module PdfSpec (qpdfInstalled, pdfPipelineTests, marksTests, hiddenFolioTests, variationTests, characterFeatureTests, turnedTests, kentenTests, rubyTests, codeTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.IORef (newIORef, readIORef)
import Data.List (isSuffixOf, nub)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.Fonts (golemFontProvider)
import Golem.Driver.Pdf (CodeInfo (..), GlyphFrame (..), PdfInput (..), PdfLayout (..), SetLine (..), Shaped (..), Shaping (..), hiddenFolios, layoutPdf, offsetOrigin, shapingOf)
import Golem.Layout.KnuthPlass (BoxContent (..), Hyphen (..), Item (..), Line (..), placeLine)
import Golem.Layout.Look (Kerning (..), Look (..), plainLook)
import Golem.Layout.Paginate (PageOut (..), Slotted (..))
import Golem.Layout.Ruby (RubyAlign (..), RubyKind (..), RubyPlacement (..), RubyStyle (..), placeRuby)
import Golem.LayoutSpec (PageGeometry (..), Rect (..), baselineRatio, columnsFor, pageGeometry, typeAreaFor)
import Golem.Pdf (spToPt)
import Golem.Pdf qualified as P
import Golem.Project (ProjectFailure (..))
import Golem.Project.Style (dimToSp, parseDim, parseStyle)
import Golem.Syntax
import Golem.TestSupport.ExternalTool (needsTool)
import Support
import System.Directory (copyFile, createDirectoryIfMissing, findExecutable)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

pdfPipelineTests :: TestTree
pdfPipelineTests =
  testGroup
    "PDF pipeline (ADR 0002)"
    [ testCase "a missing body font is reported" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        copyTree fixture tmp
        BS.writeFile (tmp </> "style.toml") pdfStyle
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf]}
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0807"]
        map diagMessage (brDiagnostics r) @?= ["style.toml に本文のフォントがありません。[fonts.body] を書いてください"]
        -- reported before the fonts are loaded (golem-driver ADR 0016)
        r' <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = noFontProvider}
        map diagCode (brDiagnostics r') @?= [DiagnosticCode "G0807"],
      testCase "with real fonts: subset OpenType fonts, ToUnicode, deterministic and parallel-safe" $ do
        a <- buildRealPdf True
        b <- buildRealPdf False
        a @?= b
        -- the bare CFF, not the OpenType font: a viewer that takes the
        -- codes of a CID-keyed CFF wrapped in OpenType as glyph IDs
        -- (PDFium) draws no Japanese
        assertBool "bare CFF program" ("/Subtype /CIDFontType0C" `BS.isInfixOf` a)
        assertBool "no OpenType program" (not ("/Subtype /OpenType" `BS.isInfixOf` a))
        assertBool "vertical font" ("/Identity-V" `BS.isInfixOf` a)
        streams <- inflateAll a
        -- 「は」(U+306F) and 「じ」(U+3058) of 「はじめに」 are mapped back to text
        assertBool "ToUnicode" (any (\st -> "<306f>" `BS.isInfixOf` st && "beginbfchar" `BS.isInfixOf` st) streams)
        qpdfCheck a,
      testCase "ruby readings, emphasis dots and line-end hyphens are drawn" $ do
        pdf <- withSystemTempDirectory "golem-driver" $ \tmp -> do
          copyTree fixture tmp
          writeStyleWithFont tmp horizontalStyle
          BS.appendFile (tmp </> "chapters/02.gm") $ TE.encodeUtf8 "\n[kenten: 強調]する。\n\nThe typesetting of hyphenation demonstrates the extraordinary flexibility of characteristically unbreakable paragraphs.\n"
          r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = FontProvider (\_ _ _ _ -> pure (Right fakeFonts))}
          assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
          case brWritten r of
            [path] -> BS.readFile path
            other -> assertFailure (show other)
        streams <- inflateAll pdf
        let content = BS.concat streams
            sizes = nub (tfSizes content)
        -- the folio and the text share a size; ruby and the dots are half of it
        assertBool ("sizes: " <> show sizes) (length sizes >= 2)
        assertBool "sesame dot" ("<FE45>" `BS.isInfixOf` content)
        assertBool "hyphen" ("<002D>" `BS.isInfixOf` content),
      testCase "a line broken at an explicit hyphen gets no added hyphen (golem-layout ADR 0008)" $ do
        let source = T.unwords (replicate 24 "well-known") <> "\n"
        pdf <- miniPdf fakeProvider False horizontalStyle source []
        contents <- pageContents pdf
        sum (map (length . occurrences "<002D>") contents) @?= T.count "-" source,
      testCase "fonts and layout are not touched unless PDF is a target" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        copyTree fixture tmp
        writeStyleWithFont tmp pdfStyle
        calls <- newIORef (0 :: Int)
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFonts = countingFonts calls}
        readIORef calls >>= (@?= 0)
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = countingFonts calls}
        readIORef calls >>= (@?= 1),
      testCase "a PDF is written, structurally sound, the same in parallel and in sequence" $ do
        a <- buildPdf True
        b <- buildPdf False
        BS.take 9 a @?= "%PDF-1.6\n"
        assertBool "pages" ("/Type /Page " `BS.isInfixOf` a)
        assertBool "glyphs" (" Tj" `BS.isInfixOf` a || BS.length a > 2000)
        a @?= b
        qpdfCheck a
    ]

notoFonts :: IO LoadedFonts
notoFonts = do
  src <- TIO.readFile "test/fixtures/kanikosen/style.toml"
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) src)
  loadFonts realProvider "test/fixtures/kanikosen" (FileId 0) style [] >>= either (assertFailure . show) pure

-- | Source Han Sans (subset) and Source Sans Pro of golem-font's tests; the role palt has the feature palt.
featureFonts :: IO LoadedFonts
featureFonts = do
  let src =
        T.unlines
          [ "[fonts.body]",
            "ja = \"fonts/SourceHanSans-Regular_subset.otf\"",
            "latin = \"fonts/SourceSansPro-Regular.otf\"",
            "",
            "[fonts.palt]",
            "ja = \"fonts/SourceHanSans-Regular_subset.otf\"",
            "features = [\"palt\"]"
          ]
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) src)
  loadFonts golemFontProvider "../golem-font/test" (FileId 0) style [] >>= either (assertFailure . show) pure

-- | Noto Serif JP of the 蟹工船 fixture as the body role, and as the role palt with the feature palt (a style uses it, so that it is loaded).
notoPaltFonts :: IO LoadedFonts
notoPaltFonts = do
  let src = "[fonts.body]\nja = \"fonts/NotoSerifJP-Regular.otf\"\n\n[fonts.palt]\nja = \"fonts/NotoSerifJP-Regular.otf\"\nfeatures = [\"palt\"]\n\n[character-styles.p]\nfont = \"palt\"\n"
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) src)
  loadFonts golemFontProvider "test/fixtures/kanikosen" (FileId 0) style [] >>= either (assertFailure . show) pure

