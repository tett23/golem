module BibliographyStyleSpec (tests) where

import Control.Applicative ((<|>))
import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Assemble.BibliographyRecords (formatBibliographyCitationWith, formatBibliographyDeferredSubsequentCitationWithSuffix, formatBibliographySubsequentCitationWithSuffix)
import Golem.Assemble.BibliographyStyle
import Golem.Bibliography.Csl qualified as Json
import Golem.Doc.Citation (CitePiece (..), citationText)
import Golem.Doc.IR (Locator (..), LocatorLabel (LocatorPage), LocatorValue (..), locatorLabelName)
import Golem.Syntax.Span (FileId (..), mkSpan)
import Test.Tasty
import Test.Tasty.HUnit

base :: BibliographyStyle Int
base =
  emptyBibliographyStyle
    { bsCitationMode = Just "author-year",
      bsCitation = Just ["{author}", "{year}"],
      bsCitationDelimiter = Just "; ",
      bsHangingIndent = Just 12,
      bsYearSuffix = Just True,
      bsTypes = Map.singleton "book" (BibliographyType (Just ["{title}"]) (Map.fromList [("title", "italic"), ("author", "roman")])),
      bsNames = Map.singleton "author" emptyBibliographyNames {bnOrder = Just "family-given", bnInitials = Just True, bnDelimiter = Just ", ", bnMax = Just 3}
    }

override :: BibliographyStyle Int
override =
  emptyBibliographyStyle
    { bsCitation = Just [],
      bsCitationDelimiter = Just "",
      bsHangingIndent = Just 0,
      bsYearSuffix = Just False,
      bsTypes = Map.singleton "book" (BibliographyType Nothing (Map.singleton "title" "bold")),
      bsNames = Map.singleton "author" emptyBibliographyNames {bnDelimiter = Just "", bnMax = Just 0}
    }

expected :: BibliographyStyle Int
expected =
  base
    { bsCitation = Just [],
      bsCitationDelimiter = Just "",
      bsHangingIndent = Just 0,
      bsYearSuffix = Just False,
      bsTypes = Map.singleton "book" (BibliographyType (Just ["{title}"]) (Map.fromList [("title", "bold"), ("author", "roman")])),
      bsNames = Map.singleton "author" emptyBibliographyNames {bnOrder = Just "family-given", bnInitials = Just True, bnDelimiter = Just "", bnMax = Just 0}
    }

tests :: TestTree
tests =
  testGroup
    "bibliography declaration overlays"
    $ [ testCase "root ADR 0470 I2: an explicit type wins over types.default" $
          bibliographyTypeFor "book" withDefault @?= Map.lookup "book" (bsTypes base),
        testCase "root ADR 0470 I2: an unknown type uses the explicit default declaration" $
          bibliographyTypeFor "report" withDefault @?= Just fallback,
        testCase "root ADR 0470 I2: a known empty type does not inherit default pieces" $
          bibliographyTypeFor "report" (withDefault {bsTypes = Map.insert "report" (BibliographyType (Just []) Map.empty) (bsTypes withDefault)}) @?= Just (BibliographyType (Just []) Map.empty),
        testCase "root ADR 0470 I2: no type and no default leaves the type unresolved" $
          bibliographyTypeFor "report" base @?= Nothing,
        testCase "root ADR 0470 I2: scalar overlays retain explicit empty, zero and false values" $ do
          let merged = overlayBibliographyStyle base override
          bsCitationMode merged @?= Just "author-year"
          bsCitation merged @?= Just []
          bsCitationDelimiter merged @?= Just ""
          bsHangingIndent merged @?= Just 0
          bsYearSuffix merged @?= Just False,
        testCase "root ADR 0470 I2: type overlays merge fields without losing inherited pieces" $
          Map.lookup "book" (bsTypes (overlayBibliographyStyle base override)) @?= Just (BibliographyType (Just ["{title}"]) (Map.fromList [("title", "bold"), ("author", "roman")])),
        testCase "root ADR 0470 I2: name overlays change only written options" $ do
          let merged = Map.lookup "author" (bsNames (overlayBibliographyStyle base override))
          fmap bnOrder merged @?= Just (Just "family-given")
          fmap bnInitials merged @?= Just (Just True)
          fmap bnDelimiter merged @?= Just (Just "")
          fmap bnMax merged @?= Just (Just 0),
        testCase "root ADR 0470 I2: language overlays merge nested partial declarations" $ do
          let first = base {bsLanguages = Map.singleton "ja" base}
              second = emptyBibliographyStyle {bsLanguages = Map.singleton "ja" override}
          Map.lookup "ja" (bsLanguages (overlayBibliographyStyle first second)) @?= Just expected,
        testCase "root ADR 0470 I2: an empty overlay is the identity on either side" $ do
          overlayBibliographyStyle base emptyBibliographyStyle @?= base
          overlayBibliographyStyle emptyBibliographyStyle base @?= base,
        testCase "root ADR 0470 I2: declaration overlay composition is associative" $
          mapM_ (\(a, b, c) -> overlayBibliographyStyle (overlayBibliographyStyle a b) c @?= overlayBibliographyStyle a (overlayBibliographyStyle b c)) [(a, b, c) | a <- [emptyBibliographyStyle, base, override], b <- [emptyBibliographyStyle, base, override], c <- [emptyBibliographyStyle, base, override]]
      ]
      <> locatorTests
      <> subsequentTests

