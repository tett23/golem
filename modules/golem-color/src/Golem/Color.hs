-- | Pure arithmetic on color components. Inputs to the constructors are bounded.
module Golem.Color
  ( Rgb,
    Cmyk,
    Gray,
    Rgb8,
    Rgb16,
    Cmyk8,
    Cmyk16,
    rgb,
    cmyk,
    gray,
    rgb8,
    rgb16,
    rgbComponents,
    rgb8Components,
    cmykComponents,
    grayComponent,
    cmyk8Components,
    cmyk16Components,
    rgbToCmyk,
    cmykToRgb,
    rgb8ToCmyk8,
    rgb16ToCmyk16,
    ycbcr8ToRgb8,
    ycck8ToCmyk8,
    cmykPercentToRgb8,
    neutralCmykGray,
    neutralCmykGrayRaw,
    tintCmyk,
    tintPercent,
    rgb8OfTintPercent,
    rgb16OfTintPercent,
    quantizeEven,
    quantizeHalfUp,
    nearestHalfUp,
    shadingTintMap,
    percentageToRgb8,
    sampleRatio,
    decodeRange,
    affine,
    percentRatio,
    labNeutralGray,
    labNeutralShadingSlope,
    invert8,
    clampUnit,
    clipRange,
    normalizeRange,
    normalizeRangeClipped,
    rangeToUnitMap,
    blackRangeToGrayMap,
    unmatte,
    hexNibbleTo8,
    hexPairTo8,
    clampRgb8,
    labLightnessRange,
  )
where

import Data.Bits (shiftR)
import Data.Word (Word64, Word8)

data Rgb = Rgb !Rational !Rational !Rational deriving (Eq, Show)

data Cmyk = Cmyk !Rational !Rational !Rational !Rational deriving (Eq, Show)

newtype Gray = Gray Rational deriving (Eq, Show)

data Rgb8 = Rgb8 !Int !Int !Int deriving (Eq, Show)

data Rgb16 = Rgb16 !Int !Int !Int deriving (Eq, Show)

data Cmyk8 = Cmyk8 !Int !Int !Int !Int deriving (Eq, Show)

data Cmyk16 = Cmyk16 !Int !Int !Int !Int deriving (Eq, Show)

bounded :: (Ord a, Num a) => a -> a -> Bool
bounded top value = value >= 0 && value <= top

rgb :: Rational -> Rational -> Rational -> Maybe Rgb
rgb r g b | all (bounded 1) [r, g, b] = Just (Rgb r g b)
rgb _ _ _ = Nothing

cmyk :: Rational -> Rational -> Rational -> Rational -> Maybe Cmyk
cmyk c m y k | all (bounded 1) [c, m, y, k] = Just (Cmyk c m y k)
cmyk _ _ _ _ = Nothing

gray :: Rational -> Maybe Gray
gray g | bounded 1 g = Just (Gray g)
gray _ = Nothing

rgb8 :: Int -> Int -> Int -> Maybe Rgb8
rgb8 r g b | all (bounded 255) [r, g, b] = Just (Rgb8 r g b)
rgb8 _ _ _ = Nothing

rgb16 :: Int -> Int -> Int -> Maybe Rgb16
rgb16 r g b | all (bounded 65535) [r, g, b] = Just (Rgb16 r g b)
rgb16 _ _ _ = Nothing

rgbComponents :: Rgb -> (Rational, Rational, Rational)
rgbComponents (Rgb r g b) = (r, g, b)

rgb8Components :: Rgb8 -> (Int, Int, Int)
rgb8Components (Rgb8 r g b) = (r, g, b)

cmykComponents :: Cmyk -> (Rational, Rational, Rational, Rational)
cmykComponents (Cmyk c m y k) = (c, m, y, k)

grayComponent :: Gray -> Rational
grayComponent (Gray g) = g

cmyk8Components :: Cmyk8 -> (Int, Int, Int, Int)
cmyk8Components (Cmyk8 c m y k) = (c, m, y, k)

cmyk16Components :: Cmyk16 -> (Int, Int, Int, Int)
cmyk16Components (Cmyk16 c m y k) = (c, m, y, k)

