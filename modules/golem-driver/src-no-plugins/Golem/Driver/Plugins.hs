{- | The plugins of a project in a Golem built without them (the flag
plugins of golem-driver off, docs/adr/0199): the wasm build. The names
and types are those of src-plugins/Golem/Driver/Plugins.hs; what that
module takes from golem-plugin is copied here, so that this build does
not depend on golem-plugin. A project without [plugins] and without
filters of plugins in [[filters]] loads as with plugins: no plugin, and
the filters of the .emet (docs/adr/0162). Any other gets G06106 at the
top of manifest.toml.
-}
module Golem.Driver.Plugins
  ( loadPlugins,
    LoadedPlugins (..),
    FunctionFilter,
    HostContext (..),
    defaultCacheDir,
    maxDataBytes,
  )
where

import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Doc.IR (Document (..))
import Golem.Eval.File (PluginHook (..), noPlugins)
import Golem.Project.Manifest
import Golem.Syntax

-- | As in src-plugins/Golem/Driver/Plugins.hs.
data LoadedPlugins = LoadedPlugins
  { lpHook :: !(Either [Diagnostic] PluginHook),
    lpWarnings :: ![Diagnostic],
    lpSources :: !(Map.Map FileId SourceInfo)
  }

-- | As in src-plugins/Golem/Driver/Plugins.hs.
type FunctionFilter = FilePath -> Text -> FilePath -> Document -> Maybe (Either [Diagnostic] (Document, [Diagnostic]))

-- | The type of golem-plugin, of the same form (docs/adr/0121).
data HostContext = HostContext
  { hcWritingMode :: !Text,
    hcVerticalNumbers :: !Text
  }
  deriving stock (Eq, Show)

-- | No cache: no plugin is read.
defaultCacheDir :: IO FilePath
defaultCacheDir = pure ""

-- | The value of golem-plugin (docs/adr/0105): the limit of [functions.requires] (docs/adr/0161).
maxDataBytes :: Int64
maxDataBytes = 64 * 1024 * 1024

-- | The filters of [[filters]] of the .emet over the document of a file, in their order (docs/adr/0162).
filtersOver :: FunctionFilter -> Manifest -> FilePath -> Document -> Either [Diagnostic] (Document, [Diagnostic])
filtersOver functionFilter manifest path doc0 =
  foldl
    ( \acc f -> case acc of
        Left ds -> Left ds
        Right (doc, ws)
          | path `notElem` fdFiles f -> Right (doc, ws)
          | otherwise -> case fdSource f of
              FilterPlugin _ -> Right (doc, ws)
              FilterFunction emet -> case functionFilter emet (fdFilter f) path doc of
                Just (Left ds) -> Left ds
                Just (Right (doc', ws')) -> Right (doc', ws <> ws')
                Nothing -> Right (doc, ws)
    )
    (Right (doc0, []))
    (manifestFilters manifest)

{- | The arguments of src-plugins/Golem/Driver/Plugins.hs; only the FileId
of manifest.toml, the filters of the .emet and the manifest are used.
-}
loadPlugins :: FilePath -> Map.Map FilePath Text -> FilePath -> FileId -> FileId -> Text -> FileId -> HostContext -> FunctionFilter -> Manifest -> IO LoadedPlugins
loadPlugins _ _ _ mfid _ _ _ _ functionFilter manifest
  | Map.null (manifestPlugins manifest) && null [() | FilterDecl (FilterPlugin _) _ _ _ _ <- manifestFilters manifest] =
      pure (LoadedPlugins (Right noPlugins {phApplyFilters = filtersOver functionFilter manifest}) [] Map.empty)
  | otherwise =
      pure (LoadedPlugins (Left [diagnostic "G06106" Error (mkSpan mfid 0 0) "このビルドの Golem にはプラグインの機能がありません"]) [] Map.empty)
