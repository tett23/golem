/-
Root ADR 0352: the separators of root ADR 0398 in the free placement of
root ADR 0397, on the flows of Physical.lean.

golem-typeset makes the units of the separators the same way in both
modes: `spaceSeparators` and `holdSeparatorNeeds` (the local functions
of `blocks`, modules/golem-typeset/src/Golem/Typeset/Flow.hs:2484 and
:2451) read the page grid pitch only, so `Separator.separatorUnits`
stands for both.  What the free mode does differently is the length of
the flows: the flows of `bRetainedFlow` are in sp, and `paginateBuilt`
(Flow.hs:827) passes them to `paginatePhysical` as they are, while the
grid mode divides each length by the line pitch first (`gridUnits`,
Flow.hs:834).  `flows` maps the grid flows of Whole.lean (those
`WholePagination.Separator.separatorFlows` and SeparatorBlocks.lean make) back to the sp
flows: a gap of `n` grid lines, which `spaceSeparators` makes `n` times
the pitch (Flow.hs:2510), is `FSpace` of `n * pitch` sp (Flow.hs:3730);
the box of a paragraph takes its grid lines before and after times the
pitch (Flow.hs:3908); a ruled block carries the measures of its rules in
sp (`ruleSide`, Flow.hs:3569), given here by `side`, as the flows of
Whole.lean only say whether it has them.  Blank lines, need-lines and
keep-with-next stay counts of lines (Flow.hs:3739, :3743, :3744), and a
visible separator is a paragraph of its one line (Flow.hs:3898).

`separatorHoldErrors` (Flow.hs:793) reads the pages of either mode;
`holdErrors` below is `Separator.holdErrors` on the pages of
Physical.lean.  Every definition is total.

`textOf` and `figsOf` read the lines and the figures the sp flows carry.
Both add up over the flows and pass the changes of SeparatorBlocks.lean
(`textOf_nested`, `figsOf_nested`), so invariants 4 and 5 of root ADR
0352 hold of the flows `paginatePhysical` receives by the theorems of
Physical.lean (`I4_free_paginate_ends`, `I5_free_text`,
`I5_free_figures` and the same for the flows with blocks).
-/
import Whole
import Separator
import SeparatorBlocks
import Physical

namespace SeparatorPhysical

open WholePagination (Separator.Unit Separator.holdGroups)

def line (l : WholePagination.Line) : PhysicalPagination.Line :=
  ⟨l.id, l.notes.map (fun n => ⟨n.id, n.lines⟩), 0⟩

def keep (k : WholePagination.Keep) : PhysicalPagination.Keep := ⟨k.first, k.last, k.all⟩

def breakKind : WholePagination.BreakKind → PhysicalPagination.BreakKind
  | .page => .page
  | .column => .column
  | .recto => .recto
  | .verso => .verso

def partUnit : WholePagination.KeepParts → PhysicalPagination.PartUnit
  | .column => .column
  | .page => .page
  | .spread => .spread

/-- `FRuled` (Flow.hs:3888): the rule before (`side true`) and the rule
    after (`side false`) it has, no overhang of the line after it, and its
    lines or its heading of `n` grid lines. -/
def ruled (pitch : Int) (side : Bool → PhysicalPagination.RuleSide) (i : Nat) (b a j : Bool) :
    WholePagination.RuledBody → PhysicalPagination.Flow
  | .lines k ls => .ruled ⟨i, if b then some (side true) else none, if a then some (side false) else none, j, 0, keep k, ls.map line, none⟩
  | .heading r n ls =>
    .ruled ⟨i, if b then some (side true) else none, if a then some (side false) else none, j, 0, PhysicalPagination.defaultKeep, ls.map line,
      some (r, (n : Int) * pitch)⟩

mutual
/-- The sp flow of a flow of the grid mode, of a pitch of `pitch` sp: the
    lengths that `gridUnits` (Flow.hs:834) divides by the pitch are
    multiplied back.  Only the flows the manuscripts here make are
    mapped; the others are dropped. -/
