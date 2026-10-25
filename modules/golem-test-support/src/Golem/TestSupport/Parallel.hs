{- | Helpers of the tests that run actions on several capabilities at once
(golem-driver ADR 0001, golem-plugin ADR 0001) and of the race tests
(docs/adr ADR 0075).
-}
module Golem.TestSupport.Parallel
  ( inParallel,
    raceFactor,
    raceFactorBy,
  )
where

import Control.Concurrent (forkOn)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception (SomeException, evaluate, try)
import Data.Char (isDigit)
import System.Environment (lookupEnv)

{- | Runs the actions at once, the i-th pinned to capability i (mod the
count), and returns their fully evaluated results in the order given.
The threads wait at a gate until all are started, so that they begin
together.
-}
inParallel :: (Show a) => [IO a] -> IO [Either String a]
inParallel acts = do
  gate <- newEmptyMVar
  vars <- traverse (start gate) (zip [0 ..] acts)
  putMVar gate ()
  traverse takeMVar vars
  where
    start gate (i, act) = do
      v <- newEmptyMVar
      _ <- forkOn i (readMVar gate >> try (act >>= \x -> evaluate (length (show x)) >> pure x) >>= putMVar v . either (\e -> Left (show (e :: SomeException))) Right)
      pure v

{- | GOLEM_RACE_TESTS, the factor of the repetitions of the race tests
(docs/adr/0075): 1 when it is not set. A value that is not an integer of
1 or more fails the suite: it is not read as 1.
-}
raceFactor :: IO Int
raceFactor = lookupEnv "GOLEM_RACE_TESTS" >>= either fail pure . raceFactorBy

{- | The factor of a value of GOLEM_RACE_TESTS: 1 when it is not set, the
value when it is an integer of 1 or more (at most six digits), and else
the message of the failure.
-}
raceFactorBy :: Maybe String -> Either String Int
raceFactorBy = maybe (Right 1) parse
  where
    parse s
      | not (null s), all isDigit s, take 1 s /= "0", length s <= 6 = Right (read s)
      | otherwise = Left ("GOLEM_RACE_TESTS must be an integer of 1 or more, not " <> show s)
