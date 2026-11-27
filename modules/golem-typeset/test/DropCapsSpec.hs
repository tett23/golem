-- | Initials align by cap height or by em-box edges (root ADR 0465).
module DropCapsSpec (dropCapsTests) where

import Data.Ratio ((%))
import Golem.LayoutSpec (baselineRatio)
import Golem.Project.Style (Sp (..))
import Golem.Typeset.Internal (dropCapMetrics)
import Test.Tasty
import Test.Tasty.HUnit

-- | Rounding to integral sp can differ from an exact edge by at most one sp.
near :: Rational -> Rational -> Assertion
near expected actual = assertBool (show (expected, actual)) (abs (expected - actual) <= 1)

lengths :: [(Sp, Sp, Int)]
lengths = [(size, pitch, n) | size <- [10 * 65536, 12 * 65536], pitch <- [10 * 65536, 15 * 65536, 1212416], n <- [1, 2, 3, 5]]

spRatio :: Sp -> Rational
spRatio = toRational . unSp

dropCapsTests :: TestTree
dropCapsTests =
  testGroup
    "root ADR 0465 initial geometry"
    [ testCase "root ADR 0465 I4: Latin cap-height tops and last baselines align across fonts" $
        sequence_
          [ do
              let (large, shift) = dropCapMetrics False True size pitch n bodyCap initialCap
              near (spRatio size * bodyCap) (spRatio large * initialCap + spRatio shift)
              shift + fromIntegral (n - 1) * pitch @?= 0
          | (size, pitch, n) <- lengths,
            (bodyCap, initialCap) <- [(66 % 100, 66 % 100), (7 % 10, 1 % 2), (1 % 2, 7 % 10)]
          ],
      testCase "root ADR 0465 I4: horizontal Japanese em-box edges coincide with the first and last rows" $
        sequence_
          [ do
              let (large, shift) = dropCapMetrics False False size pitch n (7 % 10) (1 % 2)
                  extra = spRatio (fromIntegral (n - 1) * pitch)
              near (spRatio size * baselineRatio) (spRatio large * baselineRatio + spRatio shift)
              near (negate extra - spRatio size * (1 - baselineRatio)) (spRatio shift - spRatio large * (1 - baselineRatio))
          | (size, pitch, n) <- lengths
          ],
      testCase "root ADR 0465 I4: vertical em-box edges align, including vertical Latin letters" $
        sequence_
          [ do
              let (large, shift) = dropCapMetrics True True size pitch n (7 % 10) (1 % 2)
                  extra = spRatio (fromIntegral (n - 1) * pitch)
              near (spRatio size / 2) (spRatio large / 2 + spRatio shift)
              near (negate extra - spRatio size / 2) (spRatio shift - spRatio large / 2)
          | (size, pitch, n) <- lengths
          ]
    ]
