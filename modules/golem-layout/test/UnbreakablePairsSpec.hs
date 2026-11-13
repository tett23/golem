{- | The character classes and the unbreakable pairs of JLReq
(golem-layout ADR 0049): the six characters added to the classes, the
predicates of digits, numerals and abbreviations, and no break between a
pair of digits (in horizontal writing), a prefixed abbreviation and a
numeral, and a numeral and a postfixed abbreviation, B1 to B8.

'pre0049CharClass' retains the earlier class table. The item fixtures
and hashes also cover the zero stretch required by Golem ADR 0362.
-}
module UnbreakablePairsSpec
  ( unbreakablePairsTests,
  )
where

import Data.Bits (xor)
import Data.ByteString.Lazy qualified as BL
import Data.Char (ord)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word64)
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Aki qualified as A
import Golem.Layout.CharClass
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.TestSupport.Enum (Tiers (..), listsOf, upTo)
import LineBreakEnum (Setting (..), codeEnv, composeEnv, normalSettings, partsBefore0275)
import LineBreakInvariants (forbidPairs, refArabicDigit, refNumeral, refPostfixed, refPrefixed, withoutNumberUnits)
import Numeric (showHex)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

unbreakablePairsTests :: TestTree
unbreakablePairsTests =
  testGroup
    "character classes and unbreakable pairs of JLReq (golem-layout ADR 0049)"
    [ testCase "inv1_unbreakable_spacing_case_1" $
        [unSp y | Glue _ y _ _ _ <- items "１２３", y < filStretch] @?= [0, 0],
      testCase "inv1_unbreakable_spacing_case_2" $
        [unSp y | Glue _ y _ _ _ <- items "１", y < filStretch] @?= [],
      testCase "inv1_unbreakable_spacing_property" $ do
        let positions = map A.AkiChar [minBound .. maxBound]
            custom = A.withAkiRule positions positions (A.Aki 0 (1 / 4) (3 / 4)) A.defaultAkiSet
            gaps vertical t =
              [g | g@Glue {} <- fst (composeInlines ((composeEnv vertical plain) {ceAkiSet = custom}) [IR.Text sp t]), itemStretch g < filStretch]
            protected = [(False, "１２"), (False, "￥一"), (True, "〇％"), (False, "……")]
        mapM_
          ( \(v, t) -> do
              let gs = gaps v t
              [(itemWidth g, itemStretch g, itemShrink g) | g <- gs] @?= [(163840, 0, 163840)]
              mapM_
                (\(target, order) -> glueAmounts (Line gs 0 target 0 (0, 0) 0 (0, 0) Nothing order) @?= [0])
                [(target, order) | target <- [fs, 100 * fs], order <- [AdjustUniform, AdjustStaged [] []]]
          )
          protected
        map (map itemStretch . uncurry gaps) [(False, "１漢"), (True, "１２")] @?= [[327680], [327680]],
      testGroup "B1: the characters added to the classes" b1Tests,
      testGroup "the predicates of digits, numerals and abbreviations" predicateTests,
      testGroup "B2: a run of digits" b2Tests,
      testGroup "B3: a prefixed abbreviation and a numeral" b3Tests,
      testGroup "B4: a numeral and a postfixed abbreviation" b4Tests,
      testGroup "B5: a pair across a space" b5Tests,
      testGroup "B6: the candidates only taken out" b6Tests,
      testGroup "B8: code" b8Tests,
      testGroup "B6, B7: every run of the enumeration up to two parts" goldenTests
    ]

-- * B1

-- | The characters of the table of the ADR's section 1, with their classes.
added :: [(Char, CharClass)]
added =
  [ ('\x2985', Opening),
    ('\x2986', Closing),
    ('\x301E', Closing),
    ('\xFF5E', Hyphen),
    ('\x2E3A', Inseparable),
    ('\x2E3B', Inseparable)
  ]

b1Tests :: [TestTree]
b1Tests =
  [ testCase "B1: each character of the table is of its class" $
      [(c, charClass c) | (c, _) <- added] @?= added,
    testCase "B1: on U+0000 to U+FFFF and U+1B000 to U+1B16F, charClass differs from before the ADR on the characters of the table only" $
      [c | c <- ['\x0000' .. '\xFFFF'] <> ['\x1B000' .. '\x1B16F'], charClass c /= pre0049CharClass c] @?= sort (map fst added),
    testCase "B1: a character of the table is no character of both scripts, and its class is the same in every span" $
      [(c, l) | (c, k) <- added, l <- [Nothing, Just "ja", Just "en"], charClassIn l c /= k] @?= []
  ]

