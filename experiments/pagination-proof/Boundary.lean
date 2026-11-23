/- Root ADR 0352: the boundary inputs of `boundaryTableTests`
   (modules/golem-layout/test/PaginateSpec.hs) on the paginate of
   Whole.lean.  `boundaryEnv` is the `Env` of `paginate 1 capacity` of
   Paginate.hs, its parameters computed as Paginate/Decide.hs computes
   them.  `#eval` prints the pages of every input in the format of
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
  | .keepNext n => some (0, n)
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

/-- The grid lines of each rule area of `boundaryEnv`.  No input of the
    table has a ruled block. -/
def ruleLines : Nat := 1

/-- The grid lines of a part of a code block of `boundaryEnv`, one for
    each row.  No input of the table has a code block. -/
def codeLines (_geometry rows : Nat) : Nat := rows

mutual
/-- `nextNeed` of Decide.hs, of a column of `capacity` lines in a base set
    of `columns` columns. -/
partial def nextNeed (capacity columns : Nat) : List Flow → Need
  | [] => grid 0
  | .bookPart _ _ _ body :: rest => nextNeed capacity columns (body ++ rest)
  | f :: rest =>
    if startsRecto f then grid 0 else
    match f with
    | .paragraph kp ls =>
      chained capacity columns ls.length (firstPart kp true ls.length) (fun k => linesNeed (ls.take k)) rest
    | .continued kp ls =>
      chained capacity columns ls.length (firstPart kp false ls.length) (fun k => linesNeed (ls.take k)) rest
    | .stanza kp vs =>
      chained capacity columns vs.length (firstPart kp true vs.length) (fun k => linesNeed (vs.take k).join) rest
    | .table sp h rows capt below => grid (sp + tableHead h rows capt below)
    | .defTerm ls => linesNeed ls
    | .heading _ n ls => plus ⟨n, noteLinesOf ls⟩ (nextNeed capacity columns rest)
    | .figure _ n => grid (min n capacity)
    | .pageFigure _ => grid 0
    | .wrapped _ n ls => grid (max n ls.length)
    | .space n => spaced capacity n (nextNeed capacity columns rest)
    | .brk _ | .sectionStart _ _ => grid 0
    | .noBreak | .noBreakLines _ | .keepNext _ | .needLines _ | .adjustLines _ => nextNeed capacity columns rest
    | .blank n => let r := nextNeed capacity columns rest; { r with grid := min capacity (min capacity n + r.grid) }
    | .code g caption first cont ls =>
      if ls.isEmpty then grid 0
      else
        let k := min ls.length (max 1 first)
        grid (caption + codeLines g (k + (if cont && k < ls.length then 1 else 0)))
    | .switchColumns _ => if columns = 1 then nextNeed capacity columns rest else grid 0
    | .restoreColumns => grid 0
    | .ruled _ before after _ body =>
      let size := (if before then ruleLines else 0) + body.size + (if after then ruleLines else 0)
      match body with
      | .heading _ _ ls => ⟨size, noteLinesOf ls⟩
      | .lines _ _ => grid size
    | .boxed _ kb ka body =>
      let n := nextNeed capacity columns body
      let whole := match body with
        | [.paragraph kp ls] => decide (ls.length ≤ firstPart kp true ls.length)
        | [.stanza kp vs] => decide (vs.length ≤ firstPart kp true vs.length)
        | _ => false
      { n with grid := kb + n.grid + (if whole then ka else 0) }
    | .bookPart _ _ _ _ => grid 0

/-- `followNeed` of Decide.hs. -/
partial def followNeed (capacity columns n : Nat) (after : List Flow) : Need :=
  if n = 0 then nextNeed capacity columns after
  else match after with
    | .paragraph kp ls :: more =>
      chained capacity columns ls.length (max (firstPart kp true ls.length) (min n ls.length)) (fun k => linesNeed (ls.take k)) more
    | .continued kp ls :: more =>
      chained capacity columns ls.length (max (firstPart kp false ls.length) (min n ls.length)) (fun k => linesNeed (ls.take k)) more
    | .stanza kp vs :: more =>
      chained capacity columns vs.length (max (firstPart kp true vs.length) (min n vs.length)) (fun k => linesNeed (vs.take k).join) more
    | _ => nextNeed capacity columns after

