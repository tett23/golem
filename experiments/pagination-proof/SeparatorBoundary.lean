/- Root ADR 0352: the manuscripts of SeparatorBoundary.hs on the flows
   Separator.lean makes, after `joinBoxes`, `ruledLinks` and
   `markBookParts` of SeparatorBlocks.lean, and the paginate of
   Whole.lean, under the `Env` of Boundary.lean.  `report` prints the pages, or G07134 at the line of
   the first separator of each chain split across columns, in the format
   of SeparatorBoundary.hs, and check.sh compares the two with diff.
   With `SEPARATOR_MODE=free`, the same manuscripts are laid out in the
   free placement: the sp flows of SeparatorPhysical.lean on the paginate
   of Physical.lean, under `freeEnv`, the `PhysicalSettings` that
   `physicalSettings` (Flow.hs:853) gives for the page of
   SeparatorBoundary.hs.  With `SEPARATOR_MODE` starting with `blocks`,
   the manuscripts with a box, a ruled paragraph or an item of a list
   (`blockManuscripts`) are laid out instead, and with `SEPARATOR_MODE`
   starting with `holds`, the manuscripts with a no-break after the
   paragraph a separator is held with (`holdManuscripts`).
   This is a check on finitely many inputs, not a proof. -/
import Whole
import Separator
import Boundary
import Physical
import SeparatorPhysical
import SeparatorBlocks
open WholePagination Boundary

namespace SeparatorBoundary

/-- The items of SeparatorBoundary.hs. -/
inductive Item where
  | p (k : Nat) | s | t | g | b | e | n
  /-- A paragraph of one line in a box, one with rules and an item of a
      list of one line. -/
  | x | r | l
  /-- `@blank-line` lines collapsed into one block of `k` lines. -/
  | bk (k : Nat)
  /-- `@no-page-break`, in the manuscripts of the holds. -/
  | nb
  deriving DecidableEq

