-- | Numbers the number formats cannot write, through the build (docs/adr/0213).
module UnwritableNumbersSpec (unwritableNumbersTests) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.TestSupport.Manifest
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A manifest of the chapters and the targets.
manifestOf :: [Text] -> [Text] -> BS.ByteString
manifestOf chapters targets = TE.encodeUtf8 (manifestToml testManifest {tmChapters = chapters, tmTargets = targets})

-- | Builds a project for the targets: its diagnostics, its sources and the outputs it wrote.
buildFor :: [Target] -> BS.ByteString -> BS.ByteString -> [(FilePath, Text)] -> IO ([Diagnostic], Map.Map FileId SourceInfo, [FilePath])
buildFor targets manifest style files = withSystemTempDirectory "golem-unwritable" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeFiles tmp (bodyFontFiles style)
  writeTexts tmp files
  r <- build (defaultOptions tmp) {optTargets = Just targets, optFiles = diskFiles tmp, optFonts = fakeProvider}
  pure (brDiagnostics r, brSources r, [p | p <- brWritten r, any (`isSuffixOf` p) [".pdf", ".html", ".xhtml", ".txt", ".epub", ".css"]])

-- | The book of the ADR: ㊿, then 51, its eight sections and a chapter of @number 0.
headingsStyle :: BS.ByteString
headingsStyle = horizontalStyle <> TE.encodeUtf8 "\n[headings.1]\nnumber = \"{n:circled}\"\n\n[headings.2]\nnumber = \"{1}-{n:note-symbols}\"\n"

headingsSource :: Text
headingsSource =
  T.intercalate "\n\n" (["@number 50\n# 五十", "# 五十一"] <> ["## " <> s | s <- ["一", "二", "三", "四", "五", "六", "七", "八"]] <> ["@number 0\n# 零"]) <> "\n"

-- | n pages of one line each, apart by page breaks.
pagesSource :: Int -> Text
pagesSource n = T.intercalate "\n\n@page-break\n\n" (replicate n "あ") <> "\n"

folioStyle :: Text -> BS.ByteString
folioStyle fmt = fiveLines <> TE.encodeUtf8 ("\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"" <> fmt <> "\" }\n")

summaryOf :: Diagnostic -> (DiagnosticCode, SrcSpan, Text)
summaryOf d = (diagCode d, diagSpan d, diagMessage d)

unwritableNumbersTests :: TestTree
unwritableNumbersTests =
  testGroup
    "numbers the number formats cannot write (docs/adr/0213)"
    [ testCase "N1, N5: the same G04012 in the same order for PDF, for HTML and text, and for all; no target written" $ do
        let manifest = manifestOf ["a.gm"] ["pdf", "html", "text"]
        runs <- mapM (\ts -> buildFor ts manifest headingsStyle [("a.gm", headingsSource)]) [[TargetPdf], [TargetHtml, TargetText], [TargetPdf, TargetHtml, TargetText]]
        let errs = [map summaryOf (filter isError ds) | (ds, _, _) <- runs]
            alls = [map summaryOf ds | (ds, _, _) <- runs]
        [[c | (DiagnosticCode c, _, _) <- e] | e <- errs] @?= replicate 3 ["G04012", "G04012", "G04012"]
        [[m | (_, _, m) <- e] | e <- take 1 errs]
          @?= [ [ "[headings.1] の number {n:circled} の {n:circled} では、51 を表せません",
                  "[headings.2] の number {1}-{n:note-symbols} の {n:note-symbols} では、8 を表せません",
                  "[headings.1] の number {n:circled} の {n:circled} では、0 を表せません"
                ]
              ]
        assertBool "the same diagnostics whatever the targets" (and (zipWith (==) alls (drop 1 alls)))
        [w | (_, _, w) <- runs] @?= [[], [], []],
      testCase "N4: a folio of {n:circled} on page 51 is one G07106 at the format, and no PDF; 50 pages report nothing" $ do
        let manifest = manifestOf ["a.gm"] ["pdf", "html"]
        (ds, sources, written) <- buildFor [TargetPdf] manifest (folioStyle "{n:circled}") [("a.gm", pagesSource 52)]
        let styleFid = [fid | (fid, si) <- Map.toList sources, siPath si == "style.toml"]
        [(c, m) | (DiagnosticCode c, _, m) <- map summaryOf (filter isError ds)]
          @?= [("G07106", "[masters.body] の folio の format {n:circled} の {n:circled} では、ノンブル 51 を表せません")]
        [spanFile (diagSpan d) | d <- ds, diagCode d == DiagnosticCode "G07106"] @?= styleFid
        written @?= []
        (ok, _, okWritten) <- buildFor [TargetPdf] manifest (folioStyle "{n:circled}") [("a.gm", pagesSource 50)]
        filter isError ok @?= []
        length okWritten @?= 1,
      testCase "N4: no G07106 for a book built without the PDF" $ do
        (ds, _, written) <- buildFor [TargetHtml] (manifestOf ["a.gm"] ["pdf", "html"]) (folioStyle "{n:circled}") [("a.gm", pagesSource 52)]
        filter isError ds @?= []
        assertBool (show written) (not (null written) && not (any (".pdf" `isSuffixOf`) written)),
      testCase "N4: of two master pages, only the one that cannot write its folio is reported" $ do
        let style =
              fiveLines
                <> TE.encodeUtf8 "\n[masters.front]\nfolio = { position = \"bottom-outside\", format = \"{n:upper-roman}\" }\n\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n:circled}\" }\n"
            manifest = TE.encodeUtf8 (T.replace "chapters = [\"front.gm\", \"a.gm\"]" "chapters = [{ file = \"front.gm\", master = \"front\" }, \"a.gm\"]" (TE.decodeUtf8 (manifestOf ["front.gm", "a.gm"] ["pdf"])))
        (ds, _, written) <- buildFor [TargetPdf] manifest style [("front.gm", pagesSource 50), ("a.gm", pagesSource 2)]
        [(c, m) | (DiagnosticCode c, _, m) <- map summaryOf (filter isError ds)]
          @?= [("G07106", "[masters.body] の folio の format {n:circled} の {n:circled} では、ノンブル 51 を表せません")]
        written @?= []
    ]
