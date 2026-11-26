/- Golem ADR 0352: a differential check of the transcribed Alloy predicates.
   For each sampled input that meets `alloyInputFact`, Lean computes, for
   every transcribed predicate, the set of placements that meet it (or
   whether an input-level predicate holds), and prints an Alloy `run`
   command that fixes the input and states that every original predicate
   holds of exactly the placements in the Lean set. The fixture fixes the
   instance up to isomorphism (fact allPlacements and exact scopes), so the
   command has an instance if and only if `fact input` admits the input and
   every predicate agrees. `check-alloy-diff.sh` appends the commands to
   pagination.als and expects each of them to have an instance. This
   compares the transcription with the original predicates on finitely
   many inputs; it is not a proof. -/
import Pagination
open GolemPagination

/-- The keep options of an input: none, or the paragraph of the first
    line kept with (1, 3), or kept with (3, 1) and of keep-all-lines. -/
def diffKeeps (inp : AlloyInput) (k : Nat) : AlloyKeeps :=
  match inp.paras.head?, k % 3 with
  | some q, 1 => ⟨[(q, 1, 3)], []⟩
  | some q, 2 => ⟨[(q, 3, 1)], [q]⟩
  | _, _ => ⟨[], []⟩

def placementPreds : List (String × (AlloyInput → AlloyKeeps → AlloyPlacement → Bool)) :=
  [ ("fits", fun i _ p => alloyFits i p), ("greedy", fun i _ p => alloyGreedy i p),
    ("order", fun i _ p => alloyOrder i p), ("figure", fun i _ p => alloyFigure i p),
    ("orphan", fun i _ p => alloyOrphan i p), ("widow", fun i _ p => alloyWidow i p),
    ("keepHeading", fun i _ p => alloyKeepHeading i p),
    ("noSendFromEmpty", fun i _ p => alloyNoSendFromEmpty i p),
    ("all7", fun i _ p => alloyAll7 i p),
    ("lineAfterHeadings", fun i _ p => alloyLineAfterHeadingsRule i p),
    ("orphanH", fun i _ p => alloyOrphanH i p), ("widowH", fun i _ p => alloyWidowH i p),
    ("keepHeading21", fun i _ p => alloyKeepHeading21 i p),
    ("keepHeadingR", fun i _ p => alloyKeepHeadingR i p),
    ("recto", fun i _ p => alloyRecto i p), ("base", fun i _ p => alloyBase i p),
    ("figures", fun i _ p => alloyFigures i p), ("figureOrder", fun i _ p => alloyFigureOrder i p),
    ("blankWithNext", fun i _ p => alloyBlankWithNext i p),
    ("blankWithNext25", fun i _ p => alloyBlankWithNext25 i p),
    ("base26", fun i _ p => alloyBase26 i p),
    ("needMet", fun i _ p => alloyNeedMet i p), ("spaceKeeps", fun i _ p => alloySpaceKeeps i p),
    ("spaceKeepsFirst", fun i _ p => alloySpaceKeepsFirst i p),
    ("spaceKeeps35", fun i _ p => alloySpaceKeeps35 i p),
    ("figures27", fun i _ p => alloyFigures27 i p), ("base27", fun i _ p => alloyBase27 i p),
    ("keepFirst", fun i k p => alloyKeepFirst i k p), ("keepLast", fun i k p => alloyKeepLast i k p),
    ("keepAll", fun i k p => alloyKeepAll i k p) ]

def inputPreds : List (String × (AlloyInput → Bool)) :=
  [ ("figuresFit", alloyFiguresFit), ("inDomain", alloyInDomain),
    ("inDomain26", alloyInDomain26), ("inDomain27", alloyInDomain27),
    ("inDomain35", alloyInDomain35) ]

def atom (i : Nat) : String := s!"i{i}"

def setOf (xs : List Nat) : String :=
  if xs.isEmpty then "none" else " + ".intercalate (xs.map atom)

def boolF (b : Bool) : String := if b then "(no none)" else "(some none)"

def binding (inp : AlloyInput) : String :=
  ", ".intercalate <| (List.range inp.items.length).zip inp.items |>.map fun (n, item) =>
    let s := match item with
      | .line _ => "Line" | .heading => "Heading - Recto" | .recto => "Recto"
      | .figure _ => "Figure" | .blank => "Blank" | .space => "Space" | .need _ => "Need"
    s!"{atom n}: {s}"

