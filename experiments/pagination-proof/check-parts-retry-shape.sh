#!/bin/sh
# Root ADR 0352: retain the parts recursion while checking every retry entry.
# Optional arguments select proof/model copies for negative checks.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
proof=${1:-$root/experiments/pagination-proof/RetryPrefix.lean}
model=${2:-$root/experiments/pagination-proof/Physical.lean}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

definition() {
  awk -v signature="def $1 (" '
    index($0, signature) == 1 { copy = 1 }
    /^decreasing_by/ { if (copy) exit }
    copy { print }
  ' "$2"
}

grep -Fqx "  retryEntryValid env region breaker lastWanted limit k isStart start before at' ∧" "$proof" || {
  echo 'missing parts retry entry condition' >&2
  exit 1
}
definition parts "$model" | sed \
  -e 's/def parts (/def partsRetryEntriesSafe (/' \
  -e 's/parts env/partsRetryEntriesSafe env/g' \
  -e 's/: Except Failure St :=/: Prop :=/' \
  -e 's/\.error e => \.error e/.error e => True/' \
  -e 's/\.error (\.noProgress 0)/True/g' \
  -e 's/\.ok (hold (checkWaits placed))/True/g' >"$tmp/parts"
definition partsRetryEntriesSafe "$proof" | sed \
  -e '/^  retryEntryValid .* ∧$/d' \
  -e 's/^  (match/  match/' \
  -e '/^)$/d' >"$tmp/guard"
[ -s "$tmp/parts" ] && [ -s "$tmp/guard" ] || {
  echo 'missing parts or partsRetryEntriesSafe definition' >&2
  exit 1
}
diff -u "$tmp/parts" "$tmp/guard"
