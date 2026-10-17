module CliSpec (newProjectTests, newPreflightTests, preflightTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.New
import Golem.LayoutSpec (PageGeometry (..), Rect (..), pageGeometry)
import Golem.Plugin.Lock (hashHex)
import Golem.Preflight.Rules (Level (..), Rules (..), parseRules, printRules)
import Golem.Preflight.View (GlyphView (..), ImageView (..), LineView (..), PageView (..), RuleView (..), View (..))
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Support
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

templateText :: Language -> FilePath -> T.Text
templateText lang file = fromMaybe "" (lookup file (templateFiles lang uuid0))

-- | The page size, vertical writing and right binding the template's style.toml lays out.
templatePage :: Language -> Either [Diagnostic] ((Integer, Integer), Bool, Bool)
templatePage lang =
  (\g -> (pgPageSize g, pgVertical g, pgBindingRight g))
    <$> (parseStyle (FileId 0) (templateText lang "style.toml") >>= pageGeometry (FileId 0) False)

templateFile :: Language -> FilePath -> IO BL.ByteString
templateFile lang file = pure (BL.fromStrict (TE.encodeUtf8 (templateText lang file)))

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
               templatePage Japanese @?= Right ((19505991, 27494158), True, True),
             testCase "the English template lays out a horizontal mass-market page bound on the left" $
               templatePage English @?= Right ((20054016, 32440320), False, False),
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
               TIO.readFile (dir </> "style.toml") >>= (@?= templateText Japanese "style.toml")
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
               listDirectory tmp >>= (@?= ["keep"])
           ]
        <> newPreflightTests
    )

-- ------------------------------------------------------------------ golem preflight (golem-cli ADR 0006)

-- | The preflight.toml of golem new (golem-cli ADR 0006).
newPreflightTests :: [TestTree]
newPreflightTests =
  [ testCase "the Japanese and English preflight.toml differ only in comments" $
      uncommented (templateText Japanese "preflight.toml") @?= uncommented (templateText English "preflight.toml"),
    testCase "preflight.toml is written without fonts" $ withSystemTempDirectory "golem-new" $ \tmp -> do
      createProject (tmp </> "book") (templateFiles English uuid0) Nothing >>= (@?= Right ())
      TIO.readFile (tmp </> "book/preflight.toml") >>= (@?= templateText English "preflight.toml"),
    testCase "a failed download writes no preflight.toml" $ withSystemTempDirectory "golem-new" $ \tmp -> do
      _ <- createProject (tmp </> "book") (templateFiles Japanese uuid0) (Just (fakeFetch (Left "offline"), [fakeFont "FONT"]))
      doesFileExist (tmp </> "book/preflight.toml") >>= assertBool "no preflight.toml" . not,
    testCase "the template reads as print, and its examples uncommented too" $
      forM_ [Japanese, English] $ \lang -> do
        let t = templateText lang "preflight.toml"
            (examples, pageCount) = T.breakOn pageCountMarker t
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
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ (bodyFontFiles style <> files) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  act tmp

preflightIn :: FilePath -> IO PreflightResult
preflightIn tmp = preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}

