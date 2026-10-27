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
# When they are those of this script, nothing is fetched. The SHA256SUMS of
# the release is not read: a list from the same release says nothing about
# an archive replaced there.
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
VERSION=0.1.0-rc3
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) TARGET=aarch64-apple-darwin; SHA=2097571f5a1ea13e5442e1f2a7907bffe94090564499ce23b20abea078ebae6f ;;
  Linux-x86_64) TARGET=x86_64-unknown-linux-musl; SHA=9a49e705b1ab31cb28f34838561b85627181d743a2f3f68b887374a217b85c1b ;;
  Linux-aarch64) TARGET=aarch64-unknown-linux-musl; SHA=c49dfe7452d5e8c11100ebdbc7be8a6aecb94dfdcea1122e3266b896b3b1efc1 ;;
  *)
    echo "fetch-shem: shem v$VERSION has no archive for $(uname -s)-$(uname -m); build the tag v$VERSION of https://github.com/tett23/shem with cargo build --release and give the path of the binary in SHEM" >&2
    exit 1
    ;;
esac
NAME=shem-v$VERSION-$TARGET
if [ "$EXPECTED_ONLY" = true ]; then printf '%s %s\n' "$NAME.tar.gz" "$SHA"; exit 0; fi
DEST=$ROOT/third_party/shem
if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$NAME.tar.gz $SHA" ]; then exit 0; fi
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

curl -fsSL --connect-timeout 30 --retry 3 -o "$TMP/archive" "https://github.com/tett23/shem/releases/download/v$VERSION/$NAME.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then ACTUAL=$(sha256sum "$TMP/archive" | cut -d' ' -f1); else ACTUAL=$(shasum -a 256 "$TMP/archive" | cut -d' ' -f1); fi
if [ "$ACTUAL" != "$SHA" ]; then echo "fetch-shem: SHA-256 mismatch for $NAME.tar.gz: $ACTUAL, expected $SHA" >&2; exit 1; fi
mkdir -p "$TMP/x"
tar -xzf "$TMP/archive" -C "$TMP/x"
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
