{- | The box model of the layout (root ADR 0437): the areas text is set in
and the areas text keeps out of are boxes, each of a shape, a closed
path. A box that text is set in has, besides, its writing (horizontal or
vertical) and the edge of the bounding rectangle of its shape that its
lines start from. The type area, the columns, the areas of sidenotes and
the text frames are boxes text is set in; an exclusion of wrapping is a
box text keeps out of. The areas of today are boxes of a rectangle, and
the layout keeps them as rectangles ('Rect') where it needs speed; an
exclusion keeps its side, width and count of lines for now.

These boxes are not the boxes of paragraph styles (Golem.Typeset.Box,
docs/adr/0271) nor the line boxes of docs/adr/0397.

Text is set in a box of any closed shape line by line: the bands of the
lines, each as high as the size of the type, the first touching the edge
the lines start from and each next one a line pitch further; in each
band, the intervals of the line that are inside the shape over the whole
band ('stripInside', on the shape made a polygon); of those at least
eight times the size of the type wide, the first in the writing. A band
with no such interval is skipped. Each line is broken to the width of
its interval by the unchanged line breaking.
-}
module Golem.Layout.BoxModel
  ( LayoutBox (..),
    BoxRole (..),
    Writing (..),
    LineStart (..),
    textBox,
    avoidBox,
    rectBox,
    LineSlot (..),
    lineSlots,
    BoxOverflow (..),
    flowInBox,
  )
where

import Golem.Geometry (FillRule (..), Path (..), Rect (..), rectPath)
import Golem.Geometry.Polygon (RPoint, flattenPath, stripInside)
import Golem.Layout.KnuthPlass (Item, Line (..), Params, brLines, breakParagraph, lineOverfull)
import Golem.Length (Sp (..))

-- | A box: its shape, the rule of the inside of its shape, and what it does with text.
data LayoutBox = LayoutBox {boxShape :: !Path, boxFillRule :: !FillRule, boxRole :: !BoxRole}
  deriving stock (Eq, Show)

-- | A box sets text in its shape, in a writing from an edge, or keeps text out.
data BoxRole = SetsText !Writing !LineStart | KeepsTextOut
  deriving stock (Eq, Show)

-- | Horizontal writing: lines from left to right; vertical writing: lines from top to bottom.
data Writing = Horizontal | Vertical
  deriving stock (Eq, Show)

{- | The edge of the bounding rectangle the lines start from: the usual one
(the top in horizontal writing, the right in vertical writing) or the
opposite one (the bottom, the left).
-}
data LineStart = UsualStart | OppositeStart
  deriving stock (Eq, Show)

-- | A box that sets text in a shape, from the usual edge, inside by the nonzero rule.
textBox :: Writing -> Path -> LayoutBox
textBox w p = LayoutBox p NonZero (SetsText w UsualStart)

-- | A box that keeps text out of a shape, inside by the nonzero rule.
avoidBox :: Path -> LayoutBox
avoidBox p = LayoutBox p NonZero KeepsTextOut

-- | A box of a rectangle that sets text, as the areas of the page are.
rectBox :: Writing -> Rect -> LayoutBox
rectBox w = textBox w . rectPath

{- | Where a line of a box goes: the number of its band from 0, and the
rectangle on the page of its interval in its band, as long as the line
and as high (in vertical writing, as wide) as the size of the type.
-}
data LineSlot = LineSlot {slotBand :: !Int, slotRect :: !Rect}
  deriving stock (Eq, Show)

