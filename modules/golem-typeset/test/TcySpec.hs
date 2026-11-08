-- | The fit of a tate-chu-yoko in its box (golem-driver ADR 0045), with fixed advances.
module TcySpec (tcyTests) where

import Golem.Typeset.Tcy (TcyFit (..), squeezed, tcyFit)
import Test.Tasty
import Test.Tasty.HUnit

-- | The size of the box: 10pt in sp.
s :: Integer
s = 10 * 65536

tcyTests :: [TestTree]
tcyTests =
  [ testCase "I4: W = s − 1 sp is not scaled" $
      tfScale (tcyFit s [s `div` 2, s `div` 2 - 1]) @?= 1000,
    testCase "I4: W = s is not scaled" $ do
      let f = tcyFit s [s `div` 2, s `div` 2]
      tfScale f @?= 1000
      tfWidth f @?= s,
    testCase "I4: W = s + 1 sp is scaled by ⌊1000 × s / W⌋, at most 999, and W' ≤ s" $ do
      let f = tcyFit s [s `div` 2, s `div` 2 + 1]
      tfScale f @?= fromInteger ((1000 * s) `div` (s + 1))
      assertBool (show f) (tfScale f <= 999 && tfWidth f <= s),
    testCase "I4: W = 2s is scaled by 500, W' = s" $ do
      let f = tcyFit s [s `div` 2, s `div` 2, s `div` 2, s `div` 2]
      tfScale f @?= 500
      tfWidth f @?= s,
    testCase "I4: W' ≤ s for every W from s to 4s in steps of 997 sp" $
      let bad = [w | w <- [s, s + 997 .. 4 * s], let f = tcyFit s [w], tfWidth f > s || (w > s && tfScale f /= fromInteger ((1000 * s) `div` w))]
       in bad @?= [],
    testCase "I2: the glyphs start at the scaled sums of the advances before them, in order" $ do
      let f = tcyFit s [s, s `div` 2, s]
      tfOffsets f @?= [0, squeezed (tfScale f) s, squeezed (tfScale f) (s + s `div` 2)]
      assertBool (show f) (and (zipWith (<) (tfOffsets f) (drop 1 (tfOffsets f)))),
    testCase "an empty tate-chu-yoko has no glyphs and no width" $
      tcyFit s [] @?= TcyFit 1000 0 []
  ]
