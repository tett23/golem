{- | Superscript and subscript in the PDF, HTML and plain text
(docs/adr/0269): the method of each range, its size and shift, the
measures and the baselines. These are the tests of golem-typeset that need
golem-layout and the fonts.
-}
module ScriptsSpec (scriptsTests) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.Length (Sp (..), zwToSp)
import Golem.Project.Files (diskFiles)
import Golem.Project.Position (Position (..))
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..), Shaped (..), Shaping (..), shapingOf)
import Golem.Typeset.FontProvider (golemFontProvider)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | Source Sans Pro (Latin) and Noto Serif JP (Japanese).
fontFiles :: IO [(FilePath, BS.ByteString)]
fontFiles = do
  (sans, _) <- realLatinFonts
  noto <- notoBytes
  pure [("fonts/sans.otf", sans), ("fonts/noto.otf", noto)]

-- | The body in Noto Serif JP and Source Sans Pro, horizontal or vertical.
styleOf :: Bool -> BS.ByteString
styleOf vertical = (if vertical then pdfStyle else horizontalStyle) <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\nlatin = \"fonts/sans.otf\"\n"

layoutOf :: Bool -> Text -> IO PdfLayout
layoutOf vertical source = do
  files <- fontFiles
  snd <$> (layoutMiniFonts golemFontProvider miniManifest (styleOf vertical) source files >>= either (assertFailure . show) pure)

fontsOf :: Bool -> IO LoadedFonts
fontsOf vertical = withSystemTempDirectory "golem-scripts" $ \tmp -> do
  files <- fontFiles
  writeFiles tmp files
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 (styleOf vertical)))
  loadFonts golemFontProvider (diskFiles tmp) (FileId 0) style [] >>= either (assertFailure . show) pure

boxesOf :: PdfLayout -> [(Sp, BoxContent)]
boxesOf pl = [(w, c) | sl <- Map.elems (plLines pl), Box w c <- lineItems (slLine sl)]

scriptBoxes :: PdfLayout -> [(Sp, BoxContent)]
scriptBoxes = filter ((/= PositionNormal) . lkPosition . bcLook . snd) . boxesOf

-- | 10pt, the grid of 'horizontalStyle'.
ten :: Sp
ten = 655360