-- | The one fixed, uncalibrated inverse approximation of CSS Color 5 §6.1.
rgbToCmyk :: Rgb -> Cmyk
rgbToCmyk (Rgb r g b)
  | v == 0 = Cmyk 0 0 0 1
  | otherwise = Cmyk ((v - r) / v) ((v - g) / v) ((v - b) / v) (1 - v)
  where
    v = max r (max g b)

cmykToRgb :: Cmyk -> Rgb
cmykToRgb (Cmyk c m y k) = let (r, g, b) = cmykToRgbRaw (c, m, y, k) in Rgb r g b

-- | Round a nonnegative rational to nearest, ties to even.
quantizeEven :: Int -> Rational -> Int
quantizeEven top x = round (fromIntegral top * x)

-- | PDF Decode range quantization uses half-up, not ties-to-even.
quantizeHalfUp :: Int -> Rational -> Int
quantizeHalfUp top x = floor (fromIntegral top * x + 1 / 2)

nearestHalfUp :: Rational -> Integer
nearestHalfUp x = floor (x + 1 / 2)

-- | Integer form of the same inverse. The numerator fits in Word64.
inverseInteger :: Int -> (Int, Int, Int) -> (Int, Int, Int, Int)
inverseInteger top (r, g, b) = (channel r, channel g, channel b, top - v)
  where
    v = max r (max g b)
    channel _ | v == 0 = 0
    channel x = fromIntegral (q + if 2 * remnant > denominator || (2 * remnant == denominator && odd q) then 1 else 0)
      where
        numerator = fromIntegral top * fromIntegral (v - x) :: Word64
        denominator = fromIntegral v :: Word64
        (q, remnant) = numerator `quotRem` denominator

rgb8ToCmyk8 :: Rgb8 -> Cmyk8
rgb8ToCmyk8 (Rgb8 r g b) = let (c, m, y, k) = inverseInteger 255 (r, g, b) in Cmyk8 c m y k

rgb16ToCmyk16 :: Rgb16 -> Cmyk16
rgb16ToCmyk16 (Rgb16 r g b) = let (c, m, y, k) = inverseInteger 65535 (r, g, b) in Cmyk16 c m y k

{- | The fixed-point YCbCr arithmetic from JuicyPixels 3.3.9 (BSD-3-Clause;
see LICENSE-JuicyPixels). The JPEG
decoder and its marker handling remain in golem-typeset.
-}
ycbcr8ToRgb8 :: Word8 -> Word8 -> Word8 -> Rgb8
ycbcr8ToRgb8 y cb cr = Rgb8 (clamp (yi + crR)) (clamp (yi + green)) (clamp (yi + cbB))
  where
    yi = fromIntegral y
    cbi = fromIntegral cb - 128
    cri = fromIntegral cr - 128
    crR = (91881 * cri + 32768) `shiftR` 16
    cbB = (116130 * cbi + 32768) `shiftR` 16
    green = ((-(22554 * cbi) + 32768) - 46802 * cri) `shiftR` 16
    clamp = max 0 . min 255

ycck8ToCmyk8 :: Word8 -> Word8 -> Word8 -> Word8 -> Cmyk8
ycck8ToCmyk8 y cb cr k =
  let Rgb8 r g b = ycbcr8ToRgb8 y cb cr
   in Cmyk8 (255 - r) (255 - g) (255 - b) (fromIntegral k)

-- | Existing percent swatches for HTML and screen PDF. Their public APIs stay tuples.
cmykPercentToRgb8 :: (Int, Int, Int, Int) -> (Int, Int, Int)
cmykPercentToRgb8 (c, m, y, k) =
  let (r, g, b) = cmykToRgbRaw (fromIntegral c / 100, fromIntegral m / 100, fromIntegral y / 100, fromIntegral k / 100)
   in (quantizeEven 255 r, quantizeEven 255 g, quantizeEven 255 b)

cmykToRgbRaw :: (Rational, Rational, Rational, Rational) -> (Rational, Rational, Rational)
cmykToRgbRaw (c, m, y, k) = ((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k))

neutralCmykGray :: Cmyk -> Maybe Rational
neutralCmykGray (Cmyk c m y k)
  | c == m && m == y = Just (neutralCmykGrayRaw c k)
  | otherwise = Nothing

-- | Existing PDF component operands can be outside the nominal unit interval.
neutralCmykGrayRaw :: Rational -> Rational -> Rational
neutralCmykGrayRaw c k = (1 - c) * (1 - k)

