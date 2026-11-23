/- Root ADR 0352, condition 2: the values of the evaluation of
   `Golem.Layout.KnuthPlass` on Pagination.lean's transcription.

   `CheckCaptionAssembly.hs --values` writes, for each input, a line
   "in ..." and the line "out ..." that golem-layout gives for it.  This
   file reads the "in" lines (the file named by its argument) and prints,
   for each, what the definitions of Pagination.lean give:

   * `bad t s`, `fit shrinking b`, `dem linePenalty b penalty`: the
     formulas `badness`, `fitnessOf` and `lineDemerits` against
     `captionBadness`, `captionFitness` and `captionLineDemerits`, on
     boundary values;
   * `obs ...`: a caption the breaker broke, with its items, its
     parameters, its line width and the breaks the breaker chose.  The
     lines run from `captionLineRanges`, their natural widths are
     differences of the cumulative `captionSum`, and `evaluate` of
     KnuthPlass.hs is `captionWidthEvaluation` and `captionPathCost` on
     them.  It prints the demerits of the path (but in the overfull pass,
     whose rescued and pushed-out lines the breaks do not tell apart) and,
     for each line, the adjustment ratio and the overflow of `mkLine`.  The
     glyphs are not expanded (`pExpansion` is `Nothing`), so the
     compression of `captionWidthEvaluation` is 0.

   check.sh compares the output with the "out" lines by diff.  This is a
   check on finitely many inputs, not a proof. -/
import Pagination
open GolemPagination

namespace CaptionValues

/-- An item of the breaker with every field `evaluate` and `mkLine` read. -/
structure Item where
  kind : CaptionItemKind
  width : Int
  stretch : Int := 0
  shrink : Int := 0
  protrudeStart : Int := 0
  protrudeEnd : Int := 0
  edgeStart : Int := 0
  edgeEnd : Int := 0
  flagged : Bool := false
  /-- The protrusion of the hyphen drawn at a break of the patterns or at
      a soft hyphen. -/
  hyphenEnd : Option Int := none

instance : Inhabited Item := ⟨{ kind := .glue, width := 0 }⟩

def Item.measured (i : Item) : MeasuredCaptionItem := ⟨i.kind, i.width⟩

def Item.isBox (i : Item) : Bool := match i.kind with | .box => true | _ => false

structure Params where
  pass : Nat
  linePenalty : Int
  adjDemerits : Int
  doubleHyphen : Int
  endStretch : Int
  emergency : Int
  pullInFirst : Bool
  protrusion : Bool
  width : Int

/-- `tW` of the items before `i`: the cumulative width. -/
def cumulativeWidth (items : List Item) (i : Nat) : Int :=
  captionSum ((items.take i).map Item.measured)

/-- `tY` and `tZ` of the items before `i`: the cumulative stretch and
    shrink of the glue. -/
def cumulative (f : Item → Int) (items : List Item) (i : Nat) : Int :=
  (items.take i).foldl (fun acc item => acc + f item) 0

def glueStretch (i : Item) : Int := match i.kind with | .glue => i.stretch | _ => 0
def glueShrink (i : Item) : Int := match i.kind with | .glue => i.shrink | _ => 0

/-- The values `evaluate` and `mkLine` share for the line from `s` to the
    break `b`: natural width, glue stretch, glue shrink.  As in
    KnuthPlass.hs, they are differences of the cumulative sums, so a break
    inside the items skipped after the break before it (`s > b`) gives
    negative sums. -/
def lineSums (ps : Params) (items : List Item) (s b : Nat) : Int × Int × Int :=
  let line := (items.drop s).take (b - s)
  let atBreak := items.getD b default
  let boxes := line.filter Item.isBox
  let firstBox := boxes.head?
  let lastBox := boxes.getLast?
  let protS := if ps.protrusion then (firstBox.map (·.protrudeStart)).getD 0 else 0
  let protE := if ps.protrusion then
      match atBreak.kind, atBreak.hyphenEnd with
      | .penalty _ _, some q => q
      | _, _ => (lastBox.map (·.protrudeEnd)).getD 0
    else 0
  let edgeS := (firstBox.map (·.edgeStart)).getD 0
  let edgeE := (lastBox.map (·.edgeEnd)).getD 0
  let natural := cumulativeWidth items b - cumulativeWidth items s
    + atBreak.measured.breakWidth - protS - protE + edgeS + edgeE
  (natural, cumulative glueStretch items b - cumulative glueStretch items s,
    cumulative glueShrink items b - cumulative glueShrink items s)

