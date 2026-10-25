{- | The count of the tests a suite skipped (docs/adr ADR 0074).

tasty counts a SKIP as a test that passed, so a suite run where a tool is
missing ends as if every check had run. The tests count what they skip
in a 'Skips', by the reason, and the @main@ of each suite writes one line
for each reason to the standard error after tasty's results:

> 3 tests skipped: qpdf is not installed (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)

'defaultMainReportingSkips' makes the 'Skips' of a run and passes it to
the function that builds the tests. It also sets it as the tasty option
'SkipCounter' of the tree, through which the tests of
"Golem.TestSupport.ExternalTool" count themselves.
-}
module Golem.TestSupport.Skipped
  ( Skips,
    newSkips,
    countSkipped,
    skippedSoFar,
    skippedLines,
    SkipCounter (..),
    defaultMainReportingSkips,
  )
where

import Control.Applicative (empty)
import Control.Exception (finally)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (sortOn)
import System.IO (hPutStrLn, stderr)
import Test.Tasty (TestTree, defaultMain, localOption)
import Test.Tasty.Options (IsOption (..))

-- | The counts of one run, by the reason (the line after the count).
newtype Skips = Skips (IORef [(String, Int)])

-- | No counts yet.
newSkips :: IO Skips
newSkips = Skips <$> newIORef []

{- | Counts one skip for the reason: the text of the line after the count,
such as @tests skipped: qpdf is not installed (…)@.
-}
countSkipped :: Skips -> String -> IO ()
countSkipped (Skips ref) reason = atomicModifyIORef' ref (\cs -> (bump cs, ()))
  where
    bump = \case
      [] -> [(reason, 1)]
      (r, n) : rest
        | r == reason -> (r, n + 1) : rest
        | otherwise -> (r, n) : bump rest

-- | The counts so far, in the order of the reasons.
skippedSoFar :: Skips -> IO [(String, Int)]
skippedSoFar (Skips ref) = sortOn fst <$> readIORef ref

-- | The lines of the counts: the count and the reason, in the order of the reasons.
skippedLines :: [(String, Int)] -> [String]
skippedLines cs = [show n <> " " <> reason | (reason, n) <- sortOn fst cs]

-- | Writes the lines of the counts to the standard error.
reportSkipped :: Skips -> IO ()
reportSkipped s = skippedSoFar s >>= mapM_ (hPutStrLn stderr) . skippedLines

{- | The tasty option that carries the 'Skips' of a run to the tests that
count themselves. It is set by 'defaultMainReportingSkips' and is not
read from the command line; without it nothing is counted.
-}
newtype SkipCounter = SkipCounter (Maybe Skips)

instance IsOption SkipCounter where
  defaultValue = SkipCounter Nothing
  parseValue = const Nothing
  optionName = pure "skip-counter"
  optionHelp = pure "the counts of the tests skipped (set by the suite, not on the command line)"
  optionCLParser = empty

{- | 'defaultMain' of the tests built with the 'Skips' of the run, and the
lines of the counts after tasty's results. tasty ends with an exit code,
so the lines are written on the way out.
-}
defaultMainReportingSkips :: (Skips -> TestTree) -> IO ()
defaultMainReportingSkips mk = do
  s <- newSkips
  defaultMain (localOption (SkipCounter (Just s)) (mk s)) `finally` reportSkipped s
