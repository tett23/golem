#!/bin/sh
# The time of the CI of a pull request (docs/adr ADR 0392): the median of
# the times of the last 20 successful runs of ci.yml for a pull request that
# did not skip the job build.
#
#   ci-critical-path.sh [--workflow FILE]              the runs read with gh
#   ci-critical-path.sh [--workflow FILE] JOBS.json... the runs of the files
#   ci-critical-path.sh [--workflow FILE] --needs      the needs of the jobs
#
# The time of a run is the longest path through the needs of its jobs, with
# no wait for a runner in it: the seconds t(j) of a job j are from its
# started_at to its completed_at, 0 for a job that was skipped (conclusion
# skipped) and for a job not in the run, and the longest of its runners
# for a job of a matrix (the jobs named j or "j (...)"). The end of a job is
# F(j) = t(j) + the largest F of its needs (0 for none), and the time of the
# run is F(ci). The needs are read from FILE, .github/workflows/ci.yml
# unless given, as they are when this runs.
#
# A run counts unless it has jobs of build and each of them was skipped (a
# change of documents only). The median of an even number of times is the
# mean of the two in the middle. The median is the last line of stdout; the
# time of each run is on stderr.
#
# Without files, the runs are read with gh, newest first, from the API of
# GH_REPO (tett23/golem unless given); fewer than 20 runs that count fail.
# A JOBS.json is the response of the API repos/REPO/actions/runs/ID/jobs,
# its pages joined into one {"jobs": [...]}.
#
# A recorded workflow_revision uses .github/workflows at that local Git
# commit, including all local callees. Online collection records headSha.
# --graph writes the expanded graph as JSON; --needs stays unexpanded.
# --needs writes each job of FILE and its needs, "JOB: NEED NEED", one job
# a line, in the order of FILE.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
WORKFLOW=$HERE/../../.github/workflows/ci.yml
RUNS=20

usage() {
  echo "usage: ci-critical-path.sh [--workflow FILE] [--needs | --graph | JOBS.json...]" >&2
  exit 2
}

