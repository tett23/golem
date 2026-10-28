{- | The analysis of an expression before it is evaluated (docs/adr ADR
0102): the type of an expression, decided by the expression and not by
its value, and the places that take a natural number whose value is known
at S0.
-}
module Golem.Eval.Analysis
  ( StaticType (..),
    NumType (..),
    inferExpr,
    analyse,
  )
where

import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe, mapMaybe)
import Golem.Eval.Expr
import Golem.Eval.Value
import Golem.Parser.AST
import Golem.Syntax

-- | The type of an expression.
data StaticType
  = SNum NumType
  | SString
  | SBool
  | SNil
  | SArray
  | SHash
  | -- | the closed range a...b (docs/adr ADR 0113)
    SRange
  deriving stock (Eq, Show)

-- | The types of the names of doc (docs/markup.md "予約された名前空間").
docType :: [Name] -> Maybe StaticType
docType = \case
  [] -> Just SHash
  ["chapters"] -> Just SHash
  ["chapters", "count"] -> Just (SNum TNat)
  _ -> Nothing

-- | The type of a value: the constructor of a number.
valueType :: Value -> StaticType
valueType = \case
  VNat _ -> SNum TNat
  VInt _ -> SNum TInt
  VRat _ -> SNum TRat
  VString _ -> SString
  VBool _ -> SBool
  VNil -> SNil
  VArray _ -> SArray
  VHash _ -> SHash
  VRange _ _ -> SRange

{- | The type of an expression by the rules of docs/adr ADR 0101: the
literals by their kind, an S0 name by the constructor of its value, a name
of doc by its table, an operation by the types of its arguments. Nothing
for an expression that has no value (the evaluation reports it).
-}
inferExpr :: Env -> Located Expr -> Maybe StaticType
inferExpr env (Located _ e) = case e of
  ENat _ -> num TNat
  EInt _ -> num TInt
  ERat _ -> num TRat
  EString _ -> Just SString
  EBool _ -> Just SBool
  ENil -> Just SNil
  EArray _ -> Just SArray
  EHash _ -> Just SHash
  EVar ("doc" : rest) | Map.notMember "doc" (envVars env) -> docType rest
  EVar [n] -> case Map.lookup n (envVars env) of
    Just v -> Just (valueType v)
    Nothing
      | n `elem` ["pi", "e"] -> num TRat
      | otherwise -> Nothing
  EVar (ns : rest) -> Map.lookup ns (envNamespaces env) >>= \m -> member (VHash m) rest
  EVar [] -> Nothing
  EUnary Negate x -> numOf x >>= \t -> num (max TInt t)
  EBinary op a b -> case op of
    Add -> both max
    Mul -> both max
    Sub -> both (\s t -> max TInt (max s t))
    Div -> both (\_ _ -> TRat)
    Mod -> both (\_ t -> if t == TNat then TNat else TInt)
    Pow -> both (\s t -> if t == TNat then s else TRat)
    _ -> Just SBool
    where
      both f = do
        s <- numOf a
        t <- numOf b
        num (f s t)
  ECall f args -> case (f, args) of
    ("sqrt", [_]) -> num TRat
    ("floor", [x]) -> numOf x >>= num . min TInt
    ("ceil", [x]) -> numOf x >>= num . min TInt
    ("round", [x]) -> numOf x >>= num . min TInt
    ("round", [x, _]) -> numOf x >>= num
    ("fixed", [_, _]) -> Just SString
    ("abs", [x]) -> numOf x >>= \t -> num (if t == TRat then TRat else TNat)
    ("min", xs@(_ : _)) -> traverse numOf xs >>= num . maximum
    ("max", xs@(_ : _)) -> traverse numOf xs >>= num . maximum
    ("len", [_]) -> num TNat
    ("div", [x, y]) -> do
      s <- numOf x
      t <- numOf y
      num (if s == TNat && t == TNat then TNat else TInt)
    ("join", [_, _]) -> Just SString
    _ -> Nothing
  -- a range whose end is known to be no number has no value (docs/adr ADR 0113)
  ERange a b
    | any notNumber [a, b] -> Nothing
    | otherwise -> Just SRange
  EError -> Nothing
  where
    notNumber x = case inferExpr env x of
      Just (SNum _) -> False
      Just _ -> True
      Nothing -> False
    num = Just . SNum
    numOf x = case inferExpr env x of
      Just (SNum t) -> Just t
      _ -> Nothing
    member v [] = Just (valueType v)
    member (VHash m) (k : ks) = Map.lookup k m >>= \v -> member v ks
    member _ _ = Nothing

{- | The first place of an expression that takes a natural number and
whose value is known at S0 to be negative (G02103) or not an integer
(G02104) (docs/adr ADR 0102). A place whose type is a natural number
needs no check; one that refers to doc is checked when it is evaluated
at S1, with the same code and message.
-}
analyse :: Env -> Located Expr -> Maybe Diagnostic
analyse env (Located rsp e) = listToMaybe (mapMaybe (analyse env) (children e) <> here)
  where
    here = case e of
      ECall f [_, d]
        | f `elem` ["round", "fixed"],
          inferExpr env d /= Just (SNum TNat),
          "doc" `notElem` freeNames d,
          Right v <- evalExpr env d,
          Just diag <- digitsDiagnostic f d v ->
            [diag]
      -- an end whose type is known to be no number is G02110 (docs/adr ADR 0113)
      ERange a b -> take 1 [rangeEndDiagnostic rsp (endText x) | x <- [a, b], Just t <- [inferExpr env x], not (isNum t)]
      _ -> []
    isNum = \case
      SNum _ -> True
      _ -> False
    endText x = either (const "") valueText (evalExpr env x)

children :: Expr -> [Located Expr]
children = \case
  EArray xs -> xs
  EHash kvs -> map snd kvs
  ECall _ xs -> xs
  EUnary _ x -> [x]
  EBinary _ a b -> [a, b]
  ERange a b -> [a, b]
  _ -> []
