module Main (main) where

import Codec.Compression.Zlib qualified as Z
import Control.Exception (SomeException, evaluate, try)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (isSuffixOf, nub, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (IndexGroup (..), inlineText)
import Golem.Doc.IR (Inline, InlineF (..))
import Golem.Driver
import Golem.Driver.New
import Golem.Driver.Pdf (PdfInput (..), PdfLayout (..), PlacedFigure (..), PlacedSidenote (..), SetLine (..), bibliographyLines, figureRect, flowLines, indexLines, instanceIdInputs, layoutPages, layoutPdf)
import Golem.Driver.Version (golemVersion)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.Layout.Paginate (Flow (..), PageOut (..), Slotted (..), markPages)
import Golem.Layout.Wrap (Exclusion (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..), pageGeometry, sidenoteAreaFor, typeAreaFor)
import Golem.Pdf (Font (..), FontProgram (..), spToPt)
import Golem.Plugin (watToWasm)
import Golem.Plugin.Lock (defaultCacheDir, hashHex, lockPlugins, renderLock)
import Golem.Project.Style (dimToSp, parseDim, parseStyle)
import Golem.Syntax
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, findExecutable, listDirectory)
import System.Environment (setEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

fixture :: FilePath
fixture = "test/fixtures/sample"

copyTree :: FilePath -> FilePath -> IO ()
copyTree from to = do
  createDirectoryIfMissing True to
  entries <- listDirectory from
  mapM_
    ( \e -> do
        isDir <- doesDirectoryExist (from </> e)
        if isDir then copyTree (from </> e) (to </> e) else copyFile (from </> e) (to </> e)
    )
    entries

-- | Builds a copy of the fixture and returns the bytes of one output file.
buildAndRead :: Profile -> FilePath -> IO BL.ByteString
buildAndRead profile out = withSystemTempDirectory "golem-driver" $ \tmp -> do
  copyTree fixture tmp
  r <- build (defaultOptions tmp) {optProfile = profile}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  BL.fromStrict <$> BS.readFile (tmp </> out)

-- | Replaces the [targets.*] tables of the copied fixture's manifest.
setTargets :: FilePath -> T.Text -> IO ()
setTargets root targets = do
  m <- TIO.readFile (root </> "manifest.toml")
  TIO.writeFile (root </> "manifest.toml") (fst (T.breakOn "[targets." m) <> targets)

uuid0 :: T.Text
uuid0 = "00000000-0000-4000-8000-000000000000"

templateText :: Language -> FilePath -> T.Text
templateText lang file = fromMaybe "" (lookup file (templateFiles lang uuid0))

templateFile :: Language -> FilePath -> IO BL.ByteString
templateFile lang file = pure (BL.fromStrict (TE.encodeUtf8 (templateText lang file)))

fakeFont :: BS.ByteString -> FontSource
fakeFont bytes = FontSource "fonts/a.otf" "https://example.com/a.otf" (hashHex bytes)

fakeFetch :: Either T.Text BS.ByteString -> T.Text -> IO (Either T.Text BS.ByteString)
fakeFetch r _ = pure r

golden :: String -> FilePath -> TestTree
golden name out = goldenVsString name ("test/golden/" <> name) (buildAndRead Dev out)

tests :: TestTree
tests =
  testGroup
    "golem-driver (ADR 0001)"
    [ testGroup
        "version (docs/adr/0004)"
        [ testCase "golemVersion is the content of VERSION" $ do
            v <- T.strip <$> TIO.readFile "../../VERSION"
            golemVersion @?= v,
          testCase "the PDF instance ID is computed from golem- and the version, last" $ do
            let inputs = instanceIdInputs ["input"] ["font program"]
            inputs @?= ["input", "font program", TE.encodeUtf8 ("golem-" <> golemVersion)]
            last inputs @?= TE.encodeUtf8 ("golem-" <> golemVersion)
        ],
      golden "text-horizontal-01.txt" "build/text/horizontal/chapters/01.txt",
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
        T.length (T.pack "") @?= 0,
      testGroup
        "golem new (golem-cli ADR 0003)"
        ( [ goldenVsString ("new-" <> tag <> "-" <> name) ("test/golden/new-" <> tag <> "-" <> name) (templateFile lang file)
          | (lang, tag) <- [(Japanese, "ja"), (English, "en")],
            (name, file) <- [("manifest.toml", "manifest.toml"), ("style.toml", "style.toml"), ("01.gm", "chapters/01.gm")]
          ]
            <> [ testCase "the template lays out a page" $
                   mapM_
                     (\lang -> either (assertFailure . show) (const (pure ())) (parseStyle (FileId 0) (templateText lang "style.toml") >>= pageGeometry))
                     [Japanese, English],
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
        ),
      testGroup
        "all targets when none is given (golem-cli ADR 0002)"
        [ testCase "allTargets lists the four targets in order" $
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
        ],
      testGroup
        "PDF pipeline (ADR 0002)"
        [ testCase "a missing body font is reported" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
            copyTree fixture tmp
            BS.writeFile (tmp </> "style.toml") pdfStyle
            r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf]}
            map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0802"]
            r' <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = noFontProvider}
            map diagCode (brDiagnostics r') @?= [DiagnosticCode "G0801"],
          testCase "with real fonts: subset OpenType fonts, ToUnicode, deterministic and parallel-safe" $ do
            a <- buildRealPdf True
            b <- buildRealPdf False
            a @?= b
            assertBool "OpenType program" ("/Subtype /OpenType" `BS.isInfixOf` a)
            assertBool "vertical font" ("/Identity-V" `BS.isInfixOf` a)
            streams <- inflateAll a
            -- 「は」(U+306F) and 「じ」(U+3058) of 「はじめに」 are mapped back to text
            assertBool "ToUnicode" (any (\st -> "<306f>" `BS.isInfixOf` st && "beginbfchar" `BS.isInfixOf` st) streams)
            qpdfCheck a,
          testCase "ruby readings, emphasis dots and line-end hyphens are drawn" $ do
            pdf <- withSystemTempDirectory "golem-driver" $ \tmp -> do
              copyTree fixture tmp
              BS.writeFile (tmp </> "style.toml") horizontalStyle
              BS.appendFile (tmp </> "chapters/02.gm") $ TE.encodeUtf8 "\n[kenten: 強調]する。\n\nThe typesetting of hyphenation demonstrates the extraordinary flexibility of characteristically unbreakable paragraphs.\n"
              r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = FontProvider (\_ _ -> pure (Right fakeFonts))}
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
            let occurrences c = case BS.breakSubstring "<002D>" c of
                  (_, rest) | BS.null rest -> 0 :: Int
                  (_, rest) -> 1 + occurrences (BS.drop 6 rest)
            sum (map occurrences contents) @?= T.count "-" source,
          testCase "fonts and layout are not touched unless PDF is a target" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
            copyTree fixture tmp
            BS.writeFile (tmp </> "style.toml") pdfStyle
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
        ],
      testGroup "verse (docs/adr ADR 0003)" verseTests,
      testGroup "PDF headings (ADR 0003)" headingTests,
      testGroup "PDF emphasis, character styles and colour (ADR 0004)" emphasisTests,
      testGroup "PDF wrapped figures (ADR 0005)" wrapTests,
      testGroup "PDF sidenotes (ADR 0006)" sidenoteTests,
      testGroup "PDF index and bibliography (ADR 0007)" indexTests,
      testGroup "PDF tables (ADR 0008)" tableTests,
      testGroup "plugins (golem-plugin ADR 0001, 0002)" pluginTests,
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
            qpdfCheck pdf
        ]
    ]

-- | Builds a copy of a book fixture (fonts included); no errors allowed.
buildBook :: FilePath -> IO ([FilePath], BS.ByteString, [(FilePath, T.Text)])
buildBook name = withSystemTempDirectory "golem-book" $ \tmp -> do
  copyTree ("test/fixtures" </> name) tmp
  r <- build (defaultOptions tmp)
  assertEqual "no errors" [] [(diagCode d, diagMessage d) | d <- brDiagnostics r, isError d]
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> BS.readFile p
    other -> assertFailure (show other)
  texts <- mapM (\p -> (p,) <$> TIO.readFile p) (filter (".txt" `isSuffixOf`) (brWritten r))
  pure (brWritten r, pdf, texts)

