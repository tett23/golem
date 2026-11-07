{- | E1 of docs/adr/0208 on one and on four processors: 'checkAllPar'
and 'tallyAllPar' return what 'checkAll' and 'tallyAll' return.

The tests run this program again with @+RTS -N1@ and @+RTS -N4@ and
GOLEM_ENUM_PAR_CHILD set; such a run checks every case of
"EnumParCases" and a tier of many values, prints its number of
capabilities and the cases that differ, and exits with 1 when one does.
It does not start tasty, which raises the number of capabilities of a
program that has fewer than the processors.
-}
module Main (main) where

import Control.Monad (unless)
import Data.Monoid (Sum (..))
import EnumParCases (Case (..), parCases)
import GHC.Conc (getNumCapabilities)
import Golem.TestSupport.Enum
import System.Environment (getExecutablePath, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

main :: IO ()
main = lookupEnv "GOLEM_ENUM_PAR_CHILD" >>= maybe tests (const child)

-- | A tier of 40,000 values, each of some work, broken near its end.
many :: Case
many =
  Case
    "40,000 values"
    (Tiers [[(0, 0)], [(1, i) | i <- [0 .. 39999]]])
    (\(_, i) -> [Violation "late" (show i) | work i `mod` 9973 == 17, i > 30000])
  where
    work i = foldr (\k a -> (a * 31 + k) `mod` 1000003) i [1 .. 200 :: Int]

-- | The cases that differ.
differing :: [String]
differing =
  [ caseName c <> " up to " <> show n
  | c <- parCases,
    n <- [0 .. 6],
    checkAllPar n (caseTiers c) (caseCheck c) /= checkAll n (caseTiers c) (caseCheck c)
      || tallyAllPar n (caseTiers c) (listed c) /= tallyAll n (caseTiers c) (listed c)
  ]
    <> [ caseName many
       | checkAllPar 1 (caseTiers many) (caseCheck many) /= checkAll 1 (caseTiers many) (caseCheck many)
           || tallyAllPar 1 (caseTiers many) (summed many) /= tallyAll 1 (caseTiers many) (summed many)
       ]
  where
    -- the values checked, in order
    listed c x = (caseCheck c x, [x])
    -- the number of values checked and the sum of their indices
    summed c x@(_, i) = (caseCheck c x, (Sum (1 :: Int), Sum i))

child :: IO ()
child = do
  caps <- getNumCapabilities
  putStrLn ("capabilities " <> show caps)
  mapM_ putStrLn differing
  unless (null differing) (exitWith (ExitFailure 1))

-- | Runs this program with the number of capabilities given: its exit code and output.
runWith :: Int -> IO (ExitCode, String)
runWith n = do
  self <- getExecutablePath
  (code, out, err) <- readCreateProcessWithExitCode (proc self ["+RTS", "-N" <> show n, "-RTS"]) {env = Just [("GOLEM_ENUM_PAR_CHILD", "1")]} ""
  pure (code, out <> err)

tests :: IO ()
tests =
  defaultMain $
    testGroup
      "checkAllPar (docs/adr/0208)"
      [ testCase ("E1: checkAllPar and tallyAllPar return what checkAll and tallyAll return, on " <> show n <> " processors") $ do
          (code, out) <- runWith n
          take 1 (lines out) @?= ["capabilities " <> show n]
          assertBool out (code == ExitSuccess)
      | n <- [1, 4]
      ]
