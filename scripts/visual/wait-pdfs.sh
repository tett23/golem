#!/bin/sh
# Waits in the visual job of ci.yml until the job that builds the PDFs of the
# visual regression test has uploaded the artifact visual-pdfs, so that
# visual does not wait for the whole build matrix (docs/adr/0099).
#
#   wait-pdfs.sh RUN ATTEMPT JOB
#
# RUN and ATTEMPT are those of this workflow run (GITHUB_RUN_ID,
# GITHUB_RUN_ATTEMPT), JOB the name of the job that uploads visual-pdfs.
# gh reads the repository from GH_REPO and the token from GH_TOKEN. Every
# WAIT_INTERVAL seconds (10 by default) it asks for the artifact; it exits
# 0 once the run has it, and 1 when JOB is completed without it, or when
# the attempt has no job JOB. The limit of the waiting is the timeout of
# the step.
#
# The job is the one whose name is JOB or ends with " / JOB": when
# release.yml calls ci.yml from its job ci, GitHub names the jobs of ci.yml
# "ci / build (...)", and nested calls add more such prefixes
# (docs/adr/0165). A name that only ends with JOB, without " / " before it,
# is not the job. When two or more jobs match, it exits 1 with their names
# instead of choosing one.
set -eu
[ $# -eq 3 ] || { echo "usage: wait-pdfs.sh RUN ATTEMPT JOB" >&2; exit 2; }
RUN=$1 ATTEMPT=$2 JOB=$3
INTERVAL=${WAIT_INTERVAL:-10}
while :; do
  n=$(gh api "repos/{owner}/{repo}/actions/runs/$RUN/artifacts?name=visual-pdfs" --jq '[.artifacts[] | select(.expired | not)] | length')
  if [ "$n" -gt 0 ]; then
    echo "wait-pdfs: visual-pdfs is uploaded" >&2
    exit 0
  fi
  jobs=$(gh api --paginate "repos/{owner}/{repo}/actions/runs/$RUN/attempts/$ATTEMPT/jobs" --jq '.jobs[] | [.name, .status] | @tsv')
  # the lines "name<TAB>status" of the jobs that match JOB
  found=$(printf '%s\n' "$jobs" | JOB=$JOB awk -F '\t' '
    { n = $1; j = ENVIRON["JOB"]; s = " / " j }
    n == j || (length(n) > length(s) && substr(n, length(n) - length(s) + 1) == s)')
  count=$(printf '%s' "$found" | awk 'END { print NR }')
  case "$count" in
    0)
      echo "wait-pdfs: the attempt $ATTEMPT of the run $RUN has no job '$JOB'" >&2
      exit 1
      ;;
    1) ;;
    *)
      echo "wait-pdfs: the attempt $ATTEMPT of the run $RUN has $count jobs that match '$JOB':" >&2
      printf '%s\n' "$found" | cut -f 1 | sed 's/^/  /' >&2
      exit 1
      ;;
  esac
  name=$(printf '%s\n' "$found" | cut -f 1)
  status=$(printf '%s\n' "$found" | cut -f 2)
  if [ "$status" = completed ]; then
    # the artifact is uploaded before the job completes; ask once more
    n=$(gh api "repos/{owner}/{repo}/actions/runs/$RUN/artifacts?name=visual-pdfs" --jq '[.artifacts[] | select(.expired | not)] | length')
    if [ "$n" -gt 0 ]; then exit 0; fi
    echo "wait-pdfs: '$name' completed without uploading visual-pdfs" >&2
    exit 1
  fi
  sleep "$INTERVAL"
done
