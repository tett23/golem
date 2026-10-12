module Main (main) where

import Codec.Compression.Zlib qualified as Z
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit hiding (assert)
import Test.Tasty.Hedgehog (testProperty)

main :: IO ()
main = defaultMain tests

hex :: ByteString -> String
hex = concatMap (\w -> [digits !! fromIntegral (w `div` 16), digits !! fromIntegral (w `mod` 16)]) . BS.unpack
  where
    digits = "0123456789abcdef"

page :: [Mark] -> Page
page = Page box box box
  where
    box = Rect 0 0 (595 * 65536) (842 * 65536)

font :: Font
font = Font "ABCDEF+Dummy" (TrueTypeProgram "not really a font") False [(1, 500), (2, 1000)] [] 880 (-120) 700 80 (0, -120, 1000, 880) 0 [(1, "A"), (2, "漢")]

{- | A real 2×3 baseline JPEG (test/fixtures/tiny.jpg, written by macOS sips)
with an APP2 ICC segment spliced in after SOI. qpdf --check decodes it.
-}
jpeg :: ByteString
jpeg = BS.take 2 tinyJpeg <> segment 0xE2 ("ICC_PROFILE\0" <> BS.pack [1, 1] <> "fake-icc") <> BS.drop 2 tinyJpeg
  where
    segment m body = BS.pack [0xFF, m, fromIntegral ((BS.length body + 2) `shiftR` 8), fromIntegral (BS.length body + 2)] <> body

