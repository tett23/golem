{-# LANGUAGE OverloadedStrings #-}
-- Probe for Golem.Pdf.Import.contentOperations (docs/adr 0232), used by
-- figure import and preflight G09021. Checks termination on adversarial
-- content streams: unbalanced BI/ID/EI, no EI, nested dicts/arrays, huge
-- repeats. Reports the number of operations or Nothing, never hanging
-- beyond the external time limit.
import Golem.Pdf.Import (contentOperations)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C
import System.Environment (getArgs)

cases :: [(String, BS.ByteString)]
cases =
  [ ("bi-no-id-ei", "BI /W 1 /H 1 ")
  , ("bi-no-ei", C.concat ["BI /W 1 ID ", C.replicate 1000000 'x'])
  , ("bi-id-only", "q BI ID ")
  , ("many-bi", C.concat (replicate 200000 "BI /A 1 ID xx EI "))
  , ("open-string", C.concat ["(", C.replicate 5000000 'a'])
  , ("open-array", C.concat (replicate 2000000 "["))
  , ("open-dict", C.concat (replicate 1000000 "<<"))
  , ("deep-nums", C.concat (replicate 2000000 "0 0 0 0 0 rg "))
  , ("bad-hex", C.concat ["<", C.replicate 5000000 'z'])
  , ("nested-id-ei", C.concat (replicate 500000 "BI ID EI "))
  , ("random-delims", C.replicate 5000000 '%')  -- '%' comment-ish bytes
  ]

main :: IO ()
main = do
  as <- getArgs
  let run (n, b) = case contentOperations b of
        Nothing -> putStrLn (n ++ ": Nothing (" ++ show (BS.length b) ++ " bytes)")
        Just ops -> putStrLn (n ++ ": " ++ show (length ops) ++ " ops (" ++ show (BS.length b) ++ " bytes)")
  case as of
    [] -> mapM_ run cases
    xs -> mapM_ (\x -> maybe (putStrLn (x ++ ": no such case")) (run . (,) x) (lookup x cases)) xs