def fixture (inp : AlloyInput) (k : AlloyKeeps) : List String :=
  let idx := List.range inp.items.length
  let pos := idx.map fun n => s!"{atom n}.pos = {n}"
  let attrs := (idx.zip inp.items).filterMap fun (n, item) => match item with
    | .figure s => some s!"{atom n}.size = {s}"
    | .need l => some s!"{atom n}.lines = {l}"
    | _ => none
  let lines := (idx.zip inp.items).filterMap fun (n, item) => (item.paraOf).map (n, ·)
  let paras := lines.bind fun (a, q) => lines.filterMap fun (b, r) =>
    if a < b then some (if q == r then s!"{atom a}.para = {atom b}.para"
      else s!"{atom a}.para != {atom b}.para") else none
  let lineOf := fun q => (lines.find? (·.2 == q)).map (·.1)
  let kept := k.kept.filterMap fun (q, f, l) => (lineOf q).map fun a =>
    (s!"{atom a}.para", s!"{atom a}.para.kf = {f} and {atom a}.para.kl = {l}")
  let keptSet := if kept.isEmpty then "no Kept" else
    s!"Kept = {" + ".intercalate (kept.map (·.1))}"
  let all := k.allLines.filterMap fun q => (lineOf q).map fun a => s!"{atom a}.para"
  let allSet := if all.isEmpty then "no AllLines" else s!"AllLines = {" + ".intercalate all}"
  [s!"Col.cap = {inp.cap}", s!"Col.used = {inp.used}"] ++ pos ++ attrs ++ paras ++
    kept.map (·.2) ++ [keptSet, allSet]

def matches_ (p : AlloyPlacement) : String :=
  s!"(p.brk = {p.brk} and p.kept = {setOf p.kept} and p.placed = {setOf p.placed})"

def agree (inp : AlloyInput) (k : AlloyKeeps) : List String :=
  let ps := alloyPlacements inp
  (inputPreds.map fun (name, f) => s!"({name} iff {boolF (f inp)})") ++
  (placementPreds.map fun (name, f) =>
    let yes := ps.filter (f inp k)
    let rhs := if yes.isEmpty then "(some none)" else
      "(" ++ " or ".intercalate (yes.map matches_) ++ ")"
    s!"(all p: Placement | {name}[p] iff {rhs})")

def command (n : Nat) (inp : AlloyInput) : String :=
  let k := diffKeeps inp n
  let paras := inp.paras.length
  let body := "some c: Col | " ++
    (if inp.items.isEmpty then "" else s!"some disj {binding inp} | ") ++
    "(" ++ " and ".intercalate (fixture inp k) ++ ") and (" ++
    " and ".intercalate (agree inp k) ++ ")"
  s!"run diff{n} \{\n  {body}\n} for {max 1 inp.items.length} but 6 Int, exactly {inp.items.length} Item, " ++
    s!"exactly {paras} Para, exactly {(alloyPlacements inp).length} Placement\n"

def diffKinds (cap : Nat) : List AlloyItem :=
  [.line 0, .line 1, .heading, .recto, .figure 1, .figure cap, .figure (cap+1),
   .blank, .space, .need 1, .need 2, .need (cap+1)]

/-- The sequences of exactly `n` items. -/
def diffSequences (cap : Nat) : Nat → List (List AlloyItem)
  | 0 => [[]]
  | n+1 => (diffSequences cap n).bind fun s => (diffKinds cap).map fun k => k :: s

/-- Every input of at most two items, and every `stride`-th input of three
    or four items, for capacities 3 and 4 and used lines 0, 1, cap - 1
    and cap, in that order. -/
def main (args : List String) : IO Unit := do
  let stride := (args.head? >>= String.toNat?).getD 97
  let mut n := 0
  let mut seen := 0
  for len in [0, 1, 2, 3, 4] do
    for cap in [3, 4] do
      for items in diffSequences cap len do
        for used in [0, 1, cap - 1, cap].eraseDups do
          let inp : AlloyInput := ⟨cap, used, items⟩
          if alloyInputFact inp then
            if len ≤ 2 || seen % stride == 0 then
              IO.println (command n inp)
              n := n + 1
            if len > 2 then seen := seen + 1
  IO.eprintln s!"{n} commands"
