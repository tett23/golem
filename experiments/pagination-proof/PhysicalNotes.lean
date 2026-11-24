/-
Root ADR 0352 invariant 5 for the footnotes of the free placement.

Every line of every footnote body read is placed once on the pages of
`paginate` of Physical.lean, and the lines of one note are placed from its
first line to its last.  The statement is made note by note (`filt`): the
lines of different notes may come in another order than the manuscript's
(README.md).  No note is dropped: a note that fits in no column is the
error `footnoteTooTall`, and `paginate` fails with `noProgress` when notes
are still carried on after the last column (`drainCarry`).
-/
import Physical

namespace PhysicalPagination
namespace Notes

/-! ## The lines of notes -/

/-- The lines `first`, `first + 1`, ... of note `i`, `n` of them. -/
def seg (i : Nat) : Nat → Nat → List (Nat × Nat)
  | _, 0 => []
  | f, n + 1 => (i, f) :: seg i (f + 1) n

theorem seg_add (i : Nat) : ∀ (f a b : Nat), seg i f (a + b) = seg i f a ++ seg i (f + a) b
  | f, 0, b => by simp [seg]
  | f, a + 1, b => by
    have := seg_add i (f + 1) a b
    rw [Nat.succ_add]
    show (i, f) :: seg i (f + 1) (a + b) = (i, f) :: seg i (f + 1) a ++ seg i (f + (a + 1)) b
    rw [this, show f + 1 + a = f + (a + 1) by omega]; rfl

/-- The lines of a note part. -/
def partLines (p : NotePart) : List (Nat × Nat) := seg p.1 p.2.1 p.2.2

def ex (ps : List NotePart) : List (Nat × Nat) := ps.bind partLines

/-- The lines of a note of the manuscript. -/
def noteSeg (n : Note) : List (Nat × Nat) := seg n.id 0 n.lines

def exN (ns : List Note) : List (Nat × Nat) := ns.bind noteSeg

theorem ex_append (a b : List NotePart) : ex (a ++ b) = ex a ++ ex b := List.append_bind _ _ _
theorem exN_append (a b : List Note) : exN (a ++ b) = exN a ++ exN b := List.append_bind _ _ _
@[simp] theorem ex_nil : ex [] = [] := rfl
@[simp] theorem exN_nil : exN [] = [] := rfl
theorem ex_cons (p : NotePart) (ps : List NotePart) : ex (p :: ps) = partLines p ++ ex ps := rfl
theorem exN_cons (n : Note) (ns : List Note) : exN (n :: ns) = noteSeg n ++ exN ns := rfl

/-- The lines of note `i` among `a`. -/
def filt (i : Nat) (a : List (Nat × Nat)) : List (Nat × Nat) := a.filter (fun x => x.1 == i)

theorem filt_append (i : Nat) (a b : List (Nat × Nat)) : filt i (a ++ b) = filt i a ++ filt i b := by
  induction a with
  | nil => rfl
  | cons x xs ih =>
    simp only [filt, List.cons_append, List.filter] at *
    split <;> simp [ih]

@[simp] theorem filt_nil (i : Nat) : filt i [] = [] := rfl

theorem append_eq_nil' {α : Type} {a b : List α} : a ++ b = [] ↔ a = [] ∧ b = [] := by
  cases a <;> simp

/-! ## The splits of notes -/

theorem splitNotes_lines : ∀ (r : Nat) (ns : List Note),
    ex (splitNotes r ns).1 ++ ex (splitNotes r ns).2 = exN ns
  | _, [] => rfl
  | r, ⟨i, len⟩ :: rest => by
    have map_rest : ex (rest.map (fun n => (n.id, 0, n.lines))) = exN rest := by
      induction rest with
      | nil => rfl
      | cons n ns ih => simp only [List.map, ex_cons, exN_cons, ih]; rfl
    simp only [splitNotes]
    split
    · have := splitNotes_lines (r - len) rest
      simp only [ex_cons, exN_cons, List.append_assoc, this]; rfl
    · split
      · rename_i h1 h2
        simp only [ex_cons, ex_nil, List.append_nil, map_rest, exN_cons, noteSeg, partLines]
        rw [show seg i 0 len = seg i 0 r ++ seg i (0 + r) (len - r) by rw [← seg_add]; congr 1; omega]
        simp [List.append_assoc]
      · simp only [ex_cons, ex_nil, List.nil_append, map_rest, exN_cons]; rfl

theorem splitCarried_lines (n : Nat) (ps : List NotePart) :
    ex (splitCarried n ps).1 ++ ex (splitCarried n ps).2 = ex ps := by
  induction ps generalizing n with
  | nil => cases n <;> rfl
  | cons p ps ih =>
    obtain ⟨i, o, c⟩ := p
    cases n with
    | zero => rfl
    | succ r =>
      simp only [splitCarried]
      split
      · simp only [ex_cons, List.append_assoc, ih]
      · rename_i h
        simp only [ex_cons, ex_nil, List.append_nil, partLines]
        rw [show seg i o c = seg i o (r + 1) ++ seg i (o + (r + 1)) (c - (r + 1)) by rw [← seg_add]; congr 1; omega]
        simp [List.append_assoc]

/-! ## What the state holds -/

/-- The note parts of pages, in the order of the pages. -/
def pagesNotes (ps : List PageOut) : List NotePart := ps.bind (·.notes)

theorem pagesNotes_append (a b : List PageOut) : pagesNotes (a ++ b) = pagesNotes a ++ pagesNotes b :=
  List.append_bind _ _ _

theorem pagesNotes_snoc (l : List PageOut) (p : PageOut) : pagesNotes (l ++ [p]) = pagesNotes l ++ p.notes := by
  simp [pagesNotes, List.append_bind]

theorem pagesNotes_cons (p : PageOut) (done : List PageOut) :
    pagesNotes (p :: done).reverse = pagesNotes done.reverse ++ p.notes := by
  simp [pagesNotes, List.reverse_cons, List.append_bind]

/-- The note lines of the pages closed (kept last first in `done`), of the
    current column and carried on to the next column. -/
def NM (st : St) : List (Nat × Nat) := ex (pagesNotes st.done.reverse) ++ ex st.notes ++ ex st.carry

/-! ## Notes added by lines (the manuscript's note ids apart) -/

/-- No note has lines in both. -/
def Disj (a b : List (Nat × Nat)) : Prop := ∀ i, filt i a = [] ∨ filt i b = []

/-- The notes of the manuscript are apart: no two of them share a line. -/
def Sep : List Note → Prop
  | [] => True
  | n :: ns => Disj (noteSeg n) (exN ns) ∧ Sep ns

