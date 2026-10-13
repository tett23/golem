#!/bin/sh
# Writes the time of each job and step of CI runs as a Markdown table
# (docs/adr/0009-ci-speed.md).
#
#   gh run view <id> --json jobs | scripts/ci/timings.sh
#   for id in ...; do gh run view "$id" --json jobs -q .; done | scripts/ci/timings.sh --median
#
# Without an option, the input is the JSON of one run, and each row is the
# seconds from startedAt to completedAt of a job ("ジョブ全体") or a step.
# With --median, the input is the JSON of one run per line, and each row is
# the minimum, the median and the maximum over the runs. The median of an
# even number of values is the mean of the two in the middle. A step that
# has not started or completed (startedAt or completedAt is
# 0001-01-01T00:00:00Z, as for a cancelled step) has no time: it is written
# "-" and left out of the minimum, the median and the maximum, and so is a
# skipped job or step (conclusion "skipped").
set -eu
case "${1-}" in
  "") MODE=run ;;
  --median) MODE=median ;;
  *) echo "usage: $0 [--median] < runs.json" >&2; exit 2 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "timings.sh needs jq" >&2; exit 1; }
jq -rs --arg mode "$MODE" '
  def unset: . == null or startswith("0001-");
  def secs:
    if .conclusion == "skipped" or (.startedAt | unset) or (.completedAt | unset) then null
    else (.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601) end;
  def cell: gsub("\\|"; "\\|");
  # names of jobs and steps are inline code: they are copied from the
  # workflow, and ADR references in them are not links (adr-guard)
  def code: "`" + cell + "`";
  def stepcell: if . == "ジョブ全体" then . else code end;
  def show: if . == null then "-" else tostring end;
  def rows:
    .jobs[] as $j
    | [$j.name, "ジョブ全体", ($j | secs)],
      ($j.steps // [] | sort_by(.number)[] | [$j.name, .name, secs]);
  def median:
    length as $n
    | if $n == 0 then null
      elif $n % 2 == 1 then .[($n - 1) / 2]
      else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
  if $mode == "run" then
    "| ジョブ | ステップ | 秒 |",
    "|---|---|---|",
    (.[0] | rows | "| \(.[0] | code) | \(.[1] | stepcell) | \(.[2] | show) |")
  else
    "| ジョブ | ステップ | 最小 | 中央値 | 最大 |",
    "|---|---|---|---|---|",
    (reduce (.[] | rows) as $r ({keys: [], vals: {}};
        ($r[0:2] | tojson) as $k
        | (if .vals | has($k) then . else .keys += [$k] end)
        | .vals[$k] += (if $r[2] == null then [] else [$r[2]] end))
      | .vals as $vals
      | .keys[] as $k
      | ($k | fromjson) as [$job, $step]
      | ($vals[$k] | sort) as $v
      | "| \($job | code) | \($step | stepcell) | \($v | first | show) | \($v | median | show) | \($v | last | show) |")
  end
'
