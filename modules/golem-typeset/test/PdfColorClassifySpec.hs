{- | The classification of the colours of imported PDF figures and the
constructs that cannot be recoloured (root ADR 0425): the graphics state
(blend modes, transfer functions, overprint), CIE-based colour spaces, the
data colour space of ICC profiles, and soft masks.
-}
module PdfColorClassifySpec (pdfColorClassifyTests) where

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

pdfColorClassifyTests :: [TestTree]
pdfColorClassifyTests =
  [ testGroup "root ADR 0425 I1: the graphics state" graphicsStateTests,
    testGroup "root ADR 0425 I1: ICC profiles and soft masks" profileAndMaskTests,
    testGroup "root ADR 0425 I3: CIE-based colour spaces" cieTests,
    testGroup "root ADR 0425 I4: ICCBased colour spaces by their data colour space" iccTests,
    testGroup "root ADR 0425 I5: the figure has one class" classTests
  ]

graphicsStateTests :: [TestTree]
graphicsStateTests =
  [ testCase "root ADR 0425 I1: BM Multiply over two gray rectangles is G08113" $
      rejected (states "/S gs .2 g 0 0 2 2 re f .4 g 1 1 2 2 re f" [("S", [("BM", P.OName "Multiply")])]),
    testCase "root ADR 0425 I1: a BM array of only Normal and Compatible is recoloured" $
      tinted "0 0.5 0.5 0 k" (states "/S gs .5 g 0 0 1 1 re f" [("S", [("BM", P.OArr [P.OName "Normal", P.OName "Compatible"])])]),
    testCase "root ADR 0425 I1: an empty BM array is G08113" $
      rejected (states "/S gs .5 g 0 0 1 1 re f" [("S", [("BM", P.OArr [])])]),
    testCase "root ADR 0425 I1: BM [Multiply Normal] is G08113" $
      rejected (states "/S gs .5 g 0 0 1 1 re f" [("S", [("BM", P.OArr [P.OName "Multiply", P.OName "Normal"])])]),
    testCase "root ADR 0425 I1: BM [Normal Multiply] is G08113" $
      rejected (states "/S gs .5 g 0 0 1 1 re f" [("S", [("BM", P.OArr [P.OName "Normal", P.OName "Multiply"])])]),
    testCase "root ADR 0425 I1: TR Identity and TR2 Default are recoloured" $
      tinted "0 0.5 0.5 0 k" (states "/S gs .5 g 0 0 1 1 re f" [("S", [("TR", P.OName "Identity"), ("TR2", P.OName "Default")])]),
    testCase "root ADR 0425 I1: a TR2 function is G08113" $
      rejected (states "/S gs .5 g 0 0 1 1 re f" [("S", [("TR2", P.ODict [("FunctionType", P.OInt 2), ("Domain", P.OArr [P.OInt 0, P.OInt 1]), ("N", P.OInt 1)])])]),
    testCase "root ADR 0425 I1: OPM 1 with op true is G08113 when filling" $
      rejected (states "/S gs .5 g 0 0 1 1 re f" [("S", [("OPM", P.OInt 1), ("op", P.OBool True)])]),
    testCase "root ADR 0425 I1: OPM 1 with OP true is G08113 when filling, as OP sets both without op" $
      rejected (states "/S gs .5 g 0 0 1 1 re f" [("S", [("OPM", P.OInt 1), ("OP", P.OBool True)])]),
    testCase "root ADR 0425 I1: OPM 1 with OP true is G08113 when stroking" $
      rejected (states "/S gs .5 G 0 0 1 1 re S" [("S", [("OPM", P.OInt 1), ("OP", P.OBool True), ("op", P.OBool False)])]),
    testCase "root ADR 0425 I1: OPM 1 with OP true and op false fills without overprint" $
      tinted "0 0.5 0.5 0 k" (states "/S gs .5 g 0 0 1 1 re f" [("S", [("OPM", P.OInt 1), ("OP", P.OBool True), ("op", P.OBool False)])]),
    testCase "root ADR 0425 I1: OPM 0 with op true is recoloured" $
      tinted "0 0.5 0.5 0 k" (states "/S gs .5 g 0 0 1 1 re f" [("S", [("OPM", P.OInt 0), ("op", P.OBool True)])]),
    testCase "root ADR 0425 I1: OPM 1 from one gs and OP true from another is G08113" $
      rejected (states "/A gs /B gs .5 g 0 0 1 1 re f" [("A", [("OPM", P.OInt 1)]), ("B", [("OP", P.OBool True)])]),
    testCase "root ADR 0425 I1: OPM 1 with op false, then a gs with only OP true, is G08113" $
      rejected (states "/A gs /B gs .5 g 0 0 1 1 re f" [("A", [("OPM", P.OInt 1), ("op", P.OBool False)]), ("B", [("OP", P.OBool True)])]),
    testCase "root ADR 0425 I1: overprint restored by Q no longer applies" $
      tinted "0 0.5 0.5 0 k" (states "q /S gs Q .5 g 0 0 1 1 re f" [("S", [("OPM", P.OInt 1), ("op", P.OBool True)])]),
    testCase "root ADR 0425 I1: an overprinting image is G08113" $
      rejected
        ( (states "/S gs /Im Do" [("S", [("OPM", P.OInt 1), ("op", P.OBool True)])])
            { P.ipResources = P.ODict [("ExtGState", P.ODict [("S", P.ODict [("OPM", P.OInt 1), ("op", P.OBool True)])]), ("XObject", P.ODict [("Im", P.ORef 1)])],
              P.ipObjects = [(1, P.OStream (grayImage 2 1 <> [("ColorSpace", P.OName "DeviceGray")]) (BS.pack [0, 255]))]
            }
        )
  ]

