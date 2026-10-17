-- | PDF figures and figures that cannot be placed (golem-pdf ADR 0008).
module FigureSpec (pdfFigureTests, svgFigureTests) where

import Control.Monad (forM_)
import Data.Bits (shiftR)
import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Pdf (PlacedFigure (..))
import Golem.Pdf (FigureContent (..), ImportedPage (..))
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A PDF that Golem built: one A5 page.
golemPdf :: IO BS.ByteString
golemPdf = miniPdf fakeProvider False horizontalStyle "図の本文。\n" []

-- | A PNG of one pixel, interlaced or not (readImage refuses interlaced PNGs).
png :: Bool -> BS.ByteString
png interlaced =
  BS.pack [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    <> chunk "IHDR" (be32 1 <> be32 1 <> BS.pack [8, 0, 0, 0, if interlaced then 1 else 0])
    <> chunk "IDAT" (BS.pack [0x78, 0x9C, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01])
    <> chunk "IEND" ""
  where
    be32 :: Int -> BS.ByteString
    be32 n = BS.pack [fromIntegral (n `shiftR` s) | s <- [24, 16, 8, 0 :: Int]]
    chunk name d = be32 (BS.length d) <> name <> d <> be32 0

-- | A build of the one-chapter project to the targets, in a profile: the error codes and whether a PDF was written.
buildIn :: Profile -> [Target] -> T.Text -> [(FilePath, BS.ByteString)] -> IO ([DiagnosticCode], Bool)
buildIn profile targets source files = withSystemTempDirectory "golem-figure" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n")
  BS.writeFile (tmp </> "style.toml") (withBodyFont (figStyle horizontalStyle))
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ (bodyFontFiles horizontalStyle <> files) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  r <- build (defaultOptions tmp) {optTargets = Just targets, optFonts = fakeProvider, optProfile = profile}
  pdf <- doesFileExist (tmp </> "build/a.pdf")
  pure (map diagCode (filter isError (brDiagnostics r)), pdf || any (".pdf" `isSuffixOf`) (brWritten r))

count :: BS.ByteString -> BS.ByteString -> Int
count needle hay = case BS.breakSubstring needle hay of
  (_, rest) | BS.null rest -> 0
  (_, rest) -> 1 + count needle (BS.drop (BS.length needle) rest)

{- | A PDF of one page of 200 by 100 pt, turned by Rotate, built here as
bytes: a catalog, a page tree, the page and its content.
-}
rotatedPdf :: Int -> BS.ByteString
rotatedPdf r =
  let content = "0 0 0 1 k 0 0 1 1 re f"
      objs =
        [ "<< /Type /Catalog /Pages 2 0 R >>",
          "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Rotate " <> TE.encodeUtf8 (T.pack (show r)) <> " /Resources << >> /Contents 4 0 R >>",
          "<< /Length " <> TE.encodeUtf8 (T.pack (show (BS.length content))) <> " >>\nstream\n" <> content <> "\nendstream"
        ]
      header = "%PDF-1.4\n"
      bodies = [TE.encodeUtf8 (T.pack (show n)) <> " 0 obj\n" <> o <> "\nendobj\n" | (n, o) <- zip [1 :: Int ..] objs]
      offsets = scanl (+) (BS.length header) (map BS.length bodies)
      xrefAt = last offsets
      entry o = TE.encodeUtf8 (T.justifyRight 10 '0' (T.pack (show o))) <> " 00000 n \n"
   in header
        <> BS.concat bodies
        <> "xref\n0 5\n0000000000 65535 f \n"
        <> BS.concat (map entry (init offsets))
        <> "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n"
        <> TE.encodeUtf8 (T.pack (show xrefAt))
        <> "\n%%EOF\n"

pdfFigureTests :: [TestTree]
pdfFigureTests =
  [ testGroup
      "a PDF figure of 200 by 100 pt fills the measure of 240 pt, its height by its turned size"
      [ testCase ("Rotate " <> show r) $ do
          (_, pl) <- layoutOk horizontal24 "@figure images/f.pdf web=images/f.png alt=\"t\"\n" [("images/f.pdf", rotatedPdf r), ("images/f.png", png False)]
          (_, pf, _, _) <- theFigure pl
          (pfAlong pf, pfAcross pf) @?= (240 * pt, across * pt)
      | (r, across) <- [(0 :: Int, 120), (90, 480), (180, 120), (270, 480)]
      ],
    testCase "a PDF figure fills the measure, its height in the proportion of its crop box" $ do
      fig <- golemPdf
      (_, pl) <- layoutOk horizontal24 "@figure images/f.pdf web=images/f.png alt=\"t\"\n  キャプション。\n" [("images/f.pdf", fig), ("images/f.png", png False)]
      (_, pf, _, _) <- theFigure pl
      case pfContent pf of
        VectorFigure ip -> do
          let (w, h) = ipSize ip
          pfAlong pf @?= 240 * pt
          pfAcross pf @?= floor (fromInteger (240 * pt) * h / w)
        other -> assertFailure (show other),
    testCase "the book's PDF has one Form XObject for a PDF figure placed twice" $ do
      fig <- golemPdf
      let one = "@figure images/f.pdf web=images/f.png alt=\"t\"\n  キャプション。\n\n"
      pdf <- miniPdf fakeProvider False (figStyle horizontalStyle) (one <> "本文。\n\n" <> one) [("images/f.pdf", fig), ("images/f.png", png False)]
      count "/Subtype /Form" pdf @?= 1,
    testCase "a broken PNG and an interlaced PNG are G0810, and no PDF is written, in dev and prod" $
      forM_ [Dev, Prod] $ \profile -> do
        let src = "@figure images/a.png alt=\"t\"\n\n@figure images/b.png alt=\"t\"\n"
        (codes, written) <- buildIn profile [TargetPdf] src [("images/a.png", BS.take 20 (png False)), ("images/b.png", png True)]
        codes @?= [DiagnosticCode "G0810", DiagnosticCode "G0810"]
        written @?= False,
    testCase "the message of G0810 has the path and the reason" $ withSystemTempDirectory "golem-figure" $ \tmp -> do
      BS.writeFile (tmp </> "manifest.toml") miniManifest
      BS.writeFile (tmp </> "style.toml") (withBodyFont (figStyle horizontalStyle))
      BS.writeFile (tmp </> "a.gm") "@figure images/b.png alt=\"t\"\n"
      forM_ (bodyFontFiles horizontalStyle <> [("images/b.png", png True)]) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
      r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
      map diagMessage (filter isError (brDiagnostics r)) @?= ["図版を PDF に置けません: images/b.png（インターレースの PNG は使えません）"],
    testCase "an encrypted PDF figure is G0810" $ do
      fig <- golemPdf
      let (before, after) = BS.breakSubstring "trailer\n<<" fig
          encrypted = before <> "trailer\n<< /Encrypt 1 0 R" <> BS.drop 10 after
      (codes, written) <- buildIn Dev [TargetPdf] "@figure images/f.pdf web=images/f.png alt=\"t\"\n" [("images/f.pdf", encrypted), ("images/f.png", png False)]
      codes @?= [DiagnosticCode "G0810"]
      written @?= False,
    testCase "HTML does not read the images: a broken PNG is not G0810" $ do
      (codes, _) <- buildIn Dev [TargetHtml] "@figure images/a.png alt=\"t\"\n" [("images/a.png", BS.take 20 (png False))]
      codes @?= []
  ]

-- | An SVG of 200 by 100 with a red square (golem-pdf ADR 0009).
redSvg :: BS.ByteString
redSvg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\"><rect x=\"10\" y=\"10\" width=\"50\" height=\"50\" fill=\"#ff0000\"/></svg>"

-- | The PDF of a one-chapter project with files, or the error codes.
pdfWith :: Profile -> T.Text -> [(FilePath, BS.ByteString)] -> IO ([DiagnosticCode], Maybe BS.ByteString, [T.Text])
pdfWith profile source files = withSystemTempDirectory "golem-svg" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
  BS.writeFile (tmp </> "style.toml") (withBodyFont (figStyle horizontalStyle))
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ (bodyFontFiles horizontalStyle <> files) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = profile}
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  let errs = filter isError (brDiagnostics r)
  pure (map diagCode errs, pdf, map diagMessage errs)

