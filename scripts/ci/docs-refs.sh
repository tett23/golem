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
#
# A path built from parts ("docs" </> "diagnostics.md") is not one string
# to pick up: a line with the string literal "docs" must name the document
# it reads in a comment, -- docs-refs: docs/diagnostics.md, and that path is
# checked against the list. A line without one is written to stderr as
# FILE:LINE, and the exit code is 1
# (docs/adr/0069-lint-scripts-bypassed-by-plain-rewrites.md).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$HERE/../..}
LIST=$(sh "$HERE/needs-build.sh" --list)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
{
  [ ! -d "$ROOT/modules" ] || find "$ROOT/modules" -type f \( -name '*.hs' -o -name '*.cabal' \) -not -path '*/dist-newstyle/*'
  [ ! -d "$ROOT/scripts" ] || find "$ROOT/scripts" -type f -name '*.sh'
} | sort | while IFS= read -r f; do
  case "$f" in
    # the paths in the tests of the CI scripts are their inputs, not files
    # that they read
    */scripts/ci/test.sh) continue ;;
    # check-updated.sh compares the paths of a diff and reads no document;
    # the tests of the manual name their inputs (docs/adr/0022)
    */scripts/manual/check-updated.sh | */scripts/manual/test.sh) continue ;;
    # this script names the string that it looks for
    */scripts/ci/docs-refs.sh) continue ;;
  esac
  printf '%s\n' "$f"
done >"$WORK/files"

STATUS=0
# the lines that build a path from "docs" without the comment
while IFS= read -r f; do
  grep -nF '"docs"' "$f" | grep -vF 'docs-refs: docs/' | cut -d: -f1 | sed "s|^|${f#"$ROOT"/}:|" || true
done <"$WORK/files" >"$WORK/built"
if [ -s "$WORK/built" ]; then
  echo 'docs-refs: these lines build a path from "docs"; name the document on the line with a comment, -- docs-refs: docs/<path> (docs/adr/0069):' >&2
  sed 's/^/  /' "$WORK/built" >&2
  STATUS=1
fi

while IFS= read -r f; do
  grep -hoE 'docs/[A-Za-z0-9_./-]*\.(md|toml|txt|json)' "$f" || true
done <"$WORK/files" | sort -u | while IFS= read -r ref; do
  case "$ref" in
    */adr/*) continue ;;
    # golem-eval's Golem.Eval.Number cites it in a comment
    docs/markup.md) continue ;;
  esac
  printf '%s\n' "$LIST" | grep -qxF "$ref" || printf '%s\n' "$ref"
done >"$WORK/missing"
if [ -s "$WORK/missing" ]; then
  echo "docs-refs: the build reads these documents; add them to the list in scripts/ci/needs-build.sh (docs/adr/0021):" >&2
  sed 's/^/  /' "$WORK/missing" >&2
  STATUS=1
fi
exit "$STATUS"
