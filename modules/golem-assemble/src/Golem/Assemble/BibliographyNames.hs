{- | Name formatting with explicit resolved options (root ADR 0470).
This layer supplies no defaults for omitted declaration keys. In
particular the omission suffix is already complete, including its
separator, so resolving a declaration remains the caller's task.
-}
module Golem.Assemble.BibliographyNames
  ( BibliographyName (..),
    NameOrder (..),
    NameListFormat (..),
    NameListExtras (..),
    nameListExtras,
    formatShortNamesWith,
    formatBibliographyNamesWith,
    resolveBibliographyNames,
    resolveBibliographyShortNames,
    nameListProblems,
    NameFormat (..),
    InitialFormat,
    parseInitialFormat,
    applyBibliographyNames,
    applyBibliographyNameList,
    bibliographyEditorLabel,
    formatBibliographyNames,
    formatShortNames,
  )
where

import Control.Applicative ((<|>))
import Data.Bifunctor (first)
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.BibliographyStyle qualified as Decl
import Golem.Assemble.Formats (Braces (..), Piece (..), Slot (..), formatReason, parseFormat, unknownSlot)
import Golem.Unicode.Grapheme (graphemeClusters)

-- | The parts already read from CSL; literal names keep their full text.
data BibliographyName
  = PersonalName !(Maybe Text) !(Maybe Text)
  | LiteralName !Text
  deriving stock (Eq, Show)

data NameOrder = FamilyGiven | GivenFamily | FirstFamilyGiven
  deriving stock (Eq, Show)

-- | Complete list options, with an optional count limit and a literal omission suffix.
data NameListFormat = NameListFormat
  { nlDelimiter :: !Text,
    nlLastDelimiter :: !Text,
    nlMax :: !(Maybe Int),
    nlUseFirst :: !Int,
    nlEtAl :: !Text
  }
  deriving stock (Eq, Show)

-- | Complete personal-name options; these are not the defaults of a declaration.
data NameFormat = NameFormat
  { nfOrder :: !NameOrder,
    nfPartDelimiter :: !Text,
    nfInitials :: !Bool,
    nfInitialFormat :: !InitialFormat,
    nfInitialDelimiter :: !Text,
    nfList :: !NameListFormat
  }
  deriving stock (Eq, Show)

-- | The common brace syntax, permitting only the text slot @{i}@.
newtype InitialFormat = InitialFormat [Piece ()]
  deriving stock (Eq, Show)

parseInitialFormat :: Text -> Either Text InitialFormat
parseInitialFormat source = do
  (pieces, _) <- first formatReason (parseFormat EscapesOnly slot source)
  pure (InitialFormat pieces)
  where
    slot "i" = Right (TextSlot ())
    slot name = Left (unknownSlot ("未知の差し込みです: {" <> name <> "}"))

-- | Full names, in their original order, with an explicit format.
formatBibliographyNames :: NameFormat -> [BibliographyName] -> Text
formatBibliographyNames options = formatList (nfList options) . renderedNames options

renderedNames :: NameFormat -> [BibliographyName] -> [Text]
renderedNames options = zipWith render [0 :: Int ..] . filter present
  where
    render _ (LiteralName literal) = literal
    render index (PersonalName family given) =
      let f = fromMaybe "" family
          g = maybe "" givenText given
          familyFirst = nfOrder options == FamilyGiven || (index == 0 && nfOrder options == FirstFamilyGiven)
       in if familyFirst then join (nfPartDelimiter options) [f, g] else join " " [g, f]
    givenText given
      | nfInitials options = T.intercalate (nfInitialDelimiter options) (filter (not . T.null) (map wordInitials (T.words given)))
      | otherwise = given
    wordInitials = T.intercalate "-" . map componentInitials . T.splitOn "-"
    componentInitials =
      T.intercalate (nfInitialDelimiter options)
        . map (renderInitial (nfInitialFormat options) . firstLetter)
        . filter (not . T.null)
        . T.splitOn "."

-- | Short names write only the surname, or the full literal name.
formatShortNames :: NameListFormat -> [BibliographyName] -> Text
formatShortNames options = formatList options . filter (not . T.null . T.strip) . map short
  where
    short (PersonalName family _) = fromMaybe "" family
    short (LiteralName literal) = literal

