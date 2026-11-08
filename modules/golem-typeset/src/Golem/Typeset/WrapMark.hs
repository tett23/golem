{- | The default wrap mark of inline code drawn as a shape, not as a glyph:
a thin return arrow with an open head, in a square of 3/5 of the size of
the code, its strokes 1/20 of that size thick, filled in half of the
colour of the code (golem-layout ADR 0042). The points are rational until
they are rounded down to sp, so the PDF is the same on every machine.
-}
module Golem.Typeset.WrapMark
  ( wrapMarkUnitPolygons,
    wrapMarkPolygons,
    wrapMarkFills,
    wrapMarkSwatch,
  )
where

import Golem.LayoutSpec (baselineRatio)
import Golem.Length (Sp (..))
import Golem.Pdf qualified as P

{- | The four parts of the mark in its square, (0, 0) at the lower left and
(1, 1) at the upper right, horizontal (right along the line, up above it):
the stem, the line along to the head, and the two strokes of the head.
Each part is a quadrilateral. The strokes are 1/12 of the square thick:
1/20 of the size of the code in a square of 3/5 of it. The strokes of the
head run along the hypotenuse of a triangle of 3, 4 and 5, so the points
beside them are rational.
-}
wrapMarkUnitPolygons :: [[(Rational, Rational)]]
wrapMarkUnitPolygons =
  [ [(right - h, base - h), (right + h, base - h), (right + h, top), (right - h, top)],
    [(tip + t, base - h), (right + h, base - h), (right + h, base + h), (tip + t, base + h)],
    stroke (tip, base) (tip + 24 / 100, base + 18 / 100) (-3 / 5, 4 / 5),
    stroke (tip, base) (tip + 24 / 100, base - 18 / 100) (3 / 5, 4 / 5)
  ]
  where
    t = 1 / 12
    h = t / 2
    right = 82 / 100
    base = 30 / 100
    top = 80 / 100
    tip = 12 / 100
    -- a stroke t thick from one point to another, the unit normal of its direction given
    stroke (x1, y1) (x2, y2) (nx, ny) =
      let (dx, dy) = (nx * h, ny * h)
       in [(x1 + dx, y1 + dy), (x2 + dx, y2 + dy), (x2 - dx, y2 - dy), (x1 - dx, y1 - dy)]

{- | The parts of the mark on the page, vertical or not, at the origin of
the mark, for code of the size given. The square is 3/5 of the size wide,
rounded down. Horizontal, it runs from the origin along the line, its
centre (0.88 − 1/2) of the size above the baseline. Vertical, it runs
from the origin down the line, its centre on the centre line, and the
shape is turned 90 degrees clockwise about the centre of the square.
-}
wrapMarkPolygons :: Bool -> (Sp, Sp) -> Sp -> [[(Sp, Sp)]]
wrapMarkPolygons vertical (Sp ox, Sp oy) (Sp s) = map (map onPage) wrapMarkUnitPolygons
  where
    w = toRational (floor (toRational s * 3 / 5) :: Integer)
    (cx, cy)
      | vertical = (toRational ox, toRational oy - w / 2)
      | otherwise = (toRational ox + w / 2, toRational oy + (baselineRatio - 1 / 2) * toRational s)
    onPage (u, v) =
      let (a, b) = (u - 1 / 2, v - 1 / 2)
          (dx, dy) = if vertical then (b, negate a) else (a, b)
       in (Sp (floor (cx + dx * w)), Sp (floor (cy + dy * w)))

-- | Each part filled as a closed path of straight edges: curves with their control points at their ends.
wrapMarkFills :: [[(Sp, Sp)]] -> [P.Mark]
wrapMarkFills = concatMap fill
  where
    fill = \case
      ps@(p0 : rest) -> [P.CurveFill p0 [(a, b, b) | (a, b) <- zip ps (rest <> [p0])]]
      [] -> []

{- | The colour of the mark: half of each value of the colour of the code,
rounded down, a process colour of no name; black 50% for code of no
colour. Its total ink is never more than the code's.
-}
wrapMarkSwatch :: Maybe P.Swatch -> P.Swatch
wrapMarkSwatch = \case
  Just (P.Swatch c m y k) -> P.Swatch (c `div` 2) (m `div` 2) (y `div` 2) (k `div` 2)
  Nothing -> P.Swatch 0 0 0 50
