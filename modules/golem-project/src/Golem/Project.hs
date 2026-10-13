{- | Loading a project: manifest, source files reachable from it, and the
import graph (golem-project ADR 0001).
-}
module Golem.Project
  ( Project (..),
    SourceFile (..),
    ProjectFailure (..),
    loadProject,
    loadProjectWith,
    module Golem.Project.Manifest,
    module Golem.Project.Imports,
  )
where

import Control.Monad (foldM)
import Data.ByteString qualified as BS
import Data.Char (toLower)
import Data.Either (fromRight, lefts, rights)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Parser (parse)
import Golem.Parser.AST (File (..))
import Golem.Parser.CST (Node)
import Golem.Parser.Lower (lower)
import Golem.Parser.Read (readSource)
import Golem.Parser.SourceSettings (SourceSettings)
import Golem.Project.Imports
import Golem.Project.Manifest
import Golem.Project.Paths
import Golem.Syntax
import System.Directory (doesFileExist)
import System.FilePath ((</>))

data SourceFile = SourceFile
  { sfPath :: !FilePath,
    sfText :: !Text,
    sfCst :: !Node,
    sfAst :: !File,
    sfImports :: ![ImportSite],
    sfSyntaxDiagnostics :: ![Diagnostic]
  }

data Project = Project
  { projectRoot :: !FilePath,
    projectFiles :: !FileTable,
    projectManifestFile :: !FileId,
    projectManifestText :: !Text,
    projectManifest :: !Manifest,
    projectChapters :: ![(FileId, Maybe Text)], -- manifest order
    projectSources :: !(Map FileId SourceFile),
    projectImports :: !ImportGraph,
    -- | evaluation order
    projectOrder :: ![FileId],
    -- | how each source file is read (docs/adr ADR 0013)
    projectSourceSettings :: !(Map FileId SourceSettings)
  }

{- | Why a project could not be loaded (golem-project ADR 0006): the
diagnostics, and the files registered so far, where they point:
manifest.toml when it exists and the sources read.
-}
data ProjectFailure = ProjectFailure
  { pfDiagnostics :: ![Diagnostic],
    pfSources :: !(Map FileId SourceInfo)
  }

loadProject :: FilePath -> IO (Either ProjectFailure Project)
loadProject = loadProjectWith Map.empty

-- | @overlay@ replaces file contents (used by the LSP for unsaved edits).
loadProjectWith :: Map FilePath Text -> FilePath -> IO (Either ProjectFailure Project)
loadProjectWith overlay root = do
  let (mfid, ft0) = registerFile "manifest.toml" emptyFileTable
  exists <- doesFileExist (root </> "manifest.toml")
  if not exists
    then pure (Left (ProjectFailure [diagnostic "G0316" Error (mkSpan mfid 0 0) "manifest.toml がありません"] Map.empty))
    else do
      mbytes <- BS.readFile (root </> "manifest.toml")
      let mtext = TE.decodeUtf8Lenient mbytes
          manifestInfo = Map.singleton mfid (SourceInfo "manifest.toml" (mkLineIndex mtext))
          failure ds infos = Left (ProjectFailure ds (Map.union manifestInfo infos))
      case readSource mfid mbytes >>= parseManifest mfid of
        Left ds -> pure (failure ds Map.empty)
        Right manifest -> do
          r <- loadSources overlay root mfid ft0 manifest
          pure $ case r of
            Left (ds, infos) -> failure ds infos
            Right (ft, chapters, sources, graph, settings) ->
              case findCycles graph of
                [] ->
                  Right
                    Project
                      { projectRoot = root,
                        projectFiles = ft,
                        projectManifestFile = mfid,
                        projectManifestText = mtext,
                        projectManifest = manifest,
                        projectChapters = chapters,
                        projectSources = sources,
                        projectImports = graph,
                        projectOrder = topoOrder graph,
                        projectSourceSettings = settings
                      }
                cycles -> failure (map (cycleDiagnostic ft) cycles) (Map.map sourceInfoOf sources)

sourceInfoOf :: SourceFile -> SourceInfo
sourceInfoOf sf = SourceInfo (sfPath sf) (mkLineIndex (sfText sf))

cycleDiagnostic :: FileTable -> [(FileId, ImportSite)] -> Diagnostic
cycleDiagnostic ft path = case path of
  ((_, s0) : _) ->
    (diagnostic "G0305" Error (isSpan s0) ("import が循環しています: " <> T.intercalate " → " (map name path <> take 1 (map name path))))
      { diagRelated = [(isSpan s, "@import " <> isPath s) | (_, s) <- path]
      }
  -- findCycles returns no empty path; this keeps the function total (FileId 0 is manifest.toml)
  [] -> diagnostic "G0305" Error (mkSpan (FileId 0) 0 0) "import が循環しています"
  where
    name (f, _) = maybe "?" T.pack (lookupPath f ft)

type Loaded = (FileTable, [(FileId, Maybe Text)], Map FileId SourceFile, ImportGraph, Map FileId SourceSettings)

-- | The diagnostics of a failed load and the sources read so far.
type LoadFailure = ([Diagnostic], Map FileId SourceInfo)

{- | The paths registered so far by their lower-case form: as written
(normalised) and as resolved (ADR 0006).
-}
data Seen = Seen !(Map String FilePath) !(Map String FilePath)

