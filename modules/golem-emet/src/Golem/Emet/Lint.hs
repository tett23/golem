{- | The lint of .emet (docs/adr/0162): descriptions that are almost surely
mistakes, as errors without a way to silence them, like the lint of .gm.

- E07100: a top-level function, data type or type alias without @pub@
  that nothing else in its file uses.
- E07101: an @import@ none of whose public names the file uses.
- E07102: a variable of a pattern that its right-hand side does not use;
  a name that starts with @_@ is meant to be unused.

A function with @pub@ is never reported, used or not, so that a function
can be made public before it is used. An unused binding of @where@ is the
notice E02109 of the checker, not a rule of lint.
-}
module Golem.Emet.Lint
  ( lintProgram,
  )
where

import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as T
import Golem.Emet
import Golem.Emet.Path (normalizePath)
import Golem.Emet.Syntax
import Golem.Syntax

-- | The lint of the modules of the files of a program.
lintProgram :: Program -> [Diagnostic]
lintProgram p =
  sortDiagnostics
    [ d
    | (_, (fid, _, m)) <- Map.toList (programModules p),
      d <- lintModule (programModInfos p) fid m
    ]

lintModule :: Map.Map FilePath ModInfo -> FileId -> Module -> [Diagnostic]
lintModule infos fid (Module decls) = unusedDecls <> unusedImports <> unusedVars
  where
    at (Loc s e) = mkSpan fid s (max s e)
    err code l = diagnostic code Error (at l)
    -- the names every declaration uses but its own
    usedBy = map (\d -> (ownerOf d, declNames d)) decls
    usedOutside owner = Set.unions [ns | (o, ns) <- usedBy, o /= owner || isNothing o]
    unusedDecls =
      [ err "E07100" (sigNameLoc s) ("使われていない関数です: " <> sigName s)
      | DSig s <- decls,
        not (sigPub s),
        not (Set.member (sigName s) (usedOutside (Just (sigName s))))
      ]
        <> [ err "E07100" l ("使われていないデータ型です: " <> n)
           | DData l pub n _ cs <- decls,
             not pub,
             let used = usedOutside (Just n),
             not (Set.member n used),
             not (any ((`Set.member` used) . conName) cs)
           ]
        <> [ err "E07100" l ("使われていない型の別名です: " <> n)
           | DType l pub n _ _ <- decls,
             not pub,
             not (Set.member n (usedOutside (Just n)))
           ]
    allUsed = Set.unions (map snd usedBy)
    unusedImports =
      [ err "E07101" pl ("使われていない import です: " <> path)
      | DImport _ path pl <- decls,
        Right target <- [normalizePath (T.unpack path)],
        Just mi <- [Map.lookup target infos],
        let names = publicNames mi,
        not (any (`Set.member` allUsed) names)
      ]
    unusedVars = concatMap equationVars [q | DEq q <- decls]
    equationVars q =
      unusedIn (eqPats q) (rhsNames (eqRhs q))
        <> rhsAlts (eqRhs q)
        <> concat [equationVars b | Where _ bs <- eqWheres q <> guardWheres (eqRhs q), BEq b <- bs]
    unusedIn pats used =
      [ err "E07102" l ("使われていないパターンの変数です: " <> v <> "（使わない変数は _ で始めます）")
      | (v, l) <- concatMap patVars pats,
        not ("_" `T.isPrefixOf` v),
        not (Set.member v used)
      ]
    -- the alternatives of case in a right-hand side, each with its own variables
    rhsAlts = \case
      Plain e -> exprAlts e
      Guarded gs -> concat [condAlts (guardCond g) <> exprAlts (guardBody g) | (g, _) <- gs]
    condAlts = \case
      GOtherwise _ -> []
      GExpr e -> exprAlts e
    exprAlts = \case
      ECase _ e as -> exprAlts e <> concat [unusedIn [altPat a] (rhsNames (altRhs a)) <> rhsAlts (altRhs a) | a <- as]
      EApp f x -> exprAlts f <> exprAlts x
      EBin _ _ a b -> exprAlts a <> exprAlts b
      ENeg _ e -> exprAlts e
      ETernary _ c a b -> exprAlts c <> exprAlts a <> exprAlts b
      EList _ es -> concatMap exprAlts es
      ETuple _ es -> concatMap exprAlts es
      ERecord _ _ fs -> concat [exprAlts e | (_, _, e) <- fs]
      EParen _ e -> exprAlts e
      _ -> []

-- | The declaration a use belongs to: a function by its name, a type by its name, or none.
ownerOf :: Decl -> Maybe Name
ownerOf = \case
  DSig s -> Just (sigName s)
  DEq q -> Just (eqName q)
  DData _ _ n _ _ -> Just n
  DType _ _ n _ _ -> Just n
  DImport {} -> Nothing

