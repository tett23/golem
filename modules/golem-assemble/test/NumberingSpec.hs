-- | numberSeparator (golem-html ADR 0002).
module NumberingSpec (tests) where

import Data.Text qualified as T
import Golem.Assemble.Numbering
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "number separators (golem-html ADR 0002)"
    [ testCase "inv1_number_title_separator_property" $
        mapM_ (\(lang, conf, n, title) -> titleSeparator lang conf n title @?= "") [(lang, conf, n, t) | lang <- ["ja", "en"], conf <- [Nothing, Just "", Just "::"], (n, t) <- [("", "title"), ("1", ""), ("", "")]],
      testCase "inv1_number_title_separator_case_1" $ titleSeparator "ja" (Just "") "1" "題" @?= "",
      testCase "inv1_number_title_separator_case_2" $ titleSeparator "ja" (Just "|") "" "題" @?= "",
      testCase "inv1_number_title_separator_case_3" $ titleSeparator "ja" (Just " | ") "1" "題" @?= " | ",
      testCase "J1: number separator uses the primary language subtag" $ do
        let cases = [("", False), ("j", False), ("ja", True), ("JA", True), ("ja-JP", True), ("ja-", True), ("jam", False), ("ja_JP", False), ("en", False), ("en-ja", False)]
        mapM_ (\(lang, expected) -> (numberSeparator lang "1" == "\x3000") @?= expected) cases,
      testCase "J2: number separator ignores case" $ do
        let cases = [("", False), ("j", False), ("ja", True), ("JA", True), ("ja-JP", True), ("ja-", True), ("jam", False), ("ja_JP", False), ("en", False), ("en-ja", False)]
        mapM_ (\(lang, _) -> numberSeparator lang "1" @?= numberSeparator (T.toUpper lang) "1") cases,
      testCase "an ideographic space in a Japanese book" $ do
        numberSeparator "ja" "第3章" @?= "\x3000"
        numberSeparator "ja-JP" "1.2" @?= "\x3000"
        numberSeparator "JA" "1" @?= "\x3000",
      testCase "a space in a book of any other language" $ do
        numberSeparator "en" "1" @?= " "
        numberSeparator "EN-us" "1" @?= " "
        numberSeparator "zh" "1" @?= " "
        numberSeparator "jav" "1" @?= " ",
      testCase "nothing after a number that ends with a space" $ do
        numberSeparator "en" "Chapter 1: " @?= ""
        numberSeparator "ja" "第1章\x3000" @?= ""
        numberSeparator "ja" "1\t" @?= ""
    ]
