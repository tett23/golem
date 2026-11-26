#!/bin/sh
# Golem ADR 0352: compare the transcribed predicates of Pagination.lean
# with the original predicates of pagination.als on sampled inputs.
# DiffAlloy.lean prints one Alloy command per input; each command fixes
# the input and states that every predicate holds of exactly the
# placements Lean computes, so each must have an instance.
# Usage: check-alloy-diff.sh [stride]  (every stride-th input of three or
# four items; all inputs of at most two items)
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
stride=${1:-97}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

lean -o "$tmp/Pagination.olean" "$root/experiments/pagination-proof/Pagination.lean"
LEAN_PATH="$tmp" lean --run "$root/experiments/pagination-proof/DiffAlloy.lean" "$stride" \
  > "$tmp/diff.als"
commands=$(grep -c '^run diff' "$tmp/diff.als")

cp "$root/docs/golem-layout/models/pagination.als" "$tmp/all.als"
cat "$tmp/diff.als" >> "$tmp/all.als"
JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$tmp" "${ALLOY:-alloy6}" exec -q -t text \
  -c 'diff*' -o - "$tmp/all.als" > "$tmp/result"

grep -o 'skolem \$diff[0-9]*_c' "$tmp/result" | sed 's/skolem \$\(diff[0-9]*\)_c/\1/' \
  | sort -u > "$tmp/found"
grep '^run diff' "$tmp/diff.als" | sed 's/^run \(diff[0-9]*\) .*/\1/' | sort -u > "$tmp/all"
missing=$(comm -23 "$tmp/all" "$tmp/found")
if [ -n "$missing" ]; then
  echo "transcription disagrees with pagination.als on: $missing" >&2
  exit 1
fi
echo "$commands sampled inputs agree with pagination.als"