scriptsTests :: TestTree
scriptsTests =
  testGroup
    "superscript and subscript (docs/adr/0269)"
    [ testCase "I1, I2: digits of Source Sans Pro are set in its glyphs, at the nominal size, sups last" $ do
        pl <- layoutOf False "m[style superscript: 2]\n"
        fonts <- fontsOf False
        case scriptBoxes pl of
          [(_, c)] -> do
            let lk = bcLook c
            (lkScriptGlyphs lk, lkSize lk, lkBaselineShift lk) @?= (True, ten, 0)
            fmap (last . shExtra) (Just (shapingOf (lfRoleFeatures fonts) False lk '2')) @?= Just "sups"
          other -> assertFailure (show (map (bcText . snd) other)),
      testCase "I1, I2: one character the font does not replace sets the whole range by synthesis" $ do
        pl <- layoutOf False "x[style superscript: 2あ]\n"
        map (\(_, c) -> (lkScriptGlyphs (bcLook c), lkSize (bcLook c))) (scriptBoxes pl) @?= replicate 2 (False, Sp ((7 * unSp ten) `div` 12)),
      testCase "I1, I2: Japanese of Noto Serif JP, which has no sups, is synthesis" $ do
        pl <- layoutOf False "漢[style subscript: あ]\n"
        map (\(_, c) -> lkScriptGlyphs (bcLook c)) (scriptBoxes pl) @?= [False],
      testCase "I3: synthesis at 10pt: 7/12 of the size, moved by a third up, or down for subscript" $ do
        pl <- layoutOf False "漢[style superscript: あ]漢[style subscript: あ]\n"
        map (\(_, c) -> (lkSize (bcLook c), lkBaselineShift (bcLook c))) (scriptBoxes pl)
          @?= [(Sp ((7 * unSp ten) `div` 12), Sp (unSp ten `div` 3)), (Sp ((7 * unSp ten) `div` 12), negate (Sp (unSp ten `div` 3)))],
      testCase "I3: in vertical text the shift is right for superscript and left for subscript (the baseline shift)" $ do
        pl <- layoutOf True "漢[style superscript: あ]漢[style subscript: あ]\n"
        map (\(_, c) -> signum (lkBaselineShift (bcLook c))) (scriptBoxes pl) @?= [1, -1],
      testCase "I8: the width of each box is the advance of its glyphs as drawn" $ do
        pl <- layoutOf False "m[style superscript: 2]x[style superscript: 2あ]漢[style subscript: か]\n"
        fonts <- fontsOf False
        let measured lk t = zwToSp (lkSize lk) (sum [shAdvance g | g <- lfShape fonts (shapingOf (lfRoleFeatures fonts) False lk (T.head t)) t])
        mapM_ (\(w, c) -> assertEqual (T.unpack (bcText c)) (measured (bcLook c) (bcText c)) (w - fromIntegral (lkTracking (bcLook c)))) (scriptBoxes pl),
      testCase "I7: the baselines are those of the same text without the ranges" $ do
        a <- layoutOf False "漢字[style superscript: 2]と漢字[style subscript: 2]と漢字\n"
        b <- layoutOf False "漢字2と漢字2と漢字\n"
        map (\sl -> (lineTarget (slLine sl), slIndent sl)) (Map.elems (plLines a)) @?= map (\sl -> (lineTarget (slLine sl), slIndent sl)) (Map.elems (plLines b))
        Map.keys (plLines a) @?= Map.keys (plLines b),
      {- the reading of a ruby in a range of synthesis is half the outer
      size, not of the shrunk base, and takes no position (ADR 0269, ルビ、圏点、注の印との関係) -}
      testCase "I3, I8: ruby in a range of synthesis: its reading measured and drawn at half the outer size" $ do
        let ruby = "[ruby: 漢|かんじ]"
            inRange = "漢[style superscript: " <> ruby <> "]\n"
            outside = "漢" <> ruby <> "\n"
            rubyWidths pl = [w | (w, c) <- boxesOf pl, "|" `T.isInfixOf` bcText c]
            sizesOf source = do
              files <- fontFiles
              pdf <- miniPdf golemFontProvider True (styleOf False) source files
              map dSize . drawnGlyphs . BS.concat <$> inflateAll pdf
        a <- layoutOf False inRange
        b <- layoutOf False outside
        rubyWidths a @?= rubyWidths b
        sa <- sizesOf inRange
        sb <- sizesOf outside
        -- the character before, the base, then the three characters of the reading
        (length sa, drop 2 sa) @?= (5, drop 2 sb),
      testCase "G08103 is not reported for sups and subs Golem adds" $ withSystemTempDirectory "golem-scripts" $ \tmp -> do
        files <- fontFiles
        writeProject tmp miniManifest (styleOf False) "漢[style superscript: あ]m[style superscript: 2]\n" files
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = golemFontProvider}
        [d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G08103"] @?= []
        assertBool "a PDF" (any (".pdf" `isSuffixOf`) (brWritten r)),
      testCase "plain text writes the characters of a range as they are" $ withSystemTempDirectory "golem-scripts" $ \tmp -> do
        writeProject tmp (miniManifest <> "[targets.text]\n") (styleOf False) "m[style superscript: 2]\n" []
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        t <- TIO.readFile (tmp </> "build/text/horizontal/a.txt")
        assertBool (T.unpack t) ("m2" `T.isInfixOf` t),
      testCase "HTML: based-on superscript is sup with its class, a regex style too" $ do
        let style = "[character-styles.x]\nbased-on = \"superscript\"\n\n[paragraph-styles.body]\nregex-styles = [{ pattern = '[0-9]', style = \"subscript\" }]\n"
        (page, _) <- htmlMini style "[style x: a]H2O\n"
        assertBool (T.unpack page) ("<sup class=\"cs-x\">a</sup>" `T.isInfixOf` page)
        assertBool (T.unpack page) ("H<sub>2</sub>O" `T.isInfixOf` page)
    ]
