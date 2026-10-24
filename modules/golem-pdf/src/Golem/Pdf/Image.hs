{- | Images for PDF (golem-pdf ADR 0001). JPEG is embedded as is
(DCTDecode); PNG pixels are taken out and compressed again with Flate.
ICC profiles are kept; Golem never converts image colours. Reading is
total and bounded (docs/adr ADR 0035): no input makes it throw or run
without end, and nothing is inflated beyond what the image needs.
-}
module Golem.Pdf.Image
  ( ImageData (..),
    ColorSpace (..),
    readImage,
    unfilterPng,
    inflateUpTo,
    flate,
  )
where

import Codec.Compression.Zlib qualified as Z
import Codec.Compression.Zlib.Internal qualified as ZI
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (sortOn)
import Data.Word (Word8)

data ColorSpace
  = CsGray
  | CsRgb
  | CsCmyk
  | -- | palette entries (RGB triples) and bits per index
    CsIndexed !ByteString
  deriving stock (Eq, Show)

data ImageData = ImageData
  { imgWidth :: !Int,
    imgHeight :: !Int,
    imgBits :: !Int,
    imgColor :: !ColorSpace,
    imgIcc :: !(Maybe ByteString),
    -- | the stream data: JPEG bytes (DCT) or raw samples (to be Flate-compressed)
    imgData :: !ByteString,
    imgDct :: !Bool,
    -- | Adobe CMYK JPEGs store inverted values
    imgInvertedCmyk :: !Bool,
    -- | alpha samples of PNG, as a soft mask
    imgAlpha :: !(Maybe ByteString)
  }
  deriving stock (Eq, Show)

readImage :: ByteString -> Either String ImageData
readImage b
  | BS.take 2 b == BS.pack [0xFF, 0xD8] = readJpeg b
  | BS.take 8 b == BS.pack [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] = readPng b
  | otherwise = Left "JPEG と PNG 以外の画像は使えません"

be16 :: ByteString -> Int -> Int
be16 b i = fromIntegral (BS.index b i) `shiftL` 8 .|. fromIntegral (BS.index b (i + 1))

be32 :: ByteString -> Int -> Int
be32 b i = be16 b i `shiftL` 16 .|. be16 b (i + 2)

-- ------------------------------------------------------------------ JPEG

readJpeg :: ByteString -> Either String ImageData
readJpeg b = go 2 Nothing [] False
  where
    go i sof iccs adobe
      | i + 4 > BS.length b = finish sof iccs adobe
      | BS.index b i /= 0xFF = Left "JPEG のマーカーが壊れています"
      | otherwise =
          let m = BS.index b (i + 1)
           in if m == 0xD9 || m == 0xDA
                then finish sof iccs adobe
                else
                  let len = be16 b (i + 2)
                      seg = BS.take (len - 2) (BS.drop (i + 4) b)
                      sof' = if isSof m then Just seg else sof
                      iccs' = if m == 0xE2 && BS.length seg >= 14 && BS.take 12 seg == "ICC_PROFILE\0" then (BS.index seg 12, BS.drop 14 seg) : iccs else iccs
                      adobe' = adobe || (m == 0xEE && BS.take 5 seg == "Adobe")
                   in go (i + 2 + len) sof' iccs' adobe'
    isSof m = m >= 0xC0 && m <= 0xCF && m `notElem` [0xC4, 0xC8, 0xCC]
    finish Nothing _ _ = Left "JPEG の SOF が見つかりません"
    finish (Just sof) _ _ | BS.length sof < 6 = Left "JPEG の SOF が壊れています"
    finish (Just sof) iccs adobe = do
      let bits = fromIntegral (BS.index sof 0)
          h = be16 sof 1
          w = be16 sof 3
          comps = BS.index sof 5
      cs <- case comps of
        1 -> Right CsGray
        3 -> Right CsRgb
        4 -> Right CsCmyk
        _ -> Left "JPEG の色の成分の数が不正です"
      let icc = if null iccs then Nothing else Just (BS.concat (map snd (sortOn fst iccs)))
      Right (ImageData w h bits cs icc b True (adobe && cs == CsCmyk) Nothing)