theorem Disj.append_right {a b c : List (Nat × Nat)} : Disj a (b ++ c) ↔ Disj a b ∧ Disj a c := by
  constructor
  · intro h
    refine ⟨fun i => ?_, fun i => ?_⟩ <;> rcases h i with h | h <;> simp_all [filt_append, append_eq_nil']
  · intro ⟨h1, h2⟩ i
    rcases h1 i with h | h
    · exact Or.inl h
    · rcases h2 i with h' | h'
      · exact Or.inl h'
      · exact Or.inr (by rw [filt_append, h, h']; rfl)

theorem Disj.append_left {a b c : List (Nat × Nat)} : Disj (a ++ b) c ↔ Disj a c ∧ Disj b c := by
  constructor
  · intro h
    refine ⟨fun i => ?_, fun i => ?_⟩ <;> rcases h i with h | h <;> simp_all [filt_append, append_eq_nil']
  · intro ⟨h1, h2⟩ i
    rcases h1 i with h | h
    · rcases h2 i with h' | h'
      · exact Or.inl (by rw [filt_append, h, h']; rfl)
      · exact Or.inr h'
    · exact Or.inr h

theorem Sep.append : ∀ (a b : List Note), Sep (a ++ b) → Sep a ∧ Sep b ∧ Disj (exN a) (exN b)
  | [], b, h => ⟨trivial, h, fun i => Or.inl rfl⟩
  | n :: ns, b, h => by
    have h' : Disj (noteSeg n) (exN (ns ++ b)) ∧ Sep (ns ++ b) := h
    obtain ⟨d, s⟩ := h'
    obtain ⟨s1, s2, d2⟩ := Sep.append ns b s
    rw [exN_append, Disj.append_right] at d
    refine ⟨⟨d.1, s1⟩, s2, ?_⟩
    rw [exN_cons, Disj.append_left]
    exact ⟨d.2, d2⟩

def Fresh (st : St) (X : List Note) : Prop := Disj (NM st) (exN X) ∧ Sep X

/-- From `st` to `s` the notes `X` are read: their lines are added, note by
    note, when they are new. -/
def Rel (st s : St) (X : List Note) : Prop := Fresh st X → ∀ i, filt i (NM s) = filt i (NM st ++ exN X)

theorem Rel.refl (st : St) : Rel st st [] := fun _ i => by simp

theorem Rel.trans {a b c : St} {X1 X2 : List Note} (h1 : Rel a b X1) (h2 : Rel b c X2) :
    Rel a c (X1 ++ X2) := by
  intro ⟨d, s⟩
  obtain ⟨s1, s2, d12⟩ := Sep.append X1 X2 s
  rw [exN_append, Disj.append_right] at d
  have r1 := h1 ⟨d.1, s1⟩
  have f2 : Fresh b X2 := by
    refine ⟨fun i => ?_, s2⟩
    rcases d.2 i with e | e
    · rcases d12 i with e' | e'
      · exact Or.inl (by rw [r1 i, filt_append, e, e']; rfl)
      · exact Or.inr e'
    · exact Or.inr e
  have r2 := h2 f2
  intro i
  rw [r2 i, filt_append, r1 i, exN_append, filt_append, filt_append, filt_append, List.append_assoc]

theorem Rel.congr {st s : St} {X X' : List Note} (e : X = X') (h : Rel st s X) : Rel st s X' := e ▸ h

theorem Rel.pre {a b c : St} {X : List Note} (e : NM b = NM a) (h : Rel b c X) : Rel a c X :=
  fun ⟨d, s⟩ i => by rw [h ⟨by rw [e]; exact d, s⟩ i, e]

theorem Rel.post {a b c : St} {X : List Note} (h : Rel a b X) (e : NM c = NM b) : Rel a c X :=
  fun f i => by rw [e]; exact h f i

theorem Rel.same {a b : St} (e : NM b = NM a) : Rel a b [] := Rel.pre e (Rel.refl b)

theorem Rel.tr {a b c : St} {X1 X2 X : List Note} (h1 : Rel a b X1) (h2 : Rel b c X2) (e : X1 ++ X2 = X) :
    Rel a c X := e ▸ h1.trans h2

/-- Lines added after what the state holds, whatever was carried on before
    them: the notes are new, so none of them has lines carried on. -/
theorem filt_swap (A P S1 S2 Y : List (Nat × Nat)) (hy : S1 ++ S2 = Y) (d : Disj (A ++ P) Y) (i : Nat) :
    filt i (A ++ S1 ++ (P ++ S2)) = filt i (A ++ P ++ Y) := by
  rcases d i with h | h
  · rw [filt_append, append_eq_nil'] at h
    rw [← hy]
    simp only [filt_append, h.1, h.2, List.nil_append, List.append_nil]
  · rw [← hy, filt_append, append_eq_nil'] at h
    simp only [← hy, filt_append, h.1, h.2, List.nil_append, List.append_nil]

/-- A line put with the parts `A` of its notes shown and `B` carried on. -/
theorem rel_put {st s : St} (A B : List NotePart) (X : List Note) (hy : ex A ++ ex B = exN X)
    (hd : s.done = st.done) (hn : s.notes = st.notes ++ A) (hc : s.carry = st.carry ++ B) : Rel st s X := by
  intro ⟨d, _⟩ i
  have e : NM s = (ex (pagesNotes st.done.reverse) ++ ex st.notes) ++ ex A ++ (ex st.carry ++ ex B) := by
    simp [NM, hd, hn, hc, ex_append, List.append_assoc]
  rw [e]
  exact filt_swap _ _ _ _ _ hy d i

/-! ## The operations that move to a new column keep what is held -/

theorem notes_nil_of (st : St) (h : st.notes.isEmpty = true) : st.notes = [] := by
  cases e : st.notes with
  | nil => rfl
  | cons _ _ => rw [e] at h; cases h

theorem close_nm (env : Env) (st : St) :
    ex (pagesNotes (close env st).done.reverse) = ex (pagesNotes st.done.reverse) ++ ex st.notes ∧
      (close env st).carry = st.carry := by
  unfold close
  split
  · rename_i h
    rw [notes_nil_of st h.2]; simp
  · simp [pagesNotes_snoc, ex_append]

theorem nm_fresh (env : Env) (tp : Bool) (st : St) : NM (fresh env tp st) = NM st := by
  obtain ⟨a, b⟩ := close_nm env st
  show ex (pagesNotes (close env st).done.reverse) ++ ex [] ++ ex (close env st).carry = NM st
  rw [a, b]; simp [NM]

theorem nm_placeTurnedGo (env : Env) (st : St) (ds : List Waiting) : NM (placeTurnedGo env st ds) = NM st := by
  induction ds generalizing st with
  | nil => rfl
  | cons d ds ih =>
    cases d with
    | figure i e => rfl
    | turned i =>
      simp only [placeTurnedGo]; rw [ih]; simp [NM, pagesNotes_snoc]

theorem nm_opened (env : Env) (tp : Bool) (st : St) : NM (opened env tp st) = NM st := by
  unfold opened; split
  · unfold placeTurned; rw [nm_placeTurnedGo, nm_fresh]
  · exact nm_fresh env tp st

theorem nm_placeDeferred (env : Env) (st : St) : NM (placeDeferred env st) = NM st := by
  obtain ⟨_, _, _, _, _, a6, a7, _, a9, _, _⟩ := placeDeferredGo_fields env st st.deferred
  simp only [NM, placeDeferred, a6, a7, a9]

theorem nm_carryInto (env : Env) (st : St) (h : st.notes = []) : NM (carryInto env st) = NM st := by
  unfold carryInto; split
  · rfl
  · dsimp only [NM]
    rw [List.append_assoc, splitCarried_lines, h]; simp

theorem nm_open (env : Env) (tp : Bool) (st : St) :
    NM (carryInto env (placeDeferred env (opened env tp st))) = NM st := by
  have n0 : (placeDeferred env (opened env tp st)).notes = [] := by
    obtain ⟨_, _, _, _, _, a6, _⟩ := placeDeferredGo_fields env (opened env tp st) (opened env tp st).deferred
    rw [placeDeferred, a6]; exact (opened_fields env tp st).2.1
  rw [nm_carryInto env _ n0, nm_placeDeferred, nm_opened]

theorem nm_nextColumn (env : Env) (st : St) : NM (nextColumn env st) = NM st := nm_open env false st

/-- Joining a part to the part before it of the same note keeps the lines. -/
theorem ex_joinPart (parts : List NotePart) (q : NotePart) : ex (joinPart parts q) = ex parts ++ partLines q := by
  unfold joinPart
  split
  · rename_i j f l before e
    split
    · rename_i c
      obtain ⟨c1, c2⟩ := c
      have pr : parts = before.reverse ++ [(j, f, l)] := by
        have := congrArg List.reverse e; simpa using this
      obtain ⟨qi, qf, ql⟩ := q
      simp only at c1 c2
      subst c1; subst c2
      rw [pr, ex_append, ex_append, List.append_assoc]
      simp only [ex, partLines, List.cons_bind, List.nil_bind, List.append_nil]
      rw [seg_add]
    · rw [ex_append]; simp [ex, partLines]
  · rw [ex_append]; simp [ex, partLines]

theorem ex_foldl_joinPart (parts qs : List NotePart) : ex (qs.foldl joinPart parts) = ex parts ++ ex qs := by
  induction qs generalizing parts with
  | nil => simp
  | cons q qs ih =>
    simp only [List.foldl]; rw [ih, ex_joinPart, ex_cons, List.append_assoc]

theorem nm_drainCarried (env : Env) (st : St) : NM (drainCarried env st) = NM st := by
  unfold drainCarried; dsimp only
  split <;> (try split) <;> (try rfl)
  all_goals
    simp only [NM, ex_foldl_joinPart, List.append_assoc]
    rw [splitCarried_lines]
theorem nm_nextPage (env : Env) (st : St) : NM (nextPage env st) = NM st := nm_open env true st

theorem nm_fit (env : Env) (st : St) (a : Int) : NM (fit env st a) = NM st := by
  unfold fit
  repeat' split
  all_goals first
    | rfl
    | exact nm_nextColumn env st

set_option linter.unusedVariables false in
theorem nm_drainCarry (env : Env) (st : St) : NM (drainCarry env st) = NM st := by
  rw [drainCarry]
  split
  · rename_i h
    have dec := I4_drain_rank env st ⟨Or.inl h.1, h.2⟩
    rw [nm_drainCarry env (nextColumn env st), nm_nextColumn]
  · rfl
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

set_option linter.unusedVariables false in
theorem nm_seek (env : Env) (p : St → Bool) (st : St) : NM (seek env p st) = NM st := by
  rw [seek]
  split
  · rfl
  · split
    · rename_i h
      have dec := I4_drain_rank env st ⟨seek_cond st h.2, h.1⟩
      rw [nm_seek env p (nextColumn env st), nm_nextColumn]
    · exact nm_nextColumn env st
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem nm_parityStart (env : Env) (accept : Nat → Bool) (st : St) :
    NM (parityStart env accept st) = NM st := by
  have c : NM (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st
      else nextPage env (drainCarry env st)) = NM st := by
    split
    · exact nm_drainCarry env st
    · rw [nm_nextPage, nm_drainCarry]
  unfold parityStart
  dsimp only
  generalize (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st
      else nextPage env (drainCarry env st)) = nx at c
  split
  · exact c
  · split
    · rw [← c]; simp [NM, pagesNotes_snoc]
    · rw [nm_nextPage, c]

theorem nm_breakPage (env : Env) (st : St) : NM (breakPage env st) = NM st := by
  unfold breakPage; split
  · rfl
  · exact nm_nextPage env st

theorem nm_breakAt (env : Env) (k : BreakKind) (st : St) : NM (breakAt env k st) = NM st := by
  cases k <;> unfold breakAt <;> dsimp only
  · split
    · exact nm_nextColumn env st
    · exact nm_breakPage env st
  · exact nm_breakPage env st
  · exact nm_parityStart env _ st
  · exact nm_parityStart env _ st

theorem nm_sectionStart (env : Env) (k : BreakKind) (st : St) : NM (sectionStart env k st) = NM st := by
  have a := nm_drainCarry env st
  unfold sectionStart
  cases k <;> dsimp only
  · split
    · exact a
    · rw [nm_breakAt, a]
  · split
    · exact a
    · rw [nm_breakAt, a]
  · rw [nm_breakAt, a]
  · rw [nm_breakAt, a]

theorem nm_switchColumns (env : Env) (cols : Nat) (st : St) : NM (switchColumns env cols st) = NM st := by
  have a := nm_drainCarry env st
  unfold switchColumns
  dsimp only
  split
  · obtain ⟨c1, c2⟩ := close_nm env (drainCarry env st)
    rw [← a]
    show ex (pagesNotes (close env (drainCarry env st)).done.reverse) ++ ex [] ++
      ex (close env (drainCarry env st)).carry = _
    rw [c1, c2]; simp [NM]
  · show NM (nextPage env (drainCarry env st)) = NM st
    rw [nm_nextPage, a]

theorem nm_restoreColumns (env : Env) (st : St) : NM (restoreColumns env st) = NM st :=
  nm_nextPage env st

set_option linter.unusedVariables false in
theorem nm_judgeNeed (env : Env) (b : Int) (st : St) : NM (judgeNeed env b st) = NM st := by
  rw [judgeNeed]
  split
  · rfl
  · split
    · rename_i h
      have dec := I4_nextColumn_rank env st (Or.inr h.2)
      rw [nm_judgeNeed env b (nextColumn env st), nm_nextColumn]
    · split
      · rfl
      · rename_i h
        have dec := I4_nextColumn_rank env st (Or.inl (by simpa using h))
        rw [nm_judgeNeed env b (nextColumn env st), nm_nextColumn]
termination_by rank st
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem markUnmet_notes (w : Wait) (o : PageOut) : (markUnmet w o).notes = o.notes := by
  unfold markUnmet; split <;> rfl

theorem pagesNotes_map (w : Wait) (ps : List PageOut) :
    pagesNotes (ps.map (markUnmet w)).reverse = pagesNotes ps.reverse := by
  induction ps with
  | nil => rfl
  | cons p ps ih =>
    simp only [List.map, List.reverse_cons, pagesNotes_append, ih]
    simp [pagesNotes, markUnmet_notes]

theorem nm_checkWait (acc : St) (w : Wait) : NM (checkWait acc w) = NM acc := by
  unfold checkWait
  split
  · rfl
  · split
    · rfl
    · simp only [NM]; rw [pagesNotes_map]

theorem nm_checkWaits (st : St) : NM (checkWaits st) = NM st := by
  unfold checkWaits
  have : ∀ (ws : List Wait) (a : St), NM (ws.foldl checkWait a) = NM a := by
    intro ws
    induction ws with
    | nil => intro a; rfl
    | cons w ws ih => intro a; simp only [List.foldl]; rw [ih, nm_checkWait]
  rw [this]; rfl

theorem nm_waitForPrior (u : Unmet) (q : Nat × Bool) (st : St) : NM (waitForPrior u q st) = NM st := by
  unfold waitForPrior; split <;> rfl

theorem nm_flush (env : Env) (st : St) : NM (flushPendingRule env st) = NM st := by
  unfold flushPendingRule; split <;> rfl

theorem nm_keepFrom (env : Env) (st : St) (b : Bool) : NM (keepFrom env st b) = NM st := by
  unfold keepFrom; split
  · exact nm_nextColumn env st
  · rfl

theorem nm_headingState (env : Env) (st : St) (recto b : Bool) : NM (headingStateOf env st recto b) = NM st := by
  unfold headingStateOf; split
  · exact nm_parityStart env _ st
  · exact nm_keepFrom env st b

theorem nm_keepFollowing (inner : Inner) (env : Env) (hd : Bool) (st : St) (extent : Int) (ls : List Line)
    (later : List Flow) : NM (keepFollowing inner env hd st extent ls later) = NM st := nm_keepFrom env st _

theorem nm_afterFront (env : Env) (st : St) : NM (afterFront env st) = NM st := by
  unfold afterFront; split
  · rfl
  · exact nm_nextColumn env st

/-! ## Lines -/

theorem notesOf_append (a b : List Line) : notesOf (a ++ b) = notesOf a ++ notesOf b := List.append_bind _ _ _
theorem notesOf_cons (l : Line) (ls : List Line) : notesOf (l :: ls) = l.notes ++ notesOf ls := rfl
@[simp] theorem notesOf_nil : notesOf [] = [] := rfl

theorem notesOf_take_drop (n : Nat) (ls : List Line) :
    notesOf (ls.take n) ++ notesOf (ls.drop n) = notesOf ls := by
  rw [← notesOf_append, List.take_append_drop]

theorem rel_putLine (env : Env) (allow : Bool) (st s : St) (l : Line)
    (h : putLineWithReserve allow env st l = .ok s) : Rel st s l.notes := by
  unfold putLineWithReserve at h
  split at h
  · cases h
  · split at h
    · rename_i c
      split at h
      · cases h
      · rename_i e
        exfalso
        have : noteLines l = 0 := by simp [noteLines, e]
        omega
    · injection h with h
      subst h
      exact rel_put _ _ _ (splitNotes_lines _ _) rfl rfl rfl

theorem rel_putLines (env : Env) (allow : Bool) (st s : St) (ls : List Line)
    (h : putLines allow env st ls = .ok s) : Rel st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [putLines, Except.ok.injEq] at h; subst h; exact Rel.refl _
  | cons l ls ih =>
    unfold putLines at h
    split at h
    · cases h
    · rename_i s1 e
      exact Rel.tr (rel_putLine env allow st s1 l e) (ih s1 h) rfl

theorem rel_putLinesKeeping (env : Env) (allow : Bool) (adj after : Int) (st s : St) (ls : List Line)
    (h : putLinesKeeping allow env adj after st ls = .ok s) : Rel st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [putLinesKeeping, Except.ok.injEq] at h; subst h; exact Rel.refl _
  | cons l ls ih =>
    unfold putLinesKeeping at h
    split at h
    · cases h
    · rename_i s1 e
      exact Rel.tr (Rel.pre (a := st) rfl (rel_putLine env allow { st with adjust := adj - (sumPitch env ls + after) } s1 l e)) (ih s1 h) rfl

theorem trialRest_moved_nm (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.moved next r)) :
    NM next = NM st := by
  obtain ⟨_, n, _⟩ := trialRest_moved env k start st rows fid next r h
  rw [n]; exact nm_nextColumn env st

theorem trialRest_placed_rel (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (c : Nat) (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.placed c next r)) :
    Rel st next (notesOf (rows.take c)) := by
  unfold trialRest at h
  dsimp only at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i placed e
      injection h with h; injection h with h1 h2 _
      subst h1; subst h2
      exact Rel.pre (nm_fit env st _) (Rel.post (rel_putLines env false _ placed _ e) rfl)

theorem trial_moved_nm (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (next : St) (r : Keep) (h : trial env k start st rows = .ok (.moved next r)) : NM next = NM st := by
  unfold trial at h
  split at h
  · cases h
  unfold trialFrom at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · split at h
        · have := trialRest_moved_nm env _ start _ _ _ next r h; exact this
        · injection h with h; injection h with h1 _; subst h1; exact nm_nextColumn env st
      · exact trialRest_moved_nm env _ start _ _ _ next r h

theorem trial_placed_rel (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (c : Nat) (next : St) (r : Keep) (h : trial env k start st rows = .ok (.placed c next r)) :
    Rel st next (notesOf (rows.take c)) := by
  unfold trial at h
  split at h
  · cases h
  unfold trialFrom at h
  split at h
  · injection h with h; injection h with h1 h2 _; subst h1; subst h2; exact Rel.refl st
  · split at h
    · simp at h
    · split at h
      · split at h
        · have := trialRest_placed_rel env _ start _ _ _ c next r h; exact Rel.pre rfl this
        · simp at h
      · exact trialRest_placed_rel env _ start _ _ _ c next r h

set_option linter.unusedVariables false in
theorem rel_placeLines (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (s : St)
    (h : placeLines env k start st rows = .ok s) : Rel st s (notesOf rows) := by
  match rows with
  | [] =>
    simp only [placeLines, Except.ok.injEq] at h; subst h; exact Rel.refl _
  | r :: rs =>
    rw [placeLines] at h
    split at h
    · cases h
    · rename_i next relaxed e
      have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·))
          (Nat.succ rs.length, keepRank relaxed, rank next) (Nat.succ rs.length, keepRank k, rank st) := by
        apply Prod.Lex.right
        cases I4_trial_moved env k start st _ next relaxed e with
        | inl l => exact Prod.Lex.left _ _ l
        | inr e => rw [e.1]; exact Prod.Lex.right _ e.2
      exact Rel.pre (trial_moved_nm env k start st _ next relaxed e) (rel_placeLines env relaxed start next (r :: rs) s h)
    · rename_i count next relaxed e
      have a := trial_placed_rel env k start st _ count next relaxed e
      split at h
      · rename_i c
        injection h with h; subst h
        rw [c, take_length'] at a; exact a
      · have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·))
            (Nat.succ rs.length - count, keepRank relaxed, rank (nextColumn env next))
            (Nat.succ rs.length, keepRank k, rank st) := by
          apply Prod.Lex.left
          have := I4_trial_placed env k start st _ _ count next relaxed e
          omega
        have b := rel_placeLines env relaxed false (nextColumn env next) ((r :: rs).drop count) s h
        exact Rel.tr a (Rel.pre (nm_nextColumn env next) b) (notesOf_take_drop _ _)
termination_by (rows.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem Rel.via {a b c : St} {X : List Note} (h : Rel b c X) (e : NM b = NM a) : Rel a c X := Rel.pre e h

theorem rel_placeWithNext (inner : Inner) (env : Env) (k : Keep) (start : Bool) (st : St) (ls : List Line)
    (l f : Nat) (later : List Flow) (s : St)
    (h : placeWithNext inner env k start st ls l f later = .ok s) : Rel st s (notesOf ls) := by
  unfold placeWithNext at h
  split at h
  · cases h
  · rename_i full e
    split at h
    · injection h with h; subst h; exact rel_placeLines env k start st ls _ e
    · split at h
      · injection h with h; subst h; exact rel_placeLines env k start st ls _ e
      · split at h
        · cases h
        · rename_i before e2
          have a := rel_placeLines env k start st _ before e2
          have b := rel_placeLines env k _ _ _ s h
          exact Rel.tr a (Rel.via b (nm_afterFront env before)) (notesOf_take_drop _ _)

/-! ## Stanzas -/

theorem notes_join_take_drop (n : Nat) (vs : List (List Line)) :
    notesOf (vs.take n).join ++ notesOf (vs.drop n).join = notesOf vs.join := by
  rw [← notesOf_append, ← join_app, List.take_append_drop]

theorem rel_placeStanza (env : Env) (k : Keep) (start : Bool) (st : St) (verses : List (List Line)) (s : St)
    (h : placeStanza env k start st verses = .ok s) : Rel st s (notesOf verses.join) := by
  have key : ∀ m, ∀ (k : Keep) (start : Bool) (st : St) (verses : List (List Line)),
      stanzaRank k st verses = m → ∀ s, placeStanza env k start st verses = .ok s →
      Rel st s (notesOf verses.join) := by
    intro m
    induction m using stanza_wf.induction with
    | _ m ih =>
    intro k start st verses hm s h
    subst hm
    match verses with
    | [] => simp only [placeStanza, Except.ok.injEq] at h; subst h; exact Rel.refl _
    | v :: vs =>
      rw [placeStanza] at h
      dsimp only at h
      split at h
      · rename_i h1
        split at h
        · have := ih _ (Prod.Lex.right _ (Prod.Lex.left _ _ (by simp [keepRank, h1.1]))) _ start _ (v :: vs) rfl s h
          exact Rel.via this rfl
        · rename_i h2
          have r : rank (nextColumn env st) < rank st := by
            apply I4_nextColumn_rank; left
            cases e : empty st
            · rfl
            · simp [e] at h2
          have := ih _ (Prod.Lex.right _ (Prod.Lex.right _ r)) k start _ (v :: vs) rfl s h
          exact Rel.via this (nm_nextColumn env st)
      · split at h
        · rename_i h3
          have r : rank (nextColumn env st) < rank st := by
            apply I4_nextColumn_rank; left
            have := h3.2; simp only [Bool.or_eq_false_iff] at this; exact this.1
          have := ih _ (Prod.Lex.right _ (Prod.Lex.right _ r)) k start _ (v :: vs) rfl s h
          exact Rel.via this (nm_nextColumn env st)
        · split at h
          · rename_i h4
            split at h
            · cases h
            · rename_i placed e
              have a := rel_placeLines env _ _ st _ placed e
              split at h
              · injection h with h; subst h
                rename_i c
                have : (v :: vs).drop (wholeVerses (fitting env st (v :: vs).join) (v :: vs)) = [] := by
                  rw [c]; simp
                refine Rel.congr ?_ (Rel.post a rfl)
                rw [← notes_join_take_drop (wholeVerses (fitting env st (v :: vs).join) (v :: vs)) (v :: vs), this]
                simp
              · have b := ih _ (by apply Prod.Lex.left; simp only [stanzaRank, List.length_drop, List.length_cons]; have := h4.2; omega) k false _ _ rfl s h
                exact Rel.tr (Rel.post a rfl) (Rel.via b (nm_nextColumn env _)) (notes_join_take_drop _ _)
          · split at h
            · split at h
              · cases h
              · rename_i placed e
                have a := rel_placeLines env _ true st v placed e
                have b := ih _ (Prod.Lex.left _ _ (by simp)) k false placed vs rfl s h
                exact Rel.tr a b (notesOf_append v vs.join).symm
            · rename_i h5
              split at h
              · cases h
              · rename_i placed e
                have a := rel_placeLines env _ _ st _ placed e
                split at h
                · injection h with h; subst h
                  rename_i c
                  have : (v :: vs).drop (splitAtBreak k start (vs.length + 1) (wholeVerses (fitting env st (v :: vs).join) (v :: vs))) = [] := by
                    rw [c]; simp
                  refine Rel.congr ?_ a
                  rw [← notes_join_take_drop (splitAtBreak k start (vs.length + 1) (wholeVerses (fitting env st (v :: vs).join) (v :: vs))) (v :: vs), this]
                  simp
                · have b := ih _ (by apply Prod.Lex.left; simp only [stanzaRank, List.length_drop, List.length_cons]; omega) k false _ _ rfl s h
                  exact Rel.tr a (Rel.via b (nm_nextColumn env _)) (notes_join_take_drop _ _)
  exact key _ k start st verses rfl s h

theorem rel_placeStanzaWithNext (inner : Inner) (env : Env) (k : Keep) (st : St) (verses : List (List Line))
    (l f : Nat) (later : List Flow) (s : St)
    (h : placeStanzaWithNext inner env k st verses l f later = .ok s) : Rel st s (notesOf verses.join) := by
  unfold placeStanzaWithNext at h
  split at h
  · cases h
  · rename_i full e
    have a := rel_placeStanza env k true st verses full e
    split at h
    · injection h with h; subst h; exact a
    · split at h
      · cases h
      · rename_i before e2
        split at h
        · injection h with h; subst h; exact a
        · have a2 := rel_placeStanza env k true st _ before e2
          have b := rel_placeStanza env k true _ _ s h
          exact Rel.tr a2 (Rel.via b (nm_nextColumn env _)) (notes_join_take_drop _ _)

/-! ## Headings and ruled blocks -/

theorem rel_putHeading (env : Env) (st : St) (firstId : Nat) (extent : Int) (ls : List Line) (s : St)
    (h : putHeading env st firstId extent ls = .ok s) : Rel st s (notesOf ls) := by
  unfold putHeading at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact Rel.post (rel_putLine _ false st placed _ e) rfl

theorem rel_placeHeading (env : Env) (st : St) (firstId : Nat) (extent : Int) (ls : List Line) (s : St)
    (h : placeHeading env st firstId extent ls = .ok s) : Rel st s (notesOf ls) := by
  unfold placeHeading at h
  split at h
  · cases h
  · split at h
    · exact Rel.via (rel_putHeading env _ firstId extent ls s h) rfl
    · exact Rel.via (rel_putHeading env _ firstId extent ls s h) (nm_fit env st _)

theorem rel_putRuledHeading (env : Env) (ready : St) (b a : Int) (fid : Nat) (e : Int) (ls : List Line) (s : St)
    (h : putRuledHeading env ready b a fid e ls = .ok s) : Rel ready s (notesOf ls) := by
  unfold putRuledHeading at h
  split at h
  · cases h
  · rename_i placed e2
    injection h with h; subst h
    exact Rel.post (Rel.via (rel_putHeading env _ fid e ls placed e2) rfl) rfl

theorem rel_ruledPlaceAt (env : Env) (st : St) (r : Ruled) (first lastLine : Line) (later : List Flow)
    (ready p : St) (h : ruledPlaceAt env st r first lastLine later ready = .ok p) :
    Rel ready p (notesOf r.lines) := by
  unfold ruledPlaceAt at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact Rel.post (Rel.via (rel_putLinesKeeping env true _ _ _ placed r.lines e) rfl) rfl

theorem rel_ruledLinesHere (env : Env) (st : St) (r : Ruled) (later : List Flow) (p : St)
    (h : ruledLinesHere env st r later = .ok (some p)) : Rel st p (notesOf r.lines) := by
  unfold ruledLinesHere at h
  split at h
  · split at h
    · cases h
    · split at h
      · split at h
        · cases h
        · rename_i s0 e
          injection h with h; injection h with h; subst h
          exact Rel.via (rel_ruledPlaceAt env st r _ _ later _ s0 e) (nm_fit env st _)
      · cases h
  · cases h

set_option linter.unusedVariables false in
theorem rel_placeRuled (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (s : St)
    (h : placeRuled inner env st r later = .ok s) : Rel st s (notesOf r.lines) := by
  rw [placeRuled] at h
  split at h
  · rename_i recto extent hh
    dsimp only at h
    generalize fitsFollowingGo inner env (keepVirtual env true st extent r.lines) (keepWanted later).1 0 (keepWanted later).2 = fb at h
    have hr := rank_headingState_le env st recto fb
    have hsS := nm_headingState env st recto fb
    generalize headingStateOf env st recto fb = HS at h hr hsS
    split at h
    · cases h
    · split at h
      · split at h
        · rename_i ha
          have dec : Prod.Lex (· < ·) (· < ·) (ruledRank { r with after := none }, rank HS) (ruledRank r, rank st) :=
            Prod.Lex.left _ _ (ruledRank_after r ha)
          exact Rel.via (rel_placeRuled inner env HS { r with after := none } later s h) hsS
        · rename_i ha hb
          have dec : Prod.Lex (· < ·) (· < ·) (ruledRank { r with before := none }, rank HS) (ruledRank r, rank st) :=
            Prod.Lex.left _ _ (ruledRank_before r ha hb)
          exact Rel.via (rel_placeRuled inner env HS { r with before := none } later s h) hsS
        · exact Rel.via (rel_placeHeading env HS _ extent r.lines s h) hsS
      · split at h
        · exact Rel.via (rel_putRuledHeading env _ _ _ _ extent r.lines s h) hsS
        · split at h
          · rename_i h2
            have dec : Prod.Lex (· < ·) (· < ·) (ruledRank r, rank (fit env HS (headingBeforeExtra env r +
                headingNeed env HS extent r.lines + headingAfterExtra env r extent))) (ruledRank r, rank st) :=
              Prod.Lex.right _ (Nat.lt_of_lt_of_le (I4_fit_moved env HS _ h2) hr)
            exact Rel.via (rel_placeRuled inner env _ r later s h) ((nm_fit env HS _).trans hsS)
          · exact Rel.via (rel_putRuledHeading env _ _ _ _ extent r.lines s h) ((nm_fit env HS _).trans hsS)
  · rename_i hh
    split at h
    · rename_i first lastLine _ _
      split at h
      · cases h
      · rename_i placed hr
        injection h with h; subst h
        obtain ⟨l', e⟩ := ruledHere_some inner env st r later placed hr
        exact rel_ruledLinesHere env st r l' placed e
      · split at h
        · rename_i h1
          have dec : Prod.Lex (· < ·) (· < ·) (ruledRank { r with joined := false }, rank (nextColumn env (flushPendingRule env st)))
              (ruledRank r, rank st) := by
            apply Prod.Lex.left; simp [ruledRank, joinedRank, h1.1]
          exact Rel.via (rel_placeRuled inner env (nextColumn env (flushPendingRule env st)) { r with joined := false } later s h)
            ((nm_nextColumn env _).trans (nm_flush env st))
        · split at h
          · exact rel_placeLines env r.keep true st r.lines s h
          · split at h
            · rename_i h2
              have dec : Prod.Lex (· < ·) (· < ·) (ruledRank r, rank (fit env st (room env st + 1)))
                  (ruledRank r, rank st) :=
                Prod.Lex.right _ (I4_fit_moved env st _ h2)
              exact Rel.via (rel_placeRuled inner env _ r later s h) (nm_fit env st _)
            · exact rel_placeLines env r.keep true st r.lines s h
    · rename_i H
      have : r.lines = [] := by
        cases e : r.lines with
        | nil => rfl
        | cons x xs => exact absurd (H x ((x :: xs).getLast (by simp)) (by rw [e]; rfl) (by rw [e]; rfl)) id
      injection h with h; subst h
      rw [this]; exact Rel.refl _
termination_by (ruledRank r, rank st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem rel_placeRuledKeeping (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (s : St)
    (h : placeRuledKeeping inner env st r later = .ok s) : Rel st s (notesOf r.lines) := by
  unfold placeRuledKeeping at h
  split at h
  · cases h
  · rename_i full e
    dsimp only at h
    split at h
    · split at h
      · exact Rel.via (rel_placeRuled inner env _ { r with joined := false } later s h)
          ((nm_nextColumn env _).trans (nm_flush env st))
      · injection h with h; subst h; exact rel_placeRuled inner env st r later _ e
    · injection h with h; subst h; exact rel_placeRuled inner env st r later _ e

/-! ## Wrapped figures -/

theorem rel_putWrappedLine (env : Env) (fe : Int) (st s : St) (l : Line)
    (h : putWrappedLine env fe st l = .ok s) : Rel st s l.notes := by
  unfold putWrappedLine at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact Rel.post (Rel.via (rel_putLine env false _ placed l e) rfl) rfl

theorem rel_putBeside (env : Env) (fe : Int) (st s : St) (ls : List Line)
    (h : putBeside env fe st ls = .ok s) : Rel st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [putBeside, Except.ok.injEq] at h; subst h; exact Rel.refl _
  | cons l ls ih =>
    unfold putBeside at h
    split at h
    · cases h
    · rename_i s1 e
      exact Rel.tr (Rel.via (rel_putWrappedLine env fe _ s1 l e) rfl) (ih s1 h) rfl

theorem nm_overflowMove (env : Env) (st : St) (l : Line) (gap : Int) : NM (overflowMove env st l gap) = NM st := by
  unfold overflowMove; split
  · exact nm_nextColumn env st
  · rfl

theorem nm_overflowReady (env : Env) (st : St) (l : Line) : NM (overflowReady env st l) = NM st := by
  unfold overflowReady
  dsimp only
  rw [nm_fit]
  exact nm_overflowMove env st l _

theorem rel_placeWrappedOverflow (env : Env) (st s : St) (ls : List Line)
    (h : placeWrappedOverflow env st ls = .ok s) : Rel st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [placeWrappedOverflow, Except.ok.injEq] at h; subst h; exact Rel.refl _
  | cons l ls ih =>
    unfold placeWrappedOverflow at h
    split at h
    · cases h
    · rename_i placed e
      exact Rel.tr (Rel.via (rel_putLine env false _ placed l e) (nm_overflowReady env st l)) (ih placed h) rfl

theorem rel_placeWrapped (env : Env) (st : St) (i : Nat) (e : Int) (ls : List Line)
    (s : St) (h : placeWrapped env st i e ls = .ok s) : Rel st s (notesOf ls) := by
  unfold placeWrapped at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · cases h
    · rename_i placed eq
      generalize fittingWrapped env _ _ ls = c at h eq
      have ab : Rel st placed (notesOf (ls.take c)) := Rel.via (rel_putBeside env _ _ placed _ eq) (nm_fit env st e)
      split at h
      · rename_i emp
        injection h with h; subst h
        have hd : ls.drop c = [] := by
          cases d : ls.drop c with
          | nil => rfl
          | cons _ _ => rw [d] at emp; cases emp
        refine Rel.congr ?_ (Rel.post ab rfl)
        rw [← notesOf_take_drop c ls, hd]; simp
      · have b := rel_placeWrappedOverflow env _ s _ h
        exact Rel.tr (Rel.post ab rfl) (Rel.via b (nm_nextColumn env _)) (notesOf_take_drop _ _)

/-! ## Code: its rows carry no notes -/

theorem nm_placeCode (env : Env) (caption : Int) (first : Nat) (continued : Bool) (spans : List Nat)
    (isFirst : Bool) (st : St) (rows : List Line) (s : St)
    (h : placeCode env caption first continued spans isFirst st rows = .ok s) : NM s = NM st := by
  have key : ∀ n, ∀ (isFirst : Bool) (st : St) (rows : List Line), rows.length = n →
      ∀ s, placeCode env caption first continued spans isFirst st rows = .ok s → NM s = NM st := by
    intro n
    induction n using Nat.strongInductionOn with
    | _ n ih =>
    intro isFirst st rows hn s h
    match rows with
    | [] => simp only [placeCode, Except.ok.injEq] at h; subst h; rfl
    | r :: rs =>
      rw [placeCode] at h
      dsimp only at h
      split at h
      · cases h
      · split at h
        · cases h
        · rename_i c0
          split at h
          · injection h with h; subst h
            show NM (fit env _ _) = NM st
            rw [nm_fit, nm_seek]
          · rename_i c
            have b := ih _ (by rw [← hn]; simp only [List.length_drop, List.length_cons]; exact Nat.sub_lt (Nat.succ_pos _) (Nat.pos_of_ne_zero c0))
              false _ _ rfl s h
            rw [b, nm_nextColumn]
            show NM (fit env _ _) = NM st
            rw [nm_fit, nm_seek]
  exact key _ isFirst st rows rfl s h

/-! ## Tables -/

theorem rel_putReserved (env : Env) (reserve : Int) (st s : St) (ls : List Line)
    (h : putReserved env reserve st ls = .ok s) : Rel st s (notesOf ls) := by
  induction ls generalizing st with
  | nil => simp only [putReserved, Except.ok.injEq] at h; subst h; exact Rel.refl _
  | cons l ls ih =>
    unfold putReserved at h
    split at h
    · cases h
    · rename_i s1 e
      have b := ih _ h
      exact Rel.tr (Rel.post (Rel.via (rel_putLine env true _ s1 l e) rfl) rfl) b rfl

theorem nm_putRepeated (env : Env) (st s : St) (ls : List Line) (h : putRepeated env st ls = .ok s) :
    NM s = NM st := by
  induction ls generalizing st with
  | nil => simp only [putRepeated, Except.ok.injEq] at h; subst h; rfl
  | cons l ls ih =>
    unfold putRepeated at h
    split at h
    · cases h
    · rw [ih _ h]; rfl

theorem nm_tableAt (env : Env) (b : Int) (ls : List Line) (s : St) : NM (tableAt env b ls s) = NM s :=
  nm_fit env s _

theorem rel_tableRowsGo (env : Env) (header caption : List Line) (below : Bool) (ident : Nat) :
    ∀ m (seeking passed : Bool) (start : Int) (st : St) (rows : List (List Line)),
      (rows.length, tableRowsRank passed st seeking) = m →
      ∀ s, tableRowsGo env header caption below ident seeking passed start st rows = .ok s →
      Rel st s (notesOf rows.join ++ (if below then notesOf caption else [])) := by
  intro m
  induction m using table_wf.induction with
  | _ m ih =>
  intro seeking passed start st rows hm s h
  subst hm
  match rows with
  | [] =>
    rw [tableRowsGo] at h
    split at h
    · rename_i b; exact Rel.congr (by simp [b]) (rel_putReserved env 0 st s caption h)
    · rename_i b; injection h with h; subst h; exact Rel.congr (by simp [b]) (Rel.refl st)
  | row :: rest =>
    rw [tableRowsGo] at h
    split at h
    · rename_i h1
      split at h
      · cases h
      · rename_i withHeader e
        have dec : tableLt ((row :: rest).length, tableRowsRank passed withHeader false)
            ((row :: rest).length, tableRowsRank passed st seeking) := by
          apply Prod.Lex.right
          obtain ⟨d1, c1, k1, n1, _⟩ := tableAt_fields env 0 _ st h1.2
          obtain ⟨d2, c2, k2, n2, _, _⟩ := putRepeated_fields env _ _ header e
          simp only [tableRowsRank, waiting, columnsLeft, d1, c1, k1, n1, d2, c2, k2, n2, h1.1]
          exact Prod.Lex.right _ (Prod.Lex.right _ (Prod.Lex.right _ (by decide)))
        have b := ih _ dec false passed _ withHeader (row :: rest) rfl s h
        exact Rel.via b ((nm_putRepeated env _ withHeader header e).trans (nm_tableAt env 0 _ st))
    · split at h
      · split at h
        · cases h
        · rename_i placed e
          have dec : tableLt (rest.length, tableRowsRank false placed false)
              ((row :: rest).length, tableRowsRank passed st seeking) := by
            apply Prod.Lex.left; simp
          have a := rel_putReserved env _ st placed row e
          have b := ih _ dec false false start placed rest rfl s h
          exact Rel.tr a b (by simp only [List.join, notesOf_append, List.append_assoc])
      · split at h
        · rename_i h2
          have dec : tableLt ((row :: rest).length, tableRowsRank passed (nextColumn env st) true)
              ((row :: rest).length, tableRowsRank passed st seeking) := by
            apply Prod.Lex.right; simp only [tableRowsRank]
            exact Prod.Lex.right _ (lex3_of_lex2 (I4_drain_rank env st ⟨seek_cond st h2.2, h2.1⟩))
          have b := ih _ dec true passed start _ (row :: rest) rfl s h
          exact Rel.via b (nm_nextColumn env st)
        · split at h
          · rename_i h3
            have dec : tableLt ((row :: rest).length, tableRowsRank true (nextColumn env st) true)
                ((row :: rest).length, tableRowsRank passed st seeking) := by
              apply Prod.Lex.right; simp only [tableRowsRank, h3]; exact Prod.Lex.left _ _ (by decide)
            have b := ih _ dec true true start _ (row :: rest) rfl s h
            exact Rel.via b (nm_nextColumn env st)
          · cases h

theorem rel_tableCaption (env : Env) (below : Bool) (reserve : Int) (start s : St) (caption : List Line)
    (h : tableCaption env below reserve start caption = .ok s) :
    Rel start s (if below then [] else notesOf caption) := by
  unfold tableCaption at h
  split at h
  · rename_i b; injection h with h; subst h; exact Rel.congr (by simp [b]) (Rel.refl start)
  · rename_i b; exact Rel.congr (by simp [b]) (rel_putReserved env reserve start s caption h)

/-- The notes of the lines of a table, in the order it places them. -/
def tableNotes (header : List Line) (rows : List (List Line)) (caption : List Line) (below : Bool) : List Note :=
  if below then notesOf header ++ notesOf rows.join ++ notesOf caption
  else notesOf caption ++ notesOf header ++ notesOf rows.join

theorem rel_placeTableFrom (env : Env) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool) (firstPart : List Line)
    (s : St) (h : placeTableFrom env st ident before header rows caption below firstPart = .ok s) :
    Rel st s (tableNotes header rows caption below) := by
  unfold placeTableFrom at h
  have sk := nm_seek env (tableFits env before firstPart) st
  generalize seek env (tableFits env before firstPart) st = F at h sk
  dsimp only at h
  split at h
  · cases h
  · split at h
    · cases h
    · rename_i placed e1
      split at h
      · cases h
      · rename_i withHeader e2
        have b := rel_tableCaption env below _ _ placed caption e1
        have c := rel_putReserved env _ placed withHeader header e2
        have d := rel_tableRowsGo env header caption below ident _ false false _ withHeader rows rfl s h
        have all := Rel.via ((b.trans c).trans d) ((nm_tableAt env before firstPart F).trans sk)
        refine Rel.congr ?_ all
        unfold tableNotes
        cases below <;> simp [List.append_assoc]

theorem rel_placeTable (env : Env) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool)
    (s : St) (h : placeTable env st ident before header rows caption below = .ok s) :
    Rel st s (tableNotes header rows caption below) := by
  unfold placeTable at h
  split at h
  · cases h
  · exact rel_placeTableFrom env st ident before header rows caption below _ s h


/-! ## The flows read, by their notes -/

mutual
/-- The notes of the lines a flow places, those of the flows of a box or a
    book part among them.  A heading and a ruled heading read the notes of
    all their lines (`putHeading` puts them as those of one line).  A table
    reads the notes of its header once: the header repeated in a later
    column has no notes (`repeatedOf`, `putRepeated`; `lbNotes = []` in
    modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs:1510, 1558
    and 1642).  The rows of a code block are not read for notes: `placeCode`
    of Physical.hs:1448-1472 puts them in an `SCode` slot, and golem-typeset
    builds them with no notes (modules/golem-typeset/src/Golem/Typeset/Flow.hs:3814). -/
def flowNotes : Flow → List Note
  | .heading _ _ ls => notesOf ls
  | .ruled r => notesOf r.lines
  | .wrapped _ _ ls => notesOf ls
  | .table _ _ header rows caption below => tableNotes header rows caption below
  | .boxed _ _ _ body => sourceNotes body
  | .bookPart _ _ body => sourceNotes body
  | .paragraph _ ls => notesOf ls
  | .continued _ ls => notesOf ls
  | .defTerm ls => notesOf ls
  | .stanza _ vs => notesOf vs.join
  | .code _ _ _ _ _ => []
  | .figure _ _ => []
  | .pageFigure _ => []
  | .space _ => []
  | .blank _ => []
  | .brk _ => []
  | .needLines _ => []
  | .adjustLines _ => []
  | .noBreak => []
  | .noBreakLines _ => []
  | .keepNext _ _ => []
  | .start _ => []
  | .switchColumns _ => []
  | .restoreColumns => []
def sourceNotes : List Flow → List Note
  | [] => []
  | f :: fs => flowNotes f ++ sourceNotes fs
end

theorem sourceNotes_cons (f : Flow) (fs : List Flow) : sourceNotes (f :: fs) = flowNotes f ++ sourceNotes fs := by
  simp [sourceNotes]

/-! ## Boxes -/

theorem rel_putBoxPart (env : Env) (ident : Nat) (ready s : St) (origin b a : Int) (ls : List Line) (short : List Unmet)
    (h : putBoxPart env ident ready origin b a ls short = .ok s) : Rel ready s (notesOf ls) := by
  unfold putBoxPart at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact Rel.post (Rel.via (rel_putLines env false _ placed ls e) rfl) rfl

set_option linter.unusedVariables false in
theorem rel_placeBoxedParagraph (env : Env) (ident : Nat) (fb fa : Int) (k : Keep) (start : Bool) (st : St)
    (ls : List Line) (s : St) (h : placeBoxedParagraph env ident fb fa k start st ls = .ok s) :
    Rel st s (notesOf ls) := by
  match ls with
  | [] => simp only [placeBoxedParagraph, Except.ok.injEq] at h; subst h; exact Rel.refl _
  | first :: more =>
    rw [placeBoxedParagraph] at h
    dsimp only at h
    split at h
    · cases h
    · split at h
      · cases h
      · split at h
        · rename_i h1
          split at h
          · have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) ((first :: more).length, keepRank { k with all := false }, rank (addUnmet (.splitKept first.id) st))
                ((first :: more).length, keepRank k, rank st) := by
              apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, h1.1]
            exact Rel.via (rel_placeBoxedParagraph env ident fb fa _ start _ (first :: more) s h) rfl
          · rename_i h2
            have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) ((first :: more).length, keepRank k, rank (nextColumn env st))
                ((first :: more).length, keepRank k, rank st) := by
              apply Prod.Lex.right; apply Prod.Lex.right
              exact I4_nextColumn_rank env st (Or.inl (by simpa using h2))
            exact Rel.via (rel_placeBoxedParagraph env ident fb fa k start _ (first :: more) s h) (nm_nextColumn env st)
        · split at h
          · rename_i h3
            have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) ((first :: more).length, keepRank k, rank (nextColumn env st))
                ((first :: more).length, keepRank k, rank st) := by
              apply Prod.Lex.right; apply Prod.Lex.right; exact I4_nextColumn_rank env st (Or.inl h3.2)
            exact Rel.via (rel_placeBoxedParagraph env ident fb fa k start _ (first :: more) s h) (nm_nextColumn env st)
          · split at h
            · cases h
            · rename_i finished e
              have a := Rel.via (rel_putBoxPart env ident _ finished _ _ _ _ _ e) (nm_fit env st _)
              split at h
              · rename_i h4
                have b := rel_placeBoxedParagraph env ident fb fa k false _ _ s h
                exact Rel.tr a (Rel.via b (nm_nextColumn env _)) (notesOf_take_drop _ _)
              · rename_i h4
                injection h with h; subst h
                rw [take_of_le _ (first :: more) ?_] at a
                · exact a
                · simp; omega
termination_by (ls.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | assumption
    | (apply Prod.Lex.left; try simp only [List.length_drop, List.length_cons]
       exact Nat.sub_lt (Nat.succ_pos _) (boxCount_pos _ _))

theorem nm_seal (o : BoxOpen) (st : St) : NM (seal o st) = NM st := by
  cases o with
  | none => rfl
  | some p => obtain ⟨_, _⟩ := p; rfl

theorem nm_reopen (env : Env) (ident : Nat) (fb fa : Int) (verse : List Line) (st : St) :
    NM (reopen env ident fb fa verse st).1 = NM st := by
  unfold reopen
  split
  · split
    · rfl
    · rfl
  · rfl

theorem rel_putUnits (env : Env) (m : BoxMaps) (st s : St) (first : Bool) (vs : List (List Line))
    (h : putUnits env m st first vs = .ok s) : Rel st s (notesOf vs.join) := by
  induction vs generalizing st first with
  | nil => simp only [putUnits, Except.ok.injEq] at h; subst h; exact Rel.refl _
  | cons v vs ih =>
    unfold putUnits at h
    dsimp only at h
    split at h
    · cases h
    · rename_i s1 e
      have b := ih s1 false h
      exact Rel.tr (Rel.via (rel_putLines env false _ s1 v e) rfl) b (notesOf_append v vs.join).symm

theorem rel_putStanzaPart (env : Env) (m : BoxMaps) (ident : Nat) (ready s : St) (origin b g a : Int)
    (vs : List (List Line)) (short : List Unmet) (h : putStanzaPart env m ident ready origin b g a vs short = .ok s) :
    Rel ready s (notesOf vs.join) := by
  unfold putStanzaPart at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    exact Rel.post (Rel.via (rel_putUnits env m _ placed true vs e) rfl) rfl

set_option linter.unusedVariables false in
theorem rel_placeBoxedStanza (env : Env) (ident : Nat) (fb fa : Int) (m : BoxMaps) (k : Keep) (start : Bool)
    (relaxed : List Nat) (o : BoxOpen) (st : St) (vs : List (List Line)) (s : St)
    (h : placeBoxedStanza env ident fb fa m k start relaxed o st vs = .ok s) : Rel st s (notesOf vs.join) := by
  match vs with
  | [] =>
    simp only [placeBoxedStanza, Except.ok.injEq] at h; subst h
    exact Rel.same (nm_seal o st)
  | v :: more =>
    rw [placeBoxedStanza] at h
    dsimp only at h
    split at h
    · rename_i h1
      have hne := h1.2
      have b := rel_placeBoxedStanza env ident fb fa m k start relaxed none _ (v :: more) s h
      exact Rel.via b ((nm_nextColumn env _).trans (nm_seal o st))
    · split at h
      · rename_i h2
        have hk := h2.2.2.1
        have b := rel_placeBoxedStanza env ident fb fa m _ start relaxed o _ (v :: more) s h
        exact Rel.via b rfl
      · split at h
        · rename_i p hp
          have hp' : relaxFor m relaxed v = some p := by
            split at hp
            · exact hp
            · cases hp
          have b := rel_placeBoxedStanza env ident fb fa m k start (p :: relaxed) o _ (v :: more) s h
          exact Rel.via b rfl
        · split at h
          · split at h
            · cases h
            · rename_i placed e
              have a := rel_placeBoxedParagraph env ident fb fa _ true st v placed e
              have b := rel_placeBoxedStanza env ident fb fa m k false relaxed _ _ more s h
              exact Rel.tr a (Rel.via b (nm_reopen env ident fb fa v placed)) (notesOf_append v more.join).symm
          · rename_i h3
            split at h
            · cases h
            · rename_i finished e
              have a := Rel.via (rel_putStanzaPart env m ident _ finished _ _ _ _ _ _ e) (nm_fit env st _)
              split at h
              · have b := rel_placeBoxedStanza env ident fb fa m k false relaxed none _ _ s h
                exact Rel.tr a (Rel.via b (nm_nextColumn env _)) (notes_join_take_drop _ _)
              · rename_i h4
                injection h with h; subst h
                rw [take_of_le _ (v :: more) ?_] at a
                · exact a
                · simp; omega
termination_by (vs.length, keepRank k, unrelaxed m relaxed vs, rank st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; exact rank_seal_lt env _ _ (by assumption))
    | (apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, hk])
    | (apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; exact unrelaxed_lt _ _ _ _ _ hp')
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.left; try simp only [List.length_drop, List.length_cons]
       exact Nat.sub_lt (Nat.succ_pos _) (stanzaBoxCount_pos (by assumption)))

/-- The units of a mixed box hold the notes of its paragraphs and stanzas,
    in order. -/
theorem collectMixed_notes : ∀ (body : List Flow) (p : Int) (gaps : List (Nat × Int)) (acc : List (List Line))
    (g : List (Nat × Int)) (us : List (List Line)), collectMixed p gaps acc body = some (g, us) →
    notesOf us.join = notesOf acc.reverse.join ++ sourceNotes body
  | [], _, gaps, acc, g, us, h => by
    simp only [collectMixed, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨_, h⟩ := h; subst h; simp [sourceNotes]
  | f :: rest, p, gaps, acc, g, us, h => by
    cases f with
    | space n =>
      simp only [collectMixed] at h
      rw [collectMixed_notes rest _ _ _ g us h]; simp [sourceNotes, flowNotes]
    | keepNext n =>
      simp only [collectMixed] at h
      rw [collectMixed_notes rest _ _ _ g us h]; simp [sourceNotes, flowNotes]
    | paragraph k ls =>
      simp only [collectMixed] at h
      split at h
      · rename_i e
        have z := nonempty_head_none _ e
        rw [join_singletons] at z; subst z
        rw [collectMixed_notes rest _ _ _ g us h]; simp [sourceNotes, flowNotes]
      · rw [collectMixed_notes rest _ _ _ g us h]
        simp only [List.reverse_append, List.reverse_reverse, join_app, join_nonempty, join_singletons, notesOf_append,
          sourceNotes, flowNotes, List.append_assoc]
    | stanza k vs =>
      simp only [collectMixed] at h
      split at h
      · rename_i e
        have z := nonempty_head_none _ e
        rw [collectMixed_notes rest _ _ _ g us h]; simp [sourceNotes, flowNotes, z]
      · rw [collectMixed_notes rest _ _ _ g us h]
        simp only [List.reverse_append, List.reverse_reverse, join_app, join_nonempty, notesOf_append,
          sourceNotes, flowNotes, List.append_assoc]
    | _ => simp [collectMixed] at h

/-- `placeFlow` and `placeAll` one level below read the notes of the flows. -/
def NotesOk (inner : Inner) : Prop :=
  (∀ env st f s, inner.flow env st f = .ok s → Rel st s (flowNotes f)) ∧
  (∀ env st fs s, inner.all env st fs = .ok s → Rel st s (sourceNotes fs))

theorem rel_placeFlows (inner : Inner) (hi : NotesOk inner) (env : Env) (st s : St) (body : List Flow)
    (h : placeFlows inner env st body = .ok s) : Rel st s (sourceNotes body) := by
  induction body generalizing st with
  | nil => simp only [placeFlows, Except.ok.injEq] at h; subst h; exact Rel.congr (by simp [sourceNotes]) (Rel.refl st)
  | cons f fs ih =>
    unfold placeFlows at h
    split at h
    · cases h
    · rename_i s1 e
      exact Rel.tr (hi.1 env st f s1 e) (ih s1 h) (sourceNotes_cons f fs).symm

theorem rel_placeGeneric (inner : Inner) (hi : NotesOk inner) (env : Env) (st : St) (ident : Nat) (fb fa : Int)
    (body : List Flow) (s : St) (h : placeGeneric inner env st ident fb fa body = .ok s) :
    Rel st s (sourceNotes body) := by
  unfold placeGeneric at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · cases h
    · rename_i placed e
      injection h with h; subst h
      have b := rel_placeFlows inner hi env _ placed body e
      exact Rel.post (Rel.via b (nm_fit env st (genericMinimum env ident (bodyLines body)))) rfl

theorem rel_placeBox (inner : Inner) (hi : NotesOk inner) (env : Env) (st : St) (ident : Nat) (fb fa : Int)
    (body : List Flow) (s : St) (h : placeBox inner env st ident fb fa body = .ok s) :
    Rel st s (sourceNotes body) := by
  unfold placeBox at h
  split at h
  · exact Rel.congr (by simp [sourceNotes, flowNotes]) (rel_placeBoxedParagraph env ident fb fa _ true st _ s h)
  · have c := rel_placeBoxedStanza env ident fb fa _ _ true [] none st _ s h
    rw [join_nonempty] at c
    exact Rel.congr (by simp [sourceNotes, flowNotes]) c
  · split at h
    · rename_i gaps units e
      have t := collectMixed_notes body 0 [] [] gaps units e
      have c := rel_placeBoxedStanza env ident fb fa _ _ true [] none st units s h
      rw [t] at c; exact Rel.congr (by simp) c
    · exact rel_placeGeneric inner hi env st ident fb fa body s h

/-! ## Book parts and tables across a unit -/

set_option linter.unusedVariables false in
theorem nm_settle (env : Env) (ids : List Nat) (st : St) : NM (settle env ids st) = NM st := by
  rw [settle]
  split
  · rename_i h
    have dec := I4_settle_rank env st ⟨fun e => (by have := h.1; rw [e] at this; cases this), h.2⟩
    rw [nm_settle env ids (nextColumn env st), nm_nextColumn]
  · rfl
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

set_option linter.unusedVariables false in
theorem nm_advanceUnit (env : Env) (u : PartUnit) (w : Nat × Nat) (st : St) :
    NM (advanceUnit env u w st) = NM st := by
  rw [advanceUnit]
  split
  · rename_i h
    have dec : Prod.Lex (· < ·) (· < ·) (2 * w.1 + 2 - (nextColumn env st).page, columnsLeft (nextColumn env st))
        (2 * w.1 + 2 - st.page, columnsLeft st) := by
      have b := unitKey_page u st.page st.column
      rw [h] at b
      cases nextColumn_moves env st with
      | inl l => exact Prod.Lex.left _ _ (by omega)
      | inr r => rw [r.1]; exact Prod.Lex.right _ r.2
    rw [nm_advanceUnit env u w (nextColumn env st), nm_nextColumn]
  · rfl
termination_by (2 * w.1 + 2 - st.page, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem nm_nextUnit (env : Env) (u : PartUnit) (st : St) : NM (nextUnit env u st) = NM st := by
  unfold nextUnit; rw [nm_advanceUnit, nm_nextColumn]

theorem rel_retain (env : Env) (u : PartUnit) (table : Bool) (ids : List Nat) (st : St)
    (compose : St → Except Failure St) (X : List Note) (hc : ∀ a s, compose a = .ok s → Rel a s X)
    (s : St) (h : retain env u table ids st compose = .ok s) : Rel st s X := by
  have tryOk : ∀ a s, retainTry env ids compose a = .ok s → Rel a s X := by
    intro a s e
    unfold retainTry at e
    split at e
    · cases e
    · rename_i s1 e1
      injection e with e; subst e
      exact Rel.post (hc a s1 e1) (nm_settle env ids s1)
  have rep : ∀ x, Rel st x X → Rel st (addUnmet (.splitPart table u) x) X := fun x hx => Rel.post hx rfl
  have mv : ∀ m, retainTry env ids compose (nextUnit env u st) = .ok m → Rel st m X := fun m e =>
    Rel.via (tryOk _ m e) (nm_nextUnit env u st)
  unfold retain at h
  split at h
  · cases h
  · rename_i ordinary e0
    have o := tryOk st ordinary e0
    split at h
    · split at h
      · injection h with h; subst h
        split
        · exact o
        · exact rep _ o
      · split at h
        · cases h
        · injection h with h; subst h
          split
          · exact o
          · exact rep _ o
    · split at h
      · injection h with h; subst h; exact o
      · split at h
        · cases h
        · rename_i m e1
          injection h with h; subst h
          split
          · exact mv m e1
          · apply rep
            split
            · exact o
            · exact mv m e1

set_option linter.unusedVariables false in
theorem rel_acrossGo (env : Env) (header : List Line) (st : St) (gs : List (Bool × List Line)) (s : St)
    (h : acrossGo env header st gs = .ok s) : Rel st s (notesOf (gs.map (·.2)).join) := by
  match gs with
  | [] => simp only [acrossGo, Except.ok.injEq] at h; subst h; exact Rel.refl st
  | (isRow, ls) :: rest =>
    rw [acrossGo] at h
    split at h
    · split at h
      · cases h
      · rename_i placed e
        have a := rel_putReserved env 0 st placed ls e
        have b := rel_acrossGo env header placed rest s h
        exact Rel.tr a b (by simp [notesOf_append])
    · rename_i hn
      split at h
      · split at h
        · cases h
        · rename_i withHeader e
          split at h
          · cases h
          · rename_i placed e2
            have c := rel_putReserved env 0 _ placed ls e2
            have b := rel_acrossGo env header placed rest s h
            refine Rel.tr (Rel.via c ?_) b (by simp [notesOf_append])
            refine Eq.trans ?_ ((nm_putRepeated env _ withHeader header e).trans (nm_nextColumn env st))
            split
            · rfl
            · exact nm_nextColumn env _
      · have dec : rank (nextColumn env st) < rank st := by
          apply I4_nextColumn_rank; left
          have := (not_or.1 hn).2; simpa using this
        have b := rel_acrossGo env header (nextColumn env st) ((isRow, ls) :: rest) s h
        exact Rel.via b (nm_nextColumn env st)
termination_by (gs.length, rank st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; assumption)

theorem rel_acrossTail (env : Env) (header lastRow caption : List Line) (placed s0 s : St)
    (h : acrossTail env header lastRow caption placed s0 = .ok s) : Rel s0 s (notesOf lastRow ++ notesOf caption) := by
  unfold acrossTail at h
  split at h
  · cases h
  · rename_i rowPlaced e
    have r : Rel s0 rowPlaced (notesOf lastRow) := by
      split at e
      · split at e
        · cases e
        · rename_i wh e1
          have b := rel_acrossGo env header wh _ rowPlaced e
          exact Rel.via (Rel.congr (by simp) b) (nm_putRepeated env _ wh header e1)
      · have b := rel_acrossGo env header s0 _ rowPlaced e
        split at b
        · exact Rel.congr (by simp) b
        · rename_i ne
          have : lastRow = [] := Decidable.of_not_not ne
          subst this; exact Rel.congr (by simp) b
    have c := rel_putReserved env 0 _ s caption h
    refine Rel.tr r (Rel.via c ?_) rfl
    split
    · rfl
    · exact nm_nextColumn env _

theorem splitLast_notes (rows : List (List Line)) :
    notesOf (splitLast rows).1.join ++ notesOf (splitLast rows).2.join = notesOf rows.join := by
  rw [← notesOf_append, ← join_app, splitLast_append]

/-- The groups of `placeTableAcross` and the tail of a lower caption hold
    the notes of the table in the order of `tableNotes`. -/
theorem across_notes (header : List Line) (rows : List (List Line)) (caption : List Line) (below : Bool) :
    notesOf (((if below = false ∧ caption ≠ [] then [(false, caption)] else []) ++
      (if header ≠ [] then [(false, header)] else []) ++
      (if below = true ∧ caption ≠ [] then (splitLast rows).1 else rows).map (fun r => (true, r))).map (·.2)).join ++
    (if below = true ∧ caption ≠ [] then notesOf (splitLast rows).2.join ++ notesOf caption else []) =
    tableNotes header rows caption below := by
  have sl := splitLast_notes rows
  have mc : ∀ rs : List (List Line), List.map ((fun x : Bool × List Line => x.snd) ∘ fun r => (true, r)) rs = rs := by
    intro rs; induction rs <;> simp_all
  cases below <;> by_cases hc : caption = [] <;> by_cases hh : header = [] <;>
    simp [hc, hh, tableNotes, List.map_append, join_app, notesOf_append, map_snd_join, mc] at sl ⊢ <;>
    simp [← sl, List.append_assoc]

theorem rel_placeTableAcross (env : Env) (u : PartUnit) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool) (s : St)
    (h : placeTableAcross env u st ident before header rows caption below = .ok s) :
    Rel st s (tableNotes header rows caption below) := by
  unfold placeTableAcross at h
  dsimp only at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · cases h
      · have st0 : NM (if empty st = true then st else if before + st.pending ≤ room env st then
            { st with used := st.used + st.pending + before, pending := 0, blankActive := false, blankSpans := 0 }
            else nextColumn env st) = NM st := by
          split
          · rfl
          · split
            · rfl
            · exact nm_nextColumn env st
        split at h
        · cases h
        · rename_i placed e
          have a := Rel.via (rel_acrossGo env header _ _ placed e) st0
          split at h
          · rename_i low
            have b := rel_retain env u true _ placed _ _
              (fun a s e => rel_acrossTail env header _ caption placed a s e) s h
            refine Rel.congr ?_ (a.trans b)
            rw [← across_notes header rows caption below]
            simp only [if_pos low, List.nil_append, List.append_nil]
          · rename_i low
            injection h with h; subst h
            refine Rel.congr ?_ a
            rw [← across_notes header rows caption below]
            simp only [if_neg low, List.nil_append, List.append_nil]

/-! ## One flow, and the flows -/

theorem rel_placeFlow (inner : Inner) (hi : NotesOk inner) (env : Env) (st : St) (f : Flow) (s : St)
    (h : placeFlow inner env st f = .ok s) : Rel st s (flowNotes f) := by
  cases f with
  | paragraph k ls => exact Rel.congr (by simp [flowNotes]) (rel_placeLines env k true st ls s h)
  | continued k ls => exact Rel.congr (by simp [flowNotes]) (rel_placeLines env k false st ls s h)
  | ruled r => exact Rel.congr (by simp [flowNotes]) (rel_placeRuled inner env st r [] s h)
  | space n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; exact Rel.congr (by simp [flowNotes]) (Rel.same rfl)
  | blank n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; exact Rel.congr (by simp [flowNotes]) (Rel.same rfl)
  | brk k =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_breakAt env k st))
  | start k =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_sectionStart env k st))
  | switchColumns c =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_switchColumns env c st))
  | restoreColumns =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_restoreColumns env st))
  | defTerm ls => exact Rel.congr (by simp [flowNotes]) (rel_placeLines env _ true st ls s h)
  | stanza k vs => exact Rel.congr (by simp [flowNotes]) (rel_placeStanza env k true st vs s h)
  | code c f k sp rows =>
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_placeCode env c f k sp true st rows s h))
  | wrapped i e ls => exact Rel.congr (by simp [flowNotes]) (rel_placeWrapped env st i e ls s h)
  | table i b header rows caption below =>
    simp only [placeFlow] at h
    split at h
    · exact Rel.congr (by simp [flowNotes]) (rel_placeTableAcross env _ st i b header rows caption below s h)
    · exact Rel.congr (by simp [flowNotes]) (rel_placeTable env st i b header rows caption below s h)
  | bookPart u ids body =>
    exact Rel.congr (by simp [flowNotes])
      (rel_retain env u false ids st _ _ (fun a s e => hi.2 _ a body s e) s h)
  | boxed i b a body => exact Rel.congr (by simp [flowNotes]) (rel_placeBox inner hi env st i b a body s h)
  | heading recto extent ls =>
    simp only [placeFlow] at h
    have a : NM (if recto = true then parityStart env (fun p => p % 2 == 1) st else st) = NM st := by
      split
      · exact nm_parityStart env _ st
      · rfl
    exact Rel.congr (by simp [flowNotes]) (Rel.via (rel_placeHeading env _ _ extent ls s h) a)
  | adjustLines n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_drainCarried env _))
  | noBreak =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_waitForPrior _ _ st))
  | keepNext n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_waitForPrior _ _ st))
  | noBreakLines n =>
    simp only [placeFlow] at h
    split at h
    · injection h with h; subst h; exact Rel.congr (by simp [flowNotes]) (Rel.refl st)
    · injection h with h; subst h
      exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_waitForPrior _ _ st))
  | needLines n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    have : NM (if env.capacity < (n : Int) * env.pagePitch then addUnmet (.needLines n) st else st) = NM st := by
      split <;> rfl
    exact Rel.congr (by simp [flowNotes]) (Rel.same ((nm_judgeNeed env _ _).trans this))
  | pageFigure i =>
    simp only [placeFlow] at h
    split at h
    · injection h with h; subst h
      exact Rel.congr (by simp [flowNotes])
        (Rel.same ((nm_nextPage env _).trans (rfl : NM (putSlot st env.capacity (.pageFigure i)) = NM st)))
    · injection h with h; subst h
      exact Rel.congr (by simp [flowNotes]) (Rel.same rfl)
  | figure i e =>
    simp only [placeFlow] at h
    split at h
    · cases h
    · split at h
      · injection h with h; subst h
        exact Rel.congr (by simp [flowNotes]) (Rel.same rfl)
      · split at h
        · injection h with h; subst h
          exact Rel.congr (by simp [flowNotes]) (Rel.same rfl)
        · injection h with h; subst h
          exact Rel.congr (by simp [flowNotes]) (Rel.same ((nm_fit env st e : NM (fit env st e) = NM st)))

