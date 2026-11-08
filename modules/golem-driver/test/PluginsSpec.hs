module PluginsSpec (pluginTests, cacheHomeRestored) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Control.Monad (forM_)
import Data.Bifunctor (second)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Assemble (Book (..), inlineText)
import Golem.Doc.IR (Block (..), BlockBody (..), Document (..), Inline, InlineF (..), ListItem (..), NumberStyle (..), RubySegment (..))
import Golem.Driver
import Golem.Driver.Plugins (LoadedPlugins (..), loadPlugins)
import Golem.Eval.Builtin (BuiltinInline (..), builtinName, unPluginCommandName)
import Golem.Eval.File (EvalResult (..), PluginHook (..))
import Golem.Plugin (HostContext (..), maxDataBytes, watToWasm)
import Golem.Plugin.Lock (defaultCacheDir, lockPlugins, renderLock)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..), SourceFile (..))
import Golem.Project.Files (diskFiles)
import Golem.Project.Manifest (parseManifest)
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Golem.TestSupport.Env (withEnv)
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Golem.Typeset (PdfInput (..), layoutPages)
import Support
import System.Directory (createFileLink, listDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

{- | XDG_CACHE_HOME after the plugin tests is what it was when the suite
started: the tests that set it set it back (docs/adr ADR 0072). The
suite is not -threaded, so this runs after the plugin tests.
-}
cacheHomeRestored :: Maybe String -> TestTree
cacheHomeRestored start =
  testCase "XDG_CACHE_HOME is as it was when the suite started (docs/adr ADR 0072)" $
    lookupEnv "XDG_CACHE_HOME" >>= (@?= start)

-- | A project with the identity plugin locked and cached.
withPluginProject :: BS.ByteString -> (FilePath -> IO a) -> IO a
withPluginProject = withPlugins [("identity", "identity.wat")]

{- | A project with plugins (name, wat file of golem-plugin's tests) locked
and cached; each is at https://example.com/<name>.wasm.
-}
withPlugins :: [(T.Text, FilePath)] -> BS.ByteString -> (FilePath -> IO a) -> IO a
withPlugins plugins manifestExtra k = withSystemTempDirectory "golem-driver" $ \tmp -> do
  copyTree fixture tmp
  manifest <- BS.readFile (tmp </> "manifest.toml")
  BS.writeFile (tmp </> "manifest.toml") (manifest <> manifestExtra)
  lockIn plugins tmp (k tmp)

{- | Runs an action with the plugins (name, wat file of golem-plugin's
tests) locked in plugins.lock of a project and cached in the project's
cache, and XDG_CACHE_HOME set to that cache until the action ends (docs/adr
ADR 0072); each plugin is at https://example.com/<name>.wasm.
-}
lockIn :: [(T.Text, FilePath)] -> FilePath -> IO a -> IO a
lockIn plugins tmp act = do
  served <- mapM serve plugins
  withEnv "XDG_CACHE_HOME" (tmp </> "cache") $ do
    cache <- defaultCacheDir
    r <- lockPlugins (\u -> pure (maybe (Left "404") Right (lookup u served))) cache (Map.fromList [(name, pluginUrl name) | (name, _) <- plugins])
    either (assertFailure . show) (TIO.writeFile (tmp </> "plugins.lock") . renderLock) r
    act
  where
    pluginUrl name = "https://example.com/" <> name <> ".wasm"
    -- a wat file of golem-plugin's tests, or a sample plugin built into plugins/wasm (docs/adr/0106)
    serve (name, file)
      | ".wasm" `T.isSuffixOf` T.pack file = (pluginUrl name,) <$> BS.readFile (".." </> ".." </> "plugins" </> "wasm" </> file)
      | otherwise = do
          src <- TIO.readFile ("../golem-plugin/test/plugins" </> file)
          wasm <- watToWasm src >>= either (assertFailure . T.unpack) pure
          pure (pluginUrl name, wasm)

-- | The declaration of a plugin as withPlugins serves it.
pluginDeclOf :: BS.ByteString -> BS.ByteString -> BS.ByteString
pluginDeclOf name extra = "\n[plugins." <> name <> "]\nurl = \"https://example.com/" <> name <> ".wasm\"\n" <> extra

-- | A [[filters]] item for chapters/01.gm.
filterDecl :: BS.ByteString -> BS.ByteString -> BS.ByteString
filterDecl plugin name = "\n[[filters]]\nplugin = \"" <> plugin <> "\"\nfilter = \"" <> name <> "\"\nfiles = [\"chapters/01.gm\"]\n"

-- | The span at the top of a file of the build.
topOf :: BuildResult -> FilePath -> Maybe SrcSpan
topOf r path = (\fid -> mkSpan fid 0 0) <$> sourceFileId r path

-- | The codes and messages of the diagnostics, all at the top of the manifest.
atManifestTop :: BuildResult -> IO [(DiagnosticCode, T.Text)]
atManifestTop r = do
  let ds = brDiagnostics r
  assertEqual "at the top of manifest.toml" (map (const (topOf r "manifest.toml")) ds) (map (Just . diagSpan) ds)
  pure [(diagCode d, diagMessage d) | d <- ds]

{- | A one-chapter project, a.gm, with the plugin chan of channels.wat
(golem-doc ADR 0007), for PDF, HTML and plain text.
-}
withChannels :: BS.ByteString -> T.Text -> (FilePath -> IO a) -> IO a
withChannels style source k = withSystemTempDirectory "golem-channels" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n[targets.text]\n" <> pluginDeclOf "chan" "")
  BS.writeFile (tmp </> "style.toml") style
  TIO.writeFile (tmp </> "a.gm") source
  lockIn [("chan", "channels.wat")] tmp (k tmp)

-- | The text of the lines of each page of the PDF of a project.
pdfPages :: FilePath -> IO [[T.Text]]
pdfPages tmp = do
  e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
  book <- maybe (assertFailure (show (evDiagnostics e))) pure (evBook e)
  assertEqual "no errors" [] (map diagCode (filter isError (evDiagnostics e)))
  layoutPages fakeProvider (PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing Map.empty (chapterMasters (evProject e)) (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e))
    >>= either (assertFailure . show) pure

-- | The channels of plugins (golem-doc ADR 0007).
channelTests :: [TestTree]
channelTests =
  [ testCase "G06012: a reserved name and a malformed name" $
      withPlugins [("bad", "channels-bad.wat")] (pluginDeclOf "bad" "") $ \tmp -> do
        r <- build (defaultOptions tmp)
        ds <- atManifestTop r
        sort ds
          @?= sort
            [ (DiagnosticCode "G06012", "bad: このチャネルの名前は使えません: index"),
              (DiagnosticCode "G06012", "bad: このチャネルの名前は使えません: Glossary")
            ],
    testCase "G06012: two plugins declare glossary" $
      withPlugins [("a", "channels.wat"), ("b", "channels.wat")] (pluginDeclOf "a" "" <> pluginDeclOf "b" "") $ \tmp -> do
        r <- build (defaultOptions tmp)
        ds <- atManifestTop r
        [d | d@(DiagnosticCode "G06012", _) <- ds]
          @?= [ (DiagnosticCode "G06012", "複数のプラグインが同じチャネルを宣言しています: glossary（a、b）"),
                (DiagnosticCode "G06012", "複数のプラグインが同じチャネルを宣言しています: people（a、b）")
              ],
    testCase "no G02090 after the plugins failed to load" $
      withPlugins [("chan", "channels.wat")] (pluginDeclOf "chan" "") $ \tmp -> do
        BS.writeFile (tmp </> "plugins.lock") ""
        BS.appendFile (tmp </> "chapters/02.gm") "\n@channel glossary\n"
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G06002"],
    testCase "PDF: the entries of people have their pages, those of glossary none; a note item has the page of its mark" $
      withChannels horizontalStyle ("人[person 甲: 甲]。\n\n語[term ご ご: 語]。\n\n" <> fillers 35 <> "本文[note: 注[person 乙: 乙]]。\n\n@channel people\n\n@channel glossary\n") $ \tmp -> do
        ls <- concat <$> pdfPages tmp
        assertBool (show ls) ("甲　1" `elem` ls)
        assertBool (show ls) ("乙　2" `elem` ls)
        assertBool (show ls) ("語" `elem` ls)
        assertBool (show ls) (not (any ("語　" `T.isPrefixOf`) ls)),
    testCase "PDF: in vertical text the pages are in kanji" $
      withChannels pdfStyle "人[person 甲: 甲]。\n\n@channel people\n" $ \tmp -> do
        ls <- concat <$> pdfPages tmp
        assertBool (show ls) ("甲　一" `elem` ls),
    testCase "HTML: an id at each item, the list links to it in another file; the same bytes twice" $
      withPlugins [("chan", "channels.wat")] (pluginDeclOf "chan" "") $ \tmp -> do
        TIO.appendFile (tmp </> "chapters/01.gm") "\n人[person 甲: 甲]。\n"
        TIO.appendFile (tmp </> "chapters/02.gm") "\n@channel people\n"
        let html = do
              r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
              assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
              (,) <$> TIO.readFile (tmp </> "build/html/chapters/01.xhtml") <*> TIO.readFile (tmp </> "build/html/chapters/02.xhtml")
        (one, two) <- html
        assertBool (T.unpack one) ("<span id=\"c-people-" `T.isInfixOf` one)
        assertBool (T.unpack two) ("<section class=\"channel\" data-channel=\"people\">" `T.isInfixOf` two)
        assertBool (T.unpack two) ("<li>甲 <a href=\"../chapters/01.xhtml#c-people-" `T.isInfixOf` two)
        again <- html
        again @?= (one, two),
    testCase "plain text: the body of each entry on a line" $
      withChannels horizontalStyle "人[person 甲: 甲]と[person 乙: 乙]。\n\n@channel people\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        t <- TIO.readFile (tmp </> "build/text/horizontal/a.txt")
        t @?= "人甲と乙。\n\n甲\n乙\n"
  ]

{- | A one-chapter project, a.gm, with the plugin of datum.wat, which
answers [datum] with the bytes of its data table, declared as lk with
the given keys after its url, and the given files.
-}
withDatum :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withDatum = withDataPlugin "datum.wat"

-- | The same with a plugin of the given file: a wat file or a sample plugin.
withDataPlugin :: FilePath -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withDataPlugin plugin decl source files k = withSystemTempDirectory "golem-data" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> pluginDeclOf "lk" decl)
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  TIO.writeFile (tmp </> "a.gm") source
  writeFiles tmp files
  lockIn [("lk", plugin)] tmp (k tmp)

-- | The S0 inlines of the paragraphs of a.gm, and every diagnostic.
lookedUp :: Map.Map FilePath T.Text -> FilePath -> IO ([Inline], [(DiagnosticCode, T.Text)])
lookedUp overlay tmp = do
  e <- evaluateProjectWith (diskFiles tmp) overlay Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
  let inls = [i | (fid, sf) <- Map.toList (projectSources (evProject e)), sfPath sf == "a.gm", Just r <- [Map.lookup fid (evResults e)], b <- docBlocks (erDocument r), Paragraph _ is <- [blockBody b], i <- is]
  pure (inls, [(diagCode d, diagMessage d) | d <- evDiagnostics e])

texts :: [Inline] -> [T.Text]
texts is = [t | Text _ t <- is]

{- | A one-chapter project, a.gm, with datum.wat built into
plugins/datum.wasm and declared as lk with the given keys, and the given
files: a plugin of the project's path (docs/adr/0109), no plugins.lock.
-}
withLocal :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withLocal decl source files k = withSystemTempDirectory "golem-local" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> "\n[plugins.lk]\n" <> decl)
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  TIO.writeFile (tmp </> "a.gm") source
  src <- TIO.readFile "../golem-plugin/test/plugins/datum.wat"
  wasm <- watToWasm src >>= either (assertFailure . T.unpack) pure
  writeFiles tmp (("plugins/datum.wasm", wasm) : files)
  k tmp

