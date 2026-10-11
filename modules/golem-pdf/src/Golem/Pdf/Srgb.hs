{- | An sRGB ICC profile (version 4.3, display class) built from the
constants of IEC 61966-2-1, for RGB images that carry no profile
(golem-pdf ADR 0001). Built in code, so its bytes never change.
-}
module Golem.Pdf.Srgb
  ( srgbProfile,
  )
where

import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Int (Int32)
import Data.Word (Word8)

be32 :: Integer -> [Word8]
be32 n = [fromIntegral ((n `shiftR` s) .&. 0xff) | s <- [24, 16, 8, 0]]

be16 :: Integer -> [Word8]
be16 n = [fromIntegral ((n `shiftR` 8) .&. 0xff), fromIntegral (n .&. 0xff)]

-- | s15Fixed16Number.
fixed :: Rational -> [Word8]
fixed v = be32 (fromIntegral (fromIntegral (round (v * 65536) :: Integer) :: Int32) `mod` (2 ^ (32 :: Int)))

sig :: String -> [Word8]
sig = BS.unpack . BC.pack

pad :: [Word8] -> [Word8]
pad bs = bs <> replicate ((4 - length bs `mod` 4) `mod` 4) 0

xyz :: (Rational, Rational, Rational) -> [Word8]
xyz (x, y, z) = sig "XYZ " <> [0, 0, 0, 0] <> fixed x <> fixed y <> fixed z

mluc :: String -> [Word8]
mluc text =
  let utf16 = concat [be16 (fromIntegral (fromEnum c)) | c <- text]
   in sig "mluc" <> [0, 0, 0, 0] <> be32 1 <> be32 12 <> sig "enUS" <> be32 (fromIntegral (length utf16)) <> be32 28 <> utf16

-- | The sRGB transfer function: parametric curve type 3.
para :: [Word8]
para =
  sig "para"
    <> [0, 0, 0, 0]
    <> be16 3
    <> [0, 0]
    <> concatMap fixed [12 / 5, 1000 / 1055, 55 / 1055, 100 / 1292, 4045 / 100000]

srgbProfile :: ByteString
srgbProfile =
  let tags =
        [ ("desc", mluc "sRGB IEC61966-2.1 (Golem)"),
          ("cprt", mluc "No copyright, use freely"),
          ("wtpt", xyz (0.9642, 1, 0.8249)),
          ("chad", sig "sf32" <> [0, 0, 0, 0] <> concatMap fixed [1.0478112, 0.0228866, -0.0501270, 0.0295424, 0.9904844, -0.0170491, -0.0092345, 0.0150436, 0.7521316]),
          ("rXYZ", xyz (0.4360747, 0.2225045, 0.0139322)),
          ("gXYZ", xyz (0.3850649, 0.7168786, 0.0971045)),
          ("bXYZ", xyz (0.1430804, 0.0606169, 0.7141733)),
          ("rTRC", para),
          ("gTRC", para),
          ("bTRC", para)
        ]
      tableSize = 4 + 12 * length tags
      bodies = map (pad . snd) tags
      offsets = scanl (+) (128 + tableSize) (map length bodies)
      total = 128 + tableSize + sum (map length bodies)
      table = be32 (fromIntegral (length tags)) <> concat [sig name <> be32 (fromIntegral off) <> be32 (fromIntegral (length body)) | ((name, body), off) <- zip tags offsets]
      header =
        be32 (fromIntegral total)
          <> [0, 0, 0, 0] -- preferred CMM
          <> [0x04, 0x30, 0, 0] -- version 4.3
          <> sig "mntr"
          <> sig "RGB "
          <> sig "XYZ "
          <> concatMap be16 [2026, 1, 1, 0, 0, 0] -- creation date: fixed
          <> sig "acsp"
          <> [0, 0, 0, 0] -- platform
          <> [0, 0, 0, 0] -- flags
          <> [0, 0, 0, 0] -- manufacturer
          <> [0, 0, 0, 0] -- model
          <> replicate 8 0 -- attributes
          <> be32 0 -- rendering intent: perceptual
          <> fixed 0.9642
          <> fixed 1
          <> fixed 0.8249 -- PCS illuminant D50
          <> [0, 0, 0, 0] -- creator
          <> replicate 16 0 -- profile ID: zero means not computed, as in macOS's own v4 profiles
          <> replicate 28 0
   in BS.pack (header <> table <> concat bodies)
