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

# Theorem names carry the invariant number of root ADR 0352 (for example
# I3_someFits); a command matches a theorem whose name is the command name
# after that prefix.
theorems() {
  sed -n "s/^theorem[[:space:]][[:space:]]*I[0-9][0-9]*_\([A-Za-z0-9_]*\).*/\1/p" "$1" | sort -u
}
theorems "$proof" > "$tmp/theorems"

missing=0
while IFS= read -r name; do
  grep -Fqx "$name" "$tmp/theorems" || {
    echo "missing Lean counterpart: $name" >&2
    missing=$((missing + 1))
  }
done < "$tmp/model"
if [ "$missing" -gt 0 ]; then
  echo "$missing of 42 Alloy commands lack a Lean counterpart" >&2
  exit 1
fi

# Every command is also stated on the transcribed predicates, in namespace
# Alloy.
transcribed='someFits noneMeetsAll noneMeetsAllButGreedy greedyOrphan greedyWidow
greedyKeepHeading greedyFigure orphanEmpty widowEmpty keepHeadingEmpty orphanWidow
keepHeadingOrphan keepHeadingWidow keepHeadingFigure figureOrder figureEmpty tallFigure
strictAfterHeadings relaxedAfterHeadings rectoKept rectoEnds keep21 decidedSome
waitingBlankSome waitingBlankNone waitingBlankAllButGreedy blankFigureOrder
blankBeforeWaiting25 blankRules25
needSpaceSome needSpaceAllButGreedy needFigure needGreedy needMoreSome needMore27
needMoreSpace46 needMoreSpace46Here keepNone keepDefaultDiffers keepAllSome
needSpaceNone needMoreNone'
sed -n '/^namespace Alloy$/,/^end Alloy$/p' "$proof" > "$tmp/alloy"
theorems "$tmp/alloy" > "$tmp/alloy-theorems"
for name in $transcribed; do
  grep -Fqx "$name" "$tmp/alloy-theorems" || {
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
"$lean" -o "$tmp/Pagination.olean" "$proof"

# The whole pagination of the grid mode: every definition must be total
# and every theorem proved.
whole=$root/experiments/pagination-proof/Whole.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$whole"; then
  echo "unproved or unchecked Lean declaration in $whole" >&2
  exit 1
fi
"$lean" -o "$tmp/Whole.olean" "$whole"
echo "the whole pagination model is total and its theorems are proved"

# The boundary inputs of boundaryTableTests on Whole.lean's paginate,
# evaluated under the Env of Paginate/Decide.hs, against golem-layout's
# paginate (root ADR 0352). Boundary.lean is evaluated, not proved, so it
# may use partial; it must not decide anything by native code.
boundary=$root/experiments/pagination-proof/Boundary.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$boundary"; then
  echo "unchecked Lean declaration in $boundary" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$boundary" > "$tmp/boundary-lean"
(cd "$root" && cabal exec -v0 -- runghc -hide-all-packages -package=base \
  -package-id=golem-layout-0.1.0-inplace -package-id=golem-syntax-0.1.0-inplace \
  experiments/pagination-proof/Boundary.hs) > "$tmp/boundary-haskell"
diff -u "$tmp/boundary-haskell" "$tmp/boundary-lean"
inputs=$(grep -c '^[0-9]' "$tmp/boundary-lean")
echo "the $inputs boundary inputs give the same pages in Whole.lean and golem-layout"

# The values of the evaluation of Golem.Layout.KnuthPlass (badness,
# fitness, line demerits, cumulative widths, the demerits of the chosen
# breaks and the ratio and overflow of each line) on Pagination.lean's
# definitions, against golem-layout's breaker (root ADR 0352, condition 2).
values=$root/experiments/pagination-proof/CaptionValues.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$values"; then
  echo "unchecked Lean declaration in $values" >&2
  exit 1
fi
(cd "$root" && cabal exec -v0 -- runghc -hide-all-packages -package=base -package=text \
  -package-id=golem-layout-0.1.0-inplace \
  experiments/pagination-proof/CheckCaptionAssembly.hs --values) > "$tmp/caption-values"
sed -n 's/^out //p' "$tmp/caption-values" > "$tmp/caption-haskell"
LEAN_PATH="$tmp" "$lean" --run "$values" "$tmp/caption-values" | sed -n 's/^out //p' > "$tmp/caption-lean"
diff -u "$tmp/caption-haskell" "$tmp/caption-lean"
captions=$(grep -c '^in obs' "$tmp/caption-values")
echo "the evaluation of $captions caption breaks gives the same values in Pagination.lean and golem-layout"
echo "42 Alloy commands have checked Lean counterparts, all 42 on the transcription"
