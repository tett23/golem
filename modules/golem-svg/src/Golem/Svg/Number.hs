{- | Numbers for SVG (golem-pdf ADR 0009): rationals throughout, and the
trigonometric functions and the square root as rational series cut at a
fixed number of terms, so that x86-64 and aarch64 give the same values
(docs/adr ADR 0002). Values that come out of a series are rounded to
'precisionBits' bits, which keeps the rationals small.

A number read from the SVG is 0, or between 'numberFloor' (10^-9) and
'numberLimit' (10^9) in absolute value (docs/adr ADR 0041, ADR 0083); a
number outside the range is not a number that can be read, and
'outOfRange' tells such a value apart from a malformed one.
-}
module Golem.Svg.Number
  ( parseNumber,
    numberPrefix,
    numberLimit,
    numberFloor,
    outOfRange,
    tooLarge,
    tooSmall,
    roundTo,
    sqrtR,
    cosDeg,
    sinDeg,
    tanDeg,
    atan2Deg,
    norm,
  )
where

import Data.Char (isDigit)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T

-- | The bits a value from a series is rounded to.
precisionBits :: Int
precisionBits = 40

roundTo :: Rational -> Rational
roundTo x = round (x * 2 ^ precisionBits) % (2 ^ precisionBits)

-- | The largest absolute value of a number read (docs/adr ADR 0041).
numberLimit :: Integer
numberLimit = 10 ^ (9 :: Int)

-- | The smallest absolute value of a number read that is not 0 (docs/adr ADR 0083).
numberFloor :: Rational
numberFloor = 1 % (10 ^ (9 :: Int))

-- | A whole SVG number: sign, digits, a fraction, an exponent.
parseNumber :: Text -> Maybe Rational
parseNumber t = case numberPrefix (T.strip t) of
  Just (v, rest) | T.null rest -> Just v
  _ -> Nothing

-- | A number at the start of a text and what follows it; none if it is outside the range.
numberPrefix :: Text -> Maybe (Rational, Text)
numberPrefix t = case lexNumber t of
  Just (Lexed sign mant e, rest) | not (outside mant e) -> Just (fromInteger sign * (mant % 1) * (10 ^^ e), rest)
  _ -> Nothing

{- | Whether a text has a number of the form of an SVG number whose value
is outside the range: larger than 'numberLimit', or not 0 and smaller
than 'numberFloor', in absolute value. Hexadecimal colours are the
caller's to leave out.
-}
outOfRange :: Text -> Bool
outOfRange = anyNumber outside

-- | Whether a text has a number larger than 'numberLimit' in absolute value.
tooLarge :: Text -> Bool
tooLarge = anyNumber exceeds

-- | Whether a text has a number that is not 0 and smaller than 'numberFloor' in absolute value.
tooSmall :: Text -> Bool
tooSmall = anyNumber below

-- | Whether some number of the form of an SVG number in a text is so, by its mantissa and exponent.
anyNumber :: (Integer -> Integer -> Bool) -> Text -> Bool
anyNumber p = go
  where
    go t = case T.uncons t of
      Nothing -> False
      Just (_, rest) -> case lexNumber t of
        Just (Lexed _ mant e, after) -> p mant e || go after
        Nothing -> go rest

-- | A number as its sign, its digits as an integer and the power of ten they are scaled by.
data Lexed = Lexed !Integer !Integer !Integer

outside :: Integer -> Integer -> Bool
outside mant e = exceeds mant e || below mant e

{- | Whether digits scaled by a power of ten exceed the limit, without
computing a power larger than the digits allow.
-}
exceeds :: Integer -> Integer -> Bool
exceeds mant e
  | mant == 0 = False
  | e > 9 = True
  | e >= 0 = mant * 10 ^ e > numberLimit
  | e < -60 = False
  | otherwise = mant > numberLimit * 10 ^ negate e

{- | Whether digits scaled by a power of ten are not 0 and below the floor,
without computing a power larger than the digits allow: 60 digits are
below 10^60, so with an exponent below -69 the value is below 10^-9.
-}
below :: Integer -> Integer -> Bool
below mant e
  | mant == 0 = False
  | e >= -9 = False
  | e < -69 = True
  | otherwise = mant < 10 ^ negate (e + 9)

