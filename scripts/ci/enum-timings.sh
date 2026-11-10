#!/bin/sh
# The time of each area of the enumeration tests on the settings of pull
# requests (docs/adr ADR 0281, its section 2), the first step of the areas
# of .github/workflows/enum.yml:
#
#   enum-timings.sh [WORKFLOW]          writes the table of the times
#   enum-timings.sh --list [WORKFLOW]   writes the areas, one per line
#
# An area is a step of WORKFLOW (.github/workflows/enum.yml unless given)
# that runs one pattern of golem-layout-test,
#
#   run: cabal test golem-layout-test --test-option=-p --test-option='PATTERN'
#
# with the depth of the area in an environment variable GOLEM_ENUM_*DEPTH
# (GOLEM_ENUM_DEPTH for the pagination). --list writes, for each area in
# the order of the steps, its variable, its pattern and the condition of
# its step (its if:, or nothing), separated by tabs.
#
# Without --list, the tests of each area run with that command and no
# variable GOLEM_ENUM_* set, as on pull requests, and a Markdown table is
# written: one row per area, its seconds of wall clock against the budget
# of 10 seconds, then the sum against the budget of 30 seconds. A time
# over its budget is marked, and never fails the script; tests that fail
# do, after every area has run, with a row that says so. CABAL chooses the
# cabal to run and CLOCK a command that writes the seconds since some
# point (for the tests); the clock is date, to the nanosecond where it can.
set -u
LIST=false
if [ "${1-}" = --list ]; then
  LIST=true
  shift
fi
[ $# -le 1 ] || { echo "usage: enum-timings.sh [--list] [WORKFLOW]" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
WORKFLOW=${1:-$HERE/../../.github/workflows/enum.yml}
[ -f "$WORKFLOW" ] || { echo "enum-timings: no workflow $WORKFLOW" >&2; exit 2; }
CABAL=${CABAL:-cabal}

# the areas: a step starts at "      - " and ends before the next one
areas() {
  awk '
    function flush() {
      if (pat != "" && var != "") printf "%s\t%s\t%s\n", var, pat, cond
      pat = ""; var = ""; cond = ""
    }
    /^      - / { flush() }
    /^jobs:|^  [a-z]/ { flush() }
    {
      line = $0
      sub(/^      - /, "        ", line)
      if (line ~ /^        if: /) { cond = line; sub(/^        if: /, "", cond) }
      if (line ~ /^          GOLEM_ENUM_[A-Z0-9_]*DEPTH:/) { var = line; sub(/^ */, "", var); sub(/:.*/, "", var) }
      if (line ~ /^        run: cabal test golem-layout-test --test-option=-p --test-option=\047[^\047]*\047$/) {
        pat = line; sub(/^[^\047]*\047/, "", pat); sub(/\047$/, "", pat)
      }
    }
    END { flush() }
  ' "$WORKFLOW"
}

if [ "$LIST" = true ]; then
  areas
  exit 0
fi

now() {
  if [ -n "${CLOCK-}" ]; then
    $CLOCK
  else
    t=$(date +%s.%N)
    case "$t" in
      *N*) date +%s ;;
      *) printf '%s\n' "$t" ;;
    esac
  fi
}

TAB=$(printf '\t')
LIST_FILE=$(mktemp)
trap 'rm -f "$LIST_FILE"' EXIT
areas >"$LIST_FILE"
[ -s "$LIST_FILE" ] || { echo "enum-timings: no area in $WORKFLOW" >&2; exit 1; }

# no depth nor drawn inputs of the nightly job: the settings of pull requests
for v in $(env | sed -n 's/^\(GOLEM_ENUM_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$v"
done

printf '| 範囲 | `-p` の式 | 秒 | 予算 | テスト |\n'
printf '| --- | --- | --- | --- | --- |\n'
SUM=0
FAILED=0
while IFS="$TAB" read -r var pat _; do
  start=$(now)
  if $CABAL test golem-layout-test --test-option=-p "--test-option=$pat" </dev/null >&2; then result=通る; else result=落ちる; FAILED=$((FAILED + 1)); fi
  end=$(now)
  secs=$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.2f", b - a }')
  SUM=$(awk -v a="$SUM" -v b="$secs" 'BEGIN { printf "%.2f", a + b }')
  budget=$(awk -v s="$secs" 'BEGIN { print (s > 10 ? "10 秒を超える" : "10 秒以内") }')
  printf '| `%s` | `%s` | %s | %s | %s |\n' "$var" "$pat" "$secs" "$budget" "$result"
done <"$LIST_FILE"
budget=$(awk -v s="$SUM" 'BEGIN { print (s > 30 ? "30 秒を超える" : "30 秒以内") }')
printf '| 和 | | %s | %s | |\n' "$SUM" "$budget"
[ "$FAILED" -eq 0 ]
