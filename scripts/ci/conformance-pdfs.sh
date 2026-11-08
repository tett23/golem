#!/bin/sh
# Typesets the books that the CI job verapdf checks against PDF/A-2a and
# PDF/UA-1 (docs/adr/0183-tagged-pdf-and-pdf-a.md).
#
#   conformance-pdfs.sh OUT     writes OUT/<book>.pdf for every book
#   conformance-pdfs.sh --list  prints the names of the books, one per line
#
# Each book is a copy of a fixture with an output intent added to its
# style.toml ([color] intent, the profile of scripts/ci/testdata/conformance)
# and pdfa = "2a" and pdfua = "1" added to [targets.pdf] of its
# manifest.toml. The figures, the conformance and the languages fixtures take the fonts of
# the other fixtures as fonts/ja.otf and fonts/latin.otf, as
# scripts/visual/build.sh does; the conformance fixture is set horizontally
# with its manifest.toml and style.toml, and vertically with its
# manifest-vertical.toml and style-vertical.toml.
#
# GOLEM chooses the golem to run. A book that does not build fails the
# script with exit code 1 and the output of golem on stderr.
set -eu
exit 1 # TEMPORARY: the check of docs/adr/0244 that verapdf fails without conformance-pdfs
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FIX=$ROOT/modules/golem-driver/test/fixtures
PROFILE=$HERE/testdata/conformance/golem-test-cmyk.icc
list() {
  printf '%s\n' kanikosen tempest figures conformance-horizontal conformance-vertical languages
}
case "${1-}" in
  --list) list; exit 0 ;;
  "" | -*) echo "usage: conformance-pdfs.sh OUT | conformance-pdfs.sh --list" >&2; exit 2 ;;
esac
[ $# -eq 1 ] || { echo "usage: conformance-pdfs.sh OUT | conformance-pdfs.sh --list" >&2; exit 2; }
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
GOLEM=${GOLEM:-golem}
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

# declared NAME SRC [STYLE MANIFEST]: a copy of the fixture SRC at
# WORK/NAME, its style and manifest the files STYLE and MANIFEST of SRC
# (style.toml and manifest.toml by default), with the output intent and
# the declarations
declared() {
  dir=$WORK/$1
  cp -R "$2" "$dir"
  rm -rf "$dir/build"
  if [ -n "${3-}" ]; then cp "$2/$3" "$dir/style.toml"; fi
  if [ -n "${4-}" ]; then cp "$2/$4" "$dir/manifest.toml"; fi
  cp "$PROFILE" "$dir/golem-test-cmyk.icc"
  printf '\n[color]\nintent = "golem-test-cmyk.icc"\n' >>"$dir/style.toml"
  if grep -q '^\[targets\.pdf\]$' "$dir/manifest.toml"; then
    sed '/^\[targets\.pdf\]$/a\
pdfa = "2a"\
pdfua = "1"
' "$dir/manifest.toml" >"$WORK/manifest.toml"
    cp "$WORK/manifest.toml" "$dir/manifest.toml"
  else
    printf '\n[targets.pdf]\npdfa = "2a"\npdfua = "1"\n' >>"$dir/manifest.toml"
  fi
}

# fonts DIR: Noto Serif JP of the kanikosen fixture and Source Sans Pro of
# golem-font as DIR/fonts/ja.otf and DIR/fonts/latin.otf
fonts() {
  mkdir -p "$1/fonts"
  cp "$FIX/kanikosen/fonts/NotoSerifJP-Regular.otf" "$1/fonts/ja.otf"
  cp "$ROOT/modules/golem-font/test/fonts/SourceSansPro-Regular.otf" "$1/fonts/latin.otf"
}

# pdf NAME: builds the PDF of WORK/NAME and copies it to OUT/NAME.pdf
pdf() {
  if ! (cd "$WORK/$1" && "$GOLEM" build --target pdf) 2>&1; then
    echo "conformance-pdfs: golem build of $1 failed"
    return 1
  fi
  find "$WORK/$1/build/pdf" -type f -name '*.pdf' >"$WORK/pdfs-$1"
  if [ "$(wc -l <"$WORK/pdfs-$1" | tr -d ' ')" != 1 ]; then
    echo "conformance-pdfs: $1 did not write exactly one PDF"
    return 1
  fi
  cp "$(cat "$WORK/pdfs-$1")" "$OUT/$1.pdf"
}

declared kanikosen "$FIX/kanikosen"
declared tempest "$FIX/tempest"
declared figures "$FIX/figures"
fonts "$WORK/figures"
declared conformance-horizontal "$FIX/conformance"
fonts "$WORK/conformance-horizontal"
declared conformance-vertical "$FIX/conformance" style-vertical.toml manifest-vertical.toml
fonts "$WORK/conformance-vertical"
declared languages "$FIX/languages"
fonts "$WORK/languages"
for name in $(list); do pdf "$name" >"$WORK/log-$name" 2>&1 || { cat "$WORK/log-$name" >&2; exit 1; }; done
