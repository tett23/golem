{- | The markers of lists (golem-driver ADR 0013): the number formats of
@[lists] numbers@ in style.toml and the numbers written in them.
-}
module Golem.Doc.ListMarkers
  ( ListNumberStyle (..),
    NumberFormat (..),
    parseNumberFormat,
    renderNumberFormat,
    formatListNumber,
    atDepth,
    defaultNumberFormat,
    endsWithSpacedPunctuation,
    ListSite (..),
    listSites,
  )
where

import Data.Either (lefts, rights)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Doc.Numerals (kanji)
import Golem.Syntax.Span
import Golem.Syntax.Text (tshow)

{- | How a number of a list is written: @{n}@ is the book's notation, the
others are fixed.
-}
data ListNumberStyle
  = NsBook
  | NsArabic
  | NsKanji
  | NsCircled
  | NsLowerAlpha
  | NsUpperAlpha
  | NsLowerRoman
  | NsUpperRoman
  | NsIroha
  | NsAiueo
  deriving stock (Eq, Show, Enum, Bounded)

-- | A number format: the text before the number, its notation and the text after it.
data NumberFormat = NumberFormat
  { nfPrefix :: !Text,
    nfStyle :: !ListNumberStyle,
    nfSuffix :: !Text
  }
  deriving stock (Eq, Show)

placeholders :: [(Text, ListNumberStyle)]
placeholders =
  [ ("n", NsBook),
    ("1", NsArabic),
    ("一", NsKanji),
    ("①", NsCircled),
    ("a", NsLowerAlpha),
    ("A", NsUpperAlpha),
    ("i", NsLowerRoman),
    ("I", NsUpperRoman),
    ("イ", NsIroha),
    ("ア", NsAiueo)
  ]

{- | Reads a number format: exactly one placeholder of the table; @{{@ and
@}}@ are literal braces. The error is the reason, in Japanese.
-}
parseNumberFormat :: Text -> Either Text NumberFormat
parseNumberFormat src = go [] (T.unpack src) >>= assemble
  where
    -- pieces: Left literal text, Right a placeholder
    go acc = \case
      [] -> Right (reverse acc)
      '{' : '{' : rest -> go (Left "{" : acc) rest
      '}' : '}' : rest -> go (Left "}" : acc) rest
      '{' : rest -> case break (== '}') rest of
        (key, '}' : after) -> case lookup (T.pack key) placeholders of
          Just st -> go (Right st : acc) after
          Nothing -> Left ("表にない差し込みです: {" <> T.pack key <> "}")
        _ -> Left "{ が閉じていません。差し込みでない { は {{ と書きます"
      '}' : _ -> Left "対応する { のない } があります。差し込みでない } は }} と書きます"
      c : rest -> go (Left (T.singleton c) : acc) rest
    assemble pieces = case rights pieces of
      [st] ->
        let (before, after) = break isPlaceholder pieces
         in Right (NumberFormat (literal before) st (literal (drop 1 after)))
      [] -> Left "番号の差し込みがありません"
      _ -> Left "番号の差し込みが二つ以上あります"
    isPlaceholder = either (const False) (const True)
    literal ps = T.concat (lefts ps)

