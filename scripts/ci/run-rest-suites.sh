#!/bin/sh
# Run the complete list of one rest part serially (root ADR 0481).
# Keep Cabal's package configuration and each suite's environment intact.
set -eu
usage() {
  echo "usage: run-rest-suites.sh rest-a|rest-b" >&2
  exit 2
}
[ "$#" -eq 1 ] || usage
case "$1" in rest-a | rest-b) ;; *) usage ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
if targets=$(sh "$HERE/test-suites.sh" "$1"); then
  :
else
  exit 1
fi
failed=0
while IFS= read -r target; do
  [ -n "$target" ] || continue
  if cabal test --jobs=1 "$target"; then
    :
  else
    failed=1
  fi
done <<TARGETS
$targets
TARGETS
exit "$failed"
