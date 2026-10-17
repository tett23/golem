module BuildSpec (buildTests, allTargetsTests, versionTests, producerTests, publicDomainTests, numberSeparatorTests, styleFileTests) where

import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.IORef (newIORef, readIORef)
import Data.List (isSuffixOf, sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, listToMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (HeadingInfo (..))
import Golem.Doc.IR (InlineF (..))
import Golem.Driver
import Golem.Driver.New
import Golem.Driver.Pdf (instanceIdInputs, numberedTitle, producer, runningHeadLines)
import Golem.Driver.Version (golemVersion)
import Golem.Epub (EpubConfig (..), navDocument)
import Golem.Project (Project (..), ProjectFailure (..))
import Golem.Project.Manifest (Manifest (..), Metadata (..))
import Golem.Project.Style (HeadForm (..), HeadPick (..), RunningContent (..), RunningPart (..), RunningRef (..))
import Golem.Syntax
import Support
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | Replaces the [targets.*] tables of the copied fixture's manifest.
setTargets :: FilePath -> T.Text -> IO ()
setTargets root targets = do
  m <- TIO.readFile (root </> "manifest.toml")
  TIO.writeFile (root </> "manifest.toml") (fst (T.breakOn "[targets." m) <> targets)

versionTests :: TestTree
versionTests =
  testGroup
    "version (docs/adr/0004)"
    [ testCase "the version Golem reports is the content of VERSION" $ do
        v <- T.strip <$> TIO.readFile "../../VERSION"
        golemVersion @?= v,
      testCase "the PDF instance ID is computed from golem- and the version, last" $ do
        let inputs = instanceIdInputs ["input"] ["font program"]
        inputs @?= ["input", "font program", TE.encodeUtf8 ("golem-" <> golemVersion)]
        last inputs @?= TE.encodeUtf8 ("golem-" <> golemVersion)
    ]

producerTests :: TestTree
producerTests =
  testGroup
    "Producer (golem-pdf ADR 0005)"
    [ testCase "the Producer is Golem and the version" $
        producer @?= "Golem " <> golemVersion,
      testCase "the version has the form check-version.sh accepts" $ do
        let (core, pre) = T.breakOn "-" golemVersion
            numbers = T.splitOn "." core
            preOk = T.null pre || (T.length pre > 1 && T.all (\c -> isAsciiAlnum c || c == '.' || c == '-') (T.drop 1 pre))
            isAsciiAlnum c = isDigit c || isAsciiLower c || isAsciiUpper c
        assertBool (T.unpack golemVersion) (length numbers == 3 && all (\n -> not (T.null n) && T.all isDigit n) numbers && preOk),
      testCase "the PDF has the Producer in the information dictionary, and in XMP with an output intent" $ do
        plain <- miniPdf fakeProvider True horizontalStyle "x\n" []
        assertBool "Info" (TE.encodeUtf8 ("/Producer (" <> producer <> ")") `BS.isInfixOf` plain)
        assertBool "no XMP" (not ("<pdf:Producer>" `BS.isInfixOf` plain))
        x4 <- miniPdf fakeProvider True (horizontalStyle <> "\n[color]\nintent = \"x.icc\"\n") "x\n" [("x.icc", "fake profile")]
        assertBool "Info with an intent" (TE.encodeUtf8 ("/Producer (" <> producer <> ")") `BS.isInfixOf` x4)
        assertBool "XMP" (TE.encodeUtf8 ("<pdf:Producer>" <> producer <> "</pdf:Producer>") `BS.isInfixOf` x4)
    ]

buildTests :: [TestTree]
buildTests =
  [ golden "text-horizontal-01.txt" "build/text/horizontal/chapters/01.txt",
    golden "text-vertical-01.txt" "build/text/vertical/chapters/01.txt",
    golden "html-01.xhtml" "build/html/chapters/01.xhtml",
    golden "html-front.xhtml" "build/html/front.xhtml",
    golden "html-02.xhtml" "build/html/chapters/02.xhtml",
    golden "html-style.css" "build/html/style.css",
    testCase "two builds produce identical bytes" $ do
      a <- buildAndRead Dev "build/html/chapters/01.xhtml"
      b <- buildAndRead Dev "build/html/chapters/01.xhtml"
      a @?= b
      c <- buildAndRead Dev "build/text/vertical/chapters/01.txt"
      d <- buildAndRead Dev "build/text/vertical/chapters/01.txt"
      c @?= d,
    testCase "prod drops proofreading comments and warns" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
      copyTree fixture tmp
      r <- build (defaultOptions tmp) {optProfile = Prod}
      map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0205"]
      t <- BS.readFile (tmp </> "build/text/horizontal/chapters/01.txt")
      assertBool "no proof comment" (not (BS.isInfixOf "校正" t)),
    testCase "check does not write output" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
      copyTree fixture tmp
      _ <- build (defaultOptions tmp) {optCheckOnly = True}
      exists <- doesDirectoryExist (tmp </> "build")
      exists @?= False,
    testCase "errors stop the pipeline and are sorted" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
      copyTree fixture tmp
      BS.writeFile (tmp </> "chapters/02.gm") "[nope: x] [strong: y\n"
      r <- build (defaultOptions tmp)
      map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0117"]
      exists <- doesDirectoryExist (tmp </> "build")
      exists @?= False
      T.length (T.pack "") @?= 0
  ]

allTargetsTests :: TestTree
allTargetsTests =
  testGroup
    "all targets when none is given (golem-cli ADR 0002)"
    [ testCase "all targets are HTML, EPUB, plain text and PDF, in that order" $
        allTargets @?= [TargetHtml, TargetEpub, TargetText, TargetPdf],
      testCase "all targets are built whatever the manifest declares" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        copyTree fixture tmp
        setTargets tmp "[targets.html]\n"
        r <- build (defaultOptions tmp) {optTargets = Just allTargets}
        -- the fixture has no [page] or fonts, so the PDF fails
        assertBool "PDF error" (any isError (brDiagnostics r))
        doesDirectoryExist (tmp </> "build/pdf") >>= assertBool "no PDF" . not
        mapM_
          (\d -> doesDirectoryExist (tmp </> d) >>= assertBool d)
          ["build/html", "build/epub", "build/text/vertical", "build/text/horizontal"],
      testCase "plain text without [targets.text] makes both variants" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        copyTree fixture tmp
        setTargets tmp "[targets.html]\n"
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        listDirectory (tmp </> "build/text") >>= (@?= ["horizontal", "vertical"]) . sort,
      testCase "declared variants are kept" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        copyTree fixture tmp
        setTargets tmp "[targets.text]\nvariants = [\"vertical\"]\n"
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        listDirectory (tmp </> "build/text") >>= (@?= ["vertical"])
    ]

publicDomainTests :: TestTree
publicDomainTests =
  testGroup
    "public-domain books"
    [ testCase "The Tempest builds horizontally to every target" $ do
        (written, pdf, texts) <- buildBook "tempest"
        assertBool (show written) (all (\ext -> any (ext `isSuffixOf`) written) [".pdf", ".epub", ".xhtml", ".txt"])
        let horizontal = [t | (p, t) <- texts, "horizontal/tempest.txt" `isSuffixOf` p]
        assertBool "verse lines" (any ("Full fathom five thy father lies;\nOf his bones are coral made;" `T.isInfixOf`) horizontal)
        assertBool "horizontal" (not ("/Identity-V" `BS.isInfixOf` pdf))
        qpdfCheck pdf,
      testCase "蟹工船 builds vertically to every target" $ do
        (written, pdf, _) <- buildBook "kanikosen"
        assertBool (show written) (all (\ext -> any (ext `isSuffixOf`) written) [".pdf", ".epub", ".xhtml", ".txt"])
        assertBool "vertical" ("/Identity-V" `BS.isInfixOf` pdf)
        -- 「——漁夫は」: the dashes (CID 722) turned (golem-driver ADR 0015)
        content <- BS.concat <$> inflateAll pdf
        assertBool "turned dashes" (any (\d -> dGlyph d == 722 && dMatrix d == ["0", "-1", "1", "0"]) (drawnGlyphs content))
        qpdfCheck pdf,
      testGroup "ten public-domain books (docs/adr/0026)" (map pdBookTest pdBooks)
    ]

-- | The books of test/fixtures/pd (docs/adr/0026) and whether each is set vertically.
pdBooks :: [(FilePath, Bool)]
pdBooks =
  [ ("merry-wives", False),
    ("frogs", False),
    ("snark", False),
    ("elements-of-style", False),
    ("nightmare-abbey", False),
    ("koya-hijiri", True),
    ("ichiaku-no-suna", True),
    ("haru-to-shura", True),
    ("taira-no-masakado", True),
    ("ushiyama-hotel", True)
  ]

{- | A book of test/fixtures/pd is checked without errors. With GOLEM_PD_BOOKS
set, it is built to every target too, which takes most of a minute for the
ten (docs/adr/0026). The books do not commit their fonts; the fonts of
蟹工船 and The Tempest are copied in, as scripts/fixtures/copy-fonts.sh does.
-}
pdBookTest :: (FilePath, Bool) -> TestTree
pdBookTest (name, vertical) = testCase name $ withSystemTempDirectory "golem-pd" $ \tmp -> do
  let src = "test/fixtures/pd" </> name
  entries <- listDirectory src
  forM_ entries $ \e -> do
    isDir <- doesDirectoryExist (src </> e)
    unless isDir (copyFile (src </> e) (tmp </> e))
  let (fonts, font) =
        if vertical
          then ("test/fixtures/kanikosen/fonts", "NotoSerifJP-Regular.otf")
          else ("test/fixtures/tempest/fonts", "SourceSerifVariable-Roman.ttf")
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile (fonts </> font) (tmp </> "fonts" </> font)
  full <- isJust <$> lookupEnv "GOLEM_PD_BOOKS"
  r <- build (defaultOptions tmp) {optCheckOnly = not full}
  assertEqual "no errors" [] [(diagCode d, diagMessage d) | d <- brDiagnostics r, isError d]
  when full $ do
    let written = brWritten r
    assertBool (show written) (all (\ext -> any (ext `isSuffixOf`) written) [".pdf", ".epub", ".xhtml", ".txt"])
    pdf <- case filter (".pdf" `isSuffixOf`) written of
      [p] -> BS.readFile p
      other -> assertFailure (show other)
    assertBool "the writing mode" (vertical == ("/Identity-V" `BS.isInfixOf` pdf))
    qpdfCheck pdf

-- | The fixture with style.toml replaced and extra files written (golem-project ADR 0004).
withStyleProject :: BS.ByteString -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withStyleProject style files act = withSystemTempDirectory "golem-files" $ \tmp -> do
  copyTree fixture tmp
  BS.writeFile (tmp </> "style.toml") style
  forM_ files $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  act tmp

-- | The fixture whose body font is missing.
missingStyle :: BS.ByteString
missingStyle = horizontalStyle <> "\n[fonts.body]\nja = \"fonts/missing.otf\"\n"

codeSeverities :: BuildResult -> [(DiagnosticCode, Severity)]
codeSeverities r = [(diagCode d, diagSeverity d) | d <- brDiagnostics r]

styleFileTests :: [TestTree]
styleFileTests =
  [ testCase "a missing font does not stop the evaluation: the book is assembled with no diagnostics" $ withStyleProject missingStyle [] $ \tmp -> do
      e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
      (isJust (evBook e), map diagCode (evDiagnostics e)) @?= (True, []),
    testCase "HTML, EPUB and plain text are written without the missing font, with one G0310 warning" $ withStyleProject missingStyle [] $ \tmp -> do
      r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub, TargetText]}
      codeSeverities r @?= [(DiagnosticCode "G0310", Warning)]
      assertBool "message" (any (T.isInfixOf "fonts/missing.otf" . diagMessage) (brDiagnostics r))
      mapM_ (\d -> doesDirectoryExist (tmp </> d) >>= assertBool d) ["build/html", "build/text/horizontal"]
      css <- TIO.readFile (tmp </> "build/html/style.css")
      assertBool "no @font-face" (not ("@font-face" `T.isInfixOf` css))
      doesDirectoryExist (tmp </> "build/html/fonts") >>= assertBool "no fonts directory" . not
      epub <- BS.readFile (tmp </> "build/epub/book.epub")
      assertBool "no fonts in the EPUB" (not ("OEBPS/fonts/" `BS.isInfixOf` epub)),
    testCase "the PDF stops with G0802 on style.toml before the fonts are loaded" $ withStyleProject missingStyle [] $ \tmp -> do
      calls <- newIORef (0 :: Int)
      r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = countingFonts calls}
      codeSeverities r @?= [(DiagnosticCode "G0802", Error)]
      e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
      map (spanFile . diagSpan) (brDiagnostics r) @?= [evStyleFile e]
      doesDirectoryExist (tmp </> "build/pdf") >>= assertBool "no PDF" . not
      readIORef calls >>= (@?= 0),
    testCase "plain text does not look at the files" $ withStyleProject missingStyle [] $ \tmp -> do
      r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
      codeSeverities r @?= [],
    testCase "prod makes G0310 an error and writes no HTML" $ withStyleProject missingStyle [] $ \tmp -> do
      r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optProfile = Prod}
      [s | (DiagnosticCode "G0310", s) <- codeSeverities r] @?= [Error]
      doesDirectoryExist (tmp </> "build/html") >>= assertBool "no HTML" . not,
    testCase "the PDF does not report roles it does not use; HTML leaves only the missing face out" $ do
      let style = horizontalStyle <> fakeBody <> "\n[fonts.mono]\nlatin = \"fonts/missing.otf\"\n"
      withStyleProject style fakeFontFiles $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
        -- the fixture has code and no [fonts.code]: G0808 (golem-driver ADR 0017)
        filter ((/= DiagnosticCode "G0808") . fst) (codeSeverities r) @?= []
        h <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        codeSeverities h @?= [(DiagnosticCode "G0310", Warning)]
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "body face" ("font-family: \"golem-body-ja\"; src" `T.isInfixOf` css)
        assertBool "no mono face" (not ("font-family: \"golem-mono-latin\"; src" `T.isInfixOf` css)),
    testCase "a missing ICC profile is G0806 for the PDF and nothing for HTML" $ do
      let style = horizontalStyle <> fakeBody <> "\n[color]\nintent = \"icc/none.icc\"\n"
      withStyleProject style fakeFontFiles $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
        codeSeverities r @?= [(DiagnosticCode "G0806", Error)]
        doesDirectoryExist (tmp </> "build/pdf") >>= assertBool "no PDF" . not
        h <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        codeSeverities h @?= [],
    testCase "check reports the files of every target and writes nothing" $ withStyleProject missingStyle [] $ \tmp -> do
      r <- build (defaultOptions tmp) {optTargets = Just allTargets, optCheckOnly = True}
      sort (map diagCode (brDiagnostics r)) @?= [DiagnosticCode "G0310", DiagnosticCode "G0802"]
      doesDirectoryExist (tmp </> "build") >>= assertBool "no build" . not,
    testCase "one path named by two roles is reported once for HTML and EPUB" $ do
      let style = missingStyle <> "\n[fonts.mono]\nlatin = \"fonts/missing.otf\"\n"
      withStyleProject style [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        codeSeverities r @?= [(DiagnosticCode "G0310", Warning)]
  ]
    <> [ testCase ("a project made without fonts builds every target but the PDF (" <> tag <> ")") $ withSystemTempDirectory "golem-new" $ \tmp -> do
           let dir = tmp </> "book"
           createProject dir (templateFiles lang uuid0) Nothing >>= (@?= Right ())
           r <- build (defaultOptions dir) {optTargets = Just allTargets}
           codeSeverities r @?= [(DiagnosticCode "G0310", Warning), (DiagnosticCode "G0802", Error)]
           mapM_ (\d -> doesDirectoryExist (dir </> d) >>= assertBool d) ["build/html", "build/epub", "build/text"]
           doesDirectoryExist (dir </> "build/pdf") >>= assertBool "no PDF" . not
       | (lang, tag) <- [(Japanese, "ja"), (English, "en")]
       ]

