#!/bin/sh
# Root ADR 0352: keep the local numbering guard on the recursion tree of parts.
# Optional arguments select proof/model copies for negative checks.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
proof=${1:-$root/experiments/pagination-proof/PartsNumberedEntries.lean}
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

grep -Fqx "  lineIds ((breaker at' before start).map (·.1)) = ids (base + before) (breaker at' before start).length ∧" "$proof" || {
  echo 'missing parts numbering entry condition' >&2
  exit 1
}
definition parts "$model" | sed \
  -e 's/def parts (/def partsNumberedEntriesSafe (/' \
  -e 's/parts env/partsNumberedEntriesSafe env/g' \
  -e 's/(follows : St → Bool) (hold : St → St)/(follows : St → Bool) (hold : St → St) (base : Nat)/' \
  -e 's/follows hold /follows hold base /g' \
  -e 's/: Except Failure St :=/: Prop :=/' \
  -e 's/\.error e => \.error e/.error e => True/' \
  -e 's/\.error (\.noProgress 0)/True/g' \
  -e 's/\.ok (hold (checkWaits placed))/True/g' >"$tmp/parts"
definition partsNumberedEntriesSafe "$proof" | sed \
  -e '/^  lineIds .* = ids (base + before).* ∧$/d' \
  -e 's/^  (match/  match/' \
  -e '/^)$/d' >"$tmp/guard"
[ -s "$tmp/parts" ] && [ -s "$tmp/guard" ] || {
  echo 'missing parts or partsNumberedEntriesSafe definition' >&2
  exit 1
}
diff -u "$tmp/parts" "$tmp/guard"
