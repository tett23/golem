{- | Reading a page of a PDF as a Form XObject (golem-pdf ADR 0008). The
PDFs are written by Golem itself or put together here as bytes.
-}
module ImportSpec (tests, minimalPdf, classicPdf) where

import Codec.Compression.Zlib qualified as Z
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Either (isRight)
import Data.Map.Strict qualified as Map
import Data.Word (Word8)
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf
import Golem.TestSupport.ExternalTool (needsTool)
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

-- ------------------------------------------------------------------ building PDFs

-- | An object of a PDF: its number and what is between @obj@ and @endobj@.
type RawObj = (Int, ByteString)

objBytes :: RawObj -> ByteString
objBytes (n, b) = BC.pack (show n) <> " 0 obj\n" <> b <> "\nendobj\n"

stream :: ByteString -> ByteString -> ByteString
stream dict body = "<< " <> dict <> " /Length " <> BC.pack (show (BS.length body)) <> " >>\nstream\n" <> body <> "\nendstream"

-- | The bodies laid after @prefix@, with their offsets.
layout :: ByteString -> [RawObj] -> (ByteString, [(Int, Int)])
layout prefix objs =
  let bodies = map objBytes objs
      offsets = scanl (+) (BS.length prefix) (map BS.length bodies)
   in (prefix <> BS.concat bodies, zip (map fst objs) offsets)

-- | A classic cross-reference section for the objects at their offsets.
xrefTable :: [(Int, Int)] -> ByteString
xrefTable offs =
  "xref\n"
    <> BS.concat
      [ BC.pack (show n) <> " 1\n" <> BC.pack (printf "%010d 00000 n \n" o)
      | (n, o) <- offs
      ]

-- | A PDF with a classic cross-reference table, and extra keys in the trailer.
classicPdf :: ByteString -> [RawObj] -> ByteString
classicPdf extra objs =
  let (body, offs) = layout "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n" objs
      size = maximum (map fst objs) + 1
   in body
        <> "xref\n0 1\n0000000000 65535 f \n"
        <> BS.drop 5 (xrefTable offs)
        <> "trailer\n<< /Size "
        <> BC.pack (show size)
        <> " /Root 1 0 R "
        <> extra
        <> " >>\nstartxref\n"
        <> BC.pack (show (BS.length body))
        <> "\n%%EOF\n"

-- | An incremental update of a classic PDF: the objects replaced or added.
updated :: ByteString -> [RawObj] -> ByteString
updated base objs =
  let prev = lastStartxref base
      (body, offs) = layout base objs
   in body
        <> xrefTable offs
        <> "trailer\n<< /Size 20 /Root 1 0 R /Prev "
        <> BC.pack (show prev)
        <> " >>\nstartxref\n"
        <> BC.pack (show (BS.length body))
        <> "\n%%EOF\n"
  where
    lastStartxref b =
      let (_, rest) = BS.breakSubstring "startxref\n" (snd (BS.breakSubstring "trailer" b))
       in maybe 0 fst (BC.readInt (BS.drop 10 rest))