profileAndMaskTests :: [TestTree]
profileAndMaskTests =
  [ testCase "root ADR 0425 I1: an ICCBased space whose data colour space is XYZ is G08113" $
      rejected (spaces "/C cs .5 .5 .5 scn 0 0 1 1 re f" [("C", P.OArr [P.OName "ICCBased", P.ORef 7])] [(7, P.OStream [("N", P.OInt 3)] (profile "XYZ "))]),
    testCase "root ADR 0425 I1: an ICCBased space whose data colour space is Gray with N 3 is G08113" $
      rejected (spaces "/C cs .5 .5 .5 scn 0 0 1 1 re f" [("C", P.OArr [P.OName "ICCBased", P.ORef 7])] [(7, P.OStream [("N", P.OInt 3)] (profile "GRAY"))]),
    testCase "root ADR 0425 I1: an ICCBased image whose data colour space is XYZ is G08113" $
      rejected (image (grayImage 2 8 <> [("ColorSpace", P.OArr [P.OName "ICCBased", P.ORef 7])]) (BS.pack [0, 255]) [(7, P.OStream [("N", P.OInt 1)] (profile "XYZ "))]),
    testCase "root ADR 0425 I1: a DeviceRGB soft mask is G08113" $
      rejected (image (grayImage 2 8 <> [("ColorSpace", P.OName "DeviceGray"), ("SMask", P.ORef 2)]) (BS.pack [0, 255]) [(2, P.OStream (grayImage 2 8 <> [("ColorSpace", P.OName "DeviceRGB")]) (BS.replicate 6 255))]),
    testCase "root ADR 0425 I1: a soft mask with Matte of another size than the image is G08113" $
      rejected (image (grayImage 2 8 <> [("ColorSpace", P.OName "DeviceGray"), ("SMask", P.ORef 2)]) (BS.pack [0, 255]) [(2, P.OStream (grayImage 4 8 <> [("ColorSpace", P.OName "DeviceGray"), ("Matte", P.OArr [P.OInt 0])]) (BS.replicate 4 255))]),
    testCase "root ADR 0425 I1: a soft mask with Matte and Interpolate true is G08113" $
      rejected (image (grayImage 2 8 <> [("ColorSpace", P.OName "DeviceGray"), ("SMask", P.ORef 2)]) (BS.pack [0, 255]) [(2, P.OStream (grayImage 2 8 <> [("ColorSpace", P.OName "DeviceGray"), ("Matte", P.OArr [P.OInt 0]), ("Interpolate", P.OBool True)]) (BS.replicate 2 255))])
  ]

