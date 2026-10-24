{- | Parallel composition on several OS threads (Medium tests).

The PDF pipeline composes paragraphs, figure captions and tables with
'Control.Concurrent.Async.mapConcurrently' when 'optParallel' is set
(golem-driver ADR 0001 and 0002). The tests of golem-driver-test compare
parallel and sequential builds on one capability, where the green threads
never run at the same time and the foreign calls into HarfBuzz and
FreeType never overlap. This suite is built with -threaded and -N (one
capability per processor), so that the threads really run at once;
its tests check what ADR 0001 requires of parallel runs: the output and the
diagnostics equal those of a sequential run (docs/adr/0002 determinism),
and the diagnostics are in the order of the files, the positions and the
codes.

GOLEM_RACE_TESTS=n multiplies the number of the tests of each property
by n and builds the fixture books in parallel n times (1 by default); the
pull requests run with 1, the nightly race.yml with 40 (docs/adr/0075).
-}
module ParallelSpec (parallelTests) where

import Control.Monad (forM_, replicateM)
import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.Pdf (Shaping (..))
import Golem.Syntax
import Golem.TestSupport.Parallel (inParallel)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Support
import System.FilePath (takeFileName, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testPropertyNamed)

-- | What a build left: each diagnostic as (file path, code, start, message), and the PDF.
type Outcome = ([(FilePath, DiagnosticCode, Int, Text)], Maybe BS.ByteString)

{- | Builds a project of chapters, in the order given, to PDF. The style is
written with its files; the fake body font is added when the style names
no font.
-}
buildChapters :: FontProvider -> Bool -> BS.ByteString -> [(FilePath, BS.ByteString)] -> [(FilePath, Text)] -> IO Outcome
buildChapters fonts parallel style files chapters = withSystemTempDirectory "golem-parallel" $ \tmp -> do
  let names = T.intercalate ", " [T.pack (show name) | (name, _) <- chapters]
  TIO.writeFile (tmp </> "manifest.toml") ("chapters = [" <> names <> "]\n" <> T.dropWhile (/= '\n') (TE.decodeUtf8 miniManifest))
  writeStyleWithFont tmp style
  writeFiles tmp files
  forM_ chapters $ \(name, src) -> TIO.writeFile (tmp </> name) src
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fonts, optParallel = parallel}
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  let path d = maybe "?" (takeFileName . siPath) (Map.lookup (spanFile (diagSpan d)) (brSources r))
  pure ([(path d, diagCode d, spanStart (diagSpan d), diagMessage d) | d <- brDiagnostics r], pdf)

-- | The same build in sequence, then in parallel on every capability.
sequentialAndParallel :: FontProvider -> BS.ByteString -> [(FilePath, BS.ByteString)] -> [(FilePath, Text)] -> IO (Outcome, Outcome)
sequentialAndParallel fonts style files chapters = do
  s <- buildChapters fonts False style files chapters
  p <- buildChapters fonts True style files chapters
  pure (s, p)

-- * generated manuscripts

-- | Japanese prose with punctuation, brackets and a few Latin letters.
genProse :: Gen Text
genProse = Gen.text (Range.linear 1 160) (Gen.element ("吾輩は猫である。名前はまだ無い、どこで生れたかとんと見当がつかぬ。「何でも薄暗い」——じめじめした所でニャーニャー泣いていた事だけは記憶しているAB12" :: String))

-- | One block: a paragraph (most often), a heading, a list or a small table.
genBlock :: Gen Text
genBlock =
  Gen.frequency
    [ (6, genProse),
      (1, ("# " <>) <$> Gen.text (Range.linear 1 8) (Gen.element ("見出しの章節" :: String))),
      (1, T.unlines . map ("- " <>) <$> Gen.list (Range.linear 1 4) genProse),
      (1, pure "| 項目 | 値 |\n|:---|---:|\n| 幅 | 10 |\n| 高さ | 20 |\n")
    ]

genChapter :: Gen Text
genChapter = T.intercalate "\n\n" <$> Gen.list (Range.linear 1 12) genBlock

-- | Chapters of different sizes, named c1.gm.., listed in a shuffled order.
genChapters :: Gen [(FilePath, Text)]
genChapters = do
  bodies <- Gen.list (Range.linear 1 5) genChapter
  Gen.shuffle [("c" <> show i <> ".gm", b) | (i, b) <- zip [1 :: Int ..] bodies]

-- | Noto Serif JP of the 蟹工船 fixture as the body font, set horizontally or vertically.
notoStyle :: Bool -> BS.ByteString
notoStyle vertical =
  (if vertical then replaceIn "writing-mode = \"horizontal\"" "writing-mode = \"vertical\"" horizontalStyle else horizontalStyle)
    <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\n"

-- * the tests