theorem nm_beforeOf (env : Env) (st : St) (flow : Flow) (rest : List Flow) :
    NM (beforeOf env st flow rest) = NM st := by
  have a : NM (if st.blankActive ∧ occupies flow ∧ empty st = false ∧
      room env st < min env.capacity (st.pending + env.firstNeed (decide (0 < st.notesUsed)) 1 (flow :: rest))
      then nextColumn env st else st) = NM st := by
    split
    · exact nm_nextColumn env st
    · rfl
  unfold beforeOf
  dsimp only
  split
  · exact a
  · exact a

theorem rel_placeBody (inner : Inner) (hi : NotesOk inner) (env : Env) (b : St) (flow : Flow) (rest : List Flow)
    (s : St) (h : placeBody inner env b flow rest = .ok s) : Rel b s (flowNotes flow) := by
  unfold placeBody at h
  cases flow with
  | paragraph k ls =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact rel_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h
      exact Rel.congr (by simp [flowNotes]) (rel_placeWithNext inner env k true b ls l f later s h)
  | continued k ls =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact rel_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h
      exact Rel.congr (by simp [flowNotes]) (rel_placeWithNext inner env k false b ls l f later s h)
  | noBreak =>
    simp only [Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_waitForPrior _ _ b))
  | keepNext n =>
    simp only [Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_waitForPrior _ _ b))
  | noBreakLines n =>
    simp only at h
    split at h
    · injection h with h; subst h
      exact Rel.congr (by simp [flowNotes]) (Rel.same (nm_waitForPrior _ _ b))
    · exact rel_placeFlow inner hi env b _ s h
  | ruled r => exact Rel.congr (by simp [flowNotes]) (rel_placeRuledKeeping inner env b r rest s h)
  | figure i e => exact rel_placeFlow inner hi env b _ s h
  | pageFigure i => exact rel_placeFlow inner hi env b _ s h
  | space n => exact rel_placeFlow inner hi env b _ s h
  | blank n => exact rel_placeFlow inner hi env b _ s h
  | brk k => exact rel_placeFlow inner hi env b _ s h
  | needLines n => exact rel_placeFlow inner hi env b _ s h
  | adjustLines n => exact rel_placeFlow inner hi env b _ s h
  | start k => exact rel_placeFlow inner hi env b _ s h
  | switchColumns c => exact rel_placeFlow inner hi env b _ s h
  | restoreColumns => exact rel_placeFlow inner hi env b _ s h
  | code c f k sp rows => exact rel_placeFlow inner hi env b _ s h
  | wrapped i e ls => exact rel_placeFlow inner hi env b _ s h
  | table i bf header rows caption below => exact rel_placeFlow inner hi env b _ s h
  | boxed i bf a body => exact rel_placeFlow inner hi env b _ s h
  | stanza k vs =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact rel_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h
      exact Rel.congr (by simp [flowNotes]) (rel_placeStanzaWithNext inner env k b vs l f later s h)
  | defTerm ls =>
    simp only at h
    split at h
    · exact Rel.congr (by simp [flowNotes]) (rel_placeLines env _ true _ ls s h)
    · exact Rel.congr (by simp [flowNotes])
        (Rel.via (rel_placeLines env _ true _ ls s h) (nm_keepFollowing inner env false b _ ls rest))
  | bookPart u ids body => exact rel_placeFlow inner hi env b _ s h
  | heading recto extent ls =>
    have a : NM (if recto = true then parityStart env (fun p => p % 2 == 1) b
        else keepFollowing inner env true b extent ls rest) = NM b := by
      split
      · exact nm_parityStart env _ b
      · exact nm_keepFollowing inner env true b extent ls rest
    exact Rel.congr (by simp [flowNotes]) (Rel.via (rel_placeHeading env _ _ extent ls s h) a)

