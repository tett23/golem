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

jpeg :: ByteString
jpeg =
  BS.concat
    [ BS.pack [0xFF, 0xD8],
      segment 0xE2 ("ICC_PROFILE\0" <> BS.pack [1, 1] <> "fake-icc"),
      segment 0xC0 (BS.pack [8, 0, 2, 0, 3, 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1]),
      BS.pack [0xFF, 0xDA, 0, 2, 0xFF, 0xD9]
    ]
  where
    segment m body = BS.pack [0xFF, m, fromIntegral ((BS.length body + 2) `shiftR` 8), fromIntegral (BS.length body + 2)] <> body

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
      testCase "content stream: glyph positions, colour, horizontal scaling" $ do
        let cs = contentStream (Map.fromList [(FontRef 7, 1)]) Map.empty [SetColor (Swatch 0 80 100 0), ScaledGlyphRun (FontRef 7) (10 * 65536) 985 [(2, 65536, -65536)]]
        cs @?= "0 0.8 1 0 k 0 0.8 1 0 K\nBT /F1 10 Tf 98.5 Tz\n1 0 0 1 1 -1 Tm <0002> Tj\nET\n",
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
