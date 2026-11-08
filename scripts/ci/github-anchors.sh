#!/bin/sh
# Checks that every diagnostic code of docs/diagnostics.md has its anchor in
# the HTML that GitHub renders of the file (docs/adr/0235), the anchor that
# the URL of golem explain points to
# (https://github.com/tett23/golem/blob/main/docs/diagnostics.md#g01017):
#
#   github-anchors.sh COMMIT
#
# fetches docs/diagnostics.md of COMMIT rendered by the API of GitHub
# (Accept: application/vnd.github.html) and, for each heading "## G<digits>"
# of docs/diagnostics.md of the working tree, looks for
# id="user-content-g<digits>" in it. A heading of another level, or with
# more than the code ("## G01017（説明）"), is not a code. The codes without
# their id are written on stderr, and the exit code is 1: a file over the
# size that GitHub renders has no id at all.
#
# A commit the API does not give (a pull request from a fork) fails, unless
# GITHUB_ANCHORS_SKIP_UNREACHABLE=1: then the check is skipped, said on
# stdout, and the push to main checks it. GH chooses the gh to run (for the
# tests), GITHUB_REPOSITORY the repository (tett23/golem unless set), and
# GOLEM_ROOT the root with docs/diagnostics.md (this repository unless set).
set -eu
[ $# -eq 1 ] || {
  echo "usage: github-anchors.sh COMMIT" >&2
  exit 2
}
COMMIT=$1
case "$COMMIT" in
  "" | *[!0-9a-f]*) echo "github-anchors: not a commit: $COMMIT" >&2; exit 2 ;;
esac
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${GOLEM_ROOT:-$(cd "$HERE/../.." && pwd)}
MD=$ROOT/docs/diagnostics.md
[ -f "$MD" ] || { echo "github-anchors: no $MD" >&2; exit 1; }
GH=${GH:-gh}
REPO=${GITHUB_REPOSITORY:-tett23/golem}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

if ! $GH api "repos/$REPO/contents/docs/diagnostics.md?ref=$COMMIT" -H 'Accept: application/vnd.github.html' >"$TMP/html"; then
  if [ "${GITHUB_ANCHORS_SKIP_UNREACHABLE-}" = 1 ]; then
    echo "github-anchors: skipped: the API does not give docs/diagnostics.md of $COMMIT (a pull request from a fork); the push to main checks it"
    exit 0
  fi
  echo "github-anchors: cannot fetch docs/diagnostics.md of $COMMIT rendered by GitHub" >&2
  exit 1
fi

sed -n 's/^## \(G[0-9][0-9]*\)$/\1/p' "$MD" >"$TMP/codes"
[ -s "$TMP/codes" ] || { echo "github-anchors: no heading of a code in $MD" >&2; exit 1; }
MISSING=0
while IFS= read -r code; do
  lower=$(printf '%s' "$code" | tr 'G' 'g')
  if ! grep -qF "id=\"user-content-$lower\"" "$TMP/html"; then
    echo "github-anchors: no id=\"user-content-$lower\" for $code in the HTML of GitHub" >&2
    MISSING=$((MISSING + 1))
  fi
done <"$TMP/codes"
[ "$MISSING" -eq 0 ] || exit 1
echo "github-anchors: $(wc -l <"$TMP/codes" | tr -d ' ') codes, each with its id in the HTML of GitHub"
