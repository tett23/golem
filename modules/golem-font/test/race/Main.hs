{- | FreeType's face of one 'Font' from many OS threads (a Medium test).

FreeType loads a glyph into the one glyph slot of its face, so two
threads asking for metrics at once used to read each other's glyph or
crash the process. 'glyphMetrics' and 'glyphCid' look pure (ADR 0001),
so Golem may evaluate them on any capability; the font takes a lock
around FreeType. This is a test executable of its own: before the lock,
the race killed the process, and a crash here fails this suite alone.
-}
module Main (main) where

import Control.Concurrent (forkOn, getNumCapabilities, setNumCapabilities)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception (SomeException, evaluate, try)
import Data.ByteString qualified as BS
import Golem.Font
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = do
  noto <- BS.readFile "../golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" >>= loadFont >>= either (fail . show) pure
  defaultMain (raceTests noto)

-- | The number of threads and of capabilities.
threads :: Int
threads = 8

{- | Runs the actions at once, the i-th pinned to capability i (mod the
count), and returns their fully evaluated results in the order given.
The threads wait at a gate until all are started, so that they begin
together.
-}
inParallel :: (Show a) => [IO a] -> IO [Either String a]
inParallel acts = do
  current <- getNumCapabilities
  setNumCapabilities (max threads current)
  gate <- newEmptyMVar
  vars <- traverse (start gate) (zip [0 ..] acts)
  putMVar gate ()
  traverse takeMVar vars
  where
    start gate (i, act) = do
      v <- newEmptyMVar
      _ <- forkOn i (readMVar gate >> try (act >>= \x -> evaluate (length (show x)) >> pure x) >>= putMVar v . either (\e -> Left (show (e :: SomeException))) Right)
      pure v

-- | 2000 glyph ids from k: each thread asks for its own range, so that no two threads share a thunk.
glyphsFrom :: Int -> [Int]
glyphsFrom k = [k .. k + 1999]

raceTests :: Font -> TestTree
raceTests noto =
  testGroup
    "FreeType from many threads (golem-font ADR 0001; Medium)"
    [ testCase "glyph metrics asked from eight threads at once are those asked in sequence" $ do
        let alone = [map (glyphMetrics noto) (glyphsFrom k) | k <- [1 .. threads]]
        _ <- evaluate (length (show alone))
        together <- inParallel [pure (concat (replicate 10 (map (glyphMetrics noto) (glyphsFrom k)))) | k <- [1 .. threads]]
        together @?= [Right (concat (replicate 10 a)) | a <- alone],
      testCase "CIDs and metrics asked together from eight threads are those asked in sequence" $ do
        let ask k = [(glyphCid noto g, glyphMetrics noto g) | g <- glyphsFrom k]
            alone = map ask [1 .. threads]
        _ <- evaluate (length (show alone))
        together <- inParallel [pure (ask k) | k <- [1 .. threads]]
        together @?= map Right alone
    ]
