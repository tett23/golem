#!/bin/sh
# Typesets the manual (docs/adr/0022-manual-as-typesetting-sample.md): fetches
# the fonts (or checks them, if they are there) and builds the PDF and the
# HTML of manual/ into manual/build/. GOLEM chooses the golem to run, as in
# scripts/determinism.sh.
#
# The manual must build without a single diagnostic: a warning fails it as
# an error does.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
MANUAL=$(cd "$HERE/../../manual" && pwd)
GOLEM=${GOLEM:-golem}
sh "$HERE/fetch-fonts.sh" "$MANUAL/fonts"
rm -rf "$MANUAL/build"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
CODE=0
(cd "$MANUAL" && "$GOLEM" build --target pdf --target html) >"$OUT" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] || [ -s "$OUT" ]; then
  cat "$OUT" >&2
  echo "build: golem build of manual/ exited with $CODE and wrote the diagnostics above; the manual must build without any" >&2
  exit 1
fi
