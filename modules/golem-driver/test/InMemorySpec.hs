{- | The PDF of a project built from a table of its files (docs/adr/0199):
the same bytes and the same diagnostics as the build from the folder.
-}
module InMemorySpec (inMemoryTests, filesOf, kanikosenFixture) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Syntax
import Support (copyTree)
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, removeFile)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

kanikosenFixture :: FilePath
kanikosenFixture = "test/fixtures/kanikosen"

{- | Every file under a folder, by its path from the folder with @/@, as
the table of 'buildPdfInMemory' takes them; build/ is left out.
-}
filesOf :: FilePath -> IO (Map FilePath BS.ByteString)
filesOf root = Map.fromList <$> go ""
  where
    go rel = do
      entries <- listDirectory (root </> rel)
      concat
        <$> mapM
          ( \e -> do
              let r = if null rel then e else rel <> "/" <> e
              isDir <- doesDirectoryExist (root </> r)
              if isDir then (if r == "build" then pure [] else go r) else (\b -> [(r, b)]) <$> BS.readFile (root </> r)
          )
          entries

-- | The fonts of the golden tests (OutputGoldenSpec): fonts/ja.otf and fonts/latin.otf.
copyFonts :: FilePath -> IO ()
copyFonts tmp = do
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
  copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")

-- | The PDF build/pdf has after a build, if any.
writtenPdf :: FilePath -> IO (Maybe BS.ByteString)
writtenPdf root = do
  let dir = root </> "build" </> "pdf"
  ex <- doesDirectoryExist dir
  if not ex
    then pure Nothing
    else do
      pdfs <- filter (".pdf" `isSuffixOf`) <$> listDirectory dir
      case pdfs of
        [p] -> Just <$> BS.readFile (dir </> p)
        _ -> pure Nothing

{- | Builds the folder to the PDF as golem build --target pdf does, then
builds its files from the table: the PDF and the JSON of the diagnostics
must be the same.
-}
sameAsFolder :: FilePath -> IO BuildInMemory
sameAsFolder root = do
  table <- filesOf root
  r <- build (defaultOptions root) {optTargets = Just [TargetPdf]}
  pdf <- writtenPdf root
  m <- buildPdfInMemory table
  assertEqual "diagnostics" (renderJson (brSources r) (brDiagnostics r)) (renderJson (bimSources m) (bimDiagnostics m))
  assertEqual "PDF" pdf (bimPdf m)
  pure m

-- | The project of scripts/determinism/ with its PDF style.toml and the fonts.
determinismProject :: FilePath -> IO ()
determinismProject tmp = do
  copyTree "../../scripts/determinism" tmp
  removeFile (tmp </> "hashes.txt")
  BS.readFile (tmp </> "pdf-style.toml") >>= BS.writeFile (tmp </> "style.toml")
  removeFile (tmp </> "pdf-style.toml")
  copyFonts tmp

{- | The figures fixture with a @table of a CSV file and a citation of a
CSL-JSON file: figures, a table and a bibliography read from the table.
-}
assetsProject :: FilePath -> IO ()
assetsProject tmp = do
  copyTree "test/fixtures/figures" tmp
  copyFonts tmp
  BS.readFile "test/fixtures/bibliographies/refs.json" >>= BS.writeFile (tmp </> "refs.json")
  BS.writeFile (tmp </> "data.csv") (TE.encodeUtf8 "名前,数\n蟹,1\n工船,2\n")
  m <- BS.readFile (tmp </> "manifest.toml")
  BS.writeFile (tmp </> "manifest.toml") ("bibliography = [\"refs.json\"]\n" <> m)
  g <- BS.readFile (tmp </> "figures.gm")
  BS.writeFile (tmp </> "figures.gm") (g <> TE.encodeUtf8 "\n表と文献[cite jlreq]。\n\n@table data.csv\n\n@bibliography\n")

inMemoryTests :: TestTree
inMemoryTests =
  testGroup
    "buildPdfInMemory (docs/adr/0199)"
    [ testCase "kanikosen: the PDF and the diagnostics of the folder" $
        withSystemTempDirectory "golem-memory" $ \tmp -> do
          copyTree kanikosenFixture tmp
          m <- sameAsFolder tmp
          assertBool "a PDF" (maybe False (not . BS.null) (bimPdf m)),
      testCase "scripts/determinism/ with its PDF style.toml" $
        withSystemTempDirectory "golem-memory" $ \tmp -> do
          determinismProject tmp
          m <- sameAsFolder tmp
          assertBool "a PDF" (maybe False (not . BS.null) (bimPdf m)),
      testCase "figures, a table and a bibliography are read from the table" $
        withSystemTempDirectory "golem-memory" $ \tmp -> do
          assetsProject tmp
          m <- sameAsFolder tmp
          assertBool ("a PDF: " <> T.unpack (renderJson (bimSources m) (bimDiagnostics m))) (maybe False (not . BS.null) (bimPdf m))
          assertBool "no error" (not (any isError (bimDiagnostics m))),
      testCase "a broken style.toml: no PDF, and the diagnostic at its line and column" $
        withSystemTempDirectory "golem-memory" $ \tmp -> do
          copyTree kanikosenFixture tmp
          s <- BS.readFile (tmp </> "style.toml")
          BS.writeFile (tmp </> "style.toml") (s <> "\n[page\nsize = \n")
          m <- sameAsFolder tmp
          assertBool "no PDF" (isNothing (bimPdf m))
          let json = renderJson (bimSources m) (bimDiagnostics m)
          assertBool ("an error in style.toml: " <> T.unpack json) ("\"span\":{\"file\":\"style.toml\"" `T.isInfixOf` json && "\"line\":" `T.isInfixOf` json)
          assertBool "an error" (any isError (bimDiagnostics m)),
      testCase "a font style.toml names and the table lacks: the diagnostic of a missing font file" $
        withSystemTempDirectory "golem-memory" $ \tmp -> do
          copyTree kanikosenFixture tmp
          removeFile (tmp </> "fonts" </> "NotoSerifJP-Regular.otf")
          gone <- doesFileExist (tmp </> "fonts" </> "NotoSerifJP-Regular.otf")
          assertBool "removed" (not gone)
          m <- sameAsFolder tmp
          assertBool "no PDF" (isNothing (bimPdf m))
          assertEqual "codes" [DiagnosticCode "G08002"] [diagCode d | d <- bimDiagnostics m, isError d],
      testCase "without manifest.toml: G03016" $ do
        table <- Map.delete "manifest.toml" <$> filesOf kanikosenFixture
        m <- buildPdfInMemory table
        map diagCode (bimDiagnostics m) @?= [DiagnosticCode "G03016"]
        bimPdf m @?= Nothing
    ]
