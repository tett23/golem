module Repl (run) where

import Control.Exception (AsyncException (UserInterrupt), tryJust)
import Control.Monad (when)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isControl, ord)
import Data.IORef
import Data.List (intercalate)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as LT
import Data.Text.Lazy.Encoding qualified as LTE
import Golem.Emet (Result (..), evaluateExpression)
import Golem.Eval.Expr (valueText)
import Golem.Eval.Value (Value (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), spanEnd, spanStart)
import Numeric (showHex)
import System.Exit
import System.IO

data Line = End | TooLong | Line BS.ByteString

data Entry = Ready | More BS.ByteString [Diagnostic]

limit :: Int
limit = 4096

-- | Keep at most one bounded line and one input chunk, including when a pipe never writes LF.
readLine :: IORef BS.ByteString -> IO Line
readLine pending = go 0 []
  where
    go !count !parts = do
      buffered <- readIORef pending
      chunk <- if BS.null buffered then BS.hGetSome stdin limit else pure buffered
      writeIORef pending BS.empty
      if BS.null chunk
        then pure (if count == 0 then End else finish count parts)
        else do
          let (before, end) = BS.break (== 10) chunk
              size = min (limit + 1) (count + BS.length before)
              keep = if size > limit then [] else before : parts
          if BS.null end
            then go size keep
            else writeIORef pending (BS.tail end) >> pure (finish size keep)
    finish n xs = if n > limit then TooLong else Line (BS.concat (reverse xs))

-- | Render only the prefix the REPL may print. Large nested lists never become one strict String.
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
  | otherwise = case evaluateExpression 100000 input of
      Left ds
        | not (null ds) && all needsMore ds -> pure (True, More input ds)
        | otherwise -> mapM_ report ds >> pure (False, Ready)
      Right value ->
        let output = LT.pack (showResult value)
         in if BL.length (BL.take (fromIntegral limit + 1) (LTE.encodeUtf8 output)) > fromIntegral limit
              then hPutStrLn stderr "REPL の出力が 4096 バイトを超えました" >> pure (False, Ready)
              else do
                when interactive (TIO.putStr "=> ")
                TIO.putStrLn (LT.toStrict output)
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
  pending <- newIORef BS.empty
  let interactive = inputTTY && promptTTY
      interrupt UserInterrupt | interactive = Just ()
      interrupt _ = Nothing
      cancel ok = writeIORef pending BS.empty >> hPutStrLn stderr "" >> loop ok Ready
      finish ok = pure (if ok then ExitSuccess else ExitFailure 1)
      overflow = hPutStrLn stderr "REPL の入力が 4096 バイトを超えました" >> loop False Ready
      loop !ok entry = do
        when interactive $ do
          hPutStr stderr (case entry of Ready -> "emet> "; More {} -> "....> ")
          hFlush stderr
        tryJust interrupt (readLine pending) >>= \case
          Left () -> cancel ok
          Right line -> consume ok entry line
      consume !ok entry = \case
        End -> case entry of
          Ready -> finish ok
          More _ ds -> mapM_ report ds >> finish False
        TooLong -> overflow
        Line s -> do
          let input = case entry of Ready -> s; More previous _ -> previous <> "\n" <> s
          if BS.length input > limit
            then overflow
            else do
              tryJust interrupt (submit interactive input) >>= \case
                Left () -> cancel ok
                Right (passed, next) -> loop (ok && passed) next
  loop True Ready
