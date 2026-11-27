-- | Explicit usage context for root ADR 0475 requirement checks.
module Golem.Project.BibliographyRequirements (BibliographyUse (..), bibliographyRequiredChecks, bibliographyAllRequiredChecks) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.BibliographyFormats (bibliographyPieceFields, parseBibliographyPiece)
import Golem.Assemble.BibliographyNames (nameListProblems)
import Golem.Assemble.BibliographyStyle
import Toml.Schema (Scope (..))

{- | Nothing means no list; Just [] means an empty list. Locator names
come from the validated citation IR, without a new project-to-doc dependency.
The supplied style combines book-wide and record-local attributes.
-}
data BibliographyUse = BibliographyUse
  { buListTypes :: !(Maybe [Text]),
    buLocators :: ![Text]
  }
  deriving stock (Eq, Show)

bibliographyRequiredChecks :: Text -> BibliographyUse -> BibliographyStyle d -> [(Text, Text, [Scope], Text)]
bibliographyRequiredChecks name use style =
  [("G03006", name, map ScopeKey (["bibliography", "styles", name] <> path), "参考文献のスタイル " <> name <> " の " <> T.intercalate "." path <> ": " <> reason) | (path, reason) <- issues]
  where
    issues = common <> conditional <> authorSortIssues <> typeIssues <> usedTypes <> nameIssues <> editorLabel <> locatorLabels
    missing path = [(path, "必須項目がありません")]
    require path present = if present then [] else missing path
    common =
      concat
        [ require [key] present
        | (key, present) <-
            [("citation-mode", isJust (bsCitationMode style)), ("citation", isJust (bsCitation style)), ("citation-delimiter", isJust (bsCitationDelimiter style)), ("citation-sort", isJust (bsCitationSort style)), ("sort", isJust (bsSort style)), ("hanging-indent", isJust (bsHangingIndent style)), ("year-suffix", isJust (bsYearSuffix style)), ("page-range", isJust (bsPageRange style)), ("range-delimiter", isJust (bsRangeDelimiter style))]
        ]
    conditional =
      (if bsCitationMode style == Just "author-year" then require ["citation-year"] (isJust (bsCitationYear style)) else [])
        <> (if "language" `elem` fromMaybe [] (bsSort style) then require ["language-order"] (isJust (bsLanguageOrder style)) else [])
    needsAuthorKey = "author" `elem` fromMaybe [] (bsSort style) || bsCitationSort style == Just "author-year"
    authorSortIssues =
      if needsAuthorKey
        then require ["names", "author", "part-delimiter"] (maybe False (isJust . bnPartDelimiter) (Map.lookup "author" (bsNames style)))
        else []
    typeIssues = concat [require ["types", kind, "pieces"] (isJust (btPieces value)) | (kind, value) <- Map.toList (bsTypes style)]
    usedTypes = concat [require ["types", kind] (isJust (bibliographyTypeFor kind style)) | kind <- fromMaybe [] (buListTypes use)]
    fields texts = concat [either (const []) bibliographyPieceFields (parseBibliographyPiece bibliographyFields text) | text <- texts]
    citationFields = fields (fromMaybe [] (bsCitation style) <> fromMaybe [] (bsCitationYear style) <> fromMaybe [] (bsSubsequent style))
    listFields = fields (concatMap (fromMaybe [] . btPieces) (Map.elems (bsTypes style)) <> maybe [] pure (bsLabel style))
    allFields = citationFields <> listFields
    citeAuthor = if bsCitationMode style `elem` [Just "numeric", Just "author-year"] then "short" else "author"
    roles = Set.toList (Set.fromList ([citeAuthor | "author" `elem` citationFields] <> ["author" | "author" `elem` listFields] <> ["editor" | "editor" `elem` allFields]))
    nameIssues = concatMap requiredRole roles <> concat [countIssues role names | (role, names) <- Map.toList (bsNames style)]
    requiredRole role =
      let names = Map.findWithDefault emptyBibliographyNames role (bsNames style)
          at key = ["names", role, key]
       in require (at "delimiter") (isJust (bnDelimiter names))
            <> require (at "last-delimiter") (isJust (bnLastDelimiter names))
            <> ( if role == "short"
                   then []
                   else
                     require (at "order") (isJust (bnOrder names))
                       <> require (at "initials") (isJust (bnInitials names))
                       <> (if bnOrder names `elem` [Just "family-given", Just "first-family-given"] && not (role == "author" && needsAuthorKey) then require (at "part-delimiter") (isJust (bnPartDelimiter names)) else [])
                       <> (if bnInitials names == Just True then require (at "initial-format") (isJust (bnInitialFormat names)) <> require (at "initial-delimiter") (isJust (bnInitialDelimiter names)) else [])
               )
    countIssues role names = [(["names", role, key], reason) | (key, reason) <- nameListProblems names]
    editorLabel = if "editor-label" `elem` allFields then require ["names", "editor", "label"] (maybe False (isJust . bnLabel) (Map.lookup "editor" (bsNames style))) else []
    locatorLabels = if "locator" `elem` citationFields then concat [require ["locator-labels", kind] (Map.member kind (bsLocatorLabels style)) | kind <- Set.toList (Set.fromList (buLocators use))] else []

-- | Validate declarations even when the selected style is golem or another name.
bibliographyAllRequiredChecks :: Bibliography d -> [(Text, Text, [Scope], Text)]
bibliographyAllRequiredChecks bibliography = concatMap declaration (Map.toList (bibStyles bibliography))
  where
    use = BibliographyUse Nothing []
    declaration (name, style) =
      let baseIssues = bibliographyRequiredChecks name use style
       in case bibliographyForLanguage "" style of
            Left keys -> baseIssues <> [("G03006", name, map ScopeKey ["bibliography", "styles", name, "languages", key], "参考文献のスタイル " <> name <> " の languages." <> key <> ": 大文字小文字を区別しない言語タグが重複しています") | key <- keys]
            Right _
              | not (null baseIssues) -> baseIssues
              | otherwise ->
                  concat
                    [ case bibliographyForLanguage tag style of
                        Left _ -> []
                        Right effective -> map (localized name tag) (bibliographyRequiredChecks name use effective)
                    | tag <- Map.keys (bsLanguages style)
                    ]
    localized name tag (code, owner, path, message) =
      let prefix = "参考文献のスタイル " <> name <> " の "
          localMessage = prefix <> "languages." <> tag <> "." <> fromMaybe message (T.stripPrefix prefix message)
       in (code, owner, take 3 path <> map ScopeKey ["languages", tag] <> drop 3 path, localMessage)
