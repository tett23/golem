{- | Types of .emet (docs/adr/0160). Natural numbers widen to integers and
integers to rationals: a value of a narrower number type is accepted
where a wider one is expected, also inside @List@, @Maybe@ and tuples.

There are no type classes. The operators that a class would overload
need one of three closed predicates of a type ('Pred'), which only the
built-in types satisfy ('holds'); opening them into classes adds
instances to that table and leaves the rest as it is (the section
「型クラスの余地」 of docs/adr/0160).
-}
module Golem.Emet.Types
  ( Ty (..),
    Row (..),
    Req (..),
    pureRow,
    rowVar,
    showReq,
    showRow,
    Scheme (..),
    Pred (..),
    monoScheme,
    tNat,
    tInt,
    tRat,
    tBool,
    tChar,
    tString,
    tList,
    tMaybe,
    tTuple,
    tupleKey,
    covariant,
    numRank,
    rankTy,
    holds,
    predText,
    showTy,
    showScheme,
    typeKeyName,
    substGen,
    substRow,
    builtinTypes,
    metasOf,
    rowMetas,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, maybeToList)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T

{- | A type. 'TC' names a type by its key: a built-in name (@Nat@, @List@,
@(,)@ for tuples) or @path#Name@ for a data type of a module. 'TF' is an
arrow with the row of requirements that applying it makes
(docs/adr/0161). 'TM' is a variable of inference, 'TS' a variable of a
signature inside its function (rigid; its number keeps two signatures'
@a@ apart), 'TG' a variable of a scheme.
-}
data Ty
  = TC !Text ![Ty]
  | TF !Ty !Row !Ty
  | TM !Int
  | TS !Int !Text
  | TG !Int
  deriving stock (Eq, Ord, Show)

{- | A requirement (docs/adr/0161). v1 has one kind, @file@, with the path
of the file from the root of the project, normalised. Two requirements
are the same when their kinds and paths are.
-}
newtype Req = ReqFile Text
  deriving stock (Eq, Ord, Show)

{- | A row of requirements: a set, and the variable of the rest for an
open row. The variable is a 'TM', 'TS' or 'TG' of the same numbers as
the variables of types; a number is a variable of a type or of a row,
never both. A row is a set (docs/adr/0161): a requirement is in it once.
-}
data Row = Row !(Set Req) !(Maybe Ty)
  deriving stock (Eq, Ord, Show)

-- | No requirement: the row of an arrow without one.
pureRow :: Row
pureRow = Row Set.empty Nothing

-- | The row of a variable alone.
rowVar :: Ty -> Row
rowVar v = Row Set.empty (Just v)

showReq :: Req -> Text
showReq (ReqFile p) = "file \"" <> p <> "\""

{- | A row as written in .emet, in the order of fmt: @<file "a.tsv"|e>@, a
variable alone with no brackets, and nothing for no requirement.
-}
showRow :: Row -> Text
showRow (Row rs v) = case (Set.toList rs, v) of
  ([], Nothing) -> ""
  ([], Just t) -> showVar t
  (xs, Nothing) -> "<" <> T.intercalate ", " (map showReq xs) <> ">"
  (xs, Just t) -> "<" <> T.intercalate ", " (map showReq xs) <> "|" <> showVar t <> ">"
  where
    showVar = \case
      TS _ n -> n
      TG i -> "e" <> T.pack (show i)
      _ -> "_"

{- | A type with 'TG' 0 to n - 1 for its variables, and their names; the
row that naming it makes (a function of no arguments, docs/adr/0161);
and the type.
-}
data Scheme = Scheme ![Text] !Row !Ty
  deriving stock (Eq, Show)

monoScheme :: Ty -> Scheme
monoScheme = Scheme [] pureRow

{- | The closed predicates of the operators: numbers (arithmetic), types
that compare (== and <), and types that join (++). They are the built-in
classes Num, Ord and Concat to be.
-}
data Pred = IsNum | IsOrd | IsConcat
  deriving stock (Eq, Ord, Show)

