/-
Root ADR 0352: the whole pagination of the grid mode as a state machine.

This file models `placeAll` and `step` of
modules/golem-layout/src/Golem/Layout/Paginate.hs and the state
operations of Paginate/State.hs, one Lean definition per Haskell
function, for the flows listed in `Flow` below.  README.md lists the
correspondence with file:line.  Every definition is total: the loops
of the Haskell code (`keep`, `flushDeferred`, `flushFigures` and the
column loop of `placeLines`) are defined by well-founded recursion on
the rank below, so Lean checks that they terminate on every input.

The values that the Haskell code computes from the flows ahead
(`nextNeed`) and from the lines and their notes (`fitting`,
`roomForLine`) are parameters of `Env`: the theorems hold for every
choice of them.
-/
namespace WholePagination

inductive BreakKind where
  | page | column | recto | verso
  deriving DecidableEq, Repr

structure Note where
  id : Nat
  lines : Nat
  deriving DecidableEq, Repr

structure Line where
  id : Nat
  notes : List Note
  deriving DecidableEq, Repr

structure Keep where
  first : Nat
  last : Nat
  all : Bool
  deriving DecidableEq, Repr

def defaultKeep : Keep := ⟨2, 2, false⟩

/-- The flows of the grid mode modelled here (Paginate/Types.hs `FlowAt`). -/
inductive Flow where
  | paragraph (kp : Keep) (lines : List Line)
  | continued (kp : Keep) (lines : List Line)
  | heading (recto : Bool) (n : Nat) (lines : List Line)
  | figure (id n : Nat)
  | pageFigure (id : Nat)
  | brk (k : BreakKind)
  | space (n : Nat)
  | blank (n : Nat)
  | needLines (n : Nat)
  deriving DecidableEq, Repr

inductive Slot where
  | line (id : Nat)
  | heading (id count : Nat)
  | figure (id : Nat)
  | pageFigure (id : Nat)
  deriving DecidableEq, Repr

/-- The figures waiting (`sDeferred`): only figures and turned figures
    are ever put there, so the catch-all of `placeDeferred` is not
    needed. -/
inductive Deferred where
  | figure (id n : Nat)
  | pageFigure (id : Nat)
  deriving DecidableEq, Repr

inductive Unmet where
  | needLines (n : Nat)
  | droppedBlank
  | tallHeading (id n : Nat) (free : Int)
  | unplaceableFootnote (id : Nat) (cap : Int)
  | splitKept (id : Nat)
  | shortFirst (id want got : Nat)
  | shortLast (id want got : Nat)
  deriving DecidableEq, Repr

/-- A note part: note id, first line, lines. -/
abbrev NotePart := Nat × Nat × Nat

structure PageOut where
  number : Nat
  column : Nat
  blank : Bool
  slots : List (Int × Slot)
  notes : List NotePart
  unmet : List Unmet

structure St where
  page : Nat
  column : Nat
  firstLine : Int
  used : Int
  noteLines : Int
  slots : List (Int × Slot)
  notes : List NotePart
  done : List PageOut
  deferred : List Deferred
  pending : List NotePart
  breaks : List BreakKind
  reserved : Int
  need : Option Nat
  needAt : Option (Nat × Nat)
  spaces : List (Nat × Int)
  adjust : Int
  unmet : List Unmet
  blank : List Nat
  seen : Bool
  lastDeferred : Bool
  headingOnly : Bool

structure Need where
  grid : Nat
  notes : Nat

/-- `Env` of State.hs with the columns of the set, and the values the
    model leaves open. -/
structure Env where
  capacity : Int
  separator : Int
  columns : Nat
  nextNeed : List Flow → Need
  fitting : St → List Line → Nat
  roomForLine : St → List Line → Bool

def initialState : St :=
  ⟨1, 0, 0, 0, 0, [], [], [], [], [], [], 0, none, none, [], 0, [], [], false, false, false⟩

/-! ## Queries of State.hs -/

def top (st : St) : Int := st.firstLine
def cap (env : Env) (st : St) : Int := env.capacity + st.adjust
def free (env : Env) (st : St) : Int := cap env st - st.used - st.noteLines
def isEmpty (st : St) : Bool := st.notes.isEmpty && st.used == top st
def addUnmet (u : Unmet) (st : St) : St := { st with unmet := st.unmet ++ [u] }

def noteLinesOf (ls : List Line) : Nat :=
  (ls.bind (·.notes)).foldr (fun n a => n.lines + a) 0

def needIn (env : Env) (st : St) (a b : Need) : Int :=
  let notes := a.notes + b.notes
  let sep : Int := if st.noteLines = 0 ∧ 0 < notes then env.separator else 0
  (a.grid : Int) + b.grid + notes + sep

/-! ## Operations of State.hs -/

def blankPage (_env : Env) (st : St) : St :=
  { st with done := ⟨st.page, 0, true, [], [], []⟩ :: st.done, page := st.page + 1 }

def putSlot (st : St) (n : Nat) (s : Slot) : St :=
  { st with slots := st.slots ++ [(st.used, s)], used := st.used + n, headingOnly := false }

/-- `splitNotes` of State.hs. -/
def splitNotes : Int → List Note → List NotePart × List NotePart
  | _, [] => ([], [])
  | r, ⟨i, len⟩ :: rest =>
    if (len : Int) ≤ r then
      let p := splitNotes (r - len) rest
      ((i, 0, len) :: p.1, p.2)
    else if 0 < r then
      ([(i, 0, r.toNat)], (i, r.toNat, len - r.toNat) :: rest.map (fun n => (n.id, 0, n.lines)))
    else
      ([], (i, 0, len) :: rest.map (fun n => (n.id, 0, n.lines)))

def partsLines (ps : List NotePart) : Nat := ps.foldr (fun p a => p.2.2 + a) 0

def putLineKeeping (env : Env) (reserve : Int) (st : St) (l : Line) : St :=
  let noteLines : Nat := (l.notes.map (·.lines)).foldr (· + ·) 0
  let sep : Int := if st.noteLines = 0 ∧ 0 < noteLines then env.separator else 0
  let room := cap env st - st.used - 1 - reserve - st.noteLines - sep
  let sp := splitNotes room l.notes
  { st with
    slots := st.slots ++ [(st.used, .line l.id)]
    used := st.used + 1
    noteLines := st.noteLines + (if sp.1.isEmpty ∧ 0 < reserve then 0 else sep) + partsLines sp.1
    notes := st.notes ++ sp.1
    pending := st.pending ++ sp.2
    headingOnly := false }

def putLine (env : Env) (st : St) (l : Line) : St := putLineKeeping env 0 st l

def putBlock (env : Env) (st : St) (n : Nat) : List Line → St
  | [] => st
  | ls@(l0 :: _) =>
    let tall := if free env st < n then [Unmet.tallHeading l0.id n (free env st)] else []
    let notes := ls.bind (·.notes)
    let noteLines : Nat := (notes.map (·.lines)).foldr (· + ·) 0
    let sep : Int := if st.noteLines = 0 ∧ 0 < noteLines then env.separator else 0
    let room := cap env st - st.used - n - st.noteLines - sep
    let sp := splitNotes room notes
    { st with
      slots := st.slots ++ [(st.used, .heading l0.id ls.length)]
      used := st.used + n
      noteLines := st.noteLines + (if sp.1.isEmpty then 0 else sep) + partsLines sp.1
      notes := st.notes ++ sp.1
      pending := st.pending ++ sp.2
      headingOnly := isEmpty st || st.headingOnly
      unmet := st.unmet ++ tall }

/-- An empty column makes no output. -/
def closePage (_env : Env) (st : St) : St :=
  if st.slots.isEmpty ∧ st.notes.isEmpty then st
  else { st with done := ⟨st.page, st.column, false, st.slots, st.notes, st.unmet⟩ :: st.done, unmet := [] }

