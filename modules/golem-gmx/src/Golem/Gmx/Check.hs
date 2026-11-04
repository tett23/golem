{- | The check of a module of .gmx (docs/adr/0148): the places of @where@
(G10103), names (G102xx), types by Hindley-Milner inference with the
widening of numbers, the rules of guards (G10302) and the exhaustiveness
of patterns (G10300, G10301). A module that passes becomes the core form
('Golem.Gmx.Core') that the evaluator runs.
-}
module Golem.Gmx.Check
  ( ModInfo (..),
    ConInfo (..),
    FunInfo (..),
    TypeDef (..),
    Scope (..),
    checkModule,
    builtinCons,
    requirementNames,
  )
where

import Control.Monad (foldM, forM, forM_, unless, when, zipWithM)
import Control.Monad.State.Strict
import Data.Either (fromRight, lefts, rights)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (find, nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Expr (overLimit, tooBigDiagnostic)
import Golem.Eval.Value (NumType (..), Value (..), numberOf)
import Golem.Gmx.Core
import Golem.Gmx.Exhaust
import Golem.Gmx.Parse (lineOf)
import Golem.Gmx.Syntax
import Golem.Gmx.Types
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
    ciSiblings :: ![(Name, Int)],
    ciPub :: !Bool
  }

data FunInfo = FunInfo
  { fiKey :: !GKey,
    fiScheme :: !Scheme,
    fiPub :: !Bool
  }

data ModInfo = ModInfo
  { miPath :: !FilePath,
    miTypes :: !(Map Name TypeDef),
    miCons :: !(Map Name ConInfo),
    miFuns :: !(Map Name FunInfo)
  }

