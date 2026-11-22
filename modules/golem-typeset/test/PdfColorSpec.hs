module PdfColorSpec (pdfColorTests) where

import Codec.Picture.Jpg qualified as Jpeg
import Codec.Picture.Types qualified as J
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Golem.Pdf qualified as P
import Golem.Pdf.Image (flate)
import Golem.Typeset.FigureColor (RasterAnalysis (..), RasterKind (..), analyzeRaster)
import Golem.Typeset.PdfColor (recolorImportedPage)
import Test.Tasty
import Test.Tasty.HUnit

pdfColorTests :: [TestTree]
pdfColorTests =
  [ testCase "root ADR 0403 I1: PDF DCT gray samples are decoded before recoloring" $ do
      let jpeg = BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> 128 :: Word8) 8 8))
          fields = [("Filter", P.OName "DCTDecode"), ("ColorSpace", P.OName "DeviceGray"), ("Height", P.OInt 8)] <> filter (\(name, _) -> name `notElem` ["ColorSpace", "Height"]) (imageFields 8)
          original = imagePage {P.ipObjects = [(1, P.OStream fields jpeg)]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> do
          convertedImagePixels result @?= [BS.concat (replicate 64 (BS.pack [0, 127, 127, 0]))]
          lookup 1 (P.ipObjects result) @?= lookup 1 (P.ipObjects original)
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: PDF DCT Decode inversion is applied exactly once" $ do
      let jpeg = BL.toStrict (Jpeg.encodeDirectJpegAtQualityWithMetadata 100 mempty (J.generateImage (\_ _ -> 128 :: Word8) 8 8))
          fields = [("Filter", P.OName "DCTDecode"), ("ColorSpace", P.OName "DeviceGray"), ("Height", P.OInt 8), ("Decode", P.OArr [P.OInt 1, P.OInt 0])] <> filter (\(name, _) -> name `notElem` ["ColorSpace", "Height"]) (imageFields 8)
          original = imagePage {P.ipObjects = [(1, P.OStream fields jpeg)]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> convertedImagePixels result @?= [BS.concat (replicate 64 (BS.pack [0, 128, 128, 0]))]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: image DeviceRGB honours a resource DefaultRGB profile" $ do
      let original = imagePage {P.ipResources = P.ODict [("ColorSpace", P.ORef 4), ("XObject", P.ODict [("Im", P.ORef 1)])], P.ipObjects = P.ipObjects imagePage <> [(3, P.OStream [("N", P.OInt 3)] P.srgbProfile), (4, P.ODict [("DefaultRGB", P.OArr [P.OName "ICCBased", P.ORef 3])])]}
          analyze input
            | P.imgIcc input == Just P.srgbProfile = analyzeRaster (0, 100, 100, 0) input
            | otherwise = Left "default profile was lost"
      case recolorImportedPage (0, 100, 100, 0) analyze original of
        Right (Just result) -> convertedImagePixels result @?= [cmykPixels]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: cycles in named image colour spaces terminate with an error" $ do
      let fields = ("ColorSpace", P.OName "First") : filter ((/= "ColorSpace") . fst) (imageFields 3)
          original = imagePage {P.ipResources = P.ODict [("ColorSpace", P.ODict [("First", P.OName "Second"), ("Second", P.OName "First")]), ("XObject", P.ODict [("Im", P.ORef 1)])], P.ipObjects = [(1, P.OStream fields rgbPixels)]}
      case recolorImportedPage (0, 100, 100, 0) rgbAnalyzer original of
        Left _ -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: an image resolves its named colour space in each Form scope" $ do
      let own space = P.ODict [("ColorSpace", P.ODict [("Neutral", P.OName space)]), ("XObject", P.ODict [("Im", P.ORef 3)])]
          form space = P.OStream [("Subtype", P.OName "Form"), ("Resources", own space)] "/Im Do"
          fields = [("ColorSpace", P.OName "Neutral"), ("BitsPerComponent", P.OInt 1)] <> filter (\(name, _) -> name `notElem` ["ColorSpace", "BitsPerComponent"]) (imageFields 1)
          original = (page "/A Do /B Do") {P.ipResources = P.ODict [("XObject", P.ODict [("A", P.ORef 1), ("B", P.ORef 2)])], P.ipObjects = [(1, form "DeviceGray"), (2, form "DeviceCMYK"), (3, P.OStream fields (BS.pack [0xe0]))]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> do
          let outputs = convertedImagePixels result
          length outputs @?= 2
          assertBool "gray white" (BS.pack [0, 0, 0, 0] `elem` outputs)
          assertBool "CMYK neutral black" (BS.pack [0, 255, 255, 0] `elem` outputs)
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a colour-key mask compares samples before inverse Decode" $ do
      let fields = [("Mask", P.OArr (map P.OInt [255, 255, 0, 0, 0, 0])), ("Decode", P.OArr (map P.OInt [1, 0, 1, 0, 1, 0]))] <> imageFields 2
          original = imagePage {P.ipObjects = [(1, P.OStream fields (BS.pack [255, 0, 0, 127, 127, 127]))]}
          analyze input
            | P.imgAlpha input == Just (P.Alpha 8 (BS.pack [0, 255])), P.imgData input == BS.pack [0, 255, 255, 128, 128, 128] = analyzeRaster (0, 100, 100, 0) input
            | otherwise = Left "unexpected mask or sample order"
      case recolorImportedPage (0, 100, 100, 0) analyze original of
        Right (Just _) -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: invalid colour-key ranges are rejected" $ do
      let original = imagePage {P.ipObjects = [(1, P.OStream (("Mask", P.OArr (map P.OInt [0, 256, 0, 0, 0, 0])) : imageFields 3) rgbPixels)]}
      case recolorImportedPage (0, 100, 100, 0) rgbAnalyzer original of
        Left _ -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a colour-key PDF mask becomes an equivalent gray soft mask" $ do
      let mask = P.OArr (map P.OInt [255, 255, 0, 0, 0, 0])
          original = imagePage {P.ipObjects = [(1, P.OStream (("Mask", mask) : ("Interpolate", P.OBool True) : imageFields 2) (BS.pack [255, 0, 0, 128, 128, 128]))]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> do
          lookup 1 (P.ipObjects result) @?= lookup 1 (P.ipObjects original)
          let outputs = [(entries, bytes) | (key, P.OStream entries bytes) <- P.ipObjects result, key < 0, lookup "ColorSpace" entries == Just (P.OName "DeviceCMYK")]
          case outputs of
            [(entries, bytes)] -> do
              lookup "Mask" entries @?= Nothing
              BS.drop 4 bytes @?= BS.pack [0, 127, 127, 0]
              case lookup "SMask" entries of
                Just (P.ORef reference) -> case lookup reference (P.ipObjects result) of
                  Just (P.OStream maskFields alpha) -> do
                    lookup "ColorSpace" maskFields @?= Just (P.OName "DeviceGray")
                    lookup "Interpolate" maskFields @?= Just (P.OBool True)
                    alpha @?= BS.pack [0, 255]
                  other -> assertFailure (show other)
                other -> assertFailure (show other)
            other -> assertFailure (show other)
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: reversed PDF image Decode is applied before recoloring" $ do
      let fields = ("Decode", P.OArr (map P.OInt [1, 0, 1, 0, 1, 0])) : imageFields 3
          original = imagePage {P.ipObjects = [(1, P.OStream fields (BS.map (255 -) rgbPixels))]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> convertedImagePixels result @?= [cmykPixels]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a 16-bit PDF soft mask retains its original precision and object" $ do
      let alpha = BS.pack [255, 255, 128, 0, 255, 255]
          originalMask = P.OStream [("Subtype", P.OName "Image"), ("Width", P.OInt 3), ("Height", P.OInt 1), ("BitsPerComponent", P.OInt 16), ("ColorSpace", P.OName "DeviceGray")] alpha
          original = imagePage {P.ipObjects = [(1, P.OStream (("SMask", P.ORef 2) : imageFields 3) rgbPixels), (2, originalMask)]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> do
          lookup 2 (P.ipObjects result) @?= Just originalMask
          convertedImagePixels result @?= [BS.pack [0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 127, 127, 127, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]
          [lookup "SMask" entries | (key, P.OStream entries _) <- P.ipObjects result, key < 0, lookup "Subtype" entries == Just (P.OName "Image")] @?= [Just (P.ORef 2)]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a packed reversed PDF soft mask is used only for visibility" $ do
      let samples = BS.pack [255, 0, 0, 128, 128, 128, 0, 0, 255]
          originalMask = P.OStream [("Subtype", P.OName "Image"), ("Width", P.OInt 3), ("Height", P.OInt 1), ("BitsPerComponent", P.OInt 1), ("ColorSpace", P.OName "DeviceGray"), ("Decode", P.OArr [P.OInt 1, P.OInt 0])] (BS.pack [0xa0])
          original = imagePage {P.ipObjects = [(1, P.OStream (("SMask", P.ORef 2) : imageFields 3) samples), (2, originalMask)]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> lookup 2 (P.ipObjects result) @?= Just originalMask
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: packed PDF gray samples preserve padding at each row" $ do
      let fields = [("ColorSpace", P.OName "DeviceGray"), ("BitsPerComponent", P.OInt 1), ("Height", P.OInt 2)] <> filter (\(name, _) -> name `notElem` ["ColorSpace", "BitsPerComponent", "Height"]) (imageFields 3)
          original = imagePage {P.ipObjects = [(1, P.OStream fields (BS.pack [0x40, 0xa0]))]}
          ink = [0, 255, 255, 0]
          white = [0, 0, 0, 0]
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> convertedImagePixels result @?= [BS.pack (ink <> white <> ink <> white <> ink <> white)]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: two- and four-bit PDF gray samples preserve row padding" $ do
      let cases = [(2, BS.pack [0x1c, 0xe0], [255, 170, 0, 0, 85, 255]), (4, BS.pack [0x08, 0xf0, 0xf7, 0x00], [255, 119, 0, 0, 136, 255])]
      mapM_
        ( \(bits, samples, tones) -> do
            let fields = [("ColorSpace", P.OName "DeviceGray"), ("BitsPerComponent", P.OInt bits), ("Height", P.OInt 2)] <> filter (\(name, _) -> name `notElem` ["ColorSpace", "BitsPerComponent", "Height"]) (imageFields 3)
                original = imagePage {P.ipObjects = [(1, P.OStream fields samples)]}
            case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
              Right (Just result) -> convertedImagePixels result @?= [BS.pack (concatMap (\tone -> [0, tone, tone, 0]) tones)]
              other -> assertFailure (show (bits, other))
        )
        cases,
    testCase "root ADR 0403 I1: 16-bit PDF gray retains precision when recolored" $ do
      let fields = [("ColorSpace", P.OName "DeviceGray"), ("BitsPerComponent", P.OInt 16)] <> filter (\(name, _) -> name `notElem` ["ColorSpace", "BitsPerComponent"]) (imageFields 3)
          original = imagePage {P.ipObjects = [(1, P.OStream fields (BS.pack [0, 0, 128, 0, 255, 255]))]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> do
          convertedImagePixels result @?= [BS.pack [0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 127, 255, 127, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]
          [lookup "BitsPerComponent" entries | (key, P.OStream entries _) <- P.ipObjects result, key < 0, lookup "Subtype" entries == Just (P.OName "Image")] @?= [Just (P.OInt 16)]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: an ICCBased PDF image uses the shared real raster analyzer" $ do
      let profile = P.OStream [("N", P.OInt 3), ("Filter", P.OName "FlateDecode")] (flate P.srgbProfile)
          fields = ("ColorSpace", P.OArr [P.OName "ICCBased", P.ORef 3]) : filter ((/= "ColorSpace") . fst) (imageFields 3)
          original = imagePage {P.ipObjects = [(1, P.OStream fields rgbPixels), (3, profile)]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> do
          convertedImagePixels result @?= [cmykPixels]
          lookup 3 (P.ipObjects result) @?= Just profile
        other -> assertFailure (show other),
    testCase "root ADR 0403 I3: a coloured ICCBased image remains unchanged" $ do
      let fields = ("ColorSpace", P.OArr [P.OName "ICCBased", P.ORef 3]) : filter ((/= "ColorSpace") . fst) (imageFields 2)
          original = imagePage {P.ipObjects = [(1, P.OStream fields (BS.pack [255, 0, 0, 0, 0, 255])), (3, P.OStream [("N", P.OInt 3)] P.srgbProfile)]}
      recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original @?= Right Nothing,
    testCase "root ADR 0403 I2: an ICC profile is decoded once across image paints" $ do
      let fields = ("ColorSpace", P.OArr [P.OName "ICCBased", P.ORef 3]) : filter ((/= "ColorSpace") . fst) (imageFields 3)
          original = imagePage {P.ipContent = "/Im Do /Second Do", P.ipResources = P.ODict [("XObject", P.ODict [("Im", P.ORef 1), ("Second", P.ORef 2)])], P.ipDecodedBytes = P.maxDecodedBytes - BS.length P.srgbProfile - 500, P.ipObjects = [(1, P.OStream fields rgbPixels), (2, P.OStream fields rgbPixels), (3, P.OStream [("N", P.OInt 3), ("Filter", P.OName "FlateDecode")] (flate P.srgbProfile))]}
      case recolorImportedPage (0, 100, 100, 0) (analyzeRaster (0, 100, 100, 0)) original of
        Right (Just result) -> convertedImagePixels result @?= [cmykPixels, cmykPixels]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a non-unit ICC Range is not silently treated as ordinary samples" $ do
      let fields = ("ColorSpace", P.OArr [P.OName "ICCBased", P.ORef 3]) : filter ((/= "ColorSpace") . fst) (imageFields 3)
          original = imagePage {P.ipObjects = [(1, P.OStream fields rgbPixels), (3, P.OStream [("N", P.OInt 3), ("Range", P.OArr (map P.OInt [0, 2, 0, 1, 0, 1]))] P.srgbProfile)]}
      case recolorImportedPage (0, 100, 100, 0) rgbAnalyzer original of
        Left _ -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: cyclic ICC profile references are rejected" $ do
      let fields = ("ColorSpace", P.OArr [P.OName "ICCBased", P.ORef 3]) : filter ((/= "ColorSpace") . fst) (imageFields 3)
          original = imagePage {P.ipObjects = [(1, P.OStream fields rgbPixels), (3, P.ORef 4), (4, P.ORef 3)]}
      case recolorImportedPage (0, 100, 100, 0) rgbAnalyzer original of
        Left _ -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a PDF RGB image is decoded and recolored through the shared raster analyzer" $ do
      let original = imagePage
          analyzer input
            | P.imgColor input == P.CsRgb && P.imgData input == rgbPixels = Right (RasterAnalysis Grayscale (Just input {P.imgColor = P.CsCmyk, P.imgData = cmykPixels}))
            | otherwise = Left "unexpected raster input"
      case recolorImportedPage (0, 100, 100, 0) analyzer original of
        Right (Just result) -> do
          let images = [(fields, bytes) | (key, P.OStream fields bytes) <- P.ipObjects result, key < 0, lookup "Subtype" fields == Just (P.OName "Image")]
          case images of
            [(fields, bytes)] -> do
              lookup "ColorSpace" fields @?= Just (P.OName "DeviceCMYK")
              lookup "BitsPerComponent" fields @?= Just (P.OInt 8)
              bytes @?= cmykPixels
            other -> assertFailure (show other)
          lookup 1 (P.ipObjects result) @?= lookup 1 (P.ipObjects original)
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a PDF image uses the existing Flate and predictor decoder" $ do
      let parms = P.ODict [("Predictor", P.OInt 2), ("Colors", P.OInt 3), ("Columns", P.OInt 3), ("BitsPerComponent", P.OInt 8)]
          predicted = BS.pack [0, 0, 0, 128, 128, 128, 127, 127, 127]
          original = imagePage {P.ipObjects = [(1, P.OStream (("Filter", P.OName "FlateDecode") : ("DecodeParms", parms) : imageFields 3) (flate predicted))]}
      case recolorImportedPage (0, 100, 100, 0) rgbAnalyzer original of
        Right (Just result) -> convertedImagePixels result @?= [cmykPixels]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: repeated image paints share one converted image object" $ do
      let original = imagePage {P.ipContent = "/Im Do /Im Do /Im Do", P.ipDecodedBytes = P.maxDecodedBytes - 120}
      case recolorImportedPage (0, 100, 100, 0) rgbAnalyzer original of
        Right (Just result) -> do
          convertedImagePixels result @?= [cmykPixels]
          length (P.ipObjects result) @?= 2
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: an image in a Form inherits its own resource scope" $ do
      let form = P.OStream [("Subtype", P.OName "Form"), ("Resources", P.ODict [("XObject", P.ODict [("Im", P.ORef 2)])])] "/Im Do"
          original = (page "/F Do") {P.ipResources = P.ODict [("XObject", P.ODict [("F", P.ORef 1)])], P.ipObjects = [(1, form), (2, P.OStream (imageFields 3) rgbPixels)]}
      case recolorImportedPage (0, 100, 100, 0) rgbAnalyzer original of
        Right (Just result) -> do
          convertedImagePixels result @?= [cmykPixels]
          length (P.ipObjects result) @?= 4
          lookup 1 (P.ipObjects result) @?= Just form
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: PDF image recoloring preserves a shared grayscale soft mask" $ do
      let samples = BS.pack [0, 128, 255]
          original = softMaskPage [] samples
          analyzer input
            | P.imgAlpha input == Just (P.Alpha 8 samples) = rgbAnalyzer input
            | otherwise = Left "unexpected alpha samples"
      case recolorImportedPage (0, 100, 100, 0) analyzer original of
        Right (Just result) -> do
          convertedImagePixels result @?= [cmykPixels]
          lookup 2 (P.ipObjects result) @?= lookup 2 (P.ipObjects original)
          let masks = [lookup "SMask" fields | (key, P.OStream fields _) <- P.ipObjects result, key < 0, lookup "Subtype" fields == Just (P.OName "Image")]
          masks @?= [Just (P.ORef 2)]
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: inverse Decode on a PDF soft mask is used only for visibility analysis" $ do
      let original = softMaskPage [("Decode", P.OArr [P.OInt 1, P.OInt 0])] (BS.pack [0, 128, 255])
          analyzer input
            | P.imgAlpha input == Just (P.Alpha 8 (BS.pack [255, 127, 0])) = rgbAnalyzer input
            | otherwise = Left "unexpected inverse alpha"
      case recolorImportedPage (0, 100, 100, 0) analyzer original of
        Right (Just result) -> lookup 2 (P.ipObjects result) @?= lookup 2 (P.ipObjects original)
        other -> assertFailure (show other),
    testCase "root ADR 0403 I3: a multicolor PDF image preserves the complete original page" $
      recolorImportedPage (0, 100, 100, 0) (const (Right (RasterAnalysis Multicolor Nothing))) imagePage @?= Right Nothing,
    testCase "root ADR 0403 I2: a PDF image reserves decode and output space before invoking the raster analyzer" $ do
      let oversized = imagePage {P.ipObjects = [(1, P.OStream (imageFields 1073741824) rgbPixels)]}
      case recolorImportedPage (0, 100, 100, 0) (const (Left "analyzer must not run")) oversized of
        Left message -> assertBool (T.unpack message) ("上限" `T.isInfixOf` message)
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a nested PDF Form is recolored" $ do
      result <- requireConverted (formPage ".5 g 0 0 10 10 re f" "/F Do")
      let content = newFormContent result
      assertBool "nested gray" ("0 0.5 0.5 0 k" `BS.isInfixOf` content),
    testCase "root ADR 0403 I1: a PDF Form inherits the caller paint" $ do
      result <- requireConverted (formPage "0 0 10 10 re f" ".5 g /F Do")
      assertBool "inherited paint is not reset to black" (not ("0 1 1 0 k" `BS.isInfixOf` newFormContent result)),
    testCase "root ADR 0403 I3: a reused Form in two colors keeps the original PDF" $
      recolor (formPage "0 0 10 10 re f" "1 0 0 rg /F Do 0 0 1 rg /F Do") @?= Right Nothing,
    testCase "root ADR 0403 I2: converted Forms are cloned without changing soft-mask resources" $ do
      let base = formPage "0 g 0 0 10 10 re f" "/Alpha gs /F Do"
          original = base {P.ipResources = P.ODict [("XObject", P.ODict [("F", P.ORef 1)]), ("ExtGState", P.ODict [("Alpha", P.ODict [("SMask", P.ODict [("S", P.OName "Luminosity"), ("G", P.ORef 1)])])])]}
      result <- requireConverted original
      lookup 1 (P.ipObjects result) @?= lookup 1 (P.ipObjects original)
      assertBool "original object not reused for paint" (P.ipResources result /= P.ipResources original),
    testCase "root ADR 0403 I2: a nested soft mask keeps the source XObject binding" $ do
      let base = formPage ".5 g 0 0 10 10 re f" "/Alpha gs /F Do"
          original = base {P.ipResources = P.ODict [("XObject", P.ODict [("F", P.ORef 1)]), ("ExtGState", P.ODict [("Alpha", P.ODict [("SMask", P.ODict [("S", P.OName "Luminosity"), ("G", P.ORef 3)])])])], P.ipObjects = P.ipObjects base <> [(3, P.OStream [("Subtype", P.OName "Form")] "/F Do")]}
      result <- requireConverted original
      case P.ipResources result of
        P.ODict fields | Just (P.ODict objects) <- lookup "XObject" fields -> lookup "F" objects @?= Just (P.ORef 1)
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: a cyclic PDF Form graph is rejected" $ do
      let cyclic = formPage "/F Do" "/F Do"
      case recolor cyclic of
        Left _ -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: a shared PDF Form graph is summarized without expansion" $ do
      result <- requireConverted sharedForms
      length (P.ipObjects result) @?= 80,
    testCase "root ADR 0403 I2: shared indirect Form resources remain shared" $ do
      let base = sharedForms
          own (key, P.OStream fields bytes) = (key, P.OStream (("Resources", P.ORef 1000) : fields) bytes)
          own object = object
          original = base {P.ipResources = P.ORef 1000, P.ipObjects = map own (P.ipObjects base) <> [(1000, P.ipResources base)]}
      result <- requireConverted original
      case P.ipResources result of
        P.ORef resourceKey -> do
          assertBool "resource dictionary cloned" (resourceKey /= 1000)
          let forms = [fields | (key, P.OStream fields _) <- P.ipObjects result, key < 0, lookup "Subtype" fields == Just (P.OName "Form")]
          length forms @?= 40
          map (lookup "Resources") forms @?= replicate 40 (Just (P.ORef resourceKey))
          length (P.ipObjects result) @?= 82
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: a compressed PDF Form uses its indirect filter" $ do
      let original = (formPage "unused" "/F Do") {P.ipObjects = [(1, P.OStream [("Subtype", P.OName "Form"), ("Filter", P.ORef 2)] (flate ".5 g 0 0 10 10 re f")), (2, P.OName "FlateDecode")]}
      result <- requireConverted original
      assertBool "decoded and recolored" ("0 0.5 0.5 0 k" `BS.isInfixOf` newFormContent result),
    testCase "root ADR 0403 I1: fully transparent PDF paint does not make a gray figure multicolor" $ do
      let original = (page "/Hide gs 1 0 0 rg 0 0 10 10 re f /Show gs .5 g 10 0 10 10 re f") {P.ipResources = P.ODict [("ExtGState", P.ODict [("Hide", P.ODict [("ca", P.OInt 0)]), ("Show", P.ODict [("ca", P.OInt 1)])])]}
      _ <- requireConverted original
      pure (),
    testCase "root ADR 0403 I1: PDF white black and gray become CMYK tints" $ do
      p <- converted "1 g 0 0 10 10 re f 0 g 10 0 10 10 re f .5 g 20 0 10 10 re f"
      assertBool "white" ("0 0 0 0 k" `BS.isInfixOf` P.ipContent p)
      assertBool "black" ("0 1 1 0 k" `BS.isInfixOf` P.ipContent p)
      assertBool "half" ("0 0.5 0.5 0 k" `BS.isInfixOf` P.ipContent p),
    testCase "root ADR 0403 I1: neutral CMYK and its RGB approximation use the same tint" $ do
      cmyk <- converted ".5 .5 .5 .5 k 0 0 10 10 re f"
      rgb <- converted ".25 .25 .25 rg 0 0 10 10 re f"
      P.ipContent cmyk @?= P.ipContent rgb,
    testCase "root ADR 0403 I1: unused non-gray color does not make PDF multicolor" $ do
      _ <- converted "1 0 0 rg 0 g 0 0 10 10 re f"
      pure (),
    testCase "root ADR 0403 I1: the default PDF paint is black" $ do
      p <- converted "0 0 10 10 re f"
      assertBool "default black converted" ("0 1 1 0 k" `BS.isPrefixOf` P.ipContent p),
    testCase "root ADR 0403 I2: PDF geometry transparency and resource objects stay intact" $ do
      let original = (page "0 g /Alpha gs 0 0 10 10 re f") {P.ipBox = (2, 3, 12, 23), P.ipRotate = 90, P.ipSize = (20, 10), P.ipResources = P.ODict [("ExtGState", P.ODict [("Alpha", P.ODict [("ca", P.OReal "0.5"), ("CA", P.OReal "0.5")])])]}
      p <- requireConverted original
      P.ipBox p @?= P.ipBox original
      P.ipRotate p @?= P.ipRotate original
      P.ipSize p @?= P.ipSize original
      P.ipResources p @?= P.ipResources original
      P.ipObjects p @?= P.ipObjects original
      assertBool "alpha operator retained" ("/Alpha gs" `BS.isInfixOf` P.ipContent p),
    testCase "root ADR 0403 I3: differently colored painted objects keep original PDF" $
      recolor (page "1 0 0 rg 0 0 10 10 re f 0 0 1 rg 10 0 10 10 re f") @?= Right Nothing,
    testCase "root ADR 0403 I3: multicolor inside a saved state preserves the entire PDF" $
      recolor (page "q 1 0 0 rg 0 0 10 10 re f 0 0 1 rg 10 0 10 10 re f Q") @?= Right Nothing,
    testCase "root ADR 0403 I3: graphics-state restore recovers the original paint" $
      recolor (page "1 0 0 rg q 0 g 0 0 10 10 re f Q 10 0 10 10 re f") @?= Right Nothing,
    testCase "root ADR 0403 I1: invisible PDF text adds no paint" $ do
      _ <- converted "1 0 0 rg 3 Tr (invisible) Tj 0 g 0 0 10 10 re f"
      pure (),
    testCase "root ADR 0403 I2: recoloring shares the remaining PDF decode budget" $ do
      let original = (page "0 0 10 10 re f") {P.ipDecodedBytes = 256 * 1024 * 1024 - 1}
      case recolor original of
        Left _ -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: changed PDF objects have swatch-specific identities" $ do
      red <- requireConverted (page "0 g 0 0 10 10 re f")
      let blue = recolorImportedPage (100, 100, 0, 0) noRaster (page "0 g 0 0 10 10 re f")
      case blue of
        Right (Just p) -> do
          assertBool "different swatches" (P.ipFile red /= P.ipFile p)
          assertBool "different from source" (P.ipFile p /= P.ipFile (page ""))
        other -> assertFailure (show other)
  ]
  where
    recolor = recolorImportedPage (0, 100, 100, 0) noRaster
    noRaster _ = Right (RasterAnalysis Multicolor Nothing)
    converted = requireConverted . page
    requireConverted p = case recolor p of
      Right (Just result) -> pure result
      other -> assertFailure (show other) >> pure p

page :: ByteString -> P.ImportedPage
page content = P.ImportedPage "source" 1 (0, 0, 30, 10) 0 (30, 10) (P.ODict []) Nothing content [] [P.UseGray] 0

formPage :: ByteString -> ByteString -> P.ImportedPage
formPage form content =
  (page content)
    { P.ipResources = P.ODict [("XObject", P.ODict [("F", P.ORef 1)])],
      P.ipObjects = [(1, P.OStream [("Type", P.OName "XObject"), ("Subtype", P.OName "Form"), ("BBox", P.OArr (map P.OInt [0, 0, 10, 10]))] form)]
    }

newFormContent :: P.ImportedPage -> ByteString
newFormContent p = case (P.ipResources p, P.contentOperations (P.ipContent p)) of
  (P.ODict fields, Just operations)
    | Just (P.ODict objects) <- lookup "XObject" fields,
      name : _ <- [TE.decodeLatin1 (BS.drop 1 name) | ("Do", [name]) <- operations],
      Just (P.ORef key) <- lookup name objects,
      Just (P.OStream _ content) <- lookup key (P.ipObjects p) ->
        content
  _ -> "missing converted Form"

sharedForms :: P.ImportedPage
sharedForms =
  (page "/F1 Do")
    { P.ipResources = P.ODict [("XObject", P.ODict [(name n, P.ORef n) | n <- [1 .. 40]])],
      P.ipObjects = [(n, P.OStream [("Subtype", P.OName "Form")] (if n == 40 then "0 g 0 0 10 10 re f" else TE.encodeUtf8 ("/" <> name (n + 1) <> " Do /" <> name (n + 1) <> " Do"))) | n <- [1 .. 40]]
    }
  where
    name n = "F" <> T.pack (show n)

rgbPixels :: ByteString
rgbPixels = BS.pack [0, 0, 0, 128, 128, 128, 255, 255, 255]

cmykPixels :: ByteString
cmykPixels = BS.pack [0, 255, 255, 0, 0, 127, 127, 0, 0, 0, 0, 0]

imageFields :: Integer -> [(T.Text, P.ObjOf P.ObjNum)]
imageFields width = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt width), ("Height", P.OInt 1), ("BitsPerComponent", P.OInt 8), ("ColorSpace", P.OName "DeviceRGB")]

imagePage :: P.ImportedPage
imagePage = (page "/Im Do") {P.ipResources = P.ODict [("XObject", P.ODict [("Im", P.ORef 1)])], P.ipObjects = [(1, P.OStream (imageFields 3) rgbPixels)]}

rgbAnalyzer :: P.ImageData -> Either T.Text RasterAnalysis
rgbAnalyzer input
  | P.imgColor input == P.CsRgb && P.imgData input == rgbPixels = Right (RasterAnalysis Grayscale (Just input {P.imgColor = P.CsCmyk, P.imgData = cmykPixels}))
  | otherwise = Left "unexpected raster input"

convertedImagePixels :: P.ImportedPage -> [ByteString]
convertedImagePixels result = [bytes | (key, P.OStream fields bytes) <- P.ipObjects result, key < 0, lookup "Subtype" fields == Just (P.OName "Image")]

softMaskPage :: [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> P.ImportedPage
softMaskPage extra samples = imagePage {P.ipObjects = [(1, P.OStream (("SMask", P.ORef 2) : imageFields 3) rgbPixels), (2, P.OStream ([("Subtype", P.OName "Image"), ("Width", P.OInt 3), ("Height", P.OInt 1), ("BitsPerComponent", P.OInt 8), ("ColorSpace", P.OName "DeviceGray"), ("Filter", P.OName "FlateDecode")] <> extra) (flate samples))]}
