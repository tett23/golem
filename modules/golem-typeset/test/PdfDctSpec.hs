module PdfDctSpec (pdfDctTests) where

import Codec.Picture.Jpg qualified as Jpeg
import Codec.Picture.Types qualified as J
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.List (elemIndex)
import Data.Maybe (fromMaybe)
import Data.Word (Word8)
import Golem.Pdf qualified as P
import Golem.Typeset.PdfDct
import Test.Tasty
import Test.Tasty.HUnit

pdfDctTests :: TestTree
pdfDctTests =
  testGroup
    "root ADR 0403 native PDF DCT samples"
    [ testCase "root ADR 0403 I1: explicit zero preserves raw RGB samples" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec (Just 0)) jpeg)
        BS.take 3 (P.imgData (dctImage d)) @?= BS.pack [100, 128, 128],
      testCase "root ADR 0403 I1: default three components applies YCbCr transform despite RGB component IDs" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec Nothing) jpeg)
        BS.take 3 (P.imgData (dctImage d)) @?= BS.pack [100, 100, 100],
      testCase "root ADR 0403 I1: Adobe marker takes precedence over dictionary" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec (Just 1)) (BS.take 2 jpeg <> adobe <> BS.drop 2 jpeg))
        BS.take 3 (P.imgData (dctImage d)) @?= BS.pack [100, 128, 128],
      testCase "root ADR 0403 I1: conflicting Adobe markers are rejected" $ do
        let different = BS.init adobe <> BS.singleton 1
        assertBool "conflict" (isLeft (decodePdfDct (spec Nothing) (BS.take 2 jpeg <> adobe <> different <> BS.drop 2 jpeg))),
      testCase "root ADR 0403 I1: equal Adobe hints are harmless duplicates" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec Nothing) (BS.take 2 jpeg <> adobe <> adobe <> BS.drop 2 jpeg))
        BS.take 3 (P.imgData (dctImage d)) @?= BS.pack [100, 128, 128],
      testCase "root ADR 0403 I1: Gray ignores ColorTransform" $ do
        let gray = BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> 128 :: Word8) 8 8))
        d <- either (assertFailure . show) pure (decodePdfDct (PdfDctSpec 1 (Just 99) 8 8 (1024 * 1024)) gray)
        P.imgColor (dctImage d) @?= P.CsGray
        BS.head (P.imgData (dctImage d)) @?= 128,
      testCase "root ADR 0403 I2: budget boundary includes coefficients and temporary sample arrays" $ do
        d <- either (assertFailure . show) pure (decodePdfDct (spec (Just 0)) jpeg)
        let cost = dctDecodedBytes d
        decodePdfDct (spec (Just 0)) {dctBudget = cost} jpeg @?= Right d
        assertBool "one byte short" (isLeft (decodePdfDct (spec (Just 0)) {dctBudget = cost - 1} jpeg)),
      testCase "root ADR 0403 I1: Adobe zero CMYK returns native samples before PDF Decode" $ do
        bytes <- BS.readFile "test/fixtures/pdf-adobe-cmyk.jpg"
        d <- either (assertFailure . show) pure (decodePdfDct (PdfDctSpec 4 (Just 1) 24 8 (1024 * 1024)) bytes)
        [BS.take 4 (BS.drop (x * 4) (P.imgData (dctImage d))) | x <- [0, 8, 16]] @?= map BS.pack [[255, 255, 255, 0], [255, 255, 255, 127], [255, 255, 255, 255]],
      testCase "root ADR 0403 I1: Adobe two YCCK retains PDF sample polarity and neutral channels" $ do
        bytes <- BS.readFile "test/fixtures/pdf-adobe-ycck.jpg"
        d <- either (assertFailure . show) pure (decodePdfDct (PdfDctSpec 4 (Just 0) 24 8 (1024 * 1024)) bytes)
        [BS.take 4 (BS.drop (x * 4) (P.imgData (dctImage d))) | x <- [0, 8, 16]] @?= map BS.pack [[255, 255, 255, 0], [255, 255, 255, 127], [255, 255, 255, 255]],
      testCase "root ADR 0403 I1: dictionary transform one decodes unmarked YCCK" $ do
        bytes <- withoutAdobe <$> BS.readFile "test/fixtures/pdf-adobe-ycck.jpg"
        d <- either (assertFailure . show) pure (decodePdfDct (PdfDctSpec 4 (Just 1) 24 8 (1024 * 1024)) bytes)
        BS.take 4 (P.imgData (dctImage d)) @?= BS.pack [255, 255, 255, 0],
      testCase "root ADR 0403 I1: dictionary ColorTransform two is not an Adobe marker" $ do
        bytes <- withoutAdobe <$> BS.readFile "test/fixtures/pdf-adobe-ycck.jpg"
        assertBool "invalid dictionary value" (isLeft (decodePdfDct (PdfDctSpec 4 (Just 2) 24 8 (1024 * 1024)) bytes)),
      testCase "root ADR 0403 I1: arbitrary four-component identifiers do not imply RGBA" $ do
        bytes <- BS.readFile "test/fixtures/pdf-adobe-cmyk.jpg"
        let pos tag = BS.length (fst (BS.breakSubstring (BS.pack [255, tag]) bytes))
            f = pos 192
            scan = pos 218
            old = [BS.index bytes (f + 10 + n * 3) | n <- [0 .. 3]]
            changes = zip ([f + 10 + n * 3 | n <- [0 .. 3]] <> [scan + 5 + n * 2 | n <- [0 .. 3]]) (map (fromIntegral . fromEnum) "RGBA" <> [fromIntegral (fromEnum ("RGBA" !! k)) | n <- [0 .. 3], Just k <- [elemIndex (BS.index bytes (scan + 5 + n * 2)) old]])
            renamed = BS.pack [fromMaybe v (lookup n changes) | (n, v) <- zip [0 ..] (BS.unpack bytes)]
        d <- either (assertFailure . show) pure (decodePdfDct (PdfDctSpec 4 Nothing 24 8 (1024 * 1024)) renamed)
        BS.take 4 (P.imgData (dctImage d)) @?= BS.pack [255, 255, 255, 0],
      testCase "root ADR 0403 I2: coefficient allocation is rejected before decoder" $ assertBool "budget" (isLeft (decodePdfDct (spec (Just 0)) {dctBudget = 100} jpeg)),
      testCase "root ADR 0403 I2: declared dimensions must match before decoder" $ assertBool "dimensions" (isLeft (decodePdfDct (spec Nothing) {dctWidth = 65535} jpeg))
    ]
  where
    spec transform = PdfDctSpec 3 transform 8 8 (1024 * 1024)
    jpeg = withoutAdobe (BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> J.PixelRGB8 100 128 128) 8 8)))
    withoutAdobe bytes = case BS.breakSubstring (BS.pack [255, 238]) bytes of
      (before, rest) | not (BS.null rest) -> before <> BS.drop (2 + fromIntegral (BS.index rest 2) * 256 + fromIntegral (BS.index rest 3)) rest
      _ -> bytes
    adobe = BS.pack [255, 238, 0, 14, 65, 100, 111, 98, 101, 0, 100, 0, 0, 0, 0, 0]
