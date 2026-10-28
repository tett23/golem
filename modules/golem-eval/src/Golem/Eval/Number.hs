{- | Exact numeric rules of the expression language (docs/markup.md
"数の規則", docs/adr ADR 0101): rounding a rational to decimal places,
rounding to 17 significant digits, square roots, and the text of a number
in prose. Every judgement is on integers.
-}
module Golem.Eval.Number
  ( roundHalfAway,
    roundTo,
    renderFixed,
    round17,
    sqrtRational,
    isqrt,
    piValue,
    eValue,
    renderNumber,
    exactText,
    maxFractionDigits,
    floorDiv,
    floorMod,
  )
where

import Data.Bits (shiftL)
import Data.Maybe (fromMaybe)
import Data.Ratio (denominator, numerator, (%))
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Num.Integer (integerLog2)

-- | The nearest integer, ties away from zero.
roundHalfAway :: Rational -> Integer
roundHalfAway q
  | q < 0 = negate (roundHalfAway (negate q))
  | otherwise = floor (q + 1 % 2)

-- | The nearest decimal of @n@ fractional digits, ties away from zero.
roundTo :: Integer -> Rational -> Rational
roundTo n q = roundHalfAway (q * 10 ^ n) % 10 ^ n

{- | A decimal of at most @n@ fractional digits, written with exactly @n@
(used by @fixed@).
-}
renderFixed :: Integer -> Rational -> Text
renderFixed n q
  | n <= 0 = T.pack (show m)
  | otherwise =
      let digits = T.pack (show (abs m))
          w = fromInteger n
          padded = T.replicate (w + 1 - T.length digits) "0" <> digits
          (ip, fp) = T.splitAt (T.length padded - w) padded
       in (if m < 0 then "-" else "") <> ip <> "." <> fp
  where
    m = numerator (q * 10 ^ n)

{- | The exponent @p@ with @10^p <= q < 10^(p+1)@, for @q > 0@, found by
comparing integers alone.
-}
decimalExponent :: Rational -> Integer
decimalExponent q = adjust (digitCount (numerator q) - digitCount (denominator q))
  where
    digitCount = toInteger . length . show
    adjust p
      | pow p > q = adjust (p - 1)
      | pow (p + 1) <= q = adjust (p + 1)
      | otherwise = p
    pow :: Integer -> Rational
    pow p = if p >= 0 then fromInteger (10 ^ p) else 1 % 10 ^ negate p

{- | The fractional digits of the rounding to 17 significant digits of a
positive number whose decimal exponent is @p@: 17 significant digits when
the integer part has fewer than 17, none after the point otherwise.
-}
digitsAfterPoint :: Integer -> Integer
digitsAfterPoint p = max 0 (16 - p)

{- | Rounding to 17 significant digits (docs/adr ADR 0101): the nearest
decimal of @max 0 (16 - p)@ fractional digits, for @10^p <= |q| < 10^(p+1)@.
A number that is no finite decimal is never halfway between two of them,
so the rule for ties is never used.
-}
round17 :: Rational -> Rational
round17 q
  | q == 0 = 0
  | otherwise = roundTo (digitsAfterPoint (decimalExponent (abs q))) q

-- | The integer square root: the largest @s@ with @s * s <= n@, for @n >= 0@.
isqrt :: Integer -> Integer
isqrt n
  | n < 2 = n
  | otherwise = go start
  where
    -- a power of 2 at least the root
    start = 1 `shiftL` (fromIntegral (integerLog2 n) `div` 2 + 1)
    go x =
      let y = (x + n `div` x) `div` 2
       in if y >= x then x else go y

{- | The square root of a number of 0 or more (docs/adr ADR 0101): exact
when the numerator and the denominator in lowest terms are squares, the
rounding to 17 significant digits otherwise. With @k@ the fractional
digits, the root of @x × 10^(2k)@ is between @s@ and @s + 1@; comparing
@x × 10^(2k)@ with @(s + 1/2)^2@ picks the nearer, which is never a tie,
since then @x@ would be a square.
-}
sqrtRational :: Rational -> Rational
sqrtRational x
  | x <= 0 = 0
  | sn * sn == n && sd * sd == d = sn % sd
  | otherwise =
      let -- 10^(2p) <= x < 10^(2p+2)
          p = decimalExponent x `div` 2
          k = digitsAfterPoint p
          y = x * 10 ^ (2 * k)
          s = isqrt (floor y)
          s' = if y > (fromInteger s + 1 % 2) ^ (2 :: Int) then s + 1 else s
       in s' % 10 ^ k
  where
    n = numerator x
    d = denominator x
    sn = isqrt n
    sd = isqrt d

-- | pi rounded to 17 significant digits.
piValue :: Rational
piValue = 31415926535897932 % 10 ^ (16 :: Int)

-- | e rounded to 17 significant digits.
eValue :: Rational
eValue = 27182818284590452 % 10 ^ (16 :: Int)

-- | The most fractional digits of a number in prose, and of round and fixed.
maxFractionDigits :: Integer
maxFractionDigits = 1000

{- | The text of a number in prose (docs/adr ADR 0101): an integer in
digits; a finite decimal exactly; any other rational rounded to 17
significant digits. Positional, without trailing zeros, an exponent or
separators, with an ASCII minus. Left with the fractional digits when
they are over 1000.
-}
renderNumber :: Rational -> Either Integer Text
renderNumber q
  | denominator q == 1 = Right (T.pack (show (numerator q)))
  | otherwise =
      let exact = finiteDigits (denominator q)
          (k, v) = case exact of
            Just k' -> (k', q)
            Nothing -> let r = round17 q in (fromMaybe 0 (finiteDigits (denominator r)), r)
       in if k > maxFractionDigits then Left k else Right (positional k v)

{- | A number written exactly, for messages (docs/adr ADR 0102): a finite
decimal positionally, any other rational as a fraction (@7/3@).
-}
exactText :: Rational -> Text
exactText q = case finiteDigits (denominator q) of
  Just k -> positional k q
  Nothing -> T.pack (show (numerator q)) <> "/" <> T.pack (show (denominator q))

{- | The fractional digits of a finite decimal with this denominator: the
larger of the powers of 2 and 5 in it; Nothing when it has another prime
factor.
-}
finiteDigits :: Integer -> Maybe Integer
finiteDigits d =
  let (d2, a) = strip 2 d 0
      (d5, b) = strip 5 d2 0
   in if d5 == 1 then Just (max a b) else Nothing
  where
    strip f m c = if m `mod` f == 0 then strip f (m `div` f) (c + 1) else (m, c)

-- | A finite decimal of @k@ fractional digits, without trailing zeros.
positional :: Integer -> Rational -> Text
positional k v =
  let m = numerator (v * 10 ^ k)
      digits = T.pack (show (abs m))
      w = fromInteger k
      padded = T.replicate (w + 1 - T.length digits) "0" <> digits
      (ip, fp) = T.splitAt (T.length padded - w) padded
      fp' = T.dropWhileEnd (== '0') fp
      body = if T.null fp' then ip else ip <> "." <> fp'
   in (if m < 0 then "-" else "") <> body

floorDiv :: Integer -> Integer -> Integer
floorDiv = div

floorMod :: Integer -> Integer -> Integer
floorMod = mod
