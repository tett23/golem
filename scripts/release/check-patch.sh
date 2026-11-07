#!/bin/sh
# Checks that a patch release does not change the output
# (docs/adr/0174-compatibility-promises-for-1-0.md, docs/compatibility.md).
#
#   check-patch.sh TAG
#
# The release before TAG is the latest tag v* that the commit of TAG
# reaches, TAG left out. When it is v1.0.0 or later (a prerelease of 1.0.0
# comes before it) and TAG has its X and Y (TAG is a patch of it), the
# check compares the two commits:
#
#   - the references of the visual regression test, scripts/visual/pages/,
#     are the same (docs/adr/0094);
#   - when both have the list of output hashes,
#     scripts/determinism/hashes.txt (docs/adr/0173), the lists are the
#     same but the lines of PDF files: the Producer and the instance ID of
#     a PDF hold the version of Golem.
#
# Otherwise the check passes without comparing. What differs goes to
# stderr, and the exit code is 1; a missing TAG is exit code 2.
#
# GOLEM_ROOT sets the root of the repository (the tests use it).
set -u
ROOT=${GOLEM_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT" || exit 2

PAGES=scripts/visual/pages
HASHES=scripts/determinism/hashes.txt

[ $# -eq 1 ] || {
  echo "usage: check-patch.sh TAG" >&2
  exit 2
}
TAG=$1
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || {
  printf 'check-patch: no tag %s\n' "$TAG" >&2
  exit 2
}

if ! PREV=$(git describe --tags --abbrev=0 --match 'v*' --exclude "$TAG" "$TAG" 2>/dev/null); then
  echo "check-patch: no release before $TAG; the output is not compared"
  exit 0
fi

# since_1 TAG: the tag vX.Y.Z[-PRE] is v1.0.0 or later
since_1() {
  v=${1#v}
  core=${v%%-*}
  x=${core%%.*}
  case $x in '' | *[!0-9]*) return 1 ;; esac
  [ "$x" -ge 1 ] || return 1
  [ "$core" != 1.0.0 ] || [ "$v" = "$core" ]
}
# xy TAG: X.Y of vX.Y.Z[-PRE]
xy() {
  core=${1#v}
  core=${core%%-*}
  printf '%s' "${core%.*}"
}

if ! since_1 "$PREV"; then
  echo "check-patch: the release $PREV comes before v1.0.0; the output is not compared"
  exit 0
fi
if [ "$(xy "$TAG")" != "$(xy "$PREV")" ]; then
  echo "check-patch: $TAG is not a patch of $PREV; the output is not compared"
  exit 0
fi

STATUS=0
CHANGED=$(git diff --name-only "$PREV" "$TAG" -- "$PAGES") || exit 2
if [ -n "$CHANGED" ]; then
  printf 'check-patch: %s is a patch of %s, and a patch version does not change the output; these pages of the visual regression test differ:\n' "$TAG" "$PREV" >&2
  printf '%s\n' "$CHANGED" | sed 's/^/  /' >&2
  STATUS=1
fi

T=$(mktemp -d)
trap 'rm -rf "${T:?}"' EXIT
if git cat-file -e "$PREV:$HASHES" 2>/dev/null && git cat-file -e "$TAG:$HASHES" 2>/dev/null; then
  git show "$PREV:$HASHES" | grep -v '\.pdf$' >"$T/old"
  git show "$TAG:$HASHES" | grep -v '\.pdf$' >"$T/new"
  if ! cmp -s "$T/old" "$T/new"; then
    printf 'check-patch: %s is a patch of %s, and a patch version does not change the output; these lines of %s differ (- %s, + %s):\n' "$TAG" "$PREV" "$HASHES" "$PREV" "$TAG" >&2
    diff "$T/old" "$T/new" | grep '^[<>]' | sed 's/^</  -/; s/^>/  +/' >&2
    STATUS=1
  fi
fi

[ "$STATUS" -ne 0 ] || echo "check-patch: $TAG is a patch of $PREV with the same output"
exit "$STATUS"
