module BibliographyNoteTableSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Assemble
import Golem.Assemble.BibliographyCitations
import Golem.Assemble.BibliographyNoteContext
import Golem.Assemble.BibliographyNotes (prepareBibliographyNotes)
import Golem.Assemble.BibliographyStyle
import Golem.Bibliography.Csl (CslRecord, decodeCslRecords)
import Golem.Doc.Citation (CitePiece (..), citationText)
import Golem.Doc.IR
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = mkSpan (FileId 1) 10 20

style :: BibliographyStyle Int
style = emptyBibliographyStyle {bsCitationMode = Just "note", bsCitation = Just ["{title}"], bsSubsequent = Just ["{title} at {first-note:kanji}"], bsCitationPrefix = Just "(", bsCitationSuffix = Just ")", bsCitationDelimiter = Just "; ", bsCitationSort = Just "written", bsLocatorLabels = Map.singleton "page" ("p.", "pp.")}

withRecords :: (CslRecord -> CslRecord -> Assertion) -> Assertion
withRecords action = case decodeCslRecords "[{\"id\":\"a\",\"type\":\"book\",\"title\":\"A\",\"issued\":{\"date-parts\":[[2020]]}},{\"id\":\"b\",\"type\":\"book\",\"title\":\"B\",\"issued\":{\"date-parts\":[[1990]]}}]" of
  Right [a, b] -> action a b
  other -> assertFailure (show other)

resolved :: CslRecord -> BibliographyCitationRecord Int
resolved record = BibliographyCitationRecord record style 1 "" BibliographyInitialCitation

paragraph :: [Inline] -> Block
paragraph xs = Block sp Nothing Nothing (Paragraph Nothing xs)

document :: [Inline] -> Document
document xs = Document (FileId 1) [paragraph xs]

note :: NoteChannelKind -> Int -> [Inline] -> Inline
note channel n xs = (case channel of FootnoteChannel -> Note; SidenoteChannel -> Sidenote; EndnoteChannel -> Endnote) sp n Nothing (noteBody sp xs)

context :: NoteChannelKind -> Int -> Int -> NoteCitationContext
context = NoteCitationContext sp

