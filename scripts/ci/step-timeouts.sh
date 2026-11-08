#!/bin/sh
# Counts the conclusions of the steps "qpdf is installed" and "epubcheck is
# installed" of the runs of .github/workflows/ci.yml (docs/adr/0230), where
# the apt and the epubcheck of docs/adr/0062 time out:
#
#   step-timeouts.sh SINCE COUNT
#
# reads the runs of ci.yml created after SINCE (YYYY-MM-DDTHH:MM:SSZ, or
# YYYY-MM-DD for the start of that day), newest first, and writes one
# tab-separated row per run that ran either step, until COUNT rows:
#
#   run  created  qpdf is installed  epubcheck is installed
#
# A cell counts the conclusions of the step over the jobs of every attempt
# of the run ("failure=1 success=3"); a skipped step, or one not completed,
# is not counted, and "-" is a step that did not run. A run where neither
# step ran (build skipped, for documents only) is left out and not counted.
# A step that runs over its timeout-minutes ends with "failure".
#
# The runs are read page by page, without the filter created of the API,
# which gives at most 1000 runs, until a page ends before SINCE. GH chooses
# the gh to run (for the tests); GITHUB_REPOSITORY the repository
# (tett23/golem unless set). A gh that fails fails the script.
set -eu
usage() {
  echo "usage: step-timeouts.sh SINCE COUNT" >&2
  exit 2
}
[ $# -eq 2 ] || usage
SINCE=$1
COUNT=$2
case "$COUNT" in
  "" | *[!0-9]* | 0) usage ;;
esac
case "$SINCE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
  *) echo "step-timeouts: not a date of the API: $SINCE" >&2; usage ;;
esac
command -v jq >/dev/null 2>&1 || { echo "step-timeouts: jq is needed" >&2; exit 1; }
GH=${GH:-gh}
REPO=${GITHUB_REPOSITORY:-tett23/golem}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

# the runs, newest first, a page at a time until a page has a run created
# before SINCE or no run; the created_at of the API and SINCE compare as
# strings, and a date is before every time of that day
TAB=$(printf '\t')
: >"$TMP/all"
page=1
while :; do
  $GH api -X GET "repos/$REPO/actions/workflows/ci.yml/runs" -f per_page=100 -f "page=$page" >"$TMP/page"
  jq -r '.workflow_runs[]? | [.id, .created_at] | @tsv' "$TMP/page" >"$TMP/rows"
  [ -s "$TMP/rows" ] || break
  cat "$TMP/rows" >>"$TMP/all"
  [ -z "$(awk -F '\t' -v s="$SINCE" '$2 <= s' "$TMP/rows")" ] || break
  page=$((page + 1))
done
awk -F '\t' -v s="$SINCE" '$2 > s' "$TMP/all" | sort -u | sort -t "$TAB" -k2,2r -k1,1nr >"$TMP/list"

printf 'run\tcreated\tqpdf is installed\tepubcheck is installed\n'
n=0
while IFS="$TAB" read -r id created; do
  [ "$n" -lt "$COUNT" ] || break
  $GH api -X GET --paginate "repos/$REPO/actions/runs/$id/jobs" -f filter=all -f per_page=100 >"$TMP/jobs" </dev/null
  row=$(jq -rs '
    [.[] | .jobs[]? | .steps[]?] as $steps
    | def cell($s):
        [$steps[] | select(.name == $s and .conclusion != null and .conclusion != "skipped") | .conclusion]
        | group_by(.) | map("\(.[0])=\(length)") | join(" ")
        | if . == "" then "-" else . end;
      [cell("qpdf is installed"), cell("epubcheck is installed")] | @tsv' "$TMP/jobs")
  [ "$row" != "-$TAB-" ] || continue
  printf '%s\t%s\t%s\n' "$id" "$created" "$row"
  n=$((n + 1))
done <"$TMP/list"