cieTests :: [TestTree]
cieTests =
  [ testCase "root ADR 0425 I3: CalGray 0 and 1 are tones of g 0 and g 1" $ do
      tinted "0 1 1 0 k" (cal "CalGray" "/C cs 0 scn 0 0 1 1 re f 1 scn 1 0 1 1 re f")
      tinted "0 0 0 0 k" (cal "CalGray" "/C cs 0 scn 0 0 1 1 re f 1 scn 1 0 1 1 re f"),
    testCase "root ADR 0425 I3: CalRGB (0.5, 0.5, 0.5) is a tone of g 0.5" $
      tinted "0 0.5 0.5 0 k" (cal "CalRGB" "0 g 0 0 1 1 re f /C cs .5 .5 .5 scn 0 0 1 1 re f"),
    testCase "root ADR 0425 I3: CalRGB (0.5, 0.5, 0.51) is a colour" $ do
      recolor (cal "CalRGB" "0 g 0 0 1 1 re f /C cs .5 .5 .51 scn 0 0 1 1 re f") @?= Right Nothing
      tinted "0 1 1 0 k" (cal "CalRGB" "/C cs .5 .5 .51 scn 0 0 1 1 re f"),
    testCase "root ADR 0425 I3: Lab (50, 0, 0) is a tone of g 0.5" $
      tinted "0 0.5 0.5 0 k" (lab [] "0 g 0 0 1 1 re f /C cs 50 0 0 scn 0 0 1 1 re f"),
    testCase "root ADR 0425 I3: Lab (50, 0, 1) is a colour" $
      recolor (lab [] "0 g 0 0 1 1 re f /C cs 50 0 1 scn 0 0 1 1 re f") @?= Right Nothing,
    testCase "root ADR 0425 I3: a Lab a* outside its Range that clips to 0 is a tone" $
      tinted "0 0.5 0.5 0 k" (lab [("Range", P.OArr (map P.OInt [0, 10, -10, 10]))] "0 g 0 0 1 1 re f /C cs 50 -3 0 scn 0 0 1 1 re f"),
    testCase "root ADR 0425 I3: Lab L* clips to 0 to 100" $
      tinted "0 0 0 0 k" (lab [] "0 g 0 0 1 1 re f /C cs 150 0 0 scn 0 0 1 1 re f"),
    testCase "root ADR 0425 I3: CalRGB and DeviceRGB of the same values are different colours" $
      recolor (cal "CalRGB" "1 0 0 rg 0 0 1 1 re f /C cs 1 0 0 scn 0 0 1 1 re f") @?= Right Nothing,
    testCase "root ADR 0425 I3: two CalRGB spaces of different dictionaries are different colours" $
      recolor
        ( spaces
            "/C cs 1 0 0 scn 0 0 1 1 re f /D cs 1 0 0 scn 0 0 1 1 re f"
            [ ("C", P.OArr [P.OName "CalRGB", P.ODict [("WhitePoint", P.OArr [P.OReal "0.9505", P.OInt 1, P.OReal "1.089"])]]),
              ("D", P.OArr [P.OName "CalRGB", P.ODict [("WhitePoint", P.OArr [P.OReal "0.9505", P.OInt 1, P.OReal "1.089"]), ("Gamma", P.OArr [P.OReal "2.2", P.OReal "2.2", P.OReal "2.2"])]])
            ]
            []
        )
        @?= Right Nothing,
    testCase "root ADR 0425 I3: the same CalRGB colour twice is one colour" $
      tinted "0 1 1 0 k" (cal "CalRGB" "/C cs 1 0 0 scn 0 0 1 1 re f /C CS 1 0 0 SCN 0 0 1 1 re S")
  ]

