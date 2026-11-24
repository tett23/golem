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

# The free placement of root ADR 0397 (Paginate/Physical.hs): every
# definition must be total and every theorem proved.  It is checked in the
# background, beside Whole.lean, as the separators below need it.
physical=$root/experiments/pagination-proof/Physical.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$physical"; then
  echo "unproved or unchecked Lean declaration in $physical" >&2
  exit 1
fi
"$lean" -o "$tmp/Physical.olean" "$physical" &
physicalPid=$!

# The whole pagination of the grid mode: every definition must be total
# and every theorem proved.
whole=$root/experiments/pagination-proof/Whole.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$whole"; then
  echo "unproved or unchecked Lean declaration in $whole" >&2
  exit 1
fi
"$lean" -o "$tmp/Whole.olean" "$whole"
echo "the whole pagination model is total and its theorems are proved"

# The footnote lines of the grid mode, note by note (WholeNotes.lean):
# every theorem proved.
wholeNotes=$root/experiments/pagination-proof/WholeNotes.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$wholeNotes"; then
  echo "unproved or unchecked Lean declaration in $wholeNotes" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/WholeNotes.olean" "$wholeNotes"
echo "every footnote line of the grid mode is placed once, note by note"

# The separators of root ADR 0398 on the flows of Whole.lean: every
# definition must be total and every theorem proved.  The manuscripts of
# SeparatorBoundary.hs are laid out by golem-typeset in the background,
# to be compared below.
separator=$root/experiments/pagination-proof/Separator.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$separator"; then
  echo "unproved or unchecked Lean declaration in $separator" >&2
  exit 1
fi
(cd "$root" && LEAN_PATH="$tmp" "$lean" -o "$tmp/Separator.olean" "$separator")
echo "the separator flows are total and their theorems are proved"
# The manuscripts in the six modes of SeparatorBoundary.hs: the grid and
# the free placement, without and with boxes, ruled blocks and items of
# lists, and with a no-break after the paragraph a separator is held with.
modes='grid free blocks blocks-free holds holds-free'
separatorPids=
for mode in $modes; do
  case $mode in
    grid) args= ;;
    free) args=free ;;
    blocks) args=blocks ;;
    blocks-free) args='blocks free' ;;
    holds) args=holds ;;
    holds-free) args='holds free' ;;
  esac
  # shellcheck disable=SC2086
  (cd "$root" && cabal exec -v0 -- runghc --ghc-arg=-XGHC2021 --ghc-arg=-XLambdaCase \
    --ghc-arg=-XOverloadedStrings --ghc-arg=-XDerivingStrategies --ghc-arg=-imodules/golem-driver/test \
    experiments/pagination-proof/SeparatorBoundary.hs $args) > "$tmp/separator-haskell-$mode" &
  separatorPids="$separatorPids $!"
done

# The boundary inputs of boundaryTableTests on Whole.lean's paginate,
# evaluated under the Env of Paginate/Decide.hs, against golem-layout's
# paginate (root ADR 0352). Boundary.lean is evaluated, not proved, so it
# may use partial; it must not decide anything by native code.
boundary=$root/experiments/pagination-proof/Boundary.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$boundary"; then
  echo "unchecked Lean declaration in $boundary" >&2
  exit 1
fi
# The inputs are evaluated in four parts side by side, in order.
parts=4
pids=
part=0
while [ "$part" -lt "$parts" ]; do
  LEAN_PATH="$tmp" "$lean" --run "$boundary" "$part" "$parts" > "$tmp/boundary-lean.$part" &
  pids="$pids $!"
  part=$((part + 1))
done
for pid in $pids; do
  wait "$pid"
done
part=0
: > "$tmp/boundary-lean"
while [ "$part" -lt "$parts" ]; do
  cat "$tmp/boundary-lean.$part" >> "$tmp/boundary-lean"
  part=$((part + 1))
done
(cd "$root" && cabal exec -v0 -- runghc -hide-all-packages -package=base \
  -package-id=golem-layout-0.1.0-inplace -package-id=golem-syntax-0.1.0-inplace -package-id=golem-length-0.1.0-inplace \
  experiments/pagination-proof/Boundary.hs) > "$tmp/boundary-haskell"
diff -u "$tmp/boundary-haskell" "$tmp/boundary-lean"
inputs=$(grep -c '^[0-9]' "$tmp/boundary-lean")
echo "the $inputs boundary inputs give the same pages in Whole.lean and golem-layout"

