{- | PDF figures and figures that cannot be placed (golem-pdf ADR 0008);
figures fitted to the column and turned onto a page of their own
(golem-driver ADR 0034).
-}
module FigureSpec (pdfFigureTests, svgFigureTests, fitFigureTests, turnedFigureTests) where

import Control.Monad (forM_)
import Data.Bits (shiftR)
import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, listToMaybe)
import Data.Ratio ((%))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Pdf (PdfLayout (..), PlacedFigure (..), figureRect, fitFigure)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (PageOut (..), Slotted (..), labelPages)
import Golem.LayoutSpec (PageGeometry (..), Rect (..), columnsFor, typeAreaFor)
import Golem.Pdf (FigureContent (..), ImportedPage (..), Mark (..), Turn (..), contentStream)
import Golem.Preflight.View (ImageView (..), LineView (..), PageView (..), View (..))
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
      "a PDF figure of 200 by 100 pt fills the measure of 240 pt, its height by its turned size; a tall one is fitted to the 29 lines its number leaves (golem-driver ADR 0034)"
      [ testCase ("Rotate " <> show r) $ do
          (_, pl) <- layoutOk horizontal24 "@figure images/f.pdf web=images/f.png alt=\"t\"\n" [("images/f.pdf", rotatedPdf r), ("images/f.png", png False)]
          (_, pf, _, _) <- theFigure pl
          (pfAlong pf, pfAcross pf) @?= (along, across * pt)
      | (r, along, across) <- [(0 :: Int, 240 * pt, 120), (90, 435 * pt `div` 2, 435), (180, 240 * pt, 120), (270, 435 * pt `div` 2, 435)]
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

-- ------------------------------------------------------------------ golem-driver ADR 0034

-- | An SVG of w by h with an unpainted frame.
boxSvg :: Int -> Int -> BS.ByteString
boxSvg w h = TE.encodeUtf8 (T.pack ("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" <> show w <> "\" height=\"" <> show h <> "\"><rect width=\"" <> show w <> "\" height=\"" <> show h <> "\" fill=\"none\"/></svg>"))

-- | The images of these tests: wide (3:1), tall (1:3) and square.
boxes :: [(FilePath, BS.ByteString)]
boxes = [("images/wide.svg", boxSvg 300 100), ("images/tall.svg", boxSvg 100 300), ("images/square.svg", boxSvg 100 100)]

-- | A figure of one of 'boxes', with more arguments and a caption (none when empty).
fig :: T.Text -> T.Text -> T.Text -> T.Text
fig name extra caption = "@figure images/" <> name <> ".svg alt=\"t\"" <> extra <> "\n" <> (if T.null caption then "" else "  " <> caption <> "\n") <> "\n"

tshow :: Int -> T.Text
tshow = T.pack . show

{- | A page of 300 by 400 pt: 10pt on a 15pt pitch, the writing mode, the
binding, the characters of a column, the lines, the columns (10pt
apart), and the top and gutter of the type area in pt.
-}
pageStyle :: T.Text -> T.Text -> Int -> Int -> Int -> Int -> Int -> BS.ByteString
pageStyle mode binding chars lines' cols top gutter =
  figStyle . TE.encodeUtf8 . T.concat $
    [ "[page]\nsize = { width = \"300pt\", height = \"400pt\" }\nbinding = \"",
      binding,
      "\"\nwriting-mode = \"",
      mode,
      "\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = ",
      tshow chars,
      "\nlines = ",
      tshow lines',
      "\nline-pitch = \"15pt\"\ncolumns = ",
      tshow cols,
      if cols > 1 then "\ncolumn-gap = \"10pt\"" else "",
      "\nposition = { top = \"",
      tshow top,
      "pt\", gutter = \"",
      tshow gutter,
      "pt\" }\n"
    ]

-- | Vertical, 24 characters (240pt) and 10 lines (145pt), the type area from the top.
vertical10 :: Int -> BS.ByteString
vertical10 top = pageStyle "vertical" "right" 24 10 1 top 40

-- | Horizontal, 24 characters (240pt) and 20 lines (295pt), with the binding and the gutter.
horizontal20 :: T.Text -> Int -> BS.ByteString
horizontal20 binding = pageStyle "horizontal" binding 24 20 1 20

-- | Every figure of a layout: its figure, its page and its first grid line, in the order of the pages.
figuresIn :: PdfLayout -> [(PlacedFigure, PageOut, Int)]
figuresIn pl =
  [ (pf, p, slot)
  | p <- plPages pl,
    (slot, s) <- poSlots p,
    fid <- case s of
      SFigure f -> [f]
      SWrapped f -> [f]
      SPageFigure f -> [f]
      _ -> [],
    Just pf <- [Map.lookup fid (plFigures pl)]
  ]

-- | The column of a page.
columnOf :: PageGeometry -> PageOut -> Rect
columnOf geom p = columnsFor geom (poNumber p) !! poColumn p

-- | The rectangle of the image of each figure, with its column.
placedRects :: PageGeometry -> PdfLayout -> [(Rect, Rect)]
placedRects geom pl = [(figureRect geom (poNumber p) col slot pf, col) | (pf, p, slot) <- figuresIn pl, let col = columnOf geom p]

inside :: Rect -> Rect -> Bool
inside (Rect x y w h) (Rect cx cy cw ch) = x >= cx && y >= cy && x + w <= cx + cw && y + h <= cy + ch

notices :: T.Text -> PdfLayout -> [Diagnostic]
notices code pl = [d | d <- plNotices pl, diagCode d == DiagnosticCode code]

-- | The text of a line of a caption.
captionText :: Line -> T.Text
captionText l = T.concat [bcText c | Box _ c <- lineItems l]

-- | The byte offsets of the @figure blocks of a source.
figureOffsets :: T.Text -> [Int]
figureOffsets = offsetsIn "@figure"

-- | The start of the turn of a rectangle as the content stream writes it: "q a b c d e f cm".
turnPrefix :: Turn -> Rect -> BS.ByteString
turnPrefix t r = fst (BS.breakSubstring "\n" (contentStream Map.empty Map.empty [Turned t r []]))

-- | The view of golem preflight of a one-chapter project.
viewOf :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO View
viewOf style source files = withSystemTempDirectory "golem-fit" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ (bodyFontFiles style <> files) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  p <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}
  maybe (assertFailure (show (prDiagnostics p))) pure (prView p)

