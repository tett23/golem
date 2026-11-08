{- | The alignment of the lines of a paragraph (docs/adr/0189). A paragraph
whose lines are not justified is broken as LaTeX's \raggedright breaks:
its glue does not stretch, its glyphs do not expand, and every line ends
with a stretch of 'filStretch', so that every line has badness 0. Its
lines are set at their natural widths and shifted by the difference
between the line and its contents. A justified paragraph is broken as
before; only its last line is shifted, or set as wide as the others.
-}
module Golem.Layout.Align
  ( LineAlign (..),
    ParaAlign (..),
    breakAligned,
    lineShift,
    lineSlack,
  )
where

import Golem.Layout.KnuthPlass

-- | Where a line that is not justified goes: the start, the centre or the end of the line.
data LineAlign = LineStart | LineCenter | LineEnd
  deriving stock (Eq, Show)

{- | The alignment of a paragraph: every line set as one 'LineAlign', or
every line but the last justified and the last set as a 'LineAlign', or
justified too ('Nothing').
-}
data ParaAlign = Ragged LineAlign | Justified (Maybe LineAlign)
  deriving stock (Eq, Show)

{- | Breaks a paragraph of an alignment. A ragged paragraph: the stretch of
its glue is 0 (its shrink stays), no expansion, 'filStretch' at the end
of every line. A fully justified one is broken as the others; the stretch
of the glue that ends it is taken from its last line, so that the other
glue of the line takes up the rest (docs/adr/0211: without the glue at
the end, a short last line has the badness 10000 and the breaker splits
a one-line paragraph).
-}
breakAligned :: ParaAlign -> Params -> (Int -> Sp) -> [Item] -> Breaks
breakAligned a ps lineWidth items = case a of
  Ragged _ -> breakParagraph ps {pExpansion = Nothing, pEndStretch = filStretch} lineWidth (map rigid items)
  Justified (Just _) -> breakParagraph ps lineWidth items
  Justified Nothing ->
    let r = breakParagraph ps lineWidth items
     in r {brLines = onLast fillLast (brLines r)}
  where
    rigid = \case
      Glue w _ z -> Glue w 0 z
      x -> x
    onLast f = \case
      [] -> []
      ls -> init ls <> [f (last ls)]
    -- the paragraph end: the last glue of fill of the last line
    fillLast l =
      let (before, rest) = break isFill (reverse (lineItems l))
       in case rest of
            Glue w _ z : more -> l {lineItems = reverse (before <> (Glue w 0 z : more))}
            _ -> l
    isFill = \case
      Glue _ y _ -> y >= filStretch
      _ -> False

{- | The difference between the target width of a set line and the width
of its contents at their natural widths, or 0 when the line is shrunk or
filled. Meaningful for a line whose glue does not stretch.
-}
lineSlack :: Line -> Sp
lineSlack l =
  let its = lineItems l
      (protS, protE) = lineProtrusion l
      (edgeS, edgeE) = lineEdge l
      lastIx = length its - 1
      isPenalty = \case
        Penalty {} -> True
        _ -> False
      natural = sum [itemWidth it | (i, it) <- zip [0 :: Int ..] its, not (isPenalty it) || i == lastIx] - protS - protE + edgeS + edgeE
      ex = toRational (lineExpansion l) / 1000
      expandable = toRational (unSp (sum [w | Box w c <- its, bcExpandable c]))
      rest = toRational (unSp (lineTarget l - natural)) - expandable * ex
   in if rest > 0 then Sp (floor rest) else 0

{- | How far a set line moves toward the end of the line: the slack at the
end for the start, at the start for the end, half on either side for
the centre, the odd 1sp at the end. @final@ is whether the line is the
last of its paragraph.
-}
lineShift :: ParaAlign -> Bool -> Line -> Sp
lineShift a final l = case a of
  Ragged la -> by la
  Justified (Just la) | final -> by la
  _ -> 0
  where
    by = \case
      LineStart -> 0
      LineEnd -> lineSlack l
      LineCenter -> Sp (unSp (lineSlack l) `div` 2)
