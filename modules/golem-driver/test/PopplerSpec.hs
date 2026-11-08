{- | The PDFs of Golem as Poppler reads them (docs/adr ADR 0232): the
transparent pixels of the PNGs with tRNS rendered by pdftoppm, and the
links of the pages listed by pdfinfo -url. Poppler is an executable CI
runs, never linked to Golem; without it these are SKIP, failures with
GOLEM_REQUIRE_EXTERNAL_TOOLS=1.
-}
module PopplerSpec (popplerTests) where

import Control.Monad (forM, forM_)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isSpace)
import Data.Text qualified as T
import Data.Word (Word8)
import Golem.Driver
import Golem.Length (Sp (..))
import Golem.Pdf (Alpha (..), ColorSpace (..), FigureContent (..), ImageData (..))
import Golem.Pdf.Rect (Rect (..))
import Golem.Preflight.View (ImageView (..), PageView (..), View (..))
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

popplerTests :: [TestTree]
popplerTests = [trnsTest, linkTest]

-- ------------------------------------------------------------------ pixels

-- | The colour of each pixel of an image of PNG, row by row, in 8 bits.
pixelColours :: ImageData -> [(Int, Int, Int)]
pixelColours img =
  [ colour (rowSamples r)
  | r <- [0 .. imgHeight img - 1],
    colour <- [pixel . take comps . drop (c * comps) | c <- [0 .. imgWidth img - 1]]
  ]
  where
    bits = imgBits img
    comps = case imgColor img of
      CsRgb -> 3
      CsCmyk -> 4
      _ -> 1
    rowBytes = (imgWidth img * comps * bits + 7) `div` 8
    rowSamples r = samples bits (BS.take rowBytes (BS.drop (r * rowBytes) (imgData img)))
    maxV = (1 `shiftL` bits) - 1 :: Int
    to8 v = if bits == 16 then v `shiftR` 8 else v * 255 `div` maxV
    pixel ss = case (imgColor img, ss) of
      (CsGray, [g]) -> let x = to8 g in (x, x, x)
      (CsRgb, [r, g, b]) -> (to8 r, to8 g, to8 b)
      (CsIndexed pal, [i]) -> let at k = fromIntegral (BS.index pal (3 * i + k)) in (at 0, at 1, at 2)
      _ -> (-1, -1, -1)

-- | The samples of a row of the given bits each.
samples :: Int -> BS.ByteString -> [Int]
samples bits row
  | bits == 16 = pairs (BS.unpack row)
  | bits == 8 = map fromIntegral (BS.unpack row)
  | otherwise = concatMap unpackByte (BS.unpack row)
  where
    pairs (a : b : rest) = (fromIntegral a `shiftL` 8 .|. fromIntegral b) : pairs rest
    pairs _ = []
    unpackByte :: Word8 -> [Int]
    unpackByte w = [fromIntegral (w `shiftR` (8 - bits * (k + 1))) .&. ((1 `shiftL` bits) - 1) | k <- [0 .. 8 `div` bits - 1]]

-- | A P6 PPM: its width, height and the bytes of its pixels.
readPpm :: BS.ByteString -> Maybe (Int, Int, BS.ByteString)
readPpm b = do
  rest0 <- BS.stripPrefix "P6" b
  (w, rest1) <- BC.readInt (BC.dropWhile isSpace rest0)
  (h, rest2) <- BC.readInt (BC.dropWhile isSpace rest1)
  (_, rest3) <- BC.readInt (BC.dropWhile isSpace rest2)
  Just (w, h, BS.drop 1 rest3)

ptOf :: Sp -> Double
ptOf (Sp s) = fromIntegral s / 65536

