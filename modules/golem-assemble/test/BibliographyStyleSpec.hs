module BibliographyStyleSpec (tests) where

import Data.Map.Strict qualified as Map
import Golem.Assemble.BibliographyStyle
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
    [ testCase "root ADR 0470 I2: an explicit type wins over types.default" $
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

-- Defaults here are explicit test declarations, never application defaults.
fallback :: BibliographyType
fallback = BibliographyType (Just ["{author}", "{title}"]) (Map.singleton "title" "italic")

withDefault :: BibliographyStyle Int
withDefault = base {bsTypes = Map.insert "default" fallback (bsTypes base)}
