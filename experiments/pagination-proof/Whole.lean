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
  /-- A code block (`FCode`): its geometry, the grid lines of its
      caption, the rows of its first part at least, whether a part
      before the last has a row for the text it continues, its rows. -/
  | code (geometry caption first : Nat) (continued : Bool) (rows : List Line)
  /-- A term of a definition list (`FDefTerm`). -/
  | defTerm (lines : List Line)
  /-- A table (`FTable`): the grid lines of space before it, its header
      row, its body rows, its caption and whether the caption is below. -/
  | table (space : Nat) (header : List Line) (rows : List (List Line)) (caption : List Line) (below : Bool)
  deriving DecidableEq, Repr

inductive Slot where
  | line (id : Nat)
  | heading (id count : Nat)
  | figure (id : Nat)
  | pageFigure (id : Nat)
  /-- A part of a code block (`SCode`), by the rows in it. -/
  | code (rows : List Nat)
  /-- A row of a code block, as the text of a page lists it. -/
  | codeRow (id : Nat)
  /-- A line of the header of a table repeated in a column gone on to,
      without its notes: not a line of the text. -/
  | repeated (id : Nat)
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
  /-- `codeSpan` of Paginate/Types.hs: the grid lines of a part of a
      code block of the geometry and the rows given. -/
  codeSpan : Nat → Nat → Nat
  /-- `envKeepParts env == KeepColumn`: the parts are kept in a column,
      not across a page or a spread. -/
  keepColumn : Bool
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

/-! ## Code blocks (`placeCode` of Paginate.hs) -/

/-- `spanOf` of `placeCode`: the grid lines of a part of `j` rows. -/
def codeSpanOf (env : Env) (g cap0 : Nat) (cont isFirst : Bool) (len j : Nat) : Nat :=
  (if isFirst then cap0 else 0) + env.codeSpan g (j + (if cont ∧ j < len then 1 else 0))

/-- `k` of `placeCode`: the rows placed in the column. -/
def codeCount (env : Env) (g cap0 first : Nat) (cont : Bool) (st : St) (isFirst : Bool) (len : Nat) : Nat :=
  let least := if isFirst then min len (max 1 first) else 1
  let k0 := ((List.range len).takeWhile
    (fun j => decide ((codeSpanOf env g cap0 cont isFirst len (j + 1) : Int) ≤ free env st))).length
  if least ≤ k0 then k0 else if isEmpty st then least else 0

/-- A code block of rows goes on to the next column without a row only
    from a column with something in it. -/
theorem codeCount_zero (env : Env) (g cap0 first : Nat) (cont : Bool) (st : St) (isFirst : Bool) (len : Nat)
    (hl : 0 < len) (h : codeCount env g cap0 first cont st isFirst len = 0) : isEmpty st = false := by
  simp only [codeCount] at h
  have least : 1 ≤ (if isFirst then min len (max 1 first) else 1) := by
    split
    · exact Nat.le_min.mpr ⟨hl, Nat.le_max_left ..⟩
    · exact Nat.le_refl 1
  revert h least
  generalize (if isFirst then min len (max 1 first) else 1) = least
  intro h least
  split at h
  · omega
  · split at h
    · omega
    · rename_i e; cases c : isEmpty st
      · rfl
      · exact absurd c e

