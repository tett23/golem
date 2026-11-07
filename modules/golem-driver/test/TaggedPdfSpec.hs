{- | Tagged PDF, and PDF/A-2a and PDF/UA-1 for the books that declare them
(docs/adr ADR 0183): the checks of a declared book, and the catalog and
XMP of the PDF.
-}
module TaggedPdfSpec (taggedPdfTests) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isInfixOf, isSuffixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

-- | A manifest with [targets.pdf] of the keys given, and HTML and plain text.
declaredManifest :: T.Text -> T.Text -> T.Text
declaredManifest language keys = manifestToml testManifest {tmLanguage = language, tmTargets = ["html", "text"]} <> "\n[targets.pdf]\n" <> keys

-- | The style with an output intent, and its profile.
intentStyle :: BS.ByteString
intentStyle = horizontalStyle <> "\n[color]\nintent = \"x.icc\"\n"

intentFiles :: [(FilePath, BS.ByteString)]
intentFiles = [("x.icc", "fake profile")]

-- | What a build of a one-chapter project wrote, and its diagnostics.
data Declared = Declared
  { dDiagnostics :: [Diagnostic],
    dWritten :: [FilePath],
    dManifest :: T.Text
  }

buildDeclared :: Profile -> T.Text -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO Declared
buildDeclared profile manifest style source files = withSystemTempDirectory "golem-tagged" $ \tmp -> do
  writeProject tmp (TE.encodeUtf8 manifest) style source files
  r <- build (defaultOptions tmp) {optFonts = fakeProvider, optProfile = profile}
  pure (Declared (brDiagnostics r) [drop (length tmp + 1) p | p <- brWritten r] manifest)

errorsOf :: Declared -> [T.Text]
errorsOf = codesOf . filter isError . dDiagnostics

hasPdf :: Declared -> Bool
hasPdf = any (".pdf" `isSuffixOf`) . dWritten

-- | The byte offset of the first occurrence of a text in another.
offsetOf :: T.Text -> T.Text -> Int
offsetOf needle hay = BS.length (TE.encodeUtf8 (fst (T.breakOn needle hay)))

{- | The structure tree of the PDF of a copy of a fixture, with the fonts
of the other fixtures as fonts/ja.otf and fonts/latin.otf where it has
none, and its style and manifest replaced by the files given.
-}
fixtureStructure :: FilePath -> Maybe FilePath -> Maybe FilePath -> IO T.Text
fixtureStructure name style manifest = withSystemTempDirectory "golem-structure" $ \tmp -> do
  copyTree ("test/fixtures/" <> name) tmp
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
  copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")
  -- a style of the fixture, or the page of the PDF of the sample (OutputGoldenSpec) with the fonts for code
  case style of
    Just "pdf-style" -> do
      st <- BS.readFile "../../scripts/determinism/pdf-style.toml"
      BS.writeFile (tmp </> "style.toml") (st <> "\n[fonts.code]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n")
    Just f -> copyFile (tmp </> f) (tmp </> "style.toml")
    Nothing -> pure ()
  mapM_ (\f -> copyFile (tmp </> f) (tmp </> "manifest.toml")) manifest
  r <- pdfStructure (defaultOptions tmp)
  either (\ds -> assertFailure (show (map diagCode ds)) >> pure "") pure r

-- | The golden of the structure tree of a fixture (docs/adr ADR 0183).
structureGolden :: String -> FilePath -> Maybe FilePath -> Maybe FilePath -> TestTree
structureGolden golden name style manifest = goldenVsString golden ("test/golden/" <> golden) (BL.fromStrict . TE.encodeUtf8 <$> fixtureStructure name style manifest)

-- | The structure tree of a one-chapter project.
miniStructure :: BS.ByteString -> T.Text -> IO T.Text
miniStructure style source = withSystemTempDirectory "golem-structure" $ \tmp -> do
  writeProject tmp miniManifest style source []
  r <- pdfStructure (defaultOptions tmp) {optFonts = fakeProvider}
  either (\ds -> assertFailure (show (map diagCode ds)) >> pure "") pure r

-- | The lines of a structure tree without their indentation.
treeLines :: T.Text -> [T.Text]
treeLines = map T.strip . T.lines

