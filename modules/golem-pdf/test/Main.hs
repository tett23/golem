module Main (main) where

import Codec.Compression.Zlib qualified as Z
import Control.Monad (forM_)
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Char (toUpper)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import DrawingSpec qualified
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf
import Golem.Pdf.Writer (Mark (..))
import Golem.TestSupport.ExternalTool (needsTool)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import ImageSpec qualified
import ImportSpec qualified
import Numeric (readHex)
import SecuritySpec qualified
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
main = defaultMainReportingSkips (const tests)

hex :: ByteString -> String
hex = concatMap (\w -> [digits !! fromIntegral (w `div` 16), digits !! fromIntegral (w `mod` 16)]) . BS.unpack
  where
    digits = "0123456789abcdef"

page :: [Mark] -> Page
page = Page box box box
  where
    box = Rect 0 0 (595 * 65536) (842 * 65536)

font :: Font
font = Font "ABCDEF+Dummy" (TrueTypeProgram "not really a font") False [(1, 500), (2, 1000)] [] 880 (-120) 700 80 (0, -120, 1000, 880) 0 [(1, "A"), (2, "漢")] ("Adobe", "Identity", 0)

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
      docForms = Map.empty,
      docTitle = "見本",
      docDate = (2026, 10, 11),
      docId = documentId "urn:uuid:11111111-2222-4333-8444-555555555555",
      docInstanceId = instanceId ["source", "manifest"],
      docProducer = testProducer,
      docPdfX = Nothing
    }

-- | A fixed Producer, so that the goldens do not change with the version (ADR 0005).
testProducer :: Text
testProducer = "Golem 0.0.0-test"

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

-- | The text between two markers, after the first occurrence of the first.
between :: ByteString -> ByteString -> ByteString -> Maybe ByteString
between open close hay = case BS.breakSubstring open hay of
  (_, rest) | BS.null rest -> Nothing
  (_, rest) -> Just (fst (BS.breakSubstring close (BS.drop (BS.length open) rest)))

-- | The document information dictionary: the object the trailer's /Info points at.
infoDict :: ByteString -> ByteString
infoDict pdf =
  let ref = case BC.readInt (BS.drop 6 (snd (BS.breakSubstring "/Info " pdf))) of
        Just (n, _) -> n
        Nothing -> -1
   in fst (BS.breakSubstring "\nendobj" (snd (BS.breakSubstring (BC.pack ("\n" <> show ref <> " 0 obj\n")) pdf)))

-- | Decodes hex digits of UTF-16BE that start with the byte order mark.
utf16FromHex :: ByteString -> Text
utf16FromHex h =
  let pairs s = if null s then [] else take 2 s : pairs (drop 2 s)
      bytes = BS.pack [fromIntegral n | p <- pairs (BC.unpack h), (n, _) <- take 1 (readHex p :: [(Integer, String)])]
   in TE.decodeUtf16BE (BS.drop 2 bytes)

-- | 3mm, 10mm and 13mm in sp (ADR 0004).
mm3, mm10, mm13 :: Sp
mm3 = 557314
mm10 = 1857713
mm13 = 2415027

-- | A trimmed page size for the crop mark tests.
trimSize :: (Sp, Sp)
trimSize = (297 * 65536, 420 * 65536)

-- | Whether the interiors of two rectangles meet.
overlaps :: Rect -> Rect -> Bool
overlaps (Rect x y w h) (Rect x' y' w' h') = x < x' + w' && x' < x + w && y < y' + h' && y' < y + h

-- | Whether the first rectangle lies inside the second.
within :: Rect -> Rect -> Bool
within (Rect x y w h) (Rect ox oy ow oh) = x >= ox && y >= oy && x + w <= ox + ow && y + h <= oy + oh

boxesOf :: Sheet -> (Rect, Rect, Rect)
boxesOf s = (shMedia s, shTrim s, shBleed s)

-- | The ColorSpace resource of the registration colour (ADR 0007).
registrationResource :: ByteString
registrationResource = "/ColorSpace << /Reg [/Separation /All /DeviceCMYK << /C0 [0 0 0 0] /C1 [1 1 1 1] /Domain [0 1] /FunctionType 2 /N 1 >>] >>"

