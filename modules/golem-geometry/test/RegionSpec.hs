{- | The inside of paths (root ADR 0437): a rectangle and its path cover
the same points (I1), and the intervals of a strip that lie inside a
polygon over the whole strip (root ADR 0447).
-}
module RegionSpec (tests) where

import Data.List (sort)
import Golem.Geometry
import Golem.Geometry.Polygon
import Golem.Length (Sp (..))
import Test.Tasty
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "regions"
    [ testCase "root ADR 0437 I1: rectPath r covers the points of r, edges included, on a grid of small rectangles" $
        let rects = [Rect (Sp x) (Sp y) (Sp w) (Sp h) | x <- [-1 .. 1], y <- [-1 .. 1], w <- [0 .. 3], h <- [0 .. 3]]
            grid = [(px / 2, py / 2) | px <- [-4 .. 10], py <- [-4 .. 10]]
            wrong = [(r, rule, p) | r <- rects, rule <- [NonZero, EvenOdd], p <- grid, insideRect r p /= insidePolygons rule (flattenPath (rectPath r)) p]
         in take 1 wrong @?= [],
      testCase "root ADR 0437 I1: rectPath goes round the rectangle from its lower left corner" $
        rectPath (Rect 1 2 3 4) @?= Path [SubPath (1, 2) [LineTo (4, 2), LineTo (4, 6), LineTo (1, 6)] True],
      testGroup
        "the inside of a strip"
        [ testCase "a square gives one interval across it" $
            stripInside NonZero [square 0 0 10 10] 2 4 @?= [(0, 10)],
          testCase "a strip outside the polygon gives none" $
            stripInside NonZero [square 0 0 10 10] 11 12 @?= [],
          testCase "a triangle gives the interval inside at both lines of the strip" $
            -- apex (5, 10): at y = 4 the triangle is [2, 8], at y = 6 it is [3, 7]
            stripInside NonZero [[(0, 0), (10, 0), (5, 10)]] 4 6 @?= [(3, 7)],
          testCase "a vertex inside the strip narrows the interval to the vertex" $
            -- a diamond whose left and right corners are at y = 5
            stripInside NonZero [[(5, 0), (10, 5), (5, 10), (0, 5)]] 4 6 @?= [(1, 9)],
          testCase "root ADR 0447 I1, I2: a notch that moves across the strip further than its width leaves nothing inside where it passed" $
            -- the slit is x in (1, 2) at y = 0 and x in (3.5, 4.5) at y = 10: the
            -- lines of the strip alone would leave [2, 3.5] inside
            let notched = [(0, -10), (10, -10), (10, 20), (7, 20), (2, 0), (1, 0), (6, 20), (0, 20)]
             in stripInside NonZero [notched] 0 10 @?= [(0, 1), (4.5, 10)],
          testCase "two polygons give two intervals, in order" $
            stripInside NonZero [square 20 0 10 10, square 0 0 10 10] 2 4 @?= [(0, 10), (20, 30)],
          testCase "a hole is outside by even-odd and inside by nonzero when it goes the same way" $ do
            let outer = square 0 0 30 10
                inner = square 10 0 10 10
            stripInside EvenOdd [outer, inner] 2 4 @?= [(0, 10), (20, 30)]
            stripInside NonZero [outer, inner] 2 4 @?= [(0, 30)],
          testCase "root ADR 0447 I1: every point of every interval of a star is inside over the whole strip" $
            let ivs = stripInside NonZero [star] 3 5
                ys = [3, 3 + 1 / 4 .. 5]
             in do
                  assertBool "the star has an interval" (not (null ivs))
                  assertBool (show ivs) (and [insidePolygons NonZero [star] (x, y) | (a, b) <- ivs, x <- [a, a + (b - a) / 8 .. b], y <- ys])
        ],
      testGroup "the boundary inputs of root ADR 0447" boundaryTests,
      testGroup "the polygons on the grid of 0 to 10 (root ADR 0447)" enumerationTests
    ]

