#!/bin/sh
# Builds the HTML of the checks of scripts/browser/html-checks.mjs
# (docs/adr/0234 section 3) with GOLEM (golem unless given):
#
#   build-fixtures.sh OUT
#
# OUT/horizontal and OUT/vertical are the build/html of
# scripts/browser/fixtures/horizontal and vertical, with the fonts of the
# tests of the repository copied in (ja: Noto Serif JP of kanikosen; latin
# and code: Source Sans Pro of golem-font); OUT/figures is that of the
# figures fixture of golem-driver, whose four PNGs have tRNS. A build with a
# diagnostic fails: the checks would look at other HTML.
set -eu
[ $# -eq 1 ] || { echo "usage: build-fixtures.sh OUT" >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLEM=${GOLEM:-golem}
OUT=$1
JA=$ROOT/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf
LATIN=$ROOT/modules/golem-font/test/fonts/SourceSansPro-Regular.otf
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
mkdir -p "$OUT"
# build NAME SRC: OUT/NAME is the HTML of a copy of SRC
build() {
  cp -R "$2" "$WORK/$1"
  rm -rf "$WORK/$1/build"
  mkdir -p "$WORK/$1/fonts"
  cp "$JA" "$WORK/$1/fonts/ja.otf"
  cp "$LATIN" "$WORK/$1/fonts/latin.otf"
  cp "$LATIN" "$WORK/$1/fonts/code.otf"
  (cd "$WORK/$1" && "$GOLEM" build --target html 2>"$WORK/$1.err") || { cat "$WORK/$1.err" >&2; exit 1; }
  if [ -s "$WORK/$1.err" ]; then cat "$WORK/$1.err" >&2; echo "build-fixtures: $1 has diagnostics" >&2; exit 1; fi
  rm -rf "${OUT:?}/$1"
  cp -R "$WORK/$1/build/html" "$OUT/$1"
}
build horizontal "$ROOT/scripts/browser/fixtures/horizontal"
build vertical "$ROOT/scripts/browser/fixtures/vertical"
build figures "$ROOT/modules/golem-driver/test/fixtures/figures"
