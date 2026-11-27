{- | Stable sorting of already resolved bibliography fields (root ADR
0470). The author key is supplied after normalization, and the payload
always travels with its fields, including citation locators.
-}
module Golem.Assemble.BibliographySort
  ( SortFields (..),
    sortBibliographyEntries,
    authorSortKey,
    bibliographyYearSuffixes,
  )
where

import Data.List (elemIndex, findIndex, sortBy)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.BibliographyNames (BibliographyName (..))
import Golem.Assemble.Formats (lowerAlphaNotation, writeNumber)
import Golem.Unicode.Latin (latinSortKey)

-- | Resolved keys; the author is lowercase with Latin diacritics removed.
data SortFields = SortFields
  { sfAuthor :: !Text,
    sfYear :: !(Maybe Integer),
    sfTitle :: !Text,
    sfLanguage :: !Text,
    sfCitation :: !Int
  }
  deriving stock (Eq, Show)

{- | Sort by the declared keys in order, retaining input order for ties.
A language order groups primary subtags, with unlisted languages at @*@
or at the end; without an order their primary subtags are compared.
No declaration defaults are supplied by this function.
-}
sortBibliographyEntries :: [Text] -> Maybe [Text] -> (a -> SortFields) -> [a] -> [a]
sortBibliographyEntries keys languageOrder fieldsOf =
  map snd . sortBy (\(a, _) (b, _) -> foldMap (compareKey a b) keys) . map (\entry -> (fieldsOf entry, entry))
  where
    compareKey a b = \case
      "author" -> compare (sfAuthor a) (sfAuthor b)
      "year" -> compare (sfYear a) (sfYear b)
      "title" -> compare (sfTitle a) (sfTitle b)
      "language" -> case languageOrder of
        Nothing -> compare (primary (sfLanguage a)) (primary (sfLanguage b))
        Just order -> compare (rank order (sfLanguage a)) (rank order (sfLanguage b))
      "citation" -> compare (sfCitation a) (sfCitation b)
      _ -> EQ
    primary = T.toLower . T.takeWhile (/= '-')
    rank order language =
      fromMaybe (fromMaybe (length order) (elemIndex "*" order)) (findIndex ((== primary language) . T.toLower) order)

-- | An explicit reading, or family and given joined by the configured separator.
authorSortKey :: Text -> Maybe Text -> Maybe BibliographyName -> Text
authorSortKey separator explicit author = latinSortKey (fromMaybe (maybe "" written author) explicit)
  where
    written (LiteralName text) = text
    written (PersonalName family given) = T.intercalate separator (catMaybes [family, given])

{- | The caller supplies the same-author-year groups. Only ambiguous
groups receive suffixes, in key order; duplicate keys do not add names.
-}
bibliographyYearSuffixes :: (Ord group) => [(Text, group)] -> Map Text Text
bibliographyYearSuffixes entries =
  Map.fromList
    [ (key, fromMaybe "" (writeNumber lowerAlphaNotation index))
    | keys <- Map.elems groups,
      Set.size keys > 1,
      (key, index) <- zip (Set.toAscList keys) [1 ..]
    ]
  where
    groups = Map.fromListWith Set.union [(group, Set.singleton key) | (key, group) <- entries]
