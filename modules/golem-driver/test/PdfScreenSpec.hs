-- | The PDF for the screen (root ADR 0431) and the colours of its figures (root ADR 0445).
module PdfScreenSpec (pdfScreenTests) where

import Codec.Picture qualified as J
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word16, Word8)
import Golem.Driver
import Golem.Html qualified as H
import Golem.Pdf qualified as P
import Golem.Syntax
import Support
import System.Directory (doesDirectoryExist, listDirectory, removeFile)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | What a build left: its errors, the PDF for print, the PDF for the screen, the other files written by path from the root, and the folders of build.
data Out = Out
  { oErrors :: ![Diagnostic],
    oPdf :: !(Maybe BS.ByteString),
    oScreen :: !(Maybe BS.ByteString),
    oFiles :: !(Map.Map FilePath BS.ByteString),
    oDirs :: ![FilePath]
  }

{- | Builds the one-chapter project with the extra text of the manifest
after [targets.pdf], style.toml, the source and its files, with the options
changed.
-}
buildOut :: BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (BuildOptions -> BuildOptions) -> IO Out
buildOut manifestExtra style source files f = withSystemTempDirectory "golem-screen" $ \tmp -> do
  writeProject tmp (miniManifest <> manifestExtra) style source files
  r <- build (f (defaultOptions tmp) {optFonts = fakeProvider})
  written <- mapM (\p -> (drop (length tmp + 1) p,) <$> BS.readFile p) (brWritten r)
  let pdfIn d = case [b | (p, b) <- written, takeDirectory p == d, ".pdf" `isSuffixOf` p] of
        [b] -> Just b
        _ -> Nothing
  hasBuild <- doesDirectoryExist (tmp </> "build")
  dirs <- if hasBuild then sort <$> listDirectory (tmp </> "build") else pure []
  pure (Out (filter isError (brDiagnostics r)) (pdfIn "build/pdf") (pdfIn "build/pdf-screen") (Map.fromList written) dirs)

-- | 'buildOut' with the targets chosen.
buildTargets :: [Target] -> BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO Out
buildTargets ts manifestExtra style source files = buildOut manifestExtra style source files (\o -> o {optTargets = Just ts})

-- | The PDF for the screen of a build without errors.
screenOf :: Out -> IO BS.ByteString
screenOf o = do
  map diagCode (oErrors o) @?= []
  maybe (assertFailure "no PDF for the screen") pure (oScreen o)

-- | The PDF for print of a build without errors.
printOf :: Out -> IO BS.ByteString
printOf o = do
  map diagCode (oErrors o) @?= []
  maybe (assertFailure "no PDF for print") pure (oPdf o)

-- | Whether a PDF has a text.
has :: BS.ByteString -> BS.ByteString -> Bool
has s needle = needle `BS.isInfixOf` s

-- | The numbers of every box of a name in a PDF, in pt.
boxes :: BS.ByteString -> BS.ByteString -> [[Rational]]
boxes name pdf = case BS.breakSubstring ("/" <> name <> " [") pdf of
  (_, rest)
    | BS.null rest -> []
    | otherwise ->
        let body = BS.drop (BS.length name + 3) rest
         in map ptToRational (BC.words (BC.takeWhile (/= ']') body)) : boxes name body

-- | The link annotations of a PDF in order: the URI or the destination, and the rectangle in pt.
links :: BS.ByteString -> [(BS.ByteString, [Rational])]
links pdf =
  [ (target, map ptToRational (BC.words (field "/Rect [" "]")))
  | obj <- splitOn "endobj" pdf,
    "/Subtype /Link" `BS.isInfixOf` obj,
    let field open close = BC.takeWhile (/= BC.head close) (BS.drop (BS.length open) (snd (BS.breakSubstring open obj)))
        target = if "/URI (" `BS.isInfixOf` obj then field "/URI (" ")" else field "/Dest [" "]"
  ]

splitOn :: BS.ByteString -> BS.ByteString -> [BS.ByteString]
splitOn sep s = case BS.breakSubstring sep s of
  (a, rest)
    | BS.null rest -> [a]
    | otherwise -> a : splitOn sep (BS.drop (BS.length sep) rest)

