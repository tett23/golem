{- | The expression evaluator (golem-eval ADR 0001, docs/adr ADR 0101).
Pure; every failure is a diagnostic at the position of the offending
expression. Numbers are natural numbers, integers and rationals, and
every operation is exact.
-}
module Golem.Eval.Expr
  ( Env (..),
    evalExpr,
    embedValue,
    freeNames,
    overLimit,
    tooBigDiagnostic,
    naturalDiagnostic,
    digitsDiagnostic,
  )
where

import Data.Char (isAlphaNum, isAscii)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
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

{- | The numerator and the denominator of a number are below 2^4096 in
absolute value (docs/adr ADR 0035, ADR 0101); a larger one is G02086.
-}
intLimit :: Integer
intLimit = 2 ^ (4096 :: Int)

-- | Whether a number is past the limit of 'intLimit'.
overLimit :: Rational -> Bool
overLimit q = abs (numerator q) >= intLimit || denominator q >= intLimit

tooBig :: Located a -> Eval b
tooBig at = Left (tooBigDiagnostic (locSpan at))

-- | G02086 at a span: a number past the limit of 'intLimit'.
tooBigDiagnostic :: SrcSpan -> Diagnostic
tooBigDiagnostic sp = diagnostic "G02086" Error sp "数が大きすぎます（整数と、分数の分子と分母の絶対値は 2 の 4096 乗未満に限ります）"

-- | A number of a type, or G02086 when it is too large.
checked :: Located a -> NumType -> Rational -> Eval Value
checked at t q
  | overLimit q = tooBig at
  | otherwise = pure (mkNumber t q)

-- | The value of a number that is an integer, of any type.
integral :: Value -> Maybe (NumType, Integer)
integral v = case numberOf v of
  Just (t, q) | denominator q == 1 -> Just (t, numerator q)
  _ -> Nothing

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
  ENat n -> checked le TNat (toRational n)
  EInt i -> checked le TInt (fromInteger i)
  ERat q -> checked le TRat q
  EString s -> pure (VString s)
  EBool b -> pure (VBool b)
  ENil -> pure VNil
  EArray xs -> VArray <$> traverse (evalExpr env) xs
  EHash kvs -> VHash . Map.fromList <$> traverse (\(k, x) -> (k,) <$> evalExpr env x) kvs
  EVar [n] -> case Map.lookup n (envVars env) of
    Just v -> pure v
    Nothing
      | n == "pi" -> pure (VRat piValue)
      | n == "e" -> pure (VRat eValue)
      | otherwise -> err "G02002" le ("未定義の名前 " <> n <> " です")
  EVar (ns : rest) -> case Map.lookup ns (envNamespaces env) of
    Nothing -> err "G02002" le ("未定義の名前空間 " <> ns <> " です")
    Just m -> lookupMember le (VHash m) rest
  EVar [] -> err "G02002" le "名前がありません"
  EUnary Negate x ->
    evalExpr env x >>= \v -> case numberOf v of
      Just (t, q) -> checked le (max TInt t) (negate q)
      Nothing -> typeErr le ("- は " <> typeName v <> " に使えません")
  EBinary op a b -> do
    x <- evalExpr env a
    y <- evalExpr env b
    binary le op x y
  ECall f args -> do
    vs <- traverse (evalExpr env) args
    case (args, vs) of
      ([_, d], [_, dv]) | Just diag <- digitsDiagnostic f d dv -> Left diag
      _ -> call le f vs
  EError -> err "G01020" le "式を解釈できません"

lookupMember :: Located Expr -> Value -> [Name] -> Eval Value
lookupMember _ v [] = pure v
lookupMember le (VHash m) (k : ks) = case Map.lookup k m of
  Just v -> lookupMember le v ks
  Nothing -> err "G02002" le ("未定義の名前 " <> k <> " です")
lookupMember le v _ = typeErr le (typeName v <> " の要素は参照できません")

