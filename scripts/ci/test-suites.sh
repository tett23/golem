#!/bin/sh
# Prints the targets of cabal test for one runner of the tests of the build
# job of ci.yml, one per line (docs/adr/0140).
#
#   test-suites.sh driver [MODULES]  the test suites of golem-driver
#   test-suites.sh driver-a [MODULES]  those of DRIVER_A below, for the
#                                    runner tests-driver-a
#   test-suites.sh driver-b [MODULES]  the other suites of golem-driver,
#                                    for the runner tests-driver-b
#   test-suites.sh rest [MODULES]    every other test suite
#   test-suites.sh rest-a [MODULES]  those of rest of REST_A below, for
#                                    the runner tests-rest-a
#   test-suites.sh rest-b [MODULES]  the other suites of rest, for the
#                                    runner tests-rest-b
#   test-suites.sh all [MODULES]     all, for cabal test all
#   test-suites.sh wasm [MODULES]    the suites of the golem packages of
#                                    cabal.project.wasm, the packages of
#                                    golem.wasm, and golem-test-support-test,
#                                    which wasm-tests.yml runs on wasm32
#                                    (docs/adr/0293 A1, root ADR 0415)
#
# A target is PACKAGE:test:SUITE, read from the test-suite sections of
# MODULES/*/*.cabal (MODULES is the modules/ of the repository unless
# given). Every suite is in driver or in rest, never in both, so that a new
# suite runs without being listed here (it needs its limits in
# suite-limits.tsv, docs/adr ADR 0292). wasm reads the lines
# modules/NAME of the packages: of the cabal.project.wasm next to MODULES,
# and the suites of MODULES/NAME/*.cabal, so that a suite added to a
# package of golem.wasm runs on wasm32 too. wasm adds the one suite
# golem-test-support-test, which checks the limits of time of the tests
# on wasm32 (root ADR 0388 I2, root ADR 0415); golem-test-support is a
# package of cabal.project.wasm-tests only, and its other suite, built
# with -threaded, is not run there.
#
# driver-a and driver-b split the suites of driver between the two runners
# of the tests of golem-driver of each architecture: driver-a has the
# suites of DRIVER_A, driver-b every other suite of golem-driver, so that a
# new suite of golem-driver runs on tests-driver-b without being listed
# here (root ADR 0416)
#
# rest-a and rest-b split the suites of rest in the same way: rest-a has
# the suites of REST_A, rest-b every other suite of rest, so that a new
# suite runs on tests-rest-b without being listed here. A suite of
# golem-driver in REST_A is in neither, as it is not in rest (root ADR
# 0457)
set -eu
DRIVER_A="golem-driver-pdf-test golem-driver-cli-test golem-driver-global-test"
REST_A="golem-emet-test golem-geometry-test golem-typeset-test"
usage() { echo "usage: test-suites.sh driver|driver-a|driver-b|rest|rest-a|rest-b|all|wasm [MODULES]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
PART=$1
case "$PART" in
  driver | driver-a | driver-b | rest | rest-a | rest-b | all | wasm) ;;
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
  awk -v part="$PART" -v driver_a=" $DRIVER_A " -v rest_a=" $REST_A " '
    tolower($1) == "name:" && pkg == "" { pkg = $2 }
    tolower($1) == "test-suite" { suites[++n] = $2 }
    END {
      if (pkg == "") { print "test-suites.sh: no name in " FILENAME > "/dev/stderr"; exit 1 }
      if (part != "wasm" && (part ~ /^driver/) != (pkg == "golem-driver")) exit 0
      for (i = 1; i <= n; i++) {
        a = index(driver_a, " " suites[i] " ") > 0
        if ((part == "driver-a" && !a) || (part == "driver-b" && a)) continue
        r = index(rest_a, " " suites[i] " ") > 0
        if ((part == "rest-a" && !r) || (part == "rest-b" && r)) continue
        print pkg ":test:" suites[i]
      }
    }' "$cabal"
done
if [ "$PART" = wasm ]; then echo golem-test-support:test:golem-test-support-test; fi
