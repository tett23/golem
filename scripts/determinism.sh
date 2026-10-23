#!/bin/sh
# Builds the fixed inputs and prints the SHA-256 of every output file, and
# of the stdout and the stderr of each `golem build --format json` with its
# exit code. CI runs this on x86-64 and aarch64 and compares the lists
# (docs/adr/0001, docs/adr/0002, docs/adr/0071, golem-eval ADR 0001). The
# two manuals are inputs too: they are built with their fonts, which are
# fetched once, and left in manual/build and manual-dev/build for CI to
# upload (docs/adr/0022, docs/adr/0024). scripts/manual/build.sh fails a
# manual on any diagnostic, so only their files are listed.
#
# The lines are `<SHA-256>  <input>/<file>`, `<SHA-256>  <input>/stdout`,
# `<SHA-256>  <input>/stderr` and `exit <code>  <input>`.
#
# GOLEM chooses the golem to run. For the tests: GOLEM_MANUAL_ROOT is the
# folder that holds the manuals, as in scripts/manual/build.sh.
set -eu
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
GOLEM=${GOLEM:-golem}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANUALS=$(cd "${GOLEM_MANUAL_ROOT:-$ROOT}" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

sha() { $SHA "$1" | cut -d' ' -f1; }

# files NAME DIR: the SHA-256 of every file under DIR/build
files() {
  [ -d "$2/build" ] || return 0
  (cd "$2" && find build -type f | LC_ALL=C sort | while read -r f; do
    printf '%s  %s\n' "$(sha "$f")" "$1/$f"
  done)
}

# build NAME DIR [ARG...]: builds DIR with the ARGs and lists its files, the
# SHA-256 of stdout and of stderr, and the exit code, which may be other
# than 0 (the input diagnostics ends in an error)
build() {
  name=$1 dir=$2
  shift 2
  rm -rf "$dir/build"
  code=0
  (cd "$dir" && "$GOLEM" build --format json "$@" >"$WORK/stdout" 2>"$WORK/stderr") || code=$?
  files "$name" "$dir"
  printf '%s  %s\n' "$(sha "$WORK/stdout")" "$name/stdout"
  printf '%s  %s\n' "$(sha "$WORK/stderr")" "$name/stderr"
  printf 'exit %s  %s\n' "$code" "$name"
}

for project in "$ROOT/scripts/determinism" "$ROOT/modules/golem-driver/test/fixtures/sample"; do
  build "$(basename "$project")" "$project" --target html --target epub --target text
  rm -rf "$project/build"
done
# the PDF path: Noto Serif JP of the kanikosen fixture, which has every
# character of the sample (docs/adr/0081), and Source Sans Pro of golem-font
cp -R "$ROOT/modules/golem-driver/test/fixtures/sample" "$WORK/pdf"
mkdir -p "$WORK/pdf/fonts"
cp "$ROOT/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" "$WORK/pdf/fonts/ja.otf"
cp "$ROOT/modules/golem-font/test/fonts/SourceSansPro-Regular.otf" "$WORK/pdf/fonts/latin.otf"
cp "$ROOT/scripts/determinism/pdf-style.toml" "$WORK/pdf/style.toml"
build pdf "$WORK/pdf" --target pdf
# the input that gives diagnostics and ends in an error (docs/adr/0029,
# docs/adr/0071)
cp -R "$ROOT/scripts/env-determinism/diagnostics" "$WORK/diagnostics"
build diagnostics "$WORK/diagnostics"
# the manuals (docs/adr/0022, docs/adr/0024)
GOLEM=$GOLEM sh "$ROOT/scripts/manual/build.sh" manual manual-dev
for manual in manual manual-dev; do
  files "$manual" "$MANUALS/$manual"
done
