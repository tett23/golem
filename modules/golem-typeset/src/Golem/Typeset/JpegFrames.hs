-- | Bounded JPEG frame validation shared by standalone and PDF colour conversion.
module Golem.Typeset.JpegFrames (JpegFrameInfo (..), checkJpegFrames, inspectJpegFrames, maxColorBytes) where

import Control.Monad (unless)
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Text (Text)
import Data.Word (Word8)

-- | Shared conversion allocation limit, matching the existing PNG expansion limit.
maxColorBytes :: Integer
maxColorBytes = 512 * 1024 * 1024

-- | Validated marker hints, before any standalone or PDF-specific normalization.
data JpegFrameInfo = JpegFrameInfo
  { jpegAdobeTransform :: !(Maybe Int),
    jpegComponentIds :: ![Word8]
  }

checkJpegFrames :: BS.ByteString -> Either Text Bool
checkJpegFrames bytes = (== Just 0) . jpegAdobeTransform <$> inspectJpegFrames bytes

inspectJpegFrames :: BS.ByteString -> Either Text JpegFrameInfo
inspectJpegFrames bytes = do
  unless (BS.take 2 bytes == BS.pack [255, 216]) (Left "JPEG の SOI がありません")
  go 2 0 Nothing False Nothing
  where
    size = BS.length bytes
    byte = BS.index bytes
    word i = fromIntegral (byte i) * 256 + fromIntegral (byte (i + 1)) :: Int
    failJpeg = Left "JPEG のマーカーが途中で終わっています"
    go i total frame scan adobe
      | i >= size = failJpeg
      | byte i /= 255 = if scan then go (i + 1) total frame scan adobe else Left "JPEG のマーカーが不正です"
      | otherwise = marker (i + 1) total frame scan adobe
    marker i total frame scan adobe
      | i >= size = failJpeg
      | byte i == 255 = marker (i + 1) total frame scan adobe
      | byte i == 0 = if scan then go (i + 1) total frame scan adobe else Left "JPEG のエスケープが不正です"
      | byte i == 217 = case frame of
          Just (selectors, _) | scan -> Right (JpegFrameInfo adobe selectors)
          _ -> Left "JPEG にフレームか走査がありません"
      | byte i == 216 = Left "JPEG の SOI が重複しています"
      | byte i == 1 || (byte i >= 208 && byte i <= 215) = go (i + 1) total frame scan adobe
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
              go end total' (Just (selectors, byte i == 194)) False adobe
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
                  go end total frame True adobe
                else
                  let adobe' = if byte i == 238 && length' >= 14 && BS.take 5 (BS.drop (i + 3) bytes) == "Adobe" then Just (fromIntegral (byte (i + 14))) else adobe
                   in go end total frame scan adobe'
