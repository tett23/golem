{- | Functions written in .emet (docs/adr/0160): loading a program of
modules, calling its functions with the handlers of their requirements
(docs/adr/0161), and formatting a file.
-}
module Golem.Emet
  ( Program,
    SourceProblem (..),
    loadProgram,
    callFunction,
    callFunctionCounted,
    Handlers (..),
    noHandlers,
    fileHandlers,
    Req (..),
    showReq,
    programRequirements,
    Result (..),
    stepLimit,
    depthLimit,
    parseModule,
    readEmet,
    formatEmet,
    programFiles,
  )
where

import Control.Monad (foldM)
import Data.ByteString (ByteString)
import Data.List (intercalate)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet.Builtins (builtinSources, divInfo)
import Golem.Emet.Check
import Golem.Emet.Eval
import Golem.Emet.Fmt (formatEmet)
import Golem.Emet.Parse (parseModule, readEmet)
import Golem.Emet.Path (normalizePath)
import Golem.Emet.Syntax
import Golem.Emet.Types (Req (..), showReq)
import Golem.Syntax

-- | Why a file could not be read: it is missing, or it resolves outside the root.
data SourceProblem = MissingFile | OutsideRoot
  deriving stock (Eq, Show)

-- | The checked modules of a project, ready to call.
data Program = Program
  { prGlobals :: !Globals,
    prFiles :: !(Map FilePath FileId),
    -- | the requirements the signatures write, each at its place (docs/adr/0161)
    prRequirements :: ![(Req, SrcSpan)]
  }

{- | The requirements the signatures of the program write, top-level and
of where, each where it is written, in the order of the files and of the
text: what manifest.toml must allow (E05104, docs/adr/0161).
-}
programRequirements :: Program -> [(Req, SrcSpan)]
programRequirements = prRequirements

-- | The files of the program and their ids, the built-in modules left out.
programFiles :: Program -> Map FilePath FileId
programFiles = prFiles

-- | The built-in modules, checked once.
builtins :: ([Diagnostic], Map Name ModInfo, Globals)
builtins = foldl' step ([], Map.empty, Map.fromList [snd divInfo]) builtinSources
  where
    step (ds, mods, globals) (name, path, src) = case parseModule builtinFile src of
      Left es -> (ds <> es, mods, globals)
      Right m ->
        let scope = Scope [] mods (Map.fromList [("div", fst divInfo)])
            (es, mi, defs) = checkModule True scope builtinFile path src m
         in (ds <> es, Map.insert name mi mods, Map.union globals (Map.fromList defs))
    builtinFile = FileId (-1)

data Loaded = Loaded
  { ldFiles :: !(Map FilePath (FileId, Text, Module)),
    -- | the order to check: imports before their importers
    ldOrder :: ![FilePath],
    ldDiags :: ![Diagnostic],
    ldFailed :: ![FilePath]
  }

