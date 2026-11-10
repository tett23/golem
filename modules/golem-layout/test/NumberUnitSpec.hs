{- | Numbers kept with the units after them (docs/adr/0275): no break, or a
break of number-unit-penalty, between an Arabic digit and the kana or the
kanji after it, W1 to W5.

The items before the ADR are kept two ways: as literals for the
paragraphs of W3 and W4, and, for every run of the enumeration up to two
parts (with 円), as hashes in test/golden/number-unit.tsv, written by
the implementation before the ADR with the change the ADR allows applied
('numberUnitChange').
-}
module NumberUnitSpec (numberUnitTests, numberUnitPenalty) where

import Data.Bits (xor)
import Data.ByteString.Lazy qualified as BL
import Data.Char (ord)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word64)
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.TestSupport.Enum (Tiers (..), listsOf, upTo)
import LineBreakEnum (Setting (..), codeEnv, composeEnv, normalSettings, parts)
import LineBreakInvariants (penalizePairs, refArabicDigit)
import Numeric (showHex)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

numberUnitTests :: TestTree
numberUnitTests =
  testGroup
    "numbers kept with the units after them (docs/adr/0275)"
    [ testGroup "W1: no break" w1Tests,
      testGroup "W2: the penalty" w2Tests,
      testGroup "W3, W4: the items before the ADR" w34Tests,
      testGroup "W5: a range not broken wins" w5Tests,
      testGroup "code" codeTests,
      testGroup "W3, W4: every run of the enumeration up to two parts" goldenTests
    ]

{- | The penalty of a pair of a last and a first character (docs/adr/0275):
an Arabic digit and a kana or a kanji, P.
-}
numberUnitPenalty :: Int -> Char -> Char -> Maybe Int
numberUnitPenalty p a b
  | refArabicDigit a && charClass b `elem` [Kana, Ideograph] = Just p
  | otherwise = Nothing

-- | The default setting of the enumeration.
plain :: Setting
plain = Setting True False False Nothing

-- | The composition with the penalty given, vertical or not: no-break a range not broken.
envWith :: Int -> Bool -> ComposeEnv
envWith p vertical =
  (composeEnv vertical plain)
    { ceNumberUnitPenalty = p,
      ceRestyle = \lk -> \case
        IR.CharStyle _ "no-break" _ -> lk {lkNoBreak = True}
        _ -> lk
    }

itemsWith :: Int -> Text -> [Item]
itemsWith p t = fst (composeInlines (envWith p False) [IR.Text sp t])

items :: Text -> [Item]
items = itemsWith 10000

-- | Whether a break is legal between the k-th box and the next (counting from 0).
breakAfterBox :: [Item] -> Int -> Bool
breakAfterBox its k = case drop k [i | (i, Box {}) <- zip [0 :: Int ..] its] of
  a : b : _ -> any legalAt [a + 1 .. b - 1]
  _ -> False
  where
    legalAt i = case its !! i of
      Penalty _ n _ -> n < infPenalty
      Glue {} -> case its !! (i - 1) of
        Box {} -> True
        _ -> False
      Box {} -> False

-- | The items between the box ending with the first text and the next box, starting with the second.
between :: [Item] -> Text -> Text -> [Item]
between its a b = case [(i, j) | ((i, x), (j, y)) <- zip boxes (drop 1 boxes), a `T.isSuffixOf` x, b `T.isPrefixOf` y] of
  (i, j) : _ -> take (j - i - 1) (drop (i + 1) its)
  [] -> error ("no boxes " <> show (a, b) <> " in " <> show (map snd boxes))
  where
    boxes = [(i, bcText c) | (i, Box _ c) <- zip [0 :: Int ..] its]

-- | Whether a break is legal between the two boxes.
breakBetween :: [Item] -> Text -> Text -> Bool
breakBetween its a b = case [k | (k, (x, y)) <- zip [0 ..] (zip ts (drop 1 ts)), a `T.isSuffixOf` x, b `T.isPrefixOf` y] of
  k : _ -> breakAfterBox its k
  [] -> error ("no boxes " <> show (a, b) <> " in " <> show ts)
  where
    ts = [bcText c | Box _ c <- its]

-- | The text of each line of a text set with the penalty in lines of the width given.
linesIn :: Int -> Sp -> Text -> [Text]
linesIn p w t = [T.concat [bcText c | Box _ c <- lineItems l] | l <- brLines (breakParagraph defaultParams (const w) (itemsWith p t))]

