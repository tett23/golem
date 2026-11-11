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

end GolemPagination
