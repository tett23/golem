#!/bin/sh
# The budget of 60 minutes of the sum of the times of the areas of
# .github/workflows/enum.yml, judged on every run (root ADR 0415, its
# section 3; docs/adr ADR 0281, docs/adr ADR 0304):
#
#   enum-budget.sh step SCRIPT    runs SCRIPT, the shell of a step
#   enum-budget.sh judge FILE     sums the times recorded in FILE
#
# step is the shell of the step that times the areas and of the step of
# every area (shell: sh scripts/ci/enum-budget.sh step {0}): it runs
# SCRIPT, the run: of the step that GitHub Actions wrote to a file, with
# sh -e, and adds a line of the start and the end of the run, the seconds
# of date +%s separated by a tab, to $RUNNER_TEMP/enum-steps.tsv, whether
# SCRIPT passes or fails. Its exit code is that of SCRIPT.
#
# judge sums the seconds from the start to the end of each line of FILE,
# writes the sum, and fails when it is over 3600 seconds. 3600 seconds or
# less passes. A FILE that does not exist is a run whose steps were all
# left out (main has not changed since the last successful run): its sum
# is 0. It reads nothing but FILE, and no API of GitHub.
#
# Exit code 0: SCRIPT passed, or the sum is within the budget; 1: the sum
# is over the budget; 2: a usage error, or a line of FILE that is not a
# start and an end not before it. step exits with the code of SCRIPT.
set -u
BUDGET=3600
usage() {
  echo "usage: enum-budget.sh step SCRIPT | judge FILE" >&2
  exit 2
}
[ $# -eq 2 ] || usage
case "$1" in
  step)
    [ -n "${RUNNER_TEMP:-}" ] || { echo "enum-budget: RUNNER_TEMP is not set" >&2; exit 2; }
    start=$(date +%s)
    code=0
    sh -e "$2" || code=$?
    end=$(date +%s)
    printf '%s\t%s\n' "$start" "$end" >>"$RUNNER_TEMP/enum-steps.tsv"
    exit "$code"
    ;;
  judge)
    if [ -f "$2" ]; then
      sum=$(awk -F '\t' '
        NF != 2 || $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ || $2 + 0 < $1 + 0 {
          printf "enum-budget: line %d is not a start and an end: %s\n", NR, $0 > "/dev/stderr"
          bad = 1
          exit
        }
        { s += $2 - $1 }
        END { if (bad) exit 2; print s + 0 }
      ' "$2") || exit 2
    else
      sum=0
    fi
    echo "the areas took $sum seconds of $BUDGET"
    if [ "$sum" -gt "$BUDGET" ]; then
      echo "enum-budget: the areas took $sum seconds, over the budget of $BUDGET (root ADR 0415)" >&2
      exit 1
    fi
    ;;
  *) usage ;;
esac
