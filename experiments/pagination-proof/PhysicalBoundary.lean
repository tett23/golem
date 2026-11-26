/- Root ADR 0352, the free placement of root ADR 0397: the boundary
   inputs that PhysicalBoundary.hs prints as "in" lines, evaluated on the
   paginate of Physical.lean.  `boundaryEnv` is the `PhysicalSettings` of
   PhysicalBoundary.hs with `firstNeed` as Physical.hs computes it.
   `main` prints the pages of every input in the format of
   PhysicalBoundary.hs, and check.sh compares the two with diff.  This is
   a check on finitely many inputs, not a proof; the definitions below are
   `partial` because they are only evaluated. -/
import Physical
open PhysicalPagination

namespace PhysicalBoundary

def pitchOf (i : Nat) : Int := if 900 ≤ i ∧ i < 1000 then 14 else 10
def faceOf (i : Nat) : Int := if 900 ≤ i ∧ i < 1000 then 12 else 10

def sumInt (xs : List Int) : Int := xs.foldr (· + ·) 0

instance : Inhabited Keep := ⟨defaultKeep⟩
instance : Inhabited Note := ⟨⟨0, 0⟩⟩
instance : Inhabited Line := ⟨⟨0, [], 0⟩⟩
instance : Inhabited Flow := ⟨.noBreak⟩

/-- `firstNeed` of Physical.hs. -/
partial def firstNeed (pagePitch separator capacity : Int) (hasNotes : Bool) (wanted : Nat) : List Flow → Int
  | .paragraph k ls :: rest => paragraphNeed pagePitch separator capacity hasNotes wanted k true ls rest
  | .continued k ls :: rest => paragraphNeed pagePitch separator capacity hasNotes wanted k false ls rest
  | .stanza k vs :: rest =>
    let total := vs.length
    let lowest := max (firstPart k true total) (min total (max 1 wanted))
    let count := ((List.range (total + 1)).filter (fun n => lowest ≤ n ∧ splitAtBreak k true total n = n)).headD total
    let chosen := (vs.take count).join
    let noteCount : Nat := (chosen.map noteLines).foldr (· + ·) 0
    let sep : Int := if 0 < noteCount ∧ !hasNotes then separator else 0
    let following :=
      match count == total, keepAhead rest with
      | true, some (_, f, later) =>
        firstNeed pagePitch separator capacity (hasNotes || chosen.any (fun l => !l.notes.isEmpty)) f later
      | _, _ => 0
    sumInt (chosen.map (fun l => pitchOf l.id)) + sep + (noteCount : Int) * pagePitch + following
  | .space s :: rest => s + firstNeed pagePitch separator capacity hasNotes wanted rest
  | .blank n :: rest => (n : Int) * pagePitch + firstNeed pagePitch separator capacity hasNotes wanted rest
  | .needLines _ :: rest | .adjustLines _ :: rest | .noBreak :: rest
  | .noBreakLines _ :: rest | .keepNext _ _ :: rest => firstNeed pagePitch separator capacity hasNotes wanted rest
  | .figure _ e :: _ => e
  | .wrapped _ e _ :: _ => e
  | .table _ before header rows caption below :: _ =>
    let chosen := header ++ rows.headD [] ++ (if !below || rows.length ≤ 1 then caption else [])
    let extent := before + (chosen.length : Int) * pagePitch
    let complete := extent + noteNeed pagePitch separator hasNotes chosen
    let noted := chosen.any (fun l => !l.notes.isEmpty)
    let minimumNotes : Int := if noted then pagePitch + (if hasNotes then 0 else separator) else 0
    if complete ≤ capacity then complete else extent + minimumNotes
  | .heading true _ _ :: _ => 0
  | .heading false extent ls :: rest =>
    extent + noteNeed pagePitch separator hasNotes ls +
      firstNeed pagePitch separator capacity (hasNotes || ls.any (fun l => !l.notes.isEmpty)) 1 rest
  | .code caption first continued spans rows :: _ =>
    let count := min rows.length (max first (max 1 wanted))
    caption + (codeSpanOf spans (count + if continued ∧ count < rows.length then 1 else 0) : Int) * pagePitch
  | .defTerm ls :: _ => sumInt (ls.map (fun l => pitchOf l.id)) + noteNeed pagePitch separator hasNotes ls
  | _ => 0
