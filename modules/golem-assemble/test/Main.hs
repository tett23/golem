module Main (main) where

import AssembleSpec qualified
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import IndexSpec qualified
import ListMarkersSpec qualified
import NumberingSpec qualified
import TableNumberSpec qualified
import Test.Tasty

main :: IO ()
main = enterPackageDirectory >> defaultMain (testGroup "golem-assemble" [AssembleSpec.tests, IndexSpec.tests, ListMarkersSpec.tests, NumberingSpec.tests, TableNumberSpec.tests])
