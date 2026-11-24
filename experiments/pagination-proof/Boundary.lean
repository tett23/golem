/- Root ADR 0352: the boundary inputs of `boundaryTableTests`
   (modules/golem-layout/test/PaginateSpec.hs) on the paginate of
   Whole.lean.  `boundaryEnv` is the `Env` of `paginate 1 capacity` of
   Paginate.hs, its parameters computed as Paginate/Decide.hs computes
   them.  `main` prints the pages and the unmet keeps of every input in the format of
   Boundary.hs, and check.sh compares the two with diff.  This is a check
   on finitely many inputs, not a proof; the definitions below are
   `partial` because they are only evaluated. -/
import Whole
open WholePagination

namespace Boundary

instance : Inhabited Need := ⟨⟨0, 0⟩⟩

def grid (n : Nat) : Need := ⟨n, 0⟩
def plus (a b : Need) : Need := ⟨a.grid + b.grid, a.notes + b.notes⟩
def linesNeed (ls : List Line) : Need := ⟨ls.length, noteLinesOf ls⟩

/-- `firstPart` of Decide.hs. -/
def firstPart (kp : Keep) (isStart : Bool) (n : Nat) : Nat :=
  if kp.all then n
  else ((List.range (n + 1)).filter (fun k => min kp.first n ≤ k ∧ splitAtBreak kp isStart n k = k)).headD n

/-- `soft` of Decide.hs. -/
def soft : Flow → Bool
  | .noBreakLines 0 | .needLines _ | .adjustLines _ | .space _ => true
  | _ => false

/-- The control of `keepAhead` of Decide.hs. -/
def control : Flow → Option (Nat × Nat)
  | .noBreak => some (2, 0)
  | .noBreakLines n => some (n, 0)
  | .keepNext n _ => some (0, n)
  | _ => none

/-- The loop of `keepAhead` of Decide.hs. -/
partial def keepAheadGo (before : List Flow) (lastLines firstLines : Nat) (after : List Flow) :
    List Flow × Nat × Nat × List Flow :=
  match after.dropWhile soft with
  | c :: after' =>
    match control c with
    | some (l, f) => keepAheadGo (before ++ after.takeWhile soft) (max lastLines l) (max firstLines f) after'
    | none => (before, lastLines, firstLines, after)
  | [] => (before, lastLines, firstLines, after)

/-- `keepAhead` of Decide.hs. -/
def keepAhead (rest : List Flow) : Option (List Flow × Nat × Nat × List Flow) :=
  match rest.dropWhile soft with
  | c :: after =>
    match control c with
    | some (l, f) => some (keepAheadGo (rest.takeWhile soft) l f after)
    | none => none
  | [] => none

/-- `spaced` of Decide.hs. -/
def spaced (capacity n : Nat) (r : Need) : Need := { r with grid := min capacity (n + r.grid) }

def spacesIn (fs : List Flow) : Nat :=
  (fs.filterMap fun | .space k => some k | _ => none).foldr (· + ·) 0

/-- The grid lines of the area of a rule inside a column (`insideBefore`
    and `insideAfter` of Decide.hs) for the rule of Boundary.hs: a rule
    of weight 12 on a grid of pitch 10 and face 8, no spaces, no overhang
    and not out of the column. -/
def ruleLines : Nat := 1

/-- `codeSpan` of Code.hs for the geometries of Boundary.hs: rows of one
    grid line each, without padding (0) or with half a line of padding
    above and below (1). -/
def codeLines (geometry rows : Nat) : Nat := if geometry = 0 then max 1 rows else max 1 rows + 1

/-- `holds` of Decide.hs: a keep-with-next of a visible separator among
    the controls at the start of the flows (root ADR 0398 I7). -/
def holds (held : Nat → Bool) : List Flow → Bool
  | .keepNext _ sp :: more => held sp || holds held more
  | .noBreak :: more | .noBreakLines _ :: more => holds held more
  | f :: more => if soft f then holds held more else false
  | [] => false

mutual
/-- `nextNeed` of Decide.hs, of a column of `capacity` lines in a base set
    of `columns` columns, the keeps of the visible separators `held`. -/