-- Defaults here are explicit test declarations, never application defaults.
fallback :: BibliographyType
fallback = BibliographyType (Just ["{author}", "{title}"]) (Map.singleton "title" "italic")

withDefault :: BibliographyStyle Int
withDefault = base {bsTypes = Map.insert "default" fallback (bsTypes base)}

locatorTests :: [TestTree]
locatorTests =
  [ testCase "root ADR 0480 I2: every locator preserves explicit position delimiter and plurality" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\"}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      forM_ [(label, position, delimiter, value, word, rendered) | label <- [minBound .. maxBound], position <- ["before", "after"], delimiter <- ["", " ", " | "], (value, word, rendered) <- [(LocNumber 5, "one", "5"), (LocRange 5 7, "many", "5–7"), (LocRange 5 5, "one", "5"), (LocText "xii", "one", "xii")]] $ \(label, position, delimiter, value, word, rendered) -> do
        let kind = locatorLabelName label
            declaration = locatorStyle {bsLocatorLabels = Map.singleton kind ("one", "many"), bsLocatorPositions = Map.singleton kind position, bsLocatorDelimiters = Map.singleton kind delimiter}
            expectedText = if position == "before" then word <> delimiter <> rendered else rendered <> delimiter <> word
        pieces <- either (locatorFailure . T.unpack) pure (formatBibliographyCitationWith declaration 1 (Just (Locator label value)) record)
        citationText pieces @?= expectedText,
    testCase "root ADR 0480 I2: record language overlays locator position and delimiter independently" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\"}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      let declaration = locatorStyle {bsLocatorLabels = Map.singleton "page" ("p.", "pp."), bsLanguages = Map.fromList [("ja", emptyBibliographyStyle {bsLocatorLabels = Map.singleton "page" ("頁", "頁"), bsLocatorPositions = Map.singleton "page" "after", bsLocatorDelimiters = Map.singleton "page" ""}), ("ja-JP", emptyBibliographyStyle {bsLocatorDelimiters = Map.singleton "page" " | "})]}
      forM_ [("en", "JA-jp", "5 | 頁"), ("ja", "en", "p. 5")] $ \(bookLanguage, recordLanguage, expectedText) -> do
        effective <- either (locatorFailure . show) pure (bibliographyForLanguages bookLanguage recordLanguage declaration)
        pieces <- either (locatorFailure . T.unpack) pure (formatBibliographyCitationWith effective 1 (Just (Locator LocatorPage (LocNumber 5))) record)
        citationText pieces @?= expectedText
  ]

