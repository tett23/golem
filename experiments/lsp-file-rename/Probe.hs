module Main where
import Control.Monad (unless)
import Data.Text qualified as T
import Golem.Syntax
import ReferencePlan

main :: IO ()
main = do
  let pair = ("章","新章")
      source = T.unlines ["😀", "@import ./章/a.gm as one", "@import \"章/a.gm\" as two", "@import 章外/a.gm as sibling", "本文 章/a.gm"]
      doc = [ (LineCol 1 8,LineCol 1 16,"新章/a.gm"), (LineCol 2 8,LineCol 2 16,"\"新章/a.gm\"")]
      checks =
        [ ("folder (2 sites, no prose or prefix sibling)", plan [pair] source == Right doc)
        , ("duplicate pair",plan [pair,pair] source == Right doc)
        , ("consistent ancestor and child",plan [pair,("章/a.gm","新章/a.gm")] source == Right doc)
        , ("conflicting ancestor and child",either (const True) (const False) (plan [pair,("章/a.gm","別.gm")] source))
        , ("single file", renamePath [("章/a.gm","別.gm")] "章/../章/a.gm" == Right "別.gm")
        , ("empty operation", plan [] source == Right [])
        , ("outside root",either (const True) (const False) (renamePath [pair] "../章/a.gm"))
        , ("simultaneous map", renamePath [("a","b"),("b","c")] "a" == Right "b")
        , ("unsaved buffer chosen by caller",plan [pair] "未保存😀\n@import 章/a.gm as x\n" == Right [(LineCol 1 8,LineCol 1 14,"新章/a.gm")])
        ]
  mapM_ print checks
  print (plan [pair] source)
  unless (all snd checks) (fail "reference edit mismatch")
