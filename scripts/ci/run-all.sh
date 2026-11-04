#!/bin/sh
# Runs shell scripts at the same time and prints their outputs one after
# another, in the order of the arguments, once all have ended. The
# scripts-macos job of .github/workflows/ci.yml runs the six tests of the
# scripts with it, on every core of the runner.
#
#   run-all.sh SCRIPT...
#
# Each SCRIPT runs as `sh SCRIPT`, with no standard input, its standard
# output and error together. Each output comes after a line
# `==> SCRIPT: exit CODE, SECONDS s`. The exit code is 0 when every script
# succeeded; otherwise 1, with a line on stderr for each failed script.
set -u
[ $# -ge 1 ] || { echo "usage: run-all.sh SCRIPT..." >&2; exit 2; }
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
i=0
for script in "$@"; do
  i=$((i + 1))
  (
    start=$(date +%s)
    code=0
    sh "$script" </dev/null >"$WORK/$i.out" 2>&1 || code=$?
    printf '%s %s\n' "$code" "$(($(date +%s) - start))" >"$WORK/$i.end"
  ) &
done
wait
status=0
i=0
for script in "$@"; do
  i=$((i + 1))
  read -r code seconds <"$WORK/$i.end"
  printf '==> %s: exit %s, %s s\n' "$script" "$code" "$seconds"
  cat "$WORK/$i.out"
  if [ "$code" != 0 ]; then
    printf 'run-all: %s failed (exit %s)\n' "$script" "$code" >&2
    status=1
  fi
done
exit "$status"
