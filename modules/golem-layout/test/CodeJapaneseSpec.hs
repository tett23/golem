{- | Line breaks between Japanese characters in inline code, and between
Japanese and Latin characters there, with the wrap mark at the end of a
line broken at such a break (golem-layout ADR 0034, C1 to C8).
-}
module CodeJapaneseSpec (codeJapaneseTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, look0, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | The wrap mark of the tests: the default of the character style code.
mark :: Text
mark = "⏎"

-- | The environment with the character style code of the wrap mark given.
envWith :: Text -> ComposeEnv
envWith m = (defaultComposeEnv fs) {ceRestyle = \lk -> \case IR.CharStyle _ "code" _ -> lk {lkCode = True, lkWrapMark = m}; _ -> lk}

env :: ComposeEnv
env = envWith mark

code :: Text -> IR.Inline
code t = IR.CharStyle sp "code" [IR.Text sp t]

-- | The items of the inlines, without the paragraph end.
itemsIn :: ComposeEnv -> [IR.Inline] -> [Item]
itemsIn e is = let its = fst (composeInlines e is) in take (length its - 3) its

{- | The items as text: a box its characters, a break of code with the
wrap mark |p, a break without it |p- (its width 0), a prohibition |X,
glue _.
-}
shape :: Item -> String
shape = \case
  Box _ c -> T.unpack (bcText c)
  Glue {} -> "_"
  Penalty w p h
    | p >= infPenalty -> "|X"
    | WrapMark m <- h, m == mark, w == markWidth -> "|" <> show p
    | NoHyphen <- h, w == 0 -> "|" <> show p <> "-"
    | otherwise -> "|?" <> show (w, p, h)

-- | The width of the mark: an em, as the default advance of a character not Latin.
markWidth :: Sp
markWidth = fs

shapesIn :: ComposeEnv -> Text -> [String]
shapesIn e t = map shape (itemsIn e [code t])

shapes :: Text -> [String]
shapes = shapesIn env

loose :: ComposeEnv
loose = env {ceKinsokuStrict = False}

-- | Code in a language span.
inLang :: Text -> Text -> [String]
inLang l t = map shape (itemsIn env [IR.Lang sp l [code t]])

-- | The lines of the inlines in lines of n em.
linesIn :: ComposeEnv -> Int -> [IR.Inline] -> [Line]
linesIn e n is = brLines (breakParagraph defaultParams (const (fromIntegral n * fs)) (fst (composeInlines e is)))

lineText :: Line -> Text
lineText l = T.concat [bcText c | Box _ c <- lineItems l]

-- | Whether a line ends with the wrap mark: its last item the penalty of the mark, as wide as it.
endsWithMark :: Line -> Bool
endsWithMark l = case reverse (lineItems l) of
  Penalty w _ (WrapMark m) : _ -> m == mark && w == markWidth
  _ -> False

codeJapaneseTests :: TestTree
codeJapaneseTests =
  testGroup
    "line breaks between Japanese characters in inline code (golem-layout ADR 0034)"
    [ testCase "C1: each Japanese character of code is a box, with a break of 0 between two" $
        shapes "罫線を持つ" @?= ["罫", "|0", "線", "|0", "を", "|0", "持", "|0", "つ"],
      testCase "C1: no break before a comma, after an opening bracket or before a closing one" $ do
        shapes "あ、い" @?= ["あ", "、", "|0", "い"]
        shapes "「あ」" @?= ["_", "「", "あ", "」"],
      testCase "C1: no break before a prolonged sound mark or a small kana in strict kinsoku, a break in loose kinsoku" $ do
        shapes "あーい" @?= ["あ", "ー", "|0", "い"]
        shapes "あぁい" @?= ["あ", "ぁ", "|0", "い"]
        shapesIn loose "あーい" @?= ["あ", "|0", "ー", "|0", "い"]
        shapesIn loose "あぁい" @?= ["あ", "|0", "ぁ", "|0", "い"],
      testCase "C1: no break between two ellipses" $
        shapes "……" @?= ["…", "…"],
      testCase "C1: a break at each border of Japanese and Latin characters, ASCII signs among them" $ do
        shapes "あa" @?= ["あ", "|0", "a"]
        shapes "aあ" @?= ["a", "|0", "あ"]
        shapes "あ1" @?= ["あ", "|0", "1"]
        shapes "え\"か\"" @?= ["え", "|0", "\"", "|0", "か", "|0", "\""]
        shapes "あ(い)" @?= ["あ", "|0", "(", "|0", "い", "|0", ")"]
        shapes "あ=い" @?= ["あ", "|0", "=", "|0", "い"],
      testCase "C1: no break at a border where the Japanese character prohibits it" $ do
        shapes "（a）" @?= ["_", "（", "a", "）"]
        shapes "a、" @?= ["a", "、"]
        shapes "a。" @?= ["a", "。"]
        shapes "aー" @?= ["a", "ー"]
        shapesIn loose "aー" @?= ["a", "|0", "ー"],
      testCase "C1: no break after a slash or a run of low lines before a full stop" $ do
        shapes "a/。" @?= ["a/", "。"]
        shapes "a_b_。" @?= ["a_", "|100", "b_", "。"],
      testCase "C1: a base character and its combining character are one box of code" $
        shapes "か\x3099き" @?= ["か\x3099", "|0", "き"],
      testCase "C1: in a Japanese span, a break between Japanese characters as without a span" $
        inLang "ja" "あい" @?= ["あ", "|0", "い"],
      testCase "C1: in a Latin span, no break after “ before a Japanese character: its Japanese class keeps it" $
        inLang "en" "“あ" @?= ["“", "あ"],
      testCase "C2: a break of 0 after a slash, of 100 after a run of low lines, one only, before a Japanese character" $ do
        shapes "a/あ" @?= ["a/", "|0", "あ"]
        shapes "a_b_あ" @?= ["a_", "|100", "b_", "|100", "あ"]
        shapes "a_あ" @?= ["a_", "|100", "あ"]
        shapes "_あ" @?= ["_", "|100", "あ"]
        shapes "あ_b" @?= ["あ", "|0", "_", "|100", "b"],
      testCase "C3: between Latin characters, breaks only after a slash and a run of low lines" $ do
        shapes "a b/c_d" @?= ["a", "_", "b/", "|0", "c_", "|100", "d"]
        shapes "THIRD_PARTY_LICENSES/" @?= ["THIRD_", "|100", "PARTY_", "|100", "LICENSES/"]
        shapes "abc\"def" @?= ["abc\"def"],
      testCase "C4: code without Japanese characters: the items of before, but the width and the mark of its breaks" $ do
        let plain t = itemsIn (envWith "") [code t]
            -- the items with the looks of their boxes without the mark, and the breaks of the mark as before
            unmarked = map (\case Penalty _ p (WrapMark _) -> Penalty 0 p NoHyphen; Box w c -> Box w c {bcLook = (bcLook c) {lkWrapMark = ""}}; it -> it)
        mapM_ (\t -> unmarked (itemsIn env [code t]) @?= plain t) ["a b/c_d", "THIRD_PARTY_LICENSES/", "abc\"def", "x = y"]
        map shape (plain "a b/c_d") @?= ["a", "_", "b/", "|0-", "c_", "|100-", "d"],
      testCase "C5: a URL with Japanese characters breaks as before" $ do
        let urlEnv = (defaultComposeEnv fs) {ceLook = look0 {lkUrl = True}}
            its = fst (composeInlines urlEnv [IR.Text sp "https://例え.jp/日本語"])
        [bcText c | Box _ c <- its] @?= ["https://", "例え", ".", "jp/", "日本語"]
        [(w, p, h) | Penalty w p h <- take (length its - 3) its] @?= [(0, 0, NoHyphen), (0, 100, NoHyphen), (0, 0, NoHyphen)],
      testCase "C6, C7: without the wrap mark, ten Japanese characters of code in lines of 4 em make lines of 4, 4 and 2, none overfull" $ do
        let ls = linesIn (envWith "") 4 [code "あいうえおかきくけこ"]
        map lineText ls @?= ["あいうえ", "おかきく", "けこ"]
        map lineOverflow ls @?= [0, 0, 0]
        T.concat (map lineText ls) @?= "あいうえおかきくけこ",
      testCase "C6: code broken at the borders of a string keeps every character, and draws no hyphen" $ do
        let ls = linesIn (envWith "") 4 [code "x = \"日本語の文字列\""]
            its = fst (composeInlines (envWith "") [code "x = \"日本語の文字列\""])
        assertBool (show (map lineText ls)) (length ls > 1)
        T.concat (map lineText ls) @?= "x=\"日本語の文字列\""
        [() | Penalty _ _ (PatternHyphen _) <- its] @?= []
        [() | Penalty _ _ ExplicitHyphen <- its] @?= [],
      testCase "C7: the box of a Japanese character of code is as wide as its advance and tracking; no glue between the boxes" $ do
        let tracked = (defaultComposeEnv fs) {ceRestyle = \lk -> \case IR.CharStyle _ "code" _ -> lk {lkCode = True, lkTracking = 50}; _ -> lk}
            its = itemsIn tracked [code "あいう"]
            t = Sp (unSp fs * 50 `div` 1000)
        [w | Box w _ <- its] @?= [fs + t, fs + t, fs + t]
        [() | Glue {} <- its] @?= [],
      testCase "C7: the padding is before the first box and after the last of the code only" $ do
        let padded = (defaultComposeEnv fs) {ceRestyle = \lk -> \case IR.CharStyle _ "code" _ -> lk {lkCode = True, lkPadding = 250}; _ -> lk}
            its = itemsIn padded [IR.Text sp "漢", code "あいa", IR.Text sp "漢"]
        [(bcText c, bcPadStart c, bcPadEnd c) | Box _ c <- its] @?= [("漢", 0, 0), ("あ", 250, 0), ("い", 0, 0), ("a", 0, 250), ("漢", 0, 0)],
      testCase "C7: in vertical text the Japanese boxes of code stand upright and the Latin ones are turned" $ do
        let its = itemsIn env {ceVertical = True} [code "あいab"]
        [(bcText c, boxKind c) | Box _ c <- its] @?= [("あ", KindText), ("い", KindText), ("ab", KindRotated)],
      testCase "C8: with the wrap mark, every line but the last of broken Japanese code ends with the mark, and fits" $ do
        let ls = linesIn env 4 [code "あいうえおかきくけこ"]
        -- the last line, without the mark, holds four
        map lineText ls @?= ["あいう", "えおか", "きくけこ"]
        map endsWithMark ls @?= [True, True, False]
        map lineOverflow ls @?= [0, 0, 0],
      testCase "C8: a line broken at a space of code has no mark" $ do
        let ls = linesIn env 2 [code "a b c d e"]
        assertBool (show (map lineText ls)) (length ls > 1)
        map endsWithMark ls @?= map (const False) ls,
      testCase "C8: an empty wrap mark draws no mark" $ do
        let its = fst (composeInlines (envWith "") [code "あいうえおかきくけこ"])
        [() | Penalty _ _ (WrapMark _) <- its] @?= []
    ]
