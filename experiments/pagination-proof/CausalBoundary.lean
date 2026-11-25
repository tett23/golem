/- Root ADR 0352: the manuscripts of CausalBoundary.hs, a wrapped figure
   followed by paragraphs and stanzas in the free placement, on the copies
   of the loops of golem-typeset's causalFreeFlow in Physical.lean:
   `jobsFrom` runs the figure, `paragraphs` the paragraphs and stanzas
   beside it, `parts` (`paragraph`) each paragraph, broken again at each
   cursor, `stanza`, `tryVerses` and `accept` each stanza, and, with a
   no-break after a paragraph or a stanza, `probeNext` and `probeChain`
   what follows it.  `main` prints the pages in the format of
   CausalBoundary.hs, and check.sh compares the two with diff.

   What the loops take as arguments is given here as golem-typeset
   computes it for these manuscripts.  The line breaker (`composeAt`) is
   modelled for the fake fonts of the golem-driver tests: every character
   is 1zw and a line takes as many characters as its width holds, its
   width the measure of 12zw less the exclusion of the figure where the
   row meets it (`rowExtent` and `intersects` of FreeGeometry.hs).  The
   figure is the image of 2 by 3 pixels at a width of `w` zw: its length
   across the lines is 1.5 `w` zw, and the gap of 1zw (`wrap-gap`) is
   added to both its exclusion length and width (`exclusion`,
   Flow.hs:3315).  A line has the id of the lines placed before it plus
   one, the figure taking the id 0; so the first line of a verse line
   (`ident`, `bUnitFirsts`) is the lines placed before the cursor plus
   one.  A verse line not yet tried keeps the rows composed at the full
   measure.  The paragraphs and the verse lines have the default keep and
   keep nothing with what follows by themselves, so `bindingAfter` comes
   from the no-breaks after them alone and nothing is held.

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

def lineCount (st : St) : Nat :=
  (((st.done.reverse.map (·.slots)).join ++ st.slots).filter (fun s => match s.2 with | .line _ => true | _ => false)).length

/-- `composeAt` and `numberedLines` for the fake fonts: the lines of the
    characters from `start` to `n`, each with the character after its
    break. -/