/-- `chained` of Decide.hs. -/
partial def chained (capacity columns total k : Nat) (needOf : Nat → Need) (more : List Flow) : Need :=
  let base := needOf k
  match keepAhead more with
  | some (before, _, m, after') =>
    if total ≤ k ∧ 0 < m then
      let r := spaced capacity (spacesIn before) (followNeed capacity columns m after')
      ⟨min capacity (base.grid + r.grid), base.notes + r.notes⟩
    else base
  | none => base
end

/-- `keptNeed` of Decide.hs. -/
def keptNeed (capacity columns : Nat) (rest : List Flow) : Option Need :=
  (keepAhead (flattenParts rest)).map fun (before, _, n, after) =>
    spaced capacity (spacesIn before) (followNeed capacity columns n after)

/-- `nextFirstLines` of Decide.hs. -/
partial def nextFirst (n : Nat) (after : List Flow) : Nat × Bool :=
  let skipped : Flow → Bool
    | .space _ | .needLines _ | .adjustLines _ | .noBreak | .noBreakLines _ | .keepNext _ | .blank _ => true
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

/-- The `Env` of `paginateWithin` for `paginate 1 capacity` of
    Paginate.hs, before the parameters that read the state. -/
def plainEnv (capacity : Nat) : Env where
  maxLines := 9223372036854775807
  capacity := capacity
  separator := max 1 (min 1 ((capacity : Int) - 2))
  columns := 1
  nextNeed := nextNeed capacity 1
  fitting := fun _ _ => 0
  codeSpan := codeLines
  keepParts := .column
  inBookPart := false
  roomForLine := fun _ _ => false
  keptNeed := keptNeed capacity 1
  keepLast := fun rest => match keepAhead rest with | some (_, l, _, _) => l | none => 0
  nextFirst := nextFirst
  keepNextLines := fun rest => match keepAhead rest with | some (_, _, f, _) => f | none => 0
  ruleBefore := fun _ _ _ => ruleLines
  rulesJoined := fun _ _ => ruleLines
  ruleAfter := fun _ => ruleLines
  ruleAfterAtEnd := fun _ _ => ruleLines

def boundaryEnv (capacity : Nat) : Env :=
  { plainEnv capacity with
    fitting := fitting (plainEnv capacity)
    roomForLine := roomForLine (plainEnv capacity) }

/-! ## The inputs, in the order of Boundary.hs -/

inductive Element where
  | para (base n : Nat)
  | fig (id n : Nat)

def lines' (base n : Nat) : List Line := (List.range n).map fun i => ⟨base + i, []⟩

def Element.flow : Element → Flow
  | .para base n => .paragraph defaultKeep (lines' base n)
  | .fig id n => .figure id n

def Element.show : Element → String
  | .para base n => s!"P{base}:{n}"
  | .fig id n => s!"F{id}:{n}"

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

def inputs : List (Nat × List Element) :=
  ([1, 2, 3].bind fun c => [(c, []), (c, [.para 0 1])])
  ++ ([1, 2, 3].bind fun c =>
      ((List.range 5).map (fun a => [a + 1]) ++ (List.range 4).bind (fun a => (List.range 4).map fun b => [a + 1, b + 1]))
        |>.map fun s => (c, paragraphs s))
  ++ [(3, [.fig 1 3]), (3, [.para 0 1, .fig 1 3]), (3, [.fig 1 4]), (3, [.para 0 1, .fig 1 4, .para 10 1])]
  ++ ([3, 4].bind fun c => (figureShapes c).map fun s => (c, figureInput s))

/-! ## The output, in the format of Boundary.hs -/

def slotText : Int × Slot → String
  | (g, .line i) => s!"{g}:L{i}"
  | (g, .figure i) => s!"{g}:F{i}"
  | (g, s) => s!"{g}:{reprStr s}"

def pageText (p : PageOut) : String :=
  " ".intercalate ([toString p.number, toString p.column, if p.blank then "blank" else "-"] ++ p.slots.map slotText)

/-- The pages of `paginateWithin`: those of the state, or one empty page
    when there are none (Paginate.hs, `paginateWithin`). -/
def pages (capacity : Nat) (es : List Element) : List String :=
  match (paginate (boundaryEnv capacity) (es.map Element.flow)).done.reverse with
  | [] => ["1 0 -"]
  | ps => ps.map pageText

def report : String :=
  String.join (inputs.map fun (c, es) =>
    s!"{c} [{" ".intercalate (es.map Element.show)}]\n" ++ String.join ((pages c es).map fun p => s!"  {p}\n"))

end Boundary

#eval IO.print Boundary.report