def pageFigure (_env : Env) (st : St) (i : Nat) : St :=
  { st with done := ⟨st.page, 0, false, [(0, .pageFigure i)], [], []⟩ :: st.done, page := st.page + 1 }

def carrySep (env : Env) (st : St) : Int := if st.noteLines = 0 then env.separator else 0
def carryRoom (env : Env) (st : St) : Int := max 0 (cap env st - st.noteLines - carrySep env st - 1)
def carryShown (env : Env) (st : St) (len : Nat) : Nat := min len (carryRoom env st).toNat

def carryNote (env : Env) (st : St) (p : NotePart) : St :=
  if 0 < p.2.2 ∧ carryRoom env st ≤ 0 ∧ isEmpty st = true ∧ st.reserved = 0 then
    addUnmet (.unplaceableFootnote p.1 (cap env st)) st
  else
    { st with
      notes := st.notes ++ [(p.1, p.2.1, carryShown env st p.2.2)]
      noteLines := st.noteLines + carrySep env st + carryShown env st p.2.2
      pending := st.pending ++
        (if carryShown env st p.2.2 < p.2.2 then
          [(p.1, p.2.1 + carryShown env st p.2.2, p.2.2 - carryShown env st p.2.2)] else []) }

def placeDeferred (env : Env) (st : St) : List Deferred → St
  | [] => st
  | .figure i n :: rest =>
    if (n : Int) ≤ free env st ∨ isEmpty st = true then placeDeferred env (putSlot st n (.figure i)) rest
    else { st with deferred := .figure i n :: rest }
  | rest@(.pageFigure _ :: _) => { st with deferred := rest }

/-- `span isPageFigure`. -/
def spanTurned : List Deferred → List Nat × List Deferred
  | .pageFigure i :: rest => let p := spanTurned rest; (i :: p.1, p.2)
  | rest => ([], rest)

/-- The column closed and the next one opened, before the figures and
    notes waiting are placed in it (`closed'` and `fresh` of `advance`). -/
def advanceFresh (env : Env) (toPage : Bool) (st : St) : St :=
  let closed := closePage env st
  let written := closed.done.any (·.number == st.page)
  let closed' :=
    if toPage ∧ ¬written then { closed with done := ⟨st.page, 0, true, [], [], []⟩ :: closed.done }
    else closed
  let fresh : St :=
    { closed' with
      page := if toPage then st.page + 1 else st.page
      column := if toPage then 0 else st.column + 1
      firstLine := if toPage then 0 else st.firstLine
      reserved := if toPage then 0 else st.reserved
      adjust := 0
      used := if toPage then 0 else top st
      noteLines := if toPage then 0 else st.reserved
      slots := []
      notes := []
      pending := []
      spaces := []
      headingOnly := false }
  fresh

/-- The turned figures placed first and the figures that wait. -/
def advanceTurned (toPage : Bool) (st : St) : List Nat × List Deferred :=
  if toPage then spanTurned st.deferred else ([], st.deferred)

/-- The turned figures, the continued notes and the figures waiting,
    placed in that order in the column opened. -/
def openColumn (env : Env) (base : St) (turned : List Nat) (notes : List NotePart)
    (ws : List Deferred) : St :=
  let fresh' := turned.foldl (pageFigure env) base
  let withNotes := notes.foldl (carryNote env) fresh'
  placeDeferred env { withNotes with deferred := [] } ws

def advance (env : Env) (toPage : Bool) (st : St) : St :=
  let tw := advanceTurned toPage st
  openColumn env (advanceFresh env toPage st) tw.1 st.pending tw.2

def nextColumn (env : Env) (st : St) : St := advance env (env.columns ≤ st.column + 1) st
def nextPage (env : Env) (st : St) : St := advance env true st

/-! ## The rank of the loops -/

def noteWeight (p : NotePart) : Nat := p.2.2 + 1
def pendingWeight : List NotePart → Nat
  | [] => 0
  | p :: ps => noteWeight p + pendingWeight ps

/-- What waits: the figures sent on and the lines of the continued notes. -/
def waiting (st : St) : Nat := st.deferred.length + pendingWeight st.pending
def columnsLeft (env : Env) (st : St) : Nat := env.columns - (st.column + 1)
def adjustRank (st : St) : Nat := if st.adjust < 0 then 1 else 0
def fullRank (st : St) : Nat := if isEmpty st then 0 else 1

def rank (env : Env) (st : St) : Nat × Nat × Nat × Nat :=
  (waiting st, adjustRank st, fullRank st, columnsLeft env st)

/-! ## Each operation keeps what waits from growing -/

theorem pendingWeight_append (a b : List NotePart) :
    pendingWeight (a ++ b) = pendingWeight a + pendingWeight b := by
  induction a with
  | nil => simp [pendingWeight]
  | cons p ps ih => simp [pendingWeight, ih]; omega

theorem carryNote_deferred (env : Env) (st : St) (p : NotePart) :
    (carryNote env st p).deferred = st.deferred := by
  simp only [carryNote, addUnmet]; split <;> rfl

theorem carryNote_adjust (env : Env) (st : St) (p : NotePart) :
    (carryNote env st p).adjust = st.adjust := by
  simp only [carryNote, addUnmet]; split <;> rfl

theorem carryNote_pending (env : Env) (st : St) (p : NotePart) :
    pendingWeight (carryNote env st p).pending ≤ pendingWeight st.pending + noteWeight p := by
  simp only [carryNote, addUnmet]
  split
  · simp only; omega
  · simp only [pendingWeight_append]
    have : carryShown env st p.2.2 ≤ p.2.2 := Nat.min_le_left ..
    split <;> simp [pendingWeight, noteWeight] <;> omega

/-- In an empty column that keeps no lines for notes, the first note
    carried shows a line or is dropped as unplaceable. -/
theorem carryNote_pending_lt (env : Env) (st : St) (p : NotePart)
    (e : isEmpty st = true) (r : st.reserved = 0) :
    pendingWeight (carryNote env st p).pending < pendingWeight st.pending + noteWeight p := by
  simp only [carryNote, addUnmet]
  split
  · simp only [noteWeight]; omega
  · rename_i h
    simp only [pendingWeight_append]
    have le : carryShown env st p.2.2 ≤ p.2.2 := Nat.min_le_left ..
    split
    · rename_i lt
      have len : 0 < p.2.2 := by omega
      have pos : 0 < carryShown env st p.2.2 := by
        have room : ¬ carryRoom env st ≤ 0 := fun le => h ⟨len, le, e, r⟩
        simp only [carryShown]; have cast := Int.toNat_of_nonneg (show 0 ≤ carryRoom env st by omega)
        exact Nat.lt_min.mpr ⟨len, by omega⟩
      simp [pendingWeight, noteWeight]; omega
    · simp [pendingWeight, noteWeight]; omega

theorem carryAll_deferred (env : Env) (ps : List NotePart) (st : St) :
    (ps.foldl (carryNote env) st).deferred = st.deferred := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl]; rw [ih, carryNote_deferred]

theorem carryAll_adjust (env : Env) (ps : List NotePart) (st : St) :
    (ps.foldl (carryNote env) st).adjust = st.adjust := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl]; rw [ih, carryNote_adjust]

theorem carryAll_pending (env : Env) (ps : List NotePart) (st : St) :
    pendingWeight (ps.foldl (carryNote env) st).pending ≤ pendingWeight st.pending + pendingWeight ps := by
  induction ps generalizing st with
  | nil => simp [pendingWeight]
  | cons p ps ih =>
    simp only [List.foldl, pendingWeight]
    have := ih (carryNote env st p)
    have := carryNote_pending env st p
    omega

