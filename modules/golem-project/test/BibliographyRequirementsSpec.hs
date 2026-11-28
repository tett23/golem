module BibliographyRequirementsSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Assemble.BibliographyStyle
import Golem.Project.BibliographyRequirements
import Test.Tasty
import Test.Tasty.HUnit
import Toml.Schema (Scope (..))

tests :: TestTree
tests =
  testGroup
    "root ADR 0475 requirements"
    ( [ testCase "root ADR 0475 I1: unused declarations are still checked" $
          assertBool "missing mode" (any (\(_, _, path, _) -> path == map ScopeKey ["bibliography", "styles", "unused", "citation-mode"]) (bibliographyAllRequiredChecks (Bibliography "golem" (Map.singleton "unused" emptyBibliographyStyle :: Map.Map Text (BibliographyStyle Int))))),
        testCase "root ADR 0475 I5: language collisions carry the original key paths" $
          let style = base {bsLanguages = Map.fromList [("ja", emptyBibliographyStyle), ("JA", emptyBibliographyStyle)]}
           in map (\(_, _, path, _) -> path) (bibliographyAllRequiredChecks (Bibliography "golem" (Map.singleton "mine" style))) @?= map (map ScopeKey) [["bibliography", "styles", "mine", "languages", "JA"], ["bibliography", "styles", "mine", "languages", "ja"]],
        testCase "root ADR 0475 I1: a partial language override is checked after inheritance" $
          let style = base {bsLanguages = Map.singleton "en" emptyBibliographyStyle {bsCitationMode = Just "author-year"}}
           in assertBool "language citation-year" (any (\(_, _, path, _) -> path == map ScopeKey ["bibliography", "styles", "mine", "languages", "en", "citation-year"]) (bibliographyAllRequiredChecks (Bibliography "golem" (Map.singleton "mine" style))))
      ]
        <> [ testCase ("root ADR 0475 I1: mandatory " <> show key) $
               assertContains key (paths (remove base))
           | (key, remove) <- required
           ]
        <> [ testCase "root ADR 0475 I1: explicit empty arrays remain present" $
               paths base @?= [],
             testCase "root ADR 0475 I1: author-year and language sort have conditional requirements" $ do
               assertContains "citation-year" (paths base {bsCitationMode = Just "author-year"})
               assertContains "language-order" (paths base {bsSort = Just ["language"]}),
             testCase "root ADR 0480 I1: author sorting requires its own separator without name rendering" $
               mapM_
                 (\style -> paths style @?= ["names.author.part-delimiter"])
                 [base {bsSort = Just ["author"]}, base {bsCitationSort = Just "author-year"}],
             testCase "root ADR 0480 I1: sorting alone requires no name-rendering options and keeps an empty separator" $
               paths base {bsSort = Just ["author"], bsNames = Map.singleton "author" emptyBibliographyNames {bnPartDelimiter = Just ""}} @?= [],
             testCase "root ADR 0480 I1: given-family rendering still needs the explicit author sort separator" $ do
               let names = emptyBibliographyNames {bnOrder = Just "given-family", bnInitials = Just False, bnDelimiter = Just ", ", bnLastDelimiter = Just " and "}
                   style = base {bsSort = Just ["author"], bsTypes = Map.singleton "book" (BibliographyType (Just ["{author}"]) Map.empty), bsNames = Map.singleton "author" names}
               paths style @?= ["names.author.part-delimiter"]
               paths style {bsNames = Map.singleton "author" names {bnPartDelimiter = Just " "}} @?= [],
             testCase "root ADR 0480 I1: final book and record languages cannot borrow a different language separator" $ do
               let japanese = emptyBibliographyStyle {bsCitationSort = Just "author-year", bsNames = Map.singleton "author" emptyBibliographyNames {bnPartDelimiter = Just ""}}
                   style = base {bsLanguages = Map.singleton "ja" japanese}
               bibliographyAllRequiredChecks (Bibliography "mine" (Map.singleton "mine" style)) @?= []
               combined <- either (\problem -> assertFailure (show problem) >> pure base) pure (bibliographyForLanguages "ja" "en" style)
               paths combined @?= ["names.author.part-delimiter"],
             testCase "root ADR 0480 I1: author rendering and sorting report one missing separator" $ do
               let names = emptyBibliographyNames {bnOrder = Just "family-given", bnInitials = Just False, bnDelimiter = Just ", ", bnLastDelimiter = Just " and "}
               paths base {bsSort = Just ["author"], bsTypes = Map.singleton "book" (BibliographyType (Just ["{author}"]) Map.empty), bsNames = Map.singleton "author" names} @?= ["names.author.part-delimiter"],
             testCase "root ADR 0475 I1: optional author slots require short-name options before omission" $ do
               let style = base {bsCitation = Just ["{author?}"]}
               assertContains "names.short.delimiter" (paths style)
               assertContains "names.short.last-delimiter" (paths style),
             testCase "root ADR 0475 I1: full names require order, initials and conditional initial fields" $ do
               let names = emptyBibliographyNames {bnOrder = Just "family-given", bnInitials = Just True, bnDelimiter = Just ", ", bnLastDelimiter = Just " and "}
                   style = base {bsCitationMode = Just "note", bsCitation = Just ["{author}"], bsNames = Map.singleton "author" names}
               mapM_ (\key -> assertContains ("names.author." <> key) (paths style)) ["part-delimiter", "initial-format", "initial-delimiter"],
             testCase "root ADR 0475 I1: name limits require explicit first and literal marker" $ do
               let style = base {bsNames = Map.singleton "short" emptyBibliographyNames {bnMax = Just 2}}
               assertContains "names.short.use-first" (paths style)
               assertContains "names.short.et-al" (paths style),
             testCase "root ADR 0475 I1: unbounded names reject retention-only options" $ do
               let style = base {bsNames = Map.singleton "short" emptyBibliographyNames {bnUseFirst = Just 1, bnUseLast = Just 0, bnEtAl = Just ""}}
               mapM_ (\key -> assertContains ("names.short." <> key) (paths style)) ["use-first", "use-last", "et-al"],
             testCase "root ADR 0475 I1: maximum retention sums do not overflow" $ do
               let names = emptyBibliographyNames {bnMax = Just 2147483647, bnUseFirst = Just 2147483647, bnUseLast = Just 1, bnEtAl = Just ""}
               assertContains "names.short.use-last" (paths base {bsNames = Map.singleton "short" names})
               paths base {bsNames = Map.singleton "short" names {bnUseLast = Just 0}} @?= [],
             testCase "root ADR 0475 I1: declared type tables require pieces even when empty is valid" $ do
               let style = base {bsTypes = Map.singleton "book" (BibliographyType Nothing Map.empty)}
               assertContains "types.book.pieces" (paths style)
               paths style {bsTypes = Map.singleton "book" (BibliographyType (Just []) Map.empty)} @?= [],
             testCase "root ADR 0475 I1: used types need a matching or explicit default declaration" $ do
               assertContains "types.book" (pathsFor (BibliographyUse (Just ["book"]) []) base)
               pathsFor (BibliographyUse (Just ["book"]) []) base {bsTypes = Map.singleton "default" (BibliographyType (Just []) Map.empty)} @?= [],
             testCase "root ADR 0475 I1: declared type references are checked even without a list" $ do
               let style = base {bsTypes = Map.singleton "book" (BibliographyType (Just ["{author}"]) Map.empty)}
               paths base @?= []
               assertContains "names.author.order" (paths style)
               assertContains "names.author.order" (pathsFor (BibliographyUse (Just ["book"]) []) style),
             testCase "root ADR 0475 I1: used locator labels and editor labels are required" $ do
               assertContains "locator-labels.chapter" (pathsFor (BibliographyUse Nothing ["chapter"]) base {bsCitation = Just ["{locator}"]})
               assertContains "names.editor.label" (paths base {bsCitation = Just ["{editor-label}"]})
           ]
    )

