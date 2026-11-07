{- | A run of full-width dashes drawn as one line in the PDF (docs/adr ADR
0172): each dash scaled along the line so that its ink fills an em of
the box, the ends of the lines meeting each other and the ends of the box.
-}
module DoubleDashSpec (doubleDashTests) where

import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Pdf (Shaped (..), Shaping (..))
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import PdfSpec (fontResources)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

-- | Noto Serif JP of the 蟹工船 fixture as the body, and Source Sans Pro of golem-font's tests as the role sans.
dashFonts :: BS.ByteString
dashFonts = "\n[fonts.body]\nja = \"fonts/noto.otf\"\n\n[fonts.sans]\nja = \"fonts/sans.otf\"\n\n[character-styles.s]\nfont = \"sans\"\n"

dashFiles :: IO [(FilePath, BS.ByteString)]
dashFiles = do
  noto <- notoBytes
  sans <- BS.readFile "../golem-font/test/fonts/SourceSansPro-Regular.otf"
  pure [("fonts/noto.otf", noto), ("fonts/sans.otf", sans)]

-- | The fonts of a style whose files are given.
fontsOf :: BS.ByteString -> [(FilePath, BS.ByteString)] -> IO LoadedFonts
fontsOf style files = withSystemTempDirectory "golem-dash" $ \tmp -> do
  writeFiles tmp files
  st <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 style))
  loadFonts realProvider tmp (FileId 0) st [] >>= either (assertFailure . show) pure

-- | The source of a paragraph of 漢, the dashes in a role (body or sans), and 漢.
dashSource :: T.Text -> T.Text -> T.Text
dashSource role d = "漢" <> (if role == "body" then d else "[style s: " <> d <> "]") <> "漢\n"

hex :: Int -> BS.ByteString
hex = BC.pack . printf "%04X"

{- | Checks the lines of a run of dashes in a role, horizontal or vertical:
their ends meet each other and the ends of the box within 1/1000 em, and
across the line they are where an unscaled glyph is, as thick.
-}
checkRun :: Bool -> T.Text -> T.Text -> TestTree
checkRun vertical role d = testCase (T.unpack (role <> " " <> d <> if vertical then " vertical" else " horizontal")) $ do
  files <- dashFiles
  let style = (if vertical then pdfStyle else horizontalStyle) <> dashFonts
  fonts <- fontsOf style files
  pdf <- miniPdf realProvider True style (dashSource role d) files
  content <- BS.concat <$> inflateAll pdf
  resources <- fontResources pdf
  let kan = case lfShape fonts (Shaping "body" vertical [] False) "漢" of
        [g] -> lfCode fonts (shFace g) (shGlyph g)
        other -> error (show other)
      dashes = [(c, g) | c <- T.unpack d, g <- lfShape fonts (Shaping role vertical [] False) (T.singleton c)]
      cids = [lfCode fonts (shFace g) (shGlyph g) | (_, g) <- dashes]
      drawn = [x | x <- drawnGlyphs content, dGlyph x `elem` (kan : cids)]
  map dGlyph drawn @?= [kan] <> cids <> [kan]
  (k1, ds, k2) <- case drawn of
    k1 : rest | (ds, [k2]) <- splitAt (length dashes) rest -> pure (k1, ds, k2)
    other -> assertFailure (show other)
  let size = ptToRational (dSize k1)
      tol = size / 1000
      near what expected got = assertBool (what <> ": " <> show (fromRational expected :: Double, fromRational got :: Double)) (abs (expected - got) <= tol)
      at f = ptToRational . f
      -- each dash: its glyph, its text matrix and the span of its ink along the line
      spans =
        [ (g, matrix, inkSpan)
        | ((_, g), x) <- zip dashes ds,
          let matrix = map ptToRational (dMatrix x)
              (x0, y0, x1, y1) = fromMaybe (error "no ink") (lfInkBox fonts (shFace g) (shGlyph g))
              inkSpan = case (vertical, shTurned g, matrix) of
                (False, _, [a, _, _, _]) -> (at dX x + size * a * x0, at dX x + size * a * x1)
                -- turned: x of the glyph goes down the page
                (True, True, [_, b, _, _]) -> (at dY x + size * b * x0, at dY x + size * b * x1)
                -- upright in Identity-V: the glyph origin is (1/2, 0.88) em from the vertical origin
                (True, False, [_, _, _, dd]) -> (at dY x + size * dd * (y1 - 88 / 100), at dY x + size * dd * (y0 - 88 / 100))
                _ -> error (show matrix)
        ]
      (boxStart, boxEnd)
        | vertical = (at dY k1 - size, at dY k2)
        | otherwise = (at dX k1 + size, at dX k2)
      inks = [i | (_, _, i) <- spans]
  case (inks, reverse inks) of
    ((s0, _) : _, (_, e1) : _) -> do
      near "the start of the first line" boxStart s0
      near "the end of the last line" boxEnd e1
    _ -> assertFailure "no dash"
  forM_ (zip inks (drop 1 inks)) $ \((_, e), (s, _)) -> near "the end of a line and the start of the next" e s
  -- scaled along the line only: across it, as thick and where the unscaled glyph is
  forM_ (zip spans ds) $ \((g, m, _), x) -> case (vertical, shTurned g, m) of
    (False, _, [_, b, c, dd]) -> do
      (b, c, dd) @?= (0, 0, 1)
      at dY x @?= at dY k1
    (True, True, [a, _, c, dd]) -> do
      (a, c, dd) @?= (0, 1, 0)
      near "turned across" (at dX k1 - size * lfEmBoxCentral fonts (shFace g)) (at dX x)
    (True, False, [a, b, c, _]) -> do
      (a, b, c) @?= (1, 0, 0)
      at dX x @?= at dX k1
    _ -> assertFailure (show m)
  -- the text of each glyph is its dash (ToUnicode)
  forM_ (zip dashes ds) $ \((c, _), x) -> do
    let cmaps = [cmap | (n, _, cmap) <- resources, n == dFont x]
    assertBool (show (c, dGlyph x)) (any (\cmap -> ("<" <> hex (dGlyph x) <> "> <" <> hex (fromEnum c) <> ">") `BS.isInfixOf` cmap) cmaps)