theorem carryAll_pending_lt (env : Env) (p : NotePart) (ps : List NotePart) (st : St)
    (e : isEmpty st = true) (r : st.reserved = 0) :
    pendingWeight ((p :: ps).foldl (carryNote env) st).pending
      < pendingWeight st.pending + pendingWeight (p :: ps) := by
  simp only [List.foldl, pendingWeight]
  have := carryAll_pending env ps (carryNote env st p)
  have := carryNote_pending_lt env st p e r
  omega

theorem placeDeferred_pending (env : Env) (ws : List Deferred) (st : St) :
    (placeDeferred env st ws).pending = st.pending := by
  induction ws generalizing st with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · rw [ih]; rfl
      · rfl
    | pageFigure i => rfl

theorem placeDeferred_adjust (env : Env) (ws : List Deferred) (st : St) :
    (placeDeferred env st ws).adjust = st.adjust := by
  induction ws generalizing st with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · rw [ih]; rfl
      · rfl
    | pageFigure i => rfl

theorem placeDeferred_deferred (env : Env) (ws : List Deferred) (st : St) (h : st.deferred = []) :
    (placeDeferred env st ws).deferred.length ≤ ws.length := by
  induction ws generalizing st with
  | nil => simp [placeDeferred, h]
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · have := ih (putSlot st n (.figure i)) (by simp [putSlot, h]); simp; omega
      · simp
    | pageFigure i => simp [placeDeferred]

theorem placeDeferred_deferred_lt (env : Env) (i n : Nat) (ws : List Deferred) (st : St)
    (h : st.deferred = []) (e : isEmpty st = true) :
    (placeDeferred env st (.figure i n :: ws)).deferred.length < ws.length + 1 := by
  unfold placeDeferred
  rw [if_pos (Or.inr e)]
  have := placeDeferred_deferred env ws (putSlot st n (.figure i)) (by simp [putSlot, h])
  omega

theorem spanTurned_length (d : List Deferred) :
    (spanTurned d).1.length + (spanTurned d).2.length = d.length := by
  induction d with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n => simp [spanTurned]
    | pageFigure i => simp [spanTurned]; omega

theorem pageFigures_fields (env : Env) (ts : List Nat) (st : St) :
    let r := ts.foldl (pageFigure env) st
    r.deferred = st.deferred ∧ r.pending = st.pending ∧ r.adjust = st.adjust ∧ r.notes = st.notes
      ∧ r.used = st.used ∧ r.firstLine = st.firstLine ∧ r.reserved = st.reserved
      ∧ r.noteLines = st.noteLines ∧ r.column = st.column := by
  induction ts generalizing st with
  | nil => simp
  | cons t _ ih => exact ih (pageFigure env st t)

theorem carryNote_column (env : Env) (st : St) (p : NotePart) :
    (carryNote env st p).column = st.column := by
  simp only [carryNote, addUnmet]; split <;> rfl

theorem carryAll_column (env : Env) (ps : List NotePart) (st : St) :
    (ps.foldl (carryNote env) st).column = st.column := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl]; rw [ih, carryNote_column]

theorem placeDeferred_column (env : Env) (ws : List Deferred) (st : St) :
    (placeDeferred env st ws).column = st.column := by
  induction ws generalizing st with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · rw [ih]; rfl
      · rfl
    | pageFigure i => rfl

/-! ## Going on to the next column -/

theorem openColumn_adjust (env : Env) (base : St) (ts : List Nat) (ps : List NotePart) (ws : List Deferred) :
    (openColumn env base ts ps ws).adjust = base.adjust := by
  simp only [openColumn]
  rw [placeDeferred_adjust, carryAll_adjust, (pageFigures_fields ..).2.2.1]

theorem openColumn_column (env : Env) (base : St) (ts : List Nat) (ps : List NotePart) (ws : List Deferred) :
    (openColumn env base ts ps ws).column = base.column := by
  simp only [openColumn]
  rw [placeDeferred_column, carryAll_column, (pageFigures_fields ..).2.2.2.2.2.2.2.2]

theorem openColumn_deferred (env : Env) (base : St) (ts : List Nat) (ps : List NotePart) (ws : List Deferred) :
    (openColumn env base ts ps ws).deferred.length ≤ ws.length :=
  placeDeferred_deferred env ws _ rfl

theorem openColumn_pending (env : Env) (base : St) (ts : List Nat) (ps : List NotePart) (ws : List Deferred) :
    pendingWeight (openColumn env base ts ps ws).pending ≤ pendingWeight base.pending + pendingWeight ps := by
  simp only [openColumn]
  rw [placeDeferred_pending]
  have c := carryAll_pending env ps (ts.foldl (pageFigure env) base)
  rw [(pageFigures_fields ..).2.1] at c
  exact c

theorem advance_adjust (env : Env) (b : Bool) (st : St) : (advance env b st).adjust = 0 := by
  simp only [advance]; rw [openColumn_adjust]; rfl

theorem advance_column (env : Env) (b : Bool) (st : St) :
    (advance env b st).column = if b then 0 else st.column + 1 := by
  simp only [advance]; rw [openColumn_column]; rfl

theorem advanceTurned_length (b : Bool) (st : St) :
    (advanceTurned b st).1.length + (advanceTurned b st).2.length = st.deferred.length := by
  unfold advanceTurned; split
  · exact spanTurned_length st.deferred
  · simp

theorem advance_waiting_le (env : Env) (b : Bool) (st : St) :
    waiting (advance env b st) ≤ waiting st := by
  simp only [advance, waiting]
  have d := openColumn_deferred env (advanceFresh env b st) (advanceTurned b st).1 st.pending
    (advanceTurned b st).2
  have c := openColumn_pending env (advanceFresh env b st) (advanceTurned b st).1 st.pending
    (advanceTurned b st).2
  have fresh : (advanceFresh env b st).pending = [] := rfl
  rw [fresh] at c
  have t := advanceTurned_length b st
  simp only [pendingWeight] at c
  omega

theorem spanTurned_head (w : Deferred) (ws : List Deferred) (d : List Deferred)
    (h : (spanTurned d).1 = []) (e : (spanTurned d).2 = w :: ws) : ∀ i, w ≠ .pageFigure i := by
  intro i we
  cases d with
  | nil => simp [spanTurned] at e
  | cons x xs =>
    cases x with
    | figure a b => simp [spanTurned] at e; rw [← e.1] at we; cases we
    | pageFigure a => simp [spanTurned] at h

theorem openColumn_notes_lt (env : Env) (base : St) (p : NotePart) (ps : List NotePart)
    (ws : List Deferred) (e : isEmpty base = true) (r : base.reserved = 0) :
    pendingWeight (openColumn env base [] (p :: ps) ws).pending
      < pendingWeight base.pending + pendingWeight (p :: ps) := by
  simp only [openColumn, List.foldl]
  rw [placeDeferred_pending]
  exact carryAll_pending_lt env p ps base e r

theorem openColumn_figure_lt (env : Env) (base : St) (i n : Nat) (ws : List Deferred)
    (e : isEmpty base = true) :
    (openColumn env base [] [] (.figure i n :: ws)).deferred.length < ws.length + 1 ∧
      (openColumn env base [] [] (.figure i n :: ws)).pending = base.pending := by
  simp only [openColumn, List.foldl]
  refine ⟨placeDeferred_deferred_lt env i n ws _ rfl e, ?_⟩
  rw [placeDeferred_pending]

/-- Going on to the next page places a turned figure on a page of its
    own, shows a line of the first continued note or drops it as
    unplaceable, or places the first figure waiting. -/
