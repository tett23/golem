module PluginsSpec (pluginTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Driver.Pdf (PdfInput (..), layoutPages)
import Golem.Driver.Plugins (loadPlugins)
import Golem.Eval.Builtin (BuiltinInline (..), builtinName, unPluginCommandName)
import Golem.Eval.File (EvalResult (..), PluginHook (..))
import Golem.Plugin (watToWasm)
import Golem.Plugin.Lock (defaultCacheDir, lockPlugins, renderLock)
import Golem.Project (Project (..), ProjectFailure (..), SourceFile (..))
import Golem.Project.Manifest (parseManifest)
import Golem.Syntax
import Support
import System.Directory (listDirectory)
import System.Environment (setEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

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
  lockIn plugins tmp
  k tmp

{- | The plugins (name, wat file of golem-plugin's tests) locked in
plugins.lock of a project and cached; each is at
https://example.com/<name>.wasm.
-}
lockIn :: [(T.Text, FilePath)] -> FilePath -> IO ()
lockIn plugins tmp = do
  served <- mapM serve plugins
  setEnv "XDG_CACHE_HOME" (tmp </> "cache")
  cache <- defaultCacheDir
  r <- lockPlugins (\u -> pure (maybe (Left "404") Right (lookup u served))) cache (Map.fromList [(name, pluginUrl name) | (name, _) <- plugins])
  either (assertFailure . show) (TIO.writeFile (tmp </> "plugins.lock") . renderLock) r
  where
    pluginUrl name = "https://example.com/" <> name <> ".wasm"
    serve (name, wat) = do
      src <- TIO.readFile ("../golem-plugin/test/plugins" </> wat)
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
  lockIn [("chan", "channels.wat")] tmp
  k tmp

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
  [ testCase "G0612: a reserved name and a malformed name" $
      withPlugins [("bad", "channels-bad.wat")] (pluginDeclOf "bad" "") $ \tmp -> do
        r <- build (defaultOptions tmp)
        ds <- atManifestTop r
        sort ds
          @?= sort
            [ (DiagnosticCode "G0612", "bad: このチャネルの名前は使えません: index"),
              (DiagnosticCode "G0612", "bad: このチャネルの名前は使えません: Glossary")
            ],
    testCase "G0612: two plugins declare glossary" $
      withPlugins [("a", "channels.wat"), ("b", "channels.wat")] (pluginDeclOf "a" "" <> pluginDeclOf "b" "") $ \tmp -> do
        r <- build (defaultOptions tmp)
        ds <- atManifestTop r
        [d | d@(DiagnosticCode "G0612", _) <- ds]
          @?= [ (DiagnosticCode "G0612", "複数のプラグインが同じチャネルを宣言しています: glossary（a、b）"),
                (DiagnosticCode "G0612", "複数のプラグインが同じチャネルを宣言しています: people（a、b）")
              ],
    testCase "no G0290 after the plugins failed to load" $
      withPlugins [("chan", "channels.wat")] (pluginDeclOf "chan" "") $ \tmp -> do
        BS.writeFile (tmp </> "plugins.lock") ""
        BS.appendFile (tmp </> "chapters/02.gm") "\n@channel glossary\n"
        r <- build (defaultOptions tmp)
        map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0602"],
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

pluginTests :: [TestTree]
pluginTests =
  channelTests
    <> [ testCase "a filter runs over the declared files and keeps the output" $ do
           plain <- buildAndRead Dev "build/text/horizontal/chapters/01.txt"
           filtered <- withPluginProject pluginDecl $ \tmp -> do
             r <- build (defaultOptions tmp)
             assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
             BL.fromStrict <$> BS.readFile (tmp </> "build/text/horizontal/chapters/01.txt")
           filtered @?= plain,
         testCase "G0609: a command whose answer is invalid names the command, at the call" $
           withPluginProject pluginDecl $ \tmp -> do
             BS.appendFile (tmp </> "chapters/02.gm") "\n[broken: x]\n"
             r <- build (defaultOptions tmp)
             case [d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G0609"] of
               [d] -> do
                 assertBool (show d) ("identity.broken: " `T.isPrefixOf` diagMessage d)
                 Just (spanFile (diagSpan d)) @?= sourceFileId r "chapters/02.gm"
                 assertBool (show d) (spanStart (diagSpan d) > 0)
               ds -> assertFailure (show ds),
         testCase "G0609: a filter that fails points at the top of the file it was applied to" $
           withPlugins [("loop", "loop-filter.wat")] (pluginDeclOf "loop" "" <> filterDecl "loop" "spin") $ \tmp -> do
             r <- build (defaultOptions tmp)
             case [d | d <- brDiagnostics r, diagCode d == DiagnosticCode "G0609"] of
               [d] -> do
                 assertBool (show d) ("loop.spin: " `T.isPrefixOf` diagMessage d)
                 Just (diagSpan d) @?= topOf r "chapters/01.gm"
               ds -> assertFailure (show ds),
         testCase "G0602: a plugin missing from the lock, or with another URL there" $
           withPluginProject pluginDecl $ \tmp -> do
             locked <- TIO.readFile (tmp </> "plugins.lock")
             BS.writeFile (tmp </> "plugins.lock") ""
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G0602", "plugins.lock にないプラグインです。golem plugin lock を実行してください: identity")])
             setEnv "XDG_CACHE_HOME" (tmp </> "empty-cache")
             r' <- build (defaultOptions tmp) {optCheckOnly = True}
             map diagCode (brDiagnostics r') @?= [DiagnosticCode "G0602"]
             TIO.writeFile (tmp </> "plugins.lock") (T.replace "identity.wasm" "other.wasm" locked)
             r'' <- build (defaultOptions tmp)
             atManifestTop r'' >>= (@?= [(DiagnosticCode "G0602", "plugins.lock の URL が manifest.toml と違います。golem plugin lock を実行してください: identity")]),
         testCase "G0602 only: no G0222 for the commands after a plugin fails to load" $
           withPluginProject pluginDecl $ \tmp -> do
             BS.writeFile (tmp </> "plugins.lock") ""
             BS.appendFile (tmp </> "chapters/02.gm") "\n[broken: x]\n"
             r <- build (defaultOptions tmp)
             map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0602"],
         testCase "G0603: an uncached plugin asks for golem plugin fetch" $
           withPluginProject pluginDecl $ \tmp -> do
             setEnv "XDG_CACHE_HOME" (tmp </> "empty-cache")
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G0603", "キャッシュにないプラグインです。golem plugin fetch を実行してください: identity")]),
         testCase "G0604: a cached plugin that does not match its hash" $
           withPluginProject pluginDecl $ \tmp -> do
             cache <- defaultCacheDir
             files <- listDirectory cache
             forM_ files $ \f -> do
               b <- BS.readFile (cache </> f)
               BS.writeFile (cache </> f) (BS.cons (BS.head b + 1) (BS.tail b))
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G0604", "キャッシュの配布物のハッシュが plugins.lock と一致しません: identity")]),
         testCase "G0605: a plugin that cannot be loaded" $
           withPlugins [("imports", "imports.wat")] (pluginDeclOf "imports" "") $ \tmp -> do
             r <- build (defaultOptions tmp)
             ds <- atManifestTop r
             map fst ds @?= [DiagnosticCode "G0605"]
             assertBool (show ds) (all (T.isPrefixOf "imports: プラグインが import を要求しています" . snd) ds),
         testCase "G0606: one per command, naming the plugins in order" $
           withPlugins [("b", "identity.wat"), ("a", "identity.wat")] (pluginDeclOf "b" "" <> pluginDeclOf "a" "") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G0606", "複数のプラグインが同じコマンドを提供しています: broken（a、b）")]),
         testCase "G0607: a collision with a built-in command, overridable or not" $
           withPlugins [("names", "builtin-names.wat")] (pluginDeclOf "names" "") $ \tmp -> do
             r <- build (defaultOptions tmp)
             ds <- atManifestTop r
             sort ds
               @?= sort
                 [ (DiagnosticCode "G0607", "組み込みのコマンドと衝突しています（overrides で宣言してください）: names.ruby"),
                   (DiagnosticCode "G0607", "上書きできない組み込みのコマンドと衝突しています: names.note")
                 ],
         testCase "G0608: one per name in overrides" $ do
           let g0608 m = [(DiagnosticCode "G0608", m)]
           withPluginProject (pluginDeclWith "overrides = [\"ruby\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= g0608 "プラグインが提供していないコマンドを overrides に書いています: identity.ruby")
           withPluginProject (pluginDeclWith "overrides = [\"xyz\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= g0608 "プラグインが提供していないコマンドを overrides に書いています: identity.xyz")
           withPlugins [("names", "builtin-names.wat")] (pluginDeclOf "names" "overrides = [\"note\", \"ruby\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= g0608 "上書きできる組み込みのコマンドではありません: names.note"),
         -- docs/adr ADR 0031
         testCase "overrides = [\"code\"] loads; overrides = [\"aki\"] is G0608" $ do
           withPlugins [("cd", "override-code.wat")] (pluginDeclOf "cd" "overrides = [\"code\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             brDiagnostics r @?= []
           withPlugins [("ak", "override-aki.wat")] (pluginDeclOf "ak" "overrides = [\"aki\"]\n") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G0608", "上書きできる組み込みのコマンドではありません: ak.aki")]),
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
                 assertBool (show codes) (DiagnosticCode "G0222" `notElem` codes)
                 assertBool (show codes) (not (null codes))
               other -> assertFailure (show (map fst other))
           withPlugins [("identity", "identity.wat")] (pluginDeclOf "identity" "") $ \tmp -> do
             TIO.appendFile (tmp </> "chapters/02.gm") "\n本文の [b\n"
             BS.writeFile (tmp </> "plugins.lock") ""
             e <- evaluateProject Dev tmp >>= either (assertFailure . show . pfDiagnostics) pure
             let codes = map diagCode (evDiagnostics e)
             assertBool (show codes) (DiagnosticCode "G0602" `elem` codes)
             assertBool (show codes) (any (\(DiagnosticCode c) -> "G01" `T.isPrefixOf` c) codes)
             evPluginCommands e @?= [],
         testCase "G0610: a filter of an undeclared plugin, or one the plugin does not provide" $ do
           withPluginProject (pluginDeclOf "identity" "" <> filterDecl "ghost" "x") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G0610", "宣言されていないプラグインです: ghost（フィルタ ghost.x）")])
           withPluginProject (pluginDeclOf "identity" "" <> filterDecl "identity" "nope") $ \tmp -> do
             r <- build (defaultOptions tmp)
             atManifestTop r >>= (@?= [(DiagnosticCode "G0610", "プラグインが提供していないフィルタです: identity.nope")]),
         testCase "the hook keeps overrides by type and other commands by name (docs/adr ADR 0027)" $ do
           -- (all names, the names of the overrides): the commands of the plugins
           -- and the overrides they declare
           let keysOf plugins extra = withPlugins plugins extra $ \tmp -> do
                 cache <- defaultCacheDir
                 lockText <- TIO.readFile (tmp </> "plugins.lock")
                 m <- TIO.readFile (tmp </> "manifest.toml") >>= either (assertFailure . show) pure . parseManifest (FileId 0)
                 hook <- loadPlugins cache (FileId 0) (FileId 1) lockText m >>= either (assertFailure . show) pure
                 let overrides = map (builtinName . Overridable) (Map.keys (phOverrides hook))
                 pure (sort (overrides <> map unPluginCommandName (Map.keys (phCommands hook))), sort overrides)
           keysOf [("ov", "override-ruby.wat")] (pluginDeclOf "ov" "overrides = [\"ruby\"]\n") >>= (@?= (["greet", "ruby"], ["ruby"]))
           keysOf [("identity", "identity.wat")] (pluginDeclOf "identity" "") >>= (@?= (["broken"], [])),
         testCase "G0611: plugins.lock that cannot be read points into plugins.lock" $
           withPluginProject pluginDecl $ \tmp -> do
             BS.writeFile (tmp </> "plugins.lock") "[plugins.identity\nurl = 1\n"
             r <- build (defaultOptions tmp)
             map diagCode (brDiagnostics r) @?= [DiagnosticCode "G0611"]
             assertBool "plugins.lock is a source" (isJust (sourceFileId r "plugins.lock"))
             map (Just . spanFile . diagSpan) (brDiagnostics r) @?= [sourceFileId r "plugins.lock"]
       ]
  where
    pluginDecl = pluginDeclWith ""
    pluginDeclWith extra = pluginDeclOf "identity" extra <> filterDecl "identity" "same"
