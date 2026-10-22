{- | Diagnostic sites that a build through 'build' never reaches, because
the driver reports the same problem earlier (golem-driver ADR 0016):
the fonts and the output intent when the PDF is rendered by itself, and
the blocks of the labels where G07021 points.
-}
module DiagnosticSitesSpec (diagnosticSiteTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Fonts (golemFontProvider)
import Golem.Driver.Pdf (PdfInput (..), labelSpans, renderPdf, styleFileId)
import Golem.Project (ProjectFailure (..))
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | Evaluates a one-chapter project with the fake body font and hands over the parts the PDF needs.
withMiniEvaluated :: BS.ByteString -> T.Text -> (FilePath -> Evaluated -> IO a) -> IO a
withMiniEvaluated style source k = withSystemTempDirectory "golem-sites" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  writeStyleWithFont tmp style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  ev <- evaluateProject Dev tmp
  either (assertFailure . show . pfDiagnostics) (k tmp) ev

-- | The PDF input the driver passes for an evaluated project.
inputOf :: FilePath -> Evaluated -> IO PdfInput
inputOf tmp e = case evBook e of
  Just book -> pure (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty)
  Nothing -> assertFailure (show (evDiagnostics e))

-- | The text of the source that a span covers.
spanText :: T.Text -> SrcSpan -> T.Text
spanText source sp = TE.decodeUtf8 (BS.take (spanEnd sp - spanStart sp) (BS.drop (spanStart sp) (TE.encodeUtf8 source)))

diagnosticSiteTests :: TestTree
diagnosticSiteTests =
  testGroup
    "diagnostic sites behind the driver's own checks (golem-driver ADR 0016)"
    [ testCase "G08002: the font provider by itself reports a missing font file once, at the top of the given file" $
        withSystemTempDirectory "golem-sites" $ \tmp -> do
          style <- either (assertFailure . show) pure (parseStyle (FileId 0) "[fonts.body]\nja = \"fonts/none.otf\"\nlatin = \"fonts/none.otf\"\n")
          r <- loadFonts golemFontProvider tmp (FileId 7) style []
          either (map (\d -> (diagCode d, diagSpan d, diagMessage d))) (const []) r
            @?= [(DiagnosticCode "G08002", mkSpan (FileId 7) 0 0, "フォントのファイルがありません: fonts/none.otf")],
      testCase "G08019: the font provider by itself rejects a CFF2 font (golem-font ADR 0003)" $
        withSystemTempDirectory "golem-sites" $ \tmp -> do
          BS.readFile "../golem-font/test/fonts/SourceSerif4Variable-Roman.otf" >>= BS.writeFile (tmp </> "v.otf")
          style <- either (assertFailure . show) pure (parseStyle (FileId 0) "[fonts.body]\nlatin = \"v.otf\"\n")
          r <- loadFonts golemFontProvider tmp (FileId 7) style []
          either (map (\d -> (diagCode d, diagSpan d))) (const []) r @?= [(DiagnosticCode "G08019", mkSpan (FileId 7) 0 0)],
      testCase "G08006: rendering a PDF whose output intent is missing stops at the top of style.toml" $
        withMiniEvaluated (horizontalStyle <> "\n[color]\nintent = \"icc/none.icc\"\n") "本文。\n" $ \tmp e -> do
          inp <- inputOf tmp e
          r <- renderPdf fakeProvider inp
          either (map (\d -> (diagCode d, diagSpan d, diagMessage d))) (const []) r
            @?= [(DiagnosticCode "G08006", mkSpan (styleFileId (evProject e)) 0 0, "出力インテントの ICC プロファイルがありません: icc/none.icc")],
      testCase "G07021 points at the block a label is attached to" $ do
        let source = "最初の段落。\n\n@label second\n二番目の段落。\n\n@label third\n三番目の段落。\n"
        withMiniEvaluated horizontalStyle source $ \_ e -> do
          book <- maybe (assertFailure (show (evDiagnostics e))) pure (evBook e)
          Map.map (spanText source) (labelSpans book)
            @?= Map.fromList [("second", "二番目の段落。\n"), ("third", "三番目の段落。\n")]
    ]
