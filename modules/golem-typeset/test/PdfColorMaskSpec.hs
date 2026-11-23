{- | The masks of images in imported PDF figures (root ADR 0425): masks of
another size than the image, interpolation, and soft masks with a Matte.
-}
module PdfColorMaskSpec (pdfColorMaskTests) where

import Data.Bits (testBit)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Ratio ((%))
import Data.Text qualified as T
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (analyzeRaster)
import Golem.Typeset.PdfColor (maskCoverage, recolorImportedPage)
import Test.Tasty
import Test.Tasty.HUnit

swatch :: (Int, Int, Int, Int)
swatch = (0, 100, 100, 0)

recolor :: P.ImportedPage -> Either T.Text (Maybe P.ImportedPage)
recolor = recolorImportedPage swatch (analyzeRaster swatch)

pdfColorMaskTests :: [TestTree]
pdfColorMaskTests =
  [ testGroup "root ADR 0425 I8: the coverage of masks of another size" coverageTests,
    testGroup "root ADR 0425 I9: interpolation makes every pixel visible" interpolationTests,
    testGroup "root ADR 0425 I10: soft masks with a Matte" matteTests
  ]

coverageTests :: [TestTree]
coverageTests =
  [ testCase "root ADR 0425 I8: every w, h, mw, mh in 1 to 4 and every two-valued mask agree with the rational geometry" $ do
      let cases =
            [ ((w, h, mw, mh, bits), overlaps)
            | w <- [1 .. 4],
              h <- [1 .. 4],
              mw <- [1 .. 4],
              mh <- [1 .. 4],
              let overlaps = oracle w h mw mh,
              bits <- [0 .. 2 ^ (mw * mh) - 1 :: Int]
            ]
          visibleUnder bits overlaps = [any (testBit bits) cells | cells <- overlaps]
          wrong = [c | (c@(w, h, mw, mh, bits), overlaps) <- cases, maskCoverage w h mw mh (\p q -> testBit bits (q * mw + p)) /= visibleUnder bits overlaps]
      length cases @?= 16 * sum [2 ^ (mw * mh) | mw <- [1 .. 4 :: Int], mh <- [1 .. 4 :: Int]]
      take 5 wrong @?= [],
    testCase "root ADR 0425 I8: a 2x2 image under a visible 1x1 soft mask has four visible pixels" $
      recolor (masked 2 2 (rgbPixels [gray, gray, gray, red]) (softMask 1 1 8 [] [255])) @?= Right Nothing,
    testCase "root ADR 0425 I8: a 2x2 image under a 4x4 soft mask whose top-left 2x2 is 0 hides only pixel (0, 0)" $ do
      let mask = softMask 4 4 8 [] [if p < 2 && q < 2 then 0 else 255 | q <- [0 .. 3 :: Int], p <- [0 .. 3 :: Int]]
      tinted (masked 2 2 (rgbPixels [red, gray, gray, gray]) mask)
      recolor (masked 2 2 (rgbPixels [gray, red, gray, gray]) mask) @?= Right Nothing,
    testCase "root ADR 0425 I8: a 1x1 image under a 2x2 soft mask with only its top-left above 0 is visible" $
      tinted (masked 1 1 (rgbPixels [red]) (softMask 2 2 8 [] [1, 0, 0, 0])),
    testCase "root ADR 0425 I8: a 1x1 image under a 2x2 soft mask of all 0 is invisible" $
      recolor (masked 1 1 (rgbPixels [red]) (softMask 2 2 8 [] [0, 0, 0, 0])) @?= Right Nothing,
    testCase "root ADR 0425 I8: a 3x1 image under a 2x1 mask with only its left visible shows pixels 0 and 1" $ do
      tinted (masked 3 1 (rgbPixels [gray, gray, red]) (softMask 2 1 8 [] [255, 0]))
      recolor (masked 3 1 (rgbPixels [gray, red, gray]) (softMask 2 1 8 [] [255, 0])) @?= Right Nothing,
    testCase "root ADR 0425 I8: a reversed Decode on a soft mask of another size hides its maximum samples" $
      tinted (masked 3 1 (rgbPixels [gray, gray, red]) (softMask 2 1 8 [("Decode", P.OArr [P.OInt 1, P.OInt 0])] [0, 255])),
    testCase "root ADR 0425 I8: an explicit mask of another size with the default Decode paints its 0 samples" $ do
      tinted (explicit 1 1 (rgbPixels [red]) (explicitMask 2 1 [] [0x40]))
      recolor (explicit 1 1 (rgbPixels [red]) (explicitMask 2 1 [] [0xC0])) @?= Right Nothing,
    testCase "root ADR 0425 I8: an explicit mask of another size with a reversed Decode paints its 1 samples" $
      tinted (explicit 3 1 (rgbPixels [gray, gray, red]) (explicitMask 2 1 [("Decode", P.OArr [P.OInt 1, P.OInt 0])] [0x80])),
    testCase "root ADR 0425 I8: a soft mask of another size keeps its object and the image refers to it" $
      case recolor (masked 3 1 (rgbPixels [gray, gray, red]) (softMask 2 1 8 [] [255, 0])) of
        Right (Just result) -> do
          lookup 2 (P.ipObjects result) @?= Just (softMask 2 1 8 [] [255, 0])
          [lookup "SMask" fields | (key, P.OStream fields _) <- P.ipObjects result, key < 0, lookup "Subtype" fields == Just (P.OName "Image")] @?= [Just (P.ORef 2)]
        other -> assertFailure (show other)
  ]

