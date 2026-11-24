/-
Root ADR 0352: the flows of the separators of root ADR 0398 next to
boxes, ruled blocks and book parts.

After the units are numbered, golem-typeset changes the flow three
times before the pagination (modules/golem-typeset/src/Golem/Typeset/Flow.hs:4156,
:4157 and :4203): `joinBoxes` (Flow.hs:3951) makes boxes one after the
other with only spaces and keep-with-next between them one box,
`ruledLinks` (Flow.hs:4655) lets a ruled block share the area of its
rule before with the rule after of the ruled block right before it, and
`markBookParts` (Flow.hs:4531) wraps the flows of each item of a list in
a book part.  This file models the three on the flows of Whole.lean, for
the flows `Separator.separatorFlows` makes.  `spaceAfterCode`
(Flow.hs:3581), between `joinBoxes` and `ruledLinks`, only adds a space
after a code block, and the definition terms and the tables that
`markBookParts` also wraps (its `special`) are not modelled: none is in
these flows.  Every definition is total.
-/
import Whole
import Separator

namespace WholePagination
namespace SeparatorBlocks

/-! ## joinBoxes -/

/-- `passable` of `joinBoxes`: a space or a keep-with-next may go into a
    box. -/
def passable : Flow → Bool
  | .space _ | .keepNext _ => true
  | _ => false

/-- `keyOf` of `joinBoxes`: the settings of the box of a boxed flow, by
    its id (`key`), and none for any other flow. -/
def keyOf (key : Nat → Option Nat) : Flow → Option Nat
  | .boxed i _ _ _ => key i
  | _ => none

/-- `bodyOf` of `joinBoxes`. -/
def bodyOf : Flow → List Flow
  | .boxed _ _ _ b => b
  | f => [f]

/-- `joined` of `joinBoxes`: a run of boxes is the first box with the
    bodies of the run, the flows between them in it. -/
def joined : List Flow → List Flow
  | fs@(.boxed i kb ka _ :: _) => [.boxed i kb ka (fs.bind bodyOf)]
  | fs => fs

/-- `groupBoxes` (Box.hs:40) and `joined`, as a pass from the left: the
    run being collected (its key, the flows of the run and the passable
    flows after them), which the next flow of the same key goes on and
    any other flow but a passable one ends; the passable flows after the
    run then stay out of it. -/
def joinGo (key : Nat → Option Nat) : Option (Nat × List Flow × List Flow) → List Flow → List Flow
  | none, [] => []
  | some (_, acc, mid), [] => joined acc ++ mid
  | none, f :: rest =>
    match keyOf key f with
    | some k => joinGo key (some (k, [f], [])) rest
    | none => f :: joinGo key none rest
  | some (k, acc, mid), f :: rest =>
    if keyOf key f == some k then joinGo key (some (k, acc ++ mid ++ [f], [])) rest
    else if passable f && (keyOf key f).isNone then joinGo key (some (k, acc, mid ++ [f])) rest
    else
      joined acc ++ mid ++
        match keyOf key f with
        | some k' => joinGo key (some (k', [f], [])) rest
        | none => f :: joinGo key none rest

/-- `joinBoxes` (Flow.hs:3951), on the flows. -/
def joinBoxes (key : Nat → Option Nat) (flows : List Flow) : List Flow := joinGo key none flows

/-! ## ruledLinks -/

/-- `go` of `ruledLinks` (Flow.hs:4655): a ruled block with a rule
    before, right after a ruled block with a rule after, shares its area.
    The overhang of the line after a block (`frNextOverhang`) is not in
    the flows of Whole.lean. -/
def ruledGo : Option Flow → List Flow → List Flow
  | _, [] => []
  | prev, .ruled i b a _ body :: rest =>
    let j := match prev with
      | some (.ruled _ _ true _ _) => b
      | _ => false
    .ruled i b a j body :: ruledGo (some (.ruled i b a j body)) rest
  | _, f :: rest => f :: ruledGo (some f) rest

