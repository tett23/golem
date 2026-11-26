module Main (main) where

import FlattenSpec qualified
import PathDataSpec qualified
import ReachSpec qualified
import RegionSpec qualified
import Test.Tasty

main :: IO ()
main =
  defaultMain
    ( testGroup
        "golem-geometry (root ADR 0437)"
        [RegionSpec.tests, FlattenSpec.tests, PathDataSpec.tests, ReachSpec.tests]
    )
