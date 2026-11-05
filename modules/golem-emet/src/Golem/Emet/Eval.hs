{- | The evaluator of .emet (docs/adr/0160): strict, but the bindings of a
@where@ are evaluated when first used, once. It is an abstract machine
whose continuation is an explicit stack, so that the depth of calls does
not depend on the stack of the runtime: a call in a tail position
replaces the frame of its caller, and only the others count towards the
limit of depth (E04101). Every reduction counts towards the limit of
steps (E04100), and so does the length of every string or list a
built-in operation makes. Both limits are counted by the meaning of the
program alone, so where evaluation stops does not depend on the machine.

The operators of the three predicates of the checker (numbers, types that
compare, types that join) are called through a table of their
implementations by the type of the operand ('instancesOf'), as a type
class passes its dictionary: a type class would add the instances of the
users to the table.
-}
module Golem.Emet.Eval
  ( Result (..),
    Globals,
    evalCall,
    evalCallCounted,
    stepLimit,
    depthLimit,
  )
where

import Control.Monad.ST (ST, runST)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.STRef (STRef, newSTRef, readSTRef, writeSTRef)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet.Core
import Golem.Emet.Prim (PrimValue (..), runPrim)
import Golem.Emet.Syntax (BinOp (..), Loc (..), Name, binOpText)
import Golem.Eval.Expr (binaryAt)
import Golem.Eval.Expr qualified as E
import Golem.Eval.Value (NumType (..), Value (..), mkNumber, numberOf)
import Golem.Syntax

{- | A value that a call returns or takes: a value of the expression
context, a character, a constructor and its fields, a list or a tuple. A
function cannot be passed in or out.
-}
data Result
  = RPrim !Value
  | RChar !Char
  | RCon !Text ![Result]
  | RList ![Result]
  | RTuple ![Result]
  | -- | a function, which cannot leave the evaluator
    RFun
  deriving stock (Eq, Show)

type Globals = Map GKey Global

{- | The most steps of one call from .gm (docs/adr/0160): about three times
the largest work measured, a tail recursion of ten million calls.
-}
stepLimit :: Int
stepLimit = 100000000

-- | The most frames of calls that are not tail calls.
depthLimit :: Int
depthLimit = 10000

data V s
  = VP !Value
  | VCh !Char
  | VC !Text ![V s]
  | VL ![V s]
  | VT ![V s]
  | VF !(Fn s) ![V s]

data Fn s
  = FnClo !(Clo s)
  | FnPrim !Text !Int
  | FnCon !Text !Int

-- | A function: its name, the path of its module and the line of its declaration.
data FunMeta = FunMeta !Name !FilePath !Int

data Clo s = Clo
  { cloMeta :: !FunMeta,
    cloArity :: !Int,
    cloEqs :: ![CEq],
    cloWhere :: ![CBind],
    -- | the bindings of the where it belongs to, which see each other
    cloEnv :: Env s
  }

type Env s = Map Name (Slot s)

data Slot s = SV !(V s) | SC !(STRef s (Cell s))

-- | A binding of where: not evaluated (with the function it belongs to), being evaluated, or its value.
data Cell s = Pending !FunMeta !(Env s) !CBind | Busy | Done !(V s)

-- | What is left to choose: equations (or alternatives) against values.
data Sel s = Sel !(Env s) ![CEq] ![V s]

data Ctl s = Eval !(Env s) !CExpr | Ret !(V s) | Fail !Diagnostic | Choose !(Sel s)

data Frame s
  = KArgs !Loc !(Env s) ![V s] ![CExpr]
  | KBinL !Loc !BinOp !(Env s) !CExpr
  | KBinR !Loc !BinOp !(V s)
  | KAndOr !BinOp !(Env s) !CExpr
  | KNeg !Loc
  | KCase !(Env s) ![CAlt]
  | KTern !(Env s) !CExpr !CExpr
  | KList !(Env s) ![V s] ![CExpr]
  | KTuple !(Env s) ![V s] ![CExpr]
  | KCall !FunMeta
  | -- | a binding of where being evaluated, and the function it belongs to
    KUpdate !Name !FunMeta !(STRef s (Cell s))
  | KMore !Loc ![V s]
  | -- | a guard's condition: its body, the guards after it, and the rest of the choice
    KGuard !(Env s) !CExpr ![(Maybe CExpr, CExpr)] !(Sel s)

