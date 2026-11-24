/-
Root ADR 0352, the free placement of root ADR 0397: the pagination of
modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs as a state
machine over integer sp.

One Lean definition stands for one Haskell function, for the flows listed
in `Flow` below.  README.md lists the correspondence with file:line and
what the model leaves out.  Every definition is total: the column loops
(`placeLines`, `judgeNeed`, `placeRuled`, `drainCarry`) are defined by
well-founded recursion, so Lean checks that each ends on every input.

`firstNeed` of Physical.hs, which only measures the flows ahead, is a
parameter of `Env`: the theorems hold for every choice of it.  The rule
geometry of FreeGeometry.hs is copied, only the extra lengths that move
the position in the column; the placed rules are not modelled.
-/
namespace PhysicalPagination

inductive BreakKind where
  | column | page | recto | verso
  deriving DecidableEq, Repr

structure Note where
  id : Nat
  lines : Nat
  deriving DecidableEq, Repr

/-- `LineBox` without its labels and marks. -/
structure Line where
  id : Nat
  notes : List Note
  overhang : Int
  deriving DecidableEq, Repr

structure Keep where
  first : Nat
  last : Nat
  all : Bool
  deriving DecidableEq, Repr

def defaultKeep : Keep := ⟨2, 2, false⟩

/-- `RuleSide` of RuleArea.hs. -/
structure RuleSide where
  inner : Int
  outer : Int
  weight : Int
  spaced : Bool
  outside : Option Int
  deriving DecidableEq, Repr

/-- `FRuled` with a `RuledLines` body. -/
structure Ruled where
  id : Nat
  before : Option RuleSide
  after : Option RuleSide
  joined : Bool
  nextOverhang : Int
  keep : Keep
  lines : List Line
  deriving DecidableEq, Repr

inductive Flow where
  | paragraph (k : Keep) (ls : List Line)
  | continued (k : Keep) (ls : List Line)
  | figure (id : Nat) (extent : Int)
  | pageFigure (id : Nat)
  | space (n : Int)
  | blank (n : Nat)
  | brk (k : BreakKind)
  | needLines (n : Nat)
  | adjustLines (n : Int)
  | noBreak
  | noBreakLines (n : Nat)
  | keepNext (n : Nat)
  | ruled (r : Ruled)
  deriving DecidableEq, Repr

inductive Slot where
  | line (id : Nat)
  | figure (id : Nat)
  | pageFigure (id : Nat)
  deriving DecidableEq, Repr

inductive AdjustLimit where
  | noRoom | linesPlaced | oneLine
  deriving DecidableEq, Repr

inductive Unmet where
  | noBreak
  | keepNext
  | needLines (n : Nat)
  | adjust (chosen : Int) (why : AdjustLimit)
  | droppedBlank
  | splitKept (id : Nat)
  /-- `ShortPart`: the first part (true) or the last, the first line,
      the lines asked for and the lines placed. -/
  | shortPart (firstPart : Bool) (id : Nat) (wanted placed : Nat)
  deriving DecidableEq, Repr

inductive Failure where
  | lineTooTall (id : Nat)
  | footnoteTooTall (id : Nat)
  | figureTooTall (id : Nat)
  deriving DecidableEq, Repr

/-- A note part: the note, the first line shown, the lines. -/
abbrev NotePart := Nat × Nat × Nat

structure PageOut where
  number : Nat
  column : Nat
  blank : Bool
  slots : List (Int × Slot)
  notes : List NotePart
  limit : Int
  unmet : List Unmet
  deriving DecidableEq, Repr

/-- A keep waiting for the flows after it (`psWaits`): the unmet, the
    page, the column, the slots before it, the lines asked for and
    whether only lines count. -/
abbrev Wait := Unmet × Nat × Nat × Nat × Nat × Bool

/-- `PhysicalState` of Physical.hs without labels, marks, table and box
    segments, placed rules and sections, which only decorate the output. -/
structure St where
  page : Nat
  column : Nat
  /-- `csColumns (psSet st)` and `csFirstLine (psSet st)`. -/
  columns : Nat
  firstLine : Int
  used : Int
  notesUsed : Int
  slots : List (Int × Slot)
  notes : List NotePart
  carry : List NotePart
  deferred : List (Nat × Int)
  done : List PageOut
  adjust : Int
  unmet : List Unmet
  pending : Int
  blankActive : Bool
  /-- `psBlankSpans`: one span for each blank of more than 0 lines. -/
  blankSpans : Nat
  /-- `psJoin`: the block, its rule after, its last line, the extra. -/
  join : Option (Nat × RuleSide × Line × Int)
  waits : List Wait

/-- `PhysicalSettings` without the maps the flows of the model do not
    read; the pitch and the face of a line are functions of its id. -/
structure Env where
  pagePitch : Int
  fontSize : Int
  capacity : Int
  maxCapacity : Int
  separator : Int
  columns : Nat
  firstLine : Int
  pitchOf : Nat → Int
  faceOf : Nat → Int
  /-- `firstNeed` of Physical.hs: the length the flows ahead need. -/
  firstNeed : Bool → Nat → List Flow → Int

def initial (env : Env) : St :=
  ⟨1, 0, env.columns, env.firstLine, 0, 0, [], [], [], [], [], 0, [], 0, false, 0, none, []⟩

def limit (env : Env) (st : St) : Int := env.capacity + st.adjust
def room (env : Env) (st : St) : Int := limit env st - st.used - st.notesUsed
def empty (st : St) : Bool := st.slots.isEmpty && st.notes.isEmpty && st.used == st.firstLine
def addUnmet (u : Unmet) (st : St) : St := { st with unmet := st.unmet ++ [u] }

def close (env : Env) (st : St) : St :=
  if st.slots.isEmpty ∧ st.notes.isEmpty then st
  else { st with done := ⟨st.page, st.column, false, st.slots, st.notes, limit env st, st.unmet⟩ :: st.done, unmet := [] }

def putSlot (st : St) (extent : Int) (s : Slot) : St :=
  { st with slots := st.slots ++ [(st.used, s)], used := st.used + extent }

/-- The loop of `placeDeferred`. -/
def placeDeferredGo (env : Env) (st : St) : List (Nat × Int) → St
  | [] => { st with deferred := [] }
  | (i, e) :: later =>
    if e ≤ room env st then placeDeferredGo env (putSlot st e (.figure i)) later
    else { st with deferred := (i, e) :: later }

def placeDeferred (env : Env) (st : St) : St := placeDeferredGo env st st.deferred

def partsLines (ps : List NotePart) : Nat := ps.foldr (fun p a => p.2.2 + a) 0

def splitCarried : Nat → List NotePart → List NotePart × List NotePart
  | _, [] => ([], [])
  | 0, all => ([], all)
  | r + 1, (i, o, c) :: rest =>
    if c ≤ r + 1 then
      let p := splitCarried (r + 1 - c) rest
      ((i, o, c) :: p.1, p.2)
    else ([(i, o, r + 1)], (i, o + (r + 1), c - (r + 1)) :: rest)

def carryInto (env : Env) (st : St) : St :=
  if st.carry.isEmpty then st
  else
    let available := limit env st - st.used - env.separator
    let count := (max 0 (Int.fdiv available env.pagePitch)).toNat
    let p := splitCarried count st.carry
    let extent := env.separator + (partsLines p.1 : Int) * env.pagePitch
    { st with notes := p.1, carry := p.2, notesUsed := if p.1.isEmpty then 0 else extent }

/-- The column closed and the next one opened (`fresh` of `nextColumn`,
    and of `nextPage` when `toPage`). -/
def fresh (env : Env) (toPage : Bool) (st : St) : St :=
  let closed := close env st
  let pageEnd := toPage || decide (st.columns ≤ st.column + 1)
  let first := if pageEnd then 0 else st.firstLine
  { closed with
    page := if pageEnd then st.page + 1 else st.page
    column := if pageEnd then 0 else st.column + 1
    firstLine := first
    used := first
    notesUsed := 0
    slots := []
    notes := []
    adjust := 0
    pending := 0
    blankActive := false
    join := none }

def nextColumn (env : Env) (st : St) : St := carryInto env (placeDeferred env (fresh env false st))
def nextPage (env : Env) (st : St) : St := carryInto env (placeDeferred env (fresh env true st))

def dropAtTop (st : St) : St :=
  { st with pending := 0, blankActive := false, blankSpans := 0,
            unmet := st.unmet ++ List.replicate st.blankSpans .droppedBlank }

def fit (env : Env) (st : St) (amount : Int) : St :=
  if empty st ∧ amount ≤ room env st then dropAtTop st
  else if empty st ∧ st.adjust < 0 then dropAtTop (nextColumn env st)
  else if amount + st.pending ≤ room env st then
    { st with used := st.used + st.pending, pending := 0, blankActive := false, blankSpans := 0 }
  else if empty st then dropAtTop st
  else dropAtTop (nextColumn env st)

def noteLines (l : Line) : Nat := l.notes.foldr (fun n a => n.lines + a) 0

def splitNotes : Nat → List Note → List NotePart × List NotePart
  | _, [] => ([], [])
  | cap, n :: rest =>
    if n.lines ≤ cap then
      let p := splitNotes (cap - n.lines) rest
      ((n.id, 0, n.lines) :: p.1, p.2)
    else if 0 < cap then ([(n.id, 0, cap)], (n.id, cap, n.lines - cap) :: rest.map (fun x => (x.id, 0, x.lines)))
    else ([], (n.id, 0, n.lines) :: rest.map (fun x => (x.id, 0, x.lines)))

/-- The separator a line's notes reserve (`separator` of `putLineWithReserve`). -/
def lineSep (env : Env) (st : St) (l : Line) : Int :=
  if 0 < noteLines l ∧ st.notesUsed = 0 then env.separator else 0

/-- The parts of the line's notes shown in the column and carried on. -/
def lineNotes (env : Env) (st : St) (l : Line) : List NotePart × List NotePart :=
  let available := limit env st - st.used - env.pitchOf l.id - st.notesUsed - lineSep env st l
  splitNotes (max 0 (Int.fdiv available env.pagePitch)).toNat l.notes

/-- The note length of the column after the line. -/
def lineNotesUsed (env : Env) (st : St) (l : Line) : Int :=
  st.notesUsed + (if (lineNotes env st l).1.isEmpty then 0 else lineSep env st l) +
    (partsLines (lineNotes env st l).1 : Int) * env.pagePitch

def putLineWithReserve (allow : Bool) (env : Env) (st : St) (l : Line) : Except Failure St :=
  if env.capacity < env.pitchOf l.id then .error (.lineTooTall l.id)
  else if 0 < noteLines l ∧ (lineNotes env st l).1.isEmpty ∧ empty st ∧ ¬allow ∧
      limit env st < env.pitchOf l.id + lineSep env st l + env.pagePitch then
    match l.notes with
    | n :: _ => .error (.footnoteTooTall n.id)
    | [] => .ok st
  else
    .ok { putSlot st (env.pitchOf l.id) (.line l.id) with
      notesUsed := lineNotesUsed env st l
      notes := st.notes ++ (lineNotes env st l).1
      carry := st.carry ++ (lineNotes env st l).2 }

def putLine (env : Env) (st : St) (l : Line) : Except Failure St := putLineWithReserve false env st l

/-- `foldl'` of `putLine` (or `putLineWithReserve True`) over lines. -/
def putLines (allow : Bool) (env : Env) (st : St) : List Line → Except Failure St
  | [] => .ok st
  | l :: ls =>
    match putLineWithReserve allow env st l with
    | .error e => .error e
    | .ok s => putLines allow env s ls

