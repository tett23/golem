{- | Masks encoded with CCITTFaxDecode and CCITT images with masks in
imported PDF figures (root ADR 0425 I8): a mask is judged by its decoded
values with the rules of the other masks, and a CCITT image with a mask is
judged by its visible pixels.
-}
module PdfColorCcittSpec (pdfColorCcittTests) where

import CcittEncode (encodeCcitt)
import Data.Bits (testBit)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Golem.Pdf qualified as P
import Golem.Typeset.Ccitt (CcittParams (..), defaultCcittParams)
import Golem.Typeset.FigureColor (analyzeRaster)
import Golem.Typeset.PdfColor (recolorImportedPage)
import Test.Tasty
import Test.Tasty.HUnit

swatch :: (Int, Int, Int, Int)
swatch = (0, 100, 100, 0)

recolor :: P.ImportedPage -> Either T.Text (Maybe P.ImportedPage)
recolor = recolorImportedPage swatch (analyzeRaster swatch)

pdfColorCcittTests :: [TestTree]
pdfColorCcittTests =
  [ testCase "root ADR 0425 I8: every explicit mask of 1 to 3 by 1 to 3 judges a 2x2 and a 3x1 image alike encoded with CCITT G4 or not" $ do
      let cases =
            [ (w, h, mw, mh, bits, redAt)
            | (w, h) <- [(2, 2), (3, 1)],
              mw <- [1 .. 3],
              mh <- [1 .. 3],
              bits <- [0 .. 2 ^ (mw * mh) - 1 :: Int],
              redAt <- [0 .. w * h - 1]
            ]
          differs (w, h, mw, mh, bits, redAt) =
            let samples = [[testBit bits (q * mw + p) | p <- [0 .. mw - 1]] | q <- [0 .. mh - 1]]
                image = rgbPixels [if i == redAt then red else gray | i <- [0 .. w * h - 1]]
                plain = explicitMask mw mh [] (packed samples)
                encoded = explicitMask mw mh (g4 mw mh) (ccitt mw mh samples)
             in outcome (explicit w h image plain) /= outcome (explicit w h image encoded)
      -- four red positions in the 2x2 image and three in the 3x1 one
      length cases @?= 7 * sum [2 ^ (mw * mh) | mw <- [1 .. 3 :: Int], mh <- [1 .. 3 :: Int]]
      take 5 (filter differs cases) @?= [],
    testCase "root ADR 0425 I8: a 1-bit soft mask encoded with CCITT G4 of another size hides what its samples hide" $ do
      -- the left sample of a 2x1 mask is 0 and covers only pixel 0 of a 3x1 image wholly
      let mask = softMask 2 1 (g4 2 1) (ccitt 2 1 [[False, True]])
      _ <- tinted (masked 3 1 (rgbPixels [red, gray, gray]) mask)
      recolor (masked 3 1 (rgbPixels [gray, gray, red]) mask) @?= Right Nothing,
    testCase "root ADR 0425 I8: a CCITT G3 mask with EOLs and BlackIs1 decodes like the samples it encodes" $ do
      let samples = [[True, False], [False, False]]
          params = defaultCcittParams {ccittColumns = 2, ccittRows = 2, ccittEndOfLine = True, ccittBlackIs1 = True}
          encoded = explicitMask 2 2 [("Filter", P.OName "CCITTFaxDecode"), ("DecodeParms", P.ODict [("K", P.OInt 0), ("Columns", P.OInt 2), ("Rows", P.OInt 2), ("EndOfLine", P.OBool True), ("BlackIs1", P.OBool True)])] (encodeCcitt params samples)
          plain = explicitMask 2 2 [] (packed samples)
          image = rgbPixels [gray, red, gray, gray]
      outcome (explicit 2 2 image encoded) @?= outcome (explicit 2 2 image plain),
    testCase "root ADR 0425 I8: a CCITT image with an explicit mask is judged by its visible pixels" $ do
      p <- tinted (ccittImage 2 1 [[True, False]] [("Mask", P.ORef 2)] [(2, explicitMask 2 1 [] (packed [[False, True]]))])
      -- the converted image is DeviceCMYK and keeps the explicit mask
      case [fields | (key, P.OStream fields _) <- P.ipObjects p, key < 0] of
        [fields] -> do
          lookup "ColorSpace" fields @?= Just (P.OName "DeviceCMYK")
          lookup "Mask" fields @?= Just (P.ORef 2)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I8: a CCITT image whose explicit mask hides every pixel paints nothing" $
      recolor (ccittImage 2 1 [[True, False]] [("Mask", P.ORef 2)] [(2, explicitMask 2 1 [] (packed [[True, True]]))]) @?= Right Nothing,
    testCase "root ADR 0425 I8: a CCITT image with a soft mask of another size is recoloured" $ do
      _ <- tinted (ccittImage 2 2 [[True, False], [False, True]] [("SMask", P.ORef 2)] [(2, softMask 1 1 [] (BS.pack [0x80]))])
      pure (),
    testCase "root ADR 0425 I8: a CCITT image with a colour-key mask writes the new soft mask" $ do
      p <- tinted (ccittImage 2 1 [[True, False]] [("Mask", P.OArr [P.OInt 0, P.OInt 0])] [])
      case [fields | (key, P.OStream fields _) <- P.ipObjects p, key < 0, lookup "ColorSpace" fields == Just (P.OName "DeviceCMYK")] of
        [fields] -> assertBool "soft mask" (lookup "SMask" fields /= Nothing && lookup "Mask" fields == Nothing)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I8: a CCITT mask whose Columns is not its Width is G08113" $
      rejected (explicit 2 1 (rgbPixels [gray, gray]) (explicitMask 2 1 (g4 3 1) (ccitt 3 1 [[False, True, False]]))),
    testCase "root ADR 0425 I8: a CCITT mask with damaged data is G08113" $
      rejected (explicit 2 1 (rgbPixels [gray, gray]) (explicitMask 2 1 (g4 2 1) (BS.pack [0x02, 0xFF]))),
    testCase "root ADR 0425 I8: a CCITT mask with fewer rows than its Height is G08113" $
      rejected (explicit 2 2 (rgbPixels [gray, gray, gray, gray]) (explicitMask 2 2 (g4 2 1) (ccitt 2 1 [[False, True]])))
  ]

