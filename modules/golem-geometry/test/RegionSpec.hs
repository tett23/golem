{- | The inside of paths (root ADR 0437): a rectangle and its path cover
the same points (I1), and the intervals of a strip that lie inside a
polygon over the whole strip.
-}
module RegionSpec (tests) where

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
          testCase "a notch that moves across the strip further than its width leaves nothing inside where it passed" $
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
          testCase "every point of every interval of a star is inside over the whole strip" $
            let ivs = stripInside NonZero [star] 3 5
                ys = [3, 3 + 1 / 4 .. 5]
             in do
                  assertBool "the star has an interval" (not (null ivs))
                  assertBool (show ivs) (and [insidePolygons NonZero [star] (x, y) | (a, b) <- ivs, x <- [a, a + (b - a) / 8 .. b], y <- ys])
        ]
    ]

square :: Rational -> Rational -> Rational -> Rational -> [RPoint]
square x y w h = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]

-- | A star of five points drawn as a simple polygon of ten vertices.
star :: [RPoint]
star = [(5, 10), (6, 6.5), (10, 6.5), (7, 4), (8, 0), (5, 2.5), (2, 0), (3, 4), (0, 6.5), (4, 6.5)]
