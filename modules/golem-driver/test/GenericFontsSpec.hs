{- | HTML and EPUB without font files, naming generic families (root ADR
0423): fonts of [targets.html] and [targets.epub], generic-family of the
roles.
-}
module GenericFontsSpec (genericFontsTests) where

import Codec.Archive.Zip (eRelativePath, findEntryByPath, fromEntry, toArchive, zEntries)
import Control.Applicative ((<|>))
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf, sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

genericFontsTests :: [TestTree]
genericFontsTests =
  [ testCase "root ADR 0423 I1: fonts = \"generic\" embeds no font file and writes no @font-face in HTML and EPUB" $
      withFontProject (Just "generic") Nothing Nothing fakeFontFiles $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        map diagCode (brDiagnostics r) @?= []
        assertNoFonts tmp,
    testCase "root ADR 0423 I8: without fonts, HTML and EPUB embed no font file" $
      withFontProject Nothing Nothing Nothing fakeFontFiles $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        map diagCode (brDiagnostics r) @?= []
        assertNoFonts tmp,
    testCase "root ADR 0423 I8: a book without fonts and one with fonts = \"generic\" are the same HTML and EPUB" $ do
      a <- withFontProject Nothing Nothing Nothing fakeFontFiles webOutput
      b <- withFontProject (Just "generic") Nothing Nothing fakeFontFiles webOutput
      a @?= b,
    testCase "root ADR 0423 I5: fonts = \"embed\" embeds the fonts with @font-face as before" $
      withFontProject (Just "embed") Nothing Nothing fakeFontFiles $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        map diagCode (brDiagnostics r) @?= []
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "@font-face" ("@font-face { font-family: \"golem-body-ja\"; src: url(\"fonts/b.otf\"); }" `T.isInfixOf` css)
        doesFileExist (tmp </> "build/html/fonts/b.otf") >>= assertBool "the font in HTML"
        names <- epubEntries tmp
        assertBool (show names) ("OEBPS/fonts/b.otf" `elem` names)
        opf <- epubText tmp "OEBPS/package.opf"
        assertBool "the font in the manifest" ("media-type=\"font/otf\"" `T.isInfixOf` opf),
    testCase "root ADR 0423 I5: fonts may differ between HTML and EPUB" $
      withFontProject' "[targets.html]\nfonts = \"embed\"\n\n[targets.epub]\n" Nothing Nothing fakeFontFiles $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        map diagCode (brDiagnostics r) @?= []
        doesFileExist (tmp </> "build/html/fonts/b.otf") >>= assertBool "the font in HTML"
        names <- epubEntries tmp
        assertBool (show names) (not (any ("OEBPS/fonts/" `isPrefixOf`) names))
        epubCss <- epubText tmp "OEBPS/style.css"
        assertBool "no @font-face in EPUB" (not ("@font-face" `T.isInfixOf` epubCss)),
    testCase "root ADR 0423 I4: with fonts = \"generic\", missing font files are no diagnostic in dev and prod, and the outputs are written" $
      forM_ [Dev, Prod] $ \p ->
        withFontProject (Just "generic") Nothing Nothing [] $ \tmp -> do
          r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub], optProfile = p}
          (p, map diagCode (brDiagnostics r)) @?= (p, [])
          doesFileExist (tmp </> "build/html/style.css") >>= assertBool "HTML"
          doesFileExist (tmp </> "build/epub/book.epub") >>= assertBool "EPUB",
    testCase "root ADR 0423 I4: golem check reports nothing for missing fonts with fonts = \"generic\"" $
      withFontProject (Just "generic") Nothing Nothing [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub], optCheckOnly = True, optProfile = Prod}
        map diagCode (brDiagnostics r) @?= [],
    testCase "root ADR 0423 I4: the diagnostics of HTML and EPUB with fonts = \"generic\" do not depend on the font files" $ do
      with' <- withFontProject (Just "generic") Nothing Nothing fakeFontFiles $ \tmp -> map diagCode . brDiagnostics <$> build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub], optProfile = Prod}
      without <- withFontProject (Just "generic") Nothing Nothing [] $ \tmp -> map diagCode . brDiagnostics <$> build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub], optProfile = Prod}
      with' @?= without,
    testCase "root ADR 0423 I4: with fonts = \"generic\", a font outside the project is still G03279" $
      withProjectOf (manifestOf "[targets.html]\nfonts = \"generic\"\n\n[targets.epub]\nfonts = \"generic\"\n") (horizontalStyle <> "\n[fonts.body]\nja = \"../fonts/a.otf\"\n") [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G03279"],
    testCase "root ADR 0423 I5: with fonts = \"embed\", each missing font is one G03010 as before" $
      withFontProject (Just "embed") Nothing Nothing [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        sort [(diagMessage d, diagSeverity d) | d <- brDiagnostics r, diagCode d == DiagnosticCode "G03010"]
          @?= [("フォントのファイルがないので、HTML と EPUB に同梱しません: fonts/" <> f, Warning) | f <- ["b.otf", "h.otf", "w.otf"]]
        map diagCode (brDiagnostics r) @?= replicate 3 (DiagnosticCode "G03010"),
    testCase "root ADR 0423 I6: fonts and generic-family do not change the PDF" $ do
      let pdfOf fonts generic = withProjectOf (manifestOf ("[targets.pdf]\n\n" <> targetsWith fonts)) (fontStyle generic generic) fakeFontFiles $ \tmp -> do
            r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
            map diagCode (filter isError (brDiagnostics r)) @?= []
            files <- listDirectory (tmp </> "build/pdf")
            pdfs <- mapM (\f -> BS.readFile (tmp </> "build/pdf" </> f)) [f | f <- sort files, ".pdf" `T.isSuffixOf` T.pack f]
            pure (map withoutId pdfs)
      base <- pdfOf Nothing Nothing
      forM_ [(f, g) | f <- [Just "generic", Just "embed"], g <- [Nothing, Just "sans-serif", Just "monospace"]] $ \(f, g) -> do
        other <- pdfOf f g
        assertBool (show (f, g)) (other == base),
    testCase "root ADR 0423 I6: fonts and generic-family do not change the diagnostics of the PDF" $ do
      let codesOf' fonts generic = withProjectOf (manifestOf ("[targets.pdf]\n\n" <> targetsWith fonts)) (fontStyle generic generic) [] $ \tmp ->
            map diagCode . brDiagnostics <$> build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
      base <- codesOf' Nothing Nothing
      forM_ [(f, g) | f <- [Just "generic", Just "embed"], g <- [Nothing, Just "serif"]] $ \(f, g) -> do
        other <- codesOf' f g
        (f, g, other) @?= (f, g, base),
    testCase "root ADR 0423 I6: a role with generic-family and no file is still G08007 for the PDF" $
      withProjectOf (manifestOf "[targets.pdf]\n") (horizontalStyle <> "\n[fonts.body]\ngeneric-family = \"serif\"\n") [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
        assertBool (show (map diagCode (brDiagnostics r))) (DiagnosticCode "G08007" `elem` map diagCode (brDiagnostics r)),
    testCase "root ADR 0423: the EPUB of fonts = \"generic\" and of fonts = \"embed\" is the same bytes in another directory" $
      forM_ [Just "generic", Just "embed"] $ \f -> do
        a <- withFontProject f Nothing Nothing fakeFontFiles epubBytes
        b <- withFontProject f Nothing Nothing fakeFontFiles epubBytes
        assertBool (show f) (a == b)
  ]
    <> familyTests

{- | The generic family that ends each font-family of the CSS (root ADR
0423 I2, I3): every place of the table, with each value of generic-family
on the role of the place and on body, and none.
-}
familyTests :: [TestTree]
familyTests =
  [ testCase ("root ADR 0423 " <> (if mode == "generic" then "I2" else "I3") <> ": fonts = " <> show mode <> ", body " <> show gb <> ", the other roles " <> show gr) $
      withFontProject (Just mode) gb gr fakeFontFiles $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        map diagCode (brDiagnostics r) @?= []
        forM_ ["build/html/style.css", "epub"] $ \which -> do
          css <- if which == "epub" then epubText tmp "OEBPS/style.css" else TIO.readFile (tmp </> which)
          let decls = fontFamilies css
          -- every place of the table is written
          sort [s | (s, _) <- decls, s `elem` map fst (expected gb gr)] @?= sort (map fst (expected gb gr))
          forM_ decls $ \(sel, stack) -> case lookup sel (expected gb gr) of
            _ | stack == ["inherit"] -> pure ()
            Nothing -> assertFailure ("a font-family of no place of the table: " <> T.unpack sel <> " " <> show stack)
            Just g
              | mode == "generic" -> (which, sel, stack) @?= (which, sel, [g])
              | otherwise -> (which, sel, last stack) @?= (which, sel, g)
  | mode <- ["generic", "embed"],
    gb <- values,
    gr <- values
  ]
  where
    values = [Nothing, Just "serif", Just "sans-serif", Just "monospace"]
    expected gb gr =
      [ ("body", fromMaybe "serif" gb),
        ("p.ps-note", fromMaybe "serif" gr),
        ("pre, code", fromMaybe "monospace" gr),
        (".cs-kbd", fromMaybe "monospace" gr),
        (".cs-em2", fromMaybe "serif" (gr <|> gb))
      ]

{- | The font-family declarations of a style sheet, by the selector of their
rule: the families in order, without quotes; @font-face left out.
-}
fontFamilies :: Text -> [(Text, [Text])]
fontFamilies css =
  [ (T.strip sel, map (T.strip . T.filter (/= '"')) (T.splitOn "," value))
  | line <- T.lines css,
    not ("@font-face" `T.isPrefixOf` line),
    let (sel, body) = T.breakOn " {" line,
    (_, rest) <- T.breakOnAll "font-family: " body,
    let value = T.takeWhile (/= ';') (T.drop (T.length "font-family: ") rest)
  ]

-- | The style.toml of the four roles and the styles of each place; the generic-family of body and of the other roles.
fontStyle :: Maybe Text -> Maybe Text -> BS.ByteString
fontStyle gb gr =
  horizontalStyle
    <> TE.encodeUtf8
      ( T.concat
          [ "\n[fonts." <> role <> "]\n" <> key <> " = \"fonts/" <> file <> "\"\n" <> maybe "" (\g -> "generic-family = \"" <> g <> "\"\n") gen
          | (role, key, file, gen) <- [("body", "ja", "b.otf", gb), ("sans", "ja", "w.otf", gr), ("code", "latin", "h.otf", gr), ("mono", "latin", "h.otf", gr)]
          ]
          <> "\n[paragraph-styles.note]\nfont = \"sans\"\n\n[paragraph-styles.code]\nfont = \"code\"\n\n[character-styles.kbd]\nbased-on = \"code\"\nfont = \"mono\"\n\n[character-styles.em2]\nfont = \"sans\"\n"
      )

-- | [targets.html] and [targets.epub] with fonts, or without it.
targetsWith :: Maybe Text -> Text
targetsWith fonts = T.concat ["[targets." <> t <> "]\n" <> maybe "" (\f -> "fonts = \"" <> f <> "\"\n") fonts <> "\n" | t <- ["html", "epub"]]

-- | The manifest of the one-chapter project with these targets.
manifestOf :: Text -> BS.ByteString
manifestOf targets = TE.encodeUtf8 (manifestToml testManifest {tmTargets = []} <> "\n" <> targets)

-- | A project of the four roles, with fonts in both web targets.
withFontProject :: Maybe Text -> Maybe Text -> Maybe Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withFontProject fonts = withFontProject' (targetsWith fonts)

withFontProject' :: Text -> Maybe Text -> Maybe Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withFontProject' targets gb gr = withProjectOf (manifestOf targets) (fontStyle gb gr)

withProjectOf :: BS.ByteString -> BS.ByteString -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withProjectOf manifest style files act = withSystemTempDirectory "golem-generic" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 "本文。\n")
  writeFiles tmp files
  act tmp

-- | No font file in build/html or in the EPUB, and no @font-face in their CSS.
assertNoFonts :: FilePath -> Assertion
assertNoFonts tmp = do
  doesDirectoryExist (tmp </> "build/html/fonts") >>= assertBool "no fonts in HTML" . not
  css <- TIO.readFile (tmp </> "build/html/style.css")
  assertBool "no @font-face in HTML" (not ("@font-face" `T.isInfixOf` css))
  names <- epubEntries tmp
  assertBool (show names) (not (any ("OEBPS/fonts/" `isPrefixOf`) names))
  epubCss <- epubText tmp "OEBPS/style.css"
  assertBool "no @font-face in EPUB" (not ("@font-face" `T.isInfixOf` epubCss))
  opf <- epubText tmp "OEBPS/package.opf"
  assertBool "no font in the manifest of EPUB" (not ("media-type=\"font/" `T.isInfixOf` opf))

-- | The files of the HTML and the bytes of the EPUB of a project.
webOutput :: FilePath -> IO ([(FilePath, BS.ByteString)], BS.ByteString)
webOutput tmp = do
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
  map diagCode (brDiagnostics r) @?= []
  html <- listDirectory (tmp </> "build/html")
  files <- mapM (\f -> (f,) <$> BS.readFile (tmp </> "build/html" </> f)) (sort [f | f <- html, f /= "fonts", f /= "images"])
  (files,) <$> BS.readFile (tmp </> "build/epub/book.epub")

epubBytes :: FilePath -> IO BS.ByteString
epubBytes tmp = do
  r <- build (defaultOptions tmp) {optTargets = Just [TargetEpub]}
  map diagCode (brDiagnostics r) @?= []
  BS.readFile (tmp </> "build/epub/book.epub")

epubEntries :: FilePath -> IO [FilePath]
epubEntries tmp = map eRelativePath . zEntries . toArchive . BL.fromStrict <$> BS.readFile (tmp </> "build/epub/book.epub")

epubText :: FilePath -> FilePath -> IO Text
epubText tmp path = do
  archive <- toArchive . BL.fromStrict <$> BS.readFile (tmp </> "build/epub/book.epub")
  maybe (assertFailure ("no " <> path)) (pure . TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath path archive)

-- | The PDF without its ID, which hashes the inputs, manifest.toml and style.toml among them.
withoutId :: BS.ByteString -> BS.ByteString
withoutId b = let (before, rest) = BS.breakSubstring "/ID [" b in before <> BS.drop 1 (BS.dropWhile (/= 93) rest)
