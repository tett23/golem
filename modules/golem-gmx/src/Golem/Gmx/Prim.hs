{- | The primitives of the built-in modules of .gmx (docs/adr/0148): the
functions of @List@ and @String@ that are written in Haskell, and @div@.
Each returns its value and its size, the length of the string or the list
it makes, which counts towards the limit of steps.
-}
module Golem.Gmx.Prim
  ( PrimValue (..),
    runPrim,
  )
where

import Data.Char (isDigit)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Expr (divAt)
import Golem.Eval.Number (renderNumber)
import Golem.Eval.Value (Value (..), numberOf)
import Golem.Syntax

data PrimValue
  = PV !Value
  | PC !Text ![PrimValue]
  | PL ![PrimValue]
  | PFun

-- | The span of an error of a primitive; the evaluator puts it at the call.
nowhere :: SrcSpan
nowhere = mkSpan (FileId 0) 0 0

runPrim :: Text -> [PrimValue] -> Either Diagnostic (PrimValue, Int)
runPrim name args = case (name, args) of
  ("div", [PV a, PV b]) -> (\v -> (PV v, 0)) <$> divAt nowhere a b
  -- List
  ("List.length", [PL xs]) -> sized0 (nat (length xs))
  ("List.reverse", [PL xs]) -> list (reverse xs)
  ("List.cons", [x, PL xs]) -> Right (PL (x : xs), 1)
  ("List.uncons", [PL xs]) -> sized0 $ case xs of
    [] -> PC "Nothing" []
    y : ys -> PC "Just" [PC "Cons" [y, PL ys]]
  ("List.take", [n, PL xs]) -> list (take (count n) xs)
  ("List.drop", [n, PL xs]) -> list (drop (count n) xs)
  ("List.range", [a, b]) ->
    let (x, y) = (integer a, integer b)
     in Right (PL [PV (VInt i) | i <- [x .. y]], fromInteger (max 0 (y - x + 1)))
  ("List.concat", [PL xss]) -> list (concat [xs | PL xs <- xss])
  ("List.at", [n, PL xs]) -> sized0 $ case drop (count n) xs of
    y : _ -> PC "Just" [y]
    [] -> PC "Nothing" []
  -- String
  ("String.length", [PV (VString s)]) -> sized0 (nat (T.length s))
  ("String.chars", [PV (VString s)]) -> list [PV (VString (T.singleton c)) | c <- T.unpack s]
  ("String.fromChars", [PL xs]) -> text (T.concat (strings xs))
  ("String.join", [PV (VString sep), PL xs]) -> text (T.intercalate sep (strings xs))
  ("String.split", [PV (VString sep), PV (VString s)])
    | T.null sep -> list [PV (VString (T.singleton c)) | c <- T.unpack s]
    | otherwise -> list (map (PV . VString) (T.splitOn sep s))
  ("String.lines", [PV (VString s)]) -> list (map (PV . VString) (T.lines s))
  ("String.trim", [PV (VString s)]) -> text (T.strip s)
  ("String.startsWith", [PV (VString p), PV (VString s)]) -> sized0 (PV (VBool (p `T.isPrefixOf` s)))
  ("String.endsWith", [PV (VString p), PV (VString s)]) -> sized0 (PV (VBool (p `T.isSuffixOf` s)))
  ("String.contains", [PV (VString p), PV (VString s)]) -> sized0 (PV (VBool (p `T.isInfixOf` s)))
  ("String.replace", [PV (VString from), PV (VString to), PV (VString s)])
    | T.null from -> text s
    | otherwise -> text (T.replace from to s)
  ("String.take", [n, PV (VString s)]) -> text (T.take (count n) s)
  ("String.drop", [n, PV (VString s)]) -> text (T.drop (count n) s)
  ("String.fromNat", [PV v]) -> numberText v
  ("String.fromInt", [PV v]) -> numberText v
  ("String.fromRat", [PV v]) -> numberText v
  ("String.toNat", [PV (VString s)])
    | not (T.null s) && T.all isDigit s && T.all (< '\x80') s -> sized0 (PC "Just" [PV (VNat (read (T.unpack s)))])
    | otherwise -> sized0 (PC "Nothing" [])
  ("String.toInt", [PV (VString s)]) -> sized0 $ case T.uncons s of
    Just ('-', d) | digits d -> PC "Just" [PV (VInt (negate (read (T.unpack d))))]
    _ | digits s -> PC "Just" [PV (VInt (read (T.unpack s)))]
    _ -> PC "Nothing" []
  _ -> Left (diagnostic "G02007" Error nowhere (name <> " の引数が不正です"))
  where
    sized0 v = Right (v, 0)
    list xs = Right (PL xs, length xs)
    text t = Right (PV (VString t), T.length t)
    nat n = PV (VNat (fromIntegral n))
    strings xs = [t | PV (VString t) <- xs]
    integer = \case
      PV v | Just (_, q) <- numberOf v -> truncate q
      _ -> 0 :: Integer
    count n = fromInteger (max 0 (min (toInteger (maxBound :: Int)) (integer n)))
    digits d = not (T.null d) && T.all (\c -> isDigit c && c < '\x80') d
    numberText v = case numberOf v of
      Just (_, q) -> case renderNumber q of
        Right t -> text t
        Left _ -> Left (diagnostic "G02102" Error nowhere "小数点以下が 1000 桁を超える数は文字列にできません。round に当たる計算で桁数を減らします")
      Nothing -> Left (diagnostic "G02007" Error nowhere (name <> " の引数が不正です"))
