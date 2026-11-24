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

/-- `Pending` of State.hs: a forced break not applied yet, or the start of
    a section (`some` its id) or of a paragraph of a style with
    page-break (`none`). -/
inductive Pending where
  | brk (k : BreakKind)
  | start (sec : Option Nat) (k : BreakKind)
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

/-- `KeepParts` of golem-project: the unit a part is kept in. -/
inductive KeepParts where
  | column | page | spread
  deriving DecidableEq, Repr

/-- The body of a block with rules (`RuledBody` of Paginate/Types.hs): the
    lines of a paragraph, or a heading at a recto or not, its grid lines
    and its lines. -/
inductive RuledBody where
  | lines (kp : Keep) (lines : List Line)
  | heading (recto : Bool) (n : Nat) (lines : List Line)
  deriving Repr

/-- The flows of the grid mode modelled here (Paginate/Types.hs `FlowAt`). -/
inductive Flow where
  | paragraph (kp : Keep) (lines : List Line)
  | continued (kp : Keep) (lines : List Line)
  | heading (recto : Bool) (n : Nat) (lines : List Line)
  /-- A stanza of verse (`FStanza`): its keep and its verse lines, each of
      lines. -/
  | stanza (kp : Keep) (verses : List (List Line))
  | figure (id n : Nat)
  | pageFigure (id : Nat)
  /-- A figure with lines beside it (`FWrapped`): its id, its grid lines
      and the lines beside it. -/
  | wrapped (id n : Nat) (beside : List Line)
  | brk (k : BreakKind)
  /-- The start of a section or of a paragraph of a style with page-break
      (`FSection`). -/
  | sectionStart (sec : Option Nat) (k : BreakKind)
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
  /-- A no-break (`FNoBreak`): the flow after it starts in the column
      where the flow before it ended. -/
  | noBreak
  /-- A no-break of so many last lines (`FNoBreakLines`). -/
  | noBreakLines (n : Nat)
  /-- A keep-with-next of so many lines (`FKeepNext`), by the id of its
      span: the keep a visible separator is held by has the span of the
      separator (root ADR 0398 I7). -/
  | keepNext (n : Nat) (sp : Nat)
  /-- Another set of columns (`FSwitchColumns`), by its columns. -/
  | switchColumns (columns : Nat)
  /-- Back to the base set of columns (`FRestoreColumns`). -/
  | restoreColumns
  /-- The grid lines of the column changed by so many (`FAdjustLines`,
      `@page-lines`). -/
  | adjustLines (k : Int)
  /-- A book part (`FBookPart`): the unit it is kept in, its kind, the
      ids it retains in one unit and its flows. -/
  | bookPart (unit : KeepParts) (kind : Nat) (retained : List Nat) (body : List Flow)
  /-- Paragraphs in one box (`FBoxed`): its id, its grid lines before and
      after each part, and its flows. -/
  | boxed (id before after : Nat) (body : List Flow)
  /-- A paragraph or heading with rules (`FRuled`): its id, whether it has
      a rule before and a rule after, whether its rule before shares one
      area with the rule after of the block before (`frJoined`), and its
      body. -/
  | ruled (id : Nat) (before after joined : Bool) (body : RuledBody)
  deriving Repr

/-- `BoxAt` of State.hs: the box being placed, its grid lines before and
    after each part, the first grid line of its part in the column and
    whether that part started at the top of an empty column. -/
structure BoxAt where
  id : Nat
  before : Nat
  after : Nat
  start : Int
  top : Bool
  deriving Repr

inductive Slot where
  | line (id : Nat)
  | heading (id count : Nat)
  | figure (id : Nat)
  | pageFigure (id : Nat)
  /-- A figure with lines beside it (`SWrapped`), of no grid lines of its own. -/
  | wrapped (id : Nat)
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

/-- `AdjustLimit` of Paginate/Types.hs: why `@page-lines` was cut. -/
inductive AdjustLimit where
  | noRoom | linesPlaced | oneLine
  deriving DecidableEq, Repr

inductive Unmet where
  | needLines (n : Nat)
  | droppedBlank
  | tallHeading (id n : Nat) (free : Int)
  | unplaceableFootnote (id : Nat) (cap : Int)
  | splitKept (id : Nat)
  | shortFirst (id want got : Nat)
  | shortLast (id want got : Nat)
  | noBreak
  /-- `UnmetKeepNext`, by the id of the span of its keep-with-next. -/
  | keepNext (sp : Nat)
  /-- `UnmetAdjust`: the lines the column was changed by instead, and why. -/
  | adjust (got : Int) (limit : AdjustLimit)
  /-- `SplitBookPart`: a book part, by its kind, or the last row and the
      caption of a table (`none`), not kept in its unit. -/
  | splitBookPart (kind : Option Nat) (unit : KeepParts)
  deriving DecidableEq, Repr

/-- A note part: note id, first line, lines. -/
abbrev NotePart := Nat × Nat × Nat

/-- Where a placed rule is measured from (`PlacedRule` of Paginate/Types.hs,
    the places of RuleArea.hs): the start of the em box of its grid line at
    the start of a column (`ruleBeforeAtStart`, its outside allowed or not),
    or the end of the em box of its grid line inside a column (`ruleBefore`
    and `ruleAfter`), at the end of a column (`ruleAfterAtEnd`, its outside
    allowed or not), or in the area shared with the rule of the block
    named (`rulesJoined`, the rule after of the block before and the rule
    before of the block after). -/
inductive RuleEdge where
  | start (outside : Bool)
  | inside
  | atEnd (outside : Bool)
  | joinedAfter (next : Nat)
  | joinedBefore (prior : Nat)
  deriving DecidableEq, Repr

/-- A rule placed (`PlacedRule` of Paginate/Types.hs) by the id of its
    block and whether it is the rule before, on the grid: the grid line it
    is measured from, what it is measured from, and the grid lines of its
    area.  The area of a rule at the start of a column starts at its grid
    line, that of any other rule at the grid line after it. -/
structure PlacedRule where
  id : Nat
  before : Bool
  line : Int
  edge : RuleEdge
  area : Nat
  deriving DecidableEq, Repr

/-- The first grid line of the area of a rule. -/
def PlacedRule.first (r : PlacedRule) : Int :=
  match r.edge with
  | .start _ => r.line
  | _ => r.line + 1

structure PageOut where
  number : Nat
  column : Nat
  blank : Bool
  slots : List (Int × Slot)
  notes : List NotePart
  unmet : List Unmet
  /-- `poRules`: the rules placed in the column. -/
  rules : List PlacedRule

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
  breaks : List Pending
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
  /-- `sNoBreak`: the no-breaks and keep-with-nexts waiting for the next
      flow, with the page, the column and the slots before it, and the
      lines the column must take and whether only lines count. -/
  noBreak : List (Unmet × Nat × Nat × Nat × (Nat × Bool))
  /-- `csColumns (sSet st)`: the columns of the set in effect; its first
      line is `firstLine`. -/
  columns : Nat
  /-- `sBox`: the box being placed. -/
  box : Option BoxAt
  /-- `sSections`: the sections started and the page each opened. -/
  sections : List (Nat × Nat)
  /-- `sJoin`: the rule after of the block placed last, waiting to share
      its area with the rule before of the next block, by the block's id
      and its last grid line. -/
  join : Option (Nat × Int)
  /-- `sSetAdjust`: the grid lines `FAdjustLines` changes in every column
      of a set started on this page, against the type area (root ADR
      0441). -/
  setAdjust : Int
  /-- `sRules`: the rules placed in the column. -/
  rules : List PlacedRule

structure Need where
  grid : Nat
  notes : Nat

/-- `Env` of State.hs with the columns of the base set (`envBase`), and
    the values the model leaves open. -/
structure Env where
  /-- `envMaxLines`: the most grid lines a column may have after
      `FAdjustLines`. -/
  maxLines : Int
  capacity : Int
  separator : Int
  columns : Nat
  nextNeed : List Flow → Need
  fitting : St → List Line → Nat
  /-- `codeSpan` of Paginate/Types.hs: the grid lines of a part of a
      code block of the geometry and the rows given. -/
  codeSpan : Nat → Nat → Nat
  /-- `envKeepParts`: the unit the parts are kept in. -/
  keepParts : KeepParts
  /-- `envBookPartSpan` is `Just`: the flows are in a book part. -/
  inBookPart : Bool
  roomForLine : St → List Line → Bool
  /-- `keptNeed` of Decide.hs: what a paragraph before a no-break or a
      keep-with-next keeps its last lines with. -/
  keptNeed : List Flow → Option Need
  /-- The last lines requested by the controls ahead (the second of
      `keepAhead` of Decide.hs, 0 when there are none). -/
  keepLast : List Flow → Nat
  /-- `nextFirstLines` of Decide.hs. -/
  nextFirst : Nat → List Flow → Nat × Bool
  /-- The third of `keepAhead` of Decide.hs: the first lines a
      keep-with-next ahead requests, 0 when there is none. -/
  keepNextLines : List Flow → Nat
  /-- The grid lines of the area of a block's rule before inside the
      column (`ruleBefore`, and `ruleBeforeAtStart` at the top of the
      column, its outside allowed only on the page's first line, of
      RuleArea.hs), by the block's id. -/
  ruleBefore : Nat → Bool → Bool → Nat
  /-- `rulesJoined` of RuleArea.hs: the grid lines of the area shared by
      the rule after of the block before and the rule before of the
      block, by their ids. -/
  rulesJoined : Nat → Nat → Nat
  /-- `ruleAfter` of RuleArea.hs: the grid lines of the area of a
      block's rule after inside the column, by the block's id. -/
  ruleAfter : Nat → Nat
  /-- `ruleAfterAtEnd` of RuleArea.hs: the same at the end of the column,
      its outside allowed or not. -/
  ruleAfterAtEnd : Nat → Bool → Nat
  /-- `envHeld`: whether a keep-with-next, by the id of its span, is the
      keep of a visible separator (root ADR 0398 I7). -/
  held : Nat → Bool

/-- `envKeepParts env == KeepColumn`. -/
def Env.keepColumn (env : Env) : Bool := env.keepParts == .column

def initialState (env : Env) : St :=
  ⟨1, 0, 0, 0, 0, [], [], [], [], [], [], 0, none, none, [], 0, [], [], false, false, false, [], env.columns, none, [], none, 0, []⟩

/-! ## Queries of State.hs -/

def top (st : St) : Int := st.firstLine
/-- The grid lines after the part of the box being placed. -/
def boxAfter (st : St) : Int :=
  match st.box with
  | some b => b.after
  | none => 0
/-- `atBoxStart` of State.hs. -/
def atBoxStart (st : St) : Bool :=
  match st.box with
  | some b => st.used == b.start + b.before
  | none => false
def boxTop (st : St) : Bool :=
  match st.box with
  | some b => b.top
  | none => false
def cap (env : Env) (st : St) : Int := env.capacity + st.adjust - boxAfter st
def free (env : Env) (st : St) : Int := cap env st - st.used - st.noteLines
/-- `typeAreaFree` of State.hs: the grid lines left in the column for the
    columns of a set started after it, which end at the type area or above
    the footnotes of the column, whichever comes first (root ADR 0441). -/
def typeAreaFree (env : Env) (st : St) : Int := min env.capacity (env.capacity + st.adjust - st.noteLines) - st.used
def isEmpty (st : St) : Bool := st.notes.isEmpty && (st.used == top st || (boxTop st && atBoxStart st))
def addUnmet (u : Unmet) (st : St) : St := { st with unmet := st.unmet ++ [u] }

def noteLinesOf (ls : List Line) : Nat :=
  (ls.bind (·.notes)).foldr (fun n a => n.lines + a) 0

def needIn (env : Env) (st : St) (a b : Need) : Int :=
  let notes := a.notes + b.notes
  let sep : Int := if st.noteLines = 0 ∧ 0 < notes then env.separator else 0
  (a.grid : Int) + b.grid + notes + sep

/-! ## Operations of State.hs -/

def blankPage (_env : Env) (st : St) : St :=
  { st with done := ⟨st.page, 0, true, [], [], [], []⟩ :: st.done, page := st.page + 1 }

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
  else { st with done := ⟨st.page, st.column, false, st.slots, st.notes, st.unmet, st.rules⟩ :: st.done, unmet := [] }

def pageFigure (_env : Env) (st : St) (i : Nat) : St :=
  { st with done := ⟨st.page, 0, false, [(0, .pageFigure i)], [], [], []⟩ :: st.done, page := st.page + 1 }

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
    notes waiting are placed in it (`closed'` and `fresh` of `advanceIn`). -/
def advanceFresh (env : Env) (toPage : Bool) (st : St) : St :=
  let closed := closePage env st
  let written := closed.done.any (·.number == st.page)
  let closed' :=
    if toPage ∧ ¬written then { closed with done := ⟨st.page, 0, true, [], [], [], []⟩ :: closed.done }
    else closed
  let fresh : St :=
    { closed' with
      page := if toPage then st.page + 1 else st.page
      column := if toPage then 0 else st.column + 1
      firstLine := if toPage then 0 else st.firstLine
      reserved := if toPage then 0 else st.reserved
      adjust := if toPage then 0 else st.setAdjust
      setAdjust := if toPage then 0 else st.setAdjust
      used := if toPage then 0 else top st
      noteLines := if toPage then 0 else st.reserved
      slots := []
      notes := []
      pending := []
      spaces := []
      headingOnly := false
      join := none
      rules := [] }
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

/-- `openBox` of State.hs: a part of the box from here, its grid lines
    before taken at the top of a column too. -/
def openBox (st : St) : St :=
  match st.box with
  | none => st
  | some b =>
    let b' : BoxAt := { b with start := st.used, top := st.used == top st && st.notes.isEmpty }
    { st with box := some b', used := st.used + b.before }

/-- `advance` of State.hs before `openBox`; the part of the box in the
    column closed is recorded only in the output, not modelled. -/
def advanceIn (env : Env) (toPage : Bool) (st : St) : St :=
  let tw := advanceTurned toPage st
  openColumn env (advanceFresh env toPage st) tw.1 st.pending tw.2

/-- `startSet` of State.hs: the set starts at line `first` of the page,
    above the footnote lines already there; its columns end at the type
    area or above the footnotes of the column before, whichever comes
    first (root ADR 0030, root ADR 0441). -/
def startSet (env : Env) (st : St) (columns : Nat) (first : Int) : St :=
  { closePage env st with
    columns := columns
    firstLine := first
    column := 0
    adjust := min st.noteLines st.adjust
    setAdjust := min st.noteLines st.adjust
    used := first
    reserved := st.noteLines
    slots := []
    notes := []
    spaces := []
    headingOnly := false
    join := none
    rules := [] }

def advance (env : Env) (toPage : Bool) (st : St) : St := openBox (advanceIn env toPage st)

def nextColumn (env : Env) (st : St) : St := advance env (st.columns ≤ st.column + 1) st
def nextPage (env : Env) (st : St) : St := advance env true st

/-! ## The flows nested in book parts -/

mutual
/-- The weight of a flow: what the mutual recursion of `step`, `place`
    and `runFlows` decreases. -/
def flowWeight : Flow → Nat
  | .bookPart _ _ _ body => flowsWeight body + 1
  | .boxed _ _ _ body => flowsWeight body + 1
  | _ => 1
termination_by f => sizeOf f
def flowsWeight : List Flow → Nat
  | [] => 0
  | g :: r => flowWeight g + 1 + flowsWeight r
termination_by fs => sizeOf fs
end

theorem flowsWeight_append (a b : List Flow) : flowsWeight (a ++ b) = flowsWeight a + flowsWeight b := by
  induction a with
  | nil => simp [flowsWeight]
  | cons x xs ih => simp only [List.cons_append, flowsWeight, ih]; omega

/-- `flattenBookParts` of BookParts.hs. -/
def flattenParts : List Flow → List Flow
  | [] => []
  | .bookPart _ _ _ b :: r => flattenParts b ++ flattenParts r
  | .boxed i kb ka b :: r => .boxed i kb ka (flattenParts b) :: flattenParts r
  | f :: r => f :: flattenParts r
termination_by fs => sizeOf fs

theorem flattenParts_weight (fs : List Flow) : flowsWeight (flattenParts fs) ≤ flowsWeight fs := by
  match fs with
  | [] => simp [flattenParts, flowsWeight]
  | .bookPart u k i b :: r =>
    have := flattenParts_weight b; have := flattenParts_weight r
    simp only [flattenParts, flowsWeight_append, flowsWeight, flowWeight]; omega
  | f :: r =>
    have := flattenParts_weight r
    cases f with
    | bookPart u k i b =>
      have := flattenParts_weight b
      simp only [flattenParts, flowsWeight_append, flowsWeight, flowWeight]; omega
    | boxed j kb ka b =>
      have := flattenParts_weight b
      simp only [flattenParts, flowsWeight, flowWeight]; omega
    | _ => simp only [flattenParts, flowsWeight]; omega
termination_by sizeOf fs

mutual
/-- `flowSlotIds` of BookParts.hs. -/
def flowSlotIds : Flow → List Nat
  | .bookPart _ _ _ body | .boxed _ _ _ body => flowsSlotIds body
  | .paragraph _ ls | .continued _ ls | .defTerm ls => ls.map (·.id)
  | .stanza _ vs => vs.join.map (·.id)
  | .heading _ _ ls => (ls.take 1).map (·.id)
  | .figure i _ | .pageFigure i => [i]
  | .wrapped i _ beside => i :: beside.map (·.id)
  | .table _ h rows capt _ => (h ++ rows.join ++ capt).map (·.id)
  | .code _ _ _ _ rows => rows.map (·.id)
  | .ruled _ _ _ _ (.lines _ ls) => ls.map (·.id)
  | .ruled _ _ _ _ (.heading _ _ ls) => (ls.take 1).map (·.id)
  | _ => []
termination_by f => sizeOf f
def flowsSlotIds : List Flow → List Nat
  | [] => []
  | g :: r => flowSlotIds g ++ flowsSlotIds r
termination_by fs => sizeOf fs
end

mutual
/-- `hasNested` of `placeBookPart`: a book part, or a box with one in it. -/
def hasNested : Flow → Bool
  | .bookPart .. => true
  | .boxed _ _ _ body => anyNested body
  | _ => false
termination_by f => sizeOf f
def anyNested : List Flow → Bool
  | [] => false
  | g :: r => hasNested g || anyNested r
termination_by fs => sizeOf fs
end

/-! ## The rank of the loops -/

def noteWeight (p : NotePart) : Nat := p.2.2 + 1
def pendingWeight : List NotePart → Nat
  | [] => 0
  | p :: ps => noteWeight p + pendingWeight ps

/-- What waits: the figures sent on and the lines of the continued notes. -/
def waiting (st : St) : Nat := st.deferred.length + pendingWeight st.pending
def columnsLeft (_env : Env) (st : St) : Nat := st.columns - (st.column + 1)
/-- A column made shorter: the columns left on the page and 2 when every
    column of the set is (`setAdjust < 0`), as the next one is too, or 1
    when this column alone is. -/
def adjustRank (env : Env) (st : St) : Nat :=
  if st.setAdjust < 0 then columnsLeft env st + 2 else if st.adjust < 0 then 1 else 0
def fullRank (st : St) : Nat := if isEmpty st then 0 else 1

def rank (env : Env) (st : St) : Nat × Nat × Nat × Nat :=
  (waiting st, adjustRank env st, fullRank st, columnsLeft env st)

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

theorem carryNote_join (env : Env) (st : St) (p : NotePart) : (carryNote env st p).join = st.join := by
  simp only [carryNote, addUnmet]; split <;> rfl

theorem carryAll_join (env : Env) (ps : List NotePart) (st : St) :
    (ps.foldl (carryNote env) st).join = st.join := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl]; rw [ih, carryNote_join]

theorem pageFigures_join (env : Env) (ts : List Nat) (st : St) :
    (ts.foldl (pageFigure env) st).join = st.join := by
  induction ts generalizing st with
  | nil => rfl
  | cons t _ ih => exact ih (pageFigure env st t)

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

theorem carryNote_reserved (env : Env) (st : St) (p : NotePart) :
    (carryNote env st p).reserved = st.reserved ∧ (0 < st.noteLines → 0 < (carryNote env st p).noteLines) := by
  simp only [carryNote, addUnmet]
  split
  · exact ⟨rfl, id⟩
  · refine ⟨rfl, fun h => ?_⟩
    show 0 < st.noteLines + carrySep env st + (carryShown env st p.2.2 : Int)
    have : (0 : Int) ≤ (carryShown env st p.2.2 : Int) := Int.ofNat_nonneg _
    have : carrySep env st = 0 := by simp only [carrySep]; split <;> omega
    omega

theorem carryAll_reserved (env : Env) (ps : List NotePart) (st : St) :
    (ps.foldl (carryNote env) st).reserved = st.reserved ∧
      (0 < st.noteLines → 0 < (ps.foldl (carryNote env) st).noteLines) := by
  induction ps generalizing st with
  | nil => exact ⟨rfl, id⟩
  | cons p ps ih =>
    simp only [List.foldl]
    obtain ⟨a, b⟩ := ih (carryNote env st p)
    obtain ⟨a', b'⟩ := carryNote_reserved env st p
    exact ⟨a.trans a', fun h => b (b' h)⟩

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

theorem carryAll_columns (env : Env) (ps : List NotePart) (st : St) :
    (ps.foldl (carryNote env) st).columns = st.columns := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih =>
    simp only [List.foldl]; rw [ih]; simp only [carryNote, addUnmet]; split <;> rfl

theorem pageFigures_columns (env : Env) (ts : List Nat) (st : St) :
    (ts.foldl (pageFigure env) st).columns = st.columns := by
  induction ts generalizing st with
  | nil => rfl
  | cons t ts ih => simp only [List.foldl]; rw [ih]; rfl

theorem placeDeferred_columns (env : Env) (ws : List Deferred) (st : St) :
    (placeDeferred env st ws).columns = st.columns := by
  induction ws generalizing st with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · rw [ih]; rfl
      · rfl
    | pageFigure i => rfl

/-- Going on to the next column or page keeps the set of columns. -/
theorem advanceIn_columns (env : Env) (b : Bool) (st : St) : (advanceIn env b st).columns = st.columns := by
  simp only [advanceIn, openColumn]
  rw [placeDeferred_columns]
  show (List.foldl (carryNote env) _ st.pending).columns = st.columns
  rw [carryAll_columns, pageFigures_columns]
  simp only [advanceFresh, closePage]
  split <;> (try split) <;> rfl

theorem advanceIn_adjust (env : Env) (b : Bool) (st : St) :
    (advanceIn env b st).adjust = if b then 0 else st.setAdjust := by
  simp only [advanceIn]; rw [openColumn_adjust]; rfl

theorem carryNote_setAdjust (env : Env) (st : St) (p : NotePart) :
    (carryNote env st p).setAdjust = st.setAdjust := by
  simp only [carryNote, addUnmet]; split <;> rfl

theorem carryAll_setAdjust (env : Env) (ps : List NotePart) (st : St) :
    (ps.foldl (carryNote env) st).setAdjust = st.setAdjust := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl]; rw [ih, carryNote_setAdjust]

theorem pageFigures_setAdjust (env : Env) (ts : List Nat) (st : St) :
    (ts.foldl (pageFigure env) st).setAdjust = st.setAdjust := by
  induction ts generalizing st with
  | nil => rfl
  | cons t ts ih => simp only [List.foldl]; rw [ih]; rfl

theorem placeDeferred_setAdjust (env : Env) (ws : List Deferred) (st : St) :
    (placeDeferred env st ws).setAdjust = st.setAdjust := by
  induction ws generalizing st with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · rw [ih]; rfl
      · rfl
    | pageFigure i => rfl

theorem advanceIn_setAdjust (env : Env) (b : Bool) (st : St) :
    (advanceIn env b st).setAdjust = if b then 0 else st.setAdjust := by
  simp only [advanceIn, openColumn]
  rw [placeDeferred_setAdjust, carryAll_setAdjust, pageFigures_setAdjust]; rfl

theorem advanceIn_column (env : Env) (b : Bool) (st : St) :
    (advanceIn env b st).column = if b then 0 else st.column + 1 := by
  simp only [advanceIn]; rw [openColumn_column]; rfl

theorem advanceTurned_length (b : Bool) (st : St) :
    (advanceTurned b st).1.length + (advanceTurned b st).2.length = st.deferred.length := by
  unfold advanceTurned; split
  · exact spanTurned_length st.deferred
  · simp

theorem advanceIn_waiting_le (env : Env) (b : Bool) (st : St) :
    waiting (advanceIn env b st) ≤ waiting st := by
  simp only [advanceIn, waiting]
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
theorem advanceIn_page_waiting_lt (env : Env) (st : St) (h : 0 < waiting st) :
    waiting (advanceIn env true st) < waiting st := by
  simp only [advanceIn, waiting]
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

theorem advanceIn_page_fresh (env : Env) (st : St) (h : waiting st = 0) :
    (advanceIn env true st).used = top (advanceIn env true st) ∧ (advanceIn env true st).notes = [] := by
  have d : st.deferred = [] := by
    cases e : st.deferred with
    | nil => rfl
    | cons _ _ => simp [waiting, e] at h; omega
  have p : st.pending = [] := by
    cases e : st.pending with
    | nil => rfl
    | cons q _ => simp [waiting, e, pendingWeight, noteWeight] at h; omega
  simp [advanceIn, advanceTurned, d, p, spanTurned, openColumn, placeDeferred, advanceFresh, top]

theorem openBox_deferred (st : St) : (openBox st).deferred = st.deferred := by unfold openBox; split <;> rfl
theorem openBox_pending (st : St) : (openBox st).pending = st.pending := by unfold openBox; split <;> rfl
theorem openBox_adjust (st : St) : (openBox st).adjust = st.adjust := by unfold openBox; split <;> rfl
theorem openBox_column (st : St) : (openBox st).column = st.column := by unfold openBox; split <;> rfl
theorem openBox_columns (st : St) : (openBox st).columns = st.columns := by unfold openBox; split <;> rfl
theorem openBox_page (st : St) : (openBox st).page = st.page := by unfold openBox; split <;> rfl
theorem openBox_notes (st : St) : (openBox st).notes = st.notes := by unfold openBox; split <;> rfl
theorem openBox_slots (st : St) : (openBox st).slots = st.slots := by unfold openBox; split <;> rfl
theorem openBox_done (st : St) : (openBox st).done = st.done := by unfold openBox; split <;> rfl
theorem openBox_firstLine (st : St) : (openBox st).firstLine = st.firstLine := by unfold openBox; split <;> rfl
theorem openBox_reserved (st : St) : (openBox st).reserved = st.reserved := by unfold openBox; split <;> rfl
theorem openBox_noteLines (st : St) : (openBox st).noteLines = st.noteLines := by unfold openBox; split <;> rfl
theorem openBox_unmet (st : St) : (openBox st).unmet = st.unmet := by unfold openBox; split <;> rfl
theorem openBox_need (st : St) : (openBox st).need = st.need := by unfold openBox; split <;> rfl
theorem openBox_needAt (st : St) : (openBox st).needAt = st.needAt := by unfold openBox; split <;> rfl
theorem openBox_breaks (st : St) : (openBox st).breaks = st.breaks := by unfold openBox; split <;> rfl
theorem openBox_spaces (st : St) : (openBox st).spaces = st.spaces := by unfold openBox; split <;> rfl
theorem openBox_noBreak (st : St) : (openBox st).noBreak = st.noBreak := by unfold openBox; split <;> rfl
theorem openBox_blank (st : St) : (openBox st).blank = st.blank := by unfold openBox; split <;> rfl
theorem openBox_seen (st : St) : (openBox st).seen = st.seen := by unfold openBox; split <;> rfl
theorem openBox_lastDeferred (st : St) : (openBox st).lastDeferred = st.lastDeferred := by unfold openBox; split <;> rfl
theorem openBox_headingOnly (st : St) : (openBox st).headingOnly = st.headingOnly := by unfold openBox; split <;> rfl

