{- | The boxes of paragraph styles (docs/adr/0271): which paragraphs go
into one box, the grid lines a box takes around its lines, its rectangle
in a column, its corners, and its background and border as marks.

Every length is an 'Sp'; the points of a path with round corners are
found as rationals and rounded to sp once, when they become marks.
-}
module Golem.Typeset.Box
  ( groupBoxes,
    boxLinesAround,
    boxLineRange,
    boxArea,
    Corners (..),
    cornerRadius,
    boxCorners,
    physicalCorners,
    Point,
    Segment (..),
    kappa,
    boxOutline,
    boxBorderRuns,
    boxBands,
    BoxPaint (..),
    boxMarks,
  )
where

import Golem.LayoutSpec (Rect (..))
import Golem.Pdf qualified as P
import Golem.Project.Style (BoxSide (..), RuleStyle (..), Sp (..))
import Golem.Typeset.RuleShape (RuleShape, ruleMarks, ruleShapes)

{- | Items into runs of boxes (docs/adr/0271, B4): an item with the key of
a box starts a box; the items between that may go into a box (spaces and
keep-with-next) and the next item of the same key join it. The items
between that no box of the same key follows stay out.
-}
groupBoxes :: (Eq k) => (a -> Maybe k) -> (a -> Bool) -> [a] -> [Either a (k, [a])]
groupBoxes keyOf passable = go
  where
    go [] = []
    go (x : xs) = case keyOf x of
      Nothing -> Left x : go xs
      Just k -> let (body, rest) = collect k [x] xs in Right (k, body) : go rest
    collect k acc xs =
      let (mid, rest) = span (\y -> passable y && null (keyOf y)) xs
       in case rest of
            y : more | keyOf y == Just k -> collect k (acc <> mid <> [y]) more
            _ -> (acc, xs)

{- | The grid lines a box takes before its first line and after its last,
for a line pitch p, a face of the grid h and a padding d (docs/adr/0271):
the fewest k of 0 or more with (p − h)/2 + k × p ≥ d, in one division.
-}
boxLinesAround :: Sp -> Sp -> Sp -> Int
boxLinesAround (Sp p) (Sp h) (Sp d) =
  let num = 2 * d - (p - h)
      den = 2 * p
   in if num <= 0 then 0 else fromInteger ((num + den - 1) `div` den)

{- | The indent and the end indent of the lines of a box of an indent and
an end indent (from the start and the end of the line of the column) and
a padding: the lines are the padding inside the box (docs/adr/0271).
-}
boxLineRange :: Sp -> Sp -> Sp -> (Sp, Sp)
boxLineRange start end d = (start + d, end + d)

{- | The rectangle of a part of a box of n grid lines from grid line slot
of a column, from start to end less the end indent, as the area of a
code block: its before side in the middle of the space above its first
grid line, its after side in the middle of the space below its last
(docs/adr/0271).
-}
boxArea :: Bool -> Rect -> Sp -> Sp -> Int -> Int -> Sp -> Sp -> Rect
boxArea vertical ta p fs slot n start end =
  let areaTop = fromIntegral slot * p - Sp (unSp (p - fs) `div` 2)
      across = fromIntegral n * p
      measure = if vertical then rectH ta else rectW ta
   in if vertical
        then Rect (rectX ta + rectW ta - areaTop - across) (rectY ta + rectH ta - measure + end) across (measure - start - end)
        else Rect (rectX ta + start) (rectY ta + rectH ta - areaTop - across) (measure - start - end) across

-- | The radius of each corner of a part of a box, by the sides that meet there (docs/adr/0271).
data Corners = Corners
  { beforeStart :: !Rational,
    beforeEnd :: !Rational,
    afterStart :: !Rational,
    afterEnd :: !Rational
  }
  deriving stock (Eq, Show)

-- | min(r, w/2, h/2) of a radius r and a rectangle (docs/adr/0271).
cornerRadius :: Sp -> Rect -> Rational
cornerRadius r rect = minimum [toRational (unSp r), toRational (unSp (rectW rect)) / 2, toRational (unSp (rectH rect)) / 2]

{- | The corners of a part of a box (docs/adr/0271, B8): a corner is round,
of the radius given, unless a side at it is where the box is broken (the
before side of a part after the first, the after side of a part before
the last), or the box has a border and a side at it is not drawn.
-}
boxCorners :: Bool -> [BoxSide] -> Bool -> Bool -> Rational -> Corners
boxCorners border sides isFirst isLast r =
  let at bs se =
        let open = if bs == SideBefore then isFirst else isLast
            drawn = not border || (bs `elem` sides && se `elem` sides)
         in if open && drawn then r else 0
   in Corners (at SideBefore SideStart) (at SideBefore SideEnd) (at SideAfter SideStart) (at SideAfter SideEnd)