{- | A PDF whose objects other than streams are in an object stream, with a
cross-reference stream compressed with Flate and the PNG Up predictor.
-}
xrefStreamPdf :: [RawObj] -> [RawObj] -> ByteString
xrefStreamPdf inStream direct =
  let header = "%PDF-1.5\n%\xE2\xE3\xCF\xD3\n"
      stmNum = 100
      xrefNum = 101
      pairs = scanl (+) 0 [BS.length b + 1 | (_, b) <- inStream]
      index = BC.unwords (concat [[BC.pack (show n), BC.pack (show o)] | ((n, _), o) <- zip inStream pairs])
      first = BS.length index + 1
      stmBody = index <> "\n" <> BC.unwords (map snd inStream)
      objStm = (stmNum, stream ("/Type /ObjStm /N " <> BC.pack (show (length inStream)) <> " /First " <> BC.pack (show first)) stmBody)
      (body, offs) = layout header (direct <> [objStm])
      xrefAt = BS.length body
      maxN = xrefNum
      entry n
        | Just o <- lookup n offs = [1] <> be 4 o <> be 2 0
        | Just i <- lookup n (zip (map fst inStream) [0 :: Int ..]) = [2] <> be 4 stmNum <> be 2 i
        | n == xrefNum = [1] <> be 4 xrefAt <> be 2 0
        | otherwise = [0] <> be 4 0 <> be 2 0
      rows = [entry n | n <- [0 .. maxN]]
      predicted = BS.pack (concat (zipWith up (replicate 7 0 : rows) rows))
      up prev row = 2 : zipWith (-) row prev
      compressed = BL.toStrict (Z.compress (BL.fromStrict predicted))
      xref =
        stream
          ("/Type /XRef /Size " <> BC.pack (show (maxN + 1)) <> " /W [1 4 2] /Root 1 0 R /Filter /FlateDecode /DecodeParms << /Predictor 12 /Columns 7 >>")
          compressed
   in body <> objBytes (xrefNum, xref) <> "startxref\n" <> BC.pack (show xrefAt) <> "\n%%EOF\n"
  where
    be :: Int -> Int -> [Word8]
    be k v = [fromIntegral (v `shiftR` (8 * i)) | i <- [k - 1, k - 2 .. 0]]

catalog :: RawObj
catalog = (1, "<< /Type /Catalog /Pages 2 0 R >>")