/-- `openBox` adds the grid lines before the part of the box. -/
theorem openBox_used (st : St) : st.used ≤ (openBox st).used := by
  unfold openBox; split
  · exact Int.le_refl _
  · show st.used ≤ st.used + _; have := Int.ofNat_nonneg ‹BoxAt›.before; omega

theorem isEmpty_openBox (s : St) (h1 : s.used = top s) (h2 : s.notes = []) : isEmpty (openBox s) = true := by
  unfold openBox; split
  · simp [isEmpty, h1, h2, List.isEmpty]
  · simp [isEmpty, boxTop, atBoxStart, top, List.isEmpty, h2]
    simp [top] at h1; exact Or.inr h1

theorem advance_columns (env : Env) (b : Bool) (st : St) : (advance env b st).columns = st.columns := by
  rw [advance, openBox_columns, advanceIn_columns]

theorem advance_adjust (env : Env) (b : Bool) (st : St) :
    (advance env b st).adjust = if b then 0 else st.setAdjust := by
  rw [advance, openBox_adjust, advanceIn_adjust]

theorem openBox_setAdjust (st : St) : (openBox st).setAdjust = st.setAdjust := by unfold openBox; split <;> rfl

theorem advance_setAdjust (env : Env) (b : Bool) (st : St) :
    (advance env b st).setAdjust = if b then 0 else st.setAdjust := by
  rw [advance, openBox_setAdjust, advanceIn_setAdjust]

theorem advance_column (env : Env) (b : Bool) (st : St) :
    (advance env b st).column = if b then 0 else st.column + 1 := by
  rw [advance, openBox_column, advanceIn_column]

theorem waiting_openBox (st : St) : waiting (openBox st) = waiting st := by
  simp only [waiting, openBox_deferred, openBox_pending]

theorem advance_waiting_le (env : Env) (b : Bool) (st : St) : waiting (advance env b st) ≤ waiting st := by
  rw [advance, waiting_openBox]; exact advanceIn_waiting_le env b st

theorem advance_page_waiting_lt (env : Env) (st : St) (h : 0 < waiting st) :
    waiting (advance env true st) < waiting st := by
  rw [advance, waiting_openBox]; exact advanceIn_page_waiting_lt env st h

theorem advance_page_empty (env : Env) (st : St) (h : waiting st = 0) : isEmpty (advance env true st) = true := by
  obtain ⟨a, b⟩ := advanceIn_page_fresh env st h
  exact isEmpty_openBox _ a b

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
  have adj := advance_adjust env (st.columns ≤ st.column + 1) st
  have sadj := advance_setAdjust env (st.columns ≤ st.column + 1) st
  have col := advance_column env (st.columns ≤ st.column + 1) st
  have cols := advance_columns env (st.columns ≤ st.column + 1) st
  have le := advance_waiting_le env (st.columns ≤ st.column + 1) st
  have fullOld : isEmpty st = false → fullRank st = 1 := fun n => by simp [fullRank, n]
  have fullLe : fullRank (advance env (decide (st.columns ≤ st.column + 1)) st) ≤ 1 := by
    unfold fullRank; split <;> omega
  by_cases toPage : st.columns ≤ st.column + 1
  · simp only [toPage, decide_True, ite_true] at adj sadj col cols le fullLe ⊢
    have adjZero : adjustRank env (advance env true st) = 0 := by simp [adjustRank, adj, sadj]
    by_cases w : 0 < waiting st
    · exact Or.inl (advance_page_waiting_lt env st w)
    · have w0 : waiting st = 0 := by omega
      have e := advance_page_empty env st w0
      have full0 : fullRank (advance env true st) = 0 := by simp [fullRank, e]
      right
      refine ⟨by omega, ?_⟩
      rw [adjZero, full0]
      unfold adjustRank
      cases h with
      | inl n => have := fullOld n; split <;> (try split) <;> omega
      | inr n => split <;> (try rw [if_pos n]) <;> omega
  · simp only [toPage, decide_False] at adj sadj col cols le fullLe ⊢
    have c1 : (advance env false st).column = st.column + 1 := by rw [col]; rfl
    have cl : columnsLeft env (advance env false st) < columnsLeft env st := by
      simp only [columnsLeft, c1, cols]; omega
    by_cases w : waiting (advance env false st) < waiting st
    · exact Or.inl w
    · right
      refine ⟨by omega, ?_⟩
      rw [if_neg (by decide)] at adj sadj
      unfold adjustRank
      rw [adj, sadj]
      by_cases sa : st.setAdjust < 0
      · rw [if_pos sa, if_pos sa]; left; omega
      · rw [if_neg sa, if_neg sa, if_neg sa]
        cases h with
        | inr n => rw [if_pos n]; omega
        | inl n =>
          have := fullOld n
          split <;> omega

/-- Going on while figures or notes wait decreases what waits and the
    columns left on the page (`flushDeferred`, `flushFigures`). -/
theorem I4_nextColumn_flush_rank (env : Env) (st : St) (h : 0 < waiting st) :
    Prod.Lex (· < ·) (· < ·) (waiting (nextColumn env st), columnsLeft env (nextColumn env st))
      (waiting st, columnsLeft env st) := by
  simp only [Prod.lex_def, nextColumn]
  have col := advance_column env (st.columns ≤ st.column + 1) st
  have le := advance_waiting_le env (st.columns ≤ st.column + 1) st
  by_cases toPage : st.columns ≤ st.column + 1
  · simp only [toPage, decide_True] at col le ⊢
    exact Or.inl (advance_page_waiting_lt env st h)
  · simp only [toPage, decide_False] at col le ⊢
    by_cases w : waiting (advance env false st) < waiting st
    · exact Or.inl w
    · have c1 : (advance env false st).column = st.column + 1 := by rw [col]; rfl
      exact Or.inr ⟨by omega, by simp only [columnsLeft, c1, advance_columns]; omega⟩

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

/-! ## Stanzas (`placeStanza` of Paginate.hs) -/

theorem join_append' {α : Type} (a b : List (List α)) : (a ++ b).join = a.join ++ b.join := by
  induction a with
  | nil => rfl
  | cons x xs ih => simp [List.join, ih]


/-- `k0` of `placeStanza`: the first verse lines whose lines fit in `room`. -/
def versesFitting (room : Nat) : List (List Line) → Nat
  | [] => 0
  | v :: r => if v.length ≤ room then versesFitting (room - v.length) r + 1 else 0

def stanzaK0 (env : Env) (st : St) (vs : List (List Line)) : Nat := versesFitting (env.fitting st vs.join) vs
def stanzaK2 (env : Env) (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) : Nat :=
  splitAtBreak kp isStart vs.length (stanzaK0 env st vs)

def putVerses (env : Env) (st : St) (vs : List (List Line)) : St := vs.join.foldl (putLine env) st

/-- The short last part of a stanza whose first verse line is broken as a
    paragraph. -/
def shortVerse (kp : Keep) (pid n : Nat) (more : List (List Line)) : List Unmet :=
  if n - 1 < kp.last ∧ more ≠ [] then [.shortLast pid kp.last (n - 1)] else []

set_option linter.unusedVariables false in
/-- `go` of `placeStanza` of Paginate.hs, for the stanza whose first line
    is `pid`: a verse line is not broken between columns. -/
def placeStanzaGo (env : Env) (pid : Nat) : Keep → St → Bool → List (List Line) → St
  | _, st, _, [] => st
  | kp, st, isStart, v :: more =>
    let n := (v :: more).length
    let k0 := stanzaK0 env st (v :: more)
    let k2 := stanzaK2 env kp st isStart (v :: more)
    if h1 : kp.all = true ∧ isStart = true ∧ stanzaK0 env st (v :: more) < (v :: more).length then
      if h2 : isEmpty st = true ∨ st.headingOnly = true then
        placeStanzaGo env pid { kp with all := false } (addUnmet (.splitKept pid) st) isStart (v :: more)
      else placeStanzaGo env pid kp (nextColumn env st) isStart (v :: more)
    else if (v :: more).length ≤ stanzaK2 env kp st isStart (v :: more) then putVerses env st (v :: more)
    else if h3 : 0 < stanzaK2 env kp st isStart (v :: more) then
      placeStanzaGo env pid kp (nextColumn env (putVerses env st ((v :: more).take k2))) false ((v :: more).drop k2)
    else if h4 : emptyish env st (v :: more).join = true then
      if h5 : stanzaK0 env st (v :: more) = 0 then
        placeStanzaGo env pid kp ((shortVerse kp pid n more).foldl (fun s u => addUnmet u s)
          (placeLines env defaultKeep st isStart v)) false more
      else
        placeStanzaGo env pid kp (nextColumn env ((shortParts kp pid true isStart n k0).foldl (fun s u => addUnmet u s)
          (putVerses env st ((v :: more).take k0)))) false ((v :: more).drop k0)
    else placeStanzaGo env pid kp (nextColumn env st) isStart (v :: more)
termination_by kp st _ vs => (vs.length, allRank kp, rank env st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; apply Prod.Lex.left; simp_all [allRank]; done)
    | (apply linesLt_rank; apply I4_nextColumn_rank; left; cases e : isEmpty st
       · rfl
       · simp [emptyish, e] at *)

def placeStanza (env : Env) (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) : St :=
  match vs.join with
  | [] => placeStanzaGo env 0 kp st isStart vs
  | l :: _ => placeStanzaGo env l.id kp st isStart vs

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
    if 1 < st.columns ∧ st.deferred.any isPageFigure = false then nextColumn env st
    else breakPage env st

/-- `startBefore` of Paginate.hs: the start of a section or of a paragraph
    of a style with page-break; the page a section starts on recorded. -/
def startBefore (env : Env) (st : St) (sec : Option Nat) (k : BreakKind) : St :=
  let st1 := match k with
    | .column => if isEmpty st then st else nextColumn env st
    | .page =>
      let st0 := flushDeferred env st
      if isEmpty st0 = true ∧ st0.column = 0 then st0 else nextPage env st0
    | .recto => parityStart env odd st
    | .verso => parityStart env even st
  match sec with
  | some i => { st1 with sections := st1.sections ++ [(i, st1.page)] }
  | none => st1

/-- `applyBreak` of Paginate.hs. -/
def applyPending (env : Env) (st : St) : Pending → St
  | .brk k => applyBreakKind env st k
  | .start sec k => startBefore env st sec k

def applyBreaks (env : Env) (st : St) : St :=
  st.breaks.foldl (applyPending env) { st with breaks := [] }

/-! ## Book parts (BookParts.hs `placeBookPart`) -/

/-- `slotIds` of BookParts.hs; a repeated header line is a line of the
    same id. -/
def slotIds : Slot → List Nat
  | .line i | .heading i _ | .figure i | .pageFigure i | .codeRow i | .repeated i | .wrapped i => [i]
  | .code rows => rows

/-- `key` of `placeBookPart`: the unit of a column. -/
def unitKey : KeepParts → Nat → Nat → Nat × Nat
  | .column, p, c => (p, c)
  | .page, p, _ => (p, 0)
  | .spread, p, _ => (if p = 1 then 0 else p / 2, 0)

def keyMin (a b : Nat × Nat) : Nat × Nat := if a.1 < b.1 ∨ (a.1 = b.1 ∧ a.2 ≤ b.2) then a else b

def minKey : List (Nat × Nat) → Option (Nat × Nat)
  | [] => none
  | k :: ks => some (ks.foldl keyMin k)

/-- `fits` of `placeBookPart`: every id retained is placed, and the first
    unit of each is the same. -/
def fitsPart (unit : KeepParts) (first : Nat) (wanted : List Nat) (st : St) : Bool :=
  let entries := (st.done.takeWhile (fun p => decide (first ≤ p.number))).map (fun p => (p.number, p.column, p.slots))
    ++ [(st.page, st.column, st.slots)]
  let keysOf (w : Nat) : List (Nat × Nat) :=
    entries.bind (fun e => if e.2.2.any (fun s => (slotIds s.2).contains w) then [unitKey unit e.1 e.2.1] else [])
  let found := wanted.map (fun w => minKey (keysOf w))
  found.all Option.isSome && (match found.filterMap id with
    | [] => true
    | k :: ks => ks.all (· == k))

/-- `emptyUnit` of `placeBookPart`. -/
def emptyUnit (unit : KeepParts) (st : St) : Bool :=
  isEmpty st && top st == 0 && (match unit with
    | .column => true
    | .page => st.column == 0
    | .spread => st.column == 0 && (st.page == 1 || even st.page))

theorem pageFigures_page_ge (env : Env) (ts : List Nat) (st : St) : st.page ≤ (ts.foldl (pageFigure env) st).page := by
  induction ts generalizing st with
  | nil => exact Nat.le_refl _
  | cons t ts ih => exact Nat.le_trans (Nat.le_succ _) (ih (pageFigure env st t))

theorem carryAll_page (env : Env) (ps : List NotePart) (st : St) : (ps.foldl (carryNote env) st).page = st.page := by
  induction ps generalizing st with
  | nil => rfl
  | cons p ps ih => simp only [List.foldl]; rw [ih]; simp only [carryNote, addUnmet]; split <;> rfl

theorem placeDeferred_page (env : Env) (ws : List Deferred) (st : St) : (placeDeferred env st ws).page = st.page := by
  induction ws generalizing st with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · rw [ih]; rfl
      · rfl
    | pageFigure i => rfl

theorem nextPage_page_gt (env : Env) (st : St) : st.page < (nextPage env st).page := by
  simp only [nextPage, advance]
  rw [openBox_page]
  simp only [advanceIn, openColumn]
  rw [placeDeferred_page]
  show st.page < (List.foldl (carryNote env) _ st.pending).page
  rw [carryAll_page]
  have f : (advanceFresh env true st).page = st.page + 1 := rfl
  have := pageFigures_page_ge env (advanceTurned true st).1 (advanceFresh env true st)
  omega

set_option linter.unusedVariables false in
/-- `go` of `nextUnit` for a spread: the next pages up to the first page
    of the next spread. -/
def nextSpread (env : Env) (target : Nat) (st : St) : St :=
  if h : (nextPage env st).page < target then nextSpread env target (nextPage env st) else nextPage env st
termination_by target - st.page
decreasing_by simp_wf; have := nextPage_page_gt env st; omega

/-- `nextUnit` of `placeBookPart`. -/
def nextUnit (env : Env) (unit : KeepParts) (st : St) : St :=
  match unit with
  | .column => nextColumn env st
  | .page => nextPage env st
  | .spread => nextSpread env (if st.page = 1 then 2 else 2 * (st.page / 2 + 1)) st

/-- `trial` of `placeBookPart`: the flattened flows, unless a nested part
    does not keep its ids in one unit. -/
def partTrial (env : Env) (runBody runPlain : St → St) (unit : KeepParts) (fits : St → Bool) (nested whole : Bool)
    (state : St) : St :=
  let placed := runPlain state
  let completed := if unit = .column then placed else flushFigures env placed
  if whole || !nested || !fits completed then completed else flushFigures env (runBody state)

/-- `placeBookPart` of BookParts.hs: the flows of the part run by
    `runBody`, and flattened by `runPlain`, from the state given; the
    trials that do not keep the ids retained in one unit are discarded.
    `nested` and `whole` are those of BookParts.hs. -/
def placeBookPart (env : Env) (runBody runPlain : St → St) (initial : St) (unit : KeepParts) (kind : Option Nat)
    (retained : List Nat) (nested whole : Bool) : St :=
  let fits := fitsPart unit initial.page retained
  let ordinary := if unit = .column then runBody initial else partTrial env runBody runPlain unit fits nested whole initial
  let moved := nextUnit env unit initial
  let movedTrial := partTrial env runBody runPlain unit fits nested whole moved
  let emptyTrial := if emptyUnit unit initial then ordinary else movedTrial
  let report (st : St) : St := addUnmet (.splitBookPart kind unit) st
  if retained = [] then runBody initial
  else if unit = .column then (if fits emptyTrial then ordinary else report ordinary)
  else if fits ordinary then ordinary
  else if fits movedTrial then movedTrial
  else if emptyUnit unit initial then report (runBody initial)
  else report (runBody moved)

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
  if st.used = top st ∨ atBoxStart st = true then st else { st with used := st.used + max 0 (min (n : Int) (free env st)) }

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
  | .bookPart _ _ _ (g :: _) => startsRecto g
  | .heading recto _ _ => recto
  | .ruled _ _ _ _ (.heading recto _ _) => recto
  | _ => false
termination_by f => sizeOf f
decreasing_by simp_wf; omega

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

mutual
/-- `waitsFor` of Paginate.hs: the flows that place nothing of their own. -/
def waitsFor : Flow → Bool
  | .bookPart _ _ _ body => allWaitsFor body
  | .brk _ | .sectionStart _ _ | .space _ | .blank _ | .needLines _ | .noBreak | .noBreakLines _ | .keepNext _ _
  | .adjustLines _ => true
  | _ => false
termination_by f => sizeOf f
/-- `all waitsFor`. -/
def allWaitsFor : List Flow → Bool
  | [] => true
  | g :: r => waitsFor g && allWaitsFor r
termination_by fs => sizeOf fs
end

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

/-- Whether `go` of `placeTableAcross` keeps the last row and the caption
    below it in one unit: in a book part, at the last row before a
    caption below. -/
def retainsTail (env : Env) (capt : List Line) (below retain : Bool) (isHeader : Bool)
    (remaining : List (Bool × List Line)) : Bool :=
  retain && below && !capt.isEmpty && env.inBookPart && !isHeader && remaining == [(false, capt)]

set_option linter.unusedVariables false in
/-- `go` and `placeGroup` of `placeTableAcross` of Paginate.hs: each
    group whole in a column, or in an empty column; the header repeated
    once on a page gone on to.  `retain` is the first argument of `go`,
    `fresh` whether the group is entered by `go`, not tried again by
    `placeGroup`.  In a book part, the last row and the caption below it
    are kept in one unit by `placeBookPart`. -/
def acrossGo (env : Env) (h capt : List Line) (below : Bool) :
    Bool → Bool → Bool → St → List (Bool × List Line) → St
  | _, _, _, st, [] => st
  | retain, fresh, retried, here, (isHeader, ls) :: remaining =>
    if hr : fresh = true ∧ retainsTail env capt below retain isHeader remaining = true then
      let run (start : St) : St :=
        acrossGo env h capt below false true false
          (if decide (start.page ≠ here.page) && !h.isEmpty then h.foldl putRepeated start else start)
          ((isHeader, ls) :: remaining)
      placeBookPart env run run here env.keepParts none ((ls ++ capt).map (·.id)) false true
    else if h1 : ls.length ≤ env.fitting here ls ∨ isEmpty here = true then
      acrossGo env h capt below retain true false (ls.foldl (putLine env) here) remaining
    else
      acrossGo env h capt below retain false (retried || mustRepeat h (nextColumn env here) here isHeader retried)
        (if mustRepeat h (nextColumn env here) here isHeader retried
          then h.foldl putRepeated (nextColumn env here) else nextColumn env here)
        ((isHeader, ls) :: remaining)
termination_by retain _ retried here gs =>
  (if retain then 1 else 0, gs.length, if retried then 0 else 1, rank env here)
decreasing_by
  all_goals simp_wf
  · apply Prod.Lex.left
    have := hr.2; simp only [retainsTail, Bool.and_eq_true] at this
    simp [this.1.1.1.1.1]
  · exact Prod.Lex.right _ (Prod.Lex.left _ _ (Nat.lt_succ_self _))
  · apply Prod.Lex.right; apply Prod.Lex.right
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
  acrossGo env h capt below true true false st (tableGroups h rows capt below)

/-! ## No-breaks and keep-with-nexts (docs/adr/0261) -/

/-- `previousKeep` of `placeFlow`. -/
def previousKeep (env : Env) (rest : List Flow) (kp : Keep) : Keep :=
  if 0 < env.keepLast rest then { kp with last := max kp.last (env.keepLast rest), first := max 2 kp.first }
  else kp

/-- The lines that `placeKept` sends to the next column together. -/
def keptCut (kp : Keep) (len : Nat) : Nat :=
  if kp.all = true ∨ len ≤ kp.last ∨ len - kp.last < kp.first then len else kp.last

/-- `heldHere` of State.hs: a keep-with-next of a visible separator waits
    in the current column for the flow being placed (root ADR 0398 I7). -/
def heldHere (env : Env) (st : St) : Bool :=
  st.noBreak.any fun w =>
    (match w.1 with | .keepNext sp => env.held sp | _ => false) && w.2.1 == st.page && w.2.2.1 == st.column

/-- `placeKept` of Paginate.hs, for the lines of a paragraph or a term,
    or the verse lines of a stanza. -/
def placeKept {α : Type} (env : Env) (kp : Keep) (placeIn : St → Bool → List α → St) (st : St) (isStart : Bool)
    (ls : List α) (n : Need) : St :=
  let st1 := placeIn st isStart ls
  let front := ls.take (ls.length - keptCut kp ls.length)
  let back := ls.drop (ls.length - keptCut kp ls.length)
  let stA := placeIn st isStart front
  let here := placeIn stA (isStart && front.isEmpty) back
  let fits (s : St) : Prop := needIn env s noNeed n ≤ free env s
  if fits st1 then st1
  else if here.page = stA.page ∧ here.column = stA.column ∧ fits here then here
  else if isEmpty stA = true ∨ heldHere env stA = true then st1
  else placeIn (nextColumn env stA) (isStart && front.isEmpty) back

/-- `waitFor` of Paginate.hs. -/
def waitFor (u : Unmet) (k : Nat × Bool) (st : St) : St :=
  match st.noBreak with
  | [] => { st with noBreak := [(u, st.page, st.column, st.slots.length, k)] }
  | ws@((_, p, c, n, (k0, l0)) :: _) =>
    { st with noBreak := (ws ++ [(u, p, c, n, k)]).map (fun w => (w.1, p, c, n, (max k0 k.1, l0 || k.2))) }

/-- `slotLineCount` of Paginate.hs; a repeated header line is a line. -/
def slotLineCount (linesOnly : Bool) : Slot → Nat
  | .line _ => 1
  | .repeated _ => 1
  | .heading _ m => max 1 m
  | _ => if linesOnly then 0 else 1

def linesIn (linesOnly : Bool) (n : Nat) (slots : List (Int × Slot)) : Nat :=
  ((slots.drop n).map (fun s => slotLineCount linesOnly s.2)).foldr (· + ·) 0

