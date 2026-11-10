#!/bin/sh
# The test wrapper of `cabal test` in CI: runs one test suite and stops it
# when it has not finished in SUITE_TIMEOUT seconds (600 by default), so
# that a hung suite fails in minutes and says so, instead of holding the
# job until its timeout. A deadlocked RTS cannot handle SIGTERM, so SIGKILL
# follows 10 seconds later. A suite that finished, passed or failed, is
# said on stderr with its seconds, so that the times of the suites can be
# gathered from the logs to choose the suites of each runner of the tests
# (docs/adr/0244).
#
# A suite that finished in more seconds than its limit fails, even when it
# passed, and says so on the same line; a suite that has no limit for the
# architecture (uname -m) does not run, and fails (docs/adr ADR 0292). The
# limits are read from SUITE_LIMITS, scripts/ci/suite-limits.tsv unless
# given; an empty SUITE_LIMITS puts no limit, for running the wrapper by
# hand. The rows are ARCHITECTURE<tab>SUITE<tab>SECONDS; a line that
# starts with # is a comment.
#
#   cabal test all --test-wrapper="$PWD/scripts/ci/suite-timeout.sh"
#   suite-timeout.sh PROGRAM [ARGUMENTS...]
set -u
LIMIT=${SUITE_TIMEOUT:-600}
LIMITS=${SUITE_LIMITS-$(cd "$(dirname "$0")" && pwd)/suite-limits.tsv}
NAME=$(basename "$1")
MAX=
if [ -n "$LIMITS" ]; then
  ARCH=$(uname -m)
  [ -f "$LIMITS" ] && MAX=$(awk -F '\t' -v a="$ARCH" -v s="$NAME" '!/^#/ && $1 == a && $2 == s { print $3; exit }' "$LIMITS")
  if [ -z "$MAX" ]; then
    printf '%s: no limit in scripts/ci/suite-limits.tsv\n' "$NAME" >&2
    exit 1
  fi
fi
CODE=0
START=$(date +%s)
timeout -k 10 "$LIMIT" "$@" || CODE=$?
if [ "$CODE" -eq 124 ] || [ "$CODE" -eq 137 ]; then
  printf '%s: did not finish in %s seconds\n' "$NAME" "$LIMIT" >&2
  exit "$CODE"
fi
SECS=$(($(date +%s) - START))
if [ -n "$MAX" ] && [ "$SECS" -gt "$MAX" ]; then
  printf '%s: finished in %s seconds, over its limit of %s seconds (scripts/ci/suite-limits.tsv)\n' "$NAME" "$SECS" "$MAX" >&2
  [ "$CODE" -ne 0 ] || CODE=1
else
  printf '%s: finished in %s seconds\n' "$NAME" "$SECS" >&2
fi
exit "$CODE"
