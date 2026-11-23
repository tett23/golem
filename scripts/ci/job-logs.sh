#!/bin/sh
# The warnings of the logs of the jobs of a run of CI that the list of
# allowed warnings does not allow (docs/adr/0245 section 6,
# docs/adr/0427-warning-gate-and-jobs-without-logs.md). The last step of the
# ci job of ci.yml runs it.
#
#   job-logs.sh ALLOWED JOBS DIR
#
# JOBS has the jobs of the attempt of the run as JSON objects, one after
# another, as gh api --paginate ... --jq '.jobs[]' writes them, each with
# id, name, status, conclusion and steps. The jobs read are those whose
# status is completed, whose conclusion is not skipped, and that were not
# cancelled before any step ran: such a job ran nothing, and the logs API of
# GitHub answers 404 for it. The jobs left out as cancelled with no step and
# the jobs read are written to stdout as ID<tab>NAME. ci itself is still
# running, so it is not read.
#
# The log of each job read is fetched with curl from the API of
# $GITHUB_API_URL for $GITHUB_REPOSITORY with $GH_TOKEN into DIR/ID.log.
# When a log cannot be fetched, the job is written to stderr and the logs
# after it are still fetched, so that their warnings are reported. Then
# log-warnings.sh ALLOWED checks the logs fetched, writing the warnings not
# allowed to stdout.
#
# The exit code is 0 when there is a job to read, every log was fetched and
# no warning is left that ALLOWED does not allow; 1 when there is no job to
# read, a log cannot be fetched, or a warning is not allowed; 2 for a usage
# error and a JOBS jq cannot read; and the exit code of log-warnings.sh when
# it is 2 or more.
set -u
usage() { echo "usage: job-logs.sh ALLOWED JOBS DIR" >&2; exit 2; }
[ $# -eq 3 ] || usage
ALLOWED=$1 JOBS=$2 DIR=$3
[ -f "$JOBS" ] || { echo "job-logs.sh: no such file: $JOBS" >&2; exit 2; }
[ -d "$DIR" ] || { echo "job-logs.sh: no such directory: $DIR" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

# the jobs that ended, but those skipped, as ID<tab>NAME<tab>LEFT, LEFT
# being 1 for a job cancelled before any step ran
if ! jq -r 'select(.status == "completed" and .conclusion != "skipped")
    | [.id, .name, (if .conclusion == "cancelled" and ((.steps // []) | length) == 0 then 1 else 0 end)]
    | @tsv' "$JOBS" >"$WORK/ended"; then
  echo "job-logs.sh: jq cannot read the jobs of $JOBS" >&2
  exit 2
fi
TAB=$(printf '\t')
awk -F "$TAB" -v OFS="$TAB" '$3 == 1 { print $1, $2 }' "$WORK/ended" >"$WORK/left"
awk -F "$TAB" -v OFS="$TAB" '$3 == 0 { print $1, $2 }' "$WORK/ended" >"$WORK/read"
if [ -s "$WORK/left" ]; then
  echo "the jobs cancelled before any step ran, which have no log, are not read:"
  cat "$WORK/left"
fi
if [ ! -s "$WORK/read" ]; then
  echo "job-logs.sh: no job of the run to read the log of" >&2
  exit 1
fi
echo "the jobs read:"
cat "$WORK/read"

missing=0
set --
while IFS="$TAB" read -r id name; do
  if curl -fsSL --retry 5 --retry-all-errors -H "Authorization: Bearer ${GH_TOKEN:-}" \
    "${GITHUB_API_URL:-}/repos/${GITHUB_REPOSITORY:-}/actions/jobs/$id/logs" -o "$DIR/$id.log"; then
    set -- "$@" "$DIR/$id.log"
  else
    echo "job-logs.sh: the log of the job $id ($name) cannot be fetched" >&2
    rm -f "$DIR/$id.log"
    missing=$((missing + 1))
  fi
done <"$WORK/read"

code=0
if [ $# -gt 0 ]; then
  sh "$HERE/log-warnings.sh" "$ALLOWED" "$@" || code=$?
fi
if [ "$code" -gt 1 ]; then exit "$code"; fi
if [ "$missing" -gt 0 ]; then
  echo "job-logs.sh: $missing log(s) cannot be fetched" >&2
  exit 1
fi
exit "$code"