-- | 'charClass' before golem-layout ADR 0049, copied as it was.
pre0049CharClass :: Char -> CharClass
pre0049CharClass c
  | c `elem` ("「『（［｛〈《【〔〘〖〝‘“｟«" :: String) = Opening
  | c `elem` ("」』）］｝〉》】〕〙〗〟’”｠»" :: String) = Closing
  | c `elem` ("‐‑〜゠–" :: String) = Hyphen
  | c `elem` ("？！‼⁇⁈⁉" :: String) = Dividing
  | c `elem` ("・：；" :: String) = MiddleDot
  | c `elem` ("。．" :: String) = FullStop
  | c `elem` ("、，" :: String) = Comma
  | c `elem` ("—―…‥〳〴〵" :: String) = Inseparable
  | c `elem` ("ヽヾゝゞ々〻" :: String) = Iteration
  | c == 'ー' = ProlongedSound
  | c `elem` ("ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ" :: String) = SmallKana
  | c == '\x3000' = IdeographicSpace
  | (c >= '\x3041' && c <= '\x309F') || (c >= '\x30A0' && c <= '\x30FF') = Kana
  | c < '\x80' || (c >= '\x00A0' && c <= '\x024F') || (c >= '\x0370' && c <= '\x04FF') = Western
  | otherwise = Ideograph

