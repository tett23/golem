{- | Curves made polylines (root ADR 0437 I4): de Casteljau's halving until
both inner control points are within 1/4 sp of the chord.
-}
module FlattenSpec (tests) where

import Golem.Geometry
import Golem.Geometry.Polygon
import Test.Tasty
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "flattening"
    [ testCase "the squared distance of a point to a chord" $ do
        chordDistance2 (0, 0) (10, 0) (5, 3) @?= 9
        chordDistance2 (0, 0) (10, 0) (13, 4) @?= 25
        chordDistance2 (0, 0) (0, 0) (3, 4) @?= 25,
      testCase "root ADR 0437 I4: the halves of a curve meet at its middle and keep its ends" $
        let (l@(a, _, _, m), r@(m', _, _, d)) = splitCurve ((0, 0), (0, 8), (8, 8), (8, 0))
         in do
              (a, m, m', d) @?= ((0, 0), (4, 6), (4, 6), (8, 0))
              assertBool (show (l, r)) (l /= r),
      testCase "root ADR 0437 I4: each piece of a quarter of a circle is flat within (1/4 sp)^2" $
        flatWithin (quarter 6553600),
      testCase "root ADR 0437 I4: each piece of an S curve is flat within (1/4 sp)^2" $
        flatWithin ((0, 0), (3000000, 4000000), (-1000000, 4000000), (2000000, 8000000)),
      testCase "root ADR 0437 I4: the pieces follow one another from the start to the end of the curve" $
        let b@(s, _, _, e) = quarter 655360
            ps = flatPieces b
         in do
              [p0 | (p0, _, _, _) <- take 1 ps] @?= [s]
              [p3 | (_, _, _, p3) <- drop (length ps - 1) ps] @?= [e]
              and (zipWith (\(_, _, _, p3) (p0, _, _, _) -> p3 == p0) ps (drop 1 ps)) @?= True,
      testCase "root ADR 0437 I4: a curve whose control points are on its chord is not split" $
        let b = ((0, 0), (1000, 0), (3000, 0), (4000, 0))
         in flatPieces b @?= [b],
      testCase "root ADR 0437 I4: a path is flattened to the ends of its pieces" $
        let p = Path [SubPath (0, 0) [LineTo (10, 0), CurveTo (10, 5) (10, 5) (10, 10)] True]
         in flattenPath p @?= [[(0, 0), (10, 0), (10, 10)]]
    ]

flatWithin :: Bezier -> IO ()
flatWithin b =
  let ps = flatPieces b
      bad = [p | p@(s, c1, c2, e) <- ps, chordDistance2 s e c1 > flattenTolerance2 || chordDistance2 s e c2 > flattenTolerance2]
   in do
        flattenTolerance2 @?= 1 / 16
        assertBool "the curve is split" (length ps > 1)
        take 1 bad @?= []

-- | A quarter of a circle of the radius, as one cubic curve.
quarter :: Rational -> Bezier
quarter r =
  let k = 5522847498 / 10000000000 * r
   in ((r, 0), (r, k), (k, r), (0, r))
