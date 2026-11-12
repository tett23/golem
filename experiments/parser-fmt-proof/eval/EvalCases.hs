module Main (main) where

import Control.Monad (forM_)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Golem.Emet (Result (..), evaluateExpression)
import Golem.Eval.Value (Value (..))
import Golem.Syntax (DiagnosticCode (..), diagCode)

arithmetic :: Int -> [String]
arithmetic 0 = ["0", "1"]
arithmetic depth =
  arithmetic 0 ++ [expr | a <- children, b <- children, expr <- ["(" ++ a ++ " + " ++ b ++ ")", "(div " ++ a ++ " " ++ b ++ ")"]]
  where
    children = arithmetic (depth - 1)

main :: IO ()
main = do
  let choices = ["(" ++ c ++ " ? " ++ a ++ " : " ++ b ++ ")" | c <- ["True", "False"], a <- arithmetic 1, b <- arithmetic 1]
  let strings = ["", "甲", "𠮷", "a甲"]
      appends = ["(\"" ++ a ++ "\" ++ \"" ++ b ++ "\")" | a <- strings, b <- strings]
  forM_ (arithmetic 2 ++ choices ++ appends) $ \source -> forM_ [0 .. 5] $ \budget -> do
    let result = evaluateExpression Nothing budget (TE.encodeUtf8 (T.pack source))
    value <- case result of
      Right (RPrim (VNat n)) -> pure (show n)
      Right (RPrim (VString s)) -> pure ("string " ++ T.unpack s)
      Left [d] -> let DiagnosticCode code = diagCode d in pure (T.unpack code)
      _ -> fail (show (source, budget, result))
    putStrLn (show budget ++ " " ++ source ++ " => " ++ value)