tests :: TestTree
tests =
  testGroup
    "S1 note citation table producer"
    [ testCase "root ADR 0470 I5: shared spans and items are formatted by stable S1 note and occurrence" $ withRecords $ \a _ ->
        forM_ [FootnoteChannel, SidenoteChannel, EndnoteChannel] $ \channel -> do
          let mark = Cite sp [citeItem "a"]
              cfg = AssembleConfig Map.empty "{n}" Map.empty NumberPerBook [] "{n}" "{n}" Map.empty 16 NumberPerBook
              (book, diagnostics) = assemble cfg (\_ _ _ -> Right "") [document [note channel 0 [mark, mark], note channel 0 [mark]]]
              resolver occurrence _ _ = let c = ncoContext occurrence in Right (resolved a) {bcrStyle = style {bsCitation = Just [T.pack (show (nccNumber c, nccOccurrence c)) <> ":{title}"]}}
              expected = Map.fromList [(context channel n ordinal, (sp, [citeItem "a"], "(" <> T.pack (show (n, ordinal)) <> ":A)")) | (n, ordinal) <- [(1, 0), (1, 1), (2, 0)]]
              result = formatBibliographyNoteCitations style resolver (bookDocs book)
          diagnostics @?= []
          fmap (Map.map (\(at, items, pieces) -> (at, items, citationText pieces))) result @?= Right expected
          case result of
            Left problem -> assertFailure (show problem)
            Right table -> do
              let completed = book {bookNoteCitationPieces = table}
              forM_ (Map.toList expected) $ \(c, (_, items, text)) -> fmap citationText (resolvedNoteCitationPieces completed c sp items) @?= Just text,
      testCase "root ADR 0470 I5 and root ADR 0482: prepared citations reach the S1 table in body and caption containers" $ withRecords $ \a _ ->
        forM_ [(channel, name, site) | (channel, name) <- [(FootnoteChannel, "footnote"), (EndnoteChannel, "endnote")], site <- [0 :: Int .. 5]] $ \(channel, name, site) -> do
          let mark = Cite sp [citeItem "a"]
              body = case site of
                1 -> TableBlock ((plainTable [AlignLeft] [] [[[mark]]]) {tableNoNumber = True})
                2 -> TableBlock ((plainTable [AlignLeft] [] [[[Text sp "cell"]]]) {tableCaption = Just [mark], tableNoNumber = True})
                3 -> CodeBlock (Code Nothing Nothing Nothing (Just [mark]) True [] False)
                4 -> Paragraph Nothing [Ruby sp () [RubySegment [mark] (Just "a")]]
                5 -> TableBlock ((plainTable [AlignLeft] [[mark]] []) {tableNoNumber = True})
                _ -> Paragraph Nothing [mark]
              selected = style {bsNoteChannel = Just name}
              prepared = prepareBibliographyNotes selected [Document (FileId 1) [Block sp Nothing Nothing body]]
              cfg = AssembleConfig Map.empty "{n}" Map.empty NumberPerBook [] "{n}" "{n}" Map.empty 16 NumberPerBook
              (book, diagnostics) = assemble cfg (\_ _ _ -> Right "") prepared
          diagnostics @?= []
          bookCitationItems book @?= [(sp, [citeItem "a"])]
          case formatBibliographyNoteCitations selected (\_ _ _ -> Right (resolved a)) (bookDocs book) of
            Left problem -> assertFailure (show problem)
            Right table -> do
              Map.keys table @?= [context channel 1 0]
              fmap citationText (resolvedNoteCitationPieces book {bookNoteCitationPieces = table} (context channel 1 0) sp [citeItem "a"]) @?= Just "(A)",
      testCase "root ADR 0470 I5: repeated documents keep reset numbers with independent record resolutions" $ withRecords $ \a b -> do
        let cfg = AssembleConfig Map.empty "{n}" Map.empty NumberPerChapter [] "{n}" "{n}" Map.empty 16 NumberPerChapter
            (book, diagnostics) = assemble cfg (\_ _ _ -> Right "") (replicate 2 (document [note FootnoteChannel 0 [Cite sp [citeItem "a"]]]))
            resolver occurrence _ _ = case ncoContext occurrence of
              NoteCitationContextInDocument {nccDocumentIndex = 0} -> Right (resolved a)
              NoteCitationContextInDocument {nccDocumentIndex = 1} -> Right (resolved b)
              _ -> Left "document identity missing"
        diagnostics @?= []
        fmap (Map.map (\(_, _, pieces) -> citationText pieces)) (formatBibliographyNoteCitations style resolver (bookDocs book)) @?= Right (Map.fromList [(NoteCitationContextInDocument sp FootnoteChannel 1 0 0, "(A)"), (NoteCitationContextInDocument sp FootnoteChannel 1 0 1, "(B)")]),
      testCase "root ADR 0470 I5: identical items in one mark retain independent explicit item ordinals" $ withRecords $ \a _ -> do
        let items = replicate 2 (citeItem "a")
            resolver _ ordinal _ = Right (resolved a) {bcrUse = if ordinal == 0 then BibliographyInitialCitation else BibliographySubsequentCitation 7}
        fmap (Map.map (\(_, source, pieces) -> (source, citationText pieces))) (formatBibliographyNoteCitations style resolver [document [note FootnoteChannel 1 [Cite sp items]]]) @?= Right (Map.singleton (context FootnoteChannel 1 0) (items, "(A; A at 七)")),
      testCase "root ADR 0470 I4: citation sorting preserves original lookup payload and literal affixes" $ withRecords $ \a b -> do
        let first = (citeItem "a") {citPrefix = [Text sp "<a>"], citSuffix = [Text sp "!"], citLocator = Just (Locator LocatorPage (LocNumber 5))}
            second = (citeItem "b") {citPrefix = [Text sp "<b>"], citSuffix = [Text sp "&"], citLocator = Just (Locator LocatorPage (LocNumber 8))}
            items = [first, second]
            local record = (resolved record) {bcrStyle = style {bsCitation = Just ["{title}", " / {locator}"], bsSubsequent = Just ["{title} at {first-note:kanji}", " / {locator}"], bsCitationPrefix = Just "WRONG", bsCitationDelimiter = Just "WRONG"}}
            resolver _ ordinal item = Right (local (if citKey item == "a" then a else b)) {bcrUse = if ordinal == 0 then BibliographySubsequentCitation 7 else BibliographyInitialCitation}
            result = formatBibliographyNoteCitations style {bsCitationSort = Just "year"} resolver [document [note EndnoteChannel 1 [Cite sp items]]]
        fmap (Map.map (\(at, source, pieces) -> (at, source, citationText pieces))) result @?= Right (Map.singleton (context EndnoteChannel 1 0) (sp, items, "(<b>B / p. 8&; <a>A at 七 / p. 5!)")),
      testCase "root ADR 0470 I5: explicit deferred first-note targets reach the consumer table without premature range errors" $ withRecords $ \a _ -> do
        let target = mkSpan (FileId 9) 80 90
            value = (resolved a) {bcrStyle = style {bsSubsequent = Just ["see {first-note:circled}"]}, bcrUse = BibliographyDeferredSubsequentCitation target 60}
        formatBibliographyNoteCitations style (\_ _ _ -> Right value) [document [note FootnoteChannel 2 [Cite sp [citeItem "a"]]]] @?= Right (Map.singleton (context FootnoteChannel 2 0) (sp, [citeItem "a"], [CiteText "(", CiteText "see ", CiteNoteNumber target 60 (Just "circled") Nothing, CiteText ")"])),
      testCase "root ADR 0470 I2: year form and supplied suffix retain their distinct lookup payload" $ withRecords $ \a _ -> do
        let item = CiteYearItem "a" Nothing [] []
            effective = style {bsCitationMode = Just "author-year", bsCitationYear = Just ["{year}"]}
            value = (resolved a) {bcrStyle = effective, bcrYearSuffix = "b"}
        fmap (Map.map (\(_, items, pieces) -> (items, citationText pieces))) (formatBibliographyNoteCitations effective (\_ _ _ -> Right value) [document [note FootnoteChannel 1 [Cite sp [item]]]]) @?= Right (Map.singleton (context FootnoteChannel 1 0) ([item], "(2020b)")),
      testCase "root ADR 0470 I5: resolver and formatter errors retain the first failing structural context" $ withRecords $ \a _ -> do
        let missingSpan = mkSpan (FileId 1) 30 40
            docs = [document [note FootnoteChannel 1 [Cite sp [citeItem "a"], Cite missingSpan [citeItem "missing"]]]]
            resolver _ _ item
              | citKey item == "a" = Right (resolved a)
              | otherwise = Left "missing record"
        formatBibliographyNoteCitations style resolver docs @?= Left (NoteCitationOccurrence (context FootnoteChannel 1 1) missingSpan [citeItem "missing"], "missing record")
        let invalid = (resolved a) {bcrStyle = style {bsSubsequent = Just ["{first-note:circled}"]}, bcrUse = BibliographySubsequentCitation 60}
        case formatBibliographyNoteCitations style (\_ _ _ -> Right invalid) docs of
          Left (at, message) -> do
            at @?= NoteCitationOccurrence (context FootnoteChannel 1 0) sp [citeItem "a"]
            assertBool "the existing formatter error is retained" (not (T.null message))
          Right _ -> assertFailure "out-of-range direct notation must fail",
      testCase "root ADR 0470 I5: outside-note and raw ruby citations do not invoke the note resolver" $
        formatBibliographyNoteCitations style (\_ _ _ -> Left "must not be called") [document [Cite sp [citeItem "a"], Ruby sp () [RubySegment [Cite sp [citeItem "a"]] (Just "a")]]] @?= Right Map.empty
    ]