interpolationTests :: [TestTree]
interpolationTests =
  [ testCase "root ADR 0425 I9: an image with only its own Interpolate true shows its hidden pixels" $ do
      let plain = masked 2 1 (rgbPixels [gray, red]) (softMask 2 1 8 [] [255, 0])
      tinted plain
      recolor plain {P.ipObjects = interpolated (P.ipObjects plain)} @?= Right Nothing,
    testCase "root ADR 0425 I9: a same-size explicit mask with Interpolate true makes every pixel visible" $
      recolor (explicit 2 1 (rgbPixels [gray, red]) (explicitMask 2 1 [("Interpolate", P.OBool True)] [0x40])) @?= Right Nothing,
    testCase "root ADR 0425 I9: a same-size explicit mask with Interpolate true over a gray image is recoloured" $
      tinted (explicit 2 1 (rgbPixels [gray, gray]) (explicitMask 2 1 [("Interpolate", P.OBool True)] [0x40])),
    testCase "root ADR 0425 I9: a same-size soft mask with Interpolate true makes every pixel visible" $
      recolor (masked 2 1 (rgbPixels [gray, red]) (softMask 2 1 8 [("Interpolate", P.OBool True)] [255, 0])) @?= Right Nothing,
    testCase "root ADR 0425 I9: a soft mask of another size with Interpolate true makes every pixel visible" $
      recolor (masked 3 1 (rgbPixels [gray, gray, red]) (softMask 2 1 8 [("Interpolate", P.OBool True)] [255, 0])) @?= Right Nothing
  ]
  where
    interpolated objects = [(key, if key == 1 then addInterpolate object else object) | (key, object) <- objects]
    addInterpolate (P.OStream fields bytes) = P.OStream (fields <> [("Interpolate", P.OBool True)]) bytes
    addInterpolate other = other

matteTests :: [TestTree]
matteTests =
  [ testCase "root ADR 0425 I10: a gray image under a same-size soft mask with Matte maps the image and the Matte" $
      case recolor (grayMatte [0, 128] [255, 128] [0]) of
        Right (Just result) -> do
          let images = [(fields, bytes) | (key, P.OStream fields bytes) <- P.ipObjects result, key < 0, lookup "Subtype" fields == Just (P.OName "Image"), lookup "ColorSpace" fields == Just (P.OName "DeviceCMYK")]
          map snd images @?= [BS.pack [0, 255, 255, 0, 0, 127, 127, 0]]
          case [lookup "SMask" fields | (fields, _) <- images] of
            [Just (P.ORef mask)] -> do
              assertBool "a new mask object" (mask < 0)
              case lookup mask (P.ipObjects result) of
                Just (P.OStream fields bytes) -> do
                  lookup "Matte" fields @?= Just (P.OArr [P.OInt 0, P.OInt 1, P.OInt 1, P.OInt 0])
                  bytes @?= BS.pack [255, 128]
                other -> assertFailure (show other)
            other -> assertFailure (show other)
          lookup 2 (P.ipObjects result) @?= lookup 2 (P.ipObjects (grayMatte [0, 128] [255, 128] [0]))
        other -> assertFailure (show other),
    testCase "root ADR 0425 I10: the colour with the Matte removed decides the class" $
      -- (0.5, 0.5, 0.5) at alpha 0.5 over the Matte (1, 0, 0) is (0, 1, 1).
      case recolor (rgbMatte [[128, 128, 128]] [128] [P.OInt 1, P.OInt 0, P.OInt 0]) of
        Right (Just result) -> do
          [bytes | (key, P.OStream fields bytes) <- P.ipObjects result, key < 0, lookup "ColorSpace" fields == Just (P.OName "DeviceCMYK")] @?= [BS.pack [0, 255, 255, 0]]
          [lookup "Matte" fields | (key, P.OStream fields _) <- P.ipObjects result, key < 0, lookup "ColorSpace" fields == Just (P.OName "DeviceGray")] @?= [Just (P.OArr [P.OInt 0, P.OInt 1, P.OInt 1, P.OInt 0])]
        other -> assertFailure (show other),
    testCase "root ADR 0425 I10: a pixel of alpha 0 under a Matte is invisible" $
      tinted (rgbMatte [[128, 128, 128], [255, 0, 0]] [255, 0] [P.OInt 0, P.OInt 0, P.OInt 0]),
    testCase "root ADR 0425 I10: removing the Matte clips the colour to its range" $
      -- 0.2 at alpha 0.5 over the Matte 1 is -0.6, which clips to black.
      case recolor (grayMatte [51, 255] [128, 255] [1]) of
        Right (Just result) -> [bytes | (key, P.OStream fields bytes) <- P.ipObjects result, key < 0, lookup "ColorSpace" fields == Just (P.OName "DeviceCMYK")] @?= [BS.pack [0, 204, 204, 0, 0, 0, 0, 0]]
        other -> assertFailure (show other),
    testCase "root ADR 0425 I10: a gray figure whose Matte is not a tone is G08113" $
      rejected (rgbMatte [[128, 128, 128]] [255] [P.OInt 1, P.OInt 0, P.OInt 0])
  ]

