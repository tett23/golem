{- | Plugins of a project (golem-plugin ADR 0001, 0002): read from the
cache as plugins.lock names them, checked for name collisions, and
turned into the evaluator's plugin hook. Builds never use the network.
The codes, messages and spans of the diagnostics: golem-plugin ADR 0003.
-}
module Golem.Driver.Plugins
  ( loadPlugins,
    LoadedPlugins (..),
    FunctionFilter,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAsciiLower, isDigit)
import Data.Containers.ListUtils (nubOrd)
import Data.Either (lefts, partitionEithers, rights)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Doc.Assemble (ChannelDecl (..))
import Golem.Doc.IR (Document (..))
import Golem.Eval.Builtin (BuiltinInline (..), OverridableBuiltin, PluginCommandName, parseBuiltin, pluginCommandName)
import Golem.Eval.File (PluginBlockCommand (..), PluginCommand (..), PluginHook (..), noPlugins)
import Golem.Plugin
import Golem.Plugin.Lock
import Golem.Project.Manifest
import Golem.Project.Paths (PathError (..), pathErrorMessage, resolveInRoot)
import Golem.Syntax
import System.Directory (getFileSize)
import System.FilePath ((</>))

{- | The plugins loaded: the hook, or the errors that stopped the loading;
the warnings of the checks of the data of plugins that loaded
(docs/adr/0120); and the files of data those diagnostics point at.
-}
data LoadedPlugins = LoadedPlugins
  { lpHook :: !(Either [Diagnostic] PluginHook),
    lpWarnings :: ![Diagnostic],
    lpSources :: !(Map.Map FileId SourceInfo)
  }

{- | A diagnostic of loading: one of the host, or one of golem_check_data
(docs/adr/0120), at the start of a line of a file of data, whose FileId
is given when every such file is known.
-}
data Pending
  = Ready !Diagnostic
  | AtData !Text !FilePath !ByteString !Int !DataDiagnostic

{- | A filter of a .emet (docs/adr/0162) by the path of the .emet and its
name: over the document of a .gm by its path, Nothing for one the
functions do not have (golem-driver reports it).
-}
type FunctionFilter = FilePath -> Text -> FilePath -> Document -> Maybe (Either [Diagnostic] (Document, [Diagnostic]))

{- | The filters of [[filters]] over the document of a file, in their order,
those of plugins and of .emet alike (docs/adr/0162). A filter of a
plugin that fails points at the top of the file (golem-plugin ADR 0003).
-}
filtersOver :: (Text -> Maybe Plugin) -> FunctionFilter -> Manifest -> FilePath -> Document -> Either [Diagnostic] (Document, [Diagnostic])
filtersOver lookupPlugin functionFilter manifest path doc0 =
  foldl
    ( \acc f -> case acc of
        Left ds -> Left ds
        Right (doc, ws)
          | path `notElem` fdFiles f -> Right (doc, ws)
          | otherwise -> case fdSource f of
              FilterPlugin pname
                | Just p <- lookupPlugin pname -> case applyFilter p (fdFilter f) doc of
                    Left pe -> Left [diagnostic (pluginErrorCode pe) Error (mkSpan (docFile doc0) 0 0) (qualified pname (fdFilter f) pe)]
                    Right (doc', ws') -> Right (doc', ws <> map (ofPlugin pname) ws')
                | otherwise -> Right (doc, ws)
              FilterFunction emet -> case functionFilter emet (fdFilter f) path doc of
                Just (Left ds) -> Left ds
                Just (Right (doc', ws')) -> Right (doc', ws <> ws')
                Nothing -> Right (doc, ws)
    )
    (Right (doc0, []))
    (manifestFilters manifest)

