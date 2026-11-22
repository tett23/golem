module PdfDctSpec (pdfDctTests) where

import Codec.Picture.Jpg qualified as Jpeg
import Codec.Picture.Types qualified as J
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.Word (Word8)
import Golem.Pdf qualified as P
import Golem.Typeset.PdfDct
import Test.Tasty
import Test.Tasty.HUnit

pdfDctTests :: TestTree
pdfDctTests =
  testGroup
    "root ADR 0403 native PDF DCT samples"
    [ testCase "explicit zero preserves raw RGB samples" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec (Just 0)) jpeg)
        BS.take 3 (P.imgData (dctImage d)) @?= BS.pack [100, 128, 128],
      testCase "default three components applies YCbCr transform despite RGB component IDs" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec Nothing) jpeg)
        BS.take 3 (P.imgData (dctImage d)) @?= BS.pack [100, 100, 100],
      testCase "Adobe marker takes precedence over dictionary" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec (Just 1)) (BS.take 2 jpeg <> adobe <> BS.drop 2 jpeg))
        BS.take 3 (P.imgData (dctImage d)) @?= BS.pack [100, 128, 128],
      testCase "Gray ignores ColorTransform" $ do
        let gray = BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> 128 :: Word8) 8 8))
        d <- either (assertFailure . show) pure (decodePdfDct (PdfDctSpec 1 (Just 99) 8 8 (1024 * 1024)) gray)
        P.imgColor (dctImage d) @?= P.CsGray
        BS.head (P.imgData (dctImage d)) @?= 128,
      testCase "budget boundary includes coefficients and temporary sample arrays" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec (Just 0)) jpeg)
        let cost = dctDecodedBytes d
        decodePdfDct (spec (Just 0)) {dctBudget = cost} jpeg @?= Right d
        assertBool "one byte short" (isLeft (decodePdfDct (spec (Just 0)) {dctBudget = cost - 1} jpeg)),
      testCase "unimplemented CMYK is rejected rather than using standalone inversion" $ do
        let cmyk = BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> J.PixelCMYK8 255 255 255 0) 8 8))
        assertBool "CMYK pending" (isLeft (decodePdfDct (PdfDctSpec 4 Nothing 8 8 (1024 * 1024)) cmyk)),
      testCase "coefficient allocation is rejected before decoder" $ assertBool "budget" (isLeft (decodePdfDct (spec (Just 0)) {dctBudget = 100} jpeg)),
      testCase "declared dimensions must match before decoder" $ assertBool "dimensions" (isLeft (decodePdfDct (spec Nothing) {dctWidth = 65535} jpeg))
    ]
  where
    spec transform = PdfDctSpec 3 transform 8 8 (1024 * 1024)
    jpeg = withoutAdobe (BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> J.PixelRGB8 100 128 128) 8 8)))
    withoutAdobe bytes = case BS.breakSubstring (BS.pack [255, 238]) bytes of
      (before, rest) | not (BS.null rest) -> before <> BS.drop (2 + fromIntegral (BS.index rest 2) * 256 + fromIntegral (BS.index rest 3)) rest
      _ -> bytes
    adobe = BS.pack [255, 238, 0, 14, 65, 100, 111, 98, 101, 0, 100, 0, 0, 0, 0, 0]
