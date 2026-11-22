module Golem.Lsp.FileMove (fileMoveRegistration, planFileMove) where

import Control.Applicative ((<|>))
import Control.Exception (IOException, try)
import Control.Monad (foldM, guard, unless, when)
import Data.Aeson qualified as J
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types qualified as J
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.Char (isControl, toLower)
import Data.Int (Int32)
import Data.List (find, isPrefixOf, nub, sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features qualified as F
import Golem.Lsp.FileMove.Chapters (ByteEdit, ChapterTransfer (..), transferChapters)
import Golem.Lsp.FileRename qualified as R
import Golem.Project.Paths (normalizeRelative)
import Golem.Syntax qualified as S
import Language.LSP.Protocol.Types qualified as L
import System.Directory (canonicalizePath, doesDirectoryExist, doesFileExist, listDirectory, pathIsSymbolicLink)
import System.FilePath (isAbsolute, makeRelative, normalise, splitDirectories, takeDirectory, takeExtension, (</>))
import System.IO (IOMode (ReadMode), withBinaryFile)

data Project = Project !FilePath !(Maybe FilePath)
  deriving stock (Eq, Ord)

data Sheet = Sheet !FilePath !(Maybe Text)
  deriving stock (Eq, Ord)

data Document = Document
  { docPath :: !FilePath,
    docText :: !Text,
    docVersion :: !(Maybe Int32)
  }

data Request = Request
  { workspace :: !FilePath,
    sourcePath :: !FilePath,
    destinationPath :: !FilePath,
    projects :: ![Project],
    wikiSheets :: ![Sheet],
    documents :: ![Document]
  }

data EntryKind = File | Directory | Symlink
  deriving stock (Eq)

type DirectoryIndex = Map.Map FilePath [(FilePath, EntryKind)]

data Issue = Issue !FilePath !(Maybe L.Range) !(Maybe FilePath) !String

type Result = Either Issue

fileMoveRegistration :: J.Value -> Maybe FilePath
fileMoveRegistration (J.Object params) = do
  J.Object opts <- KM.lookup "initializationOptions" params
  J.Object golem <- KM.lookup "golem" opts
  J.Object settings <- KM.lookup "fileMove" golem
  guard (KM.lookup "version" settings == Just (J.Number 1))
  J.String uri <- KM.lookup "workspaceUri" settings
  either (const Nothing) Just (fileUri uri)
fileMoveRegistration _ = Nothing

fileUri :: Text -> Either String FilePath
fileUri text = case L.uriToFilePath (L.Uri text) of
  Just p | "file:///" `T.isPrefixOf` text, isAbsolute p, '\0' `notElem` p, normalise p == p -> Right p
  _ -> Left "expected a normalized local file URI"

parseUri :: Text -> J.Parser FilePath
parseUri = either fail pure . fileUri

nullable :: (a -> J.Parser b) -> Maybe a -> J.Parser (Maybe b)
nullable = traverse

parseProject :: J.Value -> J.Parser Project
parseProject = J.withObject "project" $ \o ->
  Project <$> (o J..: "uri" >>= parseUri) <*> (o J..: "plotCsv" >>= nullable parseUri)

parseSheet :: J.Value -> J.Parser Sheet
parseSheet = J.withObject "sheet" $ \o -> Sheet <$> (o J..: "uri" >>= parseUri) <*> o J..: "title"

parseDocument :: J.Value -> J.Parser Document
parseDocument = J.withObject "open document" $ \o ->
  Document <$> (o J..: "uri" >>= parseUri) <*> o J..: "text" <*> (Just <$> o J..: "version")

parseRequest :: J.Value -> J.Parser Request
parseRequest = J.withObject "file move" $ \o -> do
  complete <- o J..: "inventoryComplete"
  unless complete (fail "workspace inventory is incomplete")
  Request
    <$> (o J..: "workspaceUri" >>= parseUri)
    <*> (o J..: "oldUri" >>= parseUri)
    <*> (o J..: "newUri" >>= parseUri)
    <*> (o J..: "projects" >>= traverse parseProject)
    <*> (o J..: "wikiSheets" >>= traverse parseSheet)
    <*> (o J..: "documents" >>= traverse parseDocument)

planFileMove :: F.Encoding -> Maybe FilePath -> J.Value -> IO (Either J.Value J.Value)
planFileMove encoding registration params = fmap (first issueJson) $
  case J.parseEither parseRequest params of
    Left e -> pure (Left (problem root e))
    Right r
      | Just (workspace r) /= registration -> pure (Left (problem (workspace r) "workspace was not registered at initialize"))
      | otherwise -> planRegistered encoding r
  where
    root = fromMaybe "/" registration

planRegistered :: F.Encoding -> Request -> IO (Result J.Value)
planRegistered enc req = do
  let root = workspace req
  readRoot <- attempt root $ do
    canonical <- canonicalizePath root
    if canonical /= root then pure (Left (problem root "workspace traverses a symbolic link")) else indexTree root
  case readRoot of
    Left e -> pure (Left e)
    Right dirs -> case checkInventory req dirs of
      Left e -> pure (Left e)
      Right files -> do
        snapshots <- readDocuments req files
        pure (snapshots >>= buildPlan enc req dirs files)

-- Index physical directories without following symbolic links, including
-- conventional build directory names that can contain source documents.
indexTree :: FilePath -> IO (Result DirectoryIndex)
indexTree dir = attempt dir $ do
  canonical <- canonicalizePath dir
  if canonical /= dir
    then pure (Left (problem dir "indexed directory now traverses a symbolic link"))
    else scanDirectory dir

scanDirectory :: FilePath -> IO (Result DirectoryIndex)
scanDirectory dir = do
  names <- sort <$> listDirectory dir
  entries <- traverse (kindOf dir) names
  case sequence entries of
    Left e -> pure (Left e)
    Right children -> do
      descendants <- traverse indexTree [p | (p, Directory) <- children]
      pure (Map.unions . (Map.singleton dir children :) <$> sequence descendants)

kindOf :: FilePath -> FilePath -> IO (Result (FilePath, EntryKind))
kindOf dir name = attempt path $ do
  symlink <- pathIsSymbolicLink path
  if symlink
    then pure (Right (path, Symlink))
    else do
      directory <- doesDirectoryExist path
      regular <- doesFileExist path
      pure $
        if directory
          then Right (path, Directory)
          else
            if regular
              then Right (path, File)
              else Left (problem path "unsupported or missing directory entry")
  where
    path = dir </> name

attempt :: FilePath -> IO (Result a) -> IO (Result a)
attempt path action = do
  result <- try action
  pure (either (Left . problem path . showIOException) id result)
  where
    showIOException :: IOException -> String
    showIOException = show

within :: FilePath -> FilePath -> Bool
within root path = splitDirectories root `isPrefixOf` splitDirectories path

problem :: FilePath -> String -> Issue
problem uri = Issue uri Nothing Nothing

projectPath :: Project -> FilePath
projectPath (Project path _) = path

checkInventory :: Request -> DirectoryIndex -> Result (Map.Map FilePath EntryKind)
checkInventory req dirs = do
  let files = Map.insert root Directory (Map.fromList (concat (Map.elems dirs)))
      declared = map projectPath (projects req)
      found = [takeDirectory file | (file, k) <- Map.toList files, k /= Directory, let parent = takeDirectory file, file == parent </> "manifest.toml"]
      safe p k = Map.lookup p files == Just k
  unless (sort found == sort declared) $
    Left (problem (fromMaybe root (find (`notElem` declared) found <|> find (`notElem` found) declared)) "project inventory does not match manifest locations")
  unless (unique declared && unique [p | Sheet p _ <- wikiSheets req] && unique (map docPath (documents req))) $
    Left (problem root "duplicate project, sheet or open document URI")
  unless (noNesting declared && noNesting (map (movedPath req) declared)) $
    Left (problem root "nested Golem projects are not supported")
  unless (old /= root && within root old && within root new && not (within old new)) $
    Left (problem old "move is outside the workspace or into its own subtree")
  unless (safe old File || safe old Directory) (Left (problem old "missing or symbolic-link source"))
  when (old `elem` [p </> "manifest.toml" | p <- declared]) $
    Left (problem old "a project manifest can only move with its project")
  unless (not (safe old File) || new /= takeDirectory new </> "manifest.toml") $
    Left (problem new "a file move cannot introduce a project manifest")
  unless (Map.member (takeDirectory new) dirs && Map.notMember new files) $
    Left (problem new "destination already exists or its parent is unavailable")
  case find (\(p, k) -> k == Symlink && within old p) (Map.toList files) of
    Just (link, _) -> Left (problem link "moving a symbolic link is not supported")
    Nothing -> pure ()
  mapM_
    ( \(Project p plot) -> do
        unless (safe (p </> "manifest.toml") File) (Left (problem p "manifest cannot be read"))
        case plot of
          Just csv | not (within p csv && safe csv File) -> Left (problem csv "plot is outside its project or cannot be read")
          _ -> pure ()
    )
    (projects req)
  mapM_ (\(Sheet p _) -> unless (safe p File) (Left (problem p "sheet cannot be read"))) (wikiSheets req)
  mapM_ (\d -> unless (safe (docPath d) File) (Left (problem (docPath d) "open document is missing or a symbolic link"))) (documents req)
  pure files
  where
    root = workspace req
    old = sourcePath req
    new = destinationPath req
    unique xs = length xs == Set.size (Set.fromList xs)
    noNesting roots = and [p == q || not (within p q) | p <- roots, q <- roots]

movedPath :: Request -> FilePath -> FilePath
movedPath req p
  | p == old = new
  | within old p = new </> makeRelative old p
  | otherwise = p
  where
    old = sourcePath req
    new = destinationPath req

owner :: [FilePath] -> FilePath -> Maybe FilePath
owner roots p = find (`within` p) roots

extension :: FilePath -> String
extension = map toLower . takeExtension

readDocuments :: Request -> Map.Map FilePath EntryKind -> IO (Result [Document])
readDocuments req files = do
  let plots = [p | Project _ (Just p) <- projects req]
      projectFiles = [projectPath p </> name | p <- projects req, name <- ["manifest.toml", "style.toml"], Map.member (projectPath p </> name) files]
      sheets = [p | Sheet p _ <- wikiSheets req]
      sources = [p | (p, k) <- Map.toList files, k /= Directory, extension p `elem` [".gm", ".emet"]]
      markdown = [p | p <- sheets, extension p == ".md"]
      pathways = Set.toAscList (Set.fromList (plots <> projectFiles <> sources <> markdown <> map docPath (documents req)))
      opening = Map.fromList [(docPath d, d) | d <- documents req]
  checked <- traverse (\p -> attempt p (Right <$> withBinaryFile p ReadMode (const (pure ())))) (filter (`notElem` pathways) sheets)
  case sequence checked of
    Left e -> pure (Left e)
    Right _ -> sequence <$> traverse (readOne opening) pathways
  where
    readOne opening path
      | Map.lookup path files /= Just File = pure (Left (problem path "reference source is not a regular file"))
      | otherwise = attempt path $ do
          canonical <- canonicalizePath path
          if canonical /= path
            then pure (Left (problem path "reference source now traverses a symbolic link"))
            else case Map.lookup path opening of
              Just doc -> pure (Right doc)
              Nothing -> do
                contents <- BS.readFile path
                pure (first (problem path . show) (Document path <$> TE.decodeUtf8' contents <*> pure Nothing))

buildPlan :: F.Encoding -> Request -> DirectoryIndex -> Map.Map FilePath EntryKind -> [Document] -> Result J.Value
buildPlan enc req dirs files docs = do
  (chapterEdits, summary) <- chapterPlan req files docs
  editGroups <- foldM (collect chapterEdits) Map.empty docs
  pure $
    J.object
      [ "complete" J..= True,
        "groups" J..= [J.object ["projectUri" J..= fmap L.filePathToUri p, "edits" J..= reverse edits] | (p, edits) <- Map.toList editGroups],
        "snapshot" J..= J.object ["documents" J..= map documentJson docs, "projects" J..= map projectJson (projects req), "wikiSheets" J..= map sheetJson (wikiSheets req), "directories" J..= map directoryJson (Map.toList dirs)],
        "chapters" J..= summary
      ]
  where
    roots = map projectPath (projects req)
    postRoots = map (movedPath req) roots
    workspaceRoot = workspace req
    plotFiles = [plot | Project _ (Just plot) <- projects req]
    indexed = [(makeRelative workspaceRoot p, title) | Sheet p title <- wikiSheets req]
    wikiPairs = [(makeRelative workspaceRoot (sourcePath req), makeRelative workspaceRoot (destinationPath req))]
    future = Map.fromList [(movedPath req path, kind) | (path, kind) <- Map.toList files]
    collect chapterEdits groups doc = do
      let path = docPath doc
          src = docText doc
          existingOwner = owner roots path
          relativeWiki = makeRelative workspaceRoot path
          isManifest = path `elem` [p </> "manifest.toml" | p <- roots]
          isStyle = path `elem` [p </> "style.toml" | p <- roots]
          structural = Map.findWithDefault [] path chapterEdits
          rewrite = rewriteRef path existingOwner
          planner
            | isManifest = R.planManifestWith (null structural) rewrite src
            | isStyle = R.planStyleWith rewrite src
            | path `elem` plotFiles = R.planPlotWith rewrite src
            | extension path == ".gm" = R.planImportsMove rewrite src
            | extension path == ".emet" = R.planEmetMove rewrite src
            | extension path == ".md" && relativeWiki `elem` map fst indexed = R.planWikiMove wikiPairs relativeWiki indexed src
            | otherwise = Right []
      references <- first (siteIssue enc doc (fromMaybe (takeDirectory path) existingOwner)) planner
      edits <- mergeEdits path (structural <> references)
      if null edits
        then pure groups
        else pure (Map.insertWith (<>) existingOwner [documentEdit enc doc edits] groups)
    rewriteRef from before _ _ spelling
      | "://" `T.isInfixOf` T.pack spelling = Right Nothing
      | otherwise = do
          relative <- first show (normalizeRelative spelling)
          let oldBase = fromMaybe (takeDirectory from) before
              original = oldBase </> relative
              newSource = movedPath req from
              after = owner postRoots newSource
              newBase = fromMaybe (takeDirectory newSource) after
              target = movedPath req original
          unless (Map.lookup original files == Just File) $
            Left "reference target is missing or a symbolic link"
          unless (within newBase target && Map.lookup target future == Just File) $
            Left "reference target is outside the destination project"
          let written = makeRelative newBase target
          unless (written == relative || extension from `notElem` [".gm", ".emet"] || not (any isControl written)) $
            Left "reference path contains an unsupported control character"
          pure (if written == relative then Nothing else Just written)

chapterPlan :: Request -> Map.Map FilePath EntryKind -> [Document] -> Result (Map.Map FilePath [ByteEdit], [J.Value])
chapterPlan req files docs = case owner roots (sourcePath req) of
  Nothing -> Right (Map.empty, [])
  Just from
    | movedPath req from /= from || target == Just from -> Right (Map.empty, [])
    | otherwise -> do
        old <- manifest from
        new <- traverse manifest target
        (oldEdit, newEdit, chapters) <- first (problem (docPath old)) (transferChapters (relocate from) (docText old) (docText <$> new))
        let replacements = Map.fromList ([(docPath old, oldEdit) | not (null oldEdit)] <> [(docPath d, newEdit) | not (null newEdit), Just d <- [new]])
        pure (replacements, map (summary from) chapters)
  where
    roots = map projectPath (projects req)
    target = owner roots (destinationPath req)
    manifest root =
      let path = root </> "manifest.toml"
       in maybe (Left (problem path "manifest snapshot is missing")) Right (find ((== path) . docPath) docs)
    relocate from path = do
      relative <- first show (normalizeRelative path)
      let original = from </> relative
          moved = movedPath req original
      unless (Map.lookup original files == Just File) (Left ("chapter cannot be read: " <> original))
      pure (if original == moved then Nothing else Just (moved, maybe moved (`makeRelative` moved) target))
    summary from transfer =
      J.object
        [ "oldUri" J..= L.filePathToUri (normalise (from </> chapterOld transfer)),
          "newUri" J..= L.filePathToUri (chapterNew transfer),
          "sourceProjectUri" J..= L.filePathToUri from,
          "destinationProjectUri" J..= fmap L.filePathToUri target,
          "sourceIndices" J..= chapterIndices transfer
        ]

mergeEdits :: FilePath -> [ByteEdit] -> Result [ByteEdit]
mergeEdits uri = fmap reverse . foldM insert [] . sortOn (\(s, e, _) -> (s, e)) . nub
  where
    insert edits edit@(start, _, _) = case edits of
      (_, lastEnd, _) : _ | start < lastEnd -> Left (problem uri "overlapping move edits")
      _ -> Right (edit : edits)

siteIssue :: F.Encoding -> Document -> FilePath -> R.PathIssue -> Issue
siteIssue enc doc root (R.PathIssue start end target reason) =
  Issue (docPath doc) (if start == end then Nothing else Just (positionRange enc (docText doc) start end)) (if null target then Nothing else Just (normalise (root </> target))) reason

positionRange :: F.Encoding -> Text -> Int -> Int -> L.Range
positionRange enc source start end = L.Range (pos start) (pos end)
  where
    index = S.mkLineIndex source
    pos i = case F.toLineCol enc index i of
      S.LineCol line column -> L.Position (fromIntegral line) (fromIntegral column)

documentEdit :: F.Encoding -> Document -> [ByteEdit] -> L.TextDocumentEdit
documentEdit enc (Document path source version) edits =
  L.TextDocumentEdit
    (L.OptionalVersionedTextDocumentIdentifier (L.filePathToUri path) (maybe (L.InR L.Null) L.InL version))
    [L.InL (L.TextEdit (positionRange enc source start end) text) | (start, end, text) <- edits]

documentJson :: Document -> J.Value
documentJson d = J.object ["uri" J..= L.filePathToUri (docPath d), "text" J..= docText d, "version" J..= docVersion d]

projectJson :: Project -> J.Value
projectJson (Project path plot) = J.object ["uri" J..= L.filePathToUri path, "plotCsv" J..= fmap L.filePathToUri plot]

sheetJson :: Sheet -> J.Value
sheetJson (Sheet path title) = J.object ["uri" J..= L.filePathToUri path, "title" J..= title]

directoryJson :: (FilePath, [(FilePath, EntryKind)]) -> J.Value
directoryJson (path, children) = J.object ["uri" J..= L.filePathToUri path, "entries" J..= [J.object ["uri" J..= L.filePathToUri entry, "kind" J..= entryKind kind] | (entry, kind) <- children]]
  where
    entryKind :: EntryKind -> Text
    entryKind File = "file"
    entryKind Directory = "directory"
    entryKind Symlink = "symlink"

issueJson :: Issue -> J.Value
issueJson (Issue path range target reason) = J.object ["issues" J..= [J.object ["uri" J..= L.filePathToUri path, "range" J..= range, "targetUri" J..= fmap L.filePathToUri target, "reason" J..= reason]]]