where
  noteNeed (pagePitch separator : Int) (hasNotes : Bool) (ls : List Line) : Int :=
    let c : Nat := (ls.map noteLines).foldr (· + ·) 0
    (if 0 < c ∧ !hasNotes then separator else 0) + (c : Int) * pagePitch
  paragraphNeed (pagePitch separator capacity : Int) (hasNotes : Bool) (wanted : Nat) (k : Keep) (start : Bool)
      (ls : List Line) (rest : List Flow) : Int :=
    let total := ls.length
    let lowest := max (firstPart k start total) (min total (max 1 wanted))
    let count := ((List.range (total + 1)).filter (fun n => lowest ≤ n ∧ splitAtBreak k start total n = n)).headD total
    let chosen := ls.take count
    let noteCount : Nat := (chosen.map noteLines).foldr (· + ·) 0
    let sep : Int := if 0 < noteCount ∧ !hasNotes then separator else 0
    let lineNeed := sumInt (chosen.map (fun l => pitchOf l.id)) + sep + (noteCount : Int) * pagePitch
    let following :=
      match count == total, keepAhead rest with
      | true, some (_, f, later) =>
        firstNeed pagePitch separator capacity (hasNotes || chosen.any (fun l => !l.notes.isEmpty)) f later
      | _, _ => 0
    lineNeed + following

def boundaryEnv (cap sep : Int) (cols : Nat) : Env :=
  { pagePitch := 10, fontSize := 10, capacity := cap, maxCapacity := cap + 20, separator := sep,
    columns := cols, firstLine := 0, pitchOf := pitchOf, faceOf := faceOf,
    headingBounds := fun i => if i = 385 then some (4, 16) else none,
    wrappedBefore := fun i => if i = 702 ∨ i = 705 then 3 else if i = 712 then 5 else 0,
    boxPadding := fun i => if i = 170 then some 3 else none,
    firstNeed := firstNeed 10 sep cap, retention := none, held := fun _ => false }

def int! (s : String) : Int := s.toInt!
def nat! (s : String) : Nat := s.toNat!

def keepOf (s : String) : Keep :=
  match s.splitOn "," with
  | [f, l, a] => ⟨nat! f, nat! l, a == "1"⟩
  | _ => panic! s!"keep {s}"

def lineOf (s : String) : Line :=
  match s.splitOn "^" with
  | i :: notes => ⟨nat! i, notes.map (fun n => match n.splitOn "." with
      | [a, b] => ⟨nat! a, nat! b⟩
      | _ => panic! s!"note {n}"), 0⟩
  | [] => panic! "line"

def linesOf (s : String) : List Line := (s.splitOn ",").map lineOf
def linesOr (s : String) : List Line := if s == "" then [] else linesOf s

def sideOf (s : String) : Option RuleSide :=
  if s == "-" then none
  else match s.splitOn "," with
    | [i, o, w, sp, out] => some ⟨int! i, int! o, int! w, sp == "1", if out == "-" then none else some (int! out)⟩
    | _ => panic! s!"side {s}"

def breakOf : String → BreakKind
  | "c" => .column
  | "p" => .page
  | "r" => .recto
  | _ => .verso

