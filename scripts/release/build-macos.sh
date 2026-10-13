#!/bin/sh
# Builds golem for macOS (arm64, macOS 14 or later) and makes the release
# archive in dist/ (docs/adr/0004-binary-distribution-and-release.md).
# GHC 9.10.3 and cabal-install 3.16.1.0 must be on PATH.
#
#   build-macos.sh TAG PLATFORM
#
# The linker writes the link map to dist/golem.map, and nm, strings -a and
# ar t of libwasmtime.a go to dist/wasmtime-{nm,strings,ar}.txt; licenses.sh
# reads them to write THIRD_PARTY_LICENSES/ (docs/adr/0007).
set -eu
[ $# -eq 2 ] || {
  echo "usage: build-macos.sh TAG PLATFORM" >&2
  exit 2
}
TAG=$1
PLATFORM=$2
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
cd "$ROOT"

MACOSX_DEPLOYMENT_TARGET=14.0
export MACOSX_DEPLOYMENT_TARGET
sh scripts/fetch-wasmtime.sh
# the link map of golem (docs/adr/0007), in cabal.project.local as
# fetch-wasmtime.sh writes
mkdir -p dist
printf '\n-- written by scripts/release/build-macos.sh\npackage golem-cli\n  ghc-options: -optl-Wl,-map,%s/dist/golem.map\n' "$ROOT" >>cabal.project.local
cabal build exe:golem
BINARY=$(cabal list-bin -v0 golem)

# nm, strings -a and ar t of libwasmtime.a, for licenses.sh (docs/adr/0007)
LIBWASMTIME=$ROOT/third_party/wasmtime/lib/libwasmtime.a
# nm of Xcode cannot read the bitcode of some members and exits with 1;
# the symbols of the other members are enough
nm "$LIBWASMTIME" >dist/wasmtime-nm.txt 2>/dev/null || true
grep -q ' _\{1,2\}R' dist/wasmtime-nm.txt || {
  echo "build-macos: nm cannot read $LIBWASMTIME" >&2
  exit 1
}
strings -a "$LIBWASMTIME" >dist/wasmtime-strings.txt
ar t "$LIBWASMTIME" >dist/wasmtime-ar.txt
LINK_MAP=$ROOT/dist/golem.map
WASMTIME_NM=$ROOT/dist/wasmtime-nm.txt
WASMTIME_STRINGS=$ROOT/dist/wasmtime-strings.txt
WASMTIME_AR=$ROOT/dist/wasmtime-ar.txt
export LINK_MAP WASMTIME_NM WASMTIME_STRINGS WASMTIME_AR

GMP_VERSION=$(sh "$HERE/gmp-version.sh")
export GMP_VERSION
sh "$HERE/fetch-gmp.sh" "$GMP_VERSION" dist
GMP_SOURCE=$ROOT/dist/gmp-$GMP_VERSION.tar.xz
export GMP_SOURCE

EXTRA=$(mktemp)
{
  echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "MACOSX_DEPLOYMENT_TARGET: $MACOSX_DEPLOYMENT_TARGET"
  echo "clang: $(cc --version | head -1)"
} >"$EXTRA"
BUILDINFO_EXTRA=$EXTRA sh "$HERE/package.sh" "$TAG" "$PLATFORM" "$BINARY" dist
rm -f "$EXTRA"
