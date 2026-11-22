module FigureColorSpec (figureColorTests) where

import Codec.Picture.Jpg qualified as Jpeg
import Codec.Picture.Png qualified as Png
import Codec.Picture.Types qualified as J
import Control.Exception (AsyncException (ThreadKilled), ErrorCall (ErrorCallWithLocation), SomeException, evaluate, throw, try)
import Control.Monad (forM_)
import Data.Bits (xor)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (fromLeft, isLeft)
import Data.Text qualified as T
import Data.Word (Word16, Word8)
import Golem.Pdf qualified as P
import Golem.Pdf.Object (ObjOf (..))
import Golem.Typeset.FigureColor
import Test.Tasty
import Test.Tasty.HUnit

figureColorTests :: TestTree
figureColorTests =
  testGroup
    "root ADR 0403 raster tones"
    [ testCase "root ADR 0403: codec exceptions do not expose machine-specific call stacks" $ do
        let conversion location = guardColorConversion (\() -> throw (ErrorCallWithLocation "codec failed" location)) (Right ())
        first <- conversion "/tmp/build-a/Image.hs:13"
        second <- conversion "/home/build-b/Image.hs:42"
        first @?= Left "図版の色変換中に復号処理が失敗しました"
        second @?= first,
      testCase "root ADR 0403 I1: gray black and white map to swatch and paper" $ do
        result <- either (assertFailure . show) pure (analyzeRaster red (image P.CsGray [0, 255]))
        raKind result @?= Grayscale
        fmap P.imgColor (raImage result) @?= Just P.CsCmyk
        fmap P.imgData (raImage result) @?= Just (BS.pack [0, 255, 255, 0, 0, 0, 0, 0]),
      testCase "root ADR 0403 I1: intermediate gray scales the CMYK components" $ do
        result <- either (assertFailure . show) pure (analyzeRaster red (image P.CsGray [128, 128]))
        fmap P.imgData (raImage result) @?= Just (BS.pack [0, 127, 127, 0, 0, 127, 127, 0]),
      testCase "root ADR 0403 I2: dimensions and per-pixel alpha remain unchanged" $ do
        let alpha = Just (P.Alpha 8 (BS.pack [0, 128]))
            original = (image P.CsGray [0, 128]) {P.imgAlpha = alpha}
        result <- either (assertFailure . show) pure (analyzeRaster red original)
        fmap (\i -> (P.imgWidth i, P.imgHeight i, P.imgAlpha i)) (raImage result) @?= Just (2, 1, alpha),
      testCase "root ADR 0403 I1: equal RGB channels use the grayscale rule" $ do
        result <- either (assertFailure . show) pure (analyzeRaster red (image P.CsRgb [0, 0, 0, 255, 255, 255]))
        raKind result @?= Grayscale
        fmap P.imgData (raImage result) @?= Just (BS.pack [0, 255, 255, 0, 0, 0, 0, 0]),
      testCase "root ADR 0403 I3: a coloured photograph is retained" $
        analyzeRaster red (image P.CsRgb [255, 0, 0, 0, 0, 255]) @?= Right (RasterAnalysis Multicolor Nothing),
      testCase "root ADR 0403 I1: one chromatic colour uses the selected swatch" $ do
        result <- either (assertFailure . show) pure (analyzeRaster red (image P.CsRgb [0, 255, 0, 0, 255, 0]))
        raKind result @?= SolidRgb (0, 1, 0)
        fmap P.imgData (raImage result) @?= Just (BS.pack [0, 255, 255, 0, 0, 255, 255, 0]),
      testCase "root ADR 0403 I1: white alone stays white" $ do
        result <- either (assertFailure . show) pure (analyzeRaster red (image P.CsRgb [255, 255, 255, 255, 255, 255]))
        raKind result @?= Grayscale
        fmap P.imgData (raImage result) @?= Just (BS.replicate 8 0),
      testCase "root ADR 0403 I1: an RGB JPEG with equal channels is grayscale" $ do
        let bytes = rgbJpeg (\x _ -> if x < 8 then J.PixelRGB8 0 0 0 else J.PixelRGB8 255 255 255)
        original <- either assertFailure pure (P.readImage bytes)
        P.imgColor original @?= P.CsRgb
        result <- either (assertFailure . show) pure (analyzeRaster red original)
        raKind result @?= Grayscale
        fmap (\i -> (P.imgWidth i, P.imgHeight i, P.imgDct i)) (raImage result) @?= Just (16, 8, False),
      testCase "root ADR 0403 I1: one-component JPEG is decoded and written as PNG for the web" $ do
        let bytes = BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> 0 :: Word8) 2 1))
        changed <- either (assertFailure . show) pure (recolorRasterBytes red bytes)
        case changed of
          Nothing -> assertFailure "no recolouring"
          Just (_, png) -> do
            assertBool "PNG signature" (BS.take 8 png == BS.pack [137, 80, 78, 71, 13, 10, 26, 10])
            case Png.decodePng png of
              Right (J.ImageRGBA8 pixels) -> J.pixelAt pixels 0 0 @?= J.PixelRGBA8 255 0 0 255
              other -> assertFailure (fromLeft "unexpected PNG pixel type" other),
      testCase "root ADR 0403 I3: coloured JPEG bytes require no rewriting" $
        recolorRasterBytes red (rgbJpeg (\x _ -> if x < 8 then J.PixelRGB8 255 0 0 else J.PixelRGB8 0 0 255)) @?= Right Nothing,
      testCase "root ADR 0406 I3: baseline and extended sequential JPEG are decoded" $ do
        let baseline = rgbJpeg (\_ _ -> J.PixelRGB8 0 0 0)
            extended = marker 0xc1 baseline
        forM_ [baseline, extended] $ \bytes -> do
          result <- safeRecolorRasterBytes red bytes
          case result of
            Right (Just _) -> pure ()
            other -> assertFailure (show other),
      testCase "root ADR 0406 I3: progressive JPEG is decoded" $ do
        bytes <- BS.readFile "test/fixtures/gray-progressive.jpg"
        assertBool "genuine progressive frame" (BS.pack [0xff, 0xc2] `BS.isInfixOf` bytes)
        result <- safeRecolorRasterBytes red bytes
        case result of
          Right (Just _) -> pure ()
          other -> assertFailure (show other),
      testCase "root ADR 0406 I1: non-eight-bit lossless and arithmetic JPEG are rejected" $ do
        let baseline = rgbJpeg (\_ _ -> J.PixelRGB8 0 0 0)
            (before, frame) = BS.breakSubstring (BS.pack [0xff, 0xc0]) baseline
            twelve = before <> BS.take 4 frame <> BS.singleton 12 <> BS.drop 5 frame
        forM_ [twelve, marker 0xc3 baseline, marker 0xc9 baseline] $ \bytes -> do
          result <- safeRecolorRasterBytes red bytes
          assertBool "unsupported coding returns a cause" (isLeft result),
      testCase "root ADR 0403 I2: JPEG declared dimensions must match the codestream" $ do
        let bytes = rgbJpeg (\_ _ -> J.PixelRGB8 0 0 0)
        original <- either assertFailure pure (P.readImage bytes)
        assertBool "dimension mismatch" (isLeft (analyzeRaster red original {P.imgWidth = 1})),
      testCase "root ADR 0403 I2: 16-bit PNG alpha and tones stay 16-bit" $ do
        let source = BL.toStrict (Png.encodePng (J.generateImage (\_ _ -> J.PixelRGBA16 32768 32768 32768 (0x1234 :: Word16)) 1 1))
        changed <- either (assertFailure . show) pure (recolorRasterBytes red source)
        case changed of
          Nothing -> assertFailure "no recolouring"
          Just (image', png) -> do
            P.imgBits image' @?= 16
            P.imgAlpha image' @?= Just (P.Alpha 16 (BS.pack [0x12, 0x34]))
            case Png.decodePng png of
              Right (J.ImageRGBA16 pixels) -> J.pixelAt pixels 0 0 @?= J.PixelRGBA16 65535 32768 32768 0x1234
              other -> assertFailure (fromLeft "unexpected PNG pixel type" other),
      testCase "root ADR 0403 I2: transparent chromatic pixels do not make a gray PNG multi-colour" $ do
        let source = BL.toStrict (Png.encodePng (J.generateImage (\x _ -> case x of 0 -> J.PixelRGBA8 255 0 0 0; 1 -> J.PixelRGBA8 128 128 128 128; _ -> J.PixelRGBA8 255 255 255 255) 3 1))
        changed <- either (assertFailure . show) pure (recolorRasterBytes red source)
        case changed of
          Nothing -> assertFailure "no recolouring"
          Just (_, png) -> case Png.decodePng png of
            Right (J.ImageRGBA8 pixels) -> do
              J.pixelAt pixels 1 0 @?= J.PixelRGBA8 255 128 128 128
              J.pixelAt pixels 2 0 @?= J.PixelRGBA8 255 255 255 255
              let J.PixelRGBA8 _ _ _ alpha = J.pixelAt pixels 0 0
              alpha @?= 0
            other -> assertFailure (fromLeft "unexpected PNG pixel type" other),
      testCase "root ADR 0403 I2: truncated and mutated JPEG inputs return without exceptions" $ do
        let bytes = rgbJpeg (\_ _ -> J.PixelRGB8 0 0 0)
            indices = [i * (BS.length bytes - 1) `div` 40 | i <- [0 .. 40]]
            broken = [BS.take i bytes <> BS.singleton (BS.index bytes i `xor` 1) <> BS.drop (i + 1) bytes | i <- indices] <> [BS.take i bytes | i <- [0 .. 32]]
        forM_ broken $ \input -> do
          result <- try (safeRecolorRasterBytes red input >>= evaluate . length . show) :: IO (Either SomeException Int)
          case result of { Left problem -> assertFailure (show problem); Right _ -> pure () },
      testCase "root ADR 0403 I2: codec boundary forces deferred pixel and alpha failures" $ do
        let delayedPixels = (image P.CsGray [0, 255]) {P.imgData = error "deferred pixels"}
            delayedAlpha = (image P.CsGray [0, 255]) {P.imgAlpha = Just (P.Alpha 8 (error "deferred alpha"))}
        forM_ [delayedPixels, delayedAlpha] $ \value -> do
          result <- guardColorConversion forceRasterAnalysis (Right (RasterAnalysis Grayscale (Just value)))
          assertBool "synchronous failure returned" (isLeft result),
      testCase "root ADR 0403 I2: codec boundary forces deferred colour classification" $ do
        result <- guardColorConversion forceRasterAnalysis (Right (RasterAnalysis (SolidRgb (error "deferred tone", 0, 0)) Nothing))
        assertBool "synchronous classification failure returned" (isLeft result),
      testCase "root ADR 0403 I2: PDF conversion boundary forces deferred resource streams" $ do
        let page = P.ImportedPage "hash" 1 (0, 0, 1, 1) 0 (1, 1) (ODict []) Nothing "content" [(1, ODict [("nested", OArr [OStream [] (error "deferred stream")])])] [] 0
        result <- guardColorConversion (maybe () forceImportedPage) (Right (Just page))
        assertBool "synchronous PDF stream failure returned" (isLeft result),
      testCase "root ADR 0403 I2: cancellation is rethrown by the codec boundary" $ do
        result <- try (guardColorConversion (\() -> throw ThreadKilled) (Right ())) :: IO (Either AsyncException (Either T.Text ()))
        result @?= Left ThreadKilled,
      testCase "root ADR 0403 I2: oversized JPEG is rejected before decoding" $
        assertBool "bounded output" (isLeft (analyzeRaster red (P.ImageData 65535 65535 8 P.CsRgb Nothing "jpeg" True False Nothing))),
      testCase "root ADR 0403 I2: broken JPEG returns a diagnostic cause" $
        assertBool "broken input" (isLeft (analyzeRaster red ((image P.CsRgb []) {P.imgDct = True, P.imgData = "not a jpeg"})))
    ]
  where
    marker code bytes = let (before, frame) = BS.breakSubstring (BS.pack [0xff, 0xc0]) bytes in before <> BS.pack [0xff, code] <> BS.drop 2 frame
    rgbJpeg pixels = BL.toStrict (Jpeg.encodeJpegAtQuality 100 (J.convertImage (J.generateImage pixels 16 8) :: J.Image J.PixelYCbCr8))
    red = (0, 100, 100, 0)
    image color samples = P.ImageData 2 1 8 color Nothing (BS.pack samples) False False Nothing
