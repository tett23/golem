#!/bin/sh
# Downloads the public-domain texts used as fixtures, checks their
# SHA-256, converts them to Golem source with golem-fixtures
# (modules/golem-fixtures, docs/adr/0023, docs/adr/0026) and formats it
# with golem fmt.
#
#   The Tempest (Shakespeare): Project Gutenberg eBook #23042
#   蟹工船 (小林多喜二): 青空文庫 図書カード No.1465
#
# and the ten books of test/fixtures/pd (docs/adr/0026):
#
#   The Merry Wives of Windsor (Shakespeare): Project Gutenberg eBook #23044
#   The Frogs (Aristophanes, tr. B. B. Rogers): Project Gutenberg eBook #7998
#   The Hunting of the Snark (Lewis Carroll): Project Gutenberg eBook #13
#   The Elements of Style (William Strunk, Jr.): Project Gutenberg eBook #37134
#   Nightmare Abbey (Thomas Love Peacock): Project Gutenberg eBook #9909
#   高野聖 (泉鏡花): 青空文庫 図書カード No.521
#   一握の砂 (石川啄木): 青空文庫 図書カード No.816
#   春と修羅 (宮沢賢治): 青空文庫 図書カード No.1058
#   平将門 (幸田露伴): 青空文庫 図書カード No.3199
#   牛山ホテル (岸田國士): 青空文庫 図書カード No.51829
#
# The ten books do not commit their fonts; copy-fonts.sh copies them in.
#
# Usage: GOLEM=path/to/golem scripts/fixtures/fetch-public-domain.sh
# CABAL sets the cabal to run golem-fixtures with (default: cabal).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLEM=${GOLEM:-golem}
CABAL=${CABAL:-cabal}
FIX=$ROOT/modules/golem-driver/test/fixtures
PD=$FIX/pd
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# converts INPUT into OUTPUT: golem-fixtures CONVERTER [OPTION...] INPUT OUTPUT
convert() {
  (cd "$ROOT" && "$CABAL" run -v0 golem-fixtures -- "$@")
}

fetch() { # url file sha256
  curl -sSfL -o "$TMP/$2" "$1"
  actual=$($SHA "$TMP/$2" | cut -d' ' -f1)
  if [ "$actual" != "$3" ]; then echo "SHA-256 mismatch for $1: $actual" >&2; exit 1; fi
}

aozora() { # url name sha256: the ruby-annotated text of a zip, in UTF-8, at $TMP/name.txt
  fetch "$1" "$2.zip" "$3"
  mkdir -p "$TMP/$2"
  unzip -q -o "$TMP/$2.zip" -d "$TMP/$2"
  iconv -f SHIFT_JIS -t UTF-8 "$TMP/$2"/*.txt > "$TMP/$2.txt"
}

fetch https://www.gutenberg.org/cache/epub/23042/pg23042.txt tempest.txt d511c4b7ba963b316705b4b097415f59b4fcb03c9964bb65673fbaae4d730219
convert gutenberg-play "$TMP/tempest.txt" "$FIX/tempest/tempest.gm"

aozora https://www.aozora.gr.jp/cards/000156/files/1465_ruby_16804.zip kanikosen 16eb0c4c83b3930818a70cefa78978b490d536de6cc52d19d30e2bcaf6b363a4
convert aozora "$TMP/kanikosen.txt" "$FIX/kanikosen/kanikosen.gm"

fetch https://www.gutenberg.org/cache/epub/23044/pg23044.txt merry-wives.txt 466e363503f03b6d8d42f20bb46feb72a12774ac5f472b09bbaebd683f61a1e2
convert gutenberg-play "$TMP/merry-wives.txt" "$PD/merry-wives/merry-wives.gm"

fetch https://www.gutenberg.org/cache/epub/7998/pg7998.txt frogs.txt 60406dc500de2b5ad9a9f509dc65cf8cdf083787d625278e02b58f1e4d7e5979
convert gutenberg-text --start "INTRODUCTORY NOTE" --verse --speakers --heading "INTRODUCTORY NOTE" --heading "THE FROGS OF ARISTOPHANES" --heading "DRAMATIS PERSON" "$TMP/frogs.txt" "$PD/frogs/frogs.gm"

fetch https://www.gutenberg.org/cache/epub/13/pg13.txt snark.txt 30d6d0a4fa246393ba85df5fa4fb3d0358bdf3f4784a8d0ebb96547275bc4f74
convert gutenberg-text --start "Inscribed to a dear Child:" --verse --heading "Fit the" --caps-heading 2 "$TMP/snark.txt" "$PD/snark/snark.gm"

fetch https://www.gutenberg.org/cache/epub/37134/pg37134.txt elements-of-style.txt bf5312eb0fa36837253ec84211cdab51deae01744e1de3ffef528aee43c27496
convert gutenberg-text --start "CONTENTS" --end "[ Transcriber's Note:" --caps-heading 1 --numbered-headings --two-columns --bold-equals "$TMP/elements-of-style.txt" "$PD/elements-of-style/elements-of-style.gm"

fetch https://www.gutenberg.org/cache/epub/9909/pg9909.txt nightmare-abbey.txt a93dc819c44779f922a03145f89f19a1a5ca4adb784c28202d70c1918a173a59
convert gutenberg-text --start "NIGHTMARE ABBEY:" --heading "CHAPTER" --notes "NOTES" "$TMP/nightmare-abbey.txt" "$PD/nightmare-abbey/nightmare-abbey.gm"

aozora https://www.aozora.gr.jp/cards/000050/files/521_ruby_20582.zip koya-hijiri daf4c4984734e87a8375ef9aa47a2d044a86b6b6b828fb36ced0ad5c411a2486
convert aozora-prose "$TMP/koya-hijiri.txt" "$PD/koya-hijiri/koya-hijiri.gm"

aozora https://www.aozora.gr.jp/cards/000153/files/816_ruby_5621.zip ichiaku-no-suna ad919f69abc8590a67e9e5b377ac1c478f1492445815a0321e089b146aaa0142
convert aozora-verse "$TMP/ichiaku-no-suna.txt" "$PD/ichiaku-no-suna/ichiaku-no-suna.gm"

aozora https://www.aozora.gr.jp/cards/000081/files/1058_ruby_4709.zip haru-to-shura d65e0acdd64bb46e6f98bd67618c1d544142e9784a7b8f376a1be0c6a744388a
convert aozora-verse "$TMP/haru-to-shura.txt" "$PD/haru-to-shura/haru-to-shura.gm"

aozora https://www.aozora.gr.jp/cards/000051/files/3199_ruby_6102.zip taira-no-masakado bcb507e480ddc3f4cb0b292045b879aecc34b7bd6a28ac78219be889f4935663
convert aozora-prose "$TMP/taira-no-masakado.txt" "$PD/taira-no-masakado/taira-no-masakado.gm"

aozora https://www.aozora.gr.jp/cards/001154/files/51829_ruby_47125.zip ushiyama-hotel d8be88751da136e48d8dcaf79c0bee10adfeb822645173dd7e9a7707c480a092
convert aozora-prose "$TMP/ushiyama-hotel.txt" "$PD/ushiyama-hotel/ushiyama-hotel.gm"

"$GOLEM" fmt "$FIX/tempest/tempest.gm" "$FIX/kanikosen/kanikosen.gm" "$PD"/*/*.gm
sh "$ROOT/scripts/fixtures/copy-fonts.sh"
