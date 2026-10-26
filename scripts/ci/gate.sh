#!/bin/sh
# The result of the jobs of ci.yml, for the job ci, which is the one check of
# ci.yml that the protection of main requires
# (docs/adr/0021-docs-workflow-and-ci-gate.md).
#
#   gate.sh < needs.json    the needs context (toJSON(needs)) of the job ci
#   gate.sh --names         the jobs that the job ci needs
#
# Every job must be in the JSON with the result success or skipped (a change
# of documents only skips the build). A failure, a cancellation or a job
# missing from the JSON is written to stderr, and the exit code is 1. Add a
# new job of ci.yml both to the needs of the job ci and to NAMES.
set -eu
NAMES="changes scripts-linux build determinism visual release-scripts scripts-macos format"
if [ "${1-}" = --names ]; then
  printf '%s\n' $NAMES
  exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "gate.sh needs jq" >&2; exit 1; }
JSON=$(cat)
printf '%s\n' "$JSON" | jq -e 'type == "object"' >/dev/null 2>&1 || {
  echo "gate: the needs context is not a JSON object" >&2
  exit 1
}
BAD=
for n in $NAMES; do
  r=$(printf '%s\n' "$JSON" | jq -r --arg n "$n" '.[$n].result // "missing"')
  case "$r" in
    success | skipped) ;;
    *)
      echo "gate: $n: $r" >&2
      BAD=1
      ;;
  esac
done
[ -z "$BAD" ]
