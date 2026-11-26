/-
Root ADR 0352: where the ids of the slots that `textSlots` leaves out come
from in the grid mode (Whole.lean).

A slot that `textSlots` leaves out (`Separator.unlisted`: a figure, a
turned figure, a wrapped figure, a row of code on its own, a header line a
table repeats) holds only ids of the manuscript: the ids of the figures,
turned figures and wrapped figures written, and the ids of the header
lines of the tables written (`flowUnl`).  `P S` asks every such slot of
the pages closed and of the current column, and every figure waiting, to
hold ids of `S` only; every function of the pagination keeps `P S` when
the ids the flows it reads add are in `S` (`U`, in the shape of `Rel` of
WholeNotes.lean).  `I3_separator_hold_no_error_ids` and
`I3_separator_chain_no_error_ids` of the end of the file discharge with it
the premise `hn` of `I3_separator_hold_no_error` and
`I3_separator_chain_no_error` of Separator.lean.
-/
import Separator

namespace WholePagination
namespace Slots

open Notes
open Separator (unlisted)

/-- A slot the text leaves out holds ids of `S` only. -/
abbrev Ok (S : List Nat) (s : Slot) : Prop := unlisted s = true → ∀ j ∈ Separator.slotIds s, j ∈ S

abbrev SlotsOk (S : List Nat) (ss : List (Int × Slot)) : Prop := ∀ x ∈ ss, Ok S x.2

/-- The slots the text leaves out, on the pages closed, in the current
    column and waiting, hold ids of `S` only. -/
abbrev P (S : List Nat) (st : St) : Prop :=
  (∀ p ∈ st.done, SlotsOk S p.slots) ∧ SlotsOk S st.slots ∧ (∀ d ∈ st.deferred, Ok S (deferredFig d))

/-- From `st` to `s`, reading flows that add the ids `X`, `P S` is kept
    when the ids `X` are in `S`. -/
def U (S : List Nat) (st s : St) (X : List Nat) : Prop := (∀ j ∈ X, j ∈ S) → P S st → P S s

theorem mem_app2 {α : Type} {x : α} : ∀ {a b : List α}, x ∈ a ++ b → x ∈ a ∨ x ∈ b
  | [], _, h => Or.inr h
  | _ :: _, _, .head _ => Or.inl (.head _)
  | _ :: _, _, .tail _ h => match mem_app2 h with
    | Or.inl m => Or.inl (.tail _ m)
    | Or.inr m => Or.inr m

theorem SlotsOk.append {S : List Nat} {a b : List (Int × Slot)} (ha : SlotsOk S a) (hb : SlotsOk S b) :
    SlotsOk S (a ++ b) := fun x m => by
  rcases mem_app2 m with m | m
  · exact ha x m
  · exact hb x m

theorem SlotsOk.listed (S : List Nat) (xs : List (Int × Slot)) (h : ∀ x ∈ xs, unlisted x.2 = false) :
    SlotsOk S xs := fun x m u => by rw [h x m] at u; cases u

theorem U.refl {S : List Nat} (st : St) : U S st st [] := fun _ p => p

theorem U.trans {S : List Nat} {a b c : St} {X1 X2 : List Nat} (h1 : U S a b X1) (h2 : U S b c X2) :
    U S a c (X1 ++ X2) := fun x p =>
  h2 (fun j m => x j (List.mem_append_of_mem_right _ m)) (h1 (fun j m => x j (List.mem_append_of_mem_left _ m)) p)

theorem U.tr {S : List Nat} {a b c : St} {X1 X2 X : List Nat} (h1 : U S a b X1) (h2 : U S b c X2)
    (e : X1 ++ X2 = X) : U S a c X := e ▸ h1.trans h2

theorem U.congr {S : List Nat} {st s : St} {X X' : List Nat} (e : X = X') (h : U S st s X) : U S st s X' := e ▸ h

theorem U.nl {S : List Nat} {a b c : St} {X : List Nat} (h1 : U S a b []) (h2 : U S b c X) : U S a c X :=
  U.tr h1 h2 (List.nil_append _)

theorem U.nr {S : List Nat} {a b c : St} {X : List Nat} (h1 : U S a b X) (h2 : U S b c []) : U S a c X :=
  U.tr h1 h2 (List.append_nil _)

theorem U.wk {S : List Nat} {a b : St} {X Y : List Nat} (h : U S a b X) (e : ∀ j ∈ X, j ∈ Y) : U S a b Y :=
  fun y p => h (fun j m => y j (e j m)) p

/-- Two steps that each add ids of `X`. -/
theorem U.tw {S : List Nat} {a b c : St} {X : List Nat} (h1 : U S a b X) (h2 : U S b c X) : U S a c X :=
  fun x p => h2 x (h1 x p)

theorem U.zero {S : List Nat} {a b : St} {X : List Nat} (h : U S a b []) : U S a b X :=
  U.wk h (fun _ m => (by cases m))

theorem U.ite {S : List Nat} {c : Prop} [Decidable c] {st a b : St} {X : List Nat} (ha : U S st a X)
    (hb : U S st b X) : U S st (if c then a else b) X := by
  split
  · exact ha
  · exact hb

/-- A frame: no slot added, or slots of the text added at the end. -/
syntax "slots_frame" : tactic
macro_rules
  | `(tactic| slots_frame) =>
    `(tactic| first | exact ⟨[], (List.append_nil _).symm, by simp⟩ | exact ⟨_, rfl, by simp [Separator.unlisted]⟩)

/-- The pages closed, the figures waiting stay, and only slots of the
    text are added to the column. -/
theorem U.frame {S : List Nat} {st s : St} (hd : s.done = st.done := by rfl) (hf : s.deferred = st.deferred := by rfl)
    (hs : ∃ xs, s.slots = st.slots ++ xs ∧ ∀ x ∈ xs, unlisted x.2 = false := by
      slots_frame) :
    U S st s [] := by
  intro _ ⟨a, b, c⟩
  obtain ⟨xs, e, l⟩ := hs
  refine ⟨by rw [hd]; exact a, by rw [e]; exact b.append (SlotsOk.listed S xs l), by rw [hf]; exact c⟩

theorem U.fl {S : List Nat} {st s c : St} {X : List Nat} (h : U S s c X) (hd : s.done = st.done := by rfl)
    (hf : s.deferred = st.deferred := by rfl)
    (hs : ∃ xs, s.slots = st.slots ++ xs ∧ ∀ x ∈ xs, unlisted x.2 = false := by
      slots_frame) : U S st c X :=
  U.nl (U.frame hd hf hs) h

theorem U.fr {S : List Nat} {st s c : St} {X : List Nat} (h : U S st s X) (hd : c.done = s.done := by rfl)
    (hf : c.deferred = s.deferred := by rfl)
    (hs : ∃ xs, c.slots = s.slots ++ xs ∧ ∀ x ∈ xs, unlisted x.2 = false := by
      slots_frame) : U S st c X :=
  U.nr h (U.frame hd hf hs)

theorem U.addU {S : List Nat} (u : Unmet) (st : St) : U S st (addUnmet u st) [] := U.frame

/-! ## The operations of State.hs -/

theorem u_putLineKeeping {S : List Nat} (env : Env) (r : Int) (st : St) (l : Line) :
    U S st (putLineKeeping env r st l) [] := U.frame

theorem u_putLine {S : List Nat} (env : Env) (st : St) (l : Line) : U S st (putLine env st l) [] := U.frame

theorem u_putBlock {S : List Nat} (env : Env) (st : St) (n : Nat) (ls : List Line) :
    U S st (putBlock env st n ls) [] := by
  cases ls with
  | nil => exact U.refl st
  | cons l0 ls => exact U.frame

theorem u_closePage {S : List Nat} (env : Env) (st : St) : U S st (closePage env st) [] := by
  unfold closePage; split
  · exact U.refl st
  · intro _ ⟨a, b, c⟩
    refine ⟨fun p m => ?_, b, c⟩
    cases m with
    | head => exact b
    | tail _ m => exact a p m

theorem u_blankPage {S : List Nat} (env : Env) (st : St) : U S st (blankPage env st) [] := by
  intro _ ⟨a, b, c⟩
  refine ⟨fun p m => ?_, b, c⟩
  cases m with
  | head => intro x m; cases m
  | tail _ m => exact a p m

/-- A turned figure of an id of `S` on a page of its own. -/
theorem u_pageFigure {S : List Nat} (env : Env) (st : St) (i : Nat) (hi : i ∈ S) :
    P S st → P S (pageFigure env st i) := by
  intro ⟨a, b, c⟩
  refine ⟨fun p m => ?_, b, c⟩
  cases m with
  | head =>
    intro x m _ j mj
    cases m with
    | head =>
      cases mj with
      | head => exact hi
      | tail _ m => cases m
    | tail _ m => cases m
  | tail _ m => exact a p m

