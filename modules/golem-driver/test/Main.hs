module Main (main) where

import BuildSpec
import ChapterNotesSpec
import CliSpec
import ColophonSpec
import DiagnosticSitesSpec
import DiagnosticsSpec
import FigureSpec
import LocaleSpec
import MemoSpec
import PageElementsSpec
import ParagraphRuleSpec
import ParagraphSpec
import PdfSpec
import PluginsSpec
import ReferencesSpec
import RuleShapeSpec
import SecuritySpec
import StylesSpec
import TableFilesSpec
import Test.Tasty

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "golem-driver (ADR 0001)"
    ( [ qpdfInstalled,
        explainTests,
        noticeTests,
        testGroup "project diagnostics (golem-project ADR 0006)" projectDiagnosticTests,
        testGroup "reading stage (golem-parser ADR 0009)" readingTests,
        evalDiagnosticTests,
        testGroup "output and layout diagnostic codes (golem-driver ADR 0016)" outputDiagnosticTests,
        testGroup "code blocks and code (golem-driver ADR 0017)" codeTests,
        testGroup "the background of inline code (golem-driver ADR 0029)" inlineCodeBackgroundTests,
        testGroup "ruby and kenten after a code block (golem-driver ADR 0033)" codeBlockRubyTests,
        testGroup "the separator after a number (golem-html ADR 0002)" numberSeparatorTests,
        versionTests,
        memoTests,
        producerTests,
        securityTests,
        tableFileTests,
        testGroup "colophon (docs/adr ADR 0033)" colophonTests
      ]
        <> buildTests
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
             testGroup "PDF emphasis, character styles and colour (ADR 0004)" emphasisTests,
             testGroup "PDF wrapped figures (ADR 0005)" wrapTests,
             testGroup "PDF captions (ADR 0010)" captionTests,
             testGroup "PDF figures (golem-pdf ADR 0008)" pdfFigureTests,
             testGroup "SVG figures (golem-pdf ADR 0009)" svgFigureTests,
             testGroup "PDF sidenotes (ADR 0006)" sidenoteTests,
             testGroup "PDF index and bibliography (ADR 0007)" indexTests,
             testGroup "bibliography entries and G0326 (golem-doc ADR 0004)" bibliographyFormatTests,
             testGroup "PDF tables (ADR 0008)" tableTests,
             testGroup "PDF table of contents (ADR 0009)" tocTests,
             testGroup "ruby placement (golem-layout ADR 0009)" rubyTests,
             testGroup "plugins (golem-plugin ADR 0001, 0002)" pluginTests,
             testGroup "vertical glyphs turned without a vertical form (ADR 0015)" turnedTests,
             testGroup "kenten in the PDF (golem-driver ADR 0019)" kentenTests,
             testGroup "paragraph separator (docs/adr ADR 0013)" separatorTests,
             testGroup "hard line breaks (docs/adr ADR 0016)" hardBreakTests,
             testGroup "aki sets and [aki] (docs/adr ADR 0019)" akiTests,
             testGroup "crop marks and bleed (golem-pdf ADR 0004)" marksTests,
             testGroup "hidden folios (ADR 0021)" hiddenFolioTests,
             testGroup "forced breaks (docs/adr ADR 0017)" breakTests,
             testGroup "manual control of page breaks (docs/adr ADR 0030)" pageControlTests,
             testGroup "columns (docs/adr ADR 0018)" columnTests,
             testGroup "index columns (docs/adr ADR 0025)" indexColumnTests,
             testGroup "variation selectors and CIDSystemInfo (golem-pdf ADR 0006)" variationTests,
             testGroup "kerning, proportional metrics and baseline shift (docs/adr/0020)" characterFeatureTests,
             testGroup "running heads (ADR 0014)" runningHeadTests,
             testGroup "golem preflight (golem-cli ADR 0006)" preflightTests,
             testGroup "footnote marks and numbers (ADR 0018)" footnoteTests,
             testGroup "the footnote separator (ADR 0024)" noteRuleTests,
             testGroup "notes at the end of the chapter (ADR 0026)" chapterNoteTests,
             testGroup "the shapes of the line styles of a rule (ADR 0028)" ruleShapeTests,
             testGroup "the rules of paragraph styles and headings (ADR 0027)" paragraphRuleTests,
             localeTests,
             publicDomainTests,
             diagnosticSiteTests
           ]
    )
