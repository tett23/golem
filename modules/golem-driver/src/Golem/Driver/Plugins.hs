{- | Plugins of a project (golem-plugin ADR 0001, 0002): read from the
cache as plugins.lock names them, checked for name collisions, and
turned into the evaluator's plugin hook. Builds never use the network.
The codes, messages and spans of the diagnostics: golem-plugin ADR 0003.
-}
module Golem.Driver.Plugins
  ( loadPlugins,
  )
where

import Data.Either (rights)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR (Document (..))
import Golem.Eval.File (PluginHook (..), builtinInlineCommands, noPlugins, overridableCommands)
import Golem.Plugin
import Golem.Plugin.Lock
import Golem.Project.Manifest
import Golem.Syntax

{- | Given the cache, the FileId of manifest.toml, where most diagnostics
point, and the FileId and text of plugins.lock (empty when there is
none), where G0611 points.
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
        pure $ case cached of
          Left NotCached -> Left [err "G0603" ("キャッシュにないプラグインです。golem plugin fetch を実行してください: " <> name)]
          Left HashMismatch -> Left [err "G0604" ("キャッシュの配布物のハッシュが plugins.lock と一致しません: " <> name)]
          Right bytes -> case loadPlugin bytes of
            Left pe -> Left [err "G0605" (name <> ": " <> describePluginError pe)]
            Right p -> Right (name, decl, p)
      Just _ -> pure (Left [err "G0602" ("plugins.lock の URL が manifest.toml と違います。golem plugin lock を実行してください: " <> name)])
      Nothing -> pure (Left [err "G0602" ("plugins.lock にないプラグインです。golem plugin lock を実行してください: " <> name)])
    hook plugins =
      let provided = [(c, name) | (name, _, p) <- plugins, c <- pluginCommands p]
          overrides = [(o, name, p) | (name, decl, p) <- plugins, o <- pdOverrides decl]
          providers = Map.fromListWith (<>) [(c, [n]) | (c, n) <- provided]
          collisions = [(c, sort ns) | (c, ns) <- Map.toList providers, length ns > 1]
          undeclared = [(c, n) | (c, n) <- provided, c `elem` builtinInlineCommands, c `notElem` [o | (o, n', _) <- overrides, n' == n]]
          badOverride (o, n, p)
            | o `notElem` pluginCommands p = Just ("プラグインが提供していないコマンドを overrides に書いています: " <> n <> "." <> o)
            | o `notElem` overridableCommands = Just ("上書きできる組み込みのコマンドではありません: " <> n <> "." <> o)
            | otherwise = Nothing
          filterError f = case lookupPlugin (fdPlugin f) of
            Nothing -> Just ("宣言されていないプラグインです: " <> fdPlugin f <> "（フィルタ " <> fdPlugin f <> "." <> fdFilter f <> "）")
            Just (_, _, p)
              | fdFilter f `notElem` pluginFilters p -> Just ("プラグインが提供していないフィルタです: " <> fdPlugin f <> "." <> fdFilter f)
              | otherwise -> Nothing
          lookupPlugin n = case [x | x@(n', _, _) <- plugins, n' == n] of
            (x : _) -> Just x
            [] -> Nothing
          collisionMessage (c, n)
            | c `elem` overridableCommands = "組み込みのコマンドと衝突しています（overrides で宣言してください）: " <> n <> "." <> c
            | otherwise = "上書きできない組み込みのコマンドと衝突しています: " <> n <> "." <> c
          diags =
            [err "G0606" ("複数のプラグインが同じコマンドを提供しています: " <> c <> "（" <> T.intercalate "、" ns <> "）") | (c, ns) <- collisions]
              <> [err "G0607" (collisionMessage u) | u <- undeclared]
              <> [err "G0608" m | Just m <- map badOverride overrides]
              <> [err "G0610" m | Just m <- map filterError (manifestFilters manifest)]
          commandOwner = Map.fromList [(c, (name, p)) | (name, _, p) <- plugins, c <- pluginCommands p, (c, name) `notElem` undeclared]
          call name vals slots sp = case Map.lookup name commandOwner of
            Nothing -> Left [diagnostic "G0222" Error sp ("未知のコマンドです: " <> name)]
            Just (pname, p) -> either (\pe -> Left [diagnostic "G0609" Error sp (qualified pname name pe)]) Right (callCommand p name vals slots sp)
          -- a filter that fails points at the top of the file (golem-plugin ADR 0003)
          applyFilters path doc0 =
            foldl
              ( \acc f -> case acc of
                  Left ds -> Left ds
                  Right (doc, ws)
                    | path `elem` fdFiles f,
                      Just (_, _, p) <- lookupPlugin (fdPlugin f) ->
                        case applyFilter p (fdFilter f) doc of
                          Left pe -> Left [diagnostic "G0609" Error (mkSpan (docFile doc0) 0 0) (qualified (fdPlugin f) (fdFilter f) pe)]
                          Right (doc', ws') -> Right (doc', ws <> ws')
                    | otherwise -> Right (doc, ws)
              )
              (Right (doc0, []))
              (manifestFilters manifest)
       in if null diags
            then
              Right
                PluginHook
                  { phCommands = Map.keysSet commandOwner,
                    phOverrides = Set.fromList [o | (o, _, _) <- overrides],
                    phCallCommand = call,
                    phApplyFilters = applyFilters
                  }
            else Left diags

-- | @plugin.name: reason@, the message of G0609.
qualified :: Text -> Text -> PluginError -> Text
qualified plugin name pe = plugin <> "." <> name <> ": " <> describePluginError pe
