{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The outside of tate-chu-yoko is one ideograph (root ADR 0479).
module TcyBoundarySpec (tcyBoundaryTests) where

import Control.Monad (forM_, replicateM)
import Data.Text (Text)
import Fixtures (fs, sp, sp0)
import Golem.Doc.IR
import Golem.Layout.Aki qualified as A
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit

-- Kept at one site so the IR migration can change the payload independently.
literal :: Text -> Inline
literal = Tcy sp

number :: Integer -> Inline
number n = Number sp n (Just StyleTcy)

-- Only dimensions and break decisions are compared, not glyph identity or source sites.
trace :: ComposeEnv -> [Inline] -> [(String, String)]
trace config = map view . fst . composeInlines config
  where
    view = \case
      Box w c -> ("box", show (w, bcEdgeStart c, bcEdgeEnd c))
      Glue w grow shrink kind zw -> ("glue", show (w, grow, shrink, kind, zw))
      Penalty w cost hyphen -> ("penalty", show (w, cost, hyphen))

env :: Bool -> ComposeEnv
env vertical = (defaultComposeEnv fs) {ceVertical = vertical}

han :: Inline
han = sp0 "漢"

tcyBoundaryTests :: TestTree
tcyBoundaryTests =
  testGroup "root ADR 0479 outer tate-chu-yoko boundaries" $
    [ testCase ("root ADR 0479 I1, I2: literal outside equals an ideograph, vertical=" <> show vertical) $
        forM_ ["1", "12", "123", "001", "ab", "!?", "（", "）", "。", "ー", "一", "%", ""] $ \inside ->
          forM_ [("あ", "い"), ("a", "b"), ("（", "）"), ("「", "。」"), ("1", "月"), ("第", "1"), ("", "月"), ("あ", "")] $ \(before, after) -> do
            let surround middle = [sp0 before, middle, sp0 after]
            assertEqual (show (inside, before, after)) (trace (env vertical) (surround han)) (trace (env vertical) (surround (literal inside)))
    | vertical <- [False, True]
    ]
      <> [ testCase "root ADR 0479 I1, I2: explicit numeric tcy has ideograph boundaries" $
             forM_ [-123, -1, 0, 1, 12, 123] $ \n ->
               forM_ [("あ", "い"), ("a", "b"), ("1", "月"), ("（", "）")] $ \(before, after) -> do
                 let surround middle = [sp0 before, middle, sp0 after]
                 trace (env True) (surround (number n)) @?= trace (env True) (surround han),
           testCase "root ADR 0479 I2: only outside digits participate in the configured number-unit penalty" $ do
             let e = (env True) {ceNumberUnitPenalty = 42}
             forM_ [("1", "%", "月"), ("第", "1", "月"), ("$", "12", ""), ("あ", "1", "月")] $ \(before, inside, after) -> do
               trace e [sp0 before, literal inside, sp0 after] @?= trace e [sp0 before, han, sp0 after],
           testCase "root ADR 0479 I1, I2: automatically selected numeric tcy has ideograph boundaries" $
             forM_ [VerticalFixed StyleTcy, VerticalAuto StyleKanji] $ \notation ->
               forM_ [0, 1, 12, 99] $ \n -> do
                 let e = (env True) {ceVerticalNumbers = notation}
                 trace e [sp0 "あ", Number sp n Nothing, sp0 "月"] @?= trace e [sp0 "あ", han, sp0 "月"],
           testCase "root ADR 0479 I2, I5: links and a larger character style keep ideograph boundaries" $
             forM_ [False, True] $ \vertical -> do
               let e = (env vertical) {ceRestyle = \lk i -> case i of CharStyle {} -> lk {lkSize = 2 * fs}; _ -> lk}
                   linked middle = [sp0 "あ", Link sp "https://example.com/" [middle], sp0 "い"]
                   styled middle = [sp0 "（", CharStyle sp "large" [middle], sp0 "）"]
               trace e (linked (literal "!?")) @?= trace e (linked han)
               trace e (styled (literal "001")) @?= trace e (styled han),
           testCase "root ADR 0479 I1, I2: one to three adjacent literal boxes have ideograph boundaries" $
             forM_ [False, True] $ \vertical ->
               forM_ [1 .. 3] $ \count ->
                 forM_ (replicateM count ["12", "ab", "!?", "）"]) $ \contents ->
                   trace (env vertical) (map literal contents) @?= trace (env vertical) (replicate count han),
           testCase "root ADR 0479 I2, I5: custom ideograph aki applies outside tcy" $ do
             let custom = A.withAkiRule [A.AkiChar Ideograph] [A.AkiChar Ideograph] (A.Aki (1 / 8) (1 / 3) (1 / 2)) A.defaultAkiSet
                 e = (env True) {ceAkiSet = custom}
             trace e [sp0 "あ", literal "12", sp0 "い"] @?= trace e [sp0 "あ", han, sp0 "い"],
           testCase "root ADR 0479 I5: explicit aki is kept next to tcy" $
             forM_ [False, True] $ \vertical -> do
               let surround middle = [sp0 "あ", Aki sp (AkiAbs 12345), middle, Aki sp (AkiZw (1 / 5)), sp0 "い"]
               trace (env vertical) (surround (literal "12")) @?= trace (env vertical) (surround han),
           testCase "root ADR 0479 I5: positive and negative tracking is once per outer box and returned at line end" $
             forM_ [False, True] $ \vertical ->
               forM_ [-100, 0, 100] $ \tracking -> do
                 let e = (env vertical) {ceLook = (ceLook (env vertical)) {lkTracking = tracking}}
                 trace e [sp0 "あ", literal "12", sp0 "い"] @?= trace e [sp0 "あ", han, sp0 "い"]
                 trace e [literal "12"] @?= trace e [han],
           testCase "root ADR 0479 I5: horizontal numeric tcy keeps its ordinary three-digit width" $ do
             let boxes xs = [(w, boxKind c, bcText c) | Box w c <- fst (composeInlines (env False) xs)]
             boxes [number 123] @?= boxes [sp0 "123"]
             trace (env False) [sp0 "あ", number 123, sp0 "い"] @?= trace (env False) [sp0 "あ", sp0 "123", sp0 "い"]
             [w | (w, _, _) <- boxes [literal "123"]] @?= [fs]
             assertBool "literal/numeric horizontal widths differ" (map (\(w, _, _) -> w) (boxes [number 123]) /= [fs])
         ]
