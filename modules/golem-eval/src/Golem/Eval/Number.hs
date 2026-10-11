{- | Deterministic numeric rules of the expression language
(docs/markup.md "数の規則", golem-eval ADR 0001).
-}
module Golem.Eval.Number
  ( Decimal (..),
    finite,
    shortestDecimal,
    renderDouble,
    roundHalfAway,
    decimalToDouble,
    renderDecimalFixed,
    powInt,
    floorDiv,
    floorMod,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Numeric (floatToDigits)

-- | A finite decimal: @mantissa * 10^(-scale)@.
data Decimal = Decimal {decMantissa :: !Integer, decScale :: !Int}
  deriving stock (Eq, Show)

-- | NaN and infinities do not exist as values; negative zero becomes zero.
finite :: Double -> Maybe Double
finite x
  | isNaN x || isInfinite x = Nothing
  | x == 0 = Just 0
  | otherwise = Just x

-- | The shortest decimal that reads back as the same double.
shortestDecimal :: Double -> Decimal
shortestDecimal x
  | x == 0 = Decimal 0 0
  | x < 0 = let Decimal m s = shortestDecimal (negate x) in Decimal (negate m) s
  | otherwise =
      let (ds, e) = floatToDigits 10 x
          m = foldl (\acc d -> acc * 10 + toInteger d) 0 ds
          s = length ds - e
       in if s >= 0 then Decimal m s else Decimal (m * 10 ^ negate s) 0

-- | Positional notation, no exponent, no trailing ".0", ASCII minus.
renderDouble :: Double -> Text
renderDouble x = renderDecimal (shortestDecimal x)

renderDecimal :: Decimal -> Text
renderDecimal (Decimal m s)
  | s <= 0 = T.pack (show (m * 10 ^ negate s))
  | otherwise =
      let neg = m < 0
          digits = T.pack (show (abs m))
          padded = T.replicate (s + 1 - T.length digits) "0" <> digits
          (ip, fp) = T.splitAt (T.length padded - s) padded
          fp' = T.dropWhileEnd (== '0') fp
          body = if T.null fp' then ip else ip <> "." <> fp'
       in (if neg && body /= "0" then "-" else "") <> body

{- | Round the shortest decimal of a double to @n@ fractional digits,
ties away from zero.
-}
roundHalfAway :: Int -> Double -> Decimal
roundHalfAway n x =
  let Decimal m s = shortestDecimal x
   in if s <= n
        then Decimal (m * 10 ^ (n - s)) n
        else
          let q = 10 ^ (s - n)
              (d, r) = abs m `quotRem` q
              d' = if 2 * r >= q then d + 1 else d
           in Decimal (signum m * d') n

decimalToDouble :: Decimal -> Double
decimalToDouble (Decimal m s)
  | s >= 0 = fromRational (fromInteger m / fromInteger (10 ^ s))
  | otherwise = fromInteger (m * 10 ^ negate s)

-- | Exactly @n@ fractional digits (used by @fixed@).
renderDecimalFixed :: Decimal -> Text
renderDecimalFixed (Decimal m n)
  | n <= 0 = T.pack (show m)
  | otherwise =
      let digits = T.pack (show (abs m))
          padded = T.replicate (n + 1 - T.length digits) "0" <> digits
          (ip, fp) = T.splitAt (T.length padded - n) padded
       in (if m < 0 then "-" else "") <> ip <> "." <> fp

-- | Exponentiation by squaring in a fixed order.
powInt :: (a -> a -> a) -> a -> a -> Integer -> a
powInt mul one = go
  where
    go b k
      | k <= 0 = one
      | even k = let h = go b (k `div` 2) in mul h h
      | otherwise = mul b (go b (k - 1))

floorDiv :: Integer -> Integer -> Integer
floorDiv = div

floorMod :: Integer -> Integer -> Integer
floorMod = mod
