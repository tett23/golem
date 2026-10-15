#!/bin/sh
# Renders the figures of the developer manual: manual-dev/images/src/NAME.svg
# becomes manual-dev/images/NAME.png. Golem places PNG and JPEG figures,
# not SVG, so the SVG files are the sources and the PNG files are committed
# next to them.
#
#   render-figures.sh [NAME...]    all the SVG files by default
#
# It uses headless Chrome (CHROME chooses the executable) and the fonts the
# manual is built with (scripts/manual/fetch-fonts.sh), so the text of the
# figures is set in Noto Sans JP. Rendering is not part of the build: run it
# after editing an SVG file and commit both files.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DIR=$(cd "$HERE/../../manual-dev" && pwd)
SCALE=${SCALE:-1.5}
if [ -z "${CHROME-}" ]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" google-chrome chromium chromium-browser; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then CHROME=$c; break; fi
  done
fi
[ -n "${CHROME-}" ] || { echo "render-figures: no Chrome; set CHROME" >&2; exit 1; }
sh "$HERE/fetch-fonts.sh" "$DIR/fonts"
if [ $# -eq 0 ]; then
  for f in "$DIR"/images/src/*.svg; do
    n=${f##*/}
    set -- "$@" "${n%.svg}"
  done
fi
for name in "$@"; do
  SRC=$DIR/images/src/$name.svg
  # the size of the figure is the width and height of its root element
  W=$(sed -n 's/.*<svg[^>]* width="\([0-9]*\)".*/\1/p' "$SRC" | head -n 1)
  H=$(sed -n 's/.*<svg[^>]* height="\([0-9]*\)".*/\1/p' "$SRC" | head -n 1)
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --force-device-scale-factor="$SCALE" --default-background-color=ffffffff \
    --window-size="$W,$H" --screenshot="$DIR/images/$name.png" "file://$SRC" >/dev/null 2>&1
  echo "$name.png"
done
