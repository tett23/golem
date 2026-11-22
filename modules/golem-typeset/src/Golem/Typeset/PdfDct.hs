{-# LANGUAGE TypeFamilies #-}

-- | PDF DCT samples before the image dictionary's Decode array (root ADR 0403).
module Golem.Typeset.PdfDct
  ( PdfDctSpec (..),
    DctSamples (..),
    decodePdfDct,
  )
where

import Codec.Picture.Jpg qualified as Jpeg
import Codec.Picture.Types qualified as J
import Control.Monad (unless)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.ByteString.Internal qualified as BSI
import Data.List (nub, sortOn)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Vector.Storable qualified as V
import Data.Word (Word8)
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (checkJpegFrames)

data PdfDctSpec = PdfDctSpec
  { dctComponents :: !Int,
    dctColorTransform :: !(Maybe Int),
    dctWidth :: !Int,
    dctHeight :: !Int,
    dctBudget :: !Int
  }
  deriving stock (Eq, Show)

data DctSamples = DctSamples
  { dctImage :: !P.ImageData,
    -- | Conservative total allocation charge, including coefficients and temporary sample arrays.
    dctDecodedBytes :: !Int
  }
  deriving stock (Eq, Show)

{- | APP14 overrides ColorTransform; neither applies the PDF Decode array.
The caller must evaluate this pure codec result inside its synchronous-exception boundary.
-}
decodePdfDct :: PdfDctSpec -> BS.ByteString -> Either Text DctSamples
decodePdfDct spec bytes = do
  unless (toInteger (BS.length bytes) * 32 + 65536 <= toInteger (dctBudget spec)) (Left "PDF の JPEG 復号予算を超えます")
  _ <- checkJpegFrames bytes
  markers <- scan 2 False []
  frame <- case [(a, b) | (kind, a, b) <- markers, kind `elem` [192, 193, 194]] of
    [value] -> pure value
    _ -> Left "PDF の複数フレーム JPEG を扱えません"
  let (start, _) = frame
      width = word (start + 7)
      height = word (start + 5)
      components = fromIntegral (BS.index bytes (start + 9))
      sampling = [(toInteger (x `shiftR` 4), toInteger (x .&. 15)) | n <- [0 .. components - 1], let x = BS.index bytes (start + 11 + 3 * n)]
      adobeMarkers = [(a, b) | (kind, a, b) <- markers, kind == 238, b - a >= 16, BS.take 5 (BS.drop (a + 4) bytes) == "Adobe"]
      adobe = case reverse adobeMarkers of
        (a, _) : _ -> Just (fromIntegral (BS.index bytes (a + 15)))
        [] -> Nothing
      frameIds = [(BS.index bytes (start + 10 + n * 3), fromIntegral (n + 1)) | n <- [0 .. components - 1]]
      canonicalEdits =
        if components /= 4
          then []
          else
            [(start + 10 + n * 3, start + 11 + n * 3, BS.singleton (fromIntegral (n + 1))) | n <- [0 .. 3]]
              <> [(a + 5 + n * 2, a + 6 + n * 2, BS.singleton (fromMaybe old (lookup old frameIds))) | (kind, a, _) <- markers, kind == 218, n <- [0 .. fromIntegral (BS.index bytes (a + 4)) - 1], let old = BS.index bytes (a + 5 + n * 2)]
      clean = BS.concat (strip 2 (sortOn (\(a, _, _) -> a) ([(a, b, BS.empty) | (a, b) <- adobeMarkers] <> canonicalEdits)))
  unless (length (nub [BS.index bytes (a + 15) | (a, _) <- adobeMarkers]) <= 1) (Left "PDF の JPEG に矛盾する Adobe ColorTransform があります")
  unless (width == dctWidth spec && height == dctHeight spec && components == dctComponents spec) (Left "PDF と JPEG の寸法または成分数が一致しません")
  unless (components == 1 || maybe True (\a -> a `elem` (if components == 3 then [0, 1] else [0, 2])) adobe) (Left "PDF の Adobe JPEG ColorTransform と成分数が一致しません")
  unless (components == 1 || isJust adobe || maybe True (`elem` [0, 1]) (dctColorTransform spec)) (Left "PDF の JPEG ColorTransform は 0 か 1 でなければなりません")
  let transform = fromMaybe (fromMaybe (if components == 3 then 1 else 0) (dctColorTransform spec)) adobe
      pixels = toInteger width * toInteger height
      maxH = maximum (map fst sampling)
      maxV = maximum (map snd sampling)
      mcus = ceilingDiv (toInteger width) (8 * maxH) * ceilingDiv (toInteger height) (8 * maxV)
      coefficients = mcus * sum [h * v | (h, v) <- sampling] * 64 * 2
      cost = coefficients + pixels * toInteger components * 3 + toInteger (BS.length bytes) * 32 + 65536
  unless (cost <= toInteger (dctBudget spec)) (Left "PDF の JPEG 復号予算を超えます")
  unless (components `elem` [1, 3, 4]) (Left "PDF の JPEG の成分数を扱えません")
  unless (components == 1 || (components == 3 && transform `elem` [0, 1]) || (components == 4 && transform `elem` [0, 1, 2])) (Left "PDF の JPEG ColorTransform を扱えません")
  let marker = BS.pack [255, 238, 0, 14, 65, 100, 111, 98, 101, 0, 100, 0, 0, 0, 0, if components == 3 then fromIntegral transform else 0]
      controlled = BS.take 2 bytes <> marker <> clean
  decoded <- either (Left . T.pack) Right (Jpeg.decodeJpeg controlled)
  image <- case decoded of
    J.ImageY8 p | components == 1 -> pure (unpack P.CsGray p)
    J.ImageRGB8 p | components == 3 && transform == 0 -> pure (unpack P.CsRgb p)
    J.ImageYCbCr8 p | components == 3 && transform == 1 -> pure (unpack P.CsRgb (J.convertImage p :: J.Image J.PixelRGB8))
    J.ImageCMYK8 p | components == 4 -> pure (unpack P.CsCmyk (if transform == 0 then p else J.pixelMap ycck p))
    _ -> Left "PDF の JPEG 復号結果の画素形式が一致しません"
  unless (P.imgWidth image == width && P.imgHeight image == height) (Left "PDF の JPEG 復号結果の寸法が一致しません")
  pure (DctSamples image (fromInteger cost))
  where
    ceilingDiv a b = (a + b - 1) `div` b
    word i = fromIntegral (BS.index bytes i) * 256 + fromIntegral (BS.index bytes (i + 1)) :: Int
    -- Validate offsets independently; standalone marker and entropy escapes have no length field.
    scan i entropy acc
      | i >= BS.length bytes = Left "PDF の JPEG マーカーが途中で終わっています"
      | BS.index bytes i /= 255 =
          if entropy
            then case BS.elemIndex 255 (BS.drop i bytes) of
              Just offset -> scan (i + offset) entropy acc
              Nothing -> Left "PDF の JPEG 終端がありません"
            else Left "PDF の JPEG マーカーが不正です"
      | i + 1 >= BS.length bytes = Left "PDF の JPEG マーカーが途中で終わっています"
      | kind == 255 = scan (i + 1) entropy acc
      | kind == 0 && entropy = scan (i + 2) entropy acc
      | kind == 217 = pure (reverse acc)
      | kind == 1 || (kind >= 208 && kind <= 215) = scan (i + 2) entropy acc
      | i + 3 >= BS.length bytes = Left "PDF の JPEG マーカーが途中で終わっています"
      | otherwise = do
          let len = word (i + 2)
              end = i + 2 + len
          unless (len >= 2 && end <= BS.length bytes) (Left "PDF の JPEG マーカー長が不正です")
          scan end (entropy || kind == 218) ((kind, i, end) : acc)
      where
        kind = BS.index bytes (i + 1)
    strip start [] = [BS.drop start bytes]
    strip start ((a, b, replacement) : rest) = BS.take (a - start) (BS.drop start bytes) : replacement : strip b rest
    -- Unlike standalone Adobe normalization, PDF DCT preserves K and returns
    -- complemented YCbCr-to-RGB channels before the separate Decode array.
    ycck (J.PixelCMYK8 y cb cr k) = case J.convertPixel (J.PixelYCbCr8 y cb cr) of
      J.PixelRGB8 r g b -> J.PixelCMYK8 (255 - r) (255 - g) (255 - b) k

unpack :: (J.PixelBaseComponent pixel ~ Word8) => P.ColorSpace -> J.Image pixel -> P.ImageData
unpack color pixels =
  let (pointer, offset, size) = V.unsafeToForeignPtr (J.imageData pixels)
   in P.ImageData (J.imageWidth pixels) (J.imageHeight pixels) 8 color Nothing (BSI.fromForeignPtr pointer offset size) False False Nothing