{- | A project as 'withLocal' with datum.wat declaring the data * instead
of table (docs/adr/0119): it takes data of any name, and answers [datum]
with the data table, which must be the first data by name.
-}
withAnyDatum :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withAnyDatum = withDescribedDatum "\\a2\\64data\\81\\61*\\68commands\\81\\65datum" 25

{- | A project as 'withLocal' with datum.wat answering golem_describe with
the given bytes (escaped for wat) of the given length instead of its own.
-}
withDescribedDatum :: T.Text -> Int -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withDescribedDatum describe size decl source files k = withSystemTempDirectory "golem-described" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> "\n[plugins.lk]\npath = \"datum.wasm\"\n" <> decl)
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  TIO.writeFile (tmp </> "a.gm") source
  src <- TIO.readFile "../golem-plugin/test/plugins/datum.wat"
  -- at 256, after the other data of datum.wat, however long it is
  let described =
        T.replace "(i64.const 29)" ("(i64.const " <> T.pack (show size) <> ")")
          . T.replace "(i64.shl (i64.const 16) (i64.const 32))" "(i64.shl (i64.const 256) (i64.const 32))"
          . T.replace "(data (i32.const 16) \"" "(data (i32.const 256) \""
          . T.replace "\"\\a2\\64data\\81\\65table\\68commands\\81\\65datum\"" ("\"" <> describe <> "\"")
  assertBool "datum.wat declares table" (described src /= src)
  wasm <- watToWasm (described src) >>= either (assertFailure . T.unpack) pure
  writeFiles tmp (("datum.wasm", wasm) : files)
  k tmp

{- | A one-chapter project, a.gm, with the plugins (name, wat file or
sample plugin) declared with the given text after their url.
-}
withBlockProject :: [(T.Text, FilePath, BS.ByteString)] -> T.Text -> (FilePath -> IO a) -> IO a
withBlockProject plugins source k = withSystemTempDirectory "golem-blocks" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> foldMap (\(n, _, decl) -> pluginDeclOf (TE.encodeUtf8 n) decl) plugins)
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  TIO.writeFile (tmp </> "a.gm") source
  lockIn [(n, f) | (n, f, _) <- plugins] tmp (k tmp)

-- | The S0 blocks of a.gm.
blocksOf :: FilePath -> IO ([Block], [(DiagnosticCode, T.Text)])
blocksOf tmp = do
  e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
  let bs = [b | (fid, sf) <- Map.toList (projectSources (evProject e)), sfPath sf == "a.gm", Just r <- [Map.lookup fid (evResults e)], b <- docBlocks (erDocument r)]
  pure (bs, [(diagCode d, diagMessage d) | d <- evDiagnostics e])

-- | Block commands of plugins (docs/adr/0122), with grid.wat.
blockCommandTests :: [TestTree]
blockCommandTests =
  [ testCase "@grid puts out the blocks of the plugin at the call" $
      withBlockProject [("gr", "grid.wat", "")] "@grid\n" $ \tmp -> do
        (bs, ds) <- blocksOf tmp
        ds @?= []
        [(spanStart (blockSpan b), spanEnd (blockSpan b), [t | Paragraph _ is <- [blockBody b], Text _ t <- is]) | b <- bs] @?= [(0, 6, ["表"])],
    testCase "a block command is not an inline command, nor an inline command a block command" $
      withBlockProject [("gr", "grid.wat", ""), ("lookup", "lookup.wasm", "")] "[grid]\n\n@lookup x\n" $ \tmp -> do
        (_, ds) <- blocksOf tmp
        map fst ds @?= [DiagnosticCode "G02022", DiagnosticCode "G02009"],
    testCase "no G02009 nor G02022 after a plugin failed to load" $
      withBlockProject [("gr", "grid.wat", "data = { table = \"none.tsv\" }\n")] "@grid\n\n[grid]\n\n@nope\n" $ \tmp -> do
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G06101", DiagnosticCode "G06102"],
    testCase "G06006: two plugins with the same block command" $
      withBlockProject [("a", "grid.wat", ""), ("b", "grid.wat", "")] "本文\n" $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "G06006", "複数のプラグインが同じブロックコマンドを提供しています: @grid（a、b）")]),
    testCase "a block command in a list item takes @label" $
      withBlockProject [("gr", "grid.wat", "")] "- 項目\n\n  @label t\n  @grid\n" $ \tmp -> do
        (bs, ds) <- blocksOf tmp
        ds @?= []
        case map blockBody bs of
          [BulletList [ListItem _ [_, Block _ (Just "t") Nothing (Paragraph _ [Text _ "表"])]]] -> pure ()
          other -> assertFailure (show other)
  ]

{- | A one-chapter project, a.gm, for PDF, HTML and EPUB with the fake
fonts, and the sample plugin bar-chart (docs/adr/0123) declared as bc
with the data sales.
-}
withBarChart :: T.Text -> (FilePath -> IO a) -> IO a
withBarChart source k = withSystemTempDirectory "golem-chart" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf", "html", "epub"]}) <> pluginDeclOf "bc" "data = { sales = \"sales.tsv\" }\n")
  BS.writeFile (tmp </> "style.toml") (withBodyFont horizontalStyle)
  TIO.writeFile (tmp </> "a.gm") source
  writeFiles tmp (("sales.tsv", TE.encodeUtf8 "月\t売上\n1月\t12\n2月\t30\n") : fakeFontFiles)
  lockIn [("bc", "bar-chart.wasm")] tmp (k tmp)

-- | The SVG bar-chart draws for 12 and 30.
chartSvg :: BS.ByteString
chartSvg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 400 200\" width=\"400\" height=\"200\"><rect x=\"20\" y=\"120\" width=\"160\" height=\"80\" fill=\"#404040\"/><rect x=\"220\" y=\"0\" width=\"160\" height=\"200\" fill=\"#404040\"/><rect x=\"0\" y=\"199\" width=\"400\" height=\"1\" fill=\"#000000\"/></svg>"

-- | Where HTML and EPUB put it.
chartPath :: FilePath
chartPath = "images/golem-plugin/" <> concatMap (printf "%02x") (BS.unpack (sha256 chartSvg)) <> ".svg"

-- | The figures of plugins (docs/adr/0123).
pluginFigureTests :: [TestTree]
pluginFigureTests =
  [ testCase "a bar chart of a plugin is a figure with a number, in PDF, HTML and EPUB" $
      withBarChart "# 章\n\n@label c\n@bar-chart sales alt=\"売上の棒グラフ\"\n  月ごとの売上\n\n[ref-number c]\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optFonts = fakeProvider}
        filter isError (brDiagnostics r) @?= []
        BS.readFile (tmp </> "build/html" </> chartPath) >>= (@?= chartSvg)
        page <- TIO.readFile (tmp </> "build/html/a.xhtml")
        assertBool (T.unpack page) (T.pack chartPath `T.isInfixOf` page)
        epubs <- filter (".epub" `isSuffixOf`) <$> listDirectory (tmp </> "build/epub")
        case epubs of
          [f] -> do
            a <- toArchive . BL.fromStrict <$> BS.readFile (tmp </> "build/epub" </> f)
            fmap (BL.toStrict . fromEntry) (findEntryByPath ("OEBPS/" <> chartPath) a) @?= Just chartSvg
          other -> assertFailure (show other)
        assertBool "a PDF" (any (".pdf" `isSuffixOf`) (brWritten r))
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        fmap (Map.size . bookFigures) (evBook e) @?= Just 1,
    testCase "the same input gives the same PDF, twice" $
      withBarChart "# 章\n\n@bar-chart sales alt=\"x\"\n" $ \tmp -> do
        let pdfOf = do
              r <- build (defaultOptions tmp) {optFonts = fakeProvider, optTargets = Just [TargetPdf]}
              case filter (".pdf" `isSuffixOf`) (brWritten r) of
                [p] -> BS.readFile p
                ps -> assertFailure (show ps)
        a <- pdfOf
        b <- pdfOf
        a @?= b,
    testCase "the source of a plugin's image written in @figure is a URL, G02060" $
      withBarChart ("@figure \"golem-plugin-image://" <> T.pack (drop (length ("images/golem-plugin/" :: String)) chartPath) <> "\" alt=x\n") $ \tmp -> do
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        map diagCode (evDiagnostics e) @?= [DiagnosticCode "G02060"],
    testCase "the errors of the plugin give no figure" $
      withBarChart "@bar-chart sales\n" $ \tmp -> do
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        map diagCode (evDiagnostics e) @?= [DiagnosticCode "bc/alt"],
    testCase "G08102: a figure of the source where HTML and EPUB put the images of plugins" $
      withBarChart "# 章\n\n@figure ./images/golem-plugin/x.svg alt=x\n" $ \tmp -> do
        writeFiles tmp [("images/golem-plugin/x.svg", chartSvg)]
        r <- build (defaultOptions tmp) {optFonts = fakeProvider}
        [(diagCode d, diagMessage d) | d <- brDiagnostics r, isError d]
          @?= [(DiagnosticCode "G08102", "図版の画像の出力のパスが、プラグインの画像を置くフォルダー images/golem-plugin と重なります: ./images/golem-plugin/x.svg")]
        assertBool "no HTML" (not (any (("build/html/" `T.isInfixOf`) . T.pack) (brWritten r)))
        assertBool "a PDF" (any (".pdf" `isSuffixOf`) (brWritten r))
  ]