-- | The rows of the table of root ADR 0447: each result, and the invariants of its row.
boundaryTests :: [TestTree]
boundaryTests =
  [ row "a square and the strip 2 to 4" [I1, I2, I3] NonZero [square 0 0 10 10] 2 4 (Just [(0, 10)]),
    row "a slanted notch whose vertices are all outside the strip 0 to 10" [I1, I2, I3] NonZero [slantedNotch] 0 10 (Just [(0, 3), (6, 10)]),
    row "a V notch with a vertex on an end of the strip 0 to 10" [I1, I2] NonZero [vNotch] 0 10 (Just [(0, 0), (6, 10)]),
    row "a bow tie and the strip 4 to 6 by nonzero" [I1, I2] NonZero [bowTie] 4 6 (Just [(0, 4), (6, 10)]),
    row "a bow tie and the strip 4 to 6 by even-odd" [I1, I2] EvenOdd [bowTie] 4 6 (Just [(0, 4), (6, 10)]),
    row "a star with concave vertices in the strip 3 to 5" [I1, I2, I3] NonZero [star] 3 5 Nothing,
    row "a horizontal edge in the strip 3 to 7" [I1, I2] NonZero [step] 3 7 (Just [(0, 5)]),
    row "a hole that goes the same way, by nonzero" [I1, I2] NonZero [square 0 0 30 10, square 10 0 10 10] 2 4 (Just [(0, 30)]),
    row "a hole that goes the same way, by even-odd" [I1, I2] EvenOdd [square 0 0 30 10, square 10 0 10 10] 2 4 (Just [(0, 10), (20, 30)]),
    row "a bow tie whose edges cross on the end line of the strip 5 to 7" [I1, I2] NonZero [bowTie] 5 7 (Just [(0, 3), (7, 10)]),
    row "a triangle that touches the strip 5 to 6 at its vertex only from below" [I1, I2] NonZero [cup] 5 6 (Just [(5, 5)]),
    row "a triangle that touches the strip 4 to 5 at its vertex only" [I1, I2] NonZero [cup] 4 5 (Just []),
    row "the empty polygon" [I1, I2] NonZero [] 0 10 (Just []),
    testCase "a strip of no height has no interval" $
      stripInside NonZero [square 0 0 10 10] 5 5 @?= []
  ]
  where
    row name invs rule polys y0 y1 expected =
      testCase ("root ADR 0447 " <> invNames invs <> ": " <> name) $ do
        let got = stripInside rule polys y0 y1
        maybe (assertBool (name <> " has an interval") (not (null got))) (got @?=) expected
        mapM_ (\i -> assertBool (show i <> " " <> show got) (holds i rule polys y0 y1 got)) invs
    invNames = \case
      [] -> ""
      i : rest -> show i <> concatMap ((", " <>) . show) rest

{- | I1 to I3 over polygons of 3 to 6 vertices on the integer grid of 0 to
10 and the strips of integer ends in it, by both fill rules. All the
polygons of so many vertices are too many; those taken are the ones at
evenly spaced indices of the polygons in lexicographic order.
-}
enumerationTests :: [TestTree]
enumerationTests =
  [ testCase ("root ADR 0447 " <> show i <> ": every polygon on the grid and every strip") $
      take 1 [(rule, poly, y0, y1, got) | (poly, rule, y0, y1) <- cases, let got = stripInside rule [poly] y0 y1, not (holds i rule [poly] y0 y1 got)] @?= []
  | i <- [I1, I2, I3]
  ]
    <> [ testCase "root ADR 0447 I1: the method of root ADR 0437, the lines of the strip and of its vertices, fails it on the grid" $
           assertBool "no polygon on the grid breaks I1 by the method of root ADR 0437" (any (\(poly, rule, y0, y1) -> not (holds I1 rule [poly] y0 y1 (linesMethod rule [poly] y0 y1))) cases),
         testCase "root ADR 0447 I1: the method of root ADR 0437 leaves the slanted notch inside" $
           assertBool "the method of root ADR 0437 keeps the notch" (not (holds I1 NonZero [slantedNotch] 0 10 (linesMethod NonZero [slantedNotch] 0 10)))
       ]
  where
    cases = [(poly, rule, y0, y1) | poly <- gridPolygons, rule <- [NonZero, EvenOdd], y0 <- [0 .. 9], y1 <- [y0 + 1 .. 10]]