locatorStyle :: BibliographyStyle Int
locatorStyle = emptyBibliographyStyle {bsCitationMode = Just "numeric", bsCitation = Just ["{locator}"], bsPageRange = Just "full", bsRangeDelimiter = Just "–"}

locatorFailure :: String -> IO a
locatorFailure message = assertFailure message >> fail message

subsequentTests :: [TestTree]
subsequentTests =
  [ testCase "root ADR 0470 I5: deferred first-note slots keep their identity, separate notations and surrounding literals" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\",\"first-note\":99}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      let target = mkSpan (FileId 7) 30 40
          declaration = locatorStyle {bsCitationMode = Just "note", bsSubsequent = Just ["({first-note:kanji})/{first-note:ordinal-en}/{first-note}"]}
      formatBibliographyDeferredSubsequentCitationWithSuffix "" (target, 12) declaration 1 Nothing record
        @?= Right [CiteText "(", CiteNoteNumber target 12 (Just "kanji") (Just "十二"), CiteText ")/", CiteNoteNumber target 12 (Just "ordinal-en") (Just "12th"), CiteText "/", CiteNoteNumber target 12 Nothing (Just "12")],
    testCase "root ADR 0470 I5: an initially unwritable deferred first-note retains its notation instead of failing early" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\"}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      let target = mkSpan (FileId 7) 30 40
          declaration = locatorStyle {bsCitationMode = Just "note", bsSubsequent = Just ["{first-note:circled}"]}
      formatBibliographyDeferredSubsequentCitationWithSuffix "" (target, 60) declaration 1 Nothing record @?= Right [CiteNoteNumber target 60 (Just "circled") Nothing]
      assertBool "the old formatter still reports its range error" (either (const True) (const False) (formatBibliographySubsequentCitationWithSuffix "" 60 declaration 1 Nothing record)),
    testCase "root ADR 0470 I5: deferred templates keep conditional omission, optional fields and an explicit empty template" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\"}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      let target = mkSpan (FileId 7) 30 40
          declaration = locatorStyle {bsCitationMode = Just "note", bsSubsequent = Just ["{title}{first-note:circled}", "{first-note?:kanji}", "{!first-note}wrong", "{!DOI}({first-note})"]}
      formatBibliographyDeferredSubsequentCitationWithSuffix "" (target, 60) declaration 1 Nothing record
        @?= Right [CiteNoteNumber target 60 (Just "kanji") (Just "六十"), CiteText "(", CiteNoteNumber target 60 Nothing (Just "60"), CiteText ")"]
      formatBibliographyDeferredSubsequentCitationWithSuffix "" (target, 60) declaration {bsSubsequent = Just []} 1 Nothing record @?= Right [],
    testCase "root ADR 0470 I5: deferred selection retains type and global fallbacks including empty templates" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\",\"type\":\"book\"}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      let target = mkSpan (FileId 7) 30 40
      forM_ [(tables, typed, later, initial) | tables <- [[], ["book"], ["default"], ["book", "default"]], typed <- choices "typed{first-note:kanji}", later <- choices "subsequent{first-note}", initial <- choices "initial{first-note:ordinal-en}"] $ \(tables, typed, later, initial) -> do
        let selected = case tables of [] -> Nothing; first : _ -> Just first
            metadata kind = emptyBibliographyTypeCitations {btcSubsequent = if Just kind == selected then typed else Just ["wrong"]}
            declaration = locatorStyle {bsCitationMode = Just "note", bsCitation = initial, bsSubsequent = later, bsTypes = Map.fromList [(kind, BibliographyType (Just []) Map.empty) | kind <- tables], bsTypeCitations = Map.fromList [(kind, metadata kind) | kind <- tables]}
            actual = formatBibliographyDeferredSubsequentCitationWithSuffix "" (target, 3) declaration 1 Nothing record
        fmap citationText actual @?= fmap citationText (formatBibliographySubsequentCitationWithSuffix "" 3 declaration 1 Nothing record)
        case actual of
          Right pieces -> assertBool "surviving fields retain identity" (all (\case CiteText text -> not ("三" `T.isInfixOf` text || "3" `T.isInfixOf` text); _ -> True) pieces)
          Left _ -> pure (),
    testCase "root ADR 0470 I5: deferred first-note does not defer other range errors or accept an unknown notation" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\",\"edition\":60}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      let target = mkSpan (FileId 7) 30 40
          declaration = locatorStyle {bsCitationMode = Just "note"}
      forM_ ["{first-note}/{edition:circled}", "{first-note:unknown}"] $ \source -> do
        let selected = declaration {bsSubsequent = Just [source]}
        formatBibliographyDeferredSubsequentCitationWithSuffix "" (target, 12) selected 1 Nothing record @?= formatBibliographySubsequentCitationWithSuffix "" 12 selected 1 Nothing record
      forM_ ["numeric", "author-year"] $ \mode -> do
        let selected = declaration {bsCitationMode = Just mode, bsCitation = Just ["{number}"], bsSubsequent = Just ["{first-note}"]}
        formatBibliographyDeferredSubsequentCitationWithSuffix "" (target, 12) selected 1 Nothing record @?= formatBibliographyCitationWith selected 1 Nothing record,
    testCase "root ADR 0470 I5: raw CSL cannot supply the derived first-note outside a subsequent note" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\",\"first-note\":99}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      forM_ ["note", "numeric", "author-year"] $ \mode -> do
        let declaration = locatorStyle {bsCitationMode = Just mode, bsCitation = Just ["{first-note}"]}
        fmap citationText (formatBibliographyCitationWith declaration 1 Nothing record) @?= Right "",
    testCase "root ADR 0480 I3: subsequent templates use the selected type then global subsequent then global citation" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\",\"type\":\"book\"}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      forM_ [(tables, typed, later, initial) | tables <- [[], ["book"], ["default"], ["book", "default"]], typed <- choices "typed", later <- choices "subsequent", initial <- choices "initial"] $ \(tables, typed, later, initial) -> do
        let selected = case tables of [] -> Nothing; first : _ -> Just first
            metadata kind = emptyBibliographyTypeCitations {btcCitation = Just ["wrong-type-initial"], btcSubsequent = if Just kind == selected then typed else Just ["wrong-default-subsequent"]}
            declaration = locatorStyle {bsCitationMode = Just "note", bsCitation = initial, bsSubsequent = later, bsTypes = Map.fromList [(kind, BibliographyType (Just []) Map.empty) | kind <- tables], bsTypeCitations = Map.fromList [(kind, metadata kind) | kind <- tables]}
            effectiveTyped = selected >> typed
            expectedText = maybe (Left "citation がありません") (Right . T.concat) (effectiveTyped <|> later <|> initial)
        fmap citationText (formatBibliographySubsequentCitationWithSuffix "" 3 declaration 1 Nothing record) @?= expectedText,
    testCase "root ADR 0470 I5: the caller supplies the first displayed note number and its explicit notation" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\",\"first-note\":99}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      let declaration = locatorStyle {bsCitationMode = Just "note", bsCitation = Just ["initial"], bsSubsequent = Just ["Note {first-note:kanji}"]}
      fmap citationText (formatBibliographySubsequentCitationWithSuffix "" 3 declaration 1 Nothing record) @?= Right "Note 三",
    testCase "root ADR 0470 I5: subsequent selection does not alter non-note citations" $ do
      records <- either (locatorFailure . show) pure (Json.decodeCslRecords "[{\"id\":\"a\"}]")
      record <- case records of [one] -> pure one; _ -> locatorFailure "one record required"
      forM_ ["numeric", "author-year"] $ \mode -> do
        let declaration = locatorStyle {bsCitationMode = Just mode, bsCitation = Just ["normal"], bsSubsequent = Just ["wrong"]}
        fmap citationText (formatBibliographySubsequentCitationWithSuffix "" 3 declaration 1 Nothing record) @?= Right "normal"
  ]

choices :: T.Text -> [Maybe [T.Text]]
choices literal = [Nothing, Just [], Just [literal]]
