#!/bin/sh
# Copies the fonts of the fixtures 『蟹工船』 and The Tempest into the ten
# books of modules/golem-driver/test/fixtures/pd/, which do not commit their
# fonts (docs/adr/0026). The Japanese books get Noto Serif JP, the English
# ones Source Serif, each with its licence.
#
# Usage: scripts/fixtures/copy-fonts.sh
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIX=$ROOT/modules/golem-driver/test/fixtures
for book in merry-wives frogs snark elements-of-style nightmare-abbey; do
  mkdir -p "$FIX/pd/$book/fonts"
  cp "$FIX/tempest/fonts/SourceSerifVariable-Roman.ttf" "$FIX/tempest/fonts/LICENSE-SourceSerif.txt" "$FIX/pd/$book/fonts/"
done
for book in koya-hijiri ichiaku-no-suna haru-to-shura taira-no-masakado ushiyama-hotel; do
  mkdir -p "$FIX/pd/$book/fonts"
  cp "$FIX/kanikosen/fonts/NotoSerifJP-Regular.otf" "$FIX/kanikosen/fonts/LICENSE-NotoSerifJP.txt" "$FIX/pd/$book/fonts/"
done
