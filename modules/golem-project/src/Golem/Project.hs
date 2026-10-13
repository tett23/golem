{- | Loading a project: manifest, source files reachable from it, and the
import graph (golem-project ADR 0001).
-}
module Golem.Project
  ( Project (..),
    SourceFile (..),
    loadProject,
    loadProjectWith,
    module Golem.Project.Manifest,
    module Golem.Project.Imports,
  )
where

import Control.Monad (foldM)
import Data.ByteString qualified as BS
import Data.Char (toLower)
import Data.Either (lefts, rights)
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
    projectOrder :: ![FileId] -- evaluation order
  }

loadProject :: FilePath -> IO (Either [Diagnostic] Project)
loadProject = loadProjectWith Map.empty

-- | @overlay@ replaces file contents (used by the LSP for unsaved edits).
loadProjectWith :: Map FilePath Text -> FilePath -> IO (Either [Diagnostic] Project)
loadProjectWith overlay root = do
  let (mfid, ft0) = registerFile "manifest.toml" emptyFileTable
  exists <- doesFileExist (root </> "manifest.toml")
  if not exists
    then pure (Left [diagnostic "G0302" Error (mkSpan mfid 0 0) "manifest.toml がありません"])
    else do
      mbytes <- BS.readFile (root </> "manifest.toml")
      case readSource mfid mbytes >>= parseManifest mfid of
        Left ds -> pure (Left ds)
        Right manifest -> do
          let mtext = TE.decodeUtf8Lenient mbytes
          r <- loadSources overlay root mfid ft0 manifest
          pure $ case r of
            Left ds -> Left ds
            Right (ft, chapters, sources, graph) ->
              let cycles = findCycles graph
               in if null cycles
                    then
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
                            projectOrder = topoOrder graph
                          }
                    else Left (map (cycleDiagnostic ft) cycles)

cycleDiagnostic :: FileTable -> [(FileId, ImportSite)] -> Diagnostic
cycleDiagnostic ft path = case path of
  ((_, s0) : _) ->
    (diagnostic "G0305" Error (isSpan s0) ("import が循環しています: " <> T.intercalate " → " (map name path <> take 1 (map name path))))
      { diagRelated = [(isSpan s, "@import " <> isPath s) | (_, s) <- path]
      }
  [] -> diagnostic "G0305" Error (mkSpan (FileId 0) 0 0) "import が循環しています"
  where
    name (f, _) = maybe "?" T.pack (lookupPath f ft)

type Loaded = (FileTable, [(FileId, Maybe Text)], Map FileId SourceFile, ImportGraph)

loadSources :: Map FilePath Text -> FilePath -> FileId -> FileTable -> Manifest -> IO (Either [Diagnostic] Loaded)
loadSources overlay root mfid ft0 manifest = do
  -- chapters first, in manifest order
  r <- foldM addChapter (Right (ft0, [], Map.empty)) (chapterFiles (manifestChapters manifest))
  case r of
    Left ds -> pure (Left ds)
    Right (ft1, chapters, lowerMap) -> do
      let queue = map fst chapters
      r2 <- crawl ft1 lowerMap Map.empty Map.empty queue
      pure $ case r2 of
        Left ds -> Left ds
        Right (ft2, sources, edges) -> Right (ft2, chapters, sources, ImportGraph edges)
  where
    manifestSpan = mkSpan mfid 0 0
    addChapter acc (p, master) = case acc of
      Left ds -> pure (Left ds)
      Right (ft, chs, lowers) -> do
        res <- resolveInRoot root p
        pure $ case res of
          Left e -> Left [pathDiagnostic manifestSpan p e]
          Right rel -> case collision lowers rel of
            Just other -> Left [diagnostic "G0304" Error manifestSpan (T.pack ("大文字と小文字だけが異なるパスです: " <> rel <> " と " <> other))]
            Nothing ->
              let (fid, ft') = registerFile rel ft
               in Right (ft', chs <> [(fid, master)], Map.insert (map toLower rel) rel lowers)
    collision lowers rel = case Map.lookup (map toLower rel) lowers of
      Just other | other /= rel -> Just other
      _ -> Nothing
    crawl ft _ sources edges [] = pure (Right (ft, sources, edges))
    crawl ft lowers sources edges (fid : rest)
      | Map.member fid sources = crawl ft lowers sources edges rest
      | otherwise = do
          let path = fromMaybe "" (lookupPath fid ft)
          content <- case Map.lookup path overlay of
            Just t -> pure (Right t)
            Nothing -> readSource fid <$> BS.readFile (root </> path)
          case content of
            Left ds -> pure (Left ds)
            Right txt -> do
              let (cst, synDiags) = parse fid txt
                  ast = lower fid cst
                  sites = importsOf ast
                  bad = lefts sites
                  goods = rights sites
              if not (null bad)
                then pure (Left bad)
                else do
                  resolved <- traverse (\s -> fmap (s,) (resolveInRoot root (T.unpack (isPath s)))) goods
                  case [pathDiagnostic (isSpan s) (T.unpack (isPath s)) e | (s, Left e) <- resolved] of
                    errs@(_ : _) -> pure (Left errs)
                    [] -> do
                      let step (ftA, lw, es, acc) (s, Right rel) = case collision lw rel of
                            Just other -> (ftA, lw, es, acc <> [diagnostic "G0304" Error (isSpan s) (T.pack ("大文字と小文字だけが異なるパスです: " <> rel <> " と " <> other))])
                            Nothing ->
                              let (tfid, ftB) = registerFile rel ftA
                               in (ftB, Map.insert (map toLower rel) rel lw, es <> [(tfid, s)], acc)
                          step acc (_, Left _) = acc
                          (ft', lowers', out, collisions) = foldl step (ft, lowers, [], []) resolved
                      if not (null collisions)
                        then pure (Left collisions)
                        else
                          crawl
                            ft'
                            lowers'
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