-- | A project of one file with verse in it.
withVerseProject :: BS.ByteString -> T.Text -> (FilePath -> IO a) -> IO a
withVerseProject style src k = withSystemTempDirectory "golem-verse" $ \tmp -> do
  manifest <- TIO.readFile (fixture </> "manifest.toml")
  TIO.writeFile (tmp </> "manifest.toml") ("chapters = [\"v.gm\"]\n" <> T.dropWhile (/= '\n') manifest)
  BS.writeFile (tmp </> "style.toml") style
  TIO.writeFile (tmp </> "v.gm") src
  k tmp

verseSource :: T.Text
verseSource = "@verse\n  Full fathom five thy father lies;\n  Of his bones are coral made;\n\n  Nothing of him that doth fade,\n"

-- | The PDF flow of a verse project and its lines as (line length, indent).
verseLines :: BS.ByteString -> T.Text -> IO ([Flow], [(Integer, Integer)])
verseLines style src = withVerseProject style src $ \tmp -> do
  ev <- evaluateProject Dev tmp
  case ev of
    Left ds -> assertFailure (show ds)
    Right e -> case evBook e of
      Nothing -> assertFailure (show (map diagCode (evDiagnostics e)))
      Just book -> do
        r <- flowLines (FontProvider (\_ _ -> pure (Right fakeFonts))) (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty)
        either (assertFailure . show) pure r

verseTests :: [TestTree]
verseTests =
  [ testCase "HTML: stanzas are p, lines are span and br; the CSS hangs the lines" $
      withVerseProject "[verse]\nhang = \"3zw\"\n" verseSource $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool
          "verse"
          ( "<div class=\"verse\">\n<p><span>Full fathom five thy father lies;</span><br/>\n<span>Of his bones are coral made;</span></p>\n<p><span>Nothing of him that doth fade,</span></p>\n</div>\n"
              `T.isInfixOf` page
          )
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "span rule" (".verse span { display: block; padding-inline-start: 3em; text-indent: -3em; }" `T.isInfixOf` css)
        assertBool "stanza gap" (".verse p + p { margin-block-start: 1em; }" `T.isInfixOf` css),
    testCase "HTML: no stanza gap rule when stanza-gap is 0" $
      withVerseProject "[verse]\nstanza-gap = 0\nindent = \"10.5pt\"\n" verseSource $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "no stanza gap" (not (".verse p + p" `T.isInfixOf` css))
        assertBool "indent" (".verse { margin-inline-start: 10.5pt; }" `T.isInfixOf` css),
    testCase "plain text: lines on lines, stanzas separated by a blank line" $
      withVerseProject "" verseSource $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        t <- TIO.readFile (tmp </> "build/text/horizontal/v.txt")
        t @?= "Full fathom five thy father lies;\nOf his bones are coral made;\n\nNothing of him that doth fade,\n",
    testCase "PDF: a long line is broken and its continuation hangs" $ do
      let style = "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 30\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n"
          fs = 655360
      (flow, ls) <- verseLines style ("@verse\n  " <> T.replicate 45 "あ" <> "\n\n  い\n")
      ls @?= [(30 * fs, 0), (28 * fs, 2 * fs), (30 * fs, 0)]
      [length bs | FParagraph bs <- flow] @?= [2, 1]
      [n | FSpace n <- flow] @?= [1],
    testCase "PDF: the hang in vertical writing, and the stanza gap from the style" $ do
      let fs = maybe 0 (dimToSp 0) (parseDim "13Q")
      (flow, ls) <- verseLines (pdfStyle <> "\n[verse]\nstanza-gap = 2\n") ("@verse\n  " <> T.replicate 60 "あ" <> "\n\n  い\n")
      map snd ls @?= [0, 2 * fs, 0]
      [n | FSpace n <- flow] @?= [2],
    testCase "PDF: a verse line takes the look of its inline elements" $ do
      (_, layout) <- layoutOk horizontalStyle "@verse\n  前の[bold: 本文]後\n" []
      [bcText c | sl <- Map.elems (plLines layout), Box _ c <- lineItems (slLine sl), lkEmbolden (bcLook c)] @?= ["本", "文"]
  ]

-- | A project with the identity plugin locked and cached.
withPluginProject :: BS.ByteString -> (FilePath -> IO a) -> IO a
withPluginProject manifestExtra k = withSystemTempDirectory "golem-driver" $ \tmp -> do
  copyTree fixture tmp
  manifest <- BS.readFile (tmp </> "manifest.toml")
  BS.writeFile (tmp </> "manifest.toml") (manifest <> manifestExtra)
  wat <- TIO.readFile "../golem-plugin/test/plugins/identity.wat"
  wasm <- either (assertFailure . T.unpack) pure (watToWasm wat)
  let url = "https://example.com/identity.wasm"
  setEnv "XDG_CACHE_HOME" (tmp </> "cache")
  cache <- defaultCacheDir
  r <- lockPlugins (\u -> pure (if u == url then Right wasm else Left "404")) cache (Map.fromList [("identity", url)])
  either (assertFailure . show) (TIO.writeFile (tmp </> "plugins.lock") . renderLock) r
  k tmp

pluginTests :: [TestTree]
pluginTests =
  [ testCase "a filter runs over the declared files and keeps the output" $ do
      plain <- buildAndRead Dev "build/text/horizontal/chapters/01.txt"
      filtered <- withPluginProject pluginDecl $ \tmp -> do
        r <- build (defaultOptions tmp)
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        BL.fromStrict <$> BS.readFile (tmp </> "build/text/horizontal/chapters/01.txt")
      filtered @?= plain,
    testCase "a command whose answer is invalid is a compile error" $
      withPluginProject pluginDecl $ \tmp -> do
        BS.appendFile (tmp </> "chapters/02.gm") "\n[broken: x]\n"
        r <- build (defaultOptions tmp)
        assertBool (show (brDiagnostics r)) (DiagnosticCode "G0609" `elem` map diagCode (brDiagnostics r)),
    testCase "a plugin missing from the lock or the cache is reported" $
      withPluginProject pluginDecl $ \tmp -> do
        BS.writeFile (tmp </> "plugins.lock") ""
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0602"]
        setEnv "XDG_CACHE_HOME" (tmp </> "empty-cache")
        r' <- build (defaultOptions tmp) {optCheckOnly = True}
        map diagCode (brDiagnostics r') @?= [DiagnosticCode "G0602"],
    testCase "an uncached plugin asks for golem plugin fetch" $
      withPluginProject pluginDecl $ \tmp -> do
        setEnv "XDG_CACHE_HOME" (tmp </> "empty-cache")
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0603"],
    testCase "overriding a command the plugin does not provide is an error" $
      withPluginProject (pluginDeclWith "overrides = [\"ruby\"]\n") $ \tmp -> do
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0608"]
  ]
  where
    pluginDecl = pluginDeclWith ""
    pluginDeclWith extra =
      "\n[plugins.identity]\nurl = \"https://example.com/identity.wasm\"\n"
        <> extra
        <> "\n[[filters]]\nplugin = \"identity\"\nfilter = \"same\"\nfiles = [\"chapters/01.gm\"]\n"

-- | B6, vertical, right binding, as in specifications.md.
pdfStyle :: BS.ByteString
pdfStyle =
  BS.concat
    [ "[page]\nsize = \"B6\"\nbinding = \"right\"\nwriting-mode = \"vertical\"\n\n",
      "[page.grid]\nfont-size = \"13Q\"\ncharacters = 42\nlines = 16\nline-pitch = \"22H\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n",
      "[headings.1]\nnumber = \"第{n:kanji}章\"\n\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
    ]

-- | A4, horizontal, narrow lines: words must be hyphenated.
horizontalStyle :: BS.ByteString
horizontalStyle =
  "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 12\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n"

-- | A one-chapter project for PDF tests.
miniManifest :: BS.ByteString
miniManifest = "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.pdf]\n"

{- | Builds a one-chapter project (style, source, extra files) to PDF and
returns the errors and the PDF, if one was written.
-}
buildMini :: FontProvider -> Bool -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO ([DiagnosticCode], Maybe BS.ByteString)
buildMini fonts parallel style source files = withSystemTempDirectory "golem-mini" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ files $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fonts, optParallel = parallel}
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  pure (map diagCode (filter isError (brDiagnostics r)), pdf)