{- | The polygons of 3 to 6 vertices on the grid: the shapes of the table
that are on it, and so many of each count at the indices of a Weyl
sequence over the polygons in lexicographic order (each index the last
plus about 0.618 of their number), which spreads them over all of them.
-}
gridPolygons :: [[RPoint]]
gridPolygons = [square 0 0 10 10, wedge, vNotch, bowTie, step, cup] <> concatMap polygonsOf [3 .. 6]
  where
    perCount = 40 :: Integer
    polygonsOf k =
      let total = 121 ^ k :: Integer
          stride = until ((/= 0) . (`mod` 11)) (+ 1) (total * 6180339887 `div` 10000000000)
       in [decode k ((n * stride) `mod` total) | n <- [1 .. perCount]]
    decode :: Int -> Integer -> [RPoint]
    decode k n = take k [(fromInteger (d `mod` 11), fromInteger (d `div` 11)) | d <- map (`mod` 121) (iterate (`div` 121) n)]

data Invariant = I1 | I2 | I3
  deriving stock (Eq, Show)

{- | Whether an invariant of root ADR 0447 holds of the intervals got for
the strip. Inside over the whole strip is decided exactly: on the
vertical line of x, whether a point is inside changes only at the y of a
vertex, where edges cross, or where an edge crosses the line, so the
points at those y and between them are enough. The x looked at are those
of the edges at the y that cut the strip, and those between them: the
ends of the intervals got and of those inside are among them.
-}
holds :: Invariant -> FillRule -> [[RPoint]] -> Rational -> Rational -> [(Rational, Rational)] -> Bool
holds inv rule polys y0 y1 got = case inv of
  I1 -> all over (inGot <> inRounded)
  I2 -> not (any over outGot)
  I3 -> all (\x -> all (\y -> insidePolygons rule polys (x, y)) (y0 : y1 : vertexYs polys y0 y1)) inGot
  where
    over = insideOverStrip rule polys y0 y1
    xs = withMidpoints (criticalXs polys y0 y1 <> concat [[a, b] | (a, b) <- got])
    inGot = filter within xs
    outGot = filter (not . within) (xs <> [minimum (0 : xs) - 1, maximum (0 : xs) + 1])
    within x = any (\(a, b) -> a <= x && x <= b) got
    rounded = [(a, b) | (a', b') <- got, let a = fromInteger (ceiling a'), let b = fromInteger (floor b'), a <= b]
    inRounded = concat [withMidpoints [a, b] | (a, b) <- rounded]

-- | Whether x is inside at every y of the strip (partially applied to the strip, it finds the y that cut it once).
insideOverStrip :: FillRule -> [[RPoint]] -> Rational -> Rational -> Rational -> Bool
insideOverStrip rule polys y0 y1 =
  let es = edgesOfT polys
      cuts = cutYs polys y0 y1
      vertices = concat polys
   in \x ->
        let atX = [ay + (by - ay) * (x - ax) / (bx - ax) | ((ax, ay), (bx, by)) <- es, ax /= bx, min ax bx < x, x < max ax bx]
            ys = withMidpoints (cuts <> filter (\y -> y0 < y && y < y1) atX)
         in all (\y -> insideEdges rule vertices es (x, y)) ys

-- | 'insidePolygons' on the vertices and the edges of the polygons, found once.
insideEdges :: FillRule -> [RPoint] -> [(RPoint, RPoint)] -> RPoint -> Bool
insideEdges rule vertices es p@(px, py) = elem p vertices || any onEdgeT es || covers (sum (map crossing es))
  where
    covers w = case rule of
      NonZero -> w /= 0
      EvenOdd -> odd w
    onEdgeT ((ax, ay), (bx, by)) =
      (bx - ax) * (py - ay) == (by - ay) * (px - ax) && min ax bx <= px && px <= max ax bx && min ay by <= py && py <= max ay by
    crossing ((ax, ay), (bx, by))
      | ay <= py && py < by && side > 0 = 1 :: Int
      | by <= py && py < ay && side < 0 = -1
      | otherwise = 0
      where
        side = (bx - ax) * (py - ay) - (px - ax) * (by - ay)

-- | The method of root ADR 0437: the x inside at both lines of the strip and at the lines of the vertices in it.
linesMethod :: FillRule -> [[RPoint]] -> Rational -> Rational -> [(Rational, Rational)]
linesMethod rule polys y0 y1 =
  let xs = withMidpoints (criticalXs polys y0 y1)
      inside x = all (\y -> insidePolygons rule polys (x, y)) (y0 : y1 : vertexYs polys y0 y1)
   in [(x, x) | x <- xs, inside x]