base :: BibliographyStyle Int
base = emptyBibliographyStyle {bsCitationMode = Just "numeric", bsCitation = Just [], bsCitationDelimiter = Just "", bsCitationSort = Just "written", bsSort = Just [], bsHangingIndent = Just 0, bsYearSuffix = Just False, bsPageRange = Just "full", bsRangeDelimiter = Just "–"}

required :: [(Text, BibliographyStyle Int -> BibliographyStyle Int)]
required = [("citation-mode", \s -> s {bsCitationMode = Nothing}), ("citation", \s -> s {bsCitation = Nothing}), ("citation-delimiter", \s -> s {bsCitationDelimiter = Nothing}), ("citation-sort", \s -> s {bsCitationSort = Nothing}), ("sort", \s -> s {bsSort = Nothing}), ("hanging-indent", \s -> s {bsHangingIndent = Nothing}), ("year-suffix", \s -> s {bsYearSuffix = Nothing}), ("page-range", \s -> s {bsPageRange = Nothing}), ("range-delimiter", \s -> s {bsRangeDelimiter = Nothing})]

paths :: BibliographyStyle Int -> [Text]
paths = pathsFor (BibliographyUse Nothing [])

pathsFor :: BibliographyUse -> BibliographyStyle Int -> [Text]
pathsFor use style = [foldPath (drop 3 path) | (code, _, path, _) <- bibliographyRequiredChecks "mine" use style, code == "G03006"]

foldPath :: [Scope] -> Text
foldPath = foldr (\scope rest -> case scope of ScopeKey key -> key <> (if rest == "" then "" else "." <> rest); ScopeIndex _ -> rest) ""

assertContains :: Text -> [Text] -> Assertion
assertContains key result = assertBool (show (key, result)) (key `elem` result)
