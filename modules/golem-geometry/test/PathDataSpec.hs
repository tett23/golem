-- | Reading the path data of SVG: M, L, C and Z with absolute coordinates (root ADR 0437).
module PathDataSpec (tests) where

import Data.Text (Text)
import Golem.Geometry
import Golem.Length (Sp (..), Unit (..), toSp)
import Test.Tasty
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "path data"
    [ testCase "M, L and Z make a closed subpath" $
        parse "M 0 0 L 10 0 L 10 10 Z" @?= Right (Path [SubPath (0, 0) [LineTo (10, 0), LineTo (10, 10)] True]),
      testCase "the numbers of M after the first point are lines, and commas separate numbers" $
        parse "M0,0 10,0 10,10" @?= Right (Path [SubPath (0, 0) [LineTo (10, 0), LineTo (10, 10)] False]),
      testCase "C takes three points, repeated" $
        parse "M 0 0 C 1 2 3 4 5 6 7 8 9 10 11 12" @?= Right (Path [SubPath (0, 0) [CurveTo (1, 2) (3, 4) (5, 6), CurveTo (7, 8) (9, 10) (11, 12)] False]),
      testCase "a second M starts a second subpath" $
        parse "M 0 0 L 1 0 Z M 5 5 L 6 5" @?= Right (Path [SubPath (0, 0) [LineTo (1, 0)] True, SubPath (5, 5) [LineTo (6, 5)] False]),
      testCase "a line after Z starts at the start of the closed subpath" $
        parse "M 1 1 L 2 1 Z L 3 3" @?= Right (Path [SubPath (1, 1) [LineTo (2, 1)] True, SubPath (1, 1) [LineTo (3, 3)] False]),
      testCase "empty data is the empty path" $
        parse " " @?= Right (Path []),
      testCase "decimals and signs are exact and converted once" $
        parsePathData (toSp Mm) "M 0.5 -1.25 L +2 .5" @?= Right (Path [SubPath (toSp Mm 0.5, toSp Mm (-1.25)) [LineTo (toSp Mm 2, toSp Mm 0.5)] False]),
      testCase "relative commands are not read" $
        errorAt "M 0 0 l 1 1" @?= Left 6,
      testCase "the data starts with M" $
        errorAt "L 1 1" @?= Left 0,
      testCase "a command takes whole points" $
        errorAt "M 0 0 L 1" @?= Left 6,
      testCase "a number needs a command before it" $
        errorAt "1 2" @?= Left 0,
      testCase "a sign alone is not a number" $
        errorAt "M - 1" @?= Left 2
    ]

parse :: Text -> Either PathDataError Path
parse = parsePathData (Sp . round)

-- | The offset of the error of the data, or the path read.
errorAt :: Text -> Either Int Path
errorAt = either (Left . pdeOffset) Right . parse
