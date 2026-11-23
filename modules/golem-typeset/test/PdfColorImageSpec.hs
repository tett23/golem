{- | Images of CIE-based and ICCBased colour spaces in imported PDF figures
(root ADR 0425): CalGray, CalRGB and Lab images, ICCBased images of Lab data
or of a Range other than 0 to 1, and Indexed spaces on these bases. Their
samples are mapped through Decode and compared as rationals.
-}
module PdfColorImageSpec (pdfColorImageTests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (analyzeRaster)
import Golem.Typeset.PdfColor (recolorImportedPage)
import Test.Tasty
import Test.Tasty.HUnit

swatch :: (Int, Int, Int, Int)
swatch = (0, 100, 100, 0)

recolor :: P.ImportedPage -> Either T.Text (Maybe P.ImportedPage)
recolor = recolorImportedPage swatch (analyzeRaster swatch)

pdfColorImageTests :: [TestTree]
pdfColorImageTests =
  [ testGroup "root ADR 0425 I3: CIE-based images" cieTests,
    testGroup "root ADR 0425 I4: ICCBased images by their data colour space and Range" iccTests,
    testGroup "root ADR 0425 I3, I4: Indexed spaces on CIE-based and ICCBased bases" indexedTests
  ]

cieTests :: [TestTree]
cieTests =
  [ testCase "root ADR 0425 I3: a CalGray image is a tone of its samples" $
      pixels (image (calSpace "CalGray") 3 8 [] (BS.pack [0, 128, 255])) @?= Right [cmyk [[0, 255, 255, 0], [0, 127, 127, 0], [0, 0, 0, 0]]],
    testCase "root ADR 0425 I3: a 16-bit CalGray image keeps its precision" $
      pixels (image (calSpace "CalGray") 3 16 [] (BS.pack [0, 0, 128, 0, 255, 255])) @?= Right [BS.pack [0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 127, 255, 127, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]],
    testCase "root ADR 0425 I3: a CalRGB image of equal components is a tone" $
      pixels (image (calSpace "CalRGB") 3 8 [] (BS.pack [0, 0, 0, 128, 128, 128, 255, 255, 255])) @?= Right [cmyk [[0, 255, 255, 0], [0, 127, 127, 0], [0, 0, 0, 0]]],
    testCase "root ADR 0425 I3: a CalRGB image with a pixel of unequal components besides a gray one is multicolour" $
      recolor (image (calSpace "CalRGB") 2 8 [] (BS.pack [128, 128, 128, 128, 128, 129])) @?= Right Nothing,
    testCase "root ADR 0425 I3: a CalRGB image of one colour paints the swatch" $
      pixels (image (calSpace "CalRGB") 2 8 [] (BS.pack [128, 128, 129, 128, 128, 129])) @?= Right [cmyk [[0, 255, 255, 0], [0, 255, 255, 0]]],
    testCase "root ADR 0425 I3: a Lab image whose a* and b* map to 0 is a tone of L* / 100" $
      pixels (image (labSpace [("Range", P.OArr (map P.OInt [-128, 127, -128, 127]))]) 2 8 [] (BS.pack [0, 128, 128, 255, 128, 128])) @?= Right [cmyk [[0, 255, 255, 0], [0, 0, 0, 0]]],
    testCase "root ADR 0425 I3: an 8-bit Lab image of the default Range has no a* of exactly 0" $
      recolor (image (labSpace []) 2 8 [] (BS.pack [0, 127, 127, 255, 127, 127])) @?= Right Nothing,
    testCase "root ADR 0425 I3: a Lab image clips a* and b* to their Range after Decode" $
      pixels (image (labSpace [("Range", P.OArr (map P.OInt [0, 10, 0, 10]))]) 2 8 [("Decode", P.OArr (map P.OInt [0, 100, -10, 10, -10, 10]))] (BS.pack [0, 0, 0, 255, 0, 0])) @?= Right [cmyk [[0, 255, 255, 0], [0, 0, 0, 0]]],
    testCase "root ADR 0425 I3: a hidden pixel of a CalRGB image adds no colour" $
      pixels
        ( (image (calSpace "CalRGB") 2 8 [("SMask", P.ORef 2)] (BS.pack [0, 0, 0, 255, 0, 0]))
            `withObjects` [(2, P.OStream [("Subtype", P.OName "Image"), ("Width", P.OInt 2), ("Height", P.OInt 1), ("BitsPerComponent", P.OInt 8), ("ColorSpace", P.OName "DeviceGray")] (BS.pack [255, 0]))]
        )
        @?= Right [cmyk [[0, 255, 255, 0], [0, 255, 255, 0]]],
    testCase "root ADR 0425 I3: a CalRGB fill and a CalRGB image of the same colour are recoloured" $
      case recolor (sameSpace "/C cs 1 0 0 scn 0 0 1 1 re f /Im Do" (BS.pack [255, 0, 0])) of
        Right (Just result) -> do
          assertBool (show (P.ipContent result)) ("0 1 1 0 k" `BS.isInfixOf` P.ipContent result)
          convertedPixels result @?= [cmyk [[0, 255, 255, 0]]]
        other -> assertFailure (show other),
    testCase "root ADR 0425 I3: a CalRGB fill and a CalRGB image of different colours are multicolour" $
      recolor (sameSpace "/C cs 1 0 0 scn 0 0 1 1 re f /Im Do" (BS.pack [0, 255, 0])) @?= Right Nothing
  ]

iccTests :: [TestTree]
iccTests =
  [ testCase "root ADR 0425 I4: an ICCBased Lab image with Range [0 100 -128 127 -128 127] is a tone of L* / 100" $
      pixels (image iccSpace 2 8 [] (BS.pack [0, 128, 128, 255, 128, 128]) `withObjects` [profileObject 3 [0, 100, -128, 127, -128, 127] "Lab "]) @?= Right [cmyk [[0, 255, 255, 0], [0, 0, 0, 0]]],
    testCase "root ADR 0425 I4: an ICCBased RGB image with Range [0 2 0 2 0 2] maps its samples by the Range" $
      pixels (image iccSpace 2 8 [] (BS.pack [0, 0, 0, 255, 255, 255]) `withObjects` [profileObject 3 [0, 2, 0, 2, 0, 2] "RGB "]) @?= Right [cmyk [[0, 255, 255, 0], [0, 0, 0, 0]]],
    testCase "root ADR 0425 I4: an ICCBased RGB image with Range [0 2 0 2 0 2] and Decode [0 1 0 1 0 1] has the tone of g 0.5" $
      pixels (image iccSpace 1 8 [("Decode", P.OArr (map P.OInt [0, 1, 0, 1, 0, 1]))] (BS.pack [255, 255, 255]) `withObjects` [profileObject 3 [0, 2, 0, 2, 0, 2] "RGB "]) @?= Right [cmyk [[0, 128, 128, 0]]],
    testCase "root ADR 0425 I4: an ICCBased Gray image with Range [0 4] is a tone of the mapped value" $
      pixels (image iccSpace 2 8 [("Decode", P.OArr (map P.OInt [0, 2]))] (BS.pack [0, 255]) `withObjects` [profileObject 1 [0, 4] "GRAY"]) @?= Right [cmyk [[0, 255, 255, 0], [0, 128, 128, 0]]],
    testCase "root ADR 0425 I4: an ICCBased RGB image whose Range differs by component is not read as device samples" $
      recolor (image iccSpace 3 8 [("Decode", P.OArr (map P.OInt [0, 1, 0, 1, 0, 1]))] (BS.pack [0, 0, 0, 128, 128, 128, 255, 255, 255]) `withObjects` [profileObject 3 [0, 2, 0, 1, 0, 1] "RGB "]) @?= Right Nothing,
    testCase "root ADR 0425 I4: an ICCBased Lab image whose profile has N 1 is G08113" $
      rejected (image iccSpace 1 8 [] (BS.pack [0]) `withObjects` [profileObject 1 [0, 100] "Lab "])
  ]

indexedTests :: [TestTree]
indexedTests =
  [ testCase "root ADR 0425 I4: an Indexed image on an ICCBased Lab base maps its table by the Range" $
      pixels (image (P.OArr [P.OName "Indexed", iccSpace, P.OInt 1, P.OHex (BS.pack [0, 128, 128, 255, 128, 128])]) 2 8 [] (BS.pack [0, 1]) `withObjects` [profileObject 3 [0, 100, -128, 127, -128, 127] "Lab "]) @?= Right [cmyk [[0, 255, 255, 0], [0, 0, 0, 0]]],
    testCase "root ADR 0425 I4: an Indexed image on an ICCBased Lab base with a colour entry is multicolour" $
      recolor (image (P.OArr [P.OName "Indexed", iccSpace, P.OInt 1, P.OHex (BS.pack [0, 128, 128, 255, 128, 129])]) 2 8 [] (BS.pack [0, 1]) `withObjects` [profileObject 3 [0, 100, -128, 127, -128, 127] "Lab "]) @?= Right Nothing,
    testCase "root ADR 0425 I3: an Indexed image on a CalRGB base of equal components is a tone" $
      pixels (image (P.OArr [P.OName "Indexed", calSpace "CalRGB", P.OInt 1, P.OHex (BS.pack [128, 128, 128, 0, 0, 0])]) 2 8 [] (BS.pack [0, 1])) @?= Right [cmyk [[0, 127, 127, 0], [0, 255, 255, 0]]],
    testCase "root ADR 0425 I4: an Indexed fill colour on an ICCBased Lab base is a tone" $
      tinted "0 1 1 0 k" ((page "0 g 0 0 1 1 re f /I cs 0 scn 0 0 1 1 re f") {P.ipResources = P.ODict [("ColorSpace", P.ODict [("I", P.OArr [P.OName "Indexed", iccSpace, P.OInt 0, P.OHex (BS.pack [0, 128, 128])])])], P.ipObjects = [profileObject 3 [0, 100, -128, 127, -128, 127] "Lab "]})
  ]

-- | The pixels of the converted images of a recoloured page.
pixels :: P.ImportedPage -> Either T.Text [ByteString]
pixels p = case recolor p of
  Right (Just result) -> Right (convertedPixels result)
  Right Nothing -> Left "unchanged"
  Left why -> Left why

convertedPixels :: P.ImportedPage -> [ByteString]
convertedPixels result = [bytes | (key, P.OStream fields bytes) <- P.ipObjects result, key < 0, lookup "Subtype" fields == Just (P.OName "Image")]

cmyk :: [[Int]] -> ByteString
cmyk = BS.pack . map fromIntegral . concat

rejected :: P.ImportedPage -> Assertion
rejected p = case recolor p of
  Left _ -> pure ()
  other -> assertFailure ("expected G08113, got " <> show other)

tinted :: ByteString -> P.ImportedPage -> Assertion
tinted expected p = case recolor p of
  Right (Just result) -> assertBool ("expected " <> show expected <> " in " <> show (P.ipContent result)) (expected `BS.isInfixOf` P.ipContent result)
  other -> assertFailure (show other)

page :: ByteString -> P.ImportedPage
page content = P.ImportedPage "source" 1 (0, 0, 30, 10) 0 (30, 10) (P.ODict []) Nothing content [] [P.UseGray] 0

-- | A page painting one image of a row of pixels in the given space.
image :: P.ObjOf P.ObjNum -> Integer -> Integer -> [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> P.ImportedPage
image space width bits extra bytes =
  (page "/Im Do")
    { P.ipResources = P.ODict [("XObject", P.ODict [("Im", P.ORef 1)])],
      P.ipObjects = [(1, P.OStream ([("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt width), ("Height", P.OInt 1), ("BitsPerComponent", P.OInt bits), ("ColorSpace", space)] <> extra) bytes)]
    }

withObjects :: P.ImportedPage -> [(P.ObjNum, P.ObjOf P.ObjNum)] -> P.ImportedPage
withObjects p objects = p {P.ipObjects = P.ipObjects p <> objects}

-- | A fill and an image both in the CalRGB space of the resource /C.
sameSpace :: ByteString -> ByteString -> P.ImportedPage
sameSpace content bytes =
  (image (P.OName "C") 1 8 [] bytes)
    { P.ipContent = content,
      P.ipResources = P.ODict [("ColorSpace", P.ODict [("C", calSpace "CalRGB")]), ("XObject", P.ODict [("Im", P.ORef 1)])]
    }

calSpace :: T.Text -> P.ObjOf P.ObjNum
calSpace family = P.OArr [P.OName family, P.ODict [("WhitePoint", P.OArr [P.OReal "0.9505", P.OInt 1, P.OReal "1.089"])]]

labSpace :: [(T.Text, P.ObjOf P.ObjNum)] -> P.ObjOf P.ObjNum
labSpace extra = P.OArr [P.OName "Lab", P.ODict ([("WhitePoint", P.OArr [P.OReal "0.9505", P.OInt 1, P.OReal "1.089"])] <> extra)]

-- | An ICCBased space on the profile object 7.
iccSpace :: P.ObjOf P.ObjNum
iccSpace = P.OArr [P.OName "ICCBased", P.ORef 7]

profileObject :: Integer -> [Integer] -> ByteString -> (P.ObjNum, P.ObjOf P.ObjNum)
profileObject components range space = (7, P.OStream [("N", P.OInt components), ("Range", P.OArr (map P.OInt range))] (BS.replicate 16 0 <> space <> BS.replicate 108 0))
