module CliSpec (newProjectTests, newPreflightTests, preflightTests) where

import Control.Exception (try)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.New
import Golem.LayoutSpec (PageGeometry (..), Rect (..), pageGeometry)
import Golem.Length (Sp (..))
import Golem.Plugin.Lock (hashHex)
import Golem.Preflight.Rules (Level (..), Rules (..), parseRules, printRules)
import Golem.Preflight.View (GlyphView (..), ImageView (..), LineView (..), PageView (..), RuleView (..), View (..))
import Golem.Project.Style (Page (..), Style (..), parseDim, parseStyle)
import Golem.Syntax
import Support
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

-- | A file of the template; one that is not in it fails the test (docs/adr/0064).
templateText :: Language -> FilePath -> IO T.Text
templateText lang file = maybe (assertFailure ("the template has no " <> file)) pure (lookup file (templateFiles lang uuid0))

-- | The page size, vertical writing and right binding the template's style.toml lays out.
templatePage :: Language -> IO (Either [Diagnostic] ((Sp, Sp), Bool, Bool))
templatePage lang = do
  style <- templateText lang "style.toml"
  pure ((\g -> (pgPageSize g, pgVertical g, pgBindingRight g)) <$> (parseStyle (FileId 0) style >>= pageGeometry (FileId 0) False))

templateFile :: Language -> FilePath -> IO BL.ByteString
templateFile lang file = BL.fromStrict . TE.encodeUtf8 <$> templateText lang file

fakeFont :: BS.ByteString -> FontSource
fakeFont bytes = FontSource "fonts/a.otf" "https://example.com/a.otf" (hashHex bytes)

fakeFetch :: Either T.Text BS.ByteString -> T.Text -> IO (Either T.Text BS.ByteString)
fakeFetch r _ = pure r

