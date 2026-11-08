#!/bin/sh
# Downloads the deno of x86-64 Linux from the GitHub release of
# denoland/deno into third_party/deno, pinned by its version and the
# SHA-256 of its zip (docs/adr/0234 section 5). .github/workflows/browser.yml
# runs golem.wasm under it (scripts/wasm/compare.sh --deno); golem does not
# use it. Deno is under the MIT License.
#
#   fetch-deno.sh             fetch, or use third_party/deno
#   fetch-deno.sh --expected  print the VERSION line it expects
#
# third_party/deno/VERSION holds the version and the SHA-256 of the zip.
# When they are those of this script, nothing is fetched. The zip is checked
# against the SHA-256 below, not against the .sha256sum of the release: a
# file of the same release says nothing about a zip replaced there.
#
# To raise the version, change VERSION and SHA256 (computed from the
# downloaded zip, and checked against its .sha256sum of the release) in one
# pull request.
set -eu
EXPECTED_ONLY=false
case ${1:-} in
  --expected) EXPECTED_ONLY=true ;;
  "") ;;
  *) echo "usage: fetch-deno.sh [--expected]" >&2; exit 2 ;;
esac
VERSION=2.9.8
SHA256=e890975bc2549807bbcc0b584ffafda72cc7c93349dd99c80483dd784f6c4609
if [ "$EXPECTED_ONLY" = true ]; then printf '%s %s\n' "$VERSION" "$SHA256"; exit 0; fi
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) echo "fetch-deno: the pinned deno is that of x86-64 Linux; this is $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEST=$ROOT/third_party/deno
if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$VERSION $SHA256" ]; then exit 0; fi
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

curl -fsSL --connect-timeout 30 --retry 3 -o "$TMP/zip" "https://github.com/denoland/deno/releases/download/v$VERSION/deno-x86_64-unknown-linux-gnu.zip"
if command -v sha256sum >/dev/null 2>&1; then ACTUAL=$(sha256sum "$TMP/zip" | cut -d' ' -f1); else ACTUAL=$(shasum -a 256 "$TMP/zip" | cut -d' ' -f1); fi
if [ "$ACTUAL" != "$SHA256" ]; then echo "fetch-deno: SHA-256 mismatch for deno $VERSION: $ACTUAL, expected $SHA256" >&2; exit 1; fi
mkdir -p "$TMP/x"
unzip -q "$TMP/zip" -d "$TMP/x"
chmod +x "$TMP/x/deno"
GOT=$("$TMP/x/deno" --version 2>/dev/null | head -n 1 || true)
case "$GOT" in
  "deno $VERSION "*) ;;
  *) echo "fetch-deno: deno --version printed '$GOT', expected deno $VERSION" >&2; exit 1 ;;
esac
rm -rf "${DEST:?}"
mkdir -p "$DEST"
cp "$TMP/x/deno" "$DEST/deno"
echo "$VERSION $SHA256" >"$DEST/VERSION"
