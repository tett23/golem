-- | Drawings of SVG figures as Form XObjects (golem-pdf ADR 0009).
module DrawingSpec (tests) where

import Codec.Compression.Zlib qualified as Z
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf
import Golem.TestSupport.ExternalTool (needsTool)
import ImportSpec (minimalPdf)
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

-- | A red square with a black outline, 20 by 10.
redSquare :: Drawing
redSquare =
  Drawing
    (20, 10)
    [ DrawGroup
        [1, 0, 0, 1, 2, 3]
        Nothing
        [ DrawPath
            (PathPaint (Just (255, 0, 0)) False (Just (PathStroke (0, 0, 0) 1 0 0 4 [] 0)))
            [SegMove (0, 0), SegLine (5, 0), SegCurve (6, 1) (6, 2) (5, 5), SegClose]
        ]
    ]

doc :: [Mark] -> [(FormRef, FormContent)] -> Map.Map ImageRef ImageData -> Document
doc marks forms images =
  Document
    { docPages = [Page box box box marks],
      docFonts = Map.empty,
      docImages = images,
      docForms = Map.fromList forms,
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

-- | Every Flate stream of a PDF, inflated.
streams :: ByteString -> [ByteString]
streams pdf = case BS.breakSubstring "/Filter /FlateDecode" pdf of
  (_, rest) | BS.null rest -> []
  (_, rest) ->
    let (_, lenAt) = BS.breakSubstring "/Length " rest
        n = maybe 0 fst (BC.readInt (BS.drop 8 lenAt))
        (_, body) = BS.breakSubstring "stream\n" lenAt
        raw = BS.take n (BS.drop 7 body)
        inflated = BL.toStrict (Z.decompress (BL.fromStrict raw))
     in inflated : streams (BS.drop 7 body)

tests :: TestTree
tests =
  testGroup
    "SVG drawings (ADR 0009)"
    [ testCase "a drawing is one Form XObject without fonts, its colours in the sRGB ICCBased" $ do
        let r = Rect 0 0 (40 * 65536) (20 * 65536)
            pdf = writePdf (doc [Form (FormRef 1) r, Form (FormRef 1) r] [(FormRef 1, DrawnForm redSquare)] Map.empty)
        count "/Subtype /Form" pdf @?= 1
        count "/Font" pdf @?= 0
        count "DeviceRGB" pdf @?= 0
        let content = BS.concat (streams pdf)
        assertBool (show content) ("/GolemSRGB cs /GolemSRGB CS" `BS.isInfixOf` content)
        assertBool (show content) ("1 0 0 sc" `BS.isInfixOf` content)
        assertBool (show content) ("0 0 0 SC 1 w 0 J 0 j 4 M [] 0 d" `BS.isInfixOf` content)
        assertBool (show content) ("5 5 c" `BS.isInfixOf` content && "\nB\n" `BS.isInfixOf` content),
      testCase "X4.verify finds nothing in a drawing" $
        verify (documentObjects (doc [Form (FormRef 1) (Rect 0 0 65536 65536)] [(FormRef 1, DrawnForm redSquare)] Map.empty) {docPdfX = Just (PdfX "fake-cmyk-profile" "JC200103" [] [])}) @?= [],
      testCase "the sRGB profile is written once for images, PDF figures and drawings" $ do
        img <- either (assertFailure . show) pure (readImage rgbPng)
        page <- either (assertFailure . show) pure (importPage 1 rgbFigure)
        let r = Rect 0 0 65536 65536
            pdf = writePdf (doc [Image (ImageRef 1) r, Form (FormRef 1) r, Form (FormRef 2) r] [(FormRef 1, DrawnForm redSquare), (FormRef 2, ImportedForm page)] (Map.fromList [(ImageRef 1, img)]))
        count "/N 3" pdf @?= 1,
      testCase "the same drawing gives the same bytes" $ do
        let d = doc [Form (FormRef 1) (Rect 0 0 65536 65536)] [(FormRef 1, DrawnForm redSquare)] Map.empty
        writePdf d @?= writePdf d,
      needsTool "qpdf" (findExecutable "qpdf") $ \qpdf ->
        testCase "qpdf --check accepts a drawing" $ do
          exe <- qpdf
          withSystemTempDirectory "golem-pdf" $ \dir -> do
            let path = dir </> "drawing.pdf"
            BS.writeFile path (writePdf (doc [Form (FormRef 1) (Rect 0 0 65536 65536)] [(FormRef 1, DrawnForm redSquare)] Map.empty))
            (code, out, err) <- readProcessWithExitCode exe ["--check", path] ""
            assertEqual (out <> err) ExitSuccess code
    ]
  where
    -- a PDF figure in DeviceRGB, which gets the sRGB profile
    rgbFigure = minimalPdfWith "1 0 0 rg 0 0 1 1 re f"

-- | The one-page PDF of ImportSpec with another content.
minimalPdfWith :: ByteString -> ByteString
minimalPdfWith content =
  let (before, rest) = BS.breakSubstring "0 0 0 1 k 0 0 100 50 re f" minimalPdf
      padded = content <> BS.replicate (25 - BS.length content) 32
   in before <> padded <> BS.drop 25 rest

-- | An RGB PNG of one pixel without a profile.
rgbPng :: ByteString
rgbPng =
  BS.pack [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    <> chunk "IHDR" (be32 1 <> be32 1 <> BS.pack [8, 2, 0, 0, 0])
    <> chunk "IDAT" (BL.toStrict (Z.compress (BL.pack [0, 255, 0, 0])))
    <> chunk "IEND" ""
  where
    be32 :: Int -> ByteString
    be32 n = BS.pack [fromIntegral (n `div` (256 ^ i) `mod` 256) | i <- [3, 2, 1, 0 :: Int]]
    chunk name d = be32 (BS.length d) <> name <> d <> be32 0
