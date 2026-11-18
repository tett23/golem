#!/bin/sh
# Prints the targets of cabal build for a runner of the build job of ci.yml,
# one per line (docs/adr/0395-bring-the-pull-request-ci-under-five-minutes.md).
#
#   build-targets.sh all [MODULES]    everything, and peg-hs: the runners
#                                     that save dist-newstyle, so that the
#                                     cache has it all, and tests-driver
#   build-targets.sh rest [MODULES]   the suites of tests-rest
#                                     (test-suites.sh rest), and peg-hs for
#                                     the check of the generated parser
#   build-targets.sh golem [MODULES]  the executable golem alone: the
#                                     outputs and the environment check use
#                                     nothing else
#
# MODULES is passed to test-suites.sh.
set -eu
usage() { echo "usage: build-targets.sh all|rest|golem [MODULES]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
case "$1" in
  all) printf 'all\npeg-cli:exe:peg-hs\n' ;;
  rest)
    SUITES=$(sh "$(dirname "$0")/test-suites.sh" rest ${2:+"$2"})
    printf '%s\npeg-cli:exe:peg-hs\n' "$SUITES"
    ;;
  golem) echo golem-cli:exe:golem ;;
  *) usage ;;
esac
