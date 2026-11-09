-- | itemNumbers and the number formats of lists (golem-driver ADR 0013).
module ListMarkersSpec (tests) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble (AssembleConfig (..), Book, NoteNumbering (..), assemble)
import Golem.Assemble.ListMarkers
import Golem.Doc.IR
import Golem.Numerals (kanji)
import Golem.Numerals.Format (Legacy (..))
import Golem.Numerals.Notation
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

item :: Maybe Integer -> ListItem
item n = ListItem (fromInteger <$> n) [Block sp Nothing Nothing (Paragraph Nothing [Text sp "x"])]

tests :: TestTree
tests =
  testGroup
    "lists (golem-driver ADR 0013)"
    [ testCase "itemNumbers counts from 1, and on from @number" $ do
        itemNumbers [item Nothing, item Nothing, item Nothing] @?= [1, 2, 3]
        itemNumbers [item Nothing, item (Just 10), item Nothing] @?= [1, 10, 11],
      testCase "formatListNumber writes a number in each notation, or cannot" $ do
        formatListNumber (NsNotation arabic) 3 @?= Just "3"
        formatListNumber (NsNotation kanjiNotation) 3 @?= Just "三"
        formatListNumber (NsNotation circledNotation) 51 @?= Nothing
        formatListNumber (NsNotation asterisksNotation) 3 @?= Just "***"
        formatListNumber NsBook 3 @?= Just "3",
      testCase "the rows of the old placeholders write what formatListNumber wrote (docs/adr/0177)" $
        sequence_
          [ formatListNumber (NsNotation n) k @?= oldFormatListNumber old k
          | (old, n) <- [(OldArabic, arabic), (OldKanji, kanjiNotation), (OldCircled, circledNotation), (OldLowerAlpha, lowerAlphaNotation), (OldUpperAlpha, upperAlphaNotation), (OldLowerRoman, lowerRomanNotation), (OldUpperRoman, upperRomanNotation), (OldIroha, irohaNotation), (OldAiueo, aiueoNotation)],
            k <- [0 .. 200] <> [3998, 3999, 4000, 4001]
          ],
      testCase "a number format has one placeholder; the old forms are read and reported; each error names its reason" $ do
        parseNumberFormat "{n}." @?= Right (NumberFormat "" NsBook ".")
        parseNumberFormat "({a})" @?= Right (NumberFormat "(" (NsNotation lowerAlphaNotation) ")")
        parseNumberFormat "({n:lower-alpha})" @?= Right (NumberFormat "(" (NsNotation lowerAlphaNotation) ")")
        parseNumberFormatLegacy "{{{n}}}" @?= Right (NumberFormat "{" NsBook "}", [LegacyBraces, LegacyBraces])
        parseNumberFormatLegacy "\\{{n}\\}" @?= Right (NumberFormat "{" NsBook "}", [])
        parseNumberFormatLegacy "第{一}" @?= Right (NumberFormat "第" (NsNotation kanjiNotation) "", [LegacySample "一" kanjiNotation])
        parseNumberFormat "{n:asterisks}" @?= Right (NumberFormat "" (NsNotation asterisksNotation) "")
        parseNumberFormat "x" @?= Left "番号の差し込みがありません"
        parseNumberFormat "{n}{n}" @?= Left "番号の差し込みが二つ以上あります"
        parseNumberFormat "{x}" @?= Left "表にない差し込みです: {x}"
        parseNumberFormat "{n" @?= Left "閉じていない { があります。文字の { は \\{ と書きます"
        parseNumberFormat "{n}}" @?= Left "対応する { のない } があります。文字の } は \\} と書きます",
      testCase "renderNumberFormat writes a format in the new way" $
        mapM_ (\(f, g) -> fmap renderNumberFormat (parseNumberFormat f) @?= Right g) [("{n}.", "{n}."), ("({a})", "({n:lower-alpha})"), ("{{{n}}}", "\\{{n}\\}"), ("{①}", "{n:circled}"), ("{n:iroha}", "{n:iroha}")],
      testCase "a list deeper than the given styles keeps the last style" $
        map (atDepth (pure 'a' <> pure 'b')) [1, 2, 3] @?= "abb",
      testCase "numbered items are listed with their numbers and depths, at their first blocks" $ do
        let inner = Block sp Nothing Nothing (OrderedList [item (Just 5)])
            second = SrcSpan (FileId 0) 3 4
            outer = Block sp Nothing Nothing (OrderedList [item Nothing, ListItem Nothing [Block second Nothing Nothing (Paragraph Nothing []), inner]])
        listSites [outer] @?= [ListSite 1 1 sp, ListSite 1 2 second, ListSite 2 5 sp],
      listNumberTests
    ]