-- | The golem-font provider that builds use by default.
realProvider :: FontProvider
realProvider = optFonts (defaultOptions "")

fakeProvider :: FontProvider
fakeProvider = FontProvider (\_ _ -> pure (Right fakeFonts))

-- | Builds with no errors allowed and returns the PDF.
miniPdf :: FontProvider -> Bool -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO BS.ByteString
miniPdf fonts parallel style source files = do
  (errs, pdf) <- buildMini fonts parallel style source files
  assertEqual "no errors" [] errs
  maybe (assertFailure "no PDF") pure pdf

-- | Glyph runs of a content stream: the Tf size and each glyph id with its origin.
glyphRuns :: BS.ByteString -> [(BS.ByteString, [(Int, BS.ByteString, BS.ByteString)])]
glyphRuns content = go (BC.lines content)
  where
    go [] = []
    go (l : rest)
      | (_ : _ : size : "Tf" : _) <- BC.words l =
          let (body, rest') = break ((== "ET") . BC.strip) rest
           in (size, [g | b <- body, Just g <- [glyph b]]) : go rest'
      | otherwise = go rest
    glyph l = case reverse (BC.words l) of
      ("Tj" : hexg : "Tm" : y : x : _) -> Just (read ("0x" <> BC.unpack (BC.filter (`notElem` ("<>" :: String)) hexg)), x, y)
      _ -> Nothing

headingTests :: [TestTree]
headingTests =
  [ testCase "a 20pt heading wraps in the measure and is drawn at 20pt" $ do
      let source = "# あいうえおかきく\n\n本文。\n"
          kana = [0x3042, 0x3044, 0x3046, 0x3048, 0x304A, 0x304B, 0x304D, 0x304F]
          headingYs pdf = do
            content <- BS.concat <$> inflateAll pdf
            pure (nub [y | (_, gs) <- glyphRuns content, (g, _, y) <- gs, g `elem` kana], tfSizes content)
      (big, sizes) <- miniPdf fakeProvider True (horizontalStyle <> "\n[headings.1]\nsize = \"20pt\"\n") source [] >>= headingYs
      length big @?= 2
      assertBool (show sizes) ("20" `elem` sizes)
      (plain, _) <- miniPdf fakeProvider True horizontalStyle source [] >>= headingYs
      length plain @?= 1,
    testCase "a heading role with its own font embeds both fonts, each with its own glyphs" $ do
      (sans, serif) <- realLatinFonts
      pdf <- miniPdf realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.heading]\nlatin = \"fonts/serif.ttf\"\n\n[headings.1]\nfont = \"heading\"\n") "# Zebra\n\nquick\n" [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
      streams <- inflateAll pdf
      let cmaps = filter ("beginbfchar" `BS.isInfixOf`) streams
      length cmaps @?= 2
      assertBool "heading glyphs only in one font" (any (\c -> "<005a>" `BS.isInfixOf` c && not ("<0071>" `BS.isInfixOf` c)) cmaps)
      assertBool "body glyphs only in the other" (any (\c -> "<0071>" `BS.isInfixOf` c && not ("<005a>" `BS.isInfixOf` c)) cmaps)
      qpdfCheck pdf,
    testCase "two roles on the same file embed one font program" $ do
      (sans, _) <- realLatinFonts
      pdf <- miniPdf realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.heading]\nlatin = \"fonts/sans.otf\"\n\n[headings.1]\nfont = \"heading\"\nsize = \"20pt\"\n") "# Zebra\n\nquick\n" [("fonts/sans.otf", sans)]
      length (occurrences "/FontFile" pdf) @?= 1,
    testCase "naming the body role and the body size changes nothing" $ do
      (sans, _) <- realLatinFonts
      let base = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n"
          files = [("fonts/sans.otf", sans)]
      a <- miniPdf realProvider True base "# Zebra\n\nquick\n" files
      b <- miniPdf realProvider True (base <> "\n[headings.1]\nfont = \"body\"\nsize = \"10pt\"\n") "# Zebra\n\nquick\n" files
      a @?= b,
    testCase "heading roles: parallel and sequential, and two builds, give the same bytes" $ do
      (sans, serif) <- realLatinFonts
      let style = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.heading]\nlatin = \"fonts/serif.ttf\"\n\n[headings.1]\nfont = \"heading\"\nsize = \"20pt\"\n"
          files = [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
          source = "# Zebra crossing\n\nThe quick brown fox jumps over the lazy dog.\n\n# Second\n\nquick\n"
      a <- miniPdf realProvider True style source files
      b <- miniPdf realProvider False style source files
      c <- miniPdf realProvider True style source files
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "different fonts with the same PostScript name are an error" $ do
      (sans, _) <- realLatinFonts
      (errs, pdf) <- buildMini realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.heading]\nlatin = \"fonts/sans2.otf\"\n\n[headings.1]\nfont = \"heading\"\n") "# Zebra\n\nquick\n" [("fonts/sans.otf", sans), ("fonts/sans2.otf", sans <> BS.replicate 4 0)]
      errs @?= [DiagnosticCode "G0805"]
      pdf @?= Nothing,
    testCase "a heading taller than the page is an error" $ do
      let style = BC.pack (T.unpack (T.replace "lines = 30" "lines = 3" (T.pack (BC.unpack horizontalStyle)))) <> "\n[headings.1]\nsize = \"60pt\"\n"
      (errs, pdf) <- buildMini fakeProvider True style "# A\n\nx\n" []
      errs @?= [DiagnosticCode "G0724"]
      pdf @?= Nothing
  ]

-- | Every glyph drawn: the font resource, the size, the glyph, the text matrix and the origin.
data Drawn = Drawn {dFont :: BS.ByteString, dSize :: BS.ByteString, dGlyph :: Int, dMatrix :: [BS.ByteString], dX :: BS.ByteString, dY :: BS.ByteString}
  deriving stock (Eq, Ord, Show)

drawnGlyphs :: BS.ByteString -> [Drawn]
drawnGlyphs content = go ("", "") (BC.lines content)
  where
    go _ [] = []
    go cur (l : rest) = case BC.words l of
      ws
        | Just (f, size) <- tf ws -> go (f, size) rest
        | (hexg : "Tm" : y : x : m) <- drop 1 (reverse ws),
          "Tj" `elem` take 1 (reverse ws),
          length m >= 4 ->
            uncurry Drawn cur (read ("0x" <> BC.unpack (BC.filter (`notElem` ("<>" :: String)) hexg))) (reverse (take 4 m)) x y : go cur rest
        | otherwise -> go cur rest
    tf ws = case dropWhile (\w -> not ("/F" `BS.isPrefixOf` w)) ws of
      (f : size : "Tf" : _) -> Just (f, size)
      _ -> Nothing

-- | A body role for styles that name other roles, so that the body stays the body.
fakeBody :: BS.ByteString
fakeBody = "\n[fonts.body]\nja = \"fonts/b.otf\"\n"

-- | The style of the PDF tests with fonts that the fake provider ignores but style.toml must find.
fakeFontFiles :: [(FilePath, BS.ByteString)]
fakeFontFiles = [("fonts/" <> f, "fake") | f <- ["b.otf", "w.otf", "h.otf"]]

