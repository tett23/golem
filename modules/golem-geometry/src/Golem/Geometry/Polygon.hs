{- | Paths made polygons, and the regions inside them (root ADR 0437), in
exact rationals: no floating point, so a native build and a wasm build
give the same intervals.

A cubic curve is halved by de Casteljau's construction until both of
its inner control points are within 1/4 sp of its chord, and then
replaced by the chord; a cubic curve lies in the convex hull of its
control points, so the chord is within 1/4 sp of the curve. A polygon
is closed as a filled path is: every subpath, closed or not.
-}
module Golem.Geometry.Polygon
  ( RPoint,
    Bezier,
    flattenTolerance2,
    chordDistance2,
    splitCurve,
    flatPieces,
    flattenPath,
    insidePolygons,
    stripInside,
  )
where

import Data.List (sort, sortOn)
import Golem.Geometry (FillRule (..), Path (..), Point, Segment (..), SubPath (..))
import Golem.Length (Sp (..))

-- | A point in rationals of sp.
type RPoint = (Rational, Rational)

-- | A cubic curve: its start, its two control points and its end.
type Bezier = (RPoint, RPoint, RPoint, RPoint)

-- | The square of the distance a control point may be from the chord: (1/4 sp)².
flattenTolerance2 :: Rational
flattenTolerance2 = 1 / 16

-- | The square of the distance of a point from the segment of its two ends (a point when they are one).
chordDistance2 :: RPoint -> RPoint -> RPoint -> Rational
chordDistance2 (ax, ay) (bx, by) (px, py) =
  let dx = bx - ax
      dy = by - ay
      len2 = dx * dx + dy * dy
      t = if len2 == 0 then 0 else max 0 (min 1 (((px - ax) * dx + (py - ay) * dy) / len2))
      qx = ax + t * dx - px
      qy = ay + t * dy - py
   in qx * qx + qy * qy

-- | The two halves of a curve at t = 1/2 (de Casteljau).
splitCurve :: Bezier -> (Bezier, Bezier)
splitCurve (p0, p1, p2, p3) =
  let mid (ax, ay) (bx, by) = ((ax + bx) / 2, (ay + by) / 2)
      a = mid p0 p1
      b = mid p1 p2
      c = mid p2 p3
      d = mid a b
      e = mid b c
      m = mid d e
   in ((p0, a, d, m), (m, e, c, p3))

-- | The pieces of a curve, in order, each flat within 'flattenTolerance2'.
flatPieces :: Bezier -> [Bezier]
flatPieces b@(p0, p1, p2, p3)
  | chordDistance2 p0 p3 p1 <= flattenTolerance2 && chordDistance2 p0 p3 p2 <= flattenTolerance2 = [b]
  | otherwise = let (l, r) = splitCurve b in flatPieces l <> flatPieces r

{- | The polygons of a path: of each subpath, its start and the end of each
line and of each flat piece of each curve. A subpath of no segment is no
polygon.
-}
flattenPath :: Path -> [[RPoint]]
flattenPath (Path subs) = [polygon s | s <- subs, not (null (subSegments s))]
  where
    polygon (SubPath start segs _) = rp start : go (rp start) segs
    go _ [] = []
    go q (seg : rest) = case seg of
      LineTo p -> rp p : go (rp p) rest
      CurveTo a b e ->
        let ps = [p3 | (_, _, _, p3) <- flatPieces (q, rp a, rp b, rp e)]
         in ps <> go (rp e) rest
    rp :: Point -> RPoint
    rp (Sp x, Sp y) = (toRational x, toRational y)

-- | The edges of polygons, each closed back to its start; edges of no length are left out.
edgesOf :: [[RPoint]] -> [(RPoint, RPoint)]
edgesOf polys = [(a, b) | poly@(_ : rest) <- polys, (a, b) <- zip poly (rest <> take 1 poly), a /= b]

{- | Whether a point is inside polygons by the fill rule, the edges
included: a point on an edge or at a vertex is inside.
-}
insidePolygons :: FillRule -> [[RPoint]] -> RPoint -> Bool
insidePolygons rule polys p =
  let es = edgesOf polys
   in elem p (concat polys) || any (onEdge p) es || covered rule (winding es p)

covered :: FillRule -> Int -> Bool
covered rule w = case rule of
  NonZero -> w /= 0
  EvenOdd -> odd w

-- | Whether a point is on the segment.
onEdge :: RPoint -> (RPoint, RPoint) -> Bool
onEdge (px, py) ((ax, ay), (bx, by)) =
  (bx - ax) * (py - ay) == (by - ay) * (px - ax)
    && min ax bx <= px
    && px <= max ax bx
    && min ay by <= py
    && py <= max ay by

-- | The winding number of the edges round a point: upward edges to its right count +1, downward ones −1.
winding :: [(RPoint, RPoint)] -> RPoint -> Int
winding es (px, py) = sum (map at es)
  where
    at ((ax, ay), (bx, by))
      | ay <= py && py < by && side > 0 = 1
      | by <= py && py < ay && side < 0 = -1
      | otherwise = 0
      where
        side = (bx - ax) * (py - ay) - (px - ax) * (by - ay)

