{- | The expression evaluator (golem-eval ADR 0001). Pure; every failure is
a diagnostic at the position of the offending expression.
-}
module Golem.Eval.Expr
  ( Env (..),
    evalExpr,
    embedValue,
    builtinNames,
    freeNames,
    PowResult (..),
    powRounded,
    maxExactBits,
  )
where

import Data.Bits (shiftR, (.&.))
import Data.Foldable (traverse_)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Ratio (denominator, numerator, (%))
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Num.Integer (integerLog2)
import Golem.Eval.Number
import Golem.Eval.Value
import Golem.Parser.AST
import Golem.Syntax

data Env = Env
  { envVars :: !(Map Name Value),
    envNamespaces :: !(Map Name (Map Name Value))
  }

type Eval = Either Diagnostic

err :: Text -> Located a -> Text -> Eval b
err code at msg = Left (diagnostic code Error (locSpan at) msg)

typeErr :: Located a -> Text -> Eval b
typeErr = err "G02001"

mkFloat :: Located a -> Double -> Eval Value
mkFloat at x = case finite x of
  Just y -> pure (VFloat y)
  Nothing -> err "G02004" at "結果が NaN か無限大になる演算です"

{- | An integer is below 2^4096 in absolute value (docs/adr ADR 0035);
a larger result of an operation is G02086.
-}
intLimit :: Integer
intLimit = 2 ^ (4096 :: Int)

-- | The most fractional digits of round and fixed (docs/adr ADR 0035).
maxDigits :: Integer
maxDigits = 1000

tooBig :: Located a -> Eval b
tooBig at = err "G02086" at "整数が大きすぎます（絶対値は 2 の 4096 乗未満に限ります）"

-- | An integer result, or G02086 when it is too large.
checkedInt :: Located a -> Integer -> Eval Value
checkedInt at i
  | abs i >= intLimit = tooBig at
  | otherwise = pure (VInt i)

builtinNames :: [Name]
builtinNames = ["pi", "e", "sqrt", "floor", "ceil", "round", "fixed", "abs", "min", "max", "len", "div", "join"]

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
      | otherwise -> err "G02002" le ("未定義の名前 " <> n <> " です")
  EVar (ns : rest) -> case Map.lookup ns (envNamespaces env) of
    Nothing -> err "G02002" le ("未定義の名前空間 " <> ns <> " です")
    Just m -> lookupMember le (VHash m) rest
  EVar [] -> err "G02002" le "名前がありません"
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
  EError -> err "G01020" le "式を解釈できません"

lookupMember :: Located Expr -> Value -> [Name] -> Eval Value
lookupMember _ v [] = pure v
lookupMember le (VHash m) (k : ks) = case Map.lookup k m of
  Just v -> lookupMember le v ks
  Nothing -> err "G02002" le ("未定義の名前 " <> k <> " です")
lookupMember le v _ = typeErr le (typeName v <> " の要素は参照できません")

{- | A number as a double: an integer is rounded to the nearest double, ties
to even; one that rounds to infinity is G02004 (golem-eval ADR 0005).
Nothing for a value that is not a number.
-}
asDouble :: Located a -> Value -> Maybe (Eval Double)
asDouble at = \case
  VInt i
    | isInfinite d -> Just (err "G02004" at "整数が大きすぎて浮動小数点数に変換できません")
    | otherwise -> Just (pure d)
    where
      d = fromInteger i :: Double
  VFloat d -> Just (pure d)
  _ -> Nothing

-- | A number as an exact rational; a double is finite, so it has one.
asRational :: Value -> Maybe Rational
asRational = \case
  VInt i -> Just (fromInteger i)
  VFloat d -> Just (toRational d)
  _ -> Nothing

{- | The order of two numbers, compared exactly: integers as integers, an
integer and a double as rationals (golem-eval ADR 0005).
-}
compareNum :: Value -> Value -> Maybe Ordering
compareNum a b = case (a, b) of
  (VInt i, VInt j) -> Just (compare i j)
  (VFloat x, VFloat y) -> Just (compare x y)
  _ -> compare <$> asRational a <*> asRational b

