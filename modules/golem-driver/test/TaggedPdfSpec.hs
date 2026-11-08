{- | Tagged PDF, and PDF/A-2a and PDF/UA-1 for the books that declare them
(docs/adr ADR 0183): the checks of a declared book, and the catalog and
XMP of the PDF.
-}
module TaggedPdfSpec (taggedPdfTests) where

import Control.Monad (filterM, forM_, unless)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isSpace)
import Data.Either (isRight)
import Data.List (isInfixOf, isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Pdf (LeafId (..), StructElem (..), StructKid (..), StructType (..))
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Golem.Typeset (orphanErrors)
import Support
import System.Directory (copyFile, createDirectoryIfMissing, doesFileExist, listDirectory)
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
miniStructure style source = miniStructureWith style source []

-- | 'miniStructure' with the files given.
miniStructureWith :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO T.Text
miniStructureWith style source files = withSystemTempDirectory "golem-structure" $ \tmp -> do
  writeProject tmp miniManifest style source files
  r <- pdfStructure (defaultOptions tmp) {optFonts = fakeProvider}
  either (\ds -> assertFailure (show (map diagCode ds)) >> pure "") pure r

{- | The leaves of the PDF of a copy of a fixture, as 'fixtureStructure'
makes it, whose text in the order of the content streams is not the text
of their glyphs in the order of the text, spaces left out (docs/adr ADR
0227, R1); a leaf of no glyph (an image) is left out.
-}
fixtureLeavesOutOfOrder :: FilePath -> IO [(LeafId, T.Text, T.Text)]
fixtureLeavesOutOfOrder name = withSystemTempDirectory "golem-structure" $ \tmp -> do
  copyTree ("test/fixtures/" <> name) tmp
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
  copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")
  r <- pdfLeafTexts (defaultOptions tmp)
  leaves <- either (\ds -> assertFailure (show (map diagCode ds)) >> pure []) pure r
  let bare = T.filter (not . isSpace)
  pure [(l, a, b) | (l, a, b) <- leaves, not (T.null b), bare a /= bare b]

-- | The style of the tests of the order of the glyphs of a box: a Latin face of its own, and synthetic bold on the Japanese side only.
orderStyle :: BS.ByteString
orderStyle = horizontal30 (fakeBody <> "\n[fonts.wide]\nlatin = \"fonts/w.otf\"\n\n[character-styles.lat]\nfont = \"wide\"\n\n[character-styles.lb]\nfont = \"wide\"\nsynthetic-bold = true\n")

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
    -- docs/adr ADR 0227
    testCase "R1: the glyphs of a box of two faces and of synthetic bold are drawn in the order of its text" $ do
      t <- miniStructureWith orderStyle "前[style lat: “a—b”]と[lang ja: [style lat: “Hello”]]と[style lb: “Hello”]、[style lb: x“y”z]。\n" fakeFontFiles
      assertBool (T.unpack t) ("“a—b”" `T.isInfixOf` t)
      length (T.breakOnAll "“Hello”" t) @?= 2
      assertBool (T.unpack t) ("x“y”z" `T.isInfixOf` t),
    testCase "R1: each leaf of the fixtures languages, complex-horizontal and complex-vertical draws its glyphs in the order of its text" $
      forM_ ["languages", "complex-horizontal", "complex-vertical"] $ \name -> do
        bad <- fixtureLeavesOutOfOrder name
        assertEqual name [] bad,
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
      <> orphanTests
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

{- | The PDF of a one-chapter project with its structure tree changed
before it is written, as a test-only stand-in for a mistake of Golem
(docs/adr ADR 0216).
-}
tamperedPdf :: Profile -> BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (StructElem -> StructElem) -> IO (Either [Diagnostic] BS.ByteString)
tamperedPdf profile manifest style source files f = withSystemTempDirectory "golem-orphans" $ \tmp -> do
  writeProject tmp manifest style source files
  pdfWithTree f (defaultOptions tmp) {optFonts = fakeProvider, optProfile = profile}

-- | The tree without its last element under the Document.
withoutLast :: StructElem -> StructElem
withoutLast root = root {seKids = take (length (seKids root) - 1) (seKids root)}

-- | The tree without its Note elements, at every depth.
withoutNotes :: StructElem -> StructElem
withoutNotes e = e {seKids = [k' | k <- seKids e, Just k' <- [keep k]]}
  where
    keep = \case
      KidElem c | seType c == SNote -> Nothing
      KidElem c -> Just (KidElem (withoutNotes c))
      k -> Just k

-- | The message of G07107 for n orphans.
orphanMessage :: Int -> T.Text
orphanMessage n = "構造の木にない内容を描きました（" <> T.pack (show n) <> " か所）。Golem の誤りです。この入力を添えて報告してください"

-- | The fixtures of test/fixtures that are books, but the public-domain books (BuildSpec builds them).
fixtureBooks :: IO [FilePath]
fixtureBooks = do
  names <- listDirectory "test/fixtures"
  filterM (\n -> doesFileExist ("test/fixtures" </> n </> "manifest.toml")) (filter (/= "pd") names)

orphanTests :: [TestTree]
orphanTests =
  [ testCase "G07107 S2 S3 S4: a unit drawn but missing from the tree is one G07107 at the unit, with no PDF, in dev and prod, with and without pdfa and pdfua" $ do
      let source = "一つめ。\n\n二つめの段落。\n"
          cases =
            [ (TE.encodeUtf8 (declaredManifest "ja" ""), horizontalStyle, []),
              (TE.encodeUtf8 (declaredManifest "ja" "pdfa = \"2a\"\n"), intentStyle, intentFiles),
              (TE.encodeUtf8 (declaredManifest "ja" "pdfua = \"1\"\n"), horizontalStyle, [])
            ]
      forM_ [(p, c) | p <- [Dev, Prod], c <- cases] $ \(profile, (manifest, style, files)) -> do
        -- the leaves the tree loses, from the tree as it is
        whole <- tamperedPdf profile manifest style source files id
        assertBool "S1: the whole tree gives a PDF" (isRight whole)
        r <- tamperedPdf profile manifest style source files withoutLast
        case r of
          Left ds -> do
            [(diagCode d, diagSeverity d, spanStart (diagSpan d)) | d <- ds] @?= [(DiagnosticCode "G07107", Error, offsetOf "二つめの段落。" source)]
            map diagMessage ds @?= [orphanMessage 1]
          Right _ -> assertFailure "a PDF was written",
    testCase "G07107 S2 S3: the body of a footnote missing from the tree is one G07107 at the note" $ do
      let source = "本文[note: 注の本文。]の後。\n"
      r <- tamperedPdf Dev miniManifest horizontalStyle source [] withoutNotes
      case r of
        Left ds -> [(diagCode d, spanStart (diagSpan d)) | d <- ds] @?= [(DiagnosticCode "G07107", offsetOf "[note:" source)]
        Right _ -> assertFailure "a PDF was written",
    testCase "G07107 S2 S3: the count is of the different leaves; a leaf of no place found is at the start of manifest.toml" $ do
      let manifestSpan = mkSpan (FileId 0) 0 0
          unitSpan = mkSpan (FileId 3) 10 20
          noteSpan = mkSpan (FileId 4) 5 9
          at = map (\d -> (diagCode d, diagSpan d, diagMessage d))
      at (orphanErrors manifestSpan (Map.fromList [(2, unitSpan)]) []) @?= []
      at (orphanErrors manifestSpan (Map.fromList [(2, unitSpan)]) [LeafId [2, 0, 1], LeafId [7, 0, 0]]) @?= [(DiagnosticCode "G07107", unitSpan, orphanMessage 2)]
      at (orphanErrors manifestSpan Map.empty [LeafId [-8, 4, 5, 9, 0, 1]]) @?= [(DiagnosticCode "G07107", noteSpan, orphanMessage 1)]
      at (orphanErrors manifestSpan Map.empty [LeafId [-9, 4, 5, 9, 1, 0]]) @?= [(DiagnosticCode "G07107", noteSpan, orphanMessage 1)]
      at (orphanErrors manifestSpan Map.empty [LeafId [7, 0, 0]]) @?= [(DiagnosticCode "G07107", manifestSpan, orphanMessage 1)]
      at (orphanErrors manifestSpan Map.empty [LeafId []]) @?= [(DiagnosticCode "G07107", manifestSpan, orphanMessage 1)],
    testCase "G07107 S5: no fixture book draws content missing from its tree" $ do
      books <- fixtureBooks
      assertBool (show books) (length books >= 10)
      failures <- concat <$> mapM fixtureOrphans books
      failures @?= []
  ]

{- | Builds a fixture book to PDF, with the fonts of the other fixtures as
fonts/ja.otf and fonts/latin.otf, the sample with the page of its PDF
golden (OutputGoldenSpec) and a book of no page with the page of
'horizontalStyle': what went wrong, if it gave G07107 or no PDF.
-}
fixtureOrphans :: FilePath -> IO [String]
fixtureOrphans name = withSystemTempDirectory "golem-orphans" $ \tmp -> do
  copyTree ("test/fixtures" </> name) tmp
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
  copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")
  if name == "sample"
    then do
      st <- BS.readFile "../../scripts/determinism/pdf-style.toml"
      BS.writeFile (tmp </> "style.toml") (st <> "\n[fonts.code]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n")
    else do
      -- a book of no page (the fixtures of HTML and of functions) takes one with the fonts
      st <- BS.readFile (tmp </> "style.toml")
      unless ("[page]" `BS.isInfixOf` st) $
        BS.writeFile (tmp </> "style.toml") (st <> "\n" <> horizontalStyle <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n\n[fonts.code]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n")
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf]}
  let codes = map diagCode (brDiagnostics r)
  pure ([name <> ": " <> show codes | DiagnosticCode "G07107" `elem` codes || not (any (".pdf" `isSuffixOf`) (brWritten r))])
