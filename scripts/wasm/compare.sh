#!/bin/sh
# The list that compares the PDF of golem.wasm with that of the native
# golem of the same commit (docs/adr/0199): for each input, the SHA-256 of
# the PDF, of the JSON of the diagnostics and the exit code.
#
#   compare.sh --native GOLEM   builds each input with golem build --target
#                               pdf --format json (the PDF of build/pdf/, the
#                               JSON on stderr)
#   compare.sh WASM             builds each input with golem.wasm under
#                               node:wasi (scripts/wasm/run.mjs)
#   compare.sh --check A B      the two lists are the same (diff); the CI
#                               compares the native list with the wasm one
#
# The inputs: kanikosen; the project of scripts/determinism/ with its PDF
# style.toml; the PDF inputs of scripts/determinism.sh (pdf,
# complex-vertical, complex-horizontal), with the fonts it gives them; and
# kanikosen with a broken style.toml and without its font, whose builds end
# in an error. The lines are `<SHA-256>  <input>/pdf` (- without a PDF),
# `<SHA-256>  <input>/diagnostics` and `exit <code>  <input>`.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
usage() { echo "usage: compare.sh --native GOLEM | compare.sh WASM | compare.sh --check A B" >&2; exit 2; }
case ${1:-} in
  --check)
    [ $# = 3 ] || usage
    if diff "$2" "$3"; then exit 0; fi
    echo "compare.sh: the PDFs or the diagnostics of wasm and native differ" >&2
    exit 1
    ;;
  --native)
    [ $# = 2 ] || usage
    MODE=native PROGRAM=$2
    ;;
  "" | -*) usage ;;
  *)
    [ $# = 1 ] || usage
    MODE=wasm PROGRAM=$1
    ;;
esac

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

JA=$ROOT/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf
LATIN=$ROOT/modules/golem-font/test/fonts/SourceSansPro-Regular.otf
fonts() { mkdir -p "$1/fonts" && cp "$JA" "$1/fonts/ja.otf" && cp "$LATIN" "$1/fonts/latin.otf"; }
copy() { # FIXTURE NAME: a copy of a folder, without build/
  cp -R "$1" "$WORK/in/$2"
  rm -rf "$WORK/in/$2/build"
}
mkdir -p "$WORK/in"
copy "$ROOT/modules/golem-driver/test/fixtures/kanikosen" kanikosen
copy "$ROOT/scripts/determinism" determinism
rm -f "$WORK/in/determinism/hashes.txt" "$WORK/in/determinism/pdf-style.toml"
cp "$ROOT/scripts/determinism/pdf-style.toml" "$WORK/in/determinism/style.toml"
fonts "$WORK/in/determinism"
copy "$ROOT/modules/golem-driver/test/fixtures/sample" pdf
cp "$ROOT/scripts/determinism/pdf-style.toml" "$WORK/in/pdf/style.toml"
fonts "$WORK/in/pdf"
for book in complex-vertical complex-horizontal; do
  copy "$ROOT/modules/golem-driver/test/fixtures/$book" "$book"
  fonts "$WORK/in/$book"
done
copy "$ROOT/modules/golem-driver/test/fixtures/kanikosen" broken-style
printf '\n[page\nsize = \n' >>"$WORK/in/broken-style/style.toml"
copy "$ROOT/modules/golem-driver/test/fixtures/kanikosen" missing-font
rm "$WORK/in/missing-font/fonts/NotoSerifJP-Regular.otf"

for name in kanikosen determinism pdf complex-vertical complex-horizontal broken-style missing-font; do
  dir=$WORK/in/$name
  code=0
  if [ "$MODE" = native ]; then
    (cd "$dir" && "$PROGRAM" build --target pdf --format json >/dev/null 2>"$WORK/json") || code=$?
    pdf=$(find "$dir/build/pdf" -name '*.pdf' 2>/dev/null | head -1)
  else
    # without the warning that WASI is experimental, which would go into the JSON
    node --no-warnings "$ROOT/scripts/wasm/run.mjs" build "$PROGRAM" "$dir" "$WORK/out.pdf" 2>"$WORK/json" || code=$?
    pdf=$WORK/out.pdf
    [ -f "$pdf" ] || pdf=
  fi
  if [ -n "$pdf" ]; then printf '%s  %s\n' "$(sha "$pdf")" "$name/pdf"; else printf '%s  %s\n' - "$name/pdf"; fi
  printf '%s  %s\n' "$(sha "$WORK/json")" "$name/diagnostics"
  printf 'exit %s  %s\n' "$code" "$name"
  rm -f "$WORK/out.pdf"
done
