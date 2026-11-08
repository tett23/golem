{- | The primitives of the built-in modules of .emet (docs/adr/0160): the
functions of @List@ and @String@ that are written in Haskell, and @div@.
Each returns its value and its size, the length of the string or the list
it makes, which counts towards the limit of steps. The size is found
before the value is made, and a value longer than the steps left is not
made (docs/adr/0223).
-}
module Golem.Emet.Prim
  ( PrimValue (..),
    primList,
    PrimStop (..),
    runPrim,
  )
where

import Data.Char (isDigit)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Expr (divAt)
import Golem.Eval.Number (renderNumber)
import Golem.Eval.Value (Value (..), numberOf)
import Golem.Syntax

data PrimValue
  = PV !Value
  | PCh !Char
  | PC !Text ![PrimValue]
  | -- | a list and its length, which is found without converting its
    -- elements: a list shared many times inside another is converted once
    -- for each time, and its length is wanted before (docs/adr/0223)
    PL Integer [PrimValue]
  | PT ![PrimValue]
  | PFun
  deriving stock (Show)

-- | The span of an error of a primitive; the evaluator puts it at the call.
nowhere :: SrcSpan
nowhere = mkSpan (FileId 0) 0 0

-- | Why a primitive makes no value: an error, or a value longer than the steps left.
data PrimStop = PrimFailed !Diagnostic | PrimOverLimit
  deriving stock (Show)

{- | A primitive applied to its arguments, given the steps left: the
length of what it would make, found from its arguments alone (docs/adr/0223),
and the value only when that length is not more than the steps left. The
length is an Integer, so that no length wraps round.
-}
runPrim :: Integer -> Text -> [PrimValue] -> Either PrimStop (PrimValue, Int64)
runPrim room name args
  | size > room = Left PrimOverLimit
  | otherwise = either (Left . PrimFailed) (\v -> Right (v, fromInteger size)) (build name args)
  where
    size = sizeOf name args

{- | The length of the string or the list a primitive makes, without making
it (docs/adr/0223): equal to the length of what 'build' makes (S1). The
work of finding it is in proportion to the arguments, which were counted
when they were made.
-}
sizeOf :: Text -> [PrimValue] -> Integer
sizeOf name args = case (name, args) of
  ("List.reverse", [PL _ xs]) -> len xs
  ("List.take", [n, PL _ xs]) -> min (toInteger (count n)) (len xs)
  ("List.drop", [n, PL _ xs]) -> max 0 (len xs - toInteger (count n))
  ("List.range", [a, b]) -> max 0 (integer b - integer a + 1)
  ("List.concat", [PL _ xss]) -> sum [n | PL n _ <- xss]
  ("String.chars", [PV (VString s)]) -> tlen s
  ("String.fromChars", [PL _ xs]) -> len [c | PCh c <- xs]
  ("String.fromChar", [PCh _]) -> 1
  ("String.join", [PV (VString sep), PL _ xs]) ->
    let ss = strings xs in sum (map tlen ss) + tlen sep * max 0 (len ss - 1)
  ("String.split", [PV (VString sep), PV (VString s)])
    | T.null sep -> tlen s
    | otherwise -> toInteger (T.count sep s) + 1
  -- T.lines: a line for each LF, and one for the text after the last LF
  ("String.lines", [PV (VString s)]) -> toInteger (T.count "\n" s) + (if T.null s || T.last s == '\n' then 0 else 1)
  ("String.trim", [PV (VString s)]) -> tlen (T.strip s)
  ("String.replace", [PV (VString from), PV (VString to), PV (VString s)])
    | T.null from -> tlen s
    | otherwise -> tlen s + toInteger (T.count from s) * (tlen to - tlen from)
  ("String.take", [n, PV (VString s)]) -> min (toInteger (count n)) (tlen s)
  ("String.drop", [n, PV (VString s)]) -> max 0 (tlen s - toInteger (count n))
  -- the digits of a number, fewer than 2^4096, with at most 1000 after the point
  ("String.fromNat", [PV v]) -> numberSize v
  ("String.fromInt", [PV v]) -> numberSize v
  ("String.fromRat", [PV v]) -> numberSize v
  _ -> 0
  where
    len :: [a] -> Integer
    len = toInteger . length
    tlen = toInteger . T.length
    numberSize v = case numberOf v of
      Just (_, q) -> either (const 0) tlen (renderNumber q)
      Nothing -> 0