tinyJpeg :: ByteString
tinyJpeg =
  BS.pack
    [ 0xFF,
      0xD8,
      0xFF,
      0xE0,
      0x00,
      0x10,
      0x4A,
      0x46,
      0x49,
      0x46,
      0x00,
      0x01,
      0x01,
      0x00,
      0x00,
      0x48,
      0x00,
      0x48,
      0x00,
      0x00,
      0xFF,
      0xE1,
      0x00,
      0x4C,
      0x45,
      0x78,
      0x69,
      0x66,
      0x00,
      0x00,
      0x4D,
      0x4D,
      0x00,
      0x2A,
      0x00,
      0x00,
      0x00,
      0x08,
      0x00,
      0x01,
      0x87,
      0x69,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x1A,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x03,
      0xA0,
      0x01,
      0x00,
      0x03,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
      0xA0,
      0x02,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x02,
      0xA0,
      0x03,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x03,
      0x00,
      0x00,
      0x00,
      0x00,
      0xFF,
      0xED,
      0x00,
      0x38,
      0x50,
      0x68,
      0x6F,
      0x74,
      0x6F,
      0x73,
      0x68,
      0x6F,
      0x70,
      0x20,
      0x33,
      0x2E,
      0x30,
      0x00,
      0x38,
      0x42,
      0x49,
      0x4D,
      0x04,
      0x04,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x38,
      0x42,
      0x49,
      0x4D,
      0x04,
      0x25,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x10,
      0xD4,
      0x1D,
      0x8C,
      0xD9,
      0x8F,
      0x00,
      0xB2,
      0x04,
      0xE9,
      0x80,
      0x09,
      0x98,
      0xEC,
      0xF8,
      0x42,
      0x7E,
      0xFF,
      0xC0,
      0x00,
      0x11,
      0x08,
      0x00,
      0x03,
      0x00,
      0x02,
      0x03,
      0x01,
      0x22,
      0x00,
      0x02,
      0x11,
      0x01,
      0x03,
      0x11,
      0x01,
      0xFF,
      0xC4,
      0x00,
      0x1F,
      0x00,
      0x00,
      0x01,
      0x05,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0A,
      0x0B,
      0xFF,
      0xC4,
      0x00,
      0xB5,
      0x10,
      0x00,
      0x02,
      0x01,
      0x03,
      0x03,
      0x02,
      0x04,
      0x03,
      0x05,
      0x05,
      0x04,
      0x04,
      0x00,
      0x00,
      0x01,
      0x7D,
      0x01,
      0x02,
      0x03,
      0x00,
      0x04,
      0x11,
      0x05,
      0x12,
      0x21,
      0x31,
      0x41,
      0x06,
      0x13,
      0x51,
      0x61,
      0x07,
      0x22,
      0x71,
      0x14,
      0x32,
      0x81,
      0x91,
      0xA1,
      0x08,
      0x23,
      0x42,
      0xB1,
      0xC1,
      0x15,
      0x52,
      0xD1,
      0xF0,
      0x24,
      0x33,
      0x62,
      0x72,
      0x82,
      0x09,
      0x0A,
      0x16,
      0x17,
      0x18,
      0x19,
      0x1A,
      0x25,
      0x26,
      0x27,
      0x28,
      0x29,
      0x2A,
      0x34,
      0x35,
      0x36,
      0x37,
      0x38,
      0x39,
      0x3A,
      0x43,
      0x44,
      0x45,
      0x46,
      0x47,
      0x48,
      0x49,
      0x4A,
      0x53,
      0x54,
      0x55,
      0x56,
      0x57,
      0x58,
      0x59,
      0x5A,
      0x63,
      0x64,
      0x65,
      0x66,
      0x67,
      0x68,
      0x69,
      0x6A,
      0x73,
      0x74,
      0x75,
      0x76,
      0x77,
      0x78,
      0x79,
      0x7A,
      0x83,
      0x84,
      0x85,
      0x86,
      0x87,
      0x88,
      0x89,
      0x8A,
      0x92,
      0x93,
      0x94,
      0x95,
      0x96,
      0x97,
      0x98,
      0x99,
      0x9A,
      0xA2,
      0xA3,
      0xA4,
      0xA5,
      0xA6,
      0xA7,
      0xA8,
      0xA9,
      0xAA,
      0xB2,
      0xB3,
      0xB4,
      0xB5,
      0xB6,
      0xB7,
      0xB8,
      0xB9,
      0xBA,
      0xC2,
      0xC3,
      0xC4,
      0xC5,
      0xC6,
      0xC7,
      0xC8,
      0xC9,
      0xCA,
      0xD2,
      0xD3,
      0xD4,
      0xD5,
      0xD6,
      0xD7,
      0xD8,
      0xD9,
      0xDA,
      0xE1,
      0xE2,
      0xE3,
      0xE4,
      0xE5,
      0xE6,
      0xE7,
      0xE8,
      0xE9,
      0xEA,
      0xF1,
      0xF2,
      0xF3,
      0xF4,
      0xF5,
      0xF6,
      0xF7,
      0xF8,
      0xF9,
      0xFA,
      0xFF,
      0xC4,
      0x00,
      0x1F,
      0x01,
      0x00,
      0x03,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0A,
      0x0B,
      0xFF,
      0xC4,
      0x00,
      0xB5,
      0x11,
      0x00,
      0x02,
      0x01,
      0x02,
      0x04,
      0x04,
      0x03,
      0x04,
      0x07,
      0x05,
      0x04,
      0x04,
      0x00,
      0x01,
      0x02,
      0x77,
      0x00,
      0x01,
      0x02,
      0x03,
      0x11,
      0x04,
      0x05,
      0x21,
      0x31,
      0x06,
      0x12,
      0x41,
      0x51,
      0x07,
      0x61,
      0x71,
      0x13,
      0x22,
      0x32,
      0x81,
      0x08,
      0x14,
      0x42,
      0x91,
      0xA1,
      0xB1,
      0xC1,
      0x09,
      0x23,
      0x33,
      0x52,
      0xF0,
      0x15,
      0x62,
      0x72,
      0xD1,
      0x0A,
      0x16,
      0x24,
      0x34,
      0xE1,
      0x25,
      0xF1,
      0x17,
      0x18,
      0x19,
      0x1A,
      0x26,
      0x27,
      0x28,
      0x29,
      0x2A,
      0x35,
      0x36,
      0x37,
      0x38,
      0x39,
      0x3A,
      0x43,
      0x44,
      0x45,
      0x46,
      0x47,
      0x48,
      0x49,
      0x4A,
      0x53,
      0x54,
      0x55,
      0x56,
      0x57,
      0x58,
      0x59,
      0x5A,
      0x63,
      0x64,
      0x65,
      0x66,
      0x67,
      0x68,
      0x69,
      0x6A,
      0x73,
      0x74,
      0x75,
      0x76,
      0x77,
      0x78,
      0x79,
      0x7A,
      0x82,
      0x83,
      0x84,
      0x85,
      0x86,
      0x87,
      0x88,
      0x89,
      0x8A,
      0x92,
      0x93,
      0x94,
      0x95,
      0x96,
      0x97,
      0x98,
      0x99,
      0x9A,
      0xA2,
      0xA3,
      0xA4,
      0xA5,
      0xA6,
      0xA7,
      0xA8,
      0xA9,
      0xAA,
      0xB2,
      0xB3,
      0xB4,
      0xB5,
      0xB6,
      0xB7,
      0xB8,
      0xB9,
      0xBA,
      0xC2,
      0xC3,
      0xC4,
      0xC5,
      0xC6,
      0xC7,
      0xC8,
      0xC9,
      0xCA,
      0xD2,
      0xD3,
      0xD4,
      0xD5,
      0xD6,
      0xD7,
      0xD8,
      0xD9,
      0xDA,
      0xE2,
      0xE3,
      0xE4,
      0xE5,
      0xE6,
      0xE7,
      0xE8,
      0xE9,
      0xEA,
      0xF2,
      0xF3,
      0xF4,
      0xF5,
      0xF6,
      0xF7,
      0xF8,
      0xF9,
      0xFA,
      0xFF,
      0xDB,
      0x00,
      0x43,
      0x00,
      0x02,
      0x02,
      0x02,
      0x02,
      0x02,
      0x02,
      0x03,
      0x02,
      0x02,
      0x03,
      0x05,
      0x03,
      0x03,
      0x03,
      0x05,
      0x06,
      0x05,
      0x05,
      0x05,
      0x05,
      0x06,
      0x08,
      0x06,
      0x06,
      0x06,
      0x06,
      0x06,
      0x08,
      0x0A,
      0x08,
      0x08,
      0x08,
      0x08,
      0x08,
      0x08,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0A,
      0x0C,
      0x0C,
      0x0C,
      0x0C,
      0x0C,
      0x0C,
      0x0E,
      0x0E,
      0x0E,
      0x0E,
      0x0E,
      0x0F,
      0x0F,
      0x0F,
      0x0F,
      0x0F,
      0x0F,
      0x0F,
      0x0F,
      0x0F,
      0x0F,
      0xFF,
      0xDB,
      0x00,
      0x43,
      0x01,
      0x02,
      0x02,
      0x02,
      0x04,
      0x04,
      0x04,
      0x07,
      0x04,
      0x04,
      0x07,
      0x10,
      0x0B,
      0x09,
      0x0B,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0x10,
      0xFF,
      0xDD,
      0x00,
      0x04,
      0x00,
      0x01,
      0xFF,
      0xDA,
      0x00,
      0x0C,
      0x03,
      0x01,
      0x00,
      0x02,
      0x11,
      0x03,
      0x11,
      0x00,
      0x3F,
      0x00,
      0xF9,
      0x1E,
      0x8A,
      0x28,
      0xAF,
      0xC7,
      0xCF,
      0xF5,
      0x40,
      0xFF,
      0xD9
    ]

