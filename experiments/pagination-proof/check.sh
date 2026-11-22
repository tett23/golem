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
  grep -Eq "^theorem [[:space:]]*${name}([[:space:]]|:)" "$proof" || {
    echo "missing Lean counterpart: $name" >&2
    missing=$((missing + 1))
  }
done < "$tmp/model"
if [ "$missing" -gt 0 ]; then
  echo "$missing of 42 Alloy commands lack a Lean counterpart" >&2
  exit 1
fi

# The commands of docs/adr/0204, docs/adr/0206 and golem-layout ADR 0026 are also stated on the
# transcribed predicates, in namespace Alloy.
transcribed='someFits noneMeetsAll noneMeetsAllButGreedy greedyOrphan greedyWidow
greedyKeepHeading greedyFigure orphanEmpty widowEmpty keepHeadingEmpty orphanWidow
keepHeadingOrphan keepHeadingWidow keepHeadingFigure figureOrder figureEmpty tallFigure
strictAfterHeadings relaxedAfterHeadings rectoKept rectoEnds keep21 decidedSome
waitingBlankSome waitingBlankNone waitingBlankAllButGreedy blankFigureOrder
blankBeforeWaiting25 blankRules25'
sed -n '/^namespace Alloy$/,/^end Alloy$/p' "$proof" > "$tmp/alloy"
for name in $transcribed; do
  grep -Eq "^theorem ${name}([[:space:]]|:)" "$tmp/alloy" || {
    echo "missing transcribed Lean counterpart: Alloy.$name" >&2
    missing=$((missing + 1))
  }
done
if [ "$missing" -gt 0 ]; then
  echo "$missing transcribed commands lack a Lean counterpart" >&2
  exit 1
fi

if grep -En '(^|[^A-Za-z])(sorry|admit|axiom)([^A-Za-z]|$)' "$proof"; then
  echo "unproved Lean declaration" >&2
  exit 1
fi

lean=${LEAN:-lean}
"$lean" "$proof"
echo "42 Alloy commands have checked Lean counterparts, 29 of them on the transcription"