-- | Kerning, proportional metrics and baseline shift (docs/adr/0020).
characterFeatureTests :: [TestTree]
characterFeatureTests =
  [ testCase "a Latin word is kerned unless -kern is added" $ do
      fonts <- featureFonts
      let s = Shaping "body" False
          apart extra = lfAdvance fonts (s extra) 'A' + lfAdvance fonts (s extra) 'V'
      lfWordAdvance fonts (s ["-kern"]) "AV" @?= apart ["-kern"]
      assertBool "kerned" (lfWordAdvance fonts (s []) "AV" < apart []),
    -- the subset of Source Han Sans has no palt; Noto Serif JP of the 蟹工船 fixture has
    testCase "palt narrows a bracket; -palt after the role's palt undoes it" $ do
      fonts <- notoPaltFonts
      assertBool "palt" (lfAdvance fonts (Shaping "body" False ["palt"]) '「' < 1)
      lfAdvance fonts (Shaping "body" False ["-palt"]) '「' @?= 1
      assertBool "the role's palt" (lfAdvance fonts (Shaping "palt" False []) '「' < 1)
      lfAdvance fonts (Shaping "palt" False ["-palt"]) '「' @?= 1,
    testCase "vpal narrows a bracket in vertical shaping" $ do
      fonts <- featureFonts
      lfAdvance fonts (Shaping "body" True []) '「' @?= 1
      assertBool "vpal" (lfAdvance fonts (Shaping "body" True ["vpal"]) '「' < 1),
    testCase "the kerning of a pair is the pair shaped together less the two shaped apart" $ do
      fonts <- featureFonts
      let s = Shaping "body" False []
          together = lfWordAdvance fonts s "AV"
      lfPairKern fonts s 'A' 'V' @?= together - lfAdvance fonts s 'A' - lfAdvance fonts s 'V'
      assertBool "negative" (lfPairKern fonts s 'A' 'V' < 0)
      lfPairKern fonts (Shaping "body" False ["-kern"]) 'A' 'V' @?= 0,
    testCase "each kerning method and proportional metrics turn on their OpenType features" $ do
      let lk k p = (plainLook "body" 655360) {lkKerning = k, lkProportional = p}
      shapingOf False (lk KernMetrics False) 'あ' @?= Shaping "body" False []
      shapingOf False (lk KernMetrics True) 'あ' @?= Shaping "body" False ["palt"]
      shapingOf True (lk KernMetrics True) 'あ' @?= Shaping "body" True ["vpal"]
      shapingOf False (lk KernNone False) 'あ' @?= Shaping "body" False ["-kern", "-vkrn"]
      shapingOf True (lk KernNone True) 'あ' @?= Shaping "body" True ["-kern", "-vkrn", "vpal"]
      shapingOf False (lk KernJapaneseEqualWidth True) 'あ' @?= Shaping "body" False ["-kern", "-vkrn", "-palt", "-vpal"]
      shapingOf False (lk KernNone True) 'a' @?= Shaping "body" False ["-kern"]
      shapingOf False (lk KernJapaneseEqualWidth True) 'a' @?= Shaping "body" False []
      -- Latin in vertical text is turned and measured horizontally
      shapingOf True (lk KernMetrics False) 'a' @?= Shaping "body" False [],
    testCase "PDF: a baseline shift moves the glyph up in horizontal text, right in vertical text" $ do
      let up = "\n[character-styles.up]\nbaseline-shift = \"2pt\"\n"
          at axis style = do
            content <- miniPdf fakeProvider True (style <> up) "あ[style up: い]う\n" [] >>= fmap BS.concat . inflateAll
            let pos c = [ptToRational (axis d) | d <- drawnGlyphs content, dGlyph d == fromEnum c]
            case (pos 'あ', pos 'い') of
              (a : _, i : _) -> pure (i - a)
              other -> assertFailure (show other)
      at dY horizontalStyle >>= (@?= 2)
      at dX pdfStyle >>= (@?= 2),
    testCase "shaping without palt or vpal gives no offsets, horizontal or vertical (golem-driver ADR 0020)" $ do
      noto <- notoFonts
      han <- featureFonts
      let txt = "漢「字」、。ー\x2014 AVa"
      sequence_
        [ assertEqual (show (fonts', v)) [] [g | g <- lfShape fonts (Shaping "body" v []) txt, shOffset g /= (0, 0)]
        | (fonts, fonts') <- [(noto, "noto" :: String), (han, "han")],
          v <- [False, True]
        ],
    testCase "palt and vpal move a bracket within its box (golem-driver ADR 0020)" $ do
      noto <- notoPaltFonts
      han <- featureFonts
      case lfShape noto (Shaping "body" False ["palt"]) "「" of
        [g] -> assertBool (show g) (fst (shOffset g) /= 0)
        other -> assertFailure (show other)
      case lfShape han (Shaping "body" True ["vpal"]) "「" of
        [g] -> assertBool (show g) (snd (shOffset g) /= 0)
        other -> assertFailure (show other),
    testCase "PDF: a glyph is drawn at its box moved by its offset; other glyphs stay (golem-driver ADR 0020)" $ do
      -- a bracket gets palt or vpal from a role's features (proportional-metrics leaves punctuation to the aki)
      let style feature = fakeBody <> "\n[fonts.palt]\nja = \"fonts/h.otf\"\nfeatures = [\"" <> feature <> "\"]\n\n[character-styles.p]\nfont = \"palt\"\n"
          -- the bracket of the role palt moved as palt (horizontal) or vpal (vertical) would; the advances stay
          moved =
            fakeFonts
              { lfShape = \s t ->
                  [ if shText g == "「" && shRole s == "palt" then g {shOffset = if shVertical s then (0, 1 / 4) else (-(1 / 4), 0)} else g
                  | g <- lfShape fakeFonts s t
                  ]
              }
          drawn fonts base feature = miniPdf (FontProvider (\_ _ _ _ -> pure (Right fonts))) True (base <> style feature) "[style p: 漢「字」]\n" fakeFontFiles >>= fmap (drawnGlyphs . BS.concat) . inflateAll
          diff base feature = do
            plain <- drawn fakeFonts base feature
            off <- drawn moved base feature
            assertEqual "the same glyphs" (map dGlyph plain) (map dGlyph off)
            pure [(dGlyph a, ptToRational (dX b) - ptToRational (dX a), ptToRational (dY b) - ptToRational (dY a)) | (a, b) <- zip plain off, dX a /= dX b || dY a /= dY b]
          near expected got = assertBool (show (expected, got)) (abs (expected - got) < 1 / 100)
      horizontal <- diff horizontalStyle "palt"
      case horizontal of
        [(g, dx', dy')] -> do
          g @?= fromEnum '「'
          near (-(10 / 4)) dx'
          dy' @?= 0
        other -> assertFailure (show other)
      vertical <- diff pdfStyle "vpal"
      case vertical of
        -- 13Q is 3.25mm: a quarter of it upward
        [(g, dx', dy')] -> do
          g @?= fromEnum '「'
          dx' @?= 0
          near (13 / 4 / 4 * 72 / 25.4) dy'
        other -> assertFailure (show other),
    testCase "the offset of a glyph by how it is drawn; a scaled run scales the x offset (golem-driver ADR 0020)" $ do
      let size = 655360
      offsetOrigin size (FrameHorizontal 0) (1 / 10, 1 / 5) (1000, 2000) @?= (1000 + 65536, 2000 + 131072)
      offsetOrigin size (FrameHorizontal 50) (1 / 10, 1 / 5) (1000, 2000) @?= (1000 + round (65536 * 1050 / 1000 :: Rational), 2000 + 131072)
      offsetOrigin size (FrameHorizontal (-30)) (1 / 10, 0) (0, 0) @?= (round (65536 * 970 / 1000 :: Rational), 0)
      offsetOrigin size FrameUpright (1 / 10, 1 / 5) (1000, 2000) @?= (1000 + 65536, 2000 + 131072)
      -- turned 90° clockwise: the glyph's x runs down the page, its y to the right
      offsetOrigin size FrameTurned (1 / 10, 1 / 5) (1000, 2000) @?= (1000 + 131072, 2000 - 65536)
      offsetOrigin size (FrameHorizontal 50) (0, 0) (1000, 2000) @?= (1000, 2000),
    testCase "HTML: the CSS of the keys; a key with the value of body's default is not written" $ do
      let styles =
            BS.concat
              [ "[character-styles.tight]\nkerning = \"none\"\ntracking = -50\nproportional-metrics = true\nbaseline-shift = \"1pt\"\n\n",
                "[character-styles.plain]\nkerning = \"metrics\"\ntracking = 0\nproportional-metrics = false\nbaseline-shift = \"0pt\"\n\n",
                "[character-styles.grid]\nkerning = \"japanese-equal-width\"\nbaseline-shift = \"-0.25zw\"\n\n",
                "[paragraph-styles.verse]\ntracking = 100\n"
              ]
          cssWith style = withVerseProject style verseSource $ \tmp -> do
            r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            TIO.readFile (tmp </> "build/html/style.css")
      css <- cssWith styles
      rulesOf ".cs-tight" css @?= [".cs-tight { font-kerning: none; letter-spacing: -0.05em; font-feature-settings: \"palt\" 1; vertical-align: 1pt; }"]
      rulesOf ".cs-plain" css @?= []
      rulesOf ".cs-grid" css @?= [".cs-grid { font-kerning: normal; vertical-align: -0.25em; }"]
      assertBool "verse" (any ("letter-spacing: 0.1em;" `T.isInfixOf`) (rulesOf "p.ps-verse" css))
      assertBool "body" (not (any ("letter-spacing" `T.isInfixOf`) (rulesOf "p" css)))
      vertical <- cssWith (pdfStyle <> "\n" <> styles)
      rulesOf ".cs-tight" vertical @?= [".cs-tight { font-kerning: none; letter-spacing: -0.05em; font-feature-settings: \"vpal\" 1; vertical-align: 1pt; }"]
  ]

variationTests :: [TestTree]
variationTests =
  [ testCase "a base character and its variation selector are shaped together" $ do
      fonts <- notoFonts
      [(shGlyph g, shText g) | g <- lfShape fonts (Shaping "body" False []) "葛\xE0100"] @?= [(16314, "葛")],
    testCase "the variant glyph is drawn and maps back to its base character" $ do
      noto <- BS.readFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"
      let body = "\n[fonts.body]\nja = \"fonts/noto.otf\"\n"
      forM_ [pdfStyle <> body, horizontalStyle <> body] $ \style -> do
        pdf <- miniPdf realProvider True style "葛\xE0100と葛\n" [("fonts/noto.otf", noto)]
        streams <- inflateAll pdf
        let content = BS.concat [st | st <- streams, " Tf" `BS.isInfixOf` st]
            cmaps = [st | st <- streams, "beginbfchar" `BS.isInfixOf` st]
        -- CID 61923 is glyph 16314
        assertBool "variant drawn" ("<F1E3> Tj" `BS.isInfixOf` content)
        assertBool "maps to 葛" (any ("<F1E3> <845b>" `BS.isInfixOf`) cmaps)
        -- no glyph for the selector alone: no .notdef, no mapping to it
        assertBool "no .notdef" (not ("<0000> Tj" `BS.isInfixOf` content))
        assertBool "no selector in ToUnicode" (not (any (\c -> "db40dd00" `BS.isInfixOf` c) cmaps))
        qpdfCheck pdf,
    testCase "the CIDFont of 蟹工船 stays Adobe-Identity-0" $ do
      (_, pdf, _) <- buildBook "kanikosen"
      assertBool "Identity" ("/CIDSystemInfo << /Ordering (Identity) /Registry (Adobe) /Supplement 0 >>" `BS.isInfixOf` pdf)
  ]

{- | Lays out a project (manifest, style, sources) with the fake fonts and
crop marks or none, and returns the geometry, the layout and the hidden
folios of each page (ADR 0021).
-}
layoutHidden :: Maybe P.MarkStyle -> BS.ByteString -> BS.ByteString -> [(FilePath, T.Text)] -> IO (PageGeometry, PdfLayout, Map.Map Int [(Char, (Integer, Integer))])
layoutHidden marks manifest style sources = withSystemTempDirectory "golem-hidden" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") style
  forM_ sources $ \(to, src) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) (TE.encodeUtf8 src)
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, pageGeometry (FileId 0) (isJust marks) (evStyle e)) of
      _ | errs@(_ : _) <- filter isError (evDiagnostics e) -> assertFailure (show errs)
      (Just book, Right geom) -> do
        let inp = PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty marks (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty
        r <- layoutPdf inp geom fakeFonts
        case r of
          Left ds -> assertFailure (show ds)
          Right layout -> pure (geom, layout, hiddenFolios inp geom layout)
      (_, Left ds) -> assertFailure (show ds)
      (Nothing, _) -> assertFailure "no book"

-- | The hidden folio tests (ADR 0021).
hiddenFolioTests :: [TestTree]
hiddenFolioTests =
  [ testCase "with crop marks, only the blank page has one" $ do
      (_, _, hf) <- layoutHidden (Just P.Western) miniManifest headsStyle [("a.gm", twoChapters)]
      Map.keys hf @?= [4],
    testCase "without crop marks, none" $ do
      (_, _, hf) <- layoutHidden Nothing miniManifest headsStyle [("a.gm", twoChapters)]
      hf @?= Map.empty,
    testCase "enabled = false, none even with crop marks" $ do
      (_, _, hf) <- layoutHidden (Just P.Western) miniManifest (headsStyle <> "\n[hidden-folio]\nenabled = false\n") [("a.gm", twoChapters)]
      hf @?= Map.empty,
    testCase "pages = \"all\": every page" $ do
      (_, _, hf) <- layoutHidden (Just P.Western) miniManifest (headsStyle <> allPages) [("a.gm", twoChapters)]
      Map.keys hf @?= [1 .. 6],
    testCase "without master pages, every page; and a page whose master page has no folio" $ do
      (_, layout, hf) <- layoutHidden (Just P.Western) miniManifest shortGrid [("a.gm", twoChapters)]
      Map.keys hf @?= nub (map poNumber (plPages layout))
      let manifest = BS.concat ["chapters = [{ file = \"front.gm\", master = \"front\" }, \"a.gm\"]\n", BS.drop (BS.length "chapters = [\"a.gm\"]\n") miniManifest]
          style =
            BS.concat
              [ shortGrid,
                "[masters.front]\nrunning-head = { position = \"top-outside\", content = \"title\" }\n\n",
                "[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
              ]
      (_, _, hf') <- layoutHidden (Just P.Western) manifest style [("front.gm", lines' 5 <> "\n"), ("a.gm", lines' 5 <> "\n")]
      Map.keys hf' @?= [1],
    testCase "the column is on the gutter side: left binding, then right binding" $ do
      (geom, _, hf) <- layoutHidden (Just P.Western) miniManifest (shortGrid <> allPages) [("a.gm", twoChapters)]
      let (pw, _) = pgPageSize geom
          xs m n = nub [x | (_, (x, _)) <- Map.findWithDefault [] n m]
      xs hf 1 @?= [mm15]
      xs hf 2 @?= [pw - mm15]
      (_, _, hr) <- layoutHidden (Just P.Western) miniManifest (replaceIn "binding = \"left\"" "binding = \"right\"" shortGrid <> allPages) [("a.gm", twoChapters)]
      xs hr 1 @?= [pw - mm15]
      xs hr 2 @?= [mm15],
    testCase "page 123: three digits from top to bottom, centred on the height of the page" $ do
      let oneLine = replaceIn "lines = 30\n" "lines = 1\n" horizontalStyle <> allPages
      (geom, _, hf) <- layoutHidden (Just P.Western) miniManifest oneLine [("a.gm", lines' 130 <> "\n")]
      let (_, ph) = pgPageSize geom
          size = 6 * pt
          h2 = ph `div` 2
      Map.lookup 123 hf @?= Just [('1', (mm15, h2 + size)), ('2', (mm15, h2)), ('3', (mm15, h2 - size))],
    testCase "the folios do not move page breaks" $ do
      (_, a, _) <- layoutHidden Nothing miniManifest (headsStyle <> allPages) [("a.gm", twoChapters)]
      (_, b, hf) <- layoutHidden (Just P.Western) miniManifest (headsStyle <> allPages) [("a.gm", twoChapters)]
      assertBool "folios" (not (Map.null hf))
      plPages a @?= plPages b,
    testCase "bleed and marks: placed against the trimmed page, moved with it in the content" $ do
      pdf <- marksPdf (\o -> o {optMarks = JapaneseMarks}) (bleedStyle <> allPages)
      (w, h) <- a5Size
      let m = TE.encodeUtf8 (spToPt (P.shOrigin (P.sheet (Just P.Japanese) 557314 (w, h))))
      streams <- inflateAll pdf
      let pageStreams = [st | st <- streams, "Tj" `BS.isInfixOf` st]
      assertBool "a page" (not (null pageStreams))
      assertBool "moved" (all (("q 1 0 0 1 " <> m <> " " <> m <> " cm") `BS.isPrefixOf`) pageStreams)
      -- '1' in 6pt, half an em wide in the fake font, centred on the line 1.5mm from the gutter
      [(dX d, dY d) | d <- drawnGlyphs (BS.concat pageStreams), dGlyph d == fromEnum '1', dSize d == "6"]
        @?= [(TE.encodeUtf8 (spToPt (mm15 - 3 * pt `div` 2)), TE.encodeUtf8 (spToPt (h `div` 2 + 3 * pt - round (toRational (6 * pt) * baselineRatio))))],
    testCase "drawn after the figures of the page" $ do
      img <- tinyImage
      b <- buildMarksFilesWith "@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n" (\o -> o {optMarks = WesternMarks}) (Just (withBodyFont (figStyle horizontalStyle <> allPages))) (bodyFontFiles horizontalStyle <> img)
      assertEqual "no errors" [] (map diagCode (bErrors b))
      pdf <- maybe (assertFailure "no PDF") pure (bPdf b)
      content <- BS.concat <$> inflateAll pdf
      let after = snd (BS.breakSubstring " Do" content)
      assertBool "a figure" (not (BS.null after))
      assertBool "the folio after it" ("<0031> Tj" `BS.isInfixOf` after),
    testCase "golem check reports G0750 only with crop marks" $ do
      let narrow = replaceIn "gutter = \"20mm\"" "gutter = \"1mm\"" horizontalStyle
      b <- buildMarks (\o -> o {optMarks = WesternMarks, optTargets = Nothing, optCheckOnly = True}) (Just narrow)
      map diagCode (bErrors b) @?= [DiagnosticCode "G0750"]
      n <- buildMarks (\o -> o {optTargets = Nothing, optCheckOnly = True}) (Just narrow)
      map diagCode (bErrors n) @?= [],
    testCase "with marks, parallel and sequential builds agree" $ do
      a <- marksPdf (\o -> o {optMarks = JapaneseMarks}) (bleedStyle <> allPages)
      b <- marksPdf (\o -> o {optMarks = JapaneseMarks, optParallel = False}) (bleedStyle <> allPages)
      a @?= b
  ]
  where
    allPages = "\n[hidden-folio]\npages = \"all\"\n"
    -- 1.5mm
    mm15 = 278657
    lines' n = T.replicate (12 * n) "あ"
    -- pages 1 to 3, a blank page 4, pages 5 and 6
    twoChapters = T.intercalate "\n\n" ["# 海", lines' 5, lines' 6, lines' 6, "# 山", lines' 5, lines' 6] <> "\n"
    shortGrid = replaceIn "lines = 30\n" "lines = 6\n" horizontalStyle <> "\n"
    headsStyle =
      BS.concat
        [ shortGrid,
          "[headings.1]\npage-break = \"recto\"\nsize = \"1zw\"\nlines = 1\n\n",
          "[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
        ]

{- | Builds the one-chapter project with a style.toml (if given) and changed
options; PDF only and the fake fonts unless the options say otherwise.
-}
buildMarks :: (BuildOptions -> BuildOptions) -> Maybe BS.ByteString -> IO Built
buildMarks = buildMarksWith "本文。\n"

-- | 'buildMarks' with another source of the chapter.
buildMarksWith :: T.Text -> (BuildOptions -> BuildOptions) -> Maybe BS.ByteString -> IO Built
buildMarksWith source f style = buildMarksFilesWith source f (withBodyFont <$> style) (foldMap bodyFontFiles style)

-- | A built PDF; no errors allowed.
marksPdf :: (BuildOptions -> BuildOptions) -> BS.ByteString -> IO BS.ByteString
marksPdf f style = do
  b <- buildMarks f (Just style)
  assertEqual "no errors" [] (map diagCode (bErrors b))
  maybe (assertFailure "no PDF") pure (bPdf b)

-- | The A5 page of horizontalStyle with 3mm of bleed.
bleedStyle :: BS.ByteString
bleedStyle = replaceIn "size = \"A5\"\n" "size = \"A5\"\nbleed = \"3mm\"\n" horizontalStyle

-- | The value of a page box, as written.
boxOf :: BS.ByteString -> BS.ByteString -> BS.ByteString
boxOf name pdf = BC.takeWhile (/= ']') (BS.drop (BS.length name + 3) (snd (BS.breakSubstring ("/" <> name <> " [") pdf)))

-- | A rectangle as a page box is written.
boxText :: Rect -> BS.ByteString
boxText (Rect x y w h) = BC.unwords [TE.encodeUtf8 (spToPt v) | v <- [x, y, x + w, y + h]]

-- | The trimmed size of the A5 page of horizontalStyle.
a5Size :: IO (Integer, Integer)
a5Size = case parseStyle (FileId 0) (TE.decodeUtf8 horizontalStyle) of
  Right s -> either (assertFailure . show) (pure . pgPageSize) (pageGeometry (FileId 0) False s)
  Left ds -> assertFailure (show ds)

-- | How many times a needle occurs.
countIn :: BS.ByteString -> BS.ByteString -> Int
countIn needle hay = case BS.breakSubstring needle hay of
  (_, rest) | BS.null rest -> 0
  (_, rest) -> 1 + countIn needle (BS.drop (BS.length needle) rest)

marksTests :: [TestTree]
marksTests =
  [ testCase "no bleed and no marks: the three boxes are the same and nothing is moved" $ do
      pdf <- marksPdf id horizontalStyle
      boxOf "MediaBox" pdf @?= boxOf "TrimBox" pdf
      boxOf "MediaBox" pdf @?= boxOf "BleedBox" pdf
      streams <- inflateAll pdf
      assertBool "no cm" (not (any ("q 1 0 0 1 " `BS.isPrefixOf`) streams)),
    testCase "3mm of bleed and Japanese marks: the boxes of the sheet, moved content and registration marks" $ do
      pdf <- marksPdf (\o -> o {optMarks = JapaneseMarks}) bleedStyle
      (w, h) <- a5Size
      let s = P.sheet (Just P.Japanese) 557314 (w, h)
      boxOf "MediaBox" pdf @?= boxText (P.shMedia s)
      boxOf "TrimBox" pdf @?= boxText (P.shTrim s)
      boxOf "BleedBox" pdf @?= boxText (P.shBleed s)
      streams <- inflateAll pdf
      assertBool "moved" (any (\st -> "q 1 0 0 1 " `BS.isPrefixOf` st && "/Reg cs 1 scn" `BS.isInfixOf` st) streams)
      assertBool "no CMYK 100%" (not (any ("1 1 1 1 k" `BS.isInfixOf`) streams))
      qpdfCheck pdf,
    testCase "Japanese marks: one Separation, of the colorant All, in the resources (ADR 0007)" $ do
      pdf <- marksPdf (\o -> o {optMarks = JapaneseMarks}) bleedStyle
      streams <- inflateAll pdf
      countIn "/Separation" (BS.concat (pdf : streams)) @?= 1
      assertBool "All" ("/ColorSpace << /Reg [/Separation /All /DeviceCMYK " `BS.isInfixOf` pdf),
    testCase "no marks: no Separation (ADR 0007)" $ do
      pdf <- marksPdf (\o -> o {optMarks = NoMarks}) bleedStyle
      streams <- inflateAll pdf
      assertBool "Separation" (not (any ("/Separation" `BS.isInfixOf`) (pdf : streams))),
    testCase "with marks, text in a swatch stays DeviceCMYK (ADR 0007)" $ do
      let style = bleedStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
      b <- buildMarksWith "前[color accent: 赤い語]後\n" (\o -> o {optMarks = JapaneseMarks}) (Just style)
      assertEqual "no errors" [] (map diagCode (bErrors b))
      pdf <- maybe (assertFailure "no PDF") pure (bPdf b)
      streams <- inflateAll pdf
      assertBool "text in k" (any ("0 0.8 1 0 k" `BS.isInfixOf`) streams)
      assertBool "marks" (any ("/Reg cs 1 scn" `BS.isInfixOf`) streams),
    testCase "3mm of bleed without marks: the MediaBox is the BleedBox, the TrimBox inside" $ do
      pdf <- marksPdf id bleedStyle
      (w, h) <- a5Size
      boxOf "MediaBox" pdf @?= boxOf "BleedBox" pdf
      boxOf "TrimBox" pdf @?= boxText (Rect 557314 557314 w h),
    testCase "Japanese marks without bleed are G0702 at the top of style.toml, and no PDF" $ do
      b <- buildMarks (\o -> o {optMarks = JapaneseMarks}) (Just horizontalStyle)
      map diagCode (bErrors b) @?= [DiagnosticCode "G0702"]
      [(fmap siPath (Map.lookup (spanFile (diagSpan d)) (bSources b)), spanStart (diagSpan d)) | d <- bErrors b] @?= [(Just "style.toml", 0)]
      bPdf b @?= Nothing
      w <- buildMarks (\o -> o {optMarks = WesternMarks}) (Just horizontalStyle)
      map diagCode (bErrors w) @?= []
      assertBool "Western PDF" (isJust (bPdf w)),
    testCase "without style.toml, G0702 is at the top of manifest.toml" $ do
      b <- buildMarks (\o -> o {optMarks = JapaneseMarks}) Nothing
      [(fmap siPath (Map.lookup (spanFile (diagSpan d)) (bSources b)), spanStart (diagSpan d)) | d <- ofCode "G0702" b] @?= [(Just "manifest.toml", 0)],
    testCase "Japanese marks without bleed are not G0702 when PDF is not a target" $ do
      b <- buildMarks (\o -> o {optMarks = JapaneseMarks, optTargets = Just [TargetHtml]}) (Just horizontalStyle)
      map diagCode (bErrors b) @?= []
      assertBool "HTML" (any (".xhtml" `isSuffixOf`) (bWritten b)),
    testCase "golem check with Japanese marks and no bleed is G0702 and writes nothing" $ do
      b <- buildMarks (\o -> o {optMarks = JapaneseMarks, optTargets = Nothing, optCheckOnly = True}) (Just horizontalStyle)
      map diagCode (bErrors b) @?= [DiagnosticCode "G0702"]
      bBuildDir b @?= False,
    testCase "bleed in style.toml changes the instance ID" $ do
      a <- marksPdf id horizontalStyle
      b <- marksPdf id bleedStyle
      assertBool "instance" (snd (pdfIds a) /= snd (pdfIds b)),
    testCase "--marks and --profile change the instance ID, not the document ID" $ do
      none <- marksPdf id bleedStyle
      japanese <- marksPdf (\o -> o {optMarks = JapaneseMarks}) bleedStyle
      prod <- marksPdf (\o -> o {optProfile = Prod}) bleedStyle
      fst (pdfIds none) @?= fst (pdfIds japanese)
      assertBool "marks" (snd (pdfIds none) /= snd (pdfIds japanese))
      assertBool "profile" (snd (pdfIds none) /= snd (pdfIds prod)),
    testCase "a page size by dimensions is the TrimBox (golem-project ADR 0005)" $ do
      pdf <- marksPdf id (replaceIn "size = \"A5\"\n" "size = { width = \"396pt\", height = \"612pt\" }\n" horizontalStyle)
      boxOf "TrimBox" pdf @?= "0 0 396 612",
    testCase "golem check rejects a page size outside the table (golem-project ADR 0005)" $ do
      b <- buildMarks (\o -> o {optTargets = Nothing, optCheckOnly = True}) (Just (replaceIn "size = \"A5\"\n" "size = \"148mm x 210mm\"\n" horizontalStyle))
      map diagCode (bErrors b) @?= [DiagnosticCode "G0317"],
    testCase "with marks and bleed, two builds give the same bytes" $ do
      a <- marksPdf (\o -> o {optMarks = JapaneseMarks}) bleedStyle
      b <- marksPdf (\o -> o {optMarks = JapaneseMarks, optParallel = False}) bleedStyle
      a @?= b
  ]

-- | The x of each glyph of a size, as numbers.
glyphXs :: BS.ByteString -> BS.ByteString -> [Double]
glyphXs size content = [read (BC.unpack (dX d)) | d <- drawnGlyphs content, dSize d == size]

rubyTests :: [TestTree]
rubyTests =
  [ testCase "the reading of a group ruby is drawn where placeRuby puts it" $ do
      let source = "[ruby: 五月雨|さみだれ]が降る。\n"
          drawnAt align = do
            content <- miniPdf fakeProvider True (horizontalStyle <> "\n[composition.ruby]\ngroup-align = \"" <> align <> "\"\n") source [] >>= fmap BS.concat . inflateAll
            pure [dX d | d <- drawnGlyphs content, dSize d == "5"]
          expected a =
            let style = RubyStyle a a a 0 True
             in [rpReading (placeRuby style GroupRuby (replicate 3 (10 * pt)) (replicate 4 (5 * pt)) (0, 0))]
      geom <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 horizontalStyle) >>= pageGeometry (FileId 0) False)
      let ta = typeAreaFor geom 1
          xsOf ps = [TE.encodeUtf8 (spToPt (rectX ta + p)) | p <- ps]
      spaced <- drawnAt "1:2:1"
      centred <- drawnAt "center"
      [spaced] @?= map xsOf (expected Align121)
      [centred] @?= map xsOf (expected AlignCenter)
      assertBool "different" (spaced /= centred),
    testCase "bold on the second base character: that glyph alone is synthetic bold (golem-layout ADR 0011)" $ do
      runs <- miniPdf fakeProvider True horizontalStyle "[ruby: 漢[bold: 字]|かんじ]\n" [] >>= fmap (strokeRuns . BS.concat) . inflateAll
      widthsOf '字' runs @?= [Just "0.125"]
      widthsOf '漢' runs @?= [Nothing]
      widthsOf 'か' runs @?= [Nothing],
    testCase "a colour on the first base character: set before that glyph, the reading in the default colour (golem-layout ADR 0011)" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n") "[ruby: [color accent: 漢]字|かんじ]\n" [] >>= fmap BS.concat . inflateAll
      let (before, coloured) = BS.breakSubstring "0 0.8 1 0 k" content
          inside = fst (BS.breakSubstring "\nQ\n" coloured)
      assertBool "coloured" (not (BS.null coloured))
      assertBool (show inside) ("<6F22>" `BS.isInfixOf` inside)
      assertBool (show inside) (not ("<5B57>" `BS.isInfixOf` inside) && not ("<304B>" `BS.isInfixOf` inside))
      assertBool "the reading is drawn outside" ("<304B>" `BS.isInfixOf` (before <> BS.drop (BS.length inside) coloured)),
    testCase "a base character 1.5 times the size: the reading's baseline is 1.5 s above the base (golem-layout ADR 0011)" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> "\n[character-styles.big]\nsize = \"1.5zw\"\n") "[ruby: [style big: 漢]字|かんじ]\n" [] >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          ysOf c = nub [read (BC.unpack (dY d)) :: Double | d <- ds, dGlyph d == fromEnum c]
      ysOf '漢' @?= ysOf '字'
      case (ysOf '漢', ysOf 'か') of
        ([base], [reading]) -> assertBool (show (base, reading)) (abs (reading - base - 15) < 0.001)
        other -> assertFailure (show other)
      [dSize d | d <- ds, dGlyph d == fromEnum '漢'] @?= ["15"],
    testCase "a regex style matching part of a ruby base sets the match in its role (golem-layout ADR 0011)" $ do
      let style = pdfStyle <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\nlatin = \"fonts/h.otf\"\n\n[character-styles.n]\nfont = \"heading\"\n\n[paragraph-styles.body]\nregex-styles = [{ pattern = '[0-9]+', style = \"n\" }]\n"
          fontsOf content c = nub [dFont d | d <- drawnGlyphs content, dGlyph d == fromEnum c]
      styled <- miniPdf fakeProvider True style "[ruby: 東京12|とうきょう]へ\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      plain <- miniPdf fakeProvider True (pdfStyle <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\nlatin = \"fonts/h.otf\"\n") "[ruby: 東京12|とうきょう]へ\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      -- 2, not 1: the folio draws a 1 in the body role
      assertBool "drawn" (not (null (fontsOf styled '2')))
      assertBool (show (fontsOf styled '2', fontsOf plain '2')) (fontsOf styled '2' /= fontsOf plain '2')
      fontsOf styled '東' @?= fontsOf plain '東',
    testCase "a ruby at the line start does not stick out of the type area" $ do
      let source = T.replicate 12 "あ" <> "[ruby: 字|あいう]の" <> T.replicate 6 "あ" <> "\n"
      content <- miniPdf fakeProvider True horizontalStyle source [] >>= fmap BS.concat . inflateAll
      geom <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 horizontalStyle) >>= pageGeometry (FileId 0) False)
      let left = read (T.unpack (spToPt (rectX (typeAreaFor geom 1)))) :: Double
          xs = glyphXs "5" content
      assertBool (show (left, xs)) (not (null xs) && all (>= left - 0.001) xs)
      assertBool (show (left, xs)) (any (\x -> abs (x - left) < 0.001) xs),
    testCase "HTML: mono ruby has class mono; the style sheet sets ruby-align" $ do
      (page, css') <- htmlMini horizontalStyle "[ruby: 組/版|くみ/はん]と[ruby: 五月雨|さみだれ]と[ruby: 字|じ]\n"
      assertBool (T.unpack page) ("<ruby class=\"mono\">組<rp>" `T.isInfixOf` page)
      assertBool (T.unpack page) ("<ruby>五月雨<rp>" `T.isInfixOf` page)
      assertBool (T.unpack page) ("<ruby class=\"mono\">字<rp>" `T.isInfixOf` page)
      assertBool (T.unpack css') ("ruby { ruby-align: space-around; }" `T.isInfixOf` css')
      assertBool (T.unpack css') ("rt { ruby-align: space-around; }" `T.isInfixOf` css')
      assertBool (T.unpack css') ("ruby.mono rt { ruby-align: center; }" `T.isInfixOf` css')
      (_, css2) <- htmlMini (horizontalStyle <> "\n[composition.ruby]\ngroup-align = \"0:1:0\"\n") "[ruby: 五月雨|さみだれ]\n"
      assertBool (T.unpack css2) ("rt { ruby-align: space-between; }" `T.isInfixOf` css2)
  ]

-- | Reports whether the qpdf checks of 'qpdfCheck' run: SKIP without qpdf.
qpdfInstalled :: TestTree
qpdfInstalled =
  needsTool "qpdf" (findExecutable "qpdf") $ \qpdf ->
    testCase "qpdf is installed for the structure checks of the PDFs" $
      qpdf >>= \exe -> assertBool exe (not (null exe))

-- | The fixture with the test fonts of golem-font as the body font.
buildRealPdf :: Bool -> IO BS.ByteString
buildRealPdf parallel = withSystemTempDirectory "golem-driver" $ \tmp -> do
  copyTree fixture tmp
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile "../golem-font/test/fonts/SourceHanSans-Regular_subset.otf" (tmp </> "fonts/ja.otf")
  copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")
  BS.writeFile (tmp </> "style.toml") (pdfStyle <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n")
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optParallel = parallel}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  case brWritten r of
    [path] -> BS.readFile path
    other -> assertFailure (show other)

buildPdf :: Bool -> IO BS.ByteString
buildPdf parallel = withSystemTempDirectory "golem-driver" $ \tmp -> do
  copyTree fixture tmp
  writeStyleWithFont tmp pdfStyle
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = FontProvider (\_ _ _ _ -> pure (Right fakeFonts)), optParallel = parallel}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  case brWritten r of
    [path] -> BS.readFile path
    other -> assertFailure (show other)