theorem spanTurned_ok {S : List Nat} : ∀ (ds : List Deferred), (∀ d ∈ ds, Ok S (deferredFig d)) →
    (∀ i ∈ (spanTurned ds).1, i ∈ S) ∧ ∀ d ∈ (spanTurned ds).2, Ok S (deferredFig d)
  | [], h => ⟨fun _ m => (by cases m), h⟩
  | .figure i n :: rest, h => ⟨fun _ m => (by cases m), h⟩
  | .pageFigure i :: rest, h => by
    obtain ⟨a, b⟩ := spanTurned_ok rest (fun d m => h d (List.mem_cons_of_mem _ m))
    refine ⟨fun j m => ?_, b⟩
    cases m with
    | head => exact h (.pageFigure i) (List.Mem.head _) rfl i (List.Mem.head _)
    | tail _ m => exact a j m

theorem u_pageFigures {S : List Nat} (env : Env) (ts : List Nat) (hs : ∀ i ∈ ts, i ∈ S) (st : St) :
    P S st → P S (ts.foldl (pageFigure env) st) := by
  induction ts generalizing st with
  | nil => exact id
  | cons t ts ih =>
    intro p
    exact ih (fun i m => hs i (List.mem_cons_of_mem _ m)) _ (u_pageFigure env st t (hs t (List.Mem.head _)) p)

theorem u_carryNote {S : List Nat} (env : Env) (st : St) (p : NotePart) : U S st (carryNote env st p) [] := by
  unfold carryNote; split
  · exact U.addU _ st
  · exact U.frame

theorem u_carryAll {S : List Nat} (env : Env) (ps : List NotePart) (st : St) :
    P S st → P S (ps.foldl (carryNote env) st) := by
  induction ps generalizing st with
  | nil => exact id
  | cons p _ ih => intro h; exact ih _ (u_carryNote env st p (fun _ m => (by cases m)) h)

theorem u_placeDeferred {S : List Nat} (env : Env) (ws : List Deferred) (hw : ∀ d ∈ ws, Ok S (deferredFig d))
    (st : St) (hp : P S st) : P S (placeDeferred env st ws) := by
  induction ws generalizing st with
  | nil => exact hp
  | cons w ws ih =>
    have hw' : ∀ d ∈ ws, Ok S (deferredFig d) := fun d m => hw d (List.mem_cons_of_mem _ m)
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · refine ih hw' _ ⟨hp.1, ?_, hp.2.2⟩
        exact hp.2.1.append (fun x m => by
          cases m with
          | head => exact hw (.figure i n) (List.Mem.head _)
          | tail _ m => cases m)
      · exact ⟨hp.1, hp.2.1, hw⟩
    | pageFigure i => exact ⟨hp.1, hp.2.1, hw⟩

theorem u_advanceFresh {S : List Nat} (env : Env) (b : Bool) (st : St) (hp : P S st) :
    P S (advanceFresh env b st) := by
  have c := u_closePage env st (fun _ m => (by cases m)) hp
  unfold advanceFresh
  dsimp only
  generalize closePage env st = C at c
  by_cases hc : b = true ∧ ¬(List.any C.done fun x => x.number == st.page) = true
  · rw [if_pos hc]
    refine ⟨fun p m => ?_, fun _ m => (by cases m), c.2.2⟩
    cases m with
    | head => intro x m; cases m
    | tail _ m => exact c.1 p m
  · rw [if_neg hc]
    exact ⟨c.1, fun _ m => (by cases m), c.2.2⟩

theorem u_openBox {S : List Nat} (st : St) : U S st (openBox st) [] :=
  U.frame (openBox_done st) (openBox_deferred st) ⟨[], by rw [openBox_slots, List.append_nil], by simp⟩

theorem u_advance {S : List Nat} (env : Env) (b : Bool) (st : St) : U S st (advance env b st) [] := by
  intro _ hp
  have tw : (∀ i ∈ (advanceTurned b st).1, i ∈ S) ∧ ∀ d ∈ (advanceTurned b st).2, Ok S (deferredFig d) := by
    unfold advanceTurned; split
    · exact spanTurned_ok st.deferred hp.2.2
    · exact ⟨fun _ m => (by cases m), hp.2.2⟩
  have f := u_advanceFresh env b st hp
  unfold advance advanceIn openColumn
  refine u_openBox _ (fun _ m => (by cases m)) ?_
  generalize advanceTurned b st = T at tw
  dsimp only
  have g := u_carryAll env st.pending _ (u_pageFigures env T.1 tw.1 _ f)
  exact u_placeDeferred env T.2 tw.2 _ ⟨g.1, g.2.1, fun _ m => (by cases m)⟩

theorem u_nextColumn {S : List Nat} (env : Env) (st : St) : U S st (nextColumn env st) [] := u_advance env _ st

theorem u_nextPage {S : List Nat} (env : Env) (st : St) : U S st (nextPage env st) [] := u_advance env _ st

theorem U.blankP {S : List Nat} (env : Env) (st : St) : U S st (blankPage env st) [] := fun _ p => u_blankPage env st (fun _ m => (by cases m)) p

theorem U.oBox {S : List Nat} (st : St) : U S st (openBox st) [] := u_openBox st

theorem U.addUs {S : List Nat} (us : List Unmet) (st : St) : U S st (us.foldl (fun s u => addUnmet u s) st) [] := by
  induction us generalizing st with
  | nil => exact U.refl st
  | cons u us ih => simp only [List.foldl]; exact U.nl (U.addU u st) (ih _)

theorem u_drainPendingNotes {S : List Nat} (env : Env) (st : St) : U S st (drainPendingNotes env st) [] := by
  obtain ⟨ns, nl, ps, e⟩ := drainPendingNotes_eq env st
  rw [e]; exact U.frame

theorem U.dropBlanks {S : List Nat} (ns : List Nat) (st : St) :
    U S st (ns.foldl (fun s _ => addUnmet .droppedBlank s) st) [] := by
  induction ns generalizing st with
  | nil => exact U.refl st
  | cons n ns ih => simp only [List.foldl]; exact U.nl (U.addU _ st) (ih _)

theorem U.addWs {S : List Nat} (ws : List (Unmet × Nat × Nat × Nat × (Nat × Bool))) (st : St) :
    U S st (ws.foldl (fun s w => addUnmet w.1 s) st) [] := by
  induction ws generalizing st with
  | nil => exact U.refl st
  | cons w ws ih => simp only [List.foldl]; exact U.nl (U.addU _ st) (ih _)

theorem u_startSet {S : List Nat} (env : Env) (st : St) (n : Nat) (first : Int) : U S st (startSet env st n first) [] := by
  intro x p
  have c := u_closePage env st x p
  exact ⟨c.1, fun _ m => (by cases m), c.2.2⟩

/-! ## The ids the flows add -/

mutual
/-- The ids of the slots the text leaves out that a flow may add: its
    figure, turned figure or wrapped figure, and the header lines of a
    table, which a later column repeats. -/
def flowUnl : Flow → List Nat
  | .figure i _ => [i]
  | .pageFigure i => [i]
  | .wrapped i _ _ => [i]
  | .table _ h _ _ _ => h.map (·.id)
  | .bookPart _ _ _ body | .boxed _ _ _ body => sourceUnl body
  | _ => []
termination_by f => sizeOf f
def sourceUnl : List Flow → List Nat
  | [] => []
  | g :: r => flowUnl g ++ sourceUnl r
termination_by fs => sizeOf fs
end

theorem sourceUnl_append (a b : List Flow) : sourceUnl (a ++ b) = sourceUnl a ++ sourceUnl b := by
  induction a with
  | nil => simp [sourceUnl]
  | cons x xs ih => simp only [List.cons_append, sourceUnl, ih, List.append_assoc]

theorem sourceUnl_flatten (fs : List Flow) : sourceUnl (flattenParts fs) = sourceUnl fs := by
  match fs with
  | [] => simp [flattenParts, sourceUnl]
  | f :: r =>
    have := sourceUnl_flatten r
    cases f with
    | bookPart u k i b =>
      have := sourceUnl_flatten b
      simp only [flattenParts, sourceUnl_append, sourceUnl, flowUnl, *]
    | boxed j kb ka b =>
      have := sourceUnl_flatten b
      simp only [flattenParts, sourceUnl, flowUnl, *]
    | _ => simp only [flattenParts, sourceUnl, *]
termination_by sizeOf fs

variable {S : List Nat}

section
variable (env : Env)

theorem u_keep (st : St) (need : St → Int) : U S st (keep env st need) [] := by
  by_cases h : free env st < need st ∧ isEmpty st = false
  · unfold keep; rw [dif_pos h]; exact U.nl (u_nextColumn env st) (u_keep (nextColumn env st) need)
  · unfold keep; rw [dif_neg h]; exact U.refl st
termination_by rank env st
decreasing_by exact I4_nextColumn_rank env st (Or.inl h.2)

theorem u_flushDeferred (st : St) : U S st (flushDeferred env st) [] := by
  by_cases h : st.deferred = [] ∧ st.pending = []
  · unfold flushDeferred; rw [dif_pos h]; exact U.refl st
  · unfold flushDeferred; rw [dif_neg h]
    exact U.nl (u_nextColumn env st) (u_flushDeferred (nextColumn env st))
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st h)