{- | The lines of a box, in order, for a size of type and a line pitch; none
for a box that keeps text out, or of no line pitch. The bands go from the
edge the lines start from, rounded into the shape to sp; the ends of an
interval are rounded into it to sp.
-}
lineSlots :: LayoutBox -> Sp -> Sp -> [LineSlot]
lineSlots box size pitch = case boxRole box of
  KeepsTextOut -> []
  SetsText writing start
    | pitch <= 0 || size <= 0 -> []
    | otherwise ->
        let polys = flattenPath (boxShape box)
            pts = concat polys
         in case pts of
              [] -> []
              _ ->
                let frame = frameOf writing start pts
                    canon = map (map (toFrame frame)) polys
                    extent = fExtent frame
                    bands = takeWhile (\k -> toRational (unSp (pitch * Sp (toInteger k) + size)) <= extent) [0 :: Int ..]
                 in [ LineSlot k (slotOnPage frame w0 size u0 u1)
                    | k <- bands,
                      let w0 = unSp pitch * toInteger k,
                      (u0, u1) <- take 1 (usable (stripInside (boxFillRule box) canon (toRational w0) (toRational (w0 + unSp size))))
                    ]
  where
    -- the intervals, rounded into themselves, at least eight times the size wide
    usable ivs = [(a, b) | (a', b') <- ivs, let a = ceiling a', let b = floor b', b - a >= 8 * unSp size]

{- | The frame of the lines of a box: u along the lines, w across them from
the edge they start from, and where on the page that edge and u = 0 are.
-}
data Frame = Frame
  { fWriting :: !Writing,
    fStart :: !LineStart,
    -- | the edge the lines start from, rounded into the shape
    fEdge :: !Integer,
    -- | the distance across the lines from that edge to the opposite one
    fExtent :: !Rational
  }

frameOf :: Writing -> LineStart -> [RPoint] -> Frame
frameOf writing start pts =
  let xs = map fst pts
      ys = map snd pts
      (lo, hi) = case writing of
        Horizontal -> (minimum ys, maximum ys)
        Vertical -> (minimum xs, maximum xs)
      edge = case start of
        UsualStart -> floor hi
        OppositeStart -> ceiling lo
      extent = case start of
        UsualStart -> toRational edge - lo
        OppositeStart -> hi - toRational edge
   in Frame writing start edge extent

-- | A point of the page in the frame: u along the lines, w across them from the edge.
toFrame :: Frame -> RPoint -> RPoint
toFrame f (x, y) =
  let e = toRational (fEdge f)
      w = case (fWriting f, fStart f) of
        (Horizontal, UsualStart) -> e - y
        (Horizontal, OppositeStart) -> y - e
        (Vertical, UsualStart) -> e - x
        (Vertical, OppositeStart) -> x - e
      u = case fWriting f of
        Horizontal -> x
        Vertical -> negate y
   in (u, w)

-- | The rectangle on the page of an interval of u in the band from w0 as wide as the size.
slotOnPage :: Frame -> Integer -> Sp -> Integer -> Integer -> Rect
slotOnPage f w0 (Sp size) u0 u1 =
  let e = fEdge f
      len = Sp (u1 - u0)
      across = case fStart f of
        UsualStart -> e - w0 - size
        OppositeStart -> e + w0
   in case fWriting f of
        Horizontal -> Rect (Sp u0) (Sp across) len (Sp size)
        Vertical -> Rect (Sp across) (Sp (negate u1)) (Sp size) len

{- | The content does not fit in the box: more lines than the box has, a
line longer than its interval, or content in a box of no line.
-}
data BoxOverflow = BoxOverflow
  deriving stock (Eq, Show)

{- | Sets paragraphs in a box: each paragraph broken by the line breaking
to the widths of the lines of the box left, line by line. No paragraph,
or only empty ones, fit in any box.
-}
flowInBox :: Params -> LayoutBox -> Sp -> Sp -> [[Item]] -> Either BoxOverflow [[(LineSlot, Line)]]
flowInBox params box size pitch = go (lineSlots box size pitch)
  where
    go _ [] = Right []
    go slots ([] : rest) = ([] :) <$> go slots rest
    go slots (items : rest) = case slots of
      [] -> Left BoxOverflow
      lastSlot : _ ->
        let widths = map (rectLength . slotRect) slots
            width i = case drop i widths of
              w : _ -> w
              [] -> rectLength (slotRect (last' lastSlot slots))
            ls = brLines (breakParagraph params width items)
            n = length ls
         in if n > length slots || any lineOverfull ls
              then Left BoxOverflow
              else (zip slots ls :) <$> go (drop n slots) rest
    rectLength r = case boxRole box of
      SetsText Vertical _ -> rectH r
      _ -> rectW r
    last' d = \case
      [] -> d
      xs -> last xs