-- | The manifest of the one-chapter project in another language.
langManifest :: T.Text -> BS.ByteString
langManifest lang = replaceIn "language = \"ja\"" ("language = \"" <> lang <> "\"") miniManifest

-- | A style with the number format of chapters and of figures.
numberStyle :: T.Text -> BS.ByteString
numberStyle format = horizontalStyle <> TE.encodeUtf8 ("\n[headings.1]\nnumber = \"" <> format <> "\"\n\n[figures]\nnumber = \"図{chapter}-{n}\"\n")

{- | Builds the one-chapter project of the language to HTML; the chapter
page and the table of contents page.
-}
sepHtml :: T.Text -> T.Text -> T.Text -> IO (T.Text, T.Text)
sepHtml lang format source = withSystemTempDirectory "golem-sep" $ \tmp -> do
  img <- tinyImage
  BS.writeFile (tmp </> "manifest.toml") (langManifest lang <> "\n[targets.html]\n")
  BS.writeFile (tmp </> "style.toml") (numberStyle format)
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ img $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  (,) <$> TIO.readFile (tmp </> "build/html/a.xhtml") <*> TIO.readFile (tmp </> "build/html/index.xhtml")

-- | The EPUB navigation document of the one-chapter project of the language.
sepNav :: T.Text -> T.Text -> T.Text -> IO T.Text
sepNav lang format source = withSystemTempDirectory "golem-sep" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (langManifest lang <> "\n[targets.epub]\n")
  BS.writeFile (tmp </> "style.toml") (numberStyle format)
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
  book <- maybe (assertFailure "no book") pure (evBook e)
  let md = manifestMetadata (projectManifest (evProject e))
      cfg = EpubConfig (mdId md) (mdTitle md) Nothing (mdLanguage md) (mdDate md) Nothing [] [] False
  pure (navDocument cfg (projectFiles (evProject e)) book)

