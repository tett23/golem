module Main (main) where

import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import ParallelSpec (parallelTests, raceFactor)

main :: IO ()
main = raceFactor >>= defaultMainReportingSkips . parallelTests
