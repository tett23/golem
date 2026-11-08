#!/bin/sh
# Downloads Neovim, the editor of the tests tools/editors/nvim/test.sh, from
# its GitHub release into third_party/nvim, pinned by its version and the
# SHA-256 of each archive (docs/adr/0231). Neovim is used by the tests and
# CI only.
#
#   fetch-nvim.sh    fetch, or use third_party/nvim; prints the path of nvim
#
# third_party/nvim/VERSION holds the name of the archive and its SHA-256.
# When they are those of this script, nothing is fetched. The checksums of
# the release are not read: a list from the same release says nothing about
# an archive replaced there (as in scripts/visual/fetch-shem.sh).
#
# The archives are pinned for x86-64 Linux and arm64 macOS; another platform
# fails: give the path of a Neovim of your own in NVIM to the tests.
#
# To raise the version, change VERSION and the two SHA-256 below, each
# computed from the downloaded archive, and the version in
# tools/editors/README.md that the examples were checked with
# (docs/adr/0231).
set -eu
[ $# -eq 0 ] || { echo "usage: fetch-nvim.sh" >&2; exit 2; }
VERSION=0.12.6
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) NAME=nvim-linux-x86_64; SHA=474430d53e6264f6d6dd18db42d6dc9df3a1b56ca9e88a325bbf860e1a811d87 ;;
  Darwin-arm64) NAME=nvim-macos-arm64; SHA=1dbd148222b051ba6c307c4d17a318ed083df018a4f6a5a0ce46955ffc9ab87b ;;
  *)
    echo "fetch-nvim: no pinned archive of Neovim v$VERSION for $(uname -s)-$(uname -m); give the path of nvim in NVIM" >&2
    exit 1
    ;;
esac
DEST=$ROOT/third_party/nvim
if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$NAME.tar.gz $SHA" ] && [ -x "$DEST/bin/nvim" ]; then
  echo "$DEST/bin/nvim"
  exit 0
fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/golem-fetch-nvim.XXXXXX")
# removes only the directories of this script
remove() {
  case "$1" in
    */golem-fetch-nvim.* | */third_party/nvim) [ ! -e "$1" ] || find "$1" -depth -delete ;;
  esac
}
trap 'remove "$TMP"' EXIT

curl -fsSL --connect-timeout 30 --retry 3 -o "$TMP/archive" "https://github.com/neovim/neovim/releases/download/v$VERSION/$NAME.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then ACTUAL=$(sha256sum "$TMP/archive" | cut -d' ' -f1); else ACTUAL=$(shasum -a 256 "$TMP/archive" | cut -d' ' -f1); fi
if [ "$ACTUAL" != "$SHA" ]; then echo "fetch-nvim: SHA-256 mismatch for $NAME.tar.gz: $ACTUAL, expected $SHA" >&2; exit 1; fi
mkdir -p "$TMP/x"
tar -xzf "$TMP/archive" -C "$TMP/x"
if [ ! -x "$TMP/x/$NAME/bin/nvim" ]; then echo "fetch-nvim: $NAME.tar.gz has no $NAME/bin/nvim" >&2; exit 1; fi
# the version is checked before anything is installed
GOT=$("$TMP/x/$NAME/bin/nvim" --version 2>/dev/null | head -n 1 || true)
if [ "$GOT" != "NVIM v$VERSION" ]; then echo "fetch-nvim: $NAME/bin/nvim --version printed '$GOT', expected 'NVIM v$VERSION'" >&2; exit 1; fi
remove "$DEST"
mkdir -p "$ROOT/third_party"
mv "$TMP/x/$NAME" "$DEST"
echo "$NAME.tar.gz $SHA" >"$DEST/VERSION"
echo "$DEST/bin/nvim"
