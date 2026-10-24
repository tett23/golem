{- | The format of one entry of the bibliography, the single built-in
style (golem-doc ADR 0004, 0005).
-}
module Golem.Doc.Bibliography
  ( CslName (..),
    CslDate (..),
    CslEntry (..),
    EntryPart (..),
    formatEntry,
    entryText,
  )
where

import Data.Char (isDigit, ord)
import Data.Maybe (catMaybes, fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax.Text (tshow)

-- | A name of CSL-JSON: family and given, or one literal string.
data CslName
  = PersonalName {cnFamily :: !(Maybe Text), cnGiven :: !(Maybe Text)}
  | LiteralName !Text
  deriving stock (Eq, Show)

{- | A date of CSL-JSON: the year, month and day of @date-parts@, or the
literal string (golem-doc ADR 0005).
-}
data CslDate
  = DateParts !Integer !(Maybe Int) !(Maybe Int)
  | DateLiteral !Text
  deriving stock (Eq, Show)

-- | The fields of a CSL-JSON item that the bibliography shows (golem-doc ADR 0005).
data CslEntry = CslEntry
  { ceId :: !Text,
    ceType :: !(Maybe Text),
    ceLanguage :: !(Maybe Text),
    ceAuthors :: ![CslName],
    ceTitle :: !(Maybe Text),
    ceContainerTitle :: !(Maybe Text),
    ceVolume :: !(Maybe Text),
    ceIssue :: !(Maybe Text),
    cePage :: !(Maybe Text),
    cePublisher :: !(Maybe Text),
    ceIssued :: !(Maybe CslDate),
    ceUrl :: !(Maybe Text),
    ceAccessed :: !(Maybe CslDate)
  }
  deriving stock (Eq, Show)

-- | A part of a formatted entry: text, or a URL that the outputs mark as such.
data EntryPart = EntryText !Text | EntryUrl !Text
  deriving stock (Eq, Show)

-- | The parts joined: the text of the entry.
entryText :: [EntryPart] -> Text
entryText = T.concat . map partText

partText :: EntryPart -> Text
partText = \case
  EntryText t -> t
  EntryUrl t -> t

{- | One entry: authors, title, container, publisher, year, and the URL
with the date of access, the fields that are not empty, separated by
@、@ and closed by @。@ in a Japanese entry, by @. @ and @.@ in a Latin
one. A Latin entry that ends in a URL without a date takes no period.
-}
formatEntry :: CslEntry -> [EntryPart]
formatEntry e = merge (if isJapaneseEntry e then japanese else latin)
  where
    names sep = T.intercalate sep (filter (not . T.null) (map nameText (ceAuthors e)))
    opt = fromMaybe ""
    year = maybe "" issuedYear (ceIssued e)
    -- the date of access only with a URL
    urlField date = case ceUrl e of
      Nothing -> []
      Just u -> [[EntryUrl u] <> maybe [] (\d -> [EntryText (date d)]) (ceAccessed e)]
    fieldsOf ts url = filter (not . null) ([[EntryText t] | t <- ts, not (T.null t)] <> url)
    japanese =
      let (titleB, containerB) = japaneseBrackets (ceType e)
          fs =
            fieldsOf
              [ names "、",
                maybe "" titleB (ceTitle e),
                maybe "" containerB (ceContainerTitle e),
                maybe "" (numbered "第" "巻") (ceVolume e) <> maybe "" (numbered "第" "号") (ceIssue e),
                maybe "" (\p -> fst (pageText p) <> "頁") (cePage e),
                opt (cePublisher e),
                year
              ]
              (urlField (\d -> "（" <> japaneseDate d <> "閲覧）"))
       in case fs of
            [] -> []
            _ -> concat (intercalateParts [EntryText "、"] fs) <> [EntryText "。" | not (endsWithAny "。？！" (entryText (last fs)))]
    latin =
      let container =
            T.intercalate ", " $
              filter
                (not . T.null)
                [ opt (ceContainerTitle e),
                  maybe "" (numbered "vol. " "") (ceVolume e),
                  maybe "" (numbered "no. " "") (ceIssue e),
                  maybe "" (\p -> let (t, range) = pageText p in (if range then "pp. " else "p. ") <> t) (cePage e)
                ]
          fs =
            fieldsOf
              [names ", ", opt (ceTitle e), container, opt (cePublisher e), year]
              (urlField (\d -> " (accessed " <> latinDate d <> ")"))
       in concat (zipWith latinField fs (map Just (drop 1 fs) <> [Nothing]))
    latinField f next
      | endsWithAny ".?!" (entryText f) = f <> maybe [] (const [EntryText " "]) next
      -- a period after a URL would look like a part of it
      | Nothing <- next, [EntryUrl _] <- f = f
      | otherwise = f <> [EntryText (maybe "." (const ". ") next)]

intercalateParts :: [EntryPart] -> [[EntryPart]] -> [[EntryPart]]
intercalateParts sep = \case
  (x : xs@(_ : _)) -> x : sep : intercalateParts sep xs
  xs -> xs

-- | Adjacent texts joined, empty texts left out.
merge :: [EntryPart] -> [EntryPart]
merge = \case
  EntryText a : EntryText b : rest -> merge (EntryText (a <> b) : rest)
  EntryText "" : rest -> merge rest
  p : rest -> p : merge rest
  [] -> []

{- | The brackets of the title and of the container of a Japanese entry
by its type (golem-doc ADR 0005).
-}
japaneseBrackets :: Maybe Text -> (Text -> Text, Text -> Text)
japaneseBrackets = \case
  Just t
    | t `elem` partTypes -> (bracket "「" "」", bracket "『" "』")
    | t `elem` webTypes -> (bracket "「" "」", id)
    | t `elem` wholeTypes -> (bracket "『" "』", id)
  _ -> (id, id)
  where
    partTypes = ["article", "article-journal", "article-magazine", "article-newspaper", "chapter", "entry", "entry-dictionary", "entry-encyclopedia", "paper-conference", "review", "review-book"]
    webTypes = ["webpage", "post", "post-weblog"]
    wholeTypes = ["book", "thesis", "report", "manuscript", "pamphlet"]

-- | A text in brackets, unless it is already in them.
bracket :: Text -> Text -> Text -> Text
bracket open close t
  | open `T.isPrefixOf` t && close `T.isSuffixOf` t = t
  | otherwise = open <> t <> close

-- | A volume or an issue: marked when it is ASCII digits, as written otherwise.
numbered :: Text -> Text -> Text -> Text
numbered before after v
  | T.all isAsciiDigit v = before <> v <> after
  | otherwise = v

isAsciiDigit :: Char -> Bool
isAsciiDigit c = isDigit c && c < '\x80'

{- | A page: runs of ASCII hyphens between digits as one en dash, and
whether it is a range (a dash or a hyphen between digits, or a comma).
-}
pageText :: Text -> (Text, Bool)
pageText p =
  let t = go Nothing (T.unpack p)
   in (T.pack t, ',' `elem` t || dashBetweenDigits t)
  where
    go _ [] = []
    go prev s@(c : rest)
      | c == '-',
        maybe False isAsciiDigit prev,
        (d : _) <- after =
          if isAsciiDigit d then '\x2013' : go (Just '\x2013') after else c : go (Just c) rest
      | otherwise = c : go (Just c) rest
      where
        after = dropWhile (== '-') s
    dashBetweenDigits = \case
      a : b : c : rest -> (isAsciiDigit a && b `elem` ("-\x2013" :: String) && isAsciiDigit c) || dashBetweenDigits (b : c : rest)
      _ -> False

-- | The year of the date of issue: only the year is shown (golem-doc ADR 0005).
issuedYear :: CslDate -> Text
issuedYear = \case
  DateParts y _ _ -> tshow y
  DateLiteral t -> t

-- | The month of a date when it is 1 to 12, and the day when it is 1 to 31.
validParts :: Maybe Int -> Maybe Int -> (Maybe Int, Maybe Int)
validParts m d = case m of
  Just mo | mo >= 1 && mo <= 12 -> (Just mo, d >>= \dy -> if dy >= 1 && dy <= 31 then Just dy else Nothing)
  _ -> (Nothing, Nothing)

-- | A date of access in a Latin entry: @October 16, 2026@, @October 2026@ or @2026@.
latinDate :: CslDate -> Text
latinDate = \case
  DateLiteral t -> t
  DateParts y m d -> case validParts m d of
    (Just mo, Just dy) -> monthName mo <> " " <> tshow dy <> ", " <> tshow y
    (Just mo, Nothing) -> monthName mo <> " " <> tshow y
    _ -> tshow y
  where
    -- a table of the processor, not of a locale
    monthName mo = case drop (mo - 1) ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"] of
      (n : _) -> n
      [] -> ""

-- | A date of access in a Japanese entry: @2026年10月16日@, @2026年10月@ or @2026年@.
japaneseDate :: CslDate -> Text
japaneseDate = \case
  DateLiteral t -> t
  DateParts y m d ->
    let (mo, dy) = validParts m d
     in tshow y <> "年" <> maybe "" (\x -> tshow x <> "月") mo <> maybe "" (\x -> tshow x <> "日") dy

endsWithAny :: [Char] -> Text -> Bool
endsWithAny cs t = maybe False ((`elem` cs) . snd) (T.unsnoc t)

-- | A literal name as written; a Japanese personal name without a space.
nameText :: CslName -> Text
nameText = \case
  LiteralName t -> t
  PersonalName f g ->
    let parts = catMaybes [f, g]
     in T.intercalate (if any hasWaji parts then "" else " ") parts

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
