{- | Conversions between UTF-8 byte offsets (the internal unit), line and
column, and the LSP position encodings (UTF-8 bytes or UTF-16 code
units, used only at the LSP boundary).
-}
module Golem.Syntax.Position
  ( LineIndex,
    mkLineIndex,
    LineCol (..),
    offsetToLineCol,
    lineColToOffset,
    offsetToUtf16LineCol,
    utf16LineColToOffset,
    offsetToUtf8LineCol,
    utf8LineColToOffset,
    lineCount,
    lineText,
  )
where

import Data.Array.Unboxed (UArray, bounds, listArray, (!))
import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)

{- | Precomputed line starts of a text, in UTF-8 bytes. The starts are an
array, so finding a line is a binary search and a line's range is an
index (golem-lsp ADR 0002).
-}
data LineIndex = LineIndex
  { liBytes :: !ByteString,
    liStarts :: !(UArray Int Int)
  }

mkLineIndex :: Text -> LineIndex
mkLineIndex t =
  let bs = TE.encodeUtf8 t
      starts = 0 : map (+ 1) (BS.elemIndices 10 bs)
   in LineIndex bs (listArray (0, length starts - 1) starts)

-- | Zero-based line; column counted in Unicode code points.
data LineCol = LineCol {lcLine :: !Int, lcColumn :: !Int}
  deriving stock (Eq, Ord, Show)

lineCount :: LineIndex -> Int
lineCount li = snd (bounds (liStarts li)) + 1

lineStartAndEnd :: LineIndex -> Int -> (Int, Int)
lineStartAndEnd li n =
  let starts = liStarts li
      e
        | n + 1 < lineCount li = starts ! (n + 1) - 1
        | otherwise = BS.length (liBytes li)
   in (starts ! n, e)

lineBytesOf :: LineIndex -> Int -> (Int, ByteString)
lineBytesOf li n =
  let (s, e) = lineStartAndEnd li n
   in (s, BS.take (e - s) (BS.drop s (liBytes li)))

lineText :: LineIndex -> Int -> Text
lineText li = TE.decodeUtf8 . snd . lineBytesOf li

-- | The last line whose start is at or before the offset (binary search).
lineOf :: LineIndex -> Int -> Int
lineOf li off = go 0 (lineCount li - 1)
  where
    starts = liStarts li
    go lo hi
      | lo >= hi = lo
      | otherwise =
          let mid = (lo + hi + 1) `div` 2
           in if starts ! mid <= off then go mid hi else go lo (mid - 1)

isContinuation :: Word8 -> Bool
isContinuation b = b .&. 0xC0 == 0x80

-- | Code points in the byte range.
codePoints :: ByteString -> Int
codePoints = BS.foldl' (\n b -> n + codePointUnits b) 0

codePointUnits :: Word8 -> Int
codePointUnits b
  | isContinuation b = 0
  | otherwise = 1

utf16Units :: ByteString -> Int
utf16Units = BS.foldl' (\n b -> n + utf16LeadUnits b) 0

-- | UTF-16 units contributed by a byte: counted at the lead byte.
utf16LeadUnits :: Word8 -> Int
utf16LeadUnits b
  | isContinuation b = 0
  | b >= 0xF0 = 2
  | otherwise = 1

offsetToLineCol :: LineIndex -> Int -> LineCol
offsetToLineCol = measureFromLineStart codePoints

offsetToUtf16LineCol :: LineIndex -> Int -> LineCol
offsetToUtf16LineCol = measureFromLineStart utf16Units

measureFromLineStart :: (ByteString -> Int) -> LineIndex -> Int -> LineCol
measureFromLineStart measure li off =
  let l = lineOf li off
      (s, _) = lineStartAndEnd li l
   in LineCol l (measure (BS.take (off - s) (BS.drop s (liBytes li))))

{- | Walk the line once from its start, accumulating the units of each
character, and stop at the boundary where the count reaches the column.
A column that falls inside a character or past the line has no offset.
-}
advance :: (Word8 -> Int) -> LineIndex -> LineCol -> Maybe Int
advance units li (LineCol l c)
  | l < 0 || l >= lineCount li || c < 0 = Nothing
  | otherwise =
      let (s, bytes) = lineBytesOf li l
          len = BS.length bytes
          go i n
            | n == c = Just (s + i)
            | n > c || i >= len = Nothing
            | otherwise = go (nextBoundary i) (n + units (BS.index bytes i))
          nextBoundary i = maybe len (+ (i + 1)) (BS.findIndex (not . isContinuation) (BS.drop (i + 1) bytes))
       in go 0 0

lineColToOffset :: LineIndex -> LineCol -> Maybe Int
lineColToOffset = advance codePointUnits

utf16LineColToOffset :: LineIndex -> LineCol -> Maybe Int
utf16LineColToOffset = advance utf16LeadUnits

-- | Columns in UTF-8 bytes (the LSP position encoding "utf-8").
offsetToUtf8LineCol :: LineIndex -> Int -> LineCol
offsetToUtf8LineCol li off =
  let l = lineOf li off
      (s, _) = lineStartAndEnd li l
   in LineCol l (off - s)

{- | No walk: the column is a byte count, valid when it is within the line
and does not land on a continuation byte.
-}
utf8LineColToOffset :: LineIndex -> LineCol -> Maybe Int
utf8LineColToOffset li (LineCol l c)
  | l < 0 || l >= lineCount li || c < 0 = Nothing
  | otherwise =
      let (s, bytes) = lineBytesOf li l
       in if c > BS.length bytes || (c < BS.length bytes && isContinuation (BS.index bytes c))
            then Nothing
            else Just (s + c)
