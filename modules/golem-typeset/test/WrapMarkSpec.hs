{- | The shape of the default wrap mark of inline code: a thin return arrow
in a square of 3/5 of the size of the code, and its colour (golem-layout
ADR 0042, W1, W4 to W7, W12 and W13).
-}
module WrapMarkSpec (wrapMarkTests) where

import Golem.Pdf qualified as P
import Golem.Project.Style (Sp (..))
import Golem.Typeset.WrapMark
import Test.Tasty
import Test.Tasty.HUnit

-- | 10pt, and a size that neither 5 nor 20 divides.
s10, odd10 :: Sp
s10 = 655360
odd10 = 655363

-- | The points of the polygons.
pointsOf :: [[(Sp, Sp)]] -> [(Sp, Sp)]
pointsOf = concat

-- | The width of the square: 3/5 of the size, rounded down.
side :: Sp -> Sp
side (Sp s) = Sp ((s * 3) `div` 5)

-- | The width of a polygon across x and y.
extent :: [(Sp, Sp)] -> (Sp, Sp)
extent ps = (maximum (map fst ps) - minimum (map fst ps), maximum (map snd ps) - minimum (map snd ps))

-- | Within one sp.
near :: Sp -> Sp -> Bool
near a b = abs (a - b) <= 1

wrapMarkTests :: [TestTree]
wrapMarkTests =
  [ testCase "W13: the polygons of a mark of 10pt at the origin are fixed sp, horizontal" $
      wrapMarkPolygons False (0, 0) s10
        @?= [ [(306053, 154009), (338821, 154009), (338821, 367001), (306053, 367001)],
              [(79953, 154009), (338821, 154009), (338821, 186777), (79953, 186777)],
              [(37355, 183500), (131727, 254279), (151388, 228065), (57016, 157286)],
              [(57016, 183500), (151388, 112721), (131727, 86507), (37355, 157286)]
            ],
    testCase "W13: the polygons of a mark of 10pt at the origin are fixed sp, vertical" $
      wrapMarkPolygons True (0, 0) s10
        @?= [ [(-95028, -306054), (-95028, -338822), (117964, -338822), (117964, -306054)],
              [(-95028, -79954), (-95028, -338822), (-62260, -338822), (-62260, -79954)],
              [(-65536, -37356), (5242, -131728), (-20972, -151389), (-91751, -57017)],
              [(-65536, -57017), (-136315, -151389), (-162530, -131728), (-91751, -37356)]
            ],
    testCase "W13: a size neither 5 nor 20 divides, away from the origin" $
      wrapMarkPolygons False (1000, 2000) odd10
        @?= [ [(307053, 156010), (339821, 156010), (339821, 369003), (307053, 369003)],
              [(80954, 156010), (339821, 156010), (339821, 188778), (80954, 188778)],
              [(38355, 185501), (132727, 256280), (152388, 230066), (58016, 159287)],
              [(58016, 185501), (152388, 114722), (132727, 88508), (38355, 159287)]
            ],
    testCase "W1: every point of a horizontal mark is in the square of 3/5 of the size from the origin along the line, centred 0.38 em above the baseline" $
      mapM_
        ( \(o@(ox, oy), s) -> do
            let w = side s
                cy = oy + Sp ((unSp s * 19) `div` 50)
                lo = cy - Sp (unSp w `div` 2) - 1
                hi = cy + Sp (unSp w `div` 2) + 1
            assertBool (show (o, s)) (all (\(x, y) -> x >= ox && x <= ox + w && y >= lo && y <= hi) (pointsOf (wrapMarkPolygons False o s)))
        )
        [((0, 0), s10), ((1000, 2000), odd10), ((-7, 3), 3 * 65536 + 1)],
    testCase "W1: every point of a vertical mark is in the square below the origin, centred on the centre line" $
      mapM_
        ( \(o@(ox, oy), s) -> do
            let w = side s
                half = Sp (unSp w `div` 2) + 1
            assertBool (show (o, s)) (all (\(x, y) -> y <= oy && y >= oy - w && x >= ox - half && x <= ox + half) (pointsOf (wrapMarkPolygons True o s)))
        )
        [((0, 0), s10), ((1000, 2000), odd10)],
    testCase "W1: four parts of four points each: the stem, the line along and the two strokes of the head" $
      map length (wrapMarkPolygons False (0, 0) odd10) @?= [4, 4, 4, 4],
    testCase "W4: the stem and the line along are 1/20 of the size thick, within 1 sp" $
      mapM_
        ( \s -> case wrapMarkPolygons False (0, 0) s of
            (stem : along : _) -> do
              let t = Sp (unSp s `div` 20)
              assertBool (show (s, extent stem)) (near (fst (extent stem)) t)
              assertBool (show (s, extent along)) (near (snd (extent along)) t)
            other -> assertFailure (show other)
        )
        [s10, odd10, 3 * 65536 + 7],
    testCase "W5: horizontal, the centre of the square is (0.88 - 1/2) em above the baseline" $
      case wrapMarkPolygons False (0, 0) s10 of
        (_ : along : _) -> do
          -- the line along is centred 0.30 of the square up: 0.2 of the square below the centre
          let w = side s10
              mid = Sp ((unSp (minimum (map snd along)) + unSp (maximum (map snd along))) `div` 2)
          assertBool (show mid) (abs (mid + Sp ((unSp w * 2) `div` 10) - Sp ((unSp s10 * 38) `div` 100)) <= 1)
        other -> assertFailure (show other),
    testCase "W6: the vertical mark is the horizontal one turned 90 degrees clockwise about the centre of its square" $
      mapM_
        ( \s -> do
            let w = toRational (unSp (side s))
                hc = (w / 2, toRational (unSp s) * 19 / 50)
                vc = (0, negate w / 2)
                turn (x, y) = (toRational (unSp y) - snd hc + fst vc, negate (toRational (unSp x) - fst hc) + snd vc)
                close (x, y) (a, b) = abs (toRational (unSp x) - a) <= 2 && abs (toRational (unSp y) - b) <= 2
            and (zipWith close (pointsOf (wrapMarkPolygons True (0, 0) s)) (map turn (pointsOf (wrapMarkPolygons False (0, 0) s)))) @? show s
        )
        [s10, odd10],
    testCase "W1: each part is a CurveFill of straight edges, its control points at the ends, closed at its start" $
      case wrapMarkFills [[(0, 0), (2, 0), (2, 1)]] of
        [P.CurveFill (0, 0) [((0, 0), (2, 0), (2, 0)), ((2, 0), (2, 1), (2, 1)), ((2, 1), (0, 0), (0, 0))]] -> pure ()
        other -> assertFailure (show other),
    testCase "W7: the colour of the mark is half of each value of the code's, rounded down" $ do
      wrapMarkSwatch (Just (P.Swatch 45 25 0 15)) @?= P.Swatch 22 12 0 7
      wrapMarkSwatch (Just (P.Swatch 90 50 0 20)) @?= P.Swatch 45 25 0 10,
    testCase "W7: code of no colour and code of black 100% draw the mark in black 50%" $ do
      wrapMarkSwatch Nothing @?= P.Swatch 0 0 0 50
      wrapMarkSwatch (Just (P.Swatch 0 0 0 100)) @?= P.Swatch 0 0 0 50,
    testCase "W12: the total ink of the mark is not more than the code's" $
      mapM_
        ( \sw@(P.Swatch c m y k) -> case wrapMarkSwatch (Just sw) of
            P.Swatch c' m' y' k' -> assertBool (show sw) (c' + m' + y' + k' <= c + m + y + k)
        )
        [P.Swatch c m y k | c <- [0, 1, 99, 100], m <- [0, 33, 100], y <- [0, 7], k <- [0, 15, 100]]
  ]