{- | The font resources of a PDF: each name (such as @/F1@) with its Type0
font dictionary and the inflated ToUnicode stream.
-}
fontResources :: BS.ByteString -> IO [(BS.ByteString, BS.ByteString, BS.ByteString)]
fontResources pdf = do
  let objectBody n = fst (BS.breakSubstring "\nendobj" (snd (BS.breakSubstring ("\n" <> BC.pack (show n) <> " 0 obj\n") pdf)))
      refAfter key body = case BC.words (snd (BS.breakSubstring key body)) of
        (_ : n : "0" : "R" : _) -> Just (read (BC.unpack n) :: Int)
        _ -> Nothing
      fontDict = fst (BS.breakSubstring ">>" (BS.drop (BS.length "/Font <<") (snd (BS.breakSubstring "/Font <<" pdf))))
      names = [(name, read (BC.unpack n) :: Int) | (name, n, "0", "R") <- quads (BC.words fontDict), "/F" `BS.isPrefixOf` name]
      quads (a : b : c : d : rest) = (a, b, c, d) : quads rest
      quads _ = []
  mapM
    ( \(name, n) -> do
        let dict = objectBody n
        cmap <- case refAfter "/ToUnicode" dict of
          Just m -> BS.concat <$> inflateAll (objectBody m <> "\nendobj")
          Nothing -> pure ""
        pure (name, dict, cmap)
    )
    names