def flow (pitch : Int) (side : Bool → PhysicalPagination.RuleSide) : WholePagination.Flow → List PhysicalPagination.Flow
  | .paragraph k ls => [.paragraph (keep k) (ls.map line)]
  | .continued k ls => [.continued (keep k) (ls.map line)]
  | .space n => [.space ((n : Int) * pitch)]
  | .blank n => [.blank n]
  | .brk k => [.brk (breakKind k)]
  | .needLines n => [.needLines n]
  | .noBreak => [.noBreak]
  | .noBreakLines n => [.noBreakLines n]
  | .keepNext n sp => [.keepNext n sp]
  | .boxed i b a body => [.boxed i ((b : Int) * pitch) ((a : Int) * pitch) (flows pitch side body)]
  | .bookPart u _ ids body => [.bookPart (partUnit u) ids (flows pitch side body)]
  | .ruled i b a j body => [ruled pitch side i b a j body]
  | _ => []

def flows (pitch : Int) (side : Bool → PhysicalPagination.RuleSide) : List WholePagination.Flow → List PhysicalPagination.Flow
  | [] => []
  | f :: fs => flow pitch side f ++ flows pitch side fs
end

/-! ## G07134 on the pages of the free placement -/

/-- The ids a slot holds (`ids` of `separatorHoldErrors`, Flow.hs:802). A
    header line repeated in a later column is `SLine` in Physical.hs. -/
def slotIds : PhysicalPagination.Slot → List Nat
  | .line i | .figure i | .pageFigure i | .wrapped i | .repeated i => [i]
  | .heading i c => (List.range c).map (i + ·)
  | .code rows _ => rows

/-- The page and the column of the first slot that holds the id
    (`places` of `separatorHoldErrors`, Flow.hs:801). -/
def place (pages : List PhysicalPagination.PageOut) (i : Nat) : Option (Nat × Nat) :=
  (pages.find? (fun p => p.slots.any (fun s => (slotIds s.2).contains i))).map (fun p => (p.number, p.column))

def splitAcross (pages : List PhysicalPagination.PageOut) (ids : List Nat) : Bool :=
  match ids.filterMap (place pages) with
  | p :: rest => rest.any (· != p)
  | [] => false

/-- `separatorHoldErrors` (Flow.hs:793) on the pages of the free
    placement: the index of the first separator of each chain split
    across columns. -/
def holdErrors (us : List Separator.Unit) (pages : List PhysicalPagination.PageOut) : List Nat :=
  ((Separator.holdGroups us).filter (fun g => splitAcross pages g.2)).map (·.1)

/-! ## Invariants 4 and 5 on the flows of the free placement -/

theorem flows_append (pitch : Int) (side : Bool → PhysicalPagination.RuleSide) (a b : List WholePagination.Flow) :
    flows pitch side (a ++ b) = flows pitch side a ++ flows pitch side b := by
  induction a with
  | nil => simp [flows]
  | cons f r ih => simp [flows, ih]

theorem physText_append (a b : List PhysicalPagination.Flow) :
    PhysicalPagination.sourceText (a ++ b) = PhysicalPagination.sourceText a ++ PhysicalPagination.sourceText b := by
  induction a with
  | nil => simp [PhysicalPagination.sourceText]
  | cons f r ih => simp [PhysicalPagination.sourceText, ih]

theorem physFigs_append (a b : List PhysicalPagination.Flow) :
    PhysicalPagination.sourceFigs (a ++ b) = PhysicalPagination.sourceFigs a ++ PhysicalPagination.sourceFigs b := by
  induction a with
  | nil => simp [PhysicalPagination.sourceFigs]
  | cons f r ih => simp [PhysicalPagination.sourceFigs, ih]

/-- The lines the sp flows of the grid flows carry, as the pages of the
    free placement hold them. -/
def textOf (pitch : Int) (side : Bool → PhysicalPagination.RuleSide) (fs : List WholePagination.Flow) : List Nat :=
  PhysicalPagination.sourceText (flows pitch side fs)

