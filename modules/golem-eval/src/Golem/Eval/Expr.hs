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

{- | A number as a double: an integer is rounded to the nearest double, ties
to even; one that rounds to infinity is G0204 (golem-eval ADR 0005).
Nothing for a value that is not a number.
-}
asDouble :: Located a -> Value -> Maybe (Eval Double)
asDouble at = \case
  VInt i
    | isInfinite d -> Just (err "G0204" at "整数が大きすぎて浮動小数点数に変換できません")
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
    (_, VInt 0) | isNum x -> err "G0203" le "0 で割っています"
    (_, VFloat 0) | isNum x -> err "G0203" le "0 で割っています"
    -- the exact quotient rounded once (golem-eval ADR 0005)
    (VInt a, VInt b) -> mkFloat le (fromRational (a % b))
    _ -> case (asDouble le x, asDouble le y) of
      (Just ea, Just eb) -> do
        a <- ea
        b <- eb
        mkFloat le (a / b)
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
      | otherwise -> rounded (fromInteger a) k
    (VFloat a, VInt k)
      | k == 0 -> pure (VFloat 1)
      | a == 0, k > 0 -> pure (VFloat 0)
      | a == 0 -> err "G0203" le "0 で割っています"
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
      PowOverflow -> err "G0204" le "結果が NaN か無限大になる演算です"
      PowTooLarge -> err "G0286" le "累乗の計算が大きすぎます"
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
  ("min", v : vs) -> extreme LT v vs
  ("max", v : vs) -> extreme GT v vs
  ("len", [VString s]) -> pure (VInt (toInteger (T.length s)))
  ("len", [VArray xs]) -> pure (VInt (toInteger (length xs)))
  ("div", [VInt _, VInt 0]) -> err "G0203" le "0 で割っています"
  ("div", [VInt a, VInt b]) -> pure (VInt (floorDiv a b))
  ("div", [_, _]) -> typeErr le "div は整数にだけ使えます"
  -- the strings of an array with a separator between them (docs/adr ADR 0033)
  ("join", [VArray xs, VString s])
    | Just ts <- traverse (\case VString t -> Just t; _ -> Nothing) xs -> pure (VString (T.intercalate s ts))
    | otherwise -> typeErr le "join の配列には文字列だけを並べます"
  ("join", [_, _]) -> typeErr le "join は文字列の配列と区切りの文字列に使えます"
  _
    | f `elem` builtinNames -> err "G0207" le (f <> " の引数が不正です")
    | otherwise -> err "G0261" le ("未定義の関数 " <> f <> " です")
  where
    tooManyDigits = err "G0286" le "小数の桁数が多すぎます（1000 桁までです）"
    num v = fromMaybe (typeErr le (typeName v <> " は数ではありません")) (asDouble le v)
    -- min and max with no argument are G0207 above; the values are compared
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
  v -> Left (diagnostic "G0208" Error sp (typeName v <> " は本文に埋め込めません"))

{- | The largest exact power, in bits: the bits of the odd part of the
base, less one, times the exponent (golem-eval ADR 0005). The judgement
looks at this alone. Raising it changes no result within it, since a
result is the exact value rounded once.
-}
maxExactBits :: Integer
maxExactBits = 2 ^ (20 :: Int)

-- | A power with a rational base, rounded once (golem-eval ADR 0005).
data PowResult
  = -- | the nearest double; zero for a result that rounds to zero
    PowValue !Double
  | -- | the result rounds to infinity (G0204)
    PowOverflow
  | -- | the exact power is over 'maxExactBits' (G0286)
    PowTooLarge
  deriving stock (Eq, Show)

{- | @a ^^ k@, for a base and an exponent that are not 0, rounded once to
the nearest double, ties to even. The size is estimated first ('estimatePow'),
so that a result far out of the range of doubles is not computed exactly:
at least 2^1025 is infinity, below 2^-1076 is zero.
-}
powRounded :: Rational -> Integer -> PowResult
powRounded a k
  | e >= 1025 = PowOverflow
  | e < -1076 = PowValue 0
  | log2 m * abs k > maxExactBits = PowTooLarge
  | otherwise = maybe PowOverflow PowValue (finite (fromRational (a ^^ k)))
  where
    e = snd (estimatePow (abs a) k)
    -- the base is ±m × 2^e' with m odd (the other part of the fraction is a power of 2)
    m = max (oddPart (numerator a)) (oddPart (denominator a))
    oddPart n = abs n `shiftR` fromInteger (log2 (abs n .&. negate (abs n)))

-- | The bits of a positive integer, less one.
log2 :: Integer -> Integer
log2 = toInteger . integerLog2

{- | The size of @q ^^ k@ for a positive @q@ and an exponent that is not 0,
as a mantissa in [1, 2) and an integer exponent: the log2 of the result is
in [e, e + 1). Repeated squaring of doubles, the mantissa brought back into
[1, 2) after each product, so that nothing overflows or becomes 0; no
'log', so that the estimate is deterministic (golem-eval ADR 0005).
-}
estimatePow :: Rational -> Integer -> (Double, Integer)
estimatePow q k
  | k < 0 = invert (go (abs k) (split q) (1, 0))
  | otherwise = go k (split q) (1, 0)
  where
    go :: Integer -> (Double, Integer) -> (Double, Integer) -> (Double, Integer)
    go 0 _ acc = acc
    go n b acc = go (n `div` 2) (mul b b) (if odd n then mul acc b else acc)
    mul (m1, e1) (m2, e2) =
      let m' = m1 * m2
       in if m' >= 2 then (m' / 2, e1 + e2 + 1) else (m', e1 + e2)
    invert (m', e')
      | m' == 1 = (1, negate e')
      | otherwise = (2 / m', negate e' - 1)

-- | A positive rational as a mantissa in [1, 2) and an integer exponent.
split :: Rational -> (Double, Integer)
split q =
  let e0 = log2 (numerator q) - log2 (denominator q)
      e = if q < 2 ^^ e0 then e0 - 1 else e0
      m = fromRational (q / 2 ^^ e) :: Double
   in if m >= 2 then (1, e + 1) else (m, e)