emphasisTests :: [TestTree]
emphasisTests =
  [ testCase "synthetic bold strokes the outline and keeps every glyph where it was" $ do
      a <- miniPdf fakeProvider True horizontalStyle "前の[bold: 本文]後\n" [] >>= fmap BS.concat . inflateAll
      b <- miniPdf fakeProvider True horizontalStyle "前の本文後\n" [] >>= fmap BS.concat . inflateAll
      assertBool "2 Tr" ("2 Tr" `BS.isInfixOf` a)
      sort [(dGlyph d, dX d, dY d) | d <- drawnGlyphs a] @?= sort [(dGlyph d, dX d, dY d) | d <- drawnGlyphs b],
    testCase "strong as italic slants Latin and Japanese alike, upright vertical glyphs too" $ do
      let slanted content = [(dGlyph d, dMatrix d) | d <- drawnGlyphs content, dGlyph d `elem` map fromEnum ("Gと組版" :: String)]
      h <- miniPdf fakeProvider True (horizontalStyle <> "\n[emphasis]\nstrong = \"italic\"\n") "[strong: Golem と組版]\n" [] >>= fmap BS.concat . inflateAll
      assertBool (show (slanted h)) (length (slanted h) == 4 && all ((== ["1", "0", "0.2", "1"]) . snd) (slanted h))
      v <- miniPdf fakeProvider True (pdfStyle <> "\n[emphasis]\nstrong = \"italic\"\n") "[strong: Golem と組版]\n" [] >>= fmap BS.concat . inflateAll
      let upright = [m | (g, m) <- slanted v, g /= fromEnum 'G']
      assertBool (show (slanted v)) (length upright == 3 && all (== ["1", "0", "0.2", "1"]) upright)
      assertBool "turned Latin" (any ((== ["0", "-1", "1", "-0.2"]) . snd) (slanted v)),
    testCase "an italic role with only Latin sets Latin upright in it and slants the Japanese" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[emphasis]\nitalic-font = \"wide\"\n") "本[italic: Golem と組版]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          latin = [d | d <- ds, dGlyph d == fromEnum 'G']
          ja = [d | d <- ds, dGlyph d == fromEnum '組']
          body = [d | d <- ds, dGlyph d == fromEnum '本']
      map dMatrix latin @?= [["1", "0", "0", "1"]]
      map dMatrix ja @?= [["1", "0", "0.2", "1"]]
      assertBool "the Latin role's font" (map dFont latin /= map dFont body)
      map dFont ja @?= map dFont body,
    testCase "a bold role with wider metrics breaks into more lines" $ do
      let source = "[bold: ab cd ef gh ij kl mn op]\n"
          rows pdf = do
            content <- BS.concat <$> inflateAll pdf
            pure (length (nub [dY d | d <- drawnGlyphs content, dGlyph d `elem` map fromEnum ['a' .. 'p']]))
      plain <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n") source fakeFontFiles >>= rows
      wide <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[emphasis]\nbold-font = \"wide\"\n") source fakeFontFiles >>= rows
      assertBool (show (plain, wide)) (wide > plain),
    testCase "a bold role with its own font embeds it with the bold glyphs only" $ do
      (sans, serif) <- realLatinFonts
      pdf <- miniPdf realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.bold]\nlatin = \"fonts/serif.ttf\"\n\n[emphasis]\nbold-font = \"bold\"\n") "[bold: Zebra] quick\n" [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
      cmaps <- filter ("beginbfchar" `BS.isInfixOf`) <$> inflateAll pdf
      length cmaps @?= 2
      assertBool "bold glyphs only in one font" (any (\c -> "<005a>" `BS.isInfixOf` c && not ("<0071>" `BS.isInfixOf` c)) cmaps)
      qpdfCheck pdf,
    testCase "colour is process CMYK, saved and restored, once per run of a swatch" $ do
      pdf <- miniPdf fakeProvider True (horizontalStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n") "前[color accent: 赤い語]後\n" []
      content <- BS.concat <$> inflateAll pdf
      assertBool "fill" ("q\n0 0.8 1 0 k 0 0.8 1 0 K\n" `BS.isInfixOf` content)
      length (occurrences "0 0.8 1 0 k" content) @?= 1
      let (_, afterColour) = BS.breakSubstring "0 0.8 1 0 k" content
      assertBool "restored" ("Q\n" `BS.isInfixOf` afterColour)
      assertBool "process colour only" (not (any (`BS.isInfixOf` pdf) ["/DeviceRGB", "/Separation", "/DeviceN"])),
    testCase "a character style sets its role and size" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n\n[character-styles.term]\nfont = \"heading\"\nsize = \"2zw\"\n") "本[style term: 語]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
      assertBool "the heading role's font" ([dFont d | d <- ds, dGlyph d == fromEnum '語'] /= [dFont d | d <- ds, dGlyph d == fromEnum '本'])
      [dSize d | d <- ds, dGlyph d == fromEnum '語'] @?= ["20"],
    testCase "emphasis, styles and colour: parallel and sequential, and two builds, give the same bytes" $ do
      let style = horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[emphasis]\nitalic-font = \"wide\"\n\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
          source = "[strong: 強い] [bold: Bold] [italic: Golem と組版] [color accent: 赤 [bold: 太い]]。\n"
      a <- miniPdf fakeProvider True style source fakeFontFiles
      b <- miniPdf fakeProvider False style source fakeFontFiles
      c <- miniPdf fakeProvider True style source fakeFontFiles
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "HTML: a bold role gives b its font and no synthetic weight" $ withSystemTempDirectory "golem-mini" $ \tmp -> do
      BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n")
      BS.writeFile (tmp </> "style.toml") "[fonts.body]\nja = \"fonts/b.otf\"\n\n[fonts.gothic]\nja = \"fonts/h.otf\"\n\n[emphasis]\nbold-font = \"gothic\"\n"
      BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 "[bold: 太い]\n")
      forM_ fakeFontFiles $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
      r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
      assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
      cssText <- TIO.readFile (tmp </> "build/html/style.css")
      assertBool (T.unpack cssText) ("b { font-family: \"golem-gothic-ja\", serif; font-weight: normal; }" `T.isInfixOf` cssText)
      assertBool "strong too" ("strong { font-family: \"golem-gothic-ja\", serif; font-weight: normal; }" `T.isInfixOf` cssText)
  ]

{- | Lays out a one-chapter project with the fake fonts, as far as the
pages; the geometry comes with it.
-}
layoutMini :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO (Either [Diagnostic] (PageGeometry, PdfLayout))
layoutMini style source files = withSystemTempDirectory "golem-layout" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ files $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  ev <- evaluateProject Dev tmp
  case ev of
    Left ds -> pure (Left ds)
    Right e -> case (evBook e, pageGeometry (evStyle e)) of
      _ | errs@(_ : _) <- filter isError (evDiagnostics e) -> pure (Left errs)
      (Just book, Right geom) -> fmap (geom,) <$> layoutPdf (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty) geom fakeFonts
      (_, Left ds) -> pure (Left ds)
      (Nothing, _) -> pure (Left (filter isError (evDiagnostics e)))

-- | Lays out with no errors allowed.
layoutOk :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO (PageGeometry, PdfLayout)
layoutOk style source files = layoutMini style source files >>= either (assertFailure . show) pure

pt :: Integer
pt = 65536

-- | horizontalStyle with 24 characters a line: 10pt, 15pt pitch, 30 lines, 240pt.
horizontal24 :: BS.ByteString
horizontal24 = figStyle (replaceIn "characters = 12" "characters = 24" horizontalStyle)

-- | Replaces ASCII text in a style (the styles of these tests are byte strings, not UTF-8).
replaceIn :: T.Text -> T.Text -> BS.ByteString -> BS.ByteString
replaceIn from to = BC.pack . T.unpack . T.replace from to . T.pack . BC.unpack

-- | Figure numbers without chapter numbers: the test sources have no chapter heading.
figStyle :: BS.ByteString -> BS.ByteString
figStyle st = st <> "\n[figures]\nnumber = \"F{n}\"\n"

