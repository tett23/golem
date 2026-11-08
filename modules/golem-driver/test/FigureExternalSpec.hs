{- | The figures that other tools wrote, in
test/fixtures/figures-external (docs/adr ADR 0232): placed or refused as
the README says, the PDFs Golem makes of them pass qpdf --check, and the
figure placed at its own size looks like its page in pdftoppm.
-}
module FigureExternalSpec (figureExternalTests, meanDifference) where

import Control.Monad (forM, forM_, unless)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isSpace)
import Data.Text qualified as T
import Golem.Driver
import Golem.Length (Sp (..))
import Golem.Pdf (ImportError (..), importErrorText)
import Golem.Pdf.Rect (Rect (..))
import Golem.Preflight.View (ImageView (..), PageView (..), View (..))
import Golem.Syntax
import Support
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..))
import System.FilePath (takeExtension, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

-- | What Golem does with a figure of a tool.
data Expect
  = -- | placed without a diagnostic
    Placed
  | -- | refused by G08010 with the wording of a constructor of golem-pdf ADR 0008
    Refused !ImportError
  | -- | refused with these codes, G08011 first
    OutOfRange ![T.Text]

-- | The rows of the README: the file and what Golem does with it.
samples :: [(FilePath, Expect)]
samples =
  [ ("inkscape.pdf", Placed),
    ("libreoffice-draw.pdf", Placed),
    ("chromium-print.pdf", Placed),
    ("matplotlib.pdf", Placed),
    ("pdftex.pdf", Placed),
    ("luatex.pdf", Placed),
    ("pdftex-spot-color.pdf", Refused SpotColor),
    ("inkscape.svg", Placed),
    ("inkscape-filter.svg", OutOfRange ["G08011"]),
    ("drawio.svg", OutOfRange ["G08011"]),
    ("drawio-foreign-object.svg", OutOfRange ["G08011"]),
    -- written by the maintainer at the release of v1.0.0; skipped until then
    ("illustrator.pdf", Placed),
    ("illustrator.svg", Placed)
  ]

dir :: FilePath
dir = "test/fixtures/figures-external"

-- | The source of a chapter with the figure at 120pt, the measure of horizontalStyle.
figureSource :: FilePath -> T.Text
figureSource file =
  "# 図\n\n図版。\n\n@figure images/"
    <> T.pack file
    <> (if takeExtension file == ".pdf" then " web=images/web.png" else "")
    <> " alt=\"図\" width=120pt\n"

-- | The files of the project of a figure: the figure and the image of the web.
figureFiles :: FilePath -> IO [(FilePath, BS.ByteString)]
figureFiles file = do
  bytes <- BS.readFile (dir </> file)
  web <- BS.readFile "test/fixtures/figures/images/gray.png"
  pure [("images" </> file, bytes), ("images/web.png", web)]

-- | The samples whose file is here.
present :: IO [(FilePath, Expect)]
present = filterMIO (\(f, _) -> doesFileExist (dir </> f)) samples
  where
    filterMIO p = fmap concat . mapM (\x -> (\ok -> [x | ok]) <$> p x)

figureExternalTests :: [TestTree]
figureExternalTests =
  [ testCase "the samples of the tools are placed or refused as the README says" $ do
      rows <- present
      assertBool "samples" (length rows >= 11)
      forM_ rows $ \(file, expect) -> do
        files <- figureFiles file
        (ds, pdf) <- withSystemTempDirectory "golem-external" $ \tmp -> do
          writeProject tmp miniManifest horizontalStyle (figureSource file) files
          r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
          pdf <- mapM BS.readFile (take 1 (filter ((== ".pdf") . takeExtension) (brWritten r)))
          pure (brDiagnostics r, pdf)
        let codes = [c | DiagnosticCode c <- map diagCode ds]
        case expect of
          Placed -> do
            assertEqual file [] codes
            maybe (assertFailure (file <> ": no PDF")) qpdfCheck (headMaybe pdf)
          Refused e -> do
            assertEqual file ["G08010"] codes
            assertBool (file <> ": " <> show (map diagMessage ds)) (all ((importErrorText e `T.isInfixOf`) . diagMessage) ds)
          OutOfRange cs -> assertEqual file cs codes,
    testCase "the README names every sample" $ do
      readme <- BS.readFile (dir </> "README.md")
      forM_ samples $ \(file, _) -> assertBool file (BC.pack ("`" <> file <> "`") `BS.isInfixOf` readme),
    testCase "each PDF placed at its own size looks like its page in pdftoppm (docs/adr ADR 0232)" $ do
      tool <- pdftoppmTool
      forM_ tool $ \pdftoppm -> do
        rows <- present
        diffs <- forM [f | (f, Placed) <- rows, takeExtension f == ".pdf"] $ \file -> withSystemTempDirectory "golem-external" $ \tmp -> do
          files <- figureFiles file
          writeProject tmp miniManifest horizontalStyle (figureSource file) files
          p <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}
          v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
          pdf <- maybe (assertFailure "no PDF") pure (prPdf p)
          BS.writeFile (tmp </> "book.pdf") pdf
          (pv, iv) <- case [(pv, iv) | pv <- vwPages v, iv <- pvImages pv] of
            [x] -> pure x
            other -> assertFailure (show (length other) <> " figures")
          -- the page of the figure as it is, at 144 dpi
          original <- render pdftoppm (dir </> file) (tmp </> "original") ["-r", "144"]
          let (ow, oh, _) = original
              Rect x y w h = ivRect iv
              Rect _ _ _ th = pvTrim pv
              -- the resolution at which the placed figure has as many pixels as the original
              dpi = fromIntegral ow * 72 / ptOf w :: Double
              left = round (ptOf x * dpi / 72) :: Int
              top = round ((ptOf th - ptOf y - ptOf h) * dpi / 72) :: Int
          placed <- render pdftoppm (tmp </> "book.pdf") (tmp </> "placed") ["-r", printf "%.4f" dpi, "-f", show (pvIndex pv), "-l", show (pvIndex pv), "-x", show left, "-y", show top, "-W", show ow, "-H", show oh]
          let d = meanDifference original placed
          pure (file, d)
        -- the threshold is the largest mean difference measured on the samples (docs/adr ADR 0232), with room
        let over = [(f, d) | (f, d) <- diffs, d > threshold]
        unless (null over) $ assertFailure (show diffs)
        assertBool (show diffs) (length diffs >= 6)
  ]
  where
    ptOf (Sp s) = fromIntegral s / 65536 :: Double
    headMaybe = \case
      x : _ -> Just x
      [] -> Nothing