{- | A number at a place that takes a natural number (docs/adr ADR 0102):
G02103 for a negative one, G02104 for one that is not an integer, with
the value written exactly; Nothing for a natural number. @what@ names
the place; a space comes between it and the Japanese when it ends in a
Latin letter (@listing の lines には).
-}
naturalDiagnostic :: Text -> SrcSpan -> Rational -> Maybe Diagnostic
naturalDiagnostic what sp q
  | q < 0 = Just (diagnostic "G02103" Error sp (place <> "には 0 以上の整数を書きます（書かれた値は " <> exactText q <> "）"))
  | denominator q /= 1 = Just (diagnostic "G02104" Error sp (place <> "には 0 以上の整数を書きます（書かれた値 " <> exactText q <> " は整数ではありません）"))
  | otherwise = Nothing
  where
    place = case T.unsnoc what of
      Just (_, c) | isAscii c && isAlphaNum c -> what <> " "
      _ -> what

{- | The number of digits of round and fixed, the second argument, when it
is a number that is no natural number; Nothing otherwise.
-}
digitsDiagnostic :: Name -> Located Expr -> Value -> Maybe Diagnostic
digitsDiagnostic f d v
  | f `elem` ["round", "fixed"], Just (_, q) <- numberOf v = naturalDiagnostic (f <> " の桁数") (locSpan d) q
  | otherwise = Nothing

-- | The order of two numbers, by their values whatever their types.
compareNum :: Value -> Value -> Maybe Ordering
compareNum a b = compare . snd <$> numberOf a <*> (snd <$> numberOf b)

binary :: Located Expr -> BinaryOp -> Value -> Value -> Eval Value
binary le op x y = case op of
  Add -> arith (+) max
  Sub -> arith (-) (\s t -> max TInt (max s t))
  Mul -> arith (*) max
  Div -> case (numberOf x, numberOf y) of
    (Just _, Just (_, 0)) -> err "G02003" le "0 で割っています"
    (Just (_, a), Just (_, b)) -> checked le TRat (a / b)
    _ -> mismatch
  Mod -> case (integral x, integral y) of
    (Just _, Just (_, 0)) -> err "G02003" le "0 で割っています"
    -- the remainder has the sign of the divisor: of 0 or more for a natural one
    (Just (_, a), Just (t, b)) -> checked le (if t == TNat then TNat else TInt) (fromInteger (floorMod a b))
    _ -> typeErr le "% は整数にだけ使えます"
  Pow -> case numberOf y of
    Just (_, k) | denominator k /= 1 -> err "G02006" le "** の指数は整数に限ります"
    _ -> case (numberOf x, integral y) of
      (Just (s, a), Just (t, k)) -> power le (if t == TNat then s else TRat) a k
      _ -> mismatch
  OpEq -> pure (VBool (equal x y))
  OpNe -> pure (VBool (not (equal x y)))
  OpLt -> VBool . (== LT) <$> compareV
  OpLe -> VBool . (/= GT) <$> compareV
  OpGt -> VBool . (== GT) <$> compareV
  OpGe -> VBool . (/= LT) <$> compareV
  where
    mismatch = typeErr le (typeName x <> " と " <> typeName y <> " にこの演算子は使えません")
    arith :: (Rational -> Rational -> Rational) -> (NumType -> NumType -> NumType) -> Eval Value
    arith f ty = case (numberOf x, numberOf y) of
      (Just (s, a), Just (t, b)) -> checked le (ty s t) (f a b)
      _ -> mismatch
    compareV = case (x, y) of
      (VString a, VString b) -> pure (compare (T.unpack a) (T.unpack b))
      _ -> maybe mismatch pure (compareNum x y)

{- | @a ** k@ for an integer @k@, exact (docs/adr ADR 0101). The size is
judged before the power is computed: with @a@ the numerator or the
denominator of the base in absolute value, @(bits of a - 1) × |k|@ of
4096 or more is G02086. The base is in lowest terms, so the power is too,
and the numerator and the denominator are raised apart.
-}
power :: Located Expr -> NumType -> Rational -> Integer -> Eval Value
power le t a k
  | k == 0 = checked le t 1
  | a == 0, k > 0 = checked le t 0
  | a == 0 = err "G02003" le "0 で割っています"
  | any (\m -> bitsLess1 m * abs k >= 4096) [abs n, d] = tooBig le
  | otherwise =
      let n' = n ^ abs k
          d' = d ^ abs k
       in checked le t (if k > 0 then n' % d' else d' % n')
  where
    n = numerator a
    d = denominator a
    bitsLess1 m = toInteger (integerLog2 m)

