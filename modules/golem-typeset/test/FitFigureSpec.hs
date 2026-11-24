{- | The size of a figure fitted to the column (golem-driver ADR 0034) as
the pagination sees it (root ADR 0440): a figure that is 0 sp across the
lines after fitting is so before fitting, the error G07135, or has a
column that leaves no line for it, the errors G07038 and G07131.
-}
module FitFigureSpec (fitFigureTests) where

import Control.Monad (forM_)
import Golem.Project.Style (Sp (..))
import Golem.Typeset (fitFigure)
import Test.Tasty
import Test.Tasty.HUnit

fitFigureTests :: [TestTree]
fitFigureTests =
  [ testCase "root ADR 0440 I1: fitting makes a figure 0 sp across only when it is so before fitting or the column leaves it no line" $
      forM_ cases $ \(ratio, along, l, s) -> do
        let (_, across, _) = fitFigure ratio along l pitch fs s
            before = floor (fromInteger (unSp along) * ratio) :: Integer
            noLine = case s of
              Just k -> k >= l
              Nothing -> fromIntegral (l - 1) * pitch + fs <= 0
        assertBool (show (ratio, along, l, s, across)) (across > 0 || before == 0 || noLine),
    testCase "root ADR 0440 I1: a figure 1 sp across before fitting stays 1 sp across in a column with room" $ do
      let (_, across, fitted) = fitFigure 1 1 10 pitch fs Nothing
      (across, fitted) @?= (1, False)
  ]
  where
    pitch = 15 * 65536
    fs = 10 * 65536
    cases =
      [ (ratio, Sp along, l, s)
      | ratio <- [1 / 1000, 1 / 2, 1, 2, 1000],
        along <- [0, 1, 2, 3, 65536, 240 * 65536],
        l <- [0 .. 3],
        s <- Nothing : map Just [1 .. 3]
      ]