-- | The context of the book a plugin asks for (docs/adr/0121).
contextTests :: [TestTree]
contextTests =
  [ testCase "G06105: a plugin that asks for context Golem does not have" $
      withDescribedDatum "\\a3\\64data\\81\\65table\\68commands\\81\\65datum\\67context\\82\\68language\\65media" 53 "" "本文\n" [] $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "G06105", "lk: Golem が渡せない文脈を求めています: language、media（渡せる文脈: vertical-numbers、writing-mode）")]),
    testCase "the LSP watches style.toml when a plugin asks for context, and not otherwise" $ do
      withDescribedDatum "\\a3\\64data\\81\\65table\\68commands\\81\\65datum\\67context\\81\\6cwriting-mode" 51 "" "本文\n" [] $ \tmp -> do
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        assertBool (show (evTableFiles e)) ("style.toml" `elem` evTableFiles e)
      withLocal "path = \"plugins/datum.wasm\"\n" "本文\n" [] $ \tmp -> do
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        assertBool (show (evTableFiles e)) ("style.toml" `notElem` evTableFiles e),
    testCase "the context is the writing mode of [page] and [numbers] vertical, with their defaults" $ do
      let ctxOf t = either (assertFailure . show) (pure . hostContext) (parseStyle (FileId 0) t)
      ctxOf "" >>= (@?= HostContext "horizontal" "kanji")
      ctxOf (TE.decodeUtf8 pdfStyle) >>= (@?= HostContext "vertical" "kanji")
      ctxOf (TE.decodeUtf8 pdfStyle <> "\n[numbers]\nvertical = \"tcy\"\n") >>= (@?= HostContext "vertical" "tcy")
  ]

{- | A one-chapter project, a.gm, in a style, with a sample plugin of
plugins/wasm (docs/adr/0106) declared under its own name with the given
keys after its url, the given extra text of the manifest, and the given
files.
-}
withSample :: BS.ByteString -> T.Text -> BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withSample style name decl extra source files k = withSystemTempDirectory "golem-sample" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> pluginDeclOf (TE.encodeUtf8 name) decl <> extra)
  BS.writeFile (tmp </> "style.toml") style
  TIO.writeFile (tmp </> "a.gm") source
  writeFiles tmp files
  lockIn [(name, T.unpack name <> ".wasm")] tmp (k tmp)

-- | 'horizontalStyle' in vertical writing.
verticalStyle :: BS.ByteString
verticalStyle = TE.encodeUtf8 (T.replace "writing-mode = \"horizontal\"" "writing-mode = \"vertical\"" (TE.decodeUtf8 horizontalStyle))

-- | The inlines in a short form: a text as it is, a number of the style tcy as #n, a tcy as [tcy: t].
shapes :: [Inline] -> [T.Text]
shapes = map $ \case
  Text _ t -> t
  Number _ n (Just StyleTcy) -> "#" <> T.pack (show n)
  Number _ n _ -> "number " <> T.pack (show n)
  Tcy _ t -> "[tcy: " <> t <> "]"
  CharStyle _ s xs -> "[" <> s <> ": " <> T.concat (shapes xs) <> "]"
  _ -> "?"

{- | The sample plugin kansuji overrides number-text (docs/adr/0125), with
the integration tests of docs/adr/0110, 0112 and 0121 that need it.
-}
kansujiTests :: [TestTree]
kansujiTests =
  [ testCase "integers, decimals, fractions and negative numbers in kanji in vertical writing" $
      kansuji verticalStyle "[number-text 123]、##12##、[number-text 123 style=kanji-digits]、[number-text [= 3.14]]、[number-text [= 2 / 3]]、[number-text [= -3]]、[number-text [= 3.0]]\n" $ \r ->
        -- the text of the plugin and the text around it are one text node
        r @?= (["百二十三、十二、一二三、三・一四、三分の二、マイナス三、三"], []),
    testCase "the words -3 and 3.14 reach the plugin as numbers (docs/adr/0111)" $
      kansuji verticalStyle "[number-text -3]、[number-text 3.14]\n" $ \r ->
        r @?= (["マイナス三、三・一四"], []),
    testCase "style=tcy gives the number node, and form=fraction a fraction" $
      kansuji verticalStyle "[number-text 12 style=tcy][number-text [= 0.5] form=fraction]\n" $ \r ->
        r @?= (["#12", "二分の一"], []),
    testCase "the default style is [numbers] vertical of style.toml, the context vertical-numbers (docs/adr/0121)" $
      kansuji (verticalStyle <> "\n[numbers]\nvertical = \"auto\"\n") "##12##と##120##\n" $ \r ->
        r @?= (["#12", "と百二十"], []),
    testCase "in horizontal writing an integer is the number node and a rational is in Arabic numerals (the context writing-mode)" $
      kansuji horizontalStyle "[number-text 123]、[number-text [= 3.14]]、[number-text [= 2 / 3]]、[number-text [= -3]]、[number-text 12 style=kanji]\n" $ \r ->
        r @?= (["number 123", "、3.14、2/3、", "number -3", "、", "number 12"], []),
    testCase "style.toml is watched, since kansuji asks for its context (docs/adr/0121)" $
      withSample verticalStyle "kansuji" "overrides = [\"number-text\"]\n" "" "x\n" [] $ \tmp -> do
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        assertBool (show (evTableFiles e)) ("style.toml" `elem` evTableFiles e),
    testCase "style.toml is not watched for lookup, which asks for no context (docs/adr/0121)" $
      withDataPlugin "lookup.wasm" "data = { table = \"w.tsv\" }\n" "x\n" [("w.tsv", "key\tv\n")] $ \tmp -> do
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        assertBool (show (evTableFiles e)) ("style.toml" `notElem` evTableFiles e),
    testCase "a word that is no number: the diagnostic of the plugin, with the name of its declaration (docs/adr/0108)" $
      kansuji verticalStyle "[number-text abc]\n" $ \r ->
        r @?= ([], [(DiagnosticCode "kansuji/not-number", "number-text には数を渡します: abc")]),
    testCase "G02091: an integer past int64 does not reach the plugin (golem-doc ADR 0006)" $
      kansuji verticalStyle "[number-text 9223372036854775808][number-text [= 1 / 9223372036854775808]]\n" $ \r ->
        second (map fst) r @?= ([], [DiagnosticCode "G02091", DiagnosticCode "G02091"]),
    testCase "*[expr] and **[expr] are expanded into the arguments of the plugin (docs/adr/0110, 0112)" $
      kansuji verticalStyle "[number-text *[[123]]]と[number-text 12 **[{style: \"tcy\"}]]\n" $ \r ->
        r @?= (["百二十三と", "#12"], []),
    testCase "G02111, G02112 and G02077: a spread of the wrong type, and a key twice, where the first key is used (docs/adr/0110, 0112)" $
      mapM_
        (\(source, out, code) -> kansuji verticalStyle source $ \r -> second (map fst) r @?= (out, [DiagnosticCode code]))
        [ ("[number-text *[12]]\n", [], "G02111"),
          ("[number-text 12 **[[1]]]\n", [], "G02112"),
          ("[number-text 12 style=kanji **[{style: \"tcy\"}]]\n", ["十二"], "G02077")
        ],
    testCase "the largest int64 in kanji" $
      kansuji verticalStyle "[number-text 9223372036854775807]\n" $ \r ->
        r @?= (["九百二十二京三千三百七十二兆三百六十八億五千四百七十七万五千八百七"], [])
  ]
  where
    kansuji style source k =
      withSample style "kansuji" "overrides = [\"number-text\"]\n" "" source [] $ \tmp ->
        lookedUp Map.empty tmp >>= \(is, ds) -> k (shapes is, ds)