{- | Golem.Pdf.X4.verify on the objects before they are written (golem-cli
ADR 0006): each requirement of the PDF/X-4 test, broken alone, is one
problem.
-}
verifyTests :: [TestTree]
verifyTests =
  [ testCase "what Golem writes with an output intent has no problem" $ do
      verify (documentObjects x4Sample) @?= []
      verify (documentObjects (documentWith [framePage Nothing 0 (100 * 65536, 100 * 65536) [], framePage (Just Japanese) (3 * 65536) (100 * 65536, 100 * 65536) []]) {docPdfX = Just x4px}) @?= [],
    testCase "without an output intent the intent, the XMP and Trapped are missing" $ do
      let ps = verify (documentObjects sample)
      assertBool (show ps) (not (null ps)),
    one "no output intent" "出力インテント" (mapObjs (onDict isCatalog (dropKey "OutputIntents"))),
    one "no DestOutputProfile" "DestOutputProfile" (mapObjs (onDict isCatalog (mapKey "OutputIntents" (\case OArr [ODict kvs] -> OArr [ODict (filter ((/= "DestOutputProfile") . fst) kvs)]; o -> o)))),
    one "no GTS_PDFXVersion" "GTS_PDFXVersion" (mapObjs (onStream isMetadata (cut "   <pdfxid:GTS_PDFXVersion>PDF/X-4</pdfxid:GTS_PDFXVersion>\n"))),
    one "no Trapped" "Trapped" (mapObjs (onStream isMetadata (cut "   <pdf:Trapped>False</pdf:Trapped>\n"))),
    one "no TrimBox" "TrimBox" (mapFirst isPage (onDict (const True) (dropKey "TrimBox"))),
    one "a BleedBox outside the MediaBox" "ページのボックス" (mapFirst isPage (onDict (const True) (mapKey "BleedBox" (const (OArr (map OInt [-1, 0, 595, 842])))))),
    one "a font not embedded" "フォントの埋め込み" (mapObjs (onDict (hasType "FontDescriptor") (dropKey "FontFile2"))),
    one "RGB without an ICC profile" "ICC プロファイルのない RGB" (mapObjs (onStream isImage (mapStreamKey "ColorSpace" (const (OName "DeviceRGB"))))),
    one "encryption" "暗号化" (\o -> o {pdfTrailer = case pdfTrailer o of ODict kvs -> ODict (kvs <> [("Encrypt", ORef 1)]); t -> t}),
    one "JavaScript" "JavaScript と外部への参照" (mapObjs (onDict isCatalog (<> [("Names", ODict [("JavaScript", ORef 1)])]))),
    one "a version after 1.6" "PDF のバージョン" (\o -> o {pdfVersion = "1.7"}),
    testCase "the version problems say バージョン, not 版" $ do
      verify ((documentObjects x4Sample) {pdfVersion = "1.7"}) @?= [X4Problem "PDF のバージョン" "1.7（1.6 以下にします）"]
      map x4Detail (verify (mapObjs (onStream isMetadata (cut "   <pdfxid:GTS_PDFXVersion>PDF/X-4</pdfxid:GTS_PDFXVersion>\n")) (documentObjects x4Sample)))
        @?= ["XMP に PDF/X-4 のバージョンがありません"],
    testCase "versions up to 1.6 pass; 1.10, 2.0 and malformed ones do not" $
      [(v, map x4Requirement (verify ((documentObjects x4Sample) {pdfVersion = v}))) | v <- ["1.4", "1.6", "1.10", "2.0", "1", "1.6.0", "a.b", ""]]
        @?= [("1.4", []), ("1.6", []), ("1.10", ["PDF のバージョン"]), ("2.0", ["PDF のバージョン"]), ("1", ["PDF のバージョン"]), ("1.6.0", ["PDF のバージョン"]), ("a.b", ["PDF のバージョン"]), ("", ["PDF のバージョン"])],
    testCase "the details name the pages, the fonts and the names found" $ do
      let pages = verify (mapObjs (onDict isPage (dropKey "TrimBox")) (documentObjects x4Twopage))
      map x4Detail pages @?= ["1、2 ページ目に TrimBox がありません"]
      let names = verify (mapObjs (onDict isCatalog (<> [("Names", ODict [("JavaScript", ORef 1)]), ("AA", ODict [("URI", OName "Launch")])])) (documentObjects x4Sample))
      -- each name once; the order is not pinned here
      map (sort . T.splitOn "、" . T.dropEnd (T.length " があります") . x4Detail) names @?= [["JavaScript", "Launch", "URI"]]
      let unembedded = verify (mapObjs (onDict (hasType "FontDescriptor") (dropKey "FontFile2")) (documentObjects x4Sample))
      assertBool (show unembedded) (all ((== "フォントの埋め込み") . x4Requirement) unembedded && all ((" を埋め込んでいません" `T.isSuffixOf`) . x4Detail) unembedded),
    -- golem-pdf ADR 0012
    testCase "the forbidden names are in the order found" $
      map x4Detail (verify (mapObjs (onDict isCatalog (<> [("Names", ODict [("JavaScript", ORef 1)]), ("AA", ODict [("URI", OName "Launch")])])) (documentObjects x4Sample)))
        @?= ["JavaScript、URI、Launch があります"],
    testCase "a forbidden name found twice is named once, where it is first found" $
      map x4Detail (verify (mapObjs (onDict isCatalog (<> [("AA", ODict [("URI", ORef 1)]), ("Names", ODict [("JavaScript", ORef 1)]), ("OpenAction", ODict [("URI", ORef 1)])])) (documentObjects x4Sample)))
        @?= ["URI、JavaScript があります"],
    testCase "the names in the trailer come before the names in the objects" $
      let inTrailer o = o {pdfTrailer = case pdfTrailer o of ODict kvs -> ODict (kvs <> [("JS", ORef 1)]); t -> t}
       in map x4Detail (verify (inTrailer (mapObjs (onDict isCatalog (<> [("Names", ODict [("JavaScript", ORef 1)])])) (documentObjects x4Sample))))
            @?= ["JS、JavaScript があります"],
    testCase "an empty output profile is no profile" $
      let objs = documentObjects x4Sample
          empty = length (pdfObjects objs) + 1
          toEmpty = mapKey "OutputIntents" (\case OArr [ODict kvs] -> OArr [ODict (mapKey "DestOutputProfile" (const (ORef empty)) kvs)]; o -> o)
       in map x4Requirement (verify objs {pdfObjects = map (onDict isCatalog toEmpty) (pdfObjects objs) <> [OStream [] ""]})
            @?= ["DestOutputProfile"],
    testCase "Trapped may be True in the XMP and in the document information" $ do
      let trapped = OName "True"
          toTrue (kvs, b) = let (pre, post) = BS.breakSubstring "<pdf:Trapped>False" b in (kvs, pre <> "<pdf:Trapped>True" <> BS.drop (BS.length "<pdf:Trapped>False") post)
          infoTrue = map (\case ODict kvs | lookup "Trapped" kvs == Just (OName "False") -> ODict (mapKey "Trapped" (const trapped) kvs); o -> o)
          objs = mapObjs (onStream isMetadata toTrue) (documentObjects x4Sample)
      verify objs {pdfObjects = infoTrue (pdfObjects objs)} @?= []
      map x4Requirement (verify (mapObjs (onStream isMetadata (cut "   <pdf:Trapped>False</pdf:Trapped>\n")) (documentObjects x4Sample))) @?= ["Trapped"],
    testCase "a problem names its requirement" $ do
      let ps = verify (mapFirst isPage (onDict (const True) (dropKey "TrimBox")) (documentObjects x4Sample))
      map x4Requirement ps @?= ["TrimBox"]
  ]
  where
    x4px = PdfX "fake-japan-color-profile" "JC200103" [] []
    x4Sample = sample {docPdfX = Just x4px}
    x4Twopage = (documentWith [framePage Nothing 0 (100 * 65536, 100 * 65536) [], framePage Nothing 0 (100 * 65536, 100 * 65536) []]) {docPdfX = Just x4px}
    one name requirement f =
      testCase name $
        map x4Requirement (verify (f (documentObjects x4Sample))) @?= [requirement]
    mapObjs f o = o {pdfObjects = map f (pdfObjects o)}
    mapFirst p f o =
      let (before, rest) = break p (pdfObjects o)
       in o {pdfObjects = before <> take 1 (map f rest) <> drop 1 rest}
    hasType t = \case
      ODict kvs -> lookup "Type" kvs == Just (OName t)
      OStream kvs _ -> lookup "Type" kvs == Just (OName t)
      _ -> False
    isCatalog = hasType "Catalog"
    isPage = hasType "Page"
    isMetadata = hasType "Metadata"
    isImage = \case
      OStream kvs _ -> lookup "Subtype" kvs == Just (OName "Image")
      _ -> False
    onDict p f = \case
      d@(ODict kvs) | p d -> ODict (f kvs)
      o -> o
    onStream p f = \case
      s@(OStream kvs b) | p s -> uncurry OStream (f (kvs, b))
      o -> o
    dropKey k = filter ((/= k) . fst)
    mapKey k f = map (\(k', v) -> if k' == k then (k', f v) else (k', v))
    mapStreamKey k f (kvs, b) = (mapKey k f kvs, b)
    cut piece (kvs, b) = let (pre, post) = BS.breakSubstring piece b in (kvs, pre <> BS.drop (BS.length piece) post)

marksTests :: [TestTree]
marksTests =
  let (w, h) = trimSize
      b = mm3
   in [ testCase "no marks and no bleed: the three boxes are the trimmed page" $ do
          let s = sheet Nothing 0 (w, h)
          boxesOf s @?= (Rect 0 0 w h, Rect 0 0 w h, Rect 0 0 w h)
          shOrigin s @?= 0,
        testCase "bleed without marks: the MediaBox is the BleedBox" $ do
          let s = sheet Nothing b (w, h)
          boxesOf s @?= (Rect 0 0 (w + 2 * b) (h + 2 * b), Rect b b w h, Rect 0 0 (w + 2 * b) (h + 2 * b))
          shOrigin s @?= b,
        testCase "Japanese marks with 3mm of bleed" $ do
          let s = sheet (Just Japanese) b (w, h)
              m = b + mm13
          shOrigin s @?= m
          boxesOf s @?= (Rect 0 0 (w + 2 * m) (h + 2 * m), Rect m m w h, Rect (m - b) (m - b) (w + 2 * b) (h + 2 * b)),
        testCase "Western marks without bleed start 3mm out" $
          shOrigin (sheet (Just Western) 0 (w, h)) @?= mm3 + mm13,
        testCase "every sheet passes the page box checks" $
          checkPdfX [boxesOf (sheet ms bl (w, h)) | ms <- [Nothing, Just Japanese, Just Western], bl <- [0, b]] @?= [],
        testCase "24 Japanese and 16 Western lines, outside the BleedBox and inside the MediaBox" $ do
          length (markRules Japanese b (w, h)) @?= 24
          length (markRules Western b (w, h)) @?= 16
          length (markRules Western 0 (w, h)) @?= 16
          forM_ [(Japanese, b), (Western, b), (Western, 0)] $ \(st, bl) -> do
            let s = sheet (Just st) bl (w, h)
                m = shOrigin s
                Rect bx by bw bh = shBleed s
                Rect mx my mw mh = shMedia s
                bleedT = Rect (bx - m) (by - m) bw bh
                mediaT = Rect (mx - m) (my - m) mw mh
            forM_ (markRules st bl (w, h)) $ \r -> do
              assertBool ("in the bleed: " <> show (st, bl, r)) (not (overlaps r bleedT))
              assertBool ("outside the media: " <> show (st, bl, r)) (within r mediaT),
        testCase "the four Japanese lines of the lower left corner" $ do
          let o = b
              l = mm10
          take 4 (markRules Japanese b (w, h))
            @?= [ Rect (-(o + l)) (-8192) l 16384,
                  Rect (-(o + l)) (-b - 8192) l 16384,
                  Rect (-8192) (-(o + l)) 16384 l,
                  Rect (-b - 8192) (-(o + l)) 16384 l
                ],
        testCase "a filled disc is four cubic curves, the control points 0.5523 of the radius away (golem-driver ADR 0028)" $
          contentStream Map.empty Map.empty [Disc (10 * 65536) (10 * 65536) (2 * 65536)]
            @?= "12 10 m\n12 11.1046 11.1046 12 10 12 c\n8.8954 12 8 11.1046 8 10 c\n8 8.8954 8.8954 8 10 8 c\n11.1046 8 12 8.8954 12 10 c\nf\n",
        testCase "a filled closed curve is m, the curves, h and f (golem-driver ADR 0028)" $
          contentStream Map.empty Map.empty [CurveFill (0, 0) [((65536, 65536), (131072, 65536), (196608, 0)), ((131072, -65536), (65536, -65536), (0, 0))]]
            @?= "0 0 m\n1 1 2 1 3 0 c\n2 -1 1 -1 0 0 c\nh f\n",
        -- golem-driver ADR 0030
        testCase "ActualText wraps its marks in /Span with the replacement text, BDC to EMC" $ do
          let cs = contentStream (Map.fromList [(FontRef 7, 1)]) Map.empty [ActualText "ffi" [GlyphRun (FontRef 7) (10 * 65536) [(3, 0, 0)]]]
          cs @?= "/Span << /ActualText (ffi) >> BDC\nBT /F1 10 Tf\n1 0 0 1 0 0 Tm <0003> Tj\nET\nEMC\n",
        testCase "ActualText of a text that is not ASCII is UTF-16BE with the BOM" $ do
          let cs = contentStream (Map.fromList [(FontRef 7, 1)]) Map.empty [ActualText "\233" [GlyphRun (FontRef 7) (10 * 65536) [(3, 0, 0)]]]
          -- hexadecimal digits are case-insensitive in PDF; the writer writes them in lower case
          assertBool (show cs) ("/SPAN << /ACTUALTEXT <FEFF00E9> >> BDC\n" `BS.isPrefixOf` BC.map toUpper cs),
        testCase "a page with ActualText passes the PDF/X-4 checks, its font a resource" $ do
          let doc = (documentWith [page [ActualText "ffi" [GlyphRun (FontRef 7) (10 * 65536) [(1, 0, 0)]]]]) {docPdfX = Just (PdfX "fake-japan-color-profile" "JC200103" [] [])}
          verify (documentObjects doc) @?= []
          assertBool "the font is a resource" ("/Font <<" `BS.isInfixOf` writePdf doc),
        testCase "a translated mark moves the origin inside q and Q" $
          contentStream Map.empty Map.empty [Translated 65536 131072 [Rule (Rect 0 0 65536 65536)]] @?= "q 1 0 0 1 1 2 cm\n0 0 1 1 re f\nQ\n",
        testCase "a turned mark turns its frame into the rectangle inside q and Q (golem-driver ADR 0034)" $ do
          let r = Rect 65536 131072 (30 * 65536) (40 * 65536 + 32768)
              inner = [Rule (Rect 0 0 65536 65536)]
          contentStream Map.empty Map.empty [Turned TurnedRight r inner] @?= "q 0 -1 1 0 1 42.5 cm\n0 0 1 1 re f\nQ\n"
          contentStream Map.empty Map.empty [Turned TurnedLeft r inner] @?= "q 0 1 -1 0 31 2 cm\n0 0 1 1 re f\nQ\n",
        testCase "images and fonts inside turned marks are page resources" $ do
          let pdf = writePdf (documentWith [page [Turned TurnedRight (Rect 0 0 65536 65536) [Image (ImageRef 1) (Rect 0 0 65536 65536), GlyphRun (FontRef 7) 65536 [(1, 0, 0)]]]])
          assertBool "XObject" ("/XObject << /Im1 " `BS.isInfixOf` pdf)
          assertBool "Font" ("/Font << /F1 " `BS.isInfixOf` pdf),
        testCase "images and fonts inside translated marks are page resources" $ do
          let pdf = writePdf (documentWith [page [Translated 65536 65536 [Saved [Image (ImageRef 1) (Rect 0 0 65536 65536)], GlyphRun (FontRef 7) 65536 [(1, 0, 0)]]]])
          assertBool "XObject" ("/XObject << /Im1 " `BS.isInfixOf` pdf)
          assertBool "Font" ("/Font << /F1 " `BS.isInfixOf` pdf)
          assertBool "jpeg" (jpeg `BS.isInfixOf` pdf),
        testCase "a framed page without marks or bleed keeps its content" $ do
          let content = [Rule (Rect 0 0 65536 65536)]
          framePage Nothing 0 (w, h) content @?= Page (Rect 0 0 w h) (Rect 0 0 w h) (Rect 0 0 w h) content,
        testCase "a framed page with Japanese marks draws them in the registration colour over the moved content" $ do
          let content = [Rule (Rect 0 0 65536 65536)]
              m = b + mm13
          pageContent (framePage (Just Japanese) b (w, h) content)
            @?= [Translated m m (content <> [RegistrationRules (markRules Japanese b (w, h))])],
        testCase "a framed page without marks has no registration rules" $ do
          let content = [Rule (Rect 0 0 65536 65536)]
          forM_ [0, b] $ \bl ->
            registrationRects (pageContent (framePage Nothing bl (w, h) content)) @?= [],
        testCase "registration rules: q, the Separation All fill, the rectangles, Q" $
          contentStream Map.empty Map.empty [RegistrationRules [Rect 0 0 65536 65536]] @?= "q\n/Reg cs 1 scn\n0 0 1 1 re f\nQ\n",
        testCase "a page with registration rules has the Reg colour space resource" $ do
          let pdf = writePdf (documentWith [page [RegistrationRules [Rect 0 0 65536 65536]]])
          assertBool (show pdf) (registrationResource `BS.isInfixOf` pdf)
          assertBool "xref" (xrefConsistent pdf),
        testCase "a PDF without registration rules has no ColorSpace and no Separation" $ do
          let pdf = writePdf sample
          assertBool "ColorSpace" (not ("/ColorSpace <<" `BS.isInfixOf` pdf))
          assertBool "Separation" (not ("/Separation" `BS.isInfixOf` pdf)),
        testCase "registration rules inside Translated and Saved still add the resource" $ do
          let pdf = writePdf (documentWith [page [Translated 65536 65536 [Saved [RegistrationRules [Rect 0 0 65536 65536]]]]])
          assertBool (show pdf) (registrationResource `BS.isInfixOf` pdf),
        testCase "framed pages keep the registration colour out of the BleedBox" $
          forM_ [(st, bl) | st <- [Japanese, Western], bl <- [0, b]] $ \(st, bl) ->
            checkRegistration [framePage (Just st) bl (w, h) [Rule (Rect 0 0 65536 65536)]] @?= [],
        testCase "registration rules on the trimmed page are reported by page number" $ do
          let framed = framePage Nothing b (w, h) []
              inside = framed {pageContent = [Translated b b [RegistrationRules [Rect 0 0 65536 65536]]]}
          checkRegistration [framed, inside] @?= [2],
        testCase "registration rules inside Translated are found at their moved positions" $
          registrationRects [Rule (Rect 0 0 1 1), Translated 10 20 [Saved [RegistrationRules [Rect 1 2 3 4]], Translated 100 200 [RegistrationRules [Rect 0 0 5 5]]]]
            @?= [Rect 11 22 3 4, Rect 110 220 5 5],
        needsTool "qpdf" (findExecutable "qpdf") $ \qpdf ->
          testCase "qpdf --check accepts a page with Japanese marks" $ do
            exe <- qpdf
            withSystemTempDirectory "golem-pdf" $ \dir -> do
              let path = dir </> "marks.pdf"
                  framed = framePage (Just Japanese) b (w, h) [GlyphRun (FontRef 7) (10 * 65536) [(1, 72 * 65536, 700 * 65536)]]
              BS.writeFile path (writePdf (documentWith [framed]) {docPdfX = Just (PdfX "fake" "JC200103" [] [])})
              (code, out, err) <- readProcessWithExitCode exe ["--check", path] ""
              assertEqual (out <> err) ExitSuccess code
      ]

producerTests :: [TestTree]
producerTests =
  [ testCase "the information dictionary has the Producer without an output intent" $ do
      let info = infoDict (writePdf sample)
      assertBool (show info) ("/Producer (Golem 0.0.0-test)" `BS.isInfixOf` info),
    testCase "with an output intent, the information dictionary and XMP both have the Producer" $ do
      let pdf = writePdf sample {docPdfX = Just (PdfX "fake" "JC200103" [] [])}
      assertBool "Info" ("/Producer (Golem 0.0.0-test)" `BS.isInfixOf` infoDict pdf)
      assertBool "XMP" ("<pdf:Producer>Golem 0.0.0-test</pdf:Producer>" `BS.isInfixOf` pdf),
    testCase "a PDF text string is literal for printable ASCII, otherwise UTF-16BE with a byte order mark" $ do
      pdfTextString "Golem 0.1.0-rc1" @?= OStr "Golem 0.1.0-rc1"
      case pdfTextString "ゴーレム" of
        OHex b -> BS.take 2 b @?= BS.pack [0xFE, 0xFF]
        other -> assertFailure (show other),
    testCase "the Producer is escaped in XMP" $ do
      let x = xmpPacket (PdfX "" "JC200103" [] []) "t" "a<b&c" (2026, 10, 11) (documentId "x") (instanceId ["a"])
      assertBool (show x) ("<pdf:Producer>a&lt;b&amp;c</pdf:Producer>" `BS.isInfixOf` x),
    -- docs/adr ADR 0033
    testCase "contributors are a dc:contributor Bag in XMP, none without them" $ do
      let x = xmpPacket (PdfX "" "JC200103" ["著者"] ["編集 & 者", "装丁者"]) "t" "p" (2026, 10, 11) (documentId "x") (instanceId ["a"])
      assertBool (show x) (TE.encodeUtf8 "   <dc:contributor><rdf:Bag><rdf:li>編集 &amp; 者</rdf:li><rdf:li>装丁者</rdf:li></rdf:Bag></dc:contributor>\n" `BS.isInfixOf` x)
      let y = xmpPacket (PdfX "" "JC200103" ["著者"] []) "t" "p" (2026, 10, 11) (documentId "x") (instanceId ["a"])
      assertBool (show y) (not ("dc:contributor" `BS.isInfixOf` y)),
    testCase "the information dictionary and XMP agree" $ do
      let pdf = writePdf sample {docPdfX = Just (PdfX "fake" "JC200103" ["山田 太郎"] [])}
          info = infoDict pdf
          infoStr k = fromMaybe "" (between ("/" <> k <> " (") ")" info)
          xmp k = maybe "" TE.decodeUtf8 (between ("<" <> k <> ">") ("</" <> k <> ">") pdf)
          -- D:YYYYMMDDHHmmSSZ as YYYY-MM-DDTHH:mm:SSZ
          asXmpDate d =
            let part i n = take n (drop i d)
             in T.pack (part 0 4 <> "-" <> part 4 2 <> "-" <> part 6 2 <> "T" <> part 8 2 <> ":" <> part 10 2 <> ":" <> part 12 2 <> "Z")
          infoDate k = asXmpDate (drop 2 (BC.unpack (infoStr k)))
          title = utf16FromHex (fromMaybe "" (between "/Title <" ">" info))
          xmpTitle = maybe "" TE.decodeUtf8 (between "<rdf:li xml:lang=\"x-default\">" "</rdf:li>" pdf)
          trapped = BC.takeWhile (`notElem` (" >/" :: String)) (fromMaybe "" (between "/Trapped /" ">" info))
      title @?= "見本"
      title @?= xmpTitle
      infoDate "CreationDate" @?= xmp "xmp:CreateDate"
      infoDate "ModDate" @?= xmp "xmp:ModifyDate"
      TE.decodeUtf8 (infoStr "Producer") @?= xmp "pdf:Producer"
      xmp "pdf:Producer" @?= testProducer
      TE.decodeUtf8 trapped @?= xmp "pdf:Trapped"
      xmp "pdf:Trapped" @?= "False"
  ]

tests :: TestTree
tests =
  testGroup
    "golem-pdf (ADR 0001)"
    [ testGroup
        "showRationalDigits, the numbers of figure matrices (golem-pdf ADR 0008)"
        [ testCase (show n <> " digits of " <> show r <> " is " <> T.unpack t) $ showRationalDigits n r @?= t
        | (n, r, t) <-
            [ (6, -(1 / 3), "-0.333333"),
              (2, 1 / 8, "0.12"), -- 12.5 hundredths: half to the even 12
              (2, 3 / 8, "0.38"), -- 37.5 hundredths: half to the even 38
              (2, -(1 / 8), "-0.12"), -- half to even on the negative side too
              (2, -(1 / 1000), "0"), -- rounds to zero: no minus sign
              (10, 1 / 20, "0.05"),
              (0, 5 / 2, "2"),
              (3, 2, "2")
            ]
        ],
      testCase "numbers: zero, negatives, rounding half to even, trailing zeros" $ do
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
      testProperty "any page content is written with consistent xref" $ property $ do
        marks <- forAll (Gen.list (Range.linear 0 20) mark)
        assert (xrefConsistent (writePdf (documentWith [page marks]))),
      testCase "PDF/X-4: output intent, XMP version, Trapped, boxes, embedded fonts, nothing forbidden" $ do
        let px = PdfX "fake-japan-color-profile" "JC200103" ["山田 太郎"] []
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
        -- the same checks as golem preflight (golem-cli ADR 0006)
        verify (documentObjects sample {docPdfX = Just px}) @?= []
        checkPdfX [(pageMediaBox p, pageTrimBox p, pageBleedBox p) | p <- docPages sample] @?= []
        checkPdfX [(Rect 0 0 10 10, Rect 0 0 10 10, Rect (-1) 0 10 10)] @?= [1],
      testCase "checkPdfX: each edge of the TrimBox and the BleedBox, and boxes that meet" $ do
        let media = Rect 0 0 100 100
            ok = (media, Rect 10 10 80 80, Rect 5 5 90 90)
        checkPdfX [ok, (media, media, media)] @?= []
        -- the TrimBox past each edge of the BleedBox, then the BleedBox past each edge of the MediaBox
        checkPdfX
          [ ok,
            (media, Rect 4 10 80 80, Rect 5 5 90 90),
            (media, Rect 10 4 80 80, Rect 5 5 90 90),
            (media, Rect 10 10 86 80, Rect 5 5 90 90),
            (media, Rect 10 10 80 86, Rect 5 5 90 90),
            (media, Rect 10 10 80 80, Rect (-1) 5 90 90),
            (media, Rect 10 10 80 80, Rect 5 (-1) 90 90),
            (media, Rect 10 10 80 80, Rect 5 5 96 90),
            (media, Rect 10 10 80 80, Rect 5 5 90 96)
          ]
          @?= [2 .. 9],
      testCase "uuidText writes every byte as two hex digits in the 8-4-4-4-12 form" $
        uuidText (BS.pack [0 .. 15]) @?= "00010203-0405-0607-0809-0a0b0c0d0e0f",
      testGroup "X4.verify (golem-cli ADR 0006)" verifyTests,
      testGroup "crop marks and bleed (ADR 0004)" marksTests,
      testGroup "Producer (ADR 0005)" producerTests,
      ImageSpec.tests,
      ImportSpec.tests,
      SecuritySpec.tests,
      DrawingSpec.tests,
      testGroup
        "CIDSystemInfo (ADR 0006)"
        [ testCase "the CIDFont carries the ROS of the font" $ do
            let doc = sample {docFonts = Map.fromList [(FontRef 7, font {fontProgram = CffProgram "not really a font", fontCidSystemInfo = ("Adobe", "Japan1", 7)})]}
                pdf = writePdf doc
            assertBool "Japan1" ("/CIDSystemInfo << /Ordering (Japan1) /Registry (Adobe) /Supplement 7 >>" `BS.isInfixOf` pdf)
            assertBool "no Identity" (not ("/Ordering (Identity)" `BS.isInfixOf` pdf))
            assertBool "xref" (xrefConsistent pdf),
          testCase "Adobe-Identity-0 is written as before" $
            assertBool "Identity" ("/CIDSystemInfo << /Ordering (Identity) /Registry (Adobe) /Supplement 0 >>" `BS.isInfixOf` writePdf sample)
        ],
      goldenVsString "XMP packet" "test/golden/xmp.xml" $
        pure (BL.fromStrict (xmpPacket (PdfX "" "JC200103" ["山田 太郎"] []) "見本 & <題>" testProducer (2026, 10, 11) (documentId "urn:uuid:11111111-2222-4333-8444-555555555555") (instanceId ["a"]))),
      needsTool "qpdf" (findExecutable "qpdf") $ \qpdf ->
        testCase "qpdf --check accepts the output" $ do
          exe <- qpdf
          withSystemTempDirectory "golem-pdf" $ \dir -> do
            let path = dir </> "sample.pdf"
            BS.writeFile path (writePdf sample)
            (code, out, err) <- readProcessWithExitCode exe ["--check", path] ""
            assertEqual (out <> err) ExitSuccess code
    ]
  where
    sp = Gen.integral (Range.linearFrom 0 (-1000000) 100000000)
    -- translated marks nest other marks (ADR 0004)
    mark =
      Gen.recursive
        Gen.choice
        [ GlyphRun (FontRef 7) <$> sp <*> Gen.list (Range.linear 0 5) ((,,) <$> Gen.int (Range.linear 0 3) <*> sp <*> sp),
          Rule <$> (Rect <$> sp <*> sp <*> sp <*> sp),
          SetColor <$> (Swatch <$> pct <*> pct <*> pct <*> pct),
          RegistrationRules <$> Gen.list (Range.linear 0 3) (Rect <$> sp <*> sp <*> sp <*> sp)
        ]
        [Translated <$> sp <*> sp <*> Gen.list (Range.linear 0 3) mark]
    pct = Gen.int (Range.linear 0 100)
