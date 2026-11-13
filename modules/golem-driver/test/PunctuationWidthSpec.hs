{- | Japanese punctuation in full-width glyphs by default, the boxes of
punctuation narrower than full width, punctuation-width, and G07126
(docs/adr/0302). These are the tests of golem-typeset that need
golem-layout and the fonts, which golem-typeset's own tests do not depend on.
-}
module PunctuationWidthSpec (punctuationWidthTests) where

import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Kerning (..), Look (..), plainLook)
import Golem.Length (Sp (..))
import Golem.Project.Feature (parseFeature)
import Golem.Project.Files (diskFiles)
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..), Shaped (..), Shaping (..), shapingForFonts, shapingOf)
import Golem.Typeset.FontProvider (golemFontProvider)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The body at 10pt with the features of its styles and punctuation-width.
lookWith :: [Text] -> Bool -> Look
lookWith fs full = (plainLook "body" 655360) {lkFeatures = fs, lkFullWidthPunctuation = full}

-- | The last value of a tag in a list of features.
lastValue :: Text -> [Text] -> Maybe Int
lastValue t fs = lookup t (reverse (mapMaybe parseFeature fs))

-- | The features a character is shaped with: the role's, then the look's and Golem's.
shapedWith :: [Text] -> Bool -> Look -> Char -> [Text]
shapedWith role vertical lk c = role <> shExtra (shapingOf (const role) vertical lk c)

-- | Noto Serif JP as fonts/noto.otf and Source Serif as fonts/serif.ttf.
fontFiles :: IO [(FilePath, BS.ByteString)]
fontFiles = do
  (_, serif) <- realLatinFonts
  noto <- notoBytes
  pure [("fonts/noto.otf", noto), ("fonts/serif.ttf", serif)]

-- | The fonts of a style.toml, loaded from those files.
fontsOf :: BS.ByteString -> IO LoadedFonts
fontsOf src = withSystemTempDirectory "golem-punct" $ \tmp -> do
  files <- fontFiles
  writeFiles tmp files
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 src))
  loadFonts golemFontProvider (diskFiles tmp) (FileId 0) style [] >>= either (assertFailure . show) pure

-- | The page of a vertical book of the tests.
verticalPage :: BS.ByteString
verticalPage = pdfStyle

-- | Noto Serif JP alone as the body role, and styles.
notoRole :: BS.ByteString
notoRole = "\n[fonts.body]\nja = \"fonts/noto.otf\"\n"

-- | Source Serif alone as the body role.
serifRole :: BS.ByteString
serifRole = "\n[fonts.body]\nlatin = \"fonts/serif.ttf\"\n"

-- | Every box of one character of a layout: its text, width, look and the glyphs it is shaped with.
boxesIn :: LoadedFonts -> Bool -> PdfLayout -> [(Text, Sp, Look, [Shaped])]
boxesIn fonts vertical pl =
  [ (bcText c, w, bcLook c, lfShape fonts (shapingForFonts fonts vertical (bcLook c) (T.head (bcText c))) (bcText c))
  | sl <- Map.elems (plLines pl),
    Box w c <- lineItems (slLine sl),
    T.length (bcText c) == 1
  ]

-- | The boxes of a text of a style, and the fonts.
layoutBoxes :: Bool -> BS.ByteString -> Text -> IO [(Text, Sp, Look, [Shaped])]
layoutBoxes vertical style source = do
  files <- fontFiles
  (_, pl) <- layoutMiniFonts golemFontProvider miniManifest style source files >>= either (assertFailure . show) pure
  fonts <- fontsOf style
  pure (boxesIn fonts vertical pl)

-- | The glyphs and advances (in em) of the boxes of a character.
glyphsOf :: Text -> [(Text, Sp, Look, [Shaped])] -> [[(Int, Rational)]]
glyphsOf t bs = [[(shGlyph g, shAdvance g) | g <- gs] | (t', _, _, gs) <- bs, t' == t]

-- | A PDF without its ID.
withoutId :: BS.ByteString -> BS.ByteString
withoutId b = let (before, rest) = BS.breakSubstring "/ID [" b in before <> BS.drop 1 (BS.dropWhile (/= 93) rest)

g07126 :: [Diagnostic] -> [Diagnostic]
g07126 = filter ((== DiagnosticCode "G07126") . diagCode)

-- | Builds with the fake fonts and returns every diagnostic and the PDF.
buildFake :: BS.ByteString -> Text -> [Text] -> Bool -> IO ([Diagnostic], BS.ByteString)
buildFake style source silenced noNotices = withSystemTempDirectory "golem-punct" $ \tmp -> do
  let manifest = miniManifest <> (if null silenced then "" else TE.encodeUtf8 ("\n[diagnostics]\nsilence-notices = [" <> T.intercalate ", " ["\"" <> c <> "\"" | c <- silenced] <> "]\n"))
  writeProject tmp manifest style source fakeFontFiles
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optNoNotices = noNotices}
  pdf <- BS.readFile (tmp </> "build/pdf/urn-uuid-11111111-2222-4333-8444-555555555555.pdf")
  pure (brDiagnostics r, pdf)

