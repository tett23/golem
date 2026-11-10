#!/bin/sh
# Prints the targets of cabal test for one runner of the tests of the build
# job of ci.yml, one per line (docs/adr/0140).
#
#   test-suites.sh driver [MODULES]  the test suites of golem-driver
#   test-suites.sh rest [MODULES]    every other test suite
#   test-suites.sh all [MODULES]     all, for cabal test all
#
# A target is PACKAGE:test:SUITE, read from the test-suite sections of
# MODULES/*/*.cabal (MODULES is the modules/ of the repository unless
# given). Every suite is in driver or in rest, never in both, so that a new
# suite runs without being listed here; it needs its limits in
# suite-limits.tsv (docs/adr ADR 0292).
set -eu
usage() { echo "usage: test-suites.sh driver|rest|all [MODULES]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
PART=$1
case "$PART" in
  driver | rest | all) ;;
  *) usage ;;
esac
if [ "$PART" = all ]; then echo all; exit 0; fi
MODULES=${2:-$(cd "$(dirname "$0")/../.." && pwd)/modules}
[ -d "$MODULES" ] || { echo "test-suites.sh: no directory $MODULES" >&2; exit 1; }
for cabal in "$MODULES"/*/*.cabal; do
  [ -f "$cabal" ] || continue
  awk -v part="$PART" '
    tolower($1) == "name:" && pkg == "" { pkg = $2 }
    tolower($1) == "test-suite" { suites[++n] = $2 }
    END {
      if (pkg == "") { print "test-suites.sh: no name in " FILENAME > "/dev/stderr"; exit 1 }
      if ((part == "driver") != (pkg == "golem-driver")) exit 0
      for (i = 1; i <= n; i++) print pkg ":test:" suites[i]
    }' "$cabal"
done