newProjectTests :: TestTree
newProjectTests =
  testGroup
    "golem new (golem-cli ADR 0003)"
    ( [ goldenVsString ("new-" <> tag <> "-" <> name) ("test/golden/new-" <> tag <> "-" <> name) (templateFile lang file)
      | (lang, tag) <- [(Japanese, "ja"), (English, "en")],
        (name, file) <- [("manifest.toml", "manifest.toml"), ("style.toml", "style.toml"), ("01.gm", "chapters/01.gm"), ("preflight.toml", "preflight.toml")]
      ]
        <> [ -- A6 is 105 x 148 mm, at 72/25.4 pt per mm and 65536 sp per pt (rounded);
             -- mass-market is 4.25 x 6.875 in, 306 x 495 pt
             testCase "the Japanese template lays out a vertical A6 page bound on the right" $
               templatePage Japanese >>= (@?= Right ((19505991, 27494158), True, True)),
             testCase "the English template lays out a horizontal mass-market page bound on the left" $
               templatePage English >>= (@?= Right ((20054016, 32440320), False, False)),
             -- golem-pdf ADR 0010, golem-project ADR 0010
             testCase "the templates have a bleed: 3mm for Japanese, 0.125in (9pt) for English" $ do
               let bleedOf lang = fmap (fmap pageBleed . stPage) . parseStyle (FileId 0) <$> templateText lang "style.toml"
               bleedOf Japanese >>= (@?= Right (Just (Sp (round (3 * 72 * 65536 / (25.4 :: Rational))))))
               bleedOf English >>= (@?= Right (Just (9 * 65536)))
               parseDim "0.125in" @?= parseDim "9pt",
             testCase "fonts come from tagged releases with fixed hashes" $ do
               map fsPath (templateFonts Japanese) @?= ["fonts/NotoSerifJP-Regular.otf", "fonts/LICENSE-NotoSerifJP.txt"]
               map fsPath (templateFonts English) @?= ["fonts/SourceSerif4-Regular.otf", "fonts/LICENSE-SourceSerif4.md"]
               map fsSha256 (templateFonts Japanese)
                 @?= [ "2c9a12dbd4f2408c4610c7ee84a108b62d7236c3775baed618c64d9cb44b2f04",
                       "6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2"
                     ]
               map fsSha256 (templateFonts English)
                 @?= [ "edf160d0d584deee8a3bb2c3371b2a7624ca63580fbe02c57c1f4c91e84d8787",
                       "75784a295293a8992f5a8d99210566e0064a012e6dab6731305e3787f15896c7"
                     ]
               assertBool "HTTPS" (all (("https://raw.githubusercontent.com/" `T.isPrefixOf`) . fsUrl) (templateFonts Japanese <> templateFonts English)),
             testCase "fetched fonts are written next to the template" $ withSystemTempDirectory "golem-new" $ \tmp -> do
               let dir = tmp </> "book"
               r <- createProject dir (templateFiles Japanese uuid0) (Just (fakeFetch (Right "FONT"), [fakeFont "FONT"]))
               r @?= Right ()
               BS.readFile (dir </> "fonts/a.otf") >>= (@?= "FONT")
               expected <- templateText Japanese "style.toml"
               TIO.readFile (dir </> "style.toml") >>= (@?= expected)
               TIO.readFile (dir </> ".gitignore") >>= (@?= "build/\n"),
             testCase "a hash mismatch writes nothing" $ withSystemTempDirectory "golem-new" $ \tmp -> do
               let dir = tmp </> "book"
               r <- createProject dir (templateFiles Japanese uuid0) (Just (fakeFetch (Right "OTHER"), [fakeFont "FONT"]))
               assertBool "error" (either (const True) (const False) r)
               doesDirectoryExist dir >>= assertBool "no directory" . not,
             testCase "a failed download writes nothing" $ withSystemTempDirectory "golem-new" $ \tmp -> do
               let dir = tmp </> "book"
               r <- createProject dir (templateFiles English uuid0) (Just (fakeFetch (Left "offline"), [fakeFont "FONT"]))
               assertBool "error" (either (const True) (const False) r)
               doesDirectoryExist dir >>= assertBool "no directory" . not,
             testCase "without fonts nothing is fetched and the style still names them" $ withSystemTempDirectory "golem-new" $ \tmp -> do
               let dir = tmp </> "book"
               r <- createProject dir (templateFiles English uuid0) Nothing
               r @?= Right ()
               doesDirectoryExist (dir </> "fonts") >>= assertBool "no fonts" . not
               TIO.readFile (dir </> "style.toml") >>= assertBool "font path" . T.isInfixOf "fonts/SourceSerif4-Regular.otf",
             testCase "a directory that is not empty is left alone" $ withSystemTempDirectory "golem-new" $ \tmp -> do
               BS.writeFile (tmp </> "keep") "x"
               r <- createProject tmp (templateFiles Japanese uuid0) Nothing
               assertBool "error" (either (const True) (const False) r)
               listDirectory tmp >>= (@?= ["keep"]),
             testCase "a file the template does not have fails the test, not an empty golden (docs/adr/0064)" $ do
               r <- try (templateText Japanese "no-such-file")
               case r of
                 Left (HUnitFailure _ _) -> pure ()
                 Right t -> assertFailure ("returned " <> show t)
           ]
        <> newPreflightTests
    )

-- ------------------------------------------------------------------ golem preflight (golem-cli ADR 0006)