iccTests :: [TestTree]
iccTests =
  [ testCase "root ADR 0425 I4: an ICCBased Lab profile with Range [0 100 -128 127 -128 127] and (50, 0, 0) is a tone of g 0.5" $
      tinted "0 0.5 0.5 0 k" (spaces "0 g 0 0 1 1 re f /C cs 50 0 0 scn 0 0 1 1 re f" [("C", P.OArr [P.OName "ICCBased", P.ORef 7])] [(7, P.OStream [("N", P.OInt 3), ("Range", P.OArr (map P.OInt [0, 100, -128, 127, -128, 127]))] (profile "Lab "))]),
    testCase "root ADR 0425 I4: an ICCBased RGB profile with Range [0 2 0 2 0 2] and (1, 1, 1) is a tone of g 0.5" $
      tinted "0 0.5 0.5 0 k" (spaces "0 g 0 0 1 1 re f /C cs 1 1 1 scn 0 0 1 1 re f" [("C", P.OArr [P.OName "ICCBased", P.ORef 7])] [(7, P.OStream [("N", P.OInt 3), ("Range", P.OArr (map P.OInt [0, 2, 0, 2, 0, 2]))] (profile "RGB "))]),
    testCase "root ADR 0425 I4: an ICCBased CMYK profile classifies as DeviceCMYK" $
      tinted "0 0.75 0.75 0" (spaces "0 g 0 0 1 1 re f /C cs .5 .5 .5 .5 scn 0 0 1 1 re f" [("C", P.OArr [P.OName "ICCBased", P.ORef 7])] [(7, P.OStream [("N", P.OInt 4)] (profile "CMYK"))]),
    testCase "root ADR 0425 I4: an ICCBased Lab L* beyond 100 within its Range is white" $
      tinted "0 0 0 0 k" (spaces "0 g 0 0 1 1 re f /C cs 150 0 0 scn 0 0 1 1 re f" [("C", P.OArr [P.OName "ICCBased", P.ORef 7])] [(7, P.OStream [("N", P.OInt 3), ("Range", P.OArr (map P.OInt [0, 200, -128, 127, -128, 127]))] (profile "Lab "))]),
    testCase "root ADR 0425 I4: an ICCBased Lab colour and a Lab colour are different colours" $
      recolor
        (spaces "/C cs 50 10 0 scn 0 0 1 1 re f /L cs 50 10 0 scn 0 0 1 1 re f" [("C", P.OArr [P.OName "ICCBased", P.ORef 7]), ("L", P.OArr [P.OName "Lab", P.ODict [("WhitePoint", P.OArr [P.OReal "0.9505", P.OInt 1, P.OReal "1.089"])]])] [(7, P.OStream [("N", P.OInt 3), ("Range", P.OArr (map P.OInt [0, 100, -128, 127, -128, 127]))] (profile "Lab "))])
        @?= Right Nothing
  ]

classTests :: [TestTree]
classTests =
  [ testCase "root ADR 0425 I5: a d1 glyph drawn with a gray fill takes the fill tone" $
      tinted
        "0 0.5 0.5 0 k"
        ( (page ".5 g BT /T3 1 Tf (a) Tj ET")
            { P.ipResources = P.ODict [("Font", P.ODict [("T3", P.ODict [("Subtype", P.OName "Type3"), ("CharProcs", P.ODict [("a", P.ORef 1)])])])],
              P.ipObjects = [(1, P.OStream [] "1 0 0 0 1 1 d1 0 0 1 1 re f")]
            }
        )
  ]

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

states :: ByteString -> [(T.Text, [(T.Text, P.ObjOf P.ObjNum)])] -> P.ImportedPage
states content named = (page content) {P.ipResources = P.ODict [("ExtGState", P.ODict [(name, P.ODict fields) | (name, fields) <- named])]}

spaces :: ByteString -> [(T.Text, P.ObjOf P.ObjNum)] -> [(P.ObjNum, P.ObjOf P.ObjNum)] -> P.ImportedPage
spaces content named objects = (page content) {P.ipResources = P.ODict [("ColorSpace", P.ODict named)], P.ipObjects = objects}

image :: [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> [(P.ObjNum, P.ObjOf P.ObjNum)] -> P.ImportedPage
image fields bytes objects = (page "/Im Do") {P.ipResources = P.ODict [("XObject", P.ODict [("Im", P.ORef 1)])], P.ipObjects = (1, P.OStream fields bytes) : objects}

cal :: T.Text -> ByteString -> P.ImportedPage
cal family content = spaces content [("C", P.OArr [P.OName family, P.ODict [("WhitePoint", P.OArr [P.OReal "0.9505", P.OInt 1, P.OReal "1.089"])]])] []

lab :: [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> P.ImportedPage
lab extra content = spaces content [("C", P.OArr [P.OName "Lab", P.ODict ([("WhitePoint", P.OArr [P.OReal "0.9505", P.OInt 1, P.OReal "1.089"])] <> extra)])] []

-- | An ICC profile header whose data colour space (bytes 16 to 19) is given.
profile :: ByteString -> ByteString
profile space = BS.replicate 16 0 <> space <> BS.replicate 108 0

grayImage :: Integer -> Integer -> [(T.Text, P.ObjOf P.ObjNum)]
grayImage width bits = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt width), ("Height", P.OInt 1), ("BitsPerComponent", P.OInt bits)]
