-- | The paths of @style.toml@ and the unit of their coordinates (root ADR 0437).
module PathDataSpec (pathDataTests) where

import Control.Monad (void)
import Golem.Length (Sp (..), Unit (..))
import Golem.Project.PathData
import Test.Tasty
import Test.Tasty.HUnit

pathDataTests :: TestTree
pathDataTests =
  testGroup
    "the paths of style.toml (root ADR 0437)"
    [ testCase "the unit is mm by default, or mm, pt or Q" $ do
        pathUnit Nothing @?= Right Mm
        pathUnit (Just "mm") @?= Right Mm
        pathUnit (Just "pt") @?= Right Pt
        pathUnit (Just "Q") @?= Right Q,
      testCase "any other unit is not read" $ do
        pathUnit (Just "in") @?= Left (PathUnitError "in")
        pathUnit (Just "zw") @?= Left (PathUnitError "zw")
        pathUnit (Just "q") @?= Left (PathUnitError "q"),
      testCase "the coordinates are of the unit, each made sp once from its decimal" $ do
        readStylePath Pt "M 0 0 L 1.5 0 L 1.5 2 Z" @?= Right (Path [SubPath (0, 0) [LineTo (98304, 0), LineTo (98304, 131072)] True])
        -- 1Q = 0.25mm, 25.4mm = 72pt: 4Q is 1mm, 185771.33...sp, rounded once
        readStylePath Q "M 4 0 L 0 0" @?= readStylePath Mm "M 1 0 L 0 0"
        readStylePath Mm "M 1 0 L 0 0" @?= Right (Path [SubPath (Sp 185771, 0) [LineTo (0, 0)] False]),
      testCase "path data that cannot be read is an error at its offset" $
        void (readStylePath Mm "M 0 0 Q 1 1") @?= Left (PathDataError 6 "知らないコマンド Q")
    ]