tinyImage :: IO [(FilePath, BS.ByteString)]
tinyImage = (\b -> [("images/tiny.jpg", b)]) <$> BS.readFile "../golem-pdf/test/fixtures/tiny.jpg"

wrapped :: T.Text -> T.Text -> T.Text
wrapped side width = "@figure images/tiny.jpg alt=\"t\" wrap=" <> side <> " width=" <> width <> "\n  キャプション。\n\n"

longPara :: Int -> T.Text
longPara n = T.replicate n "あいうえおかきくけこ" <> "\n\n"

-- | The only figure of a layout, the page it is on and its first grid line.
theFigure :: PdfLayout -> IO (Int, PlacedFigure, PageOut, Int)
theFigure pl = case [(fid, pf, p, slot) | (fid, pf) <- Map.toList (plFigures pl), p <- plPages pl, (slot, s) <- poSlots p, s `elem` [SWrapped fid, SFigure fid]] of
  [x] -> pure x
  other -> assertFailure (show [(f, n, sl) | (f, _, PageOut {poNumber = n}, sl) <- other])

-- | The lines of a page from a grid line on, with their slots.
linesFrom :: PdfLayout -> PageOut -> Int -> [(Int, SetLine)]
linesFrom pl p from = [(slot, sl) | (slot, SLine lid) <- poSlots p, slot >= from, Just sl <- [Map.lookup lid (plLines pl)]]

wrapTests :: [TestTree]
wrapTests =
  [ testCase "the exclusion of a wrapped figure covers its image and caption" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> longPara 30) img
      (_, pf, _, _) <- theFigure pl
      let n = toInteger (length (pfCaption pf))
      (pfAlong pf, pfAcross pf, pfImageLines pf) @?= (40 * pt, 60 * pt, 4)
      assertBool "a caption" (n > 0)
      fmap exLines (pfExclusion pf) @?= Just (fromInteger ((((4 + n - 1) * 15 + 10 + 10) + 14) `div` 15)),
    testCase "lines beside the figure are shorter; the rest of the paragraph is full" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> longPara 30) img
      (_, pf, p, slot) <- theFigure pl
      ex <- maybe (assertFailure "no exclusion") pure (pfExclusion pf)
      let beside = [sl | (s, sl) <- linesFrom pl p slot, s < slot + exLines ex]
          rest = [sl | (_, sl) <- linesFrom pl p (slot + exLines ex)]
      length beside @?= exLines ex
      map (lineTarget . slLine) beside @?= replicate (exLines ex) (190 * pt)
      map slIndent beside @?= replicate (exLines ex) 0
      assertBool "continued lines" (not (null rest))
      assertBool "full lines" (all ((== 240 * pt) . lineTarget . slLine) rest),
    testCase "wrap=start indents the lines beside it; the image sits at the line start or end" $ do
      img <- tinyImage
      (geom, pl) <- layoutOk horizontal24 (wrapped "start" "4zw" <> longPara 30) img
      (_, pf, p, slot) <- theFigure pl
      ex <- maybe (assertFailure "no exclusion") pure (pfExclusion pf)
      let ta = typeAreaFor geom (poNumber p)
      map (slIndent . snd) (take (exLines ex) (linesFrom pl p slot)) @?= replicate (exLines ex) (50 * pt)
      rectX (figureRect geom ta slot pf) @?= rectX ta
      (geom', pl') <- layoutOk horizontal24 (wrapped "end" "4zw" <> longPara 30) img
      (_, pf', p', slot') <- theFigure pl'
      let ta' = typeAreaFor geom' (poNumber p')
          r = figureRect geom' ta' slot' pf'
      rectX r + rectW r @?= rectX ta' + rectW ta',
    testCase "a paragraph after a short one beside the figure starts short" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> "短い段落。\n\n" <> longPara 30) img
      (_, _, p, slot) <- theFigure pl
      case linesFrom pl p slot of
        (_ : (_, second) : _) -> lineTarget (slLine second) @?= 190 * pt
        other -> assertFailure (show (length other)),
    testCase "a heading after a wrapped figure starts below the exclusion" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> "# 見出し\n\n本文。\n") img
      (_, pf, p, slot) <- theFigure pl
      ex <- maybe (assertFailure "no exclusion") pure (pfExclusion pf)
      [s | (s, SHeading {}) <- poSlots p] @?= [slot + exLines ex],
    testCase "a wrapped figure that does not fit goes to the next page with its lines" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (longPara 60 <> wrapped "end" "4zw" <> longPara 30) img
      (_, _, p, slot) <- theFigure pl
      (poNumber p, slot) @?= (2, 0)
      case plPages pl of
        (first : _) -> assertBool (show (poSlots first)) (all ((< 26) . fst) (poSlots first))
        [] -> assertFailure "no pages",
    testCase "vertical: the image hangs from the top at its grid line; lines beside it are indented" $ do
      img <- tinyImage
      (geom, pl) <- layoutOk (figStyle pdfStyle) (wrapped "start" "4zw" <> longPara 30) img
      (_, _, p, slot) <- theFigure pl
      (_, pf, _, _) <- theFigure pl
      let ta = typeAreaFor geom (poNumber p)
          r = figureRect geom ta slot pf
          fs = pgFontSize geom
      rectY r + rectH r @?= rectY ta + rectH ta
      rectX r + rectW r @?= rectX ta + rectW ta - toInteger slot * pgLinePitch geom
      ex <- maybe (assertFailure "no exclusion") pure (pfExclusion pf)
      map (slIndent . snd) (take (exLines ex) (linesFrom pl p slot)) @?= replicate (exLines ex) (5 * fs),
    testCase "a width that is not a length, or leaves too short lines, is G0722" $ do
      img <- tinyImage
      a <- layoutMini horizontal24 (wrapped "end" "3em" <> longPara 3) img
      either (map diagCode) (const []) a @?= [DiagnosticCode "G0722"]
      b <- layoutMini horizontal24 (wrapped "end" "22zw" <> longPara 3) img
      either (map diagCode) (const []) b @?= [DiagnosticCode "G0722"],
    testCase "an exclusion longer than the page is G0723 at the figure" $ do
      img <- tinyImage
      let source = "前の段落。\n\n" <> wrapped "end" "10zw" <> longPara 3
      r <- layoutMini (replaceIn "lines = 30" "lines = 10" horizontal24) source img
      case r of
        Left [d] -> do
          diagCode d @?= DiagnosticCode "G0723"
          spanStart (diagSpan d) @?= BS.length (fst (BS.breakSubstring "@figure" (TE.encodeUtf8 source)))
        other -> assertFailure (show (either (map diagCode) (const []) other)),
    testCase "a figure that does not wrap takes its image and caption lines; the caption is drawn" $ do
      img <- tinyImage
      let source = "@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n\n後の段落。\n"
      (_, pl) <- layoutOk horizontal24 source img
      (_, pf, p, slot) <- theFigure pl
      (pfImageLines pf, length (pfCaption pf)) @?= (24, 1)
      [s | (s, SLine _) <- poSlots p, s > slot] @?= [slot + 25]
      content <- miniPdf fakeProvider True horizontal24 source img >>= fmap BS.concat . inflateAll
      assertBool "caption glyphs" (fromEnum 'キ' `elem` map dGlyph (drawnGlyphs content)),
    testCase "vertical: a figure that does not wrap is inside the type area" $ do
      img <- tinyImage
      (geom, pl) <- layoutOk (figStyle (replaceIn "characters = 42" "characters = 20" pdfStyle)) "@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n\n後の段落。\n" img
      (_, pf, p, slot) <- theFigure pl
      let ta = typeAreaFor geom (poNumber p)
          r = figureRect geom ta slot pf
      assertBool (show (r, ta)) (rectX r >= rectX ta && rectX r + rectW r <= rectX ta + rectW ta && rectY r >= rectY ta && rectY r + rectH r <= rectY ta + rectH ta),
    testCase "a page reference beside a wrapped figure converges" $ do
      img <- tinyImage
      (_, pl) <- layoutOk horizontal24 (wrapped "end" "4zw" <> "参照は[ref-page later]ページ。" <> longPara 10 <> longPara 60 <> "@label later\n後の段落。\n") img
      assertBool "pages" (length (plPages pl) >= 2),
    testCase "wrapped figures: parallel and sequential, and two builds, give the same bytes" $ do
      img <- tinyImage
      let source = wrapped "start" "4zw" <> longPara 20 <> wrapped "end" "6zw" <> "短い。\n\n" <> longPara 20
      a <- miniPdf fakeProvider True horizontal24 source img
      b <- miniPdf fakeProvider False horizontal24 source img
      c <- miniPdf fakeProvider True horizontal24 source img
      a @?= b
      a @?= c
      qpdfCheck a
  ]

