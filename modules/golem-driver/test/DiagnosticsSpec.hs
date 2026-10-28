module DiagnosticsSpec (explainTests, noticeTests, projectDiagnosticTests, readingTests, evalDiagnosticTests, outputDiagnosticTests) where

import Control.Monad (filterM, forM)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isDigit)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isSuffixOf, nub, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.Explain (Explanation (..), Status (..), catalog, codeDescriptionUrl, explainHint, lookupExplanation, parseCatalog)
import Golem.Driver.Fonts (golemFontProvider)
import Golem.Driver.Pdf (Assumed (..), fixpoint)
import Golem.Layout.Paginate (ColumnSet (..), PageOut (..))
import Golem.Project (ProjectFailure (..))
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.Directory (createDirectoryIfMissing, createFileLink, doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The reading stage of every file of a project (golem-parser ADR 0009).
readingTests :: [TestTree]
readingTests =
  [ testCase "an imported file with CRLF is shown at its path" $
      withChapters "" [("a.gm", "@import y.gm as y\n\n一。\n")] [("y.gm", "a\r\nb\n")] $ \tmp -> do
        (codes, out) <- checked tmp
        codes @?= [DiagnosticCode "G01003"]
        assertBool (T.unpack out) ("y.gm:1:2:" `T.isPrefixOf` out),
    testCase "manifest.toml with CRLF is G01003 at manifest.toml" $
      withChapters "" [("a.gm", "一。\n")] [] $ \tmp -> do
        m <- BS.readFile (tmp </> "manifest.toml")
        BS.writeFile (tmp </> "manifest.toml") (BS.intercalate "\r\n" (BS.split 10 m))
        (codes, out) <- checked tmp
        codes @?= [DiagnosticCode "G01003"]
        assertBool (T.unpack out) ("manifest.toml:" `T.isPrefixOf` out),
    testCase "style.toml with a BOM is G01002, not G03006" $
      withChapters "\xEF\xBB\xBF[page]\n" [("a.gm", "一。\n")] [] $ \tmp -> do
        (codes, out) <- checked tmp
        codes @?= [DiagnosticCode "G01002"]
        assertBool (T.unpack out) ("style.toml:1:1:" `T.isPrefixOf` out),
    testCase "style.toml with CRLF is G01003, with no fix" $
      withChapters "[lists]\r\n" [("a.gm", "一。\n")] [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optCheckOnly = True}
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G01003"]
        concatMap diagFixes (brDiagnostics r) @?= [],
    testCase "an empty expression is one G01020" $
      withChapters "" [("a.gm", "[=]\n")] [] $ \tmp -> do
        (codes, _) <- checked tmp
        codes @?= [DiagnosticCode "G01020"]
  ]
  where
    checked tmp = do
      r <- build (defaultOptions tmp) {optCheckOnly = True}
      pure (map diagCode (brDiagnostics r), renderHuman (brSources r) (brDiagnostics r))

-- | G03007 once per name and the positions of a failed load (golem-project ADR 0006).
projectDiagnosticTests :: [TestTree]
projectDiagnosticTests =
  [ testCase "G03007 once per missing master page" $
      withEntries "" ["\"a.gm\"", "{ file = \"b.gm\", master = \"nope\" }", "{ file = \"c.gm\", master = \"nope\" }"] [("a.gm", "一。\n"), ("b.gm", "二。\n"), ("c.gm", "三。\n")] [] $ \tmp -> do
        ds <- g03007 tmp
        ds @?= ["style.toml にないマスターページです: nope"],
    testCase "no G03007 for a master page of style.toml" $
      withEntries "[masters.body]\n" ["{ file = \"a.gm\", master = \"body\" }"] [("a.gm", "一。\n")] [] $ \tmp ->
        g03007 tmp >>= (@?= []),
    testCase "no G03007 after a syntax error" $
      withEntries "" ["{ file = \"a.gm\", master = \"nope\" }"] [("a.gm", "[strong: 閉じない\n")] [] $ \tmp ->
        g03007 tmp >>= (@?= []),
    testCase "a failed style.toml is shown at style.toml" $
      withEntries "[page]\nunknown = 1\n" ["\"a.gm\""] [("a.gm", "一。\n")] [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optCheckOnly = True}
        assertBool "style.toml is a source" (isJust (sourceFileId r "style.toml"))
        let out = renderHuman (brSources r) (brDiagnostics r)
        assertBool (T.unpack out) ("style.toml:" `T.isPrefixOf` out),
    testCase "a missing chapter is shown at manifest.toml" $
      withEntries "" ["\"nope.gm\""] [] [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optCheckOnly = True}
        let out = renderHuman (brSources r) (brDiagnostics r)
        assertBool (T.unpack out) ("manifest.toml:1:1:" `T.isPrefixOf` out)
  ]
  where
    g03007 tmp = do
      ev <- evaluateProject Dev tmp
      case ev of
        Left f -> assertFailure (show (pfDiagnostics f))
        Right e -> pure [diagMessage d | d <- evDiagnostics e, diagCode d == DiagnosticCode "G03007"]

-- | 'buildMarks' with extra files written.
buildMarksFiles :: (BuildOptions -> BuildOptions) -> Maybe BS.ByteString -> [(FilePath, BS.ByteString)] -> IO Built
buildMarksFiles = buildMarksFilesWith "本文。\n"

-- | The manifest of 'noticeProject' with the four targets and more text after it.
noticeManifest :: BS.ByteString -> BS.ByteString
noticeManifest extra = miniManifest <> "\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\n" <> extra

-- | A source that gives every notice but G03023.
noticeSource :: BS.ByteString
noticeSource =
  "@style-def paragraph body indent=1zw\n\n# A\n\n[tcy: 10]\n\n@style verse\n  \\ x\n  y\n\n@listing src=code.hs\n\n@number 1\n+ a\n+ b\n\n@page-break\n"

noticeProject :: BS.ByteString -> BS.ByteString -> [(FilePath, BS.ByteString)]
noticeProject extra source =
  [("manifest.toml", noticeManifest extra), ("style.toml", withBodyFont horizontalStyle), ("a.gm", source), ("code.hs", "main = pure ()\n")] <> fakeFontFiles

-- | silence-info of every code of 'infoCodes' (docs/adr 0104).
silenceAllInfo :: BS.ByteString
silenceAllInfo = "\n[diagnostics]\nsilence-info = [" <> BS.intercalate ", " [TE.encodeUtf8 ("\"" <> c <> "\"") | DiagnosticCode c <- infoCodes] <> "]\n"

-- | silence-notices of every code of 'noticeCodes'.
silenceAllNotices :: BS.ByteString
silenceAllNotices = "\n[diagnostics]\nsilence-notices = [" <> BS.intercalate ", " [TE.encodeUtf8 ("\"" <> c <> "\"") | DiagnosticCode c <- noticeCodes] <> "]\n"

{- | Projects that together give every notice of 'noticeCodes' and, with
--verbose, every info of 'infoCodes' (docs/adr 0104), as functions
of more manifest text. The first builds the four targets. G03023 needs a
project without style.toml, which has no fonts for the PDF (G08007), and so
the second builds the other three.
-}
everyNoticeProjects :: [BS.ByteString -> [(FilePath, BS.ByteString)]]
everyNoticeProjects =
  [ \extra -> [("manifest.toml", noticeManifest extra), ("style.toml", withBodyFont style), ("a.gm", TE.encodeUtf8 source), ("code.hs", "main = pure ()\n"), ("images/tall.svg", tall)] <> fakeFontFiles,
    \extra -> [("manifest.toml", replaceIn "[targets.pdf]\n" "" (noticeManifest extra)), ("a.gm", "x\n")]
  ]
  where
    -- five lines of 12 characters, a paragraph style with rules, and a zero indent of caption (G03100)
    style = replaceIn "lines = 30" "lines = 5" horizontalStyle <> "\n[paragraph-styles.sec]\nrule-before = { weight = \"0.5pt\" }\nrule-after = { weight = \"0.5pt\" }\n\n[paragraph-styles.caption]\nindent = \"0zw\"\n"
    tall = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"300\"><rect width=\"100\" height=\"300\" fill=\"none\"/></svg>"
    source =
      T.concat
        [ TE.decodeUtf8 noticeSource,
          "\n本文。\n\n@style verse\n  ab\\ \n  cd\n\n", -- G02079
          "[ruby: [kenten: 漢]|かん]\n\n", -- G07045
          "```\nabcdefghijklmnopqrstuvwxyzabcd\n```\n\n", -- G07030
          "@figure images/tall.svg alt=\"t\"\n  キャプション。\n\n", -- G07039, with a caption for G03100
          "@style sec\n  " <> T.replicate 96 "あ" <> "\n\n", -- G07046
          "a\n\n@page-break\n\n@blank-line\n\nb\n\n", -- G07047 (an info)
          "@blank-line\n@blank-line\n\nc\n\n", -- G02094
          "@blank-line 5\n\nd\n\n", -- G04011
          "@page-break\n\n@page-lines -4\n\n# H\n\ne\n\n", -- G07100
          "@page-break\n\n@blank-line\n" -- G04008 and G04009
        ]

-- | The PDF without its instance ID, which is computed from the text of manifest.toml.
withoutInstanceId :: (FilePath, BS.ByteString) -> (FilePath, BS.ByteString)
withoutInstanceId (p, b)
  | ".pdf" `isSuffixOf` p =
      let (before, rest) = BS.breakSubstring "/ID [" b
       in (p, before <> BS.drop 1 (BC.dropWhile (/= ']') rest))
  | otherwise = (p, b)

codesOf :: [Diagnostic] -> [T.Text]
codesOf ds = [c | DiagnosticCode c <- map diagCode ds]

noticeTests :: TestTree
noticeTests =
  testGroup
    "notices (golem-syntax ADR 0002)"
    [ testCase "the notices of a project" $ do
        n <- buildNotified (noticeProject "" noticeSource) id
        -- the @listing is code and style.toml has no [fonts.code]: G08008 (golem-driver ADR 0017)
        codesOf (nDiagnostics n) @?= ["G02062", "G02063", "G02064", "G02065", "G04007", "G04008", "G08008"]
        map diagSeverity (nDiagnostics n) @?= replicate 7 Notice,
      -- golem-driver ADR 0043
      testCase "G03100: a zero indent of caption in style.toml is a notice at style.toml; silence-notices drops it" $ do
        let style = withBodyFont horizontalStyle <> "\n[paragraph-styles.caption]\nindent = \"0zw\"\n"
            files extra = [("manifest.toml", noticeManifest extra), ("style.toml", style), ("a.gm", "abc\n")] <> fakeFontFiles
        n <- buildNotified (files "") id
        [(diagCode d, diagSeverity d, diagMessage d) | d <- nDiagnostics n]
          @?= [(DiagnosticCode "G03100", Notice, "キャプションと傍注は字下げを掛けないので、caption.indent = \"0zw\" は効果がありません")]
        assertBool "outputs" (not (null (nOutputs n)))
        quiet <- buildNotified (files "\n[diagnostics]\nsilence-notices = [\"G03100\"]\n") id
        nDiagnostics quiet @?= [],
      testCase "silence-notices drops those notices only" $ do
        n <- buildNotified (noticeProject "\n[diagnostics]\nsilence-notices = [\"G02063\", \"G04008\"]\n" noticeSource) id
        codesOf (nDiagnostics n) @?= ["G02062", "G02064", "G02065", "G04007", "G08008"],
      -- golem-parser ADR 0012
      testCase "G02079: an escaped space at the end of a verse line is dropped, and silence-notices drops G02079" $ do
        let verse = "@style verse\n  ab\\ \n  cd\n"
        n <- buildNotified (noticeProject "" verse) id
        codesOf (nDiagnostics n) @?= ["G02079"]
        let texts = [t | (fp, t) <- nOutputs n, ".txt" `isSuffixOf` fp]
        [fp | (fp, _) <- nOutputs n, ".txt" `isSuffixOf` fp] @?= ["text/horizontal/a.txt", "text/vertical/a.txt"]
        assertBool (show texts) (all ("ab\ncd" `BS.isInfixOf`) texts)
        quiet <- buildNotified (noticeProject "\n[diagnostics]\nsilence-notices = [\"G02079\"]\n" verse) id
        codesOf (nDiagnostics quiet) @?= [],
      -- docs/adr ADR 0046, docs/adr 0104
      testCase "G07047 is an info at a blank line dropped at the top of a column, given with --verbose only" $ do
        let src = "a\n\n@page-break\n\n@blank-line\n\nb\n"
        quiet <- buildNotified (noticeProject "" src) id
        codesOf (nDiagnostics quiet) @?= []
        n <- buildNotified (noticeProject "" src) (\o -> o {optVerbose = True})
        [(c, diagSeverity d, spanStart (diagSpan d)) | d <- nDiagnostics n, let { DiagnosticCode c = diagCode d }] @?= [("G07047", Info, 16)]
        map withoutInstanceId (nOutputs n) @?= map withoutInstanceId (nOutputs quiet),
      testCase "silence-info drops G07047 even with --verbose (docs/adr 0104)" $ do
        let src = "a\n\n@page-break\n\n@blank-line\n\nb\n"
        n <- buildNotified (noticeProject "\n[diagnostics]\nsilence-info = [\"G07047\"]\n" src) (\o -> o {optVerbose = True})
        codesOf (nDiagnostics n) @?= [],
      testCase "silence-notices with G07047 is G03024 (docs/adr 0104)" $ do
        let src = "a\n\n@page-break\n\n@blank-line\n\nb\n"
        n <- buildNotified (noticeProject "\n[diagnostics]\nsilence-notices = [\"G07047\"]\n" src) id
        codesOf (nDiagnostics n) @?= ["G03024"],
      testCase "--verbose with --no-notices gives the infos and no notice (docs/adr 0104)" $ do
        let src = noticeSource <> "\na\n\n@page-break\n\n@blank-line\n\nb\n"
        n <- buildNotified (noticeProject "" src) (\o -> o {optVerbose = True, optNoNotices = True})
        codesOf (nDiagnostics n) @?= ["G07047"]
        loud <- buildNotified (noticeProject "" src) (\o -> o {optVerbose = True})
        -- the notices first, the info last
        assertBool (show (codesOf (nDiagnostics loud))) (length (nDiagnostics loud) > 1)
        drop (length (nDiagnostics loud) - 1) (codesOf (nDiagnostics loud)) @?= ["G07047"]
        [diagSeverity d | d <- nDiagnostics loud, diagSeverity d /= Info] @?= replicate (length (nDiagnostics loud) - 1) Notice,
      testCase "--no-notices drops every notice and keeps the errors" $ do
        n <- buildNotified (noticeProject "" (noticeSource <> "\n[unknown: x]\n")) (\o -> o {optNoNotices = True})
        codesOf (nDiagnostics n) @?= ["G02022"]
        n' <- buildNotified (noticeProject "" (noticeSource <> "\n[unknown: x]\n")) id
        take 1 (codesOf (nDiagnostics n')) @?= ["G02022"]
        assertBool "notices after the error" (length (nDiagnostics n') > 1),
      -- the spec: a notice or an info does not change the bytes of the outputs (docs/adr 0104)
      testCase "no notice of noticeCodes and no info of infoCodes changes the outputs of the four targets" $ do
        raised <- forM everyNoticeProjects $ \project -> do
          loud <- buildNotified (project "") id
          [diagCode d | d <- nDiagnostics loud, diagSeverity d /= Notice] @?= []
          quiet <- buildNotified (project silenceAllNotices) id
          nDiagnostics quiet @?= []
          map withoutInstanceId (nOutputs quiet) @?= map withoutInstanceId (nOutputs loud)
          none <- buildNotified (project "") (\o -> o {optNoNotices = True})
          nDiagnostics none @?= []
          nOutputs none @?= nOutputs loud
          verbose <- buildNotified (project "") (\o -> o {optVerbose = True})
          [diagCode d | d <- nDiagnostics verbose, diagSeverity d `notElem` [Notice, Info]] @?= []
          [d | d <- nDiagnostics verbose, diagSeverity d /= Info] @?= nDiagnostics loud
          nOutputs verbose @?= nOutputs loud
          silencedInfo <- buildNotified (project silenceAllInfo) (\o -> o {optVerbose = True})
          nDiagnostics silencedInfo @?= nDiagnostics loud
          map withoutInstanceId (nOutputs silencedInfo) @?= map withoutInstanceId (nOutputs loud)
          pure (map diagCode (nDiagnostics loud), [diagCode d | d <- nDiagnostics verbose, diagSeverity d == Info], map fst (nOutputs loud))
        -- a new notice or info must be added to the projects
        sort (nub (concatMap (\(n, _, _) -> n) raised)) @?= sort noticeCodes
        sort (nub (concatMap (\(_, i, _) -> i) raised)) @?= sort infoCodes
        let written = concatMap (\(_, _, w) -> w) raised
        assertBool (show written) (all (\ext -> any (ext `isSuffixOf`) written) [".pdf", ".epub", ".xhtml", ".txt"]),
      testCase "the path of @listing as the first argument gives the same outputs as src=" $ do
        let (pre, post) = BS.breakSubstring "src=code.hs" noticeSource
            positional = pre <> "code.hs" <> BS.drop (BS.length "src=code.hs") post
        a <- buildNotified (noticeProject "" noticeSource) id
        b <- buildNotified (noticeProject "" positional) id
        map withoutInstanceId (nOutputs b) @?= map withoutInstanceId (nOutputs a)
        assertBool "no G02065" ("G02065" `notElem` codesOf (nDiagnostics b)),
      testCase "G03023: no style.toml, at the start of manifest.toml" $ do
        let files = [("manifest.toml", TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["html", "epub", "text"]})), ("a.gm", "x\n")]
        n <- buildNotified files id
        [(diagCode d, diagSeverity d, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- nDiagnostics n] @?= [(DiagnosticCode "G03023", Notice, 0, 0)]
        q <- buildNotified files (\o -> o {optNoNotices = True})
        nDiagnostics q @?= []
        nOutputs q @?= nOutputs n
        withStyle <- buildNotified (("style.toml", "") : files) id
        codesOf (nDiagnostics withStyle) @?= [],
      testCase "G03023 comes with G08007 when the PDF has no fonts" $ do
        n <- buildNotified [("manifest.toml", miniManifest), ("a.gm", "x\n")] id
        -- no page either (G07001); the notice comes after the errors
        let cs = codesOf (nDiagnostics n)
        assertBool (show cs) ("G08007" `elem` cs)
        drop (length cs - 1) cs @?= ["G03023"]
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
          testCase "every code in the catalog is G, the two digits of a stage and three digits (docs/adr 0061)" $ do
            let stages = ["01", "02", "03", "04", "05", "06", "07", "08", "09"]
                malformed c = T.length c /= 6 || T.take 2 (T.drop 1 c) `notElem` stages
            assertBool "a catalog" (not (Map.null catalog))
            filter malformed (Map.keys catalog) @?= [],
          testCase "no code of four digits is in the sources (docs/adr 0061)" $ do
            pkgs <- listDirectory ".."
            dirs <- filterM doesDirectoryExist ([".." </> p </> "src" | p <- pkgs] <> ["../golem-cli/app"])
            files <- concat <$> mapM haskellFiles dirs
            old <- concat <$> mapM (fmap (quotedCodesOf 4) . TIO.readFile) files
            old @?= [],
          testCase "no retired code is in the sources" $ do
            used <- sourceCodes
            [c | (c, e) <- Map.toList catalog, exStatus e == Retired, c `elem` used] @?= [],
          testCase "the profile-dependent codes, and only they, are a warning in dev and an error in prod" $ do
            let dependent = [c | DiagnosticCode c <- profileDependentCodes]
                isDependent e = "- 重大度: dev では警告、prod ではエラー" `elem` T.lines (exBody e)
            assertBool "some profile-dependent codes" (not (null dependent))
            sort [c | (c, e) <- Map.toList catalog, isDependent e] @?= sort dependent,
          testCase "the infos of the catalog are infoCodes (docs/adr 0104)" $ do
            let isInfo e = "- 重大度: 情報" `elem` T.lines (exBody e)
            sort [c | (c, e) <- Map.toList catalog, exStatus e == InUse, isInfo e] @?= sort [c | DiagnosticCode c <- infoCodes],
          testCase "the notices of the catalog are noticeCodes (golem-syntax ADR 0002)" $ do
            let isNotice e = "- 重大度: お知らせ" `elem` T.lines (exBody e)
            sort [c | (c, e) <- Map.toList catalog, exStatus e == InUse, isNotice e] @?= sort [c | DiagnosticCode c <- noticeCodes],
          testCase "the preflight codes of the catalog are preflightCodes (golem-cli ADR 0006)" $ do
            let isPreflight e = any ("- 重大度: プリフライトの設定による" `T.isPrefixOf`) (T.lines (exBody e))
            sort [c | (c, e) <- Map.toList catalog, exStatus e == InUse, isPreflight e] @?= sort [c | DiagnosticCode c <- preflightCodes],
          testCase "the catalog has G02044 retired" $
            fmap exStatus (lookupExplanation "G02044") @?= Just Retired,
          testCase "golem explain G03029 explains it (golem-driver ADR 0041)" $
            fmap (\e -> (exStatus e, exTitle e)) (lookupExplanation "G03029") @?= Just (InUse, "隠しノンブルが仕上がりの線を越えます"),
          testCase "G02095 is in use and in the sources (golem-eval ADR 0006)" $ do
            fmap exStatus (lookupExplanation "G02095") @?= Just InUse
            used <- sourceCodes
            assertBool "G02095 in the sources" ("G02095" `elem` used),
          testCase "G02096, G02097, G02098 and G02099 are in use and in the sources (docs/adr ADR 0056, ADR 0060)" $ do
            map (fmap exStatus . lookupExplanation) ["G02096", "G02097", "G02098", "G02099"] @?= replicate 4 (Just InUse)
            used <- sourceCodes
            [c | c <- ["G02096", "G02097", "G02098", "G02099"], c `notElem` used] @?= []
        ],
      testGroup
        "the form of the document"
        [ testCase "two good sections give their titles, statuses and bodies" $
            case parseCatalog (T.unlines (preamble <> inUse "G01001" <> retired "G02044")) of
              Left e -> assertFailure (T.unpack e)
              Right es -> do
                map exCode es @?= ["G01001", "G02044"]
                map exTitle es @?= ["G01001 の題", "G02044 の題"]
                map exStatus es @?= [InUse, Retired]
                map exBody es @?= [T.intercalate "\n" (dropLast (inUse "G01001")), T.intercalate "\n" (dropLast (retired "G02044"))],
          bad "no 直し方" (preamble <> inUse "G01001" <> without "### 直し方" (inUse "G01002")) "## G01002",
          bad "no title" (preamble <> inUse "G01001" <> without "G01002 の題" (inUse "G01002")) "## G01002",
          bad "no status" (preamble <> inUse "G01001" <> without "- 状態: 使用中" (inUse "G01002")) "## G01002",
          bad "a bad severity" (preamble <> inUse "G01001" <> map (\l -> if l == "- 重大度: エラー" then "- 重大度: 致命的" else l) (inUse "G01002")) "- 重大度: 致命的",
          testCase "お知らせ is a severity (golem-syntax ADR 0002)" $
            fmap (map exCode) (parseCatalog (T.unlines (preamble <> inUse "G01001" <> map (\l -> if l == "- 重大度: エラー" then "- 重大度: お知らせ" else l) (inUse "G01002")))) @?= Right ["G01001", "G01002"],
          testCase "a severity by the preflight rules, with the default of print (golem-cli ADR 0006)" $
            fmap (map exCode) (parseCatalog (T.unlines (preamble <> inUse "G01001" <> map (\l -> if l == "- 重大度: エラー" then "- 重大度: プリフライトの設定による（print では警告）" else l) (inUse "G01002")))) @?= Right ["G01001", "G01002"],
          testCase "情報 is a severity (docs/adr 0104)" $
            fmap (map exCode) (parseCatalog (T.unlines (preamble <> inUse "G01001" <> map (\l -> if l == "- 重大度: エラー" then "- 重大度: 情報" else l) (inUse "G01002")))) @?= Right ["G01001", "G01002"],
          bad "a severity that is none of the five" (preamble <> inUse "G01001" <> map (\l -> if l == "- 重大度: エラー" then "- 重大度: ヒント" else l) (inUse "G01002")) "- 重大度: ヒント",
          bad "out of order" (preamble <> inUse "G01002" <> inUse "G01001") "## G01001",
          bad "a code twice" (preamble <> inUse "G01001" <> inUse "G01001") "## G01001",
          testCase "a retired section without 主な原因 is accepted" $
            fmap (map exCode) (parseCatalog (T.unlines (preamble <> retired "G02044"))) @?= Right ["G02044"]
        ],
      testGroup
        "lookup, hint and URL"
        [ testCase "a code is explained whatever its case" $ do
            fmap exCode (lookupExplanation "g01017") @?= Just "G01017"
            fmap exCode (lookupExplanation "G01017") @?= Just "G01017"
            fmap exCode (lookupExplanation "G9999") @?= Nothing,
          testCase "the explain hint names the smallest documented code, once" $ do
            let d c = diagnostic c Error (SrcSpan (FileId 0) 0 0) "m"
            explainHint [d "G04003", d "G01017", d "X001"] @?= "コードの説明は golem explain <コード> で表示できます（例: golem explain G01017）"
            explainHint [d "X001"] @?= ""
            explainHint [] @?= "",
          testCase "a code's description URL points at its section on main" $ do
            codeDescriptionUrl (DiagnosticCode "G01017") @?= Just "https://github.com/tett23/golem/blob/main/docs/diagnostics.md#g01017"
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

{- | The codes in the sources: the strings @"G@, five digits and @"@ in the
Haskell files under ../*/src and ../golem-cli/app (not the tests, which
write codes to cause errors).
-}
sourceCodes :: IO [T.Text]
sourceCodes = do
  pkgs <- listDirectory ".."
  dirs <- filterM doesDirectoryExist ([".." </> p </> "src" | p <- pkgs] <> ["../golem-cli/app"])
  files <- concat <$> mapM haskellFiles dirs
  codes <- mapM (fmap (quotedCodesOf 5) . TIO.readFile) files
  pure (sort (nub (concat codes)))

haskellFiles :: FilePath -> IO [FilePath]
haskellFiles dir = do
  entries <- map (dir </>) <$> listDirectory dir
  dirs <- filterM doesDirectoryExist entries
  nested <- concat <$> mapM haskellFiles dirs
  pure ([e | e <- entries, ".hs" `isSuffixOf` e, e `notElem` dirs] <> nested)

-- | The strings @"G@, @n@ digits and @"@ in a source.
quotedCodesOf :: Int -> T.Text -> [T.Text]
quotedCodesOf n src =
  [ code
  | (_, rest) <- T.breakOnAll "\"G" src,
    let code = T.take (n + 1) (T.drop 1 rest),
    T.length code == n + 1,
    T.all isDigit (T.drop 1 code),
    T.take 1 (T.drop (n + 2) rest) == "\""
  ]

-- | The fixture copied to @root@ with @src@ after its chapter 02.
withChapter :: FilePath -> BS.ByteString -> IO Int
withChapter root src = do
  copyTree fixture root
  before <- BS.readFile (root </> "chapters/02.gm")
  BS.writeFile (root </> "chapters/02.gm") (before <> "\n" <> src)
  pure (BS.length before + 1)

-- | The diagnostics of evaluation (G02xxx) of a check of @root@.
evalDiags :: FilePath -> IO [(T.Text, T.Text, Int, Int)]
evalDiags root = do
  r <- build (defaultOptions root) {optCheckOnly = True}
  pure
    [ (c, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d))
    | d <- brDiagnostics r,
      let DiagnosticCode c = diagCode d,
      "G02" `T.isPrefixOf` c
    ]

-- | golem-eval ADR 0003: the paths of assets and G02008 in S1.
evalDiagnosticTests :: TestTree
evalDiagnosticTests =
  testGroup
    "evaluation diagnostics (golem-eval ADR 0003)"
    [ testCase "absolute paths, URLs and paths outside the root are G02060" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        let root = tmp </> "book"
        at <- withChapter root "@figure /tmp/a.png alt=x\n\n@figure \"https://example.com/a.png\" alt=x\n\n@listing ../outside.txt\n"
        ds <- evalDiags root
        [(c, m) | (c, m, _, _) <- ds]
          @?= [ ("G02060", "絶対パスは使えません: /tmp/a.png"),
                ("G02060", "URL は使えません: https://example.com/a.png"),
                ("G02060", "プロジェクトルートの外を指しています: ../outside.txt")
              ]
        [s | (_, _, s, _) <- take 1 ds] @?= [at],
      testCase "a symbolic link out of the root is G02060" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        let root = tmp </> "book"
        _ <- withChapter root "@listing link.txt\n"
        BS.writeFile (tmp </> "outside.txt") "secret\n"
        createFileLink (tmp </> "outside.txt") (root </> "link.txt")
        ds <- evalDiags root
        [(c, m) | (c, m, _, _) <- ds] @?= [("G02060", "プロジェクトルートの外を指しています: link.txt")],
      testCase "a path both a figure and a listing refer to is read as text" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        -- a figure is PDF, PNG or JPEG by its extension (golem-pdf ADR 0008); plain text does not read images
        _ <- withChapter tmp "@listing notes.png\n\n@figure notes.png alt=x\n"
        BS.writeFile (tmp </> "notes.png") "hello listing\n"
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        t <- BS.readFile (tmp </> "build/text/horizontal/chapters/02.txt")
        assertBool "the listing" ("hello listing" `BS.isInfixOf` t),
      testCase "G02008 in S1 is at the inline" $ withSystemTempDirectory "golem-driver" $ \tmp -> do
        at <- withChapter tmp "[= doc.chapters]\n"
        ds <- evalDiags tmp
        ds @?= [("G02008", "連想配列 は本文に埋め込めません", at, at + 16)]
    ]

-- ------------------------------------------------------------------ golem-driver ADR 0016

-- | A copy of a font with the OS/2 fsType set.
withFsType :: Int -> BS.ByteString -> BS.ByteString
withFsType v font =
  let be16 i = fromIntegral (BS.index font i) * 256 + fromIntegral (BS.index font (i + 1)) :: Int
      be32 i = be16 i * 65536 + be16 (i + 2)
      records = [(BS.take 4 (BS.drop r font), be32 (r + 8)) | k <- [0 .. be16 4 - 1], let r = 12 + 16 * k]
   in case lookup "OS/2" records of
        Just off -> BS.take (off + 8) font <> BS.pack [fromIntegral (v `div` 256), fromIntegral (v `mod` 256)] <> BS.drop (off + 10) font
        Nothing -> font

-- | Pages with the labels and marks given, page n holding the nth list.
pagesWith :: [[T.Text]] -> [PageOut]
pagesWith ls = [PageOut n 0 False [] [] l [] [] (ColumnSet 1 0 0 0) [] 10 [] | (n, l) <- zip [1 ..] ls]

outputDiagnosticTests :: [TestTree]
outputDiagnosticTests =
  [ testCase "G07001 is at the top of style.toml, for the build and for golem check" $ do
      let noGrid = "[page]\nsize = \"A5\"\n" <> fakeBody
      b <- buildMarksFiles id (Just noGrid) fakeFontFiles
      map diagMessage (ofCode "G07001" b) @?= ["style.toml に [page.grid] がないため、版面を計算できません"]
      map (whereIs b) (ofCode "G07001" b) @?= [(Just "style.toml", 0)]
      bPdf b @?= Nothing
      c <- buildMarksFiles (\o -> o {optCheckOnly = True}) (Just noGrid) fakeFontFiles
      map (whereIs c) (ofCode "G07001" c) @?= [(Just "style.toml", 0)],
    testCase "without style.toml, G07001 is at the top of manifest.toml" $ do
      b <- buildMarksFiles id Nothing []
      map (whereIs b) (ofCode "G07001" b) @?= [(Just "manifest.toml", 0)],
    testCase "G07021: the labels that keep moving, at the block of the first" $ do
      calls <- newIORef (0 :: Int)
      let spanA = mkSpan (FileId 3) 10 20
          spanB = mkSpan (FileId 3) 30 40
          labelSpan l = if l == "a" then spanA else spanB
          flipping _ = do
            modifyIORef' calls (+ 1)
            n <- readIORef calls
            pure (Right ((), pagesWith (if odd n then [["a", "b"], []] else [[], ["a", "b"]])))
      r <- fixpoint labelSpan (const "") flipping
      case r of
        Left [d] -> do
          diagCode d @?= DiagnosticCode "G07021"
          diagMessage d @?= "ページ番号の参照が収束しません: a, b"
          diagSpan d @?= spanA
          diagRelated d @?= [(spanB, "ページが定まりません")]
        other -> assertFailure (show (fmap fst other))
      readIORef calls >>= (@?= 5),
    testCase "G07021 is not reported when a round of the layout fails" $ do
      calls <- newIORef (0 :: Int)
      let failing _ = do
            modifyIORef' calls (+ 1)
            n <- readIORef calls
            pure $
              if n == 2
                then Left [diagnostic "G07022" Error (mkSpan (FileId 1) 0 0) "x"]
                else Right ((), pagesWith [["a"]])
      r <- fixpoint (const (mkSpan (FileId 0) 0 0)) (const "") (\a -> failing (a :: Assumed))
      either (map diagCode) (const []) r @?= [DiagnosticCode "G07022"],
    testCase "G07025: an indent that leaves exactly 8 characters is not G07025; one character more is" $ do
      -- 12 characters of 10pt
      let style indent = horizontalStyle <> fakeBody <> "\n[paragraph-styles.body]\nindent = \"" <> indent <> "\"\n"
      ok <- buildMarksFiles (\o -> o {optCheckOnly = True}) (Just (style "4zw")) fakeFontFiles
      map diagCode (bErrors ok) @?= []
      over <- buildMarksFiles (\o -> o {optCheckOnly = True}) (Just (style "5zw")) fakeFontFiles
      -- caption and sidenote do not take the indent of body (golem-driver ADR 0043)
      map diagMessage (bErrors over) @?= ["段落スタイルの字下げが大きすぎます。行長を段落の文字の大きさの 8 字分以上残してください: body"],
    testCase "G07025 is about a paragraph style, at the top of style.toml, also in golem check" $ do
      let style = replaceIn "characters = 12" "characters = 10" horizontalStyle <> fakeBody <> "\n[paragraph-styles.body]\nindent = \"3zw\"\n"
      b <- buildMarksFiles id (Just style) fakeFontFiles
      assertBool "body" ("段落スタイルの字下げが大きすぎます。行長を段落の文字の大きさの 8 字分以上残してください: body" `elem` map diagMessage (ofCode "G07025" b))
      assertBool "style.toml" (all ((== (Just "style.toml", 0)) . whereIs b) (ofCode "G07025" b))
      bPdf b @?= Nothing
      c <- buildMarksFiles (\o -> o {optCheckOnly = True}) (Just style) fakeFontFiles
      nub (map diagCode (bErrors c)) @?= [DiagnosticCode "G07025"],
    testCase "G07028: beside a wrapped figure the indent leaves no line, at the paragraph" $ do
      img <- tinyImage
      let para = longPara 3
          src = wrapped "start" "12zw" <> para
      r <- layoutMini (horizontal24 <> "\n[paragraph-styles.body]\nindent = \"12zw\"\n") src img
      case r of
        Left [d] -> do
          diagCode d @?= DiagnosticCode "G07028"
          diagMessage d @?= "回り込む図版の脇で、字下げを引くと行が残りません"
          spanStart (diagSpan d) @?= BS.length (TE.encodeUtf8 (wrapped "start" "12zw"))
        other -> assertFailure (show (either (map diagCode) (const []) other)),
    testCase "G07032: every sidenote in vertical writing, captions and notes included" $ do
      a <- layoutMini pdfStyle "本文[sidenote: 注]。\n" []
      either (map diagMessage) (const []) a @?= ["縦組みの版面では傍注を使えません。脚注に替えてください"]
      b <- layoutMini pdfStyle "本文[note: 注の[sidenote: 傍注]本文]。\n" []
      either (map diagCode) (const []) b @?= [DiagnosticCode "G07032"]
      img <- tinyImage
      c <- layoutMini (figStyle pdfStyle) "@figure images/tiny.jpg alt=\"t\"\n  キャプション[sidenote: 傍注]。\n" img
      either (map diagCode) (const []) c @?= [DiagnosticCode "G07032"],
    testCase "G08001: noFontProvider, at the top of style.toml" $ do
      b <- buildMarksFiles (\o -> o {optFonts = noFontProvider}) (Just (horizontalStyle <> fakeBody)) fakeFontFiles
      map diagMessage (bErrors b) @?= ["フォントを読まない設定（noFontProvider）では PDF を出力できません"]
      map (whereIs b) (bErrors b) @?= [(Just "style.toml", 0)],
    testCase "G08007: a role without files names the role; golem check reports it without loading fonts" $ do
      calls <- newIORef (0 :: Int)
      let style = horizontalStyle <> "\n[fonts.mincho]\nfeatures = [\"palt\"]\n"
      b <- buildMarksFiles (\o -> o {optFonts = countingFonts calls}) (Just style) []
      map diagMessage (bErrors b) @?= ["[fonts.mincho] にフォントのファイルがありません"]
      map diagCode (bErrors b) @?= [DiagnosticCode "G08007"]
      map (whereIs b) (bErrors b) @?= [(Just "style.toml", 0)]
      c <- buildMarksFiles (\o -> o {optFonts = countingFonts calls, optCheckOnly = True}) (Just horizontalStyle) []
      map diagCode (bErrors c) @?= [DiagnosticCode "G08007"]
      readIORef calls >>= (@?= 0),
    testCase "G08003: a file that is no font, at the top of style.toml; each broken file once" $ do
      let broken = [("fonts/x.otf", "not a font"), ("fonts/y.otf", "not a font either")]
      b <- buildMarksFiles (\o -> o {optFonts = golemFontProvider}) (Just (horizontalStyle <> "\n[fonts.body]\nja = \"fonts/x.otf\"\n")) broken
      map diagMessage (bErrors b) @?= ["フォントを読み込めません: fonts/x.otf"]
      map (whereIs b) (bErrors b) @?= [(Just "style.toml", 0)]
      let two = horizontalStyle <> "\n[fonts.body]\nja = \"fonts/x.otf\"\n\n[fonts.gothic]\nja = \"fonts/y.otf\"\nlatin = \"fonts/x.otf\"\n\n[character-styles.g]\nfont = \"gothic\"\n"
      c <- buildMarksFiles (\o -> o {optFonts = golemFontProvider}) (Just two) broken
      map diagMessage (bErrors c) @?= ["フォントを読み込めません: fonts/x.otf", "フォントを読み込めません: fonts/y.otf"],
    testCase "G08004: fsType written as 0x and four hexadecimal digits" $ do
      noto <- notoBytes
      b <- buildMarksFiles (\o -> o {optFonts = golemFontProvider}) (Just (horizontalStyle <> "\n[fonts.body]\nja = \"fonts/r.otf\"\n")) [("fonts/r.otf", withFsType 0x0002 noto)]
      map diagCode (bErrors b) @?= [DiagnosticCode "G08004"]
      map diagMessage (bErrors b) @?= ["ライセンスが埋め込みを禁じているフォントです（fsType 0x0002）: fonts/r.otf"],
    testCase "G08019: a CFF2 font stops the PDF, in golem build, golem check and golem preflight, but not HTML (golem-font ADR 0003)" $ do
      cff2 <- BS.readFile "../golem-font/test/fonts/SourceSerif4Variable-Roman.otf"
      let style = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/v.otf\"\n"
          files = [("fonts/v.otf", cff2)]
          expected = ["CFF2 の輪郭のフォントは PDF に埋め込めません: fonts/v.otf。CFF か TrueType の輪郭のフォントを使ってください"]
      b <- buildMarksFiles (\o -> o {optFonts = golemFontProvider}) (Just style) files
      map diagMessage (bErrors b) @?= expected
      map diagCode (bErrors b) @?= [DiagnosticCode "G08019"]
      map (whereIs b) (bErrors b) @?= [(Just "style.toml", 0)]
      bPdf b @?= Nothing
      c <- buildMarksFiles (\o -> o {optFonts = golemFontProvider, optCheckOnly = True}) (Just style) files
      map diagCode (bErrors c) @?= [DiagnosticCode "G08019"]
      h <- buildMarksFiles (\o -> o {optFonts = golemFontProvider, optTargets = Just [TargetHtml]}) (Just style) files
      map diagCode (bErrors h) @?= []
      length (bWritten h) @?= 4
      withSystemTempDirectory "golem-cff2" $ \tmp -> do
        BS.writeFile (tmp </> "manifest.toml") miniManifest
        BS.writeFile (tmp </> "style.toml") style
        BS.writeFile (tmp </> "a.gm") "Text.\n"
        createDirectoryIfMissing True (tmp </> "fonts")
        BS.writeFile (tmp </> "fonts/v.otf") cff2
        p <- preflight (defaultPreflightOptions tmp)
        map diagCode (filter isError (prDiagnostics p)) @?= [DiagnosticCode "G08019"]
        assertBool "no PDF" (isNothing (prPdf p))
  ]
