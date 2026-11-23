{- | The CCITTFaxDecode filter of PDF (ISO 32000-1:2008 7.4.6): Group 3
one-dimensional and two-dimensional coding (ITU-T T.4) and Group 4 coding
(ITU-T T.6), for the masks and images of imported PDF figures (root ADR 0425).

The decoder follows the parameters of the filter: K, EndOfLine,
EncodedByteAlign, Columns, Rows, EndOfBlock and BlackIs1. Where the PDF
specification leaves the reading open, it reads like xpdf, the reader from
which most PDF readers took their CCITT decoder: zero fill bits before an
end-of-line code are skipped, also between the end-of-line codes of RTC,
and a row is byte-aligned only when no end-of-line code follows it.

Damaged data is an error rather than a guess: an unknown code, a run past
the end of the row, a changing element out of the row, the extension mode,
and data that ends inside a row.
-}
module Golem.Typeset.Ccitt
  ( CcittParams (..),
    defaultCcittParams,
    decodeCcitt,
    Code (..),
    modeCodes,
    whiteCodes,
    blackCodes,
  )
where

import Data.Bits (shiftL, shiftR, testBit, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IntSet qualified as IntSet
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Word (Word8)

-- | The parameters of the filter, with the defaults of ISO 32000-1 Table 11.
data CcittParams = CcittParams
  { ccittK :: !Int,
    ccittEndOfLine :: !Bool,
    ccittByteAlign :: !Bool,
    ccittColumns :: !Int,
    ccittRows :: !Int,
    ccittEndOfBlock :: !Bool,
    ccittBlackIs1 :: !Bool
  }
  deriving stock (Eq, Show)

defaultCcittParams :: CcittParams
defaultCcittParams = CcittParams 0 False False 1728 0 True False

-- | A code of the tables of T.4 and T.6: its value and its bits.
data Code = Code {codeValue :: !Int, codeBits :: !String}
  deriving stock (Eq, Show)

-- The modes of two-dimensional coding (T.4 Table 4).
data Mode = Pass | Horizontal | Vertical !Int | Extension
  deriving stock (Eq, Show)

{- | Decode at most the given number of rows. The result has one bit for each
pixel, the most significant bit first, and each row padded to a byte; a
white pixel is 1, or 0 when BlackIs1 is true, as the filter writes them.
-}
decodeCcitt :: CcittParams -> Int -> ByteString -> Either Text ByteString
decodeCcitt params limit input
  | ccittColumns params < 1 = Left "CCITT の Columns が不正です"
  | ccittRows params < 0 = Left "CCITT の Rows が不正です"
  | otherwise = do
      let start = skipZeros (Reader input 0 (lastOne input))
          (eolSeen, afterEol) = case peekBits 12 start of
            Just 1 -> (True, skip 12 start)
            _ -> (False, start)
          endOfLine = ccittEndOfLine params || eolSeen
          (twoD, first) = tag params afterEol
      rows <- go endOfLine [] [] 0 twoD first
      Right (BS.concat (map (packRow params) rows))
  where
    wanted = if ccittRows params > 0 then min limit (ccittRows params) else limit
    go endOfLine acc reference count twoD reader
      | count >= wanted = Right (reverse acc)
      | atEnd reader = Right (reverse acc)
      | otherwise = do
          (row, decoded) <- if twoD then decode2D (ccittColumns params) (referenceOf reference) reader else decode1D (ccittColumns params) reader
          let count' = count + 1
          case afterRow params endOfLine count' decoded of
            (True, _, _) -> Right (reverse (row : acc))
            (False, nextTwoD, next) -> go endOfLine (row : acc) row count' nextTwoD next

{- | Whether the next row is two-dimensional: always for K < 0, by the tag
bit for K > 0, and never for K = 0.
-}
tag :: CcittParams -> Reader -> (Bool, Reader)
tag params reader
  | ccittK params < 0 = (True, reader)
  | ccittK params == 0 = (False, reader)
  | otherwise = case peekBits 1 reader of
      Just bit -> (bit == 0, skip 1 reader)
      Nothing -> (False, reader)

{- | The end of a row: the end-of-line code, the alignment, the tag bit of
the next row, and the end of the data (RTC or EOFB). True when the data
ends here.
-}
afterRow :: CcittParams -> Bool -> Int -> Reader -> (Bool, Bool, Reader)
afterRow params endOfLine count reader
  | not (ccittEndOfBlock params) && ccittRows params > 0 && count >= ccittRows params = (True, False, reader)
  | otherwise =
      let (gotEol, afterEol)
            | endOfLine || not (ccittByteAlign params) =
                let searched = if endOfLine then seekEol reader else skipZeros reader
                 in case peekBits 12 searched of
                      Just 1 -> (True, skip 12 searched)
                      _ -> (False, searched)
            | otherwise = (False, reader)
          aligned = if ccittByteAlign params && not gotEol then align afterEol else afterEol
          (twoD, tagged) = tag params aligned
          -- Without a search for EOL above, an EOFB is found here.
          (gotEol', checked)
            | ccittEndOfBlock params && not endOfLine && ccittByteAlign params,
              Just 0x001001 <- peekBits 24 tagged =
                (True, skip 12 tagged)
            | otherwise = (gotEol, tagged)
       in -- RTC may have fill before each of its EOLs, as libtiff writes it
          if ccittEndOfBlock params && gotEol' && peekBits 12 (skipZeros checked) == Just 1
            then (True, twoD, checked)
            else (False, twoD, checked)

-- One-dimensional coding ------------------------------------------------

-- | A row of modified Huffman runs, as its changing elements.
decode1D :: Int -> Reader -> Either Text ([Int], Reader)
decode1D columns = go [] 0 True
  where
    go acc a0 white reader
      | a0 >= columns = Right (normalize columns (reverse acc), reader)
      | otherwise = do
          (run, next) <- readRun white reader
          let a1 = a0 + run
          if a1 > columns then Left overflow else go (a1 : acc) a1 (not white) next

-- | A run: make-up codes followed by one terminating code.
readRun :: Bool -> Reader -> Either Text (Int, Reader)
readRun white = go 0
  where
    table = if white then whiteTable else blackTable
    go total reader = do
      (value, next) <- readCode table reader
      let total' = total + value
      if total' > maxRun
        then Left overflow
        else if value < 64 then Right (total', next) else go total' next

maxRun :: Int
maxRun = 1 `shiftL` 24

-- Two-dimensional coding ------------------------------------------------

{- | A row coded against the reference row, as its changing elements. The
changing elements of a row are the positions where the colour changes,
starting from white; the even ones change to black.
-}
decode2D :: Int -> Reference -> Reader -> Either Text ([Int], Reader)
decode2D columns reference = go [] 0 True True
  where
    go acc a0 white atStart reader
      | a0 >= columns = Right (normalize columns (reverse acc), reader)
      | otherwise = do
          (mode, next) <- readCode modeTable reader >>= \(value, r) -> Right (modeOf value, r)
          let (b1, b2) = referenceElements columns reference (if atStart then -1 else a0) white
          case mode of
            Pass
              | b2 < a0 || b2 > columns -> Left offsetError
              | otherwise -> go acc b2 white False next
            Horizontal -> do
              (run1, r1) <- readRun white next
              (run2, r2) <- readRun (not white) r1
              let a1 = a0 + run1
                  a2 = a1 + run2
              if a2 > columns then Left overflow else go (a2 : a1 : acc) a2 white False r2
            Vertical shift ->
              let a1 = b1 + shift
               in if a1 < a0 || a1 > columns then Left offsetError else go (a1 : acc) a1 (not white) False next
            Extension -> Left "CCITT の拡張モードには対応していません"

{- | The changing elements of the reference row: those to black, those to
white, and all of them.
-}
data Reference = Reference !IntSet.IntSet !IntSet.IntSet !IntSet.IntSet

referenceOf :: [Int] -> Reference
referenceOf changes =
  let indexed = zip [0 :: Int ..] changes
   in Reference (IntSet.fromList [p | (i, p) <- indexed, even i]) (IntSet.fromList [p | (i, p) <- indexed, odd i]) (IntSet.fromList changes)

{- | b1, the first changing element of the reference row to the right of a0
whose colour is opposite to the colour at a0, and b2, the next one; each is
the end of the row when there is none (T.4 4.2.1.3.1).
-}
referenceElements :: Int -> Reference -> Int -> Bool -> (Int, Int)
referenceElements columns (Reference toBlack toWhite every) a0 white =
  case IntSet.lookupGT a0 (if white then toBlack else toWhite) of
    Just b1 -> (b1, fromMaybe columns (IntSet.lookupGT b1 every))
    Nothing -> (columns, columns)

{- | The changing elements of a row with the empty runs removed: two equal
neighbours cancel, and an element at the end of the row changes nothing.
-}
normalize :: Int -> [Int] -> [Int]
normalize columns = reverse . foldl' step [] . filter (< columns)
  where
    step (top : rest) p | top == p = rest
    step stack p = p : stack

modeOf :: Int -> Mode
modeOf = \case
  0 -> Pass
  1 -> Horizontal
  2 -> Vertical 0
  3 -> Vertical 1
  4 -> Vertical 2
  5 -> Vertical 3
  6 -> Vertical (-1)
  7 -> Vertical (-2)
  8 -> Vertical (-3)
  _ -> Extension

-- Output -------------------------------------------------------------------

-- | A row as packed bits: white is 1 unless BlackIs1.
packRow :: CcittParams -> [Int] -> ByteString
packRow params changes =
  let columns = ccittColumns params
      bytes = (columns + 7) `div` 8
      black = blackAt changes
      bit x = x < columns && black x == ccittBlackIs1 params
      byte k = foldl' (\acc j -> if bit (k * 8 + j) then acc .|. (0x80 `shiftR` j) else acc) (0 :: Word8) [0 .. 7]
   in BS.pack (map byte [0 .. bytes - 1])

-- | Whether each pixel is black, from the changing elements of the row.
blackAt :: [Int] -> Int -> Bool
blackAt changes =
  let starts = Map.fromList (zip changes (cycle [True, False]))
   in \x -> maybe False snd (Map.lookupLE x starts)

-- Bits ---------------------------------------------------------------------

{- | The data, the position of the next bit counted from the start, and the
position just after the last 1 bit, beyond which only fill is left.
-}
data Reader = Reader !ByteString !Int !Int

-- | The position just after the last 1 bit of the data.
lastOne :: ByteString -> Int
lastOne bytes = case BS.findIndexEnd (/= 0) bytes of
  Nothing -> 0
  Just index ->
    let byte = BS.index bytes index
     in index * 8 + 8 - length (takeWhile (not . testBit byte) [0 .. 7])

bitAt :: Reader -> Int -> Maybe Bool
bitAt (Reader bytes position _) offset =
  let p = position + offset
      (index, within) = p `divMod` 8
   in if index >= BS.length bytes then Nothing else Just (testBit (BS.index bytes index) (7 - within))

-- | Whether only zero bits, or none, are left.
atEnd :: Reader -> Bool
atEnd (Reader _ position final) = position >= final

{- | The next n bits, those past the end read as 0; Nothing when no bit is
left, like lookBits of xpdf.
-}
peekBits :: Int -> Reader -> Maybe Int
peekBits n reader = case bitAt reader 0 of
  Nothing -> Nothing
  Just _ -> Just (foldl' (\acc i -> acc `shiftL` 1 .|. (if bitAt reader i == Just True then 1 else 0)) 0 [0 .. n - 1])

skip :: Int -> Reader -> Reader
skip n (Reader bytes position final) = Reader bytes (position + n) final

align :: Reader -> Reader
align (Reader bytes position final) = Reader bytes ((position + 7) .&. negate 8) final

-- | Skip zero bits while the next 12 bits are all 0 (fill before an EOL).
skipZeros :: Reader -> Reader
skipZeros reader = case peekBits 12 reader of
  Just 0 -> skipZeros (skip 1 reader)
  _ -> reader

-- | Skip bits up to the next EOL, or to the end of the data.
seekEol :: Reader -> Reader
seekEol reader = case peekBits 12 reader of
  Just 1 -> reader
  Nothing -> reader
  Just _ -> seekEol (skip 1 reader)

-- | A code of a prefix-free table, read bit by bit.
readCode :: Map.Map (Int, Int) Int -> Reader -> Either Text (Int, Reader)
readCode table reader = go 1 0
  where
    go len acc
      | len > 13 = Left invalidCode
      | otherwise = case bitAt reader (len - 1) of
          Nothing -> Left "CCITT のデータが行の途中で終わっています"
          Just bit ->
            let acc' = acc `shiftL` 1 .|. (if bit then 1 else 0)
             in case Map.lookup (len, acc') table of
                  Just value -> Right (value, skip len reader)
                  Nothing -> go (len + 1) acc'

invalidCode, overflow, offsetError :: Text
invalidCode = "CCITT の符号が不正です"
overflow = "CCITT の連長が行の幅を超えます"
offsetError = "CCITT の変化点が行の外にあります"

-- Tables (ITU-T T.4 Tables 1 to 4) ----------------------------------------

tableOf :: [Code] -> Map.Map (Int, Int) Int
tableOf codes = Map.fromList [((length bits, foldl' (\acc c -> acc * 2 + (if c == '1' then 1 else 0)) 0 bits), value) | Code value bits <- codes]

modeTable, whiteTable, blackTable :: Map.Map (Int, Int) Int
modeTable = tableOf modeCodes
whiteTable = tableOf whiteCodes
blackTable = tableOf blackCodes

{- | The mode codes: 0 pass, 1 horizontal, 2 V0, 3 to 5 VR1 to VR3, 6 to 8
VL1 to VL3, and 9 the extension.
-}
modeCodes :: [Code]
modeCodes =
  [ Code 0 "0001",
    Code 1 "001",
    Code 2 "1",
    Code 3 "011",
    Code 4 "000011",
    Code 5 "0000011",
    Code 6 "010",
    Code 7 "000010",
    Code 8 "0000010",
    Code 9 "0000001"
  ]

whiteCodes :: [Code]
whiteCodes =
  zipWith
    Code
    [0 ..]
    [ "00110101",
      "000111",
      "0111",
      "1000",
      "1011",
      "1100",
      "1110",
      "1111",
      "10011",
      "10100",
      "00111",
      "01000",
      "001000",
      "000011",
      "110100",
      "110101",
      "101010",
      "101011",
      "0100111",
      "0001100",
      "0001000",
      "0010111",
      "0000011",
      "0000100",
      "0101000",
      "0101011",
      "0010011",
      "0100100",
      "0011000",
      "00000010",
      "00000011",
      "00011010",
      "00011011",
      "00010010",
      "00010011",
      "00010100",
      "00010101",
      "00010110",
      "00010111",
      "00101000",
      "00101001",
      "00101010",
      "00101011",
      "00101100",
      "00101101",
      "00000100",
      "00000101",
      "00001010",
      "00001011",
      "01010010",
      "01010011",
      "01010100",
      "01010101",
      "00100100",
      "00100101",
      "01011000",
      "01011001",
      "01011010",
      "01011011",
      "01001010",
      "01001011",
      "00110010",
      "00110011",
      "00110100"
    ]
    <> zipWith
      Code
      [64, 128 ..]
      [ "11011",
        "10010",
        "010111",
        "0110111",
        "00110110",
        "00110111",
        "01100100",
        "01100101",
        "01101000",
        "01100111",
        "011001100",
        "011001101",
        "011010010",
        "011010011",
        "011010100",
        "011010101",
        "011010110",
        "011010111",
        "011011000",
        "011011001",
        "011011010",
        "011011011",
        "010011000",
        "010011001",
        "010011010",
        "011000",
        "010011011"
      ]
    <> extendedCodes

blackCodes :: [Code]
blackCodes =
  zipWith
    Code
    [0 ..]
    [ "0000110111",
      "010",
      "11",
      "10",
      "011",
      "0011",
      "0010",
      "00011",
      "000101",
      "000100",
      "0000100",
      "0000101",
      "0000111",
      "00000100",
      "00000111",
      "000011000",
      "0000010111",
      "0000011000",
      "0000001000",
      "00001100111",
      "00001101000",
      "00001101100",
      "00000110111",
      "00000101000",
      "00000010111",
      "00000011000",
      "000011001010",
      "000011001011",
      "000011001100",
      "000011001101",
      "000001101000",
      "000001101001",
      "000001101010",
      "000001101011",
      "000011010010",
      "000011010011",
      "000011010100",
      "000011010101",
      "000011010110",
      "000011010111",
      "000001101100",
      "000001101101",
      "000011011010",
      "000011011011",
      "000001010100",
      "000001010101",
      "000001010110",
      "000001010111",
      "000001100100",
      "000001100101",
      "000001010010",
      "000001010011",
      "000000100100",
      "000000110111",
      "000000111000",
      "000000100111",
      "000000101000",
      "000001011000",
      "000001011001",
      "000000101011",
      "000000101100",
      "000001011010",
      "000001100110",
      "000001100111"
    ]
    <> zipWith
      Code
      [64, 128 ..]
      [ "0000001111",
        "000011001000",
        "000011001001",
        "000001011011",
        "000000110011",
        "000000110100",
        "000000110101",
        "0000001101100",
        "0000001101101",
        "0000001001010",
        "0000001001011",
        "0000001001100",
        "0000001001101",
        "0000001110010",
        "0000001110011",
        "0000001110100",
        "0000001110101",
        "0000001110110",
        "0000001110111",
        "0000001010010",
        "0000001010011",
        "0000001010100",
        "0000001010101",
        "0000001011010",
        "0000001011011",
        "0000001100100",
        "0000001100101"
      ]
    <> extendedCodes

-- | The make-up codes from 1792 to 2560, shared by both colours (T.4 Table 3).
extendedCodes :: [Code]
extendedCodes =
  zipWith
    Code
    [1792, 1856 ..]
    ["00000001000", "00000001100", "00000001101", "000000010010", "000000010011", "000000010100", "000000010101", "000000010110", "000000010111", "000000011100", "000000011101", "000000011110", "000000011111"]
