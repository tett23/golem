/-
Root ADR 0352 invariant 5 for the footnotes of the grid mode.

Every line of every footnote body read is placed once on the pages of
`paginate` of Whole.lean, and the lines of one note are placed from its
first line to its last, unless the pagination reports the note as
unplaceable (`unplaceableFootnote`).  The statement is made note by note
(`filt`): the lines of different notes may come in another order than
the manuscript's (README.md).
-/
import Whole

namespace WholePagination
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

theorem splitNotes_lines : ∀ (r : Int) (ns : List Note),
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
        have t := Int.toNat_of_nonneg (Int.le_of_lt h2)
        have e : len = r.toNat + (len - r.toNat) := by omega
        conv => rhs; rw [e, seg_add]
        simp
      · simp only [ex_cons, ex_nil, List.nil_append, map_rest, exN_cons]; rfl

/-! ## What the state holds -/

def pagesNotes (done : List PageOut) : List NotePart := done.reverse.bind (·.notes)

theorem pagesNotes_cons (p : PageOut) (done : List PageOut) :
    pagesNotes (p :: done) = pagesNotes done ++ p.notes := by
  simp [pagesNotes, List.reverse_cons, List.append_bind]

/-- The note lines of the pages closed, of the current column and carried
    on to the next column. -/
def NM (st : St) : List (Nat × Nat) := ex (pagesNotes st.done) ++ ex st.notes ++ ex st.pending

/-- The controls not met of the pages closed and of the current column. -/
def allUnmet (st : St) : List Unmet := st.done.reverse.bind (·.unmet) ++ st.unmet

def Dropped (st : St) (i : Nat) : Prop := ∃ c, Unmet.unplaceableFootnote i c ∈ allUnmet st

/-- From `a` to `b` the pages and columns closed stay as they are, and
    the slots of the current column stay at its start or go, as they are
    with what follows them, to a column closed. -/
def Keeps (a b : St) : Prop :=
  (∃ ds, b.done = ds ++ a.done) ∧
    ((∃ xs, b.slots = a.slots ++ xs) ∨ ∃ p ∈ b.done, ∃ xs, p.slots = a.slots ++ xs)

theorem Keeps.refl (a : St) : Keeps a a := ⟨⟨[], rfl⟩, Or.inl ⟨[], by simp⟩⟩

theorem Keeps.same {a b : St} (hd : b.done = a.done) (hs : b.slots = a.slots) : Keeps a b :=
  ⟨⟨[], by simp [hd]⟩, Or.inl ⟨[], by simp [hs]⟩⟩

theorem Keeps.trans {a b c : St} (h1 : Keeps a b) (h2 : Keeps b c) : Keeps a c := by
  obtain ⟨⟨d1, e1⟩, s1⟩ := h1
  obtain ⟨⟨d2, e2⟩, s2⟩ := h2
  have mem : ∀ p ∈ b.done, p ∈ c.done := fun p m => by rw [e2]; exact List.mem_append_of_mem_right _ m
  refine ⟨⟨d2 ++ d1, by rw [e2, e1, List.append_assoc]⟩, ?_⟩
  rcases s1 with ⟨xs, ex⟩ | ⟨p, mp, xs, ep⟩
  · rcases s2 with ⟨ys, ey⟩ | ⟨q, mq, ys, eq⟩
    · exact Or.inl ⟨xs ++ ys, by rw [ey, ex, List.append_assoc]⟩
    · exact Or.inr ⟨q, mq, xs ++ ys, by rw [eq, ex, List.append_assoc]⟩
  · exact Or.inr ⟨p, mem p mp, xs, ep⟩

theorem Keeps.put {a b : St} (hd : b.done = a.done) (xs : List (Int × Slot)) (hs : b.slots = a.slots ++ xs) :
    Keeps a b :=
  ⟨⟨[], by simp [hd]⟩, Or.inl ⟨xs, hs⟩⟩

/-- A column closed with the slots of the current one, and the slots
    started anew. -/
theorem Keeps.closed {a b : St} (hd : ∃ ds, b.done = ds ++ a.done)
    (hc : a.slots ≠ [] → ∃ p ∈ b.done, p.slots = a.slots) : Keeps a b := by
  refine ⟨hd, ?_⟩
  by_cases e : a.slots = []
  · exact Or.inl ⟨b.slots, by rw [e]; rfl⟩
  · obtain ⟨p, m, h⟩ := hc e
    exact Or.inr ⟨p, m, [], by rw [h, List.append_nil]⟩

theorem Keeps.cons {a b : St} (p : PageOut) (hd : b.done = p :: a.done) (hs : b.slots = a.slots) : Keeps a b :=
  ⟨⟨[p], hd⟩, Or.inl ⟨[], by simp [hs]⟩⟩

/-- A frame: the pages closed stay, and slots are only added. -/
syntax "keeps_frame" : tactic
macro_rules
  | `(tactic| keeps_frame) => `(tactic| first | exact Keeps.same rfl rfl | exact Keeps.put rfl _ rfl)

def Grows (st s : St) : Prop := (∃ u, allUnmet s = allUnmet st ++ u) ∧ Keeps st s

theorem Grows.refl (st : St) : Grows st st := ⟨⟨[], by simp⟩, Keeps.refl st⟩

theorem Grows.trans {a b c : St} (h1 : Grows a b) (h2 : Grows b c) : Grows a c := by
  obtain ⟨⟨u, e⟩, k1⟩ := h1; obtain ⟨⟨v, f⟩, k2⟩ := h2
  exact ⟨⟨u ++ v, by rw [f, e, List.append_assoc]⟩, k1.trans k2⟩

theorem Grows.of_eq {a b : St} (h : allUnmet b = allUnmet a) (k : Keeps a b) : Grows a b := ⟨⟨[], by simp [h]⟩, k⟩

theorem Grows.dropped {a b : St} (h : Grows a b) {i : Nat} (d : Dropped a i) : Dropped b i := by
  obtain ⟨⟨u, e⟩, _⟩ := h; obtain ⟨c, m⟩ := d
  exact ⟨c, by rw [e]; exact List.mem_append_of_mem_left _ m⟩

/-- From `st` to `s` the note lines `Y` are added, note by note; a note
    reported unplaceable may have lost lines, and no note gets lines
    neither held nor added. -/
def R0 (st s : St) (Y : List (Nat × Nat)) : Prop :=
  Grows st s ∧ (∀ i, filt i (NM st ++ Y) = [] → filt i (NM s) = []) ∧
    (∀ i, ¬ Dropped s i → filt i (NM s) = filt i (NM st ++ Y))

theorem R0.refl (st : St) : R0 st st [] :=
  ⟨Grows.refl st, fun i h => by simpa using h, fun i _ => by simp⟩

