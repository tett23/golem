{- | The furthest x of a region within a box (root ADR 0464): the text-side
edge of a figure's outline within a band of a line, from the vertices in
the band, the crossings of the edges with the sides of the band, and the
side of the image that clips the outline.
-}
module ReachSpec (tests) where

import Data.List (nub)
import Golem.Geometry (FillRule (..))
import Golem.Geometry.Polygon
import Test.Tasty
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "the reach of a region in a box (root ADR 0464)"
    [ testCase "root ADR 0464 I2: a square reaches its right side in a box across it" $
        reachInBox NonZero [square 0 0 10 10] (0, 20) (2, 4) @?= Just 10,
      testCase "root ADR 0464 I2: a box that misses the region has no reach" $
        reachInBox NonZero [square 0 0 10 10] (0, 20) (11, 12) @?= Nothing,
      testCase "root ADR 0464 I2: a triangle reaches its widest point in the band, at a side of the band" $
        -- apex (5, 0), base from (0, 10) to (10, 10): the right edge is at x = 5 + y / 2
        reachInBox NonZero [[(0, 10), (10, 10), (5, 0)]] (0, 20) (2, 4) @?= Just 7,
      testCase "root ADR 0464 I2: a vertex inside the band is the reach" $
        -- a diamond whose right corner (10, 5) is in the band
        reachInBox NonZero [[(5, 0), (10, 5), (5, 10), (0, 5)]] (0, 20) (4, 6) @?= Just 10,
      testCase "root ADR 0464 I2: a vertex exactly on the top side of the band is in the band" $
        -- a triangle above the band whose lowest vertex (8, 4) touches the band from 4 to 6
        reachInBox NonZero [[(0, 0), (10, 0), (8, 4)]] (0, 20) (4, 6) @?= Just 8,
      testCase "root ADR 0464 I3: a region past the right side of the box is clipped to it" $
        reachInBox NonZero [square 0 0 30 10] (0, 20) (2, 4) @?= Just 20,
      testCase "root ADR 0464 I3: a region wholly past the right side of the box has no reach" $
        reachInBox NonZero [square 25 0 5 10] (0, 20) (2, 4) @?= Nothing,
      testCase "root ADR 0464 I2: a band across the hollow of a concave region reaches only what is filled" $
        -- a U open to the right: the band from 4 to 6 meets only its spine, x = 0 to 3
        reachInBox NonZero [[(0, 0), (10, 0), (10, 3), (3, 3), (3, 7), (10, 7), (10, 10), (0, 10)]] (0, 20) (4, 6) @?= Just 3,
      testCase "root ADR 0464 I2: the empty polygon has no reach" $
        reachInBox NonZero [] (0, 20) (0, 10) @?= Nothing,
      testCase "root ADR 0464 I2, I5: the triangles on the grid of 0 to 4 reach the furthest inside point of each box, exactly" $
        let wrong =
              [ (t, b, reachInBox NonZero [t] bx by, brute t bx by)
              | t <- triangles,
                b@(bx, by) <- boxes,
                reachInBox NonZero [t] bx by /= brute t bx by
              ]
         in take 1 wrong @?= [],
      testCase "root ADR 0464 I2: the quadrilaterals on the grid of 0 to 4, self-crossing ones included, reach the furthest inside point of each box" $
        let wrong =
              [ (q, b, reachInBox NonZero [q] bx by, brute q bx by)
              | q <- quads,
                b@(bx, by) <- boxes,
                reachInBox NonZero [q] bx by /= brute q bx by
              ]
         in take 1 wrong @?= []
    ]

square :: Rational -> Rational -> Rational -> Rational -> [RPoint]
square x y w h = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]

-- the points of the grid of 0 to 4 by 2
corners :: [RPoint]
corners = [(x, y) | x <- [0, 2, 4], y <- [0, 2, 4]]

triangles :: [[RPoint]]
triangles = [[a, b, c] | a <- corners, b <- corners, a < b, c <- corners, b /= c, a /= c]

-- every fourth quadrilateral of the grid, in order: an even spread of the shapes
quads :: [[RPoint]]
quads = every 4 [[a, b, c, d] | a <- corners, b <- corners, c <- corners, d <- corners, length (nub [a, b, c, d]) == 4]
  where
    every n xs = case xs of
      [] -> []
      y : ys -> y : every n (drop (n - 1) ys)

-- boxes across the grid: the sides at the grid, between it and outside it
boxes :: [((Rational, Rational), (Rational, Rational))]
boxes = [((0, x1), (y0, y1)) | x1 <- [1, 3, 5], (y0, y1) <- [(0, 1), (1, 2), (3 / 2, 5 / 2), (2, 2), (3, 5), (-1, 0), (4, 6)]]

{- the furthest x inside the closed region in the box, by brute force: the
vertices in the box, the points where the edges cross the lines of the
box, and the corners of the box, each kept when it is inside -}
brute :: [RPoint] -> (Rational, Rational) -> (Rational, Rational) -> Maybe Rational
brute poly (x0, x1) (y0, y1) =
  let edges = zip poly (drop 1 poly <> take 1 poly)
      ys = [y0, y1] <> [y | (_, y) <- poly] <> [y | e <- edges, x <- [x0, x1], Just y <- [crossX e x]]
      xs = [x0, x1] <> [x | (x, _) <- poly] <> [x | e <- edges, y <- ys, Just x <- [crossY e y]]
      inBox (x, y) = x0 <= x && x <= x1 && y0 <= y && y <= y1
      ins = [x | x <- xs, y <- ys, inBox (x, y), insidePolygons NonZero [poly] (x, y)]
   in if null ins then Nothing else Just (maximum ins)
  where
    crossY ((ax, ay), (bx, by)) y
      | ay == by = if y == ay then Just (max ax bx) else Nothing
      | min ay by <= y && y <= max ay by = Just (ax + (bx - ax) * (y - ay) / (by - ay))
      | otherwise = Nothing
    crossX ((ax, ay), (bx, by)) x
      | ax == bx = Nothing
      | min ax bx <= x && x <= max ax bx = Just (ay + (by - ay) * (x - ax) / (bx - ax))
      | otherwise = Nothing