def flowOf (s : String) : Flow :=
  match s.splitOn ":" with
  | ["p", k, ls] => .paragraph (keepOf k) (linesOr ls)
  | ["c", k, ls] => .continued (keepOf k) (linesOf ls)
  | ["f", i, e] => .figure (nat! i) (int! e)
  | ["g", i, b, h, rs, c, bl] =>
    .table (nat! i) (int! b) (linesOr h) (if rs == "" then [] else (rs.splitOn "/").map linesOr) (linesOr c) (bl == "1")
  | ["X", i, b, a, k, ls] => .boxed (nat! i) (int! b) (int! a) [.paragraph (keepOf k) (linesOr ls)]
  | ["Y", i, b, a, k, vs] => .boxed (nat! i) (int! b) (int! a) [.stanza (keepOf k) ((vs.splitOn "/").map linesOr)]
  | ["w", i, e, ls] => .wrapped (nat! i) (int! e) (if ls == "" then [] else linesOf ls)
  | ["t", i] => .pageFigure (nat! i)
  | ["s", n] => .space (int! n)
  | ["b", n] => .blank (nat! n)
  | ["k", k] => .brk (breakOf k)
  | ["n", n] => .needLines (nat! n)
  | ["a", n] => .adjustLines (int! n)
  | ["B"] => .noBreak
  | ["L", n] => .noBreakLines (nat! n)
  | ["K", n] => .keepNext (nat! n) 0
  | ["h", r, e, ls] => .heading (r == "1") (int! e) (linesOf ls)
  | ["d", ls] => .defTerm (linesOf ls)
  | ["x", c, f, k, sp, ls] => .code (int! c) (nat! f) (k == "1") ((sp.splitOn ",").map nat!) (linesOf ls)
  | ["v", k, vs] => .stanza (keepOf k) ((vs.splitOn "/").map linesOf)
  | ["S", k] => .start (breakOf k)
  | ["W", c] => .switchColumns (nat! c)
  | ["R"] => .restoreColumns
  | ["r", i, b, a, j, o, k, ls] =>
    .ruled ⟨nat! i, sideOf b, sideOf a, j == "1", int! o, keepOf k, linesOf ls, none⟩
  | ["q", i, b, a, j, o, r, e, ls] =>
    .ruled ⟨nat! i, sideOf b, sideOf a, j == "1", int! o, defaultKeep, linesOf ls, some (r == "1", int! e)⟩
  | _ => panic! s!"flow {s}"

def unitOf : String → PartUnit
  | "c" => .column
  | "p" => .page
  | _ => .spread

def unitToken : PartUnit → String
  | .column => "c"
  | .page => "p"
  | .spread => "s"

/-- The flows of an input line: a box `O:id:before:after:n` and a book part
    `P:unit:ids:n` hold the `n` flows after them. -/