{- | What a module sees besides itself: its imports by their names, the
built-in modules by theirs, and the unqualified built-in functions
(@div@).
-}
data Scope = Scope
  { scImports :: !(Map Name ModInfo),
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

-- * The context of a check

data Ctx = Ctx
  { cxFile :: !FileId,
    cxPath :: !FilePath,
    cxSource :: !Text,
    cxMod :: !ModInfo,
    cxScope :: !Scope,
    -- | the function being checked, for the messages of guards
    cxFun :: !Name,
    -- | the requirements of the top-level function being checked (docs/adr/0149)
    cxReqs :: ![Name]
  }

data Local = LMono !Ty | LPoly !Scheme

type Locals = Map Name Local

data TcState = TcState
  { tsNext :: !Int,
    tsSubst :: !(IntMap Ty),
    tsNeeds :: !(IntMap Need),
    tsDiags :: ![Diagnostic],
    -- | the requirements the binding being checked uses
    tsUsed :: !(Set.Set Name)
  }

type Tc = StateT TcState (Either Diagnostic)

failAt :: Ctx -> Text -> Loc -> Text -> Tc a
failAt cx code l msg = lift (Left (diagnostic code Error (spanOf cx l) msg))

warnAt :: Ctx -> Text -> Loc -> Text -> Tc ()
warnAt cx code l msg = modify' (\s -> s {tsDiags = diagnostic code Error (spanOf cx l) msg : tsDiags s})

spanOf :: Ctx -> Loc -> SrcSpan
spanOf cx (Loc s e) = mkSpan (cxFile cx) s (max s e)

fresh :: Tc Ty
fresh = state (\s -> (TM (tsNext s), s {tsNext = tsNext s + 1}))

-- * Checking a module

{- | Checks a module and returns its diagnostics, what it exports and its
functions. A built-in module has the prefix of the names of its
primitives: there a signature without equations is a primitive.
-}
checkModule :: Maybe Text -> Scope -> FileId -> FilePath -> Text -> Module -> ([Diagnostic], ModInfo, [(GKey, Global)])
checkModule primPrefix scope fid path src (Module decls) =
  let cx0 = Ctx fid path src (ModInfo path Map.empty Map.empty Map.empty) scope "" []
      importDiags = importChecks cx0 decls
      (typeDiags, types) = collectTypes cx0 decls
      cx1 = cx0 {cxMod = (cxMod cx0) {miTypes = types}}
      (conDiags, cons) = collectCons cx1 decls
      cx2 = cx1 {cxMod = (cxMod cx1) {miCons = cons}}
      prims = isJust primPrefix
      (funDiags, funs, groups) = collectFuns prims cx2 decls
      cx3 = cx2 {cxMod = (cxMod cx2) {miFuns = Map.map fst funs}}
      checked = [checkFunction cx3 sig eqs | (sig, eqs@(_ : _)) <- groups]
      prim = [((path, sigName sig), GPrim (fromMaybe "" primPrefix <> "." <> sigName sig) (arity (sigType sig))) | prims, (sig, []) <- groups]
      bodyDiags = concat (lefts checked)
      defs = rights checked
   in (importDiags <> typeDiags <> conDiags <> funDiags <> bodyDiags, cxMod cx3, prim <> defs)
  where
    arity = \case
      TFun _ b -> 1 + arity b
      _ -> 0 :: Int

importChecks :: Ctx -> [Decl] -> [Diagnostic]
importChecks cx decls =
  let imports = [(a, al) | DImport _ _ al a <- decls]
      dups = duplicates imports
      builtin = [(a, al) | (a, al) <- imports, Map.member a (scBuiltins (cxScope cx))]
   in [diagnostic "G10204" Error (spanOf cx al) ("名前空間 " <> a <> " を二度定義しています") | (a, al) <- dups]
        <> [diagnostic "G10204" Error (spanOf cx al) ("名前空間 " <> a <> " は組み込みのモジュールと重なります") | (a, al) <- builtin]

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
  let entries = [(n, (l, TypeDef (key n) vs pub Nothing, Nothing)) | DData l pub n vs _ <- decls] <> [(n, (l, TypeDef (key n) vs False Nothing, Just t)) | DType l n vs t <- decls]
      dupDiags =
        [diagnostic "G10204" Error (spanOf cx l) ("型 " <> n <> " を二度定義しています") | (n, l) <- duplicates [(n, l) | (n, (l, _, _)) <- entries]]
          <> [diagnostic "G10204" Error (spanOf cx l) ("型 " <> n <> " は組み込みの型と重なります") | (n, (l, _, _)) <- entries, Map.member n builtinTypes]
      base = Map.fromList [(n, td) | (n, (_, td, _)) <- reverse entries]
      -- aliases resolved in order, each against the others (a cycle is G10201)
      resolveAlias seen n = case Map.lookup n aliasBodies of
        Nothing -> Right Nothing
        Just (l, vs, t)
          | Set.member n seen -> Left (diagnostic "G10201" Error (spanOf cx l) ("型の別名 " <> n <> " が循環しています"))
          | otherwise -> do
              let tcx = cx {cxMod = (cxMod cx) {miTypes = Map.mapWithKey (\k td -> if Map.member k aliasBodies && k /= n then td {tdAlias = fromRight Nothing (resolveAlias (Set.insert n seen) k)} else td) base}}
              Just <$> typeOf tcx (Map.fromList (zip vs [TG i | i <- [0 ..]])) t
      aliasBodies = Map.fromList [(n, (l, tdParams td, t)) | (n, (l, td, Just t)) <- entries]
      resolved = Map.mapWithKey (\n td -> (td, resolveAlias Set.empty n)) base
      aliasDiags = nub [d | (_, Left d) <- Map.elems resolved]
      types = Map.map (\(td, r) -> td {tdAlias = fromRight Nothing r}) resolved
   in (dupDiags <> aliasDiags, types)
  where
    key n = T.pack (cxPath cx) <> "#" <> n

-- | A written type in a module, with the variables it may use.
typeOf :: Ctx -> Map Name Ty -> TypeE -> Either Diagnostic Ty
typeOf cx vars = go
  where
    err l msg = Left (diagnostic "G10201" Error (spanOf cx l) msg)
    undef l msg = Left (diagnostic "G10200" Error (spanOf cx l) msg)
    go = \case
      TVar l v -> maybe (undef l ("未定義の型変数 " <> v <> " です")) Right (Map.lookup v vars)
      TFun a b -> TF <$> go a <*> go b
      TCon l q args -> do
        as <- mapM go args
        (k, params, alias) <- lookupType l q
        when (length as /= params) $ err l ("型 " <> qnameText q <> " の引数の数が合いません（" <> T.pack (show params) <> " 個を取ります）")
        pure (maybe (TC k as) (substGen as) alias)
    lookupType l q = case q of
      QName Nothing n
        | Just td <- Map.lookup n (miTypes (cxMod cx)) -> Right (tdKey td, length (tdParams td), tdAlias td)
        | Just a <- Map.lookup n builtinTypes -> Right (n, a, Nothing)
        | otherwise -> undef l ("未定義の型 " <> n <> " です")
      QName (Just m) n -> case namespace cx m of
        Nothing -> undef l ("未定義の名前空間 " <> m <> " です")
        Just mi -> case Map.lookup n (miTypes mi) of
          Nothing -> undef l ("未定義の型 " <> qnameText q <> " です")
          Just td
            | not (tdPub td) -> Left (diagnostic "G10205" Error (spanOf cx l) ("型 " <> qnameText q <> " は公開されていません（pub がありません）"))
            | otherwise -> Right (tdKey td, length (tdParams td), tdAlias td)

-- | A namespace: an import, or a built-in module.
namespace :: Ctx -> Name -> Maybe ModInfo
namespace cx m = case Map.lookup m (scImports (cxScope cx)) of
  Just mi -> Just mi
  Nothing -> Map.lookup m (scBuiltins (cxScope cx))

-- ** Constructors

collectCons :: Ctx -> [Decl] -> ([Diagnostic], Map Name ConInfo)
collectCons cx decls =
  let datas = [(pub, n, vs, cs) | DData _ pub n vs cs <- decls]
      entries =
        [ (cname, cl, mk)
        | (pub, n, vs, cs) <- datas,
          let sibs = [(conName c, conArity c) | c <- cs],
          c <- cs,
          let cname = conName c
              cl = conLoc c
              vars = Map.fromList (zip vs [TG i | i <- [0 ..]])
              mk = do
                args <- mapM (typeOf cx vars) (conTypes c)
                pure (ConInfo cname (T.pack (cxPath cx) <> "#" <> n) (length vs) args (conFieldNames c) sibs pub)
        ]
      dupDiags =
        [diagnostic "G10204" Error (spanOf cx l) ("コンストラクタ " <> n <> " を二度定義しています") | (n, l) <- duplicates [(n, l) | (n, l, _) <- entries]]
          <> [diagnostic "G10204" Error (spanOf cx l) ("コンストラクタ " <> n <> " は組み込みのコンストラクタと重なります") | (n, l, _) <- entries, Map.member n builtinCons]
      built = [(n, mk) | (n, _, mk) <- entries]
   in (dupDiags <> nub (lefts (map snd built)), Map.fromList (reverse [(n, ci) | (n, Right ci) <- built]))
  where
    conName = \case
      ConPos _ n _ -> n
      ConRec _ n _ -> n
    conLoc = \case
      ConPos l _ _ -> l
      ConRec l _ _ -> l
    conArity = length . conTypes
    conTypes = \case
      ConPos _ _ ts -> ts
      ConRec _ _ fs -> map snd fs
    conFieldNames = \case
      ConPos {} -> Nothing
      ConRec _ _ fs -> Just (map fst fs)

-- ** Functions

{- | The signatures and the equations of the top-level functions, grouped:
G10204 for a signature written twice or equations apart, G10202 for
equations without a signature, G10200 for a signature without equations
(outside the built-in modules, where it is a primitive).
-}
collectFuns :: Bool -> Ctx -> [Decl] -> ([Diagnostic], Map Name (FunInfo, Signature), [(Signature, [Equation])])
collectFuns prims cx decls =
  let sigs = [s | DSig s <- decls]
      dupSigs = duplicates [(sigName s, sigNameLoc s) | s <- sigs]
      builtinClash = [(sigName s, sigNameLoc s) | s <- sigs, Map.member (sigName s) (scGlobals (cxScope cx))]
      runs = runsOf decls
      apart = duplicates [(eqName q, eqNameLoc q) | q : _ <- runs]
      sigMap = Map.fromList (reverse [(sigName s, s) | s <- sigs])
      noSig = [r | r@(q : _) <- runs, not (Map.member (eqName q) sigMap)]
      eqsOf n = concat [r | r@(q : _) <- runs, eqName q == n]
      noEq = [s | not prims, s <- Map.elems sigMap, null (eqsOf (sigName s))]
      infos =
        Map.fromList
          [ (sigName s, (FunInfo (cxPath cx, sigName s) (withReqs sch (knownReqs s)) (sigPub s), s))
          | s <- Map.elems sigMap,
            Right sch <- [schemeOf cx (sigType s)]
          ]
      schemeDiags = nub [d | s <- Map.elems sigMap, Left d <- [schemeOf cx (sigType s)]]
      diags =
        [diagnostic "G10204" Error (spanOf cx l) ("関数 " <> n <> " のシグネチャを二度書いています") | (n, l) <- dupSigs]
          <> [diagnostic "G10204" Error (spanOf cx l) ("関数 " <> n <> " は組み込みの関数と重なります") | (n, l) <- builtinClash]
          <> [diagnostic "G10204" Error (spanOf cx l) ("関数 " <> n <> " の等式が離れています。同じ関数の等式は続けて書きます") | (n, l) <- apart]
          <> [diagnostic "G10202" Error (spanOf cx (eqNameLoc q)) ("最上位の関数 " <> eqName q <> " にシグネチャがありません") | (q : _) <- noSig]
          <> [diagnostic "G10200" Error (spanOf cx (sigNameLoc s)) ("関数 " <> sigName s <> " の等式がありません") | s <- noEq]
          <> schemeDiags
          <> concatMap (requirementDiags cx) sigs
      groups = [(s, eqsOf (sigName s)) | s <- Map.elems sigMap, Map.member (sigName s) infos]
   in (diags, infos, sortOn (locStart . sigLoc . fst) groups)

-- | The requirements a processor has handlers for (docs/adr/0149).
requirementNames :: [Name]
requirementNames = ["file"]

-- | The requirements of a signature that are known, once each.
knownReqs :: Signature -> [Name]
knownReqs s = nub [r | (r, _) <- sigReqs s, r `elem` requirementNames]

withReqs :: Scheme -> [Name] -> Scheme
withReqs (Scheme vs t _) = Scheme vs t

{- | G10500 for the names of a signature that are no requirement, all in
one diagnostic at the first, and G10502 for a name written twice.
-}
requirementDiags :: Ctx -> Signature -> [Diagnostic]
requirementDiags cx s =
  let unknown = [(r, l) | (r, l) <- sigReqs s, r `notElem` requirementNames]
   in [ diagnostic "G10500" Error (spanOf cx l) ("知らない要求です: " <> T.intercalate "、" (nub (map fst unknown)) <> "（使える要求: " <> T.intercalate "、" requirementNames <> "）")
      | (_, l) : _ <- [unknown]
      ]
        <> [diagnostic "G10502" Error (spanOf cx l) ("要求 " <> r <> " を二度書いています: " <> sigName s) | (r, l) <- duplicates (sigReqs s)]

-- | The equations of each run of one name, in order.
runsOf :: [Decl] -> [[Equation]]
runsOf = go []
  where
    go acc = \case
      [] -> close acc
      DEq q : rest -> case acc of
        (p : _) | eqName p == eqName q -> go (q : acc) rest
        _ -> close acc <> go [q] rest
      _ : rest -> close acc <> go [] rest
    close acc = [reverse acc | not (null acc)]

-- | The scheme of a signature: its variables in the order they appear.
schemeOf :: Ctx -> TypeE -> Either Diagnostic Scheme
schemeOf cx t =
  let vs = nub (typeVars t)
   in (\ty -> Scheme vs ty []) <$> typeOf cx (Map.fromList (zip vs [TG i | i <- [0 ..]])) t

typeVars :: TypeE -> [Name]
typeVars = \case
  TVar _ v -> [v]
  TFun a b -> typeVars a <> typeVars b
  TCon _ _ as -> concatMap typeVars as

{- | Checks one top-level function: the places of @where@, the numbers of
arguments, the types, guards and patterns. One error stops the check of
the function; the errors of guards and patterns come all.
-}
checkFunction :: Ctx -> Signature -> [Equation] -> Either [Diagnostic] (GKey, Global)
checkFunction cx0 sig eqs = do
  let cx = cx0 {cxFun = sigName sig, cxReqs = knownReqs sig}
  case whereDiags cx eqs of
    [] -> pure ()
    ds -> Left ds
  sch <- either (Left . pure) Right (schemeOf cx (sigType sig))
  let n = case eqs of
        q : _ -> length (eqPats q)
        [] -> 0
      sigArity = arityOf (schemeTy sch)
  forM_ eqs $ \q ->
    when (length (eqPats q) /= n || n /= sigArity) $
      Left [diagnostic "G10206" Error (spanOf cx (eqNameLoc q)) ("等式の引数の数がシグネチャと合いません: " <> sigName sig <> " は " <> T.pack (show sigArity) <> " 個の引数を取ります")]
  let run = do
        let Scheme names t _ = sch
            skolem = substGen (map TS names) t
            (argTys, resTy) = splitArgs n skolem
        binds <- checkWhereBlock cx (finalWhere eqs)
        ceqs <- checkEquations cx (whereLocals binds) argTys resTy eqs
        pure (ceqs, map (snd . snd) binds)
  case runStateT run (TcState 0 IntMap.empty IntMap.empty [] Set.empty) of
    Left d -> Left [d]
    Right ((ceqs, binds), st)
      | not (null (tsDiags st)) -> Left (reverse (tsDiags st))
      | otherwise ->
          let line = lineOf (cxSource cx) (locStart (sigLoc sig))
           in Right ((cxPath cx, sigName sig), GFun (CFun (sigName sig) (cxPath cx) line n ceqs binds))
  where
    schemeTy (Scheme _ t _) = t

arityOf :: Ty -> Int
arityOf = \case
  TF _ b -> 1 + arityOf b
  _ -> 0

splitArgs :: Int -> Ty -> ([Ty], Ty)
splitArgs 0 t = ([], t)
splitArgs n (TF a b) = let (as, r) = splitArgs (n - 1) b in (a : as, r)
splitArgs _ t = ([], t)

-- | The @where@ of a function: after its last equation (or the last guard of it).
finalWhere :: [Equation] -> [Binding]
finalWhere eqs = case reverse eqs of
  q : _ -> case (eqWheres q, eqRhs q) of
    (Where _ bs : _, _) -> bs
    ([], Guarded gs) | (_, Where _ bs : _) : _ <- reverse gs -> bs
    _ -> []
  [] -> []

-- ** The places of where (G10103)

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
    misplaced w m = diagnostic "G10103" Error (spanOf cx (whereLoc w)) (m <> ": " <> cxFun cx)
    innerWheres (Where _ bs) = concatMap bindingWheres bs
    bindingWheres = \case
      BSig _ -> []
      BLazy _ _ _ e ws -> map nested ws <> exprWheres e
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
      ERecord _ _ fs -> concat [exprWheres e | (_, _, e) <- fs]
      EParen _ e -> exprWheres e
      _ -> []
    altWs a =
      [misplaced w "case の選択肢の後ろには where を書けません" | w <- altWheres a <> guardWs (altRhs a)]
        <> rhsWheres (altRhs a)

-- * Inference

zonk :: Ty -> Tc Ty
zonk = \case
  TM i -> gets (IntMap.lookup i . tsSubst) >>= maybe (pure (TM i)) (\t -> do t' <- zonk t; modify' (\s -> s {tsSubst = IntMap.insert i t' (tsSubst s)}); pure t')
  TC c as -> TC c <$> mapM zonk as
  TF a b -> TF <$> zonk a <*> zonk b
  t -> pure t

instantiate :: Scheme -> Tc Ty
instantiate (Scheme names t _) = do
  ms <- mapM (const fresh) names
  pure (substGen ms t)

needOf :: Int -> Tc (Maybe Need)
needOf i = gets (IntMap.lookup i . tsNeeds)

addNeed :: Int -> Need -> Tc Bool
addNeed i n =
  needOf i >>= \case
    Nothing -> True <$ setNeed n
    Just m
      | m == n -> pure True
      | otherwise -> case (min m n, max m n) of
          (NeedNum, NeedEq) -> True <$ setNeed NeedNum
          (NeedEq, NeedAppend) -> unifyB (TM i) tString
          _ -> pure False
  where
    setNeed k = modify' (\s -> s {tsNeeds = IntMap.insert i k (tsNeeds s)})

satisfies :: Need -> Ty -> Bool
satisfies n t = case (n, t) of
  (NeedNum, TC c []) -> isJust (numRank c)
  (NeedEq, TC c []) -> isJust (numRank c) || c `elem` ["Bool", "String"]
  (NeedAppend, TC "String" []) -> True
  (NeedAppend, TC "List" [_]) -> True
  _ -> False

occurs :: Int -> Ty -> Bool
occurs i = \case
  TM j -> i == j
  TC _ as -> any (occurs i) as
  TF a b -> occurs i a || occurs i b
  _ -> False

-- | Unification; False when the types cannot be the same.
unifyB :: Ty -> Ty -> Tc Bool
unifyB x y = do
  a <- zonk x
  b <- zonk y
  case (a, b) of
    (TM i, TM j) | i == j -> pure True
    (TM i, t) -> bindMeta i t
    (t, TM i) -> bindMeta i t
    (TC c as, TC d bs) | c == d && length as == length bs -> allM (zipWith unifyB as bs)
    (TF a1 b1, TF a2 b2) -> allM [unifyB a1 a2, unifyB b1 b2]
    (TS p, TS q) -> pure (p == q)
    _ -> pure False

allM :: [Tc Bool] -> Tc Bool
allM = foldM (\ok m -> if ok then m else pure False) True

bindMeta :: Int -> Ty -> Tc Bool
bindMeta i t
  | occurs i t = pure False
  | otherwise = do
      need <- needOf i
      case t of
        TM j -> do
          modify' (\s -> s {tsSubst = IntMap.insert i t (tsSubst s)})
          maybe (pure True) (addNeed j) need
        _
          | maybe True (`satisfies` t) need -> True <$ modify' (\s -> s {tsSubst = IntMap.insert i t (tsSubst s)})
          | otherwise -> pure False

-- | Whether a value of the first type is accepted where the second is expected.
subsumeB :: Ty -> Ty -> Tc Bool
subsumeB x y = do
  a <- zonk x
  b <- zonk y
  case (a, b) of
    (TC c [], TC d []) | Just r <- numRank c, Just q <- numRank d -> pure (r <= q)
    (TC "List" [p], TC "List" [q]) -> subsumeB p q
    (TC "Maybe" [p], TC "Maybe" [q]) -> subsumeB p q
    _ -> unifyB a b

subsume :: Ctx -> Loc -> Ty -> Ty -> Tc ()
subsume cx l actual expected = do
  okay <- subsumeB actual expected
  unless okay (mismatch cx l expected actual)

mismatch :: Ctx -> Loc -> Ty -> Ty -> Tc a
mismatch cx l expected actual = do
  e <- zonk expected
  a <- zonk actual
  failAt cx "G10201" l ("型が合いません: " <> showTy e <> " を求める位置に " <> showTy a <> " があります")

-- | The narrowest type of two values of the same place (the branches of case).
joinTy :: Ctx -> Loc -> Ty -> Ty -> Tc Ty
joinTy cx l x y = do
  a <- zonk x
  b <- zonk y
  case (a, b) of
    (TC c [], TC d []) | Just r <- numRank c, Just q <- numRank d -> pure (rankTy (max r q))
    (TC "List" [p], TC "List" [q]) -> tList <$> joinTy cx l p q
    (TC "Maybe" [p], TC "Maybe" [q]) -> tMaybe <$> joinTy cx l p q
    _ -> do
      okay <- unifyB a b
      unless okay (mismatch cx l a b)
      zonk a

-- | The rank of a number type; a variable becomes the given type.
numberRank :: Ctx -> Loc -> Ty -> Tc Int
numberRank cx l t =
  zonk t >>= \case
    TC c [] | Just r <- numRank c -> pure r
    TM i -> do
      okay <- bindMeta i tRat
      unless okay (failAt cx "G10201" l "数を求める位置です")
      pure 2
    other -> failAt cx "G10201" l ("型が合いません: 数を求める位置に " <> showTy other <> " があります")

-- | Two operands of an arithmetic operator: a variable takes the type of the other.
numberPair :: Ctx -> Loc -> Ty -> Ty -> Tc (Int, Int)
numberPair cx l x y = do
  a <- zonk x
  b <- zonk y
  case (a, b) of
    (TM _, TM _) -> (,) <$> numberRank cx l a <*> numberRank cx l b
    (TM i, _) -> do
      r <- numberRank cx l b
      _ <- bindMeta i (rankTy r)
      pure (r, r)
    (_, TM i) -> do
      r <- numberRank cx l a
      _ <- bindMeta i (rankTy r)
      pure (r, r)
    _ -> (,) <$> numberRank cx l a <*> numberRank cx l b

arithTy :: Ctx -> Loc -> BinOp -> Ty -> Ty -> Tc Ty
arithTy cx l op x y = do
  (r, q) <- numberPair cx l x y
  let integral what = when (max r q > 1) (failAt cx "G10201" l (what <> " は整数（Nat、Int）にだけ使えます"))
  rankTy <$> case op of
    OpAdd -> pure (max r q)
    OpMul -> pure (max r q)
    OpSub -> pure (max 1 (max r q))
    OpDiv -> pure 2
    OpMod -> integral "%" >> pure (if q == 0 then 0 else 1)
    OpPow -> do
      when (q > 1) (failAt cx "G10201" l "** の指数は整数（Nat、Int）に限ります")
      pure (if q == 0 then r else 2)
    _ -> pure (max r q)

cmpTy :: Ctx -> Loc -> BinOp -> Ty -> Ty -> Tc ()
cmpTy cx l op x y = do
  a <- zonk x
  b <- zonk y
  case (a, b) of
    (TC c [], TC d []) | isJust (numRank c), isJust (numRank d) -> pure ()
    (TM i, TM _) -> do
      _ <- unifyB a b
      okay <- addNeed i NeedEq
      unless okay bad
    _ -> do
      okay <- unifyB a b
      unless okay (mismatch cx l a b)
      t <- zonk a
      case t of
        TM i -> addNeed i NeedEq >>= \ok' -> unless ok' bad
        _ | satisfies NeedEq t -> pure ()
        _ -> bad
  where
    bad = failAt cx "G10201" l (binOpText op <> " は数、Bool、String にだけ使えます")

appendTy :: Ctx -> Loc -> Ty -> Ty -> Tc Ty
appendTy cx l x y = do
  a <- zonk x
  b <- zonk y
  case (a, b) of
    (TC "List" _, _) -> joinTy cx l a b
    (_, TC "List" _) -> joinTy cx l a b
    (TM i, TM _) -> do
      _ <- unifyB a b
      okay <- addNeed i NeedAppend
      unless okay bad
      zonk a
    _ -> do
      t <- joinTy cx l a b
      case t of
        TC "String" [] -> pure t
        TM i -> addNeed i NeedAppend >>= \ok' -> unless ok' bad >> pure t
        _ -> bad
  where
    bad = failAt cx "G10201" l "++ は String どうしか List どうしにだけ使えます"

numTyOf :: Value -> Ty
numTyOf v = case numberOf v of
  Just (TNat, _) -> tNat
  Just (TInt, _) -> tInt
  _ -> tRat

checkNumber :: Ctx -> Loc -> Value -> Tc ()
checkNumber cx l v = case numberOf v of
  Just (_, q) | overLimit q -> lift (Left (tooBigDiagnostic (spanOf cx l)))
  _ -> pure ()

-- ** Names

{- | A name used in an expression, called (@True@: the head of an
application with all its arguments) or as a value. A function with
requirements may only be called, from a function whose signature has
them (G10501); a function of no arguments is called where it is named.
-}
useVar :: Ctx -> Locals -> Loc -> QName -> Bool -> Tc (Ty, CExpr)
useVar cx locals l q called = do
  (t, c, Scheme _ st reqs) <- resolveVar cx locals l q
  unless (null reqs) $ do
    if called || arityOf st == 0
      then case filter (`notElem` cxReqs cx) reqs of
        [] -> modify' (\s -> s {tsUsed = Set.union (Set.fromList reqs) (tsUsed s)})
        missing -> failAt cx "G10501" l ("シグネチャにない要求を使っています: " <> T.intercalate "、" missing <> "（" <> cxFun cx <> " のシグネチャに => " <> T.intercalate ", " missing <> " を書きます）")
      else failAt cx "G10501" l ("要求を持つ関数は値として渡せません: " <> qnameText q <> "（=> " <> T.intercalate ", " reqs <> "）")
  pure (t, c)

unparen :: Expr -> Expr
unparen = \case
  EParen _ e -> unparen e
  e -> e

resolveVar :: Ctx -> Locals -> Loc -> QName -> Tc (Ty, CExpr, Scheme)
resolveVar cx locals l q = case q of
  QName Nothing n
    | Just loc <- Map.lookup n locals -> (\(t, s) -> (t, CLocal n, s)) <$> localTy loc
    | Just fi <- Map.lookup n (miFuns (cxMod cx)) -> global fi
    | Just fi <- Map.lookup n (scGlobals (cxScope cx)) -> global fi
    | otherwise -> failAt cx "G10200" l ("未定義の名前 " <> n <> " です")
  QName (Just m) n -> case namespace cx m of
    Nothing -> failAt cx "G10200" l ("未定義の名前空間 " <> m <> " です")
    Just mi -> case Map.lookup n (miFuns mi) of
      Nothing -> failAt cx "G10200" l ("未定義の名前 " <> qnameText q <> " です")
      Just fi
        | not (fiPub fi) -> failAt cx "G10205" l (qnameText q <> " は公開されていません（pub がありません）")
        | otherwise -> global fi
  where
    global fi = (,CGlobal l (fiKey fi),fiScheme fi) <$> instantiate (fiScheme fi)
    localTy = \case
      LMono t -> pure (t, monoScheme t)
      LPoly s -> (,s) <$> instantiate s

resolveCon :: Ctx -> Loc -> QName -> Tc ConInfo
resolveCon cx l q = case q of
  QName Nothing n
    | Just ci <- Map.lookup n (miCons (cxMod cx)) -> pure ci
    | Just ci <- Map.lookup n builtinCons -> pure ci
    | otherwise -> failAt cx "G10200" l ("未定義のコンストラクタ " <> n <> " です")
  QName (Just m) n -> case namespace cx m of
    Nothing -> failAt cx "G10200" l ("未定義の名前空間 " <> m <> " です")
    Just mi -> case Map.lookup n (miCons mi) of
      Nothing -> failAt cx "G10200" l ("未定義のコンストラクタ " <> qnameText q <> " です")
      Just ci
        | not (ciPub ci) -> failAt cx "G10205" l (qnameText q <> " は公開されていません（pub がありません）")
        | otherwise -> pure ci

-- | The type of a constructor applied to metas for the parameters of its type.
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
    pure (numTyOf v, CLit v)
  EStr _ s -> pure (tString, CLit (VString s))
  EVar l q -> useVar cx locals l q False
  ECon l q -> do
    ci <- resolveCon cx l q
    (args, res) <- conType ci
    pure $ case (ciTypeKey ci, ciName ci) of
      ("Bool", b) -> (tBool, CLit (VBool (b == "True")))
      _ -> (foldr TF res args, CConV (ciName ci) (length args))
  EList _ es -> do
    ts <- mapM (infer cx locals) es
    el <- case map fst ts of
      [] -> fresh
      t : rest -> foldM (\acc (e, u) -> joinTy cx (exprLoc e) acc u) t (zip (drop 1 es) rest)
    pure (tList el, CList (map snd ts))
  e@EApp {} -> do
    let (f, args) = spine e
    (ft, cf) <- case unparen f of
      EVar l q -> useVar cx locals l q True
      _ -> infer cx locals f
    case (cf, args) of
      (CGlobal _ ("<builtin>", "div"), [a, b]) -> do
        (ta, ca) <- infer cx locals a
        (tb, cb) <- infer cx locals b
        t <- arithTy cx (exprLoc e) OpMod ta tb
        pure (if t == tNat then tNat else tInt, CApp (exprLoc e) cf [ca, cb])
      _ -> do
        (rt, cargs) <- applyArgs cx locals ft args
        pure (rt, CApp (exprLoc e) cf cargs)
  EBin l op a b -> case op of
    _ | op `elem` [OpAnd, OpOr] -> do
      ca <- check cx locals a tBool
      cb <- check cx locals b tBool
      pure (tBool, CBin l op ca cb)
    _ | op `elem` [OpEq, OpNe, OpLt, OpLe, OpGt, OpGe] -> do
      (ta, ca) <- infer cx locals a
      (tb, cb) <- infer cx locals b
      cmpTy cx l op ta tb
      pure (tBool, CBin l op ca cb)
    OpAppend -> do
      (ta, ca) <- infer cx locals a
      (tb, cb) <- infer cx locals b
      t <- appendTy cx l ta tb
      pure (t, CBin l op ca cb)
    _ -> do
      (ta, ca) <- infer cx locals a
      (tb, cb) <- infer cx locals b
      t <- arithTy cx l op ta tb
      pure (t, CBin l op ca cb)
  ENeg l e -> do
    (t, c) <- infer cx locals e
    r <- numberRank cx l t
    pure (rankTy (max 1 r), CNeg l c)
  ECase l e alts -> do
    (st, ce) <- infer cx locals e
    checked <- mapM (checkAlt cx locals st Nothing) alts
    alternativeChecks cx l [(altLoc a, [x], altRhs a, [altPat a]) | (a, (_, _, x, _)) <- zip alts checked]
    rt <- case [(altLoc a, t) | (a, (_, _, _, Just t)) <- zip alts checked] of
      [] -> fresh
      (_, t) : rest -> foldM (\acc (al, u) -> joinTy cx al acc u) t rest
    pure (rt, CCase ce [c | (c, _, _, _) <- checked])
  ETernary _ c a b -> do
    cc <- check cx locals c tBool
    (ta, ca) <- infer cx locals a
    (tb, cb) <- infer cx locals b
    t <- joinTy cx (exprLoc b) ta tb
    pure (t, CTern cc ca cb)
  ERecord l q fs -> do
    ci <- resolveCon cx l q
    (args, res) <- conType ci
    names <- maybe (failAt cx "G10201" l ("コンストラクタ " <> qnameText q <> " はレコードではありません")) pure (ciFields ci)
    forM_ (duplicates [(f, fl) | (f, fl, _) <- fs]) $ \(f, fl) -> failAt cx "G10204" fl ("欄 " <> f <> " を二度書いています")
    forM_ fs $ \(f, fl, _) -> unless (f `elem` names) (failAt cx "G10200" fl ("欄 " <> f <> " は " <> qnameText q <> " にありません"))
    cs <- forM (zip names args) $ \(f, t) -> case find (\(g, _, _) -> g == f) fs of
      Nothing -> failAt cx "G10201" l ("欄 " <> f <> " がありません")
      Just (_, _, e) -> check cx locals e t
    pure (res, if null cs then CConV (ciName ci) 0 else CApp l (CConV (ciName ci) (length cs)) cs)

spine :: Expr -> (Expr, [Expr])
spine = go []
  where
    go acc = \case
      EApp f x -> go (x : acc) f
      EParen _ e@EApp {} | null acc -> go acc e
      f -> (f, acc)

applyArgs :: Ctx -> Locals -> Ty -> [Expr] -> Tc (Ty, [CExpr])
applyArgs _ _ ft [] = pure (ft, [])
applyArgs cx locals ft (a : as) =
  zonk ft >>= \case
    TF p r -> do
      c <- check cx locals a p
      (t, cs) <- applyArgs cx locals r as
      pure (t, c : cs)
    TM i -> do
      p <- fresh
      r <- fresh
      _ <- bindMeta i (TF p r)
      applyArgs cx locals (TF p r) (a : as)
    other -> failAt cx "G10201" (exprLoc a) ("関数でない値（" <> showTy other <> "）に引数を渡しています")

check :: Ctx -> Locals -> Expr -> Ty -> Tc CExpr
check cx locals e expected = case e of
  EParen _ x -> check cx locals x expected
  ETernary _ c a b -> do
    cc <- check cx locals c tBool
    CTern cc <$> check cx locals a expected <*> check cx locals b expected
  ECase l s alts -> do
    (st, cs) <- infer cx locals s
    checked <- mapM (checkAlt cx locals st (Just expected)) alts
    alternativeChecks cx l [(altLoc a, [x], altRhs a, [altPat a]) | (a, (_, _, x, _)) <- zip alts checked]
    pure (CCase cs [c | (c, _, _, _) <- checked])
  EList _ es ->
    zonk expected >>= \case
      TC "List" [el] -> CList <$> mapM (\x -> check cx locals x el) es
      _ -> fallback
  _ -> fallback
  where
    fallback = do
      (t, c) <- infer cx locals e
      subsume cx (exprLoc e) t expected
      pure c

{- | An alternative of case, against the type of the scrutinee: checked
with the expected type of its body, or inferred (its type comes back).
-}
checkAlt :: Ctx -> Locals -> Ty -> Maybe Ty -> Alt -> Tc (CAlt, CPat, XPat, Maybe Ty)
checkAlt cx locals st expected a = do
  (binds, cp, xp) <- checkPat cx st (altPat a)
  let locals' = Map.union (Map.map LMono binds) locals
  case expected of
    Just t -> do
      r <- checkRhs cx locals' t (altRhs a)
      pure (CAlt cp r, cp, xp, Nothing)
    Nothing -> do
      t <- fresh
      r <- inferRhs cx locals' t (altRhs a)
      pure (CAlt cp r, cp, xp, Just t)

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

-- | The bodies of a right-hand side joined into the type of a fresh variable.
inferRhs :: Ctx -> Locals -> Ty -> Rhs -> Tc CRhs
inferRhs cx locals t = \case
  Plain e -> do
    (u, c) <- infer cx locals e
    _ <- unifyB t u
    pure (CPlain c)
  Guarded gs -> do
    parts <- forM gs $ \(g, _) -> do
      c <- case guardCond g of
        GOtherwise _ -> pure Nothing
        GExpr e -> Just <$> check cx locals e tBool
      (u, b) <- infer cx locals (guardBody g)
      pure (c, b, u, exprLoc (guardBody g))
    case parts of
      (_, _, u, _) : rest -> do
        j <- foldM (\acc (_, _, v, l) -> joinTy cx l acc v) u rest
        _ <- unifyB t j
        pure ()
      [] -> pure ()
    pure (CGuards [(c, b) | (c, b, _, _) <- parts])

-- ** Patterns

checkPat :: Ctx -> Ty -> Pat -> Tc (Map Name Ty, CPat, XPat)
checkPat cx expected = \case
  PVar _ n -> pure (Map.singleton n expected, CPVar n, XWild)
  PWild _ -> pure (Map.empty, CPWild, XWild)
  PNum l v -> do
    checkNumber cx l v
    let lt = numTyOf v
    okay <- subsumeB lt expected
    unless okay (mismatch cx l expected lt)
    pure (Map.empty, CPLit v, XLit (litKey v))
  PStr l s -> do
    okay <- unifyB expected tString
    unless okay (mismatch cx l expected tString)
    pure (Map.empty, CPLit (VString s), XLit (T.pack (show s)))
  PCon l q ps -> do
    ci <- resolveCon cx l q
    (args, res) <- conType ci
    okay <- unifyB expected res
    unless okay (mismatch cx l expected res)
    when (length ps /= length args) $
      failAt cx "G10201" l ("コンストラクタ " <> qnameText q <> " は " <> T.pack (show (length args)) <> " 個の引数を取ります")
    if ciTypeKey ci == "Bool"
      then pure (Map.empty, CPLit (VBool (ciName ci == "True")), XCon (conKey ci) [])
      else do
        subs <- zipWithM (checkPat cx) args ps
        binds <- mergeBinds cx l [b | (b, _, _) <- subs]
        pure (binds, CPCon (ciName ci) [c | (_, c, _) <- subs], XCon (conKey ci) [x | (_, _, x) <- subs])
  PList l ps -> do
    el <- fresh
    okay <- unifyB expected (tList el)
    unless okay (mismatch cx l expected (tList el))
    subs <- mapM (checkPat cx el) ps
    binds <- mergeBinds cx l [b | (b, _, _) <- subs]
    pure (binds, CPList [c | (_, c, _) <- subs], foldr (\(_, _, x) r -> XCon "::" [x, r]) (XCon "[]" []) subs)
  PRec l q fs -> do
    ci <- resolveCon cx l q
    (args, res) <- conType ci
    okay <- unifyB expected res
    unless okay (mismatch cx l expected res)
    names <- maybe (failAt cx "G10201" l ("コンストラクタ " <> qnameText q <> " はレコードではありません")) pure (ciFields ci)
    forM_ (duplicates [(f, patLoc p) | (f, p) <- fs]) $ \(f, fl) -> failAt cx "G10204" fl ("欄 " <> f <> " を二度書いています")
    forM_ fs $ \(f, p) -> unless (f `elem` names) (failAt cx "G10200" (patLoc p) ("欄 " <> f <> " は " <> qnameText q <> " にありません"))
    subs <- forM (zip names args) $ \(f, t) -> case lookup f fs of
      Nothing -> pure (Map.empty, CPWild, XWild)
      Just p -> checkPat cx t p
    binds <- mergeBinds cx l [b | (b, _, _) <- subs]
    pure (binds, CPCon (ciName ci) [c | (_, c, _) <- subs], XCon (conKey ci) [x | (_, _, x) <- subs])
  where
    litKey v = maybe "_" (T.pack . show . snd) (numberOf v)

mergeBinds :: Ctx -> Loc -> [Map Name Ty] -> Tc (Map Name Ty)
mergeBinds cx l = foldM add Map.empty
  where
    add acc m = case Map.keys (Map.intersection acc m) of
      n : _ -> failAt cx "G10204" l ("変数 " <> n <> " を一つのパターンに二度書いています")
      [] -> pure (Map.union acc m)

conKey :: ConInfo -> Text
conKey ci = ciTypeKey ci <> "\t" <> ciName ci

-- * Equations, where and the rules of patterns

checkEquations :: Ctx -> Locals -> [Ty] -> Ty -> [Equation] -> Tc [CEq]
checkEquations cx locals argTys resTy eqs = do
  rows <- forM eqs $ \q -> do
    pats <- zipWithM (checkPat cx) argTys (eqPats q)
    binds <- mergeBinds cx (eqLoc q) [b | (b, _, _) <- pats]
    r <- checkRhs cx (Map.union (Map.map LMono binds) locals) resTy (eqRhs q)
    pure (CEq [c | (_, c, _) <- pats] r, [x | (_, _, x) <- pats], eqPats q)
  let whole = case (eqs, reverse eqs) of
        (q : _, z : _) -> eqLoc q <-> eqLoc z
        _ -> Loc 0 0
  equationChecks cx whole [(eqLoc q, xs, eqRhs q, ps) | (q, (_, xs, ps)) <- zip eqs rows]
  pure [c | (c, _, _) <- rows]

-- | The rules of guards and patterns of the equations of a function.
equationChecks :: Ctx -> Loc -> [(Loc, [XPat], Rhs, [Pat])] -> Tc ()
equationChecks cx = patternRules cx ("等式", "関数 " <> cxFun cx <> " の等式")

alternativeChecks :: Ctx -> Loc -> [(Loc, [XPat], Rhs, [Pat])] -> Tc ()
alternativeChecks cx = patternRules cx ("選択肢", "case の選択肢")

{- | G10301 for guards after otherwise and rows never chosen, G10302 for
guards that do not end with otherwise (but before a last row of variables
only), and G10300 when the rows do not cover every value. A function or
case with G10302 is not checked for G10300: the rows without otherwise do
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
      _ : (g, _) : _ -> warnAt cx "G10301" (guardLoc g) ("otherwise の後ろのガードは選ばれません: " <> cxFun cx)
      _ -> pure ()
    Plain _ -> pure ()
  let g10302 =
        [ guardLoc (fst (last gs))
        | (i, (_, _, Guarded gs, _)) <- zip [0 :: Int ..] rows,
          not (any isOther gs),
          not (lastCatchAll && i < n - 1)
        ]
  forM_ g10302 $ \l -> warnAt cx "G10302" l ("ガードの並びの最後が otherwise ではありません: " <> cxFun cx)
  -- rows never chosen
  forM_ (zip [0 :: Int ..] rows) $ \(i, (l, xs, _, _)) ->
    let before = [ys | (_, ys, rhs, ps) <- take i rows, counts (l, ys, rhs, ps)]
     in when (i > 0 && isNothing (useful sig before xs)) $
          warnAt cx "G10301" l ("選ばれない" <> rowWord <> "です: " <> cxFun cx)
  when (null g10302) $
    let counted = [xs | r@(_, xs, _, _) <- rows, counts r]
        width = case rows of
          (_, xs, _, _) : _ -> length xs
          [] -> 1
     in case useful sig counted (replicate width XWild) of
          Just w -> warnAt cx "G10300" whole ("網羅していないパターンマッチです。" <> T.unwords (map (showWitness . display) w) <> " に当たる" <> rowWord <> "がありません（" <> whose <> "）")
          Nothing -> pure ()
  where
    display = \case
      XCon c as -> XCon (snd (T.breakOnEnd "\t" c)) (map display as)
      x -> x

signatureOf :: Ctx -> ConSignature
signatureOf cx key
  | key `elem` ["[]", "::"] = Just [("[]", 0), ("::", 2)]
  | otherwise = case T.breakOn "\t" key of
      (_, "") -> Nothing
      (tk, _) -> case [ci | ci <- allCons, ciTypeKey ci == tk] of
        ci : _ -> Just [(tk <> "\t" <> c, a) | (c, a) <- ciSiblings ci]
        [] -> Nothing
  where
    allCons =
      Map.elems (miCons (cxMod cx))
        <> Map.elems builtinCons
        <> concatMap (Map.elems . miCons) (Map.elems (scImports (cxScope cx)) <> Map.elems (scBuiltins (cxScope cx)))

-- ** where

whereLocals :: [(Name, (Local, CBind))] -> Locals
whereLocals bs = Map.fromList [(n, l) | (n, (l, _)) <- bs]

{- | The bindings of a @where@: a recursive group, inferred together and
generalised but for the variables an operator constrains. A binding
with a signature has the type of it.
-}
checkWhereBlock :: Ctx -> [Binding] -> Tc [(Name, (Local, CBind))]
checkWhereBlock cx bs = do
  let sigs = [s | BSig s <- bs]
      lazies = [(n, nl, e) | BLazy _ n nl e _ <- bs]
      itemLoc = \case
        Left (_, nl, _) -> nl
        Right (q : _) -> eqNameLoc q
        Right [] -> Loc 0 0
      runs = runsOfBindings bs
      defs = [(n, nl) | (n, nl, _) <- lazies] <> [(eqName q, eqNameLoc q) | (q : _) <- runs]
  forM_ (duplicates [(sigName s, sigNameLoc s) | s <- sigs]) $ \(n, l) -> failAt cx "G10204" l ("局所の関数 " <> n <> " のシグネチャを二度書いています")
  forM_ (duplicates defs) $ \(n, l) -> failAt cx "G10204" l (n <> " を二度定義しています")
  forM_ sigs $ \s -> unless (sigName s `elem` map fst defs) (failAt cx "G10200" (sigNameLoc s) ("局所の関数 " <> sigName s <> " の等式がありません"))
  sigSchemes <- forM sigs $ \s -> either (lift . Left) (pure . (sigName s,)) (schemeOf cx (sigType s))
  monos <- forM [n | (n, _) <- defs, n `notElem` map fst sigSchemes] $ \n -> (n,) <$> fresh
  let locals = Map.fromList ([(n, LPoly sc) | (n, sc) <- sigSchemes] <> [(n, LMono t) | (n, t) <- monos])
  checked <- forM (sortOn (locStart . itemLoc) ([Left x | x <- lazies] <> [Right r | r <- runs])) $ \item -> withUsed $ do
    let name = case item of
          Left (n, _, _) -> n
          Right (q : _) -> eqName q
          Right [] -> ""
        cxb = cx {cxFun = name}
    target <- case lookup name sigSchemes of
      Just (Scheme names t _) -> pure (substGen (map TS names) t)
      Nothing -> maybe fresh pure (lookup name monos)
    case item of
      Left (n, _, e) -> do
        c <- check cxb locals e target
        pure (n, CBind n True 0 [CEq [] (CPlain c)] (lineAt cx (itemLoc item)))
      Right run@(q : _) -> do
        let arity = length (eqPats q)
        forM_ run $ \r -> when (length (eqPats r) /= arity) (failAt cxb "G10206" (eqNameLoc r) ("局所の関数 " <> eqName r <> " の等式の引数の数が揃っていません"))
        (argTys, resTy) <- case lookup name sigSchemes of
          Just _ -> do
            t <- zonk target
            when (arityOf t /= arity) (failAt cxb "G10206" (eqNameLoc q) ("等式の引数の数がシグネチャと合いません: " <> name <> " は " <> T.pack (show (arityOf t)) <> " 個の引数を取ります"))
            pure (splitArgs arity t)
          Nothing -> do
            as <- mapM (const fresh) [1 .. arity]
            r <- fresh
            _ <- unifyB target (foldr TF r as)
            pure (as, r)
        ceqs <- checkEquations cxb locals argTys resTy run
        pure (name, CBind name False arity ceqs (lineAt cx (itemLoc item)))
      Right [] -> failAt cx "G10100" (Loc 0 0) "空の束縛"
  -- generalise the bindings without signatures
  forM checked $ \((n, cb), used) -> case lookup n sigSchemes of
    Just sc -> pure (n, (LPoly (withReqs sc (Set.toAscList used)), cb))
    Nothing -> do
      t <- zonk (fromMaybe tNat (lookup n monos))
      needs <- gets tsNeeds
      let free = nub [i | i <- metas t, not (IntMap.member i needs)]
          gen = Map.fromList (zip free [0 ..])
          t' = mapMetas (\i -> maybe (TM i) TG (Map.lookup i gen)) t
      pure (n, (LPoly (Scheme [T.pack ("t" <> show k) | k <- [1 .. length free]] t' (Set.toAscList used)), cb))
  where
    -- the requirements a binding uses, which a local function has as its own
    withUsed m = do
      before <- gets tsUsed
      modify' (\s -> s {tsUsed = Set.empty})
      r <- m
      used <- gets tsUsed
      modify' (\s -> s {tsUsed = Set.union before used})
      pure (r, used)
    metas = \case
      TM i -> [i]
      TC _ as -> concatMap metas as
      TF a b -> metas a <> metas b
      _ -> []
    mapMetas f = \case
      TM i -> f i
      TC c as -> TC c (map (mapMetas f) as)
      TF a b -> TF (mapMetas f a) (mapMetas f b)
      t -> t

runsOfBindings :: [Binding] -> [[Equation]]
runsOfBindings = go []
  where
    go acc = \case
      [] -> close acc
      BEq q : rest -> case acc of
        (p : _) | eqName p == eqName q -> go (q : acc) rest
        _ -> close acc <> go [q] rest
      _ : rest -> close acc <> go [] rest
    close acc = [reverse acc | not (null acc)]

lineAt :: Ctx -> Loc -> Int
lineAt cx l = lineOf (cxSource cx) (locStart l)
