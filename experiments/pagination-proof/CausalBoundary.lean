/- Root ADR 0352: the manuscripts of CausalBoundary.hs, a wrapped figure
   followed by paragraphs and stanzas in the free placement, on the copies
   of the loops of golem-typeset's causalFreeFlow in Physical.lean:
   `jobsFrom` runs the figure, `paragraphs` the paragraphs and stanzas
   beside it, `parts` (`paragraph`) each paragraph, broken again at each
   cursor, `stanza`, `tryVerses` and `accept` each stanza, `itemJobs` the
   later figures of a list item kept on a page or a spread, and, with a
   no-break after a paragraph or a stanza, `probeNext` and `probeChain`
   what follows it.  `main` prints the pages in the format of
   CausalBoundary.hs, and check.sh compares the two with diff.

   What the loops take as arguments is given here as golem-typeset
   computes it for these manuscripts.  The line breaker (`composeAt`) is
   modelled for the fake fonts of the golem-driver tests: every character
   is 1zw and a line takes as many characters as its width holds, its
   width the measure of 12zw (10zw in a list item, indented by 2zw) less
   the exclusion of the figure where the row meets it (`rowExtent` and `intersects` of FreeGeometry.hs).  The
   figure is the image of 2 by 3 pixels at a width of `w` zw: its length
   across the lines is 1.5 `w` zw, and the gap of 1zw (`wrap-gap`) is
   added to both its exclusion length and width (`exclusion`,
   Flow.hs:3315).  A line or a figure has the id of the lines and the
   figures placed before it (`bUnitFirsts`), so the first line of a verse
   line (`ident`) is the number of them placed before the cursor.  A verse
   line not yet tried keeps the rows `composeBeside` composed.  A
   paragraph not beside a figure is placed as an `FParagraph` of the rows
   of its measure.  The paragraphs and the verse lines have the default
   keep.  Those of the styles `held` and `poemk` keep with the next 3 lines
   (`keep-with-next = 3`), the others with nothing, so `bindingAfter` comes
   from the no-breaks after them and that count, and `keepPhysicalNext`
   waits after those that keep.

   This is a check on finitely many inputs, not a proof. -/
import Physical
open PhysicalPagination

namespace CausalBoundary

def zw : Int := 10 * 65536
def pitch : Int := 15 * 65536
def face : Int := zw

/-- `firstNeed` of Physical.hs (Paginate/Physical.hs:731) for the flows of
    these manuscripts: the paragraph lines of the pitch of the page. -/
partial def firstNeed (separator capacity : Int) (hasNotes : Bool) (wanted : Nat) : List Flow → Int
  | .paragraph k ls :: rest => paragraphNeed separator capacity hasNotes wanted k true ls rest
  | .continued k ls :: rest => paragraphNeed separator capacity hasNotes wanted k false ls rest
  | .stanza k vs :: rest =>
    let count := prefixCount wanted k true vs.length
    let following :=
      match count == vs.length, keepAhead rest with
      | true, some (_, f, later) => firstNeed separator capacity hasNotes f later
      | _, _ => 0
    ((vs.take count).join.length : Int) * pitch + following
  | .space s :: rest => s + firstNeed separator capacity hasNotes wanted rest
  | .blank n :: rest => (n : Int) * pitch + firstNeed separator capacity hasNotes wanted rest
  | .needLines _ :: rest | .adjustLines _ :: rest | .noBreak :: rest
  | .noBreakLines _ :: rest | .keepNext _ _ :: rest => firstNeed separator capacity hasNotes wanted rest
  | .figure _ e :: _ => e
  | .wrapped _ e _ :: _ => e
  | _ => 0
where
  prefixCount (wanted : Nat) (k : Keep) (start : Bool) (total : Nat) : Nat :=
    let lowest := max (firstPart k start total) (min total (max 1 wanted))
    ((List.range (total + 1)).filter (fun n => lowest ≤ n ∧ splitAtBreak k start total n = n)).headD total
  paragraphNeed (separator capacity : Int) (hasNotes : Bool) (wanted : Nat) (k : Keep) (start : Bool)
      (ls : List Line) (rest : List Flow) : Int :=
    let total := ls.length
    let count := prefixCount wanted k start total
    let following :=
      match count == total, keepAhead rest with
      | true, some (_, f, later) => firstNeed separator capacity hasNotes f later
      | _, _ => 0
    (count : Int) * pitch + following

/-- `physicalSettings` (Flow.hs:853) for a column of `lines` grid lines. -/
def env (lines : Nat) : Env :=
  let cap : Int := ((lines : Int) - 1) * pitch + face
  { pagePitch := pitch, fontSize := face, capacity := cap, maxCapacity := cap, separator := pitch,
    columns := 1, firstLine := 0, pitchOf := fun _ => pitch, faceOf := fun _ => face,
    headingBounds := fun _ => none, wrappedBefore := fun _ => 0, boxPadding := fun _ => none,
    firstNeed := firstNeed pitch cap, retention := none, held := fun _ => false }

/-- The exclusion length and width of the figure of `w` zw. -/
def extent (w : Nat) : Int := (w : Int) * zw * 3 / 2 + zw
def exclusionWidth (w : Nat) : Int := (w : Int) * zw + zw

/-- `rowExtent` and `intersects` of FreeGeometry.hs. -/
def rowExtent (start : Int) : Int × Int :=
  let a := pitch / 2 - face / 2
  (start + min 0 a, start + max pitch (a + face))

def intersects (x y : Int × Int) : Bool := decide (max x.1 y.1 < min x.2 y.2)

/-- `physicalParagraphOrigin`. -/
def paragraphOrigin (st : St) : Int := st.used + if empty st then 0 else st.pending

/-- Whether the row `k` of a paragraph composed at `at` is narrowed by the
    exclusion from `origin` (`narrowed` of `composeAt`). -/
