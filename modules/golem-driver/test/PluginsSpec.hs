module PluginsSpec (pluginTests, cacheHomeRestored) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.IR (Block (..), BlockBody (..), Document (..), Inline, InlineF (..))
import Golem.Driver
import Golem.Driver.Pdf (PdfInput (..), layoutPages)
import Golem.Driver.Plugins (loadPlugins)
import Golem.Eval.Builtin (BuiltinInline (..), builtinName, unPluginCommandName)
import Golem.Eval.File (EvalResult (..), PluginHook (..))
import Golem.Plugin (maxDataBytes, watToWasm)
import Golem.Plugin.Lock (defaultCacheDir, lockPlugins, renderLock)
import Golem.Project (Project (..), ProjectFailure (..), SourceFile (..))
import Golem.Project.Manifest (parseManifest)
import Golem.Syntax
import Golem.TestSupport.Env (withEnv)
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.Directory (createFileLink, listDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

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
  layoutPages fakeProvider (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing Map.empty (chapterMasters (evProject e)) (evStyleFile e) Map.empty)
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
  e <- evaluateProjectWith overlay Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
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
withAnyDatum decl source files k = withSystemTempDirectory "golem-any" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["text"]}) <> "\n[plugins.lk]\npath = \"datum.wasm\"\n" <> decl)
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  TIO.writeFile (tmp </> "a.gm") source
  src <- TIO.readFile "../golem-plugin/test/plugins/datum.wat"
  let anyName =
        T.replace "(i64.const 29)" "(i64.const 25)"
          . T.replace "\"\\a2\\64data\\81\\65table\\68commands" "\"\\a2\\64data\\81\\61*\\68commands"
  assertBool "datum.wat declares table" (anyName src /= src)
  wasm <- watToWasm (anyName src) >>= either (assertFailure . T.unpack) pure
  writeFiles tmp (("datum.wasm", wasm) : files)
  k tmp

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
                   (DiagnosticCode "G06007", "上書きできない組み込みのコマンドと衝突しています: names.note")
                 ],
         testCase "G06008: one per name in overrides" $ do
           let g06008 m = [(DiagnosticCode "G06008", m)]
           withPluginProject (pluginDeclWith "overrides = [\"ruby\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= g06008 "プラグインが提供していないコマンドを overrides に書いています: identity.ruby")
           withPluginProject (pluginDeclWith "overrides = [\"xyz\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= g06008 "プラグインが提供していないコマンドを overrides に書いています: identity.xyz")
           withPlugins [("names", "builtin-names.wat")] (pluginDeclOf "names" "overrides = [\"note\", \"ruby\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= g06008 "上書きできる組み込みのコマンドではありません: names.note"),
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
                 hook <- loadPlugins tmp Map.empty cache (FileId 0) (FileId 1) lockText m >>= either (assertFailure . show) pure
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
