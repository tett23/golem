#!/bin/sh
# The Hackage packages of the wasm build have the versions of the native
# build (docs/adr/0199 section 6): every package that both
# cabal.project.freeze and cabal.project.wasm.freeze pin has the same
# version in both.
#
#   wasm-freeze.sh [NATIVE WASM [TESTS]]   (cabal.project.freeze,
#                                          cabal.project.wasm.freeze and
#                                          cabal.project.wasm-tests by
#                                          default)
#
# TESTS, the project of the test suites on wasm32 (docs/adr/0293), imports
# cabal.project.wasm and cabal.project.wasm.freeze: cabal reads a freeze
# file only next to a project file of the same name, so the versions
# checked here are those of the tests too.
#
# Left out of the comparison (docs/adr/0202 section 2):
#   cborg              the wasm build takes a commit of its upstream, which
#                      still says 0.2.10.0, not the release of Hackage
#   skylighting,       the wasm build takes the archives of Hackage with a
#   skylighting-core   patch: the same version number, other contents, which
#                      a comparison of versions would hide
# The boot packages of the wasm GHC (base, text, time and the others of
# wasm32-wasi-ghc-pkg list --global) are not in cabal.project.wasm.freeze:
# their versions are those of the wasm GHC (time 1.14 where the native
# freeze has 1.12.2), recorded when the toolchain was checked (#632), so
# they are in one file only and not compared.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NATIVE=${1:-$ROOT/cabal.project.freeze}
WASM=${2:-$ROOT/cabal.project.wasm.freeze}
TESTS=${3:-}
if [ $# -lt 2 ]; then TESTS=$ROOT/cabal.project.wasm-tests; fi
if [ -n "$TESTS" ]; then
  for i in cabal.project.wasm cabal.project.wasm.freeze; do
    grep -qx "import: $i" "$TESTS" || { echo "wasm-freeze: $TESTS does not import $i" >&2; exit 1; }
  done
fi
EXCLUDED="cborg skylighting skylighting-core"
# versions FILE: NAME VERSION of each any.NAME ==VERSION, sorted
versions() {
  sed -n 's/^[a-z:]*[[:space:]]*any\.\([A-Za-z0-9-]*\) ==\([0-9.]*\),\{0,1\}[[:space:]]*$/\1 \2/p' "$1" | LC_ALL=C sort
}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
versions "$NATIVE" >"$TMP/native"
versions "$WASM" >"$TMP/wasm"
if [ ! -s "$TMP/wasm" ]; then echo "wasm-freeze: no version in $WASM" >&2; exit 1; fi
bad=$(awk -v excluded="$EXCLUDED" '
  BEGIN { n = split(excluded, e, " "); for (i = 1; i <= n; i++) skip[e[i]] = 1 }
  FNR == NR { native[$1] = $2; next }
  ($1 in native) && !($1 in skip) && native[$1] != $2 { print $1 ": " native[$1] " (native), " $2 " (wasm)" }
' "$TMP/native" "$TMP/wasm")
if [ -n "$bad" ]; then
  echo "wasm-freeze: the versions of cabal.project.wasm.freeze differ from cabal.project.freeze:" >&2
  printf '%s\n' "$bad" >&2
  exit 1
fi
