#!/bin/sh
# The time of each area of the enumeration tests on the settings of pull
# requests (docs/adr ADR 0281, its section 2; docs/adr ADR 0286), the first
# step of the areas of .github/workflows/enum.yml:
#
#   enum-timings.sh [WORKFLOW]           writes the table of the times
#   enum-timings.sh --list [WORKFLOW]    writes the areas, one per line
#   enum-timings.sh --median TABLE...    writes the medians of the tables
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
# Without an option, the executable of golem-layout-test that
# `cabal list-bin` names runs once an area, with -p and the pattern of the
# area, in modules/golem-layout as cabal test runs it, and with no variable
# GOLEM_ENUM_* set, as on pull requests; the time of the area is the wall
# clock from just before it starts to just after it ends, without the
# time cabal takes to plan and check the build (docs/adr ADR 0286, M1).
# The test suite must be built before (cabal build golem-layout-test).
# A Markdown table is written: one row per area, its seconds against the
# budget of 10 seconds, then the sum against the budget of 30 seconds. A
# time over its budget is marked, and never fails the script; tests that
# fail do, after every area has run, with a row that says so. CABAL
# chooses the cabal to run and CLOCK a command that writes the seconds
# since some point (for the tests); the clock is date, to the nanosecond
# where it can.
#
# --median reads tables written without an option, one a job, and writes
# one row per area with the seconds of each table and their median, then
# the sum of each table and the median of the sums, which is not the sum
# of the medians of the areas (M2). The median of an even number of values
# is the mean of the two in the middle, as in timings.sh. A median over
# its budget is marked, and only a median (M3); nothing fails on a time.
# Tables whose areas (their variables and patterns, in order) differ make
# no table, and the script fails (M4).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "${1-}" = --median ]; then
  shift
  [ $# -ge 1 ] || { echo "usage: enum-timings.sh --median TABLE..." >&2; exit 2; }
  for t in "$@"; do
    [ -f "$t" ] || { echo "enum-timings: no table $t" >&2; exit 2; }
  done
  # each table is read into its areas, "VAR<tab>PATTERN", and its seconds;
  # the table is written only when every table has the same areas
  awk '
    function cells(line, c,   n) {
      sub(/^\| /, "", line); sub(/ \|$/, "", line)
      return split(line, c, / \| /)
    }
    function median(k, m,   i, j, v, t, s) {
      for (i = 1; i <= m; i++) v[i] = secs[i, k] + 0
      for (i = 2; i <= m; i++) {
        t = v[i]
        for (j = i - 1; j >= 1 && v[j] > t; j--) v[j + 1] = v[j]
        v[j + 1] = t
      }
      s = (m % 2 == 1) ? v[(m + 1) / 2] : (v[m / 2] + v[m / 2 + 1]) / 2
      return sprintf("%.2f", s)
    }
    FNR == 1 { tables++; rows = 0 }
    /^\| `/ {
      n = cells($0, c)
      if (n < 5) { bad = 1; next }
      pat = c[2]
      for (i = 3; i <= n - 3; i++) pat = pat " | " c[i]
      rows++
      key = c[1] "\t" pat
      if (tables == 1) { area[rows] = key; areas = rows }
      else if (area[rows] != key) { bad = 1 }
      secs[tables, rows] = c[n - 2]
      next
    }
    /^\| 和 \|/ {
      # the cell of the area is empty: split at every bar
      split($0, c, /\|/)
      sums[tables] = c[4]
      gsub(/ /, "", sums[tables])
      if (rows != areas) bad = 1
      summed[tables] = 1
      next
    }
    END {
      if (tables != ARGC - 1) bad = 1
      for (i = 1; i <= tables; i++) if (!summed[i]) bad = 1
      if (areas == 0) bad = 1
      if (bad) { print "enum-timings: the tables do not have the same areas" > "/dev/stderr"; exit 1 }
      head = "| 範囲 | `-p` の式 |"; rule = "| --- | --- |"
      for (i = 1; i <= tables; i++) { head = head " " i " |"; rule = rule " --- |" }
      print head " 中央値 | 予算 |"
      print rule " --- | --- |"
      for (k = 1; k <= areas; k++) {
        split(area[k], vp, "\t")
        line = "| " vp[1] " | " substr(area[k], length(vp[1]) + 2) " |"
        for (i = 1; i <= tables; i++) line = line " " secs[i, k] " |"
        m = median(k, tables)
        print line " " m " | " (m + 0 > 10 ? "10 秒を超える" : "10 秒以内") " |"
      }
      line = "| 和 | |"
      for (i = 1; i <= tables; i++) { line = line " " sums[i] " |"; secs[i, "sum"] = sums[i] }
      m = median("sum", tables)
      print line " " m " | " (m + 0 > 30 ? "30 秒を超える" : "30 秒以内") " |"
    }
  ' "$@"
  exit
fi

LIST=false
if [ "${1-}" = --list ]; then
  LIST=true
  shift
fi
[ $# -le 1 ] || { echo "usage: enum-timings.sh [--list] [WORKFLOW] | --median TABLE..." >&2; exit 2; }
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

# the executable, found before any clock is read (M1)
BIN=$($CABAL list-bin golem-layout-test </dev/null) && [ -n "$BIN" ] || {
  echo "enum-timings: cabal list-bin golem-layout-test names no executable" >&2
  exit 1
}
# the directory cabal test runs the suite in: the tests read test/ there
PKG_DIR=$HERE/../../modules/golem-layout

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
  if (cd "$PKG_DIR" && "$BIN" -p "$pat") </dev/null >&2; then result=通る; else result=落ちる; FAILED=$((FAILED + 1)); fi
  end=$(now)
  secs=$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.2f", b - a }')
  SUM=$(awk -v a="$SUM" -v b="$secs" 'BEGIN { printf "%.2f", a + b }')
  budget=$(awk -v s="$secs" 'BEGIN { print (s > 10 ? "10 秒を超える" : "10 秒以内") }')
  printf '| `%s` | `%s` | %s | %s | %s |\n' "$var" "$pat" "$secs" "$budget" "$result"
done <"$LIST_FILE"
budget=$(awk -v s="$SUM" 'BEGIN { print (s > 30 ? "30 秒を超える" : "30 秒以内") }')
printf '| 和 | | %s | %s | |\n' "$SUM" "$budget"
[ "$FAILED" -eq 0 ]
