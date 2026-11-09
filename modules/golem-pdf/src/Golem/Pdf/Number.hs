{- | Numbers in PDF syntax (golem-pdf ADR 0001): sp converted to pt,
rounded to four decimals half to even with integer arithmetic, trailing
zeros removed. 'showRationalDigits' also writes the matrices of PDF
figures, whose entries are small (golem-pdf ADR 0008). 'hex4' and
'decimal10' write the glyph codes and the xref offsets with a Builder,
the bytes Text.Printf wrote (docs/adr ADR 0254).
-}
module Golem.Pdf.Number
  ( spToPt,
    showRational4,
    showRationalDigits,
    hex4,
    decimal10,
  )
where

import Data.Bits (shiftR, (.&.))
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.Text (Text)
import Data.Word (Word16, Word8)
import Golem.Length (Sp, ptText)
import Golem.Length.Decimal (showRationalDigits)

-- | Sp as pt, at most four decimals (docs/adr ADR 0103).
spToPt :: Sp -> Text
spToPt = ptText

showRational4 :: Rational -> Text
showRational4 = showRationalDigits 4

{- | A glyph code as four upper-case hexadecimal digits, the bytes of
printf "%04X" (docs/adr ADR 0254): each nibble from the top, 0-9 then A-F.
-}
hex4 :: Word16 -> B.Builder
hex4 g = digit 12 <> digit 8 <> digit 4 <> digit 0
  where
    digit :: Int -> B.Builder
    digit s = B.word8 (hexDigit (fromIntegral ((g `shiftR` s) .&. 0xF)))
    hexDigit :: Word8 -> Word8
    hexDigit d = if d < 10 then 0x30 + d else 0x37 + d

{- | A non-negative number in at least ten decimal digits, zeros first:
the bytes of printf "%010d" (docs/adr ADR 0254), for the offsets of the
xref table.
-}
decimal10 :: Int -> B.Builder
decimal10 n = B.byteString (BC.replicate (10 - digits n) '0') <> B.intDec n
  where
    digits :: Int -> Int
    digits k = if k < 10 then 1 else 1 + digits (k `div` 10)
