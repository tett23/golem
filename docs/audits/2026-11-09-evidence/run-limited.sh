#!/bin/sh
# Runs COMMAND as a child process with a time limit (seconds) and reports
# the exit status and the wall time. The GHC heap limit is passed by the
# caller as +RTS -M... -RTS. Only the child started here is killed.
#
#   run-limited.sh SECONDS COMMAND [ARG...]
set -u
limit=$1; shift
start=$(date +%s)
"$@" & pid=$!
t=0
while kill -0 "$pid" 2>/dev/null; do
  sleep 1; t=$((t + 1))
  if [ "$t" -ge "$limit" ]; then kill -9 "$pid" 2>/dev/null; echo "killed after ${limit}s" >&2; break; fi
done
wait "$pid"; rc=$?
echo "exit=$rc wall=$(( $(date +%s) - start ))s" >&2
exit "$rc"
