{- | What the language server shows in a .emet (docs/adr/0162), as pure
functions over the text of the file and the checked program, in UTF-8
byte offsets: completion, hover and the declaration of a name.

The text the editor has may not parse while it is typed. Completion
parses the text as it is, then with the rest of the line of the cursor
cut and a placeholder in its place, then with that line removed, and
takes the first that parses; names come from the program as the last
evaluation checked it.
-}
module Golem.Emet.Ide
  ( IdeKind (..),
    emetCompletions,
    emetHover,
    emetDefinition,
    emetExportAt,
    nameAt,
  )
where

import Data.ByteString qualified as BS
import Data.Char (isAlphaNum, isUpper)
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet
import Golem.Emet.Path (normalizePath)
import Golem.Emet.Syntax
import Golem.Syntax

-- | What a name completed is.
data IdeKind = IdeFunction | IdeConstructor | IdeType | IdeModule | IdeVariable | IdeRequirement | IdeKeyword
  deriving stock (Eq, Show)

-- | The text before an offset.
before :: Text -> Int -> Text
before text off = TE.decodeUtf8Lenient (BS.take off (TE.encodeUtf8 text))

{- | The name at an offset, with its module when it is qualified
(@List.map@), and its range.
-}
nameAt :: Text -> Int -> Maybe (Maybe Text, Text, Int, Int)
nameAt text off =
  let bytes = TE.encodeUtf8 text
      isName b = b < 128 && (isAlphaNum (toEnum (fromIntegral b)) || b == 95 || b == 46)
      start = off - BS.length (BS.takeWhileEnd isName (BS.take off bytes))
      end = off + BS.length (BS.takeWhile isName (BS.drop off bytes))
      word = TE.decodeUtf8Lenient (BS.take (end - start) (BS.drop start bytes))
   in case T.breakOnEnd "." word of
        _ | T.null word -> Nothing
        ("", n) -> Just (Nothing, n, start, end)
        (q, n) -> Just (Just (T.dropEnd 1 q), n, start, end)

-- | The module of the file parsed, trying the text as it is, then with the rest of the line cut, then without the line.
parsedNear :: Text -> Int -> Maybe Module
parsedNear text off =
  listToMaybe (mapMaybe parsed [text, cut "0", cut ""])
  where
    parsed t = either (const Nothing) Just (parseModule (FileId 0) t)
    pre = before text off
    lineStart = T.dropWhileEnd (/= '\n') pre
    typed = T.takeWhileEnd (/= '\n') pre
    after = T.drop (T.length pre) text
    rest = T.dropWhile (/= '\n') after
    partial = T.dropWhileEnd (\c -> isAlphaNum c || c == '_' || c == '.') typed
    cut placeholder
      | T.null placeholder = lineStart <> rest
      | otherwise = lineStart <> partial <> placeholder <> rest

-- | The modules a file imports, by their normalised paths.
importsOf :: Module -> [FilePath]
importsOf (Module decls) = [p | DImport _ raw _ <- decls, Right p <- [normalizePath (T.unpack raw)]]

-- | The module of a path: from the text given for the file itself, from the program for the others.
infoOf :: Program -> FilePath -> Maybe ModInfo
infoOf p path = Map.lookup path (programModInfos p)

builtinModuleNames' :: [Text]
builtinModuleNames' = ["List", "String", "File", "Inline", "Block"]