{- | Given the root of the project, the texts of the editor (the LSP), the
cache, the FileId of manifest.toml, where most diagnostics point, the
FileId and text of plugins.lock (empty when there is none), where G06011
points, and the first FileId for the files of data that the checks of
the data point at (docs/adr/0120), one for each file in the order of the
paths, the context of the book a plugin may ask for (docs/adr/0121), and
the filters of the .emet (docs/adr/0162), which apply in one order with
those of the plugins.
-}
loadPlugins :: FilePath -> Map.Map FilePath Text -> FilePath -> FileId -> FileId -> Text -> FileId -> HostContext -> FunctionFilter -> Manifest -> IO LoadedPlugins
loadPlugins root overlay cacheDir mfid lfid lockText (FileId dataBase) context functionFilter manifest
  | Map.null (manifestPlugins manifest) && null [() | FilterDecl (FilterPlugin _) _ _ <- manifestFilters manifest] =
      pure (LoadedPlugins (Right noPlugins {phApplyFilters = filtersOver (const Nothing) functionFilter manifest}) [] Map.empty)
  | otherwise =
      case parseLock lfid lockText of
        Left ds -> pure (LoadedPlugins (Left ds) [] Map.empty)
        Right lock -> do
          loaded <- mapM (loadOne lock) (Map.toList (manifestPlugins manifest))
          let pending = concat (lefts loaded) <> concatMap snd (rights loaded)
              files = Map.fromList [(rel, bytes) | AtData _ rel bytes _ _ <- pending]
              fids = Map.fromList (zip (Map.keys files) (map FileId [dataBase ..]))
              sources = Map.fromList [(fids Map.! rel, SourceInfo rel (mkLineIndex (TE.decodeUtf8Lenient bytes))) | (rel, bytes) <- Map.toList files]
              ready = \case
                Ready d -> d
                AtData pname rel _ off dd -> ofPlugin pname (diagnostic (ddCode dd) (ddSeverity dd) (mkSpan (fids Map.! rel) off off) (ddMessage dd))
              warnings = map ready (concatMap snd (rights loaded))
          pure $ case map (map ready) (lefts loaded) of
            [] -> LoadedPlugins (hook (map fst (rights loaded))) warnings sources
            dss -> LoadedPlugins (Left (concat dss)) warnings sources
  where
    err code = diagnostic code Error (mkSpan mfid 0 0)
    loadOne lock (name, decl) = case pdSource decl of
      -- a plugin of the project: not in plugins.lock nor in the cache (docs/adr/0109)
      PluginPath path -> do
        let what = name <> ": " <> T.pack path
        res <- resolveInRoot root path
        case res of
          Left Missing -> pure (Left [Ready (err "G06104" ("プラグインのファイルがありません: " <> what))])
          Left e -> pure (Left [Ready (err "G03003" (T.pack (pathErrorMessage e) <> ": " <> what))])
          Right rel -> BS.readFile (root </> rel) >>= loaded name decl
      PluginUrl url -> case Map.lookup name lock of
        Just e | leUrl e == url -> do
          cached <- readCached cacheDir e
          case cached of
            Left NotCached -> pure (Left [Ready (err "G06003" ("キャッシュにないプラグインです。golem plugin fetch を実行してください: " <> name))])
            Left HashMismatch -> pure (Left [Ready (err "G06004" ("キャッシュの配布物のハッシュが plugins.lock と一致しません: " <> name))])
            Right bytes -> loaded name decl bytes
        Just _ -> pure (Left [Ready (err "G06002" ("plugins.lock の URL が manifest.toml と違います。golem plugin lock を実行してください: " <> name))])
        Nothing -> pure (Left [Ready (err "G06002" ("plugins.lock にないプラグインです。golem plugin lock を実行してください: " <> name))])
    loaded name decl bytes =
      loadPlugin bytes >>= \case
        -- G06105: context the host does not have (docs/adr/0121)
        Left pe@(UnknownContext _) -> pure (Left [Ready (err "G06105" (name <> ": " <> describePluginError pe))])
        Left pe -> pure (Left [Ready (err "G06005" (name <> ": " <> describePluginError pe))])
        Right p ->
          loadData root overlay err name decl p >>= \case
            Left ds -> pure (Left (map Ready ds))
            Right files -> do
              let p' = withPluginData (Map.map snd files) (withPluginContext context p)
              checked <- checkData p'
              pure $ case checked >>= \dds -> (dds,) <$> mapM (located (mkSpan mfid 0 0) name files) dds of
                Left pe -> Left [Ready (err (pluginErrorCode pe) (qualified name "golem_check_data" pe))]
                -- an error of the data stops the plugin, as an error of loading (docs/adr/0120)
                Right (dds, ps)
                  | any ((== Error) . ddSeverity) dds -> Left ps
                  | otherwise -> Right ((name, decl, p'), ps)
    hook plugins =
      let provided = [(c, name) | (name, _, p) <- plugins, c <- pluginCommands p]
          overrides = [(o, name, p) | (name, decl, p) <- plugins, o <- pdOverrides decl]
          providers = Map.fromListWith (<>) [(c, [n]) | (c, n) <- provided]
          collisions = [(c, sort ns) | (c, ns) <- Map.toList providers, length ns > 1]
          -- the block commands (docs/adr/0122), a namespace of their own
          blockProviders = Map.fromListWith (<>) [(c, [n]) | (n, _, p) <- plugins, c <- pluginBlocks p]
          blockCollisions = [(c, sort ns) | (c, ns) <- Map.toList blockProviders, length ns > 1]
          -- each name in overrides as the built-in command it overrides, or G06008
          checkedOverrides = [((n, o), overrideTarget o n p) | (o, n, p) <- overrides]
          overrideTarget o n p
            | o `notElem` pluginCommands p = Left ("プラグインが提供していないコマンドを overrides に書いています: " <> n <> "." <> o)
            | Just (Overridable b) <- parseBuiltin o = Right b
            | otherwise = Left ("上書きできる組み込みのコマンドではありません: " <> n <> "." <> o)
          -- each command a plugin provides as a key of the hook (docs/adr ADR 0027):
          -- a name of its own, a declared override, or G06007 for an undeclared
          -- built-in name; a declared name that is not overridable is G06008 above
          (undeclared, keyed) = partitionEithers (mapMaybe (commandKey checkedOverrides) plugins')
          plugins' = [(c, name, p) | (name, _, p) <- plugins, c <- pluginCommands p]
          filterError f = case fdSource f of
            FilterFunction _ -> Nothing
            FilterPlugin pname -> case lookupPlugin pname of
              Nothing -> Just ("宣言されていないプラグインです: " <> pname <> "（フィルタ " <> pname <> "." <> fdFilter f <> "）")
              Just (_, _, p)
                | fdFilter f `notElem` pluginFilters p -> Just ("プラグインが提供していないフィルタです: " <> pname <> "." <> fdFilter f)
                | otherwise -> Nothing
          lookupPlugin n = case [x | x@(n', _, _) <- plugins, n' == n] of
            (x : _) -> Just x
            [] -> Nothing
          collisionMessage (c, n)
            | Just (Overridable _) <- parseBuiltin c = "組み込みのコマンドと衝突しています（overrides で宣言してください）: " <> n <> "." <> c
            | otherwise = "上書きできない組み込みのコマンドと衝突しています: " <> n <> "." <> c
          -- the channels of the plugins (golem-doc ADR 0007): G06012 for a name declared twice, reserved or malformed
          declared = [(channelName d, (name, d)) | (name, _, p) <- plugins, d <- pluginChannels p]
          channelProviders = Map.fromListWith (flip (<>)) [(c, [n]) | (c, (n, _)) <- declared]
          channelCollisions = [(c, ns) | (c, ns) <- Map.toList channelProviders, length ns > 1]
          badChannels = [(n, c) | (c, (n, _)) <- declared, not (validChannelName c)]
          diags =
            [err "G06006" ("複数のプラグインが同じコマンドを提供しています: " <> c <> "（" <> T.intercalate "、" ns <> "）") | (c, ns) <- collisions]
              <> [err "G06006" ("複数のプラグインが同じブロックコマンドを提供しています: @" <> c <> "（" <> T.intercalate "、" ns <> "）") | (c, ns) <- blockCollisions]
              <> [err "G06007" (collisionMessage u) | u <- undeclared]
              <> [err "G06008" m | (_, Left m) <- checkedOverrides]
              <> [err "G06010" m | Just m <- map filterError (manifestFilters manifest)]
              <> [err "G06012" ("複数のプラグインが同じチャネルを宣言しています: " <> c <> "（" <> T.intercalate "、" ns <> "）") | (c, ns) <- channelCollisions]
              <> [err "G06012" (n <> ": このチャネルの名前は使えません: " <> c) | (n, c) <- badChannels]
          call pname p name = PluginCommand $ \vals slots sp ->
            either (\pe -> Left [diagnostic (pluginErrorCode pe) Error sp (qualified pname name pe)]) (Right . fmap (map (ofPlugin pname))) (callCommand p name vals slots sp)
          callBlock pname p name = PluginBlockCommand $ \vals body sp ->
            either (\pe -> Left [diagnostic (pluginErrorCode pe) Error sp (qualified pname name pe)]) (\(bs, imgs, ds) -> Right (bs, imgs, map (ofPlugin pname) ds)) (callBlockCommand p name vals body sp)
          applyFilters = filtersOver (fmap (\(_, _, p) -> p) . lookupPlugin) functionFilter manifest
       in if null diags
            then
              Right
                PluginHook
                  { phOverrides = Map.fromList [(o, call pname p c) | (Left o, (c, pname, p)) <- keyed],
                    phCommands = Map.fromList [(k, call pname p c) | (Right k, (c, pname, p)) <- keyed],
                    phBlocks = Map.fromList [(c, callBlock pname p c) | (pname, _, p) <- plugins, c <- pluginBlocks p],
                    phChannels = Map.fromList [(c, d) | (c, (_, d)) <- declared],
                    phApplyFilters = applyFilters,
                    phContextNames = sort (nubOrd [c | (_, _, p) <- plugins, c <- pluginContextNames p])
                  }
            else Left diags

{- | A diagnostic of a plugin, its code after the name the manifest gives
the plugin: @<plugin>/<code>@, which is neither a code of Golem nor one of
another plugin (docs/adr/0108).
-}
ofPlugin :: Text -> Diagnostic -> Diagnostic
ofPlugin pname d = let DiagnosticCode c = diagCode d in d {diagCode = DiagnosticCode (pname <> "/" <> c)}

{- | A diagnostic of golem_check_data at the start of its line of the file
of its data, or at the start of the file for no line (docs/adr/0120); one
with no name, of all the data, at the top of manifest.toml, as G06101 to
G06103 (docs/adr/0136). A name the plugin was not given, or a line the
file does not have, is bad output; golem-plugin rejects no name with a
line.
-}
located :: SrcSpan -> Text -> Map.Map Text (FilePath, ByteString) -> DataDiagnostic -> Either PluginError Pending
located manifestTop pname files dd = case ddName dd of
  Nothing -> Right (Ready (ofPlugin pname (diagnostic (ddCode dd) (ddSeverity dd) manifestTop (ddMessage dd))))
  Just name -> case Map.lookup name files of
    Nothing -> Left (BadOutput ("渡していないデータの名前です: " <> name))
    Just (rel, bytes) -> case ddLine dd of
      Nothing -> Right (AtData pname rel bytes 0 dd)
      Just n -> case drop (fromIntegral n - 1) (lineStarts bytes) of
        (off : _) -> Right (AtData pname rel bytes off dd)
        [] -> Left (BadOutput ("データの行がありません: " <> name <> ": " <> T.pack (show n)))

{- | The byte offsets of the lines of a file: 0, and the one after each
LF but a last one. An empty file has the line 1.
-}
lineStarts :: ByteString -> [Int]
lineStarts b = 0 : [i + 1 | i <- BS.elemIndices 0x0A b, i + 1 < BS.length b]

{- | The data the manifest passes to a loaded plugin (docs/adr/0105): each
name must be one the plugin takes (G06102), each path a file in the
project (G03003, G06101), and all of them together at most
'maxDataBytes' (G06103). The text of the editor comes before the file,
as for @table. Every error of the plugin is reported; the size is
checked when there is none.
-}
loadData :: FilePath -> Map.Map FilePath Text -> (Text -> Text -> Diagnostic) -> Text -> PluginDecl -> Plugin -> IO (Either [Diagnostic] (Map.Map Text (FilePath, ByteString)))
loadData root overlay err name decl p = do
  let -- \* takes any well-formed name (docs/adr/0119)
      takes = [if n == "*" then "英小文字で始まる任意の名前" else n | n <- pluginDataNames p]
      unknown =
        [ err "G06102" ("プラグインが受け取らないデータの名前です: " <> name <> "." <> k <> "（受け取る名前: " <> (if null takes then "なし" else T.intercalate "、" takes) <> "）")
        | k <- Map.keys (pdData decl),
          not (takesData p k)
        ]
  found <- mapM locate (Map.toList (pdData decl))
  case unknown <> lefts found of
    [] -> do
      let sized = rights found
          total = sum [n | (_, _, n) <- sized]
      if total > fromIntegral maxDataBytes
        then pure (Left [err "G06103" ("プラグインのデータが上限（" <> tshow maxDataBytes <> " バイト）を超えています: " <> name <> "（" <> tshow total <> " バイト）")])
        else Right . Map.fromList <$> mapM (\(k, (rel, src), _) -> (\b -> (k, (rel, b))) <$> either pure BS.readFile src) sized
    ds -> pure (Left ds)
  where
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show
    -- the name, the path and the bytes of the editor or the file to read, and the size
    locate (k, path) = do
      let what = name <> "." <> k <> ": " <> T.pack path
      res <- resolveInRoot root path
      case res of
        Left Missing -> pure (Left (err "G06101" ("プラグインのデータのファイルがありません: " <> what)))
        Left e -> pure (Left (err "G03003" (T.pack (pathErrorMessage e) <> ": " <> what)))
        Right rel -> case Map.lookup rel overlay of
          Just t -> let b = TE.encodeUtf8 t in pure (Right (k, (rel, Left b), toInteger (BS.length b)))
          Nothing -> (\n -> Right (k, (rel, Right (root </> rel)), n)) <$> getFileSize (root </> rel)

{- | The key of a command a plugin provides: Right with the key, Left with
(command, plugin) for an undeclared built-in name (G06007), or Nothing for a
declared name that is not an overridable built-in command, which G06008
reports.
-}
commandKey ::
  [((Text, Text), Either Text OverridableBuiltin)] ->
  (Text, Text, p) ->
  Maybe (Either (Text, Text) (Either OverridableBuiltin PluginCommandName, (Text, Text, p)))
commandKey checked x@(c, n, _) = case pluginCommandName c of
  Just k -> Just (Right (Right k, x))
  Nothing -> case lookup (n, c) checked of
    Just (Right o) -> Just (Right (Left o, x))
    Just (Left _) -> Nothing
    Nothing -> Just (Left (c, n))

{- | The name of a channel a plugin may declare (golem-doc ADR 0007): a
lowercase ASCII letter, then lowercase letters, digits and -, and not one
of the built-in channels.
-}
validChannelName :: Text -> Bool
validChannelName c = case T.uncons c of
  Just (h, rest) -> isAsciiLower h && T.all (\x -> isAsciiLower x || isDigit x || x == '-') rest && c `notElem` reservedChannels
  Nothing -> False
  where
    reservedChannels = ["toc", "index", "bibliography", "note", "notes", "sidenote", "cite"]

{- | The code of a call that failed: G06100 for a float without a finite
value in a deferred expression (docs/adr ADR 0101), G06009 otherwise.
-}
pluginErrorCode :: PluginError -> Text
pluginErrorCode = \case
  NonFiniteFloat _ -> "G06100"
  _ -> "G06009"

-- | @plugin.name: reason@, the message of G06009 and G06100.
qualified :: Text -> Text -> PluginError -> Text
qualified plugin name pe = plugin <> "." <> name <> ": " <> describePluginError pe