{- | I11: the figures fixture as pdftoppm renders it at 72 dpi: each pixel
of the four PNGs with tRNS that is transparent is white, and one that is
partly transparent (the half-transparent green) is its colour mixed with
white by its alpha, within 2. The places come from the rectangles of the
view of golem preflight and the pixels of the PNGs.
-}
trnsTest :: TestTree
trnsTest = testCase "I11: the transparent pixels of the PNGs with tRNS are the white of the paper in pdftoppm (golem-pdf ADR 0014)" $ do
  tool <- pdftoppmTool
  forM_ tool $ \pdftoppm -> withSystemTempDirectory "golem-trns" $ \tmp -> do
    copyTree "test/fixtures/figures" tmp
    createDirectoryIfMissing True (tmp </> "fonts")
    copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
    copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")
    p <- preflight (defaultPreflightOptions tmp)
    v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
    pdf <- maybe (assertFailure "no PDF") pure (prPdf p)
    BS.writeFile (tmp </> "out.pdf") pdf
    let trns =
          [ (pv, iv, img, a)
          | pv <- vwPages v,
            iv <- pvImages pv,
            "trns-" `T.isInfixOf` ivPath iv,
            RasterFigure img <- [ivContent iv],
            Just a <- [imgAlpha img]
          ]
    length trns @?= 4
    checked <- forM trns $ \(pv, iv, img, a) -> do
      let page = pvIndex pv
          base = tmp </> ("page-" <> show page)
      (code, out, err) <- readProcessWithExitCode pdftoppm ["-r", "72", "-f", show page, "-l", show page, "-singlefile", tmp </> "out.pdf", base] ""
      assertEqual (out <> err) ExitSuccess code
      (pw, ph, px) <- maybe (assertFailure "not a PPM") pure . readPpm =<< BS.readFile (base <> ".ppm")
      let Rect x y w h = ivRect iv
          Rect _ _ _ th = pvTrim pv
          iw = imgWidth img
          ih = imgHeight img
          renderedAt col row =
            let cx = ptOf x + (fromIntegral col + 0.5) * ptOf w / fromIntegral iw
                cy = ptOf th - (ptOf y + ptOf h - (fromIntegral row + 0.5) * ptOf h / fromIntegral ih)
                (ix, iy) = (floor cx, floor cy) :: (Int, Int)
                at k = fromIntegral (BS.index px (3 * (iy * pw + ix) + k)) :: Int
             in if ix < 0 || iy < 0 || ix >= pw || iy >= ph then Nothing else Just (at 0, at 1, at 2)
          alphas = map fromIntegral (samples (alphaBits a) (alphaSamples a)) :: [Int]
          pixels = zip3 [(col, row) | row <- [0 .. ih - 1], col <- [0 .. iw - 1]] (pixelColours img) alphas
      forM [(cr, c, al) | (cr, c, al) <- pixels, al < 255] $ \((col, row), (r, g, b), al) -> do
        got <- maybe (assertFailure ("outside the page: " <> show (ivPath iv, col, row))) pure (renderedAt col row)
        let mix c = (c * al + 255 * (255 - al) + 127) `div` 255
            expected = (mix r, mix g, mix b)
            close (p1, p2, p3) (q1, q2, q3) = all (<= 2) [abs (p1 - q1), abs (p2 - q2), abs (p3 - q3)]
        if al == 0
          then assertEqual (show (ivPath iv, col, row)) (255, 255, 255) got
          else assertBool (show (ivPath iv, col, row, al, expected, got)) (close expected got)
        pure al
    let alphas = concat checked
    assertBool "transparent pixels" (0 `elem` alphas)
    assertBool "half-transparent pixels" (any (\al -> al > 0 && al < 255) alphas)

-- ------------------------------------------------------------------ links

{- | The links of a source, horizontal and vertical, as pdfinfo -url lists
them: the page and the URL of each link annotation, as the source writes
them.
-}
linkTest :: TestTree
linkTest = testCase "the link annotations as pdfinfo -url lists them: the URLs of the source and their pages, horizontal and vertical (docs/adr ADR 0182)" $ do
  tool <- pdfinfoTool
  forM_ tool $ \pdfinfo -> forM_ [horizontalStyle, pdfStyle] $ \style -> withSystemTempDirectory "golem-links" $ \tmp -> do
    let source = "一つめは[link \"https://example.com/a\": リンク]。\n\n二つめは[link \"https://example.org/b?x=1\": 別の]。\n\n" <> fillers 60 <> "三つめは[link \"https://example.com/c\": 次の]。\n"
    pdf <- miniPdf fakeProvider True style source []
    BS.writeFile (tmp </> "out.pdf") pdf
    (code, out, err) <- readProcessWithExitCode pdfinfo ["-url", tmp </> "out.pdf"] ""
    assertEqual (out <> err) ExitSuccess code
    let listed = [(page, url) | l <- drop 1 (lines out), [page, _, url] <- [words l]]
        pages = length (occurrences "/Type /Page " pdf)
    assertBool (show pages) (pages >= 2)
    let pageOf u = [p | (p, u') <- listed, u' == u]
    -- the first two on the first page, the third after the fillers on the last
    (length listed, pageOf "https://example.com/a", pageOf "https://example.org/b?x=1", pageOf "https://example.com/c")
      @?= (3, ["1"], ["1"], [show pages])
