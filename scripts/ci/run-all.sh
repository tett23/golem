#!/bin/sh
# Runs shell scripts at the same time and prints their outputs one after
# another, in the order of the arguments, once all have ended. The
# scripts-macos job of .github/workflows/ci.yml runs the six tests of the
# scripts with it, on every core of the runner (docs/adr/0154).
#
#   run-all.sh [-t SECONDS] SCRIPT...
#
# Each SCRIPT runs as `sh SCRIPT`, with no standard input, its standard
# output and error together. Each output comes after a line
# `==> SCRIPT: exit CODE, SECONDS s`. The exit code is 0 when every script
# succeeded; otherwise 1, with a line on stderr for each failed script.
#
# With -t SECONDS, a script still running SECONDS seconds after the start
# is stopped with kill: its output, as far as it wrote it, comes after
# `==> SCRIPT: timed out after SECONDS s`, and stderr has
# `run-all: SCRIPT timed out (SECONDS s)`. The processes the script started
# may go on, with their output going to the file of the script alone.
set -u
usage() { echo "usage: run-all.sh [-t SECONDS] SCRIPT..." >&2; exit 2; }
LIMIT=
if [ "${1-}" = -t ]; then
  [ $# -ge 2 ] || usage
  case $2 in
    [1-9] | [1-9]*[0-9]) case $2 in *[!0-9]*) usage ;; esac ;;
    *) usage ;;
  esac
  LIMIT=$2
  shift 2
fi
[ $# -ge 1 ] || usage
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
i=0
runners=
for script in "$@"; do
  i=$((i + 1))
  # the shell of macOS writes a line when a job it waits for is stopped;
  # the stderr of the script itself goes to its file
  (
    start=$(date +%s)
    sh "$script" </dev/null >"$WORK/$i.out" 2>&1 &
    echo $! >"$WORK/$i.pid"
    code=0
    wait $! || code=$?
    printf '%s %s\n' "$code" "$(($(date +%s) - start))" >"$WORK/$i.end"
  ) 2>/dev/null &
  runners="$runners $!"
done
watchdog=
if [ -n "$LIMIT" ]; then
  # without the output of run-all.sh, so that a pipe after it does not wait
  # for this process
  (
    sleep "$LIMIT"
    j=0
    while [ "$j" -lt "$i" ]; do
      j=$((j + 1))
      if [ ! -f "$WORK/$j.end" ] && [ -f "$WORK/$j.pid" ]; then
        : >"$WORK/$j.timedout"
        kill "$(cat "$WORK/$j.pid")" 2>/dev/null
      fi
    done
  ) </dev/null >/dev/null 2>&1 &
  watchdog=$!
fi
# shellcheck disable=SC2086
wait $runners
[ -z "$watchdog" ] || kill "$watchdog" 2>/dev/null
status=0
i=0
for script in "$@"; do
  i=$((i + 1))
  if [ -f "$WORK/$i.timedout" ]; then
    printf '==> %s: timed out after %s s\n' "$script" "$LIMIT"
    cat "$WORK/$i.out"
    printf 'run-all: %s timed out (%s s)\n' "$script" "$LIMIT" >&2
    status=1
    continue
  fi
  read -r code seconds <"$WORK/$i.end"
  printf '==> %s: exit %s, %s s\n' "$script" "$code" "$seconds"
  cat "$WORK/$i.out"
  if [ "$code" != 0 ]; then
    printf 'run-all: %s failed (exit %s)\n' "$script" "$code" >&2
    status=1
  fi
done
exit "$status"