build :: Text -> [PrimValue] -> Either Diagnostic PrimValue
build name args = case (name, args) of
  ("div", [PV a, PV b]) -> PV <$> divAt nowhere a b
  -- List
  ("List.length", [PL _ xs]) -> value (nat (length xs))
  ("List.reverse", [PL _ xs]) -> list (reverse xs)
  ("List.take", [n, PL _ xs]) -> list (take (count n) xs)
  ("List.drop", [n, PL _ xs]) -> list (drop (count n) xs)
  ("List.range", [a, b]) ->
    let (x, y) = (integer a, integer b)
     in Right (PL (max 0 (y - x + 1)) [PV (VInt i) | i <- [x .. y]])
  ("List.concat", [PL _ xss]) -> list (concat [xs | PL _ xs <- xss])
  ("List.at", [n, PL _ xs]) -> value $ case drop (count n) xs of
    y : _ -> PC "Just" [y]
    [] -> PC "Nothing" []
  -- String
  ("String.length", [PV (VString s)]) -> value (nat (T.length s))
  ("String.chars", [PV (VString s)]) -> list (map PCh (T.unpack s))
  ("String.fromChars", [PL _ xs]) -> text (T.pack [c | PCh c <- xs])
  ("String.fromChar", [PCh c]) -> text (T.singleton c)
  ("String.join", [PV (VString sep), PL _ xs]) -> text (T.intercalate sep (strings xs))
  ("String.split", [PV (VString sep), PV (VString s)])
    | T.null sep -> list [PV (VString (T.singleton c)) | c <- T.unpack s]
    | otherwise -> list (map (PV . VString) (T.splitOn sep s))
  ("String.lines", [PV (VString s)]) -> list (map (PV . VString) (T.lines s))
  ("String.trim", [PV (VString s)]) -> text (T.strip s)
  ("String.startsWith", [PV (VString p), PV (VString s)]) -> value (PV (VBool (p `T.isPrefixOf` s)))
  ("String.endsWith", [PV (VString p), PV (VString s)]) -> value (PV (VBool (p `T.isSuffixOf` s)))
  ("String.contains", [PV (VString p), PV (VString s)]) -> value (PV (VBool (p `T.isInfixOf` s)))
  ("String.replace", [PV (VString from), PV (VString to), PV (VString s)])
    | T.null from -> text s
    | otherwise -> text (T.replace from to s)
  ("String.take", [n, PV (VString s)]) -> text (T.take (count n) s)
  ("String.drop", [n, PV (VString s)]) -> text (T.drop (count n) s)
  ("String.fromNat", [PV v]) -> numberText v
  ("String.fromInt", [PV v]) -> numberText v
  ("String.fromRat", [PV v]) -> numberText v
  ("String.toNat", [PV (VString s)])
    | not (T.null s) && T.all isDigit s && T.all (< '\x80') s -> value (PC "Just" [PV (VNat (read (T.unpack s)))])
    | otherwise -> value (PC "Nothing" [])
  ("String.toInt", [PV (VString s)]) -> value $ case T.uncons s of
    Just ('-', d) | digits d -> PC "Just" [PV (VInt (negate (read (T.unpack d))))]
    _ | digits s -> PC "Just" [PV (VInt (read (T.unpack s)))]
    _ -> PC "Nothing" []
  _ -> Left (diagnostic "G02007" Error nowhere (name <> " の引数が不正です"))
  where
    value = Right
    list = Right . primList
    text = Right . PV . VString
    nat n = PV (VNat (fromIntegral n))
    digits d = not (T.null d) && T.all (\c -> isDigit c && c < '\x80') d
    numberText v = case numberOf v of
      Just (_, q) -> case renderNumber q of
        Right t -> text t
        Left _ -> Left (diagnostic "G02102" Error nowhere "小数点以下が 1000 桁を超える数は文字列にできません。round に当たる計算で桁数を減らします")
      Nothing -> Left (diagnostic "G02007" Error nowhere (name <> " の引数が不正です"))

strings :: [PrimValue] -> [Text]
strings xs = [t | PV (VString t) <- xs]

integer :: PrimValue -> Integer
integer = \case
  PV v | Just (_, q) <- numberOf v -> truncate q
  _ -> 0

-- | A count of elements or characters, at least 0 and at most the largest Int.
count :: PrimValue -> Int
count n = fromInteger (max 0 (min (toInteger (maxBound :: Int)) (integer n)))

-- | A list of primitive values with its length.
primList :: [PrimValue] -> PrimValue
primList xs = PL (toInteger (length xs)) xs
