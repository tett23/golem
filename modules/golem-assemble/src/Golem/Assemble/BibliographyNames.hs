{- | Name formatting with explicit resolved options (root ADR 0470).
This layer supplies no defaults for omitted declaration keys. In
particular the omission suffix is already complete, including its
separator, so resolving a declaration remains the caller's task.
-}
module Golem.Assemble.BibliographyNames
  ( BibliographyName (..),
    NameOrder (..),
    NameListFormat (..),
    NameFormat (..),
    InitialFormat,
    parseInitialFormat,
    formatBibliographyNames,
    formatShortNames,
  )
where

import Data.Bifunctor (first)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
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
formatBibliographyNames options = formatList (nfList options) . zipWith render [0 :: Int ..] . filter present
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
