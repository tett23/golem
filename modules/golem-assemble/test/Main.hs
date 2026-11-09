module Main (main) where

import AssembleSpec qualified
import ListMarkersSpec qualified
import NumberingSpec qualified
import TableNumberSpec qualified
import Test.Tasty

main :: IO ()
main = defaultMain (testGroup "golem-assemble" [AssembleSpec.tests, ListMarkersSpec.tests, NumberingSpec.tests, TableNumberSpec.tests])
