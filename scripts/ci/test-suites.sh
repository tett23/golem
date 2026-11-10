#!/bin/sh
# Prints the targets of cabal test for one runner of the tests of the build
# job of ci.yml, one per line (docs/adr/0140).
#
#   test-suites.sh driver [MODULES]  the test suites of golem-driver
#   test-suites.sh rest [MODULES]    every other test suite
#   test-suites.sh all [MODULES]     all, for cabal test all
#   test-suites.sh wasm [MODULES]    the suites of the golem packages of
#                                    cabal.project.wasm, the packages of
#                                    golem.wasm, which wasm-tests.yml runs
#                                    on wasm32 (docs/adr/0293 A1)
#
# A target is PACKAGE:test:SUITE, read from the test-suite sections of
# MODULES/*/*.cabal (MODULES is the modules/ of the repository unless
# given). Every suite is in driver or in rest, never in both, so that a new
# suite runs without being listed here (it needs its limits in
# suite-limits.tsv, docs/adr ADR 0292). wasm reads the lines
# modules/NAME of the packages: of the cabal.project.wasm next to MODULES,
# and the suites of MODULES/NAME/*.cabal, so that a suite added to a
# package of golem.wasm runs on wasm32 too.
set -eu
usage() { echo "usage: test-suites.sh driver|rest|all|wasm [MODULES]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
PART=$1
case "$PART" in
  driver | rest | all | wasm) ;;
  *) usage ;;
esac
if [ "$PART" = all ]; then echo all; exit 0; fi
MODULES=${2:-$(cd "$(dirname "$0")/../.." && pwd)/modules}
[ -d "$MODULES" ] || { echo "test-suites.sh: no directory $MODULES" >&2; exit 1; }
if [ "$PART" = wasm ]; then
  PROJECT=$(dirname "$MODULES")/cabal.project.wasm
  [ -f "$PROJECT" ] || { echo "test-suites.sh: no $PROJECT" >&2; exit 1; }
  CABALS=$(sed -n 's|^  modules/\([a-z0-9-]*\)[[:space:]]*$|\1|p' "$PROJECT" | while IFS= read -r d; do
    for f in "$MODULES/$d"/*.cabal; do if [ -f "$f" ]; then printf '%s\n' "$f"; fi; done
  done)
else
  CABALS=$(for f in "$MODULES"/*/*.cabal; do printf '%s\n' "$f"; done)
fi
printf '%s\n' "$CABALS" | while IFS= read -r cabal; do
  [ -f "$cabal" ] || continue
  awk -v part="$PART" '
    tolower($1) == "name:" && pkg == "" { pkg = $2 }
    tolower($1) == "test-suite" { suites[++n] = $2 }
    END {
      if (pkg == "") { print "test-suites.sh: no name in " FILENAME > "/dev/stderr"; exit 1 }
      if (part != "wasm" && (part == "driver") != (pkg == "golem-driver")) exit 0
      for (i = 1; i <= n; i++) print pkg ":test:" suites[i]
    }' "$cabal"
done
