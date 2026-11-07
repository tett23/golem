-- | The variables of [vars] of manifest.toml in the build and the running heads (docs/adr/0185).
module VarsSpec (varsTests) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | [vars] after the manifest of the PDF.
varsToml :: BS.ByteString
varsToml = "\n[vars]\nproduct = \"Golem\"\ncount = 3\nlist = [\"a\"]\n\n[vars.author]\nshort = \"tett23\"\n"

pdfManifest :: BS.ByteString
pdfManifest = miniManifest <> varsToml

-- | n lines of twelve characters
lines' :: Int -> T.Text
lines' n = T.replicate (12 * n) "あ"

-- | 海: pages 1 to 3, a blank page 4, 山: pages 5 and 6
twoChapters :: T.Text
twoChapters = T.intercalate "\n\n" ["# 海", lines' 5, lines' 6, lines' 6, "# 山", lines' 5, lines' 6] <> "\n"

-- | A style whose master page body has the running head @rh@.
headsStyle :: BS.ByteString -> BS.ByteString
headsStyle rh =
  BS.concat
    [ replaceIn "lines = 30\n" "lines = 6\n" horizontalStyle <> "\n",
      "[headings.1]\npage-break = \"recto\"\nsize = \"1zw\"\nlines = 1\n\n",
      "[masters.body]\nrunning-head = { position = \"top-outside\", ",
      rh,
      " }\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
    ]

-- | Builds a project of manifest, style and sources: its diagnostics, its sources and the files it wrote.
buildWith :: BuildOptions -> BS.ByteString -> BS.ByteString -> [(FilePath, T.Text)] -> IO ([Diagnostic], Map.Map FileId SourceInfo, [(FilePath, BS.ByteString)])
buildWith opts manifest style files = withSystemTempDirectory "golem-vars" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeFiles tmp (bodyFontFiles style)
  writeTexts tmp files
  r <- build opts {optRoot = tmp, optFiles = diskFiles tmp, optFonts = fakeProvider}
  written <- mapM (\p -> (p,) <$> BS.readFile p) (brWritten r)
  pure (brDiagnostics r, brSources r, [(drop (length tmp) p, b) | (p, b) <- written])

pdfBuild :: BuildOptions
pdfBuild = (defaultOptions ".") {optTargets = Just [TargetPdf]}

checkBuild :: BuildOptions
checkBuild = pdfBuild {optCheckOnly = True}

-- | The code, the path of the file and the start of each error.
errorSites :: Map.Map FileId SourceInfo -> [Diagnostic] -> [(T.Text, Maybe FilePath, Int)]
errorSites srcs ds =
  [ (c, siPath <$> Map.lookup (spanFile (diagSpan d)) srcs, spanStart (diagSpan d))
  | d <- ds,
    isError d,
    let DiagnosticCode c = diagCode d
  ]

-- | The byte offset of a text in the style.toml the build writes.
styleOffset :: BS.ByteString -> BS.ByteString -> Int
styleOffset style needle = BS.length (fst (BS.breakSubstring needle (withBodyFont style)))

varsTests :: TestTree
varsTests =
  testGroup
    "[vars] (docs/adr/0185)"
    [ testCase "{vars.product} of a running head shows the value, numbers and tables too" $ do
        (heads, _) <- layoutHeads pdfManifest (headsStyle "content = [\"{vars.product} {vars.count} {vars.author.short}\"]") [("a.gm", twoChapters)]
        Map.lookup 2 heads @?= Just ["Golem 3 tett23"],
      testCase "a running head shows the texts of [vars] given in the PdfInput (docs/adr/0196)" $ do
        (heads, _) <- layoutHeadsWith (Just (Map.fromList [(["product"], "差し替え")])) miniManifest (headsStyle "content = [\"{vars.product?}\"]") [("a.gm", twoChapters)]
        Map.lookup 2 heads @?= Just ["差し替え"],
      testCase "a running head does not read [vars] of the manifest again (docs/adr/0196)" $ do
        (heads, _) <- layoutHeadsWith (Just Map.empty) pdfManifest (headsStyle "content = [\"x{vars.product?}\"]") [("a.gm", twoChapters)]
        Map.lookup 2 heads @?= Just ["x"],
      testCase "{vars.missing?} is empty, without diagnostics" $ do
        (heads, _) <- layoutHeads pdfManifest (headsStyle "content = [\"{vars.missing?}{vars.product}\"]") [("a.gm", twoChapters)]
        Map.lookup 2 heads @?= Just ["Golem"]
        let style = headsStyle "content = [\"{vars.missing?}\"]"
        (ds, _, _) <- buildWith checkBuild pdfManifest style [("a.gm", twoChapters)]
        [d | d <- ds, isError d] @?= [],
      testCase "{vars.missing} is G03111 at the format in style.toml, in golem check and in the PDF build" $ do
        let style = headsStyle "content = [\"{vars.missing}\"]"
        mapM_
          ( \opts -> do
              (ds, srcs, _) <- buildWith opts pdfManifest style [("a.gm", twoChapters)]
              errorSites srcs ds @?= [("G03111", Just "style.toml", styleOffset style "\"{vars.missing}\"")]
          )
          [checkBuild, pdfBuild],
      testCase "{vars.list}, an array, is G03112" $ do
        let style = headsStyle "content = [\"{vars.list}\"]"
        (ds, srcs, _) <- buildWith checkBuild pdfManifest style [("a.gm", twoChapters)]
        errorSites srcs ds @?= [("G03112", Just "style.toml", styleOffset style "\"{vars.list}\"")],
      testCase "G03111 is reported once, whatever the number of chapters" $ do
        let style = headsStyle "content = [\"{vars.missing}\"]"
            manifest = TE.encodeUtf8 (T.replace "chapters = [\"a.gm\"]" "chapters = [\"a.gm\", \"b.gm\"]" (TE.decodeUtf8 pdfManifest))
        (ds, _, _) <- buildWith pdfBuild manifest style [("a.gm", twoChapters), ("b.gm", twoChapters)]
        map diagCode (filter isError ds) @?= [DiagnosticCode "G03111"],
      testCase "dev and prod read the same values of [vars]" $ do
        let manifest = TE.encodeUtf8 (manifestToml' "html") <> varsToml
            src = [("a.gm", "[= vars.product] [= vars.count]\n")]
        (ds, _, dev) <- buildWith (defaultOptions ".") {optProfile = Dev} manifest horizontalStyle src
        [diagMessage d | d <- ds, isError d] @?= []
        assertBool (show (map fst dev)) (any ((".xhtml" `isSuffixOf`) . fst) dev)
        (_, _, prod) <- buildWith (defaultOptions ".") {optProfile = Prod} manifest horizontalStyle src
        let html = [b | (p, b) <- dev, ".xhtml" `isSuffixOf` p]
        assertBool "the value in the HTML" (any ("Golem 3" `BS.isInfixOf`) html)
        [b | (p, b) <- prod, ".xhtml" `isSuffixOf` p] @?= html,
      testCase "the same input gives the same bytes" $ do
        let style = headsStyle "content = [\"{vars.product}\"]"
            src = [("a.gm", "[= vars.author.short]\n\n" <> twoChapters)]
        (ds, _, a) <- buildWith pdfBuild pdfManifest style src
        [d | d <- ds, isError d] @?= []
        (_, _, b) <- buildWith pdfBuild pdfManifest style src
        assertBool "a PDF" (any ((".pdf" `isSuffixOf`) . fst) a)
        b @?= a
    ]
  where
    manifestToml' t = T.replace "[targets.pdf]" ("[targets." <> t <> "]") (TE.decodeUtf8 miniManifest)