-- | The preflight.toml of golem new (golem-cli ADR 0006).
newPreflightTests :: [TestTree]
newPreflightTests =
  [ testCase "the Japanese and English preflight.toml differ only in comments" $
      do
        ja <- templateText Japanese "preflight.toml"
        en <- templateText English "preflight.toml"
        uncommented ja @?= uncommented en,
    testCase "preflight.toml is written without fonts" $ withSystemTempDirectory "golem-new" $ \tmp -> do
      createProject (tmp </> "book") (templateFiles English uuid0) Nothing >>= (@?= Right ())
      expected <- templateText English "preflight.toml"
      TIO.readFile (tmp </> "book/preflight.toml") >>= (@?= expected),
    testCase "a failed download writes no preflight.toml" $ withSystemTempDirectory "golem-new" $ \tmp -> do
      _ <- createProject (tmp </> "book") (templateFiles Japanese uuid0) (Just (fakeFetch (Left "offline"), [fakeFont "FONT"]))
      doesFileExist (tmp </> "book/preflight.toml") >>= assertBool "no preflight.toml" . not,
    testCase "the template reads as print, and its examples uncommented too" $
      forM_ [Japanese, English] $ \lang -> do
        t <- templateText lang "preflight.toml"
        let (examples, pageCount) = T.breakOn pageCountMarker t
        parseRules (FileId 0) t @?= Right printRules
        parseRules (FileId 0) (uncomment examples <> pageCount) @?= Right printRules
        parseRules (FileId 0) (uncomment t) @?= Right printRules {ruPageCount = LevelError, ruPageMultiple = 16}
  ]
  where
    uncommented = T.unlines . filter (not . ("#" `T.isPrefixOf`)) . T.lines
    -- the comment line just before the page-count example
    pageCountMarker = "\n# [page-count]"
    -- the example lines: "# " taken off the lines of keys and tables
    uncomment = T.unlines . map one . T.lines
    one l = case T.stripPrefix "# " l of
      Just rest | isSetting rest -> rest
      _ -> l
    isSetting r = "[" `T.isPrefixOf` r || (" = " `T.isInfixOf` r && not ("name" `T.isPrefixOf` r))

-- | A one-chapter project for golem preflight, with the fake fonts.
withPreflightProject :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withPreflightProject style source files act = withSystemTempDirectory "golem-preflight" $ \tmp -> do
  writeProject tmp miniManifest style source files
  act tmp

preflightIn :: FilePath -> IO PreflightResult
preflightIn tmp = preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}

errorCodes :: [Diagnostic] -> [DiagnosticCode]
errorCodes = map diagCode . filter isError

-- | A style with the swatch rich of two inks and a character style ink of that colour and no size (golem-cli ADR 0008).
inkStyle :: BS.ByteString -> BS.ByteString
inkStyle extra = horizontalStyle <> "\n[color.swatches]\nrich = { cmyk = [100, 0, 0, 100] }\n\n[character-styles.ink]\ncolor = \"rich\"\n" <> extra

-- | The G09004 of golem preflight on a source: the start of each and its message.
smallText :: BS.ByteString -> T.Text -> IO [(Int, T.Text)]
smallText style source = withPreflightProject style source [] $ \tmp -> do
  p <- preflightIn tmp
  pure [(spanStart (diagSpan d), diagMessage d) | d <- prDiagnostics p, diagCode d == DiagnosticCode "G09004"]

-- | The byte offset of the first occurrence of a text in a source.
byteAt :: T.Text -> T.Text -> Int
byteAt needle source = BS.length (TE.encodeUtf8 (fst (T.breakOn needle source)))

-- | Whether a message names a definition.
names :: T.Text -> (Int, T.Text) -> Bool
names what (_, m) = what `T.isInfixOf` m

