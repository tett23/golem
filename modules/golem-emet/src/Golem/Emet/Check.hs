{- | The check of a module of .emet (docs/adr/0160): the places of @where@
(E01103), names (E021xx), types, the rules of guards (E03102) and the
exhaustiveness of patterns (E03100, E03101). A module that passes becomes
the core form ('Golem.Emet.Core') that the evaluator runs.

Types are checked in two stages kept apart: walking the syntax collects
constraints ('Golem.Emet.Solve.Constraint') and never unifies, and the
solver decides them. The bindings of a @where@ are solved first and
generalised (Hindley-Milner), then the equations, and the defaults come
at the end of the function.

The requirements of docs/adr/0161 are rows on the arrows. The body of a
function with n arguments in its equations has the row of the n-th arrow
of its signature (the row after @::@ for none); applying an arrow, and
naming a function of no arguments, is a call that needs the row of the
arrow to be in the row of the body around it (E05101). @File.read@ takes
a string literal (E05107) and needs @file@ of its path.
-}
module Golem.Emet.Check
  ( ModInfo (..),
    ConInfo (..),
    FunInfo (..),
    TypeDef (..),
    Scope (..),
    checkModule,
    builtinCons,
    builtinModuleNames,
    Export (..),
    ExportArg (..),
    inlineTypeKey,
    blockTypeKey,
    tInlines,
    tBlocks,
    gmName,
  )
where