/-- The loop of `fitting`, from the used length and the note length. -/
def fittingGo (env : Env) (st : St) (used notes : Int) : List Line → Nat
  | [] => 0
  | l :: ls =>
    let n := noteLines l
    let sep : Int := if 0 < n ∧ notes = 0 then env.separator else 0
    let used' := used + env.pitchOf l.id
    let notes' := notes + sep + (n : Int) * env.pagePitch
    if used' + notes' ≤ limit env st then fittingGo env st used' notes' ls + 1 else 0

def fitting (env : Env) (st : St) (ls : List Line) : Nat :=
  fittingGo env st (st.used + if empty st then 0 else st.pending) st.notesUsed ls

def splitAtBreak (k : Keep) (isStart : Bool) (total count : Nat) : Nat :=
  if total ≤ count then count
  else if k.all then 0
  else
    let widow := if total - count < k.last then total - k.last else count
    if isStart ∧ 0 < widow ∧ widow < k.first then 0 else widow

/-- `firstPart` of Decide.hs. -/
def firstPart (k : Keep) (isStart : Bool) (n : Nat) : Nat :=
  if k.all then n
  else ((List.range (n + 1)).filter (fun j => min k.first n ≤ j ∧ splitAtBreak k isStart n j = j)).headD n

inductive Part where
  | moved (st : St) (k : Keep)
  | placed (count : Nat) (st : St) (k : Keep)

def sumPitch (env : Env) (ls : List Line) : Int := ls.foldr (fun l a => env.pitchOf l.id + a) 0

/-- `trialParagraphPartLimit` without a wrap region or a prefix limit,
    after its first test and the relaxation of keep-all-lines. -/
def trialRest (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (firstId : Nat) :
    Except Failure Part :=
  let total := rows.length
  let count := fitting env st rows
  let selected := splitAtBreak k start total count
  let emptyish := empty st
  if (empty st ∧ st.adjust < 0 ∧ count = 0) ∨ (selected = 0 ∧ emptyish = false) then
    .ok (.moved (nextColumn env st) k)
  else
    let takeCount := if selected = 0 then max 1 count else selected
    let here := rows.take takeCount
    let forced := selected = 0 ∧ emptyish ∧ takeCount < total
    let short :=
      (if forced ∧ start ∧ takeCount < k.first then [Unmet.shortPart true firstId k.first takeCount] else []) ++
      (if forced ∧ total - takeCount < k.last then [Unmet.shortPart false firstId k.last (total - takeCount)] else [])
    let ready := fit env st (sumPitch env here)
    match putLines false env ready here with
    | .error e => .error e
    | .ok placed => .ok (.placed takeCount { placed with unmet := placed.unmet ++ short } k)

def trial (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) : Except Failure Part :=
  match rows with
  | [] => .ok (.placed 0 st k)
  | first :: _ =>
    if env.capacity < env.pitchOf first.id then .error (.lineTooTall first.id)
    else if k.all ∧ start ∧ fitting env st rows < rows.length then
      if empty st then trialRest env { k with all := false } start (addUnmet (.splitKept first.id) st) rows first.id
      else .ok (.moved (nextColumn env st) k)
    else trialRest env k start st rows first.id

/-! ## The rank the column loops decrease -/

def carryWeight (ps : List NotePart) : Nat := ps.foldr (fun p a => p.2.2 + 1 + a) 0
/-- What waits for a later column: the figures sent on and the lines of
    the notes carried on, each note counted one more. -/
def waiting (st : St) : Nat := st.deferred.length + carryWeight st.carry
def rank (st : St) : Nat :=
  waiting st * 4 + (if st.adjust < 0 then 2 else 0) + (if empty st then 0 else 1)
def keepRank (k : Keep) : Nat := if k.all then 1 else 0
def columnsLeft (st : St) : Nat := st.columns - (st.column + 1)

/-- `placeDeferredGo` only puts figures into the column. -/
theorem placeDeferredGo_fields (env : Env) (st : St) (ds : List (Nat × Int)) :
    (placeDeferredGo env st ds).page = st.page ∧ (placeDeferredGo env st ds).column = st.column ∧
    (placeDeferredGo env st ds).columns = st.columns ∧
    (placeDeferredGo env st ds).firstLine = st.firstLine ∧ (placeDeferredGo env st ds).adjust = st.adjust ∧
    (placeDeferredGo env st ds).notes = st.notes ∧ (placeDeferredGo env st ds).carry = st.carry ∧
    (placeDeferredGo env st ds).notesUsed = st.notesUsed ∧ (placeDeferredGo env st ds).done = st.done ∧
    (placeDeferredGo env st ds).deferred.length ≤ ds.length ∧
    ((placeDeferredGo env st ds).deferred.length = ds.length →
      (placeDeferredGo env st ds).slots = st.slots ∧ (placeDeferredGo env st ds).used = st.used) := by
  induction ds generalizing st with
  | nil => simp [placeDeferredGo]
  | cons d ds ih =>
    obtain ⟨i, e⟩ := d
    simp only [placeDeferredGo]
    split
    · obtain ⟨a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, _⟩ := ih (putSlot st e (.figure i))
      simp only [putSlot] at a1 a2 a3 a4 a5 a6 a7 a8 a9
      refine ⟨a1, a2, a3, a4, a5, a6, a7, a8, a9, by simp; omega, fun h => ?_⟩
      simp at h; omega
    · simp

theorem splitCarried_weight (n : Nat) (ps : List NotePart) :
    carryWeight (splitCarried n ps).2 ≤ carryWeight ps ∧
    (0 < n → ps ≠ [] → carryWeight (splitCarried n ps).2 < carryWeight ps) ∧
    ((splitCarried n ps).1 = [] → (splitCarried n ps).2 = ps) := by
  induction ps generalizing n with
  | nil => cases n <;> simp [splitCarried]
  | cons p ps ih =>
    obtain ⟨i, o, c⟩ := p
    cases n with
    | zero => simp [splitCarried]
    | succ r =>
      simp only [splitCarried]
      split
      · obtain ⟨a, _, _⟩ := ih (r + 1 - c)
        simp only [carryWeight, List.foldr] at a ⊢
        refine ⟨by omega, fun _ _ => by omega, by simp⟩
      · simp only [carryWeight, List.foldr]
        refine ⟨by omega, fun _ _ => by omega, by simp⟩

/-- `carryInto` changes only the notes of the column and what is carried. -/
theorem carryInto_fields (env : Env) (st : St) :
    (carryInto env st).page = st.page ∧ (carryInto env st).column = st.column ∧
    (carryInto env st).columns = st.columns ∧ (carryInto env st).firstLine = st.firstLine ∧
    (carryInto env st).adjust = st.adjust ∧ (carryInto env st).slots = st.slots ∧
    (carryInto env st).used = st.used ∧ (carryInto env st).deferred = st.deferred ∧
    (carryInto env st).done = st.done ∧
    carryWeight (carryInto env st).carry ≤ carryWeight st.carry ∧
    (carryWeight (carryInto env st).carry = carryWeight st.carry → (carryInto env st).notes = [] ∨ (carryInto env st).notes = st.notes) := by
  unfold carryInto
  split
  · exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, Nat.le_refl _, fun _ => Or.inr rfl⟩
  · rename_i h
    have ne : st.carry ≠ [] := by intro c; rw [c] at h; exact h rfl
    dsimp only
    generalize (max 0 (Int.fdiv (limit env st - st.used - env.separator) env.pagePitch)).toNat = n
    obtain ⟨a, b, c⟩ := splitCarried_weight n st.carry
    refine ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, a, fun e => Or.inl ?_⟩
    cases n with
    | zero =>
      cases d : st.carry with
      | nil => exact absurd d ne
      | cons p ps => simp [splitCarried]
    | succ m => have := b (by omega) ne; omega

theorem rank_le (st : St) : rank st ≤ waiting st * 4 + 3 := by
  unfold rank; split <;> split <;> omega

/-- The next column, before the figures and notes waiting are placed: it is
    empty and has not been made shorter. -/
theorem fresh_fields (env : Env) (tp : Bool) (st : St) :
    (fresh env tp st).slots = [] ∧ (fresh env tp st).notes = [] ∧
    (fresh env tp st).used = (fresh env tp st).firstLine ∧ (fresh env tp st).adjust = 0 ∧
    (fresh env tp st).deferred = st.deferred ∧ (fresh env tp st).carry = st.carry ∧
    (fresh env tp st).columns = st.columns := by
  unfold fresh close; split <;> simp

/-- What waits does not grow on the way to a new column; if it does not
    shrink, the new column is empty. -/
theorem open_waiting (env : Env) (tp : Bool) (st : St) :
    waiting (carryInto env (placeDeferred env (fresh env tp st))) ≤ waiting st ∧
    (waiting (carryInto env (placeDeferred env (fresh env tp st))) = waiting st →
      empty (carryInto env (placeDeferred env (fresh env tp st))) = true) ∧
    (carryInto env (placeDeferred env (fresh env tp st))).adjust = 0 := by
  obtain ⟨f1, f2, f3, f4, f5, f6, _⟩ := fresh_fields env tp st
  generalize fresh env tp st = F at *
  unfold placeDeferred
  obtain ⟨_, _, _, p4, p5, p6, p7, _, _, p10, p11⟩ := placeDeferredGo_fields env F F.deferred
  generalize placeDeferredGo env F F.deferred = P at *
  obtain ⟨_, _, _, c4, c5, c6, c7, c8, _, c10, c11⟩ := carryInto_fields env P
  generalize carryInto env P = C at *
  simp only [waiting]
  rw [c8, ← f5, ← f6, ← p7]
  refine ⟨by omega, fun e => ?_, by rw [c5, p5, f4]⟩
  have l : P.deferred.length = F.deferred.length := by omega
  obtain ⟨s, u⟩ := p11 l
  have w : carryWeight C.carry = carryWeight P.carry := by omega
  have n : C.notes = [] := by
    cases c11 w with
    | inl h => exact h
    | inr h => rw [h, p6, f2]
  simp [empty, n, c6, s, f1, c7, u, f3, c4, p4, List.isEmpty]

theorem I4_nextColumn_rank (env : Env) (st : St) (h : empty st = false ∨ st.adjust < 0) :
    rank (nextColumn env st) < rank st := by
  obtain ⟨le, e, a⟩ := open_waiting env false st
  unfold nextColumn
  generalize carryInto env (placeDeferred env (fresh env false st)) = C at *
  have r := rank_le C
  by_cases lt : waiting C < waiting st
  · have : waiting C * 4 + 3 < rank st := by unfold rank; omega
    omega
  · have eq : waiting C = waiting st := by omega
    have em := e eq
    have : rank C = waiting st * 4 := by simp [rank, em, a, eq]
    rw [this]
    unfold rank
    cases h with
    | inl h => simp [h]; split <;> omega
    | inr h => simp [h]; split <;> omega

theorem trialRest_moved (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.moved next r)) :
    r = k ∧ next = nextColumn env st ∧ (empty st = false ∨ st.adjust < 0) := by
  unfold trialRest at h
  dsimp only at h
  split at h
  · rename_i c
    injection h with h; injection h with h1 h2
    refine ⟨h2.symm, h1.symm, ?_⟩
    cases c with
    | inl c => exact Or.inr c.2.1
    | inr c => exact Or.inl c.2
  · split at h <;> simp at h

theorem trialRest_placed (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (c : Nat) (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.placed c next r)) :
    1 ≤ c := by
  unfold trialRest at h
  dsimp only at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · injection h with h; injection h with h1 _ _
      subst h1; split <;> omega