-- | horizontalStyle with a sidenote column: 6zw wide, 1zw gap, 8pt; the sidenote pitch is 12pt.
sidenoteStyle :: BS.ByteString
sidenoteStyle = horizontalStyle <> "\n[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\nsize = \"8pt\"\n"

-- | Every placed sidenote with its page number.
sidenotesOf :: PdfLayout -> [(Int, PlacedSidenote)]
sidenotesOf pl = [(n, ps) | (n, pss) <- Map.toList (plSidenotes pl), ps <- pss]

-- | The grid line of the line that holds the n-th sidenote marker of a page.
slotOfMarker :: PdfLayout -> Int -> Int -> Maybe Int
slotOfMarker pl page k =
  case [slot | p <- plPages pl, poNumber p == page, (slot, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines pl)], _ <- slSidenotes sl] of
    xs | k < length xs -> Just (xs !! k)
    _ -> Nothing

-- | One-character paragraphs that fill grid lines.
fillers :: Int -> T.Text
fillers n = T.replicate n "あ\n\n"

-- | Byte offsets of a pattern in a source.
offsetsIn :: T.Text -> T.Text -> [Int]
offsetsIn pat src = occurrences (TE.encodeUtf8 pat) (TE.encodeUtf8 src)

twoLineNote :: T.Text
twoLineNote = "[sidenote: あいうえおかきくけ]"

sidenoteTests :: [TestTree]
sidenoteTests =
  [ testCase "a sidenote sits on the page of its marker, level with the marker line" $ do
      (_, pl) <- layoutOk sidenoteStyle (fillers 3 <> "本文[sidenote: 注]。\n") []
      case sidenotesOf pl of
        [(page, ps)] -> do
          page @?= 1
          Just (psTop ps) @?= fmap (\k -> toInteger k * 15 * pt) (slotOfMarker pl 1 0)
        other -> assertFailure (show (length other)),
    testCase "notes on neighbouring lines are pushed down in order, half a pitch apart" $ do
      (_, pl) <- layoutOk sidenoteStyle ("一" <> twoLineNote <> "\n\n二" <> twoLineNote <> "\n") []
      case map snd (sidenotesOf pl) of
        [a, b] -> do
          length (psLines a) @?= 2
          psTop b @?= psTop a + 20 * pt + 15 * pt `div` 2
        other -> assertFailure (show (length other)),
    testCase "notes at the foot of the page pull earlier ones up" $ do
      (_, pl) <- layoutOk sidenoteStyle (fillers 28 <> "一" <> twoLineNote <> "\n\n二" <> twoLineNote <> "\n") []
      case [ps | (1, ps) <- sidenotesOf pl] of
        [a, b] -> do
          psTop b + 20 * pt @?= 445 * pt
          assertBool "pulled up" (psTop a < 28 * 15 * pt)
        other -> assertFailure (show (length other)),
    testCase "sidenotes that do not fit, or one taller than the column, are G0733" $ do
      let crowded = T.concat (replicate 30 ("一[sidenote: " <> T.replicate 3 "あいうえおかき" <> "]\n\n"))
      r <- layoutMini sidenoteStyle crowded []
      case r of
        Left [d] -> do
          diagCode d @?= DiagnosticCode "G0733"
          assertBool "at a sidenote" (spanStart (diagSpan d) `elem` offsetsIn "[sidenote" crowded)
        other -> assertFailure (show (either (map diagCode) (const []) other))
      r' <- layoutMini sidenoteStyle ("一[sidenote: " <> T.replicate 60 "あいうえおかき" <> "]\n") []
      either (map diagCode) (const []) r' @?= [DiagnosticCode "G0733"],
    testCase "the length of a sidenote does not change the pages" $ do
      let source body = fillers 20 <> "本文[sidenote: " <> body <> "]。" <> longPara 20
      (_, a) <- layoutOk sidenoteStyle (source "短い。") []
      (_, b) <- layoutOk sidenoteStyle (source (T.replicate 4 "長い傍注の本文。")) []
      plPages a @?= plPages b,
    testCase "a sidenote follows its line to the next page" $ do
      (_, pl) <- layoutOk sidenoteStyle (fillers 28 <> T.replicate 3 "あいうえおかきくけこさし" <> "あいう[sidenote: 注]え\n") []
      map fst (sidenotesOf pl) @?= [2],
    testCase "markers: a symbol in the text and the note; none leaves no box and no prefix" $ do
      content <- miniPdf fakeProvider True (sidenoteStyle <> "marker = \"symbol\"\n") "本文[sidenote: 注]。\n" [] >>= fmap BS.concat . inflateAll
      length (filter ((== 0x203B) . dGlyph) (drawnGlyphs content)) @?= 2
      (_, none) <- layoutOk (sidenoteStyle <> "marker = \"none\"\n") "本文[sidenote: 注]。\n" []
      (_, plain) <- layoutOk sidenoteStyle "本文。\n" []
      let boxes pl = length [() | sl <- Map.elems (plLines pl), Box {} <- lineItems (slLine sl)]
      boxes none @?= boxes plain
      case map snd (sidenotesOf none) of
        [ps] -> [bcText c | l <- take 1 (psLines ps), Box _ c <- take 1 (lineItems l)] @?= ["注"]
        other -> assertFailure (show (length other)),
    testCase "sidenotes need a horizontal page with a sidenote column, and the text flow" $ do
      a <- layoutMini horizontalStyle "本文[sidenote: 注]。\n" []
      either (map diagCode) (const []) a @?= [DiagnosticCode "G0734"]
      b <- layoutMini pdfStyle "本文[sidenote: 注]。\n" []
      either (map diagCode) (const []) b @?= [DiagnosticCode "G0732"]
      c <- layoutMini sidenoteStyle "本文[note: 注の[sidenote: 傍注]本文]。\n" []
      either (map diagCode) (const []) c @?= [DiagnosticCode "G0735"]
      img <- tinyImage
      d <- layoutMini (figStyle sidenoteStyle) "@figure images/tiny.jpg alt=\"t\"\n  キャプション[sidenote: 傍注]。\n" img
      either (map diagCode) (const []) d @?= [DiagnosticCode "G0735"],
    testCase "sidenote text is drawn in the sidenote column at its size" $ do
      content <- miniPdf fakeProvider True sidenoteStyle "本文[sidenote: 注]。\n" [] >>= fmap BS.concat . inflateAll
      geom <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 sidenoteStyle) >>= pageGeometry)
      area <- maybe (assertFailure "no column") pure (sidenoteAreaFor geom 1)
      let small = [d | d <- drawnGlyphs content, dSize d == "8"]
      assertBool "8pt glyphs" (not (null small))
      assertBool (show (map dX small)) (TE.encodeUtf8 (spToPt (rectX area)) `elem` map dX small),
    testCase "a page reference in a sidenote converges" $ do
      (_, pl) <- layoutOk sidenoteStyle ("本文[sidenote: [ref-page later]ページを参照。]。\n\n" <> longPara 60 <> "@label later\n後。\n") []
      length (sidenotesOf pl) @?= 1,
    testCase "sidenotes: parallel and sequential, and two builds, give the same bytes" $ do
      let source = fillers 5 <> "一" <> twoLineNote <> "\n\n二" <> twoLineNote <> "\n\n" <> longPara 20
      a <- miniPdf fakeProvider True sidenoteStyle source []
      b <- miniPdf fakeProvider False sidenoteStyle source []
      c <- miniPdf fakeProvider True sidenoteStyle source []
      a @?= b
      a @?= c
      qpdfCheck a
  ]

