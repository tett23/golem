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
    builtinTypes,
    metasOf,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T

{- | A type. 'TC' names a type by its key: a built-in name (@Nat@, @List@,
@(,)@ for tuples) or @path#Name@ for a data type of a module. 'TM' is a
variable of inference, 'TS' a variable of a signature inside its
function (rigid; its number keeps two signatures' @a@ apart), 'TG' a
variable of a scheme.
-}
data Ty
  = TC !Text ![Ty]
  | TF !Ty !Ty
  | TM !Int
  | TS !Int !Text
  | TG !Int
  deriving stock (Eq, Ord, Show)

{- | A type with 'TG' 0 to n - 1 for its variables, and their names. The
requirements of docs/adr/0161 are to come as a row on the arrows of 'TF'.
-}
data Scheme = Scheme ![Text] !Ty
  deriving stock (Eq, Show)

monoScheme :: Ty -> Scheme
monoScheme = Scheme []

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
      TF a b -> TF (go a) (go b)
      t -> t

-- | The variables of inference in a type, in order, once each.
metasOf :: Ty -> [Int]
metasOf = foldr (\i acc -> i : filter (/= i) acc) [] . go
  where
    go = \case
      TM i -> [i]
      TC _ as -> concatMap go as
      TF a b -> go a <> go b
      _ -> []

-- | A type as written in .emet; a variable of inference is @_@.
showTy :: Ty -> Text
showTy = go 0
  where
    go :: Int -> Ty -> Text
    go p = \case
      TC c ts | c == tupleKey -> "(" <> T.intercalate ", " (map (go 0) ts) <> ")"
      TC c [] -> typeKeyName c
      TC c as -> paren (p > 1) (T.unwords (typeKeyName c : map (go 2) as))
      TF a b -> paren (p > 0) (go 1 a <> " -> " <> go 0 b)
      TM _ -> "_"
      TS _ n -> n
      TG i -> "t" <> T.pack (show i)
    paren b t = if b then "(" <> t <> ")" else t

showScheme :: Scheme -> Text
showScheme (Scheme names t) = showTy (substGen [TS i n | (i, n) <- zip [0 ..] names] t)
