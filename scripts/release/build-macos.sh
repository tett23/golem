#!/bin/sh
# Builds golem for macOS (arm64, macOS 14 or later) and makes the release
# archive in dist/ (docs/adr/0004-binary-distribution-and-release.md).
# GHC 9.10.3 and cabal-install 3.16.1.0 must be on PATH.
#
#   build-macos.sh TAG PLATFORM
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
cabal build exe:golem
BINARY=$(cabal list-bin -v0 golem)

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