numberSeparatorTests :: [TestTree]
numberSeparatorTests =
  [ testCase "HTML: an ideographic space after the number of a heading and of a caption in a Japanese book" $ do
      (page, _) <- sepHtml "ja" "第{n:kanji}章" "# 原稿の記法\n\n@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n"
      assertBool (T.unpack page) ("<span class=\"number\">第一章</span>\x3000原稿の記法</h1>" `T.isInfixOf` page)
      assertBool (T.unpack page) ("<figcaption><span class=\"number\">図1-1</span>\x3000キャプション。</figcaption>" `T.isInfixOf` page),
    testCase "HTML: a space in an English book" $ do
      (page, _) <- sepHtml "en" "{n}" "# Introduction\n"
      assertBool (T.unpack page) ("<span class=\"number\">1</span> Introduction</h1>" `T.isInfixOf` page),
    testCase "HTML: @toc and the table of contents page" $ do
      (ja, jaIndex) <- sepHtml "ja" "第{n:kanji}章" "@toc\n\n# 原稿\n"
      assertBool (T.unpack ja) (">第一章\x3000原稿</a>" `T.isInfixOf` ja)
      assertBool (T.unpack jaIndex) (">第一章\x3000原稿</a>" `T.isInfixOf` jaIndex)
      (en, enIndex) <- sepHtml "en" "{n}" "@toc\n\n# Introduction\n"
      assertBool (T.unpack en) (">1 Introduction</a>" `T.isInfixOf` en)
      assertBool (T.unpack enIndex) (">1 Introduction</a>" `T.isInfixOf` enIndex),
    testCase "EPUB: the navigation document" $ do
      ja <- sepNav "ja" "第{n:kanji}章" "# 原稿\n"
      assertBool (T.unpack ja) (">第一章\x3000原稿</a>" `T.isInfixOf` ja)
      en <- sepNav "en" "{n}" "# Introduction\n"
      assertBool (T.unpack en) (">1 Introduction</a>" `T.isInfixOf` en),
    testCase "HTML: no separator on @nonumber" $ do
      (page, _) <- sepHtml "ja" "第{n:kanji}章" "@nonumber\n# まえがき\n"
      assertBool (T.unpack page) ("\">まえがき</h1>" `T.isInfixOf` page),
    testCase "HTML and PDF: nothing more after a number format that ends with a space" $ do
      (page, _) <- sepHtml "en" "Chapter {n}: " "# Introduction\n"
      assertBool (T.unpack page) ("<span class=\"number\">Chapter 1: </span>Introduction</h1>" `T.isInfixOf` page)
      rendered (numberedTitle "en" sp0 (Just "Chapter 1: ") [Text sp0 "Introduction"]) @?= "Chapter 1: Introduction",
    testCase "PDF: the title of a heading unit" $ do
      rendered (numberedTitle "en" sp0 (Just "1") [Text sp0 "Introduction"]) @?= "1 Introduction"
      rendered (numberedTitle "ja" sp0 (Just "第一章") [Text sp0 "海"]) @?= "第一章\x3000海"
      rendered (numberedTitle "en" sp0 Nothing [Text sp0 "Preface"]) @?= "Preface",
    testCase "PDF: the running head heading.1.numbered" $ do
      listToMaybe (runningHeadLines (Map.fromList [("title", "T"), ("language", "en")]) Map.empty (RunningLines ([PartRef (RefHeading 1 HeadNumbered PickFirst) False] :| [])) Map.empty [HeadingInfo 1 (Just [1]) (Just "1") [Text sp0 "Introduction"] "Introduction" (FileId 0)]) @?= Just "1 Introduction"
      listToMaybe (runningHeadLines (Map.fromList [("title", "T"), ("language", "en")]) Map.empty (RunningLines ([PartRef (RefHeading 1 HeadNumbered PickFirst) False] :| [])) Map.empty [HeadingInfo 1 (Just [1]) (Just "Chapter 1: ") [Text sp0 "Introduction"] "Introduction" (FileId 0)]) @?= Just "Chapter 1: Introduction",
    testCase "PDF: an English book has no ideographic space after the number" $ do
      let style =
            BS.concat
              [ replaceIn "lines = 30\n" "lines = 6\n" horizontalStyle,
                "\n[headings.1]\nnumber = \"{n}\"\n\n",
                "[masters.body]\nrunning-head = { position = \"top-outside\", content = \"heading.1.numbered\" }\n"
              ]
      (heads, pl) <- layoutHeads (langManifest "en") style [("a.gm", "# Introduction\n\n" <> T.replicate (12 * 11) "あ" <> "\n")]
      Map.lookup 2 heads @?= Just ["1 Introduction"]
      assertBool (show (lineTexts pl)) (not (any (T.isInfixOf "\x3000") (lineTexts pl)))
  ]
  where
    sp0 = mkSpan (FileId 0) 0 0