w1Tests :: [TestTree]
w1Tests =
  [ testCase "W1: あ100円 in lines that end after 100 is not broken between 100 and 円: 100円 goes to the next line" $
      -- あ (1 em), the quarter em, 100 (1.5 em), the quarter em, 円 (1 em): あ100 is 2.75 em
      linesIn 10000 (3 * fs) "あ100円" @?= ["あ", "100円"],
    testCase "W1: no break between the number and the character after it in 100円, １０冊, 3つ and 5パーセント" $
      [ (t, a, b)
      | (t, a, b) <- [("100円", "100", "円"), ("１０冊", "０", "冊"), ("3つ", "3", "つ"), ("5パーセント", "5", "パ")],
        breakBetween (items t) a b
      ]
        @?= [],
    testCase "W1: the character after the unit, a kanji numeral and a full stop are as before" $ do
      breakBetween (items "2026年に") "年" "に" @?= True
      breakBetween (items "三人") "三" "人" @?= True
      -- a full stop after a digit is kept by the line-start prohibition, as before
      breakBetween (items "１。") "１" "。" @?= False,
    testCase "W1: in vertical writing alike" $
      breakBetween (fst (composeInlines (envWith 10000 True) [IR.Text sp "１０冊"])) "０" "冊" @?= False
  ]

w2Tests :: [TestTree]
w2Tests =
  [ testCase "W2: with 500, between 100 and 円 there is one penalty of 500, of no width, and the glue after it is no break" $ do
      let mid = between (itemsWith 500 "100円") "100" "円"
      [() | Penalty 0 500 NoHyphen <- mid] @?= [()]
      [() | Penalty _ n _ <- mid, n < infPenalty] @?= [()]
      case mid of
        Penalty {} : Glue {} : _ -> pure ()
        _ -> assertFailure (show mid),
    testCase "W2: with -9999, 0, 50 and 9999 the penalty is the value" $
      [p | p <- [-9999, 0, 50, 9999], [n | Penalty _ n _ <- between (itemsWith p "１０冊") "０" "冊"] /= [p]] @?= [],
    testCase "W2: a digit pair or a postfixed abbreviation keeps no break (golem-layout ADR 0049)" $ do
      breakBetween (itemsWith 50 "１２") "１" "２" @?= False
      breakBetween (itemsWith 50 "１％") "１" "％" @?= False
  ]

-- | The boxes and the glue of items: their widths, stretch and shrink, without the penalties (W3).
boxesAndGlue :: [Item] -> [(Char, Integer, Integer, Integer, Text)]
boxesAndGlue its = [x | it <- its, x <- shape it]
  where
    shape = \case
      Box w c -> [('B', unSp w, 0, 0, bcText c)]
      Glue w y z -> [('G', unSp w, unSp y, unSp z, "")]
      Penalty {} -> []

w34Tests :: [TestTree]
w34Tests =
  [ testCase "W3: the boxes and the glue of あ100円, 100円, １０冊, 3つ and 5パーセント are those before the ADR, with 10000 and 500" $
      [(t, p) | (t, before) <- recordedBoxes, p <- [10000, 500], boxesAndGlue (itemsWith p t) /= before] @?= [],
    testCase "W4: the items of 100 円 and 三人 are those before the ADR" $
      [(t, p) | (t, before) <- recordedItems, p <- [10000, 50], show (itemsShape (itemsWith p t)) /= before] @?= []
  ]

-- | The items without their looks.
itemsShape :: [Item] -> [(Char, Integer, Integer, Integer, Text, Int)]
itemsShape = map shape
  where
    shape = \case
      Box w c -> ('B', unSp w, 0, 0, bcText c, 0)
      Glue w y z -> ('G', unSp w, unSp y, unSp z, "", 0)
      Penalty w n _ -> ('P', unSp w, 0, 0, "", n)

w5Tests :: [TestTree]
w5Tests =
  [ testCase "W5: [style no-break: 100円] with 0 has no break between 100 and 円" $ do
      let its = fst (composeInlines (envWith 0 False) [IR.Text sp "あ", IR.CharStyle sp "no-break" [IR.Text sp "100円"], IR.Text sp "い"])
      breakBetween its "100" "円" @?= False
  ]

codeTests :: [TestTree]
codeTests =
  [ testCase "W4: the items of [code: 100円] and [code: １０冊] are the same whatever the penalty: not between two boxes of code" $
      [ t
      | t <- ["100円", "１０冊"],
        let codeItems p = itemsShape (fst (composeInlines ((codeEnv False plain) {ceNumberUnitPenalty = p}) [IR.CharStyle sp "code" [IR.Text sp t]])),
        any (\p -> codeItems p /= codeItems 10000) [0, 50, 9999]
      ]
        @?= []
  ]

-- * W3, W4: the golden hashes

{- | The change docs/adr/0275 makes to the items, with the penalty given:
'penalizePairs' of 'numberUnitPenalty', but between two boxes of code or a
URL ('adjacentPairs' leaves those out).
-}
numberUnitChange :: Int -> Text -> [Item] -> [Item]
numberUnitChange p = penalizePairs (numberUnitPenalty p)