g0904Tests :: [TestTree]
g0904Tests =
  [ testCase "G09004: two paragraph styles of one size, one per style, at their text (golem-cli ADR 0008)" $ do
      let style = inkStyle "\n[paragraph-styles.a]\nsize = \"4pt\"\n\n[paragraph-styles.b]\nsize = \"4pt\"\n"
          source = "@style a\n  [style ink: 一の字。]\n\n@style b\n  [style ink: 二の字。]\n"
      ds <- smallText style source
      map fst ds @?= [byteAt "一の字" source, byteAt "二の字" source]
      assertBool (show ds) (and (zipWith names ["段落スタイル a の size", "段落スタイル b の size"] ds)),
    testCase "G09004: a paragraph style based on another without a size is in the group of that one (golem-cli ADR 0008)" $ do
      let style = inkStyle "\n[paragraph-styles.a]\nsize = \"4pt\"\n\n[paragraph-styles.c]\nbased-on = \"a\"\n"
          source = "@style a\n  [style ink: 一の字。]\n\n@style c\n  [style ink: 二の字。]\n"
      ds <- smallText style source
      map fst ds @?= [byteAt "一の字" source]
      assertBool (show ds) (all (names "段落スタイル a の size") ds),
    testCase "G09004: a character style of a small size, at the text inside it (golem-cli ADR 0008)" $ do
      let style = inkStyle "\n[character-styles.s]\nsize = \"4pt\"\ncolor = \"rich\"\n"
          source = "大きな本文の段落の中の[style s: 小字]です。\n"
      ds <- smallText style source
      map fst ds @?= [byteAt "小字" source]
      assertBool (show ds) (all (names "文字スタイル s の size") ds),
    testCase "G09004: a small word in a long paragraph is at the word, not the block (golem-cli ADR 0008)" $ do
      let style = inkStyle "\n[character-styles.s]\nsize = \"4pt\"\ncolor = \"rich\"\n"
          source = T.replicate 40 "長い段落の本文。" <> "[style s: 小字]" <> T.replicate 10 "続き。" <> "\n"
      ds <- smallText style source
      map fst ds @?= [byteAt "小字" source],
    testCase "G09004: a note set at the page foot comes in the order of the source, and a line before it moves nothing (golem-cli ADR 0008)" $ do
      let style = inkStyle "\n[character-styles.s]\nsize = \"4pt\"\ncolor = \"rich\"\n\n[character-styles.t]\nsize = \"3pt\"\ncolor = \"rich\"\n"
          body = "本文[note: [style s: 注の小字]。]。\n\n[style t: 本文の小字]。\n"
          added = "足した一行。\n\n"
      ds <- smallText style body
      -- the note is drawn below the text after it, but comes first
      map fst ds @?= [byteAt "注の小字" body, byteAt "本文の小字" body]
      assertBool (show ds) (and (zipWith names ["文字スタイル s の size", "文字スタイル t の size"] ds))
      moved <- smallText style (added <> body)
      map (subtract (BS.length (TE.encodeUtf8 added)) . fst) moved @?= map fst ds
  ]