-- | Apply the ink amount 1 - the gray brightness to a selected swatch.
tintCmyk :: Cmyk -> Gray -> Cmyk
tintCmyk (Cmyk c m y k) (Gray g) = let amount = 1 - g in Cmyk (c * amount) (m * amount) (y * amount) (k * amount)

tintPercent :: (Int, Int, Int, Int) -> Rational -> (Rational, Rational, Rational, Rational)
tintPercent (c, m, y, k) brightness =
  let amount = (1 - brightness) / 100
   in (fromIntegral c * amount, fromIntegral m * amount, fromIntegral y * amount, fromIntegral k * amount)

rgb8OfTintPercent :: (Int, Int, Int, Int) -> Rational -> (Int, Int, Int)
rgb8OfTintPercent swatch brightness =
  let (r, g, b) = cmykToRgbRaw (tintPercent swatch brightness)
   in (quantizeEven 255 r, quantizeEven 255 g, quantizeEven 255 b)

rgb16OfTintPercent :: (Int, Int, Int, Int) -> Rational -> (Int, Int, Int)
rgb16OfTintPercent swatch brightness =
  let (r, g, b) = cmykToRgbRaw (tintPercent swatch brightness)
   in (quantizeEven 65535 r, quantizeEven 65535 g, quantizeEven 65535 b)

-- | For gray brightness g = alpha*v + beta, ink = swatch*(1-g).
shadingTintMap :: (Int, Int, Int, Int) -> Rational -> Rational -> [(Rational, Rational)]
shadingTintMap (c, m, y, k) alpha beta =
  let inks = map ((/ 100) . fromIntegral) [c, m, y, k]
   in [(negate (s * alpha), s * (1 - beta)) | s <- inks]

-- | CSS rgb() percentage components are rounded and then clamped.
percentageToRgb8 :: Rational -> Int
percentageToRgb8 p = max 0 (min 255 (round (p * 255 / 100)))

sampleRatio :: Int -> Int -> Rational
sampleRatio value maximumSample = fromIntegral value / fromIntegral maximumSample

decodeRange :: Rational -> Rational -> Integer -> Integer -> Rational
decodeRange low high maximumSample sample = low + fromInteger sample * (high - low) / fromInteger maximumSample

affine :: (Rational, Rational) -> Rational -> Rational
affine (a, b) value = a * value + b

percentRatio :: Int -> Rational
percentRatio value = fromIntegral value / 100

labNeutralGray :: Rational -> Rational
labNeutralGray lightness = max 0 (min 100 lightness) / 100

labNeutralShadingSlope :: Rational
labNeutralShadingSlope = 1 / 100

-- | Reverse an encoded 8-bit sample without changing its color space.
invert8 :: Word8 -> Word8
invert8 = (255 -)

clampUnit :: Rational -> Rational
clampUnit = max 0 . min 1

clipRange :: (Rational, Rational) -> Rational -> Rational
clipRange (low, high) = max low . min high

normalizeRange :: (Rational, Rational) -> Rational -> Rational
normalizeRange (low, high) value = (value - low) / (high - low)

normalizeRangeClipped :: (Rational, Rational) -> Rational -> Rational
normalizeRangeClipped range value = normalizeRange range (clipRange range value)

rangeToUnitMap :: (Rational, Rational) -> (Rational, Rational)
rangeToUnitMap (low, high) = (1 / (high - low), negate low / (high - low))

blackRangeToGrayMap :: (Rational, Rational) -> (Rational, Rational)
blackRangeToGrayMap (low, high) = (negate 1 / (high - low), 1 + low / (high - low))

unmatte :: Rational -> Rational -> Rational -> Rational
unmatte matte value opacity = matte + (value - matte) / opacity

hexNibbleTo8 :: Int -> Int
hexNibbleTo8 nibble = 17 * nibble

hexPairTo8 :: Int -> Int -> Int
hexPairTo8 high low = 16 * high + low

clampRgb8 :: Integer -> Int
clampRgb8 = fromInteger . max 0 . min 255

labLightnessRange :: (Rational, Rational) -> (Rational, Rational)
labLightnessRange (low, high) = (max 0 low, min 100 high)
