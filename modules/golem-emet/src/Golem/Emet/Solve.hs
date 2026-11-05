{- | The solving of the constraints of types (docs/adr/0160). The check
('Golem.Emet.Check') collects constraints and never unifies; this module
solves them, apart from the collection, so that type classes can come
later as instances in the table of 'holds' without a new checker
(「型クラスの余地」).

The constraints are the equality of two types, the widening of numbers
(a type accepted where another is expected), the three predicates of the
operators, and the result types of arithmetic. Solving repeats the
constraints that can be decided until none can; then, at the end of a
function, a constraint left on variables is decided by defaults, one at a
time and in the order of the constraints, so that the result does not
depend on anything but the source:

1. a variable that numbers widen into becomes the widest of them;
2. a variable that widens into numbers becomes the narrowest of them;
3. a variable that widens into a variable becomes it;
4. the operands of arithmetic that are both variables become Rat, and a
   variable beside a number becomes that number's type;
5. a variable that must be a number becomes Rat.
-}
module Golem.Emet.Solve
  ( Constraint (..),
    ArithOp (..),
    SolveState (..),
    emptySolveState,
    freshMeta,
    zonk,
    solve,
  )
where

import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (find)
import Data.Maybe (isJust)
import Data.Text (Text)
import Golem.Emet.Syntax (Loc)
import Golem.Emet.Types

data ArithOp = AAdd | ASub | AMul | ADiv | AMod | APow | ADivInt
  deriving stock (Eq, Show)

data Constraint
  = -- | the two types are the same
    KEq !Loc !Ty !Ty
  | -- | a value of the first type is accepted where the second is expected
    KSub !Loc !Ty !Ty
  | -- | the type satisfies the predicate; the text names the operator
    KPred !Loc !Text !Pred !Ty
  | -- | the operands of arithmetic and its result
    KArith !Loc !ArithOp !Ty !Ty !Ty
  | -- | the operand of the unary minus and its result
    KNeg !Loc !Ty !Ty
  deriving stock (Show)

data SolveState = SolveState
  { ssNext :: !Int,
    ssSubst :: !(IntMap Ty),
    -- | the constraints not solved yet, in their order
    ssPending :: ![Constraint]
  }

emptySolveState :: SolveState
emptySolveState = SolveState 0 IntMap.empty []

freshMeta :: SolveState -> (Ty, SolveState)
freshMeta s = (TM (ssNext s), s {ssNext = ssNext s + 1})

zonk :: SolveState -> Ty -> Ty
zonk s = go
  where
    go = \case
      TM i -> maybe (TM i) go (IntMap.lookup i (ssSubst s))
      TC c as -> TC c (map go as)
      TF a b -> TF (go a) (go b)
      t -> t

-- | The head of a type after the substitution, its arguments not resolved.
whnf :: SolveState -> Ty -> Ty
whnf s = \case
  TM i | Just t <- IntMap.lookup i (ssSubst s) -> whnf s t
  t -> t

-- | What one step does to a constraint.
data Step
  = Solved
  | Stuck
  | Into ![Constraint]
  | Failed !Loc !Text

