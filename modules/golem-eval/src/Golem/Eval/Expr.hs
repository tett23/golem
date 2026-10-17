{- | The expression evaluator (golem-eval ADR 0001). Pure; every failure is
a diagnostic at the position of the offending expression.
-}
module Golem.Eval.Expr
  ( Env (..),
    emptyEnv,
    evalExpr,
    embedValue,
    builtinNames,
    freeNames,
  )
where

import Data.Foldable (traverse_)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Number
import Golem.Eval.Value
import Golem.Parser.AST
import Golem.Syntax

data Env = Env
  { envVars :: !(Map Name Value),
    envNamespaces :: !(Map Name (Map Name Value))
  }

emptyEnv :: Env
emptyEnv = Env Map.empty Map.empty

type Eval = Either Diagnostic

err :: Text -> Located a -> Text -> Eval b
err code at msg = Left (diagnostic code Error (locSpan at) msg)

typeErr :: Located a -> Text -> Eval b
typeErr = err "G0201"

mkFloat :: Located a -> Double -> Eval Value
mkFloat at x = case finite x of
  Just y -> pure (VFloat y)
  Nothing -> err "G0204" at "結果が NaN か無限大になる演算です"

{- | An integer is below 2^4096 in absolute value (docs/adr ADR 0035);
a larger result of an operation is G0286.
-}
intLimit :: Integer
intLimit = 2 ^ (4096 :: Int)

-- | The most fractional digits of round and fixed (docs/adr ADR 0035).
maxDigits :: Integer
maxDigits = 1000

tooBig :: Located a -> Eval b
tooBig at = err "G0286" at "整数が大きすぎます（絶対値は 2 の 4096 乗未満に限ります）"

-- | An integer result, or G0286 when it is too large.
checkedInt :: Located a -> Integer -> Eval Value
checkedInt at i
  | abs i >= intLimit = tooBig at
  | otherwise = pure (VInt i)

builtinNames :: [Name]
builtinNames = ["pi", "e", "sqrt", "floor", "ceil", "round", "fixed", "abs", "min", "max", "len", "div"]

-- | Names referenced by an expression (first segment of each variable).
freeNames :: Located Expr -> [Name]
freeNames (Located _ e) = case e of
  EVar (n : _) -> [n]
  EArray xs -> concatMap freeNames xs
  EHash kvs -> concatMap (freeNames . snd) kvs
  ECall _ xs -> concatMap freeNames xs
  EUnary _ x -> freeNames x
  EBinary _ a b -> freeNames a <> freeNames b
  _ -> []

evalExpr :: Env -> Located Expr -> Eval Value
evalExpr env le@(Located _ e) = case e of
  EInt i -> pure (VInt i)
  EFloat d -> mkFloat le d
  EString s -> pure (VString s)
  EBool b -> pure (VBool b)
  ENil -> pure VNil
  EArray xs -> VArray <$> traverse (evalExpr env) xs
  EHash kvs -> VHash . Map.fromList <$> traverse (\(k, x) -> (k,) <$> evalExpr env x) kvs
  EVar [n] -> case Map.lookup n (envVars env) of
    Just v -> pure v
    Nothing
      | n == "pi" -> pure (VFloat pi)
      | n == "e" -> pure (VFloat (exp 1))
      | otherwise -> err "G0202" le ("未定義の名前 " <> n <> " です")
  EVar (ns : rest) -> case Map.lookup ns (envNamespaces env) of
    Nothing -> err "G0202" le ("未定義の名前空間 " <> ns <> " です")
    Just m -> lookupMember le (VHash m) rest
  EVar [] -> err "G0202" le "名前がありません"
  EUnary Negate x ->
    evalExpr env x >>= \case
      VInt i -> checkedInt le (negate i)
      VFloat d -> mkFloat le (negate d)
      v -> typeErr le ("- は " <> typeName v <> " に使えません")
  EBinary op a b -> do
    x <- evalExpr env a
    y <- evalExpr env b
    binary le op x y
  ECall f args -> traverse (evalExpr env) args >>= call le f
  EError -> err "G0120" le "式を解釈できません"

lookupMember :: Located Expr -> Value -> [Name] -> Eval Value
lookupMember _ v [] = pure v
lookupMember le (VHash m) (k : ks) = case Map.lookup k m of
  Just v -> lookupMember le v ks
  Nothing -> err "G0202" le ("未定義の名前 " <> k <> " です")
lookupMember le v _ = typeErr le (typeName v <> " の要素は参照できません")

asDouble :: Value -> Maybe Double
asDouble = \case
  VInt i -> Just (fromInteger i)
  VFloat d -> Just d
  _ -> Nothing

