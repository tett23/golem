{- | Functions written in .gmx (docs/adr/0148): loading a program of
modules, calling its functions, and formatting a file.
-}
module Golem.Gmx
  ( Program,
    SourceProblem (..),
    loadProgram,
    callFunction,
    callFunctionWith,
    callFunctionCounted,
    Handlers (..),
    noHandlers,
    fileHandler,
    programRequirements,
    requirementNames,
    commandName,
    Command (..),
    CommandKind (..),
    programCommands,
    callCommand,
    Result (..),
    stepLimit,
    depthLimit,
    parseModule,
    readGmx,
    formatGmx,
    programFiles,
  )
where

import Control.Monad (foldM)
import Data.ByteString (ByteString)
import Data.List (intercalate, isInfixOf, isPrefixOf)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Doc.IR (Block, Inline)
import Golem.Eval.File (FunctionParam (..))
import Golem.Eval.Value (Value (..))
import Golem.Gmx.Builtins (builtinSources, divInfo)
import Golem.Gmx.Check
import Golem.Gmx.Eval
import Golem.Gmx.Fmt (formatGmx)
import Golem.Gmx.Parse (parseModule, readGmx)
import Golem.Gmx.Syntax
import Golem.Gmx.Types
import Golem.Syntax
import System.FilePath (splitDirectories)

-- | Why a file could not be read: it is missing, or it resolves outside the root.
data SourceProblem = MissingFile | OutsideRoot
  deriving stock (Eq, Show)

-- | The checked modules of a project, ready to call.
data Program = Program
  { prGlobals :: !Globals,
    prFiles :: !(Map FilePath FileId),
    prRequirements :: ![(Text, SrcSpan)],
    -- | the commands of the files given to 'loadProgram' (docs/adr/0150)
    prCommands :: ![Command]
  }

data CommandKind = InlineCommand | BlockCommand
  deriving stock (Eq, Ord, Show)

