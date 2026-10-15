module Main (main) where

import Test.Tasty
import XhtmlSpec (xhtmlTests)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "golem-html"
    [ xhtmlTests
    ]