-- ------------------------------------------------------------------ PNG

-- | The most bytes of filtered samples a PNG may have: 512 MiB (docs/adr ADR 0035).
maxPngBytes :: Integer
maxPngBytes = 2 ^ (29 :: Int)

-- | The most bytes an ICC profile in iCCP may inflate to: 32 MiB (docs/adr ADR 0035).
maxIccBytes :: Int
maxIccBytes = 32 * 1024 * 1024

readPng :: ByteString -> Either String ImageData
readPng b = do
  chunks <- pngChunks (BS.drop 8 b)
  ihdr <- maybe (Left "PNG の IHDR がありません") Right (lookup "IHDR" chunks)
  if BS.length ihdr < 13 || be32 ihdr 0 == 0 || be32 ihdr 4 == 0 || be32 ihdr 0 > 0x7FFFFFFF || be32 ihdr 4 > 0x7FFFFFFF
    then Left "PNG の IHDR が壊れています"
    else Right ()
  let w = be32 ihdr 0
      h = be32 ihdr 4
      depth = fromIntegral (BS.index ihdr 8) :: Int
      ctype = BS.index ihdr 9
      interlace = BS.index ihdr 12
      idat = BS.concat [d | (n, d) <- chunks, n == "IDAT"]
  icc <- case lookup "iCCP" chunks of
    Nothing -> Right Nothing
    Just c ->
      let rest = BS.drop 1 (BS.dropWhile (/= 0) c)
       in case inflateUpTo (maxIccBytes + 1) (BS.drop 1 rest) of
            Left _ -> Left "PNG の ICC プロファイルを展開できません"
            Right p
              | BS.length p > maxIccBytes -> Left "PNG の ICC プロファイルが大きすぎます"
              | otherwise -> Right (Just p)
  if interlace /= 0
    then Left "インターレースの PNG は使えません"
    else do
      (channels, cs) <- case ctype of
        0 -> Right (1, CsGray)
        2 -> Right (3, CsRgb)
        3 -> maybe (Left "PNG のパレットがありません") (\p -> Right (1, CsIndexed p)) (lookup "PLTE" chunks)
        4 -> Right (2, CsGray)
        6 -> Right (4, CsRgb)
        _ -> Left "PNG の色の種類が不正です"
      if depth `notElem` allowedDepths ctype
        then Left "PNG のビット深度が色の種類に合いません"
        else Right ()
      -- the size in Integer, so that it cannot overflow (docs/adr ADR 0035)
      let rowBytesI = (toInteger w * toInteger channels * toInteger depth + 7) `div` 8
          needed = toInteger h * (rowBytesI + 1)
      if needed > maxPngBytes
        then Left "PNG の画像が大きすぎます"
        else Right ()
      let rowBytes = fromInteger rowBytesI
          bpp = max 1 ((channels * depth) `div` 8)
      -- only as many bytes as the rows need are inflated
      raw <- either (const (Left "PNG の画素のデータを展開できません")) Right (inflateUpTo (fromInteger needed) idat)
      pixels <- unfilterPng bpp rowBytes h raw
      let hasAlpha = ctype == 4 || ctype == 6
          sampleBytes = depth `div` 8
          (color, alpha)
            | hasAlpha =
                let px = channels * sampleBytes
                    colorBytes = (channels - 1) * sampleBytes
                    split i = (BS.take colorBytes (BS.drop i pixels), BS.take sampleBytes (BS.drop (i + colorBytes) pixels))
                    parts = [split i | i <- [0, px .. BS.length pixels - px]]
                 in (BS.concat (map fst parts), Just (BS.concat (map snd parts)))
            | otherwise = (pixels, Nothing)
      Right (ImageData w h depth cs icc color False False alpha)

