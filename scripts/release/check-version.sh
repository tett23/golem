#!/bin/sh
# Checks the version of Golem (docs/adr/0004-binary-distribution-and-release.md).
#
#   check-version.sh        VERSION is X.Y.Z or X.Y.Z-<identifier>, and the
#                           version of every modules/*/*.cabal is its X.Y.Z
#   check-version.sh TAG    also: TAG is vX.Y.Z (a release) or
#                           vX.Y.Z-<identifier> (a prerelease), and TAG
#                           without the v is the content of VERSION
#
# Prints key=value lines (version=, prerelease=) for $GITHUB_OUTPUT.
# An error is one line on stderr and the exit code is 1.
# GOLEM_ROOT sets the root of the repository (the tests use it).
set -eu
ROOT=${GOLEM_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}

fail() {
  printf 'check-version: %s\n' "$*" >&2
  exit 1
}

# matches STRING ERE: the whole string is one line that matches
matches() {
  [ "$(printf '%s\n' "$1" | wc -l)" -eq 1 ] && printf '%s\n' "$1" | grep -Eq "$2"
}

[ -f "$ROOT/VERSION" ] || fail "no VERSION file in $ROOT"
[ "$(wc -l <"$ROOT/VERSION")" -le 1 ] || fail "VERSION must be one line"
VERSION=$(cat "$ROOT/VERSION")
matches "$VERSION" '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || fail "VERSION is not X.Y.Z or X.Y.Z-<identifier>: $VERSION"
NUMBERS=${VERSION%%-*}

FOUND=0
for cabal in "$ROOT"/modules/*/*.cabal; do
  [ -f "$cabal" ] || continue
  FOUND=1
  v=$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\)[[:space:]]*$/\1/p' "$cabal")
  [ "$v" = "$NUMBERS" ] || fail "the version of ${cabal#"$ROOT"/} is ${v:-missing}, not $NUMBERS (VERSION is $VERSION)"
done
[ "$FOUND" -eq 1 ] || fail "no cabal files in $ROOT/modules"

if [ $# -ge 1 ]; then
  TAG=$1
  if matches "$TAG" '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    PRERELEASE=false
  elif matches "$TAG" '^v[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+$'; then
    PRERELEASE=true
  else
    fail "the tag is not vX.Y.Z or vX.Y.Z-<identifier>: $TAG"
  fi
  [ "${TAG#v}" = "$VERSION" ] || fail "the tag $TAG does not match VERSION ($VERSION)"
fi

printf 'version=%s\n' "$VERSION"
if [ $# -ge 1 ]; then printf 'prerelease=%s\n' "$PRERELEASE"; fi