-- | A book of the blocks of one file.
bookOf :: [Block] -> Book
bookOf bs = fst (assemble cfg (\_ _ _ -> Right "") [Document (FileId 0) bs])
  where
    cfg = AssembleConfig Map.empty "図{chapter}-{n}" Map.empty NumberPerFile [] "リスト{chapter}-{n}" "表{chapter}-{n}" Map.empty 16

-- | The code, the span and the message of each diagnostic.
sites :: [Diagnostic] -> [(Text, SrcSpan, Text)]
sites = map (\d -> let DiagnosticCode c = diagCode d in (c, diagSpan d, diagMessage d))

listNumberTests :: TestTree
listNumberTests =
  testGroup
    "G07029 (docs/adr/0192)"
    [ testCase "a number its format cannot write is G07029, at the item" $ do
        let at51 = SrcSpan (FileId 0) 5 6
            list = Block sp Nothing Nothing (OrderedList [item Nothing, ListItem (Just 51) [Block at51 Nothing Nothing (Paragraph Nothing [Text at51 "x"])]])
            circled = parseNumberFormat "{①}"
        case circled of
          Right f ->
            sites (listNumberDiagnostics (Just (f :| [])) False (bookOf [list]))
              @?= [("G07029", at51, "リストの番号 51 は、書式 {n:circled} で表せません")]
          Left e -> assertFailure (show e),
      testCase "without formats, the default of each writing mode decides" $ do
        let list = Block sp Nothing Nothing (OrderedList [item Nothing, item (Just 100000)])
        sites (listNumberDiagnostics Nothing False (bookOf [list])) @?= []
        sites (listNumberDiagnostics Nothing True (bookOf [list])) @?= [],
      testCase "a book of numbers its formats can write has no G07029" $ do
        let list = Block sp Nothing Nothing (OrderedList [item Nothing, item (Just 50)])
        case parseNumberFormat "{①}" of
          Right f -> sites (listNumberDiagnostics (Just (f :| [])) False (bookOf [list])) @?= []
          Left e -> assertFailure (show e)
    ]

-- | The notations of formatListNumber before docs/adr/0177, as it was: the reference of the table.
data OldStyle = OldArabic | OldKanji | OldCircled | OldLowerAlpha | OldUpperAlpha | OldLowerRoman | OldUpperRoman | OldIroha | OldAiueo

oldFormatListNumber :: OldStyle -> Integer -> Maybe Text
oldFormatListNumber st n = case st of
  OldArabic -> Just (T.pack (show n))
  OldKanji -> Just (kanji n)
  OldCircled
    | n >= 1 && n <= 20 -> Just (T.singleton (toEnum (0x2460 + fromInteger n - 1)))
    | n >= 21 && n <= 35 -> Just (T.singleton (toEnum (0x3251 + fromInteger n - 21)))
    | n >= 36 && n <= 50 -> Just (T.singleton (toEnum (0x32B1 + fromInteger n - 36)))
    | otherwise -> Nothing
  OldLowerAlpha -> alpha 'a'
  OldUpperAlpha -> alpha 'A'
  OldLowerRoman -> T.toLower <$> roman
  OldUpperRoman -> roman
  OldIroha -> fromList "イロハニホヘトチリヌルヲワカヨタレソツネナラムウヰノオクヤマケフコエテアサキユメミシヱヒモセス"
  OldAiueo -> fromList "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"
  where
    alpha base
      | n < 1 = Nothing
      | otherwise = Just (T.pack (letters n))
      where
        letters k
          | k <= 0 = []
          | otherwise = let (q, r) = (k - 1) `divMod` 26 in letters q <> [toEnum (fromEnum base + fromInteger r)]
    roman
      | n < 1 || n > 3999 = Nothing
      | otherwise = Just (T.pack (go n numerals))
      where
        go 0 _ = ""
        go k ((v, s) : rest)
          | k >= v = s <> go (k - v) ((v, s) : rest)
          | otherwise = go k rest
        go _ [] = ""
        numerals = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
    fromList :: Text -> Maybe Text
    fromList cs
      | n >= 1 && n <= toInteger (T.length cs) = Just (T.singleton (T.index cs (fromInteger n - 1)))
      | otherwise = Nothing