binary :: Located Expr -> BinaryOp -> Value -> Value -> Eval Value
binary le op x y = case op of
  Add -> arith (+) (+)
  Sub -> arith (-) (-)
  Mul -> arith (*) (*)
  Div -> case (asDouble x, asDouble y) of
    (Just _, Just 0) -> err "G0203" le "0 で割っています"
    (Just a, Just b) -> mkFloat le (a / b)
    _ -> mismatch
  Mod -> case (x, y) of
    (VInt _, VInt 0) -> err "G0203" le "0 で割っています"
    (VInt a, VInt b) -> pure (VInt (floorMod a b))
    _ -> typeErr le "% は整数にだけ使えます"
  Pow -> case (x, y) of
    (_, VFloat _) -> err "G0206" le "** の指数は整数に限ります"
    (VInt a, VInt k)
      -- the size is judged before the power is computed (docs/adr ADR 0035)
      | k == 0 -> pure (VInt 1)
      | k > 0, abs a <= 1 -> pure (VInt (a ^ k))
      | k > 0, k >= 4096 || abs a >= intLimit -> tooBig le
      | k > 0 -> checkedInt le (a ^ k)
      | a == 0 -> err "G0203" le "0 で割っています"
      | otherwise -> mkFloat le (1 / powInt (*) 1 (fromInteger a) (negate k))
    (VFloat a, VInt k)
      | k >= 0 -> mkFloat le (powInt (*) 1 a k)
      | a == 0 -> err "G0203" le "0 で割っています"
      | otherwise -> mkFloat le (1 / powInt (*) 1 a (negate k))
    _ -> mismatch
  OpEq -> pure (VBool (equal x y))
  OpNe -> pure (VBool (not (equal x y)))
  OpLt -> VBool . (== LT) <$> compareV
  OpLe -> VBool . (/= GT) <$> compareV
  OpGt -> VBool . (== GT) <$> compareV
  OpGe -> VBool . (/= LT) <$> compareV
  where
    mismatch = typeErr le (typeName x <> " と " <> typeName y <> " にこの演算子は使えません")
    arith :: (Integer -> Integer -> Integer) -> (Double -> Double -> Double) -> Eval Value
    arith fi fd = case (x, y) of
      (VInt a, VInt b) -> checkedInt le (fi a b)
      _ -> case (asDouble x, asDouble y) of
        (Just a, Just b) -> mkFloat le (fd a b)
        _ -> mismatch
    compareV = case (x, y) of
      (VString a, VString b) -> pure (compare (T.unpack a) (T.unpack b))
      (VInt a, VInt b) -> pure (compare a b)
      _ -> case (asDouble x, asDouble y) of
        (Just a, Just b) -> pure (compare a b)
        _ -> mismatch

equal :: Value -> Value -> Bool
equal a b = case (asDouble a, asDouble b, a, b) of
  (_, _, VInt i, VInt j) -> i == j
  (Just x, Just y, _, _) -> x == y
  _ -> a == b

call :: Located Expr -> Name -> [Value] -> Eval Value
call le f args = case (f, args) of
  ("sqrt", [v]) -> num v >>= \x -> if x < 0 then err "G0204" le "負の数の平方根です" else mkFloat le (sqrt x)
  ("floor", [VInt i]) -> pure (VInt i)
  ("floor", [VFloat d]) -> pure (VInt (floor d))
  ("ceil", [VInt i]) -> pure (VInt i)
  ("ceil", [VFloat d]) -> pure (VInt (ceiling d))
  ("round", [VInt i]) -> pure (VInt i)
  ("round", [VFloat d]) -> pure (VInt (decMantissa (roundHalfAway 0 d)))
  ("round", [_, VInt n]) | n > maxDigits -> tooManyDigits
  ("fixed", [_, VInt n]) | n > maxDigits -> tooManyDigits
  ("round", [v, VInt n]) | n >= 0 -> num v >>= \x -> mkFloat le (decimalToDouble (roundHalfAway (fromInteger n) x))
  ("fixed", [v, VInt n]) | n >= 0 -> num v >>= \x -> pure (VString (renderDecimalFixed (roundHalfAway (fromInteger n) x)))
  ("abs", [VInt i]) -> checkedInt le (abs i)
  ("abs", [VFloat d]) -> mkFloat le (abs d)
  ("min", v : vs) -> extreme (<) v vs
  ("max", v : vs) -> extreme (>) v vs
  ("len", [VString s]) -> pure (VInt (toInteger (T.length s)))
  ("len", [VArray xs]) -> pure (VInt (toInteger (length xs)))
  ("div", [VInt _, VInt 0]) -> err "G0203" le "0 で割っています"
  ("div", [VInt a, VInt b]) -> pure (VInt (floorDiv a b))
  ("div", [_, _]) -> typeErr le "div は整数にだけ使えます"
  _
    | f `elem` builtinNames -> err "G0207" le (f <> " の引数が不正です")
    | otherwise -> err "G0261" le ("未定義の関数 " <> f <> " です")
  where
    tooManyDigits = err "G0286" le "小数の桁数が多すぎます（1000 桁までです）"
    num v = maybe (typeErr le (typeName v <> " は数ではありません")) pure (asDouble v)
    -- min and max with no argument are G0207 above
    extreme better v vs = do
      traverse_ num (v : vs)
      pure (foldl (\a b -> if lessThan better b a then b else a) v vs)
    lessThan better a b = case (asDouble a, asDouble b) of
      (Just x, Just y) -> better x y
      _ -> False

-- | Text for embedding a value in prose; only numbers and strings.
embedValue :: SrcSpan -> Value -> Either Diagnostic Text
embedValue sp = \case
  VInt i -> Right (T.pack (show i))
  VFloat d -> Right (renderDouble d)
  VString s -> Right s
  v -> Left (diagnostic "G0208" Error sp (typeName v <> " は本文に埋め込めません"))