-- | The glyph of a character in Noto Serif JP, shaped horizontally or vertically: its id and its code in the PDF.
notoGlyph :: LoadedFonts -> Bool -> Char -> IO (Int, Int)
notoGlyph fonts v c = case lfShape fonts (Shaping "body" v []) (T.singleton c) of
  [g] -> pure (shGlyph g, lfCode fonts (shFace g) (shGlyph g))
  other -> assertFailure (show other)

-- | A PDF of a source with Noto Serif JP as the body font, and its glyphs drawn.
kentenDrawn :: BS.ByteString -> T.Text -> IO [Drawn]
kentenDrawn style source = do
  noto <- notoBytes
  pdf <- miniPdf golemFontProvider True (style <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\n") source [("fonts/noto.otf", noto)]
  drawnGlyphs . BS.concat <$> inflateAll pdf

{- | The centre of the ink box of a drawn glyph of a glyph id: horizontal,
or in a vertical font (origin at (500, 880) of the glyph).
-}
inkCentre :: LoadedFonts -> Bool -> Int -> Drawn -> IO (Rational, Rational)
inkCentre fonts v gid d = case lfInkBox fonts 0 gid of
  Just (x0, y0, x1, y1) ->
    let size = ptToRational (dSize d)
        (ox, oy) = if v then (1 / 2, 88 / 100) else (0, 0)
     in pure (ptToRational (dX d) + size * ((x0 + x1) / 2 - ox), ptToRational (dY d) + size * ((y0 + y1) / 2 - oy))
  Nothing -> assertFailure ("no ink box of glyph " <> show gid)

kentenTests :: [TestTree]
kentenTests =
  [ testCase "the ink box of a glyph in em" $ do
      fonts <- notoFonts
      (kan, _) <- notoGlyph fonts False '漢'
      lfInkBox fonts 0 kan @?= Just (36 / 1000, -(78 / 1000), 974 / 1000, 836 / 1000),
    testCase "horizontal: the sesame dot, half the size, centred above the em box" $ do
      fonts <- notoFonts
      (_, kan) <- notoGlyph fonts False '漢'
      (dotId, dot) <- notoGlyph fonts False '\xFE45'
      drawn <- kentenDrawn horizontalStyle "[kenten: 漢]\n"
      case ([d | d <- drawn, dGlyph d == kan], [d | d <- drawn, dGlyph d == dot]) of
        ([base], [mark]) -> do
          let s = ptToRational (dSize base)
              c = lfEmBoxCentral fonts 0
          ptToRational (dSize mark) @?= s / 2
          (cx, cy) <- inkCentre fonts False dotId mark
          let ex = ptToRational (dX base) + s / 2
              ey = ptToRational (dY base) + (c + 1 / 2) * s + s / 4
          assertBool (show (fromRational cx :: Double, fromRational ex :: Double)) (abs (cx - ex) < 1 / 100)
          assertBool (show (fromRational cy :: Double, fromRational ey :: Double)) (abs (cy - ey) < 1 / 100)
        other -> assertFailure (show other),
    testCase "vertical: the mark right of the centre line by 3s/4, s/2 down from the start of the box" $ do
      fonts <- notoFonts
      (_, kan) <- notoGlyph fonts True '漢'
      (dotId, dot) <- notoGlyph fonts True '\xFE45'
      drawn <- kentenDrawn pdfStyle "[kenten: 漢]\n"
      case ([d | d <- drawn, dGlyph d == kan], [d | d <- drawn, dGlyph d == dot]) of
        ([base], [mark]) -> do
          let s = ptToRational (dSize base)
          ptToRational (dSize mark) @?= s / 2
          (cx, cy) <- inkCentre fonts True dotId mark
          let ex = ptToRational (dX base) + 3 * s / 4
              ey = ptToRational (dY base) - s / 2
          assertBool (show (fromRational cx :: Double, fromRational ex :: Double)) (abs (cx - ex) < 1 / 100)
          assertBool (show (fromRational cy :: Double, fromRational ey :: Double)) (abs (cy - ey) < 1 / 100)
        other -> assertFailure (show other),
    testCase "shape=triangle draws U+25B2" $ do
      fonts <- notoFonts
      (_, tri) <- notoGlyph fonts False '\x25B2'
      drawn <- kentenDrawn horizontalStyle "[kenten shape=triangle: 漢]\n"
      length [d | d <- drawn, dGlyph d == tri] @?= 1,
    testCase "the default shape of style.toml: open-circle draws U+25CB" $ do
      fonts <- notoFonts
      (_, circle) <- notoGlyph fonts False '\x25CB'
      (_, sesame) <- notoGlyph fonts False '\xFE45'
      drawn <- kentenDrawn (horizontalStyle <> "\n[composition]\nkenten = \"open-circle\"\n") "[kenten: 漢字]\n"
      length [d | d <- drawn, dGlyph d == circle] @?= 2
      length [d | d <- drawn, dGlyph d == sesame] @?= 0,
    testCase "an opening bracket in kenten is where it is without kenten, with no mark" $ do
      fonts <- notoFonts
      (_, bracket) <- notoGlyph fonts False '「'
      (_, sesame) <- notoGlyph fonts False '\xFE45'
      with <- kentenDrawn horizontalStyle "[kenten: 「字」]\n"
      without <- kentenDrawn horizontalStyle "「字」\n"
      [(dX d, dY d) | d <- with, dGlyph d == bracket] @?= [(dX d, dY d) | d <- without, dGlyph d == bracket]
      length [d | d <- with, dGlyph d == sesame] @?= 1,
    testCase "G0809: the Japanese font has no kenten character; once per role and shape, no PDF" $ do
      (sans, _) <- realLatinFonts
      (errs, pdf) <- buildMini golemFontProvider True (horizontalStyle <> "\n[fonts.body]\nja = \"fonts/sans.otf\"\n") "[kenten: 漢]と[kenten: 字]\n" [("fonts/sans.otf", sans)]
      errs @?= [DiagnosticCode "G0809"]
      pdf @?= Nothing,
    testCase "G0809: the message names the role, the shape and the character" $ do
      (sans, _) <- realLatinFonts
      n <- buildNotified [("manifest.toml", miniManifest), ("style.toml", horizontalStyle <> "\n[fonts.body]\nja = \"fonts/sans.otf\"\n"), ("a.gm", TE.encodeUtf8 "[kenten shape=open-sesame: 漢]\n"), ("fonts/sans.otf", sans)] (\o -> o {optFonts = golemFontProvider})
      [(c, diagMessage d) | d <- nDiagnostics n, let DiagnosticCode c = diagCode d, c == "G0809"]
        @?= [("G0809", "役割 body の和文の書体に圏点の形 open-sesame の字（U+FE46）がありません")],
    testCase "G0745: kenten in a ruby base, and ruby in kenten, are a notice; the PDF is written" $
      forM_ [("[ruby: [kenten: 漢]|かん]\n", 7), ("[kenten: [ruby: 漢|かん]]\n", 9)] $ \(src, at) -> do
        n <- buildNotified ([("manifest.toml", miniManifest), ("style.toml", withBodyFont horizontalStyle), ("a.gm", TE.encodeUtf8 src)] <> fakeFontFiles) id
        [(c, diagSeverity d, spanStart (diagSpan d)) | d <- nDiagnostics n, let { DiagnosticCode c = diagCode d }, c == "G0745"] @?= [("G0745", Notice, at)]
        assertBool "the PDF" (any ((".pdf" `isSuffixOf`) . fst) (nOutputs n)),
    testCase "HTML: the class of the shape; no shape is sesame" $ do
      n <- buildNotified ([("manifest.toml", miniManifest <> "\n[targets.html]\n"), ("style.toml", withBodyFont horizontalStyle), ("a.gm", TE.encodeUtf8 "[kenten: 漢][kenten shape=open-triangle: 字]\n")] <> fakeFontFiles) id
      case [b | (p, b) <- nOutputs n, ".xhtml" `isSuffixOf` p, "kenten" `BS.isInfixOf` b] of
        [page] -> do
          assertBool "sesame" ("<span class=\"kenten kenten-sesame\">" `BS.isInfixOf` page)
          assertBool "open-triangle" ("<span class=\"kenten kenten-open-triangle\">" `BS.isInfixOf` page)
          assertBool "no default" (not ("kenten-default" `BS.isInfixOf` page))
        other -> assertFailure (show (length other, map fst (nOutputs n), nDiagnostics n))
      case [b | (p, b) <- nOutputs n, "style.css" `isSuffixOf` p, "html" `isPrefixOf'` p] of
        (css : _) ->
          mapM_
            (\rule -> assertBool (BC.unpack rule) (rule `BS.isInfixOf` css))
            [ ".kenten-sesame { text-emphasis-style: sesame; -epub-text-emphasis-style: sesame; }",
              ".kenten-double-circle { text-emphasis-style: double-circle; }",
              ".kenten-open-double-circle { text-emphasis-style: open double-circle; }",
              ".kenten-triangle { text-emphasis-style: triangle; }",
              ".kenten-open-triangle { text-emphasis-style: open triangle; }"
            ]
        [] -> assertFailure "no style.css"
  ]
  where
    isPrefixOf' a b = take (length a) b == a

turnedTests :: [TestTree]
turnedTests =
  [ testCase "vertical shaping turns an em dash that has no vertical form" $ do
      fonts <- notoFonts
      case lfShape fonts (Shaping "body" True []) "\x2014" of
        [g] -> (shGlyph g, shAdvance g, shTurned g) @?= (466, 890 / 1000, True)
        other -> assertFailure (show other),
    testCase "characters with vertical forms stay upright" $ do
      fonts <- notoFonts
      let one c = case lfShape fonts (Shaping "body" True []) (T.singleton c) of
            [g] -> pure g
            other -> assertFailure (show other)
      gs <- mapM one "\x2015\x2026\x301C"
      map shGlyph gs @?= [15282, 15280, 17592]
      comma <- one '、'
      horizontalComma <- case lfShape fonts (Shaping "body" False []) "、" of
        [g] -> pure g
        other -> assertFailure (show other)
      assertBool "vertical form of 、" (shGlyph comma /= shGlyph horizontalComma)
      map shTurned (comma : gs) @?= replicate 4 False,
    testCase "a variation selector stays in the cluster of a turned character (golem-pdf ADR 0006)" $ do
      fonts <- notoFonts
      let gs = lfShape fonts (Shaping "body" True []) "\x2014\xFE00漢"
          dash = [g | g <- gs, shText g == "\x2014"]
      -- the selector is in the dash's cluster (HarfBuzz may give it a glyph of its own) and turns with it
      map shGlyph (take 1 dash) @?= [466]
      assertBool (show gs) (all shTurned dash && all (\g -> shText g `elem` ["\x2014", "漢"]) gs)
      [shTurned g | g <- gs, shText g == "漢"] @?= [False],
    testCase "ideographs are upright; horizontal shaping never turns" $ do
      fonts <- notoFonts
      map shTurned (lfShape fonts (Shaping "body" True []) "漢") @?= [False]
      assertBool "horizontal" (not (any shTurned (lfShape fonts (Shaping "body" False []) "——漁夫は―…〜、漢「」ー")))
      assertBool "horizontal Latin" (not (any shTurned (lfShape fonts (Shaping "body" False []) "Golem --"))),
    testCase "turned dashes are drawn with the horizontal font, centred on the line" $ do
      noto <- notoBytes
      fonts <- notoFonts
      pdf <- miniPdf golemFontProvider False (pdfStyle <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\n") "——漁夫は\n" [("fonts/noto.otf", noto)]
      content <- BS.concat <$> inflateAll pdf
      resources <- fontResources pdf
      let encodingOf name = [enc | (n, dict, _) <- resources, n == name, enc <- ["Identity-V", "Identity-H"], ("/" <> enc) `BS.isInfixOf` dict]
          drawn = drawnGlyphs content
          dashes = [d | d <- drawn, dGlyph d == 722]
          turned = [d | d <- dashes, dMatrix d == ["0", "-1", "1", "0"]]
      length turned @?= 2
      length dashes @?= 2
      assertBool "the horizontal font" (all (\d -> encodingOf (dFont d) == ["Identity-H"]) turned)
      assertBool "no dash in the vertical font" (null [d | d <- drawn, dGlyph d == 722, encodingOf (dFont d) == ["Identity-V"]])
      assertBool "ToUnicode" (or [encodingOf n == ["Identity-H"] && "<02D2> <2014>" `BS.isInfixOf` cmap | (n, _, cmap) <- resources])
      -- the upright 漁 sits on the centre line; the dashes lie left of it by the centre of the em box
      case ([d | d <- drawn, encodingOf (dFont d) == ["Identity-V"], dMatrix d == ["1", "0", "0", "1"]], turned) of
        (upright : _, dash : _) -> do
          let size = ptToRational (dSize dash)
              shift = ptToRational (dX upright) - ptToRational (dX dash)
              expected = lfEmBoxCentral fonts 0 * size
          assertBool (show (fromRational shift :: Double, fromRational expected :: Double)) (expected > 0 && abs (shift - expected) < 1 / 100)
        other -> assertFailure (show other)
  ]

-- ------------------------------------------------------------------ code (golem-driver ADR 0017)

-- | The rows of the code blocks of a layout: each box with its text, from the line start of the column.
codeRows :: PdfLayout -> [[(Integer, T.Text)]]
codeRows pl =
  [ [(slIndent sl + off, bcText c) | (Box _ c, off) <- placeLine (slLine sl), not (T.null (bcText c))]
  | p <- plPages pl,
    (_, SCode lid k _) <- poSlots p,
    j <- [0 .. k - 1],
    Just sl <- [Map.lookup (lid + j) (plLines pl)]
  ]

-- | The code slots of each page and column.
codeSlots :: PdfLayout -> [[(Int, Slotted)]]
codeSlots pl = [[x | x@(_, SCode {}) <- poSlots p] | p <- plPages pl]

-- | The rectangles filled in a content stream: x, y, width and height in pt.
filledRects :: BS.ByteString -> [[Double]]
filledRects content = [map (read . BC.unpack) (take 4 ws) | l <- BC.lines content, let ws = BC.words l, drop 4 ws == ["re", "f"]]

-- | Every diagnostic of a build of the one-chapter project, with the fake fonts.
buildAllWith :: (BuildOptions -> BuildOptions) -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO BuildResult
buildAllWith f style source files = withSystemTempDirectory "golem-code" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ (bodyFontFiles style <> files) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  build (f (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider})

buildAll :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO BuildResult
buildAll = buildAllWith id

codeOf :: BuildResult -> T.Text -> [Diagnostic]
codeOf r c = [d | d <- brDiagnostics r, diagCode d == DiagnosticCode c]

codeTests :: [TestTree]
codeTests =
  [ testCase "leading spaces: the first glyph after four spaces is at the padding and four spaces" $ do
      (_, pl) <- layoutOk horizontalStyle "```\n    x\n```\n" []
      codeRows pl @?= [[(pad + 4 * sp, "x")]],
    testCase "a code block of the source keeps the spaces in a line as many as written" $ do
      (_, pl) <- layoutOk horizontalStyle "```\na   b\n```\n" []
      codeRows pl @?= [[(pad, "a"), (pad + 4 * sp, "b")]],
    testCase "tabs go to the stops every two spaces; after a Japanese character too" $ do
      (_, pl) <- layoutOk horizontalStyle "```\n\tx\nab\tx\nabcd\tx\n漢\tx\n```\n" []
      codeRows pl @?= [[(pad + 2 * sp, "x")], [(pad, "ab"), (pad + 4 * sp, "x")], [(pad, "abcd"), (pad + 6 * sp, "x")], [(pad, "漢"), (pad + 4 * sp, "x")]],
    testCase "a tab in [code: ...] of a paragraph is set as before, not at a stop" $ do
      (_, pl) <- layoutOk horizontalStyle "[code: a\tb]\n" []
      [(off, bcText c) | sl <- Map.elems (plLines pl), (Box _ c, off) <- placeLine (slLine sl), not (T.null (bcText c))] @?= [(0, "a"), (sp, "\t"), (2 * sp, "b")],
    testCase "no justification: two short words keep one space between them" $ do
      (_, pl) <- layoutOk horizontalStyle "```\nab cd\n```\n" []
      codeRows pl @?= [[(pad, "ab"), (pad + 3 * sp, "cd")]],
    testCase "no hyphenation: a long word wraps at a cluster, with no hyphen" $ do
      (_, pl) <- layoutOk horizontalStyle "```\nabcdefghijklmnopqrstuvwxyzabcd\n```\n" []
      codeRows pl @?= [[(pad, "abcdefghijklmnopqrstuv")], [(pad + 2 * sp, "wxyzabcd")]],
    testCase "no aki between Japanese and Latin: a漢b as their advances" $ do
      (_, pl) <- layoutOk horizontalStyle "```\na漢b\n```\n" []
      codeRows pl @?= [[(pad, "a"), (pad + sp, "漢"), (pad + sp + 10 * pt, "b")]],
    testCase "a wrapped line continues two spaces after its indent, or at two spaces" $ do
      (_, pl) <- layoutOk horizontalStyle "```\n  abcdefghijklmnopqrstuvwxyz\n              abcdefghijklm\n```\n" []
      codeRows pl
        @?= [ [(pad + 2 * sp, "abcdefghijklmnopqrst")],
              [(pad + 4 * sp, "uvwxyz")],
              [(pad + 14 * sp, "abcdefgh")],
              [(pad + 2 * sp, "ijklm")]
            ],
    testCase "G0730: one notice for a block with wrapped lines, with the number of lines" $ do
      r <- buildAll horizontalStyle "```\nabcdefghijklmnopqrstuvwxyzabcd\nx\nabcdefghijklmnopqrstuvwxyzabcd\n```\n" []
      [(diagMessage d, diagSeverity d) | d <- codeOf r "G0730"] @?= [("コードの行を折り返しました（2 行）", Notice)]
      assertBool "the PDF" (any (".pdf" `isSuffixOf`) (brWritten r))
      r' <- buildAll horizontalStyle "```\nabc\n```\n" []
      codeOf r' "G0730" @?= [],
    testCase "the grid: three rows of 11Q code on 13Q and 22H take three lines; the text after is on the grid" $ do
      (_, pl) <- layoutOk (grid13 <> "\n[paragraph-styles.code]\nsize = \"11Q\"\n") "```\na\nb\nc\n```\n\n本文。\n" []
      case plPages pl of
        (p : _) -> case poSlots p of
          (s0 : s1 : _) -> do
            s0 @?= (0, SCode 0 3 3)
            fst s1 @?= 3
          other -> assertFailure (show other)
        [] -> assertFailure "no page",
    testCase "the background: a CMYK rectangle of the lines taken, drawn before the text" $ do
      pdf <- miniPdf fakeProvider True (horizontalStyle <> codeBg) "```\na\nb\n```\n" []
      (geom, _) <- layoutOk (horizontalStyle <> codeBg) "```\na\nb\n```\n" []
      contents <- pageContents pdf
      let ta = firstColumn geom
          -- (2 - 1) * 15 + 10 + 2 * 5 = 35pt: three lines of 15pt
          top = rectY ta + rectH ta + (15 - 10) * pt `div` 2
      case contents of
        (c : _) -> do
          case filledRects c of
            [[x, y, w, h]] -> do
              assertBool (show (x, toPt (rectX ta))) (abs (x - toPt (rectX ta)) < 0.001)
              assertBool (show (y, h, toPt top)) (abs (y + h - toPt top) < 0.001)
              assertBool (show w) (abs (w - 120) < 0.001)
              assertBool (show h) (abs (h - 45) < 0.001)
            other -> assertFailure (show other)
          assertBool "the colour" ("0 0 0 0.08 k" `BS.isInfixOf` c)
          let (before, _) = BS.breakSubstring "BT" c
          assertBool "before the text" (" re f" `BS.isInfixOf` before)
        [] -> assertFailure "no page"
      plain <- miniPdf fakeProvider True horizontalStyle "```\na\n```\n" [] >>= pageContents
      map filledRects plain @?= [[]],
    testCase "a page break between rows: the rows that fit, the rest on the next page, a background each" $ do
      (_, pl) <- layoutOk fiveLines "一。\n\n二。\n\n三。\n\n```\na\nb\nc\nd\ne\n```\n" []
      codeSlots pl @?= [[(3, SCode 3 1 2)], [(0, SCode 4 4 5)]]
      pdf <- miniPdf fakeProvider True (fiveLines <> codeBg) "一。\n\n二。\n\n三。\n\n```\na\nb\nc\nd\ne\n```\n" []
      contents <- pageContents pdf
      map (length . filledRects) contents @?= [1, 1],
    testCase "a code block of the source whose first row and padding do not fit starts on the next page" $ do
      (_, pl) <- layoutOk fiveLines "一。\n\n二。\n\n三。\n\n四。\n\n```\na\n```\n" []
      codeSlots pl @?= [[], [(0, SCode 4 1 2)]],
    testCase "columns: the rows break at the end of a column as at a page" $ do
      (_, pl) <- layoutOk (replaceIn "lines = 30" "lines = 5" horizontal2) "一。\n\n二。\n\n三。\n\n```\na\nb\nc\n```\n" []
      [(poColumn p, [x | x@(_, SCode {}) <- poSlots p]) | p <- plPages pl] @?= [(0, [(3, SCode 3 1 2)]), (1, [(0, SCode 4 2 3)])],
    testCase "in a list: the background and the text start at the text of the item" $ do
      (geom, pl) <- layoutOk (horizontalStyle <> codeBg) "- 項目\n\n  ```\n  x\n  ```\n" []
      codeRows pl @?= [[(10 * pt + pad, "x")]]
      contents <- miniPdf fakeProvider True (horizontalStyle <> codeBg) "- 項目\n\n  ```\n  x\n  ```\n" [] >>= pageContents
      case concatMap filledRects contents of
        [[x, _, w, _]] -> do
          assertBool (show x) (abs (x - toPt (rectX (firstColumn geom) + 10 * pt)) < 0.001)
          assertBool (show w) (abs (w - 110) < 0.001)
        other -> assertFailure (show other),
    testCase "G0743: too little measure in a deep list, at the block" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.code]\npadding = \"1zw\"\n"
      r <- buildAll style "- a\n  - b\n    - c\n\n      ```\n      x\n      ```\n" []
      [(diagMessage d, spanStart (diagSpan d) > 0) | d <- codeOf r "G0743"] @?= [("コードブロックの行長が足りません", True)]
      ok <- buildAll style "- a\n  - b\n\n    ```\n    x\n    ```\n" []
      codeOf ok "G0743" @?= [],
    testCase "G0743: too little measure at the top, reported by golem check too" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.code]\npadding = \"3zw\"\n"
      r <- buildAllWith (\o -> o {optCheckOnly = True}) style "```\nx\n```\n" []
      map diagMessage (codeOf r "G0743") @?= ["コードブロックの行長が足りません"],
    testCase "G0743: one row and its padding taller than a page" $ do
      r <- buildAll (replaceIn "lines = 30" "lines = 1" horizontalStyle) "```\nx\n```\n" []
      map diagMessage (codeOf r "G0743") @?= ["コードブロックの一行が一ページに収まりません"],
    testCase "empty lines are rows, at the start, in the middle and at the end" $ do
      (_, pl) <- layoutOk horizontalStyle "```\n\nx\n\ny\n\n```\n" []
      map (map snd) (codeRows pl) @?= [[], ["x"], [], ["y"], []],
    testCase "vertical: the spaces and the tab stops are along the line, from the top" $ do
      (_, pl) <- layoutOk pdfStyle "```\n  \tx\n```\n" []
      let s13 = maybe 0 (dimToSp 0) (parseDim "13Q")
          half = round (toRational s13 / 2) :: Integer
      codeRows pl @?= [[(half + 4 * half, "x")]],
    testCase "@listing is set as a code block" $ do
      (_, a) <- layoutOk horizontalStyle "@listing src/a.txt\n" [("src/a.txt", "  a\tb\nlong line that wraps at the end\n")]
      (_, b) <- layoutOk horizontalStyle "```\n  a\tb\nlong line that wraps at the end\n```\n" []
      codeRows a @?= codeRows b,
    testCase "[fonts.code]: code is set in it" $ do
      let style = horizontalStyle <> "\n[fonts.code]\nlatin = \"fonts/w.otf\"\n" <> fakeBody
      (_, pl) <- layoutOk style "```\nab\n```\n" fakeFontFiles
      [lkLatinFace (bcLook c) | sl <- Map.elems (plLines pl), Box _ c <- lineItems (slLine sl), bcText c == "ab"] @?= ["code"],
    testCase "[fonts.code] is embedded only when the book has code" $ do
      noto <- BS.readFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"
      sans <- BS.readFile "../golem-font/test/fonts/SourceSansPro-Regular.otf"
      let style = horizontalStyle <> "\n[fonts.body]\nja = \"fonts/noto.otf\"\n\n[fonts.code]\nlatin = \"fonts/sans.otf\"\n"
          files = [("fonts/noto.otf", noto), ("fonts/sans.otf", sans)]
      withCode' <- miniPdf realProvider False style "本文。\n\n```\nabc\n```\n" files
      assertBool "embedded" ("SourceSansPro" `BS.isInfixOf` withCode')
      without <- miniPdf realProvider False style "本文。\n" files
      assertBool "not embedded" (not ("SourceSansPro" `BS.isInfixOf` without)),
    testCase "G0808: without [fonts.code], code is set in the body role, with one notice" $ do
      r <- buildAll horizontalStyle "```\nabc\n```\n\n[code: x] and [code: y]\n" []
      [(diagMessage d, diagSeverity d) | d <- codeOf r "G0808"] @?= [("コードの書体の役割 code がないので、本文の書体で組みます", Notice)]
      assertBool "the PDF" (any (".pdf" `isSuffixOf`) (brWritten r))
      r' <- buildAll horizontalStyle "本文。\n" []
      codeOf r' "G0808" @?= [],
    testCase "[code: manifest.toml] at the line end is not hyphenated: the whole goes to the next line" $ do
      ts <- listPages horizontalStyle "あいうえおかきくけ[code: manifest.toml]です。\n"
      assertBool (show ts) (any ("manifest.toml" `T.isPrefixOf`) ts),
    testCase "a path in [code: ...] breaks after a slash, with no hyphen" $ do
      (_, pl) <- layoutOk horizontalStyle "あいうえお[code: modules/golem-driver/src/Golem/Driver/Pdf.hs]\n" []
      assertSlashBreaks pl,
    testCase "a character style based on code is set as code" $ do
      (_, pl) <- layoutOk (horizontalStyle <> "\n[character-styles.path]\nbased-on = \"code\"\n") "あいうえお[style path: modules/golem-driver/src/Golem/Driver/Pdf.hs]\n" []
      assertSlashBreaks pl,
    testCase "[character-styles.code] color: the role code and the colour" $ do
      let style = horizontalStyle <> "\n[fonts.code]\nlatin = \"fonts/w.otf\"\n" <> fakeBody <> "\n[color.swatches]\nx = { cmyk = [90, 50, 0, 20] }\n\n[character-styles.code]\ncolor = \"x\"\n"
      (_, pl) <- layoutOk style "[code: abc]\n" fakeFontFiles
      [(lkLatinFace (bcLook c), lkColor (bcLook c)) | sl <- Map.elems (plLines pl), Box _ c <- lineItems (slLine sl), bcText c == "abc"] @?= [("code", Just "x")],
    testCase "HTML: pre and code in the code role and monospace; pre wraps with tabs of 2" $
      withCode (horizontalStyle <> "\n[fonts.code]\nlatin = \"fonts/w.otf\"\n" <> fakeBody) "```\nx\n```\n\n[code: y]\n" $ \css page -> do
        rulesOf "pre, code" css @?= ["pre, code { font-family: \"golem-code-latin\", monospace; }"]
        case rulesOf "pre" css of
          [r] -> do
            forM_ ["white-space: pre-wrap", "overflow-wrap: anywhere", "tab-size: 2", "hyphens: none", "font-kerning: none"] $ \d -> assertBool (T.unpack r) (d `T.isInfixOf` r)
            assertBool "no background" (not ("background-color" `T.isInfixOf` r))
            assertBool "no padding" (not ("padding" `T.isInfixOf` r))
          other -> assertFailure (show other)
        assertBool "no tab-size for code" (not (any ("tab-size" `T.isInfixOf`) (rulesOf "code" css)))
        assertBool (T.unpack page) ("<code>y</code>" `T.isInfixOf` page),
    testCase "HTML: the background and the padding of pre" $
      withCode (horizontalStyle <> codeBg) "```\nx\n```\n" $ \css _ ->
        case rulesOf "pre" css of
          [r] -> do
            assertBool (T.unpack r) ("background-color: rgb(" `T.isInfixOf` r)
            assertBool (T.unpack r) ("padding: 0.5em" `T.isInfixOf` r)
          other -> assertFailure (show other),
    testCase "HTML: without [fonts.code], monospace only" $
      withCode horizontalStyle "```\nx\n```\n" $ \css _ ->
        rulesOf "pre, code" css @?= ["pre, code { font-family: monospace; }"],
    -- golem-driver ADR 0023
    testCase "line numbers: a column of two digits, the numbers end together, none on a wrapped row" $ do
      (_, pl) <- layoutOk horizontalStyle "``` numbers=9\na\nabcdefghijklmnopqrstuvwxyz\nc\n```\n" []
      codeRows pl
        @?= [ [(pad + 5 * pt, "9"), (pad + 20 * pt, "a")],
              [(pad, "10"), (pad + 20 * pt, "abcdefghijklmnopqr")],
              [(pad + 30 * pt, "stuvwxyz")],
              [(pad, "11"), (pad + 20 * pt, "c")]
            ],
    testCase "[code] line-numbers = true numbers every block; numbers=false turns it off" $ do
      let style = horizontalStyle <> "\n[code]\nline-numbers = true\n"
      (_, pl) <- layoutOk style "```\na\n```\n\n``` numbers=false\nb\n```\n" []
      codeRows pl @?= [[(pad, "1"), (pad + 15 * pt, "a")], [(pad, "b")]],
    testCase "G0743: line numbers and diff marks leave too little measure in a list" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.code]\npadding = \"1zw\"\n"
      r <- buildAll style "- a\n  - b\n\n    ``` numbers=100 diff=true\n    +x\n    ```\n" []
      map diagMessage (codeOf r "G0743") @?= ["コードブロックの行長が足りません"]
      ok <- buildAll style "- a\n  - b\n\n    ```\n    +x\n    ```\n" []
      codeOf ok "G0743" @?= [],
    testCase "file: one more row with the file name first, not repeated after a page break" $ do
      (_, plain) <- layoutOk horizontalStyle "```\na\nb\n```\n" []
      (_, named) <- layoutOk horizontalStyle "``` file=a.hs\na\nb\n```\n" []
      codeSlots plain @?= [[(0, SCode 0 2 3)]]
      codeSlots named @?= [[(0, SCode 0 3 4)]]
      take 1 (codeRows named) @?= [[(pad, "a.hs")]]
      (_, split) <- layoutOk fiveLines "一。\n\n二。\n\n``` file=a.hs\na\nb\nc\nd\ne\n```\n" []
      codeSlots split @?= [[(2, SCode 2 2 3)], [(0, SCode 4 4 5)]]
      map (map snd) (codeRows split) @?= [["a.hs"], ["a"], ["b"], ["c"], ["d"], ["e"]],
    testCase "caption: above the block, in the caption size, outside the background" $ do
      let style = horizontalStyle <> codeBg <> "\n[code]\nnumber = \"L{n}\"\n\n[paragraph-styles.caption]\nsize = \"8pt\"\n"
      (geom, pl) <- layoutOk style "@caption 設定\n```\na\n```\n" []
      codeSlots pl @?= [[(0, SCode 0 1 3)]]
      case Map.elems (plCodes pl) of
        (ci : _) -> do
          ciCaptionSize ci @?= 8 * pt
          ciCaptionSpan ci @?= 1
          [T.concat [bcText c | Box _ c <- lineItems l] | l <- ciCaption ci] @?= ["L1　設定"]
        [] -> assertFailure "no code"
      contents <- miniPdf fakeProvider True style "@caption 設定\n```\na\n```\n" [] >>= pageContents
      let ta = firstColumn geom
          top = rectY ta + rectH ta + (15 - 10) * pt `div` 2 - 15 * pt
      case concatMap filledRects contents of
        [[_, y, _, h]] -> do
          assertBool (show (y, h, toPt top)) (abs (y + h - toPt top) < 0.001)
          assertBool (show h) (abs (h - 30) < 0.001)
        other -> assertFailure (show other),
    testCase "caption: with the first row on the next page when they do not fit" $ do
      (_, pl) <- layoutOk (fiveLines <> "\n[code]\nnumber = \"L{n}\"\n") "一。\n\n二。\n\n三。\n\n@caption 設定\n```\na\n```\n" []
      codeSlots pl @?= [[], [(0, SCode 3 1 3)]],
    testCase "highlight: a K 15% band of the row, after the background and before the text" $ do
      contents <- miniPdf fakeProvider True (horizontalStyle <> codeBg) "``` highlight=2\na\nb\n```\n" [] >>= pageContents
      case contents of
        (c : _) -> do
          case filledRects c of
            [_, [_, _, w, h]] -> do
              assertBool (show w) (abs (w - 120) < 0.001)
              assertBool (show h) (abs (h - 15) < 0.001)
            other -> assertFailure (show other)
          let (before, _) = BS.breakSubstring "BT" c
              (bg, band) = BS.breakSubstring "0 0 0 0.15 k" before
          assertBool "the background first" ("0 0 0 0.08 k" `BS.isInfixOf` bg)
          assertBool "the band before the text" (" re f" `BS.isInfixOf` band)
        [] -> assertFailure "no page"
      named <- miniPdf fakeProvider True (horizontalStyle <> "\n[color.swatches]\nhl = { cmyk = [0, 0, 30, 0] }\n\n[code]\nhighlight = \"hl\"\n") "``` highlight=2\na\nb\n```\n" [] >>= pageContents
      assertBool "the swatch" (any ("0 0 0.3 0 k" `BS.isInfixOf`) named)
      wrapped <- miniPdf fakeProvider True horizontalStyle "``` highlight=2\na\nabcdefghijklmnopqrstuvwxyzabcd\n```\n" [] >>= pageContents
      case concatMap filledRects wrapped of
        [[_, _, _, h]] -> assertBool (show h) (abs (h - 30) < 0.001)
        other -> assertFailure (show other),
    testCase "diff: the marks in their column; bands only with added and removed" $ do
      (_, pl) <- layoutOk horizontalStyle "``` diff=true\n+a\n-b\n c\n```\n" []
      codeRows pl @?= [[(pad, "+"), (pad + 10 * pt, "a")], [(pad, "-"), (pad + 10 * pt, "b")], [(pad + 10 * pt, "c")]]
      plain <- miniPdf fakeProvider True horizontalStyle "``` diff=true\n+a\n-b\n c\n```\n" [] >>= pageContents
      map filledRects plain @?= [[]]
      coloured <- miniPdf fakeProvider True (horizontalStyle <> "\n[color.swatches]\nadd = { cmyk = [20, 0, 20, 0] }\ndel = { cmyk = [0, 20, 20, 0] }\n\n[code]\nadded = \"add\"\nremoved = \"del\"\n") "``` diff=true\n+a\n-b\n c\n```\n" [] >>= pageContents
      map (length . filledRects) coloured @?= [2],
    testCase "colours: a keyword of Haskell in its swatch, the rest in the colour of the text" $ do
      let style = horizontalStyle <> "\n[color.swatches]\nkw = { cmyk = [100, 50, 0, 0] }\n\n[code.colors]\nkeyword = \"kw\"\n"
      (_, pl) <- layoutOk style "```haskell\nf x = y where y = x\n```\n" []
      let looks = [(bcText c, lkColor (bcLook c)) | sl <- Map.elems (plLines pl), Box _ c <- lineItems (slLine sl), not (T.null (bcText c))]
      [t | (t, Just "kw") <- looks] @?= ["where"]
      assertBool (show looks) (all (\(t, col) -> t == "where" || isNothing col) looks)
      plain <- miniPdf fakeProvider True horizontalStyle "```haskell\nf x = y where y = x\n```\n" [] >>= pageContents
      assertBool "no colour" (not (any (" K\n" `BS.isInfixOf`) plain))
      r <- buildAll style "```nosuchlanguage\nwhere\n```\n" []
      [diagCode d | d <- brDiagnostics r, diagSeverity d /= Notice] @?= [],
    testCase "callouts: aligned at two spaces after the longest line" $ do
      (_, pl) <- layoutOk horizontalStyle "``` callouts=true\nab <1>\nabcd <2>\n```\n" []
      codeRows pl @?= [[(pad, "ab"), (pad + 30 * pt, "①")], [(pad, "abcd"), (pad + 30 * pt, "②")]],
    testCase "callouts: each line on its own when aligning does not fit; before the mark when the line does not" $ do
      (_, pl) <- layoutOk horizontalStyle "``` callouts=true\na <1>\nabcdefghijklmnopqrs <2>\n```\n" []
      codeRows pl @?= [[(pad, "a"), (pad + 15 * pt, "①")], [(pad, "abcdefghijklmnopqrs")], [(pad + 10 * pt, "②")]],
    testCase "wrap-mark: at the end of the column on the rows that continue" $ do
      let style = horizontalStyle <> TE.encodeUtf8 "\n[code]\nwrap-mark = \"↩\"\n"
      (_, pl) <- layoutOk style "```\nabcdefghijklmnopqrstuvwxyzabcd\n```\n" []
      codeRows pl @?= [[(pad, "abcdefghijklmnopqrst"), (pad + 100 * pt, "↩")], [(pad + 10 * pt, "uvwxyzabcd")]],
    testCase "continued: the text at the end of the parts before the last, one row less in them" $ do
      let style = fiveLines <> TE.encodeUtf8 "\n[code]\ncontinued = \"（続く）\"\n"
          src = "一。\n\n二。\n\n```\na\nb\nc\nd\ne\n```\n"
      (_, plain) <- layoutOk fiveLines src []
      codeSlots plain @?= [[(2, SCode 2 2 3)], [(0, SCode 4 3 4)]]
      (_, cont) <- layoutOk style src []
      codeSlots cont @?= [[(2, SCode 2 1 3)], [(0, SCode 3 4 5)]]
      case Map.elems (plCodes cont) of
        (ci : _) -> fmap (\l -> T.concat [bcText c | Box _ c <- lineItems l]) (ciContinued ci) @?= Just "（続く）"
        [] -> assertFailure "no code",
    testCase "border: a rectangle of lines of border-width around each part" $ do
      let style = fiveLines <> "\n[color.swatches]\nline = { cmyk = [0, 0, 0, 100] }\n\n[paragraph-styles.code]\nborder = \"line\"\nborder-width = \"1pt\"\n"
      contents <- miniPdf fakeProvider True style "一。\n\n二。\n\n```\na\nb\nc\nd\ne\n```\n" [] >>= pageContents
      map (length . filledRects) contents @?= [4, 4]
      case contents of
        (c : _) -> assertBool "thin" (any (any (\x -> abs (x - 1) < 0.001) . drop 2) (filledRects c))
        [] -> assertFailure "no page",
    testCase "vertical: the line numbers before the code along the line" $ do
      (_, pl) <- layoutOk pdfStyle "``` numbers=true\nx\n```\n" []
      case codeRows pl of
        [[(a, "1"), (b, "x")]] -> assertBool (show (a, b)) (a < b)
        other -> assertFailure (show other),
    testCase "@listing with the same arguments is set as the code block" $ do
      let file = [("src/a.txt", "a\nb\nc\n")]
      (_, a) <- layoutOk horizontalStyle "@listing src/a.txt numbers=true highlight=2 file=a.txt\n" file
      (_, b) <- layoutOk horizontalStyle "``` numbers=true highlight=2 file=a.txt\na\nb\nc\n```\n" []
      codeRows a @?= codeRows b,
    testCase "the features in parallel and in sequence give the same bytes" $ do
      let style = horizontalStyle <> codeBg <> "\n[code]\nnumber = \"L{n}\"\n"
          src = "@caption c\n``` numbers=true highlight=1 diff=true callouts=true file=a\n+a <1>\n-b\n c\n```\n"
      a <- miniPdf fakeProvider True style src []
      b <- miniPdf fakeProvider False style src []
      a @?= b,
    testCase "HTML: a caption and a file wrap the block in a figure" $
      withCode (horizontalStyle <> "\n[code]\nnumber = \"L{n}\"\n") "@caption 設定\n```haskell file=a.hs\nx\n```\n\n```\ny\n```\n" $ \_ page -> do
        assertBool (T.unpack page) ("<figure class=\"listing\"><figcaption>L1　設定</figcaption><div class=\"code-file\">a.hs</div><pre>" `T.isInfixOf` page)
        assertBool (T.unpack page) ("<pre><code>y</code></pre>" `T.isInfixOf` page),
    testCase "HTML: the lines, the line numbers, the highlight, the diff and the callouts" $
      withCode horizontalStyle "``` numbers=true highlight=1 diff=true callouts=true\n+a <1>\n-b\n c\n```\n" $ \css page -> do
        assertBool (T.unpack page) ("<span class=\"line hl add\"><span class=\"ln\" aria-hidden=\"true\">1</span><span class=\"dm\" aria-hidden=\"true\">+</span>a <span class=\"callout\">①</span></span>\n" `T.isInfixOf` page)
        assertBool (T.unpack page) ("<span class=\"line del\"><span class=\"ln\" aria-hidden=\"true\"></span><span class=\"dm\" aria-hidden=\"true\">-</span>b</span>\n" `T.isInfixOf` page)
        assertBool (T.unpack page) ("<span class=\"line\"><span class=\"ln\" aria-hidden=\"true\">2</span><span class=\"dm\" aria-hidden=\"true\"> </span>c</span>" `T.isInfixOf` page)
        assertBool (T.unpack css) (any ("user-select: none" `T.isInfixOf`) (rulesOf ".ln, .dm" css))
        assertBool (T.unpack css) (any ("background-color" `T.isInfixOf`) (rulesOf "pre .hl" css)),
    testCase "HTML: the colours of [code.colors] only when it is written" $ do
      withCode (horizontalStyle <> "\n[color.swatches]\nkw = { cmyk = [100, 50, 0, 0] }\n\n[code.colors]\nkeyword = \"kw\"\n") "```haskell\nx where\n```\n" $ \css _ ->
        assertBool (T.unpack css) (any ("color: rgb(" `T.isInfixOf`) (rulesOf "code span.kw" css))
      withCode horizontalStyle "```haskell\nx where\n```\n" $ \css _ ->
        rulesOf "code span.kw" css @?= [],
    testCase "HTML: the border of pre" $
      withCode (horizontalStyle <> "\n[color.swatches]\nline = { cmyk = [0, 0, 0, 100] }\n\n[paragraph-styles.code]\nborder = \"line\"\n") "```\nx\n```\n" $ \css _ ->
        case rulesOf "pre" css of
          [r] -> assertBool (T.unpack r) ("border: 0.25pt solid rgb(" `T.isInfixOf` r)
          other -> assertFailure (show other)
  ]
  where
    -- the fake fonts: a space is half an em of 10pt; the padding is 0.5zw
    sp = 5 * pt
    pad = 5 * pt
    toPt x = fromIntegral x / 65536 :: Double
    firstColumn geom = case columnsFor geom 1 of
      (r : _) -> r
      [] -> typeAreaFor geom 1
    codeBg = "\n[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\n\n[paragraph-styles.code]\nbackground = \"code-bg\"\n"
    grid13 = replaceIn "font-size = \"10pt\"" "font-size = \"13Q\"" (replaceIn "line-pitch = \"15pt\"" "line-pitch = \"22H\"" horizontalStyle)
    -- every line but the last ends after a slash or a Japanese character
    assertSlashBreaks pl = do
      let ls = map (lineItems . slLine) (Map.elems (plLines pl))
          texts = [T.concat [bcText c | Box _ c <- l] | l <- ls]
      assertBool (show texts) (length texts > 1 && all (\t -> "/" `T.isSuffixOf` t || maybe False ((> '\x7f') . snd) (T.unsnoc t)) (take (length texts - 1) texts))
      assertBool (show texts) (T.concat texts == "あいうえおmodules/golem-driver/src/Golem/Driver/Pdf.hs")
      assertBool "no hyphen" (null [() | l <- ls, Penalty w _ PatternHyphen <- take 1 (reverse l), w > 0])
    withCode style src k = withSystemTempDirectory "golem-code-html" $ \tmp -> do
      BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n")
      BS.writeFile (tmp </> "style.toml") (withBodyFont style)
      forM_ fakeFontFiles $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
      BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 src)
      r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
      assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
      css <- TIO.readFile (tmp </> "build/html/style.css")
      page <- TIO.readFile (tmp </> "build/html/a.xhtml")
      k css page