{- | Completion at an offset: the requirements in a row; the names of a
built-in module after its name and a dot; otherwise the names the place
sees: the variables of the patterns around it, the bindings of where, the
declarations of the file, the public names of its imports, the built-in
modules, types and constructors.
-}
emetCompletions :: Maybe Program -> FilePath -> Text -> Int -> [(Text, IdeKind)]
emetCompletions program path text off
  | inRow = [("file", IdeRequirement)]
  | Just q <- qualifier = maybe [] publicOf (program >>= \p -> Map.lookup q (programBuiltins p))
  | otherwise =
      nub $
        locals
          <> own
          <> concatMap publicOf imported
          <> [(b, IdeModule) | b <- builtinModuleNames']
          <> [(t, IdeType) | inSignature, t <- ["Nat", "Int", "Rat", "Bool", "Char", "String", "List", "Maybe", "Inlines", "Blocks", "Varargs"]]
          <> [(c, IdeConstructor) | c <- ["True", "False", "Nothing", "Just"]]
          <> [("div", IdeFunction)]
  where
    pre = before text off
    line = T.takeWhileEnd (/= '\n') pre
    -- an open < on a line of a signature
    inRow =
      let afterOpen = T.takeWhileEnd (/= '<') line
       in "::" `T.isInfixOf` line && T.any (== '<') line && not (T.any (== '>') afterOpen)
    inSignature = "::" `T.isInfixOf` line
    typed = T.takeWhileEnd (\c -> isAlphaNum c || c == '_' || c == '.') line
    qualifier = case T.breakOnEnd "." typed of
      (q, _) | not (T.null q), Just (c, _) <- T.uncons q, isUpper c -> Just (T.dropEnd 1 q)
      _ -> Nothing
    m = parsedNear text off
    ownInfo = program >>= (`infoOf` path)
    own =
      maybe [] (\mi -> [(n, IdeFunction) | n <- Map.keys (miFuns mi)] <> [(n, IdeType) | inSignature, n <- Map.keys (miTypes mi)] <> [(n, IdeConstructor) | n <- Map.keys (miCons mi)]) ownInfo
        <> maybe [] declared m
    imported = [mi | Just p <- [program], Just md <- [m], target <- importsOf md, Just mi <- [infoOf p target]]
    publicOf mi =
      [(n, IdeFunction) | (n, fi) <- Map.toList (miFuns mi), fiPub fi]
        <> [(n, IdeType) | (n, td) <- Map.toList (miTypes mi), tdPub td]
        <> [(n, IdeConstructor) | (n, ci) <- Map.toList (miCons mi), ciPub ci]
    declared (Module decls) =
      [(sigName s, IdeFunction) | DSig s <- decls]
        <> [(n, IdeType) | inSignature, DData _ _ n _ _ <- decls]
        <> [(conNameOf c, IdeConstructor) | DData _ _ _ _ cs <- decls, c <- cs]
    conNameOf = \case
      ConPos _ n _ -> n
      ConRec _ n _ -> n
    locals = case m of
      Just (Module decls) -> [(n, IdeVariable) | n <- localsAt decls off]
      Nothing -> []

-- | The variables a place inside the equations sees: the patterns of its equation and of the alternatives around it, and the bindings of where.
localsAt :: [Decl] -> Int -> [Text]
localsAt decls off =
  concat
    [ equationLocals q
    | DEq q <- decls,
      inside (eqLoc q)
    ]
  where
    inside (Loc s e) = s <= off && off <= e + 1
    equationLocals q =
      concatMap patVarNames (eqPats q)
        <> whereNames q
        <> rhsLocals (eqRhs q)
        <> concat [equationLocals b | Where _ bs <- eqWheres q, BEq b <- bs, inside (eqLoc b)]
    whereNames q = [eqName b | Where _ bs <- eqWheres q, BEq b <- bs] <> [n | Where _ bs <- eqWheres q, BEq b <- bs, inside (eqLoc b), n <- concatMap patVarNames (eqPats b)]
    rhsLocals = \case
      Plain e -> exprLocals e
      Guarded gs -> concat [exprLocals (guardBody g) | (g, _) <- gs]
    exprLocals = \case
      ECase _ e as -> exprLocals e <> concat [patVarNames (altPat a) <> rhsLocals (altRhs a) | a <- as, inside (altLoc a)]
      EApp f x -> exprLocals f <> exprLocals x
      EBin _ _ a b -> exprLocals a <> exprLocals b
      ETernary _ c a b -> exprLocals c <> exprLocals a <> exprLocals b
      EParen _ e -> exprLocals e
      EList _ es -> concatMap exprLocals es
      ETuple _ es -> concatMap exprLocals es
      _ -> []

patVarNames :: Pat -> [Text]
patVarNames = \case
  PVar _ n -> [n]
  PCon _ _ ps -> concatMap patVarNames ps
  PRec _ _ fs -> concatMap (patVarNames . snd) fs
  PList _ ps -> concatMap patVarNames ps
  PCons _ a b -> patVarNames a <> patVarNames b
  PTuple _ ps -> concatMap patVarNames ps
  _ -> []

{- | The type of the function at an offset: of the file, of an import, or
of a built-in module, as its signature writes it.
-}
emetHover :: Program -> FilePath -> Text -> Int -> Maybe Text
emetHover p path text off = do
  (q, n, _, _) <- nameAt text off
  fi <- case q of
    Just mname -> Map.lookup mname (programBuiltins p) >>= \mi -> Map.lookup n (miFuns mi)
    Nothing ->
      listToMaybe
        ( [fi | Just mi <- [infoOf p path], Just fi <- [Map.lookup n (miFuns mi)]]
            <> [ fi
               | Just md <- [parsedNear text off],
                 target <- importsOf md,
                 Just mi <- [infoOf p target],
                 Just fi <- [Map.lookup n (miFuns mi)],
                 fiPub fi
               ]
        )
  pure (n <> " :: " <> showScheme (fiScheme fi))

{- | The declaration of the name at an offset: a function, a data type or
a constructor of the file or of an import, as a path and a range.
-}
emetDefinition :: Program -> FilePath -> Text -> Int -> Maybe (FilePath, Int, Int)
emetDefinition p path text off = do
  (Nothing, n, _, _) <- nameAt text off
  md <- parsedNear text off
  listToMaybe
    ( [(path, s, e) | Loc s e <- declarationOf md n]
        <> [ (target, s, e)
           | target <- importsOf md,
             Just (_, _, tm) <- [Map.lookup target (programModules p)],
             Loc s e <- declarationOf tm n
           ]
    )

-- | Where a module declares a name: the name of its signature, its data type or a constructor.
declarationOf :: Module -> Text -> [Loc]
declarationOf (Module decls) n =
  [sigNameLoc s | DSig s <- decls, sigName s == n]
    <> [l | DData l _ t _ _ <- decls, t == n]
    <> [l | DType l _ t _ _ <- decls, t == n]
    <> [conLoc c | DData _ _ _ _ cs <- decls, c <- cs, conName' c == n]
  where
    conLoc = \case
      ConPos l _ _ -> l
      ConRec l _ _ -> l
    conName' = \case
      ConPos _ c _ -> c
      ConRec _ c _ -> c

{- | The function .gm uses whose name in the file is at an offset (in its
signature or one of its equations), for the references of its calls.
-}
emetExportAt :: Program -> FilePath -> Text -> Int -> Maybe Export
emetExportAt p path text off = do
  (Nothing, n, _, _) <- nameAt text off
  listToMaybe (sortOn exName [e | e <- Map.findWithDefault [] path (programExports p), exFunction e == n])