-- | The tests, the repetitions multiplied by the factor of 'raceFactor'.
parallelTests :: Int -> TestTree
parallelTests race =
  testGroup
    "parallel composition on every capability (golem-driver ADR 0001, 0002; Medium)"
    [ testPropertyNamed
        "a generated manuscript with the fake fonts gives the bytes and diagnostics of a sequential build"
        "prop_parallelFakeFontsMatchSequential"
        ( withTests (fromIntegral (25 * race)) . property $ do
            chapters <- forAll genChapters
            (s, p) <- evalIO (sequentialAndParallel fakeProvider horizontalStyle [] chapters)
            p === s
        ),
      testPropertyNamed
        "a generated manuscript shaped by HarfBuzz gives the bytes and diagnostics of a sequential build"
        "prop_parallelRealFontsMatchSequential"
        ( withTests (fromIntegral (8 * race)) . property $ do
            chapters <- forAll genChapters
            vertical <- forAll Gen.bool
            noto <- evalIO notoBytes
            (s, p) <- evalIO (sequentialAndParallel realProvider (notoStyle vertical) [("fonts/noto.otf", noto)] chapters)
            p === s
        ),
      testCase "layout errors of three chapters come in the order of the codes, the manifest and the positions" $ do
        let wide = "| " <> T.intercalate " | " (replicate 13 "字") <> " |\n|" <> T.replicate 13 "---|" <> "\n| " <> T.intercalate " | " (replicate 13 "字") <> " |\n"
            -- the bullet • and its gap take two characters a level (golem-driver ADR 0044):
            -- the items 三, 四 and 五 leave less than 8 characters of 12 (G07027); the passes
            -- that find them and the table errors are not the order of the files
            deep = "- 一\n  - 二\n    - 三\n      - 四\n        - 五の項目。\n"
            chapters = [("z.gm", wide), ("a.gm", "前。\n\n" <> wide), ("m.gm", deep <> "\n" <> wide <> "\n" <> wide)]
        (ds, pdf) <- buildChapters fakeProvider True horizontalStyle [] chapters
        -- byte offsets: "前。" is 6 bytes and two newlines; the items of deep are 6, 8, 10
        -- and 12 bytes before "四", 62 bytes in all, then a newline; a table is 214 bytes
        -- (two rows of 80 and a rule of 54), then a newline
        (pdf, [(f, c, at) | (f, c, at, _) <- ds])
          @?= ( Nothing,
                [ ("m.gm", DiagnosticCode "G07027", 14),
                  ("m.gm", DiagnosticCode "G07027", 24),
                  ("m.gm", DiagnosticCode "G07027", 36),
                  ("z.gm", DiagnosticCode "G07041", 0),
                  ("a.gm", DiagnosticCode "G07041", 8),
                  ("m.gm", DiagnosticCode "G07041", 63),
                  ("m.gm", DiagnosticCode "G07041", 278)
                ]
              ),
      testPropertyNamed
        "advances and pair kerns asked from every capability at once are those asked in sequence"
        "prop_memoConcurrentMatchesSequential"
        ( withTests (fromIntegral (10 * race)) . property $ do
            pairs <- forAll (Gen.list (Range.linear 32 128) ((,,) <$> Gen.bool <*> Gen.element ("漢字「」、。ーabAV1" :: String) <*> Gen.element ("漢字「」、。ーabAV1" :: String)))
            -- two loads: the sequential answers must not warm the cache the threads use
            alone <- evalIO notoFonts
            shared <- evalIO notoFonts
            let ask fonts (v, a, b) = (lfAdvance fonts (Shaping "body" v []) a, lfPairKern fonts (Shaping "body" v []) a b)
            together <- evalIO (inParallel [pure (ask shared k) | k <- pairs])
            together === map (Right . ask alone) pairs
        ),
      testGroup "fixture books" [bookTest race "tempest", bookTest race "kanikosen"]
    ]

{- | A fixture book built in parallel on every capability gives the PDF of
a sequential build, n times (the factor of GOLEM_RACE_TESTS).
-}
bookTest :: Int -> FilePath -> TestTree
bookTest n name = testCase (name <> ": parallel builds on every capability give the bytes of a sequential build") $ do
  sequential <- buildBookWith False name
  parallel <- replicateM n (buildBookWith True name)
  map (== sequential) parallel @?= replicate n True

-- | Builds a copy of a book fixture to PDF; no errors allowed.
buildBookWith :: Bool -> FilePath -> IO BS.ByteString
buildBookWith parallel name = withSystemTempDirectory "golem-book" $ \tmp -> do
  copyTree ("test/fixtures" </> name) tmp
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optParallel = parallel}
  assertEqual "no errors" [] [(diagCode d, diagMessage d) | d <- brDiagnostics r, isError d]
  case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> BS.readFile p
    other -> assertFailure (show other)
