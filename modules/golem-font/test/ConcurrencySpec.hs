{- | One 'Font' used from many OS threads at once (Medium tests).

Golem composes paragraphs with 'Control.Concurrent.Async.mapConcurrently'
(golem-driver ADR 0002), and every paragraph shapes with the same loaded
fonts, so the pure functions of "Golem.Font" are evaluated on several
capabilities at once. The tests run on every processor (the suite is
built with -threaded and -N) and compare each concurrent result with the same
call made alone: the specification (docs/adr/0002 determinism) is that the
parallel result equals the sequential one.

GOLEM_RACE_TESTS=n multiplies the number of the tests of the property by
n (1 by default); the nightly race.yml sets 40 (docs/adr/0075).
-}
module ConcurrencySpec (concurrencyTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Font
import Golem.TestSupport.Parallel (inParallel)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

-- | Japanese and Latin text from the characters the fixture fonts have.
genText :: Gen Text
genText = Gen.text (Range.linear 1 40) (Gen.element ("日本語の組版、。「」ー漁夫はofficeAVA Typography1234" :: String))

concurrencyTests :: Int -> Font -> Font -> TestTree
concurrencyTests race han noto =
  testGroup
    "one font from many threads (Medium)"
    [ testPropertyNamed
        "shaping one font from every capability gives the glyphs shaping alone gives"
        "prop_concurrentShapingMatchesSequential"
        ( withTests (fromIntegral (30 * race)) . property $ do
            runs <- forAll (Gen.list (Range.linear 16 64) ((,) <$> genText <*> Gen.element [Horizontal, Vertical]))
            let request (t, d) = (shapeRequest 1000 t) {srDirection = d, srFeatures = ["palt"]}
                alone = map (Right . shapeUnits noto . request) runs
            together <- evalIO (inParallel [pure (shapeUnits noto (request r)) | r <- runs])
            together === alone
        ),
      testCase "subsetting one font from every capability gives the bytes subsetting alone gives" $ do
        let glyphSets = [[g | (g, _, _) <- shapeUnits han (shapeRequest 1000 (T.take n "「日本語の組版」、ー。"))] | n <- [1 .. 11]]
        alone <- mapM (subsetFont han) glyphSets
        together <- inParallel [subsetFont han gs | gs <- glyphSets]
        together @?= map Right alone,
      testCase "vertical origins from every capability are those asked alone" $ do
        let gids = concat (replicate 8 [1 .. 500])
            alone = map (Right . glyphVerticalOrigin noto) gids
        together <- inParallel [pure (glyphVerticalOrigin noto g) | g <- gids]
        together @?= alone
    ]
