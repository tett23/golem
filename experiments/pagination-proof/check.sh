#!/bin/sh
# Golem ADR 0352: every Alloy command must have a Lean counterpart.
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
model=$root/docs/golem-layout/models/pagination.als
expected=$root/docs/golem-layout/models/expected.txt
nightly=$root/docs/golem-layout/models/nightly.txt
proof=$root/experiments/pagination-proof/Pagination.lean
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

sed -n 's/^run[[:space:]][[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$model" | sort > "$tmp/model"
awk '$1 !~ /^#/ && NF { print $1 }' "$expected" "$nightly" | sort > "$tmp/listed"
diff -u "$tmp/model" "$tmp/listed"
[ "$(wc -l < "$tmp/model" | tr -d ' ')" -eq 42 ]
[ -f "$proof" ] || { echo "missing Lean proof: $proof" >&2; exit 1; }

missing=0
while IFS= read -r name; do
  grep -Eq "^(theorem|def|example) [[:space:]]*${name}([[:space:]]|:)" "$proof" || {
    echo "missing Lean counterpart: $name" >&2
    missing=$((missing + 1))
  }
done < "$tmp/model"
if [ "$missing" -gt 0 ]; then
  echo "$missing of 42 Alloy commands lack a Lean counterpart" >&2
  exit 1
fi

if grep -En '(^|[^A-Za-z])(sorry|admit|axiom)([^A-Za-z]|$)' "$proof"; then
  echo "unproved Lean declaration" >&2
  exit 1
fi

lean=${LEAN:-lean}
"$lean" "$proof"
echo "42 Alloy commands have checked Lean counterparts"
