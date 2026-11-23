module Main (main) where

import CodeFontSpec (codeFontTests)
import DecorationsSpec (decorationsTests)
import DoubleDashSpec (doubleDashTests)
import ExpansionSpec (expansionTests)
import FigureExternalSpec (figureExternalTests)
import FontInstanceSpec qualified
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import LinkSpec (linkTests)
import OpenTypeFeaturesSpec (openTypeFeaturesTests)
import PdfSpec
import PlatesSpec (platesTests)
import PopplerSpec (popplerTests)
import PunctuationWidthSpec (punctuationWidthTests)
import ScriptsSpec (scriptsTests)
import ShapingMemoSpec (shapingMemoTests)
import SpecimenGeometrySpec (specimenGeometryTests)
import TaggedPdfSpec (taggedPdfTests)
import TateChuYokoSpec (tateChuYokoTests)
import Test.Tasty
import VisualSubsetSpec (visualSubsetTests)

main :: IO ()
main = enterPackageDirectory >> defaultMainReportingSkips (const tests)

{- | The tests of the PDF: its structure, its tags, its fonts and the
figures that other tools wrote. golem-driver-test was split into four
suites, each with this first group, so that the names of the tests did
not change (root ADR 0416). The suite is -threaded and tasty runs them
at the same time: none of them changes the state of the process
(environment variables, the locale encoding, the current directory).
Those that do are in golem-driver-global-test (GlobalMain.hs, docs/adr/0146).
-}
tests :: TestTree
tests =
  testGroup
    "golem-driver (ADR 0001)"
    [ qpdfInstalled,
      visualSubsetTests,
      testGroup "code blocks and code (golem-driver ADR 0017)" codeTests,
      testGroup "the background of inline code (golem-driver ADR 0029)" inlineCodeBackgroundTests,
      testGroup "the link annotations of the PDF (docs/adr ADR 0182)" linkTests,
      testGroup "ruby and kenten after a code block (golem-driver ADR 0033)" codeBlockRubyTests,
      testGroup "the text layer of ligatures (golem-driver ADR 0030)" ligatureTests,
      testGroup "combining characters (golem-driver ADR 0036)" combiningTests,
      shapingMemoTests,
      taggedPdfTests,
      specimenGeometryTests,
      tateChuYokoTests,
      expansionTests,
      codeFontTests,
      openTypeFeaturesTests,
      punctuationWidthTests,
      scriptsTests,
      decorationsTests,
      pdfPipelineTests,
      testGroup "ruby placement (golem-layout ADR 0009)" rubyTests,
      testGroup "vertical glyphs turned without a vertical form (ADR 0015)" turnedTests,
      testGroup "kenten in the PDF (golem-driver ADR 0019)" kentenTests,
      testGroup "double dashes drawn as one line (docs/adr ADR 0172)" doubleDashTests,
      testGroup "crop marks and bleed (golem-pdf ADR 0004)" marksTests,
      testGroup "hidden folios (ADR 0021)" hiddenFolioTests,
      testGroup "variation selectors and CIDSystemInfo (golem-pdf ADR 0006)" variationTests,
      testGroup "kerning, proportional metrics and baseline shift (docs/adr/0020)" characterFeatureTests,
      testGroup "the plates of the PDF and G09019 to G09021 (docs/adr ADR 0232)" platesTests,
      testGroup "the PDF as Poppler reads it (docs/adr ADR 0232)" popplerTests,
      testGroup "figures written by other tools (docs/adr ADR 0232)" figureExternalTests,
      FontInstanceSpec.tests
    ]
