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
  status=$(gh api --paginate "repos/{owner}/{repo}/actions/runs/$RUN/attempts/$ATTEMPT/jobs" --jq ".jobs[] | select(.name == \"$JOB\") | .status")
  case "$status" in
    "")
      echo "wait-pdfs: the attempt $ATTEMPT of the run $RUN has no job '$JOB'" >&2
      exit 1
      ;;
    completed)
      # the artifact is uploaded before the job completes; ask once more
      n=$(gh api "repos/{owner}/{repo}/actions/runs/$RUN/artifacts?name=visual-pdfs" --jq '[.artifacts[] | select(.expired | not)] | length')
      if [ "$n" -gt 0 ]; then exit 0; fi
      echo "wait-pdfs: '$JOB' completed without uploading visual-pdfs" >&2
      exit 1
      ;;
  esac
  sleep "$INTERVAL"
done