-- | The diagnostics and outputs of a build with more manifest lines.
notifiedWith :: BS.ByteString -> BS.ByteString -> T.Text -> (BuildOptions -> BuildOptions) -> IO Notified
notifiedWith manifestExtra style source =
  buildNotified ([("manifest.toml", miniManifest <> manifestExtra), ("style.toml", withBodyFont style), ("a.gm", TE.encodeUtf8 source)] <> fakeFontFiles <> boxes)

fitFigureTests :: [TestTree]
fitFigureTests =
  [ testGroup
      "the size: within the measure and the depth of the column"
      [ testCase "without a caption a figure is as deep as the column: (L - 1) p + h, its height in proportion" $
          fitFigure 3 (240 * pt) 10 (15 * pt) (10 * pt) Nothing @?= (floor (145 * pt % 3), 145 * pt, True),
        testCase "a figure that fits keeps the measure" $
          fitFigure (1 / 3) (240 * pt) 10 (15 * pt) (10 * pt) Nothing @?= (240 * pt, 80 * pt, False),
        testCase "vertical: a wide figure with only its number is as deep as the lines the number leaves, its height in proportion" $ do
          (geom, pl) <- layoutOk (vertical10 60) (fig "wide" "" "") boxes
          (pf, p, slot) <- single (figuresIn pl)
          pfCaptionSpan pf @?= 1
          pfAcross pf @?= 9 * 15 * pt
          pfAlong pf @?= floor (fromInteger (pfAcross pf) * 100 / 300 :: Rational)
          pfFullAlong pf @?= 240 * pt
          assertBool "inside the column" (inside (figureRect geom (poNumber p) (columnOf geom p) slot pf) (columnOf geom p)),
        testCase "vertical: with a caption, the image takes the lines the caption leaves" $ do
          (geom, pl) <- layoutOk (vertical10 60) (fig "wide" "" "キャプション。") boxes
          (pf, _, slot) <- single (figuresIn pl)
          let s = pfCaptionSpan pf
          assertBool "a caption" (s > 0)
          pfImageLines pf @?= 10 - s
          pfAcross pf @?= toInteger (10 - s) * pgLinePitch geom
          assertBool "the caption in the column" (slot + pfImageLines pf + pfCaptionSpan pf <= 10),
        testCase "vertical: a tall figure (2 by 3) that fits keeps the measure" $ do
          img <- tinyImage
          (_, pl) <- layoutOk (pageStyle "vertical" "right" 24 12 1 60 40) "@figure images/tiny.jpg alt=\"t\"\n" img
          (pf, _, _) <- single (figuresIn pl)
          pfAlong pf @?= 240 * pt,
        testCase "horizontal: a tall figure is as deep as the type area and does not go below the column" $ do
          (geom, pl) <- layoutOk (horizontal20 "left" 20) (fig "tall" "" "") boxes
          (r, col) <- single (placedRects geom pl)
          (pf, _, _) <- single (figuresIn pl)
          pfAcross pf @?= 19 * 15 * pt
          assertBool "not below the column" (rectY r >= rectY col),
        testCase "horizontal: a wide figure keeps the measure" $ do
          (_, pl) <- layoutOk (horizontal20 "left" 20) (fig "wide" "" "") boxes
          (pf, _, _) <- single (figuresIn pl)
          pfAlong pf @?= 240 * pt,
        testCase "vertical, two columns: a wide figure in the second column is inside it" $ do
          (geom, pl) <- layoutOk (pageStyle "vertical" "right" 12 10 2 75 40) (fig "wide" "" "" <> fig "wide" "" "") boxes
          map (\(_, p, _) -> poColumn p) (figuresIn pl) @?= [0, 1]
          forM_ (placedRects geom pl) $ \(r, col) -> assertBool (show (r, col)) (inside r col),
        testCase "a fitted figure after text that leaves too few lines goes to the top of the next page" $ do
          (geom, pl) <- layoutOk (vertical10 60) ("あ\n\n" <> fig "wide" "" "") boxes
          (_, p, slot) <- single (figuresIn pl)
          (poNumber p, slot) @?= (2, 0)
          forM_ (placedRects geom pl) $ \(r, col) -> assertBool (show (r, col)) (inside r col)
      ],
    testGroup
      "the side: to the edge nearer the edge of the paper"
      [ testCase "vertical, the head margin smaller: to the top, on odd and even pages" $ do
          (geom, pl) <- layoutOk (vertical10 60) (fig "wide" "" "" <> fig "wide" "" "") boxes
          [rectY r + rectH r - (rectY col + rectH col) | (r, col) <- placedRects geom pl] @?= [0, 0],
        testCase "vertical, the head margin larger: to the bottom" $ do
          (geom, pl) <- layoutOk (vertical10 100) (fig "wide" "" "" <> fig "wide" "" "") boxes
          [rectY r - rectY col | (r, col) <- placedRects geom pl] @?= [0, 0],
        testCase "horizontal, bound on the left, the gutter smaller: odd pages to the left, even pages to the right" $ do
          (geom, pl) <- layoutOk (horizontal20 "left" 20) (fig "tall" "" "" <> fig "tall" "" "") boxes
          sides (placedRects geom pl) @?= ["left", "right"],
        testCase "horizontal, bound on the left, the gutter larger: odd pages to the right, even pages to the left" $ do
          (geom, pl) <- layoutOk (horizontal20 "left" 40) (fig "tall" "" "" <> fig "tall" "" "") boxes
          sides (placedRects geom pl) @?= ["right", "left"],
        testCase "horizontal, bound on the right: the sides change places" $ do
          (geom, pl) <- layoutOk (horizontal20 "right" 20) (fig "tall" "" "" <> fig "tall" "" "") boxes
          sides (placedRects geom pl) @?= ["right", "left"]
          (geom', pl') <- layoutOk (horizontal20 "right" 40) (fig "tall" "" "" <> fig "tall" "" "") boxes
          sides (placedRects geom' pl') @?= ["left", "right"],
        testCase "the same margins: to the start of the line" $ do
          (geom, pl) <- layoutOk (horizontal20 "left" 30) (fig "tall" "" "" <> fig "tall" "" "") boxes
          sides (placedRects geom pl) @?= ["left", "left"]
          (geom', pl') <- layoutOk (vertical10 80) (fig "wide" "" "" <> fig "wide" "" "") boxes
          [rectY r + rectH r - (rectY col + rectH col) | (r, col) <- placedRects geom' pl'] @?= [0, 0],
        testCase "two columns: the left column to the left, the right to the right; the upper to the top, the lower to the bottom" $ do
          (geom, pl) <- layoutOk (pageStyle "horizontal" "left" 12 20 2 20 25) (fig "tall" "" "" <> fig "tall" "" "") boxes
          sides (placedRects geom pl) @?= ["left", "right"]
          (geom', pl') <- layoutOk (pageStyle "vertical" "right" 12 10 2 75 40) (fig "wide" "" "" <> fig "wide" "" "") boxes
          case placedRects geom' pl' of
            [(r1, c1), (r2, c2)] -> do
              rectY r1 + rectH r1 @?= rectY c1 + rectH c1
              rectY r2 @?= rectY c2
            other -> assertFailure (show other),
        testCase "the caption starts at the start of the line of the column" $ do
          v <- viewOf (horizontal20 "left" 40) (fig "tall" "" "キャプション。") boxes
          (geom, _) <- layoutOk (horizontal20 "left" 40) (fig "tall" "" "キャプション。") boxes
          [rectX (lvRect l) | pv <- vwPages v, l <- pvLines pv, lvKind l == "キャプションの行"] @?= [rectX (typeAreaFor geom 1)],
        testCase "a figure that is not fitted stays where it was" $ do
          (geom, pl) <- layoutOk (horizontal20 "left" 40) (fig "wide" "" "") boxes
          (r, col) <- single (placedRects geom pl)
          (rectX r, rectW r, rectY r + rectH r) @?= (rectX col, 240 * pt, rectY col + rectH col)
      ],
    testGroup
      "the notice G0739 and the error G0738"
      [ testCase "one G0739 for each fitted figure, at the @figure, with the percentage and the hint of rotate" $ do
          let source = fig "wide" "" "" <> fig "wide" "" ""
          (_, pl) <- layoutOk (vertical10 60) source boxes
          [(diagMessage d, diagSeverity d) | d <- notices "G0739" pl] @?= replicate 2 ("図版を段に収めるため 18% に縮めました。rotate=true で回して一ページに置くと、より大きく置けます", Notice)
          map (spanStart . diagSpan) (notices "G0739" pl) @?= figureOffsets source,
        testCase "no hint when turning it would not make it larger" $ do
          (_, pl) <- layoutOk (horizontal20 "left" 20) (fig "tall" "" "") boxes
          map diagMessage (notices "G0739" pl) @?= ["図版を段に収めるため 39% に縮めました"],
        testCase "no G0739 for a figure that is not fitted" $ do
          (_, pl) <- layoutOk (horizontal20 "left" 20) (fig "wide" "" "キャプション。") boxes
          notices "G0739" pl @?= [],
        testCase "silence-notices silences G0739 and the PDF stays the same" $ do
          let source = fig "wide" "" ""
          loud <- notifiedWith "" (vertical10 60) source id
          quiet <- notifiedWith "\n[diagnostics]\nsilence-notices = [\"G0739\"]\n" (vertical10 60) source id
          length [d | d <- nDiagnostics loud, diagCode d == DiagnosticCode "G0739"] @?= 1
          [d | d <- nDiagnostics quiet, diagCode d == DiagnosticCode "G0739"] @?= []
          -- the manifests differ, and so the IDs of the PDF; the content streams are the same
          quietStreams <- maybe (assertFailure "no PDF") inflateAll (lookup pdfName (nOutputs quiet))
          loudStreams <- maybe (assertFailure "no PDF") inflateAll (lookup pdfName (nOutputs loud))
          quietStreams @?= loudStreams
          assertBool "a PDF" (isJust (lookup pdfName (nOutputs loud))),
        testCase "G0738: a caption as deep as the column, at the figure, in dev and prod" $ do
          let source = "前の段落。\n\n" <> fig "wide" "" (T.replicate 70 "あ")
          r <- layoutMini (pageStyle "horizontal" "left" 24 2 1 20 20) source boxes
          case r of
            Left [d] -> do
              diagCode d @?= DiagnosticCode "G0738"
              Just (spanStart (diagSpan d)) @?= listToMaybe (figureOffsets source)
              assertBool (T.unpack (diagMessage d)) ("図版のキャプションが段の行数を超えます（" `T.isPrefixOf` diagMessage d && "段は 2 行）" `T.isSuffixOf` diagMessage d)
            other -> assertFailure (show (either (map diagCode) (const []) other))
          forM_ [Dev, Prod] $ \profile -> do
            n <- notifiedWith "" (pageStyle "horizontal" "left" 24 2 1 20 20) source (\o -> o {optTargets = Just [TargetPdf], optProfile = profile})
            [diagCode d | d <- nDiagnostics n, isError d] @?= [DiagnosticCode "G0738"]
      ],
    testCase "fitted and turned figures: parallel and sequential, and two builds, give the same bytes" $ do
      let source = "本文。\n\n" <> fig "wide" "" "キャプション。" <> fig "wide" " rotate=true" "回した図。" <> "後の本文。\n"
      a <- miniPdf fakeProvider True (vertical10 60) source boxes
      b <- miniPdf fakeProvider False (vertical10 60) source boxes
      c <- miniPdf fakeProvider True (vertical10 60) source boxes
      a @?= b
      a @?= c
      qpdfCheck a
  ]
  where
    sides rs = [if rectX r == rectX col then "left" else if rectX r + rectW r == rectX col + rectW col then "right" else "neither" :: T.Text | (r, col) <- rs]