# The manuscripts of SeparatorBoundary.hs on the flows Separator.lean
# makes, Whole.lean's paginate and the G07134 of Separator.lean, against
# golem-typeset's layoutPdf (root ADR 0352, root ADR 0398).
# SeparatorBoundary.lean is evaluated, not proved; it imports
# Boundary.lean for its Env and prints by #eval, as main is Boundary.lean's.
sboundary=$root/experiments/pagination-proof/SeparatorBoundary.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$sboundary"; then
  echo "unchecked Lean declaration in $sboundary" >&2
  exit 1
fi
(cd "$root" && LEAN_PATH="$tmp" "$lean" -o "$tmp/Boundary.olean" "$boundary")
# The separators in the free placement (SeparatorPhysical.lean) and next
# to boxes, ruled blocks and book parts (SeparatorBlocks.lean): every
# definition must be total and every theorem proved.
wait "$physicalPid"
for model in SeparatorBlocks SeparatorPhysical; do
  file=$root/experiments/pagination-proof/$model.lean
  if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$file"; then
    echo "unproved or unchecked Lean declaration in $file" >&2
    exit 1
  fi
  (cd "$root" && LEAN_PATH="$tmp" "$lean" -o "$tmp/$model.olean" "$file")
done
echo "the separator flows of the free placement and next to boxes, ruled blocks and book parts are total and their theorems are proved"
leanPids=
for mode in $modes; do
  (cd "$root" && SEPARATOR_MODE=${mode#grid} LEAN_PATH="$tmp" "$lean" "$sboundary") > "$tmp/separator-lean-$mode" &
  leanPids="$leanPids $!"
done
for pid in $separatorPids $leanPids; do
  wait "$pid"
done
for mode in $modes; do
  diff -u "$tmp/separator-haskell-$mode" "$tmp/separator-lean-$mode"
  manuscripts=$(grep -c '^[0-9]' "$tmp/separator-lean-$mode")
  echo "the $manuscripts manuscripts ($mode) with separators give the same pages and G07134 in the Lean models and golem-typeset"
done

echo "the free placement model is total and its theorems are proved"

# The footnote lines of the free placement, note by note (PhysicalNotes.lean).
physicalNotes=$root/experiments/pagination-proof/PhysicalNotes.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$physicalNotes"; then
  echo "unproved or unchecked Lean declaration in $physicalNotes" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$physicalNotes"
echo "every footnote line of the free placement is placed once, note by note"

# The boundary inputs of PhysicalBoundary.hs on Physical.lean's paginate,
# against golem-layout's paginatePhysical (root ADR 0352).
pboundary=$root/experiments/pagination-proof/PhysicalBoundary.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$pboundary"; then
  echo "unchecked Lean declaration in $pboundary" >&2
  exit 1
fi
(cd "$root" && cabal exec -v0 -- runghc -hide-all-packages -package=base -package=containers -package=text \
  -package-id=golem-layout-0.1.0-inplace -package-id=golem-syntax-0.1.0-inplace \
  -package-id=golem-length-0.1.0-inplace -package-id=golem-doc-0.1.0-inplace \
  -package-id=golem-project-0.1.0-inplace \
  experiments/pagination-proof/PhysicalBoundary.hs) > "$tmp/physical-haskell"
LEAN_PATH="$tmp" "$lean" --run "$pboundary" "$tmp/physical-haskell" > "$tmp/physical-lean"
diff -u "$tmp/physical-haskell" "$tmp/physical-lean"
physicalInputs=$(grep -c '^in ' "$tmp/physical-lean")
wrapTrials=$(grep -c '^tw ' "$tmp/physical-lean")
echo "the $physicalInputs boundary inputs give the same pages in Physical.lean and golem-layout's paginatePhysical"
echo "the $wrapTrials trials beside a wrapped figure give the same parts in Physical.lean and trialParagraphPartLimit"

# The values of the evaluation of Golem.Layout.KnuthPlass (badness,
# fitness, line demerits, cumulative widths, the demerits of the chosen
# breaks and the ratio and overflow of each line) on Pagination.lean's
# definitions, and the pass, the breaks and the demerits of captionCompared,
# the breaker of Pagination.lean on that evaluation, against golem-layout's
# breaker (root ADR 0352, condition 2).
values=$root/experiments/pagination-proof/CaptionValues.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$values"; then
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
echo "the evaluation and the breaks of $captions captions are the same in Pagination.lean and golem-layout"
echo "42 Alloy commands have checked Lean counterparts, all 42 on the transcription"
