module Main (main) where

import Golem.TestSupport.Parallel (raceFactor)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import ParallelSpec (parallelTests)

main :: IO ()
main = raceFactor >>= defaultMainReportingSkips . const . parallelTests