binary :: Located Expr -> BinaryOp -> Value -> Value -> Eval Value
binary le op x y = case op of
  Add -> arith (+) (+)
  Sub -> arith (-) (-)
  Mul -> arith (*) (*)
  Div -> case (x, y) of
    (_, VInt 0) | isNum x -> err "G02003" le "0 で割っています"
    (_, VFloat 0) | isNum x -> err "G02003" le "0 で割っています"
    -- the exact quotient rounded once (golem-eval ADR 0005)
    (VInt a, VInt b) -> mkFloat le (fromRational (a % b))
    _ -> case (asDouble le x, asDouble le y) of
      (Just ea, Just eb) -> do
        a <- ea
        b <- eb
        mkFloat le (a / b)
      _ -> mismatch
  Mod -> case (x, y) of
    (VInt _, VInt 0) -> err "G02003" le "0 で割っています"
    (VInt a, VInt b) -> pure (VInt (floorMod a b))
    _ -> typeErr le "% は整数にだけ使えます"
  Pow -> case (x, y) of
    (_, VFloat _) -> err "G02006" le "** の指数は整数に限ります"
    (VInt a, VInt k)
      -- the size is judged before the power is computed (docs/adr ADR 0035)
      | k == 0 -> pure (VInt 1)
      | k > 0, abs a <= 1 -> pure (VInt (a ^ k))
      | k > 0, k >= 4096 || abs a >= intLimit -> tooBig le
      | k > 0 -> checkedInt le (a ^ k)
      | a == 0 -> err "G02003" le "0 で割っています"
      | otherwise -> rounded (fromInteger a) k
    (VFloat a, VInt k)
      | k == 0 -> pure (VFloat 1)
      | a == 0, k > 0 -> pure (VFloat 0)
      | a == 0 -> err "G02003" le "0 で割っています"
      | otherwise -> rounded (toRational a) k
    _ -> mismatch
  OpEq -> pure (VBool (equal x y))
  OpNe -> pure (VBool (not (equal x y)))
  OpLt -> VBool . (== LT) <$> compareV
  OpLe -> VBool . (/= GT) <$> compareV
  OpGt -> VBool . (== GT) <$> compareV
  OpGe -> VBool . (/= LT) <$> compareV
  where
    mismatch = typeErr le (typeName x <> " と " <> typeName y <> " にこの演算子は使えません")
    isNum v = case v of
      VInt _ -> True
      VFloat _ -> True
      _ -> False
    rounded a k = case powRounded a k of
      PowValue d -> pure (VFloat d)
      PowOverflow -> err "G02004" le "結果が NaN か無限大になる演算です"
      PowTooLarge n -> err "G02095" le ("累乗の正確な計算に要るビットの数 " <> T.pack (show n) <> " が、上限の 1048576（2 の 20 乗）を超えます（結果の大きさによらない上限です）")
    arith :: (Integer -> Integer -> Integer) -> (Double -> Double -> Double) -> Eval Value
    arith fi fd = case (x, y) of
      (VInt a, VInt b) -> checkedInt le (fi a b)
      _ -> case (asDouble le x, asDouble le y) of
        (Just ea, Just eb) -> do
          a <- ea
          b <- eb
          mkFloat le (fd a b)
        _ -> mismatch
    compareV = case (x, y) of
      (VString a, VString b) -> pure (compare (T.unpack a) (T.unpack b))
      _ -> maybe mismatch pure (compareNum x y)

equal :: Value -> Value -> Bool
equal a b = case compareNum a b of
  Just o -> o == EQ
  Nothing -> a == b

