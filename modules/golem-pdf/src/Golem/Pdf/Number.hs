{- | Numbers in PDF syntax (golem-pdf ADR 0001): sp converted to pt,
rounded to four decimals half to even with integer arithmetic, trailing
zeros removed.
-}
module Golem.Pdf.Number
  ( spToPt,
    showDecimal4,
    showRational4,
    showRationalDigits,
  )
where

import Data.Ratio (denominator, numerator, (%))
import Data.Text (Text)
import Data.Text qualified as T

-- | 1pt = 65536sp.
spToPt :: Integer -> Text
spToPt sp = showRational4 (sp % 65536)

showRational4 :: Rational -> Text
showRational4 r = showDecimal4 (roundHalfEven (r * 10000))

-- | An integer number of ten-thousandths.
showDecimal4 :: Integer -> Text
showDecimal4 q
  | q < 0 = "-" <> showDecimal4 (negate q)
  | otherwise =
      let (i, f) = q `quotRem` 10000
          frac = T.dropWhileEnd (== '0') (T.justifyRight 4 '0' (T.pack (show f)))
       in T.pack (show i) <> (if T.null frac then "" else "." <> frac)

roundHalfEven :: Rational -> Integer
roundHalfEven r =
  let n = numerator r
      d = denominator r
      (q, m) = n `divMod` d
   in case compare (2 * m) d of
        LT -> q
        GT -> q + 1
        EQ -> if even q then q else q + 1

{- | A rational to at most @n@ decimals, rounded half to even with integer
arithmetic, trailing zeros removed: the matrices of PDF figures, whose
entries are small (golem-pdf ADR 0008).
-}
showRationalDigits :: Int -> Rational -> Text
showRationalDigits n r
  | q < 0 = "-" <> digitsOf (negate q)
  | otherwise = digitsOf q
  where
    scale = 10 ^ n :: Integer
    q = roundHalfEven (r * fromInteger scale)
    digitsOf x =
      let (i, f) = x `quotRem` scale
          frac = T.dropWhileEnd (== '0') (T.justifyRight n '0' (T.pack (show f)))
       in T.pack (show i) <> (if T.null frac then "" else "." <> frac)
