module Main (main) where

import PackageSpec (packageTests)
import Test.Tasty

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "golem-epub"
    [ packageTests
    ]
