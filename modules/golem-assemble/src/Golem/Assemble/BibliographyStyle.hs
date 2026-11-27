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
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
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
    bnEtAl :: !(Maybe Text),
    bnLabel :: !(Maybe (Text, Text))
  }
  deriving stock (Eq, Show)

defaultBibliography :: Bibliography d
defaultBibliography = Bibliography "golem" Map.empty

emptyBibliographyStyle :: BibliographyStyle d
emptyBibliographyStyle = BibliographyStyle Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Map.empty Map.empty Map.empty Map.empty

emptyBibliographyNames :: BibliographyNames
emptyBibliographyNames = BibliographyNames Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

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
