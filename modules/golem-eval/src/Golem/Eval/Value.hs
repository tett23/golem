module Golem.Eval.Value
  ( Value (..),
    NumType (..),
    typeName,
    valueToExpr,
    numberOf,
    mkNumber,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Ratio (numerator)
import Data.Text (Text)
import Golem.Parser.AST
import Numeric.Natural (Natural)

{- | Values of the expression language. The three number types are
natural numbers, integers and rationals (docs/adr ADR 0101); the type of
a value is decided by the expression, not by the value, so 'VInt' and
'VRat' may hold a value of a narrower type. A 'VRat' is in lowest terms
with a positive denominator ('Rational' keeps it so).
-}
data Value
  = VNat !Natural
  | VInt !Integer
  | VRat !Rational
  | VString !Text
  | VBool !Bool
  | VNil
  | VArray ![Value]
  | VHash !(Map Text Value)
  deriving stock (Eq, Show)

-- | The three number types, from the narrowest (docs/adr ADR 0101).
data NumType = TNat | TInt | TRat
  deriving stock (Eq, Ord, Show)

typeName :: Value -> Text
typeName = \case
  VNat _ -> "自然数"
  VInt _ -> "整数"
  VRat _ -> "有理数"
  VString _ -> "文字列"
  VBool _ -> "真偽値"
  VNil -> "nil"
  VArray _ -> "配列"
  VHash _ -> "連想配列"

-- | The type and the value of a number; Nothing for a value that is not one.
numberOf :: Value -> Maybe (NumType, Rational)
numberOf = \case
  VNat n -> Just (TNat, toRational n)
  VInt i -> Just (TInt, fromInteger i)
  VRat q -> Just (TRat, q)
  _ -> Nothing

{- | A number of a type. The value is one of the type: an integer for
'TInt', and an integer of 0 or more for 'TNat'.
-}
mkNumber :: NumType -> Rational -> Value
mkNumber t q = case t of
  TNat -> VNat (fromInteger (numerator q))
  TInt -> VInt (numerator q)
  TRat -> VRat q

{- | A literal expression for a value, used to substitute S0 values into
expressions deferred to S1. The literal keeps the type of the value.
-}
valueToExpr :: Located Expr -> Value -> Located Expr
valueToExpr at v = Located (locSpan at) $ case v of
  VNat n -> ENat n
  VInt i -> EInt i
  VRat q -> ERat q
  VString s -> EString s
  VBool b -> EBool b
  VNil -> ENil
  VArray vs -> EArray (map (valueToExpr at) vs)
  VHash m -> EHash [(k, valueToExpr at x) | (k, x) <- Map.toAscList m]
