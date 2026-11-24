/-
Root ADR 0352: the separators of root ADR 0398 on the flows of Whole.lean.

This file models four functions of
modules/golem-typeset/src/Golem/Typeset/Flow.hs.  `spaceSeparators`
(the local function of `blocks`) turns the units of a document into the
units the flow is made of: it puts a keep-with-next of one line after a
visible separator and replaces the blank lines at its boundary by one
space.  `holdSeparatorNeeds`, after it, puts a need-lines before the
first separator of a hold with a need-lines in it, and `unmetWarnings`
reports nothing of that need-lines.  `separatorHoldErrors` reads the
pages and returns G07134 for each chain of visible separators whose lines
and the first line of the block after them are not in one column.

`I3_separator_hold_together` follows the steps of `paginate` from a
state with nothing waiting through a separator, its keep-with-next and
the paragraph after it, and shows the empty-column rule of root ADR 0398
on them: when the separator's line and the first part of the paragraph
fit a column of the whole capacity, the two lines end in one column.

The units other than the separators, the blank lines and the breaks are
left abstract: each carries its flows, whether it starts a block, passes
or resets a chain of separators, and the id of its first line.  The
theorems hold for every choice of them.  README.md lists the
correspondence with file:line.
-/
import Whole
import WholeNotes

namespace WholePagination
namespace Separator

theorem mem_app {α : Type} {a : α} {l r : List α} : a ∈ l ++ r ↔ a ∈ l ∨ a ∈ r := by
  induction l with
  | nil => simp
  | cons x xs ih =>
    rw [List.cons_append, List.mem_cons, List.mem_cons, ih]
    constructor
    · rintro (e | m | m)
      · exact Or.inl (Or.inl e)
      · exact Or.inl (Or.inr m)
      · exact Or.inr m
    · rintro ((e | m) | m)
      · exact Or.inl e
      · exact Or.inr (Or.inl m)
      · exact Or.inr (Or.inr m)

theorem mem_one {α : Type} {a b : α} (m : a ∈ [b]) : a = b := by
  rcases List.mem_cons.mp m with e | m
  · exact e
  · exact absurd m (List.not_mem_nil _)

theorem mem_filterMap' {α β : Type} (f : α → Option β) (b : β) (l : List α) :
    b ∈ l.filterMap f ↔ ∃ a, a ∈ l ∧ f a = some b := by
  induction l with
  | nil => simp [List.filterMap]
  | cons x xs ih =>
    simp only [List.filterMap]
    cases h : f x with
    | none =>
      simp only [ih]
      constructor
      · rintro ⟨a, m, e⟩; exact ⟨a, List.mem_cons_of_mem _ m, e⟩
      · rintro ⟨a, m, e⟩
        rcases List.mem_cons.mp m with r | m
        · subst r; rw [h] at e; cases e
        · exact ⟨a, m, e⟩
    | some c =>
      rw [List.mem_cons, ih]
      constructor
      · rintro (e | ⟨a, m, e⟩)
        · subst e; exact ⟨x, List.mem_cons_self _ _, h⟩
        · exact ⟨a, List.mem_cons_of_mem _ m, e⟩
      · rintro ⟨a, m, e⟩
        rcases List.mem_cons.mp m with r | m
        · subst r; rw [h] at e; cases e; exact Or.inl rfl
        · exact Or.inr ⟨a, m, e⟩

/-- How `separatorHoldErrors` reads a unit that is not a separator, a
    blank line or a break: `USection` and `UColumns` reset a chain,
    `UGap`, `UKeepNext` and `UPageControl` pass it, and any other unit
    is a block, the chain ending at its first line. -/
inductive Role where
  | block | pass | reset
  deriving DecidableEq, Repr

/-- The units of golem-typeset (`UnitKind` of Flow.hs) the separators
    meet.  A visible separator (`USeparator`, its `text` or `rule`) is
    one line with its grid lines before and after; a separator of kind
    `blank` is resolved to blank lines before the units are made. -/
inductive Unit where
  | separator (before after : Nat) (kp : Keep) (line : Line)
  /-- `UBlank`: `@blank-line` and the separators of kind `blank`. -/
  | blank (n : Nat)
  /-- `UBreak`. -/
  | brk (k : BreakKind)
  /-- `UGap`, by its grid lines. -/
  | gap (n : Nat)
  /-- `UKeepNext`, by its lines and the id of its span. -/
  | keepNext (n sp : Nat)
  /-- Any other unit: its role, its flows and the id of its first line
      (`bUnitFirsts`). -/
  | other (role : Role) (flows : List Flow) (first : Option Nat)

/-- The flows of a unit (`numberOther` and `numberText` of Flow.hs): a
    visible separator is a paragraph of its one line, a gap of `n` grid
    lines is `FSpace` of `n` lines, as `paginateBuilt` divides it by the
    line pitch. -/
def Unit.flows : Unit → List Flow
  | .separator _ _ kp l => [.paragraph kp [l]]
  | .blank n => [.blank n]
  | .brk k => [.brk k]
  | .gap n => [.space n]
  | .keepNext n sp => [.keepNext n sp]
  | .other _ fs _ => fs

def allFlows : List Unit → List Flow
  | [] => []
  | u :: r => u.flows ++ allFlows r

/-- `beforeOf` of `spaceSeparators`. -/
def beforeOf : Unit → Nat
  | .separator b _ _ _ => b
  | _ => 0

/-- `afterOf` of `spaceSeparators`. -/
def afterOf : Unit → Option Nat
  | .separator _ a _ _ => some a
  | _ => none

/-- The span and the lines after a visible separator, as `spaceSeparators`
    carries them to the unit after it (`(uSpan u,) <$> afterOf kind`);
    the span of a separator is the id of its line. -/
def holdOf : Unit → Option (Nat × Nat)
  | .separator _ a _ l => some (l.id, a)
  | _ => none

/-- The keep-with-next `spaceSeparators` puts after a visible separator:
    one line, of the span of the separator (root ADR 0398 I7). -/
def keepOf : Option (Nat × Nat) → List Unit
  | some (sp, _) => [.keepNext 1 sp]
  | none => []

def blankLines : List Unit → Nat
  | [] => 0
  | .blank k :: r => k + blankLines r
  | _ :: r => blankLines r

/-- The gap of `spaceSeparators` before a unit that is not a blank line
    or a break, after the blank lines `pending`, the visible separator
    before it leaving `previous` grid lines after it. -/
def gapOf (previous : Option Nat) (pending : List Unit) (u : Unit) : List Unit :=
  let spacing := max (max (blankLines pending) (beforeOf u)) (previous.getD 0)
  if previous.isSome || 0 < beforeOf u then
    if 0 < spacing then [if previous.isSome then .gap spacing else .blank spacing] else []
  else pending

/-- `go` of `spaceSeparators` (Flow.hs). -/
def space : Option (Nat × Nat) → List Unit → List Unit → List Unit
  | previous, pending, [] => if previous.isSome then [] else pending
  | previous, pending, .blank k :: rest => space previous (pending ++ [.blank k]) rest
  | _, pending, .brk k :: rest => pending ++ .brk k :: space none [] rest
  | previous, pending, u :: rest =>
    keepOf previous ++ gapOf (previous.map Prod.snd) pending u ++ u :: space (holdOf u) [] rest

/-! ## The need-lines asked for before a separator hold -/

/-- `inHold` of `holdSeparatorNeeds`: the units a hold goes on through,
    `USeparator`, `UGap`, `UBlank`, `UKeepNext` and `UPageControl`. -/
def inHold : Unit → Bool
  | .separator _ _ _ _ | .gap _ | .blank _ | .keepNext _ _ | .other .pass _ _ => true
  | _ => false

/-- `holdLines` of `holdSeparatorNeeds`: a visible separator is one line,
    blank lines and a gap are their lines. -/
def holdLines : Unit → Nat
  | .separator _ _ _ _ => 1
  | .blank k | .gap k => k
  | _ => 0

/-- The lines a `UPageControl (NeedLines k)` asks for. -/
def needOf : Unit → Option Nat
  | .other .pass [.needLines k] _ => some k
  | _ => none

/-- `chain` of `holdSeparatorNeeds`: the units of the hold after its
    first separator (`span inHold`). -/
def takeHold : List Unit → List Unit
  | [] => []
  | u :: r => if inHold u then u :: takeHold r else []

/-- `wanted` of `holdSeparatorNeeds`: `at + k` for each need-lines of `k`
    lines, `at` the lines of the hold before it and the blank lines before
    the hold. -/
def wants : Nat → List Unit → List Nat
  | _, [] => []
  | pos, u :: r => ((needOf u).map (pos + ·)).toList ++ wants (pos + holdLines u) r

/-- `hoisted` of `holdSeparatorNeeds`: a need-lines of the most lines
    wanted, at most the lines of a column, or nothing when no need-lines
    is in the hold. -/
def hoisted (capacity : Nat) (blanks : Nat) (hold : List Unit) : List Unit :=
  match wants blanks hold with
  | [] => []
  | w :: ws => [.other .pass [.needLines (min capacity (ws.foldl max w))] none]

/-- `holdSeparatorNeeds` (Flow.hs), on the units after `spaceSeparators`.
    `blanks` counts the blank lines just before the unit, `held` says the
    unit is in a hold.  A unit that goes on a hold is put as it is; the
    first separator of a hold gets `hoisted` before it; any other unit
    ends the hold. -/
def holdNeeds (capacity : Nat) : Nat → Bool → List Unit → List Unit
  | _, _, [] => []
  | blanks, held, u :: rest =>
    if held && inHold u then u :: holdNeeds capacity 0 true rest
    else match u with
      | .separator b a kp l =>
        hoisted capacity blanks (.separator b a kp l :: takeHold rest) ++ .separator b a kp l :: holdNeeds capacity 0 true rest
      | .blank k => .blank k :: holdNeeds capacity (blanks + k) false rest
      | u => u :: holdNeeds capacity 0 false rest

/-- The units of `blocks`, after `spaceSeparators` and
    `holdSeparatorNeeds`, in a column of `capacity` lines. -/
def separatorUnits (capacity : Nat) (us : List Unit) : List Unit := holdNeeds capacity 0 false (space none [] us)

/-- The flows made of the units, as the pagination receives them. -/
def separatorFlows (capacity : Nat) (us : List Unit) : List Flow := allFlows (separatorUnits capacity us)

/-! ## The flows made carry the text and the figures of the units -/

/-- The lines and headings of the units, in the order written: the line
    of each visible separator and the text of the flows of the others. -/
def unitsText (us : List Unit) : List Slot := sourceText (allFlows us)

/-- The flows of the units other than the separators, the blank lines,
    the breaks, the gaps and the keep-with-nexts. -/
def otherFlows : List Unit → List Flow
  | [] => []
  | .other _ fs _ :: r => fs ++ otherFlows r
  | .separator _ _ _ _ :: r | .blank _ :: r | .brk _ :: r | .gap _ :: r | .keepNext _ _ :: r => otherFlows r

theorem allFlows_append (a b : List Unit) : allFlows (a ++ b) = allFlows a ++ allFlows b := by
  induction a with
  | nil => rfl
  | cons x xs ih =>
    show x.flows ++ allFlows (xs ++ b) = (x.flows ++ allFlows xs) ++ allFlows b
    rw [ih, List.append_assoc]

theorem otherFlows_append (a b : List Unit) : otherFlows (a ++ b) = otherFlows a ++ otherFlows b := by
  induction a with
  | nil => rfl
  | cons x xs ih => cases x <;> simp [otherFlows, ih, List.append_assoc]

/-- A list of blank lines only. -/
def Blanks (us : List Unit) : Prop := ∀ u ∈ us, ∃ k, u = .blank k

theorem Blanks.nil : Blanks [] := fun _ m => absurd m (List.not_mem_nil _)

theorem Blanks.snoc {us : List Unit} (h : Blanks us) (k : Nat) : Blanks (us ++ [.blank k]) := by
  intro u m
  rcases mem_app.mp m with m | m
  · exact h u m
  · exact ⟨k, mem_one m⟩

theorem blanks_text {us : List Unit} (h : Blanks us) : sourceText (allFlows us) = [] := by
  induction us with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨k, e⟩ := h x (List.mem_cons_self _ _)
    subst e
    simp only [allFlows, Unit.flows, List.singleton_append, sourceText, flowText, List.nil_append]
    exact ih (fun u m => h u (List.mem_cons_of_mem _ m))

theorem blanks_other {us : List Unit} (h : Blanks us) : otherFlows us = [] := by
  induction us with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨k, e⟩ := h x (List.mem_cons_self _ _)
    subst e
    exact ih (fun u m => h u (List.mem_cons_of_mem _ m))

/-- `.gap` units are in the output only as gaps; they carry no text. -/
def Quiet (us : List Unit) : Prop := ∀ u ∈ us, (∃ k, u = .blank k) ∨ (∃ k, u = .gap k) ∨ (∃ k s, u = .keepNext k s)

theorem quiet_text {us : List Unit} (h : Quiet us) : sourceText (allFlows us) = [] := by
  induction us with
  | nil => rfl
  | cons x xs ih =>
    have t := ih (fun u m => h u (List.mem_cons_of_mem _ m))
    rcases h x (List.mem_cons_self _ _) with ⟨k, e⟩ | ⟨k, e⟩ | ⟨k, s, e⟩ <;> subst e <;>
      simp only [allFlows, Unit.flows, List.singleton_append, sourceText, flowText, List.nil_append, t]

theorem quiet_other {us : List Unit} (h : Quiet us) : otherFlows us = [] := by
  induction us with
  | nil => rfl
  | cons x xs ih =>
    have t := ih (fun u m => h u (List.mem_cons_of_mem _ m))
    rcases h x (List.mem_cons_self _ _) with ⟨k, e⟩ | ⟨k, e⟩ | ⟨k, s, e⟩ <;> subst e <;> exact t

theorem gapOf_quiet (previous : Option Nat) {pending : List Unit} (h : Blanks pending) (u : Unit) :
    Quiet (gapOf previous pending u) := by
  intro v m
  unfold gapOf at m
  cases previous with
  | none =>
    simp only [Option.isSome, Bool.false_or, Option.getD] at m
    split at m
    · split at m
      · exact Or.inl ⟨_, mem_one m⟩
      · exact absurd m (List.not_mem_nil _)
    · exact Or.inl (h v m)
  | some a =>
    simp only [Option.isSome, Bool.true_or, Option.getD, ite_true] at m
    split at m
    · exact Or.inr (Or.inl ⟨_, mem_one m⟩)
    · exact absurd m (List.not_mem_nil _)