-- | The sample filter auto-tcy (docs/adr/0128), with the integration test of docs/adr/0121 that needs it.
autoTcyTests :: [TestTree]
autoTcyTests =
  [ testCase "two digits and !? in tate-chu-yoko, 3.14 and 123 left alone" $
      autoTcy verticalStyle "" "第12回、本当か!?、3.14、123、[strong: 34]\n" $ \r ->
        r @?= (["第", "#12", "回、本当か", "[tcy: !?]", "、3.14、123、", "[strong: #34]"], []),
    testCase "a chunk across nodes is left alone with a warning" $
      autoTcy verticalStyle "" "[strong: 1]2\n" $ \r ->
        r @?= (["[strong: 1]", "2"], [(DiagnosticCode "auto-tcy/split", "ノードの境をまたぐので縦中横にしませんでした: 12。[tcy: ...] か [number-text ... style=tcy] で書いてください")]),
    testCase "the warning is a warning, not an error" $
      withSample verticalStyle "auto-tcy" "" filters "[strong: 1]2\n" [] $ \tmp -> do
        r <- build (defaultOptions tmp)
        [(diagCode d, diagSeverity d) | d <- brDiagnostics r] @?= [(DiagnosticCode "auto-tcy/split", Warning)],
    testCase "in horizontal writing the filter changes nothing and warns of nothing (the context writing-mode)" $
      autoTcy horizontalStyle "" "第12回、本当か!?、[strong: 1]2\n" $ \r ->
        r @?= (["第12回、本当か!?、", "[strong: 1]", "2"], []),
    testCase "code and an explicit tcy are not rewritten" $
      autoTcy verticalStyle "" "[code: 12][tcy: !?]\n" $ \r ->
        r @?= (["[code: 12]", "[tcy: !?]"], []),
    testCase "the data config chooses the counts of digits and the marks" $
      autoTcy verticalStyle "data = { config = \"tcy.conf\" }\n" "12と123と!!!\n" $ \r ->
        r @?= (["12と", "#123", "と", "[tcy: !!!]"], []),
    -- docs/adr/0162
    testCase "the filters of .emet and of plugins apply in the order of [[filters]]" $ do
      let emet =
            TE.encodeUtf8 . T.unlines $
              [ "pub filter add :: Blocks -> Blocks",
                "add bs = bs ++ Block.paragraph (Inline.text \"12\")",
                "",
                "pub filter count :: Blocks -> Blocks",
                "count bs = bs ++ Block.paragraph (Inline.text (String.fromNat (List.length (List.select isTcy (List.concatMap inlinesOf bs)))))",
                "",
                "inlinesOf :: Block.Block -> Inlines",
                "inlinesOf (Block.Paragraph _ xs) = xs",
                "inlinesOf _ = []",
                "",
                "isTcy :: Inline.Inline -> Bool",
                "isTcy (Inline.Number _ (Just Inline.TateChuYoko)) = True",
                "isTcy _ = False"
              ]
          function name = "\n[[filters]]\nfunction = \"f.emet\"\nfilter = \"" <> name <> "\"\nfiles = [\"a.gm\"]\n"
          ordered first = withSample verticalStyle "auto-tcy" "" (first <> function "count") "本文。\n" [("f.emet", emet)] $ \tmp ->
            lookedUp Map.empty tmp >>= \(is, ds) -> pure (shapes is, ds)
      ordered (function "add" <> filters) >>= (@?= (["本文。", "#12", "1"], []))
      ordered (filters <> function "add") >>= (@?= (["本文。", "12", "0"], [])),
    testCase "an error of the config points at the top of the file, in horizontal writing too" $
      withSample horizontalStyle "auto-tcy" "data = { config = \"bad.conf\" }\n" filters "12\n" [("bad.conf", "digits = 9\n")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        [(diagCode d, diagSpan d) | d <- brDiagnostics r] @?= [(DiagnosticCode "auto-tcy/config-digits", topOf' r)]
  ]
  where
    filters = "\n[[filters]]\nplugin = \"auto-tcy\"\nfilter = \"auto-tcy\"\nfiles = [\"a.gm\"]\n"
    autoTcy style decl source k =
      withSample style "auto-tcy" decl filters source [("tcy.conf", "digits = 3\nmarks = !!!\n")] $ \tmp ->
        lookedUp Map.empty tmp >>= \(is, ds) -> k (shapes is, ds)
    topOf' r = fromMaybe (error "no a.gm") (topOf r "a.gm")

{- | A one-chapter project, a.gm, with the sample plugin tsv-table
(docs/adr/0129) declared as tt with the data the declaration gives.
-}
withTsvTable :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withTsvTable decl source files k = withSystemTempDirectory "golem-tsv" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> pluginDeclOf "tt" decl)
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  TIO.writeFile (tmp </> "a.gm") source
  writeFiles tmp files
  lockIn [("tt", "tsv-table.wasm")] tmp (k tmp)

-- | A table without its spans: the alignments and the texts of the cells.
tableShape :: BlockBody -> Maybe (String, [[T.Text]], [[[T.Text]]])
tableShape = \case
  Table al h rows -> Just (show al, map texts h, map (map texts) rows)
  _ -> Nothing

salesTsv :: BS.ByteString
salesTsv = TE.encodeUtf8 "品目\t数\t備考\n\"りんご\"\t12\t\nみかん\t3\t\\x\n"

{- | The sample plugin tsv-table (docs/adr/0129), with the integration
tests of docs/adr/0110, 0119 and 0122 that need it.
-}
tsvTableTests :: [TestTree]
tsvTableTests =
  [ testCase "@tsv-table makes the table @table makes of the same TSV, with align (docs/adr/0110)" $
      withTsvTable "data = { sales = \"data/sales.tsv\" }\n" "@tsv-table sales align=left,right,center\n\n@table data/sales.tsv align=left,right,center\n" [("data/sales.tsv", salesTsv)] $ \tmp -> do
        (bs, ds) <- blocksOf tmp
        ds @?= []
        case map (tableShape . blockBody) bs of
          [Just a, Just b] -> do
            a @?= b
            a @?= ("[AlignLeft,AlignRight,AlignCenter]", [["品目"], ["数"], ["備考"]], [[["\"りんご\""], ["12"], []], [["みかん"], ["3"], ["\\x"]]])
          other -> assertFailure (show other),
    testCase "the nodes of the table are at the call (docs/adr/0122)" $
      withTsvTable "data = { sales = \"s.tsv\" }\n" "@tsv-table sales\n" [("s.tsv", "a\nb\n")] $ \tmp -> do
        (bs, _) <- blocksOf tmp
        case bs of
          [Block sp _ _ (Table _ [[Text csp "a"]] [[[Text rsp "b"]]])] -> do
            (spanStart sp, spanEnd sp) @?= (0, 17)
            csp @?= sp
            rsp @?= sp
          other -> assertFailure (show other),
    testCase "data of any name: two tables of two files, typeset to text (docs/adr/0119)" $
      withTsvTable "data = { sales = \"s.tsv\", costs = \"c.tsv\" }\n" "@tsv-table sales\n\n@tsv-table costs\n" [("s.tsv", TE.encodeUtf8 "売上\n100\n"), ("c.tsv", TE.encodeUtf8 "費用\n40\n")] $ \tmp -> do
        (bs, ds) <- blocksOf tmp
        ds @?= []
        map (tableShape . blockBody) bs @?= [Just ("[AlignDefault]", [["売上"]], [[["100"]]]), Just ("[AlignDefault]", [["費用"]], [[["40"]]])]
        r <- build (defaultOptions tmp)
        brDiagnostics r @?= []
        out <- TIO.readFile (tmp </> "build/text/horizontal/a.txt")
        map (`T.isInfixOf` out) ["売上", "100", "費用", "40"] @?= [True, True, True, True],
    testCase "@label gives the table its label" $
      withTsvTable "data = { sales = \"s.tsv\" }\n" "@label t\n@tsv-table sales\n" [("s.tsv", "a\n")] $ \tmp -> do
        (bs, ds) <- blocksOf tmp
        ds @?= []
        map blockLabel bs @?= [Just "t"],
    testCase "a table in a list item" $
      withTsvTable "data = { sales = \"s.tsv\" }\n" "- 項目\n\n  @tsv-table sales\n" [("s.tsv", "a\n")] $ \tmp -> do
        (bs, ds) <- blocksOf tmp
        ds @?= []
        case map blockBody bs of
          [BulletList [ListItem _ [_, Block _ _ _ (Table {})]]] -> pure ()
          other -> assertFailure (show other),
    testCase "the errors of the TSV are the plugin's, at the call, and give no table" $
      withTsvTable "data = { sales = \"s.tsv\" }\n" "@tsv-table sales\n\n@tsv-table costs\n" [("s.tsv", "a\tb\n1\n")] $ \tmp -> do
        (bs, ds) <- blocksOf tmp
        bs @?= []
        ds
          @?= [ (DiagnosticCode "tt/cells", "sales の 2 行目のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）"),
                (DiagnosticCode "tt/no-data", "manifest.toml の data にない名前です: costs")
              ],
    testCase "a name of data that is not a name is G06102 for a plugin of any name (docs/adr/0119)" $
      withTsvTable "data = { Sales = \"s.tsv\" }\n" "x\n" [("s.tsv", "a\n")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [DiagnosticCode "G06102"]) . map fst,
    testCase "[tsv-table] is an unknown command; @lookup an unknown block command" $
      withTsvTable "data = { sales = \"s.tsv\" }\n" "[tsv-table sales]\n\n@lookup x\n" [("s.tsv", "a\n")] $ \tmp -> do
        (_, ds) <- blocksOf tmp
        map fst ds @?= [DiagnosticCode "G02022", DiagnosticCode "G02009"],
    testCase "G06006: two plugins with the same block command" $
      withSystemTempDirectory "golem-tsv" $ \tmp -> do
        BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> pluginDeclOf "t1" "" <> pluginDeclOf "t2" "")
        BS.writeFile (tmp </> "style.toml") horizontalStyle
        TIO.writeFile (tmp </> "a.gm") "x\n"
        lockIn [("t1", "tsv-table.wasm"), ("t2", "tsv-table.wasm")] tmp $ do
          r <- build (defaultOptions tmp)
          atManifestTop r >>= (@?= [(DiagnosticCode "G06006", "複数のプラグインが同じブロックコマンドを提供しています: @tsv-table（t1、t2）")]),
    testCase "data of 64 MiB reaches the plugin, which reports its own limit" $
      withTsvTable "data = { big = \"big.tsv\" }\n" "@tsv-table big\n" [] $ \tmp -> do
        BS.writeFile (tmp </> "big.tsv") (BS.replicate (fromIntegral maxDataBytes) 0x61)
        (bs, ds) <- blocksOf tmp
        bs @?= []
        map fst ds @?= [DiagnosticCode "tt/limit"],
    -- docs/adr/0129: about 7.2e8 of the 1e9 instructions of a call
    testCase "the largest TSV the plugin takes, of Japanese text, stays within the fuel" $ do
      let cellOf r c = T.pack ("c" <> show r <> "-" <> show c) <> T.replicate 52 "あ"
          tsv = TE.encodeUtf8 (T.unlines [T.intercalate "\t" [cellOf r c | c <- [1 .. 5 :: Int]] | r <- [1 .. 10000 :: Int]])
      assertBool (show (BS.length tsv)) (BS.length tsv <= 8 * 1024 * 1024 && BS.length tsv > 8 * 1000 * 1000)
      withTsvTable "data = { big = \"big.tsv\" }\n" "@tsv-table big\n" [("big.tsv", tsv)] $ \tmp -> do
        (bs, ds) <- blocksOf tmp
        ds @?= []
        map (fmap (\(_, h, rows) -> (length h, length rows)) . tableShape . blockBody) bs @?= [Just (5, 9999)],
    testCase "no G02009 for the block commands after a plugin fails to load, as G02022 (docs/adr/0122)" $
      withTsvTable "data = { sales = \"none.tsv\" }\n" "@tsv-table sales\n\n[tsv-table sales]\n" [] $ \tmp -> do
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G06101"],
    testCase "the table is built to text" $
      withTsvTable "data = { sales = \"s.tsv\" }\n" "@tsv-table sales\n" [("s.tsv", salesTsv)] $ \tmp -> do
        r <- build (defaultOptions tmp)
        filter isError (brDiagnostics r) @?= []
        out <- TIO.readFile (tmp </> "build/text/horizontal/a.txt")
        assertBool (T.unpack out) ("みかん" `T.isInfixOf` out)
  ]

{- | A small CBOR encoder for the responses of check-data.wat: arrays,
text strings, small unsigned integers and null.
-}
data Cbor = CArr [Cbor] | CText T.Text | CUInt Int | CNull

cborBytes :: Cbor -> BS.ByteString
cborBytes = \case
  CArr xs -> headOf 0x80 (length xs) <> foldMap cborBytes xs
  CText t -> let b = TE.encodeUtf8 t in headOf 0x60 (BS.length b) <> b
  CUInt n -> headOf 0x00 n
  CNull -> BS.singleton 0xf6
  where
    headOf major n
      | n < 24 = BS.singleton (fromIntegral (major + n))
      | n < 256 = BS.pack [fromIntegral (major + 24), fromIntegral n]
      | otherwise = BS.pack [fromIntegral (major + 25), fromIntegral (n `div` 256), fromIntegral (n `mod` 256)]

{- | A one-chapter project, a.gm, with check-data.wat built into
plugins/check.wasm and declared as lk (docs/adr/0120), with the data
table = "t.tsv" and the given files. The plugin provides the command
shout and takes the data table; it answers golem_invoke and
golem_check_data with the given responses.
-}
withChecker :: BS.ByteString -> [Cbor] -> T.Text -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withChecker invoke check source files k = withSystemTempDirectory "golem-check" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> "\n[plugins.lk]\npath = \"plugins/check.wasm\"\ndata = { table = \"t.tsv\" }\n")
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  TIO.writeFile (tmp </> "a.gm") source
  src <- TIO.readFile "../golem-plugin/test/plugins/check-data.wat"
  let describe = BS.concat [BS.pack [0xa2], cborBytes (CText "commands"), cborBytes (CArr [CText "shout"]), cborBytes (CText "data"), cborBytes (CArr [CText "table"])]
      checkB = cborBytes (CArr check)
      escape = T.pack . concatMap (\w -> '\\' : hex2 w) . BS.unpack
      hex2 w = [digit (w `div` 16), digit (w `mod` 16)]
      digit d = "0123456789abcdef" !! fromIntegral d
      filled =
        T.replace "{{DESCRIBE}}" (escape describe)
          . T.replace "{{DESCRIBE_LEN}}" (T.pack (show (BS.length describe)))
          . T.replace "{{RESPONSE}}" (escape invoke)
          . T.replace "{{RESPONSE_LEN}}" (T.pack (show (BS.length invoke)))
          . T.replace "{{CHECK}}" (escape checkB)
          . T.replace "{{CHECK_LEN}}" (T.pack (show (BS.length checkB)))
          $ src
  wasm <- watToWasm filled >>= either (assertFailure . T.unpack) pure
  writeFiles tmp (("plugins/check.wasm", wasm) : files)
  k tmp

