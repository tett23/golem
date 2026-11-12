{-# LANGUAGE LambdaCase #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Golem.Emet (Result (..), callFunctionLimited, evaluateExpression, fileHandlers, loadProgram, sessionPath)
import Golem.Eval.Value (Value (..))
import Golem.Syntax (DiagnosticCode (..), FileId (..), diagCode, mkSpan)

arithmetic :: Int -> [String]
arithmetic 0 = ["0", "1"]
arithmetic depth =
  arithmetic 0 ++ [expr | a <- children, b <- children, expr <- ["(" ++ a ++ " + " ++ b ++ ")", "(div " ++ a ++ " " ++ b ++ ")"]]
  where
    children = arithmetic (depth - 1)

main :: IO ()
main = do
  let choices = ["(" ++ c ++ " ? " ++ a ++ " : " ++ b ++ ")" | c <- ["True", "False"], a <- arithmetic 1, b <- arithmetic 1]
  let strings = ["", "甲", "𠮷", "a甲", "e\x0301"]
      appends = ["(\"" ++ a ++ "\" ++ \"" ++ b ++ "\")" | a <- strings, b <- strings]
      nested = ["(" ++ s ++ " ++ \"甲\")" | s <- appends] ++ ["(\"甲\" ++ " ++ s ++ ")" | s <- appends]
  let functions = T.pack "inc :: Nat -> Nat\ninc n = n + 1\ntwice :: Nat -> Nat\ntwice n = inc (inc n)\nidentityNat :: Nat -> Nat\nidentityNat x = x\nidentityString :: String -> String\nidentityString x = x\nreadInput :: Nat -> <file \"input.tsv\"> String\nreadInput n = File.read \"input.tsv\"\n"
  session <-
    loadProgram (\_ -> pure (Right (FileId 1, TE.encodeUtf8 functions))) [sessionPath] >>= \case
      ([], Just program) -> pure program
      (diagnostics, _) -> fail (show diagnostics)
  let calls = ["(" ++ name ++ " " ++ arg ++ ")" | name <- ["inc", "twice"], arg <- arithmetic 1]
  forM_ (arithmetic 2 ++ choices ++ appends ++ nested ++ calls) $ \source -> forM_ [0 .. 9] $ \budget -> do
    let result = evaluateExpression (Just session) budget (TE.encodeUtf8 (T.pack source))
    value <- case result of
      Right (RPrim (VNat n)) -> pure (show n)
      Right (RPrim (VString s)) -> pure ("string " ++ T.unpack s)
      Left [d] -> let DiagnosticCode code = diagCode d in pure (T.unpack code)
      _ -> fail (show (source, budget, result))
    putStrLn (show budget ++ " " ++ source ++ " => " ++ value)
  forM_ [Nothing, Just "", Just "甲𠮷"] $ \contents -> forM_ [0 .. 4] $ \budget -> do
    let handlers = fileHandlers (maybe Map.empty (Map.singleton (T.pack "input.tsv") . T.pack) contents)
        result = callFunctionLimited budget handlers session (mkSpan (FileId 1) 0 0) sessionPath (T.pack "readInput") [RPrim (VNat 0)]
    value <- case result of
      Right (RPrim (VString t)) -> pure ("string " ++ T.unpack t)
      Left d -> let DiagnosticCode code = diagCode d in pure (T.unpack code)
      _ -> fail (show result)
    putStrLn (show budget ++ " readInput " ++ maybe "missing" ("present " ++) contents ++ " => " ++ value)
  forM_ [("identityNat", "0"), ("identityNat", "1"),
         ("identityString", "\"\""), ("identityString", "\"甲\""),
         ("identityString", "\"𠮷\"")] $ \(name, argument) ->
    forM_ [0 .. 4] $ \budget -> do
      let source = name ++ " " ++ argument
          result = evaluateExpression (Just session) budget (TE.encodeUtf8 (T.pack source))
      value <- case result of
        Right (RPrim (VNat n)) -> pure (show n)
        Right (RPrim (VString s)) -> pure ("string " ++ T.unpack s)
        Left [d] -> let DiagnosticCode code = diagCode d in pure (T.unpack code)
        _ -> fail (show (source, budget, result))
      putStrLn (show budget ++ " " ++ source ++ " => " ++ value)
