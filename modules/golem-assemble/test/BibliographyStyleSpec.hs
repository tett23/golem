module BibliographyStyleSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Assemble.BibliographyRecords (formatBibliographyCitationWith)
import Golem.Assemble.BibliographyStyle
import Golem.Bibliography.Csl qualified as Json
import Golem.Doc.Citation (citationText)
import Golem.Doc.IR (Locator (..), LocatorLabel (LocatorPage), LocatorValue (..), locatorLabelName)
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
