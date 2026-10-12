#!/bin/sh
# Builds golem for Linux, linked fully statically against musl, in an
# Alpine container, and makes the release archive in dist/
# (docs/adr/0004-binary-distribution-and-release.md).
# .github/workflows/release.yml runs it with docker run, the repository
# mounted at /src:
#
#   build-linux.sh TAG PLATFORM
#
# Environment: COMMIT (the commit of the build), ALPINE_IMAGE (the image
# with its digest, for BUILDINFO), ImageOS and ImageVersion (the runner).
set -eu
[ $# -eq 2 ] || {
  echo "usage: build-linux.sh TAG PLATFORM" >&2
  exit 2
}
TAG=$1
PLATFORM=$2
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
cd "$ROOT"
[ -f /etc/alpine-release ] || {
  echo "build-linux: run this in an Alpine container" >&2
  exit 1
}

# The packages of the build. The static libraries (GMP, libffi, libstdc++,
# ncurses, zlib) are linked into golem; git, cargo, rust and cmake build
# the wasmtime C API for musl (scripts/fetch-wasmtime.sh).
PACKAGES="bash binutils build-base ca-certificates cargo cmake curl file git gmp-dev gzip jq libffi-dev ncurses-dev ncurses-static numactl-dev perl rust tar xz zlib-dev zlib-static"
# shellcheck disable=SC2086
apk add --no-cache $PACKAGES

# GHC 9.10.3 for Alpine and cabal-install 3.16.1.0 through ghcup
export BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
PATH=$HOME/.ghcup/bin:$PATH
export PATH
ghcup install ghc 9.10.3 --set
ghcup install cabal 3.16.1.0 --set

sh scripts/fetch-wasmtime.sh
cabal update
cabal build exe:golem --enable-executable-static
BINARY=$(cabal list-bin -v0 golem)

GMP_VERSION=$(sh "$HERE/gmp-version.sh")
export GMP_VERSION
sh "$HERE/fetch-gmp.sh" "$GMP_VERSION" dist
GMP_SOURCE=$ROOT/dist/gmp-$GMP_VERSION.tar.xz
export GMP_SOURCE

EXTRA=$(mktemp)
{
  echo "alpine: $(cat /etc/alpine-release) ${ALPINE_IMAGE:-unknown}"
  echo "apk info -v:"
  apk info -v 2>/dev/null | LC_ALL=C sort | sed 's/^/  /'
} >"$EXTRA"
BUILDINFO_EXTRA=$EXTRA sh "$HERE/package.sh" "$TAG" "$PLATFORM" "$BINARY" dist
rm -f "$EXTRA"