theorem rel_placeNext (inner : Inner) (hi : NotesOk inner) (env : Env) (st : St) (flow : Flow) (rest : List Flow)
    (s : St) (h : placeNext inner env st flow rest = .ok s) : Rel st s (flowNotes flow) := by
  unfold placeNext at h
  split at h
  · cases h
  · rename_i p e
    injection h with h; subst h
    have a := Rel.via (rel_placeBody inner hi env _ flow rest p e) (nm_beforeOf env st flow rest)
    refine Rel.post a ?_
    split
    · exact nm_checkWaits p
    · rfl

theorem rel_placeAll (inner : Inner) (hi : NotesOk inner) (env : Env) (st : St) (flows : List Flow) (s : St)
    (h : placeAll inner env st flows = .ok s) : Rel st s (sourceNotes flows) := by
  induction flows generalizing st with
  | nil =>
    simp only [placeAll, Except.ok.injEq] at h; subst h
    exact Rel.congr (by simp [sourceNotes]) (Rel.refl _)
  | cons f fs ih =>
    simp only [placeAll] at h
    split at h
    · cases h
    · rename_i p e
      exact Rel.tr (rel_placeNext inner hi env st f fs p e) (ih p h) (sourceNotes_cons f fs).symm

/-- `placeFlow` at every level reads the notes of the flows. -/
theorem notes_level_ok : ∀ n, NotesOk (level n)
  | 0 => ⟨fun _ _ _ _ h => by simp [level] at h, fun _ _ _ _ h => by simp [level] at h⟩
  | n + 1 => ⟨fun env st f s h => rel_placeFlow (level n) (notes_level_ok n) env st f s h,
      fun env st fs s h => rel_placeAll (level n) (notes_level_ok n) env st fs s h⟩

