module Golem.Lsp.FileMove (fileMoveRegistration, planFileMove, planMovedReferences) where

import Control.Applicative ((<|>))
import Control.Exception (IOException, try)
import Control.Monad (foldM, forM_, guard, unless, when)
import Data.Aeson qualified as J
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types qualified as J
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.Char (isControl, toLower)
import Data.Int (Int32)
import Data.List (find, findIndex, isPrefixOf, nub, sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features qualified as F
import Golem.Lsp.FileMove.Chapters (ByteEdit, ChapterTransfer (..), Placement (..), partitionChapters, partitionOutgoing, partitionTransfers, rebuildChapters)
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
    -- | Independent moves: source and destination of each pair.
    moves :: ![(FilePath, FilePath)],
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
    <*> (pure <$> movePair o)
    <*> (o J..: "projects" >>= traverse parseProject)
    <*> (o J..: "wikiSheets" >>= traverse parseSheet)
    <*> (o J..: "documents" >>= traverse parseDocument)

movePair :: J.Object -> J.Parser (FilePath, FilePath)
movePair o = (,) <$> (o J..: "oldUri" >>= parseUri) <*> (o J..: "newUri" >>= parseUri)

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
  readRoot <- readWorkspace (workspace req)
  case readRoot of
    Left e -> pure (Left e)
    Right dirs -> planIndexed enc id dirs req dirs

readWorkspace :: FilePath -> IO (Result DirectoryIndex)
readWorkspace root = attempt root $ do
  canonical <- canonicalizePath root
  if canonical /= root then pure (Left (problem root "workspace traverses a symbolic link")) else indexTree root

{- | Plan the moves of a request on an index of the workspace before them.
@locate@ maps a path before the moves to where it is now on the disk and
where the response names it; @shown@ is the index of the disk as it is now,
which the snapshot reports.
-}
planIndexed :: F.Encoding -> (FilePath -> FilePath) -> DirectoryIndex -> Request -> DirectoryIndex -> IO (Result J.Value)
planIndexed enc locate shown req dirs = case checkInventory req dirs of
  Left e -> pure (Left e)
  Right files -> do
    snapshots <- readDocuments locate req files
    pure (snapshots >>= buildPlan enc locate shown req files)

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
  forM_ (moves req) $ \(old, new) -> do
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
    unique xs = length xs == Set.size (Set.fromList xs)
    noNesting roots = and [p == q || not (within p q) | p <- roots, q <- roots]

movedPath :: Request -> FilePath -> FilePath
movedPath = through . moves

-- | The composite mapping of independent moves.
through :: [(FilePath, FilePath)] -> FilePath -> FilePath
through pairs p = case find (\(old, _) -> within old p) pairs of
  Just (old, new)
    | p == old -> new
    | otherwise -> new </> makeRelative old p
  Nothing -> p

owner :: [FilePath] -> FilePath -> Maybe FilePath
owner roots p = find (`within` p) roots

extension :: FilePath -> String
extension = map toLower . takeExtension

readDocuments :: (FilePath -> FilePath) -> Request -> Map.Map FilePath EntryKind -> IO (Result [Document])
readDocuments locate req files = do
  let plots = [p | Project _ (Just p) <- projects req]
      projectFiles = [projectPath p </> name | p <- projects req, name <- ["manifest.toml", "style.toml"], Map.member (projectPath p </> name) files]
      sheets = [p | Sheet p _ <- wikiSheets req]
      sources = [p | (p, k) <- Map.toList files, k /= Directory, extension p `elem` [".gm", ".emet"]]
      markdown = [p | p <- sheets, extension p == ".md"]
      pathways = Set.toAscList (Set.fromList (plots <> projectFiles <> sources <> markdown <> map docPath (documents req)))
      opening = Map.fromList [(docPath d, d) | d <- documents req]
  checked <- traverse (\p -> attempt p (Right <$> withBinaryFile (locate p) ReadMode (const (pure ())))) (filter (`notElem` pathways) sheets)
  case sequence checked of
    Left e -> pure (Left e)
    Right _ -> sequence <$> traverse (readOne opening) pathways
  where
    readOne opening path
      | Map.lookup path files /= Just File = pure (Left (problem path "reference source is not a regular file"))
      | otherwise = attempt path $ do
          canonical <- canonicalizePath (locate path)
          if canonical /= locate path
            then pure (Left (problem path "reference source now traverses a symbolic link"))
            else case Map.lookup path opening of
              Just doc -> pure (Right doc)
              Nothing -> do
                contents <- BS.readFile (locate path)
                pure (first (problem path . show) (Document path <$> TE.decodeUtf8' contents <*> pure Nothing))

buildPlan :: F.Encoding -> (FilePath -> FilePath) -> DirectoryIndex -> Request -> Map.Map FilePath EntryKind -> [Document] -> Result J.Value
buildPlan enc locate shown req files docs = do
  (chapterEdits, summary) <- chapterPlan req files docs
  editGroups <- foldM (collect chapterEdits) Map.empty docs
  pure $
    J.object
      [ "complete" J..= True,
        "groups" J..= [J.object ["projectUri" J..= fmap (L.filePathToUri . locate) p, "edits" J..= reverse edits] | (p, edits) <- Map.toList editGroups],
        "snapshot" J..= J.object ["documents" J..= map (documentJson locate) docs, "projects" J..= map (projectJson locate) (projects req), "wikiSheets" J..= map (sheetJson locate) (wikiSheets req), "directories" J..= map directoryJson (Map.toList shown)],
        "chapters" J..= summary
      ]
  where
    roots = map projectPath (projects req)
    postRoots = map (movedPath req) roots
    workspaceRoot = workspace req
    plotFiles = [plot | Project _ (Just plot) <- projects req]
    indexed = [(makeRelative workspaceRoot p, title) | Sheet p title <- wikiSheets req]
    wikiPairs = [(makeRelative workspaceRoot old, makeRelative workspaceRoot new) | (old, new) <- moves req]
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
        else pure (Map.insertWith (<>) existingOwner [documentEdit enc locate doc edits] groups)
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

{- | Transfer chapter registrations between manifests. Each move whose
source belongs to a project that stays, and whose destination is outside
that project, makes the project a source. Every chapter of a source project
is placed once by the composite mapping, so a manifest gets one edit, and
a destination appends its incoming chapters in the order of the moves.
-}
chapterPlan :: Request -> Map.Map FilePath EntryKind -> [Document] -> Result (Map.Map FilePath [ByteEdit], [J.Value])
chapterPlan req files docs = do
  sourceParts <- traverse (\from -> manifest from >>= \old -> (from,old,) <$> first (problem (docPath old)) (partitionChapters (place True from) (docText old))) sources
  let active = [(from, old, part) | (from, old, part) <- sourceParts, not (null (partitionTransfers part))]
      outgoing = sortOn (\(_, k, _, _) -> k) [(d, k, node, old) | (_, old, part) <- active, (d, k, node) <- partitionOutgoing part]
      receivers = nub [d | (Just d, _, _, _) <- outgoing]
      incoming d = [node | (Just d', _, node, _) <- outgoing, d' == d]
  let sourceEdits = [(docPath old, rebuildChapters part (incoming from)) | (from, old, part) <- active]
  destinationEdits <-
    traverse
      ( \d -> do
          new <- manifest d
          let blame = case [old | (Just d', _, _, old) <- outgoing, d' == d] of
                old : _ -> old
                [] -> new
          part <- first (problem (docPath blame)) (partitionChapters (place False d) (docText new))
          pure (docPath new, rebuildChapters part (incoming d))
      )
      [d | d <- receivers, d `notElem` [from | (from, _, _) <- active]]
  let transfers = sortOn (\(_, _, k, _) -> k) [(from, d, k, t) | (from, _, part) <- active, (d, k, t) <- partitionTransfers part]
  pure (Map.fromList [(path, edit) | (path, edit) <- sourceEdits <> destinationEdits, not (null edit)], map summary transfers)
  where
    roots = map projectPath (projects req)
    sources = nub [from | (old, new) <- moves req, Just from <- [owner roots old], movedPath req from == from, owner roots new /= Just from]
    manifest root =
      let path = root </> "manifest.toml"
       in maybe (Left (problem path "manifest snapshot is missing")) Right (find ((== path) . docPath) docs)
    -- A source project reads every chapter; a destination keeps entries it
    -- cannot read, as the manifest rewrite skips its chapters.
    place strict project entry = case entry of
      Left reason -> if strict then Left reason else Right Keep
      Right path -> case normalizeRelative path of
        Left e -> if strict then Left (show e) else Right Keep
        Right relative -> do
          let original = project </> relative
              moved = movedPath req original
              target = owner roots moved
          when ((strict || original /= moved) && Map.lookup original files /= Just File) (Left ("chapter cannot be read: " <> original))
          if original == moved
            then pure Keep
            else
              if target == Just project
                then pure (Rewrite (makeRelative project moved))
                else do
                  unless strict (Left ("chapter of a destination project moves to another project: " <> original))
                  let order = fromMaybe 0 (findIndex (\(old, _) -> within old original) (moves req))
                  pure (Transfer target order moved (maybe moved (`makeRelative` moved) target))
    summary (from, target, _, transfer) =
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

documentEdit :: F.Encoding -> (FilePath -> FilePath) -> Document -> [ByteEdit] -> L.TextDocumentEdit
documentEdit enc locate (Document path source version) edits =
  L.TextDocumentEdit
    (L.OptionalVersionedTextDocumentIdentifier (L.filePathToUri (locate path)) (maybe (L.InR L.Null) L.InL version))
    [L.InL (L.TextEdit (positionRange enc source start end) text) | (start, end, text) <- edits]

documentJson :: (FilePath -> FilePath) -> Document -> J.Value
documentJson locate d = J.object ["uri" J..= L.filePathToUri (locate (docPath d)), "text" J..= docText d, "version" J..= docVersion d]

projectJson :: (FilePath -> FilePath) -> Project -> J.Value
projectJson locate (Project path plot) = J.object ["uri" J..= L.filePathToUri (locate path), "plotCsv" J..= fmap (L.filePathToUri . locate) plot]

sheetJson :: (FilePath -> FilePath) -> Sheet -> J.Value
sheetJson locate (Sheet path title) = J.object ["uri" J..= L.filePathToUri (locate path), "title" J..= title]

directoryJson :: (FilePath, [(FilePath, EntryKind)]) -> J.Value
directoryJson (path, children) = J.object ["uri" J..= L.filePathToUri path, "entries" J..= [J.object ["uri" J..= L.filePathToUri entry, "kind" J..= entryKind kind] | (entry, kind) <- children]]
  where
    entryKind :: EntryKind -> Text
    entryKind File = "file"
    entryKind Directory = "directory"
    entryKind Symlink = "symlink"

issueJson :: Issue -> J.Value
issueJson (Issue path range target reason) = J.object ["issues" J..= [J.object ["uri" J..= L.filePathToUri path, "range" J..= range, "targetUri" J..= fmap L.filePathToUri target, "reason" J..= reason]]]

{- | Plan the reference edits for independent moves already made on the
disk (root ADR 0426). The request names the state after the moves; the
disk index and the request are mapped back to the state before them, then
planned as 'planFileMove' plans one move, with the composite mapping.
-}
planMovedReferences :: F.Encoding -> Maybe FilePath -> J.Value -> IO (Either J.Value J.Value)
planMovedReferences encoding registration params = fmap (first issueJson) $
  case J.parseEither parseMovedRequest params of
    Left e -> pure (Left (problem root e))
    Right r
      | Just (workspace r) /= registration -> pure (Left (problem (workspace r) "workspace was not registered at initialize"))
      | otherwise -> planMoved encoding r
  where
    root = fromMaybe "/" registration

parseMovedRequest :: J.Value -> J.Parser Request
parseMovedRequest = J.withObject "moved references" $ \o -> do
  complete <- o J..: "inventoryComplete"
  unless complete (fail "workspace inventory is incomplete")
  Request
    <$> (o J..: "workspaceUri" >>= parseUri)
    <*> (o J..: "moves" >>= traverse (J.withObject "move" movePair))
    <*> (o J..: "projects" >>= traverse parseProject)
    <*> (o J..: "wikiSheets" >>= traverse parseSheet)
    <*> (o J..: "documents" >>= traverse parseDocument)

planMoved :: F.Encoding -> Request -> IO (Result J.Value)
planMoved enc after = do
  readRoot <- readWorkspace root
  case readRoot >>= \dirs -> dirs <$ checkMoved after dirs of
    Left e -> pure (Left e)
    Right dirs -> do
      let pairs = moves after
          back = through [(new, old) | (old, new) <- pairs]
          before =
            after
              { projects = [Project (back p) (back <$> plot) | Project p plot <- projects after],
                wikiSheets = [Sheet (back p) title | Sheet p title <- wikiSheets after],
                documents = [d {docPath = back (docPath d)} | d <- documents after]
              }
          forward = through pairs
      first (relocateIssue forward) <$> planIndexed enc forward dirs before (unmoveIndex root pairs dirs)
  where
    root = workspace after

relocateIssue :: (FilePath -> FilePath) -> Issue -> Issue
relocateIssue f (Issue path range target reason) = Issue (f path) range (f <$> target) reason

{- | The checks on the state after the moves: the moves are given, stay in
the workspace and are independent; each source is gone and each
destination is present, without a symbolic link. Presence is decided by
the names the parent directory lists, so a change of case is a move.
-}
checkMoved :: Request -> DirectoryIndex -> Result ()
checkMoved req dirs = do
  when (null pairs) (Left (problem root "no moves were given"))
  forM_ pairs $ \(old, new) ->
    case find (\p -> p == root || not (within root p)) [old, new] of
      Just outside -> Left (problem outside "move is outside the workspace")
      Nothing -> pure ()
  forM_ (zip [0 :: Int ..] pairs) $ \(i, (old, new)) -> do
    when (related old new) (Left (problem old "move is into its own subtree"))
    forM_ (take i pairs) $ \(old', new') ->
      when (or [related x y | x <- [old', new'], y <- [old, new]]) $
        Left (problem old "moves are not independent: they chain or nest")
  forM_ pairs $ \(old, new) -> do
    when (isJust (entry old)) (Left (problem old "move source still exists"))
    forM_ (ancestors old) $ \parent -> case entry parent of
      Just kind | kind /= Directory -> Left (problem parent "move source parent is not a directory")
      _ -> pure ()
    case entry new of
      Nothing -> Left (problem new "move destination does not exist")
      Just Symlink -> Left (problem new "move destination is a symbolic link")
      Just _ -> pure ()
    case find (\(p, k) -> k == Symlink && within new p) entries of
      Just (link, _) -> Left (problem link "move destination contains a symbolic link")
      Nothing -> pure ()
  where
    root = workspace req
    pairs = moves req
    entries = concat (Map.elems dirs)
    entry p = Map.lookup (takeDirectory p) dirs >>= lookup p
    related x y = within x y || within y x
    ancestors p = takeWhile (\a -> a /= root && within root a) (drop 1 (iterate takeDirectory p))

{- | The index before the moves: each entry under a destination goes back
under its source, and a source parent removed after the move is rebuilt.
-}
unmoveIndex :: FilePath -> [(FilePath, FilePath)] -> DirectoryIndex -> DirectoryIndex
unmoveIndex root pairs dirs = Map.unionWith (<>) (Map.fromList [(d, []) | d <- root : [p | (p, Directory) <- Map.toList complete]]) children
  where
    back = through [(new, old) | (old, new) <- pairs]
    restored = Map.fromList [(back p, k) | listing <- Map.elems dirs, (p, k) <- listing]
    complete = Map.union restored (Map.fromList [(a, Directory) | p <- Map.keys restored, a <- parents p])
    parents p = takeWhile (\a -> a /= root && within root a) (drop 1 (iterate takeDirectory p))
    children = Map.map (sortOn fst) (Map.fromListWith (<>) [(takeDirectory p, [(p, k)]) | (p, k) <- Map.toList complete])