-- | The PDF of the one-chapter project, under build/.
pdfName :: FilePath
pdfName = "pdf/urn-uuid-11111111-2222-4333-8444-555555555555.pdf"

-- | The only element of a list.
single :: [a] -> IO a
single = \case
  [x] -> pure x
  other -> assertFailure ("not one but " <> show (length other))

turnedFigureTests :: [TestTree]
turnedFigureTests =
  [ testCase "vertical: a turned figure is turned right into the type area, on odd and even pages" $ do
      let source = fig "wide" " rotate=true" "" <> fig "wide" " rotate=true" ""
      (geom, pl) <- layoutOk (vertical10 60) source boxes
      [poNumber p | (_, p, _) <- figuresIn pl] @?= [1, 2]
      content <- miniPdf fakeProvider True (vertical10 60) source boxes >>= fmap BS.concat . inflateAll
      forM_ [1, 2] $ \n -> assertBool (show n) (turnPrefix TurnedRight (typeAreaFor geom n) `BS.isInfixOf` content)
      count "q 0 1 -1 0 " content @?= 0,
    testCase "horizontal: a turned figure is turned left" $ do
      let source = fig "wide" " rotate=true" "" <> fig "wide" " rotate=true" ""
      (geom, _) <- layoutOk (horizontal20 "left" 20) source boxes
      content <- miniPdf fakeProvider True (horizontal20 "left" 20) source boxes >>= fmap BS.concat . inflateAll
      forM_ [1, 2] $ \n -> assertBool (show n) (turnPrefix TurnedLeft (typeAreaFor geom n) `BS.isInfixOf` content)
      count "q 0 -1 1 0 " content @?= 0,
    testCase "the caption of a turned figure is set to the height of the type area, or its width in vertical text" $ do
      (geom, pl) <- layoutOk (horizontal20 "left" 20) (fig "wide" " rotate=true" (T.replicate 40 "あ")) boxes
      (pf, _, _) <- single (figuresIn pl)
      assertBool "lines" (not (null (pfCaption pf)))
      map lineTarget (pfCaption pf) @?= map (const (rectH (pgTypeArea geom))) (pfCaption pf)
      (geom', pl') <- layoutOk (vertical10 60) (fig "wide" " rotate=true" (T.replicate 40 "あ")) boxes
      (pf', _, _) <- single (figuresIn pl')
      map lineTarget (pfCaption pf') @?= map (const (rectW (pgTypeArea geom'))) (pfCaption pf'),
    testCase "the frame has (Fd - h) / p + 1 lines; a figure that does not fit it is fitted with G0739 for the page" $ do
      -- horizontal24: Fm 445pt, Fd 240pt, 16 lines
      (_, pl) <- layoutOk horizontal24 (fig "square" " rotate=true" "") boxes
      (pf, _, _) <- single (figuresIn pl)
      -- the number of the figure takes one line
      (pfCaptionSpan pf, pfImageLines pf, pfAcross pf, pfAlong pf) @?= (1, 15, 225 * pt, 225 * pt)
      map diagMessage (notices "G0739" pl) @?= ["図版をページに収めるため 50% に縮めました"],
    testCase "G0738: a caption as deep as the frame" $ do
      r <- layoutMini (pageStyle "horizontal" "left" 3 20 1 20 20) (fig "wide" " rotate=true" (T.replicate 70 "あ")) boxes
      case r of
        Left [d] -> do
          diagCode d @?= DiagnosticCode "G0738"
          assertBool (T.unpack (diagMessage d)) ("図版のキャプションがページの行数を超えます（" `T.isPrefixOf` diagMessage d && "ページは 2 行）" `T.isSuffixOf` diagMessage d)
        other -> assertFailure (show (either (map diagCode) (const []) other)),
    testCase "the image and the caption of a turned figure are inside the type area on the page; the caption is text" $ do
      let style = vertical10 60
          source = fig "wide" " rotate=true" "キャプション。"
      (geom, _) <- layoutOk style source boxes
      v <- viewOf style source boxes
      let ta = typeAreaFor geom 1
          ivs = concatMap pvImages (vwPages v)
          caps = [lvRect l | pv <- vwPages v, l <- pvLines pv, lvKind l == "キャプションの行"]
      map ivTurned ivs @?= [True]
      forM_ (map ivRect ivs <> caps) $ \r -> assertBool (show (r, ta)) (inside r ta)
      assertBool "caption lines" (not (null caps))
      content <- miniPdf fakeProvider True style source boxes >>= fmap BS.concat . inflateAll
      assertBool "caption glyphs" (fromEnum 'キ' `elem` map dGlyph (drawnGlyphs content)),
    testCase "two columns: a turned figure spans the type area of both" $ do
      let style = pageStyle "horizontal" "left" 12 20 2 20 25
      (geom, _) <- layoutOk style (fig "wide" " rotate=true" "") boxes
      content <- miniPdf fakeProvider True style (fig "wide" " rotate=true" "") boxes >>= fmap BS.concat . inflateAll
      assertBool "turned" (turnPrefix TurnedLeft (typeAreaFor geom 1) `BS.isInfixOf` content),
    testCase "the page of a turned figure has its folio" $ do
      v <- viewOf (vertical10 60 <> "\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n") (fig "wide" " rotate=true" "") boxes
      [any ((== "ノンブル") . lvKind) (pvLines pv) | pv <- vwPages v, not (null (pvImages pv))] @?= [True],
    testCase "a turned figure keeps its number in the order written; ref-page names its page" $ do
      let source = "本文。\n\n@label turned\n" <> fig "wide" " rotate=true" "回した図。" <> fig "wide" "" "後の図。" <> "参照は[ref-page turned]ページ。\n"
      (_, pl) <- layoutOk (horizontal20 "left" 20) source boxes
      let placed = figuresIn pl
          turnedPage = [poNumber p | (_, p, _) <- placed, (_, SPageFigure _) <- poSlots p]
      [T.take 2 (captionText l) | (pf, _, _) <- placed, l <- take 1 (pfCaption pf)] @?= ["F1", "F2"]
      turnedPage @?= [2]
      Map.lookup "turned" (labelPages (plPages pl)) @?= Just 2,
    testCase "HTML and EPUB place a turned figure as any other" $ do
      let build' r = notifiedWith "\n[targets.html]\n\n[targets.epub]\n" (horizontal20 "left" 20) (fig "wide" r "キャプション。") (\o -> o {optTargets = Just [TargetHtml, TargetEpub]})
      turned <- build' " rotate=true"
      plain <- build' ""
      assertBool "outputs" (not (null (nOutputs plain)))
      nOutputs turned @?= nOutputs plain
  ]