/-! ## The notes of the pages (invariant 5) -/

theorem paginate_notes (env : Env) (flows : List Flow) (pages : List PageOut)
    (h : paginate env flows = .ok pages) (hn : Sep (sourceNotes flows)) :
    ∀ i, filt i (ex (pagesNotes pages)) = filt i (exN (sourceNotes flows)) := by
  unfold paginate at h
  split at h
  · cases h
  · split at h
    · cases h
    · rename_i final e
      split at h
      · rename_i clean
        have r := rel_placeAll _ (notes_level_ok _) env _ flows final e
        have R := r ⟨fun i => Or.inl rfl, hn⟩
        have n0 : NM (initial env) = [] := rfl
        have R' : ∀ i, filt i (NM final) = filt i (exN (sourceNotes flows)) := fun i => by
          rw [R i, n0, List.nil_append]
        have cy : (drainCarry env final).carry = [] := by
          cases c : (drainCarry env final).carry with
          | nil => rfl
          | cons _ _ => have c2 := clean.2; rw [c] at c2; cases c2
        obtain ⟨c1, _⟩ := close_nm env (drainCarry env final)
        have key : ex (pagesNotes (close env (drainCarry env final)).done.reverse) = NM final := by
          rw [c1, ← nm_drainCarry env final]; simp [NM, cy]
        intro i
        split at h
        · rename_i rr
          injection h with h; subst h
          rw [rr] at key
          have : ex (pagesNotes [⟨1, 0, false, [], [], env.capacity, []⟩]) = NM final := by rw [← key]; rfl
          rw [this]; exact R' i
        · injection h with h; subst h
          rw [key]; exact R' i
      · cases h

