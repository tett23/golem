/-
Root ADR 0444 I1 on the grid mode of Whole.lean.

The note lines of the pages, of the current column and carried on to the
next column, in this order, are the lines of the notes read, in the
manuscript's order, but for the notes reported unplaceable: no line of a
later note comes before a line of an earlier one (`I1_paginate_order`).
The statement holds of the flows `plainFlows` admits: no box, no switch
of the columns, and headings of one grid line or more.  A box breaks it:
its grid lines after are given back when it ends in a column where its
part has no line, and a later note then takes them while an earlier one
is still carried on (README.md).
-/
import WholeNotes

namespace WholePagination
namespace Order
open Notes

/-! ## The notes reported unplaceable -/

def dropId : Unmet → Option Nat
  | .unplaceableFootnote i _ => some i
  | _ => none

def dropsOf : List Unmet → List Nat
  | [] => []
  | u :: us => match dropId u with
    | some i => i :: dropsOf us
    | none => dropsOf us

theorem dropsOf_append (a b : List Unmet) : dropsOf (a ++ b) = dropsOf a ++ dropsOf b := by
  induction a with
  | nil => rfl
  | cons u us ih => simp only [List.cons_append, dropsOf]; split <;> simp [ih]

def dropIds (st : St) : List Nat := dropsOf (allUnmet st)

/-- The lines of the notes not in `D`. -/
def kd (D : List Nat) (a : List (Nat × Nat)) : List (Nat × Nat) := a.filter (fun x => !decide (x.1 ∈ D))

theorem kd_append (D : List Nat) (a b : List (Nat × Nat)) : kd D (a ++ b) = kd D a ++ kd D b := by
  induction a with
  | nil => rfl
  | cons x xs ih =>
    simp only [kd, List.cons_append, List.filter] at *
    split <;> simp [ih]

theorem kd_kd {D E : List Nat} (h : ∀ i, i ∈ D → i ∈ E) (a : List (Nat × Nat)) : kd E (kd D a) = kd E a := by
  induction a with
  | nil => rfl
  | cons x xs ih =>
    simp only [kd, List.filter] at *
    by_cases e : x.1 ∈ E
    · by_cases d : x.1 ∈ D
      · simp [d, e, ih]
      · simp [d, e, ih]
    · have nd : x.1 ∉ D := fun m => e (h _ m)
      simp [nd, e, ih]

/-- The pages closed and the controls not met only grow. -/
def G (st s : St) : Prop := ∃ u, allUnmet s = allUnmet st ++ u

theorem G.refl (st : St) : G st st := ⟨[], by simp⟩

theorem G.trans {a b c : St} (h1 : G a b) (h2 : G b c) : G a c := by
  obtain ⟨u, e⟩ := h1; obtain ⟨v, f⟩ := h2
  exact ⟨u ++ v, by rw [f, e, List.append_assoc]⟩

theorem G.sub {a b : St} (h : G a b) : ∀ i, i ∈ dropIds a → i ∈ dropIds b := by
  obtain ⟨u, e⟩ := h
  intro i m
  simp only [dropIds, e, dropsOf_append]
  exact List.mem_append_of_mem_left _ m

/-- From `st` to `s` the note lines `Y` are added after what `st` holds,
    in this order, but for the notes reported unplaceable. -/
def OR (st s : St) (Y : List (Nat × Nat)) : Prop :=
  G st s ∧ kd (dropIds s) (NM s) = kd (dropIds s) (NM st ++ Y)

theorem OR.refl (st : St) : OR st st [] := ⟨G.refl st, by simp⟩

theorem OR.trans {a b c : St} {Y1 Y2 : List (Nat × Nat)} (h1 : OR a b Y1) (h2 : OR b c Y2) :
    OR a c (Y1 ++ Y2) := by
  obtain ⟨g1, e1⟩ := h1; obtain ⟨g2, e2⟩ := h2
  refine ⟨g1.trans g2, ?_⟩
  rw [e2, kd_append, ← kd_kd g2.sub (NM b), e1, kd_kd g2.sub, ← kd_append, List.append_assoc]

theorem OR.of_eq {st s : St} {Y : List (Nat × Nat)} (h : NM s = NM st ++ Y) (g : G st s) : OR st s Y :=
  ⟨g, by rw [h]⟩

/-! ## The state kept: no box, the first line of the set at 0 or below,
    and the room of the column when a note is carried on -/

structure Base (st : St) : Prop where
  box : st.box = none
  first : 0 ≤ st.firstLine
  /-- The spaces placed in the column took 0 lines or more. -/
  spaces : ∀ x ∈ st.spaces, 0 ≤ x.2
  /-- No set of columns was started: no grid line is kept for the notes
      above it, nor changed for its columns. -/
  setAdj : st.setAdjust = 0
  res : st.reserved = 0
  nl : 0 ≤ st.noteLines

syntax "le_tac" : tactic
macro_rules
  | `(tactic| le_tac) => `(tactic| first | exact Int.le_refl _ | omega)

theorem Base.of {st s : St} (b : Base st) (hb : s.box = st.box := by rfl) (hf : s.firstLine = st.firstLine := by rfl)
    (hsp : s.spaces = st.spaces := by rfl) (hsa : s.setAdjust = st.setAdjust := by rfl)
    (hr : s.reserved = st.reserved := by rfl) (hl : st.noteLines ≤ s.noteLines := by le_tac) :
    Base s :=
  ⟨hb ▸ b.box, hf ▸ b.first, hsp ▸ b.spaces, hsa ▸ b.setAdj, hr ▸ b.res, by have := b.nl; omega⟩

/-- The lines of the parts. -/
theorem ex_length (ps : List NotePart) : (ex ps).length = partsLines ps := by
  induction ps with
  | nil => rfl
  | cons p ps ih =>
    obtain ⟨i, f, n⟩ := p
    have : ∀ f n, (seg i f n).length = n := by
      intro f n
      induction n generalizing f with
      | zero => rfl
      | succ n ih' => simp [seg, ih']
    simp [ex_cons, partLines, this, ih, partsLines]

theorem ex_nil_of {ps : List NotePart} (h : partsLines ps = 0) : ex ps = [] := by
  have := ex_length ps; rw [h] at this; exact List.eq_nil_of_length_eq_zero this

/-- The column holds a line, a note line or a note part. -/
def Touched (st : St) : Prop := 1 ≤ st.used ∨ 0 < st.noteLines ∨ st.notes ≠ []

/-- The column has a grid line or more, the lines used are negative only
    below note lines, and when a note is carried on, the column holds
    something and has at most `k` lines free beyond the separator a new
    note would take. -/
def OkK (env : Env) (k : Int) (st : St) : Prop :=
  1 ≤ cap env st ∧ (0 ≤ st.used ∨ 0 < st.noteLines) ∧
    (partsLines st.pending = 0 ∨ (free env st ≤ carrySep env st + k ∧ Touched st))

abbrev Ok (env : Env) (st : St) : Prop := OkK env 1 st

theorem OkK.mono {env : Env} {k k' : Int} {st : St} (h : OkK env k st) (le : k ≤ k') : OkK env k' st := by
  obtain ⟨h1, h2, h | ⟨h, t⟩⟩ := h
  · exact ⟨h1, h2, Or.inl h⟩
  · exact ⟨h1, h2, Or.inr ⟨by omega, t⟩⟩

/-- Each step: from a state kept, the notes `X` read are added in order
    and the state is kept. -/
def Q (env : Env) (st s : St) (X : List Note) : Prop :=
  Base st → Ok env st → OR st s (exN X) ∧ Base s ∧ Ok env s

theorem Q.refl (env : Env) (st : St) : Q env st st [] := fun b o => ⟨OR.refl st, b, o⟩

theorem Q.trans {env : Env} {a b c : St} {X1 X2 : List Note} (h1 : Q env a b X1) (h2 : Q env b c X2) :
    Q env a c (X1 ++ X2) := by
  intro ba oa
  obtain ⟨r1, bb, ob⟩ := h1 ba oa
  obtain ⟨r2, bc, oc⟩ := h2 bb ob
  refine ⟨?_, bc, oc⟩
  rw [exN_append]; exact r1.trans r2

theorem Q.tr {env : Env} {a b c : St} {X1 X2 X : List Note} (h1 : Q env a b X1) (h2 : Q env b c X2)
    (e : X1 ++ X2 = X) : Q env a c X := e ▸ h1.trans h2

theorem Q.nl {env : Env} {a b c : St} {X : List Note} (h1 : Q env a b []) (h2 : Q env b c X) : Q env a c X :=
  Q.tr h1 h2 (List.nil_append _)

theorem Q.nr {env : Env} {a b c : St} {X : List Note} (h1 : Q env a b X) (h2 : Q env b c []) : Q env a c X :=
  Q.tr h1 h2 (List.append_nil _)

theorem Q.ite {env : Env} {c : Prop} [Decidable c] {st a b : St} {X : List Note} (ha : Q env st a X)
    (hb : Q env st b X) : Q env st (if c then a else b) X := by
  split
  · exact ha
  · exact hb

theorem Q.dite {env : Env} {c : Prop} [Decidable c] {st : St} {a : c → St} {b : ¬ c → St} {X : List Note}
    (ha : ∀ h, Q env st (a h) X) (hb : ∀ h, Q env st (b h) X) : Q env st (if h : c then a h else b h) X := by
  split
  · exact ha _
  · exact hb _

theorem Q.congr {env : Env} {st s : St} {X X' : List Note} (e : X = X') (h : Q env st s X) : Q env st s X' := e ▸ h

/-- The lines used do not decrease. -/
syntax "used_le" : tactic
macro_rules
  | `(tactic| used_le) => `(tactic| le_tac)

/-- A step that keeps the notes, the box, the first line, the spaces and
    the note lines, and does not free lines. -/
theorem Q.frame {env : Env} {st s : St} (hd : s.done = st.done := by rfl) (hn : s.notes = st.notes := by rfl)
    (hp : s.pending = st.pending := by rfl) (hu : s.unmet = st.unmet := by rfl) (hb : s.box = st.box := by rfl)
    (hf : s.firstLine = st.firstLine := by rfl) (hsp : s.spaces = st.spaces := by rfl)
    (hl : s.noteLines = st.noteLines := by rfl) (ha : s.adjust = st.adjust := by rfl)
    (hsa : s.setAdjust = st.setAdjust := by rfl) (hr : s.reserved = st.reserved := by rfl)
    (hused : st.used ≤ s.used := by used_le) :
    Q env st s [] := by
  intro ba oa
  refine ⟨OR.of_eq (by simp [NM, hd, hn, hp]) ⟨[], by simp [allUnmet, hd, hu]⟩, ba.of hb hf hsp hsa hr (by omega), ?_⟩
  have c : carrySep env s = carrySep env st := by simp only [carrySep, hl]
  have cp : cap env s = cap env st := by simp only [cap, boxAfter, ha, hb]
  obtain ⟨o1, o2, o | ⟨o, t⟩⟩ := oa
  · exact ⟨by omega, by omega, Or.inl (by rw [hp]; exact o)⟩
  · refine ⟨by omega, by omega, Or.inr ⟨?_, ?_⟩⟩
    · simp only [free, c, cp] at o ⊢; omega
    · rcases t with t | t | t
      · exact Or.inl (by omega)
      · exact Or.inr (Or.inl (by omega))
      · exact Or.inr (Or.inr (by rw [hn]; exact t))

theorem Q.addU (env : Env) (u : Unmet) (st : St) : Q env st (addUnmet u st) [] := by
  intro ba oa
  exact ⟨OR.of_eq (by simp [NM, addUnmet]) ⟨[u], by simp [allUnmet, addUnmet, List.append_assoc]⟩, ba.of, oa⟩

theorem Q.addUs (env : Env) (us : List Unmet) (st : St) : Q env st (us.foldl (fun s u => addUnmet u s) st) [] := by
  induction us generalizing st with
  | nil => exact Q.refl env st
  | cons u us ih => simp only [List.foldl]; exact Q.nl (Q.addU env u st) (ih _)

theorem Q.addWs (env : Env) (ws : List (Unmet × Nat × Nat × Nat × (Nat × Bool))) (st : St) :
    Q env st (ws.foldl (fun s w => addUnmet w.1 s) st) [] := by
  induction ws generalizing st with
  | nil => exact Q.refl env st
  | cons w ws ih => simp only [List.foldl]; exact Q.nl (Q.addU env _ st) (ih _)

theorem Q.dropBlanks (env : Env) (ns : List Nat) (st : St) :
    Q env st (ns.foldl (fun s _ => addUnmet .droppedBlank s) st) [] := by
  induction ns generalizing st with
  | nil => exact Q.refl env st
  | cons n ns ih => simp only [List.foldl]; exact Q.nl (Q.addU env _ st) (ih _)

/-! ## Going on to the next column -/

theorem kd_seg_mem {D : List Nat} {i : Nat} (h : i ∈ D) (f n : Nat) : kd D (seg i f n) = [] := by
  induction n generalizing f with
  | zero => rfl
  | succ n ih => simp only [seg, kd, List.filter] at *; simp [h, ih]

theorem carryNote_ord (env : Env) (hs : 0 ≤ env.separator) (s : St) (p : NotePart) (hj : J env s) :
    OR s (carryNote env s p) (partLines p) ∧ J env (carryNote env s p) := by
  refine ⟨?_, (carryNote_step env hs s p hj).2⟩
  obtain ⟨i, f, n⟩ := p
  simp only [carryNote]
  split
  · refine ⟨⟨[Unmet.unplaceableFootnote i (cap env s)], by simp [allUnmet, addUnmet, List.append_assoc]⟩, ?_⟩
    have m : i ∈ dropIds (addUnmet (.unplaceableFootnote i (cap env s)) s) := by
      simp only [dropIds, allUnmet, addUnmet, ← List.append_assoc, dropsOf_append, dropsOf, dropId]
      exact List.mem_append_of_mem_right _ (List.Mem.head _)
    show kd _ (NM s) = kd _ (NM s ++ seg i f n)
    rw [kd_append, kd_seg_mem m, List.append_nil]
  · have shl : carryShown env s n ≤ n := Nat.min_le_left _ _
    have shr : carryShown env s n ≤ (carryRoom env s).toNat := Nat.min_le_right _ _
    generalize carryShown env s n = sh at *
    have room0 : carryRoom env s = 0 → sh = 0 := by intro c; rw [c] at shr; simpa using shr
    rcases hj with hp | hr
    · refine OR.of_eq ?_ ⟨[], by simp [allUnmet]⟩
      simp only [NM, hp, ex_append, ex_nil, List.append_nil, ex_cons, partLines, List.nil_append]
      split
      · have e : n = sh + (n - sh) := by omega
        conv => rhs; rw [e, seg_add]
        simp [ex_cons, partLines, List.append_assoc]
      · have e : sh = n := by omega
        simp [e, List.append_assoc]
    · have sh0 := room0 hr
      subst sh0
      refine OR.of_eq ?_ ⟨[], by simp [allUnmet]⟩
      simp only [NM, ex_append, ex_cons, ex_nil, partLines, seg, List.append_nil, List.append_assoc]
      split
      · simp [ex_cons, partLines]
      · have : n = 0 := by omega
        subst this; simp [seg]

