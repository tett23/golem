/- Golem ADR 0352: a first model of figure fitting. The Alloy commands and
   the whole-document pagination proof remain separate obligations. -/
namespace GolemPagination

/- The caller rejects a caption whose span fills the column (G07038),
   then `fitFigure` floors both dimensions. `numerator / denominator` is
   the image's across-to-along ratio. This is the captioned branch only. -/
def fitCaptionedFigure (capacity captionSpan pitch along numerator denominator : Nat) :
    Option (Nat × Nat) :=
  if captionSpan < capacity then
    let across0 := along * numerator / denominator
    let acrossMax := (capacity - captionSpan) * pitch
    if across0 ≤ acrossMax then
      some (along, across0)
    else
      some (acrossMax * denominator / numerator, acrossMax)
  else
    none

theorem I2_caption_fills_column (capacity captionSpan pitch along numerator denominator : Nat)
    (full : capacity ≤ captionSpan) :
    fitCaptionedFigure capacity captionSpan pitch along numerator denominator = none := by
  simp [fitCaptionedFigure, Nat.not_lt.mpr full]

theorem I2_fitted_figure_depth (capacity captionSpan pitch along numerator denominator : Nat)
    (room : captionSpan < capacity) :
    ∃ along' across',
      fitCaptionedFigure capacity captionSpan pitch along numerator denominator = some (along', across') ∧
      across' ≤ (capacity - captionSpan) * pitch := by
  unfold fitCaptionedFigure
  simp only [room, ↓reduceIte]
  split
  · next h => exact ⟨along, _, rfl, h⟩
  · next h => exact ⟨_, _, rfl, Nat.le_refl _⟩

/-- The image depth is rounded up to a number of grid lines by the typesetter. -/
theorem I2_fitted_image_and_caption_fit_grid
    (capacity captionSpan pitch along numerator denominator : Nat)
    (room : captionSpan < capacity) (positive : 0 < pitch) :
    ∃ width height,
      fitCaptionedFigure capacity captionSpan pitch along numerator denominator = some (width, height) ∧
      (height + pitch - 1) / pitch + captionSpan ≤ capacity := by
  obtain ⟨width, height, result, fits⟩ :=
    I2_fitted_figure_depth capacity captionSpan pitch along numerator denominator room
  refine ⟨width, height, result, ?_⟩
  have rounded : (height + pitch - 1) / pitch ≤ capacity - captionSpan := by
    apply Nat.le_of_lt_succ
    apply (Nat.div_lt_iff_lt_mul positive).2
    rw [Nat.succ_mul]
    omega
  omega

example : fitCaptionedFigure 2 2 15 240 3 1 = none := by rfl
example : fitCaptionedFigure 10 1 15 240 3 1 = some (45, 135) := by rfl

/-- Round an unsigned ratio to nearest, resolving half units to even as in
    Haskell's round on Rational. Font size is positive in the typesetter. -/
def captionPitch (bodySize pitch captionSize : Nat) : Nat :=
  let scaled := pitch * captionSize
  let whole := scaled / bodySize
  let twiceRem := 2 * (scaled % bodySize)
  if twiceRem < bodySize then whole
  else if bodySize < twiceRem then whole + 1
  else whole + whole % 2

/-- captionSpanOf calls headingBlock with a minimum span of one for a
    nonempty caption. The first line occupies one body-size area. -/
def captionGridSpan (bodySize pitch captionSize lines : Nat) : Nat :=
  match lines with
  | 0 => 0
  | rest + 1 =>
    let extent := rest * captionPitch bodySize pitch captionSize + captionSize
    1 + (extent - bodySize + pitch - 1) / pitch

private theorem caption_extent_bound (extent body pitch slots : Nat) (positive : 0 < pitch) :
    (extent - body + pitch - 1) / pitch ≤ slots ↔ extent ≤ slots * pitch + body := by
  constructor
  · intro h
    have h' := (Nat.div_lt_iff_lt_mul positive).1 (Nat.lt_succ_of_le h)
    rw [Nat.succ_mul] at h'
    omega
  · intro h
    apply Nat.le_of_lt_succ
    apply (Nat.div_lt_iff_lt_mul positive).2
    rw [Nat.succ_mul]
    by_cases small : extent ≤ body
    · rw [Nat.sub_eq_zero_of_le small, Nat.zero_add]
      exact Nat.lt_of_lt_of_le (Nat.sub_lt positive (by decide)) (Nat.le_add_left _ _)
    have eq := Nat.sub_add_cancel (Nat.le_of_not_ge small)
    omega

theorem I1_caption_grid_minimal (bodySize pitch captionSize rest slots : Nat)
    (positive : 0 < pitch) :
    captionGridSpan bodySize pitch captionSize (rest + 1) ≤ slots + 1 ↔
      rest * captionPitch bodySize pitch captionSize + captionSize ≤ slots * pitch + bodySize := by
  simp only [captionGridSpan]
  rw [Nat.add_comm 1, Nat.add_le_add_iff_right]
  exact caption_extent_bound _ _ _ _ positive

theorem I2_caption_diagnostic_iff_extent_overflows
    (bodySize pitch captionSize rest free : Nat) (positive : 0 < pitch) :
    free + 2 ≤ captionGridSpan bodySize pitch captionSize (rest + 1) ↔
      free * pitch + bodySize < rest * captionPitch bodySize pitch captionSize + captionSize := by
  have h := I1_caption_grid_minimal bodySize pitch captionSize rest free positive
  omega

example : captionPitch 2 5 1 = 2 ∧ captionPitch 2 7 1 = 4 := by decide
example : (List.range 4).map (captionGridSpan 10 15 10) = [0, 1, 2, 3] := by decide

private def cappedCubicBadness (ratio : Nat) : Nat :=
  if ratio > 1290 then 10000 else (ratio ^ 3 + 131072) / 262144

private theorem cappedCubicBadness_le (ratio : Nat) : cappedCubicBadness ratio ≤ 10000 := by
  unfold cappedCubicBadness
  split
  · decide
  · rename_i h
    have bound := Nat.pow_le_pow_left (Nat.le_of_not_gt h) 3
    omega

/-- TeX badness used by KnuthPlass.evaluate. The stretch or shrink
    available to the candidate may be nonpositive. -/
def captionBadness (distance : Nat) (available : Int) : Nat :=
  if distance = 0 then 0
  else if available ≤ 0 then 10000
  else
    let capacity := available.toNat
    let ratio := if distance ≤ 7230584 then distance * 297 / capacity
      else if 1663497 ≤ capacity then distance / (capacity / 297)
      else distance
    cappedCubicBadness ratio

theorem I1_caption_badness_bounded (distance : Nat) (available : Int) :
    captionBadness distance available ≤ 10000 := by
  unfold captionBadness
  split <;> try decide
  split <;> try decide
  exact cappedCubicBadness_le _

example : captionBadness 0 (-1) = 0 ∧ captionBadness 1 0 = 10000 ∧
    captionBadness 65536 65536 = 100 := by decide

/-- The badness, shrink direction and overflow flag computed for a candidate
    by KnuthPlass.evaluate, after protrusion and edge adjustments. -/
def captionWidthEvaluation (shortfall stretch glueShrink compression : Int)
    (pullInFirst : Bool) : Nat × Bool × Bool :=
  let shrink := glueShrink + compression
  if 0 < shortfall then (captionBadness shortfall.toNat stretch, false, false)
  else if shortfall = 0 then (0, false, false)
  else if shrink < -shortfall then (10000, true, true)
  else if pullInFirst && decide (-shortfall ≤ glueShrink) then (0, true, false)
  else (captionBadness (-shortfall).toNat shrink, true, false)

theorem I1_caption_overfull_iff (shortfall stretch glueShrink compression : Int)
    (pullInFirst : Bool) :
    (captionWidthEvaluation shortfall stretch glueShrink compression pullInFirst).2.2 = true ↔
      shortfall < 0 ∧ glueShrink + compression < -shortfall := by
  unfold captionWidthEvaluation
  by_cases pos : 0 < shortfall <;> by_cases zero : shortfall = 0 <;>
    by_cases over : glueShrink + compression < -shortfall <;>
    cases pullInFirst <;> by_cases room : -shortfall ≤ glueShrink <;>
    simp [pos, zero, over, room] <;> omega

/-- Item properties inspected by isBreak, patternAt, and after. -/
inductive CaptionItemKind where
  | box
  | glue
  | penalty (value : Int) (patternHyphen : Bool)
  deriving DecidableEq

def captionBreakCandidate (usePatterns previousBox : Bool) : CaptionItemKind → Bool
  | .box => false
  | .glue => previousBox
  | .penalty value patternHyphen => decide (value < 10000) && (usePatterns || !patternHyphen)

/-- Ordered breakpoints for one pass, carrying whether the preceding
    item was a box as the Haskell scan tests at each glue. -/
def captionBreakIndices (patterns : Bool) (prevBox : Bool) (start : Nat) :
    List CaptionItemKind → List Nat
  | [] => []
  | item :: tail =>
    let later := captionBreakIndices patterns (decide (item = .box)) (start + 1) tail
    if captionBreakCandidate patterns prevBox item then start :: later else later

theorem I1_caption_break_index_range (patterns prevBox : Bool) (start pos : Nat)
    (items : List CaptionItemKind) (member : pos ∈ captionBreakIndices patterns prevBox start items) :
    start ≤ pos ∧ pos < start + items.length := by
  induction items generalizing start prevBox with
  | nil => simp [captionBreakIndices] at member
  | cons item tail ih =>
    simp only [captionBreakIndices] at member
    split at member
    · rcases List.mem_cons.mp member with eq | rest
      · subst pos; simp only [List.length_cons]; omega
      · have := ih _ _ rest; simp only [List.length_cons]; omega
    · have := ih _ _ member; simp only [List.length_cons]; omega

example : captionBreakIndices false false 0 [.glue, .box, .glue, .penalty 0 true,
    .penalty (-10000) false] = [2, 4] := by decide

private def strictlyIncreasingBreaks : List Nat → Prop
  | [] => True
  | x :: xs => (∀ y ∈ xs, x < y) ∧ strictlyIncreasingBreaks xs

theorem I1_caption_break_indices_strict (patterns prevBox : Bool) (start : Nat)
    (items : List CaptionItemKind) :
    strictlyIncreasingBreaks (captionBreakIndices patterns prevBox start items) := by
  induction items generalizing prevBox start with
  | nil => trivial
  | cons item tail ih =>
    simp only [captionBreakIndices]
    split
    · constructor
      · intro pos member
        have bound := I1_caption_break_index_range _ _ _ _ _ member
        omega
      · apply ih
    · apply ih

/-- Count discarded items following a breakpoint, stopping at the next
    box or forced penalty. The paragraph start does not run this scan. -/
def captionDiscardCount : List CaptionItemKind → Nat
  | [] | .box :: _ => 0
  | .glue :: rest => 1 + captionDiscardCount rest
  | .penalty p _ :: rest => if p ≤ -10000 then 0 else 1 + captionDiscardCount rest

theorem I1_caption_discard_bounded (items : List CaptionItemKind) :
    captionDiscardCount items ≤ items.length := by
  induction items with
  | nil => decide
  | cons item tail ih =>
    cases item <;> simp [captionDiscardCount] <;> try omega
    split <;> omega

example : ([.glue, .penalty 9999 true, .penalty (-10000) false, .box] : List CaptionItemKind).map (captionBreakCandidate false true) = [true, false, true, false] := by decide

/-- Pass settings supplied to the paragraph breaker, in attempt order. -/
structure CaptionBreakPass where
  number : Nat
  tolerance : Int
  emergencyStretch : Int
  usePatterns : Bool
  allowOverfull : Bool
  deriving DecidableEq, Repr

def captionBreakPasses (pretolerance tolerance emergency : Int) : List CaptionBreakPass :=
  (if pretolerance ≥ 0 then [⟨1, pretolerance, 0, false, false⟩] else []) ++
  [⟨2, tolerance, 0, true, false⟩] ++
  (if emergency > 0 then [⟨3, tolerance, emergency, true, false⟩] else []) ++
  [⟨4, 9999, emergency, true, true⟩]

theorem I1_caption_overfull_pass_last (pretolerance tolerance emergency : Int) :
    (captionBreakPasses pretolerance tolerance emergency).getLast? =
      some ⟨4, 9999, emergency, true, true⟩ := by
  by_cases pre : pretolerance ≥ 0 <;> by_cases extra : emergency > 0 <;>
    simp [captionBreakPasses, pre, extra] <;> rfl

example : (captionBreakPasses (-1) 200 0).map (·.number) = [2, 4] ∧
    (captionBreakPasses 0 200 1).map (·.number) = [1, 2, 3, 4] := by decide

/-- The line and breakpoint contribution before adjacent-fitness and
    repeated-hyphen costs are added in KnuthPlass.evaluate. -/
def captionLineDemerits (linePenalty : Int) (badness : Nat) (penalty : Int) : Int :=
  let total := linePenalty + badness
  let base := if total.natAbs ≥ 10000 then 100000000 else total * total
  if 0 ≤ penalty then base + penalty * penalty
  else if -10000 < penalty then base - penalty * penalty else base

theorem I1_caption_forced_break_cost (linePenalty : Int) (badness : Nat)
    (penalty : Int) (forced : penalty ≤ -10000) :
    captionLineDemerits linePenalty badness penalty =
      captionLineDemerits linePenalty badness 0 := by
  have negative : ¬ 0 ≤ penalty := by omega
  simp [captionLineDemerits, negative, Int.not_lt.mpr forced]

example : ([-10000, -9999, 0, 1] : List Int).map (captionLineDemerits 10 0) =
    [100, -99979901, 100, 101] := by decide

/-- Classify the chosen line by shrink direction and TeX badness. -/
def captionFitness (shrinking : Bool) (bad : Nat) : Int :=
  if shrinking then (if bad > 12 then 3 else 2)
  else if bad ≥ 100 then 0 else if bad > 12 then 1 else 2

/-- Cumulative demerits of extending a predecessor, including the costs
    for two flagged breaks and nonadjacent fitness classes. -/
def captionPathCost (previous previousFitness linePenalty penalty doubleHyphen adjacent : Int)
    (previousFlagged flagged shrinking : Bool) (bad : Nat) : Int :=
  previous + captionLineDemerits linePenalty bad penalty +
    (if previousFlagged && flagged then doubleHyphen else 0) +
    (if (captionFitness shrinking bad - previousFitness).natAbs > 1 then adjacent else 0)

theorem I1_caption_path_cost_order (left right fit linePenalty penalty doubleHyphen adjacent : Int)
    (previousFlagged flagged shrinking : Bool) (bad : Nat) :
    captionPathCost left fit linePenalty penalty doubleHyphen adjacent previousFlagged flagged shrinking bad ≤
      captionPathCost right fit linePenalty penalty doubleHyphen adjacent previousFlagged flagged shrinking bad ↔
      left ≤ right := by
  unfold captionPathCost
  omega

example : [12, 13, 99, 100].map (captionFitness false) = [2, 1, 1, 0] ∧
    [12, 13].map (captionFitness true) = [2, 3] := by decide

/-- Within one (line number, fitness) entry, equal demerits select
    the later predecessor in the active list, as in KnuthPlass.step. -/
def captionPreferLater {α : Type} (old new : Int × α) : Int × α :=
  if new.1 ≤ old.1 then new else old

theorem I1_caption_choice_last_minimum {α : Type} (first : Int × α)
    (rest : List (Int × α)) (last : Int × α) :
    (first :: rest).all (fun prior => decide (last.1 ≤ prior.1)) = true →
      (rest ++ [last]).foldl captionPreferLater first = last := by
  induction rest generalizing first with
  | nil =>
    intro h
    have bound : last.1 ≤ first.1 := by simpa using h
    simp [captionPreferLater, bound]
  | cons next tail ih =>
    intro h
    simp only [List.all_cons, Bool.and_eq_true, decide_eq_true_eq] at h
    apply ih
    simp only [List.all_cons, Bool.and_eq_true, decide_eq_true_eq]
    refine ⟨?_, h.2.2⟩
    unfold captionPreferLater
    split
    · exact h.2.1
    · exact h.1

/-- Natural width of the numbered caption fixture, in scaled points.
    The shaped runs are the number, an ideographic space, two initial M
    glyphs, the individual interior glyphs, and three final M glyphs. -/
structure CaptionEnd where
  demerits : Int
  fitness : Nat
  previous : List (Int × Nat)
  deriving DecidableEq

def captionHistoryGreater : List (Int × Nat) → List (Int × Nat) → Bool
  | [], _ => false
  | _ :: _, [] => true
  | (p, f) :: xs, (q, g) :: ys =>
    if p != q then decide (p > q)
    else if f != g then decide (f > g)
    else captionHistoryGreater xs ys

def captionChooseEnd (a b : CaptionEnd) : CaptionEnd :=
  if a.demerits < b.demerits then a
  else if b.demerits < a.demerits then b
  else if a.fitness < b.fitness ||
      (a.fitness == b.fitness && captionHistoryGreater a.previous b.previous) then a else b

theorem captionChooseEnd_cost (a b : CaptionEnd) :
    (captionChooseEnd a b).demerits = min a.demerits b.demerits := by
  unfold captionChooseEnd
  split
  · omega
  · split
    · omega
    · split <;> omega

example : captionChooseEnd ⟨9, 0, []⟩ ⟨8, 3, []⟩ = ⟨8, 3, []⟩ := by decide
example : captionChooseEnd ⟨8, 0, []⟩ ⟨8, 3, []⟩ = ⟨8, 0, []⟩ := by decide
example : captionChooseEnd ⟨8, 1, [(6, 0)]⟩ ⟨8, 1, [(6, 1)]⟩ =
    ⟨8, 1, [(6, 1)]⟩ := by decide

def captionBestEnd : List CaptionEnd → Option CaptionEnd
  | [] => none
  | first :: rest => some (rest.foldl captionChooseEnd first)

theorem captionBestEnd_le (first : CaptionEnd) (rest : List CaptionEnd) :
    ∀ e ∈ first :: rest, (rest.foldl captionChooseEnd first).demerits ≤ e.demerits := by
  induction rest generalizing first with
  | nil => simp
  | cons next tail ih =>
    intro e he
    change (tail.foldl captionChooseEnd (captionChooseEnd first next)).demerits ≤ _
    have h := ih (captionChooseEnd first next)
    have bound := h _ (List.Mem.head _)
    rw [captionChooseEnd_cost] at bound
    simp only [List.mem_cons] at he
    rcases he with rfl | rfl | tailMem
    · omega
    · omega
    · exact h _ (List.Mem.tail _ tailMem)

theorem captionChooseEnd_member (a b : CaptionEnd) :
    captionChooseEnd a b = a ∨ captionChooseEnd a b = b := by
  unfold captionChooseEnd
  split <;> first | exact Or.inl rfl | split <;> first | exact Or.inr rfl | split <;> simp

theorem captionBestEnd_member (first : CaptionEnd) (rest : List CaptionEnd) :
    rest.foldl captionChooseEnd first ∈ first :: rest := by
  induction rest generalizing first with
  | nil => simp
  | cons next tail ih =>
    have h := ih (captionChooseEnd first next)
    simp only [List.mem_cons] at h ⊢
    rcases h with chosen | later
    · rcases captionChooseEnd_member first next with left | right
      · exact Or.inl (chosen.trans left)
      · exact Or.inr (Or.inl (chosen.trans right))
    · exact Or.inr (Or.inr later)

private def measuredCaptionWidth (number pair single triple interior : Nat) : Nat :=
  number + 655360 + pair + interior * single + triple

example : measuredCaptionWidth 649462 952893 476447 1429340 7 ≤ 120 * 65536 := by decide
example : measuredCaptionWidth 705167 1182269 591135 1773404 6 ≤ 120 * 65536 ∧
    120 * 65536 < measuredCaptionWidth 705167 1182269 591135 1773404 7 := by decide

/- The real-font driver test records caption spans 1 and 2 for the same
   twelve M characters in Source Sans Pro and Source Serif. With the
   measured span as input, the rounded image sizes agree with Golem. -/
example : fitCaptionedFigure 4 1 15 240 3 1 = some (15, 45) := by rfl
example : fitCaptionedFigure 4 2 15 240 3 1 = some (10, 30) := by rfl

/- The one-figure, empty-column case of the Alloy `tallFigure` command.
   A legacy figure taller than the column must be sent, while an empty
   column cannot send its first figure. -/
def legacyFits (capacity height : Nat) (kept : Bool) : Prop :=
  kept = false ∨ height ≤ capacity

def legacyFigure (capacity height : Nat) (kept : Bool) : Prop :=
  kept = decide (height ≤ capacity)

def noSendFromEmpty (kept : Bool) : Prop := kept = true

theorem tallFigure_general (capacity height : Nat) (tooTall : capacity < height) :
    ∀ kept : Bool, ¬ (legacyFits capacity height kept ∧
      legacyFigure capacity height kept ∧ noSendFromEmpty kept) := by
  intro kept
  cases kept <;> simp [legacyFits, legacyFigure, noSendFromEmpty, Nat.not_le.mpr tooTall]

theorem fittedFigure_resolves_conflict (capacity height : Nat) :
    legacyFits capacity (min capacity height) true ∧
      legacyFigure capacity (min capacity height) true ∧ noSendFromEmpty true := by
  have depthFits : min capacity height ≤ capacity := Nat.min_le_left capacity height
  simp [legacyFits, legacyFigure, noSendFromEmpty, depthFits]

theorem someFits : ∃ capacity height : Nat, ∃ kept : Bool,
    capacity = 3 ∧ height = 4 ∧ legacyFits capacity height kept := by
  exact ⟨3, 4, false, rfl, rfl, Or.inl rfl⟩

theorem tallFigure : ∃ capacity height : Nat,
    capacity = 3 ∧ height = 4 ∧
    ∀ kept : Bool, ¬ (legacyFits capacity height kept ∧
      legacyFigure capacity height kept ∧ noSendFromEmpty kept) := by
  exact ⟨3, 4, rfl, rfl, tallFigure_general 3 4 (by decide)⟩

/- A column with capacity 3 and 2 lines already used. Two headings follow.
   A break is the number of headings kept in this column. This is the
   smallest `greedyKeepHeading` witness in the Alloy model's report. -/
def twoHeadingFits (brk : Fin 3) : Prop := 2 + brk.val ≤ 3
def twoHeadingGreedy (brk : Fin 3) : Prop := brk.val = 2 ∨ 2 + brk.val + 1 > 3
def twoHeadingKeep (brk : Fin 3) : Prop := brk.val = 0 ∨ brk.val = 2

/- The conflict does not depend on the Alloy bound of 3..6 lines. -/
theorem greedyHeadingConflict_general (used : Nat) (brk : Fin 3) :
    ¬ (used + brk.val ≤ used + 1 ∧
       (brk.val = 2 ∨ used + brk.val + 1 > used + 1) ∧
       (brk.val = 0 ∨ brk.val = 2)) := by
  omega

theorem greedyOrphanConflict_general (used : Nat) (brk : Fin 3) :
    ¬ (used + brk.val ≤ used + 1 ∧
       (brk.val = 2 ∨ used + brk.val + 1 > used + 1) ∧
       brk.val ≠ 1) := by
  omega

theorem greedyKeepHeading :
    (∃ brk : Fin 3, twoHeadingFits brk ∧ twoHeadingGreedy brk) ∧
    (∃ brk : Fin 3, twoHeadingFits brk ∧ twoHeadingKeep brk) ∧
    (∀ brk : Fin 3, ¬ (twoHeadingFits brk ∧ twoHeadingGreedy brk ∧ twoHeadingKeep brk)) := by
  refine ⟨⟨1, by simp [twoHeadingFits, twoHeadingGreedy]⟩, ⟨0, by simp [twoHeadingFits, twoHeadingKeep]⟩, ?_⟩
  intro brk
  unfold twoHeadingFits twoHeadingGreedy twoHeadingKeep
  omega

theorem noneMeetsAll :
    ∀ brk : Fin 3,
      ¬ (twoHeadingFits brk ∧ twoHeadingGreedy brk ∧ twoHeadingKeep brk) := by
  exact greedyKeepHeading.2.2

/- A two-line paragraph after the same partly used column. Breaking after
   its first line would make both an orphan and a widow. -/
def twoLineOrphan (brk : Fin 3) : Prop := brk.val ≠ 1
def twoLineWidow (brk : Fin 3) : Prop := brk.val ≠ 1

theorem greedyOrphan :
    (∃ brk : Fin 3, twoHeadingFits brk ∧ twoHeadingGreedy brk) ∧
    (∃ brk : Fin 3, twoHeadingFits brk ∧ twoLineOrphan brk) ∧
    (∀ brk : Fin 3, ¬ (twoHeadingFits brk ∧ twoHeadingGreedy brk ∧ twoLineOrphan brk)) := by
  refine ⟨⟨1, by simp [twoHeadingFits, twoHeadingGreedy]⟩, ⟨0, by simp [twoHeadingFits, twoLineOrphan]⟩, ?_⟩
  intro brk
  unfold twoHeadingFits twoHeadingGreedy twoLineOrphan
  omega

theorem greedyWidow :
    (∃ brk : Fin 3, twoHeadingFits brk ∧ twoHeadingGreedy brk) ∧
    (∃ brk : Fin 3, twoHeadingFits brk ∧ twoLineWidow brk) ∧
    (∀ brk : Fin 3, ¬ (twoHeadingFits brk ∧ twoHeadingGreedy brk ∧ twoLineWidow brk)) := by
  refine ⟨⟨1, by simp [twoHeadingFits, twoHeadingGreedy]⟩, ⟨0, by simp [twoHeadingFits, twoLineWidow]⟩, ?_⟩
  intro brk
  unfold twoHeadingFits twoHeadingGreedy twoLineWidow
  omega

/- `strictAfterHeadings` from the Alloy report: an empty 3-line column,
   one heading and a three-line paragraph. A break after the heading alone
   violates `lineAfterHeadings`; a break after one or two paragraph lines
   violates the strict orphan or widow rule. -/
def headingParagraphFits (brk : Fin 5) : Prop := brk.val ≤ 3
def headingParagraphNonempty (brk : Fin 5) : Prop := brk.val ≥ 1
def headingParagraphHasLine (brk : Fin 5) : Prop := brk.val ≠ 1
def headingParagraphOrphan (brk : Fin 5) : Prop := brk.val ≠ 2
def headingParagraphWidow (brk : Fin 5) : Prop := brk.val ≠ 3

theorem strictAfterHeadings : ∀ brk : Fin 5,
    ¬ (headingParagraphFits brk ∧ headingParagraphNonempty brk ∧
       headingParagraphHasLine brk ∧ headingParagraphOrphan brk ∧
       headingParagraphWidow brk) := by
  intro brk
  unfold headingParagraphFits headingParagraphNonempty headingParagraphHasLine
    headingParagraphOrphan headingParagraphWidow
  omega

/- In a column beginning with a heading at text index 0, the first body
   line at index 1 is after headings only. This is the relaxation that
   resolves the historical strict-rule counterexample for any paragraph
   length, provided the first two text items fit. -/
def headingParagraphAfterHeadingsOnly (brk pos : Nat) : Prop :=
  ∀ earlier, earlier < pos → earlier < brk → earlier = 0

def headingParagraphOrphanH (lines brk : Nat) : Prop :=
  2 ≤ lines ∧ 1 < brk ∧ ¬ 2 < brk →
    headingParagraphAfterHeadingsOnly brk 1

def headingParagraphWidowH (lines brk : Nat) : Prop :=
  2 ≤ lines ∧ lines - 1 < brk ∧ ¬ lines < brk →
    headingParagraphAfterHeadingsOnly brk 1

def headingParagraphLineAfterHeadings (brk : Nat) : Prop :=
  (1 ≤ brk ∧ ∀ textIndex, textIndex < brk → textIndex = 0) →
    brk ≠ 1

theorem I3_relaxed_heading_paragraph_first_line
    (capacity lines : Nat) (fitsTwo : 2 ≤ capacity)
    (nonempty : 1 ≤ lines) :
    ∃ brk : Nat,
      brk = 2 ∧ brk ≤ capacity ∧ brk ≤ lines + 1 ∧
      headingParagraphOrphanH lines brk ∧
      headingParagraphWidowH lines brk ∧
      headingParagraphLineAfterHeadings brk := by
  refine ⟨2, rfl, fitsTwo, by omega, ?_, ?_, ?_⟩
  · intro _ earlier before _
    omega
  · intro _ earlier before _
    omega
  · intro ⟨_, allHeading⟩
    have lineHeading := allHeading 1 (by omega)
    omega

/- Outside Alloy's capacity-three lower bound, a one-line empty column
   cannot keep both a heading and its following first body line. The
   first-content rule forces break 1, while lineAfterHeadings forbids it. -/
theorem I3_relaxed_heading_capacity_one_conflict :
    ∀ brk : Fin 3,
      ¬ (brk.val ≤ 1 ∧ 1 ≤ brk.val ∧
        headingParagraphLineAfterHeadings brk.val) := by
  intro brk ⟨fits, firstContent, after⟩
  have alone : ∀ textIndex, textIndex < brk.val → textIndex = 0 := by
    intro textIndex before
    omega
  have nextLine := after ⟨firstContent, alone⟩
  omega

/- With one figure, the heading-only break is legal when the figure
   after the heading fits and is kept. Otherwise the first body line is
   included; a figure after that line is kept exactly when both fit. -/
def headingLineFigureRule (beforeLine : Bool)
    (capacity size : Nat) (brk : Fin 3) (kept : Bool) : Prop :=
  kept = decide (
    (if beforeLine then 1 else 2) ≤ brk.val ∧
      (if beforeLine then 1 else 2) + size ≤ capacity)

def headingLineFigureFits (capacity size : Nat)
    (brk : Fin 3) (kept : Bool) : Prop :=
  brk.val + (if kept then size else 0) ≤ capacity

def headingLineAfterHeadings (brk : Fin 3) (kept : Bool) : Prop :=
  brk.val = 1 → kept = true

theorem I3_heading_line_one_figure_exists
    (capacity size : Nat) (beforeLine : Bool)
    (twoFit : 2 ≤ capacity) (figureFits : size ≤ capacity) :
    ∃ brk : Fin 3, ∃ kept : Bool,
      1 ≤ brk.val ∧
      headingLineFigureRule beforeLine capacity size brk kept ∧
      headingLineFigureFits capacity size brk kept ∧
      headingLineAfterHeadings brk kept := by
  cases beforeLine with
  | true =>
      by_cases figureHere : 1 + size ≤ capacity
      · refine ⟨1, true, by decide, ?_, ?_, ?_⟩
        · simp [headingLineFigureRule, figureHere]
        · simp [headingLineFigureFits]
          omega
        · simp [headingLineAfterHeadings]

      · refine ⟨2, false, by decide, ?_, ?_, ?_⟩
        · simp [headingLineFigureRule, figureHere]
        · simp [headingLineFigureFits]
          omega
        · simp [headingLineAfterHeadings]
  | false =>
      by_cases figureHere : 2 + size ≤ capacity
      · refine ⟨2, true, by decide, ?_, ?_, ?_⟩
        · simp [headingLineFigureRule, figureHere]
        · simp [headingLineFigureFits]
          omega
        · simp [headingLineAfterHeadings]
      · refine ⟨2, false, by decide, ?_, ?_, ?_⟩
        · simp [headingLineFigureRule, figureHere]
        · simp [headingLineFigureFits]
          omega
        · simp [headingLineAfterHeadings]

/- A nonempty run of headings followed by a nonempty paragraph has a
   rule-compatible first break in any column with room for two lines:
   break after the first heading if another heading follows, otherwise
   include the paragraph's first line. -/
def headingRunLineAfter (headings brk : Nat) : Prop :=
  brk ≤ headings → brk ≠ headings

theorem I3_heading_run_first_break_exists
    (capacity headings lines : Nat)
    (twoFit : 2 ≤ capacity) (someHeading : 1 ≤ headings)
    (someLine : 1 ≤ lines) :
    ∃ brk : Nat,
      1 ≤ brk ∧ brk ≤ capacity ∧ brk ≤ headings + lines ∧
      headingRunLineAfter headings brk ∧
      (brk ≤ headings ∨
        headingParagraphAfterHeadingsOnly brk headings) := by
  by_cases oneHeading : headings = 1
  · refine ⟨2, by omega, twoFit, by omega, ?_, ?_⟩
    · intro _
      omega
    · right
      intro earlier before _
      omega
  · have moreHeadings : 2 ≤ headings := by omega
    refine ⟨1, by omega, by omega, by omega, ?_, Or.inl (by omega)⟩
    intro _
    omega

inductive TextRole where
  | heading
  | line
  deriving DecidableEq

def textOnlyFirstBreak : List TextRole → Nat
  | [] => 0
  | .line :: _ => 1
  | .heading :: .line :: _ => 2
  | .heading :: _ => 1

def textOnlyLineAfterHeadings (roles : List TextRole)
    (brk : Nat) : Prop :=
  (0 < brk ∧
    ∀ i, i < brk → List.get? roles i = some .heading) →
    List.get? roles brk ≠ some .line

theorem I3_text_only_first_break_line_after
    (capacity : Nat) (roles : List TextRole)
    (twoFit : 2 ≤ capacity) :
    let brk := textOnlyFirstBreak roles
    brk ≤ capacity ∧
      (roles ≠ [] → 1 ≤ brk) ∧
      textOnlyLineAfterHeadings roles brk := by
  cases roles with
  | nil => simp [textOnlyFirstBreak, textOnlyLineAfterHeadings]
  | cons first rest =>
      cases first with
      | line =>
          simp [textOnlyFirstBreak, textOnlyLineAfterHeadings]
          constructor
          · omega
          · intro onlyHeadings
            have impossible := onlyHeadings 0 (by decide)
            simp at impossible
      | heading =>
          cases rest with
          | nil =>
              simp [textOnlyFirstBreak, textOnlyLineAfterHeadings]
              omega
          | cons second tail =>
              cases second with
              | heading =>
                  simp [textOnlyFirstBreak, textOnlyLineAfterHeadings]
                  omega
              | line =>
                  simp [textOnlyFirstBreak, textOnlyLineAfterHeadings]
                  constructor
                  · exact twoFit
                  · intro onlyHeadings
                    have impossible := onlyHeadings 1 (by decide)
                    simp at impossible

theorem I3_text_only_first_break_headings_start
    (roles : List TextRole) :
    ∀ i, i < textOnlyFirstBreak roles →
      List.get? roles i = some .heading → i = 0 := by
  intro i placed heading
  cases roles with
  | nil =>
      simp [textOnlyFirstBreak] at placed
      omega
  | cons first rest =>
      cases first with
      | line =>
          simp [textOnlyFirstBreak] at placed
          have zero : i = 0 := by omega
          subst i
          simp at heading
      | heading =>
          cases rest with
          | nil =>
              simp [textOnlyFirstBreak] at placed
              omega
          | cons second tail =>
              cases second with
              | heading =>
                  simp [textOnlyFirstBreak] at placed
                  omega
              | line =>
                  simp [textOnlyFirstBreak] at placed
                  by_cases zero : i = 0
                  · exact zero
                  · have one : i = 1 := by omega
                    subst i
                    simp at heading

def textOnlyAfterHeadings (roles : List TextRole)
    (brk i : Nat) : Prop :=
  ∀ earlier, earlier < i → earlier < brk →
    List.get? roles earlier = some .heading

theorem I3_text_only_first_break_lines_after_headings
    (roles : List TextRole) :
    ∀ i, i < textOnlyFirstBreak roles →
      List.get? roles i = some .line →
      textOnlyAfterHeadings roles (textOnlyFirstBreak roles) i := by
  intro i placed line earlier before _
  cases roles with
  | nil =>
      simp [textOnlyFirstBreak] at placed
      omega
  | cons first rest =>
      cases first with
      | line =>
          simp [textOnlyFirstBreak] at placed
          omega
      | heading =>
          cases rest with
          | nil =>
              simp [textOnlyFirstBreak] at placed
              have zero : i = 0 := by omega
              subst i
              simp at line
          | cons second tail =>
              cases second with
              | heading =>
                  simp [textOnlyFirstBreak] at placed
                  have zero : i = 0 := by omega
                  subst i
                  simp at line
              | line =>
                  simp [textOnlyFirstBreak] at placed
                  have one : i = 1 := by
                    by_cases zero : i = 0
                    · subst i
                      simp at line
                    · omega
                  have earlierZero : earlier = 0 := by omega
                  subst earlier
                  simp

/- An Alloy `decidedSome` witness: capacity 3, used 0, a recto heading
   at source/text index 0 and the sole line of a one-line paragraph at
   index 1. There are no other items. The break after both text items
   makes `orphanH` and `widowH` vacuous because the paragraph has one
   line; `keepHeadingR` has no non-recto heading to constrain. -/
inductive DecidedText where
  | recto
  | line
  deriving DecidableEq

def decidedTextIndex : DecidedText → Nat
  | .recto => 0
  | .line => 1

def decidedHere (brk : Fin 3) (item : DecidedText) : Prop :=
  decidedTextIndex item < brk.val

def decidedHeading : DecidedText → Prop
  | .recto => True
  | .line => False

def decidedStartsColumn (brk : Fin 3) (item : DecidedText) : Prop :=
  ∀ earlier : DecidedText,
    decidedTextIndex earlier < decidedTextIndex item →
      ¬ decidedHere brk earlier

def decidedBase (brk : Fin 3) : Prop :=
  brk.val ≤ 3 ∧ (1 ≤ brk.val)

def decidedOrphanH (brk : Fin 3) : Prop :=
  2 ≤ (1 : Nat) → decidedStartsColumn brk .line

def decidedWidowH (brk : Fin 3) : Prop :=
  2 ≤ (1 : Nat) → decidedStartsColumn brk .line

def decidedKeepHeadingR (brk : Fin 3) : Prop :=
  ∀ h : DecidedText, decidedHeading h → h ≠ .recto →
    decidedHere brk h

def decidedLineAfterHeadings (brk : Fin 3) : Prop :=
  (1 ≤ brk.val ∧
    (∀ t : DecidedText, decidedHere brk t → decidedHeading t)) →
      decidedTextIndex .line ≠ brk.val

def decidedRectoRule (brk : Fin 3) : Prop :=
  decidedHere brk .recto → decidedStartsColumn brk .recto

theorem decidedSome :
    ∃ brk : Fin 3,
      decidedBase brk ∧ decidedOrphanH brk ∧ decidedWidowH brk ∧
      decidedKeepHeadingR brk ∧ decidedLineAfterHeadings brk ∧
      decidedRectoRule brk := by
  refine ⟨⟨2, by decide⟩, ?_⟩
  simp [decidedBase, decidedOrphanH, decidedWidowH,
    decidedKeepHeadingR, decidedLineAfterHeadings, decidedRectoRule,
    decidedStartsColumn, decidedHere, decidedHeading, decidedTextIndex]
  constructor
  · intro h
    cases h <;> simp
  · intro earlier
    cases earlier <;> simp

/- Both Alloy heading predicates quantify over all items between the
   heading and the following text. Their sole difference is the heading
   set accepted at the two endpoints and throughout that interval. -/
def headingRunKeep (item text heading here starts line linesKept : Nat → Prop) : Prop :=
  ∀ h, heading h → here h → ¬ starts h →
    ∀ t, text t → h < t →
      (∀ i, item i → h < i → i < t → heading i) →
      (heading t → here t) ∧ (line t → linesKept t)

theorem I3_keep_heading_21_implies_recto_variant
    (item text heading recto here starts line linesKept : Nat → Prop)
    (old : headingRunKeep item text heading here starts line linesKept) :
    headingRunKeep item text (fun p => heading p ∧ ¬ recto p)
      here starts line linesKept := by
  intro h eligible placed inside t isText follows between
  obtain ⟨keepHeading, keepLines⟩ := old h eligible.1 placed inside t isText follows
    (fun i isItem lo hi => (between i isItem lo hi).1)
  exact ⟨fun next => keepHeading next.1, keepLines⟩

theorem I3_heading_runs_agree_without_recto
    (item text heading recto here starts line linesKept : Nat → Prop)
    (noRectoHeading : ∀ p, heading p → ¬ recto p) :
    headingRunKeep item text heading here starts line linesKept ↔
      headingRunKeep item text (fun p => heading p ∧ ¬ recto p)
        here starts line linesKept := by
  have same : (fun p => heading p ∧ ¬ recto p) = heading := by
    funext p
    exact propext ⟨And.left, fun h => ⟨h, noRectoHeading p h⟩⟩
  rw [same]

/- Two ordinary headings followed by a recto heading. At break 2 the
   second ordinary heading is in the column and the recto is not. The
   older heading rule keeps the recto in that column; the revised rule
   ends the run before it. Both existence commands can still have a
   solution through a different break, so this compares predicates at
   one placement rather than asserting a global counterexample. -/
theorem I3_recto_heading_run_strict_difference :
    let inRun := fun p : Nat => p < 3
    let here := fun p : Nat => p < 2
    let starts := fun p : Nat => p = 0
    let ordinary := fun p : Nat => inRun p ∧ p ≠ 2
    headingRunKeep inRun inRun ordinary here starts (fun _ => False) (fun _ => True) ∧
      ¬ headingRunKeep inRun inRun inRun here starts (fun _ => False) (fun _ => True) := by
  dsimp [headingRunKeep]
  constructor
  · intro h _ _ _ t _ _ _
    exact ⟨fun next => by omega, fun _ => trivial⟩
  · intro old
    have forced := (old 1 (by decide) (by decide) (by decide) 2
      (by decide) (by decide) (by intro i _ lo hi; omega)).1 (by decide)
    omega

def rectoRunOldKeep (brk : Fin 4) : Prop :=
  1 < brk.val → 2 < brk.val

def rectoRunNewKeep (_ : Fin 4) : Prop := True

def rectoRunStartsColumn (brk : Fin 4) : Prop :=
  2 < brk.val → ¬ 0 < brk.val

theorem I3_recto_ends_heading_run :
    ∃ brk : Fin 4,
      brk.val = 2 ∧ brk.val ≤ 3 ∧ 1 ≤ brk.val ∧
      ¬ rectoRunOldKeep brk ∧ rectoRunNewKeep brk ∧
      rectoRunStartsColumn brk := by
  refine ⟨2, by decide, by decide, by decide, ?_, ?_, ?_⟩
  · simp [rectoRunOldKeep]
  · trivial
  · simp [rectoRunStartsColumn]

/- An Alloy `keepAllSome` witness: capacity 3, used 1, one line in a
   paragraph marked AllLines, and no other item. At break 0 the
   paragraph is not split, so all three keep rules hold. -/
def keepAllSomeBroken (brk : Fin 2) : Prop :=
  0 < brk.val ∧ 0 < 1 - brk.val

def keepAllSomeBase (brk : Fin 2) : Prop :=
  1 + brk.val ≤ 3

def keepAllSomeFirst (brk : Fin 2) : Prop :=
  keepAllSomeBroken brk → 2 ≤ brk.val

def keepAllSomeLast (brk : Fin 2) : Prop :=
  keepAllSomeBroken brk → 2 ≤ 1 - brk.val

def keepAllSomeAll (brk : Fin 2) : Prop :=
  keepAllSomeBroken brk → False

theorem keepAllSome :
    ∃ brk : Fin 2,
      keepAllSomeBase brk ∧ keepAllSomeFirst brk ∧
      keepAllSomeLast brk ∧ keepAllSomeAll brk := by
  refine ⟨⟨0, by decide⟩, ?_⟩
  simp [keepAllSomeBase, keepAllSomeFirst, keepAllSomeLast,
    keepAllSomeAll, keepAllSomeBroken]

def splitBroken (total here : Nat) : Prop :=
  0 < here ∧ 0 < total - here

def splitOrphan (total here : Nat) (starts : Prop) : Prop :=
  splitBroken total here ∧ here = 1 → starts

def splitWidow (total here : Nat) (starts : Prop) : Prop :=
  splitBroken total here ∧ total - here = 1 → starts

def splitKeepFirst (total here : Nat) (starts : Prop) : Prop :=
  splitBroken total here ∧ ¬starts → 2 ≤ here

def splitKeepLast (total here : Nat) (starts : Prop) : Prop :=
  splitBroken total here ∧ ¬starts → 2 ≤ total - here

theorem I3_keepDefault_count_equivalence
    (total here : Nat) (starts : Prop) :
    (splitOrphan total here starts ∧ splitWidow total here starts) ↔
      (splitKeepFirst total here starts ∧
        splitKeepLast total here starts) := by
  by_cases hstart : starts
  · simp [splitOrphan, splitWidow, splitKeepFirst, splitKeepLast, hstart]
  · simp [splitOrphan, splitWidow, splitKeepFirst, splitKeepLast,
      splitBroken, hstart]
    constructor
    · rintro ⟨orphan, widow⟩
      constructor
      · intro positive next
        by_cases one : here = 1
        · exact False.elim (orphan positive next one)
        · omega
      · intro positive next
        by_cases one : total - here = 1
        · exact False.elim (widow positive next one)
        · omega
    · rintro ⟨first, last⟩
      constructor
      · intro positive next one
        have enough := first positive next
        omega
      · intro positive next one
        have enough := last positive next
        omega

def orphanByBoundary (total here : Nat) (starts : Prop) : Prop :=
  2 ≤ total ∧ 0 < here ∧ here ≤ 1 → starts

def widowByBoundary (total here : Nat) (starts : Prop) : Prop :=
  2 ≤ total ∧ total - 1 ≤ here ∧ here < total → starts

theorem keepDefaultDiffers (total here : Nat) (starts : Prop)
    (within : here ≤ total) :
    (orphanByBoundary total here starts ∧
      widowByBoundary total here starts) ↔
      (splitKeepFirst total here starts ∧
        splitKeepLast total here starts) := by
  have orphanEq : orphanByBoundary total here starts ↔
      splitOrphan total here starts := by
    constructor
    · intro boundary ⟨⟨positive, next⟩, one⟩
      apply boundary
      constructor
      · omega
      · exact ⟨positive, by omega⟩
    · intro count ⟨atLeastTwo, positive, atMostOne⟩
      apply count
      constructor
      · exact ⟨positive, by omega⟩
      · omega
  have widowEq : widowByBoundary total here starts ↔
      splitWidow total here starts := by
    constructor
    · intro boundary ⟨⟨positive, _⟩, one⟩
      apply boundary
      exact ⟨by omega, by omega, by omega⟩
    · intro count ⟨atLeastTwo, beforeLast, beforeEnd⟩
      apply count
      constructor
      · exact ⟨by omega, by omega⟩
      · omega
  rw [orphanEq, widowEq]
  exact I3_keepDefault_count_equivalence total here starts

/- In the historical blank-line rule, the next block after the blank is
   the second figure even when it waits. The current rule skips waiting
   figures and finds the following heading. These functions capture that
   distinction for the sequence figure, blank, figure, heading. -/
def blankWithNext25Case (secondKept : Bool) : Bool := secondKept
def blankWithNextCase (firstKept secondKept headingHere : Bool) : Bool :=
  if firstKept == false && secondKept == false then headingHere else secondKept

/- An ordered list of candidate items after a blank has already removed
   blanks and need markers. `nextOf25` takes its head; `nextOf` skips figures
   that have been sent on. The equality is general when none waits. -/
def nextAfterWaiting {α : Type} (waiting : α → Bool) : List α → Option α
  | [] => none
  | x :: xs => if waiting x then nextAfterWaiting waiting xs else some x

theorem nextAfterWaiting_eq_head_when_none_wait
    (waiting : Nat → Bool) (items : List Nat)
    (noneWait : ∀ x ∈ items, waiting x = false) :
    nextAfterWaiting waiting items = items.head? := by
  induction items with
  | nil => rfl
  | cons x xs =>
      have hx : waiting x = false := noneWait x (by simp)
      simp [nextAfterWaiting, hx]

theorem nextAfterWaiting_skips_waiting_head
    (waiting : Nat → Bool) (x : Nat) (xs : List Nat)
    (waits : waiting x = true) :
    nextAfterWaiting waiting (x :: xs) = nextAfterWaiting waiting xs := by
  simp [nextAfterWaiting, waits]

/- Alloy `nextOf` is empty exactly when every candidate after the blank
   waits. The statement holds for any finite source-order candidate list,
   not just the model's two-figure limit. -/
theorem I3_nextAfterWaiting_none_iff_all_wait
    {α : Type} (waiting : α → Bool) (items : List α) :
    nextAfterWaiting waiting items = none ↔
      ∀ x ∈ items, waiting x = true := by
  induction items with
  | nil => simp [nextAfterWaiting]
  | cons x xs ih =>
      cases hx : waiting x with
      | false => simp [nextAfterWaiting, hx]
      | true => simp [nextAfterWaiting, hx, ih]

theorem I3_nextAfterWaiting_eq_find (waiting : Nat → Bool)
    (items : List Nat) :
    nextAfterWaiting waiting items = List.find? (fun x => !waiting x) items := by
  induction items with
  | nil => rfl
  | cons x xs ih =>
      cases hx : waiting x <;> simp [nextAfterWaiting, List.find?, hx, ih]

/- The witness returned by `nextOf` is the first eligible source item:
   every candidate before it waits, and it does not wait. -/
theorem I3_nextAfterWaiting_some_iff_first
    {α : Type} (waiting : α → Bool) (items : List α) (i : α) :
    nextAfterWaiting waiting items = some i ↔
      ∃ before after, items = before ++ i :: after ∧
        (∀ x ∈ before, waiting x = true) ∧ waiting i = false := by
  induction items with
  | nil =>
      constructor
      · intro h
        cases h
      · rintro ⟨before, after, eq, _, _⟩
        cases before <;> simp at eq
  | cons x xs ih =>
      cases hx : waiting x with
      | false =>
          constructor
          · intro h
            have eq : x = i := by simpa [nextAfterWaiting, hx] using h
            subst i
            exact ⟨[], xs, rfl, by simp, hx⟩
          · rintro ⟨before, after, eq, allWait, _⟩
            cases before with
            | nil =>
                simp at eq
                simpa [nextAfterWaiting, hx] using eq.1
            | cons y ys =>
                simp at eq
                have waits : waiting x = true := by
                  rw [eq.1]
                  exact allWait y (by simp)
                simp [hx] at waits
      | true =>
          constructor
          · intro h
            obtain ⟨before, after, eq, allWait, noWait⟩ :=
              ih.mp (by simpa [nextAfterWaiting, hx] using h)
            refine ⟨x :: before, after, by simp [eq], ?_, noWait⟩
            intro z member
            rcases List.mem_cons.mp member with same | earlier
            · subst z
              exact hx
            · exact allWait z earlier
          · rintro ⟨before, after, eq, allWait, noWait⟩
            cases before with
            | nil =>
                simp at eq
                have noWaitX : waiting x = false := by simpa [eq.1] using noWait
                simp [hx] at noWaitX
            | cons y ys =>
                simp at eq
                have earlierWaits : ∀ z ∈ ys, waiting z = true := by
                  intro z member
                  exact allWait z (by simp [member])
                have tail := ih.mpr ⟨ys, after, eq.2, earlierWaits, noWait⟩
                simpa [nextAfterWaiting, hx] using tail

/- These are the item kinds relevant to Alloy `nextOf`. Each item has a
   source position; the caller supplies them in increasing source order.
   `nextOf` ignores Blank and Need and later ignores waiting Figure items.
   Text remains a candidate even when it is sent to the next column. -/
inductive SourceItem where
  | text (pos : Nat)
  | figure (pos : Nat)
  | blank (pos : Nat)
  | need (pos : Nat)

def sourcePos : SourceItem → Nat
  | .text pos | .figure pos | .blank pos | .need pos => pos

def sourceOrdered : List SourceItem → Prop
  | [] => True
  | item :: rest =>
      (∀ later ∈ rest, sourcePos item < sourcePos later) ∧ sourceOrdered rest

def isContent : SourceItem → Prop
  | .text _ | .figure _ => True
  | .blank _ | .need _ => False

def firstContent : List SourceItem → Option SourceItem
  | [] => none
  | (.text pos) :: _ => some (.text pos)
  | (.figure pos) :: _ => some (.figure pos)
  | (.blank _) :: rest | (.need _) :: rest => firstContent rest

theorem I3_firstContent_is_earliest
    (items : List SourceItem) (ordered : sourceOrdered items)
    (item : SourceItem) (first : firstContent items = some item) :
    isContent item ∧ item ∈ items ∧
      ∀ other ∈ items, isContent other → sourcePos item ≤ sourcePos other := by
  induction items generalizing item with
  | nil => simp [firstContent] at first
  | cons head rest ih =>
      rcases ordered with ⟨headBefore, restOrdered⟩
      cases head with
      | text pos =>
          simp [firstContent] at first
          subst item
          refine ⟨by simp [isContent], by simp, ?_⟩
          intro other member _
          rcases List.mem_cons.mp member with same | later
          · subst other
            exact Nat.le_refl _
          · exact Nat.le_of_lt (headBefore other later)
      | figure pos =>
          simp [firstContent] at first
          subst item
          refine ⟨by simp [isContent], by simp, ?_⟩
          intro other member _
          rcases List.mem_cons.mp member with same | later
          · subst other
            exact Nat.le_refl _
          · exact Nat.le_of_lt (headBefore other later)
      | blank pos =>
          have rec := ih restOrdered item (by simpa [firstContent] using first)
          refine ⟨rec.1, List.mem_cons_of_mem _ rec.2.1, ?_⟩
          intro other member content
          rcases List.mem_cons.mp member with same | later
          · subst other
            simp [isContent] at content
          · exact rec.2.2 other later content

      | need pos =>
          have rec := ih restOrdered item (by simpa [firstContent] using first)
          refine ⟨rec.1, List.mem_cons_of_mem _ rec.2.1, ?_⟩
          intro other member content
          rcases List.mem_cons.mp member with same | later
          · subst other
            simp [isContent] at content
          · exact rec.2.2 other later content

theorem I3_firstContent_none_has_no_content
    (items : List SourceItem) (empty : firstContent items = none) :
    ∀ item ∈ items, ¬ isContent item := by
  induction items with
  | nil => intro item member; cases member
  | cons head rest ih =>
      cases head with
      | text pos => simp [firstContent] at empty
      | figure pos => simp [firstContent] at empty
      | blank pos =>
          have restEmpty : firstContent rest = none := by
            simpa [firstContent] using empty
          intro item member content
          rcases List.mem_cons.mp member with same | later
          · subst item
            simp [isContent] at content
          · exact ih restEmpty item later content
      | need pos =>
          have restEmpty : firstContent rest = none := by
            simpa [firstContent] using empty
          intro item member content
          rcases List.mem_cons.mp member with same | later
          · subst item
            simp [isContent] at content
          · exact ih restEmpty item later content

structure SourceCandidate where
  pos : Nat
  figure : Bool

def candidateAfterBlank (blankPos : Nat) : SourceItem → Option SourceCandidate
  | .text pos => if blankPos < pos then some ⟨pos, false⟩ else none
  | .figure pos => if blankPos < pos then some ⟨pos, true⟩ else none
  | .blank _ => none
  | .need _ => none

theorem I3_candidateAfterBlank_preserves_position
    (blankPos : Nat) (item : SourceItem) (candidate : SourceCandidate)
    (selected : candidateAfterBlank blankPos item = some candidate) :
    candidate.pos = sourcePos item := by
  cases item <;> simp [candidateAfterBlank, sourcePos] at selected ⊢
  all_goals rcases selected with ⟨_, rfl⟩ <;> rfl

def candidatesAfterBlank (blankPos : Nat) (items : List SourceItem) :
    List SourceCandidate :=
  items.filterMap (candidateAfterBlank blankPos)

def candidateWaits (waitingFigure : Nat → Bool) (item : SourceCandidate) : Bool :=
  item.figure && waitingFigure item.pos

def nextOfSource (blankPos : Nat) (waitingFigure : Nat → Bool) :
    List SourceItem → Option SourceCandidate
  | [] => none
  | item :: rest =>
      match candidateAfterBlank blankPos item with
      | none => nextOfSource blankPos waitingFigure rest
      | some c =>
          if candidateWaits waitingFigure c then
            nextOfSource blankPos waitingFigure rest
          else some c

theorem I3_nextOfSource_eq_filtered_candidates
    (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) :
    nextOfSource blankPos waitingFigure items =
      nextAfterWaiting (candidateWaits waitingFigure)
        (candidatesAfterBlank blankPos items) := by
  induction items with
  | nil => rfl
  | cons item rest ih =>
      cases h : candidateAfterBlank blankPos item with
      | none =>
          simpa [nextOfSource, candidatesAfterBlank, List.filterMap, h] using ih
      | some c =>
          cases hc : candidateWaits waitingFigure c with
          | false => simp [nextOfSource, candidatesAfterBlank, List.filterMap, h, hc, nextAfterWaiting]
          | true => simpa [nextOfSource, candidatesAfterBlank, List.filterMap, h, hc, nextAfterWaiting] using ih

theorem I3_nextOfSource_some_iff_first_candidate
    (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (candidate : SourceCandidate) :
    nextOfSource blankPos waitingFigure items = some candidate ↔
      ∃ before after,
        candidatesAfterBlank blankPos items = before ++ candidate :: after ∧
        (∀ x ∈ before, candidateWaits waitingFigure x = true) ∧
        candidateWaits waitingFigure candidate = false := by
  rw [I3_nextOfSource_eq_filtered_candidates]
  exact I3_nextAfterWaiting_some_iff_first
    (candidateWaits waitingFigure) (candidatesAfterBlank blankPos items) candidate

theorem I3_nextOfSource_none_iff_no_available
    (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) :
    nextOfSource blankPos waitingFigure items = none ↔
      ∀ candidate ∈ candidatesAfterBlank blankPos items,
        candidateWaits waitingFigure candidate = true := by
  rw [I3_nextOfSource_eq_filtered_candidates]
  exact I3_nextAfterWaiting_none_iff_all_wait
    (candidateWaits waitingFigure) (candidatesAfterBlank blankPos items)

/- On a source-position ordered input, the first eligible candidate is
   also the least-position eligible item in Alloy's `nextOf` set. -/
theorem I3_nextOfSource_minimal
    (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (ordered : sourceOrdered items)
    (candidate : SourceCandidate)
    (next : nextOfSource blankPos waitingFigure items = some candidate)
    (otherItem : SourceItem) (member : otherItem ∈ items)
    (other : SourceCandidate)
    (selected : candidateAfterBlank blankPos otherItem = some other)
    (available : candidateWaits waitingFigure other = false) :
    candidate.pos ≤ other.pos := by
  induction items generalizing candidate with
  | nil => cases member
  | cons head rest ih =>
      rcases ordered with ⟨headBefore, restOrdered⟩
      rcases List.mem_cons.mp member with same | tail
      · subst otherItem
        cases hc : candidateAfterBlank blankPos head with
        | none =>
            simp [hc] at selected
        | some headCandidate =>
            cases hw : candidateWaits waitingFigure headCandidate with
            | true =>
                have otherEq : other = headCandidate := by simpa [hc] using selected.symm
                subst other
                simp [hw] at available
            | false =>
                have candidateEq : candidate = headCandidate := by
                  simpa [nextOfSource, hc, hw] using next.symm
                have otherEq : other = headCandidate := by simpa [hc] using selected.symm
                subst candidate
                subst other
                exact Nat.le_refl _
      · cases hc : candidateAfterBlank blankPos head with
        | none =>
            have nextRest : nextOfSource blankPos waitingFigure rest = some candidate := by
              simpa [nextOfSource, hc] using next
            exact ih restOrdered candidate nextRest tail
        | some headCandidate =>
            cases hw : candidateWaits waitingFigure headCandidate with
            | true =>
                have nextRest : nextOfSource blankPos waitingFigure rest = some candidate := by
                  simpa [nextOfSource, hc, hw] using next
                exact ih restOrdered candidate nextRest tail
            | false =>
                have candidateEq : candidate = headCandidate := by
                  simpa [nextOfSource, hc, hw] using next.symm
                have earlier := headBefore otherItem tail
                have headPos := I3_candidateAfterBlank_preserves_position blankPos head headCandidate hc
                have otherPos := I3_candidateAfterBlank_preserves_position blankPos otherItem other selected
                rw [candidateEq, headPos, otherPos]
                exact Nat.le_of_lt earlier

theorem I3_nextOfSource_some_has_member
    (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (candidate : SourceCandidate)
    (next : nextOfSource blankPos waitingFigure items = some candidate) :
    ∃ item ∈ items,
      candidateAfterBlank blankPos item = some candidate ∧
      candidateWaits waitingFigure candidate = false := by
  induction items with
  | nil => simp [nextOfSource] at next
  | cons head rest ih =>
      cases h : candidateAfterBlank blankPos head with
      | none =>
          have nextRest : nextOfSource blankPos waitingFigure rest = some candidate := by
            simpa [nextOfSource, h] using next
          obtain ⟨item, member, selected, available⟩ := ih nextRest
          exact ⟨item, List.mem_cons_of_mem head member, selected, available⟩
      | some c =>
          cases hw : candidateWaits waitingFigure c with
          | true =>
              have nextRest : nextOfSource blankPos waitingFigure rest = some candidate := by
                simpa [nextOfSource, h, hw] using next
              obtain ⟨item, member, selected, available⟩ := ih nextRest
              exact ⟨item, List.mem_cons_of_mem head member, selected, available⟩
          | false =>
              have same : candidate = c := by
                simpa [nextOfSource, h, hw] using next.symm
              subst candidate
              exact ⟨head, List.mem_cons_self head rest, h, hw⟩

def alloyNextPosition (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (pos : Nat) : Prop :=
  (∃ item ∈ items, ∃ candidate,
      candidateAfterBlank blankPos item = some candidate ∧
      candidateWaits waitingFigure candidate = false ∧ candidate.pos = pos) ∧
  (∀ item ∈ items, ∀ candidate,
      candidateAfterBlank blankPos item = some candidate →
      candidateWaits waitingFigure candidate = false →
      pos ≤ candidate.pos)

theorem I3_candidate_member_filtered
    (blankPos : Nat) (items : List SourceItem)
    (item : SourceItem) (member : item ∈ items)
    (candidate : SourceCandidate)
    (selected : candidateAfterBlank blankPos item = some candidate) :
    candidate ∈ candidatesAfterBlank blankPos items := by
  induction items with
  | nil => cases member
  | cons head rest ih =>
      rcases List.mem_cons.mp member with same | tail
      · subst item
        simp [candidatesAfterBlank, List.filterMap, selected]
      · cases h : candidateAfterBlank blankPos head with
        | none => simpa [candidatesAfterBlank, List.filterMap, h] using ih tail
        | some c =>
            simp only [candidatesAfterBlank, List.filterMap, h, List.mem_cons]
            exact Or.inr (ih tail)

theorem I3_nextOfSource_iff_alloy_min_position
    (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (ordered : sourceOrdered items) (pos : Nat) :
    (∃ candidate, nextOfSource blankPos waitingFigure items = some candidate ∧
      candidate.pos = pos) ↔
      alloyNextPosition blankPos waitingFigure items pos := by
  constructor
  · rintro ⟨candidate, next, rfl⟩
    obtain ⟨item, member, selected, available⟩ :=
      I3_nextOfSource_some_has_member blankPos waitingFigure items candidate next
    constructor
    · exact ⟨item, member, candidate, selected, available, rfl⟩
    · intro otherItem otherMember other otherSelected otherAvailable
      exact I3_nextOfSource_minimal blankPos waitingFigure items ordered
        candidate next otherItem otherMember other otherSelected otherAvailable
  · intro spec
    obtain ⟨⟨item, member, candidate, selected, available, equalPos⟩, minimum⟩ := spec
    cases next : nextOfSource blankPos waitingFigure items with
    | none =>
        have allWait := (I3_nextOfSource_none_iff_no_available
          blankPos waitingFigure items).mp next
        have inCandidates : candidate ∈ candidatesAfterBlank blankPos items := by
          exact I3_candidate_member_filtered blankPos items item member candidate selected
        have impossible := allWait candidate inCandidates
        simp [available] at impossible
    | some first =>
        obtain ⟨firstItem, firstMember, firstSelected, firstAvailable⟩ :=
          I3_nextOfSource_some_has_member blankPos waitingFigure items first next
        have firstLe : first.pos ≤ pos := by
          rw [← equalPos]
          exact I3_nextOfSource_minimal blankPos waitingFigure items ordered
            first next item member candidate selected available
        have posLe : pos ≤ first.pos :=
          minimum firstItem firstMember first firstSelected firstAvailable
        exact ⟨first, rfl, Nat.le_antisymm firstLe posLe⟩

theorem I3_sourceOrdered_unique_position
    (items : List SourceItem) (ordered : sourceOrdered items)
    (first second : SourceItem) (firstIn : first ∈ items)
    (secondIn : second ∈ items)
    (samePos : sourcePos first = sourcePos second) : first = second := by
  induction items generalizing first second with
  | nil => cases firstIn
  | cons head rest ih =>
      rcases ordered with ⟨headBefore, restOrdered⟩
      rcases List.mem_cons.mp firstIn with firstHead | firstTail
      · subst first
        rcases List.mem_cons.mp secondIn with secondHead | secondTail
        · exact secondHead.symm
        · have earlier := headBefore second secondTail
          omega
      · rcases List.mem_cons.mp secondIn with secondHead | secondTail
        · subst second
          have earlier := headBefore first firstTail
          omega
        · exact ih restOrdered first second firstTail secondTail samePos

def alloyNextCandidate (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (candidate : SourceCandidate) : Prop :=
  (∃ item ∈ items,
      candidateAfterBlank blankPos item = some candidate ∧
      candidateWaits waitingFigure candidate = false) ∧
  (∀ item ∈ items, ∀ other,
      candidateAfterBlank blankPos item = some other →
      candidateWaits waitingFigure other = false →
      candidate.pos ≤ other.pos)

theorem I3_nextOfSource_iff_alloy_candidate
    (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (ordered : sourceOrdered items)
    (candidate : SourceCandidate) :
    nextOfSource blankPos waitingFigure items = some candidate ↔
      alloyNextCandidate blankPos waitingFigure items candidate := by
  constructor
  · intro next
    constructor
    · exact I3_nextOfSource_some_has_member blankPos waitingFigure items candidate next
    · intro item member other selected available
      exact I3_nextOfSource_minimal blankPos waitingFigure items ordered
        candidate next item member other selected available
  · intro spec
    obtain ⟨⟨item, member, selected, available⟩, minimum⟩ := spec
    have minPos : alloyNextPosition blankPos waitingFigure items candidate.pos := by
      exact ⟨⟨item, member, candidate, selected, available, rfl⟩, minimum⟩
    obtain ⟨first, next, samePos⟩ :=
      (I3_nextOfSource_iff_alloy_min_position blankPos waitingFigure
        items ordered candidate.pos).mpr minPos
    obtain ⟨firstItem, firstMember, firstSelected, _⟩ :=
      I3_nextOfSource_some_has_member blankPos waitingFigure items first next
    have firstSourcePos :=
      I3_candidateAfterBlank_preserves_position blankPos firstItem first firstSelected
    have candidateSourcePos :=
      I3_candidateAfterBlank_preserves_position blankPos item candidate selected
    have sameItem : firstItem = item :=
      I3_sourceOrdered_unique_position items ordered firstItem item
        firstMember member (by omega)
    subst firstItem
    have sameCandidate : first = candidate := by
      simp [selected] at firstSelected
      exact firstSelected.symm
    simpa [sameCandidate] using next

/- Number figures in source order. This is the `figureOrder` pair condition
   from the Alloy model without its finite limit of two figures. It says a
   kept figure requires every earlier figure to be kept. -/
def figuresInOrder (count : Nat) (kept : Nat → Bool) : Prop :=
  ∀ f, f < count → kept f = true → ∀ g, g < f → kept g = true

theorem figuresInOrder_iff_no_reentry (count : Nat) (kept : Nat → Bool) :
    figuresInOrder count kept ↔
      ∀ g f, g < f → f < count → kept g = false → kept f = false := by
  constructor
  · intro ordered g f before bound missing
    cases h : kept f with
    | false => rfl
    | true =>
        have earlier := ordered f bound h g before
        simp [missing] at earlier
  · intro noReentry f bound present g before
    cases h : kept g with
    | true => rfl
    | false =>
        have later := noReentry g f before bound h
        simp [present] at later

/- Alloy `figures` includes the earlier-figure conjunct for every kept
   figure. The `figureOrder` predicate is therefore redundant whenever
   `figures` itself holds, independent of the column capacity and the
   finite bound of two figures. Text readiness and the occupied-line
   calculation are separate inputs here. -/
def figuresRule (count : Nat) (kept : Nat → Bool)
    (textReady room : Nat → Prop) : Prop :=
  ∀ f, f < count →
    (kept f = true ↔ textReady f ∧
      (∀ g, g < f → kept g = true) ∧ room f)

def figurePrefixReady (ready room : Nat → Bool) : Nat → Bool
  | 0 => true
  | f + 1 => figurePrefixReady ready room f && ready f && room f

def greedyFigure (ready room : Nat → Bool) (f : Nat) : Bool :=
  figurePrefixReady ready room f && ready f && room f

theorem I3_figurePrefixReady_iff_all_prior
    (ready room : Nat → Bool) (f : Nat) :
    figurePrefixReady ready room f = true ↔
      ∀ g, g < f → greedyFigure ready room g = true := by
  induction f with
  | zero =>
      constructor
      · intro _ g before
        exact False.elim (Nat.not_lt_zero g before)
      · intro _
        rfl
  | succ f ih =>
      constructor
      · intro hprefix g before
        have latest : greedyFigure ready room f = true := by
          simpa [greedyFigure, figurePrefixReady] using hprefix
        by_cases same : g = f
        · simpa [same] using latest
        · have earlier : g < f := by omega
          have oldPrefix : figurePrefixReady ready room f = true := by
            simp [greedyFigure, Bool.and_eq_true] at latest
            exact latest.1.1
          exact ih.mp oldPrefix g earlier
      · intro allPrior
        have latest := allPrior f (by omega)
        simpa [greedyFigure, figurePrefixReady] using latest

theorem I3_figurePrefixReady_congr_before
    (ready roomA roomB : Nat → Bool) (f : Nat)
    (sameRoom : ∀ g, g < f → roomA g = roomB g) :
    figurePrefixReady ready roomA f = figurePrefixReady ready roomB f := by
  induction f with
  | zero => rfl
  | succ f ih =>
      have earlier := ih (by
        intro g before
        exact sameRoom g (by omega))
      simp [figurePrefixReady, earlier, sameRoom f (by omega)]

theorem I3_greedyFigure_congr_through
    (ready roomA roomB : Nat → Bool) (f : Nat)
    (sameRoom : ∀ g, g ≤ f → roomA g = roomB g) :
    greedyFigure ready roomA f = greedyFigure ready roomB f := by
  have earlier := I3_figurePrefixReady_congr_before ready roomA roomB f
    (by intro g before; exact sameRoom g (by omega))
  simp [greedyFigure, earlier, sameRoom f (by omega)]

def roomAcrossBlank (beforeBlank : Nat → Bool)
    (roomBefore : Nat → Bool) (roomAfter : Bool → Nat → Bool)
    (atTop : Bool) (f : Nat) : Bool :=
  if beforeBlank f then roomBefore f else roomAfter atTop f

theorem I3_before_blank_choice_independent
    (ready beforeBlank roomBefore : Nat → Bool)
    (roomAfter : Bool → Nat → Bool)
    (beforePrefix : ∀ g f, g < f → beforeBlank f = true → beforeBlank g = true)
    (f : Nat) (before : beforeBlank f = true) (topA topB : Bool) :
    greedyFigure ready (roomAcrossBlank beforeBlank roomBefore roomAfter topA) f =
      greedyFigure ready (roomAcrossBlank beforeBlank roomBefore roomAfter topB) f := by
  apply I3_greedyFigure_congr_through
  intro g through
  have earlier : beforeBlank g = true := by
    by_cases same : g = f
    · simpa [same] using before
    · exact beforePrefix g f (by omega) before
  simp [roomAcrossBlank, earlier]

def blankTopFromFigures (used : Nat) (earlierText : Bool)
    (count : Nat) (beforeBlank kept : Nat → Bool) : Bool :=
  decide (used = 0) && !earlierText &&
    !((List.range count).any (fun f => beforeBlank f && kept f))

theorem I3_blank_top_decision_independent
    (used count : Nat) (earlierText : Bool)
    (ready beforeBlank roomBefore : Nat → Bool)
    (roomAfter : Bool → Nat → Bool)
    (beforePrefix : ∀ g f, g < f → beforeBlank f = true → beforeBlank g = true)
    (topA topB : Bool) :
    blankTopFromFigures used earlierText count beforeBlank
      (greedyFigure ready (roomAcrossBlank beforeBlank roomBefore roomAfter topA)) =
    blankTopFromFigures used earlierText count beforeBlank
      (greedyFigure ready (roomAcrossBlank beforeBlank roomBefore roomAfter topB)) := by
  let keptA := greedyFigure ready (roomAcrossBlank beforeBlank roomBefore roomAfter topA)
  let keptB := greedyFigure ready (roomAcrossBlank beforeBlank roomBefore roomAfter topB)
  have itemEq : ∀ f, (beforeBlank f && keptA f) = (beforeBlank f && keptB f) := by
    intro f
    cases before : beforeBlank f with
    | false => simp [before]
    | true =>
        simpa [before, keptA, keptB] using
          I3_before_blank_choice_independent ready beforeBlank roomBefore roomAfter
            beforePrefix f before topA topB
  have anyEq (xs : List Nat) :
      xs.any (fun f => beforeBlank f && keptA f) =
        xs.any (fun f => beforeBlank f && keptB f) := by
    induction xs with
    | nil => rfl
    | cons f rest ih => simp [List.any, itemEq f, ih]
  exact congrArg (fun xs => decide (used = 0) && !earlierText && !xs)
    (anyEq (List.range count))

theorem I3_greedyFigures_rule (count : Nat) (ready room : Nat → Bool) :
    figuresRule count (greedyFigure ready room)
      (fun f => ready f = true) (fun f => room f = true) := by
  intro f _
  constructor
  · intro present
    have parts : (figurePrefixReady ready room f = true ∧
        ready f = true) ∧ room f = true := by
      simpa [greedyFigure, Bool.and_eq_true] using present
    exact ⟨parts.1.2,
      (I3_figurePrefixReady_iff_all_prior ready room f).mp parts.1.1,
      parts.2⟩
  · rintro ⟨readyNow, prior, roomNow⟩
    have hprefix := (I3_figurePrefixReady_iff_all_prior ready room f).mpr prior
    simp [greedyFigure, hprefix, readyNow, roomNow]

theorem I3_blankFigureOrder_causal_exists
    (used count : Nat) (earlierText : Bool)
    (ready beforeBlank roomBefore : Nat → Bool)
    (roomAfter : Bool → Nat → Bool)
    (beforePrefix : ∀ g f, g < f → beforeBlank f = true → beforeBlank g = true) :
    ∃ atTop : Bool, ∃ kept : Nat → Bool,
      atTop = blankTopFromFigures used earlierText count beforeBlank kept ∧
      figuresRule count kept (fun f => ready f = true)
        (fun f => roomAcrossBlank beforeBlank roomBefore roomAfter atTop f = true) := by
  let keptAssumingTop := greedyFigure ready
    (roomAcrossBlank beforeBlank roomBefore roomAfter true)
  let atTop := blankTopFromFigures used earlierText count beforeBlank keptAssumingTop
  let kept := greedyFigure ready
    (roomAcrossBlank beforeBlank roomBefore roomAfter atTop)
  refine ⟨atTop, kept, ?_, ?_⟩
  · simpa [atTop, kept, keptAssumingTop] using
      (I3_blank_top_decision_independent used count earlierText ready
        beforeBlank roomBefore roomAfter beforePrefix true atTop)
  · exact I3_greedyFigures_rule count ready
      (roomAcrossBlank beforeBlank roomBefore roomAfter atTop)

/- The line-count part of Alloy `figures` for figures numbered in source
   order. `textBefore f` counts all text before f; `blankBefore f` is true
   exactly when the model's one blank precedes f and is not at column top.
   The actual `figures` predicate also requires those text items and every
   earlier figure to be kept, represented by `figuresRule`. -/
def priorFigureLines (size : Nat → Nat) (f : Nat) : Nat :=
  (List.range f).foldl (fun used g => used + size g) 0

def figureHasRoom (capacity used : Nat) (textBefore size : Nat → Nat)
    (blankBefore : Nat → Bool) (f : Nat) : Prop :=
  used + textBefore f + priorFigureLines size f +
    (if blankBefore f then 1 else 0) + size f ≤ capacity

def figuresRuleWithLoad (count capacity used : Nat) (kept : Nat → Bool)
    (textReady : Nat → Prop) (textBefore size : Nat → Nat)
    (blankBefore : Nat → Bool) : Prop :=
  figuresRule count kept textReady
    (figureHasRoom capacity used textBefore size blankBefore)

theorem I3_blankFigureOrder_figures_with_load_exist
    (count capacity used : Nat) (earlierText : Bool)
    (ready beforeBlank : Nat → Bool) (textBefore size : Nat → Nat)
    (beforePrefix : ∀ g f, g < f → beforeBlank f = true → beforeBlank g = true) :
    ∃ atTop : Bool, ∃ kept : Nat → Bool,
      atTop = blankTopFromFigures used earlierText count beforeBlank kept ∧
      figuresRuleWithLoad count capacity used kept
        (fun f => ready f = true) textBefore size
        (fun f => !beforeBlank f && !atTop) := by
  let roomBefore : Nat → Bool := fun f =>
    decide (used + textBefore f + priorFigureLines size f + size f ≤ capacity)
  let roomAfter : Bool → Nat → Bool := fun top f =>
    decide (used + textBefore f + priorFigureLines size f +
      (if top then 0 else 1) + size f ≤ capacity)
  obtain ⟨top, kept, topEq, rule⟩ :=
    I3_blankFigureOrder_causal_exists used count earlierText ready beforeBlank
      roomBefore roomAfter beforePrefix
  refine ⟨top, kept, topEq, ?_⟩
  unfold figuresRuleWithLoad
  intro f bound
  have current := rule f bound
  cases hbefore : beforeBlank f <;> cases htop : top <;>
    simpa [roomAcrossBlank, roomBefore, roomAfter, figureHasRoom,
      hbefore, htop] using current

theorem I3_figuresRuleWithLoad_exists
    (count capacity used : Nat) (textReady : Nat → Bool)
    (textBefore size : Nat → Nat) (blankBefore : Nat → Bool) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad count capacity used kept
        (fun f => textReady f = true) textBefore size blankBefore := by
  let room : Nat → Bool := fun f =>
    decide (used + textBefore f + priorFigureLines size f +
      (if blankBefore f then 1 else 0) + size f ≤ capacity)
  refine ⟨greedyFigure textReady room, ?_⟩
  simpa [figuresRuleWithLoad, room, figureHasRoom] using
    (I3_greedyFigures_rule count textReady room)

theorem I3_kept_figure_has_room (count capacity used : Nat)
    (kept : Nat → Bool) (textReady : Nat → Prop)
    (textBefore size : Nat → Nat) (blankBefore : Nat → Bool)
    (rule : figuresRuleWithLoad count capacity used kept textReady textBefore size blankBefore)
    (f : Nat) (bound : f < count) (present : kept f = true) :
    figureHasRoom capacity used textBefore size blankBefore f := by
  exact ((rule f bound).mp present).2.2

theorem I3_figuresRule_implies_figuresInOrder (count : Nat)
    (kept : Nat → Bool) (textReady room : Nat → Prop)
    (rule : figuresRule count kept textReady room) :
    figuresInOrder count kept := by
  unfold figuresInOrder
  intro f bound present g before
  exact ((rule f bound).mp present).2.1 g before

theorem I3_figuresRule_and_order_iff_rule (count : Nat)
    (kept : Nat → Bool) (textReady room : Nat → Prop) :
    (figuresRule count kept textReady room ∧ figuresInOrder count kept) ↔
      figuresRule count kept textReady room := by
  constructor
  · exact And.left
  · intro rule
    exact ⟨rule, I3_figuresRule_implies_figuresInOrder count kept textReady room rule⟩

/- Alloy `waitingIn` selects an unkept figure with an earlier unkept
   figure. Under `figureOrder`, every later figure after the first sent
   figure is also sent and therefore waits. -/
def figureWaits (kept : Nat → Bool) (f : Nat) : Prop :=
  kept f = false ∧ ∃ g, g < f ∧ kept g = false

def earlierFigureSent (kept : Nat → Bool) : Nat → Bool
  | 0 => false
  | f + 1 => earlierFigureSent kept f || !kept f

def waitingFigureBool (kept : Nat → Bool) (f : Nat) : Bool :=
  !kept f && earlierFigureSent kept f

theorem I3_earlierFigureSent_iff (kept : Nat → Bool) (f : Nat) :
    earlierFigureSent kept f = true ↔
      ∃ g, g < f ∧ kept g = false := by
  induction f with
  | zero =>
      constructor
      · intro impossible
        simp [earlierFigureSent] at impossible
      · rintro ⟨g, before, _⟩
        exact False.elim (Nat.not_lt_zero g before)
  | succ f ih =>
      simp [earlierFigureSent, Bool.or_eq_true, ih]
      constructor
      · rintro (⟨g, before, sent⟩ | sent)
        · exact ⟨g, by omega, sent⟩
        · exact ⟨f, by omega, sent⟩
      · rintro ⟨g, before, sent⟩
        by_cases same : g = f
        · exact Or.inr (by simpa [same] using sent)
        · exact Or.inl ⟨g, by omega, sent⟩

theorem I3_waitingFigureBool_iff_waitingIn (kept : Nat → Bool) (f : Nat) :
    waitingFigureBool kept f = true ↔ figureWaits kept f := by
  simp [waitingFigureBool, figureWaits, Bool.and_eq_true,
    I3_earlierFigureSent_iff]

def waitingAtTwoPositions (firstPos secondPos : Nat)
    (kept : Nat → Bool) (pos : Nat) : Bool :=
  if pos = firstPos then waitingFigureBool kept 0
  else if pos = secondPos then waitingFigureBool kept 1
  else false

theorem I3_waitingAtTwoPositions_matches_waitingIn
    (firstPos secondPos : Nat) (different : firstPos ≠ secondPos)
    (kept : Nat → Bool) :
    waitingAtTwoPositions firstPos secondPos kept firstPos = false ∧
      (waitingAtTwoPositions firstPos secondPos kept secondPos = true ↔
        figureWaits kept 1) := by
  constructor
  · simp [waitingAtTwoPositions, waitingFigureBool, earlierFigureSent]
  · simpa [waitingAtTwoPositions, Ne.symm different] using
      (I3_waitingFigureBool_iff_waitingIn kept 1)

theorem waitingIn_after_first_sent (count : Nat) (kept : Nat → Bool)
    (ordered : figuresInOrder count kept)
    (g f : Nat) (before : g < f) (bound : f < count)
    (sent : kept g = false) :
    figureWaits kept f := by
  exact ⟨(figuresInOrder_iff_no_reentry count kept).mp ordered g f before bound sent,
    ⟨g, before, sent⟩⟩

/- The `blankWithNext` clause for one blank. Candidate items are in source
   order after excluding other blanks and need markers; waiting figures are
   removed by `nextAfterWaiting`. `inColumn` encodes the corresponding
   Alloy membership predicate. -/
def blankPlaced {α : Type} (waiting : α → Bool) (items : List α)
    (inColumn : α → Bool) (atTop : Bool) : Bool :=
  match nextAfterWaiting waiting items with
  | none => false
  | some i => inColumn i && !atTop

def sourceInColumn (textHere keptFigure : Nat → Bool)
    (item : SourceCandidate) : Bool :=
  if item.figure then keptFigure item.pos else textHere item.pos

def keptBeforeBlank (blankPos : Nat) (textHere keptFigure : Nat → Bool) :
    SourceItem → Bool
  | .text pos => decide (pos < blankPos) && textHere pos
  | .figure pos => decide (pos < blankPos) && keptFigure pos
  | .blank _ => false
  | .need _ => false

def blankAtTopSource (used blankPos : Nat) (items : List SourceItem)
    (textHere keptFigure : Nat → Bool) : Bool :=
  decide (used = 0) && !(items.any (keptBeforeBlank blankPos textHere keptFigure))

theorem I3_blankAtTopSource_iff_empty_before
    (used blankPos : Nat) (items : List SourceItem)
    (textHere keptFigure : Nat → Bool) :
    blankAtTopSource used blankPos items textHere keptFigure = true ↔
      used = 0 ∧
        ∀ item ∈ items, keptBeforeBlank blankPos textHere keptFigure item = false := by
  have anyFalse :
      items.any (keptBeforeBlank blankPos textHere keptFigure) = false ↔
        ∀ item ∈ items, keptBeforeBlank blankPos textHere keptFigure item = false := by
    constructor
    · intro none item member
      cases h : keptBeforeBlank blankPos textHere keptFigure item with
      | false => rfl
      | true =>
          have someItem := (List.any_eq_true).mpr ⟨item, member, h⟩
          simp [none] at someItem
    · intro allNone
      cases h : items.any (keptBeforeBlank blankPos textHere keptFigure) with
      | false => rfl
      | true =>
          obtain ⟨item, member, present⟩ := (List.any_eq_true).mp h
          have absent := allNone item member
          simp [present] at absent
  simp [blankAtTopSource, Bool.and_eq_true, Bool.not_eq_true, anyFalse]

def blankPlacedFromSource (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (textHere keptFigure : Nat → Bool)
    (atTop : Bool) : Bool :=
  match nextOfSource blankPos waitingFigure items with
  | none => false
  | some item => sourceInColumn textHere keptFigure item && !atTop

def blankPlacedFromSourceFull (used blankPos : Nat)
    (waitingFigure : Nat → Bool) (items : List SourceItem)
    (textHere keptFigure : Nat → Bool) : Bool :=
  blankPlacedFromSource blankPos waitingFigure items textHere keptFigure
    (blankAtTopSource used blankPos items textHere keptFigure)

def blankPlaced25FromSourceFull (used blankPos : Nat)
    (items : List SourceItem) (textHere keptFigure : Nat → Bool) : Bool :=
  match (candidatesAfterBlank blankPos items).head? with
  | none => false
  | some candidate =>
      sourceInColumn textHere keptFigure candidate &&
        !(blankAtTopSource used blankPos items textHere keptFigure)

theorem I3_old_blank_placed_implies_new
    (used blankPos : Nat) (items : List SourceItem)
    (waitingFigure textHere keptFigure : Nat → Bool)
    (noWaitingHere : ∀ pos, waitingFigure pos = true → keptFigure pos = false)
    (oldPlaced : blankPlaced25FromSourceFull used blankPos items
      textHere keptFigure = true) :
    blankPlacedFromSourceFull used blankPos waitingFigure items
      textHere keptFigure = true := by
  cases h : candidatesAfterBlank blankPos items with
  | nil => simp [blankPlaced25FromSourceFull, h] at oldPlaced
  | cons candidate rest =>
      have old : sourceInColumn textHere keptFigure candidate &&
          !blankAtTopSource used blankPos items textHere keptFigure = true := by
        simpa [blankPlaced25FromSourceFull, h] using oldPlaced
      simp [Bool.and_eq_true] at old
      have inColumn := old.1
      have notTop := old.2
      have candidateNotWaiting : candidateWaits waitingFigure candidate = false := by
        cases figure : candidate.figure with
        | false => simp [candidateWaits, figure]
        | true =>
          have kept : keptFigure candidate.pos = true := by
            simpa [sourceInColumn, figure] using inColumn
          have notWaiting : waitingFigure candidate.pos = false := by
            cases waiting : waitingFigure candidate.pos with
            | false => rfl
            | true =>
                have absent := noWaitingHere candidate.pos waiting
                simp [kept] at absent
          simp [candidateWaits, figure, notWaiting]
      unfold blankPlacedFromSourceFull blankPlacedFromSource
      rw [I3_nextOfSource_eq_filtered_candidates]
      simp [h, nextAfterWaiting, candidateNotWaiting, inColumn, notTop]

theorem I3_blankPlacedFromSourceFull_iff_next_in_column
    (used blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (textHere keptFigure : Nat → Bool) :
    blankPlacedFromSourceFull used blankPos waitingFigure items textHere keptFigure = true ↔
      ∃ candidate,
        nextOfSource blankPos waitingFigure items = some candidate ∧
        sourceInColumn textHere keptFigure candidate = true ∧
        blankAtTopSource used blankPos items textHere keptFigure = false := by
  unfold blankPlacedFromSourceFull blankPlacedFromSource
  cases h : nextOfSource blankPos waitingFigure items with
  | none => simp [h]
  | some candidate =>
      cases hc : sourceInColumn textHere keptFigure candidate <;>
        cases ht : blankAtTopSource used blankPos items textHere keptFigure <;>
        simp [h, hc, ht]

theorem I3_blank_placed_at_zero_text_break_has_kept_figure
    (used blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (keptFigure : Nat → Bool)
    (placed : blankPlacedFromSourceFull used blankPos waitingFigure
      items (fun _ => false) keptFigure = true) :
    ∃ candidate,
      nextOfSource blankPos waitingFigure items = some candidate ∧
      candidate.figure = true ∧ keptFigure candidate.pos = true ∧
      blankAtTopSource used blankPos items (fun _ => false) keptFigure = false := by
  obtain ⟨candidate, next, inColumn, notTop⟩ :=
    (I3_blankPlacedFromSourceFull_iff_next_in_column used blankPos waitingFigure
      items (fun _ => false) keptFigure).mp placed
  cases hfigure : candidate.figure with
  | false => simp [sourceInColumn, hfigure] at inColumn
  | true =>
      have kept : keptFigure candidate.pos = true := by
        simpa [sourceInColumn, hfigure] using inColumn
      exact ⟨candidate, next, hfigure, kept, notTop⟩

theorem I3_two_figure_fits_from_blank_cause
    (capacity used firstSize secondSize : Nat)
    (first second placed beforeFirst beforeSecond : Bool)
    (usedFits : used ≤ capacity)
    (firstFits : first = true →
      used + (if beforeFirst then 1 else 0) + firstSize ≤ capacity)
    (secondFits : second = true →
      used + firstSize + (if beforeSecond then 1 else 0) + secondSize ≤ capacity)
    (figureOrder : second = true → first = true)
    (blankOrder : beforeFirst = true → beforeSecond = true)
    (placedCause : placed = true →
      (first = true ∧ beforeFirst = true) ∨
      (second = true ∧ beforeSecond = true)) :
    used + (if first then firstSize else 0) +
      (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  cases first <;> cases second <;> cases placed <;>
    cases beforeFirst <;> cases beforeSecond <;> simp_all <;> omega

def keptAtTwoPositions (firstPos secondPos : Nat)
    (first second : Bool) (pos : Nat) : Bool :=
  if pos = firstPos then first else if pos = secondPos then second else false

def blankBeforePosition (used blankPos : Nat) (items : List SourceItem)
    (keptFigure : Nat → Bool) (figurePos : Nat) : Bool :=
  decide (blankPos < figurePos) &&
    !blankAtTopSource used blankPos items (fun _ => false) keptFigure

theorem I3_blank_source_two_figures_cause
    (used blankPos firstPos secondPos : Nat) (first second : Bool)
    (waitingFigure : Nat → Bool) (items : List SourceItem)
    (different : firstPos ≠ secondPos)
    (onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = firstPos ∨ pos = secondPos)
    (placed : blankPlacedFromSourceFull used blankPos waitingFigure items
      (fun _ => false) (keptAtTwoPositions firstPos secondPos first second) = true) :
    (first = true ∧ blankBeforePosition used blankPos items
      (keptAtTwoPositions firstPos secondPos first second) firstPos = true) ∨
    (second = true ∧ blankBeforePosition used blankPos items
      (keptAtTwoPositions firstPos secondPos first second) secondPos = true) := by
  obtain ⟨candidate, next, figure, kept, notTop⟩ :=
    I3_blank_placed_at_zero_text_break_has_kept_figure used blankPos
      waitingFigure items (keptAtTwoPositions firstPos secondPos first second) placed
  obtain ⟨item, member, selected, _⟩ :=
    I3_nextOfSource_some_has_member blankPos waitingFigure items candidate next
  cases item with
  | text pos =>
      by_cases after : blankPos < pos
      · have same : candidate = ⟨pos, false⟩ := by
          simpa [candidateAfterBlank, after] using selected.symm
        subst candidate
        simp at figure
      · simp [candidateAfterBlank, after] at selected
  | figure pos =>
      have after : blankPos < pos := by
        by_cases h : blankPos < pos
        · exact h
        · simp [candidateAfterBlank, h] at selected
      have same : candidate = ⟨pos, true⟩ := by
        simpa [candidateAfterBlank, after] using selected.symm
      subst candidate
      rcases onlyTwo pos member with firstPosEq | secondPosEq
      · subst pos
        left
        constructor
        · simpa [keptAtTwoPositions] using kept
        · simp [blankBeforePosition, after, notTop]
      · subst pos
        right
        constructor
        · simpa [keptAtTwoPositions, Ne.symm different] using kept
        · simp [blankBeforePosition, after, notTop]
  | blank pos => simp [candidateAfterBlank] at selected
  | need pos => simp [candidateAfterBlank] at selected

theorem I3_two_figure_fits_with_arbitrary_source
    (capacity used blankPos firstPos secondPos firstSize secondSize : Nat)
    (first second : Bool) (waitingFigure : Nat → Bool)
    (items : List SourceItem)
    (usedFits : used ≤ capacity) (ordered : firstPos < secondPos)
    (onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = firstPos ∨ pos = secondPos)
    (firstFits : first = true →
      used + (if blankBeforePosition used blankPos items
        (keptAtTwoPositions firstPos secondPos first second) firstPos then 1 else 0) +
        firstSize ≤ capacity)
    (secondFits : second = true →
      used + firstSize + (if blankBeforePosition used blankPos items
        (keptAtTwoPositions firstPos secondPos first second) secondPos then 1 else 0) +
        secondSize ≤ capacity)
    (figureOrder : second = true → first = true) :
    let placed := blankPlacedFromSourceFull used blankPos waitingFigure items
      (fun _ => false) (keptAtTwoPositions firstPos secondPos first second)
    used + (if first then firstSize else 0) +
      (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  let keptAt := keptAtTwoPositions firstPos secondPos first second
  let beforeFirst := blankBeforePosition used blankPos items keptAt firstPos
  let beforeSecond := blankBeforePosition used blankPos items keptAt secondPos
  let placed := blankPlacedFromSourceFull used blankPos waitingFigure items
    (fun _ => false) keptAt
  apply I3_two_figure_fits_from_blank_cause capacity used firstSize secondSize
    first second placed beforeFirst beforeSecond usedFits firstFits secondFits
    figureOrder
  · intro before
    simp [beforeFirst, beforeSecond, blankBeforePosition,
      Bool.and_eq_true] at before ⊢
    exact ⟨by omega, before.2⟩
  · intro placedHere
    exact I3_blank_source_two_figures_cause used blankPos firstPos secondPos
      first second waitingFigure items (Nat.ne_of_lt ordered) onlyTwo placedHere

theorem I3_blankAtTop_two_figures_source
    (used blankPos firstPos secondPos : Nat) (first second : Bool)
    (items : List SourceItem) (different : firstPos ≠ secondPos)
    (firstIn : .figure firstPos ∈ items)
    (secondIn : second = true → .figure secondPos ∈ items)
    (onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = firstPos ∨ pos = secondPos) :
    blankAtTopSource used blankPos items (fun _ => false)
      (keptAtTwoPositions firstPos secondPos first second) =
    blankTopFromFigures used false 2
      (fun i => if i = 0 then decide (firstPos < blankPos)
        else decide (secondPos < blankPos))
      (fun i => if i = 0 then first else second) := by
  let keptAt := keptAtTwoPositions firstPos secondPos first second
  let sourceAny := items.any (keptBeforeBlank blankPos (fun _ => false) keptAt)
  let pairAny :=
    (decide (firstPos < blankPos) && first) ||
      (decide (secondPos < blankPos) && second)
  have sourceIff : sourceAny = true ↔
      (firstPos < blankPos ∧ first = true) ∨
        (secondPos < blankPos ∧ second = true) := by
    constructor
    · intro found
      obtain ⟨item, member, hit⟩ := (List.any_eq_true).mp found
      cases item with
      | text pos => simp [keptBeforeBlank] at hit
      | blank pos => simp [keptBeforeBlank] at hit
      | need pos => simp [keptBeforeBlank] at hit
      | figure pos =>
          simp [keptBeforeBlank, Bool.and_eq_true] at hit
          have before : pos < blankPos := by
            simpa using hit.1
          have present : keptAt pos = true := hit.2
          rcases onlyTwo pos member with hp | hp
          · subst pos
            left
            exact ⟨before, by simpa [keptAt, keptAtTwoPositions] using present⟩
          · subst pos
            right
            exact ⟨before, by simpa [keptAt, keptAtTwoPositions, Ne.symm different] using present⟩
    · rintro (⟨before, present⟩ | ⟨before, present⟩)
      · apply (List.any_eq_true).mpr
        exact ⟨.figure firstPos, firstIn,
          by simp [keptBeforeBlank, keptAt, keptAtTwoPositions, before, present]⟩
      · apply (List.any_eq_true).mpr
        exact ⟨.figure secondPos, secondIn present,
          by simp [keptBeforeBlank, keptAt, keptAtTwoPositions,
            Ne.symm different, before, present]⟩
  have pairIff : pairAny = true ↔
      (firstPos < blankPos ∧ first = true) ∨
        (secondPos < blankPos ∧ second = true) := by
    simp [pairAny, Bool.or_eq_true, Bool.and_eq_true]
  have anyEq : sourceAny = pairAny := by
    cases hs : sourceAny <;> cases hp : pairAny <;>
      simp_all [sourceIff, pairIff]
  calc
    blankAtTopSource used blankPos items (fun _ => false)
        (keptAtTwoPositions firstPos secondPos first second) =
        (decide (used = 0) && !sourceAny) := by
          simp [blankAtTopSource, sourceAny, keptAt]
    _ = (decide (used = 0) && !pairAny) := by rw [anyEq]
    _ = blankTopFromFigures used false 2
        (fun i => if i = 0 then decide (firstPos < blankPos)
          else decide (secondPos < blankPos))
        (fun i => if i = 0 then first else second) := by
          simp [blankTopFromFigures, pairAny,
            show List.range 2 = [0, 1] from rfl]

theorem I3_blankAtTop_one_figure_source
    (used blankPos figurePos : Nat) (kept : Bool)
    (items : List SourceItem) (figureIn : .figure figurePos ∈ items)
    (onlyOne : ∀ pos, .figure pos ∈ items → pos = figurePos) :
    blankAtTopSource used blankPos items (fun _ => false)
      (keptAtTwoPositions figurePos (figurePos + 1) kept false) =
      blankTopFromFigures used false 1
        (fun _ => decide (figurePos < blankPos)) (fun _ => kept) := by
  have two := I3_blankAtTop_two_figures_source used blankPos figurePos
    (figurePos + 1) kept false items (Nat.ne_of_lt (Nat.lt_succ_self figurePos))
    figureIn (by intro impossible; cases impossible)
    (by intro pos member; exact Or.inl (onlyOne pos member))
  simpa [blankTopFromFigures,
    show List.range 1 = [0] from rfl,
    show List.range 2 = [0, 1] from rfl] using two

def beforeBlankMask (firstPos secondPos blankPos : Nat) (index : Nat) : Bool :=
  if index = 0 then decide (firstPos < blankPos)
  else if index = 1 then decide (secondPos < blankPos)
  else false

theorem I3_beforeBlankMask_prefix
    (firstPos secondPos blankPos : Nat) (ordered : firstPos < secondPos) :
    ∀ g f, g < f → beforeBlankMask firstPos secondPos blankPos f = true →
      beforeBlankMask firstPos secondPos blankPos g = true := by
  intro g f earlier before
  cases f with
  | zero => exact False.elim (Nat.not_lt_zero g earlier)
  | succ f =>
      cases f with
      | zero =>
          cases g with
          | zero =>
              simp [beforeBlankMask] at before ⊢
              omega
          | succ g =>
              exact False.elim (Nat.not_lt_zero g
                (Nat.lt_of_succ_lt_succ earlier))
      | succ f =>
          simp [beforeBlankMask] at before

theorem I3_blankBeforePosition_complement
    (used blankPos figurePos : Nat) (items : List SourceItem)
    (keptFigure : Nat → Bool) (different : blankPos ≠ figurePos) :
    blankBeforePosition used blankPos items keptFigure figurePos =
      (!decide (figurePos < blankPos) &&
        !blankAtTopSource used blankPos items (fun _ => false) keptFigure) := by
  by_cases after : blankPos < figurePos
  · have notBefore : ¬ figurePos < blankPos := by omega
    simp [blankBeforePosition, after, notBefore]
  · have before : figurePos < blankPos := by omega
    simp [blankBeforePosition, after, before]

theorem I3_blankFigureOrder_arbitrary_source_exists
    (capacity used blankPos firstPos secondPos firstSize secondSize : Nat)
    (ready : Nat → Bool) (textBefore : Nat → Nat)
    (waitingFigureOf : (Nat → Bool) → Nat → Bool) (items : List SourceItem)
    (usedFits : used ≤ capacity) (ordered : firstPos < secondPos)
    (blankFirstDifferent : blankPos ≠ firstPos)
    (blankSecondDifferent : blankPos ≠ secondPos)
    (firstIn : .figure firstPos ∈ items)
    (secondIn : .figure secondPos ∈ items)
    (onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = firstPos ∨ pos = secondPos) :
    ∃ atTop : Bool, ∃ kept : Nat → Bool, ∃ placed : Bool,
      figuresRuleWithLoad 2 capacity used kept
        (fun f => ready f = true) textBefore
        (fun f => if f = 0 then firstSize else secondSize)
        (fun f => !beforeBlankMask firstPos secondPos blankPos f && !atTop) ∧
      atTop = blankAtTopSource used blankPos items (fun _ => false)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      placed = blankPlacedFromSourceFull used blankPos (waitingFigureOf kept) items
        (fun _ => false)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      used + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) +
        (if placed then 1 else 0) ≤ capacity := by
  let mask := beforeBlankMask firstPos secondPos blankPos
  let size : Nat → Nat := fun f => if f = 0 then firstSize else secondSize
  obtain ⟨top, kept, topModel, rule⟩ :=
    I3_blankFigureOrder_figures_with_load_exist 2 capacity used false
      ready mask textBefore size
      (I3_beforeBlankMask_prefix firstPos secondPos blankPos ordered)
  let keptAt := keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)
  have topActual : top = blankAtTopSource used blankPos items (fun _ => false) keptAt := by
    calc
      top = blankTopFromFigures used false 2 mask kept := topModel
      _ = blankTopFromFigures used false 2
          (fun i => if i = 0 then decide (firstPos < blankPos)
            else decide (secondPos < blankPos))
          (fun i => if i = 0 then kept 0 else kept 1) := by
            simp [blankTopFromFigures, mask, beforeBlankMask,
              show List.range 2 = [0, 1] from rfl]
      _ = blankAtTopSource used blankPos items (fun _ => false) keptAt := by
            exact (I3_blankAtTop_two_figures_source used blankPos firstPos
              secondPos (kept 0) (kept 1) items (Nat.ne_of_lt ordered)
              firstIn (fun _ => secondIn) onlyTwo).symm
  let placed := blankPlacedFromSourceFull used blankPos (waitingFigureOf kept) items
    (fun _ => false) keptAt
  refine ⟨top, kept, placed, rule, topActual, rfl, ?_⟩
  have firstRoom : kept 0 = true →
      used + (if blankBeforePosition used blankPos items keptAt firstPos then 1 else 0) +
        firstSize ≤ capacity := by
    intro present
    have room := I3_kept_figure_has_room 2 capacity used kept
      (fun f => ready f = true) textBefore size
      (fun f => !mask f && !top) rule 0 (by decide) present
    have beforeEq : blankBeforePosition used blankPos items keptAt firstPos =
        (!mask 0 && !top) := by
      rw [I3_blankBeforePosition_complement used blankPos firstPos items
        keptAt blankFirstDifferent, topActual]
      rfl
    rw [beforeEq]
    simp [figureHasRoom, priorFigureLines, size, mask, beforeBlankMask] at room ⊢
    omega
  have secondRoom : kept 1 = true →
      used + firstSize +
        (if blankBeforePosition used blankPos items keptAt secondPos then 1 else 0) +
        secondSize ≤ capacity := by
    intro present
    have room := I3_kept_figure_has_room 2 capacity used kept
      (fun f => ready f = true) textBefore size
      (fun f => !mask f && !top) rule 1 (by decide) present
    have beforeEq : blankBeforePosition used blankPos items keptAt secondPos =
        (!mask 1 && !top) := by
      rw [I3_blankBeforePosition_complement used blankPos secondPos items
        keptAt blankSecondDifferent, topActual]
      rfl
    rw [beforeEq]
    simp [figureHasRoom, priorFigureLines, size, mask, beforeBlankMask,
      show List.range 1 = [0] from rfl] at room ⊢
    omega
  have orderedFigures : kept 1 = true → kept 0 = true := by
    intro present
    exact ((rule 1 (by decide)).mp present).2.1 0 (by decide)
  exact I3_two_figure_fits_with_arbitrary_source capacity used blankPos
    firstPos secondPos firstSize secondSize (kept 0) (kept 1)
    (waitingFigureOf kept) items usedFits ordered onlyTwo firstRoom secondRoom orderedFigures

theorem I3_blankFigureOrder_one_figure_arbitrary_source_exists
    (capacity used blankPos figurePos figureSize : Nat)
    (ready : Nat → Bool) (textBefore : Nat → Nat)
    (waitingFigureOf : (Nat → Bool) → Nat → Bool) (items : List SourceItem)
    (usedFits : used ≤ capacity) (blankDifferent : blankPos ≠ figurePos)
    (figureIn : .figure figurePos ∈ items)
    (onlyOne : ∀ pos, .figure pos ∈ items → pos = figurePos) :
    ∃ atTop : Bool, ∃ kept : Nat → Bool, ∃ placed : Bool,
      figuresRuleWithLoad 1 capacity used kept
        (fun f => ready f = true) textBefore (fun _ => figureSize)
        (fun f => !beforeBlankMask figurePos (figurePos + 1) blankPos f && !atTop) ∧
      atTop = blankAtTopSource used blankPos items (fun _ => false)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      placed = blankPlacedFromSourceFull used blankPos (waitingFigureOf kept) items
        (fun _ => false)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      used + (if kept 0 then figureSize else 0) +
        (if placed then 1 else 0) ≤ capacity := by
  let mask := beforeBlankMask figurePos (figurePos + 1) blankPos
  obtain ⟨top, kept, topModel, rule⟩ :=
    I3_blankFigureOrder_figures_with_load_exist 1 capacity used false
      ready mask textBefore (fun _ => figureSize)
      (I3_beforeBlankMask_prefix figurePos (figurePos + 1) blankPos
        (Nat.lt_succ_self figurePos))
  let keptAt := keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false
  have topActual : top = blankAtTopSource used blankPos items (fun _ => false) keptAt := by
    calc
      top = blankTopFromFigures used false 1 mask kept := topModel
      _ = blankTopFromFigures used false 1
          (fun _ => decide (figurePos < blankPos)) (fun _ => kept 0) := by
            simp [blankTopFromFigures, mask, beforeBlankMask,
              show List.range 1 = [0] from rfl]
      _ = blankAtTopSource used blankPos items (fun _ => false) keptAt := by
            exact (I3_blankAtTop_one_figure_source used blankPos figurePos
              (kept 0) items figureIn onlyOne).symm
  let placed := blankPlacedFromSourceFull used blankPos (waitingFigureOf kept) items
    (fun _ => false) keptAt
  refine ⟨top, kept, placed, rule, topActual, rfl, ?_⟩
  have firstRoom : kept 0 = true →
      used + (if blankBeforePosition used blankPos items keptAt figurePos then 1 else 0) +
        figureSize ≤ capacity := by
    intro present
    have room := I3_kept_figure_has_room 1 capacity used kept
      (fun f => ready f = true) textBefore (fun _ => figureSize)
      (fun f => !mask f && !top) rule 0 (by decide) present
    have beforeEq : blankBeforePosition used blankPos items keptAt figurePos =
        (!mask 0 && !top) := by
      rw [I3_blankBeforePosition_complement used blankPos figurePos items
        keptAt blankDifferent, topActual]
      rfl
    rw [beforeEq]
    simp [figureHasRoom, priorFigureLines, mask, beforeBlankMask] at room ⊢
    omega
  have fits := I3_two_figure_fits_with_arbitrary_source capacity used blankPos
    figurePos (figurePos + 1) figureSize 0 (kept 0) false
    (waitingFigureOf kept) items usedFits (Nat.lt_succ_self figurePos)
    (by intro pos member; exact Or.inl (onlyOne pos member))
    firstRoom (by intro impossible; cases impossible)
    (by intro impossible; cases impossible)
  simpa [placed] using fits

theorem I3_blankFigureOrder_no_figure_arbitrary_source_exists
    (capacity used blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (usedFits : used ≤ capacity) :
    ∃ placed : Bool,
      placed = blankPlacedFromSourceFull used blankPos waitingFigure items
        (fun _ => false) (fun _ => false) ∧
      used + (if placed then 1 else 0) ≤ capacity := by
  have absent : blankPlacedFromSourceFull used blankPos waitingFigure items
      (fun _ => false) (fun _ => false) = false := by
    cases h : blankPlacedFromSourceFull used blankPos waitingFigure items
      (fun _ => false) (fun _ => false) with
    | false => rfl
    | true =>
        obtain ⟨candidate, _, _, kept, _⟩ :=
          I3_blank_placed_at_zero_text_break_has_kept_figure used blankPos
            waitingFigure items (fun _ => false) h
        simp at kept
  exact ⟨false, absent.symm, by simpa using usedFits⟩

theorem I3_blankPlacedFromSource_eq_candidate_placement
    (blankPos : Nat) (waitingFigure : Nat → Bool)
    (items : List SourceItem) (textHere keptFigure : Nat → Bool)
    (atTop : Bool) :
    blankPlacedFromSource blankPos waitingFigure items textHere keptFigure atTop =
      blankPlaced (candidateWaits waitingFigure)
        (candidatesAfterBlank blankPos items)
        (sourceInColumn textHere keptFigure) atTop := by
  unfold blankPlacedFromSource blankPlaced
  rw [I3_nextOfSource_eq_filtered_candidates]
  cases nextAfterWaiting (candidateWaits waitingFigure)
    (candidatesAfterBlank blankPos items) <;> simp

example : blankPlacedFromSource 1 (fun pos => pos == 2)
    [.figure 0, .blank 1, .figure 2, .need 3, .text 4]
    (fun pos => pos == 4) (fun _ => false) false = true := by decide

example : blankPlacedFromSource 1 (fun pos => pos == 2)
    [.figure 0, .blank 1, .figure 2, .need 3]
    (fun _ => false) (fun _ => false) false = false := by decide

/- In the `inDomain26` inputs of `blankWithNext25`, there is no Need.
   Its next item is the head of the same source-order candidate list. -/
def blankPlaced25 (items : List Nat) (inColumn : Nat → Bool)
    (atTop : Bool) : Bool :=
  match items.head? with
  | none => false
  | some i => inColumn i && !atTop

theorem I3_blankPlaced_eq_25_when_none_wait (waiting : Nat → Bool)
    (items : List Nat) (inColumn : Nat → Bool) (atTop : Bool)
    (noneWait : ∀ x ∈ items, waiting x = false) :
    blankPlaced waiting items inColumn atTop =
      blankPlaced25 items inColumn atTop := by
  unfold blankPlaced blankPlaced25
  rw [nextAfterWaiting_eq_head_when_none_wait waiting items noneWait]
  cases items.head? <;> simp

example :
    blankPlaced25 [1, 2] (fun i => i == 2) false = false ∧
      blankPlaced (fun i => i == 1) [1, 2] (fun i => i == 2) false = true := by
  decide

theorem blankPlaced_iff_next_in_column (waiting : Nat → Bool)
    (items : List Nat) (inColumn : Nat → Bool) (atTop : Bool) :
    blankPlaced waiting items inColumn atTop = true ↔
      ∃ i, nextAfterWaiting waiting items = some i ∧
        inColumn i = true ∧ atTop = false := by
  unfold blankPlaced
  cases nextAfterWaiting waiting items with
  | none => simp
  | some i =>
      cases hi : inColumn i <;> cases ht : atTop <;> simp [hi, ht]

theorem I3_blank_dropped_after_all_wait (waiting : Nat → Bool)
    (items : List Nat) (inColumn : Nat → Bool) (atTop : Bool)
    (allWait : ∀ x ∈ items, waiting x = true) :
    blankPlaced waiting items inColumn atTop = false := by
  unfold blankPlaced
  rw [(I3_nextAfterWaiting_none_iff_all_wait waiting items).mpr allWait]

theorem blankBeforeWaiting25 :
    ∃ capacity used firstSize secondSize : Nat,
      capacity = 5 ∧ used = 4 ∧ firstSize = 4 ∧ secondSize = 5 ∧
      used + 1 ≤ capacity ∧
      decide (used + firstSize ≤ capacity) = false ∧
      decide (used + firstSize + secondSize ≤ capacity) = false ∧
      blankWithNext25Case false = false ∧
      blankWithNextCase false false true = true := by
  exact ⟨5, 4, 4, 5, by decide⟩

theorem waitingBlankSome :
    ∃ capacity used firstSize secondSize : Nat,
      capacity = 4 ∧ used = 2 ∧ firstSize = 4 ∧ secondSize = 4 ∧
      used + 1 + 1 ≤ capacity ∧
      decide (used + firstSize ≤ capacity) = false ∧
      decide (used + firstSize + secondSize ≤ capacity) = false ∧
      blankWithNextCase false false true = true := by
  exact ⟨4, 2, 4, 4, by decide⟩

/- One blank immediately before one figure, with no text. These are the
   `fits`, `figures`, `figureOrder`, and `blankWithNext` clauses of the
   Alloy `blankFigureOrder` command specialized to that order. -/
theorem blankFigureOrder_oneFigure (capacity used size : Nat) (top : Bool)
    (usedFits : used ≤ capacity) :
    ∃ kept placed : Bool,
      kept = decide (used + (if top then 0 else 1) + size ≤ capacity) ∧
      placed = decide (kept = true ∧ top = false) ∧
      used + (if kept then size else 0) + (if placed then 1 else 0) ≤ capacity := by
  by_cases room : used + (if top then 0 else 1) + size ≤ capacity
  · refine ⟨true, !top, ?_, ?_, ?_⟩
    · simp [room]
    · cases top <;> decide
    · cases top <;> simp_all <;> omega
  · refine ⟨false, false, ?_, ?_, ?_⟩
    · simp [room]
    · simp
    · simpa using usedFits

/- Two source-ordered figures after one blank and no text. With the blank
   first, it is dropped at the column top and otherwise follows the first
   kept figure. The second figure cannot be kept after the first is sent. -/
theorem blankFigureOrder_twoFiguresAfterBlank
    (capacity used firstSize secondSize : Nat)
    (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (used + (if used = 0 then 0 else 1) + firstSize ≤ capacity) ∧
      second = decide (first = true ∧
        used + (if used = 0 then 0 else 1) + firstSize + secondSize ≤ capacity) ∧
      placed = decide (first = true ∧ used ≠ 0) ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  by_cases top : used = 0
  · subst used
    by_cases firstFits : firstSize ≤ capacity
    · by_cases secondFits : firstSize + secondSize ≤ capacity
      · refine ⟨true, true, false, ?_, ?_, ?_, ?_⟩
        all_goals simp [firstFits, secondFits] <;> omega
      · refine ⟨true, false, false, ?_, ?_, ?_, ?_⟩
        all_goals simp [firstFits, secondFits] <;> omega
    · refine ⟨false, false, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits] <;> omega
  · by_cases firstFits : used + 1 + firstSize ≤ capacity
    · by_cases secondFits : used + 1 + firstSize + secondSize ≤ capacity
      · refine ⟨true, true, true, ?_, ?_, ?_, ?_⟩
        all_goals simp [top, firstFits, secondFits] <;> omega
      · refine ⟨true, false, true, ?_, ?_, ?_, ?_⟩
        all_goals simp [top, firstFits, secondFits] <;> omega
    · refine ⟨false, false, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [top, firstFits] <;> omega

/- The same no-text input with the blank between the two figures. If the
   first figure is sent, the second waits and the blank is dropped. -/
theorem blankFigureOrder_twoFiguresAroundBlank
    (capacity used firstSize secondSize : Nat)
    (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (used + firstSize ≤ capacity) ∧
      second = decide (first = true ∧
        used + firstSize + 1 + secondSize ≤ capacity) ∧
      placed = second ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  by_cases firstFits : used + firstSize ≤ capacity
  · by_cases secondFits : used + firstSize + 1 + secondSize ≤ capacity
    · refine ⟨true, true, true, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits, secondFits] <;> omega
    · refine ⟨true, false, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits, secondFits] <;> omega
  · refine ⟨false, false, false, ?_, ?_, ?_, ?_⟩
    all_goals simp [firstFits] <;> omega

/- The blank after both figures has no following block and is dropped. -/
theorem blankFigureOrder_twoFiguresBeforeBlank
    (capacity used firstSize secondSize : Nat)
    (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (used + firstSize ≤ capacity) ∧
      second = decide (first = true ∧
        used + firstSize + secondSize ≤ capacity) ∧
      placed = false ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  by_cases firstFits : used + firstSize ≤ capacity
  · by_cases secondFits : used + firstSize + secondSize ≤ capacity
    · refine ⟨true, true, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits, secondFits] <;> omega
    · refine ⟨true, false, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits, secondFits] <;> omega
  · refine ⟨false, false, false, ?_, ?_, ?_, ?_⟩
    all_goals simp [firstFits] <;> omega

theorem I3_blankWithNext_before_two_figures
    (used : Nat) (first second : Bool) :
    blankPlacedFromSourceFull used 0 (fun pos =>
      if pos = 1 then false else
        waitingFigureBool (fun i => if i = 0 then first else second) 1)
      [.blank 0, .figure 1, .figure 2]
      (fun _ => false)
      (fun pos => if pos = 1 then first else second) =
      decide (first = true ∧ used ≠ 0) := by
  cases first <;> cases second <;> cases used <;>
    simp [blankPlacedFromSourceFull, blankPlacedFromSource, blankAtTopSource,
      nextOfSource, candidateAfterBlank, candidateWaits, sourceInColumn,
      keptBeforeBlank, waitingFigureBool, earlierFigureSent]

theorem I3_blankWithNext_between_two_figures
    (used : Nat) (first second : Bool)
    (ordered : second = true → first = true) :
    blankPlacedFromSourceFull used 1 (fun _ =>
      waitingFigureBool (fun i => if i = 0 then first else second) 1)
      [.figure 0, .blank 1, .figure 2]
      (fun _ => false)
      (fun pos => if pos = 0 then first else second) = second := by
  cases first <;> cases second <;> cases used <;>
    simp_all [blankPlacedFromSourceFull, blankPlacedFromSource, blankAtTopSource,
      nextOfSource, candidateAfterBlank, candidateWaits, sourceInColumn,
      keptBeforeBlank, waitingFigureBool, earlierFigureSent]

theorem I3_blankWithNext_after_two_figures
    (used : Nat) (first second : Bool) :
    blankPlacedFromSourceFull used 2 (fun _ => false)
      [.figure 0, .figure 1, .blank 2]
      (fun _ => false)
      (fun pos => if pos = 0 then first else second) = false := by
  rfl

/- A zero-text break sends every text item on. `firstReady` and
   `secondReady` record whether each figure has any earlier text; unlike
   the preceding no-text theorem, either may therefore be unavailable. -/
def textReadyAtZeroBreak (textPositions : List Nat) (figurePos : Nat) : Prop :=
  ∀ t ∈ textPositions, figurePos ≤ t

def earlierTextItem (pos : Nat) : SourceItem → Bool
  | .text textPos => decide (textPos < pos)
  | _ => false

def textReadyZero (items : List SourceItem) (pos : Nat) : Bool :=
  !(items.any (earlierTextItem pos))

def textBeforeCount (items : List SourceItem) (pos : Nat) : Nat :=
  (items.filter (earlierTextItem pos)).length

def textHereAtBreak (items : List SourceItem) (brk pos : Nat) : Bool :=
  decide (textBeforeCount items pos < brk)

def strictTextPositions : List Nat → Prop
  | [] => True
  | x :: rest =>
      (∀ y ∈ rest, x < y) ∧ strictTextPositions rest

def textRank : List Nat → Nat → Nat
  | [], _ => 0
  | x :: rest, pos =>
      if x = pos then 0 else 1 + textRank rest pos

def countEarlierText (positions : List Nat) (pos : Nat) : Nat :=
  (positions.filter (fun x => x < pos)).length

theorem I3_count_earlier_text_eq_rank
    (positions : List Nat) (ordered : strictTextPositions positions)
    (pos : Nat) (member : pos ∈ positions) :
    countEarlierText positions pos = textRank positions pos := by
  induction positions with
  | nil => simp at member
  | cons x rest ih =>
      obtain ⟨before, restOrdered⟩ := ordered
      rcases List.mem_cons.mp member with same | inRest
      · subst pos
        have noneEarlier : rest.filter (fun y => y < x) = [] :=
          List.filter_eq_nil.mpr (by
            intro y inRest earlier
            have later := before y inRest
            simp at earlier
            omega)
        simp [countEarlierText, textRank, noneEarlier]
      · have earlier := before pos inRest
        have distinct : x ≠ pos := by omega
        have tail := ih restOrdered inRest
        simp [countEarlierText, textRank, earlier, distinct]
        simp only [countEarlierText] at tail
        omega

theorem I3_text_before_count_mapped_positions
    (positions : List Nat) (pos : Nat) :
    textBeforeCount (positions.map SourceItem.text) pos =
      countEarlierText positions pos := by
  induction positions with
  | nil => simp [textBeforeCount, countEarlierText]
  | cons x rest ih =>
      by_cases earlier : x < pos
      · simp [textBeforeCount, countEarlierText,
          earlierTextItem, earlier]
        simp only [textBeforeCount, countEarlierText] at ih
        omega
      · simp [textBeforeCount, countEarlierText,
          earlierTextItem, earlier]
        simp only [textBeforeCount, countEarlierText] at ih
        omega

theorem I3_text_here_iff_rank
    (positions : List Nat) (ordered : strictTextPositions positions)
    (pos brk : Nat) (member : pos ∈ positions) :
    textHereAtBreak (positions.map SourceItem.text) brk pos = true ↔
      textRank positions pos < brk := by
  rw [textHereAtBreak, I3_text_before_count_mapped_positions,
    I3_count_earlier_text_eq_rank positions ordered pos member]
  simp

def sourceTextPositions : List SourceItem → List Nat
  | [] => []
  | .text pos :: rest => pos :: sourceTextPositions rest
  | .figure _ :: rest | .blank _ :: rest | .need _ :: rest =>
      sourceTextPositions rest

theorem I3_source_text_position_member
    (items : List SourceItem) (pos : Nat) :
    pos ∈ sourceTextPositions items ↔ .text pos ∈ items := by
  induction items with
  | nil => simp [sourceTextPositions]
  | cons item rest ih =>
      cases item with
      | text p => simp [sourceTextPositions, ih]
      | figure p => simp [sourceTextPositions, ih]
      | blank p => simp [sourceTextPositions, ih]
      | need p => simp [sourceTextPositions, ih]

theorem I3_source_text_positions_ordered
    (items : List SourceItem) (ordered : sourceOrdered items) :
    strictTextPositions (sourceTextPositions items) := by
  induction items with
  | nil => trivial
  | cons item rest ih =>
      obtain ⟨headBefore, restOrdered⟩ := ordered
      cases item with
      | text pos =>
          constructor
          · intro later laterIn
            have textIn :=
              (I3_source_text_position_member rest later).mp laterIn
            have earlier := headBefore (.text later) textIn
            simpa [sourcePos] using earlier
          · exact ih restOrdered
      | figure _ => exact ih restOrdered
      | blank _ => exact ih restOrdered
      | need _ => exact ih restOrdered

theorem I3_source_text_before_count
    (items : List SourceItem) (pos : Nat) :
    textBeforeCount items pos =
      countEarlierText (sourceTextPositions items) pos := by
  induction items with
  | nil => simp [textBeforeCount, countEarlierText,
      sourceTextPositions]
  | cons item rest ih =>
      cases item with
      | text textPos =>
          by_cases earlier : textPos < pos
          · simp [textBeforeCount, countEarlierText,
              sourceTextPositions, earlierTextItem, earlier]
            simp only [textBeforeCount, countEarlierText] at ih
            omega
          · simp [textBeforeCount, countEarlierText,
              sourceTextPositions, earlierTextItem, earlier]
            simp only [textBeforeCount, countEarlierText] at ih
            omega
      | figure _ => simpa [textBeforeCount, countEarlierText,
          sourceTextPositions, earlierTextItem] using ih
      | blank _ => simpa [textBeforeCount, countEarlierText,
          sourceTextPositions, earlierTextItem] using ih
      | need _ => simpa [textBeforeCount, countEarlierText,
          sourceTextPositions, earlierTextItem] using ih

theorem I3_text_here_iff_source_rank
    (items : List SourceItem) (ordered : sourceOrdered items)
    (pos brk : Nat) (member : .text pos ∈ items) :
    textHereAtBreak items brk pos = true ↔
      textRank (sourceTextPositions items) pos < brk := by
  rw [textHereAtBreak, I3_source_text_before_count,
    I3_count_earlier_text_eq_rank (sourceTextPositions items)
      (I3_source_text_positions_ordered items ordered) pos
      ((I3_source_text_position_member items pos).mpr member)]
  simp

theorem I3_text_rank_points_to_position
    (positions : List Nat) (pos : Nat) (member : pos ∈ positions) :
    List.get? positions (textRank positions pos) = some pos := by
  induction positions with
  | nil => simp at member
  | cons first rest ih =>
      by_cases same : first = pos
      · subst pos
        simp [textRank]
      · have inRest := (List.mem_cons.mp member).resolve_left
          (Ne.symm same)
        simp only [textRank, if_neg same]
        rw [Nat.add_comm 1 (textRank rest pos), List.get?_cons_succ]
        exact ih inRest

theorem I3_text_rank_preserves_order
    (positions : List Nat) (ordered : strictTextPositions positions)
    (first later : Nat) (firstIn : first ∈ positions)
    (laterIn : later ∈ positions) (before : first < later) :
    textRank positions first < textRank positions later := by
  induction positions with
  | nil => simp at firstIn
  | cons head rest ih =>
      obtain ⟨headBefore, restOrdered⟩ := ordered
      rcases List.mem_cons.mp firstIn with firstHead | firstRest
      · subst first
        have distinct : head ≠ later := by omega
        simp [textRank, distinct]
        omega
      · rcases List.mem_cons.mp laterIn with laterHead | laterRest
        · subst later
          have greater := headBefore first firstRest
          omega
        · have firstDistinct : head ≠ first := by
            have greater := headBefore first firstRest
            omega
          have laterDistinct : head ≠ later := by
            have greater := headBefore later laterRest
            omega
          have tail := ih restOrdered firstRest laterRest
          simp [textRank, firstDistinct, laterDistinct]
          omega

theorem I3_text_role_at_source_rank
    {Role : Type} (items : List SourceItem) (roleForText : Nat → Role)
    (pos : Nat) (member : .text pos ∈ items) :
    List.get? ((sourceTextPositions items).map roleForText)
      (textRank (sourceTextPositions items) pos) =
      some (roleForText pos) := by
  rw [List.get?_map]
  rw [I3_text_rank_points_to_position (sourceTextPositions items) pos
    ((I3_source_text_position_member items pos).mpr member)]
  rfl

theorem I3_source_text_first_break
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → TextRole) (capacity : Nat)
    (twoFit : 2 ≤ capacity) :
    let positions := sourceTextPositions items
    let roles := positions.map roleForText
    let brk := textOnlyFirstBreak roles
    brk ≤ capacity ∧
      (roles ≠ [] → 1 ≤ brk) ∧
      textOnlyLineAfterHeadings roles brk ∧
      ∀ pos, .text pos ∈ items →
        (textHereAtBreak items brk pos = true ↔
          textRank positions pos < brk) ∧
        (textHereAtBreak items brk pos = true →
          roleForText pos = .heading → textRank positions pos = 0) ∧
        (textHereAtBreak items brk pos = true →
          roleForText pos = .line →
          textOnlyAfterHeadings roles brk (textRank positions pos)) := by
  dsimp
  obtain ⟨fits, nonempty, afterHeading⟩ :=
    I3_text_only_first_break_line_after capacity
      ((sourceTextPositions items).map roleForText) twoFit
  refine ⟨fits, nonempty, afterHeading, ?_⟩
  intro pos member
  have here := I3_text_here_iff_source_rank items ordered pos
    (textOnlyFirstBreak ((sourceTextPositions items).map roleForText))
    member
  have role := I3_text_role_at_source_rank items roleForText pos member
  refine ⟨here, ?_, ?_⟩
  · intro placed isHeading
    apply I3_text_only_first_break_headings_start
      ((sourceTextPositions items).map roleForText)
      (textRank (sourceTextPositions items) pos)
      (here.mp placed)
    simpa [isHeading] using role
  · intro placed isLine
    apply I3_text_only_first_break_lines_after_headings
      ((sourceTextPositions items).map roleForText)
      (textRank (sourceTextPositions items) pos)
      (here.mp placed)
    simpa [isLine] using role

inductive AlloyTextRole where
  | heading
  | line
  | space
  deriving DecidableEq

def alloyTextFirstBreak : List AlloyTextRole → Nat
  | [] => 0
  | .heading :: .line :: _ => 2
  | _ :: _ => 1

def alloyLineAfterHeadings (roles : List AlloyTextRole)
    (brk : Nat) : Prop :=
  (0 < brk ∧
    ∀ i, i < brk → List.get? roles i = some .heading) →
    List.get? roles brk ≠ some .line

theorem I3_alloy_text_first_break_line_after
    (capacity : Nat) (roles : List AlloyTextRole)
    (twoFit : 2 ≤ capacity) :
    let brk := alloyTextFirstBreak roles
    brk ≤ capacity ∧
      (roles ≠ [] → 1 ≤ brk) ∧
      alloyLineAfterHeadings roles brk := by
  cases roles with
  | nil => simp [alloyTextFirstBreak, alloyLineAfterHeadings]
  | cons first rest =>
      cases first with
      | heading =>
          cases rest with
          | nil =>
              simp [alloyTextFirstBreak, alloyLineAfterHeadings]
              omega
          | cons second tail =>
              cases second with
              | heading =>
                  simp [alloyTextFirstBreak, alloyLineAfterHeadings]
                  omega
              | line =>
                  simp [alloyTextFirstBreak, alloyLineAfterHeadings]
                  constructor
                  · exact twoFit
                  · intro onlyHeadings
                    have impossible := onlyHeadings 1 (by decide)
                    simp at impossible
              | space =>
                  simp [alloyTextFirstBreak, alloyLineAfterHeadings]
                  omega
      | line =>
          simp [alloyTextFirstBreak, alloyLineAfterHeadings]
          constructor
          · omega
          · intro onlyHeadings
            have impossible := onlyHeadings 0 (by decide)
            simp at impossible
      | space =>
          simp [alloyTextFirstBreak, alloyLineAfterHeadings]
          constructor
          · omega
          · intro onlyHeadings
            have impossible := onlyHeadings 0 (by decide)
            simp at impossible

theorem I3_alloy_text_first_break_lines_after_headings
    (roles : List AlloyTextRole) :
    ∀ i, i < alloyTextFirstBreak roles →
      List.get? roles i = some .line →
      ∀ earlier, earlier < i →
        List.get? roles earlier = some .heading := by
  intro i placed line earlier before
  cases roles with
  | nil =>
      simp [alloyTextFirstBreak] at placed
      omega
  | cons first rest =>
      cases first with
      | heading =>
          cases rest with
          | nil =>
              simp [alloyTextFirstBreak] at placed
              omega
          | cons second tail =>
              cases second with
              | heading =>
                  simp [alloyTextFirstBreak] at placed
                  omega
              | line =>
                  simp [alloyTextFirstBreak] at placed
                  have one : i = 1 := by
                    by_cases zero : i = 0
                    · subst i
                      simp at line
                    · omega
                  have earlierZero : earlier = 0 := by omega
                  subst earlier
                  simp
              | space =>
                  simp [alloyTextFirstBreak] at placed
                  have zero : i = 0 := by omega
                  subst i
                  simp at line
      | line =>
          simp [alloyTextFirstBreak] at placed
          omega
      | space =>
          simp [alloyTextFirstBreak] at placed
          have zero : i = 0 := by omega
          subst i
          simp at line

theorem I3_alloy_source_text_first_break
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → AlloyTextRole) (capacity : Nat)
    (twoFit : 2 ≤ capacity) :
    let positions := sourceTextPositions items
    let roles := positions.map roleForText
    let brk := alloyTextFirstBreak roles
    brk ≤ capacity ∧
      (roles ≠ [] → 1 ≤ brk) ∧
      alloyLineAfterHeadings roles brk ∧
      ∀ pos, .text pos ∈ items →
        (textHereAtBreak items brk pos = true ↔
          textRank positions pos < brk) ∧
        List.get? roles (textRank positions pos) =
          some (roleForText pos) := by
  dsimp
  obtain ⟨fits, nonempty, afterHeading⟩ :=
    I3_alloy_text_first_break_line_after capacity
      ((sourceTextPositions items).map roleForText) twoFit
  refine ⟨fits, nonempty, afterHeading, ?_⟩
  intro pos member
  constructor
  · exact I3_text_here_iff_source_rank items ordered pos
      (alloyTextFirstBreak ((sourceTextPositions items).map roleForText))
      member
  · rw [List.get?_map]
    rw [I3_text_rank_points_to_position (sourceTextPositions items) pos
      ((I3_source_text_position_member items pos).mpr member)]
    rfl

theorem I3_alloy_placed_line_prior_text_heading
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → AlloyTextRole)
    (linePos earlierPos : Nat)
    (lineIn : .text linePos ∈ items)
    (earlierIn : .text earlierPos ∈ items)
    (before : earlierPos < linePos)
    (lineRole : roleForText linePos = .line)
    (placed : textHereAtBreak items
      (alloyTextFirstBreak
        ((sourceTextPositions items).map roleForText)) linePos = true) :
    roleForText earlierPos = .heading := by
  have lineRank := (I3_text_here_iff_source_rank items ordered linePos
    (alloyTextFirstBreak
      ((sourceTextPositions items).map roleForText)) lineIn).mp placed
  have earlierRank := I3_text_rank_preserves_order
    (sourceTextPositions items)
    (I3_source_text_positions_ordered items ordered)
    earlierPos linePos
    ((I3_source_text_position_member items earlierPos).mpr earlierIn)
    ((I3_source_text_position_member items linePos).mpr lineIn)
    before
  have lineAt := I3_text_role_at_source_rank items roleForText linePos
    lineIn
  have earlierAt := I3_text_role_at_source_rank items roleForText
    earlierPos earlierIn
  have headingAt := I3_alloy_text_first_break_lines_after_headings
    ((sourceTextPositions items).map roleForText)
    (textRank (sourceTextPositions items) linePos)
    lineRank (by simpa [lineRole] using lineAt)
    (textRank (sourceTextPositions items) earlierPos) earlierRank
  rw [earlierAt] at headingAt
  exact Option.some.inj headingAt

def afterHeadingsOnlySource (used brk : Nat)
    (items : List SourceItem) (roleForText : Nat → AlloyTextRole)
    (keptFigure : Nat → Bool) (pos : Nat) : Prop :=
  used = 0 ∧
    (∀ textPos, .text textPos ∈ items → textPos < pos →
      textHereAtBreak items brk textPos = true →
      roleForText textPos = .heading) ∧
    (∀ figurePos, .figure figurePos ∈ items → figurePos < pos →
      keptFigure figurePos = false)

theorem I3_alloy_placed_line_after_sent_figures
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → AlloyTextRole)
    (keptFigure : Nat → Bool) (linePos : Nat)
    (lineIn : .text linePos ∈ items)
    (lineRole : roleForText linePos = .line)
    (earlierSent : ∀ figurePos, .figure figurePos ∈ items →
      figurePos < linePos → keptFigure figurePos = false)
    (placed : textHereAtBreak items
      (alloyTextFirstBreak
        ((sourceTextPositions items).map roleForText)) linePos = true) :
    afterHeadingsOnlySource 0
      (alloyTextFirstBreak
        ((sourceTextPositions items).map roleForText))
      items roleForText keptFigure linePos := by
  refine ⟨rfl, ?_, ?_⟩
  · intro textPos textIn before _
    exact I3_alloy_placed_line_prior_text_heading items ordered
      roleForText linePos textPos lineIn textIn before lineRole placed
  · exact earlierSent

theorem I3_alloy_placed_line_after_headings_source
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → AlloyTextRole)
    (keptFigure : Nat → Bool) (linePos : Nat)
    (lineIn : .text linePos ∈ items)
    (lineRole : roleForText linePos = .line)
    (figuresAfter : ∀ figurePos, .figure figurePos ∈ items →
      linePos < figurePos)
    (placed : textHereAtBreak items
      (alloyTextFirstBreak
        ((sourceTextPositions items).map roleForText)) linePos = true) :
    afterHeadingsOnlySource 0
      (alloyTextFirstBreak
        ((sourceTextPositions items).map roleForText))
      items roleForText keptFigure linePos := by
  apply I3_alloy_placed_line_after_sent_figures items ordered roleForText
    keptFigure linePos lineIn lineRole _ placed
  intro figurePos member before
  have after := figuresAfter figurePos member
  omega

/- A figure after the first two text items can be kept at break two
   exactly when its own rule permits it. The figure's source prefix
   count already includes both placed text items, so its room bound
   implies the complete column bound. -/
theorem I3_two_break_no_blank_one_figure
    (capacity figureSize : Nat) (items : List SourceItem)
    (figurePos : Nat) (twoFit : 2 ≤ capacity)
    (twoTextBefore : 2 ≤ textBeforeCount items figurePos) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad 1 capacity 0 kept
        (fun _ => textBeforeCount items figurePos ≤ 2)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize) (fun _ => false) ∧
      2 + (if kept 0 then figureSize else 0) ≤ capacity := by
  obtain ⟨kept, rule⟩ :=
    I3_figuresRuleWithLoad_exists 1 capacity 0
      (fun _ => decide (textBeforeCount items figurePos ≤ 2))
      (fun _ => textBeforeCount items figurePos)
      (fun _ => figureSize) (fun _ => false)
  simp only [decide_eq_true_eq] at rule
  refine ⟨kept, rule, ?_⟩
  cases present : kept 0 with
  | false => simpa [present] using twoFit
  | true =>
      have room := I3_kept_figure_has_room 1 capacity 0 kept
        (fun _ => textBeforeCount items figurePos ≤ 2)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize) (fun _ => false)
        rule 0 (by decide) present
      simp [figureHasRoom, priorFigureLines,
        show List.range 0 = [] from rfl] at room
      simp [present]
      omega

/- A figure between the initial heading and the following line has one text
   item before it. Keeping it satisfies the heading-only rule at break one.
   Sending it requires break two to include the following line instead. -/
theorem I3_heading_figure_line_break (capacity figureSize : Nat)
    (twoFit : 2 ≤ capacity) :
    ∃ brk : Nat, ∃ kept : Nat → Bool,
      ((brk = 1 ∧ kept 0 = true) ∨ (brk = 2 ∧ kept 0 = false)) ∧
      figuresRuleWithLoad 1 capacity 0 kept (fun _ => 1 ≤ brk)
        (fun _ => 1) (fun _ => figureSize) (fun _ => false) ∧
      brk + (if kept 0 then figureSize else 0) ≤ capacity := by
  obtain ⟨kept, rule⟩ := I3_figuresRuleWithLoad_exists 1 capacity 0
    (fun _ => true) (fun _ => 1) (fun _ => figureSize) (fun _ => false)
  cases present : kept 0 with
  | false =>
      exact ⟨2, kept, Or.inr ⟨rfl, present⟩, by simpa using rule,
        by simpa [present] using twoFit⟩
  | true =>
      have room := I3_kept_figure_has_room 1 capacity 0 kept _ _ _ _
        rule 0 (by decide) present
      refine ⟨1, kept, Or.inl ⟨rfl, present⟩, by simpa using rule, ?_⟩
      simpa [present, figureHasRoom, priorFigureLines,
        show List.range 0 = [] from rfl] using room

theorem I3_text_after_second_not_in_second_break
    (items : List SourceItem) (ordered : sourceOrdered items)
    (secondPos laterPos : Nat)
    (secondIn : .text secondPos ∈ items)
    (laterIn : .text laterPos ∈ items)
    (secondRank : textBeforeCount items secondPos = 1)
    (after : secondPos < laterPos) :
    textHereAtBreak items 2 laterPos = false := by
  have secondMember :=
    (I3_source_text_position_member items secondPos).mpr secondIn
  have laterMember :=
    (I3_source_text_position_member items laterPos).mpr laterIn
  have ranks := I3_text_rank_preserves_order
    (sourceTextPositions items)
    (I3_source_text_positions_ordered items ordered)
    secondPos laterPos secondMember laterMember after
  have secondCount := I3_count_earlier_text_eq_rank
    (sourceTextPositions items)
    (I3_source_text_positions_ordered items ordered)
    secondPos secondMember
  have actualSecond := I3_source_text_before_count items secondPos
  have notEarlier : ¬ textRank (sourceTextPositions items) laterPos < 2 := by
    omega
  have laterHere := I3_text_here_iff_source_rank items ordered laterPos 2
    laterIn
  cases here : textHereAtBreak items 2 laterPos with
  | false => rfl
  | true => exact False.elim (notEarlier (laterHere.mp here))

theorem I3_blank_after_second_placement_matches_used_two
    (items : List SourceItem) (ordered : sourceOrdered items)
    (secondPos blankPos : Nat)
    (waitingFigure keptFigure : Nat → Bool)
    (secondIn : .text secondPos ∈ items)
    (secondRank : textBeforeCount items secondPos = 1)
    (beforeBlank : secondPos < blankPos) :
    blankPlacedFromSourceFull 0 blankPos waitingFigure items
      (textHereAtBreak items 2) keptFigure =
    blankPlacedFromSourceFull 2 blankPos waitingFigure items
      (fun _ => false) keptFigure := by
  have secondHere : textHereAtBreak items 2 secondPos = true := by
    simp [textHereAtBreak, secondRank]
  have found : items.any (keptBeforeBlank blankPos
      (textHereAtBreak items 2) keptFigure) = true :=
    (List.any_eq_true).mpr ⟨.text secondPos, secondIn,
      by simp [keptBeforeBlank, beforeBlank, secondHere]⟩
  have top : blankAtTopSource 0 blankPos items
      (textHereAtBreak items 2) keptFigure = false := by
    simp [blankAtTopSource, found]
  have usedTop : blankAtTopSource 2 blankPos items
      (fun _ => false) keptFigure = false := by
    simp [blankAtTopSource]
  unfold blankPlacedFromSourceFull
  rw [top, usedTop]
  unfold blankPlacedFromSource
  cases next : nextOfSource blankPos waitingFigure items with
  | none => rfl
  | some candidate =>
      obtain ⟨item, member, selected, _⟩ :=
        I3_nextOfSource_some_has_member blankPos waitingFigure items
          candidate next
      cases item with
      | text pos =>
          by_cases after : blankPos < pos
          · have same : candidate = ⟨pos, false⟩ := by
              simpa [candidateAfterBlank, after] using selected.symm
            subst candidate
            have notHere := I3_text_after_second_not_in_second_break
              items ordered secondPos pos secondIn member secondRank
              (by omega)
            simp [sourceInColumn, notHere]
          · simp [candidateAfterBlank, after] at selected
      | figure pos =>
          by_cases after : blankPos < pos
          · have same : candidate = ⟨pos, true⟩ := by
              simpa [candidateAfterBlank, after] using selected.symm
            subst candidate
            simp [sourceInColumn]
          · simp [candidateAfterBlank, after] at selected
      | blank pos => simp [candidateAfterBlank] at selected
      | need pos => simp [candidateAfterBlank] at selected

theorem I3_two_break_one_figure_one_blank_after_text
    (capacity secondPos blankPos figurePos figureSize : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items)
    (twoFit : 2 ≤ capacity)
    (secondIn : .text secondPos ∈ items)
    (secondRank : textBeforeCount items secondPos = 1)
    (blankAfter : secondPos < blankPos)
    (figureAfter : 2 ≤ textBeforeCount items figurePos)
    (different : blankPos ≠ figurePos)
    (figureIn : .figure figurePos ∈ items)
    (onlyOne : ∀ pos, .figure pos ∈ items → pos = figurePos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      figuresRuleWithLoad 1 capacity 0 kept
        (fun _ => textBeforeCount items figurePos ≤ 2)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize)
        (fun f => !beforeBlankMask figurePos (figurePos + 1) blankPos f && !atTop) ∧
      atTop = blankAtTopSource 0 blankPos items
        (textHereAtBreak items 2)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      placed = blankPlacedFromSourceFull 0 blankPos (fun _ => false)
        items (textHereAtBreak items 2)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      2 + (if kept 0 then figureSize else 0) +
        (if placed then 1 else 0) ≤ capacity := by
  let count := textBeforeCount items figurePos
  obtain ⟨top, kept, placed, rule, topRule, placedRule, fits⟩ :=
    I3_blankFigureOrder_one_figure_arbitrary_source_exists
      capacity 2 blankPos figurePos figureSize
      (fun _ => decide (count ≤ 2)) (fun _ => count - 2)
      (fun _ _ => false) items twoFit different figureIn onlyOne
  have topFalse : top = false := by
    rw [topRule]
    simp [blankAtTopSource]
  have secondHere : textHereAtBreak items 2 secondPos = true := by
    simp [textHereAtBreak, secondRank]
  have actualTop : blankAtTopSource 0 blankPos items
      (textHereAtBreak items 2)
      (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) = false := by
    have found : items.any (keptBeforeBlank blankPos
        (textHereAtBreak items 2)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false)) = true :=
      (List.any_eq_true).mpr ⟨.text secondPos, secondIn,
        by simp [keptBeforeBlank, blankAfter, secondHere]⟩
    simp [blankAtTopSource, found]
  have actualPlaced : placed = blankPlacedFromSourceFull 0 blankPos
      (fun _ => false) items (textHereAtBreak items 2)
      (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) := by
    calc
      placed = blankPlacedFromSourceFull 2 blankPos (fun _ => false)
          items (fun _ => false)
          (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) :=
        placedRule
      _ = blankPlacedFromSourceFull 0 blankPos (fun _ => false)
          items (textHereAtBreak items 2)
          (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) :=
        (I3_blank_after_second_placement_matches_used_two items ordered
          secondPos blankPos (fun _ => false)
          (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false)
          secondIn secondRank blankAfter).symm
  have roomEq (f : Nat) :
      figureHasRoom capacity 2 (fun _ => count - 2)
        (fun _ => figureSize)
        (fun f => !beforeBlankMask figurePos (figurePos + 1) blankPos f && !top) f ↔
      figureHasRoom capacity 0 (fun _ => count)
        (fun _ => figureSize)
        (fun f => !beforeBlankMask figurePos (figurePos + 1) blankPos f && !top) f := by
    simp only [figureHasRoom]
    omega
  refine ⟨kept, top, placed, ?_, ?_, actualPlaced, fits⟩
  · intro f bound
    have r := rule f bound
    simpa [count, roomEq f] using r
  · rw [topFalse, actualTop]

theorem I3_two_break_two_figures_one_blank_after_text
    (capacity secondTextPos blankPos firstPos secondPos
      firstSize secondSize : Nat)
    (items : List SourceItem) (sourceOrder : sourceOrdered items)
    (twoFit : 2 ≤ capacity)
    (secondTextIn : .text secondTextPos ∈ items)
    (secondTextRank : textBeforeCount items secondTextPos = 1)
    (blankAfter : secondTextPos < blankPos)
    (firstTextBefore : 2 ≤ textBeforeCount items firstPos)
    (secondTextBefore : 2 ≤ textBeforeCount items secondPos)
    (figureOrder : firstPos < secondPos)
    (blankFirstDifferent : blankPos ≠ firstPos)
    (blankSecondDifferent : blankPos ≠ secondPos)
    (firstIn : .figure firstPos ∈ items)
    (secondIn : .figure secondPos ∈ items)
    (onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = firstPos ∨ pos = secondPos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      figuresRuleWithLoad 2 capacity 0 kept
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos) ≤ 2)
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos))
        (fun f => if f = 0 then firstSize else secondSize)
        (fun f => !beforeBlankMask firstPos secondPos blankPos f && !atTop) ∧
      atTop = blankAtTopSource 0 blankPos items
        (textHereAtBreak items 2)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      placed = blankPlacedFromSourceFull 0 blankPos
        (waitingAtTwoPositions firstPos secondPos kept) items
        (textHereAtBreak items 2)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      2 + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) +
        (if placed then 1 else 0) ≤ capacity := by
  let count : Nat → Nat := fun f => textBeforeCount items
    (if f = 0 then firstPos else secondPos)
  let sizes : Nat → Nat := fun f => if f = 0 then firstSize else secondSize
  obtain ⟨top, kept, placed, rule, topRule, placedRule, fits⟩ :=
    I3_blankFigureOrder_arbitrary_source_exists capacity 2 blankPos
      firstPos secondPos firstSize secondSize
      (fun f => decide (count f ≤ 2)) (fun f => count f - 2)
      (waitingAtTwoPositions firstPos secondPos) items twoFit
      figureOrder blankFirstDifferent blankSecondDifferent
      firstIn secondIn onlyTwo
  have topFalse : top = false := by
    rw [topRule]
    simp [blankAtTopSource]
  have secondHere : textHereAtBreak items 2 secondTextPos = true := by
    simp [textHereAtBreak, secondTextRank]
  have actualTop : blankAtTopSource 0 blankPos items
      (textHereAtBreak items 2)
      (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) = false := by
    have found : items.any (keptBeforeBlank blankPos
        (textHereAtBreak items 2)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1))) = true :=
      (List.any_eq_true).mpr ⟨.text secondTextPos, secondTextIn,
        by simp [keptBeforeBlank, blankAfter, secondHere]⟩
    simp [blankAtTopSource, found]
  have actualPlaced : placed = blankPlacedFromSourceFull 0 blankPos
      (waitingAtTwoPositions firstPos secondPos kept) items
      (textHereAtBreak items 2)
      (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) := by
    calc
      placed = blankPlacedFromSourceFull 2 blankPos
          (waitingAtTwoPositions firstPos secondPos kept) items
          (fun _ => false)
          (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) :=
        placedRule
      _ = blankPlacedFromSourceFull 0 blankPos
          (waitingAtTwoPositions firstPos secondPos kept) items
          (textHereAtBreak items 2)
          (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) :=
        (I3_blank_after_second_placement_matches_used_two items sourceOrder
          secondTextPos blankPos
          (waitingAtTwoPositions firstPos secondPos kept)
          (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1))
          secondTextIn secondTextRank blankAfter).symm
  have roomEq (f : Nat) (bound : f < 2) :
      figureHasRoom capacity 2 (fun f => count f - 2) sizes
        (fun f => !beforeBlankMask firstPos secondPos blankPos f && !top) f ↔
      figureHasRoom capacity 0 count sizes
        (fun f => !beforeBlankMask firstPos secondPos blankPos f && !top) f := by
    have enough : 2 ≤ count f := by
      by_cases zero : f = 0
      · simpa [count, zero] using firstTextBefore
      · have one : f = 1 := by omega
        simpa [count, one] using secondTextBefore
    simp only [figureHasRoom]
    omega
  refine ⟨kept, top, placed, ?_, ?_, actualPlaced, fits⟩
  · intro f bound
    have r := rule f bound
    simpa [count, sizes, roomEq f bound] using r
  · rw [topFalse, actualTop]

theorem I3_break_one_keeps_first_text
    (items : List SourceItem) (pos : Nat)
    (first : ∀ textPos, .text textPos ∈ items → pos ≤ textPos) :
    textHereAtBreak items 1 pos = true := by
  have noEarlier : ∀ item ∈ items, earlierTextItem pos item = false := by
    intro item member
    cases item with
    | text textPos =>
        have later := first textPos member
        simp [earlierTextItem, Nat.not_lt.mpr later]
    | figure _ => rfl
    | blank _ => rfl
    | need _ => rfl
  have emptyFilter : items.filter (earlierTextItem pos) = [] :=
    List.filter_eq_nil.mpr (by
      intro item member hit
      simp [noEarlier item member] at hit)
  simp [textHereAtBreak, textBeforeCount, emptyFilter]

theorem I3_break_one_text_iff_first
    (items : List SourceItem) (pos : Nat) :
    textHereAtBreak items 1 pos = true ↔
      ∀ textPos, .text textPos ∈ items → pos ≤ textPos := by
  constructor
  · intro here textPos member
    have countZero : textBeforeCount items pos = 0 := by
      simp [textHereAtBreak] at here
      omega
    have emptyFilter : items.filter (earlierTextItem pos) = [] := by
      exact List.length_eq_zero.mp (by simpa [textBeforeCount] using countZero)
    by_cases later : pos ≤ textPos
    · exact later
    · have earlier : textPos < pos := by omega
      have inFilter : .text textPos ∈ items.filter (earlierTextItem pos) :=
        List.mem_filter.mpr ⟨member, by simp [earlierTextItem, earlier]⟩
      simp [emptyFilter] at inFilter
  · intro first
    exact I3_break_one_keeps_first_text items pos first

theorem I3_textReadyZero_iff_no_earlier_text
    (items : List SourceItem) (pos : Nat) :
    textReadyZero items pos = true ↔
      ∀ textPos, .text textPos ∈ items → pos ≤ textPos := by
  constructor
  · intro ready textPos member
    by_cases earlier : textPos < pos
    · have found : items.any (earlierTextItem pos) = true :=
        (List.any_eq_true).mpr ⟨.text textPos, member,
          by simp [earlierTextItem, earlier]⟩
      simp [textReadyZero, found] at ready
    · omega
  · intro noEarlier
    cases found : items.any (earlierTextItem pos) with
    | false => simp [textReadyZero, found]
    | true =>
        obtain ⟨item, member, hit⟩ := (List.any_eq_true).mp found
        cases item with
        | text textPos =>
            have earlier : textPos < pos := by
              simpa [earlierTextItem] using hit
            have later := noEarlier textPos member
            omega
        | figure _ => simp [earlierTextItem] at hit
        | blank _ => simp [earlierTextItem] at hit
        | need _ => simp [earlierTextItem] at hit

theorem I3_textReadyZero_iff_hereAtBreakOne
    (items : List SourceItem) (pos : Nat) :
    textReadyZero items pos = true ↔
      textHereAtBreak items 1 pos = true := by
  exact (I3_textReadyZero_iff_no_earlier_text items pos).trans
    (I3_break_one_text_iff_first items pos).symm

theorem I3_blank_after_first_text_not_top
    (items : List SourceItem) (firstTextPos blankPos : Nat)
    (keptFigure : Nat → Bool)
    (firstText : .text firstTextPos ∈ items)
    (beforeBlank : firstTextPos < blankPos)
    (firstHere : textHereAtBreak items 1 firstTextPos = true) :
    blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
      keptFigure = false := by
  have found : items.any (keptBeforeBlank blankPos
      (textHereAtBreak items 1) keptFigure) = true :=
    (List.any_eq_true).mpr ⟨.text firstTextPos, firstText,
      by simp [keptBeforeBlank, beforeBlank, firstHere]⟩
  simp [blankAtTopSource, found]

theorem I3_text_after_first_text_not_in_first_break
    (items : List SourceItem) (firstTextPos laterPos : Nat)
    (firstText : .text firstTextPos ∈ items)
    (beforeLater : firstTextPos < laterPos) :
    textHereAtBreak items 1 laterPos = false := by
  cases here : textHereAtBreak items 1 laterPos with
  | false => rfl
  | true =>
      have earliest := (I3_break_one_text_iff_first items laterPos).mp here
        firstTextPos firstText
      omega

theorem I3_blank_after_first_text_placement_matches_used_one
    (items : List SourceItem) (firstTextPos blankPos : Nat)
    (waitingFigure keptFigure : Nat → Bool)
    (firstText : .text firstTextPos ∈ items)
    (firstBefore : firstTextPos < blankPos)
    (firstHere : textHereAtBreak items 1 firstTextPos = true) :
    blankPlacedFromSourceFull 0 blankPos waitingFigure items
      (textHereAtBreak items 1) keptFigure =
    blankPlacedFromSourceFull 1 blankPos waitingFigure items
      (fun _ => false) keptFigure := by
  have top := I3_blank_after_first_text_not_top items firstTextPos
    blankPos keptFigure firstText firstBefore firstHere
  have usedTop : blankAtTopSource 1 blankPos items (fun _ => false)
      keptFigure = false := by simp [blankAtTopSource]
  unfold blankPlacedFromSourceFull
  rw [top, usedTop]
  unfold blankPlacedFromSource
  cases next : nextOfSource blankPos waitingFigure items with
  | none => rfl
  | some candidate =>
      obtain ⟨item, member, selected, _⟩ :=
        I3_nextOfSource_some_has_member blankPos waitingFigure items
          candidate next
      cases item with
      | text pos =>
          by_cases after : blankPos < pos
          · have same : candidate = ⟨pos, false⟩ := by
              simpa [candidateAfterBlank, after] using selected.symm
            subst candidate
            have notHere := I3_text_after_first_text_not_in_first_break
              items firstTextPos pos firstText (by omega)
            simp [sourceInColumn, notHere]
          · simp [candidateAfterBlank, after] at selected
      | figure pos =>
          by_cases after : blankPos < pos
          · have same : candidate = ⟨pos, true⟩ := by
              simpa [candidateAfterBlank, after] using selected.symm
            subst candidate
            simp [sourceInColumn]
          · simp [candidateAfterBlank, after] at selected
      | blank pos => simp [candidateAfterBlank] at selected
      | need pos => simp [candidateAfterBlank] at selected

theorem I3_blank_before_first_text_is_top
    (items : List SourceItem) (firstTextPos blankPos : Nat)
    (keptFigure : Nat → Bool)
    (beforeText : blankPos < firstTextPos)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (noFigureBefore : ∀ figurePos, figurePos < blankPos →
      keptFigure figurePos = false) :
    blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
      keptFigure = true := by
  apply (I3_blankAtTopSource_iff_empty_before 0 blankPos items
    (textHereAtBreak items 1) keptFigure).mpr
  refine ⟨rfl, ?_⟩
  intro item member
  cases item with
  | text pos =>
      have later := first pos member
      have notBefore : ¬ pos < blankPos := by omega
      simp [keptBeforeBlank, notBefore]
  | figure pos =>
      by_cases before : pos < blankPos
      · simp [keptBeforeBlank, before, noFigureBefore pos before]
      · simp [keptBeforeBlank, before]
  | blank _ => rfl
  | need _ => rfl

theorem I3_blank_before_first_text_not_placed
    (items : List SourceItem) (firstTextPos blankPos : Nat)
    (waitingFigure keptFigure : Nat → Bool)
    (beforeText : blankPos < firstTextPos)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (noFigureBefore : ∀ figurePos, figurePos < blankPos →
      keptFigure figurePos = false) :
    blankPlacedFromSourceFull 0 blankPos waitingFigure items
      (textHereAtBreak items 1) keptFigure = false := by
  have top := I3_blank_before_first_text_is_top items firstTextPos blankPos
    keptFigure beforeText first noFigureBefore
  unfold blankPlacedFromSourceFull blankPlacedFromSource
  rw [top]
  cases nextOfSource blankPos waitingFigure items <;>
    simp

theorem I3_blank_before_first_figure_is_top
    (items : List SourceItem) (blankPos : Nat)
    (keptFigure : Nat → Bool)
    (noFigureBefore : ∀ figurePos, figurePos < blankPos →
      keptFigure figurePos = false) :
    blankAtTopSource 0 blankPos items (fun _ => false)
      keptFigure = true := by
  apply (I3_blankAtTopSource_iff_empty_before 0 blankPos items
    (fun _ => false) keptFigure).mpr
  refine ⟨rfl, ?_⟩
  intro item member
  cases item with
  | text _ => simp [keptBeforeBlank]
  | figure pos =>
      by_cases before : pos < blankPos
      · simp [keptBeforeBlank, before, noFigureBefore pos before]
      · simp [keptBeforeBlank, before]
  | blank _ => rfl
  | need _ => rfl

theorem I3_one_break_figure_load_matches_alloy
    (items : List SourceItem) (textPos figurePos : Nat)
    (member : .text textPos ∈ items) (earlier : textPos < figurePos)
    (prior blank size : Nat) :
    1 + (textBeforeCount items figurePos - 1) + prior + blank + size =
      textBeforeCount items figurePos + prior + blank + size := by
  have hit : .text textPos ∈ items.filter (earlierTextItem figurePos) :=
    List.mem_filter.mpr ⟨member, by simp [earlierTextItem, earlier]⟩
  have positive : 0 < textBeforeCount items figurePos := by
    cases h : items.filter (earlierTextItem figurePos) with
    | nil => simp [h] at hit
    | cons x xs => simp [textBeforeCount, h]
  omega

theorem I3_blankFigureOrder_two_figures_zero_break
    (capacity used blankPos firstPos secondPos firstSize secondSize : Nat)
    (items : List SourceItem) (usedFits : used ≤ capacity)
    (ordered : firstPos < secondPos)
    (blankFirstDifferent : blankPos ≠ firstPos)
    (blankSecondDifferent : blankPos ≠ secondPos)
    (firstIn : .figure firstPos ∈ items)
    (secondIn : .figure secondPos ∈ items)
    (onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = firstPos ∨ pos = secondPos) :
    ∃ atTop : Bool, ∃ kept : Nat → Bool, ∃ placed : Bool,
      figuresRuleWithLoad 2 capacity used kept
        (fun f => textReadyZero items (if f = 0 then firstPos else secondPos) = true)
        (fun f => textBeforeCount items (if f = 0 then firstPos else secondPos))
        (fun f => if f = 0 then firstSize else secondSize)
        (fun f => !beforeBlankMask firstPos secondPos blankPos f && !atTop) ∧
      atTop = blankAtTopSource used blankPos items (fun _ => false)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      placed = blankPlacedFromSourceFull used blankPos
        (waitingAtTwoPositions firstPos secondPos kept) items
        (fun _ => false)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      used + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) +
        (if placed then 1 else 0) ≤ capacity := by
  exact I3_blankFigureOrder_arbitrary_source_exists capacity used blankPos
    firstPos secondPos firstSize secondSize
    (fun f => textReadyZero items (if f = 0 then firstPos else secondPos))
    (fun f => textBeforeCount items (if f = 0 then firstPos else secondPos))
    (waitingAtTwoPositions firstPos secondPos) items usedFits ordered
    blankFirstDifferent blankSecondDifferent firstIn secondIn onlyTwo

theorem I3_blankFigureOrder_no_blank_two_figures_zero_break
    (capacity used firstPos secondPos firstSize secondSize : Nat)
    (items : List SourceItem) (usedFits : used ≤ capacity) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad 2 capacity used kept
        (fun f => textReadyZero items (if f = 0 then firstPos else secondPos) = true)
        (fun f => textBeforeCount items (if f = 0 then firstPos else secondPos))
        (fun f => if f = 0 then firstSize else secondSize)
        (fun _ => false) ∧
      used + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) ≤ capacity := by
  let ready : Nat → Bool := fun f =>
    textReadyZero items (if f = 0 then firstPos else secondPos)
  let textBefore : Nat → Nat := fun f =>
    textBeforeCount items (if f = 0 then firstPos else secondPos)
  let size : Nat → Nat := fun f => if f = 0 then firstSize else secondSize
  obtain ⟨kept, rule⟩ := I3_figuresRuleWithLoad_exists 2 capacity used
    ready textBefore size (fun _ => false)
  refine ⟨kept, rule, ?_⟩
  have firstFits : kept 0 = true → used + firstSize ≤ capacity := by
    intro present
    have room := I3_kept_figure_has_room 2 capacity used kept
      (fun f => ready f = true) textBefore size (fun _ => false)
      rule 0 (by decide) present
    simp [figureHasRoom, priorFigureLines, size] at room
    omega
  have secondFits : kept 1 = true →
      used + firstSize + secondSize ≤ capacity := by
    intro present
    have room := I3_kept_figure_has_room 2 capacity used kept
      (fun f => ready f = true) textBefore size (fun _ => false)
      rule 1 (by decide) present
    simp [figureHasRoom, priorFigureLines, size,
      show List.range 1 = [0] from rfl] at room
    omega
  have figureOrder : kept 1 = true → kept 0 = true := by
    intro present
    exact ((rule 1 (by decide)).mp present).2.1 0 (by decide)
  have fits := I3_two_figure_fits_from_blank_cause capacity used firstSize
    secondSize (kept 0) (kept 1) false false false usedFits
    (by simpa using firstFits) (by simpa using secondFits)
    figureOrder (by simp) (by simp)
  simpa using fits

theorem I3_no_blank_two_figures_arbitrary_text
    (capacity used firstSize secondSize : Nat)
    (ready : Nat → Bool) (textBefore : Nat → Nat)
    (usedFits : used ≤ capacity) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad 2 capacity used kept
        (fun f => ready f = true) textBefore
        (fun f => if f = 0 then firstSize else secondSize)
        (fun _ => false) ∧
      used + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) ≤ capacity := by
  let size : Nat → Nat := fun f => if f = 0 then firstSize else secondSize
  obtain ⟨kept, rule⟩ := I3_figuresRuleWithLoad_exists 2 capacity used
    ready textBefore size (fun _ => false)
  refine ⟨kept, rule, ?_⟩
  have firstFits : kept 0 = true → used + firstSize ≤ capacity := by
    intro present
    have room := I3_kept_figure_has_room 2 capacity used kept
      (fun f => ready f = true) textBefore size (fun _ => false)
      rule 0 (by decide) present
    simp [figureHasRoom, priorFigureLines, size] at room
    omega
  have secondFits : kept 1 = true →
      used + firstSize + secondSize ≤ capacity := by
    intro present
    have room := I3_kept_figure_has_room 2 capacity used kept
      (fun f => ready f = true) textBefore size (fun _ => false)
      rule 1 (by decide) present
    simp [figureHasRoom, priorFigureLines, size,
      show List.range 1 = [0] from rfl] at room
    omega
  have figureOrder : kept 1 = true → kept 0 = true := by
    intro present
    exact ((rule 1 (by decide)).mp present).2.1 0 (by decide)
  have fits := I3_two_figure_fits_from_blank_cause capacity used firstSize
    secondSize (kept 0) (kept 1) false false false usedFits
    (by simpa using firstFits) (by simpa using secondFits)
    figureOrder (by simp) (by simp)
  simpa using fits

theorem I3_one_break_no_blank_two_figures
    (capacity firstTextPos firstPos secondPos firstSize secondSize : Nat)
    (items : List SourceItem)
    (capacityPositive : 1 ≤ capacity)
    (firstText : .text firstTextPos ∈ items)
    (firstBefore : firstTextPos < firstPos)
    (secondBefore : firstTextPos < secondPos) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad 2 capacity 0 kept
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos) ≤ 1)
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos))
        (fun f => if f = 0 then firstSize else secondSize)
        (fun _ => false) ∧
      1 + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) ≤ capacity := by
  let pos : Nat → Nat := fun f => if f = 0 then firstPos else secondPos
  let count : Nat → Nat := fun f => textBeforeCount items (pos f)
  let size : Nat → Nat := fun f => if f = 0 then firstSize else secondSize
  let ready : Nat → Bool := fun f => decide (count f ≤ 1)
  obtain ⟨kept, shiftedRule, fits⟩ :=
    I3_no_blank_two_figures_arbitrary_text capacity 1 firstSize secondSize
      ready (fun f => count f - 1) capacityPositive
  refine ⟨kept, ?_, fits⟩
  intro f bound
  have priorText : 0 < count f := by
    have earlier : firstTextPos < pos f := by
      by_cases first : f = 0
      · simpa [pos, first] using firstBefore
      · simpa [pos, first] using secondBefore
    have hit : .text firstTextPos ∈ items.filter (earlierTextItem (pos f)) :=
      List.mem_filter.mpr ⟨firstText, by simp [earlierTextItem, earlier]⟩
    cases h : items.filter (earlierTextItem (pos f)) with
    | nil => simp [h] at hit
    | cons x xs => simp [count, textBeforeCount, h]
  have roomEq :
      figureHasRoom capacity 1 (fun g => count g - 1) size (fun _ => false) f ↔
      figureHasRoom capacity 0 count size (fun _ => false) f := by
    simp only [figureHasRoom]
    omega
  have figureRule := shiftedRule f bound
  simpa [figuresRuleWithLoad, figuresRule, ready, count, pos, size,
    roomEq] using figureRule

theorem I3_one_break_no_blank_one_figure
    (capacity firstTextPos figurePos figureSize : Nat)
    (items : List SourceItem)
    (capacityPositive : 1 ≤ capacity)
    (firstText : .text firstTextPos ∈ items)
    (beforeFigure : firstTextPos < figurePos) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad 1 capacity 0 kept
        (fun _ => textBeforeCount items figurePos ≤ 1)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize) (fun _ => false) ∧
      1 + (if kept 0 then figureSize else 0) ≤ capacity := by
  let count := textBeforeCount items figurePos
  have hit : .text firstTextPos ∈ items.filter (earlierTextItem figurePos) :=
    List.mem_filter.mpr ⟨firstText, by simp [earlierTextItem, beforeFigure]⟩
  have positive : 0 < count := by
    cases h : items.filter (earlierTextItem figurePos) with
    | nil => simp [h] at hit
    | cons x xs => simp [count, textBeforeCount, h]
  obtain ⟨kept, rule⟩ := I3_figuresRuleWithLoad_exists 1 capacity 1
    (fun _ => decide (count ≤ 1)) (fun _ => count - 1)
    (fun _ => figureSize) (fun _ => false)
  refine ⟨kept, ?_, ?_⟩
  · intro f bound
    have roomEq :
        figureHasRoom capacity 1 (fun _ => count - 1)
          (fun _ => figureSize) (fun _ => false) f ↔
        figureHasRoom capacity 0 (fun _ => count)
          (fun _ => figureSize) (fun _ => false) f := by
      simp only [figureHasRoom]
      omega
    have figureRule := rule f bound
    simpa [figuresRuleWithLoad, figuresRule, count, roomEq] using figureRule
  · cases present : kept 0 with
    | false => simpa [present] using capacityPositive
    | true =>
        have room := I3_kept_figure_has_room 1 capacity 1 kept
          (fun _ => decide (count ≤ 1) = true) (fun _ => count - 1)
          (fun _ => figureSize) (fun _ => false)
          rule 0 (by decide) present
        simp [figureHasRoom, priorFigureLines,
          show List.range 0 = [] from rfl] at room
        simp [present]
        omega

theorem I3_one_break_no_blank_no_figures
    (capacity : Nat) (capacityPositive : 1 ≤ capacity) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad 0 capacity 0 kept
        (fun _ => True) (fun _ => 0) (fun _ => 0) (fun _ => false) ∧
      1 ≤ capacity := by
  refine ⟨fun _ => false, ?_, capacityPositive⟩
  intro f bound
  exact False.elim (Nat.not_lt_zero f bound)

theorem I3_one_break_blank_before_text_two_figures
    (capacity blankPos firstTextPos firstPos secondPos firstSize secondSize : Nat)
    (items : List SourceItem)
    (capacityPositive : 1 ≤ capacity)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (blankBefore : blankPos < firstTextPos)
    (firstBefore : firstTextPos < firstPos)
    (secondBefore : firstTextPos < secondPos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      figuresRuleWithLoad 2 capacity 0 kept
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos) ≤ 1)
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos))
        (fun f => if f = 0 then firstSize else secondSize)
        (fun f => !beforeBlankMask firstPos secondPos blankPos f && !atTop) ∧
      atTop = blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      placed = blankPlacedFromSourceFull 0 blankPos
        (waitingAtTwoPositions firstPos secondPos kept) items
        (textHereAtBreak items 1)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      1 + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) +
          (if placed then 1 else 0) ≤ capacity := by
  obtain ⟨kept, figureRule, fits⟩ := I3_one_break_no_blank_two_figures
    capacity firstTextPos firstPos secondPos firstSize secondSize items
    capacityPositive firstText firstBefore secondBefore
  let keptAt := keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)
  have noFigureBefore : ∀ pos, pos < blankPos → keptAt pos = false := by
    intro pos before
    have notFirst : pos ≠ firstPos := by omega
    have notSecond : pos ≠ secondPos := by omega
    simp [keptAt, keptAtTwoPositions, notFirst, notSecond]
  have top : blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
      keptAt = true :=
    I3_blank_before_first_text_is_top items firstTextPos blankPos keptAt
      blankBefore first noFigureBefore
  have notPlaced : blankPlacedFromSourceFull 0 blankPos
      (waitingAtTwoPositions firstPos secondPos kept) items
      (textHereAtBreak items 1) keptAt = false :=
    I3_blank_before_first_text_not_placed items firstTextPos blankPos
      (waitingAtTwoPositions firstPos secondPos kept) keptAt
      blankBefore first noFigureBefore
  refine ⟨kept, true, false, ?_, top.symm, notPlaced.symm, ?_⟩
  · simpa using figureRule
  · simpa using fits

theorem I3_one_break_blank_after_text_two_figures
    (capacity firstTextPos blankPos firstPos secondPos firstSize secondSize : Nat)
    (items : List SourceItem)
    (capacityPositive : 1 ≤ capacity)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (textBeforeBlank : firstTextPos < blankPos)
    (textBeforeFirst : firstTextPos < firstPos)
    (textBeforeSecond : firstTextPos < secondPos)
    (ordered : firstPos < secondPos)
    (blankFirstDifferent : blankPos ≠ firstPos)
    (blankSecondDifferent : blankPos ≠ secondPos)
    (firstIn : .figure firstPos ∈ items)
    (secondIn : .figure secondPos ∈ items)
    (onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = firstPos ∨ pos = secondPos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      figuresRuleWithLoad 2 capacity 0 kept
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos) ≤ 1)
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos))
        (fun f => if f = 0 then firstSize else secondSize)
        (fun f => !beforeBlankMask firstPos secondPos blankPos f && !atTop) ∧
      atTop = blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      placed = blankPlacedFromSourceFull 0 blankPos
        (waitingAtTwoPositions firstPos secondPos kept) items
        (textHereAtBreak items 1)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      1 + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) +
          (if placed then 1 else 0) ≤ capacity := by
  let pos : Nat → Nat := fun f => if f = 0 then firstPos else secondPos
  let count : Nat → Nat := fun f => textBeforeCount items (pos f)
  let size : Nat → Nat := fun f => if f = 0 then firstSize else secondSize
  let ready : Nat → Bool := fun f => decide (count f ≤ 1)
  obtain ⟨top, kept, placed, shiftedRule, topRule, placedRule, fits⟩ :=
    I3_blankFigureOrder_arbitrary_source_exists capacity 1 blankPos
      firstPos secondPos firstSize secondSize ready (fun f => count f - 1)
      (waitingAtTwoPositions firstPos secondPos) items capacityPositive ordered
      blankFirstDifferent blankSecondDifferent firstIn secondIn onlyTwo
  let keptAt := keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)
  have firstHere := I3_break_one_keeps_first_text items firstTextPos first
  have actualTop : blankAtTopSource 0 blankPos items
      (textHereAtBreak items 1) keptAt = false :=
    I3_blank_after_first_text_not_top items firstTextPos blankPos keptAt
      firstText textBeforeBlank firstHere
  have usedTop : top = false := by
    rw [topRule]
    simp [blankAtTopSource]
  have actualPlaced : placed = blankPlacedFromSourceFull 0 blankPos
      (waitingAtTwoPositions firstPos secondPos kept) items
      (textHereAtBreak items 1) keptAt := by
    calc
      placed = blankPlacedFromSourceFull 1 blankPos
          (waitingAtTwoPositions firstPos secondPos kept) items
          (fun _ => false) keptAt := placedRule
      _ = blankPlacedFromSourceFull 0 blankPos
          (waitingAtTwoPositions firstPos secondPos kept) items
          (textHereAtBreak items 1) keptAt :=
        (I3_blank_after_first_text_placement_matches_used_one items
          firstTextPos blankPos (waitingAtTwoPositions firstPos secondPos kept)
          keptAt firstText textBeforeBlank firstHere).symm
  refine ⟨kept, top, placed, ?_, ?_, actualPlaced, fits⟩
  · intro f bound
    have positive : 0 < count f := by
      have before : firstTextPos < pos f := by
        by_cases firstFigure : f = 0
        · simpa [pos, firstFigure] using textBeforeFirst
        · simpa [pos, firstFigure] using textBeforeSecond
      have hit : .text firstTextPos ∈ items.filter (earlierTextItem (pos f)) :=
        List.mem_filter.mpr ⟨firstText, by simp [earlierTextItem, before]⟩
      cases h : items.filter (earlierTextItem (pos f)) with
      | nil => simp [h] at hit
      | cons x xs => simp [count, textBeforeCount, h]
    have roomEq :
        figureHasRoom capacity 1 (fun g => count g - 1) size
          (fun g => !beforeBlankMask firstPos secondPos blankPos g && !top) f ↔
        figureHasRoom capacity 0 count size
          (fun g => !beforeBlankMask firstPos secondPos blankPos g && !top) f := by
      simp only [figureHasRoom]
      omega
    have figureRule := shiftedRule f bound
    simpa [figuresRuleWithLoad, figuresRule, ready, count, pos, size,
      roomEq] using figureRule
  · rw [usedTop, actualTop]

theorem I3_one_break_blank_before_text_one_figure
    (capacity blankPos firstTextPos figurePos figureSize : Nat)
    (items : List SourceItem)
    (capacityPositive : 1 ≤ capacity)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (blankBefore : blankPos < firstTextPos)
    (textBeforeFigure : firstTextPos < figurePos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      figuresRuleWithLoad 1 capacity 0 kept
        (fun _ => textBeforeCount items figurePos ≤ 1)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize)
        (fun f => !beforeBlankMask figurePos (figurePos + 1) blankPos f && !atTop) ∧
      atTop = blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      placed = blankPlacedFromSourceFull 0 blankPos (fun _ => false) items
        (textHereAtBreak items 1)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      1 + (if kept 0 then figureSize else 0) +
        (if placed then 1 else 0) ≤ capacity := by
  obtain ⟨kept, figureRule, fits⟩ := I3_one_break_no_blank_one_figure
    capacity firstTextPos figurePos figureSize items capacityPositive
      firstText textBeforeFigure
  let keptAt := keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false
  have noFigureBefore : ∀ pos, pos < blankPos → keptAt pos = false := by
    intro pos before
    have notFirst : pos ≠ figurePos := by omega
    have notSecond : pos ≠ figurePos + 1 := by omega
    simp [keptAt, keptAtTwoPositions, notFirst, notSecond]
  have top : blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
      keptAt = true :=
    I3_blank_before_first_text_is_top items firstTextPos blankPos keptAt
      blankBefore first noFigureBefore
  have notPlaced : blankPlacedFromSourceFull 0 blankPos (fun _ => false)
      items (textHereAtBreak items 1) keptAt = false :=
    I3_blank_before_first_text_not_placed items firstTextPos blankPos
      (fun _ => false) keptAt blankBefore first noFigureBefore
  refine ⟨kept, true, false, ?_, top.symm, notPlaced.symm, ?_⟩
  · simpa using figureRule
  · simpa using fits

theorem I3_one_break_blank_after_text_one_figure
    (capacity firstTextPos blankPos figurePos figureSize : Nat)
    (items : List SourceItem)
    (capacityPositive : 1 ≤ capacity)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (textBeforeBlank : firstTextPos < blankPos)
    (textBeforeFigure : firstTextPos < figurePos)
    (blankDifferent : blankPos ≠ figurePos)
    (figureIn : .figure figurePos ∈ items)
    (onlyOne : ∀ pos, .figure pos ∈ items → pos = figurePos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      figuresRuleWithLoad 1 capacity 0 kept
        (fun _ => textBeforeCount items figurePos ≤ 1)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize)
        (fun f => !beforeBlankMask figurePos (figurePos + 1) blankPos f && !atTop) ∧
      atTop = blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      placed = blankPlacedFromSourceFull 0 blankPos (fun _ => false) items
        (textHereAtBreak items 1)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      1 + (if kept 0 then figureSize else 0) +
        (if placed then 1 else 0) ≤ capacity := by
  let count := textBeforeCount items figurePos
  let ready : Nat → Bool := fun _ => decide (count ≤ 1)
  obtain ⟨top, kept, placed, shiftedRule, topRule, placedRule, fits⟩ :=
    I3_blankFigureOrder_one_figure_arbitrary_source_exists capacity 1
      blankPos figurePos figureSize ready (fun _ => count - 1)
      (fun _ _ => false) items capacityPositive blankDifferent figureIn onlyOne
  let keptAt := keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false
  have firstHere := I3_break_one_keeps_first_text items firstTextPos first
  have actualTop : blankAtTopSource 0 blankPos items
      (textHereAtBreak items 1) keptAt = false :=
    I3_blank_after_first_text_not_top items firstTextPos blankPos keptAt
      firstText textBeforeBlank firstHere
  have usedTop : top = false := by
    rw [topRule]
    simp [blankAtTopSource]
  have actualPlaced : placed = blankPlacedFromSourceFull 0 blankPos
      (fun _ => false) items (textHereAtBreak items 1) keptAt := by
    calc
      placed = blankPlacedFromSourceFull 1 blankPos (fun _ => false)
          items (fun _ => false) keptAt := placedRule
      _ = blankPlacedFromSourceFull 0 blankPos (fun _ => false)
          items (textHereAtBreak items 1) keptAt :=
        (I3_blank_after_first_text_placement_matches_used_one items
          firstTextPos blankPos (fun _ => false) keptAt firstText
          textBeforeBlank firstHere).symm
  refine ⟨kept, top, placed, ?_, ?_, actualPlaced, fits⟩
  · have hit : .text firstTextPos ∈ items.filter (earlierTextItem figurePos) :=
      List.mem_filter.mpr ⟨firstText,
        by simp [earlierTextItem, textBeforeFigure]⟩
    have positive : 0 < count := by
      cases h : items.filter (earlierTextItem figurePos) with
      | nil => simp [h] at hit
      | cons x xs => simp [count, textBeforeCount, h]
    intro f bound
    have roomEq :
        figureHasRoom capacity 1 (fun _ => count - 1)
          (fun _ => figureSize)
          (fun g => !beforeBlankMask figurePos (figurePos + 1) blankPos g && !top) f ↔
        figureHasRoom capacity 0 (fun _ => count)
          (fun _ => figureSize)
          (fun g => !beforeBlankMask figurePos (figurePos + 1) blankPos g && !top) f := by
      simp only [figureHasRoom]
      omega
    have figureRule := shiftedRule f bound
    simpa [figuresRuleWithLoad, figuresRule, ready, count, roomEq] using figureRule
  · rw [usedTop, actualTop]

theorem I3_one_break_blank_no_figures
    (capacity firstTextPos blankPos : Nat) (items : List SourceItem)
    (capacityPositive : 1 ≤ capacity)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (different : blankPos ≠ firstTextPos) :
    ∃ atTop placed : Bool,
      atTop = blankAtTopSource 0 blankPos items (textHereAtBreak items 1)
        (fun _ => false) ∧
      placed = blankPlacedFromSourceFull 0 blankPos (fun _ => false)
        items (textHereAtBreak items 1) (fun _ => false) ∧
      1 + (if placed then 1 else 0) ≤ capacity := by
  by_cases before : blankPos < firstTextPos
  · have top := I3_blank_before_first_text_is_top items firstTextPos
      blankPos (fun _ => false) before first (by intro _ _; rfl)
    have notPlaced := I3_blank_before_first_text_not_placed items
      firstTextPos blankPos (fun _ => false) (fun _ => false)
      before first (by intro _ _; rfl)
    exact ⟨true, false, top.symm, notPlaced.symm,
      by simpa using capacityPositive⟩
  · have after : firstTextPos < blankPos := by omega
    have firstHere := I3_break_one_keeps_first_text items firstTextPos first
    have top := I3_blank_after_first_text_not_top items firstTextPos
      blankPos (fun _ => false) firstText after firstHere
    obtain ⟨placed, placedRule, fits⟩ :=
      I3_blankFigureOrder_no_figure_arbitrary_source_exists capacity 1
        blankPos (fun _ => false) items capacityPositive
    have actualPlace :=
      I3_blank_after_first_text_placement_matches_used_one items
        firstTextPos blankPos (fun _ => false) (fun _ => false)
        firstText after firstHere
    exact ⟨false, placed, top.symm,
      by calc
        placed = blankPlacedFromSourceFull 1 blankPos (fun _ => false)
            items (fun _ => false) (fun _ => false) := placedRule
        _ = blankPlacedFromSourceFull 0 blankPos (fun _ => false)
            items (textHereAtBreak items 1) (fun _ => false) :=
          actualPlace.symm,
      fits⟩

theorem I3_blankFigureOrder_no_blank_one_figure_zero_break
    (capacity used figurePos figureSize : Nat)
    (items : List SourceItem) (usedFits : used ≤ capacity) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad 1 capacity used kept
        (fun _ => textReadyZero items figurePos = true)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize) (fun _ => false) ∧
      used + (if kept 0 then figureSize else 0) ≤ capacity := by
  obtain ⟨kept, rule⟩ := I3_figuresRuleWithLoad_exists 1 capacity used
    (fun _ => textReadyZero items figurePos)
    (fun _ => textBeforeCount items figurePos)
    (fun _ => figureSize) (fun _ => false)
  refine ⟨kept, rule, ?_⟩
  cases present : kept 0 with
  | false => simpa [present] using usedFits
  | true =>
      have room := I3_kept_figure_has_room 1 capacity used kept
        (fun _ => textReadyZero items figurePos = true)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize) (fun _ => false)
        rule 0 (by decide) present
      simp [figureHasRoom, priorFigureLines,
        show List.range 0 = [] from rfl] at room
      simp [present]
      omega

theorem I3_blankFigureOrder_no_blank_no_figures
    (capacity used : Nat) (usedFits : used ≤ capacity) :
    ∃ kept : Nat → Bool,
      figuresRuleWithLoad 0 capacity used kept
        (fun _ => True) (fun _ => 0) (fun _ => 0) (fun _ => false) ∧
      used ≤ capacity := by
  refine ⟨fun _ => false, ?_, usedFits⟩
  intro f bound
  exact False.elim (Nat.not_lt_zero f bound)

inductive FigureConfig where
  | zero
  | one (pos size : Nat)
  | two (firstPos firstSize secondPos secondSize : Nat)

def figureCount : FigureConfig → Nat
  | .zero => 0
  | .one _ _ => 1
  | .two _ _ _ _ => 2

def figurePosAt : FigureConfig → Nat → Nat
  | .zero, _ => 0
  | .one pos _, _ => pos
  | .two firstPos _ secondPos _, f => if f = 0 then firstPos else secondPos

def figureSizeAt : FigureConfig → Nat → Nat
  | .zero, _ => 0
  | .one _ size, _ => size
  | .two _ firstSize _ secondSize, f => if f = 0 then firstSize else secondSize

def figureKeptAtPos : FigureConfig → (Nat → Bool) → Nat → Bool
  | .zero, _, _ => false
  | .one pos _, kept, sourcePos => keptAtTwoPositions pos (pos + 1) (kept 0) false sourcePos
  | .two firstPos _ secondPos _, kept, sourcePos =>
      keptAtTwoPositions firstPos secondPos (kept 0) (kept 1) sourcePos

def figureWaitingAtPos : FigureConfig → (Nat → Bool) → Nat → Bool
  | .zero, _, _ => false
  | .one _ _, _, _ => false
  | .two firstPos _ secondPos _, kept, sourcePos =>
      waitingAtTwoPositions firstPos secondPos kept sourcePos

theorem I3_waiting_at_pos_is_not_kept
    (config : FigureConfig) (kept : Nat → Bool)
    (validOrder : ∀ firstPos firstSize secondPos secondSize,
      config = .two firstPos firstSize secondPos secondSize → firstPos < secondPos)
    (pos : Nat) (waiting : figureWaitingAtPos config kept pos = true) :
    figureKeptAtPos config kept pos = false := by
  cases config with
  | zero => rfl
  | one _ _ => simp [figureWaitingAtPos] at waiting
  | two firstPos firstSize secondPos secondSize =>
      have ordered := validOrder firstPos firstSize secondPos secondSize rfl
      have different : firstPos ≠ secondPos := Nat.ne_of_lt ordered
      by_cases first : pos = firstPos
      · subst pos
        simp [figureWaitingAtPos, waitingAtTwoPositions,
          waitingFigureBool, earlierFigureSent] at waiting
      · by_cases second : pos = secondPos
        · subst pos
          have waitingSecond : waitingAtTwoPositions firstPos secondPos kept secondPos = true := by
            simpa [figureWaitingAtPos] using waiting
          have sent :=
            ((I3_waitingAtTwoPositions_matches_waitingIn firstPos secondPos
              different kept).2.mp waitingSecond).1
          simp [figureKeptAtPos, keptAtTwoPositions, Ne.symm different, sent]
        · simp [figureWaitingAtPos, waitingAtTwoPositions,
            first, second] at waiting

def blankMaskFor (figures : FigureConfig) (blank : Option Nat) : Nat → Bool :=
  match blank, figures with
  | some blankPos, .one pos _ => beforeBlankMask pos (pos + 1) blankPos
  | some blankPos, .two firstPos _ secondPos _ =>
      beforeBlankMask firstPos secondPos blankPos
  | _, _ => fun _ => false

def figureDomain (items : List SourceItem) : FigureConfig → Prop
  | .zero => ∀ pos, .figure pos ∉ items
  | .one pos _ => .figure pos ∈ items ∧
      ∀ otherPos, .figure otherPos ∈ items → otherPos = pos
  | .two firstPos _ secondPos _ =>
      firstPos < secondPos ∧ .figure firstPos ∈ items ∧
      .figure secondPos ∈ items ∧
      ∀ otherPos, .figure otherPos ∈ items →
        otherPos = firstPos ∨ otherPos = secondPos

def blankDomain (items : List SourceItem) : Option Nat → Prop
  | none => ∀ pos, .blank pos ∉ items
  | some pos => .blank pos ∈ items ∧
      ∀ otherPos, .blank otherPos ∈ items → otherPos = pos

def figureLoad (used : Nat) (config : FigureConfig)
    (kept : Nat → Bool) (placed : Bool) : Nat :=
  match config with
  | .zero => used + (if placed then 1 else 0)
  | .one _ size => used + (if kept 0 then size else 0) +
      (if placed then 1 else 0)
  | .two _ firstSize _ secondSize =>
      used + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) + (if placed then 1 else 0)

theorem I3_figureLoad_monotone_blank (used : Nat) (config : FigureConfig)
    (kept : Nat → Bool) (oldPlaced newPlaced : Bool)
    (oldImpliesNew : oldPlaced = true → newPlaced = true) :
    figureLoad used config kept oldPlaced ≤
      figureLoad used config kept newPlaced := by
  cases config <;> cases oldPlaced <;> cases newPlaced <;>
    simp_all [figureLoad] <;> omega

def zeroBreakPlacement (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool) : Prop :=
  figuresRuleWithLoad (figureCount config) capacity used kept
    (fun f => textReadyZero items (figurePosAt config f) = true)
    (fun f => textBeforeCount items (figurePosAt config f))
    (figureSizeAt config)
    (match blank with
      | none => fun _ => false
      | some _ => fun f => !blankMaskFor config blank f && !atTop) ∧
  atTop = (match blank with
    | none => false
    | some pos => blankAtTopSource used pos items (fun _ => false)
        (figureKeptAtPos config kept)) ∧
  placed = (match blank with
    | none => false
    | some pos => blankPlacedFromSourceFull used pos
        (figureWaitingAtPos config kept) items (fun _ => false)
        (figureKeptAtPos config kept)) ∧
  figureLoad used config kept placed ≤ capacity

def zeroBreakPlacement25 (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool) : Prop :=
  figuresRuleWithLoad (figureCount config) capacity used kept
    (fun f => textReadyZero items (figurePosAt config f) = true)
    (fun f => textBeforeCount items (figurePosAt config f))
    (figureSizeAt config)
    (match blank with
      | none => fun _ => false
      | some _ => fun f => !blankMaskFor config blank f && !atTop) ∧
  atTop = (match blank with
    | none => false
    | some pos => blankAtTopSource used pos items (fun _ => false)
        (figureKeptAtPos config kept)) ∧
  placed = (match blank with
    | none => false
    | some pos => blankPlaced25FromSourceFull used pos items
        (fun _ => false) (figureKeptAtPos config kept)) ∧
  figureLoad used config kept placed ≤ capacity

def oneBreakPlacement (capacity : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool) : Prop :=
  figuresRuleWithLoad (figureCount config) capacity 0 kept
    (fun f => textBeforeCount items (figurePosAt config f) ≤ 1)
    (fun f => textBeforeCount items (figurePosAt config f))
    (figureSizeAt config)
    (match blank with
      | none => fun _ => false
      | some _ => fun f => !blankMaskFor config blank f && !atTop) ∧
  atTop = (match blank with
    | none => false
    | some pos => blankAtTopSource 0 pos items
        (textHereAtBreak items 1) (figureKeptAtPos config kept)) ∧
  placed = (match blank with
    | none => false
    | some pos => blankPlacedFromSourceFull 0 pos
        (figureWaitingAtPos config kept) items
        (textHereAtBreak items 1) (figureKeptAtPos config kept)) ∧
  figureLoad 1 config kept placed ≤ capacity

def oneBreakPlacement25 (capacity : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool) : Prop :=
  figuresRuleWithLoad (figureCount config) capacity 0 kept
    (fun f => textBeforeCount items (figurePosAt config f) ≤ 1)
    (fun f => textBeforeCount items (figurePosAt config f))
    (figureSizeAt config)
    (match blank with
      | none => fun _ => false
      | some _ => fun f => !blankMaskFor config blank f && !atTop) ∧
  atTop = (match blank with
    | none => false
    | some pos => blankAtTopSource 0 pos items
        (textHereAtBreak items 1) (figureKeptAtPos config kept)) ∧
  placed = (match blank with
    | none => false
    | some pos => blankPlaced25FromSourceFull 0 pos items
        (textHereAtBreak items 1) (figureKeptAtPos config kept)) ∧
  figureLoad 1 config kept placed ≤ capacity

def figureSizesFit (capacity : Nat) : FigureConfig → Prop
  | .zero => True
  | .one _ size => size ≤ capacity
  | .two _ firstSize _ secondSize =>
      firstSize ≤ capacity ∧ secondSize ≤ capacity

def firstContentNotSent (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool) : Prop :=
  used = 0 →
    ∀ item, firstContent items = some item →
      match item with
      | .text _ => 1 ≤ brk
      | .figure pos => figureKeptAtPos config kept pos = true
      | .blank _ | .need _ => False

def startsColumnModel (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool) (pos : Nat) : Prop :=
  used = 0 ∧
    (∀ textPos, .text textPos ∈ items → textPos < pos →
      textHereAtBreak items brk textPos = false) ∧
    (∀ figurePos, .figure figurePos ∈ items → figurePos < pos →
      figureKeptAtPos config kept figurePos = false)

structure ParagraphBoundary where
  firstPos : Nat
  secondPos : Nat
  beforeLastPos : Nat
  lastPos : Nat
  lineCount : Nat

def paragraphBoundaryValid (items : List SourceItem)
    (p : ParagraphBoundary) : Prop :=
  .text p.firstPos ∈ items ∧
    .text p.beforeLastPos ∈ items ∧
    p.firstPos ≤ p.beforeLastPos

def orphanModel (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (paragraphs : List ParagraphBoundary) : Prop :=
  ∀ p ∈ paragraphs, 2 ≤ p.lineCount →
    textHereAtBreak items brk p.firstPos = true →
    textHereAtBreak items brk p.secondPos = false →
    startsColumnModel used brk items config kept p.firstPos

def widowModel (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (paragraphs : List ParagraphBoundary) : Prop :=
  ∀ p ∈ paragraphs, 2 ≤ p.lineCount →
    textHereAtBreak items brk p.beforeLastPos = true →
    textHereAtBreak items brk p.lastPos = false →
    startsColumnModel used brk items config kept p.firstPos

def orphanHSource (brk : Nat) (items : List SourceItem)
    (roleForText : Nat → AlloyTextRole)
    (keptFigure : Nat → Bool)
    (paragraphs : List ParagraphBoundary) : Prop :=
  ∀ p ∈ paragraphs, 2 ≤ p.lineCount →
    textHereAtBreak items brk p.firstPos = true →
    textHereAtBreak items brk p.secondPos = false →
    afterHeadingsOnlySource 0 brk items roleForText keptFigure p.firstPos

def widowHSource (brk : Nat) (items : List SourceItem)
    (roleForText : Nat → AlloyTextRole)
    (keptFigure : Nat → Bool)
    (paragraphs : List ParagraphBoundary) : Prop :=
  ∀ p ∈ paragraphs, 2 ≤ p.lineCount →
    textHereAtBreak items brk p.beforeLastPos = true →
    textHereAtBreak items brk p.lastPos = false →
    afterHeadingsOnlySource 0 brk items roleForText keptFigure p.firstPos

theorem I3_source_text_here_monotone
    (items : List SourceItem) (ordered : sourceOrdered items)
    (firstPos laterPos brk : Nat)
    (firstIn : .text firstPos ∈ items)
    (laterIn : .text laterPos ∈ items)
    (before : firstPos ≤ laterPos)
    (laterHere : textHereAtBreak items brk laterPos = true) :
    textHereAtBreak items brk firstPos = true := by
  by_cases same : firstPos = laterPos
  · simpa [same] using laterHere
  · have strict : firstPos < laterPos := by omega
    have firstMember :=
      (I3_source_text_position_member items firstPos).mpr firstIn
    have laterMember :=
      (I3_source_text_position_member items laterPos).mpr laterIn
    have ranks := I3_text_rank_preserves_order
      (sourceTextPositions items)
      (I3_source_text_positions_ordered items ordered)
      firstPos laterPos firstMember laterMember strict
    have laterRank :=
      (I3_text_here_iff_source_rank items ordered laterPos brk
        laterIn).mp laterHere
    apply (I3_text_here_iff_source_rank items ordered firstPos brk
      firstIn).mpr
    omega

theorem I3_alloy_first_break_relaxed_with_sent_figures
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → AlloyTextRole)
    (keptFigure : Nat → Bool)
    (paragraphs : List ParagraphBoundary)
    (valid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (firstIsLine : ∀ p ∈ paragraphs,
      roleForText p.firstPos = .line)
    (priorFiguresSent : ∀ p ∈ paragraphs,
      textHereAtBreak items
        (alloyTextFirstBreak
          ((sourceTextPositions items).map roleForText))
        p.firstPos = true →
      ∀ figurePos, .figure figurePos ∈ items →
        figurePos < p.firstPos → keptFigure figurePos = false) :
    let brk := alloyTextFirstBreak
      ((sourceTextPositions items).map roleForText)
    orphanHSource brk items roleForText keptFigure paragraphs ∧
      widowHSource brk items roleForText keptFigure paragraphs := by
  dsimp
  constructor
  · intro p member _ firstHere _
    have ⟨firstIn, _, _⟩ := valid p member
    exact I3_alloy_placed_line_after_sent_figures items ordered
      roleForText keptFigure p.firstPos firstIn
      (firstIsLine p member)
      (priorFiguresSent p member firstHere) firstHere
  · intro p member _ beforeLastHere _
    have ⟨firstIn, beforeLastIn, beforeLastOrder⟩ := valid p member
    have firstHere := I3_source_text_here_monotone items ordered
      p.firstPos p.beforeLastPos
      (alloyTextFirstBreak
        ((sourceTextPositions items).map roleForText))
      firstIn beforeLastIn beforeLastOrder beforeLastHere
    exact I3_alloy_placed_line_after_sent_figures items ordered
      roleForText keptFigure p.firstPos firstIn
      (firstIsLine p member)
      (priorFiguresSent p member firstHere) firstHere

theorem I3_alloy_first_break_relaxed_paragraphs
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → AlloyTextRole)
    (keptFigure : Nat → Bool)
    (paragraphs : List ParagraphBoundary)
    (valid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (firstIsLine : ∀ p ∈ paragraphs,
      roleForText p.firstPos = .line)
    (figuresAfterPlacedFirst : ∀ p ∈ paragraphs,
      textHereAtBreak items
        (alloyTextFirstBreak
          ((sourceTextPositions items).map roleForText))
        p.firstPos = true →
      ∀ figurePos, .figure figurePos ∈ items →
        p.firstPos < figurePos) :
    let brk := alloyTextFirstBreak
      ((sourceTextPositions items).map roleForText)
    orphanHSource brk items roleForText keptFigure paragraphs ∧
      widowHSource brk items roleForText keptFigure paragraphs := by
  apply I3_alloy_first_break_relaxed_with_sent_figures items ordered roleForText
    keptFigure paragraphs valid firstIsLine
  intro p member here figurePos figureIn before
  have after := figuresAfterPlacedFirst p member here figurePos figureIn
  omega

theorem I3_two_break_figure_blank_relaxed_paragraphs
    (capacity secondPos blankPos figurePos figureSize : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → AlloyTextRole)
    (paragraphs : List ParagraphBoundary)
    (twoFit : 2 ≤ capacity)
    (secondIn : .text secondPos ∈ items)
    (secondRank : textBeforeCount items secondPos = 1)
    (blankAfter : secondPos < blankPos)
    (figureAfter : 2 ≤ textBeforeCount items figurePos)
    (different : blankPos ≠ figurePos)
    (figureIn : .figure figurePos ∈ items)
    (onlyOne : ∀ pos, .figure pos ∈ items → pos = figurePos)
    (breakTwo : alloyTextFirstBreak
      ((sourceTextPositions items).map roleForText) = 2)
    (valid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (firstIsLine : ∀ p ∈ paragraphs,
      roleForText p.firstPos = .line)
    (figuresAfterPlacedFirst : ∀ p ∈ paragraphs,
      textHereAtBreak items 2 p.firstPos = true →
      p.firstPos < figurePos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      figuresRuleWithLoad 1 capacity 0 kept
        (fun _ => textBeforeCount items figurePos ≤ 2)
        (fun _ => textBeforeCount items figurePos)
        (fun _ => figureSize)
        (fun f => !beforeBlankMask figurePos (figurePos + 1) blankPos f && !atTop) ∧
      atTop = blankAtTopSource 0 blankPos items
        (textHereAtBreak items 2)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      placed = blankPlacedFromSourceFull 0 blankPos (fun _ => false)
        items (textHereAtBreak items 2)
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
      2 + (if kept 0 then figureSize else 0) +
        (if placed then 1 else 0) ≤ capacity ∧
      orphanHSource 2 items roleForText
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false)
        paragraphs ∧
      widowHSource 2 items roleForText
        (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false)
        paragraphs := by
  obtain ⟨kept, top, placed, figures, topRule, blankRule, fits⟩ :=
    I3_two_break_one_figure_one_blank_after_text capacity secondPos
      blankPos figurePos figureSize items ordered twoFit secondIn
      secondRank blankAfter figureAfter different figureIn onlyOne
  have relaxed := I3_alloy_first_break_relaxed_paragraphs items ordered
    roleForText
    (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false)
    paragraphs valid firstIsLine (by
      intro p member placedFirst otherPos otherIn
      have same := onlyOne otherPos otherIn
      subst otherPos
      apply figuresAfterPlacedFirst p member
      simpa [breakTwo] using placedFirst)
  rw [breakTwo] at relaxed
  exact ⟨kept, top, placed, figures, topRule, blankRule, fits,
    relaxed.1, relaxed.2⟩

theorem I3_two_break_two_figures_blank_relaxed_paragraphs
    (capacity secondTextPos blankPos firstPos secondPos
      firstSize secondSize : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items)
    (roleForText : Nat → AlloyTextRole)
    (paragraphs : List ParagraphBoundary)
    (twoFit : 2 ≤ capacity)
    (secondTextIn : .text secondTextPos ∈ items)
    (secondTextRank : textBeforeCount items secondTextPos = 1)
    (blankAfter : secondTextPos < blankPos)
    (firstTextBefore : 2 ≤ textBeforeCount items firstPos)
    (secondTextBefore : 2 ≤ textBeforeCount items secondPos)
    (figureOrder : firstPos < secondPos)
    (blankFirstDifferent : blankPos ≠ firstPos)
    (blankSecondDifferent : blankPos ≠ secondPos)
    (firstIn : .figure firstPos ∈ items)
    (secondIn : .figure secondPos ∈ items)
    (onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = firstPos ∨ pos = secondPos)
    (breakTwo : alloyTextFirstBreak
      ((sourceTextPositions items).map roleForText) = 2)
    (valid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (firstIsLine : ∀ p ∈ paragraphs,
      roleForText p.firstPos = .line)
    (figuresAfterPlacedFirst : ∀ p ∈ paragraphs,
      textHereAtBreak items 2 p.firstPos = true →
      p.firstPos < firstPos ∧ p.firstPos < secondPos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      figuresRuleWithLoad 2 capacity 0 kept
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos) ≤ 2)
        (fun f => textBeforeCount items
          (if f = 0 then firstPos else secondPos))
        (fun f => if f = 0 then firstSize else secondSize)
        (fun f => !beforeBlankMask firstPos secondPos blankPos f && !atTop) ∧
      atTop = blankAtTopSource 0 blankPos items
        (textHereAtBreak items 2)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      placed = blankPlacedFromSourceFull 0 blankPos
        (waitingAtTwoPositions firstPos secondPos kept) items
        (textHereAtBreak items 2)
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
      2 + (if kept 0 then firstSize else 0) +
        (if kept 1 then secondSize else 0) +
        (if placed then 1 else 0) ≤ capacity ∧
      orphanHSource 2 items roleForText
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1))
        paragraphs ∧
      widowHSource 2 items roleForText
        (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1))
        paragraphs := by
  obtain ⟨kept, top, placed, figures, topRule, blankRule, fits⟩ :=
    I3_two_break_two_figures_one_blank_after_text capacity secondTextPos
      blankPos firstPos secondPos firstSize secondSize items ordered
      twoFit secondTextIn secondTextRank blankAfter firstTextBefore
      secondTextBefore figureOrder blankFirstDifferent
      blankSecondDifferent firstIn secondIn onlyTwo
  have relaxed := I3_alloy_first_break_relaxed_paragraphs items ordered
    roleForText
    (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1))
    paragraphs valid firstIsLine (by
      intro p member placedFirst otherPos otherIn
      rcases onlyTwo otherPos otherIn with first | second
      · subst otherPos
        exact (figuresAfterPlacedFirst p member
          (by simpa [breakTwo] using placedFirst)).1
      · subst otherPos
        exact (figuresAfterPlacedFirst p member
          (by simpa [breakTwo] using placedFirst)).2)
  rw [breakTwo] at relaxed
  exact ⟨kept, top, placed, figures, topRule, blankRule, fits,
    relaxed.1, relaxed.2⟩

theorem I3_two_break_figure_blank_paragraph_fixture :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      2 + (if kept 0 then 1 else 0) +
        (if placed then 1 else 0) ≤ 3 ∧
      orphanHSource 2
        [.text 0, .text 1, .text 2, .blank 3, .figure 4]
        (fun pos => if pos = 0 then .heading else .line)
        (keptAtTwoPositions 4 5 (kept 0) false)
        [{firstPos := 1, secondPos := 2,
          beforeLastPos := 1, lastPos := 2, lineCount := 2}] ∧
      widowHSource 2
        [.text 0, .text 1, .text 2, .blank 3, .figure 4]
        (fun pos => if pos = 0 then .heading else .line)
        (keptAtTwoPositions 4 5 (kept 0) false)
        [{firstPos := 1, secondPos := 2,
          beforeLastPos := 1, lastPos := 2, lineCount := 2}] := by
  let items : List SourceItem :=
    [.text 0, .text 1, .text 2, .blank 3, .figure 4]
  let roles : Nat → AlloyTextRole :=
    fun pos => if pos = 0 then .heading else .line
  let p : ParagraphBoundary :=
    {firstPos := 1, secondPos := 2,
      beforeLastPos := 1, lastPos := 2, lineCount := 2}
  have ordered : sourceOrdered items := by
    simp [items, sourceOrdered, sourcePos]
  have secondIn : .text 1 ∈ items := by simp [items]
  have figureIn : .figure 4 ∈ items := by simp [items]
  have onlyOne : ∀ pos, .figure pos ∈ items → pos = 4 := by
    intro pos member
    simpa [items] using member
  have valid : ∀ q ∈ [p], paragraphBoundaryValid items q := by
    intro q member
    have same : q = p := by simpa using member
    subst q
    simp [p, paragraphBoundaryValid, items]
  have firstIsLine : ∀ q ∈ [p], roles q.firstPos = .line := by
    intro q member
    have same : q = p := by simpa using member
    subst q
    simp [p, roles]
  have figureAfter : ∀ q ∈ [p],
      textHereAtBreak items 2 q.firstPos = true → q.firstPos < 4 := by
    intro q member _
    have same : q = p := by simpa using member
    subst q
    simp [p]
  have witness := I3_two_break_figure_blank_relaxed_paragraphs
    3 1 3 4 1 items ordered roles [p]
    (by decide) secondIn (by simp [items, textBeforeCount,
      earlierTextItem]) (by decide)
    (by simp [items, textBeforeCount, earlierTextItem])
    (by decide) figureIn onlyOne
    (by simp [items, roles, sourceTextPositions,
      alloyTextFirstBreak])
    valid firstIsLine figureAfter
  obtain ⟨kept, top, placed, _, _, _, fits, orphan, widow⟩ := witness
  exact ⟨kept, top, placed, fits, orphan, widow⟩

theorem I3_two_break_two_figures_paragraph_fixture :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      2 + (if kept 0 then 1 else 0) +
        (if kept 1 then 1 else 0) +
        (if placed then 1 else 0) ≤ 3 ∧
      orphanHSource 2
        [.text 0, .text 1, .text 2, .blank 3,
          .figure 4, .figure 5]
        (fun pos => if pos = 0 then .heading else .line)
        (keptAtTwoPositions 4 5 (kept 0) (kept 1))
        [{firstPos := 1, secondPos := 2,
          beforeLastPos := 1, lastPos := 2, lineCount := 2}] ∧
      widowHSource 2
        [.text 0, .text 1, .text 2, .blank 3,
          .figure 4, .figure 5]
        (fun pos => if pos = 0 then .heading else .line)
        (keptAtTwoPositions 4 5 (kept 0) (kept 1))
        [{firstPos := 1, secondPos := 2,
          beforeLastPos := 1, lastPos := 2, lineCount := 2}] := by
  let items : List SourceItem :=
    [.text 0, .text 1, .text 2, .blank 3,
      .figure 4, .figure 5]
  let roles : Nat → AlloyTextRole :=
    fun pos => if pos = 0 then .heading else .line
  let p : ParagraphBoundary :=
    {firstPos := 1, secondPos := 2,
      beforeLastPos := 1, lastPos := 2, lineCount := 2}
  have ordered : sourceOrdered items := by
    simp [items, sourceOrdered, sourcePos]
  have secondTextIn : .text 1 ∈ items := by simp [items]
  have firstFigureIn : .figure 4 ∈ items := by simp [items]
  have secondFigureIn : .figure 5 ∈ items := by simp [items]
  have onlyTwo : ∀ pos, .figure pos ∈ items →
      pos = 4 ∨ pos = 5 := by
    intro pos member
    simpa [items] using member
  have valid : ∀ q ∈ [p], paragraphBoundaryValid items q := by
    intro q member
    have same : q = p := by simpa using member
    subst q
    simp [p, paragraphBoundaryValid, items]
  have firstIsLine : ∀ q ∈ [p], roles q.firstPos = .line := by
    intro q member
    have same : q = p := by simpa using member
    subst q
    simp [p, roles]
  have figuresAfter : ∀ q ∈ [p],
      textHereAtBreak items 2 q.firstPos = true →
      q.firstPos < 4 ∧ q.firstPos < 5 := by
    intro q member _
    have same : q = p := by simpa using member
    subst q
    simp [p]
  have witness := I3_two_break_two_figures_blank_relaxed_paragraphs
    3 1 3 4 5 1 1 items ordered roles [p]
    (by decide) secondTextIn
    (by simp [items, textBeforeCount, earlierTextItem])
    (by decide)
    (by simp [items, textBeforeCount, earlierTextItem])
    (by simp [items, textBeforeCount, earlierTextItem])
    (by decide) (by decide) (by decide)
    firstFigureIn secondFigureIn onlyTwo
    (by simp [items, roles, sourceTextPositions,
      alloyTextFirstBreak])
    valid firstIsLine figuresAfter
  obtain ⟨kept, top, placed, _, _, _, fits, orphan, widow⟩ := witness
  exact ⟨kept, top, placed, fits, orphan, widow⟩

def headingKeepModel (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (headings : List Nat) (keptLines : Nat → Prop) : Prop :=
  ∀ h ∈ headings,
    textHereAtBreak items brk h = true →
    ¬ startsColumnModel used brk items config kept h →
    keptLines h

def rectoModel (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (rectos : List Nat) : Prop :=
  ∀ r ∈ rectos,
    textHereAtBreak items brk r = true →
    startsColumnModel used brk items config kept r

structure KeepParagraph where
  firstPos : Nat
  linePositions : List Nat
  firstCount : Nat
  lastCount : Nat
  allLines : Bool

def keepParagraphValid (items : List SourceItem) (p : KeepParagraph) : Prop :=
  p.firstPos ∈ p.linePositions ∧
    ∀ pos ∈ p.linePositions, .text pos ∈ items ∧ p.firstPos ≤ pos

def paragraphHasHere (brk : Nat) (items : List SourceItem)
    (p : KeepParagraph) : Prop :=
  ∃ pos ∈ p.linePositions, textHereAtBreak items brk pos = true

def paragraphBrokenModel (brk : Nat) (items : List SourceItem)
    (p : KeepParagraph) : Prop :=
  paragraphHasHere brk items p ∧
    ∃ pos ∈ p.linePositions, textHereAtBreak items brk pos = false

def paragraphHereCount (brk : Nat) (items : List SourceItem)
    (p : KeepParagraph) : Nat :=
  (p.linePositions.filter
    (fun pos => textHereAtBreak items brk pos)).length

def paragraphNextCount (brk : Nat) (items : List SourceItem)
    (p : KeepParagraph) : Nat :=
  (p.linePositions.filter
    (fun pos => !textHereAtBreak items brk pos)).length

theorem I3_filter_length_positive_iff_exists
    (xs : List Nat) (f : Nat → Bool) :
    0 < (xs.filter f).length ↔ ∃ x ∈ xs, f x = true := by
  induction xs with
  | nil => simp
  | cons x xs ih =>
      cases h : f x <;> simp [List.filter, h, ih]

theorem I3_paragraph_broken_count_equivalence
    (brk : Nat) (items : List SourceItem) (p : KeepParagraph) :
    paragraphBrokenModel brk items p ↔
      0 < paragraphHereCount brk items p ∧
        0 < paragraphNextCount brk items p := by
  have hereEq : paragraphHasHere brk items p ↔
      0 < paragraphHereCount brk items p := by
    simpa [paragraphHasHere, paragraphHereCount] using
      (I3_filter_length_positive_iff_exists p.linePositions
        (textHereAtBreak items brk)).symm
  have nextEq :
      (∃ pos ∈ p.linePositions,
        textHereAtBreak items brk pos = false) ↔
        0 < paragraphNextCount brk items p := by
    rw [paragraphNextCount, I3_filter_length_positive_iff_exists]
    constructor
    · rintro ⟨pos, member, next⟩
      exact ⟨pos, member, by simp [next]⟩
    · rintro ⟨pos, member, next⟩
      cases h : textHereAtBreak items brk pos <;>
        simp [h] at next ⊢
      exact ⟨pos, member, h⟩
  simp [paragraphBrokenModel, hereEq, nextEq]

theorem I3_paragraph_line_partition
    (brk : Nat) (items : List SourceItem) (p : KeepParagraph) :
    paragraphHereCount brk items p + paragraphNextCount brk items p =
      p.linePositions.length := by
  unfold paragraphHereCount paragraphNextCount
  generalize p.linePositions = positions
  induction positions with
  | nil => simp
  | cons pos rest ih =>
      cases h : textHereAtBreak items brk pos <;>
        simp [List.filter, h] <;> omega

theorem I3_split_broken_matches_paragraph
    (brk : Nat) (items : List SourceItem) (p : KeepParagraph) :
    splitBroken p.linePositions.length (paragraphHereCount brk items p) ↔
      paragraphBrokenModel brk items p := by
  have partition := I3_paragraph_line_partition brk items p
  rw [I3_paragraph_broken_count_equivalence]
  unfold splitBroken
  omega

theorem I3_keep_default_paragraph_equivalence
    (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (p : KeepParagraph) :
    (orphanByBoundary p.linePositions.length
        (paragraphHereCount brk items p)
        (startsColumnModel used brk items config kept p.firstPos) ∧
      widowByBoundary p.linePositions.length
        (paragraphHereCount brk items p)
        (startsColumnModel used brk items config kept p.firstPos)) ↔
      (splitKeepFirst p.linePositions.length
        (paragraphHereCount brk items p)
        (startsColumnModel used brk items config kept p.firstPos) ∧
      splitKeepLast p.linePositions.length
        (paragraphHereCount brk items p)
        (startsColumnModel used brk items config kept p.firstPos)) := by
  have partition := I3_paragraph_line_partition brk items p
  exact keepDefaultDiffers p.linePositions.length
    (paragraphHereCount brk items p)
    (startsColumnModel used brk items config kept p.firstPos) (by omega)

def keepFirstModel (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (paragraphs : List KeepParagraph) : Prop :=
  ∀ p ∈ paragraphs, paragraphBrokenModel brk items p →
    ¬ startsColumnModel used brk items config kept p.firstPos →
    p.firstCount ≤ paragraphHereCount brk items p

def keepLastModel (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (paragraphs : List KeepParagraph) : Prop :=
  ∀ p ∈ paragraphs, paragraphBrokenModel brk items p →
    ¬ startsColumnModel used brk items config kept p.firstPos →
    p.lastCount ≤ paragraphNextCount brk items p

def keepAllModel (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (paragraphs : List KeepParagraph) : Prop :=
  ∀ p ∈ paragraphs, p.allLines = true →
    paragraphBrokenModel brk items p →
    startsColumnModel used brk items config kept p.firstPos

theorem I3_old_blank_rule_projection
    (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop newPlaced : Bool)
    (figuresValid : figureDomain items config)
    (newRule : zeroBreakPlacement capacity used items config blank
      kept atTop newPlaced) :
    ∃ oldPlaced : Bool,
      zeroBreakPlacement25 capacity used items config blank
        kept atTop oldPlaced := by
  obtain ⟨figureRule, topRule, newPlacedRule, fitsNew⟩ := newRule
  cases blank with
  | none =>
      refine ⟨false, figureRule, topRule, rfl, ?_⟩
      simpa [newPlacedRule] using fitsNew
  | some blankPos =>
      let oldPlaced := blankPlaced25FromSourceFull used blankPos items
        (fun _ => false) (figureKeptAtPos config kept)
      have noWaitingHere : ∀ pos,
          figureWaitingAtPos config kept pos = true →
            figureKeptAtPos config kept pos = false := by
        intro pos waiting
        apply I3_waiting_at_pos_is_not_kept config kept
        · intro firstPos firstSize secondPos secondSize equalConfig
          cases config with
          | zero => cases equalConfig
          | one _ _ => cases equalConfig
          | two p1 s1 p2 s2 =>
              cases equalConfig
              exact figuresValid.1
        · exact waiting
      have oldImpliesNew : oldPlaced = true → newPlaced = true := by
        intro oldTrue
        have newTrue := I3_old_blank_placed_implies_new used blankPos items
          (figureWaitingAtPos config kept) (fun _ => false)
          (figureKeptAtPos config kept) noWaitingHere oldTrue
        simpa [newPlacedRule] using newTrue
      have fitsOld : figureLoad used config kept oldPlaced ≤ capacity :=
        Nat.le_trans
          (I3_figureLoad_monotone_blank used config kept oldPlaced
            newPlaced oldImpliesNew)
          fitsNew
      exact ⟨oldPlaced, figureRule, topRule, rfl, fitsOld⟩

theorem I3_one_break_old_blank_rule_projection
    (capacity : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop newPlaced : Bool)
    (figuresValid : figureDomain items config)
    (newRule : oneBreakPlacement capacity items config blank
      kept atTop newPlaced) :
    ∃ oldPlaced : Bool,
      oneBreakPlacement25 capacity items config blank
        kept atTop oldPlaced := by
  obtain ⟨figureRule, topRule, newPlacedRule, fitsNew⟩ := newRule
  cases blank with
  | none =>
      refine ⟨false, figureRule, topRule, rfl, ?_⟩
      simpa [newPlacedRule] using fitsNew
  | some blankPos =>
      let oldPlaced := blankPlaced25FromSourceFull 0 blankPos items
        (textHereAtBreak items 1) (figureKeptAtPos config kept)
      have noWaitingHere : ∀ pos,
          figureWaitingAtPos config kept pos = true →
            figureKeptAtPos config kept pos = false := by
        intro pos waiting
        apply I3_waiting_at_pos_is_not_kept config kept
        · intro firstPos firstSize secondPos secondSize equalConfig
          cases config with
          | zero => cases equalConfig
          | one _ _ => cases equalConfig
          | two p1 s1 p2 s2 =>
              cases equalConfig
              exact figuresValid.1
        · exact waiting
      have oldImpliesNew : oldPlaced = true → newPlaced = true := by
        intro oldTrue
        have newTrue := I3_old_blank_placed_implies_new 0 blankPos items
          (figureWaitingAtPos config kept) (textHereAtBreak items 1)
          (figureKeptAtPos config kept) noWaitingHere oldTrue
        simpa [newPlacedRule] using newTrue
      have fitsOld : figureLoad 1 config kept oldPlaced ≤ capacity :=
        Nat.le_trans
          (I3_figureLoad_monotone_blank 1 config kept oldPlaced
            newPlaced oldImpliesNew)
          fitsNew
      exact ⟨oldPlaced, figureRule, topRule, rfl, fitsOld⟩

theorem I3_zeroBreakPlacement_implies_figure_order
    (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool)
    (placement : zeroBreakPlacement capacity used items config blank kept atTop placed) :
    figuresInOrder (figureCount config) kept := by
  exact I3_figuresRule_implies_figuresInOrder _ _ _ _ placement.1

theorem I3_zeroBreakPlacement_implies_text_order
    (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool)
    (placement : zeroBreakPlacement capacity used items config blank kept atTop placed) :
    ∀ f, f < figureCount config → kept f = true →
      ∀ pos, .text pos ∈ items → pos < figurePosAt config f → False := by
  intro f bound present pos member earlier
  have rule := placement.1 f bound
  have ready : textReadyZero items (figurePosAt config f) = true :=
    (rule.mp present).1
  have later := (I3_textReadyZero_iff_no_earlier_text items
    (figurePosAt config f)).mp ready pos member
  omega

theorem I3_empty_column_first_figure_kept
    (capacity pos size : Nat) (items : List SourceItem)
    (noEarlierText : ∀ textPos, .text textPos ∈ items → pos ≤ textPos)
    (fits : size ≤ capacity)
    (kept : Nat → Bool) (atTop placed : Bool)
    (placement : zeroBreakPlacement capacity 0 items (.one pos size) none
      kept atTop placed) :
    kept 0 = true := by
  have noEarlier : ∀ item ∈ items, earlierTextItem pos item = false := by
    intro item member
    cases item with
    | text textPos =>
        have later := noEarlierText textPos member
        simp [earlierTextItem, Nat.not_lt.mpr later]
    | figure _ => rfl
    | blank _ => rfl
    | need _ => rfl
  have countZero : textBeforeCount items pos = 0 := by
    have emptyFilter : items.filter (earlierTextItem pos) = [] :=
      List.filter_eq_nil.mpr (by
        intro item member hit
        simp [noEarlier item member] at hit)
    simp [textBeforeCount, emptyFilter]
  have ready : textReadyZero items pos = true :=
    (I3_textReadyZero_iff_no_earlier_text items pos).mpr noEarlierText
  have rule := placement.1 0 (by simp [figureCount])
  apply rule.mpr
  refine ⟨ready, ?_, ?_⟩
  · intro g before
    exact False.elim (Nat.not_lt_zero g before)
  · simp [figureHasRoom, figurePosAt, figureSizeAt, priorFigureLines,
      countZero, blankMaskFor, fits, show List.range 0 = [] from rfl]

theorem I3_empty_column_first_of_two_figures_kept
    (capacity firstPos firstSize secondPos secondSize : Nat)
    (items : List SourceItem)
    (noEarlierText : ∀ textPos, .text textPos ∈ items → firstPos ≤ textPos)
    (fits : firstSize ≤ capacity)
    (kept : Nat → Bool) (atTop placed : Bool)
    (placement : zeroBreakPlacement capacity 0 items
      (.two firstPos firstSize secondPos secondSize) none
      kept atTop placed) :
    kept 0 = true := by
  have here := I3_break_one_keeps_first_text items firstPos noEarlierText
  have countZero : textBeforeCount items firstPos = 0 := by
    simp [textHereAtBreak] at here
    omega
  have ready : textReadyZero items firstPos = true :=
    (I3_textReadyZero_iff_no_earlier_text items firstPos).mpr noEarlierText
  have rule := placement.1 0 (by simp [figureCount])
  apply rule.mpr
  refine ⟨ready, ?_, ?_⟩
  · intro g before
    exact False.elim (Nat.not_lt_zero g before)
  · simp [figureHasRoom, figurePosAt, figureSizeAt, priorFigureLines,
      countZero, blankMaskFor, fits, show List.range 0 = [] from rfl]

theorem I3_empty_column_first_figure_with_blank_kept
    (capacity figurePos figureSize blankPos : Nat)
    (items : List SourceItem)
    (noEarlierText : ∀ textPos, .text textPos ∈ items →
      figurePos ≤ textPos)
    (fits : figureSize ≤ capacity)
    (different : blankPos ≠ figurePos)
    (kept : Nat → Bool) (atTop placed : Bool)
    (placement : zeroBreakPlacement capacity 0 items
      (.one figurePos figureSize) (some blankPos)
      kept atTop placed) :
    kept 0 = true := by
  have here := I3_break_one_keeps_first_text items figurePos noEarlierText
  have countZero : textBeforeCount items figurePos = 0 := by
    simp [textHereAtBreak] at here
    omega
  have ready : textReadyZero items figurePos = true :=
    (I3_textReadyZero_iff_no_earlier_text items figurePos).mpr noEarlierText
  have topRule := placement.2.1
  have penaltyFalse :
      (!blankMaskFor (.one figurePos figureSize) (some blankPos) 0 &&
        !atTop) = false := by
    by_cases before : blankPos < figurePos
    · have noFigureBefore : ∀ pos, pos < blankPos →
          figureKeptAtPos (.one figurePos figureSize) kept pos = false := by
        intro pos beforePos
        have notFirst : pos ≠ figurePos := by omega
        have notSecond : pos ≠ figurePos + 1 := by omega
        simp [figureKeptAtPos, keptAtTwoPositions, notFirst, notSecond]
      have top := I3_blank_before_first_figure_is_top items blankPos
        (figureKeptAtPos (.one figurePos figureSize) kept) noFigureBefore
      have atTopTrue : atTop = true := by
        simpa using topRule.trans top
      simp [atTopTrue]
    · have figureBefore : figurePos < blankPos := by omega
      simp [blankMaskFor, beforeBlankMask, figureBefore]
  have rule := placement.1 0 (by simp [figureCount])
  apply rule.mpr
  refine ⟨ready, ?_, ?_⟩
  · intro g before
    exact False.elim (Nat.not_lt_zero g before)
  · simp [figureHasRoom, figurePosAt, figureSizeAt, priorFigureLines,
      countZero, penaltyFalse, fits,
      show List.range 0 = [] from rfl]

theorem I3_empty_column_first_of_two_figures_with_blank_kept
    (capacity firstPos firstSize secondPos secondSize blankPos : Nat)
    (items : List SourceItem)
    (ordered : firstPos < secondPos)
    (noEarlierText : ∀ textPos, .text textPos ∈ items →
      firstPos ≤ textPos)
    (fits : firstSize ≤ capacity)
    (different : blankPos ≠ firstPos)
    (kept : Nat → Bool) (atTop placed : Bool)
    (placement : zeroBreakPlacement capacity 0 items
      (.two firstPos firstSize secondPos secondSize) (some blankPos)
      kept atTop placed) :
    kept 0 = true := by
  have here := I3_break_one_keeps_first_text items firstPos noEarlierText
  have countZero : textBeforeCount items firstPos = 0 := by
    simp [textHereAtBreak] at here
    omega
  have ready : textReadyZero items firstPos = true :=
    (I3_textReadyZero_iff_no_earlier_text items firstPos).mpr noEarlierText
  have topRule := placement.2.1
  have penaltyFalse :
      (!blankMaskFor (.two firstPos firstSize secondPos secondSize)
        (some blankPos) 0 && !atTop) = false := by
    by_cases before : blankPos < firstPos
    · have noFigureBefore : ∀ pos, pos < blankPos →
          figureKeptAtPos (.two firstPos firstSize secondPos secondSize)
            kept pos = false := by
        intro pos beforePos
        have notFirst : pos ≠ firstPos := by omega
        have notSecond : pos ≠ secondPos := by omega
        simp [figureKeptAtPos, keptAtTwoPositions, notFirst, notSecond]
      have top := I3_blank_before_first_figure_is_top items blankPos
        (figureKeptAtPos (.two firstPos firstSize secondPos secondSize) kept)
        noFigureBefore
      have atTopTrue : atTop = true := by
        simpa using topRule.trans top
      simp [atTopTrue]
    · have figureBefore : firstPos < blankPos := by omega
      simp [blankMaskFor, beforeBlankMask, figureBefore]
  have rule := placement.1 0 (by simp [figureCount])
  apply rule.mpr
  refine ⟨ready, ?_, ?_⟩
  · intro g before
    exact False.elim (Nat.not_lt_zero g before)
  · simp [figureHasRoom, figurePosAt, figureSizeAt, priorFigureLines,
      countZero, penaltyFalse, fits,
      show List.range 0 = [] from rfl]

theorem blankFigureOrder (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (usedFits : used ≤ capacity) (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      zeroBreakPlacement capacity used items config blank kept atTop placed := by
  cases config with
  | zero =>
      cases blank with
      | none =>
          refine ⟨fun _ => false, false, false, ?_⟩
          simp [zeroBreakPlacement, figureCount, figureLoad,
            blankMaskFor, usedFits]
          intro f bound
          exact False.elim (Nat.not_lt_zero f bound)
      | some blankPos =>
          obtain ⟨placed, placedRule, fits⟩ :=
            I3_blankFigureOrder_no_figure_arbitrary_source_exists
              capacity used blankPos (fun _ => false) items usedFits
          refine ⟨fun _ => false,
            blankAtTopSource used blankPos items (fun _ => false) (fun _ => false),
            placed, ?_⟩
          unfold zeroBreakPlacement
          refine ⟨?_, ?_, ?_, ?_⟩
          · intro f bound
            exact False.elim (Nat.not_lt_zero f bound)
          · rfl
          · simpa [figureWaitingAtPos, figureKeptAtPos] using placedRule
          · simpa [figureLoad] using fits
  | one pos size =>
      cases blank with
      | none =>
          obtain ⟨kept, rule, fits⟩ :=
            I3_blankFigureOrder_no_blank_one_figure_zero_break
              capacity used pos size items usedFits
          exact ⟨kept, false, false,
            by simpa [zeroBreakPlacement, figureCount, figurePosAt,
              figureSizeAt, blankMaskFor, figureLoad] using
              (show figuresRuleWithLoad 1 capacity used kept
                (fun _ => textReadyZero items pos = true)
                (fun _ => textBeforeCount items pos)
                (fun _ => size) (fun _ => false) ∧
                used + (if kept 0 then size else 0) ≤ capacity from ⟨rule, fits⟩)⟩
      | some blankPos =>
          rcases figuresValid with ⟨figureIn, onlyOne⟩
          rcases blankValid with ⟨blankIn, _⟩
          have different : blankPos ≠ pos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.figure pos) blankIn figureIn
              (by simp [sourcePos, samePos])
            cases sameItem
          obtain ⟨top, kept, placed, rule, topRule, blankRule, fits⟩ :=
            I3_blankFigureOrder_one_figure_arbitrary_source_exists
              capacity used blankPos pos size
              (fun _ => textReadyZero items pos)
              (fun _ => textBeforeCount items pos)
              (fun _ _ => false) items usedFits different figureIn onlyOne
          refine ⟨kept, top, placed, ?_⟩
          simpa [zeroBreakPlacement, figureCount, figurePosAt,
            figureSizeAt, blankMaskFor, figureLoad,
            figureKeptAtPos, figureWaitingAtPos] using
            (show figuresRuleWithLoad 1 capacity used kept
              (fun _ => textReadyZero items pos = true)
              (fun _ => textBeforeCount items pos) (fun _ => size)
              (fun f => !beforeBlankMask pos (pos + 1) blankPos f && !top) ∧
              top = blankAtTopSource used blankPos items (fun _ => false)
                (keptAtTwoPositions pos (pos + 1) (kept 0) false) ∧
              placed = blankPlacedFromSourceFull used blankPos (fun _ => false)
                items (fun _ => false)
                (keptAtTwoPositions pos (pos + 1) (kept 0) false) ∧
              used + (if kept 0 then size else 0) +
                (if placed then 1 else 0) ≤ capacity from
              ⟨rule, topRule, blankRule, fits⟩)
  | two firstPos firstSize secondPos secondSize =>
      cases blank with
      | none =>
          obtain ⟨kept, rule, fits⟩ :=
            I3_blankFigureOrder_no_blank_two_figures_zero_break
              capacity used firstPos secondPos firstSize secondSize items usedFits
          refine ⟨kept, false, false, ?_⟩
          simpa [zeroBreakPlacement, figureCount, figurePosAt,
            figureSizeAt, blankMaskFor, figureLoad] using
            (show figuresRuleWithLoad 2 capacity used kept
              (fun f => textReadyZero items (if f = 0 then firstPos else secondPos) = true)
              (fun f => textBeforeCount items (if f = 0 then firstPos else secondPos))
              (fun f => if f = 0 then firstSize else secondSize) (fun _ => false) ∧
              used + (if kept 0 then firstSize else 0) +
                (if kept 1 then secondSize else 0) ≤ capacity from ⟨rule, fits⟩)
      | some blankPos =>
          rcases figuresValid with ⟨positions, firstIn, secondIn, onlyTwo⟩
          rcases blankValid with ⟨blankIn, _⟩
          have blankFirstDifferent : blankPos ≠ firstPos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.figure firstPos) blankIn firstIn
              (by simp [sourcePos, samePos])
            cases sameItem
          have blankSecondDifferent : blankPos ≠ secondPos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.figure secondPos) blankIn secondIn
              (by simp [sourcePos, samePos])
            cases sameItem
          obtain ⟨top, kept, placed, rule, topRule, blankRule, fits⟩ :=
            I3_blankFigureOrder_two_figures_zero_break capacity used blankPos
              firstPos secondPos firstSize secondSize items usedFits positions
              blankFirstDifferent blankSecondDifferent firstIn secondIn onlyTwo
          refine ⟨kept, top, placed, ?_⟩
          simpa [zeroBreakPlacement, figureCount, figurePosAt,
            figureSizeAt, blankMaskFor, figureLoad,
            figureKeptAtPos, figureWaitingAtPos] using
            (show figuresRuleWithLoad 2 capacity used kept
              (fun f => textReadyZero items (if f = 0 then firstPos else secondPos) = true)
              (fun f => textBeforeCount items (if f = 0 then firstPos else secondPos))
              (fun f => if f = 0 then firstSize else secondSize)
              (fun f => !beforeBlankMask firstPos secondPos blankPos f && !top) ∧
              top = blankAtTopSource used blankPos items (fun _ => false)
                (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
              placed = blankPlacedFromSourceFull used blankPos
                (waitingAtTwoPositions firstPos secondPos kept) items
                (fun _ => false)
                (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
              used + (if kept 0 then firstSize else 0) +
                (if kept 1 then secondSize else 0) +
                (if placed then 1 else 0) ≤ capacity from
              ⟨rule, topRule, blankRule, fits⟩)

theorem I3_blankFigureOrder_old_blank_projection
    (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (usedFits : used ≤ capacity) (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank) :
    ∃ kept : Nat → Bool, ∃ atTop newPlaced oldPlaced : Bool,
      zeroBreakPlacement capacity used items config blank kept atTop newPlaced ∧
      zeroBreakPlacement25 capacity used items config blank kept atTop oldPlaced ∧
      figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ pos, .text pos ∈ items → pos < figurePosAt config f → False) := by
  obtain ⟨kept, atTop, newPlaced, newRule⟩ :=
    blankFigureOrder capacity used items config blank usedFits ordered
      figuresValid blankValid
  obtain ⟨oldPlaced, oldRule⟩ :=
    I3_old_blank_rule_projection capacity used items config blank kept
      atTop newPlaced figuresValid newRule
  exact ⟨kept, atTop, newPlaced, oldPlaced, newRule, oldRule,
    I3_zeroBreakPlacement_implies_figure_order capacity used items config
      blank kept atTop newPlaced newRule,
    I3_zeroBreakPlacement_implies_text_order capacity used items config
      blank kept atTop newPlaced newRule⟩

theorem I3_blankFigureOrder_one_break
    (capacity firstTextPos : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (capacityPositive : 1 ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (textBeforeFigures : ∀ pos, .figure pos ∈ items → firstTextPos < pos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      oneBreakPlacement capacity items config blank kept atTop placed := by
  cases config with
  | zero =>
      cases blank with
      | none =>
          refine ⟨fun _ => false, false, false, ?_⟩
          unfold oneBreakPlacement
          refine ⟨?_, rfl, rfl, ?_⟩
          · intro f bound
            exact False.elim (Nat.not_lt_zero f bound)
          · simpa [figureLoad] using capacityPositive
      | some blankPos =>
          rcases blankValid with ⟨blankIn, _⟩
          have different : blankPos ≠ firstTextPos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.text firstTextPos) blankIn firstText
              (by simp [sourcePos, samePos])
            cases sameItem
          obtain ⟨top, placed, topRule, placedRule, fits⟩ :=
            I3_one_break_blank_no_figures capacity firstTextPos blankPos items
              capacityPositive firstText first different
          refine ⟨fun _ => false, top, placed, ?_⟩
          unfold oneBreakPlacement
          refine ⟨?_, ?_, ?_, ?_⟩
          · intro f bound
            exact False.elim (Nat.not_lt_zero f bound)
          · simpa [figureKeptAtPos] using topRule
          · simpa [figureWaitingAtPos, figureKeptAtPos] using placedRule
          · simpa [figureLoad] using fits
  | one figurePos figureSize =>
      rcases figuresValid with ⟨figureIn, onlyOne⟩
      have beforeFigure := textBeforeFigures figurePos figureIn
      cases blank with
      | none =>
          obtain ⟨kept, rule, fits⟩ :=
            I3_one_break_no_blank_one_figure capacity firstTextPos
              figurePos figureSize items capacityPositive firstText beforeFigure
          refine ⟨kept, false, false, ?_⟩
          simpa [oneBreakPlacement, figureCount, figurePosAt,
            figureSizeAt, blankMaskFor, figureLoad] using
            (show figuresRuleWithLoad 1 capacity 0 kept
              (fun _ => textBeforeCount items figurePos ≤ 1)
              (fun _ => textBeforeCount items figurePos)
              (fun _ => figureSize) (fun _ => false) ∧
              1 + (if kept 0 then figureSize else 0) ≤ capacity from
              ⟨rule, fits⟩)
      | some blankPos =>
          rcases blankValid with ⟨blankIn, _⟩
          have different : blankPos ≠ firstTextPos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.text firstTextPos) blankIn firstText
              (by simp [sourcePos, samePos])
            cases sameItem
          have blankFigureDifferent : blankPos ≠ figurePos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.figure figurePos) blankIn figureIn
              (by simp [sourcePos, samePos])
            cases sameItem
          let caseProof :=
            if before : blankPos < firstTextPos then
              I3_one_break_blank_before_text_one_figure capacity
                blankPos firstTextPos figurePos figureSize items
                capacityPositive firstText first before beforeFigure
            else
              I3_one_break_blank_after_text_one_figure capacity
                firstTextPos blankPos figurePos figureSize items
                capacityPositive firstText first (by omega) beforeFigure
                blankFigureDifferent figureIn onlyOne
          obtain ⟨kept, top, placed, rule, topRule, placedRule, fits⟩ := caseProof
          refine ⟨kept, top, placed, ?_⟩
          simpa [oneBreakPlacement, figureCount, figurePosAt,
            figureSizeAt, blankMaskFor, figureLoad,
            figureKeptAtPos, figureWaitingAtPos] using
            (show figuresRuleWithLoad 1 capacity 0 kept
              (fun _ => textBeforeCount items figurePos ≤ 1)
              (fun _ => textBeforeCount items figurePos)
              (fun _ => figureSize)
              (fun f => !beforeBlankMask figurePos (figurePos + 1)
                blankPos f && !top) ∧
              top = blankAtTopSource 0 blankPos items
                (textHereAtBreak items 1)
                (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
              placed = blankPlacedFromSourceFull 0 blankPos (fun _ => false)
                items (textHereAtBreak items 1)
                (keptAtTwoPositions figurePos (figurePos + 1) (kept 0) false) ∧
              1 + (if kept 0 then figureSize else 0) +
                (if placed then 1 else 0) ≤ capacity from
              ⟨rule, topRule, placedRule, fits⟩)

  | two firstPos firstSize secondPos secondSize =>
      rcases figuresValid with ⟨positions, firstIn, secondIn, onlyTwo⟩
      have beforeFirst := textBeforeFigures firstPos firstIn
      have beforeSecond := textBeforeFigures secondPos secondIn
      cases blank with
      | none =>
          obtain ⟨kept, rule, fits⟩ :=
            I3_one_break_no_blank_two_figures capacity firstTextPos
              firstPos secondPos firstSize secondSize items capacityPositive
              firstText beforeFirst beforeSecond
          refine ⟨kept, false, false, ?_⟩
          simpa [oneBreakPlacement, figureCount, figurePosAt,
            figureSizeAt, blankMaskFor, figureLoad] using
            (show figuresRuleWithLoad 2 capacity 0 kept
              (fun f => textBeforeCount items
                (if f = 0 then firstPos else secondPos) ≤ 1)
              (fun f => textBeforeCount items
                (if f = 0 then firstPos else secondPos))
              (fun f => if f = 0 then firstSize else secondSize)
              (fun _ => false) ∧
              1 + (if kept 0 then firstSize else 0) +
                (if kept 1 then secondSize else 0) ≤ capacity from
              ⟨rule, fits⟩)
      | some blankPos =>
          rcases blankValid with ⟨blankIn, _⟩
          have different : blankPos ≠ firstTextPos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.text firstTextPos) blankIn firstText
              (by simp [sourcePos, samePos])
            cases sameItem
          have blankFirstDifferent : blankPos ≠ firstPos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.figure firstPos) blankIn firstIn
              (by simp [sourcePos, samePos])
            cases sameItem
          have blankSecondDifferent : blankPos ≠ secondPos := by
            intro samePos
            have sameItem := I3_sourceOrdered_unique_position items ordered
              (.blank blankPos) (.figure secondPos) blankIn secondIn
              (by simp [sourcePos, samePos])
            cases sameItem
          let caseProof :=
            if before : blankPos < firstTextPos then
              I3_one_break_blank_before_text_two_figures capacity
                blankPos firstTextPos firstPos secondPos firstSize secondSize
                items capacityPositive firstText first before beforeFirst
                beforeSecond
            else
              I3_one_break_blank_after_text_two_figures capacity
                firstTextPos blankPos firstPos secondPos firstSize secondSize
                items capacityPositive firstText first (by omega) beforeFirst
                beforeSecond positions blankFirstDifferent blankSecondDifferent
                firstIn secondIn onlyTwo
          obtain ⟨kept, top, placed, rule, topRule, placedRule, fits⟩ := caseProof
          refine ⟨kept, top, placed, ?_⟩
          simpa [oneBreakPlacement, figureCount, figurePosAt,
            figureSizeAt, blankMaskFor, figureLoad,
            figureKeptAtPos, figureWaitingAtPos] using
            (show figuresRuleWithLoad 2 capacity 0 kept
              (fun f => textBeforeCount items
                (if f = 0 then firstPos else secondPos) ≤ 1)
              (fun f => textBeforeCount items
                (if f = 0 then firstPos else secondPos))
              (fun f => if f = 0 then firstSize else secondSize)
              (fun f => !beforeBlankMask firstPos secondPos blankPos f && !top) ∧
              top = blankAtTopSource 0 blankPos items
                (textHereAtBreak items 1)
                (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
              placed = blankPlacedFromSourceFull 0 blankPos
                (waitingAtTwoPositions firstPos secondPos kept) items
                (textHereAtBreak items 1)
                (keptAtTwoPositions firstPos secondPos (kept 0) (kept 1)) ∧
              1 + (if kept 0 then firstSize else 0) +
                (if kept 1 then secondSize else 0) +
                (if placed then 1 else 0) ≤ capacity from
              ⟨rule, topRule, placedRule, fits⟩)

theorem I3_one_break_new_and_old_blank_rules_exist
    (capacity firstTextPos : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (capacityPositive : 1 ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (textBeforeFigures : ∀ pos, .figure pos ∈ items → firstTextPos < pos) :
    ∃ kept : Nat → Bool, ∃ atTop newPlaced oldPlaced : Bool,
      oneBreakPlacement capacity items config blank kept atTop newPlaced ∧
      oneBreakPlacement25 capacity items config blank kept atTop oldPlaced := by
  obtain ⟨kept, atTop, newPlaced, newRule⟩ :=
    I3_blankFigureOrder_one_break capacity firstTextPos items config blank
      capacityPositive ordered figuresValid blankValid firstText first
      textBeforeFigures
  obtain ⟨oldPlaced, oldRule⟩ :=
    I3_one_break_old_blank_rule_projection capacity items config blank
      kept atTop newPlaced figuresValid newRule
  exact ⟨kept, atTop, newPlaced, oldPlaced, newRule, oldRule⟩

theorem I3_first_figure_stays_one_figure
    (capacity figurePos figureSize : Nat) (items : List SourceItem)
    (blank : Option Nat)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items (.one figurePos figureSize))
    (blankValid : blankDomain items blank)
    (noEarlierText : ∀ textPos, .text textPos ∈ items →
      figurePos ≤ textPos)
    (fits : figureSize ≤ capacity) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      zeroBreakPlacement capacity 0 items (.one figurePos figureSize)
        blank kept atTop placed ∧ kept 0 = true := by
  obtain ⟨kept, atTop, placed, placement⟩ :=
    blankFigureOrder capacity 0 items (.one figurePos figureSize) blank
      (Nat.zero_le capacity) ordered figuresValid blankValid
  refine ⟨kept, atTop, placed, placement, ?_⟩
  cases blank with
  | none =>
      exact I3_empty_column_first_figure_kept capacity figurePos figureSize
        items noEarlierText fits kept atTop placed placement
  | some blankPos =>
      rcases figuresValid with ⟨figureIn, _⟩
      rcases blankValid with ⟨blankIn, _⟩
      have different : blankPos ≠ figurePos := by
        intro samePos
        have sameItem := I3_sourceOrdered_unique_position items ordered
          (.blank blankPos) (.figure figurePos) blankIn figureIn
          (by simp [sourcePos, samePos])
        cases sameItem
      exact I3_empty_column_first_figure_with_blank_kept capacity
        figurePos figureSize blankPos items noEarlierText fits different
        kept atTop placed placement

theorem I3_first_figure_stays_two_figures
    (capacity firstPos firstSize secondPos secondSize : Nat)
    (items : List SourceItem) (blank : Option Nat)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items
      (.two firstPos firstSize secondPos secondSize))
    (blankValid : blankDomain items blank)
    (noEarlierText : ∀ textPos, .text textPos ∈ items →
      firstPos ≤ textPos)
    (fits : firstSize ≤ capacity) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      zeroBreakPlacement capacity 0 items
        (.two firstPos firstSize secondPos secondSize)
        blank kept atTop placed ∧ kept 0 = true := by
  obtain ⟨kept, atTop, placed, placement⟩ :=
    blankFigureOrder capacity 0 items
      (.two firstPos firstSize secondPos secondSize) blank
      (Nat.zero_le capacity) ordered figuresValid blankValid
  refine ⟨kept, atTop, placed, placement, ?_⟩
  cases blank with
  | none =>
      exact I3_empty_column_first_of_two_figures_kept capacity
        firstPos firstSize secondPos secondSize items noEarlierText fits
        kept atTop placed placement
  | some blankPos =>
      rcases figuresValid with ⟨positions, firstIn, _, _⟩
      rcases blankValid with ⟨blankIn, _⟩
      have different : blankPos ≠ firstPos := by
        intro samePos
        have sameItem := I3_sourceOrdered_unique_position items ordered
          (.blank blankPos) (.figure firstPos) blankIn firstIn
          (by simp [sourcePos, samePos])
        cases sameItem
      exact I3_empty_column_first_of_two_figures_with_blank_kept
        capacity firstPos firstSize secondPos secondSize blankPos items
        positions noEarlierText fits different kept atTop placed placement

theorem I3_blankRules25_first_text_case
    (capacity firstTextPos : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (capacityPositive : 1 ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (textBeforeFigures : ∀ pos, .figure pos ∈ items → firstTextPos < pos) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      oneBreakPlacement25 capacity items config blank kept atTop placed ∧
      textHereAtBreak items 1 firstTextPos = true := by
  obtain ⟨kept, atTop, _, placed, _, oldRule⟩ :=
    I3_one_break_new_and_old_blank_rules_exist capacity firstTextPos items
      config blank capacityPositive ordered figuresValid blankValid
      firstText first textBeforeFigures
  exact ⟨kept, atTop, placed, oldRule,
    I3_break_one_keeps_first_text items firstTextPos first⟩

theorem I3_old_blank_keeps_first_figure
    (capacity : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (figuresValid : figureDomain items config)
    (newWitness : ∃ kept : Nat → Bool, ∃ atTop newPlaced : Bool,
      zeroBreakPlacement capacity 0 items config blank kept atTop newPlaced ∧
      kept 0 = true) :
    ∃ kept : Nat → Bool, ∃ atTop oldPlaced : Bool,
      zeroBreakPlacement25 capacity 0 items config blank kept atTop oldPlaced ∧
      kept 0 = true := by
  obtain ⟨kept, atTop, newPlaced, newRule, firstKept⟩ := newWitness
  obtain ⟨oldPlaced, oldRule⟩ := I3_old_blank_rule_projection
    capacity 0 items config blank kept atTop newPlaced figuresValid newRule
  exact ⟨kept, atTop, oldPlaced, oldRule, firstKept⟩

theorem I3_blankRules25_first_figure_one_case
    (capacity figurePos figureSize : Nat) (items : List SourceItem)
    (blank : Option Nat)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items (.one figurePos figureSize))
    (blankValid : blankDomain items blank)
    (noEarlierText : ∀ textPos, .text textPos ∈ items →
      figurePos ≤ textPos)
    (fits : figureSize ≤ capacity) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      zeroBreakPlacement25 capacity 0 items (.one figurePos figureSize)
        blank kept atTop placed ∧ kept 0 = true := by
  apply I3_old_blank_keeps_first_figure capacity items
    (.one figurePos figureSize) blank figuresValid
  exact I3_first_figure_stays_one_figure capacity figurePos figureSize
    items blank ordered figuresValid blankValid noEarlierText fits

theorem I3_blankRules25_first_figure_two_case
    (capacity firstPos firstSize secondPos secondSize : Nat)
    (items : List SourceItem) (blank : Option Nat)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items
      (.two firstPos firstSize secondPos secondSize))
    (blankValid : blankDomain items blank)
    (noEarlierText : ∀ textPos, .text textPos ∈ items →
      firstPos ≤ textPos)
    (fits : firstSize ≤ capacity) :
    ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      zeroBreakPlacement25 capacity 0 items
        (.two firstPos firstSize secondPos secondSize)
        blank kept atTop placed ∧ kept 0 = true := by
  apply I3_old_blank_keeps_first_figure capacity items
    (.two firstPos firstSize secondPos secondSize) blank figuresValid
  exact I3_first_figure_stays_two_figures capacity firstPos firstSize
    secondPos secondSize items blank ordered figuresValid blankValid
    noEarlierText fits

theorem I3_one_break_ready_implies_text_order
    (items : List SourceItem) (firstTextPos figurePos : Nat)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (beforeFigure : firstTextPos < figurePos)
    (ready : textBeforeCount items figurePos ≤ 1) :
    ∀ textPos, .text textPos ∈ items → textPos < figurePos →
      textHereAtBreak items 1 textPos = true := by
  intro textPos member earlier
  let prior := items.filter (earlierTextItem figurePos)
  have firstHit : .text firstTextPos ∈ prior :=
    List.mem_filter.mpr ⟨firstText,
      by simp [earlierTextItem, beforeFigure]⟩
  have currentHit : .text textPos ∈ prior :=
    List.mem_filter.mpr ⟨member,
      by simp [earlierTextItem, earlier]⟩
  have same : textPos = firstTextPos := by
    cases h : prior with
    | nil => simp [h] at firstHit
    | cons head tail =>
        cases tail with
        | nil =>
            simp [h] at firstHit currentHit
            cases firstHit
            cases currentHit
            rfl
        | cons second rest =>
            have lengthBound : prior.length ≤ 1 := by
              simpa [prior, textBeforeCount] using ready
            simp [h] at lengthBound
            omega
  subst textPos
  exact I3_break_one_keeps_first_text items firstTextPos first

theorem I3_unique_earlier_text_count_le_one
    (items : List SourceItem) (ordered : sourceOrdered items)
    (figurePos firstTextPos : Nat)
    (unique : ∀ textPos, .text textPos ∈ items →
      textPos < figurePos → textPos = firstTextPos) :
    textBeforeCount items figurePos ≤ 1 := by
  induction items with
  | nil => simp [textBeforeCount]
  | cons head rest ih =>
      rcases ordered with ⟨headBefore, restOrdered⟩
      have uniqueRest : ∀ textPos, .text textPos ∈ rest →
          textPos < figurePos → textPos = firstTextPos := by
        intro textPos member earlier
        exact unique textPos (List.mem_cons_of_mem head member) earlier
      cases head with
      | text headPos =>
          by_cases earlier : headPos < figurePos
          · have headEq : headPos = firstTextPos :=
              unique headPos (by simp) earlier
            have noEarlierRest : ∀ item ∈ rest,
                earlierTextItem figurePos item = false := by
              intro item member
              cases item with
              | text textPos =>
                  by_cases later : textPos < figurePos
                  · have textEq := uniqueRest textPos member later
                    have sourceBefore := headBefore (.text textPos) member
                    simp [sourcePos, headEq, textEq] at sourceBefore
                  · simp [earlierTextItem, later]
              | figure _ => rfl
              | blank _ => rfl
              | need _ => rfl
            have emptyFilter : rest.filter (earlierTextItem figurePos) = [] :=
              List.filter_eq_nil.mpr (by
                intro item member hit
                simp [noEarlierRest item member] at hit)
            simp [textBeforeCount, earlierTextItem, earlier, emptyFilter]
          · have restBound := ih restOrdered uniqueRest
            simpa [textBeforeCount, earlierTextItem, earlier] using restBound
      | figure _ =>
          have restBound := ih restOrdered uniqueRest
          simpa [textBeforeCount, earlierTextItem] using restBound
      | blank _ =>
          have restBound := ih restOrdered uniqueRest
          simpa [textBeforeCount, earlierTextItem] using restBound
      | need _ =>
          have restBound := ih restOrdered uniqueRest
          simpa [textBeforeCount, earlierTextItem] using restBound

theorem I3_one_break_ready_iff_text_order
    (items : List SourceItem) (ordered : sourceOrdered items)
    (firstTextPos figurePos : Nat)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (beforeFigure : firstTextPos < figurePos) :
    textBeforeCount items figurePos ≤ 1 ↔
      ∀ textPos, .text textPos ∈ items → textPos < figurePos →
        textHereAtBreak items 1 textPos = true := by
  constructor
  · exact I3_one_break_ready_implies_text_order items firstTextPos
      figurePos firstText first beforeFigure
  · intro allHere
    apply I3_unique_earlier_text_count_le_one items ordered
      figurePos firstTextPos
    intro textPos member earlier
    have here := allHere textPos member earlier
    have noEarlier := (I3_break_one_text_iff_first items textPos).mp here
      firstTextPos firstText
    have firstBefore := first textPos member
    omega

theorem I3_figurePosAt_in_domain
    (items : List SourceItem) (config : FigureConfig)
    (valid : figureDomain items config)
    (f : Nat) (bound : f < figureCount config) :
    .figure (figurePosAt config f) ∈ items := by
  cases config with
  | zero => exact False.elim (Nat.not_lt_zero f bound)
  | one pos size =>
      have first : f = 0 := by
        simp [figureCount] at bound
        omega
      subst f
      exact valid.1
  | two firstPos firstSize secondPos secondSize =>
      rcases valid with ⟨_, firstIn, secondIn, _⟩
      by_cases first : f = 0
      · simpa [figurePosAt, first] using firstIn
      · have second : f = 1 := by
          simp [figureCount] at bound
          omega
        simpa [figurePosAt, first, second] using secondIn

theorem I3_one_break_placement_implies_text_order
    (capacity firstTextPos : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool)
    (figuresValid : figureDomain items config)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (textBeforeFigures : ∀ pos, .figure pos ∈ items → firstTextPos < pos)
    (placement : oneBreakPlacement capacity items config blank
      kept atTop placed) :
    ∀ f, f < figureCount config → kept f = true →
      ∀ textPos, .text textPos ∈ items →
        textPos < figurePosAt config f →
          textHereAtBreak items 1 textPos = true := by
  intro f bound present textPos member earlier
  have figureIn := I3_figurePosAt_in_domain items config
    figuresValid f bound
  have beforeFigure := textBeforeFigures (figurePosAt config f) figureIn
  have figureRule := placement.1 f bound
  have ready : textBeforeCount items (figurePosAt config f) ≤ 1 :=
    (figureRule.mp present).1
  exact I3_one_break_ready_implies_text_order items firstTextPos
    (figurePosAt config f) firstText first beforeFigure ready
    textPos member earlier

theorem I3_firstContent_text_before_figures
    (items : List SourceItem) (ordered : sourceOrdered items)
    (firstTextPos : Nat)
    (first : firstContent items = some (.text firstTextPos)) :
    .text firstTextPos ∈ items ∧
      (∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos) ∧
      (∀ figurePos, .figure figurePos ∈ items →
        firstTextPos < figurePos) := by
  obtain ⟨_, member, minimum⟩ := I3_firstContent_is_earliest
    items ordered (.text firstTextPos) first
  refine ⟨member, ?_, ?_⟩
  · intro textPos textIn
    have le := minimum (.text textPos) textIn (by simp [isContent])
    simpa [sourcePos] using le
  · intro figurePos figureIn
    have le := minimum (.figure figurePos) figureIn (by simp [isContent])
    have different : firstTextPos ≠ figurePos := by
      intro samePos
      have sameItem := I3_sourceOrdered_unique_position items ordered
        (.text firstTextPos) (.figure figurePos) member figureIn
        (by simp [sourcePos, samePos])
      cases sameItem
    simp [sourcePos] at le
    omega

theorem I3_firstContent_figure_before_text
    (items : List SourceItem) (ordered : sourceOrdered items)
    (figurePos : Nat)
    (first : firstContent items = some (.figure figurePos)) :
    .figure figurePos ∈ items ∧
      (∀ textPos, .text textPos ∈ items → figurePos ≤ textPos) ∧
      (∀ otherPos, .figure otherPos ∈ items →
        figurePos ≤ otherPos) := by
  obtain ⟨_, member, minimum⟩ := I3_firstContent_is_earliest
    items ordered (.figure figurePos) first
  refine ⟨member, ?_, ?_⟩
  · intro textPos textIn
    have le := minimum (.text textPos) textIn (by simp [isContent])
    simpa [sourcePos] using le
  · intro otherPos figureIn
    have le := minimum (.figure otherPos) figureIn (by simp [isContent])
    simpa [sourcePos] using le

theorem I3_firstContent_figure_matches_config
    (items : List SourceItem) (ordered : sourceOrdered items)
    (config : FigureConfig) (valid : figureDomain items config)
    (figurePos : Nat)
    (first : firstContent items = some (.figure figurePos)) :
    0 < figureCount config ∧ figurePosAt config 0 = figurePos := by
  obtain ⟨firstIn, _, firstBeforeFigures⟩ :=
    I3_firstContent_figure_before_text items ordered figurePos first
  cases config with
  | zero =>
      have absent := valid figurePos
      exact False.elim (absent firstIn)
  | one pos size =>
      have same := valid.2 figurePos firstIn
      simp [figureCount, figurePosAt, same]
  | two firstPos firstSize secondPos secondSize =>
      rcases valid with ⟨positions, firstInConfig, _, onlyTwo⟩
      rcases onlyTwo figurePos firstIn with firstEq | secondEq
      · simp [figureCount, figurePosAt, firstEq]
      · have earlier := firstBeforeFigures firstPos firstInConfig
        omega

theorem I3_first_content_text_starts_column
    (items : List SourceItem) (ordered : sourceOrdered items)
    (config : FigureConfig) (kept : Nat → Bool)
    (firstTextPos : Nat)
    (first : firstContent items = some (.text firstTextPos)) :
    startsColumnModel 0 1 items config kept firstTextPos := by
  obtain ⟨_, firstTextOrder, textBeforeFigures⟩ :=
    I3_firstContent_text_before_figures items ordered firstTextPos first
  refine ⟨rfl, ?_, ?_⟩
  · intro textPos member earlier
    have later := firstTextOrder textPos member
    exact False.elim (by omega)
  · intro figurePos member earlier
    have later := textBeforeFigures figurePos member
    exact False.elim (by omega)

theorem I3_first_break_here_is_first_text
    (items : List SourceItem) (firstTextPos : Nat)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (textPos : Nat) (member : .text textPos ∈ items)
    (here : textHereAtBreak items 1 textPos = true) :
    textPos = firstTextPos := by
  have beforeFirst := (I3_break_one_text_iff_first items textPos).mp here
    firstTextPos firstText
  have firstBefore := first textPos member
  omega

theorem I3_first_text_break_keeps_paragraphs
    (items : List SourceItem) (ordered : sourceOrdered items)
    (config : FigureConfig) (kept : Nat → Bool)
    (firstTextPos : Nat)
    (first : firstContent items = some (.text firstTextPos))
    (paragraphs : List KeepParagraph)
    (valid : ∀ p ∈ paragraphs, keepParagraphValid items p) :
    keepFirstModel 0 1 items config kept paragraphs ∧
      keepLastModel 0 1 items config kept paragraphs ∧
      keepAllModel 0 1 items config kept paragraphs := by
  obtain ⟨firstText, firstTextOrder, _⟩ :=
    I3_firstContent_text_before_figures items ordered firstTextPos first
  have starts := I3_first_content_text_starts_column items ordered
    config kept firstTextPos first
  have everyHereStarts : ∀ p ∈ paragraphs,
      paragraphHasHere 1 items p →
      startsColumnModel 0 1 items config kept p.firstPos := by
    intro p member ⟨pos, posMember, here⟩
    obtain ⟨firstMember, paragraphPositions⟩ := valid p member
    obtain ⟨textMember, firstBefore⟩ :=
      paragraphPositions pos posMember
    have same := I3_first_break_here_is_first_text items firstTextPos
      firstText firstTextOrder pos textMember here
    have firstTextMember := (paragraphPositions p.firstPos firstMember).1
    have globalBefore := firstTextOrder p.firstPos firstTextMember
    have firstEq : p.firstPos = firstTextPos := by omega
    simpa [firstEq] using starts
  refine ⟨?_, ?_, ?_⟩
  · intro p member broken notStarts
    exact False.elim (notStarts (everyHereStarts p member broken.1))
  · intro p member broken notStarts
    exact False.elim (notStarts (everyHereStarts p member broken.1))
  · intro p member _ broken
    exact everyHereStarts p member broken.1

theorem I3_zero_break_keeps_paragraphs
    (used : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (paragraphs : List KeepParagraph) :
    keepFirstModel used 0 items config kept paragraphs ∧
      keepLastModel used 0 items config kept paragraphs ∧
      keepAllModel used 0 items config kept paragraphs := by
  have neverHere : ∀ p, ¬ paragraphHasHere 0 items p := by
    intro p ⟨pos, _, here⟩
    simp [textHereAtBreak] at here
    omega
  refine ⟨?_, ?_, ?_⟩
  · intro p _ broken _
    exact False.elim (neverHere p broken.1)
  · intro p _ broken _
    exact False.elim (neverHere p broken.1)
  · intro p _ _ broken
    exact False.elim (neverHere p broken.1)

theorem I3_first_text_break_preserves_boundary_rules
    (items : List SourceItem) (ordered : sourceOrdered items)
    (config : FigureConfig) (kept : Nat → Bool)
    (firstTextPos : Nat)
    (first : firstContent items = some (.text firstTextPos))
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    orphanModel 0 1 items config kept paragraphs ∧
      widowModel 0 1 items config kept paragraphs ∧
      headingKeepModel 0 1 items config kept headings keptLines := by
  obtain ⟨firstText, firstTextOrder, _⟩ :=
    I3_firstContent_text_before_figures items ordered firstTextPos first
  have starts := I3_first_content_text_starts_column items ordered
    config kept firstTextPos first
  refine ⟨?_, ?_, ?_⟩
  · intro p member _ here _
    obtain ⟨firstIn, _, _⟩ := paragraphsValid p member
    have same := I3_first_break_here_is_first_text items firstTextPos
      firstText firstTextOrder p.firstPos firstIn here
    simpa [same] using starts
  · intro p member _ here _
    obtain ⟨firstIn, beforeLastIn, firstBeforeLast⟩ :=
      paragraphsValid p member
    have beforeLastEq := I3_first_break_here_is_first_text items
      firstTextPos firstText firstTextOrder p.beforeLastPos beforeLastIn here
    have firstAfter := firstTextOrder p.firstPos firstIn
    have firstEq : p.firstPos = firstTextPos := by omega
    simpa [firstEq] using starts
  · intro h member here notStarts
    have headingIn := headingsValid h member
    have same := I3_first_break_here_is_first_text items firstTextPos
      firstText firstTextOrder h headingIn here
    exact False.elim (notStarts (by simpa [same] using starts))

theorem I3_zero_break_preserves_boundary_rules
    (used : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (paragraphs : List ParagraphBoundary)
    (headings : List Nat) (keptLines : Nat → Prop) :
    orphanModel used 0 items config kept paragraphs ∧
      widowModel used 0 items config kept paragraphs ∧
      headingKeepModel used 0 items config kept headings keptLines := by
  refine ⟨?_, ?_, ?_⟩
  · intro p _ _ here _
    simp [textHereAtBreak] at here
    omega
  · intro p _ _ here _
    simp [textHereAtBreak] at here
    omega
  · intro h _ here _
    simp [textHereAtBreak] at here
    omega

theorem I3_zero_break_preserves_recto
    (used : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool)
    (rectos : List Nat) :
    rectoModel used 0 items config kept rectos := by
  intro r _ here
  simp [textHereAtBreak] at here
  omega

theorem I3_first_text_break_preserves_recto
    (items : List SourceItem) (ordered : sourceOrdered items)
    (config : FigureConfig) (kept : Nat → Bool)
    (firstTextPos : Nat)
    (first : firstContent items = some (.text firstTextPos))
    (rectos : List Nat)
    (rectosValid : ∀ r ∈ rectos, .text r ∈ items) :
    rectoModel 0 1 items config kept rectos := by
  obtain ⟨firstText, firstTextOrder, _⟩ :=
    I3_firstContent_text_before_figures items ordered firstTextPos first
  have starts := I3_first_content_text_starts_column items ordered
    config kept firstTextPos first
  intro r member here
  have same := I3_first_break_here_is_first_text items firstTextPos
    firstText firstTextOrder r (rectosValid r member) here
  simpa [same] using starts

theorem I3_zeroBreakPlacement25_implies_orders
    (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool)
    (placement : zeroBreakPlacement25 capacity used items config blank
      kept atTop placed) :
    figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ pos, .text pos ∈ items → pos < figurePosAt config f → False) := by
  constructor
  · exact I3_figuresRule_implies_figuresInOrder _ _ _ _ placement.1
  · intro f bound present pos member earlier
    have figureRule := placement.1 f bound
    have ready : textReadyZero items (figurePosAt config f) = true :=
      (figureRule.mp present).1
    have later := (I3_textReadyZero_iff_no_earlier_text items
      (figurePosAt config f)).mp ready pos member
    omega

theorem I3_oneBreakPlacement25_implies_orders
    (capacity firstTextPos : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (kept : Nat → Bool) (atTop placed : Bool)
    (figuresValid : figureDomain items config)
    (firstText : .text firstTextPos ∈ items)
    (first : ∀ textPos, .text textPos ∈ items → firstTextPos ≤ textPos)
    (textBeforeFigures : ∀ pos, .figure pos ∈ items → firstTextPos < pos)
    (placement : oneBreakPlacement25 capacity items config blank
      kept atTop placed) :
    figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ textPos, .text textPos ∈ items →
          textPos < figurePosAt config f →
            textHereAtBreak items 1 textPos = true) := by
  constructor
  · exact I3_figuresRule_implies_figuresInOrder _ _ _ _ placement.1
  · intro f bound present textPos member earlier
    have figureIn := I3_figurePosAt_in_domain items config
      figuresValid f bound
    have beforeFigure := textBeforeFigures (figurePosAt config f) figureIn
    have figureRule := placement.1 f bound
    have ready : textBeforeCount items (figurePosAt config f) ≤ 1 :=
      (figureRule.mp present).1
    exact I3_one_break_ready_implies_text_order items firstTextPos
      (figurePosAt config f) firstText first beforeFigure ready
      textPos member earlier

theorem blankRules25 (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank)
    (sizesFit : figureSizesFit capacity config) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config blank
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        blank kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      (brk = 1 → ∃ firstTextPos,
        firstContent items = some (.text firstTextPos)) ∧
      figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ textPos, .text textPos ∈ items →
          textPos < figurePosAt config f →
            textHereAtBreak items brk textPos = true) := by
  by_cases emptyColumn : used = 0
  · subst used
    cases firstCase : firstContent items with
    | none =>
        obtain ⟨kept, atTop, _, oldPlaced, _, oldRule, _, _⟩ :=
          I3_blankFigureOrder_old_blank_projection capacity 0 items
            config blank (Nat.zero_le capacity) ordered figuresValid blankValid
        obtain ⟨figureOrder, textOrder⟩ :=
          I3_zeroBreakPlacement25_implies_orders capacity 0 items
            config blank kept atTop oldPlaced oldRule
        refine ⟨0, kept, atTop, oldPlaced, Or.inl ⟨rfl, oldRule⟩, ?_,
          ?_, figureOrder, ?_⟩
        · simp [firstContentNotSent, firstCase]
        · intro impossible
          cases impossible
        · intro f bound present textPos member earlier
          exact False.elim (textOrder f bound present textPos member earlier)
    | some item =>
        cases item with
        | text firstTextPos =>
            obtain ⟨firstText, firstTextOrder, textBeforeFigures⟩ :=
              I3_firstContent_text_before_figures items ordered
                firstTextPos firstCase
            obtain ⟨kept, atTop, oldPlaced, oldRule, _⟩ :=
              I3_blankRules25_first_text_case capacity firstTextPos items
                config blank capacityPositive ordered figuresValid blankValid
                firstText firstTextOrder textBeforeFigures
            obtain ⟨figureOrder, textOrder⟩ :=
              I3_oneBreakPlacement25_implies_orders capacity firstTextPos
                items config blank kept atTop oldPlaced figuresValid
                firstText firstTextOrder textBeforeFigures oldRule
            refine ⟨1, kept, atTop, oldPlaced,
              Or.inr ⟨rfl, rfl, oldRule⟩, ?_, ?_, figureOrder, textOrder⟩
            · simp [firstContentNotSent, firstCase]
            · intro _
              exact ⟨firstTextPos, rfl⟩
        | figure firstFigurePos =>
            obtain ⟨figureIn, noEarlierText, _⟩ :=
              I3_firstContent_figure_before_text items ordered
                firstFigurePos firstCase
            cases config with
            | zero =>
                exact False.elim (figuresValid firstFigurePos figureIn)
            | one figurePos figureSize =>
                have same : firstFigurePos = figurePos :=
                  figuresValid.2 firstFigurePos figureIn
                subst firstFigurePos
                obtain ⟨kept, atTop, oldPlaced, oldRule, firstKept⟩ :=
                  I3_blankRules25_first_figure_one_case capacity figurePos
                    figureSize items blank ordered figuresValid blankValid
                    noEarlierText sizesFit
                obtain ⟨figureOrder, textOrder⟩ :=
                  I3_zeroBreakPlacement25_implies_orders capacity 0 items
                    (.one figurePos figureSize) blank kept atTop oldPlaced oldRule
                refine ⟨0, kept, atTop, oldPlaced,
                  Or.inl ⟨rfl, oldRule⟩, ?_, ?_, figureOrder, ?_⟩
                · intro _ item eq
                  rw [firstCase] at eq
                  cases eq
                  simpa [figureKeptAtPos, keptAtTwoPositions] using firstKept
                · intro impossible
                  cases impossible
                · intro f bound present textPos member earlier
                  exact False.elim (textOrder f bound present textPos member earlier)
            | two firstPos firstSize secondPos secondSize =>
                have same :=
                  (I3_firstContent_figure_matches_config items ordered
                    (.two firstPos firstSize secondPos secondSize) figuresValid
                    firstFigurePos firstCase).2
                simp [figurePosAt] at same
                subst firstFigurePos
                obtain ⟨kept, atTop, oldPlaced, oldRule, firstKept⟩ :=
                  I3_blankRules25_first_figure_two_case capacity firstPos
                    firstSize secondPos secondSize items blank ordered
                    figuresValid blankValid noEarlierText sizesFit.1
                obtain ⟨figureOrder, textOrder⟩ :=
                  I3_zeroBreakPlacement25_implies_orders capacity 0 items
                    (.two firstPos firstSize secondPos secondSize)
                    blank kept atTop oldPlaced oldRule
                refine ⟨0, kept, atTop, oldPlaced,
                  Or.inl ⟨rfl, oldRule⟩, ?_, ?_, figureOrder, ?_⟩
                · intro _ item eq
                  rw [firstCase] at eq
                  cases eq
                  simpa [figureKeptAtPos, keptAtTwoPositions] using firstKept
                · intro impossible
                  cases impossible
                · intro f bound present textPos member earlier
                  exact False.elim (textOrder f bound present textPos member earlier)
        | blank pos =>
            have content := (I3_firstContent_is_earliest items ordered
              (.blank pos) firstCase).1
            simp [isContent] at content
        | need pos =>
            have content := (I3_firstContent_is_earliest items ordered
              (.need pos) firstCase).1
            simp [isContent] at content
  · obtain ⟨kept, atTop, _, oldPlaced, _, oldRule, _, _⟩ :=
      I3_blankFigureOrder_old_blank_projection capacity used items
        config blank usedFits ordered figuresValid blankValid
    obtain ⟨figureOrder, textOrder⟩ :=
      I3_zeroBreakPlacement25_implies_orders capacity used items
        config blank kept atTop oldPlaced oldRule
    refine ⟨0, kept, atTop, oldPlaced, Or.inl ⟨rfl, oldRule⟩, ?_,
      ?_, figureOrder, ?_⟩
    · intro empty
      exact False.elim (emptyColumn empty)
    · intro impossible
      cases impossible
    · intro f bound present textPos member earlier
      exact False.elim (textOrder f bound present textPos member earlier)

/- Current blank-line rule, which skips a waiting figure when looking for
   the next block.  Unlike `blankRules25`, this keeps the new placement
   predicate rather than projecting it to the historical one. -/
theorem waitingBlankNone (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank)
    (sizesFit : figureSizesFit capacity config) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement capacity used items config blank
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement capacity items config
        blank kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      (brk = 1 → ∃ firstTextPos,
        firstContent items = some (.text firstTextPos)) := by
  by_cases emptyColumn : used = 0
  · subst used
    cases firstCase : firstContent items with
    | none =>
        obtain ⟨kept, atTop, placed, rule⟩ :=
          blankFigureOrder capacity 0 items config blank
            (Nat.zero_le capacity) ordered figuresValid blankValid
        refine ⟨0, kept, atTop, placed, Or.inl ⟨rfl, rule⟩,
          by simp [firstContentNotSent, firstCase], ?_⟩
        intro impossible
        cases impossible
    | some item =>
        cases item with
        | text firstTextPos =>
            obtain ⟨firstText, firstTextOrder, textBeforeFigures⟩ :=
              I3_firstContent_text_before_figures items ordered
                firstTextPos firstCase
            obtain ⟨kept, atTop, placed, rule⟩ :=
              I3_blankFigureOrder_one_break capacity firstTextPos items
                config blank capacityPositive ordered figuresValid
                blankValid firstText firstTextOrder textBeforeFigures
            refine ⟨1, kept, atTop, placed,
              Or.inr ⟨rfl, rfl, rule⟩,
              by simp [firstContentNotSent, firstCase], ?_⟩
            intro _
            exact ⟨firstTextPos, rfl⟩
        | figure firstFigurePos =>
            obtain ⟨figureIn, noEarlierText, _⟩ :=
              I3_firstContent_figure_before_text items ordered
                firstFigurePos firstCase
            cases config with
            | zero =>
                exact False.elim (figuresValid firstFigurePos figureIn)
            | one figurePos figureSize =>
                have same : firstFigurePos = figurePos :=
                  figuresValid.2 firstFigurePos figureIn
                subst firstFigurePos
                obtain ⟨kept, atTop, placed, rule, firstKept⟩ :=
                  I3_first_figure_stays_one_figure capacity figurePos
                    figureSize items blank ordered figuresValid blankValid
                    noEarlierText sizesFit
                refine ⟨0, kept, atTop, placed,
                  Or.inl ⟨rfl, rule⟩, ?_, ?_⟩
                · intro _ item eq
                  rw [firstCase] at eq
                  cases eq
                  simpa [figureKeptAtPos, keptAtTwoPositions] using firstKept
                · intro impossible
                  cases impossible
            | two firstPos firstSize secondPos secondSize =>
                have same :=
                  (I3_firstContent_figure_matches_config items ordered
                    (.two firstPos firstSize secondPos secondSize)
                    figuresValid firstFigurePos firstCase).2
                simp [figurePosAt] at same
                subst firstFigurePos
                obtain ⟨kept, atTop, placed, rule, firstKept⟩ :=
                  I3_first_figure_stays_two_figures capacity firstPos
                    firstSize secondPos secondSize items blank ordered
                    figuresValid blankValid noEarlierText sizesFit.1
                refine ⟨0, kept, atTop, placed,
                  Or.inl ⟨rfl, rule⟩, ?_, ?_⟩
                · intro _ item eq
                  rw [firstCase] at eq
                  cases eq
                  simpa [figureKeptAtPos, keptAtTwoPositions] using firstKept
                · intro impossible
                  cases impossible
        | blank pos =>
            have content := (I3_firstContent_is_earliest items ordered
              (.blank pos) firstCase).1
            simp [isContent] at content
        | need pos =>
            have content := (I3_firstContent_is_earliest items ordered
              (.need pos) firstCase).1
            simp [isContent] at content
  · obtain ⟨kept, atTop, placed, rule⟩ :=
      blankFigureOrder capacity used items config blank usedFits ordered
        figuresValid blankValid
    refine ⟨0, kept, atTop, placed, Or.inl ⟨rfl, rule⟩, ?_, ?_⟩
    · intro empty
      exact False.elim (emptyColumn empty)
    · intro impossible
      cases impossible

theorem waitingBlankAllButGreedy (capacity used : Nat)
    (items : List SourceItem) (config : FigureConfig)
    (blank : Option Nat)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement capacity used items config blank
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement capacity items config
        blank kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ textPos, .text textPos ∈ items →
          textPos < figurePosAt config f →
            textHereAtBreak items brk textPos = true) ∧
      orphanModel used brk items config kept paragraphs ∧
      widowModel used brk items config kept paragraphs ∧
      headingKeepModel used brk items config kept headings keptLines := by
  obtain ⟨brk, kept, atTop, placed, rule, noSend, firstCase⟩ :=
    waitingBlankNone capacity used items config blank capacityPositive
      usedFits ordered figuresValid blankValid sizesFit
  rcases rule with ⟨zero, zeroRule⟩ | ⟨one, empty, oneRule⟩
  · subst brk
    have figureOrder := I3_zeroBreakPlacement_implies_figure_order
      capacity used items config blank kept atTop placed zeroRule
    have textOrder := I3_zeroBreakPlacement_implies_text_order
      capacity used items config blank kept atTop placed zeroRule
    obtain ⟨orphan, widow, heading⟩ :=
      I3_zero_break_preserves_boundary_rules used items config kept
        paragraphs headings keptLines
    refine ⟨0, kept, atTop, placed, Or.inl ⟨rfl, zeroRule⟩,
      noSend, figureOrder, ?_, orphan, widow, heading⟩
    intro f bound present textPos member earlier
    exact False.elim (textOrder f bound present textPos member earlier)
  · subst brk
    subst used
    obtain ⟨firstTextPos, firstTextCase⟩ := firstCase rfl
    obtain ⟨firstText, firstTextOrder, textBeforeFigures⟩ :=
      I3_firstContent_text_before_figures items ordered firstTextPos
        firstTextCase
    have figureOrder := I3_figuresRule_implies_figuresInOrder
      _ _ _ _ oneRule.1
    have textOrder := I3_one_break_placement_implies_text_order
      capacity firstTextPos items config blank kept atTop placed
        figuresValid firstText firstTextOrder textBeforeFigures oneRule
    obtain ⟨orphan, widow, heading⟩ :=
      I3_first_text_break_preserves_boundary_rules items ordered
        config kept firstTextPos firstTextCase paragraphs paragraphsValid
        headings headingsValid keptLines
    exact ⟨1, kept, atTop, placed, Or.inr ⟨rfl, rfl, oneRule⟩,
      noSend, figureOrder, textOrder, orphan, widow, heading⟩

theorem I3_recto_compatible_with_blank_and_figure
    (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank)
    (sizesFit : figureSizesFit capacity config)
    (rectos : List Nat)
    (rectosValid : ∀ r ∈ rectos, .text r ∈ items) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement capacity used items config blank
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement capacity items config
        blank kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      rectoModel used brk items config kept rectos := by
  obtain ⟨brk, kept, atTop, placed, rule, noSend, firstCase⟩ :=
    waitingBlankNone capacity used items config blank capacityPositive
      usedFits ordered figuresValid blankValid sizesFit
  rcases rule with ⟨zero, zeroRule⟩ | ⟨one, empty, oneRule⟩
  · subst brk
    exact ⟨0, kept, atTop, placed, Or.inl ⟨rfl, zeroRule⟩,
      noSend, I3_zero_break_preserves_recto used items config kept rectos⟩
  · subst brk
    subst used
    obtain ⟨firstTextPos, firstTextCase⟩ := firstCase rfl
    exact ⟨1, kept, atTop, placed, Or.inr ⟨rfl, rfl, oneRule⟩,
      noSend, I3_first_text_break_preserves_recto items ordered config
        kept firstTextPos firstTextCase rectos rectosValid⟩

def sourceLineAfterHeadings (used brk : Nat) (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool) (headings : List Nat)
    (line : Nat → Prop) : Prop :=
  used = 0 → 1 ≤ brk → (∀ f, f < figureCount config → kept f = false) →
    (∀ t, .text t ∈ items → textHereAtBreak items brk t = true → t ∈ headings) →
      ∀ l, .text l ∈ items → line l → textBeforeCount items l ≠ brk

theorem I3_rank_of_position_at_index (positions : List Nat)
    (ordered : strictTextPositions positions) (i p : Nat)
    (atIndex : positions.get? i = some p) : textRank positions p = i := by
  induction positions generalizing i with
  | nil => simp at atIndex
  | cons first rest ih =>
    obtain ⟨before, sorted⟩ := ordered
    cases i with
    | zero =>
      simp at atIndex
      simp [textRank, atIndex]
    | succ i =>
      simp only [List.get?_cons_succ] at atIndex
      obtain ⟨bound, eq⟩ := List.get?_eq_some.mp atIndex
      have member : p ∈ rest := eq ▸ List.get_mem rest i bound
      have earlier := before p member
      simp [textRank, Nat.ne_of_lt earlier, ih sorted i atIndex, Nat.add_comm]

theorem I3_source_line_after_alloy_first_break
    (items : List SourceItem) (ordered : sourceOrdered items)
    (role : Nat → AlloyTextRole) (config : FigureConfig) (kept : Nat → Bool)
    (headings : List Nat) (line : Nat → Prop)
    (headingRole : ∀ p ∈ headings, role p = .heading)
    (lineRole : ∀ p, line p → role p = .line) :
    let roles := (sourceTextPositions items).map role
    sourceLineAfterHeadings 0 (alloyTextFirstBreak roles) items config kept headings line := by
  let positions := sourceTextPositions items
  let roles := positions.map role
  let brk := alloyTextFirstBreak roles
  change sourceLineAfterHeadings 0 brk items config kept headings line
  intro _ positive _ onlyHeadings p member isLine atBreak
  have sorted := I3_source_text_positions_ordered items ordered
  have pMember := (I3_source_text_position_member items p).mpr member
  have rank : textRank positions p = brk := by
    rw [I3_source_text_before_count,
      I3_count_earlier_text_eq_rank _ sorted p pMember] at atBreak
    exact atBreak
  have after := (I3_alloy_text_first_break_line_after 2 roles (by decide)).2.2
  apply after ⟨positive, ?_⟩
  · have atRole := I3_text_role_at_source_rank items role p member
    change roles.get? brk = some .line
    rw [← rank]
    simpa only [lineRole p isLine] using atRole
  · intro i before
    have brkLe : brk ≤ positions.length := by
      change alloyTextFirstBreak (positions.map role) ≤ positions.length
      cases positions with
      | nil => simp [alloyTextFirstBreak]
      | cons h t =>
        cases t with
        | nil => cases role h <;> simp [alloyTextFirstBreak, *]
        | cons j t => cases hh : role h <;> cases hj : role j <;>
            simp [hh, hj, alloyTextFirstBreak] <;> omega
    have inBounds : i < positions.length := by omega
    let q := positions.get ⟨i, inBounds⟩
    have atQ : positions.get? i = some q := List.get?_eq_get inBounds
    have qMember := List.get_mem positions i inBounds
    have qText := (I3_source_text_position_member items q).mp qMember
    have rankQ := I3_rank_of_position_at_index positions sorted i q atQ
    have here := (I3_text_here_iff_source_rank items ordered q brk qText).mpr
      (by simpa [← rankQ] using before)
    change (positions.map role).get? i = some .heading
    rw [List.get?_map, atQ]
    simp [headingRole q (onlyHeadings q qText here)]

/- At a two-text break the following line is already in the column.
   This discharges the heading-only premise even with figures and a blank. -/
theorem I3_two_break_line_after_headings
    (items : List SourceItem) (config : FigureConfig) (kept : Nat → Bool)
    (headings : List Nat) (line : Nat → Prop) (secondPos : Nat)
    (secondIn : .text secondPos ∈ items)
    (secondRank : textBeforeCount items secondPos = 1)
    (secondNotHeading : secondPos ∉ headings) :
    sourceLineAfterHeadings 0 2 items config kept headings line := by
  intro _ _ _ onlyHeadings
  have placed : textHereAtBreak items 2 secondPos = true := by
    simp [textHereAtBreak, secondRank]
  exact (secondNotHeading (onlyHeadings secondPos secondIn placed)).elim

theorem I3_heading_runs_and_rectos_with_blank_and_figure
    (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig) (blank : Option Nat)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (blankValid : blankDomain items blank)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings rectos : List Nat) (line linesKept : Nat → Prop)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (rectosValid : ∀ r ∈ rectos, .text r ∈ items) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement capacity used items config blank
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement capacity items config
        blank kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ textPos, .text textPos ∈ items → textPos < figurePosAt config f →
          textHereAtBreak items brk textPos = true) ∧
      orphanModel used brk items config kept paragraphs ∧
      widowModel used brk items config kept paragraphs ∧
      ((used ≠ 0 ∨ (∀ l, .text l ∈ items → line l → textBeforeCount items l ≠ 1)) →
        sourceLineAfterHeadings used brk items config kept headings line) ∧
      rectoModel used brk items config kept rectos ∧
      headingRunKeep (fun p => ∃ i ∈ items, sourcePos i = p)
        (fun p => .text p ∈ items) (fun h => h ∈ headings)
        (fun p => textHereAtBreak items brk p = true)
        (startsColumnModel used brk items config kept) line linesKept := by
  have valid : ∀ p ∈ headings ++ rectos, .text p ∈ items := by
    intro p member
    induction headings with
    | nil => exact rectosValid p member
    | cons h hs ih =>
      rcases List.mem_cons.mp member with eq | tail
      · exact headingsValid p (List.mem_cons.mpr (Or.inl eq))
      · exact ih (fun q hq => headingsValid q (List.mem_cons.mpr (Or.inr hq))) tail
  obtain ⟨brk, kept, atTop, placed, rule, noSend, figureOrder, textOrder, orphan, widow, noInterior⟩ :=
    waitingBlankAllButGreedy capacity used items config blank capacityPositive usedFits
      ordered figuresValid blankValid sizesFit paragraphs paragraphsValid
      (headings ++ rectos) valid (fun _ => False)
  refine ⟨brk, kept, atTop, placed, rule, noSend, figureOrder, textOrder, orphan, widow, ?_, ?_, ?_⟩
  · intro domain empty positive _ _ l member isLine
    rcases domain with occupied | second
    · exact (occupied empty).elim
    · rcases rule with ⟨zero, _⟩ | ⟨one, _, _⟩
      · omega
      · simpa [one] using second l member isLine
  · intro r member here
    apply Classical.byContradiction
    exact noInterior r (List.mem_append_of_mem_right headings member) here
  · intro h member here inside
    exact (noInterior h (List.mem_append_of_mem_left rectos member) here inside).elim


theorem figureEmpty (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      firstContentNotSent used brk items config kept := by
  obtain ⟨brk, kept, atTop, placed, rule, noSend, _, _, _⟩ :=
    blankRules25 capacity used items config none capacityPositive usedFits
      ordered figuresValid noBlank sizesFit
  exact ⟨brk, kept, atTop, placed, rule, noSend⟩

theorem figureOrder (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ textPos, .text textPos ∈ items →
          textPos < figurePosAt config f →
            textHereAtBreak items brk textPos = true) := by
  obtain ⟨brk, kept, atTop, placed, rule, _, _, figureOrder, textOrder⟩ :=
    blankRules25 capacity used items config none capacityPositive usedFits
      ordered figuresValid noBlank sizesFit
  exact ⟨brk, kept, atTop, placed, rule, figureOrder, textOrder⟩

theorem keep21 (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ textPos, .text textPos ∈ items →
          textPos < figurePosAt config f →
            textHereAtBreak items brk textPos = true) ∧
      orphanModel used brk items config kept paragraphs ∧
      widowModel used brk items config kept paragraphs ∧
      headingKeepModel used brk items config kept headings keptLines := by
  obtain ⟨brk, kept, atTop, placed, rule, noSend, firstCase,
    figureOrder, textOrder⟩ :=
    blankRules25 capacity used items config none capacityPositive usedFits
      ordered figuresValid noBlank sizesFit
  rcases rule with ⟨zero, zeroRule⟩ | ⟨one, empty, oneRule⟩
  · subst brk
    obtain ⟨orphan, widow, heading⟩ :=
      I3_zero_break_preserves_boundary_rules used items config kept
        paragraphs headings keptLines
    exact ⟨0, kept, atTop, placed, Or.inl ⟨rfl, zeroRule⟩,
      noSend, figureOrder, textOrder, orphan, widow, heading⟩
  · subst brk
    subst used
    obtain ⟨firstTextPos, firstTextCase⟩ := firstCase rfl
    obtain ⟨orphan, widow, heading⟩ :=
      I3_first_text_break_preserves_boundary_rules items ordered
        config kept firstTextPos firstTextCase paragraphs paragraphsValid
        headings headingsValid keptLines
    exact ⟨1, kept, atTop, placed, Or.inr ⟨rfl, rfl, oneRule⟩,
      noSend, figureOrder, textOrder, orphan, widow, heading⟩

/- The historical `keepHeadingEmpty` command searches for an input with no
   joint placement.  `keep21` constructs a stronger joint placement for every
   input in its domain.  The projection below retains the two rules queried
   by that command. -/
theorem keepHeadingEmpty (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      headingKeepModel used brk items config kept headings keptLines := by
  obtain ⟨brk, kept, atTop, placed, rule, noSend, _, _, _, _, heading⟩ :=
    keep21 capacity used items config capacityPositive usedFits ordered
      figuresValid noBlank sizesFit paragraphs paragraphsValid headings
      headingsValid keptLines
  exact ⟨brk, kept, atTop, placed, rule, noSend, heading⟩

theorem keepHeadingFigure (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      headingKeepModel used brk items config kept headings keptLines := by
  obtain ⟨brk, kept, atTop, placed, rule, _, _, _, _, _, heading⟩ :=
    keep21 capacity used items config capacityPositive usedFits ordered
      figuresValid noBlank sizesFit paragraphs paragraphsValid headings
      headingsValid keptLines
  exact ⟨brk, kept, atTop, placed, rule, heading⟩

theorem keepHeadingOrphan (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      orphanModel used brk items config kept paragraphs ∧
      headingKeepModel used brk items config kept headings keptLines := by
  obtain ⟨brk, kept, atTop, placed, rule, _, _, _, orphan, _, heading⟩ :=
    keep21 capacity used items config capacityPositive usedFits ordered
      figuresValid noBlank sizesFit paragraphs paragraphsValid headings
      headingsValid keptLines
  exact ⟨brk, kept, atTop, placed, rule, orphan, heading⟩

theorem keepHeadingWidow (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      widowModel used brk items config kept paragraphs ∧
      headingKeepModel used brk items config kept headings keptLines := by
  obtain ⟨brk, kept, atTop, placed, rule, _, _, _, _, widow, heading⟩ :=
    keep21 capacity used items config capacityPositive usedFits ordered
      figuresValid noBlank sizesFit paragraphs paragraphsValid headings
      headingsValid keptLines
  exact ⟨brk, kept, atTop, placed, rule, widow, heading⟩

theorem orphanEmpty (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      orphanModel used brk items config kept paragraphs := by
  obtain ⟨brk, kept, atTop, placed, rule, noSend, _, _, orphan, _, _⟩ :=
    keep21 capacity used items config capacityPositive usedFits ordered
      figuresValid noBlank sizesFit paragraphs paragraphsValid headings
      headingsValid keptLines
  exact ⟨brk, kept, atTop, placed, rule, noSend, orphan⟩

theorem widowEmpty (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      widowModel used brk items config kept paragraphs := by
  obtain ⟨brk, kept, atTop, placed, rule, noSend, _, _, _, widow, _⟩ :=
    keep21 capacity used items config capacityPositive usedFits ordered
      figuresValid noBlank sizesFit paragraphs paragraphsValid headings
      headingsValid keptLines
  exact ⟨brk, kept, atTop, placed, rule, noSend, widow⟩

theorem orphanWidow (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      orphanModel used brk items config kept paragraphs ∧
      widowModel used brk items config kept paragraphs := by
  obtain ⟨brk, kept, atTop, placed, rule, _, _, _, orphan, widow, _⟩ :=
    keep21 capacity used items config capacityPositive usedFits ordered
      figuresValid noBlank sizesFit paragraphs paragraphsValid headings
      headingsValid keptLines
  exact ⟨brk, kept, atTop, placed, rule, orphan, widow⟩

/- The command omits greedy filling; the same placement proves every
   remaining boundary rule in the modeled inDomain inputs. -/
theorem noneMeetsAllButGreedy (capacity used : Nat)
    (items : List SourceItem) (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List ParagraphBoundary)
    (paragraphsValid : ∀ p ∈ paragraphs, paragraphBoundaryValid items p)
    (headings : List Nat)
    (headingsValid : ∀ h ∈ headings, .text h ∈ items)
    (keptLines : Nat → Prop) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      figuresInOrder (figureCount config) kept ∧
      (∀ f, f < figureCount config → kept f = true →
        ∀ textPos, .text textPos ∈ items →
          textPos < figurePosAt config f →
            textHereAtBreak items brk textPos = true) ∧
      orphanModel used brk items config kept paragraphs ∧
      widowModel used brk items config kept paragraphs ∧
      headingKeepModel used brk items config kept headings keptLines := by
  exact keep21 capacity used items config capacityPositive usedFits ordered
    figuresValid noBlank sizesFit paragraphs paragraphsValid headings
    headingsValid keptLines

/- This proves the keep-option command for any first/last bounds and
   keep-all flags once paragraph positions agree with the ordered source. -/
theorem keepNone (capacity used : Nat) (items : List SourceItem)
    (config : FigureConfig)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity)
    (ordered : sourceOrdered items)
    (figuresValid : figureDomain items config)
    (noBlank : blankDomain items none)
    (sizesFit : figureSizesFit capacity config)
    (paragraphs : List KeepParagraph)
    (valid : ∀ p ∈ paragraphs, keepParagraphValid items p) :
    ∃ brk : Nat, ∃ kept : Nat → Bool, ∃ atTop placed : Bool,
      ((brk = 0 ∧ zeroBreakPlacement25 capacity used items config none
        kept atTop placed) ∨
       (brk = 1 ∧ used = 0 ∧ oneBreakPlacement25 capacity items config
        none kept atTop placed)) ∧
      firstContentNotSent used brk items config kept ∧
      keepFirstModel used brk items config kept paragraphs ∧
      keepLastModel used brk items config kept paragraphs ∧
      keepAllModel used brk items config kept paragraphs := by
  obtain ⟨brk, kept, atTop, placed, rule, noSend, firstCase, _, _⟩ :=
    blankRules25 capacity used items config none capacityPositive usedFits
      ordered figuresValid noBlank sizesFit
  rcases rule with ⟨zero, zeroRule⟩ | ⟨one, empty, oneRule⟩
  · subst brk
    obtain ⟨firstRule, lastRule, allRule⟩ :=
      I3_zero_break_keeps_paragraphs used items config kept paragraphs
    exact ⟨0, kept, atTop, placed, Or.inl ⟨rfl, zeroRule⟩,
      noSend, firstRule, lastRule, allRule⟩
  · subst brk
    subst used
    obtain ⟨firstTextPos, firstTextCase⟩ := firstCase rfl
    obtain ⟨firstRule, lastRule, allRule⟩ :=
      I3_first_text_break_keeps_paragraphs items ordered config kept
        firstTextPos firstTextCase paragraphs valid
    exact ⟨1, kept, atTop, placed, Or.inr ⟨rfl, rfl, oneRule⟩,
      noSend, firstRule, lastRule, allRule⟩

theorem I3_textReadyAtZeroBreak_iff_no_earlier_text
    (textPositions : List Nat) (figurePos : Nat) :
    textReadyAtZeroBreak textPositions figurePos ↔
      ∀ t ∈ textPositions, t < figurePos → False := by
  unfold textReadyAtZeroBreak
  constructor
  · intro ready t member earlier
    have later := ready t member
    omega
  · intro noEarlier t member
    by_cases later : figurePos ≤ t
    · exact later
    · have earlier : t < figurePos := by omega
      exact False.elim (noEarlier t member earlier)

theorem I3_textReadyAtZeroBreak_before (textPositions : List Nat)
    (firstPos secondPos : Nat) (before : firstPos < secondPos)
    (secondReady : textReadyAtZeroBreak textPositions secondPos) :
    textReadyAtZeroBreak textPositions firstPos := by
  intro t member
  have later := secondReady t member
  omega

theorem blankFigureOrder_twoFiguresBeforeBlank_withText
    (capacity used firstSize secondSize : Nat)
    (firstReady secondReady : Bool) (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (firstReady = true ∧ used + firstSize ≤ capacity) ∧
      second = decide (secondReady = true ∧ first = true ∧
        used + firstSize + secondSize ≤ capacity) ∧
      placed = false ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  by_cases firstFits : firstReady = true ∧ used + firstSize ≤ capacity
  · by_cases secondFits : secondReady = true ∧ used + firstSize + secondSize ≤ capacity
    · refine ⟨true, true, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits, secondFits] <;> omega
    · refine ⟨true, false, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits, secondFits] <;> omega
  · refine ⟨false, false, false, ?_, ?_, ?_, ?_⟩
    all_goals simp [firstFits] <;> omega

theorem blankFigureOrder_twoFiguresAroundBlank_withText
    (capacity used firstSize secondSize : Nat)
    (firstReady secondReady : Bool) (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (firstReady = true ∧ used + firstSize ≤ capacity) ∧
      second = decide (secondReady = true ∧ first = true ∧
        used + firstSize + 1 + secondSize ≤ capacity) ∧
      placed = second ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  by_cases firstFits : firstReady = true ∧ used + firstSize ≤ capacity
  · by_cases secondFits : secondReady = true ∧ used + firstSize + 1 + secondSize ≤ capacity
    · refine ⟨true, true, true, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits, secondFits] <;> omega
    · refine ⟨true, false, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits, secondFits] <;> omega
  · refine ⟨false, false, false, ?_, ?_, ?_, ?_⟩
    all_goals simp [firstFits] <;> omega

theorem blankFigureOrder_twoFiguresAfterBlank_withText
    (capacity used firstSize secondSize : Nat)
    (firstReady secondReady : Bool) (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (firstReady = true ∧
        used + (if used = 0 then 0 else 1) + firstSize ≤ capacity) ∧
      second = decide (secondReady = true ∧ first = true ∧
        used + (if used = 0 then 0 else 1) + firstSize + secondSize ≤ capacity) ∧
      placed = decide (first = true ∧ used ≠ 0) ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  by_cases top : used = 0
  · subst used
    by_cases firstFits : firstReady = true ∧ firstSize ≤ capacity
    · by_cases secondFits : secondReady = true ∧ firstSize + secondSize ≤ capacity
      · refine ⟨true, true, false, ?_, ?_, ?_, ?_⟩
        all_goals simp [firstFits, secondFits] <;> omega
      · refine ⟨true, false, false, ?_, ?_, ?_, ?_⟩
        all_goals simp [firstFits, secondFits] <;> omega
    · refine ⟨false, false, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [firstFits] <;> omega
  · by_cases firstFits : firstReady = true ∧ used + 1 + firstSize ≤ capacity
    · by_cases secondFits : secondReady = true ∧ used + 1 + firstSize + secondSize ≤ capacity
      · refine ⟨true, true, true, ?_, ?_, ?_, ?_⟩
        all_goals simp [top, firstFits, secondFits] <;> omega
      · refine ⟨true, false, true, ?_, ?_, ?_, ?_⟩
        all_goals simp [top, firstFits, secondFits] <;> omega
    · refine ⟨false, false, false, ?_, ?_, ?_, ?_⟩
      all_goals simp [top, firstFits] <;> omega

theorem I3_blankFigureOrder_before_two_figures_with_source
    (capacity used firstSize secondSize : Nat)
    (firstReady secondReady : Bool) (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (firstReady = true ∧
        used + (if used = 0 then 0 else 1) + firstSize ≤ capacity) ∧
      second = decide (secondReady = true ∧ first = true ∧
        used + (if used = 0 then 0 else 1) + firstSize + secondSize ≤ capacity) ∧
      placed = blankPlacedFromSourceFull used 0 (fun pos =>
        if pos = 1 then false else
          waitingFigureBool (fun i => if i = 0 then first else second) 1)
        [.blank 0, .figure 1, .figure 2]
        (fun _ => false) (fun pos => if pos = 1 then first else second) ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  obtain ⟨first, second, placed, firstRule, secondRule, blankRule, fits⟩ :=
    blankFigureOrder_twoFiguresAfterBlank_withText capacity used firstSize
      secondSize firstReady secondReady usedFits
  refine ⟨first, second, placed, firstRule, secondRule, ?_, fits⟩
  rw [I3_blankWithNext_before_two_figures]
  exact blankRule

theorem I3_blankFigureOrder_between_two_figures_with_source
    (capacity used firstSize secondSize : Nat)
    (firstReady secondReady : Bool) (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (firstReady = true ∧ used + firstSize ≤ capacity) ∧
      second = decide (secondReady = true ∧ first = true ∧
        used + firstSize + 1 + secondSize ≤ capacity) ∧
      placed = blankPlacedFromSourceFull used 1 (fun _ =>
        waitingFigureBool (fun i => if i = 0 then first else second) 1)
        [.figure 0, .blank 1, .figure 2]
        (fun _ => false) (fun pos => if pos = 0 then first else second) ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  obtain ⟨first, second, placed, firstRule, secondRule, blankRule, fits⟩ :=
    blankFigureOrder_twoFiguresAroundBlank_withText capacity used firstSize
      secondSize firstReady secondReady usedFits
  have ordered : second = true → first = true := by
    intro present
    cases hfirst : first with
    | true => rfl
    | false =>
        simp [hfirst] at secondRule
        simp [secondRule] at present
  refine ⟨first, second, placed, firstRule, secondRule, ?_, fits⟩
  rw [I3_blankWithNext_between_two_figures used first second ordered]
  exact blankRule

theorem I3_blankFigureOrder_after_two_figures_with_source
    (capacity used firstSize secondSize : Nat)
    (firstReady secondReady : Bool) (usedFits : used ≤ capacity) :
    ∃ first second placed : Bool,
      first = decide (firstReady = true ∧ used + firstSize ≤ capacity) ∧
      second = decide (secondReady = true ∧ first = true ∧
        used + firstSize + secondSize ≤ capacity) ∧
      placed = blankPlacedFromSourceFull used 2 (fun _ => false)
        [.figure 0, .figure 1, .blank 2]
        (fun _ => false) (fun pos => if pos = 0 then first else second) ∧
      used + (if first then firstSize else 0) +
        (if second then secondSize else 0) + (if placed then 1 else 0) ≤ capacity := by
  obtain ⟨first, second, placed, firstRule, secondRule, blankRule, fits⟩ :=
    blankFigureOrder_twoFiguresBeforeBlank_withText capacity used firstSize
      secondSize firstReady secondReady usedFits
  refine ⟨first, second, placed, firstRule, secondRule, ?_, fits⟩
  rw [I3_blankWithNext_after_two_figures]
  exact blankRule

theorem I3_blankWithNext_before_one_figure (used : Nat) (kept : Bool) :
    blankPlacedFromSourceFull used 0 (fun _ => false)
      [.blank 0, .figure 1] (fun _ => false) (fun _ => kept) =
      decide (kept = true ∧ used ≠ 0) := by
  cases kept <;> cases used <;>
    simp [blankPlacedFromSourceFull, blankPlacedFromSource, blankAtTopSource,
      nextOfSource, candidateAfterBlank, candidateWaits, sourceInColumn,
      keptBeforeBlank]

theorem I3_blankFigureOrder_before_one_figure_with_source
    (capacity used size : Nat) (ready : Bool) (usedFits : used ≤ capacity) :
    ∃ kept placed : Bool,
      kept = decide (ready = true ∧
        used + (if used = 0 then 0 else 1) + size ≤ capacity) ∧
      placed = blankPlacedFromSourceFull used 0 (fun _ => false)
        [.blank 0, .figure 1] (fun _ => false) (fun _ => kept) ∧
      used + (if kept then size else 0) + (if placed then 1 else 0) ≤ capacity := by
  cases hready : ready with
  | false =>
      refine ⟨false, false, ?_, ?_, ?_⟩
      · simp [hready]
      · simp [I3_blankWithNext_before_one_figure]
      · simpa using usedFits
  | true =>
      obtain ⟨kept, placed, rule, blank, fits⟩ :=
        blankFigureOrder_oneFigure capacity used size (decide (used = 0)) usedFits
      refine ⟨kept, placed, ?_, ?_, fits⟩
      · simpa [hready] using rule
      · rw [I3_blankWithNext_before_one_figure]
        simpa using blank

theorem I3_blankFigureOrder_after_one_figure_with_source
    (capacity used size : Nat) (ready : Bool) (usedFits : used ≤ capacity) :
    ∃ kept placed : Bool,
      kept = decide (ready = true ∧ used + size ≤ capacity) ∧
      placed = blankPlacedFromSourceFull used 1 (fun _ => false)
        [.figure 0, .blank 1] (fun _ => false) (fun _ => kept) ∧
      used + (if kept then size else 0) + (if placed then 1 else 0) ≤ capacity := by
  by_cases fits : ready = true ∧ used + size ≤ capacity
  · exact ⟨true, false, by simp [fits], rfl, by simpa using fits.2⟩
  · exact ⟨false, false, by simp [fits], rfl, by simpa using usedFits⟩

theorem I3_blankFigureOrder_no_figures_with_source
    (capacity used : Nat) (usedFits : used ≤ capacity) :
    ∃ placed : Bool,
      placed = blankPlacedFromSourceFull used 0 (fun _ => false)
        [.blank 0] (fun _ => false) (fun _ => false) ∧
      used + (if placed then 1 else 0) ≤ capacity := by
  exact ⟨false, rfl, by simpa using usedFits⟩

/- A need of two lines before a one-line figure in a column with one line
   left conflicts with the older rule that keeps every figure that fits. -/
namespace NeedFigureWitness
def fits (keep : Bool) : Prop := 4 + (if keep then 1 else 0) ≤ 5
def oldRule (keep : Bool) := figuresRuleWithLoad 1 5 4 (fun _ => keep)
  (fun _ => True) (fun _ => 0) (fun _ => 1) (fun _ => false)
def ordered (keep : Bool) := figuresInOrder 1 (fun _ => keep)
def met (keep : Bool) : Prop := keep = true → 2 ≤ 5 - 4

private theorem old_iff (keep : Bool) : oldRule keep ↔ keep = true := by
  constructor
  · intro rule
    exact (rule 0 (by decide)).mpr ⟨trivial,by intro g lt; omega,by unfold figureHasRoom priorFigureLines; decide⟩
  · intro yes f bound
    have zero : f = 0 := by omega
    subst f
    simp [yes,figureHasRoom,priorFigureLines,show List.range 0 = [] from rfl,Nat.not_lt_zero]

private theorem always_ordered (keep : Bool) : ordered keep := by
  intro f bound _ g lt
  omega

theorem needFigure :
    (∃ keep, fits keep ∧ oldRule keep ∧ ordered keep) ∧
    (∃ keep, fits keep ∧ met keep) ∧
    (∀ keep, ¬ (fits keep ∧ oldRule keep ∧ ordered keep ∧ met keep)) := by
  refine ⟨⟨true,by simp [fits], (old_iff true).mpr rfl,always_ordered _⟩,⟨false,by simp [fits],by simp [met]⟩,?_⟩
  intro keep all
  have yes := (old_iff keep).mp all.2.1
  have impossible := all.2.2.2 yes
  omega
end NeedFigureWitness

/- The same need before a heading conflicts with filling the last line. -/
theorem needGreedy :
    (∃ brk : Fin 2, 2 + brk.val ≤ 3 ∧
      (brk.val = 1 ∨ 2 + brk.val + 1 > 3)) ∧
    (∃ brk : Fin 2, 2 + brk.val ≤ 3 ∧
      (brk.val = 1 → 2 + 2 ≤ 3)) ∧
    (∀ brk : Fin 2, ¬ (2 + brk.val ≤ 3 ∧
      (brk.val = 1 ∨ 2 + brk.val + 1 > 3) ∧
      (brk.val = 1 → 2 + 2 ≤ 3))) := by
  refine ⟨⟨1, by decide⟩, ⟨0, by decide⟩, ?_⟩
  intro brk
  omega

/- The fixed input of golem-layout ADR 0046: capacity 4, one used line,
   need 1, space, need 3, then a one-line paragraph. Text break 1 keeps
   only the space; break 2 also keeps the paragraph. Both needs are judged
   before the space, so the larger need is met and P7 requires break 2. -/
def space46Keeps (brk : Fin 3) : Prop :=
  (4 - 1 ≥ 1 ∧ 4 - 1 ≥ 3 ∧ 1 + 1 + 1 ≤ 4) → brk.val = 2

theorem needMoreSpace46 :
    ∀ brk : Fin 3, ¬ (brk.val = 1 ∧ space46Keeps brk) := by
  intro brk
  unfold space46Keeps
  omega

theorem needMoreSpace46Here :
    ∃ brk : Fin 3, brk.val = 2 ∧ space46Keeps brk ∧ 1 + brk.val ≤ 4 := by
  exact ⟨2, by decide, by simp [space46Keeps], by decide⟩

theorem needMoreSome :
    ∃ brk : Fin 3,
      brk.val = 2 ∧ space46Keeps brk ∧
      1 + brk.val ≤ 4 ∧ 1 < 3 ∧ 3 ≤ 4 := by
  obtain ⟨brk, atTwo, keeps, fits⟩ := needMoreSpace46Here
  exact ⟨brk, atTwo, keeps, fits, by decide, by decide⟩

/- A single two-line need before one space and one body line can keep both
   text items in a capacity-three column with one line already used. -/
theorem needSpaceSome :
    ∃ brk : Fin 3,
      brk.val = 2 ∧ 1 + brk.val ≤ 3 ∧
      3 - 1 ≥ 2 ∧ 1 + 1 + 1 ≤ 3 := by
  exact ⟨2, by decide, by decide, by decide, by decide⟩

/- One need, one space and one following line. The line can be kept when
   both the need and the space fit; otherwise the space alone or neither
   is placed. This is the arithmetic core of the simplest P1/P7 input. -/
/- The occupied column from the Alloy counterexample has two of four rows
   used. The source positions are need(2), heading, recto, recto. Text ranks
   are one less than the source positions of the three headings. There are
   no figures, blanks, spaces or paragraphs. Consequently both placement
   sets are empty, base27 reduces to fits, and orphan, widow, and the line
   clause of keepHeading21 quantify over empty sets. -/
namespace NeedHeadingConflict

def heading (p : Nat) : Prop := 1 ≤ p ∧ p ≤ 3
def here (brk pos : Nat) : Prop := pos - 1 < brk
def fits (brk : Nat) : Prop := 2 + brk ≤ 4

/- needNext contains only the first heading. Both placedBefore counts are
   two, the first part has size one, and there are no earlier text items. -/
def needMet (brk : Nat) : Prop := here brk 1 → 2 ≤ 4 - 2
def spaceKeeps (brk : Nat) : Prop := 2 ≤ 4 - 2 → 2 + 1 ≤ 4 → here brk 1

def keepHeading21 (brk : Nat) : Prop :=
  headingRunKeep (fun p => p ≤ 3) heading heading (here brk)
    (fun _ => False) (fun _ => False) (fun _ => True)

theorem first_keeps_last (brk : Nat) (keeps : keepHeading21 brk)
    (first : here brk 1) : here brk 3 := by
  have last := keeps 1 (by unfold heading; decide) first (by simp) 3 (by unfold heading; decide) (by decide)
    (by intro i _ lower upper; exact ⟨by omega, by omega⟩)
  exact last.1 (by unfold heading; decide)

end NeedHeadingConflict

theorem needSpaceAllButGreedy :
    (∃ b : Fin 4, NeedHeadingConflict.fits b.val ∧
      NeedHeadingConflict.needMet b.val ∧ NeedHeadingConflict.spaceKeeps b.val) ∧
    (∃ b : Fin 4, NeedHeadingConflict.fits b.val ∧ NeedHeadingConflict.keepHeading21 b.val) ∧
    (∀ b : Fin 4, ¬ (NeedHeadingConflict.fits b.val ∧
      NeedHeadingConflict.needMet b.val ∧ NeedHeadingConflict.spaceKeeps b.val ∧
      NeedHeadingConflict.keepHeading21 b.val)) := by
  refine ⟨⟨1, by unfold NeedHeadingConflict.fits; decide, by intro _; decide,
    by intro _ _; unfold NeedHeadingConflict.here; decide⟩, ?_, ?_⟩
  · refine ⟨0, by unfold NeedHeadingConflict.fits; decide, ?_⟩
    intro h _ placed
    exact (Nat.not_lt_zero _ placed).elim
  · intro b all
    have first := all.2.2.1 (by decide) (by decide)
    have last := NeedHeadingConflict.first_keeps_last b.val all.2.2.2 first
    have bound := all.1
    change 2 < b.val at last
    change 2 + b.val ≤ 4 at bound
    omega

def needSpaceSimpleBase (capacity used : Nat) (brk : Fin 3) : Prop :=
  used + brk.val ≤ capacity

def needSpaceSimpleMet (capacity used need : Nat) (brk : Fin 3) : Prop :=
  brk.val = 2 → need ≤ capacity - used

def needSpaceSimpleKeeps (capacity used need : Nat) (brk : Fin 3) : Prop :=
  need ≤ capacity - used ∧
    used + (if 1 ≤ brk.val then 1 else 0) + 1 ≤ capacity →
    brk.val = 2

theorem I3_need_space_one_block_exists
    (capacity used need : Nat) (usedFits : used ≤ capacity)
    (needPositive : 1 ≤ need) :
    ∃ brk : Fin 3,
      needSpaceSimpleBase capacity used brk ∧
      needSpaceSimpleMet capacity used need brk ∧
      needSpaceSimpleKeeps capacity used need brk := by
  by_cases met : need ≤ capacity - used
  · by_cases bothFit : used + 2 ≤ capacity
    · refine ⟨2, ?_, ?_, ?_⟩
      all_goals simp [needSpaceSimpleBase, needSpaceSimpleMet,
        needSpaceSimpleKeeps] <;> omega
    · have oneFits : used + 1 ≤ capacity := by omega
      refine ⟨1, ?_, ?_, ?_⟩
      all_goals simp [needSpaceSimpleBase, needSpaceSimpleMet,
        needSpaceSimpleKeeps] <;> omega
  · refine ⟨0, ?_, ?_, ?_⟩
    all_goals simp [needSpaceSimpleBase, needSpaceSimpleMet,
      needSpaceSimpleKeeps] <;> omega

-- Only a new maximum triggers a check for needs sharing a following block.
def recordNeedsFit (available previous : Nat) : List Nat → Prop
  | [] => True
  | n :: rest => (previous < n → n ≤ available) ∧
      recordNeedsFit available (max previous n) rest

theorem I3_record_needs_fit_iff_all (available previous : Nat) (ns : List Nat) (prior : previous ≤ available) :
    recordNeedsFit available previous ns ↔ ∀ n ∈ ns, n ≤ available := by
  induction ns generalizing previous with
  | nil => simp [recordNeedsFit]
  | cons n rest ih =>
    simp only [recordNeedsFit, List.mem_cons, forall_eq_or_imp]
    constructor
    · rintro ⟨check, tail⟩
      have fits : n ≤ available := by
        by_cases h : previous < n
        · exact check h
        · omega
      exact ⟨fits, (ih _ (Nat.max_le.mpr ⟨prior, fits⟩)).mp tail⟩
    · rintro ⟨fits, tail⟩
      exact ⟨fun _ => fits, (ih _ (Nat.max_le.mpr ⟨prior, fits⟩)).mpr tail⟩

/- In the domain without figures, spaces count towards load but
   not placedBefore. Each need belongs to the next non-space text, and
   source order within each group is retained for recordNeedsFit. -/
structure NeedTextPrefix where
  capacity : Nat
  used : Nat
  texts : Nat
  blankRank : Option Nat
  needs : Nat → List Nat
  space : Nat → Bool
  spaceHasNoNeeds : ∀ t, space t = true → needs t = []
  firstPart : Nat → Nat
  firstPartPositive : ∀ t, 0 < firstPart t
  positiveCapacity : 0 < capacity
  usedFits : used ≤ capacity

/- Choose a maximal feasible break by length of the finite text prefix.
   Checking just its immediate successor is sufficient because each
   failed P7 target requires one additional text, possibly a space. -/
private theorem maximal_break_above (valid : Nat → Prop) (start limit : Nat)
    (lower : start ≤ limit) (initial : valid start) :
    ∃ b, start ≤ b ∧ b ≤ limit ∧ valid b ∧ (b < limit → ¬ valid (b+1)) := by
  induction limit with
  | zero =>
    exact ⟨start, Nat.le_refl _, lower, initial, by intro h; exact (Nat.not_lt_zero _ h).elim⟩
  | succ limit ih =>
    by_cases last : valid (limit+1)
    · exact ⟨limit+1, lower, Nat.le_refl _, last, by intro h; omega⟩
    · have earlier : start ≤ limit := by
        apply Classical.byContradiction
        intro bound
        have eq : start = limit+1 := by omega
        exact last (eq ▸ initial)
      obtain ⟨b, lo, hi, ok, stopped⟩ := ih earlier
      refine ⟨b, lo, by omega, ok, ?_⟩
      intro _
      by_cases eq : b = limit
      · simpa [eq] using last
      · exact stopped (by omega)

namespace NeedTextPrefix
/- Count non-space rows in the first t texts, including previously used rows. -/
def placedBefore (d : NeedTextPrefix) : Nat → Nat
  | 0 => d.used
  | i + 1 => d.placedBefore i + (if d.space i then 0 else 1)

def allowed (d : NeedTextPrefix) (t : Nat) : Prop :=
  d.placedBefore t = 0 ∨ ∀ n ∈ d.needs t, n ≤ d.capacity - d.placedBefore t

/- A blank at gap g belongs to text g. At the top (empty column
   and g = 0) it is dropped. If the break does not reach its next text
   the blank stays out; a trailing blank therefore never contributes. -/
def blankBefore (d : NeedTextPrefix) (t : Nat) : Nat :=
  match d.blankRank with
  | none => 0
  | some g => if g < t ∧ 0 < d.used + g then 1 else 0

def blankPlaced (d : NeedTextPrefix) (b : Nat) : Bool :=
  match d.blankRank with
  | none => false
  | some g => decide (g < b ∧ 0 < d.used + g)

theorem blank_load (d : NeedTextPrefix) (b : Nat) :
    (if d.blankPlaced b then 1 else 0) = d.blankBefore b := by
  cases g : d.blankRank <;> simp [blankPlaced, blankBefore, g]

/- loadBefore counts an earlier blank unless the column was empty and
   no text before that blank was actually placed. For a nonempty input,
   noSendFromEmpty ensures b > 0 whenever used = 0. -/
theorem blank_before_load (d : NeedTextPrefix) (b t g : Nat)
    (blank : d.blankRank = some g) (progress : 0 < d.used + b) :
    (if g ≤ t ∧ 0 < d.used + min g b then 1 else 0) =
      d.blankBefore (t+1) := by
  by_cases prior : g ≤ t ∧ 0 < d.used + min g b
  · have same : g < t+1 ∧ 0 < d.used + g := by omega
    simp [blankBefore, blank, prior, same]
  · have same : ¬ (g < t+1 ∧ 0 < d.used + g) := by omega
    simp [blankBefore, blank, prior, same]

private theorem blank_mono (d : NeedTextPrefix) (a b : Nat) (le : a ≤ b) :
    d.blankBefore a ≤ d.blankBefore b := by
  cases eq : d.blankRank with
  | none => simp [blankBefore, eq]
  | some g =>
    by_cases prior : g < a ∧ 0 < d.used + g
    · have later : g < b ∧ 0 < d.used + g := ⟨by omega, prior.2⟩
      simp [blankBefore, eq, prior, later]
    · simp [blankBefore, eq, prior]

def legal (d : NeedTextPrefix) (b : Nat) : Prop :=
  d.used + b + d.blankBefore b ≤ d.capacity ∧ ∀ t, t < b → d.allowed t

private theorem longestLegal (d : NeedTextPrefix) (limit : Nat) :
    ∃ b, b ≤ limit ∧ d.legal b ∧ (b < limit → ¬ d.legal (b+1)) := by
  have initial : d.legal 0 := by
    refine ⟨?_, ?_⟩
    · cases g : d.blankRank <;> simpa [blankBefore, g] using d.usedFits
    · intro t ht
      exact (Nat.not_lt_zero t ht).elim
  obtain ⟨b, _, bound, valid, stop⟩ := maximal_break_above d.legal 0 limit (Nat.zero_le _) initial
  exact ⟨b, bound, valid, stop⟩

theorem prefix_exists (d : NeedTextPrefix) :
    ∃ b, b ≤ d.texts ∧ d.used + b + d.blankBefore b ≤ d.capacity ∧
      (d.used = 0 → 0 < d.texts → 0 < b) ∧
      (∀ t, t < b → d.allowed t) ∧
      (∀ t, t < d.texts → d.needs t ≠ [] →
        (∀ i, b ≤ i → i < t → d.space i = true) →
        recordNeedsFit (d.capacity - d.placedBefore t) 0 (d.needs t) →
        d.used + min t b + d.blankBefore (t+1) + d.firstPart t ≤ d.capacity → t < b) := by
  obtain ⟨b, bound, legal, stop⟩ := d.longestLegal d.texts
  have extendAt : d.used + b + 1 + d.blankBefore (b+1) ≤ d.capacity → d.allowed b → d.legal (b+1) := by
    intro room next
    refine ⟨by omega, ?_⟩
    intro t placed
    by_cases eq : t = b
    · simpa [eq] using next
    · exact legal.2 _ (by omega)
  refine ⟨b, bound, legal.1, ?_, legal.2, ?_⟩
  · intro empty nonempty
    apply Classical.byContradiction
    intro noProgress
    have zero : b = 0 := by omega
    have noBlank : d.blankBefore (b+1) = 0 := by
      cases eq : d.blankRank with
      | none => simp [blankBefore, eq]
      | some g =>
        have top : ¬ (g < b+1 ∧ 0 < d.used + g) := by omega
        simp [blankBefore, eq, top]
    exact stop (by omega) (extendAt (by have := d.positiveCapacity; omega)
      (Or.inl (by simp [placedBefore, zero, empty])))
  · intro t member _ onlySpaces records room
    apply Classical.byContradiction
    intro missed
    have before : b ≤ t := by omega
    rw [Nat.min_eq_right before] at room
    have allowed : d.allowed b := by
      by_cases same : t = b
      · subst t
        exact Or.inr ((I3_record_needs_fit_iff_all _ 0 _ (Nat.zero_le _)).mp records)
      · have space := onlySpaces b (Nat.le_refl _) (by omega)
        exact Or.inr (by simp [d.spaceHasNoNeeds b space])
    have blankBound := d.blank_mono (b+1) (t+1) (by omega)
    exact stop (by omega)
      (extendAt (by have := d.firstPartPositive t; omega) allowed)

/- A need appears at gap g between the text preceding it and its next
   text. If t is its target, all ranks from g to t (exclusive) are spaces.
   When all texts before the need are placed, skipping such spaces cannot
   change placedBefore, even if the chosen break splits that stretch. -/
theorem placedBefore_need_gap (d : NeedTextPrefix) (g b t : Nat)
    (gapReached : g ≤ b) (beforeTarget : g ≤ t)
    (onlySpace : ∀ i, g ≤ i → i < t → d.space i = true) :
    d.placedBefore (min t b) = d.placedBefore g := by
  have flat : ∀ k, g ≤ k → k ≤ t → d.placedBefore k = d.placedBefore g := by
    intro k
    induction k with
    | zero =>
      intro h _
      have eq := Nat.eq_zero_of_le_zero h
      rw [eq]
    | succ k ih =>
      intro lower upper
      by_cases same : g = k + 1
      · rw [same]
      · have prev : g ≤ k := by omega
        simp [placedBefore, onlySpace k prev (by omega), ih prev (by omega)]
  apply flat <;> omega

end NeedTextPrefix

/- When checking a figure under figures27, the other conjuncts already
   require every earlier figure and every earlier text to be placed. An
   earlier figure can then never be waiting, and the sum in placedBefore
   uses all earlier figures. This gives a non-circular construction even
   though waitingIn and needNext are defined in terms of the placement. -/
def needTargetsFigure (needPos : Nat) (figurePos : Nat → Nat)
    (block : Nat → Prop) (f : Nat) (waiting : Nat → Prop) : Prop :=
  needPos < figurePos f ∧ ¬ waiting f ∧
    (∀ t, block t → needPos < t → t < figurePos f → False) ∧
    (∀ g, g < f → needPos < figurePos g → waiting g)

theorem I3_figure_need_target_of_prior_kept
    (f n : Nat) (positions : Nat → Nat) (block : Nat → Prop)
    (kept : Nat → Bool) (allPrior : ∀ g, g < f → kept g = true) :
    needTargetsFigure n positions block f (figureWaits kept) ↔
      needTargetsFigure n positions block f (fun _ => False) := by
  have noWait : ∀ i, i ≤ f → ¬ figureWaits kept i := by
    intro i bound h
    obtain ⟨_, g, earlier, absent⟩ := h
    have present := allPrior g (by omega)
    simp [present] at absent
  constructor
  · rintro ⟨prior, _, noText, noFig⟩
    exact ⟨prior, by simp, noText, fun g lt ng => noWait g (Nat.le_of_lt lt) (noFig g lt ng)⟩
  · rintro ⟨prior, _, noText, noFig⟩
    exact ⟨prior, noWait _ (Nat.le_refl _), noText, fun g lt ng => (noFig g lt ng).elim⟩

/- Under textReady and the all-prior-figures conjunct, no earlier text
   or figure is omitted by placedBefore. -/
theorem I3_all_prior_rows_sum (n : Nat) (size : Nat → Nat) (kept : Nat → Bool)
    (prior : ∀ i, i < n → kept i = true) :
    (List.range n).foldl (fun rows i => rows + if kept i then size i else 0) 0 =
      priorFigureLines size n := by
  have sum : ∀ (xs : List Nat) (start : Nat),
      (∀ i ∈ xs, kept i = true) →
      xs.foldl (fun rows i => rows + if kept i then size i else 0) start =
        xs.foldl (fun rows i => rows + size i) start := by
    intro xs
    induction xs with
    | nil => intros; rfl
    | cons head tail ih =>
      intro start allKept
      have headKept := allKept head (List.mem_cons_self _ _)
      simp only [List.foldl_cons, headKept, if_true]
      exact ih _ (fun i m => allKept i (List.mem_cons_of_mem _ m))
  apply sum
  intro i member
  have bound : ∀ (m : Nat) (acc : List Nat),
      (∀ j ∈ acc, j < n) → m ≤ n → ∀ j ∈ List.range.loop m acc, j < n := by
    intro m
    induction m with
    | zero => intro acc valid _; exact valid
    | succ m ih =>
      intro acc valid upper
      apply ih (m :: acc) _ (by omega)
      intro j inside
      rcases List.mem_cons.mp inside with eq | tail
      · omega
      · exact valid j tail
  exact prior i (bound n [] (by simp) (Nat.le_refl _) i member)

def needFigureStatic (capacity used : Nat) (textBefore nonSpaceBefore size positions : Nat → Nat)
    (blankBefore : Nat → Bool) (block : Nat → Prop) (needs : List (Nat × Nat)) (f : Nat) : Prop :=
    figureHasRoom capacity used textBefore size blankBefore f ∧
      (∀ n ∈ needs, needTargetsFigure n.1 positions block f (fun _ => False) →
        used + nonSpaceBefore f + priorFigureLines size f = 0 ∨
        n.2 ≤ capacity - (used + nonSpaceBefore f + priorFigureLines size f))

def figures27Model (count capacity used : Nat) (ready : Nat → Bool)
    (textBefore nonSpaceBefore size positions : Nat → Nat)
    (blankBefore : Nat → Bool) (block : Nat → Prop)
    (needs : List (Nat × Nat)) (kept : Nat → Bool) : Prop :=
      (∀ f, f < count → (kept f = true ↔
        ready f = true ∧ (∀ g, g < f → kept g = true) ∧
        figureHasRoom capacity used textBefore size blankBefore f ∧
        (∀ n ∈ needs, needTargetsFigure n.1 positions block f (figureWaits kept) →
          used + nonSpaceBefore f + priorFigureLines (fun g => if kept g then size g else 0) f = 0 ∨
          n.2 ≤ capacity - (used + nonSpaceBefore f + priorFigureLines (fun g => if kept g then size g else 0) f))))

theorem I3_figure_static_rule_iff_model
    (count capacity used : Nat) (ready : Nat → Bool)
    (textBefore nonSpaceBefore size positions : Nat → Nat)
    (blankBefore : Nat → Bool) (block : Nat → Prop)
    (needs : List (Nat × Nat)) (kept : Nat → Bool)
    : figuresRule count kept (fun f => ready f = true)
        (needFigureStatic capacity used textBefore nonSpaceBefore size positions blankBefore block needs) ↔
      figures27Model count capacity used ready textBefore nonSpaceBefore size positions
        blankBefore block needs kept := by
  have one (f : Nat) :
      (ready f = true ∧ (∀ g, g < f → kept g = true) ∧
        needFigureStatic capacity used textBefore nonSpaceBefore size positions blankBefore block needs f) ↔
      (ready f = true ∧ (∀ g, g < f → kept g = true) ∧
        figureHasRoom capacity used textBefore size blankBefore f ∧
        (∀ n ∈ needs, needTargetsFigure n.1 positions block f (figureWaits kept) →
          used + nonSpaceBefore f + priorFigureLines (fun g => if kept g then size g else 0) f = 0 ∨
          n.2 ≤ capacity - (used + nonSpaceBefore f + priorFigureLines (fun g => if kept g then size g else 0) f))) := by
    constructor
    · rintro ⟨r, prior, fits, allowed⟩
      refine ⟨r, prior, fits, ?_⟩
      intro n member target
      have same : priorFigureLines (fun g => if kept g then size g else 0) f =
          priorFigureLines size f := I3_all_prior_rows_sum _ _ _ prior
      rw [same]
      exact allowed n member ((I3_figure_need_target_of_prior_kept f n.1 positions block kept prior).mp target)
    · rintro ⟨r, prior, fits, allowed⟩
      refine ⟨r, prior, fits, ?_⟩
      intro n member target
      have same : priorFigureLines (fun g => if kept g then size g else 0) f =
          priorFigureLines size f := I3_all_prior_rows_sum _ _ _ prior
      rw [← same]
      exact allowed n member ((I3_figure_need_target_of_prior_kept f n.1 positions block kept prior).mpr target)

  exact ⟨fun rule f h => (rule f h).trans (one f),
    fun model f h => (model f h).trans (one f).symm⟩

private theorem figures27_of_static
    (count capacity used : Nat) (ready : Nat → Bool)
    (textBefore nonSpaceBefore size positions : Nat → Nat)
    (blankBefore : Nat → Bool) (block : Nat → Prop)
    (needs : List (Nat × Nat)) (kept : Nat → Bool)
    (rule : figuresRule count kept (fun f => ready f = true)
      (needFigureStatic capacity used textBefore nonSpaceBefore size positions blankBefore block needs)) :
    figures27Model count capacity used ready textBefore nonSpaceBefore size positions
      blankBefore block needs kept := by
  exact (I3_figure_static_rule_iff_model count capacity used ready textBefore nonSpaceBefore size
    positions blankBefore block needs kept).mp rule

/-- For a fixed text break and blank charge, P27 determines every figure. -/
theorem I3_need_figure_model_is_greedy
    (count capacity used : Nat) (ready room kept : Nat → Bool)
    (textBefore nonSpaceBefore size positions : Nat → Nat)
    (blankBefore : Nat → Bool) (block : Nat → Prop) (needs : List (Nat × Nat))
    (roomEq : ∀ f, room f = true ↔ needFigureStatic capacity used textBefore nonSpaceBefore
      size positions blankBefore block needs f)
    (model : figures27Model count capacity used ready textBefore nonSpaceBefore size positions
      blankBefore block needs kept) :
    ∀ f, f < count → kept f = greedyFigure ready room f := by
  have static := (I3_figure_static_rule_iff_model count capacity used ready textBefore nonSpaceBefore
    size positions blankBefore block needs kept).mpr model
  intro f
  induction f using Nat.strongInductionOn with
  | ind f ih =>
      intro bound
      apply Bool.eq_iff_iff.mpr
      rw [static f bound, I3_greedyFigures_rule count ready room f bound]
      dsimp only
      rw [roomEq f]
      have prior : (∀ g, g < f → kept g = true) ↔
          (∀ g, g < f → greedyFigure ready room g = true) := by
        constructor
        · intro allKept g lt
          rw [← ih g lt (Nat.lt_trans lt bound)]
          exact allKept g lt
        · intro allGreedy g lt
          rw [ih g lt (Nat.lt_trans lt bound)]
          exact allGreedy g lt
      rw [prior]

theorem I3_need_figure_and_blank_exist
    (count capacity used : Nat) (earlierText : Bool) (ready beforeBlank : Nat → Bool)
    (textBefore nonSpaceBefore size positions : Nat → Nat)
    (block : Nat → Prop) (needs : List (Nat × Nat))
    (beforePrefix : ∀ g f, g < f → beforeBlank f = true → beforeBlank g = true) :
    ∃ top : Bool, ∃ kept : Nat → Bool,
      top = blankTopFromFigures used earlierText count beforeBlank kept ∧
      figuresInOrder count kept ∧
      figures27Model count capacity used ready textBefore nonSpaceBefore size positions
        (fun f => !beforeBlank f && !top) block needs kept := by
  let static := fun (charge : Bool) =>
    needFigureStatic capacity used textBefore nonSpaceBefore size positions (fun _ => charge) block needs
  let room := fun charge f => @decide (static charge f) (Classical.propDecidable _)
  obtain ⟨top, kept, topRule, rule⟩ := I3_blankFigureOrder_causal_exists used count earlierText
    ready beforeBlank (room false) (fun t => room (!t)) beforePrefix
  refine ⟨top, kept, topRule, I3_figuresRule_implies_figuresInOrder _ _ _ _ rule, ?_⟩
  apply figures27_of_static
  intro f bound
  have h := rule f bound
  cases e : beforeBlank f <;> cases t : top <;>
    simpa [roomAcrossBlank, room, static, needFigureStatic, figureHasRoom, e, t] using h

/- Once the text break reaches a figure, every earlier figure is also
   text-ready. Whether the figure is kept now depends only on the room
   and need checks in that source prefix. Increasing the break cannot
   remove it or uncover another figure at an earlier text rank. -/
theorem I3_figure_break_prefix (textRank : Nat → Nat)
    (ordered : ∀ i j, i ≤ j → textRank i ≤ textRank j)
    (room : Nat → Bool) (b f : Nat) :
    greedyFigure (fun i => decide (textRank i ≤ b)) room f = true ↔
      textRank f ≤ b ∧ ∀ i, i ≤ f → room i = true := by
  let ready := fun i => decide (textRank i ≤ b)
  have rule := I3_greedyFigures_rule (f+1) ready room
  have upto : ∀ i, i ≤ f → (greedyFigure ready room i = true ↔
      textRank i ≤ b ∧ ∀ j, j ≤ i → room j = true) := by
    intro i
    induction i with
    | zero =>
      intro _
      rw [rule 0 (by omega)]
      simp [ready]
      intros; omega
    | succ i ih =>
      intro bound
      rw [rule (i+1) (by omega)]
      constructor
      · rintro ⟨now, before, own⟩
        refine ⟨(decide_eq_true_eq.mp now), ?_⟩
        intro j earlier
        by_cases same : j = i+1
        · simpa [same] using own
        · exact (((ih (by omega)).mp (before i (by omega))).2 j (by omega))
      · rintro ⟨reached, allRoom⟩
        refine ⟨by simpa [ready] using reached, ?_, allRoom _ (by omega)⟩
        intro j earlier
        have iKept := (ih (by omega)).mpr
          ⟨Nat.le_trans (ordered i (i+1) (by omega)) reached,
            fun k prior => allRoom k (by omega)⟩
        by_cases same : j = i
        · simpa [same] using iKept
        · exact ((rule i (by omega)).mp iKept).2.1 j (by omega)
  exact upto f (by omega)

theorem I3_new_figure_at_extended_break (textRank : Nat → Nat)
    (ordered : ∀ i j, i ≤ j → textRank i ≤ textRank j)
    (room : Nat → Bool) (b f : Nat)
    (missing : greedyFigure (fun i => decide (textRank i ≤ b)) room f = false)
    (placed : greedyFigure (fun i => decide (textRank i ≤ b+1)) room f = true) :
    textRank f = b+1 := by
  have next := (I3_figure_break_prefix textRank ordered room (b+1) f).mp placed
  apply Classical.byContradiction
  intro other
  have prev := (I3_figure_break_prefix textRank ordered room b f).mpr
    ⟨by omega, next.2⟩
  simp [missing] at prev

theorem I3_blank_top_stable_across_positive_breaks (used count rank : Nat)
    (beforeBlank : Nat → Bool) (textRank : Nat → Nat)
    (ordered : ∀ i j, i ≤ j → textRank i ≤ textRank j)
    (beforeRank : ∀ i, beforeBlank i = true → textRank i ≤ rank)
    (room : Nat → Bool) (b c : Nat) (positiveB : 0 < b) (positiveC : 0 < c) :
    blankTopFromFigures used (decide (0 < min b rank)) count beforeBlank
      (greedyFigure (fun i => decide (textRank i ≤ b)) room) =
    blankTopFromFigures used (decide (0 < min c rank)) count beforeBlank
      (greedyFigure (fun i => decide (textRank i ≤ c)) room) := by
  by_cases hasText : 0 < rank
  · have hb : 0 < min b rank := by omega
    have hc : 0 < min c rank := by omega
    simp [blankTopFromFigures, hb, hc]
  · have rankZero : rank = 0 := by omega
    subst rank
    have same : ∀ i, (beforeBlank i && greedyFigure (fun j => decide (textRank j ≤ b)) room i) =
        (beforeBlank i && greedyFigure (fun j => decide (textRank j ≤ c)) room i) := by
      intro i
      cases e : beforeBlank i with
      | false => rfl
      | true =>
        have bound := beforeRank i e
        have eb := I3_figure_break_prefix textRank ordered room b i
        have ec := I3_figure_break_prefix textRank ordered room c i
        have withinB : textRank i ≤ b := by omega
        have withinC : textRank i ≤ c := by omega
        have sameRoom : (greedyFigure (fun j => decide (textRank j ≤ b)) room i = true) ↔
            (greedyFigure (fun j => decide (textRank j ≤ c)) room i = true) := by
          rw [eb, ec]
          simp [withinB, withinC]
        cases hb : greedyFigure (fun j => decide (textRank j ≤ b)) room i <;>
          cases hc : greedyFigure (fun j => decide (textRank j ≤ c)) room i <;>
          simp [hb, hc] at sameRoom ⊢
    have eq : (fun i => beforeBlank i && greedyFigure (fun j => decide (textRank j ≤ b)) room i) =
        (fun i => beforeBlank i && greedyFigure (fun j => decide (textRank j ≤ c)) room i) :=
      funext same
    simp only [blankTopFromFigures, Nat.min_zero]
    rw [eq]

/- If extending the text prefix admits additional figures, the last of
   those admitted figures bounds the load of every retained figure, not
   merely its own height. The blank is charged if it was before that
   figure. If the blank is after it and no later text or figure is placed,
   the blank has no placed successor and is not charged. -/
def keptRowsThrough (kept : Nat → Bool) (size : Nat → Nat) : Nat → Nat
  | 0 => 0
  | n+1 => keptRowsThrough kept size n + (if kept n then size n else 0)

private theorem keptRowsThrough_prefix_end (kept : Nat → Bool)
    (size : Nat → Nat) (count : Nat) :
    (keptRowsThrough kept size count = 0) ∨ ∃ f, f < count ∧ kept f = true ∧
      keptRowsThrough kept size count = keptRowsThrough kept size (f+1) ∧
      (∀ i, f < i → i < count → kept i = false) := by
  induction count with
  | zero => exact Or.inl rfl
  | succ n ih =>
    cases own : kept n with
    | true => exact Or.inr ⟨n, by omega, own, rfl, by intros; omega⟩
    | false =>
      have sum : keptRowsThrough kept size (n+1) = keptRowsThrough kept size n := by
        simp [keptRowsThrough, own]
      rcases ih with empty | ⟨f, bound, yes, total, last⟩
      · exact Or.inl (sum.trans empty)
      · refine Or.inr ⟨f, by omega, yes, sum.trans total, ?_⟩
        intro i earlier upper
        by_cases eq : i = n
        · simpa [eq] using own
        · exact last i earlier (by omega)

theorem I3_blank_charge_before_last_placed (last blank : Nat)
    (items : List SourceItem) (waiting textHere kept : Nat → Bool) (top : Bool)
    (lastText : ∀ p, .text p ∈ items → textHere p = true → p ≤ last)
    (lastFigure : ∀ p, .figure p ∈ items → kept p = true → p ≤ last) :
    (if blankPlacedFromSource blank waiting items textHere kept top then 1 else 0) ≤
      (if blank < last ∧ top = false then 1 else 0) := by
  cases next : nextOfSource blank waiting items with
  | none => simp [blankPlacedFromSource, next]
  | some candidate =>
    obtain ⟨item, member, selected, _⟩ :=
      I3_nextOfSource_some_has_member blank waiting items candidate next
    cases placed : sourceInColumn textHere kept candidate with
    | false => simp [blankPlacedFromSource, next, placed]
    | true =>
      have before : blank < last := by
        cases item with
        | text p =>
          simp [candidateAfterBlank] at selected
          obtain ⟨before, eq⟩ := selected
          subst candidate
          have loaded : textHere p = true := placed
          have := lastText p member loaded
          omega
        | figure p =>
          simp [candidateAfterBlank] at selected
          obtain ⟨before, eq⟩ := selected
          subst candidate
          have loaded : kept p = true := placed
          have := lastFigure p member loaded
          omega
        | blank _ => contradiction
        | need _ => contradiction
      cases top <;> simp [blankPlacedFromSource, next, placed, before]

theorem I3_text_before_source_monotone (items : List SourceItem)
    (p q : Nat) (before : p ≤ q) :
    textBeforeCount items p ≤ textBeforeCount items q := by
  induction items with
  | nil => simp [textBeforeCount]
  | cons head rest ih =>
    simp only [textBeforeCount] at ih ⊢
    cases head with
    | text pos =>
      by_cases early : pos < p
      · have later : pos < q := by omega
        simp [earlierTextItem, early, later, ih] <;> omega
      · by_cases later : pos < q <;> simp [earlierTextItem, early, later, ih] <;> omega
    | figure _ | blank _ | need _ => simpa [earlierTextItem] using ih

theorem I3_extended_figure_prefix_fits (capacity used b count : Nat)
    (kept oldKept : Nat → Bool) (size : Nat → Nat)
    (positions : Nat → Nat) (blank : Nat) (items : List SourceItem)
    (waiting keptAt : Nat → Bool) (top : Bool)
    (positionOrder : ∀ j f, j ≤ f → positions j ≤ positions f)
    (keptSource : ∀ p, .figure p ∈ items → keptAt p = true →
      ∃ i, i < count ∧ kept i = true ∧ positions i = p)
    (newFig : ∃ j, j < count ∧ oldKept j = false ∧ kept j = true)
    (positive : ∀ j, j < count → 0 < size j)
    (placedRank : ∀ f, f < count → kept f = true → textBeforeCount items (positions f) ≤ b+1)
    (freshRank : ∀ j, j < count → oldKept j = false → kept j = true → textBeforeCount items (positions j) = b+1)
    (room : ∀ f, f < count → kept f = true →
      used + textBeforeCount items (positions f) + keptRowsThrough kept size (f+1) +
        (if blank < positions f ∧ top = false then 1 else 0) ≤ capacity) :
    used + (b+1) + keptRowsThrough kept size count +
      (if blankPlacedFromSource blank waiting items (textHereAtBreak items (b+1)) keptAt top then 1 else 0) ≤ capacity := by
  obtain ⟨j, jBound, old, yes⟩ := newFig
  have jRank := freshRank j jBound old yes
  rcases keptRowsThrough_prefix_end kept size count with empty | ⟨f, fBound, last, sum, ends⟩
  · have positiveSum : ∀ n, j < n → 0 < keptRowsThrough kept size n := by
      intro n
      induction n with
      | zero => intro h; exact (Nat.not_lt_zero _ h).elim
      | succ n ih =>
        intro h
        by_cases eq : j = n
        · subst n
          simp [keptRowsThrough, yes]
          have := positive j jBound
          omega
        · have := ih (by omega)
          simp [keptRowsThrough]
          omega
    have := positiveSum count jBound
    omega
  · have ordered : j ≤ f := by
      apply Classical.byContradiction
      intro beyond
      have absent := ends j (by omega) jBound
      simp [yes] at absent
    have later := I3_text_before_source_monotone items _ _ (positionOrder j f ordered)
    have upper := placedRank f fBound last
    have fits := room f fBound last
    have blankCharge := I3_blank_charge_before_last_placed (positions f) blank items
      waiting (textHereAtBreak items (b+1)) keptAt top (by
        intro p _ placed
        apply Classical.byContradiction
        intro after
        have later := I3_text_before_source_monotone items (positions f) p (by omega)
        change decide (textBeforeCount items p < b+1) = true at placed
        have := decide_eq_true_eq.mp placed
        omega) (by
        intro p member placed
        obtain ⟨i, iBound, included, eq⟩ := keptSource p member placed
        have prior : i ≤ f := by
          apply Classical.byContradiction
          intro later
          have absent := ends i (by omega) iBound
          simp [included] at absent
        simpa [eq] using positionOrder i f prior)
    omega

/- spaceKeeps quantifies over figures before the need that are not
   waiting. This is equivalent to retaining every preceding figure:
   the first sent figure cannot have an earlier sent figure, so it
   never belongs to waitingIn. -/
theorem I3_no_unplaced_nonwaiting_before_iff (kept : Nat → Bool) (n : Nat) :
    (∀ f, f < n → ¬ figureWaits kept f → kept f = true) ↔
      (∀ f, f < n → kept f = true) := by
  constructor
  · intro onlyNonwaiting
    have all : ∀ bound, bound ≤ n → ∀ f, f < bound → kept f = true := by
      intro bound
      induction bound with
      | zero => intro _ f lt; exact (Nat.not_lt_zero f lt).elim
      | succ k ih =>
        intro upper f lt
        have lower := ih (by omega)
        by_cases earlier : f < k
        · exact lower f earlier
        · have eq : f = k := by omega
          subst f
          apply onlyNonwaiting k (by omega)
          intro wait
          obtain ⟨_, i, prev, sent⟩ := wait
          have yes := lower i prev
          simp [yes] at sent
    exact all n (Nat.le_refl _)
  · intro all f lt _
    exact all f lt

/- If the first unplaced item is a figure and all preceding text and
   figures are already here, the room and P7 checks force that figure
   directly. There is no additional text break to select in this case. -/
theorem I3_figure_need_earlier_figures_placed
    (kept : Nat → Bool) (pos : Nat → Nat)
    (n f : Nat) (block : Nat → Prop)
    (target : needTargetsFigure n pos block f (figureWaits kept))
    (beforeNeed : ∀ g, pos g < n → ¬ figureWaits kept g → kept g = true)
    (distinct : ∀ g, pos g ≠ n) :
    ∀ g, g < f → kept g = true := by
  apply (I3_no_unplaced_nonwaiting_before_iff kept f).mp
  intro g prior notWaiting
  by_cases earlier : pos g < n
  · exact beforeNeed g earlier notWaiting
  · have different := distinct g
    exact (notWaiting (target.2.2.2 g prior (by omega))).elim

theorem I3_figure_need_earlier_text_placed
    (items : List SourceItem) (space here : Nat → Bool)
    (figPos : Nat → Nat) (n f : Nat) (kept : Nat → Bool)
    (target : needTargetsFigure n figPos (fun p => .text p ∈ items ∧ space p = false)
      f (figureWaits kept))
    (beforeNeed : ∀ p, .text p ∈ items → p < n → here p = true)
    (beforeSpaces : ∀ p, .text p ∈ items → n < p → p < figPos f →
      space p = true → here p = true)
    (distinct : ∀ p, .text p ∈ items → p ≠ n) :
    ∀ p, .text p ∈ items → p < figPos f → here p = true := by
  intro p member prior
  by_cases earlier : p < n
  · exact beforeNeed p member earlier
  · have diff := distinct p member
    have after : n < p := by omega
    cases sp : space p with
    | true => exact beforeSpaces p member after prior sp
    | false => exact (target.2.2.1 p ⟨member, sp⟩ after prior).elim

theorem I3_target_figure_stays_when_group_fits
    (count capacity used f : Nat) (ready : Nat → Bool)
    (textBefore nonSpaceBefore size positions : Nat → Nat)
    (blankBefore : Nat → Bool) (block : Nat → Prop)
    (needs : List (Nat × Nat)) (kept : Nat → Bool)
    (rule : figures27Model count capacity used ready textBefore nonSpaceBefore size
      positions blankBefore block needs kept)
    (bound : f < count) (allText : ready f = true)
    (allFig : ∀ g, g < f → ¬ figureWaits kept g → kept g = true)
    (firstFits : used + textBefore f + priorFigureLines (fun g => if kept g then size g else 0) f +
      (if blankBefore f then 1 else 0) + size f ≤ capacity)
    (records : recordNeedsFit
      (capacity - (used + nonSpaceBefore f + priorFigureLines (fun g => if kept g then size g else 0) f))
      0 ((needs.filter (fun n => @decide
        (needTargetsFigure n.1 positions block f (figureWaits kept)) (Classical.propDecidable _))).map Prod.snd)) :
    kept f = true := by
  have prior := (I3_no_unplaced_nonwaiting_before_iff kept f).mp allFig
  have sum := I3_all_prior_rows_sum f size kept prior
  change priorFigureLines (fun g => if kept g then size g else 0) f = priorFigureLines size f at sum
  apply (rule f bound).mpr
  refine ⟨allText, prior, ?_, ?_⟩
  · rwa [sum] at firstFits
  · intro n member target
    apply Or.inr
    apply (I3_record_needs_fit_iff_all _ 0 _ (Nat.zero_le _)).mp records n.2
    apply List.mem_map.mpr
    exact ⟨n, List.mem_filter.mpr ⟨member, decide_eq_true_eq.mpr target⟩, rfl⟩

/- For the original one-need rule the needMet test is made at the
   target whereas P7 checks the need where written. There is no ordinary
   text or nonwaiting figure between a need and its target, so the
   occupied, non-space load is unchanged. Record checks for several
   needs of the same block use the same equality at every need. -/
theorem I3_same_placed_rows_to_target (n target : Nat) (positions : List Nat)
    (row : Nat → Nat) (before : n ≤ target)
    (betweenEmpty : ∀ p ∈ positions, n ≤ p → p < target → row p = 0) :
    positions.foldl (fun acc p => acc + (if p < n then row p else 0)) 0 =
      positions.foldl (fun acc p => acc + (if p < target then row p else 0)) 0 := by
  have gen : ∀ (ps : List Nat) (acc : Nat),
      (∀ p ∈ ps, n ≤ p → p < target → row p = 0) →
      ps.foldl (fun a p => a + (if p < n then row p else 0)) acc =
        ps.foldl (fun a p => a + (if p < target then row p else 0)) acc := by
    intro ps
    induction ps with
    | nil => intros; rfl
    | cons p rest ih =>
      intro acc noRows
      have same : (if p < n then row p else 0) = (if p < target then row p else 0) := by
        by_cases early : p < n
        · have := Nat.lt_of_lt_of_le early before
          simp [early, this]
        · by_cases inside : p < target
          · have none := noRows p (List.mem_cons_self _ _) (by omega) inside
            simp [early, inside, none]
          · simp [early, inside]
      simp only [List.foldl_cons, same]
      exact ih _ (fun q m => noRows q (List.mem_cons_of_mem _ m))
  exact gen _ _ betweenEmpty

theorem I3_placed_text_rows_to_figure_target
    (n f : Nat) (positions : Nat → Nat) (items : List SourceItem)
    (space here : Nat → Bool) (kept : Nat → Bool)
    (target : needTargetsFigure n positions (fun p => .text p ∈ items ∧ space p = false)
      f (figureWaits kept))
    (uniquePos : ∀ p, .text p ∈ items → p ≠ n) :
    let row := fun p => if here p && !space p then 1 else 0
    (sourceTextPositions items).foldl (fun a p => a + if p < n then row p else 0) 0 =
      (sourceTextPositions items).foldl (fun a p => a + if p < positions f then row p else 0) 0 := by
  apply I3_same_placed_rows_to_target _ _ _ _ (Nat.le_of_lt target.1)
  intro p member reached before
  have text := (I3_source_text_position_member items p).mp member
  have diff := uniquePos p text
  cases sp : space p with
  | true => simp [sp]
  | false => exact (target.2.2.1 p ⟨text, sp⟩ (by omega) before).elim

theorem I3_placed_figure_rows_to_figure_target
    (n f : Nat) (figureIndices : List Nat) (positions size : Nat → Nat)
    (kept : Nat → Bool) (block : Nat → Prop)
    (target : needTargetsFigure n positions block f (figureWaits kept))
    (ordered : ∀ i j, i ≤ j → positions i ≤ positions j)
    (uniquePos : ∀ i, positions i ≠ n) :
    let sumAt := fun before => figureIndices.foldl
      (fun a i => a + if positions i < before ∧ kept i = true then size i else 0) 0
    sumAt n = sumAt (positions f) := by
  have same : ∀ i,
      (if positions i < n ∧ kept i = true then size i else 0) =
      (if positions i < positions f ∧ kept i = true then size i else 0) := by
    intro i
    by_cases here : kept i = true
    · by_cases early : positions i < n
      · have before := Nat.lt_trans early target.1
        simp [here, early, before]
      · by_cases before : positions i < positions f
        · have lt : i < f := by
            apply Classical.byContradiction
            intro h
            have order := ordered f i (by omega)
            omega
          have diff := uniquePos i
          have wait := target.2.2.2 i lt (by omega)
          have absent := wait.1
          simp [here] at absent
        · simp [here, early, before]
    · simp [here]
  have funcs : (fun (a i : Nat) => a + if positions i < n ∧ kept i = true then size i else 0) =
      (fun a i => a + if positions i < positions f ∧ kept i = true then size i else 0) := by
    funext a i
    rw [same]
  dsimp
  rw [funcs]

/- needNext for a text target requires every figure between the need
   and the target to be waiting. The first unplaced figure is never
   waiting. Once the need is reached, there can therefore be no figure
   between it and this target; all preceding figures have stayed. -/
def needTargetsText (n target : Nat) (textBlock : Nat → Prop)
    (positions : Nat → Nat) (count : Nat) (kept : Nat → Bool) : Prop :=
  n < target ∧ textBlock target ∧
    (∀ p, textBlock p → n < p → p < target → False) ∧
    (∀ f, f < count → n < positions f → positions f < target → figureWaits kept f)

theorem I3_no_intervening_figure_before_reached_need_text
    (n t count : Nat) (positions : Nat → Nat) (kept : Nat → Bool)
    (block : Nat → Prop) (target : needTargetsText n t block positions count kept)
    (ordered : ∀ i j, i ≤ j → positions i ≤ positions j)
    (distinct : ∀ f, positions f ≠ n)
    (reached : ∀ f, f < count → positions f < n → ¬ figureWaits kept f → kept f = true) :
    (∀ f, f < count → positions f < t → kept f = true) ∧
    (∀ f, f < count → n < positions f → positions f < t → False) := by
  have yes : ∀ f, f < count → positions f < t → kept f = true := by
    intro f bound before
    have all := (I3_no_unplaced_nonwaiting_before_iff kept (f+1)).mp (by
      intro g prior active
      have rel := ordered g f (by omega)
      by_cases early : positions g < n
      · exact reached g (by omega) early active
      · have diff := distinct g
        exact (active (target.2.2.2 g (by omega) (by omega) (by omega))).elim)
    exact all f (by omega)
  refine ⟨yes, ?_⟩
  intro f bound after before
  have absent := (target.2.2.2 f bound after before).1
  have present := yes f bound before
  simp [present] at absent

theorem I3_text_need_missed_only_spaces (n t count : Nat)
    (positions : Nat → Nat) (kept : Nat → Bool)
    (items : List SourceItem) (space here : Nat → Bool)
    (target : needTargetsText n t (fun p => .text p ∈ items ∧ space p = false)
      positions count kept)
    (reached : ∀ p, .text p ∈ items → p < n → here p = true)
    (distinct : ∀ p, .text p ∈ items → p ≠ n) :
    ∀ p, .text p ∈ items → p < t → here p = false → space p = true := by
  intro p member before missing
  by_cases early : p < n
  · have present := reached p member early
    simp [present] at missing
  · have diff := distinct p member
    cases sp : space p with
    | true => rfl
    | false => exact (target.2.2.1 p ⟨member, sp⟩ (by omega) before).elim

/- Source fixture shared with PaginateSpec: two paragraph lines, a
   size-three figure, need(2), a size-one figure and one paragraph line.
   Both figures are sent. The first sent figure remains a needNext
   candidate; the second waits and is passed over. Thus P1 is active
   for the last line although the prior-figure premise of P7 is false. -/
theorem I3_need_across_waiting_figure :
    let pos := fun f : Nat => if f = 0 then 2 else 4
    let kept := fun _ : Nat => false
    let items : List SourceItem := [.text 0, .text 1, .figure 2, .need 3, .figure 4, .text 5]
    ¬ figureWaits kept 0 ∧ figureWaits kept 1 ∧
      needTargetsText 3 5 (fun p => .text p ∈ items) pos 2 kept ∧
      textHereAtBreak items 3 5 = true ∧
      2 ≤ 4 - textBeforeCount items 5 ∧
      ¬ (∀ f, f < 2 → pos f < 3 → ¬ figureWaits kept f → kept f = true) := by
  dsimp
  have first : ¬ figureWaits (fun _ => false) 0 := by
    rintro ⟨_, i, h, _⟩
    exact Nat.not_lt_zero i h
  have second : figureWaits (fun _ => false) 1 :=
    ⟨rfl, 0, by decide, rfl⟩
  refine ⟨first, second, ?_, by decide, by decide, ?_⟩
  · refine ⟨by decide, by simp, ?_, ?_⟩
    · intro p member after before
      simp at member
      omega
    · intro f limit after _
      by_cases zero : f = 0
      · simp [zero] at after
      · have one : f = 1 := by omega
        simpa [one] using second
  · intro all
    have bad := all 0 (by decide) (by decide) first
    contradiction

/- The next text admitted while P7 is unmet is either the target or an
   intervening space. For an unchanged set of figures, the existing load
   bound at the target pays for this one text and any blank whose next
   placed item is no later than the target. Every already retained figure
   precedes the missed target by the figure order predicate. -/
theorem I3_figure_after_unplaced_target_impossible
    (items : List SourceItem) (t fig b : Nat) (textIn : .text t ∈ items)
    (missed : textHereAtBreak items b t = false)
    (order : ∀ p, .text p ∈ items → p < fig → textHereAtBreak items b p = true) :
    fig ≤ t := by
  apply Classical.byContradiction
  intro after
  have yes := order t textIn (by omega)
  simp [yes] at missed

theorem I3_extension_fits_before_target
    (capacity used b count : Nat) (size positions : Nat → Nat) (blank t : Nat)
    (items : List SourceItem) (waiting keptAt kept : Nat → Bool) (top : Bool)
    (part : Nat) (partPositive : 0 < part)
    (keptSource : ∀ p, .figure p ∈ items → keptAt p = true →
      ∃ i, i < count ∧ kept i = true ∧ positions i = p)
    (allTextBefore : ∀ p, .text p ∈ items → textHereAtBreak items (b+1) p = true → p ≤ t)
    (allFigBefore : ∀ i, i < count → kept i = true → positions i ≤ t)
    (localRoom : used + b + keptRowsThrough kept size count +
      (if blank < t ∧ top = false then 1 else 0) + part ≤ capacity) :
    used + (b+1) + keptRowsThrough kept size count +
      (if blankPlacedFromSource blank waiting items (textHereAtBreak items (b+1)) keptAt top
       then 1 else 0) ≤ capacity := by
  have charge := I3_blank_charge_before_last_placed t blank items waiting
    (textHereAtBreak items (b+1)) keptAt top allTextBefore (by
      intro p member present
      obtain ⟨i, bound, yes, same⟩ := keptSource p member present
      simpa [same] using allFigBefore i bound yes)
  omega

theorem I3_unchanged_figures_extended_fits
    (capacity used b count : Nat) (size positions : Nat → Nat) (blank t : Nat)
    (items : List SourceItem) (waiting keptAt kept : Nat → Bool) (top : Bool)
    (part : Nat) (partPositive : 0 < part)
    (keptSource : ∀ p, .figure p ∈ items → keptAt p = true →
      ∃ i, i < count ∧ kept i = true ∧ positions i = p)
    (ordered : sourceOrdered items) (target : .text t ∈ items)
    (missed : textHereAtBreak items b t = false)
    (figOrder : ∀ i, i < count → kept i = true →
      ∀ p, .text p ∈ items → p < positions i → textHereAtBreak items b p = true)
    (localRoom : used + b + keptRowsThrough kept size count +
      (if blank < t ∧ top = false then 1 else 0) + part ≤ capacity) :
    used + (b+1) + keptRowsThrough kept size count +
      (if blankPlacedFromSource blank waiting items (textHereAtBreak items (b+1)) keptAt top
       then 1 else 0) ≤ capacity := by
  have allTextBefore : ∀ p, .text p ∈ items → textHereAtBreak items (b+1) p = true → p ≤ t := by
    intro p member present
    apply Classical.byContradiction
    intro after
    have increasing := I3_text_rank_preserves_order (sourceTextPositions items)
      (I3_source_text_positions_ordered items ordered) t p
      ((I3_source_text_position_member items t).mpr target)
      ((I3_source_text_position_member items p).mpr member) (by omega)
    have actual := (I3_text_here_iff_source_rank items ordered p (b+1) member).mp present
    have targetMissing : ¬ textRank (sourceTextPositions items) t < b := by
      intro lt
      have yes := (I3_text_here_iff_source_rank items ordered t b target).mpr lt
      simp [yes] at missed
    omega
  apply I3_extension_fits_before_target capacity used b count size positions blank t items
    waiting keptAt kept top part partPositive keptSource allTextBefore _ localRoom
  intro i bound yes
  exact I3_figure_after_unplaced_target_impossible items t (positions i) b target missed
    (figOrder i bound yes)

/- The number of placed texts in the prefix before a missed P7 target
   is exactly the break. Consequently the b term of both extension
   bounds is the cardinality used by Alloy loadBefore rather than an
   assumption about the target. -/
private theorem filter_eq_on_members {α : Type} {xs : List α} {f g : α → Bool}
    (same : ∀ x ∈ xs, f x = g x) : xs.filter f = xs.filter g := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    have head := same x (List.mem_cons_self _ _)
    have tail := ih (fun y hy => same y (List.mem_cons_of_mem _ hy))
    simp only [List.filter_cons, head, tail]

/- At a figure position its preceding text is the take of the ordered
   source text list. Its length is the figure's textBeforeCount, so the
   first b placed texts all occur in this take whenever b is smaller. -/
private theorem placed_count_before_any_position (ps : List Nat) (t b : Nat)
    (sorted : strictTextPositions ps) (enough : b ≤ countEarlierText ps t) :
    (ps.filter (fun p => decide (p < t ∧ textRank ps p < b))).length = b := by
  induction ps generalizing b with
  | nil =>
    simp [countEarlierText] at enough
    simp [enough]
  | cons h rest ih =>
    obtain ⟨prior, tailSorted⟩ := sorted
    cases b with
    | zero =>
      have none : ∀ xs : List Nat, xs.filter (fun _ => false) = [] := by
        intro xs; induction xs with
        | nil => rfl
        | cons x xs ih => simpa using ih
      rw [filter_eq_on_members (g := fun _ => false) (by intros; simp [Nat.not_lt_zero]), none]
      rfl
    | succ b =>
      have first : h < t := by
        apply Classical.byContradiction
        intro later
        have none : rest.filter (fun p => decide (p < t)) = [] := by
          cases eq : rest.filter (fun p => decide (p < t)) with
          | nil => rfl
          | cons p ps =>
            have mem : p ∈ rest.filter (fun p => decide (p < t)) := by rw [eq]; simp
            obtain ⟨inRest, lt⟩ := List.mem_filter.mp mem
            have after := prior p inRest
            have := decide_eq_true_eq.mp lt
            omega
        simp [countEarlierText, later, none] at enough
      have remaining : b ≤ countEarlierText rest t := by
        simp [countEarlierText, first] at enough ⊢
        omega
      have tail := ih b tailSorted remaining
      have filtered : rest.filter (fun p => decide (p < t ∧ textRank (h :: rest) p < b+1)) =
          rest.filter (fun p => decide (p < t ∧ textRank rest p < b)) := by
        apply filter_eq_on_members
        intro p m
        have ne := Nat.ne_of_lt (prior p m)
        simp [textRank, ne, Nat.add_comm] <;> omega
      have head : decide (h < t ∧ textRank (h :: rest) h < b+1) = true := by
        simp [first, textRank]
      rw [List.filter_cons_of_pos (p := fun p => decide (p < t ∧ textRank (h :: rest) p < b+1)) rest head, filtered]
      simp [tail]

theorem I3_load_before_unreached_position (items : List SourceItem) (ordered : sourceOrdered items)
    (b figurePos : Nat) (beyond : b ≤ textBeforeCount items figurePos) :
    ((sourceTextPositions items).filter
      (fun p => decide (p < figurePos) && textHereAtBreak items b p)).length = b := by
  let ps := sourceTextPositions items
  have filters : ps.filter (fun p => decide (p < figurePos) && textHereAtBreak items b p) =
      ps.filter (fun p => decide (p < figurePos ∧ textRank ps p < b)) := by
    apply filter_eq_on_members
    intro p m
    have eq := I3_text_here_iff_source_rank items ordered p b ((I3_source_text_position_member items p).mp m)
    cases hp : textHereAtBreak items b p with
    | false =>
      have absent : ¬ textRank ps p < b := by intro h; have := eq.mpr h; simp [hp] at this
      simp [absent]
    | true =>
      have yes : textRank ps p < b := eq.mp hp
      simp [yes]
  change (ps.filter _).length = b
  rw [filters]
  exact placed_count_before_any_position ps figurePos b (I3_source_text_positions_ordered items ordered)
    (by simpa [I3_source_text_before_count, ps] using beyond)

theorem I3_alloy_load_before_missed_target (items : List SourceItem)
    (ordered : sourceOrdered items) (b t : Nat)
    (missed : textHereAtBreak items b t = false) :
    ((sourceTextPositions items).filter (fun p => decide (p < t) && textHereAtBreak items b p)).length = b := by
  apply I3_load_before_unreached_position items ordered b t
  change decide (textBeforeCount items t < b) = false at missed
  exact Nat.le_of_not_lt (fun lt => by simp [lt] at missed)

theorem I3_figure_rows_before_missed_target (count : Nat) (kept : Nat → Bool)
    (size pos : Nat → Nat) (items : List SourceItem) (b t : Nat)
    (member : .text t ∈ items) (missed : textHereAtBreak items b t = false)
    (uniquePos : ∀ f, f < count → pos f ≠ t)
    (ordered : ∀ f, f < count → kept f = true →
       ∀ p, .text p ∈ items → p < pos f → textHereAtBreak items b p = true) :
    keptRowsThrough (fun f => kept f && decide (pos f < t)) size count =
      keptRowsThrough kept size count := by
  have exactAt : ∀ f, f < count → (kept f && decide (pos f < t)) = kept f := by
    intro f bound
    cases yes : kept f with
    | false => rfl
    | true =>
      have le := I3_figure_after_unplaced_target_impossible items t (pos f) b member
        missed (ordered f bound yes)
      have diff := uniquePos f bound
      have lt : pos f < t := by omega
      simp [lt]
  have eq : ∀ n, n ≤ count →
      keptRowsThrough (fun f => kept f && decide (pos f < t)) size n =
        keptRowsThrough kept size n := by
    intro n
    induction n with
    | zero => intro _; rfl
    | succ n ih =>
      intro upper
      simp only [keptRowsThrough, exactAt n (by omega), ih (by omega)]
  exact eq count (Nat.le_refl _)

/- Extending a text break cannot change which need applies to a text
   already placed. A figure before that text had also been reached at
   the old break, so its room check and whether it was waiting are the
   same at both breaks. The same argument also covers rank b, the one
   new text placed when the break advances from b to b+1. -/
private theorem kept_before_reached_text (items : List SourceItem) (positions : Nat → Nat)
    (room : Nat → Bool) (b c t f : Nat)
    (rankOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (old : textBeforeCount items t ≤ b) (extendsTo : b ≤ c) (before : positions f < t) :
    let rank := fun i => textBeforeCount items (positions i)
    let kept := fun brk => greedyFigure (fun i => decide (rank i ≤ brk)) room
    kept b f = kept c f := by
  let rank := fun i => textBeforeCount items (positions i)
  let kept := fun brk => greedyFigure (fun i => decide (rank i ≤ brk)) room
  have ranks : ∀ i j, i ≤ j → rank i ≤ rank j := fun i j le =>
    I3_text_before_source_monotone items _ _ (rankOrder i j le)
  have prev := I3_text_before_source_monotone items _ _ (Nat.le_of_lt before)
  have rb : rank f ≤ b := Nat.le_trans prev old
  have rc : rank f ≤ c := Nat.le_trans rb extendsTo
  have bh := I3_figure_break_prefix rank ranks room b f
  have ch := I3_figure_break_prefix rank ranks room c f
  have equiv : kept b f = true ↔ kept c f = true := by
    change greedyFigure _ _ _ = true ↔ greedyFigure _ _ _ = true
    rw [bh, ch]
    simp [rb, rc]
  change kept b f = kept c f
  cases hb : kept b f <;> cases hc : kept c f <;> simp [hb, hc] at equiv ⊢

theorem I3_need_text_target_stable (items : List SourceItem) (positions : Nat → Nat)
    (room : Nat → Bool) (b c t n count : Nat) (block : Nat → Prop)
    (rankOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (old : textBeforeCount items t ≤ b) (extendsTo : b ≤ c) :
    let rank := fun f => textBeforeCount items (positions f)
    let kept := fun brk => greedyFigure (fun i => decide (rank i ≤ brk)) room
    needTargetsText n t block positions count (kept b) ↔
      needTargetsText n t block positions count (kept c) := by
  let rank := fun f => textBeforeCount items (positions f)
  let kept := fun brk => greedyFigure (fun i => decide (rank i ≤ brk)) room
  have stable : ∀ f, positions f < t → kept b f = kept c f :=
    fun f before => kept_before_reached_text items positions room b c t f rankOrder old extendsTo before
  have wait : ∀ f, positions f < t → (figureWaits (kept b) f ↔ figureWaits (kept c) f) := by
    intro f before
    have earlier : ∀ g, g < f → kept b g = kept c g := by
      intro g prior
      exact stable g (Nat.lt_of_le_of_lt (rankOrder g f (Nat.le_of_lt prior)) before)
    constructor
    · rintro ⟨sent, g, prior, firstSent⟩
      exact ⟨(stable f before) ▸ sent, g, prior, (earlier g prior) ▸ firstSent⟩
    · rintro ⟨sent, g, prior, firstSent⟩
      exact ⟨(stable f before).symm ▸ sent, g, prior, (earlier g prior).symm ▸ firstSent⟩
  change needTargetsText n t block positions count (kept b) ↔ _
  constructor
  · rintro ⟨nt, text, first, skips⟩
    exact ⟨nt, text, first, fun f bound after before =>
      (wait f before).mp (skips f bound after before)⟩
  · rintro ⟨nt, text, first, skips⟩
    exact ⟨nt, text, first, fun f bound after before =>
      (wait f before).mpr (skips f bound after before)⟩

theorem I3_figure_rows_stable_before_text (items : List SourceItem) (positions size : Nat → Nat)
    (room : Nat → Bool) (b c t count : Nat)
    (rankOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (old : textBeforeCount items t ≤ b) (extendsTo : b ≤ c) :
    let rank := fun i => textBeforeCount items (positions i)
    let kept := fun brk => greedyFigure (fun i => decide (rank i ≤ brk)) room
    keptRowsThrough (fun i => kept b i && decide (positions i < t)) size count =
      keptRowsThrough (fun i => kept c i && decide (positions i < t)) size count := by
  let rank := fun i => textBeforeCount items (positions i)
  let kept := fun brk => greedyFigure (fun i => decide (rank i ≤ brk)) room
  have same : (fun i => kept b i && decide (positions i < t)) =
      (fun i => kept c i && decide (positions i < t)) := by
    funext i
    by_cases before : positions i < t
    · have eq := kept_before_reached_text items positions room b c t i rankOrder old extendsTo before
      change kept b i = kept c i at eq
      simp [before, eq]
    · simp [before]
  change keptRowsThrough _ _ _ = keptRowsThrough _ _ _
  rw [same]

theorem I3_text_rows_stable_before_reached_target (items : List SourceItem)
    (ordered : sourceOrdered items) (space : Nat → Bool) (b c t : Nat)
    (target : .text t ∈ items) (reached : textBeforeCount items t ≤ b) (extendsTo : b ≤ c) :
    let rows := fun brk => ((sourceTextPositions items).filter
      (fun p => decide (p < t) && !space p && textHereAtBreak items brk p)).length
    rows b = rows c := by
  have equal : (sourceTextPositions items).filter
      (fun p => decide (p < t) && !space p && textHereAtBreak items b p) =
      (sourceTextPositions items).filter
      (fun p => decide (p < t) && !space p && textHereAtBreak items c p) := by
    apply filter_eq_on_members
    intro p pm
    by_cases prior : p < t
    · have tm := (I3_source_text_position_member items t).mpr target
      have rank := I3_text_rank_preserves_order _ (I3_source_text_positions_ordered items ordered)
        p t pm tm prior
      have count := I3_count_earlier_text_eq_rank _ (I3_source_text_positions_ordered items ordered) t tm
      have actual := I3_source_text_before_count items t
      have text := (I3_source_text_position_member items p).mp pm
      have old := (I3_text_here_iff_source_rank items ordered p b text).mpr (by omega)
      have new := (I3_text_here_iff_source_rank items ordered p c text).mpr (by omega)
      simp [old, new]
    · simp [prior]
  exact congrArg List.length equal

def placedBeforeNeedSource (used count brk : Nat) (items : List SourceItem)
    (positions size : Nat → Nat) (space kept : Nat → Bool) (t : Nat) : Nat :=
  used + ((sourceTextPositions items).filter
    (fun p => decide (p < t) && !space p && textHereAtBreak items brk p)).length +
    keptRowsThrough (fun i => kept i && decide (positions i < t)) size count

def needAtPlacedText (used capacity count : Nat) (items : List SourceItem)
    (positions size : Nat → Nat) (space : Nat → Bool) (needs : List (Nat × Nat))
    (brk : Nat) (kept : Nat → Bool) (target : Nat) : Prop :=
  let rows := placedBeforeNeedSource used count brk items positions size space kept target
  ∀ need ∈ needs, needTargetsText need.1 target
    (fun p => .text p ∈ items ∧ space p = false) positions count kept →
    rows = 0 ∨ need.2 ≤ capacity - rows

theorem I3_text_need_checks_preserved (used capacity count b c t : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items) (positions size : Nat → Nat)
    (space room : Nat → Bool) (needs : List (Nat × Nat))
    (rankOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (target : .text t ∈ items) (reached : textBeforeCount items t ≤ b) (extendsTo : b ≤ c) :
    let kept := fun brk => greedyFigure (fun i => decide (textBeforeCount items (positions i) ≤ brk)) room
    needAtPlacedText used capacity count items positions size space needs b (kept b) t ↔
      needAtPlacedText used capacity count items positions size space needs c (kept c) t := by
  have textRows := I3_text_rows_stable_before_reached_target items ordered space b c t target reached extendsTo
  have figureRows := I3_figure_rows_stable_before_text items positions size room b c t count rankOrder reached extendsTo
  dsimp only at textRows figureRows
  dsimp only [needAtPlacedText, placedBeforeNeedSource]
  rw [textRows, figureRows]
  constructor
  · intro old need member atNew
    exact old need member ((I3_need_text_target_stable items positions room b c t _ count _
      rankOrder reached extendsTo).mpr atNew)
  · intro new need member atOld
    exact new need member ((I3_need_text_target_stable items positions room b c t _ count _
      rankOrder reached extendsTo).mp atOld)

/- All needs of the same text target see the same occupied height,
   even with waiting figures between the written needs. They can
   therefore share the record-high check in spaceKeeps35. This equality
   also establishes the single-need comparison in spaceKeeps. -/
private theorem written_need_load_at_target
    (used count b n t : Nat) (items : List SourceItem)
    (positions size : Nat → Nat) (space kept : Nat → Bool)
    (uniqueText : ∀ p, .text p ∈ items → p ≠ n)
    (uniqueFigure : ∀ i, positions i ≠ n)
    (beforeTarget : n < t)
    (noBlock : ∀ p, (.text p ∈ items ∧ space p = false) → n < p → p < t → False)
    (waits : ∀ i, i < count → n < positions i → positions i < t → figureWaits kept i) :
    placedBeforeNeedSource used count b items positions size space kept n =
      placedBeforeNeedSource used count b items positions size space kept t := by
  have text : (sourceTextPositions items).filter
      (fun p => decide (p < n) && !space p && textHereAtBreak items b p) =
      (sourceTextPositions items).filter
      (fun p => decide (p < t) && !space p && textHereAtBreak items b p) := by
    apply filter_eq_on_members
    intro p pm
    have member := (I3_source_text_position_member items p).mp pm
    by_cases before : p < n
    · have earlier := Nat.lt_trans before beforeTarget
      simp [before, earlier]
    · by_cases between : p < t
      · cases sp : space p with
        | true => simp [sp]
        | false =>
          have diff := uniqueText p member
          exact (noBlock p ⟨member, sp⟩ (by omega) between).elim
      · simp [before, between]
  have figures : ∀ k, k ≤ count →
      keptRowsThrough (fun i => kept i && decide (positions i < n)) size k =
        keptRowsThrough (fun i => kept i && decide (positions i < t)) size k := by
    intro k
    induction k with
    | zero => intro _; rfl
    | succ k ih =>
      intro bound
      have equal : (kept k && decide (positions k < n)) = (kept k && decide (positions k < t)) := by
        by_cases before : positions k < n
        · have earlier := Nat.lt_trans before beforeTarget
          simp [before, earlier]
        · by_cases between : positions k < t
          · have diff := uniqueFigure k
            have sent := (waits k (by omega) (by omega) between).1
            simp [sent]
          · simp [before, between]
      simp only [keptRowsThrough, ih (by omega), equal]
  unfold placedBeforeNeedSource
  rw [text, figures _ (Nat.le_refl _)]

theorem I3_load_at_text_need_agrees_with_target
    (used count b n t : Nat) (items : List SourceItem)
    (positions size : Nat → Nat) (space kept : Nat → Bool)
    (uniqueText : ∀ p, .text p ∈ items → p ≠ n)
    (uniqueFigure : ∀ i, positions i ≠ n)
    (target : needTargetsText n t (fun p => .text p ∈ items ∧ space p = false)
      positions count kept) :
    placedBeforeNeedSource used count b items positions size space kept n =
      placedBeforeNeedSource used count b items positions size space kept t := by
  exact written_need_load_at_target used count b n t items positions size space kept uniqueText
    uniqueFigure target.1 target.2.2.1 target.2.2.2

theorem I3_load_at_figure_need_agrees_with_target
    (used count b n f : Nat) (items : List SourceItem) (positions size : Nat → Nat)
    (space kept : Nat → Bool) (order : ∀ i j, i ≤ j → positions i ≤ positions j)
    (uniqueText : ∀ p, .text p ∈ items → p ≠ n) (uniqueFigure : ∀ i, positions i ≠ n)
    (target : needTargetsFigure n positions (fun p => .text p ∈ items ∧ space p = false) f (figureWaits kept)) :
    placedBeforeNeedSource used count b items positions size space kept n =
      placedBeforeNeedSource used count b items positions size space kept (positions f) := by
  apply written_need_load_at_target used count b n (positions f) items positions size space kept
    uniqueText uniqueFigure target.1 target.2.2.1
  intro i _ after before
  have lt : i < f := by
    apply Nat.lt_of_not_ge
    intro ge
    have contradicts := order f i ge
    omega
  exact target.2.2.2 i lt after

def sourceNeedAtTarget (n t count : Nat) (items : List SourceItem)
    (positions : Nat → Nat) (space kept : Nat → Bool) : Prop :=
  needTargetsText n t (fun p => .text p ∈ items ∧ space p = false) positions count kept

def writtenGroupFits (capacity previous : Nat) (load : Nat → Nat) :
    List (Nat × Nat) → Prop
  | [] => True
  | (n, h) :: ns =>
      (previous < h → h ≤ capacity - load n) ∧
      writtenGroupFits capacity (max previous h) load ns

theorem I3_written_group_iff_target_max
    (capacity previous rows : Nat) (load : Nat → Nat) (ns : List (Nat × Nat))
    (equal : ∀ n ∈ ns, load n.1 = rows) :
    writtenGroupFits capacity previous load ns ↔
      recordNeedsFit (capacity - rows) previous (ns.map Prod.snd) := by
  induction ns generalizing previous with
  | nil => rfl
  | cons head tail ih =>
    obtain ⟨pos, height⟩ := head
    have own := equal (pos,height) (List.mem_cons_self _ _)
    have rest := ih (max previous height) (fun n m => equal n (List.mem_cons_of_mem _ m))
    simp only [writtenGroupFits, List.map_cons, recordNeedsFit, Prod.snd, own, rest]

theorem I3_written_text_needs_satisfy_P1
    (used capacity count b t : Nat) (items : List SourceItem)
    (positions size : Nat → Nat) (space kept : Nat → Bool) (needs : List (Nat × Nat))
    (distinctText : ∀ n ∈ needs, ∀ p, .text p ∈ items → p ≠ n.1)
    (distinctFigure : ∀ n ∈ needs, ∀ i, positions i ≠ n.1) :
    let load := placedBeforeNeedSource used count b items positions size space kept
    let group := needs.filter (fun n => @decide (sourceNeedAtTarget n.1 t count items positions space kept)
      (Classical.propDecidable _))
    writtenGroupFits capacity 0 load group →
      needAtPlacedText used capacity count items positions size space needs b kept t := by
  let load := placedBeforeNeedSource used count b items positions size space kept
  let group := needs.filter (fun n => @decide (sourceNeedAtTarget n.1 t count items positions space kept)
    (Classical.propDecidable _))
  change writtenGroupFits capacity 0 load group → _
  intro fit n member target
  apply Or.inr
  have equal : ∀ m ∈ group, load m.1 = load t := by
    intro m inGroup
    obtain ⟨present, selected⟩ := List.mem_filter.mp inGroup
    exact I3_load_at_text_need_agrees_with_target used count b m.1 t items positions size space kept
      (distinctText m present) (distinctFigure m present) (decide_eq_true_eq.mp selected)
  have records := (I3_written_group_iff_target_max capacity 0 (load t) load group equal).mp fit
  apply (I3_record_needs_fit_iff_all _ 0 _ (Nat.zero_le _)).mp records n.2
  exact List.mem_map.mpr ⟨n, List.mem_filter.mpr ⟨member, decide_eq_true_eq.mpr target⟩, rfl⟩

/- Extending a break to include the previously missed target preserves
   P1 for every text, not just that target. The newly placed text is
   either the target or a space between the need and the target; no
   needNext can target a space. -/
theorem I3_extend_prefix_preserves_all_text_needs
    (used capacity count b t : Nat) (items : List SourceItem) (ordered : sourceOrdered items)
    (positions size : Nat → Nat) (space room : Nat → Bool) (needs : List (Nat × Nat))
    (posOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (target : .text t ∈ items) (missed : textHereAtBreak items b t = false)
    (onlySpaces : ∀ p, .text p ∈ items → p < t →
       textHereAtBreak items b p = false → space p = true)
    (distinctText : ∀ n ∈ needs, ∀ p, .text p ∈ items → p ≠ n.1)
    (distinctFigure : ∀ n ∈ needs, ∀ i, positions i ≠ n.1) :
    let kept := fun brk => greedyFigure (fun i => decide (textBeforeCount items (positions i) ≤ brk)) room
    let group := needs.filter (fun n => @decide (sourceNeedAtTarget n.1 t count items positions space (kept b))
      (Classical.propDecidable _))
    writtenGroupFits capacity 0 (placedBeforeNeedSource used count b items positions size space (kept b)) group →
    (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
      needAtPlacedText used capacity count items positions size space needs b (kept b) p) →
    (∀ p, .text p ∈ items → textHereAtBreak items (b+1) p = true →
      needAtPlacedText used capacity count items positions size space needs (b+1) (kept (b+1)) p) := by
  dsimp only
  intro records old p member placed
  have rank : textBeforeCount items p ≤ b := by
    change decide (textBeforeCount items p < b+1) = true at placed
    have := decide_eq_true_eq.mp placed
    omega
  apply (I3_text_need_checks_preserved used capacity count b (b+1) p items ordered positions
    size space room needs posOrder member rank (by omega)).mp
  cases oldPlaced : textHereAtBreak items b p with
  | true => exact old p member oldPlaced
  | false =>
    by_cases eq : p = t
    · subst p
      exact I3_written_text_needs_satisfy_P1 _ _ _ _ _ _ _ _ _ _ _ distinctText distinctFigure records
    · have before : p < t := by
        apply Classical.byContradiction
        intro later
        have pm := (I3_source_text_position_member items p).mpr member
        have tm := (I3_source_text_position_member items t).mpr target
        have strict := I3_text_rank_preserves_order _ (I3_source_text_positions_ordered items ordered)
          t p tm pm (by omega)
        have index := (I3_text_here_iff_source_rank items ordered p (b+1) member).mp placed
        have tHere := (I3_text_here_iff_source_rank items ordered t b target).mpr (by omega)
        simp [missed] at tHere
      have sp := onlySpaces p member before oldPlaced
      intro n _ selected
      have notSpace := selected.2.1.2
      simp [sp] at notSpace

theorem I3_missed_target_can_extend_without_new_figures
    (used capacity count b t blank : Nat) (items : List SourceItem)
    (ordered : sourceOrdered items) (positions size : Nat → Nat)
    (space room waiting keptAt : Nat → Bool) (needs : List (Nat × Nat))
    (top : Bool) (firstPart : Nat) (positivePart : 0 < firstPart)
    (posOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (target : .text t ∈ items) (missed : textHereAtBreak items b t = false)
    (onlySpaces : ∀ p, .text p ∈ items → p < t → textHereAtBreak items b p = false → space p = true)
    (distinctText : ∀ n ∈ needs, ∀ p, .text p ∈ items → p ≠ n.1)
    (distinctFigure : ∀ n ∈ needs, ∀ i, positions i ≠ n.1)
    (distinctTarget : ∀ i, i < count → positions i ≠ t) :
    let kept := fun brk => greedyFigure (fun i => decide (textBeforeCount items (positions i) ≤ brk)) room
    let group := needs.filter (fun n => @decide (sourceNeedAtTarget n.1 t count items positions space (kept b))
      (Classical.propDecidable _))
    (∀ i, i < count → kept (b+1) i = kept b i) →
    (∀ p, .figure p ∈ items → keptAt p = true → ∃ i, i < count ∧ kept (b+1) i = true ∧ positions i = p) →
    (∀ i, i < count → kept b i = true → ∀ p, .text p ∈ items → p < positions i → textHereAtBreak items b p = true) →
    used + ((sourceTextPositions items).filter (fun p => decide (p < t) && textHereAtBreak items b p)).length +
      keptRowsThrough (fun i => kept b i && decide (positions i < t)) size count +
      (if blank < t ∧ top = false then 1 else 0) + firstPart ≤ capacity →
    writtenGroupFits capacity 0 (placedBeforeNeedSource used count b items positions size space (kept b)) group →
    (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
      needAtPlacedText used capacity count items positions size space needs b (kept b) p) →
    used + (b+1) + keptRowsThrough (kept (b+1)) size count +
      (if blankPlacedFromSource blank waiting items (textHereAtBreak items (b+1)) keptAt top then 1 else 0) ≤ capacity ∧
    (∀ p, .text p ∈ items → textHereAtBreak items (b+1) p = true →
      needAtPlacedText used capacity count items positions size space needs (b+1) (kept (b+1)) p) := by
  let kept := fun brk => greedyFigure (fun i => decide (textBeforeCount items (positions i) ≤ brk)) room
  dsimp only
  intro noNew source order load records p1
  change ∀ i, i < count → kept (b+1) i = kept b i at noNew
  have sameSum : ∀ n, n ≤ count → keptRowsThrough (kept (b+1)) size n = keptRowsThrough (kept b) size n := by
    intro n
    induction n with
    | zero => intro _; rfl
    | succ n ih => intro bound; simp only [keptRowsThrough, noNew n (by omega), ih (by omega)]
  have allFigures := I3_figure_rows_before_missed_target count (kept b) size positions items b t
    target missed distinctTarget order
  have localRoom : used + b + keptRowsThrough (kept b) size count +
      (if blank < t ∧ top = false then 1 else 0) + firstPart ≤ capacity := by
    rw [I3_alloy_load_before_missed_target items ordered b t missed, allFigures] at load
    exact load
  constructor
  · apply I3_unchanged_figures_extended_fits capacity used b count size positions blank t items
      waiting keptAt (kept (b+1)) top firstPart positivePart source ordered target missed
    · intro i bound new
      change kept (b+1) i = true at new
      rw [noNew i bound] at new
      exact order i bound new
    · rw [sameSum count (Nat.le_refl _)]
      exact localRoom
  · exact I3_extend_prefix_preserves_all_text_needs _ _ _ _ _ _ ordered _ _ _ _ _ posOrder target
      missed onlySpaces distinctText distinctFigure records p1

theorem I3_missed_text_target_extends
    (used capacity count b t blank : Nat) (items : List SourceItem)
    (ordered : sourceOrdered items) (positions size : Nat → Nat)
    (space room waiting keptAt : Nat → Bool) (needs : List (Nat × Nat))
    (top : Bool) (firstPart : Nat) (positivePart : 0 < firstPart)
    (posOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (target : .text t ∈ items) (missed : textHereAtBreak items b t = false)
    (onlySpaces : ∀ p, .text p ∈ items → p < t → textHereAtBreak items b p = false → space p = true)
    (distinctText : ∀ n ∈ needs, ∀ p, .text p ∈ items → p ≠ n.1)
    (distinctFigure : ∀ n ∈ needs, ∀ i, positions i ≠ n.1)
    (distinctTarget : ∀ i, i < count → positions i ≠ t) :
    let kept := fun brk => greedyFigure (fun i => decide (textBeforeCount items (positions i) ≤ brk)) room
    let group := needs.filter (fun n => @decide (sourceNeedAtTarget n.1 t count items positions space (kept b))
      (Classical.propDecidable _))
    (∀ i, i < count → 0 < size i) →
    (∀ i, i < count → kept (b+1) i = true →
      used + textBeforeCount items (positions i) + keptRowsThrough (kept (b+1)) size (i+1) +
        (if blank < positions i ∧ top = false then 1 else 0) ≤ capacity) →
    (∀ p, .figure p ∈ items → keptAt p = true → ∃ i, i < count ∧ kept (b+1) i = true ∧ positions i = p) →
    (∀ i, i < count → kept b i = true → ∀ p, .text p ∈ items → p < positions i → textHereAtBreak items b p = true) →
    used + ((sourceTextPositions items).filter (fun p => decide (p < t) && textHereAtBreak items b p)).length +
      keptRowsThrough (fun i => kept b i && decide (positions i < t)) size count +
      (if blank < t ∧ top = false then 1 else 0) + firstPart ≤ capacity →
    writtenGroupFits capacity 0 (placedBeforeNeedSource used count b items positions size space (kept b)) group →
    (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
      needAtPlacedText used capacity count items positions size space needs b (kept b) p) →
    used + (b+1) + keptRowsThrough (kept (b+1)) size count +
      (if blankPlacedFromSource blank waiting items (textHereAtBreak items (b+1)) keptAt top then 1 else 0) ≤ capacity ∧
    (∀ p, .text p ∈ items → textHereAtBreak items (b+1) p = true →
      needAtPlacedText used capacity count items positions size space needs (b+1) (kept (b+1)) p) := by
  let kept := fun brk => greedyFigure (fun i => decide (textBeforeCount items (positions i) ≤ brk)) room
  dsimp only
  intro positive figureRoom source order load records p1
  by_cases newFigure : ∃ j, j < count ∧ kept b j = false ∧ kept (b+1) j = true
  · constructor
    · apply I3_extended_figure_prefix_fits capacity used b count (kept (b+1)) (kept b)
        size positions blank items waiting keptAt top posOrder source newFigure positive
      · intro f _ placed
        have ranks := fun i j (le : i ≤ j) =>
          I3_text_before_source_monotone items _ _ (posOrder i j le)
        exact ((I3_figure_break_prefix (fun i => textBeforeCount items (positions i)) ranks room
          (b+1) f).mp placed).1
      · intro f _ absent present
        exact I3_new_figure_at_extended_break _ (fun i j le =>
          I3_text_before_source_monotone items _ _ (posOrder i j le)) room b f absent present
      · exact figureRoom
    · exact I3_extend_prefix_preserves_all_text_needs _ _ _ _ _ _ ordered _ _ _ _ _ posOrder target
        missed onlySpaces distinctText distinctFigure records p1
  · apply I3_missed_target_can_extend_without_new_figures used capacity count b t blank items
      ordered positions size space room waiting keptAt needs top firstPart positivePart posOrder target
      missed onlySpaces distinctText distinctFigure distinctTarget _ source order load records p1
    intro f bound
    change kept (b+1) f = kept b f
    cases old : kept b f with
    | false =>
      cases next : kept (b+1) f with
      | false => rfl
      | true => exact (newFigure ⟨f, bound, old, next⟩).elim
    | true =>
      have ranks := fun i j (le : i ≤ j) =>
        I3_text_before_source_monotone items _ _ (posOrder i j le)
      have prior := (I3_figure_break_prefix _ ranks room b f).mp old
      exact (I3_figure_break_prefix _ ranks room (b+1) f).mpr ⟨by omega, prior.2⟩

/- P7 tests fit at its target, but a figure needs every preceding text
   placed. If a space was skipped after the need, the break can advance
   to that space. In contrast to a text target no newly placed ordinary
   text needs to be admitted: the whole intervening text prefix consists
   of spaces. -/
theorem I3_space_before_target_figure_preserves_text_needs
    (used capacity count b n f : Nat) (items : List SourceItem) (ordered : sourceOrdered items)
    (positions size : Nat → Nat) (space room : Nat → Bool) (needs : List (Nat × Nat))
    (posOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (beyond : b < textBeforeCount items (positions f))
    (needReached : ∀ p, .text p ∈ items → p < n → textHereAtBreak items b p = true)
    (posUnique : ∀ p, .text p ∈ items → p ≠ n) :
    let kept := fun brk => greedyFigure (fun i => decide (textBeforeCount items (positions i) ≤ brk)) room
    needTargetsFigure n positions (fun p => .text p ∈ items ∧ space p = false) f (figureWaits (kept b)) →
    (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
      needAtPlacedText used capacity count items positions size space needs b (kept b) p) →
    (∀ p, .text p ∈ items → textHereAtBreak items (b+1) p = true →
      needAtPlacedText used capacity count items positions size space needs (b+1) (kept (b+1)) p) := by
  dsimp only
  intro target old p member placed
  have rank : textBeforeCount items p ≤ b := by
    change decide (textBeforeCount items p < b+1) = true at placed
    have := decide_eq_true_eq.mp placed
    omega
  apply (I3_text_need_checks_preserved used capacity count b (b+1) p items ordered positions
    size space room needs posOrder member rank (by omega)).mp
  cases previous : textHereAtBreak items b p with
  | true => exact old p member previous
  | false =>
    have beforeFigure : p < positions f := by
      apply Classical.byContradiction
      intro late
      have bound := I3_text_before_source_monotone items (positions f) p (by omega)
      omega
    have afterNeed : n < p := by
      apply Classical.byContradiction
      intro early
      have distinct := posUnique p member
      have yes := needReached p member (by omega)
      simp [previous] at yes
    cases isSpace : space p with
    | false => exact (target.2.2.1 p ⟨member, isSpace⟩ afterNeed beforeFigure).elim
    | true =>
      intro need _ selected
      have nonSpace := selected.2.1.2
      simp [isSpace] at nonSpace

theorem I3_space_extension_fits_before_unreached_figure
    (used capacity count b f blank : Nat) (items : List SourceItem)
    (positions size : Nat → Nat) (waiting keptAt kept : Nat → Bool) (top : Bool)
    (ordered : sourceOrdered items)
    (beyond : b < textBeforeCount items (positions f)) (positive : 0 < size f)
    (source : ∀ p, .figure p ∈ items → keptAt p = true →
       ∃ i, i < count ∧ kept i = true ∧ positions i = p)
    (eligible : ∀ i, i < count → kept i = true → textBeforeCount items (positions i) ≤ b)
    (room : used + ((sourceTextPositions items).filter
      (fun p => decide (p < positions f) && textHereAtBreak items b p)).length +
      keptRowsThrough (fun i => kept i && decide (positions i < positions f)) size count +
      (if blank < positions f ∧ top = false then 1 else 0) + size f ≤ capacity) :
    used + (b+1) + keptRowsThrough kept size count +
      (if blankPlacedFromSource blank waiting items (textHereAtBreak items (b+1)) keptAt top
       then 1 else 0) ≤ capacity := by
  have earlier : ∀ i, i < count → kept i = true → positions i < positions f := by
    intro i bound yes
    apply Classical.byContradiction
    intro late
    have ranks := I3_text_before_source_monotone items (positions f) (positions i) (by omega)
    have reached := eligible i bound yes
    omega
  have equal : ∀ n, n ≤ count →
      keptRowsThrough (fun i => kept i && decide (positions i < positions f)) size n =
        keptRowsThrough kept size n := by
    intro n
    induction n with
    | zero => intro _; rfl
    | succ n ih =>
      intro bound
      have same : (kept n && decide (positions n < positions f)) = kept n := by
        cases yes : kept n with
        | false => rfl
        | true => simp [earlier n (by omega) yes]
      simp only [keptRowsThrough, same, ih (by omega)]
  rw [I3_load_before_unreached_position items ordered b (positions f) (Nat.le_of_lt beyond),
    equal count (Nat.le_refl _)] at room
  apply I3_extension_fits_before_target capacity used b count size positions blank (positions f)
    items waiting keptAt kept top (size f) positive source _ _ room
  · intro p _ placed
    apply Classical.byContradiction
    intro later
    have rank := I3_text_before_source_monotone items (positions f) p (by omega)
    change decide (textBeforeCount items p < b+1) = true at placed
    have := decide_eq_true_eq.mp placed
    omega
  · exact fun i bound yes => Nat.le_of_lt (earlier i bound yes)

/- Construct the fully feasible initial break for an occupied column with
   two figures and no blank. There are no placed texts; the only figures
   reachable at break zero precede every text. Their size and need tests
   alone determine whether either may stay. -/
theorem I3_need_initial_two_figures (capacity used : Nat)
    (textBefore nonSpaceBefore size positions : Nat → Nat) (block : Nat → Prop)
    (needs : List (Nat × Nat)) (usedFits : used ≤ capacity) :
    ∃ kept : Nat → Bool,
      figures27Model 2 capacity used (fun i => decide (textBefore i ≤ 0))
        textBefore nonSpaceBefore size positions (fun _ => false) block needs kept ∧
      figuresInOrder 2 kept ∧ used + keptRowsThrough kept size 2 ≤ capacity := by
  let ready := fun i => decide (textBefore i ≤ 0)
  let static := needFigureStatic capacity used textBefore nonSpaceBefore size positions
    (fun _ => false) block needs
  let room := fun i => @decide (static i) (Classical.propDecidable _)
  let kept := greedyFigure ready room
  have basic := I3_greedyFigures_rule 2 ready room
  have rule : figuresRule 2 kept (fun i => ready i = true) static := by
    simpa only [room, decide_eq_true_eq] using basic
  have full := figures27_of_static _ _ _ _ _ _ _ _ _ _ _ _ rule
  refine ⟨kept, full, I3_figuresRule_implies_figuresInOrder _ _ _ _ rule, ?_⟩
  cases one : kept 1 with
  | true =>
    have parts := (rule 1 (by decide)).mp one
    have zero := parts.2.1 0 (by decide)
    have room := parts.2.2.1
    simp [keptRowsThrough, zero, one]
    simp [figureHasRoom, priorFigureLines, show List.range 1 = [0] from rfl] at room
    omega
  | false =>
    cases zero : kept 0 with
    | false => simpa [keptRowsThrough, one, zero] using usedFits
    | true =>
      have room := ((rule 0 (by decide)).mp zero).2.2.1
      simp [keptRowsThrough, zero, one]
      simp [figureHasRoom, priorFigureLines, show List.range 0 = [] from rfl] at room
      omega

/- Reuse the source-level zero-break construction (including its actual
   waiting-figure and following-blank predicates). The static need
   condition is conjoined with text readiness; figures27_of_static
   restores the dynamic placement-dependent needNext afterwards. -/
theorem I3_need_initial_two_figures_blank
    (capacity used blank first second firstSize secondSize : Nat)
    (items : List SourceItem) (space : Nat → Bool) (needs : List (Nat × Nat))
    (usedFits : used ≤ capacity) (ordered : first < second)
    (diffFirst : blank ≠ first) (diffSecond : blank ≠ second)
    (firstIn : .figure first ∈ items) (secondIn : .figure second ∈ items)
    (onlyTwo : ∀ p, .figure p ∈ items → p = first ∨ p = second) :
    let positions := fun f : Nat => if f = 0 then first else second
    let size := fun f : Nat => if f = 0 then firstSize else secondSize
    let textBefore := fun f => textBeforeCount items (positions f)
    let nonSpaceBefore := fun f => ((sourceTextPositions items).filter
      (fun p => decide (p < positions f) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    let mask := beforeBlankMask first second blank
    ∃ top : Bool, ∃ kept : Nat → Bool, ∃ placed : Bool,
      figures27Model 2 capacity used (fun f => decide (textBefore f ≤ 0))
        textBefore nonSpaceBefore size positions (fun f => !mask f && !top) block needs kept ∧
      top = blankAtTopSource used blank items (fun _ => false)
        (keptAtTwoPositions first second (kept 0) (kept 1)) ∧
      placed = blankPlacedFromSourceFull used blank (waitingAtTwoPositions first second kept)
        items (fun _ => false) (keptAtTwoPositions first second (kept 0) (kept 1)) ∧
      used + (if kept 0 then firstSize else 0) + (if kept 1 then secondSize else 0) +
        (if placed then 1 else 0) ≤ capacity := by
  intro positions size textBefore nonSpaceBefore block mask
  let needOK := fun f => ∀ n ∈ needs,
    needTargetsFigure n.1 positions block f (fun _ => False) →
      used + nonSpaceBefore f + priorFigureLines size f = 0 ∨
      n.2 ≤ capacity - (used + nonSpaceBefore f + priorFigureLines size f)
  let ready := fun f => decide (textBefore f ≤ 0) && @decide (needOK f) (Classical.propDecidable _)
  obtain ⟨top, kept, placed, rule, topEq, blankEq, fits⟩ :=
    I3_blankFigureOrder_arbitrary_source_exists capacity used blank first second firstSize secondSize
      ready textBefore (waitingAtTwoPositions first second) items usedFits ordered diffFirst diffSecond
      firstIn secondIn onlyTwo
  refine ⟨top, kept, placed, ?_, topEq, blankEq, fits⟩
  apply figures27_of_static
  intro f bound
  have actual := rule f bound
  simp only [ready, Bool.and_eq_true, decide_eq_true_eq] at actual
  change kept f = true ↔ decide (textBefore f ≤ 0) = true ∧ _ ∧ _
  rw [decide_eq_true_eq]
  constructor
  · intro includes
    obtain ⟨⟨texts, met⟩, earlier, room⟩ := actual.mp includes
    exact ⟨texts, earlier, room, met⟩
  · rintro ⟨texts, earlier, room, met⟩
    exact actual.mpr ⟨⟨texts, met⟩, earlier, room⟩

/- At an empty column whose first content is text, a break of one is
   feasible. Any figure that stays has exactly one earlier text: the
   first text. If none stays, the blank either precedes the first text
   (so is at the top), or follows it (so has no placed successor). -/
theorem I3_initial_one_text_with_need_figures_fits
    (capacity count first blank : Nat) (items : List SourceItem) (ordered : sourceOrdered items)
    (positions size : Nat → Nat) (kept keptAt waiting : Nat → Bool)
    (positiveCapacity : 0 < capacity) (positiveSize : ∀ i, i < count → 0 < size i)
    (firstContentText : firstContent items = some (.text first))
    (posOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (figIn : ∀ i, i < count → .figure (positions i) ∈ items)
    (source : ∀ p, .figure p ∈ items → keptAt p = true →
      ∃ i, i < count ∧ kept i = true ∧ positions i = p)
    (figRank : ∀ i, i < count → kept i = true → textBeforeCount items (positions i) ≤ 1)
    (room : ∀ i, i < count → kept i = true →
      textBeforeCount items (positions i) + keptRowsThrough kept size (i+1) +
        (if blank < positions i ∧ blankAtTopSource 0 blank items (textHereAtBreak items 1) keptAt = false
         then 1 else 0) ≤ capacity) :
    1 + keptRowsThrough kept size count +
      (if blankPlacedFromSourceFull 0 blank waiting items (textHereAtBreak items 1) keptAt then 1 else 0) ≤ capacity := by
  obtain ⟨firstIn, firstOrder, figsLater⟩ :=
    I3_firstContent_text_before_figures items ordered first firstContentText
  have onlyFirst : ∀ p, .text p ∈ items → textHereAtBreak items 1 p = true → p = first :=
    fun p member here => I3_first_break_here_is_first_text items first firstIn firstOrder p member here
  by_cases any : ∃ j, j < count ∧ kept j = true
  · have newFig : ∃ j, j < count ∧ (false = false) ∧ kept j = true := by
      obtain ⟨j, bound, yes⟩ := any
      exact ⟨j, bound, rfl, yes⟩
    apply I3_extended_figure_prefix_fits capacity 0 0 count kept (fun _ => false) size positions
      blank items waiting keptAt _ posOrder source newFig positiveSize figRank _ (by simpa using room)
    intro i bound _ yes
    have earlier := figsLater _ (figIn i bound)
    have member : .text first ∈ items.filter (earlierTextItem (positions i)) :=
      List.mem_filter.mpr ⟨firstIn, by simp [earlierTextItem, earlier]⟩
    have notZero : textBeforeCount items (positions i) ≠ 0 := by
      intro zero
      change (items.filter (earlierTextItem (positions i))).length = 0 at zero
      have nil := List.length_eq_zero.mp zero
      rw [nil] at member
      cases member
    have upper := figRank i bound yes
    omega
  · have noKept : ∀ i, i < count → kept i = false := by
      intro i bound
      cases yes : kept i with
      | false => rfl
      | true => exact (any ⟨i, bound, yes⟩).elim
    have zero : ∀ n, n ≤ count → keptRowsThrough kept size n = 0 := by
      intro n
      induction n with
      | zero => intro _; rfl
      | succ n ih =>
        intro bound
        simp [keptRowsThrough, noKept n (by omega), ih (by omega)]
    have absent : ∀ p, .figure p ∈ items → keptAt p = false := by
      intro p member
      cases yes : keptAt p with
      | false => rfl
      | true =>
        obtain ⟨i, bound, placed, _⟩ := source p member yes
        exact (any ⟨i, bound, placed⟩).elim
    cases placed : blankPlacedFromSourceFull 0 blank waiting items (textHereAtBreak items 1) keptAt with
    | false => simpa [placed, zero count (Nat.le_refl _)] using positiveCapacity
    | true =>
      obtain ⟨candidate, next, inColumn, notTop⟩ :=
        (I3_blankPlacedFromSourceFull_iff_next_in_column _ _ _ _ _ _).mp placed
      obtain ⟨item, member, selected, _⟩ := I3_nextOfSource_some_has_member _ _ _ _ next
      have before : blank < first := by
        cases item with
        | text p =>
          simp [candidateAfterBlank] at selected
          obtain ⟨lt, eq⟩ := selected
          subst candidate
          have same := onlyFirst p member inColumn
          omega
        | figure p =>
          simp [candidateAfterBlank] at selected
          obtain ⟨_, eq⟩ := selected
          subst candidate
          have including : keptAt p = true := inColumn
          simp [absent p member] at including
        | blank _ | need _ => contradiction
      have atTop : blankAtTopSource 0 blank items (textHereAtBreak items 1) keptAt = true := by
        apply (I3_blankAtTopSource_iff_empty_before _ _ _ _ _).mpr
        refine ⟨rfl, ?_⟩
        intro item member
        cases item with
        | text p =>
          have ge := firstOrder p member
          have later : ¬ p < blank := by omega
          simp [keptBeforeBlank, later]
        | figure p => simp [keptBeforeBlank, absent p member]
        | blank _ | need _ => rfl
      simp [atTop] at notTop

theorem I3_initial_need_first_text (capacity count first : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items)
    (positions size : Nat → Nat) (space kept : Nat → Bool) (needs : List (Nat × Nat))
    (firstContentText : firstContent items = some (.text first))
    (figIn : ∀ i, i < count → .figure (positions i) ∈ items) :
    ∀ p, .text p ∈ items → textHereAtBreak items 1 p = true →
      needAtPlacedText 0 capacity count items positions size space needs 1 kept p := by
  obtain ⟨firstIn, firstOrder, figsLater⟩ :=
    I3_firstContent_text_before_figures items ordered first firstContentText
  intro p member here
  have eq := I3_first_break_here_is_first_text items first firstIn firstOrder p member here
  subst p
  have rows : (sourceTextPositions items).filter
      (fun p => decide (p < first) && !space p && textHereAtBreak items 1 p) = [] := by
    cases eq : (sourceTextPositions items).filter
      (fun p => decide (p < first) && !space p && textHereAtBreak items 1 p) with
    | nil => rfl
    | cons p ps =>
      have found : p ∈ (sourceTextPositions items).filter
          (fun p => decide (p < first) && !space p && textHereAtBreak items 1 p) := by
        rw [eq]; simp
      obtain ⟨present, counts⟩ := List.mem_filter.mp found
      have ge := firstOrder p ((I3_source_text_position_member items p).mp present)
      have notBefore : ¬ p < first := by omega
      simp [notBefore] at counts
  have figs : ∀ n, n ≤ count →
      keptRowsThrough (fun i => kept i && decide (positions i < first)) size n = 0 := by
    intro n
    induction n with
    | zero => intro _; rfl
    | succ n ih =>
      intro bound
      have after := figsLater _ (figIn n (by omega))
      have before : ¬ positions n < first := by omega
      simp [keptRowsThrough, before, ih (by omega)]
  intro _ _ _
  exact Or.inl (by simp [placedBeforeNeedSource, rows, figs count (Nat.le_refl _)])

theorem I3_blank_top_separates_prior_text_and_figures
    (used blank : Nat) (items : List SourceItem) (here kept : Nat → Bool) :
    blankAtTopSource used blank items here kept =
      (!items.any (keptBeforeBlank blank here (fun _ => false)) &&
        blankAtTopSource used blank items (fun _ => false) kept) := by
  let text := keptBeforeBlank blank here (fun _ => false)
  let fig := keptBeforeBlank blank (fun _ => false) kept
  have split : ∀ xs : List SourceItem,
      xs.any (keptBeforeBlank blank here kept) = (xs.any text || xs.any fig) := by
    intro xs
    induction xs with
    | nil => rfl
    | cons item rest ih =>
      have head : keptBeforeBlank blank here kept item = (text item || fig item) := by
        cases item <;> simp [keptBeforeBlank, text, fig]
      simp only [List.any_cons, ih, head]
      cases text item <;> cases fig item <;> cases rest.any text <;> cases rest.any fig <;> rfl
  unfold blankAtTopSource
  change (_ && !(items.any (keptBeforeBlank blank here kept))) =
    (!(items.any text) && (_ && !(items.any fig)))
  rw [split]
  cases decide (used = 0) <;> cases items.any text <;> cases items.any fig <;> rfl

theorem I3_blank_top_two_figures_at_text_break
    (used blank first second : Nat) (items : List SourceItem) (here : Nat → Bool)
    (kept : Nat → Bool) (different : first ≠ second)
    (firstIn : .figure first ∈ items) (secondIn : .figure second ∈ items)
    (onlyTwo : ∀ p, .figure p ∈ items → p = first ∨ p = second) :
    blankAtTopSource used blank items here (keptAtTwoPositions first second (kept 0) (kept 1)) =
      blankTopFromFigures used (items.any (keptBeforeBlank blank here (fun _ => false))) 2
        (beforeBlankMask first second blank) kept := by
  rw [I3_blank_top_separates_prior_text_and_figures,
    I3_blankAtTop_two_figures_source used blank first second (kept 0) (kept 1) items different
      firstIn (fun _ => secondIn) onlyTwo]
  simp only [blankTopFromFigures, beforeBlankMask, show List.range 2 = [0, 1] from rfl]
  cases decide (used = 0) <;> cases items.any (keptBeforeBlank blank here (fun _ => false)) <;> simp

theorem I3_initial_first_text_full_two_figures
    (capacity blank firstText first second firstSize secondSize : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items)
    (space : Nat → Bool) (needs : List (Nat × Nat))
    (positiveCapacity : 0 < capacity) (positiveFirst : 0 < firstSize) (positiveSecond : 0 < secondSize)
    (firstContentText : firstContent items = some (.text firstText))
    (figOrder : first < second) (diffFirst : blank ≠ first) (diffSecond : blank ≠ second)
    (firstIn : .figure first ∈ items) (secondIn : .figure second ∈ items)
    (onlyTwo : ∀ p, .figure p ∈ items → p = first ∨ p = second) :
    let positions := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (positions i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < positions i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    ∃ top : Bool, ∃ kept : Nat → Bool,
      top = blankAtTopSource 0 blank items (textHereAtBreak items 1)
        (keptAtTwoPositions first second (kept 0) (kept 1)) ∧
      figures27Model 2 capacity 0 (fun i => decide (rank i ≤ 1)) rank plain size positions
        (fun i => !beforeBlankMask first second blank i && !top) block needs kept ∧
      1 + keptRowsThrough kept size 2 +
        (if blankPlacedFromSourceFull 0 blank (waitingAtTwoPositions first second kept) items
          (textHereAtBreak items 1) (keptAtTwoPositions first second (kept 0) (kept 1)) then 1 else 0) ≤ capacity ∧
      (∀ p, .text p ∈ items → textHereAtBreak items 1 p = true →
        needAtPlacedText 0 capacity 2 items positions size space needs 1 kept p) := by
  intro positions size rank plain block
  let here := textHereAtBreak items 1
  let mask := beforeBlankMask first second blank
  let roomText := fun i => decide (rank i ≤ 1)
  obtain ⟨top, kept, topEq, order, rule⟩ := I3_need_figure_and_blank_exist 2 capacity 0
    (items.any (keptBeforeBlank blank here (fun _ => false))) roomText mask
    rank plain size positions block needs (I3_beforeBlankMask_prefix first second blank figOrder)
  let atPos := keptAtTwoPositions first second (kept 0) (kept 1)
  have topSource : top = blankAtTopSource 0 blank items here atPos := by
    exact topEq.trans (I3_blank_top_two_figures_at_text_break 0 blank first second items here kept
      (Nat.ne_of_lt figOrder) firstIn secondIn onlyTwo).symm
  have source : ∀ p, .figure p ∈ items → atPos p = true →
      ∃ i, i < 2 ∧ kept i = true ∧ positions i = p := by
    intro p member present
    rcases onlyTwo p member with eq | eq
    · subst p
      exact ⟨0, by decide, by simpa [atPos, keptAtTwoPositions] using present, rfl⟩
    · subst p
      exact ⟨1, by decide, by simpa [atPos, keptAtTwoPositions, Nat.ne_of_gt figOrder] using present, rfl⟩
  have member : ∀ i, i < 2 → .figure (positions i) ∈ items := by
    intro i _
    by_cases zero : i = 0 <;> simp [positions, zero, firstIn, secondIn]
  refine ⟨top, kept, topSource, rule, ?_,
    I3_initial_need_first_text capacity 2 firstText items ordered positions size space kept needs
      firstContentText member⟩
  have posOrder : ∀ i j, i ≤ j → positions i ≤ positions j := by
    intro i j le
    by_cases iz : i = 0 <;> by_cases jz : j = 0 <;> simp [positions, iz, jz] <;> omega
  apply I3_initial_one_text_with_need_figures_fits capacity 2 firstText blank items ordered
    positions size kept atPos (waitingAtTwoPositions first second kept) positiveCapacity
    (by intro i _; by_cases zero : i = 0 <;> simp [size, zero, positiveFirst, positiveSecond])
    firstContentText posOrder member source (fun i bound yes => decide_eq_true_eq.mp (((rule i bound).mp yes).1))
  intro i bound yes
  have fits := ((rule i bound).mp yes).2.2.1
  have charges : (if !mask i && !top then 1 else 0) =
      (if blank < positions i ∧ blankAtTopSource 0 blank items here atPos = false then 1 else 0) := by
    rw [← topSource]
    have distinct : blank ≠ positions i := by
      by_cases iz : i = 0 <;> simp [positions, iz, diffFirst, diffSecond]
    have maskEq : mask i = decide (positions i < blank) := by
      by_cases iz : i = 0 <;> simp [mask, beforeBlankMask, positions, iz] <;> omega
    rw [maskEq]
    by_cases earlier : blank < positions i
    · have other : ¬ positions i < blank := by omega
      cases top <;> simp [earlier, other]
    · have other : positions i < blank := by omega
      cases top <;> simp [earlier, other]
  change 0 + rank i + priorFigureLines size i + (if !mask i && !top then 1 else 0) + size i ≤ capacity at fits
  rw [charges] at fits
  change rank i + keptRowsThrough kept size (i+1) +
    (if blank < positions i ∧ blankAtTopSource 0 blank items here atPos = false then 1 else 0) ≤ capacity
  have sum : keptRowsThrough kept size (i+1) = priorFigureLines size i + size i := by
    by_cases iz : i = 0
    · subst i
      simp [keptRowsThrough, priorFigureLines, show List.range 0 = [] from rfl, yes]
    · have one : i = 1 := by omega
      subst i
      have firstKept := order 1 (by decide) yes 0 (by decide)
      simp [keptRowsThrough, priorFigureLines, show List.range 1 = [0] from rfl, yes, firstKept]
  rw [sum]
  omega

/- On an empty column with a figure first, the zero-text break cannot
   send that figure. All earlier content is either a need or a blank,
   and an earlier blank is at the top. All needs targeting the figure
   use the firstInColumn exception. -/
theorem I3_first_figure_must_stay_under_need_rule
    (capacity count first blank : Nat) (items : List SourceItem)
    (positions size plain : Nat → Nat) (space : Nat → Bool) (needs : List (Nat × Nat))
    (top : Bool) (kept keptAt : Nat → Bool)
    (firstContentFigure : firstContent items = some (.figure first))
    (ordered : sourceOrdered items)
    (index : positions 0 = first) (nonempty : 0 < count)
    (plainRows : plain 0 = ((sourceTextPositions items).filter
      (fun p => decide (p < first) && !space p)).length)
    (sizeFits : size 0 ≤ capacity)
    (topEq : top = blankAtTopSource 0 blank items (fun _ => false) keptAt)
    (rule : figures27Model count capacity 0
      (fun f => decide (textBeforeCount items (positions f) ≤ 0))
      (fun f => textBeforeCount items (positions f)) plain size positions
      (fun f => decide (blank < positions f) && !top)
      (fun p => .text p ∈ items ∧ space p = false) needs kept) :
    kept 0 = true := by
  obtain ⟨_, _, minimal⟩ := I3_firstContent_is_earliest items ordered (.figure first) firstContentFigure
  have textAfter : ∀ p, .text p ∈ items → first ≤ p := fun p member =>
    minimal (.text p) member (by simp [isContent])
  have noText : textBeforeCount items first = 0 := by
    change (items.filter _).length = 0
    cases eq : items.filter (earlierTextItem first) with
    | nil => rfl
    | cons item rest =>
      have member : item ∈ items.filter (earlierTextItem first) := by rw [eq]; simp
      obtain ⟨inside, before⟩ := List.mem_filter.mp member
      cases item with
      | text p =>
        have ge := textAfter p inside
        simp [earlierTextItem, show ¬ p < first by omega] at before
      | figure _ | need _ | blank _ => contradiction
  have noRows : plain 0 = 0 := by
    rw [plainRows]
    cases eq : (sourceTextPositions items).filter (fun p => decide (p < first) && !space p) with
    | nil => rfl
    | cons p rest =>
      have m : p ∈ (sourceTextPositions items).filter (fun p => decide (p < first) && !space p) := by rw [eq]; simp
      obtain ⟨pm, before⟩ := List.mem_filter.mp m
      have ge := textAfter p ((I3_source_text_position_member items p).mp pm)
      simp [show ¬ p < first by omega] at before
  have noCharge : (decide (blank < positions 0) && !top) = false := by
    rw [index]
    by_cases earlier : blank < first
    · have atTop : top = true := by
        rw [topEq]
        apply (I3_blankAtTopSource_iff_empty_before _ _ _ _ _).mpr
        refine ⟨rfl, ?_⟩
        intro item member
        cases item with
        | text _ | blank _ | need _ => simp [keptBeforeBlank]
        | figure p =>
          have ge : first ≤ p := minimal (.figure p) member (by simp [isContent])
          simp [keptBeforeBlank, show ¬ p < blank by omega]
      simp [atTop]
    · simp [earlier]
  apply (rule 0 nonempty).mpr
  refine ⟨by simp [index, noText], by intro g prior; exact (Nat.not_lt_zero g prior).elim,
    ?_, ?_⟩
  · simpa [figureHasRoom, index, noText, priorFigureLines, show List.range 0 = [] from rfl,
      show (decide (blank < first) && !top) = false by simpa [index] using noCharge] using sizeFits
  · intro _ _ _
    exact Or.inl (by simp [noRows, priorFigureLines, show List.range 0 = [] from rfl])

/- Normalize the first legal break: zero for an occupied column or a
   leading figure, one for an empty column whose first content is text.
   All components below refer to this same top flag, figure set and
   source-level blank placement. -/
theorem I3_two_figure_need_initial_placement
    (capacity used blank first second firstSize secondSize : Nat) (items : List SourceItem)
    (ordered : sourceOrdered items) (space : Nat → Bool) (needs : List (Nat × Nat))
    (positiveCapacity : 0 < capacity) (usedFits : used ≤ capacity)
    (positiveFirst : 0 < firstSize) (positiveSecond : 0 < secondSize)
    (firstFits : firstSize ≤ capacity) (figOrder : first < second)
    (diffFirst : blank ≠ first) (diffSecond : blank ≠ second)
    (firstIn : .figure first ∈ items) (secondIn : .figure second ∈ items)
    (onlyTwo : ∀ p, .figure p ∈ items → p = first ∨ p = second) :
    let pos := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (pos i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < pos i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    ∃ b : Nat, ∃ top : Bool, ∃ kept : Nat → Bool,
      b ≤ (sourceTextPositions items).length ∧
      top = blankAtTopSource used blank items (textHereAtBreak items b)
        (keptAtTwoPositions first second (kept 0) (kept 1)) ∧
      figures27Model 2 capacity used (fun i => decide (rank i ≤ b)) rank plain size pos
        (fun i => !beforeBlankMask first second blank i && !top) block needs kept ∧
      used + b + keptRowsThrough kept size 2 +
        (if blankPlacedFromSourceFull used blank (waitingAtTwoPositions first second kept) items
          (textHereAtBreak items b) (keptAtTwoPositions first second (kept 0) (kept 1)) then 1 else 0) ≤ capacity ∧
      (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
        needAtPlacedText used capacity 2 items pos size space needs b kept p) ∧
      (used = 0 → ∀ p, firstContent items = some (.text p) → 0 < b) ∧
      (used = 0 → ∀ p, firstContent items = some (.figure p) →
        keptAtTwoPositions first second (kept 0) (kept 1) p = true) := by
  intro pos size rank plain block
  by_cases startText : used = 0 ∧ ∃ p, firstContent items = some (.text p)
  · obtain ⟨empty, p, firstText⟩ := startText
    subst used
    obtain ⟨top, kept, topEq, rule, fits, p1⟩ := I3_initial_first_text_full_two_figures
      capacity blank p first second firstSize secondSize items ordered space needs positiveCapacity
      positiveFirst positiveSecond firstText figOrder diffFirst diffSecond firstIn secondIn onlyTwo
    have textIn := (I3_firstContent_text_before_figures items ordered p firstText).1
    have present := (I3_source_text_position_member items p).mpr textIn
    have len : 1 ≤ (sourceTextPositions items).length := by
      cases eq : sourceTextPositions items with
      | nil => simp [eq] at present
      | cons _ _ => simp; omega
    exact ⟨1, top, kept, len, topEq, rule, by simpa using fits, p1, by intros; decide,
      by intro _ q figure; simp [firstText] at figure⟩
  · obtain ⟨top, kept, placed, rule, topEq, blankEq, fits⟩ := I3_need_initial_two_figures_blank
      capacity used blank first second firstSize secondSize items space needs usedFits figOrder diffFirst
      diffSecond firstIn secondIn onlyTwo
    have none : textHereAtBreak items 0 = fun _ => false := by
      funext p; simp [textHereAtBreak, Nat.not_lt_zero]
    refine ⟨0, top, kept, Nat.zero_le _, by simpa only [none] using topEq, rule, ?_, ?_, ?_, ?_⟩
    · rw [none, ← blankEq]
      simpa [keptRowsThrough, size, Nat.add_assoc] using fits
    · intro p _ here
      simp [none] at here
    · intro empty p text
      exact (startText ⟨empty, p, text⟩).elim
    · intro empty p figure
      subst used
      obtain ⟨member, _, figBefore⟩ := I3_firstContent_figure_before_text items ordered p figure
      have actual : p = first := by
        rcases onlyTwo p member with eq | eq
        · exact eq
        · have le := figBefore first firstIn
          omega
      subst p
      have converted : figures27Model 2 capacity 0 (fun i => decide (rank i ≤ 0))
          rank plain size pos (fun i => decide (blank < pos i) && !top) block needs kept := by
        intro i bound
        have actual := rule i bound
        have maskEq : (!beforeBlankMask first second blank i && !top) = (decide (blank < pos i) && !top) := by
          by_cases iz : i = 0
          · subst i
            by_cases before : first < blank
            · have later : ¬ blank < first := by omega
              simp [beforeBlankMask, pos, before, later]
            · have later : blank < first := by omega
              simp [beforeBlankMask, pos, before, later]
          · have io : i = 1 := by omega
            subst i
            by_cases before : second < blank
            · have later : ¬ blank < second := by omega
              simp [beforeBlankMask, pos, before, later]
            · have later : blank < second := by omega
              simp [beforeBlankMask, pos, before, later]
        simp only [figureHasRoom] at actual ⊢
        simpa only [maskEq] using actual
      have keepFirst := I3_first_figure_must_stay_under_need_rule capacity 2 first blank items
        pos size plain space needs top kept _ figure ordered rfl (by decide) rfl firstFits topEq converted
      simpa [keptAtTwoPositions] using keepFirst

theorem I3_missed_figure_target_extends_if_text_remains
    (used capacity count b n f blank : Nat) (items : List SourceItem)
    (ordered : sourceOrdered items) (positions size : Nat → Nat)
    (space room waiting keptAt : Nat → Bool) (needs : List (Nat × Nat)) (top : Bool)
    (posOrder : ∀ i j, i ≤ j → positions i ≤ positions j)
    (beyond : b < textBeforeCount items (positions f))
    (positive : ∀ i, i < count → 0 < size i) (bound : f < count)
    (needReached : ∀ p, .text p ∈ items → p < n → textHereAtBreak items b p = true)
    (unique : ∀ p, .text p ∈ items → p ≠ n) :
    let rank := fun i => textBeforeCount items (positions i)
    let kept := fun brk => greedyFigure (fun i => decide (rank i ≤ brk)) room
    needTargetsFigure n positions (fun p => .text p ∈ items ∧ space p = false) f (figureWaits (kept b)) →
    (∀ i, i < count → kept (b+1) i = true →
      used + rank i + keptRowsThrough (kept (b+1)) size (i+1) +
        (if blank < positions i ∧ top = false then 1 else 0) ≤ capacity) →
    (∀ p, .figure p ∈ items → keptAt p = true → ∃ i, i < count ∧ kept (b+1) i = true ∧ positions i = p) →
    used + ((sourceTextPositions items).filter (fun p => decide (p < positions f) && textHereAtBreak items b p)).length +
      keptRowsThrough (fun i => kept b i && decide (positions i < positions f)) size count +
      (if blank < positions f ∧ top = false then 1 else 0) + size f ≤ capacity →
    (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
      needAtPlacedText used capacity count items positions size space needs b (kept b) p) →
    used + (b+1) + keptRowsThrough (kept (b+1)) size count +
      (if blankPlacedFromSource blank waiting items (textHereAtBreak items (b+1)) keptAt top then 1 else 0) ≤ capacity ∧
    (∀ p, .text p ∈ items → textHereAtBreak items (b+1) p = true →
      needAtPlacedText used capacity count items positions size space needs (b+1) (kept (b+1)) p) := by
  intro rank kept target figureRoom source load p1
  have ranks : ∀ i j, i ≤ j → rank i ≤ rank j := fun i j le =>
    I3_text_before_source_monotone items _ _ (posOrder i j le)
  refine ⟨?_, I3_space_before_target_figure_preserves_text_needs _ _ _ _ _ _ _ ordered positions size
    space room needs posOrder beyond needReached unique target p1⟩
  by_cases fresh : ∃ j, j < count ∧ kept b j = false ∧ kept (b+1) j = true
  · exact I3_extended_figure_prefix_fits capacity used b count (kept (b+1)) (kept b) size positions
      blank items waiting keptAt top posOrder source fresh positive
      (fun i _ yes => ((I3_figure_break_prefix rank ranks room (b+1) i).mp yes).1)
      (fun i _ missing yes => I3_new_figure_at_extended_break rank ranks room b i missing yes) figureRoom
  · have same : ∀ i, i < count → kept (b+1) i = kept b i := by
      intro i within
      cases old : kept b i with
      | false =>
        cases new : kept (b+1) i with
        | false => rfl
        | true => exact (fresh ⟨i, within, old, new⟩).elim
      | true =>
        have prior := (I3_figure_break_prefix rank ranks room b i).mp old
        exact (I3_figure_break_prefix rank ranks room (b+1) i).mpr ⟨by omega, prior.2⟩
    have newLoad : ∀ k, k ≤ count →
        keptRowsThrough (fun i => kept (b+1) i && decide (positions i < positions f)) size k =
          keptRowsThrough (fun i => kept b i && decide (positions i < positions f)) size k := by
      intro k
      induction k with
      | zero => intro _; rfl
      | succ j ih =>
        intro lim
        simp only [keptRowsThrough, same j (by omega), ih (by omega)]
    apply I3_space_extension_fits_before_unreached_figure used capacity count b f blank items positions
      size waiting keptAt (kept (b+1)) top ordered beyond (positive f bound) source
    · intro i within new
      rw [same i within] at new
      exact ((I3_figure_break_prefix rank ranks room b i).mp new).1
    · rw [newLoad count (Nat.le_refl _)]
      exact load

theorem I3_missed_source_has_another_text (items : List SourceItem) (b pos : Nat)
    (beyond : b < textBeforeCount items pos) : b < (sourceTextPositions items).length := by
  rw [I3_source_text_before_count] at beyond
  have bound : ∀ ps : List Nat, countEarlierText ps pos ≤ ps.length := by
    intro ps
    induction ps with
    | nil => simp [countEarlierText]
    | cons h rest ih =>
      by_cases before : h < pos <;> simp [countEarlierText, before] at * <;> omega
  exact Nat.lt_of_lt_of_le beyond (bound _)

theorem I3_missed_text_has_another_text (items : List SourceItem) (ordered : sourceOrdered items)
    (b t : Nat) (member : .text t ∈ items) (missed : textHereAtBreak items b t = false) :
    b < (sourceTextPositions items).length := by
  have pm := (I3_source_text_position_member items t).mpr member
  have atIndex := I3_text_rank_points_to_position _ _ pm
  obtain ⟨bound, _⟩ := List.get?_eq_some.mp atIndex
  have notPlaced : ¬ textRank (sourceTextPositions items) t < b := by
    intro earlier
    have placed := (I3_text_here_iff_source_rank items ordered t b member).mpr earlier
    simp [missed] at placed
  omega

/-- On an empty column the first content is retained. This fixes whether the
    source blank is at the top across all feasible choices of the break. -/
theorem I3_blank_top_fixed_by_first_content (items : List SourceItem)
    (ordered : sourceOrdered items) (used blank : Nat) (here kept : Nat → Bool)
    (retain : used = 0 → ∀ i, firstContent items = some i →
      match i with
      | .text p => here p = true
      | .figure p => kept p = true
      | _ => False) :
    blankAtTopSource used blank items here kept =
      blankAtTopSource used blank items (fun _ => true) (fun _ => true) := by
  by_cases empty : used = 0
  · unfold blankAtTopSource
    simp only [empty, decide_True, Bool.true_and]
    congr 1
    apply Bool.eq_iff_iff.mpr
    constructor
    · intro h
      obtain ⟨i, member, before⟩ := List.any_eq_true.mp h
      apply List.any_eq_true.mpr
      refine ⟨i, member, ?_⟩
      cases i <;> simp_all [keptBeforeBlank]
    · intro h
      obtain ⟨i, member, before⟩ := List.any_eq_true.mp h
      have contents : isContent i ∧ sourcePos i < blank := by
        cases i <;> simp_all [keptBeforeBlank, isContent, sourcePos]
      cases first : firstContent items with
      | none => exact False.elim (I3_firstContent_none_has_no_content items first i member contents.1)
      | some start =>
          obtain ⟨content, belongs, earliest⟩ := I3_firstContent_is_earliest items ordered start first
          have lt := Nat.lt_of_le_of_lt (earliest i member contents.1) contents.2
          have retained := retain empty start first
          apply List.any_eq_true.mpr
          refine ⟨start, belongs, ?_⟩
          cases start <;> simp_all [keptBeforeBlank, isContent, sourcePos]
  · simp [blankAtTopSource, empty]

theorem I3_blank_top_same_for_every_admissible_break
    (items : List SourceItem) (ordered : sourceOrdered items)
    (used blank b : Nat) (config : FigureConfig) (kept : Nat → Bool)
    (retain : firstContentNotSent used b items config kept) :
    blankAtTopSource used blank items (textHereAtBreak items b) (figureKeptAtPos config kept) =
      blankAtTopSource used blank items (fun _ => true) (fun _ => true) := by
  apply I3_blank_top_fixed_by_first_content items ordered
  intro empty item first
  have retained := retain empty item first
  cases item with
  | text p =>
      have le := (I3_firstContent_text_before_figures items ordered p first).2.1
      have placed := (I3_break_one_text_iff_first items p).mpr le
      simp [textHereAtBreak] at placed ⊢
      omega
  | figure p => exact retained
  | blank p => exact retained
  | need p => exact retained

/-- A break is legal when the same figure selection and blank placement satisfy
    capacity, P1 for every retained text and the empty-column rule. -/
def twoFigureNeedBreak (capacity used blank first second firstSize secondSize : Nat)
    (items : List SourceItem) (space : Nat → Bool) (needs : List (Nat × Nat)) (b : Nat) : Prop :=
    let pos := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (pos i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < pos i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    ∃ top : Bool, ∃ kept : Nat → Bool,
      top = blankAtTopSource used blank items (textHereAtBreak items b)
        (keptAtTwoPositions first second (kept 0) (kept 1)) ∧
      figures27Model 2 capacity used (fun i => decide (rank i ≤ b)) rank plain size pos
        (fun i => !beforeBlankMask first second blank i && !top) block needs kept ∧
      used + b + keptRowsThrough kept size 2 +
        (if blankPlacedFromSourceFull used blank (waitingAtTwoPositions first second kept) items
          (textHereAtBreak items b) (keptAtTwoPositions first second (kept 0) (kept 1)) then 1 else 0) ≤ capacity ∧
      (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
        needAtPlacedText used capacity 2 items pos size space needs b kept p) ∧
      (used = 0 → ∀ p, firstContent items = some (.text p) → 0 < b) ∧
      (used = 0 → ∀ p, firstContent items = some (.figure p) →
        keptAtTwoPositions first second (kept 0) (kept 1) p = true)

theorem I3_two_figure_need_maximal_placement
    (capacity used blank first second firstSize secondSize : Nat) (items : List SourceItem)
    (ordered : sourceOrdered items) (space : Nat → Bool) (needs : List (Nat × Nat))
    (positiveCapacity : 0 < capacity) (usedFits : used ≤ capacity)
    (positiveFirst : 0 < firstSize) (positiveSecond : 0 < secondSize)
    (firstFits : firstSize ≤ capacity) (figOrder : first < second)
    (diffFirst : blank ≠ first) (diffSecond : blank ≠ second)
    (firstIn : .figure first ∈ items) (secondIn : .figure second ∈ items)
    (onlyTwo : ∀ p, .figure p ∈ items → p = first ∨ p = second) :
    let valid := twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs
    ∃ b, b ≤ (sourceTextPositions items).length ∧ valid b ∧
      (b < (sourceTextPositions items).length → ¬ valid (b + 1)) := by
  intro valid
  obtain ⟨seed, top, kept, bound, rest⟩ := I3_two_figure_need_initial_placement
    capacity used blank first second firstSize secondSize items ordered space needs
    positiveCapacity usedFits positiveFirst positiveSecond firstFits figOrder diffFirst
    diffSecond firstIn secondIn onlyTwo
  have initial : valid seed := ⟨top, kept, rest⟩
  obtain ⟨b, _, within, legal, stop⟩ := maximal_break_above valid seed _
    bound initial
  exact ⟨b, within, legal, stop⟩

theorem I3_two_figure_need_blank_charge_unique
    (used blank first second b : Nat) (items : List SourceItem) (ordered : sourceOrdered items)
    (kept : Nat → Bool)
    (firstText : used = 0 → ∀ p, firstContent items = some (.text p) → 0 < b)
    (firstFigure : used = 0 → ∀ p, firstContent items = some (.figure p) →
      keptAtTwoPositions first second (kept 0) (kept 1) p = true) :
    blankAtTopSource used blank items (textHereAtBreak items b)
      (keptAtTwoPositions first second (kept 0) (kept 1)) =
      blankAtTopSource used blank items (fun _ => true) (fun _ => true) := by
  apply I3_blank_top_fixed_by_first_content items ordered
  intro empty item initial
  cases item with
  | text p =>
      have bound := firstText empty p initial
      have le := (I3_firstContent_text_before_figures items ordered p initial).2.1
      have placed := (I3_break_one_text_iff_first items p).mpr le
      simp [textHereAtBreak] at placed ⊢
      omega
  | figure p => exact firstFigure empty p initial
  | blank p =>
      exact (I3_firstContent_is_earliest items ordered _ initial).1
  | need p =>
      exact (I3_firstContent_is_earliest items ordered _ initial).1

theorem I3_need_at_text_depends_on_actual_figures
    (used capacity count b p : Nat) (items : List SourceItem) (pos size : Nat → Nat)
    (space kept other : Nat → Bool) (needs : List (Nat × Nat))
    (same : ∀ i, i < count → kept i = other i) :
    needAtPlacedText used capacity count items pos size space needs b kept p ↔
      needAtPlacedText used capacity count items pos size space needs b other p := by
  have rows (k : Nat) (bound : k ≤ count) :
      keptRowsThrough (fun i => kept i && decide (pos i < p)) size k =
      keptRowsThrough (fun i => other i && decide (pos i < p)) size k := by
    induction k with
    | zero => rfl
    | succ k ih =>
        simp only [keptRowsThrough]
        simp only [ih (by omega), same k (by omega)]
  have waits (i : Nat) (bound : i < count) : figureWaits kept i ↔ figureWaits other i := by
    unfold figureWaits
    rw [same i bound]
    have earlier : (∃ g, g < i ∧ kept g = false) ↔ (∃ g, g < i ∧ other g = false) := by
      constructor <;> rintro ⟨g, lt, sent⟩
      · exact ⟨g, lt, (same g (Nat.lt_trans lt bound)) ▸ sent⟩
      · exact ⟨g, lt, (same g (Nat.lt_trans lt bound)).symm ▸ sent⟩
    rw [earlier]
  unfold needAtPlacedText placedBeforeNeedSource
  rw [rows count (Nat.le_refl _)]
  simp only [needTargetsText]
  constructor
  · intro check n mem h
    exact check n mem ⟨h.1, h.2.1, h.2.2.1, fun i hi a z => (waits i hi).mpr (h.2.2.2 i hi a z)⟩
  · intro check n mem h
    exact check n mem ⟨h.1, h.2.1, h.2.2.1, fun i hi a z => (waits i hi).mp (h.2.2.2 i hi a z)⟩

theorem I3_normalize_two_figure_need_break
    (capacity used blank first second firstSize secondSize b : Nat) (items : List SourceItem)
    (ordered : sourceOrdered items) (space : Nat → Bool) (needs : List (Nat × Nat))
    (valid : twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs b) :
    let pos := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (pos i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < pos i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    let top := blankAtTopSource used blank items (fun _ => true) (fun _ => true)
    let charge := fun i => !beforeBlankMask first second blank i && !top
    let room := fun i => @decide (needFigureStatic capacity used rank plain size pos charge block needs i)
      (Classical.propDecidable _)
    let kept := greedyFigure (fun i => decide (rank i ≤ b)) room
    used + b + keptRowsThrough kept size 2 +
        (if blankPlacedFromSourceFull used blank (waitingAtTwoPositions first second kept) items
          (textHereAtBreak items b) (keptAtTwoPositions first second (kept 0) (kept 1)) then 1 else 0) ≤ capacity ∧
      (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
        needAtPlacedText used capacity 2 items pos size space needs b kept p) ∧
      (used = 0 → ∀ p, firstContent items = some (.text p) → 0 < b) ∧
      (used = 0 → ∀ p, firstContent items = some (.figure p) →
        keptAtTwoPositions first second (kept 0) (kept 1) p = true) := by
  intro pos size rank plain block top charge room kept
  obtain ⟨oldTop, old, atTop, model, fit, p1, firstText, firstFig⟩ := valid
  have topEq : oldTop = top := atTop.trans (I3_two_figure_need_blank_charge_unique
    used blank first second b items ordered old firstText firstFig)
  rw [topEq] at model
  have same : ∀ i, i < 2 → old i = kept i := by
    apply I3_need_figure_model_is_greedy 2 capacity used _ room old rank plain size pos charge block needs
    · intro i; exact @decide_eq_true_iff _ (Classical.propDecidable _)
    · exact model
  have zero := same 0 (by decide)
  have one := same 1 (by decide)
  have waits : waitingAtTwoPositions first second old = waitingAtTwoPositions first second kept := by
    funext p
    simp only [waitingAtTwoPositions, waitingFigureBool, earlierFigureSent, zero, one]
  refine ⟨?_, ?_, firstText, ?_⟩
  · simpa only [keptRowsThrough, waits, zero, one] using fit
  · intro p member here
    exact (I3_need_at_text_depends_on_actual_figures used capacity 2 b p items pos size space old kept
      needs same).mp (p1 p member here)
  · simpa only [zero, one] using firstFig

theorem I3_canonical_two_figure_need_break_iff
    (capacity used blank first second firstSize secondSize b : Nat) (items : List SourceItem)
    (ordered : sourceOrdered items) (space : Nat → Bool) (needs : List (Nat × Nat)) :
    let pos := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (pos i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < pos i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    let top := blankAtTopSource used blank items (fun _ => true) (fun _ => true)
    let charge := fun i => !beforeBlankMask first second blank i && !top
    let room := fun i => @decide (needFigureStatic capacity used rank plain size pos charge block needs i)
      (Classical.propDecidable _)
    let kept := greedyFigure (fun i => decide (rank i ≤ b)) room
    (used + b + keptRowsThrough kept size 2 +
        (if blankPlacedFromSourceFull used blank (waitingAtTwoPositions first second kept) items
          (textHereAtBreak items b) (keptAtTwoPositions first second (kept 0) (kept 1)) then 1 else 0) ≤ capacity ∧
      (∀ p, .text p ∈ items → textHereAtBreak items b p = true →
        needAtPlacedText used capacity 2 items pos size space needs b kept p) ∧
      (used = 0 → ∀ p, firstContent items = some (.text p) → 0 < b) ∧
      (used = 0 → ∀ p, firstContent items = some (.figure p) →
        keptAtTwoPositions first second (kept 0) (kept 1) p = true)) ↔
      twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs b := by
  intro pos size rank plain block top charge room kept
  constructor
  · rintro ⟨fit, p1, firstText, firstFig⟩
    refine ⟨top, kept, ?_, ?_, fit, p1, firstText, firstFig⟩
    · exact (I3_two_figure_need_blank_charge_unique used blank first second b items ordered kept
        firstText firstFig).symm
    · apply figures27_of_static
      intro f bound
      have rule := I3_greedyFigures_rule 2 (fun i => decide (rank i ≤ b)) room f bound
      change kept f = true ↔ _ at rule ⊢
      have roomAt : room f = true ↔
          needFigureStatic capacity used rank plain size pos charge block needs f :=
        @decide_eq_true_iff _ (Classical.propDecidable _)
      exact rule.trans (and_congr_right fun _ => and_congr_right fun _ => roomAt)
  · exact I3_normalize_two_figure_need_break capacity used blank first second firstSize secondSize
      b items ordered space needs

theorem I3_two_figure_need_successor_is_legal
    (capacity used blank first second firstSize secondSize b : Nat) (items : List SourceItem)
    (ordered : sourceOrdered items) (figOrder : first < second)
    (space : Nat → Bool) (needs : List (Nat × Nat))
    (valid : twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs b) :
    let pos := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (pos i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < pos i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    let top := blankAtTopSource used blank items (fun _ => true) (fun _ => true)
    let charge := fun i => !beforeBlankMask first second blank i && !top
    let room := fun i => @decide (needFigureStatic capacity used rank plain size pos charge block needs i)
      (Classical.propDecidable _)
    let kept := fun c => greedyFigure (fun i => decide (rank i ≤ c)) room
    let keptAt := fun c => keptAtTwoPositions first second (kept c 0) (kept c 1)
    used + (b+1) + keptRowsThrough (kept (b+1)) size 2 +
      (if blankPlacedFromSource blank (waitingAtTwoPositions first second (kept (b+1))) items
        (textHereAtBreak items (b+1)) (keptAt (b+1)) top then 1 else 0) ≤ capacity →
    (∀ p, .text p ∈ items → textHereAtBreak items (b+1) p = true →
      needAtPlacedText used capacity 2 items pos size space needs (b+1) (kept (b+1)) p) →
    twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs (b+1) := by
  intro pos size rank plain block top charge room kept keptAt fit p1
  obtain ⟨_, _, _, firstFig⟩ := I3_normalize_two_figure_need_break capacity used blank
    first second firstSize secondSize b items ordered space needs valid
  have ranks : ∀ i j, i ≤ j → rank i ≤ rank j := by
    intro i j le
    apply I3_text_before_source_monotone
    dsimp [pos]
    split <;> split <;> omega
  have mono (i : Nat) (old : kept b i = true) : kept (b+1) i = true := by
    have parts := (I3_figure_break_prefix rank ranks room b i).mp old
    exact (I3_figure_break_prefix rank ranks room (b+1) i).mpr ⟨by omega, parts.2⟩
  have firstFigNext (empty : used = 0) (p : Nat) (initial : firstContent items = some (.figure p)) :
      keptAt (b+1) p = true := by
    have previous : keptAt b p = true := firstFig empty p initial
    by_cases a : p = first
    · simpa [keptAt, keptAtTwoPositions, a] using mono 0 (by simpa [keptAt, keptAtTwoPositions, a] using previous)
    · by_cases z : p = second
      · simpa [keptAt, keptAtTwoPositions, a, z, Nat.ne_of_gt figOrder] using
          mono 1 (by simpa [keptAt, keptAtTwoPositions, a, z, Nat.ne_of_gt figOrder] using previous)
      · simp [keptAt, keptAtTwoPositions, a, z] at previous
  have firstTextNext : used = 0 → ∀ p, firstContent items = some (.text p) → 0 < b+1 := by
    intros; omega
  have topEq := I3_two_figure_need_blank_charge_unique used blank first second (b+1) items ordered
    (kept (b+1)) firstTextNext firstFigNext
  apply (I3_canonical_two_figure_need_break_iff capacity used blank first second firstSize secondSize
    (b+1) items ordered space needs).mp
  exact ⟨by simpa only [blankPlacedFromSourceFull, topEq] using fit, p1, firstTextNext, firstFigNext⟩

theorem I3_two_figure_need_geometry_of_canonical
    (used capacity blank first second b : Nat) (size rank plain : Nat → Nat)
    (top : Bool) (block : Nat → Prop) (needs : List (Nat × Nat))
    (diffFirst : blank ≠ first) (diffSecond : blank ≠ second) :
    let pos := fun i : Nat => if i = 0 then first else second
    let charge := fun i => !beforeBlankMask first second blank i && !top
    let room := fun i => @decide (needFigureStatic capacity used rank plain size pos charge block needs i)
      (Classical.propDecidable _)
    let kept := greedyFigure (fun i => decide (rank i ≤ b)) room
    ∀ i, i < 2 → kept i = true →
      used + rank i + keptRowsThrough kept size (i+1) +
        (if blank < pos i ∧ top = false then 1 else 0) ≤ capacity := by
  intro pos charge room kept i bound yes
  have parts := ((I3_greedyFigures_rule 2 (fun i => decide (rank i ≤ b)) room i bound).mp yes)
  have roomHere : needFigureStatic capacity used rank plain size pos charge block needs i :=
    @of_decide_eq_true _ (Classical.propDecidable _) parts.2.2
  have fits := roomHere.1
  unfold figureHasRoom at fits
  have chargeEq : (if charge i then 1 else 0) = (if blank < pos i ∧ top = false then 1 else 0) := by
    have distinct : blank ≠ pos i := by
      by_cases iz : i = 0 <;> simp [pos, iz, diffFirst, diffSecond]
    have maskEq : beforeBlankMask first second blank i = decide (pos i < blank) := by
      by_cases iz : i = 0 <;> simp [beforeBlankMask, pos, iz] <;> omega
    dsimp only [charge]
    rw [maskEq]
    by_cases earlier : blank < pos i
    · have other : ¬ pos i < blank := by omega
      cases top <;> simp [earlier, other]
    · have other : pos i < blank := by omega
      cases top <;> simp [earlier, other]
  have sum : keptRowsThrough kept size (i+1) = priorFigureLines size i + size i := by
    by_cases iz : i = 0
    · subst i
      simp [keptRowsThrough, priorFigureLines, show List.range 0 = [] from rfl, yes]
    · have one : i = 1 := by omega
      subst i
      have firstKept : kept 0 = true := parts.2.1 0 (by decide)
      simp [keptRowsThrough, priorFigureLines, show List.range 1 = [0] from rfl, yes, firstKept]
  rw [sum]
  rw [chargeEq] at fits
  omega

theorem I3_source_text_rank_strict_at_member (items : List SourceItem) (p q : Nat)
    (member : .text p ∈ items) (prior : p < q) :
    textBeforeCount items p < textBeforeCount items q := by
  induction items with
  | nil => simp at member
  | cons head rest ih =>
    rcases List.mem_cons.mp member with same | tail
    · subst head
      have mono := I3_text_before_source_monotone rest p q (Nat.le_of_lt prior)
      simp [textBeforeCount, earlierTextItem, prior] at mono ⊢
      omega
    · have lt := ih tail
      simp only [textBeforeCount] at lt ⊢
      cases head with
      | text pos =>
          by_cases early : pos < p
          · have later : pos < q := by omega
            simp [earlierTextItem, early, later, lt] <;> omega
          · by_cases later : pos < q <;> simp [earlierTextItem, early, later, lt] <;> omega
      | figure _ | blank _ | need _ => simpa [earlierTextItem] using lt

theorem I3_maximal_two_figure_need_keeps_text
    (capacity used blank first second firstSize secondSize b n t firstPart : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items) (figOrder : first < second)
    (diffFirst : blank ≠ first) (diffSecond : blank ≠ second)
    (positiveFirst : 0 < firstSize) (positiveSecond : 0 < secondSize)
    (firstIn : .figure first ∈ items) (secondIn : .figure second ∈ items)
    (positivePart : 0 < firstPart) (space : Nat → Bool) (needs : List (Nat × Nat))
    (reqIn : ∀ m ∈ needs, .need m.1 ∈ items)
    (atText : .text t ∈ items)
    (reached : ∀ p, .text p ∈ items → p < n → textHereAtBreak items b p = true)
    (written : .need n ∈ items)
    (valid : twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs b)
    (maximal : b < (sourceTextPositions items).length →
      ¬ twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs (b+1)) :
    let pos := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (pos i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < pos i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    let top := blankAtTopSource used blank items (fun _ => true) (fun _ => true)
    let charge := fun i => !beforeBlankMask first second blank i && !top
    let room := fun i => @decide (needFigureStatic capacity used rank plain size pos charge block needs i)
      (Classical.propDecidable _)
    let kept := fun c => greedyFigure (fun i => decide (rank i ≤ c)) room
    let group := needs.filter (fun m => @decide (sourceNeedAtTarget m.1 t 2 items pos space (kept b))
      (Classical.propDecidable _))
    needTargetsText n t block pos 2 (kept b) →
    used + ((sourceTextPositions items).filter (fun p => decide (p < t) && textHereAtBreak items b p)).length +
      keptRowsThrough (fun i => kept b i && decide (pos i < t)) size 2 +
      (if blank < t ∧ top = false then 1 else 0) + firstPart ≤ capacity →
    writtenGroupFits capacity 0 (placedBeforeNeedSource used 2 b items pos size space (kept b)) group →
    textHereAtBreak items b t = true := by
  intro pos size rank plain block top charge room kept group target load writtenFit
  let keptAt := fun c => keptAtTwoPositions first second (kept c 0) (kept c 1)
  cases status : textHereAtBreak items b t with
  | true => rfl
  | false =>
    apply False.elim
    apply maximal (I3_missed_text_has_another_text items ordered b t atText status)
    have different (p q : Nat) (here : .text p ∈ items) (there : .need q ∈ items) : p ≠ q := by
      intro eq
      have bad := I3_sourceOrdered_unique_position items ordered _ _ here there (by simpa [sourcePos] using eq)
      cases bad
    have figureDifferent (v : Nat) (item : SourceItem) (fig : .figure v ∈ items)
        (member : item ∈ items) (diff : SourceItem.figure v ≠ item) : v ≠ sourcePos item := by
      intro eq
      exact diff (I3_sourceOrdered_unique_position items ordered _ _ fig member eq)
    have posOrder : ∀ i j, i ≤ j → pos i ≤ pos j := by
      intro i j le
      dsimp [pos]
      split <;> split <;> omega
    have figMember (i : Nat) : .figure (pos i) ∈ items := by
      by_cases zero : i = 0 <;> simp [pos, zero, firstIn, secondIn]
    obtain ⟨_, p1, _, _⟩ := I3_normalize_two_figure_need_break capacity used blank first second
      firstSize secondSize b items ordered space needs valid
    have next := I3_missed_text_target_extends used capacity 2 b t blank items ordered pos size
      space room (waitingAtTwoPositions first second (kept (b+1))) (keptAt (b+1)) needs top
      firstPart positivePart posOrder atText status
      (I3_text_need_missed_only_spaces n t 2 pos (kept b) items space _ target reached
        (fun p m => different p n m written))
      (fun m h p member => different p m.1 member (reqIn m h))
      (fun m h i => figureDifferent (pos i) (.need m.1) (figMember i) (reqIn m h) (by intro eq; cases eq))
      (fun i _ => figureDifferent (pos i) (.text t) (figMember i) atText (by intro eq; cases eq))
      (by intro i _; by_cases zero : i = 0 <;> simp [size, zero, positiveFirst, positiveSecond])
      (I3_two_figure_need_geometry_of_canonical used capacity blank first second (b+1) size rank plain
        top block needs diffFirst diffSecond)
      (by
        intro p _ yes
        by_cases a : p = first
        · exact ⟨0, by decide, by simpa [keptAt, keptAtTwoPositions, a] using yes, by simp [pos,a]⟩
        · by_cases z : p = second
          · exact ⟨1, by decide, by simpa [keptAt, keptAtTwoPositions, a, z, Nat.ne_of_gt figOrder] using yes,
              by simp [pos,z]⟩
          · simp [keptAt, keptAtTwoPositions, a, z] at yes)
      (by
        intro i _ yes p member lt
        have ready := ((I3_greedyFigures_rule 2 (fun i => decide (rank i ≤ b)) room i (by assumption)).mp yes).1
        have le : rank i ≤ b := of_decide_eq_true ready
        have lower := I3_source_text_rank_strict_at_member items p (pos i) member lt
        exact decide_eq_true (Nat.lt_of_lt_of_le lower le))
      load writtenFit p1
    exact I3_two_figure_need_successor_is_legal capacity used blank first second firstSize secondSize
      b items ordered figOrder space needs valid next.1 next.2

theorem I3_maximal_two_figure_need_reaches_figure
    (capacity used blank first second firstSize secondSize b n f : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items) (figOrder : first < second)
    (diffFirst : blank ≠ first) (diffSecond : blank ≠ second)
    (positiveFirst : 0 < firstSize) (positiveSecond : 0 < secondSize)
    (space : Nat → Bool) (needs : List (Nat × Nat)) (bound : f < 2)
    (reached : ∀ p, .text p ∈ items → p < n → textHereAtBreak items b p = true)
    (written : .need n ∈ items)
    (valid : twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs b)
    (maximal : b < (sourceTextPositions items).length →
      ¬ twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs (b+1)) :
    let pos := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (pos i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < pos i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    let top := blankAtTopSource used blank items (fun _ => true) (fun _ => true)
    let charge := fun i => !beforeBlankMask first second blank i && !top
    let room := fun i => @decide (needFigureStatic capacity used rank plain size pos charge block needs i)
      (Classical.propDecidable _)
    let kept := fun c => greedyFigure (fun i => decide (rank i ≤ c)) room
    needTargetsFigure n pos block f (figureWaits (kept b)) →
    used + ((sourceTextPositions items).filter
      (fun p => decide (p < pos f) && textHereAtBreak items b p)).length +
      keptRowsThrough (fun i => kept b i && decide (pos i < pos f)) size 2 +
      (if blank < pos f ∧ top = false then 1 else 0) + size f ≤ capacity →
    rank f ≤ b := by
  intro pos size rank plain block top charge room kept target load
  let keptAt := fun c => keptAtTwoPositions first second (kept c 0) (kept c 1)
  apply Nat.le_of_not_gt
  intro beyond
  apply maximal (I3_missed_source_has_another_text items b (pos f) beyond)
  have posOrder : ∀ i j, i ≤ j → pos i ≤ pos j := by
    intro i j le
    dsimp [pos]
    split <;> split <;> omega
  obtain ⟨_, p1, _, _⟩ := I3_normalize_two_figure_need_break capacity used blank first second
    firstSize secondSize b items ordered space needs valid
  have next := I3_missed_figure_target_extends_if_text_remains used capacity 2 b n f blank items
    ordered pos size space room (waitingAtTwoPositions first second (kept (b+1))) (keptAt (b+1))
    needs top posOrder beyond
    (by intro i _; by_cases zero : i = 0 <;> simp [size, zero, positiveFirst, positiveSecond])
    bound reached (by
      intro p member eq
      have bad := I3_sourceOrdered_unique_position items ordered _ _ member written
        (by simpa [sourcePos] using eq)
      cases bad)
    target (I3_two_figure_need_geometry_of_canonical used capacity blank first second (b+1) size rank plain
      top block needs diffFirst diffSecond)
    (by
      intro p _ yes
      by_cases a : p = first
      · exact ⟨0, by decide, by simpa [keptAt, keptAtTwoPositions, a] using yes, by simp [pos,a]⟩
      · by_cases z : p = second
        · exact ⟨1, by decide, by simpa [keptAt, keptAtTwoPositions, a, z, Nat.ne_of_gt figOrder] using yes,
            by simp [pos,z]⟩
        · simp [keptAt, keptAtTwoPositions, a, z] at yes)
    load p1
  exact I3_two_figure_need_successor_is_legal capacity used blank first second firstSize secondSize
    b items ordered figOrder space needs valid next.1 next.2

theorem I3_reached_figure_counts_every_earlier_text
    (items : List SourceItem) (b pos : Nat) (space : Nat → Bool)
    (reached : textBeforeCount items pos ≤ b) :
    ((sourceTextPositions items).filter (fun p => decide (p < pos) && textHereAtBreak items b p)).length =
      textBeforeCount items pos ∧
    (sourceTextPositions items).filter (fun p => decide (p < pos) && !space p && textHereAtBreak items b p) =
      (sourceTextPositions items).filter (fun p => decide (p < pos) && !space p) := by
  have allEarlier (p : Nat) (pm : p ∈ sourceTextPositions items) (lt : p < pos) :
      textHereAtBreak items b p = true :=
    decide_eq_true (Nat.lt_of_lt_of_le (I3_source_text_rank_strict_at_member items p pos
      ((I3_source_text_position_member items p).mp pm) lt) reached)
  have text : (sourceTextPositions items).filter (fun p => decide (p < pos) && textHereAtBreak items b p) =
      (sourceTextPositions items).filter (fun p => decide (p < pos)) := by
    apply filter_eq_on_members
    intro p pm
    by_cases lt : p < pos <;> simp [lt, allEarlier, pm]
  constructor
  · rw [text, I3_source_text_before_count]
    rfl
  · apply filter_eq_on_members
    intro p pm
    by_cases lt : p < pos <;> simp [lt, allEarlier, pm]

theorem I3_two_figure_rows_before_member
    (first second f : Nat) (size : Nat → Nat) (kept : Nat → Bool) (order : first < second)
    (bound : f < 2) :
    let pos := fun i : Nat => if i = 0 then first else second
    keptRowsThrough (fun i => kept i && decide (pos i < pos f)) size 2 =
      priorFigureLines (fun i => if kept i then size i else 0) f := by
  intro pos
  by_cases zero : f = 0
  · subst f
    simp [pos, keptRowsThrough, priorFigureLines, show List.range 0 = [] from rfl, Nat.not_lt_of_ge (Nat.le_of_lt order)]
  · have one : f = 1 := by omega
    subst f
    simp [pos, keptRowsThrough, priorFigureLines, show List.range 1 = [0] from rfl, order]

theorem I3_maximal_two_figure_need_keeps_figure
    (capacity used blank first second firstSize secondSize b n f : Nat)
    (items : List SourceItem) (ordered : sourceOrdered items) (figOrder : first < second)
    (diffFirst : blank ≠ first) (diffSecond : blank ≠ second)
    (firstIn : .figure first ∈ items) (secondIn : .figure second ∈ items)
    (positiveFirst : 0 < firstSize) (positiveSecond : 0 < secondSize)
    (space : Nat → Bool) (needs : List (Nat × Nat)) (bound : f < 2)
    (reached : ∀ p, .text p ∈ items → p < n → textHereAtBreak items b p = true)
    (reqIn : ∀ m ∈ needs, .need m.1 ∈ items)
    (written : .need n ∈ items)
    (valid : twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs b)
    (maximal : b < (sourceTextPositions items).length →
      ¬ twoFigureNeedBreak capacity used blank first second firstSize secondSize items space needs (b+1)) :
    let pos := fun i : Nat => if i = 0 then first else second
    let size := fun i : Nat => if i = 0 then firstSize else secondSize
    let rank := fun i => textBeforeCount items (pos i)
    let plain := fun i => ((sourceTextPositions items).filter
      (fun p => decide (p < pos i) && !space p)).length
    let block := fun p => .text p ∈ items ∧ space p = false
    let top := blankAtTopSource used blank items (fun _ => true) (fun _ => true)
    let charge := fun i => !beforeBlankMask first second blank i && !top
    let room := fun i => @decide (needFigureStatic capacity used rank plain size pos charge block needs i)
      (Classical.propDecidable _)
    let kept := fun c => greedyFigure (fun i => decide (rank i ≤ c)) room
    let group := needs.filter (fun m => @decide (needTargetsFigure m.1 pos block f (figureWaits (kept b)))
      (Classical.propDecidable _))
    needTargetsFigure n pos block f (figureWaits (kept b)) →
    used + ((sourceTextPositions items).filter
      (fun p => decide (p < pos f) && textHereAtBreak items b p)).length +
      keptRowsThrough (fun i => kept b i && decide (pos i < pos f)) size 2 +
      (if blank < pos f ∧ top = false then 1 else 0) + size f ≤ capacity →
    (∀ i, i < 2 → pos i < n → ¬ figureWaits (kept b) i → kept b i = true) →
    writtenGroupFits capacity 0 (placedBeforeNeedSource used 2 b items pos size space (kept b)) group →
    kept b f = true := by
  intro pos size rank plain block top charge room kept group target load prior writtenFit
  have rankReached := I3_maximal_two_figure_need_reaches_figure capacity used blank first second
    firstSize secondSize b n f items ordered figOrder diffFirst diffSecond positiveFirst positiveSecond
    space needs bound reached written valid maximal target load
  have posOrder : ∀ i j, i ≤ j → pos i ≤ pos j := by
    intro i j le
    dsimp [pos]
    split <;> split <;> omega
  have figMember (i : Nat) : .figure (pos i) ∈ items := by
    by_cases z : i = 0 <;> simp [pos,z,firstIn,secondIn]
  have diff (i q : Nat) (node : .need q ∈ items) : pos i ≠ q := by
    intro eq
    cases I3_sourceOrdered_unique_position items ordered _ _ (figMember i) node (by simpa [sourcePos] using eq)
  have roomAt (i : Nat) : room i = true ↔ needFigureStatic capacity used rank plain size pos charge block needs i :=
    @decide_eq_true_iff _ (Classical.propDecidable _)
  have rule : figures27Model 2 capacity used (fun i => decide (rank i ≤ b)) rank plain size pos charge block needs (kept b) := by
    apply figures27_of_static
    intro i hi
    exact (I3_greedyFigures_rule 2 (fun i => decide (rank i ≤ b)) room i hi).trans
      (and_congr_right fun _ => and_congr_right fun _ => roomAt i)
  have allPrior : ∀ i, i < f → ¬ figureWaits (kept b) i → kept b i = true := by
    intro i lt awake
    by_cases early : pos i < n
    · exact prior i (by omega) early awake
    · have distinct := diff i n written
      exact (awake (target.2.2.2 i lt (by omega))).elim
  obtain ⟨allText, plainText⟩ := I3_reached_figure_counts_every_earlier_text items b (pos f) space rankReached
  have figs := I3_two_figure_rows_before_member first second f size (kept b) figOrder bound
  have chargeEq : (if charge f then 1 else 0) = (if blank < pos f ∧ top = false then 1 else 0) := by
    have distinct : blank ≠ pos f := by by_cases z : f = 0 <;> simp [pos,z,diffFirst,diffSecond]
    have maskEq : beforeBlankMask first second blank f = decide (pos f < blank) := by
      by_cases z : f = 0 <;> simp [beforeBlankMask,pos,z] <;> omega
    dsimp only [charge]
    rw [maskEq]
    by_cases earlier : blank < pos f
    · have other : ¬ pos f < blank := by omega
      cases top <;> simp [earlier,other]
    · have other : pos f < blank := by omega
      cases top <;> simp [earlier,other]
  apply I3_target_figure_stays_when_group_fits 2 capacity used f _ rank plain size pos charge block needs
    (kept b) rule bound (decide_eq_true rankReached) allPrior
  · rw [allText, figs] at load
    rwa [chargeEq]
  · apply (I3_written_group_iff_target_max capacity 0 _ _ group ?_).mp writtenFit
    intro m mem
    obtain ⟨original, selected⟩ := List.mem_filter.mp mem
    rw [I3_load_at_figure_need_agrees_with_target used 2 b m.1 f items pos size space (kept b)
      posOrder (by
        intro p mText eq
        cases I3_sourceOrdered_unique_position items ordered _ _ mText (reqIn m original) (by simpa [sourcePos] using eq))
      (fun i => diff i m.1 (reqIn m original)) (@of_decide_eq_true _ (Classical.propDecidable _) selected)]
    unfold placedBeforeNeedSource
    rw [plainText, figs]

theorem I3_append_figure_preserves_earlier_blank
    (items suffix : List SourceItem) (blank : Nat) (waiting here kept : Nat → Bool)
    (top : Bool) :
    blankPlacedFromSource blank waiting items here kept top = true →
      blankPlacedFromSource blank waiting (items ++ suffix) here kept top = true := by
  have next (c : SourceCandidate) (found : nextOfSource blank waiting items = some c) :
      nextOfSource blank waiting (items ++ suffix) = some c := by
    induction items with
    | nil => simp [nextOfSource] at found
    | cons head rest ih =>
      cases cand : candidateAfterBlank blank head with
      | none =>
        simp [nextOfSource, cand] at found ⊢
        exact ih found
      | some v =>
        by_cases sent : candidateWaits waiting v = true
        · simp [nextOfSource, cand, sent] at found ⊢
          exact ih found
        · simpa [nextOfSource, cand, sent] using found
  intro placed
  cases found : nextOfSource blank waiting items with
  | none => simp [blankPlacedFromSource, found] at placed
  | some c =>
    simp only [blankPlacedFromSource, found] at placed
    simpa only [blankPlacedFromSource, next c found] using placed

theorem I3_padding_preserves_text_prefix (items suffix : List SourceItem)
    (onlyFigure : ∀ x ∈ suffix, ∃ p, x = .figure p) :
    sourceTextPositions (items ++ suffix) = sourceTextPositions items ∧
    ∀ p, textBeforeCount (items ++ suffix) p = textBeforeCount items p := by
  have none : sourceTextPositions suffix = [] := by
    induction suffix with
    | nil => rfl
    | cons x xs ih =>
      obtain ⟨p, rfl⟩ := onlyFigure x (by simp)
      exact ih (fun v h => onlyFigure v (by simp [h]))
  have eq : sourceTextPositions (items ++ suffix) = sourceTextPositions items := by
    induction items with
    | nil => exact none
    | cons x xs ih => cases x <;> simp_all [sourceTextPositions]
  exact ⟨eq, fun p => by simp only [I3_source_text_before_count, eq]⟩

def sourceEnd : List SourceItem → Nat
  | [] => 0
  | x :: xs => max (sourcePos x + 1) (sourceEnd xs)

theorem I3_original_positions_before_padding (items : List SourceItem) :
    ∀ x ∈ items, sourcePos x < sourceEnd items := by
  induction items with
  | nil => simp
  | cons h tail ih =>
    intro x mem
    rcases List.mem_cons.mp mem with rfl | old
    · simp [sourceEnd]; omega
    · exact Nat.lt_of_lt_of_le (ih x old) (Nat.le_max_right _ _)

def padNeedFigures (endPos : Nat) : FigureConfig → List SourceItem
  | .zero => [.figure endPos, .figure (endPos+1)]
  | .one _ _ => [.figure endPos]
  | .two _ _ _ _ => []

def paddedNeedConfig (endPos : Nat) : FigureConfig → FigureConfig
  | .zero => .two endPos 1 (endPos+1) 1
  | .one p size => .two p size endPos 1
  | .two p size q other => .two p size q other

private theorem member_of_source_append (xs ys : List SourceItem) (x : SourceItem) :
    x ∈ xs ++ ys ↔ x ∈ xs ∨ x ∈ ys := by
  induction xs with
  | nil => simp
  | cons h rest ih => simp only [List.cons_append, List.mem_cons, ih, or_assoc]

theorem I3_padded_need_input_has_two_figures (items : List SourceItem)
    (config : FigureConfig) (valid : figureDomain items config) :
    figureDomain (items ++ padNeedFigures (sourceEnd items) config)
      (paddedNeedConfig (sourceEnd items) config) := by
  cases config with
  | zero =>
    refine ⟨by omega, by simp [padNeedFigures,member_of_source_append], by simp [padNeedFigures,member_of_source_append], ?_⟩
    intro p member
    simp only [padNeedFigures,member_of_source_append,List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with old | h | h
    · exact (valid p old).elim
    · cases h; exact Or.inl rfl
    · cases h; exact Or.inr rfl
  | one pos size =>
    refine ⟨I3_original_positions_before_padding items (.figure pos) valid.1,
      by simp [padNeedFigures,member_of_source_append,valid.1], by simp [padNeedFigures,member_of_source_append], ?_⟩
    intro p member
    simp only [padNeedFigures,member_of_source_append,List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with old | added
    · exact Or.inl (valid.2 p old)
    · cases added; exact Or.inr rfl
  | two p size q other => simpa [padNeedFigures,paddedNeedConfig] using valid

theorem I3_padding_preserves_source_order (items : List SourceItem) (config : FigureConfig)
    (ordered : sourceOrdered items) :
    sourceOrdered (items ++ padNeedFigures (sourceEnd items) config) := by
  have appendOrdered (xs ys : List SourceItem) (xOrder : sourceOrdered xs) (yOrder : sourceOrdered ys)
      (earlier : ∀ x ∈ xs, ∀ y ∈ ys, sourcePos x < sourcePos y) : sourceOrdered (xs ++ ys) := by
    induction xs with
    | nil => exact yOrder
    | cons head tail ih =>
      refine ⟨?_, ih xOrder.2 (fun x m => earlier x (List.mem_cons_of_mem _ m))⟩
      intro y member
      rcases (member_of_source_append tail ys y).mp member with left | right
      · exact xOrder.1 y left
      · exact earlier head (by simp) y right
  apply appendOrdered _ _ ordered
  · cases config <;> simp [padNeedFigures,sourceOrdered,sourcePos]
  · intro x member y padded
    have bound := I3_original_positions_before_padding items x member
    cases config <;> simp [padNeedFigures] at padded
    · rcases padded with rfl | rfl
      · exact bound
      · exact Nat.lt_trans bound (Nat.lt_succ_self _)
    · subst y; exact bound

theorem I3_padding_keeps_original_figure_data (config : FigureConfig) (endPos i : Nat)
    (actual : i < figureCount config) :
    figurePosAt (paddedNeedConfig endPos config) i = figurePosAt config i ∧
      figureSizeAt (paddedNeedConfig endPos config) i = figureSizeAt config i := by
  cases config with
  | zero => exact (Nat.not_lt_zero _ actual).elim
  | one pos size =>
    have zero : i = 0 := by change i < 1 at actual; omega
    simp [zero,paddedNeedConfig,figurePosAt,figureSizeAt]
  | two _ _ _ _ => exact ⟨rfl,rfl⟩

/-- With no manuscript blank, use a position after all padded items. It
    neither consumes a grid line nor precedes any genuine target. -/
theorem I3_end_blank_has_no_successor (items : List SourceItem) (blank : Nat)
    (pastEnd : sourceEnd items ≤ blank) (waiting : Nat → Bool) :
    nextOfSource blank waiting items = none := by
  induction items with
  | nil => rfl
  | cons x xs ih =>
    have after : sourcePos x ≤ blank :=
      Nat.le_trans (Nat.le_of_lt (I3_original_positions_before_padding _ x (List.mem_cons_self x xs))) pastEnd
    have tail : sourceEnd xs ≤ blank := Nat.le_trans (Nat.le_max_right _ _) pastEnd
    have skip : candidateAfterBlank blank x = none := by
      cases x <;> simp [sourcePos] at after <;> simp [candidateAfterBlank] <;> omega
    simpa only [nextOfSource, skip] using ih tail

theorem I3_missing_blank_never_charged (used : Nat) (items : List SourceItem)
    (waiting here kept : Nat → Bool) :
    blankPlacedFromSourceFull used (sourceEnd items) waiting items here kept = false := by
  simp [blankPlacedFromSourceFull,blankPlacedFromSource,
    I3_end_blank_has_no_successor items _ (Nat.le_refl _) waiting]

theorem I3_padding_never_adds_figure_rows_before_an_original_target
    (items : List SourceItem) (config : FigureConfig) (kept : Nat → Bool) (target : SourceItem)
    (member : target ∈ items) :
    let padded := paddedNeedConfig (sourceEnd items) config
    keptRowsThrough (fun i => kept i && decide (figurePosAt padded i < sourcePos target))
      (figureSizeAt padded) 2 =
    keptRowsThrough (fun i => kept i && decide (figurePosAt config i < sourcePos target))
      (figureSizeAt config) (figureCount config) := by
  intro padded
  have before := I3_original_positions_before_padding items target member
  have outside : ¬ sourceEnd items < sourcePos target := by omega
  have lastOutside : ¬ sourceEnd items + 1 < sourcePos target := by omega
  cases config <;> simp [padded,paddedNeedConfig,figurePosAt,figureSizeAt,figureCount,keptRowsThrough,outside,lastOutside]

theorem I3_padding_bounds_original_figure_load (items : List SourceItem)
    (config : FigureConfig) (kept : Nat → Bool) :
    keptRowsThrough kept (figureSizeAt config) (figureCount config) ≤
      keptRowsThrough kept (figureSizeAt (paddedNeedConfig (sourceEnd items) config)) 2 := by
  cases config <;> simp [paddedNeedConfig,figureSizeAt,figureCount,keptRowsThrough] <;> omega

theorem I3_padding_preserves_placed_load_before_need
    (used b : Nat) (items : List SourceItem) (config : FigureConfig)
    (space kept : Nat → Bool) (target : SourceItem) (member : target ∈ items) :
    let augmented := items ++ padNeedFigures (sourceEnd items) config
    let padded := paddedNeedConfig (sourceEnd items) config
    placedBeforeNeedSource used 2 b augmented (figurePosAt padded) (figureSizeAt padded) space kept
      (sourcePos target) =
    placedBeforeNeedSource used (figureCount config) b items (figurePosAt config) (figureSizeAt config)
      space kept (sourcePos target) := by
  intro augmented padded
  have onlyFigure : ∀ x ∈ padNeedFigures (sourceEnd items) config, ∃ p, x = .figure p := by
    intro x mem
    cases config <;> simp [padNeedFigures] at mem
    · rcases mem with rfl | rfl <;> exact ⟨_,rfl⟩
    · subst x; exact ⟨_,rfl⟩
  obtain ⟨sameText, sameRank⟩ := I3_padding_preserves_text_prefix items _ onlyFigure
  have sameHere : textHereAtBreak augmented b = textHereAtBreak items b := by
    funext p
    simp only [textHereAtBreak, augmented, sameRank]
  unfold placedBeforeNeedSource
  rw [sameHere]
  change sourceTextPositions augmented = sourceTextPositions items at sameText
  rw [sameText, I3_padding_never_adds_figure_rows_before_an_original_target items config kept target member]

private theorem text_mem_padded_source (items : List SourceItem) (config : FigureConfig) (p : Nat) :
    SourceItem.text p ∈ items ++ padNeedFigures (sourceEnd items) config ↔ .text p ∈ items := by
  rw [member_of_source_append]
  cases config <;> simp [padNeedFigures]

theorem I3_padding_preserves_text_target (items : List SourceItem) (config : FigureConfig)
    (n t : Nat) (member : .text t ∈ items) (space kept : Nat → Bool) :
    let augmented := items ++ padNeedFigures (sourceEnd items) config
    let padded := paddedNeedConfig (sourceEnd items) config
    sourceNeedAtTarget n t 2 augmented (figurePosAt padded) space kept ↔
      sourceNeedAtTarget n t (figureCount config) items (figurePosAt config) space kept := by
  intro augmented padded
  have same (p : Nat) : .text p ∈ augmented ↔ .text p ∈ items := text_mem_padded_source items config p
  have noExtra (i : Nat) (bound : i < 2) (earlier : figurePosAt padded i < t) : i < figureCount config := by
    have endAfter : t < sourceEnd items := I3_original_positions_before_padding items (.text t) member
    cases config with
    | zero =>
        by_cases iz : i = 0 <;> simp [padded,paddedNeedConfig,figurePosAt,iz] at earlier <;> omega
    | one _ _ =>
        by_cases iz : i = 0
        · simp [figureCount,iz]
        · simp [padded,paddedNeedConfig,figurePosAt,iz] at earlier; omega
    | two _ _ _ _ => exact bound
  unfold sourceNeedAtTarget needTargetsText
  simp only [same]
  constructor
  · rintro ⟨nt,target,blocks,figures⟩
    refine ⟨nt,target,blocks,?_⟩
    intro i original after before
    have lt : i < 2 := by cases config <;> simp_all [figureCount] <;> omega
    have pos := (I3_padding_keeps_original_figure_data config (sourceEnd items) i original).1
    exact figures i lt (pos.symm ▸ after) (pos.symm ▸ before)
  · rintro ⟨nt,target,blocks,figures⟩
    refine ⟨nt,target,blocks,?_⟩
    intro i bound after before
    have original := noExtra i bound before
    have pos := (I3_padding_keeps_original_figure_data config (sourceEnd items) i original).1
    exact figures i original (pos ▸ after) (pos ▸ before)

theorem I3_padding_preserves_figure_target (items : List SourceItem) (config : FigureConfig)
    (n f : Nat) (bound : f < figureCount config) (space kept : Nat → Bool) :
    let augmented := items ++ padNeedFigures (sourceEnd items) config
    let padded := paddedNeedConfig (sourceEnd items) config
    needTargetsFigure n (figurePosAt padded) (fun p => .text p ∈ augmented ∧ space p = false) f (figureWaits kept) ↔
      needTargetsFigure n (figurePosAt config) (fun p => .text p ∈ items ∧ space p = false) f (figureWaits kept) := by
  intro augmented padded
  have posEq (i : Nat) (hi : i < figureCount config) :
      figurePosAt padded i = figurePosAt config i :=
    (I3_padding_keeps_original_figure_data config (sourceEnd items) i hi).1
  unfold needTargetsFigure
  simp only [augmented,text_mem_padded_source,posEq f bound]
  constructor
  · rintro ⟨before,awake,block,prior⟩
    refine ⟨before,awake,block,?_⟩
    intro g lt after
    apply prior g lt
    simpa only [posEq g (Nat.lt_trans lt bound)] using after
  · rintro ⟨before,awake,block,prior⟩
    refine ⟨before,awake,block,?_⟩
    intro g lt after
    apply prior g lt
    simpa only [posEq g (Nat.lt_trans lt bound)] using after

theorem I3_padding_preserves_text_P1 (used capacity b t : Nat) (items : List SourceItem)
    (config : FigureConfig) (space kept : Nat → Bool) (needs : List (Nat × Nat))
    (member : .text t ∈ items) :
    let padded := paddedNeedConfig (sourceEnd items) config
    needAtPlacedText used capacity 2 (items ++ padNeedFigures (sourceEnd items) config)
      (figurePosAt padded) (figureSizeAt padded) space needs b kept t ↔
    needAtPlacedText used capacity (figureCount config) items (figurePosAt config) (figureSizeAt config)
      space needs b kept t := by
  intro padded
  unfold needAtPlacedText
  have rows := I3_padding_preserves_placed_load_before_need used b items config space kept (.text t) member
  change placedBeforeNeedSource _ _ _ _ _ _ _ _ t = _ at rows
  dsimp only
  rw [rows]
  constructor
  · intro test n m target
    exact test n m ((I3_padding_preserves_text_target items config n.1 t member space kept).mpr target)
  · intro test n m target
    exact test n m ((I3_padding_preserves_text_target items config n.1 t member space kept).mp target)

theorem I3_padding_preserves_figures_at_original_positions (items : List SourceItem)
    (config : FigureConfig) (valid : figureDomain items config) (p : Nat) (member : .figure p ∈ items)
    (kept : Nat → Bool) :
    let padded := paddedNeedConfig (sourceEnd items) config
    figureKeptAtPos padded kept p = figureKeptAtPos config kept p ∧
      figureWaitingAtPos padded kept p = figureWaitingAtPos config kept p := by
  cases config with
  | zero => exact (valid p member).elim
  | one pos size =>
    have eq := valid.2 p member
    subst p
    simp [paddedNeedConfig,figureKeptAtPos,keptAtTwoPositions,figureWaitingAtPos,waitingAtTwoPositions,
      waitingFigureBool,earlierFigureSent]
  | two _ _ _ _ => exact ⟨rfl,rfl⟩

theorem I3_padding_preserves_real_blank_top
    (items : List SourceItem) (config : FigureConfig) (valid : figureDomain items config)
    (used b blank : Nat) (member : .blank blank ∈ items) (kept : Nat → Bool) :
    let augmented := items ++ padNeedFigures (sourceEnd items) config
    let padded := paddedNeedConfig (sourceEnd items) config
    blankAtTopSource used blank augmented (textHereAtBreak augmented b) (figureKeptAtPos padded kept) =
      blankAtTopSource used blank items (textHereAtBreak items b) (figureKeptAtPos config kept) := by
  intro augmented padded
  have onlyFig : ∀ x ∈ padNeedFigures (sourceEnd items) config, ∃ p, x = .figure p := by
    intro x hi
    cases config <;> simp [padNeedFigures] at hi
    · rcases hi with rfl | rfl <;> exact ⟨_,rfl⟩
    · subst x; exact ⟨_,rfl⟩
  have textEq (p : Nat) : textHereAtBreak augmented b p = textHereAtBreak items b p := by
    simp only [textHereAtBreak,augmented,(I3_padding_preserves_text_prefix items _ onlyFig).2]
  have original (x : SourceItem) (xm : x ∈ items) :
      keptBeforeBlank blank (textHereAtBreak augmented b) (figureKeptAtPos padded kept) x =
        keptBeforeBlank blank (textHereAtBreak items b) (figureKeptAtPos config kept) x := by
    cases x with
    | text p => simp [keptBeforeBlank,textEq]
    | figure p => simp [keptBeforeBlank,(I3_padding_preserves_figures_at_original_positions items config valid p xm kept).1,padded]
    | blank p => rfl
    | need p => rfl
  have earlier : blank < sourceEnd items := I3_original_positions_before_padding items _ member
  have added (x : SourceItem) (xm : x ∈ padNeedFigures (sourceEnd items) config) :
      keptBeforeBlank blank (textHereAtBreak augmented b) (figureKeptAtPos padded kept) x = false := by
    cases config <;> simp [padNeedFigures] at xm
    · rcases xm with rfl | rfl <;> simp [keptBeforeBlank,show ¬ sourceEnd items < blank by omega,
        show ¬ sourceEnd items + 1 < blank by omega]
    · subst x; simp [keptBeforeBlank,show ¬ sourceEnd items < blank by omega]
  apply Bool.eq_iff_iff.mpr
  rw [I3_blankAtTopSource_iff_empty_before, I3_blankAtTopSource_iff_empty_before]
  constructor
  · rintro ⟨empty,all⟩
    exact ⟨empty,fun x xm => (original x xm) ▸ all x (List.mem_append_of_mem_left _ xm)⟩
  · rintro ⟨empty,all⟩
    refine ⟨empty,?_⟩
    intro x xm
    rcases (member_of_source_append _ _ _).mp xm with old | new
    · rw [original x old]; exact all x old
    · exact added x new

private theorem blank_placement_congr_on_source (items : List SourceItem) (blank : Nat)
    (w v h t k l : Nat → Bool) (top : Bool)
    (text : ∀ p, .text p ∈ items → h p = t p)
    (fig : ∀ p, .figure p ∈ items → w p = v p ∧ k p = l p) :
    blankPlacedFromSource blank w items h k top = blankPlacedFromSource blank v items t l top := by
  induction items with
  | nil => rfl
  | cons x xs ih =>
    have tail := ih (fun p mem => text p (List.mem_cons_of_mem _ mem))
      (fun p mem => fig p (List.mem_cons_of_mem _ mem))
    cases x with
    | blank p => simpa [blankPlacedFromSource,nextOfSource,candidateAfterBlank] using tail
    | need p => simpa [blankPlacedFromSource,nextOfSource,candidateAfterBlank] using tail
    | text p =>
      by_cases lt : blank < p
      · simp [blankPlacedFromSource,nextOfSource,candidateAfterBlank,lt,candidateWaits,sourceInColumn,text p (by simp)]
      · simpa [blankPlacedFromSource,nextOfSource,candidateAfterBlank,lt] using tail
    | figure p =>
      have eq := fig p (by simp)
      by_cases lt : blank < p
      · cases waits : v p with
        | true => simpa [blankPlacedFromSource,nextOfSource,candidateAfterBlank,lt,candidateWaits,eq.1,waits] using tail
        | false => simp [blankPlacedFromSource,nextOfSource,candidateAfterBlank,lt,candidateWaits,sourceInColumn,eq.1,eq.2,waits]
      · simpa [blankPlacedFromSource,nextOfSource,candidateAfterBlank,lt] using tail

theorem I3_original_blank_load_bounded_by_padded
    (items : List SourceItem) (config : FigureConfig) (valid : figureDomain items config)
    (used b blank : Nat) (member : .blank blank ∈ items) (kept : Nat → Bool) :
    let augmented := items ++ padNeedFigures (sourceEnd items) config
    let padded := paddedNeedConfig (sourceEnd items) config
    blankPlacedFromSourceFull used blank (figureWaitingAtPos config kept) items
        (textHereAtBreak items b) (figureKeptAtPos config kept) = true →
      blankPlacedFromSourceFull used blank (figureWaitingAtPos padded kept) augmented
        (textHereAtBreak augmented b) (figureKeptAtPos padded kept) = true := by
  intro augmented padded
  have onlyFig : ∀ x ∈ padNeedFigures (sourceEnd items) config, ∃ p, x = .figure p := by
    intro x hi
    cases config <;> simp [padNeedFigures] at hi
    · rcases hi with rfl | rfl <;> exact ⟨_,rfl⟩
    · subst x; exact ⟨_,rfl⟩
  have eq := I3_padding_preserves_real_blank_top items config valid used b blank member kept
  unfold blankPlacedFromSourceFull
  rw [eq]
  intro placed
  apply I3_append_figure_preserves_earlier_blank
  apply (blank_placement_congr_on_source items blank (figureWaitingAtPos padded kept)
    (figureWaitingAtPos config kept) (textHereAtBreak augmented b) (textHereAtBreak items b)
    (figureKeptAtPos padded kept) (figureKeptAtPos config kept) _ ?_ ?_).trans placed
  · intro p _
    simp only [textHereAtBreak,augmented,(I3_padding_preserves_text_prefix items _ onlyFig).2]
  · intro p mem
    exact (I3_padding_preserves_figures_at_original_positions items config valid p mem kept).symm

theorem I3_unpad_need_capacity (items : List SourceItem) (config : FigureConfig)
    (valid : figureDomain items config) (blank : Option Nat) (blankOK : blankDomain items blank)
    (used capacity b : Nat) (kept : Nat → Bool) :
    let augmented := items ++ padNeedFigures (sourceEnd items) config
    let padded := paddedNeedConfig (sourceEnd items) config
    let pos := blank.getD (sourceEnd augmented)
    let placed := blankPlacedFromSourceFull used pos (figureWaitingAtPos padded kept) augmented
      (textHereAtBreak augmented b) (figureKeptAtPos padded kept)
    let original := fun p => blankPlacedFromSourceFull used p (figureWaitingAtPos config kept) items
      (textHereAtBreak items b) (figureKeptAtPos config kept)
    used + b + keptRowsThrough kept (figureSizeAt padded) 2 + (if placed then 1 else 0) ≤ capacity →
    used + b + keptRowsThrough kept (figureSizeAt config) (figureCount config) +
      (if blank.elim false original then 1 else 0) ≤ capacity := by
  intro augmented padded pos placed original fit
  have rows := I3_padding_bounds_original_figure_load items config kept
  change keptRowsThrough kept (figureSizeAt config) (figureCount config) ≤ keptRowsThrough kept (figureSizeAt padded) 2 at rows
  cases blank with
  | none =>
    change used + b + keptRowsThrough kept (figureSizeAt config) (figureCount config) + 0 ≤ capacity
    omega
  | some p =>
    change used + b + keptRowsThrough kept (figureSizeAt config) (figureCount config) + (if original p then 1 else 0) ≤ capacity
    cases orig : original p with
    | false => simp; omega
    | true =>
      have paddedBlank : placed = true := I3_original_blank_load_bounded_by_padded items config valid used b p blankOK.1 kept orig
      have upper : used + b + keptRowsThrough kept (figureSizeAt padded) 2 + 1 ≤ capacity := by
        simpa only [paddedBlank, if_true] using fit
      exact Nat.le_trans (Nat.add_le_add_right (Nat.add_le_add_left rows (used+b)) 1) upper

theorem I3_first_content_remains_first_under_padding (items suffix : List SourceItem)
    (item : SourceItem) (first : firstContent items = some item) :
    firstContent (items ++ suffix) = some item := by
  induction items with
  | nil => simp [firstContent] at first
  | cons h tail ih =>
    cases h with
    | text _ | figure _ => simpa [firstContent] using first
    | blank _ | need _ =>
      exact ih (by simpa [firstContent] using first)

theorem I3_unpad_need_first_content (items : List SourceItem) (config : FigureConfig)
    (valid : figureDomain items config) (ordered : sourceOrdered items) (used b : Nat) (kept : Nat → Bool) :
    firstContentNotSent used b (items ++ padNeedFigures (sourceEnd items) config)
        (paddedNeedConfig (sourceEnd items) config) kept →
      firstContentNotSent used b items config kept := by
  intro padded empty item first
  have retained := padded empty item (I3_first_content_remains_first_under_padding items _ item first)
  cases item with
  | text _ | blank _ | need _ => exact retained
  | figure p =>
    change figureKeptAtPos config kept p = true
    rw [← (I3_padding_preserves_figures_at_original_positions items config valid p
      (I3_firstContent_is_earliest items ordered _ first).2.1 kept).1]
    exact retained

theorem I3_original_figure_P27_under_padding (config : FigureConfig)
    (endPos f : Nat) (actual : f < figureCount config) (used cap : Nat)
    (rank plain : Nat → Nat) (charge : Nat → Bool) (block : Nat → Prop) (needs : List (Nat × Nat)) :
    let padded := paddedNeedConfig endPos config
    needFigureStatic cap used (fun i => rank (figurePosAt padded i)) (fun i => plain (figurePosAt padded i))
      (figureSizeAt padded) (figurePosAt padded) (fun i => charge (figurePosAt padded i)) block needs f ↔
    needFigureStatic cap used (fun i => rank (figurePosAt config i)) (fun i => plain (figurePosAt config i))
      (figureSizeAt config) (figurePosAt config) (fun i => charge (figurePosAt config i)) block needs f := by
  intro padded
  cases config with
  | zero => exact (Nat.not_lt_zero _ actual).elim
  | two _ _ _ _ => rfl
  | one p size =>
    have zero : f = 0 := by change f < 1 at actual; omega
    subst f
    simp [padded,paddedNeedConfig,needFigureStatic,figureHasRoom,figurePosAt,figureSizeAt,
      priorFigureLines,show List.range 0 = [] from rfl,needTargetsFigure, Nat.not_lt_zero]

theorem I3_unpad_need_figures_rule (config : FigureConfig) (endPos used cap b : Nat)
    (rank plain : Nat → Nat) (charge : Nat → Bool) (block : Nat → Prop)
    (needs : List (Nat × Nat)) (kept : Nat → Bool) :
    let padded := paddedNeedConfig endPos config
    let rule := fun (cfg : FigureConfig) count =>
      figures27Model count cap used (fun f => decide (rank (figurePosAt cfg f) ≤ b))
        (fun f => rank (figurePosAt cfg f)) (fun f => plain (figurePosAt cfg f))
        (figureSizeAt cfg) (figurePosAt cfg) (fun f => charge (figurePosAt cfg f)) block needs kept
    rule padded 2 → rule config (figureCount config) := by
  intro padded rule full
  apply figures27_of_static
  have static := (I3_figure_static_rule_iff_model 2 cap used _ _ _ _ _ _ block needs kept).mpr full
  intro f actual
  have bound : f < 2 := by cases config <;> simp_all [figureCount] <;> omega
  have original := static f bound
  have posEq := (I3_padding_keeps_original_figure_data config endPos f actual).1
  apply original.trans
  apply and_congr
  · simp only [posEq]
  · exact and_congr_right fun _ => I3_original_figure_P27_under_padding config endPos f actual
      used cap rank plain charge block needs

/-- Data shared by the single- and multiple-need commands. Needs occur
    in manuscript order so the written tests check successive maxima. -/
structure NeedSource where
  items : List SourceItem
  config : FigureConfig
  blank : Option Nat
  capacity : Nat
  used : Nat
  space : Nat → Bool
  needs : List (Nat × Nat)

namespace NeedSource
def here (d : NeedSource) (b : Nat) := textHereAtBreak d.items b
def waiting (d : NeedSource) (kept : Nat → Bool) := figureWaitingAtPos d.config kept
def atPos (d : NeedSource) (kept : Nat → Bool) := figureKeptAtPos d.config kept
def pos (d : NeedSource) := figurePosAt d.config
def size (d : NeedSource) := figureSizeAt d.config
def count (d : NeedSource) := figureCount d.config
def rank (d : NeedSource) (p : Nat) := textBeforeCount d.items p
def plain (d : NeedSource) (p : Nat) := ((sourceTextPositions d.items).filter
  (fun q => decide (q < p) && !d.space q)).length
def block (d : NeedSource) (p : Nat) := .text p ∈ d.items ∧ d.space p = false
def atTop (d : NeedSource) (b : Nat) (kept : Nat → Bool) (p : Nat) :=
  blankAtTopSource d.used p d.items (d.here b) (d.atPos kept)
def charge (d : NeedSource) (b : Nat) (kept : Nat → Bool) (p : Nat) : Bool :=
  d.blank.elim false (fun q => decide (q < p) && !d.atTop b kept q)
def placedBlank (d : NeedSource) (b : Nat) (kept : Nat → Bool) : Bool :=
  d.blank.elim false (fun p => blankPlacedFromSourceFull d.used p (d.waiting kept)
    d.items (d.here b) (d.atPos kept))
def before (d : NeedSource) (b : Nat) (kept : Nat → Bool) (p : Nat) :=
  placedBeforeNeedSource d.used d.count b d.items d.pos d.size d.space kept p
def load (d : NeedSource) (b : Nat) (kept : Nat → Bool) (p : Nat) :=
  d.used + ((sourceTextPositions d.items).filter (fun q => decide (q < p) && d.here b q)).length +
    keptRowsThrough (fun i => kept i && decide (d.pos i < p)) d.size d.count +
    (if d.charge b kept p then 1 else 0)
def textTarget (d : NeedSource) (kept : Nat → Bool) (n p : Nat) :=
  sourceNeedAtTarget n p d.count d.items d.pos d.space kept
def figureTarget (d : NeedSource) (kept : Nat → Bool) (n f : Nat) :=
  needTargetsFigure n d.pos d.block f (figureWaits kept)
def beforeNeed (d : NeedSource) (b n : Nat) : Prop :=
  ∀ p, .text p ∈ d.items → p < n → d.here b p = true
def earlierFigures (d : NeedSource) (kept : Nat → Bool) (n : Nat) : Prop :=
  ∀ f, f < d.count → d.pos f < n → ¬ figureWaits kept f → kept f = true
noncomputable def group (d : NeedSource) (target : Nat → Prop) :=
  d.needs.filter (fun m => @decide (target m.1) (Classical.propDecidable _))
def base (d : NeedSource) (b : Nat) (kept : Nat → Bool) : Prop :=
  b ≤ (sourceTextPositions d.items).length ∧
  d.used + b + keptRowsThrough kept d.size d.count + (if d.placedBlank b kept then 1 else 0) ≤ d.capacity ∧
  figures27Model d.count d.capacity d.used (fun i => decide (d.rank (d.pos i) ≤ b))
    (fun i => d.rank (d.pos i)) (fun i => d.plain (d.pos i)) d.size d.pos
    (fun i => d.charge b kept (d.pos i)) d.block d.needs kept ∧
  firstContentNotSent d.used b d.items d.config kept ∧
  (∀ t, .text t ∈ d.items → d.here b t = true →
    needAtPlacedText d.used d.capacity d.count d.items d.pos d.size d.space d.needs b kept t)
def keeps (d : NeedSource) (b : Nat) (kept : Nat → Bool) : Prop :=
  (∀ n ∈ d.needs, ∀ t firstPart, .text t ∈ d.items → 0 < firstPart →
    d.textTarget kept n.1 t → d.beforeNeed b n.1 →
    d.load b kept t + firstPart ≤ d.capacity →
    writtenGroupFits d.capacity 0 (d.before b kept) (d.group (fun m => d.textTarget kept m t)) →
    d.here b t = true) ∧
  (∀ n ∈ d.needs, ∀ f, f < d.count → d.figureTarget kept n.1 f → d.beforeNeed b n.1 →
    d.earlierFigures kept n.1 → d.load b kept (d.pos f) + d.size f ≤ d.capacity →
    writtenGroupFits d.capacity 0 (d.before b kept) (d.group (fun m => d.figureTarget kept m f)) →
    kept f = true)
def augment (d : NeedSource) : NeedSource :=
  let items := d.items ++ padNeedFigures (sourceEnd d.items) d.config
  { d with
    items := items
    config := paddedNeedConfig (sourceEnd d.items) d.config
    blank := some (d.blank.getD (sourceEnd items)) }

theorem augmented_count (d : NeedSource) : d.augment.count = 2 := by
  unfold count augment
  cases d.config <;> rfl

theorem augmented_text (d : NeedSource) :
    sourceTextPositions d.augment.items = sourceTextPositions d.items ∧
      ∀ p, d.augment.rank p = d.rank p := by
  apply I3_padding_preserves_text_prefix
  intro x hi
  cases hc : d.config <;> simp [hc,padNeedFigures] at hi
  · rcases hi with rfl | rfl <;> exact ⟨_,rfl⟩
  · subst x; exact ⟨_,rfl⟩

theorem augmented_here (d : NeedSource) (b p : Nat) : d.augment.here b p = d.here b p := by
  change decide (d.augment.rank p < b) = decide (d.rank p < b)
  rw [d.augmented_text.2]

theorem augmented_before (d : NeedSource) (b : Nat) (kept : Nat → Bool) (item : SourceItem)
    (mem : item ∈ d.items) : d.augment.before b kept (sourcePos item) = d.before b kept (sourcePos item) := by
  unfold before
  rw [augmented_count]
  exact I3_padding_preserves_placed_load_before_need d.used b d.items d.config d.space kept item mem

theorem augmented_charge (d : NeedSource) (valid : figureDomain d.items d.config)
    (blankOK : blankDomain d.items d.blank) (b : Nat) (kept : Nat → Bool) (item : SourceItem)
    (member : item ∈ d.items) :
    d.augment.charge b kept (sourcePos item) = d.charge b kept (sourcePos item) := by
  unfold charge
  cases hb : d.blank with
  | none =>
      have original := List.mem_append_of_mem_left (padNeedFigures (sourceEnd d.items) d.config) member
      have last : sourcePos item < sourceEnd d.augment.items := I3_original_positions_before_padding _ _ original
      have skip : ¬ sourceEnd d.augment.items < sourcePos item := by omega
      simp only [augment,hb,Option.getD,Option.elim] at skip ⊢
      simp [skip]
  | some blank =>
      rw [hb] at blankOK
      have eq := I3_padding_preserves_real_blank_top d.items d.config valid d.used b blank blankOK.1 kept
      change (decide (d.blank.getD _ < sourcePos item) && !d.augment.atTop b kept (d.blank.getD _)) =
        (decide (blank < sourcePos item) && !d.atTop b kept blank)
      simp only [hb,Option.getD]
      rw [show d.augment.atTop b kept blank = d.atTop b kept blank from eq]

theorem augmented_load (d : NeedSource) (valid : figureDomain d.items d.config)
    (blankOK : blankDomain d.items d.blank) (b : Nat) (kept : Nat → Bool) (item : SourceItem)
    (mem : item ∈ d.items) : d.augment.load b kept (sourcePos item) = d.load b kept (sourcePos item) := by
  unfold load
  simp only [augmented_text, augmented_here, augmented_count, augmented_charge d valid blankOK b kept item mem]
  rw [show keptRowsThrough (fun i => kept i && decide (d.augment.pos i < sourcePos item)) d.augment.size 2 =
    keptRowsThrough (fun i => kept i && decide (d.pos i < sourcePos item)) d.size d.count from
    I3_padding_never_adds_figure_rows_before_an_original_target d.items d.config kept item mem]
  rfl

theorem original_fig_member (d : NeedSource) (valid : figureDomain d.items d.config)
    (f : Nat) (bound : f < d.count) : .figure (d.pos f) ∈ d.items := by
  cases h : d.config with
  | zero => simp [count,h,figureCount] at bound; omega
  | one _ _ =>
      rw [h] at valid
      simpa [pos,h,figurePosAt] using valid.1
  | two p s q z =>
      rw [h] at valid
      by_cases first : f = 0 <;> simp [pos,h,figurePosAt,first,valid.2.1,valid.2.2.1]

theorem augmented_text_target (d : NeedSource) (kept : Nat → Bool) (n t : Nat)
    (mem : .text t ∈ d.items) : d.augment.textTarget kept n t ↔ d.textTarget kept n t := by
  unfold textTarget
  rw [augmented_count]
  exact I3_padding_preserves_text_target d.items d.config n t mem d.space kept

theorem augmented_figure_target (d : NeedSource) (kept : Nat → Bool) (n f : Nat)
    (bound : f < d.count) : d.augment.figureTarget kept n f ↔ d.figureTarget kept n f :=
  I3_padding_preserves_figure_target d.items d.config n f bound d.space kept

theorem augmented_earlier_figures (d : NeedSource) (kept : Nat → Bool) (n : Nat)
    (member : .need n ∈ d.items) (before : d.earlierFigures kept n) : d.augment.earlierFigures kept n := by
  intro f bound lt awake
  have endAfter : n < sourceEnd d.items := I3_original_positions_before_padding _ _ member
  have actual : f < d.count := by
    rw [augmented_count] at bound
    cases hc : d.config with
    | zero => by_cases z : f = 0 <;> simp [pos,augment,hc,paddedNeedConfig,figurePosAt,z] at lt <;> omega
    | one _ _ =>
        by_cases z : f = 0
        · simp [count,hc,figureCount,z]
        · simp [pos,augment,hc,paddedNeedConfig,figurePosAt,z] at lt; omega
    | two _ _ _ _ => simpa [count,hc,figureCount] using bound
  have eq : d.augment.pos f = d.pos f := (I3_padding_keeps_original_figure_data d.config _ f actual).1
  exact before f actual (eq ▸ lt) awake

theorem augmented_group_fits (d : NeedSource) (b : Nat) (kept : Nat → Bool) (a z : Nat → Prop)
    (same : ∀ p, a p ↔ z p) (members : ∀ m ∈ d.needs, .need m.1 ∈ d.items) :
    writtenGroupFits d.capacity 0 (d.before b kept) (d.group a) →
      writtenGroupFits d.augment.capacity 0 (d.augment.before b kept) (d.augment.group z) := by
  have groupEq : d.augment.group z = d.group a := by
    apply filter_eq_on_members
    intro m _
    apply Bool.eq_iff_iff.mpr
    simp only [decide_eq_true_eq]
    exact (same m.1).symm
  rw [groupEq]
  have gen (ms : List (Nat × Nat)) (prev : Nat) (inside : ∀ m ∈ ms, .need m.1 ∈ d.items) :
      writtenGroupFits d.capacity prev (d.before b kept) ms →
        writtenGroupFits d.augment.capacity prev (d.augment.before b kept) ms := by
    induction ms generalizing prev with
    | nil => exact id
    | cons m rest ih =>
        have eq := augmented_before d b kept (.need m.1) (inside m (by simp))
        change d.augment.before b kept m.1 = d.before b kept m.1 at eq
        simp only [writtenGroupFits,eq]
        intro old
        exact ⟨old.1,ih _ (fun n h => inside n (List.mem_cons_of_mem _ h)) old.2⟩
  exact gen _ _ (fun m member => members m (List.mem_filter.mp member).1)

theorem unpad_keeps (d : NeedSource) (valid : figureDomain d.items d.config)
    (blankOK : blankDomain d.items d.blank) (members : ∀ m ∈ d.needs, .need m.1 ∈ d.items)
    (b : Nat) (kept : Nat → Bool) (padded : d.augment.keeps b kept) : d.keeps b kept := by
  have earlier (n : Nat) (h : d.beforeNeed b n) : d.augment.beforeNeed b n := by
    intro p pm lt
    rw [augmented_here]
    exact h p ((text_mem_padded_source d.items d.config p).mp pm) lt
  constructor
  · intro n mem t part tm positive target reached loadFits groupFits
    rw [← augmented_here]
    apply padded.1 n mem t part ((text_mem_padded_source d.items d.config t).mpr tm) positive
      ((d.augmented_text_target kept n.1 t tm).mpr target) (earlier _ reached)
    · have eq := d.augmented_load valid blankOK b kept (.text t) tm
      change d.augment.load b kept t = d.load b kept t at eq
      rw [eq]; exact loadFits
    · exact d.augmented_group_fits b kept _ _ (fun m => (d.augmented_text_target kept m t tm).symm)
        members groupFits
  · intro n mem f bound target reached prior loadFits groupFits
    have fig := d.original_fig_member valid f bound
    have data := I3_padding_keeps_original_figure_data d.config (sourceEnd d.items) f bound
    have posEq : d.augment.pos f = d.pos f := data.1
    have sizeEq : d.augment.size f = d.size f := data.2
    have within : f < d.augment.count := by
      rw [augmented_count]
      cases h : d.config <;> simp [count,h,figureCount] at bound <;> omega
    apply padded.2 n mem f within ((d.augmented_figure_target kept n.1 f bound).mpr target)
      (earlier _ reached) (d.augmented_earlier_figures kept n.1 (members n mem) prior)
    · have eq := d.augmented_load valid blankOK b kept (.figure (d.pos f)) fig
      change d.augment.load b kept (d.pos f) = d.load b kept (d.pos f) at eq
      rw [posEq,sizeEq,eq]; exact loadFits
    · exact d.augmented_group_fits b kept _ _ (fun m => (d.augmented_figure_target kept m f bound).symm)
        members groupFits

theorem unpad_base (d : NeedSource) (ordered : sourceOrdered d.items)
    (valid : figureDomain d.items d.config) (blankOK : blankDomain d.items d.blank)
    (b : Nat) (kept : Nat → Bool) (padded : d.augment.base b kept) : d.base b kept := by
  obtain ⟨range,cap,rule,first,p1⟩ := padded
  refine ⟨by simpa only [d.augmented_text.1] using range, ?_, ?_, ?_, ?_⟩
  · apply I3_unpad_need_capacity d.items d.config valid d.blank blankOK d.used d.capacity b kept
    simp only [augmented_count] at cap
    exact cap
  · have old := I3_unpad_need_figures_rule d.config (sourceEnd d.items) d.used d.capacity b
      d.augment.rank d.augment.plain (d.augment.charge b kept) d.augment.block d.needs kept
    have all := old (by rw [augmented_count] at rule; exact rule)
    intro f actual
    have fig := d.original_fig_member valid f actual
    have ch := d.augmented_charge valid blankOK b kept (.figure (d.pos f)) fig
    change d.augment.charge b kept (d.pos f) = d.charge b kept (d.pos f) at ch
    have plains (q : Nat) : d.augment.plain q = d.plain q := by
      simp only [plain,d.augmented_text.1]; rfl
    have blocks : d.augment.block = d.block := by
      funext q
      apply propext
      exact and_congr (text_mem_padded_source d.items d.config q) Iff.rfl
    change d.augment.charge b kept (figurePosAt d.config f) = d.charge b kept (figurePosAt d.config f) at ch
    have one := all f actual
    simpa only [figureHasRoom, d.augmented_text.2, plains, blocks, ch] using one
  · exact I3_unpad_need_first_content d.items d.config valid ordered d.used b kept first
  · intro t tm here
    apply (I3_padding_preserves_text_P1 d.used d.capacity b t d.items d.config d.space kept d.needs tm).mp
    have paddedP1 := p1 t ((text_mem_padded_source d.items d.config t).mpr tm) (by rwa [augmented_here])
    rw [augmented_count] at paddedP1
    exact paddedP1

theorem two_figure_solution (d : NeedSource) (a sa z sz q : Nat)
    (cfg : d.config = .two a sa z sz) (bl : d.blank = some q)
    (ordered : sourceOrdered d.items) (figValid : figureDomain d.items d.config)
    (capacityPos : 0 < d.capacity) (usedFits : d.used ≤ d.capacity)
    (aPos : 0 < sa) (zPos : 0 < sz) (aFits : sa ≤ d.capacity)
    (qa : q ≠ a) (qz : q ≠ z) (members : ∀ m ∈ d.needs, .need m.1 ∈ d.items) :
    ∃ b kept, d.base b kept ∧ d.keeps b kept := by
  rw [cfg] at figValid
  obtain ⟨az, aIn, zIn, two⟩ := figValid
  obtain ⟨b, bound, good, stop⟩ := I3_two_figure_need_maximal_placement d.capacity d.used q a z sa sz
    d.items ordered d.space d.needs capacityPos usedFits aPos zPos aFits az qa qz aIn zIn two
  let pos := fun i : Nat => if i = 0 then a else z
  let size := fun i : Nat => if i = 0 then sa else sz
  let top := blankAtTopSource d.used q d.items (fun _ => true) (fun _ => true)
  let mask := fun i => !beforeBlankMask a z q i && !top
  let room := fun i => @decide (needFigureStatic d.capacity d.used (fun i => d.rank (pos i))
    (fun i => d.plain (pos i)) size pos mask d.block d.needs i) (Classical.propDecidable _)
  let kept := greedyFigure (fun i => decide (d.rank (pos i) ≤ b)) room
  obtain ⟨fit,p1,firstText,firstFig⟩ := I3_normalize_two_figure_need_break d.capacity d.used q a z sa sz b
    d.items ordered d.space d.needs good
  have canonicalTop : d.atTop b kept q = top := by
    unfold atTop atPos here
    rw [cfg]
    exact I3_two_figure_need_blank_charge_unique d.used q a z b d.items ordered kept firstText firstFig
  have chargeEq (p : Nat) : d.charge b kept p = (decide (q < p) && !top) := by
    unfold charge
    rw [bl]
    exact congrArg (fun t => decide (q < p) && !t) canonicalTop
  have maskEq (i : Nat) (within : i < 2) : mask i = d.charge b kept (pos i) := by
    rw [chargeEq]
    by_cases zero : i = 0
    · subst i; dsimp [mask,beforeBlankMask,pos]
      by_cases earlier : a < q <;> simp [earlier,show (q < a) ↔ ¬ a < q by omega]
    · have one : i = 1 := by omega
      subst i; dsimp [mask,beforeBlankMask,pos]
      by_cases earlier : z < q <;> simp [earlier,show (q < z) ↔ ¬ z < q by omega]
  have eqPos : d.pos = pos := by unfold NeedSource.pos; rw [cfg]; rfl
  have eqSize : d.size = size := by unfold NeedSource.size; rw [cfg]; rfl
  have eqCount : d.count = 2 := by unfold count; rw [cfg]; rfl
  have loadEq (p : Nat) :
      d.load b kept p = d.used + ((sourceTextPositions d.items).filter (fun v => decide (v < p) && d.here b v)).length +
        keptRowsThrough (fun i => kept i && decide (pos i < p)) size 2 + (if q < p ∧ top = false then 1 else 0) := by
    unfold load
    rw [eqCount,eqSize,eqPos,chargeEq]
    by_cases lt : q < p <;> cases top <;> simp [lt]
  refine ⟨b,kept,⟨bound,?_,?_,?_,?_⟩,?_,?_⟩
  · simpa only [eqSize,eqCount,placedBlank,bl,waiting,atPos,cfg,Option.elim,figureWaitingAtPos,
      figureKeptAtPos,here] using fit
  · rw [eqCount,eqPos,eqSize]
    apply figures27_of_static
    intro i hi
    have static := I3_greedyFigures_rule 2 (fun i => decide (d.rank (pos i) ≤ b)) room i hi
    have check : room i = true ↔ needFigureStatic d.capacity d.used (fun i => d.rank (pos i))
      (fun i => d.plain (pos i)) size pos mask d.block d.needs i := @decide_eq_true_iff _ (Classical.propDecidable _)
    apply static.trans
    apply and_congr_right; intro _
    apply and_congr_right; intro _
    apply check.trans
    simp only [needFigureStatic,figureHasRoom,maskEq i hi]
  · intro empty item first
    cases item with
    | text p => exact firstText empty p first
    | figure p => simpa [cfg,figureKeptAtPos] using firstFig empty p first
    | blank _ | need _ => exact (I3_firstContent_is_earliest d.items ordered _ first).1
  · intro t tm here
    rw [eqCount,eqPos,eqSize]
    exact p1 t tm here
  · intro n mem t part tm positive target reached fits records
    apply I3_maximal_two_figure_need_keeps_text d.capacity d.used q a z sa sz b n.1 t part
      d.items ordered az qa qz aPos zPos aIn zIn positive d.space d.needs members tm reached
      (members n mem) good stop
    · simpa only [textTarget,eqCount,eqPos] using target
    · rw [loadEq] at fits; exact fits
    · unfold group textTarget before at records
      rw [eqCount,eqPos,eqSize] at records
      exact records
  · intro n mem f within target reached prior fits records
    rw [eqCount] at within
    apply I3_maximal_two_figure_need_keeps_figure d.capacity d.used q a z sa sz b n.1 f
      d.items ordered az qa qz aIn zIn aPos zPos d.space d.needs within reached members
      (members n mem) good stop
    · simpa only [figureTarget,eqPos] using target
    · rw [loadEq,eqSize,eqPos] at fits; exact fits
    · simpa only [earlierFigures,eqCount,eqPos] using prior
    · unfold group figureTarget before at records
      rw [eqCount,eqPos,eqSize] at records
      exact records

theorem all_inputs_have_a_placement (d : NeedSource) (ordered : sourceOrdered d.items)
    (valid : figureDomain d.items d.config) (blankOK : blankDomain d.items d.blank)
    (capacityPos : 0 < d.capacity) (usedFits : d.used ≤ d.capacity)
    (sizes : ∀ i, i < d.count → 0 < d.size i ∧ d.size i ≤ d.capacity)
    (members : ∀ m ∈ d.needs, .need m.1 ∈ d.items) :
    ∃ b kept, d.base b kept ∧ d.keeps b kept := by
  have augOrder := I3_padding_preserves_source_order d.items d.config ordered
  have augValid := I3_padded_need_input_has_two_figures d.items d.config valid
  have two : ∃ a sa z sz, d.augment.config = .two a sa z sz := by
    cases h : d.config <;> simp [augment,h,paddedNeedConfig]
  obtain ⟨a,sa,z,sz,cfg⟩ := two
  have augSizes (i : Nat) (hi : i < 2) : 0 < d.augment.size i ∧ d.augment.size i ≤ d.capacity := by
    by_cases actual : i < d.count
    · have same := (I3_padding_keeps_original_figure_data d.config (sourceEnd d.items) i actual).2
      change d.augment.size i = d.size i at same
      rw [same]
      exact sizes i actual
    · cases h : d.config with
      | zero => by_cases z : i = 0 <;> simp [size,augment,h,paddedNeedConfig,figureSizeAt,z] <;> omega
      | one p s =>
          have nz : i ≠ 0 := by simp [count,h,figureCount] at actual; omega
          simp [size,augment,h,paddedNeedConfig,figureSizeAt,nz]; omega
      | two p s q v => simp [count,h,figureCount] at actual; omega
  have saOK := augSizes 0 (by decide)
  have szOK := augSizes 1 (by decide)
  simp only [size,cfg,figureSizeAt,if_pos rfl,show ¬ 1 = 0 by decide,if_false] at saOK szOK
  let q := d.blank.getD (sourceEnd d.augment.items)
  have blankIs : d.augment.blank = some q := rfl
  have distinct (p : Nat) (fig : .figure p ∈ d.augment.items) : q ≠ p := by
    cases h : d.blank with
    | none =>
      have lt : p < sourceEnd d.augment.items := I3_original_positions_before_padding _ _ fig
      simp [q,h]; omega
    | some blank =>
      rw [h] at blankOK
      have actual : .blank blank ∈ d.augment.items := List.mem_append_of_mem_left _ blankOK.1
      intro eq
      have bad := I3_sourceOrdered_unique_position _ augOrder _ _ actual fig
        (by simpa [q,h,sourcePos] using eq)
      cases bad
  have figs : figureDomain d.augment.items d.augment.config := augValid
  rw [cfg] at figs
  obtain ⟨b,kept,base,keeps⟩ := two_figure_solution d.augment a sa z sz q cfg blankIs augOrder augValid
    capacityPos usedFits saOK.1 szOK.1 saOK.2 (distinct a figs.2.1) (distinct z figs.2.2.1)
    (fun m hm => List.mem_append_of_mem_left _ (members m hm))
  exact ⟨b,kept,d.unpad_base ordered valid blankOK b kept base,d.unpad_keeps valid blankOK members b kept keeps⟩

/-- The original Alloy antecedents use a set of preceding needs at
    the same target. The list of needs is stored in source order. -/
def sourceKeeps (d : NeedSource) (b : Nat) (kept : Nat → Bool)
    (written : (Nat × Nat) → (Nat → Prop) → Prop) : Prop :=
  (∀ n ∈ d.needs, ∀ t firstPart, .text t ∈ d.items → 0 < firstPart →
    d.textTarget kept n.1 t → d.beforeNeed b n.1 → d.earlierFigures kept n.1 →
    d.load b kept t + firstPart ≤ d.capacity → written n (fun m => d.textTarget kept m t) →
    d.here b t = true) ∧
  (∀ n ∈ d.needs, ∀ f, f < d.count → d.figureTarget kept n.1 f → d.beforeNeed b n.1 →
    d.earlierFigures kept n.1 → d.load b kept (d.pos f) + d.size f ≤ d.capacity →
    written n (fun m => d.figureTarget kept m f) → kept f = true)

theorem source_keeps_of_written (d : NeedSource) (b : Nat) (kept : Nat → Bool)
    (generic : d.keeps b kept) (written : (Nat × Nat) → (Nat → Prop) → Prop)
    (fits : ∀ n ∈ d.needs, ∀ target : Nat → Prop, target n.1 → written n target →
      writtenGroupFits d.capacity 0 (d.before b kept) (d.group target)) :
    d.sourceKeeps b kept written := by
  constructor
  · intro n mem t part tm positive target reached _ load met
    exact generic.1 n mem t part tm positive target reached load (fits n mem _ target met)
  · intro n mem f bound target reached earlier load met
    exact generic.2 n mem f bound target reached earlier load (fits n mem _ target met)

def singleWritten (d : NeedSource) (b : Nat) (kept : Nat → Bool)
    (n : Nat × Nat) (_ : Nat → Prop) := n.2 ≤ d.capacity - d.before b kept n.1

def recordWritten (d : NeedSource) (b : Nat) (kept : Nat → Bool)
    (_ : Nat × Nat) (target : Nat → Prop) := ∀ m ∈ d.needs, target m.1 →
      (∀ k ∈ d.needs, target k.1 → k.1 < m.1 → k.2 < m.2) →
      m.2 ≤ d.capacity - d.before b kept m.1

theorem needSpaceNone (d : NeedSource) (ordered : sourceOrdered d.items)
    (valid : figureDomain d.items d.config) (blankOK : blankDomain d.items d.blank)
    (capacityPos : 0 < d.capacity) (usedFits : d.used ≤ d.capacity)
    (sizes : ∀ i, i < d.count → 0 < d.size i ∧ d.size i ≤ d.capacity)
    (members : ∀ m ∈ d.needs, .need m.1 ∈ d.items)
    (domain : d.needs = [] ∨ ∃ p, d.needs = [(p,2)]) :
    ∃ b kept, d.base b kept ∧ d.sourceKeeps b kept (d.singleWritten b kept) := by
  obtain ⟨b,kept,base,generic⟩ := d.all_inputs_have_a_placement ordered valid blankOK capacityPos
    usedFits sizes members
  refine ⟨b,kept,base,d.source_keeps_of_written b kept generic _ ?_⟩
  intro n mem target hit met
  rcases domain with none | ⟨p,one⟩
  · simp [none] at mem
  · simp [one] at mem
    subst n
    simpa [group,one,hit,writtenGroupFits,singleWritten] using met

theorem needMoreNone (d : NeedSource) (ordered : sourceOrdered d.items)
    (valid : figureDomain d.items d.config) (blankOK : blankDomain d.items d.blank)
    (capacityPos : 0 < d.capacity) (usedFits : d.used ≤ d.capacity)
    (sizes : ∀ i, i < d.count → 0 < d.size i ∧ d.size i ≤ d.capacity)
    (members : ∀ m ∈ d.needs, .need m.1 ∈ d.items)
    (domain : ∃ a z : Nat × Nat, d.needs = [a,z] ∧ a.1 < z.1) :
    ∃ b kept, d.base b kept ∧ d.sourceKeeps b kept (d.recordWritten b kept) := by
  obtain ⟨b,kept,base,generic⟩ := d.all_inputs_have_a_placement ordered valid blankOK capacityPos
    usedFits sizes members
  refine ⟨b,kept,base,d.source_keeps_of_written b kept generic _ ?_⟩
  intro n _ target _ met
  obtain ⟨a,z,two,lt⟩ := domain
  have aFit (hit : target a.1) : a.2 ≤ d.capacity - d.before b kept a.1 := by
    apply met a (by simp [two]) hit
    intro k km _ early
    simp [two] at km
    rcases km with rfl | rfl <;> omega
  have zFit (hit : target z.1) (earlier : target a.1 → a.2 < z.2) :
      z.2 ≤ d.capacity - d.before b kept z.1 := by
    apply met z (by simp [two]) hit
    intro k km atK early
    simp [two] at km
    rcases km with rfl | rfl
    · exact earlier atK
    · omega
  rcases a with ⟨pa, ha⟩
  rcases z with ⟨pz, hz⟩
  by_cases ta : target pa <;> by_cases tz : target pz <;>
    simp [group,two,ta,tz,writtenGroupFits] at * <;> omega

end NeedSource

namespace GreedyFigureCommand

/-- For the domain with at most one figure, reserve its rows precisely
    when the source prefix and the figure itself fit. Fill the rest with
    the longest text prefix. The skipped figure, if present, is too
    large at its source position regardless of the final break. -/
theorem greedyFigure (capacity used textCount : Nat) (usedFits : used ≤ capacity)
    (figure : Option (Nat × Nat))
    (rankBound : ∀ r h, figure = some (r,h) → r ≤ textCount) :
    ∃ b : Nat, ∃ kept : Bool,
      b ≤ textCount ∧
      (match figure with
      | none => kept = false
      | some (rank,height) => kept = decide (rank ≤ b ∧ used + rank + height ≤ capacity)) ∧
      (let load := used + b + (if kept then figure.elim 0 Prod.snd else 0)
       load ≤ capacity ∧ (b = textCount ∨ capacity < load + 1)) := by
  cases figure with
  | none =>
    refine ⟨min textCount (capacity-used),false, Nat.min_le_left _ _,rfl,?_⟩
    change used + min textCount (capacity-used) + 0 ≤ capacity ∧
      (min textCount (capacity-used) = textCount ∨ capacity < used + min textCount (capacity-used) + 0 + 1)
    omega
  | some data =>
    obtain ⟨rank,height⟩ := data
    have bounded := rankBound rank height rfl
    by_cases room : used + rank + height ≤ capacity
    · let b := min textCount (capacity-used-height)
      have ready : rank ≤ b := by dsimp [b]; omega
      refine ⟨b,true,Nat.min_le_left _ _,by simp [ready,room],?_⟩
      change used + b + height ≤ capacity ∧ (b = textCount ∨ capacity < used + b + height + 1)
      dsimp [b]; omega
    · let b := min textCount (capacity-used)
      refine ⟨b,false,Nat.min_le_left _ _,by simp [room],?_⟩
      change used + b + 0 ≤ capacity ∧ (b = textCount ∨ capacity < used + b + 0 + 1)
      dsimp [b]; omega

theorem figure_text_ready_iff (items : List SourceItem) (ordered : sourceOrdered items)
    (b p : Nat) : textBeforeCount items p ≤ b ↔
      ∀ t, .text t ∈ items → t < p → textHereAtBreak items b t = true := by
  constructor
  · intro ready t member before
    exact decide_eq_true (Nat.lt_of_lt_of_le (I3_source_text_rank_strict_at_member items t p member before) ready)
  · intro all
    apply Nat.le_of_not_gt
    intro beyond
    have count := I3_load_before_unreached_position items ordered b p (Nat.le_of_lt beyond)
    have eq : (sourceTextPositions items).filter (fun t => decide (t < p) && textHereAtBreak items b t) =
        (sourceTextPositions items).filter (fun t => decide (t < p)) := by
      apply filter_eq_on_members
      intro t member
      by_cases before : t < p
      · simp [before,all t ((I3_source_text_position_member items t).mp member) before]
      · simp [before]
    rw [eq] at count
    rw [I3_source_text_before_count] at beyond
    unfold countEarlierText at beyond
    omega

theorem greedyFigure_from_manuscript (capacity used : Nat) (usedFits : used ≤ capacity)
    (items : List SourceItem) (ordered : sourceOrdered items) (p h : Nat) :
    ∃ b : Nat, ∃ kept : Bool, b ≤ (sourceTextPositions items).length ∧
      (kept = true ↔ (∀ t, .text t ∈ items → t < p → textHereAtBreak items b t = true) ∧
        used + textBeforeCount items p + h ≤ capacity) ∧
      used + b + (if kept then h else 0) ≤ capacity ∧
      (b = (sourceTextPositions items).length ∨ capacity < used + b + (if kept then h else 0) + 1) := by
  have rankBound : textBeforeCount items p ≤ (sourceTextPositions items).length := by
    apply Nat.le_of_not_gt
    intro tooBig
    have contradiction := I3_missed_source_has_another_text items (sourceTextPositions items).length p tooBig
    omega
  obtain ⟨b,kept,bound,rule,fit,fill⟩ := greedyFigure capacity used (sourceTextPositions items).length usedFits
    (some (textBeforeCount items p,h)) (by intro r z eq; cases eq; exact rankBound)
  refine ⟨b,kept,bound,?_,fit,fill⟩
  change kept = decide (_ ∧ _) at rule
  rw [rule, decide_eq_true_eq, figure_text_ready_iff items ordered b p]

end GreedyFigureCommand

/- The two-need input judges the larger requirement; both P1 checks are
   satisfied when a line is retained. The preceding space affects fit,
   but neither requirement's remaining-line count. -/
theorem I3_need_space_two_needs_simple_exists
    (capacity used firstNeed secondNeed : Nat)
    (usedFits : used ≤ capacity)
    (firstPositive : 1 ≤ firstNeed) :
    ∃ brk : Fin 3,
      needSpaceSimpleBase capacity used brk ∧
      (brk.val = 2 →
        firstNeed ≤ capacity - used ∧
        secondNeed ≤ capacity - used) ∧
      ((firstNeed ≤ capacity - used ∧
        secondNeed ≤ capacity - used) ∧
        used + (if 1 ≤ brk.val then 1 else 0) + 1 ≤ capacity →
        brk.val = 2) := by
  have maxPositive : 1 ≤ max firstNeed secondNeed :=
    Nat.le_trans firstPositive (Nat.le_max_left _ _)
  obtain ⟨brk, base, met, keeps⟩ :=
    I3_need_space_one_block_exists capacity used
      (max firstNeed secondNeed) usedFits maxPositive
  refine ⟨brk, base, ?_, ?_⟩
  · intro placed
    have enough := met placed
    exact ⟨Nat.le_trans (Nat.le_max_left _ _) enough,
      Nat.le_trans (Nat.le_max_right _ _) enough⟩
  · rintro ⟨⟨firstEnough, secondEnough⟩, fits⟩
    apply keeps
    exact ⟨Nat.max_le.mpr ⟨firstEnough, secondEnough⟩, fits⟩

/- The first part may occupy more than one line. With a space first in
   an empty column, noSendFromEmpty also requires the one-space break
   when the following block cannot stay. -/
theorem I3_need_space_two_needs_first_part_exists
    (capacity used firstNeed secondNeed firstPart : Nat)
    (positiveCapacity : 1 ≤ capacity)
    (usedFits : used ≤ capacity)
    (positivePart : 1 ≤ firstPart) :
    ∃ brk : Fin 3,
      used + brk.val ≤ capacity ∧
      (brk.val = 2 →
        firstNeed ≤ capacity - used ∧
        secondNeed ≤ capacity - used) ∧
      ((firstNeed ≤ capacity - used ∧
        secondNeed ≤ capacity - used) ∧
        used + 1 + firstPart ≤ capacity → brk.val = 2) ∧
      (used = 0 → 1 ≤ brk.val) := by
  by_cases bothMet :
      firstNeed ≤ capacity - used ∧
        secondNeed ≤ capacity - used
  · by_cases firstFits : used + 1 + firstPart ≤ capacity
    · refine ⟨2, ?_, ?_, ?_, ?_⟩
      all_goals simp_all <;> omega
    · by_cases spaceFits : used + 1 ≤ capacity
      · refine ⟨1, ?_, ?_, ?_, ?_⟩
        all_goals simp_all <;> omega
      · refine ⟨0, ?_, ?_, ?_, ?_⟩
        all_goals simp_all <;> omega
  · by_cases spaceFits : used + 1 ≤ capacity
    · refine ⟨1, ?_, ?_, ?_, ?_⟩
      all_goals simp_all <;> omega
    · refine ⟨0, ?_, ?_, ?_, ?_⟩
      all_goals simp_all <;> omega

/- For any number of needs sharing one block, a record-high check
   suffices to choose a break. The single preceding space consumes capacity
   but contributes nothing to placedBefore at any of those needs. -/
theorem I3_shared_needs_first_part_exists
    (capacity used firstPart : Nat) (needs : List Nat)
    (capacityPositive : 1 ≤ capacity) (usedFits : used ≤ capacity) :
    ∃ brk : Fin 3,
      used + (if brk.val = 2 then 1 + firstPart else brk.val) ≤ capacity ∧
      (brk.val = 2 → ∀ n ∈ needs, n ≤ capacity - used) ∧
      (recordNeedsFit (capacity - used) 0 needs ∧
        used + 1 + firstPart ≤ capacity → brk.val = 2) ∧
      (used = 0 → 1 ≤ brk.val) := by
  by_cases keep : recordNeedsFit (capacity - used) 0 needs ∧
      used + 1 + firstPart ≤ capacity
  · refine ⟨2, ?_, ?_, fun _ => rfl, ?_⟩
    · change used + (1 + firstPart) ≤ capacity
      simpa [Nat.add_assoc] using keep.2
    · exact fun _ => (I3_record_needs_fit_iff_all _ _ _ (Nat.zero_le _)).mp keep.1
    · simp
  · by_cases spaceFits : used + 1 ≤ capacity
    · refine ⟨1, spaceFits, ?_, fun h => (keep h).elim, ?_⟩
      · intro h
        cases h
      · simp
    · refine ⟨0, by simpa using usedFits, ?_, fun h => (keep h).elim, ?_⟩
      · intro h
        cases h
      · intro empty
        omega

theorem I3_need_space_fixture_source_break (brk : Fin 3) :
    textHereAtBreak [.need 0, .text 1, .need 2, .text 3]
        brk.val 1 = decide (1 ≤ brk.val) ∧
      textHereAtBreak [.need 0, .text 1, .need 2, .text 3]
        brk.val 3 = decide (brk.val = 2) := by
  have cases : brk.val = 0 ∨ brk.val = 1 ∨ brk.val = 2 := by
    have bound := brk.isLt
    omega
  rcases cases with zero | one | two
  · simp [zero, textHereAtBreak, textBeforeCount, earlierTextItem]
  · simp [one, textHereAtBreak, textBeforeCount, earlierTextItem]
  · simp [two, textHereAtBreak, textBeforeCount, earlierTextItem]

/- Historical two-need input: capacity 3, one used line, need 1, space,
   need 3, then a one-line paragraph. The older P7 tests only the first
   need and keeps the paragraph; P1 tests the larger need before that
   paragraph and rejects it. -/
def needMore27Base (brk : Fin 3) : Prop :=
  1 + brk.val ≤ 3

def needMore27OldKeep (brk : Fin 3) : Prop :=
  (3 - 1 ≥ 1 ∧
    1 + (if 1 ≤ brk.val then 1 else 0) + 1 ≤ 3) →
    brk.val = 2

def needMore27NeedMet (brk : Fin 3) : Prop :=
  brk.val = 2 → 3 - 1 ≥ 3

theorem needMore27 :
    (∃ brk : Fin 3, needMore27Base brk ∧ needMore27OldKeep brk) ∧
    (∃ brk : Fin 3, needMore27Base brk ∧ needMore27NeedMet brk) ∧
    (∀ brk : Fin 3,
      ¬ (needMore27Base brk ∧ needMore27OldKeep brk ∧
        needMore27NeedMet brk)) := by
  refine ⟨⟨2, by simp [needMore27Base],
      by simp [needMore27OldKeep]⟩,
    ⟨0, by simp [needMore27Base],
      by simp [needMore27NeedMet]⟩, ?_⟩
  intro brk ⟨_, oldRule, needRule⟩
  have oldForces : brk.val = 2 := by
    apply oldRule
    constructor
    · decide
    · split <;> omega
  have impossible := needRule oldForces
  omega

/- A one-line body, one-line footnote separator, and one-line note cannot
   all fit in a column of capacity 1 or 2. Golem ADR 0353 makes this a
   diagnostic instead of retrying the same unplaceable note forever. -/
theorem I4_footnote_capacity_conflict (capacity : Nat) (small : capacity ≤ 2) :
    ¬ (1 + 1 + 1 ≤ capacity) := by
  omega

inductive FootnoteOutcome where
  | placed | sent | diagnostic
  deriving DecidableEq, Repr

/- The empty-column decision for one marker line, one separator, and one
   first note line. A temporary reduction sends the note to the full column. -/
def footnoteDecision (base current separator : Nat) : FootnoteOutcome :=
  if 2 + separator ≤ current then .placed
  else if current < base ∧ 2 + separator ≤ base then .sent
  else .diagnostic

def footnoteFinal (base current separator : Nat) : FootnoteOutcome :=
  match footnoteDecision base current separator with
  | .sent => footnoteDecision base base separator
  | x => x

theorem I4_footnote_small_diagnostic (base : Nat) (small : base ≤ 2) :
    footnoteFinal base base 1 = .diagnostic := by
  have tooShort : ¬ 2 + 1 ≤ base := by omega
  simp [footnoteFinal, footnoteDecision, tooShort]

theorem I4_footnote_adjusted_column_places (base current : Nat)
    (fitsBase : 3 ≤ base) (short : current < 3) :
    footnoteFinal base current 1 = .placed := by
  have tooShort : ¬ 2 + 1 ≤ current := by omega
  have send : current < base ∧ 2 + 1 ≤ base := by omega
  simp [footnoteFinal, footnoteDecision, tooShort, send, fitsBase]

theorem I4_footnote_final_never_sends (base current separator : Nat) :
    footnoteFinal base current separator ≠ .sent := by
  by_cases fits : 2 + separator ≤ current
  · simp [footnoteFinal, footnoteDecision, fits]
  · by_cases send : current < base ∧ 2 + separator ≤ base
    · simp [footnoteFinal, footnoteDecision, fits, send, send.2]
    · simp [footnoteFinal, footnoteDecision, fits, send]

namespace FootnoteSplit

structure Note where
  id : Nat
  lines : Nat

structure Part where
  id : Nat
  start : Nat
  lines : Nat
  deriving DecidableEq

def full (n : Note) : Part := ⟨n.id,0,n.lines⟩

/-- A reserved caption or box can leave negative room. In that case
    splitNotes defers the full suffix with offset zero. -/
def split (room : Int) : List Note → List Part × List Part
  | [] => ([],[])
  | n :: rest =>
    if (n.lines : Int) ≤ room then
      let tail := split (room - n.lines) rest
      (full n :: tail.1,tail.2)
    else if room > 0 then
      ([⟨n.id,0,room.toNat⟩],⟨n.id,room.toNat,n.lines-room.toNat⟩ :: rest.map full)
    else ([],full n :: rest.map full)

/-- Identify every output grid line by note ID and zero-based index,
    so equality detects gaps, duplication and changes of order. -/
def linesFrom (id start : Nat) : Nat → List (Nat × Nat)
  | 0 => []
  | n+1 => (id,start) :: linesFrom id (start+1) n

theorem lines_split (id start a b : Nat) :
    linesFrom id start a ++ linesFrom id (start+a) b = linesFrom id start (a+b) := by
  induction a generalizing start with
  | zero => simp [linesFrom]
  | succ a ih =>
    rw [Nat.succ_add]
    simp only [linesFrom,List.cons_append,List.cons.injEq,true_and]
    have eq : start + (a+1) = (start+1)+a := by omega
    rw [eq,ih]

def trace : List Part → List (Nat × Nat)
  | [] => []
  | p :: rest => linesFrom p.id p.start p.lines ++ trace rest

theorem I5_splitNotes_exact (ns : List Note) (room : Int) :
    trace (split room ns).1 ++ trace (split room ns).2 = trace (ns.map full) := by
  induction ns generalizing room with
  | nil => rfl
  | cons n rest ih =>
    by_cases fits : (n.lines : Int) ≤ room
    · simp only [split, fits, if_true, List.map_cons, trace,List.append_assoc]
      rw [ih]
    · by_cases positive : room > 0
      · have cast := Int.toNat_of_nonneg (show 0 ≤ room by omega)
        have sum : room.toNat + (n.lines - room.toNat) = n.lines := by omega
        simp only [split,fits,positive,if_false,if_true,trace,List.append_nil,List.map_cons,full]
        rw [← List.append_assoc]
        have join := lines_split n.id 0 room.toNat (n.lines-room.toNat)
        simp only [Nat.zero_add,sum] at join
        rw [join]
      · simp [split,fits,positive,trace]

/-- The part emitted by carryNote and the pending suffix start exactly
    where the preceding part stopped, including a zero-room column. -/
def carry (room : Nat) (pending : Part) : Part × Option Part :=
  let shown := min pending.lines room
  (⟨pending.id,pending.start,shown⟩,
    if shown < pending.lines then some ⟨pending.id,pending.start+shown,pending.lines-shown⟩ else none)

theorem I5_carryNote_exact (room : Nat) (p : Part) :
    trace ((carry room p).1 :: (carry room p).2.toList) = trace [p] := by
  by_cases notEnough : room < p.lines
  · have shown := Nat.min_eq_right (Nat.le_of_lt notEnough)
    simp only [carry,shown,notEnough,if_true,Option.toList,trace,List.append_nil]
    have eq := lines_split p.id p.start room (p.lines-room)
    have count : room + (p.lines-room) = p.lines := by omega
    rwa [count] at eq
  · have shown := Nat.min_eq_left (show p.lines ≤ room by omega)
    simp [carry,shown,trace,Option.toList]

theorem I4_carryNote_remainder_decreases (room : Nat) (p rest : Part) (positive : 0 < room)
    (requeued : (carry room p).2 = some rest) : rest.lines < p.lines := by
  unfold carry at requeued
  dsimp only at requeued
  split at requeued
  · rename_i notEnough
    cases requeued
    simp only
    omega
  · contradiction

/-- A body line introduces its notes in manuscript order. The abstract
    column counter counts consecutive no-room transitions before an open
    column. Replenishing it is allowed after consuming body or note data. -/
structure Body where
  id : Nat
  notes : List Note

structure Combined where
  body : List Body
  pending : List Part
  blockedColumns : Nat

def pendingSize : List Part → Nat
  | [] => 0
  | p :: rest => 1 + p.lines + pendingSize rest

def bodyNotes : List Body → List (Nat × Nat)
  | [] => []
  | line :: remaining => trace (line.notes.map full) ++ bodyNotes remaining

def noteTrace (s : Combined) := trace s.pending ++ bodyNotes s.body

private theorem trace_append (xs ys : List Part) : trace (xs ++ ys) = trace xs ++ trace ys := by
  induction xs with
  | nil => simp [trace]
  | cons x xs ih => simp [trace,ih,List.append_assoc]

/-- A footprint separates the ordered body IDs and individual note lines.
    A retry can emit a zero-length note segment, whose trace is empty. -/
inductive Progress : Combined → List Nat → List (Nat × Nat) → Combined → Prop where
  | line (l : Body) (rest : List Body) (slots : Int) (before after : Nat) :
    Progress ⟨l::rest,[],before⟩ [l.id] (trace (split slots l.notes).1)
      ⟨rest,(split slots l.notes).2,after⟩
  | lineWaiting (l : Body) (rest : List Body) (ps : List Part) (before after : Nat) :
    Progress ⟨l::rest,ps,before⟩ [l.id] [] ⟨rest,ps ++ l.notes.map full,after⟩
  | nextColumn (body : List Body) (ps : List Part) (before : Nat) :
    Progress ⟨body,ps,before+1⟩ [] [] ⟨body,ps,before⟩
  | carryPart (body : List Body) (p : Part) (ps : List Part) (slots before after : Nat)
      (possible : 0 < slots ∨ p.lines = 0) :
    Progress ⟨body,p::ps,before⟩ [] (trace [(carry slots p).1])
      ⟨body,(carry slots p).2.toList ++ ps,after⟩

def progressRank (s : Combined) : Nat × Nat × Nat := (s.body.length,pendingSize s.pending,s.blockedColumns)

theorem I4_combined_decreases {s t : Combined} {bodyOut : List Nat} {notesOut : List (Nat × Nat)}
    (move : Progress s bodyOut notesOut t) :
    Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) (progressRank t) (progressRank s) := by
  cases move with
  | line | lineWaiting => apply Prod.Lex.left; simp [progressRank]
  | nextColumn => apply Prod.Lex.right; apply Prod.Lex.right; simp [progressRank]
  | carryPart body p ps slots before after possible =>
      apply Prod.Lex.right
      apply Prod.Lex.left
      cases eq : (carry slots p).2 with
      | none => simp [eq,pendingSize,progressRank]; omega
      | some suffix =>
        have positive : 0 < slots := by
          rcases possible with h | zero
          · exact h
          · simp [carry,zero] at eq
        have decrease := I4_carryNote_remainder_decreases slots p suffix positive eq
        simp [progressRank,eq,pendingSize]
        omega

theorem I5_combined_step_exact {s t : Combined} {bodyOut : List Nat} {notesOut : List (Nat × Nat)}
    (move : Progress s bodyOut notesOut t) :
    bodyOut ++ t.body.map Body.id = s.body.map Body.id ∧ notesOut ++ noteTrace t = noteTrace s := by
  cases move with
  | line l rest slots before after =>
      simp only [noteTrace,bodyNotes,trace,List.map_cons,List.cons_append,List.nil_append,true_and]
      rw [← List.append_assoc,I5_splitNotes_exact]
  | lineWaiting l rest ps before after =>
      simp [noteTrace,bodyNotes,trace_append,List.append_assoc]
  | nextColumn => simp [noteTrace]
  | carryPart body p ps slots before after possible =>
      refine ⟨rfl,?_⟩
      have exactParts := I5_carryNote_exact slots p
      simp only [trace,List.append_nil] at exactParts
      simp only [noteTrace,trace_append,trace,List.append_nil,List.append_assoc]
      rw [← List.append_assoc (linesFrom _ _ _) (trace _) (trace ps ++ bodyNotes body),exactParts]

theorem I4_combined_termination :
    WellFounded (fun t s : Combined => ∃ bodyOut notesOut, Progress s bodyOut notesOut t) := by
  apply Subrelation.wf (r := InvImage (Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·))) progressRank)
  · rintro _ _ ⟨_,_,move⟩
    exact I4_combined_decreases move
  · exact InvImage.wf progressRank (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel Nat.lt_wfRel)).wf

/-- A finite execution retains its suffix; at completion the traces of
    the body and of each individual note line coincide with the input. -/
inductive Execution : Combined → List Nat → List (Nat × Nat) → Combined → Prop where
  | stop (s : Combined) : Execution s [] [] s
  | more {s t u : Combined} {bs bRest : List Nat} {ns nRest : List (Nat × Nat)} :
    Progress s bs ns t → Execution t bRest nRest u → Execution s (bs ++ bRest) (ns ++ nRest) u

theorem I5_combined_execution_exact {s t : Combined} {bs : List Nat} {ns : List (Nat × Nat)}
    (run : Execution s bs ns t) :
    bs ++ t.body.map Body.id = s.body.map Body.id ∧ ns ++ noteTrace t = noteTrace s := by
  induction run with
  | stop => exact ⟨rfl,rfl⟩
  | more move _ ih =>
    have first := I5_combined_step_exact move
    simp only [List.append_assoc,ih.1,ih.2]
    exact first

def Complete (s : Combined) := s.body = [] ∧ s.pending = []

theorem I5_completed_output {s t : Combined} {bs : List Nat} {ns : List (Nat × Nat)}
    (run : Execution s bs ns t) (done : Complete t) :
    bs = s.body.map Body.id ∧ ns = noteTrace s := by
  have eq := I5_combined_execution_exact run
  simpa [done.1,done.2,noteTrace,trace,bodyNotes] using eq

theorem I4_I5_three_page_witness :
    Execution ⟨[⟨0,[⟨10,1⟩,⟨20,5⟩,⟨30,2⟩]⟩],[],0⟩ [0]
      [(10,0),(20,0),(20,1),(20,2),(20,3),(20,4),(30,0),(30,1)] ⟨[],[],0⟩ := by
  let initial : Body := ⟨0,[⟨10,1⟩,⟨20,5⟩,⟨30,2⟩]⟩
  have line := Progress.line initial [] 3 0 0
  have first := Progress.carryPart [] ⟨20,2,3⟩ [⟨30,0,2⟩] 3 0 1 (Or.inl (by decide))
  have advance := Progress.nextColumn [] [⟨30,0,2⟩] 0
  have last := Progress.carryPart [] ⟨30,0,2⟩ [] 3 0 0 (Or.inl (by decide))
  exact Execution.more line (Execution.more first (Execution.more advance
    (Execution.more last (Execution.stop _))))

/-- advance ends the page exactly when the next column index reaches
    the column count. A zero-room carry that stays on the same page
    therefore consumes one of the remaining columns on that page. -/
def columnsBeforePage (columns index : Nat) := columns - 1 - index

theorem I4_within_page_retry (columns index : Nat) (samePage : index + 1 < columns) :
    columnsBeforePage columns index = columnsBeforePage columns (index+1) + 1 := by
  unfold columnsBeforePage
  omega

theorem I4_fresh_page_note_progress (capacity separator : Nat) (p : Part)
    (nonempty : 0 < p.lines) :
    (0 < p.lines ∧ (capacity : Int) - separator - 1 ≤ 0) ∨
      (0 < capacity - separator - 1 ∧
        ∀ rest, (carry (capacity-separator-1) p).2 = some rest → rest.lines < p.lines) := by
  by_cases room : capacity ≤ separator+1
  · exact Or.inl ⟨nonempty,by omega⟩
  · right
    have positive : 0 < capacity-separator-1 := by omega
    exact ⟨positive, fun r eq => I4_carryNote_remainder_decreases _ p r positive eq⟩

end FootnoteSplit

namespace TablePagination

/-- Projection of placeTable.rowsFrom. Capacity includes any caption
    that must accompany the last body row. A repeated header takes one
    grid line per box; its new start can be anywhere in the column. -/
structure Cursor where
  used : Nat
  segmentStart : Nat

def emitHeader (s : Cursor) (header : List Nat) : Cursor :=
  header.foldl (fun acc _ => { acc with used := acc.used + 1 }) s

theorem header_used (s : Cursor) (header : List Nat) :
    (emitHeader s header).used = s.used + header.length := by
  induction header generalizing s with
  | nil => simp [emitHeader]
  | cons x xs ih =>
      change (emitHeader {s with used := s.used+1} xs).used = _
      rw [ih]
      simp; omega

def retry (fresh : Cursor) (header : List Nat) : Cursor :=
  { emitHeader fresh header with segmentStart := fresh.used }

theorem repeated_header_guard (fresh : Cursor) (header : List Nat) :
    (retry fresh header).used = (retry fresh header).segmentStart + header.length :=
  header_used fresh header

def rank (header : List Nat) (s : Cursor) (remaining : List (List Nat)) :=
  2 * remaining.length + (if s.used = s.segmentStart + header.length then 0 else 1)

theorem retry_decreases (header : List Nat) (s fresh : Cursor) (remaining : List (List Nat))
    (mustRetry : s.used ≠ s.segmentStart + header.length) :
    rank header (retry fresh header) remaining < rank header s remaining := by
  simp [rank,mustRetry,repeated_header_guard]

theorem row_decreases (header : List Nat) (s next : Cursor) (row : List Nat) (rest : List (List Nat)) :
    rank header next rest < rank header s (row :: rest) := by
  unfold rank
  simp only [List.length_cons]
  split <;> split <;> omega

/-- The fitting test and fresh cursor depend on the concrete pagination
    state. The progress proof works for every result of those calls.
    The output here includes only original table body rows. -/
def rowsFrom (header : List Nat) (fits : Cursor → List Nat → List (List Nat) → Bool)
    (fresh : Cursor → Cursor) (s : Cursor) (remaining : List (List Nat)) : List (List Nat) :=
  match remaining with
  | [] => []
  | row :: rest =>
    if _consume : fits s row rest = true ∨ s.used = s.segmentStart + header.length then
      row :: rowsFrom header fits fresh {s with used := s.used + row.length} rest
    else
      rowsFrom header fits fresh (retry (fresh s) header) (row :: rest)
termination_by rank header s remaining
decreasing_by
  all_goals simp_wf
  · exact row_decreases _ _ _ _ _
  · exact retry_decreases _ _ _ _ (fun ready => _consume (Or.inr ready))

theorem I5_table_body_exact (header : List Nat) (fits : Cursor → List Nat → List (List Nat) → Bool)
    (fresh : Cursor → Cursor) (s : Cursor) (remaining : List (List Nat)) :
    rowsFrom header fits fresh s remaining = remaining := by
  cases remaining with
  | nil => rw [rowsFrom]
  | cons row rest =>
    rw [rowsFrom]
    split
    · rw [I5_table_body_exact header fits fresh _ rest]
    · exact I5_table_body_exact header fits fresh _ (row :: rest)
termination_by rank header s remaining
decreasing_by
  · exact row_decreases _ _ _ _ _
  · apply retry_decreases
    intro ready
    rename_i guard
    exact guard (Or.inr ready)

end TablePagination

/- The figure-only projection of a pagination state. Sending the next
   figure adds it to the FIFO waiting queue; emitting the queue's head
   appends it to the output. `placed ++ waiting ++ remaining` is the
   input order throughout those two transitions. -/
structure FigureState where
  placed : List Nat
  waiting : List Nat
  remaining : List Nat

def figureTrace (s : FigureState) : List Nat :=
  s.placed ++ s.waiting ++ s.remaining

def sendFigure (s : FigureState) : FigureState :=
  match s.remaining with
  | [] => s
  | x :: rest => { s with waiting := s.waiting ++ [x], remaining := rest }

def emitFigure (s : FigureState) : FigureState :=
  match s.waiting with
  | [] => s
  | x :: rest => { s with placed := s.placed ++ [x], waiting := rest }

theorem I5_sendFigure_preserves_trace (s : FigureState) :
    figureTrace (sendFigure s) = figureTrace s := by
  cases s with
  | mk placed waiting remaining =>
    cases remaining <;> simp [sendFigure, figureTrace, List.append_assoc]

theorem I5_emitFigure_preserves_trace (s : FigureState) :
    figureTrace (emitFigure s) = figureTrace s := by
  cases s with
  | mk placed waiting remaining =>
    cases waiting <;> simp [emitFigure, figureTrace, List.append_assoc]

def figureRank (s : FigureState) : Nat :=
  2 * s.remaining.length + s.waiting.length

theorem I4_sendFigure_decreases (s : FigureState) (nonempty : s.remaining ≠ []) :
    figureRank (sendFigure s) < figureRank s := by
  cases s with
  | mk placed waiting remaining =>
    cases remaining with
    | nil => contradiction
    | cons x rest => simp [sendFigure, figureRank, List.length_append]; omega

theorem I4_emitFigure_decreases (s : FigureState) (nonempty : s.waiting ≠ []) :
    figureRank (emitFigure s) < figureRank s := by
  cases s with
  | mk placed waiting remaining =>
    cases waiting with
    | nil => contradiction
    | cons x rest => simp [emitFigure, figureRank, List.length_append]; omega

def drainFigures (s : FigureState) : List Nat :=
  if _waiting : s.waiting ≠ [] then
    drainFigures (emitFigure s)
  else if _remaining : s.remaining ≠ [] then
    drainFigures (sendFigure s)
  else
    s.placed
termination_by figureRank s
decreasing_by
  all_goals simp_wf
  · exact I4_emitFigure_decreases _ _waiting
  · exact I4_sendFigure_decreases _ _remaining

theorem I5_drainFigures_exact (s : FigureState) :
    drainFigures s = figureTrace s := by
  by_cases waiting : s.waiting ≠ []
  · calc
      drainFigures s = drainFigures (emitFigure s) := by
        rw [drainFigures]
        simp [waiting]
      _ = figureTrace (emitFigure s) := I5_drainFigures_exact (emitFigure s)
      _ = figureTrace s := I5_emitFigure_preserves_trace s
  · by_cases remaining : s.remaining ≠ []
    · calc
        drainFigures s = drainFigures (sendFigure s) := by
          rw [drainFigures]
          simp [waiting, remaining]
        _ = figureTrace (sendFigure s) := I5_drainFigures_exact (sendFigure s)
        _ = figureTrace s := I5_sendFigure_preserves_trace s
    · have waitingEmpty : s.waiting = [] := by
        cases h : s.waiting with
        | nil => rfl
        | cons x xs => exact False.elim (waiting (by simp [h]))
      have remainingEmpty : s.remaining = [] := by
        cases h : s.remaining with
        | nil => rfl
        | cons x xs => exact False.elim (remaining (by simp [h]))
      simp [drainFigures, waitingEmpty, remainingEmpty, figureTrace]
termination_by figureRank s
decreasing_by
  · exact I4_emitFigure_decreases _ waiting
  · exact I4_sendFigure_decreases _ remaining


/- In the ADR 0206 domain, deleting the single optional figure leaves an
   ordered list of text items. Texts are identified by their zero-based
   ranks. A figure at rank f precedes text t exactly when f ≤ t. Size zero
   encodes absence, since every actual figure has positive size. -/
structure RectoInput where
  cap : Nat
  used : Nat
  texts : Nat
  figureRank : Nat
  figureSize : Nat
  heading : Nat → Prop
  line : Nat → Prop
  recto : Nat → Prop
  paragraph : List ParagraphBoundary
  headingsNotLines : ∀ t, heading t → ¬ line t
  rectosHeadings : ∀ t, recto t → heading t
  paragraphFirst : ∀ p ∈ paragraph, line p.firstPos
  paragraphOrder : ∀ p ∈ paragraph, p.firstPos ≤ p.beforeLastPos
  figureFits : figureSize ≤ cap
  usedFits : used ≤ cap

namespace RectoInput
def kept (d : RectoInput) (b : Nat) : Prop :=
  0 < d.figureSize ∧ d.figureRank ≤ b ∧ d.used + d.figureRank + d.figureSize ≤ d.cap

def starts (d : RectoInput) (b t : Nat) : Prop :=
  d.used = 0 ∧ t = 0 ∧ (d.kept b → t < d.figureRank)

def afterHeads (d : RectoInput) (b t : Nat) : Prop :=
  d.used = 0 ∧ (∀ u, u < t → u < b → d.heading u) ∧
    (d.kept b → t < d.figureRank)

def base (d : RectoInput) (b : Nat) : Prop :=
  b ≤ d.texts ∧ d.used + b ≤ d.cap ∧
  (d.kept b → d.used + b + d.figureSize ≤ d.cap) ∧
  (d.kept b → d.figureRank ≤ b) ∧
  (d.used = 0 → 0 < d.figureSize → d.figureRank = 0 → d.kept b) ∧
  (d.used = 0 → 0 < d.texts → (d.figureSize = 0 ∨ 0 < d.figureRank) → 0 < b)

def lineAfter (d : RectoInput) (b : Nat) : Prop :=
  d.used = 0 → 0 < b → ¬ d.kept b →
    (∀ t, t < b → d.heading t) → b < d.texts → ¬ d.line b

def orphanH (d : RectoInput) (b : Nat) : Prop :=
  ∀ p ∈ d.paragraph, 2 ≤ p.lineCount → p.firstPos < b → b ≤ p.secondPos →
    d.afterHeads b p.firstPos

def widowH (d : RectoInput) (b : Nat) : Prop :=
  ∀ p ∈ d.paragraph, 2 ≤ p.lineCount → p.beforeLastPos < b → b ≤ p.lastPos →
    d.afterHeads b p.firstPos

/- These sufficient conditions make both heading-run variants hold,
   independently of the length of the heading run and the kept lines. -/
def feasible (d : RectoInput) (b : Nat) : Prop :=
  d.base b ∧ d.lineAfter b ∧ d.orphanH b ∧ d.widowH b ∧
  (∀ t, t < b → d.heading t → d.starts b t)

private theorem feasible_of_prefix (d : RectoInput) (b : Nat)
    (base : d.base b) (after : d.lineAfter b)
    (paragraphStart : ∀ t, t < b → d.line t → d.afterHeads b t)
    (heads : ∀ t, t < b → d.heading t → d.starts b t) : d.feasible b := by
  refine ⟨base, after, ?_, ?_, heads⟩
  · intro p member _ here _
    exact paragraphStart _ here (d.paragraphFirst p member)
  · intro p member _ here _
    exact paragraphStart _ (Nat.lt_of_le_of_lt (d.paragraphOrder p member) here)
      (d.paragraphFirst p member)

theorem feasible_exists (d : RectoInput) (twoFit : 2 ≤ d.cap) :
    ∃ b, d.feasible b := by
  by_cases zeroBreak : d.used ≠ 0 ∨ d.texts = 0 ∨
      (0 < d.figureSize ∧ d.figureRank = 0)
  · refine ⟨0, feasible_of_prefix d 0 ?_ ?_ ?_ ?_⟩
    · refine ⟨by omega, by simpa using d.usedFits, ?_, fun k => k.2.1, ?_, ?_⟩
      · intro k
        have room := k.2.2
        omega
      · intro empty pos rank
        exact ⟨pos, by omega, by simpa [empty, rank] using d.figureFits⟩
      · intro empty nonempty first
        omega
    · intro _ positive
      omega
    · intro t here
      omega
    · intro t here
      omega
  · have empty : d.used = 0 := by apply Classical.byContradiction; intro h; exact zeroBreak (Or.inl h)
    have nonempty : 0 < d.texts := by
      apply Classical.byContradiction
      intro h
      exact zeroBreak (Or.inr (Or.inl (by omega)))
    have firstText : d.figureSize = 0 ∨ 0 < d.figureRank := by
      apply Classical.byContradiction
      intro h
      exact zeroBreak (Or.inr (Or.inr ⟨by omega, by omega⟩))
    have startsZero : ∀ b, d.starts b 0 := by
      intro b
      refine ⟨empty, rfl, ?_⟩
      intro k
      have positive := k.1
      omega
    by_cases two : 1 < d.texts ∧ d.heading 0 ∧ d.line 1 ∧ ¬ d.kept 1
    · obtain ⟨texts, heading, line, sent⟩ := two
      have keptAfter : d.kept 2 → d.figureRank = 2 := by
        intro k
        apply Classical.byContradiction
        intro h
        exact sent ⟨k.1, by have := k.2.1; omega, k.2.2⟩
      refine ⟨2, feasible_of_prefix d 2 ?_ ?_ ?_ ?_⟩
      · refine ⟨by omega, by omega, ?_, fun k => k.2.1, ?_, by intros; decide⟩
        · intro k
          simpa [keptAfter k] using k.2.2
        · intro _ pos rank
          omega
      · intro _ _ _ allHeadings
        exact (d.headingsNotLines 1 (allHeadings 1 (by decide)) line).elim
      · intro t here _
        refine ⟨empty, ?_, ?_⟩
        · intro u before _
          have : u = 0 := by omega
          simpa [this] using heading
        · intro k
          rw [keptAfter k]
          omega
      · intro t here tHead
        have tZero : t = 0 := by
          apply Classical.byContradiction
          intro h
          have : t = 1 := by omega
          exact d.headingsNotLines 1 (this ▸ tHead) line
        exact tZero ▸ startsZero 2
    · refine ⟨1, feasible_of_prefix d 1 ?_ ?_ ?_ ?_⟩
      · refine ⟨by omega, by omega, ?_, fun k => k.2.1, ?_, by intros; decide⟩
        · intro k
          have pos := k.1
          have bound := k.2.1
          have rank : d.figureRank = 1 := by omega
          simpa [rank] using k.2.2
        · intro _ pos rank
          omega
      · intro _ _ sent heads more line
        exact two ⟨more, heads 0 (by decide), line, sent⟩
      · intro t here _
        have eq : t = 0 := by omega
        subst t
        exact ⟨empty, by intros; omega, (startsZero 1).2.2⟩
      · intro t here _
        have eq : t = 0 := by omega
        exact eq ▸ startsZero 1
/- The explicit keep flag ranges over both choices of the Alloy placement.
   A figure occupies slot 2*f just before text f at slot 2*f+1.
   Thus intervals in headingRunKeep include the intervening figure. -/
def itemAt (d : RectoInput) (pos : Nat) : Prop :=
  (∃ t, t < d.texts ∧ pos = 2*t+1) ∨
    (0 < d.figureSize ∧ pos = 2*d.figureRank)

def basePlacement (d : RectoInput) (b : Nat) (keep : Bool) : Prop :=
  b ≤ d.texts ∧ (keep = true ↔ d.kept b) ∧
    d.used + b + (if keep then d.figureSize else 0) ≤ d.cap ∧
    (keep = true → d.figureRank ≤ b) ∧
    (d.used = 0 → 0 < d.figureSize → d.figureRank = 0 → keep = true) ∧
    (d.used = 0 → 0 < d.texts → (d.figureSize = 0 ∨ 0 < d.figureRank) → 0 < b)

def headingRule (d : RectoInput) (b : Nat) (heading : Nat → Prop)
    (linesKept : Nat → Prop) : Prop :=
  headingRunKeep d.itemAt (fun p => ∃ t, t < d.texts ∧ p = 2*t+1)
    (fun p => ∃ t, t < d.texts ∧ p = 2*t+1 ∧ heading t)
    (fun p => p / 2 < b) (fun p => d.starts b (p / 2))
    (fun p => d.line (p / 2)) linesKept

theorem placement_of_feasible (d : RectoInput) (b : Nat) (ok : d.feasible b) :
    ∃ keep, d.basePlacement b keep := by
  obtain ⟨bounds, room, fits, order, firstFigure, firstText⟩ := ok.1
  by_cases k : d.kept b
  · exact ⟨true, bounds, by simp [k], by simpa using fits k,
      fun _ => order k, by intros; rfl, firstText⟩
  · exact ⟨false, bounds, by simp [k], by simpa using room,
      by simp, fun empty pos rank => (k (firstFigure empty pos rank)).elim,
      firstText⟩

theorem headings_of_feasible (d : RectoInput) (b : Nat) (ok : d.feasible b)
    (heading linesKept : Nat → Prop) (subset : ∀ h, heading h → d.heading h) :
    d.headingRule b heading linesKept := by
  intro p eligible here inside
  obtain ⟨t, _, position, head⟩ := eligible
  subst p
  have rank : (2*t+1) / 2 = t := by omega
  change (2*t+1) / 2 < b at here
  change ¬ d.starts b ((2*t+1) / 2) at inside
  rw [rank] at here inside
  exact (inside (ok.2.2.2.2 t here (subset t head))).elim

end RectoInput

/- Alloy's "no placement" has no witness: for each input there is a
   placement satisfying all the predicates. keptLines may be any predicate,
   which includes the paragraph-dependent keptLines of ADR 0021. -/
theorem rectoKept (d : RectoInput) (twoFit : 2 ≤ d.cap)
    (keptLines : Nat → Prop) :
    ∃ b keep, d.basePlacement b keep ∧ d.orphanH b ∧ d.widowH b ∧
      d.headingRule b d.heading keptLines ∧ d.lineAfter b ∧
      (∀ t, t < b → d.recto t → d.starts b t) := by
  obtain ⟨b, ok⟩ := d.feasible_exists twoFit
  obtain ⟨keep, base⟩ := d.placement_of_feasible b ok
  exact ⟨b, keep, base, ok.2.2.1, ok.2.2.2.1,
    d.headings_of_feasible b ok d.heading keptLines (fun _ h => h),
    ok.2.1, fun t here r => ok.2.2.2.2 t here (d.rectosHeadings t r)⟩

theorem rectoEnds (d : RectoInput) (twoFit : 2 ≤ d.cap)
    (keptLines : Nat → Prop) :
    ∃ b keep, d.basePlacement b keep ∧ d.orphanH b ∧ d.widowH b ∧
      d.headingRule b (fun t => d.heading t ∧ ¬ d.recto t) keptLines ∧
      d.lineAfter b ∧ (∀ t, t < b → d.recto t → d.starts b t) := by
  obtain ⟨b, ok⟩ := d.feasible_exists twoFit
  obtain ⟨keep, base⟩ := d.placement_of_feasible b ok
  exact ⟨b, keep, base, ok.2.2.1, ok.2.2.2.1,
    d.headings_of_feasible b ok _ keptLines (fun _ h => h.1),
    ok.2.1, fun t here r => ok.2.2.2.2 t here (d.rectosHeadings t r)⟩

theorem relaxedAfterHeadings (d : RectoInput) (twoFit : 2 ≤ d.cap)
    (keptLines : Nat → Prop) :
    ∃ b keep, d.basePlacement b keep ∧ d.orphanH b ∧ d.widowH b ∧
      d.headingRule b d.heading keptLines ∧ d.lineAfter b := by
  obtain ⟨b, keep, base, orphan, widow, heading, after, _⟩ := rectoKept d twoFit keptLines
  exact ⟨b, keep, base, orphan, widow, heading, after⟩

end GolemPagination
