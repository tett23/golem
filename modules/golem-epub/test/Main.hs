module Main (main) where

import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import PackageSpec (packageTests)
import Test.Tasty

main :: IO ()
main = enterPackageDirectory >> defaultMain tests

tests :: TestTree
tests =
  testGroup
    "golem-epub"
    [ packageTests
    ]