conName :: ConDecl -> Name
conName = \case
  ConPos _ n _ -> n
  ConRec _ n _ -> n

-- | The public names of a module: functions, types and constructors.
publicNames :: ModInfo -> [Name]
publicNames mi =
  [n | (n, fi) <- Map.toList (miFuns mi), fiPub fi]
    <> [n | (n, td) <- Map.toList (miTypes mi), tdPub td]
    <> [n | (n, ci) <- Map.toList (miCons mi), ciPub ci]

-- | The names a declaration uses, unqualified: of functions, constructors and types.
declNames :: Decl -> Set Name
declNames = \case
  DImport {} -> Set.empty
  DSig s -> typeNames (sigType s)
  DEq q -> equationNames q
  DData _ _ _ _ cs -> Set.unions [Set.unions (map typeNames (conTypes c)) | c <- cs]
  DType _ _ _ _ t -> typeNames t
  where
    conTypes = \case
      ConPos _ _ ts -> ts
      ConRec _ _ fs -> map snd fs

equationNames :: Equation -> Set Name
equationNames q =
  Set.unions
    ( Set.unions (map patNames (eqPats q))
        : rhsNames (eqRhs q)
        : [bindingNames b | Where _ bs <- eqWheres q <> guardWheres (eqRhs q), b <- bs]
    )
  where
    bindingNames = \case
      BSig s -> typeNames (sigType s)
      BEq b -> equationNames b

guardWheres :: Rhs -> [Where]
guardWheres = \case
  Guarded gs -> concatMap snd gs
  Plain _ -> []

rhsNames :: Rhs -> Set Name
rhsNames = \case
  Plain e -> exprNames e
  Guarded gs -> Set.unions [condNames (guardCond g) <> exprNames (guardBody g) | (g, _) <- gs]
  where
    condNames = \case
      GOtherwise _ -> Set.empty
      GExpr e -> exprNames e

exprNames :: Expr -> Set Name
exprNames = \case
  EVar _ (QName Nothing n) -> Set.singleton n
  ECon _ (QName Nothing n) -> Set.singleton n
  ERecord _ c fs -> qualified c <> Set.unions [exprNames e | (_, _, e) <- fs]
  EList _ es -> Set.unions (map exprNames es)
  ETuple _ es -> Set.unions (map exprNames es)
  EApp f x -> exprNames f <> exprNames x
  EBin _ _ a b -> exprNames a <> exprNames b
  ENeg _ e -> exprNames e
  ECase _ e as -> exprNames e <> Set.unions [patNames (altPat a) <> rhsNames (altRhs a) <> Set.unions [whereNames w | w <- altWheres a] | a <- as]
  ETernary _ c a b -> exprNames c <> exprNames a <> exprNames b
  EParen _ e -> exprNames e
  _ -> Set.empty
  where
    qualified = \case
      QName Nothing n -> Set.singleton n
      _ -> Set.empty
    whereNames (Where _ bs) = Set.unions [equationNames b | BEq b <- bs]

-- | The constructors a pattern names.
patNames :: Pat -> Set Name
patNames = \case
  PCon _ (QName Nothing c) ps -> Set.insert c (Set.unions (map patNames ps))
  PCon _ _ ps -> Set.unions (map patNames ps)
  PRec _ (QName Nothing c) fs -> Set.insert c (Set.unions (map (patNames . snd) fs))
  PRec _ _ fs -> Set.unions (map (patNames . snd) fs)
  PList _ ps -> Set.unions (map patNames ps)
  PCons _ a b -> patNames a <> patNames b
  PTuple _ ps -> Set.unions (map patNames ps)
  _ -> Set.empty

-- | The variables of a pattern and where they are.
patVars :: Pat -> [(Name, Loc)]
patVars = \case
  PVar l n -> [(n, l)]
  PCon _ _ ps -> concatMap patVars ps
  PRec _ _ fs -> concatMap (patVars . snd) fs
  PList _ ps -> concatMap patVars ps
  PCons _ a b -> patVars a <> patVars b
  PTuple _ ps -> concatMap patVars ps
  _ -> []

typeNames :: TypeE -> Set Name
typeNames = \case
  TCon _ (QName Nothing n) as -> Set.insert n (Set.unions (map typeNames as))
  TCon _ _ as -> Set.unions (map typeNames as)
  TFun a _ b -> typeNames a <> typeNames b
  TTuple _ ts -> Set.unions (map typeNames ts)
  TNamed _ _ t _ -> typeNames t
  TVar {} -> Set.empty