theorem advance_page_waiting_lt (env : Env) (st : St) (h : 0 < waiting st) :
    waiting (advance env true st) < waiting st := by
  simp only [advance, waiting]
  have fresh : (advanceFresh env true st).pending = [] := rfl
  have freshEmpty : isEmpty (advanceFresh env true st) = true := by
    simp [advanceFresh, isEmpty, top, List.isEmpty]
  have freshReserved : (advanceFresh env true st).reserved = 0 := rfl
  have t := advanceTurned_length true st
  have tw : advanceTurned true st = spanTurned st.deferred := rfl
  generalize advanceTurned true st = tw' at t tw ⊢
  obtain ⟨turned, ws⟩ := tw'
  simp only at t tw ⊢
  have d := openColumn_deferred env (advanceFresh env true st) turned st.pending ws
  have c := openColumn_pending env (advanceFresh env true st) turned st.pending ws
  rw [fresh] at c
  simp only [pendingWeight] at c
  cases turned with
  | cons _ _ => simp only [List.length] at t; omega
  | nil =>
    simp only [List.length] at t
    revert h c d
    cases ps : st.pending with
    | cons p ps' =>
      intro _ c _
      have c' := openColumn_notes_lt env (advanceFresh env true st) p ps' ws freshEmpty freshReserved
      rw [fresh] at c'
      simp only [pendingWeight] at c' ⊢
      omega
    | nil =>
      intro h c _
      simp only [waiting, ps, pendingWeight] at h
      cases ws with
      | nil => simp at t; omega
      | cons w ws' =>
        have notTurned := spanTurned_head w ws' st.deferred
          (by rw [← tw]) (by rw [← tw])
        cases w with
        | pageFigure i => exact absurd rfl (notTurned i)
        | figure i n =>
          have := openColumn_figure_lt env (advanceFresh env true st) i n ws' freshEmpty
          rw [this.2, fresh]
          simp only [List.length] at t
          simp only [pendingWeight]
          omega

theorem advance_page_empty (env : Env) (st : St) (h : waiting st = 0) :
    isEmpty (advance env true st) = true := by
  have d : st.deferred = [] := by
    cases e : st.deferred with
    | nil => rfl
    | cons _ _ => simp [waiting, e] at h; omega
  have p : st.pending = [] := by
    cases e : st.pending with
    | nil => rfl
    | cons q _ => simp [waiting, e, pendingWeight, noteWeight] at h; omega
  simp [advance, advanceTurned, d, p, spanTurned, openColumn, placeDeferred, advanceFresh, isEmpty, top, List.isEmpty]

/-! ## The rank decreases where the loops go on -/

/-- The order of `rank`: lexicographic on four natural numbers. -/
abbrev RankLt : (Nat × Nat × Nat × Nat) → (Nat × Nat × Nat × Nat) → Prop :=
  Prod.Lex (· < ·) (Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)))

