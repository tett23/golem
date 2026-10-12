module Main (main) where

import Codec.Compression.Zlib qualified as Z
import Control.Exception (SomeException, evaluate, try)
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
import Golem.Driver
import Golem.Driver.New
import Golem.Driver.Pdf (instanceIdInputs)
import Golem.Driver.Version (golemVersion)
import Golem.LayoutSpec (pageGeometry)
import Golem.Pdf (Font (..), FontProgram (..))
import Golem.Plugin (watToWasm)
import Golem.Plugin.Lock (defaultCacheDir, hashHex, lockPlugins, renderLock)
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, findExecutable, listDirectory)
import System.Environment (setEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
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
      testGroup "plugins (golem-plugin ADR 0001, 0002)" pluginTests,
      testGroup
        "public-domain books"
        [ testCase "The Tempest builds horizontally to every target" $ do
            (written, pdf) <- buildBook "tempest"
            assertBool (show written) (all (\ext -> any (ext `isSuffixOf`) written) [".pdf", ".epub", ".xhtml", ".txt"])
            assertBool "horizontal" (not ("/Identity-V" `BS.isInfixOf` pdf))
            qpdfCheck pdf,
          testCase "蟹工船 builds vertically to every target" $ do
            (written, pdf) <- buildBook "kanikosen"
            assertBool (show written) (all (\ext -> any (ext `isSuffixOf`) written) [".pdf", ".epub", ".xhtml", ".txt"])
            assertBool "vertical" ("/Identity-V" `BS.isInfixOf` pdf)
            qpdfCheck pdf
        ]
    ]

-- | Builds a copy of a book fixture (fonts included); no errors allowed.
buildBook :: FilePath -> IO ([FilePath], BS.ByteString)
buildBook name = withSystemTempDirectory "golem-book" $ \tmp -> do
  copyTree ("test/fixtures" </> name) tmp
  r <- build (defaultOptions tmp)
  assertEqual "no errors" [] [(diagCode d, diagMessage d) | d <- brDiagnostics r, isError d]
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> BS.readFile p
    other -> assertFailure (show other)
  pure (brWritten r, pdf)

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

-- | The size of every Tf operator in a content stream (the number before Tf).
tfSizes :: BS.ByteString -> [BS.ByteString]
tfSizes content = [size | l <- BC.lines content, (size, "Tf") <- zip (BC.words l) (drop 1 (BC.words l))]

-- | Fixed-width stand-in fonts: full-width characters one em, others half.
fakeFonts :: LoadedFonts
fakeFonts =
  LoadedFonts
    { lfAdvance = adv,
      lfWordAdvance = sum . map adv . T.unpack,
      lfCode = \_ g -> g,
      lfShape = \_ t -> [(0, fromEnum c `mod` 65536, adv c, T.singleton c) | c <- T.unpack t],
      lfEmbed = \_ vertical used ->
        Font "AAAAAA+Fake" (TrueTypeProgram "fake font program") vertical [(g, 1000) | (g, _) <- used] [] 880 (-120) 700 80 (0, -120, 1000, 880) 0 used
    }
  where
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
