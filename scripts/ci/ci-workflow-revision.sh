#!/bin/sh
# The workflow revision of a pull-request run is not its head_sha (root ADR 0472).
# Check the actual workflow marker, or the first default merge checkout of
# legacy runs. Local reusable-workflow metadata cross-checks that revision.
# Exit 2 asks the caller to supply the changes job log.
set -eu
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo 'usage: ci-workflow-revision.sh REPO RUN_JSON [CHANGES_LOG]' >&2; exit 2; }
repo=$1 metadata=$2
refs=$(jq -c --arg prefix "$repo/.github/workflows/" '[.referenced_workflows[]? | select(.path|startswith($prefix)) | .sha] | unique' "$metadata")
count=$(printf '%s' "$refs" | jq length)
[ "$count" -le 1 ] || { echo 'workflow-revision: ambiguous local reusable workflow commits' >&2; exit 1; }
[ "$#" = 3 ] || { echo 'workflow-revision: the changes job log is needed' >&2; exit 2; }
log=$3
[ -f "$log" ] || { echo 'workflow-revision: no changes job log' >&2; exit 1; }
if grep -qF 'ci-critical-path: workflow_revision=' "$log"; then
  revision=$(awk '
    {sub(/\r$/,"",$0)}
    $1=="ci-critical-path:" && NF==2 && $2 ~ /^workflow_revision=/ {sub(/^workflow_revision=/,"",$2);print $2}
    $2=="ci-critical-path:" && NF==3 && $3 ~ /^workflow_revision=/ {sub(/^workflow_revision=/,"",$3);print $3}
  ' "$log" | sort -u)
else
  grep -Eq 'git checkout.*refs/remotes/pull/[0-9]+/merge' "$log" || { echo 'workflow-revision: no workflow marker or legacy merge checkout' >&2; exit 1; }
  revision=$(awk 'nextsha {sub(/\r$/,"",$0);print $NF;exit} /\[command\].*git log -1 --format=%H$/ {nextsha=1}' "$log")
fi
if [ "$count" = 1 ] && [ "$revision" != "$(printf '%s' "$refs" | jq -r '.[0]')" ]; then
  echo 'workflow-revision: caller and local callee revisions disagree' >&2
  exit 1
fi
case "$revision" in ''|*[!0-9a-f]*) echo 'workflow-revision: invalid execution revision' >&2; exit 1 ;; esac
[ "${#revision}" = 40 ] || { echo 'workflow-revision: invalid execution revision' >&2; exit 1; }
printf '%s\n' "$revision"
