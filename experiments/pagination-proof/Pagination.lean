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

example : fitCaptionedFigure 2 2 15 240 3 1 = none := by rfl
example : fitCaptionedFigure 10 1 15 240 3 1 = some (45, 135) := by rfl

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
def nextAfterWaiting (waiting : Nat → Bool) : List Nat → Option Nat
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
    (waiting : Nat → Bool) (items : List Nat) :
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
def blankPlaced (waiting : Nat → Bool) (items : List Nat)
    (inColumn : Nat → Bool) (atTop : Bool) : Bool :=
  match nextAfterWaiting waiting items with
  | none => false
  | some i => inColumn i && !atTop

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

/- A need of two lines before a one-line figure in a column with one line
   left conflicts with the older rule that keeps every figure that fits. -/
theorem needFigure :
    (∃ kept : Bool, kept = decide (4 + 1 ≤ 5)) ∧
    (∃ kept : Bool, kept = true → 4 + 2 ≤ 5) ∧
    (∀ kept : Bool, ¬ (kept = decide (4 + 1 ≤ 5) ∧
                      (kept = true → 4 + 2 ≤ 5))) := by
  refine ⟨⟨true, by decide⟩, ⟨false, by decide⟩, ?_⟩
  intro kept
  cases kept <;> decide

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

/- A one-line body, one-line footnote separator, and one-line note cannot
   all fit in a column of capacity 1 or 2. Golem's current `carryNote`
   retries without consuming the note in those columns (I4 red test). -/
theorem I4_footnote_capacity_conflict (capacity : Nat) (small : capacity ≤ 2) :
    ¬ (1 + 1 + 1 ≤ capacity) := by
  omega

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

end GolemPagination
