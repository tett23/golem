module SvgColorSpec (svgColorTests) where

import Data.ByteString qualified as BS
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import Golem.Pdf.Object qualified as O
import Golem.Svg qualified as S
import Golem.Typeset.FigureColor (analyzeRaster)
import Golem.Typeset.PdfColor (recolorImportedPage)
import Golem.Typeset.Svg (drawingImportedPage, drawingSvg, recolorFigure, svgDrawing)
import Test.Tasty
import Test.Tasty.HUnit

svgColorTests :: TestTree
svgColorTests =
  testGroup
    "root ADR 0386 figure colours"
    [ testCase "root ADR 0386 I1: one SVG colour changes independently" $
        recolorFigure (0, 100, 100, 0) (P.SvgFigure (drawing [black])) @?= P.SvgFigure (drawing [(255, 0, 0)]),
      testCase "root ADR 0386 I1: grouped strokes keep their geometry and line style" $ do
        let stroke = P.PathStroke black 2 1 2 4 [1, 2] 1
            drawing' color = P.Drawing (10, 10) [P.DrawGroup [1, 0, 0, 1, 2, 3] (Just (0, 0, 8, 8)) [P.DrawPath (P.PathPaint Nothing False (Just stroke {P.psColor = color})) [P.SegMove (0, 0), P.SegLine (10, 10)]]] [1, 0, 0, 1, 0, 0]
        recolorFigure (0, 100, 100, 0) (P.SvgFigure (drawing' black)) @?= P.SvgFigure (drawing' (255, 0, 0)),
      testCase "root ADR 0403 I1: SVG white gray and black preserve their tone" $
        recolorFigure (0, 100, 100, 0) (P.SvgFigure (drawing [(255, 255, 255), (128, 128, 128), black])) @?= P.SvgFigure (drawing [(255, 255, 255), (255, 128, 128), (255, 0, 0)]),
      testCase "root ADR 0403 I1: SVG PDF paint uses direct CMYK and keeps the geometry" $ do
        let original = drawingImportedPage (drawing [(255, 255, 255), (128, 128, 128), black])
            swatch = (0, 100, 100, 0)
        case recolorImportedPage swatch (analyzeRaster swatch) original of
          Right (Just converted) -> do
            assertBool "white" ("0 0 0 0 k" `BS.isInfixOf` P.ipContent converted)
            assertBool "black" ("0 1 1 0 k" `BS.isInfixOf` P.ipContent converted)
            P.ipBox converted @?= P.ipBox original
            P.ipSize converted @?= P.ipSize original
          other -> assertFailure (show other),
      testCase "root ADR 0403 I1: SVG gray avoids double rounding before CMYK conversion" $ do
        let original = drawingImportedPage (drawing [(7, 7, 7)])
            swatch = (0, 2, 0, 0)
        case recolorImportedPage swatch (analyzeRaster swatch) original of
          Right (Just converted) -> assertBool "2 percent magenta times 248/255 rounds to 0.01945098" ("0 0.01945098 0 0 k" `BS.isInfixOf` P.ipContent converted)
          other -> assertFailure (show other),
      testCase "root ADR 0403 I2: SVG without recolouring retains its original precision" $ do
        let original = drawing [(7, 7, 7)]
        assertBool "ordinary RGB remains four digits" ("0.0275 0.0275 0.0275 sc" `BS.isInfixOf` P.drawingContent original)
        assertBool "conversion keeps twelve digits before CMYK" ("0.027450980392" `BS.isInfixOf` P.drawingContentForRecoloring original),
      testCase "root ADR 0386 I1: normalized SVG retains its geometry and paint" $ do
        let d = drawing [(30, 60, 90)]
        case S.readSvg (TE.encodeUtf8 (drawingSvg d)) of
          Left problem -> assertFailure (show problem)
          Right svg -> svgDrawing svg @?= d,
      testCase "root ADR 0386 I1: raster image bytes are unchanged" $ do
        let figure = P.RasterFigure (P.ImageData 1 1 8 P.CsRgb Nothing "RGB" False False Nothing)
        recolorFigure (0, 100, 100, 0) figure @?= figure,
      testCase "root ADR 0386 I1: imported PDF page is unchanged" $ do
        let figure = P.VectorFigure (P.ImportedPage "hash" 1 (0, 0, 10, 10) 0 (10, 10) (O.ODict []) Nothing "content" [] [] 0)
        recolorFigure (0, 100, 100, 0) figure @?= figure,
      testCase "root ADR 0386 I1: multiple SVG colours are unchanged" $ do
        let figure = P.SvgFigure (drawing [black, (255, 0, 0)])
        recolorFigure (0, 100, 100, 0) figure @?= figure
    ]
  where
    black = (0, 0, 0)
    drawing colors = P.Drawing (10, 10) [P.DrawPath (P.PathPaint (Just color) False Nothing) [P.SegMove (0, 0), P.SegLine (10, 10)] | color <- colors] [1, 0, 0, 1, 0, 0]
