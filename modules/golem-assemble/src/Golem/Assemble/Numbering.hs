{- | The separator between a number and its title (golem-html ADR 0002),
and the title formats of numbered headings and captions (root ADR 0463).
-}
module Golem.Assemble.Numbering
  ( numberSeparator,
    titleSeparator,
    TitlePiece (..),
    formatSeparator,
    formatTitle,
    numberedTitleText,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T

{- | The text between a number and its title, from the language of the book
(a BCP 47 tag) and the number: an ideographic space when the primary
subtag is @ja@, a space otherwise, and nothing when the number already
ends with a space, an ideographic space or a tab.
-}
numberSeparator :: Text -> Text -> Text
numberSeparator lang num
  | maybe False ((`elem` [' ', '\x3000', '\t']) . snd) (T.unsnoc num) = ""
  | otherwise = languageSeparator lang

-- | The separator of the language: an ideographic space for @ja@, a space otherwise.
languageSeparator :: Text -> Text
languageSeparator lang
  | T.toLower (T.takeWhile (/= '-') lang) == "ja" = "\x3000"
  | otherwise = " "

-- | Insert a separator only between nonempty parts (Golem ADR 0372).
titleSeparator :: Text -> Maybe Text -> Text -> Text -> Text
titleSeparator lang configured number title
  | T.null number || T.null title = ""
  | otherwise = fromMaybe (numberSeparator lang number) configured

{- | A piece of a title format of a file and a level (root ADR 0463), its
slots of [metadata], [vars] and the variables of the file replaced by
their text: text, the number, the title or the separator.
-}
data TitlePiece
  = TitleText !Text
  | TitleNumber
  | TitleTitle
  | TitleSeparator
  deriving stock (Eq, Show)

{- | What @{separator}@ stands for (root ADR 0463): number-title-separator
when it is written, the separator of the language otherwise; it is there
even after a number that ends with a space.
-}
formatSeparator :: Text -> Maybe Text -> Text
formatSeparator lang = fromMaybe (languageSeparator lang)

{- | A title by its format (root ADR 0463), in the pieces of an output:
how text is written, the number, the title and the separator.
-}
formatTitle :: (Monoid m) => (Text -> m) -> m -> m -> Text -> [TitlePiece] -> m
formatTitle text number title separator = foldMap $ \case
  TitleText t -> text t
  TitleNumber -> number
  TitleTitle -> title
  TitleSeparator -> text separator

{- | The text of a numbered title: its format, or the number, the separator
and the title (Golem ADR 0372, root ADR 0463); from the language, the
separator written, the format, the number and the title.
-}
numberedTitleText :: Text -> Maybe Text -> Maybe [TitlePiece] -> Text -> Text -> Text
numberedTitleText lang separator format number title = case format of
  Just pieces -> formatTitle id number title (formatSeparator lang separator) pieces
  Nothing -> number <> titleSeparator lang separator number title <> title
