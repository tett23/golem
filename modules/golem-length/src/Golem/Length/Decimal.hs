{- | Rationals as decimal numbers (docs/adr ADR 0103, ADR 0114): the one
rule by which the output writes a number, rounded half to even. It is not
a length, but 'Golem.Length.ptText' and 'Golem.Length.emText' write with
it, and golem-pdf writes the numbers of figure matrices with it.
-}
module Golem.Length.Decimal
  ( showRationalDigits,
  )
where

import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T

{- | A rational to at most @n@ decimals, rounded half to even with integer
arithmetic, trailing zeros removed.
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

roundHalfEven :: Rational -> Integer
roundHalfEven r =
  let n = numerator r
      d = denominator r
      (q, m) = n `divMod` d
   in case compare (2 * m) d of
        LT -> q
        GT -> q + 1
        EQ -> if even q then q else q + 1
