{- | Imported PDF constructs that root ADR 0403 recolors beyond plain device
images: stencil masks, Indexed and ICCBased spaces, general Decode arrays,
RunLength and CCITT images, inline images, and the transparency settings
under which per-object recoloring would differ from the per-pixel rule.
-}
module PdfColorRangeSpec (pdfColorRangeTests) where

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

pdfColorRangeTests :: [TestTree]
pdfColorRangeTests =
  [ testCase "root ADR 0403 I1: a PDF stencil mask paints with the recolored fill and keeps its samples" $ do
      let original = withImage "0 g /Im Do" stencilFields stencilBits
      p <- requireConverted original
      assertBool "fill recolored" ("0 1 1 0 k" `BS.isInfixOf` P.ipContent p)
      convertedImages p @?= []
      lookup 1 (P.ipObjects p) @?= lookup 1 (P.ipObjects original),
    testCase "root ADR 0403 I3: a stencil mask in a second colour keeps the original PDF" $
      recolor (withImage "0 g 0 0 1 1 re f 1 0 0 rg /Im Do" stencilFields stencilBits) @?= Right Nothing,
    testCase "root ADR 0403 I1: an Indexed PDF image is recolored as its palette colours" $ do
      let palette = P.OArr [P.OName "Indexed", P.OName "DeviceRGB", P.OInt 2, P.OStr (BS.pack [255, 255, 255, 128, 128, 128, 0, 0, 0])]
          indexed = withImage "/Im Do" (grayImage 3 8 <> [("ColorSpace", palette)]) (BS.pack [0, 1, 2])
          direct = withImage "/Im Do" (grayImage 3 8 <> [("ColorSpace", P.OName "DeviceRGB")]) (BS.pack [255, 255, 255, 128, 128, 128, 0, 0, 0])
      a <- requireConverted indexed
      b <- requireConverted direct
      map snd (convertedImages a) @?= map snd (convertedImages b),
    testCase "root ADR 0403 I3: an Indexed image with a coloured entry keeps the original PDF" $ do
      let palette = P.OArr [P.OName "Indexed", P.OName "DeviceRGB", P.OInt 1, P.OHex (BS.pack [255, 255, 255, 255, 0, 0])]
      recolor (withImage "0 g 0 0 1 1 re f /Im Do" (grayImage 2 1 <> [("ColorSpace", palette)]) (BS.pack [0x40])) @?= Right Nothing,
    testCase "root ADR 0403 I1: a partial PDF image Decode maps samples before recoloring" $ do
      let mapped = withImage "/Im Do" (grayImage 2 8 <> [("ColorSpace", P.OName "DeviceGray"), ("Decode", P.OArr [P.OReal "0.2", P.OReal "0.6"])]) (BS.pack [0, 255])
          direct = withImage "/Im Do" (grayImage 2 8 <> [("ColorSpace", P.OName "DeviceGray")]) (BS.pack [51, 153])
      a <- requireConverted mapped
      b <- requireConverted direct
      map snd (convertedImages a) @?= map snd (convertedImages b),
    testCase "root ADR 0403 I1: an ICCBased vector colour space paints as its device components" $ do
      p <- requireConverted (withSpaces "/CS0 cs 0.5 sc 0 0 1 1 re f" [("CS0", P.OArr [P.OName "ICCBased", P.ORef 7])] [(7, P.OStream [("N", P.OInt 1)] (iccHeader "GRAY"))])
      assertBool "half tint" ("0 0.5 0.5 0 k" `BS.isInfixOf` P.ipContent p),
    testCase "root ADR 0403 I3: a coloured ICCBased vector paint keeps the original PDF" $
      recolor (withSpaces "0 g 0 0 1 1 re f /CS0 cs 1 0 0 scn 0 0 1 1 re f" [("CS0", P.OArr [P.OName "ICCBased", P.ORef 7])] [(7, P.OStream [("N", P.OInt 3)] (iccHeader "RGB "))]) @?= Right Nothing,
    testCase "root ADR 0403 I1: an Indexed vector colour space paints its palette colour" $ do
      p <- requireConverted (withSpaces "/P cs 1 scn 0 0 1 1 re f" [("P", P.OArr [P.OName "Indexed", P.OName "DeviceGray", P.OInt 1, P.OStr (BS.pack [0, 51])])] [])
      assertBool "palette gray 0.2" ("0 0.8 0.8 0 k" `BS.isInfixOf` P.ipContent p),
    testCase "root ADR 0403 I1: a RunLength PDF image is decoded before recoloring" $ do
      let encoded = withImage "/Im Do" (grayImage 3 8 <> [("ColorSpace", P.OName "DeviceGray"), ("Filter", P.OName "RunLengthDecode")]) (BS.pack [254, 0, 128])
          direct = withImage "/Im Do" (grayImage 3 8 <> [("ColorSpace", P.OName "DeviceGray")]) (BS.pack [0, 0, 0])
      a <- requireConverted encoded
      b <- requireConverted direct
      map snd (convertedImages a) @?= map snd (convertedImages b),
    testCase "root ADR 0403 I1: a CCITT gray image keeps its encoded data under a CMYK palette" $ do
      let fields = grayImage 8 1 <> [("ColorSpace", P.OName "DeviceGray"), ("Filter", P.OName "CCITTFaxDecode"), ("DecodeParms", P.ODict [("Columns", P.OInt 8)])]
          black = P.OHex (BS.pack [0, 255, 255, 0, 0, 0, 0, 0])
          white = P.OHex (BS.pack [0, 0, 0, 0, 0, 255, 255, 0])
      a <- requireConverted (withImage "/Im Do" fields "ccitt")
      case convertedImages a of
        [(out, bytes)] -> do
          bytes @?= "ccitt"
          lookup "Filter" out @?= Just (P.OName "CCITTFaxDecode")
          lookup "ColorSpace" out @?= Just (P.OArr [P.OName "Indexed", P.OName "DeviceCMYK", P.OInt 1, black])
        other -> assertFailure (show other)
      b <- requireConverted (withImage "/Im Do" (fields <> [("Decode", P.OArr [P.OInt 1, P.OInt 0])]) "ccitt")
      case convertedImages b of
        [(out, _)] -> do
          lookup "ColorSpace" out @?= Just (P.OArr [P.OName "Indexed", P.OName "DeviceCMYK", P.OInt 1, white])
          lookup "Decode" out @?= Nothing
        other -> assertFailure (show other),
    testCase "root ADR 0403 I1: an inline PDF image is recolored as an image XObject" $ do
      p <- requireConverted (page "q BI /W 2 /H 1 /CS /G /BPC 8 ID \0\255 EI Q")
      assertBool "no inline image remains" (not ("BI" `BS.isInfixOf` P.ipContent p))
      map snd (convertedImages p) @?= [BS.pack [0, 255, 255, 0, 0, 0, 0, 0]],
    testCase "root ADR 0403 I1: an inline stencil mask paints with the recolored fill" $ do
      p <- requireConverted (page "0 g BI /W 8 /H 1 /IM true ID \85 EI")
      assertBool "fill recolored" ("0 1 1 0 k" `BS.isInfixOf` P.ipContent p)
      [bytes | (_, P.OStream fields bytes) <- P.ipObjects p, lookup "ImageMask" fields == Just (P.OBool True)] @?= [BS.pack [85]],
    testCase "root ADR 0403 I1: a non-Normal blend mode is not recolored per object" $
      isLeft (recolor ((page "/M gs 0 g 0 0 1 1 re f") {P.ipResources = P.ODict [("ExtGState", P.ODict [("M", P.ODict [("BM", P.OName "Multiply")])])]})) @?= True,
    testCase "root ADR 0403 I1: a transfer function is not recolored per object" $
      isLeft (recolor ((page "/T gs 0 g 0 0 1 1 re f") {P.ipResources = P.ODict [("ExtGState", P.ODict [("T", P.ODict [("TR", P.ODict [("FunctionType", P.OInt 2)])])])]})) @?= True,
    testCase "root ADR 0403 I1: a converted transparency group blends in DeviceCMYK" $ do
      let original =
            (page "/F Do")
              { P.ipResources = P.ODict [("XObject", P.ODict [("F", P.ORef 1)])],
                P.ipObjects = [(1, P.OStream [("Subtype", P.OName "Form"), ("Group", P.ODict [("S", P.OName "Transparency"), ("CS", P.OName "DeviceRGB")])] "0.5 g 0 0 1 1 re f")]
              }
      p <- requireConverted original
      [lookup "Group" fields | (key, P.OStream fields _) <- P.ipObjects p, key < 0] @?= [Just (P.ODict [("S", P.OName "Transparency"), ("CS", P.OName "DeviceCMYK")])]
  ]
  where
    isLeft = either (const True) (const False)

