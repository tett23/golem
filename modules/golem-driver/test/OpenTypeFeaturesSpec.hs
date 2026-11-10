{- | The OpenType features of character and paragraph styles in the PDF
(docs/adr/0268): the order of the features a character is shaped with,
the measures and the glyphs of a range, and G08103 for a feature the font
has not. These are the tests of golem-typeset that need golem-layout and
the fonts, which golem-typeset's own tests do not depend on.
-}
module OpenTypeFeaturesSpec (openTypeFeaturesTests) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Kerning (..), Look (..), plainLook)
import Golem.Length (Sp (..), zwToSp)
import Golem.Project.Feature (parseFeature)
import Golem.Project.Files (diskFiles)
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..), Shaped (..), Shaping (..), shapingOf)
import Golem.Typeset.FontProvider (golemFontProvider)
import Support
import System.Directory (doesDirectoryExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The look of the body at 10pt with features.
featured :: [Text] -> Look
featured fs = (plainLook "body" 655360) {lkFeatures = fs}

-- | The last value of a tag in a list of features.
lastValue :: Text -> [Text] -> Maybe Int
lastValue t fs = lookup t (reverse (mapMaybe parseFeature fs))

-- | Source Sans Pro (Latin) and Noto Serif JP (Japanese), as fonts/sans.otf and fonts/noto.otf.
fontFiles :: IO [(FilePath, BS.ByteString)]
fontFiles = do
  (sans, _) <- realLatinFonts
  noto <- notoBytes
  pure [("fonts/sans.otf", sans), ("fonts/noto.otf", noto)]

-- | The fonts of a style.toml, loaded from those files.
fontsOf :: Text -> IO LoadedFonts
fontsOf src = withSystemTempDirectory "golem-features" $ \tmp -> do
  files <- fontFiles
  writeFiles tmp files
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) src)
  loadFonts golemFontProvider (diskFiles tmp) (FileId 0) style [] >>= either (assertFailure . show) pure

-- | Builds a one-chapter project to PDF with the real fonts: every diagnostic, and whether build/pdf is there.
buildWith :: Profile -> BS.ByteString -> Text -> IO ([Diagnostic], Bool)
buildWith profile style source = withSystemTempDirectory "golem-features" $ \tmp -> do
  files <- fontFiles
  writeProject tmp miniManifest style source files
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = golemFontProvider, optProfile = profile}
  dir <- doesDirectoryExist (tmp </> "build/pdf")
  pure (brDiagnostics r, dir && any (".pdf" `isSuffixOf`) (brWritten r))

g08103 :: [Diagnostic] -> [Diagnostic]
g08103 = filter ((== DiagnosticCode "G08103") . diagCode)