present :: BibliographyName -> Bool
present = \case
  LiteralName literal -> not (T.null (T.strip literal))
  PersonalName family given -> any (maybe False (not . T.null . T.strip)) [family, given]

-- | Keep the complete first grapheme, including its combining marks.
firstLetter :: Text -> Text
firstLetter = T.toUpper . fromMaybe "" . listToMaybe . graphemeClusters

renderInitial :: InitialFormat -> Text -> Text
renderInitial (InitialFormat pieces) initial = T.concat (map piece pieces)
  where
    piece (PLit literal) = literal
    piece (PText ()) = initial
    piece (PNumber () _) = initial

join :: Text -> [Text] -> Text
join delimiter = T.intercalate delimiter . filter (not . T.null)

formatList :: NameListFormat -> [Text] -> Text
formatList options names =
  let omitted = maybe False (length names >) (nlMax options)
      shown = if omitted then take (nlUseFirst options) names else names
   in joined shown <> if omitted then nlEtAl options else ""
  where
    joined [] = ""
    joined [one] = one
    joined [one, final] = one <> nlLastDelimiter options <> final
    joined (one : rest) = one <> nlDelimiter options <> joined rest

{- | Apply written name keys to caller-supplied complete options. The
caller also supplies how a raw et-al value becomes the complete suffix.
Omission separators and joining after truncation remain caller decisions.
-}
applyBibliographyNames :: (Text -> Text) -> NameFormat -> Decl.BibliographyNames -> Either Text NameFormat
applyBibliographyNames prepareSuffix base declaration = do
  order <- case Decl.bnOrder declaration of
    Nothing -> Right (nfOrder base)
    Just "family-given" -> Right FamilyGiven
    Just "given-family" -> Right GivenFamily
    Just "first-family-given" -> Right FirstFamilyGiven
    Just unknown -> Left ("名前の順を解釈できません: " <> unknown)
  initials <- maybe (Right (nfInitialFormat base)) parseInitialFormat (Decl.bnInitialFormat declaration)
  pure
    base
      { nfOrder = order,
        nfPartDelimiter = fromMaybe (nfPartDelimiter base) (Decl.bnPartDelimiter declaration),
        nfInitials = fromMaybe (nfInitials base) (Decl.bnInitials declaration),
        nfInitialFormat = initials,
        nfInitialDelimiter = fromMaybe (nfInitialDelimiter base) (Decl.bnInitialDelimiter declaration),
        nfList = applyBibliographyNameList prepareSuffix (nfList base) declaration
      }

applyBibliographyNameList :: (Text -> Text) -> NameListFormat -> Decl.BibliographyNames -> NameListFormat
applyBibliographyNameList prepareSuffix base declaration =
  base
    { nlDelimiter = fromMaybe (nlDelimiter base) (Decl.bnDelimiter declaration),
      nlLastDelimiter = fromMaybe (nlLastDelimiter base) (Decl.bnLastDelimiter declaration),
      nlMax = Decl.bnMax declaration <|> nlMax base,
      nlUseFirst = fromMaybe (nlUseFirst base) (Decl.bnUseFirst declaration),
      nlEtAl = maybe (nlEtAl base) prepareSuffix (Decl.bnEtAl declaration)
    }

-- | Select an explicit singular/plural label by the valid editor count.
bibliographyEditorLabel :: (Text, Text) -> [BibliographyName] -> Maybe Text
bibliographyEditorLabel (singular, plural) names = case filter present names of
  [] -> Nothing
  [_] -> Just singular
  _ -> Just plural