def penaltyAt (items : List Item) (b : Nat) : Int :=
  match (items.getD b default).kind with | .penalty p _ => p | _ => 0

/-- The demerits of the path of `evaluate` along the breaks, from the
    start node of fitness decent and not flagged.  It is not the demerits
    of the overfull pass, whose lines may be rescued with
    `overfullDemerits` or pushed out (`pushOut`), which the breaks alone do
    not tell apart. -/
def pathDemerits (ps : Params) (items : List Item) (breaks : List Nat) : Int :=
  let kinds := items.map (·.kind)
  let step := fun (acc : Int × Int × Bool) (r : Nat × Nat) =>
    let (total, previousFitness, previousFlagged) := acc
    let (s, b) := r
    let (natural, stretch, shrink) := lineSums ps items s b
    let emergency := if 3 ≤ ps.pass then ps.emergency else 0
    let (bad, shrinking, _) :=
      captionWidthEvaluation (ps.width - natural) (stretch + emergency + ps.endStretch) shrink 0 ps.pullInFirst
    let flagged := (items.getD b default).flagged
    (captionPathCost total previousFitness ps.linePenalty (penaltyAt items b) ps.doubleHyphen
      ps.adjDemerits previousFlagged flagged shrinking bad,
      captionFitness shrinking bad, flagged)
  ((captionLineRanges kinds 0 breaks).foldl step (0, 2, false)).1

/-- A rational as Haskell's `numerator` and `denominator` show it. -/
def ratioText (n d : Int) : String :=
  let g : Int := (Nat.gcd n.natAbs d.natAbs : Nat)
  let (n, d) := if d < 0 then (-n, -d) else (n, d)
  if g = 0 then "0/1" else s!"{n / g}/{d / g}"

/-- The ratio and the overflow of `mkLine`. -/
def lineText (ps : Params) (items : List Item) (r : Nat × Nat) : String :=
  let (natural, stretch, shrink) := lineSums ps items r.1 r.2
  let shortfall := ps.width - natural
  let ratio :=
    if 0 < shortfall ∧ 0 < stretch then ratioText shortfall stretch
    else if shortfall < 0 ∧ 0 < shrink then
      (if shortfall < -shrink then "-1/1" else ratioText shortfall shrink)
    else "0/1"
  s!"{ratio}:{max 0 (natural - shrink - ps.width)}"

/-! ## Reading the input -/

def int! (s : String) : Int := s.toInt?.getD 0
def nat! (s : String) : Nat := s.toNat?.getD 0

def item (token : String) : Item :=
  match token.splitOn ":" with
  | ["b", w, ps, pe, es, ee] =>
    { kind := .box, width := int! w, protrudeStart := int! ps, protrudeEnd := int! pe,
      edgeStart := int! es, edgeEnd := int! ee }
  | ["g", w, y, z] => { kind := .glue, width := int! w, stretch := int! y, shrink := int! z }
  | ["p", w, p, f, h] =>
    { kind := .penalty (int! p) false, width := int! w, flagged := f == "1",
      hyphenEnd := if h == "-" then none else some (int! h) }
  | _ => { kind := .box, width := 0 }

def answer (line : String) : String :=
  match line.splitOn " " with
  | ["in", "bad", t, s] => toString (captionBadness (nat! t) (int! s))
  | ["in", "fit", sh, b] => toString (captionFitness (sh == "1") (nat! b))
  | ["in", "dem", lp, b, p] => toString (captionLineDemerits (int! lp) (nat! b) (int! p))
  | "in" :: "obs" :: pass :: lp :: adj :: dbl :: endStretch :: emergency :: pull :: prot :: width :: rest =>
    let ps : Params :=
      { pass := nat! pass, linePenalty := int! lp, adjDemerits := int! adj, doubleHyphen := int! dbl,
        endStretch := int! endStretch, emergency := int! emergency, pullInFirst := pull == "1",
        protrusion := prot == "1", width := int! width }
    let items := (rest.takeWhile (· != "|")).map item
    let breaks := ((rest.dropWhile (· != "|")).drop 1).map nat!
    let ranges := captionLineRanges (items.map (·.kind)) 0 breaks
    " ".intercalate ((if ps.pass < 4 then toString (pathDemerits ps items breaks) else "-")
      :: ranges.map (lineText ps items))
  | _ => s!"unread: {line}"

end CaptionValues

def main (args : List String) : IO Unit := do
  let text ← IO.FS.readFile (args.headD "/dev/stdin")
  for line in text.splitOn "\n" do
    if line.startsWith "in " then IO.println ("out " ++ CaptionValues.answer line)