structureTests :: [TestTree]
structureTests =
  [ structureGolden "structure-sample.txt" "sample" (Just "pdf-style") Nothing,
    structureGolden "structure-kanikosen.txt" "kanikosen" Nothing Nothing,
    structureGolden "structure-conformance-horizontal.txt" "conformance" Nothing Nothing,
    structureGolden "structure-conformance-vertical.txt" "conformance" (Just "style-vertical.toml") (Just "manifest-vertical.toml"),
    -- docs/adr ADR 0187
    structureGolden "structure-languages.txt" "languages" Nothing Nothing,
    testCase "a language span is a Span of its /Lang; a block with @lang has it on its own element" $ do
      t <- treeLines <$> miniStructure horizontalStyle "本文[lang fr: x]。\n\n@lang en\nText.\n\n@lang en\n- a\n- b\n\n@lang en\n  One.\n\n  Two.\n"
      assertBool (show t) ("Span Lang=fr" `elem` t)
      [l | l <- t, "P Lang=" `T.isPrefixOf` l] @?= ["P Lang=en", "P Lang=en", "P Lang=en"]
      [l | l <- t, "L " `T.isPrefixOf` l] @?= ["L Lang=en /List /ListNumbering /Disc"]
      -- the items of the list take its language from it
      length [l | l <- t, "LI" `T.isPrefixOf` l, "Lang" `T.isInfixOf` l] @?= 0,
    testCase "a book without [lang] and @lang has no /Lang in its tree" $ do
      t <- fixtureStructure "conformance" Nothing Nothing
      assertBool "no Lang" (not ("Lang=" `T.isInfixOf` t)),
    testCase "the elements of each kind of block and inline of the conformance fixture" $ do
      h <- treeLines <$> fixtureStructure "conformance" Nothing Nothing
      let has t = assertBool (T.unpack t) (t `elem` h)
          hasPrefix t = assertBool (T.unpack t) (any (t `T.isPrefixOf`) h)
      mapM_ has ["Document", "TOC", "TOCI", "H1", "H2", "H3", "P", "Ruby", "RB", "RT", "Reference", "Code", "LI", "Lbl", "LBody", "Table", "TR", "TD", "Div", "Caption", "Index", "BibEntry"]
      mapM_ hasPrefix ["L /List /ListNumbering /Disc", "L /List /ListNumbering /Decimal", "L /List /ListNumbering /None", "TH /Table /Scope /Column", "Note ID=note-1", "Note ID=note-2"],
    testCase "a vertical book's Document has WritingMode TbRl; a horizontal one's has none" $ do
      v <- fixtureStructure "conformance" (Just "style-vertical.toml") (Just "manifest-vertical.toml")
      take 1 (T.lines v) @?= ["Document /Layout /WritingMode /TbRl"]
      h <- miniStructure horizontalStyle "本文。\n"
      take 1 (T.lines h) @?= ["Document"],
    testCase "a ruby is RB then RT, the RT the reading" $ do
      t <- treeLines <$> miniStructure horizontalStyle "前[ruby: 漢字 | かんじ]後。\n"
      let after = drop 1 (dropWhile (/= "Ruby") t)
      take 4 after @?= ["RB", "\"漢字\"", "RT", "\"かんじ\""],
    testCase "a Note follows the Reference of its mark; their IDs are one each" $ do
      t <- treeLines <$> miniStructure horizontalStyle "前[note: 一。]中[note: 二。]後。\n"
      let refs = [i | (i, l) <- zip [0 :: Int ..] t, l == "Reference"]
          notes = [i | (i, l) <- zip [0 :: Int ..] t, "Note" `T.isPrefixOf` l]
      length refs @?= 2
      [n > r | (r, n) <- zip refs notes] @?= [True, True]
      [l | l <- t, "Note" `T.isPrefixOf` l] @?= ["Note ID=note-1", "Note ID=note-2"],
    testCase "running heads, folios, rules and the marks of kenten are not leaves" $ do
      -- the running head of the conformance fixture is the short title of its chapter, a heading once in the tree
      t <- T.lines <$> fixtureStructure "conformance" Nothing Nothing
      length [l | l <- t, "見出しと段落" `T.isInfixOf` l] @?= 2
      -- the folios: no leaf of a number alone but the cells of the table
      k <- miniStructure horizontalStyle "[kenten: 強調]の字。\n"
      assertBool (T.unpack k) ("\"強調の字。\"" `T.isInfixOf` k)
      assertBool (T.unpack k) (not (T.any (`elem` ("\xFE45\x2022" :: String)) k)),
    testCase "the header row of a table on its second page is an artifact: the header text is a leaf once" $ do
      let rows = T.concat ["| " <> T.pack (show k) <> " | 行 |\n" | k <- [1 .. 40 :: Int]]
      t <- miniStructure horizontalStyle ("| 見出しの列 | 二 |\n|---|---|\n" <> rows)
      length (filter ("見出しの列" `isInfixOf`) (map T.unpack (T.lines t))) @?= 1
  ]

