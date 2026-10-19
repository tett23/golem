module ReferencesSpec (indexTests, bibliographyFormatTests, tableTests, tocTests, indexColumnTests) where

import Control.Monad (forM_, zipWithM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (isSuffixOf, nub, sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (IndexGroup (..))
import Golem.Doc.Bibliography (EntryPart (..), entryText)
import Golem.Doc.IR (Inline, InlineF (..))
import Golem.Driver
import Golem.Driver.Pdf (PdfLayout (..), SetLine (..), TocGeometry (..), TocPage (..), bibliographyLines, indexLines, tocPage)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (plainLook)
import Golem.Layout.Paginate (ColumnSet (..), PageOut (..), Slotted (..), labelPages, markPages)
import Golem.LayoutSpec (PageGeometry (..), Rect (..), pageGeometry, typeAreaFor)
import Golem.Pdf (spToPt)
import Golem.Project (Project (..), ProjectFailure (..))
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The page numbers among inlines.
numbersIn :: [Inline] -> [Integer]
numbersIn is = [n | Number _ n _ <- is]

refsJson :: BS.ByteString
refsJson = "[{\"id\": \"knuth1981\", \"title\": \"Breaking Paragraphs into Lines\", \"author\": [{\"family\": \"Knuth\", \"given\": \"Donald\"}], \"issued\": {\"date-parts\": [[1981]]}}]"

-- | Three entries, a, b and c, as CSL-JSON, and their entries for the PDF.
abcJson :: BS.ByteString
abcJson = "[{\"id\": \"a\", \"title\": \"A\"}, {\"id\": \"b\", \"title\": \"B\"}, {\"id\": \"c\", \"title\": \"C\"}]"

abcEntries :: Map.Map T.Text [EntryPart]
abcEntries = Map.fromList [(k, [EntryText ("Entry " <> T.toUpper k)]) | k <- ["a", "b", "c"]]

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
      map rendered (bibliographyLines (Map.fromList [("knuth1981", [EntryText "Knuth Donald. Breaking."])]) [("knuth1981", 1), ("missing", 2)]) @?= ["[1] Knuth Donald. Breaking.", "[2] missing"],
    testCase "the index of a book shows the pages of its marks" $ do
      let source =
            "# 一\n\n本文[index reading=くみはん: 組版]。\n\n"
              <> fillers 3
              <> "# 二\n\n"
              <> fillers 4
              <> "本文[index reading=わぶん: 和文]。\n\n@index\n"
      r <- pagesMini "" (fiveLines <> flatHeadings) source [] Map.empty
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
      r <- pagesMini "bibliography = [\"refs.json\"]\n" horizontalStyle "本文[cite knuth1981]。\n\n@bibliography\n" [("refs.json", refsJson)] (Map.fromList [("knuth1981", [EntryText "Knuth Donald. Breaking Paragraphs into Lines. 1981."])])
      ls <- concat <$> either (assertFailure . show) pure r
      assertBool (show ls) (any ("[1]" `T.isInfixOf`) ls)
      assertBool (show ls) (not (any ("knuth1981" `T.isInfixOf`) ls))
      assertBool (show ls) (any (\l -> "[1]" `T.isPrefixOf` l && "Knuth" `T.isInfixOf` l) ls),
    -- several lists (golem-doc ADR 0008)
    testCase "PDF: each @bibliography lists the citations of its range, numbered from 1" $ do
      let source = "本文[cite a][cite b]。\n\n@bibliography\n\n本文[cite b][cite c]。\n\n@bibliography\n"
      r <- pagesMini "bibliography = [\"refs.json\"]\n" horizontalStyle source [("refs.json", abcJson)] abcEntries
      ls <- concat <$> either (assertFailure . show) pure r
      filter ("Entry" `T.isInfixOf`) ls @?= ["[1]EntryA", "[2]EntryB", "[1]EntryB", "[2]EntryC"]
      assertBool (show ls) (any ("[1][2]" `T.isInfixOf`) ls)
      assertBool (show ls) (not (any ("[3]" `T.isInfixOf`) ls)),
    testCase "PDF: each @index has the marks of its own range" $ do
      let source = "本文[index reading=か: か]。\n\n@index\n\n本文[index reading=さ: さ]。\n\n@index\n"
      r <- pagesMini "" horizontalStyle source [] Map.empty
      ls <- concat <$> either (assertFailure . show) pure r
      filter (\l -> any (`T.isPrefixOf` l) ["か　", "さ　"]) ls @?= ["か　1", "さ　1"],
    testCase "plain text: each @bibliography lists the citations of its range" $
      withBibProject "bibliography = [\"refs.json\"]" "本文[cite a][cite b]。\n\n@bibliography\n\n本文[cite b][cite c]。\n\n@bibliography\n" [("refs.json", abcJson)] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        t <- TIO.readFile (tmp </> "build/text/horizontal/a.txt")
        [l | l <- T.lines t, "[" `T.isPrefixOf` l] @?= ["[1] A.", "[2] B.", "[1] B.", "[2] C."]
        assertBool (T.unpack t) ("本文[1][2]。" `T.isInfixOf` t),
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
            writeStyleWithFont tmp fiveLines
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

-- | A one-chapter project with a bibliography line and extra files.
withBibProject :: T.Text -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withBibProject bibLine source files act = withSystemTempDirectory "golem-bib" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 bibLine <> "\n" <> miniManifest <> "[targets.html]\n")
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ files $ \(to, bytes) -> BS.writeFile (tmp </> to) bytes
  act tmp

-- | loadBibliography of a project: diagnostics, keys and entries.
bibOf :: T.Text -> [(FilePath, BS.ByteString)] -> IO ([Diagnostic], Map.Map T.Text T.Text)
bibOf bibLine files = fmap (Map.map entryText) <$> bibPartsOf bibLine files

-- | loadBibliography of a project: diagnostics, keys and entries as parts.
bibPartsOf :: T.Text -> [(FilePath, BS.ByteString)] -> IO ([Diagnostic], Map.Map T.Text [EntryPart])
bibPartsOf bibLine files = withBibProject bibLine "本文。\n" files $ \tmp -> do
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> do
      (ds, _, m) <- loadBibliography tmp (projectManifest (evProject e))
      pure (ds, m)

-- | A Japanese entry, by a literal author, as CSL-JSON.
jaRefsJson :: BS.ByteString
jaRefsJson = TE.encodeUtf8 "[{\"id\": \"jisx4061\", \"title\": \"JIS X 4061:1996 日本語文字列照合順番\", \"publisher\": \"日本規格協会\", \"issued\": {\"date-parts\": [[1996]]}}, {\"id\": \"lit\", \"author\": [{\"literal\": \"日本規格協会\", \"family\": \"x\"}], \"title\": \"照合順番\", \"issued\": {\"literal\": \"n.d.\"}}]"

bibliographyFormatTests :: [TestTree]
bibliographyFormatTests =
  [ testCase "a literal author and a literal date are in the entry" $ do
      (ds, m) <- bibOf "bibliography = [\"refs.json\"]" [("refs.json", jaRefsJson)]
      ds @?= []
      Map.lookup "lit" m @?= Just "日本規格協会、照合順番、n.d.。"
      Map.lookup "jisx4061" m @?= Just "JIS X 4061:1996 日本語文字列照合順番、日本規格協会、1996。",
    testCase "a missing file is G0326 at the head of manifest.toml" $ do
      (ds, m) <- bibOf "bibliography = [\"nope.json\"]" []
      map (\d -> (diagCode d, diagSeverity d, diagSpan d, diagMessage d)) ds @?= [(DiagnosticCode "G0326", Error, mkSpan (FileId 0) 0 0, "参考文献のファイルがありません: nope.json")]
      m @?= Map.empty,
    testCase "a file that is not JSON, or not an array, is G0326" $ do
      (ds1, _) <- bibOf "bibliography = [\"refs.json\"]" [("refs.json", "{")]
      map diagCode ds1 @?= [DiagnosticCode "G0326"]
      assertBool (show ds1) (all (("参考文献のファイルを JSON として読めません: refs.json（" `T.isPrefixOf`) . diagMessage) ds1)
      (ds2, _) <- bibOf "bibliography = [\"refs.json\"]" [("refs.json", "{}")]
      map diagMessage ds2 @?= ["参考文献のファイルは CSL-JSON の配列で書きます: refs.json"],
    testCase "an absolute path is G0303" $ do
      (ds, _) <- bibOf "bibliography = [\"/abs.json\"]" []
      map diagCode ds @?= [DiagnosticCode "G0303"],
    testCase "golem check reports G0326 before the G0221 it causes" $
      withBibProject "bibliography = [\"nope.json\"]" "本文[cite jlreq]。\n" [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optCheckOnly = True}
        -- G0807 of the fontless PDF target comes after them
        take 2 (map diagCode (filter isError (brDiagnostics r))) @?= [DiagnosticCode "G0326", DiagnosticCode "G0221"],
    testCase "HTML lists a Japanese entry with 、 and 。" $
      withBibProject "bibliography = [\"refs.json\"]" "本文[cite jisx4061]。\n\n@bibliography\n" [("refs.json", jaRefsJson)] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        page <- TIO.readFile (tmp </> "build/html/a.xhtml")
        assertBool (T.unpack page) ("JIS X 4061:1996 日本語文字列照合順番、日本規格協会、1996。</li>" `T.isInfixOf` page),
    testCase "the PDF bibliography line has no space before a Latin period" $ do
      (_, m) <- bibOf "bibliography = [\"refs.json\"]" [("refs.json", jaRefsJson)]
      let ls = map rendered (bibliographyLines (Map.map (pure . EntryText) m) [("jisx4061", 1)])
      assertBool (show ls) (not (any ("日本規格協会 ." `T.isInfixOf`) ls))
      assertBool (show ls) (any ("日本規格協会、" `T.isInfixOf`) ls),
    -- golem-doc ADR 0005
    testCase "a type that is not a string is no type" $ do
      (ds, m) <- bibOf "bibliography = [\"refs.json\"]" [("refs.json", TE.encodeUtf8 "[{\"id\": \"a\", \"type\": 1, \"title\": \"組版\"}, {\"id\": \"b\", \"title\": \"組版\"}, {\"id\": \"c\", \"type\": \"book\", \"title\": \"組版\"}]")]
      ds @?= []
      Map.lookup "a" m @?= Map.lookup "b" m
      Map.lookup "c" m @?= Just "『組版』。",
    testCase "a volume as a number or a string is the same; a number that is not an integer is not read" $ do
      (_, m) <- bibOf "bibliography = [\"refs.json\"]" [("refs.json", "[{\"id\": \"n\", \"title\": \"T\", \"container-title\": \"J\", \"volume\": 11}, {\"id\": \"s\", \"title\": \"T\", \"container-title\": \"J\", \"volume\": \"11\"}, {\"id\": \"f\", \"title\": \"T\", \"container-title\": \"J\", \"volume\": 11.5}, {\"id\": \"e\", \"title\": \"T\", \"container-title\": \" \", \"page\": \"\"}]")]
      Map.lookup "n" m @?= Just "T. J, vol. 11."
      Map.lookup "s" m @?= Just "T. J, vol. 11."
      Map.lookup "f" m @?= Just "T. J."
      Map.lookup "e" m @?= Just "T.",
    testCase "the date-parts of accessed as strings are the same as numbers" $ do
      let item d = "{\"id\": \"" <> d <> "\", \"title\": \"T\", \"URL\": \"https://example.com/\", \"accessed\": {\"date-parts\": [" <> (if d == "s" then "[\"2026\", \"10\", \"16\"]" else "[2026, 10, 16]") <> "]}}"
      (_, m) <- bibOf "bibliography = [\"refs.json\"]" [("refs.json", "[" <> item "s" <> ", " <> item "n" <> "]")]
      Map.lookup "s" m @?= Just "T. https://example.com/ (accessed October 16, 2026)."
      Map.lookup "n" m @?= Map.lookup "s" m,
    testCase "HTML: a URL of https is a link of class cs-url; javascript: is a span" $
      withBibProject "bibliography = [\"refs.json\"]" "本文[cite jlreq][cite js]。\n\n@bibliography\n" [("refs.json", urlRefsJson)] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        page <- TIO.readFile (tmp </> "build/html/a.xhtml")
        assertBool (T.unpack page) ("<a class=\"cs-url\" href=\"https://www.w3.org/TR/jlreq/\">https://www.w3.org/TR/jlreq/</a>" `T.isInfixOf` page)
        assertBool (T.unpack page) ("<span class=\"cs-url\">javascript:alert(1)</span>" `T.isInfixOf` page)
        assertBool (T.unpack page) (not ("href=\"javascript" `T.isInfixOf` page))
        css' <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool (T.unpack css') (not ("cs-url" `T.isInfixOf` css')),
    testCase "PDF: the URL of an entry is in the character style url" $ do
      (_, m) <- bibPartsOf "bibliography = [\"refs.json\"]" [("refs.json", urlRefsJson)]
      case bibliographyLines m [("jlreq", 1)] of
        [[Text _ before, CharStyle _ "url" [Text _ u], Text _ after]] -> do
          before @?= "[1] 「日本語組版処理の要件」、W3C、2020、"
          u @?= "https://www.w3.org/TR/jlreq/"
          after @?= "（2026年10月16日閲覧）。"
        other -> assertFailure (show other)
  ]

-- | A Japanese web page with a URL and a date of access, and an entry with a URL of javascript:.
urlRefsJson :: BS.ByteString
urlRefsJson = TE.encodeUtf8 "[{\"id\": \"jlreq\", \"type\": \"webpage\", \"title\": \"日本語組版処理の要件\", \"publisher\": \"W3C\", \"issued\": {\"date-parts\": [[2020]]}, \"URL\": \"https://www.w3.org/TR/jlreq/\", \"accessed\": {\"date-parts\": [[2026, 10, 16]]}}, {\"id\": \"js\", \"title\": \"Script\", \"URL\": \"javascript:alert(1)\"}]"

-- | A line of one box of a width (a page number in the tests of tocPage).
oneBoxLine :: Integer -> Line
oneBoxLine w = Line [Box w (BoxContent "1" False 0 0 0 (plainLook "body" (10 * pt)) 0 0 [] 0 0)] 0 w 0 (0, 0) False (0, 0)

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
  [ testCase "a toc line's leaders end at the same place and its page number ends at the measure" $ do
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
    testCase "a toc line with a wide number, an overfull title, or no leaders" $ do
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
      r <- pagesMini "" (fiveLines <> flatHeadings <> "\n[toc]\nleader = \"none\"\n") "@toc\n\n# 一\n\n本文。\n" [] Map.empty
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
      geom <- either (assertFailure . show) pure (parseStyle (FileId 0) (TE.decodeUtf8 style) >>= pageGeometry (FileId 0) False)
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

smallTable :: T.Text
smallTable = "| 項目 | 値 |\n|:---|---:|\n| 幅 | 10 |\n| 高さ | 20 |\n"

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
    testCase "a table has a grid line of space before and after it (golem-driver ADR 0031)" $ do
      content <- miniPdf fakeProvider True horizontalStyle ("前。\n\n" <> smallTable <> "\n後。\n") [] >>= fmap BS.concat . inflateAll
      [mae, kou, taka, ato] <- mapM (baselineOf content) "前項高後"
      approx (mae - kou) 30
      approx (taka - ato) 30,
    testCase "the rules are c outside the ink of the table: a + c above, d + c below (golem-driver ADR 0031)" $ do
      -- the fake font: ink from 0.8 above to 0.1 below the baseline; a = 8pt, d = 1pt, c = (15 - 9) / 2 = 3pt
      content <- miniPdf fakeProvider True horizontalStyle ("前。\n\n" <> smallTable <> "\n後。\n") [] >>= fmap BS.concat . inflateAll
      [kou, haba, taka] <- mapM (baselineOf content) "項幅高"
      let centres = sort [ptToRational y + ptToRational h / 2 | [_, y, _, h] <- rulesIn content]
      length centres @?= 3
      zipWithM_ approx centres (sort [kou + 11, kou - 4, taka - 4])
      approx haba (kou - 15),
    testCase "an empty header row: two rules, the body after the space (golem-driver ADR 0031)" $ do
      content <- miniPdf fakeProvider True horizontalStyle ("前。\n\n" <> emptyHeaderTable 2 <> "\n後。\n") [] >>= fmap BS.concat . inflateAll
      length (rulesIn content) @?= 2
      [mae, first] <- mapM (baselineOf content) "前行"
      approx (mae - first) 30,
    testCase "an empty header row across pages: two rules on each page, no header (golem-driver ADR 0031)" $ do
      pdf <- miniPdf fakeProvider True fiveLines (emptyHeaderTable 7) []
      pages <- pageContents pdf
      map (length . rulesIn) pages @?= [2, 2],
    testCase "a book that starts with a table: its first row on the first grid line (golem-driver ADR 0031)" $ do
      table <- miniPdf fakeProvider True horizontalStyle smallTable [] >>= fmap BS.concat . inflateAll
      para <- miniPdf fakeProvider True horizontalStyle "項目。\n" [] >>= fmap BS.concat . inflateAll
      a <- baselineOf table '項'
      b <- baselineOf para '項'
      approx a b,
    testCase "vertical: the rules midway between the em boxes, and a line of space before and after (golem-driver ADR 0031)" $ do
      content <- miniPdf fakeProvider True pdfStyle "前。\n\n| 項目 | 値 |\n|---|---|\n| 幅 | 広い |\n\n後。\n" [] >>= fmap BS.concat . inflateAll
      let pitch = 22 / 4 * 72 / 25.4
          xOf c = case [ptToRational (dX d) | d <- drawnGlyphs content, dGlyph d == fromEnum c] of
            (x : _) -> pure x
            [] -> assertFailure (show c)
          near a b = assertBool (show (fromRational a :: Double, fromRational b :: Double)) (abs (a - b) < 1 / 100)
      [mae, kou, haba, ato] <- mapM xOf "前項幅後"
      near (mae - kou) (2 * pitch)
      near (haba - ato) (2 * pitch)
      let centres = sort [ptToRational x + ptToRational w / 2 | [x, _, w, _] <- rulesIn content]
      case centres of
        [c1, c2, c3] -> do
          near c1 (haba - pitch / 2)
          near c2 (kou - pitch / 2)
          near c3 (kou + pitch / 2)
        other -> assertFailure (show other),
    testCase "two tables in a row are a grid line apart (golem-driver ADR 0031)" $ do
      let second = "| 名前 | 数 |\n|---|---|\n| 長 | 1 |\n"
      content <- miniPdf fakeProvider True horizontalStyle ("前。\n\n" <> smallTable <> "\n" <> second <> "\n後。\n") [] >>= fmap BS.concat . inflateAll
      [taka, na] <- mapM (baselineOf content) "高名"
      approx (taka - na) 30,
    testCase "a table right after a heading starts on the next grid line, with no line of space (golem-driver ADR 0031)" $ do
      -- headings of one line on the body grid: the paragraph and the table both one pitch below
      let style = horizontalStyle <> flatHeadings
      toTable <- headingGap style smallTable '項'
      toText <- headingGap style "本文。\n" '本'
      approx toTable 15
      approx toText 15,
    testCase "a table after a heading with a rule after starts where a paragraph would (golem-driver ADR 0031)" $ do
      let style = horizontalStyle <> "\n[headings.1]\nsize = \"1zw\"\nlines = 1\nrule-after = { weight = \"0.5pt\", space-before = \"2pt\", space-after = \"10pt\" }\n"
      toTable <- headingGap style smallTable '項'
      toText <- headingGap style "本文。\n" '本'
      approx toTable toText,
    testCase "HTML keeps an empty header row as an empty row of the head (golem-driver ADR 0031)" $ do
      (html, _) <- htmlMini horizontalStyle (emptyHeaderTable 2)
      assertBool (T.unpack html) ("<thead>" `T.isInfixOf` html),
    testCase "tables: parallel and sequential, and two builds, give the same bytes" $ do
      let source = "前。\n\n" <> smallTable <> "\n後。\n\n" <> smallTable
      a <- miniPdf fakeProvider True horizontalStyle source []
      b <- miniPdf fakeProvider False horizontalStyle source []
      c <- miniPdf fakeProvider True horizontalStyle source []
      a @?= b
      a @?= c
      qpdfCheck a
  ]

-- | How far below the heading 章 the first line after it is, by a character of that line, in pt.
headingGap :: BS.ByteString -> T.Text -> Char -> IO Rational
headingGap style after c = do
  content <- miniPdf fakeProvider True style ("# 章\n\n" <> after) [] >>= fmap BS.concat . inflateAll
  (-) <$> baselineOf content '章' <*> baselineOf content c

-- | A table whose header row has only empty cells, with n body rows 行1, 行2, ...
emptyHeaderTable :: Int -> T.Text
emptyHeaderTable n = "| | |\n|---|---|\n" <> T.concat ["| 行" <> T.pack (show i) <> " | " <> T.pack (show i) <> " |\n" | i <- [1 .. n]]

-- | Two lengths in pt within 1/100pt.
approx :: Rational -> Rational -> Assertion
approx a b = assertBool (show (fromRational a :: Double, fromRational b :: Double)) (abs (a - b) < 1 / 100)

-- | The baseline in pt of the first glyph of a character drawn.
baselineOf :: BS.ByteString -> Char -> IO Rational
baselineOf content c = case [ptToRational (dY d) | d <- drawnGlyphs content, dGlyph d == fromEnum c] of
  (y : _) -> pure y
  [] -> assertFailure ("no " <> [c])

-- | A one-column style of 32 characters a line, the column gap 2zw (docs/adr ADR 0025).
horizontal32 :: BS.ByteString
horizontal32 = replaceIn "characters = 12" "characters = 32" (replaceIn "columns = 1" "columns = 1\ncolumn-gap = \"2zw\"" horizontalStyle)

-- | A style with [index] of @n@ columns after it.
withIndexColumns :: T.Text -> BS.ByteString -> BS.ByteString
withIndexColumns n style = style <> "\n[index]\ncolumns = " <> BC.pack (T.unpack n) <> "\n"

-- | Forty index marks, each on its own term, then a heading and the index.
indexSource :: T.Text
indexSource =
  T.concat ["本文[index reading=" <> r <> ": 語" <> r <> "]。" | r <- indexReadings] <> "\n\n# 索引\n\n@index\n"

indexReadings :: [T.Text]
indexReadings = [a <> b | a <- ["あ", "い", "う", "え", "お"], b <- ["か", "き", "く", "け", "こ", "さ", "し", "す"]]

-- | The lines of the index entries on a page.
indexLinesOn :: PdfLayout -> PageOut -> [SetLine]
indexLinesOn pl p = [sl | (_, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines pl)], "語" `T.isPrefixOf` setLineText sl]

indexColumnTests :: [TestTree]
indexColumnTests =
  [ testCase "PDF: one column of 32 characters, two index columns 2zw apart are 15 characters wide" $ do
      let style = withIndexColumns "2" (replaceIn "lines = 30" "lines = 10" horizontal32)
      (geom, pl) <- layoutOk style indexSource []
      let entries = [sl | p <- plPages pl, sl <- indexLinesOn pl p]
      assertBool "entries" (not (null entries))
      nub [lineTarget (slLine sl) | sl <- entries] @?= [15 * 10 * pt]
      nub [csMeasure (poColumnSet p) | p <- plPages pl, not (null (indexLinesOn pl p))] @?= [15 * 10 * pt]
      content <- miniPdf fakeProvider True style indexSource [] >>= pageContents
      let ta = typeAreaFor geom 1
          x1 = TE.encodeUtf8 (spToPt (rectX ta + 17 * 10 * pt))
      assertBool "the second column starts 17 characters on" (any (any ((== x1) . dX) . drawnGlyphs) (take 1 content)),
    testCase "PDF: the lines of the index columns are on the grid of the type area" $ do
      let style = withIndexColumns "2" (replaceIn "lines = 30" "lines = 10" horizontal32)
      (geom, _) <- layoutOk style indexSource []
      content <- miniPdf fakeProvider True style indexSource [] >>= pageContents
      let ta = typeAreaFor geom 1
          x1 = TE.encodeUtf8 (spToPt (rectX ta + 17 * 10 * pt))
          grid = [TE.encodeUtf8 (spToPt (rectY ta + rectH ta - g)) | g <- pgLineGrid geom]
          ys = [dY d | c <- content, d <- drawnGlyphs c, dX d == x1]
      assertBool "lines" (not (null ys))
      assertBool (show ys) (all (`elem` grid) ys),
    testCase "PDF: the running head is drawn once on the page of the switch and on the index pages" $ do
      let style = withIndexColumns "2" (replaceIn "lines = 30" "lines = 10" horizontal32) <> "\n[masters.body]\nrunning-head = { position = \"top-outside\", content = \"title\" }\n"
      content <- miniPdf fakeProvider True style indexSource [] >>= pageContents
      assertBool "pages" (length content >= 2)
      map (\c -> length [d | d <- drawnGlyphs c, dGlyph d == fromEnum 'T']) content @?= map (const 1) content,
    testCase "PDF: without [index], or with as many columns as the page, the bytes are the same" $ do
      let style = replaceIn "lines = 30" "lines = 10" horizontal32
      a <- miniPdf fakeProvider True style indexSource []
      b <- miniPdf fakeProvider True (withIndexColumns "1" style) indexSource []
      c <- miniPdf fakeProvider True (withIndexColumns "1" style <> "column-gap = \"5zw\"\n") indexSource []
      -- the instance ID is made from every input, style.toml among them (docs/adr/0004)
      let body = fst . BS.breakSubstring "trailer"
      body a @?= body b
      body a @?= body c,
    testCase "G0744: index columns under 8 characters, at the value of columns, also in golem check" $ do
      let style = withIndexColumns "5" horizontalStyle
          src = BC.unpack style
          at = length (takeWhile (/= "[index]") (lines src))
          offset = sum (map ((+ 1) . length) (take at (lines src))) + length ("[index]\ncolumns = " :: String)
      b <- buildMarksFilesWith indexSource id (Just (style <> fakeBody)) fakeFontFiles
      map diagMessage (ofCode "G0744" b) @?= ["索引の段の行長が足りません。columns を減らすか column-gap を狭めてください"]
      map (whereIs b) (ofCode "G0744" b) @?= [(Just "style.toml", offset)]
      bPdf b @?= Nothing
      c <- buildMarksFilesWith indexSource (\o -> o {optCheckOnly = True}) (Just (style <> fakeBody)) fakeFontFiles
      map diagCode (ofCode "G0744" c) @?= [DiagnosticCode "G0744"],
    testCase "PDF: with a sidenote column, two index columns are not G0701 and leave the column out" $ do
      let style = withIndexColumns "2" (replaceIn "characters = 12" "characters = 24" sidenoteStyle) <> "column-gap = \"2zw\"\n"
      (_, pl) <- layoutOk style indexSource []
      nub [lineTarget (slLine sl) | p <- plPages pl, sl <- indexLinesOn pl p] @?= [11 * 10 * pt],
    testCase "PDF: a page reference after an index of fewer pages converges on the right page" $ do
      let style = withIndexColumns "2" (replaceIn "lines = 30" "lines = 10" horizontal32)
          source = "参照は[ref-page later]ページ。\n\n" <> indexSource <> "\n@label later\n後。\n"
      (_, pl) <- layoutOk style source []
      later <- maybe (assertFailure "later") pure (Map.lookup "later" (labelPages (plPages pl)))
      let refLine = [setLineText sl | sl <- Map.elems (plLines pl), "参照は" `T.isPrefixOf` setLineText sl]
      refLine @?= ["参照は" <> T.pack (show later) <> "ページ。"]
      let one = withIndexColumns "1" (replaceIn "lines = 30" "lines = 10" horizontal32)
      (_, pl1) <- layoutOk one source []
      assertBool "fewer pages" (Map.lookup "later" (labelPages (plPages pl1)) > Just later),
    testCase "PDF: vertical, the index columns run from top to bottom" $ do
      let style = withIndexColumns "2" pdfStyle <> "column-gap = \"2zw\"\n"
      (geom, pl) <- layoutOk style indexSource []
      nub [lineTarget (slLine sl) | p <- plPages pl, sl <- indexLinesOn pl p] @?= [20 * pgFontSize geom]
      content <- miniPdf fakeProvider True style indexSource [] >>= pageContents
      let ta = typeAreaFor geom 1
          ta2 = typeAreaFor geom 2
          y1 r = TE.encodeUtf8 (spToPt (rectY r + rectH r - 22 * pgFontSize geom))
      assertBool "a glyph at the top of the second column" (any (any (\d -> dY d `elem` [y1 ta, y1 ta2]) . drawnGlyphs) content),
    testCase "HTML and EPUB: [index] columns change nothing" $ do
      let out style = withSystemTempDirectory "golem-index-columns" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
            BS.writeFile (tmp </> "style.toml") style
            BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 indexSource)
            r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            buildFiles (tmp </> "build")
      one <- out horizontalStyle
      two <- out (withIndexColumns "2" horizontalStyle)
      assertBool "files" (not (Map.null one))
      two @?= one
  ]
