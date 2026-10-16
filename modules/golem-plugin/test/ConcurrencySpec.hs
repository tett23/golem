{- | One loaded plugin called from many OS threads at once (Medium tests).

A plugin is compiled once and every call gets a fresh instance with its
own fuel and memory (ADR 0001), so calls on several capabilities must
not see each other: each answers for its own input, and running out of
fuel in one call does not affect the others. The calls are pinned to
eight capabilities (the suite is built with -threaded); every call has
its own input, so that no two calls can be shared as one thunk.
-}
module ConcurrencySpec (concurrencyTests) where

import Control.Concurrent (forkOn, getNumCapabilities, setNumCapabilities)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception (SomeException, evaluate, try)
import Data.ByteString (ByteString)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.IR
import Golem.Plugin
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

capabilities :: Int
capabilities = 8

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

{- | Runs with at least n capabilities. The count is only raised, never
restored: tasty may run other tests at the same time, and lowering it
under them would take their capabilities away.
-}
withCapabilities :: Int -> IO a -> IO a
withCapabilities n act = do
  current <- getNumCapabilities
  setNumCapabilities (max n current)
  act

loadWat :: FilePath -> IO Plugin
loadWat name = do
  src <- TIO.readFile ("test/plugins/" <> name)
  wasm <- either (assertFailure . T.unpack) pure (watToWasm src)
  either (assertFailure . show) pure (loadPluginWith 200000 defaultMemoryLimit wasm)

-- | A one-paragraph document whose text is the number.
numbered :: Int -> Document
numbered i = Document (FileId 1) [Block (mkSpan (FileId 1) 0 1) Nothing (Paragraph Nothing [Text (mkSpan (FileId 1) 0 1) (T.pack (show i))])]

-- | Whether a call ran out of fuel.
outOfFuel :: Either PluginError ByteString -> Bool
outOfFuel = \case
  Left (OutOfFuel _) -> True
  _ -> False

concurrencyTests :: TestTree
concurrencyTests =
  testGroup
    "one plugin from many threads (Medium)"
    [ testCase "64 filter calls on eight capabilities each return their own document" $ do
        p <- loadWat "identity.wat"
        let docs = map numbered [1 .. 64]
        results <- withCapabilities capabilities (inParallel [pure (fst <$> applyFilter p "same" d) | d <- docs])
        results @?= map (Right . Right) docs,
      testCase "calls that run out of fuel beside calls that finish do not change either" $ do
        identity <- loadWat "identity.wat"
        loop <- loadWat "loop.wat"
        let calls = concat [[Left i, Right i] | i <- [1 .. 16 :: Int]]
            run = \case
              Left i -> Left (outOfFuel (invokeRaw loop (TE.encodeUtf8 (T.pack (show i)))))
              Right i -> Right (fst <$> applyFilter identity "same" (numbered i))
        results <- withCapabilities capabilities (inParallel [pure (run c) | c <- calls])
        results @?= concat [[Right (Left True), Right (Right (Right (numbered i)))] | i <- [1 .. 16]]
    ]
