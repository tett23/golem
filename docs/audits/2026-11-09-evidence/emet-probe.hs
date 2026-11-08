{-# LANGUAGE OverloadedStrings #-}
-- The Emet probe of the audits of 2026-11-06 and 2026-11-08, adapted to
-- the runPrim of docs/adr/0223 (the steps left come first; a value longer
-- than them is not made). The modes are those of 2026-11-08, plus modes
-- that call the other primitives that make values from small arguments
-- (String.join, List.concat, ++).
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
    ["join"] -> call "f :: String -> String\nf x = String.join x (List.map (same x) (List.range 1 20000))\nsame :: String -> Int -> String\nsame x n = x\n" [RPrim (VString (T.replicate 20000 "b"))]
    ["concat"] -> call "f :: List Int\nf = List.concat (List.map rng (List.range 1 20000))\nrng :: Int -> List Int\nrng n = List.range 1 20000\n" []
    ["append"] -> call "f :: String -> String\nf x = go 30 x\ngo :: Int -> String -> String\ngo n s = n == 0 ? s : go (n - 1) (s ++ s)\n" [RPrim (VString (T.replicate 1000 "b"))]
    _ -> error "cost | take | length | replace | control | join | concat | append"
  where
    -- the steps left are those of the default limit of 100,000,000
    cost n = case runPrim 99999999 "List.range" [PV (VInt 1), PV (VInt n)] of
      Right (_, used) -> putStrLn (show n ++ " elements; charged=" ++ show used)
      Left d -> putStrLn (show n ++ " elements; " ++ show d)
    call src args = case runIdentity (loadProgram (\_ -> pure (Right (FileId 100,TE.encodeUtf8 src))) ["main.emet"]) of
      (ds, Just p) | not (any isError ds) -> print (callFunctionCounted noHandlers p (mkSpan (FileId 1) 0 1) "main.emet" "f" args)
      (ds, _) -> print ds
