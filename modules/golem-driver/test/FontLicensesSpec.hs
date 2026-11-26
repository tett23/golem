{- | The license documents of the fonts HTML and EPUB embed (root ADR
0433): ja-license and latin-license of the roles, where the outputs put
them, the clashes of the names under fonts/, and G03282, G03283 and G03284
for each target that embeds the fonts.
-}
module FontLicensesSpec (fontLicensesTests) where

import Codec.Archive.Zip (eRelativePath, findEntryByPath, fromEntry, toArchive, zEntries)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

fontLicensesTests :: [TestTree]
fontLicensesTests =
  [ testCase "root ADR 0433 I1: the HTML of fonts = \"embed\" has the font and its ja-license in fonts/" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"fonts/LICENSE-B.txt\"\n") (font "b.otf" <> license "LICENSE-B.txt") $ \tmp -> do
        r <- buildWeb tmp Prod
        codesIn r @?= []
        htmlFonts tmp >>= (@?= ["LICENSE-B.txt", "b.otf"])
        BS.readFile (tmp </> "build/html/fonts/LICENSE-B.txt") >>= (@?= "license LICENSE-B.txt"),
    testCase "root ADR 0433 I2: the EPUB has the licenses of ja and latin in OEBPS/fonts/, listed in the manifest" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"fonts/LICENSE-B.txt\"\nlatin = \"fonts/l.otf\"\nlatin-license = \"fonts/LICENSE-L.txt\"\n") (font "b.otf" <> font "l.otf" <> license "LICENSE-B.txt" <> license "LICENSE-L.txt") $ \tmp -> do
        r <- buildWeb tmp Prod
        codesIn r @?= []
        names <- epubEntries tmp
        filter ("OEBPS/fonts/" `isPrefixOf`) names @?= ["OEBPS/fonts/LICENSE-B.txt", "OEBPS/fonts/LICENSE-L.txt", "OEBPS/fonts/b.otf", "OEBPS/fonts/l.otf"]
        opf <- epubText tmp "OEBPS/package.opf"
        forM_ ["LICENSE-B.txt", "LICENSE-L.txt"] $ \l ->
          assertBool (T.unpack l) (("href=\"fonts/" <> l <> "\" media-type=\"text/plain\"") `T.isInfixOf` opf),
    testCase "root ADR 0433 I2: a license document of .md is text/markdown in the manifest" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"fonts/OFL.md\"\n") (font "b.otf" <> license "OFL.md") $ \tmp -> do
        r <- buildWeb tmp Prod
        codesIn r @?= []
        opf <- epubText tmp "OEBPS/package.opf"
        assertBool (T.unpack opf) ("href=\"fonts/OFL.md\" media-type=\"text/markdown\"" `T.isInfixOf` opf),
    testCase "root ADR 0433 I2: license documents of .txt and of no extension are text/plain in the manifest" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"fonts/OFL.txt\"\nlatin = \"fonts/l.otf\"\nlatin-license = \"fonts/LICENSE\"\n") (font "b.otf" <> font "l.otf" <> license "OFL.txt" <> license "LICENSE") $ \tmp -> do
        r <- buildWeb tmp Prod
        codesIn r @?= []
        opf <- epubText tmp "OEBPS/package.opf"
        forM_ ["OFL.txt", "LICENSE"] $ \l ->
          assertBool (T.unpack l) (("href=\"fonts/" <> l <> "\" media-type=\"text/plain\"") `T.isInfixOf` opf),
    testCase "root ADR 0433 I3: in prod, a copied font without ja-license is one G03282 error and neither HTML nor EPUB is written" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\n") (font "b.otf") $ \tmp -> do
        r <- buildWeb tmp Prod
        codeSeverities r @?= [(DiagnosticCode "G03282", Error)]
        assertNoWeb tmp,
    testCase "root ADR 0433 I3: in prod, a missing ja-license file is one G03283 error and neither HTML nor EPUB is written" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"fonts/OFL.txt\"\n") (font "b.otf") $ \tmp -> do
        r <- buildWeb tmp Prod
        codeSeverities r @?= [(DiagnosticCode "G03283", Error)]
        [diagMessage d | d <- brDiagnostics r] @?= ["フォントのライセンスの文書のファイルがありません: fonts/OFL.txt"]
        assertNoWeb tmp,
    testCase "root ADR 0433 I3: the missing key and the missing file of two fonts are two codes, one for each" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nlatin = \"fonts/l.otf\"\nlatin-license = \"fonts/OFL.txt\"\n") (font "b.otf" <> font "l.otf") $ \tmp -> do
        r <- buildWeb tmp Prod
        codeSeverities r @?= [(DiagnosticCode "G03282", Error), (DiagnosticCode "G03283", Error)]
        [diagMessage d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G03282"] @?= ["フォントのライセンスの文書を指定していません: [fonts.body] の ja-license（fonts/b.otf）"],
    testCase "root ADR 0433 I3: in prod, only HTML embeds the fonts: the missing ja-license stops HTML and EPUB is written" $
      withLicenseProject "[targets.html]\nfonts = \"embed\"\n\n[targets.epub]\nfonts = \"generic\"\n" (bodyStyle "ja = \"fonts/b.otf\"\n") (font "b.otf") $ \tmp -> do
        r <- buildWeb tmp Prod
        codeSeverities r @?= [(DiagnosticCode "G03282", Error)]
        doesFileExist (tmp </> "build/html/style.css") >>= assertBool "no HTML" . not
        doesFileExist (tmp </> "build/epub/book.epub") >>= assertBool "EPUB",
    testCase "root ADR 0433 I3: in prod, only EPUB embeds the fonts: the missing ja-license stops EPUB and HTML is written" $
      withLicenseProject "[targets.html]\n\n[targets.epub]\nfonts = \"embed\"\n" (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"fonts/OFL.txt\"\n") (font "b.otf") $ \tmp -> do
        r <- buildWeb tmp Prod
        codeSeverities r @?= [(DiagnosticCode "G03283", Error)]
        doesFileExist (tmp </> "build/html/style.css") >>= assertBool "HTML"
        doesFileExist (tmp </> "build/epub/book.epub") >>= assertBool "no EPUB" . not,
    testCase "root ADR 0433 I4: in dev, a font without ja-license is a G03282 warning and both outputs are written without a license" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\n") (font "b.otf") $ \tmp -> do
        r <- buildWeb tmp Dev
        codeSeverities r @?= [(DiagnosticCode "G03282", Warning)]
        htmlFonts tmp >>= (@?= ["b.otf"])
        names <- epubEntries tmp
        filter ("OEBPS/fonts/" `isPrefixOf`) names @?= ["OEBPS/fonts/b.otf"],
    testCase "root ADR 0433 I4: in dev, a missing ja-license file is a G03283 warning and both outputs are written without it" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"fonts/OFL.txt\"\n") (font "b.otf") $ \tmp -> do
        r <- buildWeb tmp Dev
        codeSeverities r @?= [(DiagnosticCode "G03283", Warning)]
        htmlFonts tmp >>= (@?= ["b.otf"])
        names <- epubEntries tmp
        filter ("OEBPS/fonts/" `isPrefixOf`) names @?= ["OEBPS/fonts/b.otf"],
    testCase "root ADR 0433 I4: golem check reports the same codes as the build" $
      forM_ [Dev, Prod] $ \p ->
        withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nlatin = \"fonts/l.otf\"\nlatin-license = \"fonts/OFL.txt\"\n") (font "b.otf" <> font "l.otf") $ \tmp -> do
          checked <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub], optProfile = p, optCheckOnly = True}
          built <- buildWeb tmp p
          (p, codeSeverities checked) @?= (p, codeSeverities built),
    testCase "root ADR 0433 I8: a ja-license outside the project is G03279, for every target and profile" $
      forM_ [(t, p) | t <- [TargetHtml, TargetEpub, TargetText], p <- [Dev, Prod]] $ \(t, p) ->
        withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"../OFL.txt\"\n") (font "b.otf") $ \tmp -> do
          r <- build (defaultOptions tmp) {optTargets = Just [t], optProfile = p}
          (t, p, codeSeverities r) @?= (t, p, [(DiagnosticCode "G03279", Error)]),
    testCase "root ADR 0433 I8: a ja-license outside the project is G03279 also when the outputs name generic families" $
      withLicenseProject "[targets.html]\n\n[targets.epub]\n" (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"/etc/OFL.txt\"\n") (font "b.otf") $ \tmp -> do
        r <- buildWeb tmp Dev
        codeSeverities r @?= [(DiagnosticCode "G03279", Error)],
    testCase "root ADR 0433 I1: a missing font (G03010) copies neither the font nor its license, with no other code" $
      forM_ ["", "ja-license = \"fonts/OFL.txt\"\n"] $ \key ->
        withLicenseProject embedBoth (bodyStyle ("ja = \"fonts/b.otf\"\n" <> key)) (license "OFL.txt") $ \tmp -> do
          r <- buildWeb tmp Dev
          (key, codeSeverities r) @?= (key, [(DiagnosticCode "G03010", Warning)])
          doesDirectoryExist (tmp </> "build/html/fonts") >>= assertBool "no fonts/ in HTML" . not
          names <- epubEntries tmp
          filter ("OEBPS/fonts/" `isPrefixOf`) names @?= [],
    testCase "root ADR 0433 I5: fonts = \"generic\" copies no license document and reports no missing key nor file" $
      forM_ [Dev, Prod] $ \p ->
        forM_ ["ja-license = \"fonts/OFL.txt\"\n", "ja-license = \"fonts/none.txt\"\n", ""] $ \key ->
          withLicenseProject "[targets.html]\nfonts = \"generic\"\n\n[targets.epub]\n" (bodyStyle ("ja = \"fonts/b.otf\"\n" <> key)) (font "b.otf" <> license "OFL.txt") $ \tmp -> do
            r <- buildWeb tmp p
            (p, key, codesIn r) @?= (p, key, [])
            doesDirectoryExist (tmp </> "build/html/fonts") >>= assertBool "no fonts/ in HTML" . not
            names <- epubEntries tmp
            filter (\n -> "OEBPS/fonts/" `isPrefixOf` n || "OFL" `T.isInfixOf` T.pack n) names @?= [],
    testCase "root ADR 0433 I5: the PDF has no license document and no code of the licenses" $
      forM_ ["", "ja-license = \"fonts/none.txt\"\n"] $ \key ->
        withLicenseProject ("[targets.pdf]\n\n" <> embedBoth) (bodyStyle ("ja = \"fonts/b.otf\"\n" <> key)) (font "b.otf" <> license "OFL.txt") $ \tmp -> do
          r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = Prod}
          (key, [c | c <- codesIn r, c `elem` licenseCodes]) @?= (key, [])
          files <- listDirectory (tmp </> "build/pdf")
          (key, [f | f <- files, f == "fonts" || "OFL" `isPrefixOf` f]) @?= (key, []),
    testCase "root ADR 0433 I6: two roles that name the same license document copy it once" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"fonts/LICENSE-NotoSerifJP.txt\"\n" <> role "heading" "ja = \"fonts/h.otf\"\nja-license = \"fonts/LICENSE-NotoSerifJP.txt\"\n") (font "b.otf" <> font "h.otf" <> license "LICENSE-NotoSerifJP.txt") $ \tmp -> do
        r <- buildWeb tmp Prod
        codesIn r @?= []
        htmlFonts tmp >>= (@?= ["LICENSE-NotoSerifJP.txt", "b.otf", "h.otf"])
        names <- epubEntries tmp
        filter ("OEBPS/fonts/" `isPrefixOf`) names @?= ["OEBPS/fonts/LICENSE-NotoSerifJP.txt", "OEBPS/fonts/b.otf", "OEBPS/fonts/h.otf"]
        opf <- epubText tmp "OEBPS/package.opf"
        length (T.breakOnAll "href=\"fonts/LICENSE-NotoSerifJP.txt\"" opf) @?= 1,
    testCase "root ADR 0433 I6: OFL.txt of the same bytes in two folders is copied once" $
      withLicenseProject embedBoth (bodyStyle "ja = \"a/b.otf\"\nja-license = \"a/OFL.txt\"\nlatin = \"c/l.otf\"\nlatin-license = \"c/OFL.txt\"\n") [("a/b.otf", "font b"), ("c/l.otf", "font l"), ("a/OFL.txt", "OFL"), ("c/OFL.txt", "OFL")] $ \tmp -> do
        r <- buildWeb tmp Prod
        codesIn r @?= []
        htmlFonts tmp >>= (@?= ["OFL.txt", "b.otf", "l.otf"])
        BS.readFile (tmp </> "build/html/fonts/OFL.txt") >>= (@?= "OFL")
        names <- epubEntries tmp
        filter ("OEBPS/fonts/" `isPrefixOf`) names @?= ["OEBPS/fonts/OFL.txt", "OEBPS/fonts/b.otf", "OEBPS/fonts/l.otf"],
    testCase "root ADR 0433 I6: the same font file of the same bytes in two folders is copied once" $
      withLicenseProject embedBoth (bodyStyle "ja = \"a/b.otf\"\nja-license = \"a/OFL.txt\"\n" <> role "heading" "ja = \"c/b.otf\"\nja-license = \"c/OFL.txt\"\n") [("a/b.otf", "font b"), ("c/b.otf", "font b"), ("a/OFL.txt", "OFL"), ("c/OFL.txt", "OFL")] $ \tmp -> do
        r <- buildWeb tmp Prod
        codesIn r @?= []
        htmlFonts tmp >>= (@?= ["OFL.txt", "b.otf"]),
    testCase "root ADR 0433 I7: OFL.txt of other bytes in two folders is one G03284 error in dev and prod, and neither output is written" $
      forM_ [Dev, Prod] $ \p ->
        withLicenseProject embedBoth (bodyStyle "ja = \"a/b.otf\"\nja-license = \"a/OFL.txt\"\nlatin = \"c/l.otf\"\nlatin-license = \"c/OFL.txt\"\n") [("a/b.otf", "font b"), ("c/l.otf", "font l"), ("a/OFL.txt", "OFL a"), ("c/OFL.txt", "OFL c")] $ \tmp -> do
          r <- buildWeb tmp p
          (p, codeSeverities r) @?= (p, [(DiagnosticCode "G03284", Error)])
          (p, [diagMessage d | d <- brDiagnostics r]) @?= (p, ["fonts に写す同じ名前のファイルの中身が違います: fonts/OFL.txt（a/OFL.txt、c/OFL.txt）"])
          assertNoWeb tmp,
    testCase "root ADR 0433 I7: fonts of the same name and other bytes in two folders are one G03284 error in dev and prod" $
      forM_ [Dev, Prod] $ \p ->
        withLicenseProject embedBoth (bodyStyle "ja = \"a/b.otf\"\nja-license = \"a/OFL.txt\"\n" <> role "heading" "ja = \"c/b.otf\"\nja-license = \"a/OFL.txt\"\n") [("a/b.otf", "font a"), ("c/b.otf", "font c"), ("a/OFL.txt", "OFL")] $ \tmp -> do
          r <- buildWeb tmp p
          (p, codeSeverities r) @?= (p, [(DiagnosticCode "G03284", Error)])
          assertNoWeb tmp,
    testCase "root ADR 0433 I7: a font and a license document of the same name and other bytes are one G03284 error" $
      withLicenseProject embedBoth (bodyStyle "ja = \"fonts/b.otf\"\nja-license = \"lic/b.otf\"\n") [("fonts/b.otf", "font"), ("lic/b.otf", "license")] $ \tmp -> do
        r <- buildWeb tmp Dev
        codeSeverities r @?= [(DiagnosticCode "G03284", Error)]
        assertNoWeb tmp,
    testCase "root ADR 0433 I7: a clash stops only the target that embeds the fonts" $
      withLicenseProject "[targets.html]\n\n[targets.epub]\nfonts = \"embed\"\n" (bodyStyle "ja = \"a/b.otf\"\nja-license = \"a/OFL.txt\"\nlatin = \"c/l.otf\"\nlatin-license = \"c/OFL.txt\"\n") [("a/b.otf", "font b"), ("c/l.otf", "font l"), ("a/OFL.txt", "OFL a"), ("c/OFL.txt", "OFL c")] $ \tmp -> do
        r <- buildWeb tmp Dev
        codeSeverities r @?= [(DiagnosticCode "G03284", Error)]
        doesFileExist (tmp </> "build/html/style.css") >>= assertBool "HTML"
        doesFileExist (tmp </> "build/epub/book.epub") >>= assertBool "no EPUB" . not,
    testCase "root ADR 0433 I7: a missing font is not copied, so it clashes with nothing" $
      withLicenseProject embedBoth (bodyStyle "ja = \"a/b.otf\"\nja-license = \"a/OFL.txt\"\n" <> role "heading" "ja = \"c/b.otf\"\nja-license = \"a/OFL.txt\"\n") [("a/b.otf", "font a"), ("a/OFL.txt", "OFL")] $ \tmp -> do
        r <- buildWeb tmp Dev
        codeSeverities r @?= [(DiagnosticCode "G03010", Warning)]
        htmlFonts tmp >>= (@?= ["OFL.txt", "b.otf"])
        BS.readFile (tmp </> "build/html/fonts/b.otf") >>= (@?= "font a"),
    testCase "root ADR 0433: the diagnostics of the licenses are the same in another directory" $ do
      let run = withLicenseProject embedBoth (bodyStyle "ja = \"a/b.otf\"\nlatin = \"c/l.otf\"\nlatin-license = \"c/none.txt\"\n" <> role "heading" "ja = \"c/b.otf\"\n") [("a/b.otf", "font a"), ("c/b.otf", "font c"), ("c/l.otf", "font l")] $ \tmp ->
            map (\d -> (diagCode d, diagSeverity d, diagMessage d)) . brDiagnostics <$> buildWeb tmp Prod
      a <- run
      b <- run
      a @?= b
      sort [c | (c, _, _) <- a] @?= map DiagnosticCode ["G03282", "G03282", "G03283", "G03284"],
    testCase "root ADR 0448 I3: golem build reports G03282 once for each font without its key, only when a built target embeds the fonts" $
      forM_ i3Rows $ \(name, targets, style, built, expected) ->
        withLicenseProject targets style (font "a.otf" <> font "b.otf") $ \tmp -> do
          r <- build (defaultOptions tmp) {optTargets = Just built, optFonts = fakeProvider, optProfile = Dev}
          (name, length [() | c <- codesIn r, c == DiagnosticCode "G03282"]) @?= (name, expected)
  ]

