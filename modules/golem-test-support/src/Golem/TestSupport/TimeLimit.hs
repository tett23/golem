{- | Time limits of tests that stop a test that does not end (docs/adr
ADR 0091).

A test of golem-pdf or golem-svg runs inside @'withinTimeLimits'
'hangLimits'@. Two limits stop it: the CPU time of the process, for a
test that computes without end, and the wall-clock time, for a test that
waits without end. The CPU time does not grow when other processes take
the processor, as the wall-clock time does, so a busy machine does not
fail a test that ends. Being within the limits does not mean that a test
is fast: the limits only detect a test that does not end (docs/adr ADR
0073).

The CPU time is that of the process, so the tests must run one at a
time: 'withinTimeLimits' fails on the threaded RTS, where tasty runs them
in parallel.
-}
module Golem.TestSupport.TimeLimit
  ( TimeLimits (..),
    hangLimits,
    withinTimeLimits,
    CpuTimeExceeded (..),
    WallTimeExceeded (..),
  )
where

import Control.Concurrent (forkIO, killThread, myThreadId, rtsSupportsBoundThreads, threadDelay, throwTo)
import Control.Exception (Exception, bracket, uninterruptibleMask_)
import GHC.Clock (getMonotonicTime)
import System.CPUTime (getCPUTime)

-- | The limits: seconds of the CPU time of the process, and of the wall-clock time.
data TimeLimits = TimeLimits
  { cpuSeconds :: Integer,
    wallSeconds :: Integer
  }
  deriving stock (Eq, Show)

{- | The limits of the tests of golem-pdf and golem-svg: 60 seconds of CPU
time and 300 seconds of wall-clock time. A test under them takes at most
10 seconds of CPU time alone.
-}
hangLimits :: TimeLimits
hangLimits = TimeLimits {cpuSeconds = 60, wallSeconds = 300}

-- | The action used more than its seconds of CPU time.
newtype CpuTimeExceeded = CpuTimeExceeded Integer
  deriving stock (Eq)

instance Show CpuTimeExceeded where
  show (CpuTimeExceeded n) = "used more than " <> show n <> " seconds of CPU time"

instance Exception CpuTimeExceeded

-- | The action took more than its seconds of wall-clock time.
newtype WallTimeExceeded = WallTimeExceeded Integer
  deriving stock (Eq)

instance Show WallTimeExceeded where
  show (WallTimeExceeded n) = "took more than " <> show n <> " seconds of wall-clock time"

instance Exception WallTimeExceeded

{- | Runs an action, and throws 'CpuTimeExceeded' or 'WallTimeExceeded' to
it when it goes over a limit. A thread reads the two clocks every 0.1
second, from the start of the action; it stops when the action ends,
by a value or by an exception. The value of the action is returned as
it is.

A loop that does not allocate is not stopped: the thread of the action
takes the exception only where it allocates.
-}
withinTimeLimits :: TimeLimits -> IO a -> IO a
withinTimeLimits limits act
  | rtsSupportsBoundThreads =
      ioError (userError "withinTimeLimits: the threaded RTS runs tests in parallel, and the CPU time of the process is not that of one test")
  | otherwise = do
      cpu0 <- getCPUTime
      wall0 <- getMonotonicTime
      me <- myThreadId
      let watch = do
            threadDelay 100000
            cpu <- getCPUTime
            wall <- getMonotonicTime
            case () of
              _
                | cpu - cpu0 > cpuSeconds limits * 1000000000000 -> throwTo me (CpuTimeExceeded (cpuSeconds limits))
                | wall - wall0 > fromInteger (wallSeconds limits) -> throwTo me (WallTimeExceeded (wallSeconds limits))
                | otherwise -> watch
      bracket (forkIO watch) (uninterruptibleMask_ . killThread) (const act)