partial def nextNeed (held : Nat → Bool) (capacity columns : Nat) : List Flow → Need
  | [] => grid 0
  | .bookPart _ _ _ body :: rest => nextNeed held capacity columns (body ++ rest)
  | f :: rest =>
    if startsRecto f then grid 0 else
    match f with
    | .paragraph kp ls =>
      chained held capacity columns false ls.length (firstPart kp true ls.length) (fun k => linesNeed (ls.take k)) rest
    | .continued kp ls =>
      chained held capacity columns false ls.length (firstPart kp false ls.length) (fun k => linesNeed (ls.take k)) rest
    | .stanza kp vs =>
      chained held capacity columns false vs.length (firstPart kp true vs.length) (fun k => linesNeed (vs.take k).join) rest
    | .table sp h rows capt below => grid (sp + tableHead h rows capt below)
    | .defTerm ls => linesNeed ls
    | .heading _ n ls => plus ⟨n, noteLinesOf ls⟩ (nextNeed held capacity columns rest)
    | .figure _ n => grid (min n capacity)
    | .pageFigure _ => grid 0
    -- with the notes of the side lines (root ADR 0443)
    | .wrapped _ n ls => ⟨max n ls.length, noteLinesOf ls⟩
    | .space n => spaced capacity n (nextNeed held capacity columns rest)
    | .brk _ | .sectionStart _ _ => grid 0
    | .noBreak | .noBreakLines _ | .keepNext _ _ | .needLines _ | .adjustLines _ => nextNeed held capacity columns rest
    | .blank n => let r := nextNeed held capacity columns rest; { r with grid := min capacity (min capacity n + r.grid) }
    | .code g caption first cont ls =>
      if ls.isEmpty then grid 0
      else
        let k := min ls.length (max 1 first)
        grid (caption + codeLines g (k + (if cont && k < ls.length then 1 else 0)))
    | .switchColumns _ => if columns = 1 then nextNeed held capacity columns rest else grid 0
    | .restoreColumns => grid 0
    | .ruled _ before after _ body =>
      let size := (if before then ruleLines else 0) + body.size + (if after then ruleLines else 0)
      match body with
      | .heading _ _ ls => ⟨size, noteLinesOf ls⟩
      | .lines _ _ => grid size
    | .boxed _ kb ka body =>
      let n := nextNeed held capacity columns body
      let whole := match body with
        | [.paragraph kp ls] => decide (ls.length ≤ firstPart kp true ls.length)
        | [.stanza kp vs] => decide (vs.length ≤ firstPart kp true vs.length)
        | _ => false
      { n with grid := kb + n.grid + (if whole then ka else 0) }
    | .bookPart _ _ _ _ => grid 0

/-- `followNeed` of Decide.hs: after a separator hold when `h`, what a
    no-break after the whole first part keeps is added too. -/
partial def followNeed (held : Nat → Bool) (capacity columns : Nat) (h : Bool) (n : Nat) (after : List Flow) : Need :=
  if n = 0 ∧ h = false then nextNeed held capacity columns after
  else match after with
    | .paragraph kp ls :: more =>
      chained held capacity columns h ls.length (max (firstPart kp true ls.length) (min n ls.length)) (fun k => linesNeed (ls.take k)) more
    | .continued kp ls :: more =>
      chained held capacity columns h ls.length (max (firstPart kp false ls.length) (min n ls.length)) (fun k => linesNeed (ls.take k)) more
    | .stanza kp vs :: more =>
      chained held capacity columns h vs.length (max (firstPart kp true vs.length) (min n vs.length)) (fun k => linesNeed (vs.take k).join) more
    | _ => nextNeed held capacity columns after