theorem carryAll_ord (env : Env) (hs : 0 ≤ env.separator) (ps : List NotePart) (s : St) (hj : J env s) :
    OR s (ps.foldl (carryNote env) s) (ex ps) ∧ J env (ps.foldl (carryNote env) s) := by
  induction ps generalizing s with
  | nil => exact ⟨OR.refl s, hj⟩
  | cons p ps ih =>
    simp only [List.foldl]
    obtain ⟨a, b⟩ := carryNote_ord env hs s p hj
    obtain ⟨c, d⟩ := ih _ b
    exact ⟨a.trans c, d⟩

theorem carryAll_fields (env : Env) (ps : List NotePart) (s : St) :
    (ps.foldl (carryNote env) s).box = s.box ∧ (ps.foldl (carryNote env) s).used = s.used ∧
      (ps.foldl (carryNote env) s).firstLine = s.firstLine ∧ (ps.foldl (carryNote env) s).adjust = s.adjust ∧
      (ps.foldl (carryNote env) s).spaces = s.spaces := by
  induction ps generalizing s with
  | nil => exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  | cons p ps ih =>
    simp only [List.foldl]
    obtain ⟨a, b, c, d, f⟩ := ih (carryNote env s p)
    have e : (carryNote env s p).box = s.box ∧ (carryNote env s p).used = s.used ∧
        (carryNote env s p).firstLine = s.firstLine ∧ (carryNote env s p).adjust = s.adjust ∧
        (carryNote env s p).spaces = s.spaces := by
      simp only [carryNote, addUnmet]; split <;> exact ⟨rfl, rfl, rfl, rfl, rfl⟩
    exact ⟨a.trans e.1, b.trans e.2.1, c.trans e.2.2.1, d.trans e.2.2.2.1, f.trans e.2.2.2.2⟩

theorem pageFigures_box (env : Env) (ts : List Nat) (st : St) :
    (ts.foldl (pageFigure env) st).box = st.box ∧ (ts.foldl (pageFigure env) st).spaces = st.spaces := by
  induction ts generalizing st with
  | nil => exact ⟨rfl, rfl⟩
  | cons t _ ih => exact ih (pageFigure env st t)

theorem placeDeferred_fields (env : Env) (ws : List Deferred) (st : St) :
    (placeDeferred env st ws).box = st.box ∧ (placeDeferred env st ws).firstLine = st.firstLine ∧
      (placeDeferred env st ws).noteLines = st.noteLines ∧ st.used ≤ (placeDeferred env st ws).used ∧
      (placeDeferred env st ws).spaces = st.spaces := by
  induction ws generalizing st with
  | nil => exact ⟨rfl, rfl, rfl, Int.le_refl _, rfl⟩
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · obtain ⟨a, b, c, d, e⟩ := ih (putSlot st n (.figure i))
        refine ⟨a, b, c, ?_, e⟩
        have : st.used ≤ (putSlot st n (.figure i)).used := by show st.used ≤ st.used + n; omega
        omega
      · exact ⟨rfl, rfl, rfl, Int.le_refl _, rfl⟩
    | pageFigure i => exact ⟨rfl, rfl, rfl, Int.le_refl _, rfl⟩

theorem openBox_none (st : St) (h : st.box = none) : openBox st = st := by
  unfold openBox; rw [h]

theorem advanceFresh_fields (env : Env) (b : Bool) (st : St) (hb : Base st) :
    let F := advanceFresh env b st
    F.box = st.box ∧ 0 ≤ F.used ∧ 0 ≤ F.firstLine ∧ F.spaces = [] ∧ F.setAdjust = 0 ∧ F.reserved = 0 ∧
      F.noteLines = 0 ∧ F.adjust = 0 ∧ F.notes = [] := by
  have h1 := hb.first; have h2 := hb.setAdj; have h3 := hb.res
  unfold advanceFresh closePage; dsimp only
  repeat' split
  all_goals refine ⟨rfl, ?_, ?_, rfl, ?_, ?_, ?_, ?_, rfl⟩ <;> simp_all [top]

theorem pageFigures_eq (env : Env) (ts : List Nat) (st : St) :
    ∃ d pg, ts.foldl (pageFigure env) st = { st with done := d, page := pg } := by
  induction ts generalizing st with
  | nil => exact ⟨st.done, st.page, rfl⟩
  | cons t ts ih =>
    obtain ⟨d, pg, e⟩ := ih (pageFigure env st t)
    exact ⟨d, pg, by simp only [List.foldl]; rw [e]; rfl⟩

theorem carryAll_eq (env : Env) (ps : List NotePart) (s : St) :
    ∃ ns nl pd us, ps.foldl (carryNote env) s = { s with notes := ns, noteLines := nl, pending := pd, unmet := us } := by
  induction ps generalizing s with
  | nil => exact ⟨s.notes, s.noteLines, s.pending, s.unmet, rfl⟩
  | cons p ps ih =>
    obtain ⟨ns, nl, pd, us, e⟩ := ih (carryNote env s p)
    have c : ∃ ns nl pd us, carryNote env s p = { s with notes := ns, noteLines := nl, pending := pd, unmet := us } := by
      unfold carryNote addUnmet; split
      · exact ⟨_, _, _, _, rfl⟩
      · exact ⟨_, _, _, _, rfl⟩
    obtain ⟨ns', nl', pd', us', e'⟩ := c
    refine ⟨ns, nl, pd, us, ?_⟩
    simp only [List.foldl]; rw [e, e']

theorem carryAll_grow (env : Env) (hs : 0 ≤ env.separator) (ps : List NotePart) (s : St) :
    s.noteLines ≤ (ps.foldl (carryNote env) s).noteLines ∧
      ((s.pending = [] ∨ s.notes ≠ []) → ((ps.foldl (carryNote env) s).pending = [] ∨
        (ps.foldl (carryNote env) s).notes ≠ [])) := by
  induction ps generalizing s with
  | nil => exact ⟨Int.le_refl _, id⟩
  | cons p ps ih =>
    simp only [List.foldl]
    obtain ⟨a, b⟩ := ih (carryNote env s p)
    have c : s.noteLines ≤ (carryNote env s p).noteLines ∧
        ((s.pending = [] ∨ s.notes ≠ []) → ((carryNote env s p).pending = [] ∨ (carryNote env s p).notes ≠ [])) := by
      unfold carryNote addUnmet; split
      · exact ⟨Int.le_refl _, id⟩
      · refine ⟨?_, fun _ => Or.inr (by simp)⟩
        show s.noteLines ≤ s.noteLines + carrySep env s + _
        have : 0 ≤ carrySep env s := by unfold carrySep; split <;> omega
        omega
    exact ⟨Int.le_trans c.1 a, fun h => b (c.2 h)⟩

theorem placeDeferred_eq (env : Env) (ws : List Deferred) (st : St) :
    ∃ sl u h d, placeDeferred env st ws = { st with slots := sl, used := u, headingOnly := h, deferred := d } ∧
      st.used ≤ u := by
  induction ws generalizing st with
  | nil => exact ⟨st.slots, st.used, st.headingOnly, st.deferred, rfl, Int.le_refl _⟩
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · obtain ⟨sl, u, h, d, e, le⟩ := ih (putSlot st n (.figure i))
        refine ⟨sl, u, h, d, by rw [e]; rfl, ?_⟩
        have : st.used ≤ (putSlot st n (.figure i)).used := by show st.used ≤ st.used + n; omega
        omega
      · exact ⟨_, _, _, _, rfl, Int.le_refl _⟩
    | pageFigure i => exact ⟨_, _, _, _, rfl, Int.le_refl _⟩

/-- The grid lines and the separator the model takes. -/
structure Hyp (env : Env) : Prop where
  sep : 0 ≤ env.separator
  cap : 1 ≤ env.capacity

/-- A column opened from a state kept is kept, and when a note is carried on
    after it, the column holds its part and its lines are taken but for
    one (`carryNote`). -/
theorem adv (env : Env) (hs : Hyp env) (b : Bool) (st : St) (hb : Base st) :
    OR st (advance env b st) [] ∧ Base (advance env b st) ∧ Ok env (advance env b st) := by
  obtain ⟨f1, f2, f3⟩ := advanceFresh_NM env b st
  obtain ⟨h1, u0, l0, f4, f5, f6, f7, f8, f9⟩ := advanceFresh_fields env b st hb
  have hbF : (advanceFresh env b st).box = none := h1.trans hb.box
  simp only [advance, advanceIn, openColumn]
  generalize advanceFresh env b st = F at *
  obtain ⟨g1, g2, g3⟩ := pageFigures_NM env (advanceTurned b st).1 F
  obtain ⟨dd, pg, pe⟩ := pageFigures_eq env (advanceTurned b st).1 F
  generalize List.foldl (pageFigure env) F (advanceTurned b st).1 = F' at *
  subst pe
  obtain ⟨c, cj⟩ := carryAll_ord env hs.sep st.pending _ (Or.inl (g3.trans f3))
  obtain ⟨cg1, cg2⟩ := carryAll_grow env hs.sep st.pending { F with done := dd, page := pg }
  have tch := cg2 (Or.inl (g3.trans f3))
  obtain ⟨ns, nl, pd, us, ce'⟩ := carryAll_eq env st.pending { F with done := dd, page := pg }
  generalize st.pending.foldl (carryNote env) { F with done := dd, page := pg } = C at *
  obtain ⟨d1, d2⟩ := placeDeferred_NM env (advanceTurned b st).2 { C with deferred := [] }
  obtain ⟨sl, u1, hd1, dfr, de, du⟩ := placeDeferred_eq env (advanceTurned b st).2 { C with deferred := [] }
  generalize placeDeferred env { C with deferred := [] } (advanceTurned b st).2 = D at *
  subst de
  subst ce'
  rw [openBox_none _ (by exact hbF)]
  obtain ⟨⟨u, gu⟩, ce⟩ := c
  have sp0 : ∀ x ∈ F.spaces, 0 ≤ x.2 := by rw [f4]; intro x m; cases m
  have du' : F.used ≤ u1 := du
  have cg1' : F.noteLines ≤ nl := cg1
  refine ⟨⟨⟨u, ?_⟩, ?_⟩, ⟨hbF, l0, sp0, f5, f6, by show 0 ≤ nl; omega⟩, ⟨?_, Or.inl (by show 0 ≤ u1; omega), ?_⟩⟩
  · exact d2.trans (gu.trans (by rw [g2, f2]))
  · have iD : dropIds _ = dropIds _ := congrArg dropsOf d2
    rw [iD, d1, List.append_nil, ← f1, ← g1]
    exact ce
  · show 1 ≤ env.capacity + F.adjust - boxAfter F
    simp only [boxAfter, hbF, f8]; have := hs.cap; omega
  · by_cases pe : pd = []
    · left; rw [pe]; rfl
    · right
      rcases cj with e | e
      · exact absurd e pe
      refine ⟨?_, Or.inr (Or.inr (by rcases tch with t | t; exact absurd t pe; exact t))⟩
      simp only [carryRoom, Int.max_def] at e
      show env.capacity + F.adjust - boxAfter F - u1 - nl ≤ (if nl = 0 then env.separator else 0) + 1
      simp only [cap, boxAfter, carrySep, hbF, f8] at e ⊢
      split at e <;> split at e <;> split <;> omega

/-! ## Steps that place no note: they keep the column or open one -/

def Frame (a b : St) : Prop :=
  b.used = a.used ∧ b.noteLines = a.noteLines ∧ b.pending = a.pending ∧ b.adjust = a.adjust ∧ b.box = a.box ∧
    b.page = a.page ∧ b.column = a.column ∧ b.notes = a.notes

theorem Frame.refl (a : St) : Frame a a := ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem Frame.trans {a b c : St} (h1 : Frame a b) (h2 : Frame b c) : Frame a c := by
  obtain ⟨a1, a2, a3, a4, a5, a6, a7, a8⟩ := h1
  obtain ⟨b1, b2, b3, b4, b5, b6, b7, b8⟩ := h2
  exact ⟨b1.trans a1, b2.trans a2, b3.trans a3, b4.trans a4, b5.trans a5, b6.trans a6, b7.trans a7, b8.trans a8⟩

theorem ok_of {env : Env} {a b : St} (a1 : b.used = a.used) (a2 : b.noteLines = a.noteLines)
    (a3 : b.pending = a.pending) (a4 : b.adjust = a.adjust) (a5 : b.box = a.box) (a6 : b.notes = a.notes)
    (o : Ok env a) : Ok env b := by
  have f : free env b = free env a := by simp only [free, cap, boxAfter, a1, a2, a4, a5]
  have cp : cap env b = cap env a := by simp only [cap, boxAfter, a4, a5]
  have c : carrySep env b = carrySep env a := by simp only [carrySep, a2]
  obtain ⟨o1, o2, o | ⟨o, t⟩⟩ := o
  · exact ⟨by rw [cp]; exact o1, by rw [a1, a2]; exact o2, Or.inl (by rw [a3]; exact o)⟩
  · refine ⟨by rw [cp]; exact o1, by rw [a1, a2]; exact o2, Or.inr ⟨by rw [f, c]; exact o, ?_⟩⟩
    unfold Touched; rw [a1, a2, a6]; exact t

theorem Frame.ok {env : Env} {a b : St} (h : Frame a b) (o : Ok env a) : Ok env b :=
  ok_of h.1 h.2.1 h.2.2.1 h.2.2.2.1 h.2.2.2.2.1 h.2.2.2.2.2.2.2 o

/-- A step that places no note: it keeps the column, or opens a column
    kept. -/
def N (env : Env) (a b : St) : Prop := Base a → OR a b [] ∧ Base b ∧ (Ok env b ∨ Frame a b)

theorem N.refl (env : Env) (a : St) : N env a a := fun b => ⟨OR.refl a, b, Or.inr (Frame.refl a)⟩

theorem N.trans {env : Env} {a b c : St} (h1 : N env a b) (h2 : N env b c) : N env a c := by
  intro ba
  obtain ⟨r1, bb, o1⟩ := h1 ba
  obtain ⟨r2, bc, o2⟩ := h2 bb
  refine ⟨by simpa using r1.trans r2, bc, ?_⟩
  rcases o2 with o2 | f2
  · exact Or.inl o2
  · rcases o1 with o1 | f1
    · exact Or.inl (f2.ok o1)
    · exact Or.inr (f1.trans f2)

theorem N.toQ {env : Env} {a b : St} (h : N env a b) : Q env a b [] := by
  intro ba oa
  obtain ⟨r, bb, o⟩ := h ba
  refine ⟨r, bb, ?_⟩
  rcases o with o | f
  · exact o
  · exact f.ok oa

theorem N.ite {env : Env} {c : Prop} [Decidable c] {st a b : St} (ha : N env st a) (hb : N env st b) :
    N env st (if c then a else b) := by
  split
  · exact ha
  · exact hb

theorem N.frame {env : Env} {st s : St} (hd : s.done = st.done := by rfl) (hn : s.notes = st.notes := by rfl)
    (hp : s.pending = st.pending := by rfl) (hu : s.unmet = st.unmet := by rfl) (hb : s.box = st.box := by rfl)
    (hf : s.firstLine = st.firstLine := by rfl) (hsp : s.spaces = st.spaces := by rfl)
    (hl : s.noteLines = st.noteLines := by rfl) (hus : s.used = st.used := by rfl)
    (ha : s.adjust = st.adjust := by rfl) (hpg : s.page = st.page := by rfl) (hc : s.column = st.column := by rfl)
    (hsa : s.setAdjust = st.setAdjust := by rfl) (hr : s.reserved = st.reserved := by rfl) :
    N env st s := by
  intro ba
  refine ⟨OR.of_eq (by simp [NM, hd, hn, hp]) ⟨[], by simp [allUnmet, hd, hu]⟩,
    ba.of hb hf hsp hsa hr (by omega), Or.inr ⟨hus, hl, hp, ha, hb, hpg, hc, hn⟩⟩

theorem N.addU (env : Env) (u : Unmet) (st : St) : N env st (addUnmet u st) := by
  intro ba
  exact ⟨OR.of_eq (by simp [NM, addUnmet]) ⟨[u], by simp [allUnmet, addUnmet, List.append_assoc]⟩,
    ba.of, Or.inr (Frame.refl st)⟩

section
variable (env : Env) (hs : Hyp env)

theorem n_advance (b : Bool) (st : St) : N env st (advance env b st) := by
  intro ba
  obtain ⟨r, bb, o⟩ := adv env hs b st ba
  exact ⟨r, bb, Or.inl o⟩

theorem n_nextColumn (st : St) : N env st (nextColumn env st) := n_advance env hs _ st
theorem n_nextPage (st : St) : N env st (nextPage env st) := n_advance env hs _ st

theorem n_keep (st : St) (need : St → Int) : N env st (keep env st need) := by
  by_cases h : free env st < need st ∧ isEmpty st = false
  · unfold keep; rw [dif_pos h]; exact N.trans (n_nextColumn env hs st) (n_keep (nextColumn env st) need)
  · unfold keep; rw [dif_neg h]; exact N.refl env st
termination_by rank env st
decreasing_by exact I4_nextColumn_rank env st (Or.inl h.2)

theorem n_applyNeed (st : St) : N env st (applyNeed env st) := by
  unfold applyNeed
  split
  · exact N.refl env st
  · split
    · rename_i _ n _ _
      have a : N env st (addUnmet (.needLines n) { st with need := none }) :=
        N.trans N.frame (N.addU env _ _)
      exact N.ite a (N.trans a (n_nextColumn env hs _))
    · exact N.trans N.frame (n_keep env hs _ _)

theorem n_needBeforeSpace (st : St) : N env st (needBeforeSpace env st) := by
  unfold needBeforeSpace
  split
  · exact N.refl env st
  · split
    · exact N.refl env st
    · split
      · exact N.trans N.frame (n_applyNeed env hs _)
      · dsimp only
        exact N.trans (N.trans N.frame (n_applyNeed env hs { st with needAt := none })) N.frame

theorem q_keep (st : St) (need : St → Int) : Q env st (keep env st need) [] := (n_keep env hs st need).toQ
theorem q_nextColumn (st : St) : Q env st (nextColumn env st) [] := (n_nextColumn env hs st).toQ
theorem q_nextPage (st : St) : Q env st (nextPage env st) [] := (n_nextPage env hs st).toQ
theorem q_applyNeed (st : St) : Q env st (applyNeed env st) [] := (n_applyNeed env hs st).toQ
theorem q_needBeforeSpace (st : St) : Q env st (needBeforeSpace env st) [] := (n_needBeforeSpace env hs st).toQ

theorem q_blankPage (st : St) : Q env st (blankPage env st) [] := by
  intro ba oa
  refine ⟨OR.of_eq (by simp [NM, blankPage, pagesNotes_cons])
    ⟨[], by simp [allUnmet, blankPage, List.reverse_cons, List.append_bind]⟩, ba.of, ?_⟩
  exact ok_of rfl rfl rfl rfl rfl rfl oa

theorem q_pageFigure (st : St) (i : Nat) : Q env st (pageFigure env st i) [] := by
  intro ba oa
  refine ⟨OR.of_eq (by simp [NM, pageFigure, pagesNotes_cons])
    ⟨[], by simp [allUnmet, pageFigure, List.reverse_cons, List.append_bind]⟩, ba.of, ?_⟩
  exact ok_of rfl rfl rfl rfl rfl rfl oa

end

/-! ## Lines and blocks with notes -/

theorem partsLines_append (a b : List NotePart) : partsLines (a ++ b) = partsLines a + partsLines b := by
  induction a with
  | nil => simp [partsLines]
  | cons p ps ih =>
    show p.2.2 + partsLines (ps ++ b) = (p.2.2 + partsLines ps) + partsLines b
    rw [ih]; omega

theorem exN_length (ns : List Note) : (exN ns).length = (ns.map (·.lines)).foldr (· + ·) 0 := by
  induction ns with
  | nil => rfl
  | cons n ns ih =>
    have : ∀ f m, (seg n.id f m).length = m := by
      intro f m
      induction m generalizing f with
      | zero => rfl
      | succ m ih' => simp [seg, ih']
    simp [exN_cons, noteSeg, this, ih]

