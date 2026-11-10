#!/bin/sh
# The SKIPs of the suites on wasm32 against those of the native suites run
# without the external tools, and the listed tests against their native
# results (docs/adr/0293 A3, A4).
#
#   check-skips.sh NATIVE WASM
#
# NATIVE has SUITE.results of each native suite and WASM SUITE.results of
# each suite run by scripts/wasm/run-suite.sh (scripts/wasm/tasty-results.sh:
# the result, a tab, the full name). Every test that is a SKIP on wasm32 is
# a SKIP natively, where only a missing tool of needsTool makes one (A4);
# every test of scripts/wasm/test-failures.tsv (FAILURES chooses another
# list) passes natively (A3). A suite of the list or of WASM without
# native results breaks both.
#
# Writes a Markdown table of the SKIPs of each suite to stdout. Exit code
# 0: both hold; 1: they do not, each test that breaks them named on stderr;
# 2: a usage error.
set -eu
[ $# = 2 ] || { echo "usage: check-skips.sh NATIVE WASM" >&2; exit 2; }
NATIVE=$1 WASM=$2
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FAILURES=${FAILURES:-$ROOT/scripts/wasm/test-failures.tsv}
[ -d "$NATIVE" ] && [ -d "$WASM" ] && [ -f "$FAILURES" ] || { echo "check-skips.sh: no $NATIVE, $WASM or $FAILURES" >&2; exit 2; }
bad=0
echo "| Suite | SKIP on wasm32 | SKIP natively |"
echo "| --- | --- | --- |"
for r in "$WASM"/*.results; do
  [ -f "$r" ] || continue
  suite=$(basename "$r" .results)
  n=$NATIVE/$suite.results
  if [ ! -f "$n" ]; then
    echo "A4 $suite: no native results" >&2
    bad=1
    continue
  fi
  echo "| $suite | $(grep -c '^SKIP' "$r" || true) | $(grep -c '^SKIP' "$n" || true) |"
  extra=$(awk -F '\t' 'FNR == NR { if ($1 == "SKIP") native[$2] = 1; next } $1 == "SKIP" && !($2 in native) { print $2 }' "$n" "$r")
  if [ -n "$extra" ]; then
    printf '%s\n' "$extra" | sed "s/^/A4 $suite: a SKIP on wasm32, not natively: /" >&2
    bad=1
  fi
done
listed=$(awk -F '\t' 'NR > 1 && NF >= 2 { print $1 "\t" $2 }' "$FAILURES")
if [ -n "$listed" ]; then
  while IFS="$(printf '\t')" read -r suite name; do
    n=$NATIVE/$suite.results
    if [ ! -f "$n" ] || ! awk -F '\t' -v t="$name" '$1 == "OK" && $2 == t { found = 1 } END { exit !found }' "$n"; then
      echo "A3 $suite: listed, but does not pass natively: $name" >&2
      bad=1
    fi
  done <<EOF
$listed
EOF
fi
exit "$bad"
