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
#   compare.sh --deno WASM      the same with run.mjs under the node:wasi of
#                               Deno (DENO chooses the deno to run)
#   compare.sh --browser BROWSER WASM
#                               the same in chromium or safari, with
#                               browser_wasi_shim (scripts/wasm/run-browser.mjs)
#   compare.sh --wasmtime WASM  the same under the C API of wasmtime
#                               (scripts/wasm/run-wasmtime.sh), which
#                               compiles WASM once (docs/adr/0238)
#   compare.sh --check A B      the two lists are the same (diff); the CI
#                               compares the native list with the wasm one
#
# The inputs: kanikosen; the project of scripts/determinism/ with its PDF
# style.toml; the PDF inputs of scripts/determinism.sh (pdf,
# complex-vertical, complex-horizontal), with the fonts it gives them; and
# kanikosen with a broken style.toml and without its font, whose builds end
# in an error; and broken-cmap, kanikosen whose Noto Serif JP has a format 6
# cmap subtable that FreeType refuses by longjmp, the exception handling of
# wasm (docs/adr/0238; its build ends in an error too); and the six inputs
# of the int-width fixture, whose values the width of Int would change
# (docs/adr/0247): int-width (an ASCII85 figure whose two content streams
# are named twice each, and @number 2147483648), int-width-reference (a
# figure with 4294967297 0 R), int-width-icc (a figure with an ICCBased of
# /N 4294967299, with a preflight.toml that checks the colour spaces),
# int-width-png (a PNG of IHDR width 2^31), int-width-png-chunk (a PNG
# with a chunk of length 2^31) and int-width-printing (an edition
# 2147483648 in printings). The lines are `<SHA-256>  <input>/pdf` (- without a PDF),
# `<SHA-256>  <input>/diagnostics` and `exit <code>  <input>`; `exit timeout
# <input>` when the build of an input ran past COMPARE_TIMEOUT seconds (600
# by default) and was stopped, so that an input that never ends does not
# keep the job to its own time-out (docs/adr/0247 section 7).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
usage() { echo "usage: compare.sh --native GOLEM | compare.sh WASM | compare.sh --deno WASM | compare.sh --browser chromium|safari WASM | compare.sh --wasmtime WASM | compare.sh --check A B" >&2; exit 2; }
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
  --deno)
    [ $# = 2 ] || usage
    MODE=deno PROGRAM=$2
    ;;
  --browser)
    [ $# = 3 ] || usage
    case $2 in chromium | safari) ;; *) usage ;; esac
    MODE=browser BROWSER=$2 PROGRAM=$3
    ;;
  --wasmtime)
    [ $# = 2 ] || usage
    MODE=wasmtime PROGRAM=$2
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
JA=$ROOT/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf
# broken-cmap breaks the two bytes at 30205 of this font, the entryCount of
# its format 6 cmap subtable; another font would be broken elsewhere
JA_SHA=2c9a12dbd4f2408c4610c7ee84a108b62d7236c3775baed618c64d9cb44b2f04
if [ "$(sha "$JA")" != "$JA_SHA" ]; then
  echo "compare.sh: the SHA-256 of $JA is not $JA_SHA: broken-cmap would not break its format 6 cmap subtable" >&2
  exit 1
fi
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

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
copy "$ROOT/modules/golem-driver/test/fixtures/kanikosen" broken-cmap
printf '\377\377' | dd of="$WORK/in/broken-cmap/fonts/NotoSerifJP-Regular.otf" bs=1 seek=30205 conv=notrunc 2>/dev/null
# the inputs of the int-width fixture (docs/adr/0247 section 7): the book
# as it is, and five with one figure or one printing in its place
IW=$ROOT/modules/golem-driver/test/fixtures/int-width
copy "$IW" int-width
fonts "$WORK/in/int-width"
figure_book() { # NAME IMAGE: the fixture with only one figure, IMAGE (with the SVG for the web)
  copy "$IW" "$1"
  fonts "$WORK/in/$1"
  printf '# 図\n\n@figure images/%s web=images/figure.svg alt="図"\n  図。\n' "$2" >"$WORK/in/$1/int-width.gm"
}
figure_book int-width-reference reference.pdf
figure_book int-width-icc icc.pdf
printf '[image-color-space]\nseverity = "error"\nallowed = ["gray"]\n' >"$WORK/in/int-width-icc/preflight.toml"
figure_book int-width-png ihdr-width.png
figure_book int-width-png-chunk chunk-length.png
copy "$IW" int-width-printing
fonts "$WORK/in/int-width-printing"
printf '# 版\n\n本文。\n' >"$WORK/in/int-width-printing/int-width.gm"
printf '\n[[metadata.printings]]\nedition = 2147483648\nprinting = 1\ndate = 2026-11-09\n' >>"$WORK/in/int-width-printing/manifest.toml"

# limited COMMAND...: COMMAND in the background, stopped with TERM (and its
# children with it, the host of run-wasmtime.sh) past LIMIT seconds and
# with KILL ten seconds later; its exit code, and $WORK/timeout when it was
# stopped. The watcher looks once a second, as scripts/models/check.sh does
LIMIT=${COMPARE_TIMEOUT:-600}
stop() { # SIGNAL PID: the process and its children
  for child in $(pgrep -P "$2" 2>/dev/null); do kill "-$1" "$child" 2>/dev/null || :; done
  kill "-$1" "$2" 2>/dev/null || :
}
limited() {
  rm -f "$WORK/timeout"
  "$@" &
  pid=$!
  (
    s=0
    while [ "$s" -lt "$LIMIT" ] && kill -0 "$pid" 2>/dev/null; do sleep 1; s=$((s + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
      : >"$WORK/timeout"
      stop TERM "$pid"
      s=0
      while [ "$s" -lt 10 ] && kill -0 "$pid" 2>/dev/null; do sleep 1; s=$((s + 1)); done
      stop KILL "$pid"
    fi
  ) </dev/null >/dev/null 2>&1 &
  watcher=$!
  status=0
  wait "$pid" || status=$?
  wait "$watcher" || :
  return "$status"
}
native_build() { # DIR
  cd "$1" && exec "$PROGRAM" build --target pdf --format json
}

if [ "$MODE" = wasmtime ]; then sh "$ROOT/scripts/wasm/run-wasmtime.sh" compile "$PROGRAM" "$WORK/wasmtime"; fi

for name in kanikosen determinism pdf complex-vertical complex-horizontal broken-style missing-font broken-cmap \
  int-width int-width-reference int-width-icc int-width-png int-width-png-chunk int-width-printing; do
  dir=$WORK/in/$name
  code=0
  if [ "$MODE" = native ]; then
    limited native_build "$dir" >/dev/null 2>"$WORK/json" || code=$?
    pdf=$(find "$dir/build/pdf" -name '*.pdf' 2>/dev/null | head -1)
  elif [ "$MODE" = browser ]; then
    # the page gives the SHA-256 of the PDF, not the PDF
    limited node "$ROOT/scripts/wasm/run-browser.mjs" build "$BROWSER" "$PROGRAM" "$dir" >"$WORK/sha" 2>"$WORK/json" || code=$?
    pdf=
  elif [ "$MODE" = wasmtime ]; then
    limited sh "$ROOT/scripts/wasm/run-wasmtime.sh" build "$WORK/wasmtime" "$dir" "$WORK/out.pdf" 2>"$WORK/json" || code=$?
    pdf=$WORK/out.pdf
    [ -f "$pdf" ] || pdf=
  elif [ "$MODE" = deno ]; then
    # Deno writes the warning that WASI is experimental to stderr, which
    # NODE_NO_WARNINGS does not stop; that line alone is taken out of the JSON
    limited "${DENO:-deno}" run --allow-read --allow-write "$ROOT/scripts/wasm/run.mjs" build "$PROGRAM" "$dir" "$WORK/out.pdf" 2>"$WORK/raw" || code=$?
    grep -v '^(node:[0-9]*) ExperimentalWarning: WASI is an experimental feature and might change at any time$' "$WORK/raw" >"$WORK/json" || true
    pdf=$WORK/out.pdf
    [ -f "$pdf" ] || pdf=
  else
    # without the warning that WASI is experimental, which would go into the JSON
    limited node --no-warnings "$ROOT/scripts/wasm/run.mjs" build "$PROGRAM" "$dir" "$WORK/out.pdf" 2>"$WORK/json" || code=$?
    pdf=$WORK/out.pdf
    [ -f "$pdf" ] || pdf=
  fi
  if [ -f "$WORK/timeout" ]; then
    code=timeout
    echo "compare.sh: $name: stopped after $LIMIT s" >&2
  # a host that failed (not the exit code of golem build) says why
  elif [ "$MODE" != native ] && [ "$code" -gt 1 ]; then
    echo "compare.sh: $name: the host exited $code:" >&2
    cat "$WORK/json" >&2
  fi
  if [ "$MODE" = browser ]; then
    sha_line=$(head -n 1 "$WORK/sha")
    printf '%s  %s\n' "${sha_line:--}" "$name/pdf"
  elif [ -n "$pdf" ]; then printf '%s  %s\n' "$(sha "$pdf")" "$name/pdf"; else printf '%s  %s\n' - "$name/pdf"; fi
  printf '%s  %s\n' "$(sha "$WORK/json")" "$name/diagnostics"
  printf 'exit %s  %s\n' "$code" "$name"
  rm -f "$WORK/out.pdf"
done