-- | The text of index or bibliography inlines, page numbers as numbers.
rendered :: [Inline] -> T.Text
rendered = T.concat . map (\case Number _ n _ -> T.pack (show n); i -> inlineText i)

-- | The page numbers among inlines.
numbersIn :: [Inline] -> [Integer]
numbersIn is = [n | Number _ n _ <- is]

{- | Lays out a one-chapter project (with extra manifest lines before
[metadata]) and returns the text of the lines of each page.
-}
pagesMini :: T.Text -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> Map.Map T.Text T.Text -> IO (Either [Diagnostic] [[T.Text]])
pagesMini manifestExtra style source files bib = withSystemTempDirectory "golem-pages" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 manifestExtra <> miniManifest)
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ files $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  ev <- evaluateProject Dev tmp
  case ev of
    Left ds -> pure (Left ds)
    Right e -> case (evBook e, filter isError (evDiagnostics e)) of
      (Just book, []) -> layoutPages fakeProvider (PdfInput tmp (evProject e) (evStyle e) book False [] bib)
      (_, ds) -> pure (Left ds)

-- | horizontalStyle with five lines a page.
fiveLines :: BS.ByteString
fiveLines = replaceIn "lines = 30" "lines = 5" horizontalStyle

refsJson :: BS.ByteString
refsJson = "[{\"id\": \"knuth1981\", \"title\": \"Breaking Paragraphs into Lines\", \"author\": [{\"family\": \"Knuth\", \"given\": \"Donald\"}], \"issued\": {\"date-parts\": [[1981]]}}]"

indexTests :: [TestTree]
indexTests =
  [ testCase "index lines: entries, sub-entries indented, pages once and in order" $ do
      let sp i = mkSpan (FileId 0) i (i + 1)
          pages = Map.fromList [(sp 1, 3), (sp 2, 3), (sp 3, 10), (sp 4, 12)]
          groups =
            [ IndexGroup ["組版"] ["くみはん"] [(FileId 0, sp 1), (FileId 0, sp 2)],
              IndexGroup ["組版", "和文組版"] ["くみはん", "わぶんくみはん"] [(FileId 0, sp 3)],
              IndexGroup ["和文"] ["わぶん"] [(FileId 0, sp 4)]
            ]
      map rendered (indexLines False (`Map.lookup` pages) groups) @?= ["組版　3", "　和文組版　10", "和文　12"],
    testCase "a sub-entry without its main entry gets a main line without pages" $ do
      let sp i = mkSpan (FileId 0) i (i + 1)
      map rendered (indexLines False (const (Just 5)) [IndexGroup ["組版", "和文組版"] ["くみはん", "わぶんくみはん"] [(FileId 0, sp 1)]]) @?= ["組版", "　和文組版　5"],
    testCase "two sub-entries share one main line" $ do
      let sp i = mkSpan (FileId 0) i (i + 1)
          groups =
            [ IndexGroup ["組版", "欧文組版"] ["くみはん", "おうぶんくみはん"] [(FileId 0, sp 1)],
              IndexGroup ["組版", "和文組版"] ["くみはん", "わぶんくみはん"] [(FileId 0, sp 2)]
            ]
      map rendered (indexLines False (const (Just 5)) groups) @?= ["組版", "　欧文組版　5", "　和文組版　5"],
    testCase "vertical index pages are numbers separated by 、" $ do
      let sp i = mkSpan (FileId 0) i (i + 1)
          pages = Map.fromList [(sp 1, 3), (sp 2, 12)]
      case indexLines True (`Map.lookup` pages) [IndexGroup ["組版"] ["くみはん"] [(FileId 0, sp 2), (FileId 0, sp 1)]] of
        [l] -> do
          numbersIn l @?= [3, 12]
          rendered l @?= "組版　3、12"
        other -> assertFailure (show other),
    testCase "bibliography lines: number and entry, or the key when it is unknown" $
      map rendered (bibliographyLines (Map.fromList [("knuth1981", "Knuth Donald. Breaking.")]) [("knuth1981", 1), ("missing", 2)]) @?= ["[1] Knuth Donald. Breaking.", "[2] missing"],
    testCase "the index of a book shows the pages of its marks" $ do
      let source =
            "# 一\n\n本文[index reading=くみはん: 組版]。\n\n"
              <> fillers 3
              <> "# 二\n\n"
              <> fillers 4
              <> "本文[index reading=わぶん: 和文]。\n\n@index\n"
      r <- pagesMini "" fiveLines source [] Map.empty
      pages <- either (assertFailure . show) pure r
      let at t = [n | (n, ls) <- zip [1 :: Int ..] pages, any (t `T.isInfixOf`) ls]
      take 1 (at "本文") @?= [1]
      assertBool (show pages) (any ("組版　1" `elem`) pages)
      assertBool (show pages) (any ("和文　3" `elem`) pages),
    testCase "an index page that gains a digit converges" $ do
      r <- pagesMini "" fiveLines (fillers 45 <> "本文[index reading=くみはん: 組版]。\n\n@index\n") [] Map.empty
      pages <- either (assertFailure . show) pure r
      assertBool (show (drop 9 pages)) (any ("組版　10" `elem`) pages),
    testCase "citations show their number; the bibliography lists the entry" $ do
      r <- pagesMini "bibliography = [\"refs.json\"]\n" horizontalStyle "本文[cite knuth1981]。\n\n@bibliography\n" [("refs.json", refsJson)] (Map.fromList [("knuth1981", "Knuth Donald. Breaking Paragraphs into Lines. 1981.")])
      ls <- concat <$> either (assertFailure . show) pure r
      assertBool (show ls) (any ("[1]" `T.isInfixOf`) ls)
      assertBool (show ls) (not (any ("knuth1981" `T.isInfixOf`) ls))
      assertBool (show ls) (any (\l -> "[1]" `T.isPrefixOf` l && "Knuth" `T.isInfixOf` l) ls),
    testCase "every index mark has a page" $ do
      img <- tinyImage
      let source =
            "# 見出し[index reading=み: 見]\n\n本文[index reading=ほ: 本]。[note: 注[index reading=ちゅう: 注]]\n\n= 用語[index reading=よう: 用]\n  定義。\n\n@figure images/tiny.jpg alt=\"t\"\n  キャプション[index reading=きゃ: 図]。\n\n@index\n"
      (_, pl) <- layoutOk horizontal24 source img
      sort (map spanStart (Map.keys (markPages (plPages pl)))) @?= offsetsIn "[index" source,
    testCase "index and bibliography: parallel and sequential, and two builds, give the same bytes" $ do
      let source = "# 一\n\n本文[index reading=くみはん: 組版][cite knuth1981]。\n\n" <> fillers 8 <> "@index\n\n@bibliography\n"
          build' parallel = withSystemTempDirectory "golem-mini" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") ("bibliography = [\"refs.json\"]\n" <> miniManifest)
            BS.writeFile (tmp </> "style.toml") fiveLines
            BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
            BS.writeFile (tmp </> "refs.json") refsJson
            r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optParallel = parallel}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            case filter (".pdf" `isSuffixOf`) (brWritten r) of
              [p] -> BS.readFile p
              other -> assertFailure (show other)
      a <- build' True
      b <- build' False
      c <- build' True
      a @?= b
      a @?= c
      qpdfCheck a
  ]

-- | The rules of a content stream: x, y, width, height as written.
rulesIn :: BS.ByteString -> [[BS.ByteString]]
rulesIn content = [take 4 ws | l <- BC.lines content, let ws = BC.words l, drop 4 ws == ["re", "f"]]