-- | A point of a path, in rationals.
type Point = (Rational, Rational)

-- | A part of a path: a line or a cubic curve to a point.
data Segment = SegLine !Point | SegCurve !Point !Point !Point
  deriving stock (Eq, Show)

{- | 4(√2 − 1)/3, of the control points of a quarter of a circle drawn as
one cubic curve, as a rational of ten digits.
-}
kappa :: Rational
kappa = 5522847498 / 10000000000

-- | The radius of the lower left, the lower right, the upper right and the upper left corner of a rectangle.
data Physical = Physical !Rational !Rational !Rational !Rational

{- | The corners of a part on the page: in horizontal text before is the
top and start the left; in vertical text before is the right and start
the top.
-}
physical :: Bool -> Corners -> Physical
physical vertical (Corners bs be as ae)
  | vertical = Physical ae be bs as
  | otherwise = Physical as ae be bs

-- | The corners of a rectangle on the page with their radii: lower left, lower right, upper right, upper left.
physicalCorners :: Bool -> Rect -> Corners -> [((Sp, Sp), Rational)]
physicalCorners vertical (Rect x y w h) cs =
  let Physical bl br tr tl = physical vertical cs
   in [((x, y), bl), ((x + w, y), br), ((x + w, y + h), tr), ((x, y + h), tl)]

{- | The four sides of a rectangle on the page from the lower left corner
counterclockwise, each from where it starts to where it ends, with the
quarter at its end; the quarter of a radius 0 is none.
-}
sidesAround :: Rect -> Physical -> [(Point, Point, [Segment])]
sidesAround (Rect x0 y0 w0 h0) (Physical bl br tr tl) =
  let x = toRational (unSp x0)
      y = toRational (unSp y0)
      w = toRational (unSp w0)
      h = toRational (unSp h0)
      quarter r a b c = [SegCurve a b c | r > 0]
   in [ ((x + bl, y), (x + w - br, y), quarter br (x + w - br + kappa * br, y) (x + w, y + br - kappa * br) (x + w, y + br)),
        ((x + w, y + br), (x + w, y + h - tr), quarter tr (x + w, y + h - tr + kappa * tr) (x + w - tr + kappa * tr, y + h) (x + w - tr, y + h)),
        ((x + w - tr, y + h), (x + tl, y + h), quarter tl (x + tl - kappa * tl, y + h) (x, y + h - tl + kappa * tl) (x, y + h - tl)),
        ((x, y + h - tl), (x, y + bl), quarter bl (x, y + bl - kappa * bl) (x + bl - kappa * bl, y) (x + bl, y))
      ]

{- | The closed path of the background of a part (docs/adr/0271, B9): the
sides of the rectangle in lines, the round corners in quarters, from the
lower left corner counterclockwise.
-}
boxOutline :: Bool -> Rect -> Corners -> (Point, [Segment])
boxOutline vertical rect cs = case sidesAround rect (physical vertical cs) of
  sides@((start, _, _) : _) -> (start, concat [SegLine end : quarter | (_, end, quarter) <- sides])
  [] -> ((0, 0), [])

-- | The sides of the page of the logical sides, in the order of 'sidesAround': bottom, right, top, left.
pageSides :: Bool -> [BoxSide]
pageSides vertical
  | vertical = [SideEnd, SideBefore, SideStart, SideAfter]
  | otherwise = [SideAfter, SideEnd, SideBefore, SideStart]

{- | The paths of the border of a part with round corners (docs/adr/0271):
the sides drawn joined by their quarters, one path for each run of sides
that follow one another; one closed path when all four are drawn.
-}
boxBorderRuns :: Bool -> Rect -> Corners -> [BoxSide] -> [(Point, [Segment], Bool)]
boxBorderRuns vertical rect cs sides =
  let around = zip (map (`elem` sides) (pageSides vertical)) (sidesAround rect (physical vertical cs))
   in if all fst around
        then [(start, concat [SegLine end : quarter | (_, (_, end, quarter)) <- around], True) | (_, (start, _, _)) : _ <- [around]]
        else
          let -- from the side after one not drawn, so that no run goes round the end of the list
              k = length (takeWhile fst around) + 1
              turned = drop k around <> take k around
              runs [] = []
              runs xs = let (run, rest) = span fst (dropWhile (not . fst) xs) in [map snd run | not (null run)] <> runs rest
              path run =
                let (start, _, _) = head' run
                    segs = concat [SegLine end : (if i < length run then quarter else []) | (i, (_, end, quarter)) <- zip [1 :: Int ..] run]
                 in (start, segs, False)
           in map path (runs turned)
  where
    head' = \case
      x : _ -> x
      [] -> ((0, 0), (0, 0), [])

