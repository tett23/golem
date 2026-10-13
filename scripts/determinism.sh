#!/bin/sh
# Builds the fixed inputs and prints the SHA-256 of every output file.
# CI runs this on x86-64 and aarch64 and compares the lists
# (docs/adr/0001, docs/adr/0002, golem-eval ADR 0001). The manual is one of
# the inputs: it is built with its fonts, which are fetched once, and left in
# manual/build for CI to upload (docs/adr/0022).
set -eu
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
GOLEM=${GOLEM:-golem}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for project in "$ROOT/scripts/determinism" "$ROOT/modules/golem-driver/test/fixtures/sample"; do
  (cd "$project" && rm -rf build && "$GOLEM" build --target html --target epub --target text >/dev/null)
  (cd "$project" && find build -type f | LC_ALL=C sort | while read -r f; do
    printf '%s  %s\n' "$($SHA "$f" | cut -d' ' -f1)" "$(basename "$project")/$f"
  done)
  rm -rf "$project/build"
done
# the PDF path with the test fonts of golem-font
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -R "$ROOT/modules/golem-driver/test/fixtures/sample" "$WORK/pdf"
mkdir -p "$WORK/pdf/fonts"
cp "$ROOT/modules/golem-font/test/fonts/SourceHanSans-Regular_subset.otf" "$WORK/pdf/fonts/ja.otf"
cp "$ROOT/modules/golem-font/test/fonts/SourceSansPro-Regular.otf" "$WORK/pdf/fonts/latin.otf"
cp "$ROOT/scripts/determinism/pdf-style.toml" "$WORK/pdf/style.toml"
(cd "$WORK/pdf" && "$GOLEM" build --target pdf >/dev/null)
(cd "$WORK/pdf" && find build -type f | LC_ALL=C sort | while read -r f; do
  printf '%s  %s\n' "$($SHA "$f" | cut -d' ' -f1)" "pdf/$f"
done)
# the manual (docs/adr/0022)
GOLEM=$GOLEM sh "$ROOT/scripts/manual/build.sh"
(cd "$ROOT/manual" && find build -type f | LC_ALL=C sort | while read -r f; do
  printf '%s  %s\n' "$($SHA "$f" | cut -d' ' -f1)" "manual/$f"
done)
