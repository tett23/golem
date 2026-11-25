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
     compression of `captionWidthEvaluation` is 0;
   * after `|`, the pass, the breaks and the demerits of `captionCompared`,
     the breaker of Pagination.lean on the same items, against those of
     `breakParagraph`;
   * `fig ...`: a caption of CaptionFonts.hs, in the advances of a real
     font, with the sizes of its column and its image.  It prints the
     pass, the breaks and the demerits of `captionCompared`, the grid
     lines `captionGridSpan` gives its lines, and the image lines and the
     size along and across the lines of `fitCaptionedFigure`, or G07038,
     against what golem-typeset placed.

   check.sh compares the output with the "out" lines by diff.  This is a
   check on finitely many inputs, not a proof. -/
import Pagination
open GolemPagination

namespace CaptionValues

/-- The items and the parameters are those of Pagination.lean's breaker
    (`CaptionItem`, `CaptionParams`); `pass` is the pass golem-layout
    broke the caption in. -/
abbrev Item := CaptionItem

structure Params where
  pass : Nat
  params : CaptionParams

def lineSums (ps : Params) := captionLineSums ps.params
def penaltyAt := captionPenaltyAt

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
    let q := ps.params
    let (bad, shrinking, _) :=
      captionWidthEvaluation (q.width - natural) (stretch + captionPassEmergency q ps.pass + q.endStretch) shrink 0
        q.pullInFirst
    let flagged := (items.getD b default).flagged
    (captionPathCost total previousFitness q.linePenalty (penaltyAt items b) q.doubleHyphen
      q.adjDemerits previousFlagged flagged shrinking bad,
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
  let shortfall := ps.params.width - natural
  let ratio :=
    if 0 < shortfall ∧ 0 < stretch then ratioText shortfall stretch
    else if shortfall < 0 ∧ 0 < shrink then
      (if shortfall < -shrink then "-1/1" else ratioText shortfall shrink)
    else "0/1"
  s!"{ratio}:{max 0 (natural - shrink - ps.params.width)}"

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
  | "in" :: "obs" :: pass :: lp :: adj :: dbl :: endStretch :: emergency :: pull :: prot :: pretol :: tol :: width :: rest =>
    let params : CaptionParams :=
      ⟨int! pretol, int! tol, int! lp, int! adj, int! dbl, int! endStretch, int! emergency,
        pull == "1", prot == "1", int! width⟩
    let ps : Params := ⟨nat! pass, params⟩
    let items := (rest.takeWhile (· != "|")).map item
    let breaks := ((rest.dropWhile (· != "|")).drop 1).map nat!
    let ranges := captionLineRanges (items.map (·.kind)) 0 breaks
    -- the breaker of Pagination.lean on the same items: its pass, breaks and demerits
    let compared := match captionCompared ps.params items with
      | some (pass, node) =>
        s!"{pass} " ++ ",".intercalate ((captionComparedBreaks node).map toString) ++ s!" {node.demerits}"
      | none => "none"
    " ".intercalate ((if ps.pass < 4 then toString (pathDemerits ps items breaks) else "-")
      :: ranges.map (lineText ps items)) ++ " | " ++ compared
  | "in" :: "fig" :: capacity :: body :: pitch :: size :: along :: num :: den :: _ :: lp :: adj :: dbl ::
      endStretch :: emergency :: pull :: prot :: pretol :: tol :: width :: rest =>
    -- a caption of CaptionFonts.hs in real fonts: the breaks of
    -- `captionCompared`, the grid lines of its lines and the figure
    let params : CaptionParams :=
      ⟨int! pretol, int! tol, int! lp, int! adj, int! dbl, int! endStretch, int! emergency,
        pull == "1", prot == "1", int! width⟩
    let items := rest.map item
    match captionCompared params items with
    | none => "none"
    | some (pass, node) =>
      let breaks := captionComparedBreaks node
      match captionAssembleWhole CaptionItem.kind items breaks with
      | none => "unassembled"
      | some lines =>
        let span := captionGridSpan (nat! body) (nat! pitch) (nat! size) lines.length
        let figure := match fitCaptionedFigure (nat! capacity) span (nat! pitch) (nat! along) (nat! num) (nat! den) with
          | none => "G07038"
          | some (along', across') => s!"{(across' + nat! pitch - 1) / nat! pitch}:{along'}:{across'}"
        s!"{pass} " ++ ",".intercalate (breaks.map toString) ++ s!" {node.demerits} {span} {figure}"
  | _ => s!"unread: {line}"

end CaptionValues

def main (args : List String) : IO Unit := do
  let text ← IO.FS.readFile (args.headD "/dev/stdin")
  for line in text.splitOn "\n" do
    if line.startsWith "in " then IO.println ("out " ++ CaptionValues.answer line)
