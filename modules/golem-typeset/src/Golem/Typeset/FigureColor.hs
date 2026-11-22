{-# LANGUAGE TypeFamilies #-}

-- | Monochrome figure colours shared by raster and PDF import (root ADR 0403).
module Golem.Typeset.FigureColor
  ( Cmyk,
    RasterKind (..),
    RasterAnalysis (..),
    analyzeRaster,
    safeAnalyzeRaster,
    safeRecolorRasterBytes,
    guardColorConversion,
    forceRasterAnalysis,
    forceImportedPage,
    recolorRasterBytes,
    rgbTone,
  )
where

import Codec.Picture.Jpg qualified as Jpeg
import Codec.Picture.Png qualified as Png
import Codec.Picture.Types qualified as J
import Control.Exception (SomeAsyncException, SomeException, displayException, evaluate, fromException, tryJust)
import Control.Monad (unless)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.ByteString.Internal qualified as BSI
import Data.ByteString.Lazy qualified as BL
import Data.List (nub)
import Data.Ratio (denominator, numerator, (%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Vector.Storable qualified as V
import Data.Word (Word8)
import Golem.Pdf qualified as P
import Golem.Pdf.Object (ObjOf (..))

-- | The selected swatch, each component as a percentage from zero to one hundred.
type Cmyk = (Int, Int, Int, Int)

data RasterKind
  = Unpainted
  | Grayscale
  | SolidRgb !(Rational, Rational, Rational)
  | SolidCmyk !(Rational, Rational, Rational, Rational)
  | Multicolor
  deriving stock (Eq, Show)

data RasterAnalysis = RasterAnalysis
  { raKind :: !RasterKind,
    -- | Converted uncompressed DeviceCMYK pixels, with dimensions and alpha unchanged.
    raImage :: !(Maybe P.ImageData)
  }
  deriving stock (Eq, Show)

-- | A pixel's exact components and their common maximum sample value.
data Pixel = Gray !Int !Int | Rgb !Int !Int !Int !Int | Cmyk !Int !Int !Int !Int !Int | InvalidPixel
  deriving stock (Eq)

data Seen = NoPixels | Grays | One !Pixel | Many

-- | The existing PNG expansion limit also bounds colour conversion and JPEG decoding.
maxColorBytes :: Integer
maxColorBytes = 512 * 1024 * 1024

analyzeRaster :: Cmyk -> P.ImageData -> Either Text RasterAnalysis
analyzeRaster swatch image = fst <$> recolorRaster swatch image

-- | Catch synchronous codec failures while forcing every returned raster buffer.
safeAnalyzeRaster :: Cmyk -> P.ImageData -> IO (Either Text RasterAnalysis)
safeAnalyzeRaster swatch image = guardColorConversion forceRasterAnalysis (analyzeRaster swatch image)

safeRecolorRasterBytes :: Cmyk -> BS.ByteString -> IO (Either Text (Maybe (P.ImageData, BS.ByteString)))
safeRecolorRasterBytes swatch bytes = guardColorConversion forceChanged (recolorRasterBytes swatch bytes)
  where
    forceChanged Nothing = ()
    forceChanged (Just (image, png)) = forceImage image `seq` BS.length png `seq` ()

-- | Evaluation stays inside the boundary; cancellation and other asynchronous exceptions propagate.
guardColorConversion :: (a -> ()) -> Either Text a -> IO (Either Text a)
guardColorConversion force result = do
  caught <- tryJust synchronous (evaluate evaluated)
  pure $ case caught of
    Left problem -> Left (T.pack (displayException problem))
    Right value -> value
  where
    synchronous :: SomeException -> Maybe SomeException
    synchronous problem = case (fromException problem :: Maybe SomeAsyncException) of
      Just _ -> Nothing
      Nothing -> Just problem
    evaluated = case result of
      Left why -> T.length why `seq` Left why
      Right value -> force value `seq` Right value

forceRasterAnalysis :: RasterAnalysis -> ()
forceRasterAnalysis analysis = forceKind (raKind analysis) `seq` maybe () forceImage (raImage analysis)
  where
    forceKind (SolidRgb (r, g, b)) = tone r `seq` tone g `seq` tone b
    forceKind (SolidCmyk (c, m, y, k)) = tone c `seq` tone m `seq` tone y `seq` tone k
    forceKind other = other `seq` ()
    tone value = numerator value `seq` denominator value `seq` ()

forceImage :: P.ImageData -> ()
forceImage image = BS.length (P.imgData image) `seq` maybe () (\alpha -> BS.length (P.alphaSamples alpha) `seq` ()) (P.imgAlpha image)

-- | Force converted PDF streams and nested resources before leaving the codec boundary.
forceImportedPage :: P.ImportedPage -> ()
forceImportedPage page =
  BS.length (P.ipFile page)
    `seq` BS.length (P.ipContent page)
    `seq` box (P.ipBox page)
    `seq` size (P.ipSize page)
    `seq` object (P.ipResources page)
    `seq` maybe () object (P.ipGroup page)
    `seq` foldr (\(key, value) rest -> key `seq` object value `seq` rest) () (P.ipObjects page)
    `seq` foldr (\color rest -> case color of P.UseIcc n bytes -> n `seq` BS.length bytes `seq` rest; _ -> color `seq` rest) () (P.ipColors page)
  where
    tone value = numerator value `seq` denominator value `seq` ()
    box (a, b, c, d) = tone a `seq` tone b `seq` tone c `seq` tone d
    size (w, h) = tone w `seq` tone h
    dictionary = foldr (\(key, value) rest -> T.length key `seq` object value `seq` rest) ()
    object = \case
      ODict pairs -> dictionary pairs
      OArr values -> foldr (\value rest -> object value `seq` rest) () values
      OStream pairs bytes -> dictionary pairs `seq` BS.length bytes `seq` ()
      OStr bytes -> BS.length bytes `seq` ()
      OHex bytes -> BS.length bytes `seq` ()
      OName name -> T.length name `seq` ()
      OReal number -> T.length number `seq` ()
      OInt number -> number `seq` ()
      ORef key -> key `seq` ()
      OBool value -> value `seq` ()
      ONull -> ()

-- | Return PNG only for a figure whose colour changes. A multi-colour source is not re-encoded.
recolorRasterBytes :: Cmyk -> BS.ByteString -> Either Text (Maybe (P.ImageData, BS.ByteString))
recolorRasterBytes swatch bytes = do
  original <- either (Left . T.pack) Right (P.readImage bytes)
  (analysis, png) <- recolorRaster swatch original
  pure ((,) <$> raImage analysis <*> png)

recolorRaster :: Cmyk -> P.ImageData -> Either Text (RasterAnalysis, Maybe BS.ByteString)
recolorRaster swatch original = do
  checkDimensions original
  image <- if P.imgDct original then decodeDct original else pure original
  validateSamples image
  seen <- scan image 0 NoPixels
  let kind = case seen of
        NoPixels -> Unpainted
        Grays -> Grayscale
        One (Rgb r g b m) -> SolidRgb (ratio r m, ratio g m, ratio b m)
        One (Cmyk c m y k top) -> SolidCmyk (ratio c top, ratio m top, ratio y top, ratio k top)
        _ -> Multicolor
  if kind == Multicolor || kind == Unpainted
    then pure (RasterAnalysis kind Nothing, Nothing)
    else do
      let bits = if P.imgBits image == 16 || maybe False ((== 16) . P.alphaBits) (P.imgAlpha image) then 16 else 8
          maximumSample = 2 ^ bits - 1 :: Int
          pixels = P.imgWidth image * P.imgHeight image
          shade pixel = if kind == Grayscale then 1 - grayValue (pixelAt image pixel) else 1
          components pixel = let (c, m, y, k) = swatch; d = shade pixel / 100 in (fromIntegral c * d, fromIntegral m * d, fromIntegral y * d, fromIntegral k * d)
          component pixel channel = case components pixel of (c, m, y, k) -> [c, m, y, k] !! channel
          sample pixel channel = fromInteger (round (fromIntegral maximumSample * component pixel channel) :: Integer) :: Int
          byteAt i =
            let sampleIndex = if bits == 16 then i `div` 2 else i
                value = sample (sampleIndex `div` 4) (sampleIndex `mod` 4)
             in fromIntegral (if bits == 16 && even i then value `shiftR` 8 else value .&. 255)
          size = pixels * 4 * (bits `div` 8)
          bytes = fst (BS.unfoldrN size (\i -> Just (byteAt i, i + 1)) 0)
          converted = image {P.imgBits = bits, P.imgColor = P.CsCmyk, P.imgIcc = Nothing, P.imgData = bytes, P.imgDct = False, P.imgInvertedCmyk = False}
          rgb pixel channel = case rgbComponents (components pixel) of (r, g, b) -> [r, g, b] !! channel
          alpha pixel = maybe maximumSample (\a -> let (v, m) = alphaAt image a pixel in round (fromIntegral maximumSample * ratio v m)) (P.imgAlpha image)
          png8 = Png.encodePng (J.Image (P.imgWidth image) (P.imgHeight image) (V.generate (pixels * 4) (\i -> if i `mod` 4 == 3 then fromIntegral (alpha (i `div` 4)) else fromIntegral (round (255 * rgb (i `div` 4) (i `mod` 4)) :: Int))) :: J.Image J.PixelRGBA8)
          png16 = Png.encodePng (J.Image (P.imgWidth image) (P.imgHeight image) (V.generate (pixels * 4) (\i -> if i `mod` 4 == 3 then fromIntegral (alpha (i `div` 4)) else fromIntegral (round (65535 * rgb (i `div` 4) (i `mod` 4)) :: Int))) :: J.Image J.PixelRGBA16)
      pure (RasterAnalysis kind (Just converted), Just (BL.toStrict (if bits == 16 then png16 else png8)))
  where
    scan image i seen
      | i == P.imgWidth image * P.imgHeight image = pure seen
      | maybe False ((== 0) . fst . (\a -> alphaAt image a i)) (P.imgAlpha image) = scan image (i + 1) seen
      | otherwise = case pixelAt image i of
          InvalidPixel -> Left "図版のパレットの画素が範囲外です"
          pixel -> case (seen, isGray pixel) of
            (NoPixels, True) -> scan image (i + 1) Grays
            (NoPixels, False) -> scan image (i + 1) (One pixel)
            (Grays, True) -> scan image (i + 1) Grays
            (One first, False) | pixel == first -> scan image (i + 1) seen
            _ -> pure Many

ratio :: Int -> Int -> Rational
ratio value maximumSample = toInteger value % toInteger maximumSample

isGray :: Pixel -> Bool
isGray = \case
  Gray _ _ -> True
  Rgb r g b _ -> r == g && g == b
  Cmyk c m y _ _ -> c == m && m == y
  InvalidPixel -> False

grayValue :: Pixel -> Rational
grayValue = \case
  Gray g m -> ratio g m
  Rgb r _ _ m -> ratio r m
  Cmyk c _ _ k m -> (1 - ratio c m) * (1 - ratio k m)
  InvalidPixel -> 1 -- only an invisible palette pixel can reach conversion

-- | The CMYK tone is computed before the screen approximation, without intermediate rounding.
rgbTone :: Cmyk -> Rational -> (Int, Int, Int)
rgbTone (c, m, y, k) gray =
  let d = (1 - gray) / 100
      (r, g, b) = rgbComponents (fromIntegral c * d, fromIntegral m * d, fromIntegral y * d, fromIntegral k * d)
   in (round (255 * r), round (255 * g), round (255 * b))

rgbComponents :: (Rational, Rational, Rational, Rational) -> (Rational, Rational, Rational)
rgbComponents (c, m, y, k) = ((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k))

checkDimensions :: P.ImageData -> Either Text ()
checkDimensions image = do
  unless (P.imgWidth image > 0 && P.imgHeight image > 0) (Left "図版の寸法が不正です")
  let bytesPerSample = if P.imgBits image > 8 || maybe False ((> 8) . P.alphaBits) (P.imgAlpha image) then 2 else 1
      size = toInteger (P.imgWidth image) * toInteger (P.imgHeight image) * 4 * bytesPerSample
  unless (size <= maxColorBytes) (Left "図版の色変換の展開後サイズが 512 MiB を超えます")

validateSamples :: P.ImageData -> Either Text ()
validateSamples image = do
  unless (P.imgBits image `elem` [1, 2, 4, 8, 16]) (Left "図版の画素のビット数を扱えません")
  let channels = case P.imgColor image of P.CsGray -> 1; P.CsRgb -> 3; P.CsCmyk -> 4; P.CsIndexed _ -> 1
  unless (toInteger (BS.length (P.imgData image)) >= sampleBytes (P.imgBits image) channels) (Left "図版の画素が途中で終わっています")
  case P.imgAlpha image of
    Nothing -> pure ()
    Just alpha -> do
      unless (P.alphaBits alpha `elem` [1, 2, 4, 8, 16]) (Left "図版の不透明度のビット数を扱えません")
      unless (toInteger (BS.length (P.alphaSamples alpha)) >= sampleBytes (P.alphaBits alpha) 1) (Left "図版の不透明度が途中で終わっています")
  where
    sampleBytes bits channels = ((toInteger (P.imgWidth image) * channels * toInteger bits + 7) `div` 8) * toInteger (P.imgHeight image)

pixelAt :: P.ImageData -> Int -> Pixel
pixelAt image pixel =
  let bits = P.imgBits image
      top = 2 ^ bits - 1
      at channels = sampleAt (P.imgData image) (P.imgWidth image) channels bits pixel
   in case P.imgColor image of
        P.CsGray -> Gray (at 1 0) top
        P.CsRgb -> Rgb (at 3 0) (at 3 1) (at 3 2) top
        P.CsCmyk -> Cmyk (at 4 0) (at 4 1) (at 4 2) (at 4 3) top
        P.CsIndexed palette ->
          let index = at 1 0 * 3
           in if index + 2 >= BS.length palette then InvalidPixel else Rgb (fromIntegral (BS.index palette index)) (fromIntegral (BS.index palette (index + 1))) (fromIntegral (BS.index palette (index + 2))) 255

sampleAt :: BS.ByteString -> Int -> Int -> Int -> Int -> Int -> Int
sampleAt bytes width channels bits pixel channel =
  let perByte = if bits < 8 then 8 `div` bits else 1
      rowBytes = if bits >= 8 then width * channels * (bits `div` 8) else (width * channels + perByte - 1) `div` perByte
      sample = (pixel `mod` width) * channels + channel
      byte = (pixel `div` width) * rowBytes + (if bits >= 8 then sample * (bits `div` 8) else sample `div` perByte)
      within = if bits >= 8 then 0 else (sample `mod` perByte) * bits
   in if bits == 16
        then fromIntegral (BS.index bytes byte) * 256 + fromIntegral (BS.index bytes (byte + 1))
        else (fromIntegral (BS.index bytes byte) `shiftR` (8 - bits - within)) .&. (2 ^ bits - 1)

alphaAt :: P.ImageData -> P.Alpha -> Int -> (Int, Int)
alphaAt image alpha pixel = (sampleAt (P.alphaSamples alpha) (P.imgWidth image) 1 (P.alphaBits alpha) pixel 0, 2 ^ P.alphaBits alpha - 1)

decodeDct :: P.ImageData -> Either Text P.ImageData
decodeDct image = do
  checkJpegFrames (P.imgData image)
  decoded <- either (Left . T.pack) Right (Jpeg.decodeJpeg (P.imgData image))
  unpacked <- case decoded of
    J.ImageY8 pixels -> pure (fromPixels P.CsGray pixels)
    J.ImageRGB8 pixels -> pure (fromPixels P.CsRgb pixels)
    J.ImageYCbCr8 pixels -> pure (fromPixels P.CsRgb (J.convertImage pixels :: J.Image J.PixelRGB8))
    J.ImageCMYK8 pixels -> pure (fromPixels P.CsCmyk pixels)
    _ -> Left "JPEG の画素の形式を扱えません"
  unless (P.imgWidth unpacked == P.imgWidth image && P.imgHeight unpacked == P.imgHeight image) (Left "JPEG の画素と宣言した寸法が一致しません")
  pure unpacked
  where
    fromPixels :: (J.PixelBaseComponent pixel ~ Word8) => P.ColorSpace -> J.Image pixel -> P.ImageData
    fromPixels color pixels =
      let (pointer, offset, size) = V.unsafeToForeignPtr (J.imageData pixels)
       in image {P.imgWidth = J.imageWidth pixels, P.imgHeight = J.imageHeight pixels, P.imgBits = 8, P.imgColor = color, P.imgIcc = Nothing, P.imgData = BSI.fromForeignPtr pointer offset size, P.imgDct = False, P.imgInvertedCmyk = False}

-- | Check every frame before the external decoder can allocate its coefficient arrays.
checkJpegFrames :: BS.ByteString -> Either Text ()
checkJpegFrames bytes = do
  unless (BS.take 2 bytes == BS.pack [255, 216]) (Left "JPEG の SOI がありません")
  go 2 0 Nothing False
  where
    size = BS.length bytes
    byte = BS.index bytes
    word i = fromIntegral (byte i) * 256 + fromIntegral (byte (i + 1)) :: Int
    failJpeg = Left "JPEG のマーカーが途中で終わっています"
    go i total frame scan
      | i >= size = failJpeg
      | byte i /= 255 = if scan then go (i + 1) total frame scan else Left "JPEG のマーカーが不正です"
      | otherwise = marker (i + 1) total frame scan
    marker i total frame scan
      | i >= size = failJpeg
      | byte i == 255 = marker (i + 1) total frame scan
      | byte i == 0 = if scan then go (i + 1) total frame scan else Left "JPEG のエスケープが不正です"
      | byte i == 217 = unless (maybe False (const scan) frame) (Left "JPEG にフレームか走査がありません")
      | byte i == 216 = Left "JPEG の SOI が重複しています"
      | byte i == 1 || (byte i >= 208 && byte i <= 215) = go (i + 1) total frame scan
      | i + 2 >= size = failJpeg
      | otherwise = do
          let length' = word (i + 1)
              end = i + 1 + length'
              sof = byte i >= 192 && byte i <= 207 && byte i `notElem` [196, 200, 204]
          unless (length' >= 2 && end <= size) failJpeg
          if sof
            then do
              unless (length' >= 8) failJpeg
              let precision = byte (i + 3)
                  height = word (i + 4)
                  width = word (i + 6)
                  components = fromIntegral (byte (i + 8)) :: Int
                  total' = total + toInteger width * toInteger height * 4
              unless (byte i `elem` [192, 193, 194] && precision == 8 && width > 0 && height > 0 && components >= 1 && components <= 4 && length' == 8 + 3 * components) (Left "JPEG のフレームの画素形式を扱えません")
              unless (total' <= maxColorBytes) (Left "JPEG の展開後サイズが 512 MiB を超えます")
              let selectors = [byte (i + 9 + 3 * component) | component <- [0 .. components - 1]]
                  sampling = [byte (i + 10 + 3 * component) | component <- [0 .. components - 1]]
                  tables = [byte (i + 11 + 3 * component) | component <- [0 .. components - 1]]
              unless (length (nub selectors) == components && all (\v -> v `shiftR` 4 >= 1 && v `shiftR` 4 <= 4 && v .&. 15 >= 1 && v .&. 15 <= 4) sampling && all (<= 3) tables) (Left "JPEG のフレームの成分が不正です")
              go end total' (Just (selectors, byte i == 194)) False
            else
              if byte i == 218
                then do
                  (frameIds, progressive) <- maybe (Left "JPEG の走査より前にフレームがありません") Right frame
                  unless (length' >= 6) failJpeg
                  let count = fromIntegral (byte (i + 3)) :: Int
                  unless (count >= 1 && count <= length frameIds && length' == 6 + 2 * count) (Left "JPEG の走査の成分数が不正です")
                  let selectors = [byte (i + 4 + 2 * component) | component <- [0 .. count - 1]]
                      tables = [byte (i + 5 + 2 * component) | component <- [0 .. count - 1]]
                      low = byte (i + 4 + 2 * count)
                      high = byte (i + 5 + 2 * count)
                      approximation = byte (i + 6 + 2 * count)
                      ah = approximation `shiftR` 4
                      al = approximation .&. 15
                  unless (length (nub selectors) == count && all (`elem` frameIds) selectors && all (\v -> v `shiftR` 4 <= 3 && v .&. 15 <= 3) tables) (Left "JPEG の走査がフレームにない成分を参照しています")
                  unless (if progressive then low <= high && high <= 63 && (if low == 0 then high == 0 else count == 1) && ah <= 13 && al <= 13 && (ah == 0 || ah == al + 1) else low == 0 && high == 63 && approximation == 0) (Left "JPEG の走査の範囲が不正です")
                  go end total frame True
                else go end total frame scan