theorem blanks_quiet {us : List Unit} (h : Blanks us) : Quiet us := fun u m => Or.inl (h u m)

theorem keep_quiet (p : Option (Nat × Nat)) : Quiet (keepOf p) := by
  intro u m
  match p, m with
  | some (sp, _), m => exact Or.inr (Or.inr ⟨1, sp, mem_one m⟩)

theorem space_text (previous : Option (Nat × Nat)) (pending : List Unit) (h : Blanks pending) (us : List Unit) :
    sourceText (allFlows (space previous pending us)) = unitsText us := by
  induction us generalizing previous pending with
  | nil =>
    simp only [space, unitsText, allFlows, sourceText]
    split
    · rfl
    · exact blanks_text h
  | cons u rest ih =>
    cases u with
    | blank k =>
      simp only [space]
      rw [ih previous _ (h.snoc k)]
      simp only [unitsText, allFlows, Unit.flows, List.singleton_append, sourceText, flowText, List.nil_append]
    | brk k =>
      simp only [space, allFlows_append, sourceText_append, blanks_text h, allFlows, Unit.flows,
        List.singleton_append, sourceText, flowText, List.nil_append]
      rw [ih none [] Blanks.nil]
      simp only [unitsText, allFlows, Unit.flows, List.singleton_append, sourceText, flowText, List.nil_append]
    | separator b a kp l =>
      simp only [space, allFlows_append, sourceText_append, quiet_text (keep_quiet _),
        quiet_text (gapOf_quiet _ h _), List.nil_append]
      simp only [allFlows, sourceText_append]
      rw [ih _ [] Blanks.nil]
      simp only [unitsText, allFlows, sourceText_append]
    | gap n =>
      simp only [space, allFlows_append, sourceText_append, quiet_text (keep_quiet _),
        quiet_text (gapOf_quiet _ h _), List.nil_append]
      simp only [allFlows, sourceText_append]
      rw [ih _ [] Blanks.nil]
      simp only [unitsText, allFlows, sourceText_append]
    | keepNext n =>
      simp only [space, allFlows_append, sourceText_append, quiet_text (keep_quiet _),
        quiet_text (gapOf_quiet _ h _), List.nil_append]
      simp only [allFlows, sourceText_append]
      rw [ih _ [] Blanks.nil]
      simp only [unitsText, allFlows, sourceText_append]
    | other r fs f =>
      simp only [space, allFlows_append, sourceText_append, quiet_text (keep_quiet _),
        quiet_text (gapOf_quiet _ h _), List.nil_append]
      simp only [allFlows, sourceText_append]
      rw [ih _ [] Blanks.nil]
      simp only [unitsText, allFlows, sourceText_append]

theorem space_other (previous : Option (Nat × Nat)) (pending : List Unit) (h : Blanks pending) (us : List Unit) :
    otherFlows (space previous pending us) = otherFlows us := by
  induction us generalizing previous pending with
  | nil =>
    simp only [space]
    split
    · rfl
    · exact blanks_other h
  | cons u rest ih =>
    cases u with
    | blank k => simp only [space]; rw [ih previous _ (h.snoc k)]; rfl
    | brk k =>
      simp only [space, otherFlows_append, blanks_other h, List.nil_append]
      rw [otherFlows, ih none [] Blanks.nil]; rfl
    | other r fs f =>
      simp only [space, otherFlows_append, quiet_other (keep_quiet _),
        quiet_other (gapOf_quiet _ h _), List.nil_append]
      rw [otherFlows, ih _ [] Blanks.nil]; rfl
    | separator b a kp l =>
      simp only [space, otherFlows_append, quiet_other (keep_quiet _),
        quiet_other (gapOf_quiet _ h _), List.nil_append]
      rw [otherFlows, ih _ [] Blanks.nil]; rfl
    | gap n =>
      simp only [space, otherFlows_append, quiet_other (keep_quiet _),
        quiet_other (gapOf_quiet _ h _), List.nil_append]
      rw [otherFlows, ih _ [] Blanks.nil]; rfl
    | keepNext n =>
      simp only [space, otherFlows_append, quiet_other (keep_quiet _),
        quiet_other (gapOf_quiet _ h _), List.nil_append]
      rw [otherFlows, ih _ [] Blanks.nil]; rfl

/-! ## The flows put in between are plain -/

/-- The flows a unit other than `other` is made of. -/
def plainFlow : Flow → Bool
  | .paragraph _ _ | .blank _ | .space _ | .keepNext _ _ | .brk _ | .needLines _ => true
  | _ => false

/-- `ys` is `xs` with plain flows put in between. -/
inductive Ins : List Flow → List Flow → Prop
  | nil : Ins [] []
  | keep (f : Flow) {xs ys : List Flow} : Ins xs ys → Ins (f :: xs) (f :: ys)
  | plain (p : Flow) {xs ys : List Flow} : plainFlow p = true → Ins xs ys → Ins xs (p :: ys)

theorem Ins.refl : ∀ xs : List Flow, Ins xs xs
  | [] => .nil
  | f :: r => .keep f (Ins.refl r)

theorem Ins.append {a b c d : List Flow} (h : Ins a b) (k : Ins c d) : Ins (a ++ c) (b ++ d) := by
  induction h with
  | nil => exact k
  | keep f _ ih => exact .keep f ih
  | plain p hp _ ih => exact .plain p hp ih

theorem allFlows_ins (us : List Unit) : Ins (otherFlows us) (allFlows us) := by
  induction us with
  | nil => exact .nil
  | cons u r ih =>
    cases u with
    | other _ fs _ => exact (Ins.refl fs).append ih
    | separator _ _ kp l => exact .plain _ rfl ih
    | blank k => exact .plain _ rfl ih
    | brk k => exact .plain _ rfl ih
    | gap n => exact .plain _ rfl ih
    | keepNext n => exact .plain _ rfl ih

theorem Ins.trans {xs ys zs : List Flow} (h : Ins xs ys) (k : Ins ys zs) : Ins xs zs := by
  induction k generalizing xs with
  | nil => exact h
  | keep f _ ih =>
    cases h with
    | keep _ h' => exact .keep f (ih h')
    | plain _ hp h' => exact .plain _ hp (ih h')
  | plain p hp _ ih => exact .plain p hp (ih h)

/-- `hoisted` is nothing or one need-lines. -/
theorem hoisted_flows (capacity blanks : Nat) (hold : List Unit) :
    allFlows (hoisted capacity blanks hold) = [] ∨ ∃ n, allFlows (hoisted capacity blanks hold) = [.needLines n] := by
  unfold hoisted
  split
  · exact Or.inl rfl
  · exact Or.inr ⟨_, rfl⟩

theorem hoisted_text (capacity blanks : Nat) (hold : List Unit) (r : List Flow) :
    sourceText (allFlows (hoisted capacity blanks hold) ++ r) = sourceText r := by
  rcases hoisted_flows capacity blanks hold with e | ⟨n, e⟩ <;> rw [e]
  · rfl
  · simp only [List.singleton_append, sourceText, flowText, List.nil_append]

theorem hoisted_ins (capacity blanks : Nat) (hold : List Unit) {xs ys : List Flow} (h : Ins xs ys) :
    Ins xs (allFlows (hoisted capacity blanks hold) ++ ys) := by
  rcases hoisted_flows capacity blanks hold with e | ⟨n, e⟩ <;> rw [e]
  · exact h
  · exact .plain _ rfl h

theorem foldl_max_ge (acc : Nat) (l : List Nat) : acc ≤ l.foldl max acc ∧ ∀ x ∈ l, x ≤ l.foldl max acc := by
  induction l generalizing acc with
  | nil => exact ⟨Nat.le_refl _, fun x m => absurd m (List.not_mem_nil _)⟩
  | cons y ys ih =>
    obtain ⟨h1, h2⟩ := ih (max acc y)
    refine ⟨Nat.le_trans (Nat.le_max_left _ _) h1, fun x m => ?_⟩
    rcases List.mem_cons.mp m with e | m
    · subst e; exact Nat.le_trans (Nat.le_max_right _ _) h1
    · exact h2 x m

/-- The need-lines asked for before a hold is there exactly when the hold
    has a need-lines; it asks for no more than a column and, for each
    need-lines of the hold, for its lines and the lines before it in the
    hold, or a whole column when they are more. -/
theorem hoisted_need (capacity blanks : Nat) (hold : List Unit) :
    (wants blanks hold = [] ∧ hoisted capacity blanks hold = []) ∨
      ∃ n, hoisted capacity blanks hold = [.other .pass [.needLines n] none] ∧ n ≤ capacity ∧
        ∀ x ∈ wants blanks hold, min capacity x ≤ n := by
  unfold hoisted
  split
  · rename_i e; exact Or.inl ⟨e, rfl⟩
  · rename_i w ws e
    refine Or.inr ⟨_, rfl, Nat.min_le_left _ _, fun x m => ?_⟩
    rw [e] at m
    obtain ⟨h1, h2⟩ := foldl_max_ge w ws
    have hx : x ≤ ws.foldl max w := by
      rcases List.mem_cons.mp m with e | m
      · subst e; exact h1
      · exact h2 x m
    rw [Nat.le_min]; exact ⟨Nat.min_le_left _ _, Nat.le_trans (Nat.min_le_right _ _) hx⟩

/-- `holdSeparatorNeeds` keeps the lines and headings of the units. -/
theorem holdNeeds_text (capacity : Nat) (blanks : Nat) (held : Bool) (us : List Unit) :
    sourceText (allFlows (holdNeeds capacity blanks held us)) = sourceText (allFlows us) := by
  induction us generalizing blanks held with
  | nil => rfl
  | cons u rest ih =>
    unfold holdNeeds
    split
    · simp only [allFlows, sourceText_append, ih]
    · split
      · rw [allFlows_append, hoisted_text]; simp only [allFlows, sourceText_append, ih]
      · simp only [allFlows, sourceText_append, ih]
      · simp only [allFlows, sourceText_append, ih]

/-- `holdSeparatorNeeds` keeps the flows of the units and puts only
    need-lines in between. -/
theorem holdNeeds_ins (capacity : Nat) (blanks : Nat) (held : Bool) (us : List Unit) :
    Ins (allFlows us) (allFlows (holdNeeds capacity blanks held us)) := by
  induction us generalizing blanks held with
  | nil => exact .nil
  | cons u rest ih =>
    unfold holdNeeds
    split
    · exact (Ins.refl u.flows).append (ih _ _)
    · split
      · rw [allFlows_append]
        exact hoisted_ins _ _ _ ((Ins.refl _).append (ih _ _))
      · exact (Ins.refl _).append (ih _ _)
      · exact (Ins.refl _).append (ih _ _)

theorem separatorFlows_ins (capacity : Nat) (us : List Unit) : Ins (otherFlows us) (separatorFlows capacity us) := by
  have h := allFlows_ins (space none [] us)
  rw [space_other none [] Blanks.nil] at h
  exact h.trans (holdNeeds_ins capacity 0 false _)

theorem plain_flatten {p : Flow} (hp : plainFlow p = true) (r : List Flow) :
    flattenParts (p :: r) = p :: flattenParts r := by
  cases p <;> simp [plainFlow] at hp <;> simp only [flattenParts]

theorem plain_joinsHead {p : Flow} (hp : plainFlow p = true) (a r : List Flow)
    (h : joinsHead (a ++ r) = false) : joinsHead (a ++ p :: r) = false := by
  simp only [joinsHead] at h ⊢
  rw [flattenParts_append, plain_flatten hp]
  rw [flattenParts_append] at h
  cases e : flattenParts a with
  | nil => cases p <;> simp [plainFlow] at hp <;> simp
  | cons x xs =>
    rw [e] at h
    simp only [List.cons_append] at h ⊢
    split at h <;> split <;> simp_all

