module BibliographySortSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Assemble.BibliographyNames (BibliographyName (..))
import Golem.Assemble.BibliographySort
import Test.Tasty
import Test.Tasty.HUnit

entry :: String -> SortFields
entry = \case
  "a" -> SortFields "alpha" (Just 2020) "Z" "en-US" 2
  "b" -> SortFields "beta" (Just 2010) "A" "ja" 0
  "c" -> SortFields "alpha" (Just 2010) "B" "fr" 1
  _ -> SortFields "alpha" (Just 2020) "Z" "en-GB" 3

tests :: TestTree
tests =
  testGroup
    "bibliography sorting"
    [ testCase "root ADR 0470 I7: unkeyed Han and kana surnames need a warning" $
        forM_ ["山田", "やまだ", "ヤマダ", "ﾔﾏﾀﾞ", "𠮷田", "Smith山田"] $ \family ->
          assertBool (show family) (authorNeedsSortKeyWarning True ["author", "year"] Nothing (Just (PersonalName (Just family) Nothing))),
      testCase "root ADR 0470 I7: other scripts and emoji do not need a reading warning" $
        forM_ ["Smith", "김", "Παπα", "🙂"] $ \family ->
          assertBool (show family) (not (authorNeedsSortKeyWarning True ["author"] Nothing (Just (PersonalName (Just family) Nothing)))),
      testCase "root ADR 0470 I7: an explicit reading avoids the warning" $
        assertBool "reading" (not (authorNeedsSortKeyWarning True ["author"] (Just "yamada") (Just (PersonalName (Just "山田") Nothing)))),
      testCase "root ADR 0470 I7: no bibliography or no author sort avoids the warning" $ do
        let author = Just (PersonalName (Just "山田") Nothing)
        authorNeedsSortKeyWarning False ["author"] Nothing author @?= False
        authorNeedsSortKeyWarning True ["citation"] Nothing author @?= False,
      testCase "root ADR 0470 I7: given names, literal names and an absent author are not surnames" $ do
        authorNeedsSortKeyWarning True ["author"] Nothing (Just (PersonalName (Just "Smith") (Just "太郎"))) @?= False
        authorNeedsSortKeyWarning True ["author"] Nothing (Just (LiteralName "研究会")) @?= False
        authorNeedsSortKeyWarning True ["author"] Nothing Nothing @?= False,
      testCase "root ADR 0470 I7: blank readings are missing just as in the CSL reader" $
        forM_ [Nothing, Just "", Just "  "] $ \reading ->
          assertBool (show reading) (authorNeedsSortKeyWarning True ["author"] reading (Just (PersonalName (Just "山田") Nothing))),
      testCase "root ADR 0470 I4: same-author-year groups receive suffixes in key order" $
        bibliographyYearSuffixes [("b", "same" :: String), ("a", "same")] @?= Map.fromList [("a", "a"), ("b", "b")],
      testCase "root ADR 0470 I4: separate author-year groups are numbered independently" $
        bibliographyYearSuffixes [("b", 2020 :: Int), ("a", 2020), ("d", 2021), ("c", 2021)] @?= Map.fromList [("a", "a"), ("b", "b"), ("c", "a"), ("d", "b")],
      testCase "root ADR 0470 I4: empty, singleton and repeated keys have no ambiguity suffix" $ do
        bibliographyYearSuffixes ([] :: [(T.Text, Int)]) @?= Map.empty
        bibliographyYearSuffixes [("a", 2020 :: Int)] @?= Map.empty
        bibliographyYearSuffixes [("a", 2020 :: Int), ("a", 2020)] @?= Map.empty,
      testCase "root ADR 0470 I4: the suffix after z is aa" $ do
        let result = bibliographyYearSuffixes [(T.pack ("k" <> show number), ()) | number <- [100 :: Int .. 126]]
        Map.lookup "k100" result @?= Just "a"
        Map.lookup "k125" result @?= Just "z"
        Map.lookup "k126" result @?= Just "aa",
      testCase "root ADR 0470 I4: year suffix assignment is invariant under input order" $
        bibliographyYearSuffixes [("b", ()), ("a", ()), ("c", ())] @?= bibliographyYearSuffixes [("c", ()), ("b", ()), ("a", ())],
      testCase "root ADR 0470 I9: the author key removes canonical Latin accents and lowercases" $
        authorSortKey " " Nothing (Just (PersonalName (Just "Kádár") Nothing)) @?= "kadar",
      testCase "root ADR 0470 I9: an explicit reading takes precedence over the name" $
        authorSortKey " " (Just "Yamada") (Just (PersonalName (Just "山田") (Just "太郎"))) @?= "yamada",
      testCase "root ADR 0470 I9: a missing reading uses the configured family-given separator" $
        authorSortKey " / " Nothing (Just (PersonalName (Just "Kádár") (Just "Dániel"))) @?= "kadar / daniel",
      testCase "root ADR 0470 I9: a literal name has a lowercase sort key" $
        authorSortKey " " Nothing (Just (LiteralName "Institute")) @?= "institute",
      testCase "root ADR 0470 I9: an absent author has an empty key" $
        authorSortKey " " Nothing Nothing @?= "",
      testCase "root ADR 0470 I4: locators stay attached to their keys after sorting" $
        sortBibliographyEntries ["author"] Nothing (entry . fst) ([("b", "page 2"), ("a", "page 1")] :: [(String, String)]) @?= [("a", "page 1"), ("b", "page 2")],
      testCase "root ADR 0470 I9: supplied normalized author keys use code-point order" $
        sortBibliographyEntries ["author"] Nothing id [SortFields "kz" Nothing "" "" 0, SortFields "kadar" Nothing "" "" 1] @?= [SortFields "kadar" Nothing "" "" 1, SortFields "kz" Nothing "" "" 0],
      testCase "root ADR 0470 I4: later sort keys break ties" $
        sortBibliographyEntries ["author", "year"] Nothing entry ["a", "b", "c"] @?= ["c", "a", "b"],
      testCase "root ADR 0470 I4: citation order is explicit and keeps each payload" $
        sortBibliographyEntries ["citation"] Nothing entry ["a", "c", "b"] @?= ["b", "c", "a"],
      testCase "root ADR 0470 I4: title order is independent of the citation order" $
        sortBibliographyEntries ["title"] Nothing entry ["a", "c", "b"] @?= ["b", "c", "a"],
      testCase "root ADR 0470 I4: language order uses primary subtags and a wildcard group" $
        sortBibliographyEntries ["language", "citation"] (Just ["ja", "*", "en"]) entry ["a", "c", "b", "d"] @?= ["b", "c", "a", "d"],
      testCase "root ADR 0470 I4: equal keys preserve input order" $
        sortBibliographyEntries ["author", "year", "title", "language"] Nothing entry ["d", "a"] @?= ["d", "a"],
      testCase "root ADR 0470 I4: an empty key list preserves written order" $
        sortBibliographyEntries [] Nothing entry ["c", "b", "a"] @?= ["c", "b", "a"],
      testCase "root ADR 0470 I4: an empty bibliography remains empty" $
        sortBibliographyEntries ["author"] Nothing entry [] @?= ([] :: [String])
    ]