{- | A function of pub inline or pub block in a file given to 'loadProgram'
(docs/adr/0150): its command, the types of its positional arguments, its
prose slots or whether it takes the body, and where it is declared.
-}
data Command = Command
  { cmdName :: !Text,
    cmdKind :: !CommandKind,
    cmdParams :: ![FunctionParam],
    cmdSlots :: !Int,
    cmdBody :: !Bool,
    cmdPath :: !FilePath,
    cmdFunction :: !Name,
    -- | the name in the signature
    cmdSpan :: !SrcSpan,
    -- | the signature as written, requirements included
    cmdSignature :: !Text
  }

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
        let scope = Scope Map.empty mods (Map.fromList [("div", fst divInfo)])
            (es, mi, defs) = checkModule (Just name) scope builtinFile path src m
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
only when there are no errors.
-}
loadProgram :: (Monad m) => (FilePath -> m (Either SourceProblem (FileId, ByteString))) -> [FilePath] -> m ([Diagnostic], Maybe Program)
loadProgram source roots = do
  loaded <- foldM (flip (visit [] Nothing)) (Loaded Map.empty [] [] []) roots
  let (preludeDiags, builtinMods, preludeGlobals) = builtins
      check (mods, ds, done, failed) path = case Map.lookup path (ldFiles loaded) of
        Nothing -> (mods, ds, done, failed)
        Just (fid, src, m@(Module decls)) ->
          let imports = [(alias, target) | DImport _ p _ alias <- decls, Right target <- [normalize (T.unpack p)]]
              broken = [p | (_, p) <- imports, p `elem` failed || not (Map.member p mods)]
           in if not (null broken)
                then (mods, ds, done, path : failed)
                else
                  let scope = Scope (Map.fromList [(a, imported) | (a, p) <- imports, Just imported <- [Map.lookup p mods]]) builtinMods (Map.fromList [("div", fst divInfo)])
                      (es, mi, fdefs) = checkModule Nothing scope fid path src m
                   in (Map.insert path mi mods, ds <> es, done <> fdefs, if null es then failed else path : failed)
      (modules, checkDiags, defs, _) = foldl' check (Map.empty, [], [], ldFailed loaded) (ldOrder loaded)
      diags = preludeDiags <> ldDiags loaded <> checkDiags
      reqs = [(r, mkSpan fid s e) | path <- ldOrder loaded, Just (fid, _, Module decls) <- [Map.lookup path (ldFiles loaded)], DSig sg <- decls, (r, Loc s e) <- sigReqs sg]
      commands =
        [ Command cname (if k == CmdInline then InlineCommand else BlockCommand) params (if k == CmdInline then length ir else 0) (k == CmdBlock && not (null ir)) path (sigName sg) (mkSpan fid s e) (sigName sg <> " :: " <> showScheme sch)
        | path <- roots,
          Just (fid, _, Module decls) <- [Map.lookup path (ldFiles loaded)],
          Just mi <- [Map.lookup path modules],
          DSig sg <- decls,
          Just k <- [sigKind sg],
          Just cname <- [commandName (sigName sg)],
          Just fi <- [Map.lookup (sigName sg) (miFuns mi)],
          let sch@(Scheme _ t _) = fiScheme fi
              (args, _) = splitAll t
              (values, ir) = break (`elem` [tInlines, tBlocks]) args
              params = mapMaybe paramOf values
              Loc s e = sigNameLoc sg
        ]
      program = Program (Map.union preludeGlobals (Map.fromList defs)) (Map.map (\(f, _, _) -> f) (ldFiles loaded)) reqs commands
  pure (sortDiagnostics diags, if any isError diags then Nothing else Just program)
  where
    visit stack via path ld
      | Map.member path (ldFiles ld) = pure ld
      | path `elem` ldFailed ld = pure ld
      | otherwise =
          source path >>= \case
            Left problem -> pure ld {ldDiags = ldDiags ld <> [problemDiag via path problem], ldFailed = path : ldFailed ld}
            Right (fid, bytes) -> case readGmx fid bytes >>= \t -> (t,) <$> parseModule fid t of
              Left ds -> pure ld {ldDiags = ldDiags ld <> ds, ldFailed = path : ldFailed ld}
              Right (src, m@(Module decls)) -> do
                let here = Map.insert path (fid, src, m) (ldFiles ld)
                    stack' = path : stack
                ld' <-
                  foldM
                    ( \acc (l, p, _) -> case normalize (T.unpack p) of
                        Left why -> pure acc {ldDiags = ldDiags acc <> [diagnostic "G03003" Error (mkSpan fid (locStart l) (locEnd l)) (why <> ": " <> p)]}
                        Right target
                          | target `elem` stack' ->
                              let cycle' = reverse (target : takeWhile (/= target) stack') <> [target]
                               in pure acc {ldDiags = ldDiags acc <> [diagnostic "G10203" Error (mkSpan fid (locStart l) (locEnd l)) ("import が循環しています: " <> T.pack (intercalate " → " (reverse (drop 1 (reverse cycle')) <> [target])))]}
                          | otherwise -> visit stack' (Just (fid, l)) target acc
                    )
                    ld {ldFiles = here}
                    [(l, p, a) | DImport _ p l a <- decls]
                pure ld' {ldOrder = ldOrder ld' <> [path]}
    problemDiag via path problem =
      let sp = maybe (mkSpan (FileId 0) 0 0) (\(f, Loc s e) -> mkSpan f s e) via
       in case problem of
            MissingFile -> diagnostic "G03002" Error sp ("ファイルがありません: " <> T.pack path)
            OutsideRoot -> diagnostic "G03003" Error sp ("プロジェクトルートの外を指しています: " <> T.pack path)

{- | A path of an import, from the root of the project: absolute paths,
URLs and paths that climb out of the root cannot be imported (G03003).
-}
normalize :: FilePath -> Either Text FilePath
normalize p
  | "://" `isInfixOf` p = Left "URL は使えません"
  | "/" `isPrefixOf` p = Left "絶対パスは使えません"
  | otherwise = intercalate "/" . reverse <$> go [] (splitDirectories p)
  where
    go acc [] = Right acc
    go acc ("." : rest) = go acc rest
    go (_ : acc) (".." : rest) = go acc rest
    go [] (".." : _) = Left "プロジェクトルートの外を指しています"
    go acc (seg : rest) = go (seg : acc) rest

-- | The type of an argument as .gm passes it.
paramOf :: Ty -> Maybe FunctionParam
paramOf = \case
  TC "Nat" [] -> Just FPNat
  TC "Int" [] -> Just FPInt
  TC "Rat" [] -> Just FPRat
  TC "String" [] -> Just FPString
  TC "Bool" [] -> Just FPBool
  TC "List" [x] -> FPList <$> paramOf x
  _ -> Nothing

-- | The commands of the program, in the order of the files and of their declarations.
programCommands :: Program -> [Command]
programCommands = prCommands

{- | Calls the function of a command with the values of its positional
arguments and its prose slots (Left) or its body (Right): the inlines
(Left) or the blocks (Right) it returns. @at@ is the call, the position of
what the function makes.
-}
callCommand :: Handlers -> Program -> SrcSpan -> Command -> [Value] -> Either [[Inline]] [Block] -> Either Diagnostic (Either [Inline] [Block])
callCommand hs p at c vals rest =
  let args = map toArg vals <> either (map RInlines) (\bs -> [RBlocks bs | cmdBody c]) rest
   in callFunctionWith hs p at (cmdPath c) (cmdFunction c) args >>= \case
        RInlines xs -> Right (Left xs)
        RBlocks xs -> Right (Right xs)
        _ -> Left (diagnostic "G10601" Error at ("関数のコマンドが Inlines か Blocks を返しませんでした: " <> cmdFunction c))
  where
    toArg = \case
      VArray xs -> RList (map toArg xs)
      v -> RPrim v

{- | Calls a function of a module of the program. @at@ is the span of the
call in .gm, where the limits of steps and depth are reported.
-}
callFunction :: Program -> SrcSpan -> FilePath -> Name -> [Result] -> Either Diagnostic Result
callFunction = callFunctionWith noHandlers

-- | 'callFunction' with the handlers of the requirements (docs/adr/0149).
callFunctionWith :: Handlers -> Program -> SrcSpan -> FilePath -> Name -> [Result] -> Either Diagnostic Result
callFunctionWith hs p at path name = evalCall hs (prGlobals p) (prFiles p) at (path, name)

{- | The handler of @file@ over the bytes of the files of [functions.data]
by their names (docs/adr/0149): a name not there is G10503, bytes that are
no UTF-8 G10504. A BOM at the start is skipped and CRLF becomes LF, as
for the files of @table.
-}
fileHandler :: Map Text ByteString -> Handlers
fileHandler files = Handlers $ \n -> case Map.lookup n decoded of
  Nothing -> Left ("G10503", "[functions.data] にない名前です: " <> n)
  Just Nothing -> Left ("G10504", "File.read で読んだファイルが UTF-8 として読めません: " <> n)
  Just (Just t) -> Right t
  where
    decoded = Map.map decode files
    decode b = case TE.decodeUtf8' b of
      Left _ -> Nothing
      Right t -> Just (T.replace "\r\n" "\n" (fromMaybe t (T.stripPrefix "\xFEFF" t)))

{- | The requirements the signatures of the program write, each at its
name in its signature, for the check against manifest.toml (G10505).
-}
programRequirements :: Program -> [(Text, SrcSpan)]
programRequirements = prRequirements

-- | 'callFunction' with the steps the call took (for measuring the work of functions).
callFunctionCounted :: Program -> SrcSpan -> FilePath -> Name -> [Result] -> (Either Diagnostic Result, Int)
callFunctionCounted p at path name = evalCallCounted noHandlers (prGlobals p) (prFiles p) at (path, name)