/-- Putting a plain flow in keeps `BoxesOk`. -/
theorem boxesOk_plain {p : Flow} (hp : plainFlow p = true) (a r : List Flow) (h : BoxesOk (a ++ r)) :
    BoxesOk (a ++ p :: r) := by
  have nb : ∀ i kb ka body, p ≠ .boxed i kb ka body := by
    intro i kb ka body e; subst e; simp [plainFlow] at hp
  have np : ∀ u k ret body, p ≠ .bookPart u k ret body := by
    intro u k ret body e; subst e; simp [plainFlow] at hp
  generalize e : a ++ r = l at h
  induction h generalizing a with
  | nil =>
    obtain ⟨rfl, rfl⟩ := List.append_eq_nil.mp e
    exact .cons p [] (fun i kb ka body q => absurd q (nb i kb ka body))
      (fun i kb ka body q => absurd q (nb i kb ka body)) (fun u k ret body q => absurd q (np u k ret body))
      (fun u k ret body q => absurd q (np u k ret body)) .nil
  | cons f r' box boxBody part partFlat tail ihBody ihPart ihFlat _ =>
    cases a with
    | nil =>
      simp only [List.nil_append] at e
      subst e
      exact .cons p _ (fun i kb ka body q => absurd q (nb i kb ka body))
        (fun i kb ka body q => absurd q (nb i kb ka body)) (fun u k ret body q => absurd q (np u k ret body))
        (fun u k ret body q => absurd q (np u k ret body)) (.cons f r' box boxBody part partFlat tail)
    | cons g a' =>
      simp only [List.cons_append, List.cons.injEq] at e
      obtain ⟨rfl, e⟩ := e
      subst e
      refine .cons g _ ?_ ?_ ?_ ?_ ?_
      · intro i kb ka body q; exact plain_joinsHead hp a' r (box i kb ka body q)
      · intro i kb ka body q
        have := ihBody i kb ka body q (body ++ a') (by rw [List.append_assoc])
        rwa [List.append_assoc] at this
      · intro u k ret body q
        have := ihPart u k ret body q (body ++ a') (by rw [List.append_assoc])
        rwa [List.append_assoc] at this
      · intro u k ret body q
        have := ihFlat u k ret body q (flattenParts body ++ a') (by rw [List.append_assoc])
        rwa [List.append_assoc] at this
      · rename_i ihTail; exact ihTail a' rfl

theorem boxesOk_ins {xs ys : List Flow} (h : Ins xs ys) (a : List Flow) (hb : BoxesOk (a ++ xs)) :
    BoxesOk (a ++ ys) := by
  induction h generalizing a with
  | nil => exact hb
  | keep f _ ih =>
    have := ih (a ++ [f]) (by rw [List.append_assoc]; exact hb)
    rwa [List.append_assoc] at this
  | plain p hp _ ih => exact boxesOk_plain hp a _ (ih a hb)

theorem plain_figureOk {p : Flow} (hp : plainFlow p = true) : figureOk p := by
  cases p <;> simp [plainFlow] at hp <;> simp [figureOk]

theorem figureOk_ins {xs ys : List Flow} (h : Ins xs ys) (hf : ∀ f ∈ xs, figureOk f) : ∀ f ∈ ys, figureOk f := by
  induction h with
  | nil => exact hf
  | keep f _ ih =>
    intro g m
    rcases List.mem_cons.mp m with e | m
    · subst e; exact hf g (List.mem_cons_self _ _)
    · exact ih (fun g m => hf g (List.mem_cons_of_mem _ m)) g m
  | plain p hp _ ih =>
    intro g m
    rcases List.mem_cons.mp m with e | m
    · subst e; exact plain_figureOk hp
    · exact ih hf g m

theorem plain_figs {p : Flow} (hp : plainFlow p = true) : flowFigs p = [] := by
  cases p <;> simp [plainFlow] at hp <;> simp [flowFigs]

theorem sourceFigs_ins {xs ys : List Flow} (h : Ins xs ys) : sourceFigs ys = sourceFigs xs := by
  induction h with
  | nil => rfl
  | keep f _ ih => simp only [sourceFigs, ih]
  | plain p hp _ ih => simp only [sourceFigs, plain_figs hp, ih, List.nil_append]

/-! ## Invariants 4 and 5 on the flows made -/

/-- Root ADR 0352 invariant 4 on the flows of root ADR 0398: the
    pagination of the flows `spaceSeparators` makes of any finite list of
    units ends, by `I4_paginate_ends`. -/
theorem I4_separator_paginate_ends (env : Env) (us : List Unit) :
    ∃ st, paginate env (separatorFlows env.capacity.toNat us) = st :=
  I4_paginate_ends env (separatorFlows env.capacity.toNat us)

/-- Root ADR 0352 invariant 5 for the lines on the flows of root ADR
    0398: the pages hold the line of every visible separator and every
    line and heading of the other units, each once, in the order
    written, by `I5_paginate_text`.  The keep-with-nexts, gaps and blank
    lines `spaceSeparators` puts in or takes out carry no line. -/
theorem I5_separator_text (env : Env) (us : List Unit) :
    pagesText (paginate env (separatorFlows env.capacity.toNat us)).done = unitsText us := by
  rw [I5_paginate_text, separatorFlows, separatorUnits, holdNeeds_text, space_text none [] Blanks.nil]

/-- Root ADR 0352 invariant 5 for the figures on the flows of root ADR
    0398, by `I5_paginate_figures`: its hypotheses on the flows of the
    units other than the separators, the blank lines, the breaks, the
    gaps and the keep-with-nexts give those on the flows made. -/
theorem I5_separator_figures (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (us : List Unit)
    (hf : ∀ f ∈ otherFlows us, figureOk f) (hb : BoxesOk (otherFlows us)) :
    pagesFigs (paginate env (separatorFlows env.capacity.toNat us)).done = sourceFigs (otherFlows us) := by
  have i := separatorFlows_ins env.capacity.toNat us
  rw [I5_paginate_figures env hc hs _ (figureOk_ins i hf) (boxesOk_ins i [] hb), sourceFigs_ins i]

/-! ## The keep after a visible separator -/

theorem space_blanks (previous : Option (Nat × Nat)) (acc bl rest : List Unit) (h : Blanks bl) :
    space previous acc (bl ++ rest) = space previous (acc ++ bl) rest := by
  induction bl generalizing acc with
  | nil => simp
  | cons x xs ih =>
    obtain ⟨k, e⟩ := h x (List.mem_cons_self _ _)
    subst e
    rw [List.cons_append]
    show space previous (acc ++ [.blank k]) (xs ++ rest) = _
    rw [ih _ (fun v m => h v (List.mem_cons_of_mem _ m)), List.append_assoc]
    rfl

theorem space_step (previous : Option (Nat × Nat)) (pending : List Unit) (u : Unit) (rest : List Unit)
    (hu : ∀ k, u ≠ .blank k) (hk : ∀ k, u ≠ .brk k) :
    space previous pending (u :: rest) =
      keepOf previous ++ gapOf (previous.map Prod.snd) pending u ++ u :: space (holdOf u) [] rest := by
  cases u with
  | blank k => exact absurd rfl (hu k)
  | brk k => exact absurd rfl (hk k)
  | _ => rfl

/-- After a visible separator, the blank lines after it and a unit that
    is neither a blank line nor a break, `spaceSeparators` puts the
    separator's line, a keep-with-next of one line, the gap and the unit
    in this order (root ADR 0398: the separator is held with the first
    line of the block after it). -/
theorem I3_separator_keeps (previous : Option (Nat × Nat)) (pending : List Unit) (b a : Nat) (kp : Keep) (l : Line)
    (blanks : List Unit) (hb : Blanks blanks) (u : Unit) (hu : ∀ k, u ≠ .blank k) (hk : ∀ k, u ≠ .brk k)
    (rest : List Unit) :
    ∃ pre, space previous pending (.separator b a kp l :: blanks ++ u :: rest) =
      pre ++ .separator b a kp l :: .keepNext 1 l.id :: gapOf (some a) blanks u ++ u :: space (holdOf u) [] rest := by
  refine ⟨keepOf previous ++ gapOf (previous.map Prod.snd) pending (.separator b a kp l), ?_⟩
  rw [List.cons_append, space_step _ _ _ _ (fun k e => Unit.noConfusion e) (fun k e => Unit.noConfusion e)]
  rw [holdOf, space_blanks _ [] blanks _ hb, List.nil_append, space_step _ _ _ _ hu hk]
  simp only [keepOf, Option.map, Option.isSome, ite_true, List.append_assoc, List.cons_append, List.singleton_append, List.nil_append]

/-! ## What adds up over the flows -/

/-- A function of the flows, such as the lines or the figures they carry,
    that adds up over the flows and gives nothing for the blank lines,
    spaces, keep-with-nexts and need-lines the separators put in. -/
structure Additive {α : Type} (T : List Flow → List α) : Prop where
  nil : T [] = []
  cons : ∀ f r, T (f :: r) = T [f] ++ T r
  onBlank : ∀ n, T [.blank n] = []
  onSpace : ∀ n, T [.space n] = []
  onKeepNext : ∀ n sp, T [.keepNext n sp] = []
  onNeedLines : ∀ n, T [.needLines n] = []

theorem Additive.append {α : Type} {T : List Flow → List α} (h : Additive T) (a b : List Flow) :
    T (a ++ b) = T a ++ T b := by
  induction a with
  | nil => rw [h.nil]; rfl
  | cons x xs ih => rw [List.cons_append, h.cons, ih, ← List.append_assoc, ← h.cons]

theorem Additive.quiet {α : Type} {T : List Flow → List α} (h : Additive T) {us : List Unit} (hq : Quiet us) :
    T (allFlows us) = [] := by
  induction us with
  | nil => exact h.nil
  | cons x xs ih =>
    have t := ih (fun u m => hq u (List.mem_cons_of_mem _ m))
    simp only [allFlows]
    rw [h.append, t, List.append_nil]
    rcases hq x (List.mem_cons_self _ _) with ⟨k, e⟩ | ⟨k, e⟩ | ⟨k, s, e⟩ <;> subst e
    · exact h.onBlank k
    · exact h.onSpace k
    · exact h.onKeepNext k s

/-- `spaceSeparators` keeps what adds up over the flows. -/
theorem Additive.space_eq {α : Type} {T : List Flow → List α} (h : Additive T) (previous : Option (Nat × Nat))
    (pending : List Unit) (hb : Blanks pending) (us : List Unit) :
    T (allFlows (space previous pending us)) = T (allFlows us) := by
  induction us generalizing previous pending with
  | nil =>
    simp only [space]
    split
    · rfl
    · rw [h.quiet (blanks_quiet hb)]; exact h.nil.symm
  | cons u rest ih =>
    cases u with
    | blank k =>
      show T (allFlows (space previous (pending ++ [.blank k]) rest)) = _
      rw [ih previous _ (hb.snoc k)]
      show _ = T ([.blank k] ++ allFlows rest)
      rw [h.append, h.onBlank, List.nil_append]
    | brk k =>
      show T (allFlows (pending ++ .brk k :: space none [] rest)) = T ([.brk k] ++ allFlows rest)
      rw [allFlows_append, h.append, h.quiet (blanks_quiet hb), List.nil_append]
      show T ([.brk k] ++ allFlows (space none [] rest)) = _
      rw [h.append, h.append, ih none [] Blanks.nil]
    | _ =>
      rw [space_step _ _ _ _ (fun k e => Unit.noConfusion e) (fun k e => Unit.noConfusion e)]
      rw [allFlows_append, allFlows_append, h.append, h.append, h.quiet (keep_quiet _),
        h.quiet (gapOf_quiet _ hb _), List.nil_append, List.nil_append]
      simp only [allFlows]
      rw [h.append, h.append, ih _ [] Blanks.nil]

theorem Additive.hoisted_eq {α : Type} {T : List Flow → List α} (h : Additive T) (capacity blanks : Nat)
    (hold : List Unit) (r : List Flow) : T (allFlows (hoisted capacity blanks hold) ++ r) = T r := by
  rcases hoisted_flows capacity blanks hold with e | ⟨n, e⟩ <;> rw [e]
  · rfl
  · rw [h.append, h.onNeedLines, List.nil_append]

/-- `holdSeparatorNeeds` keeps what adds up over the flows. -/
theorem Additive.holdNeeds_eq {α : Type} {T : List Flow → List α} (h : Additive T) (capacity : Nat)
    (blanks : Nat) (held : Bool) (us : List Unit) :
    T (allFlows (holdNeeds capacity blanks held us)) = T (allFlows us) := by
  induction us generalizing blanks held with
  | nil => rfl
  | cons u rest ih =>
    unfold holdNeeds
    split
    · simp only [allFlows]; rw [h.append, h.append, ih]
    · split
      · rw [allFlows_append, h.hoisted_eq]; simp only [allFlows]; rw [h.append, h.append, ih]
      · simp only [allFlows]; rw [h.append, h.append, ih]
      · simp only [allFlows]; rw [h.append, h.append, ih]

theorem Additive.separatorFlows_eq {α : Type} {T : List Flow → List α} (h : Additive T) (capacity : Nat)
    (us : List Unit) : T (separatorFlows capacity us) = T (allFlows us) := by
  rw [separatorFlows, separatorUnits, h.holdNeeds_eq, h.space_eq none [] Blanks.nil]

theorem sourceText_additive : Additive sourceText where
  nil := rfl
  cons f r := by simp [sourceText]
  onBlank n := by simp [sourceText, flowText]
  onSpace n := by simp [sourceText, flowText]
  onKeepNext n sp := by simp [sourceText, flowText]
  onNeedLines n := by simp [sourceText, flowText]

theorem sourceFigs_additive : Additive sourceFigs where
  nil := rfl
  cons f r := by simp [sourceFigs]
  onBlank n := by simp [sourceFigs, flowFigs]
  onSpace n := by simp [sourceFigs, flowFigs]
  onKeepNext n sp := by simp [sourceFigs, flowFigs]
  onNeedLines n := by simp [sourceFigs, flowFigs]

/-! ## The warnings of the need-lines not met -/

/-- The spans of the visible separators, by the ids of their lines, as
    the spans of `USeparator` units `layoutFigures` gives `unmetWarnings`. -/
def separatorSpans : List Unit → List Nat
  | [] => []
  | .separator _ _ _ l :: r => l.id :: separatorSpans r
  | _ :: r => separatorSpans r

def needUnmet : Unmet → Bool
  | .needLines _ => true
  | .keepNext _ => true
  | _ => false

/-- The filter of `unmetWarnings` (Flow.hs): of the controls not met, each
    at the span of its unit, a need-lines at the span of a separator, the
    one `holdSeparatorNeeds` asks for, and a keep-with-next at the span of
    a separator, the one `spaceSeparators` puts after it, report nothing; the others go on
    to their warnings.  `Unmet` of Whole.lean has no span, so the span is
    given beside it. -/
def reported (held : Nat → Bool) (unmet : List (Nat × Unmet)) : List (Nat × Unmet) :=
  unmet.filter fun x => !(held x.1 && needUnmet x.2)

/-- The need-lines asked for before a separator hold and the keep of a
    separator give no warning, and every other control not met goes on to
    its warning. -/
theorem reported_iff (us : List Unit) (unmet : List (Nat × Unmet)) (sp : Nat) (u : Unmet) :
    (sp, u) ∈ reported (fun s => (separatorSpans us).contains s) unmet ↔
      (sp, u) ∈ unmet ∧ (sp ∈ separatorSpans us → (∀ n, u ≠ .needLines n) ∧ ∀ s, u ≠ .keepNext s) := by
  have key : (separatorSpans us).contains sp = true ↔ sp ∈ separatorSpans us :=
    ⟨List.mem_of_elem_eq_true, List.elem_eq_true_of_mem⟩
  unfold reported
  rw [List.mem_filter]
  constructor
  · rintro ⟨m, h⟩
    refine ⟨m, fun hs => ⟨fun n e => ?_, fun s e => ?_⟩⟩ <;> subst e <;> simp [needUnmet, key.mpr hs] at h
  · rintro ⟨m, h⟩
    refine ⟨m, ?_⟩
    by_cases hs : sp ∈ separatorSpans us
    · cases u with
      | needLines n => exact absurd rfl ((h hs).1 n)
      | keepNext s => exact absurd rfl ((h hs).2 s)
      | _ => simp [needUnmet]
    · have : (separatorSpans us).contains sp = false := by
        cases e : (separatorSpans us).contains sp
        · rfl
        · exact absurd (key.mp e) hs
      simp [this]

/-! ## G07134: the post-processing of the pages -/

/-- The ids a slot holds, as `ids` of `separatorHoldErrors`. -/
def slotIds : Slot → List Nat
  | .line i | .figure i | .wrapped i | .pageFigure i | .codeRow i | .repeated i => [i]
  | .heading i c => (List.range c).map (i + ·)
  | .code rows => rows

/-- The page and the column of the first slot that holds the id, the
    pages in the order of output (`places` of `separatorHoldErrors`). -/
def place (pages : List PageOut) (i : Nat) : Option (Nat × Nat) :=
  (pages.find? (fun p => p.slots.any (fun s => (slotIds s.2).contains i))).map (fun p => (p.number, p.column))

/-- `groups` of `separatorHoldErrors`: from the unit at `n`, each chain
    of visible separators by the index of its first, the ids of their
    lines and the first line of the block after them. -/
def groupsFrom : Nat → List (Nat × Nat) → List Unit → List (Nat × List Nat)
  | _, _, [] => []
  | n, pending, .separator _ _ _ l :: rest => groupsFrom (n + 1) ((n, l.id) :: pending) rest
  | n, _, .brk _ :: rest => groupsFrom (n + 1) [] rest
  | n, pending, .blank _ :: rest | n, pending, .gap _ :: rest | n, pending, .keepNext _ _ :: rest =>
    groupsFrom (n + 1) pending rest
  | n, pending, .other role _ first :: rest =>
    match role, first, pending.reverse with
    | .reset, _, _ => groupsFrom (n + 1) [] rest
    | .block, some i, (site, _) :: _ => (site, pending.reverse.map (·.2) ++ [i]) :: groupsFrom (n + 1) [] rest
    | _, _, _ => groupsFrom (n + 1) pending rest

def holdGroups (us : List Unit) : List (Nat × List Nat) := groupsFrom 0 [] us

/-- Whether the ids placed are not all in one column: the first placed
    id's place differs from that of one placed after it. -/
def splitAcross (pages : List PageOut) (ids : List Nat) : Bool :=
  match ids.filterMap (place pages) with
  | p :: rest => rest.any (· != p)
  | [] => false

/-- `separatorHoldErrors`: the index of the first separator of each chain
    split across columns. -/
def holdErrors (us : List Unit) (pages : List PageOut) : List Nat :=
  ((holdGroups us).filter (fun g => splitAcross pages g.2)).map (·.1)

/-- The post-processing of `round'` (Flow.hs): the pages as they are, and
    the diagnostics before it with G07134 added. -/
def postProcess (diagnostics : List Nat) (us : List Unit) (pages : List PageOut) : List PageOut × List Nat :=
  (pages, diagnostics ++ holdErrors us pages)

/-- Root ADR 0352 invariant 5 on G07134: the post-processing leaves the
    pages as they are and only adds diagnostics after those it is given. -/
theorem I5_separator_post_keeps_pages (diagnostics : List Nat) (us : List Unit) (pages : List PageOut) :
    (postProcess diagnostics us pages).1 = pages ∧
      ∃ added, (postProcess diagnostics us pages).2 = diagnostics ++ added :=
  ⟨rfl, _, rfl⟩

theorem split_iff (pages : List PageOut) (ids : List Nat) :
    splitAcross pages ids = true ↔ ∃ a ∈ ids, ∃ b ∈ ids, ∃ p q, place pages a = some p ∧ place pages b = some q ∧ p ≠ q := by
  unfold splitAcross
  constructor
  · intro h
    split at h
    · rename_i p rest e
      obtain ⟨q, mq, hq⟩ := List.any_eq_true.mp h
      have mp : p ∈ ids.filterMap (place pages) := by rw [e]; exact List.mem_cons_self _ _
      have mq' : q ∈ ids.filterMap (place pages) := by rw [e]; exact List.mem_cons_of_mem _ mq
      obtain ⟨a, ma, ea⟩ := (mem_filterMap' _ _ _).mp mp
      obtain ⟨b, mb, eb⟩ := (mem_filterMap' _ _ _).mp mq'
      exact ⟨a, ma, b, mb, p, q, ea, eb, fun e => by simp [e] at hq⟩
    · exact absurd h (by simp)
  · rintro ⟨a, ma, b, mb, p, q, ea, eb, ne⟩
    have mp : p ∈ ids.filterMap (place pages) := (mem_filterMap' _ _ _).mpr ⟨a, ma, ea⟩
    have mq : q ∈ ids.filterMap (place pages) := (mem_filterMap' _ _ _).mpr ⟨b, mb, eb⟩
    split
    · rename_i r rest e
      rw [e] at mp mq
      apply List.any_eq_true.mpr
      rcases List.mem_cons.mp mp with ep | mp
      · rcases List.mem_cons.mp mq with eq | mq
        · exact absurd (ep.trans eq.symm) ne
        · exact ⟨q, mq, by subst ep; simp [Ne.symm ne]⟩
      · by_cases er : p = r
        · rcases List.mem_cons.mp mq with eq | mq
          · exact absurd (er.trans eq.symm) ne
          · exact ⟨q, mq, by subst er; simp [Ne.symm ne]⟩
        · exact ⟨p, mp, by simp [er]⟩
    · rename_i e; rw [e] at mp; exact absurd mp (List.not_mem_nil _)

/-- Root ADR 0352 invariant 3 on G07134: the post-processing reports a
    chain of visible separators exactly when two of its ids, the lines of
    the separators and the first line of the block after them, are
    placed in different columns. -/
theorem I3_separator_error_iff (us : List Unit) (pages : List PageOut) (site : Nat) :
    site ∈ holdErrors us pages ↔
      ∃ ids, (site, ids) ∈ holdGroups us ∧
        ∃ a ∈ ids, ∃ b ∈ ids, ∃ p q, place pages a = some p ∧ place pages b = some q ∧ p ≠ q := by
  unfold holdErrors
  constructor
  · intro m
    obtain ⟨⟨s, ids⟩, mg, e⟩ := List.mem_map.mp m
    obtain ⟨mg, hs⟩ := List.mem_filter.mp mg
    simp only at e
    subst e
    exact ⟨ids, mg, (split_iff pages ids).mp hs⟩
  · rintro ⟨ids, mg, h⟩
    exact List.mem_map.mpr ⟨(site, ids), List.mem_filter.mpr ⟨mg, (split_iff pages ids).mpr h⟩, rfl⟩

/-- The units a chain passes: blank lines, gaps, keep-with-nexts and the
    units that pass it (`UGap`, `UKeepNext`, `UPageControl`), and blocks
    with no line of their own. -/
def passes : Unit → Bool
  | .blank _ | .gap _ | .keepNext _ _ | .other .pass _ _ | .other .block _ none => true
  | _ => false

theorem groupsFrom_passes (n : Nat) (pending : List (Nat × Nat)) (mids : List Unit)
    (hm : ∀ m ∈ mids, passes m = true) (rest : List Unit) :
    groupsFrom n pending (mids ++ rest) = groupsFrom (n + mids.length) pending rest := by
  induction mids generalizing n with
  | nil => rfl
  | cons m ms ih =>
    have h1 := hm m (List.mem_cons_self _ _)
    have h2 := ih (n + 1) (fun x mx => hm x (List.mem_cons_of_mem _ mx))
    simp only [List.cons_append, List.length_cons]
    rw [show n + (ms.length + 1) = (n + 1) + ms.length by omega, ← h2]
    cases m with
    | blank k => simp only [groupsFrom]
    | gap k => simp only [groupsFrom]
    | keepNext k => simp only [groupsFrom]
    | separator => simp [passes] at h1
    | brk => simp [passes] at h1
    | other r fs f =>
      cases r <;> cases f <;> simp [passes] at h1 <;> simp only [groupsFrom]

/-- A visible separator, the units it passes and a block with a first
    line make one chain: the separator's line and the block's first
    line, reported at the separator. -/
theorem groupsFrom_single (n : Nat) (b a : Nat) (kp : Keep) (l : Line) (mids : List Unit)
    (hm : ∀ m ∈ mids, passes m = true) (fs : List Flow) (i : Nat) (rest : List Unit) :
    groupsFrom n [] (.separator b a kp l :: mids ++ .other .block fs (some i) :: rest) =
      (n, [l.id, i]) :: groupsFrom (n + 1 + mids.length + 1) [] rest := by
  rw [List.cons_append]
  show groupsFrom (n + 1) [(n, l.id)] (mids ++ .other .block fs (some i) :: rest) = _
  rw [groupsFrom_passes (n + 1) _ mids hm]
  simp [groupsFrom]

/-- Root ADR 0352 invariant 3 on G07134 for one visible separator
    followed by a block: the post-processing reports it exactly when the
    separator's line and the block's first line are placed in different
    columns. -/
theorem I3_separator_error_single (b a : Nat) (kp : Keep) (l : Line) (mids : List Unit)
    (hm : ∀ m ∈ mids, passes m = true) (fs : List Flow) (i : Nat) (pages : List PageOut) (p q : Nat × Nat)
    (hp : place pages l.id = some p) (hq : place pages i = some q) :
    0 ∈ holdErrors (.separator b a kp l :: mids ++ [.other .block fs (some i)]) pages ↔ p ≠ q := by
  have g : holdGroups (.separator b a kp l :: mids ++ [.other .block fs (some i)]) = [(0, [l.id, i])] := by
    rw [holdGroups, groupsFrom_single 0 b a kp l mids hm fs i []]; rfl
  unfold holdErrors
  rw [g]
  by_cases e : p = q
  · subst e; simp [splitAcross, List.filterMap, hp, hq, List.any]
  · have e' : q ≠ p := fun h => e h.symm
    simp [splitAcross, List.filterMap, hp, hq, List.any, e, e']

/-! ## The empty-column rule -/

/-- The ids the slots of a column hold. -/
def slotsIds (ss : List (Int × Slot)) : List Nat := ss.bind (fun s => slotIds s.2)

theorem slotsIds_append (a b : List (Int × Slot)) : slotsIds (a ++ b) = slotsIds a ++ slotsIds b := by
  simp [slotsIds, List.append_bind]

/-- The ids `a` and `b` are in one column: the current one, or one closed. -/
def Together (st : St) (a b : Nat) : Prop :=
  (a ∈ slotsIds st.slots ∧ b ∈ slotsIds st.slots) ∨ ∃ p ∈ st.done, a ∈ slotsIds p.slots ∧ b ∈ slotsIds p.slots

/-- The state a hold starts from: nothing waits (no break, need-lines,
    blank line, figure or footnote), no box is open, no `FAdjustLines`
    applies, the set of columns starts at the top of the page with no
    footnote lines kept above it, and a column with no footnote has no
    footnote lines. -/
structure Clear (st : St) : Prop where
  breaks : st.breaks = []
  need : st.need = none
  blank : st.blank = []
  box : st.box = none
  adjust : st.adjust = 0
  deferred : st.deferred = []
  pending : st.pending = []
  first : st.firstLine = 0
  reserved : st.reserved = 0
  noteLines : st.notes = [] → st.noteLines = 0

theorem closePage_keeps (env : Env) (st : St) :
    (closePage env st).breaks = st.breaks ∧ (closePage env st).need = st.need ∧ (closePage env st).blank = st.blank ∧
      (closePage env st).box = st.box ∧ (closePage env st).deferred = st.deferred := by
  unfold closePage; split <;> exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem closePage_done (env : Env) (st : St) :
    (∃ new, (closePage env st).done = new ++ st.done) ∧
      (st.slots ≠ [] → ∃ p ∈ (closePage env st).done, p.slots = st.slots) := by
  unfold closePage
  split
  · rename_i h
    refine ⟨⟨[], rfl⟩, fun ne => absurd (isEmpty_nil _ h.1) ne⟩
  · exact ⟨⟨[_], rfl⟩, fun _ => ⟨_, List.mem_cons_self _ _, rfl⟩⟩

theorem openBox_none (st : St) (h : st.box = none) : openBox st = st := by
  unfold openBox; rw [h]

theorem advanceFresh_keeps (env : Env) (b : Bool) (st : St) :
    (advanceFresh env b st).breaks = st.breaks ∧ (advanceFresh env b st).need = st.need ∧
      (advanceFresh env b st).blank = st.blank ∧ (advanceFresh env b st).box = st.box ∧
      (advanceFresh env b st).deferred = st.deferred := by
  obtain ⟨k1, k2, k3, k4, k5⟩ := closePage_keeps env st
  unfold advanceFresh; dsimp only
  split <;> exact ⟨k1, k2, k3, k4, k5⟩

theorem advanceFresh_done (env : Env) (b : Bool) (st : St) :
    (∃ new, (advanceFresh env b st).done = new ++ st.done) ∧
      (st.slots ≠ [] → ∃ p ∈ (advanceFresh env b st).done, p.slots = st.slots) := by
  obtain ⟨⟨new, d1⟩, d2⟩ := closePage_done env st
  unfold advanceFresh; dsimp only
  split
  · refine ⟨⟨⟨st.page, 0, true, [], [], []⟩ :: new, by rw [d1]; rfl⟩, fun ne => ?_⟩
    obtain ⟨p, m, h⟩ := d2 ne; exact ⟨p, List.mem_cons_of_mem _ m, h⟩
  · exact ⟨⟨new, d1⟩, d2⟩

theorem nextColumn_eq (env : Env) (st : St) (c : Clear st) :
    nextColumn env st = { advanceFresh env (decide (st.columns ≤ st.column + 1)) st with deferred := [] } := by
  have hb : advanceTurned (decide (st.columns ≤ st.column + 1)) st = ([], []) := by
    unfold advanceTurned; split <;> simp [c.deferred, spanTurned]
  unfold nextColumn advance advanceIn
  rw [hb]
  simp only [openColumn, c.pending, List.foldl, placeDeferred]
  apply openBox_none
  exact (advanceFresh_keeps env _ st).2.2.2.1.trans c.box

/-- Going on to the next column from a state with nothing waiting opens
    an empty column of the whole capacity, closing the column left. -/
theorem nextColumn_clear (env : Env) (st : St) (c : Clear st) :
    Clear (nextColumn env st) ∧ (nextColumn env st).used = 0 ∧ (nextColumn env st).noteLines = 0 ∧
      (nextColumn env st).slots = [] ∧ (nextColumn env st).notes = [] ∧
      (∃ new, (nextColumn env st).done = new ++ st.done) ∧
      (st.slots ≠ [] → ∃ p ∈ (nextColumn env st).done, p.slots = st.slots) := by
  obtain ⟨k1, k2, k3, k4, _⟩ := advanceFresh_keeps env (decide (st.columns ≤ st.column + 1)) st
  obtain ⟨d1, d2⟩ := advanceFresh_done env (decide (st.columns ≤ st.column + 1)) st
  rw [nextColumn_eq env st c]
  have u : (advanceFresh env (decide (st.columns ≤ st.column + 1)) st).used = 0 := by
    unfold advanceFresh; dsimp only; split <;> simp [top, c.first]
  have nl : (advanceFresh env (decide (st.columns ≤ st.column + 1)) st).noteLines = 0 := by
    unfold advanceFresh; dsimp only; split <;> simp [c.reserved]
  have f : (advanceFresh env (decide (st.columns ≤ st.column + 1)) st).firstLine = 0 := by
    unfold advanceFresh; dsimp only; split <;> simp [c.first]
  have r : (advanceFresh env (decide (st.columns ≤ st.column + 1)) st).reserved = 0 := by
    unfold advanceFresh; dsimp only; split <;> simp [c.reserved]
  have a : (advanceFresh env (decide (st.columns ≤ st.column + 1)) st).adjust = 0 := by
    unfold advanceFresh; dsimp only
  have sl : (advanceFresh env (decide (st.columns ≤ st.column + 1)) st).slots = [] := by
    unfold advanceFresh; dsimp only
  have no : (advanceFresh env (decide (st.columns ≤ st.column + 1)) st).notes = [] := by
    unfold advanceFresh; dsimp only
  have pe : (advanceFresh env (decide (st.columns ≤ st.column + 1)) st).pending = [] := by
    unfold advanceFresh; dsimp only
  exact ⟨⟨k1.trans c.breaks, k2.trans c.need, k3.trans c.blank, k4.trans c.box, a, rfl, pe, f, r, fun _ => nl⟩,
    u, nl, sl, no, d1, d2⟩

/-- A line with no footnote takes one line of the column and nothing else. -/
theorem putLine_plain (env : Env) (st : St) (l : Line) (h : l.notes = []) :
    putLine env st l = { st with slots := st.slots ++ [(st.used, .line l.id)], used := st.used + 1, headingOnly := false } := by
  cases st
  simp [putLine, putLineKeeping, h, splitNotes, partsLines]

theorem clear_putLine (env : Env) (st : St) (l : Line) (h : l.notes = []) (c : Clear st) : Clear (putLine env st l) := by
  rw [putLine_plain env st l h]
  exact ⟨c.breaks, c.need, c.blank, c.box, c.adjust, c.deferred, c.pending, c.first, c.reserved, c.noteLines⟩

theorem clear_addUnmet (u : Unmet) (st : St) (c : Clear st) : Clear (addUnmet u st) :=
  ⟨c.breaks, c.need, c.blank, c.box, c.adjust, c.deferred, c.pending, c.first, c.reserved, c.noteLines⟩

theorem clear_addUnmets (us : List Unmet) (st : St) (c : Clear st) : Clear (us.foldl (fun s u => addUnmet u s) st) := by
  induction us generalizing st with
  | nil => exact c
  | cons u _ ih => exact ih _ (clear_addUnmet u st c)

theorem addUnmets_slots (us : List Unmet) (st : St) :
    (us.foldl (fun s u => addUnmet u s) st).slots = st.slots ∧ (us.foldl (fun s u => addUnmet u s) st).done = st.done ∧
      (us.foldl (fun s u => addUnmet u s) st).used = st.used ∧
      (us.foldl (fun s u => addUnmet u s) st).noteLines = st.noteLines := by
  induction us generalizing st with
  | nil => exact ⟨rfl, rfl, rfl, rfl⟩
  | cons u _ ih => exact ih _

theorem putLines_plain (env : Env) (ls : List Line) (hl : ∀ x ∈ ls, x.notes = []) (st : St) (c : Clear st) :
    Clear (ls.foldl (putLine env) st) ∧ (ls.foldl (putLine env) st).done = st.done ∧
      (ls.foldl (putLine env) st).noteLines = st.noteLines ∧
      (ls.foldl (putLine env) st).used = st.used + ls.length ∧
      ∃ pos : List Int, (ls.foldl (putLine env) st).slots = st.slots ++ (pos.zip (ls.map (fun x => Slot.line x.id))) ∧
        pos.length = ls.length := by
  induction ls generalizing st with
  | nil => exact ⟨c, rfl, rfl, by simp, [], by simp, rfl⟩
  | cons x xs ih =>
    have hx := hl x (List.mem_cons_self _ _)
    obtain ⟨c', d, nl, u, pos, e, len⟩ := ih (fun y m => hl y (List.mem_cons_of_mem _ m)) _ (clear_putLine env st x hx c)
    simp only [List.foldl]
    rw [putLine_plain env st x hx] at c' d nl u e ⊢
    refine ⟨c', d, nl, by rw [u]; simp; omega, st.used :: pos, ?_, by simp [len]⟩
    rw [e]; simp

/-- `fitting` of Decide.hs on lines with no footnote: the lines the free
    lines of the column take, at most all of them. -/
def PlainFitting (env : Env) : Prop :=
  ∀ s (ls : List Line), (∀ x ∈ ls, x.notes = []) → env.fitting s ls = min ls.length (free env s).toNat

/-- The lines of a paragraph that fit the free lines are put one after the
    other in the column. -/
theorem placeLinesGo_all (env : Env) (hfit : PlainFitting env) (pid : Nat) (kp : Keep) (s : St) (isStart : Bool)
    (ls : List Line) (hl : ∀ x ∈ ls, x.notes = []) (ha : s.adjust = 0) (hf : (ls.length : Int) ≤ free env s) :
    placeLinesGo env pid kp s isStart ls = ls.foldl (putLine env) s := by
  match ls with
  | [] => simp [placeLinesGo]
  | l :: ls' =>
    have k0 : env.fitting s (l :: ls') = (l :: ls').length := by
      rw [hfit s _ hl]; apply Nat.min_eq_left; have e := Int.toNat_of_nonneg (show 0 ≤ free env s by omega); omega
    have h1 : ¬(s.adjust < 0 ∧ isEmpty s = true ∧ env.roomForLine s (l :: ls') = false) := by
      rw [ha]; intro h; exact absurd h.1 (by decide)
    have h2 : ¬(kp.all = true ∧ isStart = true ∧ env.fitting s (l :: ls') < (l :: ls').length) := by
      rw [k0]; intro h; exact absurd h.2.2 (Nat.lt_irrefl _)
    have h4 : (l :: ls').length ≤ (lineCount env kp s isStart (l :: ls')).1 := by
      simp only [lineCount, k0, splitAtBreak, Nat.le_refl, ite_true]
      split
      · rw [Nat.min_self]; exact Nat.le_max_right _ _
      · exact Nat.le_refl _
    unfold placeLinesGo
    rw [dif_neg h1, dif_neg h2, dif_pos h4]

/-- A paragraph of one line with no footnote is put at the end of a
    column, from the state given or from a later one with nothing waiting. -/
theorem placeLinesGo_one (env : Env) (pid : Nat) (kp : Keep) (s : St) (isStart : Bool) (l : Line)
    (hl : l.notes = []) (c : Clear s) :
    ∃ s', Clear s' ∧ placeLinesGo env pid kp s isStart [l] = putLine env s' l := by
  by_cases h1 : s.adjust < 0 ∧ isEmpty s = true ∧ env.roomForLine s [l] = false
  · exact absurd h1.1 (by rw [c.adjust]; decide)
  · by_cases h2 : kp.all = true ∧ isStart = true ∧ env.fitting s [l] < [l].length
    · by_cases h3 : isEmpty s = true ∨ s.headingOnly = true
      · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_pos h3]
        exact placeLinesGo_one env pid { kp with all := false } (addUnmet (.splitKept pid) s) isStart l hl
          (clear_addUnmet _ s c)
      · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_neg h3]
        exact placeLinesGo_one env pid kp (nextColumn env s) isStart l hl (nextColumn_clear env s c).1
    · by_cases h4 : [l].length ≤ (lineCount env kp s isStart [l]).1
      · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2, dif_pos h4]
        exact ⟨s, c, rfl⟩
      · have k0 : (lineCount env kp s isStart [l]).1 = 0 := by simp at h4; omega
        unfold placeLinesGo; rw [dif_neg h1, dif_neg h2, dif_neg h4]
        simp only [k0, List.take, List.foldl, List.drop]
        exact placeLinesGo_one env pid kp _ _ l hl
          (nextColumn_clear env _ (clear_addUnmets _ s c)).1
termination_by (allRank kp, rank env s)
decreasing_by
  all_goals simp_wf
  · simp only [allRank, h2.1]; exact Prod.Lex.left _ _ (by decide)
  · have : isEmpty s = false := by
      cases e : isEmpty s
      · rfl
      · exact absurd (Or.inl e) h3
    exact Prod.Lex.right _ (I4_nextColumn_rank env s (Or.inl this))
  · have z := lineCount_zero env kp s isStart [l] k0
    simp only [shortParts, z.1]
    exact Prod.Lex.right _ (I4_nextColumn_rank env s (Or.inl z.2))

theorem mem_take' {α : Type} {l : List α} {k : Nat} {x : α} (m : x ∈ l.take k) : x ∈ l := by
  rw [← List.take_append_drop k l]; exact mem_app.mpr (Or.inl m)

theorem mem_drop' {α : Type} {l : List α} {k : Nat} {x : α} (m : x ∈ l.drop k) : x ∈ l := by
  rw [← List.take_append_drop k l]; exact mem_app.mpr (Or.inr m)

/-- The lines placed so far stay on the pages closed. -/
theorem placeLinesGo_done (env : Env) (pid : Nat) (kp : Keep) (s : St) (isStart : Bool) (ls : List Line)
    (hl : ∀ x ∈ ls, x.notes = []) (c : Clear s) :
    ∃ new, (placeLinesGo env pid kp s isStart ls).done = new ++ s.done := by
  match ls with
  | [] => exact ⟨[], by simp [placeLinesGo]⟩
  | l :: ls' =>
    by_cases h1 : s.adjust < 0 ∧ isEmpty s = true ∧ env.roomForLine s (l :: ls') = false
    · exact absurd h1.1 (by rw [c.adjust]; decide)
    · by_cases h2 : kp.all = true ∧ isStart = true ∧ env.fitting s (l :: ls') < (l :: ls').length
      · by_cases h3 : isEmpty s = true ∨ s.headingOnly = true
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_pos h3]
          exact placeLinesGo_done env pid { kp with all := false } (addUnmet (.splitKept pid) s) isStart _ hl
            (clear_addUnmet _ s c)
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_neg h3]
          obtain ⟨n1, e1⟩ := (nextColumn_clear env s c).2.2.2.2.2.1
          obtain ⟨n2, e2⟩ := placeLinesGo_done env pid kp (nextColumn env s) isStart _ hl (nextColumn_clear env s c).1
          exact ⟨n2 ++ n1, by rw [e2, e1, List.append_assoc]⟩
      · by_cases h4 : (l :: ls').length ≤ (lineCount env kp s isStart (l :: ls')).1
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2, dif_pos h4]
          exact ⟨[], (putLines_plain env _ hl s c).2.1⟩
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2, dif_neg h4]
          have ht : ∀ x ∈ (l :: ls').take (lineCount env kp s isStart (l :: ls')).1, x.notes = [] :=
            fun x m => hl x (mem_take' m)
          have hd : ∀ x ∈ (l :: ls').drop (lineCount env kp s isStart (l :: ls')).1, x.notes = [] :=
            fun x m => hl x (mem_drop' m)
          have p := putLines_plain env _ ht s c
          have c1 := clear_addUnmets (shortParts kp pid (lineCount env kp s isStart (l :: ls')).2 isStart
            (l :: ls').length (lineCount env kp s isStart (l :: ls')).1) _ p.1
          have a1 := addUnmets_slots (shortParts kp pid (lineCount env kp s isStart (l :: ls')).2 isStart
            (l :: ls').length (lineCount env kp s isStart (l :: ls')).1) (((l :: ls').take
              (lineCount env kp s isStart (l :: ls')).1).foldl (putLine env) s)
          obtain ⟨n1, e1⟩ := (nextColumn_clear env _ c1).2.2.2.2.2.1
          obtain ⟨n2, e2⟩ := placeLinesGo_done env pid kp _ (isStart && (lineCount env kp s isStart (l :: ls')).1 == 0) _ hd
            (nextColumn_clear env _ c1).1
          exact ⟨n2 ++ n1, by rw [e2, e1, a1.2.1, p.2.1, List.append_assoc]⟩
termination_by (ls.length, allRank kp, rank env s)
decreasing_by
  all_goals simp_wf
  · simp only [allRank, h2.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ (by decide))
  · have : isEmpty s = false := by
      cases e : isEmpty s
      · rfl
      · exact absurd (Or.inl e) h3
    exact linesLt_rank (I4_nextColumn_rank env s (Or.inl this))
  · by_cases k0 : (lineCount env kp s isStart (l :: ls')).1 = 0
    · have z := lineCount_zero env kp s isStart (l :: ls') k0
      simp only [k0, List.take, List.foldl, List.drop, shortParts, z.1]
      rw [Nat.sub_zero]
      exact linesLt_rank (I4_nextColumn_rank env s (Or.inl z.2))
    · apply Prod.Lex.left
      change ¬ List.length (l :: ls') ≤ (lineCount env kp s isStart (l :: ls')).1 at h4
      simp only [List.length] at h4
      omega

/-- A first part `p` of a paragraph of `n` lines (`firstPart` of
    Decide.hs) that fits leaves every larger part that fits, short of
    the whole, a split of one line or more and no more than it. -/
theorem split_pos (kp : Keep) (n p k : Nat) (hp : 1 ≤ p) (hpk : p ≤ k) (hk : k < n)
    (hfix : splitAtBreak kp true n p = p) :
    1 ≤ splitAtBreak kp true n k ∧ splitAtBreak kp true n k ≤ k := by
  have np : ¬ n ≤ p := by omega
  have nk : ¬ n ≤ k := by omega
  unfold splitAtBreak at hfix ⊢
  rw [if_neg np] at hfix
  rw [if_neg nk]
  cases ha : kp.all
  · simp only [ha] at hfix ⊢
    by_cases a : n - p < kp.last <;> by_cases b : n - k < kp.last <;> simp only [a, b, ite_true, ite_false] at hfix ⊢ <;>
      (split at hfix <;> split <;> simp_all <;> omega)
  · simp only [ha, ite_true] at hfix; omega

theorem zip_first (pos : List Int) (l0 : Line) (ls : List Line) (h : pos.length = (l0 :: ls).length) :
    l0.id ∈ slotsIds (pos.zip ((l0 :: ls).map (fun x => Slot.line x.id))) := by
  cases pos with
  | nil => simp at h
  | cons q qs => simp [slotsIds, List.zip, List.zipWith, slotIds]

/-- A paragraph whose first part `p` fits the free lines puts its first
    line after the slots of the column, in the column or in one closed
    with them. -/
theorem placeLinesGo_first (env : Env) (hfit : PlainFitting env) (kq : Keep) (s : St) (l0 : Line) (ls : List Line)
    (hl : ∀ x ∈ l0 :: ls, x.notes = []) (c : Clear s) (p : Nat) (hp : 1 ≤ p) (hf : (p : Int) ≤ free env s)
    (hpart : (l0 :: ls).length ≤ p ∨ splitAtBreak kq true (l0 :: ls).length p = p) :
    ∃ more, l0.id ∈ slotsIds more ∧
      ((placeLinesGo env l0.id kq s true (l0 :: ls)).slots = s.slots ++ more ∨
        ∃ q ∈ (placeLinesGo env l0.id kq s true (l0 :: ls)).done, q.slots = s.slots ++ more) := by
  by_cases all : ((l0 :: ls).length : Int) ≤ free env s
  · rw [placeLinesGo_all env hfit l0.id kq s true _ hl c.adjust all]
    obtain ⟨_, _, _, _, pos, e, len⟩ := putLines_plain env _ hl s c
    exact ⟨_, zip_first pos l0 ls len, Or.inl e⟩
  · have e0 := Int.toNat_of_nonneg (show 0 ≤ free env s by omega)
    have k0 : env.fitting s (l0 :: ls) = (free env s).toNat := by
      rw [hfit s _ hl]; apply Nat.min_eq_right; omega
    have pk : p ≤ (free env s).toNat := by omega
    have kn : (free env s).toNat < (l0 :: ls).length := by omega
    have fix : splitAtBreak kq true (l0 :: ls).length p = p := by
      rcases hpart with h | h
      · omega
      · exact h
    have sp := split_pos kq _ p _ hp pk kn fix
    have notAll : kq.all = false := by
      cases e : kq.all
      · rfl
      · unfold splitAtBreak at fix; rw [if_neg (by omega), e] at fix; simp at fix; omega
    have h1 : ¬(s.adjust < 0 ∧ isEmpty s = true ∧ env.roomForLine s (l0 :: ls) = false) := by
      rw [c.adjust]; intro h; exact absurd h.1 (by decide)
    have h2 : ¬(kq.all = true ∧ true = true ∧ env.fitting s (l0 :: ls) < (l0 :: ls).length) := by
      rw [notAll]; intro h; cases h.1
    have lc : lineCount env kq s true (l0 :: ls) =
        (splitAtBreak kq true (l0 :: ls).length (free env s).toNat, false) := by
      simp only [lineCount, k0]
      have : (splitAtBreak kq true (l0 :: ls).length (free env s).toNat == 0) = false := by
        cases e : (splitAtBreak kq true (l0 :: ls).length (free env s).toNat == 0)
        · rfl
        · exact absurd ((beq_iff_eq _ _).mp e) (by have := sp.1; omega)
      rw [this]; rfl
    have h4 : ¬(l0 :: ls).length ≤ (lineCount env kq s true (l0 :: ls)).1 := by rw [lc]; omega
    unfold placeLinesGo; rw [dif_neg h1, dif_neg h2, dif_neg h4]
    rw [lc]
    have sh : ∀ a b, shortParts kq l0.id false true a b = [] := by intro a b; simp [shortParts]
    rw [sh]
    simp only [List.foldl]
    generalize hk : splitAtBreak kq true (l0 :: ls).length (free env s).toNat = k at sp ⊢
    obtain ⟨k1, _⟩ := sp
    have ht : ∀ x ∈ (l0 :: ls).take k, x.notes = [] := fun x m => hl x (mem_take' m)
    have hd : ∀ x ∈ (l0 :: ls).drop k, x.notes = [] := fun x m => hl x (mem_drop' m)
    have tk : (l0 :: ls).take k = l0 :: ls.take (k - 1) := by
      match k, k1 with
      | 0, h => exact absurd h (by decide)
      | k + 1, _ => simp
    obtain ⟨c1, _, _, _, pos, e, len⟩ := putLines_plain env _ ht s c
    rw [tk] at len
    have ne : (((l0 :: ls).take k).foldl (putLine env) s).slots ≠ [] := by
      rw [e]; cases pos with
      | nil => simp at len
      | cons q qs => rw [tk]; simp [List.zip, List.zipWith]
    have nc := nextColumn_clear env _ c1
    obtain ⟨q, mq, eq⟩ := nc.2.2.2.2.2.2 ne
    obtain ⟨n2, e2⟩ := placeLinesGo_done env l0.id kq _ (true && k == 0) _ hd nc.1
    refine ⟨_, zip_first pos l0 (ls.take (k - 1)) len, Or.inr ⟨q, ?_, ?_⟩⟩
    · rw [e2]; exact mem_app.mpr (Or.inr mq)
    · rw [eq, e, tk]

theorem applyBreaks_nil (env : Env) (st : St) (h : st.breaks = []) : applyBreaks env st = st := by
  unfold applyBreaks; rw [h]; cases st; simp_all

/-- The step of a paragraph, when no break, need-lines or blank line waits. -/
theorem step_paragraph (env : Env) (st : St) (kp : Keep) (ls : List Line) (rest : List Flow) (c : Clear st) :
    step env st (.paragraph kp ls) rest =
      { checkNoBreak (placeFlow env { st with needAt := none } (.paragraph kp ls) rest) with
        seen := true, lastDeferred := false, spaces := [] } := by
  unfold step
  simp only [applyBreaks_nil env st c.breaks, waitsBehind]
  have nb : needBefore env st (.paragraph kp ls :: rest) = { st with needAt := none } := by
    unfold needBefore; split <;> simp_all [applyNeed, c.need]
  rw [nb]
  have pb : placeBlank env { st with needAt := none } (.paragraph kp ls) rest = { st with needAt := none } := by
    unfold placeBlank; simp [c.blank]
  rw [pb]
  simp

theorem placeFlow_none (env : Env) (st : St) (kp : Keep) (ls : List Line) (rest : List Flow)
    (h : env.keptNeed rest = none) : placeFlow env st (.paragraph kp ls) rest = placeLines env kp st true ls := by
  unfold placeFlow; rw [h]
  show WholePagination.place env st _ rest = _
  unfold WholePagination.place; rfl

theorem placeFlow_some (env : Env) (st : St) (kp : Keep) (ls : List Line) (rest : List Flow) (n : Need)
    (h : env.keptNeed rest = some n) :
    placeFlow env st (.paragraph kp ls) rest = placeKept env (previousKeep env rest kp) (placeLines env kp) st true ls n := by
  unfold placeFlow; rw [h]

theorem needIn_grid (env : Env) (st : St) (n : Nat) : needIn env st noNeed ⟨n, 0⟩ = n := by
  simp [needIn, noNeed]

theorem free_putLine (env : Env) (st : St) (l : Line) (h : l.notes = []) :
    free env (putLine env st l) = free env st - 1 := by
  rw [putLine_plain env st l h]; simp only [free, cap, boxAfter]; omega

/-- The separator's line, kept with the first part of `n` lines of what
    follows it (`placeKept` of Paginate.hs), ends a column with `n` free
    lines left when a column of the whole capacity holds the line and
    those `n` lines. -/
theorem separator_place (env : Env) (hfit : PlainFitting env) (st : St) (kp : Keep) (l : Line) (rest : List Flow)
    (n : Nat) (hl : l.notes = []) (c : Clear st) (hw : heldHere env st = false) (hlast : 1 ≤ kp.last)
    (hhold : 1 + (n : Int) ≤ env.capacity) :
    ∃ s', Clear s' ∧
      placeKept env (previousKeep env rest kp) (placeLines env kp) st true [l] ⟨n, 0⟩ = putLine env s' l ∧
      (n : Int) ≤ free env (putLine env s' l) := by
  have cut : keptCut (previousKeep env rest kp) 1 = 1 := by
    have : 1 ≤ (previousKeep env rest kp).last := by
      unfold previousKeep; split
      · exact Nat.le_trans hlast (Nat.le_max_left _ _)
      · exact hlast
    unfold keptCut; rw [if_pos (Or.inr (Or.inl this))]
  have hl1 : ∀ x ∈ [l], x.notes = [] := fun x m => by rw [mem_one m]; exact hl
  -- the line put in a column of the whole capacity
  have fresh : ∀ s, Clear s → s.used = 0 → s.noteLines = 0 →
      placeLines env kp s true [l] = putLine env s l ∧ (n : Int) ≤ free env (putLine env s l) := by
    intro s cs u nl
    have fs : free env s = env.capacity := by simp only [free, cap, boxAfter, cs.box, cs.adjust, u, nl]; omega
    refine ⟨?_, ?_⟩
    · show placeLinesGo env l.id kp s true [l] = _
      rw [placeLinesGo_all env hfit l.id kp s true [l] hl1 cs.adjust (by simp only [List.length]; omega)]; rfl
    · rw [free_putLine env s l hl, fs]; omega
  unfold placeKept
  have one : [l].length = 1 := rfl
  simp only [one, cut, Nat.sub_self, List.take_zero, List.drop_zero]
  have stA : placeLines env kp st true [] = st := rfl
  rw [stA]
  simp only [needIn_grid, Bool.and_true, List.isEmpty]
  obtain ⟨s', cs', e'⟩ := placeLinesGo_one env l.id kp st true l hl c
  have e1 : placeLines env kp st true [l] = putLine env s' l := e'
  rw [e1]
  by_cases f1 : (n : Int) ≤ free env (putLine env s' l)
  · rw [if_pos f1]; exact ⟨s', cs', rfl, f1⟩
  · rw [if_neg f1, if_neg (fun h => f1 h.2.2)]
    by_cases em : isEmpty st = true
    · exfalso
      have u : st.used = 0 := by
        simp only [isEmpty, Bool.and_eq_true, Bool.or_eq_true, boxTop, c.box, Bool.false_and, or_false] at em
        have := em.2; simp [top, c.first] at this; exact this
      have nl : st.notes = [] := by
        simp only [isEmpty, Bool.and_eq_true] at em; exact isEmpty_nil _ em.1
      obtain ⟨a, b⟩ := fresh st c u (c.noteLines nl)
      rw [← e1, a] at f1; exact f1 b
    · rw [if_neg (fun h => h.elim em (fun h' => by rw [hw] at h'; exact Bool.false_ne_true h'))]
      have nc := nextColumn_clear env st c
      obtain ⟨a, b⟩ := fresh (nextColumn env st) nc.1 nc.2.1 nc.2.2.1
      exact ⟨nextColumn env st, nc.1, a, b⟩

/-- What the empty-column rule reads of a state. -/
def View (st : St) :=
  (st.slots, st.done, st.used, st.noteLines, st.notes, st.breaks, st.need, st.blank, st.box, st.adjust,
    st.deferred, st.pending, st.firstLine, st.reserved)

theorem view_clear {a b : St} (v : View a = View b) (c : Clear a) : Clear b := by
  simp only [View, Prod.mk.injEq] at v
  obtain ⟨_, _, _, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13, e14⟩ := v
  exact ⟨e6 ▸ c.breaks, e7 ▸ c.need, e8 ▸ c.blank, e9 ▸ c.box, e10 ▸ c.adjust, e11 ▸ c.deferred, e12 ▸ c.pending,
    e13 ▸ c.first, e14 ▸ c.reserved, fun h => e4 ▸ c.noteLines (e5 ▸ h)⟩

theorem view_free (env : Env) {a b : St} (v : View a = View b) : free env a = free env b := by
  simp only [View, Prod.mk.injEq] at v
  obtain ⟨_, _, e3, e4, _, _, _, _, e9, e10, _⟩ := v
  simp only [free, cap, boxAfter, e3, e4, e9, e10]

theorem view_checkNoBreak (st : St) : View (checkNoBreak st) = View st := by
  rcases checkNoBreak_eq st with e | ⟨u, e⟩ <;> rw [e] <;> rfl

theorem view_keepNext (env : Env) (st : St) (n sp : Nat) (rest : List Flow) :
    View (step env st (.keepNext n sp) rest) = View st := by
  unfold step
  split
  · rfl
  · obtain ⟨w, e⟩ := waitFor_eq (.keepNext sp) (env.nextFirst n rest) st; rw [e]; rfl

/-- `checkNoBreak` leaves nothing waiting. -/
theorem checkNoBreak_noBreak (st : St) : (checkNoBreak st).noBreak = [] := by
  unfold checkNoBreak
  split
  · assumption
  · rfl

/-- A paragraph or a stanza that `placeKept` sends to the next column
    whole, placed where a separator hold waits, is placed as it is, as
    from an empty column (root ADR 0398 I7, `heldHere`). -/
theorem placeKept_held {α : Type} (env : Env) (kp : Keep) (placeIn : St → Bool → List α → St) (st : St)
    (isStart : Bool) (ls : List α) (n : Need) (hcut : keptCut kp ls.length = ls.length)
    (h0 : placeIn st isStart [] = st) (hh : heldHere env st = true) :
    placeKept env kp placeIn st isStart ls n = placeIn st isStart ls := by
  unfold placeKept
  simp only [hcut, Nat.sub_self, List.take_zero, List.drop_zero, h0, List.isEmpty, Bool.and_true, hh, or_true,
    ite_true, ite_self]

/-- Root ADR 0352 invariant 3 on the empty-column rule of root ADR 0398
    (docs/specifications.md:1873), in the grid mode: a visible separator
    with no space after it, its keep-with-next of one line and the
    paragraph after it put the separator's line and the paragraph's first
    line in one column, when the separator's line and the first part of
    the paragraph that its keep asks for (`n` lines, `keptNeed` of
    Decide.hs, with what a no-break or a keep-with-next after the whole
    paragraph keeps) fit a column of the whole capacity.

    The hypotheses: nothing waits before the separator and the set of
    columns has no footnote lines kept above it (`Clear`), and no
    separator hold waits in its column (`heldHere`); the lines have no
    footnote and `fitting` counts the free lines (`PlainFitting`); the
    separator keeps one last line or more (`keep-last-lines` is 1 or more,
    docs/specifications.md:3100); its keep has the span of a visible
    separator (`env.held sp`); `p`, a first part of the paragraph (its
    whole or a split `splitAtBreak` leaves as it is, as `firstPart` of
    Decide.hs gives), is one line or more and no more than `n`; and either
    no no-break or keep-with-next follows the paragraph (`keptNeed` of
    what follows it is none), or `placeKept` would send the paragraph to
    the next column whole (`keptCut`), as a paragraph of no more lines
    than it keeps last. -/
theorem I3_separator_hold_together (env : Env) (hfit : PlainFitting env) (st : St) (c : Clear st)
    (hw : heldHere env st = false)
    (kp kq : Keep) (l l0 : Line) (ls : List Line) (rest : List Flow) (n p sp : Nat)
    (hl : ∀ x ∈ l :: l0 :: ls, x.notes = []) (hlast : 1 ≤ kp.last)
    (hkept : env.keptNeed (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest) = some ⟨n, 0⟩)
    (hsp : env.held sp = true)
    (hnext : env.keptNeed rest = none ∨
      keptCut (previousKeep env rest kq) (l0 :: ls).length = (l0 :: ls).length)
    (hhold : 1 + (n : Int) ≤ env.capacity)
    (hp : 1 ≤ p) (hpn : p ≤ n) (hpart : (l0 :: ls).length ≤ p ∨ splitAtBreak kq true (l0 :: ls).length p = p) :
    let s1 := step env st (.paragraph kp [l]) (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest)
    let s2 := step env s1 (.keepNext 1 sp) (.paragraph kq (l0 :: ls) :: rest)
    let s3 := step env s2 (.paragraph kq (l0 :: ls)) rest
    placeAll env st (.paragraph kp [l] :: .keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest) = placeAll env s3 rest ∧
      Together s3 l.id l0.id := by
  intro s1 s2 s3
  refine ⟨rfl, ?_⟩
  have hl0 : l.notes = [] := hl l (List.mem_cons_self _ _)
  have hb : ∀ x ∈ l0 :: ls, x.notes = [] := fun x m => hl x (List.mem_cons_of_mem _ m)
  -- the separator
  obtain ⟨s', cs', e', fr⟩ := separator_place env hfit { st with needAt := none } kp l
    (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest) n hl0 (view_clear (a := st) rfl c) hw hlast hhold
  have s1e : s1 = { checkNoBreak (placeFlow env { st with needAt := none } (.paragraph kp [l])
      (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest)) with seen := true, lastDeferred := false, spaces := [] } :=
    step_paragraph env st kp [l] _ c
  have v1 : View s1 = View (putLine env s' l) := by
    rw [s1e, placeFlow_some env _ kp [l] _ _ hkept, e']
    exact view_checkNoBreak _
  have m1 : l.id ∈ slotsIds s1.slots := by
    have : s1.slots = (putLine env s' l).slots := congrArg (·.1) v1
    rw [this, putLine_plain env s' l hl0, slotsIds_append]
    exact mem_app.mpr (Or.inr (by simp [slotsIds, slotIds]))
  have c1 : Clear s1 := view_clear v1.symm (clear_putLine env s' l hl0 cs')
  have f1 : (n : Int) ≤ free env s1 := by rw [view_free env v1]; exact fr
  -- the keep-with-next, waiting in the separator's column
  have v2 : View s2 = View s1 := view_keepNext env s1 1 sp _
  have c2 : Clear s2 := view_clear v2.symm c1
  have f2 : (p : Int) ≤ free env s2 := by rw [view_free env v2]; omega
  have m2 : l.id ∈ slotsIds s2.slots := by
    have : s2.slots = s1.slots := congrArg (·.1) v2
    rw [this]; exact m1
  have h2 : heldHere env { s2 with needAt := none } = true := by
    have nb1 : s1.noBreak = [] := by rw [s1e]; exact checkNoBreak_noBreak _
    have sn1 : s1.seen = true := by rw [s1e]
    have ld1 : s1.lastDeferred = false := by rw [s1e]
    show heldHere env (step env s1 (.keepNext 1 sp) (.paragraph kq (l0 :: ls) :: rest)) = true
    unfold step
    rw [if_neg (by rw [sn1, ld1]; decide)]
    unfold waitFor
    rw [nb1]
    simp [heldHere, hsp]
  -- the paragraph
  have e3 : s3 = { checkNoBreak (placeLinesGo env l0.id kq { s2 with needAt := none } true (l0 :: ls)) with
      seen := true, lastDeferred := false, spaces := [] } := by
    show step env s2 _ rest = _
    rw [step_paragraph env s2 kq _ rest c2]
    cases hk : env.keptNeed rest with
    | none => rw [placeFlow_none env _ kq _ rest hk]; rfl
    | some m =>
      have hcut : keptCut (previousKeep env rest kq) (l0 :: ls).length = (l0 :: ls).length := by
        rcases hnext with h | h
        · rw [hk] at h; cases h
        · exact h
      rw [placeFlow_some env _ kq _ rest m hk, placeKept_held env _ _ _ true _ m hcut rfl h2]; rfl
  obtain ⟨more, mm, h⟩ := placeLinesGo_first env hfit kq { s2 with needAt := none } l0 ls hb (view_clear (a := s2) rfl c2) p hp f2 hpart
  have v3 : View s3 = View (placeLinesGo env l0.id kq { s2 with needAt := none } true (l0 :: ls)) := by
    rw [e3]; exact view_checkNoBreak _
  have sl : s3.slots = (placeLinesGo env l0.id kq { s2 with needAt := none } true (l0 :: ls)).slots :=
    congrArg (·.1) v3
  have dn : s3.done = (placeLinesGo env l0.id kq { s2 with needAt := none } true (l0 :: ls)).done :=
    congrArg (·.2.1) v3
  have both : l.id ∈ slotsIds (s2.slots ++ more) ∧ l0.id ∈ slotsIds (s2.slots ++ more) := by
    rw [slotsIds_append]; exact ⟨mem_app.mpr (Or.inl m2), mem_app.mpr (Or.inr mm)⟩
  rcases h with h | ⟨q, mq, hq⟩
  · left; rw [sl, h]; exact both
  · right; refine ⟨q, by rw [dn]; exact mq, ?_⟩
    rw [hq]; exact both

/-! ## The hold in the pages output -/

theorem bind_nil' {α β : Type} (g : α → List β) : ∀ (xs : List α), (∀ x ∈ xs, g x = []) → xs.bind g = []
  | [], _ => rfl
  | x :: xs, h => by
    rw [List.cons_bind, h x (List.mem_cons_self _ _), bind_nil' g xs (fun y m => h y (List.mem_cons_of_mem _ m))]; rfl

theorem mem_bind_iff {α β : Type} (g : α → List β) (y : β) : ∀ (xs : List α), y ∈ xs.bind g ↔ ∃ x ∈ xs, y ∈ g x
  | [] => by simp
  | x :: xs => by
    rw [List.cons_bind, mem_app, mem_bind_iff g y xs]
    constructor
    · rintro (h | ⟨z, m, h⟩)
      · exact ⟨x, List.mem_cons_self _ _, h⟩
      · exact ⟨z, List.mem_cons_of_mem _ m, h⟩
    · rintro ⟨z, m, h⟩
      cases m with
      | head => exact Or.inl h
      | tail _ m => exact Or.inr ⟨z, m, h⟩

theorem mem_reverse' {α : Type} {x : α} : ∀ {xs : List α}, x ∈ xs → x ∈ xs.reverse
  | _ :: xs, .head _ => by rw [List.reverse_cons]; exact mem_app.mpr (Or.inr (List.mem_cons_self _ _))
  | _ :: xs, .tail _ m => by rw [List.reverse_cons]; exact mem_app.mpr (Or.inl (mem_reverse' m))

theorem find?_none' {α : Type} (f : α → Bool) : ∀ (xs : List α), xs.find? f = none → ∀ x ∈ xs, f x = false
  | [], _, _, m => absurd m (List.not_mem_nil _)
  | y :: ys, h, x, m => by
    unfold List.find? at h
    cases e : f y with
    | true => rw [e] at h; cases h
    | false =>
      rw [e] at h
      cases m with
      | head => exact e
      | tail _ m => exact find?_none' f ys h x m

theorem find?_some' {α : Type} (f : α → Bool) : ∀ (xs : List α) (r : α), xs.find? f = some r → f r = true ∧ r ∈ xs
  | [], _, h => by cases h
  | y :: ys, r, h => by
    unfold List.find? at h
    cases e : f y with
    | true => rw [e] at h; cases h; exact ⟨e, List.mem_cons_self _ _⟩
    | false =>
      rw [e] at h
      obtain ⟨a, b⟩ := find?_some' f ys r h
      exact ⟨a, List.mem_cons_of_mem _ b⟩

/-- Two ids in one column stay in one column when the later steps keep the
    columns closed and the slots of the current column (`Notes.Keeps`). -/
theorem together_keeps {a b : St} (k : Notes.Keeps a b) {x y : Nat} (h : Together a x y) : Together b x y := by
  obtain ⟨⟨ds, e⟩, s⟩ := k
  rcases h with ⟨hx, hy⟩ | ⟨p, mp, hx, hy⟩
  · rcases s with ⟨xs, ex⟩ | ⟨q, mq, xs, eq⟩
    · left; rw [ex, slotsIds_append]; exact ⟨mem_app.mpr (Or.inl hx), mem_app.mpr (Or.inl hy)⟩
    · right
      exact ⟨q, mq, by rw [eq, slotsIds_append]; exact mem_app.mpr (Or.inl hx),
        by rw [eq, slotsIds_append]; exact mem_app.mpr (Or.inl hy)⟩
  · right; exact ⟨p, by rw [e]; exact List.mem_append_of_mem_right _ mp, hx, hy⟩

/-- `closePage` closes the current column with its slots. -/
theorem together_closePage (env : Env) {st : St} {x y : Nat} (h : Together st x y) :
    ∃ p ∈ (closePage env st).done, x ∈ slotsIds p.slots ∧ y ∈ slotsIds p.slots := by
  rcases h with ⟨hx, hy⟩ | ⟨p, mp, hx, hy⟩
  · have ne : st.slots ≠ [] := by
      intro e; rw [e] at hx; exact absurd hx (List.not_mem_nil _)
    obtain ⟨p, mp, ep⟩ := Notes.closePage_closes env st ne
    exact ⟨p, mp, by rw [ep]; exact hx, by rw [ep]; exact hy⟩
  · obtain ⟨⟨ds, e⟩, _⟩ := Notes.keeps_closePage env st
    exact ⟨p, by rw [e]; exact List.mem_append_of_mem_right _ mp, hx, hy⟩

/-- Root ADR 0352 invariant 3 on G07134, from `I3_separator_hold_together`:
    under its hypotheses, the separator's line and the first line of the
    paragraph after it are in one column of the pages output, as the later
    steps keep the columns closed (`Notes.keeps_placeAll`).  It also
    assumes that the footnote separator takes 0 lines or more and that the
    notes after the paragraph are new (`Notes.Fresh`). -/
theorem I3_separator_hold_one_column (env : Env) (hs : 0 ≤ env.separator) (hfit : PlainFitting env) (st : St)
    (c : Clear st) (hw : heldHere env st = false)
    (kp kq : Keep) (l l0 : Line) (ls : List Line) (rest : List Flow) (n p sp : Nat)
    (hl : ∀ x ∈ l :: l0 :: ls, x.notes = []) (hlast : 1 ≤ kp.last)
    (hkept : env.keptNeed (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest) = some ⟨n, 0⟩)
    (hsp : env.held sp = true)
    (hnext : env.keptNeed rest = none ∨
      keptCut (previousKeep env rest kq) (l0 :: ls).length = (l0 :: ls).length)
    (hhold : 1 + (n : Int) ≤ env.capacity)
    (hp : 1 ≤ p) (hpn : p ≤ n) (hpart : (l0 :: ls).length ≤ p ∨ splitAtBreak kq true (l0 :: ls).length p = p)
    (hf : Notes.Fresh st (Notes.sourceNotes rest)) :
    ∃ q ∈ (closePage env (placeAll env st (.paragraph kp [l] :: .keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest))).done,
      l.id ∈ slotsIds q.slots ∧ l0.id ∈ slotsIds q.slots := by
  obtain ⟨e, t⟩ := I3_separator_hold_together env hfit st c hw kp kq l l0 ls rest n p sp hl hlast hkept hsp hnext
    hhold hp hpn hpart
  rw [e]
  have n1 : Notes.flowNotes (.paragraph kp [l]) = [] := by
    simp [Notes.flowNotes, hl l (List.mem_cons_self _ _)]
  have n3 : Notes.flowNotes (.paragraph kq (l0 :: ls)) = [] := by
    have : ∀ x ∈ l0 :: ls, x.notes = [] := fun x m => hl x (List.mem_cons_of_mem _ m)
    simp only [Notes.flowNotes]
    exact bind_nil' _ _ this
  have n2 : Notes.flowNotes (.keepNext 1 sp) = [] := by simp [Notes.flowNotes]
  have r1 := Notes.rel_step env hs st (.paragraph kp [l]) (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest)
  have r2 := Notes.rel_step env hs (step env st (.paragraph kp [l]) (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest))
    (.keepNext 1 sp) (.paragraph kq (l0 :: ls) :: rest)
  have r3 := Notes.rel_step env hs (step env (step env st (.paragraph kp [l])
    (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest)) (.keepNext 1 sp) (.paragraph kq (l0 :: ls) :: rest))
    (.paragraph kq (l0 :: ls)) rest
  rw [n1] at r1; rw [n2] at r2; rw [n3] at r3
  have r := Notes.Rel.nl r1 (Notes.Rel.nl r2 r3)
  have f3 := Notes.Rel.fresh_after r (by rw [List.nil_append]; exact hf)
  exact together_closePage env (together_keeps (Notes.keeps_placeAll env hs rest _ f3) t)

theorem slotsIds_mem {i : Nat} {ss : List (Int × Slot)} :
    i ∈ slotsIds ss ↔ (ss.any (fun s => (slotIds s.2).contains i)) = true := by
  rw [slotsIds, mem_bind_iff, List.any_eq_true]
  constructor
  · rintro ⟨s, m, h⟩; exact ⟨s, m, List.elem_eq_true_of_mem h⟩
  · rintro ⟨s, m, h⟩; exact ⟨s, m, List.mem_of_elem_eq_true h⟩

/-- The place of an id in one column only of the pages. -/
theorem place_one {pages : List PageOut} {q : PageOut} (mq : q ∈ pages) {i : Nat} (hi : i ∈ slotsIds q.slots)
    (hu : ∀ q' ∈ pages, i ∈ slotsIds q'.slots → q' = q) : place pages i = some (q.number, q.column) := by
  unfold place
  cases e : pages.find? (fun p => p.slots.any (fun s => (slotIds s.2).contains i)) with
  | none =>
    have := find?_none' _ _ e q mq
    rw [slotsIds_mem.mp hi] at this; cases this
  | some r =>
    obtain ⟨hr, mr⟩ := find?_some' _ _ _ e
    rw [hu r mr (slotsIds_mem.mpr hr)]; rfl

/-- Under the hypotheses of `I3_separator_hold_one_column`, and when each
    of the two lines is in one column only of the pages output, the
    post-processing reports no G07134 for the chain of the separator and
    the paragraph.  `I3_separator_hold_no_error` derives the last
    hypothesis from the text of the pages (`text_placeAll`). -/
theorem hold_no_error_of_once (env : Env) (hs : 0 ≤ env.separator) (hfit : PlainFitting env) (st : St)
    (c : Clear st) (hw : heldHere env st = false)
    (kp kq : Keep) (l l0 : Line) (ls : List Line) (rest : List Flow) (n p sp : Nat)
    (hl : ∀ x ∈ l :: l0 :: ls, x.notes = []) (hlast : 1 ≤ kp.last)
    (hkept : env.keptNeed (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest) = some ⟨n, 0⟩)
    (hsp : env.held sp = true)
    (hnext : env.keptNeed rest = none ∨
      keptCut (previousKeep env rest kq) (l0 :: ls).length = (l0 :: ls).length)
    (hhold : 1 + (n : Int) ≤ env.capacity)
    (hp : 1 ≤ p) (hpn : p ≤ n) (hpart : (l0 :: ls).length ≤ p ∨ splitAtBreak kq true (l0 :: ls).length p = p)
    (hf : Notes.Fresh st (Notes.sourceNotes rest))
    (b a : Nat) (kp' : Keep) (mids : List Unit) (hm : ∀ m ∈ mids, passes m = true) (fs : List Flow)
    (hu : ∀ i ∈ [l.id, l0.id], ∀ q ∈ (closePage env (placeAll env st
      (.paragraph kp [l] :: .keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest))).done.reverse,
      ∀ q' ∈ (closePage env (placeAll env st
        (.paragraph kp [l] :: .keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest))).done.reverse,
      i ∈ slotsIds q.slots → i ∈ slotsIds q'.slots → q = q') :
    0 ∉ holdErrors (.separator b a kp' l :: mids ++ [.other .block fs (some l0.id)])
      (closePage env (placeAll env st
        (.paragraph kp [l] :: .keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest))).done.reverse := by
  obtain ⟨q, mq, h1, h2⟩ := I3_separator_hold_one_column env hs hfit st c hw kp kq l l0 ls rest n p sp hl hlast
    hkept hsp hnext hhold hp hpn hpart hf
  have mq' := mem_reverse' mq
  have e1 := place_one mq' h1 (fun q' m h => hu l.id (List.mem_cons_self _ _) q' m q mq' h h1)
  have e2 := place_one mq' h2 (fun q' m h =>
    hu l0.id (List.mem_cons_of_mem _ (List.mem_cons_self _ _)) q' m q mq' h h2)
  rw [I3_separator_error_single b a kp' l mids hm fs l0.id _ _ _ e1 e2]
  exact fun ne => ne rfl

/-! ## The ids of the hold, once in the pages output -/

/-- Each element differs from those after it. -/
def Uniq : List Nat → Prop
  | [] => True
  | x :: xs => x ∉ xs ∧ Uniq xs

theorem uniq_append : ∀ {a b : List Nat}, Uniq (a ++ b) → (∀ x ∈ a, x ∉ b) ∧ Uniq b
  | [], _, h => ⟨fun _ m => absurd m (List.not_mem_nil _), h⟩
  | x :: xs, b, h => by
    obtain ⟨hx, h⟩ := (h : x ∉ xs ++ b ∧ Uniq (xs ++ b))
    obtain ⟨d, u⟩ := uniq_append h
    refine ⟨fun y m => ?_, u⟩
    cases m with
    | head => exact fun mb => hx (mem_app.mpr (Or.inr mb))
    | tail _ m => exact d y m

/-- An element of the ids of two members of a list whose ids are unique
    is of one member. -/
theorem uniq_bind {β : Type} (f : β → List Nat) : ∀ (L : List β), Uniq (L.bind f) →
    ∀ q ∈ L, ∀ q' ∈ L, ∀ x, x ∈ f q → x ∈ f q' → q = q'
  | [], _, _, m, _, _, _, _, _ => absurd m (List.not_mem_nil _)
  | y :: ys, h, q, mq, q', mq', x, hx, hx' => by
    rw [List.cons_bind] at h
    obtain ⟨d, u⟩ := uniq_append h
    have inb : ∀ z ∈ ys, x ∈ f z → x ∈ ys.bind f := fun z m hz => (mem_bind_iff f x ys).mpr ⟨z, m, hz⟩
    cases mq with
    | head =>
      cases mq' with
      | head => rfl
      | tail _ m' => exact absurd (inb q' m' hx') (d x hx)
    | tail _ m =>
      cases mq' with
      | head => exact absurd (inb q m hx) (d x hx')
      | tail _ m' => exact uniq_bind f ys u q m q' m' x hx hx'

theorem bind_bind' {α β γ : Type} (g : α → List β) (h : β → List γ) : ∀ (L : List α),
    (L.bind g).bind h = L.bind (fun p => (g p).bind h)
  | [] => rfl
  | x :: xs => by rw [List.cons_bind, List.append_bind, bind_bind' g h xs, List.cons_bind]

/-- The slots `textSlots` leaves out: figures, turned figures, wrapped
    figures, rows of code on their own and the header lines a table
    repeats. -/
def unlisted : Slot → Bool
  | .figure _ | .pageFigure _ | .wrapped _ | .codeRow _ | .repeated _ => true
  | _ => false

theorem codeRows_ids : ∀ (rows : List Nat), (rows.map Slot.codeRow).bind slotIds = rows
  | [] => rfl
  | r :: rs => by rw [List.map_cons, List.cons_bind, codeRows_ids rs]; rfl

/-- An id of a slot is an id of the text of the slots, or of a slot the
    text leaves out. -/
theorem slotsIds_text (i : Nat) : ∀ (ss : List (Int × Slot)), i ∈ slotsIds ss →
    i ∈ (textSlots ss).bind slotIds ∨ ∃ s ∈ ss, unlisted s.2 = true ∧ i ∈ slotIds s.2
  | [], h => absurd h (List.not_mem_nil _)
  | (g, s) :: r, h => by
    have ih := slotsIds_text i r
    have e : slotsIds ((g, s) :: r) = slotIds s ++ slotsIds r := by simp [slotsIds, List.cons_bind]
    have t : textSlots ((g, s) :: r) = textSlots [(g, s)] ++ textSlots r := by
      rw [← textSlots_append]; rfl
    rw [e] at h
    rw [t, List.append_bind]
    rcases mem_app.mp h with h | h
    · cases s with
      | line j => exact Or.inl (mem_app.mpr (Or.inl (by simpa [textSlots, slotIds] using h)))
      | heading j c => exact Or.inl (mem_app.mpr (Or.inl (by simpa [textSlots] using h)))
      | code rows =>
        refine Or.inl (mem_app.mpr (Or.inl ?_))
        simp only [textSlots, List.append_nil, codeRows_ids]; exact h
      | figure j | pageFigure j | wrapped j | codeRow j | repeated j =>
        exact Or.inr ⟨(g, _), List.mem_cons_self _ _, rfl, h⟩
    · rcases ih h with h | ⟨x, mx, ux, hx⟩
      · exact Or.inl (mem_app.mpr (Or.inr h))
      · exact Or.inr ⟨x, List.mem_cons_of_mem _ mx, ux, hx⟩

theorem pagesText_closePage (env : Env) (st : St) : pagesText (closePage env st).done = text st := by
  unfold closePage
  split
  · rename_i e
    have s : st.slots = [] := by
      cases c : st.slots with
      | nil => rfl
      | cons _ _ => simp [c, List.isEmpty] at e
    simp [text, s, textSlots]
  · rw [pagesText_cons]; rfl

/-- Root ADR 0352 invariant 5 read as the ids: when the ids of the text
    placed before and of the flows written are unique, an id is in one
    column only of the pages output, unless a slot the text leaves out
    holds it (`text_placeAll`). -/
theorem once_of_uniq (env : Env) (st : St) (flows : List Flow) (i : Nat)
    (hd : Uniq ((text st ++ sourceText flows).bind slotIds))
    (hn : ∀ q ∈ (closePage env (placeAll env st flows)).done.reverse, ∀ s ∈ q.slots,
      unlisted s.2 = true → i ∉ slotIds s.2) :
    ∀ q ∈ (closePage env (placeAll env st flows)).done.reverse,
      ∀ q' ∈ (closePage env (placeAll env st flows)).done.reverse,
      i ∈ slotsIds q.slots → i ∈ slotsIds q'.slots → q = q' := by
  intro q mq q' mq' h h'
  generalize hL : (closePage env (placeAll env st flows)).done.reverse = L at hn mq mq'
  have toText : ∀ r ∈ L, i ∈ slotsIds r.slots → i ∈ (textSlots r.slots).bind slotIds := by
    intro r mr hr
    rcases slotsIds_text i r.slots hr with t | ⟨s, ms, us, hs⟩
    · exact t
    · exact absurd hs (hn r mr s ms us)
  have e : L.bind (fun p => (textSlots p.slots).bind slotIds) = (text st ++ sourceText flows).bind slotIds := by
    rw [← bind_bind', ← hL, ← text_placeAll env flows st, ← pagesText_closePage env]; rfl
  rw [← e] at hd
  exact uniq_bind (fun p => (textSlots p.slots).bind slotIds) L hd q mq q' mq' i (toText q mq h) (toText q' mq' h')

/-- Root ADR 0352 invariant 3 on G07134 for one visible separator held
    with the paragraph after it: under the hypotheses of
    `I3_separator_hold_one_column`, the post-processing reports no G07134
    for the chain of the separator and the paragraph, when the ids of the
    text placed before and of the flows are unique (golem-typeset numbers
    lines, figures and rows of code by one counter, `nuNext` of Flow.hs)
    and no slot the text leaves out holds the two lines' ids. -/
theorem I3_separator_hold_no_error (env : Env) (hs : 0 ≤ env.separator) (hfit : PlainFitting env) (st : St)
    (c : Clear st) (hw : heldHere env st = false)
    (kp kq : Keep) (l l0 : Line) (ls : List Line) (rest : List Flow) (n p sp : Nat)
    (hl : ∀ x ∈ l :: l0 :: ls, x.notes = []) (hlast : 1 ≤ kp.last)
    (hkept : env.keptNeed (.keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest) = some ⟨n, 0⟩)
    (hsp : env.held sp = true)
    (hnext : env.keptNeed rest = none ∨
      keptCut (previousKeep env rest kq) (l0 :: ls).length = (l0 :: ls).length)
    (hhold : 1 + (n : Int) ≤ env.capacity)
    (hp : 1 ≤ p) (hpn : p ≤ n) (hpart : (l0 :: ls).length ≤ p ∨ splitAtBreak kq true (l0 :: ls).length p = p)
    (hf : Notes.Fresh st (Notes.sourceNotes rest))
    (b a : Nat) (kp' : Keep) (mids : List Unit) (hm : ∀ m ∈ mids, passes m = true) (fs : List Flow)
    (hd : Uniq ((text st ++ sourceText (.paragraph kp [l] :: .keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest)).bind
      slotIds))
    (hn : ∀ i ∈ [l.id, l0.id], ∀ q ∈ (closePage env (placeAll env st
      (.paragraph kp [l] :: .keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest))).done.reverse,
      ∀ s ∈ q.slots, unlisted s.2 = true → i ∉ slotIds s.2) :
    0 ∉ holdErrors (.separator b a kp' l :: mids ++ [.other .block fs (some l0.id)])
      (closePage env (placeAll env st
        (.paragraph kp [l] :: .keepNext 1 sp :: .paragraph kq (l0 :: ls) :: rest))).done.reverse :=
  hold_no_error_of_once env hs hfit st c hw kp kq l l0 ls rest n p sp hl hlast hkept hsp hnext hhold hp hpn hpart hf
    b a kp' mids hm fs (fun i mi => once_of_uniq env st _ i hd (hn i mi))

/-- The flows `separatorFlows` makes of a visible separator with no space
    before or after it and the paragraph after it are the separator's
    line, a keep-with-next of one line and the paragraph. -/
theorem separatorFlows_hold (capacity : Nat) (kp kq : Keep) (l : Line) (ls : List Line) (i : Nat) :
    separatorFlows capacity [.separator 0 0 kp l, .other .block [.paragraph kq ls] (some i)] =
      [.paragraph kp [l], .keepNext 1 l.id, .paragraph kq ls] := rfl

end Separator
end WholePagination