theorem splitNotes_sum (r : Int) (ns : List Note) :
    partsLines (splitNotes r ns).1 + partsLines (splitNotes r ns).2 = (ns.map (·.lines)).foldr (· + ·) 0 := by
  rw [← ex_length, ← ex_length, ← List.length_append, splitNotes_lines, exN_length]

theorem splitNotes_nonpos : ∀ (r : Int) (ns : List Note), r ≤ 0 → partsLines (splitNotes r ns).1 = 0
  | _, [], _ => rfl
  | r, ⟨i, len⟩ :: rest, h => by
    simp only [splitNotes]
    split
    · rename_i h1
      have : len = 0 := by omega
      subst this
      simp only [partsLines, List.foldr]
      have := splitNotes_nonpos (r - ((0 : Nat) : Int)) rest (by omega)
      simp only [partsLines] at this; rw [this]
    · split
      · omega
      · rfl

theorem splitNotes_shown : ∀ (r : Int) (ns : List Note), 0 < partsLines (splitNotes r ns).2 →
    (partsLines (splitNotes r ns).1 : Int) = max r 0
  | _, [], h => by simp [splitNotes, partsLines] at h
  | r, ⟨i, len⟩ :: rest, h => by
    simp only [splitNotes] at h ⊢
    split
    · rename_i h1
      rw [if_pos h1] at h
      have := splitNotes_shown (r - len) rest h
      simp only [partsLines, List.foldr] at this ⊢
      rw [Int.ofNat_add, this]
      simp only [Int.max_def]; split <;> split <;> omega
    · rename_i h1
      rw [if_neg h1] at h
      split
      · rename_i h2
        simp only [partsLines, List.foldr]
        have := Int.toNat_of_nonneg (Int.le_of_lt h2)
        simp only [Int.max_def]; split <;> omega
      · rename_i h2
        simp only [partsLines, List.foldr]
        simp only [Int.max_def]; split <;> omega

/-- `drainPendingNotes` leaves a kept column, whatever the column before:
    the lines a carried note does not take are at most the one it leaves
    for a column with no slot. -/
theorem takeNoteLines_shown : ∀ (r : Int) (ps : List NotePart), 0 < partsLines (takeNoteLines r ps).2 →
    (partsLines (takeNoteLines r ps).1 : Int) = max r 0
  | _, [], h => by simp [takeNoteLines, partsLines] at h
  | r, (i, f, l) :: more, h => by
    simp only [takeNoteLines] at h ⊢
    split
    · rename_i h0; simp only [partsLines, List.foldr, Int.max_def]; split <;> omega
    · rename_i h0
      rw [if_neg h0] at h
      split
      · rename_i h1
        rw [if_pos h1] at h
        have := takeNoteLines_shown (r - l) more h
        simp only [partsLines, List.foldr] at this ⊢
        rw [Int.ofNat_add, this]
        simp only [Int.max_def]; split <;> (try split) <;> omega
      · rename_i h1
        simp only [partsLines, List.foldr]
        have := Int.toNat_of_nonneg (show 0 ≤ r by omega)
        simp only [Int.max_def]; split <;> omega

/-- The arithmetic of a line put: when a note is carried on, nothing of a
    new note is shown, and the column keeps at most `R` lines free beyond
    the separator. -/
