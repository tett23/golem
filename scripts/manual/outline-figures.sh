#!/bin/sh
# Outlines the figures of the developer manual (golem-pdf ADR 0009):
# manual-dev/images/src/NAME.svg, the source with its text, becomes
# manual-dev/images/NAME.svg, with the text as paths. Golem places SVG
# figures without text, so the sources are kept for editing and the
# outlined files are committed next to them. Do not edit the outlined
# files by hand; scripts/manual/check-figures.sh checks that each was made
# from its source as it is.
#
#   outline-figures.sh [NAME...]    all the SVG files by default
#
# It uses Inkscape 1.x (INKSCAPE chooses the executable) and only the fonts
# of the manual (scripts/manual/fetch-fonts.sh): a fontconfig of its own
# names manual-dev/fonts alone and maps the family of the sources, Fig
# Sans, to Noto Sans JP, so the fonts of the machine are never used.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DIR=$(cd "$HERE/../../manual-dev" && pwd)
INKSCAPE=${INKSCAPE:-inkscape}
command -v "$INKSCAPE" >/dev/null 2>&1 || { echo "outline-figures: no Inkscape; set INKSCAPE" >&2; exit 1; }
sh "$HERE/fetch-fonts.sh" "$DIR/fonts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/fonts.conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>$DIR/fonts</dir>
  <cachedir>$TMP/cache</cachedir>
  <alias binding="same"><family>Fig Sans</family><prefer><family>Noto Sans JP</family></prefer></alias>
</fontconfig>
EOF
VERSION=$(FONTCONFIG_FILE="$TMP/fonts.conf" HOME="$TMP" "$INKSCAPE" --version 2>/dev/null | head -n 1)
if [ $# -eq 0 ]; then
  for f in "$DIR"/images/src/*.svg; do
    n=${f##*/}
    set -- "$@" "${n%.svg}"
  done
fi
for name in "$@"; do
  SRC=$DIR/images/src/$name.svg
  SUM=$(sha256sum "$SRC" | cut -d ' ' -f 1)
  # Inkscape does not read @font-face, and an outlined SVG must not keep it (G08011)
  sed '/@font-face/d' "$SRC" > "$TMP/$name.svg"
  FONTCONFIG_FILE="$TMP/fonts.conf" HOME="$TMP" "$INKSCAPE" --export-text-to-path --export-plain-svg \
    --export-filename="$TMP/$name.out.svg" "$TMP/$name.svg" >/dev/null 2>&1
  {
    # the XML declaration, then the comment that check-figures.sh reads
    sed -n '1{/^<?xml/p}' "$TMP/$name.out.svg"
    printf '<!-- Made by scripts/manual/outline-figures.sh from images/src/%s.svg (sha256 %s) with %s. Do not edit by hand. -->\n' "$name" "$SUM" "$VERSION"
    sed '1{/^<?xml/d}' "$TMP/$name.out.svg"
  } > "$DIR/images/$name.svg"
  echo "$name.svg"
done