{- | The rows of the table of root ADR 0448 for golem build: the name, the
targets of the manifest, style.toml, the targets built, and the number of
G03282.
-}
i3Rows :: [(String, Text, Text, [Target], Int)]
i3Rows =
  [ ("no [fonts]", embedBoth, TE.decodeUtf8 horizontalStyle, [TargetHtml, TargetEpub], 0),
    ("one font, HTML embeds", embedBoth, oneFont, [TargetHtml], 1),
    ("two fonts, HTML embeds", embedBoth, bodyStyle "ja = \"fonts/a.otf\"\nlatin = \"fonts/b.otf\"\n", [TargetHtml], 2),
    ("one font, HTML and EPUB embed", embedBoth, oneFont, [TargetHtml, TargetEpub], 1),
    ("HTML generic, EPUB embeds", "[targets.html]\nfonts = \"generic\"\n\n[targets.epub]\nfonts = \"embed\"\n", oneFont, [TargetHtml, TargetEpub], 1),
    ("HTML generic", "[targets.html]\nfonts = \"generic\"\n", oneFont, [TargetHtml], 0),
    ("only the PDF", "[targets.pdf]\n\n" <> embedBoth, oneFont, [TargetPdf], 0),
    ("HTML embeds, EPUB generic, built with --target epub", "[targets.html]\nfonts = \"embed\"\n\n[targets.epub]\n", oneFont, [TargetEpub], 0)
  ]
  where
    oneFont = bodyStyle "ja = \"fonts/a.otf\"\n"