def Item.name : Item → String
  | .p k => s!"P{k}"
  | .s => "S" | .t => "T" | .g => "G" | .b => "B" | .e => "E" | .n => "N" | .bk k => s!"B{k}"
  | .x => "X" | .r => "R" | .l => "L" | .nb => "K"

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
  | id, .nb :: r => .other .pass [.noBreak] none :: units c id r
  | id, .x :: r => .other .block [.boxed id 1 1 [.paragraph defaultKeep (lines' id 1)]] (some id) :: units c (id + 1) r
  | id, .r :: r => .other .block [.ruled id true true false (.lines defaultKeep (lines' id 1))] (some id) :: units c (id + 1) r
  | id, .l :: r => .other .block [.paragraph defaultKeep (lines' id 1)] (some id) :: units c (id + 1) r

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

/-- `blockManuscripts` of SeparatorBoundary.hs. -/
def blockManuscripts : List (List Item) :=
  [[], [Item.p 1]].bind fun lead => [1, 2, 3].bind fun n =>
    ((replicateM n [Item.s, .t, .x, .r, .l, .n, .p 1]).filter fun m => m.any fun i => i == .s || i == .t).bind fun middle =>
      ([[], [Item.p 1], [Item.x], [Item.r], [Item.l]].filter fun last =>
        (middle ++ last).any fun i => i == .x || i == .r || i == .l).map fun last => lead ++ middle ++ last

def blockInputs : List (Nat × Nat × List Item) :=
  (List.range combos.length).bind fun c => [3, 4].bind fun capacity => blockManuscripts.map fun m => (c, capacity, m)

/-- `holdManuscripts` of SeparatorBoundary.hs. -/
def holdManuscripts : List (List Item) :=
  [[], [Item.p 1]].bind fun lead => [Item.s, .t].bind fun s => [[], [Item.s], [Item.b]].bind fun pre =>
    [1, 2, 3].bind fun a =>
      [[Item.p 1], [.p 2], [.p 3], [.p 1, .nb, .p 1], [.p 2, .nb, .p 2]].map fun after =>
        lead ++ [s] ++ pre ++ [.p a, .nb] ++ after

def holdInputs : List (Nat × Nat × List Item) :=
  (List.range combos.length).bind fun c => [2, 3, 4, 5].bind fun capacity => holdManuscripts.map fun m => (c, capacity, m)

/-- The lines an item takes. -/
def Item.lines : Item → Nat
  | .p k => k
  | .s | .t | .x | .r | .l => 1
  | _ => 0

/-- The first line of each item with lines and the item of a list it is,
    if any (`owners` of `markBookParts`). -/
def owners (items : List Item) : List (Nat × Option Nat) :=
  let rec go : Nat → List Item → List (Nat × Option Nat)
    | _, [] => []
    | ident, i :: rest =>
      (if 0 < i.lines then [(ident, if i == .l then some ident else none)] else []) ++ go (ident + i.lines) rest
  go 0 items

/-- The boxes by their first line: all of one paragraph style. -/
def boxKey (items : List Item) (i : Nat) : Option Nat :=
  if (boxIds items).contains i then some 0 else none
where
  boxIds (items : List Item) : List Nat :=
    let rec go : Nat → List Item → List Nat
      | _, [] => []
      | ident, it :: rest => (if it == .x then [ident] else []) ++ go (ident + it.lines) rest
    go 0 items

/-- The flows golem-typeset paginates (`bRetainedFlow`), in a column of
    `capacity` lines, the parts of lists kept in a column. -/
def flowsOf (items : List Item) (capacity : Nat) (us : List Separator.Unit) : List Flow :=
  SeparatorBlocks.blockFlows (boxKey items) .column (owners items) capacity us

/-- `boundaryEnv` with the rule areas of RuleArea.hs for the rules of
    `blockStyle` (a weight of 1pt, 10pt outside and 5pt inside the rule
    before, 10pt inside and 5pt outside the rule after, on a pitch of 15pt
    and a face of 10pt): one grid line inside the column (`ruleLines`),
    one at its start and at its end, and two shared; the keeps of the
    visible separators are `held` (`paginateHeld`, Flow.hs:869). -/
def blockEnv (capacity : Nat) (held : Nat → Bool) : Env :=
  { boundaryEnv capacity held with
    ruleBefore := fun _ _ _ => 1
    rulesJoined := fun _ _ => 2
    ruleAfter := fun _ => 1
    ruleAfterAtEnd := fun _ _ => 1 }

/-- The spans of the keeps of the visible separators (`separatorSpans`,
    Flow.hs:826): those of the separators, by the ids of their lines. -/
def held (us : List Separator.Unit) (sp : Nat) : Bool := (Separator.separatorSpans us).contains sp

/-- The line of the separator at an index of the units. -/
def siteLine (us : List Separator.Unit) (i : Nat) : String :=
  match us.get? i with
  | some (.separator _ _ _ l) => toString l.id
  | _ => s!"@{i}"

def output (c capacity : Nat) (items : List Item) : List String :=
  let us := units (combos.getD c ((0, 0), (0, 0))) 0 (overPage capacity (effective (collapse items)))
  let made := Separator.separatorUnits capacity us
  let final := paginate (blockEnv capacity (held us)) (flowsOf items capacity us)
  -- the controls not met in a column with no output go with the last
  -- page, as `paginateWithin` of Paginate.hs puts them
  let pages := match final.done with
    | [] => [⟨1, 0, false, [], [], final.unmet, []⟩]
    | last :: earlier => ({ last with unmet := last.unmet ++ final.unmet } :: earlier).reverse
  match Separator.holdErrors made pages with
  -- SeparatorBoundary.hs does not print the rules placed
  | [] => pages.map fun p => pageText { p with rules := [] }
  | sites => ["error " ++ " ".intercalate ((sites.map fun i => s!"G07134:{siteLine made i}").toArray.qsort (· < ·)).toList]


/-! ## The free placement -/

/-- The line pitch and the font size of `horizontalStyle` (15pt, 10pt) in sp. -/
def pitch : Int := 15 * 65536
def face : Int := 10 * 65536

/-- `firstNeed` of Physical.hs (Paginate/Physical.hs:731), every line of
    the pitch of the page: the body paragraphs and the separators of these
    manuscripts take no line pitch of their own (`bLinePitches`). -/
partial def firstNeed (separator capacity : Int) (hasNotes : Bool) (wanted : Nat) : List PhysicalPagination.Flow → Int
  | .paragraph k ls :: rest => paragraphNeed separator capacity hasNotes wanted k true ls rest
  | .continued k ls :: rest => paragraphNeed separator capacity hasNotes wanted k false ls rest
  | .stanza k vs :: rest =>
    let total := vs.length
    let lowest := max (PhysicalPagination.firstPart k true total) (min total (max 1 wanted))
    let count := ((List.range (total + 1)).filter (fun n => lowest ≤ n ∧ PhysicalPagination.splitAtBreak k true total n = n)).headD total
    let chosen := (vs.take count).join
    let following :=
      match count == total, PhysicalPagination.keepAhead rest with
      | true, some (_, f, later) => firstNeed separator capacity (hasNotes || chosen.any (fun l => !l.notes.isEmpty)) f later
      | _, _ => 0
    (chosen.length : Int) * pitch + noteNeed separator hasNotes chosen + following
  | .space s :: rest => s + firstNeed separator capacity hasNotes wanted rest
  | .blank n :: rest => (n : Int) * pitch + firstNeed separator capacity hasNotes wanted rest
  | .needLines _ :: rest | .adjustLines _ :: rest | .noBreak :: rest
  | .noBreakLines _ :: rest | .keepNext _ _ :: rest => firstNeed separator capacity hasNotes wanted rest
  | .figure _ e :: _ => e
  | .wrapped _ e _ :: _ => e
  | .heading true _ _ :: _ => 0
  | .heading false extent ls :: rest =>
    extent + noteNeed separator hasNotes ls + firstNeed separator capacity (hasNotes || ls.any (fun l => !l.notes.isEmpty)) 1 rest
  | .defTerm ls :: _ => (ls.length : Int) * pitch + noteNeed separator hasNotes ls
  | _ => 0
where
  noteNeed (separator : Int) (hasNotes : Bool) (ls : List PhysicalPagination.Line) : Int :=
    let c : Nat := (ls.map PhysicalPagination.noteLines).foldr (· + ·) 0
    (if 0 < c ∧ !hasNotes then separator else 0) + (c : Int) * pitch
  paragraphNeed (separator capacity : Int) (hasNotes : Bool) (wanted : Nat) (k : PhysicalPagination.Keep) (start : Bool)
      (ls : List PhysicalPagination.Line) (rest : List PhysicalPagination.Flow) : Int :=
    let total := ls.length
    let lowest := max (PhysicalPagination.firstPart k start total) (min total (max 1 wanted))
    let count := ((List.range (total + 1)).filter (fun n => lowest ≤ n ∧ PhysicalPagination.splitAtBreak k start total n = n)).headD total
    let chosen := ls.take count
    let following :=
      match count == total, PhysicalPagination.keepAhead rest with
      | true, some (_, f, later) => firstNeed separator capacity (hasNotes || chosen.any (fun l => !l.notes.isEmpty)) f later
      | _, _ => 0
    (chosen.length : Int) * pitch + noteNeed separator hasNotes chosen + following

/-- `physicalSettings` (Flow.hs:853) for a column of `lines` grid lines:
    its height is `(lines - 1) * pitch + face`; the manuscripts have no
    notes, no `@page-lines`, no headings, no wrapped figures, and the
    boxes have no padding of their own. -/
def freeEnv (lines : Nat) (held : Nat → Bool) : PhysicalPagination.Env :=
  let cap : Int := ((lines : Int) - 1) * pitch + face
  { pagePitch := pitch, fontSize := face, capacity := cap, maxCapacity := cap, separator := pitch,
    columns := 1, firstLine := 0, pitchOf := fun _ => pitch, faceOf := fun _ => face,
    headingBounds := fun _ => none, wrappedBefore := fun _ => 0, boxPadding := fun _ => none,
    firstNeed := firstNeed pitch cap, retention := none, held := held }

/-- The rules of `blockStyle` as `ruleSide` (Flow.hs:3569) makes them:
    the rule before has its space after inside and its space before
    outside, the rule after the other way round; both are spaced and kept
    in the column. -/
def side : Bool → PhysicalPagination.RuleSide
  | true => ⟨5 * 65536, 10 * 65536, 65536, true, none⟩
  | false => ⟨10 * 65536, 5 * 65536, 65536, true, none⟩

/-- `freeEnv` with the padding of the boxes of `blockStyle`, 1zw, by the
    first line of each box (`bBoxPadding`, Flow.hs:4202). -/
def freeBlockEnv (items : List Item) (lines : Nat) (held : Nat → Bool) : PhysicalPagination.Env :=
  { freeEnv lines held with boxPadding := fun i => if (boxKey items i).isSome then some face else none }

def freeSlot : Int × PhysicalPagination.Slot → String
  | (p, .line i) | (p, .repeated i) => s!"{p}:L{i}"
  | (p, .figure i) => s!"{p}:SFigure {i}"
  | (p, .pageFigure i) => s!"{p}:SPageFigure {i}"
  | (p, .wrapped i) => s!"{p}:SWrapped {i}"
  | (p, .heading i n) => s!"{p}:SHeading {i} {n}"
  | (p, .code ids g) => s!"{p}:SCode {ids.headD 0} {ids.length} {g}"

def freeUnmet : PhysicalPagination.Unmet → String
  | .needLines n => s!"!need{n}"
  | .noBreak => "!nobreak"
  | .keepNext _ => "!keepnext"
  | .droppedBlank => "!dropped"
  | .shortPart true i w g => s!"!first{i}:{w}:{g}"
  | .shortPart false i w g => s!"!last{i}:{w}:{g}"
  | _ => "!other"

def freePageText (p : PhysicalPagination.PageOut) : String :=
  " ".intercalate ([toString p.number, toString p.column, if p.blank then "blank" else "-"] ++ p.slots.map freeSlot ++ p.unmet.map freeUnmet)

/-- The byte length of the source of an item in SeparatorBoundary.hs. -/
def Item.bytes : Item → Nat
  | .p k => 36 * k
  | .s => 3 | .t => 16 | .g => 14 | .b => 13 | .e => 11 | .n => 13 | .bk _ => 13
  | .x => 13 + 30 | .r => 13 + 36 | .l => 2 + 30 | .nb => 14

/-- Where SeparatorBoundary.hs prints a diagnostic at the unit of the line
    `i`: the id of a separator, or the byte offset of the paragraph
    (`physicalError` and `paraOfLine`, Flow.hs:840). -/
def lineSite (items : List Item) (i : Nat) : String :=
  let rec go : Nat → Nat → List Item → String
    | _, _, [] => s!"?{i}"
    | ident, offset, it :: rest =>
      if ident ≤ i ∧ i < ident + it.lines then
        (if it == .s || it == .t then toString ident else s!"@{offset}")
      else go (ident + it.lines) (offset + it.bytes + 2) rest
  go 0 0 items

def failureText (items : List Item) : PhysicalPagination.Failure → String
  | .lineTooTall i => s!"G07129:{lineSite items i}"
  | .boxTooTall i => s!"G07121:{lineSite items i}"
  | _ => "failure"

def freeOutput (c capacity : Nat) (items : List Item) : List String :=
  let us := units (combos.getD c ((0, 0), (0, 0))) 0 (overPage capacity (effective (collapse items)))
  let made := Separator.separatorUnits capacity us
  match PhysicalPagination.paginate (freeBlockEnv items capacity (held us)) (SeparatorPhysical.flows pitch side (flowsOf items capacity us)) with
  | .error f => ["error " ++ failureText items f]
  | .ok pages =>
    match SeparatorPhysical.holdErrors made pages with
    | [] => pages.map freePageText
    | sites => ["error " ++ " ".intercalate ((sites.map fun i => s!"G07134:{siteLine made i}").toArray.qsort (· < ·)).toList]

def report (blocks holds free : Bool) (part parts : Nat) : String :=
  let all := if blocks then blockInputs else if holds then holdInputs else inputs
  let size := (all.length + parts - 1) / parts
  String.join (((all.drop (part * size)).take size).map fun (c, capacity, items) =>
    s!"{c} {capacity} [{" ".intercalate (items.map Item.name)}]\n" ++
      String.join (((if free then freeOutput else output) c capacity items).map fun p => s!"  {p}\n"))

/-- `fitting` of Boundary.lean counts the free lines of the column for
    lines with no footnote. -/
theorem fitting_go (env : Env) (st : St) (u nl : Int) (ls : List Line) (h : ∀ x ∈ ls, x.notes = []) :
    Boundary.fitting.go env st u nl ls = min ls.length (cap env st - u - nl).toNat := by
  induction ls generalizing u with
  | nil => simp [Boundary.fitting.go]
  | cons x xs ih =>
    have hx : x.notes = [] := h x (List.mem_cons_self _ _)
    simp only [Boundary.fitting.go, hx, List.map, List.foldr]
    have z : (nl + ((0 : Nat) : Int) + if nl = 0 ∧ (0 : Int) < ((0 : Nat) : Int) then env.separator else 0) = nl := by
      simp
    rw [z, ih (u + 1) (fun y m => h y (List.mem_cons_of_mem _ m))]
    split
    · have e := Int.toNat_of_nonneg (show 0 ≤ cap env st - (u + 1) - nl by omega)
      have e2 := Int.toNat_of_nonneg (show 0 ≤ cap env st - u - nl by omega)
      simp only [List.length]
      omega
    · have : (cap env st - u - nl).toNat = 0 := by
        have hh : cap env st - u - nl ≤ 0 := by omega
        generalize cap env st - u - nl = a at hh ⊢
        cases a with
        | ofNat k =>
          have : k = 0 := by have := hh; simp only [Int.ofNat_eq_coe] at this; omega
          subst this; rfl
        | negSucc k => rfl
      simp [this]

/-- The `Env` of the check satisfies `Separator.PlainFitting`, the
    hypothesis of `Separator.I3_separator_hold_together`. -/
theorem boundary_plainFitting (capacity : Nat) : Separator.PlainFitting (Boundary.boundaryEnv capacity) := by
  intro s ls h
  show Boundary.fitting _ s ls = _
  unfold Boundary.fitting
  rw [fitting_go _ s _ _ ls h]
  simp only [free, Boundary.boundaryEnv, Boundary.plainEnv, cap]

end SeparatorBoundary

-- check.sh evaluates the inputs in `SEPARATOR_PARTS` contiguous parts
-- side by side, this one part `SEPARATOR_PART`: the manuscripts with
-- blocks when `SEPARATOR_MODE` starts with `blocks`, those of the holds
-- when it starts with `holds`, in the free
-- placement when it ends with `free`; `#eval` prints it, as `main` is
-- Boundary.lean's.
#eval show IO _root_.Unit from do
  let part := ((← IO.getEnv "SEPARATOR_PART").getD "0").toNat!
  let parts := ((← IO.getEnv "SEPARATOR_PARTS").getD "1").toNat!
  let mode := (← IO.getEnv "SEPARATOR_MODE").getD ""
  IO.print (SeparatorBoundary.report (mode.startsWith "blocks") (mode.startsWith "holds") (mode.endsWith "free") part parts)