-- | The glyphs of each page, without their places.
pageGlyphs :: BS.ByteString -> IO [[(BS.ByteString, Int)]]
pageGlyphs pdf = map (map (\d -> (dFont d, dGlyph d)) . drawnGlyphs) <$> pageContents pdf

-- | The style with a swatch accent.
accentStyle :: BS.ByteString -> BS.ByteString
accentStyle st = st <> "\n[color.swatches]\naccent = { cmyk = [15, 30, 45, 60] }\n"

intentStyle :: BS.ByteString
intentStyle = horizontalStyle <> "\n[color]\nintent = \"x.icc\"\n"

bleedStyle :: BS.ByteString
bleedStyle = replaceIn "[page]\n" "[page]\nbleed = \"3mm\"\n" horizontalStyle

linkSource :: T.Text
linkSource =
  "@label top\n# 見出し\n\nあ[link \"https://example.com/\": いう]え。"
    <> T.replicate 3 "長い本文の行です。"
    <> "[link \"https://example.org/\": 行をまたぐリンクの文字の並びがとても長く続きます]。[ref-page top]\n"

both :: [Target]
both = [TargetPdf, TargetPdfScreen]

-- | The components of a swatch in the digits of the numbers of the PDF.
rgbText :: (Int, Int, Int) -> BS.ByteString
rgbText (r, g, b) = BS.intercalate " " [TE.encodeUtf8 (P.showRational4 (toInteger v % 255)) | v <- [r, g, b]]