-- | Noto Serif JP alone as the body role.
notoStyle :: BS.ByteString
notoStyle = horizontalStyle <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\n\n[character-styles.sc]\nfeatures = [\"smcp\"]\n\n[character-styles.off]\nfeatures = [\"-smcp\"]\n"

-- | Noto Serif JP and Source Sans Pro as the body role.
bothStyle :: BS.ByteString
bothStyle = horizontalStyle <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\nlatin = \"fonts/sans.otf\"\n\n[character-styles.sc]\nfeatures = [\"smcp\"]\n"

openTypeFeaturesTests :: TestTree
openTypeFeaturesTests =
  testGroup
    "OpenType features of styles in the PDF (docs/adr/0268)"
    [ testCase "I2: the features of the look come after the role's and before Golem's" $ do
        shExtra (shapingOf (const ["palt"]) False (featured ["onum", "smcp"]) 'a') @?= ["onum", "smcp"]
        shExtra (shapingOf (const []) False ((featured ["onum"]) {lkKerning = KernNone}) 'a') @?= ["onum", "-kern"]
        shExtra (shapingOf (const []) False ((featured ["onum"]) {lkProportional = True}) 'あ') @?= ["onum", "palt"],
      testCase "I2: palt of a style loses to japanese-equal-width, as the role's does" $ do
        let extra = shExtra (shapingOf (const []) False ((featured ["palt"]) {lkKerning = KernJapaneseEqualWidth}) 'あ')
        lastValue "palt" extra @?= Just 0
        extra @?= ["-kern", "-vkrn", "-palt", "-vpal"],
      testCase "I2: halt of a style is turned off on JLReq's punctuation only" $ do
        let extra c = shExtra (shapingOf (const []) False (featured ["halt"]) c)
        lastValue "halt" (extra '「') @?= Just 0
        extra '「' @?= ["-palt", "-vpal", "-halt"]
        extra 'あ' @?= ["halt"]
        -- without halt the punctuation is shaped as before
        shExtra (shapingOf (const []) False (featured []) '「') @?= ["-palt", "-vpal"],
      testCase "I2: halt, vhal, chws and vchw of the role are turned off on JLReq's punctuation" $ do
        shExtra (shapingOf (const ["chws", "vhal"]) True (featured []) '」') @?= ["-palt", "-vpal", "-vhal", "-chws"]
        shExtra (shapingOf (const ["chws", "-chws"]) True (featured []) '」') @?= ["-palt", "-vpal"],
      testCase "I1: a range in smcp is measured and drawn with smcp" $ do
        let style = horizontalStyle <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\nlatin = \"fonts/sans.otf\"\n\n[character-styles.sc]\nfeatures = [\"smcp\"]\n"
        files <- fontFiles
        (_, pl) <- layoutMiniFonts golemFontProvider miniManifest style "ab [style sc: cdef] gh\n" files >>= either (assertFailure . show) pure
        fonts <- fontsOf (TE.decodeUtf8 style)
        let boxes = [(w, c) | sl <- Map.elems (plLines pl), Box w c <- lineItems (slLine sl)]
            measured lk t = zwToSp (lkSize lk) (sum [shAdvance g | g <- lfShape fonts (shapingOf (lfRoleFeatures fonts) False lk (T.head t)) t])
        case [(w, c) | (w, c) <- boxes, bcText c == "cdef"] of
          [(w, c)] -> do
            lkFeatures (bcLook c) @?= ["smcp"]
            w @?= measured (bcLook c) "cdef"
            assertBool "smcp changes the width" (w /= measured (bcLook c) {lkFeatures = []} "cdef")
          other -> assertFailure (show (map (bcText . snd) other))
        mapM_ (\(w, c) -> w @?= measured (bcLook c) (bcText c)) [(w, c) | (w, c) <- boxes, not (T.null (bcText c))],
      testCase "I1, I9: a range in a character style of @style-def with features is set as one of style.toml" $ do
        let fontsToml = horizontalStyle <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\nlatin = \"fonts/sans.otf\"\n"
            source = "ab [style sc: cdef] gh\n"
        files <- fontFiles
        let boxesOf style src = do
              (_, pl) <- layoutMiniFonts golemFontProvider miniManifest style src files >>= either (assertFailure . show) pure
              pure [(w, bcText c, lkFeatures (bcLook c)) | sl <- Map.elems (plLines pl), Box w c <- lineItems (slLine sl), not (T.null (bcText c))]
        toml <- boxesOf (fontsToml <> "\n[character-styles.sc]\nfeatures = [\"smcp\", \"-liga\"]\n") source
        local <- boxesOf fontsToml ("@style-def character sc features=\"smcp,-liga\"\n\n" <> source)
        plain <- boxesOf fontsToml ("@style-def character sc\n\n" <> source)
        [f | (_, t, f) <- toml, t == "cdef"] @?= [["smcp", "-liga"]]
        [f | (_, t, f) <- plain, t == "cdef"] @?= [[]]
        assertBool "smcp changes the width" (toml /= plain)
        local @?= toml,
      testCase "every feature is shaped, the 33rd too: 32 of the role and smcp of a style" $ do
        let padding = ["-ss" <> T.justifyRight 2 '0' (T.pack (show n)) | n <- [1 .. 20 :: Int]] <> ["-cv" <> T.justifyRight 2 '0' (T.pack (show n)) | n <- [1 .. 12 :: Int]]
            role = "[fonts.body]\nlatin = \"fonts/sans.otf\"\nfeatures = [" <> T.intercalate ", " ["\"" <> p <> "\"" | p <- padding] <> "]\n"
        fonts <- fontsOf role
        let glyphs extra = map shGlyph (lfShape fonts (Shaping "body" False extra False) "abc")
        length (lfRoleFeatures fonts "body") @?= 32
        assertBool "smcp, the 33rd, changes the glyphs" (glyphs ["smcp"] /= glyphs []),
      testCase "I8: smcp on a range of Noto Serif JP alone is one G08103, once for two places" $ do
        (ds, _) <- buildWith Dev notoStyle "[style sc: 漢字] と [style sc: かな]\n"
        case g08103 ds of
          [d] -> do
            diagSeverity d @?= Warning
            diagMessage d @?= "フォント fonts/noto.otf に OpenType の機能 smcp がありません"
            diagFacts d @?= [("font", FactText "fonts/noto.otf"), ("feature", FactText "smcp"), ("pdf-pages", FactInts [1])]
          other -> assertFailure (show other),
      testCase "I8: G08103 is at the first value of style.toml that turns the feature on" $ do
        (ds, _) <- buildWith Dev notoStyle "[style sc: 漢字]\n"
        let src = TE.decodeUtf8 notoStyle
        map (spanStart . diagSpan) (g08103 ds) @?= [BS.length (TE.encodeUtf8 (fst (T.breakOn "\"smcp\"" src)))],
      testCase "I8: none for a range of Japanese and Latin whose Latin face has smcp" $ do
        (ds, _) <- buildWith Dev bothStyle "[style sc: 漢字abc]\n"
        g08103 ds @?= [],
      testCase "I8: a range of Japanese alone with the Latin face having smcp is reported" $ do
        (ds, _) <- buildWith Dev bothStyle "[style sc: 漢字]\n"
        map diagFacts (g08103 ds) @?= [[("font", FactText "fonts/noto.otf"), ("feature", FactText "smcp"), ("pdf-pages", FactInts [1])]],
      testCase "I7: a feature turned off is not reported" $ do
        (ds, _) <- buildWith Dev notoStyle "[style off: 漢字]\n"
        g08103 ds @?= [],
      testCase "G08103: a warning in dev with the PDF, an error in prod without it" $ do
        (dev, devPdf) <- buildWith Dev notoStyle "[style sc: 漢字]\n"
        map diagSeverity (g08103 dev) @?= [Warning]
        assertBool "the PDF in dev" devPdf
        (prod, prodPdf) <- buildWith Prod notoStyle "[style sc: 漢字]\n"
        map diagSeverity (g08103 prod) @?= [Error]
        assertBool "no PDF in prod" (not prodPdf),
      testCase "G08103: none without features" $ do
        (ds, _) <- buildWith Dev bothStyle "漢字abc\n"
        g08103 ds @?= [],
      testCase "a style without features shapes as before: the plain look's features are empty" $
        lkFeatures (plainLook "body" (Sp 655360)) @?= []
    ]
