{-# LANGUAGE OverloadedStrings #-}
import Data.Functor.Identity (runIdentity)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet
import Golem.Emet.Prim
import Golem.Eval.Value (Value(..))
import Golem.Syntax
import System.Environment (getArgs)

main = do
  args <- getArgs
  case args of
    ["cost"] -> mapM_ cost [10, 9223372036854775808, 18446744073709551616]
    ["take"] -> call "f :: List Int\nf = List.take 3 (List.range 1 18446744073709551616)\n" []
    ["length"] -> call "f :: Nat\nf = List.length (List.range 1 18446744073709551616)\n" []
    ["replace"] -> call "f :: String -> String -> String\nf x y = String.replace \"a\" x y\n" [RPrim (VString (T.replicate 20000 "b")),RPrim (VString (T.replicate 20000 "a"))]
    ["control"] -> call "f :: List Int\nf = List.range 1 100000001\n" []
    _ -> error "cost | take | length | replace | control"
  where
    cost n = case runPrim "List.range" [PV (VInt 1), PV (VInt n)] of
      Right (_, used) -> putStrLn (show n ++ " elements; charged=" ++ show used)
      Left d -> print d
    call src args = case runIdentity (loadProgram (\_ -> pure (Right (FileId 100,TE.encodeUtf8 src))) ["main.emet"]) of
      (ds, Just p) | not (any isError ds) -> print (callFunctionCounted noHandlers p (mkSpan (FileId 1) 0 1) "main.emet" "f" args)
      (ds, _) -> print ds