-- | [[], []]: no inlines and no diagnostics.
emptyAnswer :: BS.ByteString
emptyAnswer = cborBytes (CArr [CArr [], CArr []])

{- | An answer with a diagnostic at a span of no request, G06009 if a
command is called at all.
-}
calledAnswer :: BS.ByteString
calledAnswer = cborBytes (CArr [CArr [], CArr [CArr [CText "called", CUInt 1, CArr [CUInt 99, CUInt 0, CUInt 0], CText "m"]]])

-- | A data-diagnostic of golem_check_data.
dataDiag :: T.Text -> Int -> T.Text -> Maybe Int -> T.Text -> Cbor
dataDiag code sev name = noNameDiag' code sev (CText name)

-- | A data-diagnostic of golem_check_data with a null name (docs/adr/0136).
noNameDiag :: T.Text -> Int -> Maybe Int -> T.Text -> Cbor
noNameDiag code sev = noNameDiag' code sev CNull

noNameDiag' :: T.Text -> Int -> Cbor -> Maybe Int -> T.Text -> Cbor
noNameDiag' code sev name line msg = CArr [CText code, CUInt sev, name, maybe CNull CUInt line, CText msg]

-- | Where each diagnostic of a build points: the file, the line and the column, as rendered.
pointedAt :: BuildResult -> [T.Text]
pointedAt r = filter (not . T.null) [l | l <- T.lines (renderHuman (brSources r) (brDiagnostics r)), ": error[" `T.isInfixOf` l || ": warning[" `T.isInfixOf` l]

-- | The check of a plugin's data at load (docs/adr/0120).
checkDataTests :: [TestTree]
checkDataTests =
  [ testCase "an error of golem_check_data points at its line of the file of the data, once, and no command runs" $
      withChecker calledAnswer [dataDiag "tsv-columns" 0 "table" (Just 2) "欄の数が違います"] "[shout]\n\n[shout]\n\n[shout]\n" [("t.tsv", "a\tb\nc\nd\te\n")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        pointedAt r @?= ["t.tsv:2:1: error[lk/tsv-columns]: 欄の数が違います"]
        map (spanStart . diagSpan) (brDiagnostics r) @?= [4]
        map (Just . spanFile . diagSpan) (brDiagnostics r) @?= [sourceFileId r "t.tsv"],
    testCase "an error of the data is reported in a book that calls no command" $
      withChecker calledAnswer [dataDiag "tsv-columns" 0 "table" (Just 2) "欄の数が違います"] "本文\n" [("t.tsv", "a\tb\nc\n")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        pointedAt r @?= ["t.tsv:2:1: error[lk/tsv-columns]: 欄の数が違います"],
    testCase "no G02022 after an error of the data" $
      withChecker calledAnswer [dataDiag "tsv-empty" 0 "table" Nothing "空です"] "[shout]\n" [("t.tsv", "")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        pointedAt r @?= ["t.tsv:1:1: error[lk/tsv-empty]: 空です"],
    testCase "a warning of the data: the plugin loads and its commands run" $
      withChecker emptyAnswer [dataDiag "tsv-blank" 1 "table" (Just 1) "空の行です"] "[shout]\n" [("t.tsv", "\na\n")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        pointedAt r @?= ["t.tsv:1:1: warning[lk/tsv-blank]: 空の行です"],
    testCase "the commands of a plugin with nothing to report run" $
      withChecker calledAnswer [] "[shout]\n" [("t.tsv", "a\n")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G06009"],
    testCase "an error with a null name is at the top of manifest.toml, once, and no command runs (docs/adr/0136)" $
      withChecker calledAnswer [noNameDiag "no-data" 0 Nothing "データを渡してください"] "[shout]\n\n[shout]\n" [("t.tsv", "a\n")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "lk/no-data", "データを渡してください")]),
    testCase "G06009: a name the plugin was not given, a line out of the file, a code of the wrong form" $
      mapM_
        ( \(d, why) -> withChecker emptyAnswer [d] "本文\n" [("t.tsv", "a\nb\n")] $ \tmp -> do
            r <- build (defaultOptions tmp)
            atManifestTop r >>= (@?= [(DiagnosticCode "G06009", "lk.golem_check_data: プラグインの出力が不正です: " <> why)])
        )
        [ (dataDiag "x" 0 "other" Nothing "m", "渡していないデータの名前です: other"),
          (dataDiag "x" 0 "table" (Just 3) "m", "データの行がありません: table: 3"),
          (dataDiag "Lookup/x" 0 "table" Nothing "m", "診断のコードの形が不正です: Lookup/x"),
          (noNameDiag "x" 0 (Just 1) "m", "データの名前のない診断に行があります")
        ]
  ]

-- | Data of any name (docs/adr/0119).
anyDataTests :: [TestTree]
anyDataTests =
  [ testCase "a plugin that declares * takes data of names the project chooses" $
      withAnyDatum "data = { table = \"t.txt\", units = \"s.txt\", weights = \"c.txt\" }\n" "[datum]\n" [("t.txt", "value"), ("s.txt", "s"), ("c.txt", "c")] $ \tmp -> do
        (inls, ds) <- lookedUp Map.empty tmp
        (texts inls, ds) @?= (["value"], []),
    testCase "G06102: a name of data of the wrong form, for a plugin that declares *" $
      withAnyDatum "data = { table = \"t.txt\", Sales = \"t.txt\" }\n" "[datum]\n" [("t.txt", "value")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "G06102", "プラグインが受け取らないデータの名前です: lk.Sales（受け取る名前: 英小文字で始まる任意の名前）")])
  ]

-- | A plugin of the project's path (docs/adr/0109).
localPluginTests :: [TestTree]
localPluginTests =
  [ testCase "a plugin of the project's path runs without plugins.lock" $
      withLocal "path = \"plugins/datum.wasm\"\ndata = { table = \"v.txt\" }\n" "[datum]\n" [("v.txt", "value")] $ \tmp -> do
        (inls, ds) <- lookedUp Map.empty tmp
        (texts inls, ds) @?= (["value"], [])
        listDirectory tmp >>= (@?= False) . elem "plugins.lock",
    testCase "the file of a plugin of the project's path is watched like the files of @table" $
      withLocal "path = \"./plugins/datum.wasm\"\n" "本文\n" [] $ \tmp -> do
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        assertBool (show (evTableFiles e)) ("plugins/datum.wasm" `elem` evTableFiles e),
    testCase "G06104: a plugin of the project's path that is not there" $
      withLocal "path = \"plugins/none.wasm\"\n" "本文\n" [] $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "G06104", "プラグインのファイルがありません: lk: plugins/none.wasm")]),
    testCase "G03003: a path of a plugin outside the project, absolute or a URL" $
      mapM_
        ( \(path, why) -> withLocal ("path = \"" <> path <> "\"\n") "本文\n" [] $ \tmp -> do
            r <- build (defaultOptions tmp)
            atManifestTop r >>= (@?= [(DiagnosticCode "G03003", why <> ": lk: " <> TE.decodeUtf8 path)])
        )
        [ ("../datum.wasm", "プロジェクトルートの外を指しています"),
          ("/etc/hosts", "絶対パスは使えません"),
          ("https://example.com/datum.wasm", "URL は使えません")
        ]
  ]

-- | The words of the glossary tests: kana sorts カーニング before 組版.
glossaryTsv :: BS.ByteString
glossaryTsv = TE.encodeUtf8 "# 語\t読み\t定義\t参照\n組版\tくみはん\t版を組むこと\nカーニング\t\t字間の調整\tkern\n組む\tくむ\t版を作ること\n"

{- | A one-chapter project, a.gm, with the sample plugin glossary of
plugins/wasm (docs/adr/0126) and its words in terms.tsv, for PDF, HTML and
plain text.
-}
withGlossary :: BS.ByteString -> T.Text -> (FilePath -> IO a) -> IO a
withGlossary = withGlossaryOf glossaryTsv

-- | 'withGlossary' with the given terms.tsv.
withGlossaryOf :: BS.ByteString -> BS.ByteString -> T.Text -> (FilePath -> IO a) -> IO a
withGlossaryOf tsv style source k = withSystemTempDirectory "golem-glossary" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.html]\n[targets.text]\n" <> pluginDeclOf "glossary" "data = { terms = \"terms.tsv\" }\n")
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "terms.tsv") tsv
  TIO.writeFile (tmp </> "a.gm") source
  lockIn [("glossary", "glossary.wasm")] tmp (k tmp)