/-- The figures the sp flows of the grid flows carry. -/
def figsOf (pitch : Int) (side : Bool → PhysicalPagination.RuleSide) (fs : List WholePagination.Flow) : List Nat :=
  PhysicalPagination.sourceFigs (flows pitch side fs)

theorem textOf_nested (pitch : Int) (side : Bool → PhysicalPagination.RuleSide) :
    WholePagination.SeparatorBlocks.Nested (textOf pitch side) :=
  { nil := rfl
    cons := fun f r => by
      simp only [textOf]
      rw [show flows pitch side (f :: r) = flows pitch side [f] ++ flows pitch side r from
        (flows_append pitch side [f] r), physText_append]
    onBlank := fun n => by simp [textOf, flows, flow, PhysicalPagination.sourceText, PhysicalPagination.flowText]
    onSpace := fun n => by simp [textOf, flows, flow, PhysicalPagination.sourceText, PhysicalPagination.flowText]
    onKeepNext := fun n sp => by simp [textOf, flows, flow, PhysicalPagination.sourceText, PhysicalPagination.flowText]
    onNeedLines := fun n => by simp [textOf, flows, flow, PhysicalPagination.sourceText, PhysicalPagination.flowText]
    boxed := fun i kb ka body => by simp [textOf, flows, flow, PhysicalPagination.sourceText, PhysicalPagination.flowText]
    bookPart := fun u k ids body => by
      simp [textOf, flows, flow, PhysicalPagination.sourceText, PhysicalPagination.flowText]
    ruled := fun i b a j j' body => by
      cases body <;> simp [textOf, flows, flow, ruled, PhysicalPagination.sourceText, PhysicalPagination.flowText,
        PhysicalPagination.ruledText] }

theorem figsOf_nested (pitch : Int) (side : Bool → PhysicalPagination.RuleSide) :
    WholePagination.SeparatorBlocks.Nested (figsOf pitch side) :=
  { nil := rfl
    cons := fun f r => by
      simp only [figsOf]
      rw [show flows pitch side (f :: r) = flows pitch side [f] ++ flows pitch side r from
        (flows_append pitch side [f] r), physFigs_append]
    onBlank := fun n => by simp [figsOf, flows, flow, PhysicalPagination.sourceFigs, PhysicalPagination.flowFigs]
    onSpace := fun n => by simp [figsOf, flows, flow, PhysicalPagination.sourceFigs, PhysicalPagination.flowFigs]
    onKeepNext := fun n sp => by simp [figsOf, flows, flow, PhysicalPagination.sourceFigs, PhysicalPagination.flowFigs]
    onNeedLines := fun n => by simp [figsOf, flows, flow, PhysicalPagination.sourceFigs, PhysicalPagination.flowFigs]
    boxed := fun i kb ka body => by simp [figsOf, flows, flow, PhysicalPagination.sourceFigs, PhysicalPagination.flowFigs]
    bookPart := fun u k ids body => by
      simp [figsOf, flows, flow, PhysicalPagination.sourceFigs, PhysicalPagination.flowFigs]
    ruled := fun i b a j j' body => by
      cases body <;> simp [figsOf, flows, flow, ruled, PhysicalPagination.sourceFigs, PhysicalPagination.flowFigs] }

/-- Root ADR 0352 invariant 4 on the separators in the free placement, by
    `PhysicalPagination.I4_paginate_ends`. -/
theorem I4_free_paginate_ends (env : PhysicalPagination.Env) (pitch : Int) (side : Bool → PhysicalPagination.RuleSide)
    (capacity : Nat) (us : List Separator.Unit) :
    ∃ r, PhysicalPagination.paginate env (flows pitch side (WholePagination.Separator.separatorFlows capacity us)) = r :=
  PhysicalPagination.I4_paginate_ends env _

/-- Root ADR 0352 invariant 5 for the lines on the separators in the free
    placement: when `paginatePhysical` returns pages, they hold the lines
    the units carry into the free placement once each, in the order
    written, by `PhysicalPagination.I5_paginate_text`. -/
