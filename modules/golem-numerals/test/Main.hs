module Main (main) where

import Golem.Numerals (kanji)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

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
        ]
    ]
