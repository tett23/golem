#!/bin/sh
# Checks that every document under docs/ that the code or the scripts name is
# in the list of the documents that the build reads (needs-build.sh --list),
# so that a change of one of them does not skip the build
# (docs/adr/0021-docs-workflow-and-ci-gate.md).
#
#   docs-refs.sh [ROOT]
#
# It looks in the *.hs and *.cabal files under ROOT/modules and the *.sh
# files under ROOT/scripts. ADRs (a path with /adr/) are left out: they are
# cited in comments, and the build never reads them. A document that is not
# in the list is written to stderr, and the exit code is 1.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$HERE/../..}
LIST=$(sh "$HERE/needs-build.sh" --list)
MISSING=$(mktemp)
trap 'rm -f "$MISSING"' EXIT
{
  [ ! -d "$ROOT/modules" ] || find "$ROOT/modules" -type f \( -name '*.hs' -o -name '*.cabal' \) -not -path '*/dist-newstyle/*'
  [ ! -d "$ROOT/scripts" ] || find "$ROOT/scripts" -type f -name '*.sh'
} | sort | while IFS= read -r f; do
  case "$f" in
    # the paths in the tests of the CI scripts are their inputs, not files
    # that they read
    */scripts/ci/test.sh) continue ;;
  esac
  grep -hoE 'docs/[A-Za-z0-9_./-]*\.(md|toml|txt|json)' "$f" || true
done | sort -u | while IFS= read -r ref; do
  case "$ref" in
    */adr/*) continue ;;
    # golem-eval's Golem.Eval.Number cites it in a comment
    docs/markup.md) continue ;;
  esac
  printf '%s\n' "$LIST" | grep -qxF "$ref" || printf '%s\n' "$ref"
done >"$MISSING"
if [ -s "$MISSING" ]; then
  echo "docs-refs: the build reads these documents; add them to the list in scripts/ci/needs-build.sh (docs/adr/0021):" >&2
  sed 's/^/  /' "$MISSING" >&2
  exit 1
fi
