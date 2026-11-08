module Main (main) where

import AlignSpaceSpec (alignSpaceTests)
import BuildSpec
import CallsSpec (callsTests)
import ChapterNotesSpec
import CliSpec
import ColophonSpec
import ComplexFixtureSpec (complexFixtureTests)
import DiagnosticSitesSpec
import DiagnosticsSpec
import DoubleDashSpec (doubleDashTests)
import EmetSamplesSpec (emetSamplesTests)
import FigureSpec
import FileSpacesSpec (fileSpacesTests)
import FunctionLibrarySpec (functionLibraryTests)
import FunctionsSpec (functionsTests)
import Golem.TestSupport.Skipped (Skips, defaultMainReportingSkips)
import HeadingLevelsSpec (headingLevelsTests)
import InMemorySpec (inMemoryTests)
import LinkSpec (linkTests)
import OutputGoldenSpec
import OverflowSpec (overflowTests)
import PageElementsSpec
import PageStartsSpec (pageStartsTests)
import ParagraphRuleSpec
import ParagraphSpec
import PdfSpec
import ReferencesSpec
import SecuritySpec
import SpecimenGeometrySpec (specimenGeometryTests)
import StylesSpec
import TableFilesSpec
import TaggedPdfSpec (taggedPdfTests)
import Test.Tasty
import UnwritableNumbersSpec (unwritableNumbersTests)
import VarsSpec (varsTests)

main :: IO ()
main = defaultMainReportingSkips tests

