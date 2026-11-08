#!/bin/sh
# Downloads shem, the rasterizer of the visual regression test, from its
# GitHub release into third_party/shem, pinned by its version and the
# SHA-256 of each archive (docs/adr/0093). shem is used by the tests and CI
# only; golem does not link it.
#
#   fetch-shem.sh             fetch, or use third_party/shem
#   fetch-shem.sh --expected  print the VERSION line it expects
#
# third_party/shem/VERSION holds the name of the archive and its SHA-256.
# When they are those of this script, nothing is fetched. The archive is
# kept in GOLEM_DOWNLOADS (third_party/downloads by default), which CI
# caches; scripts/ci/fetch-url.sh fetches it, with retries, only when the
# archive there is not of the SHA-256 below (docs/adr/0243). The
# SHA256SUMS of the release is not read: a list from the same release says
# nothing about an archive replaced there.
#
# A platform without an archive of shem (x86-64 macOS, Windows) fails: build
# the pinned tag of shem yourself and give its path in SHEM to the scripts
# of the visual regression test.
#
# To raise the version, change VERSION and the three SHA-256 below, each
# computed from the downloaded archive and checked against the SHA256SUMS of
# the release (docs/adr/0093). A change of the pre-release identifier is
# handled as in docs/adr/0100: render the PDFs with both versions and list
# the pages whose SHA-256 differ in the pull request.
set -eu
EXPECTED_ONLY=false
case ${1:-} in
  --expected) EXPECTED_ONLY=true ;;
  "") ;;
  *) echo "usage: fetch-shem.sh [--expected]" >&2; exit 2 ;;
esac
VERSION=0.1.0-rc4
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) TARGET=aarch64-apple-darwin; SHA=bf60ddf8db44c6a28955f05b53aa3e7d5c5a62e2b6cbe4138df5ed9211546d99 ;;
  Linux-x86_64) TARGET=x86_64-unknown-linux-musl; SHA=5337e1fb4dc5e336f4f84cd051f392c949ef34df1e2edb5159532f941367c0d9 ;;
  Linux-aarch64) TARGET=aarch64-unknown-linux-musl; SHA=ba5e0e5b80bf00fbb3bbc0aefa62178c92d7ce4171b3a101e5700820c5592a08 ;;
  *)
    echo "fetch-shem: shem v$VERSION has no archive for $(uname -s)-$(uname -m); build the tag v$VERSION of https://github.com/tett23/shem with cargo build --release and give the path of the binary in SHEM" >&2
    exit 1
    ;;
esac
NAME=shem-v$VERSION-$TARGET
if [ "$EXPECTED_ONLY" = true ]; then printf '%s %s\n' "$NAME.tar.gz" "$SHA"; exit 0; fi
DEST=$ROOT/third_party/shem
if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$NAME.tar.gz $SHA" ]; then exit 0; fi
ARCHIVE=${GOLEM_DOWNLOADS:-$ROOT/third_party/downloads}/$NAME.tar.gz
sh "$ROOT/scripts/ci/fetch-url.sh" "$ARCHIVE" "$SHA" "https://github.com/tett23/shem/releases/download/v$VERSION/$NAME.tar.gz"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/x"
tar -xzf "$ARCHIVE" -C "$TMP/x"
if [ ! -f "$TMP/x/$NAME/shem" ]; then echo "fetch-shem: $NAME.tar.gz has no $NAME/shem" >&2; exit 1; fi
chmod +x "$TMP/x/$NAME/shem"
# the version is checked before anything is installed
GOT=$("$TMP/x/$NAME/shem" --version 2>/dev/null || true)
if [ "$GOT" != "shem $VERSION" ]; then echo "fetch-shem: $NAME/shem --version printed '$GOT', expected 'shem $VERSION'" >&2; exit 1; fi
rm -rf "${DEST:?}"
mkdir -p "$DEST"
cp "$TMP/x/$NAME/shem" "$DEST/shem"
[ ! -f "$TMP/x/$NAME/LICENSE" ] || cp "$TMP/x/$NAME/LICENSE" "$DEST/LICENSE"
echo "$NAME.tar.gz $SHA" >"$DEST/VERSION"