-- | The sample plugin glossary (docs/adr/0126) through every target.
glossaryTests :: [TestTree]
glossaryTests =
  [ -- カーニング has no reading in the TSV: the word is its reading, and it sorts before くみはん
    testCase "plain text: the words in the order of their readings, each with its definition" $
      withGlossary horizontalStyle "[term: 組版]と[term: カーニング]。\n\n@label kern\n# 字間\n\n@channel glossary\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        t <- TIO.readFile (tmp </> "build/text/horizontal/a.txt")
        t @?= "組版とカーニング。\n\n1　字間\n\nカーニング　字間の調整（→「字間」）\n組版　版を組むこと\n",
    testCase "PDF: each entry has the pages of the word, and the page of its label after the arrow" $
      withGlossary horizontalStyle ("[term: 組版]。\n\n" <> fillers 35 <> "[term: 組版]と[term: カーニング]。\n\n@label kern\n# 字間\n\n@channel glossary\n") $ \tmp -> do
        t <- T.concat . concat <$> pdfPages tmp
        assertBool (show t) ("カーニング　字間の調整（→2）　2組版　版を組むこと　1,2" `T.isSuffixOf` t),
    -- the page of the label in the numerals of [numbers], as [ref-page] in the text (docs/adr/0118)
    testCase "PDF: in vertical text the page of the label is in kanji, as [ref-page] in the text" $
      withGlossary pdfStyle "[term: カーニング]。[ref-page kern]\n\n@label kern\n# 字間\n\n@channel glossary\n" $ \tmp -> do
        ls <- concat <$> pdfPages tmp
        assertBool (show ls) ("カーニング。一" `elem` ls)
        assertBool (show ls) ("カーニング　字間の調整（→一）　一" `elem` ls),
    -- docs/adr/0127
    testCase "a headword in the argument: two forms of the word make one entry with two places" $
      withGlossary horizontalStyle "[term 組む: 組んだ]版と[term: 組む]版。\n\n@channel glossary\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetText]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        t <- TIO.readFile (tmp </> "build/text/horizontal/a.txt")
        t @?= "組んだ版と組む版。\n\n組む　版を作ること\n"
        html <- TIO.readFile (tmp </> "build/html/a.xhtml")
        (T.count "<li>" html, T.count "href=\"#c-glossary-" html + T.count "a.xhtml#c-glossary-" html) @?= (1, 2),
    testCase "G04003: the label of the fourth column is not in the book" $
      withGlossary horizontalStyle "[term: カーニング]。\n\n@channel glossary\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        [(diagCode d, diagMessage d) | d <- brDiagnostics r] @?= [(DiagnosticCode "G04003", "存在しないラベルへの参照です: kern")],
    testCase "a word the data does not have is the plugin's error, at the call; the word stays in the text" $
      withGlossary horizontalStyle "前[term: 版面]後\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        [(diagCode d, diagMessage d, spanStart (diagSpan d)) | d <- brDiagnostics r] @?= [(DiagnosticCode "glossary/unknown", "terms にない語です: 版面", 3)],
    -- docs/adr/0120: the check of the data at load, through a real plugin
    testCase "a bad line of terms is reported once, at its line, however many [term] the book has" $
      withGlossaryOf (TE.encodeUtf8 "組版\tくみはん\t版を組むこと\n\nx\ty\n") horizontalStyle "[term: 組版]と[term: 組版]と[term: 組版]。\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        pointedAt r @?= ["terms.tsv:3:1: error[glossary/tsv-columns]: terms の 3 行めの欄の数が 3 か 4 ではありません"],
    testCase "a bad line of terms is reported in a book without [term]" $
      withGlossaryOf (TE.encodeUtf8 "組版\t\t版を組むこと\n") horizontalStyle "本文。\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        pointedAt r @?= ["terms.tsv:1:1: error[glossary/tsv-no-reading]: terms の 1 行めの語は漢字を含むので、読みが要ります: 組版"],
    testCase "glossary/no-data: no terms, once at the top of manifest.toml, with or without [term] (docs/adr/0136)" $
      mapM_
        ( \source -> withSystemTempDirectory "golem-glossary" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "[targets.text]\n" <> pluginDeclOf "glossary" "")
            BS.writeFile (tmp </> "style.toml") horizontalStyle
            TIO.writeFile (tmp </> "a.gm") source
            lockIn [("glossary", "glossary.wasm")] tmp $ do
              r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
              atManifestTop r >>= (@?= [(DiagnosticCode "glossary/no-data", "manifest.toml で data の terms を渡してください")])
        )
        ["本文。\n", "[term: 組版]と[term: 組版]と[term: 組版]。\n"],
    -- the copies of a title do not count (docs/adr/0145)
    testCase "PDF: a word of a heading on page 1 has the page 1, with @toc or [ref-title] on page 2" $
      mapM_
        ( \copy -> withGlossary horizontalStyle ("@label h\n# [term: 組版]の章\n\n" <> fillers 35 <> copy <> "\n\n@channel glossary\n") $ \tmp -> do
            t <- T.concat . concat <$> pdfPages tmp
            assertBool (show t) ("組版　版を組むこと　1" `T.isSuffixOf` t)
        )
        ["@toc", "参照[ref-title h]"],
    testCase "HTML: a word of a heading copied by [ref-title] links to the heading only" $
      withGlossary horizontalStyle "@label h\n# [term: 組版]の章\n\n参照[ref-title h]。\n\n@channel glossary\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        html <- TIO.readFile (tmp </> "build/html/a.xhtml")
        (T.count "id=\"c-glossary-" html, T.count "href=\"#c-glossary-" html + T.count "a.xhtml#c-glossary-" html) @?= (1, 1),
    testCase "HTML: an index mark nested in a style of a heading has no id in @toc" $
      withGlossary horizontalStyle "@toc\n\n# [strong: [index reading=はんめん: 版面]と]\n\n@index\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        html <- TIO.readFile (tmp </> "build/html/a.xhtml")
        T.count "id=\"i-" html @?= 1,
    testCase "HTML: a word and an index mark in a heading have their ids once, not again in @toc of the same file" $
      withGlossary horizontalStyle "@toc\n\n# [term: 組版]と[index reading=はんめん: 版面]\n\n@channel glossary\n\n@index\n" $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        html <- TIO.readFile (tmp </> "build/html/a.xhtml")
        map (`T.count` html) ["id=\"c-glossary-", "id=\"i-"] @?= [1, 1],
    testCase "HTML and EPUB: the list links to the words in another file; the same bytes twice" $
      withPlugins [("glossary", "glossary.wasm")] (pluginDeclOf "glossary" "data = { terms = \"terms.tsv\" }\n") $ \tmp -> do
        BS.writeFile (tmp </> "terms.tsv") (TE.encodeUtf8 "組版\tくみはん\t版を組むこと\tintro\n")
        TIO.appendFile (tmp </> "chapters/01.gm") "\n[term: 組版]を試す。\n"
        TIO.appendFile (tmp </> "chapters/02.gm") "\n# 用語集\n\n@channel glossary\n"
        let out = do
              r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
              assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
              (,,) <$> TIO.readFile (tmp </> "build/html/chapters/01.xhtml") <*> TIO.readFile (tmp </> "build/html/chapters/02.xhtml") <*> BS.readFile (tmp </> "build/epub/book.epub")
        (one, two, epub) <- out
        assertBool (T.unpack one) ("<span id=\"c-glossary-" `T.isInfixOf` one)
        assertBool (T.unpack two) ("<section class=\"channel\" data-channel=\"glossary\">" `T.isInfixOf` two)
        assertBool (T.unpack two) ("<li>組版　版を組むこと（→<a href=\"../chapters/01.xhtml#" `T.isInfixOf` two)
        assertBool (T.unpack two) ("） <a href=\"../chapters/01.xhtml#c-glossary-" `T.isInfixOf` two)
        again <- out
        again @?= (one, two, epub)
  ]

{- | A two-chapter project, a.gm and b.gm, with a sample ruby plugin of
plugins/wasm declared as the given name with the given data, as a filter of
both chapters, and the given files.
-}
withRubyFilter :: T.Text -> BS.ByteString -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withRubyFilter name decl files k = withSystemTempDirectory "golem-ruby" $ \tmp -> do
  let n = TE.encodeUtf8 name
  BS.writeFile (tmp </> "manifest.toml") $
    TE.encodeUtf8 (manifestToml testManifest {tmChapters = ["a.gm", "b.gm"], tmTargets = ["text"]})
      <> pluginDeclOf n decl
      <> "\n[[filters]]\nplugin = \""
      <> n
      <> "\"\nfilter = \""
      <> n
      <> "\"\nfiles = [\"a.gm\", \"b.gm\"]\n"
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  writeFiles tmp files
  lockIn [(name, T.unpack name <> ".wasm")] tmp (k tmp)

{- | The paragraphs of each chapter after the filters, a ruby as its bases
each followed by 《reading》, and every diagnostic with the file it is in.
-}
rubyText :: FilePath -> IO ([(FilePath, [T.Text])], [(DiagnosticCode, Maybe FilePath, T.Text)])
rubyText tmp = do
  e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
  let srcs = projectSources (evProject e)
      pathOf fid = sfPath <$> Map.lookup fid srcs
      paras = [(sfPath sf, [T.concat (map shown is) | b <- docBlocks (erDocument r), Paragraph _ is <- [blockBody b]]) | (fid, sf) <- Map.toList srcs, Just r <- [Map.lookup fid (evResults e)]]
      shown = \case
        Text _ t -> t
        Ruby _ _ segs -> T.concat [T.concat (map inlineText (rsBase s)) <> maybe "" (\r -> "《" <> r <> "》") (rsReading s) | s <- segs]
        _ -> ""
  pure (sort paras, [(diagCode d, pathOf (spanFile (diagSpan d)), diagMessage d) | d <- evDiagnostics e])

