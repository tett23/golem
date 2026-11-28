module BibliographyNamesSpec (tests) where

import Data.Either (isLeft)
import Data.Text qualified as T
import Golem.Assemble.BibliographyNames
import Golem.Assemble.BibliographyStyle qualified as Decl
import Test.Tasty
import Test.Tasty.HUnit

initial :: InitialFormat
initial = either (error . show) id (parseInitialFormat "{i}.")

list :: NameListFormat
list = NameListFormat ", " " and " Nothing 1 " et al."

style :: NameFormat
style = NameFormat GivenFamily ", " True initial " " list

name :: String -> String -> BibliographyName
name family given = PersonalName (fromString family) (fromString given)
  where
    fromString = \case "" -> Nothing; value -> Just (T.pack value)

tests :: TestTree
tests =
  testGroup
    "bibliography names"
    [ testCase "root ADR 0470 I6: editor labels distinguish one and three editors" $ do
        bibliographyEditorLabel ("ed.", "eds.") [name "Pavlenko" "Aneta"] @?= Just "ed."
        bibliographyEditorLabel ("ed.", "eds.") [name "A" "One", name "B" "Two", name "C" "Three"] @?= Just "eds.",
      testCase "root ADR 0470 I3: absent and empty editors have no label" $ do
        bibliographyEditorLabel ("ed.", "eds.") [] @?= Nothing
        bibliographyEditorLabel ("ed.", "eds.") [LiteralName "", name "" ""] @?= Nothing,
      testCase "root ADR 0470 I2: an empty name declaration retains the explicit base" $
        applyBibliographyNames id style Decl.emptyBibliographyNames @?= Right style,
      testCase "root ADR 0470 I2: a full name declaration overrides every written option" $ do
        let declaration = Decl.emptyBibliographyNames {Decl.bnOrder = Just "family-given", Decl.bnPartDelimiter = Just "", Decl.bnInitials = Just False, Decl.bnInitialFormat = Just "{i}", Decl.bnInitialDelimiter = Just "", Decl.bnDelimiter = Just "; ", Decl.bnLastDelimiter = Just " & ", Decl.bnMax = Just 2, Decl.bnUseFirst = Just 1, Decl.bnEtAl = Just "others"}
            initials = either (error . show) id (parseInitialFormat "{i}")
            expected = NameFormat FamilyGiven "" False initials "" (NameListFormat "; " " & " (Just 2) 1 " / others")
        applyBibliographyNames (" / " <>) style declaration @?= Right expected,
      testCase "root ADR 0470 I2: explicit zero, false and empty name values survive application" $
        applyBibliographyNames id style Decl.emptyBibliographyNames {Decl.bnInitials = Just False, Decl.bnPartDelimiter = Just "", Decl.bnMax = Just 0, Decl.bnUseFirst = Just 0, Decl.bnDelimiter = Just ""}
          @?= Right style {nfInitials = False, nfPartDelimiter = "", nfList = list {nlMax = Just 0, nlUseFirst = 0, nlDelimiter = ""}},
      testCase "root ADR 0470 I2: et-al preparation is explicit and applied only when written" $ do
        applyBibliographyNameList (" " <>) list Decl.emptyBibliographyNames {Decl.bnEtAl = Just "et al."} @?= list {nlEtAl = " et al."}
        applyBibliographyNameList ("!" <>) list Decl.emptyBibliographyNames @?= list,
      testCase "root ADR 0470 I7: an invalid written name order is rejected" $
        assertBool "unknown order" (isLeft (applyBibliographyNames id style Decl.emptyBibliographyNames {Decl.bnOrder = Just "reversed"})),
      testCase "root ADR 0470 I7: a written initial format is parsed before application" $
        assertBool "unknown initial slot" (isLeft (applyBibliographyNames id style Decl.emptyBibliographyNames {Decl.bnInitialFormat = Just "{unknown}"})),
      testCase "root ADR 0470 I6: IEEE author initials from the primary-source example" $
        formatBibliographyNames style [name "Chiampi" "M. M.", name "Zilberti" "L. L."] @?= "M. M. Chiampi and L. L. Zilberti",
      testCase "root ADR 0470 I6: Vancouver author initials from the primary-source example" $ do
        let initials = either (error . show) id (parseInitialFormat "{i}")
            vancouver = style {nfOrder = FamilyGiven, nfPartDelimiter = " ", nfInitialFormat = initials, nfInitialDelimiter = "", nfList = list {nlLastDelimiter = ", "}}
        formatBibliographyNames vancouver [name "Halpern" "S. D.", name "Ubel" "P. A.", name "Caplan" "A. L."] @?= "Halpern SD, Ubel PA, Caplan AL",
      testCase "root ADR 0470 I2: only the first name is family-given" $
        formatBibliographyNames style {nfOrder = FirstFamilyGiven, nfInitials = False, nfList = list {nlLastDelimiter = " & "}} [name "Heller" "Monica", name "Pavlenko" "Aneta", name "Teutsch-Dwyer" "Marya"] @?= "Heller, Monica, Aneta Pavlenko & Marya Teutsch-Dwyer",
      testCase "root ADR 0470 I2: compact already-written initials are preserved" $
        formatBibliographyNames style [name "Chiampi" "M.M."] @?= "M. M. Chiampi",
      testCase "root ADR 0470 I2: hyphens survive already-written initials" $
        formatBibliographyNames style [name "Smith" "J.-P."] @?= "J.-P. Smith",
      testCase "root ADR 0470 I2: empty hyphen components do not create extra dots" $
        formatBibliographyNames style [name "Smith" "Jean--Pierre"] @?= "J.--P. Smith",
      testCase "root ADR 0470 I2: literal names are not abbreviated or reordered" $
        formatBibliographyNames style [LiteralName "Research Team"] @?= "Research Team",
      testCase "root ADR 0470 I2: missing name parts do not add separators" $ do
        formatBibliographyNames style {nfInitials = False} [name "Smith" ""] @?= "Smith"
        formatBibliographyNames style {nfInitials = False} [name "" "Ann"] @?= "Ann",
      testCase "root ADR 0470 I2: short names use surnames and literal names" $
        formatShortNames list [name "Smith" "Ann", LiteralName "Team"] @?= "Smith and Team",
      testCase "root ADR 0470 I2: an over-limit list uses the explicitly supplied omission suffix" $
        formatShortNames list {nlMax = Just 2, nlUseFirst = 1} [name "A" "One", name "B" "Two", name "C" "Three"] @?= "A et al.",
      testCase "root ADR 0470 I2: exactly the maximum has no omission suffix" $
        formatShortNames list {nlMax = Just 2, nlUseFirst = 1} [name "A" "One", name "B" "Two"] @?= "A and B",
      testCase "root ADR 0470 I2: an empty name list has no text" $
        formatBibliographyNames style [] @?= "",
      testCase "root ADR 0470 I2: combining marks stay with the initial letter" $
        formatBibliographyNames style [PersonalName (Just "Smith") (Just "e\x0301\&mile")] @?= "E\x0301. Smith",
      testCase "root ADR 0470 I2: hyphenated given names retain their hyphen" $
        formatBibliographyNames style [name "Smith" "Jean-Pierre"] @?= "J.-P. Smith",
      testCase "root ADR 0470 I2: an initial preserves an extended grapheme cluster" $
        formatBibliographyNames style [PersonalName (Just "Smith") (Just "👨\x200D\&👩\x200D\&👧\x200D\&👦 Family")] @?= "👨\x200D\&👩\x200D\&👧\x200D\&👦. F. Smith",
      testCase "root ADR 0470 I2: escaped braces remain literal in initial-format" $ do
        let brackets = either (error . show) id (parseInitialFormat "\\{{i}\\}")
        formatBibliographyNames style {nfInitialFormat = brackets} [name "Smith" "John"] @?= "{J} Smith",
      testCase "root ADR 0470 I7: initial-format rejects unknown names and number notations" $
        mapM_ (\source -> assertBool (show source) (isLeft (parseInitialFormat source))) ["{name}", "{i:kanji}", "{i", "{}"]
    ]
