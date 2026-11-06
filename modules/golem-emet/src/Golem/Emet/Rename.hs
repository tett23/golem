{-# LANGUAGE MultiWayIf #-}

{- | Renaming a name of .emet (docs/adr/0170), over the syntax of the
files of a program.

Each name of a file is resolved to what it names: a local name (a
variable of a pattern, a binding of where), a top-level name of a file
(a function, a data type or an alias, a constructor), or a built-in
name. A local name is renamed in its function; a top-level name in the
file that declares it and, when it is pub, in the files that import that
file.

The new name is checked first, and nothing is renamed when it fails:
the rules of names of .emet, the reserved words, and the names it would
meet (E02104, E02108 of docs/adr/0160): the other names of its scope, the
names the files import, and the names it would hide or be hidden by. A
function .gm calls by its name must keep a name of .gm (E06100) and
differ from the other names of its kind (E06106).

The texts are those the editor has: each file is parsed again, and the
files that import a file are those of the program as last checked.
-}
module Golem.Emet.Rename
  ( RenameError (..),
    Renamed (..),
    emetRename,
  )
where

import Data.ByteString qualified as BS
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List (nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet.Check (builtinCons, builtinModuleNames, gmName)
import Golem.Emet.Parse (parseModule)
import Golem.Emet.Path (normalizePath)
import Golem.Emet.Syntax
import Golem.Emet.Types (builtinTypes)
import Golem.Syntax (FileId (..))

-- | Why a name cannot be renamed to another.
data RenameError
  = -- | no name of a function, a type, a constructor or a local at the place
    RenameNotAName
  | -- | a name of a built-in module, type, constructor or function
    RenameBuiltin !Text
  | -- | not a name of the kind of .emet
    RenameInvalid !Text
  | RenameReserved !Text
  | -- | the name meets another name in the same scope
    RenameTaken !Text
  | -- | a function .gm calls by its name, and the new name is no name of a command of .gm
    RenameNotCommand !Text
  | -- | a file that has to be rewritten does not parse
    RenameSyntax !FilePath
  deriving stock (Eq, Show)

{- | The ranges to rewrite with the new name, by file, in UTF-8 bytes; and,
for a top-level function with a kind after pub, its file, its name, its
kind and whether it has the name .gm uses written as a string.
-}
data Renamed = Renamed
  { rnEdits :: ![(FilePath, Int, Int)],
    rnExported :: !(Maybe (FilePath, Name, Kind, Bool))
  }
  deriving stock (Eq, Show)

-- | The namespaces of the top-level names.
data Ns = NsValue | NsType | NsCon
  deriving stock (Eq, Ord, Show)

-- | What a name names.
data Ref = RLocal !Int | RTop !FilePath !Ns !Name | RBuiltin
  deriving stock (Eq, Ord, Show)

-- | A name in a file: its range, what it names, and the local names in scope there.
data Occ = Occ
  { occStart :: !Int,
    occEnd :: !Int,
    occName :: !Name,
    occRef :: !Ref,
    occBound :: !(Set Name)
  }

-- | A local name: its id, the ranges of its scope, and the names it may not take.
data Binder = Binder
  { bdId :: !Int,
    bdName :: !Name,
    bdScope :: ![Loc],
    bdSiblings :: ![Name]
  }

-- | The words of the language and those it reserves (E01102), as the grammar's.
reservedWords :: [Text]
reservedWords =
  [ "pub",
    "inline",
    "block",
    "filter",
    "fn",
    "data",
    "type",
    "import",
    "as",
    "where",
    "case",
    "of",
    "otherwise",
    "if",
    "then",
    "else",
    "for",
    "while",
    "let",
    "in",
    "lazy",
    "class",
    "instance",
    "deriving",
    "default"
  ]

isNameChar :: Char -> Bool
isNameChar c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '_'

isVarName :: Text -> Bool
isVarName t = case T.uncons t of
  Just (c, rest) -> (isAsciiLower c || c == '_') && T.all isNameChar rest && t /= "_"
  Nothing -> False

isConName :: Text -> Bool
isConName t = case T.uncons t of
  Just (c, rest) -> isAsciiUpper c && T.all isNameChar rest
  Nothing -> False

byteLen :: Text -> Int
byteLen = BS.length . TE.encodeUtf8

{- | Renames the name at an offset of a file. The files are those of the
program: the module as last checked and the text the editor has now.
-}
emetRename :: Map FilePath (Module, Text) -> FilePath -> Int -> Text -> Either RenameError Renamed
emetRename files path off new = do
  m <- maybe (Left (RenameSyntax path)) Right (current path)
  let (occs, binders) = resolve mods path (textOf path) m
  o <- maybe (Left RenameNotAName) Right (listToMaybe (sortOn (\x -> occEnd x - occStart x) [x | x <- occs, occStart x <= off, off <= occEnd x]))
  case occRef o of
    RBuiltin -> Left (RenameBuiltin (occName o))
    RLocal i -> do
      validVar
      b <- maybe (Left RenameNotAName) Right (listToMaybe [x | x <- binders, bdId x == i])
      let mine = [x | x <- occs, occRef x == RLocal i]
          inScope x = any (\(Loc s e) -> s <= occStart x && occEnd x <= e) (bdScope b)
      if
        | new == bdName b -> pure (Renamed [] Nothing)
        | new `elem` bdSiblings b || any (Set.member new . occBound) mine -> Left (RenameTaken new)
        | any (\x -> occName x == new && occRef x /= RLocal i && inScope x) occs -> Left (RenameTaken new)
        | otherwise -> pure (Renamed [(path, occStart x, occEnd x) | x <- mine] Nothing)
    target@(RTop p ns n) -> do
      case ns of
        NsValue -> validVar
        _ -> validCon ns
      decl <- maybe (Left (RenameSyntax p)) Right (Map.lookup p mods)
      let public = isPublic decl ns n
          importers = [f | public, (f, md) <- Map.toList mods, f /= p, p `elem` importsOf md]
          affected = p : importers
      mapM_ (\f -> maybe (Left (RenameSyntax f)) (const (Right ())) (current f)) affected
      let occsOf f = maybe [] (fst . resolve mods f (textOf f)) (current f)
          mine = [(f, x) | f <- affected, x <- occsOf f, occRef x == target]
          exported = (\(_, a, b, c) -> (p, a, b, c)) <$> exportedOf decl n
          others f = ownNames (fromMaybe (Module []) (Map.lookup f mods)) ns
          importedBy f skip = concat [publicNames md ns | Just fm <- [Map.lookup f mods], q <- importsOf fm, q /= skip, Just md <- [Map.lookup q mods]]
          taken =
            new `elem` filter (/= n) (others p)
              || new `elem` importedBy p ""
              || any (\f -> new `elem` others f || new `elem` importedBy f p) importers
              || any (Set.member new . occBound . snd) mine
              || builtinClash ns
      if
        | new == n -> pure (Renamed [] exported)
        | taken -> Left (RenameTaken new)
        | Just (_, _, k, False) <- exported, k /= KindFn, not (gmName new) -> Left (RenameNotCommand new)
        | Just (_, _, k, False) <- exported, new `elem` exportNames decl k -> Left (RenameTaken new)
        | Just (_, _, KindFn, _) <- exported, new `elem` exportNames decl KindFn -> Left (RenameTaken new)
        | otherwise -> pure (Renamed [(f, occStart x, occEnd x) | (f, x) <- mine] exported)
  where
    textOf f = maybe "" snd (Map.lookup f files)
    current f = Map.lookup f files >>= \(_, t) -> either (const Nothing) Just (parseModule (FileId 0) t)
    -- the modules as the editor has them, those that do not parse as last checked
    mods = Map.mapWithKey (\f (old, _) -> fromMaybe old (current f)) files
    validVar
      | new `elem` reservedWords = Left (RenameReserved new)
      | isVarName new = Right ()
      | otherwise = Left (RenameInvalid new)
    validCon _
      | isConName new = Right ()
      | otherwise = Left (RenameInvalid new)
    builtinClash = \case
      NsValue -> new == "div"
      NsType -> Map.member new builtinTypes || new `elem` ["Inlines", "Blocks", "Varargs"] || new `elem` builtinModuleNames
      NsCon -> Map.member new builtinCons || new `elem` builtinModuleNames

-- | The paths a module imports.
importsOf :: Module -> [FilePath]
importsOf (Module decls) = [p | DImport _ raw _ <- decls, Right p <- [normalizePath (T.unpack raw)]]

-- | The names a module declares in a namespace.
ownNames :: Module -> Ns -> [Name]
ownNames (Module decls) = \case
  NsValue -> nub ([sigName s | DSig s <- decls] <> [eqName q | DEq q <- decls])
  NsType -> [n | DData _ _ n _ _ <- decls] <> [n | DType _ _ n _ _ <- decls]
  NsCon -> [conName c | DData _ _ _ _ cs <- decls, c <- cs]

-- | The pub names a module declares in a namespace.
publicNames :: Module -> Ns -> [Name]
publicNames md ns = [n | n <- ownNames md ns, isPublic md ns n]

isPublic :: Module -> Ns -> Name -> Bool
isPublic (Module decls) ns n = case ns of
  NsValue -> or [sigPub s | DSig s <- decls, sigName s == n]
  NsType -> or ([p | DData _ p t _ _ <- decls, t == n] <> [p | DType _ p t _ _ <- decls, t == n])
  NsCon -> or [p | DData _ p _ _ cs <- decls, c <- cs, conName c == n]

-- | A top-level function with a kind: its path, name, kind and whether it has a string name.
exportedOf :: Module -> Name -> Maybe (FilePath, Name, Kind, Bool)
exportedOf (Module decls) n = listToMaybe [("", n, k, isJust (sigExport s)) | DSig s <- decls, sigName s == n, Just (k, _) <- [sigKind s]]

-- | The names .gm uses of the functions of a kind of a module.
exportNames :: Module -> Kind -> [Text]
exportNames (Module decls) k = [maybe (sigName s) fst (sigExport s) | DSig s <- decls, Just (k', _) <- [sigKind s], k' == k]

conName :: ConDecl -> Name
conName = \case
  ConPos _ n _ -> n
  ConRec _ n _ -> n

-- * Resolving the names of a file

data Env = Env
  { envVals :: !(Map Name Ref),
    envTypes :: !(Map Name Ref),
    envCons :: !(Map Name Ref)
  }

-- | The names of a file and the local names it binds.
resolve :: Map FilePath Module -> FilePath -> Text -> Module -> ([Occ], [Binder])
resolve mods path text md@(Module decls) = mconcat (map decl decls)
  where
    bytes = TE.encodeUtf8 text
    env =
      Env
        { envVals = top NsValue,
          envTypes = top NsType,
          envCons = top NsCon
        }
    top ns =
      Map.union
        (Map.fromList [(n, RTop path ns n) | n <- ownNames md ns])
        (Map.unions [Map.fromList [(n, RTop q ns n) | n <- publicNames im ns] | q <- importsOf md, Just im <- [Map.lookup q mods]])
    occAt s n = Occ s (s + byteLen n) n
    decl = \case
      DImport {} -> mempty
      DSig s -> ([occAt (locStart (sigNameLoc s)) (sigName s) (RTop path NsValue (sigName s)) Set.empty], []) <> typeE (sigType s)
      DEq q
        | (first : _) <- eqsNamed (eqName q),
          locStart (eqLoc first) == locStart (eqLoc q) ->
            function (eqsNamed (eqName q))
      DEq _ -> mempty
      DData l _ n _ cs ->
        ([occAt s n (RTop path NsType n) Set.empty | Just s <- [firstWord l n]], [])
          <> mconcat (map conDecl cs)
      DType l _ n _ t -> ([occAt s n (RTop path NsType n) Set.empty | Just s <- [firstWord l n]], []) <> typeE t
    eqsNamed n = [q | DEq q <- decls, eqName q == n]
    conDecl = \case
      ConPos l n ts -> ([occAt (locStart l) n (RTop path NsCon n) Set.empty], []) <> mconcat (map typeE ts)
      ConRec l n fs -> ([occAt (locStart l) n (RTop path NsCon n) Set.empty], []) <> mconcat (map (typeE . snd) fs)
    -- the first whole word in the range of a declaration: the name after its keywords
    firstWord (Loc s e) n =
      let piece = BS.take (e - s) (BS.drop s bytes)
          wb = TE.encodeUtf8 n
          isWordByte b = b == 95 || (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
          at i =
            BS.take (BS.length wb) (BS.drop i piece) == wb
              && (i == 0 || not (isWordByte (BS.index piece (i - 1))))
              && (i + BS.length wb >= BS.length piece || not (isWordByte (BS.index piece (i + BS.length wb))))
       in listToMaybe [s + i | i <- [0 .. BS.length piece - BS.length wb], at i]
    typeE = \case
      TCon l q args -> (qualOcc l q (envTypes env) Set.empty, []) <> mconcat (map typeE args)
      TVar {} -> mempty
      TFun a _ b -> typeE a <> typeE b
      TTuple _ ts -> mconcat (map typeE ts)
      TNamed _ _ t d -> typeE t <> maybe mempty (expr (Ctx []) Map.empty) d
    qualOcc l (QName q n) names bound = case q of
      Nothing -> [occAt (locStart l) n (fromMaybe RBuiltin (Map.lookup n names)) bound]
      Just m -> [occAt (locStart l) (m <> "." <> n) RBuiltin bound]
    -- a top-level function: its equations and the bindings of its where
    function eqs =
      let wheres = [w | q <- eqs, w <- eqWheres q <> guardWheres (eqRhs q)]
          bindings = concat [bs | Where _ bs <- wheres]
          whereEqs = [b | BEq b <- bindings]
          whereSigs = [s | BSig s <- bindings]
          whereNames = nub (map eqName whereEqs <> map sigName whereSigs)
          whereId n = fromMaybe 0 (listToMaybe ([locStart (eqNameLoc b) | b <- whereEqs, eqName b == n] <> [locStart (sigNameLoc s) | s <- whereSigs, sigName s == n]))
          whereRefs = Map.fromList [(n, RLocal (whereId n)) | n <- whereNames]
          scope = map eqLoc eqs
          ctx = Ctx whereNames
          (eqOccs, eqBinders) = mconcat (map (equation ctx whereRefs) eqs)
          (wOccs, wBinders) = mconcat (map (whereBinding ctx whereRefs whereId) bindings)
          patBinders = eqBinders <> wBinders
          whereBinders = [Binder (whereId n) n scope (filter (/= n) whereNames <> map bdName patBinders) | n <- whereNames]
       in (eqOccs <> wOccs, patBinders <> whereBinders)
    equation ctx whereRefs q =
      let (patOccs, binders, refs) = patterns ctx [eqLoc q] (eqPats q)
          locals = Map.union refs whereRefs
       in ([occAt (locStart (eqNameLoc q)) (eqName q) (RTop path NsValue (eqName q)) Set.empty], binders)
            <> (patOccs, [])
            <> rhs ctx locals (eqRhs q)
    whereBinding ctx whereRefs whereId = \case
      BSig s -> ([occAt (locStart (sigNameLoc s)) (sigName s) (RLocal (whereId (sigName s))) (Map.keysSet whereRefs)], []) <> typeE (sigType s)
      BEq b ->
        let (patOccs, binders, refs) = patterns ctx [eqLoc b] (eqPats b)
            locals = Map.union refs whereRefs
         in ([occAt (locStart (eqNameLoc b)) (eqName b) (RLocal (whereId (eqName b))) (Map.keysSet whereRefs)], binders)
              <> (patOccs, [])
              <> rhs ctx locals (eqRhs b)
    -- the variables of a group of patterns, each a local of the scope
    patterns ctx scope ps =
      let vars = concatMap patVars ps
          names = map fst vars
          binders = [Binder (locStart l) n scope (filter (/= n) names <> ctxWhere ctx) | (n, l) <- vars]
          refs = Map.fromList [(n, RLocal (locStart l)) | (n, l) <- vars]
          bound = Set.fromList (names <> ctxWhere ctx)
       in (concatMap (patOcc bound) ps, binders, refs)
    patOcc bound = \case
      PVar l n -> [occAt (locStart l) n (RLocal (locStart l)) bound]
      PCon l q ps -> qualOcc l q (envCons env) bound <> concatMap (patOcc bound) ps
      PRec l q fs -> qualOcc l q (envCons env) bound <> concatMap (patOcc bound . snd) fs
      PList _ ps -> concatMap (patOcc bound) ps
      PCons _ a b -> patOcc bound a <> patOcc bound b
      PTuple _ ps -> concatMap (patOcc bound) ps
      _ -> []
    rhs ctx locals = \case
      Plain e -> expr ctx locals e
      Guarded gs ->
        mconcat
          [ (case guardCond g of GExpr c -> expr ctx locals c; GOtherwise _ -> mempty) <> expr ctx locals (guardBody g)
          | (g, _) <- gs
          ]
    expr ctx locals = \case
      EVar l (QName Nothing n) -> ([occAt (locStart l) n (fromMaybe (fromMaybe RBuiltin (Map.lookup n (envVals env))) (Map.lookup n locals)) bound], [])
      EVar l (QName (Just m) n) -> ([occAt (locStart l) (m <> "." <> n) RBuiltin bound], [])
      ECon l q -> (qualOcc l q (envCons env) bound, [])
      ERecord l q fs -> (qualOcc l q (envCons env) bound, []) <> mconcat [expr ctx locals x | (_, _, x) <- fs]
      ECase _ s alts ->
        expr ctx locals s
          <> mconcat
            [ let (patOccs, binders, refs) = patterns ctx [altLoc a] [altPat a]
               in (patOccs, binders) <> rhs ctx (Map.union refs locals) (altRhs a)
            | a <- alts
            ]
      EApp f x -> expr ctx locals f <> expr ctx locals x
      EBin _ _ a b -> expr ctx locals a <> expr ctx locals b
      ENeg _ x -> expr ctx locals x
      ETernary _ c a b -> expr ctx locals c <> expr ctx locals a <> expr ctx locals b
      EParen _ x -> expr ctx locals x
      EList _ xs -> mconcat (map (expr ctx locals) xs)
      ETuple _ xs -> mconcat (map (expr ctx locals) xs)
      _ -> mempty
      where
        bound = Map.keysSet locals
    guardWheres = \case
      Guarded gs -> concatMap snd gs
      Plain _ -> []

-- | What the patterns of a function may not take: the names of the bindings of its where.
newtype Ctx = Ctx {ctxWhere :: [Name]}

-- | The variables of a pattern with their ranges.
patVars :: Pat -> [(Name, Loc)]
patVars = \case
  PVar l n -> [(n, l)]
  PCon _ _ ps -> concatMap patVars ps
  PRec _ _ fs -> concatMap (patVars . snd) fs
  PList _ ps -> concatMap patVars ps
  PCons _ a b -> patVars a <> patVars b
  PTuple _ ps -> concatMap patVars ps
  _ -> []
