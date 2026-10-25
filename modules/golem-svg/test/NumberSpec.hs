{- | The numbers of SVG (golem-pdf ADR 0009, docs/adr ADR 0041): the
reading of a number with its limit, and the series of the trigonometric
functions and the square root.
-}
module NumberSpec (numberTests) where

import Data.Ratio ((%))
import Data.Text qualified as T
import Golem.Svg.Number
import Golem.TestSupport.TimeLimit (hangLimits, withinTimeLimits)
import Test.Tasty
import Test.Tasty.HUnit

-- | Within 2^-36 of each other: the series are rounded to 2^-40.
near :: Rational -> Rational -> Bool
near a b = abs (a - b) <= 1 % (2 ^ (36 :: Int))

assertNear :: String -> Rational -> Rational -> Assertion
assertNear = assertWithin near

{- | Within 2^-29 degrees: the halvings of atan and the conversion to
degrees lose a few bits of the 2^-40 of the series.
-}
assertNearDeg :: String -> Rational -> Rational -> Assertion
assertNearDeg = assertWithin (\a b -> abs (a - b) <= 1 % (2 ^ (29 :: Int)))

assertWithin :: (Rational -> Rational -> Bool) -> String -> Rational -> Rational -> Assertion
assertWithin close what expected got = assertBool (what <> ": " <> show (fromRational got :: Double) <> " is not near " <> show (fromRational expected :: Double)) (close expected got)

-- | Every whole degree of two turns either way, and some fractions.
degrees :: [Rational]
degrees = map fromInteger [-720 .. 720] <> [1 % 3, 45 % 2, (-89) % 7, 179 + 999 % 1000]

