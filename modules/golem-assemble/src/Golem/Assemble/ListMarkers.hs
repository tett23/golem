{- | The markers of lists (golem-driver ADR 0013): the number formats of
@[lists] numbers@ in style.toml and the numbers written in them.
-}
module Golem.Assemble.ListMarkers
  ( ListNumberStyle (..),
    NumberFormat (..),
    parseNumberFormat,
    parseNumberFormatLegacy,
    renderNumberFormat,
    formatListNumber,
    atDepth,
    defaultNumberFormat,
    endsWithSpacedPunctuation,
    ListSite (..),
    listSites,
    listNumberDiagnostics,
  )
where

import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble (Book (..))
import Golem.Doc.IR
import Golem.Numerals.Format
import Golem.Numerals.Notation
import Golem.Syntax.Diagnostic (Diagnostic, Severity (..), diagnostic)
import Golem.Syntax.Span
import Golem.Syntax.Text (tshow)

{- | How a number of a list is written: @{n}@ is the book's notation, the
others a notation of the table (docs/adr/0177).
-}
data ListNumberStyle
  = NsBook
  | NsNotation !Notation
  deriving stock (Eq, Show)

-- | A number format: the text before the number, its notation and the text after it.
data NumberFormat = NumberFormat
  { nfPrefix :: !Text,
    nfStyle :: !ListNumberStyle,
    nfSuffix :: !Text
  }
  deriving stock (Eq, Show)

{- | The samples of the notations in braces (golem-driver ADR 0013), read
until they are retired (G03115, docs/adr/0177).
-}
samples :: [(Text, Notation)]
samples =
  [ ("1", arabic),
    ("一", kanjiNotation),
    ("①", circledNotation),
    ("a", lowerAlphaNotation),
    ("A", upperAlphaNotation),
    ("i", lowerRomanNotation),
    ("I", upperRomanNotation),
    ("イ", irohaNotation),
    ("ア", aiueoNotation)
  ]

{- | Reads a number format: exactly one @{n}@ or @{n:<notation>}@
(docs/adr/0177); @{{@, @}}@ and the samples are read as before. The error
is the reason, in Japanese.
-}
parseNumberFormat :: Text -> Either Text NumberFormat
parseNumberFormat = fmap fst . parseNumberFormatLegacy

-- | 'parseNumberFormat' with the forms to be retired the format uses (G03114, G03115).
parseNumberFormatLegacy :: Text -> Either Text (NumberFormat, [Legacy])
parseNumberFormatLegacy src = do
  (ps, legacy) <- parseFormat DoubledToo table src
  (pre, (), n, suf) <- singleNumber ps
  pure (NumberFormat pre (maybe NsBook NsNotation n) suf, legacy)
  where
    table = \case
      "n" -> Right (NumberSlot ())
      name
        | Just n <- lookup name samples -> Right (SampleSlot () n)
        | otherwise -> Left ("表にない差し込みです: {" <> name <> "}")

-- | The format as style.toml writes it.
renderNumberFormat :: NumberFormat -> Text
renderNumberFormat (NumberFormat pre st suf) =
  escapeLiteral pre <> "{n" <> notation <> "}" <> escapeLiteral suf
  where
    notation = case st of
      NsBook -> ""
      NsNotation n -> ":" <> notationName n

{- | A number in a notation; 'Nothing' when the notation cannot write it
(G07029). @{n}@ is written in Arabic numerals here: its vertical notation
is chosen where it is set.
-}
formatListNumber :: ListNumberStyle -> Integer -> Maybe Text
formatListNumber st n = case st of
  NsBook -> Just (tshow n)
  NsNotation x -> writeNumber x n

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

{- | Numbers of list items that the number format of their depth cannot
write (golem-driver ADR 0013): G07029 at the item, whatever the target.
@formats@ are the number formats of @[lists] numbers@; without them, the
default of the writing mode (docs/adr/0192).
-}
listNumberDiagnostics :: Maybe (NonEmpty NumberFormat) -> Bool -> Book -> [Diagnostic]
listNumberDiagnostics numbers vertical book =
  [ diagnostic "G07029" Error (lsiSpan s) ("リストの番号 " <> T.pack (show (lsiNumber s)) <> " は、書式 " <> renderNumberFormat f <> " で表せません")
  | s <- listSites (concat [bs | Document _ bs <- bookDocs book]),
    let f = atDepth formats (lsiDepth s),
    null (formatListNumber (nfStyle f) (lsiNumber s))
  ]
  where
    formats = fromMaybe (pure (defaultNumberFormat vertical)) numbers
