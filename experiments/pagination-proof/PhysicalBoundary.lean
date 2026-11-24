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
partial def firstNeed (pagePitch separator : Int) (hasNotes : Bool) (wanted : Nat) : List Flow → Int
  | .paragraph k ls :: rest => paragraphNeed pagePitch separator hasNotes wanted k true ls rest
  | .continued k ls :: rest => paragraphNeed pagePitch separator hasNotes wanted k false ls rest
  | .space s :: rest => s + firstNeed pagePitch separator hasNotes wanted rest
  | .blank n :: rest => (n : Int) * pagePitch + firstNeed pagePitch separator hasNotes wanted rest
  | .needLines _ :: rest | .adjustLines _ :: rest | .noBreak :: rest
  | .noBreakLines _ :: rest | .keepNext _ :: rest => firstNeed pagePitch separator hasNotes wanted rest
  | .figure _ e :: _ => e
  | .heading true _ _ :: _ => 0
  | .heading false extent ls :: rest =>
    extent + noteNeed pagePitch separator hasNotes ls +
      firstNeed pagePitch separator (hasNotes || ls.any (fun l => !l.notes.isEmpty)) 1 rest
  | .defTerm ls :: _ => sumInt (ls.map (fun l => pitchOf l.id)) + noteNeed pagePitch separator hasNotes ls
  | _ => 0
where
  noteNeed (pagePitch separator : Int) (hasNotes : Bool) (ls : List Line) : Int :=
    let c : Nat := (ls.map noteLines).foldr (· + ·) 0
    (if 0 < c ∧ !hasNotes then separator else 0) + (c : Int) * pagePitch
  paragraphNeed (pagePitch separator : Int) (hasNotes : Bool) (wanted : Nat) (k : Keep) (start : Bool)
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
        firstNeed pagePitch separator (hasNotes || chosen.any (fun l => !l.notes.isEmpty)) f later
      | _, _ => 0
    lineNeed + following

def boundaryEnv (cap sep : Int) (cols : Nat) : Env :=
  { pagePitch := 10, fontSize := 10, capacity := cap, maxCapacity := cap + 20, separator := sep,
    columns := cols, firstLine := 0, pitchOf := pitchOf, faceOf := faceOf,
    firstNeed := firstNeed 10 sep }

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
  | ["p", k, ls] => .paragraph (keepOf k) (linesOf ls)
  | ["c", k, ls] => .continued (keepOf k) (linesOf ls)
  | ["f", i, e] => .figure (nat! i) (int! e)
  | ["t", i] => .pageFigure (nat! i)
  | ["s", n] => .space (int! n)
  | ["b", n] => .blank (nat! n)
  | ["k", k] => .brk (breakOf k)
  | ["n", n] => .needLines (nat! n)
  | ["a", n] => .adjustLines (int! n)
  | ["B"] => .noBreak
  | ["L", n] => .noBreakLines (nat! n)
  | ["K", n] => .keepNext (nat! n)
  | ["h", r, e, ls] => .heading (r == "1") (int! e) (linesOf ls)
  | ["d", ls] => .defTerm (linesOf ls)
  | ["S", k] => .start (breakOf k)
  | ["W", c] => .switchColumns (nat! c)
  | ["R"] => .restoreColumns
  | ["r", i, b, a, j, o, k, ls] =>
    .ruled ⟨nat! i, sideOf b, sideOf a, j == "1", int! o, keepOf k, linesOf ls⟩
  | _ => panic! s!"flow {s}"

def slotToken : Int × Slot → String
  | (p, .line i) => s!"{p}:L{i}"
  | (p, .figure i) => s!"{p}:F{i}"
  | (p, .pageFigure i) => s!"{p}:T{i}"
  | (p, .heading i n) => s!"{p}:H{i}.{n}"

def unmetToken : Unmet → String
  | .needLines n => s!"!need{n}"
  | .noBreak => "!nobreak"
  | .keepNext => "!keepnext"
  | .adjust n why => s!"!adjust{n}:" ++ (match why with | .noRoom => "room" | .linesPlaced => "placed" | .oneLine => "one")
  | .droppedBlank => "!dropped"
  | .splitKept i => s!"!split{i}"
  | .shortPart true i w g => s!"!first{i}:{w}:{g}"
  | .shortPart false i w g => s!"!last{i}:{w}:{g}"
  | .tallHeading i e r => s!"!tall{i}:{e}:{r}"

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

def run (input : String) : List String :=
  match input.splitOn " " with
  | "in" :: cap :: sep :: cols :: flows =>
    match paginate (boundaryEnv (int! cap) (int! sep) (nat! cols)) (flows.map flowOf) with
    | .error e => [s!"out fail {failureToken e}"]
    | .ok pages => pages.map pageToken
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
  | _ => throw (IO.userError "usage: PhysicalBoundary.lean <inputs>")
