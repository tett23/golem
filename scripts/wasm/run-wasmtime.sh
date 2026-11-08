#!/bin/sh
# golem.wasm under the C API of wasmtime (docs/adr/0238): builds the host
# scripts/wasm/run-wasmtime.c with cc and the C API that
# scripts/fetch-wasmtime.sh put in third_party/wasmtime, compiles golem.wasm
# once, and builds each project with it. run.mjs makes the input frame and
# reads the result frame.
#
#   run-wasmtime.sh compile WASM HOST   builds HOST/run-wasmtime and
#                                       compiles WASM to HOST/golem.cwasm
#   run-wasmtime.sh build HOST DIR PDF  run.mjs frame DIR, run-wasmtime call
#                                       and run.mjs result PDF: the PDF to
#                                       PDF, the JSON of the diagnostics to
#                                       stderr, and the exit code of
#                                       run.mjs build
#
# A usage error exits 2; a failure of the host, more than 1. CC chooses the
# C compiler, NODE the node to run.
set -eu
usage() { echo "usage: run-wasmtime.sh compile WASM HOST | run-wasmtime.sh build HOST DIR PDF" >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NODE=${NODE:-node}
case ${1:-} in
  compile)
    [ $# = 3 ] || usage
    WASMTIME=$ROOT/third_party/wasmtime
    if [ "$(cat "$WASMTIME/VERSION" 2>/dev/null || true)" != "$(sh "$ROOT/scripts/fetch-wasmtime.sh" --expected)" ]; then
      echo "run-wasmtime.sh: $WASMTIME is not the C API of scripts/fetch-wasmtime.sh; run it first" >&2
      exit 3
    fi
    case "$(uname -s)" in
      Darwin) LIBS="-framework CoreFoundation" ;;
      *) LIBS="-lpthread -ldl -lm" ;;
    esac
    mkdir -p "$3"
    # shellcheck disable=SC2086 # LIBS is a list of options
    "${CC:-cc}" -O2 -I"$WASMTIME/include" -o "$3/run-wasmtime" "$ROOT/scripts/wasm/run-wasmtime.c" "$WASMTIME/lib/libwasmtime.a" $LIBS || { echo "run-wasmtime.sh: run-wasmtime.c does not build" >&2; exit 3; }
    "$3/run-wasmtime" compile "$2" "$3/golem.cwasm" || { echo "run-wasmtime.sh: run-wasmtime compile $2 failed" >&2; exit 3; }
    ;;
  build)
    [ $# = 4 ] || usage
    HOST=$2 DIR=$3 PDF=$4
    WORK=$(mktemp -d)
    trap 'rm -rf "${WORK:?}"' EXIT
    "$NODE" --no-warnings "$ROOT/scripts/wasm/run.mjs" frame "$DIR" >"$WORK/frame" || { echo "run-wasmtime.sh: run.mjs frame $DIR failed" >&2; exit 3; }
    "$HOST/run-wasmtime" call "$HOST/golem.cwasm" <"$WORK/frame" >"$WORK/result" || { echo "run-wasmtime.sh: run-wasmtime call failed" >&2; exit 3; }
    code=0
    "$NODE" --no-warnings "$ROOT/scripts/wasm/run.mjs" result "$PDF" <"$WORK/result" || code=$?
    exit "$code"
    ;;
  *) usage ;;
esac
