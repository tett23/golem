#!/bin/sh
# Typesets the inputs of the visual regression test to PDF
# (docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md).
#
#   build.sh OUT     writes OUT/<input>.pdf for every input
#   build.sh --list  prints the names of the inputs, one per line
#
# The list of the inputs is written here only; check.sh and run.sh read it
# with --list. Each project is copied to a temporary directory and built
# there, so that nothing is written to the build/ of the repository. The
# fonts of the ten public-domain books are copied into the repository with
# scripts/fixtures/copy-fonts.sh, and those of the manuals are fetched into
# manual/fonts and manual-dev/fonts by scripts/manual/fetch-fonts.sh, as
# for the other scripts (GOLEM_MANUAL_SKIP_FONTS=1 skips it, for the
# tests). The manuals are built with a fixed commit and tag, so that their
# colophon does not change with every commit.
#
# GOLEM chooses the golem to run, as in scripts/determinism.sh. An input
# that does not build fails the script with exit code 1 and the output of
# golem on stderr.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FIX=$ROOT/modules/golem-driver/test/fixtures
PD_BOOKS="elements-of-style frogs haru-to-shura ichiaku-no-suna koya-hijiri merry-wives nightmare-abbey snark taira-no-masakado ushiyama-hotel"
list() {
  printf '%s\n' sample figures kanikosen kanikosen-marks-japanese tempest
  for book in $PD_BOOKS; do printf 'pd-%s\n' "$book"; done
  printf '%s\n' manual manual-dev
}
case "${1-}" in
  --list) list; exit 0 ;;
  "" | -*) echo "usage: build.sh OUT | build.sh --list" >&2; exit 2 ;;
esac
[ $# -eq 1 ] || { echo "usage: build.sh OUT | build.sh --list" >&2; exit 2; }
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
GOLEM=${GOLEM:-golem}
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

# pdf NAME DIR [ARG...]: builds the PDF of DIR with the ARGs and copies it
# to OUT/NAME.pdf
pdf() {
  name=$1 dir=$2
  shift 2
  rm -rf "$dir/build"
  if ! (cd "$dir" && "$GOLEM" build --target pdf "$@") >"$WORK/log" 2>&1; then
    cat "$WORK/log" >&2
    echo "build: golem build of $name failed" >&2
    exit 1
  fi
  one "$name" "$dir"
}

# one NAME DIR: copies the one PDF in DIR/build/pdf to OUT/NAME.pdf
one() {
  find "$2/build/pdf" -type f -name '*.pdf' >"$WORK/pdfs" 2>/dev/null || true
  if [ "$(wc -l <"$WORK/pdfs" | tr -d ' ')" != 1 ]; then
    echo "build: $1 did not write exactly one PDF" >&2
    exit 1
  fi
  cp "$(cat "$WORK/pdfs")" "$OUT/$1.pdf"
}

# copy NAME SRC: a copy of the project SRC at WORK/NAME, without its build/
copy() {
  cp -R "$2" "$WORK/$1"
  rm -rf "$WORK/$1/build"
}

# fonts DIR: Noto Serif JP of the kanikosen fixture and Source Sans Pro of
# golem-font as DIR/fonts/ja.otf and DIR/fonts/latin.otf, as in
# scripts/determinism.sh and OutputGoldenSpec
fonts() {
  mkdir -p "$1/fonts"
  cp "$FIX/kanikosen/fonts/NotoSerifJP-Regular.otf" "$1/fonts/ja.otf"
  cp "$ROOT/modules/golem-font/test/fonts/SourceSansPro-Regular.otf" "$1/fonts/latin.otf"
}

sh "$ROOT/scripts/fixtures/copy-fonts.sh"

copy sample "$FIX/sample"
fonts "$WORK/sample"
cp "$ROOT/scripts/determinism/pdf-style.toml" "$WORK/sample/style.toml"
pdf sample "$WORK/sample"

copy figures "$FIX/figures"
fonts "$WORK/figures"
pdf figures "$WORK/figures"

copy kanikosen "$FIX/kanikosen"
pdf kanikosen "$WORK/kanikosen"

# the Japanese crop marks with a bleed of 3 mm: the Separation colour of the
# marks and a MediaBox with the bleed
copy kanikosen-marks-japanese "$FIX/kanikosen"
awk '{ print } $0 == "[page]" { print "bleed = \"3mm\"" }' "$FIX/kanikosen/style.toml" >"$WORK/kanikosen-marks-japanese/style.toml"
if ! grep -qx 'bleed = "3mm"' "$WORK/kanikosen-marks-japanese/style.toml"; then
  echo "build: the style.toml of kanikosen has no [page] for the bleed" >&2
  exit 1
fi
pdf kanikosen-marks-japanese "$WORK/kanikosen-marks-japanese" --marks japanese

copy tempest "$FIX/tempest"
pdf tempest "$WORK/tempest"

for book in $PD_BOOKS; do
  copy "pd-$book" "$FIX/pd/$book"
  pdf "pd-$book" "$WORK/pd-$book"
done

# the manuals, with their fonts fetched (or checked) in the repository once
mkdir -p "$WORK/manuals"
for manual in manual manual-dev; do
  [ "${GOLEM_MANUAL_SKIP_FONTS-}" = 1 ] || sh "$ROOT/scripts/manual/fetch-fonts.sh" "$ROOT/$manual/fonts"
  cp -R "$ROOT/$manual" "$WORK/manuals/$manual"
  rm -rf "$WORK/manuals/$manual/build"
done
if ! GOLEM=$GOLEM GOLEM_MANUAL_ROOT=$WORK/manuals \
  GOLEM_MANUAL_COMMIT=0000000000000000000000000000000000000000 GOLEM_MANUAL_TAG=v0.0.0-visual \
  sh "$ROOT/scripts/manual/build.sh" manual manual-dev >"$WORK/log" 2>&1; then
  cat "$WORK/log" >&2
  echo "build: the manuals did not build" >&2
  exit 1
fi
for manual in manual manual-dev; do
  one "$manual" "$WORK/manuals/$manual"
done
