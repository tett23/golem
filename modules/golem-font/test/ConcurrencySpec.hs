{- | One 'Font' used from many OS threads at once (Medium tests).

Golem composes paragraphs with 'Control.Concurrent.Async.mapConcurrently'
(golem-driver ADR 0002), and every paragraph shapes with the same loaded
fonts, so the pure functions of "Golem.Font" are evaluated on several
capabilities at once. The tests run on eight capabilities (the suite is
built with -threaded) and compare each concurrent result with the same
call made alone: the specification (docs/adr/0002 determinism) is that the
parallel result equals the sequential one.
-}
module ConcurrencySpec (concurrencyTests) where

import Control.Concurrent (forkOn, getNumCapabilities, setNumCapabilities)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception (SomeException, evaluate, try)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Font
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

-- | The number of capabilities the tests run on.
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

-- | Japanese and Latin text from the characters the fixture fonts have.
genText :: Gen Text
genText = Gen.text (Range.linear 1 40) (Gen.element ("日本語の組版、。「」ー漁夫はofficeAVA Typography1234" :: String))

concurrencyTests :: Font -> Font -> TestTree
concurrencyTests han noto =
  testGroup
    "one font from many threads (Medium)"
    [ testPropertyNamed
        "shaping one font from eight capabilities gives the glyphs shaping alone gives"
        "prop_concurrentShapingMatchesSequential"
        ( withTests 30 . property $ do
            runs <- forAll (Gen.list (Range.linear 16 64) ((,) <$> genText <*> Gen.element [Horizontal, Vertical]))
            let request (t, d) = (shapeRequest 1000 t) {srDirection = d, srFeatures = ["palt"]}
                alone = map (Right . shapeUnits noto . request) runs
            together <- evalIO (withCapabilities capabilities (inParallel [pure (shapeUnits noto (request r)) | r <- runs]))
            together === alone
        ),
      testCase "subsetting one font from eight capabilities gives the bytes subsetting alone gives" $ do
        let glyphSets = [[g | (g, _, _) <- shapeUnits han (shapeRequest 1000 (T.take n "「日本語の組版」、ー。"))] | n <- [1 .. 11]]
        alone <- mapM (subsetFont han) glyphSets
        together <- withCapabilities capabilities (inParallel [subsetFont han gs | gs <- glyphSets])
        together @?= map Right alone,
      testCase "vertical origins from eight capabilities are those asked alone" $ do
        let gids = concat (replicate 8 [1 .. 500])
            alone = map (Right . glyphVerticalOrigin noto) gids
        together <- withCapabilities capabilities (inParallel [pure (glyphVerticalOrigin noto g) | g <- gids])
        together @?= alone
    ]