-- | The codes of root ADR 0433.
licenseCodes :: [DiagnosticCode]
licenseCodes = map DiagnosticCode ["G03282", "G03283", "G03284"]

-- | Both web targets embed the fonts.
embedBoth :: Text
embedBoth = "[targets.html]\nfonts = \"embed\"\n\n[targets.epub]\nfonts = \"embed\"\n"

-- | A horizontal style.toml with [fonts.body] of these keys.
bodyStyle :: Text -> Text
bodyStyle keys = TE.decodeUtf8 horizontalStyle <> "\n[fonts.body]\n" <> keys

-- | Another role, used by the headings so that the PDF loads it too.
role :: Text -> Text -> Text
role name keys = "\n[fonts." <> name <> "]\n" <> keys

font :: FilePath -> [(FilePath, BS.ByteString)]
font name = [("fonts/" <> name, "fake " <> TE.encodeUtf8 (T.pack name))]

license :: FilePath -> [(FilePath, BS.ByteString)]
license name = [("fonts/" <> name, "license " <> TE.encodeUtf8 (T.pack name))]

buildWeb :: FilePath -> Profile -> IO BuildResult
buildWeb tmp p = build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub], optProfile = p}

codeSeverities :: BuildResult -> [(DiagnosticCode, Severity)]
codeSeverities r = [(diagCode d, diagSeverity d) | d <- brDiagnostics r]

