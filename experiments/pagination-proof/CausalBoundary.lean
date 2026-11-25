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

/-- The lines and the wrapped figures placed: the id of the next one
    (`bUnitFirsts` numbers the lines and the figures in order from 0). -/
def slotCount (st : St) : Nat :=
  (((st.done.reverse.map (·.slots)).join ++ st.slots).filter
    (fun s => match s.2 with | .line _ | .wrapped _ => true | _ => false)).length

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
(`retainPart_retains`).  These are proved.  That `runJob` places the
lines of the flows before the figure, the figure and then lines numbered
on from it (`runLines`) is not: `check.sh` checks it at each run in the
manuscripts (`premiseFailures`). -/

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

/-- What each piece of `jobsFrom` places on these manuscripts. -/
def piecePremise (m : Ms) : JobPiece → St → List Nat → Prop
  | .outside prior done job, c, ls =>
    ls = sourceText (flowsOf m (slotCount c) (span m (after m prior) (itemStart m job - 1) done |>.filter (· < itemStart m job)))
  | .run prior _ job, c, ls => runLines m prior job c ls = true
  | .rest key prior, c, ls =>
    ls = sourceText (flowsOf m (slotCount c) ((span m (after m (some prior)) m.us.length none).filter (fun j => itemAt m j == some key)))
  | .finish prior done, c, ls => ls = sourceText (flowsOf m (slotCount c) (span m (after m prior) m.us.length done))

/-- The premises of `I5_jobsFrom_lines` hold for these manuscripts when
    `runJob` places `runLines`. -/
theorem jobs_lines (e : Env) (m : Ms)
    (hrun : ∀ prior job c s, runJob e m prior job c = .ok s → ∃ ls, runLines m prior job c ls = true ∧ Step c s ls []) :
    JobsLines (jobs e m) (piecePremise m) where
  outside := fun _ _ _ c s h => ⟨_, rfl, stepAt_lines e m c s _ h⟩
  run := fun prior _ job c s h => hrun prior job c s h
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
    in order, when `runJob` places `runLines`. -/
theorem I5_causal_jobsFrom_lines (e : Env) (m : Ms)
    (hrun : ∀ prior job c s, runJob e m prior job c = .ok s → ∃ ls, runLines m prior job c ls = true ∧ Step c s ls [])
    (s : St) (h : jobsFrom (jobs e m) none none (initial e) ((indices m).filter (isFig m)) = .ok s) :
    ∃ lss, PieceChain (piecePremise m) (initial e) (jobPieces (jobs e m) none none ((indices m).filter (isFig m))) lss s :=
  I5_jobsFrom_lines _ _ (jobs_lines e m hrun) _ _ _ _ _ h

/-- `runJob`, failing where it does not place `runLines` and no figures. -/
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
