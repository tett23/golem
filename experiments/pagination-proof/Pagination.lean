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

end GolemPagination