errorCodes :: [Diagnostic] -> [DiagnosticCode]
errorCodes = map diagCode . filter isError

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
        map (rectW . pvTrim) (vwPages v) @?= map (const (round (148 * 72 / 25.4 * 65536 :: Rational))) (vwPages v)
        assertBool "folio on every page" (all (any ((== "ノンブル") . lvKind) . pvLines) (vwPages v))
        case concatMap pvImages (vwPages v) of
          [iv] -> do
            ivPath iv @?= "images/tiny.jpg"
            -- a figure that does not wrap fills the measure: 12 characters of 10pt
            rectW (ivRect iv) @?= 120 * 65536
          other -> assertFailure (show (length other))
        sort (map rvWeight (concatMap pvRules (vwPages v))) @?= [round (0.3 * 65536 :: Rational), round (0.6 * 65536 :: Rational), round (0.6 * 65536 :: Rational)],
    testCase "the view: the rule before the footnotes is a rule of its own kind (golem-driver ADR 0024)" $
      withPreflightProject (horizontalStyle <> "\n[notes.rule]\nlength = \"5zw\"\nweight = \"0.2pt\"\n") "# 章\n\n漢[note: 注。]字\n" [] $ \tmp -> do
        p <- preflightIn tmp
        v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
        [(rvKind r, rvWeight r) | r <- concatMap pvRules (vwPages v)] @?= [("脚注の罫線", round (0.2 * 65536 :: Rational))],
    testCase "the view: the weight of a rule is its thinnest part, its colour a swatch used (golem-driver ADR 0028)" $ do
      let weightOf st = withPreflightProject (horizontalStyle <> "\n[notes.rule]\nlength = \"5zw\"\nweight = \"1.2pt\"\nstyle = \"" <> st <> "\"\n") "# 章\n\n漢[note: 注。]字\n" [] $ \tmp -> do
            p <- preflightIn tmp
            v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
            pure (map rvWeight (concatMap pvRules (vwPages v)))
          w = round (1.2 * 65536 :: Rational)
      weightOf "thin-thin" >>= (@?= [w `div` 3])
      weightOf "wavy" >>= (@?= [w `div` 4])
      weightOf "dotted" >>= (@?= [w])
      withPreflightProject (horizontalStyle <> "\n[color.swatches]\nheavy = { cmyk = [100, 100, 100, 100] }\n\n[notes.rule]\nlength = \"5zw\"\ncolor = \"heavy\"\n") "# 章\n\n漢[note: 注。]字\n" [] $ \tmp -> do
        p <- preflightIn tmp
        v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
        Map.keys (vwSwatchesUsed v) @?= ["heavy"]
        assertBool (show (prDiagnostics p)) (DiagnosticCode "G0915" `elem` map diagCode (prDiagnostics p)),
    testCase "a character the font has not is glyph 0 in the view (with real fonts)" $ withSystemTempDirectory "golem-preflight" $ \tmp -> do
      copyTree fixture tmp
      createDirectoryIfMissing True (tmp </> "fonts")
      copyFile "../golem-font/test/fonts/SourceHanSans-Regular_subset.otf" (tmp </> "fonts/ja.otf")
      BS.writeFile (tmp </> "style.toml") (pdfStyle <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\n")
      BS.appendFile (tmp </> "chapters/02.gm") (TE.encodeUtf8 "\n私用\xE000。\n")
      p <- preflight (defaultPreflightOptions tmp)
      v <- maybe (assertFailure (show (prDiagnostics p))) pure (prView p)
      assertBool "glyph 0 of U+E000" (any (any (\g -> gvGlyph g == 0 && gvText g == "\xE000") . pvGlyphs) (vwPages v))
      assertBool "G0902" (DiagnosticCode "G0902" `elem` errorCodes (prDiagnostics p)),
    testCase "a PDF as a figure is G0905" $
      withPreflightProject horizontalStyle "# 章\n\n@figure images/a.pdf web=images/a.png alt=\"t\"\n\n本文。\n" [("images/a.pdf", "%PDF-1.4\n"), ("images/a.png", "png")] $ \tmp -> do
        p <- preflightIn tmp
        assertEqual (show (prDiagnostics p)) [DiagnosticCode "G0905"] (map diagCode (filter ((== DiagnosticCode "G0905") . diagCode) (prDiagnostics p))),
    {- the profile is prod: G0205 is reported in prod only. G0504, the
    example of the ADR, is a diagnostic of golem lint, which neither golem
    build nor golem preflight runs. -}
    testCase "the profile is prod (G0205 is reported in prod only)" $
      withPreflightProject horizontalStyle "本文。 %%= 校正 %%\n" [] $ \tmp -> do
        p <- preflightIn tmp
        [diagSeverity d | d <- prDiagnostics p, diagCode d == DiagnosticCode "G0205"] @?= [Warning]
        assertBool "a view" (isJust (prView p)),
    testCase "an error of the build stops before the checks" $
      withPreflightProject horizontalStyle "[nope: x]\n" [] $ \tmp -> do
        p <- preflightIn tmp
        assertBool "errors" (not (null (errorCodes (prDiagnostics p))))
        assertBool "no view" (isNothing (prView p)),
    testCase "rules out of the project are read, a missing file is G0901" $
      withPreflightProject horizontalStyle "本文。\n" [] $ \tmp -> withSystemTempDirectory "golem-rules" $ \other -> do
        TIO.writeFile (other </> "printer.toml") "based-on = \"none\"\nname = \"A 印刷\"\n"
        p <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider, poRules = Just (other </> "printer.toml")}
        prRulesLabel p @?= "A 印刷"
        prBasedOn p @?= "none"
        errorCodes (prDiagnostics p) @?= []
        q <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider, poRules = Just (other </> "missing.toml")}
        map diagCode (prDiagnostics q) @?= [DiagnosticCode "G0901"]
        prPdf q @?= Nothing,
    testCase "a wrong preflight.toml stops before the PDF" $
      withPreflightProject horizontalStyle "本文。\n" [("preflight.toml", "[pdf-x]\nseverity = \"notice\"\n")] $ \tmp -> do
        p <- preflightIn tmp
        map diagCode (prDiagnostics p) @?= [DiagnosticCode "G0901"]
        prPdf p @?= Nothing
  ]
    <> [ testCase ("the template fails print with G0910 and G0914 only, and passes with bleed and intent (" <> tag <> ")") $ withSystemTempDirectory "golem-new" $ \tmp -> do
           let dir = tmp </> "book"
           createProject dir (templateFiles lang uuid0) Nothing >>= (@?= Right ())
           forM_ (templateFonts lang) $ \f -> createDirectoryIfMissing True (takeDirectory (dir </> fsPath f)) >> BS.writeFile (dir </> fsPath f) "fake"
           p <- preflightIn dir
           sort (errorCodes (prDiagnostics p)) @?= [DiagnosticCode "G0910", DiagnosticCode "G0914"]
           [diagMessage d | d <- prDiagnostics p, diagCode d == DiagnosticCode "G0914"] @?= ["PDF/X-4 の要件を満たしていません: 出力インテントがありません（style.toml の [color] に intent を書きます）"]
           style <- TIO.readFile (dir </> "style.toml")
           TIO.writeFile (dir </> "style.toml") (T.replace "[page]\n" "[page]\nbleed = \"3mm\"\n" style <> "\n[color]\nintent = \"profiles/test.icc\"\n")
           createDirectoryIfMissing True (dir </> "profiles")
           BS.writeFile (dir </> "profiles/test.icc") "fake profile"
           q <- preflightIn dir
           errorCodes (prDiagnostics q) @?= []
       | (lang, tag) <- [(Japanese, "ja"), (English, "en")]
       ]
