{- | Lines beside a figure wrapped along its outline (root ADR 0464): the
outline placed on the image, the edge of the area within the band of each
line, and what each line loses.
-}
module WrapOutlineSpec (wrapOutlineTests) where

import Data.Text qualified as T
import Golem.Geometry (FillRule (..))
import Golem.Geometry.Polygon (RPoint, insidePolygons)
import Golem.Layout.KnuthPlass (Sp (..))
import Golem.Layout.Wrap
import Golem.Project.PathData (outlineScale, readOutlinePath)
import Test.Tasty
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

wrapOutlineTests :: TestTree
wrapOutlineTests =
  testGroup
    "outlines of wrapped figures (root ADR 0464)"
    [ testGroup "placing an outline on its image" placing,
      testGroup "the boundary inputs" boundary,
      testGroup "small polygons and bands" enumerated
    ]

-- the figure of the tests: 1000 sp along, 600 sp across, a pitch of 100, the gap 30, the face 80
along, across, pitch, gap, face :: Sp
along = 1000
across = 600
pitch = 100
gap = 30
face = 80

outline :: Bool -> Wrap -> (Rational, Rational) -> (Sp, Sp) -> String -> IO [[RPoint]]
outline vertical side size placed src = case readOutlinePath (T.pack src) of
  Left e -> assertFailure (show e) >> pure []
  Right p -> pure (placeOutline vertical side (\(x, y) -> (x / fromInteger outlineScale, y / fromInteger outlineScale)) size placed p)

placing :: [TestTree]
placing =
  [ testCase "root ADR 0464 I3: a square on the image is the image, in horizontal writing at the start" $ do
      ps <- outline False WrapStart (100, 100) (along, across) squareSrc
      ps @?= [[(0, 0), (1000, 0), (1000, 600), (0, 600)]],
    testCase "root ADR 0464 I3: at the end the outline is measured from the end of the line" $ do
      ps <- outline False WrapEnd (100, 100) (along, across) squareSrc
      ps @?= [[(1000, 0), (0, 0), (0, 600), (1000, 600)]],
    testCase "root ADR 0464 I3: in vertical writing the lines go down and their progression to the left" $ do
      -- the image is 600 wide (across the lines) and 1000 high (along them)
      ps <- outline True WrapStart (100, 100) (along, across) squareSrc
      ps @?= [[(0, 600), (0, 0), (1000, 0), (1000, 600)]],
    testCase "root ADR 0464 I3: in vertical writing at the end the outline is measured from the bottom" $ do
      ps <- outline True WrapEnd (100, 100) (along, across) squareSrc
      ps @?= [[(1000, 600), (1000, 0), (0, 0), (0, 600)]],
    testCase "root ADR 0464: an outline is scaled with the image in each direction, from its own units" $ do
      -- an image of 200 by 50 pixels placed at 1000 by 600
      ps <- outline False WrapStart (200, 50) (along, across) "M 20 5 L 40.5 5 L 40.5 25 Z"
      ps @?= [[(100, 60), (2025 / 10, 60), (2025 / 10, 300)]]
  ]

rat :: Sp -> Rational
rat (Sp n) = fromInteger n

squareSrc :: String
squareSrc = "M 0 0 L 100 0 L 100 100 L 0 100 Z"

-- an exclusion of an outline on the image of 100 by 100, with a caption from 700 to 780 or none
outlined :: Wrap -> Bool -> [[RPoint]] -> Exclusion
outlined side captioned ps =
  let depth = if captioned then 780 else across
   in outlinedExclusion side pitch gap along depth (PlacedOutline ps (rat along, rat across) (if captioned then Just (700, 780) else Nothing))

rect :: Bool -> Exclusion
rect captioned = exclusion WrapStart pitch gap along (if captioned then 780 else across)

-- the band of grid line g: from its start, the face high
takeAt :: Exclusion -> Int -> Sp
takeAt ex g = lineTake ex (fromIntegral g * pitch) face