-- | The bit depths the PNG specification allows for each colour type.
allowedDepths :: Word8 -> [Int]
allowedDepths = \case
  0 -> [1, 2, 4, 8, 16]
  2 -> [8, 16]
  3 -> [1, 2, 4, 8]
  4 -> [8, 16]
  6 -> [8, 16]
  _ -> []

{- | Flate (zlib) at level 9, the highest. The level decides the bytes of
every compressed stream of the output, so there is one place for it.
-}
flate :: ByteString -> ByteString
flate = BL.toStrict . Z.compressWith Z.defaultCompressParams {Z.compressLevel = Z.compressionLevel 9} . BL.fromStrict

{- | At most @limit@ bytes of a zlib stream, inflating no further; Left when
the stream is broken before that. A stream that ends early gives what it
has.
-}
inflateUpTo :: Int -> ByteString -> Either String ByteString
inflateUpTo limit input = go 0 [] stream
  where
    stream =
      ZI.foldDecompressStreamWithInput
        Chunk
        (const End)
        (Broken . show)
        (ZI.decompressST ZI.zlibFormat ZI.defaultDecompressParams)
        (BL.fromStrict input)
    go n acc = \case
      _ | n >= limit -> Right (BS.take limit (BS.concat (reverse acc)))
      Chunk c rest -> go (n + BS.length c) (c : acc) rest
      End -> Right (BS.concat (reverse acc))
      Broken e -> Left e

-- | The output of inflating, as far as it is read.
data Inflated = Chunk !ByteString Inflated | End | Broken String

pngChunks :: ByteString -> Either String [(ByteString, ByteString)]
pngChunks b
  | BS.length b < 12 = Right []
  | otherwise =
      let len = be32 b 0
          name = BS.take 4 (BS.drop 4 b)
          dat = BS.take len (BS.drop 8 b)
       in if BS.length dat < len
            then Left "PNG のチャンクが途中で切れています"
            else if name == "IEND" then Right [] else ((name, dat) :) <$> pngChunks (BS.drop (12 + len) b)

-- | Reverses the PNG scanline filters (None, Sub, Up, Average, Paeth).
unfilterPng :: Int -> Int -> Int -> ByteString -> Either String ByteString
unfilterPng bpp rowBytes h raw
  | BS.length raw < h * (rowBytes + 1) = Left "PNG の画素のデータが足りません"
  | otherwise = Right (BS.concat (reverse (snd (foldl' row (BS.replicate rowBytes 0, []) [0 .. h - 1]))))
  where
    row (prev, acc) y =
      let off = y * (rowBytes + 1)
          ftype = BS.index raw off
          line = BS.take rowBytes (BS.drop (off + 1) raw)
          out = decode ftype prev line
       in (out, out : acc)
    decode :: Word8 -> ByteString -> ByteString -> ByteString
    decode ftype prev line = BS.pack (reverse (foldl' go [] [0 .. rowBytes - 1]))
      where
        go done i =
          let x = BS.index line i
              a = if i >= bpp then done !! (bpp - 1) else 0
              b' = BS.index prev i
              c = if i >= bpp then BS.index prev (i - bpp) else 0
              v = case ftype of
                1 -> x + a
                2 -> x + b'
                3 -> x + fromIntegral ((fromIntegral a + fromIntegral b' :: Int) `div` 2)
                4 -> x + paeth a b' c
                _ -> x
           in v : done
    paeth :: Word8 -> Word8 -> Word8 -> Word8
    paeth a b c =
      let p = fromIntegral a + fromIntegral b - fromIntegral c :: Int
          pa = abs (p - fromIntegral a)
          pb = abs (p - fromIntegral b)
          pc = abs (p - fromIntegral c)
       in if pa <= pb && pa <= pc then a else if pb <= pc then b else c