-- | The sample plugin sou-ruby (docs/adr/0130).
souRubyTests :: [TestTree]
souRubyTests =
  [ testCase "with the TSV only: every word gets its ruby, a kanji the TSV does not have is a warning once a file" $
      withRubyFilter "sou-ruby" "data = { words = \"words.tsv\" }\n" [("words.tsv", TE.encodeUtf8 "東京\tとうきょう\n住/む\tす/\n"), ("a.gm", TE.encodeUtf8 "東京に住む。大阪と大阪。\n\n東京。\n"), ("b.gm", TE.encodeUtf8 "大阪の東京。\n")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        (paras, ds) <- rubyText tmp
        paras @?= [("a.gm", ["東京《とうきょう》に住《す》む。大阪と大阪。", "東京《とうきょう》。"]), ("b.gm", ["大阪の東京《とうきょう》。"])]
        ds
          @?= [ (DiagnosticCode "sou-ruby/unread", Just "a.gm", "読みの分からない漢字です: 大阪"),
                (DiagnosticCode "sou-ruby/unread", Just "b.gm", "読みの分からない漢字です: 大阪")
              ],
    testCase "some of the files of a dictionary: sou-ruby/dict, once for each file of the filter" $
      withRubyFilter "sou-ruby" "data = { words = \"words.tsv\", dict-trie = \"dict.trie\", dict-unk = \"unk.bin\" }\n" [("words.tsv", TE.encodeUtf8 "東京\tとうきょう\n"), ("dict.trie", "x"), ("unk.bin", "x"), ("a.gm", TE.encodeUtf8 "東京。\n"), ("b.gm", TE.encodeUtf8 "東京。\n")] $ \tmp -> do
        (paras, ds) <- rubyText tmp
        paras @?= [("a.gm", ["東京。"]), ("b.gm", ["東京。"])]
        let missing = "辞書のファイルが足りません: dict-char-def、dict-matrix、dict-metadata、dict-vals、dict-vals-idx、dict-words、dict-words-idx"
        ds @?= [(DiagnosticCode "sou-ruby/dict", Just f, missing) | f <- ["a.gm", "b.gm"]]
  ]

-- | The sample plugin first-ruby (docs/adr/0131).
firstRubyTests :: [TestTree]
firstRubyTests =
  [ testCase "the first occurrence in each file gets ruby, b.gm again; a ruby of the source counts" $
      withRubyFilter "first-ruby" "data = { words = \"words.tsv\" }\n" [("words.tsv", TE.encodeUtf8 "東京\tとうきょう\n大阪\tおおさか\n"), ("a.gm", TE.encodeUtf8 "# 東京\n\n東京と[ruby: 大阪|おおさか]。\n\n東京と大阪。\n"), ("b.gm", TE.encodeUtf8 "大阪と東京と東京。\n")] $ \tmp -> do
        (paras, ds) <- rubyText tmp
        paras @?= [("a.gm", ["東京《とうきょう》と大阪《おおさか》。", "東京と大阪。"]), ("b.gm", ["大阪《おおさか》と東京《とうきょう》と東京。"])]
        ds @?= [],
    testCase "an error of the TSV is reported once for each file of the filter" $
      withRubyFilter "first-ruby" "data = { words = \"words.tsv\" }\n" [("words.tsv", TE.encodeUtf8 "東京\n"), ("a.gm", TE.encodeUtf8 "東京。\n"), ("b.gm", TE.encodeUtf8 "東京。\n")] $ \tmp -> do
        (paras, ds) <- rubyText tmp
        paras @?= [("a.gm", ["東京。"]), ("b.gm", ["東京。"])]
        ds @?= [(DiagnosticCode "first-ruby/tsv", Just f, "words の 1 行め: 語と読みをタブで区切った二つの欄がありません") | f <- ["a.gm", "b.gm"]],
    testCase "first-ruby/no-words: no words in the data, once at the top of manifest.toml (docs/adr/0136)" $
      withRubyFilter "first-ruby" "" [("a.gm", TE.encodeUtf8 "東京。\n"), ("b.gm", "")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "first-ruby/no-words", "manifest.toml の data で words を渡してください")])
  ]

-- | The data a project passes to a plugin (docs/adr/0105).
dataTests :: [TestTree]
dataTests =
  [ testCase "the sample plugin lookup gives the value of a key in its TSV (docs/adr/0106)" $
      withDataPlugin "lookup.wasm" "data = { table = \"data/words.tsv\" }\n" "[lookup: key]\n" [("data/words.tsv", "# words\nkey\tvalue\nkey\tsecond\n")] $ \tmp -> do
        (inls, ds) <- lookedUp Map.empty tmp
        (texts inls, ds) @?= (["value"], []),
    testCase "the code of a plugin's diagnostic has the name of the plugin before it, in human and JSON output (docs/adr/0108)" $
      withSystemTempDirectory "golem-data" $ \tmp -> do
        BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> pluginDeclOf "lookup" "data = { table = \"w.tsv\" }\n")
        BS.writeFile (tmp </> "style.toml") horizontalStyle
        TIO.writeFile (tmp </> "a.gm") "[lookup: none]\n"
        BS.writeFile (tmp </> "w.tsv") "key\tvalue\n"
        lockIn [("lookup", "lookup.wasm")] tmp $ do
          r <- build (defaultOptions tmp)
          map diagCode (brDiagnostics r) @?= [DiagnosticCode "lookup/no-key"]
          let human = renderHuman (brSources r) (brDiagnostics r)
              json = renderJson (brSources r) (brDiagnostics r)
          assertBool (T.unpack human) ("error[lookup/no-key]" `T.isInfixOf` human)
          assertBool (T.unpack json) ("\"code\":\"lookup/no-key\"" `T.isInfixOf` json),
    testCase "the sample plugin lookup without its data reports its own diagnostic (docs/adr/0106)" $
      withDataPlugin "lookup.wasm" "" "[lookup: key]\n" [] $ \tmp -> do
        (_, ds) <- lookedUp Map.empty tmp
        map fst ds @?= [DiagnosticCode "lk/no-table"],
    testCase "the plugin reads the file the manifest passes as data" $
      withDatum "data = { table = \"data/words.tsv\" }\n" "[datum]\n" [("data/words.tsv", "value")] $ \tmp -> do
        (inls, ds) <- lookedUp Map.empty tmp
        (texts inls, ds) @?= (["value"], []),
    testCase "without the data the plugin reports its own diagnostic" $
      withDatum "" "[datum]\n" [] $ \tmp -> do
        (_, ds) <- lookedUp Map.empty tmp
        map fst ds @?= [DiagnosticCode "lk/no-table"],
    testCase "a changed file gives the new value when the project is evaluated again" $
      withDatum "data = { table = \"words.tsv\" }\n" "[datum]\n" [("words.tsv", "one")] $ \tmp -> do
        lookedUp Map.empty tmp >>= (@?= ["one"]) . texts . fst
        BS.writeFile (tmp </> "words.tsv") "two"
        lookedUp Map.empty tmp >>= (@?= ["two"]) . texts . fst,
    testCase "the text of the editor comes before the file (as for @table, golem-eval ADR 0004)" $
      withDatum "data = { table = \"words.tsv\" }\n" "[datum]\n" [("words.tsv", "disk")] $ \tmp ->
        lookedUp (Map.fromList [("words.tsv", "editor")]) tmp >>= (@?= ["editor"]) . texts . fst,
    testCase "the files of data are watched like the files of @table" $
      withDatum "data = { table = \"./data/../words.tsv\" }\n" "[datum]\n" [("words.tsv", "v")] $ \tmp -> do
        e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
        assertBool (show (evTableFiles e)) ("words.tsv" `elem` evTableFiles e),
    testCase "G06101: a file of data that is not there" $
      withDatum "data = { table = \"none.tsv\" }\n" "[datum]\n" [] $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "G06101", "プラグインのデータのファイルがありません: lk.table: none.tsv")]),
    testCase "G06102: a name of data the plugin does not take" $
      withDatum "data = { table = \"w.tsv\", tabel = \"w.tsv\" }\n" "[datum]\n" [("w.tsv", "v")] $ \tmp -> do
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "G06102", "プラグインが受け取らないデータの名前です: lk.tabel（受け取る名前: table）")]),
    testCase "G03003: a path of data outside the project, absolute or a URL" $
      mapM_
        ( \(path, why) -> withDatum ("data = { table = \"" <> path <> "\" }\n") "[datum]\n" [] $ \tmp -> do
            r <- build (defaultOptions tmp)
            atManifestTop r >>= (@?= [(DiagnosticCode "G03003", why <> ": lk.table: " <> TE.decodeUtf8 path)])
        )
        [ ("../w.tsv", "プロジェクトルートの外を指しています"),
          ("/etc/hosts", "絶対パスは使えません"),
          ("https://example.com/w.tsv", "URL は使えません")
        ],
    testCase "G03003: a symbolic link out of the project" $
      withSystemTempDirectory "golem-outside" $ \out -> do
        BS.writeFile (out </> "w.tsv") "secret"
        withDatum "data = { table = \"w.tsv\" }\n" "[datum]\n" [] $ \tmp -> do
          createFileLink (out </> "w.tsv") (tmp </> "w.tsv")
          r <- build (defaultOptions tmp)
          atManifestTop r >>= (@?= [DiagnosticCode "G03003"]) . map fst,
    testCase "G06103: data over the limit, all the files of a plugin together" $
      withDatum "data = { table = \"big.tsv\" }\n" "[datum]\n" [] $ \tmp -> do
        BS.writeFile (tmp </> "big.tsv") (BS.replicate (fromIntegral maxDataBytes + 1) 0x20)
        r <- build (defaultOptions tmp)
        atManifestTop r >>= (@?= [(DiagnosticCode "G06103", "プラグインのデータが上限（67108864 バイト）を超えています: lk（67108865 バイト）")]),
    testCase "no G02022 after an error of the data (golem-plugin ADR 0003)" $
      withDatum "data = { table = \"none.tsv\" }\n" "[datum]\n" [] $ \tmp -> do
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G06101"]
  ]

