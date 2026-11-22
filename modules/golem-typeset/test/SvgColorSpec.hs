module SvgColorSpec (svgColorTests) where

import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import Golem.Pdf.Object qualified as O
import Golem.Svg qualified as S
import Golem.Typeset.Svg (drawingSvg, recolorFigure, svgDrawing)
import Test.Tasty
import Test.Tasty.HUnit

svgColorTests :: TestTree
svgColorTests =
  testGroup
    "root ADR 0386 figure colours"
    [ testCase "root ADR 0386 I1: one SVG colour changes independently" $
        recolorFigure (30, 60, 90) (P.SvgFigure (drawing [black])) @?= P.SvgFigure (drawing [(30, 60, 90)]),
      testCase "root ADR 0386 I1: grouped strokes keep their geometry and line style" $ do
        let stroke = P.PathStroke black 2 1 2 4 [1, 2] 1
            drawing' color = P.Drawing (10, 10) [P.DrawGroup [1, 0, 0, 1, 2, 3] (Just (0, 0, 8, 8)) [P.DrawPath (P.PathPaint Nothing False (Just stroke {P.psColor = color})) [P.SegMove (0, 0), P.SegLine (10, 10)]]]
        recolorFigure (30, 60, 90) (P.SvgFigure (drawing' black)) @?= P.SvgFigure (drawing' (30, 60, 90)),
      testCase "root ADR 0386 I1: normalized SVG retains its geometry and paint" $ do
        let d = drawing [(30, 60, 90)]
        case S.readSvg (TE.encodeUtf8 (drawingSvg d)) of
          Left problem -> assertFailure (show problem)
          Right svg -> svgDrawing svg @?= d,
      testCase "root ADR 0386 I1: raster image bytes are unchanged" $ do
        let figure = P.RasterFigure (P.ImageData 1 1 8 P.CsRgb Nothing "RGB" False False Nothing)
        recolorFigure (30, 60, 90) figure @?= figure,
      testCase "root ADR 0386 I1: imported PDF page is unchanged" $ do
        let figure = P.VectorFigure (P.ImportedPage "hash" 1 (0, 0, 10, 10) 0 (10, 10) (O.ODict []) Nothing "content" [] [])
        recolorFigure (30, 60, 90) figure @?= figure,
      testCase "root ADR 0386 I1: multiple SVG colours are unchanged" $ do
        let figure = P.SvgFigure (drawing [black, (255, 0, 0)])
        recolorFigure (30, 60, 90) figure @?= figure
    ]
  where
    black = (0, 0, 0)
    drawing colors = P.Drawing (10, 10) [P.DrawPath (P.PathPaint (Just color) False Nothing) [P.SegMove (0, 0), P.SegLine (10, 10)] | color <- colors]
