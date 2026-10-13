#!/bin/sh
# Writes the paths that a change touches, one per line
# (docs/adr/0021-docs-workflow-and-ci-gate.md).
#
#   changed-paths.sh EVENT [BASE HEAD]
#
# pull_request  the paths from the merge base of BASE and HEAD to HEAD
#               (git diff BASE...HEAD), as GitHub shows a pull request: BASE
#               is the tip of the base branch, which moves on when other pull
#               requests are merged, and the two-dot diff would count their
#               changes too
# push          the paths from BASE to HEAD (git diff BASE..HEAD)
#
# The exit code 3 means that the change has no range: another EVENT (a call
# from release.yml), or a push without BASE or that created the branch
# (BASE of zeros). The caller then builds. A failure of git is another
# nonzero exit code, and the caller builds then too.
set -eu
[ $# -ge 1 ] || {
  echo "usage: changed-paths.sh EVENT [BASE HEAD]" >&2
  exit 2
}
EVENT=$1
BASE=${2-}
HEAD=${3-}
case "$EVENT" in
  pull_request) RANGE=$BASE...$HEAD ;;
  push)
    case "$BASE" in
      *[!0]*) RANGE=$BASE..$HEAD ;;
      *) exit 3 ;;
    esac
    ;;
  *) exit 3 ;;
esac
[ -n "$BASE" ] && [ -n "$HEAD" ] || exit 3
git -c core.quotePath=false diff --name-only "$RANGE"