-- | The y that cut the strip: its ends, the vertices in it and where edges cross in it.
cutYs :: [[RPoint]] -> Rational -> Rational -> [Rational]
cutYs polys y0 y1 =
  let es = edgesOfT polys
      crossings = [y | (i, e) <- zip [0 :: Int ..] es, f <- drop (i + 1) es, Just y <- [crossAt e f], y0 < y, y < y1]
   in sortedSet (y0 : y1 : vertexYs polys y0 y1 <> crossings)

vertexYs :: [[RPoint]] -> Rational -> Rational -> [Rational]
vertexYs polys y0 y1 = [y | (_, y) <- concat polys, y0 < y, y < y1]

-- | The x of the edges and the vertices at the y that cut the strip.
criticalXs :: [[RPoint]] -> Rational -> Rational -> [Rational]
criticalXs polys y0 y1 =
  let ys = cutYs polys y0 y1
   in [ if ay == by then ax else ax + (bx - ax) * (y - ay) / (by - ay)
      | ((ax, ay), (bx, by)) <- edgesOfT polys,
        y <- ys,
        min ay by <= y,
        y <= max ay by
      ]
        <> map fst (concat polys)

-- | The points given, sorted without repeats, with those halfway between each two next to each other.
withMidpoints :: [Rational] -> [Rational]
withMidpoints zs =
  let s = sortedSet zs
   in concat (zipWith (\a b -> [a, (a + b) / 2]) s (drop 1 s)) <> drop (length s - 1) s

-- | The values sorted, each once.
sortedSet :: [Rational] -> [Rational]
sortedSet = foldr (\x acc -> if take 1 acc == [x] then acc else x : acc) [] . sort

edgesOfT :: [[RPoint]] -> [(RPoint, RPoint)]
edgesOfT polys = [(a, b) | poly@(_ : rest) <- polys, (a, b) <- zip poly (rest <> take 1 poly), a /= b]

-- | The y where two edges meet at one point.
crossAt :: (RPoint, RPoint) -> (RPoint, RPoint) -> Maybe Rational
crossAt ((ax, ay), (bx, by)) ((cx, cy), (dx, dy)) =
  let rx = bx - ax
      ry = by - ay
      sx = dx - cx
      sy = dy - cy
      den = rx * sy - ry * sx
      t = ((cx - ax) * sy - (cy - ay) * sx) / den
      u = ((cx - ax) * ry - (cy - ay) * rx) / den
   in if den /= 0 && 0 <= t && t <= 1 && 0 <= u && u <= 1 then Just (ay + t * ry) else Nothing

-- | The notch of root ADR 0447 whose vertices are all outside the strip 0 to 10.
slantedNotch :: [RPoint]
slantedNotch = [(0, -10), (10, -10), (10, 20), (8, 20), (2, -10), (1, -10), (7, 20), (0, 20)]

-- | The V notch of root ADR 0447 with a vertex on the lower end of the strip 0 to 10.
vNotch :: [RPoint]
vNotch = [(0, 0), (10, 0), (10, 10), (6, 10), (0, 5), (5, 10), (0, 10)]

bowTie :: [RPoint]
bowTie = [(0, 0), (10, 10), (10, 0), (0, 10)]

-- | A shape with a horizontal edge at y = 5.
step :: [RPoint]
step = [(0, 0), (10, 0), (10, 5), (5, 5), (5, 10), (0, 10)]

{- | A square whose left side is bent into a thin slanted wedge, the
vertices (0, 0), (0, 1) and (9, 10): at y = 2 the wedge is x in (1, 1.8)
and at y = 8 it is x in (7, 7.2), so the lines of the strip 2 to 8 alone
would leave [1.8, 7] inside.
-}
wedge :: [RPoint]
wedge = [(0, 0), (10, 0), (10, 10), (0, 10), (0, 1), (9, 10)]

-- | A triangle whose lowest point is the vertex (5, 5).
cup :: [RPoint]
cup = [(5, 5), (10, 10), (0, 10)]

square :: Rational -> Rational -> Rational -> Rational -> [RPoint]
square x y w h = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]

-- | A star of five points drawn as a simple polygon of ten vertices.
star :: [RPoint]
star = [(5, 10), (6, 6.5), (10, 6.5), (7, 4), (8, 0), (5, 2.5), (2, 0), (3, 4), (0, 6.5), (4, 6.5)]