/-- Root ADR 0352 invariant 5 for the footnotes of the free placement: the
    pages of the pagination hold no line of a note not read, and, note by
    note, every line of the note's body read, each once, from the first to
    the last.  It assumes that no two notes of the manuscript share a line
    (`Sep`, implied by distinct ids, `sep_of_distinct`). -/
theorem I5_paginate_notes (env : Env) (flows : List Flow) (pages : List PageOut)
    (h : paginate env flows = .ok pages) (hn : Sep (sourceNotes flows)) :
    (∀ i, filt i (exN (sourceNotes flows)) = [] → filt i (ex (pagesNotes pages)) = []) ∧
    (∀ i, filt i (ex (pagesNotes pages)) = filt i (exN (sourceNotes flows))) := by
  have e := paginate_notes env flows pages h hn
  exact ⟨fun i z => by rw [e i]; exact z, e⟩

/-- No two ids of the list are the same. -/
def Distinct : List Nat → Prop
  | [] => True
  | i :: is => i ∉ is ∧ Distinct is

theorem filt_seg_ne (j i f n : Nat) (h : j ≠ i) : filt j (seg i f n) = [] := by
  induction n generalizing f with
  | zero => rfl
  | succ n ih =>
    simp only [seg, filt, List.filter] at *
    have : (i == j) = false := by
      cases h2 : i == j
      · rfl
      · exact absurd (eq_of_beq h2).symm h
    simp [this, ih]