taggedPdfTests :: TestTree
taggedPdfTests =
  testGroup
    "tagged PDF, PDF/A-2a and PDF/UA-1 (docs/adr ADR 0183)"
    $ structureTests
      <> [ testCase "pdfa = \"2a\" without [color] intent is G03113 at the value, with no PDF but HTML and plain text, in dev and prod" $
             mapM_
               ( \profile -> do
                   d <- buildDeclared profile (declaredManifest "ja" "pdfa = \"2a\"\n") horizontalStyle "本文。\n" []
                   errorsOf d @?= ["G03113"]
                   [(diagMessage x, spanStart (diagSpan x)) | x <- dDiagnostics d, diagCode x == DiagnosticCode "G03113"]
                     @?= [("PDF/A には [color] の intent が要ります", offsetOf "\"2a\"" (dManifest d))]
                   hasPdf d @?= False
                   assertBool (show (dWritten d)) (any (".xhtml" `isSuffixOf`) (dWritten d))
                   assertBool (show (dWritten d)) (any (".txt" `isSuffixOf`) (dWritten d))
               )
               [Dev, Prod],
           testCase "pdfua = \"1\" alone needs no output intent" $ do
             d <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle "本文。\n" []
             errorsOf d @?= []
             hasPdf d @?= True,
           testCase "a language not of the form of a tag is G03119 at the value with pdfua, and with pdfa" $ do
             d <- buildDeclared Dev (declaredManifest "日本 語!" "pdfua = \"1\"\n") horizontalStyle "本文。\n" []
             errorsOf d @?= ["G03119"]
             [(diagMessage x, spanStart (diagSpan x)) | x <- dDiagnostics d, diagCode x == DiagnosticCode "G03119"]
               @?= [("PDF/A と PDF/UA には、language を言語のタグの形で書きます: 日本 語!", offsetOf "\"日本 語!\"" (dManifest d))]
             hasPdf d @?= False
             e <- buildDeclared Dev (declaredManifest "日本 語!" "pdfa = \"2a\"\n") intentStyle "本文。\n" intentFiles
             errorsOf e @?= ["G03119"],
           testCase "without pdfa and pdfua a language of any form is no error" $ do
             d <- buildDeclared Dev (declaredManifest "日本 語!" "") horizontalStyle "# 一\n\n### 二\n" []
             errorsOf d @?= []
             hasPdf d @?= True,
           testCase "with pdfua a heading two levels deeper, and a first heading not of level 1, are G07103 at the heading" $ do
             let source = "# 一\n\n本文。\n\n### 三\n"
             d <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle source []
             errorsOf d @?= ["G07103"]
             [(diagMessage x, spanStart (diagSpan x)) | x <- dDiagnostics d, diagCode x == DiagnosticCode "G07103"]
               @?= [("PDF/UA では見出しの段を飛ばせません: 1 から 3", offsetOf "### 三" source)]
             hasPdf d @?= False
             e <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle "## 二\n" []
             [(diagMessage x, spanStart (diagSpan x)) | x <- dDiagnostics e, diagCode x == DiagnosticCode "G07103"]
               @?= [("PDF/UA では見出しの段を飛ばせません: 0 から 2", 0)],
           testCase "with pdfua a heading may go back any number of levels" $ do
             d <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle "# 一\n\n## 二\n\n### 三\n\n# 四\n" []
             errorsOf d @?= [],
           testCase "with pdfa a character of the private use area is G07104 at its text" $ do
             let source = "本文\xE000。\n"
             d <- buildDeclared Dev (declaredManifest "ja" "pdfa = \"2a\"\n") intentStyle source intentFiles
             errorsOf d @?= ["G07104"]
             [(diagMessage x, spanFile (diagSpan x) /= FileId 0) | x <- dDiagnostics d, diagCode x == DiagnosticCode "G07104"]
               @?= [("PDF/A-2a の PDF に私用領域の字は書けません: U+E000", True)]
             hasPdf d @?= False
             e <- buildDeclared Dev (declaredManifest "ja" "pdfua = \"1\"\n") horizontalStyle source []
             errorsOf e @?= [],
           testCase "pdfa and an output intent: golem preflight finds nothing against PDF/X-4" $
             withSystemTempDirectory "golem-tagged" $ \tmp -> do
               writeProject tmp (TE.encodeUtf8 (declaredManifest "ja" "pdfa = \"2a\"\npdfua = \"1\"\n")) intentStyle "# 一\n\n本文。\n" intentFiles
               p <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}
               [c | c <- codesOf (prDiagnostics p), c == "G09014"] @?= []
         ]