pdfScreenTests :: TestTree
pdfScreenTests =
  testGroup
    "the PDF for the screen (root ADR 0431, root ADR 0445)"
    [ testCase "root ADR 0431 I1, I5: a book with an intent: the PDF for print is PDF/X-4, the PDF for the screen 1.7 without an output intent, with the same pages and characters" $ do
        o <- buildTargets both "" intentStyle "# 章\n\n本文の文字。\n\n二つめの段落。\n" [("x.icc", "fake profile")]
        pdf <- printOf o
        screen <- screenOf o
        assertBool "print 1.6" ("%PDF-1.6" `BS.isPrefixOf` pdf)
        assertBool "print X-4" (all (has pdf) ["/OutputIntents", "GTS_PDFXVersion"])
        assertBool "screen 1.7" ("%PDF-1.7" `BS.isPrefixOf` screen)
        assertBool "no output intent" (not (any (has screen) ["/OutputIntents", "GTS_PDFXVersion", "/Trapped"]))
        printed <- pageGlyphs pdf
        shown <- pageGlyphs screen
        length shown @?= length printed
        shown @?= printed,
      testCase "root ADR 0431 I1: a book without an intent built for the screen alone is 1.7 without an output intent" $ do
        o <- buildTargets [TargetPdfScreen] "" horizontalStyle "本文。\n" []
        screen <- screenOf o
        assertBool "1.7" ("%PDF-1.7" `BS.isPrefixOf` screen)
        assertBool "no output intent" (not (any (has screen) ["/OutputIntents", "GTS_PDFXVersion"]))
        oPdf o @?= Nothing
        oDirs o @?= ["pdf-screen"]
        Map.keys (oFiles o) @?= ["build/pdf-screen/urn-uuid-11111111-2222-4333-8444-555555555555.pdf"],
      testGroup
        "root ADR 0431 I2, I10: the MediaBox of the PDF for the screen is the TrimBox of the PDF for print at the origin, without the bleed and the marks"
        [ testCase name $ do
            o <- buildOut "" style source [] (\opt -> opt {optTargets = Just both, optMarks = marks})
            pdf <- printOf o
            screen <- screenOf o
            let trims = boxes "TrimBox" pdf
                medias = boxes "MediaBox" screen
            assertBool "pages" (not (null trims))
            medias @?= [[0, 0, x1 - x0, y1 - y0] | [x0, y0, x1, y1] <- trims]
            boxes "TrimBox" screen @?= []
            boxes "BleedBox" screen @?= []
            assertBool "no Separation" (not (has screen "/Separation"))
            assertBool "the print PDF has its marks" (marks == NoMarks || has pdf "/Separation")
        | (name, style, source, marks) <-
            [ ("one page", horizontalStyle, "本文。\n", NoMarks),
              ("a background into the bleed", bleedStyle <> "\n[color.swatches]\npale = { cmyk = [0, 0, 20, 0] }\n[paragraph-styles.column]\nbackground = \"pale\"\n", "@style column\n本文。\n", NoMarks),
              ("Japanese marks", bleedStyle, "本文。\n", JapaneseMarks),
              ("Western marks", horizontalStyle, T.replicate 40 "本文の段落。\n\n", WesternMarks)
            ]
        ],
      testCase "root ADR 0431 I3: a book without links has no link annotations" $ do
        o <- buildTargets [TargetPdfScreen] "" horizontalStyle "本文。\n" []
        screen <- screenOf o
        links screen @?= [],
      testCase "root ADR 0431 I3: the links of the PDF for the screen are those of the PDF for print without an intent, moved by the corner of its TrimBox" $ do
        o <- buildTargets both "" bleedStyle linkSource []
        pdf <- printOf o
        screen <- screenOf o
        let printed = links pdf
            shown = links screen
            (cx, cy) = case boxes "TrimBox" pdf of
              [x0, y0, _, _] : _ -> (x0, y0)
              _ -> (0, 0)
            uris = filter (("https:" `BS.isPrefixOf`) . fst)
            dests = filter (not . ("https:" `BS.isPrefixOf`) . fst)
            -- a number of the PDF for the screen is that of the PDF for print less the corner, to the digits written
            near a b = abs (a - b) <= 1 % 10000
            sameRect r q = length r == 4 && length q == 4 && and (zipWith near r (zipWith (-) q [cx, cy, cx, cy]))
        assertBool "the bleed moves the trimmed page" (cx > 0 && cy > 0)
        assertBool (show printed) (length (uris printed) >= 3)
        assertBool "a destination inside the document" (not (null (dests printed)))
        length shown @?= length printed
        map fst (uris shown) @?= map fst (uris printed)
        assertBool (show (shown, printed)) (and (zipWith (\(_, r) (_, q) -> sameRect r q) (uris shown) (uris printed)))
        -- the page of each destination is the same; its top is moved as the rectangles are
        forM_ (zip (dests shown) (dests printed)) $ \((t, r), (u, q)) -> do
          assertBool (show (r, q)) (sameRect r q)
          case (BC.words t, BC.words u) of
            ([p, z, ref, xyz, l, top, n], [p', z', ref', xyz', l', top', n']) -> do
              [p, z, ref, xyz, l, n] @?= [p', z', ref', xyz', l', n']
              assertBool (show (top, top')) (near (ptToRational top) (ptToRational top' - cy))
            other -> assertFailure (show other),
      testCase "root ADR 0431 I4: the copy of cmykToRgb in golem-pdf gives what golem-html's does" $ do
        let values = [0, 1, 2, 33, 49, 50, 51, 66, 98, 99, 100] <> [0, 5 .. 100]
            differ = [cmyk | c <- values, m <- values, y <- values, k <- values, let cmyk = (c, m, y, k), P.cmykToRgb cmyk /= H.cmykToRgb cmyk]
        take 5 differ @?= []
        P.cmykToRgb (0, 0, 0, 0) @?= H.cmykToRgb (0, 0, 0, 0)
        P.cmykToRgb (100, 100, 100, 100) @?= H.cmykToRgb (100, 100, 100, 100),
      testCase "root ADR 0431 I4, root ADR 0445 I4: a swatch on characters, a rule and a background is the sRGB of cmykToRgb in the PDF for the screen" $ do
        let style =
              accentStyle horizontalStyle
                <> "\n[character-styles.ink]\ncolor = \"accent\"\n[paragraph-styles.column]\nbackground = \"accent\"\nborder = \"accent\"\nborder-width = \"1pt\"\n"
        o <- buildTargets both "" style "[style ink: 色の字]。\n\n@style column\n囲み。\n" []
        pdf <- printOf o
        screen <- screenOf o
        streams <- concat <$> mapM inflateAll [screen]
        printedStreams <- inflateAll pdf
        let rgb = rgbText (H.cmykToRgb (15, 30, 45, 60))
            painted = sum [length (occurrences ("/GolemSRGB cs " <> rgb <> " sc") c) | c <- streams]
        assertBool (show rgb) (painted >= 3)
        assertBool "print is CMYK" (any (has' "0.15 0.3 0.45 0.6 k") printedStreams)
        assertBool "no CMYK on the screen" (not (any (has' "0.15 0.3 0.45 0.6 k") streams))
        qpdfCheck screen,
      testCase "root ADR 0431 I4: the both ends of the swatches" $ do
        let style = horizontalStyle <> "\n[color.swatches]\nwhite = { cmyk = [0, 0, 0, 0] }\nrich = { cmyk = [100, 100, 100, 100] }\n[character-styles.w]\ncolor = \"white\"\n[character-styles.r]\ncolor = \"rich\"\n"
        o <- buildTargets [TargetPdfScreen] "" style "[style w: 白]と[style r: 黒]。\n" []
        screen <- screenOf o
        streams <- inflateAll screen
        assertBool "white" (any (has' "/GolemSRGB cs 1 1 1 sc") streams)
        assertBool "black" (any (has' "/GolemSRGB cs 0 0 0 sc") streams),
      testCase "root ADR 0431 I6: without --target, build/pdf-screen is not made, with or without [targets.pdf-screen]" $
        forM_ ["", "\n[targets.pdf-screen]\n"] $ \extra -> do
          o <- buildOut extra horizontalStyle "本文。\n" [] (\opt -> opt {optTargets = Just allTargets})
          map diagCode (oErrors o) @?= []
          assertBool (show (oDirs o)) ("pdf" `elem` oDirs o && "pdf-screen" `notElem` oDirs o)
          n <- buildOut extra horizontalStyle "本文。\n" [] (\opt -> opt {optTargets = Nothing})
          assertBool (show (oDirs n)) ("pdf-screen" `notElem` oDirs n),
      testCase "root ADR 0431 I7: the same input gives the same PDF for the screen" $ do
        a <- buildTargets both "" (accentStyle bleedStyle) linkSource [] >>= screenOf
        b <- buildTargets both "" (accentStyle bleedStyle) linkSource [] >>= screenOf
        c <- buildTargets [TargetPdfScreen] "" (accentStyle bleedStyle) linkSource [] >>= screenOf
        a == b @? "two builds differ"
        a == c @? "the PDF for the screen differs with the PDF for print",
      testCase "root ADR 0431 I8: a key of [targets.pdf-screen] other than pdfua, and a pdfua other than \"1\", are G03001 and write no PDF" $
        forM_ ["pdfa = \"2a\"\n", "pdfua = \"2\"\n"] $ \key -> do
          o <- buildTargets [TargetPdfScreen] ("\n[targets.pdf-screen]\n" <> key) horizontalStyle "本文。\n" []
          map diagCode (oErrors o) @?= [DiagnosticCode "G03001"]
          oScreen o @?= Nothing,
      testCase "root ADR 0431 I9: the PDF for print and the PDF for the screen have the same document ID and other instance IDs" $ do
        o <- buildTargets both "" horizontalStyle "本文。\n" []
        pdf <- printOf o
        screen <- screenOf o
        fst (pdfIds screen) @?= fst (pdfIds pdf)
        assertBool "other instance IDs" (snd (pdfIds screen) /= snd (pdfIds pdf)),
      testCase "root ADR 0431 I11: pdfua = \"1\" of [targets.pdf-screen] declares PDF/UA-1 in the XMP" $ do
        o <- buildTargets [TargetPdfScreen] "\n[targets.pdf-screen]\npdfua = \"1\"\n" horizontalStyle "# 見出し\n\n本文。\n" []
        screen <- screenOf o
        assertBool "pdfuaid:part" (has screen "<pdfuaid:part>1</pdfuaid:part>")
        assertBool "no PDF/X" (not (has screen "GTS_PDFXVersion"))
        plain <- buildTargets [TargetPdfScreen] "" horizontalStyle "# 見出し\n\n本文。\n" [] >>= screenOf
        assertBool "without pdfua, no XMP" (not (has plain "pdfuaid")),
      testCase "root ADR 0431 I12: built for the screen alone without the profile of the intent, no G08006 and a PDF" $ do
        o <- buildTargets [TargetPdfScreen] "" intentStyle "本文。\n" []
        _ <- screenOf o
        p <- buildTargets [TargetPdf] "" intentStyle "本文。\n" []
        map diagCode (oErrors p) @?= [DiagnosticCode "G08006"],
      testCase "root ADR 0431 I12: built for the screen alone without the body font, G08002 and no PDF" $
        withSystemTempDirectory "golem-screen-font" $ \tmp -> do
          writeProject tmp miniManifest horizontalStyle "本文。\n" []
          -- the body font of 'withBodyFont' is gone
          assertBool "a body font" (not (null (bodyFontFiles horizontalStyle)))
          mapM_ (removeFile . (tmp </>) . fst) (bodyFontFiles horizontalStyle)
          r <- build (defaultOptions tmp) {optTargets = Just [TargetPdfScreen], optFonts = fakeProvider}
          assertBool (show (map diagCode (brDiagnostics r))) (DiagnosticCode "G08002" `elem` map diagCode (filter isError (brDiagnostics r)))
          exists <- doesDirectoryExist (tmp </> "build/pdf-screen")
          exists @?= False,
      testGroup "root ADR 0445: the colours of the figures of the PDF for the screen" figureTests
    ]
  where
    has' needle s = needle `BS.isInfixOf` s

-- | The style of the figures drawn in the swatch C0 M100 Y100 K0 (root ADR 0403).
colorStyle :: BS.ByteString
colorStyle = figStyle horizontalStyle <> "color = \"accent\"\n[color.swatches.accent]\ncmyk = [0, 100, 100, 0]\n"

-- | The PDF for print, the PDF for the screen and HTML of a figure in the colour of 'colorStyle'.
figureBuild :: T.Text -> [(FilePath, BS.ByteString)] -> IO (BS.ByteString, BS.ByteString, Map.Map FilePath BS.ByteString)
figureBuild source files = do
  o <- buildTargets [TargetHtml, TargetPdf, TargetPdfScreen] "\n[targets.html]\n" colorStyle source files
  pdf <- printOf o
  screen <- screenOf o
  pure (pdf, screen, oFiles o)

-- | The colours of an SVG of HTML: each rgb(r,g,b).
svgColors :: BS.ByteString -> [(Int, Int, Int)]
svgColors svg = case BS.breakSubstring "rgb(" svg of
  (_, rest)
    | BS.null rest -> []
    | otherwise ->
        let body = BS.drop 4 rest
         in case map (read . BC.unpack) (BC.split ',' (BC.takeWhile (/= ')') body)) of
              [r, g, b] -> (r, g, b) : svgColors body
              _ -> svgColors body

-- | The colours a drawing of the PDF paints: each r g b of sc and SC.
drawnColors :: BS.ByteString -> [BS.ByteString]
drawnColors stream = [BS.intercalate " " (take 3 ws) | l <- BC.lines stream, let ws = BC.words l, length ws >= 4, ws !! 3 `elem` ["sc", "SC"]]

-- | The streams of the drawings of SVG figures.
drawings :: BS.ByteString -> IO [BS.ByteString]
drawings pdf = filter ("/GolemSRGB cs /GolemSRGB CS\n" `BS.isInfixOf`) . filter (" cm\n/GolemSRGB cs" `BS.isInfixOf`) <$> inflateAll pdf

-- | The objects that a Form XObject of a PDF figure brings: each stream and dictionary after the first Form, without object numbers.
formObjects :: BS.ByteString -> [BS.ByteString]
formObjects pdf =
  [ stripRefs (BS.drop 1 (BC.dropWhile (/= '\n') obj))
  | obj <- splitOn "endobj" pdf,
    any (`BS.isInfixOf` obj) ["/Subtype /Form", "/PatternType", "/ShadingType", "/GolemC"]
  ]
  where
    stripRefs s = BC.unwords [if all (`BC.elem` "0123456789") (BC.unpack w) then "N" else w | w <- BC.words s]

-- | Pixels of a PNG as 16-bit RGBA.
pngPixels :: BS.ByteString -> Either String [(Word16, Word16, Word16, Word16)]
pngPixels bytes = do
  img <- J.decodePng bytes
  case img of
    J.ImageRGBA16 i -> pure [let J.PixelRGBA16 r g b a = J.pixelAt i x y in (r, g, b, a) | y <- [0 .. J.imageHeight i - 1], x <- [0 .. J.imageWidth i - 1]]
    J.ImageRGBA8 i -> pure [let J.PixelRGBA8 r g b a = J.pixelAt i x y in (wide r, wide g, wide b, wide a) | y <- [0 .. J.imageHeight i - 1], x <- [0 .. J.imageWidth i - 1]]
    _ -> Left "the PNG of HTML is not RGBA"
  where
    wide v = fromIntegral v * 257

-- | The samples of an image of the PDF, as 16 bits, with its alpha (fully opaque without an SMask).
imageSamples :: Int -> BS.ByteString -> Maybe (Int, BS.ByteString) -> [(Word16, Word16, Word16, Word16)]
imageSamples bits rgbBytes alpha =
  let comps = samplesOf bits rgbBytes
      alphas = maybe (repeat 65535) (uncurry samplesOf) alpha
      triples (r : g : b : rest) = (r, g, b) : triples rest
      triples _ = []
   in zipWith (\(r, g, b) a -> (r, g, b, a)) (triples comps) alphas

samplesOf :: Int -> BS.ByteString -> [Word16]
samplesOf 16 bs = [fromIntegral hi * 256 + fromIntegral lo | (hi, lo) <- pairs (BS.unpack bs)]
  where
    pairs (a : b : rest) = (a, b) : pairs rest
    pairs _ = []
samplesOf _ bs = [fromIntegral v * 257 | v <- BS.unpack bs]

-- | Each image of a PDF: its bits, its samples and those of its SMask.
pdfImages :: BS.ByteString -> IO [(Int, BS.ByteString, Maybe (Int, BS.ByteString))]
pdfImages pdf = do
  let objs = splitOn "endobj" pdf
      numbered = Map.fromList (mapMaybe numberOf objs)
      numberOf obj = case BC.words (BC.takeWhile (/= '\n') (BC.dropWhile (`elem` ("\n\r " :: String)) obj)) of
        [n, "0", "obj"] | all (`BC.elem` "0123456789") (BC.unpack n) -> Just (read (BC.unpack n) :: Int, obj)
        _ -> Nothing
      images = [obj | obj <- objs, "/Subtype /Image" `BS.isInfixOf` obj, "/ICCBased" `BS.isInfixOf` obj]
  mapM
    ( \obj -> do
        body <- streamOf obj
        let bits = intAfter "/BitsPerComponent " obj
        alpha <- case intAfterMaybe "/SMask " obj of
          Just n | Just smask <- Map.lookup n numbered -> (\b -> Just (intAfter "/BitsPerComponent " smask, b)) <$> streamOf smask
          _ -> pure Nothing
        pure (bits, body, alpha)
    )
    images
  where
    streamOf obj = do
      inflated <- inflateAll obj
      pure (case inflated of s : _ -> s; [] -> "")
    intAfter key obj = fromMaybe 0 (intAfterMaybe key obj)
    intAfterMaybe key obj = case BS.breakSubstring key obj of
      (_, rest) | BS.null rest -> Nothing
      (_, rest) -> case BC.readInt (BS.drop (BS.length key) rest) of
        Just (n, _) -> Just n
        Nothing -> Nothing

-- | A PNG of 8-bit gray from rows of samples.
grayPng8 :: [[Word8]] -> BS.ByteString
grayPng8 rows = BS.toStrict (J.encodePng (J.generateImage (\x y -> rows !! y !! x) (maybe 0 length (listToMaybe rows)) (length rows) :: J.Image J.Pixel8))

figureTests :: [TestTree]
figureTests =
  [ testCase "root ADR 0445 I1: a PDF figure in the colour of the swatch is the same DeviceCMYK in the PDF for print and the PDF for the screen" $ do
      (pdf, screen, _) <- figureBuild "@figure images/f.pdf web=images/f.png alt=\"t\"\n" [("images/f.pdf", grayPdf), ("images/f.png", grayPng8 [[0, 255]])]
      let printed = formObjects pdf
      assertBool "a Form" (not (null printed))
      formObjects screen @?= printed
      qpdfCheck screen,
    testCase "root ADR 0445 I1: the transparency group of a PDF figure keeps its colour space" $ do
      (pdf, screen, _) <- figureBuild "@figure images/f.pdf web=images/f.png alt=\"t\"\n" [("images/f.pdf", groupPdf), ("images/f.png", grayPng8 [[0, 255]])]
      let printed = formObjects pdf
      assertBool "a group" (any ("/Group" `BS.isInfixOf`) printed)
      formObjects screen @?= printed,
    testGroup
      "root ADR 0445 I2: an SVG figure in the colour of the swatch is the sRGB of the SVG of HTML"
      [ testCase name $ do
          (_, screen, html) <- figureBuild "@figure images/f.svg alt=\"t\"\n" [("images/f.svg", svg)]
          htmlSvg <- maybe (assertFailure (show (Map.keys html))) pure (Map.lookup "build/html/images/f.svg" html)
          let expected = Set.fromList (map rgbText (svgColors htmlSvg))
          drawn <- drawings screen
          assertBool "a drawing" (not (null drawn))
          Set.fromList (concatMap drawnColors drawn) @?= expected
          assertBool "recoloured" (not (Set.null expected))
      | (name, svg) <-
          [ ("gray alone", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect x=\"0\" y=\"0\" width=\"10\" height=\"10\" fill=\"#ffffff\"/><path d=\"M 1 1 L 9 1\" fill=\"none\" stroke=\"#808080\"/><path d=\"M 1 3 L 9 3 L 9 9 Z\" fill=\"#000000\"/></svg>"),
            ("one colour", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path d=\"M 1 3 L 9 3 L 9 9 Z\" fill=\"#3366cc\"/><path d=\"M 1 1 L 9 1\" fill=\"none\" stroke=\"#3366cc\"/></svg>")
          ]
      ],
    testGroup
      "root ADR 0445 I3: a raster figure in the colour of the swatch has the pixels of the PNG of HTML"
      [ testCase name $ do
          bytes <- load
          (_, screen, html) <- figureBuild ("@figure images/" <> T.pack file <> " alt=\"t\"\n") [("images/" <> file, bytes)]
          htmlPng <- case [b | (p, b) <- Map.toList html, "build/html/images/" `isPrefixOfS` p, ".png" `isSuffixOf` p] of
            [b] -> pure b
            other -> assertFailure ("the PNG of HTML: " <> show (length other) <> " " <> show (Map.keys html))
          expected <- either assertFailure pure (pngPixels htmlPng)
          images <- pdfImages screen
          case images of
            [(bits, rgbBytes, alpha)] -> do
              let shown = imageSamples bits rgbBytes alpha
              length shown @?= length expected
              shown @?= expected
              check expected
            other -> assertFailure ("images: " <> show (length other))
      | (name, file, load, check) <-
          [ ("one colour, every pixel the swatch", "one.png", pure (rgbPng [[(10, 20, 30), (10, 20, 30)], [(10, 20, 30), (10, 20, 30)]]), \px -> nubRgb px @?= [scale (H.cmykToRgb (0, 100, 100, 0))]),
            ("8-bit gray", "gray.png", pure (grayPng8 [[0, 64, 128, 255], [255, 200, 100, 0]]), const (pure ())),
            ("gray JPEG", "gray.jpg", BS.readFile "../golem-typeset/test/fixtures/gray-progressive.jpg", const (pure ())),
            ("16-bit gray", "gray16.png", pure gray16Png, const (pure ())),
            ("gray with alpha", "alpha.png", pure grayAlphaPng, assertBool "alpha" . any (\(_, _, _, a) -> a /= 65535))
          ]
      ]
  ]
  where
    isPrefixOfS a b = take (length a) b == a
    nubRgb px = Set.toList (Set.fromList [(r, g, b) | (r, g, b, _) <- px])
    scale (r, g, b) = (fromIntegral r * 257, fromIntegral g * 257, fromIntegral b * 257)

rgbPng :: [[(Word8, Word8, Word8)]] -> BS.ByteString
rgbPng rows = BS.toStrict (J.encodePng (J.generateImage (\x y -> let (r, g, b) = rows !! y !! x in J.PixelRGB8 r g b) (maybe 0 length (listToMaybe rows)) (length rows)))

gray16Png :: BS.ByteString
gray16Png = BS.toStrict (J.encodePng (J.generateImage (\x y -> [0, 1000, 30000, 65535, 40000, 12345] !! (y * 3 + x)) 3 2 :: J.Image J.Pixel16))

grayAlphaPng :: BS.ByteString
grayAlphaPng = BS.toStrict (J.encodePng (J.generateImage (\x y -> [J.PixelYA8 0 255, J.PixelYA8 128 100, J.PixelYA8 255 0, J.PixelYA8 64 200] !! (y * 2 + x)) 2 2))

-- | A PDF of one page of 200 by 100 pt with the given resources, content and objects after it.
pdfOf :: BS.ByteString -> BS.ByteString -> [(Int, BS.ByteString)] -> BS.ByteString
pdfOf resources content extra =
  numberedPdf
    ( [ (1, "<< /Type /Catalog /Pages 2 0 R >>"),
        (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
        (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources " <> resources <> " /Contents 4 0 R >>"),
        (4, "<< /Length " <> BC.pack (show (BS.length content)) <> " >>\nstream\n" <> content <> "\nendstream")
      ]
        <> extra
    )

-- | A PDF figure painted in two grays.
grayPdf :: BS.ByteString
grayPdf = pdfOf "<< >>" "q 0.5 g 0 0 100 50 re f 0 G 1 w 0 0 m 200 100 l S Q" []

-- | A PDF figure with a transparency group of DeviceRGB, painting gray.
groupPdf :: BS.ByteString
groupPdf = pdfOf "<< /XObject << /G 5 0 R >> >>" "q /G Do Q" [(5, "<< /Type /XObject /Subtype /Form /BBox [0 0 200 100] /Group << /S /Transparency /CS /DeviceRGB >> /Length " <> BC.pack (show (BS.length inner)) <> " >>\nstream\n" <> inner <> "\nendstream")]
  where
    inner = "0.25 g 0 0 50 50 re f" :: BS.ByteString

-- | A PDF of numbered objects with a classic cross-reference table.
numberedPdf :: [(Int, BS.ByteString)] -> BS.ByteString
numberedPdf objs =
  let header = "%PDF-1.6\n"
      bodies = [BC.pack (show n) <> " 0 obj\n" <> o <> "\nendobj\n" | (n, o) <- objs]
      offsets = scanl (+) (BS.length header) (map BS.length bodies)
      size = maximum (map fst objs) + 1
      entry n = case lookup n (zip (map fst objs) offsets) of
        Just off -> BC.pack (pad 10 (show off)) <> " 00000 n \n"
        Nothing -> "0000000000 65535 f \n"
      xrefAt = last offsets
      pad w s = replicate (w - length s) '0' <> s
   in header <> BS.concat bodies <> "xref\n0 " <> BC.pack (show size) <> "\n" <> BS.concat (map entry [0 .. size - 1]) <> "trailer\n<< /Size " <> BC.pack (show size) <> " /Root 1 0 R >>\nstartxref\n" <> BC.pack (show xrefAt) <> "\n%%EOF\n"