{- | Solves the pending constraints with these new ones after them. With
@final@, the constraints left on variables are decided by the defaults;
without, they stay pending (a @where@ before its bindings are
generalised). The first error is a location and a message of E02101.
-}
solve :: Bool -> [Constraint] -> SolveState -> Either (Loc, Text) SolveState
solve final new s0 = loop s0 {ssPending = ssPending s0 <> new}
  where
    loop s = do
      (progress, s') <- pass s
      if progress
        then loop s'
        else
          if final
            then case defaulting s' of
              Just s'' -> loop s''
              Nothing -> pure s' {ssPending = []}
            else pure s'

    -- one pass over the pending constraints
    pass s = go False s {ssPending = []} (ssPending s)
      where
        go progress st = \case
          [] -> Right (progress, st {ssPending = reverse (ssPending st)})
          c : rest -> case step st c of
            (Failed l m, _) -> Left (l, m)
            (Solved, st') -> go True st' rest
            (Stuck, st') -> go progress st' {ssPending = c : ssPending st'} rest
            (Into cs, st') -> go True st' (cs <> rest)

step :: SolveState -> Constraint -> (Step, SolveState)
step s = \case
  KEq l a b -> case unify s a b of
    Just s' -> (Solved, s')
    Nothing -> (mismatch l a b, s)
  KSub l a b -> sub l (whnf s a) (whnf s b)
  KPred l op p t -> case whnf s t of
    TM _ -> (Stuck, s)
    t'
      | holds p t' -> (Solved, s)
      | otherwise -> (Failed l (op <> " は " <> predText p <> " にだけ使えます（" <> showTy (zonk s t') <> " があります）"), s)
  KArith l op a b r -> case (rankOf (whnf s a), rankOf (whnf s b)) of
    (Just x, Just y) -> case arith op x y of
      Right k -> (Into [KEq l r (rankTy k)], s)
      Left m -> (Failed l m, s)
    _ -> (Stuck, s)
  KNeg l a r -> case rankOf (whnf s a) of
    Just x -> (Into [KEq l r (rankTy (max 1 x))], s)
    Nothing -> (Stuck, s)
  where
    sub l a b = case (a, b) of
      (TC c [], TC d []) | Just x <- numRank c, Just y <- numRank d -> if x <= y then (Solved, s) else (mismatch l b a, s)
      (TC c as, TC d bs) | c == d, covariant c, length as == length bs -> (Into (zipWith (KSub l) as bs), s)
      (TM _, TM _) -> (Stuck, s)
      (TM _, t) | isNumber t -> (Stuck, s)
      (t, TM _) | isNumber t -> (Stuck, s)
      (TM i, TC c as) | covariant c -> shape l i c as (\t -> KSub l t b)
      (TC c as, TM i) | covariant c -> shape l i c as (KSub l a)
      _ -> case unify s a b of
        Just s' -> (Solved, s')
        Nothing -> (mismatch l b a, s)
    -- a variable takes the constructor of the other side, with new variables
    shape _ i c as k =
      let (ms, s') = foldr (\_ (acc, st) -> let (m, st') = freshMeta st in (m : acc, st')) ([], s) as
          t = TC c ms
       in (Into [k t], s' {ssSubst = IntMap.insert i t (ssSubst s')})
    mismatch l expected actual =
      Failed l ("型が合いません: " <> showTy (zonk s expected) <> " を求める位置に " <> showTy (zonk s actual) <> " があります")

isNumber :: Ty -> Bool
isNumber = \case
  TC c [] -> isJust (numRank c)
  _ -> False

rankOf :: Ty -> Maybe Int
rankOf = \case
  TC c [] -> numRank c
  _ -> Nothing

{- | The rank of the result of arithmetic on numbers of two ranks, by the
rules of the expression context (docs/adr/0101): @-@ makes an integer at
least, @/@ a rational; @%@ and @div@ take integers, and @%@ makes a natural
number for a natural divisor, @div@ for two natural numbers; @**@ takes an
integral exponent and makes a rational for an integer one.
-}
arith :: ArithOp -> Int -> Int -> Either Text Int
arith op x y = case op of
  AAdd -> Right (max x y)
  AMul -> Right (max x y)
  ASub -> Right (max 1 (max x y))
  ADiv -> Right 2
  AMod -> integral "%" >> Right (if y == 0 then 0 else 1)
  ADivInt -> integral "div" >> Right (if max x y == 0 then 0 else 1)
  APow
    | y > 1 -> Left "** の指数は整数（Nat、Int）に限ります"
    | otherwise -> Right (if y == 0 then x else 2)
  where
    integral what
      | max x y > 1 = Left (what <> " は整数（Nat、Int）にだけ使えます")
      | otherwise = Right ()

-- | Unification; Nothing when the types cannot be the same.
unify :: SolveState -> Ty -> Ty -> Maybe SolveState
unify s x y = case (whnf s x, whnf s y) of
  (TM i, TM j) | i == j -> Just s
  (TM i, t) -> bind i t
  (t, TM i) -> bind i t
  (TC c as, TC d bs) | c == d && length as == length bs -> unifyAll s (zip as bs)
  (TF a1 b1, TF a2 b2) -> unifyAll s [(a1, a2), (b1, b2)]
  (TS i _, TS j _) | i == j -> Just s
  _ -> Nothing
  where
    bind i t
      | i `elem` metasOf (zonk s t) = Nothing
      | otherwise = Just s {ssSubst = IntMap.insert i t (ssSubst s)}

unifyAll :: SolveState -> [(Ty, Ty)] -> Maybe SolveState
unifyAll = foldl (\acc (a, b) -> acc >>= \st -> unify st a b) . Just

{- | The first default that applies to the pending constraints (all of
them stuck), as the module's header lists; Nothing when none does.
-}
defaulting :: SolveState -> Maybe SolveState
defaulting s = firstJust [lower, upper, metaPair, arithmetic, number]
  where
    pending = ssPending s
    set i t = s {ssSubst = IntMap.insert i t (ssSubst s)}
    metaOf t = case whnf s t of
      TM i -> Just i
      _ -> Nothing
    lowers i = [r | KSub _ a b <- pending, metaOf b == Just i, Just r <- [rankOf (whnf s a)]]
    uppers i = [r | KSub _ a b <- pending, metaOf a == Just i, Just r <- [rankOf (whnf s b)]]
    lower = do
      i <- firstJust [metaOf b | KSub _ a b <- pending, isNumber (whnf s a)]
      pure (set i (rankTy (maximum (lowers i))))
    upper = do
      i <- firstJust [metaOf a | KSub _ a b <- pending, isNumber (whnf s b)]
      pure (set i (rankTy (minimum (uppers i))))
    metaPair = do
      (i, t) <- firstJust [(,b) <$> metaOf a | KSub _ a b <- pending, Just _ <- [metaOf b]]
      unify s (TM i) t
    arithmetic = do
      (a, b) <- find (\(a, b) -> isJust (metaOf a) || isJust (metaOf b)) [(a, b) | KArith _ _ a b _ <- pending]
      case (metaOf a, metaOf b) of
        (Just i, Just j) -> unify (set i tRat) (TM j) tRat
        (Just i, Nothing) -> Just (set i (whnf s b))
        (Nothing, Just j) -> Just (set j (whnf s a))
        (Nothing, Nothing) -> Nothing
    number = do
      i <- firstJust ([metaOf t | KPred _ _ IsNum t <- pending] <> [metaOf t | KNeg _ t _ <- pending])
      pure (set i tRat)

firstJust :: [Maybe a] -> Maybe a
firstJust = \case
  [] -> Nothing
  Just x : _ -> Just x
  Nothing : xs -> firstJust xs