theorem R0.trans {a b c : St} {Y1 Y2 : List (Nat × Nat)} (h1 : R0 a b Y1) (h2 : R0 b c Y2) :
    R0 a c (Y1 ++ Y2) := by
  obtain ⟨g1, s1, e1⟩ := h1; obtain ⟨g2, s2, e2⟩ := h2
  refine ⟨g1.trans g2, fun i h => ?_, fun i nd => ?_⟩
  · rw [← List.append_assoc, filt_append, append_eq_nil'] at h
    exact s2 i (by rw [filt_append, s1 i h.1, h.2]; rfl)
  · have nd1 : ¬ Dropped b i := fun d => nd (g2.dropped d)
    rw [e2 i nd, filt_append, e1 i nd1, ← filt_append, List.append_assoc]

theorem R0.of_eq {st s : St} {Y : List (Nat × Nat)} (h : NM s = NM st ++ Y) (g : Grows st s) : R0 st s Y :=
  ⟨g, fun i e => by rw [h]; exact e, fun i _ => by rw [h]⟩

theorem R0.same {st s : St} (h : NM s = NM st) (g : Grows st s) : R0 st s [] :=
  R0.of_eq (by rw [h, List.append_nil]) g

/-- `st'` holds what `st` holds but `Z`, which goes on to `c`. -/
theorem R0.pre {st st' c : St} {Z : List (Nat × Nat)} (e : NM st' ++ Z = NM st) (g : Grows st st')
    (h : R0 st' c Z) : R0 st c [] := by
  obtain ⟨g1, s1, e1⟩ := h
  refine ⟨g.trans g1, fun i h => ?_, fun i nd => ?_⟩
  · rw [List.append_nil] at h; rw [← e] at h; exact s1 i h
  · rw [e1 i nd, e, List.append_nil]

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
    note, if they are new. -/
def Rel (st s : St) (X : List Note) : Prop := Fresh st X → R0 st s (exN X)

theorem Rel.refl (st : St) : Rel st st [] := fun _ => R0.refl st

theorem Rel.of_R0 {st s : St} (h : R0 st s []) : Rel st s [] := fun _ => h

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
      · exact Or.inl (r1.2.1 i (by rw [filt_append, e, e']; rfl))
      · exact Or.inr e'
    · exact Or.inr e
  have r2 := h2 f2
  rw [exN_append]
  exact r1.trans r2

theorem Rel.congr {st s : St} {X X' : List Note} (e : X = X') (h : Rel st s X) : Rel st s X' := e ▸ h

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

/-! ## The operations of State.hs -/

theorem R0.of_filt {st s : St} {Y : List (Nat × Nat)} (h : ∀ i, filt i (NM s) = filt i (NM st ++ Y))
    (g : Grows st s) : R0 st s Y :=
  ⟨g, fun i e => by rw [h]; exact e, fun i _ => h i⟩

theorem R0.frame {st s : St} (hd : s.done = st.done) (hn : s.notes = st.notes) (hp : s.pending = st.pending)
    (hu : s.unmet = st.unmet) (hk : Keeps st s := by keeps_frame) :
    R0 st s [] :=
  R0.same (by simp [NM, hd, hn, hp]) (Grows.of_eq (by simp [allUnmet, hd, hu]) hk)

theorem Rel.frame {st s : St} (hd : s.done = st.done) (hn : s.notes = st.notes) (hp : s.pending = st.pending)
    (hu : s.unmet = st.unmet) (hk : Keeps st s := by keeps_frame) :
    Rel st s [] := Rel.of_R0 (R0.frame hd hn hp hu hk)

theorem R0.addU (u : Unmet) (st : St) : R0 st (addUnmet u st) [] :=
  R0.same (by simp [NM, addUnmet]) ⟨⟨[u], by simp [allUnmet, addUnmet, List.append_assoc]⟩, Keeps.same rfl rfl⟩

theorem Rel.addU (u : Unmet) (st : St) : Rel st (addUnmet u st) [] := Rel.of_R0 (R0.addU u st)

/-- A line or block put with the parts `sp` of its notes shown and carried. -/
theorem R0.put {st s : St} {Y : List (Nat × Nat)} (sp : List NotePart × List NotePart)
    (hy : ex sp.1 ++ ex sp.2 = Y) (hd : s.done = st.done) (hn : s.notes = st.notes ++ sp.1)
    (hp : s.pending = st.pending ++ sp.2) (g : Grows st s) (d : Disj (NM st) Y) : R0 st s Y := by
  refine R0.of_filt (fun i => ?_) g
  have e : NM s = (ex (pagesNotes st.done) ++ ex st.notes) ++ ex sp.1 ++ (ex st.pending ++ ex sp.2) := by
    simp [NM, hd, hn, hp, ex_append, List.append_assoc]
  rw [e]
  exact filt_swap _ _ _ _ _ hy (by simpa [NM, List.append_assoc] using d) i

theorem rel_putLineKeeping (env : Env) (r : Int) (st : St) (l : Line) :
    Rel st (putLineKeeping env r st l) l.notes := by
  intro ⟨d, _⟩
  exact R0.put (splitNotes _ l.notes) (splitNotes_lines _ _) rfl rfl rfl (Grows.of_eq rfl (Keeps.put rfl _ rfl)) d

theorem rel_putLine (env : Env) (st : St) (l : Line) : Rel st (putLine env st l) l.notes :=
  rel_putLineKeeping env 0 st l

theorem rel_putBlock (env : Env) (st : St) (n : Nat) (ls : List Line) :
    Rel st (putBlock env st n ls) (ls.bind (·.notes)) := by
  cases ls with
  | nil => exact Rel.refl st
  | cons l0 ls =>
    intro ⟨d, _⟩
    exact R0.put (splitNotes _ ((l0 :: ls).bind (·.notes))) (splitNotes_lines _ _) rfl rfl rfl
      ⟨⟨if free env st < n then [Unmet.tallHeading l0.id n (free env st)] else [],
        by simp [allUnmet, putBlock, List.append_assoc]⟩, Keeps.put rfl _ rfl⟩ d

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

/-! ## The next column -/

theorem closePage_facts (env : Env) (st : St) :
    pagesNotes (closePage env st).done = pagesNotes st.done ++ st.notes ∧
      (closePage env st).done.reverse.bind (·.unmet) ++ (closePage env st).unmet = allUnmet st ∧
      (closePage env st).pending = st.pending := by
  simp only [closePage]
  split
  · rename_i e
    have n : st.notes = [] := isEmpty_nil _ e.2
    simp [n, allUnmet]
  · simp [pagesNotes_cons, allUnmet, List.reverse_cons, List.append_bind]

theorem advanceFresh_NM (env : Env) (b : Bool) (st : St) :
    NM (advanceFresh env b st) ++ ex st.pending = NM st ∧ allUnmet (advanceFresh env b st) = allUnmet st ∧
      (advanceFresh env b st).pending = [] := by
  obtain ⟨c1, c2, _⟩ := closePage_facts env st
  simp only [advanceFresh]
  generalize closePage env st = C at *
  refine ⟨?_, ?_, ?_⟩ <;> (repeat' split)
  all_goals first
    | trivial
    | simp [NM, pagesNotes_cons, c1, ex_append, List.append_assoc]; done
    | (rw [← c2]; simp [allUnmet, List.reverse_cons, List.append_bind]; done)
    | (rw [← c2]; rfl)

theorem pageFigures_NM (env : Env) (ts : List Nat) (st : St) :
    NM (ts.foldl (pageFigure env) st) = NM st ∧ allUnmet (ts.foldl (pageFigure env) st) = allUnmet st ∧
      (ts.foldl (pageFigure env) st).pending = st.pending := by
  induction ts generalizing st with
  | nil => exact ⟨rfl, rfl, rfl⟩
  | cons t ts ih =>
    simp only [List.foldl]
    obtain ⟨a, b, c⟩ := ih (pageFigure env st t)
    refine ⟨a.trans ?_, b.trans ?_, c⟩
    · simp [NM, pageFigure, pagesNotes_cons]
    · simp [allUnmet, pageFigure, List.reverse_cons, List.append_bind]

/-- Nothing waits, or nothing more of the notes waiting fits. -/
def J (env : Env) (s : St) : Prop := s.pending = [] ∨ carryRoom env s = 0

theorem carryRoom_nonneg (env : Env) (s : St) : 0 ≤ carryRoom env s := by
  simp only [carryRoom]; exact Int.le_max_left _ _

theorem carryRoom_after (env : Env) (hs : 0 ≤ env.separator) (s r : St) (sh : Nat)
    (hc : cap env r = cap env s) (hn : r.noteLines = s.noteLines + carrySep env s + sh)
    (he : (sh : Int) = carryRoom env s) : carryRoom env r = 0 := by
  have z := carryRoom_nonneg env s
  simp only [carryRoom, carrySep] at *
  rw [hc, hn]
  rw [Int.max_def] at he ⊢
  split at he <;> split <;> split <;> split at * <;> omega

theorem carryNote_step (env : Env) (hs : 0 ≤ env.separator) (s : St) (p : NotePart) (hj : J env s) :
    R0 s (carryNote env s p) (partLines p) ∧ J env (carryNote env s p) := by
  obtain ⟨i, f, n⟩ := p
  simp only [carryNote]
  split
  · refine ⟨⟨⟨⟨[Unmet.unplaceableFootnote i (cap env s)], by simp [allUnmet, addUnmet, List.append_assoc]⟩,
      Keeps.same rfl rfl⟩, ?_, ?_⟩, hj⟩
    · intro j h; rw [filt_append, append_eq_nil'] at h; exact h.1
    · intro j nd
      have ne : j ≠ i := by
        intro e; subst e; exact nd ⟨cap env s, by
          simp only [allUnmet, addUnmet]
          exact List.mem_append_of_mem_right _ (List.mem_append_of_mem_right _ (List.Mem.head _))⟩
      show filt j (NM s) = filt j (NM s ++ seg i f n)
      rw [filt_append, filt_seg_ne j i f n ne, List.append_nil]
  · have z := carryRoom_nonneg env s
    have t := Int.toNat_of_nonneg z
    have shl : carryShown env s n ≤ n := Nat.min_le_left _ _
    have shr : carryShown env s n ≤ (carryRoom env s).toNat := Nat.min_le_right _ _
    have shc : carryShown env s n < n → ((carryShown env s n : Nat) : Int) = carryRoom env s := by
      intro c
      have hR : (carryRoom env s).toNat ≤ n := by
        rcases Nat.le_total n (carryRoom env s).toNat with h | h
        · simp only [carryShown] at c; rw [Nat.min_eq_left h] at c; exact absurd c (Nat.lt_irrefl _)
        · exact h
      simp only [carryShown]; rw [Nat.min_eq_right hR, t]
    generalize carryShown env s n = sh at *
    have room0 : carryRoom env s = 0 → sh = 0 := by intro c; rw [c] at shr; simpa using shr
    rcases hj with hp | hr
    · refine ⟨R0.of_eq ?_ (Grows.of_eq rfl (Keeps.same rfl rfl)), ?_⟩
      · simp only [NM, hp, ex_append, ex_nil, List.append_nil, ex_cons, partLines, List.nil_append]
        split
        · have e : n = sh + (n - sh) := by omega
          conv => rhs; rw [e, seg_add]
          simp [ex_cons, partLines, List.append_assoc]
        · have e : sh = n := by omega
          simp [e, List.append_assoc]
      · split
        · exact Or.inr (carryRoom_after env hs s _ sh rfl rfl (shc (by assumption)))
        · exact Or.inl (by simp [hp])
    · have sh0 := room0 hr
      subst sh0
      refine ⟨R0.of_eq ?_ (Grows.of_eq rfl (Keeps.same rfl rfl)), Or.inr ?_⟩
      · simp only [NM, ex_append, ex_cons, ex_nil, partLines, seg, List.append_nil, List.append_assoc]
        split
        · simp [ex_cons, partLines]
        · have : n = 0 := by omega
          subst this; simp [seg]
      · exact carryRoom_after env hs s _ 0 rfl rfl (by rw [hr]; rfl)

theorem carryAll_R0 (env : Env) (hs : 0 ≤ env.separator) (ps : List NotePart) (s : St) (hj : J env s) :
    R0 s (ps.foldl (carryNote env) s) (ex ps) := by
  induction ps generalizing s with
  | nil => exact R0.refl s
  | cons p ps ih =>
    simp only [List.foldl]
    obtain ⟨a, b⟩ := carryNote_step env hs s p hj
    exact a.trans (ih _ b)

theorem placeDeferred_NM (env : Env) (ws : List Deferred) (st : St) :
    NM (placeDeferred env st ws) = NM st ∧ allUnmet (placeDeferred env st ws) = allUnmet st := by
  induction ws generalizing st with
  | nil => exact ⟨rfl, rfl⟩
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · obtain ⟨a, b⟩ := ih (putSlot st n (.figure i)); exact ⟨a, b⟩
      · exact ⟨rfl, rfl⟩
    | pageFigure i => exact ⟨rfl, rfl⟩

theorem keeps_closePage (env : Env) (st : St) : Keeps st (closePage env st) := by
  unfold closePage; split
  · exact Keeps.refl st
  · exact Keeps.cons ⟨st.page, st.column, false, st.slots, st.notes, st.unmet, st.rules⟩ rfl rfl

theorem closePage_closes (env : Env) (st : St) (ne : st.slots ≠ []) :
    ∃ p ∈ (closePage env st).done, p.slots = st.slots := by
  unfold closePage; split
  · rename_i h; exact absurd (isEmpty_nil _ h.1) ne
  · exact ⟨_, List.mem_cons_self _ _, rfl⟩

theorem keeps_startSet (env : Env) (st : St) (n : Nat) (first : Int) : Keeps st (startSet env st n first) :=
  Keeps.closed (keeps_closePage env st).1 (closePage_closes env st)

theorem keeps_advanceFresh (env : Env) (b : Bool) (st : St) : Keeps st (advanceFresh env b st) := by
  refine Keeps.closed ?_ ?_
  · unfold advanceFresh closePage; dsimp only
    repeat' split
    all_goals first | exact ⟨[], rfl⟩ | exact ⟨[_], rfl⟩ | exact ⟨[_, _], rfl⟩
  · intro ne
    have e : ¬ (st.slots.isEmpty = true ∧ st.notes.isEmpty = true) := by
      intro h; apply ne; cases e : st.slots with
      | nil => rfl
      | cons _ _ => rw [e] at h; simp [List.isEmpty] at h
    unfold advanceFresh closePage; dsimp only
    simp only [e, ite_false]
    split
    · exact ⟨_, List.mem_cons_of_mem _ (List.mem_cons_self _ _), rfl⟩
    · exact ⟨_, List.mem_cons_self _ _, rfl⟩

theorem keeps_pageFigures (env : Env) (ts : List Nat) (st : St) : Keeps st (ts.foldl (pageFigure env) st) := by
  induction ts generalizing st with
  | nil => exact Keeps.refl st
  | cons t ts ih => exact Keeps.trans (by exact Keeps.cons ⟨st.page, 0, false, [(0, .pageFigure t)], [], [], []⟩ rfl rfl) (ih _)

theorem keeps_carryAll (env : Env) (ps : List NotePart) (st : St) : Keeps st (ps.foldl (carryNote env) st) := by
  induction ps generalizing st with
  | nil => exact Keeps.refl st
  | cons p ps ih =>
    refine Keeps.trans ?_ (ih _)
    unfold carryNote; split
    · exact Keeps.same rfl rfl
    · exact Keeps.same rfl rfl

theorem keeps_placeDeferred (env : Env) (ws : List Deferred) (st : St) : Keeps st (placeDeferred env st ws) := by
  induction ws generalizing st with
  | nil => exact Keeps.refl st
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · exact Keeps.trans (by exact Keeps.put rfl _ rfl) (ih _)
      · exact Keeps.same rfl rfl
    | pageFigure i => exact Keeps.same rfl rfl

theorem keeps_openColumn (env : Env) (base : St) (turned : List Nat) (notes : List NotePart) (ws : List Deferred) :
    Keeps base (openColumn env base turned notes ws) :=
  (keeps_pageFigures env turned base).trans ((keeps_carryAll env notes _).trans
    (Keeps.trans (by exact Keeps.same rfl rfl) (keeps_placeDeferred env ws _)))

theorem keeps_openBox (st : St) : Keeps st (openBox st) := Keeps.same (openBox_done st) (openBox_slots st)

theorem keeps_advance (env : Env) (b : Bool) (st : St) : Keeps st (advance env b st) :=
  (keeps_advanceFresh env b st).trans ((keeps_openColumn env _ _ _ _).trans (keeps_openBox _))

theorem R0.adv (env : Env) (hs : 0 ≤ env.separator) (b : Bool) (st : St) : R0 st (advance env b st) [] := by
  obtain ⟨f1, f2, f3⟩ := advanceFresh_NM env b st
  have k1 := keeps_advanceFresh env b st
  simp only [advance, advanceIn, openColumn]
  generalize advanceFresh env b st = F at *
  obtain ⟨g1, g2, g3⟩ := pageFigures_NM env (advanceTurned b st).1 F
  have k2 := k1.trans (keeps_pageFigures env (advanceTurned b st).1 F)
  generalize List.foldl (pageFigure env) F (advanceTurned b st).1 = F' at *
  have c := carryAll_R0 env hs st.pending F' (Or.inl (g3.trans f3))
  generalize st.pending.foldl (carryNote env) F' = C at *
  obtain ⟨d1, d2⟩ := placeDeferred_NM env (advanceTurned b st).2 { C with deferred := [] }
  have o : R0 C (openBox (placeDeferred env { C with deferred := [] } (advanceTurned b st).2)) [] :=
    R0.same (by rw [NM, openBox_done, openBox_notes, openBox_pending, ← NM, d1]; rfl)
      (Grows.of_eq (by rw [allUnmet, openBox_done, openBox_unmet, ← allUnmet, d2]; rfl)
        (Keeps.trans (by exact Keeps.same rfl rfl) ((keeps_placeDeferred env _ _).trans (keeps_openBox _))))
  have := c.trans o
  rw [List.append_nil] at this
  exact R0.pre (by rw [g1, f1]) (Grows.of_eq (by rw [g2, f2]) k2) this

theorem rel_nextColumn (env : Env) (hs : 0 ≤ env.separator) (st : St) : Rel st (nextColumn env st) [] :=
  Rel.of_R0 (R0.adv env hs _ st)

theorem rel_nextPage (env : Env) (hs : 0 ≤ env.separator) (st : St) : Rel st (nextPage env st) [] :=
  Rel.of_R0 (R0.adv env hs _ st)

/-! ## The flows read, by their notes -/

mutual
/-- The notes of the lines of the flows written.  The rows of a code
    block carry no notes: golem-typeset makes them without notes
    (Flow.hs:3814) and `placeCode` of Paginate.hs reads none. -/
def flowNotes : Flow → List Note
  | .paragraph _ ls => ls.bind (·.notes)
  | .continued _ ls => ls.bind (·.notes)
  | .defTerm ls => ls.bind (·.notes)
  | .stanza _ vs => vs.join.bind (·.notes)
  | .wrapped _ _ beside => beside.bind (·.notes)
  | .heading _ _ ls => ls.bind (·.notes)
  | .table _ h rows capt below => (tableLines h rows capt below).bind (·.notes)
  | .bookPart _ _ _ body | .boxed _ _ _ body => sourceNotes body
  | .ruled _ _ _ _ (.lines _ ls) => ls.bind (·.notes)
  | .ruled _ _ _ _ (.heading _ _ ls) => ls.bind (·.notes)
  | _ => []
termination_by f => sizeOf f
def sourceNotes : List Flow → List Note
  | [] => []
  | g :: r => flowNotes g ++ sourceNotes r
termination_by fs => sizeOf fs
end

theorem sourceNotes_append (a b : List Flow) : sourceNotes (a ++ b) = sourceNotes a ++ sourceNotes b := by
  induction a with
  | nil => simp [sourceNotes]
  | cons x xs ih => simp only [List.cons_append, sourceNotes, ih, List.append_assoc]

theorem sourceNotes_flatten (fs : List Flow) : sourceNotes (flattenParts fs) = sourceNotes fs := by
  match fs with
  | [] => simp [flattenParts, sourceNotes]
  | f :: r =>
    have := sourceNotes_flatten r
    cases f with
    | bookPart u k i b =>
      have := sourceNotes_flatten b
      simp only [flattenParts, sourceNotes_append, sourceNotes, flowNotes, *]
    | boxed j kb ka b =>
      have := sourceNotes_flatten b
      simp only [flattenParts, sourceNotes, flowNotes, *]
    | _ => simp only [flattenParts, sourceNotes, *]
termination_by sizeOf fs

/-! ## Composing the steps -/

theorem Rel.tr {a b c : St} {X1 X2 X : List Note} (h1 : Rel a b X1) (h2 : Rel b c X2) (e : X1 ++ X2 = X) :
    Rel a c X := e ▸ h1.trans h2

theorem Rel.nl {a b c : St} {X : List Note} (h1 : Rel a b []) (h2 : Rel b c X) : Rel a c X :=
  Rel.tr h1 h2 (List.nil_append _)

theorem Rel.nr {a b c : St} {X : List Note} (h1 : Rel a b X) (h2 : Rel b c []) : Rel a c X :=
  Rel.tr h1 h2 (List.append_nil _)

theorem Rel.fl {st s c : St} {X : List Note} (h : Rel s c X) (hd : s.done = st.done := by rfl)
    (hn : s.notes = st.notes := by rfl) (hp : s.pending = st.pending := by rfl) (hu : s.unmet = st.unmet := by rfl)
    (hk : Keeps st s := by keeps_frame) : Rel st c X :=
  Rel.nl (Rel.frame hd hn hp hu hk) h

theorem Rel.fr {st s c : St} {X : List Note} (h : Rel st s X) (hd : c.done = s.done := by rfl)
    (hn : c.notes = s.notes := by rfl) (hp : c.pending = s.pending := by rfl) (hu : c.unmet = s.unmet := by rfl)
    (hk : Keeps s c := by keeps_frame) : Rel st c X :=
  Rel.nr h (Rel.frame hd hn hp hu hk)

theorem Rel.ite {c : Prop} [Decidable c] {st a b : St} {X : List Note} (ha : Rel st a X) (hb : Rel st b X) :
    Rel st (if c then a else b) X := by
  split
  · exact ha
  · exact hb

theorem Rel.blankP (env : Env) (st : St) : Rel st (blankPage env st) [] :=
  Rel.of_R0 (R0.same (by simp [NM, blankPage, pagesNotes_cons])
    (Grows.of_eq (by simp [allUnmet, blankPage, List.reverse_cons, List.append_bind])
      (by exact Keeps.cons ⟨st.page, 0, true, [], [], [], []⟩ rfl rfl)))

theorem Rel.pageF (env : Env) (st : St) (i : Nat) : Rel st (pageFigure env st i) [] :=
  Rel.of_R0 (R0.same (by simp [NM, pageFigure, pagesNotes_cons])
    (Grows.of_eq (by simp [allUnmet, pageFigure, List.reverse_cons, List.append_bind])
      (by exact Keeps.cons ⟨st.page, 0, false, [(0, .pageFigure i)], [], [], []⟩ rfl rfl)))

theorem Rel.oBox (st : St) : Rel st (openBox st) [] :=
  Rel.frame (openBox_done st) (openBox_notes st) (openBox_pending st) (openBox_unmet st) (Keeps.same (openBox_done st) (openBox_slots st))

theorem Rel.addUs (us : List Unmet) (st : St) : Rel st (us.foldl (fun s u => addUnmet u s) st) [] := by
  induction us generalizing st with
  | nil => exact Rel.refl st
  | cons u us ih => simp only [List.foldl]; exact Rel.nl (Rel.addU u st) (ih _)

/-- Joining a part to the part before it of the same note keeps the lines. -/
theorem ex_joinNotePart (parts : List NotePart) (q : NotePart) :
    ex (joinNotePart parts q) = ex parts ++ partLines q := by
  unfold joinNotePart
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

theorem ex_foldl_joinNotePart (parts qs : List NotePart) :
    ex (qs.foldl joinNotePart parts) = ex parts ++ ex qs := by
  induction qs generalizing parts with
  | nil => simp
  | cons q qs ih =>
    simp only [List.foldl]; rw [ih, ex_joinNotePart, ex_cons, List.append_assoc]

theorem takeNoteLines_lines (r : Int) (ps : List NotePart) :
    ex (takeNoteLines r ps).1 ++ ex (takeNoteLines r ps).2 = ex ps := by
  induction ps generalizing r with
  | nil => rfl
  | cons p more ih =>
    obtain ⟨i, f, l⟩ := p
    simp only [takeNoteLines]
    split
    · rfl
    · split
      · simp only [ex_cons, List.append_assoc, ih]
      · rename_i h1 h2
        have t := Int.toNat_of_nonneg (show 0 ≤ r by omega)
        simp only [ex_cons, ex_nil, List.append_nil, partLines, ← List.append_assoc]
        rw [← seg_add, show r.toNat + (l - r.toNat) = l by omega]

/-- `drainPendingNotes` moves lines of the notes continued to the column,
    in their order, and keeps every line of every note: the lines of the
    notes of the pages, of the column and continued, in this order, stay
    as they are, so the continued notes come before any note placed after
    them (root ADR 0444 I1 for `@page-lines` on the grid). -/
theorem nm_drainPendingNotes (env : Env) (st : St) : NM (drainPendingNotes env st) = NM st := by
  unfold drainPendingNotes
  split
  · rfl
  · dsimp only [NM]
    rw [ex_foldl_joinNotePart, List.append_assoc, List.append_assoc, List.append_assoc, takeNoteLines_lines]

theorem rel_drainPendingNotes (env : Env) (st : St) : Rel st (drainPendingNotes env st) [] := by
  obtain ⟨ns, nl, ps, e⟩ := drainPendingNotes_eq env st
  have n := nm_drainPendingNotes env st
  rw [e] at n ⊢
  exact Rel.of_R0 (R0.same n (Grows.of_eq rfl (Keeps.same rfl rfl)))

theorem Rel.dropBlanks (ns : List Nat) (st : St) :
    Rel st (ns.foldl (fun s _ => addUnmet .droppedBlank s) st) [] := by
  induction ns generalizing st with
  | nil => exact Rel.refl st
  | cons n ns ih => simp only [List.foldl]; exact Rel.nl (Rel.addU _ st) (ih _)

section
variable (env : Env) (hs : 0 ≤ env.separator)

theorem rel_keep (st : St) (need : St → Int) : Rel st (keep env st need) [] := by
  by_cases h : free env st < need st ∧ isEmpty st = false
  · unfold keep; rw [dif_pos h]; exact Rel.nl (rel_nextColumn env hs st) (rel_keep (nextColumn env st) need)
  · unfold keep; rw [dif_neg h]; exact Rel.refl st
termination_by rank env st
decreasing_by exact I4_nextColumn_rank env st (Or.inl h.2)

theorem rel_flushDeferred (st : St) : Rel st (flushDeferred env st) [] := by
  by_cases h : st.deferred = [] ∧ st.pending = []
  · unfold flushDeferred; rw [dif_pos h]; exact Rel.refl st
  · unfold flushDeferred; rw [dif_neg h]
    exact Rel.nl (rel_nextColumn env hs st) (rel_flushDeferred (nextColumn env st))
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st h)

theorem flushDeferred_pending (st : St) : (flushDeferred env st).pending = [] := by
  by_cases h : st.deferred = [] ∧ st.pending = []
  · unfold flushDeferred; rw [dif_pos h]; exact h.2
  · unfold flushDeferred; rw [dif_neg h]; exact flushDeferred_pending (nextColumn env st)
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st h)

theorem rel_flushFigures (st : St) : Rel st (flushFigures env st) [] := by
  by_cases h : st.deferred = []
  · unfold flushFigures; rw [dif_pos h]; exact Rel.refl st
  · unfold flushFigures; rw [dif_neg h]
    exact Rel.nl (rel_nextColumn env hs st) (rel_flushFigures (nextColumn env st))
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st (fun c => h c.1))

theorem rel_parityStart (p : Nat → Bool) (st : St) : Rel st (parityStart env p st) [] := by
  simp only [parityStart]
  have h0 := rel_flushDeferred env hs st
  have h1 : Rel st (if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then
      flushDeferred env st else nextPage env (flushDeferred env st)) [] :=
    Rel.ite h0 (Rel.nl h0 (rel_nextPage env hs _))
  generalize (if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then
      flushDeferred env st else nextPage env (flushDeferred env st)) = s1 at h1
  exact Rel.ite h1 (Rel.nl h1 (Rel.blankP env s1))

theorem rel_breakPage (st : St) : Rel st (breakPage env st) [] := by
  simp only [breakPage]
  exact Rel.ite (Rel.blankP env st) (Rel.ite (Rel.refl st) (rel_nextPage env hs st))

theorem rel_applyBreakKind (st : St) (k : BreakKind) : Rel st (applyBreakKind env st k) [] := by
  cases k
  · exact rel_breakPage env hs st
  · exact Rel.ite (rel_nextColumn env hs st) (rel_breakPage env hs st)
  · exact rel_parityStart env hs odd st
  · exact rel_parityStart env hs even st

theorem rel_startBefore (st : St) (sec : Option Nat) (k : BreakKind) : Rel st (startBefore env st sec k) [] := by
  have h1 : Rel st (match k with
      | .column => if isEmpty st then st else nextColumn env st
      | .page =>
        if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
        else nextPage env (flushDeferred env st)
      | .recto => parityStart env odd st
      | .verso => parityStart env even st) [] := by
    cases k
    · exact Rel.ite (rel_flushDeferred env hs st) (Rel.nl (rel_flushDeferred env hs st) (rel_nextPage env hs _))
    · exact Rel.ite (Rel.refl st) (rel_nextColumn env hs st)
    · exact rel_parityStart env hs odd st
    · exact rel_parityStart env hs even st
  simp only [startBefore]
  split
  · exact Rel.fr h1
  · exact h1

theorem rel_applyBreaks (st : St) : Rel st (applyBreaks env st) [] := by
  simp only [applyBreaks]
  suffices ∀ (ks : List Pending) (s : St), Rel s (ks.foldl (applyPending env) s) [] from
    Rel.fl (this st.breaks _)
  intro ks
  induction ks with
  | nil => intro s; exact Rel.refl s
  | cons k ks ih =>
    intro s; simp only [List.foldl]
    refine Rel.nl ?_ (ih _)
    cases k with
    | brk k => exact rel_applyBreakKind env hs s k
    | start sec k => exact rel_startBefore env hs s sec k

theorem rel_applyNeed (st : St) : Rel st (applyNeed env st) [] := by
  unfold applyNeed
  split
  · exact Rel.refl st
  · split
    · rename_i _ n _ _
      have a : Rel st (addUnmet (.needLines n) { st with need := none }) [] :=
        Rel.fl (Rel.addU _ _)
      exact Rel.ite a (Rel.nl a (rel_nextColumn env hs _))
    · exact Rel.fl (rel_keep env hs _ _)

theorem rel_needBeforeSpace (st : St) : Rel st (needBeforeSpace env st) [] := by
  unfold needBeforeSpace
  split
  · exact Rel.refl st
  · split
    · exact Rel.refl st
    · split
      · exact Rel.fl (rel_applyNeed env hs _)
      · dsimp only
        exact Rel.fr (Rel.fl (rel_applyNeed env hs { st with needAt := none }))

theorem rel_placeSpaceFlow (st : St) (n : Nat) : Rel st (placeSpaceFlow env st n) [] := by
  unfold placeSpaceFlow; split
  · exact Rel.refl st
  · exact Rel.frame rfl rfl rfl rfl

theorem rel_placeSpace (st : St) (n : Nat) : Rel st (placeSpace env st n) [] :=
  Rel.fr (rel_placeSpaceFlow env st n)

theorem rel_placeSpaces (ns : List Nat) (st : St) : Rel st (ns.foldl (placeSpace env) st) [] := by
  induction ns generalizing st with
  | nil => exact Rel.refl st
  | cons n ns ih => simp only [List.foldl]; exact Rel.nl (rel_placeSpace env st n) (ih _)

theorem rel_needBeforeSpaces (st : St) : Rel st (needBeforeSpaces env st) [] := by
  unfold needBeforeSpaces
  simp only
  have a := Rel.nl (Rel.frame rfl rfl rfl rfl : Rel st { st with used := st.used - (st.spaces.map (·.2)).foldr (· + ·) 0 } [])
    (rel_needBeforeSpace env hs _)
  split
  · exact Rel.fr a
  · exact Rel.nr a (rel_placeSpaces env _ _)

theorem rel_needAfterSpaces (st : St) : Rel st (needAfterSpaces env st) [] := by
  unfold needAfterSpaces; split
  · exact Rel.refl st
  · exact rel_needBeforeSpaces env hs st

theorem rel_needMore (n : Nat) (st : St) : Rel st (needMore env n st) [] := by
  unfold needMore
  split
  · split
    · exact Rel.refl st
    · exact Rel.fl (rel_needAfterSpaces env hs _)
  · exact Rel.fl (rel_needAfterSpaces env hs _)

theorem rel_needBefore (st : St) (flows : List Flow) : Rel st (needBefore env st flows) [] := by
  unfold needBefore
  split
  · split
    · exact Rel.fl (rel_keep env hs _ _)
    · exact Rel.fl (rel_applyNeed env hs _)
  · exact Rel.fl (rel_applyNeed env hs _)

theorem rel_placeBlank (st : St) (f : Flow) (rest : List Flow) : Rel st (placeBlank env st f rest) [] := by
  unfold placeBlank
  split
  · exact Rel.refl st
  · simp only
    have h1 : Rel st (if startsRecto f = true then parityStart env odd st else st) [] :=
      Rel.ite (rel_parityStart env hs odd st) (Rel.refl st)
    generalize (if startsRecto f = true then parityStart env odd st else st) = s1 at h1
    exact Rel.ite (Rel.nl (Rel.nl h1 (rel_keep env hs s1 _)) (Rel.fl (Rel.dropBlanks _ _)))
      (Rel.fr (Rel.nl h1 (rel_keep env hs s1 _)))

end

/-! ## Lines, stanzas, code and tables -/

theorem bind_take_drop (k : Nat) (ls : List Line) :
    (ls.take k).bind (·.notes) ++ (ls.drop k).bind (·.notes) = ls.bind (·.notes) := by
  rw [← List.append_bind, List.take_append_drop]

theorem Rel.addWs (ws : List (Unmet × Nat × Nat × Nat × (Nat × Bool))) (st : St) :
    Rel st (ws.foldl (fun s w => addUnmet w.1 s) st) [] := by
  induction ws generalizing st with
  | nil => exact Rel.refl st
  | cons w ws ih => simp only [List.foldl]; exact Rel.nl (Rel.addU _ st) (ih _)

section
variable (env : Env) (hs : 0 ≤ env.separator)

theorem rel_putLines (ls : List Line) (st : St) : Rel st (ls.foldl (putLine env) st) (ls.bind (·.notes)) := by
  induction ls generalizing st with
  | nil => exact Rel.refl st
  | cons l ls ih => simp only [List.foldl]; exact Rel.tr (rel_putLine env st l) (ih _) rfl

theorem rel_placeLinesGo (pid : Nat) (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) :
    Rel st (placeLinesGo env pid kp st isStart ls) (ls.bind (·.notes)) := by
  match ls with
  | [] => simp only [placeLinesGo]; exact Rel.refl st
  | l :: ls' =>
    by_cases h1 : st.adjust < 0 ∧ isEmpty st = true ∧ env.roomForLine st (l :: ls') = false
    · unfold placeLinesGo; rw [dif_pos h1]
      exact Rel.nl (rel_nextColumn env hs st) (rel_placeLinesGo pid kp (nextColumn env st) isStart (l :: ls'))
    · by_cases h2 : kp.all = true ∧ isStart = true ∧ env.fitting st (l :: ls') < (l :: ls').length
      · by_cases h3 : isEmpty st = true ∨ st.headingOnly = true
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_pos h3]
          exact Rel.nl (Rel.addU _ st)
            (rel_placeLinesGo pid { kp with all := false } (addUnmet (.splitKept pid) st) isStart (l :: ls'))
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_neg h3]
          exact Rel.nl (rel_nextColumn env hs st) (rel_placeLinesGo pid kp (nextColumn env st) isStart (l :: ls'))
      · by_cases h4 : (l :: ls').length ≤ (lineCount env kp st isStart (l :: ls')).1
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_pos h4]; exact rel_putLines env _ st
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_neg h4]
          exact Rel.tr (Rel.nr (rel_putLines env _ st) (Rel.addUs _ _))
            (Rel.nl (rel_nextColumn env hs _)
              (rel_placeLinesGo pid kp _ _ ((l :: ls').drop (lineCount env kp st isStart (l :: ls')).1)))
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

theorem rel_placeLines (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) :
    Rel st (placeLines env kp st isStart ls) (ls.bind (·.notes)) := by
  cases ls with
  | nil => simp only [placeLines]; exact Rel.refl st
  | cons l ls => exact rel_placeLinesGo env hs _ _ _ _ _

theorem rel_putVerses (st : St) (vs : List (List Line)) :
    Rel st (putVerses env st vs) (vs.join.bind (·.notes)) := rel_putLines env vs.join st

theorem join_take_drop (k : Nat) (vs : List (List Line)) :
    (vs.take k).join.bind (·.notes) ++ (vs.drop k).join.bind (·.notes) = vs.join.bind (·.notes) := by
  rw [← List.append_bind, ← join_append', List.take_append_drop]

theorem rel_placeStanzaGo (pid : Nat) (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) :
    Rel st (placeStanzaGo env pid kp st isStart vs) (vs.join.bind (·.notes)) := by
  match vs with
  | [] => simp only [placeStanzaGo]; exact Rel.refl st
  | v :: more =>
    unfold placeStanzaGo
    simp only
    split
    · split
      · exact Rel.nl (Rel.addU _ st) (rel_placeStanzaGo pid { kp with all := false } _ isStart (v :: more))
      · exact Rel.nl (rel_nextColumn env hs st) (rel_placeStanzaGo pid kp _ isStart (v :: more))
    · split
      · exact rel_putVerses env st _
      · split
        · exact Rel.tr (rel_putVerses env st _) (Rel.nl (rel_nextColumn env hs _) (rel_placeStanzaGo pid kp _ false _))
            (join_take_drop _ _)
        · split
          · split
            · exact Rel.tr (Rel.nr (rel_placeLines env hs _ st isStart v) (Rel.addUs _ _))
                (rel_placeStanzaGo pid kp _ false more) (by simp [List.append_bind])
            · exact Rel.tr (Rel.nr (rel_putVerses env st _) (Rel.addUs _ _))
                (Rel.nl (rel_nextColumn env hs _) (rel_placeStanzaGo pid kp _ false _)) (join_take_drop _ _)
          · exact Rel.nl (rel_nextColumn env hs st) (rel_placeStanzaGo pid kp _ isStart (v :: more))
termination_by (vs.length, allRank kp, rank env st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; apply Prod.Lex.left; simp_all [allRank]; done)
    | (apply linesLt_rank; apply I4_nextColumn_rank; left; cases e : isEmpty st
       · rfl
       · simp [emptyish, e] at *)

theorem rel_placeStanza (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) :
    Rel st (placeStanza env kp st isStart vs) (vs.join.bind (·.notes)) := by
  unfold placeStanza; split <;> exact rel_placeStanzaGo env hs _ _ _ _ _

theorem rel_placeCode (g cap0 first : Nat) (cont : Bool) (st : St) (isFirst : Bool) (ls : List Line) :
    Rel st (placeCode env g cap0 first cont st isFirst ls) [] := by
  match ls with
  | [] => unfold placeCode; exact Rel.refl st
  | l0 :: ls' =>
    by_cases h : codeCount env g cap0 first cont st isFirst (l0 :: ls').length = 0
    · unfold placeCode; rw [dif_pos h]
      exact Rel.nl (rel_nextColumn env hs st) (rel_placeCode g cap0 first cont (nextColumn env st) isFirst (l0 :: ls'))
    · unfold placeCode; rw [dif_neg h]
      simp only
      split
      · exact Rel.frame rfl rfl rfl rfl
      · exact Rel.fl (Rel.nl (rel_nextColumn env hs _)
          (rel_placeCode g cap0 first cont _ false ((l0 :: ls').drop (codeCount env g cap0 first cont st isFirst (l0 :: ls').length))))
termination_by (ls.length, rank env st)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.right _ (I4_nextColumn_rank env st
      (Or.inl (codeCount_zero env g cap0 first cont st isFirst _ (by simp) h)))
  · apply Prod.Lex.left
    simp only [List.length, Nat.succ_eq_add_one] at *
    omega

theorem rel_putRepeateds (ls : List Line) (st : St) : Rel st (ls.foldl putRepeated st) [] := by
  induction ls generalizing st with
  | nil => exact Rel.refl st
  | cons l ls ih => simp only [List.foldl]; exact Rel.fl (ih _)

theorem rel_tableRowsGo (h capt : List Line) (below : Bool) (st : St) (first : Int) (rows : List (List Line)) :
    Rel st (tableRowsGo env h capt below st first rows) (rows.join.bind (·.notes)) := by
  match rows with
  | [] => unfold tableRowsGo; exact Rel.refl st
  | r :: rest =>
    by_cases h1 : (withCaption capt below r rest).length ≤ env.fitting st (withCaption capt below r rest)
        ∨ st.used = first + h.length
    · unfold tableRowsGo; rw [dif_pos h1]
      exact Rel.tr (rel_putLines env r st) (rel_tableRowsGo h capt below _ first rest) (by simp [List.append_bind])
    · unfold tableRowsGo; rw [dif_neg h1]
      simp only
      exact Rel.nl (Rel.nl (Rel.nl (rel_nextColumn env hs st) (rel_keep env hs _ _)) (rel_putRepeateds _ _))
        (rel_tableRowsGo h capt below _ _ (r :: rest))
termination_by (rows.length, if st.used = first + h.length then 0 else 1)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
    have : ¬ st.used = first + h.length := fun e => h1 (Or.inr e)
    simp only [putRepeateds_used, this, ite_true, ite_false]
    decide

theorem rel_placeTable (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    Rel st (placeTable env st h rows capt below) ((tableLines h rows capt below).bind (·.notes)) := by
  cases below
  · simp only [placeTable]
    exact Rel.tr (Rel.tr (rel_putLines env capt st) (rel_putLines env h _) rfl) (rel_tableRowsGo env hs _ _ _ _ _ _)
      (by simp [tableLines, List.append_bind, List.append_assoc])
  · simp only [placeTable]
    exact Rel.tr (Rel.tr (rel_putLines env h st) (rel_tableRowsGo env hs _ _ _ _ _ _) rfl) (rel_putLines env capt _)
      (by simp [tableLines, List.append_bind, List.append_assoc])

theorem rel_nextSpread (t : Nat) (st : St) : Rel st (nextSpread env t st) [] := by
  by_cases h : (nextPage env st).page < t
  · unfold nextSpread; rw [dif_pos h]; exact Rel.nl (rel_nextPage env hs st) (rel_nextSpread t (nextPage env st))
  · unfold nextSpread; rw [dif_neg h]; exact rel_nextPage env hs st
termination_by t - st.page
decreasing_by simp_wf; have := nextPage_page_gt env st; omega

theorem rel_nextUnit (unit : KeepParts) (st : St) : Rel st (nextUnit env unit st) [] := by
  cases unit
  · exact rel_nextColumn env hs st
  · exact rel_nextPage env hs st
  · exact rel_nextSpread env hs _ st

theorem rel_partTrial (runBody runPlain : St → St) (X : List Note)
    (hb : ∀ s, Rel s (runBody s) X) (hp : ∀ s, Rel s (runPlain s) X)
    (unit : KeepParts) (fits : St → Bool) (nested whole : Bool) (st : St) :
    Rel st (partTrial env runBody runPlain unit fits nested whole st) X := by
  simp only [partTrial]
  repeat' split
  all_goals first
    | exact hp _
    | exact Rel.nr (hp _) (rel_flushFigures env hs _)
    | exact Rel.nr (hb _) (rel_flushFigures env hs _)

/-- Every trial of a book part reads the same notes. -/
theorem rel_placeBookPart (runBody runPlain : St → St) (X : List Note)
    (hb : ∀ s, Rel s (runBody s) X) (hp : ∀ s, Rel s (runPlain s) X)
    (initial : St) (unit : KeepParts) (kind : Option Nat) (retained : List Nat) (nested whole : Bool) :
    Rel initial (placeBookPart env runBody runPlain initial unit kind retained nested whole) X := by
  have pt := rel_partTrial env hs runBody runPlain X hb hp unit
  simp only [placeBookPart]
  repeat' split
  all_goals first
    | exact hb _
    | exact pt _ _ _ _
    | exact Rel.nl (rel_nextUnit env hs unit _) (pt _ _ _ _)
    | exact Rel.nr (hb _) (Rel.addU _ _)
    | exact Rel.nr (pt _ _ _ _) (Rel.addU _ _)
    | exact Rel.nr (Rel.nl (rel_nextUnit env hs unit _) (hb _)) (Rel.addU _ _)

theorem rel_acrossGo (h capt : List Line) (below retain fresh retried : Bool) (st : St)
    (gs : List (Bool × List Line)) :
    Rel st (acrossGo env h capt below retain fresh retried st gs) ((gs.bind (·.2)).bind (·.notes)) := by
  match gs with
  | [] => unfold acrossGo; exact Rel.refl st
  | (isHeader, ls) :: remaining =>
    by_cases hr : fresh = true ∧ retainsTail env capt below retain isHeader remaining = true
    · unfold acrossGo; rw [dif_pos hr]
      apply rel_placeBookPart env hs
      all_goals intro s
      all_goals refine Rel.nl ?_ (rel_acrossGo h capt below false true false _ ((isHeader, ls) :: remaining))
      all_goals split
      all_goals first | exact Rel.refl _ | exact rel_putRepeateds _ _
    · by_cases h1 : ls.length ≤ env.fitting st ls ∨ isEmpty st = true
      · unfold acrossGo; rw [dif_neg hr, dif_pos h1]
        exact Rel.tr (rel_putLines env ls st) (rel_acrossGo h capt below retain true false _ remaining)
          (by simp [List.append_bind])
      · unfold acrossGo; rw [dif_neg hr, dif_neg h1]
        refine Rel.nl ?_ (rel_acrossGo h capt below retain false _ _ ((isHeader, ls) :: remaining))
        split
        · exact Rel.nl (rel_nextColumn env hs st) (rel_putRepeateds _ _)
        · exact rel_nextColumn env hs st
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

theorem rel_placeTableAcross (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    Rel st (placeTableAcross env st h rows capt below) ((tableLines h rows capt below).bind (·.notes)) := by
  simp only [placeTableAcross]
  rw [← tableGroups_lines]
  exact rel_acrossGo env hs _ _ _ _ _ _ _ _

theorem rel_startSet (st : St) (n : Nat) (first : Int) : Rel st (startSet env st n first) [] := by
  obtain ⟨c1, c2, c3⟩ := closePage_facts env st
  refine Rel.of_R0 (R0.same ?_ (Grows.of_eq ?_ (keeps_startSet env st n first)))
  · simp only [NM, startSet]; rw [c1, c3]; simp [ex_append, List.append_assoc]
  · simp only [allUnmet, startSet]; exact c2

end

/-! ## Controls, rules and the flows -/

theorem rel_checkNoBreak (st : St) : Rel st (checkNoBreak st) [] := by
  unfold checkNoBreak
  split
  · exact Rel.refl st
  · simp only
    exact Rel.fr (Rel.ite (Rel.refl st) (Rel.addWs _ st))

theorem rel_waitFor (u : Unmet) (k : Nat × Bool) (st : St) : Rel st (waitFor u k st) [] := by
  unfold waitFor; split
  · exact Rel.frame rfl rfl rfl rfl
  · exact Rel.frame rfl rfl rfl rfl

section
variable (env : Env) (hs : 0 ≤ env.separator)

theorem rel_placeKept {α : Type} (kp : Keep) (placeIn : St → Bool → List α → St)
    (T : List α → List Note) (hT : ∀ a b, T (a ++ b) = T a ++ T b)
    (hp : ∀ s b xs, Rel s (placeIn s b xs) (T xs))
    (st : St) (isStart : Bool) (ls : List α) (n : Need) :
    Rel st (placeKept env kp placeIn st isStart ls n) (T ls) := by
  have tl : T (ls.take (ls.length - keptCut kp ls.length)) ++ T (ls.drop (ls.length - keptCut kp ls.length))
      = T ls := by rw [← hT, List.take_append_drop]
  simp only [placeKept]
  apply Rel.ite
  · exact hp _ _ _
  · apply Rel.ite
    · exact Rel.tr (hp _ _ _) (hp _ _ _) tl
    · apply Rel.ite
      · exact hp _ _ _
      · exact Rel.tr (hp _ _ _) (Rel.nl (rel_nextColumn env hs _) (hp _ _ _)) tl

theorem rel_putRuledLines (k2 : Nat) (ls : List Line) (st : St) :
    Rel st (putRuledLines env k2 st ls) (ls.bind (·.notes)) := by
  induction ls generalizing st with
  | nil => exact Rel.refl st
  | cons l ls ih =>
    simp only [putRuledLines]
    exact Rel.tr (rel_putLineKeeping env _ st l) (ih _) rfl

/-- The notes of the lines of a block with rules. -/
def ruledNotes : RuledBody → List Note
  | .lines _ ls => ls.bind (·.notes)
  | .heading _ _ ls => ls.bind (·.notes)

theorem rel_commitRuled (st : St) (body : RuledBody) (p : Plan) :
    Rel st (commitRuled env st body p) (ruledNotes body) := by
  cases body with
  | lines kp ls =>
    simp only [commitRuled]
    exact Rel.fr (Rel.fl (rel_putRuledLines env p.after ls { st with used := st.used + p.before, join := none }))
  | heading r n ls =>
    simp only [commitRuled]
    exact Rel.fr (Rel.fr (Rel.fl (rel_putBlock env { st with used := st.used + p.before, join := none } n ls)))

theorem rel_splitRuled (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow) :
    Rel st (splitRuled env st i b a body rest) (ruledNotes body) := by
  have h0 : Rel st (if isEmpty st = true then st else nextColumn env st) [] :=
    Rel.ite (Rel.refl st) (rel_nextColumn env hs st)
  cases body with
  | lines kp ls => simp only [splitRuled]; exact Rel.nl h0 (rel_placeLines env hs _ _ _ _)
  | heading r n ls =>
    simp only [splitRuled]
    generalize (if isEmpty st = true then st else nextColumn env st) = s at h0
    split
    · exact Rel.nl h0 (rel_commitRuled env _ _ _)
    · split
      · exact Rel.nl h0 (rel_commitRuled env _ _ _)
      · exact Rel.nl h0 (rel_putBlock env _ n ls)

theorem rel_flushJoin (st : St) : Rel st (flushJoin env st) [] := by
  unfold flushJoin; split
  · exact Rel.refl st
  · exact Rel.frame rfl rfl rfl rfl

theorem rel_placeRuledFresh (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow) :
    Rel st (placeRuledFresh env st i b a body rest) (ruledNotes body) := by
  have h1 : Rel st (if body.recto = true then parityStart env odd st else st) [] :=
    Rel.ite (rel_parityStart env hs _ _) (Rel.refl st)
  simp only [placeRuledFresh]
  generalize (if body.recto = true then parityStart env odd st else st) = s1 at h1
  have h2 : ∀ s2 : St, Rel st s2 [] →
      Rel st (match settleRuled env s2 i b a body rest none with
        | some placed => placed
        | none =>
          if isEmpty s2 = true then splitRuled env s2 i b a body rest
          else
            match settleRuled env (nextColumn env s2) i b a body rest none with
            | some placed => placed
            | none => splitRuled env (nextColumn env s2) i b a body rest) (ruledNotes body) := by
    intro s2 e
    apply settle_or (fun r => Rel st r (ruledNotes body))
    · intro _ _ _; exact Rel.nl e (rel_commitRuled env _ _ _)
    · split
      · exact Rel.nl e (rel_splitRuled env hs _ _ _ _ _ _)
      · apply settle_or (fun r => Rel st r (ruledNotes body))
        · intro _ _ _; exact Rel.nl e (Rel.nl (rel_nextColumn env hs _) (rel_commitRuled env _ _ _))
        · exact Rel.nl e (Rel.nl (rel_nextColumn env hs _) (rel_splitRuled env hs _ _ _ _ _ _))
  apply h2
  cases body with
  | heading r n ls =>
    cases r <;> simp only [ruledKeep]
    · exact Rel.nl h1 (rel_keep env hs _ _)
    · exact h1
  | lines kp ls =>
    simp only [ruledKeep]
    split
    · split
      · exact Rel.nl h1 (rel_keep env hs _ _)
      · exact h1
    · exact h1

theorem rel_placeRuled (st : St) (i : Nat) (b a j : Bool) (body : RuledBody) (rest : List Flow) :
    Rel st (placeRuled env st i b a j body rest) (ruledNotes body) := by
  unfold placeRuled
  split
  · apply joined_or (fun r => Rel st r (ruledNotes body))
    · intro _ _ _; exact rel_commitRuled env _ _ _
    · unfold unjoined; split
      · exact Rel.nl (rel_flushJoin env st) (Rel.nl (rel_nextColumn env hs _) (rel_placeRuledFresh env hs _ _ _ _ _ _))
      · exact Rel.nl (rel_flushJoin env st) (rel_placeRuledFresh env hs _ _ _ _ _ _)
  · exact rel_placeRuledFresh env hs _ _ _ _ _ _

end

theorem flowNotes_ruled (i : Nat) (b a j : Bool) (body : RuledBody) :
    flowNotes (.ruled i b a j body) = ruledNotes body := by
  cases body <;> simp [flowNotes, ruledNotes]

mutual
theorem rel_place (env : Env) (hs : 0 ≤ env.separator) (st : St) (f : Flow) (rest : List Flow) :
    Rel st (place env st f rest) (flowNotes f) := by
  cases f with
  | paragraph kp ls => simp only [place, flowNotes]; exact rel_placeLines env hs _ _ _ _
  | stanza kp vs => simp only [place, flowNotes]; exact rel_placeStanza env hs _ _ _ _
  | ruled i b a j body => simp only [place]; rw [flowNotes_ruled]; exact rel_placeRuled env hs _ _ _ _ _ _ _
  | wrapped i n beside =>
    simp only [place, flowNotes]
    have h : Rel st (placeLines env defaultKeep (putSlot (keep env (flushFigures env st)
        (fun s => needIn env s ⟨max n beside.length, noteLinesOf beside⟩ ⟨0, 0⟩)) 0
        (.wrapped i)) false beside) (beside.bind (·.notes)) :=
      Rel.nl (Rel.nl (rel_flushFigures env hs st) (rel_keep env hs _ _)) (Rel.fl (rel_placeLines env hs _ _ _ _))
    exact Rel.ite (Rel.fr h) h
  | continued kp ls => simp only [place, flowNotes]; exact rel_placeLines env hs _ _ _ _
  | heading recto n ls =>
    simp only [place, flowNotes]
    have h1 : Rel st (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) [] :=
      Rel.ite (rel_parityStart env hs _ _) (rel_keep env hs _ _)
    generalize (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) = s1 at h1
    exact Rel.nl (Rel.ite h1 (Rel.nl h1 (rel_nextColumn env hs _))) (rel_putBlock env _ n ls)
  | figure i n =>
    simp only [place, flowNotes]
    exact Rel.ite (Rel.frame rfl rfl rfl rfl) (Rel.ite (Rel.frame rfl rfl rfl rfl) (Rel.frame rfl rfl rfl rfl))
  | pageFigure i =>
    simp only [place, flowNotes]
    exact Rel.ite (Rel.fl (Rel.pageF env _ i)) (Rel.frame rfl rfl rfl rfl)
  | brk k => simp only [place, flowNotes]; exact Rel.frame rfl rfl rfl rfl
  | sectionStart sec k => simp only [place, flowNotes]; exact Rel.frame rfl rfl rfl rfl
  | space n => simp only [place, flowNotes]; exact rel_placeSpaceFlow env _ _
  | needLines n => simp only [place, flowNotes]; exact Rel.refl st
  | blank n => simp only [place, flowNotes]; exact Rel.refl st
  | noBreak => simp only [place, flowNotes]; exact Rel.refl st
  | noBreakLines n => simp only [place, flowNotes]; exact Rel.refl st
  | keepNext n => simp only [place, flowNotes]; exact Rel.refl st
  | switchColumns n =>
    simp only [place, flowNotes]
    exact Rel.nl (rel_flushDeferred env hs st) (Rel.ite (rel_startSet env _ _ _) (Rel.fr (rel_nextPage env hs (flushDeferred env st))))
  | restoreColumns =>
    simp only [place, flowNotes]
    exact Rel.ite (Rel.frame rfl rfl rfl rfl) (Rel.fr (rel_nextPage env hs st))
  | adjustLines k => simp only [place, flowNotes]; exact Rel.refl st
  | bookPart u k r body => simp only [place, flowNotes]; exact rel_runFlows env hs st body rest
  | boxed i kb ka body =>
    simp only [place, flowNotes]
    have h : Rel st (runFlows env (openBox { keep env st (fun s => (kb : Int) + ka + needIn env s noNeed (env.nextNeed body))
        with box := some ⟨i, kb, ka, 0, false⟩ }) body rest) (sourceNotes body) :=
      Rel.nl (Rel.nl (rel_keep env hs st _) (Rel.fl (Rel.oBox _))) (rel_runFlows env hs _ body rest)
    exact Rel.nr (Rel.fr h) (rel_drainPendingNotes env _)
  | code g c first cont ls => simp only [place, flowNotes]; exact rel_placeCode env hs _ _ _ _ _ _ _
  | defTerm ls =>
    simp only [place, flowNotes]
    split
    · exact Rel.nl (rel_keep env hs _ _) (rel_placeLines env hs _ _ _ _)
    · exact rel_placeLines env hs _ _ _ _
  | table sp0 h rows capt below =>
    simp only [place, flowNotes]
    split
    · refine Rel.nl ?_ (rel_placeTable env hs _ _ _ _ _)
      apply Rel.ite
      · exact Rel.frame rfl rfl rfl rfl
      · exact Rel.nl (rel_nextColumn env hs _) (rel_keep env hs _ _)
    · refine Rel.nl ?_ (rel_placeTableAcross env hs _ _ _ _ _)
      apply Rel.ite
      · exact Rel.frame rfl rfl rfl rfl
      · exact rel_nextColumn env hs _
termination_by (flowWeight f, 0)
decreasing_by all_goals simp_wf; (try subst_vars); apply Prod.Lex.left; simp only [flowWeight]; omega

theorem rel_placeFlow (env : Env) (hs : 0 ≤ env.separator) (st : St) (f : Flow) (rest : List Flow) :
    Rel st (placeFlow env st f rest) (flowNotes f) := by
  have pl : ∀ kp s b xs, Rel s (placeLines env kp s b xs) (xs.bind (·.notes)) :=
    fun kp s b xs => rel_placeLines env hs kp s b xs
  unfold placeFlow
  split
  · simp only [flowNotes]; exact rel_placeKept env hs _ _ _ (fun a b => List.append_bind a b _) (pl _) st true _ _
  · simp only [flowNotes]
    exact rel_placeKept env hs _ _ (fun vs => vs.join.bind (·.notes))
      (fun a b => by simp only [join_append', List.append_bind]) (fun s b xs => rel_placeStanza env hs _ s b xs) st true _ _
  · simp only [flowNotes]; exact rel_placeKept env hs _ _ _ (fun a b => List.append_bind a b _) (pl _) st false _ _
  · simp only [flowNotes]
    exact Rel.nl (Rel.ite (Rel.refl st) (rel_keep env hs _ _))
      (rel_placeKept env hs _ _ _ (fun a b => List.append_bind a b _) (pl _) _ true _ _)
  · exact rel_place env hs _ _ _
termination_by (flowWeight f, 1)
decreasing_by all_goals simp_wf; apply Prod.Lex.right; decide

theorem rel_step (env : Env) (hs : 0 ≤ env.separator) (st : St) (f : Flow) (rest : List Flow) :
    Rel st (step env st f rest) (flowNotes f) := by
  have general : ∀ (a : Bool) (b : List (Nat × Int)), Rel st ({ (if waitsBehind (applyBreaks env st) f
      then checkNoBreak (place env (applyBreaks env st) f rest)
      else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest))
      with seen := true, lastDeferred := a, spaces := b } : St) (flowNotes f) := by
    intro _ _
    have h : Rel st (if waitsBehind (applyBreaks env st) f
      then checkNoBreak (place env (applyBreaks env st) f rest)
      else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest))
        (flowNotes f) := by
      apply Rel.ite
      · exact Rel.nl (rel_applyBreaks env hs st) (Rel.nr (rel_place env hs _ _ _) (rel_checkNoBreak _))
      · exact Rel.nl (Rel.nl (rel_applyBreaks env hs st) (Rel.nl (rel_needBefore env hs _ _) (rel_placeBlank env hs _ _ _)))
          (Rel.nr (rel_placeFlow env hs _ _ _) (rel_checkNoBreak _))
    exact Rel.fr h
  have ctl : ∀ (u : Unmet) (k : Nat × Bool), Rel st (if st.seen = false ∨ st.lastDeferred = true then addUnmet u st
      else waitFor u k st) [] := fun u k => Rel.ite (Rel.addU u st) (rel_waitFor u k st)
  cases f with
  | needLines n => simp only [step, flowNotes]; exact rel_needMore env hs _ _
  | bookPart u k r body =>
    simp only [step, flowNotes]
    refine Rel.nl (b := if r = [] then st else applyBreaks env st) (Rel.ite (Rel.refl st) (rel_applyBreaks env hs st)) ?_
    apply rel_placeBookPart env hs
    · intro s; exact rel_runFlows { env with keepParts := u, inBookPart := true } hs s body rest
    · intro s; have := rel_runFlows { env with keepParts := u, inBookPart := true } hs s (flattenParts body) rest
      rw [sourceNotes_flatten] at this; exact this
  | adjustLines k =>
    simp only [step, flowNotes]
    refine Rel.nl (rel_applyBreaks env hs st) (Rel.nr ?_ (rel_drainPendingNotes env _))
    simp only [adjustLines]
    split
    · exact Rel.fl (Rel.addU _ _)
    · exact Rel.frame rfl rfl rfl rfl
  | noBreak => simp only [step, flowNotes]; exact ctl _ _
  | noBreakLines n =>
    cases n with
    | zero => simp only [step, flowNotes]; exact Rel.refl st
    | succ m => simp only [step, flowNotes]; exact ctl _ _
  | keepNext n => simp only [step, flowNotes]; exact ctl _ _
  | blank n =>
    simp only [step, flowNotes]
    exact Rel.ite (Rel.refl st) (Rel.frame rfl rfl rfl rfl)
  | brk k => simp only [step]; exact rel_place env hs st (.brk k) rest
  | sectionStart sec k => simp only [step]; exact rel_place env hs st (.sectionStart sec k) rest
  | space n =>
    simp only [step, flowNotes]
    exact Rel.nl (Rel.nl (rel_applyBreaks env hs st) (rel_needBeforeSpaces env hs _)) (rel_placeSpace env _ _)
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

theorem rel_runFlows (env : Env) (hs : 0 ≤ env.separator) (st : St) (fs : List Flow) (rest : List Flow) :
    Rel st (runFlows env st fs rest) (sourceNotes fs) := by
  match fs with
  | [] => unfold runFlows; simp only [sourceNotes]; exact Rel.refl st
  | g :: more =>
    unfold runFlows
    exact Rel.tr (rel_step env hs st g (more ++ rest)) (rel_runFlows env hs _ more rest) (by simp [sourceNotes])
termination_by (flowsWeight fs, 3)
decreasing_by
  all_goals simp_wf
  all_goals apply Prod.Lex.left; simp only [flowsWeight]; omega
end

theorem rel_placeAll (env : Env) (hs : 0 ≤ env.separator) (flows : List Flow) (st : St) :
    Rel st (placeAll env st flows) (sourceNotes flows) ∧ (placeAll env st flows).pending = [] := by
  induction flows generalizing st with
  | nil =>
    simp only [placeAll, sourceNotes]
    have a := Rel.addWs st.noBreak st
    generalize st.noBreak.foldl (fun s w => addUnmet w.1 s) st = s1 at a
    refine ⟨?_, ?_⟩
    · split
      · exact Rel.nl (Rel.fr a) (rel_flushDeferred env hs _)
      · split
        · exact Rel.nl (Rel.nl (Rel.fr a) (Rel.dropBlanks _ _)) (rel_flushDeferred env hs _)
        · exact Rel.nl (Rel.nl (Rel.nl (Rel.fr a) (rel_nextColumn env hs _)) (Rel.dropBlanks _ _))
            (rel_flushDeferred env hs _)
    · repeat' split
      all_goals exact flushDeferred_pending env _
  | cons f rest ih =>
    simp only [placeAll]
    obtain ⟨a, b⟩ := ih (step env st f rest)
    exact ⟨Rel.tr (rel_step env hs st f rest) a (by simp [sourceNotes]), b⟩

/-! ## The notes of the pages (invariant 5) -/

theorem paginate_facts (env : Env) (hs : 0 ≤ env.separator) (flows : List Flow) :
    ∃ st, Rel (initialState env) st (sourceNotes flows) ∧
      ex (pagesNotes (paginate env flows).done) = NM st ∧ allUnmet (paginate env flows) = allUnmet st := by
  obtain ⟨r, p⟩ := rel_placeAll env hs flows (initialState env)
  obtain ⟨c1, c2, _⟩ := closePage_facts env (placeAll env (initialState env) flows)
  refine ⟨_, r, ?_, ?_⟩
  · simp only [paginate]; rw [c1, NM, p, ex_append]; simp
  · simp only [paginate, allUnmet] at c2 ⊢; exact c2

/-- What `Rel.trans` reads off its first step: the notes read after it
    are still new. -/
theorem Rel.fresh_after {a b : St} {X1 X2 : List Note} (h1 : Rel a b X1) (f : Fresh a (X1 ++ X2)) :
    Fresh b X2 := by
  obtain ⟨d, s⟩ := f
  obtain ⟨s1, s2, d12⟩ := Sep.append X1 X2 s
  rw [exN_append, Disj.append_right] at d
  have r1 := h1 ⟨d.1, s1⟩
  refine ⟨fun i => ?_, s2⟩
  rcases d.2 i with e | e
  · rcases d12 i with e' | e'
    · exact Or.inl (r1.2.1 i (by rw [filt_append, e, e']; rfl))
    · exact Or.inr e'
  · exact Or.inr e

/-- The later steps keep the pages and columns closed, and the slots of
    the current column, as they are (`Keeps`), when the notes read are new. -/
theorem keeps_placeAll (env : Env) (hs : 0 ≤ env.separator) (flows : List Flow) (st : St)
    (hf : Fresh st (sourceNotes flows)) : Keeps st (placeAll env st flows) :=
  ((rel_placeAll env hs flows st).1 hf).1.2

/-- Root ADR 0352 invariant 5 for the footnotes of the grid mode: the
    pages of the pagination hold no line of a note not written, and, note
    by note, every line of the note's body written, each once, from the
    first to the last, unless the pagination reports the note as
    unplaceable.  It assumes that the footnote separator takes 0 lines or
    more (golem-layout clamps it to 1 line or more) and that no two notes
    of the manuscript share an id (`Sep`, implied by `Distinct`). -/
theorem I5_paginate_notes (env : Env) (hs : 0 ≤ env.separator) (flows : List Flow)
    (hn : Sep (sourceNotes flows)) :
    (∀ i, filt i (exN (sourceNotes flows)) = [] → filt i (ex (pagesNotes (paginate env flows).done)) = []) ∧
    (∀ i, (¬ ∃ c, Unmet.unplaceableFootnote i c ∈ allUnmet (paginate env flows)) →
      filt i (ex (pagesNotes (paginate env flows).done)) = filt i (exN (sourceNotes flows))) := by
  obtain ⟨st, r, e1, e2⟩ := paginate_facts env hs flows
  have R := r ⟨fun i => Or.inl rfl, hn⟩
  have n0 : NM (initialState env) = [] := rfl
  obtain ⟨_, s, eq⟩ := R
  rw [n0, List.nil_append] at s eq
  refine ⟨fun i h => ?_, fun i nd => ?_⟩
  · rw [e1]; exact s i h
  · rw [e1]; exact eq i (by rw [Dropped, ← e2]; exact nd)

/-- No two ids of the list are the same. -/
def Distinct : List Nat → Prop
  | [] => True
  | i :: is => i ∉ is ∧ Distinct is

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

/-- Root ADR 0352 invariant 5 for each footnote of the grid mode, when the
    note ids of the manuscript are distinct: the lines of note `n` on the
    pages are its lines 0, 1, ..., `n.lines - 1`, each once and in this
    order, unless the pagination reports the note as unplaceable. -/
theorem I5_paginate_each_note (env : Env) (hs : 0 ≤ env.separator) (flows : List Flow)
    (hd : Distinct ((sourceNotes flows).map (·.id))) (n : Note) (m : n ∈ sourceNotes flows)
    (nd : ¬ ∃ c, Unmet.unplaceableFootnote n.id c ∈ allUnmet (paginate env flows)) :
    filt n.id (ex (pagesNotes (paginate env flows).done)) = seg n.id 0 n.lines := by
  rw [(I5_paginate_notes env hs flows (sep_of_distinct _ hd)).2 n.id nd, filt_exN_mem _ hd n m]; rfl

end Notes
end WholePagination
