module Main (main) where

import ConformanceSpec qualified
import CountsSpec qualified
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import SegmentSpec qualified
import Test.Tasty

main :: IO ()
main =
  enterPackageDirectory
    >> defaultMain
      ( testGroup
          "golem-unicode (docs/adr ADR 0411)"
          [ConformanceSpec.tests, SegmentSpec.tests, CountsSpec.tests]
      )
