#!/bin/sh
# The Hackage packages that the wasm build of Golem takes patched
# (docs/adr/0202 section 2): skylighting-core-0.15 and skylighting-0.15,
# without Skylighting.Parser and Skylighting.Loader, their re-exports and
# xml-conduit, which brings network, which WASI preview 1 cannot build.
# Golem uses lookupSyntax, tokenize and defaultSyntaxMap only, which read
# no XML.
#
#   fetch-wasm-packages.sh
#
# scripts/ci/fetch-url.sh fetches each archive, with retries, into
# GOLEM_DOWNLOADS (third_party/downloads by default) and checks it against
# the SHA-256 written here; an archive there of the SHA-256 is not fetched
# again (docs/adr/0243). It is unpacked into
# third_party/wasm-packages/<package>/, which is made anew each time, and
# the patch scripts/wasm/patches/<package>.patch is applied with patch -p1.
# A mismatch or a patch that does not apply fails the script.
# cabal.project.wasm lists the two directories.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CORE_SHA=485721e90b3f5e52369a11f08994969a224c038ae4c812734233ff3b30b6fa61
SKY_SHA=2929c28a042453ee67785201dda234308ef19e068fb474cc1db69dd5f67c4dab
DEST=$ROOT/third_party/wasm-packages
DOWNLOADS=${GOLEM_DOWNLOADS:-$ROOT/third_party/downloads}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$DEST"
# one PACKAGE SHA256
one() {
  sh "$ROOT/scripts/ci/fetch-url.sh" "$DOWNLOADS/$1.tar.gz" "$2" "https://hackage.haskell.org/package/$1/$1.tar.gz"
  mkdir "$TMP/$1.x"
  tar -xzf "$DOWNLOADS/$1.tar.gz" -C "$TMP/$1.x"
  if ! (cd "$TMP/$1.x/$1" && patch -p1 -f -s <"$ROOT/scripts/wasm/patches/$1.patch"); then
    echo "the patch scripts/wasm/patches/$1.patch does not apply to $1" >&2
    exit 1
  fi
  rm -rf "${DEST:?}/$1"
  mv "$TMP/$1.x/$1" "$DEST/$1"
  echo "$1: SHA-256 $2, patched"
}
one skylighting-core-0.15 "$CORE_SHA"
one skylighting-0.15 "$SKY_SHA"
