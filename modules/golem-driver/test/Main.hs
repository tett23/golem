module Main (main) where

import Codec.Compression.Zlib qualified as Z
import Control.Exception (SomeException, evaluate, try)
import Control.Monad (filterM, forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (isSuffixOf, nub, sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (IndexGroup (..), inlineText)
import Golem.Doc.IR (Inline, InlineF (..))
import Golem.Driver
import Golem.Driver.Explain (Explanation (..), Status (..), catalog, codeDescriptionUrl, explainHint, lookupExplanation, parseCatalog)
import Golem.Driver.New
import Golem.Driver.Pdf (PdfInput (..), PdfLayout (..), PlacedFigure (..), PlacedSidenote (..), SetLine (..), TocGeometry (..), TocPage (..), bibliographyLines, figureRect, flowLines, indexLines, instanceIdInputs, layoutPages, layoutPdf, producer, syntheticStroke, syntheticStrokeJa, syntheticStrokeLatin, tocPage, usedRoles)
import Golem.Driver.Version (golemVersion)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..), Synthetic (..), plainLook)
import Golem.Layout.Paginate (Flow (..), PageOut (..), Slotted (..), markPages)
import Golem.Layout.Ruby (RubyAlign (..), RubyKind (..), RubyPlacement (..), RubyStyle (..), placeRuby)
import Golem.Layout.Wrap (Exclusion (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..), baselineRatio, pageGeometry, sidenoteAreaFor, typeAreaFor)
import Golem.Pdf (Font (..), FontProgram (..), spToPt)
import Golem.Pdf qualified as P
import Golem.Plugin (watToWasm)
import Golem.Plugin.Lock (defaultCacheDir, hashHex, lockPlugins, renderLock)
import Golem.Project.Style (Dim (..), dimToSp, parseDim, parseStyle)
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
    [ explainTests,
      testGroup
        "version (docs/adr/0004)"
        [ testCase "golemVersion is the content of VERSION" $ do
            v <- T.strip <$> TIO.readFile "../../VERSION"
            golemVersion @?= v,
          testCase "the PDF instance ID is computed from golem- and the version, last" $ do
            let inputs = instanceIdInputs ["input"] ["font program"]
            inputs @?= ["input", "font program", TE.encodeUtf8 ("golem-" <> golemVersion)]
            last inputs @?= TE.encodeUtf8 ("golem-" <> golemVersion)
        ],
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
            sum (map (length . occurrences "<002D>") contents) @?= T.count "-" source,
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
      testGroup "files of style.toml per target (golem-project ADR 0004)" styleFileTests,
      testGroup "verse (docs/adr ADR 0003)" verseTests,
      testGroup "paragraph indents (docs/adr ADR 0006)" indentTests,
      testGroup "PDF headings (ADR 0003)" headingTests,
      testGroup "PDF emphasis, character styles and colour (ADR 0004)" emphasisTests,
      testGroup "PDF wrapped figures (ADR 0005)" wrapTests,
      testGroup "PDF captions (ADR 0010)" captionTests,
      testGroup "PDF sidenotes (ADR 0006)" sidenoteTests,
      testGroup "PDF index and bibliography (ADR 0007)" indexTests,
      testGroup "PDF tables (ADR 0008)" tableTests,
      testGroup "PDF table of contents (ADR 0009)" tocTests,
      testGroup "ruby placement (golem-layout ADR 0009)" rubyTests,
      testGroup "plugins (golem-plugin ADR 0001, 0002)" pluginTests,
      testGroup "crop marks and bleed (golem-pdf ADR 0004)" marksTests,
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
verseSource = "@style verse\n  Full fathom five thy father lies;\n  Of his bones are coral made;\n\n  Nothing of him that doth fade,\n"

-- | The PDF flow of a verse project and its lines as (line length, indent).
verseLines :: BS.ByteString -> T.Text -> IO ([Flow], [(Integer, Integer)])
verseLines style src = withVerseProject style src $ \tmp -> do
  ev <- evaluateProject Dev tmp
  case ev of
    Left ds -> assertFailure (show ds)
    Right e -> case evBook e of
      Nothing -> assertFailure (show (map diagCode (evDiagnostics e)))
      Just book -> do
        r <- flowLines (FontProvider (\_ _ -> pure (Right fakeFonts))) (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing)
        either (assertFailure . show) pure r

verseTests :: [TestTree]
verseTests =
  [ testCase "HTML: stanzas are p of the verse style, lines are span and br; the CSS hangs the lines" $
      withVerseProject "[paragraph-styles.verse]\nindent = \"3zw\"\nfirst-line-indent = \"-3zw\"\n" verseSource $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        page <- TIO.readFile (tmp </> "build/html/v.xhtml")
        assertBool
          (T.unpack page)
          ( "<p class=\"ps-verse\"><span class=\"line\">Full fathom five thy father lies;</span><br/>\n<span class=\"line\">Of his bones are coral made;</span></p>\n<p class=\"ps-verse\"><span class=\"line\">Nothing of him that doth fade,</span></p>\n"
              `T.isInfixOf` page
          )
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "line rule" (".line { display: block; }" `T.isInfixOf` css)
        assertBool "br rule" (".line + br { display: none; }" `T.isInfixOf` css)
        assertBool "hang" ("p.ps-verse { padding-inline-start: 3em; text-indent: -3em; }" `T.isInfixOf` css)
        assertBool "stanza gap" ("p.ps-verse + p.ps-verse { margin-block-start: 1em; }" `T.isInfixOf` css),
    testCase "HTML: no space rule when space-between is 0" $
      withVerseProject "[paragraph-styles.verse]\nspace-between = 0\nindent = \"10.5pt\"\n" verseSource $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "no stanza gap" (not ("p.ps-verse + p.ps-verse" `T.isInfixOf` css))
        assertBool "margin" ("p.ps-verse { margin-block: 0; }" `T.isInfixOf` css)
        assertBool "indent" ("p.ps-verse { padding-inline-start: 10.5pt; text-indent: -2em; }" `T.isInfixOf` css),
    testCase "plain text: lines on lines, stanzas separated by a blank line" $
      withVerseProject "" verseSource $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        t <- TIO.readFile (tmp </> "build/text/horizontal/v.txt")
        t @?= "Full fathom five thy father lies;\nOf his bones are coral made;\n\nNothing of him that doth fade,\n",
    testCase "PDF: a long line is broken and its continuation hangs" $ do
      let style = "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 30\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n"
          fs = 655360
      (flow, ls) <- verseLines style ("@style verse\n  " <> T.replicate 45 "あ" <> "\n\n  い\n")
      ls @?= [(30 * fs, 0), (28 * fs, 2 * fs), (30 * fs, 0)]
      [length bs | FParagraph bs <- flow] @?= [2, 1]
      [n | FSpace n <- flow] @?= [1],
    testCase "PDF: the hang in vertical writing, and the space between stanzas from the style" $ do
      let fs = maybe 0 (dimToSp 0) (parseDim "13Q")
      (flow, ls) <- verseLines (pdfStyle <> "\n[paragraph-styles.verse]\nspace-between = 2\n") ("@style verse\n  " <> T.replicate 60 "あ" <> "\n\n  い\n")
      map snd ls @?= [0, 2 * fs, 0]
      [n | FSpace n <- flow] @?= [2],
    testCase "PDF: the attribute form and a label" $ do
      (flow, ls) <- verseLines pdfStyle "@label song\n@style verse\nあ\nい\n"
      length ls @?= 2
      [length bs | FParagraph bs <- flow] @?= [1, 1],
    testCase "PDF: a verse line takes the look of its inline elements" $ do
      (_, layout) <- layoutOk horizontalStyle "@style verse\n  前の[bold: 本文]後\n" []
      [bcText c | sl <- Map.elems (plLines layout), Box _ c <- lineItems (slLine sl), synBold (lkSynthetic (bcLook c))] @?= ["本", "文"]
  ]

-- | horizontalStyle with 30 characters a line (300pt), and more.
horizontal30 :: BS.ByteString -> BS.ByteString
horizontal30 extra = replaceIn "characters = 12" "characters = 30" horizontalStyle <> extra

indentTests :: [TestTree]
indentTests =
  [ testCase "PDF: the first line of a paragraph is indented by first-line-indent" $ do
      let fs = 655360
      (_, ls) <- verseLines (horizontal30 "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") (T.replicate 45 "あ" <> "\n")
      ls @?= [(29 * fs, fs), (30 * fs, 0)],
    testCase "PDF: a hanging indent" $ do
      let fs = 655360
      (_, ls) <- verseLines (horizontal30 "\n[paragraph-styles.quote]\nindent = \"2zw\"\nfirst-line-indent = \"-2zw\"\n") ("@style quote\n" <> T.replicate 45 "あ" <> "\n")
      map snd ls @?= [0, 2 * fs]
      map fst ls @?= [30 * fs, 28 * fs],
    testCase "PDF: vertical, the first line starts a character lower" $ do
      let fs = maybe 0 (dimToSp 0) (parseDim "13Q")
          firstY pdf = do
            content <- BS.concat <$> inflateAll pdf
            case [dY d | d <- drawnGlyphs content, dGlyph d == fromEnum 'い'] of
              (y : _) -> pure (ptToRational y)
              [] -> assertFailure "no glyph"
      (_, ls) <- verseLines (pdfStyle <> "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") (T.replicate 60 "あ" <> "\n")
      take 2 (map snd ls) @?= [fs, 0]
      a <- miniPdf fakeProvider True (pdfStyle <> "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") "いろは\n" [] >>= firstY
      b <- miniPdf fakeProvider True pdfStyle "いろは\n" [] >>= firstY
      assertBool (show (a, b)) (abs ((b - a) - toRational fs / 65536) < 1 / 100),
    testCase "PDF: no indent in list items and the table of contents; indent in definitions" $ do
      let fs = 655360
          style = horizontal30 "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n"
      (_, items) <- verseLines style "- 項目\n- 項目\n"
      map snd items @?= [0, 0]
      (_, toc) <- verseLines style "@toc\n\n# 章\n"
      assertBool (show toc) (all ((== 0) . snd) toc)
      (_, defs) <- verseLines style "= 用語\n  説明の段落。\n"
      map snd defs @?= [0, fs],
    testCase "PDF: beside a wrap=start figure, the first line adds its indent to the exclusion" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (horizontal24 <> "\n[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n") (wrapped "start" "4zw" <> longPara 30) img
      (_, _, p, slot) <- theFigure pl
      take 2 (map (slIndent . snd) (linesFrom pl p slot)) @?= [60 * pt, 50 * pt],
    testCase "PDF: an indent that leaves less than 8 characters is G0725" $ do
      let style = replaceIn "characters = 12" "characters = 10" horizontalStyle <> "\n[paragraph-styles.body]\nindent = \"3zw\"\n"
      (errs, pdf) <- buildMini fakeProvider True style "本文。\n" []
      (nub errs, pdf) @?= ([DiagnosticCode "G0725"], Nothing),
    testCase "HTML: the indent of body and of verse, none in list items" $ do
      withVerseProject "[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n" "本文。\n" $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "body" ("p { padding-inline-start: 0em; text-indent: 1em; }" `T.isInfixOf` css)
        assertBool "list items" ("li p, li p[class] { padding-inline-start: 0; text-indent: 0; }" `T.isInfixOf` css)
      withVerseProject "" verseSource $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "verse" ("p.ps-verse { padding-inline-start: 2em; text-indent: -2em; }" `T.isInfixOf` css)
        assertBool "lines" (".line { display: block; }" `T.isInfixOf` css)
        assertBool "no body rule" (not ("\np { " `T.isInfixOf` css)),
    testCase "plain text: the first line starts with ideographic spaces" $ do
      let text style src = withVerseProject style src $ \tmp -> do
            _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
            TIO.readFile (tmp </> "build/text/horizontal/v.txt")
      text "[paragraph-styles.body]\nfirst-line-indent = \"1zw\"\n" "本文。\n\n- 項目\n" >>= (@?= "　本文。\n\n・項目\n")
      text "[paragraph-styles.body]\nfirst-line-indent = \"3mm\"\n" "本文。\n" >>= (@?= "本文。\n")
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

-- | What a build of the one-chapter project left behind.
data Built = Built
  { bErrors :: ![Diagnostic],
    bSources :: !(Map.Map FileId SourceInfo),
    bPdf :: !(Maybe BS.ByteString),
    bWritten :: ![FilePath],
    bBuildDir :: !Bool
  }

{- | Builds the one-chapter project with a style.toml (if given) and changed
options; PDF only and the fake fonts unless the options say otherwise.
-}
buildMarks :: (BuildOptions -> BuildOptions) -> Maybe BS.ByteString -> IO Built
buildMarks = buildMarksWith "本文。\n"

-- | 'buildMarks' with another source of the chapter.
buildMarksWith :: T.Text -> (BuildOptions -> BuildOptions) -> Maybe BS.ByteString -> IO Built
buildMarksWith source f style = withSystemTempDirectory "golem-marks" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n")
  forM_ style (BS.writeFile (tmp </> "style.toml"))
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  r <- build (f (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider})
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  dir <- doesDirectoryExist (tmp </> "build")
  pure (Built (filter isError (brDiagnostics r)) (brSources r) pdf (brWritten r) dir)

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

-- | The document ID and the instance ID of the trailer.
pdfIds :: BS.ByteString -> (BS.ByteString, BS.ByteString)
pdfIds pdf =
  let rest = BS.drop 6 (snd (BS.breakSubstring "/ID [<" pdf))
      (a, rest') = BS.breakSubstring ">" rest
   in (a, BC.takeWhile (/= '>') (BS.drop 3 rest'))

-- | The trimmed size of the A5 page of horizontalStyle.
a5Size :: IO (Integer, Integer)
a5Size = case parseStyle (FileId 0) (TE.decodeUtf8 horizontalStyle) of
  Right s -> either (assertFailure . show) (pure . pgPageSize) (pageGeometry s)
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
      [(fmap siPath (Map.lookup (spanFile (diagSpan d)) (bSources b)), spanStart (diagSpan d)) | d <- bErrors b] @?= [(Just "manifest.toml", 0)],
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
      -- style.toml is an input of the instance ID (golem-pdf ADR 0004), so the trailer differs
      let withoutId pdf = fst (BS.breakSubstring "/ID [" pdf)
      withoutId a @?= withoutId b
      assertBool "instance ID" (snd (pdfIds a) /= snd (pdfIds b)),
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

{- | The runs of glyphs of a content stream: the font resource, the stroke
width of synthetic bold (when the run has one) and the glyphs (golem-driver ADR 0012).
-}
strokeRuns :: BS.ByteString -> [(BS.ByteString, Maybe BS.ByteString, [Int])]
strokeRuns content = go (BC.lines content)
  where
    go [] = []
    go (l : rest)
      | ws@(_ : _) <- BC.words l,
        "Tf" `elem` ws,
        (f : _) <- dropWhile (not . ("/F" `BS.isPrefixOf`)) ws =
          let (body, rest') = break (("ET" `BS.isPrefixOf`) . BC.strip) rest
              width = case dropWhile (/= "Tr") ws of
                (_ : w : "w" : _) -> Just w
                _ -> Nothing
           in (f, width, [g | b <- body, Just g <- [glyph b]]) : go rest'
      | otherwise = go rest
    glyph l = case reverse (BC.words l) of
      ("Tj" : hexg : "Tm" : _) -> Just (read ("0x" <> BC.unpack (BC.filter (`notElem` ("<>" :: String)) hexg)))
      _ -> Nothing

-- | The stroke widths of the runs that draw a character.
widthsOf :: Char -> [(BS.ByteString, Maybe BS.ByteString, [Int])] -> [Maybe BS.ByteString]
widthsOf c runs = nub [w | (_, w, gs) <- runs, fromEnum c `elem` gs]

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
      h <- miniPdf fakeProvider True (horizontalStyle <> "\n[character-styles.strong]\nbased-on = \"italic\"\n") "[strong: Golem と組版]\n" [] >>= fmap BS.concat . inflateAll
      assertBool (show (slanted h)) (length (slanted h) == 4 && all ((== ["1", "0", "0.2", "1"]) . snd) (slanted h))
      v <- miniPdf fakeProvider True (pdfStyle <> "\n[character-styles.strong]\nbased-on = \"italic\"\n") "[strong: Golem と組版]\n" [] >>= fmap BS.concat . inflateAll
      let upright = [m | (g, m) <- slanted v, g /= fromEnum 'G']
      assertBool (show (slanted v)) (length upright == 3 && all (== ["1", "0", "0.2", "1"]) upright)
      assertBool "turned Latin" (any ((== ["0", "-1", "1", "-0.2"]) . snd) (slanted v)),
    testCase "an italic role with only Latin sets Latin upright in it and slants the Japanese" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.italic]\nfont = \"wide\"\n") "本[italic: Golem と組版]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
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
      wide <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.bold]\nfont = \"wide\"\n") source fakeFontFiles >>= rows
      assertBool (show (plain, wide)) (wide > plain),
    testCase "a bold role with its own font embeds it with the bold glyphs only" $ do
      (sans, serif) <- realLatinFonts
      pdf <- miniPdf realProvider True (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.bold]\nlatin = \"fonts/serif.ttf\"\n\n[character-styles.bold]\nfont = \"bold\"\n") "[bold: Zebra] quick\n" [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
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
      let style = horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.italic]\nfont = \"wide\"\n\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
          source = "[strong: 強い] [bold: Bold] [italic: Golem と組版] [color accent: 赤 [bold: 太い]]。\n"
      a <- miniPdf fakeProvider True style source fakeFontFiles
      b <- miniPdf fakeProvider False style source fakeFontFiles
      c <- miniPdf fakeProvider True style source fakeFontFiles
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "HTML: a bold role is declared bold and b names it before the body" $ withSystemTempDirectory "golem-mini" $ \tmp -> do
      BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n")
      BS.writeFile (tmp </> "style.toml") "[fonts.body]\nja = \"fonts/b.otf\"\n\n[fonts.gothic]\nja = \"fonts/h.otf\"\n\n[character-styles.bold]\nfont = \"gothic\"\n"
      BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 "[bold: 太い]\n")
      forM_ fakeFontFiles $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
      r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
      assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
      cssText <- TIO.readFile (tmp </> "build/html/style.css")
      assertBool (T.unpack cssText) ("@font-face { font-family: \"golem-gothic-ja\"; src: url(\"fonts/h.otf\"); font-weight: bold; }" `T.isInfixOf` cssText)
      assertBool (T.unpack cssText) ("b { font-family: \"golem-gothic-ja\", \"golem-body-ja\", serif; font-weight: bold; }" `T.isInfixOf` cssText)
      assertBool "strong too" ("strong { font-family: \"golem-gothic-ja\", \"golem-body-ja\", serif; font-weight: bold; }" `T.isInfixOf` cssText),
    testCase "the stroke of synthetic bold: 1/80 of the size for Japanese, 1/60 for Latin (golem-driver ADR 0012)" $ do
      syntheticStroke syntheticStrokeJa 655360 @?= 8192
      syntheticStroke syntheticStrokeLatin 655360 @?= 10922
      ja <- miniPdf fakeProvider True horizontalStyle "前の[bold: 本文]後\n" [] >>= fmap (strokeRuns . BS.concat) . inflateAll
      nub [w | (_, Just w, _) <- ja] @?= ["0.125"]
      latin <- miniPdf fakeProvider True horizontalStyle "[bold: Golem]\n" [] >>= fmap (strokeRuns . BS.concat) . inflateAll
      nub [w | (_, Just w, _) <- latin] @?= [TE.encodeUtf8 (spToPt 10922)],
    testCase "Japanese and Latin in one bold run get their own strokes, and the glyphs stay" $ do
      let style = horizontalStyle <> fakeBody
      runs <- miniPdf fakeProvider True style "[bold: 本Golem]\n" fakeFontFiles >>= fmap (strokeRuns . BS.concat) . inflateAll
      widthsOf '本' runs @?= [Just "0.125"]
      widthsOf 'G' runs @?= [Just (TE.encodeUtf8 (spToPt 10922))]
      a <- miniPdf fakeProvider True style "[bold: 本Golem]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      b <- miniPdf fakeProvider True style "本Golem\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      sort [(dGlyph d, dX d, dY d) | d <- drawnGlyphs a] @?= sort [(dGlyph d, dX d, dY d) | d <- drawnGlyphs b],
    testCase "the stroke follows the size" $ do
      runs <- miniPdf fakeProvider True (horizontalStyle <> "\n[character-styles.big]\nsize = \"2zw\"\n") "[style big: [bold: 本]]\n" [] >>= fmap (strokeRuns . BS.concat) . inflateAll
      widthsOf '本' runs @?= [Just "0.25"],
    testCase "a bold role with Japanese only: Japanese in it without a stroke, Latin synthetic" $ do
      runs <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n\n[character-styles.bold]\nfont = \"heading\"\n") "[bold: 本Golem]\n" fakeFontFiles >>= fmap (strokeRuns . BS.concat) . inflateAll
      widthsOf '本' runs @?= [Nothing]
      widthsOf 'G' runs @?= [Just (TE.encodeUtf8 (spToPt 10922))]
      assertBool "different fonts" (nub [f | (f, _, gs) <- runs, fromEnum '本' `elem` gs] /= nub [f | (f, _, gs) <- runs, fromEnum 'G' `elem` gs]),
    testCase "a character style colours its text" $ do
      pdf <- miniPdf fakeProvider True (horizontalStyle <> "\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n\n[character-styles.term]\ncolor = \"accent\"\n") "前[style term: 語]後\n" []
      content <- BS.concat <$> inflateAll pdf
      assertBool "fill" ("0 0.8 1 0 k" `BS.isInfixOf` content),
    testCase "a paragraph style sets the role of its paragraphs" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n\n[paragraph-styles.quote]\nfont = \"heading\"\n") "本\n\n@style quote\n語\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
      assertBool "the heading role's font" ([dFont d | d <- ds, dGlyph d == fromEnum '語'] /= [dFont d | d <- ds, dGlyph d == fromEnum '本'])
      assertBool "drawn" (not (null [d | d <- ds, dGlyph d == fromEnum '語'])),
    testCase "a role with one side leaves the other side in the outer face, synthetic" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.bold]\nfont = \"wide\"\n") "本[bold: 語Go]\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
      [dFont d | d <- ds, dGlyph d == fromEnum '語'] @?= [dFont d | d <- ds, dGlyph d == fromEnum '本']
      assertBool "Latin in the wide role" ([dFont d | d <- ds, dGlyph d == fromEnum 'G'] /= [dFont d | d <- ds, dGlyph d == fromEnum '本'])
      assertBool "the Japanese side is synthetic bold" ("2 Tr" `BS.isInfixOf` content)
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
      (Just book, Right geom) -> fmap (geom,) <$> layoutPdf (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing) geom fakeFonts
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
sidenoteStyle = sidenoteStyleWith ""