theorem u_flushFigures (st : St) : U S st (flushFigures env st) [] := by
  by_cases h : st.deferred = []
  · unfold flushFigures; rw [dif_pos h]; exact U.refl st
  · unfold flushFigures; rw [dif_neg h]
    exact U.nl (u_nextColumn env st) (u_flushFigures (nextColumn env st))
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st (fun c => h c.1))

theorem u_parityStart (p : Nat → Bool) (st : St) : U S st (parityStart env p st) [] := by
  simp only [parityStart]
  have h0 : U S st (flushDeferred env st) [] := u_flushDeferred env st
  have h1 : U S st (if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then
      flushDeferred env st else nextPage env (flushDeferred env st)) [] :=
    U.ite h0 (U.nl h0 (u_nextPage env _))
  generalize (if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then
      flushDeferred env st else nextPage env (flushDeferred env st)) = s1 at h1
  exact U.ite h1 (U.nl h1 (U.blankP env s1))

theorem u_breakPage (st : St) : U S st (breakPage env st) [] := by
  simp only [breakPage]
  exact U.ite (U.blankP env st) (U.ite (U.refl st) (u_nextPage env st))

theorem u_applyBreakKind (st : St) (k : BreakKind) : U S st (applyBreakKind env st k) [] := by
  cases k
  · exact u_breakPage env st
  · exact U.ite (u_nextColumn env st) (u_breakPage env st)
  · exact u_parityStart env odd st
  · exact u_parityStart env even st

theorem u_startBefore (st : St) (sec : Option Nat) (k : BreakKind) : U S st (startBefore env st sec k) [] := by
  have h1 : U S st (match k with
      | .column => if isEmpty st then st else nextColumn env st
      | .page =>
        if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
        else nextPage env (flushDeferred env st)
      | .recto => parityStart env odd st
      | .verso => parityStart env even st) [] := by
    cases k
    · exact U.ite (u_flushDeferred env st) (U.nl (u_flushDeferred env st) (u_nextPage env _))
    · exact U.ite (U.refl st) (u_nextColumn env st)
    · exact u_parityStart env odd st
    · exact u_parityStart env even st
  simp only [startBefore]
  split
  · exact U.fr h1
  · exact h1

theorem u_applyBreaks (st : St) : U S st (applyBreaks env st) [] := by
  simp only [applyBreaks]
  suffices ∀ (ks : List Pending) (s : St), U S s (ks.foldl (applyPending env) s) [] from
    U.fl (this st.breaks _)
  intro ks
  induction ks with
  | nil => intro s; exact U.refl s
  | cons k ks ih =>
    intro s; simp only [List.foldl]
    refine U.nl ?_ (ih _)
    cases k with
    | brk k => exact u_applyBreakKind env s k
    | start sec k => exact u_startBefore env s sec k

theorem u_applyNeed (st : St) : U S st (applyNeed env st) [] := by
  unfold applyNeed
  split
  · exact U.refl st
  · split
    · rename_i _ n _ _
      have a : U S st (addUnmet (.needLines n) { st with need := none }) [] :=
        U.fl (U.addU _ _)
      exact U.ite a (U.nl a (u_nextColumn env _))
    · exact U.fl (u_keep env _ _)

theorem u_needBeforeSpace (st : St) : U S st (needBeforeSpace env st) [] := by
  unfold needBeforeSpace
  split
  · exact U.refl st
  · split
    · exact U.refl st
    · split
      · exact U.fl (u_applyNeed env _)
      · dsimp only
        exact U.fr (U.fl (u_applyNeed env { st with needAt := none }))

theorem u_placeSpaceFlow (st : St) (n : Nat) : U S st (placeSpaceFlow env st n) [] := by
  unfold placeSpaceFlow; split
  · exact U.refl st
  · exact U.frame

theorem u_placeSpace (st : St) (n : Nat) : U S st (placeSpace env st n) [] :=
  U.fr (u_placeSpaceFlow env st n)

theorem u_placeSpaces (ns : List Nat) (st : St) : U S st (ns.foldl (placeSpace env) st) [] := by
  induction ns generalizing st with
  | nil => exact U.refl st
  | cons n ns ih => simp only [List.foldl]; exact U.nl (u_placeSpace env st n) (ih _)

theorem u_needBeforeSpaces (st : St) : U S st (needBeforeSpaces env st) [] := by
  unfold needBeforeSpaces
  simp only
  have a := U.nl (U.frame : U S st { st with used := st.used - (st.spaces.map (·.2)).foldr (· + ·) 0 } [])
    (u_needBeforeSpace env _)
  split
  · exact U.fr a
  · exact U.nr a (u_placeSpaces env _ _)

theorem u_needAfterSpaces (st : St) : U S st (needAfterSpaces env st) [] := by
  unfold needAfterSpaces; split
  · exact U.refl st
  · exact u_needBeforeSpaces env st

theorem u_needMore (n : Nat) (st : St) : U S st (needMore env n st) [] := by
  unfold needMore
  split
  · split
    · exact U.refl st
    · exact U.fl (u_needAfterSpaces env _)
  · exact U.fl (u_needAfterSpaces env _)

theorem u_needBefore (st : St) (flows : List Flow) : U S st (needBefore env st flows) [] := by
  unfold needBefore
  split
  · split
    · exact U.fl (u_keep env _ _)
    · exact U.fl (u_applyNeed env _)
  · exact U.fl (u_applyNeed env _)

theorem u_placeBlank (st : St) (f : Flow) (rest : List Flow) : U S st (placeBlank env st f rest) [] := by
  unfold placeBlank
  split
  · exact U.refl st
  · simp only
    have h1 : U S st (if startsRecto f = true then parityStart env odd st else st) [] :=
      U.ite (u_parityStart env odd st) (U.refl st)
    generalize (if startsRecto f = true then parityStart env odd st else st) = s1 at h1
    exact U.ite (U.nl (U.nl h1 (u_keep env s1 _)) (U.fl (U.dropBlanks _ _)))
      (U.fr (U.nl h1 (u_keep env s1 _)))

end

/-! ## Lines, stanzas, code and tables -/

section
variable (env : Env)

theorem u_putLines (ls : List Line) (st : St) : U S st (ls.foldl (putLine env) st) [] := by
  induction ls generalizing st with
  | nil => exact U.refl st
  | cons l ls ih => simp only [List.foldl]; exact U.tr (u_putLine env st l) (ih _) rfl

