#!/bin/sh
# The limits of the test suites of CI, scripts/ci/suite-limits.tsv, which
# the test wrapper suite-timeout.sh holds each suite to (docs/adr ADR 0292).
#
#   suite-limits.sh < LINES               writes the table
#   suite-limits.sh --fetch N > LINES     the lines of the last N pushes to main
#   suite-limits.sh --check [TABLE [MODULES]]
#   suite-limits.sh --set ARCH SUITE SECONDS [TABLE]
#
# The input is the lines that suite-timeout.sh writes for a suite that
# finished ("SUITE: finished in SECONDS seconds", with or without ", over
# its limit ..."), each after its architecture (uname -m) and a tab; other
# lines, and the text before the name of the suite (the time of a log), are
# left out. For each architecture and suite the limit is max(10, ceil(2 m))
# seconds, where m is the median of the seconds; the median of an even
# number of values is the mean of the two in the middle, as in timings.sh.
# The table is ARCHITECTURE<tab>SUITE<tab>SECONDS, one row a suite, sorted,
# after a comment line.
#
# --fetch chooses the last N successful runs of ci.yml for a push to main
# that ran the tests, and writes those lines of the logs of their runners of
# the tests (the jobs build (RUNNER, tests-...)), the architecture read from
# the runner: aarch64 for ubuntu-24.04-arm, x86_64 for the others. The runs
# and jobs are read with gh, the logs with curl from the same API, as the
# ci job does (docs/adr/0245 section 6). GH_REPO chooses the repository,
# tett23/golem unless given.
#
# --set rewrites the row of ARCH and SUITE of TABLE (scripts/ci/suite-limits.tsv
# unless given) to the limit max(10, ceil(2 t)) of SECONDS t alone, for a
# suite that grew by added tests: t is the seconds of the CI of the pull
# request (docs/adr ADR 0301). Other rows stay. Without exactly one such row
# it changes nothing and fails.
#
# --check fails unless TABLE (scripts/ci/suite-limits.tsv unless given) has
# exactly one row for each suite of test-suites.sh driver and rest (of
# MODULES, modules/ unless given) on each of x86_64 and aarch64, and no row
# of another suite.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)