theorem rankLt_of {a b c d a' b' c' d' : Nat}
    (h : a' < a ∨ (a' = a ∧ (b' < b ∨ (b' = b ∧ (c' < c ∨ (c' = c ∧ d' < d)))))) :
    RankLt (a', b', c', d') (a, b, c, d) := by
  simp only [RankLt, Prod.lex_def]
  exact h

/-- Going on from a column with something in it, or from a column made
    shorter, decreases the rank: the loops `keep` and `placeLines` go
    on to the next column only from such a column. -/
theorem I4_nextColumn_rank (env : Env) (st : St) (h : isEmpty st = false ∨ st.adjust < 0) :
    RankLt (rank env (nextColumn env st)) (rank env st) := by
  simp only [rank, nextColumn]
  apply rankLt_of
  have adj := advance_adjust env (env.columns ≤ st.column + 1) st
  have col := advance_column env (env.columns ≤ st.column + 1) st
  have le := advance_waiting_le env (env.columns ≤ st.column + 1) st
  have adjZero : adjustRank (advance env (decide (env.columns ≤ st.column + 1)) st) = 0 := by
    simp [adjustRank, adj]
  have adjOld : st.adjust < 0 → adjustRank st = 1 := fun n => by simp [adjustRank, n]
  have fullOld : isEmpty st = false → fullRank st = 1 := fun n => by simp [fullRank, n]
  have fullLe : fullRank (advance env (decide (env.columns ≤ st.column + 1)) st) ≤ 1 := by
    unfold fullRank; split <;> omega
  by_cases toPage : env.columns ≤ st.column + 1
  · simp only [toPage, decide_True] at adj col le adjZero fullLe ⊢
    by_cases w : 0 < waiting st
    · exact Or.inl (advance_page_waiting_lt env st w)
    · have w0 : waiting st = 0 := by omega
      have e := advance_page_empty env st w0
      have full0 : fullRank (advance env true st) = 0 := by simp [fullRank, e]
      right
      refine ⟨by omega, ?_⟩
      rw [adjZero, full0]
      cases h with
      | inl n =>
        have := fullOld n
        by_cases a : st.adjust < 0
        · have := adjOld a; omega
        · have a0 : adjustRank st = 0 := by simp [adjustRank, a]
          omega
      | inr n => have := adjOld n; omega
  · simp only [toPage, decide_False] at adj col le adjZero fullLe ⊢
    have cl : columnsLeft env (advance env false st) < columnsLeft env st := by
      have c1 : (advance env false st).column = st.column + 1 := by rw [col]; rfl
      simp only [columnsLeft, c1]; omega
    by_cases w : waiting (advance env false st) < waiting st
    · exact Or.inl w
    · right
      refine ⟨by omega, ?_⟩
      rw [adjZero]
      cases h with
      | inr n => have := adjOld n; omega
      | inl n =>
        have := fullOld n
        by_cases a : st.adjust < 0
        · have := adjOld a; omega
        · have a0 : adjustRank st = 0 := by simp [adjustRank, a]
          omega

/-- Going on while figures or notes wait decreases what waits and the
    columns left on the page (`flushDeferred`, `flushFigures`). -/
theorem I4_nextColumn_flush_rank (env : Env) (st : St) (h : 0 < waiting st) :
    Prod.Lex (· < ·) (· < ·) (waiting (nextColumn env st), columnsLeft env (nextColumn env st))
      (waiting st, columnsLeft env st) := by
  simp only [Prod.lex_def, nextColumn]
  have col := advance_column env (env.columns ≤ st.column + 1) st
  have le := advance_waiting_le env (env.columns ≤ st.column + 1) st
  by_cases toPage : env.columns ≤ st.column + 1
  · simp only [toPage, decide_True] at col le ⊢
    exact Or.inl (advance_page_waiting_lt env st h)
  · simp only [toPage, decide_False] at col le ⊢
    by_cases w : waiting (advance env false st) < waiting st
    · exact Or.inl w
    · have c1 : (advance env false st).column = st.column + 1 := by rw [col]; rfl
      exact Or.inr ⟨by omega, by simp only [columnsLeft, c1]; omega⟩

/-! ## The loops of State.hs -/

set_option linter.unusedVariables false in
/-- `keep` of State.hs: the next columns, until the lines needed are free
    or the column is empty. -/
def keep (env : Env) (st : St) (need : St → Int) : St :=
  if h : free env st < need st ∧ isEmpty st = false then keep env (nextColumn env st) need else st
termination_by rank env st
decreasing_by exact I4_nextColumn_rank env st (Or.inl h.2)

theorem waiting_pos (st : St) (h : ¬(st.deferred = [] ∧ st.pending = [])) : 0 < waiting st := by
  simp only [waiting]
  cases d : st.deferred with
  | cons _ _ => simp; omega
  | nil =>
    cases p : st.pending with
    | nil => exact absurd ⟨d, p⟩ h
    | cons q _ => simp [pendingWeight, noteWeight]; omega

set_option linter.unusedVariables false in
/-- `flushDeferred` of State.hs. -/
def flushDeferred (env : Env) (st : St) : St :=
  if h : st.deferred = [] ∧ st.pending = [] then st else flushDeferred env (nextColumn env st)
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st h)

set_option linter.unusedVariables false in
/-- `flushFigures` of State.hs. -/
def flushFigures (env : Env) (st : St) : St :=
  if h : st.deferred = [] then st else flushFigures env (nextColumn env st)
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st (fun c => h c.1))

/-! ## The lines of a paragraph (`placeLines` of Paginate.hs) -/

/-- `splitAtBreak` of Decide.hs. -/
def splitAtBreak (kp : Keep) (isStart : Bool) (n k : Nat) : Nat :=
  if n ≤ k then k
  else if kp.all then 0
  else
    let k1 := if n - k < kp.last then n - kp.last else k
    if isStart ∧ 0 < k1 ∧ k1 < kp.first then 0 else k1

def emptyish (env : Env) (st : St) (ls : List Line) : Bool :=
  isEmpty st || (st.headingOnly && env.roomForLine st ls)

/-- The lines placed in the column (`k`) and whether they are forced. -/
def lineCount (env : Env) (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) : Nat × Bool :=
  let n := ls.length
  let k0 := env.fitting st ls
  let k2 := splitAtBreak kp isStart n k0
  let forced := k2 == 0 && emptyish env st ls
  (if forced then max 1 (min n k0) else k2, forced)

def shortParts (kp : Keep) (pid : Nat) (forced isStart : Bool) (n k : Nat) : List Unmet :=
  (if forced ∧ isStart ∧ k < kp.first then [.shortFirst pid kp.first k] else [])
    ++ (if forced ∧ n - k < kp.last then [.shortLast pid kp.last (n - k)] else [])

theorem lineCount_zero (env : Env) (kp : Keep) (st : St) (isStart : Bool) (ls : List Line)
    (h : (lineCount env kp st isStart ls).1 = 0) :
    (lineCount env kp st isStart ls).2 = false ∧ isEmpty st = false := by
  simp only [lineCount] at h ⊢
  cases hf : (splitAtBreak kp isStart ls.length (env.fitting st ls) == 0 && emptyish env st ls)
  · rw [hf] at h
    simp only [ite_false] at h
    refine ⟨rfl, ?_⟩
    rw [h] at hf
    simp only [emptyish, beq_self_eq_true, Bool.true_and, Bool.or_eq_false_iff] at hf
    exact hf.1
  · rw [hf] at h
    simp at h
    omega

def allRank (kp : Keep) : Nat := if kp.all then 1 else 0

abbrev LinesLt : (Nat × Nat × Nat × Nat × Nat × Nat) → (Nat × Nat × Nat × Nat × Nat × Nat) → Prop :=
  Prod.Lex (· < ·) (Prod.Lex (· < ·) RankLt)

theorem linesLt_rank {a b : Nat} {r r' : Nat × Nat × Nat × Nat} (h : RankLt r' r) :
    LinesLt (a, b, r') (a, b, r) := by
  exact Prod.Lex.right _ (Prod.Lex.right _ h)

set_option linter.unusedVariables false in
/-- `go` of `placeLines` of Paginate.hs, for the paragraph whose first
    line is `pid`. -/
def placeLinesGo (env : Env) (pid : Nat) : Keep → St → Bool → List Line → St
  | _, st, _, [] => st
  | kp, st, isStart, l :: ls' =>
    if h1 : st.adjust < 0 ∧ isEmpty st = true ∧ env.roomForLine st (l :: ls') = false then
      placeLinesGo env pid kp (nextColumn env st) isStart (l :: ls')
    else if h2 : kp.all = true ∧ isStart = true ∧ env.fitting st (l :: ls') < (l :: ls').length then
      if h3 : isEmpty st = true ∨ st.headingOnly = true then
        placeLinesGo env pid { kp with all := false } (addUnmet (.splitKept pid) st) isStart (l :: ls')
      else placeLinesGo env pid kp (nextColumn env st) isStart (l :: ls')
    else
      let kf := lineCount env kp st isStart (l :: ls')
      if h4 : (l :: ls').length ≤ kf.1 then (l :: ls').foldl (putLine env) st
      else
        let short := shortParts kp pid kf.2 isStart (l :: ls').length kf.1
        let st1 := short.foldl (fun s u => addUnmet u s) (((l :: ls').take kf.1).foldl (putLine env) st)
        placeLinesGo env pid kp (nextColumn env st1) (isStart && kf.1 == 0) ((l :: ls').drop kf.1)
termination_by kp st _ ls => (ls.length, allRank kp, rank env st)
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
      change ¬ List.length (l :: ls') ≤ (lineCount env kp st isStart (l :: ls')).1 at h4
      simp only [List.length] at h4
      omega

def placeLines (env : Env) (kp : Keep) (st : St) (isStart : Bool) : List Line → St
  | [] => st
  | l0 :: ls => placeLinesGo env l0.id kp st isStart (l0 :: ls)

/-! ## Breaks (Paginate.hs `applyBreaks` and State.hs `parityStart`) -/

def isPageFigure : Deferred → Bool
  | .pageFigure _ => true
  | _ => false

def isPageFigureSlot : Int × Slot → Bool
  | (_, .pageFigure _) => true
  | _ => false

def afterPageFigure (st : St) : Bool :=
  match st.done with
  | po :: _ => po.number + 1 == st.page && po.slots.any isPageFigureSlot
  | [] => false

def parityStart (env : Env) (p : Nat → Bool) (st : St) : St :=
  let st0 := flushDeferred env st
  let st1 := if isEmpty st0 = true ∧ st0.column = 0 then st0 else nextPage env st0
  if p st1.page then st1 else blankPage env st1

def odd (n : Nat) : Bool := n % 2 == 1
def even (n : Nat) : Bool := n % 2 == 0

def breakPage (env : Env) (st : St) : St :=
  if isEmpty st = true ∧ st.column = 0 ∧ afterPageFigure st = false then blankPage env st
  else if isEmpty st = true ∧ st.column = 0 then st
  else nextPage env st

def applyBreakKind (env : Env) (st : St) : BreakKind → St
  | .page => breakPage env st
  | .recto => parityStart env odd st
  | .verso => parityStart env even st
  | .column =>
    if 1 < env.columns ∧ st.deferred.any isPageFigure = false then nextColumn env st
    else breakPage env st

def applyBreaks (env : Env) (st : St) : St :=
  st.breaks.foldl (applyBreakKind env) { st with breaks := [] }

/-! ## Need-lines, spaces and blank lines -/

def noNeed : Need := ⟨0, 0⟩

def applyNeed (env : Env) (st : St) : St :=
  match st.need with
  | none => st
  | some n =>
    if cap env st < n then
      let st1 := addUnmet (.needLines n) { st with need := none }
      if isEmpty st1 then st1 else nextColumn env st1
    else keep env { st with need := none } (fun _ => n)

def needBeforeSpace (env : Env) (st : St) : St :=
  match st.need with
  | none => st
  | some n =>
    if st.needAt = some (st.page, st.column) then st
    else if cap env st < n then applyNeed env { st with needAt := none }
    else
      let st1 := applyNeed env { st with needAt := none }
      { st1 with need := some n, needAt := some (st1.page, st1.column) }

/-- `place` of a space. -/
def placeSpaceFlow (env : Env) (st : St) (n : Nat) : St :=
  if st.used = top st then st else { st with used := st.used + max 0 (min (n : Int) (free env st)) }

def placeSpace (env : Env) (st : St) (n : Nat) : St :=
  let st1 := placeSpaceFlow env st n
  { st1 with spaces := st.spaces ++ [(n, st1.used - st.used)] }

def needBeforeSpaces (env : Env) (st : St) : St :=
  let k := (st.spaces.map (·.2)).foldr (· + ·) 0
  let st1 := needBeforeSpace env { st with used := st.used - k }
  if st1.page = st.page ∧ st1.column = st.column then { st1 with used := st1.used + k }
  else (st.spaces.map (·.1)).foldl (placeSpace env) st1

def needAfterSpaces (env : Env) (st : St) : St :=
  if st.spaces = [] ∨ st.breaks ≠ [] then st else needBeforeSpaces env st

def needMore (env : Env) (n : Nat) (st : St) : St :=
  match st.need with
  | some n0 => if n ≤ n0 then st else needAfterSpaces env { st with need := some n, needAt := none }
  | none => needAfterSpaces env { st with need := some n, needAt := none }

def needBefore (env : Env) (st : St) (flows : List Flow) : St :=
  match st.need, st.needAt with
  | some n, some at_ =>
    if at_ = (st.page, st.column) then
      keep env { st with need := none, needAt := none }
        (fun s => if (s.page, s.column) = at_ then needIn env s noNeed (env.nextNeed flows) else n)
    else applyNeed env { st with needAt := none }
  | _, _ => applyNeed env { st with needAt := none }

def startsRecto : Flow → Bool
  | .heading recto _ _ => recto
  | _ => false

def placeBlank (env : Env) (st0 : St) (f : Flow) (rest : List Flow) : St :=
  match st0.blank with
  | [] => st0
  | blanks =>
    let capacity := env.capacity
    let st1 := if startsRecto f then parityStart env odd st0 else st0
    let total : Int := blanks.foldl (fun a (n : Nat) => min capacity (a + min capacity (n : Int))) 0
    let st2 := keep env st1
      (fun s => if s.used = top s then 0 else total + needIn env s noNeed (env.nextNeed (f :: rest)))
    if st2.used = top st2 then blanks.foldl (fun s _ => addUnmet .droppedBlank s) { st2 with blank := [] }
    else { st2 with used := st2.used + total, blank := [] }

/-! ## One flow (`place`, `step` and `placeAll` of Paginate.hs) -/

def waitsBehind (st : St) : Flow → Bool
  | .figure _ _ => !st.deferred.isEmpty
  | .pageFigure _ =>
    !(st.deferred.isEmpty && st.column == 0 && st.used == 0 && st.notes.isEmpty && st.noteLines == 0)
  | _ => false

def waitsFor : Flow → Bool
  | .brk _ | .space _ | .blank _ | .needLines _ => true
  | _ => false

def headingNeed (env : Env) (st : St) (n : Nat) (ls : List Line) : Int :=
  needIn env st ⟨n, noteLinesOf ls⟩ noNeed

def place (env : Env) (st : St) (f : Flow) (rest : List Flow) : St :=
  match f with
  | .paragraph kp ls => placeLines env kp st true ls
  | .continued kp ls => placeLines env kp st false ls
  | .heading recto n ls =>
    let st1 := if recto then parityStart env odd st
      else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))
    let st2 := if headingNeed env st1 n ls ≤ free env st1 ∨ isEmpty st1 = true then st1
      else nextColumn env st1
    putBlock env st2 n ls
  | .figure i n =>
    if !st.deferred.isEmpty then { st with deferred := st.deferred ++ [.figure i n] }
    else if (n : Int) ≤ free env st ∨ isEmpty st = true then putSlot st n (.figure i)
    else { st with deferred := st.deferred ++ [.figure i n] }
  | .pageFigure i =>
    if st.deferred.isEmpty ∧ st.column = 0 ∧ st.used = 0 ∧ st.notes.isEmpty ∧ st.noteLines = 0 then
      pageFigure env { st with adjust := 0 } i
    else { st with deferred := st.deferred ++ [.pageFigure i] }
  | .brk k => { st with breaks := st.breaks ++ [k] }
  | .space n => placeSpaceFlow env st n
  | .needLines _ => st
  | .blank _ => st

def deferredFigure (i : Nat) : Deferred → Bool
  | .figure j _ => i == j
  | _ => false

/-- `step` of Paginate.hs; `checkNoBreak` and `placeFlow` are the
    identity and `place` here, as no flow of the model is a no-break or
    a keep-with-next. -/
def step (env : Env) (st : St) (f : Flow) (rest : List Flow) : St :=
  match f with
  | .needLines n => needMore env n st
  | .blank n => if rest.all waitsFor then st else { st with blank := st.blank ++ [n] }
  | .brk _ => place env st f rest
  | .space n => placeSpace env (needBeforeSpaces env (applyBreaks env st)) n
  | _ =>
    let stB := applyBreaks env st
    let waiting := waitsBehind stB f
    let st1 := if waiting then place env stB f rest
      else place env (placeBlank env (needBefore env stB (f :: rest)) f rest) f rest
    let deferred := match f with
      | .figure i _ => st1.deferred.any (deferredFigure i)
      | .pageFigure _ => true
      | _ => false
    let spaces := if waiting ∧ st.breaks = [] then st1.spaces else []
    { st1 with seen := true, lastDeferred := deferred, spaces := spaces }

def placeAll (env : Env) (st : St) : List Flow → St
  | [] =>
    let st2 := { st with breaks := [], need := none, needAt := none, blank := [] }
    let dropBlanks (s : St) := st.blank.foldl (fun s' _ => addUnmet .droppedBlank s') s
    if st.blank = [] then flushDeferred env st2
    else if st2.deferred = [] then flushDeferred env (dropBlanks st2)
    else flushDeferred env (dropBlanks (nextColumn env st2))
  | f :: rest => placeAll env (step env st f rest) rest

/-- `paginateWithin` of Paginate.hs up to the pages it returns. -/
def paginate (env : Env) (flows : List Flow) : St :=
  closePage env (placeAll env initialState flows)

/-- Root ADR 0352 invariant 4: the pagination of every finite list of
    flows ends.  Every definition above is total, and the
    loops are accepted by Lean through `I4_nextColumn_rank` and
    `I4_nextColumn_flush_rank`. -/
theorem I4_paginate_ends (env : Env) (flows : List Flow) : ∃ st, paginate env flows = st :=
  ⟨_, rfl⟩

/-! ## The lines are placed once, in the order written (invariant 5) -/

/-- The lines and headings of slots, in order. -/
def textSlots : List (Int × Slot) → List Slot
  | [] => []
  | (_, .line i) :: r => .line i :: textSlots r
  | (_, .heading i c) :: r => .heading i c :: textSlots r
  | _ :: r => textSlots r

theorem textSlots_append (a b : List (Int × Slot)) :
    textSlots (a ++ b) = textSlots a ++ textSlots b := by
  induction a with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨g, s⟩ := x
    cases s <;> simp [textSlots, ih]

/-- The lines and headings of the pages closed, in page order. -/
def pagesText (done : List PageOut) : List Slot := done.reverse.bind (fun p => textSlots p.slots)

theorem pagesText_cons (p : PageOut) (done : List PageOut) :
    pagesText (p :: done) = pagesText done ++ textSlots p.slots := by
  simp [pagesText, List.reverse_cons, List.append_bind]

/-- The lines and headings placed so far: those of the pages closed,
    then those of the current column. -/
def text (st : St) : List Slot := pagesText st.done ++ textSlots st.slots

/-- The lines and headings of the flows written. -/
def flowText : Flow → List Slot
  | .paragraph _ ls => ls.map (fun l => .line l.id)
  | .continued _ ls => ls.map (fun l => .line l.id)
  | .heading _ _ [] => []
  | .heading _ _ (l0 :: ls) => [.heading l0.id (ls.length + 1)]
  | _ => []

def sourceText (flows : List Flow) : List Slot := flows.bind flowText

theorem text_addUnmet (u : Unmet) (st : St) : text (addUnmet u st) = text st := rfl

theorem text_putSlot_figure (st : St) (n i : Nat) : text (putSlot st n (.figure i)) = text st := by
  simp [text, putSlot, textSlots_append, textSlots]

theorem text_pageFigure (env : Env) (st : St) (i : Nat) : text (pageFigure env st i) = text st := by
  simp [text, pageFigure, pagesText_cons, textSlots]

theorem text_blankPage (env : Env) (st : St) : text (blankPage env st) = text st := by
  simp [text, blankPage, pagesText_cons, textSlots]

theorem text_advanceFresh (env : Env) (b : Bool) (st : St) : text (advanceFresh env b st) = text st := by
  simp only [advanceFresh, closePage]
  by_cases e : st.slots.isEmpty = true ∧ st.notes.isEmpty = true
  · have s : st.slots = [] := by
      cases h : st.slots with
      | nil => rfl
      | cons _ _ => simp [h, List.isEmpty] at e
    simp only [e, and_self, ite_true]
    repeat' split
    all_goals simp [text, pagesText_cons, textSlots, s]
  · simp only [e, ite_false]
    repeat' split
    all_goals simp [text, pagesText_cons, textSlots]

theorem text_carryNote (env : Env) (st : St) (p : NotePart) : text (carryNote env st p) = text st := by
  simp only [carryNote, addUnmet]; split <;> rfl

theorem text_carryAll (env : Env) (ps : List NotePart) (st : St) :
    text (ps.foldl (carryNote env) st) = text st := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl]; rw [ih, text_carryNote]

theorem text_pageFigures (env : Env) (ts : List Nat) (st : St) :
    text (ts.foldl (pageFigure env) st) = text st := by
  induction ts generalizing st with
  | nil => rfl
  | cons t ts ih => simp only [List.foldl]; rw [ih, text_pageFigure]

theorem text_placeDeferred (env : Env) (ws : List Deferred) (st : St) :
    text (placeDeferred env st ws) = text st := by
  induction ws generalizing st with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · rw [ih, text_putSlot_figure]
      · rfl
    | pageFigure i => rfl

theorem text_advance (env : Env) (b : Bool) (st : St) : text (advance env b st) = text st := by
  simp only [advance, openColumn]
  rw [text_placeDeferred]
  show text (List.foldl (carryNote env) _ st.pending) = text st
  rw [text_carryAll, text_pageFigures, text_advanceFresh]

theorem text_nextColumn (env : Env) (st : St) : text (nextColumn env st) = text st := text_advance ..
theorem text_nextPage (env : Env) (st : St) : text (nextPage env st) = text st := text_advance ..

theorem text_keep (env : Env) (st : St) (need : St → Int) : text (keep env st need) = text st := by
  by_cases h : free env st < need st ∧ isEmpty st = false
  · unfold keep; rw [dif_pos h, text_keep env (nextColumn env st) need, text_nextColumn]
  · unfold keep; rw [dif_neg h]
termination_by rank env st
decreasing_by exact I4_nextColumn_rank env st (Or.inl h.2)

theorem text_flushDeferred (env : Env) (st : St) : text (flushDeferred env st) = text st := by
  by_cases h : st.deferred = [] ∧ st.pending = []
  · unfold flushDeferred; rw [dif_pos h]
  · unfold flushDeferred; rw [dif_neg h]
    rw [text_flushDeferred env (nextColumn env st), text_nextColumn]
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st h)

theorem text_flushFigures (env : Env) (st : St) : text (flushFigures env st) = text st := by
  by_cases h : st.deferred = []
  · unfold flushFigures; rw [dif_pos h]
  · unfold flushFigures; rw [dif_neg h]
    rw [text_flushFigures env (nextColumn env st), text_nextColumn]
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st (fun c => h c.1))

theorem text_parityStart (env : Env) (p : Nat → Bool) (st : St) : text (parityStart env p st) = text st := by
  simp only [parityStart]
  repeat' split
  all_goals simp only [text_blankPage, text_nextPage, text_flushDeferred]

theorem text_breakPage (env : Env) (st : St) : text (breakPage env st) = text st := by
  simp only [breakPage]
  repeat' split
  all_goals simp only [text_blankPage, text_nextPage]

theorem text_applyBreakKind (env : Env) (st : St) (k : BreakKind) :
    text (applyBreakKind env st k) = text st := by
  cases k <;> simp only [applyBreakKind, text_breakPage, text_parityStart]
  split <;> simp only [text_nextColumn, text_breakPage]

theorem text_applyBreaks (env : Env) (st : St) : text (applyBreaks env st) = text st := by
  simp only [applyBreaks]
  suffices ∀ (ks : List BreakKind) (s : St), text (ks.foldl (applyBreakKind env) s) = text s by
    rw [this]; rfl
  intro ks
  induction ks with
  | nil => intro s; rfl
  | cons k ks ih => intro s; simp only [List.foldl]; rw [ih, text_applyBreakKind]

theorem text_ite {c : Prop} [Decidable c] {a b : St} {t : List Slot} (ha : text a = t) (hb : text b = t) :
    text (if c then a else b) = t := by
  split
  · exact ha
  · exact hb

theorem text_applyNeed (env : Env) (st : St) : text (applyNeed env st) = text st := by
  unfold applyNeed
  split
  · rfl
  · split
    · apply text_ite
      · rfl
      · rw [text_nextColumn]; rfl
    · rw [text_keep]; rfl

theorem text_needBeforeSpace (env : Env) (st : St) : text (needBeforeSpace env st) = text st := by
  unfold needBeforeSpace
  split
  · rfl
  · repeat' split
    all_goals first | rfl | (rw [text_applyNeed]; rfl) | (show text (applyNeed env _) = _; rw [text_applyNeed]; rfl)

theorem text_placeSpaceFlow (env : Env) (st : St) (n : Nat) : text (placeSpaceFlow env st n) = text st := by
  unfold placeSpaceFlow; split <;> rfl

theorem text_placeSpace (env : Env) (st : St) (n : Nat) : text (placeSpace env st n) = text st := by
  show text (placeSpaceFlow env st n) = text st
  exact text_placeSpaceFlow env st n

theorem text_placeSpaces (env : Env) (ns : List Nat) (st : St) :
    text (ns.foldl (placeSpace env) st) = text st := by
  induction ns generalizing st with
  | nil => rfl
  | cons n ns ih => simp only [List.foldl]; rw [ih, text_placeSpace]

theorem text_needBeforeSpaces (env : Env) (st : St) : text (needBeforeSpaces env st) = text st := by
  unfold needBeforeSpaces
  simp only
  split
  · show text (needBeforeSpace env _) = text st
    rw [text_needBeforeSpace]; rfl
  · rw [text_placeSpaces, text_needBeforeSpace]; rfl

theorem text_needAfterSpaces (env : Env) (st : St) : text (needAfterSpaces env st) = text st := by
  unfold needAfterSpaces; split
  · rfl
  · exact text_needBeforeSpaces env st

theorem text_needMore (env : Env) (n : Nat) (st : St) : text (needMore env n st) = text st := by
  unfold needMore
  split
  · split
    · rfl
    · rw [text_needAfterSpaces]; rfl
  · rw [text_needAfterSpaces]; rfl

theorem text_needBefore (env : Env) (st : St) (flows : List Flow) :
    text (needBefore env st flows) = text st := by
  unfold needBefore
  split
  · split
    · rw [text_keep]; rfl
    · rw [text_applyNeed]; rfl
  · rw [text_applyNeed]; rfl

theorem text_dropBlanks (ns : List Nat) (st : St) :
    text (ns.foldl (fun s _ => addUnmet .droppedBlank s) st) = text st := by
  induction ns generalizing st with
  | nil => rfl
  | cons n ns ih => simp only [List.foldl]; rw [ih, text_addUnmet]

theorem text_placeBlank (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    text (placeBlank env st f rest) = text st := by
  unfold placeBlank
  split
  · rfl
  · simp only
    have h1 : text (if startsRecto f = true then parityStart env odd st else st) = text st := by
      split
      · exact text_parityStart env odd st
      · rfl
    apply text_ite
    · rw [text_dropBlanks]; show text (keep env _ _) = _; rw [text_keep]; exact h1
    · show text (keep env _ _) = _; rw [text_keep]; exact h1

theorem text_putLine (env : Env) (st : St) (l : Line) :
    text (putLine env st l) = text st ++ [.line l.id] := by
  simp [text, putLine, putLineKeeping, textSlots_append, textSlots]

theorem text_putLines (env : Env) (ls : List Line) (st : St) :
    text (ls.foldl (putLine env) st) = text st ++ ls.map (fun l => .line l.id) := by
  induction ls generalizing st with
  | nil => simp
  | cons l ls ih => simp only [List.foldl, List.map]; rw [ih, text_putLine]; simp

theorem text_putBlock (env : Env) (st : St) (n : Nat) (ls : List Line) :
    text (putBlock env st n ls) = text st ++ flowText (.heading false n ls) := by
  cases ls with
  | nil => simp [putBlock, flowText]
  | cons l0 ls => simp [putBlock, flowText, text, textSlots_append, textSlots]

theorem text_shortParts (us : List Unmet) (st : St) :
    text (us.foldl (fun s u => addUnmet u s) st) = text st := by
  induction us generalizing st with
  | nil => rfl
  | cons u us ih => simp only [List.foldl]; rw [ih, text_addUnmet]

theorem text_placeLinesGo (env : Env) (pid : Nat) (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) :
    text (placeLinesGo env pid kp st isStart ls) = text st ++ ls.map (fun l => .line l.id) := by
  match ls with
  | [] => simp [placeLinesGo]
  | l :: ls' =>
    by_cases h1 : st.adjust < 0 ∧ isEmpty st = true ∧ env.roomForLine st (l :: ls') = false
    · unfold placeLinesGo; rw [dif_pos h1, text_placeLinesGo env pid kp (nextColumn env st), text_nextColumn]
    · by_cases h2 : kp.all = true ∧ isStart = true ∧ env.fitting st (l :: ls') < (l :: ls').length
      · by_cases h3 : isEmpty st = true ∨ st.headingOnly = true
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_pos h3]
          rw [text_placeLinesGo env pid { kp with all := false } (addUnmet (.splitKept pid) st), text_addUnmet]
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_neg h3]
          rw [text_placeLinesGo env pid kp (nextColumn env st), text_nextColumn]
      · by_cases h4 : (l :: ls').length ≤ (lineCount env kp st isStart (l :: ls')).1
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_pos h4, text_putLines]
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_neg h4]
          rw [text_placeLinesGo env pid kp _ _ ((l :: ls').drop (lineCount env kp st isStart (l :: ls')).1)]
          rw [text_nextColumn, text_shortParts, text_putLines, List.append_assoc, ← List.map_append,
            List.take_append_drop]
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

theorem text_placeLines (env : Env) (kp : Keep) (st : St) (isStart : Bool) (ls : List Line) :
    text (placeLines env kp st isStart ls) = text st ++ ls.map (fun l => .line l.id) := by
  cases ls with
  | nil => simp [placeLines]
  | cons l ls => exact text_placeLinesGo ..

theorem flowText_heading (recto : Bool) (n : Nat) (ls : List Line) :
    flowText (.heading recto n ls) = flowText (.heading false n ls) := by
  cases ls <;> rfl

theorem text_place (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    text (place env st f rest) = text st ++ flowText f := by
  cases f with
  | paragraph kp ls => exact text_placeLines ..
  | continued kp ls => exact text_placeLines ..
  | heading recto n ls =>
    simp only [place]
    rw [text_putBlock, flowText_heading recto]
    congr 1
    apply text_ite
    · apply text_ite
      · exact text_parityStart ..
      · exact text_keep ..
    · rw [text_nextColumn]
      apply text_ite
      · exact text_parityStart ..
      · exact text_keep ..
  | figure i n =>
    simp only [place, flowText, List.append_nil]
    apply text_ite
    · rfl
    · apply text_ite
      · exact text_putSlot_figure ..
      · rfl
  | pageFigure i =>
    simp only [place, flowText, List.append_nil]
    apply text_ite
    · rw [text_pageFigure]; rfl
    · rfl
  | brk k => simp only [place, flowText, List.append_nil]; rfl
  | space n => simp only [place, flowText, List.append_nil]; exact text_placeSpaceFlow ..
  | needLines n => simp [place, flowText]
  | blank n => simp [place, flowText]

theorem text_step (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    text (step env st f rest) = text st ++ flowText f := by
  have general : ∀ (a : Bool) (b : List (Nat × Int)), text ({ (if waitsBehind (applyBreaks env st) f then place env (applyBreaks env st) f rest
      else place env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest)
      with seen := true, lastDeferred := a, spaces := b } : St) = text st ++ flowText f := by
    intro _ _
    show text (if waitsBehind (applyBreaks env st) f then place env (applyBreaks env st) f rest
      else place env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest) = _
    apply text_ite
    · rw [text_place, text_applyBreaks]
    · rw [text_place, text_placeBlank, text_needBefore, text_applyBreaks]
  cases f with
  | needLines n => simp only [step, flowText, List.append_nil]; exact text_needMore ..
  | blank n =>
    simp only [step, flowText, List.append_nil]
    apply text_ite <;> rfl
  | brk k => simp only [step]; exact text_place ..
  | space n =>
    simp only [step, flowText, List.append_nil]
    rw [text_placeSpace, text_needBeforeSpaces, text_applyBreaks]
  | paragraph kp ls => simp only [step]; exact general _ _
  | continued kp ls => simp only [step]; exact general _ _
  | heading recto n ls => simp only [step]; exact general _ _
  | figure i n => simp only [step]; exact general _ _
  | pageFigure i => simp only [step]; exact general _ _

theorem text_placeAll (env : Env) (flows : List Flow) (st : St) :
    text (placeAll env st flows) = text st ++ sourceText flows := by
  induction flows generalizing st with
  | nil =>
    simp only [placeAll, sourceText, List.bind, List.join, List.map, List.append_nil]
    apply text_ite
    · rw [text_flushDeferred]; rfl
    · apply text_ite
      · rw [text_flushDeferred, text_dropBlanks]; rfl
      · rw [text_flushDeferred, text_dropBlanks, text_nextColumn]; rfl
  | cons f rest ih =>
    simp only [placeAll]
    rw [ih, text_step]
    simp [sourceText, List.cons_bind, List.append_assoc]

/-- Root ADR 0352 invariant 5 for the lines: the pages of the pagination
    hold every line of the paragraphs and every heading written, each
    once, in the order written. -/
theorem I5_paginate_text (env : Env) (flows : List Flow) :
    pagesText (paginate env flows).done = sourceText flows := by
  have h := text_placeAll env flows initialState
  have i : text initialState = [] := rfl
  rw [i, List.nil_append] at h
  simp only [paginate, closePage]
  generalize placeAll env initialState flows = st at h
  split
  · rename_i e
    have s : st.slots = [] := by
      cases c : st.slots with
      | nil => rfl
      | cons _ _ => simp [c, List.isEmpty] at e
    simp only [text, s, textSlots, List.append_nil] at h
    exact h
  · rw [pagesText_cons]; exact h

end WholePagination
