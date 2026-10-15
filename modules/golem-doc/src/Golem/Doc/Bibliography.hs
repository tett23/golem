{- | The format of one entry of the bibliography, the single built-in
style (golem-doc ADR 0004).
-}
module Golem.Doc.Bibliography
  ( CslName (..),
    CslDate (..),
    CslEntry (..),
    formatEntry,
  )
where

import Data.Char (ord)
import Data.Maybe (catMaybes, fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T

-- | A name of CSL-JSON: family and given, or one literal string.
data CslName
  = PersonalName {cnFamily :: !(Maybe Text), cnGiven :: !(Maybe Text)}
  | LiteralName !Text
  deriving stock (Eq, Show)

-- | The date of issue: the year of @date-parts@, or the literal string.
data CslDate = DateYear !Integer | DateLiteral !Text
  deriving stock (Eq, Show)

-- | The fields of a CSL-JSON item that the bibliography shows.
data CslEntry = CslEntry
  { ceId :: !Text,
    ceLanguage :: !(Maybe Text),
    ceAuthors :: ![CslName],
    ceTitle :: !(Maybe Text),
    cePublisher :: !(Maybe Text),
    ceIssued :: !(Maybe CslDate)
  }
  deriving stock (Eq, Show)

{- | One entry: authors, title, publisher and year, the fields that are
not empty, separated by @、@ and closed by @。@ in a Japanese entry, by
@. @ and @.@ in a Latin one.
-}
formatEntry :: CslEntry -> Text
formatEntry e
  | isJapaneseEntry e = japanese
  | otherwise = latin
  where
    names = filter (not . T.null) (map nameText (ceAuthors e))
    fields sep = filter (not . T.null) [T.intercalate sep names, fromMaybe "" (ceTitle e), fromMaybe "" (cePublisher e), maybe "" dateText (ceIssued e)]
    japanese = case fields "、" of
      [] -> ""
      fs -> let body = T.intercalate "、" fs in if endsWithAny "。？！" (last fs) then body else body <> "。"
    latin = case fields ", " of
      [] -> ""
      fs -> T.concat (zipWith latinField fs (map Just (drop 1 fs) <> [Nothing]))
    latinField f next
      | endsWithAny ".?!" f = f <> maybe "" (const " ") next
      | otherwise = f <> maybe "." (const ". ") next

endsWithAny :: [Char] -> Text -> Bool
endsWithAny cs t = maybe False ((`elem` cs) . snd) (T.unsnoc t)

-- | A literal name as written; a Japanese personal name without a space.
nameText :: CslName -> Text
nameText = \case
  LiteralName t -> t
  PersonalName f g ->
    let parts = catMaybes [f, g]
     in T.intercalate (if any hasWaji parts then "" else " ") parts

dateText :: CslDate -> Text
dateText = \case
  DateYear y -> T.pack (show y)
  DateLiteral t -> t

{- | Whether an entry is Japanese: by the primary subtag of its language,
or else by the first of title, authors and publisher that it has.
-}
isJapaneseEntry :: CslEntry -> Bool
isJapaneseEntry e = case ceLanguage e of
  Just l -> T.toLower (T.takeWhile (/= '-') l) == "ja"
  Nothing -> maybe False hasWaji (listToMaybe (mapMaybe nonEmpty [ceTitle e, authors, cePublisher e]))
  where
    authors = Just (T.concat (map nameText (ceAuthors e)))
    nonEmpty = \case
      Just t | not (T.null t) -> Just t
      _ -> Nothing

-- | Whether a text has hiragana, katakana, kanji, 々, 〆 or 〇.
hasWaji :: Text -> Bool
hasWaji = T.any waji
  where
    waji c =
      let n = ord c
       in (n >= 0x3040 && n <= 0x309F)
            || (n >= 0x30A0 && n <= 0x30FF)
            || (n >= 0x31F0 && n <= 0x31FF)
            || (n >= 0x4E00 && n <= 0x9FFF)
            || (n >= 0x3400 && n <= 0x4DBF)
            || (n >= 0xF900 && n <= 0xFAFF)
            || c `elem` ("々〆〇" :: String)