theorem I4_trial_moved (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (next : St) (relaxed : Keep) (h : trial env k start st rows = .ok (.moved next relaxed)) :
    keepRank relaxed < keepRank k ∨ (keepRank relaxed = keepRank k ∧ rank next < rank st) := by
  unfold trial at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · rename_i c
        split at h
        · obtain ⟨e, _, _⟩ := trialRest_moved env _ start _ _ _ next relaxed h
          left; subst e; simp [keepRank, c.1]
        · injection h with h; injection h with h1 h2
          subst h1; subst h2
          rename_i ne
          exact Or.inr ⟨rfl, I4_nextColumn_rank env st (Or.inl (by simpa using ne))⟩
      · obtain ⟨e, n, m⟩ := trialRest_moved env _ start _ _ _ next relaxed h
        subst e; subst n
        exact Or.inr ⟨rfl, I4_nextColumn_rank env st m⟩

theorem I4_trial_placed (env : Env) (k : Keep) (start : Bool) (st : St) (r : Line) (rs : List Line)
    (c : Nat) (next : St) (relaxed : Keep) (h : trial env k start st (r :: rs) = .ok (.placed c next relaxed)) :
    1 ≤ c := by
  unfold trial at h
  dsimp only at h
  split at h
  · simp at h
  · split at h
    · split at h
      · exact trialRest_placed env _ start _ _ _ c next relaxed h
      · simp at h
    · exact trialRest_placed env _ start _ _ _ c next relaxed h

/-! ## Paragraphs -/

def placeLines (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) : Except Failure St :=
  match rows with
  | [] => .ok st
  | r :: rs =>
    match h : trial env k start st (r :: rs) with
    | .error e => .error e
    | .ok (.moved next relaxed) => placeLines env relaxed start next (r :: rs)
    | .ok (.placed count next relaxed) =>
      if count = (r :: rs).length then .ok next
      else placeLines env relaxed false (nextColumn env next) ((r :: rs).drop count)
termination_by (rows.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right
    cases I4_trial_moved env k start st _ next relaxed h with
    | inl l => exact Prod.Lex.left _ _ l
    | inr e => rw [e.1]; exact Prod.Lex.right _ e.2
  · apply Prod.Lex.left
    have := I4_trial_placed env k start st _ _ count next relaxed h
    omega

/-! ## The rules of FreeGeometry.hs, their extra lengths only -/

def half (n : Int) : Int := Int.fdiv n 2
def faceOffset (pitch face : Int) : Int := half pitch - half face
def ruleBeforeExtra (pitch face inner weight overhang : Int) : Int :=
  max 0 (inner + weight + overhang - faceOffset pitch face)
def ruleAfterExtra (pitch face inner weight : Int) : Int :=
  max 0 (inner + weight - (pitch - face - faceOffset pitch face))
/-- The extra of `ruleBeforeGap` and of `ruleAfterGap`. -/
def ruleGapExtra (gap : Int) (s : RuleSide) (overhang : Int) : Int :=
  max 0 (s.inner + s.weight + s.outer + overhang - gap)
def rulesSharedExtra (gap : Int) (b a : RuleSide) (overhang : Int) : Int :=
  max 0 (b.inner + b.weight + max b.outer a.outer + a.weight + a.inner + overhang - gap)
def ruleBeforeEdgeExtra (pitch face : Int) (s : RuleSide) (overhang : Int) : Int :=
  let leading := faceOffset pitch face
  let exact := leading - overhang - s.inner - s.weight
  let outside := if s.spaced then exact else min (-s.weight) exact
  let extra := ruleBeforeExtra pitch face s.inner s.weight overhang
  match s.outside with
  | some available => if outside + s.weight ≤ 0 ∧ -outside ≤ available then 0 else extra
  | none => extra
def ruleAfterEdgeExtra (pitch face : Int) (s : RuleSide) : Int :=
  let faceEnd := faceOffset pitch face + face
  let exact := faceEnd + s.inner
  let outside := if s.spaced then exact else max pitch exact
  let extra := ruleAfterExtra pitch face s.inner s.weight
  match s.outside with
  | some available => if pitch ≤ outside ∧ outside + s.weight - pitch ≤ available then 0 else extra
  | none => extra

def flowLines : Flow → List Line
  | .paragraph _ ls => ls
  | .continued _ ls => ls
  | .ruled r => r.lines
  | _ => []

/-! ## Ruled blocks -/

def flushPendingRule (env : Env) (st : St) : St :=
  match st.join with
  | none => st
  | some (_, side, l, priorExtra) =>
    let extra := ruleAfterEdgeExtra (env.pitchOf l.id) (env.faceOf l.id) { side with outside := none }
    { st with used := st.used + max 0 (extra - priorExtra), join := none }

def lastSlot (st : St) : Option (Int × Slot) := st.slots.getLast?

/-- The extra before the first line of a ruled block (`beforeGeometry`). -/
def ruledBefore (env : Env) (st : St) (r : Ruled) (first : Line) (side : RuleSide) : Int :=
  let firstPitch := env.pitchOf first.id
  let firstFace := env.faceOf first.id
  let edge := ruleBeforeEdgeExtra firstPitch firstFace
    (if empty st ∧ st.used = 0 then side else { side with outside := none }) first.overhang
  let unjoined :=
    match lastSlot st with
    | some (priorAt, .line priorId) =>
      if st.pending = 0 then
        let priorEnd := priorAt + faceOffset (env.pitchOf priorId) (env.faceOf priorId) + env.faceOf priorId
        let gap := st.used + faceOffset firstPitch firstFace - priorEnd
        ruleGapExtra gap side first.overhang
      else edge
    | _ => edge
  match st.join with
  | some (_, prior, priorLine, priorExtra) =>
    if r.joined then
      let previousPitch := env.pitchOf priorLine.id
      let previousFace := env.faceOf priorLine.id
      let priorEnd := st.used - priorExtra - previousPitch + faceOffset previousPitch previousFace + previousFace
      let gap := st.used + faceOffset firstPitch firstFace - priorEnd
      rulesSharedExtra gap prior side first.overhang
    else unjoined
  | none => unjoined

def joiningNext : List Flow → Bool
  | .ruled r :: _ => r.joined && r.before.isSome
  | _ => false

/-- The extra after the last line of a ruled block (`afterGeometry`). -/
def ruledAfter (env : Env) (r : Ruled) (lastLine : Line) (later : List Flow) (side : RuleSide) : Int :=
  let lastPitch := env.pitchOf lastLine.id
  let lastFace := env.faceOf lastLine.id
  let edge := ruleAfterEdgeExtra lastPitch lastFace { side with outside := none }
  match later with
  | f :: _ =>
    match flowLines f with
    | n :: _ =>
      let gap := lastPitch - lastFace - faceOffset lastPitch lastFace + faceOffset (env.pitchOf n.id) (env.faceOf n.id)
      ruleGapExtra gap side r.nextOverhang
    | [] => edge
  | [] => edge

def joinedRank (r : Ruled) : Nat := if r.joined then 1 else 0

theorem I4_fit_moved (env : Env) (st : St) (a : Int)
    (h : ¬((fit env st a).page = st.page ∧ (fit env st a).column = st.column)) :
    rank (fit env st a) < rank st := by
  have d : ∀ s : St, rank (dropAtTop s) = rank s := fun s => rfl
  unfold fit at h ⊢
  by_cases c1 : empty st = true ∧ a ≤ room env st
  · rw [if_pos c1] at h; exact absurd ⟨rfl, rfl⟩ h
  rw [if_neg c1] at h ⊢
  by_cases c2 : empty st = true ∧ st.adjust < 0
  · rw [if_pos c2]; rw [d]; exact I4_nextColumn_rank env st (Or.inr c2.2)
  rw [if_neg c2] at h ⊢
  by_cases c3 : a + st.pending ≤ room env st
  · rw [if_pos c3] at h; exact absurd ⟨rfl, rfl⟩ h
  rw [if_neg c3] at h ⊢
  by_cases c4 : empty st = true
  · rw [if_pos c4] at h; exact absurd ⟨rfl, rfl⟩ h
  rw [if_neg c4]; rw [d]; exact I4_nextColumn_rank env st (Or.inl (by simpa using c4))

/-- The extra length before a ruled block (`beforeExtra`). -/
def ruledBeforeExtra (env : Env) (st : St) (r : Ruled) (first : Line) : Int :=
  match r.before with
  | some side => ruledBefore env st r first side
  | none => 0

/-- The extra length after a ruled block (`afterExtra`): none when its
    rule after waits to share its area with the next block. -/
def ruledAfterExtra (env : Env) (r : Ruled) (lastLine : Line) (later : List Flow) : Int :=
  if joiningNext later then 0
  else match r.after with
    | some side => ruledAfter env r lastLine later side
    | none => 0

/-- The rule after waiting for the next block (`waiting` of `placeRuled`). -/
def ruledJoin (env : Env) (r : Ruled) (lastLine : Line) (later : List Flow) : Option (Nat × RuleSide × Line × Int) :=
  if joiningNext later then r.after.map (fun side => (r.id, side, lastLine, ruledAfterExtra env r lastLine later))
  else none

def ruledExtent (env : Env) (st : St) (r : Ruled) (first lastLine : Line) (later : List Flow) : Int :=
  ruledBeforeExtra env st r first + sumPitch env r.lines + ruledAfterExtra env r lastLine later

set_option linter.unusedVariables false in
def placeRuled (env : Env) (st : St) (r : Ruled) (later : List Flow) : Except Failure St :=
  match r.lines.head?, r.lines.getLast? with
  | some first, some lastLine =>
    if h1 : r.joined ∧ st.join.isSome ∧ room env st < ruledExtent env st r first lastLine later + st.pending ∧
        empty st = false then
      placeRuled env (nextColumn env (flushPendingRule env st)) { r with joined := false } later
    else if env.capacity < ruledExtent env st r first lastLine later then placeLines env r.keep true st r.lines
    else if h2 : ¬((fit env st (ruledExtent env st r first lastLine later)).page = st.page ∧
        (fit env st (ruledExtent env st r first lastLine later)).column = st.column) then
      placeRuled env (fit env st (ruledExtent env st r first lastLine later)) r later
    else
      match putLines true env
          { fit env st (ruledExtent env st r first lastLine later) with
            used := (fit env st (ruledExtent env st r first lastLine later)).used + ruledBeforeExtra env st r first
            adjust := (fit env st (ruledExtent env st r first lastLine later)).adjust - ruledAfterExtra env r lastLine later }
          r.lines with
      | .error e => .error e
      | .ok placed =>
        .ok { placed with
          used := placed.used + ruledAfterExtra env r lastLine later
          adjust := (fit env st (ruledExtent env st r first lastLine later)).adjust
          join := ruledJoin env r lastLine later }
  | _, _ => .ok st
termination_by (joinedRank r, rank st)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.left; simp [joinedRank, h1.1]
  · apply Prod.Lex.right; exact I4_fit_moved env st _ h2

/-! ## What follows a block -/

/-- `keepAhead` of Physical.hs: the last and first lines the controls
    ahead ask for, and the flows without them. -/
def soft : Flow → Bool
  | .space _ | .needLines _ | .adjustLines _ | .noBreakLines 0 => true
  | _ => false

def counts : Flow → Option (Nat × Nat)
  | .noBreak => some (2, 0)
  | .noBreakLines n => some (n, 0)
  | .keepNext n => some (0, n)
  | _ => none

/-- `collect` of `keepAhead`: `before` and the soft flows since the last
    control, then the flows not yet read. -/
def collect (before between : List Flow) (l f : Nat) : List Flow → Nat × Nat × List Flow
  | [] => (l, f, before ++ between)
  | x :: xs =>
    if soft x then collect before (between ++ [x]) l f xs
    else match counts x with
      | some (l', f') => collect (before ++ between) [] (max l l') (max f f') xs
      | none => (l, f, before ++ between ++ x :: xs)

def keepAheadGo (between : List Flow) : List Flow → Option (Nat × Nat × List Flow)
  | [] => none
  | x :: xs =>
    if soft x then keepAheadGo (between ++ [x]) xs
    else match counts x with
      | some (l, f) => some (collect between [] l f xs)
      | none => none

def keepAhead (flows : List Flow) : Option (Nat × Nat × List Flow) := keepAheadGo [] flows

def followingRows (wanted : Nat) : List Flow → Nat × Bool
  | .paragraph k ls :: _ => (max (firstPart k true ls.length) (min wanted ls.length), true)
  | .continued k ls :: _ => (max (firstPart k false ls.length) (min wanted ls.length), true)
  | .space _ :: rest | .needLines _ :: rest | .adjustLines _ :: rest
  | .noBreak :: rest | .noBreakLines _ :: rest | .keepNext _ :: rest => followingRows wanted rest
  | _ => (1, false)

def fitsFollowingGo (env : Env) (st : St) (wanted : Nat) (extra : Int) : List Flow → Bool
  | .space s :: rest => fitsFollowingGo env st wanted (extra + s) rest
  | .needLines _ :: rest | .adjustLines _ :: rest | .noBreak :: rest
  | .noBreakLines _ :: rest | .keepNext _ :: rest => fitsFollowingGo env st wanted extra rest
  | .ruled r :: rest =>
    match placeRuled env { st with pending := st.pending + extra } r rest with
    | .ok placed => placed.page == st.page && placed.column == st.column
    | .error _ => false
  | rest => decide (extra + env.firstNeed (decide (0 < st.notesUsed)) wanted rest ≤ room env st)

def fitsFollowing (env : Env) (st : St) (wanted : Nat) (flows : List Flow) : Bool :=
  fitsFollowingGo env st wanted 0 flows

/-- The lines of a paragraph moved on with what follows (`backCount` of
    `placeWithNext`). -/
def keptBack (k : Keep) (lastCount len : Nat) : Nat :=
  let requested := max lastCount k.last
  let minimumFirst := if 0 < lastCount then max 2 k.first else k.first
  if k.all ∨ len ≤ requested ∨ len - requested < minimumFirst then len else requested

/-- The column after the front part: the same one when it is still empty. -/
def afterFront (env : Env) (before : St) : St := if empty before then before else nextColumn env before

def placeWithNext (env : Env) (k : Keep) (start : Bool) (st : St) (ls : List Line)
    (lastCount firstCount : Nat) (later : List Flow) : Except Failure St :=
  match placeLines env k start st ls with
  | .error e => .error e
  | .ok full =>
    if fitsFollowing env full firstCount later then .ok full
    else if (ls.drop (ls.length - keptBack k lastCount ls.length)).isEmpty then .ok full
    else
      match placeLines env k start st (ls.take (ls.length - keptBack k lastCount ls.length)) with
      | .error e => .error e
      | .ok before =>
        placeLines env k (start && (ls.take (ls.length - keptBack k lastCount ls.length)).isEmpty)
          (afterFront env before) (ls.drop (ls.length - keptBack k lastCount ls.length))

def placeRuledKeeping (env : Env) (st : St) (r : Ruled) (later : List Flow) : Except Failure St :=
  match placeRuled env st r later with
  | .error e => .error e
  | .ok full =>
    match keepAhead later with
    | some (_, wanted, rest) =>
      if empty st = false ∧ fitsFollowing env full wanted rest = false then
        placeRuled env (nextColumn env (flushPendingRule env st)) { r with joined := false } later
      else .ok full
    | none => .ok full

/-! ## Keeps waiting for what follows -/

def waitFor (u : Unmet) (req : Nat × Bool) (st : St) : St :=
  let combined := st.waits.foldl (fun a w => max a w.2.2.2.2.1) req.1
  let onlyLines := req.2 || st.waits.any (fun w => w.2.2.2.2.2)
  let prior := st.waits.map (fun w => (w.1, w.2.1, w.2.2.1, w.2.2.2.1, combined, onlyLines))
  { st with waits := prior ++ [(u, st.page, st.column, st.slots.length, combined, onlyLines)] }

def waitForPrior (u : Unmet) (req : Nat × Bool) (st : St) : St :=
  if empty st ∨ st.deferred ≠ [] then addUnmet u st else waitFor u req st

def addedSlots (linesOnly : Bool) (prior : Nat) (slots : List (Int × Slot)) : Nat :=
  ((slots.drop prior).map (fun s => match s.2 with | .line _ => 1 | _ => if linesOnly then 0 else 1)).foldr (· + ·) 0

/-- Whether a wait is met: the column it started in took the lines asked for. -/
def waitMet (acc : St) (w : Wait) : Bool :=
  let (_, page, column, prior, required, linesOnly) := w
  let current := acc.page == page && acc.column == column
  let inCurrent := if current then addedSlots linesOnly prior acc.slots else 0
  let inDone := (acc.done.filter (fun o => o.number == page && o.column == column)).foldl
    (fun a o => max a (addedSlots linesOnly prior o.slots)) 0
  decide (max 1 required ≤ max inCurrent inDone)

def markUnmet (w : Wait) (o : PageOut) : PageOut :=
  if o.number == w.2.1 && o.column == w.2.2.1 then { o with unmet := o.unmet ++ [w.1] } else o

def checkWait (acc : St) (w : Wait) : St :=
  if waitMet acc w then acc
  else if acc.page == w.2.1 && acc.column == w.2.2.1 then addUnmet w.1 acc
  else { acc with done := acc.done.map (markUnmet w) }

def checkWaits (st : St) : St := st.waits.foldl checkWait { st with waits := [] }

/-! ## Breaks -/

/-- `drainCarry`, going on only while the next page can take the first
    figure sent on and a line of the first note carried on; README.md
    explains why `paginate` never meets a state where it stops early. -/
def drainOk (env : Env) (st : St) : Bool :=
  (st.carry.isEmpty || decide (0 < env.pagePitch ∧ env.separator + env.pagePitch ≤ env.capacity)) &&
  (match st.deferred with | (_, e) :: _ => decide (e ≤ env.capacity) | [] => true)

theorem fdiv_nat (k n : Nat) : Int.fdiv (Int.ofNat (k + 1)) (Int.ofNat n) = Int.ofNat ((k + 1) / n) := rfl

theorem fdiv_pos (a b : Int) (hb : 0 < b) (h : b ≤ a) : 1 ≤ Int.fdiv a b := by
  match a, b, hb, h with
  | Int.ofNat (k + 1), Int.ofNat n, hb, h =>
    rw [fdiv_nat]
    simp only [Int.ofNat_eq_coe] at hb h ⊢
    have : 1 ≤ (k + 1) / n := (Nat.le_div_iff_mul_le (by omega)).2 (by omega)
    omega
  | Int.ofNat 0, Int.ofNat n, hb, h => simp only [Int.ofNat_eq_coe] at hb h; omega
  | Int.negSucc m, _, hb, h => have := Int.negSucc_lt_zero m; omega
  | Int.ofNat _, Int.negSucc m, hb, _ => exact absurd hb (Int.not_lt.2 (Int.le_of_lt (Int.negSucc_lt_zero m)))

/-- A note carried on shows at least one line where a line fits. -/
theorem carryInto_strict (env : Env) (st : St) (ne : st.carry ≠ [])
    (h : 1 ≤ Int.fdiv (limit env st - st.used - env.separator) env.pagePitch) :
    carryWeight (carryInto env st).carry < carryWeight st.carry := by
  unfold carryInto
  have e : st.carry.isEmpty = false := by
    cases c : st.carry with
    | nil => exact absurd c ne
    | cons _ _ => rfl
  rw [e]
  dsimp only
  simp only [ite_false]
  generalize Int.fdiv (limit env st - st.used - env.separator) env.pagePitch = q at h ⊢
  have m : max 0 q = q := Int.max_eq_right (by omega)
  have t : ((q.toNat : Nat) : Int) = q := Int.toNat_of_nonneg (by omega)
  rw [m]
  exact (splitCarried_weight _ st.carry).2.1 (by omega) ne

theorem fresh_pageEnd (env : Env) (st : St) (h : st.columns ≤ st.column + 1) :
    (fresh env false st).used = 0 ∧ (fresh env false st).adjust = 0 ∧ (fresh env false st).notesUsed = 0 ∧
    (fresh env false st).column = 0 := by
  simp [fresh, h]

theorem fresh_inPage (env : Env) (st : St) (h : ¬st.columns ≤ st.column + 1) :
    (fresh env false st).column = st.column + 1 := by
  simp [fresh, h]

/-- `drainCarry` goes on to a column that leaves fewer columns on the
    page or less waiting, and on to a new page only with less waiting. -/
theorem I4_drain_rank (env : Env) (st : St)
    (h : (st.carry.isEmpty && st.deferred.isEmpty) = false ∧ drainOk env st = true) :
    Prod.Lex (· < ·) (· < ·) (waiting (nextColumn env st), columnsLeft (nextColumn env st))
      (waiting st, columnsLeft st) := by
  obtain ⟨le, _, _⟩ := open_waiting env false st
  obtain ⟨_, _, _, _, f5, f6, f7⟩ := fresh_fields env false st
  by_cases pe : st.columns ≤ st.column + 1
  · apply Prod.Lex.left
    obtain ⟨u0, a0, n0, _⟩ := fresh_pageEnd env st pe
    unfold nextColumn placeDeferred
    generalize fresh env false st = Fr at *
    cases d : st.deferred with
    | cons x rest =>
      obtain ⟨i, e⟩ := x
      have ok : e ≤ env.capacity := by
        have := h.2; simp only [drainOk, d, Bool.and_eq_true, decide_eq_true_eq] at this; exact this.2
      rw [f5, d]
      simp only [placeDeferredGo]
      have r : e ≤ room env Fr := by simp only [room, limit, u0, a0, n0]; omega
      rw [if_pos r]
      obtain ⟨_, _, _, _, _, _, p7, _, _, p10, _⟩ := placeDeferredGo_fields env (putSlot Fr e (.figure i)) rest
      obtain ⟨_, _, _, _, _, _, _, c8, _, c10, _⟩ := carryInto_fields env (placeDeferredGo env (putSlot Fr e (.figure i)) rest)
      simp only [waiting, c8, d, List.length_cons]
      have p7' : (placeDeferredGo env (putSlot Fr e (.figure i)) rest).carry = st.carry := p7.trans f6
      rw [p7'] at c10
      omega
    | nil =>
      have ne : st.carry ≠ [] := by
        intro c; have := h.1; rw [c, d] at this; exact absurd this (by decide)
      have fits : 0 < env.pagePitch ∧ env.separator + env.pagePitch ≤ env.capacity := by
        have := h.2
        cases c : st.carry with
        | nil => exact absurd c ne
        | cons _ _ => simp only [drainOk, c, d, List.isEmpty, Bool.false_or, Bool.and_true, decide_eq_true_eq] at this; exact this
      rw [f5, d]
      simp only [placeDeferredGo]
      have s := carryInto_strict env { Fr with deferred := [] } (by rw [← f6] at ne; exact ne)
        (fdiv_pos _ _ fits.1 (by show env.pagePitch ≤ env.capacity + Fr.adjust - Fr.used - env.separator; omega))
      simp only [waiting, d, List.length_nil]
      have : ({ Fr with deferred := [] } : St).carry = st.carry := f6
      obtain ⟨_, _, _, _, _, _, _, c8, _, _, _⟩ := carryInto_fields env { Fr with deferred := [] }
      have e2 : carryWeight ({ Fr with deferred := [] } : St).carry = carryWeight st.carry := by rw [this]
      rw [c8]; simp only [List.length_nil]; omega
  · have cl : columnsLeft (nextColumn env st) < columnsLeft st := by
      unfold nextColumn placeDeferred
      have fc := fresh_inPage env st pe
      obtain ⟨_, p2, p3, _⟩ := placeDeferredGo_fields env (fresh env false st) (fresh env false st).deferred
      obtain ⟨_, c2, c3, _⟩ := carryInto_fields env (placeDeferredGo env (fresh env false st) (fresh env false st).deferred)
      simp only [columnsLeft, c2, c3, p2, p3, fc, f7]
      omega
    unfold nextColumn at cl ⊢
    by_cases w : waiting (carryInto env (placeDeferred env (fresh env false st))) < waiting st
    · exact Prod.Lex.left _ _ w
    · have : waiting (carryInto env (placeDeferred env (fresh env false st))) = waiting st := by omega
      rw [this]; exact Prod.Lex.right _ cl

set_option linter.unusedVariables false in
def drainCarry (env : Env) (st : St) : St :=
  if h : (st.carry.isEmpty && st.deferred.isEmpty) = false ∧ drainOk env st = true then
    drainCarry env (nextColumn env st)
  else st
termination_by (waiting st, columnsLeft st)
decreasing_by
  simp_wf
  exact I4_drain_rank env st h

def parityStart (env : Env) (accept : Nat → Bool) (st : St) : St :=
  let settled := drainCarry env st
  let next := if empty settled ∧ settled.column = 0 then settled else nextPage env settled
  if accept next.page then next
  else if empty next then
    { next with done := ⟨next.page, 0, true, [], [], limit env next, []⟩ :: next.done, page := next.page + 1 }
  else nextPage env next

def breakAt (env : Env) (k : BreakKind) (st : St) : St :=
  match k with
  | .column => nextColumn env st
  | .page => nextPage env st
  | .recto => parityStart env (fun p => p % 2 == 1) st
  | .verso => parityStart env (fun p => p % 2 == 0) st

/-! ## Need-lines and adjust-lines -/

set_option linter.unusedVariables false in
def judgeNeed (env : Env) (bounded : Int) (st : St) : St :=
  if bounded ≤ room env st then st
  else if h : empty st = true ∧ st.adjust < 0 then judgeNeed env bounded (nextColumn env st)
  else if h' : empty st then st
  else judgeNeed env bounded (nextColumn env st)
termination_by rank st
decreasing_by
  all_goals simp_wf
  · exact I4_nextColumn_rank env st (Or.inr h.2)
  · exact I4_nextColumn_rank env st (Or.inl (by simpa using h'))

def ceilDiv (a b : Int) : Int := -(Int.fdiv (-a) b)

def adjustLines (env : Env) (n : Int) (st : St) : St :=
  let usedLength := st.used + st.notesUsed
  let wanted := Int.fdiv st.adjust env.pagePitch + n
  let lower := ceilDiv (max env.fontSize usedLength - env.capacity) env.pagePitch
  let upper := Int.fdiv (env.maxCapacity - env.capacity) env.pagePitch
  let chosen := max lower (min upper wanted)
  let why := if chosen < wanted then AdjustLimit.noRoom else if env.fontSize < usedLength then .linesPlaced else .oneLine
  { st with adjust := chosen * env.pagePitch,
            unmet := st.unmet ++ (if chosen ≠ wanted then [Unmet.adjust chosen why] else []) }

/-! ## One flow -/

def placeFlow (env : Env) (st : St) : Flow → Except Failure St
  | .paragraph k ls => placeLines env k true st ls
  | .continued k ls => placeLines env k false st ls
  | .space n => .ok { st with pending := if st.blankActive then st.pending else st.pending + max 0 n }
  | .blank n => .ok { st with
      pending := (if st.blankActive then st.pending else 0) + (n : Int) * env.pagePitch
      blankActive := true
      blankSpans := st.blankSpans + (if 0 < n then 1 else 0) }
  | .figure i e =>
    if env.capacity < e then .error (.figureTooTall i)
    else if st.deferred ≠ [] then .ok { st with deferred := st.deferred ++ [(i, e)] }
    else if room env st < e + st.pending ∧ empty st = false then
      .ok { st with deferred := st.deferred ++ [(i, e)], pending := 0, blankActive := false }
    else .ok (putSlot (fit env st e) e (.figure i))
  | .brk k => .ok (breakAt env k st)
  | .needLines n =>
    let required := (n : Int) * env.pagePitch
    let bounded := min required env.capacity
    let marked := if env.capacity < required then addUnmet (.needLines n) st else st
    .ok (judgeNeed env bounded marked)
  | .adjustLines n => .ok (adjustLines env n st)
  | .noBreak => .ok (waitForPrior .noBreak (1, false) st)
  | .noBreakLines n => if n = 0 then .ok st else .ok (waitForPrior .noBreak (1, false) st)
  | .keepNext _ => .ok (waitForPrior .keepNext (1, false) st)
  | .pageFigure i =>
    let fr := if empty st then st else nextPage env st
    .ok (nextPage env (putSlot fr env.capacity (.pageFigure i)))
  | .ruled r => placeRuled env st r []

def occupies : Flow → Bool
  | .paragraph _ _ | .continued _ _ | .figure _ _ | .pageFigure _ | .ruled _ => true
  | _ => false

/-- The state a flow starts from in `placeNext`: the next column when a
    blank before it leaves too little room, and without a rule waiting to
    be shared unless the flow is a ruled block. -/
def beforeOf (env : Env) (st : St) (flow : Flow) (rest : List Flow) : St :=
  let boundaryNeed := min env.capacity (st.pending + env.firstNeed (decide (0 < st.notesUsed)) 1 (flow :: rest))
  let afterBlank :=
    if st.blankActive ∧ occupies flow ∧ empty st = false ∧ room env st < boundaryNeed then nextColumn env st else st
  match flow with
  | .ruled _ => afterBlank
  | _ => { afterBlank with join := none }

/-- The placement of the flow itself in `placeNext`. -/
def placeBody (env : Env) (before : St) (flow : Flow) (rest : List Flow) : Except Failure St :=
  match flow, keepAhead rest with
  | .paragraph k ls, some (l, f, later) => placeWithNext env k true before ls l f later
  | .continued k ls, some (l, f, later) => placeWithNext env k false before ls l f later
  | .noBreak, _ => .ok (waitForPrior .noBreak (followingRows 0 rest) before)
  | .noBreakLines n, _ =>
    if 0 < n then .ok (waitForPrior .noBreak (followingRows 0 rest) before) else placeFlow env before flow
  | .keepNext n, _ => .ok (waitForPrior .keepNext (followingRows n rest) before)
  | .ruled r, _ => placeRuledKeeping env before r rest
  | _, _ => placeFlow env before flow

def placeNext (env : Env) (st : St) (flow : Flow) (rest : List Flow) : Except Failure St :=
  match placeBody env (beforeOf env st flow rest) flow rest with
  | .error e => .error e
  | .ok s => .ok (if occupies flow then checkWaits s else s)

def placeAll (env : Env) (st : St) : List Flow → Except Failure St
  | [] => .ok st
  | f :: rest =>
    match placeNext env st f rest with
    | .error e => .error e
    | .ok s => placeAll env s rest

def checkNotes (env : Env) (flows : List Flow) : Option Failure :=
  match (flows.bind flowLines).bind (fun l => l.notes) with
  | n :: _ => if env.capacity < env.separator + env.pagePitch then some (.footnoteTooTall n.id) else none
  | [] => none

/-- `paginatePhysical` of Physical.hs. -/
def paginate (env : Env) (flows : List Flow) : Except Failure (List PageOut) :=
  match checkNotes env flows with
  | some e => .error e
  | none =>
    match placeAll env (initial env) flows with
    | .error e => .error e
    | .ok final =>
      let closed := close env (drainCarry env final)
      match closed.done.reverse with
      | [] => .ok [⟨1, 0, false, [], [], env.capacity, []⟩]
      | pages => .ok pages

/-! ## What the pages hold -/

def textSlots : List (Int × Slot) → List Nat
  | [] => []
  | (_, .line i) :: r => i :: textSlots r
  | _ :: r => textSlots r
def figSlots : List (Int × Slot) → List Nat
  | [] => []
  | (_, .figure i) :: r => i :: figSlots r
  | _ :: r => figSlots r
def pagesText : List PageOut → List Nat
  | [] => []
  | p :: ps => textSlots p.slots ++ pagesText ps
def pagesFigs : List PageOut → List Nat
  | [] => []
  | p :: ps => figSlots p.slots ++ pagesFigs ps
/-- The lines placed, in the pages closed and in the column. -/
def text (st : St) : List Nat := pagesText st.done.reverse ++ textSlots st.slots
/-- The figures placed, in the pages closed and in the column, then those sent on. -/
def figs (st : St) : List Nat := pagesFigs st.done.reverse ++ figSlots st.slots ++ st.deferred.map (·.1)
def lineIds (ls : List Line) : List Nat := ls.map (·.id)
def flowFigs : Flow → List Nat
  | .figure i _ => [i]
  | _ => []
def sourceText : List Flow → List Nat
  | [] => []
  | f :: fs => lineIds (flowLines f) ++ sourceText fs
def sourceFigs : List Flow → List Nat
  | [] => []
  | f :: fs => flowFigs f ++ sourceFigs fs

/-- A note line and its separator fit in the column. -/
def NotesFit (env : Env) : Prop := env.separator + env.pagePitch ≤ env.capacity
/-- What `drainCarry` needs to go on: the figures sent on fit in a column,
    and notes are carried on only where a note line fits. -/
def Good (env : Env) (st : St) : Prop :=
  (∀ d ∈ st.deferred, d.2 ≤ env.capacity) ∧ (st.carry ≠ [] → NotesFit env)
def LineOk (env : Env) (l : Line) : Prop := l.notes = [] ∨ NotesFit env

/-- From `st` to `s`, the lines `t` and the figures `g` are added. -/
def Step (env : Env) (st s : St) (t g : List Nat) : Prop :=
  text s = text st ++ t ∧ figs s = figs st ++ g ∧ (Good env st → Good env s)

theorem Step.refl (env : Env) (st : St) : Step env st st [] [] := by
  simp [Step]

theorem Step.trans {env : Env} {a b c : St} {t g t' g' : List Nat}
    (h : Step env a b t g) (h' : Step env b c t' g') : Step env a c (t ++ t') (g ++ g') := by
  obtain ⟨t1, g1, d1⟩ := h
  obtain ⟨t2, g2, d2⟩ := h'
  exact ⟨by rw [t2, t1, List.append_assoc], by rw [g2, g1, List.append_assoc], fun x => d2 (d1 x)⟩

theorem Step.same {env : Env} {st s : St} (d : s.done = st.done) (sl : s.slots = st.slots)
    (df : s.deferred = st.deferred) (c : s.carry = st.carry) : Step env st s [] [] := by
  refine ⟨?_, ?_, ?_⟩
  · simp [text, d, sl]
  · simp [figs, d, sl, df]
  · intro ⟨a, b⟩; exact ⟨by rw [df]; exact a, by rw [c]; exact b⟩

theorem textSlots_append (a b : List (Int × Slot)) : textSlots (a ++ b) = textSlots a ++ textSlots b := by
  induction a with
  | nil => rfl
  | cons x r ih => obtain ⟨_, s⟩ := x; cases s <;> simp [textSlots, ih]
theorem figSlots_append (a b : List (Int × Slot)) : figSlots (a ++ b) = figSlots a ++ figSlots b := by
  induction a with
  | nil => rfl
  | cons x r ih => obtain ⟨_, s⟩ := x; cases s <;> simp [figSlots, ih]
theorem pagesText_append (a b : List PageOut) : pagesText (a ++ b) = pagesText a ++ pagesText b := by
  induction a with
  | nil => rfl
  | cons x r ih => simp [pagesText, ih]
theorem pagesFigs_append (a b : List PageOut) : pagesFigs (a ++ b) = pagesFigs a ++ pagesFigs b := by
  induction a with
  | nil => rfl
  | cons x r ih => simp [pagesFigs, ih]

theorem step_fresh (env : Env) (tp : Bool) (st : St) : Step env st (fresh env tp st) [] [] := by
  unfold fresh close
  split
  · rename_i h
    have s : st.slots = [] := by
      cases c : st.slots with
      | nil => rfl
      | cons _ _ => simp [c, List.isEmpty] at h
    refine ⟨?_, ?_, ?_⟩
    · simp [text, s, textSlots]
    · simp [figs, s, figSlots]
    · intro g; exact g
  · refine ⟨?_, ?_, ?_⟩
    · simp [text, pagesText_append, pagesText, textSlots]
    · simp [figs, pagesFigs_append, pagesFigs, figSlots]
    · intro g; exact g


theorem pdg_step (env : Env) (st : St) (ds : List (Nat × Int)) :
    text (placeDeferredGo env st ds) = text st ∧
    figs (placeDeferredGo env st ds) = pagesFigs st.done.reverse ++ figSlots st.slots ++ ds.map (·.1) ∧
    (placeDeferredGo env st ds).carry = st.carry ∧
    (∀ d ∈ (placeDeferredGo env st ds).deferred, d ∈ ds) := by
  induction ds generalizing st with
  | nil => simp [placeDeferredGo, text, figs]
  | cons d ds ih =>
    obtain ⟨i, e⟩ := d
    simp only [placeDeferredGo]
    split
    · obtain ⟨a, b, c, d⟩ := ih (putSlot st e (.figure i))
      refine ⟨?_, ?_, c, fun x m => List.mem_cons_of_mem _ (d x m)⟩
      · rw [a]; simp [text, putSlot, textSlots_append, textSlots]
      · rw [b]; simp [putSlot, figSlots_append, figSlots]
    · refine ⟨rfl, by simp [figs], rfl, fun x m => m⟩

theorem step_placeDeferred (env : Env) (st : St) : Step env st (placeDeferred env st) [] [] := by
  obtain ⟨a, b, c, d⟩ := pdg_step env st st.deferred
  refine ⟨by rw [placeDeferred, a, List.append_nil], by rw [placeDeferred, b, List.append_nil]; rfl, ?_⟩
  intro ⟨g1, g2⟩
  exact ⟨fun x m => g1 x (d x m), by rw [placeDeferred, c]; exact g2⟩

theorem step_carryInto (env : Env) (st : St) : Step env st (carryInto env st) [] [] := by
  unfold carryInto
  split
  · exact Step.refl env st
  · rename_i h
    have ne : st.carry ≠ [] := by intro c; rw [c] at h; exact h rfl
    refine ⟨by simp [text], by simp [figs], fun ⟨g1, g2⟩ => ⟨g1, fun _ => g2 ne⟩⟩

theorem step_nextColumn (env : Env) (st : St) : Step env st (nextColumn env st) [] [] := by
  have := ((step_fresh env false st).trans (step_placeDeferred env _)).trans (step_carryInto env _)
  simpa using this

theorem step_nextPage (env : Env) (st : St) : Step env st (nextPage env st) [] [] := by
  have := ((step_fresh env true st).trans (step_placeDeferred env _)).trans (step_carryInto env _)
  simpa using this


theorem step_dropAtTop (env : Env) (st : St) : Step env st (dropAtTop st) [] [] := Step.same rfl rfl rfl rfl

theorem step_fit (env : Env) (st : St) (a : Int) : Step env st (fit env st a) [] [] := by
  unfold fit
  repeat' split
  all_goals first
    | exact step_dropAtTop env st
    | exact Step.same rfl rfl rfl rfl
    | simpa using (step_nextColumn env st).trans (step_dropAtTop env _)

theorem nextColumn_deferred (env : Env) (st : St) (h : st.deferred = []) : (nextColumn env st).deferred = [] := by
  unfold nextColumn placeDeferred
  obtain ⟨_, _, _, _, f5, _, _⟩ := fresh_fields env false st
  obtain ⟨_, _, _, d⟩ := pdg_step env (fresh env false st) (fresh env false st).deferred
  obtain ⟨_, _, _, _, _, _, _, c8, _⟩ := carryInto_fields env (placeDeferredGo env (fresh env false st) (fresh env false st).deferred)
  rw [c8]
  cases e : (placeDeferredGo env (fresh env false st) (fresh env false st).deferred).deferred with
  | nil => rfl
  | cons x _ => have := d x (by rw [e]; exact List.mem_cons_self _ _); rw [f5, h] at this; cases this

theorem fit_deferred (env : Env) (st : St) (a : Int) (h : st.deferred = []) : (fit env st a).deferred = [] := by
  unfold fit
  repeat' split
  all_goals first
    | exact h
    | exact nextColumn_deferred env st h

theorem step_putLineSlot (env : Env) (st : St) (e : Int) (i : Nat) :
    Step env st (putSlot st e (.line i)) [i] [] := by
  refine ⟨?_, ?_, fun g => g⟩
  · simp [text, putSlot, textSlots_append, textSlots]
  · simp [figs, putSlot, figSlots_append, figSlots]

theorem step_putFigureSlot (env : Env) (st : St) (e : Int) (i : Nat) (h : st.deferred = []) :
    Step env st (putSlot st e (.figure i)) [] [i] := by
  refine ⟨?_, ?_, fun g => g⟩
  · simp [text, putSlot, textSlots_append, textSlots]
  · simp [figs, putSlot, figSlots_append, figSlots, h]

theorem step_putPageFigureSlot (env : Env) (st : St) (e : Int) (i : Nat) :
    Step env st (putSlot st e (.pageFigure i)) [] [] := by
  refine ⟨?_, ?_, fun g => g⟩
  · simp [text, putSlot, textSlots_append, textSlots]
  · simp [figs, putSlot, figSlots_append, figSlots]

theorem splitNotes_nil (n : Nat) : splitNotes n [] = ([], []) := by cases n <;> rfl

theorem step_putLine (env : Env) (allow : Bool) (st s : St) (l : Line) (hl : LineOk env l)
    (h : putLineWithReserve allow env st l = .ok s) : Step env st s [l.id] [] := by
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
      obtain ⟨t1, g1, _⟩ := step_putLineSlot env st (env.pitchOf l.id) l.id
      refine ⟨t1, g1, fun ⟨a, b⟩ => ⟨a, fun ne => ?_⟩⟩
      cases hl with
      | inr f => exact f
      | inl e =>
        simp only [lineNotes, e, splitNotes_nil, List.append_nil] at ne
        exact b ne

theorem step_putLines (env : Env) (allow : Bool) (st s : St) (ls : List Line) (hl : ∀ l ∈ ls, LineOk env l)
    (h : putLines allow env st ls = .ok s) : Step env st s (lineIds ls) [] := by
  induction ls generalizing st with
  | nil => simp only [putLines, Except.ok.injEq] at h; subst h; exact Step.refl env _
  | cons l ls ih =>
    unfold putLines at h
    split at h
    · cases h
    · rename_i s1 e
      have a := step_putLine env allow st s1 l (hl l (List.mem_cons_self _ _)) e
      have b := ih s1 (fun x m => hl x (List.mem_cons_of_mem _ m)) h
      simpa [lineIds] using a.trans b


theorem step_unmet (env : Env) (st : St) (u : List Unmet) : Step env st { st with unmet := u } [] [] :=
  Step.same rfl rfl rfl rfl

theorem mem_take' {α : Type} : ∀ (n : Nat) (ls : List α) (x : α), x ∈ ls.take n → x ∈ ls
  | 0, _, _, m => by simp at m
  | _ + 1, [], _, m => by simp at m
  | n + 1, y :: ys, x, m => by
    simp only [List.take, List.mem_cons] at m ⊢
    cases m with
    | inl e => exact Or.inl e
    | inr m => exact Or.inr (mem_take' n ys x m)

theorem mem_drop' {α : Type} : ∀ (n : Nat) (ls : List α) (x : α), x ∈ ls.drop n → x ∈ ls
  | 0, _, _, m => m
  | _ + 1, [], _, m => by simp at m
  | n + 1, _ :: ys, x, m => List.mem_cons_of_mem _ (mem_drop' n ys x m)

theorem lineOk_take {env : Env} {ls : List Line} (n : Nat) (h : ∀ l ∈ ls, LineOk env l) :
    ∀ l ∈ ls.take n, LineOk env l := fun l m => h l (mem_take' n ls l m)

theorem lineOk_drop {env : Env} {ls : List Line} (n : Nat) (h : ∀ l ∈ ls, LineOk env l) :
    ∀ l ∈ ls.drop n, LineOk env l := fun l m => h l (mem_drop' n ls l m)

theorem trialRest_moved_step (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.moved next r)) :
    Step env st next [] [] := by
  obtain ⟨_, n, _⟩ := trialRest_moved env k start st rows fid next r h
  rw [n]; exact step_nextColumn env st

theorem trialRest_placed_step (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (hl : ∀ l ∈ rows, LineOk env l)
    (c : Nat) (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.placed c next r)) :
    Step env st next (lineIds (rows.take c)) [] := by
  unfold trialRest at h
  dsimp only at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i placed e
      injection h with h; injection h with h1 h2 _
      subst h1; subst h2
      have a := step_fit env st (sumPitch env (rows.take (if splitAtBreak k start rows.length (fitting env st rows) = 0 then max 1 (fitting env st rows) else splitAtBreak k start rows.length (fitting env st rows))))
      have b := step_putLines env false _ placed _ (lineOk_take _ hl) e
      simpa using (a.trans b).trans (step_unmet env placed _)

theorem step_addUnmet (env : Env) (st : St) (u : Unmet) : Step env st (addUnmet u st) [] [] :=
  Step.same rfl rfl rfl rfl

theorem trial_moved_step (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (next : St) (r : Keep) (h : trial env k start st rows = .ok (.moved next r)) :
    Step env st next [] [] := by
  unfold trial at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · split at h
        · simpa using (step_addUnmet env st _).trans (trialRest_moved_step env _ start _ _ _ next r h)
        · injection h with h; injection h with h1 _; subst h1; exact step_nextColumn env st
      · exact trialRest_moved_step env _ start _ _ _ next r h

theorem trial_placed_step (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (hl : ∀ l ∈ rows, LineOk env l)
    (c : Nat) (next : St) (r : Keep) (h : trial env k start st rows = .ok (.placed c next r)) :
    Step env st next (lineIds (rows.take c)) [] := by
  unfold trial at h
  split at h
  · injection h with h; injection h with h1 h2 _; subst h1; subst h2; simpa [lineIds] using Step.refl env st
  · split at h
    · simp at h
    · split at h
      · split at h
        · simpa using (step_addUnmet env st _).trans (trialRest_placed_step env _ start _ _ _ hl c next r h)
        · simp at h
      · exact trialRest_placed_step env _ start _ _ _ hl c next r h


theorem take_length' {α : Type} (ls : List α) : ls.take ls.length = ls := by
  induction ls with
  | nil => rfl
  | cons _ _ ih => simp [List.take, ih]

theorem lineIds_append (a b : List Line) : lineIds (a ++ b) = lineIds a ++ lineIds b := by
  simp [lineIds]

set_option linter.unusedVariables false in
theorem step_placeLines (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (hl : ∀ l ∈ rows, LineOk env l) (s : St) (h : placeLines env k start st rows = .ok s) :
    Step env st s (lineIds rows) [] := by
  match rows with
  | [] =>
    simp only [placeLines, Except.ok.injEq] at h; subst h; exact Step.refl env _
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
      have a := trial_moved_step env k start st _ next relaxed e
      have b := step_placeLines env relaxed start next (r :: rs) hl s h
      simpa using a.trans b
    · rename_i count next relaxed e
      have a := trial_placed_step env k start st _ hl count next relaxed e
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
        have b := step_placeLines env relaxed false (nextColumn env next) ((r :: rs).drop count) (lineOk_drop _ hl) s h
        have := (a.trans (step_nextColumn env next)).trans b
        rw [List.append_nil, List.append_nil, ← lineIds_append, List.take_append_drop] at this
        exact this
termination_by (rows.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  all_goals assumption


theorem step_flush (env : Env) (st : St) : Step env st (flushPendingRule env st) [] [] := by
  unfold flushPendingRule
  split
  · exact Step.refl env st
  · exact Step.same rfl rfl rfl rfl

set_option linter.unusedVariables false in
theorem step_placeRuled (env : Env) (st : St) (r : Ruled) (later : List Flow)
    (hl : ∀ l ∈ r.lines, LineOk env l) (s : St) (h : placeRuled env st r later = .ok s) :
    Step env st s (lineIds r.lines) [] := by
  rw [placeRuled] at h
  split at h
  · rename_i first lastLine _ _
    split at h
    · rename_i h1
      have dec : Prod.Lex (· < ·) (· < ·) (joinedRank { r with joined := false }, rank (nextColumn env (flushPendingRule env st)))
          (joinedRank r, rank st) := by
        apply Prod.Lex.left; simp [joinedRank, h1.1]
      have b := step_placeRuled env (nextColumn env (flushPendingRule env st)) { r with joined := false } later hl s h
      simpa using ((step_flush env st).trans (step_nextColumn env _)).trans b
    · split at h
      · exact step_placeLines env r.keep true st r.lines hl s h
      · split at h
        · rename_i h2
          have dec : Prod.Lex (· < ·) (· < ·) (joinedRank r, rank (fit env st (ruledExtent env st r first lastLine later)))
              (joinedRank r, rank st) :=
            Prod.Lex.right _ (I4_fit_moved env st _ h2)
          have b := step_placeRuled env _ r later hl s h
          simpa using (step_fit env st _).trans b
        · split at h
          · cases h
          · rename_i placed e
            injection h with h; subst h
            have b := step_putLines env true _ placed r.lines hl e
            simpa using ((step_fit env st _).trans (Step.same rfl rfl rfl rfl)).trans (b.trans (Step.same rfl rfl rfl rfl))
  · rename_i H
    have : r.lines = [] := by
      cases hh : r.lines with
      | nil => rfl
      | cons x xs => exact absurd (H x ((x :: xs).getLast (by simp)) (by rw [hh]; rfl) (by rw [hh]; rfl)) id
    injection h with h; subst h
    rw [this]; exact Step.refl env _
termination_by (joinedRank r, rank st)
decreasing_by
  all_goals simp_wf
  all_goals assumption


theorem step_placeWithNext (env : Env) (k : Keep) (start : Bool) (st : St) (ls : List Line)
    (l f : Nat) (later : List Flow) (hl : ∀ x ∈ ls, LineOk env x) (s : St)
    (h : placeWithNext env k start st ls l f later = .ok s) : Step env st s (lineIds ls) [] := by
  unfold placeWithNext at h
  split at h
  · cases h
  · rename_i full e
    split at h
    · injection h with h; subst h; exact step_placeLines env k start st ls hl _ e
    · split at h
      · injection h with h; subst h; exact step_placeLines env k start st ls hl _ e
      · split at h
        · cases h
        · rename_i before e2
          have a := step_placeLines env k start st _ (lineOk_take _ hl) before e2
          have m : Step env before (afterFront env before) [] [] := by
            unfold afterFront; split
            · exact Step.refl env _
            · exact step_nextColumn env _
          have b := step_placeLines env k _ _ _ (lineOk_drop _ hl) s h
          have := (a.trans m).trans b
          rw [List.append_nil, ← lineIds_append, List.take_append_drop] at this
          exact this

theorem step_placeRuledKeeping (env : Env) (st : St) (r : Ruled) (later : List Flow)
    (hl : ∀ l ∈ r.lines, LineOk env l) (s : St) (h : placeRuledKeeping env st r later = .ok s) :
    Step env st s (lineIds r.lines) [] := by
  unfold placeRuledKeeping at h
  split at h
  · cases h
  · rename_i full e
    split at h
    · split at h
      · have b := step_placeRuled env _ { r with joined := false } later hl s h
        simpa using ((step_flush env st).trans (step_nextColumn env _)).trans b
      · injection h with h; subst h; exact step_placeRuled env st r later hl _ e
    · injection h with h; subst h; exact step_placeRuled env st r later hl _ e

theorem step_waitFor (env : Env) (u : Unmet) (q : Nat × Bool) (st : St) : Step env st (waitFor u q st) [] [] :=
  Step.same rfl rfl rfl rfl

theorem step_waitForPrior (env : Env) (u : Unmet) (q : Nat × Bool) (st : St) :
    Step env st (waitForPrior u q st) [] [] := by
  unfold waitForPrior; split
  · exact step_addUnmet env st u
  · exact step_waitFor env u q st

theorem pagesText_map (f : PageOut → PageOut) (hf : ∀ p, (f p).slots = p.slots) (ps : List PageOut) :
    pagesText (ps.map f).reverse = pagesText ps.reverse ∧ pagesFigs (ps.map f).reverse = pagesFigs ps.reverse := by
  induction ps with
  | nil => simp
  | cons p ps ih =>
    simp only [List.map, List.reverse_cons, pagesText_append, pagesFigs_append, ih.1, ih.2, pagesText, pagesFigs, hf]
    trivial

theorem step_checkWait (env : Env) (acc : St) (w : Wait) : Step env acc (checkWait acc w) [] [] := by
  unfold checkWait
  split
  · exact Step.refl env acc
  · split
    · exact step_addUnmet env acc _
    · obtain ⟨a, b⟩ := pagesText_map (markUnmet w) (fun o => by unfold markUnmet; split <;> rfl) acc.done
      refine ⟨?_, ?_, fun g => g⟩
      · simp only [text]; rw [a]; simp
      · simp only [figs]; rw [b]; simp

theorem step_checkWaits (env : Env) (st : St) : Step env st (checkWaits st) [] [] := by
  unfold checkWaits
  have : ∀ (ws : List Wait) (a : St), Step env a (ws.foldl checkWait a) [] [] := by
    intro ws
    induction ws with
    | nil => intro a; exact Step.refl env a
    | cons w ws ih => intro a; simpa using (step_checkWait env a w).trans (ih _)
  simpa using (Step.same (s := { st with waits := [] }) rfl rfl rfl rfl).trans (this st.waits _)


set_option linter.unusedVariables false in
theorem step_drainCarry (env : Env) (st : St) : Step env st (drainCarry env st) [] [] := by
  rw [drainCarry]
  split
  · rename_i h
    have dec := I4_drain_rank env st h
    simpa using (step_nextColumn env st).trans (step_drainCarry env (nextColumn env st))
  · exact Step.refl env st
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem step_parityStart (env : Env) (accept : Nat → Bool) (st : St) :
    Step env st (parityStart env accept st) [] [] := by
  have a := step_drainCarry env st
  have b : Step env (drainCarry env st)
      (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st else nextPage env (drainCarry env st)) [] [] := by
    split
    · exact Step.refl env _
    · exact step_nextPage env _
  have c := a.trans b
  simp only [List.append_nil] at c
  unfold parityStart
  dsimp only
  generalize (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st else nextPage env (drainCarry env st)) = nx at c
  split
  · exact c
  · split
    · refine ⟨?_, ?_, fun g => c.2.2 g⟩
      · have := c.1; simp only [text, List.append_nil] at this; simp [text, pagesText_append, pagesText, textSlots, this]
      · have := c.2.1; simp only [figs, List.append_nil] at this; simp [figs, pagesFigs_append, pagesFigs, figSlots]; simpa using this
    · simpa using c.trans (step_nextPage env nx)

theorem step_breakAt (env : Env) (k : BreakKind) (st : St) : Step env st (breakAt env k st) [] [] := by
  cases k <;> unfold breakAt
  · exact step_nextColumn env st
  · exact step_nextPage env st
  · exact step_parityStart env _ st
  · exact step_parityStart env _ st

set_option linter.unusedVariables false in
theorem step_judgeNeed (env : Env) (b : Int) (st : St) : Step env st (judgeNeed env b st) [] [] := by
  rw [judgeNeed]
  split
  · exact Step.refl env st
  · split
    · rename_i h
      have dec := I4_nextColumn_rank env st (Or.inr h.2)
      simpa using (step_nextColumn env st).trans (step_judgeNeed env b (nextColumn env st))
    · split
      · exact Step.refl env st
      · rename_i h
        have dec := I4_nextColumn_rank env st (Or.inl (by simpa using h))
        simpa using (step_nextColumn env st).trans (step_judgeNeed env b (nextColumn env st))
termination_by rank st
decreasing_by
  all_goals simp_wf
  all_goals assumption


theorem mem_append' {α : Type} {x : α} : ∀ {a b : List α}, x ∈ a ++ b → x ∈ a ∨ x ∈ b
  | [], _, m => Or.inr m
  | y :: ys, b, m => by
    cases m with
    | head => exact Or.inl (List.Mem.head _)
    | tail _ m => cases mem_append' m with
      | inl m => exact Or.inl (List.Mem.tail _ m)
      | inr m => exact Or.inr m

def FlowOk (env : Env) (f : Flow) : Prop := ∀ l ∈ flowLines f, LineOk env l

theorem step_adjustLines (env : Env) (n : Int) (st : St) : Step env st (adjustLines env n st) [] [] :=
  Step.same rfl rfl rfl rfl

theorem step_placeFlow (env : Env) (st : St) (f : Flow) (hf : FlowOk env f) (s : St)
    (h : placeFlow env st f = .ok s) : Step env st s (lineIds (flowLines f)) (flowFigs f) := by
  cases f with
  | paragraph k ls => exact step_placeLines env k true st ls hf s h
  | continued k ls => exact step_placeLines env k false st ls hf s h
  | ruled r => exact step_placeRuled env st r [] hf s h
  | space n => simp only [placeFlow, Except.ok.injEq] at h; subst h; exact Step.same rfl rfl rfl rfl
  | blank n => simp only [placeFlow, Except.ok.injEq] at h; subst h; exact Step.same rfl rfl rfl rfl
  | brk k => simp only [placeFlow, Except.ok.injEq] at h; subst h; exact step_breakAt env k st
  | adjustLines n => simp only [placeFlow, Except.ok.injEq] at h; subst h; exact step_adjustLines env n st
  | noBreak => simp only [placeFlow, Except.ok.injEq] at h; subst h; exact step_waitForPrior env _ _ st
  | keepNext n => simp only [placeFlow, Except.ok.injEq] at h; subst h; exact step_waitForPrior env _ _ st
  | noBreakLines n =>
    simp only [placeFlow] at h
    split at h
    · injection h with h; subst h; exact Step.refl env st
    · injection h with h; subst h; exact step_waitForPrior env _ _ st
  | needLines n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    have : Step env st (if env.capacity < (n : Int) * env.pagePitch then addUnmet (.needLines n) st else st) [] [] := by
      split
      · exact step_addUnmet env st _
      · exact Step.refl env st
    simpa using this.trans (step_judgeNeed env _ _)
  | pageFigure i =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    have : Step env st (if empty st = true then st else nextPage env st) [] [] := by
      split
      · exact Step.refl env st
      · exact step_nextPage env st
    simpa [flowFigs] using (this.trans (step_putPageFigureSlot env _ env.capacity i)).trans (step_nextPage env _)
  | figure i e =>
    simp only [placeFlow] at h
    split at h
    · cases h
    · rename_i big
      split at h
      · injection h with h; subst h
        refine ⟨by simp [text, flowLines, lineIds], by simp [figs, flowFigs], fun ⟨g1, g2⟩ => ⟨?_, g2⟩⟩
        intro d m
        cases mem_append' m with
        | inl m => exact g1 d m
        | inr m => simp at m; subst m; exact Int.not_lt.1 big
      · split at h
        · injection h with h; subst h
          refine ⟨by simp [text, flowLines, lineIds], by simp [figs, flowFigs], fun ⟨g1, g2⟩ => ⟨?_, g2⟩⟩
          intro d m
          cases mem_append' m with
          | inl m => exact g1 d m
          | inr m => simp at m; subst m; exact Int.not_lt.1 big
        · rename_i nd _
          injection h with h; subst h
          have d0 : st.deferred = [] := Decidable.of_not_not nd
          simpa [flowLines, lineIds, flowFigs] using (step_fit env st e).trans
            (step_putFigureSlot env _ e i (fit_deferred env st e d0))


theorem step_beforeOf (env : Env) (st : St) (flow : Flow) (rest : List Flow) :
    Step env st (beforeOf env st flow rest) [] [] := by
  have a : Step env st (if st.blankActive ∧ occupies flow ∧ empty st = false ∧
      room env st < min env.capacity (st.pending + env.firstNeed (decide (0 < st.notesUsed)) 1 (flow :: rest))
      then nextColumn env st else st) [] [] := by
    split
    · exact step_nextColumn env st
    · exact Step.refl env st
  unfold beforeOf
  dsimp only
  split
  · exact a
  · simpa using a.trans (Step.same rfl rfl rfl rfl)

theorem step_placeBody (env : Env) (b : St) (flow : Flow) (rest : List Flow) (hf : FlowOk env flow) (s : St)
    (h : placeBody env b flow rest = .ok s) : Step env b s (lineIds (flowLines flow)) (flowFigs flow) := by
  unfold placeBody at h
  cases flow with
  | paragraph k ls =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact step_placeFlow env b _ hf s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h; exact step_placeWithNext env k true b ls l f later hf s h
  | continued k ls =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact step_placeFlow env b _ hf s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h; exact step_placeWithNext env k false b ls l f later hf s h
  | noBreak => simp only [Except.ok.injEq] at h; subst h; exact step_waitForPrior env _ _ b
  | keepNext n => simp only [Except.ok.injEq] at h; subst h; exact step_waitForPrior env _ _ b
  | noBreakLines n =>
    simp only at h
    split at h
    · injection h with h; subst h; exact step_waitForPrior env _ _ b
    · exact step_placeFlow env b _ hf s h
  | ruled r => exact step_placeRuledKeeping env b r rest hf s h
  | figure i e => exact step_placeFlow env b _ hf s h
  | pageFigure i => exact step_placeFlow env b _ hf s h
  | space n => exact step_placeFlow env b _ hf s h
  | blank n => exact step_placeFlow env b _ hf s h
  | brk k => exact step_placeFlow env b _ hf s h
  | needLines n => exact step_placeFlow env b _ hf s h
  | adjustLines n => exact step_placeFlow env b _ hf s h

theorem step_placeNext (env : Env) (st : St) (flow : Flow) (rest : List Flow) (hf : FlowOk env flow) (s : St)
    (h : placeNext env st flow rest = .ok s) : Step env st s (lineIds (flowLines flow)) (flowFigs flow) := by
  unfold placeNext at h
  split at h
  · cases h
  · rename_i p e
    injection h with h; subst h
    have a := (step_beforeOf env st flow rest).trans (step_placeBody env _ flow rest hf p e)
    have c : Step env p (if occupies flow = true then checkWaits p else p) [] [] := by
      split
      · exact step_checkWaits env p
      · exact Step.refl env p
    simpa using a.trans c

theorem step_placeAll (env : Env) (st : St) (flows : List Flow) (hf : ∀ f ∈ flows, FlowOk env f) (s : St)
    (h : placeAll env st flows = .ok s) : Step env st s (sourceText flows) (sourceFigs flows) := by
  induction flows generalizing st with
  | nil => simp only [placeAll, Except.ok.injEq] at h; subst h; exact Step.refl env _
  | cons f fs ih =>
    simp only [placeAll] at h
    split at h
    · cases h
    · rename_i p e
      have a := step_placeNext env st f fs (hf f (List.mem_cons_self _ _)) p e
      have b := ih p (fun x m => hf x (List.mem_cons_of_mem _ m)) h
      simpa [sourceText, sourceFigs] using a.trans b


theorem bind_nil {α β : Type} (g : α → List β) : ∀ {xs : List α}, xs.bind g = [] → ∀ x ∈ xs, g x = []
  | [], _, x, m => by cases m
  | y :: ys, h, x, m => by
    have e : g y ++ ys.bind g = [] := h
    cases hy : g y with
    | cons _ _ => rw [hy] at e; cases e
    | nil =>
      rw [hy, List.nil_append] at e
      cases m with
      | head => exact hy
      | tail _ m => exact bind_nil g e x m

theorem mem_append_left' {α : Type} {x : α} : ∀ {a : List α} (b : List α), x ∈ a → x ∈ a ++ b
  | _ :: _, _, .head _ => .head _
  | _ :: _, b, .tail _ m => .tail _ (mem_append_left' b m)

theorem mem_append_right' {α : Type} {x : α} : ∀ (a : List α) {b : List α}, x ∈ b → x ∈ a ++ b
  | [], _, m => m
  | _ :: a, _, m => .tail _ (mem_append_right' a m)

theorem mem_bind' {α β : Type} {g : α → List β} {x : α} {y : β} : ∀ {xs : List α}, x ∈ xs → y ∈ g x → y ∈ xs.bind g
  | _ :: ys, .head _, my => by rw [List.cons_bind]; exact mem_append_left' _ my
  | z :: _, .tail _ m, my => by rw [List.cons_bind]; exact mem_append_right' (g z) (mem_bind' m my)

theorem checkNotes_ok (env : Env) (flows : List Flow) (h : checkNotes env flows = none) :
    ∀ f ∈ flows, FlowOk env f := by
  unfold checkNotes at h
  split at h
  · split at h
    · cases h
    · rename_i fits
      exact fun _ _ _ _ => Or.inr (Int.not_lt.1 fits)
  · rename_i e
    intro f m l ml
    exact Or.inl (bind_nil (fun l => l.notes) e l (mem_bind' m ml))

theorem close_pages (env : Env) (st : St) :
    pagesText (close env st).done.reverse = text st ∧
    pagesFigs (close env st).done.reverse = pagesFigs st.done.reverse ++ figSlots st.slots := by
  unfold close
  split
  · rename_i h
    have s : st.slots = [] := by
      cases c : st.slots with
      | nil => rfl
      | cons _ _ => simp [c, List.isEmpty] at h
    simp [text, s, textSlots, figSlots]
  · simp [text, pagesText_append, pagesText, pagesFigs_append, pagesFigs]

theorem drainOk_of_good (env : Env) (st : St) (hp : 0 < env.pagePitch) (g : Good env st) : drainOk env st = true := by
  unfold drainOk
  simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq]
  constructor
  · cases c : st.carry with
    | nil => exact Or.inl rfl
    | cons _ _ => exact Or.inr ⟨hp, g.2 (by rw [c]; intro h; cases h)⟩
  · cases d : st.deferred with
    | nil => trivial
    | cons x _ => simp only [decide_eq_true_eq]; exact g.1 x (by rw [d]; exact List.mem_cons_self _ _)

set_option linter.unusedVariables false in
theorem drain_empty (env : Env) (hp : 0 < env.pagePitch) (st : St) (g : Good env st) :
    (drainCarry env st).deferred = [] := by
  rw [drainCarry]
  split
  · rename_i h
    have dec := I4_drain_rank env st h
    exact drain_empty env hp (nextColumn env st) ((step_nextColumn env st).2.2 g)
  · rename_i h
    have ok := drainOk_of_good env st hp g
    have : (st.carry.isEmpty && st.deferred.isEmpty) = true := by
      cases e : (st.carry.isEmpty && st.deferred.isEmpty)
      · exact absurd ⟨e, ok⟩ h
      · rfl
    simp only [Bool.and_eq_true] at this
    cases d : st.deferred with
    | nil => rfl
    | cons _ _ => rw [d] at this; cases this.2
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

/-- Invariant 4: the free placement is a total function; every column
    loop ends (`I4_nextColumn_rank`, `I4_fit_moved`, `I4_drain_rank`). -/
theorem I4_paginate_ends (env : Env) (flows : List Flow) : ∃ r, paginate env flows = r := ⟨_, rfl⟩

/-- Invariant 5: the lines of the paragraphs and the ruled blocks are
    placed once each, in the order of the manuscript. -/
theorem I5_paginate_text (env : Env) (flows : List Flow) (pages : List PageOut)
    (h : paginate env flows = .ok pages) : pagesText pages = sourceText flows := by
  unfold paginate at h
  split at h
  · cases h
  · rename_i hn
    split at h
    · cases h
    · rename_i final e
      dsimp only at h
      have a := (step_placeAll env _ flows (checkNotes_ok env flows hn) final e).trans (step_drainCarry env final)
      have c := close_pages env (drainCarry env final)
      have t : text (initial env) = [] := rfl
      have a1 := a.1
      rw [t, List.nil_append, List.append_nil] at a1
      split at h
      · rename_i r
        injection h with h; subst h
        rw [r] at c; rw [← a1, ← c.1]; rfl
      · injection h with h; subst h
        rw [c.1, a1]

/-- Invariant 5: the figures that are not turned are placed once each, in
    the order of the manuscript, for a page line pitch above 0. -/
theorem I5_paginate_figures (env : Env) (hp : 0 < env.pagePitch) (flows : List Flow) (pages : List PageOut)
    (h : paginate env flows = .ok pages) : pagesFigs pages = sourceFigs flows := by
  unfold paginate at h
  split at h
  · cases h
  · rename_i hn
    split at h
    · cases h
    · rename_i final e
      dsimp only at h
      have a := (step_placeAll env _ flows (checkNotes_ok env flows hn) final e).trans (step_drainCarry env final)
      have d := drain_empty env hp final ((step_placeAll env _ flows (checkNotes_ok env flows hn) final e).2.2
        ⟨fun _ m => (by cases m), fun c => absurd rfl c⟩)
      have c := close_pages env (drainCarry env final)
      have f0 : figs (initial env) = [] := rfl
      have fa := a.2.1
      rw [f0, List.nil_append, List.append_nil] at fa
      simp only [figs, d, List.map, List.append_nil] at fa
      split at h
      · rename_i r
        injection h with h; subst h
        rw [r] at c; rw [← fa, ← c.2]; rfl
      · injection h with h; subst h
        rw [c.2, fa]


end PhysicalPagination