theorem I5_free_text (env : PhysicalPagination.Env) (pitch : Int) (side : Bool → PhysicalPagination.RuleSide)
    (capacity : Nat) (us : List Separator.Unit) (pages : List PhysicalPagination.PageOut)
    (h : PhysicalPagination.paginate env (flows pitch side (WholePagination.Separator.separatorFlows capacity us)) = .ok pages) :
    PhysicalPagination.pagesText pages = textOf pitch side (WholePagination.Separator.allFlows us) := by
  rw [PhysicalPagination.I5_paginate_text env _ pages h]
  exact (textOf_nested pitch side).separatorFlows_eq capacity us

/-- Root ADR 0352 invariant 5 for the figures on the separators in the
    free placement, by `PhysicalPagination.I5_paginate_figures`. -/
theorem I5_free_figures (env : PhysicalPagination.Env) (pitch : Int) (side : Bool → PhysicalPagination.RuleSide)
    (capacity : Nat) (us : List Separator.Unit) (pages : List PhysicalPagination.PageOut)
    (h : PhysicalPagination.paginate env (flows pitch side (WholePagination.Separator.separatorFlows capacity us)) = .ok pages) :
    PhysicalPagination.pagesFigs pages = figsOf pitch side (WholePagination.Separator.allFlows us) := by
  rw [PhysicalPagination.I5_paginate_figures env _ pages h]
  exact (figsOf_nested pitch side).separatorFlows_eq capacity us

/-- Invariant 4 on the flows after `joinBoxes`, `ruledLinks` and
    `markBookParts` in the free placement. -/
theorem I4_free_blocks_paginate_ends (env : PhysicalPagination.Env) (pitch : Int)
    (side : Bool → PhysicalPagination.RuleSide) (key : Nat → Option Nat) (unit : WholePagination.KeepParts)
    (owners : List (Nat × Option Nat)) (capacity : Nat) (us : List Separator.Unit) :
    ∃ r, PhysicalPagination.paginate env
      (flows pitch side (WholePagination.SeparatorBlocks.blockFlows key unit owners capacity us)) = r :=
  PhysicalPagination.I4_paginate_ends env _

/-- Invariant 5 for the lines on the flows after the three changes in the
    free placement. -/
theorem I5_free_blocks_text (env : PhysicalPagination.Env) (pitch : Int) (side : Bool → PhysicalPagination.RuleSide)
    (key : Nat → Option Nat) (unit : WholePagination.KeepParts) (owners : List (Nat × Option Nat))
    (capacity : Nat) (us : List Separator.Unit) (pages : List PhysicalPagination.PageOut)
    (h : PhysicalPagination.paginate env
      (flows pitch side (WholePagination.SeparatorBlocks.blockFlows key unit owners capacity us)) = .ok pages) :
    PhysicalPagination.pagesText pages = textOf pitch side (WholePagination.Separator.allFlows us) := by
  rw [PhysicalPagination.I5_paginate_text env _ pages h]
  exact (textOf_nested pitch side).blockFlows_eq key unit owners capacity us

/-- Invariant 5 for the figures on the flows after the three changes in
    the free placement. -/
theorem I5_free_blocks_figures (env : PhysicalPagination.Env) (pitch : Int)
    (side : Bool → PhysicalPagination.RuleSide) (key : Nat → Option Nat) (unit : WholePagination.KeepParts)
    (owners : List (Nat × Option Nat)) (capacity : Nat) (us : List Separator.Unit)
    (pages : List PhysicalPagination.PageOut)
    (h : PhysicalPagination.paginate env
      (flows pitch side (WholePagination.SeparatorBlocks.blockFlows key unit owners capacity us)) = .ok pages) :
    PhysicalPagination.pagesFigs pages = figsOf pitch side (WholePagination.Separator.allFlows us) := by
  rw [PhysicalPagination.I5_paginate_figures env _ pages h]
  exact (figsOf_nested pitch side).blockFlows_eq key unit owners capacity us

end SeparatorPhysical
