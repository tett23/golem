{- | The functions of the project (docs/adr/0149): [functions] of
manifest.toml, the .gmx it names and those they import, and the handler
of the requirement file. Every file is read when the project is loaded,
so that evaluation never touches the file system, and the files are
checked whether or not a chapter calls a function.
-}
module Golem.Driver.Functions
  ( LoadedFunctions (..),
    loadFunctions,
    loadFunctionsAt,
    functionFiles,
    Result (..),
  )
where

import Control.Monad (forM)
import Data.ByteString qualified as BS
import Data.Either (lefts, rights)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Gmx
import Golem.Plugin (maxDataBytes)
import Golem.Project (Project (..), loadProjectWith)
import Golem.Project.Manifest
import Golem.Project.Paths (PathError (..), normalizeRelative, pathErrorMessage, resolveInRoot)
import Golem.Syntax
import System.Directory (getFileSize)
import System.FilePath ((</>))

data LoadedFunctions = LoadedFunctions
  { lfDiagnostics :: ![Diagnostic],
    -- | the .gmx read, where their diagnostics point
    lfSources :: !(Map FileId SourceInfo),
    -- | the checked program and the handlers of its requirements; Nothing after an error
    lfProgram :: !(Maybe (Program, Handlers)),
    -- | a function of the program called with the handlers
    lfProgramCall :: !(Maybe (SrcSpan -> FilePath -> Text -> [Result] -> Either Diagnostic Result))
  }

-- | The .gmx of files and the files of data, which the LSP watches (docs/adr/0149).
functionFiles :: Manifest -> Set FilePath
functionFiles m = case manifestFunctions m of
  Nothing -> Set.empty
  Just fd -> Set.fromList [rel | p <- fnFiles fd <> Map.elems (fnData fd), Right rel <- [normalizeRelative p]]

{- | Loads [functions]: the root of the project, the text of the editor by
path, the FileId of manifest.toml, where the errors of the table point,
and the first FileId of the .gmx, given in the order they are read.
-}
loadFunctions :: FilePath -> Map FilePath Text -> FileId -> FileId -> Manifest -> IO LoadedFunctions
loadFunctions root overlay mfid (FileId base) manifest = case manifestFunctions manifest of
  Nothing -> pure (LoadedFunctions [] Map.empty Nothing Nothing)
  Just fd -> do
    let err code = diagnostic code Error (mkSpan mfid 0 0)
        unknownReqs = [r | r <- fnRequires fd, r `notElem` requirementNames]
        reqDiags =
          [ err "G03101" ("[functions] の requires に知らない要求があります: " <> T.intercalate "、" (nub unknownReqs) <> "（使える要求: " <> T.intercalate "、" requirementNames <> "）")
          | not (null unknownReqs)
          ]
        noFile = [err "G03104" "[functions.data] がありますが、[functions] の requires に file がありません" | not (Map.null (fnData fd)), "file" `notElem` fnRequires fd]
    -- the files of files and of [functions.data]: G03003, G03102
    fileChecks <- forM (fnFiles fd) $ \p ->
      resolveInRoot root p >>= \case
        Left Missing -> pure (Left (err "G03102" ("[functions] の files のファイルがありません: " <> T.pack p)))
        Left e -> pure (Left (err "G03003" (T.pack (pathErrorMessage e) <> ": " <> T.pack p)))
        Right rel -> pure (Right rel)
    dataChecks <- forM (Map.toList (fnData fd)) $ \(name, p) ->
      resolveInRoot root p >>= \case
        Left Missing -> pure (Left (err "G03102" ("[functions.data] のファイルがありません: " <> name <> ": " <> T.pack p)))
        Left e -> pure (Left (err "G03003" (T.pack (pathErrorMessage e) <> ": " <> name <> ": " <> T.pack p)))
        Right rel -> do
          size <- maybe (toInteger <$> getFileSize (root </> rel)) (pure . toInteger . BS.length . TE.encodeUtf8) (Map.lookup rel overlay)
          pure (Right (name, rel, size))
    let found = rights dataChecks
        total = sum [n | (_, _, n) <- found]
        sizeDiags = [err "G03103" ("[functions.data] の大きさの合計が上限（" <> tshow maxDataBytes <> " バイト）を超えています（" <> tshow total <> " バイト）") | total > toInteger maxDataBytes]
        tableDiags = reqDiags <> lefts fileChecks <> lefts dataChecks <> sizeDiags <> noFile
    -- the .gmx, read once each, with ids in the order they are read
    next <- newIORef base
    infos <- newIORef Map.empty
    let source p =
          resolveInRoot root p >>= \case
            Left Missing -> pure (Left MissingFile)
            Left _ -> pure (Left OutsideRoot)
            Right rel -> do
              bytes <- maybe (BS.readFile (root </> rel)) (pure . TE.encodeUtf8) (Map.lookup rel overlay)
              n <- readIORef next
              modifyIORef' next (+ 1)
              modifyIORef' infos (Map.insert (FileId n) (readInfo' rel bytes))
              pure (Right (FileId n, bytes))
    (gmxDiags, program) <- loadProgram source (rights fileChecks)
    sources <- readIORef infos
    let reqs = fnRequires fd
        missingReqs = case program of
          Just p -> [diagnostic "G10505" Error sp ("manifest.toml の [functions] の requires にない要求です: " <> r <> "（requires に \"" <> r <> "\" を足します）") | (r, sp) <- programRequirements p, r `elem` requirementNames, r `notElem` reqs]
          Nothing -> []
    datas <- forM found $ \(name, rel, _) -> (name,) <$> maybe (BS.readFile (root </> rel)) (pure . TE.encodeUtf8) (Map.lookup rel overlay)
    let diags = tableDiags <> gmxDiags <> missingReqs
        handlers = fileHandler (Map.fromList datas)
        ready = if any isError diags then Nothing else (,handlers) <$> program
    pure (LoadedFunctions diags sources ready ((\(p, hs) -> callFunctionWith hs p) <$> ready))
  where
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show
    readInfo' rel bytes = SourceInfo rel (mkLineIndex (TE.decodeUtf8Lenient bytes))

-- | 'loadFunctions' of the project at a root, for tests and tools.
loadFunctionsAt :: FilePath -> IO LoadedFunctions
loadFunctionsAt root =
  loadProjectWith Map.empty root >>= \case
    Left _ -> pure (LoadedFunctions [] Map.empty Nothing Nothing)
    Right p -> loadFunctions root Map.empty (projectManifestFile p) (FileId 1000000) (projectManifest p)