{- | For each pixel, row by row, the mask pixels (numbered q * mw + p) whose
square meets the pixel's square with an area above 0, computed with
rationals.
-}
oracle :: Int -> Int -> Int -> Int -> [[Int]]
oracle w h mw mh =
  [ [q * mw + p | q <- [0 .. mh - 1], p <- [0 .. mw - 1], overlap (cell i w) (cell p mw) * overlap (cell j h) (cell q mh) > 0]
  | j <- [0 .. h - 1],
    i <- [0 .. w - 1]
  ]
  where
    cell :: Int -> Int -> (Rational, Rational)
    cell k n = (toInteger k % toInteger n, toInteger (k + 1) % toInteger n)
    overlap (a, b) (c, d) = max 0 (min b d - max a c)

gray, red :: [Int]
gray = [128, 128, 128]
red = [255, 0, 0]

rgbPixels :: [[Int]] -> ByteString
rgbPixels = BS.pack . map fromIntegral . concat

tinted :: P.ImportedPage -> Assertion
tinted p = case recolor p of
  Right (Just _) -> pure ()
  other -> assertFailure ("expected a recoloured page, got " <> show other)

rejected :: P.ImportedPage -> Assertion
rejected p = case recolor p of
  Left _ -> pure ()
  other -> assertFailure ("expected G08113, got " <> show other)

page :: P.ImportedPage
page = P.ImportedPage "source" 1 (0, 0, 30, 10) 0 (30, 10) (P.ODict [("XObject", P.ODict [("Im", P.ORef 1)])]) Nothing "/Im Do" [] [P.UseGray] 0

imageFields :: T.Text -> Integer -> Integer -> [(T.Text, P.ObjOf P.ObjNum)]
imageFields space w h = [("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt w), ("Height", P.OInt h), ("BitsPerComponent", P.OInt 8), ("ColorSpace", P.OName space)]

-- | A DeviceRGB image under the soft mask object 2.
masked :: Integer -> Integer -> ByteString -> P.ObjOf P.ObjNum -> P.ImportedPage
masked w h bytes mask = page {P.ipObjects = [(1, P.OStream (imageFields "DeviceRGB" w h <> [("SMask", P.ORef 2)]) bytes), (2, mask)]}

-- | A DeviceRGB image under the explicit mask object 2.
explicit :: Integer -> Integer -> ByteString -> P.ObjOf P.ObjNum -> P.ImportedPage
explicit w h bytes mask = page {P.ipObjects = [(1, P.OStream (imageFields "DeviceRGB" w h <> [("Mask", P.ORef 2)]) bytes), (2, mask)]}

softMask :: Integer -> Integer -> Integer -> [(T.Text, P.ObjOf P.ObjNum)] -> [Int] -> P.ObjOf P.ObjNum
softMask w h bits extra samples = P.OStream ([("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt w), ("Height", P.OInt h), ("BitsPerComponent", P.OInt bits), ("ColorSpace", P.OName "DeviceGray")] <> extra) (BS.pack (map fromIntegral samples))

explicitMask :: Integer -> Integer -> [(T.Text, P.ObjOf P.ObjNum)] -> [Int] -> P.ObjOf P.ObjNum
explicitMask w h extra bytes = P.OStream ([("Type", P.OName "XObject"), ("Subtype", P.OName "Image"), ("Width", P.OInt w), ("Height", P.OInt h), ("ImageMask", P.OBool True)] <> extra) (BS.pack (map fromIntegral bytes))

-- | A one-row DeviceGray image under a same-size soft mask with a Matte.
grayMatte :: [Int] -> [Int] -> [Integer] -> P.ImportedPage
grayMatte samples alphas matte =
  let w = toInteger (length samples)
   in page {P.ipObjects = [(1, P.OStream (imageFields "DeviceGray" w 1 <> [("SMask", P.ORef 2)]) (BS.pack (map fromIntegral samples))), (2, softMask w 1 8 [("Matte", P.OArr (map P.OInt matte))] alphas)]}

-- | A one-row DeviceRGB image under a same-size soft mask with a Matte.
rgbMatte :: [[Int]] -> [Int] -> [P.ObjOf P.ObjNum] -> P.ImportedPage
rgbMatte pixels alphas matte =
  let w = toInteger (length pixels)
   in page {P.ipObjects = [(1, P.OStream (imageFields "DeviceRGB" w 1 <> [("SMask", P.ORef 2)]) (rgbPixels pixels)), (2, softMask w 1 8 [("Matte", P.OArr matte)] alphas)]}