theorem filt_seg_eq (i f n : Nat) : filt i (seg i f n) = seg i f n := by
  induction n generalizing f with
  | zero => rfl
  | succ n ih =>
    simp only [seg, filt, List.filter] at *
    simp [ih]

theorem filt_exN_ne (i : Nat) (ns : List Note) (h : i ∉ ns.map (·.id)) : filt i (exN ns) = [] := by
  induction ns with
  | nil => rfl
  | cons m ms ih =>
    simp only [List.map, List.mem_cons, not_or] at h
    rw [exN_cons, filt_append, noteSeg, filt_seg_ne i m.id 0 m.lines h.1, ih h.2]; rfl

theorem sep_of_distinct (ns : List Note) (h : Distinct (ns.map (·.id))) : Sep ns := by
  induction ns with
  | nil => trivial
  | cons n ns ih =>
    obtain ⟨h1, h2⟩ := h
    refine ⟨fun i => ?_, ih h2⟩
    by_cases e : i = n.id
    · subst e; exact Or.inr (filt_exN_ne _ ns h1)
    · exact Or.inl (filt_seg_ne i n.id 0 n.lines e)

theorem filt_exN_mem (ns : List Note) (h : Distinct (ns.map (·.id))) (n : Note) (m : n ∈ ns) :
    filt n.id (exN ns) = noteSeg n := by
  induction ns with
  | nil => cases m
  | cons k ks ih =>
    obtain ⟨h1, h2⟩ := h
    rw [exN_cons, filt_append]
    cases m with
    | head => rw [noteSeg, filt_seg_eq, filt_exN_ne _ ks h1, List.append_nil]
    | tail _ m =>
      have ne : n.id ≠ k.id := by
        intro e; apply h1; show k.id ∈ _; rw [← e]; exact List.mem_map_of_mem _ m
      rw [noteSeg, filt_seg_ne _ _ _ _ ne, ih h2 m]; rfl

/-- Root ADR 0352 invariant 5 for each footnote of the free placement, when
    the note ids of the manuscript are distinct: the lines of note `n` on the
    pages are its lines 0, 1, ..., `n.lines - 1`, each once and in this
    order. -/
theorem I5_paginate_each_note (env : Env) (flows : List Flow) (pages : List PageOut)
    (h : paginate env flows = .ok pages)
    (hd : Distinct ((sourceNotes flows).map (·.id))) (n : Note) (m : n ∈ sourceNotes flows) :
    filt n.id (ex (pagesNotes pages)) = seg n.id 0 n.lines := by
  rw [(I5_paginate_notes env flows pages h (sep_of_distinct _ hd)).2 n.id, filt_exN_mem _ hd n m]; rfl


end Notes
end PhysicalPagination
