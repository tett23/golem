{- | The padding of inline code on its first and last pieces that are not
spaces (golem-layout ADR 0048, D1 to D5): a space at an end of code stays
glue outside the padding, and the padding goes on the character next to it.
-}
module CodePaddingSpec (codePaddingTests) where

import Control.Monad (forM_)
import Data.Text (Text)
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | The default padding of the character style code, 0.25zw.
quarter :: Sp
quarter = Sp (unSp fs `div` 4)

-- | 0.5zw, more than the default.
half :: Sp
half = Sp (unSp fs `div` 2)

-- | The environment with the character style code of the padding given and a background.
envWith :: Sp -> ComposeEnv
envWith p = (defaultComposeEnv fs) {ceRestyle = \lk -> \case IR.CharStyle _ "code" _ -> lk {lkCode = True, lkBackground = Just "bg", lkPadding = p}; _ -> lk}

env :: ComposeEnv
env = envWith quarter

code :: Text -> IR.Inline
code t = IR.CharStyle sp "code" [IR.Text sp t]

txt :: Text -> IR.Inline
txt = IR.Text sp

itemsIn :: ComposeEnv -> [IR.Inline] -> [Item]
itemsIn e = fst . composeInlines e

-- | The boxes: their text, the padding before and after them.
pads :: ComposeEnv -> [IR.Inline] -> [(Text, Sp, Sp)]
pads e is = [(bcText c, bcPadStart c, bcPadEnd c) | Box _ c <- itemsIn e is]

-- | The boxes: their text and width.
widths :: ComposeEnv -> [IR.Inline] -> [(Text, Sp)]
widths e is = [(bcText c, w) | Box w c <- itemsIn e is]

-- | The items but the boxes: the glue and the penalties.
between :: ComposeEnv -> [IR.Inline] -> [Item]
between e is =
  [ x
  | x <- itemsIn e is,
    case x of
      Box {} -> False
      _ -> True
  ]

-- | The inputs of D1 and D2: spaces at the start, at the end, at both ends, two of them, in the middle and at the end of a paragraph, before a forced break.
edgeInputs :: [[IR.Inline]]
edgeInputs =
  [ [txt "あ", code " 漢", txt "い"],
    [txt "あ", code "  漢", txt "い"],
    [txt "あ", code "漢 ", txt "い"],
    [txt "あ", code " 漢 ", txt "い"],
    [txt "あ", code "漢 "],
    [txt "あ", code "漢 ", IR.LineBreak sp, txt "い"],
    [code " 漢", txt "い"],
    [txt "あ", code " a ", txt "い"],
    [txt "あ", code " a b ", txt "い"]
  ]

codePaddingTests :: TestTree
codePaddingTests =
  testGroup
    "the padding of inline code on its first and last pieces that are not spaces (golem-layout ADR 0048)"
    [ testCase "D1: the padding before the Japanese character after a space at the start of code" $ do
        pads env [txt "あ", code " 漢", txt "い"] @?= [("あ", 0, 0), ("漢", quarter, quarter), ("い", 0, 0)]
        widths env [txt "あ", code " 漢", txt "い"] @?= [("あ", fs), ("漢", fs + 2 * quarter), ("い", fs)],
      testCase "D1: two spaces at the start, and code at the start of the paragraph" $ do
        pads env [txt "あ", code "  漢", txt "い"] @?= [("あ", 0, 0), ("漢", quarter, quarter), ("い", 0, 0)]
        pads env [code " 漢", txt "い"] @?= [("漢", quarter, quarter), ("い", 0, 0)],
      testCase "D1, D2: Latin text, and two words, with spaces at both ends" $ do
        pads env [txt "あ", code " a ", txt "い"] @?= [("あ", 0, 0), ("a", quarter, quarter), ("い", 0, 0)]
        pads env [txt "あ", code " a b ", txt "い"] @?= [("あ", 0, 0), ("a", quarter, 0), ("b", 0, quarter), ("い", 0, 0)],
      testCase "D2: the padding after the Japanese character before a space at the end of code" $
        pads env [txt "あ", code "漢 ", txt "い"] @?= [("あ", 0, 0), ("漢", quarter, quarter), ("い", 0, 0)],
      testCase "D2: at the end of the paragraph and before a forced break" $ do
        pads env [txt "あ", code "漢 "] @?= [("あ", 0, 0), ("漢", quarter, quarter)]
        pads env [txt "あ", code "漢 ", IR.LineBreak sp, txt "い"] @?= [("あ", 0, 0), ("漢", quarter, quarter), ("い", 0, 0)],
      testCase "D1, D2: the padding of 0.5zw, and of 0" $ do
        pads (envWith half) [txt "あ", code " 漢 ", txt "い"] @?= [("あ", 0, 0), ("漢", half, half), ("い", 0, 0)]
        pads (envWith 0) [txt "あ", code " 漢 ", txt "い"] @?= [("あ", 0, 0), ("漢", 0, 0), ("い", 0, 0)],
      testCase "D1, D2: in vertical text" $
        pads env {ceVertical = True} [txt "あ", code " 漢 ", txt "い"] @?= [("あ", 0, 0), ("漢", quarter, quarter), ("い", 0, 0)],
      testCase "D1, D2: the mark of a note between spaces of code takes both paddings" $ do
        let marked = [txt "あ", IR.CharStyle sp "code" [txt " ", IR.Note sp 1 (IR.noteBody sp [txt "n"]), txt " "], txt "い"]
        [(bcPadStart c, bcPadEnd c) | Box _ c <- itemsIn env marked, boxKind c == KindNoteMark] @?= [(quarter, quarter)],
      testCase "D1, D2: ruby after a space of code takes no padding, nor does anything else" $ do
        let ruby = IR.Ruby sp () [IR.RubySegment [IR.Text sp "漢"] (Just "かん")]
        [(bcPadStart c, bcPadEnd c) | Box _ c <- itemsIn env [txt "あ", IR.CharStyle sp "code" [txt " ", ruby, txt " "], txt "い"], bcPadStart c /= 0 || bcPadEnd c /= 0] @?= [],
      testCase "D3: code of spaces only has no padding" $ do
        pads env [txt "あ", code " ", txt "い"] @?= [("あ", 0, 0), ("い", 0, 0)]
        pads env [txt "あ", code "  ", txt "い"] @?= [("あ", 0, 0), ("い", 0, 0)],
      testCase "D4: code without a space at its ends is composed as before golem-layout ADR 0048" $ do
        pads env [code "a b"] @?= [("a", quarter, 0), ("b", 0, quarter)]
        widths env [code "a b"] @?= [("a", 491520), ("b", 491520)]
        pads env [code "漢"] @?= [("漢", quarter, quarter)]
        widths env [code "漢"] @?= [("漢", fs + 2 * quarter)]
        pads env [code "a/b"] @?= [("a/", quarter, 0), ("b", 0, quarter)]
        widths env [code "a/b"] @?= [("a/", 819200), ("b", 491520)]
        forM_ [[code "a b"], [code "漢"], [code "a/b"]] $ \is -> between env is @?= between (envWith 0) is,
      testCase "D5: the glue of the spaces at the ends and the penalties before it are as before golem-layout ADR 0048" $
        forM_ edgeInputs $
          \is -> between env is @?= between (envWith 0) is
    ]
