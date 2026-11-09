{- | Line breaks of inline code after the runs of hyphen-minus signs and
full stops between two Latin characters (golem-layout ADR 0045, J1 to J7):
a break of 100 there, with the wrap mark, but where the run is the first
or the last of the string between spaces, where a slash or a low line is
beside it, and between two digits.
-}
module CodeStopSpec (codeStopTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import LineBreakEnum (Setting (..), codeEnv)
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

-- | The width of the default mark: 3/5 of the size of the code, rounded down (golem-layout ADR 0042, W3).
markWidth :: Sp
markWidth = Sp ((unSp fs * 3) `div` 5)

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

shapesIn :: ComposeEnv -> Text -> [String]
shapesIn e t = map shape (itemsIn e [code t])

shapes :: Text -> [String]
shapes = shapesIn env

-- | The setting of the enumeration with strict kinsoku, no hanging, no protrusion and no language span.
plain :: Setting
plain = Setting True False False Nothing

{- | The lines of the inlines in lines of the width given, with the advances
of the enumeration (Latin letters 1/2 em, hyphen-minus signs and full stops
1/4 em, Japanese characters an em) and the wrap mark of 3/5 em.
-}
enumLines :: Sp -> [IR.Inline] -> Breaks
enumLines w is = breakParagraph defaultParams (const w) (fst (composeInlines (codeEnv False plain) is))

lineText :: Line -> Text
lineText l = T.concat [bcText c | Box _ c <- lineItems l]

-- | The mark a line ends with: the text of the penalty of the mark it breaks at.
endMarks :: Line -> [Text]
endMarks l = case reverse (lineItems l) of
  Penalty _ _ (WrapMark m) : _ -> [m]
  _ -> []

codeStopTests :: TestTree
codeStopTests =
  testGroup
    "line breaks of inline code after hyphen-minus signs and full stops (golem-layout ADR 0045)"
    [ testCase "J1: attest-build-provenance breaks after each hyphen-minus sign, with a break of 100" $
        shapes "attest-build-provenance" @?= ["attest-", "|100", "build-", "|100", "provenance"],
      testCase "J1: golem-*.tar.gz breaks after golem-, after *. and after tar." $
        shapes "golem-*.tar.gz" @?= ["golem-", "|100", "*.", "|100", "tar.", "|100", "gz"],
      testCase "J1: no break after the first run of the string nor after the last" $ do
        shapes "-n" @?= ["-n"]
        shapes "--target" @?= ["--target"]
        shapes ".wasm" @?= [".wasm"]
        shapes "foo." @?= ["foo."]
        shapes "a-" @?= ["a-"]
        shapes "-a-" @?= ["-a-"],
      testCase "J1: no break between two digits" $ do
        shapes "1.0.0" @?= ["1.0.0"]
        shapes "0.5zw" @?= ["0.5zw"]
        shapes "2026-11-09" @?= ["2026-11-09"]
        shapes "v1.0.0-rc4" @?= ["v1.0.0-", "|100", "rc4"],
      testCase "J1: a break where only one of the two characters is a digit" $ do
        shapes "a1.b" @?= ["a1.", "|100", "b"]
        shapes "1.a" @?= ["1.", "|100", "a"],
      testCase "J1: a run of two or three signs breaks after the run only, once" $ do
        shapes "a--b" @?= ["a--", "|100", "b"]
        shapes "a.-b" @?= ["a.-", "|100", "b"]
        shapes "a...b" @?= ["a...", "|100", "b"],
      testCase "J1: each string between spaces is judged alone" $
        shapes "a-b c.d" @?= ["a-", "|100", "b", "_", "c.", "|100", "d"],
      testCase "J1: a combining character after the sign stays with it" $
        shapes "a-\x0301\&b" @?= ["a-\x0301", "|100", "b"],
      testCase "J2: the break is as wide as the mark, as the break after a slash" $ do
        let ws = [(w, p, h) | Penalty w p h <- itemsIn env [code "a-b/c"]]
        ws @?= [(markWidth, 100, WrapMark mark), (markWidth, 0, WrapMark mark)],
      testCase "J2: with an empty wrap mark, the break is a break of 100 of no width and no hyphen" $
        shapesIn (envWith "") "a-b.c" @?= ["a-", "|100-", "b.", "|100-", "c"],
      testCase "J3: no break after other signs between Latin characters" $ do
        shapes "abc\"def" @?= ["abc\"def"]
        shapes "a:b" @?= ["a:b"]
        shapes "a=b" @?= ["a=b"],
      testCase "J3: a slash or a low line beside the run: the break of the slash or the low line only" $ do
        shapes "a/-b" @?= ["a/", "|0", "-b"]
        shapes "a-/b" @?= ["a-/", "|0", "b"]
        shapes "a_-b" @?= ["a_", "|100", "-b"]
        shapes "a-_b" @?= ["a-_", "|100", "b"],
      testCase "J4: before a Japanese character, the break of golem-layout ADR 0034 only" $ do
        shapes "a-あ" @?= ["a-", "|0", "あ"]
        shapes "a.。" @?= ["a.", "。"]
        shapes "a-（" @?= ["a-", "|0", "（"]
        shapes "あ-a" @?= ["あ", "|0", "-a"],
      testCase "J5: a URL breaks as before, not after a hyphen-minus sign" $ do
        let urlEnv = (defaultComposeEnv fs) {ceRestyle = \lk -> \case IR.CharStyle _ "url" _ -> lk {lkUrl = True}; _ -> lk}
            its = itemsIn urlEnv [IR.CharStyle sp "url" [IR.Text sp "https://a-b.example/c-d"]]
        [bcText c | Box _ c <- its] @?= ["https://", "a-b.", "example/", "c-d"],
      testCase "J5: a written hyphen of Latin text outside code breaks as before" $
        [(w, bcText c) | Box w c <- itemsIn env [IR.Text sp "lime-tree"]] <> [(w, T.pack (show (p, h))) | Penalty w p h <- itemsIn env [IR.Text sp "lime-tree"]]
          @?= [(Sp 1638400, "lime-"), (Sp 1310720, "tree"), (0, "(50,ExplicitHyphen)")],
      testCase "J6: aaaa-bbbb.cccc in lines of 4 em breaks into aaaa-, bbbb. and cccc, each but the last with the mark, none overfull" $ do
        let ls = brLines (enumLines (4 * fs) [code "aaaa-bbbb.cccc"])
        map lineText ls @?= ["aaaa-", "bbbb.", "cccc"]
        map endMarks ls @?= [[mark], [mark], []]
        map lineOverflow ls @?= [0, 0, 0]
        T.concat (map lineText ls) @?= "aaaa-bbbb.cccc",
      testCase "J1, J7: the case of the release chapter, Japanese text and a long code, breaks in the first two passes, every line but the last no looser than r = 1" $ do
        let br = enumLines (Sp (unSp fs * 43 `div` 2)) [IR.Text sp "あいうえおかきくけこ", code "aaaaaaa/aaaaaaaaaaaa-aaaaaaaaaa"]
            ls = brLines br
        assertBool ("pass " <> show (brPass br)) (brPass br <= 2)
        assertBool (show [(lineText l, lineRatio l) | l <- ls]) (all ((<= 1) . lineRatio) (take (length ls - 1) ls))
    ]