{- | The intervals of x whose points are inside the polygons by the fill
rule at every y from the first to the second (the strip), in order;
closed, and of no length where the inside narrows to a point (root ADR
0447).

The strip is cut at the vertices in it and where edges cross in it. In
each part, the edges that cross the part keep their order, so each gap
between two of them is inside or outside over the whole part; an outside
gap rules out the x it covers anywhere in the part, from the leftmost to
the rightmost place of its two edges. What no part rules out is inside
over the whole strip.
-}
stripInside :: FillRule -> [[RPoint]] -> Rational -> Rational -> [(Rational, Rational)]
stripInside rule polys y0 y1
  | y0 >= y1 = []
  | otherwise =
      let es = sortOn lowY [e | e@((_, ay), (_, by)) <- edgesOf polys, ay /= by, max ay by > y0, min ay by < y1]
          inStrip y = y0 < y && y < y1
          cuts = dedupe (sort ([y0, y1] <> [y | ((_, ay), (_, by)) <- es, y <- [ay, by], inStrip y]))
       in complementOf (sweep es [] (zip cuts (drop 1 cuts)))
  where
    lowY ((_, ay), (_, by)) = min ay by
    highY ((_, ay), (_, by)) = max ay by
    -- the parts in order, with the edges that cross each: those that start
    -- at or below it and end above its bottom (no vertex is inside a part)
    sweep _ _ [] = []
    sweep pending active ((ya, yb) : parts) =
      let (starting, later) = span ((<= ya) . lowY) pending
          active' = [e | e <- active <> starting, highY e > ya]
          -- the edges of a part cross where they change their order: the
          -- part is cut there too
          inner = dedupe (sort [y | (e, f) <- pairs active', Just y <- [crossingY e f], ya < y, y < yb])
          pieces = let ys = ya : inner <> [yb] in zip ys (drop 1 ys)
       in concatMap (outsideIn rule active') pieces <> sweep later active' parts
    pairs xs = [(a, b) | (i, a) <- zip [0 :: Int ..] xs, b <- drop (i + 1) xs]

{- | The x ruled out in a part of the strip, given the edges that cross the
whole part and no other: open intervals, Nothing for no bound. The
winding number of a gap is that of the edges to its left, negated: left
of all the edges it is 0.
-}
outsideIn :: FillRule -> [(RPoint, RPoint)] -> (Rational, Rational) -> [(Maybe Rational, Maybe Rational)]
outsideIn rule es (ya, yb) =
  let ym = (ya + yb) / 2
      crossing = sortOn (`xAt` ym) es
      dir ((_, ay), (_, by)) = if ay < by then 1 else -1 :: Int
      ends e = (min (xAt e ya) (xAt e yb), max (xAt e ya) (xAt e yb))
      -- each gap with the edges on its sides and the winding number in it
      lefts = Nothing : map Just crossing
      rights = map Just crossing <> [Nothing]
      windings = scanl (\w e -> w - dir e) 0 crossing
      width l r = case (l, r) of
        (Just a, Just b) -> xAt a ym /= xAt b ym
        _ -> True
   in [ (fmap (fst . ends) l, fmap (snd . ends) r)
      | (l, r, w) <- zip3 lefts rights windings,
        width l r,
        not (covered rule w)
      ]

-- | The x of an edge at a y it reaches.
xAt :: (RPoint, RPoint) -> Rational -> Rational
xAt ((ax, ay), (bx, by)) y
  | ay == by = min ax bx
  | otherwise = ax + (bx - ax) * (y - ay) / (by - ay)

-- | The y where two edges cross at one point, inside both.
crossingY :: (RPoint, RPoint) -> (RPoint, RPoint) -> Maybe Rational
crossingY ((ax, ay), (bx, by)) ((cx, cy), (dx, dy)) =
  let rx = bx - ax
      ry = by - ay
      sx = dx - cx
      sy = dy - cy
      den = rx * sy - ry * sx
   in if den == 0
        then Nothing
        else
          let t = ((cx - ax) * sy - (cy - ay) * sx) / den
              u = ((cx - ax) * ry - (cy - ay) * rx) / den
           in if 0 <= t && t <= 1 && 0 <= u && u <= 1 then Just (ay + t * ry) else Nothing

-- | What open intervals leave: the closed intervals between them, in order.
complementOf :: [(Maybe Rational, Maybe Rational)] -> [(Rational, Rational)]
complementOf ruled
  | any (\(l, r) -> null l && null r) ruled = []
  | otherwise =
      let -- every interval ruled out has a bound on at least one side
          lowest = maximum' [r | (Nothing, Just r) <- ruled]
          highest = minimum' [l | (Just l, Nothing) <- ruled]
          inner = sort [(l, r) | (Just l, Just r) <- ruled, l < r]
       in case (lowest, highest) of
            (Just lo, Just hi) | lo <= hi -> sweep lo hi inner
            _ -> []
  where
    maximum' = \case
      [] -> Nothing
      zs -> Just (maximum zs)
    minimum' = \case
      [] -> Nothing
      zs -> Just (minimum zs)
    -- the closed intervals of [from, to] that no open (l, r) covers, the (l, r) in the order of l
    sweep from to = \case
      [] -> [(from, to)]
      (l, r) : rest
        | r <= from -> sweep from to rest
        | l >= to -> [(from, to)]
        | l < from -> after r rest
        | otherwise -> (from, l) : after r rest
      where
        after r rest = if r > to then [] else sweep r to rest

dedupe :: (Eq a) => [a] -> [a]
dedupe = \case
  a : b : rest | a == b -> dedupe (b : rest)
  a : rest -> a : dedupe rest
  [] -> []