pluginTests :: [TestTree]
pluginTests =
  channelTests
    <> dataTests
    <> localPluginTests
    <> anyDataTests
    <> checkDataTests
    <> [testGroup "the sample plugin glossary (docs/adr/0126)" glossaryTests]
    <> [testGroup "the sample plugin sou-ruby (docs/adr/0130)" souRubyTests]
    <> [testGroup "the sample plugin first-ruby (docs/adr/0131)" firstRubyTests]
    <> contextTests
    <> kansujiTests
    <> autoTcyTests
    <> tsvTableTests
    <> blockCommandTests
    <> pluginFigureTests
    <> [ testCase "a filter runs over the declared files and keeps the output" $ do
           plain <- buildAndRead Dev "build/text/horizontal/chapters/01.txt"
           filtered <- withPluginProject pluginDecl $ \tmp -> do
             r <- build (defaultOptions tmp)
             assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
             BL.fromStrict <$> BS.readFile (tmp </> "build/text/horizontal/chapters/01.txt")
           filtered @?= plain,
         testCase "G06009: a command whose answer is invalid names the command, at the call" $
           withPluginProject pluginDecl $ \tmp -> do
             BS.appendFile (tmp </> "chapters/02.gm") "\n[broken: x]\n"
             r <- build (defaultOptions tmp)
             case [d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G06009"] of
               [d] -> do
                 assertBool (show d) ("identity.broken: " `T.isPrefixOf` diagMessage d)
                 Just (spanFile (diagSpan d)) @?= sourceFileId r "chapters/02.gm"
                 assertBool (show d) (spanStart (diagSpan d) > 0)
               ds -> assertFailure (show ds),
         testCase "G06009: a filter that fails points at the top of the file it was applied to" $
           withPlugins [("loop", "loop-filter.wat")] (pluginDeclOf "loop" "" <> filterDecl "loop" "spin") $ \tmp -> do
             r <- build (defaultOptions tmp)
             case [d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G06009"] of
               [d] -> do
                 assertBool (show d) ("loop.spin: " `T.isPrefixOf` diagMessage d)
                 Just (diagSpan d) @?= topOf r "chapters/01.gm"
               ds -> assertFailure (show ds),
         -- docs/adr ADR 0101
         testCase "G06100: a command that writes NaN, Infinity or -Infinity in a deferred expression, at the call" $
           mapM_
             ( \(name, v) -> withPlugins [("nf", "nonfinite.wat")] (pluginDeclOf "nf" "") $ \tmp -> do
                 BS.appendFile (tmp </> "chapters/02.gm") ("\n[" <> TE.encodeUtf8 name <> "]\n")
                 r <- build (defaultOptions tmp)
                 case [d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G06100"] of
                   [d] -> do
                     diagMessage d @?= "nf." <> name <> ": 遅延した式に有限でない浮動小数点数（" <> v <> "）があります"
                     Just (spanFile (diagSpan d)) @?= sourceFileId r "chapters/02.gm"
                   ds -> assertFailure (show ds)
             )
             nonFinite,
         testCase "G06100: a filter that writes NaN, Infinity or -Infinity in a deferred expression, at the top of the file" $
           mapM_
             ( \(name, v) -> withPlugins [("nf", "nonfinite.wat")] (pluginDeclOf "nf" "" <> filterDecl "nf" (TE.encodeUtf8 name)) $ \tmp -> do
                 r <- build (defaultOptions tmp)
                 case [d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G06100"] of
                   [d] -> do
                     diagMessage d @?= "nf." <> name <> ": 遅延した式に有限でない浮動小数点数（" <> v <> "）があります"
                     Just (diagSpan d) @?= topOf r "chapters/01.gm"
                   ds -> assertFailure (show ds)
             )
             nonFinite,
         testCase "G06002: a plugin missing from the lock, or with another URL there" $
           withPluginProject pluginDecl $ \tmp -> do
             locked <- TIO.readFile (tmp </> "plugins.lock")
             BS.writeFile (tmp </> "plugins.lock") ""
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G06002", "plugins.lock にないプラグインです。golem plugin lock を実行してください: identity")])
             r' <- withEnv "XDG_CACHE_HOME" (tmp </> "empty-cache") $ build (defaultOptions tmp) {optCheckOnly = True}
             map diagCode (brDiagnostics r') @?= [DiagnosticCode "G06002"]
             TIO.writeFile (tmp </> "plugins.lock") (T.replace "identity.wasm" "other.wasm" locked)
             r'' <- build (defaultOptions tmp)
             atManifestTop r'' >>= (@?= [(DiagnosticCode "G06002", "plugins.lock の URL が manifest.toml と違います。golem plugin lock を実行してください: identity")]),
         testCase "G06002 only: no G02022 for the commands after a plugin fails to load" $
           withPluginProject pluginDecl $ \tmp -> do
             BS.writeFile (tmp </> "plugins.lock") ""
             BS.appendFile (tmp </> "chapters/02.gm") "\n[broken: x]\n"
             r <- build (defaultOptions tmp)
             map diagCode (brDiagnostics r) @?= [DiagnosticCode "G06002"],
         testCase "G06003: an uncached plugin asks for golem plugin fetch" $
           withPluginProject pluginDecl $ \tmp -> do
             r <- withEnv "XDG_CACHE_HOME" (tmp </> "empty-cache") $ build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G06003", "キャッシュにないプラグインです。golem plugin fetch を実行してください: identity")]),
         testCase "G06004: a cached plugin that does not match its hash" $
           withPluginProject pluginDecl $ \tmp -> do
             cache <- defaultCacheDir
             files <- listDirectory cache
             forM_ files $ \f -> do
               b <- BS.readFile (cache </> f)
               BS.writeFile (cache </> f) (BS.cons (BS.head b + 1) (BS.tail b))
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G06004", "キャッシュの配布物のハッシュが plugins.lock と一致しません: identity")]),
         testCase "G06005: a plugin that cannot be loaded" $
           withPlugins [("imports", "imports.wat")] (pluginDeclOf "imports" "") $ \tmp -> do
             r <- build (defaultOptions tmp)
             ds <- atManifestTop r
             map fst ds @?= [DiagnosticCode "G06005"]
             assertBool (show ds) (all (T.isPrefixOf "imports: プラグインが import を要求しています" . snd) ds),
         testCase "G06006: one per command, naming the plugins in order" $
           withPlugins [("b", "identity.wat"), ("a", "identity.wat")] (pluginDeclOf "b" "" <> pluginDeclOf "a" "") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G06006", "複数のプラグインが同じコマンドを提供しています: broken（a、b）")]),
         testCase "G06007: a collision with a built-in command, overridable or not" $
           withPlugins [("names", "builtin-names.wat")] (pluginDeclOf "names" "") $ \tmp -> do
             r <- build (defaultOptions tmp)
             ds <- atManifestTop r
             sort ds
               @?= sort
                 [ (DiagnosticCode "G06007", "組み込みのコマンドと衝突しています（overrides で宣言してください）: names.ruby"),
                   (DiagnosticCode "G06007", "上書きできない組み込みのコマンドと衝突しています: names.note"),
                   -- link is built in, and a plugin may not override it (docs/adr ADR 0182)
                   (DiagnosticCode "G06007", "上書きできない組み込みのコマンドと衝突しています: names.link")
                 ],
         testCase "G06008: one per name in overrides" $ do
           let g06008 m = [(DiagnosticCode "G06008", m)]
           withPluginProject (pluginDeclWith "overrides = [\"ruby\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= g06008 "プラグインが提供していないコマンドを overrides に書いています: identity.ruby")
           withPluginProject (pluginDeclWith "overrides = [\"xyz\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= g06008 "プラグインが提供していないコマンドを overrides に書いています: identity.xyz")
           -- link may not be overridden either (docs/adr ADR 0182)
           withPlugins [("names", "builtin-names.wat")] (pluginDeclOf "names" "overrides = [\"note\", \"ruby\", \"link\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             ds <- atManifestTop r
             sort ds @?= sort (g06008 "上書きできる組み込みのコマンドではありません: names.note" <> g06008 "上書きできる組み込みのコマンドではありません: names.link"),
         -- docs/adr ADR 0031
         testCase "overrides = [\"code\"] loads; overrides = [\"aki\"] is G06008" $ do
           withPlugins [("cd", "override-code.wat")] (pluginDeclOf "cd" "overrides = [\"code\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             brDiagnostics r @?= []
           withPlugins [("ak", "override-aki.wat")] (pluginDeclOf "ak" "overrides = [\"aki\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G06008", "上書きできる組み込みのコマンドではありません: ak.aki")]),
         testCase "evPluginCommands: the names of the commands of the plugins" $
           withPlugins [("identity", "identity.wat")] (pluginDeclOf "identity" "") $ \tmp -> do
             e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
             evPluginCommands e @?= ["broken"],
         testCase "with a syntax error the plugins are loaded: their names, the hook of evReevaluate and their diagnostics" $ do
           withPlugins [("identity", "identity.wat")] (pluginDeclOf "identity" "") $ \tmp -> do
             TIO.appendFile (tmp </> "chapters/01.gm") "\n[broken: x]\n"
             TIO.appendFile (tmp </> "chapters/02.gm") "\n本文の [b\n"
             e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
             evPluginCommands e @?= ["broken"]
             case [(fid, sf) | (fid, sf) <- Map.toList (projectSources (evProject e)), sfPath sf == "chapters/01.gm"] of
               [(fid, sf)] -> do
                 let codes = map diagCode (erDiagnostics (evReevaluate e fid sf))
                 assertBool (show codes) (DiagnosticCode "G02022" `notElem` codes)
                 codes @?= [DiagnosticCode "G02002", DiagnosticCode "G02002", DiagnosticCode "G06009"]
               other -> assertFailure (show (map fst other))
           withPlugins [("identity", "identity.wat")] (pluginDeclOf "identity" "") $ \tmp -> do
             TIO.appendFile (tmp </> "chapters/02.gm") "\n本文の [b\n"
             BS.writeFile (tmp </> "plugins.lock") ""
             e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
             let codes = map diagCode (evDiagnostics e)
             assertBool (show codes) (DiagnosticCode "G06002" `elem` codes)
             assertBool (show codes) (any (\(DiagnosticCode c) -> "G01" `T.isPrefixOf` c) codes)
             evPluginCommands e @?= [],
         testCase "G06010: a filter of an undeclared plugin, or one the plugin does not provide" $ do
           withPluginProject (pluginDeclOf "identity" "" <> filterDecl "ghost" "x") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G06010", "宣言されていないプラグインです: ghost（フィルタ ghost.x）")])
           withPluginProject (pluginDeclOf "identity" "" <> filterDecl "identity" "nope") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G06010", "プラグインが提供していないフィルタです: identity.nope")]),
         testCase "the hook keeps overrides by type and other commands by name (docs/adr ADR 0027)" $ do
           -- (all names, the names of the overrides): the commands of the plugins
           -- and the overrides they declare
           let keysOf plugins extra = withPlugins plugins extra $ \tmp -> do
                 cache <- defaultCacheDir
                 lockText <- TIO.readFile (tmp </> "plugins.lock")
                 m <- TIO.readFile (tmp </> "manifest.toml") >>= either (assertFailure . show) pure . parseManifest (FileId 0)
                 hook <- loadPlugins tmp Map.empty cache (FileId 0) (FileId 1) lockText (FileId 2) (HostContext "horizontal" "kanji") (\_ _ _ _ -> Nothing) m >>= either (assertFailure . show) pure . lpHook
                 let overrides = map (builtinName . Overridable) (Map.keys (phOverrides hook))
                 pure (sort (overrides <> map unPluginCommandName (Map.keys (phCommands hook))), sort overrides)
           keysOf [("ov", "override-ruby.wat")] (pluginDeclOf "ov" "overrides = [\"ruby\"]\n") >>= (@?= (["greet", "ruby"], ["ruby"]))
           keysOf [("identity", "identity.wat")] (pluginDeclOf "identity" "") >>= (@?= (["broken"], [])),
         testCase "G06011: plugins.lock that cannot be read points into plugins.lock" $
           withPluginProject pluginDecl $ \tmp -> do
             BS.writeFile (tmp </> "plugins.lock") "[plugins.identity\nurl = 1\n"
             r <- build (defaultOptions tmp)
             map diagCode (brDiagnostics r) @?= [DiagnosticCode "G06011"]
             assertBool "plugins.lock is a source" (isJust (sourceFileId r "plugins.lock"))
             map (Just . spanFile . diagSpan) (brDiagnostics r) @?= [sourceFileId r "plugins.lock"]
       ]
  where
    pluginDecl = pluginDeclWith ""
    -- the commands and filters of nonfinite.wat and the values they write (docs/adr ADR 0101)
    nonFinite :: [(T.Text, T.Text)]
    nonFinite = [("nan", "NaN"), ("inf", "Infinity"), ("ninf", "-Infinity")]
    pluginDeclWith extra = pluginDeclOf "identity" extra <> filterDecl "identity" "same"