-- | Equality by value: numbers whatever their types, inside arrays and hashes too.
equal :: Value -> Value -> Bool
equal a b = case (numberOf a, numberOf b) of
  (Just (_, p), Just (_, q)) -> p == q
  _ -> case (a, b) of
    (VArray xs, VArray ys) -> length xs == length ys && and (zipWith equal xs ys)
    (VHash m, VHash n) -> Map.keys m == Map.keys n && and (zipWith equal (Map.elems m) (Map.elems n))
    _ -> a == b

call :: Located Expr -> Name -> [Value] -> Eval Value
call le f args = case (f, args) of
  ("sqrt", [v]) ->
    num v >>= \(_, q) ->
      if q < 0 then err "G02101" le "負の数の平方根は求められません" else checked le TRat (sqrtRational q)
  ("floor", [v]) | Just (t, q) <- numberOf v -> checked le (min TInt t) (fromInteger (floor q))
  ("ceil", [v]) | Just (t, q) <- numberOf v -> checked le (min TInt t) (fromInteger (ceiling q))
  ("round", [v]) | Just (t, q) <- numberOf v -> checked le (min TInt t) (fromInteger (roundHalfAway q))
  ("round", [_, d]) | Just (_, n) <- integral d, n > maxFractionDigits -> tooManyDigits
  ("fixed", [_, d]) | Just (_, n) <- integral d, n > maxFractionDigits -> tooManyDigits
  ("round", [v, d]) | Just (_, n) <- integral d, n >= 0 -> num v >>= \(t, q) -> checked le t (roundTo n q)
  ("fixed", [v, d]) | Just (_, n) <- integral d, n >= 0 -> num v >>= \(_, q) -> pure (VString (renderFixed n (roundTo n q)))
  ("abs", [v]) | Just (t, q) <- numberOf v -> checked le (if t == TRat then TRat else TNat) (abs q)
  ("min", v : vs) -> extreme LT v vs
  ("max", v : vs) -> extreme GT v vs
  ("len", [VString s]) -> pure (VNat (fromIntegral (T.length s)))
  ("len", [VArray xs]) -> pure (VNat (fromIntegral (length xs)))
  ("div", [a, b]) -> case (integral a, integral b) of
    (Just _, Just (_, 0)) -> err "G02003" le "0 で割っています"
    (Just (s, x), Just (t, y)) -> checked le (if s == TNat && t == TNat then TNat else TInt) (fromInteger (floorDiv x y))
    _ -> typeErr le "div は整数にだけ使えます"
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
    num v = maybe (typeErr le (typeName v <> " は数ではありません")) pure (numberOf v)
    -- min and max with no argument are G02007 above; the values are compared
    -- exactly, the earlier of equal ones is kept, and it is widened to the
    -- widest type of the arguments (docs/adr ADR 0101)
    extreme better v vs = do
      ns <- traverse num (v : vs)
      let pick (s, a) (t, b) = if compare b a == better then (t, b) else (s, a)
          (_, q) = foldl1 pick ns
      checked le (maximum (map fst ns)) q

{- | Text for embedding a value in prose; only numbers and strings. A
number is written by its value alone (docs/adr ADR 0101); one of more than
1000 fractional digits is G02102.
-}
embedValue :: SrcSpan -> Value -> Either Diagnostic Text
embedValue sp v = case (numberOf v, v) of
  (Just (_, q), _) -> case renderNumber q of
    Right t -> Right t
    Left _ -> Left (diagnostic "G02102" Error sp "小数点以下が 1000 桁を超える数は本文に埋め込めません。round か fixed で桁数を決めます")
  (_, VString s) -> Right s
  _ -> Left (diagnostic "G02008" Error sp (typeName v <> " は本文に埋め込めません"))
