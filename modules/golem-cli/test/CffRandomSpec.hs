{- | The PDF of a CFF font whose CharStrings run random (Golem ADR 0390, I3,
I8 and I9), built by separate golem processes.

The font is the RandomSansPro-Regular.otf of the tests of golem-font
(Source Sans Pro with four glyphs rewritten, see RandomFontSpec there): the
box of q comes from random, b divides by an interval holding 0 (G08108), d
calls a subroutine by a number FreeType does not take (G08109), and v calls
past the INDEX (G08107) by such a number (G08109). The project is the en
template of golem new with that font in place of its font.
-}
module CffRandomSpec (cffRandomTests) where

import Control.Monad (forM, forM_, when)
import Data.Aeson qualified as J
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory, removeDirectoryRecursive)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

cffRandomTests :: TestTree
cffRandomTests =
  testGroup
    "the PDF of a CFF font that runs random (Golem ADR 0390)"
    [ testCase "ADR 0390 I3: four golem processes, one with FREETYPE_PROPERTIES=cff:random-seed=777, write the same PDF" $
        withBook "q\n" $ \book -> do
          pdfs <- forM [[], [], [], [("FREETYPE_PROPERTIES", "cff:random-seed=777")]] $ \extra -> do
            (code, err) <- build book extra ["--target", "pdf"]
            assertEqual err ExitSuccess code
            pdfOf book >>= maybe (assertFailure "no PDF") pure
          case pdfs of
            first : rest -> forM_ rest (\p -> assertBool "the PDFs differ" (p == first))
            [] -> assertFailure "no build",
      testGroup
        "ADR 0390 I8, I9: no PDF after G08107, G08108 or G08109, in dev and in prod"
        [ testCase (profile <> ": " <> show text) $ withBook text $ \book -> do
            (code, out) <- build book [] ["--target", "pdf", "--profile", profile, "--format", "json"]
            (code, codesOf out) @?= (ExitFailure 1, expected)
            pdfOf book >>= (@?= Nothing)
        | profile <- ["dev", "prod"],
          (text, expected) <-
            [ ("qb\n", ["G08108"]),
              ("qd\n", ["G08109"]),
              ("qv\n", ["G08107", "G08109"])
            ]
        ],
      testCase "ADR 0390 I8: a glyph FreeType reads is not G08109, though its box comes from random" $
        withBook "q\n" $ \book -> do
          (code, out) <- build book [] ["--target", "pdf", "--format", "json"]
          (code, codesOf out) @?= (ExitSuccess, [])
          pdfOf book >>= maybe (assertFailure "no PDF") (const (pure ()))
    ]

-- | The en template with the rewritten font and a chapter of the text.
withBook :: String -> (FilePath -> IO ()) -> IO ()
withBook text act = withSystemTempDirectory "golem-random" $ \tmp -> do
  (code, _, err) <- readCreateProcessWithExitCode (proc "golem" ["new", "book", "--language", "en", "--no-fonts"]) {cwd = Just tmp} ""
  assertEqual err ExitSuccess code
  let book = tmp </> "book"
  font <- BS.readFile "../golem-font/test/fonts/RandomSansPro-Regular.otf"
  createDirectoryIfMissing True (book </> "fonts")
  BS.writeFile (book </> "fonts/SourceSerif4-Regular.otf") font
  BS.writeFile (book </> "chapters/01.gm") (TE.encodeUtf8 (T.pack text))
  act book

{- | golem build in its own process, with the variables added to the
environment (and FREETYPE_PROPERTIES taken out of it otherwise), after the
build directory is removed: the exit code and stdout followed by stderr.
-}
build :: FilePath -> [(String, String)] -> [String] -> IO (ExitCode, String)
build book extra args = do
  exists <- doesDirectoryExist (book </> "build")
  when exists (removeDirectoryRecursive (book </> "build"))
  env <- filter ((/= "FREETYPE_PROPERTIES") . fst) <$> getEnvironment
  (code, _, err) <- readCreateProcessWithExitCode (proc "golem" ("build" : args)) {cwd = Just book, env = Just (extra <> env)} ""
  pure (code, err)

-- | The PDF golem build wrote, if any.
pdfOf :: FilePath -> IO (Maybe BS.ByteString)
pdfOf book = do
  exists <- doesDirectoryExist (book </> "build/pdf")
  pdfs <- if exists then filter (".pdf" `isSuffixOf`) <$> listDirectory (book </> "build/pdf") else pure []
  case pdfs of
    [p] -> Just <$> BS.readFile (book </> "build/pdf" </> p)
    [] -> pure Nothing
    ps -> assertFailure ("several PDFs: " <> show ps)

-- | The codes of the diagnostics of --format json, in their order.
codesOf :: String -> [Text]
codesOf out = case J.decode (BL.fromStrict (TE.encodeUtf8 (T.pack out))) :: Maybe [Map.Map Text J.Value] of
  Just ds -> [c | d <- ds, Just (J.String c) <- [Map.lookup "code" d]]
  Nothing -> ["not JSON: " <> T.pack out]
