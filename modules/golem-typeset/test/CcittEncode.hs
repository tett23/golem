{-# LANGUAGE MultiWayIf #-}

{- | A CCITT encoder for the tests of the decoder (root ADR 0425): Group 3
one-dimensional and two-dimensional coding (ITU-T T.4 4.1 and 4.2) and
Group 4 coding (ITU-T T.6), written from the coding procedures of the
recommendations rather than from the decoder.

The layout of the stream follows the parameters of the PDF filter: an
end-of-line code before each row when EndOfLine is true, with zero fill
before it so that it ends on a byte boundary when EncodedByteAlign is
true; zero fill after each row without end-of-line codes when
EncodedByteAlign is true; the tag bit of each row when K > 0; and RTC or
EOFB at the end when EndOfBlock is true.
-}
module CcittEncode (encodeCcitt, changesOf, packRows, endMarked) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Word (Word8)
import Golem.Typeset.Ccitt (CcittParams (..), Code (..), blackCodes, modeCodes, whiteCodes)

-- | The rows of pixels, True for black, as the filter's encoded data.
encodeCcitt :: CcittParams -> [[Bool]] -> ByteString
encodeCcitt params rows = packBits (reverse (fst (foldl' emit ([], 0) pieces)))
  where
    columns = ccittColumns params
    k = ccittK params
    align = ccittByteAlign params
    withEol = ccittEndOfLine params && k >= 0
    eol = replicate 11 False <> [True]
    emit (acc, n) = \case
      Bits bits -> (reverse bits <> acc, n + length bits)
      FillBeforeEol -> let pad = (8 - (n + 12) `mod` 8) `mod` 8 in (replicate pad False <> acc, n + pad)
      Align -> let pad = (8 - n `mod` 8) `mod` 8 in (replicate pad False <> acc, n + pad)
    twoD i = k < 0 || (k > 0 && i `mod` k /= 0)
    tagged i = [Bits [not (twoD i)] | k > 0]
    eolPieces = [FillBeforeEol | align] <> [Bits eol]
    pieces = concat (zipWith3 rowPieces [0 :: Int ..] (map changesOf ([] : rows)) rows) <> trailer
    rowPieces i reference pixels =
      let current = changesOf pixels
          body = if twoD i then code2D columns reference current else code1D columns current
       in [piece | withEol, piece <- eolPieces] <> tagged i <> [Bits body] <> [Align | align && not withEol]
    trailer
      | not (ccittEndOfBlock params) = []
      | k < 0 = [Bits (eol <> eol)]
      | withEol || not align || k == 0 = concat (replicate 6 (eolPieces' <> [Bits [True] | k > 0]))
      | otherwise = []
    eolPieces' = if withEol then eolPieces else [Bits eol]

-- | A piece of the stream: bits, or zero fill to a byte boundary.
data Piece = Bits [Bool] | FillBeforeEol | Align

{- | Whether the stream ends with RTC or EOFB. It does not when K > 0,
EndOfLine is false and EncodedByteAlign is true: the reader takes the tag
bit before it looks for EOFB there, so that the end must be given by Rows.
-}
endMarked :: CcittParams -> Bool
endMarked params = ccittEndOfBlock params && not (ccittK params > 0 && not (ccittEndOfLine params) && ccittByteAlign params)

-- | Bits, the first bit the most significant one, zero-padded to a byte.
packBits :: [Bool] -> ByteString
packBits bits = BS.pack (map byte (chunks bits))
  where
    chunks [] = []
    chunks xs = let (h, t) = splitAt 8 xs in (h <> replicate (8 - length h) False) : chunks t
    byte = foldl' (\acc b -> acc * 2 + (if b then 1 else 0)) (0 :: Word8)

{- | The changing elements of a row: the positions whose colour differs from
the pixel on the left, the first pixel compared with white.
-}
changesOf :: [Bool] -> [Int]
changesOf pixels = [i | (i, (before, now)) <- zip [0 ..] (zip (False : pixels) pixels), before /= now]

-- | Rows of pixels as the decoder writes them: 1 for white, MSB first.
packRows :: Bool -> [[Bool]] -> ByteString
packRows blackIs1 = BS.concat . map (packBits . map (== blackIs1))

-- One-dimensional coding (T.4 4.1) ----------------------------------------

code1D :: Int -> [Int] -> [Bool]
code1D columns changes =
  let bounds = 0 : changes <> [columns]
      runs = zipWith (-) (drop 1 bounds) bounds
   in concat (zipWith runCode (cycle [True, False]) runs)

-- | A run of a colour (True for white): make-up codes, then a terminating code.
runCode :: Bool -> Int -> [Bool]
runCode white n
  | n >= 2560 + 64 = codeOf table 2560 <> runCode white (n - 2560)
  | n >= 64 = let m = n `div` 64 * 64 in codeOf table (min m 2560) <> codeOf table (n - min m 2560)
  | otherwise = codeOf table n
  where
    table = if white then whiteCodes else blackCodes

codeOf :: [Code] -> Int -> [Bool]
codeOf table value = case [bits | Code v bits <- table, v == value] of
  bits : _ -> map (== '1') bits
  [] -> error ("no code for " <> show value)

-- Two-dimensional coding (T.4 4.2.1.3.4) ----------------------------------

{- | A row coded against the changing elements of the reference row. a0
starts on an imaginary white element before the row; a1 and a2 are the next
changing elements of the coding row, b1 the first changing element of the
reference row to the right of a0 of the colour opposite to a0, and b2 the
next one, each the end of the row when there is none.
-}
code2D :: Int -> [Int] -> [Int] -> [Bool]
code2D columns reference current = go (-1) True
  where
    after p xs = case filter (> p) xs of
      x : _ -> x
      [] -> columns
    go a0 white
      | a0 >= columns = []
      | otherwise =
          let a1 = after a0 current
              a2 = after a1 current
              opposite = [p | (i, p) <- zip [0 :: Int ..] reference, even i == white]
              b1 = after a0 opposite
              b2 = after b1 reference
           in if
                | b2 < a1 -> modeBits 0 <> go b2 white
                | abs (a1 - b1) <= 3 -> modeBits (vertical (a1 - b1)) <> go a1 (not white)
                | otherwise -> modeBits 1 <> runCode white (a1 - max 0 a0) <> runCode (not white) (a2 - a1) <> go a2 white
    vertical d = case d of
      0 -> 2
      1 -> 3
      2 -> 4
      3 -> 5
      -1 -> 6
      -2 -> 7
      _ -> 8
    modeBits = codeOf modeCodes
