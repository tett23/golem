module Main (main) where

import Golem.TestSupport.Parallel (raceFactor)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import Golem.TestSupport.Watchdog (watchTests)
import ParallelSpec (parallelTests)

{- | The tests under the watchdog (docs/adr ADR 0117): a test that runs
for more than 300 seconds of wall-clock time for each repetition of
GOLEM_RACE_TESTS aborts the suite with its name, even when the runtime
itself is stuck. Alone, the slowest test takes about 9 seconds.
-}
main :: IO ()
main = raceFactor >>= \race -> defaultMainReportingSkips (const (watchTests (300 * toInteger race) (parallelTests race)))