{- | The bands of a border of a weight on the sides drawn of a part
without round corners (docs/adr/0271): each centred on its side, as long
as the side and the weight; drawn in the line style by 'ruleShapes'. On
the page: the top, the bottom, the left and the right, the order of the
border of code blocks (golem-driver ADR 0023).
-}
boxBands :: Bool -> Rect -> Sp -> RuleStyle -> [BoxSide] -> [RuleShape]
boxBands vertical (Rect x y w h) t style sides =
  let half = Sp (unSp t `div` 2)
      top = (False, Rect (x - half) (y + h - half) (w + t) t)
      bottom = (False, Rect (x - half) (y - half) (w + t) t)
      left = (True, Rect (x - half) (y - half) t (h + t))
      right = (True, Rect (x + w - half) (y - half) t (h + t))
      bands
        | vertical = [(SideStart, top), (SideEnd, bottom), (SideAfter, left), (SideBefore, right)]
        | otherwise = [(SideBefore, top), (SideAfter, bottom), (SideStart, left), (SideEnd, right)]
   in concat [ruleShapes along band style | (side, (along, band)) <- bands, side `elem` sides]

{- | What a box paints (docs/adr/0271): its background, its border (the
swatch, the width and the line style, its lengths found) and the sides
of the border, and the radius of its corners.
-}
data BoxPaint = BoxPaint
  { bpBackground :: !(Maybe P.Swatch),
    bpBorder :: !(Maybe (P.Swatch, Sp, RuleStyle)),
    bpSides :: ![BoxSide],
    bpRadius :: !Sp
  }
  deriving stock (Eq, Show)

{- | The marks of a part of a box in its rectangle, with their swatches:
those of the background and those of the border (docs/adr/0271). A part with no round
corner fills the rectangle and draws the bands; one with a round corner
fills its outline, its lines as curves, and strokes the paths of its border, the dashes and
the dots by a dash array of the lengths of the line style, the dots of
round ends.
-}
boxMarks :: Bool -> Rect -> BoxPaint -> Bool -> Bool -> ([(P.Swatch, P.Mark)], [(P.Swatch, P.Mark)])
boxMarks vertical rect bp isFirst isLast =
  let cs = boxCorners (isJustBorder bp) (bpSides bp) isFirst isLast (cornerRadius (bpRadius bp) rect)
      square = all (== 0) [beforeStart cs, beforeEnd cs, afterStart cs, afterEnd cs]
      background = case bpBackground bp of
        Just sw
          | square -> [(sw, P.Saved [P.SetColor sw, P.Rule rect])]
          | otherwise -> let (start, segs) = boxOutline vertical rect cs in [(sw, P.Saved [P.SetColor sw, P.CurveFill (spPoint start) (asCurves start (dropClosing start segs))])]
        Nothing -> []
      border = case bpBorder bp of
        Just (sw, t, style)
          | square -> [(sw, m) | m <- ruleMarks (Just sw) (boxBands vertical rect t style (bpSides bp))]
          | otherwise ->
              let stroke = case style of
                    RuleDashed d g -> P.LineStroke t [d, g] False
                    RuleDotted g -> P.LineStroke t [0, t + g] True
                    _ -> P.LineStroke t [] False
               in [(sw, P.Saved (P.SetColor sw : [P.StrokedPath stroke (spPoint start) (map spSegment (if closed then dropClosing start segs else segs)) closed | (start, segs, closed) <- boxBorderRuns vertical rect cs (bpSides bp)]))]
        Nothing -> []
   in (background, border)
  where
    isJustBorder = maybe False (const True) . bpBorder
    -- the last line back to the start of a closed path is the h that closes it
    dropClosing start segs = case reverse segs of
      SegLine end : rest | end == start -> reverse rest
      _ -> segs

{- | The segments of a filled path as cubic curves, a line as one whose
control points are its ends (as the wrap mark draws its edges,
golem-layout ADR 0042): the operators the rasterizer of the visual
regression test reads (docs/adr/0093).
-}
asCurves :: Point -> [Segment] -> [((Sp, Sp), (Sp, Sp), (Sp, Sp))]
asCurves start = go start
  where
    go _ [] = []
    go q (seg : rest) = case seg of
      SegLine e -> (spPoint q, spPoint e, spPoint e) : go e rest
      SegCurve a b c -> (spPoint a, spPoint b, spPoint c) : go c rest

-- | A point rounded to sp.
spPoint :: Point -> (Sp, Sp)
spPoint (x, y) = (Sp (round x), Sp (round y))

spSegment :: Segment -> P.PathSegment
spSegment = \case
  SegLine q -> P.LineTo (spPoint q)
  SegCurve a b c -> P.CurveTo (spPoint a) (spPoint b) (spPoint c)