def narrowed (region : Region) (origin : Int) (at' : St) (k : Nat) : Bool :=
  match region with
  | some (p, c, e) => p == at'.page && c == at'.column && intersects (rowExtent (paragraphOrigin at' + (k : Int) * pitch)) (origin, e)
  | none => false

/-- The text placed, the lines and the wrapped figures in these
    manuscripts, which have no headings and no code: the id of the next one
    (`bUnitFirsts` numbers the lines and the figures in order from 0). -/
def slotCount (st : St) : Nat := (text st).length

/-- The ids of the slots placed. -/
def placedIds (st : St) : List Nat :=
  ((st.done.reverse.map (·.slots)).join ++ st.slots).bind (fun s => slotIds s.2)

/-- `composeAt` and `numberedLines` for the fake fonts: the lines of the
    characters from `start` to `n`, `measure` characters to a line where
    the row does not meet the exclusion, each with the character after its
    break. -/
def breakLines (w measure : Nat) (region : Region) (origin : Int) (at' : St) (start n : Nat) : List (Line × Nat) :=
  let first := slotCount at'
  let rec go : Nat → Nat → Nat → List (Line × Nat)
    | 0, _, _ => []
    | fuel + 1, k, from' =>
      if n ≤ from' then []
      else
        let width := (measure : Int) * zw - (if narrowed region origin at' k then exclusionWidth w else 0)
        let next := min n (from' + (width / zw).toNat)
        (⟨first + k, [], 0⟩, next) :: go fuel (k + 1) next
  go (n + 1) 0 start

/-- A paragraph of so many characters, a no-break, a stanza of verse lines
    of so many characters each, or a list item of a paragraph of so many
    characters followed by wrapped figures, each with the paragraphs of the
    item after it.  `q` and `h` are the paragraph and the stanza that keep
    with the next 3 lines.  `j` is a list item like `i` followed by a nested
    list item of a paragraph of so many characters, which is not set beside
    the figures of its outer item. -/
inductive Item where
  | p (n : Nat)
  | k
  | v (ns : List Nat)
  | i (first : Nat) (figures : List (List Nat))
  | q (n : Nat)
  | h (ns : List Nat)
  | j (first : Nat) (figures : List (List Nat)) (sub : Nat)

def Item.name : Item → String
  | .p n => toString n
  | .k => "K"
  | .v ns => "V" ++ ",".intercalate (ns.map toString)
  | .i n fs => "I" ++ toString n ++ String.join (fs.map fun ps => "/" ++ ",".intercalate (ps.map toString))
  | .q n => "Q" ++ toString n
  | .h ns => "H" ++ ",".intercalate (ns.map toString)
  | .j n fs sub => "J" ++ toString n ++ String.join (fs.map fun ps => "/" ++ ",".intercalate (ps.map toString)) ++
    "-" ++ toString sub

/-- A unit of golem-typeset: a paragraph (of the list item `item`, if any),
    a no-break, a verse line of the stanza `s` (each verse line of a stanza
    is a unit of its own), a wrapped figure, or a paragraph of a list item
    nested in the list item `item`. -/
inductive Unit' where
  | para (item : Option Nat) (n : Nat)
  | ctrl
  | verse (s n : Nat)
  | fig (item : Option Nat)
  | sub (item n : Nat)

/-- The units of the items after a wrapped figure, if `lead`; the stanzas
    and the list items are numbered by their position. -/
def units (lead : Bool) (items : List Item) : List Unit' :=
  (if lead then [Unit'.fig none] else []) ++
  (items.enum.map fun (s, i) => match i with
    | .p n | .q n => [Unit'.para none n]
    | .k => [Unit'.ctrl]
    | .v ns | .h ns => ns.map (Unit'.verse s)
    | .i n fs => Unit'.para (some s) n :: fs.bind fun ps => Unit'.fig (some s) :: ps.map (Unit'.para (some s))
    | .j n fs sub =>
      Unit'.para (some s) n :: (fs.bind fun ps => Unit'.fig (some s) :: ps.map (Unit'.para (some s))) ++ [Unit'.sub s sub]).join

/-- The lines each unit of `units` keeps with what follows by its style
    (`keep-with-next`). -/
def wants (lead : Bool) (items : List Item) : List Nat :=
  (if lead then [0] else []) ++
  (items.map fun i => match i with
    | .q _ => [3]
    | .h ns => ns.map fun _ => 3
    | .v ns => ns.map fun _ => 0
    | .i _ fs => 0 :: fs.bind fun ps => 0 :: ps.map fun _ => 0
    | .j _ fs _ => 0 :: (fs.bind fun ps => 0 :: ps.map fun _ => 0) ++ [0]
    | _ => [0]).join

/-- A manuscript: the width of its figures in zw, the unit a list item is
    kept in (`keep-parts`; a list item is retained when it is a page or a
    spread), its units, and the lines each keeps with what follows by its
    style. -/
structure Ms where
  w : Nat
  part : PartUnit
  us : List Unit'
  wanted : List Nat

def Ms.at (m : Ms) (i : Nat) : Option Unit' := m.us.get? i

def Ms.retaining (m : Ms) : Bool := m.part != .column

/-- The lines the unit `i` keeps with what follows by its style. -/
def wantOf (m : Ms) (i : Nat) : Nat := (m.wanted.get? i).getD 0

def chars (m : Ms) (i : Nat) : Nat :=
  match m.at i with
  | some (.para _ n) => n
  | some (.verse _ n) => n
  | some (.sub _ n) => n
  | _ => 0

def itemAt (m : Ms) (i : Nat) : Option Nat :=
  match m.at i with
  | some (.para k _) => k
  | some (.fig k) => k
  | some (.sub k _) => some k
  | _ => none

/-- The characters of a line: a list item is indented by 2zw, a nested
    one by 4zw. -/
def measure (m : Ms) (i : Nat) : Nat :=
  match m.at i with
  | some (.sub _ _) => 8
  | _ => if (itemAt m i).isSome then 10 else 12

def stanzaOf (m : Ms) (i : Nat) : Option Nat :=
  match m.at i with
  | some (.verse s _) => some s
  | _ => none

def isVerse (m : Ms) (i : Nat) : Bool := (stanzaOf m i).isSome

def isFig (m : Ms) (i : Nat) : Bool :=
  match m.at i with
  | some (.fig _) => true
  | _ => false

def indices (m : Ms) : List Nat := List.range m.us.length

/-- The no-breaks between the positions `prior` and `index`
    (`controlsBetween`). -/
def controlsBetween (m : Ms) (prior index : Nat) : List Flow :=
  (indices m).filterMap fun j =>
    if prior < j ∧ j < index then
      match m.at j with
      | some .ctrl => some .noBreak
      | _ => none
    else none

/-- The no-breaks right after the position `index` (`bindingAfter`). -/
def controlsAfter (m : Ms) (index : Nat) : List Flow :=
  ((m.us.drop (index + 1)).takeWhile (fun i => match i with | .ctrl => true | _ => false)).map (fun _ => .noBreak)

/-- `bindingAfter` for a paragraph or a verse line: the no-breaks after it
    and the lines its style keeps with what follows. -/
def binding (m : Ms) (index : Nat) : Nat × Nat :=
  match keepAhead (controlsAfter m index) with
  | none => (0, wantOf m index)
  | some (l, f, _) => (l, max f (wantOf m index))

/-- `keepPhysicalNext`: the wait for the lines asked of what follows. -/
def holdNext (required : Nat) (linesOnly : Bool) (st : St) : St :=
  waitForPrior (.keepNext 0) (max 1 required, linesOnly) st

/-- The paragraphs beside the figure `job` (`composeBeside` and
    `besideParagraphs`): the paragraphs and verse lines after it, past
    no-breaks, of its list item when one is kept on a page or a spread. -/
def besides (m : Ms) (job : Nat) : List Nat :=
  let rec go : Nat → Nat → List Nat
    | 0, _ => []
    | fuel + 1, j =>
      match m.at j with
      | some (.para k _) => if !m.retaining || k == itemAt m job then j :: go fuel (j + 1) else []
      | some (.verse _ _) => if !m.retaining || none == itemAt m job then j :: go fuel (j + 1) else []
      | some (.sub _ _) => if !m.retaining then j :: go fuel (j + 1) else []
      | some .ctrl => go fuel (j + 1)
      | _ => []
  go m.us.length (job + 1)

/-- The last position the figure `job` and its paragraphs take. -/
def coveredEnd (m : Ms) (job : Nat) : Nat := ((besides m job).getLast?).getD job

def inner : Inner := level 1

/-- The settings of these manuscripts meet the premises of
    `tryVerses_column_check_unobservable`: `tryVerses` gives the same
    trials with or without its same-column check. -/
theorem tryVerses_column_check_here (lines : Nat) (region : Region) (b : Beside) (cursor : St) (indices : List Nat) :
    tryVersesAnyColumn (env lines) region b cursor indices = tryVerses (env lines) region b cursor indices :=
  tryVerses_column_check_unobservable (env lines) (by simp [env, pitch]) (by simp [env, pitch]) region b cursor indices

/-- `stepPhysicalPrefix`: the prefix placed with the following flows ahead. -/
def stepPrefix (e : Env) (st : St) (following : List Flow) : List Flow → Except Failure St
  | [] => .ok st
  | f :: rest =>
    match placeNext inner e st f (rest ++ following) with
    | .error x => .error x
    | .ok s => stepPrefix e s following rest

/-- The flows of the positions, not beside a figure: a paragraph composed
    at its measure, its lines numbered from `first`. -/
def flowsOf (m : Ms) (first : Nat) : List Nat → List Flow
  | [] => []
  | i :: rest =>
    match m.at i with
    | some (.para _ n) | some (.sub _ n) =>
      let rows : List Line := (List.range ((n + measure m i - 1) / measure m i)).map fun k => ⟨first + k, [], 0⟩
      .paragraph defaultKeep rows :: flowsOf m (first + rows.length) rest
    | some .ctrl => .noBreak :: flowsOf m first rest
    | _ => flowsOf m first rest

/-- The positions from `low` to `high`, both included, outside the list
    item `done`. -/
def span (m : Ms) (low high : Nat) (done : Option Nat) : List Nat :=
  (indices m).filter fun j => low ≤ j ∧ j ≤ high ∧ !(done.isSome && itemAt m j == done)

/-- `stepPhysicalCursor` of the positions. -/
def stepAt (e : Env) (m : Ms) (at' : St) (ps : List Nat) : Except Failure St :=
  placeAll inner e at' (flowsOf m (slotCount at') ps)

def beside (m : Ms) (region : Region) (origin : Int) : Beside :=
  { compose := fun at' i => (breakLines m.w (measure m i) region origin at' 0 (chars m i)).map (·.1),
    binding := binding m, keepOf := fun _ => defaultKeep, holds := fun i => 0 < wantOf m i,
    hold := fun _ required linesOnly st => holdNext required linesOnly st, ident := fun at' _ => slotCount at', isStanza := isVerse m,
    sameVerse := fun i j => isVerse m j && stanzaOf m i == stanzaOf m j }

/-- The number of rows of `n` characters as `composeBeside` composes them
    before the trials: the row `k` of a unit at `distance` from the top of
    the figure is narrowed where it meets the exclusion from 0. -/
def besideRows (w measure n : Nat) (distance : Int) : Nat :=
  let rec go : Nat → Nat → Nat → Nat
    | 0, _, _ => 0
    | fuel + 1, k, from' =>
      if n ≤ from' then 0
      else
        let narrow := intersects (rowExtent (distance + (k : Int) * pitch)) (0, extent w)
        let width := (measure : Int) * zw - (if narrow then exclusionWidth w else 0)
        go fuel (k + 1) (min n (from' + (width / zw).toNat)) + 1
  go (n + 1) 0 0

/-- The distance from the top of the figure `job` of the paragraph `i`
    beside it: the rows of the paragraphs before `i`, each composed at the
    distance of those before it. -/
def besideDistance (m : Ms) (job i : Nat) : Int :=
  ((besides m job).filter (· < i)).foldl (fun d j => d + (besideRows m.w (measure m j) (chars m j) d : Int) * pitch) 0

/-- The rows of a verse line as composed before it is tried
    (`composeBeside`); only their number is read. -/
def orig (m : Ms) (job i : Nat) : List Line :=
  (List.range (besideRows m.w (measure m i) (chars m i) (besideDistance m job i))).map fun _ => ⟨0, [], 0⟩

/-- The rows of the first `n` verse lines: those `tryVerses` placed as
    composed at the cursor before each, the others as composed before. -/
def verseRowCount (m : Ms) (job : Nat) (region : Region) (origin : Int) (ready : St) (verses : List Nat)
    (trials : List St) (n : Nat) : Nat :=
  ((List.range n).map fun k =>
    match verses.get? k, (ready :: trials).get? k with
    | some i, some at' => if k < trials.length then ((beside m region origin).compose at' i).length else (orig m job i).length
    | some i, none => (orig m job i).length
    | none, _ => 0).foldl (· + ·) 0

/-- What follows the paragraphs beside the figure: no flows. -/
def probe (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) : Probe :=
  { prefixAt := fun i j at' => placeAll inner e at' (controlsBetween m i j),
    following := fun at' wanted =>
      let (required, linesOnly) := followingRows wanted []
      (required, linesOnly, fitsFollowing inner e at' wanted []),
    required := fun wanted keep rows => (followingRows wanted [.paragraph keep rows]).1,
    verseRequired := verseRowCount m job region origin }

/-- `paragraph` of the paragraph or verse line `index` with the keep `k`
    and the binding `(lastWanted, wanted)`. -/
def paragraphAt (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (index : Nat)
    (later : List Nat) (k : Keep) (lastWanted wanted : Nat) (at' : St) : Except Failure St :=
  let probed := fun st =>
    if 0 < wanted ∨ 0 < lastWanted then
      match probeNext e region (beside m region origin) (probe e m job region origin) index later st wanted with
      | .ok r => r
      | .error _ => (0, true, false)
    else (0, true, true)
  let hold := fun st => if 0 < wantOf m index then holdNext (probed st).1 (probed st).2.1 st else st
  parts e region (fun at'' _ start => breakLines m.w (measure m index) region origin at'' start (chars m index))
    (chars m index) lastWanted (fun st => (probed st).2.2) hold none k true 0 0 at'

def paras (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) : Paras :=
  { preliminary := fun prior index at' => placeAll inner e at' (controlsBetween m prior index),
    ready := fun prior index at' rows =>
      let ahead := if isVerse m index then [.stanza defaultKeep rows] else rows.map (.paragraph defaultKeep ·)
      stepPrefix e at' ahead (controlsBetween m prior index),
    orig := orig m job,
    paragraph := fun index later at' =>
      let (lastWanted, wanted) := binding m index
      paragraphAt e m job region origin index later defaultKeep lastWanted wanted at' }

/-- `probeNext` after the last verse line, and the fallback of a verse line
    by its display rows: `paragraph` with the default keep and no binding. -/
def stanzaArgs (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) : StanzaArgs :=
  { follows := fun i later at' wanted =>
      probeNext e region (beside m region origin) (probe e m job region origin) i later at' wanted,
    fallback := fun i later at' => paragraphAt e m job region origin i later defaultKeep 0 0 at' }

/-- The first position after the figure `prior` and its paragraphs. -/
def after (m : Ms) (prior : Option Nat) : Nat := (prior.map (coveredEnd m · + 1)).getD 0

/-- The first position of the list item of `job`, or `job`. -/
def itemStart (m : Ms) (job : Nat) : Nat :=
  match itemAt m job with
  | some k => ((indices m).find? fun j => itemAt m j == some k).getD job
  | none => job

/-- The flows before the figure `job` in its item, or since the figure
    `prior`. -/
def prefixFlows (m : Ms) (prior : Option Nat) (job : Nat) (at' : St) : List Flow :=
  let low :=
    if !m.retaining then after m prior
    else if prior.isSome || (itemAt m job).isSome then max (after m prior) (itemStart m job) else 0
  flowsOf m (slotCount at') (span m low (job - 1) none |>.filter (· < job))

/-- The id of the figure `job`: the lines and figures placed before it. -/
def wrapIdent (m : Ms) (prior : Option Nat) (job : Nat) (at' : St) : Nat :=
  slotCount at' + ((prefixFlows m prior job at').map fun f => match f with | .paragraph _ ls => ls.length | _ => 0).foldl (· + ·) 0

/-- `runJob`: the flows before the figure `job` (`prefixFlows`), the
    figure (`beginPhysicalWrapAfter`, its id the lines and figures before
    it), and the paragraphs beside it. -/
def runJob (e : Env) (m : Ms) (prior : Option Nat) (job : Nat) (at' : St) : Except Failure St :=
  let prefixFlows := prefixFlows m prior job at'
  let ident := wrapIdent m prior job at'
  match stepPrefix e at' [.wrapped ident (extent m.w) []] prefixFlows with
  | .error f => .error f
  | .ok ready =>
    match beginWrap e ready ident (extent m.w) with
    | .error f => .error f
    | .ok (anchored, region) =>
      let origin := (region.map (·.2.2)).getD 0 - extent m.w
      let positions := (besides m job).filter (fun i => 0 < chars m i)
      match paragraphs e region (beside m region origin) (stanzaArgs e m job region origin)
          (paras e m job region origin) job anchored positions with
      | .error f => .error f
      | .ok placed => .ok (endWrap region placed)

/-- `retainPhysicalPart` of `keep-parts = "page"` or `"spread"` (`u`), the
    ids of the part those of the slots the trial placed. -/
def retainPart (e : Env) (u : PartUnit) {α : Type} (trial : St → Except Failure (α × St)) (at' : St) :
    Except Failure (α × St) :=
  let attempt : St → Except Failure (α × List Nat × St) := fun s =>
    match trial s with
    | .error f => .error f
    | .ok (a, placed) =>
      let ids := (placedIds placed).filter (fun i => !(placedIds s).contains i)
      .ok (a, ids, settle e ids placed)
  match attempt at' with
  | .error f => .error f
  | .ok (a, ids, ordinary) =>
    if partFits u at' ids ordinary (unitKey u at'.page at'.column) then .ok (a, ordinary)
    else
      let moved := nextUnit e u at'
      match attempt moved with
      | .error f => .error f
      | .ok (b, ids', m) =>
        if partFits u at' ids' m (unitKey u moved.page moved.column) then .ok (b, m)
        else if emptyUnit u at' then .ok (a, addUnmet (Unmet.splitPart false u) ordinary)
        else .ok (b, addUnmet (Unmet.splitPart false u) m)

/-- The loop over the figures of the manuscript (`jobsFrom`). -/
def jobs (e : Env) (m : Ms) : Jobs :=
  { itemOf := fun job => if m.retaining then itemAt m job else none,
    outside := fun prior done job at' => stepAt e m at' (span m (after m prior) (itemStart m job - 1) done |>.filter (· < itemStart m job)),
    run := fun prior _ job at' => runJob e m prior job at',
    itemRest := fun key prior at' => stepAt e m at' ((span m (after m (some prior)) m.us.length none).filter (fun j => itemAt m j == some key)),
    finish := fun prior done at' => stepAt e m at' (span m (after m prior) m.us.length done),
    retain := fun trial at' => if m.retaining then retainPart e m.part trial at' else trial at' }

/-! ### The premises of `I5_jobsFrom_lines` on these manuscripts

`outside`, `itemRest` and `finish` place the lines of their positions, as
`FParagraph`s numbered from the lines and figures placed before them
(`stepAt_lines`), and `retainPart` returns one run of its trial
(`retainPart_retains`).  `runJob` places the lines of the flows before
the figure, the figure and then lines numbered on from it (`runLines`,
`runJob_lines`): a line or a wrapped figure has the id of the text placed
before it (`slotCount`), so the lines `parts`, `stanza` and `paragraphs`
add are numbered on from the text at their cursor (`I5_paragraphs_counts`).
`check.sh` still checks `runLines` at each run in the manuscripts
(`premiseFailures`), as a guard on the copies. -/

theorem flowsOf_figs (m : Ms) (first : Nat) (ps : List Nat) : sourceFigs (flowsOf m first ps) = [] := by
  induction ps generalizing first with
  | nil => rfl
  | cons i rest ih => unfold flowsOf; split <;> simp [sourceFigs, flowFigs, ih]

theorem stepAt_lines (e : Env) (m : Ms) (c s : St) (ps : List Nat) (h : stepAt e m c ps = .ok s) :
    Step c s (sourceText (flowsOf m (slotCount c) ps)) [] := by
  have := step_placeAll inner (level_ok 1) e c _ s h
  rwa [flowsOf_figs] at this

theorem retainPart_retains (e : Env) (u : PartUnit) {α : Type} (trial : St → Except Failure (α × St)) (at' : St)
    (r : α × St) (h : retainPart e u trial at' = .ok r) :
    ∃ s r', trial s = .ok r' ∧ r'.1 = r.1 ∧ Step at' s [] [] ∧ Step r'.2 r.2 [] [] := by
  unfold retainPart at h
  dsimp only at h
  cases ht : trial at' with
  | error f => rw [ht] at h; cases h
  | ok p =>
    obtain ⟨a, placed⟩ := p
    rw [ht] at h
    dsimp only at h
    split at h
    · injection h with h; subst h; exact ⟨at', (a, placed), ht, rfl, Step.refl _, step_settle _ _ _⟩
    · cases hm : trial (nextUnit e u at') with
      | error f => rw [hm] at h; cases h
      | ok q =>
        obtain ⟨b, placed'⟩ := q
        rw [hm] at h
        dsimp only at h
        split at h
        · injection h with h; subst h
          exact ⟨nextUnit e u at', (b, placed'), hm, rfl, step_nextUnit _ _ _, step_settle _ _ _⟩
        · split at h
          · injection h with h; subst h
            exact ⟨at', (a, placed), ht, rfl, Step.refl _, by simpa using (step_settle e _ placed).trans (step_addUnmet _ _)⟩
          · injection h with h; subst h
            exact ⟨nextUnit e u at', (b, placed'), hm, rfl, step_nextUnit _ _ _,
              by simpa using (step_settle e _ placed').trans (step_addUnmet _ _)⟩

/-- The lines `runJob` places at `c`: those of the flows before the figure,
    the figure, and lines numbered on from the figure, each once and in
    order. -/
def runLines (m : Ms) (prior : Option Nat) (job : Nat) (c : St) (ls : List Nat) : Bool :=
  let pre := sourceText (prefixFlows m prior job c) ++ [wrapIdent m prior job c]
  ls.take pre.length == pre && ls.drop pre.length == ids (wrapIdent m prior job c + 1) (ls.length - pre.length)

theorem breakLines_go_ids (w measure : Nat) (region : Region) (origin : Int) (at' : St) (n first : Nat) :
    ∀ fuel k from', lineIds ((breakLines.go w measure region origin at' n first fuel k from').map (·.1)) =
      ids (first + k) (breakLines.go w measure region origin at' n first fuel k from').length
  | 0, _, _ => rfl
  | fuel + 1, k, from' => by
    have ih := fun k f => breakLines_go_ids w measure region origin at' n first fuel k f
    unfold breakLines.go
    split
    · rfl
    · simp only [lineIds] at ih ⊢
      simp only [Nat.add_eq, Nat.add_zero]
      simp only [List.map, List.length_cons, ih, ids, Nat.add_assoc]
      rfl

/-- The lines `breakLines` composes at a cursor are numbered on from the
    text placed there. -/
theorem breakLines_ids (w measure : Nat) (region : Region) (origin : Int) (at' : St) (start n : Nat) :
    lineIds ((breakLines w measure region origin at' start n).map (·.1)) =
      ids (text at').length (breakLines w measure region origin at' start n).length := by
  have := breakLines_go_ids w measure region origin at' n (slotCount at') (n + 1) 0 start
  simpa [breakLines] using this

theorem range_length : ∀ n, (List.range n).length = n
  | 0 => rfl
  | n + 1 => by rw [range_succ', List.length_append, range_length n]; rfl

theorem rows_ids (first : Nat) : ∀ n,
    lineIds ((List.range n).map fun k => (⟨first + k, [], 0⟩ : Line)) = ids first n
  | 0 => rfl
  | n + 1 => by
    rw [range_succ', List.map_append, lineIds_append, rows_ids first n, ← ids_append]
    rfl

def flowLength : Flow → Nat
  | .paragraph _ ls => ls.length
  | _ => 0

theorem para_text (m : Ms) (first N : Nat) (rest : List Nat)
    (ih : ∀ f, sourceText (flowsOf m f rest) = ids f (sourceText (flowsOf m f rest)).length) :
    sourceText (.paragraph defaultKeep ((List.range N).map fun k => (⟨first + k, [], 0⟩ : Line)) ::
        flowsOf m (first + ((List.range N).map fun k => (⟨first + k, [], 0⟩ : Line)).length) rest) =
      ids first (sourceText (.paragraph defaultKeep ((List.range N).map fun k => (⟨first + k, [], 0⟩ : Line)) ::
        flowsOf m (first + ((List.range N).map fun k => (⟨first + k, [], 0⟩ : Line)).length) rest)).length := by
  simp only [sourceText, flowText, rows_ids, List.length_map, range_length, List.length_append, ids_length]
  have := ih (first + N)
  generalize sourceText (flowsOf m (first + N) rest) = t at this ⊢
  have e : ids first N ++ t = ids first N ++ ids (first + N) t.length := congrArg _ this
  rw [e, ids_append]

theorem para_length (m : Ms) (first N acc : Nat) (rest : List Nat)
    (ih : ∀ f acc, ((flowsOf m f rest).map flowLength).foldl (· + ·) acc = acc + (sourceText (flowsOf m f rest)).length) :
    ((Flow.paragraph defaultKeep ((List.range N).map fun k => (⟨first + k, [], 0⟩ : Line)) ::
        flowsOf m (first + ((List.range N).map fun k => (⟨first + k, [], 0⟩ : Line)).length) rest).map flowLength).foldl
        (· + ·) acc =
      acc + (sourceText (.paragraph defaultKeep ((List.range N).map fun k => (⟨first + k, [], 0⟩ : Line)) ::
        flowsOf m (first + ((List.range N).map fun k => (⟨first + k, [], 0⟩ : Line)).length) rest)).length := by
  simp only [List.map, List.foldl, flowLength, sourceText, flowText, rows_ids, List.length_map, range_length,
    List.length_append, ids_length]
  rw [ih]; omega

/-- The flows of the positions place the lines numbered from `first` on. -/
theorem flowsOf_text (m : Ms) : ∀ (first : Nat) (ps : List Nat),
    sourceText (flowsOf m first ps) = ids first (sourceText (flowsOf m first ps)).length
  | _, [] => rfl
  | first, i :: rest => by
    unfold flowsOf
    split
    · exact para_text m first _ rest (fun f => flowsOf_text m f rest)
    · exact para_text m first _ rest (fun f => flowsOf_text m f rest)
    · simp only [sourceText, flowText, List.nil_append]; exact flowsOf_text m first rest
    · exact flowsOf_text m first rest

/-- The lines of the paragraphs of the flows of the positions are those
    they place. -/
theorem flowsOf_length (m : Ms) : ∀ (first : Nat) (ps : List Nat) (acc : Nat),
    ((flowsOf m first ps).map flowLength).foldl (· + ·) acc = acc + (sourceText (flowsOf m first ps)).length
  | _, [], acc => rfl
  | first, i :: rest, acc => by
    unfold flowsOf
    split
    · exact para_length m first _ acc rest (fun f acc => flowsOf_length m f rest acc)
    · exact para_length m first _ acc rest (fun f acc => flowsOf_length m f rest acc)
    · simp only [List.map, List.foldl, flowLength, sourceText, flowText, List.nil_append, Nat.add_zero]
      exact flowsOf_length m first rest acc
    · exact flowsOf_length m first rest acc

theorem noBreaks_text : ∀ (l : List Flow), (∀ f ∈ l, f = .noBreak) → sourceText l = [] ∧ sourceFigs l = []
  | [], _ => ⟨rfl, rfl⟩
  | f :: fs, h => by
    have e := h f (List.mem_cons_self _ _)
    subst e
    have := noBreaks_text fs (fun g hg => h g (List.mem_cons_of_mem _ hg))
    simp only [sourceText, sourceFigs, flowText, flowFigs, List.nil_append, this, and_self]

theorem filterMap_noBreaks (g : Nat → Option Flow) (hg : ∀ a x, g a = some x → x = .noBreak) :
    ∀ (l : List Nat) (f : Flow), f ∈ l.filterMap g → f = .noBreak
  | [], _, h => by cases h
  | a :: l, f, h => by
    simp only [List.filterMap] at h
    split at h
    · exact filterMap_noBreaks g hg l f h
    · rename_i x e
      cases h with
      | head => exact hg a f e
      | tail _ h => exact filterMap_noBreaks g hg l f h

theorem controlsBetween_text (m : Ms) (prior index : Nat) :
    sourceText (controlsBetween m prior index) = [] ∧ sourceFigs (controlsBetween m prior index) = [] := by
  apply noBreaks_text
  apply filterMap_noBreaks
  intro j x e
  split at e
  · split at e
    · injection e with e; exact e.symm
    · cases e
  · cases e

theorem step_stepPrefix (e : Env) (following : List Flow) :
    ∀ (flows : List Flow) (st s : St), stepPrefix e st following flows = .ok s →
    Step st s (sourceText flows) (sourceFigs flows)
  | [], st, s, h => by simp only [stepPrefix, Except.ok.injEq] at h; subst h; exact Step.refl _
  | f :: rest, st, s, h => by
    simp only [stepPrefix] at h
    split at h
    · cases h
    · rename_i s1 e1
      have := (step_placeNext inner (level_ok 1) e st f _ s1 e1).trans (step_stepPrefix e following rest s1 s h)
      simpa [sourceText, sourceFigs] using this

theorem step_beginWrap (e : Env) (st : St) (ident : Nat) (extent : Int) (r : St × Region)
    (h : beginWrap e st ident extent = .ok r) : Step st r.1 [ident] [] := by
  unfold beginWrap at h
  split at h
  · cases h
  · injection h with h; subst h
    simpa using ((step_fit e st extent).trans (step_putWrappedSlot _ ident)).trans (step_checkWaits _)

theorem step_holdNext (required : Nat) (linesOnly : Bool) (st : St) : Step st (holdNext required linesOnly st) [] [] :=
  step_waitForPrior _ _ st

theorem compose_ids (m : Ms) (region : Region) (origin : Int) (c : St) (i : Nat) :
    lineIds ((beside m region origin).compose c i) = ids (text c).length ((beside m region origin).compose c i).length := by
  simp only [beside]
  rw [breakLines_ids, List.length_map]

/-- `paragraph` and the fallback of a verse line add lines numbered on
    from the text at their cursor. -/
theorem paragraphAt_counts (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (index : Nat)
    (later : List Nat) (k : Keep) (lastWanted wanted : Nat) (c s : St)
    (h : paragraphAt e m job region origin index later k lastWanted wanted c = .ok s) : Counts c s := by
  unfold paragraphAt at h
  refine parts_counts _ _ _ _ _ _ _ (fun a _ t => breakLines_ids _ _ _ _ a t _) (fun st => ?_) _ _ _ _ _ _ _ h
  dsimp only
  split
  · exact step_holdNext _ _ st
  · exact Step.refl st

/-- The paragraphs beside a figure add lines numbered on from the text at
    their cursor. -/
theorem paragraphs_counts_here (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (prior : Nat)
    (c s : St) (positions : List Nat)
    (h : paragraphs e region (beside m region origin) (stanzaArgs e m job region origin) (paras e m job region origin)
      prior c positions = .ok s) : Counts c s := by
  refine I5_paragraphs_counts e region (beside m region origin) (stanzaArgs e m job region origin)
    (paras e m job region origin) (compose_ids m region origin)
    (fun i later c s h => paragraphAt_counts e m job region origin i later defaultKeep 0 0 c s h)
    (fun _ _ _ st => step_holdNext _ _ st) (fun prior index c rows s h => ?_)
    (fun index later c s h => by
      simp only [paras] at h
      exact paragraphAt_counts e m job region origin index later _ _ _ c s h) prior c positions s h
  have := step_stepPrefix e _ _ c s h
  rw [(controlsBetween_text m prior index).1, (controlsBetween_text m prior index).2] at this
  exact Counts.ofStep this

theorem take_drop_app (a x : List Nat) : (a ++ x).take a.length = a ∧ (a ++ x).drop a.length = x := by
  induction a with
  | nil => simp
  | cons y ys ih => simp [ih.1, ih.2]

/-- `runJob` places the lines of the flows before the figure, the figure,
    and lines numbered on from the figure (`runLines`). -/
theorem runJob_lines (e : Env) (m : Ms) (prior : Option Nat) (job : Nat) (c s : St)
    (h : runJob e m prior job c = .ok s) : ∃ ls, runLines m prior job c ls = true ∧ Step c s ls [] := by
  unfold runJob at h
  dsimp only at h
  split at h
  · cases h
  · rename_i ready hready
    split at h
    · cases h
    · rename_i anchored region hbw
      split at h
      · cases h
      · rename_i placed hpl
        injection h with h; subst h
        have s1 := step_stepPrefix e _ _ c ready hready
        rw [show sourceFigs (prefixFlows m prior job c) = [] from flowsOf_figs _ _ _] at s1
        have s2 := step_beginWrap e ready _ _ _ hbw
        obtain ⟨n, s3⟩ := paragraphs_counts_here e m job region _ job anchored placed _ hpl
        have s4 := step_endWrap region placed
        have pre : sourceText (prefixFlows m prior job c) = ids (slotCount c) (sourceText (prefixFlows m prior job c)).length :=
          flowsOf_text m _ _
        have wi : wrapIdent m prior job c = slotCount c + (sourceText (prefixFlows m prior job c)).length := by
          unfold wrapIdent
          have := flowsOf_length m (slotCount c) (span m (if !m.retaining then after m prior
            else if prior.isSome || (itemAt m job).isSome then max (after m prior) (itemStart m job) else 0) (job - 1) none
              |>.filter (· < job)) 0
          simp only [prefixFlows] at this ⊢
          rw [show (fun f => match f with | .paragraph _ ls => ls.length | _ => 0) = flowLength from
            funext fun f => by cases f <;> rfl]
          omega
        have la : (text anchored).length = wrapIdent m prior job c + 1 := by
          rw [s2.1, s1.1, wi]; simp only [slotCount, List.length_append, List.length_cons, List.length_nil]
        rw [la] at s3
        refine ⟨sourceText (prefixFlows m prior job c) ++ [wrapIdent m prior job c] ++ ids (wrapIdent m prior job c + 1) n,
          ?_, by simpa using ((s1.trans s2).trans s3).trans s4⟩
        have hA := take_drop_app (sourceText (prefixFlows m prior job c) ++ [wrapIdent m prior job c])
          (ids (wrapIdent m prior job c + 1) n)
        have hl : ((sourceText (prefixFlows m prior job c) ++ [wrapIdent m prior job c]) ++
            ids (wrapIdent m prior job c + 1) n).length -
            (sourceText (prefixFlows m prior job c) ++ [wrapIdent m prior job c]).length = n := by
          simp only [List.length_append, ids_length]; omega
        simp only [runLines]
        rw [hA.1, hA.2, hl]
        simp

/-- What each piece of `jobsFrom` places on these manuscripts. -/
def piecePremise (m : Ms) : JobPiece → St → List Nat → Prop
  | .outside prior done job, c, ls =>
    ls = sourceText (flowsOf m (slotCount c) (span m (after m prior) (itemStart m job - 1) done |>.filter (· < itemStart m job)))
  | .run prior _ job, c, ls => runLines m prior job c ls = true
  | .rest key prior, c, ls =>
    ls = sourceText (flowsOf m (slotCount c) ((span m (after m (some prior)) m.us.length none).filter (fun j => itemAt m j == some key)))
  | .finish prior done, c, ls => ls = sourceText (flowsOf m (slotCount c) (span m (after m prior) m.us.length done))

/-- The premises of `I5_jobsFrom_lines` hold for these manuscripts. -/
theorem jobs_lines (e : Env) (m : Ms) : JobsLines (jobs e m) (piecePremise m) where
  outside := fun _ _ _ c s h => ⟨_, rfl, stepAt_lines e m c s _ h⟩
  run := fun prior _ job c s h => runJob_lines e m prior job c s h
  itemRest := fun _ _ c s h => ⟨_, rfl, stepAt_lines e m c s _ h⟩
  finish := fun _ _ c s h => ⟨_, rfl, stepAt_lines e m c s _ h⟩
  retain := by
    intro α trial at' r h
    simp only [jobs] at h
    split at h
    · exact retainPart_retains e m.part trial at' r h
    · exact ⟨at', r, h, rfl, Step.refl _, Step.refl _⟩

/-- On these manuscripts, `jobsFrom` places the lines of the positions
    outside the figures and of the runs of the figures, each piece once and
    in order. -/
theorem I5_causal_jobsFrom_lines (e : Env) (m : Ms) (s : St)
    (h : jobsFrom (jobs e m) none none (initial e) ((indices m).filter (isFig m)) = .ok s) :
    ∃ lss, PieceChain (piecePremise m) (initial e) (jobPieces (jobs e m) none none ((indices m).filter (isFig m))) lss s :=
  I5_jobsFrom_lines _ _ (jobs_lines e m) _ _ _ _ _ h

/-- `runJob`, failing where it does not place `runLines` and no figures;
    `runJob_lines` proves it never fails so, and check.sh keeps the check
    as a guard on the copies. -/
def runChecked (e : Env) (m : Ms) (prior : Option Nat) (job : Nat) (c : St) : Except Failure St :=
  match runJob e m prior job c with
  | .error f => .error f
  | .ok s =>
    if (text s).take (text c).length == text c && figs s == figs c &&
        runLines m prior job c ((text s).drop (text c).length) then .ok s
    else .error (.noProgress 1000000)

/-- The manuscripts where a run of `jobsFrom` does not place `runLines`. -/
def premiseFailures (m : Ms) (lines : Nat) : Bool :=
  let e := env lines
  match jobsFrom { jobs e m with run := fun prior _ job at' => runChecked e m prior job at' } none none (initial e)
      ((indices m).filter (isFig m)) with
  | .error (.noProgress 1000000) => true
  | _ => false

/-! ### The rows of the verse lines not tried

`paragraphs` steps the no-breaks before a stanza with the rows of its
verse lines ahead, and the verse lines `tryVerses` did not place keep the
rows composed before (`orig`).  On these manuscripts any rows in their
place give the same pages (`I5_paragraphs_orig`).  When `tryVerses` placed
the first part of the stanza, the no-breaks wait for the same lines
(`I5_noBreak_rows_orig`).  When it did not, at an empty cursor the
no-breaks mark themselves unmet without waiting, and at a cursor that is
not empty `stanza` places none of its lines in that column
(`I5_stanza_moves`); the waits of the no-breaks are then dead, and the
stanza gives the same result whatever lines they ask for
(`stanza_accept_sim`). -/

theorem breakLines_go_blind (w measure : Nat) (region : Region) (origin : Int) (at' : St) (n first : Nat)
    (ws : List Wait) : ∀ fuel k from', breakLines.go w measure region origin (setW at' ws) n first fuel k from' =
      breakLines.go w measure region origin at' n first fuel k from'
  | 0, _, _ => rfl
  | fuel + 1, k, from' => by
    unfold breakLines.go
    have hn : ∀ k, narrowed region origin (setW at' ws) k = narrowed region origin at' k := fun _ => rfl
    simp only [Nat.add_eq, Nat.add_zero, hn, breakLines_go_blind w measure region origin at' n first ws fuel]

theorem breakLines_blind (w measure : Nat) (region : Region) (origin : Int) (at' : St) (start n : Nat) (ws : List Wait) :
    breakLines w measure region origin (setW at' ws) start n = breakLines w measure region origin at' start n := by
  unfold breakLines
  rw [show slotCount (setW at' ws) = slotCount at' from rfl, breakLines_go_blind]

theorem beside_blind (m : Ms) (region : Region) (origin : Int) : (beside m region origin).blind := by
  intro st w i
  simp only [beside]
  rw [breakLines_blind]

theorem paragraphAt_sim (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (index : Nat)
    (later : List Nat) (k : Keep) (lastWanted wanted : Nat) (c : St) (w : List Wait) (h : Sim c (setW c w)) :
    paragraphAt e m job region origin index later k lastWanted wanted (setW c w) =
      paragraphAt e m job region origin index later k lastWanted wanted c := by
  unfold paragraphAt
  exact parts_sim _ _ _ _ _ _ _ (fun st ws _ t => breakLines_blind _ _ _ _ st t _ ws) _ _ _ _ _ c w h

/-- A no-break before a stanza: it waits for `R`, or marks itself unmet at
    an empty cursor. -/
def nbStep (R : Nat × Bool) (st : St) : St := waitForPrior .noBreak R { st with join := none }

def nbIter (R : Nat × Bool) : Nat → St → St
  | 0, st => st
  | n + 1, st => nbIter R n (nbStep R st)

theorem followingRows_noBreaks (following : List Flow) :
    ∀ (fs : List Flow), (∀ f ∈ fs, f = .noBreak) → followingRows 0 (fs ++ following) = followingRows 0 following
  | [], _ => rfl
  | f :: fs, h => by
    rw [h f (.head _)]
    exact followingRows_noBreaks following fs (fun g hg => h g (.tail _ hg))

theorem stepPrefix_noBreaks (e : Env) (following : List Flow) :
    ∀ (fs : List Flow) (st : St), (∀ f ∈ fs, f = .noBreak) →
    stepPrefix e st following fs = .ok (nbIter (followingRows 0 following) fs.length st)
  | [], _, _ => rfl
  | f :: fs, st, h => by
    have hf := h f (.head _)
    subst hf
    have hr := fun g hg => h g (.tail _ hg)
    simp only [stepPrefix, placeNext, placeBody, beforeOf, occupies]
    rw [followingRows_noBreaks following fs hr]
    simp only [show (false = true) = False from by decide, false_and, and_false, if_false]
    exact stepPrefix_noBreaks e following fs _ hr

theorem placeAll_noBreaks (e : Env) :
    ∀ (fs : List Flow) (st : St), (∀ f ∈ fs, f = .noBreak) → placeAll inner e st fs = .ok (nbIter (1, false) fs.length st)
  | [], _, _ => rfl
  | f :: fs, st, h => by
    have hf := h f (.head _)
    subst hf
    have hr := fun g hg => h g (.tail _ hg)
    have : followingRows 0 fs = (1, false) := by
      have := followingRows_noBreaks [] fs hr
      rw [List.append_nil] at this; rw [this]; rfl
    simp only [placeAll, placeNext, placeBody, beforeOf, occupies]
    rw [this]
    simp only [show (false = true) = False from by decide, false_and, and_false, if_false]
    exact placeAll_noBreaks e fs _ hr

theorem controls_noBreaks (m : Ms) (prior index : Nat) : ∀ f ∈ controlsBetween m prior index, f = .noBreak :=
  filterMap_noBreaks _ (by
    intro j x e
    split at e
    · split at e
      · injection e with e; exact e.symm
      · cases e
    · cases e) _

/-- A no-break keeps the column, the slots and the pages closed. -/
theorem nbStep_keeps (R : Nat × Bool) (st : St) :
    (nbStep R st).page = st.page ∧ (nbStep R st).column = st.column ∧ (nbStep R st).slots = st.slots ∧
    (nbStep R st).done = st.done ∧ (nbStep R st).notes = st.notes ∧ (nbStep R st).used = st.used ∧
    (nbStep R st).firstLine = st.firstLine ∧ (nbStep R st).deferred = st.deferred := by
  unfold nbStep waitForPrior; split <;> exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem nbIter_keeps (R : Nat × Bool) : ∀ (n : Nat) (st : St),
    (nbIter R n st).page = st.page ∧ (nbIter R n st).column = st.column ∧ (nbIter R n st).slots = st.slots ∧
    (nbIter R n st).done = st.done ∧ (nbIter R n st).notes = st.notes ∧ (nbIter R n st).used = st.used ∧
    (nbIter R n st).firstLine = st.firstLine ∧ (nbIter R n st).deferred = st.deferred
  | 0, _ => ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  | n + 1, st => by
    obtain ⟨a1, a2, a3, a4, a5, a6, a7, a8⟩ := nbIter_keeps R n (nbStep R st)
    obtain ⟨b1, b2, b3, b4, b5, b6, b7, b8⟩ := nbStep_keeps R st
    exact ⟨a1.trans b1, a2.trans b2, a3.trans b3, a4.trans b4, a5.trans b5, a6.trans b6, a7.trans b7, a8.trans b8⟩

theorem nbIter_empty (R : Nat × Bool) (n : Nat) (st : St) : empty (nbIter R n st) = empty st := by
  obtain ⟨_, _, a3, _, a5, a6, a7, _⟩ := nbIter_keeps R n st
  simp only [empty, a3, a5, a6, a7]

/-- At an empty cursor, or one with figures sent on, the no-breaks wait
    for nothing. -/
theorem nbIter_unmet (R R' : Nat × Bool) : ∀ (n : Nat) (st : St), (empty st = true ∨ st.deferred ≠ []) →
    nbIter R n st = nbIter R' n st
  | 0, _, _ => rfl
  | n + 1, st, h => by
    have e : nbStep R st = nbStep R' st := by
      unfold nbStep waitForPrior
      rw [if_pos (by simpa [empty] using h), if_pos (by simpa [empty] using h)]
    simp only [nbIter]
    rw [e]
    apply nbIter_unmet R R' n
    obtain ⟨_, _, a3, _, a5, a6, a7, a8⟩ := nbStep_keeps R' st
    simpa [empty, a3, a5, a6, a7, a8] using h

/-- The no-breaks with two counts give states that differ only in their
    waits. -/
theorem nbStep_setW (R R' : Nat × Bool) (st : St) (w : List Wait) : ∃ w', nbStep R' (setW st w) = setW (nbStep R st) w' := by
  have e : nbStep R' (setW st w) = waitForPrior .noBreak R' (setW { st with join := none } w) := rfl
  rw [e]
  unfold nbStep waitForPrior
  simp only [empty_setW, setW_deferred]
  split
  · exact ⟨w, rfl⟩
  · exact ⟨_, rfl⟩

theorem nbIter_setW (R R' : Nat × Bool) : ∀ (n : Nat) (st : St) (w : List Wait),
    ∃ w', nbIter R' n (setW st w) = setW (nbIter R n st) w'
  | 0, st, w => ⟨w, rfl⟩
  | n + 1, st, w => by
    simp only [nbIter]
    obtain ⟨w1, e⟩ := nbStep_setW R R' st w
    rw [e]
    exact nbIter_setW R R' n (nbStep R st) w1

/-- A wait at the column and after the slots of `c`. -/
def AtC (c : St) (x : Wait) : Prop := x.2.1 = c.page ∧ x.2.2.1 = c.column ∧ x.2.2.2.1 = c.slots.length

def setReq (q : Nat) (ol : Bool) (x : Wait) : Wait := (x.1, x.2.1, x.2.2.1, x.2.2.2.1, q, ol)

theorem WRel.lines {D : Wait → Prop} : ∀ {ws w : List Wait}, WRel D ws w →
    ws.map (fun x => x.2.2.2.2.2) = w.map (fun x => x.2.2.2.2.2)
  | [], [], _ => rfl
  | x :: xs, y :: ys, ⟨h, r⟩ => by
    simp only [List.map]
    rw [WRel.lines r]
    rcases h with e | ⟨t, _⟩
    · rw [e]
    · rw [t.2.2.2.2]
  | [], _ :: _, r => r.elim
  | _ :: _, [], r => r.elim

theorem WRel.setReq {D : Wait → Prop} (q q' : Nat) (ol : Bool) (hD : ∀ x, D x → D (setReq q ol x)) :
    ∀ {ws w : List Wait}, WRel D ws w → (∀ x ∈ ws, D x) → WRel D (ws.map (setReq q ol)) (w.map (setReq q' ol))
  | [], [], _, _ => trivial
  | x :: xs, y :: ys, ⟨h, r⟩, hx => by
    refine ⟨Or.inr ⟨?_, hD x (hx x (.head _))⟩, WRel.setReq q q' ol hD r (fun z hz => hx z (.tail _ hz))⟩
    rcases h with e | ⟨t, _⟩
    · subst e; exact ⟨rfl, rfl, rfl, rfl, rfl⟩
    · exact ⟨t.1, t.2.1, t.2.2.1, t.2.2.2.1, rfl⟩
  | [], _ :: _, r, _ => r.elim
  | _ :: _, [], r, _ => r.elim

theorem WRel.append {D : Wait → Prop} : ∀ {a b a' b' : List Wait}, WRel D a a' → WRel D b b' → WRel D (a ++ b) (a' ++ b')
  | [], _, [], _, _, h => h
  | _ :: _, _, _ :: _, _, ⟨h, r⟩, h' => ⟨h, WRel.append r h'⟩
  | [], _, _ :: _, _, r, _ => r.elim
  | _ :: _, _, [], _, r, _ => r.elim

theorem any_lines (ws w : List Wait) (e : ws.map (fun x => x.2.2.2.2.2) = w.map (fun x => x.2.2.2.2.2)) :
    ws.any (fun x => x.2.2.2.2.2) = w.any (fun x => x.2.2.2.2.2) := by
  induction ws generalizing w with
  | nil => cases w with
    | nil => rfl
    | cons _ _ => cases e
  | cons x xs ih => cases w with
    | nil => cases e
    | cons y ys =>
      simp only [List.map, List.cons.injEq] at e
      simp only [List.any, e.1, ih ys e.2]

theorem waitFor_eq (u : Unmet) (R : Nat × Bool) (st : St) :
    (waitFor u R st).waits = st.waits.map (setReq (st.waits.foldl (fun a w => max a w.2.2.2.2.1) R.1)
      (R.2 || st.waits.any (fun w => w.2.2.2.2.2))) ++
      [(u, st.page, st.column, st.slots.length, st.waits.foldl (fun a w => max a w.2.2.2.2.1) R.1,
        R.2 || st.waits.any (fun w => w.2.2.2.2.2))] := rfl

/-- The no-breaks with two counts of the same kind give states whose waits
    differ only in the lines they ask for, all at the column and after
    the slots of the cursor. -/
theorem nbIter_twin (c : St) (R R' : Nat × Bool) (h2 : R.2 = R'.2) : ∀ (n : Nat) (st : St) (w : List Wait),
    st.page = c.page → st.column = c.column → st.slots = c.slots → (∀ x ∈ st.waits, AtC c x) →
    WRel (AtC c) st.waits w →
    ∃ w', nbIter R' n (setW st w) = setW (nbIter R n st) w' ∧ WRel (AtC c) (nbIter R n st).waits w' ∧
      ∀ x ∈ (nbIter R n st).waits, AtC c x
  | 0, st, w, _, _, _, ha, hr => ⟨w, rfl, hr, ha⟩
  | n + 1, st, w, hp, hc, hs, ha, hr => by
    simp only [nbIter]
    have step : ∃ w1, nbStep R' (setW st w) = setW (nbStep R st) w1 ∧ WRel (AtC c) (nbStep R st).waits w1 ∧
        ∀ x ∈ (nbStep R st).waits, AtC c x := by
      have e : nbStep R' (setW st w) = waitForPrior .noBreak R' (setW { st with join := none } w) := rfl
      rw [e]
      unfold nbStep waitForPrior
      simp only [empty_setW, setW_deferred]
      split
      · exact ⟨w, rfl, hr, ha⟩
      · refine ⟨(waitFor .noBreak R' (setW { st with join := none } w)).waits, rfl, ?_, ?_⟩
        · rw [waitFor_eq, waitFor_eq]
          have hl : (R.2 || st.waits.any (fun w => w.2.2.2.2.2)) =
              (R'.2 || (setW { st with join := none } w).waits.any (fun w => w.2.2.2.2.2)) := by
            rw [h2]; exact congrArg _ (any_lines _ _ (WRel.lines hr))
          rw [← hl]
          refine WRel.append (WRel.setReq _ _ _ (fun x d => d) hr ha) ⟨Or.inr ⟨⟨rfl, rfl, rfl, rfl, rfl⟩, ?_⟩, trivial⟩
          exact ⟨hp, hc, by rw [hs]⟩
        · intro x hx
          rw [waitFor_eq] at hx
          rcases mem_app hx with m | m
          · obtain ⟨y, hy, ey⟩ := mem_map_of m
            rw [← ey]; exact ha y hy
          · cases m with
            | head => exact ⟨hp, hc, by rw [hs]⟩
            | tail _ m => cases m
    obtain ⟨w1, e, r1, a1⟩ := step
    rw [e]
    obtain ⟨k1, k2, k3, _⟩ := nbStep_keeps R st
    exact nbIter_twin c R R' h2 n (nbStep R st) w1 (k1.trans hp) (k2.trans hc) (k3.trans hs) a1 r1

theorem addedSlots_all (lo : Bool) (s : List (Int × Slot)) : addedSlots lo s.length s = 0 := by
  unfold addedSlots; rw [List.drop_length]; rfl

theorem moveCursor_waits (e : Env) (region : Region) (st : St) : (moveCursor e region st).waits = st.waits := by
  have := moveCursor_setW e region st st.waits
  rw [setW_self] at this
  rw [this]; rfl

/-- After the move to the next column, a wait at the column and after the
    slots of the cursor is dead. -/
theorem dead_moved (e : Env) (region : Region) (c st : St) (hw : WO st) (hp : st.page = c.page)
    (hc : st.column = c.column) (hs : st.slots = c.slots) (x : Wait) (hx : AtC c x) :
    Dead (moveCursor e region st) x := by
  obtain ⟨x1, x2, x3⟩ := hx
  have lt := nextColumn_lt e (endWrap region st)
  refine ⟨?_, ?_⟩
  · simp only [pos, x1, x2, ← hp, ← hc] at lt ⊢; exact lt
  · intro o ho e1 e2
    rcases nextColumn_done e (endWrap region st) o ho with m | ⟨_, sl⟩ | q
    · exfalso
      have := hw o m
      simp only [PLt, opos, pos, e1, e2, x1, x2, ← hp, ← hc] at this
      omega
    · rw [sl, x3, ← hs]; exact addedSlots_all _ _
    · exfalso
      simp only [PLt, opos, pos, e1, e2, x1, x2, ← hp, ← hc] at q
      exact absurd q (by simp [endWrap])

/-- `paras` with other rows for the verse lines not tried. -/
def parasWith (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (o : Nat → List Line) : Paras :=
  { paras e m job region origin with orig := o }

theorem WO_nbIter (R : Nat × Bool) (n : Nat) (st : St) (h : WO st) : WO (nbIter R n st) := by
  obtain ⟨a1, a2, _, a4, _⟩ := nbIter_keeps R n st
  intro o ho
  rw [a4] at ho
  simp only [pos, a1, a2]
  exact h o ho

theorem holdNext_fresh (r : Nat) (l : Bool) (st : St) : Fresh (holdNext r l (checkWaits st)) :=
  Fresh_waitForPrior _ _ _ (checkWaits_fields st).1

theorem paragraphAt_rel (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (index : Nat)
    (later : List Nat) (k : Keep) (lastWanted wanted : Nat) (c s : St)
    (h : paragraphAt e m job region origin index later k lastWanted wanted c = .ok s) : (WO c → WO s) ∧ Fresh s := by
  unfold paragraphAt at h
  refine parts_rel _ _ _ _ _ _ _ (fun a b => WO a → WO b) Fresh (fun f g x => g (f x))
    (fun _ _ _ st _ p hp x => x.adv (adv_trialWrap _ _ _ _ _ st _ p hp))
    (fun st x => x.adv (adv_moveCursor _ _ st))
    (fun st => ?_) _ _ _ _ _ _ _ h
  dsimp only
  split
  · exact ⟨fun x => WO_waitForPrior _ _ (WO_checkWaits x), holdNext_fresh _ _ _⟩
  · exact ⟨fun x => WO_checkWaits x, Fresh_checkWaits _⟩

theorem stanza_rel (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (later : List Nat) (keep : Keep)
    (isStart : Bool) (c s : St) (indices : List Nat)
    (h : stanza e region (beside m region origin) (stanzaArgs e m job region origin) later keep isStart c indices = .ok s) :
    (WO c → WO s) ∧ Fresh s :=
  (stanza_accept_rel e region (beside m region origin) (stanzaArgs e m job region origin) (fun a b => WO a → WO b) Fresh (fun f g x => g (f x))
    (fun _ _ _ st _ p hp x => x.adv (adv_trialWrap _ _ _ _ _ st _ p hp))
    (fun st x => x.adv (adv_moveCursor _ _ st)) (fun _ _ x => x) (fun _ _ x => x)
    (fun _ => ⟨fun x => WO_checkWaits x, Fresh_checkWaits _⟩)
    (fun _ _ _ _ => ⟨fun x => WO_waitForPrior _ _ (WO_checkWaits x), holdNext_fresh _ _ _⟩)
    (fun i later c s h => (paragraphAt_rel e m job region origin i later defaultKeep 0 0 c s h).1) _).1
    later keep isStart c indices s rfl h

/-- The rows the verse lines not tried keep (`orig`) leave what `paragraphs`
    places unchanged, from a cursor whose closed pages lie before its column
    and whose waits are in its column after its slots. -/
theorem I5_paragraphs_orig (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (o : Nat → List Line)
    (prior : Nat) (cursor : St) (positions : List Nat) (hw : WO cursor) (hf : Fresh cursor) :
    paragraphs e region (beside m region origin) (stanzaArgs e m job region origin) (parasWith e m job region origin o)
      prior cursor positions =
    paragraphs e region (beside m region origin) (stanzaArgs e m job region origin) (paras e m job region origin)
      prior cursor positions := by
  match positions with
  | [] => rfl
  | index :: later =>
    conv => lhs; rw [paragraphs]
    conv => rhs; rw [paragraphs]
    have f1 : (parasWith e m job region origin o).preliminary = (paras e m job region origin).preliminary := rfl
    have f2 : (parasWith e m job region origin o).ready = (paras e m job region origin).ready := rfl
    have f3 : (parasWith e m job region origin o).paragraph = (paras e m job region origin).paragraph := rfl
    rw [f1, f2, f3]
    have hpre : (paras e m job region origin).preliminary prior index cursor =
        .ok (nbIter (1, false) (controlsBetween m prior index).length cursor) :=
      placeAll_noBreaks e _ cursor (controls_noBreaks m prior index)
    rw [hpre]
    simp only
    have hready : ∀ rows, (beside m region origin).isStanza index = true →
        (paras e m job region origin).ready prior index cursor rows =
        .ok (nbIter (followingRows 0 [.stanza defaultKeep rows]) (controlsBetween m prior index).length cursor) := by
      intro rows hs
      have hv : isVerse m index = true := hs
      simp only [paras, hv, if_true]
      exact stepPrefix_noBreaks e _ _ cursor (controls_noBreaks m prior index)
    by_cases hs : (beside m region origin).isStanza index = true
    · rw [if_pos hs, if_pos hs]
      cases ht : tryVerses e region (beside m region origin) (nbIter (1, false) (controlsBetween m prior index).length cursor)
          (verseSpan (beside m region origin) index later).1 with
      | error x => rfl
      | ok trials =>
        simp only
        rw [hready _ hs, hready _ hs]
        simp only
        generalize (controlsBetween m prior index).length = n at ht ⊢
        generalize hvs : (verseSpan (beside m region origin) index later).1 = vs at ht ⊢
        generalize hpre : nbIter (1, false) n cursor = pre at ht ⊢
        have hst : stanza e region (beside m region origin) (stanzaArgs e m job region origin)
              (verseSpan (beside m region origin) index later).2 ((beside m region origin).keepOf index) true
              (nbIter (followingRows 0 [.stanza defaultKeep
                (verseRows (beside m region origin) (parasWith e m job region origin o) (pre :: trials).dropLast vs)]) n cursor) vs =
            stanza e region (beside m region origin) (stanzaArgs e m job region origin)
              (verseSpan (beside m region origin) index later).2 ((beside m region origin).keepOf index) true
              (nbIter (followingRows 0 [.stanza defaultKeep
                (verseRows (beside m region origin) (paras e m job region origin) (pre :: trials).dropLast vs)]) n cursor) vs := by
          have hle := tryVerses_length e region (beside m region origin) pre vs trials ht
          by_cases hE : empty cursor = true ∨ cursor.deferred ≠ []
          · rw [nbIter_unmet _ _ n cursor hE]
          by_cases hfp : firstPart defaultKeep true vs.length ≤ trials.length
          · rw [I5_noBreak_rows_orig (beside m region origin) (parasWith e m job region origin o)
              (paras e m job region origin) defaultKeep pre trials vs hfp hle]
          have he : empty cursor = false := by
            cases h : empty cursor with
            | false => rfl
            | true => exact absurd (Or.inl h) hE
          generalize (verseRows (beside m region origin) (parasWith e m job region origin o) (pre :: trials).dropLast vs) = ro
          generalize (verseRows (beside m region origin) (paras e m job region origin) (pre :: trials).dropLast vs) = rr
          obtain ⟨w, ew, wr, _⟩ := nbIter_twin cursor (followingRows 0 [.stanza defaultKeep rr])
            (followingRows 0 [.stanza defaultKeep ro]) rfl n cursor cursor.waits rfl rfl rfl hf (WRel.refl _ _)
          rw [setW_self] at ew
          rw [ew]
          obtain ⟨w1, e1⟩ := nbIter_setW (1, false) (followingRows 0 [.stanza defaultKeep rr]) n cursor cursor.waits
          rw [setW_self, hpre] at e1
          have kp := nbIter_keeps (followingRows 0 [.stanza defaultKeep rr]) n cursor
          have hX : tryVerses e region (beside m region origin) (nbIter (followingRows 0 [.stanza defaultKeep rr]) n cursor) vs =
              .ok (trials.map (setW · w1)) := by
            rw [e1, tryVerses_setW _ _ _ (beside_blind m region origin), ht]; rfl
          have hXo : tryVerses e region (beside m region origin)
              (setW (nbIter (followingRows 0 [.stanza defaultKeep rr]) n cursor) w) vs = .ok (trials.map (setW · w)) := by
            rw [e1]
            show tryVerses _ _ _ (setW pre w) vs = _
            rw [tryVerses_setW _ _ _ (beside_blind m region origin), ht]; rfl
          have hne : vs ≠ [] := by rw [← hvs]; simp [verseSpan]
          have lt : trials.length < firstPart ((beside m region origin).keepOf index) true vs.length := Nat.lt_of_not_le hfp
          have heX : empty (nbIter (followingRows 0 [.stanza defaultKeep rr]) n cursor) = false := by
            rw [nbIter_empty]; exact he
          have hk : ((beside m region origin).keepOf index).all = false := rfl
          rw [I5_stanza_moves e region (beside m region origin) (stanzaArgs e m job region origin) _ _ _ vs _ hk hX
              (by rw [List.length_map]; exact lt) heX hne,
            I5_stanza_moves e region (beside m region origin) (stanzaArgs e m job region origin) _ _ _ vs _ hk hXo
              (by rw [List.length_map]; exact lt) heX hne,
            moveCursor_setW]
          exact (stanza_accept_sim e region (beside m region origin) (stanzaArgs e m job region origin)
            (beside_blind m region origin) (fun _ _ _ => rfl)
            (fun i later c w h => paragraphAt_sim e m job region origin i later defaultKeep 0 0 c w h) _).1
            _ _ true _ vs w rfl ⟨w, rfl, by
              rw [moveCursor_waits]
              exact WRel.mono (fun x hx => dead_moved e region cursor _ (WO_nbIter _ _ _ hw) kp.1 kp.2.1 kp.2.2.1 x hx) wr⟩
        rw [hst]
        cases hs2 : stanza e region (beside m region origin) (stanzaArgs e m job region origin)
            (verseSpan (beside m region origin) index later).2 ((beside m region origin).keepOf index) true
            (nbIter (followingRows 0 [.stanza defaultKeep
              (verseRows (beside m region origin) (paras e m job region origin) (pre :: trials).dropLast vs)]) n cursor) vs with
        | error x => rfl
        | ok next =>
          simp only
          have r := stanza_rel e m job region origin _ _ true _ next _ hs2
          exact I5_paragraphs_orig e m job region origin o _ next _ (r.1 (WO_nbIter _ _ _ hw)) r.2
    · rw [if_neg hs, if_neg hs]
      cases hr : (paras e m job region origin).ready prior index cursor
          [(beside m region origin).compose (nbIter (1, false) (controlsBetween m prior index).length cursor) index] with
      | error x => rfl
      | ok ready =>
        simp only
        cases hn : (paras e m job region origin).paragraph index later ready with
        | error x => rfl
        | ok next =>
          simp only
          have hv : isVerse m index = false := by simpa using hs
          have er : ready = nbIter (followingRows 0 ([(beside m region origin).compose
              (nbIter (1, false) (controlsBetween m prior index).length cursor) index].map (.paragraph defaultKeep ·)))
              (controlsBetween m prior index).length cursor := by
            simp only [paras, hv] at hr
            rw [stepPrefix_noBreaks e _ _ cursor (controls_noBreaks m prior index)] at hr
            injection hr with hr; exact hr.symm
          simp only [paras] at hn
          have r := paragraphAt_rel e m job region origin index later _ _ _ ready next hn
          exact I5_paragraphs_orig e m job region origin o index next later (r.1 (er ▸ WO_nbIter _ _ _ hw)) r.2
termination_by positions.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after (beside m region origin) index later; omega)

theorem flowsOf_kinds (m : Ms) : ∀ (first : Nat) (ps : List Nat),
    ∀ f ∈ flowsOf m first ps, (∃ k ls, f = .paragraph k ls) ∨ f = .noBreak
  | _, [] => fun _ h => by cases h
  | first, i :: rest => by
    unfold flowsOf
    split
    · intro f hf
      cases hf with
      | head => exact Or.inl ⟨_, _, rfl⟩
      | tail _ m' => exact flowsOf_kinds m _ rest f m'
    · intro f hf
      cases hf with
      | head => exact Or.inl ⟨_, _, rfl⟩
      | tail _ m' => exact flowsOf_kinds m _ rest f m'
    · intro f hf
      cases hf with
      | head => exact Or.inr rfl
      | tail _ m' => exact flowsOf_kinds m _ rest f m'
    · exact flowsOf_kinds m first rest

theorem WO_stepPrefix (e : Env) (following : List Flow) : ∀ (flows : List Flow) (st s : St),
    (∀ f ∈ flows, (∃ k ls, f = .paragraph k ls) ∨ f = .noBreak) → stepPrefix e st following flows = .ok s → WO st → WO s
  | [], st, s, _, h, hw => by simp only [stepPrefix, Except.ok.injEq] at h; subst h; exact hw
  | f :: rest, st, s, hk, h, hw => by
    simp only [stepPrefix] at h
    split at h
    · cases h
    · rename_i s1 e1
      exact WO_stepPrefix e following rest s1 s (fun g hg => hk g (.tail _ hg)) h
        (WO_placeNext inner e st f _ s1 (hk f (.head _)) e1 hw)

/-- `runJob` with the rows `o job` for the verse lines not tried. -/
def runJobWith (o : Nat → Nat → List Line) (e : Env) (m : Ms) (prior : Option Nat) (job : Nat) (at' : St) :
    Except Failure St :=
  let prefixFlows := prefixFlows m prior job at'
  let ident := wrapIdent m prior job at'
  match stepPrefix e at' [.wrapped ident (extent m.w) []] prefixFlows with
  | .error f => .error f
  | .ok ready =>
    match beginWrap e ready ident (extent m.w) with
    | .error f => .error f
    | .ok (anchored, region) =>
      let origin := (region.map (·.2.2)).getD 0 - extent m.w
      let positions := (besides m job).filter (fun i => 0 < chars m i)
      match paragraphs e region (beside m region origin) (stanzaArgs e m job region origin)
          (parasWith e m job region origin (o job)) job anchored positions with
      | .error f => .error f
      | .ok placed => .ok (endWrap region placed)

theorem runJob_with (e : Env) (m : Ms) (prior : Option Nat) (job : Nat) (c : St) :
    runJobWith (orig m) e m prior job c = runJob e m prior job c := rfl

/-- On these manuscripts, the rows the verse lines not tried keep (`orig`)
    leave what a run of a figure places unchanged, from a cursor whose
    closed pages lie before its column. -/
theorem I5_runJob_orig (o : Nat → Nat → List Line) (e : Env) (m : Ms) (prior : Option Nat) (job : Nat) (c : St)
    (hw : WO c) : runJobWith o e m prior job c = runJob e m prior job c := by
  unfold runJobWith runJob
  dsimp only
  cases h1 : stepPrefix e c [.wrapped (wrapIdent m prior job c) (extent m.w) []] (prefixFlows m prior job c) with
  | error x => rfl
  | ok ready =>
    simp only
    cases h2 : beginWrap e ready (wrapIdent m prior job c) (extent m.w) with
    | error x => rfl
    | ok r =>
      obtain ⟨anchored, region⟩ := r
      simp only
      have wr := WO_stepPrefix e _ _ c ready (flowsOf_kinds m _ _) h1 hw
      unfold beginWrap at h2
      split at h2
      · cases h2
      · injection h2 with h2
        injection h2 with ha _
        rw [I5_paragraphs_orig e m job region _ (o job) job anchored _ (by
          rw [← ha]; exact WO_checkWaits ((wr.adv (adv_fit e ready _)).adv (Adv.same rfl rfl rfl))) (by
          rw [← ha]; exact Fresh_checkWaits _)]

def slotText : Int × Slot → String
  | (p, .line i) => s!"{p}:L{i}"
  | (p, .wrapped i) => s!"{p}:SWrapped {i}"
  | (p, _) => s!"{p}:other"

def unmetText : Unmet → String
  | .noBreak => "!nobreak"
  | .keepNext _ => "!keepnext"
  | .needLines n => s!"!need{n}"
  | .shortPart true i w g => s!"!first{i}:{w}:{g}"
  | .shortPart false i w g => s!"!last{i}:{w}:{g}"
  | .splitPart false .page => "!splitpage"
  | .splitPart false .spread => "!splitspread"
  | _ => "!other"

def pageText (p : PageOut) : String :=
  "  " ++ " ".intercalate ([toString p.number, toString p.column, if p.blank then "blank" else "-"] ++
    p.slots.map slotText ++ p.unmet.map unmetText)

/-- The pages, or the diagnostics.  golem-typeset reports a figure whose
    exclusion is longer than the column (G07023) for each such figure when
    it composes the figures, before `causalFreeFlow`; `beginWrap` would
    stop at the first (G07038). -/
def output (m : Ms) (lines : Nat) : List String :=
  let e := env lines
  let figures := (indices m).filter (isFig m)
  let tall := figures.filter (fun _ => e.capacity < extent m.w)
  if 0 < tall.length then ["  error " ++ " ".intercalate (tall.map fun _ => "G07023")] else
  match jobsFrom (jobs e m) none none (initial e) figures with
  | .error (.figureTooTall _) => ["  error G07038"]
  | .error _ => ["  error failure"]
  | .ok final =>
    match (close e (drainCarry e final)).done.reverse with
    | [] => ["  1 0 -"]
    | pages => pages.map pageText

theorem WO_placeAll (e : Env) : ∀ (flows : List Flow) (st s : St),
    (∀ f ∈ flows, (∃ k ls, f = .paragraph k ls) ∨ f = .noBreak) → placeAll inner e st flows = .ok s → WO st → WO s
  | [], st, s, _, h, hw => by simp only [placeAll, Except.ok.injEq] at h; subst h; exact hw
  | f :: rest, st, s, hk, h, hw => by
    simp only [placeAll] at h
    split at h
    · cases h
    · rename_i s1 e1
      exact WO_placeAll e rest s1 s (fun g hg => hk g (.tail _ hg)) h (WO_placeNext inner e st f _ s1 (hk f (.head _)) e1 hw)

theorem WO_stepAt (e : Env) (m : Ms) (c s : St) (ps : List Nat) (h : stepAt e m c ps = .ok s) (hw : WO c) : WO s :=
  WO_placeAll e _ c s (flowsOf_kinds m _ _) h hw

theorem WO_ready (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (prior index : Nat) (c s : St)
    (rows : List (List Line)) (h : (paras e m job region origin).ready prior index c rows = .ok s) (hw : WO c) : WO s := by
  simp only [paras] at h
  rw [stepPrefix_noBreaks e _ _ c (controls_noBreaks m prior index)] at h
  injection h with h; subst h
  exact WO_nbIter _ _ _ hw

theorem WO_paragraphs (e : Env) (m : Ms) (job : Nat) (region : Region) (origin : Int) (prior : Nat) (cursor : St)
    (positions : List Nat) (s : St)
    (h : paragraphs e region (beside m region origin) (stanzaArgs e m job region origin) (paras e m job region origin)
      prior cursor positions = .ok s) (hw : WO cursor) : WO s := by
  match positions with
  | [] => simp only [paragraphs, Except.ok.injEq] at h; subst h; exact hw
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
              exact WO_paragraphs e m job region origin _ next _ s h
                ((stanza_rel e m job region origin _ _ _ ready next _ es).1 (WO_ready e m job region origin _ _ _ _ _ er hw))
      · split at h
        · cases h
        · rename_i ready er
          split at h
          · cases h
          · rename_i next en
            simp only [paras] at en
            exact WO_paragraphs e m job region origin index next later s h
              ((paragraphAt_rel e m job region origin _ _ _ _ _ ready next en).1 (WO_ready e m job region origin _ _ _ _ _ er hw))
termination_by positions.length
decreasing_by
  all_goals simp_wf
  all_goals (have := verseSpan_after (beside m region origin) index later; omega)

theorem WO_runJob (e : Env) (m : Ms) (prior : Option Nat) (job : Nat) (c s : St) (h : runJob e m prior job c = .ok s)
    (hw : WO c) : WO s := by
  unfold runJob at h
  dsimp only at h
  split at h
  · cases h
  · rename_i ready h1
    have wr := WO_stepPrefix e _ _ c ready (flowsOf_kinds m _ _) h1 hw
    split at h
    · cases h
    · rename_i anchored region h2
      split at h
      · cases h
      · rename_i placed h3
        injection h with h; subst h
        unfold beginWrap at h2
        split at h2
        · cases h2
        · injection h2 with h2
          injection h2 with ha _
          have wa : WO anchored := by
            rw [← ha]; exact WO_checkWaits ((wr.adv (adv_fit e ready _)).adv (Adv.same rfl rfl rfl))
          exact (WO_paragraphs e m job region _ job anchored _ placed h3 wa).adv (Adv.same rfl rfl rfl)

theorem retainPart_congr (e : Env) (u : PartUnit) {α : Type} (trial trial' : St → Except Failure (α × St)) (at' : St)
    (h1 : trial' at' = trial at') (h2 : trial' (nextUnit e u at') = trial (nextUnit e u at')) :
    retainPart e u trial' at' = retainPart e u trial at' := by
  unfold retainPart
  dsimp only
  rw [h1, h2]

theorem WO_retainPart (e : Env) (u : PartUnit) {α : Type} (trial : St → Except Failure (α × St)) (at' : St)
    (r : α × St) (h : retainPart e u trial at' = .ok r) (hw : WO at')
    (ht : ∀ s r, WO s → trial s = .ok r → WO r.2) : WO r.2 := by
  unfold retainPart at h
  dsimp only at h
  cases h1 : trial at' with
  | error f => rw [h1] at h; cases h
  | ok p =>
    obtain ⟨a, placed⟩ := p
    rw [h1] at h
    dsimp only at h
    have wp : WO placed := ht _ _ hw h1
    split at h
    · injection h with h; subst h; exact wp.adv (adv_settle _ _ _)
    · have wn : WO (nextUnit e u at') := hw.adv (adv_nextUnit e u at')
      cases h2 : trial (nextUnit e u at') with
      | error f => rw [h2] at h; cases h
      | ok q =>
        obtain ⟨b, placed'⟩ := q
        rw [h2] at h
        dsimp only at h
        have wq : WO placed' := ht _ _ wn h2
        split at h
        · injection h with h; subst h; exact wq.adv (adv_settle _ _ _)
        · split at h
          · injection h with h; subst h; exact (wp.adv (adv_settle _ _ _)).adv (Adv.same rfl rfl rfl)
          · injection h with h; subst h; exact (wq.adv (adv_settle _ _ _)).adv (Adv.same rfl rfl rfl)

/-- The loop over the figures with the rows `o job` for the verse lines
    not tried. -/
def jobsWith (o : Nat → Nat → List Line) (e : Env) (m : Ms) : Jobs :=
  { jobs e m with run := fun prior _ job at' => runJobWith o e m prior job at' }

/-- On these manuscripts, the rows the verse lines not tried keep (`orig`)
    leave the pages `jobsFrom` places unchanged. -/
theorem I5_jobsFrom_orig (o : Nat → Nat → List Line) (e : Env) (m : Ms) (jobsList : List Nat) :
    jobsFrom (jobsWith o e m) none none (initial e) jobsList = jobsFrom (jobs e m) none none (initial e) jobsList := by
  refine jobsFrom_congr (jobs e m) _ WO
    (fun prior _ job c hc => I5_runJob_orig o e m prior job c hc)
    (fun prior _ job c s hc h => WO_runJob e m prior job c s h hc)
    (fun _ _ _ c s hc h => WO_stepAt e m c s _ h hc)
    (fun _ _ c s hc h => WO_stepAt e m c s _ h hc)
    (fun trial trial' at' hw ht => ?_)
    (fun trial at' r hw ht h => ?_) none none (initial e) jobsList (fun o ho => by cases ho)
  · simp only [jobs]
    split
    · exact retainPart_congr e m.part trial trial' at' (ht _ hw) (ht _ (hw.adv (adv_nextUnit e m.part at')))
    · exact ht _ hw
  · simp only [jobs] at h
    split at h
    · exact WO_retainPart e m.part trial at' r h hw ht
    · exact ht _ _ hw h

/-- `output` with the rows `o job` for the verse lines not tried. -/
def outputWith (o : Nat → Nat → List Line) (m : Ms) (lines : Nat) : List String :=
  let e := env lines
  let figures := (indices m).filter (isFig m)
  let tall := figures.filter (fun _ => e.capacity < extent m.w)
  if 0 < tall.length then ["  error " ++ " ".intercalate (tall.map fun _ => "G07023")] else
  match jobsFrom (jobsWith o e m) none none (initial e) figures with
  | .error (.figureTooTall _) => ["  error G07038"]
  | .error _ => ["  error failure"]
  | .ok final =>
    match (close e (drainCarry e final)).done.reverse with
    | [] => ["  1 0 -"]
    | pages => pages.map pageText

/-- The rows the verse lines not tried keep (`orig`), which a no-break
    ahead of a stanza waits for, never change the pages or the diagnostics
    of these manuscripts. -/
theorem I5_output_orig (o : Nat → Nat → List Line) (m : Ms) (lines : Nat) : outputWith o m lines = output m lines := by
  unfold outputWith output
  dsimp only
  rw [I5_jobsFrom_orig]

def replicateM : Nat → List Nat → List (List Nat)
  | 0, _ => [[]]
  | n + 1, xs => xs.bind (fun x => (replicateM n xs).map (x :: ·))

/-- The stanzas of CausalBoundary.hs: one to four verse lines alone; two
    or three before or after a paragraph, with or without a no-break
    between them; and two stanzas of two verse lines. -/
def stanzas : List (List Item) :=
  ([1, 2, 3].bind fun n => (replicateM n [5, 12, 25]).map fun ns => [Item.v ns]) ++
  ((replicateM 4 [5, 25]).map fun ns => [Item.v ns]) ++
  ([2, 3].bind fun n => (replicateM n [5, 25]).bind fun ns => [5, 12].bind fun size =>
    [[.p size, .v ns], [.v ns, .p size], [.p size, .k, .v ns], [.v ns, .k, .p size]]) ++
  ((replicateM 2 [5, 25]).bind fun as => (replicateM 2 [5, 25]).map fun bs => [Item.v as, Item.v bs])

/-- A stanza or a paragraph that keeps with the next 3 lines, before a
    stanza of four verse lines or before a paragraph. -/
def holding : List (List Item) :=
  let heads := ((replicateM 2 [5, 25]).map Item.h) ++ ([5, 12].map Item.q)
  (heads.bind fun held => (replicateM 4 [5, 25]).map fun bs => [held, Item.v bs]) ++
  (heads.bind fun held => [5, 12, 25].map fun n => [held, Item.p n])

/-- The manuscripts of CausalBoundary.hs after a wrapped figure. -/
def manuscripts : List (List Item) :=
  ([1, 2, 3].bind fun n => (replicateM n [5, 12, 25]).map (·.map Item.p)) ++
  ([2, 3].bind fun n => (replicateM n [5, 12, 25]).bind fun ns =>
    ((replicateM (n - 1) [0, 1]).filter (fun hs => hs.any (· == 1))).map fun hs =>
      (List.zip (0 :: hs) ns).bind fun (h, c) => (if h == 1 then [Item.k] else []) ++ [Item.p c]) ++
  stanzas ++ holding

/-- An item with a figure and a nested item after it, alone, before a
    paragraph, and before an item with a figure. -/
def nested : List (List Item) :=
  ([5, 25].bind fun p => [5, 12, 25].map fun sub => [Item.j 3 [[p]] sub]) ++
  ([5, 25].bind fun p => [5, 25].bind fun sub => [5, 25].map fun n => [Item.j 3 [[p]] sub, .p n]) ++
  ([5, 25].bind fun p => [5, 25].bind fun sub => [5, 25].map fun q => [Item.j 3 [[p]] sub, .i 3 [[q]]])

/-- The list items of CausalBoundary.hs, in each mode of `keep-parts`: an item with a
    figure and one or two paragraphs after it, an item with two figures, two
    items, and an item after or before a paragraph. -/
def lists : List (List Item) :=
  ([3, 15].bind fun a => ([1, 2].bind fun n => replicateM n [5, 12, 25]).map fun ps => [Item.i a [ps]]) ++
  ((replicateM 2 [5, 25]).map fun pq => [Item.i 3 (pq.map ([·]))]) ++
  ((replicateM 2 [5, 25]).map fun pq => pq.map fun p => Item.i 3 [[p]]) ++
  ([5, 25].bind fun n => [5, 12, 25].bind fun p => [[.p n, .i 3 [[p]]], [.i 3 [[p]], .p n]]) ++
  nested

def inputs : List (String × Ms × Nat) :=
  ([2, 3].bind fun w => [3, 4, 5, 6].bind fun lines => manuscripts.map fun items =>
    (s!"{w} {lines} [{" ".intercalate (items.map Item.name)}]", ⟨w, .column, units true items, wants true items⟩, lines)) ++
  ([("column", PartUnit.column), ("page", .page), ("spread", .spread)].bind fun (mode, u) =>
    [2, 3].bind fun w => [3, 4, 5, 6].bind fun lines => lists.map fun items =>
      (s!"{w} {lines} {mode} [{" ".intercalate (items.map Item.name)}]", ⟨w, u, units false items, wants false items⟩, lines))

end CausalBoundary

/-- The pages of the manuscripts, or, with `premises`, the manuscripts
    where a run does not place `runLines` and their number. -/
def main (args : List String) : IO UInt32 := do
  let out ← IO.getStdout
  if args == ["premises"] then
    let failed := CausalBoundary.inputs.filter (fun (_, m, lines) => CausalBoundary.premiseFailures m lines)
    for (name, _, _) in failed do
      out.putStrLn s!"runLines fails: {name}"
    out.putStrLn s!"{CausalBoundary.inputs.length} manuscripts, {failed.length} where a run does not place runLines"
    return (if failed.isEmpty then 0 else 1)
  for (name, m, lines) in CausalBoundary.inputs do
    out.putStrLn name
    for l in CausalBoundary.output m lines do
      out.putStrLn l
  return 0