codesIn :: BuildResult -> [DiagnosticCode]
codesIn = map diagCode . brDiagnostics

withLicenseProject :: Text -> Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withLicenseProject targets style files act = withSystemTempDirectory "golem-licenses" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = []} <> "\n" <> targets))
  BS.writeFile (tmp </> "style.toml") (TE.encodeUtf8 style)
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 "本文。\n")
  writeFiles tmp files
  act tmp

-- | The files in build/html/fonts.
htmlFonts :: FilePath -> IO [FilePath]
htmlFonts tmp = sort <$> listDirectory (tmp </> "build/html/fonts")

-- | Neither HTML nor EPUB was written.
assertNoWeb :: FilePath -> Assertion
assertNoWeb tmp = do
  doesFileExist (tmp </> "build/html/style.css") >>= assertBool "no HTML" . not
  doesFileExist (tmp </> "build/epub/book.epub") >>= assertBool "no EPUB" . not

epubEntries :: FilePath -> IO [FilePath]
epubEntries tmp = sort . map eRelativePath . zEntries . toArchive . BL.fromStrict <$> BS.readFile (tmp </> "build/epub/book.epub")

epubText :: FilePath -> FilePath -> IO Text
epubText tmp path = do
  archive <- toArchive . BL.fromStrict <$> BS.readFile (tmp </> "build/epub/book.epub")
  maybe (assertFailure ("no " <> path)) (pure . TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath path archive)