import Control.Monad (forM, forM_, unless, when, zipWithM)
import Control.Monad.State.Strict
import Data.ByteString qualified as BS
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Either (fromRight, lefts)
import Data.List (find, nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet.Core
import Golem.Emet.Exhaust
import Golem.Emet.Parse (lineOf)
import Golem.Emet.Path (normalizePath)
import Golem.Emet.Solve
import Golem.Emet.Syntax
import Golem.Emet.Types
import Golem.Eval.Expr (overLimit, tooBigDiagnostic)
import Golem.Eval.Functions (ArgType (..))
import Golem.Eval.Value (NumType (..), Value (..), mkNumber, numberOf)
import Golem.Syntax

-- * What a module exports

data TypeDef = TypeDef
  { tdKey :: !Text,
    tdParams :: ![Name],
    tdPub :: !Bool,
    -- | the body of an alias, with 'TG' for the parameters
    tdAlias :: !(Maybe Ty)
  }

data ConInfo = ConInfo
  { ciName :: !Name,
    ciTypeKey :: !Text,
    ciParams :: !Int,
    ciArgs :: ![Ty],
    ciFields :: !(Maybe [Name]),
    -- | the constructors of the type in the order they are declared, with their arities
    ciSiblings :: ![(Name, Int)],
    ciPub :: !Bool
  }

data FunInfo = FunInfo
  { fiKey :: !GKey,
    fiScheme :: !Scheme,
    fiPub :: !Bool
  }

-- | What a module defines, @pub@ or not; an import sees the @pub@ part.
data ModInfo = ModInfo
  { miPath :: !FilePath,
    miTypes :: !(Map Name TypeDef),
    miCons :: !(Map Name ConInfo),
    miFuns :: !(Map Name FunInfo),
    -- | the functions .gm uses, in the order of the file (docs/adr/0162)
    miExports :: ![Export]
  }

{- | A function .gm uses (docs/adr/0162): its kind, the name .gm uses, the
name of the function, the path of its module, what it takes, the type of
its result, where it is declared, and its signature as written (with
its requirements), for the LSP.
-}
data Export = Export
  { exKind :: !Kind,
    exName :: !Text,
    exFunction :: !Name,
    exPath :: !FilePath,
    exArgs :: ![ExportArg],
    exResult :: !Ty,
    exSpan :: !SrcSpan,
    exSignature :: !Text
  }

-- | An argument of a function .gm uses, by what .gm gives it.
data ExportArg
  = ArgPositional !ArgType
  | -- | @Varargs a@: the rest of the positional values
    ArgVarargs !ArgType
  | -- | a keyword argument: its name in .gm, its type and its default
    ArgKeyword !Text !ArgType !Value
  | -- | a prose slot of an inline command
    ArgProse
  | -- | the body of a block command, and the document of a filter
    ArgBody

{- | What a module sees besides itself: its imports in their order, each
with the range of its path; the built-in modules by their names; and the
unqualified built-in functions (@div@).
-}
data Scope = Scope
  { scImports :: ![(Loc, ModInfo)],
    scBuiltins :: !(Map Name ModInfo),
    scGlobals :: !(Map Name FunInfo)
  }

-- | @True@, @False@, @Nothing@ and @Just@.
builtinCons :: Map Name ConInfo
builtinCons =
  Map.fromList
    [ ("True", ConInfo "True" "Bool" 0 [] Nothing boolSigs True),
      ("False", ConInfo "False" "Bool" 0 [] Nothing boolSigs True),
      ("Nothing", ConInfo "Nothing" "Maybe" 1 [] Nothing maybeSigs True),
      ("Just", ConInfo "Just" "Maybe" 1 [TG 0] Nothing maybeSigs True)
    ]
  where
    boolSigs = [("False", 0), ("True", 0)]
    maybeSigs = [("Nothing", 0), ("Just", 1)]

-- | The names of the built-in modules, which no type or constructor of a user may take.
builtinModuleNames :: [Name]
builtinModuleNames = ["List", "String", "File", "Inline", "Block"]

-- | The keys of the data types of the semantic IR (docs/adr/0162).
inlineTypeKey, blockTypeKey :: Text
inlineTypeKey = "<builtin>/Inline.emet#Inline"
blockTypeKey = "<builtin>/Block.emet#Block"

-- | @Inlines@ and @Blocks@: @List Inline@ and @List Block@.
tInlines, tBlocks :: Ty
tInlines = tList (TC inlineTypeKey [])
tBlocks = tList (TC blockTypeKey [])

{- | The names of the types every module sees besides 'builtinTypes', each
the name of another type: @Inlines@, @Blocks@ and @Varargs a@, which is
@List a@ (docs/adr/0162). Their parameters, and the types they name.
-}
namedTypes :: Map Name (Int, Ty)
namedTypes = Map.fromList [("Inlines", (0, tInlines)), ("Blocks", (0, tBlocks)), ("Varargs", (1, tList (TG 0)))]

-- * The names a module sees

-- | Where a name comes from: this file (Nothing), or the path of an import.
type Origin = Maybe FilePath

data Visible = Visible
  { vTypes :: !(Map Name (Origin, TypeDef)),
    vCons :: !(Map Name (Origin, ConInfo)),
    vFuns :: !(Map Name (Origin, FunInfo)),
    -- | the names of the imports that are not pub (E02105)
    vHidden :: !(Set Name)
  }

-- * The context of a check

data Ctx = Ctx
  { cxFile :: !FileId,
    cxPath :: !FilePath,
    cxSource :: !Text,
    cxVis :: !Visible,
    cxScope :: !Scope,
    -- | the function being checked, for the messages of guards
    cxFun :: !Name,
    -- | the binding of where whose body is checked; "" for the equations
    cxUser :: !Name,
    -- | the names of the bindings of the where of the function
    cxWhereNames :: !(Set Name),
    -- | the row of the body being checked, which every call in it needs its requirements in
    cxAmbient :: !Row
  }

-- | A local name: its type and the row naming it makes (a value of where), or its scheme.
data Local = LMono !Row !Ty | LPoly !Scheme

type Locals = Map Name Local

data TcState = TcState
  { tsSolve :: !SolveState,
    -- | the constraints collected and not solved yet, last first
    tsWanted :: ![Constraint],
    -- | the errors of patterns and guards, last first
    tsDiags :: ![Diagnostic],
    -- | which binding of where uses which (the user "" is the equations)
    tsUses :: !(Set (Name, Name)),
    tsSkolems :: !Int,
    -- | the rows of the calls, each with the binding of where it is in ("" for the equations)
    tsCalls :: ![(Name, Row)]
  }

type Tc = StateT TcState (Either Diagnostic)

failAt :: Ctx -> Text -> Loc -> Text -> Tc a
failAt cx code l msg = lift (Left (diagnostic code Error (spanOf cx l) msg))

warnAt :: Ctx -> Text -> Loc -> Text -> Tc ()
warnAt cx code l msg = modify' (\s -> s {tsDiags = diagnostic code Error (spanOf cx l) msg : tsDiags s})

spanOf :: Ctx -> Loc -> SrcSpan
spanOf cx (Loc s e) = mkSpan (cxFile cx) s (max s e)

-- | The first of the errors of a signature stops the check.
failFirst :: Ctx -> [Diagnostic] -> Tc a
failFirst cx = \case
  d : _ -> lift (Left d)
  [] -> failAt cx "E02101" (Loc 0 0) "シグネチャの誤り"

fresh :: Tc Ty
fresh = state (\s -> let (t, ss) = freshMeta (tsSolve s) in (t, s {tsSolve = ss}))

-- | A row of a new variable.
freshR :: Tc Row
freshR = rowVar <$> fresh

emit :: Constraint -> Tc ()
emit c = modify' (\s -> s {tsWanted = c : tsWanted s})

-- | A call at a place: its row must be in the row of the body (docs/adr/0161).
emitCall :: Ctx -> Loc -> Row -> Tc ()
emitCall cx l r
  | r == pureRow = pure ()
  | otherwise = do
      emit (KRow l RCall r (cxAmbient cx))
      modify' (\s -> s {tsCalls = (cxUser cx, r) : tsCalls s})

-- | Solves the constraints collected; a failure is E02101 or E05101.
solveNow :: Ctx -> Bool -> Tc ()
solveNow cx final = do
  st <- get
  case solve final (reverse (tsWanted st)) (tsSolve st) of
    Left (l, code, m) -> failAt cx code l m
    Right ss -> put st {tsSolve = ss, tsWanted = []}

zonkM :: Ty -> Tc Ty
zonkM t = gets (\s -> zonk (tsSolve s) t)

-- * Checking a module

{- | Checks a module and returns its diagnostics, what it defines and its
functions. In a built-in module (@prims@), a signature without equations
is a primitive.
-}
checkModule :: Bool -> Scope -> FileId -> FilePath -> Text -> Module -> ([Diagnostic], ModInfo, [(GKey, Global)])
checkModule prims scope fid path src (Module decls) =
  let vis0 = importedNames scope
      cx0 = Ctx fid path src vis0 scope "" "" Set.empty pureRow
      (typeDiags, types) = collectTypes cx0 decls
      cx1 = withOwn cx0 (ModInfo path types Map.empty Map.empty [])
      (conDiags, cons) = collectCons cx1 decls
      cx2 = withOwn cx0 (ModInfo path types cons Map.empty [])
      (funDiags, funs, groups) = collectFuns prims cx2 decls
      (exportDiags, exports) = checkExports cx2 decls [s | (_, s) <- Map.elems funs]
      own = ModInfo path types cons (Map.map fst funs) exports
      cx3 = withOwn cx0 own
      importDiags = importCollisions cx0 own
      checked = [checkFunction cx3 sig eqs | (sig, eqs@(_ : _)) <- groups]
      prim = [((path, sigName sig), GPrim (T.pack (dropExt path) <> "." <> sigName sig) (arity (sigType sig))) | prims, (sig, []) <- groups]
      bodyDiags = concat (lefts checked) <> concat [ds | Right (ds, _) <- checked]
      defs = [d | Right (_, d) <- checked]
   in (importDiags <> typeDiags <> conDiags <> funDiags <> exportDiags <> bodyDiags, own, prim <> defs)
  where
    arity = \case
      TFun _ _ b -> 1 + arity b
      _ -> 0 :: Int
    -- <builtin>/List.emet -> List
    dropExt p = takeWhile (/= '.') (reverse (takeWhile (/= '/') (reverse p)))

-- | The context with the names of this module over those of the imports.
withOwn :: Ctx -> ModInfo -> Ctx
withOwn cx mi =
  let v = cxVis cx
   in cx
        { cxVis =
            v
              { vTypes = Map.union (Map.map (Nothing,) (miTypes mi)) (vTypes v),
                vCons = Map.union (Map.map (Nothing,) (miCons mi)) (vCons v),
                vFuns = Map.union (Map.map (Nothing,) (miFuns mi)) (vFuns v)
              }
        }

-- | The pub names of the imports, the first import's on a collision (E02108 reports it).
importedNames :: Scope -> Visible
importedNames scope =
  let mods = map snd (scImports scope)
      types = Map.unionsWith const [Map.map (Just (miPath mi),) (Map.filter tdPub (miTypes mi)) | mi <- mods]
      cons = Map.unionsWith const [Map.map (Just (miPath mi),) (Map.filter ciPub (miCons mi)) | mi <- mods]
      funs = Map.unionsWith const [Map.map (Just (miPath mi),) (Map.filter fiPub (miFuns mi)) | mi <- mods]
      hidden =
        Set.unions
          [ Set.fromList (Map.keys (Map.filter (not . tdPub) (miTypes mi)) <> Map.keys (Map.filter (not . ciPub) (miCons mi)) <> Map.keys (Map.filter (not . fiPub) (miFuns mi)))
          | mi <- mods
          ]
   in Visible types cons funs hidden

{- | E02108 for a pub name of an import that another import brought
before, or that this file defines: at the path of the import, whether
the name is used or not (docs/adr/0160).
-}
importCollisions :: Ctx -> ModInfo -> [Diagnostic]
importCollisions cx own = go Map.empty (scImports (cxScope cx))
  where
    go _ [] = []
    go seen ((l, mi) : rest) =
      let names =
            [("型 ", n) | (n, td) <- Map.toList (miTypes mi), tdPub td]
              <> [("コンストラクタ ", n) | (n, ci) <- Map.toList (miCons mi), ciPub ci]
              <> [("関数 ", n) | (n, fi) <- Map.toList (miFuns mi), fiPub fi]
          ownHas (k, n) = case k of
            "型 " -> Map.member n (miTypes own)
            "コンストラクタ " -> Map.member n (miCons own)
            _ -> Map.member n (miFuns own)
          here = T.pack (miPath mi)
          diag = diagnostic "E02108" Error (spanOf cx l)
          clash kn@(k, n)
            | ownHas kn = Just (diag ("取り込んだ" <> k <> n <> " が、このファイルの定義と重なります（" <> here <> " と " <> T.pack (miPath own) <> "）"))
            | Just p <- Map.lookup kn seen = Just (diag ("取り込んだ" <> k <> n <> " が重なります（" <> T.pack p <> " と " <> here <> "）"))
            | otherwise = Nothing
          ds = [d | kn <- names, Just d <- [clash kn]]
          seen' = Map.union seen (Map.fromList [(kn, miPath mi) | kn <- names])
       in ds <> go seen' rest

-- | The second and later of names that occur twice.
duplicates :: [(Name, Loc)] -> [(Name, Loc)]
duplicates = go Set.empty
  where
    go _ [] = []
    go seen ((n, l) : rest)
      | Set.member n seen = (n, l) : go seen rest
      | otherwise = go (Set.insert n seen) rest

-- ** Types

collectTypes :: Ctx -> [Decl] -> ([Diagnostic], Map Name TypeDef)
collectTypes cx decls =
  let entries = [(n, (l, TypeDef (key n) vs pub Nothing, Nothing)) | DData l pub n vs _ <- decls] <> [(n, (l, TypeDef (key n) vs pub Nothing, Just t)) | DType l pub n vs t <- decls]
      dupDiags =
        [diagnostic "E02104" Error (spanOf cx l) ("型 " <> n <> " を二度定義しています") | (n, l) <- duplicates [(n, l) | (n, (l, _, _)) <- entries]]
          <> [diagnostic "E02104" Error (spanOf cx l) ("型 " <> n <> " は組み込みの型と重なります") | (n, (l, _, _)) <- entries, Map.member n builtinTypes || Map.member n namedTypes]
          <> [diagnostic "E02104" Error (spanOf cx l) ("型 " <> n <> " は組み込みのモジュールの名前と重なります") | (n, (l, _, _)) <- entries, n `elem` builtinModuleNames, not (Map.member n builtinTypes), not ("<builtin>/" `T.isPrefixOf` T.pack (cxPath cx))]
      base = Map.fromList [(n, td) | (n, (_, td, _)) <- reverse entries]
      -- aliases resolved in order, each against the others (a cycle is E02101)
      resolveAlias seen n = case Map.lookup n aliasBodies of
        Nothing -> Right Nothing
        Just (l, vs, t)
          | Set.member n seen -> Left (diagnostic "E02101" Error (spanOf cx l) ("型の別名 " <> n <> " が循環しています"))
          | otherwise -> do
              let others = Map.mapWithKey (\k td -> if Map.member k aliasBodies && k /= n then td {tdAlias = fromRight Nothing (resolveAlias (Set.insert n seen) k)} else td) base
                  tcx = withOwn cx (ModInfo (cxPath cx) others Map.empty Map.empty [])
              noRowVars cx t
              Just <$> typeOf tcx (Map.fromList (zip vs [TG i | i <- [0 ..]])) t
      aliasBodies = Map.fromList [(n, (l, tdParams td, t)) | (n, (l, td, Just t)) <- entries]
      resolved = Map.mapWithKey (\n td -> (td, resolveAlias Set.empty n)) base
      aliasDiags = nub [d | (_, Left d) <- Map.elems resolved]
      types = Map.map (\(td, r) -> td {tdAlias = fromRight Nothing r}) resolved
   in (dupDiags <> aliasDiags, types)
  where
    key n = T.pack (cxPath cx) <> "#" <> n

{- | The rows of a type of an alias or a data type: requirements are
checked as those of a signature, and a variable of a row is E02101, as
the parameters of these types are types.
-}
noRowVars :: Ctx -> TypeE -> Either Diagnostic ()
noRowVars cx t = case rowDiagnostics cx Nothing t <> [diagnostic "E02101" Error (spanOf cx l) "型の別名とデータ型には要求の変数を書けません" | VarUse _ l True <- varUses Nothing t] of
  d : _ -> Left d
  [] -> Right ()

-- | A written type in a module, with the variables it may use.
typeOf :: Ctx -> Map Name Ty -> TypeE -> Either Diagnostic Ty
typeOf cx vars = go
  where
    err l msg = Left (diagnostic "E02101" Error (spanOf cx l) msg)
    undef l msg = Left (diagnostic "E02100" Error (spanOf cx l) msg)
    go = \case
      TVar l v -> maybe (undef l ("未定義の型変数 " <> v <> " です")) Right (Map.lookup v vars)
      TFun a r b -> TF <$> go a <*> rowOf cx vars r <*> go b
      TTuple _ ts -> tTuple <$> mapM go ts
      -- a keyword argument is an argument of its type (docs/adr/0162)
      TNamed _ _ inner _ -> go inner
      TCon l q args -> do
        as <- mapM go args
        (k, params, alias) <- lookupType l q
        when (length as /= params) $ err l ("型 " <> qnameText q <> " の引数の数が合いません（" <> T.pack (show params) <> " 個を取ります）")
        pure (maybe (TC k as) (substGen as) alias)
    lookupType l q = case q of
      QName Nothing n
        | Just (_, td) <- Map.lookup n (vTypes (cxVis cx)) -> Right (tdKey td, length (tdParams td), tdAlias td)
        | Just a <- Map.lookup n builtinTypes -> Right (n, a, Nothing)
        | Just (a, t) <- Map.lookup n namedTypes -> Right (n, a, Just t)
        | Set.member n (vHidden (cxVis cx)) -> Left (diagnostic "E02105" Error (spanOf cx l) ("型 " <> n <> " は公開されていません（pub がありません）"))
        | otherwise -> undef l ("未定義の型 " <> n <> " です")
      QName (Just m) n -> case Map.lookup m (scBuiltins (cxScope cx)) of
        Nothing -> undef l ("未定義のモジュール " <> m <> " です")
        Just mi -> case Map.lookup n (miTypes mi) of
          Nothing -> undef l ("未定義の型 " <> qnameText q <> " です")
          Just td
            | not (tdPub td) -> Left (diagnostic "E02105" Error (spanOf cx l) ("型 " <> qnameText q <> " は公開されていません"))
            | otherwise -> Right (tdKey td, length (tdParams td), tdAlias td)

-- ** Rows of requirements (docs/adr/0161)

-- | The kinds of requirements of v1.
requirementKinds :: [Name]
requirementKinds = ["file"]

{- | A written row; the requirements that are not right are left out, as
'rowDiagnostics' reports them.
-}
rowOf :: Ctx -> Map Name Ty -> Maybe RowE -> Either Diagnostic Row
rowOf cx vars = \case
  Nothing -> Right pureRow
  Just (RowE _ reqs v) -> Row (Set.fromList [r | (_, Right r) <- map reqOf reqs]) <$> traverse var v
  where
    var (n, l) = maybe (Left (diagnostic "E02100" Error (spanOf cx l) ("未定義の要求の変数 " <> n <> " です"))) Right (Map.lookup n vars)

-- | A written requirement: the requirement, or what is wrong with it.
reqOf :: ReqE -> (ReqE, Either ReqProblem Req)
reqOf q = (q,) $ case (reqKind q, reqArgs q) of
  ("file", [p]) -> either (Left . BadPath p) (Right . ReqFile . T.pack) (normalizePath (T.unpack p))
  ("file", _) -> Left FileArity
  (k, _) -> Left (UnknownKind k)

data ReqProblem = UnknownKind !Name | FileArity | BadPath !Text !Text

-- | The rows of a type, the one after @::@ first, in the order they are written.
rowsOf :: Maybe RowE -> TypeE -> [RowE]
rowsOf lead t = maybe id (:) lead (go t)
  where
    go = \case
      TFun a r b -> go a <> maybe [] pure r <> go b
      TCon _ _ as -> concatMap go as
      TTuple _ ts -> concatMap go ts
      TNamed _ _ inner _ -> go inner
      TVar {} -> []

{- | The errors of the requirements of a type: E05100 once for all the
kinds not in the list, E02101 for @file@ without one path, G03003 for a
path outside the root, E05102 for a requirement twice in a row, and
G03004 for two paths of a row that differ only in case.
-}
rowDiagnostics :: Ctx -> Maybe RowE -> TypeE -> [Diagnostic]
rowDiagnostics cx lead t =
  let rows = rowsOf lead t
      checked = [map reqOf (rowReqs r) | r <- rows]
      unknown = [(q, k) | qs <- checked, (q, Left (UnknownKind k)) <- qs]
      kindDiag = case unknown of
        (q, _) : _ -> [diagnostic "E05100" Error (spanOf cx (reqLoc q)) ("知らない要求の種類です: " <> T.intercalate "、" (nub (map snd unknown)) <> "（使える種類: " <> T.intercalate "、" requirementKinds <> "）")]
        [] -> []
      problems =
        concat
          [ case e of
              FileArity -> [diagnostic "E02101" Error (spanOf cx (reqLoc q)) "file には読むファイルのパスを一つだけ書きます"]
              BadPath raw why -> [diagnostic "G03003" Error (spanOf cx (reqLoc q)) (why <> ": " <> raw)]
              UnknownKind _ -> []
          | qs <- checked,
            (q, Left e) <- qs
          ]
      repeats = concatMap (inRow Map.empty Map.empty) [[(q, r) | (q, Right r) <- qs] | qs <- checked]
      inRow _ _ [] = []
      inRow seen lower ((q, r@(ReqFile p)) : rest)
        | Map.member r seen = diagnostic "E05102" Error (spanOf cx (reqLoc q)) ("同じ要求を二度書いています: " <> showReq r) : inRow seen lower rest
        | Just other <- Map.lookup (T.toLower p) lower = diagnostic "G03004" Error (spanOf cx (reqLoc q)) ("大文字と小文字だけが異なるパスです: " <> p <> " と " <> other) : inRow seen lower rest
        | otherwise = inRow (Map.insert r () seen) (Map.insert (T.toLower p) p lower) rest
   in kindDiag <> problems <> repeats

-- | A variable of a type or of a row, where it is written.
data VarUse = VarUse !Name !Loc !Bool

-- | The variables of a type in the order they are written, each use with whether it is of a row.
varUses :: Maybe RowE -> TypeE -> [VarUse]
varUses lead t = rowVars lead <> go t
  where
    go = \case
      TVar l v -> [VarUse v l False]
      TFun a r b -> go a <> rowVars r <> go b
      TCon _ _ as -> concatMap go as
      TTuple _ ts -> concatMap go ts
      TNamed _ _ inner _ -> go inner
    rowVars r = [VarUse v l True | Just (RowE _ _ (Just (v, l))) <- [r]]

-- ** Constructors

collectCons :: Ctx -> [Decl] -> ([Diagnostic], Map Name ConInfo)
collectCons cx decls =
  let datas = [(pub, n, vs, cs) | DData _ pub n vs cs <- decls]
      entries =
        [ (cname, cl, mk)
        | (pub, n, vs, cs) <- datas,
          let sibs = [(conName c, length (conTypes c)) | c <- cs],
          c <- cs,
          let cname = conName c
              cl = conLoc c
              vars = Map.fromList (zip vs [TG i | i <- [0 ..]])
              mk = do
                mapM_ (noRowVars cx) (conTypes c)
                args <- mapM (typeOf cx vars) (conTypes c)
                fieldDup c
                pure (ConInfo cname (T.pack (cxPath cx) <> "#" <> n) (length vs) args (conFieldNames c) sibs pub)
        ]
      dupDiags =
        [diagnostic "E02104" Error (spanOf cx l) ("コンストラクタ " <> n <> " を二度定義しています") | (n, l) <- duplicates [(n, l) | (n, l, _) <- entries]]
          <> [diagnostic "E02104" Error (spanOf cx l) ("コンストラクタ " <> n <> " は組み込みのコンストラクタと重なります") | (n, l, _) <- entries, Map.member n builtinCons]
          <> [diagnostic "E02104" Error (spanOf cx l) ("コンストラクタ " <> n <> " は組み込みのモジュールの名前と重なります") | (n, l, _) <- entries, n `elem` builtinModuleNames]
      built = [(n, mk) | (n, _, mk) <- entries]
   in (dupDiags <> nub (lefts (map snd built)), Map.fromList (reverse [(n, ci) | (n, Right ci) <- built]))
  where
    conName = \case
      ConPos _ n _ -> n
      ConRec _ n _ -> n
    conLoc = \case
      ConPos l _ _ -> l
      ConRec l _ _ -> l
    conTypes = \case
      ConPos _ _ ts -> ts
      ConRec _ _ fs -> map snd fs
    conFieldNames = \case
      ConPos {} -> Nothing
      ConRec _ _ fs -> Just (map fst fs)
    fieldDup = \case
      ConRec l n fs | (f : _) <- [f | (f, _) <- duplicates [(f, l) | (f, _) <- fs]] -> Left (diagnostic "E02104" Error (spanOf cx l) ("欄 " <> f <> " を二度定義しています: " <> n))
      _ -> Right ()

-- ** Functions

{- | The signatures and the equations of the top-level functions, grouped:
E02104 for a signature written twice, E02107 for equations apart, E02102
for equations without a signature, E02100 for a signature without
equations (outside the built-in modules, where it is a primitive).
-}
collectFuns :: Bool -> Ctx -> [Decl] -> ([Diagnostic], Map Name (FunInfo, Signature), [(Signature, [Equation])])
collectFuns prims cx decls =
  let sigs = [s | DSig s <- decls]
      dupSigs = duplicates [(sigName s, sigNameLoc s) | s <- sigs]
      builtinClash = [(sigName s, sigNameLoc s) | s <- sigs, Map.member (sigName s) (scGlobals (cxScope cx))]
      runs = runsOf [case d of DEq q -> Just q; _ -> Nothing | d <- decls]
      apart = duplicates [(eqName q, eqNameLoc q) | q : _ <- runs]
      sigMap = Map.fromList (reverse [(sigName s, s) | s <- sigs])
      noSig = [r | r@(q : _) <- runs, not (Map.member (eqName q) sigMap)]
      eqsOf n = concat [r | r@(q : _) <- runs, eqName q == n]
      noEq = [s | not prims, s <- Map.elems sigMap, null (eqsOf (sigName s))]
      infos =
        Map.fromList
          [ (sigName s, (FunInfo (cxPath cx, sigName s) sch (sigPub s), s))
          | s <- Map.elems sigMap,
            Right sch <- [schemeOf cx s]
          ]
      schemeDiags = nub [d | s <- Map.elems sigMap, Left ds <- [schemeOf cx s], d <- ds]
      diags =
        [diagnostic "E02104" Error (spanOf cx l) ("関数 " <> n <> " のシグネチャを二度書いています") | (n, l) <- dupSigs]
          <> [diagnostic "E02104" Error (spanOf cx l) ("関数 " <> n <> " は組み込みの関数と重なります") | (n, l) <- builtinClash]
          <> [diagnostic "E02107" Error (spanOf cx l) ("関数 " <> n <> " の等式が離れています。同じ関数の等式は続けて書きます") | (n, l) <- apart]
          <> [diagnostic "E02102" Error (spanOf cx (eqNameLoc q)) ("最上位の関数 " <> eqName q <> " にシグネチャがありません") | (q : _) <- noSig]
          <> [diagnostic "E02100" Error (spanOf cx (sigNameLoc s)) ("関数 " <> sigName s <> " の等式がありません") | s <- noEq]
          <> schemeDiags
      groups = [(s, eqsOf (sigName s)) | s <- Map.elems sigMap, Map.member (sigName s) infos, sigName s `notElem` map fst apart]
   in (diags, infos, sortOn (locStart . sigLoc . fst) groups)

{- | The equations of each run of one name, in order. A run ends at an
equation of another name or at anything else ('Nothing').
-}
runsOf :: [Maybe Equation] -> [[Equation]]
runsOf = go []
  where
    go acc = \case
      [] -> close acc
      Just q : rest -> case acc of
        (p : _) | eqName p == eqName q -> go (q : acc) rest
        _ -> close acc <> go [q] rest
      Nothing : rest -> close acc <> go [] rest
    close acc = [reverse acc | not (null acc)]

{- | The scheme of a signature: its variables in the order they appear,
those of types and of rows. The errors of its requirements come all; a
variable both of a type and of a row is E02101.
-}
schemeOf :: Ctx -> Signature -> Either [Diagnostic] Scheme
schemeOf cx sig =
  let lead = sigRow sig
      t = sigType sig
      uses = varUses lead t
      vs = nub [v | VarUse v _ _ <- uses]
      clash = [diagnostic "E02101" Error (spanOf cx l) ("変数 " <> v <> " を型の変数と要求の変数の両方に使っています") | VarUse v l True <- uses, any (\(VarUse w _ r) -> w == v && not r) uses]
      vars = Map.fromList (zip vs [TG i | i <- [0 ..]])
   in case rowDiagnostics cx lead t <> take 1 clash of
        [] -> either (Left . pure) Right (Scheme vs <$> rowOf cx vars lead <*> typeOf cx vars t)
        ds -> Left ds

-- | A scheme with its variables made rigid, new ones: the row of naming it and the type.
skolemize :: Scheme -> Tc (Row, Ty)
skolemize (Scheme names r t) = do
  k <- gets tsSkolems
  modify' (\s -> s {tsSkolems = k + length names})
  let vs = [TS (k + i) n | (i, n) <- zip [0 ..] names]
  pure (substRow vs r, substGen vs t)

arityOf :: Ty -> Int
arityOf = \case
  TF _ _ b -> 1 + arityOf b
  _ -> 0

{- | The types of the first n arguments, the row of the body (the n-th
arrow's, or the row of naming it for none) and the type of the result.
-}
splitBody :: Int -> Row -> Ty -> ([Ty], Row, Ty)
splitBody 0 r t = ([], r, t)
splitBody 1 _ (TF a r b) = ([a], r, b)
splitBody n r0 (TF a _ b) = let (as, r, res) = splitBody (n - 1) r0 b in (a : as, r, res)
splitBody _ r t = ([], r, t)

{- | The arrows of n arguments, of no requirement but the n-th, whose row is
given; the row is that of naming it for none.
-}
arrowsWith :: [Ty] -> Row -> Ty -> Ty
arrowsWith as r res = case as of
  [] -> res
  [a] -> TF a r res
  a : rest -> TF a pureRow (arrowsWith rest r res)

{- | E05106: a row written before the arrow of the body of a function of n
arguments (after @::@, or on an arrow before the n-th), or one from an
alias there.
-}
earlyRows :: Ctx -> Int -> Signature -> Row -> Ty -> [Diagnostic]
earlyRows cx n sig lead ty =
  let written = [r | n >= 1, Just r <- [sigRow sig]] <> before 1 (sigType sig)
      before i = \case
        TFun _ r b | i < n -> maybe [] pure r <> before (i + 1 :: Int) b
        _ -> []
      typed = (n >= 1 && lead /= pureRow) || any (/= pureRow) (tyRows (n - 1) ty)
      tyRows k = \case
        TF _ r b | k > 0 -> r : tyRows (k - 1 :: Int) b
        _ -> []
      diag l = diagnostic "E05106" Error (spanOf cx l) ("本体を評価する前の矢印に要求の列があります: " <> sigName sig <> " の本体は " <> T.pack (show n) <> " 個目の矢印で評価します")
   in case written of
        r : _ -> [diag (rowLoc r)]
        []
          | typed -> [diag (typeLoc (sigType sig))]
          | otherwise -> []

{- | E02106: equations with different numbers of arguments, or more than
the arrows of the signature. Fewer return a function.
-}
arityDiag :: Ctx -> Name -> Maybe Int -> [Equation] -> Maybe Diagnostic
arityDiag cx name arrows eqs = case eqs of
  [] -> Nothing
  q : _ ->
    let n = length (eqPats q)
     in case [r | r <- eqs, length (eqPats r) /= n] of
          r : _ -> Just (diagnostic "E02106" Error (spanOf cx (eqNameLoc r)) ("等式どうしで引数の数が違います: " <> name <> " の最初の等式は " <> T.pack (show n) <> " 個の引数を取ります"))
          []
            | Just a <- arrows, n > a -> Just (diagnostic "E02106" Error (spanOf cx (eqNameLoc q)) ("等式の引数がシグネチャの矢印の数より多くあります: " <> name <> " は " <> T.pack (show a) <> " 個までの引数を取ります"))
            | otherwise -> Nothing

{- | Checks one top-level function: the places of @where@, the numbers of
arguments, the types, guards and patterns. One error of names or types
stops the check of the function; the errors of guards and patterns come
all, and the notices of unused bindings (E02109) after them.
-}
checkFunction :: Ctx -> Signature -> [Equation] -> Either [Diagnostic] ([Diagnostic], (GKey, Global))
checkFunction cx0 sig eqs = do
  let bindings = finalWhere eqs
      whereNames = Set.fromList ([eqName q | BEq q <- bindings])
      cx = cx0 {cxFun = sigName sig, cxUser = "", cxWhereNames = whereNames}
  case whereDiags cx eqs of
    [] -> pure ()
    ds -> Left ds
  sch@(Scheme _ lead sigTy) <- schemeOf cx sig
  forM_ (arityDiag cx (sigName sig) (Just (arityOf sigTy)) eqs) (Left . pure)
  let n = maybe 0 (length . eqPats) (safeHead eqs)
  case earlyRows cx n sig lead sigTy of
    [] -> pure ()
    ds -> Left ds
  let run = do
        (refRow, skolem) <- skolemize sch
        let (argTys, bodyRow, resTy) = splitBody n refRow skolem
            cxb = cx {cxAmbient = bodyRow}
        binds <- checkWhereBlock cxb bindings
        ceqs <- checkEquations cxb (whereLocals binds) argTys resTy eqs
        solveNow cx True
        uses <- gets tsUses
        unused <- unusedRequirements cx n sig bodyRow
        pure (ceqs, map (snd . snd) binds, unusedNotices cx bindings uses <> unused)
  case runStateT run (TcState emptySolveState [] [] Set.empty 0 []) of
    Left d -> Left [d]
    Right ((ceqs, binds, notices), st)
      | not (null (tsDiags st)) -> Left (reverse (tsDiags st) <> notices)
      | otherwise ->
          let line = lineOf (cxSource cx) (locStart (sigLoc sig))
           in Right (notices, ((cxPath cx, sigName sig), GFun (CFun (sigName sig) (cxPath cx) line n ceqs binds)))

{- | E05108, an info, for each requirement of the closed row of the body
of a top-level function that no call of its equations needs, at the
requirement as written (docs/adr/0161). A variable of an open row is
never reported.
-}
unusedRequirements :: Ctx -> Int -> Signature -> Row -> Tc [Diagnostic]
unusedRequirements cx n sig (Row declared tl) = case tl of
  Just _ -> pure []
  Nothing -> do
    st <- gets tsSolve
    calls <- gets tsCalls
    let used = Set.unions [rs | ("", r) <- calls, let Row rs _ = zonkRow st r]
        written = [(r, reqLoc q) | rowE <- bodyRowE, (q, Right r) <- map reqOf (rowReqs rowE)]
        at r = fromMaybe (sigLoc sig) (lookup r written)
    pure
      [ diagnostic "E05108" Info (spanOf cx (at r)) ("関数 " <> sigName sig <> " の本体が使わない要求です: " <> showReq r)
      | r <- Set.toList (Set.difference declared used)
      ]
  where
    bodyRowE = case n of
      0 -> maybe [] pure (sigRow sig)
      _ -> nth n (sigType sig)
    nth k = \case
      TFun _ r b
        | k == 1 -> maybe [] pure r
        | otherwise -> nth (k - 1 :: Int) b
      _ -> []

safeHead :: [a] -> Maybe a
safeHead = \case
  x : _ -> Just x
  [] -> Nothing

-- | E02109 for each binding no equation and no other binding uses.
unusedNotices :: Ctx -> [Binding] -> Set (Name, Name) -> [Diagnostic]
unusedNotices cx bindings uses =
  [ notice "E02109" (spanOf cx l) ("使われていない where の束縛です: " <> n)
  | (n, l) <- nubOn fst [(eqName q, eqNameLoc q) | BEq q <- bindings],
    not (any (\(user, used) -> used == n && user /= n) (Set.toList uses))
  ]
  where
    nubOn f = foldr (\x acc -> x : filter ((/= f x) . f) acc) []

-- | The @where@ of a function: after its last equation (or the last guard of it).
finalWhere :: [Equation] -> [Binding]
finalWhere eqs = case reverse eqs of
  q : _ -> case (eqWheres q, eqRhs q) of
    (Where _ bs : _, _) -> bs
    ([], Guarded gs) | (_, Where _ bs : _) : _ <- reverse gs -> bs
    _ -> []
  [] -> []

-- ** The places of where (E01103)

whereDiags :: Ctx -> [Equation] -> [Diagnostic]
whereDiags cx eqs = concatMap perEq (zip [0 ..] eqs)
  where
    lastIx = length eqs - 1
    perEq (i, q) =
      let final = i == lastIx
          gws = case eqRhs q of
            Guarded gs -> [(w, j == length gs - 1) | (j, (_, ws)) <- zip [0 :: Int ..] gs, w <- ws]
            Plain _ -> []
          placed =
            [(w, final && k == 0 && null gws) | (k, w) <- zip [0 :: Int ..] (eqWheres q)]
              <> [(w, final && null (eqWheres q) && isLast && k == 0) | (k, (w, isLast)) <- zip [0 :: Int ..] gws]
       in [misplaced w "where は関数の最後の等式（ガードがあれば最後のガード）の後ろに一つだけ書けます" | (w, False) <- placed]
            <> concat [innerWheres w | (w, True) <- placed]
            <> rhsWheres (eqRhs q)
    misplaced w m = diagnostic "E01103" Error (spanOf cx (whereLoc w)) (m <> ": " <> cxFun cx)
    innerWheres (Where _ bs) = concatMap bindingWheres bs
    bindingWheres = \case
      BSig _ -> []
      BEq q -> map nested (eqWheres q) <> map nested (guardWs (eqRhs q)) <> rhsWheres (eqRhs q)
    nested w = misplaced w "where の中には where を書けません"
    guardWs = \case
      Guarded gs -> concatMap snd gs
      Plain _ -> []
    rhsWheres = \case
      Plain e -> exprWheres e
      Guarded gs -> concat [condWheres (guardCond g) <> exprWheres (guardBody g) | (g, _) <- gs]
    condWheres = \case
      GOtherwise _ -> []
      GExpr e -> exprWheres e
    exprWheres = \case
      ECase _ e as -> exprWheres e <> concatMap altWs as
      EApp f x -> exprWheres f <> exprWheres x
      EBin _ _ a b -> exprWheres a <> exprWheres b
      ENeg _ e -> exprWheres e
      ETernary _ c a b -> exprWheres c <> exprWheres a <> exprWheres b
      EList _ es -> concatMap exprWheres es
      ETuple _ es -> concatMap exprWheres es
      ERecord _ _ fs -> concat [exprWheres e | (_, _, e) <- fs]
      EParen _ e -> exprWheres e
      _ -> []
    altWs a =
      [misplaced w "case の選択肢の後ろには where を書けません" | w <- altWheres a <> guardWs (altRhs a)]
        <> rhsWheres (altRhs a)

-- * Constraints of expressions

numTyOf :: Value -> Ty
numTyOf v = case numberOf v of
  Just (TNat, _) -> tNat
  Just (TInt, _) -> tInt
  _ -> tRat

checkNumber :: Ctx -> Loc -> Value -> Tc ()
checkNumber cx l v = case numberOf v of
  Just (_, q) | overLimit q -> lift (Left (tooBigDiagnostic (spanOf cx l)))
  _ -> pure ()

instantiate :: Scheme -> Tc (Row, Ty)
instantiate (Scheme names r t) = do
  ms <- mapM (const fresh) names
  pure (substRow ms r, substGen ms t)

-- ** Names

resolveVar :: Ctx -> Locals -> Loc -> QName -> Tc (Ty, CExpr)
resolveVar cx locals l q = case q of
  QName (Just "File") "read" -> failAt cx "E05107" l fileReadLiteral
  QName Nothing n
    | Just loc <- Map.lookup n locals -> do
        when (Set.member n (cxWhereNames cx)) $ modify' (\s -> s {tsUses = Set.insert (cxUser cx, n) (tsUses s)})
        (,CLocal n) <$> localTy loc
    | Just (_, fi) <- Map.lookup n (vFuns (cxVis cx)) -> global fi
    | Just fi <- Map.lookup n (scGlobals (cxScope cx)) -> global fi
    | Set.member n (vHidden (cxVis cx)) -> failAt cx "E02105" l (n <> " は公開されていません（取り込んだファイルで pub がありません）")
    | otherwise -> failAt cx "E02100" l ("未定義の名前 " <> n <> " です")
  QName (Just m) n -> case Map.lookup m (scBuiltins (cxScope cx)) of
    Nothing -> failAt cx "E02100" l ("未定義のモジュール " <> m <> " です")
    Just mi -> case Map.lookup n (miFuns mi) of
      Nothing -> failAt cx "E02100" l ("未定義の名前 " <> qnameText q <> " です")
      Just fi
        | not (fiPub fi) -> failAt cx "E02105" l (qnameText q <> " は公開されていません")
        | otherwise -> global fi
  where
    -- naming a function of no arguments is a call of it (docs/adr/0161)
    named (r, t) = emitCall cx l r >> pure t
    global fi = (,CGlobal l (fiKey fi)) <$> (instantiate (fiScheme fi) >>= named)
    localTy = \case
      LMono r t -> named (r, t)
      LPoly s -> instantiate s >>= named

fileReadLiteral :: Text
fileReadLiteral = "File.read の引数は文字列のリテラルに限ります。読むファイルは型の検査の時点で決まっていなければなりません"

-- | The key of File.read, which the driver handles (docs/adr/0161).
fileReadKey :: GKey
fileReadKey = ("<builtin>/File.emet", "read")

resolveCon :: Ctx -> Loc -> QName -> Tc ConInfo
resolveCon cx l q = case q of
  QName Nothing n
    | Just (_, ci) <- Map.lookup n (vCons (cxVis cx)) -> pure ci
    | Just ci <- Map.lookup n builtinCons -> pure ci
    | Set.member n (vHidden (cxVis cx)) -> failAt cx "E02105" l ("コンストラクタ " <> n <> " は公開されていません（取り込んだファイルで pub がありません）")
    | otherwise -> failAt cx "E02100" l ("未定義のコンストラクタ " <> n <> " です")
  QName (Just m) n -> case Map.lookup m (scBuiltins (cxScope cx)) of
    Nothing -> failAt cx "E02100" l ("未定義のモジュール " <> m <> " です")
    Just mi -> case Map.lookup n (miCons mi) of
      Nothing -> failAt cx "E02100" l ("未定義のコンストラクタ " <> qnameText q <> " です")
      Just ci
        | not (ciPub ci) -> failAt cx "E02105" l (qnameText q <> " は公開されていません")
        | otherwise -> pure ci

-- | The type of a constructor applied to new variables for the parameters of its type.
conType :: ConInfo -> Tc ([Ty], Ty)
conType ci = do
  ms <- mapM (const fresh) [1 .. ciParams ci]
  pure (map (substGen ms) (ciArgs ci), TC (ciTypeKey ci) ms)

-- ** Expressions

infer :: Ctx -> Locals -> Expr -> Tc (Ty, CExpr)
infer cx locals = \case
  EParen _ e -> infer cx locals e
  ENum l v -> do
    checkNumber cx l v
    pure (numTyOf v, CLit (LValue v))
  EStr _ s -> pure (tString, CLit (LValue (VString s)))
  EChar _ c -> pure (tChar, CLit (LChar c))
  EVar l q -> resolveVar cx locals l q
  ECon l q -> do
    ci <- resolveCon cx l q
    (args, res) <- conType ci
    pure $ case (ciTypeKey ci, ciName ci) of
      ("Bool", b) -> (tBool, CLit (LValue (VBool (b == "True"))))
      _ -> (foldr (`TF` pureRow) res args, CConV (ciName ci) (length args))
  EList _ es -> do
    el <- fresh
    cs <- mapM (\e -> check cx locals e el) es
    pure (tList el, CList cs)
  ETuple _ es -> do
    ts <- mapM (infer cx locals) es
    pure (tTuple (map fst ts), CTuple (map snd ts))
  e@EApp {} -> case spine e of
    (EVar l (QName (Just "File") "read"), a : more) -> case unparen a of
      EStr sl raw -> case normalizePath (T.unpack raw) of
        Left why -> failAt cx "G03003" sl (why <> ": " <> raw)
        Right p -> do
          let path = T.pack p
              read' = CApp (exprLoc e) (CGlobal l fileReadKey) [CLit (LValue (VString path))]
          emitCall cx (exprLoc e) (Row (Set.singleton (ReqFile path)) Nothing)
          (rt, cargs) <- applyArgs cx locals (exprLoc e) tString more
          pure (rt, if null cargs then read' else CApp (exprLoc e) read' cargs)
      _ -> failAt cx "E05107" (exprLoc a) fileReadLiteral
    (f, args) -> do
      (ft, cf) <- infer cx locals f
      case (cf, args) of
        (CGlobal _ ("<builtin>", "div"), [a, b]) -> do
          (ta, ca) <- infer cx locals a
          (tb, cb) <- infer cx locals b
          r <- arithmetic (exprLoc e) "div" ADivInt ta tb
          pure (r, CApp (exprLoc e) cf [ca, cb])
        _ -> do
          (rt, cargs) <- applyArgs cx locals (exprLoc e) ft args
          pure (rt, CApp (exprLoc e) cf cargs)
  EBin l op a b -> do
    (ta, ca) <- infer cx locals a
    (tb, cb) <- infer cx locals b
    t <- case op of
      _ | op `elem` [OpAnd, OpOr] -> do
        emit (KSub (exprLoc a) ta tBool)
        emit (KSub (exprLoc b) tb tBool)
        pure tBool
      _ | op `elem` [OpEq, OpNe, OpLt, OpLe, OpGt, OpGe] -> do
        t <- fresh
        emit (KSub (exprLoc a) ta t)
        emit (KSub (exprLoc b) tb t)
        emit (KPred l (binOpText op) IsOrd t)
        pure tBool
      OpAppend -> do
        t <- fresh
        emit (KSub (exprLoc a) ta t)
        emit (KSub (exprLoc b) tb t)
        emit (KPred l "++" IsConcat t)
        pure t
      OpCons -> do
        el <- fresh
        emit (KSub (exprLoc a) ta el)
        emit (KSub (exprLoc b) tb (tList el))
        pure (tList el)
      _ -> arithmetic l (binOpText op) (arithOf op) ta tb
    pure (t, CBin l op ca cb)
  ENeg l e -> do
    (t, c) <- infer cx locals e
    emit (KPred l "-" IsNum t)
    r <- fresh
    emit (KNeg l t r)
    pure (r, CNeg l c)
  ECase l e alts -> do
    (st, ce) <- infer cx locals e
    r <- fresh
    checked <- mapM (checkAlt cx locals st r) alts
    alternativeChecks cx l [(altLoc a, [x], altRhs a, [altPat a]) | (a, (_, x)) <- zip alts checked]
    pure (r, CCase ce (map fst checked))
  ETernary _ c a b -> do
    cc <- check cx locals c tBool
    r <- fresh
    ca <- check cx locals a r
    cb <- check cx locals b r
    pure (r, CTern cc ca cb)
  ERecord l q fs -> do
    ci <- resolveCon cx l q
    (args, res) <- conType ci
    names <- maybe (failAt cx "E02101" l ("コンストラクタ " <> qnameText q <> " はレコードではありません")) pure (ciFields ci)
    forM_ (duplicates [(f, fl) | (f, fl, _) <- fs]) $ \(f, fl) -> failAt cx "E02104" fl ("欄 " <> f <> " を二度書いています")
    forM_ fs $ \(f, fl, _) -> unless (f `elem` names) (failAt cx "E02100" fl ("欄 " <> f <> " は " <> qnameText q <> " にありません"))
    cs <- forM (zip names args) $ \(f, t) -> case find (\(g, _, _) -> g == f) fs of
      Nothing -> failAt cx "E02101" l ("欄 " <> f <> " がありません")
      Just (_, _, e) -> check cx locals e t
    pure (res, if null cs then CConV (ciName ci) 0 else CApp l (CConV (ciName ci) (length cs)) cs)
  where
    arithmetic l what op ta tb = do
      emit (KPred l what IsNum ta)
      emit (KPred l what IsNum tb)
      r <- fresh
      emit (KArith l op ta tb r)
      pure r
    arithOf = \case
      OpAdd -> AAdd
      OpSub -> ASub
      OpMul -> AMul
      OpDiv -> ADiv
      OpMod -> AMod
      _ -> APow

unparen :: Expr -> Expr
unparen = \case
  EParen _ x -> unparen x
  x -> x

spine :: Expr -> (Expr, [Expr])
spine = go []
  where
    go acc = \case
      EApp f x -> go (x : acc) f
      EParen _ e@EApp {} | null acc -> go acc e
      f -> (f, acc)

{- | The arguments of an application at a place: applying each arrow is a
call of its row (docs/adr/0161).
-}
applyArgs :: Ctx -> Locals -> Loc -> Ty -> [Expr] -> Tc (Ty, [CExpr])
applyArgs _ _ _ ft [] = pure (ft, [])
applyArgs cx locals at ft (a : as) = do
  (p, row, r) <- case ft of
    TF p row r -> pure (p, row, r)
    _ -> do
      p <- fresh
      row <- freshR
      r <- fresh
      emit (KEq (exprLoc a) (TF p row r) ft)
      pure (p, row, r)
  c <- check cx locals a p
  emitCall cx at row
  (t, cs) <- applyArgs cx locals at r as
  pure (t, c : cs)

-- | An expression where a type is expected: a narrower number is accepted.
check :: Ctx -> Locals -> Expr -> Ty -> Tc CExpr
check cx locals e expected = do
  (t, c) <- infer cx locals e
  emit (KSub (exprLoc e) t expected)
  pure c

-- | An alternative of case, against the type of the scrutinee and that of the result.
checkAlt :: Ctx -> Locals -> Ty -> Ty -> Alt -> Tc (CAlt, XPat)
checkAlt cx locals st r a = do
  (binds, cp, xp) <- checkPat cx st (altPat a)
  rhs <- checkRhs cx (Map.union (Map.map (LMono pureRow) binds) locals) r (altRhs a)
  pure (CAlt cp rhs, xp)

checkRhs :: Ctx -> Locals -> Ty -> Rhs -> Tc CRhs
checkRhs cx locals t = \case
  Plain e -> CPlain <$> check cx locals e t
  Guarded gs -> CGuards <$> mapM guard gs
    where
      guard (g, _) = do
        c <- case guardCond g of
          GOtherwise _ -> pure Nothing
          GExpr e -> Just <$> check cx locals e tBool
        (c,) <$> check cx locals (guardBody g) t

-- ** Patterns

checkPat :: Ctx -> Ty -> Pat -> Tc (Map Name Ty, CPat, XPat)
checkPat cx expected = \case
  PVar l n -> do
    when (Set.member n (cxWhereNames cx)) $ failAt cx "E02104" l ("変数 " <> n <> " は where の束縛と同じ名前です")
    pure (Map.singleton n expected, CPVar n, XWild)
  PWild _ -> pure (Map.empty, CPWild, XWild)
  PNum l v -> do
    checkNumber cx l v
    emit (KSub l (numTyOf v) expected)
    pure (Map.empty, CPLit (LValue v), XLit (maybe "_" (T.pack . show . snd) (numberOf v)))
  PStr l s -> do
    emit (KEq l tString expected)
    pure (Map.empty, CPLit (LValue (VString s)), XLit (T.pack (show s)))
  PChar l c -> do
    emit (KEq l tChar expected)
    pure (Map.empty, CPLit (LChar c), XLit (T.pack (show c)))
  PCon l q ps -> do
    ci <- resolveCon cx l q
    (args, res) <- conType ci
    emit (KEq l res expected)
    when (length ps /= length args) $
      failAt cx "E02101" l ("コンストラクタ " <> qnameText q <> " は " <> T.pack (show (length args)) <> " 個の引数を取ります")
    if ciTypeKey ci == "Bool"
      then pure (Map.empty, CPLit (LValue (VBool (ciName ci == "True"))), XCon (conKey ci) [])
      else do
        subs <- zipWithM (checkPat cx) args ps
        binds <- mergeBinds cx l [b | (b, _, _) <- subs]
        pure (binds, CPCon (ciName ci) [c | (_, c, _) <- subs], XCon (conKey ci) [x | (_, _, x) <- subs])
  PList l ps -> do
    el <- fresh
    emit (KEq l (tList el) expected)
    subs <- mapM (checkPat cx el) ps
    binds <- mergeBinds cx l [b | (b, _, _) <- subs]
    pure (binds, CPList [c | (_, c, _) <- subs], foldr (\(_, _, x) r -> XCon "::" [x, r]) (XCon "[]" []) subs)
  PCons l h t -> do
    el <- fresh
    emit (KEq l (tList el) expected)
    (bh, ch, xh) <- checkPat cx el h
    (bt, ct, xt) <- checkPat cx (tList el) t
    binds <- mergeBinds cx l [bh, bt]
    pure (binds, CPCons ch ct, XCon "::" [xh, xt])
  PTuple l ps -> do
    ms <- mapM (const fresh) ps
    emit (KEq l (tTuple ms) expected)
    subs <- zipWithM (checkPat cx) ms ps
    binds <- mergeBinds cx l [b | (b, _, _) <- subs]
    pure (binds, CPTuple [c | (_, c, _) <- subs], XCon (tupleCon (length ps)) [x | (_, _, x) <- subs])
  PRec l q fs -> do
    ci <- resolveCon cx l q
    (args, res) <- conType ci
    emit (KEq l res expected)
    names <- maybe (failAt cx "E02101" l ("コンストラクタ " <> qnameText q <> " はレコードではありません")) pure (ciFields ci)
    forM_ (duplicates [(f, patLoc p) | (f, p) <- fs]) $ \(f, fl) -> failAt cx "E02104" fl ("欄 " <> f <> " を二度書いています")
    forM_ fs $ \(f, p) -> unless (f `elem` names) (failAt cx "E02100" (patLoc p) ("欄 " <> f <> " は " <> qnameText q <> " にありません"))
    subs <- forM (zip names args) $ \(f, t) -> case lookup f fs of
      Nothing -> pure (Map.empty, CPWild, XWild)
      Just p -> checkPat cx t p
    binds <- mergeBinds cx l [b | (b, _, _) <- subs]
    pure (binds, CPCon (ciName ci) [c | (_, c, _) <- subs], XCon (conKey ci) [x | (_, _, x) <- subs])

mergeBinds :: Ctx -> Loc -> [Map Name Ty] -> Tc (Map Name Ty)
mergeBinds cx l = foldM' Map.empty
  where
    foldM' acc = \case
      [] -> pure acc
      m : rest -> case Map.keys (Map.intersection acc m) of
        n : _ -> failAt cx "E02104" l ("変数 " <> n <> " を一つのパターンに二度書いています")
        [] -> foldM' (Map.union acc m) rest

-- | The constructor of the tuples of n items in the rows of patterns: @(,)@ and a comma for each item past the second.
tupleCon :: Int -> Text
tupleCon n = "(,)" <> T.replicate (n - 2) ","

conKey :: ConInfo -> Text
conKey ci = ciTypeKey ci <> "\t" <> ciName ci

-- * Equations and the rules of patterns

checkEquations :: Ctx -> Locals -> [Ty] -> Ty -> [Equation] -> Tc [CEq]
checkEquations cx locals argTys resTy eqs = do
  rows <- forM eqs $ \q -> do
    pats <- zipWithM (checkPat cx) argTys (eqPats q)
    binds <- mergeBinds cx (eqLoc q) [b | (b, _, _) <- pats]
    r <- checkRhs cx (Map.union (Map.map (LMono pureRow) binds) locals) resTy (eqRhs q)
    pure (CEq [c | (_, c, _) <- pats] r, [x | (_, _, x) <- pats])
  let whole = case (eqs, reverse eqs) of
        (q : _, z : _) -> eqLoc q <-> eqLoc z
        _ -> Loc 0 0
  patternRules cx ("等式", "関数 " <> cxFun cx <> " の等式") whole [(eqLoc q, xs, eqRhs q, eqPats q) | (q, (_, xs)) <- zip eqs rows]
  pure (map fst rows)

alternativeChecks :: Ctx -> Loc -> [(Loc, [XPat], Rhs, [Pat])] -> Tc ()
alternativeChecks cx = patternRules cx ("選択肢", "case の選択肢")

{- | E03101 for guards after otherwise and rows never chosen, E03102 for
guards that do not end with otherwise (but before a last row of variables
only), and E03100 when the rows do not cover every value. A function or
case with E03102 is not checked for E03100: the rows without otherwise do
not count, and the missing values would be the same mistake again.
-}
patternRules :: Ctx -> (Text, Text) -> Loc -> [(Loc, [XPat], Rhs, [Pat])] -> Tc ()
patternRules cx (rowWord, whose) whole rows = do
  let sig = signatureOf cx
      n = length rows
      lastCatchAll = case reverse rows of
        (_, _, Plain _, ps) : _ -> all varOrWild ps
        _ -> False
      varOrWild = \case
        PVar {} -> True
        PWild _ -> True
        _ -> False
      isOther = \case
        (Guard _ (GOtherwise _) _, _) -> True
        _ -> False
      counts (_, _, rhs, _) = case rhs of
        Plain _ -> True
        Guarded gs -> any isOther gs
  forM_ rows $ \(_, _, rhs, _) -> case rhs of
    Guarded gs -> case dropWhile (not . isOther) gs of
      _ : (g, _) : _ -> warnAt cx "E03101" (guardLoc g) ("otherwise の後ろのガードは選ばれません: " <> cxFun cx)
      _ -> pure ()
    Plain _ -> pure ()
  let lastGuards =
        [ guardLoc (fst (last gs))
        | (i, (_, _, Guarded gs, _)) <- zip [0 :: Int ..] rows,
          not (any isOther gs),
          not (lastCatchAll && i < n - 1)
        ]
  forM_ lastGuards $ \l -> warnAt cx "E03102" l ("ガードの並びの最後が otherwise ではありません: " <> cxFun cx)
  -- rows never chosen
  forM_ (zip [0 :: Int ..] rows) $ \(i, (l, xs, _, _)) ->
    let before = [ys | r@(_, ys, _, _) <- take i rows, counts r]
     in when (i > 0 && isNothing (useful sig before xs)) $
          warnAt cx "E03101" l ("選ばれない" <> rowWord <> "です: " <> cxFun cx)
  when (null lastGuards) $
    let counted = [xs | r@(_, xs, _, _) <- rows, counts r]
        width = case rows of
          (_, xs, _, _) : _ -> length xs
          [] -> 1
     in case useful sig counted (replicate width XWild) of
          Just w -> warnAt cx "E03100" whole ("網羅していないパターンマッチです。" <> T.unwords (map (showWitness . display) w) <> " に当たる" <> rowWord <> "がありません（" <> whose <> "）")
          Nothing -> pure ()
  where
    display = \case
      XCon c as -> XCon (snd (T.breakOnEnd "\t" c)) (map display as)
      x -> x

signatureOf :: Ctx -> ConSignature
signatureOf cx key
  | key `elem` ["[]", "::"] = Just [("[]", 0), ("::", 2)]
  | Just n <- T.stripPrefix "(,)" key = Just [(key, T.length n + 2)]
  | otherwise = case T.breakOn "\t" key of
      (_, "") -> Nothing
      (tk, _) -> case [ci | ci <- allCons, ciTypeKey ci == tk] of
        ci : _ -> Just [(tk <> "\t" <> c, a) | (c, a) <- ciSiblings ci]
        [] -> Nothing
  where
    allCons =
      map snd (Map.elems (vCons (cxVis cx)))
        <> Map.elems builtinCons
        <> concatMap (Map.elems . miCons) (Map.elems (scBuiltins (cxScope cx)))

-- * where

whereLocals :: [(Name, (Local, CBind))] -> Locals
whereLocals bs = Map.fromList [(n, l) | (n, (l, _)) <- bs]

{- | The bindings of a @where@: a recursive group, inferred together,
solved, and generalised but for the variables that constraints left
pending still hold. A binding with a signature has the type of it.
-}
checkWhereBlock :: Ctx -> [Binding] -> Tc [(Name, (Local, CBind))]
checkWhereBlock cx bs = do
  let sigs = [s | BSig s <- bs]
      runs = runsOf [case b of BEq q -> Just q; BSig _ -> Nothing | b <- bs]
      defs = [(eqName q, eqNameLoc q) | (q : _) <- runs]
  forM_ (duplicates [(sigName s, sigNameLoc s) | s <- sigs]) $ \(n, l) -> failAt cx "E02104" l ("局所の関数 " <> n <> " のシグネチャを二度書いています")
  forM_ (duplicates defs) $ \(n, l) -> failAt cx "E02107" l ("束縛 " <> n <> " の等式が離れています。同じ束縛の等式は続けて書きます")
  forM_ sigs $ \s -> unless (sigName s `elem` map fst defs) (failAt cx "E02100" (sigNameLoc s) ("束縛 " <> sigName s <> " の等式がありません"))
  sigSchemes <- forM sigs $ \s -> either (failFirst cx) (pure . (sigName s,)) (schemeOf cx s)
  let arities = Map.fromList [(eqName q, length (eqPats q)) | q : _ <- runs]
  -- a value of where without a signature: the row of naming it is that of its body
  monos <- forM [n | (n, _) <- defs, n `notElem` map fst sigSchemes] $ \n -> do
    t <- fresh
    r <- if Map.lookup n arities == Just 0 then freshR else pure pureRow
    pure (n, (r, t))
  let locals = Map.fromList ([(n, LPoly sc) | (n, sc) <- sigSchemes] <> [(n, LMono r t) | (n, (r, t)) <- monos])
  checked <- forM runs $ \run -> case run of
    [] -> failAt cx "E01100" (Loc 0 0) "空の束縛"
    q : _ -> do
      let name = eqName q
          sigScheme = lookup name sigSchemes
      forM_ (arityDiag cx name (arityOf . (\(Scheme _ _ t) -> t) <$> sigScheme) run) (lift . Left)
      let arity = length (eqPats q)
      forM_ [s | s <- sigs, sigName s == name] $ \s -> forM_ sigScheme $ \(Scheme _ lead t) -> case earlyRows cx arity s lead t of
        d : _ -> lift (Left d)
        [] -> pure ()
      (argTys, bodyRow, resTy) <- case sigScheme of
        Just sc -> do
          (lead, target) <- skolemize sc
          pure (splitBody arity lead target)
        Nothing -> do
          let (monoRow, target) = fromMaybe (pureRow, tNat) (lookup name monos)
          as <- mapM (const fresh) [1 .. arity]
          r <- fresh
          row <- if arity == 0 then pure monoRow else freshR
          emit (KEq (eqNameLoc q) (arrowsWith as row r) target)
          pure (as, row, r)
      ceqs <- checkEquations cx {cxUser = name, cxFun = name, cxAmbient = bodyRow} locals argTys resTy run
      pure (name, CBind name arity ceqs (lineAt cx (eqNameLoc q)))
  solveNow cx False
  pending <- gets (ssPending . tsSolve)
  held <- Set.fromList . concatMap metasOf <$> mapM zonkM (concatMap constraintTypes pending)
  st <- gets tsSolve
  forM checked $ \(n, cb) -> case lookup n sigSchemes of
    Just sc -> pure (n, (LPoly sc, cb))
    Nothing -> do
      let (r0, t0) = fromMaybe (pureRow, tNat) (lookup n monos)
          r = zonkRow st r0
      t <- zonkM t0
      let free = [i | i <- metasOf t, not (Set.member i held)]
          gen = Map.fromList (zip free [0 ..])
          t' = mapMetas (\i -> maybe (TM i) TG (Map.lookup i gen)) t
      pure (n, (if null free then LMono r t else LPoly (Scheme [T.pack ("t" <> show k) | k <- [1 .. length free]] r t'), cb))
  where
    mapMetas f = \case
      TM i -> f i
      TC c as -> TC c (map (mapMetas f) as)
      TF a r b -> TF (mapMetas f a) (mapRow f r) (mapMetas f b)
      t -> t
    mapRow f (Row rs v) = Row rs (mapMetas f <$> v)

{- | The types a constraint holds; a row as the arrow between two
booleans, so that its variable counts.
-}
constraintTypes :: Constraint -> [Ty]
constraintTypes = \case
  KEq _ a b -> [a, b]
  KSub _ a b -> [a, b]
  KPred _ _ _ t -> [t]
  KArith _ _ a b r -> [a, b, r]
  KNeg _ a r -> [a, r]
  KRow _ _ a b -> [TF tBool a tBool, TF tBool b tBool]

lineAt :: Ctx -> Loc -> Int
lineAt cx l = lineOf (cxSource cx) (locStart l)

-- * The functions .gm uses (docs/adr/0162)

{- | Whether a name is a name of a command of .gm: a lowercase ASCII
letter, then lowercase letters, digits and @-@.
-}
gmName :: Text -> Bool
gmName t = case T.uncons t of
  Just (c, rest) -> isAsciiLower c && T.all (\x -> isAsciiLower x || isDigit x || x == '-') rest
  Nothing -> False

{- | The functions .gm uses and the errors of their declarations (E06100
to E06106), and the keyword and the variable arguments where no function
.gm calls has them: in a signature of no kind or of where, a field of a
data type and an alias (E06103, E06105). One error at most for each
declaration, the first.
-}
checkExports :: Ctx -> [Decl] -> [Signature] -> ([Diagnostic], [Export])
checkExports cx decls sigs =
  let topSigs = sortOn (locStart . sigLoc) sigs
      checked = [(s, exportOf cx s) | s <- topSigs]
      exports = [e | (_, Right (Just e)) <- checked]
      sigDiags = [d | (_, Left d) <- checked]
      dupDiags =
        [ diagnostic "E06106" Error (exSpan e) ("同じ名前の" <> kindNoun (exKind e) <> "を二度出しています: " <> exName e)
        | (i, e) <- zip [0 :: Int ..] exports,
          any (\o -> nameSpace (exKind o) == nameSpace (exKind e) && exName o == exName e) (take i exports)
        ]
      -- the signatures of where, the fields of data types and the aliases
      elsewhere =
        concat
          [ take 1 (misplaced t)
          | d <- decls,
            t <- case d of
              DData _ _ _ _ cs -> concatMap conTypes cs
              DType _ _ _ _ t -> [t]
              DEq q -> [sigType bs | Where _ bsx <- eqWheres q <> guardWs (eqRhs q), BSig bs <- bsx]
              _ -> []
          ]
   in (sigDiags <> dupDiags <> elsewhere, exports)
  where
    nameSpace = \case
      KindInline -> 0 :: Int
      KindBlock -> 1
      KindFilter -> 2
      KindFn -> 3
    conTypes = \case
      ConPos _ _ ts -> ts
      ConRec _ _ fs -> map snd fs
    guardWs = \case
      Guarded gs -> concatMap snd gs
      Plain _ -> []
    misplaced t = [named l | l <- namedLocs t] <> [varargs l | l <- varargsLocs t]
    named l = diagnostic "E06103" Error (spanOf cx l) "キーワード引数は、.gm から呼ぶインラインのコマンドとブロックコマンドの引数にだけ書けます"
    varargs l = diagnostic "E06105" Error (spanOf cx l) "Varargs は、pub inline、pub block、pub fn の引数にだけ書けます"

kindNoun :: Kind -> Text
kindNoun = \case
  KindInline -> "インラインのコマンド"
  KindBlock -> "ブロックコマンド"
  KindFilter -> "フィルタ"
  KindFn -> "式の関数"

-- | The ranges of the keyword arguments of a type, at any depth.
namedLocs :: TypeE -> [Loc]
namedLocs = \case
  TNamed l _ t _ -> l : namedLocs t
  TFun a _ b -> namedLocs a <> namedLocs b
  TCon _ _ as -> concatMap namedLocs as
  TTuple _ ts -> concatMap namedLocs ts
  TVar {} -> []

-- | The ranges of the Varargs of a type, at any depth.
varargsLocs :: TypeE -> [Loc]
varargsLocs = \case
  TCon l (QName Nothing "Varargs") as -> l : concatMap varargsLocs as
  TCon _ _ as -> concatMap varargsLocs as
  TFun a _ b -> varargsLocs a <> varargsLocs b
  TTuple _ ts -> concatMap varargsLocs ts
  TNamed _ _ t _ -> varargsLocs t
  TVar {} -> []

-- | The arguments of a written type: the types before the arrows, and the result.
syntaxArrows :: TypeE -> ([TypeE], TypeE)
syntaxArrows = \case
  TFun a _ b -> let (as, r) = syntaxArrows b in (a : as, r)
  t -> ([], t)

tyArrows :: Ty -> ([Ty], Ty)
tyArrows = \case
  TF a _ b -> let (as, r) = tyArrows b in (a : as, r)
  t -> ([], t)

-- | A type .gm passes and a pub fn returns (docs/adr/0162).
gmType :: Ty -> Maybe ArgType
gmType = \case
  TC "Nat" [] -> Just ArgNat
  TC "Int" [] -> Just ArgInt
  TC "Rat" [] -> Just ArgRat
  TC "String" [] -> Just ArgString
  TC "Bool" [] -> Just ArgBool
  TC "List" [t] -> ArgList <$> gmType t
  _ -> Nothing

-- | An argument as written, with its type.
data Shape
  = SPositional !Loc !Ty
  | SVarargs !Loc !Ty
  | SKeyword !Loc !ArgName !Ty !(Maybe Expr)
  | SProse !Loc
  | SBlocks !Loc

{- | The function .gm uses of a signature, Nothing for one of no kind, or
the first error of its declaration.
-}
exportOf :: Ctx -> Signature -> Either Diagnostic (Maybe Export)
exportOf cx sig = case sigKind sig of
  Nothing -> case (namedLocs (sigType sig), varargsLocs (sigType sig)) of
    (l : _, _) -> Left (diagnostic "E06103" Error (spanOf cx l) ("キーワード引数は、.gm から呼ぶインラインのコマンドとブロックコマンドの引数にだけ書けます: " <> sigName sig))
    (_, l : _) -> Left (diagnostic "E06105" Error (spanOf cx l) ("Varargs は、pub inline、pub block、pub fn の引数にだけ書けます: " <> sigName sig))
    _ -> Right Nothing
  Just (kind, _) -> case schemeOf cx sig of
    -- the errors of the signature are reported by the check of its function
    Left _ -> Right Nothing
    Right (Scheme _ _ ty) -> Just <$> exportWith kind ty
  where
    err code l m = Left (diagnostic code Error (spanOf cx l) m)
    fname = sigName sig
    exportWith kind ty = do
      name <- exportName kind
      let (sArgs, sRes) = syntaxArrows (sigType sig)
          (tArgs, tRes) = tyArrows ty
          -- an alias may hide arrows: then the written arguments are not known
          aligned = length sArgs == length tArgs
          resLoc = if aligned then typeLoc sRes else typeLoc (sigType sig)
          shapes = zipWith shapeOf (if aligned then map Just sArgs else map (const Nothing) tArgs) tArgs
          -- a Varargs nested in another type, or in the result
          nested = if aligned then concatMap nestedVarargs sArgs <> varargsLocs sRes else []
      mapM_ (\l -> err "E06105" l ("Varargs は引数の型にだけ書けます: " <> fname)) (take 1 nested)
      when (kind == KindFilter) $ do
        mapM_ (\l -> err "E06103" l ("フィルタはキーワード引数を持てません: " <> fname)) (take 1 (namedLocs (sigType sig)))
        mapM_ (\l -> err "E06105" l ("フィルタは可変長引数を持てません: " <> fname)) (take 1 (varargsLocs (sigType sig)))
      args <- case kind of
        KindInline -> do
          resultIs kind resLoc tRes tInlines "Inlines"
          ordered kind shapes
        KindBlock -> do
          resultIs kind resLoc tRes tBlocks "Blocks"
          ordered kind shapes
        KindFilter -> case (shapes, tRes == tBlocks) of
          ([SBlocks _], True) -> Right [ArgBody]
          _ -> err "E06101" (typeLoc (sigType sig)) ("pub filter の型は Blocks -> Blocks か、要求の列を付けた Blocks -> <...> Blocks です: " <> fname)
        KindFn -> case gmType tRes of
          Nothing -> err "E06101" resLoc ("pub fn の戻り値は Nat、Int、Rat、String、Bool か、それらの List です: " <> fname <> " :: " <> showTy tRes)
          Just _ -> ordered kind shapes
      pure (Export kind name fname (cxPath cx) args tRes (spanOf cx (sigNameLoc sig)) (sourceText (sigLoc sig)))
    exportName kind = case (kind, sigExport sig) of
      (KindFn, Just (_, l)) -> err "E06100" l ("pub fn は .emet の名前のまま式から呼ぶので、名前の文字列を書けません: " <> fname)
      (KindFn, Nothing) -> Right fname
      (_, Just (n, l))
        | gmName n -> Right n
        | otherwise -> err "E06100" l ("コマンドとフィルタの名前は、英小文字で始まり、英小文字、数字、- だけで書きます: \"" <> n <> "\"")
      (_, Nothing)
        | gmName fname -> Right fname
        | otherwise -> err "E06100" (sigNameLoc sig) ("関数の名前 " <> fname <> " は .gm のコマンドの名前になりません。pub " <> kindWord kind <> " \"" <> suggestion fname <> "\" " <> fname <> " のように、名前を文字列で書きます")
    suggestion n = T.toLower (T.concatMap (\c -> if isAsciiUpper c then T.pack ['-', c] else if c == '_' then "-" else T.singleton c) n)
    resultIs kind l t want wantText
      | t == want = Right ()
      | otherwise = err "E06101" l ("pub " <> kindWord kind <> " の戻り値は " <> wantText <> " です: " <> fname <> " :: " <> showTy t)
    shapeOf written t = case written of
      Just (TNamed l n _ d) -> SKeyword l n t d
      Just a@(TCon l (QName Nothing "Varargs") [_]) -> case t of
        TC "List" [e] -> SVarargs l e
        _ -> SPositional (typeLoc a) t
      Just a
        | t == tInlines -> SProse (typeLoc a)
        | t == tBlocks -> SBlocks (typeLoc a)
        | otherwise -> SPositional (typeLoc a) t
      Nothing
        | t == tInlines -> SProse (sigNameLoc sig)
        | t == tBlocks -> SBlocks (sigNameLoc sig)
        | otherwise -> SPositional (sigNameLoc sig) t
    nestedVarargs = \case
      TCon _ (QName Nothing "Varargs") as -> concatMap varargsLocs as
      t -> varargsLocs t
    -- the stages of the arguments: positional 0, variable 1, keyword 2, prose or body 3
    ordered kind = go (0 :: Int) False
      where
        isCommand = kind `elem` [KindInline, KindBlock]
        go _ _ [] = Right []
        go stage seenVar (sh : rest) = case sh of
          SPositional l t
            | stage == 1 -> err "E06105" l ("可変長引数の後ろに位置引数は置けません: " <> fname)
            | stage == 2 -> err "E06103" l ("キーワード引数は位置引数と可変長引数の後ろに置きます: " <> fname)
            | stage == 3 -> err "E06102" l ("Inlines と Blocks の引数は、ほかの型の引数の後ろに置きます: " <> fname)
            | otherwise -> case gmType t of
                Nothing -> err "E06102" l (notPassable t)
                Just a -> (ArgPositional a :) <$> go 0 seenVar rest
          SVarargs l t
            | seenVar -> err "E06105" l ("可変長引数は一つの関数に一つだけです: " <> fname)
            | stage >= 2 -> err "E06105" l ("可変長引数は位置引数の最後に置きます: " <> fname)
            | otherwise -> case gmType t of
                Nothing -> err "E06102" l (notPassable t)
                Just a -> (ArgVarargs a :) <$> go 1 True rest
          SKeyword l n t d
            | not isCommand -> err "E06103" l ("キーワード引数は、インラインのコマンドとブロックコマンドだけが持てます: " <> fname)
            | stage == 3 -> err "E06103" l ("キーワード引数は散文スロットと本体の前に置きます: " <> fname)
            | not (gmName (argNameText n)) -> err "E06100" (argNameLoc n) ("キーワード引数の名前は、英小文字で始まり、英小文字、数字、- だけで書きます: " <> argNameText n)
            | otherwise -> case (gmType t, d) of
                (Nothing, _) -> err "E06102" l (notPassable t)
                (_, Nothing) -> err "E06103" l ("キーワード引数には既定の値を書きます: " <> argNameText n)
                (Just a, Just e) -> case literalValue a e of
                  Nothing -> err "E06103" (exprLoc e) ("キーワード引数の既定の値は " <> showTy t <> " のリテラルに限ります: " <> argNameText n)
                  Just v -> (ArgKeyword (argNameText n) a v :) <$> go 2 seenVar rest
          SProse l
            | kind /= KindInline -> err "E06102" l ("Inlines を受け取れるのはインラインのコマンドの散文スロットだけです: " <> fname)
            | otherwise -> (ArgProse :) <$> go 3 seenVar rest
          SBlocks l
            | kind /= KindBlock -> err "E06102" l ("Blocks を受け取れるのはブロックコマンドの本体だけです: " <> fname)
            | not (null rest) -> err "E06102" l ("本体の Blocks はブロックコマンドの最後の引数に置きます: " <> fname)
            | otherwise -> pure [ArgBody]
    notPassable t = ".gm から渡せない型の引数です（渡せるのは Nat、Int、Rat、String、Bool とそれらの List）: " <> fname <> " の " <> showTy t
    sourceText (Loc a b) = TE.decodeUtf8Lenient (BS.take (b - a) (BS.drop a (TE.encodeUtf8 (cxSource cx))))

{- | The value of a default of a keyword argument (docs/adr/0162): a
literal of its type, a number widened to it.
-}
literalValue :: ArgType -> Expr -> Maybe Value
literalValue t e = case (t, e) of
  (_, EParen _ x) -> literalValue t x
  (ArgString, EStr _ s) -> Just (VString s)
  (ArgBool, ECon _ (QName Nothing "True")) -> Just (VBool True)
  (ArgBool, ECon _ (QName Nothing "False")) -> Just (VBool False)
  (ArgList a, EList _ xs) -> VArray <$> traverse (literalValue a) xs
  (_, ENum _ v) -> number v
  (_, ENeg _ (ENum _ v)) -> numberOf v >>= \(_, q) -> number (mkNumber TRat (negate q))
  _ -> Nothing
  where
    number v = case (t, numberOf v) of
      (ArgNat, Just (_, q)) | q >= 0 && q == fromInteger (round q) -> Just (VNat (fromInteger (round q)))
      (ArgInt, Just (_, q)) | q == fromInteger (round q) -> Just (VInt (round q))
      (ArgRat, Just (_, q)) -> Just (VRat q)
      _ -> Nothing