-- | Extra resolved controls keep the original five-field constructor compatible.
data NameListExtras = NameListExtras
  { neUseLast :: !Int,
    nePairDelimiter :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

nameListExtras :: Decl.BibliographyNames -> NameListExtras
nameListExtras declaration = NameListExtras (fromMaybe 0 (Decl.bnUseLast declaration)) (Decl.bnPairDelimiter declaration)

formatShortNamesWith :: NameListExtras -> NameListFormat -> [BibliographyName] -> Text
formatShortNamesWith extras options = formatListWith extras options . filter (not . T.null . T.strip) . map short
  where
    short (PersonalName family _) = fromMaybe "" family
    short (LiteralName literal) = literal

formatListWith :: NameListExtras -> NameListFormat -> [Text] -> Text
formatListWith extras options names
  | null names = ""
  | maybe False (length names >) (nlMax options) =
      T.intercalate (nlDelimiter options) (take (nlUseFirst options) names)
        <> nlEtAl options
        <> T.intercalate (nlDelimiter options) (drop (length names - neUseLast extras) names)
  | otherwise = joined names
  where
    joined [] = ""
    joined [one] = one
    joined [one, final] = one <> fromMaybe (nlLastDelimiter options) (nePairDelimiter extras) <> final
    joined many = T.intercalate (nlDelimiter options) (init many) <> nlLastDelimiter options <> last many

formatBibliographyNamesWith :: NameListExtras -> NameFormat -> [BibliographyName] -> Text
formatBibliographyNamesWith extras options = formatListWith extras (nfList options) . renderedNames options

-- | Resolve a complete declaration without borrowing another style's values.
resolveBibliographyNames :: Decl.BibliographyNames -> Either Text (NameFormat, NameListExtras)
resolveBibliographyNames declaration = do
  (names, extras) <- resolveBibliographyShortNames declaration
  writtenOrder <- requiredOption "order" (Decl.bnOrder declaration)
  order <- case writtenOrder of
    "family-given" -> Right FamilyGiven
    "given-family" -> Right GivenFamily
    "first-family-given" -> Right FirstFamilyGiven
    _ -> Left "order に使えない値です"
  initials <- requiredOption "initials" (Decl.bnInitials declaration)
  partDelimiter <- if order == GivenFamily then Right (fromMaybe "" (Decl.bnPartDelimiter declaration)) else requiredOption "part-delimiter" (Decl.bnPartDelimiter declaration)
  initial <- case Decl.bnInitialFormat declaration of
    Just text -> parseInitialFormat text
    Nothing | initials -> Left "initial-format は必須項目です"
    -- This value is never observed when initials is false; no other style is borrowed.
    Nothing -> parseInitialFormat "{i}"
  initialDelimiter <- if initials then requiredOption "initial-delimiter" (Decl.bnInitialDelimiter declaration) else Right (fromMaybe "" (Decl.bnInitialDelimiter declaration))
  pure (NameFormat order partDelimiter initials initial initialDelimiter names, extras)

resolveBibliographyShortNames :: Decl.BibliographyNames -> Either Text (NameListFormat, NameListExtras)
resolveBibliographyShortNames declaration = do
  case nameListProblems declaration of
    [] -> Right ()
    (key, reason) : _ -> Left (key <> ": " <> reason)
  delimiter <- requiredOption "delimiter" (Decl.bnDelimiter declaration)
  lastDelimiter <- requiredOption "last-delimiter" (Decl.bnLastDelimiter declaration)
  pure (NameListFormat delimiter lastDelimiter (Decl.bnMax declaration) (fromMaybe 0 (Decl.bnUseFirst declaration)) (fromMaybe "" (Decl.bnEtAl declaration)), nameListExtras declaration)

requiredOption :: Text -> Maybe a -> Either Text a
requiredOption key = maybe (Left (key <> " は必須項目です")) Right

-- | Shared count constraints for the project checker and the canonical resolver.
nameListProblems :: Decl.BibliographyNames -> [(Text, Text)]
nameListProblems names =
  let values = [("max", Decl.bnMax names), ("use-first", Decl.bnUseFirst names), ("use-last", Decl.bnUseLast names)]
      valid number = number >= 0 && toInteger number <= 2147483647
      bounds = [(key, "名前の数は0以上2147483647以下の整数です") | (key, Just number) <- values, not (valid number)]
      require key supplied = [(key, "必須項目がありません") | not supplied]
   in bounds <> case Decl.bnMax names of
        Nothing -> [(key, "max のない名前の表に省略の指定は書けません") | (key, supplied) <- [("use-first", isJust (Decl.bnUseFirst names)), ("use-last", isJust (Decl.bnUseLast names)), ("et-al", isJust (Decl.bnEtAl names))], supplied]
        Just limit ->
          require "use-first" (isJust (Decl.bnUseFirst names))
            <> require "et-al" (isJust (Decl.bnEtAl names))
            <> [(if isJust (Decl.bnUseLast names) then "use-last" else "use-first", "先頭と末尾の保持数の合計が max を超えています") | let lastCount = fromMaybe 0 (Decl.bnUseLast names), Just firstCount <- [Decl.bnUseFirst names], all valid [limit, firstCount, lastCount], toInteger firstCount + toInteger lastCount > toInteger limit]
