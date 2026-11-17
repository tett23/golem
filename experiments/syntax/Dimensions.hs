module Main (main) where

import Control.Monad (forM)
import Data.Text qualified as T
import Golem.Project.Style (Dim (..), parseDim, parseStyle)
import Golem.Syntax (FileId (..), diagCode)
import System.Exit (exitFailure)

main :: IO ()
main = do
  let canonical = parseDim "0pt"
      probes =
        [ ("319 I1 parseDim " ++ show input, parseDim input == canonical)
        | input <- ["0", "-0"]
        ] ++
        [ ("319 I1 TOML bleed " ++ show input, result input == result "\"0pt\"")
        | input <- ["0", "-0", "+0", "\"0\"", "\"-0\""]
        ] ++
        [ ("319 I2 reject " ++ show input, either (const True) (const False) (result input))
        | input <- ["1", "0.0", "\"00\"", "\"+0\"", "\"\""]
        ]
      result v = either (Left . map diagCode) Right (parseStyle (FileId 0) ("[page]\nsize=\"A5\"\nbleed=" <> v <> "\n"))
  print (canonical, map parseDim ["0","-0","0pt","1"])
  passed <- forM probes $ \(label,ok) -> putStrLn (label ++ " " ++ if ok then "PASS" else "FAIL") >> pure ok
  print (length (filter id passed), length probes)
  if and passed then pure () else exitFailure