requireConverted :: P.ImportedPage -> IO P.ImportedPage
requireConverted p = case recolor p of
  Right (Just result) -> pure result
  other -> assertFailure (show other) >> pure p

convertedImages :: P.ImportedPage -> [([(T.Text, P.ObjOf P.ObjNum)], ByteString)]
convertedImages p = [(fields, bytes) | (key, P.OStream fields bytes) <- P.ipObjects p, key < 0, lookup "Subtype" fields == Just (P.OName "Image")]

page :: ByteString -> P.ImportedPage
page content = P.ImportedPage "source" 1 (0, 0, 30, 10) 0 (30, 10) (P.ODict []) Nothing content [] [P.UseGray] 0

withImage :: ByteString -> [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> P.ImportedPage
withImage content fields bytes = (page content) {P.ipResources = P.ODict [("XObject", P.ODict [("Im", P.ORef 1)])], P.ipObjects = [(1, P.OStream fields bytes)]}

withSpaces :: ByteString -> [(T.Text, P.ObjOf P.ObjNum)] -> [(P.ObjNum, P.ObjOf P.ObjNum)] -> P.ImportedPage
withSpaces content spaces objects = (page content) {P.ipResources = P.ODict [("ColorSpace", P.ODict spaces)], P.ipObjects = objects}

grayImage :: Integer -> Integer -> [(T.Text, P.ObjOf P.ObjNum)]
grayImage width bits = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt width), ("Height", P.OInt 1), ("BitsPerComponent", P.OInt bits)]

stencilFields :: [(T.Text, P.ObjOf P.ObjNum)]
stencilFields = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt 8), ("Height", P.OInt 1), ("ImageMask", P.OBool True)]

stencilBits :: ByteString
stencilBits = BS.pack [0x55]

-- | An ICC profile header whose data colour space is given (root ADR 0425).
iccHeader :: ByteString -> ByteString
iccHeader space = BS.replicate 16 0 <> space <> BS.replicate 108 0