-- | sidenoteStyle with more keys for the paragraph style sidenote (golem-driver ADR 0011); [sidenotes] stays last.
sidenoteStyleWith :: BS.ByteString -> BS.ByteString
sidenoteStyleWith keys = horizontalStyle <> "\n[paragraph-styles.sidenote]\nsize = \"8pt\"\n" <> keys <> "\n[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\n"

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

-- | horizontal24 with a caption style.
captionStyle :: BS.ByteString -> BS.ByteString
captionStyle keys = horizontal24 <> "\n[paragraph-styles.caption]\n" <> keys

-- | A figure that is not wrapped, with a caption of n full-width characters, and a paragraph after it.
figureWith :: Int -> T.Text
figureWith n = "@figure images/tiny.jpg alt=\"t\"\n  " <> T.replicate n "甲" <> "\n\n後の段落。\n"

-- | The grid line of the first line after a figure, from the figure's first grid line.
afterFigure :: PdfLayout -> IO Int
afterFigure pl = do
  (_, _, p, slot) <- theFigure pl
  case [s | (s, SLine _) <- poSlots p, s > slot] of
    (s : _) -> pure (s - slot)
    [] -> assertFailure "no line after the figure"

captionTests :: [TestTree]
captionTests =
  [ testCase "a small wrapped caption: its size, its pitch and the exclusion" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (captionStyle "size = \"8pt\"\n") (wrapped "end" "4zw" <> longPara 30) img
      (_, pf, _, _) <- theFigure pl
      (pfCaptionSize pf, pfCaptionPitch pf) @?= (8 * pt, 12 * pt)
      let n = toInteger (length (pfCaption pf))
      fmap exLines (pfExclusion pf) @?= Just (fromInteger ((4 * 15 + (n - 1) * 12 + 8 + 10 + 14) `div` 15)),
    testCase "a small caption takes fewer grid lines; the text after it stays on the grid" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (captionStyle "size = \"6pt\"\n") (figureWith 100) img
      (_, pf, _, _) <- theFigure pl
      (length (pfCaption pf), pfCaptionPitch pf, pfCaptionSpan pf) @?= (3, 9 * pt, 2)
      afterFigure pl >>= (@?= 24 + 2)
      (_, plain) <- layoutOk horizontal24 (figureWith 100) img
      (_, pf', _, _) <- theFigure plain
      length (pfCaption pf') @?= 5
      afterFigure plain >>= (@?= 24 + 5),
    testCase "the caption is drawn at its size from the top of its grid lines" $ do
      img <- tinyImage
      let style = captionStyle "size = \"6pt\"\n"
      (geom, pl) <- layoutOk style (figureWith 100) img
      (_, _, p, slot) <- theFigure pl
      pdf <- miniPdf fakeProvider True style (figureWith 100) img
      content <- BS.concat <$> inflateAll pdf
      let ta = typeAreaFor geom (poNumber p)
          top = toRational (rectY ta + rectH ta) / 65536
          ys = sortOn negate (nub [ptToRational (dY d) | d <- drawnGlyphs content, dSize d == "6"])
          first = top - toRational (toInteger (slot + 24) * 15 * pt + round (toRational (6 * pt) * baselineRatio)) / 65536
      case ys of
        (y1 : y2 : _) -> do
          assertBool (show (y1, first)) (abs (y1 - first) < 1 / 100)
          assertBool (show (y1, y2)) (abs (y1 - y2 - 9) < 1 / 100)
        other -> assertFailure (show other),
    testCase "a caption role sets the caption, the body stays in the body role" $ do
      img <- tinyImage
      content <- miniPdf fakeProvider True (captionStyle "font = \"heading\"\n" <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n") (figureWith 4) (img <> fakeFontFiles) >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
      assertBool "drawn" (not (null [d | d <- ds, dGlyph d == fromEnum '甲']))
      assertBool "the heading role's font" (nub [dFont d | d <- ds, dGlyph d == fromEnum '甲'] /= nub [dFont d | d <- ds, dGlyph d == fromEnum '後']),
    testCase "a small caption fits where a body-size one is G0723" $ do
      img <- tinyImage
      let short = replaceIn "lines = 30" "lines = 8" horizontal24
          source = "@figure images/tiny.jpg alt=\"t\" wrap=end width=4zw\n  " <> T.replicate 14 "甲" <> "\n\n" <> longPara 2
      (errs, _) <- buildMini fakeProvider True short source img
      errs @?= [DiagnosticCode "G0723"]
      (errs', _) <- buildMini fakeProvider True (short <> "\n[paragraph-styles.caption]\nsize = \"5pt\"\n") source img
      errs' @?= [],
    testCase "vertical: the caption is in the type area, its first centre line half its size from the grid" $ do
      img <- tinyImage
      let style = figStyle (replaceIn "characters = 42" "characters = 20" pdfStyle) <> "\n[paragraph-styles.caption]\nsize = \"10Q\"\n"
          q = maybe 0 (dimToSp 0) (parseDim "10Q")
      (geom, pl) <- layoutOk style (figureWith 10) img
      (_, pf, p, slot) <- theFigure pl
      pdf <- miniPdf fakeProvider True style (figureWith 10) img
      content <- BS.concat <$> inflateAll pdf
      let ta = typeAreaFor geom (poNumber p)
          right = toRational (rectX ta + rectW ta) / 65536
          xs = sortOn negate (nub [ptToRational (dX d) | d <- drawnGlyphs content, dGlyph d == fromEnum '甲'])
          expected = right - toRational (toInteger (slot + pfImageLines pf) * pgLinePitch geom + q `div` 2) / 65536
      case xs of
        (x : _) -> do
          assertBool (show (x, expected)) (abs (x - expected) < 1 / 100)
          assertBool "in the type area" (x > toRational (rectX ta) / 65536)
        [] -> assertFailure "no caption glyph",
    testCase "naming the body role and size changes nothing" $ do
      img <- tinyImage
      a <- miniPdf fakeProvider True (horizontal24 <> fakeBody) (figureWith 30) (img <> fakeFontFiles)
      b <- miniPdf fakeProvider True (captionStyle "font = \"body\"\nsize = \"10pt\"\n" <> fakeBody) (figureWith 30) (img <> fakeFontFiles)
      c1 <- BS.concat <$> inflateAll a
      c2 <- BS.concat <$> inflateAll b
      drawnGlyphs c1 @?= drawnGlyphs c2,
    testCase "a caption based on another style takes its size" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (horizontal24 <> "\n[paragraph-styles.note]\nsize = \"8pt\"\n\n[paragraph-styles.caption]\nbased-on = \"note\"\n") (figureWith 10) img
      (_, pf, _, _) <- theFigure pl
      pfCaptionSize pf @?= 8 * pt,
    testCase "the indent of the caption style does not move the caption" $ do
      img <- tinyImage
      a <- miniPdf fakeProvider True horizontal24 (figureWith 30) img >>= fmap BS.concat . inflateAll
      b <- miniPdf fakeProvider True (captionStyle "first-line-indent = \"1zw\"\n") (figureWith 30) img >>= fmap BS.concat . inflateAll
      [d | d <- drawnGlyphs a, dGlyph d == fromEnum '甲'] @?= [d | d <- drawnGlyphs b, dGlyph d == fromEnum '甲'],
    testCase "small captions: parallel and sequential, and two builds, give the same bytes" $ do
      img <- tinyImage
      let style = captionStyle "size = \"7pt\"\n"
          source = wrapped "start" "4zw" <> longPara 20 <> figureWith 60
      a <- miniPdf fakeProvider True style source img
      b <- miniPdf fakeProvider False style source img
      c <- miniPdf fakeProvider True style source img
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "with real fonts the caption font holds the caption's glyphs only" $ do
      (sans, serif) <- realLatinFonts
      img <- tinyImage
      let style = horizontal24 <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.caption]\nlatin = \"fonts/serif.ttf\"\n\n[paragraph-styles.caption]\nfont = \"caption\"\n"
      pdf <- miniPdf realProvider True style "@figure images/tiny.jpg alt=\"t\"\n  Zebra\n\nquick\n" (img <> [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)])
      cmaps <- filter ("beginbfchar" `BS.isInfixOf`) <$> inflateAll pdf
      length cmaps @?= 2
      assertBool "caption glyphs only in one font" (any (\c -> "<005a>" `BS.isInfixOf` c && not ("<0071>" `BS.isInfixOf` c)) cmaps)
      assertBool "body glyphs only in the other" (any (\c -> "<0071>" `BS.isInfixOf` c && not ("<005a>" `BS.isInfixOf` c)) cmaps)
      qpdfCheck pdf,
    testCase "HTML: figcaption takes the caption's font and size relative to the grid" $ do
      let css keys = withSystemTempDirectory "golem-mini" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n")
            BS.writeFile (tmp </> "style.toml") (horizontalStyle <> "\n[fonts.caption]\nlatin = \"fonts/c.otf\"\n\n[paragraph-styles.caption]\n" <> keys)
            BS.writeFile (tmp </> "a.gm") "x\n"
            createDirectoryIfMissing True (tmp </> "fonts")
            BS.writeFile (tmp </> "fonts/c.otf") "fake"
            r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            TIO.readFile (tmp </> "build/html/style.css")
      a <- css "font = \"caption\"\nsize = \"8pt\"\n"
      assertBool (T.unpack a) ("figcaption { font-family: \"golem-caption-latin\", serif; font-size: 0.8em; }" `T.isInfixOf` a)
      b <- css "size = \"0.85zw\"\n"
      assertBool (T.unpack b) ("figcaption { font-size: 0.85em; }" `T.isInfixOf` b),
    testCase "cssFontSize: relative to an absolute grid, pt without a page" $ do
      let styleOf src = either (\ds -> assertFailure (show ds) >> error "unreachable") pure (parseStyle (FileId 0) src)
          dim t = fromMaybe (Abs 0) (parseDim t)
      s13 <- styleOf "[page]\nsize = \"B6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 30\nlines = 20\nline-pitch = \"22H\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n"
      cssFontSize s13 (dim "11Q") @?= "0.846em"
      cssFontSize s13 (dim "0.85zw") @?= "0.85em"
      none <- styleOf ""
      cssFontSize none (dim "9pt") @?= "9pt"
  ]

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
      qpdfCheck a,
    testCase "the roles the PDF uses include the sidenote's (golem-driver ADR 0011)" $ do
      s <- either (assertFailure . show) pure (parseStyle (FileId 0) "[fonts.body]\nja = \"b.otf\"\n\n[fonts.heading]\nja = \"h.otf\"\n\n[paragraph-styles.sidenote]\nfont = \"heading\"\n")
      usedRoles s @?= ["body", "heading"],
    testCase "a sidenote role sets the note and its number; the text and its marker stay in the body" $ do
      content <- miniPdf fakeProvider True (sidenoteStyleWith "font = \"heading\"\n" <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n") "本文[sidenote: 注]。\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          fontsOf c sz = nub [dFont d | d <- ds, dGlyph d == fromEnum c, dSize d == sz]
      fontsOf '注' "8" @?= fontsOf '1' "8"
      assertBool "drawn" (not (null (fontsOf '注' "8")))
      assertBool "the note's role" (fontsOf '注' "8" /= fontsOf '本' "10")
      nub [dFont d | d <- ds, dGlyph d == fromEnum '1', dSize d /= "8"] @?= fontsOf '本' "10",
    testCase "a sidenote role measures the note in its own font" $ do
      let note = "本文[sidenote: abcdefghijklmnopqrstuvwxyz]。\n"
          linesOf style = do
            (_, pl) <- layoutOk style note fakeFontFiles
            pure (sum [length (psLines ps) | (_, ps) <- sidenotesOf pl])
      plain <- linesOf (sidenoteStyle <> fakeBody)
      wide <- linesOf (sidenoteStyleWith "font = \"wide\"\n" <> fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n")
      assertBool (show (plain, wide)) (wide > plain),
    testCase "naming the body role, or an indent, changes nothing" $ do
      let source = "本文[sidenote: 傍注の本文はここにある。]。\n"
      a <- miniPdf fakeProvider True (sidenoteStyle <> fakeBody) source fakeFontFiles
      b <- miniPdf fakeProvider True (sidenoteStyleWith "font = \"body\"\n" <> fakeBody) source fakeFontFiles
      c <- miniPdf fakeProvider True (sidenoteStyleWith "first-line-indent = \"1zw\"\n" <> fakeBody) source fakeFontFiles
      -- style.toml is an input of the instance ID (golem-pdf ADR 0004), so the trailer differs
      let withoutId pdf = fst (BS.breakSubstring "/ID [" pdf)
      withoutId a @?= withoutId b
      withoutId a @?= withoutId c,
    testCase "a character style inside a sidenote takes its own role" $ do
      content <- miniPdf fakeProvider True (sidenoteStyle <> fakeBody <> "\n[fonts.wide]\nja = \"fonts/w.otf\"\n\n[character-styles.bold]\nfont = \"wide\"\n") "本文[sidenote: 注の[bold: 語]。]。\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          fontsOf c = nub [dFont d | d <- ds, dGlyph d == fromEnum c]
      assertBool "the bold role" (fontsOf '語' /= fontsOf '注')
      fontsOf '注' @?= fontsOf '本',
    testCase "sidenote roles: parallel and sequential, and two builds, give the same bytes" $ do
      let style = sidenoteStyleWith "font = \"heading\"\n" <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n"
          files = fakeFontFiles
          source = fillers 5 <> "一" <> twoLineNote <> "\n\n二" <> twoLineNote <> "\n\n" <> longPara 20
      a <- miniPdf fakeProvider True style source files
      b <- miniPdf fakeProvider False style source files
      c <- miniPdf fakeProvider True style source files
      a @?= b
      a @?= c
      qpdfCheck a,
    testCase "with real fonts the sidenote font holds the sidenote's glyphs only" $ do
      (sans, serif) <- realLatinFonts
      let style = sidenoteStyleWith "font = \"note\"\n" <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\n\n[fonts.note]\nlatin = \"fonts/serif.ttf\"\n"
      pdf <- miniPdf realProvider True style "quick[sidenote: Zebra] quick\n" [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
      cmaps <- filter ("beginbfchar" `BS.isInfixOf`) <$> inflateAll pdf
      length cmaps @?= 2
      assertBool "sidenote glyphs only in one font" (any (\c -> "<005a>" `BS.isInfixOf` c && not ("<0071>" `BS.isInfixOf` c)) cmaps)
      assertBool "body glyphs only in the other" (any (\c -> "<0071>" `BS.isInfixOf` c && not ("<005a>" `BS.isInfixOf` c)) cmaps)
      qpdfCheck pdf,
    testCase "HTML: .sidenote takes the sidenote's font and size" $ do
      let css keys = withSystemTempDirectory "golem-mini" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n")
            BS.writeFile (tmp </> "style.toml") (horizontalStyle <> "\n[fonts.note]\nlatin = \"fonts/n.otf\"\n\n[paragraph-styles.sidenote]\n" <> keys)
            BS.writeFile (tmp </> "a.gm") "x\n"
            createDirectoryIfMissing True (tmp </> "fonts")
            BS.writeFile (tmp </> "fonts/n.otf") "fake"
            r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            TIO.readFile (tmp </> "build/html/style.css")
      a <- css "font = \"note\"\nsize = \"8pt\"\n"
      assertBool (T.unpack a) (".sidenote { font-family: \"golem-note-latin\", serif; font-size: 0.8em; }" `T.isInfixOf` a)
      b <- css "size = \"8pt\"\n"
      assertBool (T.unpack b) (".sidenote { font-size: 0.8em; }" `T.isInfixOf` b)
      c <- css "font = \"note\"\n"
      assertBool (T.unpack c) (".sidenote { font-family: \"golem-note-latin\", serif; font-size: 0.85em; }" `T.isInfixOf` c)
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
      (Just book, []) -> layoutPages fakeProvider (PdfInput tmp (evProject e) (evStyle e) book False [] bib Nothing)
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

-- | A line of one box of a width (a page number in the tests of tocPage).
oneBoxLine :: Integer -> Line
oneBoxLine w = Line [Box w (BoxContent "1" False 0 0 0 (plainLook "body" (10 * pt)) 0 0)] 0 w 0 (0, 0) False (0, 0)

-- | fs = 10pt, measure = 120pt, W = 15pt, g = 5pt, u = 10pt.
tocGeom :: Bool -> TocGeometry
tocGeom leaders = TocGeometry (120 * pt) (15 * pt) (5 * pt) (10 * pt) leaders (plainLook "body" (10 * pt))

leaderCount :: TocPage -> Int
leaderCount tp = length [() | Box {} <- lineItems (tpLeader tp)]

-- | Twelve chapters of a few lines each, after a table of contents.
twelveChapters :: T.Text
twelveChapters = "@toc\n\n" <> T.concat ["# 章" <> T.singleton k <> "\n\n" <> fillers 3 | k <- "あいうえおかきくけこさし"]

-- | The page number at the end of a line of the table of contents.
trailingNumber :: T.Text -> Maybe Int
trailingNumber l = case T.takeWhileEnd (`elem` ['0' .. '9']) l of
  ds | not (T.null ds) -> Just (read (T.unpack ds))
  _ -> Nothing

-- | The lines of the table of contents of a book's pages: the lines with a leader.
tocLinesOf :: [[T.Text]] -> [T.Text]
tocLinesOf pages = [l | ls <- pages, l <- ls, "…" `T.isInfixOf` l]

-- | The first page (from 1) with a line that ends with a text and is not in the table of contents.
pageWith :: [[T.Text]] -> T.Text -> Maybe Int
pageWith pages t = case [n | (n, ls) <- zip [1 ..] pages, any (\l -> t `T.isSuffixOf` l && not ("…" `T.isInfixOf` l)) ls] of
  (n : _) -> Just n
  [] -> Nothing

tocTests :: [TestTree]
tocTests =
  [ testCase "tocPage: leaders end at the same place; the number ends at the measure" $ do
      let at e = tocPage (tocGeom True) (e * pt) (oneBoxLine (10 * pt))
          a = at 60
      leaderCount a @?= 3
      tpLeaderStart a @?= 70 * pt
      tpNumberStart a @?= 110 * pt
      let b = at 62
      tpLeaderStart b @?= 70 * pt
      tpLeaderStart b + toInteger (leaderCount b) * 10 * pt @?= 100 * pt
      let c = at 85
      leaderCount c @?= 1
      tpLeaderStart c @?= 90 * pt,
    testCase "tocPage: a number wider than W, an overfull title, no leaders" $ do
      let wide = tocPage (tocGeom True) (60 * pt) (oneBoxLine (20 * pt))
      tpNumberStart wide @?= 100 * pt
      tpLeaderStart wide + toInteger (leaderCount wide) * 10 * pt @?= 95 * pt
      let over = tocPage (tocGeom True) (118 * pt) (oneBoxLine (10 * pt))
      tpNumberStart over @?= 123 * pt
      leaderCount over @?= 0
      forM_ [60, 62, 85, 118] $ \e -> do
        let none = tocPage (tocGeom False) (e * pt) (oneBoxLine (10 * pt))
            dots = tocPage (tocGeom True) (e * pt) (oneBoxLine (10 * pt))
        leaderCount none @?= 0
        tpNumberStart none @?= tpNumberStart dots,
    testCase "toc lines are shortened by the reserve and indented by level" $ do
      (_, ls) <- verseLines horizontalStyle "@toc depth=2\n\n# 一\n\n本文。\n\n## 節\n\n本文。\n\n# 二\n\n本文。\n"
      take 3 ls @?= [(85 * pt, 0), (75 * pt, 10 * pt), (85 * pt, 0)],
    testCase "a toc over three pages shows the page of each heading" $ do
      r <- pagesMini "" fiveLines twelveChapters [] Map.empty
      pages <- either (assertFailure . show) pure r
      let tocs = tocLinesOf pages
      length tocs @?= 12
      [n | (n, ls) <- zip [1 :: Int ..] pages, any ("…" `T.isInfixOf`) ls] @?= [1, 2, 3]
      forM_ (zip tocs "あいうえおかきくけこさし") $ \(l, k) ->
        trailingNumber l @?= pageWith pages ("章" <> T.singleton k),
    testCase "the toc lines do not depend on the page numbers" $ do
      (_, first) <- verseLines fiveLines twelveChapters
      (_, pl) <- layoutOk fiveLines twelveChapters []
      [(lineTarget (slLine sl), slIndent sl) | sl <- Map.elems (plLines pl)] @?= first
      let boxesOf sl = [bcText c | Box _ c <- lineItems (slLine sl)]
      assertBool "toc lines" (not (any (any ("…" `T.isInfixOf`) . boxesOf) (take 12 (Map.elems (plLines pl))))),
    testCase "a heading that moves from page 9 to 10 shows 10 and converges" $ do
      r <- pagesMini "" fiveLines ("@toc\n\n" <> fillers 44 <> "# 終\n\n本文。\n") [] Map.empty
      pages <- either (assertFailure . show) pure r
      pageWith pages "終" @?= Just 10
      map trailingNumber (tocLinesOf pages) @?= [Just 10],
    testCase "a recto heading after a blank page shows its odd page" $ do
      r <- pagesMini "" (fiveLines <> "\n[headings.1]\npage-break = \"recto\"\n") "@toc\n\n# 一\n\n本文。\n\n# 二\n\n本文。\n" [] Map.empty
      pages <- either (assertFailure . show) pure r
      map trailingNumber (tocLinesOf pages) @?= [Just 3, Just 5]
      pageWith pages "一" @?= Just 3
      pages !! 1 @?= [],
    testCase "every toc entry within the depth has a page" $ do
      (_, pl) <- layoutOk fiveLines "@toc depth=2\n\n# 一\n\n## 節\n\n### 項\n\n本文。\n\n# 二\n\n## 節二\n\n本文。\n" []
      Map.size (plTocPages pl) @?= 4,
    testCase "leader = none draws no leader but the page" $ do
      r <- pagesMini "" (fiveLines <> "\n[toc]\nleader = \"none\"\n") "@toc\n\n# 一\n\n本文。\n" [] Map.empty
      pages <- either (assertFailure . show) pure r
      case concat pages of
        (l : _) -> do
          assertBool (show l) (not ("…" `T.isInfixOf` l))
          trailingNumber l @?= Just 1
        [] -> assertFailure "no lines",
    testCase "vertical toc page numbers are kanji" $ do
      r <- pagesMini "" pdfStyle ("@toc\n\n" <> fillers 34 <> "# 終\n\n本文。\n") [] Map.empty
      pages <- either (assertFailure . show) pure r
      case tocLinesOf pages of
        [l] -> assertBool (show l) ("…三" `T.isSuffixOf` l)
        other -> assertFailure (show other),
    testCase "toc page numbers end at the right edge of the type area" $ do
      let source = "@toc depth=2\n\n# 一\n\n## 節\n\n本文。\n\n# 二\n\n本文。\n"
          style = horizontalStyle <> "\n[headings.1]\nnumber = \"{n:kanji}\"\n\n[headings.2]\nnumber = \"{n:kanji}\"\n"
      content <- miniPdf fakeProvider True style source [] >>= fmap BS.concat . inflateAll
      geom <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 style) >>= pageGeometry)
      let ta = typeAreaFor geom 1
          ones = [d | d <- drawnGlyphs content, dGlyph d == fromEnum '1']
      length ones @?= 3
      map dX ones @?= replicate 3 (TE.encodeUtf8 (spToPt (rectX ta + 115 * pt))),
    testCase "a book with a toc: parallel and sequential, and two builds, give the same bytes" $ do
      a <- miniPdf fakeProvider True fiveLines twelveChapters []
      b <- miniPdf fakeProvider False fiveLines twelveChapters []
      c <- miniPdf fakeProvider True fiveLines twelveChapters []
      a @?= b
      a @?= c
      qpdfCheck a
  ]

-- | Builds a one-chapter project to HTML and returns the chapter and the style sheet.
htmlMini :: BS.ByteString -> T.Text -> IO (T.Text, T.Text)
htmlMini style source = withSystemTempDirectory "golem-html" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n")
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  page <- TIO.readFile (tmp </> "build/html/a.xhtml")
  css' <- TIO.readFile (tmp </> "build/html/style.css")
  pure (page, css')

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
      geom <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 horizontalStyle) >>= pageGeometry)
      let ta = typeAreaFor geom 1
          xsOf ps = [TE.encodeUtf8 (spToPt (rectX ta + p)) | p <- ps]
      spaced <- drawnAt "1:2:1"
      centred <- drawnAt "center"
      [spaced] @?= map xsOf (expected Align121)
      [centred] @?= map xsOf (expected AlignCenter)
      assertBool "different" (spaced /= centred),
    testCase "a ruby at the line start does not stick out of the type area" $ do
      let source = T.replicate 12 "あ" <> "[ruby: 字|あいう]の" <> T.replicate 6 "あ" <> "\n"
      content <- miniPdf fakeProvider True horizontalStyle source [] >>= fmap BS.concat . inflateAll
      geom <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 horizontalStyle) >>= pageGeometry)
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
  [ testCase "a missing font does not stop the evaluation" $ withStyleProject missingStyle [] $ \tmp -> do
      e <- evaluateProject Dev tmp
      either (assertFailure . show) (const (pure ())) e,
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
      e <- evaluateProject Dev tmp >>= either (assertFailure . show) pure
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
        codeSeverities r @?= []
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

-- * golem explain (golem-cli ADR 0005)

explainTests :: TestTree
explainTests =
  testGroup
    "explanations of the diagnostic codes (golem-cli ADR 0005)"
    [ testGroup
        "docs/diagnostics.md covers the codes in the sources"
        [ testCase "every code in the sources is in the catalog and in use" $ do
            used <- sourceCodes
            assertBool "no code found in the sources" (not (null used))
            case [c | c <- used, fmap exStatus (Map.lookup c catalog) /= Just InUse] of
              [] -> pure ()
              missing -> assertFailure ("codes without an explanation in use: " <> unwords (map T.unpack missing)),
          testCase "every code in use is in the sources" $ do
            used <- sourceCodes
            case [c | (c, e) <- Map.toList catalog, exStatus e == InUse, c `notElem` used] of
              [] -> pure ()
              unused -> assertFailure ("codes in use but not in the sources (make them retired): " <> unwords (map T.unpack unused)),
          testCase "no retired code is in the sources" $ do
            used <- sourceCodes
            [c | (c, e) <- Map.toList catalog, exStatus e == Retired, c `elem` used] @?= [],
          testCase "the profile-dependent codes, and only they, are a warning in dev and an error in prod" $ do
            let dependent = [c | DiagnosticCode c <- profileDependentCodes]
                isDependent e = "- 重大度: dev では警告、prod ではエラー" `elem` T.lines (exBody e)
            assertBool "some profile-dependent codes" (not (null dependent))
            sort [c | (c, e) <- Map.toList catalog, isDependent e] @?= sort dependent,
          testCase "the catalog has G0244 retired" $
            fmap exStatus (lookupExplanation "G0244") @?= Just Retired
        ],
      testGroup
        "the form of the document"
        [ testCase "two good sections give their titles, statuses and bodies" $
            case parseCatalog (T.unlines (preamble <> inUse "G0101" <> retired "G0244")) of
              Left e -> assertFailure (T.unpack e)
              Right es -> do
                map exCode es @?= ["G0101", "G0244"]
                map exTitle es @?= ["G0101 の題", "G0244 の題"]
                map exStatus es @?= [InUse, Retired]
                map exBody es @?= [T.intercalate "\n" (dropLast (inUse "G0101")), T.intercalate "\n" (dropLast (retired "G0244"))],
          bad "no 直し方" (preamble <> inUse "G0101" <> without "### 直し方" (inUse "G0102")) "## G0102",
          bad "no title" (preamble <> inUse "G0101" <> without "G0102 の題" (inUse "G0102")) "## G0102",
          bad "no status" (preamble <> inUse "G0101" <> without "- 状態: 使用中" (inUse "G0102")) "## G0102",
          bad "a bad severity" (preamble <> inUse "G0101" <> map (\l -> if l == "- 重大度: エラー" then "- 重大度: 致命的" else l) (inUse "G0102")) "- 重大度: 致命的",
          bad "out of order" (preamble <> inUse "G0102" <> inUse "G0101") "## G0101",
          bad "a code twice" (preamble <> inUse "G0101" <> inUse "G0101") "## G0101",
          testCase "a retired section without 主な原因 is accepted" $
            fmap (map exCode) (parseCatalog (T.unlines (preamble <> retired "G0244"))) @?= Right ["G0244"]
        ],
      testGroup
        "lookup, hint and URL"
        [ testCase "lookupExplanation ignores case" $ do
            fmap exCode (lookupExplanation "g0117") @?= Just "G0117"
            fmap exCode (lookupExplanation "G0117") @?= Just "G0117"
            fmap exCode (lookupExplanation "G9999") @?= Nothing,
          testCase "explainHint names the smallest documented code, once" $ do
            let d c = diagnostic c Error (SrcSpan (FileId 0) 0 0) "m"
            explainHint [d "G0403", d "G0117", d "X001"] @?= "コードの説明は golem explain <コード> で表示できます（例: golem explain G0117）"
            explainHint [d "X001"] @?= ""
            explainHint [] @?= "",
          testCase "codeDescriptionUrl points at the section on main" $ do
            codeDescriptionUrl (DiagnosticCode "G0117") @?= Just "https://github.com/tett23/golem/blob/main/docs/diagnostics.md#g0117"
            codeDescriptionUrl (DiagnosticCode "X001") @?= Nothing
        ]
    ]
  where
    preamble = ["# 診断のコード", "", "前書き。", "", "## 番号の区分", "", "表。", ""]
    inUse c = ["## " <> c, "", c <> " の題", "", "- 重大度: エラー", "- 状態: 使用中", "", "### 意味", "", "意味。", "", "### 主な原因", "", "- 原因。", "", "### 直し方", "", "直す。", ""]
    retired c = ["## " <> c, "", c <> " の題", "", "- 重大度: エラー", "- 状態: 廃止", "", "### 意味", "", "廃止した。", "", "### 直し方", "", "代わりに書く。", ""]
    dropLast xs = take (length xs - 1) xs
    without l = filter (/= l)
    bad name ls at = testCase (name <> " is rejected with the line number") $
      case parseCatalog (T.unlines ls) of
        Right _ -> assertFailure "accepted"
        Left e -> do
          let n = last [i | (i, l) <- zip [1 :: Int ..] ls, l == at]
          assertBool (T.unpack e) (T.pack (show n <> " 行目") `T.isInfixOf` e)

{- | The codes in the sources: the strings @"G@, four digits and @"@ in the
Haskell files under ../*/src and ../golem-cli/app (not the tests, which
write codes to cause errors).
-}
sourceCodes :: IO [T.Text]
sourceCodes = do
  pkgs <- listDirectory ".."
  dirs <- filterM doesDirectoryExist ([".." </> p </> "src" | p <- pkgs] <> ["../golem-cli/app"])
  files <- concat <$> mapM haskellFiles dirs
  codes <- mapM (fmap quotedCodes . TIO.readFile) files
  pure (sort (nub (concat codes)))

haskellFiles :: FilePath -> IO [FilePath]
haskellFiles dir = do
  entries <- map (dir </>) <$> listDirectory dir
  dirs <- filterM doesDirectoryExist entries
  nested <- concat <$> mapM haskellFiles dirs
  pure ([e | e <- entries, ".hs" `isSuffixOf` e, e `notElem` dirs] <> nested)

quotedCodes :: T.Text -> [T.Text]
quotedCodes src =
  [ code
  | (_, rest) <- T.breakOnAll "\"G" src,
    let code = T.take 5 (T.drop 1 rest),
    T.length code == 5,
    T.all isDigit (T.drop 1 code),
    T.take 1 (T.drop 6 rest) == "\""
  ]
