#!/bin/sh
# Reuse the CI manual fonts and their checksum-verified fetch script.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
sh "$ROOT/scripts/manual/fetch-fonts.sh" "$ROOT/manual/fonts"
for project in muromachi-court discourse-politeness honorifics; do
    mkdir -p "$HERE/$project/fonts"
    cp "$ROOT/manual/fonts/"* "$HERE/$project/fonts/"
done