case "${1-}" in
  --check)
    TABLE=${2:-$HERE/suite-limits.tsv}
    MODULES=${3:-$HERE/../../modules}
    [ -f "$TABLE" ] || { echo "suite-limits: no table $TABLE" >&2; exit 1; }
    SUITES=$({ sh "$HERE/test-suites.sh" driver "$MODULES"; sh "$HERE/test-suites.sh" rest "$MODULES"; } | sed 's/.*:test://')
    printf '%s\n' "$SUITES" | awk -F '\t' '
      NR == FNR { if ($0 != "") { want["x86_64\t" $0] = 1; want["aarch64\t" $0] = 1 } next }
      /^#/ || $0 == "" { next }
      { k = $1 "\t" $2; seen[k]++ }
      END {
        bad = 0
        for (k in want) if (seen[k] != 1) { split(k, p, "\t"); printf "suite-limits: %s on %s has %d rows, not one\n", p[2], p[1], seen[k] + 0 > "/dev/stderr"; bad = 1 }
        for (k in seen) if (!(k in want)) { split(k, p, "\t"); printf "suite-limits: %s on %s is not a suite of test-suites.sh\n", p[2], p[1] > "/dev/stderr"; bad = 1 }
        exit bad
      }' - "$TABLE"
    exit
    ;;
  --fetch)
    [ $# -eq 2 ] || { echo "usage: suite-limits.sh --fetch N" >&2; exit 2; }
    N=$2
    REPO=${GH_REPO:-tett23/golem}
    TOKEN=$(gh auth token)
    LOGS=$(mktemp -d)
    trap 'rm -rf "${LOGS:?}"' EXIT
    found=0
    for run in $(gh run list --repo "$REPO" --workflow ci.yml --branch main --event push --status success --limit 200 --json databaseId --jq '.[].databaseId'); do
      [ "$found" -lt "$N" ] || break
      jobs=$(gh api "repos/$REPO/actions/runs/$run/jobs?per_page=100" --paginate \
        --jq '.jobs[] | select(.name | test("^build \\(.*, tests-")) | select(.conclusion == "success") | "\(.id)\t\(.name)"')
      [ -n "$jobs" ] || continue
      found=$((found + 1))
      printf '%s\n' "$jobs" | while IFS="$(printf '\t')" read -r id name; do
        case "$name" in *ubuntu-24.04-arm*) arch=aarch64 ;; *) arch=x86_64 ;; esac
        curl -fsSL --retry 5 --retry-all-errors -H "Authorization: Bearer $TOKEN" \
          "https://api.github.com/repos/$REPO/actions/jobs/$id/logs" -o "$LOGS/$id.log"
        grep -E '[^ ]+: finished in [0-9.]+ seconds' "$LOGS/$id.log" | sed "s/^/$arch$(printf '\t')/"
      done
    done
    [ "$found" -eq "$N" ] || { echo "suite-limits: only $found runs of the tests found" >&2; exit 1; }
    exit 0
    ;;
  --set)
    [ $# -eq 4 ] || [ $# -eq 5 ] || { echo "usage: suite-limits.sh --set ARCH SUITE SECONDS [TABLE]" >&2; exit 2; }
    ARCH=$2 SUITE=$3 T=$4
    TABLE=${5:-$HERE/suite-limits.tsv}
    case $T in
      '' | .* | *. | *[!0-9.]* | *.*.*) echo "suite-limits: $T is not a number of seconds" >&2; exit 2 ;;
    esac
    [ -f "$TABLE" ] || { echo "suite-limits: no table $TABLE" >&2; exit 1; }
    NEW=$(awk -F '\t' -v a="$ARCH" -v s="$SUITE" -v t="$T" '
      BEGIN { OFS = "\t"; lim = int(2 * t); if (lim < 2 * t) lim++; if (lim < 10) lim = 10 }
      !/^#/ && $1 == a && $2 == s { $3 = lim; n++ }
      { print }
      END { exit n == 1 ? 0 : 1 }' "$TABLE") || { echo "suite-limits: $TABLE has no one row of $SUITE on $ARCH" >&2; exit 1; }
    printf '%s\n' "$NEW" >"$TABLE"
    exit 0
    ;;
  "") ;;
  *) echo "usage: suite-limits.sh [--fetch N | --check [TABLE [MODULES]] | --set ARCH SUITE SECONDS [TABLE]] < LINES" >&2; exit 2 ;;
esac

OUT=$(awk -F '\t' '
  {
    if (!match($2, /[^ ]+: finished in [0-9.]+ seconds/)) next
    line = substr($2, RSTART, RLENGTH)
    suite = line; sub(/: finished in .*/, "", suite)
    s = line; sub(/.*: finished in /, "", s); sub(/ seconds$/, "", s)
    k = $1 "\t" suite
    n[k]++
    v[k, n[k]] = s + 0
  }
  END {
    for (k in n) {
      m = n[k]
      for (i = 1; i <= m; i++) w[i] = v[k, i]
      for (i = 2; i <= m; i++) {
        t = w[i]
        for (j = i - 1; j >= 1 && w[j] > t; j--) w[j + 1] = w[j]
        w[j + 1] = t
      }
      med = (m % 2 == 1) ? w[(m + 1) / 2] : (w[m / 2] + w[m / 2 + 1]) / 2
      lim = int(2 * med)
      if (lim < 2 * med) lim++
      if (lim < 10) lim = 10
      print k "\t" lim
    }
  }')
[ -n "$OUT" ] || { echo "suite-limits: no line of a suite that finished" >&2; exit 1; }
printf '# architecture, suite, seconds: max(10, ceil(2 m)), m the median of the last runs (scripts/ci/suite-limits.sh, docs/adr ADR 0292)\n'
printf '%s\n' "$OUT" | LC_ALL=C sort
