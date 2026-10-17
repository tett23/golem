-- | The shapes of the line styles of a rule (golem-driver ADR 0028).
module RuleShapeSpec (ruleShapeTests) where

import Golem.Driver.RuleShape
import Golem.LayoutSpec (Rect (..))
import Golem.Project.Style (RuleStyle (..))
import Test.Tasty
import Test.Tasty.HUnit

pt :: Rational -> Integer
pt x = round (x * 65536)

-- | A horizontal band of length l and weight w with its lower left corner at the origin.
band :: Integer -> Integer -> Rect
band = Rect 0 0

rects :: [RuleShape] -> [Rect]
rects ss = [r | ShapeRect r <- ss]

ruleShapeTests :: [TestTree]
ruleShapeTests =
  [ testCase "thin-thin: two lines of a third of the weight, their outer edges on the band" $ do
      let w = pt 1
      case rects (ruleShapes False (band (pt 100) w) (RuleMulti [1, 1, 1])) of
        [a, b] -> do
          rectY a + rectH a @?= w
          rectY b @?= 0
          assertBool (show a) (abs (rectH a - w `div` 3) <= 1)
          assertBool (show b) (abs (rectH b - w `div` 3) <= 1)
          rectW a @?= pt 100
        other -> assertFailure (show other),
    testCase "thick-thin: 2pt, a gap of 1pt and 1pt from the before side" $
      [(rectY r, rectH r) | r <- rects (ruleShapes False (band (pt 100) (pt 4)) (RuleMulti [2, 1, 1]))]
        @?= [(pt 2, pt 2), (0, pt 1)],
    testCase "thick-thin-thick: 2pt, 1pt, 1pt, 1pt, 2pt" $
      [(rectY r, rectH r) | r <- rects (ruleShapes False (band (pt 100) (pt 7)) (RuleMulti [2, 1, 1, 1, 2]))]
        @?= [(pt 5, pt 2), (pt 3, pt 1), (0, pt 2)],
    testCase "dashed: the dashes and gaps adjusted so that both ends are dashes" $ do
      let ds = rects (ruleShapes False (band (pt 100) (pt 1)) (RuleDashed (pt 3) (pt 2)))
      length ds @?= 20
      map rectX (take 1 ds) @?= [0]
      [rectX r + rectW r | r <- drop 19 ds] @?= [pt 100]
      -- T = 98pt: every dash is close to 3pt × 100/98
      assertBool (show (map rectW ds)) (all (\r -> abs (rectW r - pt (300 / 98)) <= 1) ds)
      assertBool "the weight" (all (\r -> rectY r == 0 && rectH r == pt 1) ds),
    testCase "dashed: a rule shorter than a dash and a gap is one line" $
      rects (ruleShapes False (band (pt 3) (pt 1)) (RuleDashed (pt 3) (pt 2))) @?= [Rect 0 0 (pt 3) (pt 1)],
    testCase "dotted: 34 discs, the first and the last inside the ends" $ do
      let ds = [(x, y, r) | ShapeDisc x y r <- ruleShapes False (band (pt 100) (pt 1)) (RuleDotted (pt 2))]
      length ds @?= 34
      take 1 ds @?= [(pt 0.5, pt 0.5, pt 0.5)]
      drop 33 ds @?= [(pt 99.5, pt 0.5, pt 0.5)],
    testCase "japanese dots: 34 squares of the weight" $ do
      let ds = rects (ruleShapes False (band (pt 100) (pt 1)) (RuleJapaneseDots (pt 2)))
      length ds @?= 34
      take 1 ds @?= [Rect 0 0 (pt 1) (pt 1)]
      drop 33 ds @?= [Rect (pt 99) 0 (pt 1) (pt 1)],
    testCase "wavy: 13 half periods on each edge, touching both edges of the band and inside it" $
      case ruleShapes False (band (pt 100) (pt 4)) RuleWavy of
        [ShapeCurve start segs] -> do
          -- the upper edge, the end, the lower edge back
          length segs @?= 13 + 1 + 13
          let ys = fromInteger (snd start) : concat [map snd (bezier p0 s) | (p0, s) <- zip (start : [e | (_, _, e) <- segs]) segs]
          assertBool (show (maximum ys)) (abs (maximum ys - fromInteger (pt 4)) <= 2)
          assertBool (show (minimum ys)) (abs (minimum ys) <= 2)
          assertBool "inside the band" (all (\y -> y >= -1 && y <= fromInteger (pt 4) + 1) ys)
        other -> assertFailure (show other),
    testCase "vertical: the same division down from the top of the band" $ do
      let ds = rects (ruleShapes True (Rect 0 0 (pt 1) (pt 100)) (RuleDashed (pt 3) (pt 2)))
      length ds @?= 20
      [rectY r + rectH r | r <- take 1 ds] @?= [pt 100]
      map rectY (drop 19 ds) @?= [0]
      assertBool "the weight across" (all (\r -> rectX r == 0 && rectW r == pt 1) ds)
      [(rectX r, rectW r) | r <- rects (ruleShapes True (Rect 0 0 (pt 4) (pt 100)) (RuleMulti [2, 1, 1]))]
        @?= [(pt 2, pt 2), (0, pt 1)],
    testCase "the thinnest part of each style" $ do
      ruleThinnest (pt 1) RuleSolid @?= pt 1
      ruleThinnest (pt 4) (RuleMulti [2, 1, 1]) @?= pt 1
      ruleThinnest (pt 4) RuleWavy @?= pt 1
      ruleThinnest (pt 1) (RuleDotted (pt 2)) @?= pt 1
  ]
  where
    -- points along a cubic curve
    bezier (x0, y0) ((x1, y1), (x2, y2), (x3, y3)) =
      [ (b (fromInteger x0) (fromInteger x1) (fromInteger x2) (fromInteger x3) t, b (fromInteger y0) (fromInteger y1) (fromInteger y2) (fromInteger y3) t)
      | i <- [0 .. 64 :: Int],
        let t = fromIntegral i / 64
      ]
    b :: Double -> Double -> Double -> Double -> Double -> Double
    b p0 p1 p2 p3 t = (1 - t) ^ (3 :: Int) * p0 + 3 * (1 - t) ^ (2 :: Int) * t * p1 + 3 * (1 - t) * t * t * p2 + t ^ (3 :: Int) * p3