{- | The tests. The suite is -threaded and tasty runs them at the same time:
none of them changes the state of the process (environment variables, the
locale encoding, the current directory). Those that do are in
golem-driver-global-test (GlobalMain.hs, docs/adr/0146).
-}
tests :: Skips -> TestTree
tests skips =
  testGroup
    "golem-driver (ADR 0001)"
    ( [ qpdfInstalled,
        explainTests,
        noticeTests,
        testGroup "project diagnostics (golem-project ADR 0006)" projectDiagnosticTests,
        testGroup "reading stage (golem-parser ADR 0009)" readingTests,
        evalDiagnosticTests,
        functionsTests,
        callsTests,
        varsTests,
        unwritableNumbersTests,
        emetSamplesTests,
        functionLibraryTests,
        testGroup "output and layout diagnostic codes (golem-driver ADR 0016)" outputDiagnosticTests,
        testGroup "code blocks and code (golem-driver ADR 0017)" codeTests,
        testGroup "the background of inline code (golem-driver ADR 0029)" inlineCodeBackgroundTests,
        testGroup "the link annotations of the PDF (docs/adr ADR 0182)" linkTests,
        testGroup "ruby and kenten after a code block (golem-driver ADR 0033)" codeBlockRubyTests,
        testGroup "the text layer of ligatures (golem-driver ADR 0030)" ligatureTests,
        testGroup "combining characters (golem-driver ADR 0036)" combiningTests,
        testGroup "the separator after a number (golem-html ADR 0002)" numberSeparatorTests,
        testGroup "the default bullet by the output (golem-driver ADR 0044)" bulletTests,
        versionTests,
        producerTests,
        securityTests,
        tableFileTests,
        inMemoryTests,
        testGroup "colophon (docs/adr ADR 0033)" colophonTests
      ]
        <> buildTests
        <> [outputGoldenTests, complexFixtureTests, taggedPdfTests, overflowTests, specimenGeometryTests]
        <> [ newProjectTests,
             allTargetsTests,
             pdfPipelineTests,
             testGroup "files of style.toml per target (golem-project ADR 0004)" styleFileTests,
             testGroup "verse (docs/adr ADR 0003)" verseTests,
             testGroup "paragraph indents (docs/adr ADR 0006)" indentTests,
             testGroup "list indents (golem-driver ADR 0013)" listTests,
             testGroup "styles defined in a file (docs/adr ADR 0014)" inFileTests,
             testGroup "regex styles (docs/adr ADR 0015)" regexStyleTests,
             testGroup "PDF headings (ADR 0003)" headingTests,
             testGroup "headings of six levels (docs/adr/0188)" headingLevelsTests,
             testGroup "PDF emphasis, character styles and colour (ADR 0004)" emphasisTests,
             testGroup "PDF wrapped figures (ADR 0005)" wrapTests,
             testGroup "PDF captions (ADR 0010)" captionTests,
             testGroup "PDF figures (golem-pdf ADR 0008)" pdfFigureTests,
             testGroup "SVG figures (golem-pdf ADR 0009)" svgFigureTests,
             testGroup "SVG active content in HTML and EPUB (docs/adr ADR 0039)" activeContentTests,
             testGroup "figures fitted to the column (golem-driver ADR 0034)" fitFigureTests,
             testGroup "the width of figures (docs/adr/0190)" figureWidthTests,
             testGroup "turned figures (golem-driver ADR 0034)" turnedFigureTests,
             testGroup "PDF sidenotes (ADR 0006)" sidenoteTests,
             testGroup "PDF index and bibliography (ADR 0007)" indexTests,
             testGroup "bibliography entries and G03026 (golem-doc ADR 0004)" bibliographyFormatTests,
             testGroup "PDF tables (ADR 0008)" tableTests,
             testGroup "table column widths (golem-driver ADR 0037)" columnWidthTests,
             testGroup "PDF table of contents (ADR 0009)" tocTests,
             testGroup "ruby placement (golem-layout ADR 0009)" rubyTests,
             testGroup "vertical glyphs turned without a vertical form (ADR 0015)" turnedTests,
             testGroup "kenten in the PDF (golem-driver ADR 0019)" kentenTests,
             testGroup "double dashes drawn as one line (docs/adr ADR 0172)" doubleDashTests,
             pageStartsTests,
             testGroup "paragraph separator (docs/adr ADR 0013)" separatorTests,
             testGroup "hard line breaks (docs/adr ADR 0016)" hardBreakTests,
             testGroup "aki sets and [aki] (docs/adr ADR 0019)" akiTests,
             testGroup "inseparable characters at the line edges (golem-layout ADR 0016)" inseparableTests,
             testGroup "spaces inside inline code (golem-layout ADR 0017)" codeSpaceTests,
             testGroup "protrusion at the ends of Latin words (docs/adr/0222)" protrusionTests,
             testGroup "line breaks inside a URL and the space after a note mark (golem-layout ADR 0018)" urlBreakTests,
             testGroup "crop marks and bleed (golem-pdf ADR 0004)" marksTests,
             testGroup "hidden folios (ADR 0021)" hiddenFolioTests,
             testGroup "forced breaks (docs/adr ADR 0017)" breakTests,
             testGroup "manual control of page breaks (docs/adr ADR 0030)" pageControlTests,
             testGroup "blank lines (docs/adr ADR 0046)" blankLineTests,
             testGroup "columns (docs/adr ADR 0018)" columnTests,
             testGroup "index columns (docs/adr ADR 0025)" indexColumnTests,
             testGroup "the numerals of ref-page in vertical text (docs/adr/0118)" refPageNumeralTests,
             testGroup "variation selectors and CIDSystemInfo (golem-pdf ADR 0006)" variationTests,
             testGroup "kerning, proportional metrics and baseline shift (docs/adr/0020)" characterFeatureTests,
             testGroup "running heads (ADR 0014)" runningHeadTests,
             testGroup "golem preflight (golem-cli ADR 0006)" preflightTests,
             testGroup "footnote marks and numbers (ADR 0018)" footnoteTests,
             testGroup "the footnote separator (ADR 0024)" noteRuleTests,
             testGroup "notes at the end of the chapter (ADR 0026)" chapterNoteTests,
             testGroup "the rules of paragraph styles and headings (ADR 0027)" paragraphRuleTests,
             testGroup "the alignment, spaces and end indent of paragraph styles (docs/adr/0189)" alignSpaceTests,
             testGroup "the spaces of paragraph styles redefined in files (docs/adr/0217)" fileSpacesTests,
             publicDomainTests skips,
             diagnosticSiteTests
           ]
    )