theorem u_placeLinesGo (pid : Nat) (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) :
    U S st (placeLinesGo env pid kp st isStart ls) [] := by
  match ls with
  | [] => simp only [placeLinesGo]; exact U.refl st
  | l :: ls' =>
    by_cases h1 : st.adjust < 0 ∧ isEmpty st = true ∧ env.roomForLine st (l :: ls') = false
    · unfold placeLinesGo; rw [dif_pos h1]
      exact U.nl (u_nextColumn env st) (u_placeLinesGo pid kp (nextColumn env st) isStart (l :: ls'))
    · by_cases h2 : kp.all = true ∧ isStart = true ∧ env.fitting st (l :: ls') < (l :: ls').length
      · by_cases h3 : isEmpty st = true ∨ st.headingOnly = true
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_pos h3]
          exact U.nl (U.addU _ st)
            (u_placeLinesGo pid { kp with all := false } (addUnmet (.splitKept pid) st) isStart (l :: ls'))
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_neg h3]
          exact U.nl (u_nextColumn env st) (u_placeLinesGo pid kp (nextColumn env st) isStart (l :: ls'))
      · by_cases h4 : (l :: ls').length ≤ (lineCount env kp st isStart (l :: ls')).1
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_pos h4]; exact u_putLines env _ st
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_neg h4]
          exact U.tr (U.nr (u_putLines env _ st) (U.addUs _ _))
            (U.nl (u_nextColumn env _)
              (u_placeLinesGo pid kp _ _ ((l :: ls').drop (lineCount env kp st isStart (l :: ls')).1)))
            rfl
termination_by (ls.length, allRank kp, rank env st)
decreasing_by
  all_goals simp_wf
  · exact linesLt_rank (I4_nextColumn_rank env st (Or.inr h1.1))
  · simp only [allRank, h2.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ (by decide))
  · have : isEmpty st = false := by
      cases e : isEmpty st
      · rfl
      · exact absurd (Or.inl e) h3
    exact linesLt_rank (I4_nextColumn_rank env st (Or.inl this))
  · by_cases k0 : (lineCount env kp st isStart (l :: ls')).1 = 0
    · have z := lineCount_zero env kp st isStart (l :: ls') k0
      simp only [k0, List.take, List.foldl, List.drop, shortParts, z.1]
      rw [Nat.sub_zero]
      exact linesLt_rank (I4_nextColumn_rank env st (Or.inl z.2))
    · apply Prod.Lex.left
      simp only [List.length] at h4
      omega

theorem u_placeLines (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) :
    U S st (placeLines env kp st isStart ls) [] := by
  cases ls with
  | nil => simp only [placeLines]; exact U.refl st
  | cons l ls => exact u_placeLinesGo env _ _ _ _ _

theorem u_putVerses (st : St) (vs : List (List Line)) :
    U S st (putVerses env st vs) [] := u_putLines env vs.join st

theorem u_placeStanzaGo (pid : Nat) (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) :
    U S st (placeStanzaGo env pid kp st isStart vs) [] := by
  match vs with
  | [] => simp only [placeStanzaGo]; exact U.refl st
  | v :: more =>
    unfold placeStanzaGo
    simp only
    split
    · split
      · exact U.nl (U.addU _ st) (u_placeStanzaGo pid { kp with all := false } _ isStart (v :: more))
      · exact U.nl (u_nextColumn env st) (u_placeStanzaGo pid kp _ isStart (v :: more))
    · split
      · exact u_putVerses env st _
      · split
        · exact U.tr (u_putVerses env st _) (U.nl (u_nextColumn env _) (u_placeStanzaGo pid kp _ false _))
            rfl
        · split
          · split
            · exact U.tr (U.nr (u_placeLines env _ st isStart v) (U.addUs _ _))
                (u_placeStanzaGo pid kp _ false more) (by simp [List.append_bind])
            · exact U.tr (U.nr (u_putVerses env st _) (U.addUs _ _))
                (U.nl (u_nextColumn env _) (u_placeStanzaGo pid kp _ false _)) rfl
          · exact U.nl (u_nextColumn env st) (u_placeStanzaGo pid kp _ isStart (v :: more))
termination_by (vs.length, allRank kp, rank env st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; apply Prod.Lex.left; simp_all [allRank]; done)
    | (apply linesLt_rank; apply I4_nextColumn_rank; left; cases e : isEmpty st
       · rfl
       · simp [emptyish, e] at *)

theorem u_placeStanza (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) :
    U S st (placeStanza env kp st isStart vs) [] := by
  unfold placeStanza; split <;> exact u_placeStanzaGo env _ _ _ _ _

theorem u_placeCode (g cap0 first : Nat) (cont : Bool) (st : St) (isFirst : Bool) (ls : List Line) :
    U S st (placeCode env g cap0 first cont st isFirst ls) [] := by
  match ls with
  | [] => unfold placeCode; exact U.refl st
  | l0 :: ls' =>
    by_cases h : codeCount env g cap0 first cont st isFirst (l0 :: ls').length = 0
    · unfold placeCode; rw [dif_pos h]
      exact U.nl (u_nextColumn env st) (u_placeCode g cap0 first cont (nextColumn env st) isFirst (l0 :: ls'))
    · unfold placeCode; rw [dif_neg h]
      simp only
      split
      · exact U.frame
      · exact U.fl (U.nl (u_nextColumn env _)
          (u_placeCode g cap0 first cont _ false ((l0 :: ls').drop (codeCount env g cap0 first cont st isFirst (l0 :: ls').length))))
termination_by (ls.length, rank env st)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.right _ (I4_nextColumn_rank env st
      (Or.inl (codeCount_zero env g cap0 first cont st isFirst _ (by simp) h)))
  · apply Prod.Lex.left
    simp only [List.length, Nat.succ_eq_add_one] at *
    omega

/-- The header lines repeated hold the ids of the header. -/
theorem u_putRepeateds (ls : List Line) (st : St) : U S st (ls.foldl putRepeated st) (ls.map (·.id)) := by
  induction ls generalizing st with
  | nil => exact U.refl st
  | cons l ls ih =>
    simp only [List.foldl, List.map]
    refine U.tr (X1 := [l.id]) ?_ (ih _) rfl
    intro x ⟨a, b, c⟩
    refine ⟨a, b.append (fun y m => ?_), c⟩
    cases m with
    | head =>
      intro _ j mj
      cases mj with
      | head => exact x _ (List.Mem.head _)
      | tail _ m => cases m
    | tail _ m => cases m

theorem u_tableRowsGo (h capt : List Line) (below : Bool) (st : St) (first : Int) (rows : List (List Line)) :
    U S st (tableRowsGo env h capt below st first rows) (h.map (·.id)) := by
  match rows with
  | [] => unfold tableRowsGo; exact U.zero (U.refl st)
  | r :: rest =>
    by_cases h1 : (withCaption capt below r rest).length ≤ env.fitting st (withCaption capt below r rest)
        ∨ st.used = first + h.length
    · unfold tableRowsGo; rw [dif_pos h1]
      exact U.tw (U.zero (u_putLines env r st)) (u_tableRowsGo h capt below _ first rest)
    · unfold tableRowsGo; rw [dif_neg h1]
      simp only
      exact U.tw (U.zero (U.nl (u_nextColumn env st) (u_keep env _ _))) (U.tw (u_putRepeateds _ _)
        (u_tableRowsGo h capt below _ _ (r :: rest)))
termination_by (rows.length, if st.used = first + h.length then 0 else 1)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
    have : ¬ st.used = first + h.length := fun e => h1 (Or.inr e)
    simp only [putRepeateds_used, this, ite_true, ite_false]
    decide

theorem u_placeTable (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    U S st (placeTable env st h rows capt below) (h.map (·.id)) := by
  cases below
  · simp only [placeTable]
    exact U.tw (U.zero (U.nl (u_putLines env capt st) (u_putLines env h _))) (u_tableRowsGo env _ _ _ _ _ _)
  · simp only [placeTable]
    exact U.tw (U.tw (U.zero (u_putLines env h st)) (u_tableRowsGo env _ _ _ _ _ _)) (U.zero (u_putLines env capt _))

theorem u_nextSpread (t : Nat) (st : St) : U S st (nextSpread env t st) [] := by
  by_cases h : (nextPage env st).page < t
  · unfold nextSpread; rw [dif_pos h]; exact U.nl (u_nextPage env st) (u_nextSpread t (nextPage env st))
  · unfold nextSpread; rw [dif_neg h]; exact u_nextPage env st
termination_by t - st.page
decreasing_by simp_wf; have := nextPage_page_gt env st; omega

theorem u_nextUnit (unit : KeepParts) (st : St) : U S st (nextUnit env unit st) [] := by
  cases unit
  · exact u_nextColumn env st
  · exact u_nextPage env st
  · exact u_nextSpread env _ st

theorem u_partTrial (runBody runPlain : St → St) (X : List Nat)
    (hb : ∀ s, U S s (runBody s) X) (hp : ∀ s, U S s (runPlain s) X)
    (unit : KeepParts) (fits : St → Bool) (nested whole : Bool) (st : St) :
    U S st (partTrial env runBody runPlain unit fits nested whole st) X := by
  simp only [partTrial]
  repeat' split
  all_goals first
    | exact hp _
    | exact U.nr (hp _) (u_flushFigures env _)
    | exact U.nr (hb _) (u_flushFigures env _)

/-- Every trial of a book part adds the same ids. -/
theorem u_placeBookPart (runBody runPlain : St → St) (X : List Nat)
    (hb : ∀ s, U S s (runBody s) X) (hp : ∀ s, U S s (runPlain s) X)
    (initial : St) (unit : KeepParts) (kind : Option Nat) (retained : List Nat) (nested whole : Bool) :
    U S initial (placeBookPart env runBody runPlain initial unit kind retained nested whole) X := by
  have pt := u_partTrial env runBody runPlain X hb hp unit
  simp only [placeBookPart]
  repeat' split
  all_goals first
    | exact hb _
    | exact pt _ _ _ _
    | exact U.nl (u_nextUnit env unit _) (pt _ _ _ _)
    | exact U.nr (hb _) (U.addU _ _)
    | exact U.nr (pt _ _ _ _) (U.addU _ _)
    | exact U.nr (U.nl (u_nextUnit env unit _) (hb _)) (U.addU _ _)

theorem u_acrossGo (h capt : List Line) (below retain fresh retried : Bool) (st : St)
    (gs : List (Bool × List Line)) :
    U S st (acrossGo env h capt below retain fresh retried st gs) (h.map (·.id)) := by
  match gs with
  | [] => unfold acrossGo; exact U.zero (U.refl st)
  | (isHeader, ls) :: remaining =>
    by_cases hr : fresh = true ∧ retainsTail env capt below retain isHeader remaining = true
    · unfold acrossGo; rw [dif_pos hr]
      apply u_placeBookPart env
      all_goals intro s
      all_goals refine U.tw ?_ (u_acrossGo h capt below false true false _ ((isHeader, ls) :: remaining))
      all_goals split
      all_goals first | exact U.zero (U.refl _) | exact u_putRepeateds _ _
    · by_cases h1 : ls.length ≤ env.fitting st ls ∨ isEmpty st = true
      · unfold acrossGo; rw [dif_neg hr, dif_pos h1]
        exact U.tw (U.zero (u_putLines env ls st)) (u_acrossGo h capt below retain true false _ remaining)
      · unfold acrossGo; rw [dif_neg hr, dif_neg h1]
        refine U.tw ?_ (u_acrossGo h capt below retain false _ _ ((isHeader, ls) :: remaining))
        split
        · exact U.nl (u_nextColumn env st) (u_putRepeateds _ _)
        · exact U.zero (u_nextColumn env st)
termination_by (if retain then 1 else 0, gs.length, if retried then 0 else 1, rank env st)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.left
    have := hr.2; simp only [retainsTail, Bool.and_eq_true] at this
    simp [this.1.1.1.1.1]
  · apply Prod.Lex.left
    have := hr.2; simp only [retainsTail, Bool.and_eq_true] at this
    simp [this.1.1.1.1.1]
  · exact Prod.Lex.right _ (Prod.Lex.left _ _ (Nat.lt_succ_self _))
  · apply Prod.Lex.right; apply Prod.Lex.right
    have ne : isEmpty st = false := by
      cases e : isEmpty st
      · rfl
      · exact absurd (Or.inr e) h1
    cases m : mustRepeat h (nextColumn env st) st isHeader retried
    · simp only [Bool.or_false, ite_false, or_false]
      exact Prod.Lex.right _ (I4_nextColumn_rank env st (Or.inl ne))
    · have r : retried = false := by
        cases retried
        · rfl
        · simp [mustRepeat] at m
      subst r
      exact Prod.Lex.left _ _ (by simp)

theorem u_placeTableAcross (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    U S st (placeTableAcross env st h rows capt below) (h.map (·.id)) := by
  simp only [placeTableAcross]
  exact u_acrossGo env _ _ _ _ _ _ _ _

end

/-! ## Controls, rules and the flows -/

theorem u_checkNoBreak (st : St) : U S st (checkNoBreak st) [] := by
  unfold checkNoBreak
  split
  · exact U.refl st
  · simp only
    exact U.fr (U.ite (U.refl st) (U.addWs _ st))

theorem u_waitFor (u : Unmet) (k : Nat × Bool) (st : St) : U S st (waitFor u k st) [] := by
  unfold waitFor; split
  · exact U.frame
  · exact U.frame

section
variable (env : Env)

theorem u_placeKept {α : Type} (kp : Keep) (placeIn : St → Bool → List α → St)
    (T : List α → List Nat) (hT : ∀ a b, T (a ++ b) = T a ++ T b)
    (hp : ∀ s b xs, U S s (placeIn s b xs) (T xs))
    (st : St) (isStart : Bool) (ls : List α) (n : Need) :
    U S st (placeKept env kp placeIn st isStart ls n) (T ls) := by
  have tl : T (ls.take (ls.length - keptCut kp ls.length)) ++ T (ls.drop (ls.length - keptCut kp ls.length))
      = T ls := by rw [← hT, List.take_append_drop]
  simp only [placeKept]
  apply U.ite
  · exact hp _ _ _
  · apply U.ite
    · exact U.tr (hp _ _ _) (hp _ _ _) tl
    · apply U.ite
      · exact hp _ _ _
      · exact U.tr (hp _ _ _) (U.nl (u_nextColumn env _) (hp _ _ _)) tl

theorem u_putRuledLines (k2 : Nat) (ls : List Line) (st : St) :
    U S st (putRuledLines env k2 st ls) [] := by
  induction ls generalizing st with
  | nil => exact U.refl st
  | cons l ls ih =>
    simp only [putRuledLines]
    exact U.tr (u_putLineKeeping env _ st l) (ih _) rfl

theorem u_commitRuled (st : St) (body : RuledBody) (p : Plan) :
    U S st (commitRuled env st body p) [] := by
  cases body with
  | lines kp ls =>
    simp only [commitRuled]
    exact U.fr (U.fl (u_putRuledLines env p.after ls { st with used := st.used + p.before, join := none }))
  | heading r n ls =>
    simp only [commitRuled]
    exact U.fr (U.fr (U.fl (u_putBlock env { st with used := st.used + p.before, join := none } n ls)))

theorem u_splitRuled (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow) :
    U S st (splitRuled env st i b a body rest) [] := by
  have h0 : U S st (if isEmpty st = true then st else nextColumn env st) [] :=
    U.ite (U.refl st) (u_nextColumn env st)
  cases body with
  | lines kp ls => simp only [splitRuled]; exact U.nl h0 (u_placeLines env _ _ _ _)
  | heading r n ls =>
    simp only [splitRuled]
    generalize (if isEmpty st = true then st else nextColumn env st) = s at h0
    split
    · exact U.nl h0 (u_commitRuled env _ _ _)
    · split
      · exact U.nl h0 (u_commitRuled env _ _ _)
      · exact U.nl h0 (u_putBlock env _ n ls)

theorem u_flushJoin (st : St) : U S st (flushJoin env st) [] := by
  unfold flushJoin; split
  · exact U.refl st
  · exact U.frame

theorem u_placeRuledFresh (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow) :
    U S st (placeRuledFresh env st i b a body rest) [] := by
  have h1 : U S st (if body.recto = true then parityStart env odd st else st) [] :=
    U.ite (u_parityStart env _ _) (U.refl st)
  simp only [placeRuledFresh]
  generalize (if body.recto = true then parityStart env odd st else st) = s1 at h1
  have h2 : ∀ s2 : St, U S st s2 [] →
      U S st (match settleRuled env s2 i b a body rest none with
        | some placed => placed
        | none =>
          if isEmpty s2 = true then splitRuled env s2 i b a body rest
          else
            match settleRuled env (nextColumn env s2) i b a body rest none with
            | some placed => placed
            | none => splitRuled env (nextColumn env s2) i b a body rest) [] := by
    intro s2 e
    apply settle_or (fun r => U S st r [])
    · intro _ _ _; exact U.nl e (u_commitRuled env _ _ _)
    · split
      · exact U.nl e (u_splitRuled env _ _ _ _ _ _)
      · apply settle_or (fun r => U S st r [])
        · intro _ _ _; exact U.nl e (U.nl (u_nextColumn env _) (u_commitRuled env _ _ _))
        · exact U.nl e (U.nl (u_nextColumn env _) (u_splitRuled env _ _ _ _ _ _))
  apply h2
  cases body with
  | heading r n ls =>
    cases r <;> simp only [ruledKeep]
    · exact U.nl h1 (u_keep env _ _)
    · exact h1
  | lines kp ls =>
    simp only [ruledKeep]
    split
    · split
      · exact U.nl h1 (u_keep env _ _)
      · exact h1
    · exact h1

theorem u_placeRuled (st : St) (i : Nat) (b a j : Bool) (body : RuledBody) (rest : List Flow) :
    U S st (placeRuled env st i b a j body rest) [] := by
  unfold placeRuled
  split
  · apply joined_or (fun r => U S st r [])
    · intro _ _ _; exact u_commitRuled env _ _ _
    · unfold unjoined; split
      · exact U.nl (u_flushJoin env st) (U.nl (u_nextColumn env _) (u_placeRuledFresh env _ _ _ _ _ _))
      · exact U.nl (u_flushJoin env st) (u_placeRuledFresh env _ _ _ _ _ _)
  · exact u_placeRuledFresh env _ _ _ _ _ _

end

/-- A slot of one id the text leaves out. -/
theorem u_putUnlisted (st : St) (n : Nat) (sl : Slot) (i : Nat) (hs : Separator.slotIds sl = [i]) :
    U S st (putSlot st n sl) [i] := by
  intro x ⟨a, b, c⟩
  refine ⟨a, b.append (fun y m => ?_), c⟩
  cases m with
  | head =>
    intro _ j mj
    rw [hs] at mj
    cases mj with
    | head => exact x _ (List.Mem.head _)
    | tail _ m => cases m
  | tail _ m => cases m

/-- A figure sent on. -/
theorem u_defer (st : St) (d : Deferred) (i : Nat) (hd : Separator.slotIds (deferredFig d) = [i]) :
    U S st { st with deferred := st.deferred ++ [d] } [i] := by
  intro x ⟨a, b, c⟩
  refine ⟨a, b, fun e m => ?_⟩
  rcases mem_app2 m with m | m
  · exact c e m
  · cases m with
    | head =>
      intro _ j mj
      rw [hd] at mj
      cases mj with
      | head => exact x _ (List.Mem.head _)
      | tail _ m => cases m
    | tail _ m => cases m

theorem u_pageFigureU (env : Env) (st : St) (i : Nat) : U S st (pageFigure env st i) [i] :=
  fun x p => u_pageFigure env st i (x i (List.Mem.head _)) p

mutual
theorem u_place (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    U S st (place env st f rest) (flowUnl f) := by
  cases f with
  | paragraph kp ls => simp only [place, flowUnl]; exact u_placeLines env _ _ _ _
  | stanza kp vs => simp only [place, flowUnl]; exact u_placeStanza env _ _ _ _
  | ruled i b a j body => simp only [place, flowUnl]; exact u_placeRuled env _ _ _ _ _ _ _
  | wrapped i n beside =>
    simp only [place, flowUnl]
    have h : U S st (placeLines env defaultKeep (putSlot (keep env (flushFigures env st)
        (fun s => needIn env s ⟨max n beside.length, noteLinesOf beside⟩ ⟨0, 0⟩)) 0
        (.wrapped i)) false beside) [i] :=
      U.nl (U.nl (u_flushFigures env st) (u_keep env _ _)) (U.nr (u_putUnlisted _ 0 (.wrapped i) i rfl) (u_placeLines env _ _ _ _))
    exact U.ite (U.fr h) h
  | continued kp ls => simp only [place, flowUnl]; exact u_placeLines env _ _ _ _
  | heading recto n ls =>
    simp only [place, flowUnl]
    have h1 : U S st (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) [] :=
      U.ite (u_parityStart env _ _) (u_keep env _ _)
    generalize (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) = s1 at h1
    exact U.nl (U.ite h1 (U.nl h1 (u_nextColumn env _))) (u_putBlock env _ n ls)
  | figure i n =>
    simp only [place, flowUnl]
    exact U.ite (u_defer st (.figure i n) i rfl) (U.ite (u_putUnlisted st n (.figure i) i rfl) (u_defer st (.figure i n) i rfl))
  | pageFigure i =>
    simp only [place, flowUnl]
    exact U.ite (U.fl (u_pageFigureU env _ i)) (u_defer st (.pageFigure i) i rfl)
  | brk k => simp only [place, flowUnl]; exact U.frame
  | sectionStart sec k => simp only [place, flowUnl]; exact U.frame
  | space n => simp only [place, flowUnl]; exact u_placeSpaceFlow env _ _
  | needLines n => simp only [place, flowUnl]; exact U.refl st
  | blank n => simp only [place, flowUnl]; exact U.refl st
  | noBreak => simp only [place, flowUnl]; exact U.refl st
  | noBreakLines n => simp only [place, flowUnl]; exact U.refl st
  | keepNext n => simp only [place, flowUnl]; exact U.refl st
  | switchColumns n =>
    simp only [place, flowUnl]
    exact U.nl (u_flushDeferred env st) (U.ite (u_startSet env _ _ _) (U.fr (u_nextPage env (flushDeferred env st))))
  | restoreColumns =>
    simp only [place, flowUnl]
    exact U.ite (U.frame) (U.fr (u_nextPage env st))
  | adjustLines k => simp only [place, flowUnl]; exact U.refl st
  | bookPart u k r body => simp only [place, flowUnl]; exact u_runFlows env st body rest
  | boxed i kb ka body =>
    simp only [place, flowUnl]
    have h : U S st (runFlows env (openBox { keep env st (fun s => (kb : Int) + ka + needIn env s noNeed (env.nextNeed body))
        with box := some ⟨i, kb, ka, 0, false⟩ }) body rest) (sourceUnl body) :=
      U.nl (U.nl (u_keep env st _) (U.fl (U.oBox _))) (u_runFlows env _ body rest)
    exact U.nr (U.fr h) (u_drainPendingNotes env _)
  | code g c first cont ls => simp only [place, flowUnl]; exact u_placeCode env _ _ _ _ _ _ _
  | defTerm ls =>
    simp only [place, flowUnl]
    split
    · exact U.nl (u_keep env _ _) (u_placeLines env _ _ _ _)
    · exact u_placeLines env _ _ _ _
  | table sp0 h rows capt below =>
    simp only [place, flowUnl]
    split
    · refine U.nl ?_ (u_placeTable env _ _ _ _ _)
      apply U.ite
      · exact U.frame
      · exact U.nl (u_nextColumn env _) (u_keep env _ _)
    · refine U.nl ?_ (u_placeTableAcross env _ _ _ _ _)
      apply U.ite
      · exact U.frame
      · exact u_nextColumn env _
termination_by (flowWeight f, 0)
decreasing_by all_goals simp_wf; (try subst_vars); apply Prod.Lex.left; simp only [flowWeight]; omega

theorem u_placeFlow (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    U S st (placeFlow env st f rest) (flowUnl f) := by
  have pl : ∀ kp s b xs, U S s (placeLines env kp s b xs) ((fun _ => []) xs) :=
    fun kp s b xs => u_placeLines env kp s b xs
  unfold placeFlow
  split
  · simp only [flowUnl]; exact u_placeKept env _ _ _ (fun _ _ => rfl) (pl _) st true _ _
  · simp only [flowUnl]
    exact u_placeKept env _ _ (fun _ => [])
      (fun _ _ => rfl) (fun s b xs => u_placeStanza env _ s b xs) st true _ _
  · simp only [flowUnl]; exact u_placeKept env _ _ _ (fun _ _ => rfl) (pl _) st false _ _
  · simp only [flowUnl]
    exact U.nl (U.ite (U.refl st) (u_keep env _ _))
      (u_placeKept env _ _ _ (fun _ _ => rfl) (pl _) _ true _ _)
  · exact u_place env _ _ _
termination_by (flowWeight f, 1)
decreasing_by all_goals simp_wf; apply Prod.Lex.right; decide

theorem u_step (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    U S st (step env st f rest) (flowUnl f) := by
  have general : ∀ (a : Bool) (b : List (Nat × Int)), U S st ({ (if waitsBehind (applyBreaks env st) f
      then checkNoBreak (place env (applyBreaks env st) f rest)
      else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest))
      with seen := true, lastDeferred := a, spaces := b } : St) (flowUnl f) := by
    intro _ _
    have h : U S st (if waitsBehind (applyBreaks env st) f
      then checkNoBreak (place env (applyBreaks env st) f rest)
      else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest))
        (flowUnl f) := by
      apply U.ite
      · exact U.nl (u_applyBreaks env st) (U.nr (u_place env _ _ _) (u_checkNoBreak _))
      · exact U.nl (U.nl (u_applyBreaks env st) (U.nl (u_needBefore env _ _) (u_placeBlank env _ _ _)))
          (U.nr (u_placeFlow env _ _ _) (u_checkNoBreak _))
    exact U.fr h
  have ctl : ∀ (u : Unmet) (k : Nat × Bool), U S st (if st.seen = false ∨ st.lastDeferred = true then addUnmet u st
      else waitFor u k st) [] := fun u k => U.ite (U.addU u st) (u_waitFor u k st)
  cases f with
  | needLines n => simp only [step, flowUnl]; exact u_needMore env _ _
  | bookPart u k r body =>
    simp only [step, flowUnl]
    refine U.nl (b := if r = [] then st else applyBreaks env st) (U.ite (U.refl st) (u_applyBreaks env st)) ?_
    apply u_placeBookPart env
    · intro s; exact u_runFlows { env with keepParts := u, inBookPart := true } s body rest
    · intro s; have := u_runFlows { env with keepParts := u, inBookPart := true } s (flattenParts body) rest
      rw [sourceUnl_flatten] at this; exact this
  | adjustLines k =>
    simp only [step, flowUnl]
    refine U.nl (u_applyBreaks env st) (U.nr ?_ (u_drainPendingNotes env _))
    simp only [adjustLines]
    split
    · exact U.fl (U.addU _ _)
    · exact U.frame
  | noBreak => simp only [step, flowUnl]; exact ctl _ _
  | noBreakLines n =>
    cases n with
    | zero => simp only [step, flowUnl]; exact U.refl st
    | succ m => simp only [step, flowUnl]; exact ctl _ _
  | keepNext n => simp only [step, flowUnl]; exact ctl _ _
  | blank n =>
    simp only [step, flowUnl]
    exact U.ite (U.refl st) (U.frame)
  | brk k => simp only [step]; exact u_place env st (.brk k) rest
  | sectionStart sec k => simp only [step]; exact u_place env st (.sectionStart sec k) rest
  | space n =>
    simp only [step, flowUnl]
    exact U.nl (U.nl (u_applyBreaks env st) (u_needBeforeSpaces env _)) (u_placeSpace env _ _)
  | paragraph kp ls => simp only [step]; exact general _ _
  | continued kp ls => simp only [step]; exact general _ _
  | heading recto n ls => simp only [step]; exact general _ _
  | figure i n => simp only [step]; exact general _ _
  | pageFigure i => simp only [step]; exact general _ _
  | code g c first cont ls => simp only [step]; exact general _ _
  | defTerm ls => simp only [step]; exact general _ _
  | table sp0 h rows capt below => simp only [step]; exact general _ _
  | switchColumns n => simp only [step]; exact general _ _
  | restoreColumns => simp only [step]; exact general _ _
  | stanza kp vs => simp only [step]; exact general _ _
  | wrapped i n beside => simp only [step]; exact general _ _
  | ruled i b a j body => simp only [step]; exact general _ _
  | boxed i kb ka body => simp only [step]; exact general _ _
termination_by (flowWeight f, 2)
decreasing_by
  all_goals simp_wf
  all_goals try subst_vars
  all_goals first
    | (apply Prod.Lex.right; decide)
    | (apply Prod.Lex.left; simp only [flowWeight]; omega)
    | (apply Prod.Lex.left; have := flattenParts_weight body; simp only [flowWeight]; omega)

theorem u_runFlows (env : Env) (st : St) (fs : List Flow) (rest : List Flow) :
    U S st (runFlows env st fs rest) (sourceUnl fs) := by
  match fs with
  | [] => unfold runFlows; simp only [sourceUnl]; exact U.refl st
  | g :: more =>
    unfold runFlows
    exact U.tr (u_step env st g (more ++ rest)) (u_runFlows env _ more rest) (by simp [sourceUnl])
termination_by (flowsWeight fs, 3)
decreasing_by
  all_goals simp_wf
  all_goals apply Prod.Lex.left; simp only [flowsWeight]; omega
end

theorem u_placeAll (env : Env) (flows : List Flow) (st : St) :
    U S st (placeAll env st flows) (sourceUnl flows) ∧ (placeAll env st flows).pending = [] := by
  induction flows generalizing st with
  | nil =>
    simp only [placeAll, sourceUnl]
    have a : U S st (st.noBreak.foldl (fun s w => addUnmet w.1 s) st) [] := U.addWs st.noBreak st
    generalize st.noBreak.foldl (fun s w => addUnmet w.1 s) st = s1 at a
    refine ⟨?_, ?_⟩
    · split
      · exact U.nl (U.fr a) (u_flushDeferred env _)
      · split
        · exact U.nl (U.nl (U.fr a) (U.dropBlanks _ _)) (u_flushDeferred env _)
        · exact U.nl (U.nl (U.nl (U.fr a) (u_nextColumn env _)) (U.dropBlanks _ _))
            (u_flushDeferred env _)
    · repeat' split
      all_goals exact flushDeferred_pending env _
  | cons f rest ih =>
    simp only [placeAll]
    obtain ⟨a, b⟩ := ih (step env st f rest)
    exact ⟨U.tr (u_step env st f rest) a (by simp [sourceUnl]), b⟩

/-! ## The premise of the separators: no slot the text leaves out holds their lines -/

/-- `P` for a wider list. -/
theorem P.wk {T S : List Nat} {st : St} (h : P T st) (e : ∀ j ∈ T, j ∈ S) : P S st :=
  ⟨fun p m x mx u j mj => e j (h.1 p m x mx u j mj), fun x mx u j mj => e j (h.2.1 x mx u j mj),
    fun d m u j mj => e j (h.2.2 d m u j mj)⟩

theorem mem_reverse2 {α : Type} {x : α} {l : List α} (h : x ∈ l.reverse) : x ∈ l := by
  induction l with
  | nil => cases h
  | cons y ys ih =>
    rw [List.reverse_cons] at h
    rcases mem_app2 h with m | m
    · exact List.mem_cons_of_mem _ (ih m)
    · cases m with
      | head => exact List.Mem.head _
      | tail _ m => cases m

/-- The slots the text leaves out on the pages of `placeAll` hold ids of
    the slots the text leaves out before it (`T`) or of the flows
    (`sourceUnl`) only. -/
theorem unlisted_of (env : Env) (st : St) (flows : List Flow) (T : List Nat) (hst : P T st) :
    ∀ q ∈ (closePage env (placeAll env st flows)).done.reverse, ∀ s ∈ q.slots, unlisted s.2 = true →
      ∀ j ∈ Separator.slotIds s.2, j ∈ T ++ sourceUnl flows := by
  have p0 : P (T ++ sourceUnl flows) st := hst.wk (fun j m => List.mem_append_of_mem_left _ m)
  have hx : ∀ j ∈ sourceUnl flows, j ∈ T ++ sourceUnl flows := fun j m => List.mem_append_of_mem_right _ m
  have p1 := (u_placeAll env flows st).1 hx p0
  have p2 := u_closePage (S := T ++ sourceUnl flows) env _ (fun _ m => (by cases m)) p1
  intro q mq s ms u j mj
  exact p2.1 q (mem_reverse2 mq) s ms u j mj

/-- The premise `hn` of the theorems on G07134 of Separator.lean, from
    ids that the slots the text leaves out before the flows do not hold
    and that the flows do not add. -/
theorem hn_of (env : Env) (st : St) (flows : List Flow) (T : List Nat) (hst : P T st) (ids : List Nat)
    (h : ∀ i ∈ ids, i ∉ T ∧ i ∉ sourceUnl flows) :
    ∀ i ∈ ids, ∀ q ∈ (closePage env (placeAll env st flows)).done.reverse,
      ∀ s ∈ q.slots, unlisted s.2 = true → i ∉ Separator.slotIds s.2 := by
  intro i mi q mq s ms u m
  rcases mem_app2 (unlisted_of env st flows T hst q mq s ms u i m) with e | e
  · exact (h i mi).1 e
  · exact (h i mi).2 e

mutual
/-- The ids of the figures, turned figures and wrapped figures written. -/
def flowFigIds : Flow → List Nat
  | .figure i _ => [i]
  | .pageFigure i => [i]
  | .wrapped i _ _ => [i]
  | .bookPart _ _ _ body | .boxed _ _ _ body => sourceFigIds body
  | _ => []
termination_by f => sizeOf f
def sourceFigIds : List Flow → List Nat
  | [] => []
  | g :: r => flowFigIds g ++ sourceFigIds r
termination_by fs => sizeOf fs
end

mutual
/-- An id a flow adds is that of a figure, or of a header line of a
    table, which is a line of the text written. -/
theorem flowUnl_split (f : Flow) (j : Nat) (h : j ∈ flowUnl f) :
    j ∈ flowFigIds f ∨ j ∈ (flowText f).bind Separator.slotIds := by
  match f with
  | .figure i _ => left; simpa [flowUnl, flowFigIds] using h
  | .pageFigure i => left; simpa [flowUnl, flowFigIds] using h
  | .wrapped i _ _ => left; simpa [flowUnl, flowFigIds] using h
  | .table _ hd rows capt below =>
    right
    simp only [flowUnl] at h
    simp only [flowText, tableLines, List.map_append, List.append_bind]
    have : j ∈ (hd.map (fun l => Slot.line l.id)).bind Separator.slotIds := by
      clear rows capt below
      induction hd with
      | nil => cases h
      | cons l ls ih =>
        simp only [List.map, List.cons_bind] at h ⊢
        cases h with
        | head => exact List.Mem.head _
        | tail _ m => exact List.mem_cons_of_mem _ (ih m)
    exact List.mem_append_of_mem_left _ (List.mem_append_of_mem_left _ (List.mem_append_of_mem_right _ this))
  | .bookPart _ _ _ body =>
    simp only [flowUnl, flowFigIds, flowText] at h ⊢
    exact sourceUnl_split body j h
  | .boxed _ _ _ body =>
    simp only [flowUnl, flowFigIds, flowText] at h ⊢
    exact sourceUnl_split body j h
  | .paragraph _ _ | .continued _ _ | .ruled _ _ _ _ _ | .heading _ _ _ | .defTerm _ | .stanza _ _ | .code _ _ _ _ _
  | .brk _ | .sectionStart _ _ | .space _ | .needLines _ | .blank _ | .noBreak | .noBreakLines _ | .keepNext _ _
  | .switchColumns _ | .restoreColumns | .adjustLines _ => simp [flowUnl] at h
termination_by sizeOf f
theorem sourceUnl_split (fs : List Flow) (j : Nat) (h : j ∈ sourceUnl fs) :
    j ∈ sourceFigIds fs ∨ j ∈ (sourceText fs).bind Separator.slotIds := by
  match fs with
  | [] => cases h
  | g :: r =>
    simp only [sourceUnl] at h
    simp only [sourceFigIds, sourceText, List.append_bind]
    rcases mem_app2 h with m | m
    · rcases flowUnl_split g j m with e | e
      · exact Or.inl (List.mem_append_of_mem_left _ e)
      · exact Or.inr (List.mem_append_of_mem_left _ e)
    · rcases sourceUnl_split r j m with e | e
      · exact Or.inl (List.mem_append_of_mem_right _ e)
      · exact Or.inr (List.mem_append_of_mem_right _ e)
termination_by sizeOf fs
end

open Separator (Uniq uniq_append Link linkFlows chainFlows gapFlows)

/-- An id of the text of the flows before `rest` is not an id of the text
    of `rest`, when the ids are unique. -/
theorem not_in_rest (st : St) (pre rest : List Flow) (i : Nat)
    (hd : Uniq ((text st ++ sourceText (pre ++ rest)).bind Separator.slotIds)) (hi : i ∈ (sourceText pre).bind Separator.slotIds) :
    i ∉ (sourceText rest).bind Separator.slotIds := by
  rw [sourceText_append, List.append_bind, List.append_bind] at hd
  exact (uniq_append (uniq_append hd).2).1 i hi

/-- Such an id is not added by the flows either, unless it is that of a
    figure after `pre`. -/
theorem not_unl (st : St) (pre rest : List Flow) (i : Nat)
    (hd : Uniq ((text st ++ sourceText (pre ++ rest)).bind Separator.slotIds)) (hi : i ∈ (sourceText pre).bind Separator.slotIds)
    (hpre : sourceUnl pre = []) (hfig : i ∉ sourceFigIds rest) : i ∉ sourceUnl (pre ++ rest) := by
  rw [sourceUnl_append, hpre, List.nil_append]
  intro m
  rcases sourceUnl_split rest i m with e | e
  · exact hfig e
  · exact not_in_rest st pre rest i hd hi e

theorem sourceUnl_chain : ∀ (ks : List Link), sourceUnl (chainFlows ks) = []
  | [] => rfl
  | k :: ks => by
    simp only [chainFlows, linkFlows, sourceUnl_append, sourceUnl_chain ks]
    cases k.gap <;> simp [sourceUnl, flowUnl, gapFlows]

theorem chain_text (i : Nat) : ∀ (ks : List Link), i ∈ ks.map (·.line.id) →
    i ∈ (sourceText (chainFlows ks)).bind Separator.slotIds
  | [], h => by cases h
  | k :: ks, h => by
    simp only [chainFlows, sourceText_append, List.append_bind]
    cases h with
    | head => apply List.mem_append_of_mem_left; cases k.gap <;> simp [linkFlows, gapFlows, sourceText, flowText, Separator.slotIds]
    | tail _ m => exact List.mem_append_of_mem_right _ (chain_text i ks m)

/-- `I3_separator_hold_no_error` with its premise on the slots the text
    leaves out discharged: the slots of `st` the text leaves out hold ids
    of `T` only, which are not the ids of the two lines, and the flows
    after the paragraph have no figure of the ids of the two lines
    (golem-typeset numbers lines and figures by one counter, `nuNext` of
    Flow.hs).  The header lines a table repeats are lines of the text
    after the paragraph, so `hd` keeps them apart. -/
theorem I3_separator_hold_no_error_ids (env : Env) (hs : 0 ≤ env.separator) (hfit : Separator.PlainFitting env)
    (st : St) (c : Separator.Clear st) (hw : heldHere env st = false)
    (kp kq : Keep) (l l0 : Line) (ls : List Line) (gap : Option Nat) (rest : List Flow) (n p sp : Nat)
    (hl : ∀ x ∈ l :: l0 :: ls, x.notes = []) (hlast : 1 ≤ kp.last)
    (hkept : env.keptNeed (.keepNext 1 sp :: (gapFlows gap ++ .paragraph kq (l0 :: ls) :: rest)) = some ⟨n, 0⟩)
    (hsp : env.held sp = true)
    (hfront : env.keptNeed rest = none ∨
      ((l0 :: ls).length - keptCut (previousKeep env rest kq) (l0 :: ls).length ≤ p ∨
        splitAtBreak kq true ((l0 :: ls).length - keptCut (previousKeep env rest kq) (l0 :: ls).length) p = p))
    (hhold : 1 + (n : Int) ≤ env.capacity)
    (hp : 1 ≤ p) (hpn : p + Separator.gapLines gap ≤ n)
    (hpart : (l0 :: ls).length ≤ p ∨ splitAtBreak kq true (l0 :: ls).length p = p)
    (hf : Notes.Fresh st (Notes.sourceNotes rest))
    (b a : Nat) (kp' : Keep) (mids : List Separator.Unit) (hm : ∀ m ∈ mids, Separator.passes m = true)
    (fs : List Flow)
    (hd : Uniq ((text st ++ sourceText (.paragraph kp [l] :: .keepNext 1 sp :: (gapFlows gap ++ .paragraph kq (l0 :: ls) :: rest))).bind
      Separator.slotIds))
    (T : List Nat) (hst : P T st) (hT : l.id ∉ T ∧ l0.id ∉ T) (hfig : l.id ∉ sourceFigIds rest ∧ l0.id ∉ sourceFigIds rest) :
    0 ∉ Separator.holdErrors (.separator b a kp' l :: mids ++ [.other .block fs (some l0.id)])
      (closePage env (placeAll env st
        (.paragraph kp [l] :: .keepNext 1 sp :: (gapFlows gap ++ .paragraph kq (l0 :: ls) :: rest)))).done.reverse := by
  have e : (.paragraph kp [l] :: .keepNext 1 sp :: (gapFlows gap ++ .paragraph kq (l0 :: ls) :: rest) : List Flow) =
      (.paragraph kp [l] :: .keepNext 1 sp :: (gapFlows gap ++ [.paragraph kq (l0 :: ls)])) ++ rest := by simp
  have hpre : sourceUnl (.paragraph kp [l] :: .keepNext 1 sp :: (gapFlows gap ++ [.paragraph kq (l0 :: ls)])) = [] := by
    cases gap <;> simp [sourceUnl, flowUnl, gapFlows]
  have hi : ∀ i ∈ [l.id, l0.id], i ∈ (sourceText (.paragraph kp [l] :: .keepNext 1 sp ::
      (gapFlows gap ++ [.paragraph kq (l0 :: ls)]))).bind Separator.slotIds := by
    intro i mi
    cases gap <;> simp [gapFlows, sourceText, flowText, Separator.slotIds] at mi ⊢ <;> rcases mi with m | m <;> simp [m]
  refine Separator.I3_separator_hold_no_error env hs hfit st c hw kp kq l l0 ls gap rest n p sp hl hlast hkept hsp
    hfront hhold hp hpn hpart hf b a kp' mids hm fs hd ?_
  refine hn_of env st _ T hst _ (fun i mi => ⟨?_, ?_⟩)
  · cases mi with
    | head => exact hT.1
    | tail _ m => cases m with
      | head => exact hT.2
      | tail _ m => cases m
  · rw [e] at hd ⊢
    refine not_unl st _ rest i hd (hi i mi) hpre ?_
    cases mi with
    | head => exact hfig.1
    | tail _ m => cases m with
      | head => exact hfig.2
      | tail _ m => cases m

/-- `I3_separator_chain_no_error` with its premise on the slots the text
    leaves out discharged, as `I3_separator_hold_no_error_ids`: for the
    lines of the separators of the chain and the first line of the
    paragraph. -/
theorem I3_separator_chain_no_error_ids (env : Env) (hs : 0 ≤ env.separator) (hfit : Separator.PlainFitting env)
    (st : St) (c : Separator.Clear st) (hw : heldHere env st = false)
    (k1 : Link) (ks : List Link) (kq : Keep) (l0 : Line) (ls : List Line) (rest : List Flow) (n p : Nat)
    (hk : ∀ k ∈ k1 :: ks, k.line.notes = [] ∧ 1 ≤ k.kp.last ∧ env.held k.sp = true)
    (hb : ∀ x ∈ l0 :: ls, x.notes = [])
    (hkept : env.keptNeed (.keepNext 1 k1.sp :: (gapFlows k1.gap ++ (chainFlows ks ++ .paragraph kq (l0 :: ls) :: rest)))
      = some ⟨n, 0⟩)
    (hfront : env.keptNeed rest = none ∨
      ((l0 :: ls).length - keptCut (previousKeep env rest kq) (l0 :: ls).length ≤ p ∨
        splitAtBreak kq true ((l0 :: ls).length - keptCut (previousKeep env rest kq) (l0 :: ls).length) p = p))
    (hhold : 1 + (n : Int) ≤ env.capacity)
    (hp : 1 ≤ p) (hpn : p + Separator.gapLines k1.gap + Separator.chainLines ks ≤ n)
    (hpart : (l0 :: ls).length ≤ p ∨ splitAtBreak kq true (l0 :: ls).length p = p)
    (hf : Notes.Fresh st (Notes.sourceNotes rest))
    (us : List ((Nat × Nat × Keep × Line) × List Separator.Unit)) (hus : us.map (·.1.2.2.2.id) = (k1 :: ks).map (·.line.id))
    (hm : ∀ y ∈ us, ∀ m ∈ y.2, Separator.passes m = true) (fs : List Flow)
    (hd : Uniq ((text st ++ sourceText (chainFlows (k1 :: ks) ++ .paragraph kq (l0 :: ls) :: rest)).bind Separator.slotIds))
    (T : List Nat) (hst : P T st)
    (hids : ∀ i ∈ (k1 :: ks).map (·.line.id) ++ [l0.id], i ∉ T ∧ i ∉ sourceFigIds rest) :
    0 ∉ Separator.holdErrors (Separator.sepUnits us ++ [.other .block fs (some l0.id)])
      (closePage env (placeAll env st (chainFlows (k1 :: ks) ++ .paragraph kq (l0 :: ls) :: rest))).done.reverse := by
  have e : chainFlows (k1 :: ks) ++ .paragraph kq (l0 :: ls) :: rest =
      (chainFlows (k1 :: ks) ++ [.paragraph kq (l0 :: ls)]) ++ rest := by simp
  have hpre : sourceUnl (chainFlows (k1 :: ks) ++ [.paragraph kq (l0 :: ls)]) = [] := by
    rw [sourceUnl_append, sourceUnl_chain]; simp [sourceUnl, flowUnl]
  have hi : ∀ i ∈ (k1 :: ks).map (·.line.id) ++ [l0.id],
      i ∈ (sourceText (chainFlows (k1 :: ks) ++ [.paragraph kq (l0 :: ls)])).bind Separator.slotIds := by
    intro i mi
    rw [sourceText_append, List.append_bind]
    rcases mem_app2 mi with m | m
    · exact List.mem_append_of_mem_left _ (chain_text i _ m)
    · apply List.mem_append_of_mem_right
      cases m with
      | head => simp [sourceText, flowText, Separator.slotIds]
      | tail _ m => cases m
  refine Separator.I3_separator_chain_no_error env hs hfit st c hw k1 ks kq l0 ls rest n p hk hb hkept hfront hhold
    hp hpn hpart hf us hus hm fs hd ?_
  refine hn_of env st _ T hst _ (fun i mi => ⟨(hids i mi).1, ?_⟩)
  rw [e] at hd ⊢
  exact not_unl st _ rest i hd (hi i mi) hpre (hids i mi).2

end Slots
end WholePagination