-- | Content streams that draw (pages), each inflated.
pageContents :: BS.ByteString -> IO [BS.ByteString]
pageContents pdf = filter (\c -> " Tf" `BS.isInfixOf` c || " re f" `BS.isInfixOf` c) <$> inflateAll pdf

smallTable :: T.Text
smallTable = "| 項目 | 値 |\n|:---|---:|\n| 幅 | 10 |\n| 高さ | 20 |\n"

ptToRational :: BS.ByteString -> Rational
ptToRational t = case BC.split '.' t of
  [i] -> fromInteger (read (BC.unpack i))
  [i, f] ->
    let sign = if "-" `BS.isPrefixOf` i then -1 else 1
        whole = abs (read (BC.unpack i) :: Integer)
     in sign * (fromInteger whole + fromInteger (read (BC.unpack f)) / 10 ^ BS.length f)
  _ -> 0

tableTests :: [TestTree]
tableTests =
  [ testCase "a table has three rules: top, below the header, bottom" $ do
      content <- miniPdf fakeProvider True horizontalStyle ("前。\n\n" <> smallTable <> "\n後。\n") [] >>= fmap BS.concat . inflateAll
      length (rulesIn content) @?= 3,
    testCase "a table across two pages repeats its header and its rules" $ do
      let rows = T.concat ["| 行" <> T.pack (show i) <> " | " <> T.pack (show i) <> " |\n" | i <- [1 .. 6 :: Int]]
      pdf <- miniPdf fakeProvider True fiveLines ("| 項目 | 値 |\n|---|---|\n" <> rows) []
      pages <- pageContents pdf
      length (concatMap rulesIn pages) @?= 6
      length [() | c <- pages, fromEnum '項' `elem` map dGlyph (drawnGlyphs c)] @?= 2,
    testCase "vertical: rules run down the page and columns follow each other downwards" $ do
      content <- miniPdf fakeProvider True pdfStyle "前。\n\n| 項目 | 値 |\n|---|---|\n| 幅 | 広い |\n" [] >>= fmap BS.concat . inflateAll
      let rs = rulesIn content
      length rs @?= 3
      assertBool (show rs) (all (\case [_, _, w, h] -> ptToRational w < ptToRational h; _ -> False) rs)
      let ds = drawnGlyphs content
      case ([d | d <- ds, dGlyph d == fromEnum '幅'], [d | d <- ds, dGlyph d == fromEnum '広']) of
        ([a], b : _) -> do
          dX a @?= dX b
          assertBool (show (dY a, dY b)) (ptToRational (dY b) < ptToRational (dY a))
        other -> assertFailure (show other),
    testCase "columns too wide for the measure, or a row taller than a page, are errors" $ do
      let wide = "| " <> T.intercalate " | " (replicate 13 "字") <> " |\n|" <> T.replicate 13 "---|" <> "\n| " <> T.intercalate " | " (replicate 13 "字") <> " |\n"
      (e1, p1) <- buildMini fakeProvider True horizontalStyle wide []
      (e1, p1) @?= ([DiagnosticCode "G0741"], Nothing)
      let tall = "| 項目 | 値 |\n|---|---|\n| " <> T.replicate 60 "あ" <> " | 1 |\n"
      (e2, p2) <- buildMini fakeProvider True fiveLines tall []
      (e2, p2) @?= ([DiagnosticCode "G0742"], Nothing),
    testCase "a table from CSV is set the same way" $ do
      content <- miniPdf fakeProvider True horizontalStyle "@table src=data.csv\n" [("data.csv", TE.encodeUtf8 "項目,値\n幅,10\n")] >>= fmap BS.concat . inflateAll
      length (rulesIn content) @?= 3
      assertBool "cells" (fromEnum '幅' `elem` map dGlyph (drawnGlyphs content)),
    testCase "tables: parallel and sequential, and two builds, give the same bytes" $ do
      let source = "前。\n\n" <> smallTable <> "\n後。\n\n" <> smallTable
      a <- miniPdf fakeProvider True horizontalStyle source []
      b <- miniPdf fakeProvider False horizontalStyle source []
      c <- miniPdf fakeProvider True horizontalStyle source []
      a @?= b
      a @?= c
      qpdfCheck a
  ]

-- | The Latin test fonts of golem-font: a CFF sans and a TrueType serif.
realLatinFonts :: IO (BS.ByteString, BS.ByteString)
realLatinFonts = (,) <$> BS.readFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" <*> BS.readFile "../golem-font/test/fonts/SourceSerifVariable-Roman.ttf"

-- | How many times a pattern occurs.
occurrences :: BS.ByteString -> BS.ByteString -> [Int]
occurrences pat = go 0
  where
    go off s = case BS.breakSubstring pat s of
      (_, rest) | BS.null rest -> []
      (before, rest) -> (off + BS.length before) : go (off + BS.length before + 1) (BS.drop 1 rest)

-- | The size of every Tf operator in a content stream (the number before Tf).
tfSizes :: BS.ByteString -> [BS.ByteString]
tfSizes content = [size | l <- BC.lines content, (size, "Tf") <- zip (BC.words l) (drop 1 (BC.words l))]

{- | Fixed-width stand-in fonts: full-width characters one em, others half;
the role "wide" (face 2) sets everything one em wide; the role "heading"
is face 4.
-}
fakeFonts :: LoadedFonts
fakeFonts =
  LoadedFonts
    { lfAdvance = advOf,
      lfWordAdvance = \role -> sum . map (advOf role) . T.unpack,
      lfCode = \_ g -> g,
      lfShape = \role _ t -> [(faceOf role, fromEnum c `mod` 65536, advOf role c, T.singleton c) | c <- T.unpack t],
      lfEmbed = \_ vertical used ->
        Font "AAAAAA+Fake" (TrueTypeProgram "fake font program") vertical [(g, 1000) | (g, _) <- used] [] 880 (-120) 700 80 (0, -120, 1000, 880) 0 used
    }
  where
    -- the role "wide" sets every character one em wide
    advOf role c = if role == "wide" then 1 else adv c
    faceOf = \case
      "wide" -> 2
      "heading" -> 4
      _ -> 0
    adv c = if fromEnum c < 0x2000 then 1 / 2 else 1

qpdfCheck :: BS.ByteString -> IO ()
qpdfCheck pdf = do
  qpdf <- findExecutable "qpdf"
  case qpdf of
    Nothing -> pure ()
    Just exe -> withSystemTempDirectory "golem-pdf" $ \dir -> do
      BS.writeFile (dir </> "out.pdf") pdf
      (code, out, err) <- readProcessWithExitCode exe ["--check", dir </> "out.pdf"] ""
      assertEqual (out <> err) ExitSuccess code

-- | Every Flate stream of a PDF, inflated (others as they are).
inflateAll :: BS.ByteString -> IO [BS.ByteString]
inflateAll pdf = case BS.breakSubstring "stream\n" pdf of
  (_, rest) | BS.null rest -> pure []
  (_, rest) -> do
    let body = BS.drop 7 rest
        (content, rest') = BS.breakSubstring "\nendstream" body
    r <- try (evaluate (BL.toStrict (Z.decompress (BL.fromStrict content))))
    let inflated = either (\(_ :: SomeException) -> content) id r
    (inflated :) <$> inflateAll (BS.drop (BS.length "\nendstream") rest')

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

countingFonts :: IORef Int -> FontProvider
countingFonts ref = FontProvider (\_ _ -> modifyIORef' ref (+ 1) >> pure (Right fakeFonts))

buildPdf :: Bool -> IO BS.ByteString
buildPdf parallel = withSystemTempDirectory "golem-driver" $ \tmp -> do
  copyTree fixture tmp
  BS.writeFile (tmp </> "style.toml") pdfStyle
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = FontProvider (\_ _ -> pure (Right fakeFonts)), optParallel = parallel}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  case brWritten r of
    [path] -> BS.readFile path
    other -> assertFailure (show other)
