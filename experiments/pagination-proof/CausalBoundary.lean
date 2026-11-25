/- Root ADR 0352: the manuscripts of CausalBoundary.hs, a wrapped figure
   followed by paragraphs in the free placement, on the copies of the
   loops of golem-typeset's causalFreeFlow in Physical.lean: `jobsFrom`
   runs the figure, `paragraphs` the paragraphs beside it, and `parts`
   (`paragraph`) each paragraph, broken again at each cursor.  `main`
   prints the pages in the format of CausalBoundary.hs, and check.sh
   compares the two with diff.

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
   one, the figure taking the id 0.  The paragraphs have the default keep
   and no controls between them, so `bindingAfter` is (0, 0), the probe
   is not called and nothing is held.

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
  | .space s :: rest => s + firstNeed separator capacity hasNotes wanted rest
  | .blank n :: rest => (n : Int) * pitch + firstNeed separator capacity hasNotes wanted rest
  | .needLines _ :: rest | .adjustLines _ :: rest | .noBreak :: rest
  | .noBreakLines _ :: rest | .keepNext _ _ :: rest => firstNeed separator capacity hasNotes wanted rest
  | .figure _ e :: _ => e
  | .wrapped _ e _ :: _ => e
  | _ => 0
where
  paragraphNeed (separator capacity : Int) (hasNotes : Bool) (wanted : Nat) (k : Keep) (start : Bool)
      (ls : List Line) (rest : List Flow) : Int :=
    let total := ls.length
    let lowest := max (firstPart k start total) (min total (max 1 wanted))
    let count := ((List.range (total + 1)).filter (fun n => lowest ≤ n ∧ splitAtBreak k start total n = n)).headD total
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

/-- A paragraph of so many characters, or a no-break. -/
inductive Item where
  | p (n : Nat)
  | k

def Item.name : Item → String
  | .p n => toString n
  | .k => "K"

/-- The item at the position `i` (from 1; the figure is 0). -/
def itemAt (items : List Item) (i : Nat) : Option Item := items.get? (i - 1)

def chars (items : List Item) (i : Nat) : Nat :=
  match itemAt items i with
  | some (.p n) => n
  | _ => 0

/-- The no-breaks between the positions `prior` and `index`
    (`controlsBetween`). -/
def controlsBetween (items : List Item) (prior index : Nat) : List Flow :=
  ((List.range items.length).map (· + 1)).filterMap fun j =>
    if prior < j ∧ j < index then
      match itemAt items j with
      | some .k => some .noBreak
      | _ => none
    else none

/-- The no-breaks right after the position `index` (`bindingAfter`). -/
def controlsAfter (items : List Item) (index : Nat) : List Flow :=
  ((items.drop index).takeWhile (fun i => match i with | .k => true | _ => false)).map (fun _ => .noBreak)

/-- `bindingAfter` for a paragraph of the default style, which keeps
    nothing with what follows by itself. -/
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
    hold := fun _ _ _ st => st, ident := fun _ => 0, isStanza := fun _ => false, sameVerse := fun _ _ => false }

/-- What follows the paragraphs beside the figure: no flows. -/
def probe (e : Env) (items : List Item) : Probe :=
  { prefixAt := fun i j at' => placeAll inner e at' (controlsBetween items i j),
    following := fun at' wanted =>
      let (required, linesOnly) := followingRows wanted []
      (required, linesOnly, fitsFollowing inner e at' wanted []),
    required := fun wanted keep rows => (followingRows wanted [.paragraph keep rows]).1,
    verseRequired := fun _ _ _ => 0 }

def paras (e : Env) (w : Nat) (region : Region) (origin : Int) (items : List Item) : Paras :=
  { preliminary := fun prior index at' => placeAll inner e at' (controlsBetween items prior index),
    ready := fun prior index at' rows =>
      stepPrefix e at' (rows.map (.paragraph defaultKeep ·)) (controlsBetween items prior index),
    orig := fun _ => [],
    paragraph := fun index later at' =>
      let (lastWanted, wanted) := binding items index
      let follows := fun st =>
        if 0 < wanted ∨ 0 < lastWanted then
          match probeNext e region (beside w region origin items) (probe e items) index later st wanted with
          | .ok r => r.2.2
          | .error _ => false
        else true
      parts e region (fun at'' _ start => breakLines w region origin at'' start (chars items index)) (chars items index)
        lastWanted follows id none defaultKeep true 0 0 at' }

def stanzaArgs : StanzaArgs := { follows := fun _ _ _ _ => .ok (0, true, true), fallback := fun _ _ at' => .ok at' }

/-- `runJob` of the figure 0 with the paragraphs after it. -/
def jobs (e : Env) (w : Nat) (items : List Item) : Jobs :=
  { itemOf := fun _ => none,
    outside := fun _ _ _ at' => .ok at',
    run := fun _ _ job at' =>
      match beginWrap e at' job (extent w) with
      | .error f => .error f
      | .ok (anchored, region) =>
        let origin := (region.map (·.2.2)).getD 0 - extent w
        let positions := ((List.range items.length).map (· + 1)).filter (fun i => 0 < chars items i)
        match paragraphs e region (beside w region origin items) stanzaArgs (paras e w region origin items) job anchored
            positions with
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

/-- The manuscripts of CausalBoundary.hs. -/
def manuscripts : List (List Item) :=
  ([1, 2, 3].bind fun n => (replicateM n [5, 12, 25]).map (·.map Item.p)) ++
  ([2, 3].bind fun n => (replicateM n [5, 12, 25]).bind fun ns =>
    ((replicateM (n - 1) [0, 1]).filter (fun hs => hs.any (· == 1))).map fun hs =>
      (List.zip (0 :: hs) ns).bind fun (h, c) => (if h == 1 then [Item.k] else []) ++ [Item.p c])

def inputs : List (Nat × Nat × List Item) :=
  [2, 3].bind fun w => [3, 4, 5, 6].bind fun lines => manuscripts.map fun items => (w, lines, items)

end CausalBoundary

def main : IO Unit := do
  let out ← IO.getStdout
  for (w, lines, items) in CausalBoundary.inputs do
    out.putStrLn s!"{w} {lines} [{" ".intercalate (items.map CausalBoundary.Item.name)}]"
    for l in CausalBoundary.output w lines items do
      out.putStrLn l
