module Main (main) where

import Control.Monad (forM)
import Data.Map.Strict qualified as Map
import Golem.Doc.IR (BlockBody(..),Code(..),CodeLine(..))
import Golem.Eval.File (Asset(..), EvalContext(..))
import Golem.Syntax (FileId(..))
import Support
import System.Exit (exitFailure)

main :: IO ()
main = do
  let ctx = baseCtx {ctxAssets=Map.fromList [("a.txt",AssetText (FileId 2) "one\ntwo\nthree\nfour\nfive\nsix\nseven\n"),("t.csv",AssetText (FileId 3) "a,b\nc,d\n")]}
      cases =
        [ ("315 I2", "@listing a.txt a.txt", ["G02253"])
        , ("315 I2", "@listing a.txt src=a.txt", ["G02253"])
        , ("315 I2", "@listing src=a.txt src=a.txt", ["G02077"])
        , ("315 I2", "@listing a.txt src=a.txt src=b.txt", ["G02077"])
        , ("316 I1", "@listing a.txt lines=\"1...3, 5...7\"", [])
        , ("316 I1", "@listing a.txt lines=\"1.,.3, 5..,7\"", ["G02105"])
        , ("316 I1", "@listing a.txt lines=-1", ["G02110"])
        , ("316 I1", "@set n = 0\n\n@listing a.txt lines=[= n]", ["G02037"])
        , ("316 I1", "@set n = -1\n\n@listing a.txt lines=[= n]", ["G02103"])
        , ("319 I2", "@blank-line 0", [])
        , ("319 I2", "@blank-line 2\n@blank-line 0", [])
        , ("319 I2", "@blank-line 0\n@blank-line 2", [])
        ]
  matches <- forM cases $ \(label,src,expected) -> do
    let (diagnostics,r) = evalSource ctx (src <> "\n")
        actual = map diagCodeText diagnostics
        ok = actual == expected
    print (label,src,actual,length (resultBlocks r),ok)
    pure ok
  let bodies src = resultBodies (snd (evalSource ctx src))
      selected = [ (clNumber line,clText line) | CodeBlock c <- bodies "@listing a.txt lines=\"1...3, 5...7\"\n", line <- codeLines c ]
      checks = [ ("316 I1 selected numbered lines", selected == zip (map Just [1,2,3,5,6,7]) ["one","two","three","five","six","seven"])
               , ("319 I2 left identity", bodies "@blank-line 0\n@blank-line 2\n" == [BlankLines 2])
               , ("319 I2 right identity", bodies "@blank-line 2\n@blank-line 0\n" == [BlankLines 2])
               , ("319 I2 zero", null (bodies "@blank-line 0\n"))
               ]
      outcomes = matches ++ map snd checks
  mapM_ print checks
  print (length (filter id outcomes),length outcomes)
  if and outcomes then pure () else exitFailure