tNat, tInt, tRat, tBool, tChar, tString :: Ty
tNat = TC "Nat" []
tInt = TC "Int" []
tRat = TC "Rat" []
tBool = TC "Bool" []
tChar = TC "Char" []
tString = TC "String" []

tList, tMaybe :: Ty -> Ty
tList t = TC "List" [t]
tMaybe t = TC "Maybe" [t]

tupleKey :: Text
tupleKey = "(,)"

tTuple :: [Ty] -> Ty
tTuple = TC tupleKey

-- | The type constructors through which numbers widen.
covariant :: Text -> Bool
covariant c = c `elem` ["List", "Maybe", tupleKey]

-- | The order of the number types, from the narrowest.
numRank :: Text -> Maybe Int
numRank = \case
  "Nat" -> Just 0
  "Int" -> Just 1
  "Rat" -> Just 2
  _ -> Nothing

rankTy :: Int -> Ty
rankTy = \case
  0 -> tNat
  1 -> tInt
  _ -> tRat

{- | Whether a type that is no variable satisfies a predicate: the table
of the instances, the built-in types alone.
-}
holds :: Pred -> Ty -> Bool
holds p t = case (p, t) of
  (IsNum, TC c []) -> isJust (numRank c)
  (IsOrd, TC c []) -> isJust (numRank c) || c `elem` ["Bool", "Char", "String"]
  (IsConcat, TC "String" []) -> True
  (IsConcat, TC "List" [_]) -> True
  _ -> False

-- | What a predicate asks, for messages.
predText :: Pred -> Text
predText = \case
  IsNum -> "数（Nat、Int、Rat）"
  IsOrd -> "数、Bool、Char、String"
  IsConcat -> "String か List"

-- | The built-in types and their numbers of parameters.
builtinTypes :: Map Text Int
builtinTypes = Map.fromList [("Nat", 0), ("Int", 0), ("Rat", 0), ("Bool", 0), ("Char", 0), ("String", 0), ("List", 1), ("Maybe", 1)]

-- | The name of a type as written: the part after @#@ of a key.
typeKeyName :: Text -> Text
typeKeyName k = case T.breakOnEnd "#" k of
  ("", n) -> n
  (_, n) -> n

substGen :: [Ty] -> Ty -> Ty
substGen ts = go
  where
    go = \case
      TG i | i < length ts -> ts !! i
      TC c as -> TC c (map go as)
      TF a r b -> TF (go a) (substRow ts r) (go b)
      t -> t

substRow :: [Ty] -> Row -> Row
substRow ts (Row rs v) = Row rs (substGen ts <$> v)

-- | The variables of inference in a type, of types and of rows, in order, once each.
metasOf :: Ty -> [Int]
metasOf = foldr (\i acc -> i : filter (/= i) acc) [] . go
  where
    go = \case
      TM i -> [i]
      TC _ as -> concatMap go as
      TF a r b -> go a <> rowMetas r <> go b
      _ -> []

-- | The variable of inference of a row.
rowMetas :: Row -> [Int]
rowMetas (Row _ v) = [i | TM i <- maybeToList v]

-- | A type as written in .emet; a variable of inference is @_@.
showTy :: Ty -> Text
showTy = go 0
  where
    go :: Int -> Ty -> Text
    go p = \case
      TC c ts | c == tupleKey -> "(" <> T.intercalate ", " (map (go 0) ts) <> ")"
      TC c [] -> typeKeyName c
      TC c as -> paren (p > 1) (T.unwords (typeKeyName c : map (go 2) as))
      TF a r b -> paren (p > 0) (go 1 a <> " -> " <> rowText r <> go 0 b)
      TM _ -> "_"
      TS _ n -> n
      TG i -> "t" <> T.pack (show i)
    paren b t = if b then "(" <> t <> ")" else t
    rowText r = case showRow r of
      "" -> ""
      x -> x <> " "

showScheme :: Scheme -> Text
showScheme (Scheme names r t) =
  let vs = [TS i n | (i, n) <- zip [0 ..] names]
   in case showRow (substRow vs r) of
        "" -> showTy (substGen vs t)
        x -> x <> " " <> showTy (substGen vs t)