/-- `checkNoBreak` of Paginate.hs. -/
def checkNoBreak (st : St) : St :=
  match st.noBreak with
  | [] => st
  | ws@((_, p, c, n, (k, linesOnly)) :: _) =>
    let added := if st.page = p ∧ st.column = c then linesIn linesOnly n st.slots
      else ((st.done.filter (fun po => po.number == p && po.column == c)).map
        (fun po => linesIn linesOnly n po.slots)).foldr max 0
    let st' := if max 1 k ≤ added then st else ws.foldl (fun s w => addUnmet w.1 s) st
    { st' with noBreak := [] }

def deferredFigure (i : Nat) : Deferred → Bool
  | .figure j _ => i == j
  | _ => false

/-- `adjustLines` of Paginate.hs: at least one line and the lines placed,
    at most `maxLines`. -/
def adjustLines (env : Env) (st : St) (k : Int) : St :=
  let want := st.adjust + k
  let placed := st.used + st.noteLines
  let got := max (max 1 placed - env.capacity) (min (env.maxLines - env.capacity) want)
  let st1 := { st with adjust := got }
  let limit := if got < want then AdjustLimit.noRoom else if 1 ≤ placed then .linesPlaced else .oneLine
  if got ≠ want then addUnmet (.adjust got limit) st1 else st1

/-- `takeNoteLines` of State.hs: the first `r` lines of the notes in
    parts, in their order, and the rest. -/
def takeNoteLines : Int → List NotePart → List NotePart × List NotePart
  | _, [] => ([], [])
  | r, (i, f, l) :: more =>
    if r ≤ 0 then ([], (i, f, l) :: more)
    else if (l : Int) ≤ r then
      let p := takeNoteLines (r - l) more
      ((i, f, l) :: p.1, p.2)
    else ([(i, f, r.toNat)], (i, f + r.toNat, l - r.toNat) :: more)

/-- `joinNotePart` of State.hs: a part of a note after the parts of a
    column, joined to the part before it of the same note. -/
def joinNotePart (parts : List NotePart) (p : NotePart) : List NotePart :=
  match parts.reverse with
  | (j, f, l) :: before => if j = p.1 ∧ f + l = p.2.1 then before.reverse ++ [(j, f, l + p.2.2)] else parts ++ [p]
  | [] => parts ++ [p]

/-- `drainPendingNotes` of State.hs: the continued notes take the room
    `FAdjustLines` has added to the column, in their order, before any
    later note (root ADR 0444): all of it when the column has text, all
    but one line when it has none, as `carryNote` leaves one.  What does
    not fit goes on to the next column. -/
def drainSep (env : Env) (st : St) : Int := if st.noteLines = 0 then env.separator else 0
def drainRoom (env : Env) (st : St) : Int := free env st - drainSep env st - (if st.slots.isEmpty then 1 else 0)

def drainPendingNotes (env : Env) (st : St) : St :=
  if st.pending.isEmpty ∨ drainRoom env st ≤ 0 then st
  else
    let p := takeNoteLines (drainRoom env st) st.pending
    { st with notes := p.1.foldl joinNotePart st.notes,
              noteLines := st.noteLines + drainSep env st + partsLines p.1, pending := p.2 }

/-- The grid line after the part of the box in the column closed, with
    its grid lines after (`ends` of `place` of `FBoxed`, from
    `closeBox`); the lines used where the part has no line. -/
def boxEnd (st : St) : Int :=
  match st.box with
  | none => st.used
  | some b =>
    match st.slots.filterMap (fun s => match s with | (g, .line _) => if b.start ≤ g then some g else none | _ => none) with
    | [] => st.used
    | g :: gs => gs.foldl max g + b.after + 1

/-! ## Blocks with rules (`placeRuled` of Paginate.hs, golem-driver ADR 0027) -/

def RuledBody.lines' : RuledBody → List Line
  | .lines _ ls | .heading _ _ ls => ls

/-- `bodySize` of Decide.hs. -/
def RuledBody.size : RuledBody → Nat
  | .lines _ ls => ls.length
  | .heading _ n _ => n

def RuledBody.recto : RuledBody → Bool
  | .heading true _ _ => true
  | _ => false

/-- `joinsNext` of Decide.hs: the rule after waits for the next block to
    share its area. -/
def joinsNext (after : Bool) (rest : List Flow) : Bool :=
  after && match flattenParts rest with
    | .ruled _ true _ true _ :: _ => true
    | _ => false

/-- `Plan` of Decide.hs without the rules placed: the grid lines of the
    area before, the grid lines of the area after, and the rule after
    that waits for the next block. -/
structure Plan where
  before : Nat
  after : Nat
  waiting : Option (Nat × Int)
  /-- The rules placed before the lines of the block, and after them. -/
  beforeRules : List PlacedRule
  afterRules : List PlacedRule

/-- `planOf` of Decide.hs. -/
def planOf (env : Env) (st : St) (i : Nat) (before after : Bool) (body : RuledBody) (rest : List Flow)
    (joined : Option (Nat × Int)) : Plan :=
  let k1 : Nat := match joined with
    | some (a, _) => env.rulesJoined a i
    | none => if before then env.ruleBefore i (st.used == top st) (top st == 0) else 0
  let rulesBefore : List PlacedRule := match joined with
    | some (a, aLast) => [⟨a, false, aLast, .joinedAfter i, k1⟩, ⟨i, true, aLast, .joinedBefore a, k1⟩]
    | none =>
      if before then
        if st.used == top st then [⟨i, true, st.used, .start (top st == 0), k1⟩]
        else [⟨i, true, st.used - 1, .inside, k1⟩]
      else []
  let lastLine : Int := st.used + k1 + body.size - 1
  let notes := decide (0 < st.noteLines) || !(body.lines'.all (·.notes.isEmpty))
  let k2 : Nat :=
    if after && !joinsNext after rest then
      if cap env st - st.noteLines ≤ lastLine + 1 + env.ruleAfter i then env.ruleAfterAtEnd i !notes
      else env.ruleAfter i
    else 0
  let rulesAfter : List PlacedRule :=
    if after && !joinsNext after rest then
      [⟨i, false, lastLine, if cap env st - st.noteLines ≤ lastLine + 1 + env.ruleAfter i then .atEnd !notes else .inside, k2⟩]
    else []
  ⟨k1, k2, if joinsNext after rest then some (i, lastLine) else none, rulesBefore, rulesAfter⟩

/-- `planParts` of Decide.hs: a paragraph's block fits by its grid lines
    alone, a heading's counts its notes. -/
def planParts (body : RuledBody) (p : Plan) : Need :=
  match body with
  | .lines _ ls => ⟨p.before + ls.length + p.after, 0⟩
  | .heading _ n ls => ⟨p.before + n + p.after, noteLinesOf ls⟩

def planNeed (env : Env) (st : St) (body : RuledBody) (p : Plan) : Int := needIn env st (planParts body p) noNeed

/-- The lines of a paragraph's block, each keeping the grid lines of the
    lines after it and of the area after. -/
def putRuledLines (env : Env) (k2 : Nat) : St → List Line → St
  | st, [] => st
  | st, l :: ls => putRuledLines env k2 (putLineKeeping env (ls.length + k2) st l) ls

/-- `commitRuled` of Paginate.hs. -/
def commitRuled (env : Env) (st : St) (body : RuledBody) (p : Plan) : St :=
  let st1 := { st with used := st.used + p.before, join := none }
  let st2 := match body with
    | .lines _ ls => putRuledLines env p.after st1 ls
    | .heading _ n ls => { putBlock env st1 n ls with headingOnly := isEmpty st || st.headingOnly }
  { st2 with
    used := min (st2.used + p.after) (max st2.used (cap env st2 - st2.noteLines))
    join := p.waiting
    rules := st2.rules ++ p.beforeRules ++ p.afterRules }

/-- `splitRuled` of Paginate.hs: a block that does not fit an empty
    column. -/
def splitRuled (env : Env) (st0 : St) (i : Nat) (before after : Bool) (body : RuledBody) (rest : List Flow) : St :=
  let st := if isEmpty st0 then st0 else nextColumn env st0
  let k1 := (planOf env st i before after body rest none).before
  match body with
  | .lines kp ls => placeLines env kp st true ls
  | .heading _ n ls =>
    let k2 := (planOf env st i before after body [] none).after
    let rb := (planOf env st i before after body rest none).beforeRules
    let ra := (planOf env st i before after body [] none).afterRules
    if (k1 : Int) + headingNeed env st n ls + k2 ≤ free env st then commitRuled env st body ⟨k1, k2, none, rb, ra⟩
    else if (k1 : Int) + headingNeed env st n ls ≤ free env st then commitRuled env st body ⟨k1, 0, none, rb, []⟩
    else putBlock env st n ls

/-- `flushJoin` of Paginate.hs: the rule after of the block before, in
    its own area. -/
def flushJoin (env : Env) (st : St) : St :=
  match st.join with
  | none => st
  | some (a, aLast) =>
    let k : Nat := if cap env st - st.noteLines ≤ aLast + 1 + env.ruleAfter a
      then env.ruleAfterAtEnd a (st.noteLines == 0) else env.ruleAfter a
    { st with
      used := st.used + min (k : Int) (free env st)
      join := none
      rules := st.rules ++ [⟨a, false, aLast,
        if cap env st - st.noteLines ≤ aLast + 1 + env.ruleAfter a then .atEnd (st.noteLines == 0) else .inside, k⟩] }

/-- The grid lines of the area of the rule after that waits, in its own
    area (`ownAfter` of Paginate.hs): at the end of the column when the
    area would reach it or the footnote lines. -/
def ownArea (env : Env) (st : St) (a : Nat) (aLast : Int) : Nat :=
  if cap env st - st.noteLines ≤ aLast + 1 + env.ruleAfter a
  then env.ruleAfterAtEnd a (st.noteLines == 0) else env.ruleAfter a

/-- `maybe True ((<= free env st) . snd) (ownAfter env st)` of
    Paginate.hs: the rule after that waits fits the room in its own area. -/
def ownFits (env : Env) (st : St) : Bool :=
  match st.join with
  | none => true
  | some (a, aLast) => decide ((ownArea env st a aLast : Int) ≤ free env st)

mutual
/-- `settleRuled` of Paginate.hs: a block placed here when its block fits
    the room.  Its rule after shares an area with the next block's rule
    before only when that block goes on in this column (golem-driver ADR
    0027, 「隣り合う罫線」); otherwise the area is its own and is counted in
    the block, so that the rule stays in the column. -/
def settleRuled (env : Env) (st : St) (i : Nat) (before after : Bool) (body : RuledBody) (rest : List Flow)
    (joined : Option (Nat × Int)) : Option St :=
  if planNeed env st body (planOf env st i before after body rest joined) ≤ free env st
      ∧ settlesOn env (commitRuled env st body (planOf env st i before after body rest joined)) (flattenParts rest) = true then
    some (commitRuled env st body (planOf env st i before after body rest joined))
  else if planNeed env st body (planOf env st i before after body [] joined) ≤ free env st then
    some (commitRuled env st body (planOf env st i before after body [] joined))
  else none
termination_by (flowsWeight rest, 1)
decreasing_by
  simp_wf
  have := flattenParts_weight rest
  rcases Nat.lt_or_eq_of_le this with h | h
  · exact Prod.Lex.left _ _ h
  · rw [h]; exact Prod.Lex.right _ (by decide)

/-- `settlesAfter` of Paginate.hs on the flows ahead with their book parts
    opened (`flattenBookParts`): the rule after that waits stays in the
    column: the next block takes it into its area in this column, or its
    own area fits the room. -/
def settlesOn (env : Env) (st : St) (fs : List Flow) : Bool :=
  match st.join, fs with
  | none, _ => true
  | some j, .ruled i true a true body :: later =>
    if !body.recto && (settleRuled env st i true a body later (some j)).isSome then true
    else ownFits env st
  | some _, _ => ownFits env st
termination_by (flowsWeight fs, 0)
decreasing_by
  simp_wf
  apply Prod.Lex.left
  simp only [flowsWeight]; omega
end

/-- `settlesAfter` of Paginate.hs. -/
def settlesAfter (env : Env) (st : St) (rest : List Flow) : Bool := settlesOn env st (flattenParts rest)

/-- What `settleRuled` places: the block committed with the plan that
    shares its rule after with the flows ahead, or with the plan whose
    rule after takes its own area, each fitting the room. -/
theorem settleRuled_spec (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow)
    (j : Option (Nat × Int)) (r : St) (h : settleRuled env st i b a body rest j = some r) :
    ∃ rest', (rest' = rest ∨ rest' = []) ∧ planNeed env st body (planOf env st i b a body rest' j) ≤ free env st
      ∧ r = commitRuled env st body (planOf env st i b a body rest' j) := by
  unfold settleRuled at h
  split at h
  · rename_i c; exact ⟨rest, Or.inl rfl, c.1, (Option.some.inj h).symm⟩
  · split at h
    · rename_i c; exact ⟨[], Or.inr rfl, c, (Option.some.inj h).symm⟩
    · cases h

/-- A property of every block `settleRuled` commits holds of what a
    placement that falls back to `x` places. -/
theorem settle_or (P : St → Prop) (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody)
    (rest : List Flow) (j : Option (Nat × Int)) (x : St)
    (hc : ∀ rest', (rest' = rest ∨ rest' = []) → planNeed env st body (planOf env st i b a body rest' j) ≤ free env st →
      P (commitRuled env st body (planOf env st i b a body rest' j)))
    (hx : P x) :
    P (match settleRuled env st i b a body rest j with | some p => p | none => x) := by
  cases h : settleRuled env st i b a body rest j with
  | none => exact hx
  | some r =>
    obtain ⟨rest', e, fit, hr⟩ := settleRuled_spec env st i b a body rest j r h
    simp only []; rw [hr]; exact hc rest' e fit

/-- The columns a block with no rule waiting goes on to first: a heading
    not at a recto keeps the first part of what follows, a paragraph of
    keep-with-next the first part of what follows that. -/
def ruledKeep (env : Env) (st1 : St) (i : Nat) (before after : Bool) (body : RuledBody) (rest : List Flow) : St :=
  let plan (s : St) := planOf env s i before after body rest none
  match body with
  | .heading false _ _ => keep env st1 (fun s => needIn env s (planParts body (plan s)) (env.nextNeed rest))
  | .heading true _ _ => st1
  | .lines _ _ =>
    match env.keptNeed rest with
    | some kn => if 0 < env.keepNextLines rest then keep env st1 (fun s => needIn env s (planParts body (plan s)) kn) else st1
    | none => st1

/-- `placeRuled` of Paginate.hs with no rule waiting. -/
def placeRuledFresh (env : Env) (st : St) (i : Nat) (before after : Bool) (body : RuledBody) (rest : List Flow) : St :=
  let st1 := if body.recto then parityStart env odd st else st
  let st2 := ruledKeep env st1 i before after body rest
  match settleRuled env st2 i before after body rest none with
  | some placed => placed
  | none =>
    if isEmpty st2 then splitRuled env st2 i before after body rest
    else
      match settleRuled env (nextColumn env st2) i before after body rest none with
      | some placed => placed
      | none => splitRuled env (nextColumn env st2) i before after body rest

/-- The block placed sharing the area of the rule waiting `j`, when it
    shares it (`frJoined`, a rule before, not at a recto) and settles in
    this column. -/
def settleJoined (env : Env) (st : St) (i : Nat) (before after joined : Bool) (body : RuledBody) (rest : List Flow)
    (j : Nat × Int) : Option St :=
  if joined && before && !body.recto then settleRuled env st i before after body rest (some j) else none

/-- `placeRuled` of Paginate.hs: a block whose rule before shares the area
    of the rule waiting when it settles there; else the rule waiting takes
    its own area first. -/
def placeRuled (env : Env) (st : St) (i : Nat) (before after joined : Bool) (body : RuledBody) (rest : List Flow) : St :=
  match st.join with
  | some j =>
    match settleJoined env st i before after joined body rest j with
    | some placed => placed
    | none => placeRuledFresh env (flushJoin env st) i before after body rest
  | none => placeRuledFresh env st i before after body rest

theorem settleJoined_spec (env : Env) (st : St) (i : Nat) (b a jn : Bool) (body : RuledBody) (rest : List Flow)
    (jj : Nat × Int) (r : St) (h : settleJoined env st i b a jn body rest jj = some r) :
    (jn && b && !body.recto) = true ∧ settleRuled env st i b a body rest (some jj) = some r := by
  unfold settleJoined at h
  split at h
  · rename_i c; exact ⟨c, h⟩
  · cases h

/-- A property of every block committed sharing the rule waiting `jj`
    holds of what `placeRuled` places when a rule waits, falling back to
    `x`. -/
theorem joined_or (P : St → Prop) (env : Env) (st : St) (i : Nat) (b a jn : Bool) (body : RuledBody)
    (rest : List Flow) (jj : Nat × Int) (x : St)
    (hc : ∀ rest', (rest' = rest ∨ rest' = []) →
      planNeed env st body (planOf env st i b a body rest' (some jj)) ≤ free env st →
      P (commitRuled env st body (planOf env st i b a body rest' (some jj))))
    (hx : P x) :
    P (match settleJoined env st i b a jn body rest jj with | some p => p | none => x) := by
  cases h : settleJoined env st i b a jn body rest jj with
  | none => exact hx
  | some r =>
    obtain ⟨_, h2⟩ := settleJoined_spec env st i b a jn body rest jj r h
    obtain ⟨rest', e, fit, hr⟩ := settleRuled_spec env st i b a body rest (some jj) r h2
    simp only []; rw [hr]; exact hc rest' e fit

/-! ## One flow and the flows of a part (mutual: a book part and a box run their flows by `step`) -/

mutual
/-- `place` of Paginate.hs. -/
def place (env : Env) (st : St) (f : Flow) (rest : List Flow) : St :=
  match f with
  | .paragraph kp ls => placeLines env kp st true ls
  | .continued kp ls => placeLines env kp st false ls
  | .stanza kp vs => placeStanza env kp st true vs
  | .ruled i before after joined body => placeRuled env st i before after joined body rest
  | .wrapped i n beside =>
    let st0 := flushFigures env st
    let size : Int := max (n : Int) beside.length
    -- the figure fits with the notes of its side lines and their separator (root ADR 0443)
    let st1 := keep env st0 (fun s => needIn env s ⟨max n beside.length, noteLinesOf beside⟩ ⟨0, 0⟩)
    let st2 := putSlot st1 0 (.wrapped i)
    let st3 := placeLines env defaultKeep st2 false beside
    -- the side lines their notes send on take the next column from its top
    if st3.page = st2.page ∧ st3.column = st2.column then { st3 with used := max (st1.used + size) st3.used }
    else st3
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
  | .brk k => { st with breaks := st.breaks ++ [.brk k] }
  | .sectionStart sec k => { st with breaks := st.breaks ++ [.start sec k] }
  | .space n => placeSpaceFlow env st n
  | .needLines _ => st
  | .blank _ => st
  | .noBreak => st
  | .noBreakLines _ => st
  | .keepNext _ _ => st
  | .switchColumns n =>
    let st1 := flushDeferred env st
    if (env.columns = 1 ∧ 0 < typeAreaFree env st1) ∨ (isEmpty st1 = true ∧ st1.column = 0) then
      startSet env st1 n st1.used
    else { nextPage env st1 with columns := n, firstLine := 0 }
  | .restoreColumns =>
    if isEmpty st = true ∧ st.column = 0 ∧ top st = 0 then { st with columns := env.columns, firstLine := 0 }
    else { nextPage env st with columns := env.columns, firstLine := 0 }
  | .adjustLines _ => st
  | .bookPart _ _ _ body => runFlows env st body rest
  | .boxed i kb ka body =>
    let st1 := keep env st (fun s => (kb : Int) + ka + needIn env s noNeed (env.nextNeed body))
    let inBox := runFlows env (openBox { st1 with box := some ⟨i, kb, ka, 0, false⟩ }) body rest
    drainPendingNotes env { inBox with box := none, used := max inBox.used (boxEnd inBox) }
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
      let st1 := if sp + headed ≤ free env st ∨ isEmpty st = true
        then { st with used := st.used + max 0 (min sp (free env st)) }
        else keep env (nextColumn env st) (fun _ => headed)
      placeTable env st1 h rows capt below
    else
      let space : Int := if st.used = top st then 0 else sp0
      let started := if space ≤ free env st then { st with used := st.used + space } else nextColumn env st
      placeTableAcross env started h rows capt below
termination_by (flowWeight f, 0)
decreasing_by all_goals simp_wf; (try subst_vars); apply Prod.Lex.left; simp only [flowWeight]; omega

/-- `placeFlow` of Paginate.hs. -/
def placeFlow (env : Env) (st : St) (f : Flow) (rest : List Flow) : St :=
  match f, env.keptNeed rest with
  | .paragraph kp ls, some n => placeKept env (previousKeep env rest kp) (placeLines env kp) st true ls n
  | .stanza kp vs, some n => placeKept env kp (placeStanza env kp) st true vs n
  | .continued kp ls, some n => placeKept env (previousKeep env rest kp) (placeLines env kp) st false ls n
  | .defTerm ls, some n =>
    let initial := if 0 < env.keepLast rest then st
      else keep env st (fun s => needIn env s ⟨ls.length, noteLinesOf ls⟩ (env.nextNeed rest))
    placeKept env (previousKeep env rest defaultKeep) (placeLines env defaultKeep) initial true ls n
  | f, _ => place env st f rest
termination_by (flowWeight f, 1)
decreasing_by all_goals simp_wf; apply Prod.Lex.right; decide

/-- `step` of Paginate.hs. -/
def step (env : Env) (st : St) (f : Flow) (rest : List Flow) : St :=
  match f with
  | .needLines n => needMore env n st
  -- the continued notes take the room added first (root ADR 0444)
  | .adjustLines k => drainPendingNotes env (adjustLines env (applyBreaks env st) k)
  | .bookPart unit kind retained body =>
    let env' : Env := { env with keepParts := unit, inBookPart := true }
    let plain := flattenParts body
    placeBookPart env (fun s => runFlows env' s body rest) (fun s => runFlows env' s plain rest)
      (if retained = [] then st else applyBreaks env st) unit (some kind) retained (anyNested body)
      ((flowsSlotIds plain).all retained.contains)
  | .noBreakLines 0 => st
  | .noBreakLines _ | .noBreak =>
    if st.seen = false ∨ st.lastDeferred = true then addUnmet .noBreak st else waitFor .noBreak (1, false) st
  | .keepNext n sp =>
    if st.seen = false ∨ st.lastDeferred = true then addUnmet (.keepNext sp) st
    else waitFor (.keepNext sp) (env.nextFirst n rest) st
  | .blank n => if allWaitsFor rest then st else { st with blank := st.blank ++ [n] }
  | .brk k => place env st (.brk k) rest
  | .sectionStart sec k => place env st (.sectionStart sec k) rest
  | .space n => placeSpace env (needBeforeSpaces env (applyBreaks env st)) n
  | f =>
    let stB := applyBreaks env st
    let waiting := waitsBehind stB f
    let st1 := if waiting then checkNoBreak (place env stB f rest)
      else checkNoBreak (placeFlow env (placeBlank env (needBefore env stB (f :: rest)) f rest) f rest)
    let deferred := match f with
      | .figure i _ => st1.deferred.any (deferredFigure i)
      | .pageFigure _ => true
      | _ => false
    let spaces := if waiting ∧ st.breaks = [] then st1.spaces else []
    { st1 with seen := true, lastDeferred := deferred, spaces := spaces }
termination_by (flowWeight f, 2)
decreasing_by
  all_goals simp_wf
  all_goals try subst_vars
  all_goals first
    | (apply Prod.Lex.right; decide)
    | (apply Prod.Lex.left; simp only [flowWeight]; omega)
    | (apply Prod.Lex.left; have := flattenParts_weight body; simp only [flowWeight]; omega)

/-- `go` of the book part in `step`, and `foldBody` of `place`: each
    flow placed, with the flows after it to look ahead to. -/
def runFlows (env : Env) (st : St) (fs : List Flow) (rest : List Flow) : St :=
  match fs with
  | [] => st
  | g :: more => runFlows env (step env st g (more ++ rest)) more rest
termination_by (flowsWeight fs, 3)
decreasing_by
  all_goals simp_wf
  all_goals apply Prod.Lex.left; simp only [flowsWeight]; omega
end

def placeAll (env : Env) (st : St) : List Flow → St
  | [] =>
    let st1 := st.noBreak.foldl (fun s w => addUnmet w.1 s) st
    let st2 := { st1 with breaks := [], need := none, needAt := none, noBreak := [], blank := [] }
    let dropBlanks (s : St) := st1.blank.foldl (fun s' _ => addUnmet .droppedBlank s') s
    if st1.blank = [] then flushDeferred env st2
    else if st2.deferred = [] then flushDeferred env (dropBlanks st2)
    else flushDeferred env (dropBlanks (nextColumn env st2))
  | f :: rest => placeAll env (step env st f rest) rest

/-- `paginateWithin` of Paginate.hs up to the pages it returns. -/
def paginate (env : Env) (flows : List Flow) : St :=
  closePage env (placeAll env (initialState env) flows)

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

mutual
/-- The lines and headings of the flows written. -/
def flowText : Flow → List Slot
  | .paragraph _ ls => ls.map (fun l => .line l.id)
  | .continued _ ls => ls.map (fun l => .line l.id)
  | .defTerm ls => ls.map (fun l => .line l.id)
  | .stanza _ vs => vs.join.map (fun l => .line l.id)
  | .wrapped _ _ beside => beside.map (fun l => .line l.id)
  | .heading _ _ [] => []
  | .heading _ _ (l0 :: ls) => [.heading l0.id (ls.length + 1)]
  | .code _ _ _ _ ls => ls.map (fun l => .codeRow l.id)
  | .table _ h rows capt below => (tableLines h rows capt below).map (fun l => .line l.id)
  | .bookPart _ _ _ body | .boxed _ _ _ body => sourceText body
  | .ruled _ _ _ _ (.lines _ ls) => ls.map (fun l => .line l.id)
  | .ruled _ _ _ _ (.heading _ n ls) => flowText (.heading false n ls)
  | _ => []
termination_by f => sizeOf f
def sourceText : List Flow → List Slot
  | [] => []
  | g :: r => flowText g ++ sourceText r
termination_by fs => sizeOf fs
end

theorem sourceText_append (a b : List Flow) : sourceText (a ++ b) = sourceText a ++ sourceText b := by
  induction a with
  | nil => simp [sourceText]
  | cons x xs ih => simp only [List.cons_append, sourceText, ih, List.append_assoc]

theorem sourceText_flatten (fs : List Flow) : sourceText (flattenParts fs) = sourceText fs := by
  match fs with
  | [] => simp [flattenParts, sourceText]
  | f :: r =>
    have := sourceText_flatten r
    cases f with
    | bookPart u k i b =>
      have := sourceText_flatten b
      simp only [flattenParts, sourceText_append, sourceText, flowText, *]
    | boxed j kb ka b =>
      have := sourceText_flatten b
      simp only [flattenParts, sourceText, flowText, *]
    | _ => simp only [flattenParts, sourceText, *]
termination_by sizeOf fs

theorem text_addUnmet (u : Unmet) (st : St) : text (addUnmet u st) = text st := rfl

theorem text_putSlot_figure (st : St) (n i : Nat) : text (putSlot st n (.figure i)) = text st := by
  simp [text, putSlot, textSlots_append, textSlots]

theorem text_putSlot_wrapped (st : St) (n i : Nat) : text (putSlot st n (.wrapped i)) = text st := by
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

theorem text_openBox (st : St) : text (openBox st) = text st := by unfold openBox; split <;> rfl

theorem text_advance (env : Env) (b : Bool) (st : St) : text (advance env b st) = text st := by
  rw [advance, text_openBox]
  simp only [advanceIn, openColumn]
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

theorem text_startBefore (env : Env) (st : St) (sec : Option Nat) (k : BreakKind) :
    text (startBefore env st sec k) = text st := by
  have h1 : text (match k with
      | .column => if isEmpty st then st else nextColumn env st
      | .page =>
        if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
        else nextPage env (flushDeferred env st)
      | .recto => parityStart env odd st
      | .verso => parityStart env even st) = text st := by
    cases k
    · simp only; split
      · rw [text_flushDeferred]
      · rw [text_nextPage, text_flushDeferred]
    · simp only; split
      · rfl
      · rw [text_nextColumn]
    · exact text_parityStart ..
    · exact text_parityStart ..
  simp only [startBefore]
  split
  · exact h1
  · exact h1

/-- `drainPendingNotes` changes only the notes of the column, their lines
    and the notes continued. -/
theorem drainPendingNotes_eq (env : Env) (st : St) :
    ∃ ns nl ps, drainPendingNotes env st = { st with notes := ns, noteLines := nl, pending := ps } := by
  unfold drainPendingNotes
  split
  · exact ⟨st.notes, st.noteLines, st.pending, rfl⟩
  · exact ⟨_, _, _, rfl⟩

theorem text_drainPendingNotes (env : Env) (st : St) : text (drainPendingNotes env st) = text st := by
  obtain ⟨ns, nl, ps, e⟩ := drainPendingNotes_eq env st
  rw [e]; rfl

theorem text_applyBreaks (env : Env) (st : St) : text (applyBreaks env st) = text st := by
  simp only [applyBreaks]
  suffices ∀ (ks : List Pending) (s : St), text (ks.foldl (applyPending env) s) = text s by
    rw [this]; rfl
  intro ks
  induction ks with
  | nil => intro s; rfl
  | cons k ks ih =>
    intro s; simp only [List.foldl]; rw [ih]
    cases k with
    | brk k => exact text_applyBreakKind ..
    | start sec k => exact text_startBefore ..

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

theorem text_putVerses (env : Env) (st : St) (vs : List (List Line)) :
    text (putVerses env st vs) = text st ++ vs.join.map (fun l => .line l.id) := text_putLines env vs.join st

theorem text_placeStanzaGo (env : Env) (pid : Nat) (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) :
    text (placeStanzaGo env pid kp st isStart vs) = text st ++ vs.join.map (fun l => .line l.id) := by
  match vs with
  | [] => simp [placeStanzaGo]
  | v :: more =>
    have td : ∀ k s, text (putVerses env s ((v :: more).take k)) ++ ((v :: more).drop k).join.map (fun l => .line l.id)
        = text s ++ (v :: more).join.map (fun l => .line l.id) := by
      intro k s
      rw [text_putVerses, List.append_assoc, ← List.map_append, ← join_append', List.take_append_drop]
    unfold placeStanzaGo
    simp only
    split
    · split
      · rw [text_placeStanzaGo env pid { kp with all := false } _ isStart (v :: more), text_addUnmet]
      · rw [text_placeStanzaGo env pid kp _ isStart (v :: more), text_nextColumn]
    · split
      · exact text_putVerses ..
      · split
        · rw [text_placeStanzaGo env pid kp _ false _, text_nextColumn]; exact td _ _
        · split
          · split
            · rw [text_placeStanzaGo env pid kp _ false more, text_shortParts, text_placeLines, List.append_assoc,
                ← List.map_append]
              simp
            · rw [text_placeStanzaGo env pid kp _ false _, text_nextColumn, text_shortParts]; exact td _ _
          · rw [text_placeStanzaGo env pid kp _ isStart (v :: more), text_nextColumn]
termination_by (vs.length, allRank kp, rank env st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; apply Prod.Lex.left; simp_all [allRank]; done)
    | (apply linesLt_rank; apply I4_nextColumn_rank; left; cases e : isEmpty st
       · rfl
       · simp [emptyish, e] at *)

theorem text_placeStanza (env : Env) (kp : Keep) (st : St) (isStart : Bool) (vs : List (List Line)) :
    text (placeStanza env kp st isStart vs) = text st ++ vs.join.map (fun l => .line l.id) := by
  unfold placeStanza; split <;> exact text_placeStanzaGo ..

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

theorem text_nextSpread (env : Env) (t : Nat) (st : St) : text (nextSpread env t st) = text st := by
  by_cases h : (nextPage env st).page < t
  · unfold nextSpread; rw [dif_pos h, text_nextSpread env t (nextPage env st), text_nextPage]
  · unfold nextSpread; rw [dif_neg h, text_nextPage]
termination_by t - st.page
decreasing_by simp_wf; have := nextPage_page_gt env st; omega

theorem text_nextUnit (env : Env) (unit : KeepParts) (st : St) : text (nextUnit env unit st) = text st := by
  cases unit <;> simp only [nextUnit, text_nextColumn, text_nextPage, text_nextSpread]

theorem text_partTrial (env : Env) (runBody runPlain : St → St) (X : List Slot)
    (hb : ∀ s, text (runBody s) = text s ++ X) (hp : ∀ s, text (runPlain s) = text s ++ X)
    (unit : KeepParts) (fits : St → Bool) (nested whole : Bool) (st : St) :
    text (partTrial env runBody runPlain unit fits nested whole st) = text st ++ X := by
  simp only [partTrial]
  repeat' split
  all_goals simp only [text_flushFigures, hb, hp]

/-- Every trial of a book part places the same lines. -/
theorem text_placeBookPart (env : Env) (runBody runPlain : St → St) (X : List Slot)
    (hb : ∀ s, text (runBody s) = text s ++ X) (hp : ∀ s, text (runPlain s) = text s ++ X)
    (initial : St) (unit : KeepParts) (kind : Option Nat) (retained : List Nat) (nested whole : Bool) :
    text (placeBookPart env runBody runPlain initial unit kind retained nested whole) = text initial ++ X := by
  simp only [placeBookPart]
  repeat' split
  all_goals simp only [text_addUnmet, text_partTrial env runBody runPlain X hb hp, hb, text_nextUnit]

theorem text_acrossGo (env : Env) (h capt : List Line) (below retain fresh retried : Bool) (st : St)
    (gs : List (Bool × List Line)) :
    text (acrossGo env h capt below retain fresh retried st gs)
      = text st ++ (gs.bind (·.2)).map (fun l => .line l.id) := by
  match gs with
  | [] => unfold acrossGo; simp
  | (isHeader, ls) :: remaining =>
    by_cases hr : fresh = true ∧ retainsTail env capt below retain isHeader remaining = true
    · unfold acrossGo; rw [dif_pos hr]
      apply text_placeBookPart
      all_goals intro s
      all_goals rw [text_acrossGo env h capt below false true false _ ((isHeader, ls) :: remaining)]
      all_goals congr 1
      all_goals split
      all_goals first | rfl | rw [text_putRepeateds]
    · by_cases h1 : ls.length ≤ env.fitting st ls ∨ isEmpty st = true
      · unfold acrossGo; rw [dif_neg hr, dif_pos h1, text_acrossGo env h capt below retain true false _ remaining,
          text_putLines]
        simp
      · unfold acrossGo; rw [dif_neg hr, dif_neg h1]
        rw [text_acrossGo env h capt below retain false _ _ ((isHeader, ls) :: remaining)]
        congr 1
        split
        · rw [text_putRepeateds, text_nextColumn]
        · rw [text_nextColumn]
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

theorem text_startSet (env : Env) (st : St) (n : Nat) (first : Int) : text (startSet env st n first) = text st := by
  simp only [startSet, closePage]
  by_cases e : st.slots.isEmpty = true ∧ st.notes.isEmpty = true
  · have s : st.slots = [] := by
      cases h : st.slots with
      | nil => rfl
      | cons _ _ => simp [h, List.isEmpty] at e
    simp only [e, and_self, ite_true]
    simp [text, textSlots, s]
  · simp only [e, ite_false]
    simp [text, pagesText_cons, textSlots]

theorem flowText_heading (recto : Bool) (n : Nat) (ls : List Line) :
    flowText (.heading recto n ls) = flowText (.heading false n ls) := by
  cases ls <;> simp [flowText]

/-- The controls not met recorded. -/
theorem addUnmets_eq (ws : List (Unmet × Nat × Nat × Nat × (Nat × Bool))) (st : St) :
    ws.foldl (fun s w => addUnmet w.1 s) st = { st with unmet := st.unmet ++ ws.map (·.1) } := by
  induction ws generalizing st with
  | nil => simp
  | cons w ws ih => simp only [List.foldl]; rw [ih]; simp [addUnmet]

theorem checkNoBreak_aux (st : St) (c : Prop) [Decidable c] (ws : List (Unmet × Nat × Nat × Nat × (Nat × Bool))) :
    ∃ u, ({ (if c then st else ws.foldl (fun s w => addUnmet w.1 s) st) with noBreak := [] } : St)
      = { st with unmet := u, noBreak := [] } := by
  split
  · exact ⟨st.unmet, rfl⟩
  · rw [addUnmets_eq]; exact ⟨_, rfl⟩

/-- `checkNoBreak` changes only the controls not met and those waiting. -/
theorem checkNoBreak_eq (st : St) :
    checkNoBreak st = st ∨ ∃ u, checkNoBreak st = { st with unmet := u, noBreak := [] } := by
  unfold checkNoBreak
  split
  · exact Or.inl rfl
  · exact Or.inr (checkNoBreak_aux st _ _)

theorem waitFor_eq (u : Unmet) (k : Nat × Bool) (st : St) : ∃ w, waitFor u k st = { st with noBreak := w } := by
  unfold waitFor; split
  · exact ⟨_, rfl⟩
  · exact ⟨_, rfl⟩

theorem text_checkNoBreak (st : St) : text (checkNoBreak st) = text st := by
  rcases checkNoBreak_eq st with e | ⟨u, e⟩ <;> rw [e]; rfl

theorem text_waitFor (u : Unmet) (k : Nat × Bool) (st : St) : text (waitFor u k st) = text st := by
  obtain ⟨w, e⟩ := waitFor_eq u k st; rw [e]; rfl

theorem text_placeKept {α : Type} (env : Env) (kp : Keep) (placeIn : St → Bool → List α → St)
    (T : List α → List Slot) (hT : ∀ a b, T (a ++ b) = T a ++ T b)
    (hp : ∀ s b xs, text (placeIn s b xs) = text s ++ T xs)
    (st : St) (isStart : Bool) (ls : List α) (n : Need) :
    text (placeKept env kp placeIn st isStart ls n) = text st ++ T ls := by
  have split2 : ∀ s, text (placeIn (placeIn s isStart (ls.take (ls.length - keptCut kp ls.length)))
      (isStart && (ls.take (ls.length - keptCut kp ls.length)).isEmpty) (ls.drop (ls.length - keptCut kp ls.length)))
      = text s ++ T ls := by
    intro s
    rw [hp, hp, List.append_assoc, ← hT, List.take_append_drop]
  simp only [placeKept]
  apply text_ite
  · exact hp ..
  · apply text_ite
    · exact split2 st
    · apply text_ite
      · exact hp ..
      · rw [hp, text_nextColumn, hp, List.append_assoc, ← hT, List.take_append_drop]

mutual
theorem text_putRuledLines (env : Env) (k2 : Nat) (ls : List Line) (st : St) :
    text (putRuledLines env k2 st ls) = text st ++ ls.map (fun l => .line l.id) := by
  induction ls generalizing st with
  | nil => simp [putRuledLines]
  | cons l ls ih =>
    simp only [putRuledLines, List.map]; rw [ih]
    simp [text, putLineKeeping, textSlots_append, textSlots]

theorem text_commitRuled (env : Env) (st : St) (body : RuledBody) (p : Plan) :
    text (commitRuled env st body p) = text st ++ flowText (.ruled 0 false false false body) := by
  cases body with
  | lines kp ls => simp only [commitRuled, flowText]; exact text_putRuledLines ..
  | heading r n ls =>
    simp only [commitRuled, flowText]
    show text (putBlock env _ n ls) = _
    rw [text_putBlock]; simp [flowText]; rfl

theorem text_splitRuled (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow) :
    text (splitRuled env st i b a body rest) = text st ++ flowText (.ruled 0 false false false body) := by
  have h0 : text (if isEmpty st = true then st else nextColumn env st) = text st := text_ite rfl (text_nextColumn ..)
  cases body with
  | lines kp ls => simp only [splitRuled, flowText]; rw [text_placeLines, h0]
  | heading r n ls =>
    simp only [splitRuled]
    generalize (if isEmpty st = true then st else nextColumn env st) = s at h0
    split
    · rw [text_commitRuled, h0]
    · split
      · rw [text_commitRuled, h0]
      · rw [text_putBlock, h0]; simp [flowText]

theorem text_flushJoin (env : Env) (st : St) : text (flushJoin env st) = text st := by
  unfold flushJoin; split <;> rfl

theorem text_placeRuledFresh (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow) :
    text (placeRuledFresh env st i b a body rest) = text st ++ flowText (.ruled 0 false false false body) := by
  have h1 : text (if body.recto = true then parityStart env odd st else st) = text st :=
    text_ite (text_parityStart ..) rfl
  simp only [placeRuledFresh]
  generalize (if body.recto = true then parityStart env odd st else st) = s1 at h1
  have h2 : ∀ s2 : St, text s2 = text st →
      text (match settleRuled env s2 i b a body rest none with
        | some placed => placed
        | none =>
          if isEmpty s2 = true then splitRuled env s2 i b a body rest
          else
            match settleRuled env (nextColumn env s2) i b a body rest none with
            | some placed => placed
            | none => splitRuled env (nextColumn env s2) i b a body rest) = text st ++ flowText (.ruled 0 false false false body) := by
    intro s2 e
    apply settle_or (fun r => text r = _)
    · intro _ _ _; rw [text_commitRuled, e]
    · split
      · rw [text_splitRuled, e]
      · apply settle_or (fun r => text r = _)
        · intro _ _ _; rw [text_commitRuled, text_nextColumn, e]
        · rw [text_splitRuled, text_nextColumn, e]
  apply h2
  cases body with
  | heading r n ls => cases r <;> simp only [ruledKeep] <;> first | exact (text_keep ..).trans h1 | exact h1
  | lines kp ls =>
    simp only [ruledKeep]
    split
    · split
      · exact (text_keep ..).trans h1
      · exact h1
    · exact h1

theorem text_placeRuled (env : Env) (st : St) (i : Nat) (b a j : Bool) (body : RuledBody) (rest : List Flow) :
    text (placeRuled env st i b a j body rest) = text st ++ flowText (.ruled i b a j body) := by
  have e : flowText (.ruled i b a j body) = flowText (.ruled 0 false false false body) := by cases body <;> simp [flowText]
  rw [e]
  unfold placeRuled
  split
  · apply joined_or (fun r => text r = _)
    · intro _ _ _; exact text_commitRuled ..
    · rw [text_placeRuledFresh, text_flushJoin]
  · exact text_placeRuledFresh ..

theorem text_place (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    text (place env st f rest) = text st ++ flowText f := by
  cases f with
  | paragraph kp ls => simp only [place, flowText]; exact text_placeLines ..
  | stanza kp vs => simp only [place, flowText]; exact text_placeStanza ..
  | ruled i b a j body => simp only [place]; exact text_placeRuled ..
  | wrapped i n beside =>
    simp only [place, flowText]
    split <;>
    · show text (placeLines env defaultKeep _ false beside) = _
      rw [text_placeLines, text_putSlot_wrapped, text_keep, text_flushFigures]
  | continued kp ls => simp only [place, flowText]; exact text_placeLines ..
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
  | sectionStart sec k => simp only [place, flowText, List.append_nil]; rfl
  | space n => simp only [place, flowText, List.append_nil]; exact text_placeSpaceFlow ..
  | needLines n => simp [place, flowText]
  | blank n => simp [place, flowText]
  | noBreak => simp [place, flowText]
  | noBreakLines n => simp [place, flowText]
  | keepNext n => simp [place, flowText]
  | switchColumns n =>
    simp only [place, flowText, List.append_nil]
    apply text_ite
    · rw [text_startSet, text_flushDeferred]
    · show text (nextPage env _) = _
      rw [text_nextPage, text_flushDeferred]
  | restoreColumns =>
    simp only [place, flowText, List.append_nil]
    apply text_ite
    · rfl
    · show text (nextPage env _) = _
      rw [text_nextPage]
  | adjustLines k => simp [place, flowText]
  | bookPart u k r body => simp only [place, flowText]; exact text_runFlows env st body rest
  | boxed i kb ka body =>
    simp only [place, flowText]
    show text (drainPendingNotes env _) = _
    rw [text_drainPendingNotes]
    show text (runFlows env _ body rest) = _
    rw [text_runFlows, text_openBox]
    show text (keep env st _) ++ _ = _
    rw [text_keep]
  | code g c first cont ls => simp only [place, flowText]; exact text_placeCode ..
  | defTerm ls =>
    simp only [place]
    split
    · rw [text_placeLines, text_keep]; simp [flowText]
    · rw [text_placeLines]; simp [flowText]
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
termination_by (flowWeight f, 0)
decreasing_by all_goals simp_wf; (try subst_vars); apply Prod.Lex.left; simp only [flowWeight]; omega

theorem text_placeFlow (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    text (placeFlow env st f rest) = text st ++ flowText f := by
  have pl : ∀ kp s b xs, text (placeLines env kp s b xs) = text s ++ xs.map (fun l => .line l.id) :=
    fun kp s b xs => text_placeLines env kp s b xs
  unfold placeFlow
  split
  · simp only [flowText]; exact text_placeKept env _ _ _ (fun a b => List.map_append _ a b) (pl _) st true _ _
  · simp only [flowText]
    exact text_placeKept env _ _ (fun vs => vs.join.map (fun l => .line l.id))
      (fun a b => by simp only [join_append', List.map_append]) (fun s b xs => text_placeStanza env _ s b xs) st true _ _
  · simp only [flowText]; exact text_placeKept env _ _ _ (fun a b => List.map_append _ a b) (pl _) st false _ _
  · simp only [flowText]
    rw [text_placeKept env _ _ _ (fun a b => List.map_append _ a b) (pl _)]
    congr 1
    apply text_ite
    · rfl
    · exact text_keep ..
  · exact text_place ..
termination_by (flowWeight f, 1)
decreasing_by all_goals simp_wf; apply Prod.Lex.right; decide

theorem text_step (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    text (step env st f rest) = text st ++ flowText f := by
  have general : ∀ (a : Bool) (b : List (Nat × Int)), text ({ (if waitsBehind (applyBreaks env st) f
      then checkNoBreak (place env (applyBreaks env st) f rest)
      else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest))
      with seen := true, lastDeferred := a, spaces := b } : St) = text st ++ flowText f := by
    intro _ _
    show text (if waitsBehind (applyBreaks env st) f then checkNoBreak (place env (applyBreaks env st) f rest)
      else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest))
      = _
    apply text_ite
    · rw [text_checkNoBreak, text_place, text_applyBreaks]
    · rw [text_checkNoBreak, text_placeFlow, text_placeBlank, text_needBefore, text_applyBreaks]
  have ctl : ∀ (u : Unmet) (k : Nat × Bool), text (if st.seen = false ∨ st.lastDeferred = true then addUnmet u st
      else waitFor u k st) = text st := by
    intro u k; apply text_ite
    · rfl
    · exact text_waitFor ..
  cases f with
  | needLines n => simp only [step, flowText, List.append_nil]; exact text_needMore ..
  | bookPart u k r body =>
    simp only [step, flowText]
    rw [text_placeBookPart env _ _ (sourceText body)]
    · split
      · rfl
      · rw [text_applyBreaks]
    · intro s; exact text_runFlows _ s body rest
    · intro s; rw [text_runFlows, sourceText_flatten]
  | adjustLines k =>
    simp only [step, flowText, List.append_nil]
    rw [text_drainPendingNotes]
    simp only [adjustLines]
    rw [← text_applyBreaks env st]
    split <;> rfl
  | noBreak => simp only [step, flowText, List.append_nil]; exact ctl _ _
  | noBreakLines n =>
    cases n with
    | zero => simp [step, flowText]
    | succ m => simp only [step, flowText, List.append_nil]; exact ctl _ _
  | keepNext n => simp only [step, flowText, List.append_nil]; exact ctl _ _
  | blank n =>
    simp only [step, flowText, List.append_nil]
    apply text_ite <;> rfl
  | brk k => simp only [step]; exact text_place env st (.brk k) rest
  | sectionStart sec k => simp only [step]; exact text_place env st (.sectionStart sec k) rest
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

theorem text_runFlows (env : Env) (st : St) (fs : List Flow) (rest : List Flow) :
    text (runFlows env st fs rest) = text st ++ sourceText fs := by
  match fs with
  | [] => unfold runFlows; simp [sourceText]
  | g :: more =>
    unfold runFlows
    rw [text_runFlows env _ more rest, text_step]
    simp [sourceText, List.append_assoc]
termination_by (flowsWeight fs, 3)
decreasing_by
  all_goals simp_wf
  all_goals apply Prod.Lex.left; simp only [flowsWeight]; omega
end

theorem text_placeAll (env : Env) (flows : List Flow) (st : St) :
    text (placeAll env st flows) = text st ++ sourceText flows := by
  induction flows generalizing st with
  | nil =>
    simp only [placeAll, sourceText, List.append_nil]
    rw [addUnmets_eq]
    apply text_ite
    · rw [text_flushDeferred]; rfl
    · apply text_ite
      · rw [text_flushDeferred, text_dropBlanks]; rfl
      · rw [text_flushDeferred, text_dropBlanks, text_nextColumn]; rfl
  | cons f rest ih =>
    simp only [placeAll]
    rw [ih, text_step]
    simp [sourceText, List.append_assoc]

/-- Root ADR 0352 invariant 5 for the lines: the pages of the pagination
    hold every line of the paragraphs, the terms and the tables, every
    heading and every row of the code blocks written, each once, in the
    order written.  The header lines a table repeats in a column gone on
    to are slots of their own, not lines of the text. -/
theorem I5_paginate_text (env : Env) (flows : List Flow) :
    pagesText (paginate env flows).done = sourceText flows := by
  have h := text_placeAll env flows (initialState env)
  have i : text (initialState env) = [] := rfl
  rw [i, List.nil_append] at h
  simp only [paginate, closePage]
  generalize placeAll env (initialState env) flows = st at h
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
closed (README.md).  It also needs a capacity of 1 line or more, the
input of root ADR 0352, so that blank lines add no negative lines, and
a footnote separator of 0 lines or more, so that the footnote lines of
a column never decrease. -/

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

mutual
def flowFigs : Flow → List Slot
  | .figure i _ => [.figure i]
  | .pageFigure i => [.pageFigure i]
  | .bookPart _ _ _ body | .boxed _ _ _ body => sourceFigs body
  | _ => []
termination_by f => sizeOf f
def sourceFigs : List Flow → List Slot
  | [] => []
  | g :: r => flowFigs g ++ sourceFigs r
termination_by fs => sizeOf fs
end

theorem sourceFigs_append (a b : List Flow) : sourceFigs (a ++ b) = sourceFigs a ++ sourceFigs b := by
  induction a with
  | nil => simp [sourceFigs]
  | cons x xs ih => simp only [List.cons_append, sourceFigs, ih, List.append_assoc]

theorem sourceFigs_flatten (fs : List Flow) : sourceFigs (flattenParts fs) = sourceFigs fs := by
  match fs with
  | [] => simp [flattenParts, sourceFigs]
  | f :: r =>
    have := sourceFigs_flatten r
    cases f with
    | bookPart u k i b =>
      have := sourceFigs_flatten b
      simp only [flattenParts, sourceFigs_append, sourceFigs, flowFigs, *]
    | boxed j kb ka b =>
      have := sourceFigs_flatten b
      simp only [flattenParts, sourceFigs, flowFigs, *]
    | _ => simp only [flattenParts, sourceFigs, *]
termination_by sizeOf fs

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
  /-- The first line of the set of columns is 0 or more, or the set
      keeps footnote lines at the foot of each of its columns. -/
  first : 0 ≤ st.firstLine ∨ 0 < st.reserved
  deferred : deferredOk st.deferred

/-- The lines used are negative only below footnote lines, and a column
    that holds a figure has used a line or more or has footnote lines;
    the footnote lines of a column never decrease. -/
structure Inv (st : St) : Prop where
  weak : Weak st
  used : 0 ≤ st.used ∨ 0 < st.noteLines
  fig : figSlots st.slots = [] ∨ 1 ≤ st.used ∨ 0 < st.noteLines
  /-- No rule after waits for the next block to share its area. -/
  join : st.join = none

/-- `a` comes before `b`: an earlier page, or an earlier column of the
    same page. -/
def posLt (a b : St) : Prop := a.page < b.page ∨ (a.page = b.page ∧ a.column < b.column)

theorem posLt_trans {a b c : St} (h1 : posLt a b) (h2 : posLt b c) : posLt a c := by
  simp only [posLt] at *; omega

/-- `r` keeps the column of `st` as it is. -/
def Same (st r : St) : Prop :=
  r.slots = st.slots ∧ r.used = st.used ∧ r.page = st.page ∧ r.column = st.column ∧ r.firstLine = st.firstLine
    ∧ r.deferred = st.deferred ∧ r.noteLines = st.noteLines ∧ r.adjust = st.adjust ∧ r.reserved = st.reserved
    ∧ r.join = st.join

theorem Same.trans' {a b c : St} (h1 : Same a b) (h2 : Same b c) : Same a c := by
  obtain ⟨a1, a2, a3, a4, a5, a6, a7, a8, a9, a10⟩ := h1
  obtain ⟨b1, b2, b3, b4, b5, b6, b7, b8, b9, b10⟩ := h2
  exact ⟨b1.trans a1, b2.trans a2, b3.trans a3, b4.trans a4, b5.trans a5, b6.trans a6, b7.trans a7, b8.trans a8,
    b9.trans a9, b10.trans a10⟩

theorem Same.weak {st r : St} (s : Same st r) (w : Weak st) : Weak r := by
  obtain ⟨_, _, _, _, a5, a6, _, _, a9, _⟩ := s
  exact ⟨a5 ▸ a9 ▸ w.first, a6 ▸ w.deferred⟩

theorem Same.inv {st r : St} (s : Same st r) (i : Inv st) : Inv r := by
  have w := s.weak i.weak
  obtain ⟨a1, a2, _, _, _, _, a7, _, _, a10⟩ := s
  exact ⟨w, a2 ▸ a7 ▸ i.used, a1 ▸ a2 ▸ a7 ▸ i.fig, a10 ▸ i.join⟩

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
    (fs : figSlots r.slots = figSlots st.slots ∨ (1 ≤ n ∧ ∃ x, figSlots r.slots = figSlots st.slots ++ x))
    (j : r.join = st.join := by first | rfl | assumption) : Inv r := by
  refine ⟨w, ?_, ?_, j ▸ h.join⟩
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

theorem openBox_join (st : St) : (openBox st).join = st.join := by unfold openBox; split <;> rfl

theorem inv_openBox (st : St) (h : Inv st) : Inv (openBox st) := by
  have u := openBox_used st
  refine inv_addUsed h ⟨?_, ?_⟩ ((openBox st).used - st.used) (by omega) (by omega)
    (by rw [openBox_noteLines]; exact Int.le_refl _) (Or.inl (by rw [openBox_slots])) (openBox_join st)
  · rw [openBox_firstLine, openBox_reserved]; exact h.weak.first
  · rw [openBox_deferred]; exact h.weak.deferred

theorem putSlot_inv (st : St) (n i : Nat) (h : Inv st) (hn : 1 ≤ n) : Inv (putSlot st n (.figure i)) :=
  inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ n (by omega) rfl (Int.le_refl _)
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
      · exact ⟨⟨h.weak.first, hw⟩, h.used, h.fig, h.join⟩
    | pageFigure i => exact ⟨⟨h.weak.first, hw⟩, h.used, h.fig, h.join⟩

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

theorem figs_openBox (st : St) : figs (openBox st) = figs st := by unfold openBox; split <;> rfl

theorem advance_figs (env : Env) (b : Bool) (st : St) : figs (advance env b st) = figs st := by
  rw [advance, figs_openBox]
  simp only [advanceIn, openColumn]
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
  rw [advance, openBox_page]
  simp only [advanceIn, openColumn]
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
  rw [advance]; apply inv_openBox
  simp only [advanceIn, openColumn]
  obtain ⟨_, f2, _, _, f5, f6⟩ := advanceFresh_figs env b st
  have okTurned : deferredOk (advanceTurned b st).2 := by
    unfold advanceTurned; split
    · exact deferredOk_spanTurned _ w.deferred
    · exact w.deferred
  have fa : (advanceFresh env b st).adjust = (if b then 0 else st.setAdjust) := rfl
  have fr' : (advanceFresh env b st).reserved = (if b then 0 else st.reserved) := rfl
  have fn : (advanceFresh env b st).noteLines = (if b then 0 else st.reserved) := rfl
  have fj : (advanceFresh env b st).join = none := rfl
  generalize advanceFresh env b st = fr at f2 f5 f6 fa fr' fn fj
  obtain ⟨_, p2, _⟩ := pageFigures_page env (advanceTurned b st).1 fr
  have pf := pageFigures_fields env (advanceTurned b st).1 fr
  have p9 := pageFigures_join env (advanceTurned b st).1 fr
  generalize (advanceTurned b st).1.foldl (pageFigure env) fr = pg at p2 pf p9
  obtain ⟨_, c2, _, c4, c5⟩ := carryAll_frame env st.pending pg
  have c6 := carryAll_adjust env st.pending pg
  have c7 := carryAll_reserved env st.pending pg
  have c9 : (st.pending.foldl (carryNote env) pg).join = pg.join := carryAll_join env st.pending pg
  generalize st.pending.foldl (carryNote env) pg = cn at c2 c4 c5 c6 c7 c9
  have w1 := w.first
  have base : Inv { cn with deferred := [] } := by
    refine ⟨⟨?_, trivial⟩, ?_, ?_, ?_⟩
    · show 0 ≤ cn.firstLine ∨ 0 < cn.reserved
      rw [c5, pf.2.2.2.2.2.1, f6, c7.1, pf.2.2.2.2.2.2.1, fr']; cases b <;> simp <;> omega
    · show 0 ≤ cn.used ∨ 0 < cn.noteLines
      rw [c4, pf.2.2.2.2.1, f5]
      have c8 : 0 < pg.noteLines → 0 < cn.noteLines := c7.2
      rw [pf.2.2.2.2.2.2.2.1, fn] at c8
      cases b
      · simp at c8 ⊢; omega
      · simp
    · left; show figSlots cn.slots = []; rw [c2, p2, f2]; rfl
    · show cn.join = none; rw [c9, p9, fj]
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
  · unfold keep; rw [dif_neg h]; exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
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
  ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩

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

theorem startBefore_figs (env : Env) (st : St) (sec : Option Nat) (k : BreakKind) (h : Inv st) :
    figs (startBefore env st sec k) = figs st ∧ Inv (startBefore env st sec k) := by
  have h1 : figs (match k with
      | .column => if isEmpty st then st else nextColumn env st
      | .page =>
        if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
        else nextPage env (flushDeferred env st)
      | .recto => parityStart env odd st
      | .verso => parityStart env even st) = figs st ∧ Inv (match k with
      | .column => if isEmpty st then st else nextColumn env st
      | .page =>
        if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
        else nextPage env (flushDeferred env st)
      | .recto => parityStart env odd st
      | .verso => parityStart env even st) := by
    obtain ⟨f0, i0, _⟩ := flushDeferred_figs env st h
    cases k
    · simp only; split
      · exact ⟨f0, i0⟩
      · exact ⟨(figs_nextPage env _).trans f0, inv_nextPage env _ i0⟩
    · simp only; split
      · exact ⟨rfl, h⟩
      · exact ⟨figs_nextColumn env st, inv_nextColumn env st h⟩
    · exact parityStart_figs env odd st h
    · exact parityStart_figs env even st h
  simp only [startBefore]
  split
  · exact ⟨h1.1, ⟨⟨h1.2.weak.first, h1.2.weak.deferred⟩, h1.2.used, h1.2.fig, h1.2.join⟩⟩
  · exact h1

theorem figs_drainPendingNotes (env : Env) (st : St) : figs (drainPendingNotes env st) = figs st := by
  obtain ⟨ns, nl, ps, e⟩ := drainPendingNotes_eq env st
  rw [e]; rfl

theorem drainPendingNotes_noteLines (env : Env) (st : St) (hs : 0 ≤ env.separator) :
    st.noteLines ≤ (drainPendingNotes env st).noteLines := by
  have : 0 ≤ drainSep env st := by unfold drainSep; split <;> omega
  unfold drainPendingNotes
  split
  · exact Int.le_refl _
  · dsimp only; omega

theorem inv_drainPendingNotes (env : Env) (st : St) (hs : 0 ≤ env.separator) (h : Inv st) :
    Inv (drainPendingNotes env st) := by
  have le := drainPendingNotes_noteLines env st hs
  obtain ⟨ns, nl, ps, e⟩ := drainPendingNotes_eq env st
  rw [e] at le ⊢
  change st.noteLines ≤ nl at le
  refine ⟨⟨h.weak.first, h.weak.deferred⟩, ?_, ?_, h.join⟩
  · rcases h.used with u | u
    · exact Or.inl u
    · exact Or.inr (by show 0 < nl; omega)
  · rcases h.fig with u | u | u
    · exact Or.inl u
    · exact Or.inr (Or.inl u)
    · exact Or.inr (Or.inr (by show 0 < nl; omega))

theorem applyBreaks_figs (env : Env) (st : St) (h : Inv st) :
    figs (applyBreaks env st) = figs st ∧ Inv (applyBreaks env st) := by
  simp only [applyBreaks]
  suffices ∀ (ks : List Pending) (s : St), Inv s →
      figs (ks.foldl (applyPending env) s) = figs s ∧ Inv (ks.foldl (applyPending env) s) by
    exact this _ _ ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩
  intro ks
  induction ks with
  | nil => intro s i; exact ⟨rfl, i⟩
  | cons k ks ih =>
    intro s i
    simp only [List.foldl]
    have one : figs (applyPending env s k) = figs s ∧ Inv (applyPending env s k) := by
      cases k with
      | start sec k => exact startBefore_figs env s sec k i
      | brk k =>
      simp only [applyPending]
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
  · exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  · split
    · dsimp only; split
      · exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
      · exact moves_nextColumn env _ ⟨w.first, w.deferred⟩
    · exact keep_moves env _ _ ⟨w.first, w.deferred⟩

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
  · exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  · split
    · exact moves_same ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
    · split
      · exact applyNeed_moves env _ ⟨w.first, w.deferred⟩
      · have m := applyNeed_moves env { st with needAt := none } ⟨w.first, w.deferred⟩
        rcases m with sm | ⟨i, p⟩
        · exact moves_same sm
        · exact Or.inr ⟨⟨⟨i.weak.first, i.weak.deferred⟩, i.used, i.fig, i.join⟩, p⟩

theorem figs_needBeforeSpace (env : Env) (st : St) : figs (needBeforeSpace env st) = figs st := by
  unfold needBeforeSpace
  split
  · rfl
  · repeat' split
    all_goals first | rfl | (rw [figs_applyNeed]; rfl) | (show figs (applyNeed env _) = _; rw [figs_applyNeed]; rfl)

theorem inv_placeSpaceFlow (env : Env) (st : St) (n : Nat) (h : Inv st) : Inv (placeSpaceFlow env st n) := by
  unfold placeSpaceFlow; split
  · exact h
  · exact inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ _ (Int.le_max_left ..) rfl
      (Int.le_refl _) (Or.inl rfl)

theorem inv_placeSpace (env : Env) (st : St) (n : Nat) (h : Inv st) : Inv (placeSpace env st n) := by
  have i := inv_placeSpaceFlow env st n h
  exact ⟨⟨i.weak.first, i.weak.deferred⟩, i.used, i.fig, i.join⟩

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
  have m := needBeforeSpace_moves env { st with used := st.used - k } ⟨h.weak.first, h.weak.deferred⟩
  simp only
  generalize needBeforeSpace env { st with used := st.used - k } = st1 at m
  split
  · rename_i e
    rcases m with ⟨s1, s2, _, _, s5, s6, s7, _, s9, s10⟩ | ⟨_, p⟩
    · have u : st1.used + k = st.used := by rw [s2]; show st.used - k + k = st.used; omega
      refine ⟨⟨?_, ?_⟩, ?_, ?_, ?_⟩
      · show 0 ≤ st1.firstLine ∨ 0 < st1.reserved; rw [s5, s9]; exact h.weak.first
      · show deferredOk st1.deferred; rw [s6]; exact h.weak.deferred
      · show 0 ≤ st1.used + k ∨ 0 < st1.noteLines; rw [u, s7]; exact h.used
      · show figSlots st1.slots = [] ∨ 1 ≤ st1.used + k ∨ 0 < st1.noteLines; rw [u, s1, s7]; exact h.fig
      · show st1.join = none; rw [s10]; exact h.join
    · exfalso; simp only [posLt] at p; omega
  · rename_i e
    rcases m with ⟨_, _, s3, s4, _, _, _, _, _, _⟩ | ⟨i, _⟩
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
    fun _ _ => ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩
  unfold needMore
  split
  · split
    · exact ⟨rfl, h⟩
    · exact needAfterSpaces_figs env _ (h' _ _)
  · exact needAfterSpaces_figs env _ (h' _ _)

theorem needBefore_figs (env : Env) (st : St) (flows : List Flow) (h : Inv st) :
    figs (needBefore env st flows) = figs st ∧ Inv (needBefore env st flows) := by
  have w : ∀ a b, Weak { st with need := a, needAt := b } := fun _ _ => ⟨h.weak.first, h.weak.deferred⟩
  have i : ∀ a b, Inv { st with need := a, needAt := b } :=
    fun _ _ => ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩
  have i' : Inv { st with needAt := none } := ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩
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
  | cons _ _ ih => exact ih (addUnmet .droppedBlank st) ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩

theorem blankTail (total : Int) (ht : 0 ≤ total) (blanks : List Nat) (s2 : St) (X : List Slot)
    (h : Inv s2) (f : figs s2 = X) :
    figs (if s2.used = top s2 then blanks.foldl (fun s _ => addUnmet .droppedBlank s) { s2 with blank := [] }
      else { s2 with used := s2.used + total, blank := [] }) = X ∧
    Inv (if s2.used = top s2 then blanks.foldl (fun s _ => addUnmet .droppedBlank s) { s2 with blank := [] }
      else { s2 with used := s2.used + total, blank := [] }) := by
  split
  · have := dropBlanks_figs blanks { s2 with blank := [] } ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩
    exact ⟨this.1.trans f, this.2⟩
  · exact ⟨f, inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ total ht rfl (Int.le_refl _)
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
  exact inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ 1 (by decide) rfl
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
    exact inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ n (Int.ofNat_nonneg n) rfl nl
      (Or.inl (by simp [putBlock, figSlots_append, figSlots]))

theorem shortParts_figs (us : List Unmet) (st : St) (h : Inv st) :
    figs (us.foldl (fun s u => addUnmet u s) st) = figs st ∧ Inv (us.foldl (fun s u => addUnmet u s) st) := by
  induction us generalizing st with
  | nil => exact ⟨rfl, h⟩
  | cons u _ ih => exact ih (addUnmet u st) ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩

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
            (l :: ls') ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩
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

theorem putVerses_figs (env : Env) (hs : 0 ≤ env.separator) (vs : List (List Line)) (st : St) (h : Inv st) :
    figs (putVerses env st vs) = figs st ∧ Inv (putVerses env st vs) := putLines_figs env hs vs.join st h

theorem putSlot_code_figs (st : St) (n : Nat) (rows : List Nat) (h : Inv st) :
    figs (putSlot st n (.code rows)) = figs st ∧ Inv (putSlot st n (.code rows)) := by
  refine ⟨by simp [figs, putSlot, figSlots_append, figSlots], ?_⟩
  exact inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ n (Int.ofNat_nonneg n) rfl (Int.le_refl _)
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

theorem placeStanzaGo_figs (env : Env) (hs : 0 ≤ env.separator) (pid : Nat) (kp : Keep) (st : St) (isStart : Bool)
    (vs : List (List Line)) (h : Inv st) :
    figs (placeStanzaGo env pid kp st isStart vs) = figs st ∧ Inv (placeStanzaGo env pid kp st isStart vs) := by
  match vs with
  | [] => unfold placeStanzaGo; exact ⟨rfl, h⟩
  | v :: more =>
    unfold placeStanzaGo
    simp only
    split
    · split
      · exact placeStanzaGo_figs env hs pid { kp with all := false } _ isStart (v :: more) ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩
      · have := placeStanzaGo_figs env hs pid kp _ isStart (v :: more) (inv_nextColumn env st h)
        rw [figs_nextColumn] at this; exact this
    · split
      · exact putVerses_figs env hs _ st h
      · split
        · have p := putVerses_figs env hs ((v :: more).take (stanzaK2 env kp st isStart (v :: more))) st h
          have := placeStanzaGo_figs env hs pid kp _ false
            ((v :: more).drop (stanzaK2 env kp st isStart (v :: more))) (inv_nextColumn env _ p.2)
          rw [figs_nextColumn, p.1] at this; exact this
        · split
          · split
            · have p := placeLines_figs env hs defaultKeep st isStart v h
              have q := shortParts_figs (shortVerse kp pid (v :: more).length more) _ p.2
              have := placeStanzaGo_figs env hs pid kp _ false more q.2
              rw [q.1, p.1] at this; exact this
            · have p := putVerses_figs env hs ((v :: more).take
                (stanzaK0 env st (v :: more))) st h
              have q := shortParts_figs (shortParts kp pid true isStart (v :: more).length
                (stanzaK0 env st (v :: more))) _ p.2
              have := placeStanzaGo_figs env hs pid kp _ false
                ((v :: more).drop (stanzaK0 env st (v :: more))) (inv_nextColumn env _ q.2)
              rw [figs_nextColumn, q.1, p.1] at this; exact this
          · have := placeStanzaGo_figs env hs pid kp _ isStart (v :: more) (inv_nextColumn env st h)
            rw [figs_nextColumn] at this; exact this
termination_by (vs.length, allRank kp, rank env st)
decreasing_by
  all_goals simp_wf
  all_goals first
    | (apply Prod.Lex.left; omega)
    | (apply Prod.Lex.right; apply Prod.Lex.left; simp_all [allRank]; done)
    | (apply linesLt_rank; apply I4_nextColumn_rank; left; cases e : isEmpty st
       · rfl
       · simp [emptyish, e] at *)

theorem placeStanza_figs (env : Env) (hs : 0 ≤ env.separator) (kp : Keep) (st : St) (isStart : Bool)
    (vs : List (List Line)) (h : Inv st) :
    figs (placeStanza env kp st isStart vs) = figs st ∧ Inv (placeStanza env kp st isStart vs) := by
  unfold placeStanza; split <;> exact placeStanzaGo_figs env hs _ kp st isStart vs h

/-! ### One flow and the whole -/

mutual
/-- A figure flow is at least one line high, in a book part too. -/
def figureOk : Flow → Prop
  | .figure _ n => 1 ≤ n
  | .bookPart _ _ _ body | .boxed _ _ _ body => figuresOk body
  | _ => True
termination_by f => sizeOf f
def figuresOk : List Flow → Prop
  | [] => True
  | g :: r => figureOk g ∧ figuresOk r
termination_by fs => sizeOf fs
end

theorem figuresOk_append (a b : List Flow) (ha : figuresOk a) (hb : figuresOk b) : figuresOk (a ++ b) := by
  induction a with
  | nil => exact hb
  | cons x xs ih =>
    simp only [List.cons_append, figuresOk] at ha ⊢
    exact ⟨ha.1, ih ha.2⟩

theorem figuresOk_flatten (fs : List Flow) (h : figuresOk fs) : figuresOk (flattenParts fs) := by
  match fs with
  | [] => simp [flattenParts, figuresOk]
  | f :: r =>
    simp only [figuresOk] at h
    have := figuresOk_flatten r h.2
    cases f with
    | bookPart u k i b =>
      have hb : figuresOk b := by have := h.1; simp only [figureOk] at this; exact this
      have := figuresOk_flatten b hb
      simp only [flattenParts]; exact figuresOk_append _ _ (by assumption) (by assumption)
    | boxed j kb ka b =>
      have hb : figuresOk b := by have := h.1; simp only [figureOk] at this; exact this
      have := figuresOk_flatten b hb
      simp only [flattenParts, figuresOk, figureOk]; exact ⟨by assumption, by assumption⟩
    | _ => simp only [flattenParts, figuresOk]; exact ⟨h.1, by assumption⟩
termination_by sizeOf fs

theorem flushFigures_figs (env : Env) (st : St) (h : Inv st) :
    figs (flushFigures env st) = figs st ∧ Inv (flushFigures env st) := by
  by_cases c : st.deferred = []
  · unfold flushFigures; rw [dif_pos c]; exact ⟨rfl, h⟩
  · unfold flushFigures; rw [dif_neg c]
    have := flushFigures_figs env (nextColumn env st) (inv_nextColumn env st h)
    rw [figs_nextColumn] at this
    exact this
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st (fun e => c e.1))

theorem nextSpread_figs (env : Env) (t : Nat) (st : St) (h : Inv st) :
    figs (nextSpread env t st) = figs st ∧ Inv (nextSpread env t st) := by
  by_cases c : (nextPage env st).page < t
  · unfold nextSpread; rw [dif_pos c]
    have := nextSpread_figs env t (nextPage env st) (inv_nextPage env st h)
    rw [figs_nextPage] at this; exact this
  · unfold nextSpread; rw [dif_neg c]; exact ⟨figs_nextPage env st, inv_nextPage env st h⟩
termination_by t - st.page
decreasing_by simp_wf; have := nextPage_page_gt env st; omega

theorem nextUnit_figs (env : Env) (unit : KeepParts) (st : St) (h : Inv st) :
    figs (nextUnit env unit st) = figs st ∧ Inv (nextUnit env unit st) := by
  cases unit
  · exact ⟨figs_nextColumn env st, inv_nextColumn env st h⟩
  · exact ⟨figs_nextPage env st, inv_nextPage env st h⟩
  · exact nextSpread_figs env _ st h

theorem inv_addUnmet (u : Unmet) (st : St) (h : Inv st) : Inv (addUnmet u st) :=
  ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩

theorem partTrial_figs (env : Env) (runBody runPlain : St → St) (Y : List Slot)
    (hb : ∀ s, Inv s → figs (runBody s) = figs s ++ Y ∧ Inv (runBody s))
    (hp : ∀ s, Inv s → figs (runPlain s) = figs s ++ Y ∧ Inv (runPlain s))
    (unit : KeepParts) (fits : St → Bool) (nested whole : Bool) (st : St) (h : Inv st) :
    figs (partTrial env runBody runPlain unit fits nested whole st) = figs st ++ Y ∧
      Inv (partTrial env runBody runPlain unit fits nested whole st) := by
  have p := hp st h
  have b := hb st h
  have fp := flushFigures_figs env _ p.2
  have fb := flushFigures_figs env _ b.2
  rw [p.1] at fp; rw [b.1] at fb
  simp only [partTrial]
  repeat' split
  all_goals first | exact p | exact fp | exact fb

/-- Every trial of a book part places the same figures, in a valid state. -/
theorem placeBookPart_figs (env : Env) (runBody runPlain : St → St) (Y : List Slot)
    (hb : ∀ s, Inv s → figs (runBody s) = figs s ++ Y ∧ Inv (runBody s))
    (hp : ∀ s, Inv s → figs (runPlain s) = figs s ++ Y ∧ Inv (runPlain s))
    (initial : St) (unit : KeepParts) (kind : Option Nat) (retained : List Nat) (nested whole : Bool)
    (h : Inv initial) :
    figs (placeBookPart env runBody runPlain initial unit kind retained nested whole) = figs initial ++ Y ∧
      Inv (placeBookPart env runBody runPlain initial unit kind retained nested whole) := by
  have m := nextUnit_figs env unit initial h
  have t0 := partTrial_figs env runBody runPlain Y hb hp unit (fitsPart unit initial.page retained) nested whole
    initial h
  have t1 := partTrial_figs env runBody runPlain Y hb hp unit (fitsPart unit initial.page retained) nested whole
    _ m.2
  rw [m.1] at t1
  have b0 := hb initial h
  have b1 := hb _ m.2
  rw [m.1] at b1
  have rep : ∀ k (x : St), figs x = figs initial ++ Y ∧ Inv x →
      figs (addUnmet k x) = figs initial ++ Y ∧ Inv (addUnmet k x) :=
    fun k x hx => ⟨hx.1, inv_addUnmet k x hx.2⟩
  simp only [placeBookPart]
  repeat' split
  all_goals first
    | exact b0
    | exact t0
    | exact t1
    | exact b1
    | exact rep _ _ b0
    | exact rep _ _ t0
    | exact rep _ _ b1
    | exact rep _ _ t1

theorem isEmpty_nil {α : Type} (l : List α) (h : l.isEmpty = true) : l = [] := by
  cases l with
  | nil => rfl
  | cons _ _ => simp [List.isEmpty] at h

theorem defer_figs (st : St) (d : Deferred) (h : Inv st) (hd : deferredOk [d]) :
    figs { st with deferred := st.deferred ++ [d] } = figs st ++ [deferredFig d] ∧
      Inv { st with deferred := st.deferred ++ [d] } :=
  ⟨by simp [figs, List.map_append],
    ⟨⟨h.weak.first, deferredOk_append _ _ h.weak.deferred hd⟩, h.used, h.fig, h.join⟩⟩

/-! ### Tables -/

theorem putRepeated_figs (st : St) (l : Line) (h : Inv st) :
    figs (putRepeated st l) = figs st ∧ Inv (putRepeated st l) :=
  ⟨by simp [figs, putRepeated, figSlots_append, figSlots],
    inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ 1 (by decide) rfl (Int.le_refl _)
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

theorem acrossGo_figs (env : Env) (hs : 0 ≤ env.separator) (h capt : List Line) (below retain fresh retried : Bool)
    (st : St) (gs : List (Bool × List Line)) (hi : Inv st) :
    figs (acrossGo env h capt below retain fresh retried st gs) = figs st ∧
      Inv (acrossGo env h capt below retain fresh retried st gs) := by
  match gs with
  | [] => unfold acrossGo; exact ⟨rfl, hi⟩
  | (isHeader, ls) :: remaining =>
    by_cases hr : fresh = true ∧ retainsTail env capt below retain isHeader remaining = true
    · unfold acrossGo; rw [dif_pos hr]
      have run : ∀ s, Inv s → figs (acrossGo env h capt below false true false
          (if decide (s.page ≠ st.page) && !h.isEmpty then h.foldl putRepeated s else s)
          ((isHeader, ls) :: remaining)) = figs s ++ [] ∧
          Inv (acrossGo env h capt below false true false
          (if decide (s.page ≠ st.page) && !h.isEmpty then h.foldl putRepeated s else s)
          ((isHeader, ls) :: remaining)) := by
        intro s i
        have q : figs (if decide (s.page ≠ st.page) && !h.isEmpty then h.foldl putRepeated s else s) = figs s ∧
            Inv (if decide (s.page ≠ st.page) && !h.isEmpty then h.foldl putRepeated s else s) := by
          split
          · exact putRepeateds_figs h s i
          · exact ⟨rfl, i⟩
        have := acrossGo_figs env hs h capt below false true false _ ((isHeader, ls) :: remaining) q.2
        rw [q.1, List.append_nil] at *; exact this
      have := placeBookPart_figs env _ _ [] run run st env.keepParts none ((ls ++ capt).map (·.id)) false true hi
      rw [List.append_nil] at this; exact this
    · by_cases h1 : ls.length ≤ env.fitting st ls ∨ isEmpty st = true
      · unfold acrossGo; rw [dif_neg hr, dif_pos h1]
        have p := putLines_figs env hs ls st hi
        have := acrossGo_figs env hs h capt below retain true false _ remaining p.2
        rw [p.1] at this; exact this
      · unfold acrossGo; rw [dif_neg hr, dif_neg h1]
        have n := inv_nextColumn env st hi
        have q : figs (if mustRepeat h (nextColumn env st) st isHeader retried = true
              then h.foldl putRepeated (nextColumn env st) else nextColumn env st) = figs st ∧
            Inv (if mustRepeat h (nextColumn env st) st isHeader retried = true
              then h.foldl putRepeated (nextColumn env st) else nextColumn env st) := by
          split
          · have := putRepeateds_figs h _ n
            rw [figs_nextColumn] at this; exact this
          · exact ⟨figs_nextColumn env st, n⟩
        have := acrossGo_figs env hs h capt below retain false (retried || mustRepeat h (nextColumn env st) st isHeader retried) _
          ((isHeader, ls) :: remaining) q.2
        rw [q.1] at this; exact this
termination_by (if retain then 1 else 0, gs.length, if retried then 0 else 1, rank env st)
decreasing_by
  all_goals simp_wf
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

/-- The space before a table in `KeepColumn`: never below the top of
    the column, where the room left is negative too. -/
theorem tableStart_inv (env : Env) (st : St) (h : Inv st) (sp : Int) :
    Inv { st with used := st.used + max 0 (min sp (free env st)) } :=
  inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ _ (Int.le_max_left ..) rfl (Int.le_refl _) (Or.inl rfl)

theorem startSet_figs (env : Env) (st : St) (n : Nat) (h : Inv st) :
    figs (startSet env st n st.used) = figs st ∧ Inv (startSet env st n st.used) := by
  have inv : Inv (startSet env st n st.used) := by
    have d : (startSet env st n st.used).deferred = st.deferred := by
      simp only [startSet, closePage]; split <;> rfl
    have nl : (startSet env st n st.used).noteLines = st.noteLines := by
      simp only [startSet, closePage]; split <;> rfl
    refine ⟨⟨?_, ?_⟩, ?_, ?_, ?_⟩
    · show 0 ≤ st.used ∨ 0 < st.noteLines; exact h.used
    · rw [d]; exact h.weak.deferred
    · show 0 ≤ st.used ∨ 0 < (startSet env st n st.used).noteLines; rw [nl]; exact h.used
    · left; rfl
    · rfl
  refine ⟨?_, inv⟩
  simp only [startSet, closePage]
  by_cases e : st.slots.isEmpty = true ∧ st.notes.isEmpty = true
  · have s : st.slots = [] := by
      cases h : st.slots with
      | nil => rfl
      | cons _ _ => simp [h, List.isEmpty] at e
    simp only [e, and_self, ite_true]
    simp [figs, figSlots, s]
  · simp only [e, ite_false]
    simp [figs, pagesFigs_cons, figSlots]

theorem checkNoBreak_figs (st : St) (h : Inv st) :
    figs (checkNoBreak st) = figs st ∧ Inv (checkNoBreak st) := by
  rcases checkNoBreak_eq st with e | ⟨u, e⟩ <;> rw [e]
  · exact ⟨rfl, h⟩
  · exact ⟨rfl, ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩⟩

theorem waitFor_figs (u : Unmet) (k : Nat × Bool) (st : St) (h : Inv st) :
    figs (waitFor u k st) = figs st ∧ Inv (waitFor u k st) := by
  obtain ⟨w, e⟩ := waitFor_eq u k st; rw [e]
  exact ⟨rfl, ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩⟩

theorem placeKept_figs {α : Type} (env : Env) (kp : Keep) (placeIn : St → Bool → List α → St)
    (hp : ∀ s b xs, Inv s → figs (placeIn s b xs) = figs s ∧ Inv (placeIn s b xs))
    (st : St) (isStart : Bool) (ls : List α) (n : Need) (h : Inv st) :
    figs (placeKept env kp placeIn st isStart ls n) = figs st ∧ Inv (placeKept env kp placeIn st isStart ls n) := by
  have one := hp st isStart ls h
  have a := hp st isStart (ls.take (ls.length - keptCut kp ls.length)) h
  have two := hp _ (isStart && (ls.take (ls.length - keptCut kp ls.length)).isEmpty)
    (ls.drop (ls.length - keptCut kp ls.length)) a.2
  have three := hp _ (isStart && (ls.take (ls.length - keptCut kp ls.length)).isEmpty)
    (ls.drop (ls.length - keptCut kp ls.length)) (inv_nextColumn env _ a.2)
  rw [figs_nextColumn, a.1] at three
  rw [a.1] at two
  simp only [placeKept]
  split
  · exact one
  · split
    · exact two
    · split
      · exact one
      · exact three

/-! ### The breaks, the need-lines and the blank lines waiting

A rule waits for the next block only between two steps; these lemmas
show that the operations of a ruled block leave the breaks, the
need-lines and the blank lines waiting as they are. -/

/-- The breaks, the need-lines and the blank lines waiting. -/
def frame (st : St) : List Pending × Option Nat × List Nat := (st.breaks, st.need, st.blank)

theorem frame_placeDeferred (env : Env) (ws : List Deferred) (st : St) :
    frame (placeDeferred env st ws) = frame st := by
  induction ws generalizing st with
  | nil => rfl
  | cons w ws ih =>
    cases w with
    | figure i n =>
      unfold placeDeferred; split
      · exact ih _
      · rfl
    | pageFigure i => rfl

theorem frame_advance (env : Env) (b : Bool) (st : St) : frame (advance env b st) = frame st := by
  have o : ∀ s : St, frame (openBox s) = frame s := fun s => by unfold openBox; split <;> rfl
  rw [advance, o]
  simp only [advanceIn, openColumn]
  rw [frame_placeDeferred]
  have c : ∀ (ps : List NotePart) (s : St), frame (ps.foldl (carryNote env) s) = frame s := by
    intro ps; induction ps with
    | nil => intro s; rfl
    | cons p ps ih => intro s; simp only [List.foldl]; rw [ih]; simp only [carryNote, addUnmet]; split <;> rfl
  have g : ∀ (ts : List Nat) (s : St), frame (ts.foldl (pageFigure env) s) = frame s := by
    intro ts; induction ts with
    | nil => intro s; rfl
    | cons t ts ih => intro s; simp only [List.foldl]; rw [ih]; rfl
  show frame (List.foldl (carryNote env) _ st.pending) = frame st
  rw [c, g]
  have e1 : (advanceFresh env b st).breaks = st.breaks := by
    simp only [advanceFresh, closePage]; split <;> (try split) <;> rfl
  have e2 : (advanceFresh env b st).need = st.need := by
    simp only [advanceFresh, closePage]; split <;> (try split) <;> rfl
  have e3 : (advanceFresh env b st).blank = st.blank := by
    simp only [advanceFresh, closePage]; split <;> (try split) <;> rfl
  simp only [frame, e1, e2, e3]

theorem frame_nextColumn (env : Env) (st : St) : frame (nextColumn env st) = frame st := frame_advance ..
theorem frame_nextPage (env : Env) (st : St) : frame (nextPage env st) = frame st := frame_advance ..

theorem frame_keep (env : Env) (st : St) (need : St → Int) : frame (keep env st need) = frame st := by
  by_cases h : free env st < need st ∧ isEmpty st = false
  · unfold keep; rw [dif_pos h, frame_keep env (nextColumn env st) need, frame_nextColumn]
  · unfold keep; rw [dif_neg h]
termination_by rank env st
decreasing_by exact I4_nextColumn_rank env st (Or.inl h.2)

theorem frame_flushDeferred (env : Env) (st : St) : frame (flushDeferred env st) = frame st := by
  by_cases h : st.deferred = [] ∧ st.pending = []
  · unfold flushDeferred; rw [dif_pos h]
  · unfold flushDeferred; rw [dif_neg h]
    rw [frame_flushDeferred env (nextColumn env st), frame_nextColumn]
termination_by (waiting st, columnsLeft env st)
decreasing_by exact I4_nextColumn_flush_rank env st (waiting_pos st h)

theorem frame_parityStart (env : Env) (p : Nat → Bool) (st : St) : frame (parityStart env p st) = frame st := by
  simp only [parityStart]
  have : frame (if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
      else nextPage env (flushDeferred env st)) = frame st := by
    split
    · exact frame_flushDeferred ..
    · rw [frame_nextPage, frame_flushDeferred]
  generalize (if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
      else nextPage env (flushDeferred env st)) = s1 at this
  split
  · exact this
  · exact this

theorem frame_breakPage (env : Env) (st : St) : frame (breakPage env st) = frame st := by
  simp only [breakPage]; split
  · rfl
  · split
    · rfl
    · exact frame_nextPage ..

theorem breaks_applyPending (env : Env) (st : St) (k : Pending) (h : st.breaks = []) :
    (applyPending env st k).breaks = [] ∧ (applyPending env st k).need = st.need
      ∧ (applyPending env st k).blank = st.blank := by
  suffices frame (applyPending env st k) = frame st by
    simp only [frame, Prod.mk.injEq] at this; exact ⟨this.1.trans h, this.2.1, this.2.2⟩
  cases k with
  | brk k =>
    simp only [applyPending]
    cases k with
    | page => exact frame_breakPage ..
    | recto => exact frame_parityStart ..
    | verso => exact frame_parityStart ..
    | column => simp only [applyBreakKind]; split
                · exact frame_nextColumn ..
                · exact frame_breakPage ..
  | start sec k =>
    simp only [applyPending, startBefore]
    have : frame (match k with
        | .column => if isEmpty st then st else nextColumn env st
        | .page =>
          if isEmpty (flushDeferred env st) = true ∧ (flushDeferred env st).column = 0 then flushDeferred env st
          else nextPage env (flushDeferred env st)
        | .recto => parityStart env odd st
        | .verso => parityStart env even st) = frame st := by
      cases k with
      | column => simp only []; split
                  · rfl
                  · exact frame_nextColumn ..
      | page => simp only []; split
                · exact frame_flushDeferred ..
                · rw [frame_nextPage, frame_flushDeferred]
      | recto => exact frame_parityStart ..
      | verso => exact frame_parityStart ..
    cases sec <;> exact this

/-- `applyBreaks` leaves no break waiting, and the need-lines and the
    blank lines as they were. -/
theorem applyBreaks_frame (env : Env) (st : St) :
    (applyBreaks env st).breaks = [] ∧ (applyBreaks env st).need = st.need ∧ (applyBreaks env st).blank = st.blank := by
  simp only [applyBreaks]
  suffices ∀ (ks : List Pending) (s : St), s.breaks = [] →
      (ks.foldl (applyPending env) s).breaks = [] ∧ (ks.foldl (applyPending env) s).need = s.need
        ∧ (ks.foldl (applyPending env) s).blank = s.blank from this _ _ rfl
  intro ks; induction ks with
  | nil => intro s h; exact ⟨h, rfl, rfl⟩
  | cons k ks ih =>
    intro s h; simp only [List.foldl]
    obtain ⟨a, b, c⟩ := breaks_applyPending env s k h
    obtain ⟨a', b', c'⟩ := ih _ a
    exact ⟨a', b'.trans b, c'.trans c⟩

theorem frame_parts {a b : St} (h : frame a = frame b) : a.breaks = b.breaks ∧ a.need = b.need ∧ a.blank = b.blank := by
  simp only [frame, Prod.mk.injEq] at h; exact h

theorem keep_parts (env : Env) (s : St) (nd : St → Int) :
    (keep env s nd).breaks = s.breaks ∧ (keep env s nd).need = s.need ∧ (keep env s nd).blank = s.blank :=
  frame_parts (frame_keep env s nd)

theorem applyNeed_frame (env : Env) (st : St) :
    (applyNeed env st).breaks = st.breaks ∧ (applyNeed env st).need = none ∧ (applyNeed env st).blank = st.blank := by
  unfold applyNeed
  split
  · rename_i e; exact ⟨rfl, e, rfl⟩
  · split
    · simp only []
      split
      · exact ⟨rfl, rfl, rfl⟩
      · exact frame_parts (frame_nextColumn env _)
    · exact keep_parts env _ _

theorem needBefore_frame (env : Env) (st : St) (flows : List Flow) :
    (needBefore env st flows).breaks = st.breaks ∧ (needBefore env st flows).need = none
      ∧ (needBefore env st flows).blank = st.blank := by
  unfold needBefore
  split
  · split
    · exact keep_parts env _ _
    · exact applyNeed_frame env _
  · exact applyNeed_frame env _

theorem dropBlanks_parts (bs : List Nat) (s : St) :
    (bs.foldl (fun s _ => addUnmet .droppedBlank s) s).breaks = s.breaks
      ∧ (bs.foldl (fun s _ => addUnmet .droppedBlank s) s).need = s.need
      ∧ (bs.foldl (fun s _ => addUnmet .droppedBlank s) s).blank = s.blank := by
  induction bs generalizing s with
  | nil => exact ⟨rfl, rfl, rfl⟩
  | cons _ _ ih => exact ih _

theorem placeBlank_frame (env : Env) (st : St) (f : Flow) (rest : List Flow) :
    (placeBlank env st f rest).breaks = st.breaks ∧ (placeBlank env st f rest).need = st.need
      ∧ (placeBlank env st f rest).blank = [] := by
  have p : (if startsRecto f = true then parityStart env odd st else st).breaks = st.breaks ∧
      (if startsRecto f = true then parityStart env odd st else st).need = st.need := by
    split
    · exact ⟨(frame_parts (frame_parityStart env odd st)).1, (frame_parts (frame_parityStart env odd st)).2.1⟩
    · exact ⟨rfl, rfl⟩
  unfold placeBlank
  split
  · rename_i e; exact ⟨rfl, rfl, e⟩
  · simp only []
    generalize (if startsRecto f = true then parityStart env odd st else st) = s1 at p
    split
    · rw [(dropBlanks_parts _ _).1, (dropBlanks_parts _ _).2.1, (dropBlanks_parts _ _).2.2]
      exact ⟨(keep_parts env _ _).1.trans p.1, (keep_parts env _ _).2.1.trans p.2, rfl⟩
    · exact ⟨(keep_parts env _ _).1.trans p.1, (keep_parts env _ _).2.1.trans p.2, rfl⟩

theorem frame_putRuledLines (env : Env) (k2 : Nat) (ls : List Line) (st : St) :
    frame (putRuledLines env k2 st ls) = frame st := by
  induction ls generalizing st with
  | nil => rfl
  | cons l ls ih => simp only [putRuledLines]; rw [ih]; rfl

theorem frame_commitRuled (env : Env) (st : St) (body : RuledBody) (p : Plan) :
    frame (commitRuled env st body p) = frame st := by
  cases body with
  | lines kp ls =>
    simp only [commitRuled]
    show frame (putRuledLines env p.after _ ls) = _
    rw [frame_putRuledLines]; rfl
  | heading r n ls =>
    simp only [commitRuled]
    show frame (putBlock env _ n ls) = _
    cases ls <;> rfl

/-! ### Blocks with rules -/

theorem putLineKeeping_noteLines (env : Env) (hs : 0 ≤ env.separator) (r : Int) (st : St) (l : Line) :
    st.noteLines ≤ (putLineKeeping env r st l).noteLines := by
  simp only [putLineKeeping]
  generalize (splitNotes _ _).1 = sh
  have : (0 : Int) ≤ (partsLines sh : Int) := Int.ofNat_nonneg _
  split <;> (try split) <;> omega

theorem putRuledLines_figs (env : Env) (hs : 0 ≤ env.separator) (k2 : Nat) (ls : List Line) (st : St) (h : Inv st) :
    figs (putRuledLines env k2 st ls) = figs st ∧ Inv (putRuledLines env k2 st ls) := by
  induction ls generalizing st with
  | nil => exact ⟨rfl, h⟩
  | cons l ls ih =>
    simp only [putRuledLines]
    have i1 : Inv (putLineKeeping env (ls.length + k2) st l) :=
      inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ 1 (by decide) rfl (putLineKeeping_noteLines env hs _ st l)
        (Or.inl (by simp [putLineKeeping, figSlots_append, figSlots]))
    have f1 : figs (putLineKeeping env (ls.length + k2) st l) = figs st := by
      simp [figs, putLineKeeping, figSlots_append, figSlots]
    have := ih _ i1
    exact ⟨this.1.trans f1, this.2⟩

theorem commitRuled_figs (env : Env) (hs : 0 ≤ env.separator) (st : St) (body : RuledBody) (p : Plan)
    (h : Inv st) (hw : p.waiting = none) :
    figs (commitRuled env st body p) = figs st ∧ Inv (commitRuled env st body p) := by
  have i1 : Inv { st with used := st.used + p.before, join := none } :=
    inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ p.before (Int.ofNat_nonneg _) rfl (Int.le_refl _) (Or.inl rfl)
      h.join.symm
  have two : figs (match body with
      | .lines _ ls => putRuledLines env p.after { st with used := st.used + p.before, join := none } ls
      | .heading _ n ls => { putBlock env { st with used := st.used + p.before, join := none } n ls with
          headingOnly := isEmpty st || st.headingOnly }) = figs st ∧
      Inv (match body with
      | .lines _ ls => putRuledLines env p.after { st with used := st.used + p.before, join := none } ls
      | .heading _ n ls => { putBlock env { st with used := st.used + p.before, join := none } n ls with
          headingOnly := isEmpty st || st.headingOnly }) := by
    cases body with
    | lines kp ls => exact putRuledLines_figs env hs _ ls _ i1
    | heading r n ls =>
      have b := putBlock_figs env hs _ n ls i1
      exact ⟨b.1, ⟨⟨b.2.weak.first, b.2.weak.deferred⟩, b.2.used, b.2.fig, b.2.join⟩⟩
  simp only [commitRuled]
  generalize (match body with
      | .lines _ ls => putRuledLines env p.after { st with used := st.used + p.before, join := none } ls
      | .heading _ n ls => { putBlock env { st with used := st.used + p.before, join := none } n ls with
          headingOnly := isEmpty st || st.headingOnly }) = s2 at two
  refine ⟨two.1, ?_⟩
  have i2 := two.2
  exact inv_addUsed i2 ⟨i2.weak.first, i2.weak.deferred⟩
    (min (s2.used + p.after) (max s2.used (cap env s2 - s2.noteLines)) - s2.used)
    (by have m1 := Int.le_max_left s2.used (cap env s2 - s2.noteLines)
        have m2 : (0 : Int) ≤ p.after := Int.ofNat_nonneg _
        have := Int.le_min.mpr (And.intro (show s2.used ≤ s2.used + p.after by omega) m1)
        omega)
    (by show min _ _ = _; omega) (Int.le_refl _) (Or.inl rfl) (by rw [i2.join]; exact hw)

theorem splitRuled_figs (env : Env) (hs : 0 ≤ env.separator) (st : St) (i : Nat) (b a : Bool) (body : RuledBody)
    (rest : List Flow) (h : Inv st) :
    figs (splitRuled env st i b a body rest) = figs st ∧ Inv (splitRuled env st i b a body rest) := by
  have h0 : figs (if isEmpty st = true then st else nextColumn env st) = figs st ∧
      Inv (if isEmpty st = true then st else nextColumn env st) := by
    split
    · exact ⟨rfl, h⟩
    · exact ⟨figs_nextColumn .., inv_nextColumn env st h⟩
  simp only [splitRuled]
  generalize (if isEmpty st = true then st else nextColumn env st) = s at h0
  cases body with
  | lines kp ls => have := placeLines_figs env hs kp s true ls h0.2; exact ⟨this.1.trans h0.1, this.2⟩
  | heading r n ls =>
    simp only []
    split
    · have := commitRuled_figs env hs s (.heading r n ls) ⟨(planOf env s i b a (.heading r n ls) rest none).before,
        (planOf env s i b a (.heading r n ls) [] none).after, none,
        (planOf env s i b a (.heading r n ls) rest none).beforeRules, (planOf env s i b a (.heading r n ls) [] none).afterRules⟩ h0.2 rfl
      exact ⟨this.1.trans h0.1, this.2⟩
    · split
      · have := commitRuled_figs env hs s (.heading r n ls) ⟨(planOf env s i b a (.heading r n ls) rest none).before,
          0, none, (planOf env s i b a (.heading r n ls) rest none).beforeRules, []⟩ h0.2 rfl
        exact ⟨this.1.trans h0.1, this.2⟩
      · have := putBlock_figs env hs s n ls h0.2; exact ⟨this.1.trans h0.1, this.2⟩

/-! ### A rule waiting between two blocks -/

/-- `joinsNext` without the rule after: the first flow ahead, the book
    parts made flat, is a block whose rule before shares the area of the
    rule waiting. -/
def joinsHead (fs : List Flow) : Bool :=
  match flattenParts fs with
  | .ruled _ true _ true _ :: _ => true
  | _ => false

theorem joinsNext_eq (a : Bool) (fs : List Flow) : joinsNext a fs = (a && joinsHead fs) := rfl

/-- A rule waits only for the block ahead to share its area. -/
def JoinAhead (st : St) (fs : List Flow) : Prop := st.join ≠ none → joinsHead fs = true

/-- The state after a block whose rule after waits: valid but for the
    rule waiting, with room left or footnote lines in the column, and no
    break, need-lines or blank lines waiting. -/
structure Win (env : Env) (st : St) : Prop where
  inv : Inv { st with join := none }
  room : 0 < st.noteLines ∨ 0 ≤ free env st
  breaks : st.breaks = []
  need : st.need = none
  blank : st.blank = []

def Good (env : Env) (st : St) : Prop := Inv st ∨ Win env st

theorem withJoin_self (st : St) (h : st.join = none) : { st with join := none } = st := by
  cases st; simp only at h; subst h; rfl

theorem inv_of_good (env : Env) (st : St) (h : Good env st) (e : st.join = none) : Inv st := by
  rcases h with i | w
  · exact i
  · have := w.inv; rwa [withJoin_self st e] at this

theorem good_weak (env : Env) (st : St) (h : Good env st) : Weak st := by
  rcases h with i | w
  · exact i.weak
  · exact ⟨w.inv.weak.first, w.inv.weak.deferred⟩

theorem joinAhead_of_none {st : St} (fs : List Flow) (h : st.join = none) : JoinAhead st fs :=
  fun n => absurd h n

/-- The head of the flows ahead is the flow itself unless it is a book
    part. -/
theorem joinsHead_cons (f : Flow) (r : List Flow) (h : ∀ u k ret body, f ≠ .bookPart u k ret body) :
    joinsHead (f :: r) = (match f with | .ruled _ true _ true _ => true | _ => false) := by
  cases f with
  | bookPart u k ret body => exact absurd rfl (h u k ret body)
  | boxed i kb ka body => simp [joinsHead, flattenParts]
  | ruled i b a j body => cases b <;> cases j <;> simp [joinsHead, flattenParts]
  | _ => simp [joinsHead, flattenParts]

theorem splitNotes_le (r : Int) (ns : List Note) : ((partsLines (splitNotes r ns).1 : Nat) : Int) ≤ max 0 r := by
  induction ns generalizing r with
  | nil => simp [splitNotes, partsLines]; exact Int.le_max_left 0 r
  | cons n rest ih =>
    simp only [splitNotes]
    split
    · have := ih (r - n.lines)
      simp only [partsLines, List.foldr] at this ⊢
      have m3 := Int.le_max_right 0 r
      rename_i hl
      have : max 0 (r - n.lines) = r - n.lines := by
        rcases Int.le_total 0 (r - n.lines) with h | h
        · exact Int.max_eq_right h
        · omega
      push_cast; omega
    · split
      · simp only [partsLines, List.foldr]
        rename_i h1 h2
        have := Int.le_max_right 0 r
        have : ((r.toNat : Nat) : Int) = r := Int.toNat_of_nonneg (by omega)
        omega
      · simp [partsLines]; exact Int.le_max_left 0 r

theorem room_step (used nl cap sep r P A : Int) (hP0 : 0 ≤ P) (hP : P ≤ max 0 (cap - used - 1 - r - nl - sep))
    (hs : 0 ≤ sep) (hsep : sep ≠ 0 → nl = 0) (hA : A = 0 ∨ A = sep)
    (h : 0 < nl ∨ used + nl + 1 + r ≤ cap) : 0 < nl + A + P ∨ used + 1 + (nl + A + P) + r ≤ cap := by
  rcases Int.le_total 0 (cap - used - 1 - r - nl - sep) with q | q
  · rw [Int.max_eq_right q] at hP; omega
  · rw [Int.max_eq_left q] at hP
    by_cases s0 : sep = 0
    · omega
    · have := hsep s0; omega

theorem putLineKeeping_room (env : Env) (hs : 0 ≤ env.separator) (r : Int) (st : St) (l : Line)
    (h : 0 < st.noteLines ∨ st.used + st.noteLines + 1 + r ≤ cap env st) :
    0 < (putLineKeeping env r st l).noteLines ∨
      (putLineKeeping env r st l).used + (putLineKeeping env r st l).noteLines + r ≤ cap env st := by
  simp only [putLineKeeping]
  generalize hsp : (if st.noteLines = 0 ∧ 0 < (l.notes.map (·.lines)).foldr (· + ·) 0 then env.separator else 0) = sep
  have s0 : 0 ≤ sep := by rw [← hsp]; split <;> omega
  have s1 : sep ≠ 0 → st.noteLines = 0 := by rw [← hsp]; split <;> (rename_i c; intro; first | exact c.1 | omega)
  have b := splitNotes_le (cap env st - st.used - 1 - r - st.noteLines - sep) l.notes
  generalize splitNotes _ l.notes = sp at b
  have p0 : (0 : Int) ≤ (partsLines sp.1 : Int) := Int.ofNat_nonneg _
  have := room_step st.used st.noteLines (cap env st) sep r (partsLines sp.1)
    (if sp.1.isEmpty ∧ 0 < r then 0 else sep) p0 b s0 s1 (by split <;> simp) h
  exact this

/-- The lines of a paragraph's block put with room for them: the column
    keeps room for the lines after each, or has footnote lines. -/
theorem putRuledLines_room (env : Env) (hs : 0 ≤ env.separator) (k2 : Nat) (ls : List Line) (st : St)
    (h : 0 < st.noteLines ∨ st.used + st.noteLines + ls.length + k2 ≤ cap env st) :
    (0 < (putRuledLines env k2 st ls).noteLines ∨
      (putRuledLines env k2 st ls).used + (putRuledLines env k2 st ls).noteLines + k2 ≤ cap env (putRuledLines env k2 st ls))
    ∧ cap env (putRuledLines env k2 st ls) = cap env st := by
  induction ls generalizing st with
  | nil => simp only [putRuledLines, List.length] at h ⊢; exact ⟨by omega, by simp⟩
  | cons l ls ih =>
    simp only [putRuledLines]
    have c : cap env (putLineKeeping env (ls.length + k2) st l) = cap env st := rfl
    refine (fun p => ⟨p.1, p.2.trans c⟩) (ih _ ?_)
    have := putLineKeeping_room env hs (ls.length + k2) st l (by simp only [List.length] at h; push_cast at h ⊢; omega)
    rw [c]; push_cast at this ⊢; omega

theorem room_gen (used nl cap sep d P A : Int) (hP0 : 0 ≤ P) (hP : P ≤ max 0 (cap - used - d - nl - sep))
    (hs : 0 ≤ sep) (hsep : sep ≠ 0 → nl = 0) (hA : A = 0 ∨ A = sep)
    (h : 0 < nl ∨ used + nl + d ≤ cap) : 0 < nl + A + P ∨ used + d + (nl + A + P) ≤ cap := by
  rcases Int.le_total 0 (cap - used - d - nl - sep) with q | q
  · rw [Int.max_eq_right q] at hP; omega
  · rw [Int.max_eq_left q] at hP
    by_cases s0 : sep = 0
    · omega
    · have := hsep s0; omega

theorem putBlock_room (env : Env) (hs : 0 ≤ env.separator) (st : St) (n : Nat) (ls : List Line)
    (h : 0 < st.noteLines ∨ st.used + st.noteLines + n ≤ cap env st) :
    0 < (putBlock env st n ls).noteLines ∨ (putBlock env st n ls).used + (putBlock env st n ls).noteLines ≤ cap env st := by
  cases ls with
  | nil => simp only [putBlock]; omega
  | cons l0 ls =>
    simp only [putBlock]
    generalize hsp : (if st.noteLines = 0 ∧ 0 < ((l0 :: ls).bind (·.notes) |>.map (·.lines)).foldr (· + ·) 0
      then env.separator else 0) = sep
    have s0 : 0 ≤ sep := by rw [← hsp]; split <;> omega
    have s1 : sep ≠ 0 → st.noteLines = 0 := by rw [← hsp]; split <;> (rename_i c; intro; first | exact c.1 | omega)
    have b := splitNotes_le (cap env st - st.used - n - st.noteLines - sep) ((l0 :: ls).bind (·.notes))
    generalize splitNotes _ _ = sp at b
    have p0 : (0 : Int) ≤ (partsLines sp.1 : Int) := Int.ofNat_nonneg _
    have := room_gen st.used st.noteLines (cap env st) sep n (partsLines sp.1)
      (if sp.1.isEmpty then 0 else sep) p0 b s0 s1 (by split <;> simp) h
    omega

theorem planNeed_ge (env : Env) (hs : 0 ≤ env.separator) (st : St) (body : RuledBody) (p : Plan) :
    (p.before + body.size + p.after : Int) ≤ planNeed env st body p := by
  cases body with
  | lines kp ls =>
    simp only [planNeed, planParts, needIn, noNeed, RuledBody.size]; push_cast
    split <;> omega
  | heading r n ls =>
    simp only [planNeed, planParts, needIn, noNeed, RuledBody.size]; push_cast
    split <;> omega

theorem cap_putRuledLines (env : Env) (k2 : Nat) (ls : List Line) (st : St) :
    cap env (putRuledLines env k2 st ls) = cap env st := by
  induction ls generalizing st with
  | nil => rfl
  | cons l ls ih => simp only [putRuledLines]; rw [ih]; rfl

/-- A block committed: its figures none, the state valid but for the rule
    left waiting, the column with room for it when its rule after waits,
    and the breaks, the need-lines and the blank lines waiting kept. -/
theorem commitRuled_good (env : Env) (hs : 0 ≤ env.separator) (st : St) (body : RuledBody) (p : Plan)
    (h : Inv { st with join := none }) :
    figs (commitRuled env st body p) = figs st ∧ Inv { commitRuled env st body p with join := none }
      ∧ (commitRuled env st body p).join = p.waiting
      ∧ (p.after = 0 → planNeed env st body p ≤ free env st →
          0 < (commitRuled env st body p).noteLines ∨ 0 ≤ free env (commitRuled env st body p))
      ∧ frame (commitRuled env st body p) = frame st := by
  have i1 : Inv { st with used := st.used + p.before, join := none } :=
    inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ p.before (Int.ofNat_nonneg _) rfl (Int.le_refl _) (Or.inl rfl)
  have two : let s2 := match body with
        | .lines _ ls => putRuledLines env p.after { st with used := st.used + p.before, join := none } ls
        | .heading _ n ls => { putBlock env { st with used := st.used + p.before, join := none } n ls with
            headingOnly := isEmpty st || st.headingOnly }
      figs s2 = figs st ∧ Inv s2 ∧ cap env s2 = cap env st ∧ frame s2 = frame st ∧
        (p.after = 0 → planNeed env st body p ≤ free env st → 0 < s2.noteLines ∨ s2.used + s2.noteLines ≤ cap env st) := by
    have ge := planNeed_ge env hs st body p
    cases body with
    | lines kp ls =>
      have fl := putRuledLines_figs env hs p.after ls _ i1
      refine ⟨fl.1, fl.2, cap_putRuledLines .., (frame_putRuledLines ..).trans rfl, ?_⟩
      intro ha hf
      simp only [RuledBody.size] at ge
      have := putRuledLines_room env hs p.after ls { st with used := st.used + p.before, join := none }
        (Or.inr (by simp only [free] at hf; push_cast at hf ge ⊢; show _ ≤ cap env st; omega))
      rcases this.1 with a | a
      · exact Or.inl a
      · right; rw [this.2] at a
        have a' : (putRuledLines env p.after { st with used := st.used + p.before, join := none } ls).used
            + (putRuledLines env p.after { st with used := st.used + p.before, join := none } ls).noteLines
            + p.after ≤ cap env st := a
        show (putRuledLines env p.after _ ls).used + (putRuledLines env p.after _ ls).noteLines ≤ cap env st
        omega
    | heading r n ls =>
      have b := putBlock_figs env hs _ n ls i1
      refine ⟨b.1, ⟨⟨b.2.weak.first, b.2.weak.deferred⟩, b.2.used, b.2.fig, b.2.join⟩, ?_, ?_, ?_⟩
      · show cap env { putBlock env _ n ls with headingOnly := _ } = _; cases ls <;> rfl
      · show frame (putBlock env _ n ls) = _; cases ls <;> rfl
      intro ha hf
      simp only [RuledBody.size] at ge
      exact putBlock_room env hs { st with used := st.used + p.before, join := none } n ls
        (Or.inr (by simp only [free] at hf; push_cast at hf ge ⊢; show _ ≤ cap env st; omega))
  simp only [commitRuled]
  generalize (match body with
      | .lines _ ls => putRuledLines env p.after { st with used := st.used + p.before, join := none } ls
      | .heading _ n ls => { putBlock env { st with used := st.used + p.before, join := none } n ls with
          headingOnly := isEmpty st || st.headingOnly }) = s2 at two
  obtain ⟨f2, i2, c2, fr2, r2⟩ := two
  have m1 := Int.le_max_left s2.used (cap env s2 - s2.noteLines)
  have m2 := Int.min_le_left (s2.used + p.after) (max s2.used (cap env s2 - s2.noteLines))
  have m3 := Int.le_min.mpr (And.intro (show s2.used ≤ s2.used + p.after by have := Int.ofNat_nonneg p.after; omega) m1)
  refine ⟨f2, ?_, by first | rfl | trivial, ?_, fr2⟩
  · exact inv_addUsed i2 ⟨i2.weak.first, i2.weak.deferred⟩
      (min (s2.used + p.after) (max s2.used (cap env s2 - s2.noteLines)) - s2.used) (by omega)
      (by show min _ _ = _; omega) (Int.le_refl _) (Or.inl rfl) i2.join.symm
  · intro ha hf
    have r := r2 ha hf
    have e : min (s2.used + p.after) (max s2.used (cap env s2 - s2.noteLines)) = s2.used := by
      rw [ha]; simp only [Int.ofNat_zero, Int.add_zero]; exact Int.min_eq_left m1
    show 0 < s2.noteLines ∨ 0 ≤ cap env s2 - min (s2.used + p.after) (max s2.used (cap env s2 - s2.noteLines)) - s2.noteLines
    rw [e, c2]; omega

theorem planOf_waiting' (env : Env) (st : St) (i : Nat) (b a : Bool) (body : RuledBody) (rest : List Flow)
    (j : Option (Nat × Int)) (h : (planOf env st i b a body rest j).waiting ≠ none) :
    joinsHead rest = true ∧ a = true ∧ (planOf env st i b a body rest j).after = 0 := by
  by_cases e : joinsNext a rest = true
  · rw [joinsNext_eq] at e
    have ha : a = true := by cases a <;> simp_all
    have hh : joinsHead rest = true := by cases a <;> simp_all
    refine ⟨hh, ha, ?_⟩
    simp [planOf, joinsNext_eq, ha, hh]
  · exact absurd (by simp [planOf, e]) h

theorem frame_flushJoin (env : Env) (st : St) : frame (flushJoin env st) = frame st := by
  unfold flushJoin; split <;> rfl

theorem flushJoin_inv (env : Env) (st : St) (w : Win env st) :
    figs (flushJoin env st) = figs st ∧ Inv (flushJoin env st) := by
  unfold flushJoin
  split
  · rename_i e; refine ⟨rfl, ?_⟩; have := w.inv; rwa [withJoin_self st e] at this
  · refine ⟨rfl, ?_⟩
    have I := w.inv
    rcases w.room with n | f
    · exact ⟨⟨I.weak.first, I.weak.deferred⟩, Or.inr n, Or.inr (Or.inr n), rfl⟩
    · exact inv_addUsed I ⟨I.weak.first, I.weak.deferred⟩ (min _ (free env st))
        (Int.le_min.mpr ⟨Int.ofNat_nonneg _, f⟩) rfl (Int.le_refl _) (Or.inl rfl) rfl

/-- A block committed in a column with no break, need-lines or blank
    lines waiting: valid, or with its rule after waiting for the block
    ahead. -/
theorem commit_good (env : Env) (hs : 0 ≤ env.separator) (s : St) (i : Nat) (b a : Bool) (body : RuledBody)
    (rest : List Flow) (j : Option (Nat × Int)) (h : Inv { s with join := none })
    (q : s.breaks = [] ∧ s.need = none ∧ s.blank = [])
    (hf : planNeed env s body (planOf env s i b a body rest j) ≤ free env s) :
    figs (commitRuled env s body (planOf env s i b a body rest j)) = figs s
      ∧ Good env (commitRuled env s body (planOf env s i b a body rest j))
      ∧ JoinAhead (commitRuled env s body (planOf env s i b a body rest j)) rest := by
  obtain ⟨f1, i1, j1, r1, fr1⟩ := commitRuled_good env hs s body (planOf env s i b a body rest j) h
  refine ⟨f1, ?_, ?_⟩
  · by_cases w : (planOf env s i b a body rest j).waiting = none
    · left; have := i1; rwa [withJoin_self _ (j1.trans w)] at this
    · obtain ⟨_, _, k0⟩ := planOf_waiting' env s i b a body rest j w
      have fp := frame_parts fr1
      exact Or.inr ⟨i1, r1 k0 hf, fp.1.trans q.1, fp.2.1.trans q.2.1, fp.2.2.trans q.2.2⟩
  · intro n
    rw [j1] at n
    exact (planOf_waiting' env s i b a body rest j n).1

/-- `commit_good` for the plans `settleRuled` commits: sharing the rule
    after with the flows ahead, or with its own area. -/
theorem commit_good' (env : Env) (hs : 0 ≤ env.separator) (s : St) (i : Nat) (b a : Bool) (body : RuledBody)
    (rest rest' : List Flow) (e : rest' = rest ∨ rest' = []) (j : Option (Nat × Int)) (h : Inv { s with join := none })
    (q : s.breaks = [] ∧ s.need = none ∧ s.blank = [])
    (hf : planNeed env s body (planOf env s i b a body rest' j) ≤ free env s) :
    figs (commitRuled env s body (planOf env s i b a body rest' j)) = figs s
      ∧ Good env (commitRuled env s body (planOf env s i b a body rest' j))
      ∧ JoinAhead (commitRuled env s body (planOf env s i b a body rest' j)) rest := by
  have := commit_good env hs s i b a body rest' j h q hf
  rcases e with rfl | rfl
  · exact this
  · exact ⟨this.1, this.2.1, fun n => absurd (this.2.2 n) (by simp [joinsHead, flattenParts])⟩

theorem placeRuledFresh_good (env : Env) (hs : 0 ≤ env.separator) (st : St) (i : Nat) (b a : Bool)
    (body : RuledBody) (rest : List Flow) (h : Inv st) (q : st.breaks = [] ∧ st.need = none ∧ st.blank = []) :
    figs (placeRuledFresh env st i b a body rest) = figs st ∧ Good env (placeRuledFresh env st i b a body rest)
      ∧ JoinAhead (placeRuledFresh env st i b a body rest) rest := by
  have h1 : figs (if body.recto = true then parityStart env odd st else st) = figs st ∧
      Inv (if body.recto = true then parityStart env odd st else st) ∧
      frame (if body.recto = true then parityStart env odd st else st) = frame st := by
    split
    · exact ⟨(parityStart_figs env odd st h).1, (parityStart_figs env odd st h).2, frame_parityStart ..⟩
    · exact ⟨rfl, h, rfl⟩
  have qf : ∀ s : St, frame s = frame st → s.breaks = [] ∧ s.need = none ∧ s.blank = [] := by
    intro s e; have := frame_parts e; exact ⟨this.1.trans q.1, this.2.1.trans q.2.1, this.2.2.trans q.2.2⟩
  have sg : ∀ s : St, Inv s →
      figs (splitRuled env s i b a body rest) = figs s ∧ Good env (splitRuled env s i b a body rest)
        ∧ JoinAhead (splitRuled env s i b a body rest) rest := by
    intro s is
    have := splitRuled_figs env hs s i b a body rest is
    exact ⟨this.1, Or.inl this.2, joinAhead_of_none _ this.2.join⟩
  have last : ∀ s2 : St, figs s2 = figs st → Inv s2 → frame s2 = frame st →
      let r := match settleRuled env s2 i b a body rest none with
        | some placed => placed
        | none =>
          if isEmpty s2 = true then splitRuled env s2 i b a body rest
          else
            match settleRuled env (nextColumn env s2) i b a body rest none with
            | some placed => placed
            | none => splitRuled env (nextColumn env s2) i b a body rest
      figs r = figs st ∧ Good env r ∧ JoinAhead r rest := by
    intro s2 e i2 fr2
    have n2 := inv_nextColumn env s2 i2
    have e2 : figs (nextColumn env s2) = figs st := (figs_nextColumn ..).trans e
    have fn2 : frame (nextColumn env s2) = frame st := (frame_nextColumn ..).trans fr2
    simp only []
    apply settle_or (fun r => figs r = figs st ∧ Good env r ∧ JoinAhead r rest)
    · intro rest' er hf
      have := commit_good' env hs s2 i b a body rest rest' er none (by rwa [withJoin_self s2 i2.join]) (qf s2 fr2) hf
      exact ⟨this.1.trans e, this.2⟩
    · split
      · have := sg s2 i2; exact ⟨this.1.trans e, this.2⟩
      · apply settle_or (fun r => figs r = figs st ∧ Good env r ∧ JoinAhead r rest)
        · intro rest' er hf
          have := commit_good' env hs _ i b a body rest rest' er none (by rwa [withJoin_self _ n2.join]) (qf _ fn2) hf
          exact ⟨this.1.trans e2, this.2⟩
        · have := sg _ n2; exact ⟨this.1.trans e2, this.2⟩
  simp only [placeRuledFresh]
  generalize (if body.recto = true then parityStart env odd st else st) = s1 at h1
  obtain ⟨f1, i1, fr1⟩ := h1
  have kp : ∀ nd, figs (keep env s1 nd) = figs st ∧ Inv (keep env s1 nd) ∧ frame (keep env s1 nd) = frame st :=
    fun nd => ⟨(figs_keep ..).trans f1, inv_keep env s1 nd i1, (frame_keep ..).trans fr1⟩
  have ok : figs (ruledKeep env s1 i b a body rest) = figs st ∧ Inv (ruledKeep env s1 i b a body rest) ∧
      frame (ruledKeep env s1 i b a body rest) = frame st := by
    cases body with
    | heading r n ls => cases r
                        · exact kp _
                        · exact ⟨f1, i1, fr1⟩
    | lines kp' ls =>
      simp only [ruledKeep]
      split
      · split
        · exact kp _
        · exact ⟨f1, i1, fr1⟩
      · exact ⟨f1, i1, fr1⟩
  exact last _ ok.1 ok.2.1 ok.2.2

theorem placeRuled_good (env : Env) (hs : 0 ≤ env.separator) (st : St) (i : Nat) (b a j : Bool)
    (body : RuledBody) (rest : List Flow) (hg : Good env st) (q : st.breaks = [] ∧ st.need = none ∧ st.blank = []) :
    figs (placeRuled env st i b a j body rest) = figs st ∧ Good env (placeRuled env st i b a j body rest)
      ∧ JoinAhead (placeRuled env st i b a j body rest) rest := by
  unfold placeRuled
  split
  · rename_i jj e
    have w : Win env st := by
      rcases hg with i0 | w
      · rw [i0.join] at e; cases e
      · exact w
    apply joined_or (fun r => figs r = figs st ∧ Good env r ∧ JoinAhead r rest)
    · intro rest' er hf
      exact commit_good' env hs st i b a body rest rest' er (some jj) w.inv q hf
    · have fl := flushJoin_inv env st w
      have := placeRuledFresh_good env hs (flushJoin env st) i b a body rest fl.2
        (by have := frame_parts (frame_flushJoin env st); exact ⟨this.1.trans q.1, this.2.1.trans q.2.1, this.2.2.trans q.2.2⟩)
      exact ⟨this.1.trans fl.1, this.2⟩
  · rename_i e
    exact placeRuledFresh_good env hs st i b a body rest (inv_of_good env st hg e) q

/-! ### Book parts, boxes and steps with a rule waiting -/

theorem flattenParts_append (a b : List Flow) : flattenParts (a ++ b) = flattenParts a ++ flattenParts b := by
  match a with
  | [] => simp [flattenParts]
  | f :: r =>
    have ih := flattenParts_append r b
    cases f with
    | bookPart u k i body => simp only [List.cons_append, flattenParts]; rw [ih, List.append_assoc]
    | boxed j kb ka body => simp only [List.cons_append, flattenParts]; rw [ih]
    | _ => simp only [List.cons_append, flattenParts]; rw [ih]
termination_by sizeOf a

theorem flattenParts_flattenParts (a : List Flow) : flattenParts (flattenParts a) = flattenParts a := by
  match a with
  | [] => simp [flattenParts]
  | f :: r =>
    have ih := flattenParts_flattenParts r
    cases f with
    | bookPart u k i body =>
      have ib := flattenParts_flattenParts body
      simp only [flattenParts]; rw [flattenParts_append, ib, ih]
    | boxed j kb ka body =>
      have ib := flattenParts_flattenParts body
      simp only [flattenParts]; rw [ib, ih]
    | _ => simp only [flattenParts]; rw [ih]
termination_by sizeOf a

theorem joinsHead_bookPart (u : KeepParts) (k : Nat) (r : List Nat) (body rest : List Flow) :
    joinsHead (.bookPart u k r body :: rest) = joinsHead (body ++ rest) ∧
      joinsHead (.bookPart u k r body :: rest) = joinsHead (flattenParts body ++ rest) := by
  have e1 : flattenParts (.bookPart u k r body :: rest) = flattenParts (body ++ rest) := by
    rw [flattenParts_append]; simp only [flattenParts]
  have e2 : flattenParts (flattenParts body ++ rest) = flattenParts (body ++ rest) := by
    rw [flattenParts_append, flattenParts_flattenParts, ← flattenParts_append]
  simp only [joinsHead]; rw [e1, e2]; exact ⟨rfl, rfl⟩

theorem joinAhead_nil {st : St} (h : JoinAhead st []) : st.join = none := by
  cases e : st.join with
  | none => rfl
  | some j => exact absurd (h (by simp [e])) (by simp [joinsHead, flattenParts])

/-- The boxes made by golem-typeset before the ruled blocks are linked:
    the flow after a box, the book parts made flat, never shares the
    area of a rule waiting, here and in the bodies of the book parts and
    the boxes. -/
inductive BoxesOk : List Flow → Prop
  | nil : BoxesOk []
  | cons (f : Flow) (r : List Flow)
      (box : ∀ i kb ka body, f = .boxed i kb ka body → joinsHead r = false)
      (boxBody : ∀ i kb ka body, f = .boxed i kb ka body → BoxesOk (body ++ r))
      (part : ∀ u k ret body, f = .bookPart u k ret body → BoxesOk (body ++ r))
      (partFlat : ∀ u k ret body, f = .bookPart u k ret body → BoxesOk (flattenParts body ++ r))
      (tail : BoxesOk r) : BoxesOk (f :: r)

/-- Two blocks sharing the area of their rules satisfy `BoxesOk`: the
    hypothesis leaves the shared rules in. -/
theorem BoxesOk_shared (kp : Keep) (a b : List Line) :
    BoxesOk [.ruled 0 false true false (.lines kp a), .ruled 1 true false true (.lines kp b)] := by
  refine .cons _ _ (fun _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    (fun _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) ?_
  refine .cons _ _ (fun _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    (fun _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) .nil

theorem BoxesOk.tail' {f : Flow} {r : List Flow} (h : BoxesOk (f :: r)) : BoxesOk r := by
  cases h with | cons _ _ _ _ _ _ t => exact t

theorem BoxesOk.box' {i kb ka : Nat} {body r : List Flow} (h : BoxesOk (.boxed i kb ka body :: r)) :
    joinsHead r = false ∧ BoxesOk (body ++ r) := by
  cases h with | cons _ _ b bb _ _ _ => exact ⟨b i kb ka body rfl, bb i kb ka body rfl⟩

theorem BoxesOk.part' {u : KeepParts} {k : Nat} {ret : List Nat} {body r : List Flow}
    (h : BoxesOk (.bookPart u k ret body :: r)) : BoxesOk (body ++ r) ∧ BoxesOk (flattenParts body ++ r) := by
  cases h with | cons _ _ _ _ p pf _ => exact ⟨p u k ret body rfl, pf u k ret body rfl⟩

theorem good_addUnmet (env : Env) (u : Unmet) (st : St) (h : Good env st) : Good env (addUnmet u st) := by
  rcases h with i | w
  · exact Or.inl (inv_addUnmet u st i)
  · exact Or.inr ⟨inv_addUnmet u _ w.inv, w.room, w.breaks, w.need, w.blank⟩

theorem good_checkNoBreak (env : Env) (st : St) (h : Good env st) :
    figs (checkNoBreak st) = figs st ∧ Good env (checkNoBreak st) ∧ (checkNoBreak st).join = st.join := by
  rcases checkNoBreak_eq st with e | ⟨u, e⟩ <;> rw [e]
  · exact ⟨rfl, h, rfl⟩
  · refine ⟨rfl, ?_, rfl⟩
    rcases h with i | w
    · exact Or.inl ⟨⟨i.weak.first, i.weak.deferred⟩, i.used, i.fig, i.join⟩
    · exact Or.inr ⟨⟨⟨w.inv.weak.first, w.inv.weak.deferred⟩, w.inv.used, w.inv.fig, w.inv.join⟩,
        w.room, w.breaks, w.need, w.blank⟩

theorem good_seen (env : Env) (st : St) (a : Bool) (sp : List (Nat × Int)) (h : Good env st) :
    Good env { st with seen := true, lastDeferred := a, spaces := sp } := by
  rcases h with i | w
  · exact Or.inl ⟨⟨i.weak.first, i.weak.deferred⟩, i.used, i.fig, i.join⟩
  · exact Or.inr ⟨⟨⟨w.inv.weak.first, w.inv.weak.deferred⟩, w.inv.used, w.inv.fig, w.inv.join⟩,
      w.room, w.breaks, w.need, w.blank⟩

theorem flushFigures_good (env : Env) (st : St) (h : Good env st) :
    figs (flushFigures env st) = figs st ∧ (flushFigures env st = st ∨ Inv (flushFigures env st)) := by
  by_cases c : st.deferred = []
  · unfold flushFigures; rw [dif_pos c]; exact ⟨rfl, Or.inl rfl⟩
  · unfold flushFigures; rw [dif_neg c]
    have := flushFigures_figs env (nextColumn env st) ((advance_inv env _ st (good_weak env st h)).1)
    rw [figs_nextColumn] at this
    exact ⟨this.1, Or.inr this.2⟩

theorem nextUnit_inv (env : Env) (unit : KeepParts) (st : St) (w : Weak st) :
    figs (nextUnit env unit st) = figs st ∧ Inv (nextUnit env unit st) := by
  cases unit
  · exact ⟨figs_nextColumn env st, (advance_inv env _ st w).1⟩
  · exact ⟨figs_nextPage env st, (advance_inv env _ st w).1⟩
  · simp only [nextUnit]
    by_cases c : (nextPage env st).page < (if st.page = 1 then 2 else 2 * (st.page / 2 + 1))
    · unfold nextSpread; rw [dif_pos c]
      have := nextSpread_figs env (if st.page = 1 then 2 else 2 * (st.page / 2 + 1)) (nextPage env st)
        (advance_inv env _ st w).1
      rw [figs_nextPage] at this; exact this
    · unfold nextSpread; rw [dif_neg c]; exact ⟨figs_nextPage env st, (advance_inv env _ st w).1⟩

theorem partTrial_P (env : Env) (runBody runPlain : St → St) (Y : List Slot) (Pin Pout : St → Prop)
    (hb : ∀ s, Pin s → figs (runBody s) = figs s ++ Y ∧ Pout (runBody s))
    (hp : ∀ s, Pin s → figs (runPlain s) = figs s ++ Y ∧ Pout (runPlain s))
    (hff : ∀ s, Pout s → figs (flushFigures env s) = figs s ∧ Pout (flushFigures env s))
    (unit : KeepParts) (fits : St → Bool) (nested whole : Bool) (st : St) (h : Pin st) :
    figs (partTrial env runBody runPlain unit fits nested whole st) = figs st ++ Y ∧
      Pout (partTrial env runBody runPlain unit fits nested whole st) := by
  have p := hp st h
  have b := hb st h
  have fp := hff _ p.2
  have fb := hff _ b.2
  rw [p.1] at fp; rw [b.1] at fb
  simp only [partTrial]
  repeat' split
  all_goals first | exact p | exact fp | exact fb

theorem placeBookPart_P (env : Env) (runBody runPlain : St → St) (Y : List Slot) (Pin Pout : St → Prop)
    (hb : ∀ s, Pin s → figs (runBody s) = figs s ++ Y ∧ Pout (runBody s))
    (hp : ∀ s, Pin s → figs (runPlain s) = figs s ++ Y ∧ Pout (runPlain s))
    (hff : ∀ s, Pout s → figs (flushFigures env s) = figs s ∧ Pout (flushFigures env s))
    (hrep : ∀ u s, Pout s → Pout (addUnmet u s))
    (initial : St) (unit : KeepParts) (kind : Option Nat) (retained : List Nat) (nested whole : Bool)
    (hnu : figs (nextUnit env unit initial) = figs initial ∧ Pin (nextUnit env unit initial))
    (h : Pin initial) :
    figs (placeBookPart env runBody runPlain initial unit kind retained nested whole) = figs initial ++ Y ∧
      Pout (placeBookPart env runBody runPlain initial unit kind retained nested whole) := by
  have m := hnu
  have t0 := partTrial_P env runBody runPlain Y Pin Pout hb hp hff unit (fitsPart unit initial.page retained)
    nested whole initial h
  have t1 := partTrial_P env runBody runPlain Y Pin Pout hb hp hff unit (fitsPart unit initial.page retained)
    nested whole _ m.2
  rw [m.1] at t1
  have b0 := hb initial h
  have b1 := hb _ m.2
  rw [m.1] at b1
  have rep : ∀ k (x : St), figs x = figs initial ++ Y ∧ Pout x →
      figs (addUnmet k x) = figs initial ++ Y ∧ Pout (addUnmet k x) :=
    fun k x hx => ⟨hx.1, hrep k x hx.2⟩
  simp only [placeBookPart]
  repeat' split
  all_goals first
    | exact b0
    | exact t0
    | exact t1
    | exact b1
    | exact rep _ _ b0
    | exact rep _ _ t0
    | exact rep _ _ b1
    | exact rep _ _ t1

theorem applyBreaks_nil (env : Env) (st : St) (h : st.breaks = []) : applyBreaks env st = st := by
  cases st; simp only at h; subst h; rfl

theorem win_needAt (env : Env) (st : St) (x : Option (Nat × Nat)) (w : Win env st) : Win env { st with needAt := x } :=
  ⟨⟨⟨w.inv.weak.first, w.inv.weak.deferred⟩, w.inv.used, w.inv.fig, w.inv.join⟩, w.room, w.breaks, w.need, w.blank⟩

/-- Before a block with a rule waiting, the breaks, the need-lines and the
    blank lines do nothing. -/
theorem prelude_win (env : Env) (st : St) (f : Flow) (rest : List Flow) (w : Win env st) :
    placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest = { st with needAt := none } := by
  rw [applyBreaks_nil env st w.breaks]
  have n : needBefore env st (f :: rest) = { st with needAt := none } := by
    unfold needBefore; rw [w.need]; simp only [applyNeed]
  rw [n]
  unfold placeBlank; simp only [w.blank]

theorem good_env {env env' : Env} (hc : env'.capacity = env.capacity) {st : St} (h : Good env st) : Good env' st := by
  rcases h with i | w
  · exact Or.inl i
  · refine Or.inr ⟨w.inv, ?_, w.breaks, w.need, w.blank⟩
    have : free env' st = free env st := by simp only [free, cap, hc]
    rw [this]; exact w.room

/-- A flow other than a block with rules or a book part has no rule
    waiting before it. -/
theorem plainInv (env : Env) (st : St) (f : Flow) (rest : List Flow) (hg : Good env st)
    (ha : JoinAhead st (f :: rest)) (n1 : ∀ i b a j body, f ≠ .ruled i b a j body)
    (n2 : ∀ u k r body, f ≠ .bookPart u k r body) : Inv st := by
  apply inv_of_good env st hg
  cases e : st.join with
  | none => rfl
  | some jj =>
    exfalso
    have := ha (by simp [e])
    rw [joinsHead_cons f rest n2] at this
    cases f with
    | ruled i b a j body => exact n1 i b a j body rfl
    | bookPart u k r body => exact n2 u k r body rfl
    | _ => simp at this

mutual
theorem place_figs (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (st : St) (f : Flow)
    (rest : List Flow) (hg : Good env st) (ha : JoinAhead st (f :: rest)) (hb : BoxesOk (f :: rest))
    (hq : ∀ i b a j body, f = .ruled i b a j body → st.breaks = [] ∧ st.need = none ∧ st.blank = [])
    (hf : figureOk f) :
    figs (place env st f rest) = figs st ++ flowFigs f ∧ Good env (place env st f rest)
      ∧ JoinAhead (place env st f rest) rest := by
  have up : ∀ r : St, figs r = figs st ++ flowFigs f ∧ Inv r →
      figs r = figs st ++ flowFigs f ∧ Good env r ∧ JoinAhead r rest :=
    fun r x => ⟨x.1, Or.inl x.2, joinAhead_of_none _ x.2.join⟩
  have hI := plainInv env st f rest hg ha
  cases f with
  | paragraph kp ls =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact placeLines_figs env hs kp st true ls h
  | stanza kp vs =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact placeStanza_figs env hs kp st true vs h
  | ruled i b a j body =>
    simp only [place, flowFigs, List.append_nil]
    exact placeRuled_good env hs st i b a j body rest hg (hq i b a j body rfl)
  | wrapped i n beside =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]
    have f0 := flushFigures_figs env st h
    have k := inv_keep env (flushFigures env st) (fun s => needIn env s ⟨max n beside.length, noteLinesOf beside⟩ ⟨0, 0⟩) f0.2
    have fk := figs_keep env (flushFigures env st) (fun s => needIn env s ⟨max n beside.length, noteLinesOf beside⟩ ⟨0, 0⟩)
    generalize keep env (flushFigures env st) (fun s => needIn env s ⟨max n beside.length, noteLinesOf beside⟩ ⟨0, 0⟩) = st1 at k fk
    have ps : Inv (putSlot st1 0 (.wrapped i)) :=
      inv_addUsed k ⟨k.weak.first, k.weak.deferred⟩ 0 (Int.le_refl 0) (by simp [putSlot]) (Int.le_refl _)
        (Or.inl (by simp [putSlot, figSlots_append, figSlots]))
    have fp : figs (putSlot st1 0 (.wrapped i)) = figs st1 := by simp [figs, putSlot, figSlots_append, figSlots]
    have p := placeLines_figs env hs defaultKeep _ false beside ps
    rw [fp, fk, f0.1] at p
    generalize placeLines env defaultKeep (putSlot st1 0 (.wrapped i)) false beside = st3 at p
    split
    · refine ⟨p.1, ?_⟩
      exact inv_addUsed p.2 ⟨p.2.weak.first, p.2.weak.deferred⟩ (max (st1.used + max (n : Int) beside.length) st3.used - st3.used)
        (by have := Int.le_max_right (st1.used + max (n : Int) beside.length) st3.used; omega) (by show max _ _ = _; omega)
        (Int.le_refl _) (Or.inl rfl)
    · exact p
  | continued kp ls =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact placeLines_figs env hs kp st false ls h
  | heading recto n ls =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
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
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    have hf : 1 ≤ n := by simpa [figureOk] using hf
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
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs]
    split
    · rename_i c
      have d0 : st.deferred = [] := isEmpty_nil _ c.1
      have s0 : figSlots st.slots = [] := by
        rcases h.fig with g | g | g
        · exact g
        · have := c.2.2.1; omega
        · have := c.2.2.2.2; omega
      refine ⟨?_, ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩⟩
      simp [figs, pageFigure, pagesFigs_cons, figSlots, d0, s0]
    · exact defer_figs st _ h trivial
  | brk k =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]
    exact ⟨by simp [figs], ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩⟩
  | sectionStart sec k =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]
    exact ⟨by simp [figs], ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩⟩
  | space n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]
    refine ⟨?_, inv_placeSpaceFlow env st n h⟩
    unfold placeSpaceFlow; split <;> rfl
  | needLines n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact ⟨trivial, h⟩
  | blank n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact ⟨trivial, h⟩
  | noBreak =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact ⟨trivial, h⟩
  | noBreakLines n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact ⟨trivial, h⟩
  | keepNext n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact ⟨trivial, h⟩
  | switchColumns n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]
    obtain ⟨f1, i1, _⟩ := flushDeferred_figs env st h
    generalize flushDeferred env st = s1 at f1 i1
    split
    · have := startSet_figs env s1 n i1
      exact ⟨this.1.trans f1, this.2⟩
    · have i2 := inv_nextPage env s1 i1
      exact ⟨(figs_nextPage env s1).trans f1,
        ⟨⟨Or.inl (Int.le_refl 0), i2.weak.deferred⟩, i2.used, i2.fig, i2.join⟩⟩
  | restoreColumns =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]
    split
    · exact ⟨rfl, ⟨⟨Or.inl (Int.le_refl 0), h.weak.deferred⟩, h.used, h.fig, h.join⟩⟩
    · have i2 := inv_nextPage env st h
      exact ⟨figs_nextPage env st,
        ⟨⟨Or.inl (Int.le_refl 0), i2.weak.deferred⟩, i2.used, i2.fig, i2.join⟩⟩
  | adjustLines k =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact ⟨trivial, h⟩
  | bookPart u k r body =>
    simp only [place, flowFigs]
    simp only [figureOk] at hf
    exact runFlows_figs env hc hs st body rest hg (fun n => (joinsHead_bookPart u k r body rest).1 ▸ ha n)
      hb.part'.1 hf
  | boxed i kb ka body =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs]
    simp only [figureOk] at hf
    obtain ⟨hn, hbb⟩ := hb.box'
    have k := inv_keep env st (fun s => (kb : Int) + ka + needIn env s noNeed (env.nextNeed body)) h
    have fk := figs_keep env st (fun s => (kb : Int) + ka + needIn env s noNeed (env.nextNeed body))
    generalize keep env st (fun s => (kb : Int) + ka + needIn env s noNeed (env.nextNeed body)) = st1 at k fk
    have o : Inv (openBox { st1 with box := some ⟨i, kb, ka, 0, false⟩ }) :=
      inv_openBox _ ⟨⟨k.weak.first, k.weak.deferred⟩, k.used, k.fig, k.join⟩
    have r0 := runFlows_figs env hc hs _ body rest (Or.inl o) (joinAhead_of_none _ o.join) hbb hf
    have r : figs (runFlows env (openBox { st1 with box := some ⟨i, kb, ka, 0, false⟩ }) body rest)
        = figs (openBox { st1 with box := some ⟨i, kb, ka, 0, false⟩ }) ++ sourceFigs body
        ∧ Inv (runFlows env (openBox { st1 with box := some ⟨i, kb, ka, 0, false⟩ }) body rest) := by
      refine ⟨r0.1, inv_of_good env _ r0.2.1 ?_⟩
      cases e : (runFlows env (openBox { st1 with box := some ⟨i, kb, ka, 0, false⟩ }) body rest).join with
      | none => rfl
      | some _ => have := r0.2.2 (by simp [e]); rw [hn] at this; cases this
    rw [figs_openBox] at r
    generalize runFlows env (openBox { st1 with box := some ⟨i, kb, ka, 0, false⟩ }) body rest = ib at r
    refine ⟨?_, ?_⟩
    · show figs (drainPendingNotes env _) = _; rw [figs_drainPendingNotes]; show figs ib = _; rw [r.1]; congr 1
    · refine inv_drainPendingNotes env _ hs ?_
      exact inv_addUsed r.2 ⟨r.2.weak.first, r.2.weak.deferred⟩ (max ib.used (boxEnd ib) - ib.used)
          (by have := Int.le_max_left ib.used (boxEnd ib); omega) (by show max _ _ = _; omega) (Int.le_refl _)
          (Or.inl rfl)
  | code g c first cont ls =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]; exact placeCode_figs env g c first cont st true h ls
  | defTerm ls =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]
    split
    · have k := inv_keep env st (fun s => needIn env s ⟨ls.length, noteLinesOf ls⟩ (env.nextNeed rest)) h
      have := placeLines_figs env hs defaultKeep _ true ls k
      rw [figs_keep] at this; exact this
    · exact placeLines_figs env hs _ st true ls h
  | table sp0 hd rows capt below =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [place, flowFigs, List.append_nil]
    have sp0' : (0 : Int) ≤ sp0 := Int.ofNat_nonneg sp0
    have hsp : (0 : Int) ≤ (if st.used = top st then 0 else (sp0 : Int)) := by split <;> omega
    generalize (if st.used = top st then 0 else (sp0 : Int)) = sp at hsp ⊢
    by_cases kc : env.keepColumn = true
    · rw [if_pos kc]
      have s1 : figs (if sp + (tableHead hd rows capt below : Int) ≤ free env st ∨ isEmpty st = true
            then { st with used := st.used + max 0 (min sp (free env st)) }
            else keep env (nextColumn env st) (fun _ => (tableHead hd rows capt below : Int))) = figs st ∧
          Inv (if sp + (tableHead hd rows capt below : Int) ≤ free env st ∨ isEmpty st = true
            then { st with used := st.used + max 0 (min sp (free env st)) }
            else keep env (nextColumn env st) (fun _ => (tableHead hd rows capt below : Int))) := by
        split
        · rename_i c
          exact ⟨rfl, tableStart_inv env st h _⟩
        · exact ⟨by rw [figs_keep, figs_nextColumn], inv_keep env _ _ (inv_nextColumn env st h)⟩
      have := placeTable_figs env hs _ hd rows capt below s1.2
      rw [s1.1] at this; exact this
    · rw [if_neg kc]
      have s1 : figs (if sp ≤ free env st then { st with used := st.used + sp } else nextColumn env st) = figs st ∧
          Inv (if sp ≤ free env st then { st with used := st.used + sp } else nextColumn env st) := by
        split
        · exact ⟨rfl, inv_addUsed h ⟨h.weak.first, h.weak.deferred⟩ _ hsp rfl (Int.le_refl _)
            (Or.inl rfl)⟩
        · exact ⟨figs_nextColumn env st, inv_nextColumn env st h⟩
      have := acrossGo_figs env hs hd capt below true true false _ (tableGroups hd rows capt below) s1.2
      rw [s1.1] at this; exact this
termination_by (flowWeight f, 0)
decreasing_by all_goals simp_wf; (try subst_vars); apply Prod.Lex.left; simp only [flowWeight]; omega

theorem placeFlow_figs (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (st : St) (f : Flow)
    (rest : List Flow) (hg : Good env st) (ha : JoinAhead st (f :: rest)) (hb : BoxesOk (f :: rest))
    (hq : ∀ i b a j body, f = .ruled i b a j body → st.breaks = [] ∧ st.need = none ∧ st.blank = [])
    (hf : figureOk f) :
    figs (placeFlow env st f rest) = figs st ++ flowFigs f ∧ Good env (placeFlow env st f rest)
      ∧ JoinAhead (placeFlow env st f rest) rest := by
  have up : ∀ r : St, figs r = figs st ++ flowFigs f ∧ Inv r →
      figs r = figs st ++ flowFigs f ∧ Good env r ∧ JoinAhead r rest :=
    fun r x => ⟨x.1, Or.inl x.2, joinAhead_of_none _ x.2.join⟩
  have hI := plainInv env st f rest hg ha
  have pl : ∀ kp s b xs, Inv s → figs (placeLines env kp s b xs) = figs s ∧ Inv (placeLines env kp s b xs) :=
    fun kp s b xs i => placeLines_figs env hs kp s b xs i
  unfold placeFlow
  split
  · have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [flowFigs, List.append_nil]; exact placeKept_figs env _ _ (pl _) st true _ _ h
  · have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [flowFigs, List.append_nil]
    exact placeKept_figs env _ _ (fun s b xs i => placeStanza_figs env hs _ s b xs i) st true _ _ h
  · have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [flowFigs, List.append_nil]; exact placeKept_figs env _ _ (pl _) st false _ _ h
  · have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    rename_i ls n _
    simp only [flowFigs, List.append_nil]
    have i : figs (if 0 < env.keepLast rest then st
        else keep env st (fun s => needIn env s ⟨ls.length, noteLinesOf ls⟩ (env.nextNeed rest))) = figs st ∧
        Inv (if 0 < env.keepLast rest then st
        else keep env st (fun s => needIn env s ⟨ls.length, noteLinesOf ls⟩ (env.nextNeed rest))) := by
      split
      · exact ⟨rfl, h⟩
      · exact ⟨figs_keep .., inv_keep env st _ h⟩
    have := placeKept_figs env (previousKeep env rest defaultKeep) (placeLines env defaultKeep) (pl _) _ true ls n i.2
    rw [i.1] at this; exact this
  · exact place_figs env hc hs _ _ rest hg ha hb hq hf
termination_by (flowWeight f, 1)
decreasing_by all_goals simp_wf; apply Prod.Lex.right; decide

theorem step_figs (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (st : St) (f : Flow) (rest : List Flow)
    (hg : Good env st) (ha : JoinAhead st (f :: rest)) (hb : BoxesOk (f :: rest)) (hf : figureOk f) :
    figs (step env st f rest) = figs st ++ flowFigs f ∧ Good env (step env st f rest)
      ∧ JoinAhead (step env st f rest) rest := by
  have up : ∀ r : St, figs r = figs st ++ flowFigs f ∧ Inv r →
      figs r = figs st ++ flowFigs f ∧ Good env r ∧ JoinAhead r rest :=
    fun r x => ⟨x.1, Or.inl x.2, joinAhead_of_none _ x.2.join⟩
  have hI := plainInv env st f rest hg ha
  have general : (∀ i b a j body, f ≠ .ruled i b a j body) → (∀ u k r body, f ≠ .bookPart u k r body) →
      ∀ (a : Bool) (sp : List (Nat × Int)),
      let r : St := if waitsBehind (applyBreaks env st) f then checkNoBreak (place env (applyBreaks env st) f rest)
        else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest)
      figs { r with seen := true, lastDeferred := a, spaces := sp } = figs st ++ flowFigs f ∧
        Good env { r with seen := true, lastDeferred := a, spaces := sp } ∧
        JoinAhead { r with seen := true, lastDeferred := a, spaces := sp } rest := by
    intro n1 n2 a sp
    have h := hI n1 n2
    have b := applyBreaks_figs env st h
    have nq : ∀ s : St, ∀ i b' a' j body, f = .ruled i b' a' j body → s.breaks = [] ∧ s.need = none ∧ s.blank = [] :=
      fun _ i b' a' j body e => absurd e (n1 i b' a' j body)
    have core : figs (if waitsBehind (applyBreaks env st) f then checkNoBreak (place env (applyBreaks env st) f rest)
        else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest))
        = figs st ++ flowFigs f ∧
        Good env (if waitsBehind (applyBreaks env st) f then checkNoBreak (place env (applyBreaks env st) f rest)
        else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest)) ∧
        JoinAhead (if waitsBehind (applyBreaks env st) f then checkNoBreak (place env (applyBreaks env st) f rest)
        else checkNoBreak (placeFlow env (placeBlank env (needBefore env (applyBreaks env st) (f :: rest)) f rest) f rest)) rest := by
      split
      · have p := place_figs env hc hs _ f rest (Or.inl b.2) (joinAhead_of_none _ b.2.join) hb (nq _) hf
        have c := good_checkNoBreak env _ p.2.1
        rw [p.1, b.1] at c
        exact ⟨c.1, c.2.1, fun ne => p.2.2 (c.2.2 ▸ ne)⟩
      · have n := needBefore_figs env (applyBreaks env st) (f :: rest) b.2
        have k := placeBlank_figs env (by omega) _ f rest n.2
        have p := placeFlow_figs env hc hs _ f rest (Or.inl k.2) (joinAhead_of_none _ k.2.join) hb (nq _) hf
        have c := good_checkNoBreak env _ p.2.1
        rw [p.1, k.1, n.1, b.1] at c
        exact ⟨c.1, c.2.1, fun ne => p.2.2 (c.2.2 ▸ ne)⟩
    exact ⟨core.1, good_seen env _ a sp core.2.1, core.2.2⟩
  have ctl : Inv st → ∀ (u : Unmet) (k : Nat × Bool),
      figs (if st.seen = false ∨ st.lastDeferred = true then addUnmet u st else waitFor u k st) = figs st ∧
      Inv (if st.seen = false ∨ st.lastDeferred = true then addUnmet u st else waitFor u k st) := by
    intro h u k; split
    · exact ⟨rfl, ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩⟩
    · exact waitFor_figs u k st h
  cases f with
  | needLines n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [step, flowFigs, List.append_nil]; exact needMore_figs env n st h
  | bookPart u k r body =>
    simp only [step, flowFigs]
    simp only [figureOk] at hf
    have init : figs (if r = [] then st else applyBreaks env st) = figs st ∧
        Good env (if r = [] then st else applyBreaks env st) ∧
        JoinAhead (if r = [] then st else applyBreaks env st) (.bookPart u k r body :: rest) := by
      split
      · exact ⟨rfl, hg, ha⟩
      · rcases hg with h | w
        · have b := applyBreaks_figs env st h; exact ⟨b.1, Or.inl b.2, joinAhead_of_none _ b.2.join⟩
        · rw [applyBreaks_nil env st w.breaks]; exact ⟨rfl, Or.inr w, ha⟩
    generalize (if r = [] then st else applyBreaks env st) = s0 at init
    obtain ⟨jb, jp⟩ := joinsHead_bookPart u k r body rest
    obtain ⟨bb, bp⟩ := hb.part'
    have ge1 : ∀ s, Good env s → Good { env with keepParts := u, inBookPart := true } s :=
      fun _ x => good_env (env := env) (env' := { env with keepParts := u, inBookPart := true }) rfl x
    have ge2 : ∀ s, Good { env with keepParts := u, inBookPart := true } s → Good env s :=
      fun _ x => good_env (env := { env with keepParts := u, inBookPart := true }) (env' := env) rfl x
    have := placeBookPart_P env (fun s => runFlows { env with keepParts := u, inBookPart := true } s body rest)
      (fun s => runFlows { env with keepParts := u, inBookPart := true } s (flattenParts body) rest) (sourceFigs body)
      (fun s => Good env s ∧ JoinAhead s (.bookPart u k r body :: rest))
      (fun s => Good env s ∧ JoinAhead s rest)
      (fun s x => by
        have := runFlows_figs { env with keepParts := u, inBookPart := true } hc hs s body rest
          (ge1 _ x.1) (fun n => jb ▸ x.2 n) bb hf
        exact ⟨this.1, ge2 _ this.2.1, this.2.2⟩)
      (fun s x => by
        have := runFlows_figs { env with keepParts := u, inBookPart := true } hc hs s (flattenParts body) rest
          (ge1 _ x.1) (fun n => jp ▸ x.2 n) bp (figuresOk_flatten body hf)
        rw [sourceFigs_flatten] at this; exact ⟨this.1, ge2 _ this.2.1, this.2.2⟩)
      (fun s x => by
        have := flushFigures_good env s x.1
        rcases this.2 with e | i
        · rw [e]; exact ⟨rfl, x⟩
        · exact ⟨this.1, Or.inl i, joinAhead_of_none _ i.join⟩)
      (fun u' s x => ⟨good_addUnmet env u' s x.1, x.2⟩)
      s0 u (some k) r (anyNested body) ((flowsSlotIds (flattenParts body)).all r.contains)
      (by have := nextUnit_inv env u s0 (good_weak env s0 init.2.1)
          exact ⟨this.1, Or.inl this.2, joinAhead_of_none _ this.2.join⟩)
      ⟨init.2.1, init.2.2⟩
    rw [init.1] at this; exact this
  | adjustLines k =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    have b := applyBreaks_figs env st h
    simp only [step, flowFigs, List.append_nil]
    have i := b.2
    refine ⟨?_, ?_⟩
    · rw [figs_drainPendingNotes, ← b.1]; simp only [adjustLines]; split <;> rfl
    · apply inv_drainPendingNotes env _ hs
      simp only [adjustLines]; split
      · exact ⟨⟨i.weak.first, i.weak.deferred⟩, i.used, i.fig, i.join⟩
      · exact ⟨⟨i.weak.first, i.weak.deferred⟩, i.used, i.fig, i.join⟩
  | noBreak =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [step, flowFigs, List.append_nil]; exact ctl h _ _
  | noBreakLines n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    cases n with
    | zero => simp only [step, flowFigs, List.append_nil]; exact ⟨trivial, h⟩
    | succ m => simp only [step, flowFigs, List.append_nil]; exact ctl h _ _
  | keepNext n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [step, flowFigs, List.append_nil]; exact ctl h _ _
  | blank n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    simp only [step, flowFigs, List.append_nil]
    split
    · exact ⟨rfl, h⟩
    · exact ⟨rfl, ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩⟩
  | brk k =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    simp only [step]
    exact place_figs env hc hs st (.brk k) rest (Or.inl h) (joinAhead_of_none _ h.join) hb
      (fun _ _ _ _ _ e => Flow.noConfusion e) hf
  | sectionStart sec k =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    simp only [step]
    exact place_figs env hc hs st (.sectionStart sec k) rest (Or.inl h) (joinAhead_of_none _ h.join) hb
      (fun _ _ _ _ _ e => Flow.noConfusion e) hf
  | space n =>
    have h := hI (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e)
    refine up _ ?_
    have b := applyBreaks_figs env st h
    simp only [step, flowFigs, List.append_nil]
    have s := inv_needBeforeSpaces env _ b.2
    refine ⟨?_, inv_placeSpace env _ n s⟩
    show figs (placeSpaceFlow env _ n) = _
    have : figs (placeSpaceFlow env (needBeforeSpaces env (applyBreaks env st)) n)
        = figs (needBeforeSpaces env (applyBreaks env st)) := by
      unfold placeSpaceFlow; split <;> rfl
    rw [this, figs_needBeforeSpaces, b.1]
  | paragraph kp ls =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | continued kp ls =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | heading recto n ls =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | figure i n =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | pageFigure i =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | code g' c first cont ls =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | defTerm ls =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | table sp0 h rows capt below =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | switchColumns n =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | restoreColumns =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | stanza kp vs =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | wrapped i n beside =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | boxed i kb ka body =>
    simp only [step]
    exact general (fun _ _ _ _ _ e => Flow.noConfusion e) (fun _ _ _ _ e => Flow.noConfusion e) _ _
  | ruled i b a j body =>
    simp only [step]
    -- the breaks, the need-lines and the blank lines before the block
    have pre : figs (placeBlank env (needBefore env (applyBreaks env st) (.ruled i b a j body :: rest)) (.ruled i b a j body) rest) = figs st
        ∧ Good env (placeBlank env (needBefore env (applyBreaks env st) (.ruled i b a j body :: rest)) (.ruled i b a j body) rest)
        ∧ JoinAhead (placeBlank env (needBefore env (applyBreaks env st) (.ruled i b a j body :: rest)) (.ruled i b a j body) rest)
            (.ruled i b a j body :: rest)
        ∧ (placeBlank env (needBefore env (applyBreaks env st) (.ruled i b a j body :: rest)) (.ruled i b a j body) rest).breaks = []
        ∧ (placeBlank env (needBefore env (applyBreaks env st) (.ruled i b a j body :: rest)) (.ruled i b a j body) rest).need = none
        ∧ (placeBlank env (needBefore env (applyBreaks env st) (.ruled i b a j body :: rest)) (.ruled i b a j body) rest).blank = [] := by
      rcases hg with h | w
      · have b0 := applyBreaks_figs env st h
        have n := needBefore_figs env (applyBreaks env st) (.ruled i b a j body :: rest) b0.2
        have k := placeBlank_figs env (by omega) _ (.ruled i b a j body) rest n.2
        obtain ⟨a1, _, _⟩ := applyBreaks_frame env st
        obtain ⟨n1, n2, _⟩ := needBefore_frame env (applyBreaks env st) (.ruled i b a j body :: rest)
        obtain ⟨k1, k2, k3⟩ := placeBlank_frame env (needBefore env (applyBreaks env st) (.ruled i b a j body :: rest))
          (.ruled i b a j body) rest
        exact ⟨k.1.trans (n.1.trans b0.1), Or.inl k.2, joinAhead_of_none _ k.2.join, k1.trans (n1.trans a1),
          k2.trans n2, k3⟩
      · rw [prelude_win env st _ rest w]
        exact ⟨rfl, Or.inr (win_needAt env st none w), ha, w.breaks, w.need, w.blank⟩
    generalize placeBlank env (needBefore env (applyBreaks env st) (.ruled i b a j body :: rest)) (.ruled i b a j body) rest
      = s at pre
    obtain ⟨f0, g0, a0, q1, q2, q3⟩ := pre
    have p := placeFlow_figs env hc hs s (.ruled i b a j body) rest g0 a0 hb (fun _ _ _ _ _ _ => ⟨q1, q2, q3⟩) hf
    have c := good_checkNoBreak env _ p.2.1
    rw [p.1, f0] at c
    exact ⟨c.1, good_seen env _ _ _ c.2.1, fun ne => p.2.2 (c.2.2 ▸ ne)⟩
termination_by (flowWeight f, 2)
decreasing_by
  all_goals simp_wf
  all_goals try subst_vars
  all_goals first
    | (apply Prod.Lex.right; decide)
    | (apply Prod.Lex.left; simp only [flowWeight]; omega)
    | (apply Prod.Lex.left; have := flattenParts_weight body; simp only [flowWeight]; omega)

theorem runFlows_figs (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (st : St) (fs : List Flow)
    (rest : List Flow) (hg : Good env st) (ha : JoinAhead st (fs ++ rest)) (hb : BoxesOk (fs ++ rest))
    (hf : figuresOk fs) :
    figs (runFlows env st fs rest) = figs st ++ sourceFigs fs ∧ Good env (runFlows env st fs rest)
      ∧ JoinAhead (runFlows env st fs rest) rest := by
  match fs with
  | [] => unfold runFlows; simp only [sourceFigs, List.append_nil]; exact ⟨trivial, hg, ha⟩
  | g :: more =>
    unfold runFlows
    simp only [figuresOk] at hf
    have s := step_figs env hc hs st g (more ++ rest) hg ha hb hf.1
    have r := runFlows_figs env hc hs _ more rest s.2.1 s.2.2 hb.tail' hf.2
    rw [s.1] at r
    simp only [sourceFigs, List.append_assoc] at r ⊢
    exact r
termination_by (flowsWeight fs, 3)
decreasing_by
  all_goals simp_wf
  all_goals apply Prod.Lex.left; simp only [flowsWeight]; omega

end

theorem placeAll_figs (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (flows : List Flow) (st : St)
    (hg : Good env st) (ha : JoinAhead st flows) (hb : BoxesOk flows) (hf : ∀ f ∈ flows, figureOk f) :
    figs (placeAll env st flows) = figs st ++ sourceFigs flows ∧ (placeAll env st flows).deferred = [] := by
  induction flows generalizing st with
  | nil =>
    have h := inv_of_good env st hg (joinAhead_nil ha)
    simp only [placeAll, sourceFigs, List.append_nil]
    rw [addUnmets_eq]
    generalize st.unmet ++ st.noBreak.map (fun w => w.1) = u
    have h2 : Inv { st with unmet := u, breaks := [], need := none, needAt := none, noBreak := [], blank := [] } :=
      ⟨⟨h.weak.first, h.weak.deferred⟩, h.used, h.fig, h.join⟩
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
    have s := step_figs env hc hs st f rest hg ha hb (hf f (List.mem_cons_self f rest))
    have := ih (step env st f rest) s.2.1 s.2.2 hb.tail' (fun g m => hf g (List.mem_cons_of_mem f m))
    refine ⟨?_, this.2⟩
    rw [this.1, s.1]
    simp [sourceFigs, List.cons_bind, List.append_assoc]

/-- Root ADR 0352 invariant 5 for the figures: the pages of the
    pagination hold every figure and turned figure written, each once,
    in the order written.  It assumes that every figure is at least one
    line high, that a column holds 1 line or more, that the footnote
    separator takes 0 lines or more (golem-layout clamps it to 1 line or
    more) and that no block after a box shares the area of a rule waiting
    (`BoxesOk`, as golem-typeset links the ruled blocks after it makes
    the boxes); README.md shows the input that breaks the order with a
    figure of no lines. -/
theorem I5_paginate_figures (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator) (flows : List Flow)
    (hf : ∀ f ∈ flows, figureOk f) (hb : BoxesOk flows) :
    pagesFigs (paginate env flows).done = sourceFigs flows := by
  have i : Inv (initialState env) := ⟨⟨Or.inl (Int.le_refl 0), trivial⟩, Or.inl (Int.le_refl 0), Or.inl rfl, rfl⟩
  obtain ⟨h, d⟩ := placeAll_figs env hc hs flows (initialState env) (Or.inl i) (joinAhead_of_none _ rfl) hb hf
  have e : figs (initialState env) = [] := rfl
  rw [e, List.nil_append] at h
  simp only [paginate, closePage]
  generalize placeAll env (initialState env) flows = st at h d
  simp only [figs, d, List.map, List.append_nil] at h
  split
  · rename_i c
    have s : st.slots = [] := isEmpty_nil _ c.1
    simp only [s, figSlots, List.append_nil] at h
    exact h
  · rw [pagesFigs_cons]; exact h

/-! ## Root ADR 0440: no figure of no lines reaches the pagination -/

/-- The flows golem-typeset lets reach the pagination under root ADR
    0440: a figure of no grid lines is kept off the pages with its error
    (G07135, `keepsOffPages` and `numberFigure` of Flow.hs), here at any
    depth of boxes and book parts. -/
def admitFigures : List Flow → List Flow
  | [] => []
  | .figure i n :: r => if n = 0 then admitFigures r else .figure i n :: admitFigures r
  | .bookPart u k t b :: r => .bookPart u k t (admitFigures b) :: admitFigures r
  | .boxed i kb ka b :: r => .boxed i kb ka (admitFigures b) :: admitFigures r
  | f :: r => f :: admitFigures r
termination_by fs => sizeOf fs

theorem figuresOk_mem : ∀ {fs : List Flow}, figuresOk fs → ∀ f ∈ fs, figureOk f
  | [], _, _, m => absurd m (List.not_mem_nil _)
  | g :: r, h, f, m => by
    simp only [figuresOk] at h
    rcases List.mem_cons.mp m with e | m
    · subst e; exact h.1
    · exact figuresOk_mem h.2 f m

/-- Every figure that root ADR 0440 lets through is a line high or more. -/
theorem figuresOk_admit (fs : List Flow) : figuresOk (admitFigures fs) := by
  match fs with
  | [] => simp [admitFigures, figuresOk]
  | f :: r =>
    have := figuresOk_admit r
    cases f with
    | figure i n =>
      simp only [admitFigures]
      split
      · exact this
      · rename_i h
        simp only [figuresOk, figureOk]; exact ⟨by omega, this⟩
    | bookPart u k t b =>
      have := figuresOk_admit b
      simp only [admitFigures, figuresOk, figureOk]; exact ⟨by assumption, by assumption⟩
    | boxed j kb ka b =>
      have := figuresOk_admit b
      simp only [admitFigures, figuresOk, figureOk]; exact ⟨by assumption, by assumption⟩
    | _ => simp only [admitFigures, figuresOk, figureOk]; exact ⟨trivial, this⟩
termination_by sizeOf fs

/-- Root ADR 0352 invariant 5 for the figures on the flows root ADR 0440
    lets through: `I5_paginate_figures` without its hypothesis on the
    height of the figures, which G07135 discharges. -/
theorem I5_paginate_figures_admitted (env : Env) (hc : 1 ≤ env.capacity) (hs : 0 ≤ env.separator)
    (flows : List Flow) (hb : BoxesOk (admitFigures flows)) :
    pagesFigs (paginate env (admitFigures flows)).done = sourceFigs (admitFigures flows) :=
  I5_paginate_figures env hc hs _ (figuresOk_mem (figuresOk_admit flows)) hb

/-! ## Root ADR 0444: the continued notes take the room `@page-lines` adds -/

theorem partsLines_cons (p : NotePart) (ps : List NotePart) : partsLines (p :: ps) = p.2.2 + partsLines ps := rfl

/-- `takeNoteLines` that leaves notes takes exactly the lines asked for. -/
theorem takeNoteLines_full (r : Int) (ps : List NotePart) (hr : 0 ≤ r) (h : (takeNoteLines r ps).2 ≠ []) :
    (partsLines (takeNoteLines r ps).1 : Int) = r := by
  induction ps generalizing r with
  | nil => simp [takeNoteLines] at h
  | cons p more ih =>
    obtain ⟨i, f, l⟩ := p
    simp only [takeNoteLines] at h ⊢
    split
    · simp [partsLines]; omega
    · rename_i h1
      split
      · rename_i h2
        rw [if_neg h1, if_pos h2] at h
        have := ih (r - l) (by omega) h
        simp only [partsLines_cons] at this ⊢
        push_cast; omega
      · show ((r.toNat + 0 : Nat) : Int) = r
        rw [Nat.add_zero]; exact Int.toNat_of_nonneg hr

/-- Root ADR 0444 I2 on the grid: after `@page-lines` the continued notes
    that do not fit leave the column no room but the line it keeps when it
    has no text yet, or the separator they did not use. -/
theorem drain_room (env : Env) (st : St) (hs : 0 ≤ env.separator)
    (h : (drainPendingNotes env st).pending ≠ []) :
    free env (drainPendingNotes env st) ≤ drainSep env st + (if st.slots.isEmpty then 1 else 0) := by
  have s0 : 0 ≤ drainSep env st := by unfold drainSep; split <;> omega
  have dr : drainRoom env st = free env st - drainSep env st - (if st.slots.isEmpty then 1 else 0) := rfl
  by_cases c : st.pending.isEmpty = true ∨ drainRoom env st ≤ 0
  · have e : drainPendingNotes env st = st := by unfold drainPendingNotes; rw [if_pos c]
    rw [e] at h ⊢
    rcases c with c | c
    · exfalso; apply h
      cases hp : st.pending with
      | nil => rfl
      | cons _ _ => rw [hp] at c; simp [List.isEmpty] at c
    · omega
  · have r : 0 < drainRoom env st := by
      have := (not_or.mp c).2; omega
    have e : drainPendingNotes env st =
        { st with notes := (takeNoteLines (drainRoom env st) st.pending).1.foldl joinNotePart st.notes,
                  noteLines := st.noteLines + drainSep env st + partsLines (takeNoteLines (drainRoom env st) st.pending).1,
                  pending := (takeNoteLines (drainRoom env st) st.pending).2 } := by
      unfold drainPendingNotes; rw [if_neg c]
    rw [e] at h ⊢
    have full := takeNoteLines_full _ _ (by omega) h
    generalize takeNoteLines (drainRoom env st) st.pending = p at full ⊢
    simp only [free, cap, boxAfter] at dr ⊢
    omega

end WholePagination
