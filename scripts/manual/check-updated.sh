#!/bin/sh
# Checks that a change of the specification also updates the manual
# (docs/adr/0022-manual-as-typesetting-sample.md). The pre-push hook and the
# manual job of .github/workflows/docs.yml run it.
#
#   check-updated.sh BASE HEAD
#
# It reads the paths changed from the merge base of BASE and HEAD to HEAD
# (BASE...HEAD). If docs/markup.md or docs/specifications.md changed and
# docs/manual.md did not, the exit code is 1, unless a commit of BASE..HEAD
# has the trailer "Manual: unchanged" (a change of the specification that
# does not change what the manual describes, such as a v2 item).
set -eu
[ $# -eq 2 ] || { echo "usage: check-updated.sh BASE HEAD" >&2; exit 2; }
BASE=$1
HEAD=$2
PATHS=$(git -c core.quotePath=false diff --name-only "$BASE...$HEAD")
SPEC=$(printf '%s\n' "$PATHS" | grep -xE 'docs/(markup|specifications)\.md' || true)
[ -n "$SPEC" ] || exit 0
! printf '%s\n' "$PATHS" | grep -qx 'docs/manual.md' || exit 0
if git log --format='%(trailers:key=Manual,valueonly)' "$BASE..$HEAD" | grep -qix '[[:space:]]*unchanged[[:space:]]*'; then
  exit 0
fi
{
  echo "check-updated: the specification changed, but the manual did not (docs/adr/0022):"
  printf '%s\n' "$SPEC" | sed 's/^/  /'
  echo "Update docs/manual.md and manual/ in the same pull request."
  echo "If what the manual describes does not change (an item for v2, for example),"
  echo "add the trailer below to the message of one of the commits:"
  echo
  echo "  Manual: unchanged"
} >&2
exit 1