partial def flowsOf : Nat → List String → List Flow × List String
  | 0, ts => ([], ts)
  | _ + 1, [] => ([], [])
  | n + 1, t :: ts =>
    let (f, rest) :=
      match t.splitOn ":" with
      | ["O", i, b, a, c] =>
        let (body, rest) := flowsOf (nat! c) ts
        (Flow.boxed (nat! i) (int! b) (int! a) body, rest)
      | ["P", u, ids, c] =>
        let (body, rest) := flowsOf (nat! c) ts
        (Flow.bookPart (unitOf u) (if ids == "-" then [] else (ids.splitOn ",").map nat!) body, rest)
      | _ => (flowOf t, ts)
    let (more, rest') := flowsOf n rest
    (f :: more, rest')

def slotToken : Int × Slot → String
  | (p, .line i) => s!"{p}:L{i}"
  | (p, .figure i) => s!"{p}:F{i}"
  | (p, .pageFigure i) => s!"{p}:T{i}"
  | (p, .heading i n) => s!"{p}:H{i}.{n}"
  | (p, .code ids g) => s!"{p}:C{ids.headD 0}.{ids.length}.{g}"
  | (p, .wrapped i) => s!"{p}:W{i}"
  | (p, .repeated i) => s!"{p}:L{i}"

def unmetToken : Unmet → String
  | .needLines n => s!"!need{n}"
  | .noBreak => "!nobreak"
  | .keepNext _ => "!keepnext"
  | .adjust n why => s!"!adjust{n}:" ++ (match why with | .noRoom => "room" | .linesPlaced => "placed" | .oneLine => "one")
  | .droppedBlank => "!dropped"
  | .splitKept i => s!"!split{i}"
  | .shortPart true i w g => s!"!first{i}:{w}:{g}"
  | .shortPart false i w g => s!"!last{i}:{w}:{g}"
  | .tallHeading i e r => s!"!tall{i}:{e}:{r}"
  | .splitPart t u => s!"!splitpart:{if t then "table" else "part"}:{unitToken u}"

def pageToken (p : PageOut) : String :=
  " ".intercalate (["out", toString p.number, toString p.column, if p.blank then "blank" else "-", toString p.limit]
    ++ p.slots.map slotToken
    ++ p.notes.map (fun (i, f, n) => s!"n{i}:{f}:{n}")
    ++ p.unmet.map unmetToken)

def failureToken : Failure → String
  | .lineTooTall i => s!"line{i}"
  | .footnoteTooTall i => s!"note{i}"
  | .figureTooTall i => s!"figure{i}"
  | .headingTooTall i => s!"heading{i}"
  | .codeTooTall i => s!"code{i}"
  | .tableTooTall i => s!"table{i}"
  | .tableCaptionTooTall i => s!"tablecaption{i}"
  | .boxTooTall i => s!"box{i}"
  | .noProgress _ => "loop"

def run (input : String) : List String :=
  match input.splitOn " " with
  | "in" :: cap :: sep :: cols :: flows =>
    match paginate (boundaryEnv (int! cap) (int! sep) (nat! cols)) (flowsOf flows.length flows).1 with
    | .error e => [s!"out fail {failureToken e}"]
    | .ok pages => pages.map pageToken
  | _ => []

def finish (env : Env) (st : St) : List PageOut :=
  match (close env (drainCarry env st)).done.reverse with
  | [] => [⟨1, 0, false, [], [], env.capacity, []⟩]
  | pages => pages

def keepTok (k : Keep) : String := s!"{k.first},{k.last},{if k.all then 1 else 0}"

/-- The result of a trial, and of one more trial of a part moved on. -/
partial def shownWrap (env : Env) (lim : Option Nat) (start : Bool) (rows : List Line) (again : Bool) :
    Except Failure (Region × Part) → List String
  | .error f => [s!"out fail {failureToken f}"]
  | .ok (region, .moved st kk) =>
    s!"part moved {keepTok kk}" ::
      (if again then shownWrap env lim start rows false ((trialWrap env region lim kk start st rows).map (fun p => (region, p)))
       else (finish env st).map pageToken)
  | .ok (_, .placed n st kk) => s!"part placed {n} {keepTok kk}" :: (finish env st).map pageToken

/-- A `tw` line of PhysicalBoundary.hs: `trialWrap` after the flows before
    it and `beginWrap`. -/
def runWrap (input : String) : List String :=
  match input.splitOn " " with
  | "tw" :: cap :: sep :: cols :: e :: lim :: p :: s :: pre =>
    let env := boundaryEnv (int! cap) (int! sep) (nat! cols)
    let flows := (flowsOf pre.length pre).1
    let (k, rows) := match flowOf p with
      | .paragraph k ls => (k, ls)
      | _ => (defaultKeep, [])
    let lim := if lim == "-" then none else some (nat! lim)
    let result : Except Failure (Region × Part) :=
      match checkNotes env flows with
      | some f => .error f
      | none =>
        match placeAll (level (flowsDepth flows)) env (initial env) flows with
        | .error f => .error f
        | .ok st =>
          match beginWrap env st 150 (int! e) with
          | .error f => .error f
          | .ok (st2, region) => (trialWrap env region lim k (s == "1") st2 rows).map (fun p => (region, p))
    shownWrap env lim (s == "1") rows true result
  | _ => []

end PhysicalBoundary

def main (args : List String) : IO Unit := do
  match args with
  | [path] =>
    let text ← IO.FS.readFile path
    let out ← IO.getStdout
    for l in text.splitOn "\n" do
      if l.startsWith "in " then
        out.putStrLn l
        for o in PhysicalBoundary.run l do
          out.putStrLn o
      else if l.startsWith "tw " then
        out.putStrLn l
        for o in PhysicalBoundary.runWrap l do
          out.putStrLn o
  | _ => throw (IO.userError "usage: PhysicalBoundary.lean <inputs>")
