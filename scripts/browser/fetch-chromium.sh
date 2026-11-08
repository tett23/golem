#!/bin/sh
# Downloads chrome-headless-shell of Chrome for Testing for x86-64 Linux into
# third_party/chromium, pinned by its version and the SHA-256 of its zip
# (docs/adr/0234 section 1). The checks of HTML and golem.wasm in
# .github/workflows/browser.yml drive it; golem does not use it.
#
#   fetch-chromium.sh             fetch, or use third_party/chromium
#   fetch-chromium.sh --expected  print the VERSION line it expects
#
# third_party/chromium/VERSION holds the version and the SHA-256 of the
# zip. When they are those of this script, nothing is fetched. The zip is
# kept in GOLEM_DOWNLOADS (third_party/downloads by default), which
# browser.yml caches; scripts/ci/fetch-url.sh fetches it, with retries,
# only when the zip there is not of the SHA-256 below (docs/adr/0243). The
# zip is checked against the SHA-256 below before anything is unpacked;
# Chrome for Testing publishes no checksum, so the SHA-256 is that of the
# zip of the version when it was pinned, and a zip replaced at the same URL
# fails.
#
# Chrome for Testing is "Google Chrome for Testing" under the Google Chrome
# Terms of Service (the ABOUT of the zip; its LICENSE.headless_shell lists
# the licences of Chromium and its parts). It is fetched from Google and
# not distributed with Golem.
#
# To raise the version, change VERSION and SHA256 to those of a version of
# https://googlechromelabs.github.io/chrome-for-testing/ (the SHA-256 is
# computed from the downloaded zip) in one pull request, and check that the
# checks of browser.yml pass with it (docs/adr/0234 section 1).
set -eu
EXPECTED_ONLY=false
case ${1:-} in
  --expected) EXPECTED_ONLY=true ;;
  "") ;;
  *) echo "usage: fetch-chromium.sh [--expected]" >&2; exit 2 ;;
esac
VERSION=157.0.8103.38
SHA256=deafffa74660b34853a4119c361fd427ac8c9fcb62db51ddb8a797cd83a4ba2d
if [ "$EXPECTED_ONLY" = true ]; then printf '%s %s\n' "$VERSION" "$SHA256"; exit 0; fi
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) echo "fetch-chromium: the pinned chrome-headless-shell is that of x86-64 Linux; this is $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEST=$ROOT/third_party/chromium
if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$VERSION $SHA256" ]; then exit 0; fi
ZIP=${GOLEM_DOWNLOADS:-$ROOT/third_party/downloads}/chrome-headless-shell-linux64.zip
sh "$ROOT/scripts/ci/fetch-url.sh" "$ZIP" "$SHA256" "https://storage.googleapis.com/chrome-for-testing-public/$VERSION/linux64/chrome-headless-shell-linux64.zip"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/x"
unzip -q "$ZIP" -d "$TMP/x"
if [ ! -f "$TMP/x/chrome-headless-shell-linux64/chrome-headless-shell" ]; then echo "fetch-chromium: the zip has no chrome-headless-shell-linux64/chrome-headless-shell" >&2; exit 1; fi
rm -rf "${DEST:?}"
mkdir -p "$DEST"
mv "$TMP/x/chrome-headless-shell-linux64" "$DEST/"
echo "$VERSION $SHA256" >"$DEST/VERSION"