doubleDashTests :: [TestTree]
doubleDashTests =
  [ testGroup
      "the lines of a run meet each other and the ends of its box, Noto Serif JP (with a double dash ligature) and Source Sans Pro (without, side bearings on its dash)"
      [checkRun v role d | v <- [False, True], role <- ["body", "sans"], d <- ["\x2014\x2014", "\x2015\x2015", "\x2014\x2015", "\x2014\x2014\x2014"]],
    testCase "the dashes are shaped one by one: Noto Serif JP's ligature is not used" $ do
      files <- dashFiles
      pdf <- miniPdf realProvider True (pdfStyle <> dashFonts) (dashSource "body" "\x2014\x2014") files
      content <- BS.concat <$> inflateAll pdf
      -- glyph 1100 of Noto Serif JP is its double dash (golem-driver ADR 0015); 466 its U+2014
      fonts <- fontsOf (pdfStyle <> dashFonts) files
      let cid = lfCode fonts 0
      assertBool "no ligature" (cid 1100 `notElem` map dGlyph (drawnGlyphs content))
      length (filter ((== cid 466) . dGlyph) (drawnGlyphs content)) @?= 2,
    testCase "the same PDF in parallel and in sequence, and twice" $ do
      files <- dashFiles
      let source = T.concat [dashSource role d | role <- ["body", "sans"], d <- ["\x2014\x2014", "\x2015\x2015\x2015"]]
      forM_ [pdfStyle, horizontalStyle] $ \page -> do
        pdfs <- forM [True, False, True] $ \parallel -> miniPdf realProvider parallel (page <> dashFonts) source files
        assertBool "the same bytes" (and (zipWith (==) pdfs (drop 1 pdfs))),
    testCase "G07101: a dash without ink is drawn unscaled, an em for each, with a notice at the first dash of the run" $
      withSystemTempDirectory "golem-dash" $ \tmp -> do
        let source = "あ[style e: \x2014\x2014]い\n\nう\x2014\x2014え\n" :: T.Text
            style = horizontalStyle <> fakeBody <> "\n[fonts.inkless]\nja = \"fonts/b.otf\"\n\n[character-styles.e]\nfont = \"inkless\"\n"
        writeProject tmp miniManifest style source fakeFontFiles
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
        let g07101 = [d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G07101"]
        [(diagSeverity d, spanStart (diagSpan d), spanEnd (diagSpan d) - spanStart (diagSpan d)) | d <- g07101] @?= [(Notice, o, 6) | o <- take 1 (offsetsIn "\x2014\x2014" source)]
        map diagMessage g07101 @?= ["ダッシュの字形に線がないので、二倍ダッシュの線をつながずに描きます: U+2014（fonts/b.otf）"]
        [d | d <- brDiagnostics r, isError d] @?= []
        pdf <- BS.readFile (tmp </> "build/pdf/urn-uuid-11111111-2222-4333-8444-555555555555.pdf")
        content <- BS.concat <$> inflateAll pdf
        let drawn = drawnGlyphs content
            size = maybe 0 (ptToRational . dSize) (listToMaybe drawn)
            dash = [x | x <- drawn, dGlyph x == 0x2014]
            first = [x | x <- drawn, dGlyph x == fromEnum 'あ']
        -- the inkless dashes: unscaled, at the start of each em of the box
        case (first, take 2 dash) of
          ([a], ds@[_, _]) -> do
            map dMatrix ds @?= replicate 2 ["1", "0", "0", "1"]
            map (ptToRational . dX) ds @?= [ptToRational (dX a) + size, ptToRational (dX a) + 2 * size]
          other -> assertFailure (show other)
        -- the dashes of the body have ink and are scaled
        assertBool "scaled" (all ((/= ["1", "0", "0", "1"]) . dMatrix) (drop 2 dash))
  ]