{- | Loads the modules of these files (paths from the root of the
project) and those they import, and checks them. @source@ reads a file;
the paths it gets are normalised and inside the root. The program comes
only when there are no errors; notices (E02109) do not keep it.
-}
loadProgram :: (Monad m) => (FilePath -> m (Either SourceProblem (FileId, ByteString))) -> [FilePath] -> m ([Diagnostic], Maybe Program)
loadProgram source roots = do
  loaded <- foldM (flip (visit [] Nothing)) (Loaded Map.empty [] [] []) roots
  let (preludeDiags, builtinMods, preludeGlobals) = builtins
      check (mods, ds, done, failed) path = case Map.lookup path (ldFiles loaded) of
        Nothing -> (mods, ds, done, failed)
        Just (fid, src, m@(Module decls)) ->
          let imports = [(l, target) | DImport _ p l <- decls, Right target <- [normalizePath (T.unpack p)]]
              broken = [p | (_, p) <- imports, p `elem` failed || not (Map.member p mods)]
           in if not (null broken)
                then (mods, ds, done, path : failed)
                else
                  let scope = Scope [(l, imported) | (l, p) <- imports, Just imported <- [Map.lookup p mods]] builtinMods (Map.fromList [("div", fst divInfo)])
                      (es, mi, fdefs) = checkModule False scope fid path src m
                   in (Map.insert path mi mods, ds <> es, done <> fdefs, if any isError es then path : failed else failed)
      (_, checkDiags, defs, _) = foldl' check (Map.empty, [], [], ldFailed loaded) (ldOrder loaded)
      diags = preludeDiags <> ldDiags loaded <> checkDiags
      reqs =
        [ (ReqFile (T.pack p), mkSpan fid (locStart l) (locEnd l))
        | path <- ldOrder loaded,
          Just (fid, _, Module decls) <- [Map.lookup path (ldFiles loaded)],
          sig <- concatMap signatures decls,
          RowE _ qs _ <- rowsOfSig sig,
          ReqE l "file" [raw] <- qs,
          Right p <- [normalizePath (T.unpack raw)]
        ]
      program = Program (Map.union preludeGlobals (Map.fromList defs)) (Map.map (\(f, _, _) -> f) (ldFiles loaded)) reqs
  pure (sortDiagnostics diags, if any isError diags then Nothing else Just program)
  where
    visit stack via path ld
      | Map.member path (ldFiles ld) = pure ld
      | path `elem` ldFailed ld = pure ld
      | otherwise =
          source path >>= \case
            Left problem -> pure ld {ldDiags = ldDiags ld <> [problemDiag via path problem], ldFailed = path : ldFailed ld}
            Right (fid, bytes) -> case readEmet fid bytes >>= \t -> (t,) <$> parseModule fid t of
              Left ds -> pure ld {ldDiags = ldDiags ld <> ds, ldFailed = path : ldFailed ld}
              Right (src, m@(Module decls)) -> do
                let here = Map.insert path (fid, src, m) (ldFiles ld)
                    stack' = path : stack
                ld' <-
                  foldM
                    ( \acc (l, p) -> case normalizePath (T.unpack p) of
                        Left why -> pure acc {ldDiags = ldDiags acc <> [diagnostic "G03003" Error (mkSpan fid (locStart l) (locEnd l)) (why <> ": " <> p)]}
                        Right target
                          | target `elem` stack' ->
                              let cycle' = reverse (takeWhile (/= target) stack') <> [target]
                               in pure acc {ldDiags = ldDiags acc <> [diagnostic "E02103" Error (mkSpan fid (locStart l) (locEnd l)) ("import が循環しています: " <> T.pack (intercalate " → " (target : cycle')))]}
                          | otherwise -> visit stack' (Just (fid, l)) target acc
                    )
                    ld {ldFiles = here}
                    [(l, p) | DImport _ p l <- decls]
                pure ld' {ldOrder = ldOrder ld' <> [path]}
    problemDiag via path problem =
      let sp = maybe (mkSpan (FileId 0) 0 0) (\(f, Loc s e) -> mkSpan f s e) via
       in case problem of
            MissingFile -> diagnostic "G03002" Error sp ("ファイルがありません: " <> T.pack path)
            OutsideRoot -> diagnostic "G03003" Error sp ("プロジェクトルートの外を指しています: " <> T.pack path)

-- | The signatures of a declaration: the top-level one, or those of the where of an equation.
signatures :: Decl -> [Signature]
signatures = \case
  DSig s -> [s]
  DEq q -> [s | Where _ bs <- eqWheres q <> guardWheres (eqRhs q), BSig s <- bs]
  _ -> []
  where
    guardWheres = \case
      Guarded gs -> concatMap snd gs
      Plain _ -> []

-- | The rows of a signature, the one after @::@ first.
rowsOfSig :: Signature -> [RowE]
rowsOfSig sig = maybe id (:) (sigRow sig) (go (sigType sig))
  where
    go = \case
      TFun a r b -> go a <> maybe [] pure r <> go b
      TCon _ _ as -> concatMap go as
      TTuple _ ts -> concatMap go ts
      TVar {} -> []

{- | The handlers of the requirements over the texts of the files by their
paths from the root (docs/adr/0161), which the driver reads when the
project is loaded.
-}
fileHandlers :: Map Text Text -> Handlers
fileHandlers files = Handlers (`Map.lookup` files)

{- | Calls a function of a module of the program with the handlers of the
requirements. @at@ is the span of the call in .gm, where the limits of
steps and depth are reported.
-}
callFunction :: Handlers -> Program -> SrcSpan -> FilePath -> Name -> [Result] -> Either Diagnostic Result
callFunction hs p at path name = evalCall hs (prGlobals p) (prFiles p) at (path, name)

-- | 'callFunction' with the steps the call took (for measuring the work of functions).
callFunctionCounted :: Handlers -> Program -> SrcSpan -> FilePath -> Name -> [Result] -> (Either Diagnostic Result, Int)
callFunctionCounted hs p at path name = evalCallCounted hs (prGlobals p) (prFiles p) at (path, name)
