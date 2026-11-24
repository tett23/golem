/- Root ADR 0352: the manuscripts of SeparatorBoundary.hs on the flows
   Separator.lean makes and the paginate of Whole.lean, under the `Env`
   of Boundary.lean.  `report` prints the pages, or G07134 at the line of
   the first separator of each chain split across columns, in the format
   of SeparatorBoundary.hs, and check.sh compares the two with diff.
   This is a check on finitely many inputs, not a proof. -/
import Whole
import Separator
import Boundary
open WholePagination Boundary

namespace SeparatorBoundary

/-- The items of SeparatorBoundary.hs. -/
inductive Item where
  | p (k : Nat) | s | t | g | b | e | n
  /-- `@blank-line` lines collapsed into one block of `k` lines. -/
  | bk (k : Nat)
  deriving DecidableEq

def Item.name : Item → String
  | .p k => s!"P{k}"
  | .s => "S" | .t => "T" | .g => "G" | .b => "B" | .e => "E" | .n => "N" | .bk k => s!"B{k}"

/-- The grid lines before and after the separators default and scene. -/
def combos : List ((Nat × Nat) × (Nat × Nat)) := [((0, 0), (1, 2)), ((1, 1), (2, 0))]

/-- The units of the items from the line `id`: a paragraph of `k` lines,
    a visible separator of one line, the blank separator `gap` and
    `@blank-line 1` as blank lines of one line, `@page-break` as a
    break and `@need-lines 2` as a unit that passes a chain. -/
def units (c : (Nat × Nat) × (Nat × Nat)) : Nat → List Item → List Separator.Unit
  | _, [] => []
  | id, .p k :: r => .other .block [.paragraph defaultKeep (lines' id k)] (some id) :: units c (id + k) r
  | id, .s :: r => .separator c.1.1 c.1.2 defaultKeep ⟨id, []⟩ :: units c (id + 1) r
  | id, .t :: r => .separator c.2.1 c.2.2 defaultKeep ⟨id, []⟩ :: units c (id + 1) r
  | id, .g :: r | id, .b :: r => .blank 1 :: units c id r
  | id, .bk k :: r => .blank k :: units c id r
  | id, .e :: r => .brk .page :: units c id r
  | id, .n :: r => .other .pass [.needLines 2] none :: units c id r

/-- `ineffectiveBlankLines` of golem-assemble (Assemble.hs): a blank
    line with only blank lines, need-lines and breaks after it, or a
    break after the blank lines and need-lines after it, is dropped
    before the units are made (G04009, G04010).  A separator of kind
    `blank` is a blank line by then (`resolveBlock` of Driver.hs). -/
def soft : Item → Bool
  | .b | .g | .n | .bk _ => true
  | _ => false

def blank : Item → Bool
  | .b | .g | .bk _ => true
  | _ => false

def blankCount : Item → Nat
  | .b | .g => 1
  | .bk k => k
  | _ => 0

/-- `collapseBlankLines` of golem-eval (File.hs): the `@blank-line`s of a
    run, with only need-lines between them, become one at the first, of
    their lines added up.  The separator `gap` is resolved after it and
    stays apart. -/
def collapse (items : List Item) : List Item :=
  let rec go : List Item → List Item → List Item
    | run, [] => flush run
    | run, i :: rest => if i == .b || i == .n then go (run ++ [i]) rest else flush run ++ i :: go [] rest
  go [] items
where
  flush (run : List Item) : List Item :=
    let total := (run.filter (· == .b)).length
    let rec put : Bool → List Item → List Item
      | _, [] => []
      | done, .b :: r => if done then put done r else .bk total :: put true r
      | done, i :: r => i :: put done r
    put false run

def effective : List Item → List Item
  | [] => []
  | i :: rest =>
    let atEnd := rest.all fun j => soft j || j == .e
    let brk := (rest.dropWhile soft).head? == some .e
    if blank i && (atEnd || brk) then effective rest else i :: effective rest

/-- `blankLinesOverPage` of golem-assemble: the blank lines of a run, with
    only need-lines between them, of the lines of a page or more are
    dropped (G04011). -/
def overPage (capacity : Nat) (items : List Item) : List Item :=
  let rec runs : List Item → List (List Item)
    | [] => [[]]
    | i :: rest =>
      match runs rest with
      | r :: rs => if soft i then (i :: r) :: rs else [] :: [i] :: r :: rs
      | [] => [[i]]
  (runs items).bind fun r =>
    if capacity ≤ ((r.filter blank).map blankCount).foldr (· + ·) 0 then r.filter (fun i => !blank i) else r

def manuscripts : List (List Item) :=
  [[], [Item.p 1]].bind fun lead => [1, 2, 3].bind fun n =>
    ((replicateM n [Item.s, .t, .g, .b, .e, .n, .p 1]).filter fun m => m.any fun i => i == .s || i == .t).bind fun middle =>
      [[], [Item.p 1], [Item.p 2]].map fun last => lead ++ middle ++ last

def inputs : List (Nat × Nat × List Item) :=
  (List.range combos.length).bind fun c => [1, 2, 3].bind fun capacity => manuscripts.map fun m => (c, capacity, m)

/-- The line of the separator at an index of the units. -/
def siteLine (us : List Separator.Unit) (i : Nat) : String :=
  match us.get? i with
  | some (.separator _ _ _ l) => toString l.id
  | _ => s!"@{i}"

def output (c capacity : Nat) (items : List Item) : List String :=
  let us := units (combos.getD c ((0, 0), (0, 0))) 0 (overPage capacity (effective (collapse items)))
  let made := Separator.separatorUnits us
  let final := paginate (boundaryEnv capacity) (Separator.separatorFlows us)
  -- the controls not met in a column with no output go with the last
  -- page, as `paginateWithin` of Paginate.hs puts them
  let pages := match final.done with
    | [] => [⟨1, 0, false, [], [], final.unmet⟩]
    | last :: earlier => ({ last with unmet := last.unmet ++ final.unmet } :: earlier).reverse
  match Separator.holdErrors made pages with
  | [] => pages.map pageText
  | sites => ["error " ++ " ".intercalate ((sites.map fun i => s!"G07134:{siteLine made i}").toArray.qsort (· < ·)).toList]

def report (part parts : Nat) : String :=
  let size := (inputs.length + parts - 1) / parts
  String.join (((inputs.drop (part * size)).take size).map fun (c, capacity, items) =>
    s!"{c} {capacity} [{" ".intercalate (items.map Item.name)}]\n" ++ String.join ((output c capacity items).map fun p => s!"  {p}\n"))

end SeparatorBoundary

-- check.sh evaluates the inputs in `SEPARATOR_PARTS` contiguous parts
-- side by side, this one part `SEPARATOR_PART`; `#eval` prints it, as
-- `main` is Boundary.lean's.
#eval show IO _root_.Unit from do
  let part := ((← IO.getEnv "SEPARATOR_PART").getD "0").toNat!
  let parts := ((← IO.getEnv "SEPARATOR_PARTS").getD "1").toNat!
  IO.print (SeparatorBoundary.report part parts)
