-- | Lengths and the conversions of their units (docs/adr ADR 0103).
module LengthSpec (tests) where

import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Length
import Golem.Length.Decimal (showRationalDigits)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

-- | A rational of up to four decimals, as a length is written in style.toml.
genRational :: Gen Rational
genRational = do
  n <- Gen.integral (Range.linearFrom 0 (-10000000) 10000000)
  d <- Gen.element [1, 10, 100, 1000, 10000]
  pure (n % d)

genSp :: Gen Sp
genSp = Sp <$> Gen.integral (Range.linearFrom 0 (-100000000) 100000000)

-- | Hundredths written to two decimals, independently of mmText.
hundredths :: Integer -> Text
hundredths k =
  let (i, f) = k `divMod` 100
   in T.pack (show i <> "." <> (if f < 10 then "0" else "") <> show f <> "mm")

tests :: TestTree
tests =
  testGroup
    "length (docs/adr ADR 0103)"
    [ testGroup
        "toSp"
        [ testCase "1pt is 65536sp" $ toSp Pt 1 @?= 65536,
          testCase "1in is 72pt" $ toSp In 1 @?= 4718592,
          testCase "25.4mm is 1in" $ toSp Mm (254 % 10) @?= 4718592,
          testCase "4Q is 1mm" $ toSp Q 4 @?= toSp Mm 1,
          testCase "4H is 1mm" $ toSp H 4 @?= toSp Mm 1,
          testProperty "mm rounds once, half to even, as parseDim did" $ property $ do
            r <- forAll genRational
            unSp (toSp Mm r) === round (r * 72 * 65536 / (254 % 10)),
          testProperty "pt rounds once, half to even, as parseDim did" $ property $ do
            r <- forAll genRational
            unSp (toSp Pt r) === round (r * 65536)
        ],
      testGroup
        "fromSp"
        [ testProperty "pt is exact" $ property $ do
            s <- forAll genSp
            fromSp Pt s * 65536 === toRational (unSp s),
          testProperty "in is exact" $ property $ do
            s <- forAll genSp
            fromSp In s * 72 * 65536 === toRational (unSp s)
        ],
      testGroup
        "zwToSp"
        [ testCase "a quarter of 10pt" $ zwToSp 655360 (1 % 4) @?= 163840,
          testCase "2.5 rounds to 2" $ zwToSp 10 (1 % 4) @?= 2,
          testCase "3.5 rounds to 4" $ zwToSp 14 (1 % 4) @?= 4,
          testCase "333/1000 of 10.5pt is rounded once (docs/adr ADR 0114)" $ do
            -- 333 × 688128 / 1000 = 229146.624
            zwToSp 688128 (333 % 1000) @?= 229147
            -- rounding each step separately would give a different value
            unSp (zwToSp 688128 (333 % 1000)) /= round (fromIntegral (round (333 / 1000 * 10.5 * 100 :: Double) :: Integer) / 100 * 65536 :: Double) @?= True,
          testCase "half of 1sp rounds to the even 0" $ zwToSp 1 (1 % 2) @?= 0,
          testCase "half of 3sp rounds to the even 2" $ zwToSp 3 (1 % 2) @?= 2
        ],
      testGroup
        "mmText"
        [ testCase "0.1mm" $ mmText 18577 @?= "0.10mm",
          testCase "-0.1mm" $ mmText (-18577) @?= "-0.10mm",
          testCase "zero" $ mmText 0 @?= "0.00mm",
          testCase "a negative value that rounds to zero has no sign" $ mmText (-1) @?= "0.00mm",
          testCase "3mm keeps its trailing zeros" $ mmText (toSp Mm 3) @?= "3.00mm",
          testCase "18pt is 6.35mm" $ mmText (toSp Pt 18) @?= "6.35mm",
          testCase "27pt (9.525mm) rounds half to even" $ mmText (toSp Pt 27) @?= "9.52mm",
          testCase "9pt (3.175mm) rounds half to even" $ mmText (toSp Pt 9) @?= "3.18mm",
          testProperty "hundredths of a mm come back unrounded" $ property $ do
            k <- forAll (Gen.integral (Range.linear 0 100000))
            mmText (toSp Mm (k % 100)) === hundredths k
        ],
      testGroup
        "ptText and emText"
        [ testCase "1sp is 0pt at four decimals" $ ptText 1 @?= "0",
          testCase "65536sp is 1pt" $ ptText 65536 @?= "1",
          testCase "3mm is 8.5039pt" $ ptText (toSp Mm 3) @?= "8.5039",
          testCase "9pt on 12.6pt is 0.7143em" $ emText (9 / (126 % 10)) @?= "0.7143"
        ],
      testGroup
        "showRationalDigits (docs/adr ADR 0114)"
        [ testCase "four digits of 0.03125 is 0.0312" $ showRationalDigits 4 (2048 % 65536) @?= "0.0312",
          testCase "six digits of -1/3 is -0.333333" $ showRationalDigits 6 (-(1 % 3)) @?= "-0.333333",
          testCase "ten digits of 1/20 is 0.05" $ showRationalDigits 10 (1 % 20) @?= "0.05"
        ]
    ]
