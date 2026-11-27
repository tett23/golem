{- | The declaration data of root ADR 0470. Optional members distinguish
an omitted key from an explicit empty value, including language overrides.
Dimensions are supplied by the project package; the format layer does
not depend on that package.
-}
module Golem.Assemble.BibliographyStyle
  ( Bibliography (..),
    BibliographyStyle (..),
    BibliographyType (..),
    BibliographyNames (..),
    defaultBibliography,
    emptyBibliographyStyle,
    emptyBibliographyNames,
    builtinBibliographyNames,
    bibliographyFields,
    bibliographyLocatorNames,
    bibliographyTypeFor,
    bibliographyForLanguage,
    bibliographyForLanguages,
    overlayBibliographyStyle,
    overlayBibliographyNames,
  )
where

import Control.Applicative ((<|>))
import Data.Char (isAsciiUpper, toLower)
import Data.List (sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR (LocatorLabel (..), locatorLabelName)

-- | The selected name and the writer's declarations.
data Bibliography d = Bibliography
  { bibSelected :: !Text,
    bibStyles :: !(Map Text (BibliographyStyle d))
  }
  deriving stock (Eq, Show)

-- | One declaration, or the partial declaration of a language override.
data BibliographyStyle d = BibliographyStyle
  { bsCitationMode :: !(Maybe Text),
    bsCitation :: !(Maybe [Text]),
    bsCitationYear :: !(Maybe [Text]),
    bsCitationDelimiter :: !(Maybe Text),
    bsCitationPrefix :: !(Maybe Text),
    bsCitationSuffix :: !(Maybe Text),
    bsCitationSort :: !(Maybe Text),
    bsSubsequent :: !(Maybe [Text]),
    bsNoteChannel :: !(Maybe Text),
    bsSort :: !(Maybe [Text]),
    bsLanguageOrder :: !(Maybe [Text]),
    bsLabel :: !(Maybe Text),
    bsHangingIndent :: !(Maybe d),
    bsYearSuffix :: !(Maybe Bool),
    bsPageRange :: !(Maybe Text),
    bsRangeDelimiter :: !(Maybe Text),
    bsMonths :: !(Maybe [Text]),
    bsLocatorLabels :: !(Map Text (Text, Text)),
    bsTypes :: !(Map Text BibliographyType),
    bsNames :: !(Map Text BibliographyNames),
    bsLanguages :: !(Map Text (BibliographyStyle d))
  }
  deriving stock (Eq, Show)

-- | The conditional pieces and per-field character styles of one entry type.
data BibliographyType = BibliographyType
  { btPieces :: !(Maybe [Text]),
    btCharStyles :: !(Map Text Text)
  }
  deriving stock (Eq, Show)

-- | The full, editor or short-name keys, with absence retained.
data BibliographyNames = BibliographyNames
  { bnOrder :: !(Maybe Text),
    bnPartDelimiter :: !(Maybe Text),
    bnInitials :: !(Maybe Bool),
    bnInitialFormat :: !(Maybe Text),
    bnInitialDelimiter :: !(Maybe Text),
    bnDelimiter :: !(Maybe Text),
    bnLastDelimiter :: !(Maybe Text),
    bnMax :: !(Maybe Int),
    bnUseFirst :: !(Maybe Int),
    bnUseLast :: !(Maybe Int),
    bnPairDelimiter :: !(Maybe Text),
    bnEtAl :: !(Maybe Text),
    bnLabel :: !(Maybe (Text, Text))
  }
  deriving stock (Eq, Show)

defaultBibliography :: Bibliography d
defaultBibliography = Bibliography "golem" Map.empty

emptyBibliographyStyle :: BibliographyStyle d
emptyBibliographyStyle = BibliographyStyle Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Map.empty Map.empty Map.empty Map.empty

emptyBibliographyNames :: BibliographyNames
emptyBibliographyNames = BibliographyNames Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

builtinBibliographyNames :: [Text]
builtinBibliographyNames = ["golem", "ieee", "vancouver", "sist02", "unified-linguistics", "chicago-notes-bibliography", "chicago-author-date", "apa"]

{- | CSL variables (CSL-JSON input schema), plus the derived slots of
root ADR 0470. This table validates slot names; it does not discard data
from the input record. Case is significant, including DOI, URL and ISBN.
-}
bibliographyFields :: [Text]
bibliographyFields =
  [ "language",
    "abstract",
    "annote",
    "archive",
    "archive_collection",
    "archive_location",
    "archive-place",
    "authority",
    "call-number",
    "citation-label",
    "collection-title",
    "container-title",
    "container-title-short",
    "dimensions",
    "division",
    "DOI",
    "event",
    "event-title",
    "event-place",
    "genre",
    "ISBN",
    "ISSN",
    "jurisdiction",
    "keyword",
    "medium",
    "note",
    "original-publisher",
    "original-publisher-place",
    "original-title",
    "part-title",
    "PMCID",
    "PMID",
    "publisher",
    "publisher-place",
    "references",
    "reviewed-genre",
    "reviewed-title",
    "scale",
    "source",
    "status",
    "title",
    "title-short",
    "URL",
    "version",
    "volume-title",
    "volume-title-short",
    "year-suffix",
    "chapter-number",
    "citation-number",
    "collection-number",
    "edition",
    "first-reference-note-number",
    "issue",
    "locator",
    "number",
    "number-of-pages",
    "number-of-volumes",
    "page",
    "page-first",
    "part",
    "printing",
    "section",
    "supplement",
    "volume",
    "author",
    "chair",
    "collection-editor",
    "compiler",
    "composer",
    "container-author",
    "contributor",
    "curator",
    "director",
    "editor",
    "editorial-director",
    "executive-producer",
    "guest",
    "host",
    "interviewer",
    "illustrator",
    "narrator",
    "organizer",
    "original-author",
    "performer",
    "producer",
    "recipient",
    "reviewed-author",
    "script-writer",
    "series-creator",
    "translator",
    "accessed",
    "available-date",
    "event-date",
    "issued",
    "original-date",
    "submitted",
    "editor-label",
    "year",
    "month",
    "day",
    "first-note"
  ]

-- | The locator keys already used by the citation IR.
bibliographyLocatorNames :: [Text]
bibliographyLocatorNames = map locatorLabelName [minBound :: LocatorLabel .. maxBound]

-- | Apply a partial declaration over a base without supplying defaults.
overlayBibliographyStyle :: BibliographyStyle d -> BibliographyStyle d -> BibliographyStyle d
overlayBibliographyStyle base override =
  BibliographyStyle
    { bsCitationMode = bsCitationMode override <|> bsCitationMode base,
      bsCitation = bsCitation override <|> bsCitation base,
      bsCitationYear = bsCitationYear override <|> bsCitationYear base,
      bsCitationDelimiter = bsCitationDelimiter override <|> bsCitationDelimiter base,
      bsCitationPrefix = bsCitationPrefix override <|> bsCitationPrefix base,
      bsCitationSuffix = bsCitationSuffix override <|> bsCitationSuffix base,
      bsCitationSort = bsCitationSort override <|> bsCitationSort base,
      bsSubsequent = bsSubsequent override <|> bsSubsequent base,
      bsNoteChannel = bsNoteChannel override <|> bsNoteChannel base,
      bsSort = bsSort override <|> bsSort base,
      bsLanguageOrder = bsLanguageOrder override <|> bsLanguageOrder base,
      bsLabel = bsLabel override <|> bsLabel base,
      bsHangingIndent = bsHangingIndent override <|> bsHangingIndent base,
      bsYearSuffix = bsYearSuffix override <|> bsYearSuffix base,
      bsPageRange = bsPageRange override <|> bsPageRange base,
      bsRangeDelimiter = bsRangeDelimiter override <|> bsRangeDelimiter base,
      bsMonths = bsMonths override <|> bsMonths base,
      bsLocatorLabels = Map.union (bsLocatorLabels override) (bsLocatorLabels base),
      bsTypes = Map.unionWith overlayType (bsTypes base) (bsTypes override),
      bsNames = Map.unionWith overlayBibliographyNames (bsNames base) (bsNames override),
      bsLanguages = Map.unionWith overlayBibliographyStyle (bsLanguages base) (bsLanguages override)
    }
  where
    overlayType first second = BibliographyType (btPieces second <|> btPieces first) (Map.union (btCharStyles second) (btCharStyles first))

-- | Keep inherited name options unless that option was explicitly written.
overlayBibliographyNames :: BibliographyNames -> BibliographyNames -> BibliographyNames
overlayBibliographyNames base override =
  BibliographyNames
    { bnOrder = bnOrder override <|> bnOrder base,
      bnPartDelimiter = bnPartDelimiter override <|> bnPartDelimiter base,
      bnInitials = bnInitials override <|> bnInitials base,
      bnInitialFormat = bnInitialFormat override <|> bnInitialFormat base,
      bnInitialDelimiter = bnInitialDelimiter override <|> bnInitialDelimiter base,
      bnDelimiter = bnDelimiter override <|> bnDelimiter base,
      bnLastDelimiter = bnLastDelimiter override <|> bnLastDelimiter base,
      bnMax = bnMax override <|> bnMax base,
      bnUseFirst = bnUseFirst override <|> bnUseFirst base,
      bnUseLast = bnUseLast override <|> bnUseLast base,
      bnPairDelimiter = bnPairDelimiter override <|> bnPairDelimiter base,
      bnEtAl = bnEtAl override <|> bnEtAl base,
      bnLabel = bnLabel override <|> bnLabel base
    }

{- | Use the declared entry type, or types.default only when that type is absent.
No pieces or styles are inferred when neither declaration exists (root ADR 0470).
-}
bibliographyTypeFor :: Text -> BibliographyStyle d -> Maybe BibliographyType
bibliographyTypeFor entryType declaration =
  Map.lookup entryType (bsTypes declaration) <|> Map.lookup "default" (bsTypes declaration)

-- | Select partial language overlays; collisions retain their written keys.
bibliographyForLanguage :: Text -> BibliographyStyle d -> Either [Text] (BibliographyStyle d)
bibliographyForLanguage language base
  | not (null duplicates) = Left duplicates
  | otherwise = Right (foldl' overlayBibliographyStyle base selected)
  where
    written = Map.toList (bsLanguages base)
    groups = Map.fromListWith (<>) [(asciiLower key, [key]) | (key, _) <- written]
    duplicates = sort (concat [keys | keys <- Map.elems groups, length keys > 1])
    normalized = Map.fromList [(asciiLower key, value) | (key, value) <- written]
    parts = T.splitOn "-" (asciiLower language)
    prefixes = [T.intercalate "-" (take n parts) | n <- [1 .. length parts]]
    selected = mapMaybe (`Map.lookup` normalized) prefixes
    asciiLower = T.map (\c -> if isAsciiUpper c then toLower c else c)

-- | Resolve book-wide controls independently from record-local formatting.
bibliographyForLanguages :: Text -> Text -> BibliographyStyle d -> Either [Text] (BibliographyStyle d)
bibliographyForLanguages bookLanguage recordLanguage base = do
  book <- bibliographyForLanguage bookLanguage base
  record <- bibliographyForLanguage recordLanguage base
  pure
    record
      { bsCitationMode = bsCitationMode book,
        bsCitationDelimiter = bsCitationDelimiter book,
        bsCitationPrefix = bsCitationPrefix book,
        bsCitationSuffix = bsCitationSuffix book,
        bsCitationSort = bsCitationSort book,
        bsNoteChannel = bsNoteChannel book,
        bsSort = bsSort book,
        bsLanguageOrder = bsLanguageOrder book,
        bsYearSuffix = bsYearSuffix book,
        bsHangingIndent = bsHangingIndent book
      }