svgFigureTests :: [TestTree]
svgFigureTests =
  [ testCase "an SVG figure fills the measure, its height in the proportion of its root, as one Form XObject" $ do
      (_, pl) <- layoutOk horizontal24 "@figure images/f.svg alt=\"t\"\n  キャプション。\n" [("images/f.svg", redSvg)]
      (_, pf, _, _) <- theFigure pl
      (pfAlong pf, pfAcross pf) @?= (240 * pt, 120 * pt)
      (codes, pdf, _) <- pdfWith Dev "@figure images/f.svg alt=\"t\"\n" [("images/f.svg", redSvg)]
      codes @?= []
      bytes <- maybe (assertFailure "no PDF") pure pdf
      count "/Subtype /Form" bytes @?= 1
      count "DeviceRGB" bytes @?= 0,
    testCase "the paint of an SVG reaches the PDF: sRGB sc and SC, caps, joins and the even-odd rule" $ do
      let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path d=\"M0 0 L10 10\" fill=\"none\" stroke=\"#ff0000\" stroke-linecap=\"round\" stroke-linejoin=\"bevel\"/><rect width=\"5\" height=\"5\" fill=\"#00ff00\" fill-rule=\"evenodd\" stroke=\"#0000ff\" stroke-linecap=\"square\" stroke-linejoin=\"round\"/></svg>"
      (codes, pdf, _) <- pdfWith Dev "@figure images/p.svg alt=\"t\"\n" [("images/p.svg", svg)]
      codes @?= []
      streams <- maybe (assertFailure "no PDF") inflateAll pdf
      let content = BS.concat streams
      -- stroke colour, width 1, cap (round 1, square 2), join (bevel 2, round 1), miter limit 4, no dash
      assertBool (show content) ("1 0 0 SC 1 w 1 J 2 j 4 M [] 0 d\n0 0 m\n10 10 l\nS\n" `BS.isInfixOf` content)
      assertBool (show content) ("0 1 0 sc\n0 0 1 SC 1 w 2 J 1 j 4 M [] 0 d\n" `BS.isInfixOf` content)
      assertBool (show content) ("h\nB*\n" `BS.isInfixOf` content),
    testCase "two builds of an SVG figure give the same bytes" $ do
      (_, a, _) <- pdfWith Dev "@figure images/f.svg alt=\"t\"\n" [("images/f.svg", redSvg)]
      (_, b, _) <- pdfWith Dev "@figure images/f.svg alt=\"t\"\n" [("images/f.svg", redSvg)]
      assertBool "same" (a == b && isJust a),
    testCase "a gradient is G0811 and no PDF is written, in dev and prod; a broken SVG is G0810" $ do
      forM_ [Dev, Prod] $ \profile -> do
        (codes, pdf, _) <- pdfWith profile "@figure images/g.svg alt=\"t\"\n" [("images/g.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><linearGradient id=\"g\"/></svg>")]
        (codes, pdf) @?= ([DiagnosticCode "G0811"], Nothing)
      (codes, _, _) <- pdfWith Dev "@figure images/b.svg alt=\"t\"\n" [("images/b.svg", "<svg")]
      codes @?= [DiagnosticCode "G0810"],
    testCase "text is G0811, asking for outlines" $ do
      (codes, _, msgs) <- pdfWith Dev "@figure images/t.svg alt=\"t\"\n" [("images/t.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\">\n<text>a</text><use/></svg>")]
      codes @?= [DiagnosticCode "G0811"]
      msgs @?= ["SVG の図版に扱えないものがあります: images/t.svg:2:1（text: 文字は輪郭にして書き出してください）ほか 1 件"],
    testCase "one problem that is not text is G0811 without the request for outlines and without ほか" $ do
      (codes, _, msgs) <- pdfWith Dev "@figure images/g.svg alt=\"t\"\n" [("images/g.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\">\n  <use/></svg>")]
      codes @?= [DiagnosticCode "G0811"]
      msgs @?= ["SVG の図版に扱えないものがあります: images/g.svg:2:3（use）"],
    testCase "HTML and EPUB place an SVG with text as it is, or its web image" $ withSystemTempDirectory "golem-svg" $ \tmp -> do
      BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
      BS.writeFile (tmp </> "style.toml") (figStyle horizontalStyle)
      BS.writeFile (tmp </> "a.gm") "@figure images/t.svg alt=\"t\"\n\n@figure images/u.svg web=images/u.png alt=\"u\"\n"
      createDirectoryIfMissing True (tmp </> "images")
      BS.writeFile (tmp </> "images/t.svg") "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><text>a</text></svg>"
      BS.writeFile (tmp </> "images/u.svg") "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><text>b</text></svg>"
      BS.writeFile (tmp </> "images/u.png") (png False)
      r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
      brDiagnostics r @?= []
      page <- BS.readFile (tmp </> "build/html/a.xhtml")
      assertBool "t.svg" ("src=\"images/t.svg\"" `BS.isInfixOf` page)
      assertBool "u.png" ("src=\"images/u.png\"" `BS.isInfixOf` page)
  ]
