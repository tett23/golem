/-
Root ADR 0352: the separators of root ADR 0398 on the flows of Whole.lean.

This file models two functions of
modules/golem-typeset/src/Golem/Typeset/Flow.hs.  `spaceSeparators`
(the local function of `blocks`) turns the units of a document into the
units the flow is made of: it puts a keep-with-next of one line after a
visible separator and replaces the blank lines at its boundary by one
space.  `separatorHoldErrors` reads the pages and returns G07134 for each
chain of visible separators whose lines and the first line of the block
after them are not in one column.

The units other than the separators, the blank lines and the breaks are
left abstract: each carries its flows, whether it starts a block, passes
or resets a chain of separators, and the id of its first line.  The
theorems hold for every choice of them.  README.md lists the
correspondence with file:line.
-/
import Whole

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
  /-- `UKeepNext`. -/
  | keepNext (n : Nat)
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
  | .keepNext n => [.keepNext n]
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
def space : Option Nat → List Unit → List Unit → List Unit
  | previous, pending, [] => if previous.isSome then [] else pending
  | previous, pending, .blank k :: rest => space previous (pending ++ [.blank k]) rest
  | _, pending, .brk k :: rest => pending ++ .brk k :: space none [] rest
  | previous, pending, u :: rest =>
    (if previous.isSome then [.keepNext 1] else []) ++ gapOf previous pending u ++ u :: space (afterOf u) [] rest

/-- The units of `blocks`, after `spaceSeparators`. -/
def separatorUnits (us : List Unit) : List Unit := space none [] us

/-- The flows made of the units, as the pagination receives them. -/
def separatorFlows (us : List Unit) : List Flow := allFlows (separatorUnits us)

/-! ## The flows made carry the text and the figures of the units -/

/-- The lines and headings of the units, in the order written: the line
    of each visible separator and the text of the flows of the others. -/
def unitsText (us : List Unit) : List Slot := sourceText (allFlows us)

/-- The flows of the units other than the separators, the blank lines,
    the breaks, the gaps and the keep-with-nexts. -/
def otherFlows : List Unit → List Flow
  | [] => []
  | .other _ fs _ :: r => fs ++ otherFlows r
  | .separator _ _ _ _ :: r | .blank _ :: r | .brk _ :: r | .gap _ :: r | .keepNext _ :: r => otherFlows r

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
def Quiet (us : List Unit) : Prop := ∀ u ∈ us, (∃ k, u = .blank k) ∨ (∃ k, u = .gap k) ∨ (∃ k, u = .keepNext k)

theorem quiet_text {us : List Unit} (h : Quiet us) : sourceText (allFlows us) = [] := by
  induction us with
  | nil => rfl
  | cons x xs ih =>
    have t := ih (fun u m => h u (List.mem_cons_of_mem _ m))
    rcases h x (List.mem_cons_self _ _) with ⟨k, e⟩ | ⟨k, e⟩ | ⟨k, e⟩ <;> subst e <;>
      simp only [allFlows, Unit.flows, List.singleton_append, sourceText, flowText, List.nil_append, t]

theorem quiet_other {us : List Unit} (h : Quiet us) : otherFlows us = [] := by
  induction us with
  | nil => rfl
  | cons x xs ih =>
    have t := ih (fun u m => h u (List.mem_cons_of_mem _ m))
    rcases h x (List.mem_cons_self _ _) with ⟨k, e⟩ | ⟨k, e⟩ | ⟨k, e⟩ <;> subst e <;> exact t

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

theorem keep_quiet (b : Bool) : Quiet (if b then [.keepNext 1] else []) := by
  intro u m
  split at m
  · exact Or.inr (Or.inr ⟨1, mem_one m⟩)
  · exact absurd m (List.not_mem_nil _)

theorem space_text (previous : Option Nat) (pending : List Unit) (h : Blanks pending) (us : List Unit) :
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

theorem space_other (previous : Option Nat) (pending : List Unit) (h : Blanks pending) (us : List Unit) :
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
  | .paragraph _ _ | .blank _ | .space _ | .keepNext _ | .brk _ => true
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