boundary :: [TestTree]
boundary =
  [ testCase "root ADR 0464 I1: a figure without an outline loses its width and the gap on every line, wherever its band" $
      let ex = rect True
       in [s | s <- map Sp [-200, -170 .. 1200], f <- [0, 80, 150], lineTake ex s f /= exWidth ex] @?= [],
    testCase "root ADR 0464 I1: a figure without an outline keeps the line lengths L*(i)" $
      [wrappedLineWidth 3000 (rect False) 0 i | i <- [0 .. 7]] @?= replicate 7 (3000 - 1030) <> [3000],
    testCase "root ADR 0464 I3: an outline the same as the image loses what the rectangle loses beside the image and the caption" $ do
      ps <- outline False WrapStart (100, 100) (along, across) squareSrc
      let ex = outlined WrapStart True ps
      exLines ex @?= 9
      [takeAt ex g | g <- [0 .. exLines ex - 1]] @?= replicate 9 1030,
    testCase "root ADR 0464 I3: an outline past the image is clipped to it" $ do
      ps <- outline False WrapStart (100, 100) (along, across) "M -50 -50 L 150 -50 L 150 150 L -50 150 Z"
      let ex = outlined WrapStart False ps
      [takeAt ex g | g <- [0 .. exLines ex - 1]] @?= replicate (exLines ex) 1030,
    testCase "root ADR 0464 I2, I3, I4: a triangle of the lower left, the lower right and the top at the end gives longer lines higher up" $ do
      ps <- outline False WrapEnd (100, 100) (along, across) "M 0 100 L 100 100 L 50 0 Z"
      let ex = outlined WrapEnd False ps
          takes = [takeAt ex g | g <- [0 .. exLines ex - 1]]
      assertBool (show takes) (and (zipWith (<=) takes (drop 1 takes)) && take 1 takes < drop (length takes - 1) takes)
      -- the band of line 0 widened by the gap reaches y = 110 sp, where the edge is at x = 500 - 110 * 500 / 600
      take 1 takes @?= [Sp (ceiling (1000 - (500 - 110 * 500 / 600 :: Rational))) + gap],
    testCase "root ADR 0464 I2, I4: a circle of four cubic curves gives its shortest line in the middle" $ do
      ps <- outline False WrapStart (100, 100) (along, 1000) circleSrc
      let ex = outlinedExclusion WrapStart pitch gap along 1000 (PlacedOutline ps (1000, 1000) Nothing)
          takes = [takeAt ex g | g <- [0 .. exLines ex - 1]]
          widest = maximum takes
      assertBool (show takes) (takes !! 4 == widest || takes !! 5 == widest)
      assertBool (show takes) (all (< widest) (take 1 takes <> drop (length takes - 1) takes)),
    testCase "root ADR 0464 I3: a line whose band does not meet the outline keeps the measure" $ do
      ps <- outline False WrapStart (100, 100) (along, across) "M 0 0 L 100 0 L 50 30 Z"
      let ex = outlined WrapStart False ps
      -- the outline ends at 180 sp; line 3 starts at 300, its band widened by the gap at 270
      [takeAt ex g | g <- [3 .. exLines ex - 1]] @?= replicate (exLines ex - 3) 0,
    testCase "root ADR 0464 I2: a vertex exactly on the top side of the widened band is in the band" $ do
      -- the lowest vertex (800, 240) is where the band of the line at 270 begins once widened by 30
      ps <- outline False WrapStart (100, 100) (along, across) "M 0 0 L 100 0 L 80 40 Z"
      lineTake (outlined WrapStart False ps) 270 face @?= 800 + gap,
    testCase "root ADR 0464 I3: the caption is a rectangle as wide as the figure" $ do
      ps <- outline False WrapStart (100, 100) (along, across) "M 0 0 L 10 0 L 10 10 L 0 10 Z"
      let ex = outlined WrapStart True ps
      takeAt ex 7 @?= 1030
  ]

circleSrc :: String
circleSrc = "M 100 50 C 100 77.6142 77.6142 100 50 100 C 22.3858 100 0 77.6142 0 50 C 0 22.3858 22.3858 0 50 0 C 77.6142 0 100 22.3858 100 50 Z"

-- the triangles on the grid of the image by 50, each as it is placed
triangles :: [String]
triangles =
  [ "M " <> pt a <> " L " <> pt b <> " L " <> pt c <> " Z"
  | a <- grid,
    b <- grid,
    c <- grid,
    a < b,
    a /= c,
    b /= c
  ]
  where
    grid = [(x, y) | x <- [0, 50, 100 :: Int], y <- [0, 50, 100 :: Int]]
    pt (x, y) = show x <> " " <> show y

-- the band starts, on the grid and off it, above the figure and below it
bandStarts :: [Sp]
bandStarts = map Sp [-130, -97 .. 820]

enumerated :: [TestTree]
enumerated =
  [ testCase "root ADR 0464 I2: no point of the area in the widened band of a line is closer to the text than the gap" $
      check $ \ex polys captioned s t ->
        let b0 = rat (s - gap)
            b1 = rat (s + face + gap)
            bs = [b0, b0 + (b1 - b0) / 8 .. b1]
            as = [0, rat along / 25 .. rat along]
            inArea (a, b) =
              (0 <= b && b <= rat across && insidePolygons NonZero polys (a, b))
                || (captioned && 700 <= b && b <= 780)
         in [(a, b) | b <- bs, a <- as, inArea (a, b), a > rat (t - gap)] == [] && exWidth ex >= 0,
    testCase "root ADR 0464 I3: no line beside an outline loses more than beside the rectangle" $
      check $
        \ex _ _ _ t -> t <= exWidth ex,
    testCase "root ADR 0464 I4: the text of a line starts the gap and less than 1 sp more from the edge" $
      check $ \ex _ _ s t -> case exEdge ex (rat (s - gap)) (rat (s + face + gap)) of
        Nothing -> t == 0
        Just e -> rat (t - gap) >= e && rat (t - gap) < e + 1
  ]
  where
    check p = do
      cases <-
        sequence
          [ (\ps -> (ps, side, vertical, captioned)) <$> outline vertical side (100, 100) (along, across) src
          | src <- triangles,
            side <- [WrapStart, WrapEnd],
            vertical <- [False, True],
            captioned <- [False, True]
          ]
      let wrong =
            [ (polys, side, vertical, captioned, s, t)
            | (polys, side, vertical, captioned) <- cases,
              let ex = outlined side captioned polys,
              s <- bandStarts,
              let t = lineTake ex s face,
              not (p ex polys captioned s t)
            ]
      take 1 wrong @?= []
