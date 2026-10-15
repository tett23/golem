#!/bin/sh
# Checks that a change of the specification or of the guide for
# contributors also updates a manual (docs/adr/0024-manual-audiences-and-policy.md,
# which replaces the rule of docs/adr/0022). The pre-push hook and the
# manual job of .github/workflows/docs.yml run it.
#
#   check-updated.sh BASE HEAD
#
# It reads the paths changed from the merge base of BASE and HEAD to HEAD
# (BASE...HEAD) and the messages of the commits of BASE..HEAD.
#
#   1. A change of docs/markup.md or docs/specifications.md needs a change
#      of a file under manual/ or manual-dev/.
#   2. A change of CONTRIBUTING.md or CONTRIBUTING.en.md needs a change of a
#      file under manual-dev/.
#
# A commit of BASE..HEAD with the trailer "Manual: unchanged" passes both
# rules (a change that does not change what the manuals describe, such as a
# v2 item). The specifications of the modules and the ADRs are not checked.
set -eu
[ $# -eq 2 ] || { echo "usage: check-updated.sh BASE HEAD" >&2; exit 2; }
BASE=$1
HEAD=$2
PATHS=$(git -c core.quotePath=false diff --name-only "$BASE...$HEAD")
has() { printf '%s\n' "$PATHS" | grep -qE "$1"; }
SPEC=$(printf '%s\n' "$PATHS" | grep -xE 'docs/(markup|specifications)\.md' || true)
GUIDE=$(printf '%s\n' "$PATHS" | grep -xE 'CONTRIBUTING(\.en)?\.md' || true)
RULE1=
RULE2=
if [ -n "$SPEC" ] && ! has '^manual(-dev)?/'; then RULE1=1; fi
if [ -n "$GUIDE" ] && ! has '^manual-dev/'; then RULE2=1; fi
[ -n "$RULE1$RULE2" ] || exit 0
if git log --format='%(trailers:key=Manual,valueonly)' "$BASE..$HEAD" | grep -qix '[[:space:]]*unchanged[[:space:]]*'; then
  exit 0
fi
{
  if [ -n "$RULE1" ]; then
    echo "check-updated: the specification changed, but neither manual/ nor manual-dev/ did (rule 1, docs/adr/0024):"
    printf '%s\n' "$SPEC" | sed 's/^/  /'
    echo "Update the manual that describes the change (manual/ for users, manual-dev/ for developers) in the same pull request."
  fi
  if [ -n "$RULE2" ]; then
    echo "check-updated: the guide for contributors changed, but manual-dev/ did not (rule 2, docs/adr/0024):"
    printf '%s\n' "$GUIDE" | sed 's/^/  /'
    echo "Update part 2 of the developer manual (manual-dev/) in the same pull request."
  fi
  echo "If what the manuals describe does not change (an item for v2, for example),"
  echo "add the trailer below to the message of one of the commits:"
  echo
  echo "  Manual: unchanged"
} >&2
exit 1
