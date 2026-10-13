{- | The workspace of the language server (golem-lsp ADR 0001): the
project evaluated to S1 with unsaved edits taking precedence, files
outside the project parsed and evaluated to S0 only, and selective
re-evaluation.
-}
module Golem.Lsp.Workspace
  ( Workspace (..),
    Source (..),
    openWorkspace,
    updateFile,
    closeFile,
    sourceOf,
    lineIndexOf,
    diagnosticsFor,
    Summary,
    summaryOf,
  )
where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Driver (Evaluated (..), builtinKeepStyles, evaluateProjectWith, keepStyles, paraLineBreaks)
import Golem.Driver.Lint (lintEvaluated)
import Golem.Eval.File
import Golem.Eval.Settings (isSettingCommand)
import Golem.Eval.Value (Value)
import Golem.Lint
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Parser.CST (Node)
import Golem.Parser.SourceSettings
import Golem.Project
import Golem.Project.Style (Style (..), defaultStyle, withLocalStyles)
import Golem.Syntax
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (makeRelative, (</>))

-- | One source file as the features see it.
data Source = Source
  { srcPath :: !FilePath,
    srcFile :: !FileId,
    srcText :: !Text,
    srcCst :: !Node,
    srcAst :: !A.File,
    srcResult :: !(Maybe EvalResult),
    srcInProject :: !Bool
  }

data Workspace = Workspace
  { wsRoot :: !FilePath,
    wsOverlay :: !(Map FilePath Text),
    wsEvaluated :: !(Maybe Evaluated),
    -- | errors that stop the project from loading (bad manifest, import cycle…)
    wsProjectErrors :: ![Diagnostic],
    -- | open files the manifest does not reach
    wsLoose :: !(Map FilePath Source),
    -- | how many times the whole project was evaluated
    wsFullEvaluations :: !Int,
    -- | every .gm file under the root, for @import completion
    wsSourceFiles :: ![FilePath],
    -- | the line index of every known file, for position conversion (ADR 0002)
    wsLines :: !(Map FilePath LineIndex)
  }

{- | What other files depend on: imports, exported variables, headings and
labels.
-}
type Summary = ([Text], Map Text Value, Text)

summaryOf :: A.File -> Maybe EvalResult -> Summary
summaryOf ast res =
  ( [p | Right s <- importsOf ast, let p = isPath s],
    maybe Map.empty erExports res,
    eraseSpans (T.pack (show (structure ast)))
  )
  where
    structure (A.File _ bs) = concatMap blk bs
    blk (A.Located _ b) = case b of
      A.Heading l is -> [show (l, is)]
      -- the file settings change that file alone (docs/adr ADR 0014)
      A.Attributed cs t -> [show c | x@(A.Located _ c) <- cs, not (isSettingCommand x)] <> maybe [] blk t
      A.BlockCommand _ _ body -> concatMap blk body
      A.BulletList items -> concatMap (concatMap blk) items
      A.OrderedList items -> concatMap (concatMap blk) items
      A.DefList gs -> concatMap (concatMap (concatMap blk) . A.dgDefs) gs
      _ -> []
    eraseSpans t = case T.breakOn "SrcSpan {" t of
      (pre, rest)
        | T.null rest -> pre
        | otherwise -> pre <> eraseSpans (T.drop 1 (T.dropWhile (/= '}') rest))

openWorkspace :: FilePath -> IO Workspace
openWorkspace root = do
  files <- listSources root
  fullEvaluate (Workspace root Map.empty Nothing [] Map.empty 0 files Map.empty)

listSources :: FilePath -> IO [FilePath]
listSources root = map (makeRelative root) <$> go root
  where
    go dir = do
      entries <- listDirectory dir
      concat
        <$> mapM
          ( \e -> do
              let p = dir </> e
              isDir <- doesDirectoryExist p
              if isDir
                then if e `elem` ["build", "dist-newstyle", ".git"] then pure [] else go p
                else pure [p | ".gm" `T.isSuffixOf` T.pack e]
          )
          entries

fullEvaluate :: Workspace -> IO Workspace
fullEvaluate ws = do
  r <- evaluateProjectWith (wsOverlay ws) Dev (wsRoot ws)
  let ws' = ws {wsFullEvaluations = wsFullEvaluations ws + 1}
  pure . rebuildLines $ case r of
    Left ds -> refreshLoose ws' {wsEvaluated = Nothing, wsProjectErrors = ds}
    Right e -> refreshLoose ws' {wsEvaluated = Just e, wsProjectErrors = []}

-- | Line indexes of the project's sources and of every edited file.
rebuildLines :: Workspace -> Workspace
rebuildLines ws =
  let projectTexts = case wsEvaluated ws of
        Just e -> Map.fromList [(sfPath sf, sfText sf) | sf <- Map.elems (projectSources (evProject e))]
        Nothing -> Map.empty
   in ws {wsLines = Map.map mkLineIndex (Map.union (wsOverlay ws) projectTexts)}

-- | The line index of a file; an unknown file has the index of empty text.
lineIndexOf :: Workspace -> FilePath -> LineIndex
lineIndexOf ws path = Map.findWithDefault (mkLineIndex "") path (wsLines ws)

projectPaths :: Workspace -> Set.Set FilePath
projectPaths ws = case wsEvaluated ws of
  Just e -> Set.fromList (map sfPath (Map.elems (projectSources (evProject e))))
  Nothing -> Set.empty

