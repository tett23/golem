{- | The values of the literals of .gmx (docs/adr/0148): numbers by the
rules of the expression context of .gm (docs/adr/0101), and strings with
their escapes.
-}
module Golem.Gmx.Literal
  ( numberValue,
    negateValue,
    stringValue,
  )
where

import Data.Char (chr, isDigit, isHexDigit)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Value (NumType (..), Value (..), mkNumber, numberOf)
import Numeric (readHex)

{- | A number literal, as one of the expression context of .gm
(golem-parser's @number@): digits are a natural number, a decimal or an
exponent the exact rational. An exponent over 1300 in absolute value is
2^4096 or its reciprocal, which the checker reports as too large (G02086)
without making the power of 10. The grammar admits only well-formed
literals.
-}
numberValue :: Text -> Value
numberValue t = case T.splitOn "e" t of
  [m] -> mantissa m
  [m, x]
    | abs k > 1300 -> VRat (if k > 0 then 2 ^ (4096 :: Int) else 1 % 2 ^ (4096 :: Int))
    | otherwise -> case mantissa m of
        VNat n -> VRat (toRational n * 10 ^^ k)
        VRat q -> VRat (q * 10 ^^ k)
        v -> v
    where
      k = exponentOf x
  _ -> VNat 0
  where
    mantissa m = case T.splitOn "." m of
      [i] -> VNat (fromInteger (digits i))
      [i, f] -> VRat (digits (i <> f) % 10 ^ T.length f)
      _ -> VNat 0
    digits d = if T.all isDigit d && not (T.null d) then read (T.unpack d) else 0 :: Integer
    exponentOf x = case T.uncons x of
      Just ('+', d) -> digits d
      Just ('-', d) -> negate (digits d)
      _ -> digits x

-- | The negation of a number literal in a pattern (@-1@): an integer or a rational.
negateValue :: Value -> Value
negateValue v = case numberOf v of
  Just (t, q) -> mkNumber (max TInt t) (negate q)
  Nothing -> v

-- | The text of a string literal between its quotes, with the escapes resolved.
stringValue :: Text -> Text
stringValue = T.pack . go . T.unpack
  where
    go = \case
      '\\' : 'u' : '{' : rest ->
        let (h, rest') = span isHexDigit rest
         in case readHex h of
              [(n, "")] | n <= 0x10FFFF -> chr n : go (drop 1 rest')
              _ -> go (drop 1 rest')
      '\\' : c : rest -> esc c : go rest
      c : rest -> c : go rest
      [] -> []
    esc = \case
      'n' -> '\n'
      't' -> '\t'
      c -> c
