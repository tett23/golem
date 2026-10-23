{- | The count of the tests a suite skipped (docs/adr ADR 0074).

tasty counts a SKIP as a test that passed, so a suite run where a tool is
missing ends as if every check had run. The tests count what they skip
here, by the reason, and the @main@ of each suite writes one line for
each reason to the standard error after tasty's results:

> 3 tests skipped: qpdf is not installed (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)
-}
module Golem.TestSupport.Skipped
  ( countSkipped,
    skippedSoFar,
    resetSkipped,
    skippedLines,
    reportSkipped,
    defaultMainReportingSkips,
  )
where

import Control.Exception (finally)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (sortOn)
import System.IO (hPutStrLn, stderr)
import System.IO.Unsafe (unsafePerformIO)
import Test.Tasty (TestTree, defaultMain)

-- | The counts so far, by the reason (the line after the count).
skipped :: IORef [(String, Int)]
skipped = unsafePerformIO (newIORef [])
{-# NOINLINE skipped #-}

{- | Counts one skip for the reason: the text of the line after the count,
such as @tests skipped: qpdf is not installed (…)@.
-}
countSkipped :: String -> IO ()
countSkipped reason = atomicModifyIORef' skipped (\cs -> (bump cs, ()))
  where
    bump = \case
      [] -> [(reason, 1)]
      (r, n) : rest
        | r == reason -> (r, n + 1) : rest
        | otherwise -> (r, n) : bump rest

-- | The counts so far, in the order of the reasons.
skippedSoFar :: IO [(String, Int)]
skippedSoFar = sortOn fst <$> readIORef skipped

-- | Forgets the counts (for the tests of this module).
resetSkipped :: IO ()
resetSkipped = atomicModifyIORef' skipped (const ([], ()))

-- | The lines of the counts: the count and the reason, in the order of the reasons.
skippedLines :: [(String, Int)] -> [String]
skippedLines cs = [show n <> " " <> reason | (reason, n) <- sortOn fst cs]

-- | Writes the lines of the counts to the standard error.
reportSkipped :: IO ()
reportSkipped = skippedSoFar >>= mapM_ (hPutStrLn stderr) . skippedLines

{- | 'defaultMain', and the lines of the counts after tasty's results.
tasty ends with an exit code, so the lines are written on the way out.
-}
defaultMainReportingSkips :: TestTree -> IO ()
defaultMainReportingSkips t = defaultMain t `finally` reportSkipped
