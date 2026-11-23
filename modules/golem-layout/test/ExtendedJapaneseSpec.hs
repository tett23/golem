module ExtendedJapaneseSpec (extendedJapaneseTests) where

import Control.Monad (forM_)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.Layout.Warichu (splitWarichu)
import Golem.Unicode.Grapheme (graphemeClusters)
import Test.Tasty
import Test.Tasty.HUnit

extendedJapaneseTests :: TestTree
extendedJapaneseTests =
  testGroup
    "root ADR 0380 extended Japanese composition"
    [ testCase "root ADR 0380 I1: inv1_extended_japanese_composition_property: every split preserves the grapheme sequence and minimises the wider line" $ do
        forM_ [T.replicate n "漢a" <> "e\x301👨\x200d👩\x200d👧\x200d👦" | n <- [0 .. 24]] $ \text -> do
          let units = graphemeClusters text
              measure = sum . map (\u -> if u == "a" then 3 else 7) . graphemeClusters
              (a, b) = splitWarichu measure text
              candidates = [let (x, y) = splitAt i units in (T.concat x, T.concat y) | i <- [0 .. length units]]
              costs = [max (measure x) (measure y) | (x, y) <- candidates]
          graphemeClusters a <> graphemeClusters b @?= units
          max (measure a) (measure b) @?= minimum costs
          [(a, b)] @?= take 1 [p | (p, c) <- zip candidates costs, c == minimum costs],
      testCase "root ADR 0380 I1: inv1_extended_japanese_composition_case_1: one grapheme leaves the first line empty on a tie" $
        splitWarichu (fromIntegral . length . graphemeClusters) "e\x301" @?= ("", "e\x301"),
      testCase "root ADR 0380 I1: an empty cutting note stays empty" $
        splitWarichu (const 0) "" @?= ("", ""),
      testCase "root ADR 0380 I1: inv1_extended_japanese_composition_case_2: upright AB makes two unrotated full-size boxes" $ do
        let env = (defaultComposeEnv fs) {ceVertical = True}
            items = fst (composeInlines env [Upright sp "AB"])
        [(w, boxKind c, bcText c) | Box w c <- items] @?= [(fs, KindUpright, "A"), (fs, KindUpright, "B")],
      testCase "root ADR 0380 I1: warichu is one half-size two-line inline box" $ do
        let env = defaultComposeEnv fs
            boxes = [(w, bcWarichu c) | Box w c <- fst (composeInlines env [Warichu sp "漢字仮名"])]
        boxes @?= [(fs, Just ("漢字", "仮名"))],
      testCase "root ADR 0380 I1: character advance changes the cells without changing glyph size" $ do
        let env = (defaultComposeEnv fs) {ceCellRatio = 4 / 5}
            boxes = [(w, lkSize (bcLook c), bcEdgeEnd c) | Box w c <- fst (composeInlines env [Text sp "漢字"])]
        boxes @?= replicate 2 (Sp (unSp fs * 4 `div` 5), fs, Sp (unSp fs `div` 5))
    ]