-- * the predicates (the ADR's section 2)

predicateTests :: [TestTree]
predicateTests =
  [ testCase "isArabicDigit, isNumeral, isPrefixedAbbreviation and isPostfixedAbbreviation are the lists of the ADR on every code point" $
      take 10 [c | c <- [minBound .. maxBound], (isArabicDigit c, isNumeral c, isPrefixedAbbreviation c, isPostfixedAbbreviation c) /= (refArabicDigit c, refNumeral c, refPrefixed c, refPostfixed c)] @?= [],
    testCase "the lists hold 20 digits, 36 numerals, 10 prefixed and 34 postfixed abbreviations" $
      map (\p -> length (filter p [minBound .. maxBound])) [refArabicDigit, refNumeral, refPrefixed, refPostfixed] @?= [20, 36, 10, 34]
  ]

-- * the paragraphs

-- | The default setting of the enumeration: strict kinsoku, no hanging, no protrusion, no span.
plain :: Setting
plain = Setting True False False Nothing

{- | The items of a text, vertical or not, without the change of
docs/adr/0275, which keeps a digit with a kanji after it in vertical
writing too: these tests are of golem-layout ADR 0049 alone.
-}
itemsV :: Bool -> Text -> [Item]
itemsV vertical t = withoutNumberUnits vertical t (fst (composeInlines (composeEnv vertical plain) [IR.Text sp t]))

items :: Text -> [Item]
items = itemsV False

-- | What the tests compare of an item: the boxes by their characters, the widths, stretch and shrink, the penalties and their hyphens.
data Shape = SBox Integer Text | SGlue Integer Integer Integer | SPen Integer Int String
  deriving stock (Eq, Show)

shapeOf :: Item -> Shape
shapeOf = \case
  Box w c -> SBox (unSp w) (bcText c)
  Glue w y z _ _ -> SGlue (unSp w) (unSp y) (unSp z)
  Penalty w p h -> SPen (unSp w) p (hyphenName h)
  where
    hyphenName = \case
      NoHyphen -> ""
      ExplicitHyphen -> "E"
      PatternHyphen _ -> "P"
      SoftHyphen _ -> "S"
      WrapMark m -> "W" <> T.unpack m

shapes :: [Item] -> [Shape]
shapes = map shapeOf

-- | Whether a break is legal between the k-th box and the next (counting from 0).
breakAfterBox :: [Item] -> Int -> Bool
breakAfterBox its k = case drop k [i | (i, Box {}) <- zip [0 :: Int ..] its] of
  a : b : _ -> any legalAt [a + 1 .. b - 1]
  _ -> False
  where
    legalAt i = case its !! i of
      Penalty _ p _ -> p < infPenalty
      Glue {} -> case its !! (i - 1) of
        Box {} -> True
        _ -> False
      Box {} -> False

-- | The texts of the boxes.
boxTexts :: [Item] -> [Text]
boxTexts its = [bcText c | Box _ c <- its]

-- | Whether a break is legal between the box ending with the first text and the next box starting with the second.
breakBetween :: [Item] -> Text -> Text -> Bool
breakBetween its a b =
  case [k | (k, (x, y)) <- zip [0 ..] (zip ts (drop 1 ts)), a `T.isSuffixOf` x, b `T.isPrefixOf` y] of
    k : _ -> breakAfterBox its k
    [] -> error ("no boxes " <> show (a, b) <> " in " <> show ts)
  where
    ts = boxTexts its

-- | The text of each line of a text set in lines of n em, vertical or not.
linesIn :: Bool -> Int -> Text -> [Text]
linesIn vertical n t =
  [T.concat (boxTexts (lineItems l)) | l <- brLines (breakParagraph defaultParams (const (fromIntegral n * fs)) (itemsV vertical t))]

-- * B2 to B8

b2Tests :: [TestTree]
b2Tests =
  [ testCase "B2: horizontal, １２３ in lines of 2 em is not broken between １ and ２: one line, past W" $
      linesIn False 2 "１２３" @?= ["１２３"],
    testCase "B2: horizontal, １２３ in lines of 3 em is one line" $
      linesIn False 3 "１２３" @?= ["１２３"],
    testCase "B2: vertical, １２３ in lines of 2 em is broken as before the ADR" $
      linesIn True 2 "１２３" @?= ["１２", "３"],
    testCase "B2: no candidate between two digits of either width, horizontal; between them vertical" $ do
      map (\(a, b) -> breakBetween (items (a <> b)) a b) pairsOfDigits @?= map (const False) pairsOfDigits
      map (\(a, b) -> breakBetween (itemsV True (a <> b)) a b) widePairs @?= map (const True) widePairs,
    testCase "B2: a digit and a kanji numeral are no run of digits" $
      breakBetween (items "１一") "１" "一" @?= True
  ]
  where
    pairsOfDigits = [("1", "１"), ("１", "1"), ("１", "２"), ("０", "９")]
    widePairs = [("１", "２"), ("０", "９")]

b3Tests :: [TestTree]
b3Tests =
  [ testCase "B3: あ￥１００ has no candidate between ￥ and １, and is broken after あ in lines of 2 em" $ do
      breakBetween (items "あ￥１００") "￥" "１" @?= False
      linesIn False 2 "あ￥１００" @?= ["あ", "￥１００"],
    testCase "B3: €100 and №1 have no candidate between the sign and the number" $ do
      breakBetween (items "€100") "€" "100" @?= False
      breakBetween (items "№1") "№" "1" @?= False,
    testCase "B3: each prefixed abbreviation before １ and 一, in vertical writing too" $
      [ (a, n, v)
      | a <- "¥$£#€№￥＄￡＃",
        n <- "１一",
        v <- [False, True],
        breakBetween (itemsV v (T.pack [a, n])) (T.singleton a) (T.singleton n)
      ]
        @?= []
  ]

b4Tests :: [TestTree]
b4Tests =
  [ testCase "B4: 100％, 三〇％, １０℃ and 5′ have no candidate between the number and the sign" $ do
      breakBetween (items "100％") "100" "％" @?= False
      breakBetween (items "三〇％") "〇" "％" @?= False
      breakBetween (items "１０℃") "０" "℃" @?= False
      breakBetween (items "5′") "5" "′" @?= False,
    testCase "B4: ￥１００％ has no candidate in it" $
      [k | k <- [0 .. 3], breakAfterBox (items "￥１００％") k] @?= [],
    testCase "B4: each postfixed abbreviation after ０ and 〇, in vertical writing too" $
      [ (n, a, v)
      | n <- "０〇",
        a <- "°′″℃¢%‰㏋ℓ㌃㌍㌔㌘㌢㌣㌦㌧㌫㌶㌻㍉㍊㍍㍑㍗㎎㎏㎜㎝㎞㎡㏄％￠",
        v <- [False, True],
        breakBetween (itemsV v (T.pack [n, a])) (T.singleton n) (T.singleton a)
      ]
        @?= []
  ]

b5Tests :: [TestTree]
b5Tests =
  [ testCase "B5: the items of １００ ％ keep the word space and suppress stretch only between the digits" $
      shapes (items "１００ ％") @?= recordedSpaced
  ]

b6Tests :: [TestTree]
b6Tests =
  [ testCase ("B6: the items of " <> T.unpack t <> " have infinite pair penalties and zero stretch at those pairs") $
      shapes (items t) @?= want
  | (t, want) <- recordedPairs
  ]

b8Tests :: [TestTree]
b8Tests =
  [ testCase ("B8: the items of [code: " <> T.unpack t <> "] are those before the ADR") $
      shapes (codeItems t) @?= want
  | (t, want) <- recordedCode
  ]
  where
    codeItems t = fst (composeInlines (codeEnv False plain) [IR.CharStyle sp "code" [IR.Text sp t]])

-- * B6, B7: the golden hashes

{- | Every run of the enumeration up to two parts (the 24 parts of
docs/adr/0209 and １, ％ and ￥), each in its settings of the normal form,
with 'あ' set none or once before it and 'い' none or once after it,
horizontal and vertical. The golden hashes include the pair penalties
and the zero stretch of Golem ADR 0362.
-}
goldenTests :: [TestTree]
goldenTests =
  [ goldenVsString
      "B6, B7: the items of every run include the pair penalties and stretch limits (test/golden/unbreakable-pairs.tsv)"
      "test/golden/unbreakable-pairs.tsv"
      (pure (BL.fromStrict (TE.encodeUtf8 (T.unlines (map line runs))))),
    testCase "B6: the change of B6 changes no items of any run: the candidates of the pairs are already infinite" $
      take 5 [(run, k, v) | run <- runs, v <- [False, True], (k, its) <- itemsOfRun v run, forbidPairs v (textOf' k run) its /= its]
        @?= []
  ]
  where
    runs = concat (upTo 2 (listsOf (Tiers [partsBefore0275])))
    line run = T.intercalate "\t" [T.pack (show run), hashOf False run, hashOf True run]
    hashOf v run = T.pack (showHex (fnv (show [(s, map shapeOf (forbidPairs v t its)) | (s, its) <- itemsOfRun v run, let t = textOf' s run])) "")
    textOf' (_, pre, post) run = T.replicate pre "あ" <> T.concat run <> T.replicate post "い"
    itemsOfRun v run =
      [ ((s, pre, post), its)
      | -- the span of fr, added to the enumeration after the golden was
        -- written (docs/adr ADR 0276), is not in it
        s <- filter ((/= Just "fr") . sLang) (normalSettings run),
        pre <- [0, 1],
        post <- [0, 1],
        -- without the change of docs/adr/0275, as the hashes were written before it
        let its = withoutNumberUnits v (textOf' (s, pre, post) run) (fst (composeInlines (composeEnv v s) (inl s pre run post)))
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

{- * the items recorded before the ADR

The items the implementation before golem-layout ADR 0049 gave, with the
change of B6 applied ('forbidPairs') and pair stretches zeroed for Golem ADR 0362; code items are unchanged.
-}

recordedSpaced :: [Shape]
recordedSpaced =
  [SBox 655360 "１", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "０", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "０", SGlue 163840 81920 54613, SBox 655360 "％", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]

recordedPairs :: [(Text, [Shape])]
recordedPairs =
  [ ("１２３", [SBox 655360 "１", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "２", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "３", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("あ￥１００", [SBox 655360 "あ", SGlue 0 65536 0, SBox 655360 "￥", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "１", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "０", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "０", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("€100", [SBox 655360 "€", SPen 0 10000 "", SGlue 163840 0 81920, SBox 983040 "100", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("№1", [SBox 655360 "№", SPen 0 10000 "", SGlue 163840 0 81920, SBox 327680 "1", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("100％", [SBox 983040 "100", SPen 0 10000 "", SGlue 163840 0 81920, SBox 655360 "％", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("三〇％", [SBox 655360 "三", SGlue 0 65536 0, SBox 655360 "〇", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "％", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("１０℃", [SBox 655360 "１", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "０", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "℃", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("5′", [SBox 327680 "5", SPen 0 10000 "", SGlue 163840 0 81920, SBox 655360 "′", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("￥１００％", [SBox 655360 "￥", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "１", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "０", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "０", SPen 0 10000 "", SGlue 0 0 0, SBox 655360 "％", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""])
  ]

recordedCode :: [(Text, [Shape])]
recordedCode =
  [ ("１２３", [SBox 655360 "１", SPen 393216 0 "W⏎", SBox 655360 "２", SPen 393216 0 "W⏎", SBox 655360 "３", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""]),
    ("100％", [SBox 983040 "100", SPen 393216 0 "W⏎", SBox 655360 "％", SPen 0 10000 "", SGlue 0 1125899906842624 0, SPen 0 (-10000) ""])
  ]
