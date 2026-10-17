#!/bin/sh
# The test wrapper of `cabal test` in CI: runs one test suite and stops it
# when it has not finished in SUITE_TIMEOUT seconds (600 by default), so
# that a hung suite fails in minutes and says so, instead of holding the
# job until its timeout. A deadlocked RTS cannot handle SIGTERM, so SIGKILL
# follows 10 seconds later.
#
#   cabal test all --test-wrapper="$PWD/scripts/ci/suite-timeout.sh"
#   suite-timeout.sh PROGRAM [ARGUMENTS...]
set -u
LIMIT=${SUITE_TIMEOUT:-600}
CODE=0
timeout -k 10 "$LIMIT" "$@" || CODE=$?
if [ "$CODE" -eq 124 ] || [ "$CODE" -eq 137 ]; then
  printf '%s: did not finish in %s seconds\n' "$(basename "$1")" "$LIMIT" >&2
fi
exit "$CODE"
