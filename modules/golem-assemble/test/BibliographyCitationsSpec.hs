module BibliographyCitationsSpec (tests) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Lazy.Encoding qualified as TLE
import Golem.Assemble.BibliographyCitations
import Golem.Assemble.BibliographyStyle
import Golem.Bibliography.Csl (CslRecord, decodeCslRecords)
import Golem.Doc.Citation (CitePiece (..), citationText)
import Golem.Doc.IR
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

records :: IO [CslRecord]
records = either (assertFailure . show) pure (decodeCslRecords (TLE.encodeUtf8 "[{\"id\":\"a\",\"type\":\"book\",\"title\":\"A\",\"author\":[{\"family\":\"Kádár\"}],\"issued\":{\"date-parts\":[[2020]]}},{\"id\":\"b\",\"type\":\"book\",\"title\":\"B\",\"author\":[{\"family\":\"Kz\"}],\"issued\":{\"date-parts\":[[1990]]}},{\"id\":\"c\",\"type\":\"book\",\"title\":\"C\",\"author\":[{\"family\":\"Kádár\"}],\"issued\":{\"literal\":\"寛永某年\"}}]"))

style :: BibliographyStyle Int
style = emptyBibliographyStyle {bsCitationMode = Just "note", bsCitation = Just ["{title}"], bsSubsequent = Just ["{title} at {first-note:kanji}", " / {locator}"], bsLocatorLabels = Map.singleton "page" ("p.", "pp."), bsCitationPrefix = Just "(", bsCitationSuffix = Just ")", bsCitationDelimiter = Just "; ", bsCitationSort = Just "written"}

sp :: SrcSpan
sp = mkSpan (FileId 0) 2 3

resolved :: CslRecord -> Int -> BibliographyCitationUse -> BibliographyCitationRecord Int
resolved record number = BibliographyCitationRecord record style number ""

textOf :: Either Text [CitePiece] -> Either Text Text
textOf = fmap citationText

tests :: TestTree
tests =
  testGroup
    "resolved citation mark composition"
    [ testCase "root ADR 0470 I4/I5: sorted payloads retain explicit direct subsequent targets and literal affixes" $ do
        rs <- records
        case rs of
          a : b : _ -> do
            let affixed = (citeItem "a") {citPrefix = [Text sp "<a>"], citSuffix = [Text sp "&"], citLocator = Just (Locator LocatorPage (LocNumber 5))}
                local = style {bsCitationPrefix = Just "WRONG", bsCitationDelimiter = Just "WRONG"}
                input = [(affixed, (resolved a 9 (BibliographySubsequentCitation 7)) {bcrStyle = local}), (citeItem "b", resolved b 4 BibliographyInitialCitation)]
            textOf (formatBibliographyCitationMark style {bsCitationSort = Just "year"} input) @?= Right "(B; <a>A at 七 / p. 5&)"
          _ -> assertFailure "three source records expected",
      testCase "root ADR 0470 I5: deferred subsequent fragments retain out-of-range S1 identities and notation" $ do
        rs <- records
        case rs of
          a : _ -> do
            let value = (resolved a 8 (BibliographyDeferredSubsequentCitation sp 60)) {bcrStyle = style {bsSubsequent = Just ["see {first-note:circled}"]}}
            formatBibliographyCitationMark style [(citeItem "a", value)] @?= Right [CiteText "(", CiteText "see ", CiteNoteNumber sp 60 (Just "circled") Nothing, CiteText ")"]
          _ -> assertFailure "source record expected",
      testCase "root ADR 0480 I4: author-year uses normalized authors then numeric or literal unknown years stably" $ do
        rs <- records
        case rs of
          a : b : c : _ -> do
            let names = Map.singleton "author" emptyBibliographyNames {bnPartDelimiter = Just ""}
                value record n = (resolved record n BibliographyInitialCitation) {bcrStyle = style {bsNames = names, bsCitation = Just ["{title} {year}"]}}
            textOf (formatBibliographyCitationMark style {bsCitationSort = Just "author-year"} [(citeItem "b", value b 2), (citeItem "a", value a 1), (citeItem "c", value c 3)]) @?= Right "(C 寛永某年; A 2020; B 1990)"
          _ -> assertFailure "three source records expected",
      testCase "root ADR 0470: year-only forms and linked number identities survive common composition" $ do
        rs <- records
        case rs of
          a : _ -> do
            let authorYear = style {bsCitationMode = Just "author-year", bsCitation = Just ["{title} {year}"], bsCitationYear = Just ["{year}"]}
                value = (resolved a 3 BibliographyInitialCitation) {bcrStyle = authorYear, bcrYearSuffix = "b"}
            textOf (formatBibliographyCitationMark authorYear [(citeItem "a", value), (CiteYearItem "a" Nothing [] [], value)]) @?= Right "(A 2020b; 2020b)"
            forM_ [BibliographyInitialCitation, BibliographySubsequentCitation 7, BibliographyDeferredSubsequentCitation sp 7] $ \use ->
              textOf (formatBibliographyCitationMark authorYear [(CiteYearItem "a" Nothing [] [], value {bcrUse = use})]) @?= Right "(2020b)"
            let numeric = style {bsCitationMode = Just "numeric", bsCitation = Just ["{number}"]}
            formatBibliographyCitationMark numeric [(citeItem "a", value {bcrStyle = numeric})] @?= Right [CiteText "(", CiteNumber "a" 3, CiteText ")"]
          _ -> assertFailure "source record expected",
      testCase "root ADR 0475 I4: empty marks and empty pieces have no envelope but literal affixes remain" $ do
        formatBibliographyCitationMark style [] @?= Right []
        rs <- records
        case rs of
          a : _ -> do
            let empty = (resolved a 1 BibliographyInitialCitation) {bcrStyle = style {bsCitation = Just []}}
            formatBibliographyCitationMark style [(citeItem "a", empty)] @?= Right []
            textOf (formatBibliographyCitationMark style [((citeItem "a") {citPrefix = [Text sp "literal"]}, empty)]) @?= Right "(literal)"
          _ -> assertFailure "source record expected",
      testCase "root ADR 0470 I5: direct notation failures retain the existing error" $ do
        rs <- records
        case rs of
          a : _ -> do
            let value = (resolved a 1 (BibliographySubsequentCitation 60)) {bcrStyle = style {bsSubsequent = Just ["{first-note:circled}"]}}
            assertBool "a known direct number outside the notation is rejected" (isLeft (formatBibliographyCitationMark style [(citeItem "a", value)]))
          _ -> assertFailure "source record expected"
    ]