preflightTests :: [TestTree]
preflightTests =
  [ testCase "the PDF checked is the PDF of build --profile prod, not of dev" $
      withPreflightProject horizontalStyle "本文。\n" [] $ \tmp -> do
        p <- preflightIn tmp
        pdf <- maybe (assertFailure "no PDF") pure (prPdf p)
        let built profile = do
              r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = profile}
              case filter (".pdf" `isSuffixOf`) (brWritten r) of
                [path] -> BS.readFile path
                other -> assertFailure (show other)
        prod <- built Prod
        dev <- built Dev
        assertBool "prod" (pdf == prod)
        assertBool "dev" (pdf /= dev),
    -- golem-driver ADR 0029
    testCase "the view: the background of inline code is a swatch used" $
      withPreflightProject (horizontalStyle <> "\n[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\n\n[character-styles.code]\nbackground = \"code-bg\"\n") "本文の[code: x]。\n" [] $ \tmp -> do
        p <- preflightIn tmp
        v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
        Map.lookup "code-bg" (vwSwatchesUsed v) @?= Just (0, 0, 0, 8),
    testCase "the view: the trimmed page, the folio, the image and the table rules" $ do
      img <- tinyImage
      let source = "# 章\n\n@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n\n| a | b |\n|---|---|\n| c | d |\n\n本文。\n"
      withPreflightProject (horizontalStyle <> "\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n") source img $ \tmp -> do
        p <- preflightIn tmp
        v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
        -- A5: 148mm wide
        map (rectW . pvTrim) (vwPages v) @?= map (const (Sp (round (148 * 72 / 25.4 * 65536 :: Rational)))) (vwPages v)
        assertBool "folio on every page" (all (any ((== "ノンブル") . lvKind) . pvLines) (vwPages v))
        case concatMap pvImages (vwPages v) of
          [iv] -> do
            ivPath iv @?= "images/tiny.jpg"
            -- a figure that does not wrap fills the measure: 12 characters of 10pt
            rectW (ivRect iv) @?= 120 * 65536
          other -> assertFailure (show (length other))
        sort (map rvWeight (concatMap pvRules (vwPages v))) @?= [Sp (round (0.3 * 65536 :: Rational)), Sp (round (0.6 * 65536 :: Rational)), Sp (round (0.6 * 65536 :: Rational))],
    testCase "the view: the rule before the footnotes is a rule of its own kind (golem-driver ADR 0024)" $
      withPreflightProject (horizontalStyle <> "\n[notes.rule]\nlength = \"5zw\"\nweight = \"0.2pt\"\n") "# 章\n\n漢[note: 注。]字\n" [] $ \tmp -> do
        p <- preflightIn tmp
        v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
        [(rvKind r, rvWeight r) | r <- concatMap pvRules (vwPages v)] @?= [("脚注の罫線", Sp (round (0.2 * 65536 :: Rational)))],
    testCase "the view: the weight of a rule is its thinnest part, its colour a swatch used (golem-driver ADR 0028)" $ do
      let weightOf st = withPreflightProject (horizontalStyle <> "\n[notes.rule]\nlength = \"5zw\"\nweight = \"1.2pt\"\nstyle = \"" <> st <> "\"\n") "# 章\n\n漢[note: 注。]字\n" [] $ \tmp -> do
            p <- preflightIn tmp
            v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
            pure (map rvWeight (concatMap pvRules (vwPages v)))
          w = Sp (round (1.2 * 65536 :: Rational))
      weightOf "thin-thin" >>= (@?= [Sp (unSp w `div` 3)])
      weightOf "wavy" >>= (@?= [Sp (unSp w `div` 4)])
      weightOf "dotted" >>= (@?= [w])
      withPreflightProject (horizontalStyle <> "\n[color.swatches]\nheavy = { cmyk = [100, 100, 100, 100] }\n\n[notes.rule]\nlength = \"5zw\"\ncolor = \"heavy\"\n") "# 章\n\n漢[note: 注。]字\n" [] $ \tmp -> do
        p <- preflightIn tmp
        v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
        Map.keys (vwSwatchesUsed v) @?= ["heavy"]
        assertBool (show (prDiagnostics p)) (DiagnosticCode "G09015" `elem` map diagCode (prDiagnostics p)),
    testCase "the view: paragraph rules are of their own kind; one near the trim is G09012 (golem-driver ADR 0027)" $ do
      let ruled extra = horizontalStyle <> "\n[paragraph-styles.sec]\nrule-before = { weight = \"0.5pt\"" <> extra <> " }\n"
          source = "前。\n\n@style sec\n  節。\n"
      withPreflightProject (ruled "") source [] $ \tmp -> do
        p <- preflightIn tmp
        v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
        [rvKind r | r <- concatMap pvRules (vwPages v)] @?= ["段落の罫線"]
        assertBool (show (prDiagnostics p)) (DiagnosticCode "G09012" `notElem` map diagCode (prDiagnostics p))
      withPreflightProject (ruled ", start-indent = \"-19mm\"") source [] $ \tmp -> do
        p <- preflightIn tmp
        assertBool (show (prDiagnostics p)) (DiagnosticCode "G09012" `elem` map diagCode (prDiagnostics p)),
    testCase "a character the font has not is glyph 0 in the view (with real fonts)" $ withSystemTempDirectory "golem-preflight" $ \tmp -> do
      copyTree fixture tmp
      createDirectoryIfMissing True (tmp </> "fonts")
      copyFile "../golem-font/test/fonts/SourceHanSans-Regular_subset.otf" (tmp </> "fonts/ja.otf")
      BS.writeFile (tmp </> "style.toml") (pdfStyle <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\n")
      BS.appendFile (tmp </> "chapters/02.gm") (TE.encodeUtf8 "\n私用\xE000。\n")
      p <- preflight (defaultPreflightOptions tmp)
      v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
      assertBool "glyph 0 of U+E000" (any (any (\g -> gvGlyph g == 0 && gvText g == "\xE000") . pvGlyphs) (vwPages v))
      assertBool "G09002" (DiagnosticCode "G09002" `elem` errorCodes (prDiagnostics p)),
    testCase "a character the font has not: the G08100 of the build, an error, beside G09002 (docs/adr 0081)" $ do
      let privateUse rules = withSystemTempDirectory "golem-preflight" $ \tmp -> do
            copyTree fixture tmp
            createDirectoryIfMissing True (tmp </> "fonts")
            copyFile "../golem-font/test/fonts/SourceHanSans-Regular_subset.otf" (tmp </> "fonts/ja.otf")
            BS.writeFile (tmp </> "style.toml") (pdfStyle <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\n")
            forM_ rules (BS.writeFile (tmp </> "preflight.toml"))
            BS.appendFile (tmp </> "chapters/02.gm") (TE.encodeUtf8 "\n私用\xE000。\n")
            p <- preflight (defaultPreflightOptions tmp)
            assertBool "the PDF is checked" (isJust (prView p))
            pure [(diagCode d, diagSeverity d, diagSpan d, diagMessage d) | d <- prDiagnostics p, "U+E000" `T.isInfixOf` diagMessage d]
      found <- privateUse Nothing
      case found of
        [(c1, s1, sp1, m1), (c2, s2, sp2, m2)] -> do
          (c1, s1, c2, s2) @?= (DiagnosticCode "G08100", Error, DiagnosticCode "G09002", Error)
          (sp1, m1) @?= (sp2, m2)
        other -> assertFailure (show other)
      warned <- privateUse (Just "[glyph-missing]\nseverity = \"warning\"\n")
      [(c, sev) | (c, sev, _, _) <- warned] @?= [(DiagnosticCode "G08100", Error), (DiagnosticCode "G09002", Warning)]
      off <- privateUse (Just "[glyph-missing]\nseverity = \"off\"\n")
      [(c, sev) | (c, sev, _, _) <- off] @?= [(DiagnosticCode "G08100", Error)],
    testCase "a PDF as a figure is placed, with neither G09005 nor G08010 (golem-pdf ADR 0008)" $ do
      fig <- miniPdf fakeProvider False horizontalStyle "図。\n" []
      img <- tinyImage
      withPreflightProject horizontalStyle "# 章\n\n@figure images/a.pdf web=images/tiny.jpg alt=\"t\"\n\n本文。\n" (("images/a.pdf", fig) : img) $ \tmp -> do
        p <- preflightIn tmp
        let codes = map diagCode (prDiagnostics p)
        assertBool (show codes) (DiagnosticCode "G09005" `notElem` codes && DiagnosticCode "G08010" `notElem` codes)
        v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
        map ivPath (concatMap pvImages (vwPages v)) @?= ["images/a.pdf"],
    testCase "an SVG figure is G09008 (rgb) in print, and not G09006 (golem-pdf ADR 0009)" $
      withPreflightProject horizontalStyle "# 章\n\n@figure images/a.svg alt=\"t\"\n\n本文。\n" [("images/a.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"5\" height=\"5\" fill=\"red\"/></svg>")] $ \tmp -> do
        p <- preflightIn tmp
        let codes = map diagCode (prDiagnostics p)
        assertBool (show codes) (DiagnosticCode "G09008" `elem` codes && DiagnosticCode "G09006" `notElem` codes),
    testCase "a figure that cannot be placed stops golem preflight with G08010 before the checks (golem-pdf ADR 0008)" $
      withPreflightProject horizontalStyle "# 章\n\n@figure images/a.png alt=\"t\"\n\n本文。\n" [("images/a.png", "\x89PNG\r\n\x1a\n")] $ \tmp -> do
        p <- preflightIn tmp
        errorCodes (prDiagnostics p) @?= [DiagnosticCode "G08010"]
        assertBool "no view" (isNothing (prView p)),
    testCase "image-unplaceable in preflight.toml is G09001 (golem-pdf ADR 0008)" $
      withPreflightProject horizontalStyle "本文。\n" [("preflight.toml", "[image-unplaceable]\nseverity = \"off\"\n")] $ \tmp -> do
        p <- preflightIn tmp
        map diagCode (prDiagnostics p) @?= [DiagnosticCode "G09001"],
    {- the profile is prod: G02005 is reported in prod only. G05004, the
    example of the ADR, is a diagnostic of golem lint, which neither golem
    build nor golem preflight runs. -}
    testCase "the profile is prod (G02005 is reported in prod only)" $
      withPreflightProject horizontalStyle "本文。 %%= 校正 %%\n" [] $ \tmp -> do
        p <- preflightIn tmp
        [diagSeverity d | d <- prDiagnostics p, diagCode d == DiagnosticCode "G02005"] @?= [Warning]
        assertBool "a view" (isJust (prView p)),
    testCase "an error of the build stops before the checks" $
      withPreflightProject horizontalStyle "[nope: x]\n" [] $ \tmp -> do
        p <- preflightIn tmp
        errorCodes (prDiagnostics p) @?= [DiagnosticCode "G02022"]
        assertBool "no view" (isNothing (prView p)),
    testCase "rules out of the project are read, a missing file is G09001" $
      withPreflightProject horizontalStyle "本文。\n" [] $ \tmp -> withSystemTempDirectory "golem-rules" $ \other -> do
        TIO.writeFile (other </> "printer.toml") "based-on = \"none\"\nname = \"A 印刷\"\n"
        p <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider, poRules = Just (other </> "printer.toml")}
        prRulesLabel p @?= "A 印刷"
        prBasedOn p @?= "none"
        errorCodes (prDiagnostics p) @?= []
        q <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider, poRules = Just (other </> "missing.toml")}
        map diagCode (prDiagnostics q) @?= [DiagnosticCode "G09001"]
        prPdf q @?= Nothing,
    testCase "a wrong preflight.toml stops before the PDF" $
      withPreflightProject horizontalStyle "本文。\n" [("preflight.toml", "[pdf-x]\nseverity = \"notice\"\n")] $ \tmp -> do
        p <- preflightIn tmp
        map diagCode (prDiagnostics p) @?= [DiagnosticCode "G09001"]
        prPdf p @?= Nothing
  ]
    <> [ testCase ("the template fails print with G09014 only, and passes with intent; it has a bleed (golem-pdf ADR 0010) (" <> tag <> ")") $ withSystemTempDirectory "golem-new" $ \tmp -> do
           let dir = tmp </> "book"
           createProject dir (templateFiles lang uuid0) Nothing >>= (@?= Right ())
           writeFiles dir [(fsPath f, "fake") | f <- templateFonts lang]
           p <- preflightIn dir
           sort (errorCodes (prDiagnostics p)) @?= [DiagnosticCode "G09014"]
           [diagMessage d | d <- prDiagnostics p, diagCode d == DiagnosticCode "G09014"] @?= ["PDF/X-4 の要件を満たしていません: 出力インテントがありません（style.toml の [color] に intent を書きます）"]
           style <- TIO.readFile (dir </> "style.toml")
           TIO.writeFile (dir </> "style.toml") (style <> "\n[color]\nintent = \"profiles/test.icc\"\n")
           createDirectoryIfMissing True (dir </> "profiles")
           BS.writeFile (dir </> "profiles/test.icc") "fake profile"
           q <- preflightIn dir
           errorCodes (prDiagnostics q) @?= []
       | (lang, tag) <- [(Japanese, "ja"), (English, "en")]
       ]
    <> g0904Tests
