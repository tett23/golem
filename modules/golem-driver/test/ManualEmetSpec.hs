{- | The .emet of the user manual: the functions it calls (manual/functions/)
and the mistakes its introduction to Emet shows (manual/examples/emet/).

The manual builds without a single diagnostic in CI, so the functions it
calls run there; these tests add that every one of them is as @golem fmt@
writes it. A mistake is a file @<code>-<name>.emet@, maybe with a
@<code>-<name>.gm@ beside it: the lines of a chapter that imports the
.emet as @ex@. The project of the two gives the one diagnostic of the
code in the name of the file, and nothing else.
-}
module ManualEmetSpec (manualEmetTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Functions (formatFunctionFile)
import Support (codesOf)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (replaceExtension, takeExtension, takeFileName, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The manual, from the directory of golem-driver, where the tests run.
manual :: FilePath
manual = "../../manual"

manualEmetTests :: TestTree
manualEmetTests =
  testGroup
    "the .emet of the user manual (manual/functions, manual/examples/emet)"
    [ testCase "every .emet of manual/functions is as golem fmt writes it" $ do
        files <- emetUnder (manual </> "functions")
        assertBool "manual/functions has no .emet" (not (null files))
        forM_ files $ \f -> do
          t <- readText f
          case formatFunctionFile t of
            Left ds -> assertFailure (f <> ": " <> show (codesOf ds))
            Right formatted -> assertBool (f <> " is not formatted") (formatted == t),
      testCase "every mistake of manual/examples/emet gives the diagnostic of its name, and only it" $ do
        let dir = manual </> "examples" </> "emet"
        files <- sort . filter ((== ".emet") . takeExtension) <$> listDirectory dir
        assertBool "manual/examples/emet has no .emet" (not (null files))
        forM_ files $ \f -> do
          got <- mistakeCodes (dir </> f)
          (f, got) @?= (f, [codeOf f])
    ]

-- | The code in the name of a mistake: e01100-chained.emet is E01100.
codeOf :: FilePath -> Text
codeOf = T.toUpper . T.takeWhile (/= '-') . T.pack . takeFileName

-- | The codes of the diagnostics of the project of a mistake.
mistakeCodes :: FilePath -> IO [Text]
mistakeCodes f = withSystemTempDirectory "golem-manual-emet" $ \tmp -> do
  createDirectoryIfMissing True (tmp </> "functions")
  BS.readFile f >>= BS.writeFile (tmp </> "functions" </> "ex.emet")
  let gm = replaceExtension f "gm"
  hasGm <- doesFileExist gm
  calls <- if hasGm then readText gm else pure ""
  BS.writeFile (tmp </> "example.gm") (TE.encodeUtf8 ("@import functions/ex.emet as ex\n\n" <> calls))
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 projectManifest)
  BS.writeFile (tmp </> "style.toml") "[paragraph-styles.example]\nindent = \"1zw\"\n"
  r <- build (defaultOptions tmp)
  pure (codesOf (brDiagnostics r))

projectManifest :: Text
projectManifest =
  T.unlines
    [ "chapters = [\"example.gm\"]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000771\"",
      "title = \"Emet 入門の誤りの例\"",
      "language = \"ja\"",
      "date = 2026-11-09",
      "",
      "[targets.text]",
      "",
      "[source]",
      "paragraph-separator = \"blank-line\""
    ]

-- | The .emet under a directory and its subdirectories, sorted.
emetUnder :: FilePath -> IO [FilePath]
emetUnder dir = do
  entries <- sort <$> listDirectory dir
  concat <$> mapM (pick . (dir </>)) entries
  where
    pick p = do
      isDir <- doesDirectoryExist p
      if isDir
        then emetUnder p
        else pure [p | takeExtension p == ".emet"]

readText :: FilePath -> IO Text
readText p = TE.decodeUtf8 <$> BS.readFile p
