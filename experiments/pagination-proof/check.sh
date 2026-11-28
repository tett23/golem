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
# Match the compiler that built the project instead of the system default.
# CABAL_PLAN and RUNGHC follow the parser proof exporter's overrides.
plan=${CABAL_PLAN:-$root/dist-newstyle/cache/plan.json}
compiler=$(jq -er '."compiler-id" | select(startswith("ghc-"))' "$plan")
runghc=${RUNGHC:-runghc-${compiler#ghc-}}
ghc=$(command -v "$compiler") || {
  echo "missing Cabal compiler $compiler" >&2
  exit 1
}
command -v "$runghc" >/dev/null || {
  echo "missing $runghc for Cabal compiler $compiler" >&2
  exit 1
}
echo "checking pagination with $compiler and $runghc"

# Support.hs imports libraries directly.  Cabal's project environment
# can register them as hidden, so expose the in-place package IDs just
# as the standalone layout checks below do.  This also prevents picking
# an installed copy of a library from another checkout.
driverCheck() {
  cabal exec -v0 -- "$runghc" -f "$ghc" --ghc-arg=-XGHC2021 --ghc-arg=-XLambdaCase \
    --ghc-arg=-XOverloadedStrings --ghc-arg=-XDerivingStrategies --ghc-arg=-imodules/golem-driver/test \
    -package-id=golem-assemble-0.1.0-inplace -package-id=golem-bibliography-0.1.0-inplace \
    -package-id=golem-doc-0.1.0-inplace -package-id=golem-driver-0.1.0-inplace \
    -package-id=golem-layout-0.1.0-inplace -package-id=golem-layout-spec-0.1.0-inplace \
    -package-id=golem-length-0.1.0-inplace -package-id=golem-pdf-0.1.0-inplace \
    -package-id=golem-project-0.1.0-inplace -package-id=golem-syntax-0.1.0-inplace \
    -package-id=golem-test-support-0.1.0-inplace -package-id=golem-typeset-0.1.0-inplace \
    -package-id=golem-unicode-0.1.0-inplace "$@"
}

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

# The order of the footnote lines of the grid mode (root ADR 0444 I1,
# WholeOrder.lean): every theorem proved.  It is checked in the background
# and waited for at the end.
wholeOrder=$root/experiments/pagination-proof/WholeOrder.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$wholeOrder"; then
  echo "unproved or unchecked Lean declaration in $wholeOrder" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$wholeOrder" > "$tmp/whole-order" 2>&1 &
wholeOrderPid=$!

# The rules of the ruled blocks of the grid mode (WholeRules.lean): every
# theorem proved.  It is checked in the background and waited for at the
# end.
wholeRules=$root/experiments/pagination-proof/WholeRules.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$wholeRules"; then
  echo "unproved or unchecked Lean declaration in $wholeRules" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$wholeRules" > "$tmp/whole-rules" 2>&1 &
wholeRulesPid=$!

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
# Where the ids of the slots the text leaves out come from in the grid
# mode (WholeSlots.lean).
wholeSlots=$root/experiments/pagination-proof/WholeSlots.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$wholeSlots"; then
  echo "unproved or unchecked Lean declaration in $wholeSlots" >&2
  exit 1
fi
(cd "$root" && LEAN_PATH="$tmp" "$lean" "$wholeSlots")
echo "the slots the text leaves out hold ids of the manuscript in the grid mode"
# The manuscripts in the ten modes of SeparatorBoundary.hs: the grid and
# the free placement, without and with boxes, ruled blocks and items of
# lists, with a no-break after the paragraph a separator is held with, and
# with code blocks, whose slots print the ids of their rows, and with
# one-line paragraph keeps that distinguish a one-line separator hold
# from an incorrect two-line hold.
modes='grid free blocks blocks-free holds holds-free code code-free split split-free'
separatorPids=
for mode in $modes; do
  case $mode in
    grid) args= ;;
    free) args=free ;;
    blocks) args=blocks ;;
    blocks-free) args='blocks free' ;;
    holds) args=holds ;;
    holds-free) args='holds free' ;;
    code) args=code ;;
    code-free) args='code free' ;;
    split) args=split ;;
    split-free) args='split free' ;;
  esac
  # shellcheck disable=SC2086
  (cd "$root" && driverCheck experiments/pagination-proof/SeparatorBoundary.hs $args) > "$tmp/separator-haskell-$mode" &
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
(cd "$root" && cabal exec -v0 -- "$runghc" -f "$ghc" -hide-all-packages -package=base \
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
LEAN_PATH="$tmp" "$lean" -o "$tmp/PhysicalNotes.olean" "$physicalNotes"
echo "every footnote line of the free placement is placed once, note by note"

# The premise drainOk of drainCarry at the end of the free placement
# (PhysicalDrain.lean).
physicalDrain=$root/experiments/pagination-proof/PhysicalDrain.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$physicalDrain"; then
  echo "unproved or unchecked Lean declaration in $physicalDrain" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$physicalDrain"
echo "drainOk holds at the last drainCarry of the free placement"

# The exclusion is created at the cursor and remains behind it.  In
# particular, trialWrapRest_putLine's next-column premise is derived
# from the cursor position, not assumed as a conclusion.
wrapPosition=$root/experiments/pagination-proof/WrapPosition.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$wrapPosition"; then
  echo "unproved or unchecked Lean declaration in $wrapPosition" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/WrapPosition.olean" "$wrapPosition"
echo "a wrap is outside the next column after beginWrap and successful forward parts"

wrapCalls=$root/experiments/pagination-proof/WrapCalls.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$wrapCalls"; then
  echo "unproved or unchecked Lean declaration in $wrapCalls" >&2
  exit 1
fi
sh "$root/experiments/pagination-proof/check-wrap-call-shape.sh"
LEAN_PATH="$tmp" "$lean" -o "$tmp/WrapCalls.olean" "$wrapCalls"
echo "every recursive parts entry preserves its wrap position and nonempty active column"

wrapVerses=$root/experiments/pagination-proof/WrapVerses.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$wrapVerses"; then
  echo "unproved or unchecked Lean declaration in $wrapVerses" >&2
  exit 1
fi
sh "$root/experiments/pagination-proof/check-wrap-verse-shape.sh"
LEAN_PATH="$tmp" "$lean" -o "$tmp/WrapVerses.olean" "$wrapVerses"
echo "every recursive verse trial entry and returned snapshot preserves its wrap readiness"

# Only the arithmetic component of the retry's first-ID premise is
# proved here; the connection to the complete rebuild/parts model remains.
causalFirstIds=$root/experiments/pagination-proof/CausalFirstIds.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$causalFirstIds"; then
  echo "unproved or unchecked Lean declaration in $causalFirstIds" >&2
  exit 1
fi
"$lean" -o "$tmp/CausalFirstIds.olean" "$causalFirstIds"
echo "the arithmetic first-ID scan preserves the current unit's ID under rebreaking"

# Model the owning figure's contribution and the following beside scan.
builtFirstIds=$root/experiments/pagination-proof/BuiltFirstIds.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$builtFirstIds"; then
  echo "unproved or unchecked Lean declaration in $builtFirstIds" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/BuiltFirstIds.olean" "$builtFirstIds" > "$tmp/built-first-ids"
printf '%s\n' true > "$tmp/built-first-ids-expected"
diff -u "$tmp/built-first-ids-expected" "$tmp/built-first-ids"
echo "root ADR 0352 I5: two-pass owner and beside numbering preserves the rebroken paragraph's first ID; 648 boundaries and 2 counterchecks pass"

# Retain the composed row payload as well as the existing Physical ID list.
numberedPayload=$root/experiments/pagination-proof/NumberedPayload.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$numberedPayload"; then
  echo "unproved or unchecked Lean declaration in $numberedPayload" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$numberedPayload"
echo "root ADR 0352 I5: numbered composed rows preserve payload, order, split prefixes, and the existing Physical ID projection"

# Derive source progress from the actual selected caption scan and partial trial.
chosenSourceProgress=$root/experiments/pagination-proof/ChosenSourceProgress.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$chosenSourceProgress"; then
  echo "unproved or unchecked Lean declaration in $chosenSourceProgress" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$chosenSourceProgress"
echo "root ADR 0352 I4: chosen fresh-suffix breaks and partial trials discharge the modeled source-progress guard"

# Check the caller-derived positive cutoffs and the complete front retry rank.
retryPrefix=$root/experiments/pagination-proof/RetryPrefix.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$retryPrefix"; then
  echo "unproved or unchecked Lean declaration in $retryPrefix" >&2
  exit 1
fi
sh "$root/experiments/pagination-proof/check-parts-retry-shape.sh"
LEAN_PATH="$tmp" "$lean" "$retryPrefix"
(cd "$root" && cabal exec -v0 -- "$runghc" -f "$ghc" -hide-all-packages -package=base -package=containers \
  -package-id=golem-layout-0.1.0-inplace -package-id=golem-length-0.1.0-inplace \
  experiments/pagination-proof/RetryPrefixChecks.hs)
echo "root ADR 0352 I4: all modeled retry entries have positive cutoffs and a decreasing complete-front retry rank"

# Keep the last-part retry counterexample explicit; do not assume h6 always holds.
lastRetryCounter=$root/experiments/pagination-proof/RetryLastCounter.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$lastRetryCounter"; then
  echo "unproved or unchecked Lean declaration in $lastRetryCounter" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$lastRetryCounter"
(cd "$root" && cabal exec -v0 -- "$runghc" -f "$ghc" -hide-all-packages -package=base -package=containers -package=text \
  -package-id=golem-layout-0.1.0-inplace -package-id=golem-syntax-0.1.0-inplace \
  -package-id=golem-length-0.1.0-inplace -package-id=golem-doc-0.1.0-inplace \
  -package-id=golem-project-0.1.0-inplace \
  experiments/pagination-proof/RetryLastCounter.hs)
echo "root ADR 0352 I4: the last-part retry counterexample is checked by the kernel, not assumed away"

# Side-job unit keys remain ordered and separate at a hard barrier.
besideOwnership=$root/experiments/pagination-proof/BesideOwnership.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$besideOwnership"; then
  echo "unproved or unchecked Lean declaration in $besideOwnership" >&2
  exit 1
fi
"$lean" -o "$tmp/BesideOwnership.olean" "$besideOwnership"
echo "root ADR 0352 I5: modeled side-job keys are unique, ordered, and separate across figure barriers"

# All and only eligible rows before a barrier enter the side job.
besideCoverage=$root/experiments/pagination-proof/BesideCoverage.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$besideCoverage"; then
  echo "unproved or unchecked Lean declaration in $besideCoverage" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$besideCoverage"
echo "root ADR 0352 I5: modeled side-job membership is exactly the eligible prefix, with no eligible row lost"

# A value-only Map.adjust preserves the side-job key domain and selection.
besideAdjustment=$root/experiments/pagination-proof/BesideAdjustment.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$besideAdjustment"; then
  echo "unproved or unchecked Lean declaration in $besideAdjustment" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/BesideAdjustment.olean" "$besideAdjustment"
echo "root ADR 0352 I5: modeled rebreaking preserves the side-job domain, guards, and selected keys"

# Derive unchanged earlier row counts from unique selected keys and one-key updates.
selectedCountPrefix=$root/experiments/pagination-proof/SelectedCountPrefix.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$selectedCountPrefix"; then
  echo "unproved or unchecked Lean declaration in $selectedCountPrefix" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/SelectedCountPrefix.olean" "$selectedCountPrefix"
echo "root ADR 0352 I5: unique selected keys discharge the inner row-count prefix premise of two-pass numbering"

# Fresh composition only emits paragraph keys, so figures provide real barriers.
besideProducer=$root/experiments/pagination-proof/BesideProducer.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$besideProducer"; then
  echo "unproved or unchecked Lean declaration in $besideProducer" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/BesideProducer.olean" "$besideProducer"
echo "root ADR 0352 I5: fresh modeled producers exclude figure keys and discharge the figure-barrier guards"

# Each fresh job stays after its owner and before a later figure.
besideProducerRange=$root/experiments/pagination-proof/BesideProducerRange.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$besideProducerRange"; then
  echo "unproved or unchecked Lean declaration in $besideProducerRange" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/BesideProducerRange.olean" "$besideProducerRange"
echo "root ADR 0352 I5: fresh jobs preserve source-key order and stay separated by later figures"

# Reused composition checks the previous domain and the current surrounding units.
besideReuse=$root/experiments/pagination-proof/BesideReuse.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$besideReuse"; then
  echo "unproved or unchecked Lean declaration in $besideReuse" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/BesideReuse.olean" "$besideReuse"
echo "root ADR 0352 I5: cached and fresh jobs preserve the paragraph-kind invariant"
LEAN_PATH="$tmp" "$lean" "$root/experiments/pagination-proof/BesideReuseBoundary.lean"

# Carry the previous-domain premise through arbitrary modeled cache rounds.
besideReuseRounds=$root/experiments/pagination-proof/BesideReuseRounds.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$besideReuseRounds"; then
  echo "unproved or unchecked Lean declaration in $besideReuseRounds" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/BesideReuseRounds.olean" "$besideReuseRounds"
LEAN_PATH="$tmp" "$lean" "$root/experiments/pagination-proof/BesideReuseRoundsBoundary.lean"
echo "root ADR 0352 I5: modeled cache rounds preserve paragraph kinds and finite input bounds"

# Derive separation and source order for cached/fresh mixed jobs.
besideReuseOrder=$root/experiments/pagination-proof/BesideReuseOrder.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$besideReuseOrder"; then
  echo "unproved or unchecked Lean declaration in $besideReuseOrder" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/BesideReuseOrder.olean" "$besideReuseOrder"
LEAN_PATH="$tmp" "$lean" "$root/experiments/pagination-proof/BesideReuseOrderBoundary.lean"
echo "root ADR 0352 I5: mixed cached/fresh jobs preserve order and remain separated by figures"

# Derive the outer contribution prefix from prior figure ownership ranges.
priorUnitCounts=$root/experiments/pagination-proof/PriorUnitCounts.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$priorUnitCounts"; then
  echo "unproved or unchecked Lean declaration in $priorUnitCounts" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/PriorUnitCounts.olean" "$priorUnitCounts"
LEAN_PATH="$tmp" "$lean" "$root/experiments/pagination-proof/PriorUnitCountsBoundary.lean"
echo "root ADR 0352 I5: selected target updates preserve modeled prior-unit contributions and two-pass first IDs"

# Carry per-job source order into complete rounds and their retained caches.
mixedRoundOrder=$root/experiments/pagination-proof/MixedRoundOrder.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$mixedRoundOrder"; then
  echo "unproved or unchecked Lean declaration in $mixedRoundOrder" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/MixedRoundOrder.olean" "$mixedRoundOrder"
LEAN_PATH="$tmp" "$lean" "$root/experiments/pagination-proof/MixedRoundOrderBoundary.lean"
echo "root ADR 0352 I5: legal mixed-job rounds retain globally ordered and unique keys"





# The boundary inputs of PhysicalBoundary.hs on Physical.lean's paginate,
# against golem-layout's paginatePhysical (root ADR 0352).
pboundary=$root/experiments/pagination-proof/PhysicalBoundary.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$pboundary"; then
  echo "unchecked Lean declaration in $pboundary" >&2
  exit 1
fi
(cd "$root" && cabal exec -v0 -- "$runghc" -f "$ghc" -hide-all-packages -package=base -package=containers -package=text \
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

# The manuscripts of CausalBoundary.hs, a wrapped figure followed by
# paragraphs and stanzas, and wrapped figures in list items kept on a
# page, on the copies of causalFreeFlow's loops in Physical.lean
# (jobsFrom, itemJobs, paragraphs, parts, probeNext, probeChain, stanza,
# tryVerses and accept), against
# golem-typeset's layoutPdf (root ADR 0352).  CausalBoundary.lean is
# evaluated, not proved, so it may use partial.
cboundary=$root/experiments/pagination-proof/CausalBoundary.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$cboundary"; then
  echo "unchecked Lean declaration in $cboundary" >&2
  exit 1
fi
(cd "$root" && driverCheck experiments/pagination-proof/CausalBoundary.hs) > "$tmp/causal-haskell"
LEAN_PATH="$tmp" "$lean" --run "$cboundary" > "$tmp/causal-lean"
diff -u "$tmp/causal-haskell" "$tmp/causal-lean"
causalInputs=$(grep -c '^[0-9]' "$tmp/causal-lean")
echo "the $causalInputs manuscripts with a wrapped figure give the same pages in causalFreeFlow's loops of Physical.lean and golem-typeset"
# Each run of a figure places the lines of runLines (CausalBoundary.lean),
# proved by runJob_lines; the check stays as a guard on the copies.
LEAN_PATH="$tmp" "$lean" --run "$cboundary" premises > "$tmp/causal-premises" || {
  cat "$tmp/causal-premises" >&2
  exit 1
}
echo "every run of a figure places the lines of runLines in the $causalInputs manuscripts"

# Instantiate stanza's hold and display-row fallback before using its cursor.
LEAN_PATH="$tmp" "$lean" -o "$tmp/CausalBoundary.olean" "$cboundary"
# Root ADR 0483 retains the forced public result and consumes it in parts.
LEAN_PATH="$tmp" "$lean" "$root/experiments/pagination-proof/ForcedPrefix.lean"
causalStanza=$root/experiments/pagination-proof/CausalStanza.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$causalStanza"; then
  echo "unproved or unchecked Lean declaration in $causalStanza" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/CausalStanza.olean" "$causalStanza"
echo "causal stanza hold and display-row fallback preserve wrap cursor readiness"

# Connect no-break preprocessing and successive paragraph/stanza results.
causalParagraphs=$root/experiments/pagination-proof/CausalParagraphs.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$causalParagraphs"; then
  echo "unproved or unchecked Lean declaration in $causalParagraphs" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" -o "$tmp/CausalParagraphs.olean" "$causalParagraphs"
(cd "$root" && CAUSAL_MODE=controls driverCheck experiments/pagination-proof/CausalBoundary.hs) > "$tmp/causal-controls-haskell"
CAUSAL_MODE=controls LEAN_PATH="$tmp" "$lean" --run "$cboundary" > "$tmp/causal-controls-lean"
diff -u "$tmp/causal-controls-haskell" "$tmp/causal-controls-lean"
controlInputs=$(grep -c '^[0-9]' "$tmp/causal-controls-lean")
CAUSAL_MODE=controls LEAN_PATH="$tmp" "$lean" --run "$cboundary" premises > "$tmp/causal-controls-premises" || {
  cat "$tmp/causal-controls-premises" >&2
  exit 1
}
echo "causal paragraph cursor handoffs and $controlInputs repeated no-break boundary cases agree"

# Include entries of unsuccessful paragraphs calls, not only successful outputs.
causalCalls=$root/experiments/pagination-proof/CausalCalls.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$causalCalls"; then
  echo "unproved or unchecked Lean declaration in $causalCalls" >&2
  exit 1
fi
sh "$root/experiments/pagination-proof/check-causal-call-shape.sh"
LEAN_PATH="$tmp" "$lean" -o "$tmp/CausalCalls.olean" "$causalCalls"
echo "causal paragraph entries, including failed attempts, preserve wrap readiness"

# Follow every mutual stanza/accept recursion and the concrete model holds.
causalStanzaEntries=$root/experiments/pagination-proof/CausalStanzaEntries.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$causalStanzaEntries"; then
  echo "unproved or unchecked Lean declaration in $causalStanzaEntries" >&2
  exit 1
fi
sh "$root/experiments/pagination-proof/check-causal-stanza-shape.sh"
LEAN_PATH="$tmp" "$lean" "$causalStanzaEntries"
echo "root ADR 0352 I3: every modeled stanza and accept entry preserves wrap readiness"

# Follow both probe loops, including failed verse and paragraph trials.
causalProbeEntries=$root/experiments/pagination-proof/CausalProbeEntries.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$causalProbeEntries"; then
  echo "unproved or unchecked Lean declaration in $causalProbeEntries" >&2
  exit 1
fi
sh "$root/experiments/pagination-proof/check-causal-probe-shape.sh"
LEAN_PATH="$tmp" "$lean" "$causalProbeEntries"
echo "root ADR 0352 I3: every modeled probe entry preserves wrap readiness"

# Relate the reached parts counter to the actual text length, not all states.
partsOffsetEntries=$root/experiments/pagination-proof/PartsOffsetEntries.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$partsOffsetEntries"; then
  echo "unproved or unchecked Lean declaration in $partsOffsetEntries" >&2
  exit 1
fi
sh "$root/experiments/pagination-proof/check-parts-offset-shape.sh"
LEAN_PATH="$tmp" "$lean" -o "$tmp/PartsOffsetEntries.olean" "$partsOffsetEntries"
echo "root ADR 0352 I5: every modeled parts entry preserves the text offset"

# Connect those reached offsets to the concrete breaker's numbering.
partsNumberedEntries=$root/experiments/pagination-proof/PartsNumberedEntries.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$partsNumberedEntries"; then
  echo "unproved or unchecked Lean declaration in $partsNumberedEntries" >&2
  exit 1
fi
sh "$root/experiments/pagination-proof/check-parts-numbered-shape.sh"
LEAN_PATH="$tmp" "$lean" -o "$tmp/PartsNumberedEntries.olean" "$partsNumberedEntries"
echo "root ADR 0352 I5: every reached concrete parts entry has sequential line IDs"

# Use those local entry guards for the modeled successful paragraph output.
partsNumberedOutput=$root/experiments/pagination-proof/PartsNumberedOutput.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|implemented_by|extern|native_decide)([^A-Za-z_]|$)' "$partsNumberedOutput"; then
  echo "unproved or unchecked Lean declaration in $partsNumberedOutput" >&2
  exit 1
fi
LEAN_PATH="$tmp" "$lean" "$partsNumberedOutput" > "$tmp/parts-numbered-output"
printf '%s\n' true > "$tmp/parts-numbered-output-expected"
diff -u "$tmp/parts-numbered-output-expected" "$tmp/parts-numbered-output"
echo "root ADR 0352 I5: successful modeled paragraph output preserves its prefix and sequential line IDs; 24 direct boundaries pass"


# The values of the evaluation of Golem.Layout.KnuthPlass (badness,
# fitness, line demerits, cumulative widths, the demerits of the chosen
# breaks and the ratio, overflow, glyph expansion and target of each line,
# with lines of different widths and glyphs that expand) on Pagination.lean's
# definitions, and the pass, the breaks and the demerits of captionCompared,
# the breaker of Pagination.lean on that evaluation, against golem-layout's
# breaker (root ADR 0352, condition 2).
values=$root/experiments/pagination-proof/CaptionValues.lean
if grep -En '(^|[^A-Za-z_])(sorry|admit|axiom|partial|unsafe|native_decide|implemented_by|extern)([^A-Za-z_]|$)' "$values"; then
  echo "unchecked Lean declaration in $values" >&2
  exit 1
fi
(cd "$root" && cabal exec -v0 -- "$runghc" -f "$ghc" -hide-all-packages -package=base -package=text \
  -package-id=golem-layout-0.1.0-inplace \
  experiments/pagination-proof/CheckCaptionAssembly.hs --values) > "$tmp/caption-values"
sed -n 's/^out //p' "$tmp/caption-values" > "$tmp/caption-haskell"
LEAN_PATH="$tmp" "$lean" --run "$values" "$tmp/caption-values" | sed -n 's/^out //p' > "$tmp/caption-lean"
diff -u "$tmp/caption-haskell" "$tmp/caption-lean"
captions=$(grep -c '^in obs' "$tmp/caption-values")
echo "the evaluation and the breaks of $captions inputs are the same in Pagination.lean and golem-layout"

# The caption rows of the table of boundary inputs, in the advances of
# two real fonts (CaptionFonts.hs): the breaks of captionCompared, the
# grid lines of the caption and the figure of fitCaptionedFigure, or
# G07038, against golem-typeset (root ADR 0352, invariants 1 and 2).
(cd "$root" && driverCheck experiments/pagination-proof/CaptionFonts.hs) > "$tmp/caption-fonts"
sed -n 's/^out //p' "$tmp/caption-fonts" > "$tmp/caption-fonts-haskell"
LEAN_PATH="$tmp" "$lean" --run "$values" "$tmp/caption-fonts" | sed -n 's/^out //p' > "$tmp/caption-fonts-lean"
diff -u "$tmp/caption-fonts-haskell" "$tmp/caption-fonts-lean"
fonts=$(grep -c '^in fig' "$tmp/caption-fonts")
echo "the breaks, the grid lines and the figures of $fonts captions in real fonts are the same in Pagination.lean and golem-typeset"
if ! wait "$wholeOrderPid"; then
  cat "$tmp/whole-order" >&2
  exit 1
fi
echo "the footnote lines of the grid mode come in the manuscript's order"
if ! wait "$wholeRulesPid"; then
  cat "$tmp/whole-rules" >&2
  exit 1
fi
echo "the rules of the ruled blocks of the grid mode are placed with their blocks in one column"
echo "42 Alloy commands have checked Lean counterparts, all 42 on the transcription"