numberTests :: TestTree
numberTests =
  testGroup
    "numbers (golem-pdf ADR 0009)"
    [ testCase "the forms of a number" $
        map
          (\t -> (t, parseNumber t))
          ["0", "1", "-1.5", "+.5", "1.", "007", "1e3", "1E-2", "-2.5e+2", " 2 ", "0.000001"]
          @?= [ ("0", Just 0),
                ("1", Just 1),
                ("-1.5", Just ((-3) % 2)),
                ("+.5", Just (1 % 2)),
                ("1.", Just 1),
                ("007", Just 7),
                ("1e3", Just 1000),
                ("1E-2", Just (1 % 100)),
                ("-2.5e+2", Just (-250)),
                (" 2 ", Just 2),
                ("0.000001", Just (1 % 1000000))
              ],
      testCase "what is not a number" $
        map (\t -> (t, parseNumber t)) ["", ".", "-", "e5", "1e", "1e+", "1.2.3", "1px", "--1", "1e12345", "0x10"]
          @?= map (,Nothing) ["", ".", "-", "e5", "1e", "1e+", "1.2.3", "1px", "--1", "1e12345", "0x10"],
      testCase "the prefix of a number and the rest after it" $ do
        numberPrefix "12px" @?= Just (12, "px")
        numberPrefix "-3.5e1,4" @?= Just (-35, ",4")
        numberPrefix "1e" @?= Just (1, "e")
        numberPrefix ".5.5" @?= Just (1 % 2, ".5")
        numberPrefix "px" @?= Nothing,
      testCase "at most 10^9 in absolute value, however it is written (docs/adr ADR 0041)" $ do
        map parseNumber ["1000000000", "-1000000000", "1e9", "0.1e10", "1000000000.0", "999999999.999"]
          @?= map Just [10 ^ (9 :: Int), -(10 ^ (9 :: Int)), 10 ^ (9 :: Int), 10 ^ (9 :: Int), 10 ^ (9 :: Int), 999999999999 % 1000]
        map parseNumber ["1000000001", "-1000000001", "1e10", "1.000000001e9", "1000000000.1", "1e9999"] @?= replicate 6 Nothing
        parseNumber "0e9999" @?= Just 0
        numberLimit @?= 10 ^ (9 :: Int),
      testCase "a number that is not 0 is at least 10^-9 in absolute value (docs/adr ADR 0083)" $ do
        map parseNumber ["1e-9", "-1e-9", "0.000000001", "10e-10", "1" <> T.replicate 59 "0" <> "e-68"]
          @?= map Just [1 % (10 ^ (9 :: Int)), -(1 % (10 ^ (9 :: Int))), 1 % (10 ^ (9 :: Int)), 1 % (10 ^ (9 :: Int)), 1 % (10 ^ (9 :: Int))]
        map parseNumber ["1e-10", "-1e-10", "1e-9999", "0.000000000999", "9.99999999e-10", "0.0000000001", T.replicate 60 "9" <> "e-70"] @?= replicate 7 Nothing
        map parseNumber ["0", "-0", "0e-9999", "0.0", "0e5"] @?= replicate 5 (Just 0)
        numberFloor @?= 1 % (10 ^ (9 :: Int)),
      testCase "a number of 60 digits and an exponent of -9999 is judged without the power of ten (docs/adr ADR 0083)" $ withinTimeLimits hangLimits $ do
        parseNumber "1e-9999" @?= Nothing
        parseNumber (T.replicate 60 "9" <> "e-9999") @?= Nothing
        outOfRange (T.replicate 60 "9" <> "e-9999") @?= True,
      testCase "60 digits are read, 61 are not" $ do
        -- the digits before and after the point together
        parseNumber ("1." <> T.replicate 58 "0" <> "1") @?= Just (1 + 1 % (10 ^ (59 :: Int)))
        parseNumber ("1." <> T.replicate 59 "0" <> "1") @?= Nothing
        parseNumber (T.replicate 60 "0") @?= Just 0
        parseNumber (T.replicate 61 "0") @?= Nothing,
      testCase "outOfRange finds a number outside the range anywhere in a text, tooSmall a small one (docs/adr ADR 0083)" $ do
        map outOfRange ["1e10", "a 1e-10 b", "M0,0 L1,1e-10", "1e-9", "0", "0e-9999", "abc", "rgb(1e-10, 0, 0)"]
          @?= [True, True, True, False, False, False, False, True]
        map tooSmall ["1e10", "1e-10", "0 1e-9999", "1e-9", "0"] @?= [False, True, True, False, False]
        map tooLarge ["1e10", "1e-10"] @?= [True, False],
      testCase "tooLarge finds a number past the limit anywhere in a text" $
        map
          (\t -> (t, tooLarge t))
          ["1e10", "a 2000000000 b", "M0,0 L1,1e10", "1000000000", "1e9", "0e9999", "abc", "", "-1000000001", "1.5e9"]
          @?= zip
            ["1e10", "a 2000000000 b", "M0,0 L1,1e10", "1000000000", "1e9", "0e9999", "abc", "", "-1000000001", "1.5e9"]
            [True, True, True, False, False, False, False, False, True, True],
      testCase "the right angles are exact, in any turn" $
        [(d, cosDeg d, sinDeg d) | d <- [-450, -360, -270, -180, -90, 0, 90, 180, 270, 360, 450, 720]]
          @?= [ (-450, 0, -1),
                (-360, 1, 0),
                (-270, 0, 1),
                (-180, -1, 0),
                (-90, 0, -1),
                (0, 1, 0),
                (90, 0, 1),
                (180, -1, 0),
                (270, 0, -1),
                (360, 1, 0),
                (450, 0, 1),
                (720, 1, 0)
              ],
      testCase "cos and sin of known angles" $ do
        assertNear "sin 30" (1 % 2) (sinDeg 30)
        assertNear "cos 60" (1 % 2) (cosDeg 60)
        assertNear "sin 150" (1 % 2) (sinDeg 150)
        assertNear "cos 120" ((-1) % 2) (cosDeg 120)
        assertNear "sin -30" ((-1) % 2) (sinDeg (-30))
        assertNear "sin 210" ((-1) % 2) (sinDeg 210)
        assertNear "cos 300" (1 % 2) (cosDeg 300)
        assertNear "cos 45 squared" (1 % 2) (cosDeg 45 * cosDeg 45)
        assertNear "tan 45" 1 (tanDeg 45)
        assertNear "tan -45" (-1) (tanDeg (-45))
        assertNear "tan 135" (-1) (tanDeg 135)
        tanDeg 90 @?= 0,
      testCase "cos^2 + sin^2 is 1 and a turn changes nothing, at every degree" $
        mapM_
          ( \d -> do
              assertNear ("cos^2 + sin^2 at " <> show d) 1 (cosDeg d ^ (2 :: Int) + sinDeg d ^ (2 :: Int))
              (cosDeg (d + 360), sinDeg (d + 360)) @?= (cosDeg d, sinDeg d)
              assertNear ("sin(-x) at " <> show d) (negate (sinDeg d)) (sinDeg (negate d))
              assertNear ("cos(90 - x) at " <> show d) (sinDeg d) (cosDeg (90 - d))
          )
          degrees,
      testCase "atan2 gives back the angle in (-180, 180]" $
        mapM_
          ( \d -> do
              let expected = d - 360 * fromInteger (ceiling ((d - 180) / 360))
                  got = atan2Deg (sinDeg d) (cosDeg d)
              assertNearDeg ("atan2 at " <> show d) expected got
              assertBool ("in range at " <> show d) (got > -180 && got <= 180)
              assertNearDeg ("atan2 scaled at " <> show d) got (atan2Deg (7 * sinDeg d) (7 * cosDeg d))
          )
          [d | d <- degrees, d `notElem` [-540, -180, 180, 540]],
      testCase "atan2 on the axes" $
        [atan2Deg y x | (y, x) <- [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (5, 5), (-5, -5)]] @?= [0, 90, -90, 0, 180, atan2Deg 1 1, atan2Deg (-1) (-1)],
      testCase "atan2 of the diagonals" $ do
        assertNearDeg "45" 45 (atan2Deg 1 1)
        assertNearDeg "135" 135 (atan2Deg 1 (-1))
        assertNearDeg "-45" (-45) (atan2Deg (-1) 1)
        assertNearDeg "-135" (-135) (atan2Deg (-1) (-1)),
      testCase "the square root is exact on squares and the floor at 2^-40 elsewhere" $ do
        map sqrtR [0, 1, 4, 9 % 4, 1 % 65536, 10 ^ (18 :: Int)] @?= [0, 1, 2, 3 % 2, 1 % 256, 10 ^ (9 :: Int)]
        map sqrtR [-1, -4] @?= [0, 0]
        let step = 1 % (2 ^ (40 :: Int))
        mapM_
          ( \x -> do
              let s = sqrtR x
              assertBool ("floor of the root of " <> show x) (s * s <= x && (s + step) * (s + step) > x)
          )
          [2, 3, 1 % 3, 10, 1000000007, 1 % 1000]
        norm (3, 4) @?= 5
        norm (-5, 12) @?= 13,
      testCase "roundTo is to 2^-40, half to even" $ do
        roundTo (1 % 3) @?= round ((1 % 3) * 2 ^ (40 :: Int) :: Rational) % (2 ^ (40 :: Int))
        roundTo (1 % (2 ^ (41 :: Int))) @?= 0
        roundTo (3 % (2 ^ (41 :: Int))) @?= 2 % (2 ^ (40 :: Int))
        roundTo 5 @?= 5
    ]