theorem put_arith (C u nl R sepr N sep room P1 P2 Pp e cs cs' : Int)
    (_hR : 0 ≤ R) (hsepr : 0 ≤ sepr) (hP1 : 0 ≤ P1) (hP2 : 0 ≤ P2) (hN : P1 + P2 = N)
    (hsep : (nl = 0 ∧ 0 < N ∧ sep = sepr) ∨ (¬ (nl = 0 ∧ 0 < N) ∧ sep = 0))
    (hroom : room = C - u - 1 - R - nl - sep)
    (S0 : room ≤ 0 → P1 = 0) (S1 : 0 < P2 → P1 = max room 0)
    (he : e = sep ∨ (e = 0 ∧ P1 = 0))
    (hcs : (nl = 0 ∧ cs = sepr) ∨ (nl ≠ 0 ∧ cs = 0))
    (hcs' : (nl + e + P1 = 0 ∧ cs' = sepr) ∨ (nl + e + P1 ≠ 0 ∧ cs' = 0))
    (o : Pp = 0 ∨ C - u - nl ≤ cs + (R + 1)) :
    (Pp = 0 ∨ P1 = 0) ∧ (Pp + P2 = 0 ∨ C - (u + 1) - (nl + e + P1) ≤ cs' + R) := by
  have m1 : 0 < P2 → room ≥ 0 → P1 = room := fun h r => by rw [S1 h]; simp only [Int.max_def]; split <;> omega
  have m2 : 0 < P2 → room < 0 → P1 = 0 := fun h r => by rw [S1 h]; simp only [Int.max_def]; split <;> omega
  constructor
  · rcases o with o | o
    · exact Or.inl o
    · right
      by_cases hn : 0 < N
      · apply S0; omega
      · omega
  · by_cases hp : Pp = 0
    · by_cases h2 : P2 = 0
      · left; omega
      · right
        by_cases r0 : room ≥ 0
        · have := m1 (by omega) r0; omega
        · have := m2 (by omega) (by omega); omega
    · right
      rcases o with o | o
      · exact absurd o hp
      · have p1 : P1 = 0 := by
          by_cases hn : 0 < N
          · apply S0; omega
          · omega
        omega

/-- The same for a block of `n` grid lines, one or more. -/
theorem block_arith (C u nl n sepr N sep room P1 P2 Pp e cs cs' : Int)
    (hn1 : 1 ≤ n) (hsepr : 0 ≤ sepr) (hP1 : 0 ≤ P1) (hP2 : 0 ≤ P2) (hN : P1 + P2 = N)
    (hsep : (nl = 0 ∧ 0 < N ∧ sep = sepr) ∨ (¬ (nl = 0 ∧ 0 < N) ∧ sep = 0))
    (hroom : room = C - u - n - nl - sep)
    (S0 : room ≤ 0 → P1 = 0) (S1 : 0 < P2 → P1 = max room 0)
    (he : e = sep ∨ (e = 0 ∧ P1 = 0))
    (hcs : (nl = 0 ∧ cs = sepr) ∨ (nl ≠ 0 ∧ cs = 0))
    (hcs' : (nl + e + P1 = 0 ∧ cs' = sepr) ∨ (nl + e + P1 ≠ 0 ∧ cs' = 0))
    (o : Pp = 0 ∨ C - u - nl ≤ cs + 1) :
    (Pp = 0 ∨ P1 = 0) ∧ (Pp + P2 = 0 ∨ C - (u + n) - (nl + e + P1) ≤ cs' + 1) := by
  have m1 : 0 < P2 → room ≥ 0 → P1 = room := fun h r => by rw [S1 h]; simp only [Int.max_def]; split <;> omega
  have m2 : 0 < P2 → room < 0 → P1 = 0 := fun h r => by rw [S1 h]; simp only [Int.max_def]; split <;> omega
  constructor
  · rcases o with o | o
    · exact Or.inl o
    · right
      by_cases hn : 0 < N
      · apply S0; omega
      · omega
  · by_cases hp : Pp = 0
    · by_cases h2 : P2 = 0
      · left; omega
      · right
        by_cases r0 : room ≥ 0
        · have := m1 (by omega) r0; omega
        · have := m2 (by omega) (by omega); omega
    · right
      rcases o with o | o
      · exact absurd o hp
      · have p1 : P1 = 0 := by
          by_cases hn : 0 < N
          · apply S0; omega
          · omega
        omega

/-- The parts of a line or a block put: nothing is shown while a note is
    carried on, so the lines read come after what the state holds. -/
theorem nm_put {st s : St} (sp : List NotePart × List NotePart) (Y : List (Nat × Nat))
    (hy : ex sp.1 ++ ex sp.2 = Y) (hd : s.done = st.done) (hn : s.notes = st.notes ++ sp.1)
    (hp : s.pending = st.pending ++ sp.2) (h : partsLines st.pending = 0 ∨ partsLines sp.1 = 0) :
    NM s = NM st ++ Y := by
  simp only [NM, hd, hn, hp, ex_append, ← hy]
  rcases h with h | h
  · rw [ex_nil_of h]; simp [List.append_assoc]
  · rw [ex_nil_of h]; simp [List.append_assoc]

theorem sep_cases (env : Env) (nl : Int) (N : Nat) :
    (nl = 0 ∧ 0 < (N : Int) ∧ (if nl = 0 ∧ 0 < N then env.separator else 0) = env.separator) ∨
      (¬ (nl = 0 ∧ 0 < (N : Int)) ∧ (if nl = 0 ∧ 0 < N then env.separator else 0) = 0) := by
  split
  · rename_i h; left; exact ⟨h.1, by omega, rfl⟩
  · rename_i h; right; exact ⟨fun c => h ⟨c.1, by omega⟩, rfl⟩

theorem carrySep_cases (env : Env) (st : St) :
    (st.noteLines = 0 ∧ carrySep env st = env.separator) ∨ (st.noteLines ≠ 0 ∧ carrySep env st = 0) := by
  simp only [carrySep]; split
  · left; exact ⟨by assumption, rfl⟩
  · right; exact ⟨by assumption, rfl⟩

section
variable (env : Env) (hs : Hyp env)

theorem q_putLineKeeping (R : Nat) (st : St) (l : Line) (ba : Base st) (o : OkK env (R + 1) st) :
    OR st (putLineKeeping env R st l) (exN l.notes) ∧ Base (putLineKeeping env R st l) ∧
      OkK env R (putLineKeeping env R st l) := by
  have hsep := sep_cases env st.noteLines ((l.notes.map (·.lines)).foldr (· + ·) 0)
  generalize hN : (l.notes.map (·.lines)).foldr (· + ·) 0 = N at hsep
  generalize hsp : (if st.noteLines = 0 ∧ 0 < N then env.separator else 0) = sep at hsep
  generalize hr : cap env st - st.used - 1 - (R : Int) - st.noteLines - sep = room
  have L := splitNotes_lines room l.notes
  have S0 := splitNotes_nonpos room l.notes
  have S1 := splitNotes_shown room l.notes
  have S2 := splitNotes_sum room l.notes
  generalize hq : splitNotes room l.notes = sp at L S0 S1 S2
  generalize he : (if sp.1.isEmpty = true ∧ 0 < (R : Int) then (0 : Int) else sep) = e
  have hput : putLineKeeping env R st l = { st with
      slots := st.slots ++ [(st.used, .line l.id)], used := st.used + 1,
      noteLines := st.noteLines + e + partsLines sp.1, notes := st.notes ++ sp.1,
      pending := st.pending ++ sp.2, headingOnly := false } := by
    rw [← he, ← hq, ← hr, ← hsp, ← hN]; rfl
  rw [hput]
  have he' : e = sep ∨ (e = 0 ∧ ((partsLines sp.1 : Nat) : Int) = 0) := by
    rw [← he]; split
    · rename_i h; right; refine ⟨rfl, ?_⟩
      cases c : sp.1 with
      | nil => rfl
      | cons _ _ => rw [c] at h; simp [List.isEmpty] at h
    · left; rfl
  have cs := carrySep_cases env st
  have cs' := carrySep_cases env { st with
      slots := st.slots ++ [(st.used, .line l.id)], used := st.used + 1,
      noteLines := st.noteLines + e + partsLines sp.1, notes := st.notes ++ sp.1,
      pending := st.pending ++ sp.2, headingOnly := false }
  obtain ⟨oc, ou, o⟩ := o
  have o' : ((partsLines st.pending : Nat) : Int) = 0 ∨ cap env st - st.used - st.noteLines ≤ carrySep env st + (R + 1) := by
    rcases o with o | ⟨o, _⟩
    · exact Or.inl (by exact_mod_cast o)
    · exact Or.inr o
  rw [hN] at S2; rw [← S2] at hsep
  have e0 : 0 ≤ e := by have := hs.sep; rcases he' with h | h <;> rcases hsep with g | g <;> omega
  have a := put_arith (cap env st) st.used st.noteLines R env.separator _ sep room (partsLines sp.1) (partsLines sp.2)
    (partsLines st.pending) e (carrySep env st) _ (by omega) hs.sep (by omega) (by omega) rfl
    (by simpa using hsep) hr.symm (fun h => by exact_mod_cast S0 h) (fun h => S1 (by exact_mod_cast h))
    he' cs cs' o'
  obtain ⟨a1, a2⟩ := a
  have a1' : partsLines st.pending = 0 ∨ partsLines sp.1 = 0 := by
    rcases a1 with h | h
    · exact Or.inl (by exact_mod_cast h)
    · exact Or.inr (by exact_mod_cast h)
  refine ⟨OR.of_eq (nm_put sp _ L rfl rfl rfl a1') ⟨[], by simp [allUnmet]⟩,
    ba.of (hl := by show st.noteLines ≤ st.noteLines + e + _; omega), oc, ?_, ?_⟩
  · rcases ou with u | u
    · exact Or.inl (show 0 ≤ st.used + 1 by omega)
    · exact Or.inr (show 0 < st.noteLines + e + _ by omega)
  rcases a2 with h | h
  · left; show partsLines (st.pending ++ sp.2) = 0; rw [partsLines_append]; omega
  · refine Or.inr ⟨h, ?_⟩
    rcases ou with u | u
    · exact Or.inl (show 1 ≤ st.used + 1 by omega)
    · exact Or.inr (Or.inl (show 0 < st.noteLines + e + _ by omega))

theorem q_putLine (st : St) (l : Line) : Q env st (putLine env st l) l.notes := by
  intro ba oa
  obtain ⟨a, b, c⟩ := q_putLineKeeping env hs 0 st l ba (by simpa using oa)
  exact ⟨a, b, c.mono (by decide)⟩

theorem q_putLines (ls : List Line) (st : St) : Q env st (ls.foldl (putLine env) st) (ls.bind (·.notes)) := by
  induction ls generalizing st with
  | nil => exact Q.refl env st
  | cons l ls ih => simp only [List.foldl]; exact Q.tr (q_putLine env hs st l) (ih _) rfl

theorem q_putBlock (st : St) (n : Nat) (hn : 1 ≤ n) (ls : List Line) :
    Q env st (putBlock env st n ls) (ls.bind (·.notes)) := by
  cases ls with
  | nil => exact Q.refl env st
  | cons l0 ls =>
  intro ba o
  have hsep := sep_cases env st.noteLines ((((l0 :: ls).bind (·.notes)).map (·.lines)).foldr (· + ·) 0)
  generalize hN : (((l0 :: ls).bind (·.notes)).map (·.lines)).foldr (· + ·) 0 = N at hsep
  generalize hsp : (if st.noteLines = 0 ∧ 0 < N then env.separator else 0) = sep at hsep
  generalize hr : cap env st - st.used - (n : Int) - st.noteLines - sep = room
  have L := splitNotes_lines room ((l0 :: ls).bind (·.notes))
  have S0 := splitNotes_nonpos room ((l0 :: ls).bind (·.notes))
  have S1 := splitNotes_shown room ((l0 :: ls).bind (·.notes))
  have S2 := splitNotes_sum room ((l0 :: ls).bind (·.notes))
  generalize hq : splitNotes room ((l0 :: ls).bind (·.notes)) = sp at L S0 S1 S2
  generalize he : (if sp.1.isEmpty = true then (0 : Int) else sep) = e
  generalize ht : (if free env st < n then [Unmet.tallHeading l0.id n (free env st)] else []) = tall
  have hput : putBlock env st n (l0 :: ls) = { st with
      slots := st.slots ++ [(st.used, .heading l0.id (l0 :: ls).length)], used := st.used + n,
      noteLines := st.noteLines + e + partsLines sp.1, notes := st.notes ++ sp.1,
      pending := st.pending ++ sp.2, headingOnly := isEmpty st || st.headingOnly, unmet := st.unmet ++ tall } := by
    rw [← he, ← hq, ← hr, ← hsp, ← hN, ← ht]; rfl
  rw [hput]
  have he' : e = sep ∨ (e = 0 ∧ ((partsLines sp.1 : Nat) : Int) = 0) := by
    rw [← he]; split
    · rename_i h; right; refine ⟨rfl, ?_⟩
      cases c : sp.1 with
      | nil => rfl
      | cons _ _ => rw [c] at h; simp [List.isEmpty] at h
    · left; rfl
  have cs := carrySep_cases env st
  have cs' := carrySep_cases env { st with
      slots := st.slots ++ [(st.used, .heading l0.id (l0 :: ls).length)], used := st.used + n,
      noteLines := st.noteLines + e + partsLines sp.1, notes := st.notes ++ sp.1,
      pending := st.pending ++ sp.2, headingOnly := isEmpty st || st.headingOnly, unmet := st.unmet ++ tall }
  obtain ⟨oc, ou, o⟩ := o
  have o' : ((partsLines st.pending : Nat) : Int) = 0 ∨ cap env st - st.used - st.noteLines ≤ carrySep env st + 1 := by
    rcases o with o | ⟨o, _⟩
    · exact Or.inl (by exact_mod_cast o)
    · exact Or.inr o
  rw [hN] at S2; rw [← S2] at hsep
  have e0 : 0 ≤ e := by have := hs.sep; rcases he' with h | h <;> rcases hsep with g | g <;> omega
  have a := block_arith (cap env st) st.used st.noteLines n env.separator _ sep room (partsLines sp.1) (partsLines sp.2)
    (partsLines st.pending) e (carrySep env st) _ (by omega) hs.sep (by omega) (by omega) rfl
    (by simpa using hsep) hr.symm (fun h => by exact_mod_cast S0 h) (fun h => S1 (by exact_mod_cast h))
    he' cs cs' o'
  obtain ⟨a1, a2⟩ := a
  have a1' : partsLines st.pending = 0 ∨ partsLines sp.1 = 0 := by
    rcases a1 with h | h
    · exact Or.inl (by exact_mod_cast h)
    · exact Or.inr (by exact_mod_cast h)
  refine ⟨OR.of_eq ?_ ⟨tall, by simp [allUnmet, List.append_assoc]⟩,
    ba.of (hl := by show st.noteLines ≤ st.noteLines + e + _; omega), oc, ?_, ?_⟩
  · rw [exN]; exact nm_put sp _ L rfl rfl rfl a1'
  · rcases ou with u | u
    · exact Or.inl (show 0 ≤ st.used + n by omega)
    · exact Or.inr (show 0 < st.noteLines + e + _ by omega)
  rcases a2 with h | h
  · left; show partsLines (st.pending ++ sp.2) = 0; rw [partsLines_append]; omega
  · refine Or.inr ⟨h, ?_⟩
    rcases ou with u | u
    · exact Or.inl (show 1 ≤ st.used + n by omega)
    · exact Or.inr (Or.inl (show 0 < st.noteLines + e + _ by omega))

theorem drain_facts (st : St) (hc : 1 ≤ cap env st) (hu : 0 ≤ st.used ∨ 0 < st.noteLines)
    (ht : 0 < partsLines st.pending → Touched st) (hnl : 0 ≤ st.noteLines) :
    OR st (drainPendingNotes env st) [] ∧ (Base st → Base (drainPendingNotes env st)) ∧
      Ok env (drainPendingNotes env st) := by
  have s0 := hs.sep
  have ds : 0 ≤ drainSep env st := by unfold drainSep; split <;> omega
  obtain ⟨ns, nl, ps, e⟩ := drainPendingNotes_eq env st
  have n := nm_drainPendingNotes env st
  have grow : st.noteLines ≤ (drainPendingNotes env st).noteLines := by
    unfold drainPendingNotes; split
    · exact Int.le_refl _
    · show st.noteLines ≤ st.noteLines + drainSep env st + _; omega
  refine ⟨OR.of_eq (by rw [n, List.append_nil]) ⟨[], by rw [e]; simp [allUnmet]⟩,
    fun b => b.of (hb := by rw [e]) (hf := by rw [e]) (hsp := by rw [e]) (hsa := by rw [e]) (hr := by rw [e])
      (hl := grow), ?_⟩
  have hc' : 1 ≤ cap env (drainPendingNotes env st) := by rw [e]; exact hc
  have hu' : 0 ≤ (drainPendingNotes env st).used ∨ 0 < (drainPendingNotes env st).noteLines := by
    have : (drainPendingNotes env st).used = st.used := by rw [e]
    rcases hu with u | u
    · exact Or.inl (by omega)
    · exact Or.inr (by omega)
  refine ⟨hc', hu', ?_⟩
  clear hc' hu' grow
  unfold drainPendingNotes
  split
  · rename_i c
    by_cases z : partsLines st.pending = 0
    · exact Or.inl z
    rcases c with c | c
    · left; cases h : st.pending with
      | nil => rfl
      | cons _ _ => rw [h] at c; simp [List.isEmpty] at c
    · right; refine ⟨?_, ht (by omega)⟩
      simp only [drainRoom, drainSep] at c; simp only [carrySep]; split at c <;> split <;> omega
  · rename_i c
    have _r0 : 0 < drainRoom env st := by
      by_cases hh : 0 < drainRoom env st
      · exact hh
      · exact absurd (Or.inr (by omega)) c
    have T := takeNoteLines_shown (drainRoom env st) st.pending
    generalize takeNoteLines (drainRoom env st) st.pending = p at T ⊢
    by_cases z : partsLines p.2 = 0
    · left; exact z
    · right
      have t := T (by omega)
      have dm : max (drainRoom env st) 0 = drainRoom env st := by
        simp only [Int.max_def]; split <;> omega
      rw [dm] at t
      refine ⟨?_, Or.inr (Or.inl (show 0 < st.noteLines + drainSep env st + _ by omega))⟩
      have i1 : (if st.slots.isEmpty = true then (1 : Int) else 0) ≤ 1 := by split <;> omega
      simp only [drainRoom] at t
      show cap env st - st.used - (st.noteLines + drainSep env st + partsLines p.1) ≤ _ + 1
      simp only [free] at t
      unfold carrySep; split <;> omega

/-- `@page-lines`, then the carried notes drained. -/
theorem q_adjust (st : St) (k : Int) : Q env st (drainPendingNotes env (adjustLines env st k)) [] := by
  intro ba oa
  obtain ⟨_, ou, op⟩ := oa
  have a : OR st (adjustLines env st k) [] ∧ Base (adjustLines env st k) ∧
      (adjustLines env st k).used = st.used ∧ (adjustLines env st k).noteLines = st.noteLines ∧
      (adjustLines env st k).pending = st.pending ∧ (adjustLines env st k).notes = st.notes ∧
      1 ≤ cap env (adjustLines env st k) := by
    simp only [adjustLines]
    split
    · refine ⟨OR.of_eq (by simp [NM, addUnmet]) ⟨[_], by simp [allUnmet, addUnmet]; rfl⟩, ba.of, rfl, rfl, rfl, rfl, ?_⟩
      show 1 ≤ env.capacity + max (max 1 (st.used + st.noteLines) - env.capacity)
        (min (env.maxLines - env.capacity) (st.adjust + k)) - boxAfter st
      simp only [boxAfter, ba.box]
      have := Int.le_max_left (max 1 (st.used + st.noteLines) - env.capacity)
        (min (env.maxLines - env.capacity) (st.adjust + k))
      have := Int.le_max_left 1 (st.used + st.noteLines)
      omega
    · refine ⟨OR.of_eq (by simp [NM]) ⟨[], by simp [allUnmet]⟩, ba.of, rfl, rfl, rfl, rfl, ?_⟩
      show 1 ≤ env.capacity + max (max 1 (st.used + st.noteLines) - env.capacity)
        (min (env.maxLines - env.capacity) (st.adjust + k)) - boxAfter st
      simp only [boxAfter, ba.box]
      have := Int.le_max_left (max 1 (st.used + st.noteLines) - env.capacity)
        (min (env.maxLines - env.capacity) (st.adjust + k))
      have := Int.le_max_left 1 (st.used + st.noteLines)
      omega
  obtain ⟨a1, a2, a3, a4, a5, a6, a7⟩ := a
  obtain ⟨d1, d2, d3⟩ := drain_facts env hs (adjustLines env st k) a7 (by rw [a3, a4]; exact ou)
    (fun h => by
      rw [a5] at h
      rcases op with o | ⟨_, t⟩
      · omega
      · unfold Touched; rw [a3, a4, a6]; exact t)
    (by rw [a4]; exact ba.nl)
  exact ⟨by simpa using a1.trans d1, d2 a2, d3⟩
end

theorem spaces_nonneg : ∀ (xs : List (Nat × Int)), (∀ x ∈ xs, 0 ≤ x.2) → 0 ≤ (xs.map (·.2)).foldr (· + ·) 0
  | [], _ => Int.le_refl _
  | x :: xs, h => by
    simp only [List.map, List.foldr]
    have := spaces_nonneg xs (fun y m => h y (List.mem_cons_of_mem _ m))
    have := h x (List.mem_cons_self _ _)
    omega

theorem mem_append_cases {α : Type} {x : α} : ∀ {a b : List α}, x ∈ a ++ b → x ∈ a ∨ x ∈ b
  | [], _, m => Or.inr m
  | y :: ys, b, m => by
    cases m with
    | head => exact Or.inl (List.Mem.head _)
    | tail _ m =>
      rcases mem_append_cases m with h | h
      · exact Or.inl (List.Mem.tail _ h)
      · exact Or.inr h

theorem ok_addUsed {env : Env} {s : St} (d : Int) (hd : 0 ≤ d) (o : Ok env s) :
    Ok env { s with used := s.used + d } := by
  obtain ⟨o1, o2, o3⟩ := o
  refine ⟨o1, ?_, ?_⟩
  · rcases o2 with h | h
    · exact Or.inl (show 0 ≤ s.used + d by omega)
    · exact Or.inr h
  · rcases o3 with h | ⟨h, t⟩
    · exact Or.inl h
    · refine Or.inr ⟨show cap env s - (s.used + d) - s.noteLines ≤ carrySep env s + 1 by simp only [free] at h; omega, ?_⟩
      rcases t with t | t | t
      · exact Or.inl (show 1 ≤ s.used + d by omega)
      · exact Or.inr (Or.inl t)
      · exact Or.inr (Or.inr t)

/-! ## The loops and breaks of State.hs -/

section
variable (env : Env) (hs : Hyp env)

theorem n_flushDeferred (st : St) : N env st (flushDeferred env st) := by
  by_cases h : st.deferred = [] ∧ st.pending = []
  · unfold flushDeferred; rw [dif_pos h]; exact N.refl env st
  · unfold flushDeferred; rw [dif_neg h]
    exact N.trans (n_nextColumn env hs st) (n_flushDeferred (nextColumn env st))
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st h)

theorem n_flushFigures (st : St) : N env st (flushFigures env st) := by
  by_cases h : st.deferred = []
  · unfold flushFigures; rw [dif_pos h]; exact N.refl env st
  · unfold flushFigures; rw [dif_neg h]
    exact N.trans (n_nextColumn env hs st) (n_flushFigures (nextColumn env st))
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st (fun c => h c.1))

theorem q_flushDeferred (st : St) : Q env st (flushDeferred env st) [] := (n_flushDeferred env hs st).toQ
theorem q_flushFigures (st : St) : Q env st (flushFigures env st) [] := (n_flushFigures env hs st).toQ

theorem q_parityStart (p : Nat → Bool) (st : St) : Q env st (parityStart env p st) [] := by
  simp only [parityStart]
  have h0 := q_flushDeferred env hs st
  have h1 : Q env st (if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then
      flushDeferred env st else nextPage env (flushDeferred env st)) [] :=
    Q.ite h0 (Q.nl h0 (q_nextPage env hs _))
  generalize (if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then
      flushDeferred env st else nextPage env (flushDeferred env st)) = s1 at h1
  exact Q.ite h1 (Q.nl h1 (q_blankPage env s1))

theorem q_breakPage (st : St) : Q env st (breakPage env st) [] := by
  simp only [breakPage]
  exact Q.ite (q_blankPage env st) (Q.ite (Q.refl env st) (q_nextPage env hs st))

theorem q_applyBreakKind (st : St) (k : BreakKind) : Q env st (applyBreakKind env st k) [] := by
  cases k
  · exact q_breakPage env hs st
  · exact Q.ite (q_nextColumn env hs st) (q_breakPage env hs st)
  · exact q_parityStart env hs odd st
  · exact q_parityStart env hs even st

theorem q_startBefore (st : St) (sec : Option Nat) (k : BreakKind) : Q env st (startBefore env st sec k) [] := by
  have h1 : Q env st (match k with
      | .column => if isEmpty st then st else nextColumn env st
      | .page =>
        if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
        else nextPage env (flushDeferred env st)
      | .recto => parityStart env odd st
      | .verso => parityStart env even st) [] := by
    cases k
    · exact Q.ite (q_flushDeferred env hs st) (Q.nl (q_flushDeferred env hs st) (q_nextPage env hs _))
    · exact Q.ite (Q.refl env st) (q_nextColumn env hs st)
    · exact q_parityStart env hs odd st
    · exact q_parityStart env hs even st
  simp only [startBefore]
  split
  · exact Q.nr h1 Q.frame
  · exact h1

theorem q_applyBreaks (st : St) : Q env st (applyBreaks env st) [] := by
  simp only [applyBreaks]
  suffices ∀ (ks : List Pending) (s : St), Q env s (ks.foldl (applyPending env) s) [] from
    Q.nl Q.frame (this st.breaks _)
  intro ks
  induction ks with
  | nil => intro s; exact Q.refl env s
  | cons k ks ih =>
    intro s; simp only [List.foldl]
    refine Q.nl ?_ (ih _)
    cases k with
    | brk k => exact q_applyBreakKind env hs s k
    | start sec k => exact q_startBefore env hs s sec k

theorem q_placeSpaceFlow (st : St) (n : Nat) : Q env st (placeSpaceFlow env st n) [] := by
  unfold placeSpaceFlow; split
  · exact Q.refl env st
  · refine Q.frame (hused := ?_)
    have := Int.le_max_left 0 (min (n : Int) (free env st))
    show st.used ≤ st.used + _; omega

theorem placeSpaceFlow_used (st : St) (n : Nat) : st.used ≤ (placeSpaceFlow env st n).used := by
  unfold placeSpaceFlow; split
  · exact Int.le_refl _
  · have := Int.le_max_left 0 (min (n : Int) (free env st))
    show st.used ≤ st.used + _; omega

theorem q_placeSpace (st : St) (n : Nat) : Q env st (placeSpace env st n) [] := by
  intro ba oa
  obtain ⟨r, b, o⟩ := q_placeSpaceFlow env st n ba oa
  have u := placeSpaceFlow_used env st n
  refine ⟨?_, ⟨b.box, b.first, ?_, b.setAdj, b.res, b.nl⟩, ?_⟩
  · obtain ⟨g, e⟩ := r
    exact ⟨g, e⟩
  · intro x m
    rcases mem_append_cases m with m | m
    · exact ba.spaces x m
    · cases m with
      | head => show 0 ≤ (placeSpaceFlow env st n).used - st.used; omega
      | tail _ m => cases m
  · exact ok_of rfl rfl rfl rfl rfl rfl o

theorem q_placeSpaces (ns : List Nat) (st : St) : Q env st (ns.foldl (placeSpace env) st) [] := by
  induction ns generalizing st with
  | nil => exact Q.refl env st
  | cons n ns ih => simp only [List.foldl]; exact Q.nl (q_placeSpace env st n) (ih _)

/-- The spaces taken off, the need placed, and the spaces placed again:
    where the column stays, its lines are as they were. -/
theorem q_needBeforeSpaces (st : St) : Q env st (needBeforeSpaces env st) [] := by
  intro ba oa
  unfold needBeforeSpaces
  simp only
  have k0 := spaces_nonneg st.spaces ba.spaces
  generalize (st.spaces.map (·.2)).foldr (· + ·) 0 = k at k0
  have b0 : Base { st with used := st.used - k } := ba.of
  have r0 : OR st { st with used := st.used - k } [] := OR.of_eq (by simp [NM]) ⟨[], by simp [allUnmet]⟩
  obtain ⟨r1, b1, o1⟩ := n_needBeforeSpace env hs { st with used := st.used - k } b0
  generalize needBeforeSpace env { st with used := st.used - k } = s1 at r1 b1 o1
  split
  · rename_i pc
    refine ⟨?_, b1.of, ?_⟩
    · have := (r0.trans r1).trans (OR.of_eq (Y := []) (st := s1) (s := { s1 with used := s1.used + k }) (by simp [NM])
        ⟨[], by simp [allUnmet]⟩)
      simpa using this
    · rcases o1 with o1 | f
      · exact ok_addUsed k k0 o1
      · obtain ⟨f1, f2, f3, f4, f5, _, _, f8⟩ := f
        exact ok_of (a := st) (by show s1.used + k = st.used; rw [f1]; show st.used - k + k = st.used; omega) f2 f3 f4 f5 f8 oa
  · rename_i pc
    rcases o1 with o1 | f
    · obtain ⟨r2, b2, o2⟩ := q_placeSpaces env (st.spaces.map (·.1)) s1 b1 o1
      exact ⟨by simpa using (r0.trans r1).trans r2, b2, o2⟩
    · exact absurd ⟨f.2.2.2.2.2.1, f.2.2.2.2.2.2.1⟩ pc

theorem q_needAfterSpaces (st : St) : Q env st (needAfterSpaces env st) [] := by
  unfold needAfterSpaces; split
  · exact Q.refl env st
  · exact q_needBeforeSpaces env hs st

theorem q_needMore (n : Nat) (st : St) : Q env st (needMore env n st) [] := by
  unfold needMore
  split
  · split
    · exact Q.refl env st
    · exact Q.nl Q.frame (q_needAfterSpaces env hs _)
  · exact Q.nl Q.frame (q_needAfterSpaces env hs _)

theorem q_needBefore (st : St) (flows : List Flow) : Q env st (needBefore env st flows) [] := by
  unfold needBefore
  split
  · split
    · exact Q.nl Q.frame (q_keep env hs _ _)
    · exact Q.nl Q.frame (q_applyNeed env hs _)
  · exact Q.nl Q.frame (q_applyNeed env hs _)

theorem blanks_total_nonneg (hc : 0 ≤ env.capacity) : ∀ (bs : List Nat) (a : Int), 0 ≤ a →
    0 ≤ bs.foldl (fun a (n : Nat) => min env.capacity (a + min env.capacity (n : Int))) a
  | [], _, h => h
  | b :: bs, a, h => by
    simp only [List.foldl]
    apply blanks_total_nonneg hc bs
    simp only [Int.min_def]; split <;> split <;> omega

theorem q_placeBlank (st : St) (f : Flow) (rest : List Flow) :
    Q env st (placeBlank env st f rest) [] := by
  unfold placeBlank
  split
  · exact Q.refl env st
  · simp only
    have h1 : Q env st (if startsRecto f = true then parityStart env odd st else st) [] :=
      Q.ite (q_parityStart env hs odd st) (Q.refl env st)
    generalize (if startsRecto f = true then parityStart env odd st else st) = s1 at h1
    refine Q.ite (Q.nl (Q.nl h1 (q_keep env hs s1 _)) (Q.nl Q.frame (Q.dropBlanks env _ _)))
      (Q.nr (Q.nl h1 (q_keep env hs s1 _)) (Q.frame (hused := ?_)))
    have := blanks_total_nonneg env (by have := hs.cap; omega) st.blank 0 (Int.le_refl _)
    show _ ≤ _ + _; omega

end

/-- A heading with rules takes one grid line or more. -/
def RuledOk : RuledBody → Prop
  | .heading _ n _ => 1 ≤ n
  | .lines _ _ => True

/-! ## Lines, stanzas, code and tables -/

section
variable (env : Env) (hs : Hyp env)

theorem q_placeLinesGo (pid : Nat) (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) :
    Q env st (placeLinesGo env pid kp st isStart ls) (ls.bind (·.notes)) := by
  match ls with
  | [] => simp only [placeLinesGo]; exact Q.refl env st
  | l :: ls' =>
    by_cases h1 : st.adjust < 0 ∧ isEmpty st = true ∧ env.roomForLine st (l :: ls') = false
    · unfold placeLinesGo; rw [dif_pos h1]
      exact Q.nl (q_nextColumn env hs st) (q_placeLinesGo pid kp (nextColumn env st) isStart (l :: ls'))
    · by_cases h2 : kp.all = true ∧ isStart = true ∧ env.fitting st (l :: ls') < (l :: ls').length
      · by_cases h3 : isEmpty st = true ∨ st.headingOnly = true
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_pos h3]
          exact Q.nl (Q.addU env _ st)
            (q_placeLinesGo pid { kp with all := false } (addUnmet (.splitKept pid) st) isStart (l :: ls'))
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_neg h3]
          exact Q.nl (q_nextColumn env hs st) (q_placeLinesGo pid kp (nextColumn env st) isStart (l :: ls'))
      · by_cases h4 : (l :: ls').length ≤ (lineCount env kp st isStart (l :: ls')).1
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_pos h4]; exact q_putLines env hs _ st
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_neg h4]
          exact Q.tr (Q.nr (q_putLines env hs _ st) (Q.addUs env _ _))
            (Q.nl (q_nextColumn env hs _)
              (q_placeLinesGo pid kp _ _ ((l :: ls').drop (lineCount env kp st isStart (l :: ls')).1)))
            (bind_take_drop _ _)
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

theorem q_placeLines (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) :
    Q env st (placeLines env kp st isStart ls) (ls.bind (·.notes)) := by
  cases ls with
  | nil => simp only [placeLines]; exact Q.refl env st
  | cons l ls => exact q_placeLinesGo env hs _ _ _ _ _

theorem q_putVerses (st : St) (vs : List (List Line)) :
    Q env st (putVerses env st vs) (vs.join.bind (·.notes)) := q_putLines env hs vs.join st

theorem q_placeStanzaGo (pid : Nat) (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) :
    Q env st (placeStanzaGo env pid kp st isStart vs) (vs.join.bind (·.notes)) := by
  match vs with
  | [] => simp only [placeStanzaGo]; exact Q.refl env st
  | v :: more =>
    unfold placeStanzaGo
    simp only
    split
    · split
      · exact Q.nl (Q.addU env _ st) (q_placeStanzaGo pid { kp with all := false } _ isStart (v :: more))
      · exact Q.nl (q_nextColumn env hs st) (q_placeStanzaGo pid kp _ isStart (v :: more))
    · split
      · exact q_putVerses env hs st _
      · split
        · exact Q.tr (q_putVerses env hs st _) (Q.nl (q_nextColumn env hs _) (q_placeStanzaGo pid kp _ false _))
            (join_take_drop _ _)
        · split
          · split
            · exact Q.tr (Q.nr (q_placeLines env hs _ st isStart v) (Q.addUs env _ _))
                (q_placeStanzaGo pid kp _ false more) (by simp [List.append_bind])
            · exact Q.tr (Q.nr (q_putVerses env hs st _) (Q.addUs env _ _))
                (Q.nl (q_nextColumn env hs _) (q_placeStanzaGo pid kp _ false _)) (join_take_drop _ _)
          · exact Q.nl (q_nextColumn env hs st) (q_placeStanzaGo pid kp _ isStart (v :: more))
termination_by (vs.length, allRank kp, rank env st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; apply Prod.Lex.left; simp_all [allRank]; done)
    | (apply linesLt_rank; apply I4_nextColumn_rank; left; cases e : isEmpty st
       · rfl
       · simp [emptyish, e] at *)

theorem q_placeStanza (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) :
    Q env st (placeStanza env kp st isStart vs) (vs.join.bind (·.notes)) := by
  unfold placeStanza; split <;> exact q_placeStanzaGo env hs _ _ _ _ _

theorem q_putSlot (st : St) (n : Nat) (s : Slot) : Q env st (putSlot st n s) [] :=
  Q.frame (hused := by show st.used ≤ st.used + _; omega)

theorem q_placeCode (g cap0 first : Nat) (cont : Bool) (st : St) (isFirst : Bool) (ls : List Line) :
    Q env st (placeCode env g cap0 first cont st isFirst ls) [] := by
  match ls with
  | [] => unfold placeCode; exact Q.refl env st
  | l0 :: ls' =>
    by_cases h : codeCount env g cap0 first cont st isFirst (l0 :: ls').length = 0
    · unfold placeCode; rw [dif_pos h]
      exact Q.nl (q_nextColumn env hs st) (q_placeCode g cap0 first cont (nextColumn env st) isFirst (l0 :: ls'))
    · unfold placeCode; rw [dif_neg h]
      simp only
      split
      · exact q_putSlot env _ _ _
      · exact Q.nl (q_putSlot env _ _ _) (Q.nl (q_nextColumn env hs _)
          (q_placeCode g cap0 first cont _ false ((l0 :: ls').drop (codeCount env g cap0 first cont st isFirst (l0 :: ls').length))))
termination_by (ls.length, rank env st)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.right _ (I4_nextColumn_rank env st
      (Or.inl (codeCount_zero env g cap0 first cont st isFirst _ (by simp) h)))
  · apply Prod.Lex.left
    simp only [List.length, Nat.succ_eq_add_one] at *
    omega

theorem q_putRepeateds (ls : List Line) (st : St) : Q env st (ls.foldl putRepeated st) [] := by
  induction ls generalizing st with
  | nil => exact Q.refl env st
  | cons l ls ih =>
    simp only [List.foldl]
    exact Q.nl (Q.frame (hused := by show st.used ≤ st.used + 1; omega)) (ih _)

theorem q_tableRowsGo (h capt : List Line) (below : Bool) (st : St) (first : Int) (rows : List (List Line)) :
    Q env st (tableRowsGo env h capt below st first rows) (rows.join.bind (·.notes)) := by
  match rows with
  | [] => unfold tableRowsGo; exact Q.refl env st
  | r :: rest =>
    by_cases h1 : (withCaption capt below r rest).length ≤ env.fitting st (withCaption capt below r rest)
        ∨ st.used = first + h.length
    · unfold tableRowsGo; rw [dif_pos h1]
      exact Q.tr (q_putLines env hs r st) (q_tableRowsGo h capt below _ first rest) (by simp [List.append_bind])
    · unfold tableRowsGo; rw [dif_neg h1]
      simp only
      exact Q.nl (Q.nl (Q.nl (q_nextColumn env hs st) (q_keep env hs _ _)) (q_putRepeateds env _ _))
        (q_tableRowsGo h capt below _ _ (r :: rest))
termination_by (rows.length, if st.used = first + h.length then 0 else 1)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
    have : ¬ st.used = first + h.length := fun e => h1 (Or.inr e)
    simp only [putRepeateds_used, this, ite_true, ite_false]
    decide

theorem q_placeTable (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    Q env st (placeTable env st h rows capt below) ((tableLines h rows capt below).bind (·.notes)) := by
  cases below
  · simp only [placeTable]
    exact Q.tr (Q.tr (q_putLines env hs capt st) (q_putLines env hs h _) rfl) (q_tableRowsGo env hs _ _ _ _ _ _)
      (by simp [tableLines, List.append_bind, List.append_assoc])
  · simp only [placeTable]
    exact Q.tr (Q.tr (q_putLines env hs h st) (q_tableRowsGo env hs _ _ _ _ _ _) rfl) (q_putLines env hs capt _)
      (by simp [tableLines, List.append_bind, List.append_assoc])

theorem q_nextSpread (t : Nat) (st : St) : Q env st (nextSpread env t st) [] := by
  by_cases h : (nextPage env st).page < t
  · unfold nextSpread; rw [dif_pos h]; exact Q.nl (q_nextPage env hs st) (q_nextSpread t (nextPage env st))
  · unfold nextSpread; rw [dif_neg h]; exact q_nextPage env hs st
termination_by t - st.page
decreasing_by simp_wf; have := nextPage_page_gt env st; omega

theorem q_nextUnit (unit : KeepParts) (st : St) : Q env st (nextUnit env unit st) [] := by
  cases unit
  · exact q_nextColumn env hs st
  · exact q_nextPage env hs st
  · exact q_nextSpread env hs _ st

theorem q_partTrial (runBody runPlain : St → St) (X : List Note)
    (hb : ∀ s, Q env s (runBody s) X) (hp : ∀ s, Q env s (runPlain s) X)
    (unit : KeepParts) (fits : St → Bool) (nested whole : Bool) (st : St) :
    Q env st (partTrial env runBody runPlain unit fits nested whole st) X := by
  simp only [partTrial]
  repeat' split
  all_goals first
    | exact hp _
    | exact Q.nr (hp _) (q_flushFigures env hs _)
    | exact Q.nr (hb _) (q_flushFigures env hs _)

theorem q_placeBookPart (runBody runPlain : St → St) (X : List Note)
    (hb : ∀ s, Q env s (runBody s) X) (hp : ∀ s, Q env s (runPlain s) X)
    (initial : St) (unit : KeepParts) (kind : Option Nat) (retained : List Nat) (nested whole : Bool) :
    Q env initial (placeBookPart env runBody runPlain initial unit kind retained nested whole) X := by
  have pt := q_partTrial env hs runBody runPlain X hb hp unit
  simp only [placeBookPart]
  repeat' split
  all_goals first
    | exact hb _
    | exact pt _ _ _ _
    | exact Q.nl (q_nextUnit env hs unit _) (pt _ _ _ _)
    | exact Q.nr (hb _) (Q.addU env _ _)
    | exact Q.nr (pt _ _ _ _) (Q.addU env _ _)
    | exact Q.nr (Q.nl (q_nextUnit env hs unit _) (hb _)) (Q.addU env _ _)

theorem q_acrossGo (h capt : List Line) (below retain fresh retried : Bool) (st : St)
    (gs : List (Bool × List Line)) :
    Q env st (acrossGo env h capt below retain fresh retried st gs) ((gs.bind (·.2)).bind (·.notes)) := by
  match gs with
  | [] => unfold acrossGo; exact Q.refl env st
  | (isHeader, ls) :: remaining =>
    by_cases hr : fresh = true ∧ retainsTail env capt below retain isHeader remaining = true
    · unfold acrossGo; rw [dif_pos hr]
      apply q_placeBookPart env hs
      all_goals intro s
      all_goals refine Q.nl ?_ (q_acrossGo h capt below false true false _ ((isHeader, ls) :: remaining))
      all_goals split
      all_goals first | exact Q.refl env _ | exact q_putRepeateds env _ _
    · by_cases h1 : ls.length ≤ env.fitting st ls ∨ isEmpty st = true
      · unfold acrossGo; rw [dif_neg hr, dif_pos h1]
        exact Q.tr (q_putLines env hs ls st) (q_acrossGo h capt below retain true false _ remaining)
          (by simp [List.append_bind])
      · unfold acrossGo; rw [dif_neg hr, dif_neg h1]
        refine Q.nl ?_ (q_acrossGo h capt below retain false _ _ ((isHeader, ls) :: remaining))
        split
        · exact Q.nl (q_nextColumn env hs st) (q_putRepeateds env _ _)
        · exact q_nextColumn env hs st
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

theorem q_placeTableAcross (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    Q env st (placeTableAcross env st h rows capt below) ((tableLines h rows capt below).bind (·.notes)) := by
  simp only [placeTableAcross]
  rw [← tableGroups_lines]
  exact q_acrossGo env hs _ _ _ _ _ _ _ _

end

/-! ## Controls and rules -/

theorem q_checkNoBreak (env : Env) (st : St) : Q env st (checkNoBreak st) [] := by
  unfold checkNoBreak
  split
  · exact Q.refl env st
  · simp only
    exact Q.nr (Q.ite (Q.refl env st) (Q.addWs env _ st)) Q.frame

theorem q_waitFor (env : Env) (u : Unmet) (k : Nat × Bool) (st : St) : Q env st (waitFor u k st) [] := by
  unfold waitFor; split
  · exact Q.frame
  · exact Q.frame

section
variable (env : Env) (hs : Hyp env)

theorem q_placeKept {α : Type} (kp : Keep) (placeIn : St → Bool → List α → St)
    (T : List α → List Note) (hT : ∀ a b, T (a ++ b) = T a ++ T b)
    (hp : ∀ s b xs, Q env s (placeIn s b xs) (T xs))
    (st : St) (isStart : Bool) (ls : List α) (n : Need) :
    Q env st (placeKept env kp placeIn st isStart ls n) (T ls) := by
  have tl : T (ls.take (ls.length - keptCut kp ls.length)) ++ T (ls.drop (ls.length - keptCut kp ls.length))
      = T ls := by rw [← hT, List.take_append_drop]
  simp only [placeKept]
  apply Q.ite
  · exact hp _ _ _
  · apply Q.ite
    · exact Q.tr (hp _ _ _) (hp _ _ _) tl
    · apply Q.ite
      · exact hp _ _ _
      · exact Q.tr (hp _ _ _) (Q.nl (q_nextColumn env hs _) (hp _ _ _)) tl

/-- The lines of a paragraph with rules, each keeping the lines after it
    and the rule after: the lines free beyond the separator stay within
    what is kept for them. -/
theorem q_putRuledLines (k2 : Nat) (ls : List Line) (st : St) (ba : Base st)
    (o : OkK env (max 1 ((ls.length + k2 : Nat) : Int)) st) :
    OR st (putRuledLines env k2 st ls) (exN (ls.bind (·.notes))) ∧ Base (putRuledLines env k2 st ls) ∧
      OkK env (max 1 (k2 : Int)) (putRuledLines env k2 st ls) := by
  induction ls generalizing st with
  | nil => exact ⟨OR.refl st, ba, by simpa using o⟩
  | cons l ls ih =>
    simp only [putRuledLines]
    have o1 : OkK env (((ls.length + k2 : Nat) : Int) + 1) st := by
      refine o.mono ?_; simp only [List.length]; simp only [Int.max_def]; split <;> omega
    obtain ⟨r1, b1, k1⟩ := q_putLineKeeping env hs (ls.length + k2) st l ba o1
    have e : (((ls.length + k2 : Nat)) : Int) = (ls.length : Int) + (k2 : Int) := by push_cast; rfl
    rw [e] at r1 b1 k1
    obtain ⟨r2, b2, k2'⟩ := ih _ b1 (k1.mono (by simp only [Int.max_def]; split <;> omega))
    refine ⟨?_, b2, k2'⟩
    have := r1.trans r2
    rw [List.cons_bind, exN_append]; exact this

theorem q_commitRuled (st : St) (body : RuledBody) (p : Plan) (hb : RuledOk body) :
    Q env st (commitRuled env st body p) (ruledNotes body) := by
  intro ba oa
  have q1 : Q env st { st with used := st.used + p.before, join := none } [] :=
    Q.frame (hused := by show st.used ≤ st.used + p.before; omega)
  obtain ⟨r1, b1, o1⟩ := q1 ba oa
  have fin : ∀ s : St, OkK env (max 1 (p.after : Int)) s →
      Ok env { s with used := min (s.used + p.after) (max s.used (cap env s - s.noteLines)), join := p.waiting } := by
    intro s o
    have up : s.used ≤ min (s.used + p.after) (max s.used (cap env s - s.noteLines)) := by
      have := Int.le_max_left s.used (cap env s - s.noteLines)
      simp only [Int.min_def]; split <;> omega
    obtain ⟨o1, o2, o | ⟨o, t⟩⟩ := o
    · exact ⟨o1, by rcases o2 with h | h; exact Or.inl (by show 0 ≤ min _ _; omega); exact Or.inr h, Or.inl o⟩
    · refine ⟨o1, by rcases o2 with h | h; exact Or.inl (by show 0 ≤ min _ _; omega); exact Or.inr h, Or.inr ⟨?_, ?_⟩⟩
      · show cap env s - min (s.used + p.after) (max s.used (cap env s - s.noteLines)) - s.noteLines ≤ carrySep env s + 1
        have c0 : 0 ≤ carrySep env s := by have := hs.sep; unfold carrySep; split <;> omega
        simp only [free] at o
        simp only [Int.min_def, Int.max_def] at o ⊢
        split <;> split <;> split at o <;> omega
      · rcases t with t | t | t
        · exact Or.inl (show 1 ≤ min _ _ by omega)
        · exact Or.inr (Or.inl t)
        · exact Or.inr (Or.inr t)
  simp only [commitRuled]
  generalize { st with used := st.used + p.before, join := none } = st1 at r1 b1 o1 ⊢
  cases body with
  | lines kp ls =>
    simp only
    obtain ⟨r2, b2, o2⟩ := q_putRuledLines env hs p.after ls st1 b1
      (o1.mono (by simp only [Int.max_def]; split <;> omega))
    generalize putRuledLines env p.after st1 ls = s2 at r2 b2 o2 ⊢
    refine ⟨?_, b2.of, fin _ o2⟩
    have := (r1.trans r2).trans (OR.of_eq (Y := []) (st := s2)
      (s := { s2 with used := min (s2.used + p.after) (max s2.used (cap env s2 - s2.noteLines)), join := p.waiting })
      (by simp [NM]) ⟨[], by simp [allUnmet]⟩)
    simpa [ruledNotes] using this
  | heading r n ls =>
    simp only
    obtain ⟨r2, b2, o2⟩ := q_putBlock env hs st1 n hb ls b1 o1
    generalize putBlock env st1 n ls = s2 at r2 b2 o2 ⊢
    refine ⟨?_, b2.of, ?_⟩
    · have := (r1.trans r2).trans (OR.of_eq (Y := []) (st := s2)
        (s := { { s2 with headingOnly := isEmpty st || st.headingOnly } with
          used := min (s2.used + p.after) (max s2.used (cap env s2 - s2.noteLines)), join := p.waiting })
        (by simp [NM]) ⟨[], by simp [allUnmet]⟩)
      simpa [ruledNotes] using this
    · exact fin { s2 with headingOnly := isEmpty st || st.headingOnly } (o2.mono (by simp only [Int.max_def]; split <;> omega))

theorem q_splitRuled (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow) (hb : RuledOk body) :
    Q env st (splitRuled env st i b a body rest) (ruledNotes body) := by
  have h0 : Q env st (if isEmpty st = true then st else nextColumn env st) [] :=
    Q.ite (Q.refl env st) (q_nextColumn env hs st)
  cases body with
  | lines kp ls => simp only [splitRuled]; exact Q.nl h0 (q_placeLines env hs _ _ _ _)
  | heading r n ls =>
    simp only [splitRuled]
    generalize (if isEmpty st = true then st else nextColumn env st) = s at h0
    split
    · exact Q.nl h0 (q_commitRuled env hs _ _ _ hb)
    · split
      · exact Q.nl h0 (q_commitRuled env hs _ _ _ hb)
      · exact Q.nl h0 (q_putBlock env hs _ n hb ls)

theorem q_flushUsed (st : St) (x : Int) (hx : 0 ≤ x) :
    Q env st { st with used := st.used + min x (free env st), join := none } [] := by
  · intro ba oa
    refine ⟨OR.of_eq (by simp [NM]) ⟨[], by simp [allUnmet]⟩, ba.of, ?_⟩
    obtain ⟨o1, o2, o3⟩ := oa
    have nl := ba.nl
    have c0 : 0 ≤ carrySep env st := by have := hs.sep; unfold carrySep; split <;> omega
    have fr : free env st = cap env st - st.used - st.noteLines := rfl
    have m : ∀ (x : Int), 0 ≤ x → (0 ≤ free env st → min x (free env st) ≥ 0 ∧ min x (free env st) ≤ free env st) ∧
        (free env st < 0 → min x (free env st) = free env st) := by
      intro x hx; simp only [Int.min_def]; constructor <;> intro h <;> split <;> omega
    obtain ⟨m1, m2⟩ := m x hx
    refine ⟨o1, ?_, ?_⟩
    · show 0 ≤ st.used + min x (free env st) ∨ 0 < st.noteLines
      by_cases f0 : 0 ≤ free env st
      · have := m1 f0; rcases o2 with h | h
        · exact Or.inl (by omega)
        · exact Or.inr h
      · have := m2 (by omega)
        by_cases n0 : 0 < st.noteLines
        · exact Or.inr n0
        · exact Or.inl (by omega)
    · rcases o3 with o | ⟨o, t⟩
      · exact Or.inl o
      · refine Or.inr ⟨?_, ?_⟩
        · show cap env st - (st.used + min x (free env st)) - st.noteLines ≤ carrySep env st + 1
          by_cases f0 : 0 ≤ free env st
          · have := m1 f0; omega
          · have := m2 (by omega); omega
        · show 1 ≤ st.used + min x (free env st) ∨ 0 < st.noteLines ∨ st.notes ≠ []
          by_cases f0 : 0 ≤ free env st
          · have := m1 f0
            rcases t with t | t | t
            · exact Or.inl (by omega)
            · exact Or.inr (Or.inl t)
            · exact Or.inr (Or.inr t)
          · have := m2 (by omega)
            by_cases n0 : 0 < st.noteLines
            · exact Or.inr (Or.inl n0)
            · exact Or.inl (by omega)

theorem q_flushJoin (st : St) : Q env st (flushJoin env st) [] := by
  unfold flushJoin; split
  · exact Q.refl env st
  · exact q_flushUsed env hs st _ (Int.ofNat_nonneg _)

theorem q_placeRuledFresh (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow) (hb : RuledOk body) :
    Q env st (placeRuledFresh env st i b a body rest) (ruledNotes body) := by
  have h1 : Q env st (if body.recto = true then parityStart env odd st else st) [] :=
    Q.ite (q_parityStart env hs _ _) (Q.refl env st)
  simp only [placeRuledFresh]
  generalize (if body.recto = true then parityStart env odd st else st) = s1 at h1
  have h2 : ∀ s2 : St, Q env st s2 [] →
      Q env st (if planNeed env s2 body (planOf env s2 i b a body rest none) ≤ free env s2 then
          commitRuled env s2 body (planOf env s2 i b a body rest none)
        else if isEmpty s2 = true then splitRuled env s2 i b a body rest
        else if planNeed env (nextColumn env s2) body (planOf env (nextColumn env s2) i b a body rest none)
            ≤ free env (nextColumn env s2) then
          commitRuled env (nextColumn env s2) body (planOf env (nextColumn env s2) i b a body rest none)
        else splitRuled env (nextColumn env s2) i b a body rest) (ruledNotes body) := by
    intro s2 e
    split
    · exact Q.nl e (q_commitRuled env hs _ _ _ hb)
    · split
      · exact Q.nl e (q_splitRuled env hs _ _ _ _ _ _ hb)
      · split
        · exact Q.nl e (Q.nl (q_nextColumn env hs _) (q_commitRuled env hs _ _ _ hb))
        · exact Q.nl e (Q.nl (q_nextColumn env hs _) (q_splitRuled env hs _ _ _ _ _ _ hb))
  apply h2
  cases body with
  | heading r n ls =>
    cases r <;> simp only [ruledKeep]
    · exact Q.nl h1 (q_keep env hs _ _)
    · exact h1
  | lines kp ls =>
    simp only [ruledKeep]
    split
    · split
      · exact Q.nl h1 (q_keep env hs _ _)
      · exact h1
    · exact h1

theorem q_placeRuled (st : St) (i : Nat) (b a j : Bool) (body : RuledBody) (rest : List Flow) (hb : RuledOk body) :
    Q env st (placeRuled env st i b a j body rest) (ruledNotes body) := by
  unfold placeRuled
  split
  · split
    · exact q_commitRuled env hs _ _ _ hb
    · exact Q.nl (q_flushJoin env hs st) (q_placeRuledFresh env hs _ _ _ _ _ _ hb)
  · exact q_placeRuledFresh env hs _ _ _ _ _ _ hb

end

/-! ## The flows `I1_paginate_order` admits -/

mutual
/-- No box, no switch of the columns, and headings of one grid line or
    more (`hbSpan` of `headingBlock`, Paginate.hs, is `max 1 least` or
    more). -/
def plainFlow : Flow → Prop
  | .boxed _ _ _ _ => False
  | .switchColumns _ => False
  | .heading _ n _ => 1 ≤ n
  | .ruled _ _ _ _ body => RuledOk body
  | .bookPart _ _ _ body => plainFlows body
  | _ => True
termination_by f => sizeOf f
def plainFlows : List Flow → Prop
  | [] => True
  | g :: r => plainFlow g ∧ plainFlows r
termination_by fs => sizeOf fs
end

theorem plainFlows_append : ∀ (a b : List Flow), plainFlows a → plainFlows b → plainFlows (a ++ b)
  | [], _, _, hb => hb
  | g :: r, b, ha, hb => by
    simp only [List.cons_append, plainFlows] at ha ⊢
    exact ⟨ha.1, plainFlows_append r b ha.2 hb⟩

theorem plainFlows_flatten (fs : List Flow) (h : plainFlows fs) : plainFlows (flattenParts fs) := by
  match fs with
  | [] => simp [flattenParts, plainFlows]
  | f :: r =>
    simp only [plainFlows] at h
    have hr := plainFlows_flatten r h.2
    cases f with
    | bookPart u k i b =>
      simp only [plainFlow] at h
      simp only [flattenParts]
      exact plainFlows_append _ _ (plainFlows_flatten b h.1) hr
    | boxed j kb ka b => simp only [plainFlow] at h; exact h.1.elim
    | _ => simp only [flattenParts, plainFlows]; exact ⟨h.1, hr⟩
termination_by sizeOf fs

theorem Q.bookEnv {env : Env} (u : KeepParts) {a b : St} {X : List Note}
    (h : Q { env with keepParts := u, inBookPart := true } a b X) : Q env a b X := h

theorem q_setFirst (env : Env) (st : St) (c : Nat) : Q env st { st with columns := c, firstLine := 0 } [] := by
  intro ba oa
  exact ⟨OR.of_eq (by simp [NM]) ⟨[], by simp [allUnmet]⟩,
    ⟨ba.box, Int.le_refl _, ba.spaces, ba.setAdj, ba.res, ba.nl⟩, ok_of rfl rfl rfl rfl rfl rfl oa⟩

theorem q_settle (env : Env) (st : St) (s a : Bool) (c : Prop) [Decidable c] :
    Q env st { st with seen := s, lastDeferred := a, spaces := if c then st.spaces else [] } [] := by
  intro ba oa
  refine ⟨OR.of_eq (by simp [NM]) ⟨[], by simp [allUnmet]⟩,
    ⟨ba.box, ba.first, ?_, ba.setAdj, ba.res, ba.nl⟩, ok_of rfl rfl rfl rfl rfl rfl oa⟩
  show ∀ x ∈ (if c then st.spaces else []), 0 ≤ x.2
  split
  · exact ba.spaces
  · intro x m; cases m

theorem q_pageFigurePlace (env : Env) (hs : Hyp env) (st : St) (i : Nat)
    (c : st.deferred.isEmpty ∧ st.column = 0 ∧ st.used = 0 ∧ st.notes.isEmpty ∧ st.noteLines = 0) :
    Q env st (pageFigure env { st with adjust := 0 } i) [] := by
  intro ba oa
  obtain ⟨_, _, u0, n0, l0⟩ := c
  refine ⟨OR.of_eq (by simp [NM, pageFigure, pagesNotes_cons])
    ⟨[], by simp [allUnmet, pageFigure, List.reverse_cons, List.append_bind]⟩,
    ⟨ba.box, ba.first, ba.spaces, ba.setAdj, ba.res, ba.nl⟩, ?_, ?_, ?_⟩
  · show 1 ≤ env.capacity + 0 - boxAfter st
    simp only [boxAfter, ba.box]; have := hs.cap; omega
  · exact Or.inl (show 0 ≤ st.used by omega)
  · left
    obtain ⟨_, _, o | ⟨_, t⟩⟩ := oa
    · exact o
    · exfalso
      have ne : st.notes = [] := by
        cases e : st.notes with
        | nil => rfl
        | cons _ _ => rw [e] at n0; simp [List.isEmpty] at n0
      rcases t with t | t | t
      · omega
      · omega
      · exact t ne

theorem flowNotes_ruled' (i : Nat) (b a j : Bool) (body : RuledBody) :
    flowNotes (.ruled i b a j body) = ruledNotes body := by
  cases body <;> simp [flowNotes, ruledNotes]

mutual
theorem q_place (env : Env) (hs : Hyp env) (st : St) (f : Flow) (rest : List Flow) (hp : plainFlow f) :
    Q env st (place env st f rest) (flowNotes f) := by
  cases f with
  | paragraph kp ls => simp only [place, flowNotes]; exact q_placeLines env hs _ _ _ _
  | stanza kp vs => simp only [place, flowNotes]; exact q_placeStanza env hs _ _ _ _
  | ruled i b a j body =>
    simp only [plainFlow] at hp
    simp only [place]; rw [flowNotes_ruled']; exact q_placeRuled env hs _ _ _ _ _ _ _ hp
  | wrapped i n beside =>
    simp only [place, flowNotes]
    have h : Q env st (placeLines env defaultKeep (putSlot (keep env (flushFigures env st)
        (fun s => needIn env s ⟨max n beside.length, noteLinesOf beside⟩ ⟨0, 0⟩)) 0
        (.wrapped i)) false beside) (beside.bind (·.notes)) :=
      Q.nl (Q.nl (q_flushFigures env hs st) (q_keep env hs _ _)) (Q.nl (q_putSlot env _ _ _) (q_placeLines env hs _ _ _ _))
    refine Q.ite (Q.nr h (Q.frame (hused := ?_))) h
    exact Int.le_max_right _ _
  | continued kp ls => simp only [place, flowNotes]; exact q_placeLines env hs _ _ _ _
  | heading recto n ls =>
    simp only [plainFlow] at hp
    simp only [place, flowNotes]
    have h1 : Q env st (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) [] :=
      Q.ite (q_parityStart env hs _ _) (q_keep env hs _ _)
    generalize (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) = s1 at h1
    exact Q.nl (Q.ite h1 (Q.nl h1 (q_nextColumn env hs _))) (q_putBlock env hs _ n hp ls)
  | figure i n =>
    simp only [place, flowNotes]
    exact Q.ite Q.frame (Q.ite (q_putSlot env _ _ _) Q.frame)
  | pageFigure i =>
    simp only [place, flowNotes]
    split
    · rename_i c
      exact q_pageFigurePlace env hs st i (by simpa using c)
    · exact Q.frame
  | brk k => simp only [place, flowNotes]; exact Q.frame
  | sectionStart sec k => simp only [place, flowNotes]; exact Q.frame
  | space n => simp only [place, flowNotes]; exact q_placeSpaceFlow env _ _
  | needLines n => simp only [place, flowNotes]; exact Q.refl env st
  | blank n => simp only [place, flowNotes]; exact Q.refl env st
  | noBreak => simp only [place, flowNotes]; exact Q.refl env st
  | noBreakLines n => simp only [place, flowNotes]; exact Q.refl env st
  | keepNext n => simp only [place, flowNotes]; exact Q.refl env st
  | switchColumns n => simp only [plainFlow] at hp
  | restoreColumns =>
    simp only [place, flowNotes]
    exact Q.ite (q_setFirst env st _) (Q.nr (q_nextPage env hs st) (q_setFirst env _ _))
  | adjustLines k => simp only [place, flowNotes]; exact Q.refl env st
  | bookPart u k r body =>
    simp only [plainFlow] at hp
    simp only [place, flowNotes]; exact q_runFlows env hs st body rest hp
  | boxed i kb ka body => simp only [plainFlow] at hp
  | code g c first cont ls => simp only [place, flowNotes]; exact q_placeCode env hs _ _ _ _ _ _ _
  | defTerm ls =>
    simp only [place, flowNotes]
    split
    · exact Q.nl (q_keep env hs _ _) (q_placeLines env hs _ _ _ _)
    · exact q_placeLines env hs _ _ _ _
  | table sp0 h rows capt below =>
    simp only [place, flowNotes]
    split
    · refine Q.nl ?_ (q_placeTable env hs _ _ _ _ _)
      apply Q.ite
      · refine Q.frame (hused := ?_)
        show st.used ≤ st.used + _
        have := Int.le_max_left 0 (min (if st.used = top st then 0 else (sp0 : Int)) (free env st))
        omega
      · exact Q.nl (q_nextColumn env hs _) (q_keep env hs _ _)
    · refine Q.nl ?_ (q_placeTableAcross env hs _ _ _ _ _)
      apply Q.ite
      · refine Q.frame (hused := ?_)
        show st.used ≤ st.used + (if st.used = top st then 0 else (sp0 : Int))
        split <;> omega
      · exact q_nextColumn env hs _
termination_by (flowWeight f, 0)
decreasing_by all_goals simp_wf; (try subst_vars); apply Prod.Lex.left; simp only [flowWeight]; omega

theorem q_placeFlow (env : Env) (hs : Hyp env) (st : St) (f : Flow) (rest : List Flow) (hp : plainFlow f) :
    Q env st (placeFlow env st f rest) (flowNotes f) := by
  have pl : ∀ kp s b xs, Q env s (placeLines env kp s b xs) (xs.bind (·.notes)) :=
    fun kp s b xs => q_placeLines env hs kp s b xs
  unfold placeFlow
  split
  · simp only [flowNotes]; exact q_placeKept env hs _ _ _ (fun a b => List.append_bind a b _) (pl _) st true _ _
  · simp only [flowNotes]
    exact q_placeKept env hs _ _ (fun vs => vs.join.bind (·.notes))
      (fun a b => by simp only [join_append', List.append_bind]) (fun s b xs => q_placeStanza env hs _ s b xs) st true _ _
  · simp only [flowNotes]; exact q_placeKept env hs _ _ _ (fun a b => List.append_bind a b _) (pl _) st false _ _
  · simp only [flowNotes]
    exact Q.nl (Q.ite (Q.refl env st) (q_keep env hs _ _))
      (q_placeKept env hs _ _ _ (fun a b => List.append_bind a b _) (pl _) _ true _ _)
  · exact q_place env hs _ _ _ hp
termination_by (flowWeight f, 1)
decreasing_by all_goals simp_wf; apply Prod.Lex.right; decide

theorem q_step (env : Env) (hs : Hyp env) (st : St) (f : Flow) (rest : List Flow) (hp : plainFlow f) :
    Q env st (step env st f rest) (flowNotes f) := by
  have general : ∀ (a : Bool) (c : Prop) [Decidable c], Q env st (
      let X := if waitsBehind (applyBreaks env st) f
        then checkNoBreak (place env (applyBreaks env st) f rest)
        else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest)
      { X with seen := true, lastDeferred := a, spaces := if c then X.spaces else [] } : St) (flowNotes f) := by
    intro a c _
    have h : Q env st (if waitsBehind (applyBreaks env st) f
      then checkNoBreak (place env (applyBreaks env st) f rest)
      else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest))
        (flowNotes f) := by
      apply Q.ite
      · exact Q.nl (q_applyBreaks env hs st) (Q.nr (q_place env hs _ _ _ hp) (q_checkNoBreak env _))
      · exact Q.nl (Q.nl (q_applyBreaks env hs st) (Q.nl (q_needBefore env hs _ _) (q_placeBlank env hs _ _ _)))
          (Q.nr (q_placeFlow env hs _ _ _ hp) (q_checkNoBreak env _))
    exact Q.nr h (q_settle env _ _ _ _)
  have ctl : ∀ (u : Unmet) (k : Nat × Bool), Q env st (if st.seen = false ∨ st.lastDeferred = true then addUnmet u st
      else waitFor u k st) [] := fun u k => Q.ite (Q.addU env u st) (q_waitFor env u k st)
  cases f with
  | needLines n => simp only [step, flowNotes]; exact q_needMore env hs _ _
  | bookPart u k r body =>
    simp only [plainFlow] at hp
    simp only [step, flowNotes]
    refine Q.nl (b := if r = [] then st else applyBreaks env st) (Q.ite (Q.refl env st) (q_applyBreaks env hs st)) ?_
    have hs' : Hyp { env with keepParts := u, inBookPart := true } := ⟨hs.sep, hs.cap⟩
    apply q_placeBookPart env hs
    · intro s; exact Q.bookEnv u (q_runFlows { env with keepParts := u, inBookPart := true } hs' s body rest hp)
    · intro s; have := q_runFlows { env with keepParts := u, inBookPart := true } hs' s (flattenParts body) rest
        (plainFlows_flatten body hp)
      rw [sourceNotes_flatten] at this; exact Q.bookEnv u this
  | adjustLines k =>
    simp only [step, flowNotes]
    exact Q.nl (q_applyBreaks env hs st) (q_adjust env hs _ k)
  | noBreak => simp only [step, flowNotes]; exact ctl _ _
  | noBreakLines n =>
    cases n with
    | zero => simp only [step, flowNotes]; exact Q.refl env st
    | succ m => simp only [step, flowNotes]; exact ctl _ _
  | keepNext n => simp only [step, flowNotes]; exact ctl _ _
  | blank n =>
    simp only [step, flowNotes]
    exact Q.ite (Q.refl env st) Q.frame
  | brk k => simp only [step]; exact q_place env hs st (.brk k) rest hp
  | sectionStart sec k => simp only [step]; exact q_place env hs st (.sectionStart sec k) rest hp
  | space n =>
    simp only [step, flowNotes]
    exact Q.nl (Q.nl (q_applyBreaks env hs st) (q_needBeforeSpaces env hs _)) (q_placeSpace env _ _)
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

theorem q_runFlows (env : Env) (hs : Hyp env) (st : St) (fs : List Flow) (rest : List Flow) (hp : plainFlows fs) :
    Q env st (runFlows env st fs rest) (sourceNotes fs) := by
  match fs with
  | [] => unfold runFlows; simp only [sourceNotes]; exact Q.refl env st
  | g :: more =>
    simp only [plainFlows] at hp
    unfold runFlows
    exact Q.tr (q_step env hs st g (more ++ rest) hp.1) (q_runFlows env hs _ more rest hp.2) (by simp [sourceNotes])
termination_by (flowsWeight fs, 3)
decreasing_by
  all_goals simp_wf
  all_goals apply Prod.Lex.left; simp only [flowsWeight]; omega
end

theorem q_placeAll (env : Env) (hs : Hyp env) (flows : List Flow) (st : St) (hp : plainFlows flows) :
    Q env st (placeAll env st flows) (sourceNotes flows) ∧ (placeAll env st flows).pending = [] := by
  induction flows generalizing st with
  | nil =>
    simp only [placeAll, sourceNotes]
    have a := Q.addWs env st.noBreak st
    generalize st.noBreak.foldl (fun s w => addUnmet w.1 s) st = s1 at a
    refine ⟨?_, ?_⟩
    · split
      · exact Q.nl (Q.nr a Q.frame) (q_flushDeferred env hs _)
      · split
        · exact Q.nl (Q.nl (Q.nr a Q.frame) (Q.dropBlanks env _ _)) (q_flushDeferred env hs _)
        · exact Q.nl (Q.nl (Q.nl (Q.nr a Q.frame) (q_nextColumn env hs _)) (Q.dropBlanks env _ _))
            (q_flushDeferred env hs _)
    · repeat' split
      all_goals exact flushDeferred_pending env _
  | cons f rest ih =>
    simp only [plainFlows] at hp
    simp only [placeAll]
    obtain ⟨a, b⟩ := ih (step env st f rest) hp.2
    exact ⟨Q.tr (q_step env hs st f rest hp.1) a (by simp [sourceNotes]), b⟩

/-! ## The order of the notes on the pages (root ADR 0444 I1) -/

/-- The note lines of the pages are the lines of the notes of the
    manuscript, in the manuscript's order, but for the notes reported
    unplaceable. -/
theorem paginate_order (env : Env) (hs : Hyp env) (flows : List Flow) (hp : plainFlows flows) :
    kd (dropIds (paginate env flows)) (ex (pagesNotes (paginate env flows).done)) =
      kd (dropIds (paginate env flows)) (exN (sourceNotes flows)) := by
  obtain ⟨q, p⟩ := q_placeAll env hs flows (initialState env) hp
  have b0 : Base (initialState env) := ⟨rfl, Int.le_refl _, (fun _ m => by cases m), rfl, rfl, Int.le_refl _⟩
  have o0 : Ok env (initialState env) := ⟨by show 1 ≤ env.capacity + 0 - 0; have := hs.cap; omega,
    Or.inl (Int.le_refl _), Or.inl rfl⟩
  obtain ⟨⟨_, e⟩, _, _⟩ := q b0 o0
  obtain ⟨c1, c2, _⟩ := closePage_facts env (placeAll env (initialState env) flows)
  have d : dropIds (paginate env flows) = dropIds (placeAll env (initialState env) flows) := by
    simp only [dropIds, paginate]; exact congrArg dropsOf c2
  have n : ex (pagesNotes (paginate env flows).done) = NM (placeAll env (initialState env) flows) := by
    simp only [paginate]; rw [c1, NM, p, ex_append]; simp
  rw [d, n, e]; rfl

theorem kd_split {D : List Nat} : ∀ (L M1 M2 : List (Nat × Nat)), kd D L = M1 ++ M2 →
    ∃ L1 L2, L = L1 ++ L2 ∧ kd D L1 = M1 ∧ kd D L2 = M2
  | [], M1, M2, h => by
    have : M1 = [] ∧ M2 = [] := append_eq_nil'.mp h.symm
    exact ⟨[], [], rfl, by rw [this.1]; rfl, by rw [this.2]; rfl⟩
  | x :: xs, M1, M2, h => by
    by_cases m : x.1 ∈ D
    · have h' : kd D xs = M1 ++ M2 := by simpa [kd, List.filter, m] using h
      obtain ⟨L1, L2, e, e1, e2⟩ := kd_split xs M1 M2 h'
      exact ⟨x :: L1, L2, by rw [e]; rfl, by simpa [kd, List.filter, m] using e1, e2⟩
    · have h' : x :: kd D xs = M1 ++ M2 := by simpa [kd, List.filter, m] using h
      cases M1 with
      | nil =>
        exact ⟨[], x :: xs, rfl, rfl, by simpa using h⟩
      | cons y ys =>
        simp only [List.cons_append, List.cons.injEq] at h'
        obtain ⟨hy, ht⟩ := h'
        obtain ⟨L1, L2, e, e1, e2⟩ := kd_split xs ys M2 ht
        exact ⟨x :: L1, L2, by rw [e]; rfl, by simp [kd, List.filter, m] at e1 ⊢; rw [hy]; exact ⟨rfl, e1⟩, e2⟩

theorem filter_filter_of {α : Type} (p q : α → Bool) (h : ∀ x, p x = true → q x = true) :
    ∀ L : List α, (L.filter q).filter p = L.filter p
  | [] => rfl
  | x :: xs => by
    have ih := filter_filter_of p q h xs
    by_cases hq : q x = true
    · by_cases hp : p x = true
      · simp [List.filter, hq, hp, ih]
      · simp [List.filter, hq, hp, ih]
    · have hp : p x = false := by
        cases e : p x
        · rfl
        · exact absurd (h x e) hq
      simp [List.filter, hq, hp, ih]

theorem filt_kd {D : List Nat} {i : Nat} (h : i ∉ D) (L : List (Nat × Nat)) : filt i (kd D L) = filt i L := by
  unfold filt kd
  apply filter_filter_of
  intro x e
  have : x.1 = i := by simpa using e
  rw [this]; simp [h]

theorem distinct_right : ∀ (xs ys : List Nat), Distinct (xs ++ ys) → Distinct ys
  | [], _, h => h
  | _ :: xs, ys, h => distinct_right xs ys h.2

theorem distinct_apart : ∀ (xs ys : List Nat), Distinct (xs ++ ys) → ∀ i, i ∈ ys → i ∉ xs
  | [], _, _, _, _, m => by cases m
  | x :: xs, ys, h, i, my, m => by
    cases m with
    | head => exact h.1 (List.mem_append_of_mem_right _ my)
    | tail _ m => exact distinct_apart xs ys h.2 i my m

/-- Root ADR 0444 I1 on the grid mode: when the mark of note `a` comes
    before the mark of note `b` in the manuscript, the lines of the pages
    split into a front holding every line of `a` and a back holding every
    line of `b`, unless one of them is reported unplaceable.  It assumes
    the flows of `plainFlows`, distinct note ids, a separator of 0 lines
    or more and a column of 1 grid line or more. -/
theorem I1_paginate_order (env : Env) (hs : Hyp env) (flows : List Flow) (hp : plainFlows flows)
    (hd : Distinct ((sourceNotes flows).map (·.id))) (a b : Note) (A B C : List Note)
    (ho : sourceNotes flows = A ++ a :: (B ++ b :: C))
    (na : ¬ ∃ c, Unmet.unplaceableFootnote a.id c ∈ allUnmet (paginate env flows))
    (nb : ¬ ∃ c, Unmet.unplaceableFootnote b.id c ∈ allUnmet (paginate env flows)) :
    ∃ L1 L2, ex (pagesNotes (paginate env flows).done) = L1 ++ L2 ∧ filt b.id L1 = [] ∧ filt a.id L2 = [] := by
  have e := paginate_order env hs flows hp
  have nd : ∀ n : Note, (¬ ∃ c, Unmet.unplaceableFootnote n.id c ∈ allUnmet (paginate env flows)) →
      n.id ∉ dropIds (paginate env flows) := by
    intro n h m
    apply h
    simp only [dropIds] at m
    generalize allUnmet (paginate env flows) = us at m ⊢
    induction us with
    | nil => cases m
    | cons u us ih =>
      simp only [dropsOf] at m
      cases u with
      | unplaceableFootnote j c =>
        simp only [dropId] at m
        cases m with
        | head => exact ⟨c, List.Mem.head _⟩
        | tail _ m => obtain ⟨c', m'⟩ := ih m; exact ⟨c', List.Mem.tail _ m'⟩
      | _ => simp only [dropId] at m; obtain ⟨c', m'⟩ := ih m; exact ⟨c', List.Mem.tail _ m'⟩
  rw [ho, show A ++ a :: (B ++ b :: C) = (A ++ a :: B) ++ (b :: C) by simp, exN_append, kd_append] at e
  obtain ⟨L1, L2, eL, e1, e2⟩ := kd_split _ _ _ e
  refine ⟨L1, L2, eL, ?_, ?_⟩
  · rw [← filt_kd (nd b nb), e1, filt_kd (nd b nb)]
    have hb : b.id ∉ (A ++ a :: B).map (·.id) := by
      rw [ho, show A ++ a :: (B ++ b :: C) = (A ++ a :: B) ++ (b :: C) by simp, List.map_append] at hd
      exact distinct_apart _ _ hd b.id (List.Mem.head _)
    exact filt_exN_ne _ _ hb
  · rw [← filt_kd (nd a na), e2, filt_kd (nd a na)]
    have ha : a.id ∉ (b :: C).map (·.id) := by
      rw [ho, List.map_append, List.map_cons] at hd
      have h2 := (distinct_right _ _ hd).1
      intro m; apply h2
      rw [List.map_append]; exact List.mem_append_of_mem_right _ m
    exact filt_exN_ne _ _ ha

end Order
end WholePagination
