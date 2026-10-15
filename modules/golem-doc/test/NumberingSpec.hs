-- | numberSeparator (golem-html ADR 0002).
module NumberingSpec (tests) where

import Golem.Doc.Numbering
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "number separators (golem-html ADR 0002)"
    [ testCase "an ideographic space in a Japanese book" $ do
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
