{- | Types of .gmx (docs/adr/0148) and their unification. Natural numbers
widen to integers and integers to rationals: a value of a narrower number
type is accepted where a wider one is expected ('subsume'), also inside
@List@ and @Maybe@. There are no type classes; a type variable that an
operator needs to be a number, comparable or joinable carries that need
('Need') and is never generalised.
-}
module Golem.Gmx.Types
  ( Ty (..),
    Scheme (..),
    Need (..),
    monoScheme,
    tNat,
    tInt,
    tRat,
    tBool,
    tString,
    tInlines,
    tBlocks,
    tList,
    tMaybe,
    numRank,
    rankTy,
    showTy,
    showScheme,
    typeKeyName,
    substGen,
    builtinTypes,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T

{- | A type. 'TC' names a type by its key: a built-in name (@Nat@) or
@path#Name@ for a data type of a module. 'TM' is a variable of inference,
'TS' a variable of a signature inside its function, 'TG' a variable of a
scheme.
-}
data Ty
  = TC !Text ![Ty]
  | TF !Ty !Ty
  | TM !Int
  | TS !Text
  | TG !Int
  deriving stock (Eq, Ord, Show)

{- | A type with 'TG' 0 to n - 1 for its variables, and their names, and
the requirements of the function (docs/adr/0149): a set of names, so that
variables of requirements and handlers of users can be added later.
-}
data Scheme = Scheme ![Text] !Ty ![Text]
  deriving stock (Eq, Show)

monoScheme :: Ty -> Scheme
monoScheme t = Scheme [] t []

-- | What an operator needs of a variable.
data Need = NeedNum | NeedEq | NeedAppend
  deriving stock (Eq, Ord, Show)

tNat, tInt, tRat, tBool, tString :: Ty
tNat = TC "Nat" []
tInt = TC "Int" []
tRat = TC "Rat" []
tBool = TC "Bool" []
tString = TC "String" []

tInlines, tBlocks :: Ty
tInlines = TC "Inlines" []
tBlocks = TC "Blocks" []

tList, tMaybe :: Ty -> Ty
tList t = TC "List" [t]
tMaybe t = TC "Maybe" [t]

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

-- | The built-in types and their numbers of parameters.
builtinTypes :: Map Text Int
builtinTypes = Map.fromList [("Nat", 0), ("Int", 0), ("Rat", 0), ("Bool", 0), ("String", 0), ("List", 1), ("Maybe", 1), ("Inlines", 0), ("Blocks", 0)]

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

-- | A type as written in .gmx; a variable of inference is @_@.
showTy :: Ty -> Text
showTy = go 0
  where
    go :: Int -> Ty -> Text
    go p = \case
      TC c [] -> typeKeyName c
      TC c as -> paren (p > 1) (T.unwords (typeKeyName c : map (go 2) as))
      TF a b -> paren (p > 0) (go 1 a <> " -> " <> go 0 b)
      TM _ -> "_"
      TS n -> n
      TG i -> "t" <> T.pack (show i)
    paren b t = if b then "(" <> t <> ")" else t

showScheme :: Scheme -> Text
showScheme (Scheme names t reqs) =
  showTy (substGen (map TS names) t) <> if null reqs then "" else " => " <> T.intercalate ", " reqs
