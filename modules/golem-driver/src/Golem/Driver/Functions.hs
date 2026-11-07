{- | The requirements of the functions of .emet and their handlers
(docs/adr/0161). The files of [functions.requires] are read once, when the
project is loaded, whether or not a chapter calls a function; the handler
of @file@ returns what was read, so that evaluation never touches the
file system. The requirements the signatures of .emet write are checked
against [functions.requires] (E05104).
-}
module Golem.Driver.Functions
  ( RequiredFiles (..),
    loadRequiredFiles,
    requiredFileSet,
    requirementHandlers,
    LoadedFunctions (..),
    loadFunctions,
    requirementDiagnostics,
    formatFunctionFile,
  )
where

import Data.ByteString qualified as BS
import Data.Char (toLower)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver.Plugins (maxDataBytes)
import Golem.Emet
import Golem.Project.Files (Files (..))
import Golem.Project.Manifest (Manifest (..))
import Golem.Project.Paths (PathError (..), normalizeRelative, pathErrorMessage)
import Golem.Syntax

-- | The files of [functions.requires] read, and the errors of reading them.
data RequiredFiles = RequiredFiles
  { rqDiagnostics :: ![Diagnostic],
    -- | the texts by their paths from the root as written, normalised; without a BOM, with LF
    rqTexts :: !(Map Text Text)
  }

{- | The files of [functions.requires], normalised, which the LSP watches
with the files of @table. Paths of the wrong shape are left out; G03003
reports them.
-}
requiredFileSet :: Manifest -> Set FilePath
requiredFileSet m = Set.fromList [rel | p <- fromMaybe [] (manifestRequiredFiles m), Right rel <- [normalizeRelative p]]

-- | The handlers of the requirements over the files read.
requirementHandlers :: RequiredFiles -> Handlers
requirementHandlers = fileHandlers . rqTexts

{- | Reads the files of [functions.requires] (the files of the project, the
texts of the editor by their paths, the FileId of manifest.toml, where
the errors point): G03003 for a path outside the root, G03004 for two
paths that differ only in case, G03102 for a missing file, E05105 for a
file over 'maxDataBytes', E05103 for one that is no UTF-8. A BOM at the
start is skipped and CRLF becomes LF, as for the files of @table.
-}
loadRequiredFiles :: Files -> Map FilePath Text -> FileId -> Manifest -> IO RequiredFiles
loadRequiredFiles files overlay mfid manifest = go [] [] Map.empty (nub (fromMaybe [] (manifestRequiredFiles manifest)))
  where
    err code = diagnostic code Error (mkSpan mfid 0 0)
    go ds _ texts [] = pure (RequiredFiles (reverse ds) texts)
    go ds seen texts (p : rest) = case normalizeRelative p of
      Left e -> go (err "G03003" (T.pack (pathErrorMessage e <> ": " <> p)) : ds) seen texts rest
      Right written
        | Just other <- find (\o -> map toLower o == map toLower written && o /= written) seen ->
            go (err "G03004" (T.pack ("大文字と小文字だけが異なるパスです: " <> written <> " と " <> other)) : ds) seen texts rest
        | otherwise -> do
            let seen' = written : seen
            filesResolve files p >>= \case
              Left Missing -> go (err "G03102" ("[functions.requires] の file のファイルがありません: " <> T.pack p) : ds) seen' texts rest
              Left e -> go (err "G03003" (T.pack (pathErrorMessage e <> ": " <> p)) : ds) seen' texts rest
              Right rel -> do
                size <- maybe (filesSize files rel) (pure . toInteger . BS.length . TE.encodeUtf8) (Map.lookup rel overlay)
                if size > toInteger maxDataBytes
                  then go (err "E05105" ("要求したファイルが上限（" <> tshow maxDataBytes <> " バイト）を超えています: " <> T.pack p <> "（" <> tshow size <> " バイト）") : ds) seen' texts rest
                  else do
                    bytes <- maybe (filesRead files rel) (pure . TE.encodeUtf8) (Map.lookup rel overlay)
                    case TE.decodeUtf8' (fromMaybe bytes (BS.stripPrefix "\xEF\xBB\xBF" bytes)) of
                      Left _ -> go (err "E05103" ("要求したファイルが UTF-8 として読めません: " <> T.pack p) : ds) seen' texts rest
                      Right t -> go ds seen' (Map.insert (T.pack written) (T.replace "\r\n" "\n" t) texts) rest
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show

{- | golem fmt of a .emet (docs/adr/0160, docs/adr/0162): the formatted
text, or the errors that keep it from being read.
-}
formatFunctionFile :: Text -> Either [Diagnostic] Text
formatFunctionFile = formatEmet

-- | The functions of the .emet a program reaches, checked.
data LoadedFunctions = LoadedFunctions
  { lfDiagnostics :: ![Diagnostic],
    -- | the .emet read, where their diagnostics point
    lfSources :: !(Map FileId SourceInfo),
    -- | the checked program; Nothing after an error
    lfProgram :: !(Maybe Program)
  }

{- | Loads the .emet of these root files (paths from the root of the
project) and those they import, and checks the requirements of their
signatures against [functions.requires] (E05104): the files of the
project, the texts of the editor by their paths, the first FileId of the
.emet, given in the order they are read, and the manifest. ADR 0162 calls
it with the .emet that @import of .gm and [[filters]] reach.
-}
loadFunctions :: Files -> Map FilePath Text -> FileId -> Manifest -> [FilePath] -> IO LoadedFunctions
loadFunctions files overlay (FileId base) manifest roots = do
  next <- newIORef base
  infos <- newIORef Map.empty
  let source p =
        filesResolve files p >>= \case
          Left Missing -> pure (Left MissingFile)
          Left _ -> pure (Left OutsideRoot)
          Right rel -> do
            bytes <- maybe (filesRead files rel) (pure . TE.encodeUtf8) (Map.lookup rel overlay)
            n <- readIORef next
            modifyIORef' next (+ 1)
            modifyIORef' infos (Map.insert (FileId n) (SourceInfo rel (mkLineIndex (TE.decodeUtf8Lenient bytes))))
            pure (Right (FileId n, bytes))
  (ds, program) <- loadProgram source roots
  sources <- readIORef infos
  let reqDiags = maybe [] (requirementDiagnostics manifest) program
      diags = ds <> reqDiags
  pure (LoadedFunctions diags sources (if any isError diags then Nothing else program))

{- | E05104 at each requirement of a signature of the program that
[functions.requires] does not have, with the line to add to
manifest.toml; G03004 instead for a path that differs from one of the
manifest only in case.
-}
requirementDiagnostics :: Manifest -> Program -> [Diagnostic]
requirementDiagnostics manifest program =
  [ d
  | (ReqFile p, sp) <- programRequirements program,
    not (Set.member p allowed),
    let d = case [o | o <- Set.toList allowed, T.toLower o == T.toLower p] of
          other : _ -> diagnostic "G03004" Error sp ("大文字と小文字だけが異なるパスです: " <> p <> " と " <> other)
          [] -> diagnostic "E05104" Error sp (showReq (ReqFile p) <> " が manifest.toml の [functions.requires] にありません。" <> fix p)
  ]
  where
    written = manifestRequiredFiles manifest
    allowed = Set.fromList [T.pack rel | p <- fromMaybe [] written, Right rel <- [normalizeRelative p]]
    fix p = case written of
      Nothing -> "[functions.requires] に file = [\"" <> p <> "\"] と書きます"
      Just _ -> "[functions.requires] の file に \"" <> p <> "\" を足します"