/-- `chainedHeld` of Decide.hs (`chained` when `h` is false). -/
partial def chained (held : Nat → Bool) (capacity columns : Nat) (h : Bool) (total k : Nat) (needOf : Nat → Need)
    (more : List Flow) : Need :=
  let base := needOf k
  match keepAhead more with
  | some (before, l, m, after') =>
    if total ≤ k ∧ (0 < m ∨ (h = true ∧ 0 < l)) then
      let r := spaced capacity (spacesIn before) (followNeed held capacity columns (holds held more) m after')
      ⟨min capacity (base.grid + r.grid), base.notes + r.notes⟩
    else base
  | none => base
end

/-- `keptNeed` of Decide.hs. -/
def keptNeed (held : Nat → Bool) (capacity columns : Nat) (rest : List Flow) : Option Need :=
  let flat := flattenParts rest
  (keepAhead flat).map fun (before, _, n, after) =>
    spaced capacity (spacesIn before) (followNeed held capacity columns (holds held flat) n after)

/-- `nextFirstLines` of Decide.hs. -/
partial def nextFirst (n : Nat) (after : List Flow) : Nat × Bool :=
  let skipped : Flow → Bool
    | .space _ | .needLines _ | .adjustLines _ | .noBreak | .noBreakLines _ | .keepNext _ _ | .blank _ => true
    | _ => false
  match (flattenParts after).dropWhile skipped with
  | .bookPart _ _ _ body :: more => nextFirst n (body ++ more)
  | .boxed _ _ _ body :: _ => nextFirst n body
  | .paragraph kp ls :: _ => (max (firstPart kp true ls.length) (min n ls.length), true)
  | .continued kp ls :: _ => (max (firstPart kp false ls.length) (min n ls.length), true)
  | .stanza kp vs :: _ => ((vs.take (max (firstPart kp true vs.length) (min n vs.length))).join.length, true)
  | _ => (1, false)

/-- `fitting` of Decide.hs. -/
def fitting (env : Env) (st : St) (ls : List Line) : Nat :=
  let rec go (u nl : Int) : List Line → Nat
    | [] => 0
    | l :: more =>
      let noteLines : Int := ((l.notes.map (·.lines)).foldr (· + ·) 0 : Nat)
      let sep : Int := if nl = 0 ∧ 0 < noteLines then env.separator else 0
      if u + 1 + (nl + noteLines + sep) ≤ cap env st then go (u + 1) (nl + noteLines + sep) more + 1 else 0
  go st.used st.noteLines ls

/-- `roomForLine` of Decide.hs. -/
def roomForLine (env : Env) (st : St) (ls : List Line) : Bool :=
  let noteLines : Int := noteLinesOf (ls.take 1)
  let sep : Int := if st.noteLines = 0 ∧ 0 < noteLines then env.separator else 0
  decide (1 + (if 0 < noteLines then sep + 1 else 0) ≤ free env st)

/-- The `Env` of `paginateHeld` for `paginate 1 capacity` of
    Paginate.hs, the keeps of the visible separators `held` (none for
    `paginate`), before the parameters that read the state. -/
def plainEnv (capacity : Nat) (held : Nat → Bool := fun _ => false) : Env where
  maxLines := 9223372036854775807
  capacity := capacity
  separator := max 1 (min 1 ((capacity : Int) - 2))
  columns := 1
  nextNeed := nextNeed held capacity 1
  fitting := fun _ _ => 0
  codeSpan := codeLines
  keepParts := .column
  inBookPart := false
  roomForLine := fun _ _ => false
  keptNeed := keptNeed held capacity 1
  keepLast := fun rest => match keepAhead rest with | some (_, l, _, _) => l | none => 0
  nextFirst := nextFirst
  keepNextLines := fun rest => match keepAhead rest with | some (_, _, f, _) => f | none => 0
  -- `ruleBeforeAtStart`, `ruleAfterAtEnd` and `rulesJoined` of RuleArea.hs
  -- for the rule of Boundary.hs
  ruleBefore := fun _ atStart _ => if atStart then 2 else ruleLines
  rulesJoined := fun _ _ => 3
  ruleAfter := fun _ => ruleLines
  ruleAfterAtEnd := fun _ _ => 2
  held := held

def boundaryEnv (capacity : Nat) (held : Nat → Bool := fun _ => false) : Env :=
  { plainEnv capacity held with
    fitting := fitting (plainEnv capacity held)
    roomForLine := roomForLine (plainEnv capacity held) }

/-! ## The inputs, in the order of Boundary.hs -/

/-- A paragraph, a figure, a heading of one line over one grid line, a
    need-lines, a no-break, a no-break of so many lines and a
    keep-with-next. -/
inductive Element where
  | para (base n : Nat)
  | fig (id n : Nat)
  | head (base : Nat)
  | need (n : Nat)
  | noBreak
  | noBreakLines (n : Nat)
  | keepNext (n : Nat)
  /-- id, grid lines before and after, body -/
  | boxed (id before after : Nat) (body : List Element)
  | space (n : Nat)
  /-- first line, space before, header lines, lines of each row, caption
      lines, caption below -/
  | table (base sp h : Nat) (rows : List Nat) (c : Nat) (below : Bool)
  /-- geometry, caption, first rows, continued, first row, rows -/
  | code (g c f : Nat) (cont : Bool) (base n : Nat)
  /-- id, rule before, rule after, joined, body (lines, or a heading over
      so many grid lines), first line -/
  | ruled (id : Nat) (b a j : Bool) (body : Sum Nat Nat) (base : Nat)
  /-- keep all, first line, lines of each verse line -/
  | stanza (all : Bool) (base : Nat) (vs : List Nat)
  /-- id, grid lines, first line beside, lines beside -/
  | wrapped (id n base b : Nat)
  /-- first line, lines, the line with the note, lines of the note -/
  | noted (base n pos m : Nat)
  /-- the grid lines `@page-lines` changes the column by -/
  | adjust (k : Int)
  /-- the columns switched to -/
  | switch (n : Nat)
  /-- id, grid lines, first line beside, lines beside, the line with the
      note, lines of the note -/
  | wrappedNoted (id n base b pos m : Nat)
  deriving Inhabited

instance : Inhabited Flow := ⟨.noBreak⟩

def lines' (base n : Nat) : List Line := (List.range n).map fun i => ⟨base + i, []⟩

/-- The lines of consecutive blocks of the sizes given from `base`. -/
def runs (base : Nat) : List Nat → List (List Line)
  | [] => []
  | n :: ns => lines' base n :: runs (base + n) ns

def notedLines (base n pos m : Nat) : List Line :=
  (lines' base n).enum.map fun (j, l) => if j = pos then { l with notes := [⟨500 + base, m⟩] } else l

partial def Element.flow : Element → Flow
  | .boxed i b a body => .boxed i b a (body.map Element.flow)
  | .space n => .space n
  | .table base sp h rows c below =>
    .table sp (lines' base h) (runs (base + h) rows) (lines' (base + h + rows.foldr (· + ·) 0) c) below
  | .code g c f cont base n => .code g c f cont (lines' base n)
  | .ruled i b a j body base =>
    .ruled i b a j (match body with
      | .inl n => .lines defaultKeep (lines' base n)
      | .inr n => .heading false n (lines' base 1))
  | .stanza all base vs => .stanza ⟨2, 2, all⟩ (runs base vs)
  | .wrapped i n base b => .wrapped i n (lines' base b)
  | .noted base n pos m => .paragraph defaultKeep (notedLines base n pos m)
  | .adjust k => .adjustLines k
  | .switch n => .switchColumns n
  | .wrappedNoted i n base b pos m => .wrapped i n (notedLines base b pos m)
  | .para base n => .paragraph defaultKeep (lines' base n)
  | .fig id n => .figure id n
  | .head base => .heading false 1 (lines' base 1)
  | .need n => .needLines n
  | .noBreak => .noBreak
  | .noBreakLines n => .noBreakLines n
  | .keepNext n => .keepNext n 0

partial def Element.show : Element → String
  | .para base n => s!"P{base}:{n}"
  | .fig id n => s!"F{id}:{n}"
  | .head base => s!"H{base}"
  | .need n => s!"N{n}"
  | .noBreak => "B"
  | .noBreakLines n => s!"B{n}"
  | .keepNext n => s!"K{n}"
  | .boxed i b a body => s!"X{i}:{b}:{a}(" ++ " ".intercalate (body.map Element.show) ++ ")"
  | .space n => s!"_{n}"
  | .table base sp h rows c below =>
    s!"T{base}:{sp}:{h}:" ++ ",".intercalate (rows.map toString) ++ s!":{c}" ++ (if below then "b" else "a")
  | .code g c f cont base n => s!"C{base}:{g}:{c}:{f}:{bit cont}:{n}"
  | .ruled i b a j body base =>
    s!"R{i}:{bit b}{bit a}{bit j}:" ++ (match body with | .inl n => s!"L{n}" | .inr n => s!"H{n}") ++ s!":{base}"
  | .stanza all base vs => s!"V{base}:{bit all}:" ++ ",".intercalate (vs.map toString)
  | .wrapped i n base b => s!"W{i}:{n}:{base}:{b}"
  | .adjust k => s!"A{k}"
  | .switch n => s!"S{n}"
  | .wrappedNoted i n base b pos m => s!"Y{i}:{n}:{base}:{b}:{pos}:{m}"
  | .noted base n pos m => s!"Q{base}:{n}:{pos}:{m}"
where
  bit (b : Bool) : String := if b then "1" else "0"

def replicateM {α : Type} : Nat → List α → List (List α)
  | 0, _ => [[]]
  | n + 1, xs => xs.bind fun x => (replicateM n xs).map (x :: ·)

def paragraphs (sizes : List Nat) : List Element :=
  (List.range sizes.length).zip sizes |>.map fun (k, n) => .para (10 * k) n

def figureShapes (c : Nat) : List (List (Sum Nat Nat)) :=
  let choices := ([1, 2, 3].map Sum.inl) ++ ((List.range c).map fun i => Sum.inr (i + 1))
  (List.range 4).bind fun i => (replicateM (i + 1) choices).filter fun s =>
    let figures := (s.filter fun | .inr _ => true | .inl _ => false).length
    1 ≤ figures ∧ figures ≤ 3

def figureInput (shape : List (Sum Nat Nat)) : List Element :=
  (List.range shape.length).zip shape |>.map fun
    | (k, .inl n) => .para (10 * k) n
    | (k, .inr n) => .fig (100 + k) n

/-- One to three elements, each a paragraph of one to five lines, a
    heading, a need-lines of two or three lines, a no-break, a no-break
    of three lines or a keep-with-next of one or two lines, as in
    Boundary.hs. -/
def controlChoices : List (Nat → Element) :=
  [fun k => .para (10 * k) 1, fun k => .para (10 * k) 2, fun k => .para (10 * k) 3,
   fun k => .para (10 * k) 4, fun k => .para (10 * k) 5,
   fun k => .head (10 * k), fun _ => .need 2, fun _ => .need 3, fun _ => .noBreak, fun _ => .noBreakLines 3,
   fun _ => .keepNext 1, fun _ => .keepNext 2]

def controlShapes : List (List (Nat → Element)) :=
  [1, 2, 3].bind fun n => replicateM n controlChoices

/-- The shape, then a last paragraph of `n` lines. -/
def controlInput (shape : List (Nat → Element)) (n : Nat) : List Element :=
  ((List.range shape.length).zip shape |>.map fun (k, e) => e k) ++ [.para (10 * shape.length) n]

/-- The other kinds of flows, as `kindChoices` of Boundary.hs. -/
def kindChoices : List (Nat → Element) :=
  ([((0 : Nat), (0 : Nat)), (1, 1), (1, 0)].bind fun (b, a) => [1, 2, 3, 4].map fun n => fun (k : Nat) => Element.boxed (100 + k) b a [.para (10 * k) n])
  ++ [fun (k : Nat) => Element.boxed (100 + k) 1 1 [.para (10 * k) 1, .space 1, .para (10 * k + 5) 2]]
  ++ ([0, 1].bind fun sp => [0, 1].bind fun h => [[1], [1, 1], [1, 1, 1], [2, 1]].bind fun rows =>
      [(0, false), (1, false), (1, true)].map fun (c, below) => fun (k : Nat) => Element.table (10 * k) sp h rows c below)
  ++ ([0, 1].bind fun g => [0, 1].bind fun c => [1, 2].bind fun f => [false, true].bind fun cont =>
      [1, 2, 3, 4].map fun n => fun (k : Nat) => Element.code g c f cont (10 * k) n)
  ++ ([false, true].bind fun b => [false, true].bind fun a =>
      [(Sum.inl 1 : Sum Nat Nat), .inl 2, .inl 3, .inr 1, .inr 2].map fun body => fun (k : Nat) => Element.ruled (100 + k) b a false body (10 * k))
  ++ ([false, true].bind fun all => [[1], [1, 1], [1, 1, 1], [2, 1], [1, 2, 1], [1, 1, 1, 1]].map fun vs =>
      fun (k : Nat) => Element.stanza all (10 * k) vs)
  ++ ([1, 2, 3].bind fun n => [0, 1, 2, 3].map fun b => fun (k : Nat) => Element.wrapped (100 + k) n (10 * k) b)
  ++ ([1, 2, 3].bind fun n => (List.range n).bind fun pos => [1, 2, 3].map fun m => fun (k : Nat) => Element.noted (10 * k) n pos m)

/-- `pairChoices` of Boundary.hs. -/
def pairChoices : List (Nat → Element) :=
  [fun (k : Nat) => Element.boxed (100 + k) 1 1 [.para (10 * k) 2],
   fun (k : Nat) => Element.boxed (100 + k) 1 0 [.para (10 * k) 3],
   fun (k : Nat) => Element.table (10 * k) 1 1 [1, 1] 1 true,
   fun (k : Nat) => Element.table (10 * k) 0 0 [2, 1] 1 false,
   fun (k : Nat) => Element.code 1 1 2 true (10 * k) 3,
   fun (k : Nat) => Element.code 0 0 1 false (10 * k) 2,
   fun (k : Nat) => Element.ruled (100 + k) true true false (.inl 2) (10 * k),
   fun (k : Nat) => Element.ruled (100 + k) true true true (.inl 1) (10 * k),
   fun (k : Nat) => Element.ruled (100 + k) true false true (.inr 1) (10 * k),
   fun (k : Nat) => Element.ruled (100 + k) false true false (.inl 2) (10 * k),
   fun (k : Nat) => Element.stanza false (10 * k) [1, 1, 1],
   fun (k : Nat) => Element.stanza true (10 * k) [2, 1],
   fun (k : Nat) => Element.wrapped (100 + k) 2 (10 * k) 3,
   fun (k : Nat) => Element.wrapped (100 + k) 3 (10 * k) 1,
   fun (k : Nat) => Element.noted (10 * k) 2 1 2,
   fun (k : Nat) => Element.noted (10 * k) 1 0 3,
   fun (_ : Nat) => Element.keepNext 1,
   fun (_ : Nat) => Element.keepNext 2,
   fun (_ : Nat) => Element.noBreak,
   fun (_ : Nat) => Element.noBreakLines 3,
   fun (_ : Nat) => Element.need 2,
   fun (k : Nat) => Element.para (10 * k) 2]

/-- `kindInputs` of Boundary.hs. -/
def kindInputs : List (Nat × List Element) :=
  ([2, 3, 4, 5].bind fun c => [0, 1, 2].bind fun p => kindChoices.bind fun kind => [1, 2, 3].map fun n =>
      (c, (if 0 < p then [Element.para 0 p] else []) ++ [kind 1, .para 20 n]))
  ++ ([2, 3, 4].bind fun c => pairChoices.bind fun a => pairChoices.bind fun b => [1, 2].map fun n =>
      (c, [a 0, b 1, .para 20 n]))
  ++ ([3, 4, 5].bind fun c => [1, 2].bind fun p =>
      [fun (k : Nat) => Element.head (10 * k), fun _ => .keepNext 1, fun _ => .noBreak, fun _ => .need 3].bind fun control =>
      kindChoices.bind fun kind => [true, false].bind fun kindFirst => [1, 3].map fun n =>
      (c, [Element.para 0 p] ++ (if kindFirst then [kind 1, control 2] else [control 1, kind 2]) ++ [.para 30 n]))

/-- `adjustInputs` of Boundary.hs. -/
def adjustInputs : List (Nat × List Element) :=
  ([3, 4, 5].bind fun c => [2, 3, 4, 5, 6].bind fun m => [(-1 : Int), 1, 2, 3, 4].bind fun a =>
      [[], [Element.noted 10 1 0 1], [Element.wrappedNoted 100 2 10 2 0 1], [Element.switch 2, .para 10 3]].bind fun more =>
      [1, 3].map fun n => (c, [Element.noted 0 1 0 m, .adjust a] ++ more ++ [.para 20 n]))
  ++ ([3, 4, 5].bind fun c => [1, 2].bind fun p => [0, 1, 2].bind fun m => [(-2 : Int), -1, 1, 2].bind fun a =>
      [2, 3].bind fun s => [1, 2, 3, 4, 5, 6].map fun q =>
      (c, [if m = 0 then Element.para 0 p else .noted 0 p 0 m, .adjust a, .switch s, .para 10 q, .para 20 1]))
  ++ ([2, 3, 4, 5].bind fun c => [0, 1, 2].bind fun p => [1, 2, 3].bind fun n => [1, 2, 3].bind fun b =>
      (List.range b).bind fun pos => [1, 2, 3].bind fun m => [1, 2, 3].map fun k =>
      (c, (if 0 < p then [Element.para 0 p] else []) ++ [.wrappedNoted 100 n 10 b pos m, .para 20 k]))
  ++ ([3, 4, 5].bind fun c => [1, 2].bind fun p => [Element.head 40, .keepNext 1, .noBreak, .need 3].bind fun control =>
      [1, 2].bind fun n => [1, 2].bind fun b => [1, 2, 3].map fun m =>
      (c, [Element.para 0 p, control, .wrappedNoted 100 n 10 b 0 m, .para 20 1]))

def inputs : List (Nat × List Element) :=
  ([1, 2, 3].bind fun c => [(c, []), (c, [.para 0 1])])
  ++ ([1, 2, 3].bind fun c =>
      ((List.range 5).map (fun a => [a + 1]) ++ (List.range 4).bind (fun a => (List.range 4).map fun b => [a + 1, b + 1]))
        |>.map fun s => (c, paragraphs s))
  ++ [(3, [.fig 1 3]), (3, [.para 0 1, .fig 1 3]), (3, [.fig 1 4]), (3, [.para 0 1, .fig 1 4, .para 10 1])]
  ++ ([3, 4].bind fun c => (figureShapes c).map fun s => (c, figureInput s))
  ++ ([2, 3, 4].bind fun c => controlShapes.bind fun s => [1, 2, 3].map fun n => (c, controlInput s n))

/-! ## The output, in the format of Boundary.hs -/

def slotText : Int × Slot → String
  | (g, .line i) => s!"{g}:L{i}"
  | (g, .figure i) => s!"{g}:F{i}"
  | (g, .heading i n) => s!"{g}:H{i}:{n}"
  | (g, .wrapped i) => s!"{g}:W{i}"
  | (g, .code rows) => s!"{g}:C{rows.headD 0}:{rows.length}"
  -- a header line repeated is a line of Paginate.hs
  | (g, .repeated i) => s!"{g}:L{i}"
  | (g, s) => s!"{g}:{reprStr s}"

def unmetText : Unmet → String
  | .needLines n => s!"!need{n}"
  | .noBreak => "!nobreak"
  | .keepNext _ => "!keepnext"
  | .droppedBlank => "!dropped"
  | .tallHeading i n f => s!"!tall{i}:{n}:{f}"
  | .splitKept i => s!"!split{i}"
  | .shortFirst i w g => s!"!first{i}:{w}:{g}"
  | .shortLast i w g => s!"!last{i}:{w}:{g}"
  | .unplaceableFootnote i n => s!"!unplaceable{i}:{n}"
  | .adjust n limit =>
    s!"!adjust{n}:" ++ (match limit with | .noRoom => "AdjustNoRoom" | .linesPlaced => "AdjustLinesPlaced" | .oneLine => "AdjustOneLine")
  | u => s!"!{reprStr u}"

def pageText (p : PageOut) : String :=
  " ".intercalate ([toString p.number, toString p.column, if p.blank then "blank" else "-"] ++ p.slots.map slotText
    ++ p.notes.map (fun (i, first, n) => s!"n{i}:{first}:{n}") ++ p.unmet.map unmetText)

/-- The pages of `paginateWithin`: those of the state, or one empty page
    when there are none (Paginate.hs, `paginateWithin`). -/
def pages (capacity : Nat) (es : List Element) : List String :=
  match (paginate (boundaryEnv capacity) (es.map Element.flow)).done.reverse with
  | [] => ["1 0 -"]
  | ps => ps.map pageText

/-- The pages of the inputs of part `part` of `parts` contiguous parts,
    so that check.sh evaluates the parts side by side. -/
def report (part parts : Nat) : String :=
  let all := inputs ++ kindInputs ++ adjustInputs
  let size := (all.length + parts - 1) / parts
  String.join (((all.drop (part * size)).take size).map fun (c, es) =>
    s!"{c} [{" ".intercalate (es.map Element.show)}]\n" ++ String.join ((pages c es).map fun p => s!"  {p}\n"))

end Boundary

def main : List String → IO Unit
  | [part, parts] => IO.print (Boundary.report part.toNat! parts.toNat!)
  | _ => IO.print (Boundary.report 0 1)
