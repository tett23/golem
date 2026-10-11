{- | Plugins of a project (golem-plugin ADR 0001, 0002): read from the
cache as plugins.lock names them, checked for name collisions, and
turned into the evaluator's plugin hook. Builds never use the network.
-}
module Golem.Driver.Plugins
  ( loadPlugins,
  )
where

import Data.ByteString qualified as BS
import Data.Either (rights)
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text.Encoding qualified as TE
import Golem.Eval.File (PluginHook (..), builtinInlineCommands, noPlugins, overridableCommands)
import Golem.Plugin
import Golem.Plugin.Lock
import Golem.Project.Manifest
import Golem.Syntax
import System.Directory (doesFileExist)
import System.FilePath ((</>))

loadPlugins :: FilePath -> FilePath -> FileId -> Manifest -> IO (Either [Diagnostic] PluginHook)
loadPlugins root cacheDir mfid manifest
  | Map.null (manifestPlugins manifest) && null (manifestFilters manifest) = pure (Right noPlugins)
  | otherwise = do
      let lockPath = root </> "plugins.lock"
      exists <- doesFileExist lockPath
      lockText <- if exists then TE.decodeUtf8Lenient <$> BS.readFile lockPath else pure ""
      case parseLock mfid lockText of
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
      _ -> pure (Left [err "G0602" ("plugins.lock にないプラグインです。golem plugin lock を実行してください: " <> name)])
    hook plugins =
      let provided = [(c, name) | (name, _, p) <- plugins, c <- pluginCommands p]
          overrides = [(o, name, p) | (name, decl, p) <- plugins, o <- pdOverrides decl]
          collisions = [c | c <- nub (map fst provided), length [() | (c', _) <- provided, c' == c] > 1]
          undeclared = [(c, n) | (c, n) <- provided, c `elem` builtinInlineCommands, c `notElem` [o | (o, n', _) <- overrides, n' == n]]
          missing = [(o, n) | (o, n, p) <- overrides, o `notElem` pluginCommands p]
          notOverridable = [(o, n) | (o, n, _) <- overrides, o `notElem` overridableCommands]
          filterErrors =
            [ fdPlugin f <> "." <> fdFilter f
            | f <- manifestFilters manifest,
              maybe True (\(_, _, p) -> fdFilter f `notElem` pluginFilters p) (lookupPlugin (fdPlugin f))
            ]
          lookupPlugin n = case [x | x@(n', _, _) <- plugins, n' == n] of
            (x : _) -> Just x
            [] -> Nothing
          diags =
            [err "G0606" ("複数のプラグインが同じコマンドを提供しています: " <> c) | c <- collisions]
              <> [err "G0607" ("組み込みのコマンドと衝突しています（overrides で宣言してください）: " <> n <> "." <> c) | (c, n) <- undeclared]
              <> [err "G0608" ("プラグインが提供していないコマンドを overrides に書いています: " <> n <> "." <> o) | (o, n) <- missing]
              <> [err "G0608" ("上書きできないコマンドです: " <> n <> "." <> o) | (o, n) <- notOverridable]
              <> [err "G0610" ("宣言されていないプラグインかフィルタです: " <> f) | f <- filterErrors]
          commandOwner = Map.fromList [(c, p) | (name, _, p) <- plugins, c <- pluginCommands p, (c, name) `notElem` undeclared]
          call name vals slots sp = case Map.lookup name commandOwner of
            Nothing -> Left [diagnostic "G0222" Error sp ("未知のコマンドです: " <> name)]
            Just p -> either (\pe -> Left [diagnostic "G0609" Error sp (describePluginError pe)]) Right (callCommand p name vals slots sp)
          applyFilters path doc0 =
            foldl
              ( \acc f -> case acc of
                  Left ds -> Left ds
                  Right (doc, ws)
                    | path `elem` fdFiles f,
                      Just (_, _, p) <- lookupPlugin (fdPlugin f) ->
                        case applyFilter p (fdFilter f) doc of
                          Left pe -> Left [err "G0609" (fdPlugin f <> "." <> fdFilter f <> ": " <> describePluginError pe)]
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