-- | The outcome of a recolouring without the objects kept from the source.
outcome :: P.ImportedPage -> Either T.Text (Maybe (ByteString, [(P.ObjNum, P.ObjOf P.ObjNum)]))
outcome p = fmap (\q -> (P.ipContent q, [(key, object) | (key, object) <- P.ipObjects q, key < 0])) <$> recolor p

-- | The parameters of a G4 mask and its samples, True for 1, encoded.
g4 :: Int -> Int -> [(T.Text, P.ObjOf P.ObjNum)]
g4 columns rows = [("Filter", P.OName "CCITTFaxDecode"), ("DecodeParms", P.ODict [("K", P.OInt (-1)), ("Columns", P.OInt (toInteger columns)), ("Rows", P.OInt (toInteger rows))])]

-- | Samples encoded with G4: a 0 sample is a black pixel, as BlackIs1 is false.
ccitt :: Int -> Int -> [[Bool]] -> ByteString
ccitt columns rows samples = encodeCcitt defaultCcittParams {ccittK = -1, ccittColumns = columns, ccittRows = rows} (map (map not) samples)

-- | Samples packed one bit each, rows padded to a byte.
packed :: [[Bool]] -> ByteString
packed = BS.concat . map row
  where
    row bits = BS.pack (map byte (chunks bits))
    chunks [] = []
    chunks xs = let (h, t) = splitAt 8 xs in take 8 (h <> repeat False) : chunks t
    byte = foldl (\acc b -> acc * 2 + (if b then 1 else 0)) 0

gray, red :: [Int]
gray = [128, 128, 128]
red = [255, 0, 0]

rgbPixels :: [[Int]] -> ByteString
rgbPixels = BS.pack . map fromIntegral . concat

tinted :: P.ImportedPage -> IO P.ImportedPage
tinted p = case recolor p of
  Right (Just q) -> pure q
  other -> assertFailure ("expected a recoloured page, got " <> show other)

rejected :: P.ImportedPage -> Assertion
rejected p = case recolor p of
  Left _ -> pure ()
  other -> assertFailure ("expected G08113, got " <> show other)

page :: P.ImportedPage
page = P.ImportedPage "source" 1 (0, 0, 30, 10) 0 (30, 10) (P.ODict [("XObject", P.ODict [("Im", P.ORef 1)])]) Nothing "/Im Do" [] [P.UseGray] 0

rgbImage :: Int -> Int -> [(T.Text, P.ObjOf P.ObjNum)]
rgbImage w h = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt (toInteger w)), ("Height", P.OInt (toInteger h)), ("BitsPerComponent", P.OInt 8), ("ColorSpace", P.OName "DeviceRGB")]

-- | A DeviceRGB image under the soft mask object 2.
masked :: Int -> Int -> ByteString -> P.ObjOf P.ObjNum -> P.ImportedPage
masked w h bytes mask = page {P.ipObjects = [(1, P.OStream (rgbImage w h <> [("SMask", P.ORef 2)]) bytes), (2, mask)]}

-- | A DeviceRGB image under the explicit mask object 2.
explicit :: Int -> Int -> ByteString -> P.ObjOf P.ObjNum -> P.ImportedPage
explicit w h bytes mask = page {P.ipObjects = [(1, P.OStream (rgbImage w h <> [("Mask", P.ORef 2)]) bytes), (2, mask)]}

softMask :: Int -> Int -> [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> P.ObjOf P.ObjNum
softMask w h extra = P.OStream ([("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt (toInteger w)), ("Height", P.OInt (toInteger h)), ("BitsPerComponent", P.OInt 1), ("ColorSpace", P.OName "DeviceGray")] <> extra)

explicitMask :: Int -> Int -> [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> P.ObjOf P.ObjNum
explicitMask w h extra = P.OStream ([("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt (toInteger w)), ("Height", P.OInt (toInteger h)), ("ImageMask", P.OBool True)] <> extra)

-- | A 1-bit DeviceGray image encoded with G4 (True for black) with masks.
ccittImage :: Int -> Int -> [[Bool]] -> [(T.Text, P.ObjOf P.ObjNum)] -> [(P.ObjNum, P.ObjOf P.ObjNum)] -> P.ImportedPage
ccittImage w h black extra objects =
  let fields = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt (toInteger w)), ("Height", P.OInt (toInteger h)), ("BitsPerComponent", P.OInt 1), ("ColorSpace", P.OName "DeviceGray")] <> g4 w h <> extra
   in page {P.ipObjects = (1, P.OStream fields (encodeCcitt defaultCcittParams {ccittK = -1, ccittColumns = w, ccittRows = h} black)) : objects}