-- | Open files outside the project: syntax and S0 only.
refreshLoose :: Workspace -> Workspace
refreshLoose ws =
  ws {wsLoose = Map.fromList [(p, loose p t) | (p, t) <- Map.toList (wsOverlay ws), not (p `Set.member` projectPaths ws)]}

loose :: FilePath -> Text -> Source
loose path text =
  let fid = FileId 0
      (ast, cst, synDiags) = parseAst fid text
      -- a file outside the project knows the built-in styles only (docs/adr ADR 0005)
      ctx = EvalContext fid path Dev Map.empty Map.empty Set.empty (Map.keysSet (stCharStyles defaultStyle)) (paraLineBreaks defaultStyle) "sesame" Set.empty Map.empty noPlugins defaultSourceSettings defaultStyle
      res = evalFile ctx ast
   in Source path fid text cst ast (Just res {erDiagnostics = synDiags <> erDiagnostics res}) False

{- | An edit. The edited file alone is evaluated again; the project is
evaluated again only when its summary changed.
-}
updateFile :: Workspace -> FilePath -> Text -> IO Workspace
updateFile ws0 path text = do
  let ws =
        ws0
          { wsOverlay = Map.insert path text (wsOverlay ws0),
            wsLines = Map.insert path (mkLineIndex text) (wsLines ws0)
          }
  case wsEvaluated ws of
    Just e
      | Just (fid, old) <- findSource e path ->
          let (ast, cst, synDiags) = parseAst fid text
              sf = old {sfText = text, sfCst = cst, sfAst = ast, sfSyntaxDiagnostics = synDiags}
              res = evReevaluate e fid sf
              oldRes = Map.lookup fid (evResults e)
              unchanged =
                summaryOf ast (Just res) == summaryOf (sfAst old) oldRes
                  && not (hasErrors synDiags)
                  && not (hasErrors (sfSyntaxDiagnostics old))
                  && isJust (evBook e)
           in if unchanged
                then pure ws {wsEvaluated = Just (replaceFile e fid sf res)}
                else fullEvaluate ws
    Just _ -> pure (refreshLoose ws)
    Nothing -> fullEvaluate ws

closeFile :: Workspace -> FilePath -> IO Workspace
closeFile ws path = fullEvaluate ws {wsOverlay = Map.delete path (wsOverlay ws)}

findSource :: Evaluated -> FilePath -> Maybe (FileId, SourceFile)
findSource e path = case [(fid, sf) | (fid, sf) <- Map.toList (projectSources (evProject e)), sfPath sf == path] of
  (x : _) -> Just x
  [] -> Nothing

{- | Replaces one file's parse and S0 result. Diagnostics of S0 for that
file are recomputed; S1 diagnostics are kept.
-}
replaceFile :: Evaluated -> FileId -> SourceFile -> EvalResult -> Evaluated
replaceFile e fid sf res =
  let p = evProject e
      oldS0 = maybe [] erDiagnostics (Map.lookup fid (evResults e))
      oldSyn = maybe [] sfSyntaxDiagnostics (Map.lookup fid (projectSources p))
      kept = [d | d <- evDiagnostics e, not (spanFile (diagSpan d) == fid && (d `elem` oldS0 || d `elem` oldSyn))]
   in e
        { evProject = p {projectSources = Map.insert fid sf (projectSources p)},
          evResults = Map.insert fid res (evResults e),
          evDiagnostics = sortDiagnostics (kept <> sfSyntaxDiagnostics sf <> erDiagnostics res)
        }

sourceOf :: Workspace -> FilePath -> Maybe Source
sourceOf ws path = case wsEvaluated ws >>= \e -> fmap (e,) (findSource e path) of
  Just (e, (fid, sf)) -> Just (Source path fid (sfText sf) (sfCst sf) (sfAst sf) (Map.lookup fid (evResults e)) True)
  Nothing -> Map.lookup path (wsLoose ws)

-- | Diagnostics of every known file, with lint in the dev profile.
diagnosticsFor :: Workspace -> Map FilePath [Diagnostic]
diagnosticsFor ws =
  Map.unionWith (<>) projectDiags looseDiags
  where
    -- the styles a loose file defines count for its G0501 (docs/adr ADR 0014)
    looseKeep s = maybe builtinKeepStyles (keepStyles . withLocalStyles defaultStyle . erStyles) (srcResult s)
    -- and its @manifest (docs/adr ADR 0013, 0014)
    looseDiags = Map.map (\s -> sortDiagnostics (maybe [] erDiagnostics (srcResult s) <> latinJoinedByNewline (maybe defaultSourceSettings erSource (srcResult s)) (looseKeep s) (srcFile s) (srcCst s))) (wsLoose ws)
    projectDiags = case wsEvaluated ws of
      Nothing -> Map.fromList [("manifest.toml", wsProjectErrors ws)]
      Just e ->
        let p = evProject e
            ft = projectFiles p
            lintDiags = lintEvaluated e
            all' = map (adjustForProfile Dev) (evDiagnostics e <> lintDiags)
            byFile = Map.fromListWith (flip (<>)) [(fromMaybe "manifest.toml" (lookupPath (spanFile (diagSpan d)) ft), [d]) | d <- all']
            empties = Map.fromList [(sfPath sf, []) | sf <- Map.elems (projectSources p)]
         in Map.map (sortOn (spanStart . diagSpan)) (Map.union byFile empties)
