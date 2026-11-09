{- | Soft hyphens (U+00AD) in the composition (docs/adr ADR 0272): taken out
of the text, a break at those between two letters of an element, no
patterns in an element with one, and why each other one is not a break.
-}
module SoftHyphenSpec (softHyphenTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (compose, fs, look0, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (LinkTarget (..), Look (..))
import Golem.Layout.Table (cellExtent)
import Test.Tasty
import Test.Tasty.HUnit

-- | The environment of US English words.
enUS :: ComposeEnv
enUS = (defaultComposeEnv fs) {cePatterns = const (Just englishUS)}

-- | The items as text: a box its text, a penalty its kind.
shape :: [Item] -> [String]
shape = concatMap one . dropEnd
  where
    one = \case
      Box _ c -> [T.unpack (bcText c)]
      Penalty w p h -> ["pen " <> show w <> " " <> show p <> " " <> show h]
      Glue {} -> ["glue"]
    -- the end of the paragraph
    dropEnd its = take (length its - 3) its

-- | The width of a hyphen in the default environment: half an em.
hyphenW :: Sp
hyphenW = Sp (unSp fs `div` 2)

-- | The penalty of a soft hyphen in the default environment.
softPen :: String
softPen = "pen " <> show hyphenW <> " 50 SoftHyphen 0"

-- | The notes of the soft hyphens of inlines, with the index of each in its text as where it is.
sites :: ComposeEnv -> [IR.Inline] -> [(Int, SoftHyphenNote)]
sites env inls = [(o, n) | (_, o, n) <- softHyphenSites env {ceSourceAt = \_ _ i -> i} inls]

text :: Text -> IR.Inline
text = IR.Text sp

softHyphenTests :: TestTree
softHyphenTests =
  testGroup
    "soft hyphens (docs/adr ADR 0272)"
    [ testCase "I1 I2 I3: in\xAD\&com\xADpre\xADhen\xADsi\xAD\&bil\xADity breaks at its soft hyphens and nowhere else" $
        shape (compose enUS "in\xAD\&com\xADpre\xADhen\xADsi\xAD\&bil\xADity")
          @?= concat (zipWith (\i t -> [softPen | i > (0 :: Int)] <> [t]) [0 ..] ["in", "com", "pre", "hen", "si", "bil", "ity"]),
      testCase "I1: と\xADいう is composed as という" $
        compose enUS "と\xADいう" @?= compose enUS "という",
      testCase "I1: a soft hyphen alone makes no item" $
        compose enUS "\xAD" @?= compose enUS "",
      testCase "two soft hyphens in a row are one break" $
        shape (compose enUS "ta\xAD\xAD\&ble") @?= ["ta", softPen, "ble"],
      testCase "I4: a soft hyphen at the head of a word keeps it whole, the patterns among it" $ do
        shape (compose enUS "\xADhyphenation") @?= ["hyphenation"]
        shape (compose enUS "“\xADhyphenation”") @?= ["“hyphenation”"]
        sites enUS [text "\xADhyphenation"] @?= []
        sites enUS [text "“\xADhyphenation”"] @?= [],
      testCase "I4: one soft hyphen in a long word: the word breaks there only" $
        shape (compose enUS "hyphen\xAD\&ation") @?= ["hyphen", softPen, "ation"],
      testCase "a soft hyphen breaks without the two and three letters of the patterns" $
        shape (compose enUS "a\xAD\&ble") @?= ["a", softPen, "ble"],
      testCase "co-op\xAD\&er\xAD\&ate breaks after co- and at its soft hyphens" $
        shape (compose enUS "co-op\xAD\&er\xAD\&ate") @?= ["co-", "pen 0 50 ExplicitHyphen", "op", softPen, "er", softPen, "ate"],
      testCase "the element of a written hyphen without a soft hyphen is still hyphenated by the patterns" $
        shape (compose enUS "hyphenation-ta\xAD\&ble") @?= ["hy", "pen " <> show hyphenW <> " 50 PatternHyphen 0", "phen", "pen " <> show hyphenW <> " 50 PatternHyphen 0", "ation-", "pen 0 50 ExplicitHyphen", "ta", softPen, "ble"],
      testCase "explicit-hyphen-penalty 10000: the word is kept whole at its hyphens, but breaks at its soft hyphens" $
        shape (compose enUS {ceExplicitHyphenPenalty = 10000} "co-op\xAD\&er\xAD\&ate") @?= ["co-op", softPen, "er", softPen, "ate"],
      testCase "a word of a link breaks at none of its soft hyphens" $
        shape (fst (composeInlines enUS {ceRestyle = \lk -> \case { IR.Link _ u _ -> lk {lkLink = Just (LinkUri u)}; _ -> lk }} [IR.Link sp "https://example.com" [text "ta\xAD\&ble"]])) @?= ["table"],
      testCase "the boxes are where their characters are in the text with its soft hyphens (docs/adr ADR 0195)" $ do
        let its = fst (composeInlines enUS {ceSourceAt = \_ _ i -> i} [text "in\xAD\&com\xADpre"])
        [(bcText c, bcAt c) | Box _ c <- its] @?= [("in", 0), ("com", 3), ("pre", 7)],
      testCase "the soft hyphen breaks of a cell count as breaks, with the width of a hyphen (docs/adr ADR 0272)" $ do
        let its = compose enUS "in\xAD\&com\xADprehen"
            box t = sum [w | Box w _ <- compose (defaultComposeEnv fs) t]
        fst (cellExtent its) @?= box "prehen",
      testCase "G07123: a soft hyphen without a letter on either side, at a word's end, between Japanese characters" $ do
        sites enUS [text "a\xAD."] @?= [(1, ShyNotBetweenLetters)]
        sites enUS [text "table\xAD next"] @?= [(5, ShyNotBetweenLetters)]
        sites enUS [text "と\xADいう"] @?= [(1, ShyNotBetweenLetters)]
        sites enUS [text "co\xAD-op"] @?= [(2, ShyNotBetweenLetters)]
        sites enUS [text "co-\xADop"] @?= [],
      testCase "G07123: each soft hyphen of a text, in its order" $
        sites enUS [text "a\xAD.b\xAD\xAD"] @?= [(1, ShyNotBetweenLetters), (4, ShyNotBetweenLetters), (5, ShyNotBetweenLetters)],
      testCase "G07124: a soft hyphen in code, a URL, a link and a range that does not break" $ do
        let lookOf f = enUS {ceLook = f look0}
        sites (lookOf (\l -> l {lkCode = True})) [text "ta\xAD\&ble"] @?= [(2, ShyInUnbreakable)]
        sites (lookOf (\l -> l {lkUrl = True})) [text "ta\xAD\&ble"] @?= [(2, ShyInUnbreakable)]
        sites (lookOf (\l -> l {lkLink = Just (LinkUri "https://example.com")})) [text "ta\xAD\&ble"] @?= [(2, ShyInUnbreakable)]
        sites (lookOf (\l -> l {lkNoBreak = True})) [text "ta\xAD\&ble"] @?= [(2, ShyInUnbreakable)]
        sites (lookOf (\l -> l {lkNoBreak = True})) [text "\xADtable"] @?= [],
      testCase "a soft hyphen that is a break is not reported" $
        sites enUS [text "ta\xAD\&ble"] @?= [],
      testCase "the soft hyphens of the body of a note are reported" $
        sites enUS [text "a", IR.Note sp 1 (IR.noteBody sp [text "b\xAD."])] @?= [(1, ShyNotBetweenLetters)]
    ]
