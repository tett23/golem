module Main (main) where

import BookLanguageSpec (bookLanguageTests)
import BuildSpec
import ColophonSpec
import ComplexFixtureSpec (complexFixtureTests)
import EmetSamplesSpec (emetSamplesTests)
import ForceTableSpec (forceTableTests)
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Golem.TestSupport.Skipped (Skips, defaultMainReportingSkips)
import InMemorySpec (inMemoryTests)
import IndexRangeSpec (indexRangeTests)
import InsideLinksSpec (insideLinksTests)
import ManualEmetSpec (manualEmetTests)
import OutputGoldenSpec
import ReferencesSpec
import TableCaptionsSpec (tableCaptionsTests)
import TableFilesSpec
import Test.Tasty
import TocStylesSpec (tocStylesTests)

main :: IO ()
main = enterPackageDirectory >> defaultMainReportingSkips tests

{- | The tests of the outputs: HTML, EPUB and plain text, the goldens of
the four targets, bibliographies, indexes and cross references.
golem-driver-test was split into four suites, each with this first group,
so that the names of the tests did not change (root ADR 0416). The suite
is -threaded and tasty runs them at the same time: none of them changes
the state of the process (environment variables, the locale encoding, the
current directory). Those that do are in golem-driver-global-test
(GlobalMain.hs, docs/adr/0146).
-}
tests :: Skips -> TestTree
tests skips =
  testGroup
    "golem-driver (ADR 0001)"
    ( [ indexRangeTests,
        tocStylesTests,
        emetSamplesTests,
        manualEmetTests,
        testGroup "the separator after a number (golem-html ADR 0002)" numberSeparatorTests,
        testGroup "the default bullet by the output (golem-driver ADR 0044)" bulletTests,
        versionTests,
        producerTests,
        tableFileTests,
        inMemoryTests,
        testGroup "colophon (docs/adr ADR 0033)" colophonTests
      ]
        <> buildTests
        <> [outputGoldenTests, complexFixtureTests, insideLinksTests, bookLanguageTests]
        <> [ allTargetsTests,
             testGroup "files of style.toml per target (golem-project ADR 0004)" styleFileTests,
             testGroup "PDF index and bibliography (ADR 0007)" indexTests,
             testGroup "bibliography entries and G03026 (golem-doc ADR 0004)" bibliographyFormatTests,
             testGroup "PDF tables (ADR 0008)" tableTests,
             testGroup "table numbers, captions, column widths and cell styles (docs/adr/0262)" tableCaptionsTests,
             forceTableTests,
             testGroup "table column widths (golem-driver ADR 0037)" columnWidthTests,
             testGroup "PDF table of contents (ADR 0009)" tocTests,
             testGroup "line breaks inside a URL and the space after a note mark (golem-layout ADR 0018)" urlBreakTests,
             testGroup "index columns (docs/adr ADR 0025)" indexColumnTests,
             testGroup "the numerals of ref-page in vertical text (docs/adr/0118)" refPageNumeralTests,
             publicDomainTests skips
           ]
    )
