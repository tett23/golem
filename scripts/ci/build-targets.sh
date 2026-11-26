#!/bin/sh
# Prints the targets of cabal build for a runner of the build job of ci.yml,
# or for the job cache-dist, one per line
# (docs/adr/0395-bring-the-pull-request-ci-under-five-minutes.md, root ADR
# 0416, root ADR 0457).
#
#   build-targets.sh all [MODULES]       everything, and peg-hs: cache-dist,
#                                        which saves dist-newstyle, so that
#                                        the cache has it all
#   build-targets.sh driver-a [MODULES]  the suites of tests-driver-a
#   build-targets.sh driver-b [MODULES]  the suites of tests-driver-b
#                                        (test-suites.sh driver-a and
#                                        driver-b)
#   build-targets.sh rest [MODULES]      the suites of rest
#                                        (test-suites.sh rest), peg-hs for
#                                        the check of the generated parser,
#                                        and every executable of MODULES
#                                        but golem, which no suite may
#                                        build: build, which ci needs,
#                                        still compiles them, as it did
#                                        when one runner built all. An
#                                        executable with buildable: False
#                                        (under a condition, as golem-wasm
#                                        off wasm32) is left out, as all
#                                        leaves it out. rest is what
#                                        rest-a and rest-b build together
#   build-targets.sh rest-a [MODULES]    the suites of tests-rest-a
#                                        (test-suites.sh rest-a) and peg-hs
#   build-targets.sh rest-b [MODULES]    the suites of tests-rest-b
#                                        (test-suites.sh rest-b) and the
#                                        executables of rest, so that a new
#                                        executable is built on
#                                        tests-rest-b (root ADR 0457)
#   build-targets.sh golem [MODULES]    the executable golem alone: the
#                                        outputs and the environment check
#                                        use nothing else
#
# MODULES is passed to test-suites.sh, and is the modules/ of the
# repository unless given.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
usage() { echo "usage: build-targets.sh all|driver-a|driver-b|rest|rest-a|rest-b|golem [MODULES]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
# every executable of the modules $1 but golem and those not buildable
executables() {
  for f in "$1"/*/*.cabal; do
    [ -f "$f" ] || continue
    awk 'tolower($1) == "name:" && pkg == "" { pkg = $2 }
      /^[^ \t-]/ { in_exe = 0 }
      tolower($1) == "executable" { exes[++n] = $2; in_exe = 1 }
      in_exe && tolower($1) == "buildable:" && tolower($2) == "false" { off[n] = 1 }
      END { for (i = 1; i <= n; i++) if (exes[i] != "golem" && !off[i]) print pkg ":exe:" exes[i] }' "$f"
  done
}
MODULES=${2:-$HERE/../../modules}
case "$1" in
  all) printf 'all\npeg-cli:exe:peg-hs\n' ;;
  driver-a | driver-b) sh "$HERE/test-suites.sh" "$1" ${2:+"$2"} ;;
  rest)
    SUITES=$(sh "$HERE/test-suites.sh" rest "$MODULES")
    printf '%s\npeg-cli:exe:peg-hs\n' "$SUITES"
    executables "$MODULES"
    ;;
  rest-a)
    SUITES=$(sh "$HERE/test-suites.sh" rest-a "$MODULES")
    if [ -n "$SUITES" ]; then printf '%s\n' "$SUITES"; fi
    echo peg-cli:exe:peg-hs
    ;;
  rest-b)
    SUITES=$(sh "$HERE/test-suites.sh" rest-b "$MODULES")
    if [ -n "$SUITES" ]; then printf '%s\n' "$SUITES"; fi
    executables "$MODULES"
    ;;
  golem) echo golem-cli:exe:golem ;;
  *) usage ;;
esac