-- | The format as written in style.toml.
renderNumberFormat :: NumberFormat -> Text
renderNumberFormat (NumberFormat pre st suf) =
  escape pre <> "{" <> maybe "?" fst (lookupKey st) <> "}" <> escape suf
  where
    lookupKey s = case [p | p@(_, s') <- placeholders, s' == s] of
      (p : _) -> Just p
      [] -> Nothing
    escape = T.replace "}" "}}" . T.replace "{" "{{"

{- | A number in a notation; 'Nothing' when the notation cannot write it
(G07029). @{n}@ is written in Arabic numerals here: its vertical notation
is chosen where it is set.
-}
formatListNumber :: ListNumberStyle -> Integer -> Maybe Text
formatListNumber st n = case st of
  NsBook -> Just (tshow n)
  NsArabic -> Just (tshow n)
  NsKanji -> Just (kanji n)
  NsCircled
    | n >= 1 && n <= 20 -> Just (T.singleton (toEnum (0x2460 + fromInteger n - 1)))
    | n >= 21 && n <= 35 -> Just (T.singleton (toEnum (0x3251 + fromInteger n - 21)))
    | n >= 36 && n <= 50 -> Just (T.singleton (toEnum (0x32B1 + fromInteger n - 36)))
    | otherwise -> Nothing
  NsLowerAlpha -> alpha 'a'
  NsUpperAlpha -> alpha 'A'
  NsLowerRoman -> T.toLower <$> roman
  NsUpperRoman -> roman
  NsIroha -> fromList iroha
  NsAiueo -> fromList aiueo
  where
    -- bijective base 26: z, aa, ab
    alpha base
      | n < 1 = Nothing
      | otherwise = Just (T.pack (letters n))
      where
        letters k
          | k <= 0 = []
          | otherwise = let (q, r) = (k - 1) `divMod` 26 in letters q <> [toEnum (fromEnum base + fromInteger r)]
    roman
      | n < 1 || n > 3999 = Nothing
      | otherwise = Just (T.pack (go n numerals))
      where
        go 0 _ = ""
        go k ((v, s) : rest)
          | k >= v = s <> go (k - v) ((v, s) : rest)
          | otherwise = go k rest
        go _ [] = ""
        numerals = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
    fromList cs
      | n >= 1 && n <= toInteger (T.length cs) = Just (T.singleton (T.index cs (fromInteger n - 1)))
      | otherwise = Nothing

-- | イロハ順, 47 characters.
iroha :: Text
iroha = "イロハニホヘトチリヌルヲワカヨタレソツネナラムウヰノオクヤマケフコエテアサキユメミシヱヒモセス"

-- | アイウエオ順, 46 characters.
aiueo :: Text
aiueo = "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"

{- | The element of a list of per-depth values for a depth (1 is the
outermost list); deeper lists keep the last element.
-}
atDepth :: NonEmpty a -> Int -> a
atDepth xs d = case drop (max 0 (d - 1)) (NE.toList xs) of
  (x : _) -> x
  [] -> NE.last xs

{- | The number format of a book without @[lists] numbers@: @{n}.@ in
horizontal writing, @{n}、@ in vertical writing.
-}
defaultNumberFormat :: Bool -> NumberFormat
defaultNumberFormat vertical = NumberFormat "" NsBook (if vertical then "、" else ".")

{- | Whether a marker ends with punctuation that has space outside its face
in its full-width box: ・, 、, 。 and the closing brackets. Such a marker
needs no gap before the text.
-}
endsWithSpacedPunctuation :: Text -> Bool
endsWithSpacedPunctuation t = case T.unsnoc t of
  Just (_, c) -> c `elem` ("・、，。．」』）］｝〉》】〕〙〗〟’”｠" :: String)
  Nothing -> False

-- | An item of a numbered list: its depth, its number and where it is.
data ListSite = ListSite
  { lsiDepth :: !Int,
    lsiNumber :: !Integer,
    lsiSpan :: !SrcSpan
  }
  deriving stock (Eq, Show)

{- | Every item of every numbered list in the blocks, in document order,
with the depth of its list (lists of both kinds count) and its number.
The span is the item's first block, or the list's without one.
-}
listSites :: [Block] -> [ListSite]
listSites = concatMap (go 0)
  where
    go depth (Block sp _ body) = case body of
      BulletList items -> concatMap (concatMap (go (depth + 1)) . itemBlocks) items
      OrderedList items ->
        concat
          [ ListSite (depth + 1) n (itemSpan sp it) : concatMap (go (depth + 1)) (itemBlocks it)
          | (n, it) <- zip (itemNumbers items) items
          ]
      DefList gs -> concatMap (concatMap (go depth)) (concatMap dgDefs gs)
      _ -> []
    itemSpan sp it = case itemBlocks it of
      (Block bsp _ _ : _) -> bsp
      [] -> sp