punctuationWidthTests :: TestTree
punctuationWidthTests =
  testGroup
    "full-width punctuation and narrow punctuation (docs/adr/0302)"
    [ testCase "Golem ADR 0378 inv1_punctuation_proportional_features_case_1: permission alone" $ do
        fonts <- fontsOf (notoRole <> "punctuation-proportional = true\n")
        let extra = shExtra (shapingForFonts fonts False (lookWith [] True) '「')
        lastValue "palt" extra @?= Nothing
        lastValue "fwid" extra @?= Just 1,
      testCase "Golem ADR 0378 inv1_punctuation_proportional_features_case_2: directional feature and explicit width" $ do
        fonts <- fontsOf (notoRole <> "punctuation-proportional = true\nfeatures = [\"palt\", \"vpal\"]\n")
        forM_ [(False, "palt"), (True, "vpal")] $ \(vertical, tag) ->
          forM_ ['「', '」', '。', '、', '・'] $ \ch -> do
            let effective lk = lfRoleFeatures fonts "body" <> shExtra (shapingForFonts fonts vertical lk ch)
                look = lookWith [] True
            lastValue tag (effective look) @?= Just 1
            lastValue "fwid" (effective look) @?= Nothing
            lastValue "hwid" (effective (lookWith ["hwid"] True)) @?= Just 1
            lastValue tag (effective look {lkKerning = KernJapaneseEqualWidth}) @?= Just 0,
      testCase "N6: Golem adds fwid to JLReq's punctuation only, horizontal and vertical" $
        forM_ [False, True] $ \v -> do
          let fwid c = lastValue "fwid" (shapedWith [] v (lookWith [] True) c)
          forM_ ("\x201C\x201D\x2018\x2019「」。、・" :: String) $ \c -> fwid c @?= Just 1
          forM_ ("あ？a" :: String) $ \c -> fwid c @?= Nothing,
      testCase "N6: punctuation-width = font adds no fwid" $
        forM_ [False, True] $ \v ->
          forM_ ("\x201C「。" :: String) $ \c -> lastValue "fwid" (shapedWith [] v (lookWith [] False) c) @?= Nothing,
      testCase "N7: a width feature written in the role or the styles wins over the default" $ do
        let at role fs = shapedWith role False (lookWith fs True)
        lastValue "fwid" (at ["-fwid"] [] '\x201D') @?= Just 0
        lastValue "fwid" (at [] ["-fwid"] '\x201D') @?= Just 0
        lastValue "fwid" (at [] ["fwid=0"] '\x201D') @?= Just 0
        lastValue "fwid" (at [] ["hwid"] '\x201D') @?= Nothing
        lastValue "hwid" (at [] ["hwid"] '\x201D') @?= Just 1
        forM_ ["pwid", "twid", "qwid"] $ \t -> lastValue "fwid" (at [] [t] '\x201D') @?= Nothing
        -- fwid written stays with punctuation-width = font
        lastValue "fwid" (shapedWith ["fwid"] False (lookWith [] False) '\x201D') @?= Just 1,
      testCase "N6, N3: Noto Serif JP sets “ and ” in its full-width glyphs, as wide as 「 and 」; 「 and 。 keep their glyphs" $
        forM_ [(False, horizontalStyle), (True, verticalPage)] $ \(v, page) -> do
          bs <- layoutBoxes v (page <> notoRole) "あ\x201Cい\x201Dう「え」お。\n"
          glyphsOf "\x201C" bs @?= [[(if v then 17581 else 17576, 1)]]
          glyphsOf "\x201D" bs @?= [[(if v then 17582 else 17577, 1)]]
          -- the glyphs of 「 and 。 are those without fwid
          fonts <- fontsOf (page <> notoRole)
          forM_ (["「", "。"] :: [Text]) $ \t ->
            glyphsOf t bs @?= [[(shGlyph g, shAdvance g) | g <- lfShape fonts (shapingForFonts fonts v lk {lkFullWidthPunctuation = False} (T.head t)) t] | (t', _, lk, _) <- bs, t' == t]
          unless v $ map (map fst) (glyphsOf "「" bs <> glyphsOf "。" bs) @?= [[1155], [1145]]
          [w | (t, w, _, _) <- bs, t == "\x201C"] @?= [w | (t, w, _, _) <- bs, t == "「"]
          [w | (t, w, _, _) <- bs, t == "\x201D"] @?= [w | (t, w, _, _) <- bs, t == "」"],
      testCase "N7, N8: punctuation-width and -fwid on paragraph and character styles choose the glyphs of the font" $ do
        let styles =
              BS.concat
                [ "\n[paragraph-styles.plain]\npunctuation-width = \"font\"\n",
                  "\n[character-styles.plain]\npunctuation-width = \"font\"\n",
                  "\n[character-styles.full]\npunctuation-width = \"full-width\"\n",
                  "\n[character-styles.nofwid]\nfeatures = [\"-fwid\"]\n"
                ]
            narrow = [(472, 213 / 500)]
            full = [(17576, 1)]
        forM_
          [ ("あ\x201Cい\n", notoRole, full),
            ("@style plain\nあ\x201Cい\n", notoRole, narrow),
            ("あ[style plain: \x201C]い\n", notoRole, narrow),
            ("@style plain\nあ[style full: \x201C]い\n", notoRole, full),
            ("あ[style nofwid: \x201C]い\n", notoRole, narrow),
            ("あ\x201Cい\n", notoRole <> "features = [\"-fwid\"]\n", narrow)
          ]
          $ \(source, role, expected) -> do
            bs <- layoutBoxes False (horizontalStyle <> role <> styles) source
            glyphsOf "\x201C" bs @?= [expected]
            -- the narrow glyph is drawn inside a box of half an em, as wide as the full one
            forM_ [(w, lk) | (t, w, lk, _) <- bs, t == "\x201C"] $ \(w, lk) -> w @?= Sp (unSp (lkSize lk) `div` 2),
      testCase "N4, N5: in Source Serif alone, ” of he said ” here does not reach here, horizontal and vertical" $
        forM_ [(False, horizontalStyle), (True, verticalPage)] $ \(v, page) -> do
          files <- fontFiles
          let style = page <> serifRole
          pdf <- miniPdf golemFontProvider False style "he said \x201D here\n" files
          fonts <- fontsOf style
          content <- BS.concat <$> inflateAll pdf
          let gid c = case lfShape fonts (Shaping "body" False [] False) (T.singleton c) of
                (g : _) -> (lfCode fonts (shFace g) (shGlyph g), shAdvance g)
                [] -> (0, 0)
              (quote, a) = gid '\x201D'
              (h, _) = gid 'h'
              drawn = drawnGlyphs content
              along d = if v then negate (ptToRational (dY d)) else ptToRational (dX d)
          case ([d | d <- drawn, dGlyph d == quote], [d | d <- drawn, dGlyph d == h]) of
            ([q], hs@(_ : _)) -> do
              let size = ptToRational (dSize q)
              let next = minimum [along x | x <- hs, along x > along q]
              assertBool (show (along q, a, next)) (along q + a * size <= next)
            other -> assertFailure (show other),
      testCase "N9: G07126 once for a glyph whose ink reaches the next character, at its first box" $ do
        let style = horizontalStyle <> fakeBody <> "\n[fonts.overhang]\nja = \"fonts/b.otf\"\n\n[character-styles.o]\nfont = \"overhang\"\n\n[character-styles.tight]\ntracking = -500\n"
            source = "[style o: あ\x201Dい]\n\n[style o: う\x201Dえ]\n\n[style o: お\x201D]\n\nか[style tight: \x201D]き\n" :: Text
        (ds, _) <- buildFake style source [] False
        let off = BS.length (TE.encodeUtf8 (fst (T.breakOn "\x201D" source)))
        [(diagSeverity d, spanStart (diagSpan d), diagMessage d) | d <- g07126 ds] @?= [(Notice, off, "約物の字面が隣の字にかかります: U+201D（fonts/b.otf）")],
      testCase "N9: no G07126 at the end of a paragraph or for an overlap by tracking alone" $ do
        let style = horizontalStyle <> fakeBody <> "\n[fonts.overhang]\nja = \"fonts/b.otf\"\n\n[character-styles.o]\nfont = \"overhang\"\n\n[character-styles.tight]\ntracking = -500\n"
        (ds, _) <- buildFake style "[style o: お\x201D]\n\nか[style tight: \x201D]き\n" [] False
        g07126 ds @?= [],
      testCase "N10: G07126 silenced or with --no-notices changes nothing in the PDF, and the same book gives the same diagnostics" $ do
        let style = horizontalStyle <> fakeBody <> "\n[fonts.overhang]\nja = \"fonts/b.otf\"\n\n[character-styles.o]\nfont = \"overhang\"\n"
            source = "[style o: あ\x201Dい]\n"
        (ds1, pdf1) <- buildFake style source [] False
        (ds2, pdf2) <- buildFake style source [] False
        (ds3, pdf3) <- buildFake style source ["G07126"] False
        (ds4, pdf4) <- buildFake style source [] True
        length (g07126 ds1) @?= 1
        map diagCode ds1 @?= map diagCode ds2
        g07126 ds3 @?= []
        g07126 ds4 @?= []
        pdf1 @?= pdf2
        -- the ID of the PDF is computed from the text of manifest.toml
        withoutId pdf1 @?= withoutId pdf3
        pdf1 @?= pdf4
    ]
