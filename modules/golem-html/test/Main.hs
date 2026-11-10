module Main (main) where

import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Test.Tasty
import XhtmlSpec (xhtmlTests)

main :: IO ()
main = enterPackageDirectory >> defaultMain tests

tests :: TestTree
tests =
  testGroup
    "golem-html"
    [ xhtmlTests
    ]
