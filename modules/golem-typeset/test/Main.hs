module Main (main) where

import BoxSpec (boxTests)
import FigureColorSpec (figureColorTests)
import GlyphRunsSpec (glyphRunsTests)
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import MemoSpec (memoTests)
import PdfColorClassifySpec (pdfColorClassifyTests)
import PdfColorMeshSpec (pdfColorMeshTests)
import PdfColorPatternSpec (pdfColorPatternTests)
import PdfColorRangeSpec (pdfColorRangeTests)
import PdfColorShadingSpec (pdfColorShadingTests)
import PdfColorSpec (pdfColorTests)
import PdfDctSpec (pdfDctTests)
import RuleShapeSpec (ruleShapeTests)
import SvgColorSpec (svgColorTests)
import TcySpec (tcyTests)
import Test.Tasty
import WrapMarkSpec (wrapMarkTests)

main :: IO ()
main = enterPackageDirectory >> defaultMain tests

-- | The tests of the modules of golem-typeset that need no evaluation (docs/adr/0192).
tests :: TestTree
tests =
  testGroup
    "golem-typeset"
    [ pdfDctTests,
      figureColorTests,
      svgColorTests,
      testGroup "PDF figure colors" pdfColorTests,
      testGroup "PDF figure colour range" pdfColorRangeTests,
      testGroup "PDF figure colour classes (root ADR 0425)" pdfColorClassifyTests,
      testGroup "PDF figure shadings (root ADR 0425)" pdfColorShadingTests,
      testGroup "PDF figure mesh shadings (root ADR 0425)" pdfColorMeshTests,
      testGroup "PDF figure patterns (root ADR 0425)" pdfColorPatternTests,
      memoTests,
      testGroup "the shapes of the line styles of a rule (ADR 0028)" ruleShapeTests,
      testGroup "the glyph runs of a box in the order of its text (docs/adr ADR 0227)" glyphRunsTests,
      testGroup "the fit of a tate-chu-yoko in its box (golem-driver ADR 0045)" tcyTests,
      testGroup "the shape and the colour of the wrap mark of inline code (golem-layout ADR 0042)" wrapMarkTests,
      testGroup "the boxes of paragraph styles (docs/adr/0271)" boxTests
    ]
