{- | Where each page of the PDF starts in the source (docs/adr ADR 0195):
where a character of a text is in the source, and the JSON of the start
of each page that golem build writes next to the PDF.
-}
module Golem.Driver.Pdf.Pages
  ( sourceAt,
    pagesJson,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector.Unboxed qualified as U
import Golem.Syntax (FileId, LineCol (..), SrcSpan (..), jsonString, mkLineIndex, offsetToUtf16LineCol)

{- | Where the character at an index of the text of a 'Text' inline is in
the source, as a byte offset in the file of its span. The text is the
source of the span with characters dropped (the newlines of a paragraph,
the backslashes of escapes); each character is matched with the first
of its bytes in the source after the character before it. The
characters of a text that does not come from its span that way (a
value, the number of a heading) or of a span outside the sources are
not in the source: -1. Applied to a span and a text, the offsets are
found once for all the characters.
-}
sourceAt :: Map FileId ByteString -> SrcSpan -> Text -> Int -> Int
sourceAt sources sp t = case Map.lookup (spanFile sp) sources >>= align . slice of
  Just offs -> \i -> spanStart sp + (if i >= 0 && i < U.length offs then offs U.! i else 0)
  Nothing -> const (-1)
  where
    slice src = BS.take (spanEnd sp - spanStart sp) (BS.drop (spanStart sp) src)
    align bs = U.fromList <$> go bs 0 (T.unpack t)
    go _ _ [] = Just []
    go bs cur (c : cs) =
      let enc = TE.encodeUtf8 (T.singleton c)
       in find bs enc cur >>= \p -> (p :) <$> go bs (p + BS.length enc) cs
    -- the first byte of a character is never inside another character
    find bs enc cur = case BS.elemIndex (BS.head enc) (BS.drop cur bs) of
      Just k
        | enc `BS.isPrefixOf` BS.drop (cur + k) bs -> Just (cur + k)
        | otherwise -> find bs enc (cur + k + 1)
      Nothing -> Nothing

{- | The JSON of the start of each page, in the order of the pages
(docs/adr ADR 0195): an array with an object for each page, its number
in the PDF from 1, and the file (its path relative to the root), the
line and the character where its first line starts, as an LSP position:
both from 0, the character in UTF-16 code units. A page without a line
of the source has its number only. The keys are in a fixed order and
the array is on one line, as the diagnostics of --format json.
-}
pagesJson :: Map FileId (FilePath, Text) -> [Maybe (FileId, Int)] -> Text
pagesJson sources starts = "[" <> T.intercalate "," (zipWith one [1 :: Int ..] starts) <> "]\n"
  where
    indexes = Map.map (\(p, src) -> (p, mkLineIndex src)) sources
    one n start = "{\"page\":" <> tshow n <> maybe "" position (start >>= located) <> "}"
    located (fid, off) = (\(p, li) -> (p, offsetToUtf16LineCol li off)) <$> Map.lookup fid indexes
    position (p, LineCol l c) = ",\"file\":" <> jsonString (T.pack p) <> ",\"line\":" <> tshow l <> ",\"character\":" <> tshow c
    tshow = T.pack . show
