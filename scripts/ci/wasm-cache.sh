#!/bin/sh
# Says why the toolchain cache of the wasm job of ci.yml (the toolchain and
# its cabal store, ghc-wasm-...) missed, in one line for the Times step
# (docs/adr/0219-frequency-of-the-wasm-job-and-its-uncached-runs.md).
#
#   wasm-cache.sh HIT TOOLCHAIN PROJECT
#
# HIT is true when the cache was restored by its key (cache-hit of
# actions/cache). TOOLCHAIN is true when scripts/fetch-ghc-wasm.sh is that
# of main, PROJECT when cabal.project.wasm, its freeze,
# scripts/fetch-wasm-packages.sh and scripts/wasm/patches/ are those of
# main. Each is true or false.
#
#   a hit                        the cache was restored
#   TOOLCHAIN false              the toolchain changed
#   PROJECT false                the project or its freeze changed
#   both true                    the cache was evicted: a ::warning::
#                                annotation, and the job still passes
#
# A pull request that changes the toolchain or the freeze may take more
# than 5 minutes once (CONTRIBUTING.md); an evicted cache is a fault of CI.
# The exit code is 0, and 2 for wrong arguments.
set -u
usage() {
  echo "usage: wasm-cache.sh HIT TOOLCHAIN PROJECT (each true or false)" >&2
  exit 2
}
[ $# -eq 3 ] || usage
for a in "$@"; do
  case $a in true | false) ;; *) usage ;; esac
done
if [ "$1" = true ]; then
  echo "wasm-cache: the toolchain cache was restored"
elif [ "$2" = false ]; then
  echo "wasm-cache: missed, as scripts/fetch-ghc-wasm.sh differs from main (the toolchain changed)"
elif [ "$3" = false ]; then
  echo "wasm-cache: missed, as the project or its freeze differs from main"
else
  echo "::warning::wasm-cache: missed, though the toolchain, the project and its freeze are those of main: the cache was evicted (docs/adr/0219)"
fi