{- | The largest mean difference of a channel, in 0 to 255, between a
sample and the figure placed: measured as at most 2.56 on the samples (LibreOffice Draw; 0.58 to 2.04 for the others)
(docs/adr ADR 0232; anti-aliasing at the edges and the colour of DeviceRGB
written as sRGB), so twice that.
-}
threshold :: Double
threshold = 5

-- | Renders a page with pdftoppm to a PPM and reads it: width, height, pixels.
render :: FilePath -> FilePath -> FilePath -> [String] -> IO (Int, Int, BS.ByteString)
render pdftoppm pdf out args = do
  (code, o, e) <- readProcessWithExitCode pdftoppm (args <> ["-singlefile", pdf, out]) ""
  assertEqual (o <> e) ExitSuccess code
  bytes <- BS.readFile (out <> ".ppm")
  maybe (assertFailure ("not a PPM: " <> out)) pure (readPpm bytes)

-- | A P6 PPM: its width, height and the bytes of its pixels.
readPpm :: BS.ByteString -> Maybe (Int, Int, BS.ByteString)
readPpm b = do
  rest0 <- BS.stripPrefix "P6" b
  (w, rest1) <- BC.readInt (BC.dropWhile isSpace rest0)
  (h, rest2) <- BC.readInt (BC.dropWhile isSpace rest1)
  (_, rest3) <- BC.readInt (BC.dropWhile isSpace rest2)
  Just (w, h, BS.drop 1 rest3)

-- | The mean absolute difference of the channels of two images of one size; the largest when the sizes differ.
meanDifference :: (Int, Int, BS.ByteString) -> (Int, Int, BS.ByteString) -> Double
meanDifference (w1, h1, a) (w2, h2, b)
  | w1 /= w2 || h1 /= h2 || BS.length a /= BS.length b || BS.null a = 255
  | otherwise = fromIntegral (sum (BS.zipWith (\p q -> abs (fromIntegral p - fromIntegral q :: Int)) a b)) / fromIntegral (BS.length a)
