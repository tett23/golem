#!/bin/sh
# Whether a wasm module has instructions of the legacy exception handling
# (try, catch, catch_all, delegate, rethrow; docs/adr/0238): Node validates
# the module twice, as it is and with --no-experimental-wasm-legacy-eh,
# under which V8 refuses those instructions. The standard exception
# handling (try_table, throw_ref, throw) is valid under both.
#
#   legacy-eh.sh WASM
#
# Exits 0 when both validate the module, 1 when only the first does (the
# module has the legacy exception handling), and 2 when the first does not
# either (another error, or a file that cannot be read) or on a usage
# error. NODE chooses the node to run.
set -u
[ $# = 1 ] || { echo "usage: legacy-eh.sh WASM" >&2; exit 2; }
NODE=${NODE:-node}
VALIDATE='const fs = require("node:fs"); let b; try { b = fs.readFileSync(process.argv[1]); } catch (e) { console.error(e.message); process.exit(3); } process.exit(WebAssembly.validate(b) ? 0 : 1);'
code=0
"$NODE" -e "$VALIDATE" "$1" || code=$?
case $code in
  0) ;;
  1) echo "legacy-eh.sh: $1 is not a valid wasm module" >&2; exit 2 ;;
  *) echo "legacy-eh.sh: $1 cannot be validated (node exited $code)" >&2; exit 2 ;;
esac
code=0
"$NODE" --no-experimental-wasm-legacy-eh -e "$VALIDATE" "$1" || code=$?
case $code in
  0) exit 0 ;;
  1) echo "legacy-eh.sh: $1 has instructions of the legacy exception handling (try, catch, catch_all, delegate or rethrow)" >&2; exit 1 ;;
  *) echo "legacy-eh.sh: $1 cannot be validated with --no-experimental-wasm-legacy-eh (node exited $code)" >&2; exit 2 ;;
esac
