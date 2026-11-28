module Bibliography0475Spec (tests) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.BibliographyNames
import Golem.Assemble.BibliographyStyle qualified as D
import Golem.Assemble.CitationFormats
import Golem.Doc.Citation
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "root ADR 0475 prototype"
    [ testCase "root ADR 0475 I4: two items get one literal envelope" $
        citationText (joinBibliographyCitations "(" ")" "; " [[CiteText "A, 2020"], [CiteText "B, 2021"]]) @?= "(A, 2020; B, 2021)",
      testCase "root ADR 0475 I4: per-item brackets retain linked numeric identities" $
        joinBibliographyCitations "" "" ", " [[CiteText "[", CiteNumber "a" 1, CiteText "]"], [CiteText "[", CiteNumber "b" 2, CiteText "]"]] @?= [CiteText "[", CiteNumber "a" 1, CiteText "]", CiteText ", ", CiteText "[", CiteNumber "b" 2, CiteText "]"],
      testCase "root ADR 0475 I4: empty citation content does not emit an envelope" $ do
        joinBibliographyCitations "(" ")" "; " [] @?= []
        joinBibliographyCitations "(" ")" "; " [[CiteText ""]] @?= [],
      testCase "root ADR 0475 I5: book controls and local citation fields stay separate" $ do
        let base = languageBase {D.bsLanguages = Map.fromList [("ja", D.emptyBibliographyStyle {D.bsCitationMode = Just "note", D.bsCitationDelimiter = Just "; ", D.bsCitationPrefix = Just "(", D.bsCitationSuffix = Just ")", D.bsCitation = Just ["Japanese"], D.bsLabel = Just "book-local"}), ("fr", D.emptyBibliographyStyle {D.bsCitationMode = Just "numeric", D.bsCitationDelimiter = Just "WRONG", D.bsCitationPrefix = Just "WRONG", D.bsCitationSuffix = Just "WRONG", D.bsCitation = Just ["French"], D.bsLabel = Just "record-local"})]}
        out <- either (assertFailure . show) pure (D.bibliographyForLanguages "JA" "FR" base)
        (D.bsCitationMode out, D.bsCitationDelimiter out, D.bsCitationPrefix out, D.bsCitationSuffix out, D.bsCitation out, D.bsLabel out) @?= (Just "note", Just "; ", Just "(", Just ")", Just ["French"], Just "record-local"),
      testCase "root ADR 0475 I2: tail-only retention does not rename the original first author" $ do
        initial <- either (assertFailure . T.unpack) pure (parseInitialFormat "{i}.")
        let options = NameFormat FirstFamilyGiven ", " False initial "" (NameListFormat ", " " & " (Just 1) 0 "… ")
            people = [PersonalName (Just "Alpha") (Just "Ann"), PersonalName (Just "Beta") (Just "Bea")]
        formatBibliographyNamesWith (NameListExtras 1 Nothing) options people @?= "… Bea Beta",
      testCase "root ADR 0475 I2: first-family-given retains original positions on both sides" $ do
        initial <- either (assertFailure . T.unpack) pure (parseInitialFormat "{i}.")
        let options = NameFormat FirstFamilyGiven ", " False initial "" (NameListFormat ", " " & " (Just 2) 1 "; …; ")
            people = [PersonalName (Just "Alpha") (Just "Ann"), PersonalName (Just "Beta") (Just "Bea"), PersonalName (Just "Gamma") (Just "Gina")]
        formatBibliographyNamesWith (NameListExtras 1 Nothing) options people @?= "Alpha, Ann; …; Gina Gamma",
      testCase "root ADR 0475 I2: pair and final delimiters depend on original count" $ do
        render (NameListExtras 0 (Just " and ")) unlimited [] @?= ""
        render (NameListExtras 0 (Just " and ")) unlimited ["A"] @?= "A"
        render (NameListExtras 0 (Just " and ")) unlimited ["A", "B"] @?= "A and B"
        render (NameListExtras 0 (Just " and ")) unlimited ["A", "B", "C"] @?= "A, B, and C",
      testCase "root ADR 0475 I3: truncated prefixes never use the last delimiter" $
        render (NameListExtras 0 (Just " and ")) (unlimited {nlMax = Just 2, nlUseFirst = 2, nlEtAl = ", et al."}) ["A", "B", "C"] @?= "A, B, et al.",
      testCase "root ADR 0475 I2: APA keeps the first nineteen and the actual final author" $ do
        let people = [T.pack (show n) | n <- [1 :: Int .. 21]]
            opts = unlimited {nlMax = Just 20, nlUseFirst = 19, nlEtAl = ", …, "}
        render (NameListExtras 1 Nothing) opts people @?= T.intercalate ", " (take 19 people) <> ", …, 21"
        render (NameListExtras 1 Nothing) opts (take 20 people) @?= T.intercalate ", " (take 19 people) <> ", and 20",
      testCase "root ADR 0475 I2: retention boundaries never duplicate names" $
        forM_ [0 .. 6] $ \limit -> forM_ [0 .. limit] $ \first ->
          let lastCount = limit - first; people = map (T.pack . show) [1 .. limit + 1]; opts = NameListFormat "/" "LAST" (Just limit) first "!"
           in render (NameListExtras lastCount (Just "PAIR")) opts people @?= T.intercalate "/" (take first people) <> "!" <> T.intercalate "/" (drop (length people - lastCount) people),
      testCase "root ADR 0475 I3: max zero has no names and literal et-al once" $ do
        let opts = unlimited {nlMax = Just 0, nlUseFirst = 0, nlEtAl = "<et-al>"}
        render (NameListExtras 0 Nothing) opts [] @?= ""
        render (NameListExtras 0 Nothing) opts ["A"] @?= "<et-al>",
      testCase "root ADR 0475 I3: declared extras retain explicit empty pair delimiters" $
        nameListExtras D.emptyBibliographyNames {D.bnUseLast = Just 1, D.bnPairDelimiter = Just ""} @?= NameListExtras 1 (Just ""),
      testCase "root ADR 0475 I5: language overlays are case independent and applied coarse to fine" $
        forM_ ["ja-JP", "JA-jp", "Ja-jP"] $ \tag -> do
          out <- either (assertFailure . show) pure (D.bibliographyForLanguage tag languageBase)
          D.bsCitationDelimiter out @?= Just ""
          D.bsSort out @?= Just []
          D.bsYearSuffix out @?= Just False
          D.bsHangingIndent out @?= Just 0,
      testCase "root ADR 0475 I5: private subtags and component boundaries are exact" $ do
        out <- either (assertFailure . show) pure (D.bibliographyForLanguage "ja-JP-x-example" languageBase)
        D.bsLabel out @?= Just "fine"
        fmap D.bsCitationDelimiter (D.bibliographyForLanguage "jav" languageBase) @?= Right (Just "base"),
      testCase "root ADR 0475 I5: normalized duplicate language keys are rejected" $
        assertBool "collision" (isLeft (D.bibliographyForLanguage "en" (languageBase {D.bsLanguages = Map.fromList [("ja", D.emptyBibliographyStyle), ("JA", D.emptyBibliographyStyle)]})))
    ]

unlimited :: NameListFormat
unlimited = NameListFormat ", " ", and " Nothing 0 "unused"

render :: NameListExtras -> NameListFormat -> [Text] -> Text
render extras opts = formatShortNamesWith extras opts . map LiteralName

languageBase :: D.BibliographyStyle Int
languageBase =
  D.emptyBibliographyStyle
    { D.bsCitationDelimiter = Just "base",
      D.bsLanguages =
        Map.fromList
          [ ("JA", D.emptyBibliographyStyle {D.bsCitationDelimiter = Just "coarse", D.bsYearSuffix = Just False}),
            ("ja-jp", D.emptyBibliographyStyle {D.bsCitationDelimiter = Just "", D.bsSort = Just [], D.bsHangingIndent = Just 0}),
            ("JA-jp-X", D.emptyBibliographyStyle {D.bsLabel = Just "private"}),
            ("ja-JP-x-example", D.emptyBibliographyStyle {D.bsLabel = Just "fine"})
          ]
    }
