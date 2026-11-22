module Main (main) where

import AdjustOrderSpec (adjustOrderTests)
import AlignSpaceSpec (alignSpaceTests)
import BoxesSpec (boxesTests)
import CaptionSidenoteIndentSpec (captionSidenoteIndentTests)
import CaptionSidenoteParagraphsSpec (captionSidenoteParagraphsTests)
import ChapterNotesSpec
import CompressedNoteMarksSpec (compressedNoteMarksTests)
import FigureSpec
import FileSpacesSpec (fileSpacesTests)
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import HeadingLevelsSpec (headingLevelsTests)
import KeepOptionsSpec (keepOptionsTests)
import LineAdjustmentSpec (lineAdjustmentTests)
import NestedFiguresSpec qualified
import NoteBodyStylesSpec (noteBodyStylesTests)
import NotesSpec (notesTests)
import NumberTitleSeparatorSpec (numberTitleSeparatorTests)
import OverflowSpec (overflowTests)
import PageElementsSpec
import PageLabelsSpec (pageLabelsTests)
import PageMapSpec (pageMapTests)
import PageNoteNumbersSpec (pageNoteNumbersTests)
import PageStartsSpec (pageStartsTests)
import ParagraphPitchSpec (paragraphPitchTests)
import ParagraphRuleSpec
import ParagraphSpec
import ParagraphStyleControlsSpec (paragraphStyleControlsTests)
import ParagraphWrapPitchSpec (paragraphWrapPitchTests)
import ReuseSpec
import SeparatorSpec (visibleSeparatorTests)
import SinglePageSpec qualified
import SoftHyphenSpec (softHyphenTests)
import StylesSpec
import Test.Tasty
import VerseLineNumbersSpec (verseLineNumberTests)

main :: IO ()
main = enterPackageDirectory >> defaultMainReportingSkips (const tests)

{- | The tests of the pages: paragraphs, headings, notes, figures and
their placement, and page breaks. golem-driver-test was split into four
suites, each with this first group, so that the names of the tests did
not change (root ADR 0416). The suite is -threaded and tasty runs them at the same
time: none of them changes the state of the process (environment
variables, the locale encoding, the current directory). Those that do are
in golem-driver-global-test (GlobalMain.hs, docs/adr/0146).
-}
tests :: TestTree
tests =
  testGroup
    "golem-driver (ADR 0001)"
    [ NestedFiguresSpec.tests,
      SinglePageSpec.tests,
      pageLabelsTests,
      keepOptionsTests,
      lineAdjustmentTests,
      adjustOrderTests,
      boxesTests,
      overflowTests,
      softHyphenTests,
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
      testGroup "notes of more than one paragraph (docs/adr/0263)" notesTests,
      pageStartsTests,
      pageMapTests,
      testGroup "paragraph separator (docs/adr ADR 0013)" separatorTests,
      testGroup "hard line breaks (docs/adr ADR 0016)" hardBreakTests,
      testGroup "aki sets and [aki] (docs/adr ADR 0019)" akiTests,
      testGroup "inseparable characters at the line edges (golem-layout ADR 0016)" inseparableTests,
      testGroup "spaces inside inline code (golem-layout ADR 0017)" codeSpaceTests,
      testGroup "protrusion at the ends of Latin words (docs/adr/0222)" protrusionTests,
      testGroup "forced breaks (docs/adr ADR 0017)" breakTests,
      testGroup "manual control of page breaks (docs/adr ADR 0030)" pageControlTests,
      testGroup "blank lines (docs/adr ADR 0046)" blankLineTests,
      testGroup "columns (docs/adr ADR 0018)" columnTests,
      testGroup "running heads (ADR 0014)" runningHeadTests,
      testGroup "the decorations of running heads and folios (docs/adr/0410)" runningHeadDecorationTests,
      testGroup "footnote marks and numbers (ADR 0018)" footnoteTests,
      testGroup "the footnote separator (ADR 0024)" noteRuleTests,
      testGroup "notes at the end of the chapter (ADR 0026)" chapterNoteTests,
      testGroup "the paragraph styles of notes (docs/adr/0366)" noteBodyStylesTests,
      testGroup "notes numbered per page (docs/adr/0383)" pageNoteNumbersTests,
      testGroup "the kanji numbers of note marks set flat (docs/adr/0381)" compressedNoteMarksTests,
      testGroup "the paragraphs of captions and sidenotes (docs/adr/0367)" captionSidenoteParagraphsTests,
      testGroup "the paragraph style controls (docs/adr/0374)" paragraphStyleControlsTests,
      testGroup "the indents of captions and sidenotes that leave no character (docs/adr/0389)" captionSidenoteIndentTests,
      testGroup "the separator between a number and its title (Golem ADR 0372)" numberTitleSeparatorTests,
      testGroup "verse line numbers (root ADR 0384)" verseLineNumberTests,
      testGroup "the rules of paragraph styles and headings (ADR 0027)" paragraphRuleTests,
      paragraphPitchTests,
      paragraphWrapPitchTests,
      testGroup "root ADR 0398: visible separators" visibleSeparatorTests,
      testGroup "the alignment, spaces and end indent of paragraph styles (docs/adr/0189)" alignSpaceTests,
      testGroup "the spaces of paragraph styles redefined in files (docs/adr/0217)" fileSpacesTests,
      testGroup "the compositions reused between the rounds of page references (docs/adr ADR 0251)" reuseTests
    ]
