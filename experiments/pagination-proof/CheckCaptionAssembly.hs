{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

-- Emits the actual Knuth--Plass break positions and source-box identities
-- as Lean examples. It does not replace the general active-node proof.
module Main (main) where

import Control.Monad (replicateM)
import Data.List (intercalate)
import Data.Text qualified as T
import Golem.Layout.Japanese (ComposeEnv (ceLook), defaultComposeEnv)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (noBoxSource)
import System.Environment (getArgs)
import System.Exit (die)

box :: Int -> Sp -> Item
box ident width =
  Box width (BoxContent (T.pack (show ident)) False 0 0 ident look 0 0 [] 0 0 noBoxSource Nothing noLeaf ident)
  where
    look = ceLook (defaultComposeEnv (10 * 65536))

finish :: [Item]
finish = [glue 0 filStretch 0, Penalty 0 (-infPenalty) NoHyphen]

inputs :: [[Item]]
inputs = [zipWith identify [0 ..] items <> finish | size <- [0 .. 4], items <- replicateM size atoms]
  where
    atoms = [box 0 10, box 0 40, glue 5 20 3, Penalty 0 0 NoHyphen, Penalty 9 0 ExplicitHyphen, Penalty 0 (-infPenalty) NoHyphen, Penalty 0 (-100) NoHyphen]
    identify ident (Box width content) = Box width content {bcTag = ident}
    identify _ item = item

observations :: [([Item], Breaks)]
observations =
  [ (items, breakParagraph params (const width) items)
  | items <- inputs,
    params <- [defaultParams, defaultParams {pEndStretch = 100}],
    width <- [10, 30, 60]
  ]

boxIds :: [Item] -> [Int]
boxIds items = [bcTag content | Box _ content <- items]

leanList :: (a -> String) -> [a] -> String
leanList render values = "[" <> intercalate "," (map render values) <> "]"

leanItem :: Item -> String
leanItem item = case item of
  Box _ content -> "(.box," <> show (bcTag content) <> ")"
  Glue {} -> "(.glue,0)"
  Penalty _ penalty hyphen ->
    "(.penalty (" <> show penalty <> ") " <> (if isPatternHyphen hyphen then "true" else "false") <> ",0)"

leanExample :: ([Item], Breaks) -> String
leanExample (items, result) =
  "example : (captionAssembleWhole Prod.fst ("
    <> leanList leanItem items
    <> " : List (CaptionItemKind × Nat)) "
    <> leanList show (brPositions result)
    <> ").isSome = true ∧ ("
    <> leanList show (boxIds (concatMap lineItems (brLines result)))
    <> " : List Nat) = "
    <> leanList show (boxIds items)
    <> " := by decide"

main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> do
      let failures = [(brPositions result, boxIds items, boxIds (concatMap lineItems (brLines result))) | (items, result) <- observations, boxIds items /= boxIds (concatMap lineItems (brLines result))]
      if null failures
        then putStrLn (show (length observations) <> " actual caption-break inputs preserve source box identities")
        else die ("caption box mismatches: " <> show (take 3 failures))
    ["--lean"] -> do
      putStrLn "import Pagination"
      putStrLn "open GolemPagination"
      putStrLn ("-- " <> show (length observations) <> " finite observations, not a general active-node proof.")
      mapM_ (putStrLn . leanExample) observations
    _ -> die "usage: CheckCaptionAssembly [--lean]"