call :: Located Expr -> Name -> [Value] -> Eval Value
call le f args = case (f, args) of
  ("sqrt", [v]) -> num v >>= \x -> if x < 0 then err "G02004" le "負の数の平方根です" else mkFloat le (sqrt x)
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
  ("min", v : vs) -> extreme LT v vs
  ("max", v : vs) -> extreme GT v vs
  ("len", [VString s]) -> pure (VInt (toInteger (T.length s)))
  ("len", [VArray xs]) -> pure (VInt (toInteger (length xs)))
  ("div", [VInt _, VInt 0]) -> err "G02003" le "0 で割っています"
  ("div", [VInt a, VInt b]) -> pure (VInt (floorDiv a b))
  ("div", [_, _]) -> typeErr le "div は整数にだけ使えます"
  -- the strings of an array with a separator between them (docs/adr ADR 0033)
  ("join", [VArray xs, VString s])
    | Just ts <- traverse (\case VString t -> Just t; _ -> Nothing) xs -> pure (VString (T.intercalate s ts))
    | otherwise -> typeErr le "join の配列には文字列だけを並べます"
  ("join", [_, _]) -> typeErr le "join は文字列の配列と区切りの文字列に使えます"
  _
    | f `elem` builtinNames -> err "G02007" le (f <> " の引数が不正です")
    | otherwise -> err "G02061" le ("未定義の関数 " <> f <> " です")
  where
    tooManyDigits = err "G02086" le "小数の桁数が多すぎます（1000 桁までです）"
    num v = fromMaybe (typeErr le (typeName v <> " は数ではありません")) (asDouble le v)
    -- min and max with no argument are G02007 above; the values are compared
    -- exactly, and the earlier of equal ones is kept (golem-eval ADR 0005)
    extreme better v vs = do
      traverse_ isNumber (v : vs)
      pure (foldl (\a b -> if compareNum b a == Just better then b else a) v vs)
    isNumber v = maybe (typeErr le (typeName v <> " は数ではありません")) (const (pure ())) (asRational v)

-- | Text for embedding a value in prose; only numbers and strings.
embedValue :: SrcSpan -> Value -> Either Diagnostic Text
embedValue sp = \case
  VInt i -> Right (T.pack (show i))
  VFloat d -> Right (renderDouble d)
  VString s -> Right s
  v -> Left (diagnostic "G02008" Error sp (typeName v <> " は本文に埋め込めません"))

{- | The largest exact power, in bits: the bits of the odd part of the
base, less one, times the exponent (golem-eval ADR 0005, ADR 0006). The
judgement looks at this alone, before the range. Raising it changes no
result within it, since a result is the exact value rounded once.
-}
maxExactBits :: Integer
maxExactBits = 2 ^ (20 :: Int)

-- | A power with a rational base, rounded once (golem-eval ADR 0005).
data PowResult
  = -- | the nearest double; zero for a result that rounds to zero
    PowValue !Double
  | -- | the result rounds to infinity (G02004)
    PowOverflow
  | -- | the exact power needs this many bits, over 'maxExactBits' (G02095)
    PowTooLarge !Integer
  deriving stock (Eq, Show)

{- | @a ^^ k@, for a base and an exponent that are not 0, rounded once to
the nearest double, ties to even (golem-eval ADR 0006). Every judgement is
on integers: first the limit of the exact computation, then the range
from the bits of the exact power, so that the result depends on the input
alone and on no estimate. With @|a| = m × 2^f@, @m@ odd, the exact power is
@m^|k| × 2^(f × k)@ or its reciprocal; at least 2^1024 is infinity, at
most 2^-1075 (halfway to the least subnormal) is zero.
-}
powRounded :: Rational -> Integer -> PowResult
powRounded a k
  | bitsNeeded > maxExactBits = PowTooLarge bitsNeeded
  | lo >= 1024 = PowOverflow
  | hi <= -1075 = PowValue 0
  | otherwise = maybe PowOverflow PowValue (finite (withSign (fromRational exact)))
  where
    (m, f) = oddAndPowerOfTwo (abs a)
    bitsNeeded = log2 m * abs k
    p = m ^ abs k
    big = f * k
    l = log2 p + 1
    -- 2^lo <= |result| < 2^hi for k > 0; 2^lo < |result| <= 2^hi for k < 0
    (lo, hi)
      | k > 0 = (l - 1 + big, l + big)
      | otherwise = (big - l, big - l + 1)
    exact
      | k > 0 = fromInteger p * 2 ^^ big
      | otherwise = 2 ^^ big / fromInteger p
    withSign d = if a < 0 && odd k then negate d else d

{- | A positive rational whose denominator is a power of 2 (an integer or
a double) as @m × 2^f@ with @m@ odd.
-}
oddAndPowerOfTwo :: Rational -> (Integer, Integer)
oddAndPowerOfTwo q =
  let (mn, fn) = twos (numerator q)
      (md, fd) = twos (denominator q)
   in (mn * md, fn - fd)
  where
    twos n =
      let z = log2 (n .&. negate n)
       in (n `shiftR` fromInteger z, z)

-- | The bits of a positive integer, less one.
log2 :: Integer -> Integer
log2 = toInteger . integerLog2
