{- | Plugins of a project (golem-plugin ADR 0001, 0002): read from the
cache as plugins.lock names them, checked for name collisions, and
turned into the evaluator's plugin hook. Builds never use the network.
The codes, messages and spans of the diagnostics: golem-plugin ADR 0003.
-}
module Golem.Driver.Plugins
  ( loadPlugins,
  )
where

import Data.Char (isAsciiLower, isDigit)
import Data.Either (partitionEithers, rights)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble (ChannelDecl (..))
import Golem.Doc.IR (Document (..))
import Golem.Eval.Builtin (BuiltinInline (..), OverridableBuiltin, PluginCommandName, parseBuiltin, pluginCommandName)
import Golem.Eval.File (PluginCommand (..), PluginHook (..), noPlugins)
import Golem.Plugin
import Golem.Plugin.Lock
import Golem.Project.Manifest
import Golem.Syntax

{- | Given the cache, the FileId of manifest.toml, where most diagnostics
point, and the FileId and text of plugins.lock (empty when there is
none), where G06011 points.
-}
loadPlugins :: FilePath -> FileId -> FileId -> Text -> Manifest -> IO (Either [Diagnostic] PluginHook)
loadPlugins cacheDir mfid lfid lockText manifest
  | Map.null (manifestPlugins manifest) && null (manifestFilters manifest) = pure (Right noPlugins)
  | otherwise =
      case parseLock lfid lockText of
        Left ds -> pure (Left ds)
        Right lock -> do
          loaded <- mapM (loadOne lock) (Map.toList (manifestPlugins manifest))
          pure $ case [d | Left ds <- loaded, d <- ds] of
            [] -> hook (rights loaded)
            ds -> Left ds
  where
    err code = diagnostic code Error (mkSpan mfid 0 0)
    loadOne lock (name, decl) = case Map.lookup name lock of
      Just e | leUrl e == pdUrl decl -> do
        cached <- readCached cacheDir e
        case cached of
          Left NotCached -> pure (Left [err "G06003" ("キャッシュにないプラグインです。golem plugin fetch を実行してください: " <> name)])
          Left HashMismatch -> pure (Left [err "G06004" ("キャッシュの配布物のハッシュが plugins.lock と一致しません: " <> name)])
          Right bytes ->
            loadPlugin bytes >>= \case
              Left pe -> pure (Left [err "G06005" (name <> ": " <> describePluginError pe)])
              Right p -> pure (Right (name, decl, p))
      Just _ -> pure (Left [err "G06002" ("plugins.lock の URL が manifest.toml と違います。golem plugin lock を実行してください: " <> name)])
      Nothing -> pure (Left [err "G06002" ("plugins.lock にないプラグインです。golem plugin lock を実行してください: " <> name)])
    hook plugins =
      let provided = [(c, name) | (name, _, p) <- plugins, c <- pluginCommands p]
          overrides = [(o, name, p) | (name, decl, p) <- plugins, o <- pdOverrides decl]
          providers = Map.fromListWith (<>) [(c, [n]) | (c, n) <- provided]
          collisions = [(c, sort ns) | (c, ns) <- Map.toList providers, length ns > 1]
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
          filterError f = case lookupPlugin (fdPlugin f) of
            Nothing -> Just ("宣言されていないプラグインです: " <> fdPlugin f <> "（フィルタ " <> fdPlugin f <> "." <> fdFilter f <> "）")
            Just (_, _, p)
              | fdFilter f `notElem` pluginFilters p -> Just ("プラグインが提供していないフィルタです: " <> fdPlugin f <> "." <> fdFilter f)
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
              <> [err "G06007" (collisionMessage u) | u <- undeclared]
              <> [err "G06008" m | (_, Left m) <- checkedOverrides]
              <> [err "G06010" m | Just m <- map filterError (manifestFilters manifest)]
              <> [err "G06012" ("複数のプラグインが同じチャネルを宣言しています: " <> c <> "（" <> T.intercalate "、" ns <> "）") | (c, ns) <- channelCollisions]
              <> [err "G06012" (n <> ": このチャネルの名前は使えません: " <> c) | (n, c) <- badChannels]
          call pname p name = PluginCommand $ \vals slots sp ->
            either (\pe -> Left [diagnostic "G06009" Error sp (qualified pname name pe)]) Right (callCommand p name vals slots sp)
          -- a filter that fails points at the top of the file (golem-plugin ADR 0003)
          applyFilters path doc0 =
            foldl
              ( \acc f -> case acc of
                  Left ds -> Left ds
                  Right (doc, ws)
                    | path `elem` fdFiles f,
                      Just (_, _, p) <- lookupPlugin (fdPlugin f) ->
                        case applyFilter p (fdFilter f) doc of
                          Left pe -> Left [diagnostic "G06009" Error (mkSpan (docFile doc0) 0 0) (qualified (fdPlugin f) (fdFilter f) pe)]
                          Right (doc', ws') -> Right (doc', ws <> ws')
                    | otherwise -> Right (doc, ws)
              )
              (Right (doc0, []))
              (manifestFilters manifest)
       in if null diags
            then
              Right
                PluginHook
                  { phOverrides = Map.fromList [(o, call pname p c) | (Left o, (c, pname, p)) <- keyed],
                    phCommands = Map.fromList [(k, call pname p c) | (Right k, (c, pname, p)) <- keyed],
                    phChannels = Map.fromList [(c, d) | (c, (_, d)) <- declared],
                    phApplyFilters = applyFilters
                  }
            else Left diags

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

-- | @plugin.name: reason@, the message of G06009.
qualified :: Text -> Text -> PluginError -> Text
qualified plugin name pe = plugin <> "." <> name <> ": " <> describePluginError pe
