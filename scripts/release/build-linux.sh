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
#
# The linker writes the link map to dist/golem.map, and nm, strings -a and
# ar t of libwasmtime.a go to dist/wasmtime-{nm,strings,ar}.txt; licenses.sh
# reads them to write THIRD_PARTY_LICENSES/ (docs/adr/0007).
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
# ncurses, zlib) are linked into golem.
PACKAGES="bash binutils build-base ca-certificates curl file git gmp-dev gmp-static gzip jq libffi-dev ncurses-dev ncurses-static numactl-dev perl tar xz zlib-dev zlib-static"
# shellcheck disable=SC2086
apk add --no-cache $PACKAGES

# GHC 9.10.3 for Alpine and cabal-install 3.16.1.0 through ghcup. The
# bootstrap script of ghcup is fetched from the commit that installs
# GHCUP_VERSION and is checked by its SHA-256 before it runs; ghcup checks
# GHC and cabal by the SHA-256 of its metadata (docs/adr/0044). Update the
# three lines together when ghcup is updated.
GHCUP_VERSION=0.2.6.2
GHCUP_BOOTSTRAP_COMMIT=77e50744d3afc6d7cc090e787b9093b03405a042
GHCUP_BOOTSTRAP_SHA256=c85add4cdca779ea34bcbeeb3a311bbfed23fc96583311df41fe4e73554eba6d
BOOTSTRAP=$(mktemp)
curl --proto '=https' --tlsv1.2 -sSfL -o "$BOOTSTRAP" \
  "https://raw.githubusercontent.com/haskell/ghcup-hs/$GHCUP_BOOTSTRAP_COMMIT/scripts/bootstrap/bootstrap-haskell"
ACTUAL=$(sha256sum "$BOOTSTRAP" | cut -d' ' -f1)
[ "$ACTUAL" = "$GHCUP_BOOTSTRAP_SHA256" ] || {
  echo "build-linux: SHA-256 mismatch for the bootstrap script of ghcup: $ACTUAL" >&2
  exit 1
}
grep -qx "ghver=\"$GHCUP_VERSION\"" "$BOOTSTRAP" || {
  echo "build-linux: the bootstrap script of ghcup does not install ghcup $GHCUP_VERSION" >&2
  exit 1
}
export BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1
sh "$BOOTSTRAP"
rm -f "$BOOTSTRAP"
PATH=$HOME/.ghcup/bin:$PATH
export PATH
ghcup install ghc 9.10.3 --set
ghcup install cabal 3.16.1.0 --set

sh scripts/fetch-wasmtime.sh
# the link map of golem (docs/adr/0007), in cabal.project.local as
# fetch-wasmtime.sh writes
mkdir -p dist
printf '\n-- written by scripts/release/build-linux.sh\npackage golem-cli\n  ghc-options: -optl-Wl,-Map=%s/dist/golem.map\n' "$ROOT" >>cabal.project.local
cabal update
cabal build exe:golem --enable-executable-static
BINARY=$(cabal list-bin -v0 golem)

# the license documents of the Alpine packages linked into golem; an
# origin without a -doc package is left to licenses/alpine/ (docs/adr/0007)
for origin in $(sh "$HERE/link-components.sh" dist/golem.map --apk | cut -f1 | sort -u || true); do
  apk add --no-cache "$origin-doc" || echo "build-linux: no $origin-doc"
done

LIBWASMTIME=$ROOT/third_party/wasmtime/lib/libwasmtime.a
# nm may not read every member (bitcode) and exit with 1; the symbols of
# the other members are enough
nm "$LIBWASMTIME" >dist/wasmtime-nm.txt 2>/dev/null || true
grep -q ' _\{1,2\}R' dist/wasmtime-nm.txt || {
  echo "build-linux: nm cannot read $LIBWASMTIME" >&2
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
  echo "alpine: $(cat /etc/alpine-release) ${ALPINE_IMAGE:-unknown}"
  echo "apk info -v:"
  apk info -v 2>/dev/null | LC_ALL=C sort | sed 's/^/  /'
} >"$EXTRA"
BUILDINFO_EXTRA=$EXTRA sh "$HERE/package.sh" "$TAG" "$PLATFORM" "$BINARY" dist
rm -f "$EXTRA"