-- | What applying a function does: the next control and stack, the steps and the change of depth.
data Step s = Step !(Ctl s) ![Frame s] !Int !Int

{- | Calls a top-level function with arguments. @at@ is the span of the
call in .gm, where the limits and the cycles of bindings are reported;
other errors point into the .emet, whose file ids @files@ gives. Nothing
comes out of a call that fails.
-}
evalCall :: Globals -> Map FilePath FileId -> SrcSpan -> GKey -> [Result] -> Either Diagnostic Result
evalCall globals files at key args = fst (evalCallCounted globals files at key args)

-- | 'evalCall' with the steps the call took, to measure the work of functions against 'stepLimit'.
evalCallCounted :: Globals -> Map FilePath FileId -> SrcSpan -> GKey -> [Result] -> (Either Diagnostic Result, Int)
evalCallCounted globals files at key args = case Map.lookup key globals of
  Nothing -> (Left (diagnostic "E02100" Error at ("未定義の関数 " <> snd key <> " です")), 0)
  Just g -> runST $ do
    Step c k n d <- apply (Loc 0 0) (globalValue g) (map fromResult args) []
    (r, used) <- loop c k n d
    pure (toResult <$> r, used)
  where
    stop steps d = pure (Left d, steps)

    spanAt :: FilePath -> Loc -> SrcSpan
    spanAt path (Loc s e) = mkSpan (Map.findWithDefault (spanFile at) path files) s (max s e)

    loop :: Ctl s -> [Frame s] -> Int -> Int -> ST s (Either Diagnostic (V s), Int)
    loop ctl k !steps !depth
      | steps > stepLimit = stop steps (diagnostic "E04100" Error at ("関数の評価の手数が上限（" <> T.pack (show stepLimit) <> " 手）を超えました: " <> current k))
      | depth > depthLimit = stop steps (diagnostic "E04101" Error at ("末尾でない呼び出しの深さが上限（" <> T.pack (show depthLimit) <> "）を超えました: " <> current k))
      | otherwise = case ctl of
          Eval env e -> evalE env e k steps depth
          Ret v -> ret v k steps depth
          Fail d -> stop steps d
          Choose sel -> select sel k steps depth

    current k = case [m | KCall m <- k] of
      m : _ -> metaText m
      [] -> snd key

    metaText (FunMeta n p l) = n <> "（" <> T.pack p <> ":" <> T.pack (show l) <> "）"

    -- an error of an operation, at its place in the .emet
    fault k l d = Fail (d {diagSpan = spanAt (pathOf k) l})

    pathOf k = case [p | KCall (FunMeta _ p _) <- k] of
      p : _ -> p
      [] -> fst key

    evalE env e k steps depth = case e of
      CLit (LValue v) -> loop (Ret (VP v)) k steps depth
      CLit (LChar c) -> loop (Ret (VCh c)) k steps depth
      CLocal n -> case Map.lookup n env of
        Just (SV v) -> loop (Ret v) k steps depth
        Just (SC ref) -> force n ref k steps depth
        Nothing -> stop steps (diagnostic "E02100" Error at ("未定義の名前 " <> n <> " です"))
      CGlobal l g -> case Map.lookup g globals of
        -- a function of no arguments is called where it is named
        Just gl@(GFun f) | cfArity f == 0 -> do
          Step c k' n d <- apply l (globalValue gl) [] k
          loop c k' (steps + n) (depth + d)
        Just gl -> loop (Ret (globalValue gl)) k steps depth
        Nothing -> stop steps (diagnostic "E02100" Error at ("未定義の関数 " <> snd g <> " です"))
      CConV c 0 -> loop (Ret (VC c [])) k steps depth
      CConV c n -> loop (Ret (VF (FnCon c n) [])) k steps depth
      CList [] -> loop (Ret (VL [])) k steps depth
      CList (x : xs) -> loop (Eval env x) (KList env [] xs : k) steps depth
      CTuple [] -> loop (Ret (VT [])) k steps depth
      CTuple (x : xs) -> loop (Eval env x) (KTuple env [] xs : k) steps depth
      CApp l f as -> loop (Eval env f) (KArgs l env [] as : k) steps depth
      CBin l op a b -> case op of
        OpAnd -> loop (Eval env a) (KAndOr op env b : k) steps depth
        OpOr -> loop (Eval env a) (KAndOr op env b : k) steps depth
        _ -> loop (Eval env a) (KBinL l op env b : k) steps depth
      CNeg l x -> loop (Eval env x) (KNeg l : k) steps depth
      CCase s alts -> loop (Eval env s) (KCase env alts : k) steps depth
      CTern c a b -> loop (Eval env c) (KTern env a b : k) steps depth

    -- a binding of where: its value, or its evaluation now
    force n ref k steps depth =
      readSTRef ref >>= \case
        Done v -> loop (Ret v) k steps depth
        -- a binding that needs its own value never ends
        Busy ->
          let chain = reverse (n : takeUntil ref k)
              owner = case [m | KUpdate _ m r <- k, r == ref] of
                FunMeta f p l : _ -> "（" <> f <> "、" <> T.pack p <> ":" <> T.pack (show l) <> "）"
                [] -> ""
           in stop steps (diagnostic "E04102" Error at ("where の束縛が評価の途中で自分自身の値を求めました: " <> T.intercalate " → " chain <> owner))
        Pending meta env b -> do
          writeSTRef ref Busy
          select (Sel env (cbEqs b) []) (KUpdate n meta ref : k) (steps + 1) depth

    -- the names of the bindings being evaluated, from the latest to the one of the reference
    takeUntil ref = \case
      [] -> []
      KUpdate m _ r : rest
        | r == ref -> [m]
        | otherwise -> m : takeUntil ref rest
      _ : rest -> takeUntil ref rest

    ret v k steps depth = case k of
      [] -> pure (Right v, steps)
      fr : rest -> case fr of
        KCall _ -> loop (Ret v) rest steps (depth - 1)
        KUpdate _ _ ref -> writeSTRef ref (Done v) >> loop (Ret v) rest steps depth
        KArgs l _ done [] -> case reverse (v : done) of
          f : as -> do
            Step c k' n d <- apply l f as rest
            loop c k' (steps + n) (depth + d)
          [] -> loop (Ret v) rest steps depth
        KArgs l env done (x : xs) -> loop (Eval env x) (KArgs l env (v : done) xs : rest) steps depth
        KList _ done [] -> loop (Ret (VL (reverse (v : done)))) rest (steps + 1) depth
        KList env done (x : xs) -> loop (Eval env x) (KList env (v : done) xs : rest) steps depth
        KTuple _ done [] -> loop (Ret (VT (reverse (v : done)))) rest (steps + 1) depth
        KTuple env done (x : xs) -> loop (Eval env x) (KTuple env (v : done) xs : rest) steps depth
        KAndOr op env b -> case (op, v) of
          (OpAnd, VP (VBool False)) -> loop (Ret v) rest (steps + 1) depth
          (OpOr, VP (VBool True)) -> loop (Ret v) rest (steps + 1) depth
          _ -> loop (Eval env b) rest (steps + 1) depth
        KBinL l op env b -> loop (Eval env b) (KBinR l op v : rest) steps depth
        KBinR l op a -> case binop op a v of
          Right (r, size) -> loop (Ret r) rest (steps + 1 + size) depth
          Left d -> loop (fault rest l d) rest steps depth
        KNeg l -> case v of
          VP x | Just (t, q) <- numberOf x -> loop (Ret (VP (mkNumber (max TInt t) (negate q)))) rest (steps + 1) depth
          _ -> loop (fault rest l (diagnostic "G02001" Error at "- は数にだけ使えます")) rest steps depth
        KTern env a b -> case v of
          VP (VBool True) -> loop (Eval env a) rest (steps + 1) depth
          _ -> loop (Eval env b) rest (steps + 1) depth
        KCase env alts -> select (Sel env [CEq [p] r | CAlt p r <- alts] [v]) rest (steps + 1) depth
        KMore l more -> do
          Step c k' n d <- apply l v more rest
          loop c k' (steps + n) (depth + d)
        KGuard env body guards sel -> case v of
          VP (VBool True) -> loop (Eval env body) rest steps depth
          _ -> runGuards env guards sel rest steps depth

    -- the first equation whose patterns match
    select (Sel env eqs vs) k steps depth = case eqs of
      [] -> stop steps (diagnostic "E03100" Error at "どの等式にも当たりません")
      CEq ps rhs : rest -> case matchAll ps vs of
        Nothing -> select (Sel env rest vs) k steps depth
        Just binds -> do
          let env' = Map.union (Map.map SV binds) env
          case rhs of
            CPlain e -> loop (Eval env' e) k (steps + 1) depth
            CGuards gs -> runGuards env' gs (Sel env rest vs) k (steps + 1) depth

    runGuards env guards sel k steps depth = case guards of
      [] -> select sel k steps depth
      (Nothing, body) : _ -> loop (Eval env body) k steps depth
      (Just c, body) : more -> loop (Eval env c) (KGuard env body more sel : k) steps depth

    -- applying a function value to arguments
    apply :: Loc -> V s -> [V s] -> [Frame s] -> ST s (Step s)
    apply l f given k = case f of
      VF fn held -> do
        let all' = held <> given
            n = arity fn
        if length all' < n
          then pure (Step (Ret (VF fn all')) k 0 0)
          else do
            let (now, more) = splitAt n all'
                k' = if null more then k else KMore l more : k
            enter l fn now k'
      _ -> pure (Step (Ret f) k 0 0)

    arity = \case
      FnClo c -> cloArity c
      FnPrim _ n -> n
      FnCon _ n -> n

    enter l fn vs k = case fn of
      FnCon c _ -> pure (Step (Ret (VC c vs)) k 1 0)
      FnPrim name _ -> pure $ case runPrim name (map toPrim vs) of
        Right (pv, size) -> Step (Ret (fromPrim pv)) k (1 + size) 0
        Left d -> Step (fault k l d) k 1 0
      FnClo c -> do
        let meta = cloMeta c
            (k', d) = case k of
              KCall _ : rest -> (KCall meta : rest, 0)
              _ -> (KCall meta : k, 1)
        env <- whereEnv (cloEnv c) (cloWhere c) meta
        pure (Step (Choose (Sel env (cloEqs c) vs)) k' 1 d)

    -- the bindings of a where for one call: cells for values, closures for local functions
    whereEnv base binds meta@(FunMeta _ path _) = do
      cells <- mapM (\b -> (b,) <$> newSTRef Busy) [b | b <- binds, cbArity b == 0]
      let refs = Map.fromList [(cbName b, r) | (b, r) <- cells]
          env = foldl' add base binds
          add m b = case Map.lookup (cbName b) refs of
            Just r -> Map.insert (cbName b) (SC r) m
            Nothing -> Map.insert (cbName b) (SV (VF (FnClo (Clo (FunMeta (cbName b) path (cbLine b)) (cbArity b) (cbEqs b) [] env)) [])) m
      mapM_ (\(b, r) -> writeSTRef r (Pending meta env b)) cells
      pure env

    binop op a b = case op of
      OpCons -> case b of
        VL xs -> Right (VL (a : xs), 1)
        _ -> bad
      OpAppend -> maybe bad Right (instConcat (instancesOf a) >>= \f -> f a b)
      _ | Just test <- cmpOf op -> maybe bad (\c -> Right (VP (VBool (test (c a b))), 0)) (instOrd (instancesOf a))
      _ -> case (a, b, golemOp op) of
        (VP x, VP y, Just o) | Just arith <- instNum (instancesOf a) -> (\r -> (VP r, 0)) <$> arith o x y
        _ -> bad
      where
        bad = Left (diagnostic "G02001" Error at (binOpText op <> " を使えない値です"))

    -- the table of the instances of the predicates, by the type of a value
    instancesOf :: V s -> Instances s
    instancesOf = \case
      VP v | Just _ <- numberOf v -> Instances (Just (binaryAt at)) (Just numOrder) Nothing
      VP (VBool _) -> Instances Nothing (Just boolOrder) Nothing
      VP (VString _) -> Instances Nothing (Just stringOrder) (Just stringJoin)
      VCh _ -> Instances Nothing (Just charOrder) Nothing
      VL _ -> Instances Nothing Nothing (Just listJoin)
      _ -> Instances Nothing Nothing Nothing

{- | The implementations of the operators for one type: arithmetic,
comparison, and joining with the size of what it makes.
-}
data Instances s = Instances
  { instNum :: !(Maybe (E.BinaryOp -> Value -> Value -> Either Diagnostic Value)),
    instOrd :: !(Maybe (V s -> V s -> Ordering)),
    instConcat :: !(Maybe (V s -> V s -> Maybe (V s, Int)))
  }

-- | Numbers by their values, whatever their types.
numOrder :: V s -> V s -> Ordering
numOrder (VP a) (VP b) | Just (_, x) <- numberOf a, Just (_, y) <- numberOf b = compare x y
numOrder _ _ = EQ

boolOrder :: V s -> V s -> Ordering
boolOrder (VP (VBool a)) (VP (VBool b)) = compare a b
boolOrder _ _ = EQ

-- | Strings by their code points, as in the expression context.
stringOrder :: V s -> V s -> Ordering
stringOrder (VP (VString a)) (VP (VString b)) = compare (T.unpack a) (T.unpack b)
stringOrder _ _ = EQ

charOrder :: V s -> V s -> Ordering
charOrder (VCh a) (VCh b) = compare a b
charOrder _ _ = EQ

stringJoin :: V s -> V s -> Maybe (V s, Int)
stringJoin (VP (VString x)) (VP (VString y)) = let r = x <> y in Just (VP (VString r), T.length r)
stringJoin _ _ = Nothing

listJoin :: V s -> V s -> Maybe (V s, Int)
listJoin (VL x) (VL y) = Just (VL (x <> y), length x + length y)
listJoin _ _ = Nothing

cmpOf :: BinOp -> Maybe (Ordering -> Bool)
cmpOf = \case
  OpEq -> Just (== EQ)
  OpNe -> Just (/= EQ)
  OpLt -> Just (== LT)
  OpLe -> Just (/= GT)
  OpGt -> Just (== GT)
  OpGe -> Just (/= LT)
  _ -> Nothing

golemOp :: BinOp -> Maybe E.BinaryOp
golemOp = \case
  OpAdd -> Just E.Add
  OpSub -> Just E.Sub
  OpMul -> Just E.Mul
  OpDiv -> Just E.Div
  OpMod -> Just E.Mod
  OpPow -> Just E.Pow
  _ -> Nothing

globalValue :: Global -> V s
globalValue = \case
  GFun f -> VF (FnClo (Clo (FunMeta (cfName f) (cfPath f) (cfLine f)) (cfArity f) (cfEqs f) (cfWhere f) Map.empty)) []
  GPrim name n -> VF (FnPrim name n) []

matchAll :: [CPat] -> [V s] -> Maybe (Map Name (V s))
matchAll = matchIn Map.empty

matchIn :: Map Name (V s) -> [CPat] -> [V s] -> Maybe (Map Name (V s))
matchIn m0 ps vs = foldl' (\acc (p, v) -> acc >>= \m -> match m p v) (Just m0) (zip ps vs)

match :: Map Name (V s) -> CPat -> V s -> Maybe (Map Name (V s))
match m p v = case (p, v) of
  (CPVar n, _) -> Just (Map.insert n v m)
  (CPWild, _) -> Just m
  (CPLit (LValue l), VP x) -> if litEq l x then Just m else Nothing
  (CPLit (LChar c), VCh d) -> if c == d then Just m else Nothing
  (CPCon c ps, VC d vs) | c == d -> matchIn m ps vs
  (CPList ps, VL vs) | length ps == length vs -> matchIn m ps vs
  (CPCons h t, VL (x : xs)) -> match m h x >>= \m' -> match m' t (VL xs)
  (CPTuple ps, VT vs) | length ps == length vs -> matchIn m ps vs
  _ -> Nothing

litEq :: Value -> Value -> Bool
litEq a b = case (numberOf a, numberOf b) of
  (Just (_, x), Just (_, y)) -> x == y
  _ -> a == b

toPrim :: V s -> PrimValue
toPrim = \case
  VP v -> PV v
  VCh c -> PCh c
  VC c vs -> PC c (map toPrim vs)
  VL vs -> PL (map toPrim vs)
  VT vs -> PT (map toPrim vs)
  VF {} -> PFun

fromPrim :: PrimValue -> V s
fromPrim = \case
  PV v -> VP v
  PCh c -> VCh c
  PC c vs -> VC c (map fromPrim vs)
  PL vs -> VL (map fromPrim vs)
  PT vs -> VT (map fromPrim vs)
  PFun -> VP VNil

toResult :: V s -> Result
toResult = \case
  VP v -> RPrim v
  VCh c -> RChar c
  VC c vs -> RCon c (map toResult vs)
  VL vs -> RList (map toResult vs)
  VT vs -> RTuple (map toResult vs)
  VF {} -> RFun

fromResult :: Result -> V s
fromResult = \case
  RPrim v -> VP v
  RChar c -> VCh c
  RCon c vs -> VC c (map fromResult vs)
  RList vs -> VL (map fromResult vs)
  RTuple vs -> VT (map fromResult vs)
  RFun -> VP VNil
