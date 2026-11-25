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

/-- `FRuled`: its body is `RuledLines keep lines` when `heading` is none,
    and `RuledHeading recto extent lines` when it is `some (recto, extent)`;
    `keep` is then not read. -/
structure Ruled where
  id : Nat
  before : Option RuleSide
  after : Option RuleSide
  joined : Bool
  nextOverhang : Int
  keep : Keep
  lines : List Line
  heading : Option (Bool × Int)
  deriving DecidableEq, Repr

/-- `KeepParts` of Golem.Project.Style: the unit a book part is kept in. -/
inductive PartUnit where
  | column | page | spread
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
  /-- `FKeepNext`: its lines and the id of its span; the keep a visible
      separator is held by has the span of the separator (root ADR 0398 I7). -/
  | keepNext (n : Nat) (sp : Nat)
  | ruled (r : Ruled)
  /-- `FSection` of a section: the start the flows after it need. -/
  | start (k : BreakKind)
  /-- `FSwitchColumns` with the number of columns of the set. -/
  | switchColumns (cols : Nat)
  | restoreColumns
  /-- `FHeading`: recto, its extent and its lines. -/
  | heading (recto : Bool) (extent : Int) (ls : List Line)
  | defTerm (ls : List Line)
  /-- `FStanza`: its verse lines, each the lines it is broken into. -/
  | stanza (k : Keep) (verses : List (List Line))
  /-- `FCode`: the caption, the rows of the first part, continued, the
      grid lines `codeSpan` gives for 0, 1, 2, ... rows, and the rows. -/
  | code (caption : Int) (first : Nat) (continued : Bool) (spans : List Nat) (rows : List Line)
  /-- `FWrapped`: the figure, its extent and the lines beside it. -/
  | wrapped (id : Nat) (extent : Int) (beside : List Line)
  /-- `FTable`: the space before it, the header, the rows, the caption and
      whether the caption is below. -/
  | table (id : Nat) (before : Int) (header : List Line) (rows : List (List Line)) (caption : List Line) (below : Bool)
  /-- `FBoxed ident before after body`. -/
  | boxed (id : Nat) (before after : Int) (body : List Flow)
  /-- `FBookPart unit source kind identifiers body`, without the source and
      the kind. -/
  | bookPart (unit : PartUnit) (ids : List Nat) (body : List Flow)
  deriving Repr

inductive Slot where
  | line (id : Nat)
  | figure (id : Nat)
  | pageFigure (id : Nat)
  /-- `SHeading`: the first line and the number of lines. -/
  | heading (id : Nat) (n : Nat)
  /-- `SCode`: the rows of the part (Physical.hs keeps the first and the
      number) and the grid lines it takes. -/
  | code (ids : List Nat) (grid : Nat)
  /-- `SWrapped`: a wrapped figure, of no extent. -/
  | wrapped (id : Nat)
  /-- A header line of a table repeated in a later column: `SLine` in
      Physical.hs, not counted as text. -/
  | repeated (id : Nat)
  deriving DecidableEq, Repr

inductive AdjustLimit where
  | noRoom | linesPlaced | oneLine
  deriving DecidableEq, Repr

inductive Unmet where
  | noBreak
  /-- `UnmetKeepNext`, by the id of the span of its keep-with-next. -/
  | keepNext (sp : Nat)
  | needLines (n : Nat)
  | adjust (chosen : Int) (why : AdjustLimit)
  | droppedBlank
  | splitKept (id : Nat)
  /-- `ShortPart`: the first part (true) or the last, the first line,
      the lines asked for and the lines placed. -/
  | shortPart (firstPart : Bool) (id : Nat) (wanted placed : Nat)
  /-- `TallHeadingExtent`: the first line, the extent and the room left. -/
  | tallHeading (id : Nat) (extent room : Int)
  /-- `SplitBookPart`: of the tail of a table (true) or of a book part. -/
  | splitPart (table : Bool) (unit : PartUnit)
  deriving DecidableEq, Repr

inductive Failure where
  | lineTooTall (id : Nat)
  | footnoteTooTall (id : Nat)
  | figureTooTall (id : Nat)
  | headingTooTall (id : Nat)
  | codeTooTall (id : Nat)
  | tableTooTall (id : Nat)
  | tableCaptionTooTall (id : Nat)
  | boxTooTall (id : Nat)
  /-- A flow that fits in no column: Physical.hs goes on to the next
      column for ever (see `seek`). -/
  | noProgress (id : Nat)
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

/-- `Waiting` of Physical.hs: a figure waiting for room, or a turned
    figure waiting for a page of its own. -/
inductive Waiting where
  | figure (id : Nat) (extent : Int)
  | turned (id : Nat)
  deriving DecidableEq, Repr

def Waiting.id : Waiting → Nat
  | .figure i _ => i
  | .turned i => i

def Waiting.isTurned : Waiting → Bool
  | .turned _ => true
  | .figure _ _ => false

/-- A figure waiting fits in an empty column. -/
def Waiting.fits (capacity : Int) : Waiting → Prop
  | .figure _ e => e ≤ capacity
  | .turned _ => True

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
  deferred : List Waiting
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
  /-- `psBoxes`: the box, the start and the end of each part in the column. -/
  boxes : List (Nat × Int × Int)
  /-- `psReserved`: the notes at the foot of the page that the columns of
      a set started on it keep clear (root ADR 0025). -/
  reserved : Int
  /-- `psSetAdjustment`: what `FAdjustLines` changes in every column of a
      set started on this page (root ADR 0441). -/
  setAdjust : Int
  /-- The places of the rules after (`psRules` with `prBefore` false) in
      the column: a ruled heading reads them for its rule before (PR #1151). -/
  afterRules : List Int

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
  /-- `physicalHeadingBounds`: the face of the first line of a heading from
      its top and the end of the face of its last line. -/
  headingBounds : Nat → Option (Int × Int)
  /-- `physicalWrappedBefore`: the gap before a line beside or after a
      wrapped figure. -/
  wrappedBefore : Nat → Int
  /-- `physicalBoxPadding`: the padding of a box. -/
  boxPadding : Nat → Option Int
  /-- `firstNeed` of Physical.hs: the length the flows ahead need. -/
  firstNeed : Bool → Nat → List Flow → Int
  /-- `physicalRetention`: the unit of the book part being placed, other
      than column. -/
  retention : Option PartUnit
  /-- `physicalHeld`: whether a keep-with-next, by the id of its span, is
      the keep of a visible separator (root ADR 0398 I7). -/
  held : Nat → Bool

def initial (env : Env) : St :=
  ⟨1, 0, env.columns, env.firstLine, 0, 0, [], [], [], [], [], 0, [], 0, false, 0, none, [], [], 0, 0, []⟩

def limit (env : Env) (st : St) : Int := env.capacity + st.adjust
def room (env : Env) (st : St) : Int := limit env st - st.used - st.notesUsed
def empty (st : St) : Bool := st.slots.isEmpty && st.notes.isEmpty && st.used == st.firstLine
def isHeading : Slot → Bool
  | .heading _ _ => true
  | _ => false
/-- `headingOnly`: the column holds headings and nothing else. -/
def headingOnly (st : St) : Bool := !st.slots.isEmpty && st.slots.all (fun s => isHeading s.2)
def addUnmet (u : Unmet) (st : St) : St := { st with unmet := st.unmet ++ [u] }

def close (env : Env) (st : St) : St :=
  if st.slots.isEmpty ∧ st.notes.isEmpty then st
  else { st with done := ⟨st.page, st.column, false, st.slots, st.notes, limit env st, st.unmet⟩ :: st.done, unmet := [] }

def putSlot (st : St) (extent : Int) (s : Slot) : St :=
  { st with slots := st.slots ++ [(st.used, s)], used := st.used + extent }

/-- The loop of `placeDeferred`. -/
def placeDeferredGo (env : Env) (st : St) : List Waiting → St
  | .figure i e :: later =>
    if e ≤ room env st then placeDeferredGo env (putSlot st e (.figure i)) later
    else { st with deferred := .figure i e :: later }
  | ds => { st with deferred := ds }

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
    let available := limit env st - st.used - st.notesUsed - env.separator
    let count := (max 0 (Int.fdiv available env.pagePitch)).toNat
    let p := splitCarried count st.carry
    let extent := env.separator + (partsLines p.1 : Int) * env.pagePitch
    { st with notes := p.1, carry := p.2, notesUsed := st.notesUsed + if p.1.isEmpty then 0 else extent }

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
    notesUsed := if pageEnd then 0 else st.reserved
    reserved := if pageEnd then 0 else st.reserved
    slots := []
    notes := []
    adjust := if pageEnd then 0 else st.setAdjust
    setAdjust := if pageEnd then 0 else st.setAdjust
    pending := 0
    blankActive := false
    join := none
    boxes := []
    afterRules := [] }

/-- The loop of `placeTurned`: each turned figure waiting at the start of a
    page takes that page. -/
def placeTurnedGo (env : Env) (st : St) : List Waiting → St
  | .turned i :: later =>
    placeTurnedGo env { st with
      done := ⟨st.page, 0, false, [(0, .pageFigure i)], [], limit env st, []⟩ :: st.done
      page := st.page + 1 } later
  | ds => { st with deferred := ds }

def placeTurned (env : Env) (st : St) : St := placeTurnedGo env st st.deferred

/-- The new column, with the turned figures placed when it starts a page. -/
def opened (env : Env) (toPage : Bool) (st : St) : St :=
  if toPage || decide (st.columns ≤ st.column + 1) then placeTurned env (fresh env toPage st) else fresh env toPage st

def nextColumn (env : Env) (st : St) : St := carryInto env (placeDeferred env (opened env false st))
def nextPage (env : Env) (st : St) : St := carryInto env (placeDeferred env (opened env true st))

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
  let emptyish := empty st || (headingOnly st && decide (0 < count))
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

/-- `checkPhysicalNotes` of the rows `trialParagraphPartLimit` takes. -/
def checkRows (env : Env) (rows : List Line) : Option Failure :=
  match rows.bind (fun l => l.notes) with
  | n :: _ => if env.capacity < env.separator + env.pagePitch then some (.footnoteTooTall n.id) else none
  | [] => none

/-- `go` of `trialParagraphPartLimit`. -/
def trialFrom (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) : Except Failure Part :=
  match rows with
  | [] => .ok (.placed 0 st k)
  | first :: _ =>
    if env.capacity < env.pitchOf first.id then .error (.lineTooTall first.id)
    else if k.all ∧ start ∧ fitting env st rows < rows.length then
      if empty st || headingOnly st then trialRest env { k with all := false } start (addUnmet (.splitKept first.id) st) rows first.id
      else .ok (.moved (nextColumn env st) k)
    else trialRest env k start st rows first.id

/-- `trialParagraphPartLimit` without a wrap region or a prefix limit. -/
def trial (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) : Except Failure Part :=
  match checkRows env rows with
  | some e => .error e
  | none => trialFrom env k start st rows

/-! ## The rank the column loops decrease -/

def carryWeight (ps : List NotePart) : Nat := ps.foldr (fun p a => p.2.2 + 1 + a) 0
/-- What waits for a later column: the figures sent on and the lines of
    the notes carried on, each note counted one more. -/
def waiting (st : St) : Nat := st.deferred.length + carryWeight st.carry
def columnsLeft (st : St) : Nat := st.columns - (st.column + 1)
/-- What a column made shorter weighs: the columns left on the page when
    every column of the set is made shorter (`setAdjust < 0`), as the next
    one is too, or 2 when this column alone is. -/
def adjustWeight (st : St) : Nat :=
  if st.setAdjust < 0 then 4 * columnsLeft st + 4 else if st.adjust < 0 then 2 else 0
/-- The weight of one thing waiting, more than any `adjustWeight` and
    emptiness of a column of the set. -/
def unitWeight (st : St) : Nat := 4 * st.columns + 8
def rank (st : St) : Nat :=
  waiting st * unitWeight st + adjustWeight st + (if empty st then 0 else 1)
def keepRank (k : Keep) : Nat := if k.all then 1 else 0

/-- `placeDeferredGo` only puts figures into the column. -/
theorem placeDeferredGo_fields (env : Env) (st : St) (ds : List Waiting) :
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
    cases d with
    | turned i => simp [placeDeferredGo]
    | figure i e =>
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
    generalize (max 0 (Int.fdiv (limit env st - st.used - st.notesUsed - env.separator) env.pagePitch)).toNat = n
    obtain ⟨a, b, c⟩ := splitCarried_weight n st.carry
    refine ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, a, fun e => Or.inl ?_⟩
    cases n with
    | zero =>
      cases d : st.carry with
      | nil => exact absurd d ne
      | cons p ps => simp [splitCarried]
    | succ m => have := b (by omega) ne; omega

theorem adjustWeight_lt (st : St) : adjustWeight st + 1 < unitWeight st := by
  unfold adjustWeight unitWeight columnsLeft; split
  · omega
  · split <;> omega

theorem rank_le (st : St) : rank st < (waiting st + 1) * unitWeight st := by
  have := adjustWeight_lt st
  rw [Nat.succ_mul]; unfold rank; split <;> omega

theorem rank_low (st : St) : waiting st * unitWeight st ≤ rank st := by
  unfold rank; omega

/-- A column that is not empty or is made shorter weighs more than the
    things waiting. -/
theorem rank_pos (st : St) (h : empty st = false ∨ st.adjust < 0) : waiting st * unitWeight st < rank st := by
  have : 0 < adjustWeight st + (if empty st then 0 else 1) := by
    unfold adjustWeight
    cases h with
    | inl h => simp [h]
    | inr h => split <;> (try rw [if_pos h]) <;> split <;> omega
  have r : rank st = waiting st * unitWeight st + (adjustWeight st + (if empty st then 0 else 1)) := by
    unfold rank; omega
  omega

theorem adjustWeight_congr {a b : St} (h1 : a.setAdjust = b.setAdjust) (h2 : a.adjust = b.adjust)
    (h3 : a.column = b.column) (h4 : a.columns = b.columns) : adjustWeight a = adjustWeight b := by
  simp only [adjustWeight, columnsLeft, h1, h2, h3, h4]

/-- The new column weighs less than the column before, or nothing: it is
    made shorter only when every column of the set is, and then it leaves
    one column fewer on the page. -/
theorem fresh_weight (env : Env) (tp : Bool) (st : St) :
    adjustWeight (fresh env tp st) < adjustWeight st ∨ adjustWeight (fresh env tp st) = 0 := by
  unfold adjustWeight columnsLeft fresh close
  by_cases pe : (tp || decide (st.columns ≤ st.column + 1)) = true
  · right; split <;> simp [pe]
  · have pe' : ¬st.columns ≤ st.column + 1 := by
      intro c; apply pe; simp [c]
    simp only [Bool.not_eq_true] at pe
    by_cases sa : st.setAdjust < 0
    · left; split <;> simp [pe, sa] <;> omega
    · right; split <;> simp [pe, sa] <;> omega

/-- The next column, before the figures and notes waiting are placed: it is
    empty and has not been made shorter. -/
theorem fresh_fields (env : Env) (tp : Bool) (st : St) :
    (fresh env tp st).slots = [] ∧ (fresh env tp st).notes = [] ∧
    (fresh env tp st).used = (fresh env tp st).firstLine ∧
    (adjustWeight (fresh env tp st) < adjustWeight st ∨ adjustWeight (fresh env tp st) = 0) ∧
    (fresh env tp st).deferred = st.deferred ∧ (fresh env tp st).carry = st.carry ∧
    (fresh env tp st).columns = st.columns := by
  refine ⟨?_, ?_, ?_, fresh_weight env tp st, ?_⟩ <;> unfold fresh close <;> split <;> simp

/-- `placeTurnedGo` only closes pages of turned figures. -/
theorem placeTurnedGo_fields (env : Env) (st : St) (ds : List Waiting) :
    (placeTurnedGo env st ds).slots = st.slots ∧ (placeTurnedGo env st ds).notes = st.notes ∧
    (placeTurnedGo env st ds).used = st.used ∧ (placeTurnedGo env st ds).firstLine = st.firstLine ∧
    (placeTurnedGo env st ds).adjust = st.adjust ∧ (placeTurnedGo env st ds).carry = st.carry ∧
    (placeTurnedGo env st ds).notesUsed = st.notesUsed ∧ (placeTurnedGo env st ds).columns = st.columns ∧
    (placeTurnedGo env st ds).column = st.column ∧
    (placeTurnedGo env st ds).deferred.length ≤ ds.length ∧
    (∀ d ∈ (placeTurnedGo env st ds).deferred, d ∈ ds) ∧
    (∀ i later, ds = .turned i :: later → (placeTurnedGo env st ds).deferred.length < ds.length) ∧
    ((placeTurnedGo env st ds).deferred.length = ds.length →
      (placeTurnedGo env st ds).deferred = ds ∧ (placeTurnedGo env st ds).done = st.done) := by
  induction ds generalizing st with
  | nil => simp [placeTurnedGo]
  | cons d ds ih =>
    cases d with
    | figure i e => simp [placeTurnedGo]
    | turned i =>
      simp only [placeTurnedGo]
      obtain ⟨a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, _⟩ := ih { st with
        done := ⟨st.page, 0, false, [(0, .pageFigure i)], [], limit env st, []⟩ :: st.done, page := st.page + 1 }
      refine ⟨a1, a2, a3, a4, a5, a6, a7, a8, a9, by simp; omega, fun x m => List.mem_cons_of_mem _ (a11 x m),
        fun _ _ _ => by simp; omega, fun h => ?_⟩
      simp at h; omega

theorem placeTurnedGo_setAdjust (env : Env) (st : St) (ds : List Waiting) :
    (placeTurnedGo env st ds).setAdjust = st.setAdjust := by
  induction ds generalizing st with
  | nil => rfl
  | cons d ds ih =>
    cases d with
    | figure i e => rfl
    | turned i => simp only [placeTurnedGo]; rw [ih]

theorem placeDeferredGo_setAdjust (env : Env) (st : St) (ds : List Waiting) :
    (placeDeferredGo env st ds).setAdjust = st.setAdjust := by
  induction ds generalizing st with
  | nil => rfl
  | cons d ds ih =>
    cases d with
    | figure i e => simp only [placeDeferredGo]; split <;> (try rw [ih]) <;> rfl
    | turned i => rfl

theorem carryInto_setAdjust (env : Env) (st : St) : (carryInto env st).setAdjust = st.setAdjust := by
  unfold carryInto; split <;> rfl

/-- The new column: empty, weighing less than the column before or
    nothing, with no more waiting. -/
theorem opened_fields (env : Env) (tp : Bool) (st : St) :
    (opened env tp st).slots = [] ∧ (opened env tp st).notes = [] ∧
    (opened env tp st).used = (opened env tp st).firstLine ∧
    (adjustWeight (opened env tp st) < adjustWeight st ∨ adjustWeight (opened env tp st) = 0) ∧
    (opened env tp st).deferred.length ≤ st.deferred.length ∧ (opened env tp st).carry = st.carry ∧
    (opened env tp st).columns = st.columns ∧ (∀ d ∈ (opened env tp st).deferred, d ∈ st.deferred) := by
  obtain ⟨f1, f2, f3, f4, f5, f6, f7⟩ := fresh_fields env tp st
  unfold opened
  split
  · unfold placeTurned
    obtain ⟨a1, a2, a3, a4, a5, a6, _, a8, a9, a10, a11, _⟩ := placeTurnedGo_fields env (fresh env tp st) (fresh env tp st).deferred
    have aw : adjustWeight (placeTurnedGo env (fresh env tp st) (fresh env tp st).deferred) =
        adjustWeight (fresh env tp st) :=
      adjustWeight_congr (placeTurnedGo_setAdjust env _ _) a5 a9 a8
    refine ⟨by rw [a1, f1], by rw [a2, f2], by rw [a3, a4, f3], by rw [aw]; exact f4, by rw [← f5]; exact a10,
      by rw [a6, f6], by rw [a8, f7], fun x m => by rw [← f5]; exact a11 x m⟩
  · exact ⟨f1, f2, f3, f4, by simp [f5], f6, f7, fun x m => by rw [← f5]; exact m⟩

/-- What waits does not grow on the way to a new column; if it does not
    shrink, the new column is empty. -/
theorem open_waiting (env : Env) (tp : Bool) (st : St) :
    waiting (carryInto env (placeDeferred env (opened env tp st))) ≤ waiting st ∧
    (waiting (carryInto env (placeDeferred env (opened env tp st))) = waiting st →
      empty (carryInto env (placeDeferred env (opened env tp st))) = true) ∧
    (adjustWeight (carryInto env (placeDeferred env (opened env tp st))) < adjustWeight st ∨
      adjustWeight (carryInto env (placeDeferred env (opened env tp st))) = 0) ∧
    (carryInto env (placeDeferred env (opened env tp st))).columns = st.columns := by
  obtain ⟨f1, f2, f3, f4, f5, f6, f7, _⟩ := opened_fields env tp st
  generalize opened env tp st = F at *
  unfold placeDeferred
  obtain ⟨_, p2, p3, p4, p5, p6, p7, _, _, p10, p11⟩ := placeDeferredGo_fields env F F.deferred
  have ps := placeDeferredGo_setAdjust env F F.deferred
  generalize placeDeferredGo env F F.deferred = P at *
  obtain ⟨_, c2, c3, c4, c5, c6, c7, c8, _, c10, c11⟩ := carryInto_fields env P
  have cs := carryInto_setAdjust env P
  generalize carryInto env P = C at *
  have aw : adjustWeight C = adjustWeight F :=
    adjustWeight_congr (cs.trans ps) (c5.trans p5) (c2.trans p2) (c3.trans p3)
  simp only [waiting]
  rw [c8, ← f6, ← p7]
  refine ⟨by omega, fun e => ?_, by rw [aw]; exact f4, by rw [c3, p3, f7]⟩
  have l : P.deferred.length = F.deferred.length := by omega
  obtain ⟨s, u⟩ := p11 l
  have w : carryWeight C.carry = carryWeight P.carry := by omega
  have n : C.notes = [] := by
    cases c11 w with
    | inl h => exact h
    | inr h => rw [h, p6, f2]
  simp [empty, n, c6, s, f1, c7, u, f3, c4, p4, List.isEmpty]

/-- The rank of the column a state goes on to, with what waits of a state
    `st` of the same weight and columns. -/
theorem open_rank (C X st : St) (le : waiting C ≤ waiting X) (e : waiting C = waiting X → empty C = true)
    (a : adjustWeight C < adjustWeight X ∨ adjustWeight C = 0) (cc : C.columns = X.columns)
    (hw : waiting X = waiting st) (hx : adjustWeight X ≤ adjustWeight st) (hc : X.columns = st.columns) :
    rank C ≤ rank st ∧ ((empty st = false ∨ st.adjust < 0) → rank C < rank st) := by
  have u : unitWeight C = unitWeight st := by simp only [unitWeight, cc, hc]
  have r := rank_le C
  have low := rank_low st
  rw [u] at r
  by_cases lt : waiting C < waiting st
  · have : (waiting C + 1) * unitWeight st ≤ waiting st * unitWeight st := Nat.mul_le_mul_right _ lt
    omega
  · have eq : waiting C = waiting st := by omega
    have em := e (eq.trans hw.symm)
    have rc : rank C = waiting st * unitWeight st + adjustWeight C := by simp [rank, em, eq, u]
    have rs : rank st = waiting st * unitWeight st + adjustWeight st + (if empty st then 0 else 1) := rfl
    refine ⟨by rw [rc, rs]; split <;> omega, fun h => ?_⟩
    have p := rank_pos st h
    rw [rc]
    rcases a with a | a
    · rw [rs]; split <;> omega
    · omega

theorem I4_nextColumn_rank (env : Env) (st : St) (h : empty st = false ∨ st.adjust < 0) :
    rank (nextColumn env st) < rank st := by
  obtain ⟨le, e, a, c⟩ := open_waiting env false st
  exact (open_rank _ st st le e a c rfl (Nat.le_refl _) rfl).2 h

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
    | inr c =>
      have e := c.2
      simp only [Bool.or_eq_false_iff] at e
      exact Or.inl e.1
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
  · cases h
  unfold trialFrom at h
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
          refine Or.inr ⟨rfl, I4_nextColumn_rank env st (Or.inl ?_)⟩
          cases e : empty st
          · rfl
          · exact absurd (by simp [e]) ne
      · obtain ⟨e, n, m⟩ := trialRest_moved env _ start _ _ _ next relaxed h
        subst e; subst n
        exact Or.inr ⟨rfl, I4_nextColumn_rank env st m⟩

theorem I4_trial_placed (env : Env) (k : Keep) (start : Bool) (st : St) (r : Line) (rs : List Line)
    (c : Nat) (next : St) (relaxed : Keep) (h : trial env k start st (r :: rs) = .ok (.placed c next relaxed)) :
    1 ≤ c := by
  unfold trial at h
  split at h
  · cases h
  unfold trialFrom at h
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

mutual
/-- `flowLines` of Physical.hs: the lines of a box are those of its body. -/
def flowLines : Flow → List Line
  | .paragraph _ ls => ls
  | .continued _ ls => ls
  | .ruled r => r.lines
  | .heading _ _ ls => ls
  | .defTerm ls => ls
  | .stanza _ vs => vs.join
  | .code _ _ _ _ rows => rows
  | .wrapped _ _ ls => ls
  | .table _ _ header rows caption _ => header ++ rows.join ++ caption
  | .boxed _ _ _ body => bodyLines body
  | .bookPart _ _ _ => []
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
def bodyLines : List Flow → List Line
  | [] => []
  | f :: fs => flowLines f ++ bodyLines fs
end

/-! ## Ruled blocks -/

/-- The place of a rule after at the end of the column from the start of
    the last line (`snd (ruleAfterEdge pitch face side {rsdOutside =
    Nothing})`). -/
def ruleAfterEdgePos (pitch face : Int) (side : RuleSide) : Int :=
  let faceEnd := faceOffset pitch face + face
  if side.spaced then faceEnd + side.inner
  else faceEnd + half (pitch + ruleAfterExtra pitch face side.inner side.weight - faceEnd - side.weight)

def flushPendingRule (env : Env) (st : St) : St :=
  match st.join with
  | none => st
  | some (_, side, l, priorExtra) =>
    let extra := ruleAfterEdgeExtra (env.pitchOf l.id) (env.faceOf l.id) { side with outside := none }
    let firstAt := st.used - priorExtra - env.pitchOf l.id
    { st with used := st.used + max 0 (extra - priorExtra), join := none,
              afterRules := st.afterRules ++ [firstAt + ruleAfterEdgePos (env.pitchOf l.id) (env.faceOf l.id) side] }

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

/-- `joinsNext` of Physical.hs: the flows begin with a ruled paragraph
    whose rule before shares the area of the rule after before it; a ruled
    heading does not share it. -/
def joiningNext : List Flow → Bool
  | .ruled r :: _ => r.joined && r.before.isSome && r.heading.isNone
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

/-- The position of the rule after from the start of the last line
    (`snd (afterGeometry side)` of `ruledLinesPlan`): in the gap before the
    first line of the next flow (`ruleAfterGap`), or at the edge
    (`ruleAfterEdge` with no outside). -/
def ruleAfterPos (env : Env) (r : Ruled) (lastLine : Line) (later : List Flow) (side : RuleSide) : Int :=
  let lastPitch := env.pitchOf lastLine.id
  let lastFace := env.faceOf lastLine.id
  let faceEnd := faceOffset lastPitch lastFace + lastFace
  let edge := if side.spaced then faceEnd + side.inner
    else faceEnd + half (lastPitch + ruleAfterExtra lastPitch lastFace side.inner side.weight - faceEnd - side.weight)
  match later with
  | f :: _ =>
    match flowLines f with
    | n :: _ =>
      let gap := lastPitch - lastFace - faceOffset lastPitch lastFace + faceOffset (env.pitchOf n.id) (env.faceOf n.id)
      faceEnd + (if side.spaced then side.inner
        else half (gap + ruleGapExtra gap side r.nextOverhang - r.nextOverhang - side.weight))
    | [] => edge
  | [] => edge

/-- The place of the rule after of the block before, sharing the gap with
    the rule before of a joined block (`priorPosition` of `rulesSharedGap`),
    from the end of the face before. -/
def sharedPriorPos (gap : Int) (b a : RuleSide) (overhang : Int) : Int :=
  let distance := gap + rulesSharedExtra gap b a overhang
  let rest := distance - overhang - b.weight - a.weight
  if b.spaced || a.spaced then b.inner else Int.fdiv rest 3

/-- The rules after that `place` of `ruledLinesPlan` adds to the column
    from `st`: the rule after of the block before, when its rule before
    shares that area (`sharedRules`), and its own rule after when it does
    not wait (`endRule`), placed from `placedUsed`, the used length after
    its last line. -/
def ruledAfterRules (env : Env) (st : St) (r : Ruled) (first lastLine : Line) (later : List Flow) (placedUsed : Int) :
    List Int :=
  let shared :=
    match r.before, st.join with
    | some side, some (_, prior, priorLine, priorExtra) =>
      if r.joined then
        let previousPitch := env.pitchOf priorLine.id
        let previousFace := env.faceOf priorLine.id
        let priorEnd := st.used - priorExtra - previousPitch + faceOffset previousPitch previousFace + previousFace
        let gap := st.used + faceOffset (env.pitchOf first.id) (env.faceOf first.id) - priorEnd
        [priorEnd + sharedPriorPos gap prior side first.overhang]
      else []
    | _, _ => []
  let own :=
    if joiningNext later then []
    else match r.after with
      | some side => [placedUsed - env.pitchOf lastLine.id + ruleAfterPos env r lastLine later side]
      | none => []
  shared ++ own

/-- `ruleAfterInColumn` of Physical.hs on the state `f` a ruled paragraph
    is placed to: its rule after (`endRule`, placed `afterExtra` and the
    pitch of the last line before the lines used) ends before the notes of
    the column.  The model reads the one rule after of the block, not
    `psRules`; the ids of ruled blocks are distinct. -/
def ruleAfterFits (env : Env) (r : Ruled) (lastLine : Line) (later : List Flow) (f : St) : Bool :=
  match r.after with
  | none => true
  | some side =>
    decide (f.used - ruledAfterExtra env r lastLine later - env.pitchOf lastLine.id
      + ruleAfterPos env r lastLine later side + side.weight ≤ limit env f - f.notesUsed)

/-- `ruleAfterInColumn` of the last line of a ruled paragraph. -/
def ruleAfterFitsLast (env : Env) (r : Ruled) (later : List Flow) (f : St) : Bool :=
  match r.lines.getLast? with
  | some lastLine => ruleAfterFits env r lastLine later f
  | none => true

/-- The last step of `ruledHere`: the placement with the flows after it
    when it settles and fits, else `fallback`. -/
def hereOr (settled : Bool) (inside : Option St) (later : List Flow) (fallback : Except Failure (Option St)) :
    Except Failure (Option St) :=
  if settled && (inside.isSome || later.isEmpty) then .ok inside else fallback

theorem hereOr_some (b : Bool) (inside : Option St) (later : List Flow) (fb : Except Failure (Option St)) (p : St)
    (h : hereOr b inside later fb = .ok (some p)) : inside = some p ∨ fb = .ok (some p) := by
  unfold hereOr at h
  split at h
  · injection h with h; exact Or.inl h
  · exact Or.inr h

/-- `putKeeping` of `ruledLinesPlan`: each line put with the column made
    shorter by the lines after it in the block and the extra `after`, so
    that its notes keep that area clear (golem-driver ADR 0027). -/
def putLinesKeeping (allow : Bool) (env : Env) (adj after : Int) (st : St) : List Line → Except Failure St
  | [] => .ok st
  | l :: ls =>
    match putLineWithReserve allow env { st with adjust := adj - (sumPitch env ls + after) } l with
    | .error e => .error e
    | .ok s => putLinesKeeping allow env adj after s ls

/-- `place` of `ruledLinesPlan`: the lines of a ruled paragraph put from
    `ready`, the extra before them and the extra after them. -/
def ruledPlaceAt (env : Env) (st : St) (r : Ruled) (first lastLine : Line) (later : List Flow) (ready : St) :
    Except Failure St :=
  match putLinesKeeping true env ready.adjust (ruledAfterExtra env r lastLine later)
      { ready with used := ready.used + ruledBeforeExtra env st r first }
      r.lines with
  | .error e => .error e
  | .ok placed =>
    .ok { placed with
      used := placed.used + ruledAfterExtra env r lastLine later
      adjust := ready.adjust
      join := ruledJoin env r lastLine later
      afterRules := placed.afterRules ++ ruledAfterRules env st r first lastLine later placed.used }

/-- `ruledLinesHere` of Physical.hs: a ruled paragraph placed in this
    column with the flows after it, or none when it does not fit the room.
    An empty column that `fit` keeps although its room is shorter than the
    block (a column switch started it down the page) does not take the
    block either (PR #1150); `placeRuled` then breaks it without rules. -/
def ruledLinesHere (env : Env) (st : St) (r : Ruled) (later : List Flow) : Except Failure (Option St) :=
  match r.heading, r.lines.head?, r.lines.getLast? with
  | none, some first, some lastLine =>
    if env.capacity < ruledExtent env st r first lastLine later then .ok none
    else if (fit env st (ruledExtent env st r first lastLine later)).page = st.page
        ∧ (fit env st (ruledExtent env st r first lastLine later)).column = st.column
        ∧ ruledExtent env st r first lastLine later
            ≤ room env (fit env st (ruledExtent env st r first lastLine later)) then
      match ruledPlaceAt env st r first lastLine later (fit env st (ruledExtent env st r first lastLine later)) with
      | .error e => .error e
      | .ok s => .ok (some s)
    else .ok none
  | _, _, _ => .ok none

/-! ## Headings -/

def headId : List Line → Nat
  | l :: _ => l.id
  | [] => 0

def notesOf (ls : List Line) : List Note := ls.bind (fun l => l.notes)
def notesCount (ls : List Line) : Nat := ls.foldr (fun l a => noteLines l + a) 0

/-- The settings of `putHeading`: the first line takes the extent. -/
def headingEnv (env : Env) (firstId : Nat) (extent : Int) : Env :=
  { env with pitchOf := fun i => if i = firstId then extent else env.pitchOf i }

/-- `putHeading`: one slot, its notes as those of one line. -/
def putHeading (env : Env) (st : St) (firstId : Nat) (extent : Int) (ls : List Line) : Except Failure St :=
  match putLine (headingEnv env firstId extent) st ⟨firstId, notesOf ls, 0⟩ with
  | .error e => .error e
  | .ok placed => .ok { placed with slots := st.slots ++ [(st.used, .heading firstId ls.length)] }

def headingNeed (env : Env) (st : St) (extent : Int) (ls : List Line) : Int :=
  let notes := notesCount ls
  let separator := if 0 < notes ∧ st.notesUsed = 0 then env.separator else 0
  let complete := extent + separator + (notes : Int) * env.pagePitch
  if complete ≤ env.capacity then complete
  else extent + separator + (if 0 < notes then env.pagePitch else 0)

/-- The heading placed over the room of a column made shorter (`TallHeadingExtent`). -/
def tallAt (st : St) (firstId : Nat) (extent roomLeft : Int) : St :=
  { st with pending := 0, blankActive := false, blankSpans := 0,
            unmet := st.unmet ++ [.tallHeading firstId extent roomLeft] }

def placeHeading (env : Env) (st : St) (firstId : Nat) (extent : Int) (ls : List Line) : Except Failure St :=
  if env.capacity < extent then .error (.headingTooTall firstId)
  else if empty st ∧ st.adjust < 0 ∧ room env st < headingNeed env st extent ls ∧
      headingNeed env st extent ls ≤ env.capacity - st.used - st.notesUsed then
    putHeading env (tallAt st firstId extent (room env st)) firstId extent ls
  else putHeading env (fit env st (headingNeed env st extent ls)) firstId extent ls

/-! ## What follows a block -/

/-- `keepAhead` of Physical.hs: the last and first lines the controls
    ahead ask for, and the flows without them. -/
def soft : Flow → Bool
  | .space _ | .needLines _ | .adjustLines _ | .noBreakLines 0 => true
  | _ => false

def counts : Flow → Option (Nat × Nat)
  | .noBreak => some (2, 0)
  | .noBreakLines n => some (n, 0)
  | .keepNext n _ => some (0, n)
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
  | .stanza k vs :: _ => ((vs.take (max (firstPart k true vs.length) (min wanted vs.length))).join.length, true)
  | .paragraph k ls :: _ => (max (firstPart k true ls.length) (min wanted ls.length), true)
  | .continued k ls :: _ => (max (firstPart k false ls.length) (min wanted ls.length), true)
  | .space _ :: rest | .needLines _ :: rest | .adjustLines _ :: rest
  | .noBreak :: rest | .noBreakLines _ :: rest | .keepNext _ _ :: rest => followingRows wanted rest
  | _ => (1, false)

/-- The column with the heading or definition term on trial (`virtual`
    of `keepFollowing`). -/
def keepVirtual (env : Env) (heading : Bool) (st : St) (extent : Int) (ls : List Line) : St :=
  let noteCount := notesCount ls
  let notes : Int := (noteCount : Int) * env.pagePitch + (if 0 < noteCount ∧ st.notesUsed = 0 then env.separator else 0)
  let origin := st.used + st.pending
  let virtualSlots : List (Int × Slot) :=
    if heading then [(origin, .heading (headId ls) ls.length)]
    else (ls.foldl (fun (a : List (Int × Slot) × Int) l => (a.1 ++ [(a.2, .line l.id)], a.2 + env.pitchOf l.id)) ([], origin)).1
  { st with used := origin + extent, notesUsed := st.notesUsed + notes, slots := st.slots ++ virtualSlots, pending := 0 }

def keepWanted (later : List Flow) : Nat × List Flow :=
  match keepAhead later with
  | some (_, n, rest) => (n, rest)
  | none => (1, later)

/-! ## Stanzas -/

/-- The verse lines whose lines all fit among the first `count` lines. -/
def wholeVerses (count : Nat) : List (List Line) → Nat
  | [] => 0
  | v :: vs => if v.length ≤ count then wholeVerses (count - v.length) vs + 1 else 0

def stanzaShort (k : Keep) (start : Bool) (firstId total whole : Nat) : List Unmet :=
  (if start ∧ whole < k.first then [Unmet.shortPart true firstId k.first whole] else []) ++
  (if total - whole < k.last then [Unmet.shortPart false firstId k.last (total - whole)] else [])

theorem wholeVerses_le (c : Nat) (vs : List (List Line)) : wholeVerses c vs ≤ vs.length := by
  induction vs generalizing c with
  | nil => simp [wholeVerses]
  | cons v vs ih => simp only [wholeVerses]; split <;> simp; have := ih (c - v.length); omega

set_option linter.unusedVariables false in
/-- `placeStanza`: a verse line is not broken between columns. -/
def placeStanza (env : Env) (k : Keep) (start : Bool) (st : St) (verses : List (List Line)) : Except Failure St :=
  match verses with
  | [] => .ok st
  | firstVerse :: remaining =>
    let count := fitting env st (firstVerse :: remaining).join
    let whole := wholeVerses count (firstVerse :: remaining)
    let total := remaining.length + 1
    let selected := splitAtBreak k start total whole
    if h1 : k.all ∧ start ∧ whole < total then
      if h2 : (empty st || headingOnly st) = true then
        placeStanza env { k with all := false } start (addUnmet (.splitKept (headId firstVerse)) st) (firstVerse :: remaining)
      else placeStanza env k start (nextColumn env st) (firstVerse :: remaining)
    else if h3 : selected = 0 ∧ (empty st || (headingOnly st && decide (0 < count))) = false then
      placeStanza env k start (nextColumn env st) (firstVerse :: remaining)
    else if h4 : selected = 0 ∧ 0 < whole then
      match placeLines env defaultKeep start st ((firstVerse :: remaining).take whole).join with
      | .error e => .error e
      | .ok placed =>
        let warned := { placed with unmet := placed.unmet ++ stanzaShort k start (headId firstVerse) total whole }
        if whole = total then .ok warned
        else placeStanza env k false (nextColumn env warned) ((firstVerse :: remaining).drop whole)
    else if h5 : selected = 0 then
      match placeLines env defaultKeep true st firstVerse with
      | .error e => .error e
      | .ok placed => placeStanza env k false placed remaining
    else
      match placeLines env ⟨1, 1, false⟩ start st ((firstVerse :: remaining).take selected).join with
      | .error e => .error e
      | .ok placed =>
        if selected = total then .ok placed
        else placeStanza env k false (nextColumn env placed) ((firstVerse :: remaining).drop selected)
termination_by (verses.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, h1.1]
  · apply Prod.Lex.right; apply Prod.Lex.right
    apply I4_nextColumn_rank; left
    cases e : empty st
    · rfl
    · simp [e] at h2
  · apply Prod.Lex.right; apply Prod.Lex.right
    apply I4_nextColumn_rank; left
    have := h3.2; simp only [Bool.or_eq_false_iff] at this; exact this.1
  · apply Prod.Lex.left; have h := h4.2; simp only [whole, count, List.join] at h; omega
  · apply Prod.Lex.left; omega
  · apply Prod.Lex.left; have h := h5; simp only [selected, whole, count, total, List.join] at h; omega

/-! ## Keeps waiting for what follows -/

def waitFor (u : Unmet) (req : Nat × Bool) (st : St) : St :=
  let combined := st.waits.foldl (fun a w => max a w.2.2.2.2.1) req.1
  let onlyLines := req.2 || st.waits.any (fun w => w.2.2.2.2.2)
  let prior := st.waits.map (fun w => (w.1, w.2.1, w.2.2.1, w.2.2.2.1, combined, onlyLines))
  { st with waits := prior ++ [(u, st.page, st.column, st.slots.length, combined, onlyLines)] }

def waitForPrior (u : Unmet) (req : Nat × Bool) (st : St) : St :=
  if empty st ∨ st.deferred ≠ [] then addUnmet u st else waitFor u req st

def addedSlots (linesOnly : Bool) (prior : Nat) (slots : List (Int × Slot)) : Nat :=
  ((slots.drop prior).map (fun s => match s.2 with
    | .line _ => 1
    | .heading _ n => max 1 n
    | _ => if linesOnly then 0 else 1)).foldr (· + ·) 0

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

/-- The first figure sent on fits in a column. -/
def figureOk (env : Env) (st : St) : Bool :=
  match st.deferred with | .figure _ e :: _ => decide (e ≤ env.capacity) | _ => true

/-- `drainCarry`, going on only while the next page can take the first
    figure sent on and a line of the first note carried on; README.md
    explains why `paginate` never meets a state where it stops early. -/
def drainOk (env : Env) (st : St) : Bool :=
  (st.carry.isEmpty || decide (0 < env.pagePitch ∧ env.separator + env.pagePitch ≤ env.capacity)) && figureOk env st

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
    (h : 1 ≤ Int.fdiv (limit env st - st.used - st.notesUsed - env.separator) env.pagePitch) :
    carryWeight (carryInto env st).carry < carryWeight st.carry := by
  unfold carryInto
  have e : st.carry.isEmpty = false := by
    cases c : st.carry with
    | nil => exact absurd c ne
    | cons _ _ => rfl
  rw [e]
  dsimp only
  simp only [ite_false]
  generalize Int.fdiv (limit env st - st.used - st.notesUsed - env.separator) env.pagePitch = q at h ⊢
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

/-- `I4_drain_rank` with what it needs of `drainOk` only. -/
theorem drain_rank_core (env : Env) (st : St)
    (h : ((st.carry.isEmpty && st.deferred.isEmpty) = false ∨ ¬st.columns ≤ st.column + 1) ∧ figureOk env st = true ∧
      (st.deferred = [] → st.carry ≠ [] → 0 < env.pagePitch ∧ env.separator + env.pagePitch ≤ env.capacity)) :
    Prod.Lex (· < ·) (· < ·) (waiting (nextColumn env st), columnsLeft (nextColumn env st))
      (waiting st, columnsLeft st) := by
  obtain ⟨le, _, _⟩ := open_waiting env false st
  by_cases pe : st.columns ≤ st.column + 1
  · apply Prod.Lex.left
    have h1 : (st.carry.isEmpty && st.deferred.isEmpty) = false := h.1.resolve_right (fun n => n pe)
    have op : opened env false st = placeTurned env (fresh env false st) := by simp [opened, pe]
    unfold nextColumn placeDeferred
    rw [op]
    unfold placeTurned
    obtain ⟨u0, a0, n0, _⟩ := fresh_pageEnd env st pe
    obtain ⟨_, _, _, _, f5, f6, _⟩ := fresh_fields env false st
    generalize fresh env false st = Fr at *
    obtain ⟨_, _, t3, _, t5, t6, t7, _, _, t10, _, t12, t13⟩ := placeTurnedGo_fields env Fr Fr.deferred
    generalize placeTurnedGo env Fr Fr.deferred = T at *
    rw [f5] at t10 t12 t13
    by_cases lt : T.deferred.length < st.deferred.length
    · obtain ⟨_, _, _, _, _, _, p7, _, _, p10, _⟩ := placeDeferredGo_fields env T T.deferred
      obtain ⟨_, _, _, _, _, _, _, c8, _, c10, _⟩ := carryInto_fields env (placeDeferredGo env T T.deferred)
      simp only [waiting, c8]
      rw [p7, t6, f6] at c10
      omega
    · have eqd : T.deferred = st.deferred := (t13 (by omega)).1
      rw [eqd]
      cases d : st.deferred with
      | cons x rest =>
        cases x with
        | turned i => have := t12 i rest d; omega
        | figure i e =>
          have ok : e ≤ env.capacity := by
            have := h.2.1; simp only [figureOk, d, decide_eq_true_eq] at this; exact this
          simp only [placeDeferredGo]
          have r : e ≤ room env T := by simp only [room, limit, t3, t5, t7, u0, a0, n0]; omega
          rw [if_pos r]
          obtain ⟨_, _, _, _, _, _, p7, _, _, p10, _⟩ := placeDeferredGo_fields env (putSlot T e (.figure i)) rest
          obtain ⟨_, _, _, _, _, _, _, c8, _, c10, _⟩ := carryInto_fields env (placeDeferredGo env (putSlot T e (.figure i)) rest)
          simp only [waiting, c8, d, List.length_cons]
          have p7' : (placeDeferredGo env (putSlot T e (.figure i)) rest).carry = st.carry := (p7.trans t6).trans f6
          rw [p7'] at c10
          omega
      | nil =>
        have ne : st.carry ≠ [] := by
          intro c; have := h1; rw [c, d] at this; exact absurd this (by decide)
        have fits : 0 < env.pagePitch ∧ env.separator + env.pagePitch ≤ env.capacity := h.2.2 d ne
        simp only [placeDeferredGo]
        have s := carryInto_strict env { T with deferred := [] } (by rw [← f6, ← t6] at ne; exact ne)
          (fdiv_pos _ _ fits.1 (by show env.pagePitch ≤ env.capacity + T.adjust - T.used - T.notesUsed - env.separator; rw [t3, t5, t7, u0, a0, n0]; omega))
        simp only [waiting, d, List.length_nil]
        have : ({ T with deferred := [] } : St).carry = st.carry := t6.trans f6
        obtain ⟨_, _, _, _, _, _, _, c8, _, _, _⟩ := carryInto_fields env { T with deferred := [] }
        have e2 : carryWeight ({ T with deferred := [] } : St).carry = carryWeight st.carry := by rw [this]
        rw [c8]; simp only [List.length_nil]; omega
  · have op : opened env false st = fresh env false st := by simp [opened, pe]
    have cl : columnsLeft (nextColumn env st) < columnsLeft st := by
      unfold nextColumn placeDeferred
      rw [op]
      have fc := fresh_inPage env st pe
      obtain ⟨_, _, _, _, _, _, f7⟩ := fresh_fields env false st
      obtain ⟨_, p2, p3, _⟩ := placeDeferredGo_fields env (fresh env false st) (fresh env false st).deferred
      obtain ⟨_, c2, c3, _⟩ := carryInto_fields env (placeDeferredGo env (fresh env false st) (fresh env false st).deferred)
      simp only [columnsLeft, c2, c3, p2, p3, fc, f7]
      omega
    unfold nextColumn at cl ⊢
    by_cases w : waiting (carryInto env (placeDeferred env (opened env false st))) < waiting st
    · exact Prod.Lex.left _ _ w
    · have : waiting (carryInto env (placeDeferred env (opened env false st))) = waiting st := by omega
      rw [this]; exact Prod.Lex.right _ cl

/-- `drainCarry` goes on to a column that leaves fewer columns on the
    page or less waiting, and on to a new page only with less waiting. -/
theorem I4_drain_rank (env : Env) (st : St)
    (h : ((st.carry.isEmpty && st.deferred.isEmpty) = false ∨ ¬st.columns ≤ st.column + 1) ∧ drainOk env st = true) :
    Prod.Lex (· < ·) (· < ·) (waiting (nextColumn env st), columnsLeft (nextColumn env st))
      (waiting st, columnsLeft st) := by
  have d := h.2
  simp only [drainOk, Bool.and_eq_true] at d
  refine drain_rank_core env st ⟨h.1, d.2, fun _ ne => ?_⟩
  have c : st.carry.isEmpty = false := by
    cases e : st.carry with
    | nil => exact absurd e ne
    | cons _ _ => rfl
  have := d.1; rw [c] at this; simpa using this

/-- The next column while a figure is sent on leaves fewer columns on the
    page or less waiting. -/
theorem I4_settle_rank (env : Env) (st : St) (h : st.deferred ≠ [] ∧ figureOk env st = true) :
    Prod.Lex (· < ·) (· < ·) (waiting (nextColumn env st), columnsLeft (nextColumn env st))
      (waiting st, columnsLeft st) := by
  refine drain_rank_core env st ⟨Or.inl ?_, h.2, fun d => absurd d h.1⟩
  cases e : st.deferred with
  | nil => exact absurd e h.1
  | cons _ _ => simp [e, List.isEmpty]

set_option linter.unusedVariables false in
def drainCarry (env : Env) (st : St) : St :=
  if h : (st.carry.isEmpty && st.deferred.isEmpty) = false ∧ drainOk env st = true then
    drainCarry env (nextColumn env st)
  else st
termination_by (waiting st, columnsLeft st)
decreasing_by
  simp_wf
  exact I4_drain_rank env st ⟨Or.inl h.1, h.2⟩

theorem seek_cond (st : St) (h : ¬(waiting st = 0 ∧ st.columns ≤ st.column + 1)) :
    (st.carry.isEmpty && st.deferred.isEmpty) = false ∨ ¬st.columns ≤ st.column + 1 := by
  by_cases pe : st.columns ≤ st.column + 1
  · left
    have w : waiting st ≠ 0 := fun w => h ⟨w, pe⟩
    cases c : st.carry with
    | cons _ _ => rfl
    | nil =>
      cases d : st.deferred with
      | cons _ _ => rfl
      | nil => exact absurd (by simp [waiting, c, d, carryWeight]) w
  · exact Or.inr pe

set_option linter.unusedVariables false in
/-- The loop of a flow that goes on to the next column until it fits
    (`count == 0` of `placeCode`). It stops after the start of a page with
    nothing waiting: Physical.hs would loop for ever when the flow does
    not fit there, as every later column is the same. -/
def seek (env : Env) (p : St → Bool) (st : St) : St :=
  if p st then st
  else if h : drainOk env st = true ∧ ¬(waiting st = 0 ∧ st.columns ≤ st.column + 1) then seek env p (nextColumn env st)
  else nextColumn env st
termination_by (waiting st, columnsLeft st)
decreasing_by
  simp_wf
  exact I4_drain_rank env st ⟨seek_cond st h.2, h.1⟩

def parityStart (env : Env) (accept : Nat → Bool) (st : St) : St :=
  let settled := drainCarry env st
  let next := if empty settled ∧ settled.column = 0 then settled else nextPage env settled
  if accept next.page then next
  else if empty next then
    { next with done := ⟨next.page, 0, true, [], [], limit env next, []⟩ :: next.done, page := next.page + 1 }
  else nextPage env next

/-- The page before holds a turned figure (`afterTurned`). -/
def afterTurned (st : St) : Bool :=
  match st.done with
  | p :: _ => p.number == st.page - 1 && p.slots.any (fun s => match s.2 with | .pageFigure _ => true | _ => false)
  | [] => false

/-- The page break of `breakAt`: none on the page after a turned figure. -/
def breakPage (env : Env) (st : St) : St :=
  if empty st ∧ st.column = 0 ∧ afterTurned st then st else nextPage env st

def breakAt (env : Env) (k : BreakKind) (st : St) : St :=
  match k with
  | .column => if 1 < st.columns ∧ st.deferred.any Waiting.isTurned = false then nextColumn env st else breakPage env st
  | .page => breakPage env st
  | .recto => parityStart env (fun p => p % 2 == 1) st
  | .verso => parityStart env (fun p => p % 2 == 0) st

/-- `FSection`: nothing in an empty column or on an empty page. -/
def sectionStart (env : Env) (k : BreakKind) (st : St) : St :=
  let settled := drainCarry env st
  match k with
  | .column => if empty settled then settled else breakAt env k settled
  | .page => if empty settled ∧ settled.column = 0 then settled else breakAt env k settled
  | _ => breakAt env k settled

/-- `setRoom` of `FSwitchColumns`: the room left above the type area or
    above the footnotes of the column, whichever comes first (root ADR
    0441). -/
def setRoom (env : Env) (st : St) : Int := min env.capacity (limit env st - st.notesUsed) - st.used

/-- `FSwitchColumns`: the new columns start below what the page holds, or
    on the next page.  They keep the notes of the page clear (root ADR
    0025) and end where the first does, at the type area or above the
    footnotes of the column before, whichever comes first (root ADR
    0441). -/
def switchColumns (env : Env) (cols : Nat) (st : St) : St :=
  let settled := drainCarry env st
  if (env.columns = 1 ∧ 0 < setRoom env settled) ∨ (empty settled ∧ settled.column = 0) then
    { close env settled with
      columns := cols, firstLine := settled.used, column := 0, used := settled.used,
      reserved := settled.notesUsed, adjust := min settled.notesUsed settled.adjust,
      setAdjust := min settled.notesUsed settled.adjust,
      slots := [], notes := [], join := none, pending := 0, blankActive := false, blankSpans := 0, boxes := [],
      afterRules := [] }
  else { nextPage env settled with columns := cols, firstLine := 0 }

/-- `FRestoreColumns`: the next page, in the columns of the page. -/
def restoreColumns (env : Env) (st : St) : St :=
  { nextPage env st with columns := env.columns, firstLine := env.firstLine }

/-! ## What the rank of a column does on the way to the next ones -/

/-- Going on to a new column or page never raises `rank`. -/
theorem rank_open_le (env : Env) (tp : Bool) (st : St) :
    rank (carryInto env (placeDeferred env (opened env tp st))) ≤ rank st := by
  obtain ⟨le, e, a, c⟩ := open_waiting env tp st
  exact (open_rank _ st st le e a c rfl (Nat.le_refl _) rfl).1

set_option linter.unusedVariables false in
theorem rank_drainCarry_le (env : Env) (st : St) : rank (drainCarry env st) ≤ rank st := by
  rw [drainCarry]
  split
  · rename_i h
    have dec := I4_drain_rank env st ⟨Or.inl h.1, h.2⟩
    exact Nat.le_trans (rank_drainCarry_le env (nextColumn env st)) (rank_open_le env false st)
  · exact Nat.le_refl _
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem rank_parityStart_le (env : Env) (accept : Nat → Bool) (st : St) :
    rank (parityStart env accept st) ≤ rank st := by
  have a := rank_drainCarry_le env st
  have b : rank (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st
      else nextPage env (drainCarry env st)) ≤ rank (drainCarry env st) := by
    split
    · exact Nat.le_refl _
    · exact rank_open_le env true _
  unfold parityStart
  dsimp only
  generalize (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st
      else nextPage env (drainCarry env st)) = nx at b
  split
  · omega
  · split
    · exact Nat.le_trans (Nat.le_of_eq rfl) (Nat.le_trans b a)
    · exact Nat.le_trans (rank_open_le env true nx) (Nat.le_trans b a)

/-- `keepFollowing` with what follows judged: the next column unless the
    column is empty or what follows fits. -/
def keepFrom (env : Env) (st : St) (fits : Bool) : St :=
  if empty st = false ∧ fits = false then nextColumn env st else st

theorem rank_keepFrom_le (env : Env) (st : St) (b : Bool) : rank (keepFrom env st b) ≤ rank st := by
  unfold keepFrom
  split
  · rename_i h; exact Nat.le_of_lt (I4_nextColumn_rank env st (Or.inl h.1))
  · exact Nat.le_refl _

/-- The column a ruled heading starts from: an odd page, or the column
    `keepFollowing` gives with what follows judged. -/
def headingStateOf (env : Env) (st : St) (recto fits : Bool) : St :=
  if recto then parityStart env (fun p => p % 2 == 1) st else keepFrom env st fits

theorem rank_headingState_le (env : Env) (st : St) (recto b : Bool) :
    rank (headingStateOf env st recto b) ≤ rank st := by
  unfold headingStateOf
  split
  · exact rank_parityStart_le env _ st
  · exact rank_keepFrom_le env st b

/-! ## Boxes -/

/-- `boxExtras` of FreeGeometry.hs: the padding around the first and the
    last line. -/
def paddingExtra (env : Env) (padding : Int) (first last : Line) : Int × Int :=
  (max 0 (padding - faceOffset (env.pitchOf first.id) (env.faceOf first.id)),
   max 0 (padding - (env.pitchOf last.id - env.faceOf last.id - faceOffset (env.pitchOf last.id) (env.faceOf last.id))))

/-- `extras` of `placeBoxedParagraphWithKeeps` and `placeBoxedStanzaWith`:
    the padding of the box around its first and last lines, or the lengths
    the flow gives. -/
def boxExtra (env : Env) (ident : Nat) (fb fa : Int) (first last : Line) : Int × Int :=
  match env.boxPadding ident with
  | some padding => paddingExtra env padding first last
  | none => (fb, fa)

/-- The note lines of the lines and the separator they need. -/
def boxNotes (env : Env) (st : St) (ls : List Line) : Int :=
  (if 0 < notesCount ls ∧ st.notesUsed = 0 then env.separator else 0) + (notesCount ls : Int) * env.pagePitch

/-- `fragmentSize`: a part of a boxed paragraph with its padding and notes. -/
def fragmentSize (env : Env) (ident : Nat) (fb fa : Int) (st : St) (ls : List Line) : Int :=
  match ls.head?, ls.getLast? with
  | some first, some last =>
    (boxExtra env ident fb fa first last).1 + sumPitch env ls + (boxExtra env ident fb fa first last).2 + boxNotes env st ls
  | _, _ => 0

/-- The largest number of the first lines whose part fits (`available`). -/
def boxAvailable (fits : Nat → Bool) : Nat → Nat
  | 0 => 0
  | k + 1 => if fits (k + 1) then k + 1 else boxAvailable fits k

/-- The lines of a boxed paragraph a column takes (`candidateCount`). -/
def boxCount (selected available : Nat) : Nat := if selected = 0 then max 1 available else selected

theorem boxCount_pos (s a : Nat) : 1 ≤ boxCount s a := by unfold boxCount; split <;> omega

/-- The units of a boxed stanza a column takes (`count`). -/
def stanzaBoxCount (selected paragraphCount available : Nat) : Nat :=
  if 0 < selected then selected else if 0 < paragraphCount then paragraphCount else available

theorem stanzaBoxCount_pos {s q a : Nat} (h : ¬(s = 0 ∧ a = 0)) : 1 ≤ stanzaBoxCount s q a := by
  unfold stanzaBoxCount; split
  · omega
  · split <;> omega

/-- A part of a box put at `ready`: its padding before, its lines, its
    padding after, and its segment. -/
def putBoxPart (env : Env) (ident : Nat) (ready : St) (origin before after : Int) (ls : List Line) (short : List Unmet) :
    Except Failure St :=
  match putLines false env { ready with used := ready.used + before, adjust := ready.adjust - after } ls with
  | .error e => .error e
  | .ok placed =>
    .ok { placed with used := placed.used + after, adjust := ready.adjust,
                      boxes := placed.boxes ++ [(ident, origin, placed.used + after)], unmet := placed.unmet ++ short }

set_option linter.unusedVariables false in
/-- `placeBoxedParagraph` (`placeBoxedParagraphWithKeeps` with no marks,
    every gap 0): the lines of one paragraph in a box. -/
def placeBoxedParagraph (env : Env) (ident : Nat) (fb fa : Int) (k : Keep) (start : Bool) (st : St) (ls : List Line) :
    Except Failure St :=
  match ls with
  | [] => .ok st
  | first :: more =>
    let firstSize := (boxExtra env ident fb fa first first).1 + env.pitchOf first.id + (boxExtra env ident fb fa first first).2
    let available := boxAvailable (fun j => decide (fragmentSize env ident fb fa st ((first :: more).take j) + st.pending ≤ room env st))
      (more.length + 1)
    let selected := splitAtBreak k start (more.length + 1) available
    let count := boxCount selected available
    if env.capacity < firstSize then .error (.boxTooTall ident)
    else if env.capacity < firstSize + env.separator + env.pagePitch ∧ (first.notes.filter (fun n => 0 < n.lines)) ≠ [] then
      .error (.footnoteTooTall ((first.notes.filter (fun n => 0 < n.lines)).headD ⟨0, 0⟩).id)
    else if h1 : k.all ∧ start ∧ available < more.length + 1 then
      if h2 : empty st then placeBoxedParagraph env ident fb fa { k with all := false } start (addUnmet (.splitKept first.id) st) (first :: more)
      else placeBoxedParagraph env ident fb fa k start (nextColumn env st) (first :: more)
    else if h3 : selected = 0 ∧ empty st = false then placeBoxedParagraph env ident fb fa k start (nextColumn env st) (first :: more)
    else
      let here := (first :: more).take count
      let forced := selected = 0 ∧ empty st ∧ count < more.length + 1
      let short :=
        (if forced ∧ start ∧ count < k.first then [Unmet.shortPart true first.id k.first count] else []) ++
        (if forced ∧ more.length + 1 - count < k.last then [Unmet.shortPart false first.id k.last (more.length + 1 - count)] else [])
      let extra := boxExtra env ident fb fa (here.headD first) (here.getLastD first)
      let ready := fit env st (fragmentSize env ident fb fa st here)
      match putBoxPart env ident ready ready.used extra.1 extra.2 here short with
      | .error e => .error e
      | .ok finished =>
        if h4 : count < more.length + 1 then
          placeBoxedParagraph env ident fb fa k false (nextColumn env finished) ((first :: more).drop count)
        else .ok finished
termination_by (ls.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, h1.1]
  · apply Prod.Lex.right; apply Prod.Lex.right
    exact I4_nextColumn_rank env st (Or.inl (by simpa using h2))
  · apply Prod.Lex.right; apply Prod.Lex.right; exact I4_nextColumn_rank env st (Or.inl h3.2)
  · apply Prod.Lex.left
    exact Nat.sub_lt (Nat.succ_pos _) (boxCount_pos _ _)

/-- The box segment left open over a fallback paragraph of a stanza. -/
abbrev BoxOpen := Option ((Nat × Int × Int) × Int)

def seal (open? : BoxOpen) (st : St) : St :=
  match open? with
  | none => st
  | some (segment, after) => { st with used := st.used + after, boxes := st.boxes ++ [segment] }

/-- `reopen`: the segment of the box the fallback paragraph closed at the
    end of the column, opened again for the verse lines after it. -/
def reopen (env : Env) (ident : Nat) (fb fa : Int) (verse : List Line) (st : St) : St × BoxOpen :=
  match st.boxes.reverse, verse.getLast? with
  | segment :: earlier, some lastLine =>
    if segment.1 = ident ∧ segment.2.2 = st.used then
      ({ st with used := st.used - (boxExtra env ident fb fa lastLine lastLine).2, boxes := earlier.reverse },
       some (segment, (boxExtra env ident fb fa lastLine lastLine).2))
    else (st, none)
  | _, _ => (st, none)

/-- `BoxUnitKeep`: the keep of the paragraph or the stanza of a unit, the
    first line of that paragraph, the index of the unit in it and the number
    of its units. -/
structure UnitKeep where
  keep : Keep
  paragraph : Nat
  index : Nat
  count : Nat

/-- The maps of `placeBoxedStanzaWith` as lists keyed by a line id: the
    keep-with-next links (`keepMarks` holds a span for each, `keepCounts`
    the largest count), `unitKeeps` and `gaps`. A later entry of `units`
    and `gaps` wins, as in `Map.fromList` and `Map.insert`. -/
structure BoxMaps where
  links : List (Nat × Nat)
  units : List (Nat × UnitKeep)
  gaps : List (Nat × Int)

def noMaps : BoxMaps := ⟨[], [], []⟩

def lookupLast {α : Type} (xs : List (Nat × α)) (i : Nat) : Option α :=
  (xs.reverse.find? (fun x => x.1 == i)).map (·.2)

def BoxMaps.gap (m : BoxMaps) (i : Nat) : Int := (lookupLast m.gaps i).getD 0
def BoxMaps.marks (m : BoxMaps) (i : Nat) : Nat := (m.links.filter (fun x => x.1 == i)).length
def BoxMaps.count (m : BoxMaps) (i : Nat) : Option Nat :=
  match m.links.filter (fun x => x.1 == i) with
  | [] => none
  | x :: xs => some (xs.foldl (fun a y => max a y.2) x.2)
def BoxMaps.hasUnits (m : BoxMaps) : Bool := !m.units.isEmpty
/-- `boundsOf`: the keep of the unit, by its first line. -/
def BoxMaps.bounds (m : BoxMaps) (unit : List Line) : Option UnitKeep :=
  match unit with
  | l :: _ => lookupLast m.units l.id
  | [] => none

/-- `betweenUnits` of `size`: the gaps before the units after the first,
    and before the first when the part goes on from an open segment. -/
def unitGaps (m : BoxMaps) (opened : Bool) : Nat → List (List Line) → Int
  | _, [] => 0
  | j, v :: vs => (match v with | l :: _ => if 0 < j ∨ opened = true then m.gap l.id else 0 | [] => 0) + unitGaps m opened (j + 1) vs

/-- `size` of `placeBoxedStanzaWith`. -/
def stanzaBoxSize (env : Env) (ident : Nat) (fb fa : Int) (m : BoxMaps) (st : St) (open? : BoxOpen) (vs : List (List Line)) : Int :=
  match vs.join.head?, vs.join.getLast? with
  | some first, some last =>
    (if open?.isSome then 0 else (boxExtra env ident fb fa first last).1) + sumPitch env vs.join +
      unitGaps m open?.isSome 0 vs + (boxExtra env ident fb fa first last).2 + boxNotes env st vs.join
  | _, _ => 0
theorem rank_seal_lt (env : Env) (o : BoxOpen) (st : St) (h : empty st = false) :
    rank (nextColumn env (seal o st)) < rank st := by
  cases o with
  | none => exact I4_nextColumn_rank env st (Or.inl h)
  | some p =>
    obtain ⟨seg, after⟩ := p
    cases e : empty (seal (some (seg, after)) st)
    · have e' := e
      simp only [seal] at e'
      have : rank (seal (some (seg, after)) st) = rank st := by
        simp only [rank, seal, waiting, unitWeight, adjustWeight, columnsLeft, e', h]
      have := I4_nextColumn_rank env _ (Or.inl e); omega
    · have a := rank_open_le env false (seal (some (seg, after)) st)
      have e' := e
      simp only [seal] at e'
      have : rank (seal (some (seg, after)) st) + 1 = rank st := by
        simp only [rank, seal, waiting, unitWeight, adjustWeight, columnsLeft, h, e']; simp
      exact Nat.lt_of_le_of_lt a (by omega)

/-- `linkBreaks`: the keep-with-next spans a break after the first `n`
    units cuts. -/
def linkBreaks (m : BoxMaps) (vs : List (List Line)) (n : Nat) : Nat :=
  if vs.length ≤ n then 0
  else
    let cut := (vs.take n).join.length
    (vs.join.enum.filter (fun x => decide (x.1 < cut) &&
      (match m.count x.2.id with | some w => decide (cut - x.1 - 1 < w) | none => false))).foldr
      (fun x a => m.marks x.2.id + a) 0

/-- `boundary`: the units on the two sides of a break after the first `n`
    units, when they are of one paragraph. -/
def unitBoundary (m : BoxMaps) (vs : List (List Line)) (n : Nat) : Option (UnitKeep × UnitKeep) :=
  match vs.drop (n - 1), vs.drop n with
  | b :: _, a :: _ =>
    match m.bounds b, m.bounds a with
    | some x, some y => if x.paragraph = y.paragraph then some (x, y) else none
    | _, _ => none
  | _, _ => none

def atGroupStart (m : BoxMaps) (vs : List (List Line)) (b : UnitKeep) : Bool :=
  match (vs.filterMap m.bounds).find? (fun x => x.paragraph == b.paragraph) with
  | some x => x.index == 0
  | none => false

def paragraphBreak (m : BoxMaps) (relaxed : List Nat) (vs : List (List Line)) (n : Nat) : Bool :=
  match unitBoundary m vs n with
  | none => true
  | some (a, b) =>
    (!a.keep.all || relaxed.contains a.paragraph) && (!atGroupStart m vs a || decide (a.keep.first ≤ a.index + 1)) &&
      decide (a.keep.last ≤ b.count - b.index)

def legalBreak (m : BoxMaps) (relaxed : List Nat) (vs : List (List Line)) (n : Nat) : Bool :=
  paragraphBreak m relaxed vs n && linkBreaks m vs n == 0

def boundaryWarnings (m : BoxMaps) (vs : List (List Line)) (n : Nat) : List Unmet :=
  match unitBoundary m vs n with
  | some (a, b) =>
    (if atGroupStart m vs a = true ∧ a.index + 1 < a.keep.first then [Unmet.shortPart true a.paragraph a.keep.first (a.index + 1)] else []) ++
    (if b.count - b.index < a.keep.last then [Unmet.shortPart false b.paragraph a.keep.last (b.count - b.index)] else [])
  | none => []

/-- The paragraph whose keep-all-lines a unit relaxes when no part of it fits. -/
def relaxFor (m : BoxMaps) (relaxed : List Nat) (unit : List Line) : Option Nat :=
  match m.bounds unit with
  | some b => if b.keep.all = true ∧ b.paragraph ∉ relaxed then some b.paragraph else none
  | none => none

def fallbackKeep (m : BoxMaps) (relaxed : List Nat) (unit : List Line) : Keep :=
  match m.bounds unit with
  | some b => if relaxed.contains b.paragraph then { b.keep with all := false } else b.keep
  | none => ⟨1, 1, false⟩

/-- The units whose paragraph a later relaxation may still relax. -/
def unrelaxed (m : BoxMaps) (relaxed : List Nat) (vs : List (List Line)) : Nat :=
  (vs.filter (fun v => (relaxFor m relaxed v).isSome)).length

theorem filter_length_mono {α : Type} (p q : α → Bool) (h : ∀ x, p x = true → q x = true) :
    ∀ xs : List α, (xs.filter p).length ≤ (xs.filter q).length
  | [] => Nat.le_refl _
  | x :: xs => by
    have ih := filter_length_mono p q h xs
    cases hp : p x <;> cases hq : q x <;> simp [List.filter, hp, hq] <;> try omega
    exact absurd (h x hp) (by simp [hq])

theorem relaxFor_mono (m : BoxMaps) (p : Nat) (relaxed : List Nat) (w : List Line)
    (h : (relaxFor m (p :: relaxed) w).isSome = true) : (relaxFor m relaxed w).isSome = true := by
  unfold relaxFor at h ⊢
  split at h
  · rename_i b _
    by_cases c : b.keep.all = true ∧ b.paragraph ∉ p :: relaxed
    · rw [if_pos ⟨c.1, fun m => c.2 (List.mem_cons_of_mem _ m)⟩]; rfl
    · rw [if_neg c] at h; cases h
  · cases h

theorem unrelaxed_lt (m : BoxMaps) (relaxed : List Nat) (v : List Line) (vs : List (List Line)) (p : Nat)
    (h : relaxFor m relaxed v = some p) : unrelaxed m (p :: relaxed) (v :: vs) < unrelaxed m relaxed (v :: vs) := by
  have hn : relaxFor m (p :: relaxed) v = none := by
    unfold relaxFor at h ⊢
    split at h
    · rename_i b _
      by_cases c : b.keep.all = true ∧ b.paragraph ∉ relaxed
      · rw [if_pos c] at h; injection h with h; subst h
        rw [if_neg]; intro c'; exact c'.2 (List.mem_cons_self _ _)
      · rw [if_neg c] at h; cases h
    · cases h
  have mono := filter_length_mono _ _ (relaxFor_mono m p relaxed) vs
  unfold unrelaxed
  simp [List.filter, hn, h]
  omega

/-- The lines of the units, each unit after the first moved by its gap. -/
def putUnits (env : Env) (m : BoxMaps) (st : St) : Bool → List (List Line) → Except Failure St
  | _, [] => .ok st
  | first, v :: vs =>
    let gap := if first then 0 else (match v with | l :: _ => m.gap l.id | [] => 0)
    match putLines false env { st with used := st.used + gap } v with
    | .error e => .error e
    | .ok s => putUnits env m s false vs

/-- A part of a boxed stanza put at `ready`: its padding before, the gap
    before its first unit, its units, its padding after, and its segment. -/
def putStanzaPart (env : Env) (m : BoxMaps) (ident : Nat) (ready : St) (origin before firstGap after : Int)
    (vs : List (List Line)) (short : List Unmet) : Except Failure St :=
  match putUnits env m { ready with used := ready.used + before + firstGap, adjust := ready.adjust - after } true vs with
  | .error e => .error e
  | .ok placed =>
    .ok { placed with used := placed.used + after, adjust := ready.adjust,
                      boxes := placed.boxes ++ [(ident, origin, placed.used + after)], unmet := placed.unmet ++ short }

/-- `selected` and `paragraphCount` of `placeBoxedStanzaWith`: the largest
    break that fits and that `legal` allows, or the break of the keep of the
    box when it has no keeps of its own. -/
def boxSelected (legal : Nat → Bool) (m : BoxMaps) (k : Keep) (start : Bool) (total available : Nat) : Nat :=
  if m.hasUnits then boxAvailable legal available else splitAtBreak k start total available

/-- `short` of `placeBoxedStanzaWith`: the parts shorter than their keeps
    and the keep-with-next links a forced break cuts. -/
def boxShort (m : BoxMaps) (k : Keep) (start forced : Bool) (vs : List (List Line)) (count : Nat) : List Unmet :=
  (if m.hasUnits then (if forced then boundaryWarnings m vs count else [])
   else (if forced ∧ start ∧ count < k.first then [Unmet.shortPart true (headId (vs.headD [])) k.first count] else []) ++
    (if forced ∧ vs.length - count < k.last then
      [Unmet.shortPart false (headId (vs.headD [])) k.last (vs.length - count)] else [])) ++
  List.replicate (if forced then linkBreaks m vs count else 0) (Unmet.keepNext 0)

def lex4 (a b : Nat × Nat × Nat × Nat) : Prop :=
  Prod.Lex (· < ·) (Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·))) a b

set_option linter.unusedVariables false in
/-- `placeBoxedStanzaWith`: the units of a box, each a verse line of a
    stanza or a line of a paragraph, a unit too tall for an empty column
    broken as a boxed paragraph. `placeBoxedStanza` is this with no maps. -/
def placeBoxedStanza (env : Env) (ident : Nat) (fb fa : Int) (m : BoxMaps) (k : Keep) (start : Bool)
    (relaxed : List Nat) (open? : BoxOpen) (st : St) : List (List Line) → Except Failure St
  | [] => .ok (seal open? st)
  | firstVerse :: more =>
    let available := boxAvailable
      (fun j => decide (stanzaBoxSize env ident fb fa m st open? ((firstVerse :: more).take j) + st.pending ≤ room env st))
      (more.length + 1)
    let selected := boxSelected (legalBreak m relaxed (firstVerse :: more)) m k start (more.length + 1) available
    let paragraphCount := boxSelected (paragraphBreak m relaxed (firstVerse :: more)) m k start (more.length + 1) available
    if h1 : selected = 0 ∧ empty st = false then
      placeBoxedStanza env ident fb fa m k start relaxed none (nextColumn env (seal open? st)) (firstVerse :: more)
    else if h2 : selected = 0 ∧ paragraphCount = 0 ∧ k.all ∧ start then
      placeBoxedStanza env ident fb fa m { k with all := false } start relaxed open?
        (addUnmet (.splitKept (headId firstVerse)) st) (firstVerse :: more)
    else match hp : (if selected = 0 ∧ paragraphCount = 0 then relaxFor m relaxed firstVerse else none) with
    | some p =>
      placeBoxedStanza env ident fb fa m k start (p :: relaxed) open? (addUnmet (.splitKept p) st) (firstVerse :: more)
    | none =>
      if h3 : selected = 0 ∧ available = 0 then
        match placeBoxedParagraph env ident fb fa (fallbackKeep m relaxed firstVerse) true st firstVerse with
        | .error e => .error e
        | .ok placed =>
          placeBoxedStanza env ident fb fa m k false relaxed (reopen env ident fb fa firstVerse placed).2
            (reopen env ident fb fa firstVerse placed).1 more
      else
        let count := stanzaBoxCount selected paragraphCount available
        let here := (firstVerse :: more).take count
        let forced := selected = 0 ∧ count < more.length + 1
        let short := boxShort m k start (decide forced) (firstVerse :: more) count
        let extra := boxExtra env ident fb fa (here.join.headD ⟨0, [], 0⟩) (here.join.getLastD ⟨0, [], 0⟩)
        let ready := fit env st (stanzaBoxSize env ident fb fa m st open? here)
        let origin := match open? with
          | some (segment, _) => segment.2.1
          | none => ready.used
        let firstGap := if open?.isSome then m.gap (here.join.headD ⟨0, [], 0⟩).id else 0
        match putStanzaPart env m ident ready origin (if open?.isSome then 0 else extra.1) firstGap extra.2 here short with
        | .error e => .error e
        | .ok finished =>
          if h4 : count < more.length + 1 then
            placeBoxedStanza env ident fb fa m k false relaxed none (nextColumn env finished) ((firstVerse :: more).drop count)
          else .ok finished
termination_by vs => (vs.length, keepRank k, unrelaxed m relaxed vs, rank st)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; exact rank_seal_lt env _ st h1.2
  · apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, h2.2.2.1]
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    apply unrelaxed_lt
    split at hp
    · exact hp
    · cases hp
  · apply Prod.Lex.left; omega
  · apply Prod.Lex.left
    exact Nat.sub_lt (Nat.succ_pos _) (stanzaBoxCount_pos h3)

/-- `fitsFollowing` of a box placed on trial: it puts a part in the column. -/
def boxFits (st : St) : Except Failure St → Bool
  | .ok placed =>
    (placed.page == st.page && placed.column == st.column && decide (st.slots.length < placed.slots.length)) ||
      placed.done.any (fun o => o.number == st.page && o.column == st.column && decide (st.slots.length < o.slots.length))
  | .error _ => false

def nonemptyVerses (vs : List (List Line)) : List (List Line) := vs.filter (fun v => !v.isEmpty)

/-- `collectMixedBoxUnits`: the units of a box of paragraphs, stanzas,
    spaces and keeps (a unit for each line of a paragraph and each verse
    line of a stanza), and the spaces before each unit after them. -/
def collectMixed : Int → List (Nat × Int) → List (List Line) → List Flow → Option (List (Nat × Int) × List (List Line))
  | _, gaps, units, [] => some (gaps, units.reverse)
  | p, gaps, units, .space n :: rest => collectMixed (p + n) gaps units rest
  | p, gaps, units, .keepNext _ _ :: rest => collectMixed p gaps units rest
  | p, gaps, units, .paragraph _ ls :: rest =>
    match (nonemptyVerses (ls.map (fun l => [l]))).join.head? with
    | none => collectMixed p gaps units rest
    | some first =>
      collectMixed 0 (if p = 0 then gaps else gaps ++ [(first.id, p)]) ((nonemptyVerses (ls.map (fun l => [l]))).reverse ++ units) rest
  | p, gaps, units, .stanza _ vs :: rest =>
    match (nonemptyVerses vs).join.head? with
    | none => collectMixed p gaps units rest
    | some first => collectMixed 0 (if p = 0 then gaps else gaps ++ [(first.id, p)]) ((nonemptyVerses vs).reverse ++ units) rest
  | _, _, _, _ :: _ => none

/-- `boxKeepLinks`: each keep-with-next of a box, with the last line before
    it and the lines it asks for. -/
def boxLinks : Option Nat → List Flow → List (Nat × Nat)
  | _, [] => []
  | prior, .space _ :: rest => boxLinks prior rest
  | prior, .keepNext w _ :: rest =>
    (match prior with | some i => [(i, (followingRows w rest).1)] | none => []) ++ boxLinks prior rest
  | prior, f :: rest =>
    boxLinks (match (flowLines f).getLast? with | some l => some l.id | none => prior) rest

/-- `boxUnitKeeps` of one paragraph or stanza. -/
def unitEntries (k : Keep) (raw : List (List Line)) : List (Nat × UnitKeep) :=
  match (nonemptyVerses raw).join.head? with
  | none => []
  | some p => (nonemptyVerses raw).enum.filterMap (fun x => x.2.head?.map (fun l => (l.id, ⟨k, p.id, x.1, (nonemptyVerses raw).length⟩)))

def unitKeepsOf : List Flow → List (Nat × UnitKeep)
  | [] => []
  | .paragraph k ls :: rest => unitEntries k (ls.map (fun l => [l])) ++ unitKeepsOf rest
  | .stanza k vs :: rest => unitEntries k vs ++ unitKeepsOf rest
  | _ :: rest => unitKeepsOf rest

def mapsOf (body : List Flow) (gaps : List (Nat × Int)) : BoxMaps := ⟨boxLinks none body, unitKeepsOf body, gaps⟩

/-- The extras of a box with any other body (`boxExtras` with the padding
    or 0), or the lengths the flow gives when it has no lines. -/
def genericExtra (env : Env) (ident : Nat) (fb fa : Int) (ls : List Line) : Int × Int :=
  match ls.head?, ls.getLast? with
  | some first, some last => paddingExtra env ((env.boxPadding ident).getD 0) first last
  | _, _ => (fb, fa)

/-- `minimumSize`: the first line with the padding around it. -/
def genericMinimum (env : Env) (ident : Nat) (ls : List Line) : Int :=
  match ls.head? with
  | some first =>
    (paddingExtra env ((env.boxPadding ident).getD 0) first first).1 + env.pitchOf first.id +
      (paddingExtra env ((env.boxPadding ident).getD 0) first first).2
  | none => 0

/-- `placeFlow` for the flows inside a box, one level of nesting below. -/
structure Inner where
  flow : Env → St → Flow → Except Failure St
  /-- `placeAll` for the flows of a book part. -/
  all : Env → St → List Flow → Except Failure St

/-- The `foldl'` of `placeFlow` over the body of a box. -/
def placeFlows (inner : Inner) (env : Env) (st : St) : List Flow → Except Failure St
  | [] => .ok st
  | f :: fs =>
    match inner.flow env st f with
    | .error e => .error e
    | .ok s => placeFlows inner env s fs

/-- `FBoxed` with any other body: its flows placed one after another inside
    the padding. -/
def placeGeneric (inner : Inner) (env : Env) (st : St) (ident : Nat) (fb fa : Int) (body : List Flow) : Except Failure St :=
  if env.capacity < genericMinimum env ident (bodyLines body) then .error (.boxTooTall ident)
  else
    let start := fit env st (genericMinimum env ident (bodyLines body))
    let extra := genericExtra env ident fb fa (bodyLines body)
    match placeFlows inner env { start with used := start.used + extra.1 } body with
    | .error e => .error e
    | .ok placed =>
      .ok { placed with used := placed.used + extra.2, boxes := placed.boxes ++ [(ident, start.used, placed.used + extra.2)] }

/-- The cases of `FBoxed` in `placeFlow`. -/
def placeBox (inner : Inner) (env : Env) (st : St) (ident : Nat) (fb fa : Int) (body : List Flow) : Except Failure St :=
  match body with
  | [.paragraph k ls] => placeBoxedParagraph env ident fb fa k true st ls
  | [.stanza k vs] => placeBoxedStanza env ident fb fa noMaps k true [] none st (nonemptyVerses vs)
  | _ =>
    match collectMixed 0 [] [] body with
    | some (gaps, units) => placeBoxedStanza env ident fb fa (mapsOf body gaps) ⟨1, 1, false⟩ true [] none st units
    | none => placeGeneric inner env st ident fb fa body

/-! ## What follows a block, and ruled blocks -/

theorem collect_length (before between : List Flow) (l f : Nat) (xs : List Flow) :
    (collect before between l f xs).2.2.length ≤ before.length + between.length + xs.length := by
  induction xs generalizing before between l f with
  | nil => simp [collect]
  | cons x xs ih =>
    simp only [collect]
    split
    · have := ih before (between ++ [x]) l f; simp at this ⊢; omega
    · split
      · rename_i l' f' _
        have := ih (before ++ between) [] (max l l') (max f f'); simp at this ⊢; omega
      · simp; omega

theorem keepAheadGo_length (between : List Flow) (xs : List Flow) (l f : Nat) (r : List Flow)
    (h : keepAheadGo between xs = some (l, f, r)) : r.length ≤ between.length + xs.length := by
  induction xs generalizing between with
  | nil => simp [keepAheadGo] at h
  | cons x xs ih =>
    simp only [keepAheadGo] at h
    split at h
    · have := ih (between ++ [x]) h; simp at this ⊢; omega
    · split at h
      · rename_i l' f' _
        injection h with h
        have c := collect_length between [] l' f' xs
        rw [h] at c
        simp at c ⊢; omega
      · cases h

theorem keepWanted_length (later : List Flow) : (keepWanted later).2.length ≤ later.length := by
  unfold keepWanted
  split
  · rename_i n rest e
    have := keepAheadGo_length [] later _ n rest e
    simp at this ⊢; exact this
  · exact Nat.le_refl _

/-- The rules of a ruled block, and whether its rule before waits to share. -/
def ruledRank (r : Ruled) : Nat :=
  (if r.before.isSome then 1 else 0) + (if r.after.isSome then 1 else 0) + joinedRank r

theorem ruledRank_le (r : Ruled) : ruledRank r ≤ 3 := by
  unfold ruledRank joinedRank; split <;> split <;> split <;> omega

theorem ruledRank_after (r : Ruled) {side : RuleSide} (h : r.after = some side) :
    ruledRank { r with after := none } < ruledRank r := by
  obtain ⟨_, b, a, j, _, _, _, _⟩ := r
  simp only at h; subst h
  cases b <;> cases j <;> simp [ruledRank, joinedRank]

theorem ruledRank_before (r : Ruled) {side : RuleSide} (ha : r.after = none) (h : r.before = some side) :
    ruledRank { r with before := none } < ruledRank r := by
  obtain ⟨_, b, a, j, _, _, _, _⟩ := r
  simp only at h ha; subst h; subst ha
  cases j <;> simp [ruledRank, joinedRank]

/-- The extra length of the rule before a ruled heading at the edge of its
    area (`startExtra`, `beforeEdge` with the side as it is): whether an
    empty column holds the heading with its rules (golem-driver ADR 0035). -/
def headingBeforeExtra (env : Env) (r : Ruled) : Int :=
  match r.before, r.lines.head? with
  | some side, some l =>
    let size := env.faceOf l.id
    let pitch := match env.headingBounds (headId r.lines) with
      | some (firstFaceAt, _) => 2 * firstFaceAt + size
      | none => env.pitchOf l.id
    ruleBeforeEdgeExtra pitch size side l.overhang
  | _, _ => 0

/-- The virtual pitch of the first line of a ruled heading
    (`virtualPitch` of `beforeEdge` in `placeRuled`'s `RuledHeading`). -/
def headingFirstPitch (env : Env) (r : Ruled) (l : Line) : Int :=
  match env.headingBounds (headId r.lines) with
  | some (firstFaceAt, _) => 2 * firstFaceAt + env.faceOf l.id
  | none => env.pitchOf l.id

/-- The position of the rule before a ruled heading from the start of its
    area at the edge (`snd (beforeEdge side line)`, `ruleBeforeEdge` with
    the virtual pitch). -/
def headingBeforePos (env : Env) (r : Ruled) (side : RuleSide) (l : Line) : Int :=
  let pitch := headingFirstPitch env r l
  let size := env.faceOf l.id
  let leading := faceOffset pitch size
  let exact := leading - l.overhang - side.inner - side.weight
  let outside := if side.spaced then exact else min (-side.weight) exact
  let extra := ruleBeforeExtra pitch size side.inner side.weight l.overhang
  let rest := leading + extra - l.overhang - side.weight
  let inside := if side.spaced then exact + extra else rest - half rest
  match side.outside with
  | some available => if outside + side.weight ≤ 0 ∧ -outside ≤ available then outside else inside
  | none => inside

/-- The place of a rule before in a face-to-face gap from the end of the
    face before (`snd (ruleBeforeGap gap side overhang)`). -/
def ruleBeforeGapPos (gap : Int) (side : RuleSide) (overhang : Int) : Int :=
  let distance := gap + ruleGapExtra gap side overhang
  let rest := distance - overhang - side.weight
  if side.spaced then distance - overhang - side.inner - side.weight else rest - half rest

/-- The last slot of a column when it is a line (`SLine`, a repeated
    header line included): its place and its id. -/
def lastLineSlot (st : St) : Option (Int × Nat) :=
  match lastSlot st with
  | some (cur, .line i) => some (cur, i)
  | some (cur, .repeated i) => some (cur, i)
  | _ => none

/-- The rule before a ruled heading as a ruled paragraph's (PR #1151,
    `beforeGeometry` of `placeRuled`'s `RuledHeading` on `at`): after a
    line with no space and no rule after below it, in the gap between the
    faces (`ruleBeforeGap`); else at the edge of the heading's area, with
    the outside only at the top of an empty column at 0.  Its extra and
    its place from the start of the heading's box. -/
def headingBeforeGeom (env : Env) (cur : St) (r : Ruled) (side : RuleSide) (l : Line) : Int × Int :=
  let edgeSide := if empty cur ∧ cur.used = 0 then side else { side with outside := none }
  let edge := (ruleBeforeEdgeExtra (headingFirstPitch env r l) (env.faceOf l.id) edgeSide l.overhang,
    headingBeforePos env r edgeSide l)
  match lastLineSlot cur with
  | some (priorAt, priorId) =>
    if cur.pending = 0 ∧ cur.afterRules.all (fun a => decide (a < priorAt)) then
      let priorEnd := priorAt + faceOffset (env.pitchOf priorId) (env.faceOf priorId) + env.faceOf priorId
      let gap := cur.used + faceOffset (headingFirstPitch env r l) (env.faceOf l.id) - priorEnd
      (ruleGapExtra gap side l.overhang, priorEnd + ruleBeforeGapPos gap side l.overhang - cur.used)
    else edge
  | none => edge

/-- The extra length of the rule before a ruled heading placed from `cur`
    (`beforeExtra`). -/
def headingBeforeAt (env : Env) (cur : St) (r : Ruled) : Int :=
  match r.before, r.lines.head? with
  | some side, some l => (headingBeforeGeom env cur r side l).1
  | _, _ => 0

/-- The end of the face of the last line of a ruled heading from the
    start of its box, and the space after it to the end of the box
    (`lastFace`). -/
def headingLastFace (env : Env) (r : Ruled) (extent : Int) (l : Line) : Int × Int :=
  match env.headingBounds (headId r.lines) with
  | some (_, lastFaceEnd) => (lastFaceEnd, extent - lastFaceEnd)
  | none =>
    let pitch := env.pitchOf l.id
    let size := env.faceOf l.id
    (extent - pitch + faceOffset pitch size + size, pitch - size - faceOffset pitch size)

/-- Whether a flow is a ruled block with a rule before of its own
    (`ruledBefore` of Physical.hs). -/
def ruledBeforeFlow : Flow → Bool
  | .ruled r => r.before.isSome
  | _ => false

/-- The gap between the faces after a ruled heading in the middle of a
    column (PR #1152): the next flow has a line and no rule before. -/
def headingNextGap (env : Env) (r : Ruled) (extent : Int) (l : Line) : List Flow → Option Int
  | f :: _ =>
    if ruledBeforeFlow f then none
    else match flowLines f with
      | n :: _ => some ((headingLastFace env r extent l).2 + faceOffset (env.pitchOf n.id) (env.faceOf n.id))
      | [] => none
  | [] => none

/-- The rule after a ruled heading (`afterGeometry interior`): in the
    middle of a column, in the gap between the faces with its outer space
    and the overhang of the next line (`ruleAfterGap`); else at the end of
    the column, without the outer space (`ruleAfterEdge`).  Its extra and
    its place from the start of the heading's box. -/
def headingAfterGeom (env : Env) (r : Ruled) (extent : Int) (later : List Flow) (interior : Bool)
    (side : RuleSide) (l : Line) : Int × Int :=
  let faceEnd := (headingLastFace env r extent l).1
  let trailing := (headingLastFace env r extent l).2
  let size := env.faceOf l.id
  match (if interior then headingNextGap env r extent l later else none) with
  | some gap =>
    (ruleGapExtra gap side r.nextOverhang,
      faceEnd + (if side.spaced then side.inner
        else half (gap + ruleGapExtra gap side r.nextOverhang - r.nextOverhang - side.weight)))
  | none =>
    match env.headingBounds (headId r.lines) with
    | none =>
      let pitch := env.pitchOf l.id
      (ruleAfterEdgeExtra pitch size { side with outside := none }, extent - pitch + ruleAfterEdgePos pitch size side)
    | some _ =>
      let pitch := 2 * trailing + size
      (ruleAfterEdgeExtra pitch size { side with outside := none },
        faceEnd - size - trailing + ruleAfterEdgePos pitch size side)

/-- The extra length of the rule after a ruled heading (`afterExtraOf`). -/
def headingAfterAt (env : Env) (r : Ruled) (extent : Int) (later : List Flow) (interior : Bool) : Int :=
  match r.after, r.lines.getLast? with
  | some side, some l => (headingAfterGeom env r extent later interior side l).1
  | _, _ => 0

/-- The extra length of the rule after a ruled heading at the end of the
    column (`afterExtraOf False`). -/
def headingAfterExtra (env : Env) (r : Ruled) (extent : Int) : Int := headingAfterAt env r extent [] false

/-- The place of the rule after a ruled heading from the start of its box,
    as a list of none or one (`endRule`). -/
def headingAfterRule (env : Env) (r : Ruled) (extent : Int) (later : List Flow) (interior : Bool) : List Int :=
  match r.after, r.lines.getLast? with
  | some side, some l => [(headingAfterGeom env r extent later interior side l).2]
  | _, _ => []

/-- `ruleAfterInColumn` on the state `s` a ruled heading is placed to from
    `ready` with the extra `before`: its rule after ends above the notes. -/
def headingRuleFits (env : Env) (r : Ruled) (extent : Int) (later : List Flow) (ready : St) (before : Int) (s : St) : Bool :=
  match r.after, r.lines.getLast? with
  | some side, some l =>
    decide (ready.used + before + (headingAfterGeom env r extent later true side l).2 + side.weight ≤ limit env s - s.notesUsed)
  | _, _ => true

/-- A ruled heading put at `ready`, its rules around it; `ends` are the
    places of its rule after from the start of its box. -/
def putRuledHeading (env : Env) (ready : St) (before after : Int) (ends : List Int) (firstId : Nat) (extent : Int)
    (ls : List Line) : Except Failure St :=
  match putHeading env { ready with used := ready.used + before, adjust := ready.adjust - after } firstId extent ls with
  | .error e => .error e
  | .ok placed =>
    .ok { placed with
      adjust := ready.adjust
      used := placed.used + after
      afterRules := placed.afterRules ++ ends.map (fun p => ready.used + before + p) }

/-- The state a ruled heading of `size` is placed from (`ready` of
    `attempt`): the column made shorter, or `fit`. -/
def headingReady (env : Env) (hs : St) (firstId : Nat) (extent size : Int) : St :=
  if empty hs ∧ hs.adjust < 0 ∧ room env hs < size ∧ size ≤ env.capacity - hs.used - hs.notesUsed then
    tallAt hs firstId extent (room env hs)
  else fit env hs size

theorem headingReady_moved (env : Env) (hs : St) (firstId : Nat) (extent size : Int)
    (h : ¬((headingReady env hs firstId extent size).page = hs.page ∧ (headingReady env hs firstId extent size).column = hs.column)) :
    rank (headingReady env hs firstId extent size) < rank hs := by
  unfold headingReady at h ⊢
  split at h
  · exact absurd ⟨rfl, rfl⟩ h
  · rename_i c
    rw [if_neg c]
    exact I4_fit_moved env hs size h

def headingNotesExtent (env : Env) (ls : List Line) : Int :=
  (notesCount ls : Int) * env.pagePitch + (if 0 < notesCount ls then env.separator else 0)

/- `fitsFollowing` places a ruled block on trial, and a ruled heading asks
   `keepFollowing`, so the two are one recursion. `fitsFollowingGo` takes
   the flows after a block, `placeRuled` the flows after it, its rules and
   the rank of the column: a call of `placeRuled` from `fitsFollowingGo`
   keeps the flows after the block, and a call of `fitsFollowingGo` from
   `placeRuled` reads no more flows than those after the block
   (`keepWanted_length`). -/
set_option linter.unusedVariables false in
mutual
def fitsFollowingGo (inner : Inner) (env : Env) (st : St) (wanted : Nat) (extra : Int) : List Flow → Bool
  | .space s :: rest => fitsFollowingGo inner env st wanted (extra + s) rest
  | .needLines _ :: rest => fitsFollowingGo inner env st wanted extra rest
  | .adjustLines _ :: rest => fitsFollowingGo inner env st wanted extra rest
  | .noBreak :: rest => fitsFollowingGo inner env st wanted extra rest
  | .noBreakLines _ :: rest => fitsFollowingGo inner env st wanted extra rest
  | .keepNext _ _ :: rest => fitsFollowingGo inner env st wanted extra rest
  | .heading true _ _ :: _ => true
  | .heading false extent ls :: rest =>
    if extra + st.pending + env.firstNeed (decide (0 < st.notesUsed)) 1 [.heading false extent ls] ≤ room env st then
      match placeHeading env { st with pending := st.pending + extra } (headId ls) extent ls with
      | .ok placed => (placed.page == st.page && placed.column == st.column) && fitsFollowingGo inner env placed 1 0 rest
      | .error _ => false
    else false
  | .ruled r :: rest =>
    match r.heading with
    | some (true, _) => true
    | _ =>
      match placeRuled inner env { st with pending := st.pending + extra } r rest with
      | .ok placed => placed.page == st.page && placed.column == st.column
      | .error _ => false
  | .boxed i b a body :: _ => boxFits st (placeBox inner env { st with pending := st.pending + extra } i b a body)
  | rest => decide (extra + env.firstNeed (decide (0 < st.notesUsed)) wanted rest ≤ room env st)
termination_by fs => (fs.length, 5, 0)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; apply Prod.Lex.left; have := ruledRank_le r; omega)

def placeRuled (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) : Except Failure St :=
  match hh : r.heading with
  | some (recto, extent) =>
    let hs := headingStateOf env st recto
      (fitsFollowingGo inner env (keepVirtual env true st extent r.lines) (keepWanted later).1 0 (keepWanted later).2)
    let firstId := headId r.lines
    let start := headingBeforeExtra env r
    let before := headingBeforeAt env hs r
    -- the interior rule after while it and its area lie in the column, else
    -- the rule at the end of the column (PR #1152, root ADR 0397 I8)
    let afterIn := headingAfterAt env r extent later true
    let afterEdge := headingAfterExtra env r extent
    let inReady := headingReady env hs firstId extent (before + headingNeed env hs extent r.lines + afterIn)
    let edgeReady := headingReady env hs firstId extent (before + headingNeed env hs extent r.lines + afterEdge)
    if env.capacity < extent then .error (.headingTooTall firstId)
    else if env.capacity < start + extent + afterEdge + headingNotesExtent env r.lines then
      match ha : r.after, hb : r.before with
      | some _, _ => placeRuled inner env hs { r with after := none } later
      | none, some _ => placeRuled inner env hs { r with before := none } later
      | none, none => placeHeading env hs firstId extent r.lines
    else if h2 : ¬(inReady.page = hs.page ∧ inReady.column = hs.column) then
      if h3 : ¬(edgeReady.page = hs.page ∧ edgeReady.column = hs.column) then placeRuled inner env edgeReady r later
      else putRuledHeading env edgeReady before afterEdge (headingAfterRule env r extent later false) firstId extent r.lines
    else
      match putRuledHeading env inReady before afterIn (headingAfterRule env r extent later true) firstId extent r.lines with
      | .error e => .error e
      | .ok inside =>
        if headingRuleFits env r extent later inReady before inside then .ok inside
        else if h4 : ¬(edgeReady.page = hs.page ∧ edgeReady.column = hs.column) then placeRuled inner env edgeReady r later
        else putRuledHeading env edgeReady before afterEdge (headingAfterRule env r extent later false) firstId extent r.lines
  | none =>
    match r.lines.head?, r.lines.getLast? with
    | some first, some lastLine =>
      match ruledHere inner env st r later with
      | .error e => .error e
      | .ok (some placed) => .ok placed
      | .ok none =>
        if h1 : r.joined ∧ st.join.isSome ∧ empty st = false then
          placeRuled inner env (nextColumn env (flushPendingRule env st)) { r with joined := false } later
        else if env.capacity < ruledExtent env st r first lastLine later then placeLines env r.keep true st r.lines
        -- a block an empty column cannot hold with its rules is broken without them (golem-driver ADR 0035)
        else if h2 : ¬((fit env st (room env st + 1)).page = st.page ∧
            (fit env st (room env st + 1)).column = st.column) then
          placeRuled inner env (fit env st (room env st + 1)) r later
        else placeLines env r.keep true st r.lines
    | _, _ => .ok st
termination_by (later.length + 1, ruledRank r + 1, rank st)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.left; have := keepWanted_length later; omega
  · apply Prod.Lex.right; apply Prod.Lex.left; have := ruledRank_after r ha; omega
  · apply Prod.Lex.right; apply Prod.Lex.left; have := ruledRank_before r ha hb; omega
  · apply Prod.Lex.right; apply Prod.Lex.right
    exact Nat.lt_of_lt_of_le (headingReady_moved env _ _ _ _ h3) (rank_headingState_le env st recto _)
  · apply Prod.Lex.right; apply Prod.Lex.right
    exact Nat.lt_of_lt_of_le (headingReady_moved env _ _ _ _ h4) (rank_headingState_le env st recto _)
  · apply Prod.Lex.right; apply Prod.Lex.left; omega
  · apply Prod.Lex.right; apply Prod.Lex.left; simp [ruledRank, joinedRank, h1.1]
  · apply Prod.Lex.right; apply Prod.Lex.right; exact I4_fit_moved env st _ h2

/-- `ruledHere` of Physical.hs: a ruled paragraph in this column, with its
    rule after waiting to share its area with the next block's rule before
    when that block goes on in this column (golem-driver ADR 0027,
    「隣り合う罫線」), or with the area of its own before the next flow when
    the rule lies in the column.  Else the rule ends the column: its own
    area at the end of the column is counted in the block (the flows after
    it are not read), so that the rule stays in the column (root ADR 0397
    I8).  None when the block goes on to the next column. -/
def ruledHere (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) : Except Failure (Option St) :=
  match ruledLinesHere env st r later with
  | .error e => .error e
  | .ok inside =>
    let settled : Bool := match inside with
      | none => true
      | some placed =>
        if later.isEmpty then true
        else if joiningNext later then settlesHere inner env placed later
        else ruleAfterFitsLast env r later placed
    hereOr settled inside later (ruledLinesHere env st r [])
termination_by (later.length + 1, 0, 0)
decreasing_by
  all_goals simp_wf
  apply Prod.Lex.left; omega

/-- `settlesHere` of Physical.hs on the flows after a rule after that
    waits: the ruled block they begin with takes that rule into its area in
    the same column. -/
def settlesHere (inner : Inner) (env : Env) (st : St) (later : List Flow) : Bool :=
  match later with
  | .ruled next :: rest =>
    match ruledHere inner env st next rest with
    | .ok (some placed) => !movesForFollowing inner env st next placed rest
    | _ => false
  | _ => false
termination_by (later.length, 1, 0)
decreasing_by
  all_goals simp_wf
  all_goals (apply Prod.Lex.right; apply Prod.Lex.left; omega)

/-- `movesForFollowing` of Physical.hs: a ruled block placed as `full`
    goes on to the next column for what it keeps with it. -/
def movesForFollowing (inner : Inner) (env : Env) (st : St) (r : Ruled) (full : St) (later : List Flow) : Bool :=
  match h : keepAhead later with
  | some (_, wanted, rest) => !empty st && !fitsFollowingGo inner env full wanted 0 rest
  | none => if r.heading.isSome then !empty st && !fitsFollowingGo inner env full 1 0 later else false
termination_by (later.length + 1, 0, 0)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.left
    have := keepAheadGo_length [] later _ _ rest h
    simp at this; omega
  · apply Prod.Lex.left; omega
end

def fitsFollowing (inner : Inner) (env : Env) (st : St) (wanted : Nat) (flows : List Flow) : Bool :=
  fitsFollowingGo inner env st wanted 0 flows

/-- `keepFollowing`: a heading or a definition term goes on to the next
    column unless the first part of what follows fits after it. -/
def keepFollowing (inner : Inner) (env : Env) (heading : Bool) (st : St) (extent : Int) (ls : List Line) (later : List Flow) : St :=
  keepFrom env st (fitsFollowing inner env (keepVirtual env heading st extent ls) (keepWanted later).1 (keepWanted later).2)

/-- The lines of a paragraph moved on with what follows (`backCount` of
    `placeWithNext`). -/
def keptBack (k : Keep) (lastCount len : Nat) : Nat :=
  let requested := max lastCount k.last
  let minimumFirst := if 0 < lastCount then max 2 k.first else k.first
  if k.all ∨ len ≤ requested ∨ len - requested < minimumFirst then len else requested

/-- `heldHere` of Physical.hs: a keep-with-next of a visible separator
    waits in the current column for the flow being placed (root ADR 0398
    I7). -/
def heldHere (env : Env) (st : St) : Bool :=
  st.waits.any fun w =>
    (match w.1 with | .keepNext sp => env.held sp | _ => false) && w.2.1 == st.page && w.2.2.1 == st.column

/-- The column after the front part: the same one when it is still empty,
    or when a separator hold waits in it. -/
def afterFront (env : Env) (before : St) : St := if empty before = true ∨ heldHere env before = true then before else nextColumn env before

def placeWithNext (inner : Inner) (env : Env) (k : Keep) (start : Bool) (st : St) (ls : List Line)
    (lastCount firstCount : Nat) (later : List Flow) : Except Failure St :=
  match placeLines env k start st ls with
  | .error e => .error e
  | .ok full =>
    if fitsFollowing inner env full firstCount later then .ok full
    else if (ls.drop (ls.length - keptBack k lastCount ls.length)).isEmpty then .ok full
    else
      match placeLines env k start st (ls.take (ls.length - keptBack k lastCount ls.length)) with
      | .error e => .error e
      | .ok before =>
        placeLines env k (start && (ls.take (ls.length - keptBack k lastCount ls.length)).isEmpty)
          (afterFront env before) (ls.drop (ls.length - keptBack k lastCount ls.length))

/-- The verse lines moved on with what follows (`backCount`). -/
def stanzaBack (k : Keep) (lastCount total : Nat) : Nat :=
  let requested := max lastCount k.last
  if k.all ∨ total ≤ requested ∨ total - requested < k.first then total else requested

def placeStanzaWithNext (inner : Inner) (env : Env) (k : Keep) (st : St) (verses : List (List Line))
    (lastCount firstCount : Nat) (later : List Flow) : Except Failure St :=
  match placeStanza env k true st verses with
  | .error e => .error e
  | .ok full =>
    if fitsFollowing inner env full firstCount later then .ok full
    else
      match placeStanza env k true st (verses.take (verses.length - stanzaBack k lastCount verses.length)) with
      | .error e => .error e
      | .ok before =>
        if (verses.drop (verses.length - stanzaBack k lastCount verses.length)).isEmpty ∨ empty before = true ∨ heldHere env before = true then .ok full
        else placeStanza env k true (nextColumn env before) (verses.drop (verses.length - stanzaBack k lastCount verses.length))

def placeRuledKeeping (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) : Except Failure St :=
  match placeRuled inner env st r later with
  | .error e => .error e
  | .ok full =>
    let following := match keepAhead later with
      | some (_, wanted, rest) => some (wanted, rest)
      | none => if r.heading.isSome then some (1, later) else none
    match following with
    | some (wanted, rest) =>
      if empty st = false ∧ fitsFollowing inner env full wanted rest = false then
        placeRuled inner env (nextColumn env (flushPendingRule env st)) { r with joined := false } later
      else .ok full
    | none => .ok full


/-! ## Code -/

def codeSpanOf (spans : List Nat) (k : Nat) : Nat := spans.getD k 1

/-- `spanOf` of `placeCode`. -/
def codeExtent (env : Env) (caption : Int) (isFirst continued : Bool) (spans : List Nat) (total n : Nat) : Int :=
  (if isFirst then caption else 0) + (codeSpanOf spans (n + if continued ∧ n < total then 1 else 0) : Int) * env.pagePitch

def codeMinimum (isFirst : Bool) (first total : Nat) : Nat := if isFirst then min total (max 1 first) else 1

/-- The consecutive numbers of rows from `j` that fit. -/
def codeFit (ok : Nat → Bool) (j : Nat) : Nat → Nat
  | 0 => 0
  | r + 1 => if ok j then codeFit ok (j + 1) r + 1 else 0

theorem codeFit_le (ok : Nat → Bool) : ∀ (j n : Nat), codeFit ok j n ≤ n
  | _, 0 => Nat.le_refl _
  | j, r + 1 => by
    simp only [codeFit]
    split
    · exact Nat.succ_le_succ (codeFit_le ok (j + 1) r)
    · exact Nat.zero_le _

def codeFitting (env : Env) (st : St) (caption : Int) (isFirst continued : Bool) (spans : List Nat) (total : Nat) : Nat :=
  codeFit (fun n => decide (codeExtent env caption isFirst continued spans total n + (if empty st then 0 else st.pending) ≤ room env st)) 1 total

/-- `count` of `placeCode`: the rows that fit, or none below the minimum. -/
def codeCount (env : Env) (st : St) (caption : Int) (first : Nat) (isFirst continued : Bool) (spans : List Nat) (total : Nat) : Nat :=
  if codeMinimum isFirst first total ≤ codeFitting env st caption isFirst continued spans total
  then codeFitting env st caption isFirst continued spans total else 0

theorem codeCount_le (env : Env) (st : St) (c : Int) (f : Nat) (i k : Bool) (sp : List Nat) (t : Nat) :
    codeCount env st c f i k sp t ≤ t := by
  unfold codeCount
  split
  · exact codeFit_le _ _ _
  · omega

set_option linter.unusedVariables false in
def placeCode (env : Env) (caption : Int) (first : Nat) (continued : Bool) (spans : List Nat)
    (isFirst : Bool) (st : St) (rows : List Line) : Except Failure St :=
  match rows with
  | [] => .ok st
  | r :: rs =>
    if env.capacity < codeExtent env caption isFirst continued spans (rs.length + 1) (codeMinimum isFirst first (rs.length + 1)) then
      .error (.codeTooTall r.id)
    else
      let found := seek env (fun s => decide (0 < codeCount env s caption first isFirst continued spans (rs.length + 1))) st
      let count := codeCount env found caption first isFirst continued spans (rs.length + 1)
      have hc : count ≤ rs.length + 1 := codeCount_le env found caption first isFirst continued spans (rs.length + 1)
      if h : count = 0 then .error (.noProgress r.id)
      else
        let extent := codeExtent env caption isFirst continued spans (rs.length + 1) count
        let grid := codeSpanOf spans (count + if continued ∧ count < rs.length + 1 then 1 else 0)
        let placed := putSlot (fit env found extent) extent (.code (((r :: rs).take count).map (·.id)) grid)
        if h2 : count = rs.length + 1 then .ok placed
        else placeCode env caption first continued spans false (nextColumn env placed) ((r :: rs).drop count)
termination_by rows.length
decreasing_by
  simp_wf
  exact Nat.sub_lt (Nat.succ_pos _) (Nat.pos_of_ne_zero h)

/-! ## Wrapped figures -/

/-- The loop of `fittingWrapped`: the lines beside a wrapped figure that fit
    with the notes they show. -/
def fittingWrappedGo (env : Env) (st : St) (figureEnd used notes : Int) : List Line → Nat
  | [] => 0
  | l :: ls =>
    let n : Int := noteLines l
    let sep : Int := if 0 < n ∧ notes = 0 then env.separator else 0
    let used' := used + env.wrappedBefore l.id + env.pitchOf l.id
    let available := limit env st - max figureEnd used' - notes - sep
    let shown := max 0 (min n (Int.fdiv available env.pagePitch))
    let notes' := notes + (if shown = 0 then 0 else sep + shown * env.pagePitch)
    if max figureEnd used' + notes + (if 0 < n then sep + env.pagePitch else 0) ≤ limit env st
    then fittingWrappedGo env st figureEnd used' notes' ls + 1 else 0

def fittingWrapped (env : Env) (st : St) (figureEnd : Int) (ls : List Line) : Nat :=
  fittingWrappedGo env st figureEnd st.used st.notesUsed ls

/-- A line beside a wrapped figure, the rest of the figure reserved. -/
def putWrappedLine (env : Env) (figureEnd : Int) (st : St) (l : Line) : Except Failure St :=
  match putLine env { st with adjust := st.adjust - max 0 (figureEnd - st.used - env.pitchOf l.id) } l with
  | .error e => .error e
  | .ok placed => .ok { placed with adjust := st.adjust }

/-- The fold of `FWrapped` over the lines beside the figure. -/
def putBeside (env : Env) (figureEnd : Int) (st : St) : List Line → Except Failure St
  | [] => .ok st
  | l :: ls =>
    match putWrappedLine env figureEnd { st with used := st.used + env.wrappedBefore l.id } l with
    | .error e => .error e
    | .ok s => putBeside env figureEnd s ls

/-- The next column when the line does not fit with its gap (`ready` of
    `placeWrappedOverflow`). -/
def overflowMove (env : Env) (st : St) (l : Line) (gap : Int) : St :=
  if fitting env { st with pending := st.pending + gap } [l] = 0 ∧ empty st = false then nextColumn env st else st

/-- The column a line after a wrapped figure is put in (`atLine` of
    `placeWrappedOverflow`), with the gap before it. -/
def overflowReady (env : Env) (st : St) (l : Line) : St :=
  let gap := if empty st then 0 else env.wrappedBefore l.id
  let ready := overflowMove env st l gap
  fit env { ready with pending := ready.pending + if empty ready then 0 else gap } (env.pitchOf l.id)

/-- `placeWrappedOverflow`: the lines that do not fit beside the figure. -/
def placeWrappedOverflow (env : Env) (st : St) : List Line → Except Failure St
  | [] => .ok st
  | l :: rest =>
    match putLine env (overflowReady env st l) l with
    | .error e => .error e
    | .ok placed => placeWrappedOverflow env placed rest

/-- `FWrapped`: the figure at the start of its lines, those that fit beside
    it, and the rest after it. -/
def placeWrapped (env : Env) (st : St) (i : Nat) (extent : Int) (beside : List Line) : Except Failure St :=
  if env.capacity < extent then .error (.figureTooTall i)
  else
    let start := fit env st extent
    let origin := start.used
    let withFigure := putSlot start 0 (.wrapped i)
    let count := fittingWrapped env withFigure (origin + extent) beside
    match putBeside env (origin + extent) withFigure (beside.take count) with
    | .error e => .error e
    | .ok placed =>
      let after := { placed with used := max placed.used (origin + extent) }
      if (beside.drop count).isEmpty then .ok after
      else placeWrappedOverflow env (nextColumn env after) (beside.drop count)

/-! ## A paragraph beside a wrapped figure -/

/-- `PhysicalWrap`: the page, the column and the end of an exclusion. -/
abbrev Region := Option (Nat × Nat × Int)

/-- `activeWrapEnd`: the end of the exclusion in its column, 0 elsewhere. -/
def wrapEnd (region : Region) (st : St) : Int :=
  match region with
  | some (p, c, e) => if p = st.page ∧ c = st.column then e else 0
  | none => 0

/-- `endPhysicalWrap`: the used length at least the end of the exclusion. -/
def endWrap (region : Region) (st : St) : St := { st with used := max st.used (wrapEnd region st) }

/-- `movePhysicalCursor`. -/
def moveCursor (env : Env) (region : Region) (st : St) : St := nextColumn env (endWrap region st)

/-- `beginPhysicalWrap`: the wrapped figure at the start of its lines, and
    its exclusion. -/
def beginWrap (env : Env) (st : St) (ident : Nat) (extent : Int) : Except Failure (St × Region) :=
  if env.capacity < extent then .error (.figureTooTall ident)
  else
    let ready := fit env st extent
    .ok (checkWaits (putSlot ready 0 (.wrapped ident)), some (ready.page, ready.column, ready.used + extent))

/-- The loop of `fittingHere` in the column of an exclusion. -/
def fittingWrapGo (env : Env) (st : St) (e used notes : Int) : List Line → Nat
  | [] => 0
  | l :: ls =>
    let n := noteLines l
    let sep : Int := if 0 < n ∧ notes = 0 then env.separator else 0
    let used' := used + env.pitchOf l.id
    let notes' := notes + sep + (n : Int) * env.pagePitch
    if max e used' + notes' ≤ limit env st then fittingWrapGo env st e used' notes' ls + 1 else 0

/-- `fittingHere` of `trialParagraphPartLimit`. -/
def fittingHere (env : Env) (region : Region) (st : St) (rows : List Line) : Nat :=
  if wrapEnd region st = 0 then fitting env st rows
  else fittingWrapGo env st (wrapEnd region st) (st.used + if empty st then 0 else st.pending) st.notesUsed rows

/-- `put` of `trialParagraphPartLimit`: a line beside the exclusion, or a line. -/
def putHere (env : Env) (region : Region) (st : St) (l : Line) : Except Failure St :=
  if 0 < wrapEnd region st then putWrappedLine env (wrapEnd region st) st l else putLine env st l

def putHereLines (env : Env) (region : Region) (st : St) : List Line → Except Failure St
  | [] => .ok st
  | l :: ls =>
    match putHere env region st l with
    | .error e => .error e
    | .ok s => putHereLines env region s ls

/-- `selected` with the prefix limit. -/
def limited (limit : Option Nat) (n : Nat) : Nat :=
  match limit with
  | some m => min m n
  | none => n

/-- `trialParagraphPartLimit` after its first test and the relaxation of
    keep-all-lines. -/
def trialWrapRest (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool) (st : St)
    (rows : List Line) (firstId : Nat) : Except Failure Part :=
  let total := rows.length
  let count := fittingHere env region st rows
  let selected := limited limit (splitAtBreak k start total count)
  let emptyish := empty st || (headingOnly st && decide (0 < count))
  if (empty st ∧ st.adjust < 0 ∧ count = 0) ∨ (selected = 0 ∧ emptyish = false) then
    .ok (.moved (moveCursor env region st) k)
  else
    let takeCount := if selected = 0 then max 1 count else selected
    let here := rows.take takeCount
    let forced := selected = 0 ∧ emptyish ∧ takeCount < total
    let short :=
      (if forced ∧ start ∧ takeCount < k.first then [Unmet.shortPart true firstId k.first takeCount] else []) ++
      (if forced ∧ total - takeCount < k.last then [Unmet.shortPart false firstId k.last (total - takeCount)] else [])
    let ready := fit env st (sumPitch env here)
    match putHereLines env region ready here with
    | .error e => .error e
    | .ok placed => .ok (.placed takeCount { placed with unmet := placed.unmet ++ short } k)

def trialWrapFrom (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool) (st : St)
    (rows : List Line) : Except Failure Part :=
  match rows with
  | [] => .ok (.placed 0 st k)
  | first :: _ =>
    if env.capacity < env.pitchOf first.id then .error (.lineTooTall first.id)
    else if k.all ∧ start ∧ fittingHere env region st rows < rows.length then
      if empty st || headingOnly st then
        trialWrapRest env region limit { k with all := false } start (addUnmet (.splitKept first.id) st) rows first.id
      else .ok (.moved (moveCursor env region st) k)
    else trialWrapRest env region limit k start st rows first.id

/-- `trialParagraphPartLimit` with a wrap region and a prefix limit. -/
def trialWrap (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool) (st : St)
    (rows : List Line) : Except Failure Part :=
  match checkRows env rows with
  | some e => .error e
  | none => trialWrapFrom env region limit k start st rows

/-- Going on from a state with what waits of `st` lowers the rank of `st`
    when it is not empty or made shorter. -/
theorem nextColumn_rank_of (env : Env) (X st : St) (hw : waiting X = waiting st)
    (hx : adjustWeight X ≤ adjustWeight st) (hc : X.columns = st.columns)
    (h : empty st = false ∨ st.adjust < 0) : rank (nextColumn env X) < rank st := by
  obtain ⟨le, e, a, c⟩ := open_waiting env false X
  exact (open_rank _ X st le e a c hw hx hc).2 h

theorem I4_moveCursor_rank (env : Env) (region : Region) (st : St) (h : empty st = false ∨ st.adjust < 0) :
    rank (moveCursor env region st) < rank st :=
  nextColumn_rank_of env _ st rfl (Nat.le_of_eq (adjustWeight_congr rfl rfl rfl rfl)) rfl h

theorem trialWrapRest_moved (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool) (st : St)
    (rows : List Line) (fid : Nat) (next : St) (r : Keep)
    (h : trialWrapRest env region limit k start st rows fid = .ok (.moved next r)) :
    r = k ∧ next = moveCursor env region st ∧ (empty st = false ∨ st.adjust < 0) := by
  unfold trialWrapRest at h
  dsimp only at h
  split at h
  · rename_i c
    injection h with h; injection h with h1 h2
    refine ⟨h2.symm, h1.symm, ?_⟩
    cases c with
    | inl c => exact Or.inr c.2.1
    | inr c =>
      have e := c.2
      simp only [Bool.or_eq_false_iff] at e
      exact Or.inl e.1
  · split at h <;> simp at h

theorem trialWrapRest_placed (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool) (st : St)
    (rows : List Line) (fid : Nat) (c : Nat) (next : St) (r : Keep)
    (h : trialWrapRest env region limit k start st rows fid = .ok (.placed c next r)) : 1 ≤ c := by
  unfold trialWrapRest at h
  dsimp only at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · injection h with h; injection h with h1 _ _
      subst h1; split <;> omega

theorem I4_trialWrap_moved (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool) (st : St)
    (rows : List Line) (next : St) (relaxed : Keep)
    (h : trialWrap env region limit k start st rows = .ok (.moved next relaxed)) :
    keepRank relaxed < keepRank k ∨ (keepRank relaxed = keepRank k ∧ rank next < rank st) := by
  unfold trialWrap at h
  split at h
  · cases h
  unfold trialWrapFrom at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · rename_i c
        split at h
        · obtain ⟨e, _, _⟩ := trialWrapRest_moved env region limit _ start _ _ _ next relaxed h
          left; subst e; simp [keepRank, c.1]
        · injection h with h; injection h with h1 h2
          subst h1; subst h2
          rename_i ne
          refine Or.inr ⟨rfl, I4_moveCursor_rank env region st (Or.inl ?_)⟩
          cases e : empty st
          · rfl
          · exact absurd (by simp [e]) ne
      · obtain ⟨e, n, m⟩ := trialWrapRest_moved env region limit _ start _ _ _ next relaxed h
        subst e; subst n
        exact Or.inr ⟨rfl, I4_moveCursor_rank env region st m⟩

/-- `parts` of golem-typeset's `paragraph`: the rank of a retry. -/
def limitRank (limit : Option Nat) (total : Nat) : Nat :=
  match limit with
  | some n => n
  | none => total + 1

/-- The item after the break of the `count`-th line. -/
def nextItem (tail : List (Line × Nat)) (count start : Nat) : Nat :=
  ((tail.drop (count - 1)).head?.map (·.2)).getD start

/-- `minimumFront` of `paragraph`. -/
def minimumFront (isStart : Bool) (lastWanted : Nat) (k : Keep) : Nat :=
  if isStart then max (if 0 < lastWanted then 2 else 1) k.first else 1

set_option linter.unusedVariables false in
/-- `parts` of `paragraph` in golem-typeset's `causalFreeFlow`: a paragraph
    beside a wrapped figure, its unplaced source broken again at each
    cursor. `breaker at before start` stands for `composeAt` and
    `numberedLines`: the lines of the source from the item `start`, each
    with the item after its break, numbered after `before` lines; `items`
    is the number of items of the source. `follows` stands for `probeNext`,
    and `hold` for `keepPhysicalNext` after the last part. Where
    golem-typeset would retry with a bound that is not smaller, or go on
    from an item that is not later, the model returns `noProgress`. -/
def parts (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St)
    (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) : Except Failure St :=
  match hm : trialWrap env region limit k isStart at' ((breaker at' before start).map (·.1)) with
  | .error e => .error e
  | .ok (.moved moved relaxed) =>
    parts env region breaker items lastWanted follows hold none relaxed isStart start before moved
  | .ok (.placed count placed relaxed) =>
    if (breaker at' before start).length ≤ count then
      if follows (checkWaits placed) || (breaker at' before start).isEmpty then .ok (hold (checkWaits placed))
      else if h1 : minimumFront isStart lastWanted k ≤ count - max lastWanted (max 1 relaxed.last) ∧ relaxed.all = false then
        if h2 : count - max lastWanted (max 1 relaxed.last) < limitRank limit (breaker at' before start).length then
          parts env region breaker items lastWanted follows hold (some (count - max lastWanted (max 1 relaxed.last)))
            k isStart start before at'
        else .error (.noProgress 0)
      else if h3 : empty at' = false then
        parts env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at')
      else .ok (hold (checkWaits placed))
    else if h4 : start < nextItem (breaker at' before start) count start ∧ start < items then
      if (breaker (moveCursor env region placed) (before + count) (nextItem (breaker at' before start) count start)).length
          < relaxed.last then
        if h5 : minimumFront isStart lastWanted k < count then
          if h6 : count - 1 < limitRank limit (breaker at' before start).length then
            parts env region breaker items lastWanted follows hold (some (count - 1)) k isStart start before at'
          else .error (.noProgress 0)
        else if h7 : empty at' = false then
          parts env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at')
        else
          parts env region breaker items lastWanted follows hold none relaxed false
            (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed)
      else
        parts env region breaker items lastWanted follows hold none relaxed false
          (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed)
    else .error (.noProgress 0)
termination_by (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right
    cases I4_trialWrap_moved env region limit k isStart at' _ moved relaxed hm with
    | inl l => exact Prod.Lex.left _ _ l
    | inr e => rw [e.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ e.2)
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right
    simp only [limitRank] at h2 ⊢; exact h2
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region at' (Or.inl h3)
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right
    simp only [limitRank] at h6 ⊢; exact h6
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region at' (Or.inl h7)
  · apply Prod.Lex.left; have a := h4.1; have b := h4.2; omega
  · apply Prod.Lex.left; have a := h4.1; have b := h4.2; omega

/-! ## The loops of `causalFreeFlow` beside a wrapped figure -/

/-- What `causalFreeFlow` reads from the composition and from what follows
    a stanza, given as arguments as `parts` takes its breaker.
    `compose at i` stands for `composeAt` from the item 0 and
    `numberedLines`: the rows of the paragraph or verse line `i` composed
    at the cursor `at`.  `binding i` is `bindingAfter` of `i` (`lastWanted`
    and `wanted`), `keepOf i` the keep of `i`, `holds i` whether `i` keeps
    with what follows (`snd (paraStartAndKeep unit) > 0`), `hold i` its
    `keepPhysicalNext`, and `ident at i` its first line in the composition of
    the cursor `at` (`bUnitFirsts`, which counts the lines composed before
    `i` at the cursors they were placed at).  `sameVerse i j`
    is whether `j` is a verse line of the stanza of `i`, and `isStanza i`
    whether `i` is a verse line. -/
structure Beside where
  compose : St → Nat → List Line
  binding : Nat → Nat × Nat
  keepOf : Nat → Keep
  holds : Nat → Bool
  hold : Nat → Nat → Bool → St → St
  ident : St → Nat → Nat
  isStanza : Nat → Bool
  sameVerse : Nat → Nat → Bool

/-- `tryVerses` of `causalFreeFlow`: each verse line composed at the cursor
    the verse lines before it leave, while it is placed whole in the
    column of the cursor.  It recurses on the verse lines. -/
def tryVerses (env : Env) (region : Region) (b : Beside) (cursor : St) : List Nat → Except Failure (List St)
  | [] => .ok []
  | index :: later =>
    match trialWrap env region none ⟨1, 1, false⟩ true cursor (b.compose cursor index) with
    | .error e => .error e
    | .ok (.placed count placed _) =>
      if count = (b.compose cursor index).length ∧ placed.page = cursor.page ∧ placed.column = cursor.column then
        match tryVerses env region b placed later with
        | .error e => .error e
        | .ok rest => .ok (placed :: rest)
      else .ok []
    | .ok (.moved _ _) => .ok []

theorem tryVerses_length (env : Env) (region : Region) (b : Beside) (cursor : St) (indices : List Nat)
    (trials : List St) (h : tryVerses env region b cursor indices = .ok trials) : trials.length ≤ indices.length := by
  induction indices generalizing cursor trials with
  | nil => simp [tryVerses] at h; subst h; simp
  | cons index later ih =>
    unfold tryVerses at h
    split at h
    · cases h
    · split at h
      · split at h
        · cases h
        · rename_i rest e
          injection h with h; subst h
          have := ih _ _ e
          simp only [List.length_cons]; omega
      · injection h with h; subst h; simp
    · injection h with h; subst h; simp

/-- The verse lines of a stanza from its first verse line `i`: `span
    sameVerse (i : more)`, where `i` is a verse line of its own stanza. -/
def verseSpan (b : Beside) (i : Nat) (more : List Nat) : List Nat × List Nat :=
  (i :: more.takeWhile (b.sameVerse i), more.dropWhile (b.sameVerse i))

theorem verseSpan_after (b : Beside) (i : Nat) (more : List Nat) : (verseSpan b i more).2.length ≤ more.length := by
  unfold verseSpan
  induction more with
  | nil => simp
  | cons x xs ih =>
    simp only [List.dropWhile_cons]
    split
    · simp only [List.length_cons] at ih ⊢; omega
    · simp

/-- What the probe of `causalFreeFlow` reads besides `Beside`: `prefix i j
    at` stands for `stepPhysicalCursor` of the controls between `i` and `j`
    and the start break of `j`; `following at wanted` for the result of
    `probeNext` after the last paragraph beside the figure
    (`physicalFollowingRows` and `fitsPhysicalFollowing` on the cursor
    `endPhysicalWrap` leaves); `required wanted keep rows` for
    `fst (physicalFollowingRows wanted [FParagraph keep rows])`; and
    `verseRequired ready verses trials n` for the rows of the first `n` verse
    lines as the trials from the cursor `ready` composed them. -/
structure Probe where
  prefixAt : Nat → Nat → St → Except Failure St
  following : St → Nat → Nat × Bool × Bool
  required : Nat → Keep → List Line → Nat
  verseRequired : St → List Nat → List St → Nat → Nat

/- `probeNext` and `probeChain` of `causalFreeFlow`: whether what follows a
   paragraph beside a wrapped figure fits after it.  `probeNext` passes
   `probeChain` fewer flows than it takes: the paragraph or the stanza it
   tries comes off the front.  `probeChain` passes `probeNext` the same
   flows, so the two stop by the number of flows and then the function. -/
mutual
def probeNext (env : Env) (region : Region) (b : Beside) (p : Probe) (index : Nat) (later : List Nat) (cursor : St)
    (wanted : Nat) : Except Failure (Nat × Bool × Bool) :=
  match later with
  | [] => .ok (p.following (endWrap region cursor) wanted)
  | nextIndex :: more =>
    match p.prefixAt index nextIndex cursor with
    | .error e => .error e
    | .ok ready =>
      let same := fun (a c : St) => a.page = c.page ∧ a.column = c.column
      if b.isStanza nextIndex then
        let verses := (verseSpan b nextIndex more).1
        let afterVerses := (verseSpan b nextIndex more).2
        let wantedVerses := max (firstPart (b.keepOf nextIndex) true verses.length) (min wanted verses.length)
        match tryVerses env region b ready verses with
        | .error e => .error e
        | .ok trials =>
          let required := p.verseRequired ready verses trials wantedVerses
          let prefixFits := decide (same cursor ready) && decide (wantedVerses ≤ trials.length)
          let chain : Except Failure Bool :=
            if prefixFits && decide (wantedVerses = verses.length) then
              match trials.getLast? with
              | some placed => probeChain env region b p (verses.getLast?.getD nextIndex) afterVerses placed
              | none => .ok true
            else .ok true
          match chain with
          | .error e => .error e
          | .ok chainFits => .ok (required, true, prefixFits && chainFits)
      else
        let rows := b.compose ready nextIndex
        let keep := b.keepOf nextIndex
        let required := p.required wanted keep rows
        match trialWrap env region none { keep with first := max keep.first required } true ready rows with
        | .error e => .error e
        | .ok (.moved _ _) => .ok (required, true, false)
        | .ok (.placed count placed _) =>
          let prefixFits := decide (same cursor ready) && decide (same ready placed) && decide (required ≤ count)
          let chain : Except Failure Bool :=
            if prefixFits && decide (count = rows.length) then probeChain env region b p nextIndex more placed
            else .ok true
          match chain with
          | .error e => .error e
          | .ok chainFits => .ok (required, true, prefixFits && chainFits)
termination_by (later.length, 0)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.left; have := verseSpan_after b index later; omega
  · apply Prod.Lex.left; omega

def probeChain (env : Env) (region : Region) (b : Beside) (p : Probe) (index : Nat) (later : List Nat) (cursor : St) :
    Except Failure Bool :=
  if 0 < (b.binding index).2 ∨ 0 < (b.binding index).1 then
    match probeNext env region b p index later cursor (b.binding index).2 with
    | .error e => .error e
    | .ok r => .ok r.2.2
  else .ok true
termination_by (later.length, 1)
decreasing_by
  all_goals simp_wf
  apply Prod.Lex.right; omega
end

/-- What `stanza` reads besides `Beside`: `follows i later at wanted`
    stands for `probeNext` after the last verse line `i`, and `fallback i
    later at` for `paragraph` (the loop `parts`) placing the verse line
    `i` by its display rows. -/
structure StanzaArgs where
  follows : Nat → List Nat → St → Nat → Except Failure (Nat × Bool × Bool)
  fallback : Nat → List Nat → St → Except Failure St

/- `stanza` of `causalFreeFlow` and its `accept`.  `stanza` takes the verse
   lines of a stanza still to place; `accept count` places the first
   `count` verse lines that `tryVerses` placed whole.  Every call of
   `stanza` from `stanza` or `accept` places a verse line or more
   (`accept` with `count` at least 1, and the fallback of one verse line
   that an empty column cannot hold), clears keep-all-lines, or moves a
   cursor that is not empty to the next column (`I4_moveCursor_rank`);
   `accept` calls itself with a smaller count.  So the two stop by the
   number of the verse lines, `keepRank`, `rank`, the function, and the
   count.  A count of 0, or one beyond the trials, which golem-typeset
   would read with `!!` and fail on, returns `noProgress`; `count` is 1 or
   more and at most the trials (`splitAtBreak` returns at most the count
   it takes). -/
set_option linter.unusedVariables false in
mutual
def stanza (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (later : List Nat) (keep : Keep)
    (isStart : Bool) (cursor : St) (indices : List Nat) : Except Failure St :=
  match indices with
  | [] => .ok (checkWaits cursor)
  | firstIndex :: rest =>
    match tryVerses env region b cursor (firstIndex :: rest) with
    | .error e => .error e
    | .ok trials =>
      let whole := trials.length
      let total := rest.length + 1
      let selected := splitAtBreak keep isStart total whole
      if keep.all ∧ isStart ∧ whole < total then
        if empty cursor then
          stanza env region b a later { keep with all := false } isStart
            (addUnmet (.splitKept (b.ident cursor firstIndex)) cursor) (firstIndex :: rest)
        else if h : empty cursor = false then
          stanza env region b a later keep isStart (moveCursor env region cursor) (firstIndex :: rest)
        else .ok cursor
      else if 0 < selected then
        accept env region b a later keep isStart cursor (firstIndex :: rest) trials selected []
      else if h : empty cursor = false then
        stanza env region b a later keep isStart (moveCursor env region cursor) (firstIndex :: rest)
      else if 0 < whole then
        accept env region b a later keep isStart cursor (firstIndex :: rest) trials whole
          ((if isStart ∧ whole < keep.first then [Unmet.shortPart true (b.ident cursor firstIndex) keep.first whole] else []) ++
            (if total - whole < keep.last then [Unmet.shortPart false (b.ident cursor firstIndex) keep.last (total - whole)] else []))
      else
        match a.fallback firstIndex (rest ++ later) cursor with
        | .error e => .error e
        | .ok next => stanza env region b a later keep false next rest
termination_by (indices.length, keepRank keep, rank cursor, 1, 0)
decreasing_by
  all_goals simp_wf
  · rename_i c _; apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, c.1]
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region cursor (Or.inl h)
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; omega
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region cursor (Or.inl h)
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; omega
  · apply Prod.Lex.left; omega

def accept (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (later : List Nat) (keep : Keep)
    (isStart : Bool) (cursor : St) (indices : List Nat) (trials : List St) (count : Nat) (problems : List Unmet) :
    Except Failure St :=
  if h0 : count = 0 then .error (.noProgress (b.ident cursor (indices.headD 0)))
  else
    match trials[count - 1]? with
    | none => .error (.noProgress (b.ident cursor (indices.headD 0)))
    | some placed =>
      let warned := { placed with unmet := placed.unmet ++ problems }
      if hr : (indices.drop count).isEmpty then
        let settled := checkWaits warned
        let lastIndex := indices.getLast?.getD 0
        let lastWanted := (b.binding lastIndex).1
        let wanted := (b.binding lastIndex).2
        let probed : Except Failure (Nat × Bool × Bool) :=
          if 0 < wanted ∨ 0 < lastWanted then a.follows lastIndex later settled wanted else .ok (0, true, true)
        match probed with
        | .error e => .error e
        | .ok (required, linesOnly, fits) =>
          let held := if b.holds lastIndex then b.hold lastIndex required linesOnly settled else settled
          let front := count - max lastWanted (max 1 keep.last)
          if fits then .ok held
          else if (if isStart then max 1 keep.first else 1) ≤ front ∧ keep.all = false then
            accept env region b a later keep isStart cursor indices trials front []
          else if h : empty cursor = false then
            stanza env region b a later keep isStart (moveCursor env region cursor) indices
          else .ok held
      else
        stanza env region b a later keep false (moveCursor env region warned) (indices.drop count)
termination_by (indices.length, keepRank keep, rank cursor, 0, count)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; omega
  · apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
    exact I4_moveCursor_rank env region cursor (Or.inl h)
  · apply Prod.Lex.left
    have : indices.length ≠ 0 := by
      intro e; rw [List.length_eq_zero.mp e] at hr; simp [List.isEmpty] at hr
    omega
end

/-- What the loop over the wrapped figures of `causalFreeFlow` reads, given
    as arguments.  `itemOf job` is the outermost list item of the figure
    `job` when page or spread retention is on (`[key | retaining, …]`).
    `outside prior done job at` stands for `stepPhysicalCursor` of the
    flows before the item, `run prior done job at` for `runJob` of `job`
    after the flows before it (the paragraphs beside it go through
    `paragraphs`, `parts` and `stanza`), `itemRest key prior at` for
    `stepPhysicalCursor` of the rest of the item, `finish prior done at`
    for the flows after the last figure and `finishPhysicalCursor`, and
    `retain` for `retainPhysicalPart`, which may run its trial at several
    cursors. -/
structure Jobs where
  itemOf : Nat → Option Nat
  outside : Option Nat → Option Nat → Nat → St → Except Failure St
  run : Option Nat → Option Nat → Nat → St → Except Failure St
  itemRest : Nat → Nat → St → Except Failure St
  finish : Option Nat → Option Nat → St → Except Failure St
  retain : {α : Type} → (St → Except Failure (α × St)) → St → Except Failure (α × St)

/-- The end of `itemJobs`: the rest of the item after the figure `prior`,
    with the figures `later` left. -/
def itemEnd (j : Jobs) (key prior : Nat) (cursor : St) (later : List Nat) :
    Except Failure ((Nat × {l : List Nat // l.length ≤ later.length}) × St) :=
  match j.itemRest key prior cursor with
  | .error e => .error e
  | .ok final => .ok ((prior, ⟨later, Nat.le_refl _⟩), final)

/-- `itemJobs` of `causalFreeFlow`: the later figures of the same list
    item, then the rest of the item.  It returns the last figure placed,
    the figures it left, which are no more than it took, and the cursor.
    It recurses on the figures. -/
def itemJobs (j : Jobs) (key prior : Nat) (cursor : St) :
    (later : List Nat) → Except Failure ((Nat × {l : List Nat // l.length ≤ later.length}) × St)
  | next :: more =>
    if j.itemOf next = some key then
      match j.run (some prior) none next cursor with
      | .error e => .error e
      | .ok nextCursor =>
        match itemJobs j key next nextCursor more with
        | .error e => .error e
        | .ok ((last, ⟨left, hl⟩), placed) =>
          .ok ((last, ⟨left, by simp only [List.length_cons]; omega⟩), placed)
    else itemEnd j key prior cursor (next :: more)
  | [] => itemEnd j key prior cursor []

set_option linter.unusedVariables false in
/-- `jobsFrom` of `causalFreeFlow`: each wrapped figure with the paragraphs
    beside it, a figure in a list item with the later figures of its item.
    Each call places one figure or more and goes on with the figures
    `itemJobs` left, so it stops by the number of figures. -/
def jobsFrom (j : Jobs) (prior done : Option Nat) (cursor : St) (jobs : List Nat) : Except Failure St :=
  match jobs with
  | [] => j.finish prior done cursor
  | job :: rest =>
    match j.itemOf job with
    | some key =>
      match j.outside prior done job cursor with
      | .error e => .error e
      | .ok ready =>
        let trial : St → Except Failure ((Nat × {l : List Nat // l.length ≤ rest.length}) × St) := fun at' =>
          match j.run prior done job at' with
          | .error e => .error e
          | .ok first => itemJobs j key job first rest
        match j.retain trial ready with
        | .error e => .error e
        | .ok ((lastJob, ⟨left, hl⟩), placedCursor) => jobsFrom j (some lastJob) (some key) placedCursor left
    | none =>
      match j.run prior done job cursor with
      | .error e => .error e
      | .ok placed => jobsFrom j (some job) none placed rest
termination_by jobs.length
decreasing_by
  all_goals simp_wf
  all_goals omega

/-- What the loop over the paragraphs beside a wrapped figure reads besides
    `Beside` and `StanzaArgs`.  `preliminary prior index at` stands for
    `stepPhysicalCursor` of the controls between `prior` and `index` and of
    the start break of `index`; `ready prior index at rows` for
    `stepPhysicalPrefix` of the same flows followed by the rows of `index`
    (the paragraph, or each verse line of the stanza); `orig i` for the rows
    of the verse line `i` as composed before, which golem-typeset reads for
    the verse lines `tryVerses` did not place; and `paragraph index later
    at` for `paragraph` (the loop `parts`) with the keep of `index` and its
    `bindingAfter`. -/
structure Paras where
  preliminary : Nat → Nat → St → Except Failure St
  ready : Nat → Nat → St → List (List Line) → Except Failure St
  orig : Nat → List Line
  paragraph : Nat → List Nat → St → Except Failure St

/-- The rows of each verse line of a stanza that `paragraphs` steps the
    prefix with: a verse line `tryVerses` placed is composed at the cursor
    the verse lines before it left (`starts`), one it did not place keeps
    the rows composed before. -/
def verseRows (b : Beside) (p : Paras) : List St → List Nat → List (List Line)
  | at' :: more, i :: rest => b.compose at' i :: verseRows b p more rest
  | [], rest => rest.map p.orig
  | _, [] => []

/-- `paragraphs` of `causalFreeFlow`: the paragraphs and stanzas beside a
    wrapped figure, in order.  A paragraph goes through `paragraph` and a
    stanza, the verse lines of one source span (`verseSpan`), through
    `stanza`.  Each call takes the paragraph or the whole stanza off the
    front, so it stops by the number of the paragraphs left. -/
def paragraphs (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (p : Paras) (prior : Nat) (cursor : St)
    (indices : List Nat) : Except Failure St :=
  match indices with
  | [] => .ok cursor
  | index :: later =>
    match p.preliminary prior index cursor with
    | .error e => .error e
    | .ok pre =>
      if b.isStanza index then
        match tryVerses env region b pre (verseSpan b index later).1 with
        | .error e => .error e
        | .ok trials =>
          match p.ready prior index cursor (verseRows b p (pre :: trials).dropLast (verseSpan b index later).1) with
          | .error e => .error e
          | .ok ready =>
            match stanza env region b a (verseSpan b index later).2 (b.keepOf index) true ready
                (verseSpan b index later).1 with
            | .error e => .error e
            | .ok next =>
              paragraphs env region b a p (((verseSpan b index later).1.getLast?).getD index) next
                (verseSpan b index later).2
      else
        match p.ready prior index cursor [b.compose pre index] with
        | .error e => .error e
        | .ok ready =>
          match p.paragraph index later ready with
          | .error e => .error e
          | .ok next => paragraphs env region b a p index next later
termination_by indices.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after b index later; omega)

/-- The groups `paragraphs` hands on, in order: a paragraph alone, or the
    verse lines of a stanza (`verseSpan`). -/
def groups (b : Beside) (indices : List Nat) : List (List Nat) :=
  match indices with
  | [] => []
  | index :: later =>
    if b.isStanza index then (verseSpan b index later).1 :: groups b (verseSpan b index later).2
    else [index] :: groups b later
termination_by indices.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after b index later; omega)

theorem takeWhile_dropWhile (f : Nat → Bool) (l : List Nat) : l.takeWhile f ++ l.dropWhile f = l := by
  induction l with
  | nil => rfl
  | cons x xs ih => by_cases hx : f x <;> simp [List.takeWhile, List.dropWhile, hx, ih]

theorem verseSpan_join (b : Beside) (i : Nat) (more : List Nat) :
    (verseSpan b i more).1 ++ (verseSpan b i more).2 = i :: more := by
  simp only [verseSpan, List.cons_append, takeWhile_dropWhile]

/-- Every paragraph and verse line is in one group, in the order of the
    input. -/
theorem I5_groups_join (b : Beside) (indices : List Nat) : (groups b indices).join = indices := by
  match indices with
  | [] => simp [groups]
  | index :: later =>
    unfold groups
    split
    · simp only [List.join_cons]
      rw [I5_groups_join b (verseSpan b index later).2, verseSpan_join]
    · simp only [List.join_cons, List.singleton_append]
      rw [I5_groups_join b later]
termination_by indices.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after b index later; omega)

/-- One group of `paragraphs`: a paragraph through `paragraph`, or a stanza
    through `tryVerses` and `stanza`, with `later` the groups after it. -/
def placeGroup (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (p : Paras) (prior : Nat) (cursor : St)
    (g later : List Nat) : Except Failure St :=
  match g with
  | [] => .ok cursor
  | index :: _ =>
    match p.preliminary prior index cursor with
    | .error e => .error e
    | .ok pre =>
      if b.isStanza index then
        match tryVerses env region b pre g with
        | .error e => .error e
        | .ok trials =>
          match p.ready prior index cursor (verseRows b p (pre :: trials).dropLast g) with
          | .error e => .error e
          | .ok ready => stanza env region b a later (b.keepOf index) true ready g
      else
        match p.ready prior index cursor [b.compose pre index] with
        | .error e => .error e
        | .ok ready => p.paragraph index later ready

/-- The groups placed one after another, each after the last index of the
    group before it. -/
def byGroups (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (p : Paras) (prior : Nat) (cursor : St) :
    List (List Nat) → Except Failure St
  | [] => .ok cursor
  | g :: gs =>
    match placeGroup env region b a p prior cursor g gs.join with
    | .error e => .error e
    | .ok next => byGroups env region b a p (g.getLast?.getD prior) next gs

theorem getLast_getD (x : Nat) (t : List Nat) (y z : Nat) : (x :: t).getLast?.getD y = (x :: t).getLast?.getD z := by
  induction t generalizing x with
  | nil => rfl
  | cons u us ih => simp only [List.getLast?] at ih ⊢; exact ih u

/-- `paragraphs` hands every paragraph and verse line it takes to one
    group, the groups in the order of the input (`I5_groups_join`): it is
    `byGroups` on `groups`. -/
theorem I5_paragraphs_groups (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (p : Paras) (prior : Nat)
    (cursor : St) (indices : List Nat) :
    paragraphs env region b a p prior cursor indices = byGroups env region b a p prior cursor (groups b indices) := by
  match indices with
  | [] => simp [paragraphs, groups, byGroups]
  | index :: later =>
    rw [paragraphs, groups]
    by_cases hs : b.isStanza index = true
    · have hv : (verseSpan b index later).1 = index :: later.takeWhile (b.sameVerse index) := rfl
      simp only [hs, if_true]
      rw [hv]
      simp only [byGroups, placeGroup, hs, if_true, I5_groups_join]
      cases p.preliminary prior index cursor with
      | error e => rfl
      | ok pre =>
        simp only
        cases tryVerses env region b pre (index :: later.takeWhile (b.sameVerse index)) with
        | error e => rfl
        | ok trials =>
          simp only
          cases p.ready prior index cursor (verseRows b p (pre :: trials).dropLast (index :: later.takeWhile (b.sameVerse index))) with
          | error e => rfl
          | ok ready =>
            simp only
            cases stanza env region b a (verseSpan b index later).2 (b.keepOf index) true ready (index :: later.takeWhile (b.sameVerse index)) with
            | error e => rfl
            | ok next =>
              simp only
              rw [I5_paragraphs_groups env region b a p _ next (verseSpan b index later).2, getLast_getD]
    · simp only [hs, if_false]
      simp only [byGroups, placeGroup, hs, if_false, I5_groups_join, List.getLast?, Option.getD]
      cases p.preliminary prior index cursor with
      | error e => rfl
      | ok pre =>
        simp only
        cases p.ready prior index cursor [b.compose pre index] with
        | error e => rfl
        | ok ready =>
          simp only
          cases p.paragraph index later ready with
          | error e => rfl
          | ok next => simp only; rw [I5_paragraphs_groups env region b a p index next later]; rfl
termination_by indices.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after b index later; omega)

/-! ### The rows of the verse lines not tried, ahead of a no-break

`paragraphs` steps the controls before a stanza with the rows of its verse
lines ahead (`verseRows`): those `tryVerses` placed as composed at their
cursors, the others as composed before (`orig`).  A no-break among the
controls waits for the rows of the first part of the stanza
(`followingRows`).  These rows come from `orig` only when `tryVerses`
placed fewer verse lines than the first part (`I5_noBreak_rows_orig`), and
the verse lines `stanza` takes into a column that is not empty, by
`splitAtBreak`, are never fewer than the first part
(`I5_splitAtBreak_firstPart`). -/

theorem dropLast_length (c : St) (cs : List St) : ((c :: cs).dropLast).length = cs.length := by
  induction cs generalizing c with
  | nil => rfl
  | cons d ds ih => simp only [List.dropLast, List.length_cons]; rw [ih d]

theorem verseRows_take (b : Beside) (p p' : Paras) :
    ∀ (cs : List St) (vs : List Nat) (n : Nat), n ≤ cs.length →
    (verseRows b p cs vs).take n = (verseRows b p' cs vs).take n
  | [], _, n, h => by simp at h; subst h; rfl
  | _ :: _, [], n, _ => by simp [verseRows]
  | c :: cs, v :: vs, 0, _ => rfl
  | c :: cs, v :: vs, n + 1, h => by
    simp only [verseRows, List.take]
    exact congrArg _ (verseRows_take b p p' cs vs n (by simp at h; omega))

/-- The rows a no-break waits for ahead of a stanza do not read `orig`
    when `tryVerses` placed the first part of the stanza. -/
theorem I5_noBreak_rows_orig (b : Beside) (p p' : Paras) (k : Keep) (pre : St) (trials : List St) (vs : List Nat)
    (h : firstPart k true vs.length ≤ trials.length) (hl : trials.length ≤ vs.length) :
    followingRows 0 [.stanza k (verseRows b p (pre :: trials).dropLast vs)] =
      followingRows 0 [.stanza k (verseRows b p' (pre :: trials).dropLast vs)] := by
  have len : ∀ q : Paras, (verseRows b q (pre :: trials).dropLast vs).length = vs.length := by
    intro q
    have g : ∀ (cs : List St) (ws : List Nat), cs.length ≤ ws.length → (verseRows b q cs ws).length = ws.length := by
      intro cs
      induction cs with
      | nil => intro ws _; simp [verseRows]
      | cons c cs ih =>
        intro ws hw
        cases ws with
        | nil => simp at hw
        | cons w ws => simp only [verseRows, List.length_cons]; rw [ih ws (by simp at hw; omega)]
    exact g _ _ (by rw [dropLast_length]; omega)
  simp only [followingRows, len, Nat.min_zero, Nat.max_zero]
  rw [verseRows_take b p p' _ _ _ (by rw [dropLast_length]; omega)]

theorem range_loop_app (k : Nat) (acc : List Nat) : List.range.loop k acc = List.range.loop k [] ++ acc := by
  induction k generalizing acc with
  | zero => rfl
  | succ k ih => simp only [List.range.loop]; rw [ih (k :: acc), ih [k]]; simp

theorem range_succ' (n : Nat) : List.range (n + 1) = List.range n ++ [n] := by
  simp only [List.range, List.range.loop]; exact range_loop_app n [n]

theorem filter_app (P : Nat → Bool) (a b : List Nat) : (a ++ b).filter P = a.filter P ++ b.filter P := by
  induction a with
  | nil => rfl
  | cons x xs ih => by_cases hx : P x = true <;> simp [List.filter, hx, ih]

theorem filter_range_head (P : Nat → Bool) :
    ∀ (m y : Nat) (ys : List Nat), (List.range m).filter P = y :: ys → y < m
  | 0, _, _, h => by simp [List.range, List.range.loop, List.filter] at h
  | m + 1, y, ys, h => by
    rw [range_succ', filter_app] at h
    cases e : (List.range m).filter P with
    | nil =>
      rw [e] at h
      by_cases pm : P m = true
      · simp [List.filter, pm] at h; omega
      · simp [List.filter, pm] at h
    | cons z zs =>
      rw [e] at h
      simp only [List.cons_append, List.cons.injEq] at h
      have := filter_range_head P m z zs e
      omega

theorem headD_filter_range_le (P : Nat → Bool) :
    ∀ (n s d : Nat), s ≤ n → P s = true → ((List.range (n + 1)).filter P).headD d ≤ s
  | 0, s, d, hs, hp => by
    have : s = 0 := by omega
    subst this
    simp [List.range, List.range.loop, List.filter, hp]
  | n + 1, s, d, hs, hp => by
    rw [range_succ', filter_app]
    cases e : (List.range (n + 1)).filter P with
    | nil =>
      by_cases sn : s ≤ n
      · have := headD_filter_range_le P n s (s + 1) sn hp
        rw [e] at this; simp at this; omega
      · have : s = n + 1 := by omega
        subst this
        simp [List.filter, hp]
    | cons y ys =>
      simp only [List.cons_append, List.headD]
      by_cases sn : s ≤ n
      · have := headD_filter_range_le P n s d sn hp
        rw [e] at this; simpa using this
      · have := filter_range_head P (n + 1) y ys e
        omega

theorem splitAtBreak_spec (k : Keep) (n c : Nat) (hc : c ≤ n) (h : 0 < splitAtBreak k true n c) :
    splitAtBreak k true n c ≤ n ∧ (splitAtBreak k true n c = n ∨
      (k.all = false ∧ k.last ≤ n - splitAtBreak k true n c ∧ k.first ≤ splitAtBreak k true n c)) := by
  unfold splitAtBreak at h ⊢
  by_cases t : n ≤ c
  · rw [if_pos t] at h ⊢; omega
  rw [if_neg t] at h ⊢
  by_cases a : k.all = true
  · rw [if_pos a] at h; omega
  rw [if_neg a] at h ⊢
  have a' : k.all = false := by simpa using a
  dsimp only at h ⊢
  by_cases w : n - c < k.last
  · rw [if_pos w] at h ⊢
    by_cases q : 0 < n - k.last ∧ n - k.last < k.first
    · rw [if_pos ⟨rfl, q⟩] at h; omega
    · rw [if_neg (fun x => q x.2)] at h ⊢
      have f := Nat.not_lt.mp (fun x => q ⟨h, x⟩)
      refine ⟨by omega, Or.inr ⟨a', by omega, f⟩⟩
  · rw [if_neg w] at h ⊢
    by_cases q : 0 < c ∧ c < k.first
    · rw [if_pos ⟨rfl, q⟩] at h; omega
    · rw [if_neg (fun x => q x.2)] at h ⊢
      have f := Nat.not_lt.mp (fun x => q ⟨h, x⟩)
      refine ⟨by omega, Or.inr ⟨a', by omega, f⟩⟩

theorem splitAtBreak_fix (k : Keep) (n s : Nat)
    (h : s = n ∨ (k.all = false ∧ k.last ≤ n - s ∧ k.first ≤ s)) : splitAtBreak k true n s = s := by
  unfold splitAtBreak
  by_cases t : n ≤ s
  · rw [if_pos t]
  rw [if_neg t]
  rcases h with e | ⟨a, l, f⟩
  · omega
  rw [if_neg (by simp [a])]
  dsimp only
  have w : ¬ (n - s < k.last) := by omega
  simp only [w, if_false]
  rw [if_neg (fun x => absurd x.2.2 (by omega))]

/-- A number of verse lines `splitAtBreak` takes at the start of a stanza,
    from at most the stanza, is none or at least its first part. -/
theorem I5_splitAtBreak_firstPart (k : Keep) (n c : Nat) (hc : c ≤ n) (h : 0 < splitAtBreak k true n c) :
    firstPart k true n ≤ splitAtBreak k true n c := by
  obtain ⟨le, spec⟩ := splitAtBreak_spec k n c hc h
  unfold firstPart
  by_cases a : k.all = true
  · rw [if_pos a]
    rcases spec with e | ⟨a', _, _⟩
    · omega
    · rw [a] at a'; cases a'
  rw [if_neg a]
  have fix := splitAtBreak_fix k n _ spec
  have first : min k.first n ≤ splitAtBreak k true n c := by
    rcases spec with e | ⟨_, _, f⟩ <;> omega
  exact headD_filter_range_le _ n _ n le (by simp [first, fix])

/-! ## Tables -/

/-- The header lines repeated in a later column, without their notes. -/
def repeatedOf (ls : List Line) : List Line := ls.map (fun l => { l with notes := [] })

/-- `tableNeed`: the lines and, all or one, the note lines of a table part. -/
def tableNeed (env : Env) (st : St) (complete : Bool) (ls : List Line) : Int :=
  let count := notesCount ls
  let sep : Int := if 0 < count ∧ st.notesUsed = 0 then env.separator else 0
  ((ls.length + (if complete then count else min 1 count) : Nat) : Int) * env.pagePitch + sep

def checkTableNotes (env : Env) (ls : List Line) : Option Failure :=
  match notesOf ls with
  | n :: _ => if env.capacity < tableNeed env (initial env) false ls then some (.footnoteTooTall n.id) else none
  | [] => none

/-- `placeTableLinesReserved`: each line with the lines after it reserved. -/
def putReserved (env : Env) (reserve : Int) (st : St) : List Line → Except Failure St
  | [] => .ok st
  | l :: rest =>
    match putLineWithReserve true env { st with adjust := st.adjust - (reserve + (rest.length : Int) * env.pagePitch) } l with
    | .error e => .error e
    | .ok placed => putReserved env reserve { placed with adjust := st.adjust } rest

/-- The header repeated in a later column: `placeTableLinesReserved` of
    lines without notes, in slots that do not count as text. -/
def putRepeated (env : Env) (st : St) : List Line → Except Failure St
  | [] => .ok st
  | l :: rest =>
    if env.capacity < env.pitchOf l.id then .error (.lineTooTall l.id)
    else putRepeated env (putSlot st (env.pitchOf l.id) (.repeated l.id)) rest

/-- The condition of `tableReady`. -/
def tableFits (env : Env) (before : Int) (ls : List Line) (s : St) : Bool :=
  decide (tableNeed env s false ls + (if empty s then 0 else before + s.pending) ≤ room env s)

/-- The column `tableReady` returns once `tableFits` holds. -/
def tableAt (env : Env) (before : Int) (ls : List Line) (s : St) : St :=
  fit env s (tableNeed env s false ls + (if empty s then 0 else before))

def tableRowsRank (passed : Bool) (st : St) (seeking : Bool) : Nat × Nat × Nat × Nat :=
  (if passed then 0 else 1, waiting st, columnsLeft st, if seeking then 1 else 0)

theorem lex3_of_lex2 {a b c d x y : Nat} (h : Prod.Lex (· < ·) (· < ·) (a, b) (c, d)) :
    Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) (a, b, x) (c, d, y) := by
  cases h with
  | left _ _ h => exact Prod.Lex.left _ _ h
  | right _ h => exact Prod.Lex.right _ (Prod.Lex.left _ _ h)

/-- Where `tableFits` holds, `fit` stays in the column. -/
theorem tableAt_fields (env : Env) (b : Int) (ls : List Line) (s : St) (h : tableFits env b ls s = true) :
    (tableAt env b ls s).deferred = s.deferred ∧ (tableAt env b ls s).carry = s.carry ∧
    (tableAt env b ls s).column = s.column ∧ (tableAt env b ls s).columns = s.columns ∧
    (tableAt env b ls s).page = s.page := by
  unfold tableFits at h
  unfold tableAt fit
  cases e : empty s
  · simp only [e, if_false, decide_eq_true_eq, false_and] at h ⊢
    rw [if_pos (by omega)]
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · simp only [e, if_true, decide_eq_true_eq, true_and] at h ⊢
    rw [if_pos (by omega)]
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem putRepeated_fields (env : Env) (st s : St) (ls : List Line) (h : putRepeated env st ls = .ok s) :
    s.deferred = st.deferred ∧ s.carry = st.carry ∧ s.column = st.column ∧ s.columns = st.columns ∧
    s.page = st.page ∧ s.done = st.done := by
  induction ls generalizing st with
  | nil => simp only [putRepeated, Except.ok.injEq] at h; subst h; exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
  | cons l ls ih =>
    unfold putRepeated at h
    split at h
    · cases h
    · exact ih (putSlot st (env.pitchOf l.id) (.repeated l.id)) h

/-- The caption below a table, with its last row. -/
def tableTail (caption : List Line) (below : Bool) (rest : List (List Line)) : List Line :=
  if below ∧ rest.isEmpty then caption else []

set_option linter.unusedVariables false in
/-- `go` of `placeTableRows`, with the loop of `tableReady` after a row
    that does not fit (`seeking`). It stops where Physical.hs would repeat
    the header for ever: when it goes on from the last column of a page
    with nothing waiting a second time since the last row it placed
    (`passed`), every later column is the same. -/
def tableRowsGo (env : Env) (header caption : List Line) (below : Bool) (ident : Nat)
    (seeking passed : Bool) (start : Int) (st : St) : List (List Line) → Except Failure St
  | [] => if below then putReserved env 0 st caption else .ok st
  | row :: rest =>
    if h1 : seeking ∧ tableFits env 0 (repeatedOf header ++ row ++ tableTail caption below rest) st then
      match h : putRepeated env (tableAt env 0 (repeatedOf header ++ row ++ tableTail caption below rest) st) header with
      | .error e => .error e
      | .ok withHeader =>
        tableRowsGo env header caption below ident false passed
          (tableAt env 0 (repeatedOf header ++ row ++ tableTail caption below rest) st).used withHeader (row :: rest)
    else if ¬seeking ∧ (tableNeed env st true (row ++ tableTail caption below rest) ≤ room env st ∨
        st.used = start + (header.length : Int) * env.pagePitch) then
      match putReserved env (((tableTail caption below rest).length : Int) * env.pagePitch) st row with
      | .error e => .error e
      | .ok placed => tableRowsGo env header caption below ident false false start placed rest
    else if h2 : drainOk env st = true ∧ ¬(waiting st = 0 ∧ st.columns ≤ st.column + 1) then
      tableRowsGo env header caption below ident true passed start (nextColumn env st) (row :: rest)
    else if h3 : passed = false then
      tableRowsGo env header caption below ident true true start (nextColumn env st) (row :: rest)
    else .error (.noProgress ident)
termination_by rows => (rows.length, tableRowsRank passed st seeking)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.right
    obtain ⟨d1, c1, k1, n1, _⟩ := tableAt_fields env 0 _ st h1.2
    obtain ⟨d2, c2, k2, n2, _, _⟩ := putRepeated_fields env _ _ header h
    simp only [tableRowsRank, waiting, columnsLeft, d1, c1, k1, n1, d2, c2, k2, n2, h1.1]
    exact Prod.Lex.right _ (Prod.Lex.right _ (Prod.Lex.right _ (by decide)))
  · apply Prod.Lex.left; omega
  · apply Prod.Lex.right; simp only [tableRowsRank]
    exact Prod.Lex.right _ (lex3_of_lex2 (I4_drain_rank env st ⟨seek_cond st h2.2, h2.1⟩))
  · apply Prod.Lex.right; simp only [tableRowsRank, h3]; exact Prod.Lex.left _ _ (by decide)

/-- The caption above a table, placed before its header. -/
def tableCaption (env : Env) (below : Bool) (reserve : Int) (start : St) (caption : List Line) : Except Failure St :=
  if below then .ok start else putReserved env reserve start caption

/-- `placeTable` from `tableReady` on, for the first part `firstPart`. -/
def placeTableFrom (env : Env) (st : St) (ident : Nat) (before : Int) (header : List Line) (rows : List (List Line))
    (caption : List Line) (below : Bool) (firstPart : List Line) : Except Failure St :=
  let found := seek env (tableFits env before firstPart) st
  if tableFits env before firstPart found = false then .error (.noProgress ident)
  else
    let ready := tableAt env before firstPart found
    match tableCaption env below (((header.length + (rows.headD []).length : Nat) : Int) * env.pagePitch)
        { ready with used := ready.used + if empty ready then 0 else before } caption with
    | .error e => .error e
    | .ok placed =>
      match putReserved env ((((rows.headD []) ++ (if below ∧ rows.length ≤ 1 then caption else [])).length : Int) * env.pagePitch)
          placed header with
      | .error e => .error e
      | .ok withHeader => tableRowsGo env header caption below ident false false placed.used withHeader rows

/-- The first part of a table: the header, the first row and the caption
    that goes with them. -/
def tableFirstPart (header : List Line) (rows : List (List Line)) (caption : List Line) (below : Bool) : List Line :=
  (if below then [] else caption) ++ header ++ rows.headD [] ++
    (if below then (if below = false ∨ rows.length ≤ 1 then caption else []) else [])

/-- The checks of `placeTable` before it places anything. -/
def tableCheck (env : Env) (ident : Nat) (header : List Line) (rows : List (List Line)) (caption : List Line)
    (below : Bool) : Option Failure :=
  let firstPart := tableFirstPart header rows caption below
  let captionRows := if below = false ∨ rows.length ≤ 1 then caption else []
  let remainingParts := (rows.drop 1).enum.map (fun (j, row) =>
    repeatedOf header ++ row ++ (if below ∧ j + 2 = rows.length then caption else []))
  if env.capacity < (firstPart.length : Int) * env.pagePitch then
    some (if captionRows.isEmpty then .tableTooTall ident else .tableCaptionTooTall ident)
  else if rows.any (fun row => decide (env.capacity < ((header.length + row.length : Nat) : Int) * env.pagePitch)) then
    some (.tableTooTall ident)
  else if below ∧ env.capacity < ((header.length + (rows.getLastD []).length + caption.length : Nat) : Int) * env.pagePitch then
    some (.tableCaptionTooTall ident)
  else ((firstPart :: remainingParts).filterMap (checkTableNotes env)).head?

/-- `placeTable`, out of a book part: the first part where it fits, then
    the rows, the header repeated in each later column. -/
def placeTable (env : Env) (st : St) (ident : Nat) (before : Int) (header : List Line) (rows : List (List Line))
    (caption : List Line) (below : Bool) : Except Failure St :=
  match tableCheck env ident header rows caption below with
  | some e => .error e
  | none => placeTableFrom env st ident before header rows caption below (tableFirstPart header rows caption below)

/-! ## Book parts -/

/-- `key` of `retainPhysicalPart`: the unit a column is in. -/
def unitKey (u : PartUnit) (page column : Nat) : Nat × Nat :=
  match u with
  | .column => (page, column)
  | .page => (page, 0)
  | .spread => (if page = 1 then 0 else page / 2, 0)

theorem unitKey_page (u : PartUnit) (p c : Nat) : p < 2 * (unitKey u p c).1 + 2 := by
  cases u
  · simp [unitKey]; omega
  · simp [unitKey]; omega
  · simp only [unitKey]; split <;> omega

/-- `emptyUnit`: an empty column at the start of its unit. -/
def emptyUnit (u : PartUnit) (st : St) : Bool :=
  empty st && st.used == 0 &&
    match u with
    | .column => true
    | .page => st.column == 0
    | .spread => st.column == 0 && (st.page == 1 || st.page % 2 == 0)

theorem placeTurnedGo_page (env : Env) (st : St) (ds : List Waiting) : st.page ≤ (placeTurnedGo env st ds).page := by
  induction ds generalizing st with
  | nil => simp [placeTurnedGo]
  | cons d ds ih =>
    cases d with
    | figure i e => simp [placeTurnedGo]
    | turned i =>
      simp only [placeTurnedGo]
      exact Nat.le_trans (Nat.le_succ _) (ih { st with
        done := ⟨st.page, 0, false, [(0, .pageFigure i)], [], limit env st, []⟩ :: st.done, page := st.page + 1 })

/-- The next column is on a later page, or on the same page with fewer
    columns left. -/
theorem nextColumn_moves (env : Env) (st : St) :
    st.page < (nextColumn env st).page ∨
    ((nextColumn env st).page = st.page ∧ columnsLeft (nextColumn env st) < columnsLeft st) := by
  have keep : ∀ O : St, (carryInto env (placeDeferredGo env O O.deferred)).page = O.page ∧
      columnsLeft (carryInto env (placeDeferredGo env O O.deferred)) = columnsLeft O := by
    intro O
    obtain ⟨p1, p2, p3, _⟩ := placeDeferredGo_fields env O O.deferred
    obtain ⟨c1, c2, c3, _⟩ := carryInto_fields env (placeDeferredGo env O O.deferred)
    exact ⟨by rw [c1, p1], by simp only [columnsLeft, c2, c3, p2, p3]⟩
  unfold nextColumn placeDeferred
  obtain ⟨k1, k2⟩ := keep (opened env false st)
  rw [k1, k2]
  by_cases pe : st.columns ≤ st.column + 1
  · left
    have op : opened env false st = placeTurned env (fresh env false st) := by simp [opened, pe]
    rw [op]; unfold placeTurned
    have := placeTurnedGo_page env (fresh env false st) (fresh env false st).deferred
    have fp : (fresh env false st).page = st.page + 1 := by simp [fresh, pe]
    omega
  · right
    have op : opened env false st = fresh env false st := by simp [opened, pe]
    rw [op]
    have fc := fresh_inPage env st pe
    obtain ⟨_, _, _, _, _, _, f7⟩ := fresh_fields env false st
    refine ⟨by simp [fresh, pe], ?_⟩
    simp only [columnsLeft, fc, f7]; omega

set_option linter.unusedVariables false in
/-- `advance` of `nextUnit`: the columns of the unit `wanted` passed. -/
def advanceUnit (env : Env) (u : PartUnit) (wanted : Nat × Nat) (st : St) : St :=
  if h : unitKey u st.page st.column = wanted then advanceUnit env u wanted (nextColumn env st) else st
termination_by (2 * wanted.1 + 2 - st.page, columnsLeft st)
decreasing_by
  simp_wf
  have b := unitKey_page u st.page st.column
  rw [h] at b
  cases nextColumn_moves env st with
  | inl l => exact Prod.Lex.left _ _ (by omega)
  | inr r => rw [r.1]; exact Prod.Lex.right _ r.2

/-- `nextUnit`: the first column of the next unit. -/
def nextUnit (env : Env) (u : PartUnit) (st : St) : St :=
  advanceUnit env u (unitKey u st.page st.column) (nextColumn env st)

set_option linter.unusedVariables false in
/-- `settle` of `retainPhysicalPart`: the next column while a figure of the
    part is sent on. -/
def settle (env : Env) (ids : List Nat) (st : St) : St :=
  if h : st.deferred.any (fun w => ids.contains w.id) = true ∧ figureOk env st = true then
    settle env ids (nextColumn env st)
  else st
termination_by (waiting st, columnsLeft st)
decreasing_by
  simp_wf
  refine I4_settle_rank env st ⟨fun e => ?_, h.2⟩
  have := h.1; rw [e] at this; cases this

/-- `slotIds` of BookParts.hs. -/
def slotIds : Slot → List Nat
  | .line i | .figure i | .pageFigure i | .heading i _ | .wrapped i | .repeated i => [i]
  | .code ids _ => ids

def lexMin (a b : Nat × Nat) : Nat × Nat := if a.1 < b.1 ∨ (a.1 = b.1 ∧ a.2 ≤ b.2) then a else b

/-- The least unit of the columns that hold the id (`Map.fromListWith min`). -/
def minKey (entries : List ((Nat × Nat) × List (Int × Slot))) (i : Nat) : Option (Nat × Nat) :=
  entries.foldl (fun acc e =>
    if e.2.any (fun s => (slotIds s.2).contains i) then
      some (match acc with | some a => lexMin a e.1 | none => e.1)
    else acc) none

/-- `fits` of `retainPhysicalPart`: every id is placed, and first in the
    unit the trial starts in. -/
def partFits (u : PartUnit) (initial : St) (ids : List Nat) (st : St) (expected : Nat × Nat) : Bool :=
  ids.isEmpty ||
    let entries := (st.done.takeWhile (fun o => decide (initial.page ≤ o.number))).map (fun o => (unitKey u o.number o.column, o.slots)) ++
      [(unitKey u st.page st.column, st.slots)]
    ids.all (fun i => minKey entries i == some expected)

/-- `trial` of `retainPhysicalPart`. -/
def retainTry (env : Env) (ids : List Nat) (compose : St → Except Failure St) (s0 : St) : Except Failure St :=
  match compose s0 with
  | .error e => .error e
  | .ok s => .ok (settle env ids s)

/-- `retainPhysicalPart`: a book part, or the tail of a table, placed where
    it starts and on trial at the start of the next unit. -/
def retain (env : Env) (u : PartUnit) (table : Bool) (ids : List Nat) (st : St)
    (compose : St → Except Failure St) : Except Failure St :=
  match retainTry env ids compose st with
  | .error e => .error e
  | .ok ordinary =>
    if u = .column then
      if emptyUnit u st then
        .ok (if partFits u st ids ordinary (unitKey u st.page st.column) then ordinary
          else addUnmet (.splitPart table u) ordinary)
      else
        match retainTry env ids compose (nextUnit env u st) with
        | .error e => .error e
        | .ok m =>
          .ok (if partFits u st ids m (unitKey u (nextUnit env u st).page (nextUnit env u st).column) then ordinary
            else addUnmet (.splitPart table u) ordinary)
    else if partFits u st ids ordinary (unitKey u st.page st.column) then .ok ordinary
    else
      match retainTry env ids compose (nextUnit env u st) with
      | .error e => .error e
      | .ok m =>
        .ok (if partFits u st ids m (unitKey u (nextUnit env u st).page (nextUnit env u st).column) then m
          else addUnmet (.splitPart table u) (if emptyUnit u st then ordinary else m))

set_option linter.unusedVariables false in
/-- `go` of `placeTableAcross`: each group (a row, or not) in the column
    where it fits or at the top of a column, the header repeated where a
    row starts a new page. -/
def acrossGo (env : Env) (header : List Line) (st : St) : List (Bool × List Line) → Except Failure St
  | [] => .ok st
  | (isRow, ls) :: rest =>
    if h : tableNeed env st true ls ≤ room env st ∨ empty st = true then
      match putReserved env 0 st ls with
      | .error e => .error e
      | .ok placed => acrossGo env header placed rest
    else if isRow = true ∧ (nextColumn env st).page ≠ st.page ∧ header ≠ [] then
      match putRepeated env (nextColumn env st) header with
      | .error e => .error e
      | .ok withHeader =>
        match putReserved env 0 (if tableNeed env withHeader true ls ≤ room env withHeader then withHeader
            else nextColumn env withHeader) ls with
        | .error e => .error e
        | .ok placed => acrossGo env header placed rest
    else acrossGo env header (nextColumn env st) ((isRow, ls) :: rest)
termination_by gs => (gs.length, rank st)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.left; omega
  · apply Prod.Lex.left; omega
  · apply Prod.Lex.right; apply I4_nextColumn_rank; left
    have := (not_or.1 h).2; simpa using this

/-- The rows before the last and the last, as lists. -/
def splitLast {α : Type} : List α → List α × List α
  | [] => ([], [])
  | [x] => ([], [x])
  | x :: y :: zs => ((x :: (splitLast (y :: zs)).1), (splitLast (y :: zs)).2)

/-- The last row and the caption below it, in the unit of the last row. -/
def acrossTail (env : Env) (header lastRow caption : List Line) (placed s0 : St) : Except Failure St :=
  match (if s0.page ≠ placed.page ∧ header ≠ [] ∧ lastRow ≠ [] then
      match putRepeated env s0 header with
      | .error e => .error e
      | .ok wh => acrossGo env header wh [(true, lastRow)]
    else acrossGo env header s0 (if lastRow ≠ [] then [(true, lastRow)] else [])) with
  | .error e => .error e
  | .ok rowPlaced =>
    putReserved env 0 (if tableNeed env rowPlaced true caption ≤ room env rowPlaced ∨ empty rowPlaced = true then rowPlaced
      else nextColumn env rowPlaced) caption

/-- `placeTableAcross`: a table in a book part of page or spread. -/
def placeTableAcross (env : Env) (u : PartUnit) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool) : Except Failure St :=
  let extent := fun (ls : List Line) => (ls.length : Int) * env.pagePitch
  if caption ≠ [] ∧ env.capacity < extent caption then .error (.tableCaptionTooTall ident)
  else if rows.any (fun row => decide (env.capacity < extent row ∨ env.capacity < extent header ∨
      env.capacity * ((max 1 st.columns : Nat) : Int) < extent header + extent row)) then .error (.tableTooTall ident)
  else
    match ((caption :: header :: rows).filterMap (checkTableNotes env)).head? with
    | some e => .error e
    | none =>
      let started :=
        if empty st then st
        else if before + st.pending ≤ room env st then
          { st with used := st.used + st.pending + before, pending := 0, blankActive := false, blankSpans := 0 }
        else nextColumn env st
      let lowered := below = true ∧ caption ≠ []
      let bodyRows := if lowered then (splitLast rows).1 else rows
      let groups := (if below = false ∧ caption ≠ [] then [(false, caption)] else []) ++
        (if header ≠ [] then [(false, header)] else []) ++ bodyRows.map (fun r => (true, r))
      match acrossGo env header started groups with
      | .error e => .error e
      | .ok placed =>
        if lowered then
          retain env u true (((splitLast rows).2.join ++ caption).map (·.id)) placed
            (acrossTail env header (splitLast rows).2.join caption placed)
        else .ok placed

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

/-- `joinPart` of `drainCarried`: a part after the part before it of the
    same note joins it. -/
def joinPart (parts : List NotePart) (p : NotePart) : List NotePart :=
  match parts.reverse with
  | (j, f, l) :: before => if j = p.1 ∧ f + l = p.2.1 then before.reverse ++ [(j, f, l + p.2.2)] else parts ++ [p]
  | [] => parts ++ [p]

/-- `drainCarried`: the continued notes take the room that `FAdjustLines`
    has added to the column, in their order, before any later note,
    leaving nothing for the text, as `carryInto` (root ADR 0444).  What
    does not fit goes on. -/
def drainCarried (env : Env) (st : St) : St :=
  let separator := if st.notesUsed = 0 then env.separator else 0
  let count := (max 0 (Int.fdiv (room env st - separator) env.pagePitch)).toNat
  let p := splitCarried count st.carry
  if st.carry.isEmpty ∨ p.1.isEmpty then st
  else { st with notes := p.1.foldl joinPart st.notes, carry := p.2,
                 notesUsed := st.notesUsed + separator + (partsLines p.1 : Int) * env.pagePitch }

theorem drainCarried_fields (env : Env) (st : St) :
    (drainCarried env st).done = st.done ∧ (drainCarried env st).slots = st.slots ∧
      (drainCarried env st).deferred = st.deferred := by
  unfold drainCarried; dsimp only; split <;> (try split) <;> exact ⟨rfl, rfl, rfl⟩

/-! ## One flow -/

def placeFlow (inner : Inner) (env : Env) (st : St) : Flow → Except Failure St
  | .paragraph k ls => placeLines env k true st ls
  | .continued k ls => placeLines env k false st ls
  | .space n => .ok { st with pending := if st.blankActive then st.pending else st.pending + max 0 n }
  | .blank n => .ok { st with
      pending := (if st.blankActive then st.pending else 0) + (n : Int) * env.pagePitch
      blankActive := true
      blankSpans := st.blankSpans + (if 0 < n then 1 else 0) }
  | .figure i e =>
    if env.capacity < e then .error (.figureTooTall i)
    else if st.deferred ≠ [] then .ok { st with deferred := st.deferred ++ [.figure i e] }
    else if room env st < e + st.pending ∧ empty st = false then
      .ok { st with deferred := st.deferred ++ [.figure i e], pending := 0, blankActive := false }
    else .ok (putSlot (fit env st e) e (.figure i))
  | .brk k => .ok (breakAt env k st)
  | .needLines n =>
    let required := (n : Int) * env.pagePitch
    let bounded := min required env.capacity
    let marked := if env.capacity < required then addUnmet (.needLines n) st else st
    .ok (judgeNeed env bounded marked)
  | .adjustLines n => .ok (drainCarried env (adjustLines env n st))
  | .noBreak => .ok (waitForPrior .noBreak (1, false) st)
  | .noBreakLines n => if n = 0 then .ok st else .ok (waitForPrior .noBreak (1, false) st)
  | .keepNext _ sp => .ok (waitForPrior (.keepNext sp) (1, false) st)
  | .pageFigure i =>
    if st.deferred = [] ∧ st.column = 0 ∧ st.used = 0 ∧ empty st = true then
      .ok (nextPage env (putSlot st env.capacity (.pageFigure i)))
    else .ok { st with deferred := st.deferred ++ [.turned i] }
  | .ruled r => placeRuled inner env st r []
  | .start k => .ok (sectionStart env k st)
  | .switchColumns cols => .ok (switchColumns env cols st)
  | .restoreColumns => .ok (restoreColumns env st)
  | .heading recto extent ls =>
    placeHeading env (if recto then parityStart env (fun p => p % 2 == 1) st else st) (headId ls) extent ls
  | .defTerm ls => placeLines env defaultKeep true st ls
  | .stanza k vs => placeStanza env k true st vs
  | .code caption first continued spans rows => placeCode env caption first continued spans true st rows
  | .wrapped i e ls => placeWrapped env st i e ls
  | .table i b header rows caption below =>
    match env.retention with
    | some u => placeTableAcross env u st i b header rows caption below
    | none => placeTable env st i b header rows caption below
  | .bookPart u ids body =>
    retain env u false ids st (fun s0 => inner.all (if u = .column then env else { env with retention := some u }) s0 body)
  | .boxed i b a body => placeBox inner env st i b a body

def occupies : Flow → Bool
  | .paragraph _ _ | .continued _ _ | .figure _ _ | .pageFigure _ | .ruled _ | .heading _ _ _ | .defTerm _ | .stanza _ _ | .code _ _ _ _ _ | .wrapped _ _ _ | .table _ _ _ _ _ _
  | .boxed _ _ _ _ => true
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
def placeBody (inner : Inner) (env : Env) (before : St) (flow : Flow) (rest : List Flow) : Except Failure St :=
  match flow, keepAhead rest with
  | .paragraph k ls, some (l, f, later) => placeWithNext inner env k true before ls l f later
  | .continued k ls, some (l, f, later) => placeWithNext inner env k false before ls l f later
  | .noBreak, _ => .ok (waitForPrior .noBreak (followingRows 0 rest) before)
  | .noBreakLines n, _ =>
    if 0 < n then .ok (waitForPrior .noBreak (followingRows 0 rest) before) else placeFlow inner env before flow
  | .keepNext n sp, _ => .ok (waitForPrior (.keepNext sp) (followingRows n rest) before)
  | .stanza k vs, some (l, f, later) => placeStanzaWithNext inner env k before vs l f later
  | .defTerm ls, _ =>
    if env.retention.isSome then placeLines env ⟨1, 1, false⟩ true before ls
    else placeLines env defaultKeep true (keepFollowing inner env false before (sumPitch env ls) ls rest) ls
  | .heading recto extent ls, _ =>
    placeHeading env (if recto then parityStart env (fun p => p % 2 == 1) before
      else keepFollowing inner env true before extent ls rest) (headId ls) extent ls
  | .ruled r, _ => placeRuledKeeping inner env before r rest
  | _, _ => placeFlow inner env before flow

def placeNext (inner : Inner) (env : Env) (st : St) (flow : Flow) (rest : List Flow) : Except Failure St :=
  match placeBody inner env (beforeOf env st flow rest) flow rest with
  | .error e => .error e
  | .ok s => .ok (if occupies flow then checkWaits s else s)

def placeAll (inner : Inner) (env : Env) (st : St) : List Flow → Except Failure St
  | [] => .ok st
  | f :: rest =>
    match placeNext inner env st f rest with
    | .error e => .error e
    | .ok s => placeAll inner env s rest

/-- `placeFlow` and `placeAll` with `n` levels of boxes and book parts
    inside each other; below them nothing is placed. `paginate` uses as many levels as the flows nest. -/
def level : Nat → Inner
  | 0 => ⟨fun _ _ _ => .error (.noProgress 0), fun _ _ _ => .error (.noProgress 0)⟩
  | n + 1 => ⟨placeFlow (level n), placeAll (level n)⟩

mutual
def flowDepth : Flow → Nat
  | .boxed _ _ _ body => flowsDepth body + 1
  | .bookPart _ _ body => flowsDepth body + 1
  | _ => 0
def flowsDepth : List Flow → Nat
  | [] => 0
  | f :: fs => max (flowDepth f) (flowsDepth fs)
end

def checkNotes (env : Env) (flows : List Flow) : Option Failure :=
  match (bodyLines flows).bind (fun l => l.notes) with
  | n :: _ => if env.capacity < env.separator + env.pagePitch then some (.footnoteTooTall n.id) else none
  | [] => none

/-- `paginatePhysical` of Physical.hs. -/
def paginate (env : Env) (flows : List Flow) : Except Failure (List PageOut) :=
  match checkNotes env flows with
  | some e => .error e
  | none =>
    match placeAll (level (flowsDepth flows)) env (initial env) flows with
    | .error e => .error e
    | .ok final =>
      if (drainCarry env final).deferred.isEmpty ∧ (drainCarry env final).carry.isEmpty then
        match (close env (drainCarry env final)).done.reverse with
        | [] => .ok [⟨1, 0, false, [], [], env.capacity, []⟩]
        | pages => .ok pages
      else .error (.noProgress 0)

/-! ## What the pages hold -/

def textSlots : List (Int × Slot) → List Nat
  | [] => []
  | (_, .line i) :: r => i :: textSlots r
  | (_, .heading i _) :: r => i :: textSlots r
  | (_, .code ids _) :: r => ids ++ textSlots r
  | (_, .wrapped i) :: r => i :: textSlots r
  | _ :: r => textSlots r
def figSlots : List (Int × Slot) → List Nat
  | [] => []
  | (_, .figure i) :: r => i :: figSlots r
  | (_, .pageFigure i) :: r => i :: figSlots r
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
def figs (st : St) : List Nat := pagesFigs st.done.reverse ++ figSlots st.slots ++ st.deferred.map Waiting.id
def lineIds (ls : List Line) : List Nat := ls.map (·.id)
/-- The ids a table adds to the text, in the order it is placed. -/
def tableText (header : List Line) (rows : List (List Line)) (caption : List Line) (below : Bool) : List Nat :=
  if below then lineIds header ++ lineIds rows.join ++ lineIds caption
  else lineIds caption ++ lineIds header ++ lineIds rows.join

/-- The ids a ruled block adds to the text: its lines, or the first line
    of a ruled heading. -/
def ruledText (r : Ruled) : List Nat := if r.heading.isSome then [headId r.lines] else lineIds r.lines

mutual
/-- The ids a flow adds to the text: its lines, the first line of a
    heading, a wrapped figure before its lines, and those of the flows of a
    box. -/
def flowText : Flow → List Nat
  | .heading _ _ ls => [headId ls]
  | .ruled r => ruledText r
  | .wrapped i _ ls => i :: lineIds ls
  | .table _ _ header rows caption below => tableText header rows caption below
  | .boxed _ _ _ body => sourceText body
  | .bookPart _ _ body => sourceText body
  | .paragraph _ ls => lineIds ls
  | .continued _ ls => lineIds ls
  | .defTerm ls => lineIds ls
  | .stanza _ vs => lineIds vs.join
  | .code _ _ _ _ rows => lineIds rows
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
def sourceText : List Flow → List Nat
  | [] => []
  | f :: fs => flowText f ++ sourceText fs
end

mutual
/-- The figures of a flow, and those of the flows of a box. -/
def flowFigs : Flow → List Nat
  | .figure i _ => [i]
  | .pageFigure i => [i]
  | .boxed _ _ _ body => sourceFigs body
  | .bookPart _ _ body => sourceFigs body
  | .paragraph _ _ => []
  | .continued _ _ => []
  | .defTerm _ => []
  | .stanza _ _ => []
  | .code _ _ _ _ _ => []
  | .heading _ _ _ => []
  | .ruled _ => []
  | .wrapped _ _ _ => []
  | .table _ _ _ _ _ _ => []
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
def sourceFigs : List Flow → List Nat
  | [] => []
  | f :: fs => flowFigs f ++ sourceFigs fs
end

/-- From `st` to `s`, the lines `t` and the figures `g` are added. -/
def Step (st s : St) (t g : List Nat) : Prop :=
  text s = text st ++ t ∧ figs s = figs st ++ g

theorem Step.refl (st : St) : Step st st [] [] := by
  simp [Step]

theorem Step.trans {a b c : St} {t g t' g' : List Nat}
    (h : Step a b t g) (h' : Step b c t' g') : Step a c (t ++ t') (g ++ g') := by
  obtain ⟨t1, g1⟩ := h
  obtain ⟨t2, g2⟩ := h'
  exact ⟨by rw [t2, t1, List.append_assoc], by rw [g2, g1, List.append_assoc]⟩

theorem Step.same {st s : St} (d : s.done = st.done) (sl : s.slots = st.slots)
    (df : s.deferred = st.deferred) : Step st s [] [] := by
  refine ⟨?_, ?_⟩
  · simp [text, d, sl]
  · simp [figs, d, sl, df]

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

theorem step_fresh (env : Env) (tp : Bool) (st : St) : Step st (fresh env tp st) [] [] := by
  unfold fresh close
  split
  · rename_i h
    have s : st.slots = [] := by
      cases c : st.slots with
      | nil => rfl
      | cons _ _ => simp [c, List.isEmpty] at h
    refine ⟨?_, ?_⟩
    · simp [text, s, textSlots]
    · simp [figs, s, figSlots]
  · refine ⟨?_, ?_⟩
    · simp [text, pagesText_append, pagesText, textSlots]
    · simp [figs, pagesFigs_append, pagesFigs, figSlots]

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

theorem close_fields (env : Env) (st : St) :
    (close env st).deferred = st.deferred ∧ (close env st).carry = st.carry ∧ (close env st).page = st.page ∧
    (close env st).column = st.column ∧ (close env st).columns = st.columns ∧ (close env st).slots = st.slots ∧
    (close env st).used = st.used ∧ (close env st).adjust = st.adjust ∧ (close env st).notesUsed = st.notesUsed := by
  unfold close; split <;> exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- A column closed and emptied in the same page or the next. -/
theorem step_closed (env : Env) (st s : St) (d : s.done = (close env st).done) (sl : s.slots = [])
    (df : s.deferred = st.deferred) : Step st s [] [] := by
  obtain ⟨a, b⟩ := close_pages env st
  refine ⟨?_, ?_⟩
  · simp only [text, d, sl, textSlots, List.append_nil]; exact a
  · simp only [figs, d, sl, df, figSlots, List.append_nil]; rw [b]


theorem pdg_step (env : Env) (st : St) (ds : List Waiting) :
    text (placeDeferredGo env st ds) = text st ∧
    figs (placeDeferredGo env st ds) = pagesFigs st.done.reverse ++ figSlots st.slots ++ ds.map Waiting.id ∧
    (placeDeferredGo env st ds).carry = st.carry ∧
    (∀ d ∈ (placeDeferredGo env st ds).deferred, d ∈ ds) := by
  induction ds generalizing st with
  | nil => simp [placeDeferredGo, text, figs]
  | cons d ds ih =>
    cases d with
    | turned i => refine ⟨rfl, by simp [figs, placeDeferredGo], rfl, fun x m => by simpa [placeDeferredGo] using m⟩
    | figure i e =>
      simp only [placeDeferredGo]
      split
      · obtain ⟨a, b, c, d⟩ := ih (putSlot st e (.figure i))
        refine ⟨?_, ?_, c, fun x m => List.mem_cons_of_mem _ (d x m)⟩
        · rw [a]; simp [text, putSlot, textSlots_append, textSlots]
        · rw [b]; simp [putSlot, figSlots_append, figSlots, Waiting.id]
      · refine ⟨rfl, by simp [figs], rfl, fun x m => m⟩

theorem ptg_step (env : Env) (st : St) (ds : List Waiting) (hs : st.slots = []) :
    text (placeTurnedGo env st ds) = text st ∧
    figs (placeTurnedGo env st ds) = pagesFigs st.done.reverse ++ ds.map Waiting.id := by
  induction ds generalizing st with
  | nil => simp [placeTurnedGo, text, figs, hs, figSlots]
  | cons d ds ih =>
    cases d with
    | figure i e => simp [placeTurnedGo, text, figs, hs, figSlots]
    | turned i =>
      simp only [placeTurnedGo]
      obtain ⟨a, b⟩ := ih { st with
        done := ⟨st.page, 0, false, [(0, .pageFigure i)], [], limit env st, []⟩ :: st.done, page := st.page + 1 } hs
      refine ⟨?_, ?_⟩
      · rw [a]; simp [text, pagesText_append, pagesText, textSlots]
      · rw [b]; simp [pagesFigs_append, pagesFigs, figSlots, Waiting.id]

theorem step_opened (env : Env) (tp : Bool) (st : St) : Step st (opened env tp st) [] [] := by
  have f := step_fresh env tp st
  unfold opened
  split
  · obtain ⟨f1, _, _, _, _, _, _⟩ := fresh_fields env tp st
    generalize fresh env tp st = F at *
    obtain ⟨a, b⟩ := ptg_step env F F.deferred f1
    have g : Step F (placeTurned env F) [] [] := by
      refine ⟨by rw [placeTurned, a, List.append_nil], ?_⟩
      rw [placeTurned, b, List.append_nil]; simp [figs, f1, figSlots]
    simpa using f.trans g
  · exact f

theorem step_placeDeferred (env : Env) (st : St) : Step st (placeDeferred env st) [] [] := by
  obtain ⟨a, b, _, _⟩ := pdg_step env st st.deferred
  exact ⟨by rw [placeDeferred, a, List.append_nil], by rw [placeDeferred, b, List.append_nil]; rfl⟩

theorem step_carryInto (env : Env) (st : St) : Step st (carryInto env st) [] [] := by
  unfold carryInto
  split
  · exact Step.refl st
  · exact ⟨by simp [text], by simp [figs]⟩

theorem step_nextColumn (env : Env) (st : St) : Step st (nextColumn env st) [] [] := by
  have := ((step_opened env false st).trans (step_placeDeferred env _)).trans (step_carryInto env _)
  simpa using this

theorem step_nextPage (env : Env) (st : St) : Step st (nextPage env st) [] [] := by
  have := ((step_opened env true st).trans (step_placeDeferred env _)).trans (step_carryInto env _)
  simpa using this


theorem step_dropAtTop (st : St) : Step st (dropAtTop st) [] [] := Step.same rfl rfl rfl

theorem step_fit (env : Env) (st : St) (a : Int) : Step st (fit env st a) [] [] := by
  unfold fit
  repeat' split
  all_goals first
    | exact step_dropAtTop st
    | exact Step.same rfl rfl rfl
    | simpa using (step_nextColumn env st).trans (step_dropAtTop _)

theorem nextColumn_deferred (env : Env) (st : St) (h : st.deferred = []) : (nextColumn env st).deferred = [] := by
  unfold nextColumn placeDeferred
  obtain ⟨_, _, _, _, _, _, _, o8⟩ := opened_fields env false st
  generalize opened env false st = O at *
  obtain ⟨_, _, _, d⟩ := pdg_step env O O.deferred
  obtain ⟨_, _, _, _, _, _, _, c8, _⟩ := carryInto_fields env (placeDeferredGo env O O.deferred)
  rw [c8]
  cases e : (placeDeferredGo env O O.deferred).deferred with
  | nil => rfl
  | cons x _ =>
    have := o8 x (d x (by rw [e]; exact List.mem_cons_self _ _))
    rw [h] at this; cases this

theorem fit_deferred (env : Env) (st : St) (a : Int) (h : st.deferred = []) : (fit env st a).deferred = [] := by
  unfold fit
  repeat' split
  all_goals first
    | exact h
    | exact nextColumn_deferred env st h

theorem step_putLineSlot (st : St) (e : Int) (i : Nat) :
    Step st (putSlot st e (.line i)) [i] [] := by
  refine ⟨?_, ?_⟩
  · simp [text, putSlot, textSlots_append, textSlots]
  · simp [figs, putSlot, figSlots_append, figSlots]

theorem step_putFigureSlot (st : St) (e : Int) (i : Nat) (h : st.deferred = []) :
    Step st (putSlot st e (.figure i)) [] [i] := by
  refine ⟨?_, ?_⟩
  · simp [text, putSlot, textSlots_append, textSlots]
  · simp [figs, putSlot, figSlots_append, figSlots, h]

theorem step_putPageFigureSlot (st : St) (e : Int) (i : Nat) (h : st.deferred = []) :
    Step st (putSlot st e (.pageFigure i)) [] [i] := by
  refine ⟨?_, ?_⟩
  · simp [text, putSlot, textSlots_append, textSlots]
  · simp [figs, putSlot, figSlots_append, figSlots, h]

theorem splitNotes_nil (n : Nat) : splitNotes n [] = ([], []) := by cases n <;> rfl

theorem step_putLine (env : Env) (allow : Bool) (st s : St) (l : Line)
    (h : putLineWithReserve allow env st l = .ok s) : Step st s [l.id] [] := by
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
      obtain ⟨t1, g1⟩ := step_putLineSlot st (env.pitchOf l.id) l.id
      exact ⟨t1, g1⟩

theorem step_putLines (env : Env) (allow : Bool) (st s : St) (ls : List Line)
    (h : putLines allow env st ls = .ok s) : Step st s (lineIds ls) [] := by
  induction ls generalizing st with
  | nil => simp only [putLines, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons l ls ih =>
    unfold putLines at h
    split at h
    · cases h
    · rename_i s1 e
      have a := step_putLine env allow st s1 l e
      have b := ih s1 h
      simpa [lineIds] using a.trans b

theorem step_putLinesKeeping (env : Env) (allow : Bool) (adj after : Int) (st s : St) (ls : List Line)
    (h : putLinesKeeping allow env adj after st ls = .ok s) : Step st s (lineIds ls) [] := by
  induction ls generalizing st with
  | nil => simp only [putLinesKeeping, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons l ls ih =>
    unfold putLinesKeeping at h
    split at h
    · cases h
    · rename_i s1 e
      have a := (Step.same rfl rfl rfl).trans (step_putLine env allow _ s1 l e)
      have b := ih s1 h
      simpa [lineIds] using a.trans b

theorem step_unmet (st : St) (u : List Unmet) : Step st { st with unmet := u } [] [] :=
  Step.same rfl rfl rfl

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

theorem trialRest_moved_step (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.moved next r)) :
    Step st next [] [] := by
  obtain ⟨_, n, _⟩ := trialRest_moved env k start st rows fid next r h
  rw [n]; exact step_nextColumn env st

theorem trialRest_placed_step (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat)
    (c : Nat) (next : St) (r : Keep) (h : trialRest env k start st rows fid = .ok (.placed c next r)) :
    Step st next (lineIds (rows.take c)) [] := by
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
      have b := step_putLines env false _ placed _ e
      simpa using (a.trans b).trans (step_unmet placed _)

theorem step_addUnmet (st : St) (u : Unmet) : Step st (addUnmet u st) [] [] :=
  Step.same rfl rfl rfl

theorem trial_moved_step (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (next : St) (r : Keep) (h : trial env k start st rows = .ok (.moved next r)) :
    Step st next [] [] := by
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
        · simpa using (step_addUnmet st _).trans (trialRest_moved_step env _ start _ _ _ next r h)
        · injection h with h; injection h with h1 _; subst h1; exact step_nextColumn env st
      · exact trialRest_moved_step env _ start _ _ _ next r h

theorem trial_placed_step (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line)
    (c : Nat) (next : St) (r : Keep) (h : trial env k start st rows = .ok (.placed c next r)) :
    Step st next (lineIds (rows.take c)) [] := by
  unfold trial at h
  split at h
  · cases h
  unfold trialFrom at h
  split at h
  · injection h with h; injection h with h1 h2 _; subst h1; subst h2; simpa [lineIds] using Step.refl st
  · split at h
    · simp at h
    · split at h
      · split at h
        · simpa using (step_addUnmet st _).trans (trialRest_placed_step env _ start _ _ _ c next r h)
        · simp at h
      · exact trialRest_placed_step env _ start _ _ _ c next r h


theorem take_length' {α : Type} (ls : List α) : ls.take ls.length = ls := by
  induction ls with
  | nil => rfl
  | cons _ _ ih => simp [List.take, ih]

theorem lineIds_append (a b : List Line) : lineIds (a ++ b) = lineIds a ++ lineIds b := by
  simp [lineIds]

set_option linter.unusedVariables false in
theorem step_placeLines (env : Env) (k : Keep) (start : Bool) (st : St) (rows : List Line) (s : St) (h : placeLines env k start st rows = .ok s) :
    Step st s (lineIds rows) [] := by
  match rows with
  | [] =>
    simp only [placeLines, Except.ok.injEq] at h; subst h; exact Step.refl _
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
      have b := step_placeLines env relaxed start next (r :: rs) s h
      simpa using a.trans b
    · rename_i count next relaxed e
      have a := trial_placed_step env k start st _ count next relaxed e
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
        have b := step_placeLines env relaxed false (nextColumn env next) ((r :: rs).drop count) s h
        have := (a.trans (step_nextColumn env next)).trans b
        rw [List.append_nil, List.append_nil, ← lineIds_append, List.take_append_drop] at this
        exact this
termination_by (rows.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  all_goals assumption


theorem step_flush (env : Env) (st : St) : Step st (flushPendingRule env st) [] [] := by
  unfold flushPendingRule
  split
  · exact Step.refl st
  · exact Step.same rfl rfl rfl

theorem step_placeWithNext (inner : Inner) (env : Env) (k : Keep) (start : Bool) (st : St) (ls : List Line)
    (l f : Nat) (later : List Flow) (s : St)
    (h : placeWithNext inner env k start st ls l f later = .ok s) : Step st s (lineIds ls) [] := by
  unfold placeWithNext at h
  split at h
  · cases h
  · rename_i full e
    split at h
    · injection h with h; subst h; exact step_placeLines env k start st ls _ e
    · split at h
      · injection h with h; subst h; exact step_placeLines env k start st ls _ e
      · split at h
        · cases h
        · rename_i before e2
          have a := step_placeLines env k start st _ before e2
          have m : Step before (afterFront env before) [] [] := by
            unfold afterFront; split
            · exact Step.refl _
            · exact step_nextColumn env _
          have b := step_placeLines env k _ _ _ s h
          have := (a.trans m).trans b
          rw [List.append_nil, ← lineIds_append, List.take_append_drop] at this
          exact this

theorem mem_append_left' {α : Type} {x : α} : ∀ {a : List α} (b : List α), x ∈ a → x ∈ a ++ b
  | _ :: _, _, .head _ => .head _
  | _ :: _, b, .tail _ m => .tail _ (mem_append_left' b m)

theorem mem_append_right' {α : Type} {x : α} : ∀ (a : List α) {b : List α}, x ∈ b → x ∈ a ++ b
  | [], _, m => m
  | _ :: a, _, m => .tail _ (mem_append_right' a m)

theorem join_app (a b : List (List Line)) : (a ++ b).join = a.join ++ b.join := by
  induction a with
  | nil => rfl
  | cons x xs ih => simp [List.join, ih]

theorem join_take_drop (n : Nat) (vs : List (List Line)) :
    lineIds (vs.take n).join ++ lineIds (vs.drop n).join = lineIds vs.join := by
  rw [← lineIds_append, ← join_app, List.take_append_drop]

/-- The rank of `placeStanza`. -/
def stanzaRank (k : Keep) (st : St) (verses : List (List Line)) : Nat × Nat × Nat := (verses.length, keepRank k, rank st)
def stanzaLt (a b : Nat × Nat × Nat) : Prop := Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) a b

theorem stanza_wf : WellFounded stanzaLt :=
  (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel Nat.lt_wfRel)).wf

theorem step_placeStanza (env : Env) (k : Keep) (start : Bool) (st : St) (verses : List (List Line)) (s : St) (h : placeStanza env k start st verses = .ok s) :
    Step st s (lineIds verses.join) [] := by
  have key : ∀ m, ∀ (k : Keep) (start : Bool) (st : St) (verses : List (List Line)),
      stanzaRank k st verses = m → ∀ s, placeStanza env k start st verses = .ok s →
      Step st s (lineIds verses.join) [] := by
    intro m
    induction m using stanza_wf.induction with
    | _ m ih =>
    intro k start st verses hm s h
    subst hm
    match verses with
    | [] => simp only [placeStanza, Except.ok.injEq] at h; subst h; exact Step.refl _
    | v :: vs =>
      rw [placeStanza] at h
      dsimp only at h
      split at h
      · rename_i h1
        split at h
        · have := ih _ (Prod.Lex.right _ (Prod.Lex.left _ _ (by simp [keepRank, h1.1]))) _ start _ (v :: vs) rfl s h
          simpa using (step_addUnmet st _).trans this
        · rename_i h2
          have r : rank (nextColumn env st) < rank st := by
            apply I4_nextColumn_rank; left
            cases e : empty st
            · rfl
            · simp [e] at h2
          have := ih _ (Prod.Lex.right _ (Prod.Lex.right _ r)) k start _ (v :: vs) rfl s h
          simpa using (step_nextColumn env st).trans this
      · split at h
        · rename_i h3
          have r : rank (nextColumn env st) < rank st := by
            apply I4_nextColumn_rank; left
            have := h3.2; simp only [Bool.or_eq_false_iff] at this; exact this.1
          have := ih _ (Prod.Lex.right _ (Prod.Lex.right _ r)) k start _ (v :: vs) rfl s h
          simpa using (step_nextColumn env st).trans this
        · split at h
          · rename_i h4
            split at h
            · cases h
            · rename_i placed e
              have a := step_placeLines env _ _ st _ placed e
              split at h
              · injection h with h; subst h
                rename_i c
                have : (v :: vs).drop (wholeVerses (fitting env st (v :: vs).join) (v :: vs)) = [] := by
                  rw [c]; simp
                have b := a.trans (step_unmet placed (placed.unmet ++ stanzaShort k start (headId v) (vs.length + 1)
                  (wholeVerses (fitting env st (v :: vs).join) (v :: vs))))
                rw [← join_take_drop (wholeVerses (fitting env st (v :: vs).join) (v :: vs)) (v :: vs), this]
                simpa [lineIds] using b
              · have b := ih _ (by apply Prod.Lex.left; simp only [stanzaRank, List.length_drop, List.length_cons]; have := h4.2; omega) k false _ _ rfl s h
                have := ((a.trans (step_unmet placed _)).trans (step_nextColumn env _)).trans b
                simpa [join_take_drop] using this
          · split at h
            · split at h
              · cases h
              · rename_i placed e
                have a := step_placeLines env _ true st v placed e
                have b := ih _ (Prod.Lex.left _ _ (by simp)) k false placed vs rfl
                  s h
                simpa [List.join, lineIds_append] using a.trans b
            · rename_i h5
              split at h
              · cases h
              · rename_i placed e
                have a := step_placeLines env _ _ st _ placed e
                split at h
                · injection h with h; subst h
                  rename_i c
                  have : (v :: vs).drop (splitAtBreak k start (vs.length + 1) (wholeVerses (fitting env st (v :: vs).join) (v :: vs))) = [] := by
                    rw [c]; simp
                  rw [← join_take_drop (splitAtBreak k start (vs.length + 1) (wholeVerses (fitting env st (v :: vs).join) (v :: vs))) (v :: vs), this]
                  simpa [lineIds] using a
                · have b := ih _ (by apply Prod.Lex.left; simp only [stanzaRank, List.length_drop, List.length_cons]; omega) k false _ _ rfl s h
                  have := (a.trans (step_nextColumn env _)).trans b
                  simpa [join_take_drop] using this
  exact key _ k start st verses rfl s h

theorem step_placeStanzaWithNext (inner : Inner) (env : Env) (k : Keep) (st : St) (verses : List (List Line))
    (l f : Nat) (later : List Flow) (s : St)
    (h : placeStanzaWithNext inner env k st verses l f later = .ok s) : Step st s (lineIds verses.join) [] := by
  unfold placeStanzaWithNext at h
  split at h
  · cases h
  · rename_i full e
    have a := step_placeStanza env k true st verses full e
    split at h
    · injection h with h; subst h; exact a
    · split at h
      · cases h
      · rename_i before e2
        split at h
        · injection h with h; subst h; exact a
        · have a2 := step_placeStanza env k true st _ before e2
          have b := step_placeStanza env k true _ _ s h
          have := (a2.trans (step_nextColumn env _)).trans b
          simpa [join_take_drop] using this

theorem step_waitFor (u : Unmet) (q : Nat × Bool) (st : St) : Step st (waitFor u q st) [] [] :=
  Step.same rfl rfl rfl

theorem step_waitForPrior (u : Unmet) (q : Nat × Bool) (st : St) :
    Step st (waitForPrior u q st) [] [] := by
  unfold waitForPrior; split
  · exact step_addUnmet st u
  · exact step_waitFor u q st

theorem pagesText_map (f : PageOut → PageOut) (hs : ∀ p, (f p).slots = p.slots) (ps : List PageOut) :
    pagesText (ps.map f).reverse = pagesText ps.reverse ∧ pagesFigs (ps.map f).reverse = pagesFigs ps.reverse := by
  induction ps with
  | nil => simp
  | cons p ps ih =>
    simp only [List.map, List.reverse_cons, pagesText_append, pagesFigs_append, ih.1, ih.2, pagesText, pagesFigs, hs]
    trivial

theorem step_checkWait (acc : St) (w : Wait) : Step acc (checkWait acc w) [] [] := by
  unfold checkWait
  split
  · exact Step.refl acc
  · split
    · exact step_addUnmet acc _
    · obtain ⟨a, b⟩ := pagesText_map (markUnmet w) (fun o => by unfold markUnmet; split <;> rfl) acc.done
      refine ⟨?_, ?_⟩
      · simp only [text]; rw [a]; simp
      · simp only [figs]; rw [b]; simp

theorem step_checkWaits (st : St) : Step st (checkWaits st) [] [] := by
  unfold checkWaits
  have : ∀ (ws : List Wait) (a : St), Step a (ws.foldl checkWait a) [] [] := by
    intro ws
    induction ws with
    | nil => intro a; exact Step.refl a
    | cons w ws ih => intro a; simpa using (step_checkWait a w).trans (ih _)
  simpa using (Step.same (s := { st with waits := [] }) rfl rfl rfl).trans (this st.waits _)


set_option linter.unusedVariables false in
theorem step_drainCarry (env : Env) (st : St) : Step st (drainCarry env st) [] [] := by
  rw [drainCarry]
  split
  · rename_i h
    have dec := I4_drain_rank env st ⟨Or.inl h.1, h.2⟩
    simpa using (step_nextColumn env st).trans (step_drainCarry env (nextColumn env st))
  · exact Step.refl st
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

set_option linter.unusedVariables false in
theorem step_seek (env : Env) (p : St → Bool) (st : St) : Step st (seek env p st) [] [] := by
  rw [seek]
  split
  · exact Step.refl st
  · split
    · rename_i h
      have dec := I4_drain_rank env st ⟨seek_cond st h.2, h.1⟩
      simpa using (step_nextColumn env st).trans (step_seek env p (nextColumn env st))
    · exact step_nextColumn env st
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem step_putCodeSlot (st : St) (e : Int) (ids : List Nat) (g : Nat) :
    Step st (putSlot st e (.code ids g)) ids [] := by
  refine ⟨?_, ?_⟩
  · simp [text, putSlot, textSlots_append, textSlots]
  · simp [figs, putSlot, figSlots_append, figSlots]

theorem Step.text_eq {st s : St} {t t' g : List Nat} (e : t = t') (h : Step st s t g) :
    Step st s t' g := e ▸ h

theorem step_seekFitCode (env : Env) (p : St → Bool) (st : St) (e : Int) (ids : List Nat) (g : Nat) :
    Step st (putSlot (fit env (seek env p st) e) e (.code ids g)) ids [] := by
  simpa using (step_seek env p st).trans ((step_fit env _ e).trans (step_putCodeSlot _ e ids g))

theorem step_placeCode (env : Env) (caption : Int) (first : Nat) (continued : Bool) (spans : List Nat)
    (isFirst : Bool) (st : St) (rows : List Line) (s : St)
    (h : placeCode env caption first continued spans isFirst st rows = .ok s) : Step st s (lineIds rows) [] := by
  have key : ∀ n, ∀ (isFirst : Bool) (st : St) (rows : List Line), rows.length = n →
      ∀ s, placeCode env caption first continued spans isFirst st rows = .ok s → Step st s (lineIds rows) [] := by
    intro n
    induction n using Nat.strongInductionOn with
    | _ n ih =>
    intro isFirst st rows hn s h
    match rows with
    | [] => simp only [placeCode, Except.ok.injEq] at h; subst h; exact Step.refl _
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
            rename_i c
            refine Step.text_eq ?_ (step_seekFitCode env _ st _ _ _)
            rw [c]; exact congrArg lineIds (take_length' (r :: rs))
          · rename_i c
            have b := ih _ (by rw [← hn]; simp only [List.length_drop, List.length_cons]; exact Nat.sub_lt (Nat.succ_pos _) (Nat.pos_of_ne_zero c0))
              false _ _ rfl s h
            refine Step.text_eq ?_ (((step_seekFitCode env _ st _ _ _).trans (step_nextColumn env _)).trans b)
            show lineIds _ ++ [] ++ lineIds _ = _
            rw [List.append_nil, ← lineIds_append, List.take_append_drop]
  exact key _ isFirst st rows rfl s h

theorem step_parityStart (env : Env) (accept : Nat → Bool) (st : St) :
    Step st (parityStart env accept st) [] [] := by
  have a := step_drainCarry env st
  have b : Step (drainCarry env st)
      (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st else nextPage env (drainCarry env st)) [] [] := by
    split
    · exact Step.refl _
    · exact step_nextPage env _
  have c := a.trans b
  simp only [List.append_nil] at c
  unfold parityStart
  dsimp only
  generalize (if empty (drainCarry env st) ∧ (drainCarry env st).column = 0 then drainCarry env st else nextPage env (drainCarry env st)) = nx at c
  split
  · exact c
  · split
    · refine ⟨?_, ?_⟩
      · have := c.1; simp only [text, List.append_nil] at this; simp [text, pagesText_append, pagesText, textSlots, this]
      · have := c.2; simp only [figs, List.append_nil] at this; simp [figs, pagesFigs_append, pagesFigs, figSlots]; simpa using this
    · simpa using c.trans (step_nextPage env nx)

theorem step_breakAt (env : Env) (k : BreakKind) (st : St) : Step st (breakAt env k st) [] [] := by
  have bp : Step st (breakPage env st) [] [] := by
    unfold breakPage; split
    · exact Step.refl st
    · exact step_nextPage env st
  cases k <;> unfold breakAt <;> dsimp only
  · split
    · exact step_nextColumn env st
    · exact bp
  · exact bp
  · exact step_parityStart env _ st
  · exact step_parityStart env _ st

theorem step_sectionStart (env : Env) (k : BreakKind) (st : St) : Step st (sectionStart env k st) [] [] := by
  have a := step_drainCarry env st
  have b : ∀ c : Prop, ∀ _ : Decidable c, Step (drainCarry env st)
      (if c then drainCarry env st else breakAt env k (drainCarry env st)) [] [] := by
    intro c _; split
    · exact Step.refl _
    · exact step_breakAt env k _
  unfold sectionStart
  cases k
  · simpa using a.trans (b _ _)
  · simpa using a.trans (b _ _)
  · simpa using a.trans (step_breakAt env _ _)
  · simpa using a.trans (step_breakAt env _ _)

theorem step_switchColumns (env : Env) (cols : Nat) (st : St) :
    Step st (switchColumns env cols st) [] [] := by
  have a := step_drainCarry env st
  unfold switchColumns
  dsimp only
  split
  · have h := step_closed env (drainCarry env st) { close env (drainCarry env st) with
      columns := cols, firstLine := (drainCarry env st).used, column := 0, used := (drainCarry env st).used,
      reserved := (drainCarry env st).notesUsed, adjust := min (drainCarry env st).notesUsed (drainCarry env st).adjust,
      setAdjust := min (drainCarry env st).notesUsed (drainCarry env st).adjust,
      slots := [], notes := [], join := none, pending := 0, blankActive := false, blankSpans := 0, boxes := [],
      afterRules := [] } rfl rfl (close_fields env _).1
    simpa using a.trans h
  · simpa using (a.trans (step_nextPage env _)).trans (Step.same rfl rfl rfl)

theorem step_restoreColumns (env : Env) (st : St) : Step st (restoreColumns env st) [] [] := by
  simpa using (step_nextPage env st).trans (Step.same rfl rfl rfl)

set_option linter.unusedVariables false in
theorem step_judgeNeed (env : Env) (b : Int) (st : St) : Step st (judgeNeed env b st) [] [] := by
  rw [judgeNeed]
  split
  · exact Step.refl st
  · split
    · rename_i h
      have dec := I4_nextColumn_rank env st (Or.inr h.2)
      simpa using (step_nextColumn env st).trans (step_judgeNeed env b (nextColumn env st))
    · split
      · exact Step.refl st
      · rename_i h
        have dec := I4_nextColumn_rank env st (Or.inl (by simpa using h))
        simpa using (step_nextColumn env st).trans (step_judgeNeed env b (nextColumn env st))
termination_by rank st
decreasing_by
  all_goals simp_wf
  all_goals assumption


theorem putLine_fields (env : Env) (allow : Bool) (st s : St) (l : Line)
    (h : putLineWithReserve allow env st l = .ok s) :
    s.done = st.done ∧ s.deferred = st.deferred ∧ s.page = st.page ∧ s.column = st.column := by
  unfold putLineWithReserve at h
  split at h
  · cases h
  · split at h
    · split at h
      · cases h
      · injection h with h; subst h; exact ⟨rfl, rfl, rfl, rfl⟩
    · injection h with h; subst h; exact ⟨rfl, rfl, rfl, rfl⟩

theorem step_putHeading (env : Env) (st : St) (firstId : Nat) (extent : Int) (ls : List Line) (s : St) (h : putHeading env st firstId extent ls = .ok s) :
    Step st s [firstId] [] := by
  unfold putHeading at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    obtain ⟨d, df, _, _⟩ := putLine_fields _ false st placed _ e
    refine ⟨?_, ?_⟩
    · simp [text, d, textSlots_append, textSlots]
    · simp [figs, d, df, figSlots_append, figSlots]

theorem step_placeHeading (env : Env) (st : St) (firstId : Nat) (extent : Int) (ls : List Line) (s : St) (h : placeHeading env st firstId extent ls = .ok s) :
    Step st s [firstId] [] := by
  unfold placeHeading at h
  split at h
  · cases h
  · split at h
    · simpa using (Step.same rfl rfl rfl).trans (step_putHeading env _ firstId extent ls s h)
    · simpa using (step_fit env st _).trans (step_putHeading env _ firstId extent ls s h)

theorem step_keepFollowing (inner : Inner) (env : Env) (hd : Bool) (st : St) (extent : Int) (ls : List Line) (later : List Flow) :
    Step st (keepFollowing inner env hd st extent ls later) [] [] := by
  unfold keepFollowing keepFrom
  split
  · exact step_nextColumn env st
  · exact Step.refl st

theorem step_putRuledHeading (env : Env) (ready : St) (b a : Int) (ends : List Int) (fid : Nat) (e : Int) (ls : List Line) (s : St) (h : putRuledHeading env ready b a ends fid e ls = .ok s) :
    Step ready s [fid] [] := by
  unfold putRuledHeading at h
  split at h
  · cases h
  · rename_i placed e2
    injection h with h; subst h
    have c := step_putHeading env _ fid e ls placed e2
    simpa using ((Step.same rfl rfl rfl).trans c).trans (Step.same rfl rfl rfl)

theorem step_headingReady (env : Env) (hs : St) (fid : Nat) (extent size : Int) :
    Step hs (headingReady env hs fid extent size) [] [] := by
  unfold headingReady
  split
  · exact Step.same rfl rfl rfl
  · exact step_fit env hs size

theorem step_headingState (env : Env) (st : St) (recto b : Bool) :
    Step st (headingStateOf env st recto b) [] [] := by
  unfold headingStateOf
  split
  · exact step_parityStart env _ st
  · unfold keepFrom; split
    · exact step_nextColumn env st
    · exact Step.refl st

/-- What `ruledHere` places is what `ruledLinesHere` places with the flows
    after the block or without them. -/
theorem ruledHere_some (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (p : St)
    (h : ruledHere inner env st r later = .ok (some p)) :
    ∃ l', ruledLinesHere env st r l' = .ok (some p) := by
  rw [ruledHere] at h
  split at h
  · cases h
  · rename_i inside e
    rcases hereOr_some _ _ _ _ p h with h | h
    · subst h; exact ⟨later, e⟩
    · exact ⟨[], h⟩

theorem ruledPlaceAt_step (env : Env) (st : St) (r : Ruled) (first lastLine : Line) (later : List Flow)
    (ready p : St) (h : ruledPlaceAt env st r first lastLine later ready = .ok p) :
    Step ready p (lineIds r.lines) [] := by
  unfold ruledPlaceAt at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    have c := step_putLinesKeeping env true _ _ _ placed r.lines e
    simpa using (Step.same rfl rfl rfl).trans (c.trans (Step.same rfl rfl rfl))

theorem ruledLinesHere_step (env : Env) (st : St) (r : Ruled) (later : List Flow) (p : St)
    (h : ruledLinesHere env st r later = .ok (some p)) : Step st p (lineIds r.lines) [] := by
  unfold ruledLinesHere at h
  split at h
  · split at h
    · cases h
    · split at h
      · split at h
        · cases h
        · rename_i s0 e
          injection h with h; injection h with h; subst h
          simpa using (step_fit env st _).trans (ruledPlaceAt_step env st r _ _ later _ s0 e)
      · cases h
  · cases h

set_option linter.unusedVariables false in
theorem step_placeRuled (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (s : St) (h : placeRuled inner env st r later = .ok s) :
    Step st s (ruledText r) [] := by
  rw [placeRuled] at h
  split at h
  · rename_i recto extent hh
    have tx : ∀ r' : Ruled, r'.heading = r.heading → r'.lines = r.lines → ruledText r' = [headId r.lines] := by
      intro r' e1 e2; simp [ruledText, e1, e2, hh]
    rw [tx r rfl rfl]
    dsimp only at h
    generalize fitsFollowingGo inner env (keepVirtual env true st extent r.lines) (keepWanted later).1 0 (keepWanted later).2 = fb at h
    have hr := rank_headingState_le env st recto fb
    have hsS := step_headingState env st recto fb
    generalize headingStateOf env st recto fb = HS at h hr hsS
    split at h
    · cases h
    · split at h
      · split at h
        · rename_i ha
          have dec : Prod.Lex (· < ·) (· < ·) (ruledRank { r with after := none }, rank HS) (ruledRank r, rank st) :=
            Prod.Lex.left _ _ (ruledRank_after r ha)
          have c := step_placeRuled inner env HS { r with after := none } later s h
          rw [tx { r with after := none } rfl rfl] at c
          simpa using hsS.trans c
        · rename_i ha hb
          have dec : Prod.Lex (· < ·) (· < ·) (ruledRank { r with before := none }, rank HS) (ruledRank r, rank st) :=
            Prod.Lex.left _ _ (ruledRank_before r ha hb)
          have c := step_placeRuled inner env HS { r with before := none } later s h
          rw [tx { r with before := none } rfl rfl] at c
          simpa using hsS.trans c
        · simpa using hsS.trans (step_placeHeading env HS _ extent r.lines s h)
      · split at h
        · split at h
          · rename_i h2 h3
            have dec : Prod.Lex (· < ·) (· < ·) (ruledRank r, rank (headingReady env HS (headId r.lines) extent
                (headingBeforeAt env HS r + headingNeed env HS extent r.lines + headingAfterExtra env r extent)))
                (ruledRank r, rank st) :=
              Prod.Lex.right _ (Nat.lt_of_lt_of_le (headingReady_moved env HS _ _ _ h3) hr)
            have c := step_placeRuled inner env _ r later s h
            rw [tx r rfl rfl] at c
            simpa using (hsS.trans (step_headingReady env HS _ _ _)).trans c
          · simpa using (hsS.trans (step_headingReady env HS _ _ _)).trans
              (step_putRuledHeading env _ _ _ _ _ extent r.lines s h)
        · split at h
          · cases h
          · rename_i inside e
            split at h
            · injection h with h; subst h
              simpa using (hsS.trans (step_headingReady env HS _ _ _)).trans
                (step_putRuledHeading env _ _ _ _ _ extent r.lines inside e)
            · split at h
              · rename_i h4
                have dec : Prod.Lex (· < ·) (· < ·) (ruledRank r, rank (headingReady env HS (headId r.lines) extent
                    (headingBeforeAt env HS r + headingNeed env HS extent r.lines + headingAfterExtra env r extent)))
                    (ruledRank r, rank st) :=
                  Prod.Lex.right _ (Nat.lt_of_lt_of_le (headingReady_moved env HS _ _ _ h4) hr)
                have c := step_placeRuled inner env _ r later s h
                rw [tx r rfl rfl] at c
                simpa using (hsS.trans (step_headingReady env HS _ _ _)).trans c
              · simpa using (hsS.trans (step_headingReady env HS _ _ _)).trans
                  (step_putRuledHeading env _ _ _ _ _ extent r.lines s h)
  · rename_i hh
    have tx : ∀ r' : Ruled, r'.heading = r.heading → r'.lines = r.lines → ruledText r' = lineIds r.lines := by
      intro r' e1 e2; simp [ruledText, e1, e2, hh]
    rw [tx r rfl rfl]
    split at h
    · rename_i first lastLine _ _
      split at h
      · cases h
      · rename_i placed hr
        injection h with h; subst h
        obtain ⟨l', e⟩ := ruledHere_some inner env st r later placed hr
        exact ruledLinesHere_step env st r l' placed e
      · split at h
        · rename_i h1
          have dec : Prod.Lex (· < ·) (· < ·) (ruledRank { r with joined := false }, rank (nextColumn env (flushPendingRule env st)))
              (ruledRank r, rank st) := by
            apply Prod.Lex.left; simp [ruledRank, joinedRank, h1.1]
          have c := step_placeRuled inner env (nextColumn env (flushPendingRule env st)) { r with joined := false } later s h
          rw [tx { r with joined := false } rfl rfl] at c
          simpa using ((step_flush env st).trans (step_nextColumn env _)).trans c
        · split at h
          · exact step_placeLines env r.keep true st r.lines s h
          · split at h
            · rename_i h2
              have dec : Prod.Lex (· < ·) (· < ·) (ruledRank r, rank (fit env st (room env st + 1)))
                  (ruledRank r, rank st) :=
                Prod.Lex.right _ (I4_fit_moved env st _ h2)
              have c := step_placeRuled inner env _ r later s h
              rw [tx r rfl rfl] at c
              simpa using (step_fit env st _).trans c
            · exact step_placeLines env r.keep true st r.lines s h
    · rename_i H
      have : r.lines = [] := by
        cases e : r.lines with
        | nil => rfl
        | cons x xs => exact absurd (H x ((x :: xs).getLast (by simp)) (by rw [e]; rfl) (by rw [e]; rfl)) id
      injection h with h; subst h
      rw [this]; exact Step.refl _
termination_by (ruledRank r, rank st)
decreasing_by
  all_goals simp_wf
  all_goals assumption


theorem step_placeRuledKeeping (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (s : St) (h : placeRuledKeeping inner env st r later = .ok s) :
    Step st s (ruledText r) [] := by
  unfold placeRuledKeeping at h
  split at h
  · cases h
  · rename_i full e
    dsimp only at h
    split at h
    · split at h
      · have c := step_placeRuled inner env _ { r with joined := false } later s h
        have tx : ruledText { r with joined := false } = ruledText r := rfl
        rw [tx] at c
        simpa using ((step_flush env st).trans (step_nextColumn env _)).trans c
      · injection h with h; subst h; exact step_placeRuled inner env st r later _ e
    · injection h with h; subst h; exact step_placeRuled inner env st r later _ e

theorem step_putWrappedSlot (st : St) (i : Nat) :
    Step st (putSlot st 0 (.wrapped i)) [i] [] := by
  refine ⟨?_, ?_⟩
  · simp [text, putSlot, textSlots_append, textSlots]
  · simp [figs, putSlot, figSlots_append, figSlots]

theorem step_putWrappedLine (env : Env) (fe : Int) (st s : St) (l : Line)
    (h : putWrappedLine env fe st l = .ok s) : Step st s [l.id] [] := by
  unfold putWrappedLine at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    have c := step_putLine env false _ placed l e
    simpa using ((Step.same rfl rfl rfl).trans c).trans (Step.same rfl rfl rfl)

theorem step_putBeside (env : Env) (fe : Int) (st s : St) (ls : List Line)
    (h : putBeside env fe st ls = .ok s) : Step st s (lineIds ls) [] := by
  induction ls generalizing st with
  | nil => simp only [putBeside, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons l ls ih =>
    unfold putBeside at h
    split at h
    · cases h
    · rename_i s1 e
      have a := step_putWrappedLine env fe _ s1 l e
      have b := ih s1 h
      simpa [lineIds] using ((Step.same rfl rfl rfl).trans a).trans b

theorem step_fitPending (env : Env) (st R : St) (p a : Int) (h : Step st R [] []) :
    Step st (fit env { R with pending := p } a) [] [] := by
  have c := (h.trans (Step.same rfl rfl rfl)).trans (step_fit env { R with pending := p } a)
  simpa only [List.append_nil] using c

theorem step_overflowMove (env : Env) (st : St) (l : Line) (gap : Int) :
    Step st (overflowMove env st l gap) [] [] := by
  unfold overflowMove
  split
  · exact step_nextColumn env st
  · exact Step.refl st

theorem step_overflowReady (env : Env) (st : St) (l : Line) : Step st (overflowReady env st l) [] [] := by
  unfold overflowReady
  dsimp only
  apply step_fitPending
  exact step_overflowMove env st l _

theorem step_placeWrappedOverflow (env : Env) (st s : St) (ls : List Line)
    (h : placeWrappedOverflow env st ls = .ok s) : Step st s (lineIds ls) [] := by
  induction ls generalizing st with
  | nil => simp only [placeWrappedOverflow, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons l ls ih =>
    unfold placeWrappedOverflow at h
    split at h
    · cases h
    · rename_i placed e
      have a := step_putLine env false _ placed l e
      have b := ih placed h
      simpa [lineIds] using ((step_overflowReady env st l).trans a).trans b

theorem step_placeWrapped (env : Env) (st : St) (i : Nat) (e : Int) (ls : List Line)
    (s : St) (h : placeWrapped env st i e ls = .ok s) : Step st s (i :: lineIds ls) [] := by
  unfold placeWrapped at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · cases h
    · rename_i placed eq
      generalize fittingWrapped env _ _ ls = c at h eq
      have ab := ((step_fit env st e).trans (step_putWrappedSlot _ i)).trans
        (step_putBeside env _ _ placed _ eq)
      have tx : i :: lineIds ls = [] ++ [i] ++ lineIds (ls.take c) ++ lineIds (ls.drop c) := by
        rw [List.append_assoc, ← lineIds_append, List.take_append_drop]; rfl
      rw [tx]
      split at h
      · rename_i emp
        injection h with h; subst h
        have hd : ls.drop c = [] := by
          cases d : ls.drop c with
          | nil => rfl
          | cons _ _ => rw [d] at emp; cases emp
        rw [hd]
        have c2 := ab.trans (Step.same (s := { placed with used := max placed.used ((fit env st e).used + e) }) rfl rfl rfl)
        simpa only [List.append_nil, lineIds, List.map] using c2
      · have b := step_placeWrappedOverflow env _ s _ h
        have c2 := ((ab.trans (Step.same (s := { placed with used := max placed.used ((fit env st e).used + e) })
          rfl rfl rfl)).trans (step_nextColumn env _)).trans b
        simpa only [List.append_nil] using c2

theorem step_endWrap (region : Region) (st : St) : Step st (endWrap region st) [] [] := Step.same rfl rfl rfl

theorem step_moveCursor (env : Env) (region : Region) (st : St) : Step st (moveCursor env region st) [] [] := by
  simpa using (step_endWrap region st).trans (step_nextColumn env _)

theorem step_putHere (env : Env) (region : Region) (st s : St) (l : Line) (h : putHere env region st l = .ok s) :
    Step st s [l.id] [] := by
  unfold putHere at h
  split at h
  · exact step_putWrappedLine env _ st s l h
  · exact step_putLine env false st s l h

theorem step_putHereLines (env : Env) (region : Region) (st s : St) (ls : List Line)
    (h : putHereLines env region st ls = .ok s) : Step st s (lineIds ls) [] := by
  induction ls generalizing st with
  | nil => simp only [putHereLines, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons l ls ih =>
    unfold putHereLines at h
    split at h
    · cases h
    · rename_i s1 e
      simpa [lineIds] using (step_putHere env region st s1 l e).trans (ih s1 h)

theorem trialWrapRest_placed_step (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool)
    (st : St) (rows : List Line) (fid : Nat) (c : Nat) (next : St) (r : Keep)
    (h : trialWrapRest env region limit k start st rows fid = .ok (.placed c next r)) :
    Step st next (lineIds (rows.take c)) [] := by
  unfold trialWrapRest at h
  dsimp only at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i placed e
      injection h with h; injection h with h1 h2 _
      subst h1; subst h2
      have a := step_fit env st (sumPitch env (rows.take (if limited limit (splitAtBreak k start rows.length
        (fittingHere env region st rows)) = 0 then max 1 (fittingHere env region st rows) else limited limit
        (splitAtBreak k start rows.length (fittingHere env region st rows)))))
      have b := step_putHereLines env region _ placed _ e
      simpa using (a.trans b).trans (step_unmet placed _)

theorem trialWrap_moved_step (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool) (st : St)
    (rows : List Line) (next : St) (r : Keep) (h : trialWrap env region limit k start st rows = .ok (.moved next r)) :
    Step st next [] [] := by
  unfold trialWrap at h
  split at h
  · cases h
  unfold trialWrapFrom at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · split at h
      · split at h
        · obtain ⟨_, n, _⟩ := trialWrapRest_moved env region limit _ start _ _ _ next r h
          subst n; simpa using (step_addUnmet st _).trans (step_moveCursor env region _)
        · injection h with h; injection h with h1 _; subst h1; exact step_moveCursor env region st
      · obtain ⟨_, n, _⟩ := trialWrapRest_moved env region limit _ start _ _ _ next r h
        subst n; exact step_moveCursor env region st

theorem trialWrap_placed_step (env : Env) (region : Region) (limit : Option Nat) (k : Keep) (start : Bool) (st : St)
    (rows : List Line) (c : Nat) (next : St) (r : Keep)
    (h : trialWrap env region limit k start st rows = .ok (.placed c next r)) :
    Step st next (lineIds (rows.take c)) [] := by
  unfold trialWrap at h
  split at h
  · cases h
  unfold trialWrapFrom at h
  split at h
  · injection h with h; injection h with h1 h2 _; subst h1; subst h2; simpa [lineIds] using Step.refl st
  · split at h
    · simp at h
    · split at h
      · split at h
        · simpa using (step_addUnmet st _).trans (trialWrapRest_placed_step env region limit _ start _ _ _ c next r h)
        · simp at h
      · exact trialWrapRest_placed_step env region limit _ start _ _ _ c next r h

/-- The ids `s`, `s + 1`, ..., of `n` lines. -/
def ids : Nat → Nat → List Nat
  | _, 0 => []
  | s, n + 1 => s :: ids (s + 1) n

theorem ids_append (s a b : Nat) : ids s a ++ ids (s + a) b = ids s (a + b) := by
  induction a generalizing s with
  | zero => simp [ids]
  | succ a ih =>
    rw [Nat.succ_add]
    show s :: (ids (s + 1) a ++ ids (s + (a + 1)) b) = s :: ids (s + 1) (a + b)
    rw [show s + (a + 1) = s + 1 + a by omega, ih]

theorem ids_take (s m n : Nat) : (ids s n).take m = ids s (min m n) := by
  induction n generalizing s m with
  | zero => simp [ids]
  | succ n ih =>
    cases m with
    | zero => simp [ids]
    | succ m =>
      show s :: (ids (s + 1) n).take m = ids s (min (m + 1) (n + 1))
      rw [ih, show min (m + 1) (n + 1) = min m n + 1 by omega]; rfl

theorem lineIds_take (ls : List Line) (n : Nat) : lineIds (ls.take n) = (lineIds ls).take n := by
  induction ls generalizing n with
  | nil => cases n <;> rfl
  | cons l ls ih => cases n with
    | zero => rfl
    | succ n => simp only [List.take, lineIds, List.map] at ih ⊢; rw [ih]

def lex4lt (a b : Nat × Nat × Nat × Nat) : Prop :=
  Prod.Lex (· < ·) (Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·))) a b

theorem lex4_wf : WellFounded lex4lt :=
  (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel Nat.lt_wfRel))).wf

/-- The lines `parts` places are the lines of the paragraph from the
    `before`-th on, each once and in order, when the breaker numbers each
    line after those placed before it (`numberedLines`). -/
theorem I5_parts_lines (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St) (base : Nat)
    (hb : ∀ a c t, lineIds ((breaker a c t).map (·.1)) = ids (base + c) (breaker a c t).length)
    (hh : ∀ s, Step s (hold s) [] []) :
    ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) (s : St),
    parts env region breaker items lastWanted follows hold limit k isStart start before at' = .ok s →
    ∃ n, Step at' s (ids (base + before) n) [] := by
  have key : ∀ m, ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
      (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) = m → ∀ s,
      parts env region breaker items lastWanted follows hold limit k isStart start before at' = .ok s →
      ∃ n, Step at' s (ids (base + before) n) [] := by
    intro m
    induction m using lex4_wf.induction with
    | _ m ih =>
    intro limit k isStart start before at' hm0 s h
    subst hm0
    rw [parts] at h
    split at h
    · cases h
    · rename_i moved relaxed hm
      have a := trialWrap_moved_step env region limit k isStart at' _ moved relaxed hm
      have dec : lex4lt (items - start, keepRank relaxed, rank moved, limitRank none (breaker moved before start).length)
          (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
        apply Prod.Lex.right
        cases I4_trialWrap_moved env region limit k isStart at' _ moved relaxed hm with
        | inl l => exact Prod.Lex.left _ _ l
        | inr e => rw [e.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ e.2)
      obtain ⟨n, b⟩ := ih _ dec none relaxed isStart start before moved rfl s h
      exact ⟨n, by simpa using a.trans b⟩
    · rename_i count placed relaxed hm
      have a := trialWrap_placed_step env region limit k isStart at' _ count placed relaxed hm
      rw [lineIds_take, hb, ids_take] at a
      have done : Step at' (hold (checkWaits placed)) (ids (base + before) (min count (breaker at' before start).length)) [] := by
        simpa using (a.trans (step_checkWaits placed)).trans (hh _)
      have movePart : ∀ s, empty at' = false →
          parts env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at') = .ok s →
          ∃ n, Step at' s (ids (base + before) n) [] := by
        intro s e3 e
        have dec : lex4lt (items - start, keepRank k, rank (moveCursor env region at'),
            limitRank none (breaker (moveCursor env region at') before start).length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
          apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
          exact I4_moveCursor_rank env region at' (Or.inl e3)
        obtain ⟨n, b⟩ := ih _ dec none k isStart start before _ rfl s e
        exact ⟨n, by simpa using (step_moveCursor env region at').trans b⟩
      have retry : ∀ s n, n < limitRank limit (breaker at' before start).length →
          parts env region breaker items lastWanted follows hold (some n) k isStart start before at' = .ok s →
          ∃ n, Step at' s (ids (base + before) n) [] := by
        intro s n hn e
        have dec : lex4lt (items - start, keepRank k, rank at', limitRank (some n) (breaker at' before start).length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
          apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; exact hn
        exact ih _ dec (some n) k isStart start before at' rfl s e
      split at h
      · split at h
        · injection h with h; subst h; exact ⟨_, done⟩
        · split at h
          · split at h
            · rename_i h2; exact retry s _ h2 h
            · cases h
          · split at h
            · rename_i h3; exact movePart s h3 h
            · injection h with h; subst h; exact ⟨_, done⟩
      · rename_i full
        have mc : min count (breaker at' before start).length = count := by omega
        rw [mc] at a
        split at h
        · rename_i h4
          have go : ∀ s, parts env region breaker items lastWanted follows hold none relaxed false
              (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed) = .ok s →
              ∃ n, Step at' s (ids (base + before) n) [] := by
            intro s e
            have dec : lex4lt (items - nextItem (breaker at' before start) count start, keepRank relaxed,
                rank (moveCursor env region placed), limitRank none (breaker (moveCursor env region placed) (before + count)
                  (nextItem (breaker at' before start) count start)).length)
                (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
              apply Prod.Lex.left; obtain ⟨_, _⟩ := h4; omega
            obtain ⟨n, b⟩ := ih _ dec none relaxed false _ (before + count) _ rfl s e
            refine ⟨count + n, ?_⟩
            have c := (a.trans (step_moveCursor env region placed)).trans b
            rw [← ids_append, Nat.add_assoc]; simpa using c
          split at h
          · split at h
            · split at h
              · rename_i h6; exact retry s _ h6 h
              · cases h
            · split at h
              · rename_i h7; exact movePart s h7 h
              · exact go s h
          · exact go s h
        · cases h
  intro limit k isStart start before at' s h
  exact key _ limit k isStart start before at' rfl s h

/-- Each index with its lines, `P i ls` for each pair, in order. -/
def Each (P : Nat → List Nat → Prop) : List Nat → List (List Nat) → Prop
  | [], [] => True
  | i :: is, ls :: lss => P i ls ∧ Each P is lss
  | _, _ => False

theorem Each.append {P : Nat → List Nat → Prop} :
    ∀ {a b : List Nat} {la lb : List (List Nat)}, Each P a la → Each P b lb → Each P (a ++ b) (la ++ lb)
  | [], _, [], _, _, hb => hb
  | _ :: _, _, _ :: _, _, ⟨p, r⟩, hb => ⟨p, Each.append r hb⟩
  | [], _, _ :: _, _, h, _ => h.elim
  | _ :: _, _, [], _, h, _ => h.elim

theorem join_append' (a b : List (List Nat)) : (a ++ b).join = a.join ++ b.join := by
  induction a with
  | nil => rfl
  | cons x xs ih => simp [List.join, ih, List.append_assoc]

/-- The trials of `tryVerses`: each places the rows of its verse line
    composed at the cursor the trial before it leaves. -/
def VerseChain (b : Beside) : St → List Nat → List St → Prop
  | _, _, [] => True
  | c, i :: is, t :: ts => Step c t (lineIds (b.compose c i)) [] ∧ VerseChain b t is ts
  | _, [], _ :: _ => False

theorem I5_tryVerses_lines (env : Env) (region : Region) (b : Beside) (cursor : St) (indices : List Nat)
    (trials : List St) (h : tryVerses env region b cursor indices = .ok trials) : VerseChain b cursor indices trials := by
  induction indices generalizing cursor trials with
  | nil => simp [tryVerses] at h; subst h; trivial
  | cons index later ih =>
    unfold tryVerses at h
    split at h
    · cases h
    · rename_i count placed relaxed hm
      split at h
      · rename_i hc
        split at h
        · cases h
        · rename_i rest e
          injection h with h; subst h
          have a := trialWrap_placed_step env region none ⟨1, 1, false⟩ true cursor _ count placed relaxed hm
          rw [hc.1, List.take_length] at a
          exact ⟨a, ih placed rest e⟩
      · injection h with h; subst h; trivial
    · injection h with h; subst h; trivial

theorem verseChain_get (b : Beside) (P : Nat → List Nat → Prop) (hP : ∀ c i, P i (lineIds (b.compose c i))) :
    ∀ (ts : List St) (c : St) (is : List Nat) (n : Nat) (t : St), VerseChain b c is ts → ts.get? n = some t →
    ∃ lss, Each P (is.take (n + 1)) lss ∧ Step c t lss.join []
  | [], _, _, _, _, _, e => by simp at e
  | _ :: _, _, [], _, _, h, _ => h.elim
  | t0 :: ts, c, i :: is, 0, t, ⟨s, _⟩, e => by
    simp at e; subst e
    exact ⟨[lineIds (b.compose c i)], ⟨hP c i, by cases is <;> trivial⟩, by simpa [List.join] using s⟩
  | t0 :: ts, c, i :: is, n + 1, t, ⟨s, r⟩, e => by
    simp at e
    obtain ⟨lss, he, st⟩ := verseChain_get b P hP ts t0 is n t r e
    exact ⟨lineIds (b.compose c i) :: lss, ⟨hP c i, he⟩, by simpa [List.join] using s.trans st⟩

def lex5lt (a b : Nat × Nat × Nat × Nat × Nat) : Prop :=
  Prod.Lex (· < ·) (Prod.Lex (· < ·) (Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)))) a b

theorem lex5_wf : WellFounded lex5lt :=
  (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel Nat.lt_wfRel)))).wf

theorem getElem?_get? (l : List St) (n : Nat) : l[n]? = l.get? n := by
  unfold getElem?
  split
  · rename_i h; simp [List.get?_eq_get h]; rfl
  · rename_i h; rw [List.get?_len_le (by omega)]

theorem take_of_drop_isEmpty (l : List Nat) (n : Nat) (h : (l.drop n).isEmpty = true) : l.take n = l := by
  have e : l.drop n = [] := by cases hd : l.drop n <;> simp_all [List.isEmpty]
  have := List.take_append_drop n l
  rw [e, List.append_nil] at this; exact this

/-- The verse lines `stanza` places: each verse line of the stanza once, in
    order, each the lines of `P` (the rows of the verse line composed at a
    cursor, or the lines the fallback places), when the fallback places the
    lines of `P` of its verse line and the hold of what follows places
    nothing. -/
theorem stanza_accept_lines (env : Env) (region : Region) (b : Beside) (a : StanzaArgs)
    (P : Nat → List Nat → Prop) (hP : ∀ c i, P i (lineIds (b.compose c i)))
    (hf : ∀ i later c s, a.fallback i later c = .ok s → ∃ ls, P i ls ∧ Step c s ls [])
    (hh : ∀ i r l s, Step s (b.hold i r l s) [] []) : ∀ m,
    (∀ later keep isStart cursor indices s, (indices.length, keepRank keep, rank cursor, 1, 0) = m →
      stanza env region b a later keep isStart cursor indices = .ok s →
      ∃ lss, Each P indices lss ∧ Step cursor s lss.join []) ∧
    (∀ later keep isStart cursor indices trials count problems s, (indices.length, keepRank keep, rank cursor, 0, count) = m →
      VerseChain b cursor indices trials →
      accept env region b a later keep isStart cursor indices trials count problems = .ok s →
      ∃ lss, Each P indices lss ∧ Step cursor s lss.join []) := by
  intro m
  induction m using lex5_wf.induction with
  | _ m ih =>
  constructor
  · intro later keep isStart cursor indices s hm h
    subst hm
    cases indices with
    | nil =>
      simp only [stanza, Except.ok.injEq] at h; subst h
      exact ⟨[], trivial, by simpa using step_checkWaits cursor⟩
    | cons firstIndex rest =>
      rw [stanza] at h
      split at h
      · cases h
      · rename_i trials ht
        have hc := I5_tryVerses_lines env region b cursor _ trials ht
        -- a recursive `stanza` on the same verse lines from a cursor the step to which places nothing
        have again : ∀ keep' cursor', Step cursor cursor' [] [] →
            lex5lt ((firstIndex :: rest).length, keepRank keep', rank cursor', 1, 0)
              ((firstIndex :: rest).length, keepRank keep, rank cursor, 1, 0) →
            stanza env region b a later keep' isStart cursor' (firstIndex :: rest) = .ok s →
            ∃ lss, Each P (firstIndex :: rest) lss ∧ Step cursor s lss.join [] := by
          intro keep' cursor' st dec e
          obtain ⟨lss, he, st'⟩ := (ih _ dec).1 later keep' isStart cursor' _ s rfl e
          exact ⟨lss, he, by simpa using st.trans st'⟩
        have moved : empty cursor = false →
            stanza env region b a later keep isStart (moveCursor env region cursor) (firstIndex :: rest) = .ok s →
            ∃ lss, Each P (firstIndex :: rest) lss ∧ Step cursor s lss.join [] := fun e =>
          again keep _ (step_moveCursor env region cursor) (by
            apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
            exact I4_moveCursor_rank env region cursor (Or.inl e))
        have accepted : ∀ count problems,
            accept env region b a later keep isStart cursor (firstIndex :: rest) trials count problems = .ok s →
            ∃ lss, Each P (firstIndex :: rest) lss ∧ Step cursor s lss.join [] := fun count problems e =>
          (ih _ (by apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; omega)).2
            later keep isStart cursor _ trials count problems s rfl hc e
        dsimp only at h
        split at h
        · rename_i c
          split at h
          · exact again _ _ (step_addUnmet _ _) (by
              apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, c.1]) h
          · split at h
            · rename_i e; exact moved e h
            · rename_i e1 e2; simp_all
        · split at h
          · exact accepted _ _ h
          · split at h
            · rename_i e; exact moved e h
            · split at h
              · exact accepted _ _ h
              · split at h
                · cases h
                · rename_i next hn
                  obtain ⟨ls, hp, st⟩ := hf _ _ _ _ hn
                  obtain ⟨lss, he, st'⟩ := (ih _ (by apply Prod.Lex.left; simp)).1 later keep false next rest s rfl h
                  exact ⟨ls :: lss, ⟨hp, he⟩, by simpa [List.join] using st.trans st'⟩
  · intro later keep isStart cursor indices trials count problems s hm hc h
    subst hm
    rw [accept] at h
    split at h
    · cases h
    · rename_i h0
      split at h
      · cases h
      · rename_i placed hp
        obtain ⟨lp, hep, stp⟩ := verseChain_get b P hP trials cursor indices (count - 1) placed hc (by
          rw [← hp, getElem?_get?])
        rw [show count - 1 + 1 = count by omega] at hep
        have sw := stp.trans (step_unmet placed (placed.unmet ++ problems))
        dsimp only at h
        split at h
        · rename_i hr
          rw [take_of_drop_isEmpty indices count hr] at hep
          have held : ∀ (r : Nat) (l : Bool), Step cursor
              (if b.holds (indices.getLast?.getD 0) then b.hold (indices.getLast?.getD 0) r l
                (checkWaits { placed with unmet := placed.unmet ++ problems })
               else checkWaits { placed with unmet := placed.unmet ++ problems }) lp.join [] := by
            intro r l
            have sc := sw.trans (step_checkWaits _)
            split
            · simpa using sc.trans (hh _ _ _ _)
            · simpa using sc
          split at h
          · cases h
          · rename_i required linesOnly fits _
            split at h
            · injection h with h; subst h; exact ⟨lp, hep, held _ _⟩
            · generalize (if isStart = true then max 1 keep.first else 1) = q at h
              split at h
              · exact (ih _ (by
                  apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; omega)).2
                  later keep isStart cursor indices trials _ [] s rfl hc h
              · split at h
                · rename_i e
                  obtain ⟨lss, he, st'⟩ := (ih _ (by
                    apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
                    exact I4_moveCursor_rank env region cursor (Or.inl e))).1
                    later keep isStart _ indices s rfl h
                  exact ⟨lss, he, by simpa using (step_moveCursor env region cursor).trans st'⟩
                · injection h with h; subst h; exact ⟨lp, hep, held _ _⟩
        · rename_i hr
          have hne : indices.length ≠ 0 := by
            intro e; rw [List.length_eq_zero.mp e] at hr; simp [List.isEmpty] at hr
          obtain ⟨lr, her, str⟩ := (ih _ (by apply Prod.Lex.left; simp; omega)).1
            later keep false _ (indices.drop count) s rfl h
          refine ⟨lp ++ lr, ?_, ?_⟩
          · have := Each.append hep her; rwa [List.take_append_drop] at this
          · rw [join_append']; simpa using (sw.trans (step_moveCursor env region _)).trans str

/-- `tryVerses` places each verse line it takes whole, once and in order:
    each trial places the rows of its verse line composed at the cursor the
    trial before it leaves (`I5_tryVerses_lines`).  `stanza` places each
    verse line of the stanza once and in order, each by the rows of a trial
    or by the fallback. -/
theorem I5_stanza_lines (env : Env) (region : Region) (b : Beside) (a : StanzaArgs)
    (P : Nat → List Nat → Prop) (hP : ∀ c i, P i (lineIds (b.compose c i)))
    (hf : ∀ i later c s, a.fallback i later c = .ok s → ∃ ls, P i ls ∧ Step c s ls [])
    (hh : ∀ i r l s, Step s (b.hold i r l s) [] [])
    (later : List Nat) (keep : Keep) (isStart : Bool) (cursor : St) (indices : List Nat) (s : St)
    (h : stanza env region b a later keep isStart cursor indices = .ok s) :
    ∃ lss, Each P indices lss ∧ Step cursor s lss.join [] :=
  (stanza_accept_lines env region b a P hP hf hh _).1 later keep isStart cursor indices s rfl h

/-! ### Lines numbered on from the text placed

When the breaker and `compose` number each line after the text placed
before the cursor they compose at (`bUnitFirsts`, which counts the lines
and the wrapped figures placed), `parts`, `stanza` and `paragraphs` add
lines numbered on from the text at their cursor (`Counts`), whatever
columns they move through. -/

/-- From `c` to `s`, lines numbered on from the text at `c` are added, and
    no figures. -/
def Counts (c s : St) : Prop := ∃ n, Step c s (ids (text c).length n) []

theorem ids_length (s n : Nat) : (ids s n).length = n := by
  induction n generalizing s with
  | zero => rfl
  | succ n ih => simp [ids, ih]

theorem Counts.ofStep {c s : St} (h : Step c s [] []) : Counts c s := ⟨0, by simpa [ids] using h⟩

theorem Counts.refl (c : St) : Counts c c := Counts.ofStep (Step.refl c)

theorem Counts.trans {a b c : St} (h : Counts a b) (h' : Counts b c) : Counts a c := by
  obtain ⟨n, s⟩ := h
  obtain ⟨n', s'⟩ := h'
  have lb : (text b).length = (text a).length + n := by rw [s.1, List.length_append, ids_length]
  rw [lb] at s'
  exact ⟨n + n', by simpa [ids_append] using s.trans s'⟩

/-- `parts` adds lines numbered on from the text at its cursor, when the
    breaker numbers the lines it composes at a cursor on from the text
    there. -/
theorem parts_counts (env : Env) (region : Region) (breaker : St → Nat → Nat → List (Line × Nat)) (items lastWanted : Nat)
    (follows : St → Bool) (hold : St → St)
    (hb : ∀ a c t, lineIds ((breaker a c t).map (·.1)) = ids (text a).length (breaker a c t).length)
    (hh : ∀ s, Step s (hold s) [] []) :
    ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St) (s : St),
    parts env region breaker items lastWanted follows hold limit k isStart start before at' = .ok s → Counts at' s := by
  have key : ∀ m, ∀ (limit : Option Nat) (k : Keep) (isStart : Bool) (start before : Nat) (at' : St),
      (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) = m → ∀ s,
      parts env region breaker items lastWanted follows hold limit k isStart start before at' = .ok s →
      Counts at' s := by
    intro m
    induction m using lex4_wf.induction with
    | _ m ih =>
    intro limit k isStart start before at' hm0 s h
    subst hm0
    rw [parts] at h
    split at h
    · cases h
    · rename_i moved relaxed hm
      have a := trialWrap_moved_step env region limit k isStart at' _ moved relaxed hm
      have dec : lex4lt (items - start, keepRank relaxed, rank moved, limitRank none (breaker moved before start).length)
          (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
        apply Prod.Lex.right
        cases I4_trialWrap_moved env region limit k isStart at' _ moved relaxed hm with
        | inl l => exact Prod.Lex.left _ _ l
        | inr e => rw [e.1]; exact Prod.Lex.right _ (Prod.Lex.left _ _ e.2)
      exact (Counts.ofStep a).trans (ih _ dec none relaxed isStart start before moved rfl s h)
    · rename_i count placed relaxed hm
      have a := trialWrap_placed_step env region limit k isStart at' _ count placed relaxed hm
      rw [lineIds_take, hb, ids_take] at a
      have pc : Counts at' placed := ⟨_, a⟩
      have done : Counts at' (hold (checkWaits placed)) :=
        pc.trans (Counts.ofStep (by simpa using (step_checkWaits placed).trans (hh _)))
      have movePart : ∀ s, empty at' = false →
          parts env region breaker items lastWanted follows hold none k isStart start before (moveCursor env region at') = .ok s →
          Counts at' s := by
        intro s e3 e
        have dec : lex4lt (items - start, keepRank k, rank (moveCursor env region at'),
            limitRank none (breaker (moveCursor env region at') before start).length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
          apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
          exact I4_moveCursor_rank env region at' (Or.inl e3)
        exact (Counts.ofStep (step_moveCursor env region at')).trans (ih _ dec none k isStart start before _ rfl s e)
      have retry : ∀ s n, n < limitRank limit (breaker at' before start).length →
          parts env region breaker items lastWanted follows hold (some n) k isStart start before at' = .ok s →
          Counts at' s := by
        intro s n hn e
        have dec : lex4lt (items - start, keepRank k, rank at', limitRank (some n) (breaker at' before start).length)
            (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
          apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; exact hn
        exact ih _ dec (some n) k isStart start before at' rfl s e
      split at h
      · split at h
        · injection h with h; subst h; exact done
        · split at h
          · split at h
            · rename_i h2; exact retry s _ h2 h
            · cases h
          · split at h
            · rename_i h3; exact movePart s h3 h
            · injection h with h; subst h; exact done
      · split at h
        · rename_i h4
          have go : ∀ s, parts env region breaker items lastWanted follows hold none relaxed false
              (nextItem (breaker at' before start) count start) (before + count) (moveCursor env region placed) = .ok s →
              Counts at' s := by
            intro s e
            have dec : lex4lt (items - nextItem (breaker at' before start) count start, keepRank relaxed,
                rank (moveCursor env region placed), limitRank none (breaker (moveCursor env region placed) (before + count)
                  (nextItem (breaker at' before start) count start)).length)
                (items - start, keepRank k, rank at', limitRank limit (breaker at' before start).length) := by
              apply Prod.Lex.left; obtain ⟨_, _⟩ := h4; omega
            exact (pc.trans (Counts.ofStep (step_moveCursor env region placed))).trans
              (ih _ dec none relaxed false _ (before + count) _ rfl s e)
          split at h
          · split at h
            · split at h
              · rename_i h6; exact retry s _ h6 h
              · cases h
            · split at h
              · rename_i h7; exact movePart s h7 h
              · exact go s h
          · exact go s h
        · cases h
  intro limit k isStart start before at' s h
  exact key _ limit k isStart start before at' rfl s h

/-- Each trial of `tryVerses` adds lines numbered on from the text at its
    cursor, when `compose` numbers them so. -/
theorem verseChain_counts (b : Beside)
    (hP : ∀ c i, lineIds (b.compose c i) = ids (text c).length (b.compose c i).length) :
    ∀ (ts : List St) (c : St) (is : List Nat) (n : Nat) (t : St), VerseChain b c is ts → ts.get? n = some t →
    Counts c t
  | [], _, _, _, _, _, e => by simp at e
  | _ :: _, _, [], _, _, h, _ => h.elim
  | t0 :: ts, c, i :: is, 0, t, ⟨s, _⟩, e => by
    simp at e; subst e
    rw [hP] at s; exact ⟨_, s⟩
  | t0 :: ts, c, i :: is, n + 1, t, ⟨s, r⟩, e => by
    simp at e
    rw [hP] at s
    exact Counts.trans (⟨_, s⟩ : Counts c t0) (verseChain_counts b hP ts t0 is n t r e)

/-- `stanza` and `accept` add lines numbered on from the text at their
    cursor, when `compose` numbers the rows so, the fallback adds lines so
    and the hold of what follows places nothing. -/
theorem stanza_accept_counts (env : Env) (region : Region) (b : Beside) (a : StanzaArgs)
    (hP : ∀ c i, lineIds (b.compose c i) = ids (text c).length (b.compose c i).length)
    (hf : ∀ i later c s, a.fallback i later c = .ok s → Counts c s)
    (hh : ∀ i r l s, Step s (b.hold i r l s) [] []) : ∀ m,
    (∀ later keep isStart cursor indices s, (indices.length, keepRank keep, rank cursor, 1, 0) = m →
      stanza env region b a later keep isStart cursor indices = .ok s → Counts cursor s) ∧
    (∀ later keep isStart cursor indices trials count problems s, (indices.length, keepRank keep, rank cursor, 0, count) = m →
      VerseChain b cursor indices trials →
      accept env region b a later keep isStart cursor indices trials count problems = .ok s → Counts cursor s) := by
  intro m
  induction m using lex5_wf.induction with
  | _ m ih =>
  constructor
  · intro later keep isStart cursor indices s hm h
    subst hm
    cases indices with
    | nil =>
      simp only [stanza, Except.ok.injEq] at h; subst h
      exact Counts.ofStep (step_checkWaits cursor)
    | cons firstIndex rest =>
      rw [stanza] at h
      split at h
      · cases h
      · rename_i trials ht
        have hc := I5_tryVerses_lines env region b cursor _ trials ht
        have again : ∀ keep' cursor', Step cursor cursor' [] [] →
            lex5lt ((firstIndex :: rest).length, keepRank keep', rank cursor', 1, 0)
              ((firstIndex :: rest).length, keepRank keep, rank cursor, 1, 0) →
            stanza env region b a later keep' isStart cursor' (firstIndex :: rest) = .ok s → Counts cursor s := by
          intro keep' cursor' st dec e
          exact (Counts.ofStep st).trans ((ih _ dec).1 later keep' isStart cursor' _ s rfl e)
        have moved : empty cursor = false →
            stanza env region b a later keep isStart (moveCursor env region cursor) (firstIndex :: rest) = .ok s →
            Counts cursor s := fun e =>
          again keep _ (step_moveCursor env region cursor) (by
            apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
            exact I4_moveCursor_rank env region cursor (Or.inl e))
        have accepted : ∀ count problems,
            accept env region b a later keep isStart cursor (firstIndex :: rest) trials count problems = .ok s →
            Counts cursor s := fun count problems e =>
          (ih _ (by apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left; omega)).2
            later keep isStart cursor _ trials count problems s rfl hc e
        dsimp only at h
        split at h
        · rename_i c
          split at h
          · exact again _ _ (step_addUnmet _ _) (by
              apply Prod.Lex.right; apply Prod.Lex.left; simp [keepRank, c.1]) h
          · split at h
            · rename_i e; exact moved e h
            · rename_i e1 e2; simp_all
        · split at h
          · exact accepted _ _ h
          · split at h
            · rename_i e; exact moved e h
            · split at h
              · exact accepted _ _ h
              · split at h
                · cases h
                · rename_i next hn
                  exact (hf _ _ _ _ hn).trans ((ih _ (by apply Prod.Lex.left; simp)).1 later keep false next rest s rfl h)
  · intro later keep isStart cursor indices trials count problems s hm hc h
    subst hm
    rw [accept] at h
    split at h
    · cases h
    · rename_i h0
      split at h
      · cases h
      · rename_i placed hp
        have cp : Counts cursor placed :=
          verseChain_counts b hP trials cursor indices (count - 1) placed hc (by rw [← hp, getElem?_get?])
        have sw : Counts cursor { placed with unmet := placed.unmet ++ problems } :=
          cp.trans (Counts.ofStep (step_unmet placed _))
        dsimp only at h
        split at h
        · have held : ∀ (r : Nat) (l : Bool), Counts cursor
              (if b.holds (indices.getLast?.getD 0) then b.hold (indices.getLast?.getD 0) r l
                (checkWaits { placed with unmet := placed.unmet ++ problems })
               else checkWaits { placed with unmet := placed.unmet ++ problems }) := by
            intro r l
            have sc := sw.trans (Counts.ofStep (step_checkWaits _))
            split
            · exact sc.trans (Counts.ofStep (hh _ _ _ _))
            · exact sc
          split at h
          · cases h
          · rename_i required linesOnly fits _
            split at h
            · injection h with h; subst h; exact held _ _
            · generalize (if isStart = true then max 1 keep.first else 1) = q at h
              split at h
              · exact (ih _ (by
                  apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.right; omega)).2
                  later keep isStart cursor indices trials _ [] s rfl hc h
              · split at h
                · rename_i e
                  exact (Counts.ofStep (step_moveCursor env region cursor)).trans ((ih _ (by
                    apply Prod.Lex.right; apply Prod.Lex.right; apply Prod.Lex.left
                    exact I4_moveCursor_rank env region cursor (Or.inl e))).1
                    later keep isStart _ indices s rfl h)
                · injection h with h; subst h; exact held _ _
        · rename_i hr
          have hne : indices.length ≠ 0 := by
            intro e; rw [List.length_eq_zero.mp e] at hr; simp [List.isEmpty] at hr
          exact (sw.trans (Counts.ofStep (step_moveCursor env region _))).trans
            ((ih _ (by apply Prod.Lex.left; simp; omega)).1 later keep false _ (indices.drop count) s rfl h)

/-- `paragraphs` adds lines numbered on from the text at its cursor, when
    `compose` numbers the rows so, `ready` steps the controls without
    placing anything numbered otherwise, and `paragraph` and the fallback
    add lines so. -/
theorem I5_paragraphs_counts (env : Env) (region : Region) (b : Beside) (a : StanzaArgs) (p : Paras)
    (hP : ∀ c i, lineIds (b.compose c i) = ids (text c).length (b.compose c i).length)
    (hf : ∀ i later c s, a.fallback i later c = .ok s → Counts c s)
    (hh : ∀ i r l s, Step s (b.hold i r l s) [] [])
    (hr : ∀ prior index c rows s, p.ready prior index c rows = .ok s → Counts c s)
    (hp : ∀ index later c s, p.paragraph index later c = .ok s → Counts c s)
    (prior : Nat) (cursor : St) (indices : List Nat) (s : St)
    (h : paragraphs env region b a p prior cursor indices = .ok s) : Counts cursor s := by
  match indices with
  | [] => simp only [paragraphs, Except.ok.injEq] at h; subst h; exact Counts.refl _
  | index :: later =>
    rw [paragraphs] at h
    split at h
    · cases h
    · split at h
      · split at h
        · cases h
        · split at h
          · cases h
          · rename_i ready er
            split at h
            · cases h
            · rename_i next es
              exact ((hr _ _ _ _ _ er).trans
                ((stanza_accept_counts env region b a hP hf hh _).1 _ _ _ ready _ next rfl es)).trans
                (I5_paragraphs_counts env region b a p hP hf hh hr hp _ next _ s h)
      · split at h
        · cases h
        · rename_i ready er
          split at h
          · cases h
          · rename_i next en
            exact ((hr _ _ _ _ _ er).trans (hp _ _ _ _ en)).trans
              (I5_paragraphs_counts env region b a p hP hf hh hr hp index next later s h)
termination_by indices.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after b index later; omega)

/-! ### The same-column check of `tryVerses`

`tryVerses` accepts a trial that placed its verse line whole only when the
trial stayed in the column of the cursor.  The check never fails there: a
trial of `trialParagraphPartLimit` that places lines leaves the page and the
column of its cursor as they were, when the separator and the pitch of the
page are not negative.  `tryVersesAnyColumn` is `tryVerses` without the
check, and `tryVerses_column_check_unobservable` shows the two equal. -/

theorem putLineWithReserve_column (allow : Bool) (env : Env) (st s : St) (l : Line)
    (h : putLineWithReserve allow env st l = .ok s) : s.page = st.page ∧ s.column = st.column := by
  unfold putLineWithReserve at h
  split at h
  · cases h
  · split at h
    · split at h
      · cases h
      · injection h with h; subst h; exact ⟨rfl, rfl⟩
    · injection h with h; subst h; exact ⟨rfl, rfl⟩

theorem putHere_column (env : Env) (region : Region) (st s : St) (l : Line) (h : putHere env region st l = .ok s) :
    s.page = st.page ∧ s.column = st.column := by
  unfold putHere at h
  split at h
  · unfold putWrappedLine at h
    split at h
    · cases h
    · rename_i placed e
      injection h with h; subst h
      unfold putLine at e
      have a := putLineWithReserve_column false env _ placed l e
      exact a
  · exact putLineWithReserve_column false env st s l h

theorem putHereLines_column (env : Env) (region : Region) (st s : St) (ls : List Line)
    (h : putHereLines env region st ls = .ok s) : s.page = st.page ∧ s.column = st.column := by
  induction ls generalizing st with
  | nil => simp only [putHereLines, Except.ok.injEq] at h; subst h; exact ⟨rfl, rfl⟩
  | cons l ls ih =>
    unfold putHereLines at h
    split at h
    · cases h
    · rename_i s1 e
      have a := putHere_column env region st s1 l e
      have b := ih s1 h
      exact ⟨b.1.trans a.1, b.2.trans a.2⟩

/-- `fit` keeps the column where an empty column with a negative
    adjustment has room for the amount and a column that is not empty has
    room for it with the pending space. -/
theorem fit_same_column (env : Env) (st : St) (a : Int)
    (h2 : empty st = true → st.adjust < 0 → a ≤ room env st)
    (h5 : empty st = false → a + st.pending ≤ room env st) :
    (fit env st a).page = st.page ∧ (fit env st a).column = st.column := by
  unfold fit
  by_cases c1 : empty st = true ∧ a ≤ room env st
  · rw [if_pos c1]; exact ⟨rfl, rfl⟩
  rw [if_neg c1]
  by_cases c2 : empty st = true ∧ st.adjust < 0
  · exact absurd ⟨c2.1, h2 c2.1 c2.2⟩ c1
  rw [if_neg c2]
  by_cases c3 : a + st.pending ≤ room env st
  · rw [if_pos c3]; exact ⟨rfl, rfl⟩
  rw [if_neg c3]
  by_cases c4 : empty st = true
  · rw [if_pos c4]; exact ⟨rfl, rfl⟩
  · exact absurd (h5 (by simpa using c4)) c3

theorem notes_grow (env : Env) (hs : 0 ≤ env.separator) (hp : 0 ≤ env.pagePitch) (notes : Int) (l : Line)
    (c : Bool) : notes ≤ notes + (if c then env.separator else 0) + (noteLines l : Int) * env.pagePitch := by
  have : 0 ≤ (noteLines l : Int) * env.pagePitch := Int.mul_nonneg (Int.ofNat_nonneg _) hp
  cases c <;> simp <;> omega

theorem sumPitch_take_succ (env : Env) (l : Line) (ls : List Line) (n : Nat) :
    sumPitch env ((l :: ls).take (n + 1)) = env.pitchOf l.id + sumPitch env (ls.take n) := rfl

/-- The lines `fittingGo` counts fit under the limit with their notes. -/
theorem fittingGo_bound (env : Env) (hs : 0 ≤ env.separator) (hp : 0 ≤ env.pagePitch) (st : St) :
    ∀ (ls : List Line) (used notes : Int) (n : Nat), 0 < n → n ≤ fittingGo env st used notes ls →
      used + sumPitch env (ls.take n) + notes ≤ limit env st
  | [], _, _, n, h0, h => by simp [fittingGo] at h; omega
  | l :: ls, used, notes, n, h0, h => by
    unfold fittingGo at h
    dsimp only at h
    have q0 : 0 ≤ (noteLines l : Int) * env.pagePitch := Int.mul_nonneg (Int.ofNat_nonneg _) hp
    generalize (noteLines l : Int) * env.pagePitch = q at *
    match n, h0 with
    | m + 1, _ =>
      rw [sumPitch_take_succ]
      split at h <;> split at h <;> first
        | omega
        | (rename_i c
           cases m with
           | zero => simp only [List.take_zero, sumPitch, List.foldr]; omega
           | succ m' =>
             have ih := fittingGo_bound env hs hp st ls _ _ (m' + 1) (by omega) (Nat.le_of_succ_le_succ h)
             simp only [Nat.succ_eq_add_one] at *
             omega)

/-- The lines `fittingWrapGo` counts fit under the limit with their notes. -/
theorem fittingWrapGo_bound (env : Env) (hs : 0 ≤ env.separator) (hp : 0 ≤ env.pagePitch) (st : St) (e : Int) :
    ∀ (ls : List Line) (used notes : Int) (n : Nat), 0 < n → n ≤ fittingWrapGo env st e used notes ls →
      used + sumPitch env (ls.take n) + notes ≤ limit env st
  | [], _, _, n, h0, h => by simp [fittingWrapGo] at h; omega
  | l :: ls, used, notes, n, h0, h => by
    unfold fittingWrapGo at h
    dsimp only at h
    have q0 : 0 ≤ (noteLines l : Int) * env.pagePitch := Int.mul_nonneg (Int.ofNat_nonneg _) hp
    generalize (noteLines l : Int) * env.pagePitch = q at *
    have mx := Int.le_max_right e (used + env.pitchOf l.id)
    match n, h0 with
    | m + 1, _ =>
      rw [sumPitch_take_succ]
      split at h <;> split at h <;> first
        | omega
        | (rename_i c
           cases m with
           | zero => simp only [List.take_zero, sumPitch, List.foldr]; omega
           | succ m' =>
             have ih := fittingWrapGo_bound env hs hp st e ls _ _ (m' + 1) (by omega) (Nat.le_of_succ_le_succ h)
             simp only [Nat.succ_eq_add_one] at *
             omega)

/-- The lines `fittingHere` counts fit in the room of the column, after the
    pending space when the column is not empty. -/
theorem fittingHere_bound (env : Env) (hs : 0 ≤ env.separator) (hp : 0 ≤ env.pagePitch) (region : Region) (st : St)
    (rows : List Line) (n : Nat) (h0 : 0 < n) (h : n ≤ fittingHere env region st rows) :
    sumPitch env (rows.take n) + (if empty st then 0 else st.pending) ≤ room env st := by
  unfold fittingHere at h
  unfold room
  split at h
  · unfold fitting at h
    have := fittingGo_bound env hs hp st rows _ _ n h0 h
    generalize (if empty st = true then 0 else st.pending) = x at *
    omega
  · have := fittingWrapGo_bound env hs hp st _ rows _ _ n h0 h
    generalize (if empty st = true then 0 else st.pending) = x at *
    omega

theorem splitAtBreak_le (k : Keep) (start : Bool) (total count : Nat) : splitAtBreak k start total count ≤ count := by
  unfold splitAtBreak
  split
  · omega
  · split
    · omega
    · show (if start = true ∧ 0 < (if total - count < k.last then total - k.last else count) ∧
          (if total - count < k.last then total - k.last else count) < k.first then 0
          else (if total - count < k.last then total - k.last else count)) ≤ count
      by_cases h3 : total - count < k.last
      · rw [if_pos h3]; split <;> omega
      · rw [if_neg h3]; split <;> omega

theorem limited_le (limit : Option Nat) (n : Nat) : limited limit n ≤ n := by
  unfold limited; split <;> omega

/-- A trial of `trialParagraphPartLimit` after its first test that places
    lines leaves them in the column of its cursor. -/
theorem trialWrapRest_column (env : Env) (hs : 0 ≤ env.separator) (hp : 0 ≤ env.pagePitch) (region : Region)
    (limit : Option Nat) (k : Keep) (start : Bool) (st : St) (rows : List Line) (fid : Nat) (c : Nat) (next : St)
    (r : Keep) (h : trialWrapRest env region limit k start st rows fid = .ok (.placed c next r)) :
    next.page = st.page ∧ next.column = st.column := by
  unfold trialWrapRest at h
  have bound := fittingHere_bound env hs hp region st rows
  have sl := splitAtBreak_le k start rows.length (fittingHere env region st rows)
  have ll := limited_le limit (splitAtBreak k start rows.length (fittingHere env region st rows))
  dsimp only at h
  generalize fittingHere env region st rows = count at *
  generalize limited limit (splitAtBreak k start rows.length count) = sel at *
  split at h
  · simp at h
  · rename_i moved
    split at h
    · simp at h
    · rename_i placed e
      injection h with h; injection h with _ h2 _
      subst h2
      have hc := putHereLines_column env region _ placed _ e
      have tk : count = 0 ∨ (0 < (if sel = 0 then max 1 count else sel) ∧ (if sel = 0 then max 1 count else sel) ≤ count) := by
        by_cases c0 : count = 0
        · exact Or.inl c0
        · right; split <;> omega
      have fs := fit_same_column env st (sumPitch env (rows.take (if sel = 0 then max 1 count else sel)))
        (fun he ha => by
          rcases tk with c0 | ⟨t0, t1⟩
          · exact absurd (Or.inl ⟨he, ha, c0⟩) moved
          · have := bound _ t0 t1; simp only [he, if_true] at this; omega)
        (fun he => by
          rcases tk with c0 | ⟨t0, t1⟩
          · subst c0
            have : sel = 0 := by omega
            exact absurd (Or.inr ⟨this, by simp [he]⟩) moved
          · have := bound _ t0 t1; simp only [he] at this; simpa using this)
      exact ⟨hc.1.trans fs.1, hc.2.trans fs.2⟩

/-- A trial of `trialParagraphPartLimit` that places lines leaves them in
    the column of its cursor. -/
theorem trialWrap_placed_column (env : Env) (hs : 0 ≤ env.separator) (hp : 0 ≤ env.pagePitch) (region : Region)
    (limit : Option Nat) (k : Keep) (start : Bool) (st : St) (rows : List Line) (c : Nat) (next : St) (r : Keep)
    (h : trialWrap env region limit k start st rows = .ok (.placed c next r)) :
    next.page = st.page ∧ next.column = st.column := by
  unfold trialWrap at h
  split at h
  · cases h
  unfold trialWrapFrom at h
  split at h
  · injection h with h; injection h with _ h2 _; subst h2; exact ⟨rfl, rfl⟩
  · split at h
    · simp at h
    · split at h
      · split at h
        · have a := trialWrapRest_column env hs hp region limit _ start _ _ _ c next r h
          exact a
        · simp at h
      · exact trialWrapRest_column env hs hp region limit _ start _ _ _ c next r h

/-- `tryVerses` without the check that the trial stayed in the column of
    the cursor. -/
def tryVersesAnyColumn (env : Env) (region : Region) (b : Beside) (cursor : St) : List Nat → Except Failure (List St)
  | [] => .ok []
  | index :: later =>
    match trialWrap env region none ⟨1, 1, false⟩ true cursor (b.compose cursor index) with
    | .error e => .error e
    | .ok (.placed count placed _) =>
      if count = (b.compose cursor index).length then
        match tryVersesAnyColumn env region b placed later with
        | .error e => .error e
        | .ok rest => .ok (placed :: rest)
      else .ok []
    | .ok (.moved _ _) => .ok []

/-- The check of `tryVerses` that the trial stayed in the column of the
    cursor does not change what it returns, on every input whose separator
    and pitch of the page are not negative (`trialWrap_placed_column`). -/
theorem tryVerses_column_check_unobservable (env : Env) (hs : 0 ≤ env.separator) (hp : 0 ≤ env.pagePitch)
    (region : Region) (b : Beside) (cursor : St) (indices : List Nat) :
    tryVersesAnyColumn env region b cursor indices = tryVerses env region b cursor indices := by
  induction indices generalizing cursor with
  | nil => rfl
  | cons index later ih =>
    unfold tryVersesAnyColumn tryVerses
    cases hm : trialWrap env region none ⟨1, 1, false⟩ true cursor (b.compose cursor index) with
    | error e => rfl
    | ok part =>
      cases part with
      | moved _ _ => rfl
      | placed count placed relaxed =>
        have col := trialWrap_placed_column env hs hp region none _ true cursor _ count placed relaxed hm
        dsimp only
        by_cases hc : count = (b.compose cursor index).length
        · have hb : count = (b.compose cursor index).length ∧ placed.page = cursor.page ∧
              placed.column = cursor.column := ⟨hc, col.1, col.2⟩
          rw [if_pos hc, if_pos hb, ih placed]
        · rw [if_neg hc, if_neg (fun x => hc x.1)]

/-- `itemJobs` runs the figures at the front of `later` that belong to the
    item `key`, each once and in order, and leaves the figures after them:
    the last figure it returns is the last of those it ran (or `prior`),
    and the figures it leaves are `later` without them. -/
theorem I5_itemJobs_figures (j : Jobs) (key prior : Nat) (cursor : St) (later : List Nat)
    (r : (Nat × {l : List Nat // l.length ≤ later.length}) × St) (h : itemJobs j key prior cursor later = .ok r) :
    r.1.2.val = later.dropWhile (fun x => j.itemOf x = some key) ∧
      r.1.1 = (prior :: later.takeWhile (fun x => j.itemOf x = some key)).getLast (by simp) := by
  induction later generalizing prior cursor with
  | nil =>
    unfold itemJobs itemEnd at h
    split at h
    · cases h
    · injection h with h; subst h; simp [List.getLast]
  | cons next more ih =>
    unfold itemJobs at h
    by_cases hk : j.itemOf next = some key
    · rw [if_pos hk] at h
      split at h
      · cases h
      · rename_i c _
        split at h
        · cases h
        · rename_i last' left' hl' placed e
          injection h with h; subst h
          have ⟨a, b⟩ := ih next c _ e
          refine ⟨by simp only at a ⊢; rw [a]; simp [List.dropWhile, hk], ?_⟩
          simp only at b ⊢; rw [b]; simp [List.takeWhile, hk, List.getLast]
    · rw [if_neg hk] at h
      unfold itemEnd at h
      split at h
      · cases h
      · injection h with h; subst h
        simp [List.dropWhile, List.takeWhile, hk, List.getLast]

theorem dropWhile_length_le (f : Nat → Bool) (l : List Nat) : (l.dropWhile f).length ≤ l.length := by
  induction l with
  | nil => simp
  | cons x xs ih =>
    simp only [List.dropWhile_cons]
    split
    · simp only [List.length_cons]; omega
    · simp

/-- `retain` returns the value of one of the trials it runs. -/
def RetainOk (j : Jobs) : Prop :=
  ∀ {α : Type} (trial : St → Except Failure (α × St)) (at' : St) (r : α × St),
    j.retain trial at' = .ok r → ∃ s r', trial s = .ok r' ∧ r'.1 = r.1

/-- The groups of figures `jobsFrom` takes one call at a time: a figure in a
    retained list item with the later figures of its item at the front of
    the rest, or a figure alone. -/
def jobGroups (j : Jobs) (jobs : List Nat) : List (List Nat) :=
  match jobs with
  | [] => []
  | job :: rest =>
    match j.itemOf job with
    | some key =>
      (job :: rest.takeWhile (fun x => j.itemOf x = some key)) ::
        jobGroups j (rest.dropWhile (fun x => j.itemOf x = some key))
    | none => [job] :: jobGroups j rest
termination_by jobs.length
decreasing_by
  all_goals simp_wf
  · exact Nat.lt_succ_of_le (dropWhile_length_le _ _)

/-- Every figure is in one group, in the order of the input. -/
theorem I5_jobGroups_join (j : Jobs) (jobs : List Nat) : (jobGroups j jobs).join = jobs := by
  match jobs with
  | [] => rw [jobGroups]; rfl
  | job :: rest =>
    rw [jobGroups]
    split
    · rename_i key _
      simp only [List.join_cons, List.cons_append]
      rw [I5_jobGroups_join j (rest.dropWhile (fun x => j.itemOf x = some key)), takeWhile_dropWhile]
    · simp only [List.join_cons, List.singleton_append]
      rw [I5_jobGroups_join j rest]
termination_by jobs.length
decreasing_by
  all_goals simp_wf
  · exact Nat.lt_succ_of_le (dropWhile_length_le _ _)

/-- When `retain` returns the value of one of its trials, the trial of a
    figure in a retained list item runs the figures of its group
    (`I5_itemJobs_figures`), and `jobsFrom` goes on with the figures after
    the group, from its last figure. -/
theorem I5_jobsFrom_after_group (j : Jobs) (hr : RetainOk j) (prior done : Option Nat) (job key : Nat)
    (rest : List Nat) (ready : St) (lastJob : Nat) (left : List Nat) (hl : left.length ≤ rest.length) (pc : St)
    (h : j.retain (fun at' => match j.run prior done job at' with
      | .error e => .error e
      | .ok first => itemJobs j key job first rest) ready = .ok ((lastJob, ⟨left, hl⟩), pc)) :
    left = rest.dropWhile (fun x => j.itemOf x = some key) ∧
      lastJob = (job :: rest.takeWhile (fun x => j.itemOf x = some key)).getLast (by simp) := by
  obtain ⟨s, r', e, v⟩ := hr _ ready _ h
  split at e
  · cases e
  · rename_i first _
    have := I5_itemJobs_figures j key job first rest r' e
    rw [v] at this
    exact this

/-! ### The lines of `jobsFrom` and `itemJobs`

`jobsFrom` and `itemJobs` place no lines of their own: every line comes
from one call of `outside`, `run`, `itemRest` or `finish` (a piece,
`JobPiece`), and `retain` keeps the lines of one run of its trial.  The
pieces of one run of `jobsFrom` follow from the figures alone
(`jobPieces`).  Given what each piece places (`JobsLines`), the lines
`jobsFrom` places are those of its pieces, each piece once and in order
(`I5_jobsFrom_lines`); its runs are those of the figures, each once and in
order (`I5_jobPieces_runs`). -/

/-- One call that places lines in `jobsFrom` or `itemJobs`. -/
inductive JobPiece where
  | outside (prior done : Option Nat) (job : Nat)
  | run (prior done : Option Nat) (job : Nat)
  | rest (key prior : Nat)
  | finish (prior done : Option Nat)

/-- The figure of a run. -/
def JobPiece.job? : JobPiece → Option Nat
  | .run _ _ job => some job
  | _ => none

/-- The pieces of `itemJobs`: a run for each figure at the front of `later`
    in the item `key`, then the rest of the item. -/
def itemPieces (j : Jobs) (key prior : Nat) : List Nat → List JobPiece
  | next :: more =>
    if j.itemOf next = some key then .run (some prior) none next :: itemPieces j key next more
    else [.rest key prior]
  | [] => [.rest key prior]

/-- The last figure of a group. -/
def lastOf (job : Nat) (more : List Nat) : Nat := (job :: more).getLast (by simp)

/-- The pieces of `jobsFrom`: for a figure in a retained list item, the
    flows before the item, the run of the figure and the pieces of
    `itemJobs`; for another figure, its run; and the flows after the last
    figure. -/
def jobPieces (j : Jobs) (prior done : Option Nat) (jobs : List Nat) : List JobPiece :=
  match jobs with
  | [] => [.finish prior done]
  | job :: rest =>
    match j.itemOf job with
    | some key =>
      .outside prior done job :: .run prior done job :: itemPieces j key job rest ++
        jobPieces j (some (lastOf job (rest.takeWhile (fun x => j.itemOf x = some key)))) (some key)
          (rest.dropWhile (fun x => j.itemOf x = some key))
    | none => .run prior done job :: jobPieces j (some job) none rest
termination_by jobs.length
decreasing_by
  all_goals simp_wf
  · exact Nat.lt_succ_of_le (dropWhile_length_le _ _)

theorem fm_run (prior done : Option Nat) (job : Nat) (l : List JobPiece) :
    (JobPiece.run prior done job :: l).filterMap JobPiece.job? = job :: l.filterMap JobPiece.job? := rfl

theorem fm_outside (prior done : Option Nat) (job : Nat) (l : List JobPiece) :
    (JobPiece.outside prior done job :: l).filterMap JobPiece.job? = l.filterMap JobPiece.job? := rfl

theorem filterMap_app (f : JobPiece → Option Nat) (a b : List JobPiece) :
    (a ++ b).filterMap f = a.filterMap f ++ b.filterMap f := by
  induction a with
  | nil => rfl
  | cons x xs ih => simp only [List.cons_append, List.filterMap]; cases f x <;> simp [ih]

theorem itemPieces_runs (j : Jobs) (key prior : Nat) (later : List Nat) :
    (itemPieces j key prior later).filterMap JobPiece.job? = later.takeWhile (fun x => j.itemOf x = some key) := by
  induction later generalizing prior with
  | nil => rfl
  | cons next more ih =>
    by_cases hk : j.itemOf next = some key
    · simp [itemPieces, hk, List.filterMap, JobPiece.job?, ih, List.takeWhile]
    · simp [itemPieces, hk, List.filterMap, JobPiece.job?, List.takeWhile]

/-- The runs of the pieces of `jobsFrom` are those of the figures, each
    once and in order. -/
theorem I5_jobPieces_runs (j : Jobs) (prior done : Option Nat) (jobs : List Nat) :
    (jobPieces j prior done jobs).filterMap JobPiece.job? = jobs := by
  match jobs with
  | [] => rw [jobPieces]; rfl
  | job :: rest =>
    rw [jobPieces]
    split
    · rename_i key _
      rw [filterMap_app, fm_outside, fm_run, itemPieces_runs, I5_jobPieces_runs j _ _ (rest.dropWhile (fun x => j.itemOf x = some key)), List.cons_append, takeWhile_dropWhile]
    · rw [fm_run, I5_jobPieces_runs j _ _ rest]
termination_by jobs.length
decreasing_by
  all_goals simp_wf
  · exact Nat.lt_succ_of_le (dropWhile_length_le _ _)

/-- From `c` to `s` through the pieces, each with its lines: before a
    piece the cursor may move without placing anything (`retain` runs its
    trial at another cursor), the piece places its lines `ls` with
    `P piece at ls` at the cursor `at` it runs at, and after the last piece
    the cursor may move again. -/
def PieceChain (P : JobPiece → St → List Nat → Prop) : St → List JobPiece → List (List Nat) → St → Prop
  | c, [], [], s => Step c s [] []
  | c, p :: ps, ls :: lss, s => ∃ a b, Step c a [] [] ∧ P p a ls ∧ Step a b ls [] ∧ PieceChain P b ps lss s
  | _, _, _, _ => False

theorem PieceChain.step {P : JobPiece → St → List Nat → Prop} :
    ∀ {c s : St} {ps : List JobPiece} {lss : List (List Nat)}, PieceChain P c ps lss s → Step c s lss.join []
  | _, _, [], [], h => h
  | _, _, _ :: _, _ :: _, ⟨_, _, m, _, st, r⟩ => by
    simpa using (m.trans st).trans (PieceChain.step r)
  | _, _, [], _ :: _, h => h.elim
  | _, _, _ :: _, [], h => h.elim

theorem PieceChain.pre {P : JobPiece → St → List Nat → Prop} {c a : St} (m : Step c a [] []) :
    ∀ {s : St} {ps : List JobPiece} {lss : List (List Nat)}, PieceChain P a ps lss s → PieceChain P c ps lss s
  | _, [], [], h => by simpa using m.trans h
  | _, _ :: _, _ :: _, ⟨a', b, m', p, st, r⟩ => ⟨a', b, by simpa using m.trans m', p, st, r⟩
  | _, [], _ :: _, h => h.elim
  | _, _ :: _, [], h => h.elim

theorem PieceChain.append {P : JobPiece → St → List Nat → Prop} :
    ∀ {c s t : St} {ps qs : List JobPiece} {lss mss : List (List Nat)},
    PieceChain P c ps lss s → PieceChain P s qs mss t → PieceChain P c (ps ++ qs) (lss ++ mss) t
  | _, _, _, [], _, [], _, h, h' => PieceChain.pre h h'
  | _, _, _, _ :: _, _, _ :: _, _, ⟨a, b, m, p, st, r⟩, h' => ⟨a, b, m, p, st, PieceChain.append r h'⟩
  | _, _, _, [], _, _ :: _, _, h, _ => h.elim
  | _, _, _, _ :: _, _, [], _, h, _ => h.elim

theorem PieceChain.single {P : JobPiece → St → List Nat → Prop} {p : JobPiece} {c s : St} {ls : List Nat}
    (hp : P p c ls) (st : Step c s ls []) : PieceChain P c [p] [ls] s :=
  ⟨c, s, Step.refl c, hp, st, Step.refl s⟩

/-- What `jobsFrom` and `itemJobs` assume of their arguments: `outside`,
    `run`, `itemRest` and `finish` each place lines `ls` with `P piece at ls`
    and no figures, and `retain` returns the value of one run of its trial
    at a cursor it reaches without placing anything, the cursor of that run
    moved on without placing anything. -/
structure JobsLines (j : Jobs) (P : JobPiece → St → List Nat → Prop) : Prop where
  outside : ∀ prior done job c s, j.outside prior done job c = .ok s →
    ∃ ls, P (.outside prior done job) c ls ∧ Step c s ls []
  run : ∀ prior done job c s, j.run prior done job c = .ok s → ∃ ls, P (.run prior done job) c ls ∧ Step c s ls []
  itemRest : ∀ key prior c s, j.itemRest key prior c = .ok s → ∃ ls, P (.rest key prior) c ls ∧ Step c s ls []
  finish : ∀ prior done c s, j.finish prior done c = .ok s → ∃ ls, P (.finish prior done) c ls ∧ Step c s ls []
  retain : ∀ {α : Type} (trial : St → Except Failure (α × St)) (at' : St) (r : α × St), j.retain trial at' = .ok r →
    ∃ s r', trial s = .ok r' ∧ r'.1 = r.1 ∧ Step at' s [] [] ∧ Step r'.2 r.2 [] []

/-- `itemJobs` places the lines of its pieces, each once and in order. -/
theorem I5_itemJobs_lines (j : Jobs) (P : JobPiece → St → List Nat → Prop) (hj : JobsLines j P) (key : Nat) :
    ∀ (later : List Nat) (prior : Nat) (cursor : St) (r : (Nat × {l : List Nat // l.length ≤ later.length}) × St),
    itemJobs j key prior cursor later = .ok r → ∃ lss, PieceChain P cursor (itemPieces j key prior later) lss r.2
  | [], prior, cursor, r, h => by
    unfold itemJobs itemEnd at h
    split at h
    · cases h
    · rename_i final e
      injection h with h; subst h
      obtain ⟨ls, p, st⟩ := hj.itemRest _ _ _ _ e
      exact ⟨[ls], PieceChain.single p st⟩
  | next :: more, prior, cursor, r, h => by
    unfold itemJobs at h
    by_cases hk : j.itemOf next = some key
    · rw [if_pos hk] at h
      split at h
      · cases h
      · rename_i c e
        split at h
        · cases h
        · rename_i last' left' hl' placed e'
          injection h with h; subst h
          obtain ⟨ls, p, st⟩ := hj.run _ _ _ _ _ e
          obtain ⟨lss, ch⟩ := I5_itemJobs_lines j P hj key more next c _ e'
          refine ⟨ls :: lss, ?_⟩
          simp only [itemPieces, hk, if_true]
          exact ⟨cursor, c, Step.refl _, p, st, ch⟩
    · rw [if_neg hk] at h
      unfold itemEnd at h
      split at h
      · cases h
      · rename_i final e
        injection h with h; subst h
        obtain ⟨ls, p, st⟩ := hj.itemRest _ _ _ _ e
        refine ⟨[ls], ?_⟩
        simp only [itemPieces, hk, if_false]
        exact PieceChain.single p st

/-- `jobsFrom` places the lines of its pieces (`jobPieces`), each once and
    in order, under the premises `JobsLines` on its arguments. -/
theorem I5_jobsFrom_lines (j : Jobs) (P : JobPiece → St → List Nat → Prop) (hj : JobsLines j P)
    (prior done : Option Nat) (cursor s : St) (jobs : List Nat) (h : jobsFrom j prior done cursor jobs = .ok s) :
    ∃ lss, PieceChain P cursor (jobPieces j prior done jobs) lss s := by
  match jobs with
  | [] =>
    rw [jobsFrom] at h
    obtain ⟨ls, p, st⟩ := hj.finish _ _ _ _ h
    rw [jobPieces]
    exact ⟨[ls], PieceChain.single p st⟩
  | job :: rest =>
    rw [jobsFrom] at h
    rw [jobPieces]
    split at h
    · rename_i key _
      split at h
      · cases h
      · rename_i ready ho
        dsimp only at h
        split at h
        · cases h
        · rename_i lastJob left hl pc hr
          obtain ⟨lo, po, so⟩ := hj.outside _ _ _ _ _ ho
          obtain ⟨s0, r', ht, hv, m0, m1⟩ := hj.retain _ _ _ hr
          try simp only at ht
          split at ht
          · cases ht
          · rename_i first hrun
            obtain ⟨lr, pr, sr⟩ := hj.run _ _ _ _ _ hrun
            obtain ⟨li, ci⟩ := I5_itemJobs_lines j P hj key rest job first r' ht
            have fig := I5_itemJobs_figures j key job first rest r' ht
            rw [hv] at fig
            obtain ⟨lj, cj⟩ := I5_jobsFrom_lines j P hj (some lastJob) (some key) pc s left h
            simp only at fig
            rw [fig.1, fig.2] at cj
            refine ⟨lo :: lr :: (li ++ lj), ?_⟩
            refine ⟨cursor, ready, Step.refl _, po, so, s0, first, m0, pr, sr, ?_⟩
            exact PieceChain.append ci (PieceChain.pre m1 cj)
    · split at h
      · cases h
      · rename_i placed hrun
        obtain ⟨lr, pr, sr⟩ := hj.run _ _ _ _ _ hrun
        obtain ⟨lj, cj⟩ := I5_jobsFrom_lines j P hj (some job) none placed s rest h
        exact ⟨lr :: lj, cursor, placed, Step.refl _, pr, sr, cj⟩
termination_by jobs.length
decreasing_by
  all_goals simp_wf
  all_goals omega

theorem step_putReserved (env : Env) (reserve : Int) (st s : St) (ls : List Line)
    (h : putReserved env reserve st ls = .ok s) : Step st s (lineIds ls) [] := by
  induction ls generalizing st with
  | nil => simp only [putReserved, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons l ls ih =>
    unfold putReserved at h
    split at h
    · cases h
    · rename_i s1 e
      have a := step_putLine env true _ s1 l e
      have b := ih _ h
      have c := (((Step.same rfl rfl rfl).trans a).trans (Step.same rfl rfl rfl)).trans b
      simpa only [lineIds, List.map, List.nil_append, List.append_nil, List.singleton_append] using c

theorem step_putRepeated (env : Env) (st s : St) (ls : List Line) (h : putRepeated env st ls = .ok s) :
    Step st s [] [] := by
  induction ls generalizing st with
  | nil => simp only [putRepeated, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons l ls ih =>
    unfold putRepeated at h
    split at h
    · cases h
    · have a : Step st (putSlot st (env.pitchOf l.id) (.repeated l.id)) [] [] := by
        refine ⟨?_, ?_⟩
        · simp [text, putSlot, textSlots_append, textSlots]
        · simp [figs, putSlot, figSlots_append, figSlots]
      simpa using a.trans (ih _ h)

theorem step_tableAt (env : Env) (b : Int) (ls : List Line) (s : St) : Step s (tableAt env b ls s) [] [] :=
  step_fit env s _

def tableLt (a b : Nat × Nat × Nat × Nat × Nat) : Prop :=
  Prod.Lex (· < ·) (Prod.Lex (· < ·) (Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)))) a b

theorem table_wf : WellFounded tableLt :=
  (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel (Prod.lex Nat.lt_wfRel Nat.lt_wfRel)))).wf

theorem step_tableRowsGo (env : Env) (header caption : List Line) (below : Bool) (ident : Nat) :
    ∀ m (seeking passed : Bool) (start : Int) (st : St) (rows : List (List Line)),
      (rows.length, tableRowsRank passed st seeking) = m →
      ∀ s, tableRowsGo env header caption below ident seeking passed start st rows = .ok s →
      Step st s (lineIds rows.join ++ (if below then lineIds caption else [])) [] := by
  intro m
  induction m using table_wf.induction with
  | _ m ih =>
  intro seeking passed start st rows hm s h
  subst hm
  match rows with
  | [] =>
    rw [tableRowsGo] at h
    split at h
    · rename_i b; simpa [b, List.join] using step_putReserved env 0 st s caption h
    · rename_i b; injection h with h; subst h; simpa [b, List.join] using Step.refl st
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
        have a := (step_tableAt env 0 _ st).trans (step_putRepeated env _ withHeader header e)
        have b := ih _ dec false passed _ withHeader (row :: rest) rfl s h
        simpa using a.trans b
    · split at h
      · split at h
        · cases h
        · rename_i placed e
          have dec : tableLt (rest.length, tableRowsRank false placed false)
              ((row :: rest).length, tableRowsRank passed st seeking) := by
            apply Prod.Lex.left; simp
          have a := step_putReserved env _ st placed row e
          have b := ih _ dec false false start placed rest rfl s h
          have c := a.trans b
          simpa only [List.join, lineIds_append, List.append_assoc] using c
      · split at h
        · rename_i h2
          have dec : tableLt ((row :: rest).length, tableRowsRank passed (nextColumn env st) true)
              ((row :: rest).length, tableRowsRank passed st seeking) := by
            apply Prod.Lex.right; simp only [tableRowsRank]
            exact Prod.Lex.right _ (lex3_of_lex2 (I4_drain_rank env st ⟨seek_cond st h2.2, h2.1⟩))
          have b := ih _ dec true passed start _ (row :: rest) rfl s h
          simpa using (step_nextColumn env st).trans b
        · split at h
          · rename_i h3
            have dec : tableLt ((row :: rest).length, tableRowsRank true (nextColumn env st) true)
                ((row :: rest).length, tableRowsRank passed st seeking) := by
              apply Prod.Lex.right; simp only [tableRowsRank, h3]; exact Prod.Lex.left _ _ (by decide)
            have b := ih _ dec true true start _ (row :: rest) rfl s h
            simpa using (step_nextColumn env st).trans b
          · cases h

theorem step_tableCaption (env : Env) (below : Bool) (reserve : Int) (start s : St) (caption : List Line) (h : tableCaption env below reserve start caption = .ok s) :
    Step start s (if below then [] else lineIds caption) [] := by
  unfold tableCaption at h
  split at h
  · rename_i b; injection h with h; subst h; simpa [b] using Step.refl start
  · rename_i b; simpa [b] using step_putReserved env reserve start s caption h

theorem step_placeTableFrom (env : Env) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool) (firstPart : List Line)
    (s : St) (h : placeTableFrom env st ident before header rows caption below firstPart = .ok s) :
    Step st s (tableText header rows caption below) [] := by
  unfold placeTableFrom at h
  have sk := step_seek env (tableFits env before firstPart) st
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
        have a := (sk.trans (step_tableAt env before firstPart F)).trans (Step.same rfl rfl rfl)
        have b := step_tableCaption env below _ _ placed caption e1
        have c := step_putReserved env _ placed withHeader header e2
        have d := step_tableRowsGo env header caption below ident _ false false _ withHeader rows rfl s h
        have all := ((a.trans b).trans c).trans d
        unfold tableText
        cases below
        · simpa [List.append_assoc] using all
        · simpa [List.append_assoc] using all

theorem step_placeTable (env : Env) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool)
    (s : St) (h : placeTable env st ident before header rows caption below = .ok s) :
    Step st s (tableText header rows caption below) [] := by
  unfold placeTable at h
  split at h
  · cases h
  · exact step_placeTableFrom env st ident before header rows caption below _ s h

theorem take_of_le {α : Type} : ∀ (n : Nat) (ls : List α), ls.length ≤ n → ls.take n = ls
  | _, [], _ => by cases ‹Nat› <;> rfl
  | 0, _ :: _, h => by simp at h
  | n + 1, x :: xs, h => by simp only [List.take, List.cons.injEq, true_and]; exact take_of_le n xs (by simp at h; omega)

theorem step_putBoxPart (env : Env) (ident : Nat) (ready s : St) (origin b a : Int) (ls : List Line) (short : List Unmet) (h : putBoxPart env ident ready origin b a ls short = .ok s) :
    Step ready s (lineIds ls) [] := by
  unfold putBoxPart at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    have c := ((Step.same rfl rfl rfl).trans (step_putLines env false _ placed ls e)).trans (Step.same rfl rfl rfl)
    simpa only [List.nil_append, List.append_nil] using c

set_option linter.unusedVariables false in
theorem step_placeBoxedParagraph (env : Env) (ident : Nat) (fb fa : Int) (k : Keep) (start : Bool) (st : St) (ls : List Line) (s : St) (h : placeBoxedParagraph env ident fb fa k start st ls = .ok s) :
    Step st s (lineIds ls) [] := by
  match ls with
  | [] => simp only [placeBoxedParagraph, Except.ok.injEq] at h; subst h; exact Step.refl _
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
            have b := step_placeBoxedParagraph env ident fb fa _ start _ (first :: more) s h
            simpa using (step_addUnmet st _).trans b
          · rename_i h2
            have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) ((first :: more).length, keepRank k, rank (nextColumn env st))
                ((first :: more).length, keepRank k, rank st) := by
              apply Prod.Lex.right; apply Prod.Lex.right
              exact I4_nextColumn_rank env st (Or.inl (by simpa using h2))
            have b := step_placeBoxedParagraph env ident fb fa k start _ (first :: more) s h
            simpa using (step_nextColumn env st).trans b
        · split at h
          · rename_i h3
            have dec : Prod.Lex (· < ·) (Prod.Lex (· < ·) (· < ·)) ((first :: more).length, keepRank k, rank (nextColumn env st))
                ((first :: more).length, keepRank k, rank st) := by
              apply Prod.Lex.right; apply Prod.Lex.right; exact I4_nextColumn_rank env st (Or.inl h3.2)
            have b := step_placeBoxedParagraph env ident fb fa k start _ (first :: more) s h
            simpa using (step_nextColumn env st).trans b
          · split at h
            · cases h
            · rename_i finished e
              have a := (step_fit env st _).trans (step_putBoxPart env ident _ finished _ _ _ _ _ e)
              split at h
              · rename_i h4
                have b := step_placeBoxedParagraph env ident fb fa k false _ _ s h
                have all := (a.trans (step_nextColumn env _)).trans b
                rw [List.append_nil, List.nil_append, ← lineIds_append, List.take_append_drop] at all
                exact all
              · rename_i h4
                injection h with h; subst h
                rw [take_of_le _ (first :: more) ?_] at a
                · simpa using a
                · simp; omega
termination_by (ls.length, keepRank k, rank st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | assumption
    | (apply Prod.Lex.left; try simp only [List.length_drop, List.length_cons]
       exact Nat.sub_lt (Nat.succ_pos _) (boxCount_pos _ _))

theorem step_seal (o : BoxOpen) (st : St) : Step st (seal o st) [] [] := by
  cases o with
  | none => exact Step.refl st
  | some p => exact Step.same rfl rfl rfl

theorem step_reopen (env : Env) (ident : Nat) (fb fa : Int) (verse : List Line) (st : St) :
    Step st (reopen env ident fb fa verse st).1 [] [] := by
  unfold reopen
  split
  · split
    · exact Step.same rfl rfl rfl
    · exact Step.refl st
  · exact Step.refl st

theorem join_nonempty (vs : List (List Line)) : (nonemptyVerses vs).join = vs.join := by
  induction vs with
  | nil => rfl
  | cons v vs ih =>
    unfold nonemptyVerses at *
    cases v with
    | nil => exact ih
    | cons x xs => exact congrArg ((x :: xs) ++ ·) ih

theorem step_putUnits (env : Env) (m : BoxMaps) (st s : St) (first : Bool) (vs : List (List Line))
    (h : putUnits env m st first vs = .ok s) : Step st s (lineIds vs.join) [] := by
  induction vs generalizing st first with
  | nil => simp only [putUnits, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons v vs ih =>
    unfold putUnits at h
    dsimp only at h
    split at h
    · cases h
    · rename_i s1 e
      have a := step_putLines env false _ s1 v e
      have b := ih s1 false h
      simpa [List.join, lineIds_append] using ((Step.same rfl rfl rfl).trans a).trans b

theorem step_putStanzaPart (env : Env) (m : BoxMaps) (ident : Nat) (ready s : St) (origin b g a : Int)
    (vs : List (List Line)) (short : List Unmet) (h : putStanzaPart env m ident ready origin b g a vs short = .ok s) :
    Step ready s (lineIds vs.join) [] := by
  unfold putStanzaPart at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    have c := ((Step.same rfl rfl rfl).trans (step_putUnits env m _ placed true vs e)).trans (Step.same rfl rfl rfl)
    simpa only [List.nil_append, List.append_nil] using c

set_option linter.unusedVariables false in
theorem step_placeBoxedStanza (env : Env) (ident : Nat) (fb fa : Int) (m : BoxMaps) (k : Keep) (start : Bool)
    (relaxed : List Nat) (o : BoxOpen) (st : St) (vs : List (List Line)) (s : St)
    (h : placeBoxedStanza env ident fb fa m k start relaxed o st vs = .ok s) : Step st s (lineIds vs.join) [] := by
  match vs with
  | [] =>
    simp only [placeBoxedStanza, Except.ok.injEq] at h; subst h
    simpa [List.join, lineIds] using step_seal o st
  | v :: more =>
    rw [placeBoxedStanza] at h
    dsimp only at h
    split at h
    · rename_i h1
      have hne := h1.2
      have b := step_placeBoxedStanza env ident fb fa m k start relaxed none _ (v :: more) s h
      simpa using ((step_seal o st).trans (step_nextColumn env _)).trans b
    · split at h
      · rename_i h2
        have hk := h2.2.2.1
        have b := step_placeBoxedStanza env ident fb fa m _ start relaxed o _ (v :: more) s h
        simpa using (step_addUnmet st _).trans b
      · split at h
        · rename_i p hp
          have hp' : relaxFor m relaxed v = some p := by
            split at hp
            · exact hp
            · cases hp
          have b := step_placeBoxedStanza env ident fb fa m k start (p :: relaxed) o _ (v :: more) s h
          simpa using (step_addUnmet st _).trans b
        · split at h
          · split at h
            · cases h
            · rename_i placed e
              have a := step_placeBoxedParagraph env ident fb fa _ true st v placed e
              have b := step_placeBoxedStanza env ident fb fa m k false relaxed _ _ more s h
              simpa [List.join, lineIds_append] using (a.trans (step_reopen env ident fb fa v placed)).trans b
          · rename_i h3
            split at h
            · cases h
            · rename_i finished e
              have a := (step_fit env st _).trans (step_putStanzaPart env m ident _ finished _ _ _ _ _ _ e)
              split at h
              · have b := step_placeBoxedStanza env ident fb fa m k false relaxed none _ _ s h
                have all := (a.trans (step_nextColumn env _)).trans b
                simpa [join_take_drop] using all
              · rename_i h4
                injection h with h; subst h
                rw [take_of_le _ (v :: more) ?_] at a
                · simpa using a
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

theorem join_singletons (ls : List Line) : (ls.map (fun l => [l])).join = ls := by
  induction ls with
  | nil => rfl
  | cons l ls ih => simp [List.join, ih]

theorem nonempty_head_none (vs : List (List Line)) (h : (nonemptyVerses vs).join.head? = none) : vs.join = [] := by
  rw [← join_nonempty]
  cases e : (nonemptyVerses vs).join with
  | nil => rfl
  | cons x xs => rw [e] at h; cases h

/-- The units of a mixed box are the lines of its paragraphs and stanzas,
    in order, and it holds no figures. -/
theorem collectMixed_text : ∀ (body : List Flow) (p : Int) (gaps : List (Nat × Int)) (acc : List (List Line))
    (g : List (Nat × Int)) (us : List (List Line)), collectMixed p gaps acc body = some (g, us) →
    lineIds us.join = lineIds acc.reverse.join ++ sourceText body ∧ sourceFigs body = []
  | [], _, gaps, acc, g, us, h => by
    simp only [collectMixed, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨_, h⟩ := h; subst h; simp [sourceText, sourceFigs]
  | f :: rest, p, gaps, acc, g, us, h => by
    cases f with
    | space n =>
      simp only [collectMixed] at h
      obtain ⟨a, b⟩ := collectMixed_text rest _ _ _ g us h
      simp [sourceText, sourceFigs, flowText, flowFigs, a, b]
    | keepNext n =>
      simp only [collectMixed] at h
      obtain ⟨a, b⟩ := collectMixed_text rest _ _ _ g us h
      simp [sourceText, sourceFigs, flowText, flowFigs, a, b]
    | paragraph k ls =>
      simp only [collectMixed] at h
      split at h
      · rename_i e
        have z := nonempty_head_none _ e
        rw [join_singletons] at z; subst z
        obtain ⟨a, b⟩ := collectMixed_text rest _ _ _ g us h
        refine ⟨?_, by simp [sourceFigs, flowFigs, b]⟩
        rw [a]; simp [sourceText, flowText, lineIds]
      · obtain ⟨a, b⟩ := collectMixed_text rest _ _ _ g us h
        refine ⟨?_, by simp [sourceFigs, flowFigs, b]⟩
        rw [a]
        simp only [List.reverse_append, List.reverse_reverse, join_app, join_nonempty, join_singletons, lineIds_append,
          sourceText, flowText, List.append_assoc]
    | stanza k vs =>
      simp only [collectMixed] at h
      split at h
      · rename_i e
        have z := nonempty_head_none _ e
        obtain ⟨a, b⟩ := collectMixed_text rest _ _ _ g us h
        refine ⟨?_, by simp [sourceFigs, flowFigs, b]⟩
        rw [a]; simp [sourceText, flowText, lineIds, z]
      · obtain ⟨a, b⟩ := collectMixed_text rest _ _ _ g us h
        refine ⟨?_, by simp [sourceFigs, flowFigs, b]⟩
        rw [a]
        simp only [List.reverse_append, List.reverse_reverse, join_app, join_nonempty, lineIds_append,
          sourceText, flowText, List.append_assoc]
    | _ => simp [collectMixed] at h

/-- `placeFlow` one level below places each flow with its lines and figures. -/
def InnerOk (inner : Inner) : Prop :=
  (∀ env st f s, inner.flow env st f = .ok s → Step st s (flowText f) (flowFigs f)) ∧
  (∀ env st fs s, inner.all env st fs = .ok s → Step st s (sourceText fs) (sourceFigs fs))

theorem step_placeFlows (inner : Inner) (hi : InnerOk inner) (env : Env) (st s : St) (body : List Flow)
    (h : placeFlows inner env st body = .ok s) : Step st s (sourceText body) (sourceFigs body) := by
  induction body generalizing st with
  | nil => simp only [placeFlows, Except.ok.injEq] at h; subst h; simpa [sourceText, sourceFigs] using Step.refl st
  | cons f fs ih =>
    unfold placeFlows at h
    split at h
    · cases h
    · rename_i s1 e
      have a := hi.1 env st f s1 e
      have b := ih s1 h
      simpa [sourceText, sourceFigs] using a.trans b

theorem step_placeGeneric (inner : Inner) (hi : InnerOk inner) (env : Env) (st : St) (ident : Nat) (fb fa : Int)
    (body : List Flow) (s : St) (h : placeGeneric inner env st ident fb fa body = .ok s) :
    Step st s (sourceText body) (sourceFigs body) := by
  unfold placeGeneric at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · cases h
    · rename_i placed e
      injection h with h; subst h
      have b := step_placeFlows inner hi env _ placed body e
      have a : Step st { fit env st (genericMinimum env ident (bodyLines body)) with
          used := (fit env st (genericMinimum env ident (bodyLines body))).used +
            (genericExtra env ident fb fa (bodyLines body)).1 } [] [] :=
        (step_fit env st _).trans (Step.same rfl rfl rfl)
      simpa using (a.trans b).trans (Step.same rfl rfl rfl)

theorem step_placeBox (inner : Inner) (hi : InnerOk inner) (env : Env) (st : St) (ident : Nat) (fb fa : Int)
    (body : List Flow) (s : St) (h : placeBox inner env st ident fb fa body = .ok s) :
    Step st s (sourceText body) (sourceFigs body) := by
  unfold placeBox at h
  split at h
  · simpa [sourceText, flowText, sourceFigs, flowFigs] using step_placeBoxedParagraph env ident fb fa _ true st _ s h
  · have c := step_placeBoxedStanza env ident fb fa _ _ true [] none st _ s h
    rw [join_nonempty] at c
    simpa [sourceText, flowText, sourceFigs, flowFigs] using c
  · split at h
    · rename_i gaps units e
      obtain ⟨t, f⟩ := collectMixed_text body 0 [] [] gaps units e
      have c := step_placeBoxedStanza env ident fb fa _ _ true [] none st units s h
      rw [t] at c; rw [f]; simpa [lineIds] using c
    · exact step_placeGeneric inner hi env st ident fb fa body s h

theorem mem_append' {α : Type} {x : α} : ∀ {a b : List α}, x ∈ a ++ b → x ∈ a ∨ x ∈ b
  | [], _, m => Or.inr m
  | y :: ys, b, m => by
    cases m with
    | head => exact Or.inl (List.Mem.head _)
    | tail _ m => cases mem_append' m with
      | inl m => exact Or.inl (List.Mem.tail _ m)
      | inr m => exact Or.inr m

theorem step_adjustLines (env : Env) (n : Int) (st : St) :
    Step st (drainCarried env (adjustLines env n st)) [] [] :=
  let f := drainCarried_fields env (adjustLines env n st)
  Step.same f.1 f.2.1 f.2.2

set_option linter.unusedVariables false in
theorem step_settle (env : Env) (ids : List Nat) (st : St) : Step st (settle env ids st) [] [] := by
  rw [settle]
  split
  · rename_i h
    have dec := I4_settle_rank env st ⟨fun e => (by have := h.1; rw [e] at this; cases this), h.2⟩
    simpa using (step_nextColumn env st).trans (step_settle env ids (nextColumn env st))
  · exact Step.refl st
termination_by (waiting st, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

set_option linter.unusedVariables false in
theorem step_advanceUnit (env : Env) (u : PartUnit) (w : Nat × Nat) (st : St) :
    Step st (advanceUnit env u w st) [] [] := by
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
    simpa using (step_nextColumn env st).trans (step_advanceUnit env u w (nextColumn env st))
  · exact Step.refl st
termination_by (2 * w.1 + 2 - st.page, columnsLeft st)
decreasing_by
  all_goals simp_wf
  all_goals assumption

theorem step_nextUnit (env : Env) (u : PartUnit) (st : St) : Step st (nextUnit env u st) [] [] := by
  simpa using (step_nextColumn env st).trans (step_advanceUnit env u _ _)

theorem step_retain (env : Env) (u : PartUnit) (table : Bool) (ids : List Nat) (st : St)
    (compose : St → Except Failure St) (t g : List Nat) (hc : ∀ a s, compose a = .ok s → Step a s t g)
    (s : St) (h : retain env u table ids st compose = .ok s) : Step st s t g := by
  have tryOk : ∀ a s, retainTry env ids compose a = .ok s → Step a s t g := by
    intro a s e
    unfold retainTry at e
    split at e
    · cases e
    · rename_i s1 e1
      injection e with e; subst e
      simpa using (hc a s1 e1).trans (step_settle env ids s1)
  have rep : ∀ x, Step st x t g → Step st (addUnmet (.splitPart table u) x) t g := fun x hx => by
    simpa using hx.trans (step_addUnmet x _)
  have mv : ∀ m, retainTry env ids compose (nextUnit env u st) = .ok m → Step st m t g := fun m e => by
    simpa using (step_nextUnit env u st).trans (tryOk _ m e)
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
theorem step_acrossGo (env : Env) (header : List Line) (st : St) (gs : List (Bool × List Line)) (s : St)
    (h : acrossGo env header st gs = .ok s) : Step st s (lineIds (gs.map (·.2)).join) [] := by
  match gs with
  | [] => simp only [acrossGo, Except.ok.injEq] at h; subst h; simpa [lineIds] using Step.refl st
  | (isRow, ls) :: rest =>
    rw [acrossGo] at h
    split at h
    · split at h
      · cases h
      · rename_i placed e
        have a := step_putReserved env 0 st placed ls e
        have b := step_acrossGo env header placed rest s h
        simpa [List.join, lineIds_append] using a.trans b
    · rename_i hn
      split at h
      · split at h
        · cases h
        · rename_i withHeader e
          split at h
          · cases h
          · rename_i placed e2
            have a := (step_nextColumn env st).trans (step_putRepeated env _ withHeader header e)
            have m : Step withHeader (if tableNeed env withHeader true ls ≤ room env withHeader then withHeader
                else nextColumn env withHeader) [] [] := by
              split
              · exact Step.refl _
              · exact step_nextColumn env _
            have c := step_putReserved env 0 _ placed ls e2
            have b := step_acrossGo env header placed rest s h
            simpa [List.join, lineIds_append] using ((a.trans m).trans c).trans b
      · have dec : rank (nextColumn env st) < rank st := by
          apply I4_nextColumn_rank; left
          have := (not_or.1 hn).2; simpa using this
        have b := step_acrossGo env header (nextColumn env st) ((isRow, ls) :: rest) s h
        simpa using (step_nextColumn env st).trans b
termination_by (gs.length, rank st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; assumption)

theorem splitLast_append {α : Type} : ∀ xs : List α, (splitLast xs).1 ++ (splitLast xs).2 = xs
  | [] => rfl
  | [_] => rfl
  | x :: y :: zs => by
    have := splitLast_append (y :: zs)
    simp only [splitLast, List.cons_append, this]

theorem map_snd_join (rs : List (List Line)) : ((rs.map (fun r => (true, r))).map (·.2)) = rs := by
  induction rs with
  | nil => rfl
  | cons r rs ih => simp [ih]

theorem step_acrossTail (env : Env) (header lastRow caption : List Line) (placed s0 s : St)
    (h : acrossTail env header lastRow caption placed s0 = .ok s) : Step s0 s (lineIds lastRow ++ lineIds caption) [] := by
  unfold acrossTail at h
  split at h
  · cases h
  · rename_i rowPlaced e
    have r : Step s0 rowPlaced (lineIds lastRow) [] := by
      split at e
      · split at e
        · cases e
        · rename_i wh e1
          have a := step_putRepeated env _ wh header e1
          have b := step_acrossGo env header wh _ rowPlaced e
          simpa [lineIds] using a.trans b
      · have b := step_acrossGo env header s0 _ rowPlaced e
        split at b
        · simpa [lineIds] using b
        · rename_i ne
          have : lastRow = [] := Decidable.of_not_not ne
          subst this; simpa [lineIds] using b
    have m : Step rowPlaced (if tableNeed env rowPlaced true caption ≤ room env rowPlaced ∨ empty rowPlaced = true then rowPlaced
        else nextColumn env rowPlaced) [] [] := by
      split
      · exact Step.refl _
      · exact step_nextColumn env _
    have c := step_putReserved env 0 _ s caption h
    simpa using (r.trans m).trans c

theorem splitLast_ids (rows : List (List Line)) :
    lineIds (splitLast rows).1.join ++ lineIds (splitLast rows).2.join = lineIds rows.join := by
  rw [← lineIds_append, ← join_app, splitLast_append]

/-- The groups of `placeTableAcross` and the tail of a lower caption hold
    the lines of the table in the order of `tableText`. -/
theorem across_text (header : List Line) (rows : List (List Line)) (caption : List Line) (below : Bool) :
    lineIds (((if below = false ∧ caption ≠ [] then [(false, caption)] else []) ++
      (if header ≠ [] then [(false, header)] else []) ++
      (if below = true ∧ caption ≠ [] then (splitLast rows).1 else rows).map (fun r => (true, r))).map (·.2)).join ++
    (if below = true ∧ caption ≠ [] then lineIds (splitLast rows).2.join ++ lineIds caption else []) =
    tableText header rows caption below := by
  have sl := splitLast_ids rows
  have mc : ∀ rs : List (List Line), List.map ((fun x : Bool × List Line => x.snd) ∘ fun r => (true, r)) rs = rs := by
    intro rs; induction rs <;> simp_all
  cases below <;> by_cases hc : caption = [] <;> by_cases hh : header = [] <;>
    simp [hc, hh, tableText, List.map_append, join_app, lineIds_append, map_snd_join, lineIds, mc] at sl ⊢ <;>
    simp [← sl, List.append_assoc]

theorem step_placeTableAcross (env : Env) (u : PartUnit) (st : St) (ident : Nat) (before : Int) (header : List Line)
    (rows : List (List Line)) (caption : List Line) (below : Bool) (s : St)
    (h : placeTableAcross env u st ident before header rows caption below = .ok s) :
    Step st s (tableText header rows caption below) [] := by
  unfold placeTableAcross at h
  dsimp only at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · cases h
      · have st0 : Step st (if empty st = true then st else if before + st.pending ≤ room env st then
            { st with used := st.used + st.pending + before, pending := 0, blankActive := false, blankSpans := 0 }
            else nextColumn env st) [] [] := by
          split
          · exact Step.refl st
          · split
            · exact Step.same rfl rfl rfl
            · exact step_nextColumn env st
        split at h
        · cases h
        · rename_i placed e
          have a := st0.trans (step_acrossGo env header _ _ placed e)
          split at h
          · rename_i low
            have b := step_retain env u true _ placed _ _ []
              (fun a s e => step_acrossTail env header _ caption placed a s e) s h
            refine Step.text_eq ?_ (a.trans b)
            rw [← across_text header rows caption below]
            simp only [if_pos low, List.nil_append, List.append_nil]
          · rename_i low
            injection h with h; subst h
            refine Step.text_eq ?_ a
            rw [← across_text header rows caption below]
            simp only [if_neg low, List.nil_append, List.append_nil]

theorem step_placeFlow (inner : Inner) (hi : InnerOk inner) (env : Env) (st : St) (f : Flow) (s : St)
    (h : placeFlow inner env st f = .ok s) : Step st s (flowText f) (flowFigs f) := by
  cases f with
  | paragraph k ls => simpa [flowText, flowFigs] using step_placeLines env k true st ls s h
  | continued k ls => simpa [flowText, flowFigs] using step_placeLines env k false st ls s h
  | ruled r => simpa [flowText, flowFigs] using step_placeRuled inner env st r [] s h
  | space n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using Step.same rfl rfl rfl
  | blank n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using Step.same rfl rfl rfl
  | brk k =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_breakAt env k st
  | start k =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_sectionStart env k st
  | switchColumns c =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_switchColumns env c st
  | restoreColumns =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_restoreColumns env st
  | defTerm ls => simpa [flowText, flowFigs] using step_placeLines env _ true st ls s h
  | stanza k vs => simpa [flowText, flowFigs] using step_placeStanza env k true st vs s h
  | code c f k sp rows => simpa [flowText, flowFigs] using step_placeCode env c f k sp true st rows s h
  | wrapped i e ls => simpa [flowText, flowFigs] using step_placeWrapped env st i e ls s h
  | table i b header rows caption below =>
    simp only [placeFlow] at h
    split at h
    · simpa [flowText, flowFigs] using step_placeTableAcross env _ st i b header rows caption below s h
    · simpa [flowText, flowFigs] using step_placeTable env st i b header rows caption below s h
  | bookPart u ids body =>
    simpa [flowText, flowFigs] using step_retain env u false ids st _ _ _ (fun a s e => hi.2 _ a body s e) s h
  | boxed i b a body => simpa [flowText, flowFigs] using step_placeBox inner hi env st i b a body s h
  | heading recto extent ls =>
    simp only [placeFlow] at h
    have a : Step st (if recto = true then parityStart env (fun p => p % 2 == 1) st else st) [] [] := by
      split
      · exact step_parityStart env _ st
      · exact Step.refl st
    simpa [flowText, flowFigs] using a.trans (step_placeHeading env _ _ extent ls s h)
  | adjustLines n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_adjustLines env n st
  | noBreak =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_waitForPrior _ _ st
  | keepNext n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_waitForPrior _ _ st
  | noBreakLines n =>
    simp only [placeFlow] at h
    split at h
    · injection h with h; subst h; simpa [flowText, flowFigs] using Step.refl st
    · injection h with h; subst h; simpa [flowText, flowFigs] using step_waitForPrior _ _ st
  | needLines n =>
    simp only [placeFlow, Except.ok.injEq] at h; subst h
    have : Step st (if env.capacity < (n : Int) * env.pagePitch then addUnmet (.needLines n) st else st) [] [] := by
      split
      · exact step_addUnmet st _
      · exact Step.refl st
    simpa [flowText, flowFigs] using this.trans (step_judgeNeed env _ _)
  | pageFigure i =>
    simp only [placeFlow] at h
    split at h
    · rename_i c
      injection h with h; subst h
      simpa [flowText, flowFigs] using
        (step_putPageFigureSlot st env.capacity i c.1).trans (step_nextPage env _)
    · injection h with h; subst h
      exact ⟨by simp [text, flowText], by simp [figs, flowFigs, Waiting.id]⟩
  | figure i e =>
    simp only [placeFlow] at h
    split at h
    · cases h
    · split at h
      · injection h with h; subst h
        exact ⟨by simp [text, flowText], by simp [figs, flowFigs, Waiting.id]⟩
      · split at h
        · injection h with h; subst h
          exact ⟨by simp [text, flowText], by simp [figs, flowFigs, Waiting.id]⟩
        · rename_i nd _
          injection h with h; subst h
          have d0 : st.deferred = [] := Decidable.of_not_not nd
          simpa [flowText, flowFigs] using (step_fit env st e).trans
            (step_putFigureSlot _ e i (fit_deferred env st e d0))


theorem step_beforeOf (env : Env) (st : St) (flow : Flow) (rest : List Flow) :
    Step st (beforeOf env st flow rest) [] [] := by
  have a : Step st (if st.blankActive ∧ occupies flow ∧ empty st = false ∧
      room env st < min env.capacity (st.pending + env.firstNeed (decide (0 < st.notesUsed)) 1 (flow :: rest))
      then nextColumn env st else st) [] [] := by
    split
    · exact step_nextColumn env st
    · exact Step.refl st
  unfold beforeOf
  dsimp only
  split
  · exact a
  · simpa using a.trans (Step.same rfl rfl rfl)

theorem step_placeBody (inner : Inner) (hi : InnerOk inner) (env : Env) (b : St) (flow : Flow) (rest : List Flow) (s : St)
    (h : placeBody inner env b flow rest = .ok s) : Step b s (flowText flow) (flowFigs flow) := by
  unfold placeBody at h
  cases flow with
  | paragraph k ls =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact step_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h; simpa [flowText, flowFigs] using step_placeWithNext inner env k true b ls l f later s h
  | continued k ls =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact step_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h; simpa [flowText, flowFigs] using step_placeWithNext inner env k false b ls l f later s h
  | noBreak => simp only [Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_waitForPrior _ _ b
  | keepNext n => simp only [Except.ok.injEq] at h; subst h; simpa [flowText, flowFigs] using step_waitForPrior _ _ b
  | noBreakLines n =>
    simp only at h
    split at h
    · injection h with h; subst h; simpa [flowText, flowFigs] using step_waitForPrior _ _ b
    · exact step_placeFlow inner hi env b _ s h
  | ruled r => simpa [flowText, flowFigs] using step_placeRuledKeeping inner env b r rest s h
  | figure i e => exact step_placeFlow inner hi env b _ s h
  | pageFigure i => exact step_placeFlow inner hi env b _ s h
  | space n => exact step_placeFlow inner hi env b _ s h
  | blank n => exact step_placeFlow inner hi env b _ s h
  | brk k => exact step_placeFlow inner hi env b _ s h
  | needLines n => exact step_placeFlow inner hi env b _ s h
  | adjustLines n => exact step_placeFlow inner hi env b _ s h
  | start k => exact step_placeFlow inner hi env b _ s h
  | switchColumns c => exact step_placeFlow inner hi env b _ s h
  | restoreColumns => exact step_placeFlow inner hi env b _ s h
  | code c f k sp rows => exact step_placeFlow inner hi env b _ s h
  | wrapped i e ls => exact step_placeFlow inner hi env b _ s h
  | table i bf header rows caption below => exact step_placeFlow inner hi env b _ s h
  | boxed i bf a body => exact step_placeFlow inner hi env b _ s h
  | stanza k vs =>
    cases e : keepAhead rest with
    | none => simp only [e] at h; exact step_placeFlow inner hi env b _ s h
    | some p =>
      obtain ⟨l, f, later⟩ := p
      simp only [e] at h; simpa [flowText, flowFigs] using step_placeStanzaWithNext inner env k b vs l f later s h
  | defTerm ls =>
    simp only at h
    split at h
    · simpa [flowText, flowFigs] using step_placeLines env _ true _ ls s h
    · simpa [flowText, flowFigs] using (step_keepFollowing inner env false b _ ls rest).trans (step_placeLines env _ true _ ls s h)
  | bookPart u ids body => exact step_placeFlow inner hi env b _ s h
  | heading recto extent ls =>
    have a : Step b (if recto = true then parityStart env (fun p => p % 2 == 1) b
        else keepFollowing inner env true b extent ls rest) [] [] := by
      split
      · exact step_parityStart env _ b
      · exact step_keepFollowing inner env true b extent ls rest
    simpa [flowText, flowFigs] using a.trans (step_placeHeading env _ _ extent ls s h)

theorem step_placeNext (inner : Inner) (hi : InnerOk inner) (env : Env) (st : St) (flow : Flow) (rest : List Flow) (s : St)
    (h : placeNext inner env st flow rest = .ok s) : Step st s (flowText flow) (flowFigs flow) := by
  unfold placeNext at h
  split at h
  · cases h
  · rename_i p e
    injection h with h; subst h
    have a := (step_beforeOf env st flow rest).trans (step_placeBody inner hi env _ flow rest p e)
    have c : Step p (if occupies flow = true then checkWaits p else p) [] [] := by
      split
      · exact step_checkWaits p
      · exact Step.refl p
    simpa using a.trans c

theorem step_placeAll (inner : Inner) (hi : InnerOk inner) (env : Env) (st : St) (flows : List Flow) (s : St)
    (h : placeAll inner env st flows = .ok s) : Step st s (sourceText flows) (sourceFigs flows) := by
  induction flows generalizing st with
  | nil => simp only [placeAll, Except.ok.injEq] at h; subst h; exact Step.refl _
  | cons f fs ih =>
    simp only [placeAll] at h
    split at h
    · cases h
    · rename_i p e
      have a := step_placeNext inner hi env st f fs p e
      have b := ih p h
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

theorem mem_bind' {α β : Type} {g : α → List β} {x : α} {y : β} : ∀ {xs : List α}, x ∈ xs → y ∈ g x → y ∈ xs.bind g
  | _ :: ys, .head _, my => by rw [List.cons_bind]; exact mem_append_left' _ my
  | z :: _, .tail _ m, my => by rw [List.cons_bind]; exact mem_append_right' (g z) (mem_bind' m my)

/-- `placeFlow` at every level places each flow with its lines and figures. -/
theorem level_ok : ∀ n, InnerOk (level n)
  | 0 => ⟨fun _ _ _ _ h => by simp [level] at h, fun _ _ _ _ h => by simp [level] at h⟩
  | n + 1 => ⟨fun env st f s h => step_placeFlow (level n) (level_ok n) env st f s h,
      fun env st fs s h => step_placeAll (level n) (level_ok n) env st fs s h⟩

/-- Invariant 4: the free placement is a total function; every column
    loop ends (`I4_nextColumn_rank`, `I4_fit_moved`, `I4_drain_rank`). -/
theorem I4_paginate_ends (env : Env) (flows : List Flow) : ∃ r, paginate env flows = r := ⟨_, rfl⟩

/-- What `paginate` places, from the first column to the last column closed. -/
theorem paginate_step (env : Env) (flows : List Flow) (pages : List PageOut)
    (h : paginate env flows = .ok pages) :
    pagesText pages = sourceText flows ∧ pagesFigs pages = sourceFigs flows := by
  unfold paginate at h
  split at h
  · cases h
  · split at h
    · cases h
    · rename_i final e
      split at h
      · rename_i clean
        have a := (step_placeAll _ (level_ok _) env _ flows final e).trans (step_drainCarry env final)
        have d : (drainCarry env final).deferred = [] := by
          cases c : (drainCarry env final).deferred with
          | nil => rfl
          | cons _ _ => have c1 := clean.1; rw [c] at c1; cases c1
        have c := close_pages env (drainCarry env final)
        have t : text (initial env) = [] := rfl
        have f0 : figs (initial env) = [] := rfl
        obtain ⟨a1, a2⟩ := a
        rw [t, List.nil_append, List.append_nil] at a1
        rw [f0, List.nil_append, List.append_nil] at a2
        simp only [figs, d, List.map, List.append_nil] at a2
        split at h
        · rename_i r
          injection h with h; subst h
          rw [r] at c
          exact ⟨by rw [← a1, ← c.1]; rfl, by rw [← a2, ← c.2]; rfl⟩
        · injection h with h; subst h
          exact ⟨by rw [c.1, a1], by rw [c.2, a2]⟩
      · cases h

/-- Invariant 5: the lines of the paragraphs, definition terms, stanzas,
    code blocks, ruled blocks, tables (a header repeated in a later column
    aside), boxes and the lines beside wrapped figures, the
    first line of each heading and ruled heading, and each wrapped figure
    before its lines, are placed once each, in the order of the manuscript. -/
theorem I5_paginate_text (env : Env) (flows : List Flow) (pages : List PageOut)
    (h : paginate env flows = .ok pages) : pagesText pages = sourceText flows :=
  (paginate_step env flows pages h).1

/-- Invariant 5: the figures and the turned figures, those in boxes among
    them, are placed once each, in the order of the manuscript. -/
theorem I5_paginate_figures (env : Env) (flows : List Flow) (pages : List PageOut)
    (h : paginate env flows = .ok pages) : pagesFigs pages = sourceFigs flows :=
  (paginate_step env flows pages h).2


/-! ## The rule after of a ruled paragraph in the free placement (golem-driver ADR 0027) -/

theorem half_le (n : Int) (h : 0 ≤ n) : half n ≤ n := by
  unfold half
  match n, h with
  | .ofNat 0, _ => decide
  | .ofNat (k + 1), _ =>
    show Int.ofNat ((k + 1) / 2) ≤ Int.ofNat (k + 1)
    exact Int.ofNat_le.mpr (Nat.div_le_self _ _)

theorem fdiv_mul_le (a b : Int) (hb : 0 < b) (hq : 1 ≤ Int.fdiv a b) : Int.fdiv a b * b ≤ a := by
  match a, b, hb, hq with
  | Int.ofNat (k + 1), Int.ofNat n, _, _ =>
    rw [fdiv_nat]
    simp only [Int.ofNat_eq_coe]
    exact Int.ofNat_le.mpr (Nat.div_mul_le_self _ _)
  | Int.ofNat 0, Int.ofNat n, _, hq =>
    have : Int.fdiv (Int.ofNat 0) (Int.ofNat n) = 0 := by cases n <;> rfl
    rw [this] at hq; omega
  | Int.negSucc m, Int.ofNat (n + 1), _, hq =>
    have : Int.fdiv (Int.negSucc m) (Int.ofNat (n + 1)) = Int.negSucc (m / (n + 1)) := rfl
    rw [this] at hq; have := Int.negSucc_lt_zero (m / (n + 1)); omega
  | Int.negSucc m, Int.ofNat 0, hb, _ => simp at hb
  | _, Int.negSucc m, hb, _ => exact absurd hb (Int.not_lt.2 (Int.le_of_lt (Int.negSucc_lt_zero m)))

theorem splitNotes_parts_le : ∀ (c : Nat) (ns : List Note), partsLines (splitNotes c ns).1 ≤ c
  | c, [] => by rw [splitNotes_nil]; simp [partsLines]
  | c, n :: rest => by
    simp only [splitNotes]
    split
    · have := splitNotes_parts_le (c - n.lines) rest
      simp only [partsLines, List.foldr] at this ⊢
      omega
    · split
      · simp [partsLines]
      · simp [partsLines]

theorem splitNotes_parts_pos : ∀ (c : Nat) (ns : List Note), (∀ n ∈ ns, 0 < n.lines) →
    (splitNotes c ns).1 ≠ [] → 1 ≤ partsLines (splitNotes c ns).1
  | c, [], _, h => by rw [splitNotes_nil] at h; exact absurd rfl h
  | c, n :: rest, hp, h => by
    have p := hp n (List.mem_cons_self _ _)
    simp only [splitNotes] at h ⊢
    split
    · simp only [partsLines, List.foldr]; omega
    · split
      · simp only [partsLines, List.foldr]; omega
      · rename_i h1 h2; simp only [h1, h2, if_false] at h; exact absurd rfl h

theorem lineNotesUsed_le (env : Env) (st : St) (l : Line) (hp : 0 < env.pagePitch) (hn : ∀ n ∈ l.notes, 0 < n.lines)
    (hr : st.used + env.pitchOf l.id + st.notesUsed ≤ limit env st) :
    st.used + env.pitchOf l.id + lineNotesUsed env st l ≤ limit env st := by
  unfold lineNotesUsed
  by_cases he : (lineNotes env st l).1.isEmpty
  · rw [if_pos he]
    have : (lineNotes env st l).1 = [] := by
      revert he; cases (lineNotes env st l).1 <;> simp [List.isEmpty]
    rw [this]; simp only [partsLines, List.foldr]; omega
  · rw [if_neg he]
    have ne : (lineNotes env st l).1 ≠ [] := fun e => he (by rw [e]; rfl)
    unfold lineNotes at ne ⊢
    dsimp only at ne ⊢
    generalize hq : Int.fdiv (limit env st - st.used - env.pitchOf l.id - st.notesUsed - lineSep env st l) env.pagePitch = q
    rw [hq] at ne
    have le := splitNotes_parts_le (max 0 q).toNat l.notes
    have pos := splitNotes_parts_pos (max 0 q).toNat l.notes hn ne
    generalize partsLines (splitNotes (max 0 q).toNat l.notes).1 = m at le pos ⊢
    have q1 : 1 ≤ q := by
      have : 1 ≤ (max 0 q).toNat := Nat.le_trans pos le
      have := Int.toNat_of_nonneg (Int.le_max_left 0 q)
      omega
    have qm := fdiv_mul_le _ _ hp (by rw [hq]; exact q1)
    rw [hq] at qm
    have kq : ((max 0 q).toNat : Int) = q := by
      rw [Int.toNat_of_nonneg (Int.le_max_left 0 q)]; omega
    have : (m : Int) * env.pagePitch ≤ q * env.pagePitch := by
      rw [← kq]; exact Int.mul_le_mul_of_nonneg_right (Int.ofNat_le.mpr le) (Int.le_of_lt hp)
    omega

theorem putLine_room (allow : Bool) (env : Env) (st s : St) (l : Line) (hp : 0 < env.pagePitch)
    (hn : ∀ n ∈ l.notes, 0 < n.lines) (hr : st.used + env.pitchOf l.id + st.notesUsed ≤ limit env st)
    (h : putLineWithReserve allow env st l = .ok s) :
    s.used = st.used + env.pitchOf l.id ∧ s.used + s.notesUsed ≤ limit env st := by
  unfold putLineWithReserve at h
  split at h
  · cases h
  · split at h
    · split at h
      · cases h
      · rename_i c _ e
        exfalso
        have : noteLines l = 0 := by simp [noteLines, e]
        omega
    · injection h with h; subst h
      have := lineNotesUsed_le env st l hp hn hr
      refine ⟨rfl, ?_⟩
      show st.used + env.pitchOf l.id + lineNotesUsed env st l ≤ limit env st
      exact this

theorem putLinesKeeping_room (allow : Bool) (env : Env) (adj after : Int) (hp : 0 < env.pagePitch) :
    ∀ (ls : List Line) (st s : St), (∀ l ∈ ls, ∀ n ∈ l.notes, 0 < n.lines) →
    st.used + st.notesUsed + sumPitch env ls + after ≤ env.capacity + adj →
    putLinesKeeping allow env adj after st ls = .ok s → s.used + s.notesUsed + after ≤ env.capacity + adj
  | [], st, s, _, hr, h => by
    simp only [putLinesKeeping, Except.ok.injEq] at h; subst h
    simp only [sumPitch, List.foldr] at hr; omega
  | l :: ls, st, s, hn, hr, h => by
    unfold putLinesKeeping at h
    split at h
    · cases h
    · rename_i s1 e
      have sp : sumPitch env (l :: ls) = env.pitchOf l.id + sumPitch env ls := rfl
      obtain ⟨_, r⟩ := putLine_room allow env _ s1 l hp (hn l (List.mem_cons_self _ _))
        (by simp only [limit]; omega) e
      simp only [limit] at r
      exact putLinesKeeping_room allow env adj after hp ls s1 s (fun x hx => hn x (List.mem_cons_of_mem _ hx))
        (by omega) h

/-- A ruled paragraph placed from a state where its extent fits the room
    leaves its lines, the area of its rule after and its notes within the
    column. -/
theorem ruledPlaceAt_room (env : Env) (st : St) (r : Ruled) (first lastLine : Line) (later : List Flow)
    (ready p : St) (hp : 0 < env.pagePitch) (hn : ∀ l ∈ r.lines, ∀ n ∈ l.notes, 0 < n.lines)
    (hr : ruledExtent env st r first lastLine later ≤ room env ready)
    (h : ruledPlaceAt env st r first lastLine later ready = .ok p) :
    p.used + p.notesUsed ≤ limit env p := by
  unfold ruledPlaceAt at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    have := putLinesKeeping_room true env _ _ hp r.lines _ placed hn
      (by simp only [ruledExtent, room, limit] at hr ⊢; omega) e
    simp only [limit]; omega

theorem nextColumn_elsewhere (env : Env) (st : St) :
    (nextColumn env st).page ≠ st.page ∨ (nextColumn env st).column ≠ st.column := by
  have keep : ∀ O : St, (carryInto env (placeDeferredGo env O O.deferred)).page = O.page ∧
      (carryInto env (placeDeferredGo env O O.deferred)).column = O.column := by
    intro O
    obtain ⟨p1, p2, _⟩ := placeDeferredGo_fields env O O.deferred
    obtain ⟨c1, c2, _⟩ := carryInto_fields env (placeDeferredGo env O O.deferred)
    exact ⟨by rw [c1, p1], by rw [c2, p2]⟩
  unfold nextColumn placeDeferred
  obtain ⟨k1, k2⟩ := keep (opened env false st)
  rw [k1, k2]
  by_cases pe : st.columns ≤ st.column + 1
  · left
    have op : opened env false st = placeTurned env (fresh env false st) := by simp [opened, pe]
    rw [op]; unfold placeTurned
    have := placeTurnedGo_page env (fresh env false st) (fresh env false st).deferred
    have fp : (fresh env false st).page = st.page + 1 := by simp [fresh, pe]
    omega
  · right
    have op : opened env false st = fresh env false st := by simp [opened, pe]
    rw [op, fresh_inPage env st pe]; omega

/-- `fit` keeps the column only where the amount fits its room, or where
    the column is empty and its room shorter than the amount. -/
theorem fit_here_room (env : Env) (st : St) (a : Int)
    (h : (fit env st a).page = st.page ∧ (fit env st a).column = st.column) :
    a ≤ room env (fit env st a) ∨ (empty st = true ∧ room env st < a) := by
  unfold fit at h ⊢
  by_cases c1 : empty st = true ∧ a ≤ room env st
  · rw [if_pos c1]; left; simp only [dropAtTop, room, limit] at c1 ⊢; omega
  · rw [if_neg c1] at h ⊢
    by_cases c2 : empty st = true ∧ st.adjust < 0
    · right; exact ⟨c2.1, Int.not_le.mp (fun x => c1 ⟨c2.1, x⟩)⟩
    · rw [if_neg c2] at h ⊢
      by_cases c3 : a + st.pending ≤ room env st
      · rw [if_pos c3]; left; simp only [room, limit] at c3 ⊢; omega
      · rw [if_neg c3] at h ⊢
        by_cases c4 : empty st = true
        · right; exact ⟨c4, Int.not_le.mp (fun x => c1 ⟨c4, x⟩)⟩
        · rw [if_neg c4] at h
          exfalso
          rcases nextColumn_elsewhere env st with e | e
          · exact e h.1
          · exact e h.2

/-- What `ruledLinesHere` places lies within the column with its notes:
    it places the block only where its extent fits the room of the column
    `fit` keeps (PR #1150). -/
theorem ruledLinesHere_room (env : Env) (st : St) (r : Ruled) (later : List Flow) (p : St)
    (hp : 0 < env.pagePitch) (hn : ∀ l ∈ r.lines, ∀ n ∈ l.notes, 0 < n.lines)
    (h : ruledLinesHere env st r later = .ok (some p)) :
    p.used + p.notesUsed ≤ limit env p := by
  unfold ruledLinesHere at h
  split at h
  · rename_i first lastLine _ _ _
    split at h
    · cases h
    · split at h
      · rename_i hc
        split at h
        · cases h
        · rename_i s0 e
          injection h with h; injection h with h; subst h
          exact ruledPlaceAt_room env st r first lastLine later _ _ hp hn hc.2.2 e
      · cases h
  · cases h

/-- The rule after of a ruled paragraph at the end of the column
    (`ruleAfterEdge` with no outside, the flows after it not read) ends
    within the area counted after its last line: the pitch of that line and
    the extra after it. -/
theorem I3_ruleAfter_edge (env : Env) (r : Ruled) (lastLine : Line) (side : RuleSide) (ha : r.after = some side)
    (hi : 0 ≤ side.inner) :
    ruleAfterPos env r lastLine [] side + side.weight ≤ env.pitchOf lastLine.id + ruledAfterExtra env r lastLine [] := by
  simp only [ruleAfterPos, ruledAfterExtra, joiningNext, ha, ruledAfter, ruleAfterEdgeExtra]
  generalize env.pitchOf lastLine.id = p
  generalize env.faceOf lastLine.id = f
  have hE : side.inner + side.weight - (p - f - faceOffset p f) ≤ ruleAfterExtra p f side.inner side.weight := by
    unfold ruleAfterExtra; exact Int.le_max_right _ _
  simp only [if_false]
  split
  · omega
  · have := half_le (p + ruleAfterExtra p f side.inner side.weight - (faceOffset p f + f) - side.weight) (by omega)
    omega

/-- What `ruledHere` places: the block with the flows after it, when they
    are none, or begin with a ruled paragraph that takes its rule after
    into its area, or its rule after in the area of its own lies in the
    column (`ruleAfterInColumn`); or else the block with the column-end
    area of its own, the flows after it not read. -/
theorem hereOr_cases (b : Bool) (inside : Option St) (later : List Flow) (fb : Except Failure (Option St)) (p : St)
    (h : hereOr b inside later fb = .ok (some p)) : (inside = some p ∧ b = true) ∨ fb = .ok (some p) := by
  unfold hereOr at h
  split at h
  · rename_i c
    injection h with h
    simp only [Bool.and_eq_true] at c
    exact Or.inl ⟨h, c.1⟩
  · exact Or.inr h

theorem ruledHere_cases (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (p : St)
    (h : ruledHere inner env st r later = .ok (some p)) :
    (ruledLinesHere env st r later = .ok (some p)
      ∧ (later = [] ∨ joiningNext later = true ∨ ruleAfterFitsLast env r later p = true))
    ∨ ruledLinesHere env st r [] = .ok (some p) := by
  rw [ruledHere] at h
  split at h
  · cases h
  · rename_i inside e
    rcases hereOr_cases _ _ _ _ p h with ⟨hi, c1⟩ | h
    · subst hi
      refine Or.inl ⟨e, ?_⟩
      dsimp only at c1
      split at c1
      · rename_i he; exact Or.inl (by cases later with | nil => rfl | cons _ _ => cases he)
      · split at c1
        · rename_i hj; exact Or.inr (Or.inl hj)
        · exact Or.inr (Or.inr c1)
    · exact Or.inr h

/-- Each line of a ruled paragraph `ruledHere` places, and the notes of
    the lines, lie within the column (golem-driver ADR 0027, root ADR 0397
    I8): the used length only grows while the lines are put, and the state
    after the last line keeps the used length and the notes within the
    column. -/
theorem I3_ruledHere_in_column (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (p : St)
    (hp : 0 < env.pagePitch) (hn : ∀ l ∈ r.lines, ∀ n ∈ l.notes, 0 < n.lines)
    (h : ruledHere inner env st r later = .ok (some p)) :
    p.used + p.notesUsed ≤ limit env p := by
  rcases ruledHere_cases inner env st r later p h with ⟨e, _⟩ | e
  · exact ruledLinesHere_room env st r later p hp hn e
  · exact ruledLinesHere_room env st r [] p hp hn e

/-- The rule after of a ruled paragraph `ruledHere` places in the free
    placement (golem-driver ADR 0027, root ADR 0397 I8): it waits for the
    next block to share its area, or it ends within the column and above
    the notes of the column.  Each line of the block keeps the lines after
    it and the area of the rule after out of its notes (`putKeeping` of
    `ruledLinesPlan`), so a rule placed at the end of the column ends above
    the notes as well. -/
theorem I3_ruledHere_rule_after (inner : Inner) (env : Env) (st : St) (r : Ruled) (later : List Flow) (p : St)
    (side : RuleSide) (lastLine : Line) (ha : r.after = some side) (hl : r.lines.getLast? = some lastLine)
    (hi : 0 ≤ side.inner) (hp : 0 < env.pagePitch) (hn : ∀ l ∈ r.lines, ∀ n ∈ l.notes, 0 < n.lines)
    (h : ruledHere inner env st r later = .ok (some p)) :
    (ruledLinesHere env st r later = .ok (some p) ∧ joiningNext later = true)
    ∨ (∃ l', ruledLinesHere env st r l' = .ok (some p) ∧ joiningNext l' = false
      ∧ p.used - ruledAfterExtra env r lastLine l' - env.pitchOf lastLine.id
          + ruleAfterPos env r lastLine l' side + side.weight ≤ limit env p - p.notesUsed) := by
  have edge := I3_ruleAfter_edge env r lastLine side ha hi
  have atEdge : ruledLinesHere env st r [] = .ok (some p) →
      ∃ l', ruledLinesHere env st r l' = .ok (some p) ∧ joiningNext l' = false
        ∧ p.used - ruledAfterExtra env r lastLine l' - env.pitchOf lastLine.id
            + ruleAfterPos env r lastLine l' side + side.weight ≤ limit env p - p.notesUsed := by
    intro e
    refine ⟨[], e, rfl, ?_⟩
    have f := ruledLinesHere_room env st r [] p hp hn e
    omega
  rcases ruledHere_cases inner env st r later p h with ⟨e, c⟩ | e
  · by_cases hj : joiningNext later = true
    · exact Or.inl ⟨e, hj⟩
    · rcases c with c | c | c
      · subst c; exact Or.inr (atEdge e)
      · exact absurd c hj
      · refine Or.inr ⟨later, e, by simpa using hj, ?_⟩
        simp only [ruleAfterFitsLast, hl, ruleAfterFits, ha, decide_eq_true_eq] at c
        exact c
  · exact Or.inr (atEdge e)


/-! ## The rules of a ruled heading in the free placement (PR #1148, #1151, #1152)

Since PR #1148 a rule after waits to share its area only with a ruled
paragraph (`joiningNext`); before a ruled heading the paragraph draws its
own rule after (`endRule` of `ruledLinesPlan`, in the gap before the first
line of the heading).  Since PR #1151 the heading draws its rule before as
a ruled paragraph does (`headingBeforeGeom`): after a line with no space
and no rule after below it, in the gap between the faces; else at the
edge of its own area, outside the column only at the top of an empty
column at 0.  Since PR #1152 its rule after takes the gap before the next
line in the middle of a column, and the edge of the column otherwise
(`headingAfterGeom`).  Each rule lies in the column above the notes and
off the faces beside it; a paragraph's rule after and a heading's rule
before may still overlap (`ruledHeading_rules_overlap`). -/

theorem half_eq (n : Int) : half n = n / 2 := by
  unfold half
  match n with
  | .ofNat 0 => rfl
  | .ofNat (_ + 1) => rfl
  | .negSucc _ => rfl

theorem half_nonneg (n : Int) (h : 0 ≤ n) : 0 ≤ half n := by
  rw [half_eq]; omega

theorem headingBeforeExtra_eq (env : Env) (r : Ruled) (side : RuleSide) (l : Line)
    (hb : r.before = some side) (hl : r.lines.head? = some l) :
    headingBeforeExtra env r = ruleBeforeEdgeExtra (headingFirstPitch env r l) (env.faceOf l.id) side l.overhang := by
  unfold headingBeforeExtra headingFirstPitch
  rw [hb, hl]

/-- The rule before a ruled heading at the edge of its area: outside the
    column, wholly before the start of the area, when the side has an
    outside; else it starts at or after the start of the area and ends
    within the extra before the heading and the leading of its first line
    less its overhang. -/
theorem headingBeforePos_edge (env : Env) (r : Ruled) (side : RuleSide) (l : Line) (hi : 0 ≤ side.inner) :
    (side.outside.isSome ∧ headingBeforePos env r side l + side.weight ≤ 0 ∧
      headingBeforePos env r side l + side.weight
        ≤ faceOffset (headingFirstPitch env r l) (env.faceOf l.id) - l.overhang) ∨
    (0 ≤ headingBeforePos env r side l ∧
      headingBeforePos env r side l + side.weight
        ≤ ruleBeforeEdgeExtra (headingFirstPitch env r l) (env.faceOf l.id) side l.overhang
          + faceOffset (headingFirstPitch env r l) (env.faceOf l.id) - l.overhang) := by
  unfold headingBeforePos ruleBeforeEdgeExtra
  generalize headingFirstPitch env r l = p
  generalize env.faceOf l.id = f
  have hE : side.inner + side.weight + l.overhang - faceOffset p f ≤ ruleBeforeExtra p f side.inner side.weight l.overhang := by
    unfold ruleBeforeExtra; exact Int.le_max_right _ _
  simp only [half_eq]
  cases side.outside with
  | none =>
    dsimp only
    split <;> exact Or.inr ⟨by omega, by omega⟩
  | some available =>
    dsimp only
    repeat' split
    all_goals first
      | exact Or.inl ⟨rfl, by omega, by omega⟩
      | exact Or.inr ⟨by omega, by omega⟩

/-- The rule before in a face-to-face gap (`ruleBeforeGap`): it starts at
    or after the end of the face before and ends within the gap with its
    extra, less the overhang of the face after. -/
theorem ruleBeforeGapPos_bounds (gap : Int) (side : RuleSide) (overhang : Int) (hi : 0 ≤ side.inner) (ho : 0 ≤ side.outer) :
    0 ≤ ruleBeforeGapPos gap side overhang ∧
    ruleBeforeGapPos gap side overhang + side.weight ≤ gap + ruleGapExtra gap side overhang - overhang := by
  unfold ruleBeforeGapPos
  have hE : side.inner + side.weight + side.outer + overhang - gap ≤ ruleGapExtra gap side overhang := by
    unfold ruleGapExtra; exact Int.le_max_right _ _
  dsimp only
  rw [half_eq]
  split <;> constructor <;> omega

/-- `putRuledHeading` from a state whose room holds the extras and the
    extent: the heading's area ends at the used length it leaves, and that
    length and the notes lie within the column. -/
theorem putRuledHeading_room (env : Env) (ready s : St) (before after : Int) (ends : List Int) (firstId : Nat)
    (extent : Int) (ls : List Line) (hp : 0 < env.pagePitch) (hn : ∀ n ∈ notesOf ls, 0 < n.lines)
    (hr : before + extent + after ≤ room env ready)
    (h : putRuledHeading env ready before after ends firstId extent ls = .ok s) :
    s.used = ready.used + before + extent + after ∧ s.used + s.notesUsed ≤ limit env s := by
  unfold putRuledHeading at h
  split at h
  · cases h
  · rename_i placed e
    injection h with h; subst h
    unfold putHeading at e
    split at e
    · cases e
    · rename_i s1 e1
      injection e with e; subst e
      have pe : (headingEnv env firstId extent).pitchOf firstId = extent := by simp [headingEnv]
      have := putLine_room false (headingEnv env firstId extent) _ s1 ⟨firstId, notesOf ls, 0⟩ hp hn
        (by rw [pe]; simp only [room, limit, headingEnv] at hr ⊢; omega) e1
      rw [pe] at this
      simp only [limit, headingEnv] at this ⊢
      constructor <;> omega

/-- The two cases of `headingBeforeGeom`: in the gap after the line
    before, with no space pending; or at the edge of the heading's area,
    with the outside only at the top of an empty column at 0. -/
theorem headingBeforeGeom_cases (env : Env) (cur : St) (r : Ruled) (side : RuleSide) (l : Line) :
    (∃ priorAt priorId, lastLineSlot cur = some (priorAt, priorId) ∧ cur.pending = 0 ∧
      headingBeforeGeom env cur r side l =
        (ruleGapExtra (cur.used + faceOffset (headingFirstPitch env r l) (env.faceOf l.id)
            - (priorAt + faceOffset (env.pitchOf priorId) (env.faceOf priorId) + env.faceOf priorId)) side l.overhang,
          priorAt + faceOffset (env.pitchOf priorId) (env.faceOf priorId) + env.faceOf priorId
            + ruleBeforeGapPos (cur.used + faceOffset (headingFirstPitch env r l) (env.faceOf l.id)
                - (priorAt + faceOffset (env.pitchOf priorId) (env.faceOf priorId) + env.faceOf priorId)) side l.overhang
            - cur.used)) ∨
    (∃ side' : RuleSide, side'.inner = side.inner ∧ side'.weight = side.weight ∧
      (side'.outside.isSome → empty cur ∧ cur.used = 0) ∧
      headingBeforeGeom env cur r side l =
        (ruleBeforeEdgeExtra (headingFirstPitch env r l) (env.faceOf l.id) side' l.overhang, headingBeforePos env r side' l)) := by
  have edge : ∃ side' : RuleSide, side'.inner = side.inner ∧ side'.weight = side.weight ∧
      (side'.outside.isSome → empty cur ∧ cur.used = 0) ∧
      side' = (if empty cur ∧ cur.used = 0 then side else { side with outside := none }) := by
    by_cases c : empty cur ∧ cur.used = 0
    · exact ⟨side, rfl, rfl, fun _ => c, by rw [if_pos c]⟩
    · refine ⟨{ side with outside := none }, rfl, rfl, fun o => by simp at o, by rw [if_neg c]⟩
  obtain ⟨side', e1, e2, e3, e4⟩ := edge
  subst e4
  cases hs : lastLineSlot cur with
  | none =>
    right; refine ⟨_, e1, e2, e3, ?_⟩
    unfold headingBeforeGeom; simp only [hs]
  | some p =>
    obtain ⟨priorAt, priorId⟩ := p
    by_cases c : cur.pending = 0 ∧ cur.afterRules.all (fun a => decide (a < priorAt))
    · left; refine ⟨priorAt, priorId, rfl, c.1, ?_⟩
      unfold headingBeforeGeom; simp only [hs]; rw [if_pos c]
    · right; refine ⟨_, e1, e2, e3, ?_⟩
      unfold headingBeforeGeom; simp only [hs]; rw [if_neg c]

theorem ruleBeforeEdgeExtra_nonneg (pitch face : Int) (side : RuleSide) (overhang : Int) :
    0 ≤ ruleBeforeEdgeExtra pitch face side overhang := by
  unfold ruleBeforeEdgeExtra ruleBeforeExtra
  dsimp only
  repeat' split
  all_goals first
    | exact Int.le_refl 0
    | exact Int.le_max_left _ _

theorem ruleGapExtra_nonneg (gap : Int) (side : RuleSide) (overhang : Int) : 0 ≤ ruleGapExtra gap side overhang := by
  unfold ruleGapExtra; exact Int.le_max_left _ _

/-- `fit` that keeps the column leaves the used length as it was when no
    space is pending: it drops the space at the top of an empty column, or
    puts the pending space, which is 0. -/
theorem fit_here_used (env : Env) (st : St) (a : Int)
    (h : (fit env st a).page = st.page ∧ (fit env st a).column = st.column) (hp : st.pending = 0) :
    (fit env st a).used = st.used := by
  unfold fit at h ⊢
  by_cases c1 : empty st = true ∧ a ≤ room env st
  · rw [if_pos c1]; rfl
  · rw [if_neg c1] at h ⊢
    by_cases c2 : empty st = true ∧ st.adjust < 0
    · rw [if_pos c2] at h
      exfalso
      have := nextColumn_elsewhere env st
      simp only [dropAtTop] at h
      rcases this with e | e
      · exact e h.1
      · exact e h.2
    · rw [if_neg c2] at h ⊢
      by_cases c3 : a + st.pending ≤ room env st
      · rw [if_pos c3]; simp only [hp]; omega
      · rw [if_neg c3] at h ⊢
        by_cases c4 : empty st = true
        · rw [if_pos c4]; rfl
        · rw [if_neg c4] at h
          exfalso
          have := nextColumn_elsewhere env st
          simp only [dropAtTop] at h
          rcases this with e | e
          · exact e h.1
          · exact e h.2

/-- `headingReady` that keeps the column leaves the used length as it was
    when no space is pending: the column made shorter (`tallAt`) keeps it,
    and so does `fit` (`fit_here_used`). -/
theorem headingReady_here_used (env : Env) (hs : St) (firstId : Nat) (extent size : Int)
    (h : (headingReady env hs firstId extent size).page = hs.page ∧
      (headingReady env hs firstId extent size).column = hs.column) (hp : hs.pending = 0) :
    (headingReady env hs firstId extent size).used = hs.used := by
  unfold headingReady at h ⊢
  split
  · rfl
  · rename_i c
    rw [if_neg c] at h
    exact fit_here_used env hs size h hp

/-- The rule before a ruled heading placed from `ready`, with its geometry
    taken on `cur` (`beforeGeometry headingState`), lies off the heading's
    face and in the column above the notes; it starts after the face of
    the line before it, or at or after the start of the heading's area, or
    else it lies wholly above an empty column that starts at 0 (the
    outside of golem-driver ADR 0040).  `ready` is `headingReady` of `cur`
    in the same column, as `placeRuled` puts the heading
    (`headingReady_here_used`). -/
theorem I3_ruledHeading_rule_before (env : Env) (r : Ruled) (side : RuleSide) (l : Line) (cur ready s : St)
    (extent after size : Int) (ends : List Int) (hb : r.before = some side) (hl : r.lines.head? = some l)
    (hi : 0 ≤ side.inner) (ho : 0 ≤ side.outer) (hp : 0 < env.pagePitch)
    (hn : ∀ n ∈ notesOf r.lines, 0 < n.lines)
    (he : faceOffset (headingFirstPitch env r l) (env.faceOf l.id) - l.overhang ≤ extent)
    (hready : ready = headingReady env cur (headId r.lines) extent size)
    (hk : ready.page = cur.page ∧ ready.column = cur.column) (ha : 0 ≤ after)
    (hr : headingBeforeAt env cur r + extent + after ≤ room env ready)
    (h : putRuledHeading env ready (headingBeforeAt env cur r) after ends (headId r.lines) extent r.lines = .ok s) :
    ready.used + (headingBeforeGeom env cur r side l).2 + side.weight
      ≤ ready.used + headingBeforeAt env cur r + faceOffset (headingFirstPitch env r l) (env.faceOf l.id) - l.overhang ∧
    ready.used + (headingBeforeGeom env cur r side l).2 + side.weight ≤ limit env s - s.notesUsed ∧
    ((∃ priorAt priorId, lastLineSlot cur = some (priorAt, priorId) ∧
        priorAt + faceOffset (env.pitchOf priorId) (env.faceOf priorId) + env.faceOf priorId
          ≤ ready.used + (headingBeforeGeom env cur r side l).2) ∨
      ready.used ≤ ready.used + (headingBeforeGeom env cur r side l).2 ∨
      (empty cur ∧ cur.used = 0 ∧ ready.used + (headingBeforeGeom env cur r side l).2 + side.weight ≤ ready.used)) := by
  have hu : cur.pending = 0 → ready.used = cur.used := by
    intro hpend; subst hready; exact headingReady_here_used env cur _ _ _ hk hpend
  have room' := putRuledHeading_room env ready s _ _ _ _ extent r.lines hp hn hr h
  have hB : headingBeforeAt env cur r = (headingBeforeGeom env cur r side l).1 := by
    unfold headingBeforeAt; rw [hb, hl]
  rw [hB] at room' ⊢
  rcases headingBeforeGeom_cases env cur r side l with ⟨priorAt, priorId, hs, hpend, eq⟩ | ⟨side', e1, e2, e3, eq⟩
  · rw [eq] at room' ⊢
    dsimp only at room' ⊢
    have u := hu hpend
    have b := ruleBeforeGapPos_bounds (cur.used + faceOffset (headingFirstPitch env r l) (env.faceOf l.id)
      - (priorAt + faceOffset (env.pitchOf priorId) (env.faceOf priorId) + env.faceOf priorId)) side l.overhang hi ho
    refine ⟨by omega, by omega, Or.inl ⟨priorAt, priorId, hs, by omega⟩⟩
  · rw [eq] at room' ⊢
    dsimp only at room' ⊢
    have b := headingBeforePos_edge env r side' l (by rw [e1]; exact hi)
    have x := ruleBeforeEdgeExtra_nonneg (headingFirstPitch env r l) (env.faceOf l.id) side' l.overhang
    rw [e2] at b
    rcases b with ⟨o, b, b'⟩ | ⟨b1, b2⟩
    · exact ⟨by omega, by omega, Or.inr (Or.inr ⟨(e3 o).1, (e3 o).2, by omega⟩)⟩
    · exact ⟨by omega, by omega, Or.inr (Or.inl (by omega))⟩

/-- The rule after at the end of the column (`ruleAfterEdge` with no
    outside): it starts at or after the end of the face and ends within
    the pitch and the extra. -/
theorem ruleAfterEdgePos_bounds (pitch face : Int) (side : RuleSide) (hi : 0 ≤ side.inner) :
    faceOffset pitch face + face ≤ ruleAfterEdgePos pitch face side ∧
    ruleAfterEdgePos pitch face side + side.weight ≤ pitch + ruleAfterEdgeExtra pitch face { side with outside := none } := by
  unfold ruleAfterEdgePos ruleAfterEdgeExtra
  have hE : side.inner + side.weight - (pitch - face - faceOffset pitch face) ≤ ruleAfterExtra pitch face side.inner side.weight := by
    unfold ruleAfterExtra; exact Int.le_max_right _ _
  dsimp only
  rw [half_eq]
  split <;> constructor <;> omega

theorem headingLastFace_sum (env : Env) (r : Ruled) (extent : Int) (l : Line) :
    (headingLastFace env r extent l).1 + (headingLastFace env r extent l).2 = extent := by
  unfold headingLastFace
  split <;> (dsimp only; omega)

/-- The rule after a ruled heading (`headingAfterGeom`) starts at or after
    the end of the face of its last line; in the middle of a column it
    ends before the face of the next line less its overhang, which starts
    `gap` after that end and the extra, and at the end of the column it
    ends within the heading's box and the extra. -/
theorem headingAfterGeom_bounds (env : Env) (r : Ruled) (extent : Int) (later : List Flow) (interior : Bool)
    (side : RuleSide) (l : Line) (hi : 0 ≤ side.inner) (ho : 0 ≤ side.outer) :
    (headingLastFace env r extent l).1 ≤ (headingAfterGeom env r extent later interior side l).2 ∧
    ((∃ gap, interior = true ∧ headingNextGap env r extent l later = some gap ∧
        (headingAfterGeom env r extent later interior side l).2 + side.weight
          ≤ (headingLastFace env r extent l).1 + gap + (headingAfterGeom env r extent later interior side l).1
            - r.nextOverhang) ∨
      (headingAfterGeom env r extent later interior side l).2 + side.weight
        ≤ extent + (headingAfterGeom env r extent later interior side l).1) := by
  unfold headingAfterGeom
  dsimp only
  split
  · rename_i gap hg
    have hi' : interior = true ∧ headingNextGap env r extent l later = some gap := by
      cases interior
      · simp at hg
      · simpa using hg
    have hE : side.inner + side.weight + side.outer + r.nextOverhang - gap ≤ ruleGapExtra gap side r.nextOverhang := by
      unfold ruleGapExtra; exact Int.le_max_right _ _
    rw [half_eq]
    constructor
    · split <;> omega
    · left; refine ⟨gap, hi'.1, hi'.2, ?_⟩; split <;> omega
  · cases hb : env.headingBounds (headId r.lines) with
    | none =>
      have b := ruleAfterEdgePos_bounds (env.pitchOf l.id) (env.faceOf l.id) side hi
      have lf : headingLastFace env r extent l = (extent - env.pitchOf l.id + faceOffset (env.pitchOf l.id) (env.faceOf l.id)
          + env.faceOf l.id, env.pitchOf l.id - env.faceOf l.id - faceOffset (env.pitchOf l.id) (env.faceOf l.id)) := by
        unfold headingLastFace; rw [hb]
      rw [lf]
      dsimp only
      exact ⟨by omega, Or.inr (by omega)⟩
    | some bd =>
      obtain ⟨ffa, lfe⟩ := bd
      have lf : headingLastFace env r extent l = (lfe, extent - lfe) := by
        unfold headingLastFace; rw [hb]
      rw [lf]
      dsimp only
      have b := ruleAfterEdgePos_bounds (2 * (extent - lfe) + env.faceOf l.id) (env.faceOf l.id) side hi
      have fo : faceOffset (2 * (extent - lfe) + env.faceOf l.id) (env.faceOf l.id) = extent - lfe := by
        unfold faceOffset; rw [half_eq, half_eq]; omega
      exact ⟨by omega, Or.inr (by omega)⟩

/-- The rule after a ruled heading placed from `ready` with the extra
    `before` (`endRule` of `placeRuled`'s `RuledHeading`) lies off every
    face and in the column above the notes: it starts at or after the end
    of the face of the heading's last line; in the middle of a column it
    ends before the face of the next line (that line's box starts where the
    heading's area ends, `s.used`, and its face `gap - trailing` after),
    less the next line's overhang; at the end of the column it ends within
    the heading's area.  `placeRuled` keeps the interior rule only when it
    ends above the notes (`headingRuleFits`, `ruleAfterInColumn`). -/
theorem I3_ruledHeading_rule_after (env : Env) (r : Ruled) (side : RuleSide) (l : Line) (ready s : St)
    (extent before : Int) (later : List Flow) (interior : Bool)
    (ha : r.after = some side) (hl : r.lines.getLast? = some l) (hi : 0 ≤ side.inner) (ho : 0 ≤ side.outer)
    (hp : 0 < env.pagePitch) (hn : ∀ n ∈ notesOf r.lines, 0 < n.lines)
    (hr : before + extent + headingAfterAt env r extent later interior ≤ room env ready)
    (h : putRuledHeading env ready before (headingAfterAt env r extent later interior)
      (headingAfterRule env r extent later interior) (headId r.lines) extent r.lines = .ok s)
    (hf : interior = true → headingRuleFits env r extent later ready before s = true) :
    ready.used + before + (headingLastFace env r extent l).1
      ≤ ready.used + before + (headingAfterGeom env r extent later interior side l).2 ∧
    ready.used + before + (headingAfterGeom env r extent later interior side l).2 + side.weight
      ≤ limit env s - s.notesUsed ∧
    ((∃ gap, headingNextGap env r extent l later = some gap ∧
        ready.used + before + (headingAfterGeom env r extent later interior side l).2 + side.weight
          ≤ s.used + (gap - (headingLastFace env r extent l).2) - r.nextOverhang) ∨
      ready.used + before + (headingAfterGeom env r extent later interior side l).2 + side.weight ≤ s.used) ∧
    s.afterRules.getLast? = some (ready.used + before + (headingAfterGeom env r extent later interior side l).2) := by
  have room' := putRuledHeading_room env ready s _ _ _ _ extent r.lines hp hn hr h
  have hA : headingAfterAt env r extent later interior = (headingAfterGeom env r extent later interior side l).1 := by
    unfold headingAfterAt; rw [ha, hl]
  have rules : s.afterRules.getLast? = some (ready.used + before + (headingAfterGeom env r extent later interior side l).2) := by
    unfold putRuledHeading at h
    split at h
    · cases h
    · injection h with h; subst h
      have : headingAfterRule env r extent later interior = [(headingAfterGeom env r extent later interior side l).2] := by
        unfold headingAfterRule; rw [ha, hl]
      simp [this]
  rw [hA] at room'
  have sum := headingLastFace_sum env r extent l
  have b := headingAfterGeom_bounds env r extent later interior side l hi ho
  rcases b with ⟨b1, ⟨gap, hint, hg, b2⟩ | b2⟩
  · subst hint
    have fits := hf rfl
    unfold headingRuleFits at fits
    rw [ha, hl] at fits
    have fits := of_decide_eq_true fits
    exact ⟨by omega, by omega, Or.inl ⟨gap, hg, by omega⟩, rules⟩
  · exact ⟨by omega, by omega, Or.inr (by omega), rules⟩

/-- A ruled paragraph `ruledHere` places before a ruled heading: its rule
    after does not wait (a ruled heading shares no area), and it ends
    within the column above the notes. -/
theorem I3_ruledHere_heading_rule_after (inner : Inner) (env : Env) (st : St) (r h : Ruled) (rest : List Flow)
    (p : St) (side : RuleSide) (lastLine : Line) (hh : h.heading.isSome = true)
    (ha : r.after = some side) (hl : r.lines.getLast? = some lastLine)
    (hi : 0 ≤ side.inner) (hp : 0 < env.pagePitch) (hn : ∀ l ∈ r.lines, ∀ n ∈ l.notes, 0 < n.lines)
    (e : ruledHere inner env st r (.ruled h :: rest) = .ok (some p)) :
    ∃ l', ruledLinesHere env st r l' = .ok (some p)
      ∧ p.used - ruledAfterExtra env r lastLine l' - env.pitchOf lastLine.id
          + ruleAfterPos env r lastLine l' side + side.weight ≤ limit env p - p.notesUsed := by
  rcases I3_ruledHere_rule_after inner env st r _ p side lastLine ha hl hi hp hn e with ⟨_, j⟩ | ⟨l', e', _, b⟩
  · have : joiningNext (.ruled h :: rest) = false := by
      simp only [joiningNext]
      cases c : h.heading with
      | none => rw [c] at hh; cases hh
      | some _ => simp
    rw [this] at j; cases j
  · exact ⟨l', e', b⟩

/-- The column of `ruledHeading_rules_overlap`: lines of pitch 20 sp and
    face 10 sp, no heading bounds. -/
def overlapEnv : Env :=
  { pagePitch := 20, fontSize := 10, capacity := 200, maxCapacity := 220, separator := 0, columns := 1,
    firstLine := 0, pitchOf := fun _ => 20, faceOf := fun _ => 10, headingBounds := fun _ => none,
    wrappedBefore := fun _ => 0, boxPadding := fun _ => none, firstNeed := fun _ _ _ => 0,
    retention := none, held := fun _ => false }

/-- A centred rule of 4 sp with no spaces. -/
def overlapSide : RuleSide := ⟨0, 0, 4, false, none⟩
def overlapLine : Line := ⟨10, [], 0⟩
def overlapHeadingLine : Line := ⟨20, [], 0⟩
/-- The ruled paragraph of one line with a rule after. -/
def overlapParagraph : Ruled := ⟨1, none, some overlapSide, false, 0, defaultKeep, [overlapLine], none⟩
/-- The ruled heading of extent 20 sp with a rule before. -/
def overlapHeading : Ruled := ⟨2, some overlapSide, none, false, 0, defaultKeep, [overlapHeadingLine], some (false, 20)⟩

/-- The column of `ruledHeading_rules_overlap` after the paragraph of one
    line placed at 0: its rule after at `rule`, if any. -/
def overlapAfter (rules : List Int) : St :=
  { initial overlapEnv with slots := [(0, .line 10)], used := 20, afterRules := rules }

/-- The two rules still overlap after PR #1151: the paragraph's line is
    placed at 0, and its rule after (in the gap before the heading's first
    line, with no extra) runs from 18 to 22 sp; it lies below the start of
    the line, so the heading draws its rule before at the edge of its own
    area (`headingBeforeGeom`), with no extra: the heading starts at 20 sp
    and its rule before runs from 21 to 25 sp.  golem-layout's
    paginatePhysical places the two rules at 18 and 21 sp on this input
    (README.md). -/
theorem ruledHeading_rules_overlap :
    ruledAfterExtra overlapEnv overlapParagraph overlapLine [.ruled overlapHeading] = 0 ∧
    ruledAfterRules overlapEnv (initial overlapEnv) overlapParagraph overlapLine overlapLine
      [.ruled overlapHeading] 20 = [18] ∧
    headingBeforeExtra overlapEnv overlapHeading = 0 ∧
    headingBeforeGeom overlapEnv (overlapAfter [18]) overlapHeading overlapSide overlapHeadingLine = (0, 1) ∧
    (21 : Int) < 18 + overlapSide.weight := by
  decide

/-- The side of `ruledHeading_outside_rule_off_face`: a rule of 12 sp with
    no spaces that may go 20 sp out of the column. -/
def outsideSide : RuleSide := ⟨0, 0, 12, false, some 20⟩

/-- Before PR #1151 a ruled heading's rule before with an outside, after a
    plain line in the middle of a column, was counted outside the column
    and drawn inside its area over its face.  Now it lies in the gap
    between the faces: after the line placed at 0 (its face ends at 15 sp)
    the heading takes 2 sp of extra, so its face starts at 20 + 2 + 5 =
    27 sp, and the rule runs from 15 to 27 sp, off both faces.
    golem-layout's paginatePhysical places the heading at 22 sp and the
    rule at 15 sp on this input (README.md). -/
theorem ruledHeading_outside_rule_off_face :
    headingBeforeGeom overlapEnv (overlapAfter []) { overlapHeading with before := some outsideSide }
      outsideSide overlapHeadingLine = (2, -5) ∧
    (15 : Int) ≤ 20 + -5 ∧
    20 + -5 + outsideSide.weight ≤ 20 + 2
      + faceOffset (overlapEnv.pitchOf overlapHeadingLine.id) (overlapEnv.faceOf overlapHeadingLine.id) := by
  decide

end PhysicalPagination