def ruledLinks (flows : List Flow) : List Flow := ruledGo none flows

/-! ## markBookParts -/

/-- `owner` of `itemOwners` (Flow.hs:4517): the unit of the greatest
    first line not after the first id of the flow; the units are given
    as their first line and their outermost item of a list, if any. -/
def ownerOf (owners : List (Nat × Option Nat)) (f : Flow) : Option (Option Nat) :=
  match flowSlotIds f with
  | [] => none
  | i :: _ => (owners.filter (fun o => o.1 ≤ i)).foldl (fun found o =>
      match found with
      | some (j, _) => if j ≤ o.1 then some o else found
      | none => some o) none |>.map (·.2)

/-- The owner of the nearest flow after each flow (`future` of
    `itemOwners`). -/
def nexts : List (Option (Option Nat)) → List (Option (Option Nat))
  | [] => []
  | _ :: rest => (rest.find? Option.isSome).getD none :: nexts rest

/-- `fill` of `itemOwners`: a flow of no owner between two flows of the
    same outermost item of a list belongs to that item. -/
def fillGo : Option (Option Nat) → List (Option (Option Nat) × Option (Option Nat)) → List (Option (Option Nat))
  | _, [] => []
  | previous, (u, next) :: rest =>
    let inherited := match previous, next with
      | some (some a), some (some b) => if a == b then previous else none
      | _, _ => none
    (u <|> inherited) :: fillGo (u <|> previous) rest

/-- `itemOwners` (Flow.hs:4513), as the key of the outermost item of each
    flow (`key 0`). -/
def itemKeys (owners : List (Nat × Option Nat)) (flows : List Flow) : List (Option Nat) :=
  let raw := flows.map (ownerOf owners)
  (fillGo none (raw.zip (nexts raw))).map (fun o => o.bind id)

mutual
/-- `special` of `markBookParts`, for boxes only. -/
def special : List Flow → List Flow
  | [] => []
  | .boxed i b a body :: rest => .boxed i b a (special body) :: special rest
  | f :: rest => f :: special rest
end

/-- `wrapLists 0` of `markBookParts`, the items one level deep: a run of
    flows of one item is a book part of `unit` of the ids of its flows. -/
def wrapGo (unit : KeepParts) : Option (Nat × List Flow) → List (Option Nat × Flow) → List Flow
  | none, [] => []
  | some (_, acc), [] => [part unit acc]
  | none, (k, f) :: rest =>
    match k with
    | some k => wrapGo unit (some (k, [f])) rest
    | none => f :: wrapGo unit none rest
  | some (k, acc), (k', f) :: rest =>
    if k' == some k then wrapGo unit (some (k, acc ++ [f])) rest
    else part unit acc ::
      match k' with
      | some k' => wrapGo unit (some (k', [f])) rest
      | none => f :: wrapGo unit none rest
where
  part (unit : KeepParts) (inside : List Flow) : Flow :=
    let body := special inside
    .bookPart unit 0 (flowsSlotIds body) body

/-- `markBookParts` (Flow.hs:4531) on items of a list one level deep. -/
def markBookParts (unit : KeepParts) (owners : List (Nat × Option Nat)) (flows : List Flow) : List Flow :=
  special (wrapGo unit none ((itemKeys owners flows).zip flows))

/-- The flows `paginateBuilt` receives (`bRetainedFlow`, Flow.hs:4203):
    the flows of the units after `spaceSeparators` and
    `holdSeparatorNeeds`, then `joinBoxes`, `ruledLinks` and
    `markBookParts`. -/
def blockFlows (key : Nat → Option Nat) (unit : KeepParts) (owners : List (Nat × Option Nat))
    (capacity : Nat) (us : List Separator.Unit) : List Flow :=
  markBookParts unit owners (ruledLinks (joinBoxes key (Separator.separatorFlows capacity us)))

end SeparatorBlocks
end WholePagination