def breakLines (w : Nat) (region : Region) (origin : Int) (at' : St) (start n : Nat) : List (Line × Nat) :=
  let first := lineCount at' + 1
  let rec go : Nat → Nat → Nat → List (Line × Nat)
    | 0, _, _ => []
    | fuel + 1, k, from' =>
      if n ≤ from' then []
      else
        let width := 12 * zw - (if narrowed region origin at' k then exclusionWidth w else 0)
        let next := min n (from' + (width / zw).toNat)
        (⟨first + k, [], 0⟩, next) :: go fuel (k + 1) next
  go (n + 1) 0 start

/-- A paragraph of so many characters, a no-break, or a stanza of verse
    lines of so many characters each. -/
inductive Item where
  | p (n : Nat)
  | k
  | v (ns : List Nat)

def Item.name : Item → String
  | .p n => toString n
  | .k => "K"
  | .v ns => "V" ++ ",".intercalate (ns.map toString)

/-- A unit of golem-typeset: a paragraph, a no-break, or a verse line of
    the stanza `s` (each verse line of a stanza is a unit of its own). -/
inductive Unit' where
  | para (n : Nat)
  | ctrl
  | verse (s n : Nat)

/-- The units of the items, the stanzas numbered by their position. -/
def units (items : List Item) : List Unit' :=
  (items.enum.map fun (s, i) => match i with
    | .p n => [Unit'.para n]
    | .k => [Unit'.ctrl]
    | .v ns => ns.map (Unit'.verse s)).join

/-- The unit at the position `i` (from 1; the figure is 0). -/
def unitAt (items : List Item) (i : Nat) : Option Unit' := (units items).get? (i - 1)

def chars (items : List Item) (i : Nat) : Nat :=
  match unitAt items i with
  | some (.para n) => n
  | some (.verse _ n) => n
  | _ => 0

def stanzaOf (items : List Item) (i : Nat) : Option Nat :=
  match unitAt items i with
  | some (.verse s _) => some s
  | _ => none

def isVerse (items : List Item) (i : Nat) : Bool := (stanzaOf items i).isSome

/-- The no-breaks between the positions `prior` and `index`
    (`controlsBetween`). -/
def controlsBetween (items : List Item) (prior index : Nat) : List Flow :=
  ((List.range (units items).length).map (· + 1)).filterMap fun j =>
    if prior < j ∧ j < index then
      match unitAt items j with
      | some .ctrl => some .noBreak
      | _ => none
    else none

/-- The no-breaks right after the position `index` (`bindingAfter`). -/
def controlsAfter (items : List Item) (index : Nat) : List Flow :=
  (((units items).drop index).takeWhile (fun i => match i with | .ctrl => true | _ => false)).map (fun _ => .noBreak)

/-- `bindingAfter` for a paragraph or a verse line of the default style
    and of `poem`, which keep nothing with what follows by themselves. -/
def binding (items : List Item) (index : Nat) : Nat × Nat :=
  match keepAhead (controlsAfter items index) with
  | none => (0, 0)
  | some (l, f, _) => (l, f)

def inner : Inner := level 1

/-- `stepPhysicalPrefix`: the prefix placed with the following flows ahead. -/
def stepPrefix (e : Env) (st : St) (following : List Flow) : List Flow → Except Failure St
  | [] => .ok st
  | f :: rest =>
    match placeNext inner e st f (rest ++ following) with
    | .error x => .error x
    | .ok s => stepPrefix e s following rest

def beside (w : Nat) (region : Region) (origin : Int) (items : List Item) : Beside :=
  { compose := fun at' i => (breakLines w region origin at' 0 (chars items i)).map (·.1),
    binding := binding items, keepOf := fun _ => defaultKeep, holds := fun _ => false,
    hold := fun _ _ _ st => st, ident := fun at' _ => lineCount at' + 1, isStanza := isVerse items,
    sameVerse := fun i j => isVerse items j && stanzaOf items i == stanzaOf items j }

/-- The number of rows of `n` characters as `composeBeside` composes them
    before the trials: the row `k` of a unit at `distance` from the top of
    the figure is narrowed where it meets the exclusion from 0. -/
def besideRows (w n : Nat) (distance : Int) : Nat :=
  let rec go : Nat → Nat → Nat → Nat
    | 0, _, _ => 0
    | fuel + 1, k, from' =>
      if n ≤ from' then 0
      else
        let narrow := intersects (rowExtent (distance + (k : Int) * pitch)) (0, extent w)
        let width := 12 * zw - (if narrow then exclusionWidth w else 0)
        go fuel (k + 1) (min n (from' + (width / zw).toNat)) + 1
  go (n + 1) 0 0

/-- The rows of the units before `i` and after the figure as `composeBeside`
    composes them, each at the distance the units before it take. -/
def besideDistance (w : Nat) (items : List Item) (i : Nat) : Int :=
  ((List.range (i - 1)).map (· + 1)).foldl (fun d j => d + (besideRows w (chars items j) d : Int) * pitch) 0

/-- The rows of a verse line as composed before it is tried
    (`composeBeside`); only their number is read. -/
def orig (w : Nat) (items : List Item) (i : Nat) : List Line :=
  (List.range (besideRows w (chars items i) (besideDistance w items i))).map fun _ => ⟨0, [], 0⟩

/-- The rows of the first `n` verse lines: those `tryVerses` placed as
    composed at the cursor before each, the others as composed before. -/
def verseRowCount (w : Nat) (region : Region) (origin : Int) (items : List Item) (ready : St) (verses : List Nat)
    (trials : List St) (n : Nat) : Nat :=
  ((List.range n).map fun k =>
    match verses.get? k, (ready :: trials).get? k with
    | some i, some at' => if k < trials.length then ((beside w region origin items).compose at' i).length else (orig w items i).length
    | some i, none => (orig w items i).length
    | none, _ => 0).foldl (· + ·) 0

/-- What follows the paragraphs beside the figure: no flows. -/
def probe (e : Env) (w : Nat) (region : Region) (origin : Int) (items : List Item) : Probe :=
  { prefixAt := fun i j at' => placeAll inner e at' (controlsBetween items i j),
    following := fun at' wanted =>
      let (required, linesOnly) := followingRows wanted []
      (required, linesOnly, fitsFollowing inner e at' wanted []),
    required := fun wanted keep rows => (followingRows wanted [.paragraph keep rows]).1,
    verseRequired := verseRowCount w region origin items }

/-- `paragraph` of the paragraph or verse line `index` with the keep `k`
    and the binding `(lastWanted, wanted)`. -/
def paragraphAt (e : Env) (w : Nat) (region : Region) (origin : Int) (items : List Item) (index : Nat)
    (later : List Nat) (k : Keep) (lastWanted wanted : Nat) (at' : St) : Except Failure St :=
  let follows := fun st =>
    if 0 < wanted ∨ 0 < lastWanted then
      match probeNext e region (beside w region origin items) (probe e w region origin items) index later st wanted with
      | .ok r => r.2.2
      | .error _ => false
    else true
  parts e region (fun at'' _ start => breakLines w region origin at'' start (chars items index)) (chars items index)
    lastWanted follows id none k true 0 0 at'

def paras (e : Env) (w : Nat) (region : Region) (origin : Int) (items : List Item) : Paras :=
  { preliminary := fun prior index at' => placeAll inner e at' (controlsBetween items prior index),
    ready := fun prior index at' rows =>
      let ahead := if isVerse items index then [.stanza defaultKeep rows] else rows.map (.paragraph defaultKeep ·)
      stepPrefix e at' ahead (controlsBetween items prior index),
    orig := orig w items,
    paragraph := fun index later at' =>
      let (lastWanted, wanted) := binding items index
      paragraphAt e w region origin items index later defaultKeep lastWanted wanted at' }

/-- `probeNext` after the last verse line, and the fallback of a verse line
    by its display rows: `paragraph` with the default keep and no binding. -/
def stanzaArgs (e : Env) (w : Nat) (region : Region) (origin : Int) (items : List Item) : StanzaArgs :=
  { follows := fun i later at' wanted =>
      probeNext e region (beside w region origin items) (probe e w region origin items) i later at' wanted,
    fallback := fun i later at' => paragraphAt e w region origin items i later defaultKeep 0 0 at' }

/-- `runJob` of the figure 0 with the paragraphs after it. -/
def jobs (e : Env) (w : Nat) (items : List Item) : Jobs :=
  { itemOf := fun _ => none,
    outside := fun _ _ _ at' => .ok at',
    run := fun _ _ job at' =>
      match beginWrap e at' job (extent w) with
      | .error f => .error f
      | .ok (anchored, region) =>
        let origin := (region.map (·.2.2)).getD 0 - extent w
        let positions := ((List.range (units items).length).map (· + 1)).filter (fun i => 0 < chars items i)
        match paragraphs e region (beside w region origin items) (stanzaArgs e w region origin items)
            (paras e w region origin items) job anchored positions with
        | .error f => .error f
        | .ok placed => .ok (endWrap region placed),
    itemRest := fun _ _ at' => .ok at',
    finish := fun _ _ at' => .ok at',
    retain := fun trial at' => trial at' }

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
  | _ => "!other"

def pageText (p : PageOut) : String :=
  "  " ++ " ".intercalate ([toString p.number, toString p.column, if p.blank then "blank" else "-"] ++
    p.slots.map slotText ++ p.unmet.map unmetText)

def output (w lines : Nat) (items : List Item) : List String :=
  let e := env lines
  match jobsFrom (jobs e w items) none none (initial e) [0] with
  | .error (.figureTooTall _) => ["  error G07023"]
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

/-- The manuscripts of CausalBoundary.hs. -/
def manuscripts : List (List Item) :=
  ([1, 2, 3].bind fun n => (replicateM n [5, 12, 25]).map (·.map Item.p)) ++
  ([2, 3].bind fun n => (replicateM n [5, 12, 25]).bind fun ns =>
    ((replicateM (n - 1) [0, 1]).filter (fun hs => hs.any (· == 1))).map fun hs =>
      (List.zip (0 :: hs) ns).bind fun (h, c) => (if h == 1 then [Item.k] else []) ++ [Item.p c]) ++
  stanzas

def inputs : List (Nat × Nat × List Item) :=
  [2, 3].bind fun w => [3, 4, 5, 6].bind fun lines => manuscripts.map fun items => (w, lines, items)

end CausalBoundary

def main : IO Unit := do
  let out ← IO.getStdout
  for (w, lines, items) in CausalBoundary.inputs do
    out.putStrLn s!"{w} {lines} [{" ".intercalate (items.map CausalBoundary.Item.name)}]"
    for l in CausalBoundary.output w lines items do
      out.putStrLn l
