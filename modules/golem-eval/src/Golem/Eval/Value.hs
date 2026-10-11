module Golem.Eval.Value
  ( Value (..),
    typeName,
    valueToExpr,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Parser.AST

{- | Values of the expression language. 'VFloat' never holds NaN, an
infinity or negative zero: every float is built through 'finite'.
-}
data Value
  = VInt !Integer
  | VFloat !Double
  | VString !Text
  | VBool !Bool
  | VNil
  | VArray ![Value]
  | VHash !(Map Text Value)
  deriving stock (Eq, Show)

typeName :: Value -> Text
typeName = \case
  VInt _ -> "整数"
  VFloat _ -> "浮動小数点数"
  VString _ -> "文字列"
  VBool _ -> "真偽値"
  VNil -> "nil"
  VArray _ -> "配列"
  VHash _ -> "連想配列"

{- | A literal expression for a value, used to substitute S0 values into
expressions deferred to S1.
-}
valueToExpr :: Located Expr -> Value -> Located Expr
valueToExpr at v = Located (locSpan at) $ case v of
  VInt i -> EInt i
  VFloat d -> EFloat d
  VString s -> EString s
  VBool b -> EBool b
  VNil -> ENil
  VArray vs -> EArray (map (valueToExpr at) vs)
  VHash m -> EHash [(k, valueToExpr at x) | (k, x) <- Map.toAscList m]