set_option linter.unusedVariables false in
def placeCode (env : Env) (g cap0 first : Nat) (cont : Bool) : St → Bool → List Line → St
  | st, _, [] => st
  | st, isFirst, l0 :: ls' =>
    if h : codeCount env g cap0 first cont st isFirst (l0 :: ls').length = 0 then
      placeCode env g cap0 first cont (nextColumn env st) isFirst (l0 :: ls')
    else
      let k := codeCount env g cap0 first cont st isFirst (l0 :: ls').length
      let st1 := putSlot st (codeSpanOf env g cap0 cont isFirst (l0 :: ls').length k)
        (.code (((l0 :: ls').take k).map (·.id)))
      if (l0 :: ls').drop k = [] then st1
      else placeCode env g cap0 first cont (nextColumn env st1) false ((l0 :: ls').drop k)
termination_by st _ ls => (ls.length, rank env st)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.right _ (I4_nextColumn_rank env st
      (Or.inl (codeCount_zero env g cap0 first cont st isFirst _ (by simp) h)))
  · apply Prod.Lex.left
    simp only [List.length, Nat.succ_eq_add_one] at *
    omega

/-! ## Tables (`placeTable` and `placeTableAcross` of Paginate.hs) -/

/-- A line of the header repeated: `putLine` of the line without its
    notes, labels and marks, recorded as a slot of its own. -/
def putRepeated (st : St) (l : Line) : St :=
  { st with slots := st.slots ++ [(st.used, .repeated l.id)], used := st.used + 1, headingOnly := false }

theorem putRepeateds_used (ls : List Line) (st : St) :
    (ls.foldl putRepeated st).used = st.used + ls.length := by
  induction ls generalizing st with
  | nil => simp
  | cons l ls ih => simp only [List.foldl]; rw [ih]; simp [putRepeated]; omega

/-- `tableHead` of Decide.hs: the header, the first row and the caption
    kept with them. -/
def tableHead (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) : Nat :=
  h.length + (match rows with | [] => 0 | r :: _ => r.length)
    + (if below = false ∨ rows.length ≤ 1 then capt.length else 0)

/-- The row with the caption below it when it is the last one
    (`withCaption` of `placeTable`). -/
def withCaption (capt : List Line) (below : Bool) (r : List Line) (rest : List (List Line)) : List Line :=
  if below = true ∧ rest = [] then r ++ capt else r

set_option linter.unusedVariables false in
/-- `rowsFrom` of `placeTable`: the rows of a table, each whole, from the
    grid line `first` of the part of the table in the column.  A row
    that does not fit goes on with the header repeated, and the row
    after a repeated header is placed: the second recursion therefore
    places a row. -/
def tableRowsGo (env : Env) (h capt : List Line) (below : Bool) : St → Int → List (List Line) → St
  | stc, _, [] => stc
  | stc, first, r :: rest =>
    if h1 : (withCaption capt below r rest).length ≤ env.fitting stc (withCaption capt below r rest)
        ∨ stc.used = first + h.length then
      tableRowsGo env h capt below (r.foldl (putLine env) stc) first rest
    else
      let fresh := keep env (nextColumn env stc)
        (fun _ => (h.length + (withCaption capt below r rest).length : Int))
      tableRowsGo env h capt below (h.foldl putRepeated fresh) fresh.used (r :: rest)
termination_by stc first rows => (rows.length, if stc.used = first + h.length then 0 else 1)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
    have : ¬ stc.used = first + h.length := fun e => h1 (Or.inr e)
    simp only [putRepeateds_used, this, ite_true, ite_false]
    decide

/-- `placeTable` of Paginate.hs (`KeepColumn`); the table segments it
    records are not modelled. -/
def placeTable (env : Env) (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    St :=
  let st0 := if below then st else capt.foldl (putLine env) st
  let st1 := h.foldl (putLine env) st0
  let placed := tableRowsGo env h capt below st1 st0.used rows
  if below then capt.foldl (putLine env) placed else placed

/-- `groups` of `placeTableAcross`: the caption above, the header, the
    rows and the caption below; `true` marks the header. -/
def tableGroups (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    List (Bool × List Line) :=
  (if below = false ∧ capt ≠ [] then [(false, capt)] else []) ++ (if h = [] then [] else [(true, h)])
    ++ rows.map (fun r => (false, r)) ++ (if below = true ∧ capt ≠ [] then [(false, capt)] else [])

/-- `mustRepeat` of `placeTableAcross`. -/
def mustRepeat (h : List Line) (fresh here : St) (isHeader retried : Bool) : Bool :=
  decide (fresh.page ≠ here.page) && !isHeader && !retried && !h.isEmpty

set_option linter.unusedVariables false in
/-- `go` and `placeGroup` of `placeTableAcross` of Paginate.hs, outside a
    book part (`envBookPartSpan` is `Nothing`): each group whole in a
    column, or in an empty column; the header repeated once on a page
    gone on to. -/
def acrossGo (env : Env) (h : List Line) : Bool → St → List (Bool × List Line) → St
  | _, st, [] => st
  | retried, here, (isHeader, ls) :: remaining =>
    if h1 : ls.length ≤ env.fitting here ls ∨ isEmpty here = true then
      acrossGo env h false (ls.foldl (putLine env) here) remaining
    else
      acrossGo env h (retried || mustRepeat h (nextColumn env here) here isHeader retried)
        (if mustRepeat h (nextColumn env here) here isHeader retried
          then h.foldl putRepeated (nextColumn env here) else nextColumn env here)
        ((isHeader, ls) :: remaining)
termination_by retried here gs => (gs.length, if retried then 0 else 1, rank env here)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
    have ne : isEmpty here = false := by
      cases e : isEmpty here
      · rfl
      · exact absurd (Or.inr e) h1
    cases m : mustRepeat h (nextColumn env here) here isHeader retried
    · simp only [Bool.or_false, ite_false, or_false]
      exact Prod.Lex.right _ (I4_nextColumn_rank env here (Or.inl ne))
    · have r : retried = false := by
        cases retried
        · rfl
        · simp [mustRepeat] at m
      subst r
      exact Prod.Lex.left _ _ (by simp)

def placeTableAcross (env : Env) (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line)
    (below : Bool) : St :=
  acrossGo env h false st (tableGroups h rows capt below)

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
  | .code g cap0 first cont ls => placeCode env g cap0 first cont st true ls
  | .defTerm ls =>
    if env.keepColumn then
      placeLines env defaultKeep
        (keep env st (fun s => needIn env s ⟨ls.length, noteLinesOf ls⟩ (env.nextNeed rest))) true ls
    else placeLines env ⟨1, 1, false⟩ st true ls
  | .table sp0 h rows capt below =>
    if env.keepColumn then
      let sp : Int := if st.used = top st then 0 else sp0
      let headed : Int := tableHead h rows capt below
      let st1 := if sp + headed ≤ free env st ∨ isEmpty st = true then { st with used := st.used + min sp (free env st) }
        else keep env (nextColumn env st) (fun _ => headed)
      placeTable env st1 h rows capt below
    else
      let space : Int := if st.used = top st then 0 else sp0
      let started := if space ≤ free env st then { st with used := st.used + space } else nextColumn env st
      placeTableAcross env started h rows capt below

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
  | (_, .code rows) :: r => rows.map Slot.codeRow ++ textSlots r
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

/-- The lines of a table, in the order written. -/
def tableLines (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) : List Line :=
  (if below then [] else capt) ++ h ++ rows.join ++ (if below then capt else [])

/-- The lines and headings of the flows written. -/
def flowText : Flow → List Slot
  | .paragraph _ ls => ls.map (fun l => .line l.id)
  | .continued _ ls => ls.map (fun l => .line l.id)
  | .defTerm ls => ls.map (fun l => .line l.id)
  | .heading _ _ [] => []
  | .heading _ _ (l0 :: ls) => [.heading l0.id (ls.length + 1)]
  | .code _ _ _ _ ls => ls.map (fun l => .codeRow l.id)
  | .table _ h rows capt below => (tableLines h rows capt below).map (fun l => .line l.id)
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

theorem text_putSlot_code (st : St) (n : Nat) (rows : List Nat) :
    text (putSlot st n (.code rows)) = text st ++ rows.map Slot.codeRow := by
  simp [text, putSlot, textSlots_append, textSlots]

theorem text_placeCode (env : Env) (g cap0 first : Nat) (cont : Bool) (st : St) (isFirst : Bool)
    (ls : List Line) :
    text (placeCode env g cap0 first cont st isFirst ls) = text st ++ ls.map (fun l => .codeRow l.id) := by
  match ls with
  | [] => unfold placeCode; simp
  | l0 :: ls' =>
    by_cases h : codeCount env g cap0 first cont st isFirst (l0 :: ls').length = 0
    · unfold placeCode; rw [dif_pos h, text_placeCode env g cap0 first cont (nextColumn env st), text_nextColumn]
    · unfold placeCode; rw [dif_neg h]
      simp only
      generalize codeCount env g cap0 first cont st isFirst (l0 :: ls').length = k
      split
      · rename_i e
        rw [text_putSlot_code, List.map_map]
        congr 2
        have := List.take_append_drop k (l0 :: ls')
        rw [e, List.append_nil] at this
        exact this
      · rw [text_placeCode env g cap0 first cont _ false ((l0 :: ls').drop k), text_nextColumn,
          text_putSlot_code, List.map_map, List.append_assoc]
        congr 1
        rw [show (Slot.codeRow ∘ fun x : Line => x.id) = (fun l => Slot.codeRow l.id) from rfl,
          ← List.map_append, List.take_append_drop]
termination_by (ls.length, rank env st)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.right _ (I4_nextColumn_rank env st
      (Or.inl (codeCount_zero env g cap0 first cont st isFirst _ (by simp) h)))
  · apply Prod.Lex.left
    simp only [List.length, Nat.succ_eq_add_one] at *
    omega

theorem text_putRepeated (st : St) (l : Line) : text (putRepeated st l) = text st := by
  simp [text, putRepeated, textSlots_append, textSlots]

theorem text_putRepeateds (ls : List Line) (st : St) : text (ls.foldl putRepeated st) = text st := by
  induction ls generalizing st with
  | nil => rfl
  | cons l ls ih => simp only [List.foldl]; rw [ih, text_putRepeated]

theorem text_tableRowsGo (env : Env) (h capt : List Line) (below : Bool) (st : St) (first : Int)
    (rows : List (List Line)) :
    text (tableRowsGo env h capt below st first rows) = text st ++ rows.join.map (fun l => .line l.id) := by
  match rows with
  | [] => unfold tableRowsGo; simp
  | r :: rest =>
    by_cases h1 : (withCaption capt below r rest).length ≤ env.fitting st (withCaption capt below r rest)
        ∨ st.used = first + h.length
    · unfold tableRowsGo; rw [dif_pos h1, text_tableRowsGo env h capt below _ first rest, text_putLines]
      simp
    · unfold tableRowsGo; rw [dif_neg h1]
      simp only
      rw [text_tableRowsGo env h capt below _ _ (r :: rest), text_putRepeateds, text_keep, text_nextColumn]
termination_by (rows.length, if st.used = first + h.length then 0 else 1)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
    have : ¬ st.used = first + h.length := fun e => h1 (Or.inr e)
    simp only [putRepeateds_used, this, ite_true, ite_false]
    decide

theorem text_placeTable (env : Env) (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line)
    (below : Bool) :
    text (placeTable env st h rows capt below) = text st ++ (tableLines h rows capt below).map (fun l => .line l.id) := by
  cases below <;> simp [placeTable, tableLines, text_tableRowsGo, text_putLines]

theorem text_acrossGo (env : Env) (h : List Line) (retried : Bool) (st : St) (gs : List (Bool × List Line)) :
    text (acrossGo env h retried st gs) = text st ++ (gs.bind (·.2)).map (fun l => .line l.id) := by
  match gs with
  | [] => unfold acrossGo; simp
  | (isHeader, ls) :: remaining =>
    by_cases h1 : ls.length ≤ env.fitting st ls ∨ isEmpty st = true
    · unfold acrossGo; rw [dif_pos h1, text_acrossGo env h false _ remaining, text_putLines]
      simp
    · unfold acrossGo; rw [dif_neg h1]
      rw [text_acrossGo env h _ _ ((isHeader, ls) :: remaining)]
      congr 1
      split
      · rw [text_putRepeateds, text_nextColumn]
      · rw [text_nextColumn]
termination_by (gs.length, if retried then 0 else 1, rank env st)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
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

theorem join_append' {α : Type} (a b : List (List α)) : (a ++ b).join = a.join ++ b.join := by
  induction a with
  | nil => rfl
  | cons x xs ih => simp [List.join, ih]

theorem tableGroups_lines (h : List Line) (rows : List (List Line)) (capt : List Line) (below : Bool) :
    (tableGroups h rows capt below).bind (·.2) = tableLines h rows capt below := by
  have j : List.join (List.map ((fun x : Bool × List Line => x.snd) ∘ fun r => (false, r)) rows) = rows.join := by
    congr 1; induction rows with
    | nil => rfl
    | cons r rs ih => simp only [List.map]; rw [ih]; rfl
  cases below <;> cases h <;> cases capt <;> simp [tableGroups, tableLines, List.append_bind, List.bind, j, join_append']

theorem text_placeTableAcross (env : Env) (st : St) (h : List Line) (rows : List (List Line)) (capt : List Line)
    (below : Bool) :
    text (placeTableAcross env st h rows capt below)
      = text st ++ (tableLines h rows capt below).map (fun l => .line l.id) := by
  simp only [placeTableAcross]; rw [text_acrossGo, tableGroups_lines]

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
  | code g c first cont ls => exact text_placeCode ..
  | defTerm ls =>
    simp only [place]
    split
    · rw [text_placeLines, text_keep]; rfl
    · rw [text_placeLines]; rfl
  | table sp0 h rows capt below =>
    simp only [place, flowText]
    split
    · rw [text_placeTable]
      congr 1
      apply text_ite
      · rfl
      · rw [text_keep, text_nextColumn]
    · rw [text_placeTableAcross]
      congr 1
      apply text_ite
      · rfl
      · rw [text_nextColumn]

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
  | code g c first cont ls => simp only [step]; exact general _ _
  | defTerm ls => simp only [step]; exact general _ _
  | table sp0 h rows capt below => simp only [step]; exact general _ _

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
    hold every line of the paragraphs, the terms and the tables, every
    heading and every row of the code blocks written, each once, in the
    order written.  The header lines a table repeats in a column gone on
    to are slots of their own, not lines of the text. -/
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


/-! ## The figures are placed once, in the order written (invariant 5)

The figures of the model are the figures and the turned figures.  The
proof needs every figure to be at least one line high: a figure of no
lines leaves the column's lines used at 0, so a turned figure after it
is put on a page of its own before the column that holds the figure is
closed (README.md).  It also needs a capacity of 0 lines or more and a
footnote separator of 0 lines or more: the lines used become negative
only where a table in an empty column takes the negative room that its
footnote lines leave, and the footnote lines of a column never
decrease. -/

/-- The figures and turned figures of slots, in order. -/
def figSlots : List (Int × Slot) → List Slot
  | [] => []
  | (_, .figure i) :: r => .figure i :: figSlots r
  | (_, .pageFigure i) :: r => .pageFigure i :: figSlots r
  | _ :: r => figSlots r

theorem figSlots_append (a b : List (Int × Slot)) :
    figSlots (a ++ b) = figSlots a ++ figSlots b := by
  induction a with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨g, s⟩ := x
    cases s <;> simp [figSlots, ih]

def pagesFigs (done : List PageOut) : List Slot := done.reverse.bind (fun p => figSlots p.slots)

theorem pagesFigs_cons (p : PageOut) (done : List PageOut) :
    pagesFigs (p :: done) = pagesFigs done ++ figSlots p.slots := by
  simp [pagesFigs, List.reverse_cons, List.append_bind]

def deferredFig : Deferred → Slot
  | .figure i _ => .figure i
  | .pageFigure i => .pageFigure i

/-- The figures on the pages closed, then in the current column, then
    waiting. -/
def figs (st : St) : List Slot :=
  pagesFigs st.done ++ figSlots st.slots ++ st.deferred.map deferredFig

def flowFigs : Flow → List Slot
  | .figure i _ => [.figure i]
  | .pageFigure i => [.pageFigure i]
  | _ => []

def sourceFigs (flows : List Flow) : List Slot := flows.bind flowFigs

/-- Every figure waiting is at least one line high. -/
def deferredOk : List Deferred → Prop
  | [] => True
  | .figure _ n :: r => 1 ≤ n ∧ deferredOk r
  | .pageFigure _ :: r => deferredOk r

theorem deferredOk_append (a b : List Deferred) (ha : deferredOk a) (hb : deferredOk b) :
    deferredOk (a ++ b) := by
  induction a with
  | nil => exact hb
  | cons x xs ih =>
    cases x with
    | figure i n => exact ⟨ha.1, ih ha.2⟩
    | pageFigure i => exact ih ha

theorem deferredOk_spanTurned (d : List Deferred) (h : deferredOk d) : deferredOk (spanTurned d).2 := by
  induction d with
  | nil => exact h
  | cons x xs ih =>
    cases x with
    | figure i n => exact h
    | pageFigure i => exact ih h

/-- What holds of every state outside `needBeforeSpaces`. -/
structure Weak (st : St) : Prop where
  first : st.firstLine = 0
  deferred : deferredOk st.deferred
  adjust : 0 ≤ st.adjust

/-- The lines used are negative only below footnote lines, and a column
    that holds a figure has used a line or more or has footnote lines.
    A table in an empty column whose footnote lines leave no room takes
    the negative room left (`place` of `FTable`), so the lines used may
    be negative; the footnote lines of a column never decrease. -/
structure Inv (st : St) : Prop where
  weak : Weak st
  used : 0 ≤ st.used ∨ 0 < st.noteLines
  fig : figSlots st.slots = [] ∨ 1 ≤ st.used ∨ 0 < st.noteLines

/-- `a` comes before `b`: an earlier page, or an earlier column of the
    same page. -/
def posLt (a b : St) : Prop := a.page < b.page ∨ (a.page = b.page ∧ a.column < b.column)

theorem posLt_trans {a b c : St} (h1 : posLt a b) (h2 : posLt b c) : posLt a c := by
  simp only [posLt] at *; omega

/-- `r` keeps the column of `st` as it is. -/
def Same (st r : St) : Prop :=
  r.slots = st.slots ∧ r.used = st.used ∧ r.page = st.page ∧ r.column = st.column ∧ r.firstLine = st.firstLine
    ∧ r.deferred = st.deferred ∧ r.noteLines = st.noteLines ∧ r.adjust = st.adjust

theorem Same.trans' {a b c : St} (h1 : Same a b) (h2 : Same b c) : Same a c := by
  obtain ⟨a1, a2, a3, a4, a5, a6, a7, a8⟩ := h1
  obtain ⟨b1, b2, b3, b4, b5, b6, b7, b8⟩ := h2
  exact ⟨b1.trans a1, b2.trans a2, b3.trans a3, b4.trans a4, b5.trans a5, b6.trans a6, b7.trans a7, b8.trans a8⟩

theorem Same.weak {st r : St} (s : Same st r) (w : Weak st) : Weak r := by
  obtain ⟨_, _, _, _, a5, a6, _, a8⟩ := s
  exact ⟨a5.trans w.first, a6 ▸ w.deferred, a8 ▸ w.adjust⟩

theorem Same.inv {st r : St} (s : Same st r) (i : Inv st) : Inv r := by
  have w := s.weak i.weak
  obtain ⟨a1, a2, _, _, _, _, a7, _⟩ := s
  exact ⟨w, a2 ▸ a7 ▸ i.used, a1 ▸ a2 ▸ a7 ▸ i.fig⟩

theorem Same.page' {st r : St} (s : Same st r) : r.page = st.page := s.2.2.1
theorem Same.column' {st r : St} (s : Same st r) : r.column = st.column := s.2.2.2.1

/-- `r` keeps the column of `st` as it is, or is a valid state in a later
    column. -/
def Moves (st r : St) : Prop := Same st r ∨ (Inv r ∧ posLt st r)

theorem Moves.trans {a b c : St} (h1 : Moves a b) (h2 : Moves b c) : Moves a c := by
  rcases h1 with s1 | ⟨i1, p1⟩
  · rcases h2 with s2 | ⟨i2, p2⟩
    · exact Or.inl (s1.trans' s2)
    · right; refine ⟨i2, ?_⟩
      have := s1.page'; have := s1.column'
      simp only [posLt] at *; omega
  · rcases h2 with s2 | ⟨i2, p2⟩
    · right
      refine ⟨s2.inv i1, ?_⟩
      have := s2.page'; have := s2.column'
      simp only [posLt] at *; omega
    · exact Or.inr ⟨i2, posLt_trans p1 p2⟩

theorem Moves.inv {st r : St} (i : Inv st) (h : Moves st r) : Inv r := by
  rcases h with s | ⟨i2, _⟩
  · exact s.inv i
  · exact i2

/-! ### Going on to the next column keeps the figures and makes a valid state -/

theorem pageFigures_page (env : Env) (ts : List Nat) (st : St) :
    (ts.foldl (pageFigure env) st).page = st.page + ts.length ∧
      (ts.foldl (pageFigure env) st).slots = st.slots ∧
      pagesFigs (ts.foldl (pageFigure env) st).done = pagesFigs st.done ++ ts.map Slot.pageFigure := by
  induction ts generalizing st with
  | nil => simp
  | cons t ts ih =>
    simp only [List.foldl]
    obtain ⟨a, b, c⟩ := ih (pageFigure env st t)
    refine ⟨?_, ?_, ?_⟩
    · rw [a]; simp [pageFigure]; omega
    · rw [b]; rfl
    · rw [c]; simp [pageFigure, pagesFigs_cons, figSlots]

theorem carryNote_frame (env : Env) (st : St) (p : NotePart) :
    let r := carryNote env st p
    r.page = st.page ∧ r.slots = st.slots ∧ r.done = st.done ∧ r.used = st.used
      ∧ r.firstLine = st.firstLine := by
  simp only [carryNote, addUnmet]; split <;> exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem carryAll_frame (env : Env) (ps : List NotePart) (st : St) :
    let r := ps.foldl (carryNote env) st
    r.page = st.page ∧ r.slots = st.slots ∧ r.done = st.done ∧ r.used = st.used
      ∧ r.firstLine = st.firstLine := by
  induction ps generalizing st with
  | nil => exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  | cons p ps ih =>
    simp only [List.foldl]
    obtain ⟨a, b, c, d, e⟩ := ih (carryNote env st p)
    obtain ⟨a', b', c', d', e'⟩ := carryNote_frame env st p
    exact ⟨a.trans a', b.trans b', c.trans c', d.trans d', e.trans e'⟩

theorem placeDeferred_figs (env : Env) (ws : List Deferred) (st : St) (h : st.deferred = []) :
    let r := placeDeferred env st ws
    r.page = st.page ∧ r.done = st.done ∧
      figSlots r.slots ++ r.deferred.map deferredFig = figSlots st.slots ++ ws.map deferredFig := by
  induction ws generalizing st with
  | nil => simp [placeDeferred, h]
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · obtain ⟨a, b, c⟩ := ih (putSlot st n (.figure i)) h
        refine ⟨a, b, ?_⟩
        rw [c]; simp [putSlot, figSlots_append, figSlots, deferredFig]
      · simp
    | pageFigure i => simp [placeDeferred]

/-- Lines put in a column keep the lines used from becoming negative
    above no footnote lines, and a figure in it counted. -/
theorem inv_addUsed {st r : St} (h : Inv st) (w : Weak r) (n : Int) (hn : 0 ≤ n) (u : r.used = st.used + n)
    (nl : st.noteLines ≤ r.noteLines)
    (fs : figSlots r.slots = figSlots st.slots ∨ (1 ≤ n ∧ ∃ x, figSlots r.slots = figSlots st.slots ++ x)) : Inv r := by
  refine ⟨w, ?_, ?_⟩
  · rcases h.used with a | a
    · left; omega
    · right; omega
  · rcases fs with e | ⟨n1, _⟩
    · rw [e]
      rcases h.fig with a | a | a
      · exact Or.inl a
      · right; left; omega
      · right; right; omega
    · right
      rcases h.used with a | a
      · left; omega
      · right; omega

theorem putSlot_inv (st : St) (n i : Nat) (h : Inv st) (hn : 1 ≤ n) : Inv (putSlot st n (.figure i)) :=
  inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ n (by omega) rfl (Int.le_refl _)
    (Or.inr ⟨by omega, [.figure i], by simp [putSlot, figSlots_append, figSlots]⟩)

theorem placeDeferred_inv (env : Env) (ws : List Deferred) (st : St) (h : Inv st) (hw : deferredOk ws) :
    Inv (placeDeferred env st ws) := by
  induction ws generalizing st with
  | nil => exact h
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · exact ih _ (putSlot_inv st n i h hw.1) hw.2
      · exact ⟨⟨h.weak.first, hw, h.weak.adjust⟩, h.used, h.fig⟩
    | pageFigure i => exact ⟨⟨h.weak.first, hw, h.weak.adjust⟩, h.used, h.fig⟩

theorem spanTurned_figs (d : List Deferred) :
    (spanTurned d).1.map Slot.pageFigure ++ (spanTurned d).2.map deferredFig = d.map deferredFig := by
  induction d with
  | nil => rfl
  | cons x xs ih =>
    cases x with
    | figure i n => simp [spanTurned]
    | pageFigure i => simp [spanTurned, deferredFig]; exact ih

theorem advanceFresh_figs (env : Env) (b : Bool) (st : St) :
    let r := advanceFresh env b st
    pagesFigs r.done = pagesFigs st.done ++ figSlots st.slots ∧ r.slots = [] ∧ r.deferred = st.deferred
      ∧ r.page = (if b then st.page + 1 else st.page) ∧ r.used = (if b then 0 else st.firstLine)
      ∧ r.firstLine = (if b then 0 else st.firstLine) := by
  refine ⟨?_, rfl, ?_, rfl, rfl, rfl⟩
  · simp only [advanceFresh, closePage]
    by_cases e : st.slots.isEmpty = true ∧ st.notes.isEmpty = true
    · have s : st.slots = [] := by
        cases h : st.slots with
        | nil => rfl
        | cons _ _ => simp [h, List.isEmpty] at e
      simp only [e, and_self, ite_true]
      split <;> simp [pagesFigs_cons, figSlots, s]
    · simp only [e, ite_false]
      split <;> simp [pagesFigs_cons, figSlots]
  · simp only [advanceFresh, closePage]
    split <;> (try split) <;> rfl

theorem advance_figs (env : Env) (b : Bool) (st : St) : figs (advance env b st) = figs st := by
  simp only [advance, openColumn]
  obtain ⟨f1, f2, f3, _, _, _⟩ := advanceFresh_figs env b st
  generalize advanceFresh env b st = fr at f1 f2 f3
  obtain ⟨p1, p2, p3⟩ := pageFigures_page env (advanceTurned b st).1 fr
  generalize (advanceTurned b st).1.foldl (pageFigure env) fr = pf at p1 p2 p3
  obtain ⟨c1, c2, c3, _, _⟩ := carryAll_frame env st.pending pf
  generalize st.pending.foldl (carryNote env) pf = cn at c1 c2 c3
  obtain ⟨_, d2, d3⟩ := placeDeferred_figs env (advanceTurned b st).2 { cn with deferred := [] } rfl
  simp only [figs]
  rw [List.append_assoc, d3, d2]
  simp only [c2, c3, p2, f2, p3, f1, figSlots, List.append_nil, List.append_assoc]
  congr 2
  have : (advanceTurned b st).1.map Slot.pageFigure ++ (advanceTurned b st).2.map deferredFig
      = st.deferred.map deferredFig := by
    unfold advanceTurned; split
    · exact spanTurned_figs _
    · simp
  exact this

theorem advance_page (env : Env) (b : Bool) (st : St) :
    (advance env b st).page = (if b then st.page + 1 else st.page) + (advanceTurned b st).1.length := by
  simp only [advance, openColumn]
  obtain ⟨_, _, _, f4, _, _⟩ := advanceFresh_figs env b st
  generalize advanceFresh env b st = fr at f4
  obtain ⟨p1, _, _⟩ := pageFigures_page env (advanceTurned b st).1 fr
  generalize (advanceTurned b st).1.foldl (pageFigure env) fr = pg at p1
  obtain ⟨c1, _, _, _, _⟩ := carryAll_frame env st.pending pg
  generalize st.pending.foldl (carryNote env) pg = cn at c1
  obtain ⟨d1, _, _⟩ := placeDeferred_figs env (advanceTurned b st).2 { cn with deferred := [] } rfl
  rw [d1]; show cn.page = _; rw [c1, p1, f4]

theorem advance_posLt (env : Env) (b : Bool) (st : St) : posLt st (advance env b st) := by
  have p := advance_page env b st
  have c := advance_column env b st
  simp only [posLt, p, c]
  cases b with
  | true => left; simp; omega
  | false => right; simp [advanceTurned]

theorem advance_inv (env : Env) (b : Bool) (st : St) (w : Weak st) :
    Inv (advance env b st) ∧ posLt st (advance env b st) := by
  refine ⟨?_, advance_posLt env b st⟩
  simp only [advance, openColumn]
  obtain ⟨_, f2, _, _, f5, f6⟩ := advanceFresh_figs env b st
  have okTurned : deferredOk (advanceTurned b st).2 := by
    unfold advanceTurned; split
    · exact deferredOk_spanTurned _ w.deferred
    · exact w.deferred
  have fa : (advanceFresh env b st).adjust = 0 := rfl
  generalize advanceFresh env b st = fr at f2 f5 f6 fa
  obtain ⟨_, p2, _⟩ := pageFigures_page env (advanceTurned b st).1 fr
  have pf := pageFigures_fields env (advanceTurned b st).1 fr
  generalize (advanceTurned b st).1.foldl (pageFigure env) fr = pg at p2 pf
  obtain ⟨_, c2, _, c4, c5⟩ := carryAll_frame env st.pending pg
  have c6 := carryAll_adjust env st.pending pg
  generalize st.pending.foldl (carryNote env) pg = cn at c2 c4 c5 c6
  have base : Inv { cn with deferred := [] } := by
    refine ⟨⟨?_, trivial, ?_⟩, ?_, ?_⟩
    · show cn.firstLine = 0
      rw [c5, pf.2.2.2.2.2.1, f6]; have := w.first; split <;> simp [this]
    · show 0 ≤ cn.adjust
      rw [c6, pf.2.2.1, fa]; decide
    · left; show 0 ≤ cn.used
      rw [c4, pf.2.2.2.2.1, f5]; have := w.first; split <;> simp [this]
    · left; show figSlots cn.slots = []; rw [c2, p2, f2]; rfl
  exact placeDeferred_inv env _ _ base okTurned

theorem figs_nextColumn (env : Env) (st : St) : figs (nextColumn env st) = figs st := advance_figs ..
theorem figs_nextPage (env : Env) (st : St) : figs (nextPage env st) = figs st := advance_figs ..

theorem moves_nextColumn (env : Env) (st : St) (w : Weak st) : Moves st (nextColumn env st) :=
  Or.inr (advance_inv env _ st w)

theorem Inv.weak' {st : St} (h : Inv st) : Weak st := h.weak

/-- A state that keeps the column of `st` as it is. -/
theorem moves_same {st r : St} (s : Same st r) : Moves st r := Or.inl s

theorem moves_weak {st r : St} (w : Weak st) (m : Moves st r) : Weak r := by
  rcases m with s | ⟨i, _⟩
  · exact s.weak w
  · exact i.weak

/-! ### The loops and the breaks -/

theorem keep_moves (env : Env) (st : St) (need : St → Int) (w : Weak st) : Moves st (keep env st need) := by
  by_cases h : free env st < need st ∧ isEmpty st = false
  · unfold keep; rw [dif_pos h]
    have m := moves_nextColumn env st w
    exact m.trans (keep_moves env (nextColumn env st) need (moves_weak w m))
  · unfold keep; rw [dif_neg h]; exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
termination_by rank env st
decreasing_by exact I4_nextColumn_rank env st (Or.inl h.2)

theorem figs_keep (env : Env) (st : St) (need : St → Int) : figs (keep env st need) = figs st := by
  by_cases h : free env st < need st ∧ isEmpty st = false
  · unfold keep; rw [dif_pos h, figs_keep env (nextColumn env st) need, figs_nextColumn]
  · unfold keep; rw [dif_neg h]
termination_by rank env st
decreasing_by exact I4_nextColumn_rank env st (Or.inl h.2)

theorem inv_nextColumn (env : Env) (st : St) (h : Inv st) : Inv (nextColumn env st) :=
  (advance_inv env _ st h.weak).1

theorem inv_nextPage (env : Env) (st : St) (h : Inv st) : Inv (nextPage env st) :=
  (advance_inv env _ st h.weak).1

theorem inv_keep (env : Env) (st : St) (need : St → Int) (h : Inv st) : Inv (keep env st need) :=
  (keep_moves env st need h.weak).inv h

theorem flushDeferred_figs (env : Env) (st : St) (h : Inv st) :
    figs (flushDeferred env st) = figs st ∧ Inv (flushDeferred env st) ∧ (flushDeferred env st).deferred = [] := by
  by_cases c : st.deferred = [] ∧ st.pending = []
  · unfold flushDeferred; rw [dif_pos c]; exact ⟨rfl, h, c.1⟩
  · unfold flushDeferred; rw [dif_neg c]
    have := flushDeferred_figs env (nextColumn env st) (inv_nextColumn env st h)
    rw [figs_nextColumn] at this
    exact this
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st c)

theorem figs_blankPage (env : Env) (st : St) : figs (blankPage env st) = figs st := by
  simp [figs, blankPage, pagesFigs_cons, figSlots]

theorem inv_blankPage (env : Env) (st : St) (h : Inv st) : Inv (blankPage env st) :=
  ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩

theorem parityStart_figs (env : Env) (p : Nat → Bool) (st : St) (h : Inv st) :
    figs (parityStart env p st) = figs st ∧ Inv (parityStart env p st) := by
  obtain ⟨f, i, _⟩ := flushDeferred_figs env st h
  simp only [parityStart]
  generalize flushDeferred env st = s0 at f i
  have h1 : figs (if isEmpty s0 = true ∧ s0.column = 0 then s0 else nextPage env s0) = figs st ∧
      Inv (if isEmpty s0 = true ∧ s0.column = 0 then s0 else nextPage env s0) := by
    split
    · exact ⟨f, i⟩
    · exact ⟨(figs_nextPage env s0).trans f, inv_nextPage env s0 i⟩
  generalize (if isEmpty s0 = true ∧ s0.column = 0 then s0 else nextPage env s0) = s1 at h1
  split
  · exact h1
  · exact ⟨(figs_blankPage env s1).trans h1.1, inv_blankPage env s1 h1.2⟩

theorem breakPage_figs (env : Env) (st : St) (h : Inv st) :
    figs (breakPage env st) = figs st ∧ Inv (breakPage env st) := by
  simp only [breakPage]
  split
  · exact ⟨figs_blankPage env st, inv_blankPage env st h⟩
  · split
    · exact ⟨rfl, h⟩
    · exact ⟨figs_nextPage env st, inv_nextPage env st h⟩

theorem applyBreaks_figs (env : Env) (st : St) (h : Inv st) :
    figs (applyBreaks env st) = figs st ∧ Inv (applyBreaks env st) := by
  simp only [applyBreaks]
  suffices ∀ (ks : List BreakKind) (s : St), Inv s →
      figs (ks.foldl (applyBreakKind env) s) = figs s ∧ Inv (ks.foldl (applyBreakKind env) s) by
    exact this _ _ ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩
  intro ks
  induction ks with
  | nil => intro s i; exact ⟨rfl, i⟩
  | cons k ks ih =>
    intro s i
    simp only [List.foldl]
    have one : figs (applyBreakKind env s k) = figs s ∧ Inv (applyBreakKind env s k) := by
      cases k with
      | page => exact breakPage_figs env s i
      | recto => exact parityStart_figs env odd s i
      | verso => exact parityStart_figs env even s i
      | column =>
        simp only [applyBreakKind]
        split
        · exact ⟨figs_nextColumn env s, inv_nextColumn env s i⟩
        · exact breakPage_figs env s i
    have := ih _ one.2
    exact ⟨this.1.trans one.1, this.2⟩

/-! ### Need-lines and spaces -/

theorem applyNeed_moves (env : Env) (st : St) (w : Weak st) : Moves st (applyNeed env st) := by
  unfold applyNeed
  split
  · exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  · split
    · dsimp only; split
      · exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
      · exact moves_nextColumn env _ ⟨w.first, w.deferred, w.adjust⟩
    · exact keep_moves env _ _ ⟨w.first, w.deferred, w.adjust⟩

theorem figs_applyNeed (env : Env) (st : St) : figs (applyNeed env st) = figs st := by
  unfold applyNeed
  split
  · rfl
  · split
    · dsimp only; split
      · rfl
      · rw [figs_nextColumn]; rfl
    · rw [figs_keep]; rfl

theorem needBeforeSpace_moves (env : Env) (st : St) (w : Weak st) : Moves st (needBeforeSpace env st) := by
  unfold needBeforeSpace
  split
  · exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  · split
    · exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
    · split
      · exact applyNeed_moves env _ ⟨w.first, w.deferred, w.adjust⟩
      · have m := applyNeed_moves env { st with needAt := none } ⟨w.first, w.deferred, w.adjust⟩
        rcases m with sm | ⟨i, p⟩
        · exact moves_same sm
        · exact Or.inr ⟨⟨⟨i.weak.first, i.weak.deferred, i.weak.adjust⟩, i.used, i.fig⟩, p⟩

theorem figs_needBeforeSpace (env : Env) (st : St) : figs (needBeforeSpace env st) = figs st := by
  unfold needBeforeSpace
  split
  · rfl
  · repeat' split
    all_goals first | rfl | (rw [figs_applyNeed]; rfl) | (show figs (applyNeed env _) = _; rw [figs_applyNeed]; rfl)

theorem inv_placeSpaceFlow (env : Env) (st : St) (n : Nat) (h : Inv st) : Inv (placeSpaceFlow env st n) := by
  unfold placeSpaceFlow; split
  · exact h
  · exact inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ _ (Int.le_max_left ..) rfl
      (Int.le_refl _) (Or.inl rfl)

theorem inv_placeSpace (env : Env) (st : St) (n : Nat) (h : Inv st) : Inv (placeSpace env st n) := by
  have i := inv_placeSpaceFlow env st n h
  exact ⟨⟨i.weak.first, i.weak.deferred, i.weak.adjust⟩, i.used, i.fig⟩

theorem inv_placeSpaces (env : Env) (ns : List Nat) (st : St) (h : Inv st) :
    Inv (ns.foldl (placeSpace env) st) := by
  induction ns generalizing st with
  | nil => exact h
  | cons n _ ih => exact ih _ (inv_placeSpace env st n h)

theorem figs_placeSpaces (env : Env) (ns : List Nat) (st : St) :
    figs (ns.foldl (placeSpace env) st) = figs st := by
  induction ns generalizing st with
  | nil => rfl
  | cons n ns ih =>
    simp only [List.foldl]; rw [ih]
    show figs (placeSpaceFlow env st n) = _
    unfold placeSpaceFlow; split <;> rfl

/-- `needBeforeSpaces` takes the spaces out of the lines used for a
    while.  If the column stays, the lines used come back as they were;
    otherwise the state is the valid state of a later column. -/
theorem inv_needBeforeSpaces (env : Env) (st : St) (h : Inv st) : Inv (needBeforeSpaces env st) := by
  unfold needBeforeSpaces
  generalize (st.spaces.map (·.2)).foldr (· + ·) 0 = k
  have m := needBeforeSpace_moves env { st with used := st.used - k } ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩
  simp only
  generalize needBeforeSpace env { st with used := st.used - k } = st1 at m
  split
  · rename_i e
    rcases m with ⟨s1, s2, _, _, s5, s6, s7, s8⟩ | ⟨_, p⟩
    · have u : st1.used + k = st.used := by rw [s2]; show st.used - k + k = st.used; omega
      refine ⟨⟨?_, ?_, ?_⟩, ?_, ?_⟩
      · show st1.firstLine = 0; rw [s5]; exact h.weak.first
      · show deferredOk st1.deferred; rw [s6]; exact h.weak.deferred
      · show 0 ≤ st1.adjust; rw [s8]; exact h.weak.adjust
      · show 0 ≤ st1.used + k ∨ 0 < st1.noteLines; rw [u, s7]; exact h.used
      · show figSlots st1.slots = [] ∨ 1 ≤ st1.used + k ∨ 0 < st1.noteLines; rw [u, s1, s7]; exact h.fig
    · exfalso; simp only [posLt] at p; omega
  · rename_i e
    rcases m with ⟨_, _, s3, s4, _, _, _, _⟩ | ⟨i, _⟩
    · exact absurd ⟨s3, s4⟩ e
    · exact inv_placeSpaces env _ st1 i

theorem figs_needBeforeSpaces (env : Env) (st : St) : figs (needBeforeSpaces env st) = figs st := by
  unfold needBeforeSpaces
  simp only
  split
  · show figs (needBeforeSpace env _) = figs st
    rw [figs_needBeforeSpace]; rfl
  · rw [figs_placeSpaces, figs_needBeforeSpace]; rfl

theorem needAfterSpaces_figs (env : Env) (st : St) (h : Inv st) :
    figs (needAfterSpaces env st) = figs st ∧ Inv (needAfterSpaces env st) := by
  unfold needAfterSpaces; split
  · exact ⟨rfl, h⟩
  · exact ⟨figs_needBeforeSpaces env st, inv_needBeforeSpaces env st h⟩

theorem needMore_figs (env : Env) (n : Nat) (st : St) (h : Inv st) :
    figs (needMore env n st) = figs st ∧ Inv (needMore env n st) := by
  have h' : ∀ a b, Inv { st with need := a, needAt := b } :=
    fun _ _ => ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩
  unfold needMore
  split
  · split
    · exact ⟨rfl, h⟩
    · exact needAfterSpaces_figs env _ (h' _ _)
  · exact needAfterSpaces_figs env _ (h' _ _)

theorem needBefore_figs (env : Env) (st : St) (flows : List Flow) (h : Inv st) :
    figs (needBefore env st flows) = figs st ∧ Inv (needBefore env st flows) := by
  have w : ∀ a b, Weak { st with need := a, needAt := b } := fun _ _ => ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩
  have i : ∀ a b, Inv { st with need := a, needAt := b } :=
    fun _ _ => ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩
  have i' : Inv { st with needAt := none } := ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩
  unfold needBefore
  split
  · split
    · exact ⟨by rw [figs_keep]; rfl, (keep_moves env _ _ (w _ _)).inv (i _ _)⟩
    · exact ⟨by rw [figs_applyNeed]; rfl, (applyNeed_moves env _ i'.weak).inv i'⟩
  · exact ⟨by rw [figs_applyNeed]; rfl, (applyNeed_moves env _ i'.weak).inv i'⟩

/-! ### Blank lines -/

theorem total_nonneg (c : Int) (hc : 0 ≤ c) (ns : List Nat) (a : Int) (ha : 0 ≤ a) :
    0 ≤ ns.foldl (fun a (n : Nat) => min c (a + min c (n : Int))) a := by
  induction ns generalizing a with
  | nil => exact ha
  | cons n _ ih =>
    apply ih
    have : 0 ≤ min c (n : Int) := Int.le_min.mpr ⟨hc, Int.ofNat_nonneg n⟩
    exact Int.le_min.mpr ⟨hc, by omega⟩

theorem dropBlanks_figs (ns : List Nat) (st : St) (h : Inv st) :
    figs (ns.foldl (fun s _ => addUnmet .droppedBlank s) st) = figs st ∧
      Inv (ns.foldl (fun s _ => addUnmet .droppedBlank s) st) := by
  induction ns generalizing st with
  | nil => exact ⟨rfl, h⟩
  | cons _ _ ih => exact ih (addUnmet .droppedBlank st) ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩

theorem blankTail (total : Int) (ht : 0 ≤ total) (blanks : List Nat) (s2 : St) (X : List Slot)
    (h : Inv s2) (f : figs s2 = X) :
    figs (if s2.used = top s2 then blanks.foldl (fun s _ => addUnmet .droppedBlank s) { s2 with blank := [] }
      else { s2 with used := s2.used + total, blank := [] }) = X ∧
    Inv (if s2.used = top s2 then blanks.foldl (fun s _ => addUnmet .droppedBlank s) { s2 with blank := [] }
      else { s2 with used := s2.used + total, blank := [] }) := by
  split
  · have := dropBlanks_figs blanks { s2 with blank := [] } ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩
    exact ⟨this.1.trans f, this.2⟩
  · exact ⟨f, inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ total ht rfl (Int.le_refl _)
      (Or.inl rfl)⟩

theorem placeBlank_figs (env : Env) (hc : 0 ≤ env.capacity) (st : St) (f : Flow) (rest : List Flow)
    (h : Inv st) : figs (placeBlank env st f rest) = figs st ∧ Inv (placeBlank env st f rest) := by
  unfold placeBlank
  split
  · exact ⟨rfl, h⟩
  · dsimp only
    have h1 : figs (if startsRecto f = true then parityStart env odd st else st) = figs st ∧
        Inv (if startsRecto f = true then parityStart env odd st else st) := by
      split
      · exact parityStart_figs env odd st h
      · exact ⟨rfl, h⟩
    generalize (if startsRecto f = true then parityStart env odd st else st) = s1 at h1
    apply blankTail
    · exact total_nonneg _ hc _ 0 (Int.le_refl 0)
    · exact inv_keep env s1 _ h1.2
    · rw [figs_keep]; exact h1.1

/-! ### Lines and headings -/

/-- With a separator of no negative lines, the footnote lines of a column
    never decrease. -/
theorem putLine_noteLines (env : Env) (hs : 0 ≤ env.separator) (st : St) (l : Line) :
    st.noteLines ≤ (putLine env st l).noteLines := by
  simp only [putLine, putLineKeeping]
  have : (0 : Int) ≤ (partsLines (splitNotes (cap env st - st.used - 1 - 0 - st.noteLines
    - (if st.noteLines = 0 ∧ 0 < (List.foldr (· + ·) 0 (List.map (·.lines) l.notes)) then env.separator else 0))
    l.notes).1 : Int) := Int.ofNat_nonneg _
  split <;> split <;> omega

theorem putLine_figs (env : Env) (hs : 0 ≤ env.separator) (st : St) (l : Line) (h : Inv st) :
    figs (putLine env st l) = figs st ∧ Inv (putLine env st l) := by
  refine ⟨by simp [figs, putLine, putLineKeeping, figSlots_append, figSlots], ?_⟩
  exact inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ 1 (by decide) rfl
    (putLine_noteLines env hs st l) (Or.inl (by simp [putLine, putLineKeeping, figSlots_append, figSlots]))

theorem putLines_figs (env : Env) (hs : 0 ≤ env.separator) (ls : List Line) (st : St) (h : Inv st) :
    figs (ls.foldl (putLine env) st) = figs st ∧ Inv (ls.foldl (putLine env) st) := by
  induction ls generalizing st with
  | nil => exact ⟨rfl, h⟩
  | cons l ls ih =>
    simp only [List.foldl]
    have one := putLine_figs env hs st l h
    have := ih _ one.2
    exact ⟨this.1.trans one.1, this.2⟩

theorem putBlock_figs (env : Env) (hs : 0 ≤ env.separator) (st : St) (n : Nat) (ls : List Line) (h : Inv st) :
    figs (putBlock env st n ls) = figs st ∧ Inv (putBlock env st n ls) := by
  cases ls with
  | nil => exact ⟨rfl, h⟩
  | cons l0 ls =>
    refine ⟨by simp [figs, putBlock, figSlots_append, figSlots], ?_⟩
    have nl : st.noteLines ≤ (putBlock env st n (l0 :: ls)).noteLines := by
      simp only [putBlock]
      generalize (splitNotes _ _).1 = sh
      have : (0 : Int) ≤ (partsLines sh : Int) := Int.ofNat_nonneg _
      split <;> (try split) <;> omega
    exact inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ n (Int.ofNat_nonneg n) rfl nl
      (Or.inl (by simp [putBlock, figSlots_append, figSlots]))

theorem shortParts_figs (us : List Unmet) (st : St) (h : Inv st) :
    figs (us.foldl (fun s u => addUnmet u s) st) = figs st ∧ Inv (us.foldl (fun s u => addUnmet u s) st) := by
  induction us generalizing st with
  | nil => exact ⟨rfl, h⟩
  | cons u _ ih => exact ih (addUnmet u st) ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩

theorem placeLinesGo_figs (env : Env) (hs : 0 ≤ env.separator) (pid : Nat) (kp : Keep) (st : St) (isStart : Bool)
    (ls : List Line) (h : Inv st) :
    figs (placeLinesGo env pid kp st isStart ls) = figs st ∧ Inv (placeLinesGo env pid kp st isStart ls) := by
  match ls with
  | [] => unfold placeLinesGo; exact ⟨rfl, h⟩
  | l :: ls' =>
    by_cases h1 : st.adjust < 0 ∧ isEmpty st = true ∧ env.roomForLine st (l :: ls') = false
    · unfold placeLinesGo; rw [dif_pos h1]
      have := placeLinesGo_figs env hs pid kp (nextColumn env st) isStart (l :: ls') (inv_nextColumn env st h)
      rw [figs_nextColumn] at this; exact this
    · by_cases h2 : kp.all = true ∧ isStart = true ∧ env.fitting st (l :: ls') < (l :: ls').length
      · by_cases h3 : isEmpty st = true ∨ st.headingOnly = true
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_pos h3]
          exact placeLinesGo_figs env hs pid { kp with all := false } (addUnmet (.splitKept pid) st) isStart
            (l :: ls') ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩
        · unfold placeLinesGo; rw [dif_neg h1, dif_pos h2, dif_neg h3]
          have := placeLinesGo_figs env hs pid kp (nextColumn env st) isStart (l :: ls') (inv_nextColumn env st h)
          rw [figs_nextColumn] at this; exact this
      · by_cases h4 : (l :: ls').length ≤ (lineCount env kp st isStart (l :: ls')).1
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_pos h4]; exact putLines_figs env hs _ st h
        · unfold placeLinesGo; rw [dif_neg h1, dif_neg h2]
          rw [dif_neg h4]
          have p := putLines_figs env hs ((l :: ls').take (lineCount env kp st isStart (l :: ls')).1) st h
          have s := shortParts_figs (shortParts kp pid (lineCount env kp st isStart (l :: ls')).2 isStart
            (l :: ls').length (lineCount env kp st isStart (l :: ls')).1) _ p.2
          have := placeLinesGo_figs env hs pid kp _ (isStart && (lineCount env kp st isStart (l :: ls')).1 == 0)
            ((l :: ls').drop (lineCount env kp st isStart (l :: ls')).1) (inv_nextColumn env _ s.2)
          rw [figs_nextColumn, s.1, p.1] at this
          exact this
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

theorem putSlot_code_figs (st : St) (n : Nat) (rows : List Nat) (h : Inv st) :
    figs (putSlot st n (.code rows)) = figs st ∧ Inv (putSlot st n (.code rows)) := by
  refine ⟨by simp [figs, putSlot, figSlots_append, figSlots], ?_⟩
  exact inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ n (Int.ofNat_nonneg n) rfl (Int.le_refl _)
    (Or.inl (by simp [putSlot, figSlots_append, figSlots]))

theorem placeCode_figs (env : Env) (g cap0 first : Nat) (cont : Bool) (st : St) (isFirst : Bool)
    (h : Inv st) (ls : List Line) :
    figs (placeCode env g cap0 first cont st isFirst ls) = figs st ∧
      Inv (placeCode env g cap0 first cont st isFirst ls) := by
  match ls with
  | [] => unfold placeCode; exact ⟨rfl, h⟩
  | l0 :: ls' =>
    by_cases c : codeCount env g cap0 first cont st isFirst (l0 :: ls').length = 0
    · unfold placeCode; rw [dif_pos c]
      have := placeCode_figs env g cap0 first cont (nextColumn env st) isFirst
        (inv_nextColumn env st h) (l0 :: ls')
      rw [figs_nextColumn] at this; exact this
    · unfold placeCode; rw [dif_neg c]
      simp only
      generalize codeCount env g cap0 first cont st isFirst (l0 :: ls').length = k
      have p := putSlot_code_figs st (codeSpanOf env g cap0 cont isFirst (l0 :: ls').length k)
        (((l0 :: ls').take k).map (·.id)) h
      split
      · exact p
      · have := placeCode_figs env g cap0 first cont _ false (inv_nextColumn env _ p.2) ((l0 :: ls').drop k)
        rw [figs_nextColumn, p.1] at this; exact this
termination_by (ls.length, rank env st)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.right _ (I4_nextColumn_rank env st
      (Or.inl (codeCount_zero env g cap0 first cont st isFirst _ (by simp) c)))
  · apply Prod.Lex.left
    simp only [List.length, Nat.succ_eq_add_one] at *
    omega

theorem placeLines_figs (env : Env) (hs : 0 ≤ env.separator) (kp : Keep) (st : St) (isStart : Bool) (ls : List Line)
    (h : Inv st) :
    figs (placeLines env kp st isStart ls) = figs st ∧ Inv (placeLines env kp st isStart ls) := by
  cases ls with
  | nil => exact ⟨rfl, h⟩
  | cons l ls => exact placeLinesGo_figs env hs _ kp st isStart _ h

/-! ### One flow and the whole -/

/-- A figure flow is at least one line high. -/
def figureOk : Flow → Prop
  | .figure _ n => 1 ≤ n
  | _ => True

theorem isEmpty_nil {α : Type} (l : List α) (h : l.isEmpty = true) : l = [] := by
  cases l with
  | nil => rfl
  | cons _ _ => simp [List.isEmpty] at h

theorem defer_figs (st : St) (d : Deferred) (h : Inv st) (hd : deferredOk [d]) :
    figs { st with deferred := st.deferred ++ [d] } = figs st ++ [deferredFig d] ∧
      Inv { st with deferred := st.deferred ++ [d] } :=
  ⟨by simp [figs, List.map_append],
    ⟨⟨h.weak.first, deferredOk_append _ _ h.weak.deferred hd, h.weak.adjust⟩, h.used, h.fig⟩⟩

/-! ### Tables -/

theorem putRepeated_figs (st : St) (l : Line) (h : Inv st) :
    figs (putRepeated st l) = figs st ∧ Inv (putRepeated st l) :=
  ⟨by simp [figs, putRepeated, figSlots_append, figSlots],
    inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ 1 (by decide) rfl (Int.le_refl _)
      (Or.inl (by simp [putRepeated, figSlots_append, figSlots]))⟩

theorem putRepeateds_figs (ls : List Line) (st : St) (h : Inv st) :
    figs (ls.foldl putRepeated st) = figs st ∧ Inv (ls.foldl putRepeated st) := by
  induction ls generalizing st with
  | nil => exact ⟨rfl, h⟩
  | cons l ls ih =>
    simp only [List.foldl]
    have one := putRepeated_figs st l h
    have := ih _ one.2
    exact ⟨this.1.trans one.1, this.2⟩

theorem tableRowsGo_figs (env : Env) (hs : 0 ≤ env.separator) (h capt : List Line) (below : Bool) (st : St)
    (first : Int) (rows : List (List Line)) (hi : Inv st) :
    figs (tableRowsGo env h capt below st first rows) = figs st ∧ Inv (tableRowsGo env h capt below st first rows) := by
  match rows with
  | [] => unfold tableRowsGo; exact ⟨rfl, hi⟩
  | r :: rest =>
    by_cases h1 : (withCaption capt below r rest).length ≤ env.fitting st (withCaption capt below r rest)
        ∨ st.used = first + h.length
    · unfold tableRowsGo; rw [dif_pos h1]
      have p := putLines_figs env hs r st hi
      have := tableRowsGo_figs env hs h capt below _ first rest p.2
      rw [p.1] at this; exact this
    · unfold tableRowsGo; rw [dif_neg h1]
      simp only
      have k := inv_keep env (nextColumn env st)
        (fun _ => (h.length + (withCaption capt below r rest).length : Int)) (inv_nextColumn env st hi)
      have fk := figs_keep env (nextColumn env st) (fun _ => (h.length + (withCaption capt below r rest).length : Int))
      rw [figs_nextColumn] at fk
      generalize keep env (nextColumn env st) (fun _ => (h.length + (withCaption capt below r rest).length : Int))
        = fresh at k fk ⊢
      have p := putRepeateds_figs h fresh k
      have := tableRowsGo_figs env hs h capt below (h.foldl putRepeated fresh) fresh.used (r :: rest) p.2
      rw [p.1, fk] at this; exact this
termination_by (rows.length, if st.used = first + h.length then 0 else 1)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
    have : ¬ st.used = first + h.length := fun e => h1 (Or.inr e)
    simp only [putRepeateds_used, this, ite_true, ite_false]
    decide

theorem placeTable_figs (env : Env) (hs : 0 ≤ env.separator) (st : St) (h : List Line) (rows : List (List Line))
    (capt : List Line) (below : Bool) (hi : Inv st) :
    figs (placeTable env st h rows capt below) = figs st ∧ Inv (placeTable env st h rows capt below) := by
  simp only [placeTable]
  have p0 : figs (if below = true then st else capt.foldl (putLine env) st) = figs st ∧
      Inv (if below = true then st else capt.foldl (putLine env) st) := by
    split
    · exact ⟨rfl, hi⟩
    · exact putLines_figs env hs capt st hi
  generalize (if below = true then st else capt.foldl (putLine env) st) = s0 at p0
  have p1 := putLines_figs env hs h s0 p0.2
  have p2 := tableRowsGo_figs env hs h capt below _ s0.used rows p1.2
  rw [p1.1, p0.1] at p2
  generalize tableRowsGo env h capt below (h.foldl (putLine env) s0) s0.used rows = s2 at p2
  split
  · have p3 := putLines_figs env hs capt s2 p2.2
    exact ⟨p3.1.trans p2.1, p3.2⟩
  · exact p2

theorem acrossGo_figs (env : Env) (hs : 0 ≤ env.separator) (h : List Line) (retried : Bool) (st : St)
    (gs : List (Bool × List Line)) (hi : Inv st) :
    figs (acrossGo env h retried st gs) = figs st ∧ Inv (acrossGo env h retried st gs) := by
  match gs with
  | [] => unfold acrossGo; exact ⟨rfl, hi⟩
  | (isHeader, ls) :: remaining =>
    by_cases h1 : ls.length ≤ env.fitting st ls ∨ isEmpty st = true
    · unfold acrossGo; rw [dif_pos h1]
      have p := putLines_figs env hs ls st hi
      have := acrossGo_figs env hs h false _ remaining p.2
      rw [p.1] at this; exact this
    · unfold acrossGo; rw [dif_neg h1]
      have n := inv_nextColumn env st hi
      have q : figs (if mustRepeat h (nextColumn env st) st isHeader retried = true
            then h.foldl putRepeated (nextColumn env st) else nextColumn env st) = figs st ∧
          Inv (if mustRepeat h (nextColumn env st) st isHeader retried = true
            then h.foldl putRepeated (nextColumn env st) else nextColumn env st) := by
        split
        · have := putRepeateds_figs h _ n
          rw [figs_nextColumn] at this; exact this
        · exact ⟨figs_nextColumn env st, n⟩
      have := acrossGo_figs env hs h (retried || mustRepeat h (nextColumn env st) st isHeader retried) _
        ((isHeader, ls) :: remaining) q.2
      rw [q.1] at this; exact this
termination_by (gs.length, if retried then 0 else 1, rank env st)
decreasing_by
  all_goals simp_wf
  · exact Prod.Lex.left _ _ (Nat.lt_succ_self _)
  · apply Prod.Lex.right
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

/-- The space before a table in `KeepColumn`: in an empty column whose
    footnote lines leave no room, the lines used drop by the room
    missing, so they are negative only below footnote lines. -/
theorem tableStart_inv (env : Env) (hc : 0 ≤ env.capacity) (st : St) (h : Inv st) (sp headed : Int)
    (hsp : 0 ≤ sp) (hh : 0 ≤ headed) (c : sp + headed ≤ free env st ∨ isEmpty st = true) :
    Inv { st with used := st.used + min sp (free env st) } := by
  by_cases d : 0 ≤ min sp (free env st)
  · exact inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ _ d rfl (Int.le_refl _) (Or.inl rfl)
  · have m : min sp (free env st) = free env st := by
      rw [Int.min_def]; split
      · omega
      · rfl
    have e : isEmpty st = true := by
      rcases c with c | c
      · omega
      · exact c
    have u0 : st.used = 0 := by
      have := h.weak.first
      simp [isEmpty, top] at e
      omega
    have fr : free env st = env.capacity + st.adjust - st.used - st.noteLines := rfl
    have a := h.weak.adjust
    refine ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, ?_, ?_⟩
    · show 0 ≤ st.used + min sp (free env st) ∨ 0 < st.noteLines
      rw [m]; omega
    · show figSlots st.slots = [] ∨ 1 ≤ st.used + min sp (free env st) ∨ 0 < st.noteLines
      rcases h.fig with g | g | g
      · exact Or.inl g
      · omega
      · exact Or.inr (Or.inr g)

theorem place_figs (env : Env) (hc : 0 ≤ env.capacity) (hs : 0 ≤ env.separator) (st : St) (f : Flow)
    (rest : List Flow) (h : Inv st) (hf : figureOk f) :
    figs (place env st f rest) = figs st ++ flowFigs f ∧ Inv (place env st f rest) := by
  cases f with
  | paragraph kp ls => simp only [flowFigs, List.append_nil]; exact placeLines_figs env hs kp st true ls h
  | continued kp ls => simp only [flowFigs, List.append_nil]; exact placeLines_figs env hs kp st false ls h
  | heading recto n ls =>
    simp only [place, flowFigs, List.append_nil]
    have h1 : figs (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) = figs st ∧
        Inv (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) := by
      split
      · exact parityStart_figs env odd st h
      · exact ⟨figs_keep .., inv_keep env st _ h⟩
    generalize (if recto = true then parityStart env odd st
        else keep env st (fun s => needIn env s ⟨n, noteLinesOf ls⟩ (env.nextNeed rest))) = s1 at h1
    have h2 : figs (if headingNeed env s1 n ls ≤ free env s1 ∨ isEmpty s1 = true then s1 else nextColumn env s1)
        = figs st ∧
        Inv (if headingNeed env s1 n ls ≤ free env s1 ∨ isEmpty s1 = true then s1 else nextColumn env s1) := by
      split
      · exact h1
      · exact ⟨(figs_nextColumn env s1).trans h1.1, inv_nextColumn env s1 h1.2⟩
    generalize (if headingNeed env s1 n ls ≤ free env s1 ∨ isEmpty s1 = true then s1 else nextColumn env s1)
      = s2 at h2
    have := putBlock_figs env hs s2 n ls h2.2
    exact ⟨this.1.trans h2.1, this.2⟩
  | figure i n =>
    simp only [place, flowFigs]
    split
    · exact defer_figs st _ h ⟨hf, trivial⟩
    · rename_i d
      have d0 : st.deferred = [] := isEmpty_nil _ (by simpa using d)
      split
      · refine ⟨?_, putSlot_inv st n i h hf⟩
        simp [figs, putSlot, figSlots_append, figSlots, d0]
      · exact defer_figs st _ h ⟨hf, trivial⟩
  | pageFigure i =>
    simp only [place, flowFigs]
    split
    · rename_i c
      have d0 : st.deferred = [] := isEmpty_nil _ c.1
      have s0 : figSlots st.slots = [] := by
        rcases h.fig with g | g | g
        · exact g
        · have := c.2.2.1; omega
        · have := c.2.2.2.2; omega
      refine ⟨?_, ⟨⟨h.weak.first, h.weak.deferred, Int.le_refl 0⟩, h.used, h.fig⟩⟩
      simp [figs, pageFigure, pagesFigs_cons, figSlots, d0, s0]
    · exact defer_figs st _ h trivial
  | brk k => exact ⟨by simp [place, figs, flowFigs], ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩⟩
  | space n =>
    simp only [place, flowFigs, List.append_nil]
    refine ⟨?_, inv_placeSpaceFlow env st n h⟩
    unfold placeSpaceFlow; split <;> rfl
  | needLines n => exact ⟨by simp [place, flowFigs], h⟩
  | blank n => exact ⟨by simp [place, flowFigs], h⟩
  | code g c first cont ls =>
    simp only [place, flowFigs, List.append_nil]; exact placeCode_figs env g c first cont st true h ls
  | defTerm ls =>
    simp only [place, flowFigs, List.append_nil]
    split
    · have k := inv_keep env st (fun s => needIn env s ⟨ls.length, noteLinesOf ls⟩ (env.nextNeed rest)) h
      have := placeLines_figs env hs defaultKeep _ true ls k
      rw [figs_keep] at this; exact this
    · exact placeLines_figs env hs _ st true ls h
  | table sp0 hd rows capt below =>
    simp only [place, flowFigs, List.append_nil]
    have sp0' : (0 : Int) ≤ sp0 := Int.ofNat_nonneg sp0
    have hsp : (0 : Int) ≤ (if st.used = top st then 0 else (sp0 : Int)) := by split <;> omega
    generalize (if st.used = top st then 0 else (sp0 : Int)) = sp at hsp ⊢
    by_cases kc : env.keepColumn = true
    · rw [if_pos kc]
      have s1 : figs (if sp + (tableHead hd rows capt below : Int) ≤ free env st ∨ isEmpty st = true
            then { st with used := st.used + min sp (free env st) }
            else keep env (nextColumn env st) (fun _ => (tableHead hd rows capt below : Int))) = figs st ∧
          Inv (if sp + (tableHead hd rows capt below : Int) ≤ free env st ∨ isEmpty st = true
            then { st with used := st.used + min sp (free env st) }
            else keep env (nextColumn env st) (fun _ => (tableHead hd rows capt below : Int))) := by
        split
        · rename_i c
          exact ⟨rfl, tableStart_inv env hc st h _ _ hsp (Int.ofNat_nonneg _) c⟩
        · exact ⟨by rw [figs_keep, figs_nextColumn], inv_keep env _ _ (inv_nextColumn env st h)⟩
      have := placeTable_figs env hs _ hd rows capt below s1.2
      rw [s1.1] at this; exact this
    · rw [if_neg kc]
      have s1 : figs (if sp ≤ free env st then { st with used := st.used + sp } else nextColumn env st) = figs st ∧
          Inv (if sp ≤ free env st then { st with used := st.used + sp } else nextColumn env st) := by
        split
        · exact ⟨rfl, inv_addUsed h ⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩ _ hsp rfl (Int.le_refl _)
            (Or.inl rfl)⟩
        · exact ⟨figs_nextColumn env st, inv_nextColumn env st h⟩
      have := acrossGo_figs env hs hd false _ (tableGroups hd rows capt below) s1.2
      rw [s1.1] at this; exact this

theorem step_figs (env : Env) (hc : 0 ≤ env.capacity) (hs : 0 ≤ env.separator) (st : St) (f : Flow) (rest : List Flow)
    (h : Inv st) (hf : figureOk f) :
    figs (step env st f rest) = figs st ++ flowFigs f ∧ Inv (step env st f rest) := by
  have b := applyBreaks_figs env st h
  have general : ∀ (a : Bool) (sp : List (Nat × Int)),
      let r : St := if waitsBehind (applyBreaks env st) f then place env (applyBreaks env st) f rest
        else place env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest
      figs { r with seen := true, lastDeferred := a, spaces := sp } = figs st ++ flowFigs f ∧
        Inv { r with seen := true, lastDeferred := a, spaces := sp } := by
    intro a sp
    have core : figs (if waitsBehind (applyBreaks env st) f then place env (applyBreaks env st) f rest
        else place env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest)
        = figs st ++ flowFigs f ∧
        Inv (if waitsBehind (applyBreaks env st) f then place env (applyBreaks env st) f rest
        else place env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest) := by
      split
      · have p := place_figs env hc hs _ f rest b.2 hf
        rw [b.1] at p; exact p
      · have n := needBefore_figs env (applyBreaks env st) (f :: rest) b.2
        have k := placeBlank_figs env hc _ f rest n.2
        have p := place_figs env hc hs _ f rest k.2 hf
        rw [k.1, n.1, b.1] at p; exact p
    exact ⟨core.1, ⟨⟨core.2.weak.first, core.2.weak.deferred, core.2.weak.adjust⟩, core.2.used, core.2.fig⟩⟩
  cases f with
  | needLines n => simp only [step, flowFigs, List.append_nil]; exact needMore_figs env n st h
  | blank n =>
    simp only [step, flowFigs, List.append_nil]
    split
    · exact ⟨rfl, h⟩
    · exact ⟨rfl, ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩⟩
  | brk k => simp only [step]; exact place_figs env hc hs st _ rest h hf
  | space n =>
    simp only [step, flowFigs, List.append_nil]
    have s := inv_needBeforeSpaces env _ b.2
    refine ⟨?_, inv_placeSpace env _ n s⟩
    show figs (placeSpaceFlow env _ n) = _
    have : figs (placeSpaceFlow env (needBeforeSpaces env (applyBreaks env st)) n)
        = figs (needBeforeSpaces env (applyBreaks env st)) := by
      unfold placeSpaceFlow; split <;> rfl
    rw [this, figs_needBeforeSpaces, b.1]
  | paragraph kp ls => simp only [step]; exact general _ _
  | continued kp ls => simp only [step]; exact general _ _
  | heading recto n ls => simp only [step]; exact general _ _
  | figure i n => simp only [step]; exact general _ _
  | pageFigure i => simp only [step]; exact general _ _
  | code g c first cont ls => simp only [step]; exact general _ _
  | defTerm ls => simp only [step]; exact general _ _
  | table sp0 h rows capt below => simp only [step]; exact general _ _

theorem placeAll_figs (env : Env) (hc : 0 ≤ env.capacity) (hs : 0 ≤ env.separator) (flows : List Flow) (st : St) (h : Inv st)
    (hf : ∀ f ∈ flows, figureOk f) :
    figs (placeAll env st flows) = figs st ++ sourceFigs flows ∧ (placeAll env st flows).deferred = [] := by
  induction flows generalizing st with
  | nil =>
    simp only [placeAll, sourceFigs, List.bind, List.join, List.map, List.append_nil]
    have h2 : Inv { st with breaks := [], need := none, needAt := none, blank := [] } :=
      ⟨⟨h.weak.first, h.weak.deferred, h.weak.adjust⟩, h.used, h.fig⟩
    split
    · obtain ⟨a, _, c⟩ := flushDeferred_figs env _ h2; exact ⟨a, c⟩
    · split
      · have d := dropBlanks_figs st.blank _ h2
        obtain ⟨a, _, c⟩ := flushDeferred_figs env _ d.2; exact ⟨a.trans d.1, c⟩
      · have d := dropBlanks_figs st.blank _ (inv_nextColumn env _ h2)
        obtain ⟨a, _, c⟩ := flushDeferred_figs env _ d.2
        refine ⟨?_, c⟩
        rw [a, d.1, figs_nextColumn]; rfl
  | cons f rest ih =>
    simp only [placeAll]
    have s := step_figs env hc hs st f rest h (hf f (List.mem_cons_self f rest))
    have := ih (step env st f rest) s.2 (fun g m => hf g (List.mem_cons_of_mem f m))
    refine ⟨?_, this.2⟩
    rw [this.1, s.1]
    simp [sourceFigs, List.cons_bind, List.append_assoc]

/-- Root ADR 0352 invariant 5 for the figures: the pages of the
    pagination hold every figure and turned figure written, each once,
    in the order written.  It assumes that every figure is at least one
    line high, that a column holds 0 lines or more and that the footnote
    separator takes 0 lines or more (golem-layout clamps it to 1 line or
    more); README.md shows the input that breaks the order with a figure
    of no lines. -/
theorem I5_paginate_figures (env : Env) (hc : 0 ≤ env.capacity) (hs : 0 ≤ env.separator) (flows : List Flow)
    (hf : ∀ f ∈ flows, figureOk f) :
    pagesFigs (paginate env flows).done = sourceFigs flows := by
  have i : Inv initialState := ⟨⟨rfl, trivial, by decide⟩, Or.inl (by decide), Or.inl rfl⟩
  obtain ⟨h, d⟩ := placeAll_figs env hc hs flows initialState i hf
  have e : figs initialState = [] := rfl
  rw [e, List.nil_append] at h
  simp only [paginate, closePage]
  generalize placeAll env initialState flows = st at h d
  simp only [figs, d, List.map, List.append_nil] at h
  split
  · rename_i c
    have s : st.slots = [] := isEmpty_nil _ c.1
    simp only [s, figSlots, List.append_nil] at h
    exact h
  · rw [pagesFigs_cons]; exact h
end WholePagination
