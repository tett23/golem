#!/bin/sh
# Downloads the public-domain texts used as fixtures, checks their
# SHA-256, converts them to Golem source and formats it with golem fmt.
#
#   The Tempest (Shakespeare): Project Gutenberg eBook #23042
#   蟹工船 (小林多喜二): 青空文庫 図書カード No.1465
#
# Usage: GOLEM=path/to/golem scripts/fixtures/fetch-public-domain.sh
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLEM=${GOLEM:-golem}
FIX=$ROOT/modules/golem-driver/test/fixtures
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fetch() { # url file sha256
  curl -sSfL -o "$TMP/$2" "$1"
  actual=$($SHA "$TMP/$2" | cut -d' ' -f1)
  if [ "$actual" != "$3" ]; then echo "SHA-256 mismatch for $1: $actual" >&2; exit 1; fi
}

fetch https://www.gutenberg.org/cache/epub/23042/pg23042.txt tempest.txt d511c4b7ba963b316705b4b097415f59b4fcb03c9964bb65673fbaae4d730219
python3 -I "$ROOT/scripts/fixtures/gutenberg_play_to_gm.py" "$TMP/tempest.txt" "$FIX/tempest/tempest.gm"

fetch https://www.aozora.gr.jp/cards/000156/files/1465_ruby_16804.zip kanikosen.zip 16eb0c4c83b3930818a70cefa78978b490d536de6cc52d19d30e2bcaf6b363a4
mkdir -p "$TMP/kanikosen"
unzip -q -o "$TMP/kanikosen.zip" -d "$TMP/kanikosen"
iconv -f SHIFT_JIS -t UTF-8 "$TMP"/kanikosen/*.txt > "$TMP/kanikosen.txt"
python3 -I "$ROOT/scripts/fixtures/aozora_to_gm.py" "$TMP/kanikosen.txt" "$FIX/kanikosen/kanikosen.gm"

"$GOLEM" fmt "$FIX/tempest/tempest.gm" "$FIX/kanikosen/kanikosen.gm"