-- | A 2×2 RGBA PNG with the Sub and Paeth filters.
png :: ByteString
png =
  BS.concat
    [ BS.pack [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      chunk "IHDR" (be32 2 <> be32 2 <> BS.pack [8, 6, 0, 0, 0]),
      chunk "IDAT" (BL.toStrict (Z.compress (BL.fromStrict raw))),
      chunk "IEND" ""
    ]
  where
    -- row 0: Sub filter; row 1: Paeth filter
    raw = BS.pack ([1, 10, 20, 30, 255, 5, 5, 5, 0] <> [4, 1, 1, 1, 0, 1, 1, 1, 0])
    be32 :: Int -> ByteString
    be32 n = BS.pack [fromIntegral (n `shiftR` s) | s <- [24, 16, 8, 0 :: Int]]
    chunk name d = be32 (BS.length d) <> name <> d <> be32 0

documentWith :: [Page] -> Document
documentWith ps =
  Document
    { docPages = ps,
      docFonts = Map.fromList [(FontRef 7, font)],
      docImages = Map.fromList [(ImageRef 1, either error id (readImage jpeg))],
      docTitle = "見本",
      docDate = (2026, 10, 11),
      docId = documentId "urn:uuid:11111111-2222-4333-8444-555555555555",
      docInstanceId = instanceId ["source", "manifest"],
      docPdfX = Nothing
    }

sample :: Document
sample =
  documentWith
    [ page [SetColor (Swatch 0 80 100 0), GlyphRun (FontRef 7) (10 * 65536) [(1, 72 * 65536, 700 * 65536), (2, 77 * 65536, 700 * 65536)], Rule (Rect 0 0 65536 32768)],
      page [Image (ImageRef 1) (Rect 0 0 (100 * 65536) (50 * 65536)), ScaledGlyphRun (FontRef 7) (9 * 65536) 1015 [(1, 0, 0)]]
    ]

countOf :: ByteString -> ByteString -> Int
countOf needle hay = case BS.breakSubstring needle hay of
  (_, rest) | BS.null rest -> 0
  (_, rest) -> 1 + countOf needle (BS.drop (BS.length needle) rest)

-- | Every xref entry points at "n 0 obj".
xrefConsistent :: ByteString -> Bool
xrefConsistent pdf =
  let (_, afterXref) = BS.breakSubstring "\nxref\n" pdf
      ls = drop 4 (BC.lines afterXref) -- "", "xref", "0 N", the free entry
      entries = takeWhile (BC.isSuffixOf " n ") ls
      offsets = [read (BC.unpack (BS.take 10 l)) :: Int | l <- entries]
      startxref = case drop 1 (dropWhile (/= "startxref") (BC.lines pdf)) of
        (l : _) -> read (BC.unpack l) :: Int
        [] -> -1
   in and [BC.pack (show n <> " 0 obj") `BS.isPrefixOf` BS.drop o pdf | (n, o) <- zip [1 :: Int ..] offsets]
        && "xref" `BS.isPrefixOf` BS.drop startxref pdf
        && not (null entries)

tests :: TestTree
tests =
  testGroup
    "golem-pdf (ADR 0001)"
    [ testCase "numbers: zero, negatives, rounding half to even, trailing zeros" $ do
        spToPt 0 @?= "0"
        spToPt 65536 @?= "1"
        spToPt (-32768) @?= "-0.5"
        spToPt 1 @?= "0"
        spToPt 7 @?= "0.0001"
        spToPt 2048 @?= "0.0312" -- 0.03125: the 4th decimal stays even
        spToPt 6144 @?= "0.0938" -- 0.09375: rounds up to even
        spToPt (10 * 65536 + 6554) @?= "10.1",
      testCase "SHA-256 test vectors" $ do
        hex (sha256 "") @?= "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        hex (sha256 "abc") @?= "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        hex (sha256 (BS.replicate 1000 0x61)) @?= "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
      testCase "the same document is written byte for byte the same" $
        writePdf sample @?= writePdf sample,
      testCase "structure: header, xref offsets, trailer ID, sorted keys" $ do
        let pdf = writePdf sample
        BS.take 9 pdf @?= "%PDF-1.6\n"
        assertBool "xref" (xrefConsistent pdf)
        assertBool "ID" ("/ID [<" `BS.isInfixOf` pdf)
        assertBool "dates from metadata" ("/CreationDate (D:20261011000000Z)" `BS.isInfixOf` pdf)
        assertBool "sorted keys" ("<< /Pages 2 0 R /Type /Catalog >>" `BS.isInfixOf` pdf),
      testCase "JPEG is embedded without decoding and keeps its ICC profile" $ do
        let pdf = writePdf sample
        assertBool "jpeg bytes" (jpeg `BS.isInfixOf` pdf)
        assertBool "DCT" ("/DCTDecode" `BS.isInfixOf` pdf)
        assertBool "ICC" ("/ICCBased" `BS.isInfixOf` pdf)
        fmap imgIcc (readImage jpeg) @?= Right (Just "fake-icc"),
      testCase "PNG filters are reversed and alpha becomes a soft mask" $ do
        img <- either assertFailure pure (readImage png)
        imgData img @?= BS.pack [10, 20, 30, 15, 25, 35, 11, 21, 31, 16, 26, 36]
        imgAlpha img @?= Just (BS.pack [255, 255, 255, 255]),
      testCase "an RGB image without a profile gets the sRGB profile" $ do
        let p = srgbProfile
            be32 i = foldl (\acc b -> acc * 256 + fromIntegral b) (0 :: Int) (BS.unpack (BS.take 4 (BS.drop i p)))
        be32 0 @?= BS.length p
        BS.take 4 (BS.drop 36 p) @?= "acsp"
        BS.take 4 (BS.drop 12 p) @?= "mntr"
        be32 128 @?= 10
        -- every tag lies inside the profile
        assertBool "tags" (and [be32 (132 + 12 * k + 4) + be32 (132 + 12 * k + 8) <= BS.length p | k <- [0 .. 9]])
        img <- either assertFailure pure (readImage png)
        let pdf = writePdf (documentWith [page [Image (ImageRef 2) (Rect 0 0 65536 65536)]]) {docImages = Map.fromList [(ImageRef 2, img)]}
        assertBool "ICCBased" ("/ICCBased" `BS.isInfixOf` pdf)
        assertBool "N 3" ("/N 3" `BS.isInfixOf` pdf),
      testCase "an RGB image without a profile gets its own sRGB object; Info stays the Info" $ do
        img <- either assertFailure pure (readImage tinyJpeg)
        imgIcc img @?= Nothing
        let pdf = writePdf (documentWith [page [Image (ImageRef 2) (Rect 0 0 65536 65536)]]) {docImages = Map.fromList [(ImageRef 2, img)]}
            objectAt n = snd (BS.breakSubstring (BC.pack ("\n" <> show n <> " 0 obj\n")) pdf)
            refAfter key = case BC.readInt (BS.drop (BS.length key) (snd (BS.breakSubstring key pdf))) of
              Just (n, _) -> n
              Nothing -> -1
            icc = refAfter "/ICCBased "
            info = refAfter "/Info "
        assertBool "xref" (xrefConsistent pdf)
        assertBool ("ICCBased points at a profile stream, object " <> show icc) ("/N 3" `BS.isInfixOf` BS.take 200 (objectAt icc))
        assertBool ("Info points at the Info dictionary, object " <> show info) ("/CreationDate" `BS.isInfixOf` BS.take 300 (objectAt info)),
      testCase "content stream: glyph positions, colour, horizontal scaling" $ do
        let cs = contentStream (Map.fromList [(FontRef 7, 1)]) Map.empty [SetColor (Swatch 0 80 100 0), ScaledGlyphRun (FontRef 7) (10 * 65536) 985 [(2, 65536, -65536)]]
        cs @?= "0 0.8 1 0 k 0 0.8 1 0 K\nBT /F1 10 Tf 98.5 Tz\n1 0 0 1 1 -1 Tm <0002> Tj\nET\n",
      testGroup
        "styled glyph runs and saved state (golem-driver ADR 0004)"
        [ testCase "a slanted, emboldened run sets its text matrix and stroke inside q and Q" $ do
            let cs = contentStream (Map.fromList [(FontRef 7, 1)]) Map.empty [StyledGlyphRun (RunStyle 1000 False (1 / 5) (65536 `div` 4)) (FontRef 7) (10 * 65536) [(2, 65536, -65536)]]
            assertBool (show cs) ("q BT /F1 10 Tf 2 Tr 0.25 w" `BS.isInfixOf` cs)
            assertBool (show cs) ("1 0 0.2 1 1 -1 Tm <0002> Tj" `BS.isInfixOf` cs)
            assertBool (show cs) ("ET Q" `BS.isInfixOf` cs)
            assertBool "no scaling" (not ("Tz" `BS.isInfixOf` cs)),
          testCase "a turned run is slanted before it is turned" $ do
            let cs = contentStream (Map.fromList [(FontRef 7, 1)]) Map.empty [StyledGlyphRun (RunStyle 1000 True (1 / 5) 0) (FontRef 7) (10 * 65536) [(2, 65536, -65536)]]
            assertBool (show cs) ("0 -1 1 -0.2 1 -1 Tm <0002> Tj" `BS.isInfixOf` cs)
            assertBool "no stroke" (not ("Tr" `BS.isInfixOf` cs)),
          testCase "horizontal scaling is written only when it is not 1000" $ do
            let run sc = contentStream (Map.fromList [(FontRef 7, 1)]) Map.empty [StyledGlyphRun (RunStyle sc False (1 / 5) 0) (FontRef 7) (10 * 65536) [(2, 0, 0)]]
            assertBool "Tz" ("105 Tz" `BS.isInfixOf` run 1050)
            assertBool "no Tz" (not ("Tz" `BS.isInfixOf` run 1000)),
          testCase "saved marks restore the colour" $ do
            let cs = contentStream (Map.fromList [(FontRef 7, 1)]) Map.empty [Saved [SetColor (Swatch 0 80 100 0), GlyphRun (FontRef 7) (10 * 65536) [(2, 0, 0)]]]
            BS.take 2 cs @?= "q\n"
            assertBool (show cs) ("Q\n" `BS.isSuffixOf` cs)
            assertBool "fill" ("0 0.8 1 0 k" `BS.isInfixOf` cs)
            assertBool "stroke" ("0 0.8 1 0 K" `BS.isInfixOf` cs),
          testCase "fonts inside saved marks and styled runs are page resources" $ do
            let doc =
                  (documentWith [page [Saved [GlyphRun (FontRef 7) 65536 [(1, 0, 0)]], StyledGlyphRun (RunStyle 1000 False (1 / 5) 0) (FontRef 8) 65536 [(2, 0, 0)]]])
                    { docFonts = Map.fromList [(FontRef 7, font), (FontRef 8, font)]
                    }
                pdf = writePdf doc
            assertBool "F1" ("/F1 " `BS.isInfixOf` pdf)
            assertBool "F2" ("/F2 " `BS.isInfixOf` pdf)
            countOf "/Type /FontDescriptor" pdf @?= 2
        ],
      testProperty "any page content is written deterministically with consistent xref" $ property $ do
        marks <- forAll (Gen.list (Range.linear 0 20) mark)
        let pdf = writePdf (documentWith [page marks])
        pdf === writePdf (documentWith [page marks])
        assert (xrefConsistent pdf),
      testCase "PDF/X-4: output intent, XMP version, Trapped, boxes, embedded fonts, nothing forbidden" $ do
        let px = PdfX "fake-japan-color-profile" "JC200103" ["山田 太郎"]
            pdf = writePdf sample {docPdfX = Just px}
        BS.take 9 pdf @?= "%PDF-1.6\n"
        assertBool "output intent" ("/S /GTS_PDFX" `BS.isInfixOf` pdf && "/DestOutputProfile" `BS.isInfixOf` pdf)
        assertBool "condition" ("/OutputConditionIdentifier (JC200103)" `BS.isInfixOf` pdf)
        assertBool "xmp version" ("<pdfxid:GTS_PDFXVersion>PDF/X-4</pdfxid:GTS_PDFXVersion>" `BS.isInfixOf` pdf)
        assertBool "trapped" ("/Trapped /False" `BS.isInfixOf` pdf && "<pdf:Trapped>False</pdf:Trapped>" `BS.isInfixOf` pdf)
        countOf "/TrimBox" pdf @?= length (docPages sample)
        -- every font descriptor points at an embedded font program
        countOf "/FontFile2 " pdf + countOf "/FontFile3 " pdf @?= countOf "/Type /FontDescriptor" pdf
        assertBool "no forbidden entries" (not (any (`BS.isInfixOf` pdf) ["/Encrypt", "/JavaScript", "/JS ", "/URI", "/Launch", "/GoToR"]))
        assertBool "xref" (xrefConsistent pdf)
        checkPdfX [(pageMediaBox p, pageTrimBox p, pageBleedBox p) | p <- docPages sample] @?= []
        checkPdfX [(Rect 0 0 10 10, Rect 0 0 10 10, Rect (-1) 0 10 10)] @?= [1],
      goldenVsString "XMP packet" "test/golden/xmp.xml" $
        pure (BL.fromStrict (xmpPacket (PdfX "" "JC200103" ["山田 太郎"]) "見本 & <題>" (2026, 10, 11) (documentId "urn:uuid:11111111-2222-4333-8444-555555555555") (instanceId ["a"]))),
      testCase "qpdf --check accepts the output (when qpdf is installed)" $ do
        qpdf <- findExecutable "qpdf"
        case qpdf of
          Nothing -> pure ()
          Just exe -> withSystemTempDirectory "golem-pdf" $ \dir -> do
            let path = dir </> "sample.pdf"
            BS.writeFile path (writePdf sample)
            (code, out, err) <- readProcessWithExitCode exe ["--check", path] ""
            assertEqual (out <> err) ExitSuccess code
    ]
  where
    sp = Gen.integral (Range.linearFrom 0 (-1000000) 100000000)
    mark =
      Gen.choice
        [ GlyphRun (FontRef 7) <$> sp <*> Gen.list (Range.linear 0 5) ((,,) <$> Gen.int (Range.linear 0 3) <*> sp <*> sp),
          Rule <$> (Rect <$> sp <*> sp <*> sp <*> sp),
          SetColor <$> (Swatch <$> pct <*> pct <*> pct <*> pct)
        ]
    pct = Gen.int (Range.linear 0 100)
