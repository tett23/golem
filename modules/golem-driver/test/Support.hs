-- | Helpers shared by the topic modules of the golem-driver tests.
module Support where

import Codec.Compression.Zlib qualified as Z
import Control.Exception (SomeException, evaluate, try)
import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Char (isDigit)
import Data.IORef (IORef, modifyIORef')
import Data.List (isSuffixOf, nub, sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (inlineText)
import Golem.Doc.Bibliography (EntryPart)
import Golem.Doc.IR (Inline, InlineF (..))
import Golem.Driver
import Golem.Driver.Pdf (ClusterPart (..), PdfInput (..), PdfLayout (..), PlacedFigure (..), SetLine (..), Shaped (..), Shaping (..), flowLines, layoutPages, layoutPdf, runningHeads)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (Flow (..), PageOut (..), Slotted (..))
import Golem.LayoutSpec (PageGeometry (..), pageGeometry)
import Golem.Pdf (Font (..), FontProgram (..))
import Golem.Project (Project (..), ProjectFailure (..))
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Golem.TestSupport.ExternalTool (optionalTool)
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, findExecutable, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

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

uuid0 :: T.Text
uuid0 = "00000000-0000-4000-8000-000000000000"

golden :: String -> FilePath -> TestTree
golden = goldenIn Dev

-- | The golden of one output file of the fixture built with a profile.
goldenIn :: Profile -> String -> FilePath -> TestTree
goldenIn profile name out = goldenVsString name ("test/golden/" <> name) (buildAndRead profile out)

{- | A file prod builds to the same bytes as dev: the golden of dev fixes
both, and this asserts that it may (docs/adr/0064).
-}
sameInProd :: FilePath -> TestTree
sameInProd out = testCase ("prod builds " <> out <> " as dev does") $ do
  dev <- buildAndRead Dev out
  prod <- buildAndRead Prod out
  prod @?= dev

-- | A file prod builds differently from dev (docs/adr/0064).
differsInProd :: FilePath -> TestTree
differsInProd out = testCase ("prod builds " <> out <> " differently from dev") $ do
  dev <- buildAndRead Dev out
  prod <- buildAndRead Prod out
  assertBool "dev and prod differ" (prod /= dev)

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
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case evBook e of
      Nothing -> assertFailure (show (map diagCode (evDiagnostics e)))
      Just book -> do
        r <- flowLines (FontProvider (\_ _ _ _ -> pure (Right fakeFonts))) (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing Map.empty (chapterMasters (evProject e)) (evStyleFile e) Map.empty)
        either (assertFailure . show) pure r

-- | horizontalStyle with 30 characters a line (300pt), and more.
horizontal30 :: BS.ByteString -> BS.ByteString
horizontal30 extra = replaceIn "characters = 12" "characters = 30" horizontalStyle <> extra

-- | The text of each line of a layout, in order.
lineTexts :: PdfLayout -> [T.Text]
lineTexts pl = [T.concat [bcText c | Box _ c <- lineItems (slLine sl)] | sl <- Map.elems (plLines pl)]

-- | The text of every line of every page.
listPages :: BS.ByteString -> T.Text -> IO [T.Text]
listPages style src = pagesMini "" style src [] Map.empty >>= either (assertFailure . show) (pure . concat)

-- | A project of chapters (in order) and other files, with a style.toml.
withChapters :: BS.ByteString -> [(FilePath, T.Text)] -> [(FilePath, T.Text)] -> (FilePath -> IO a) -> IO a
withChapters style chapters = withEntries style ["\"" <> T.pack p <> "\"" | (p, _) <- chapters] chapters

-- | As withChapters, with the entries of the chapters written as TOML.
withEntries :: BS.ByteString -> [T.Text] -> [(FilePath, T.Text)] -> [(FilePath, T.Text)] -> (FilePath -> IO a) -> IO a
withEntries style entries chapters others k = withSystemTempDirectory "golem-chapters" $ \tmp -> do
  manifest <- TIO.readFile (fixture </> "manifest.toml")
  TIO.writeFile (tmp </> "manifest.toml") ("chapters = [" <> T.intercalate ", " entries <> "]\n" <> T.dropWhile (/= '\n') manifest)
  BS.writeFile (tmp </> "style.toml") style
  forM_ (chapters <> others) $ \(p, src) -> TIO.writeFile (tmp </> p) src
  k tmp

-- | The rules of a style sheet that start with a selector.
rulesOf :: T.Text -> T.Text -> [T.Text]
rulesOf sel css = [l | l <- T.lines css, (sel <> " {") `T.isPrefixOf` l]

-- | The FileId of a file the build's diagnostics may point at.
sourceFileId :: BuildResult -> FilePath -> Maybe FileId
sourceFileId r path = lookup path [(siPath si, fid) | (fid, si) <- Map.toList (brSources r)]

-- | B6, vertical, right binding, as in specifications.md.
pdfStyle :: BS.ByteString
pdfStyle =
  BS.concat
    [ "[page]\nsize = \"B6\"\nbinding = \"right\"\nwriting-mode = \"vertical\"\n\n",
      "[page.grid]\nfont-size = \"13Q\"\ncharacters = 42\nlines = 16\nline-pitch = \"22H\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n",
      -- UTF-8: a literal ByteString keeps only the low byte of each character
      TE.encodeUtf8 "[headings.1]\nnumber = \"第{n:kanji}章\"\n\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
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
buildMini fonts parallel style source files = do
  (errs, pdf) <- buildMiniErrors fonts parallel style source files
  pure (map diagCode errs, pdf)

{- | Writes files into a directory, making the folders on their paths; a
later file of the same path replaces an earlier one.
-}
writeFiles :: FilePath -> [(FilePath, BS.ByteString)] -> IO ()
writeFiles dir = mapM_ (\(to, bytes) -> createDirectoryIfMissing True (takeDirectory (dir </> to)) >> BS.writeFile (dir </> to) bytes)

-- | 'writeFiles' with texts, written in UTF-8.
writeTexts :: FilePath -> [(FilePath, T.Text)] -> IO ()
writeTexts dir = writeFiles dir . map (fmap TE.encodeUtf8)

{- | Writes a one-chapter project into a directory: the manifest,
style.toml with 'withBodyFont', the chapter a.gm, then the files of the
body font and the other files.
-}
writeProject :: FilePath -> BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO ()
writeProject dir manifest style source files = do
  BS.writeFile (dir </> "manifest.toml") manifest
  BS.writeFile (dir </> "style.toml") (withBodyFont style)
  BS.writeFile (dir </> "a.gm") (TE.encodeUtf8 source)
  writeFiles dir (bodyFontFiles style <> files)

-- | 'buildMini' with the errors themselves.
buildMiniErrors :: FontProvider -> Bool -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO ([Diagnostic], Maybe BS.ByteString)
buildMiniErrors fonts parallel style source files = withSystemTempDirectory "golem-mini" $ \tmp -> do
  writeProject tmp miniManifest style source files
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fonts, optParallel = parallel}
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  pure (filter isError (brDiagnostics r), pdf)

-- | What a build of the one-chapter project left behind.
data Built = Built
  { bErrors :: ![Diagnostic],
    bSources :: !(Map.Map FileId SourceInfo),
    bPdf :: !(Maybe BS.ByteString),
    bWritten :: ![FilePath],
    bBuildDir :: !Bool
  }

buildMarksFilesWith :: T.Text -> (BuildOptions -> BuildOptions) -> Maybe BS.ByteString -> [(FilePath, BS.ByteString)] -> IO Built
buildMarksFilesWith source f style files = withSystemTempDirectory "golem-marks" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n")
  forM_ style (BS.writeFile (tmp </> "style.toml"))
  writeFiles tmp files
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  r <- build (f (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider})
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> Just <$> BS.readFile p
    _ -> pure Nothing
  dir <- doesDirectoryExist (tmp </> "build")
  pure (Built (filter isError (brDiagnostics r)) (brSources r) pdf (brWritten r) dir)

-- | The document ID and the instance ID of the trailer.
pdfIds :: BS.ByteString -> (BS.ByteString, BS.ByteString)
pdfIds pdf =
  let rest = BS.drop 6 (snd (BS.breakSubstring "/ID [<" pdf))
      (a, rest') = BS.breakSubstring ">" rest
   in (a, BC.takeWhile (/= '>') (BS.drop 3 rest'))

-- | The golem-font provider that builds use by default.
realProvider :: FontProvider
realProvider = optFonts (defaultOptions "")

fakeProvider :: FontProvider
fakeProvider = FontProvider (\_ _ _ _ -> pure (Right fakeFonts))

-- | Builds with no errors allowed and returns the PDF.
miniPdf :: FontProvider -> Bool -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO BS.ByteString
miniPdf fonts parallel style source files = do
  (errs, pdf) <- buildMini fonts parallel style source files
  assertEqual "no errors" [] errs
  maybe (assertFailure "no PDF") pure pdf

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

{- | A style with the fake body font when it names no font role, so that a
PDF test is not stopped by G08007 (golem-driver ADR 0016).
-}
withBodyFont :: BS.ByteString -> BS.ByteString
withBodyFont style
  | "[fonts." `BS.isInfixOf` style = style
  | otherwise = style <> fakeBody

-- | Writes style.toml with 'withBodyFont' and its files into a project.
writeStyleWithFont :: FilePath -> BS.ByteString -> IO ()
writeStyleWithFont tmp style = do
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeFiles tmp (bodyFontFiles style)

-- | The files 'withBodyFont' needs.
bodyFontFiles :: BS.ByteString -> [(FilePath, BS.ByteString)]
bodyFontFiles style
  | "[fonts." `BS.isInfixOf` style = []
  | otherwise = fakeFontFiles

{- | Lays out a one-chapter project with the fake fonts, as far as the
pages; the geometry comes with it.
-}
layoutMini :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO (Either [Diagnostic] (PageGeometry, PdfLayout))
layoutMini = layoutMiniWith miniManifest

-- | 'layoutMini' with another manifest.
layoutMiniWith :: BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO (Either [Diagnostic] (PageGeometry, PdfLayout))
layoutMiniWith = layoutMiniFonts fakeProvider

-- | 'layoutMiniWith' with the fonts of a provider.
layoutMiniFonts :: FontProvider -> BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO (Either [Diagnostic] (PageGeometry, PdfLayout))
layoutMiniFonts provider manifest style source files = withSystemTempDirectory "golem-layout" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  writeFiles tmp files
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> pure (Left (pfDiagnostics f))
    Right e -> case (evBook e, pageGeometry (FileId 0) False (evStyle e)) of
      _ | errs@(_ : _) <- filter isError (evDiagnostics e) -> pure (Left errs)
      (Just book, Right geom) ->
        loadFonts provider tmp (evStyleFile e) (evStyle e) [] >>= \case
          Left ds -> pure (Left ds)
          Right fonts -> do
            (_, _, bib) <- loadBibliography tmp (projectManifest (evProject e))
            fmap (geom,) <$> layoutPdf (PdfInput tmp (evProject e) (evStyle e) book False [] bib Nothing Map.empty (chapterMasters (evProject e)) (evStyleFile e) Map.empty) geom fonts
      (_, Left ds) -> pure (Left ds)
      (Nothing, _) -> pure (Left (filter isError (evDiagnostics e)))

-- | The master page of each chapter file that names one, as the driver passes it.
chapterMasters :: Project -> Map.Map FileId T.Text
chapterMasters p = Map.fromList [(fid, m) | (fid, Just m) <- projectChapters p]

{- | Lays out a project (manifest, style, sources) with the fake fonts and
returns the running head of each page and the layout (ADR 0014).
-}
layoutHeads :: BS.ByteString -> BS.ByteString -> [(FilePath, T.Text)] -> IO (Map.Map Int [T.Text], PdfLayout)
layoutHeads manifest style sources = withSystemTempDirectory "golem-heads" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") style
  writeTexts tmp sources
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, pageGeometry (FileId 0) False (evStyle e)) of
      _ | errs@(_ : _) <- filter isError (evDiagnostics e) -> assertFailure (show errs)
      (Just book, Right geom) -> do
        -- the variables of the running heads, as the driver passes them (golem-driver ADR 0022)
        let (vars, varDiags) = runningVars e
            inp = PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) vars
        assertEqual "running head variables" [] varDiags
        r <- layoutPdf inp geom fakeFonts
        case r of
          Left ds -> assertFailure (show ds)
          Right layout -> pure (runningHeads inp geom layout, layout)
      (_, Left ds) -> assertFailure (show ds)
      (Nothing, _) -> assertFailure "no book"

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

-- | horizontalStyle with a sidenote column: 6zw wide, 1zw gap, 8pt; the sidenote pitch is 12pt.
sidenoteStyle :: BS.ByteString
sidenoteStyle = sidenoteStyleWith ""

-- | sidenoteStyle with more keys for the paragraph style sidenote (golem-driver ADR 0011); [sidenotes] stays last.
sidenoteStyleWith :: BS.ByteString -> BS.ByteString
sidenoteStyleWith keys = horizontalStyle <> "\n[paragraph-styles.sidenote]\nsize = \"8pt\"\n" <> keys <> "\n[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\n"

-- | One-character paragraphs that fill grid lines.
fillers :: Int -> T.Text
fillers n = T.replicate n "あ\n\n"

-- | Byte offsets of a pattern in a source.
offsetsIn :: T.Text -> T.Text -> [Int]
offsetsIn pat src = occurrences (TE.encodeUtf8 pat) (TE.encodeUtf8 src)

-- | The text of index or bibliography inlines, page numbers as numbers.
rendered :: [Inline] -> T.Text
rendered = T.concat . map (\case Number _ n _ -> T.pack (show n); i -> inlineText i)

{- | Lays out a one-chapter project (with extra manifest lines before
[metadata]) and returns the text of the lines of each page.
-}
pagesMini :: T.Text -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> Map.Map T.Text [EntryPart] -> IO (Either [Diagnostic] [[T.Text]])
pagesMini manifestExtra style source files bib = withSystemTempDirectory "golem-pages" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 manifestExtra <> miniManifest)
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  writeFiles tmp files
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> pure (Left (pfDiagnostics f))
    Right e -> case (evBook e, filter isError (evDiagnostics e)) of
      (Just book, []) -> layoutPages fakeProvider (PdfInput tmp (evProject e) (evStyle e) book False [] bib Nothing Map.empty (chapterMasters (evProject e)) (evStyleFile e) Map.empty)
      (_, ds) -> pure (Left ds)

{- | Headings of the body size on the body grid, as before the defaults of
golem-driver ADR 0032: for the tests that are not about headings.
-}
flatHeadings :: BS.ByteString
flatHeadings = BS.concat ["\n[headings." <> BC.pack (show l) <> "]\nsize = \"1zw\"\nlines = 1\n" | l <- [1 :: Int, 2, 3]]

-- | horizontalStyle with five lines a page.
fiveLines :: BS.ByteString
fiveLines = replaceIn "lines = 30" "lines = 5" horizontalStyle

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

-- | The rules of a content stream: x, y, width, height as written.
rulesIn :: BS.ByteString -> [[BS.ByteString]]
rulesIn content = [take 4 ws | l <- BC.lines content, let ws = BC.words l, drop 4 ws == ["re", "f"]]

-- | Content streams that draw (pages), each inflated.
pageContents :: BS.ByteString -> IO [BS.ByteString]
pageContents pdf = filter (\c -> " Tf" `BS.isInfixOf` c || " re f" `BS.isInfixOf` c) <$> inflateAll pdf

ptToRational :: BS.ByteString -> Rational
ptToRational t = case BC.split '.' t of
  [i] -> fromInteger (read (BC.unpack i))
  [i, f] ->
    let sign = if "-" `BS.isPrefixOf` i then -1 else 1
        whole = abs (read (BC.unpack i) :: Integer)
     in sign * (fromInteger whole + fromInteger (read (BC.unpack f)) / 10 ^ BS.length f)
  _ -> 0

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
    { lfAdvance = advOf . shRole,
      lfWordAdvance = \s -> sum . map (advOf (shRole s)) . T.unpack,
      lfPairKern = \_ _ _ -> 0,
      lfCode = \_ g -> g,
      lfShape = \s t -> [Shaped (faceOf (shRole s)) (fromEnum c `mod` 65536) (advOf (shRole s) c) (T.singleton c) False i (0, 0) ClusterWhole | (i, c) <- zip [0 ..] (T.unpack t)],
      lfEmBoxCentral = const (38 / 100),
      lfFaceFile = const ("fonts/b.otf", "truetype"),
      lfInkBox = \_ _ -> Just (1 / 10, -(1 / 10), 9 / 10, 8 / 10),
      lfEmbed = \_ vertical used ->
        pure . Right $
          Font "AAAAAA+Fake" (TrueTypeProgram "fake font program") vertical [(g, 1000) | (g, _) <- used] [] 880 (-120) 700 80 (0, -120, 1000, 880) 0 used ("Adobe", "Identity", 0)
    }
  where
    -- the role "wide" sets every character one em wide
    advOf role c = if role == "wide" then 1 else adv c
    faceOf = \case
      "wide" -> 2
      "heading" -> 4
      "code" -> 6
      _ -> 0
    adv c = if fromEnum c < 0x2000 then 1 / 2 else 1

{- | qpdf --check accepts the PDF. Where qpdf is not installed the check is
left out of the test that calls it, and 'qpdfInstalled' reports the SKIP;
with GOLEM_REQUIRE_EXTERNAL_TOOLS=1 (CI) the test fails instead.
-}
qpdfCheck :: BS.ByteString -> IO ()
qpdfCheck pdf = do
  qpdf <- optionalTool "qpdf" (findExecutable "qpdf")
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

countingFonts :: IORef Int -> FontProvider
countingFonts ref = FontProvider (\_ _ _ _ -> modifyIORef' ref (+ 1) >> pure (Right fakeFonts))

notoBytes :: IO BS.ByteString
notoBytes = BS.readFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"

-- | The fonts of the kanikosen fixture (Noto Serif JP), loaded by golem-font.
notoFonts :: IO LoadedFonts
notoFonts = do
  src <- TIO.readFile "test/fixtures/kanikosen/style.toml"
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) src)
  loadFonts realProvider "test/fixtures/kanikosen" (FileId 0) style [] >>= either (assertFailure . show) pure

-- * notices (golem-syntax ADR 0002)

-- | What a build of a project left: the diagnostics and the files written.
data Notified = Notified
  { nDiagnostics :: ![Diagnostic],
    -- | the files written, by their paths under build/
    nOutputs :: ![(FilePath, BS.ByteString)]
  }

-- | Builds a project of the given files with the options.
buildNotified :: [(FilePath, BS.ByteString)] -> (BuildOptions -> BuildOptions) -> IO Notified
buildNotified files f = withSystemTempDirectory "golem-notice" $ \tmp -> do
  writeFiles tmp files
  r <- build (f (defaultOptions tmp) {optFonts = fakeProvider})
  outs <- forM (sort (brWritten r)) $ \p -> (drop (length (tmp </> "build/")) p,) <$> BS.readFile p
  pure (Notified (brDiagnostics r) outs)

-- | horizontalStyle in two columns two em apart (docs/adr ADR 0018).
horizontal2 :: BS.ByteString
horizontal2 = replaceIn "columns = 1" "columns = 2\ncolumn-gap = \"2zw\"" horizontalStyle

-- | The text of a set line.
setLineText :: SetLine -> T.Text
setLineText sl = T.concat [bcText c | Box _ c <- lineItems (slLine sl)]

-- | The files of a build directory and their bytes, by path.
buildFiles :: FilePath -> IO (Map.Map FilePath BS.ByteString)
buildFiles dir = do
  entries <- listDirectory dir
  maps <- mapM one entries
  pure (Map.unions maps)
  where
    one e = do
      isDir <- doesDirectoryExist (dir </> e)
      if isDir
        then Map.mapKeys (e </>) <$> buildFiles (dir </> e)
        else Map.singleton e <$> BS.readFile (dir </> e)

-- | The path of the file a diagnostic is in and where it starts.
whereIs :: Built -> Diagnostic -> (Maybe FilePath, Int)
whereIs b d = (fmap siPath (Map.lookup (spanFile (diagSpan d)) (bSources b)), spanStart (diagSpan d))

-- | The diagnostics of one code.
diagnosticsOf :: T.Text -> [Diagnostic] -> [Diagnostic]
diagnosticsOf c ds = [d | d <- ds, diagCode d == DiagnosticCode c]

-- | The errors of one code.
ofCode :: T.Text -> Built -> [Diagnostic]
ofCode c = diagnosticsOf c . bErrors

{- | A diagnostic as its code, message, file and span, so that a test
compares all of them at once.
-}
described :: Diagnostic -> (T.Text, T.Text, FileId, Int, Int)
described d =
  let DiagnosticCode c = diagCode d
      sp = diagSpan d
   in (c, diagMessage d, spanFile sp, spanStart sp, spanEnd sp)

-- | The diagnostics of a layout that failed, described; a layout that succeeded has none.
layoutErrors :: Either [Diagnostic] a -> [(T.Text, T.Text, FileId, Int, Int)]
layoutErrors = either (map described) (const [])

-- ------------------------------------------------------------------ the objects of a PDF (docs/adr ADR 0076)

-- | A value of a PDF object, as far as the tests read one.
data PdfValue
  = PdfDict [(BS.ByteString, PdfValue)]
  | PdfArray [PdfValue]
  | PdfRef Int
  | PdfAtom BS.ByteString
  deriving stock (Eq, Show)

{- | The values of the objects of a PDF without object streams, by number:
what follows @N 0 obj@, up to the stream or @endobj@. Golem writes no
object streams, and @qpdf --qdf --object-streams=disable@ writes none
either; the stream data is not read.
-}
pdfObjects :: BS.ByteString -> Map.Map Int PdfValue
pdfObjects pdf = Map.fromList (go pdf)
  where
    go b = case BS.breakSubstring " 0 obj" b of
      (before, rest)
        | BS.null rest -> []
        | otherwise ->
            let num = BC.reverse (BC.takeWhile isDigitC (BC.reverse before))
                -- the header starts a line
                atLineStart = maybe True ((`elem` ("\r\n" :: String)) . snd) (BC.unsnoc (BS.take (BS.length before - BS.length num) before))
                body = BS.drop (BS.length " 0 obj") rest
                next = go body
             in case (BC.readInt num, pdfValue (pdfTokens (objectText body))) of
                  (Just (n, _), Just (v, _)) | not (BS.null num), atLineStart -> (n, v) : next
                  _ -> next
    isDigitC = isDigit
    -- the text of the object before its stream data, which is not PDF syntax
    objectText body = fst (BS.breakSubstring "stream" (fst (BS.breakSubstring "endobj" body)))

-- | The tokens of PDF syntax: delimiters, names, numbers, keywords, strings.
pdfTokens :: BS.ByteString -> [BS.ByteString]
pdfTokens b0 = case BC.uncons (BC.dropWhile isWhite b0) of
  Nothing -> []
  Just (c, rest)
    | c == '%' -> pdfTokens (BC.dropWhile (/= '\n') rest)
    | c == '<', Just ('<', r) <- BC.uncons rest -> "<<" : pdfTokens r
    | c == '>', Just ('>', r) <- BC.uncons rest -> ">>" : pdfTokens r
    | c == '<' -> let (h, r) = BC.break (== '>') rest in ("<" <> h <> ">") : pdfTokens (BS.drop 1 r)
    | c == '[' || c == ']' -> BC.singleton c : pdfTokens rest
    | c == '(' -> let (s, r) = literal (1 :: Int) rest "" in ("(" <> s) : pdfTokens r
    | otherwise ->
        let (t, r) = BC.break (\x -> isWhite x || x `elem` ("/<>[]()%" :: String)) rest
         in (BC.singleton c <> t) : pdfTokens r
  where
    isWhite x = x `elem` (" \t\r\n\f\0" :: String)
    literal depth b acc = case BC.uncons b of
      Nothing -> (acc, "")
      Just ('\\', r) -> literal depth (BS.drop 1 r) (acc <> "\\" <> BS.take 1 r)
      Just ('(', r) -> literal (depth + 1) r (acc <> "(")
      Just (')', r)
        | depth == 1 -> (acc <> ")", r)
        | otherwise -> literal (depth - 1) r (acc <> ")")
      Just (x, r) -> literal depth r (BC.snoc acc x)

-- | The first value of the tokens, and the tokens after it.
pdfValue :: [BS.ByteString] -> Maybe (PdfValue, [BS.ByteString])
pdfValue = \case
  "<<" : rest -> dict [] rest
  "[" : rest -> array [] rest
  a : b : "R" : rest | Just (n, "") <- BC.readInt a, Just _ <- BC.readInt b -> Just (PdfRef n, rest)
  t : rest | t `notElem` [">>", "]"] -> Just (PdfAtom t, rest)
  _ -> Nothing
  where
    dict acc = \case
      ">>" : rest -> Just (PdfDict (reverse acc), rest)
      k : rest | "/" `BS.isPrefixOf` k -> do
        (v, rest') <- pdfValue rest
        dict ((k, v) : acc) rest'
      _ -> Nothing
    array acc = \case
      "]" : rest -> Just (PdfArray (reverse acc), rest)
      ts -> do
        (v, rest) <- pdfValue ts
        array (v : acc) rest

-- | The value of a key of a dictionary, its reference followed.
pdfLookup :: Map.Map Int PdfValue -> BS.ByteString -> PdfValue -> Maybe PdfValue
pdfLookup objs key = \case
  PdfDict kvs -> resolve <$> lookup key kvs
  _ -> Nothing
  where
    resolve = \case
      PdfRef n -> Map.findWithDefault (PdfAtom "null") n objs
      v -> v

{- | The PDF as @qpdf --qdf --object-streams=disable@ writes it, where qpdf
is installed ('optionalTool': a failure with GOLEM_REQUIRE_EXTERNAL_TOOLS=1).
-}
qpdfExpanded :: BS.ByteString -> IO (Maybe BS.ByteString)
qpdfExpanded pdf = do
  qpdf <- optionalTool "qpdf" (findExecutable "qpdf")
  case qpdf of
    Nothing -> pure Nothing
    Just exe -> withSystemTempDirectory "golem-qdf" $ \dir -> do
      BS.writeFile (dir </> "in.pdf") pdf
      (code, out, err) <- readProcessWithExitCode exe ["--qdf", "--object-streams=disable", dir </> "in.pdf", dir </> "out.pdf"] ""
      assertEqual (out <> err) ExitSuccess code
      Just <$> BS.readFile (dir </> "out.pdf")
