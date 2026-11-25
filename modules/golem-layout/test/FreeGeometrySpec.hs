module FreeGeometrySpec (freeGeometryTests) where

import Control.Monad (forM_)
import Golem.Layout.FreeGeometry
import Golem.Layout.RuleArea (RuleSide (..))
import Golem.Length (Sp (..))
import Test.Tasty
import Test.Tasty.HUnit

freeGeometryTests :: TestTree
freeGeometryTests =
  testGroup
    "free placement geometry"
    [ testCase "root ADR 0397 I3: odd pitches retain integer centers" $ do
        centerDistance 5 4 3 @?= 8
        centerDistance 4 5 3 @?= 7
        centerDistance 18 16 6 @?= 23,
      testCase "root ADR 0397 I8: column extent keeps existing type area" $ do
        columnExtent 20 16 10 @?= 314
        columnExtent 1 16 10 @?= 10,
      testCase "root ADR 0397 I10: touching exclusion edges do not overlap" $ do
        intersects (0, 10) (10, 20) @?= False
        intersects (0, 11) (10, 20) @?= True
        intersects (0, 10) (5, 5) @?= False
        rowExtent 0 4 8 @?= (-2, 6),
      testCase "root ADR 0397 I11: padding has exact face clearance without double counting" $
        forM_ [(Sp p, Sp h, Sp d) | p <- [1 .. 9], h <- [1 .. 9], d <- [0 .. 9]] $ \(p, h, d) -> do
          let (before, afterExtra) = boxExtras p h p h d
              a = faceOffset p h
              b = p - h - a
          assertBool "before clearance" (before + a >= d)
          assertBool "after clearance" (afterExtra + b >= d)
          assertBool "minimal before" (before == 0 || before - 1 + a < d)
          assertBool "minimal after" (afterExtra == 0 || afterExtra - 1 + b < d),
      testCase "root ADR 0397 I11: rule additions account for existing line leading" $ do
        ruleBeforeExtra 18 10 2 1 0 @?= 0
        ruleBeforeExtra 18 10 2 1 3 @?= 2
        ruleAfterExtra 18 10 2 1 @?= 0
        ruleBetweenExtra 4 2 1 2 1 @?= 2,
      testCase "root ADR 0397 I11: an unspecified rule leaves the odd sp outside" $ do
        let side = RuleSide 0 0 1 False Nothing
        ruleBeforeGap 8 side 0 @?= (0, 4)
        ruleAfterGap 8 side 0 @?= (0, 3)
        ruleBeforeEdge 18 10 side 0 @?= (0, 2)
        ruleAfterEdge 18 10 18 side @?= (0, 15),
      testCase "root ADR 0397 I11: negative face gaps receive only the required extra length" $ do
        let side = RuleSide 2 3 1 True Nothing
        ruleBeforeGap (-4) side 1 @?= (11, 3)
        ruleAfterGap (-4) side 1 @?= (11, 2),
      testCase "root ADR 0397 I11: two unspecified rules put indivisible sp between them" $ do
        let side = RuleSide 0 0 1 False Nothing
        rulesSharedGap 10 side side 0 @?= (0, 2, 7),
      testCase "root ADR 0397 I11: shared rules preserve both inner distances" $ do
        let a = RuleSide 2 3 1 True Nothing
            b = RuleSide 4 5 2 True Nothing
        rulesSharedGap 8 a b 1 @?= (7, 2, 8),
      testCase "root ADR 0397 I11: edge rules reserve exact missing leading" $ do
        let side = RuleSide 2 99 1 True Nothing
        ruleBeforeEdge 4 10 side 1 @?= (7, 0)
        ruleAfterEdge 4 10 4 side @?= (6, 9),
      testCase "root ADR 0397 I11: permitted outside rules use no body space" $ do
        let before = RuleSide 2 99 1 True (Just 7)
            afterSide = RuleSide 2 99 1 True (Just 6)
        ruleBeforeEdge 4 10 before 1 @?= (0, -7)
        ruleAfterEdge 4 10 4 afterSide @?= (0, 9)
    ]