{- | Every run of the enumeration up to two parts (the parts of
golem-layout ADR 0049 and 円), each in its settings of the normal form,
with 'あ' none or once before it and 'い' none or once after it, with the
penalties 10000 and 50, horizontal and vertical: the hash of the items
with the change of the ADR applied. Written by the implementation before
the ADR; the items are also the same with the change applied, so they are
those before the ADR with the change.
-}
goldenTests :: [TestTree]
goldenTests =
  [ goldenVsString
      "W3, W4: the items of every run are those before the ADR with its change (test/golden/number-unit.tsv)"
      "test/golden/number-unit.tsv"
      (pure (BL.fromStrict (TE.encodeUtf8 (T.unlines (map line runs))))),
    testCase "W1, W2: the change of the ADR changes no items of any run: the breaks of its pairs are already its penalty" $
      take 5 [(run, k, p, v) | run <- runs, p <- [10000, 50], v <- [False, True], (k, its) <- itemsOfRun p v run, numberUnitChange p (textOf k run) its /= its]
        @?= []
  ]
  where
    runs = concat (upTo 2 (listsOf (Tiers [parts])))
    line run = T.intercalate "\t" (T.pack (show run) : [hashOf p v run | p <- [10000, 50], v <- [False, True]])
    hashOf p v run = T.pack (showHex (fnv (show [(k, itemsShape (numberUnitChange p (textOf k run) its)) | (k, its) <- itemsOfRun p v run])) "")
    textOf (_, pre, post) run = T.replicate pre "あ" <> T.concat run <> T.replicate post "い"
    itemsOfRun p v run =
      [ ((s, pre, post), fst (composeInlines ((composeEnv v s) {ceNumberUnitPenalty = p}) (inl s pre run post)))
      | s <- normalSettings run,
        pre <- [0, 1],
        post <- [0, 1]
      ]
    inl s pre run post =
      [IR.Text sp (T.replicate pre "あ") | pre > 0]
        <> [maybe text (\l -> IR.Lang sp l [text]) (sLang s) | not (null run)]
        <> [IR.Text sp (T.replicate post "い") | post > 0]
      where
        text = IR.Text sp (T.concat run)

-- | FNV-1a, 64 bits, over the code points of a string.
fnv :: String -> Word64
fnv = foldl (\h c -> (h `xor` fromIntegral (ord c)) * 0x100000001b3) 0xcbf29ce484222325

-- * the items recorded before the ADR

-- | The boxes and the glue of the paragraphs of W3, as the implementation before the ADR gave them.
recordedBoxes :: [(Text, [(Char, Integer, Integer, Integer, Text)])]
recordedBoxes =
  [ ("あ100円", [('B', 655360, 0, 0, "あ"), ('G', 163840, 163840, 81920, ""), ('B', 983040, 0, 0, "100"), ('G', 163840, 163840, 81920, ""), ('B', 655360, 0, 0, "円"), ('G', 0, 1125899906842624, 0, "")]),
    ("100円", [('B', 983040, 0, 0, "100"), ('G', 163840, 163840, 81920, ""), ('B', 655360, 0, 0, "円"), ('G', 0, 1125899906842624, 0, "")]),
    ("１０冊", [('B', 655360, 0, 0, "１"), ('G', 0, 65536, 0, ""), ('B', 655360, 0, 0, "０"), ('G', 0, 65536, 0, ""), ('B', 655360, 0, 0, "冊"), ('G', 0, 1125899906842624, 0, "")]),
    ("3つ", [('B', 327680, 0, 0, "3"), ('G', 163840, 163840, 81920, ""), ('B', 655360, 0, 0, "つ"), ('G', 0, 1125899906842624, 0, "")]),
    ("5パーセント", [('B', 327680, 0, 0, "5"), ('G', 163840, 163840, 81920, ""), ('B', 655360, 0, 0, "パ"), ('B', 655360, 0, 0, "ー"), ('G', 0, 65536, 0, ""), ('B', 655360, 0, 0, "セ"), ('G', 0, 65536, 0, ""), ('B', 655360, 0, 0, "ン"), ('G', 0, 65536, 0, ""), ('B', 655360, 0, 0, "ト"), ('G', 0, 1125899906842624, 0, "")])
  ]

-- | The items of the paragraphs of W4, as the implementation before the ADR gave them (shown).
recordedItems :: [(Text, String)]
recordedItems =
  [ ("100 \20870", "[('B',983040,0,0,\"100\",0),('G',163840,81920,54613,\"\",0),('B',655360,0,0,\"\\20870\",0),('P',0,0,0,\"\",10000),('G',0,1125899906842624,0,\"\",0),('P',0,0,0,\"\",-10000)]"),
    ("\19977\20154", "[('B',655360,0,0,\"\\19977\",0),('G',0,65536,0,\"\",0),('B',655360,0,0,\"\\20154\",0),('P',0,0,0,\"\",10000),('G',0,1125899906842624,0,\"\",0),('P',0,0,0,\"\",-10000)]")
  ]
