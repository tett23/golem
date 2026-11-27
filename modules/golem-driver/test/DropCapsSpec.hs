-- | Drop caps through the ordinary evaluation and layout pipeline (root ADR 0465).
module DropCapsSpec (dropCapsTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.Length (Sp (..))
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..), Shaped (..), Shaping (..))
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

fs :: Sp
fs = 655360

dropStyle :: BS.ByteString -> BS.ByteString
dropStyle keys = horizontalStyle <> "\n[paragraph-styles.title]\nfirst-line-indent = \"1zw\"\n" <> keys

linesOf :: PdfLayout -> [SetLine]
linesOf = Map.elems . plLines

setLines :: PdfLayout -> [(Sp, [Item])]
setLines pl = [(slIndent sl, lineItems (slLine sl)) | sl <- linesOf pl]

buildDiagnostics :: Bool -> BS.ByteString -> T.Text -> IO [Diagnostic]
buildDiagnostics check style source = withSystemTempDirectory "golem-drop" $ \tmp -> do
  writeProject tmp miniManifest style source []
  brDiagnostics <$> build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optCheckOnly = check}

dropCapsTests :: [TestTree]
dropCapsTests =
  [ testCase "root ADR 0465 I2, I4: three-line drop cap shortens three lines and suppresses first-line indent" $ do
      (_, pl) <- layoutOk (dropStyle "drop-lines = 3\n") ("@style title\n" <> T.replicate 70 "あ" <> "\n") []
      let ls = linesOf pl
      assertBool "at least four lines" (length ls > 3)
      take 4 (map slIndent ls) @?= [4 * fs, 4 * fs, 4 * fs, 0]
      take 4 (map (lineTarget . slLine) ls) @?= [8 * fs, 8 * fs, 8 * fs, 12 * fs]
      let caps = [bcLook c | sl <- ls, Box _ c <- lineItems (slLine sl), lkSize (bcLook c) > fs]
      map lkSize caps @?= [4 * fs],
    testCase "root ADR 0465 I4: right alignment does not move the initial into later body lines" $ do
      (_, pl) <- layoutOk (dropStyle "drop-lines = 3\nalign = \"right\"\n") "@style title\nあいう\n" []
      let capStarts = [slIndent sl + bcPadStart c | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), lkSize (bcLook c) > fs]
      capStarts @?= [0],
    testCase "root ADR 0465 I3: a one-character paragraph occupies the requested three lines" $ do
      (_, pl) <- layoutOk (dropStyle "drop-lines = 3\n") "@style title\nあ\n" []
      length (linesOf pl) @?= 3,
    testCase "root ADR 0465 I3: the three initial rows move together when only two rows remain" $ do
      let style = replaceIn "lines = 30" "lines = 5" (dropStyle "drop-lines = 3\n[paragraph-styles.body]\nfirst-line-indent = \"0zw\"\n")
      (_, pl) <- layoutOk style (T.replicate 36 "先" <> "\n\n@style title\nあ\n") []
      let positions = Map.fromList [(ident, (poNumber page, poColumn page)) | page <- plPages pl, (_, SLine ident) <- poSlots page]
      map (`Map.lookup` positions) [3, 4, 5] @?= replicate 3 (Just (2, 0)),
    testCase "root ADR 0465 I2: one row uses the ordinary glyph size but has no first-line indent" $ do
      (_, pl) <- layoutOk (dropStyle "drop-lines = 1\n") "@style title\nあいう\n" []
      take 1 (map slIndent (linesOf pl)) @?= [fs]
      [lkSize (bcLook c) | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), not (T.null (bcText c))] @?= [fs, fs, fs],
    testCase "root ADR 0465 I2, I3: kept source lines apply the cap only to their first part" $ do
      (_, pl) <- layoutOk (dropStyle "drop-lines = 3\nline-breaks = \"keep\"\n") "@style title\n  あ\n  いうえ\n" []
      map slIndent (linesOf pl) @?= [4 * fs, 4 * fs, 4 * fs, fs]
      length [() | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), lkSize (bcLook c) > fs] @?= 1,
    testCase "root ADR 0465 I2: the actual initial face supplies cap height, ignoring initial-style size" $ do
      let shape request text = [if shRole request == "heading" && text == "H" then glyph {shFace = 0} else glyph | glyph <- lfShape fakeFonts request text]
          fonts = fakeFonts {lfShape = shape, lfCapHeight = \face -> if face == 4 then 1 / 2 else 7 / 10}
          provider = FontProvider (\_ _ _ _ -> pure (Right fonts))
          style = dropStyle "drop-lines = 3\ninitial-style = \"cap\"\n[character-styles.cap]\nfont = \"heading\"\nsize = \"100pt\"\n[fonts.body]\nja = \"fonts/b.otf\"\n[fonts.heading]\nlatin = \"fonts/h.otf\"\n"
      laid <- layoutMiniFonts provider miniManifest style "@style title\nAbcd\n" fakeFontFiles
      (_, pl) <- either (assertFailure . show) pure laid
      [lkSize (bcLook c) | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), bcText c == "A"] @?= [74 * 65536],
    testCase "root ADR 0465 I2: drop-gap is added to the advance on each shortened line" $ do
      (_, pl) <- layoutOk (dropStyle "drop-lines = 2\ndrop-gap = \"2pt\"\n") ("@style title\n" <> T.replicate 40 "あ" <> "\n") []
      take 3 (map slIndent (linesOf pl)) @?= [Sp 1769472, Sp 1769472, 0],
    testCase "root ADR 0465 I1, I7: list items ignore drop-lines and retain their lines" $ do
      let src = "@style title\n  - あいうえおかきくけこさしすせそ\n"
      (_, dropped) <- layoutOk (dropStyle "drop-lines = 3\n") src []
      (_, plain) <- layoutOk (dropStyle "") src []
      setLines dropped @?= setLines plain,
    testCase "root ADR 0465 I5: unsupported initials warn once per paragraph, not for a list item" $ do
      ds <- buildDiagnostics True (dropStyle "drop-lines = 2\n") "@style title\n[ruby: 漢 | かん]です。\n\n@style title\n[tcy: 12]月。\n\n@style title\n  - [ruby: 字 | じ]です。\n"
      length (diagnosticsOf "G07143" ds) @?= 2,
    testCase "root ADR 0465 I2: HTML writes initial-letter and gap with excluded paragraphs marked" $ withSystemTempDirectory "golem-drop-html" $ \tmp -> do
      writeProject tmp (miniManifest <> "\n[targets.html]\n") (dropStyle "drop-lines = 3\ndrop-gap = \"2pt\"\n") "@style title\nあいうえお\n\n@style title\n  - あいうえお\n" []
      r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFonts = fakeProvider}
      filter isError (brDiagnostics r) @?= []
      css <- TIO.readFile (tmp </> "build/html/style.css")
      assertBool "initial-letter rule" ("p.ps-title:not([data-no-drop])::first-letter { initial-letter: 3; margin-inline-end: 2pt; }" `T.isInfixOf` css)
      page <- TIO.readFile (tmp </> "build/html/a.html")
      T.count "data-no-drop" page @?= 1
  ]