theorem separatorFlows_ins (us : List Unit) : Ins (otherFlows us) (separatorFlows us) := by
  have h := allFlows_ins (separatorUnits us)
  rw [separatorUnits, space_other none [] Blanks.nil] at h
  exact h

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
    ∃ st, paginate env (separatorFlows us) = st :=
  I4_paginate_ends env (separatorFlows us)

/-- Root ADR 0352 invariant 5 for the lines on the flows of root ADR
    0398: the pages hold the line of every visible separator and every
    line and heading of the other units, each once, in the order
    written, by `I5_paginate_text`.  The keep-with-nexts, gaps and blank
    lines `spaceSeparators` puts in or takes out carry no line. -/
theorem I5_separator_text (env : Env) (us : List Unit) :
    pagesText (paginate env (separatorFlows us)).done = unitsText us := by
  rw [I5_paginate_text, separatorFlows, separatorUnits, space_text none [] Blanks.nil]

/-- Root ADR 0352 invariant 5 for the figures on the flows of root ADR
    0398, by `I5_paginate_figures`: its hypotheses on the flows of the
    units other than the separators, the blank lines, the breaks, the
    gaps and the keep-with-nexts give those on the flows made. -/
theorem I5_separator_figures (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (us : List Unit)
    (hf : ∀ f ∈ otherFlows us, figureOk f) (hb : BoxesOk (otherFlows us)) :
    pagesFigs (paginate env (separatorFlows us)).done = sourceFigs (otherFlows us) := by
  have i := separatorFlows_ins us
  rw [I5_paginate_figures env hc hs _ (figureOk_ins i hf) (boxesOk_ins i [] hb), sourceFigs_ins i]

/-! ## The keep after a visible separator -/

theorem space_blanks (previous : Option Nat) (acc bl rest : List Unit) (h : Blanks bl) :
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

theorem space_step (previous : Option Nat) (pending : List Unit) (u : Unit) (rest : List Unit)
    (hu : ∀ k, u ≠ .blank k) (hk : ∀ k, u ≠ .brk k) :
    space previous pending (u :: rest) =
      (if previous.isSome then [.keepNext 1] else []) ++ gapOf previous pending u ++ u :: space (afterOf u) [] rest := by
  cases u with
  | blank k => exact absurd rfl (hu k)
  | brk k => exact absurd rfl (hk k)
  | _ => rfl

/-- After a visible separator, the blank lines after it and a unit that
    is neither a blank line nor a break, `spaceSeparators` puts the
    separator's line, a keep-with-next of one line, the gap and the unit
    in this order (root ADR 0398: the separator is held with the first
    line of the block after it). -/
theorem I3_separator_keeps (previous : Option Nat) (pending : List Unit) (b a : Nat) (kp : Keep) (l : Line)
    (blanks : List Unit) (hb : Blanks blanks) (u : Unit) (hu : ∀ k, u ≠ .blank k) (hk : ∀ k, u ≠ .brk k)
    (rest : List Unit) :
    ∃ pre, space previous pending (.separator b a kp l :: blanks ++ u :: rest) =
      pre ++ .separator b a kp l :: .keepNext 1 :: gapOf (some a) blanks u ++ u :: space (afterOf u) [] rest := by
  refine ⟨(if previous.isSome then [.keepNext 1] else []) ++ gapOf previous pending (.separator b a kp l), ?_⟩
  rw [List.cons_append, space_step _ _ _ _ (fun k e => Unit.noConfusion e) (fun k e => Unit.noConfusion e)]
  rw [afterOf, space_blanks _ [] blanks _ hb, List.nil_append, space_step _ _ _ _ hu hk]
  simp only [Option.isSome, ite_true, List.append_assoc, List.cons_append, List.singleton_append, List.nil_append]

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
  | n, pending, .blank _ :: rest | n, pending, .gap _ :: rest | n, pending, .keepNext _ :: rest =>
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
  | .blank _ | .gap _ | .keepNext _ | .other .pass _ _ | .other .block _ none => true
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

end Separator
end WholePagination
