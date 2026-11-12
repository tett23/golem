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
    (secondIn : .figure secondPos ∈ items)
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
        exact ⟨.figure secondPos, secondIn,
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
              firstIn secondIn onlyTwo).symm
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
