{- | Reading PNG and JPEG images and writing them as image XObjects
(golem-pdf ADR 0001, "画像"), and the font and content of a scaled glyph
run. The images are built here, a few pixels each, so that the expected
samples can be worked out by hand.
-}
module ImageSpec (tests, allocatedBy, zeros) where

import Codec.Compression.Zlib qualified as Z
import Control.Exception (SomeException, evaluate, try)
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Word (Word8)
import GHC.Stats (allocated_bytes, getRTSStats, getRTSStatsEnabled)
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf
import Test.Tasty
import Test.Tasty.HUnit

-- ------------------------------------------------------------------ building images

be32 :: Int -> ByteString
be32 n = BS.pack [fromIntegral (n `shiftR` s) | s <- [24, 16, 8, 0 :: Int]]

-- | A chunk with a zero CRC (the reader does not check it).
chunk :: ByteString -> ByteString -> ByteString
chunk name d = be32 (BS.length d) <> name <> d <> be32 0

pngSignature :: ByteString
pngSignature = BS.pack [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

-- | IHDR: width, height, bit depth, colour type, interlace.
ihdr :: Int -> Int -> Word8 -> Word8 -> Word8 -> ByteString
ihdr w h depth ctype interlace = chunk "IHDR" (be32 w <> be32 h <> BS.pack [depth, ctype, 0, 0, interlace])

idat :: [Word8] -> ByteString
idat raw = chunk "IDAT" (BL.toStrict (Z.compress (BL.fromStrict (BS.pack raw))))

png :: [ByteString] -> ByteString
png cs = BS.concat ([pngSignature] <> cs <> [chunk "IEND" ""])

-- | A 3×2 8-bit grey PNG; each row is its filter byte and three samples.
grey3x2 :: [Word8] -> [Word8] -> ByteString
grey3x2 row0 row1 = png [ihdr 3 2 8 0 0, idat (row0 <> row1)]

decoded :: ByteString -> Either String ByteString
decoded = fmap imgData . readImage

-- | A JPEG of markers only: SOI, the given segments, EOI.
jpegOf :: [(Word8, ByteString)] -> ByteString
jpegOf segs = BS.pack [0xFF, 0xD8] <> BS.concat [BS.pack [0xFF, m, fromIntegral ((BS.length b + 2) `shiftR` 8), fromIntegral (BS.length b + 2)] <> b | (m, b) <- segs] <> BS.pack [0xFF, 0xD9]

-- | SOF0 of a 1×1 image with the given number of components.
sof :: Int -> (Word8, ByteString)
sof n = (0xC0, BS.pack ([8, 0, 1, 0, 1, fromIntegral n] <> concat [[fromIntegral k, 0x11, 0] | k <- [1 .. n]]))

-- | The APP14 segment that Adobe writes (version 100, transform 2: YCCK).
adobe :: (Word8, ByteString)
adobe = (0xEE, "Adobe" <> BS.pack [0, 100, 0, 0, 0, 0, 2])

-- ------------------------------------------------------------------ writing

-- | A one-page document with no fonts and the image 1 drawn once.
withImage :: ImageData -> ByteString
withImage img = writePdf (document [Image (ImageRef 1) (Rect 0 0 65536 65536)]) {docImages = Map.fromList [(ImageRef 1, img)]}

document :: [Mark] -> Document
document marks =
  Document
    { docPages = [Page box box box marks],
      docFonts = Map.empty,
      docImages = Map.empty,
      docForms = Map.empty,
      docTitle = "t",
      docDate = (2026, 10, 16),
      docId = documentId "urn:uuid:11111111-2222-4333-8444-555555555555",
      docInstanceId = instanceId ["source"],
      docProducer = "Golem 0.0.0-test",
      docPdfX = Nothing
    }
  where
    box = Rect 0 0 (100 * 65536) (100 * 65536)

readOk :: ByteString -> IO ImageData
readOk = either assertFailure pure . readImage

contains :: ByteString -> ByteString -> Assertion
contains pdf needle = assertBool ("expected " <> show needle) (needle `BS.isInfixOf` pdf)

-- | The decompressed data of the stream of object n.
streamOf :: Int -> ByteString -> ByteString
streamOf n pdf =
  let obj = snd (BS.breakSubstring (BC.pack ("\n" <> show n <> " 0 obj\n")) pdf)
      len = maybe 0 fst (BC.readInt (BS.drop 8 (snd (BS.breakSubstring "/Length " obj))))
      body = BS.take len (BS.drop 7 (snd (BS.breakSubstring "stream\n" obj)))
   in BL.toStrict (Z.decompress (BL.fromStrict body))

font :: Font
font = Font "ABCDEF+Dummy" (TrueTypeProgram "not really a font") False [(1, 500)] [] 880 (-120) 700 80 (0, -120, 1000, 880) 0 [(1, "A")] ("Adobe", "Identity", 0)

-- ------------------------------------------------------------------ tests

filterTests :: TestTree
filterTests =
  testGroup
    "PNG scanline filters"
    [ testCase "None keeps the samples" $
        decoded (grey3x2 [0, 10, 20, 30] [0, 1, 2, 3]) @?= Right (BS.pack [10, 20, 30, 1, 2, 3]),
      testCase "Sub adds the sample to the left, modulo 256" $
        -- 200; 100 + 200 = 300 = 44 (mod 256); 1 + 44
        decoded (grey3x2 [1, 200, 100, 1] [0, 0, 0, 0]) @?= Right (BS.pack [200, 44, 45, 0, 0, 0]),
      testCase "Up adds the sample above" $
        decoded (grey3x2 [0, 10, 20, 30] [2, 1, 2, 3]) @?= Right (BS.pack [10, 20, 30, 11, 22, 33]),
      testCase "Up on the first row adds zero" $
        decoded (grey3x2 [2, 7, 8, 9] [0, 0, 0, 0]) @?= Right (BS.pack [7, 8, 9, 0, 0, 0]),
      testCase "Average adds the floor of the mean of left and above" $
        -- 4 + (0 + 10) / 2 = 9; 6 + (9 + 20) / 2 = 6 + 14 = 20; 8 + (20 + 30) / 2 = 33
        decoded (grey3x2 [0, 10, 20, 30] [3, 4, 6, 8]) @?= Right (BS.pack [10, 20, 30, 9, 20, 33]),
      testCase "Average does not overflow when left and above are large" $
        -- 0 + (0 + 250) / 2 = 125; 1 + (125 + 250) / 2 = 1 + 187 = 188; 0 + (188 + 250) / 2 = 219
        decoded (grey3x2 [0, 250, 250, 250] [3, 0, 1, 0]) @?= Right (BS.pack [250, 250, 250, 125, 188, 219]),
      testCase "Paeth predicts from whichever of left, above and upper left is nearest" $
        -- row 0 is 100 15 20. Row 1:
        -- x0: left 0, above 100, upper left 0 -> above (100); 166 + 100 = 10 (mod 256)
        -- x1: left 10, above 15, upper left 100; p = -75 -> left (10); 0 + 10 = 10
        -- x2: left 10, above 20, upper left 15; p = 15 -> upper left (15); 1 + 15 = 16
        decoded (grey3x2 [0, 100, 15, 20] [4, 166, 0, 1]) @?= Right (BS.pack [100, 15, 20, 10, 10, 16]),
      testCase "Paeth prefers above to upper left when they are equally near" $
        -- row 0 is 20 40 0. Row 1:
        -- x0: above (20) is nearest; 246 + 20 = 10 (mod 256)
        -- x1: left 10, above 40, upper left 20; p = 30, both 10 away -> above (40); 0 + 40 = 40
        -- x2: left 40, above 0, upper left 40; p = 0 -> above (0); 0 + 0 = 0
        decoded (grey3x2 [0, 20, 40, 0] [4, 246, 0, 0]) @?= Right (BS.pack [20, 40, 0, 10, 40, 0]),
      testCase "the filters of an RGB image work on whole pixels of three bytes" $
        -- a 2×1 RGB row with Sub: the second pixel adds the first, byte for byte
        decoded (png [ihdr 2 1 8 2 0, idat [1, 10, 20, 30, 1, 2, 3]]) @?= Right (BS.pack [10, 20, 30, 11, 22, 33])
    ]

pngTests :: TestTree
pngTests =
  testGroup
    "PNG colour types"
    [ testCase "a palette PNG keeps its indices and the PLTE entries" $ do
        img <- readOk (png [ihdr 3 1 8 3 0, chunk "PLTE" (BS.pack [255, 0, 0, 0, 0, 255]), idat [0, 1, 0, 1]])
        (imgColor img, imgData img, imgIcc img) @?= (CsIndexed (BS.pack [255, 0, 0, 0, 0, 255]), BS.pack [1, 0, 1], Nothing),
      testCase "a grey PNG with alpha splits the alpha into the soft mask" $ do
        img <- readOk (png [ihdr 2 1 8 4 0, idat [0, 10, 255, 20, 128]])
        (imgColor img, imgData img, imgAlpha img) @?= (CsGray, BS.pack [10, 20], Just (BS.pack [255, 128])),
      testCase "the iCCP profile is decompressed after its name and compression method" $ do
        let profile = "an ICC profile" :: ByteString
            iccp = chunk "iCCP" ("sRGB\0\0" <> BL.toStrict (Z.compress (BL.fromStrict profile)))
        img <- readOk (png [ihdr 1 1 8 2 0, iccp, idat [0, 1, 2, 3]])
        imgIcc img @?= Just profile,
      testCase "PDF: a palette PNG without a profile is Indexed over the sRGB profile" $ do
        img <- readOk (png [ihdr 3 1 8 3 0, chunk "PLTE" (BS.pack [255, 0, 0, 0, 0, 255]), idat [0, 1, 0, 1]])
        -- objects: catalog, pages, page, content, the image (5), its profile (6)
        let pdf = withImage img
        pdf `contains` "/ColorSpace [/Indexed [/ICCBased 6 0 R] 1 <ff00000000ff>]"
        pdf `contains` "6 0 obj\n<< /Filter /FlateDecode /Length",
      testCase "PDF: the samples of a palette PNG are the indices, Flate-compressed" $ do
        img <- readOk (png [ihdr 3 1 8 3 0, chunk "PLTE" (BS.pack [255, 0, 0, 0, 0, 255]), idat [0, 1, 0, 1]])
        streamOf 5 (withImage img) @?= BS.pack [1, 0, 1],
      testCase "PDF: a palette PNG with its own profile uses that profile" $ do
        let iccp = chunk "iCCP" ("p\0\0" <> BL.toStrict (Z.compress "own profile"))
        img <- readOk (png [ihdr 1 1 8 3 0, iccp, chunk "PLTE" (BS.pack [1, 2, 3]), idat [0, 0]])
        streamOf 6 (withImage img) @?= "own profile",
      testCase "PDF: a grey PNG without a profile is DeviceGray and gets no profile" $ do
        img <- readOk (png [ihdr 1 1 8 0 0, idat [0, 7]])
        let pdf = withImage img
        pdf `contains` "/ColorSpace /DeviceGray"
        assertBool "no ICCBased" (not ("/ICCBased" `BS.isInfixOf` pdf))
    ]

jpegTests :: TestTree
jpegTests =
  testGroup
    "JPEG colour"
    [ testCase "an Adobe CMYK JPEG is marked inverted" $ do
        img <- readOk (jpegOf [adobe, sof 4])
        (imgColor img, imgInvertedCmyk img) @?= (CsCmyk, True),
      testCase "a CMYK JPEG without the Adobe segment is not inverted" $ do
        img <- readOk (jpegOf [sof 4])
        (imgColor img, imgInvertedCmyk img) @?= (CsCmyk, False),
      testCase "an Adobe segment on an RGB JPEG does not invert it" $ do
        img <- readOk (jpegOf [adobe, sof 3])
        (imgColor img, imgInvertedCmyk img) @?= (CsRgb, False),
      testCase "a one-component JPEG is grey" $ do
        img <- readOk (jpegOf [sof 1])
        (imgColor img, imgWidth img, imgHeight img, imgBits img) @?= (CsGray, 1, 1, 8),
      testCase "PDF: an inverted CMYK JPEG has the Decode array 1 0 four times" $ do
        img <- readOk (jpegOf [adobe, sof 4])
        withImage img `contains` "/ColorSpace /DeviceCMYK /Decode [1 0 1 0 1 0 1 0] /Filter /DCTDecode",
      testCase "PDF: a CMYK JPEG that is not inverted has no Decode array" $ do
        img <- readOk (jpegOf [sof 4])
        withImage img `contains` "/ColorSpace /DeviceCMYK /Filter /DCTDecode"
    ]

rejectionTests :: TestTree
rejectionTests =
  testGroup
    "unsupported images are rejected"
    [ testCase "neither JPEG nor PNG" $
        decoded "GIF89a\1\0\1\0" @?= Left "JPEG と PNG 以外の画像は使えません",
      testCase "an interlaced PNG" $
        decoded (png [ihdr 1 1 8 0 1, idat [0, 0]]) @?= Left "インターレースの PNG は使えません",
      testCase "a PNG colour type that does not exist" $
        decoded (png [ihdr 1 1 8 5 0, idat [0, 0]]) @?= Left "PNG の色の種類が不正です",
      testCase "a palette PNG without PLTE" $
        decoded (png [ihdr 1 1 8 3 0, idat [0, 0]]) @?= Left "PNG のパレットがありません",
      testCase "a PNG without IHDR" $
        decoded (png [idat [0, 0]]) @?= Left "PNG の IHDR がありません",
      testCase "a PNG chunk cut short" $
        decoded (pngSignature <> be32 100 <> "IHDR" <> BS.replicate 20 0) @?= Left "PNG のチャンクが途中で切れています",
      testCase "a PNG with fewer rows than its height" $
        decoded (png [ihdr 1 2 8 0 0, idat [0, 0]]) @?= Left "PNG の画素のデータが足りません",
      testCase "a JPEG whose segment does not start with FF" $
        decoded (BS.pack [0xFF, 0xD8, 0x00, 0xC0, 0, 2, 0, 0]) @?= Left "JPEG のマーカーが壊れています",
      testCase "a JPEG without SOF" $
        decoded (jpegOf [adobe]) @?= Left "JPEG の SOF が見つかりません",
      testCase "a JPEG of two components" $
        decoded (jpegOf [sof 2]) @?= Left "JPEG の色の成分の数が不正です"
    ]

scaledRunTests :: TestTree
scaledRunTests =
  testGroup
    "scaled glyph runs in the PDF (golem-layout ADR 0005)"
    [ testCase "the font of a page with only a scaled run is a page resource and embedded" $ do
        let pdf = writePdf (document [ScaledGlyphRun (FontRef 7) (9 * 65536) 1015 [(1, 0, 0)]]) {docFonts = Map.fromList [(FontRef 7, font)]}
        pdf `contains` "/Resources << /Font << /F1 5 0 R >> >>"
        pdf `contains` "/BaseFont /ABCDEF+Dummy",
      testCase "the page content of a scaled run sets Tz in percent" $ do
        let pdf = writePdf (document [ScaledGlyphRun (FontRef 7) (9 * 65536) 1015 [(1, 65536, 2 * 65536)]]) {docFonts = Map.fromList [(FontRef 7, font)]}
        streamOf 4 pdf @?= "BT /F1 9 Tf 101.5 Tz\n1 0 0 1 1 2 Tm <0001> Tj\nET\n"
    ]

tests :: TestTree
tests = testGroup "images and scaled runs (golem-pdf ADR 0001)" [filterTests, pngTests, jpegTests, rejectionTests, hostileTests, scaledRunTests]

-- ------------------------------------------------------------------ hostile images

-- | The result of reading, fully evaluated; an exception is a failure.
total :: ByteString -> IO (Either String ByteString)
total b = do
  r <- try (evaluate (forceResult (readImage b)))
  case r of
    Left (e :: SomeException) -> assertFailure ("readImage threw: " <> show e)
    Right x -> pure x
  where
    forceResult = \case
      Left e -> length e `seq` Left e
      Right img -> BS.length (imgData img) `seq` maybe () (`seq` ()) (imgIcc img) `seq` Right (imgData img)

-- | A zlib stream of n zero bytes, made lazily.
zeros :: Int -> ByteString
zeros n = BL.toStrict (Z.compress (BL.replicate (fromIntegral n) 0))

-- | Bytes allocated by an action (GHC.Stats; the suite runs with -T).
allocatedBy :: IO a -> IO (a, Integer)
allocatedBy act = do
  enabled <- getRTSStatsEnabled
  if not enabled
    then assertFailure "the test suite needs +RTS -T"
    else do
      before <- allocated_bytes <$> getRTSStats
      x <- act
      after <- allocated_bytes <$> getRTSStats
      pure (x, toInteger (after - before))

hostileTests :: TestTree
hostileTests =
  testGroup
    "hostile images end, without exceptions and within limits (docs/adr ADR 0035)"
    [ localOption (mkTimeout 5000000)
        $ testCase "alpha with a bit depth under 8 is an error, not an endless list"
        $ total (png [ihdr 2 1 4 6 0, idat [0, 0, 0, 0, 0]]) >>= (@?= Left "PNG のビット深度が色の種類に合いません"),
      testCase "a bit depth the colour type does not allow is an error" $
        total (png [ihdr 1 1 16 3 0, chunk "PLTE" (BS.pack [1, 2, 3]), idat [0, 0, 0]]) >>= (@?= Left "PNG のビット深度が色の種類に合いません"),
      testCase "an IHDR shorter than 13 bytes is an error" $
        total (png [chunk "IHDR" (be32 1 <> be32 1 <> BS.pack [8]), idat [0, 0]]) >>= (@?= Left "PNG の IHDR が壊れています"),
      testCase "a width or height of 0 is an error" $
        total (png [ihdr 0 1 8 0 0, idat [0]]) >>= (@?= Left "PNG の IHDR が壊れています"),
      localOption (mkTimeout 5000000)
        $ testCase "a size that overflows Int is too large, at once"
        $ total (png [ihdr 0x7FFFFFFF 0x7FFFFFFF 16 6 0, idat [0, 0]]) >>= (@?= Left "PNG の画像が大きすぎます"),
      testCase "more than 512 MiB of samples is too large" $
        total (png [ihdr 30000 30000 16 6 0, idat [0, 0]]) >>= (@?= Left "PNG の画像が大きすぎます"),
      -- 32768 rows of a filter byte and 16383 samples: exactly 2^29 bytes (docs/adr ADR 0068)
      testCase "exactly 512 MiB of filtered samples is not too large (docs/adr ADR 0068)" $
        total (png [ihdr 16383 32768 8 0 0, idat [0, 0]]) >>= (@?= Left "PNG の画素のデータが足りません"),
      testCase "one row beyond 512 MiB of filtered samples is too large (docs/adr ADR 0068)" $
        total (png [ihdr 16383 32769 8 0 0, idat [0, 0]]) >>= (@?= Left "PNG の画像が大きすぎます"),
      testCase "an IDAT that is not zlib is an error" $
        total (png [ihdr 1 1 8 0 0, chunk "IDAT" "not zlib at all"]) >>= (@?= Left "PNG の画素のデータを展開できません"),
      testCase "an IDAT that inflates to 64 MiB is read only as far as the image needs" $ do
        let bomb = png [ihdr 1 1 8 0 0, chunk "IDAT" (zeros (64 * 1024 * 1024))]
        _ <- evaluate (BS.length bomb)
        (r, bytes) <- allocatedBy (total bomb)
        r @?= Right (BS.pack [0])
        assertBool ("allocated " <> show bytes) (bytes < 16 * 1024 * 1024),
      testCase "an ICC profile that inflates beyond 32 MiB is an error" $ do
        let iccp = chunk "iCCP" ("p\0\0" <> zeros (64 * 1024 * 1024))
        total (png [ihdr 1 1 8 0 0, iccp, idat [0, 0]]) >>= (@?= Left "PNG の ICC プロファイルが大きすぎます"),
      testCase "an ICC profile that inflates to exactly 32 MiB is read (docs/adr ADR 0068)" $ do
        let iccp = chunk "iCCP" ("p\0\0" <> zeros (32 * 1024 * 1024))
        total (png [ihdr 1 1 8 0 0, iccp, idat [0, 0]]) >>= (@?= Right (BS.pack [0])),
      testCase "an ICC profile that inflates to 32 MiB and one byte is an error (docs/adr ADR 0068)" $ do
        let iccp = chunk "iCCP" ("p\0\0" <> zeros (32 * 1024 * 1024 + 1))
        total (png [ihdr 1 1 8 0 0, iccp, idat [0, 0]]) >>= (@?= Left "PNG の ICC プロファイルが大きすぎます"),
      testCase "an ICC profile that is not zlib is an error" $
        total (png [ihdr 1 1 8 0 0, chunk "iCCP" "p\0\0garbage", idat [0, 0]]) >>= (@?= Left "PNG の ICC プロファイルを展開できません"),
      testCase "a JPEG SOF shorter than 6 bytes is an error" $
        total (jpegOf [(0xC0, BS.pack [8, 0, 1])]) >>= (@?= Left "JPEG の SOF が壊れています"),
      testCase "a JPEG APP2 ICC piece shorter than 14 bytes is left out" $ do
        r <- try (evaluate (fmap imgIcc (readImage (jpegOf [(0xE2, "ICC_PROFILE\0"), sof 3]))))
        case r of
          Left (e :: SomeException) -> assertFailure ("readImage threw: " <> show e)
          Right x -> x @?= Right Nothing
    ]
