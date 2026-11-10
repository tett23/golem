#!/bin/sh
# One test suite of the packages of golem.wasm on wasm32, against the list
# of the tests known to fail there (docs/adr/0293 section 4).
#
#   run-suite.sh TARGET WASM OUT
#
# TARGET is PACKAGE:test:SUITE (scripts/ci/test-suites.sh wasm), WASM the
# suite built for wasm32, OUT a directory for the logs. The tests of SUITE
# in scripts/wasm/test-failures.tsv (FAILURES chooses another list) are
# left out with tasty's -p, and every other test must pass or be a SKIP
# (A2); then each listed test runs alone and must fail (A3): one that
# passes, or that the suite does not have, is to be taken off the list.
# RUN chooses the command that runs a suite (node scripts/wasm/run-tests.mjs
# by default); it gets WASM, PACKAGE and the arguments of tasty.
#
# Written to OUT: SUITE.log (the output of the run of the other tests),
# SUITE.results (scripts/wasm/tasty-results.sh of it), SUITE.skipped (the
# names of the tests that were a SKIP), SUITE.listed.log (the runs of the
# listed tests), and one line to stdout: SUITE, the seconds, the exit
# code of the run, the number of tests that passed, failed and were a
# SKIP, tab-separated.
#
# Exit code 0: A2 and A3 hold for the suite; 1: they do not, each test
# that breaks them is named on stderr; 2: a usage error.
set -u
usage() { echo "usage: run-suite.sh PACKAGE:test:SUITE WASM OUT" >&2; exit 2; }
[ $# = 3 ] || usage
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TARGET=$1 WASM=$2 OUT=$3
case "$TARGET" in
  *:test:*) ;;
  *) usage ;;
esac
PACKAGE=${TARGET%%:*}
SUITE=${TARGET##*:}
case "$PACKAGE$SUITE" in
  *[!a-z0-9-]*) usage ;;
esac
FAILURES=${FAILURES:-$ROOT/scripts/wasm/test-failures.tsv}
[ -f "$FAILURES" ] || { echo "run-suite.sh: no list $FAILURES" >&2; exit 2; }
mkdir -p "$OUT"
# runs the suite with the arguments given
suite() {
  if [ -n "${RUN:-}" ]; then
    # shellcheck disable=SC2086 # RUN is a command and its arguments
    $RUN "$WASM" "$PACKAGE" --color never "$@"
  else
    node --no-warnings "$ROOT/scripts/wasm/run-tests.mjs" "$WASM" "$PACKAGE" --color never "$@"
  fi
}
# the listed tests of SUITE, one name per line (the header and the lines
# of other suites left out)
awk -F '\t' -v s="$SUITE" 'NR > 1 && $1 == s { print $2 }' "$FAILURES" >"$OUT/$SUITE.listed"
# a string of tasty's patterns: in double quotes, \ and " escaped
quote() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"; }
PATTERN=
while IFS= read -r name; do
  if [ -z "$PATTERN" ]; then PATTERN="\$0 == $(quote "$name")"; else PATTERN="$PATTERN || \$0 == $(quote "$name")"; fi
done <"$OUT/$SUITE.listed"
if [ -n "$PATTERN" ]; then
  bytes=$(LC_ALL=C printf '%s' "!($PATTERN)" | wc -c | tr -d ' ')
  if [ "$bytes" -gt 65536 ]; then
    echo "A2 $SUITE: the pattern of $bytes bytes is over 65536" >&2
    exit 1
  fi
fi
start=$(date +%s)
code=0
if [ -n "$PATTERN" ]; then
  suite -p "!($PATTERN)" >"$OUT/$SUITE.log" 2>&1 || code=$?
else
  suite >"$OUT/$SUITE.log" 2>&1 || code=$?
fi
seconds=$(($(date +%s) - start))
sh "$ROOT/scripts/wasm/tasty-results.sh" "$OUT/$SUITE.log" >"$OUT/$SUITE.results"
awk -F '\t' '$1 == "SKIP" { print $2 }' "$OUT/$SUITE.results" >"$OUT/$SUITE.skipped"
count() { awk -F '\t' -v r="$1" '$1 == r { n++ } END { print n + 0 }' "$OUT/$SUITE.results"; }
bad=0
if [ "$code" != 0 ]; then
  bad=1
  echo "A2 $SUITE: the tests not in $(basename "$FAILURES") exited $code" >&2
  awk -F '\t' -v s="$SUITE" '$1 == "FAIL" { print "A2 " s ": failed: " $2 }' "$OUT/$SUITE.results" >&2
fi
: >"$OUT/$SUITE.listed.log"
while IFS= read -r name; do
  c=0
  suite -p "\$0 == $(quote "$name")" >>"$OUT/$SUITE.listed.log" 2>&1 </dev/null || c=$?
  if [ "$c" = 0 ]; then
    bad=1
    echo "A3 $SUITE: listed, but passes or is not a test of the suite: $name" >&2
  fi
done <"$OUT/$SUITE.listed"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$SUITE" "$seconds" "$code" "$(count OK)" "$(count FAIL)" "$(count SKIP)"
exit "$bad"
