module Main (main) where

import Data.Char (isAsciiLower, isDigit)
import Data.Either (isLeft)
import Data.List (nub)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Golem.Numerals (kanji)
import Golem.Numerals.Format
import Golem.Numerals.Notation
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

named :: T.Text -> Notation
named t = fromMaybe (error ("no notation " <> T.unpack t)) (notationNamed t)

tests :: TestTree
tests =
  testGroup
    "golem-numerals"
    [ testGroup
        "the integers of the IR are int64 (golem-doc ADR 0006)"
        [ testCase "kanji up to the ends of int64" $ do
            kanji (2 ^ (63 :: Int) - 1) @?= "九百二十二京三千三百七十二兆三百六十八億五千四百七十七万五千八百七"
            kanji (negate (2 ^ (63 :: Int))) @?= "マイナス九百二十二京三千三百七十二兆三百六十八億五千四百七十七万五千八百八"
            kanji (10 ^ (16 :: Int)) @?= "一京"
        ],
      testGroup
        "the table of notations (docs/adr/0177)"
        [ testCase "each row writes 1, 2, 3 and 12, and the ends of its range" $ do
            let row name = map (writeNumber (named name))
            row "arabic" [0, 1, 2, 3, 12] @?= map Just ["0", "1", "2", "3", "12"]
            row "arabic" [-1] @?= [Nothing]
            row "kanji" [0, 1, 2, 3, 12] @?= map Just ["〇", "一", "二", "三", "十二"]
            row "kanji" [-1] @?= [Nothing]
            row "kanji-digits" [0, 1, 2, 3, 12] @?= map Just ["〇", "一", "二", "三", "一二"]
            row "kanji-digits" [-1] @?= [Nothing]
            row "circled" [1, 2, 3, 12, 20, 21, 35, 36, 50] @?= map Just ["①", "②", "③", "⑫", "⑳", "㉑", "㉟", "㊱", "㊿"]
            row "circled" [0, 51] @?= [Nothing, Nothing]
            row "lower-alpha" [1, 2, 3, 12, 26, 27, 52] @?= map Just ["a", "b", "c", "l", "z", "aa", "az"]
            row "lower-alpha" [0] @?= [Nothing]
            row "upper-alpha" [1, 2, 3, 12, 27] @?= map Just ["A", "B", "C", "L", "AA"]
            row "upper-alpha" [0] @?= [Nothing]
            row "lower-roman" [1, 2, 3, 12, 1994, 3999] @?= map Just ["i", "ii", "iii", "xii", "mcmxciv", "mmmcmxcix"]
            row "lower-roman" [0, 4000] @?= [Nothing, Nothing]
            row "upper-roman" [1, 2, 3, 12, 3999] @?= map Just ["I", "II", "III", "XII", "MMMCMXCIX"]
            row "upper-roman" [0, 4000] @?= [Nothing, Nothing]
            row "iroha" [1, 2, 3, 12, 47] @?= map Just ["イ", "ロ", "ハ", "ヲ", "ス"]
            row "iroha" [0, 48] @?= [Nothing, Nothing]
            row "aiueo" [1, 2, 3, 12, 46] @?= map Just ["ア", "イ", "ウ", "シ", "ン"]
            row "aiueo" [0, 47] @?= [Nothing, Nothing]
            row "asterisks" [1, 2, 3, 12] @?= map Just ["*", "**", "***", "************"]
            row "asterisks" [0] @?= [Nothing]
            row "note-symbols" [1, 2, 3] @?= map Just ["*", "\x2020", "\x2021"],
          testCase "note-symbols are the seven of JLReq 4.2.2, and no more" $ do
            map (writeNumber noteSymbolsNotation) [1 .. 7] @?= map (Just . T.singleton) "*\x2020\x2021\x00B6\x00A7\x2016#"
            writeNumber noteSymbolsNotation 0 @?= Nothing
            writeNumber noteSymbolsNotation 8 @?= Nothing,
          testCase "the ranges come from the rows" $ do
            notationRange arabic @?= (0, Nothing)
            notationRange circledNotation @?= (1, Just 50)
            notationRange upperRomanNotation @?= (1, Just 3999)
            notationRange irohaNotation @?= (1, Just 47)
            notationRange aiueoNotation @?= (1, Just 46)
            notationRange noteSymbolsNotation @?= (1, Just 7)
            notationRange asterisksNotation @?= (1, Nothing),
          testCase "the names differ and are of lower-case letters, digits and -" $ do
            let names = map notationName notations
            length (nub names) @?= length names
            assertBool "the characters of the names" (all (T.all (\c -> isAsciiLower c || isDigit c || c == '-')) names)
            map notationName notations @?= ["arabic", "kanji", "kanji-digits", "circled", "lower-alpha", "upper-alpha", "lower-roman", "upper-roman", "iroha", "aiueo", "asterisks", "note-symbols"]
        ],
      testGroup
        "the reading of formats (docs/adr/0177)"
        [ testCase "escapes are characters" $ do
            parseMarkFormat "\\{{n}\\}" @?= Right (MarkFormat "{" arabic "}")
            parseMarkFormat "\\\\{n}" @?= Right (MarkFormat "\\" arabic "")
            parseMarkFormat "（{n:kanji}）" @?= Right (MarkFormat "（" kanjiNotation "）")
            parseMarkFormat "*{n}" @?= Right defaultMarkFormat,
          testCase "wrong formats" $ do
            let bad t = assertBool (T.unpack t) (isLeft (parseMarkFormat t))
            mapM_ bad ["\\a{n}", "{n}\\", "{n", "{n}}", "{x}", "{n:x}", "注", "{n}{n}", "{{n}}", "{}"],
          testCase "the table of a format decides what slots it reads" $ do
            assertBool "{chapter} in a mark format" (isLeft (parseMarkFormat "{chapter}"))
            parseNumberFormatText "{chapter}-{n}" @?= Right [PNumber SlotChapter Nothing, PLit "-", PNumber SlotOwn Nothing]
            parseNumberFormatText "{chapter:upper-roman}" @?= Right [PNumber SlotChapter (Just upperRomanNotation)],
          testCase "doubled braces are read only where the format allows them, and are reported" $ do
            let table = \case
                  "n" -> Right (NumberSlot ())
                  "一" -> Right (SampleSlot () kanjiNotation)
                  name -> Left name
            parseFormat DoubledToo table "{{{n}}}" @?= Right ([PLit "{", PNumber () Nothing, PLit "}"], [LegacyBraces, LegacyBraces])
            parseFormat DoubledToo table "\\{{n}\\}" @?= Right ([PLit "{", PNumber () Nothing, PLit "}"], [])
            parseFormat DoubledToo table "{一}" @?= Right ([PNumber () (Just kanjiNotation)], [LegacySample "一" kanjiNotation])
            assertBool "{{ without doubled braces" (isLeft (parseFormat EscapesOnly table "{{n}}")),
          testCase "number formats" $ do
            formatNumber "第{n:kanji}章" [3] Nothing @?= "第三章"
            formatNumber "{1}.{2}" [3, 4] Nothing @?= "3.4"
            formatNumber "図{chapter}-{n}" [2] (Just 5) @?= "図5-2"
            formatNumber "{chapter:upper-roman}" [] (Just 4) @?= "IV"
            formatNumber "\\{{n}\\}" [7] Nothing @?= "{7}"
            renderMarkFormat (MarkFormat "{" kanjiNotation "）") @?= "\\{{n:kanji}）"
        ]
    ]
