{- | Conversions between UTF-8 byte offsets (the internal unit), line and
column, and UTF-16 code units (used only at the LSP boundary).
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

import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)

-- | Precomputed line starts of a text, in UTF-8 bytes.
data LineIndex = LineIndex
  { liBytes :: !ByteString,
    liStarts :: ![Int]
  }

mkLineIndex :: Text -> LineIndex
mkLineIndex t =
  let bs = TE.encodeUtf8 t
   in LineIndex bs (0 : map (+ 1) (BS.elemIndices 10 bs))

-- | Zero-based line; column counted in Unicode code points.
data LineCol = LineCol {lcLine :: !Int, lcColumn :: !Int}
  deriving stock (Eq, Ord, Show)

lineCount :: LineIndex -> Int
lineCount = length . liStarts

lineStartAndEnd :: LineIndex -> Int -> (Int, Int)
lineStartAndEnd li n =
  let starts = liStarts li
      s = starts !! n
      e = case drop (n + 1) starts of
        (nxt : _) -> nxt - 1
        [] -> BS.length (liBytes li)
   in (s, e)

lineText :: LineIndex -> Int -> Text
lineText li n =
  let (s, e) = lineStartAndEnd li n
   in TE.decodeUtf8 (BS.take (e - s) (BS.drop s (liBytes li)))

lineOf :: LineIndex -> Int -> Int
lineOf li off = length (takeWhile (<= off) (liStarts li)) - 1

isContinuation :: Word8 -> Bool
isContinuation b = b .&. 0xC0 == 0x80

-- | Code points in the byte range.
codePoints :: ByteString -> Int
codePoints = BS.foldl' (\n b -> if isContinuation b then n else n + 1) 0

utf16Units :: ByteString -> Int
utf16Units = BS.foldl' step 0
  where
    step n b
      | isContinuation b = n
      | b >= 0xF0 = n + 2
      | otherwise = n + 1

offsetToLineCol :: LineIndex -> Int -> LineCol
offsetToLineCol li off =
  let l = lineOf li off
      (s, _) = lineStartAndEnd li l
   in LineCol l (codePoints (BS.take (off - s) (BS.drop s (liBytes li))))

offsetToUtf16LineCol :: LineIndex -> Int -> LineCol
offsetToUtf16LineCol li off =
  let l = lineOf li off
      (s, _) = lineStartAndEnd li l
   in LineCol l (utf16Units (BS.take (off - s) (BS.drop s (liBytes li))))

-- | Walk forward over the line until the unit count is reached.
advance :: (ByteString -> Int) -> LineIndex -> LineCol -> Maybe Int
advance measure li (LineCol l c)
  | l < 0 || l >= lineCount li = Nothing
  | otherwise =
      let (s, e) = lineStartAndEnd li l
          lineBytes = BS.take (e - s) (BS.drop s (liBytes li))
          atBoundary i = i >= BS.length lineBytes || not (isContinuation (BS.index lineBytes i))
          go i
            | atBoundary i && measure (BS.take i lineBytes) == c = Just (s + i)
            | i >= BS.length lineBytes = Nothing
            | otherwise = go (i + 1)
       in go 0

lineColToOffset :: LineIndex -> LineCol -> Maybe Int
lineColToOffset = advance codePoints

utf16LineColToOffset :: LineIndex -> LineCol -> Maybe Int
utf16LineColToOffset = advance utf16Units

-- | Columns in UTF-8 bytes (the LSP position encoding "utf-8").
offsetToUtf8LineCol :: LineIndex -> Int -> LineCol
offsetToUtf8LineCol li off =
  let l = lineOf li off
      (s, _) = lineStartAndEnd li l
   in LineCol l (off - s)

utf8LineColToOffset :: LineIndex -> LineCol -> Maybe Int
utf8LineColToOffset = advance BS.length
