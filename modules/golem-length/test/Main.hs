module Main (main) where

import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import LengthSpec qualified
import Test.Tasty

main :: IO ()
main = enterPackageDirectory >> defaultMain LengthSpec.tests