-- | The form of an SVG number: at most 60 digits and an exponent of at most 4 digits.
lexNumber :: Text -> Maybe (Lexed, Text)
lexNumber t0 =
  let (sign, t1) = case T.uncons t0 of
        Just ('-', r) -> (-1, r)
        Just ('+', r) -> (1, r)
        _ -> (1, t0)
      (int, t2) = T.span isDigit t1
      (frac, t3) = case T.uncons t2 of
        Just ('.', r) -> T.span isDigit r
        _ -> ("", t2)
      (ex, t4) = case T.uncons t3 of
        Just (e, r)
          | e == 'e' || e == 'E',
            let (es, r') = case T.uncons r of
                  Just ('-', r'') -> (-1, r'')
                  Just ('+', r'') -> (1, r'')
                  _ -> (1, r),
            let (ds, r''') = T.span isDigit r',
            not (T.null ds),
            T.length ds <= 4 ->
              (es * read (T.unpack ds), r''')
        _ -> (0 :: Integer, t3)
   in if (T.null int && T.null frac) || T.length int + T.length frac > 60
        then Nothing
        else
          let digits = int <> frac
              mant = if T.null digits then 0 else read (T.unpack digits) :: Integer
              scale = toInteger (T.length frac)
           in Just (Lexed sign mant (ex - scale), t4)

-- | The square root, by the integer square root of the value scaled.
sqrtR :: Rational -> Rational
sqrtR x
  | x <= 0 = 0
  | otherwise =
      let s = 2 ^ precisionBits :: Integer
          n = floor (x * fromInteger (s * s)) :: Integer
       in isqrt n % s

isqrt :: Integer -> Integer
isqrt n
  | n < 2 = n
  | otherwise = go n
  where
    go x = let y = (x + n `div` x) `div` 2 in if y >= x then x else go y

-- | The length of a vector.
norm :: (Rational, Rational) -> Rational
norm (x, y) = sqrtR (x * x + y * y)

-- | π to 40 decimals.
piR :: Rational
piR = 31415926535897932384626433832795028841971 % (10 ^ (40 :: Int))

-- | The cosine and sine of an angle in degrees; exact at multiples of 90.
cosSinDeg :: Rational -> (Rational, Rational)
cosSinDeg d0 =
  let d = d0 - 360 * fromInteger (floor (d0 / 360))
   in case d of
        0 -> (1, 0)
        90 -> (0, 1)
        180 -> (-1, 0)
        270 -> (0, -1)
        _ ->
          -- to [-45, 45] by the quarter turns
          let q = round (d / 90) :: Integer
              r = (d - 90 * fromInteger q) * piR / 180
              c = roundTo (series 1 (\k -> negate (r * r) / fromInteger ((2 * k - 1) * (2 * k))))
              s = roundTo (r * series 1 (\k -> negate (r * r) / fromInteger ((2 * k) * (2 * k + 1))))
           in case q `mod` 4 of
                0 -> (c, s)
                1 -> (-s, c)
                2 -> (-c, -s)
                _ -> (s, -c)
  where
    -- 1 + t1 + t1 t2 + ...: 16 terms, enough for |r| <= pi/4 at 40 bits
    series :: Rational -> (Integer -> Rational) -> Rational
    series first ratio = sum (take 16 (scanl (\acc k -> acc * ratio k) first [1 ..]))

cosDeg :: Rational -> Rational
cosDeg = fst . cosSinDeg

sinDeg :: Rational -> Rational
sinDeg = snd . cosSinDeg

tanDeg :: Rational -> Rational
tanDeg d = let (c, s) = cosSinDeg d in if c == 0 then 0 else roundTo (s / c)

{- | The angle of a vector in degrees, in (-180, 180]: atan by halving the
argument twice and a series.
-}
atan2Deg :: Rational -> Rational -> Rational
atan2Deg y x
  | x == 0 && y == 0 = 0
  | x == 0 = if y > 0 then 90 else -90
  | y == 0 = if x > 0 then 0 else 180
  | abs y <= abs x =
      let a = atanR (y / x)
       in if x > 0 then a else if y > 0 then a + 180 else a - 180
  | otherwise = let a = atanR (x / y) in if y > 0 then 90 - a else -90 - a
  where
    -- atan z for |z| <= 1, in degrees
    atanR z =
      let half v = roundTo (v / (1 + sqrtR (1 + v * v)))
          w = half (half z)
          t = sum (take 20 (zipWith (\k p -> p / fromInteger (2 * k + 1) * (if even k then 1 else -1)) [0 :: Integer ..] (iterate (* (w * w)) w)))
       in roundTo (4 * t * 180 / piR)