-- | One page of 200 by 100 pt, with the content and the resources given.
onePage :: ByteString -> ByteString -> [RawObj]
onePage resources content =
  [ catalog,
    (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
    (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources " <> resources <> " /Contents 4 0 R >>"),
    (4, stream "" content)
  ]

minimalPdf :: ByteString
minimalPdf = classicPdf "" (onePage "<< >>" "0 0 0 1 k 0 0 100 50 re f")

importOk :: Int -> ByteString -> IO ImportedPage
importOk n b = either (assertFailure . show) pure (importPage n b)

hasInfix :: ByteString -> ByteString -> Bool
hasInfix = BS.isInfixOf

-- ------------------------------------------------------------------ tests

tests :: TestTree
tests =
  testGroup
    "PDF figures (ADR 0008)"
    [ testGroup "the cross-reference" xrefTests,
      testGroup "pages" pageTests,
      testGroup "what is refused" refusalTests,
      testGroup "colours" colourTests,
      testGroup "writing" writingTests
    ]

xrefTests :: [TestTree]
xrefTests =
  [ testCase "a cross-reference table" $ do
      p <- importOk 1 minimalPdf
      ipSize p @?= (200, 100)
      assertBool (show (ipContent p)) ("0 0 100 50 re f" `hasInfix` ipContent p),
    testCase "a cross-reference stream and an object stream" $ do
      let pdf =
            xrefStreamPdf
              [ catalog,
                (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
                (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 150] /Resources << >> /Contents 4 0 R >>")
              ]
              [(4, stream "/Filter /FlateDecode" (BL.toStrict (Z.compress "0 0 0 1 k 1 1 2 2 re f")))]
      p <- importOk 1 pdf
      ipSize p @?= (300, 150)
      assertBool (show (ipContent p)) ("1 1 2 2 re f" `hasInfix` ipContent p),
    testCase "a later revision wins (/Prev)" $ do
      let pdf = updated minimalPdf [(4, stream "" "0 0 0 1 k 9 9 9 9 re f")]
      p <- importOk 1 pdf
      assertBool (show (ipContent p)) ("9 9 9 9 re f" `hasInfix` ipContent p)
      assertBool "not the first revision" (not ("0 0 100 50 re f" `hasInfix` ipContent p)),
    testCase "no header is Malformed" $
      case importPage 1 (BS.drop 9 minimalPdf) of
        Left (Malformed _) -> pure ()
        other -> assertFailure (show other),
    testCase "startxref out of the file is Malformed" $
      case importPage 1 (fst (BS.breakSubstring "startxref" minimalPdf) <> "startxref\n999999\n%%EOF\n") of
        Left (Malformed _) -> pure ()
        other -> assertFailure (show other),
    testCase "a page written by Golem can be read" $ do
      let pdf = writePdf golemDoc
      assertBool "imported" (isRight (importPage 1 pdf))
  ]

pageTests :: [TestTree]
pageTests =
  [ testCase "the third page of three, and no fourth" $ do
      let pdf =
            classicPdf
              ""
              [ catalog,
                (2, "<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 /MediaBox [0 0 100 100] /Resources << >> >>"),
                (3, "<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>"),
                (4, stream "" "1 1 1 1 re f"),
                (5, "<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>"),
                (6, stream "" "2 2 2 2 re f"),
                (7, "<< /Type /Page /Parent 2 0 R /Contents 8 0 R >>"),
                (8, stream "" "3 3 3 3 re f")
              ]
      p <- importOk 3 pdf
      assertBool (show (ipContent p)) ("3 3 3 3 re f" `hasInfix` ipContent p)
      ipPage p @?= 3
      importPage 4 pdf @?= Left (NoSuchPage 4 3),
    testCase "MediaBox and Resources are inherited from the page tree" $ do
      let pdf =
            classicPdf
              ""
              [ catalog,
                (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 50 80] /Resources << /ExtGState << /G1 5 0 R >> >> >>"),
                (3, "<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>"),
                (4, stream "" "/G1 gs 0 0 1 1 re f"),
                (5, "<< /Type /ExtGState /CA 0.5 >>")
              ]
      p <- importOk 1 pdf
      ipBox p @?= (0, 0, 50, 80)
      map fst (ipObjects p) @?= [5]
      case ipResources p of
        ODict kvs -> map fst kvs @?= ["ExtGState"]
        other -> assertFailure (show other),
    testCase "the crop box is cut to the media box" $ do
      let pdf = classicPdf "" (onePage' "/MediaBox [0 0 200 100] /CropBox [-10 -10 100 50]")
      p <- importOk 1 pdf
      ipBox p @?= (0, 0, 100, 50)
      ipSize p @?= (100, 50),
    testCase "Rotate 90 swaps the width and the height" $ do
      let pdf = classicPdf "" (onePage' "/MediaBox [0 0 200 100] /Rotate 90")
      p <- importOk 1 pdf
      ipRotate p @?= 90
      ipSize p @?= (100, 200),
    testCase "Rotate -90 is 270 and swaps the width and the height" $ do
      p <- importOk 1 (classicPdf "" (onePage' "/MediaBox [0 0 200 100] /Rotate -90"))
      (ipRotate p, ipSize p) @?= (270, (100, 200)),
    testCase "Rotate 180 keeps the width and the height" $ do
      p <- importOk 1 (classicPdf "" (onePage' "/MediaBox [0 0 200 100] /Rotate 180"))
      (ipRotate p, ipSize p) @?= (180, (200, 100)),
    testCase "Rotate 45 is Malformed" $
      case importPage 1 (classicPdf "" (onePage' "/MediaBox [0 0 200 100] /Rotate 45")) of
        Left (Malformed _) -> pure ()
        other -> assertFailure (show other),
    testCase "a crop box inside the media box is the box" $ do
      p <- importOk 1 (classicPdf "" (onePage' "/MediaBox [0 0 200 100] /CropBox [10 20 110 70]"))
      (ipBox p, ipSize p) @?= ((10, 20, 110, 70), (100, 50)),
    testCase "a crop box of no width is Malformed" $
      case importPage 1 (classicPdf "" (onePage' "/MediaBox [0 0 200 100] /CropBox [100 0 100 100]")) of
        Left (Malformed _) -> pure ()
        other -> assertFailure (show other),
    testCase "the same input gives the same page" $
      importPage 1 rgbPdf @?= importPage 1 rgbPdf
  ]
  where
    onePage' boxes =
      [ catalog,
        (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
        (3, "<< /Type /Page /Parent 2 0 R " <> boxes <> " /Resources << >> /Contents 4 0 R >>"),
        (4, stream "" "0 0 1 1 re f")
      ]

refusalTests :: [TestTree]
refusalTests =
  [ testCase "an encrypted PDF" $
      importPage 1 (classicPdf "/Encrypt 9 0 R" (onePage "<< >>" "0 0 1 1 re f" <> [(9, "<< /Filter /Standard >>")])) @?= Left Encrypted,
    testCase "a content stream in LZWDecode" $
      importPage 1 (classicPdf "" (take 3 (onePage "<< >>" "") <> [(4, stream "/Filter /LZWDecode" "\x80\x0b\x60")])) @?= Left (UnsupportedFilter "LZWDecode"),
    testCase "Helvetica not embedded" $
      importPage 1 (classicPdf "" (onePage "<< /Font << /F1 5 0 R >> >>" "BT /F1 12 Tf (a) Tj ET" <> [(5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")]))
        @?= Left (FontNotEmbedded "Helvetica"),
    testCase "a Separation colour space" $
      importPage 1 (classicPdf "" (onePage "<< /ColorSpace << /CS1 [/Separation /Gold /DeviceCMYK 5 0 R] >> >>" "/CS1 cs 1 scn" <> [(5, "<< /FunctionType 2 /Domain [0 1] /C0 [0 0 0 0] /C1 [0 0.2 1 0] /N 1 >>")]))
        @?= Left SpotColor,
    testCase "a form with /OC" $
      importPage 1 (classicPdf "" (onePage "<< /XObject << /X1 5 0 R >> >>" "/X1 Do" <> [(5, stream "/Type /XObject /Subtype /Form /BBox [0 0 1 1] /OC 6 0 R" "0 0 1 1 re f"), (6, "<< /Type /OCG /Name (a) >>")]))
        @?= Left OptionalContent,
    testCase "an RGB inline image" $
      importPage 1 (classicPdf "" (onePage "<< >>" "q 1 0 0 1 0 0 cm BI /W 1 /H 1 /CS /RGB /BPC 8 ID \xff\x00\x00 EI Q"))
        @?= Left RgbInlineImage,
    testCase "UserUnit 2" $
      importPage 1 (classicPdf "" [catalog, (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"), (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1 1] /UserUnit 2 /Resources << >> /Contents 4 0 R >>"), (4, stream "" "")])
        @?= Left UnsupportedUserUnit,
    testCase "each refusal has its wording" $
      map importErrorText [Encrypted, NoSuchPage 4 3, UnsupportedFilter "LZWDecode", FontNotEmbedded "Helvetica", Malformed "相互参照"]
        @?= ["暗号化された PDF は使えません", "4 ページ目がありません（全 3 ページ）", "LZWDecode で圧縮された PDF は使えません", "埋め込んでいないフォントがあります: Helvetica", "PDF として読めません（相互参照）"]
  ]

-- | A page in DeviceRGB and DeviceCMYK with an RGB image.
rgbPdf :: ByteString
rgbPdf =
  classicPdf
    ""
    ( onePage "<< /XObject << /Im1 5 0 R >> >>" "1 0 0 rg /DeviceRGB cs 0 0 1 1 re f 0 0 0 1 k /Im1 Do"
        <> [(5, stream "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB" "\xff\x00\x00")]
    )

colourTests :: [TestTree]
colourTests =
  [ testCase "DeviceRGB in the content becomes the sRGB ICCBased" $ do
      p <- importOk 1 rgbPdf
      let c = ipContent p
      assertBool (show c) ("/GolemSRGB cs 1 0 0 sc" `hasInfix` c)
      assertBool (show c) ("/GolemSRGB cs 0 0 1 1 re f" `hasInfix` c)
      assertBool (show c) ("0 0 0 1 k" `hasInfix` c)
      assertBool (show c) (not (" rg" `hasInfix` c) && not ("DeviceRGB" `hasInfix` c))
      case ipResources p of
        ODict kvs -> lookup "ColorSpace" kvs @?= Just (ODict [("GolemSRGB", OArr [OName "ICCBased", ORef 0])])
        other -> assertFailure (show other),
    testCase "an RGB image gets the sRGB ICCBased" $ do
      p <- importOk 1 rgbPdf
      case lookup 5 (ipObjects p) of
        Just (OStream d _) -> lookup "ColorSpace" d @?= Just (OArr [OName "ICCBased", ORef 0])
        other -> assertFailure (show other),
    testCase "RG and /DeviceRGB CS of the stroke become GolemSRGB with CS and SC" $ do
      p <- importOk 1 (classicPdf "" (onePage "<< >>" "0 1 0 RG /DeviceRGB CS 0 0 1 1 re S"))
      ipContent p @?= "/GolemSRGB CS 0 1 0 SC /GolemSRGB CS 0 0 1 1 re S",
    testCase "rg in a string or a comment is not an operator and stays as it is" $ do
      let content = "BT (1 0 0 rg) Tj ET\n% 1 0 0 rg\n0 0 0 1 k"
      p <- importOk 1 (classicPdf "" (onePage "<< >>" content))
      ipContent p @?= content
      ipColors p @?= [UseCmyk],
    testCase "DeviceRGB in the content of a Form XObject is replaced, and its Resources gain GolemSRGB" $ do
      p <- importOk 1 (classicPdf "" (onePage "<< /XObject << /X1 5 0 R >> >>" "/X1 Do" <> [(5, stream "/Type /XObject /Subtype /Form /BBox [0 0 1 1] /Resources << >>" "1 0 0 rg 0 0 1 1 re f")]))
      case lookup 5 (ipObjects p) of
        Just (OStream d body) -> do
          BL.toStrict (Z.decompress (BL.fromStrict body)) @?= "/GolemSRGB cs 1 0 0 sc 0 0 1 1 re f"
          lookup "Resources" d @?= Just (ODict [("ColorSpace", ODict [("GolemSRGB", OArr [OName "ICCBased", ORef 0])])])
        other -> assertFailure (show other),
    testCase "the sRGB profile added is object 0: the whole profile, three components, Flate" $ do
      p <- importOk 1 rgbPdf
      case lookup 0 (ipObjects p) of
        Just (OStream d body) -> do
          d @?= [("N", OInt 3), ("Filter", OName "FlateDecode")]
          BL.toStrict (Z.decompress (BL.fromStrict body)) @?= srgbProfile
        other -> assertFailure (show other),
    testCase "a page only in DeviceCMYK gets no sRGB profile" $ do
      p <- importOk 1 minimalPdf
      (lookup 0 (ipObjects p), ipResources p) @?= (Nothing, ODict []),
    testCase "the colour spaces used" $ do
      p <- importOk 1 rgbPdf
      ipColors p @?= [UseRgb, UseCmyk]
  ]

-- | A document of one page that draws the form 1 twice.
formDoc :: [Mark] -> [(FormRef, ImportedPage)] -> Document
formDoc marks forms =
  golemDoc
    { docPages = [Page box box box marks],
      docForms = Map.fromList [(r, ImportedForm p) | (r, p) <- forms]
    }
  where
    box = Rect 0 0 (100 * 65536) (100 * 65536)

golemDoc :: Document
golemDoc =
  Document
    { docPages = [Page box box box [SetColor (Swatch 0 0 0 100), Rule (Rect 0 0 65536 65536)]],
      docFonts = Map.empty,
      docImages = Map.empty,
      docForms = Map.empty,
      docTitle = "t",
      docDate = (2026, 10, 17),
      docId = documentId "urn:uuid:11111111-2222-4333-8444-555555555555",
      docInstanceId = instanceId ["source"],
      docProducer = "Golem 0.0.0-test",
      docPdfX = Nothing
    }
  where
    box = Rect 0 0 (100 * 65536) (100 * 65536)

count :: ByteString -> ByteString -> Int
count needle hay = case BS.breakSubstring needle hay of
  (_, rest) | BS.null rest -> 0
  (_, rest) -> 1 + count needle (BS.drop (BS.length needle) rest)

writingTests :: [TestTree]
writingTests =
  [ testCase "a form drawn twice is written once" $ do
      p <- importOk 1 rgbPdf
      let r = Rect 0 0 (50 * 65536) (25 * 65536)
          pdf = writePdf (formDoc [Form (FormRef 1) r, Form (FormRef 1) r] [(FormRef 1, p)])
      count "/Subtype /Form" pdf @?= 1
      count "/Subtype /Image" pdf @?= 1
      count "/Fm1 Do" (contentOf pdf) @?= 2,
    testCase "two pages of one file share their objects" $ do
      let pdf =
            classicPdf
              ""
              [ catalog,
                (2, "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 /MediaBox [0 0 100 100] /Resources << /XObject << /Im1 7 0 R >> >> >>"),
                (3, "<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>"),
                (4, stream "" "/Im1 Do"),
                (5, "<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>"),
                (6, stream "" "/Im1 Do"),
                (7, stream "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray" "\x00")
              ]
      p1 <- importOk 1 pdf
      p2 <- importOk 2 pdf
      let r = Rect 0 0 65536 65536
          out = writePdf (formDoc [Form (FormRef 1) r, Form (FormRef 2) r] [(FormRef 1, p1), (FormRef 2, p2)])
      count "/Subtype /Form" out @?= 2
      count "/Subtype /Image" out @?= 1,
    testGroup
      "the Matrix of a PDF figure maps its crop box, turned by Rotate, to the unit square"
      -- the box (10, 20)-(110, 70) is 100 by 50; e.g. Rotate 90 maps (x, y) to ((y - 20) / 50, (110 - x) / 100),
      -- so the lower left corner (10, 20) goes to (0, 1), the upper left of the turned figure
      [ testCase ("Rotate " <> show r) $ do
          p <- importOk 1 (classicPdf "" [catalog, (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"), (3, "<< /Type /Page /Parent 2 0 R /MediaBox [10 20 110 70] /Rotate " <> BC.pack (show r) <> " /Resources << >> /Contents 4 0 R >>"), (4, stream "" "0 0 1 1 re f")])
          let pdf = writePdf (formDoc [Form (FormRef 1) (Rect 0 0 65536 65536)] [(FormRef 1, p)])
          assertBool (show pdf) ("/BBox [10 20 110 70]" `BS.isInfixOf` pdf)
          assertBool (show pdf) (("/Matrix [" <> matrix <> "]") `BS.isInfixOf` pdf)
      | (r, matrix) <-
          [ (0 :: Int, "0.01 0 0 0.02 -0.1 -0.4"),
            (90, "0 -0.01 0.02 0 -0.4 1.1"),
            (180, "-0.01 0 0 -0.02 1.1 1.4"),
            (270, "0 0.01 -0.02 0 1.4 -0.1")
          ]
      ],
    testCase "the same document gives the same bytes" $ do
      p <- importOk 1 rgbPdf
      let doc = formDoc [Form (FormRef 1) (Rect 0 0 65536 65536)] [(FormRef 1, p)]
      writePdf doc @?= writePdf doc
      Right p @?= importPage 1 rgbPdf,
    testCase "X4.verify finds nothing in a PDF figure with RGB" $ do
      p <- importOk 1 rgbPdf
      let doc = (formDoc [Form (FormRef 1) (Rect 0 0 65536 65536)] [(FormRef 1, p)]) {docPdfX = Just (PdfX "fake-cmyk-profile" "JC200103" [] [])}
      verify (documentObjects doc) @?= [],
    needsTool "qpdf" (findExecutable "qpdf") $ \qpdf ->
      testCase "qpdf --check accepts a PDF figure" $ do
        exe <- qpdf
        p <- importOk 1 rgbPdf
        withSystemTempDirectory "golem-pdf" $ \dir -> do
          let path = dir </> "figure.pdf"
          BS.writeFile path (writePdf (formDoc [Form (FormRef 1) (Rect 0 0 65536 65536)] [(FormRef 1, p)]))
          (code, out, err) <- readProcessWithExitCode exe ["--check", path] ""
          assertEqual (out <> err) ExitSuccess code
  ]
  where
    -- the first Flate stream: the content of the first page
    contentOf pdf =
      let (_, at) = BS.breakSubstring "<< /Filter /FlateDecode /Length " pdf
          rest = BS.drop 32 at
       in case BC.readInt rest of
            Just (n, _) ->
              let (_, s') = BS.breakSubstring ">>\nstream\n" rest
               in BL.toStrict (Z.decompress (BL.fromStrict (BS.take n (BS.drop 10 s'))))
            Nothing -> ""