if [ "${1-}" = --workflow ]; then
  [ $# -ge 2 ] || usage
  WORKFLOW=$2
  shift 2
fi
[ -f "$WORKFLOW" ] || { echo "ci-critical-path: no workflow $WORKFLOW" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ci-critical-path: jq is needed" >&2; exit 1; }

# the needs of the jobs of the workflow, "JOB: NEED NEED", from the three
# forms of needs: a word, a list in brackets, and the lines of a list
needs() {
  awk '
    function flush() { if (job != "") print job ":" (deps == "" ? "" : " " deps) }
    function add(w) {
      gsub(/["\047[:space:]]/, "", w)
      if (w != "") deps = (deps == "" ? w : deps " " w)
    }
    { sub(/[[:space:]]+#.*$/, "") }
    /^[^[:space:]#]/ { injobs = ($0 ~ /^jobs:[[:space:]]*$/); list = 0; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      flush(); job = $0; sub(/^  /, "", job); sub(/:.*/, "", job); deps = ""; list = 0; next
    }
    /^    needs:/ {
      v = $0; sub(/^    needs:[[:space:]]*/, "", v)
      if (v == "") { list = 1; next }
      gsub(/[][]/, "", v)
      n = split(v, w, ",")
      for (i = 1; i <= n; i++) add(w[i])
      list = 0; next
    }
    list && /^      - / { v = $0; sub(/^      - /, "", v); add(v); next }
    /^    [^ ]/ { list = 0 }
    END { flush() }
  ' "$WORKFLOW"
}

if [ "${1-}" = --needs ]; then
  [ $# -eq 1 ] || usage
  needs
  exit 0
fi

# The expanded graph has zero-duration entry/exit nodes for local calls.
GRAPH=$(sh "$HERE/ci-workflow-graph.sh" "$WORKFLOW")
printf '%s\n' "$GRAPH" | jq -e 'has("ci")' >/dev/null || { echo "ci-critical-path: no job ci in $WORKFLOW" >&2; exit 1; }
if [ "${1-}" = --graph ]; then
  [ $# -eq 1 ] || usage
  printf '%s\n' "$GRAPH"
  exit 0
fi

# time FILE: the time of the run of FILE, or nothing when it skipped build
time_of() {
  revision=$(jq -r '.workflow_revision // empty' "$1")
  if [ -n "$revision" ]; then
    case "$revision" in *[!0-9a-f]*) echo "ci-critical-path: invalid workflow revision $revision" >&2; return 1 ;; esac
    [ "${#revision}" -eq 40 ] || { echo "ci-critical-path: invalid workflow revision $revision" >&2; return 1; }
    source_dir=$TMP/revisions/$revision
    if [ ! -d "$source_dir" ]; then
      mkdir -p "$source_dir"
      git -C "$HERE/../.." archive "$revision" .github/workflows >"$TMP/workflows.tar" || { echo "ci-critical-path: unreadable workflow revision $revision" >&2; return 1; }
      tar -xf "$TMP/workflows.tar" -C "$source_dir"
    fi
    GRAPH=$(sh "$HERE/ci-workflow-graph.sh" "$source_dir/.github/workflows/ci.yml") || return 1
    printf '%s\n' "$GRAPH" | jq -e 'has("ci")' >/dev/null || { echo "ci-critical-path: no job ci at $revision" >&2; return 1; }
  fi

  jq -r --argjson g "$GRAPH" '
    def base: .name | split(" / ") | (.[-1] |= sub(" \\(.*$"; "")) | join(" / ");
    def secs: if .conclusion == "skipped" then 0
              elif .status != null and .status != "completed" then error("incomplete job: " + .name)
              else (.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601) end;
    $g as $template
    | def caller($name): ($name|split(" / ")|map(sub(" \\(.*$";""))|join(" / ")+" / @entry") as $entry | $template|has($entry);
      ([.jobs[].name | split(" / ") as $parts
        | range(1; $parts|length) as $i
        | {plain:($parts[:$i]|map(sub(" \\(.*$"; ""))),real:$parts[:$i]}] | unique) as $prefixes
    | ($template | to_entries | map(
        .key as $key | ($key|split(" / ")) as $parts | $parts[:-1] as $parents
        | ($prefixes|map(select(.plain==$parents)|.real)|unique) as $matches
        | (if ($parents|length)==0 then [[]] elif ($matches|length)==0 then [$parents] else $matches end)[] as $realparents
        | {template:$key,real:($realparents+[$parts[-1]]|join(" / ")),parents:$parents,realparents:$realparents})) as $nodes
    | ($nodes|map(. as $n | {key:.real,value:[
        $template[$n.template][] as $dep | $nodes[] | select(.template==$dep) | . as $d
        | select(all(range(0;[($n.parents|length),($d.parents|length)]|min); . as $i
            | if $n.parents[:($i+1)]==$d.parents[:($i+1)] then $n.realparents[$i]==$d.realparents[$i] else true end))
        | .real]})|from_entries) as $g
    | [.jobs[] | select(.conclusion != "skipped") | base as $n | select(($g|has($n)|not) and (caller($n)|not)) | .name] as $unknown
    | if ($unknown|length)>0 then error("unmatched workflow jobs: "+($unknown|join(", "))) else . end
    | [.jobs[] | select(base == "build")] as $b
    | if ($b | length) > 0 and all($b[]; .conclusion == "skipped") then empty
      else
        (reduce .jobs[] as $j ({}; ($j | base) as $n | if caller($n) then . else .[$n] = ([.[$n] // 0, ($j | secs)] | max) end)) as $t
        | def f($j): ($t[$j] // 0) + ([($g[$j] // [])[] | f(.)] | max // 0);
          f("ci")
      end' "$1"
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ci-critical-path.XXXXXX")
trap 'rm -rf "${TMP:?}"' EXIT
: >"$TMP/times"

if [ $# -gt 0 ]; then
  for f in "$@"; do
    t=$(time_of "$f")
    [ -z "$t" ] || { printf '%s\t%s\n' "$f" "$t" >&2; printf '%s\n' "$t" >>"$TMP/times"; }
  done
  [ -s "$TMP/times" ] || { echo "ci-critical-path: no run that ran build" >&2; exit 1; }
else
  REPO=${GH_REPO:-tett23/golem}
  found=0
  LIST=$(gh run list --repo "$REPO" --workflow ci.yml --event pull_request --status success --limit 200 --json databaseId,headSha --jq '.[] | "\(.databaseId):\(.headSha)"')
  for entry in $LIST; do
    [ "$found" -lt "$RUNS" ] || break
    run=${entry%%:*}
    revision=${entry#*:}
    sh "$HERE/github-api-read.sh" --paginate "repos/$REPO/actions/runs/$run/jobs?per_page=100" |
      jq -s --arg revision "$revision" '{jobs: [.[].jobs[]],workflow_revision:$revision}' >"$TMP/$run.json"
    t=$(time_of "$TMP/$run.json")
    [ -n "$t" ] || continue
    found=$((found + 1))
    printf '%s\t%s\n' "$run" "$t" >&2
    printf '%s\n' "$t" >>"$TMP/times"
  done
  [ "$found" -eq "$RUNS" ] || { echo "ci-critical-path: only $found runs that ran build found" >&2; exit 1; }
fi

sort -n "$TMP/times" | awk '
  { v[NR] = $1 }
  END { print (NR % 2 == 1) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2 }'