{- | A path that differs from a registered one only in case (G0304), as
the later path and the earlier one. The written paths come first, so that
every file system gives the same error; the resolved paths catch links
whose targets differ only in case (ADR 0006).
-}
caseCollision :: Seen -> FilePath -> FilePath -> Maybe (FilePath, FilePath)
caseCollision (Seen written resolved) w rel = case (clash written w, clash resolved rel) of
  (Just other, _) -> Just (w, other)
  (_, Just other) -> Just (rel, other)
  _ -> Nothing
  where
    clash m p = case Map.lookup (map toLower p) m of
      Just other | other /= p -> Just other
      _ -> Nothing

see :: FilePath -> FilePath -> Seen -> Seen
see w rel (Seen written resolved) = Seen (Map.insert (map toLower w) w written) (Map.insert (map toLower rel) rel resolved)

caseDiagnostic :: SrcSpan -> (FilePath, FilePath) -> Diagnostic
caseDiagnostic sp (later, earlier) = diagnostic "G0304" Error sp (T.pack ("大文字と小文字だけが異なるパスです: " <> later <> " と " <> earlier))

-- | A path as written, normalised; resolving it has already succeeded.
writtenPath :: FilePath -> FilePath
writtenPath p = fromRight p (normalizeRelative p)

loadSources :: Map FilePath Text -> FilePath -> FileId -> FileTable -> Manifest -> IO (Either LoadFailure Loaded)
loadSources overlay root mfid ft0 manifest = do
  -- chapters first, in manifest order
  r <- foldM addChapter (Right (ft0, [], Seen Map.empty Map.empty, Map.empty)) (chapterFiles (manifestChapters manifest))
  case r of
    Left ds -> pure (Left (ds, Map.empty))
    Right (ft1, chapters, seen, chapterSettings) -> do
      let queue = map fst chapters
      r2 <- crawl ft1 seen Map.empty Map.empty queue
      pure $ case r2 of
        Left e -> Left e
        Right (ft2, sources, edges) ->
          -- files reached only by @import take [source] (docs/adr ADR 0013)
          let settings = Map.union chapterSettings (Map.map (const baseSettings) sources)
           in Right (ft2, chapters, sources, ImportGraph edges, settings)
  where
    manifestSpan = mkSpan mfid 0 0
    baseSettings = manifestSource manifest
    addChapter acc (p, master, edits) = case acc of
      Left ds -> pure (Left ds)
      Right (ft, chs, seen, settings) -> do
        res <- resolveInRoot root p
        pure $ case res of
          Left e -> Left [pathDiagnostic manifestSpan p e]
          Right rel -> case caseCollision seen (writtenPath p) rel of
            Just c -> Left [caseDiagnostic manifestSpan c]
            Nothing ->
              let (fid, ft') = registerFile rel ft
                  own = applyEdits edits baseSettings
               in case Map.lookup fid settings of
                    Just earlier
                      | earlier /= own ->
                          Left [diagnostic "G0301" Error manifestSpan (T.pack ("同じファイルを [source] の設定を変えて章に二度並べています: " <> rel))]
                    _ -> Right (ft', chs <> [(fid, master)], see (writtenPath p) rel seen, Map.insert fid own settings)
    crawl ft _ sources edges [] = pure (Right (ft, sources, edges))
    crawl ft seen sources edges (fid : rest)
      | Map.member fid sources = crawl ft seen sources edges rest
      | otherwise = do
          let path = fromMaybe "" (lookupPath fid ft)
          (content, shown) <- case Map.lookup path overlay of
            Just t -> pure (Right t, t)
            Nothing -> (\b -> (readSource fid b, TE.decodeUtf8Lenient b)) <$> BS.readFile (root </> path)
          -- the sources read so far and this one, where the errors point (ADR 0006)
          let failed ds = pure (Left (ds, Map.insert fid (SourceInfo path (mkLineIndex shown)) (Map.map sourceInfoOf sources)))
          case content of
            Left ds -> failed ds
            Right txt -> do
              let (cst, synDiags) = parse fid txt
                  ast = lower fid cst
                  sites = importsOf ast
                  bad = lefts sites
                  goods = rights sites
              if not (null bad)
                then failed bad
                else do
                  resolved <- traverse (\s -> fmap (s,) (resolveInRoot root (T.unpack (isPath s)))) goods
                  case [pathDiagnostic (isSpan s) (T.unpack (isPath s)) e | (s, Left e) <- resolved] of
                    errs@(_ : _) -> failed errs
                    [] -> do
                      let step (ftA, sn, es, acc) (s, Right rel) =
                            let w = writtenPath (T.unpack (isPath s))
                             in case caseCollision sn w rel of
                                  Just c -> (ftA, sn, es, acc <> [caseDiagnostic (isSpan s) c])
                                  Nothing ->
                                    let (tfid, ftB) = registerFile rel ftA
                                     in (ftB, see w rel sn, es <> [(tfid, s)], acc)
                          step acc (_, Left _) = acc
                          (ft', seen', out, collisions) = foldl step (ft, seen, [], []) resolved
                      if not (null collisions)
                        then failed collisions
                        else
                          crawl
                            ft'
                            seen'
                            (Map.insert fid (SourceFile path txt cst ast goods synDiags) sources)
                            (Map.insert fid out edges)
                            (rest <> map fst out)

pathDiagnostic :: SrcSpan -> FilePath -> PathError -> Diagnostic
pathDiagnostic sp p e =
  diagnostic code Error sp (T.pack (pathErrorMessage e <> ": " <> p))
  where
    code = case e of
      Missing -> "G0302"
      _ -> "G0303"
