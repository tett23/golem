module Main (main) where

import Control.Monad (forM)
import Data.Map.Strict qualified as Map
import Golem.Eval.File (Asset(..), EvalContext(..))
import Golem.Syntax (FileId(..))
import Support
import System.Exit (exitFailure)

main :: IO ()
main = do
  let ctx = baseCtx {ctxAssets=Map.fromList [("a.txt",AssetText (FileId 2) "one\ntwo\n"),("t.csv",AssetText (FileId 3) "a,b\nc,d\n")]}
      cases =
        [ ("315 I1", "@listing a.txt", []), ("315 I1", "@listing", ["G02036"])
        , ("315 I2", "@listing src=missing.txt", ["G02250"])
        , ("315 I2", "@listing a.txt src=a.txt", ["G02253"])
        , ("315 I2", "@listing missing.txt src=a.txt", ["G02253"])
        , ("316 I1", "@listing a.txt lines=1...2", [])
        , ("316 I2", "@listing a.txt lines=1-2", ["G02251"])
        , ("316 I2", "``` highlight=1-2,3-4\na\nb\nc\nd\n```", ["G02251"])
        , ("316 I2", "@listing a.txt lines=3--1", ["G02251"])
        , ("317 I1", "@table t.csv", []), ("317 I1", "@table", ["G02034"])
        , ("317 I2", "@table src=missing.csv", ["G02252"])
        , ("317 I2", "@table t.csv src=missing.csv", ["G02130"])
        , ("317 I2", "@table t.csv t.csv", ["G02130"])
        ]
  matches <- forM cases $ \(label,src,expected) -> do
    let (diagnostics,r) = evalSource ctx (src <> "\n")
        actual = map diagCodeText diagnostics
        ok = actual == expected
    print (label,src,actual,length (resultBlocks r),ok)
    pure ok
  print (length (filter id matches),length cases)
  if and matches then pure () else exitFailure
