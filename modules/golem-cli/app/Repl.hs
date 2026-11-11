module Repl (run) where

import Control.Exception (AsyncException (UserInterrupt), tryJust)
import Control.Monad (when)
import Data.ByteString qualified as BS
import Data.Char (isControl, ord)
import Data.List (intercalate)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as LT
import Data.Text.Lazy.IO qualified as LTIO
import Golem.Emet (Result (..), evaluateExpression, stepLimit)
import Golem.Eval.Expr (valueText)
import Golem.Eval.Value (Value (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), spanEnd, spanStart)
import Numeric (showHex)
import System.Exit
import System.IO

data Entry = Ready | More BS.ByteString [Diagnostic]

showResult :: Result -> String
showResult = \case
  RPrim (VString s) -> quoted '"' (T.unpack s)
  RPrim (VBool b) -> if b then "True" else "False"
  RPrim v -> T.unpack (valueText v)
  RChar c -> quoted '\'' [c]
  RCon c [] -> T.unpack c
  RCon c fields -> "(" <> unwords (T.unpack c : map showResult fields) <> ")"
  RList xs -> "[" <> intercalate ", " (map showResult xs) <> "]"
  RTuple xs -> "(" <> intercalate ", " (map showResult xs) <> ")"
  RFun -> "<function>"
  where
    quoted q cs = q : concatMap (escape q) cs ++ [q]
    escape q c | c == q || c == '\\' = ['\\', c]
    escape _ '\n' = "\\n"
    escape _ '\t' = "\\t"
    escape _ c | isControl c = "\\u{" <> showHex (ord c) "}"
    escape _ c = [c]

report :: Diagnostic -> IO ()
report d = do
  let DiagnosticCode code = diagCode d
      sp = diagSpan d
      site = T.pack (" [" ++ show (spanStart sp) ++ "," ++ show (spanEnd sp) ++ "): ")
  TIO.hPutStrLn stderr (code <> site <> diagMessage d)

submit :: Bool -> BS.ByteString -> IO (Bool, Entry)
submit interactive input
  | BS.all (`elem` [32, 9, 10]) input = pure (True, Ready)
  | otherwise = case evaluateExpression stepLimit input of
      Left ds
        | not (null ds) && all needsMore ds -> pure (True, More input ds)
        | otherwise -> mapM_ report ds >> pure (False, Ready)
      Right value -> do
        when interactive (TIO.putStr "=> ")
        LTIO.hPutStrLn stdout (LT.pack (showResult value))
        hFlush stdout
        pure (True, Ready)
  where
    needsMore d =
      let DiagnosticCode code = diagCode d
          sp = diagSpan d
       in code `elem` ["E01100", "E01101"] && spanStart sp == BS.length input && spanEnd sp == BS.length input

run :: IO ExitCode
run = do
  inputTTY <- hIsTerminalDevice stdin
  promptTTY <- hIsTerminalDevice stderr
  let interactive = inputTTY && promptTTY
      interrupt UserInterrupt | interactive = Just ()
      interrupt _ = Nothing
      cancel ok = hPutStrLn stderr "" >> loop ok Ready
      finish ok = pure (if ok then ExitSuccess else ExitFailure 1)
      loop !ok entry = do
        when interactive $ do
          hPutStr stderr (case entry of Ready -> "emet> "; More {} -> "....> ")
          hFlush stderr
        tryJust interrupt (hIsEOF stdin >>= \eof -> if eof then pure Nothing else Just <$> BS.hGetLine stdin) >>= \case
          Left () -> cancel ok
          Right line -> consume ok entry line
      consume !ok entry = \case
        Nothing -> case entry of
          Ready -> finish ok
          More _ ds -> mapM_ report ds >> finish False
        Just s -> do
          let input = case entry of Ready -> s; More previous _ -> previous <> "\n" <> s
          tryJust interrupt (submit interactive input) >>= \case
            Left () -> cancel ok
            Right (passed, next) -> loop (ok && passed) next
  loop True Ready
