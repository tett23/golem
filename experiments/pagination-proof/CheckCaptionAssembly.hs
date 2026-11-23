{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Emits the actual Knuth--Plass break positions and source-box identities
-- as Lean examples (--lean), and the values of the evaluation for
-- CaptionValues.lean (--values). It does not replace the general
-- active-node proof.
module Main (main) where

import Control.Monad (replicateM)
import Data.List (intercalate)
import Data.Ratio (denominator, numerator)
import Data.Text qualified as T
import Golem.Layout.Japanese (ComposeEnv (ceLook), defaultComposeEnv)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (noBoxSource)
import System.Environment (getArgs)
import System.Exit (die)

box :: Int -> Sp -> Item
box ident width =
  Box width (BoxContent (T.pack (show ident)) False 0 0 ident look 0 0 [] 0 0 noBoxSource Nothing noLeaf ident Nothing)
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

-- The values of the evaluation (root ADR 0352, condition 2). With
-- --values, the lines "in ..." are the input of CaptionValues.lean and the
-- lines "out ..." what it must print for them: the formulas of badness,
-- fitness and line demerits on boundary values, then, for every caption
-- the breaker breaks, its demerits (but in the overfull pass) and, for each
-- line, its adjustment ratio and its overflow.

-- A box that protrudes and has edges, and a soft hyphen, for the inputs
-- with protrusion.
protrudingBox :: Item
protrudingBox =
  Box 25 (BoxContent "p" False 2 3 0 look 1 4 [] 0 0 noBoxSource Nothing noLeaf 0 Nothing)
  where
    look = ceLook (defaultComposeEnv (10 * 65536))

valueObservations :: [(Params, Sp, [Item], Breaks)]
valueObservations =
  [ (params, width, items, breakParagraph params (const width) items)
  | (params, size, atoms) <- plain <> extended,
    items <- [zipWith identify [0 ..] chosen <> finish | chosen <- concatMap (`replicateM` atoms) [0 .. size]],
    width <- [10, 30, 60]
  ]
  where
    plainAtoms = [box 0 10, box 0 40, glue 5 20 3, Penalty 0 0 NoHyphen, Penalty 9 0 ExplicitHyphen, Penalty 0 (-infPenalty) NoHyphen, Penalty 0 (-100) NoHyphen]
    plain = [(p, 4, plainAtoms) | p <- [defaultParams, defaultParams {pEndStretch = 100}]]
    extended =
      [ (p, 3, plainAtoms <> [protrudingBox, Penalty 6 50 (SoftHyphen 2)])
      | p <- [defaultParams {pProtrusion = True}, defaultParams {pPullInFirst = True}, defaultParams {pEmergencyStretch = 10}]
      ]
    identify ident (Box width content) = Box width content {bcTag = ident}
    identify _ item = item

flag :: Bool -> String
flag b = if b then "1" else "0"

itemToken :: Item -> String
itemToken = \case
  Box w c -> intercalate ":" ["b", sp w, sp (bcProtrudeStart c), sp (bcProtrudeEnd c), sp (bcEdgeStart c), sp (bcEdgeEnd c)]
  Glue w y z _ _ -> intercalate ":" ["g", sp w, sp y, sp z]
  Penalty w p h -> intercalate ":" ["p", sp w, show p, flag (flagged h), hyphenEnd h]
  where
    flagged = \case
      PatternHyphen _ -> True
      ExplicitHyphen -> True
      SoftHyphen _ -> True
      _ -> False
    hyphenEnd = \case
      PatternHyphen q -> sp q
      SoftHyphen q -> sp q
      _ -> "-"

sp :: Sp -> String
sp = show . unSp

valueLines :: [(String, String)]
valueLines =
  [("bad " <> show t <> " " <> show s, show (badness (Sp t) (Sp s))) | t <- spans, s <- (-1) : spans]
    <> [("fit " <> flag sh <> " " <> show b, show (fitnessOf sh b)) | sh <- [False, True], b <- [0, 12, 13, 99, 100, 10000]]
    <> [ ("dem " <> show lp <> " " <> show b <> " " <> show p, show (lineDemerits defaultParams {pLinePenalty = lp} b p))
       | lp <- [-10010, -10000, -1, 0, 10, 9990, 10000],
         b <- [0, 1, 9990, 10000],
         p <- [-10001, -10000, -9999, -1, 0, 1, 9999, 10000]
       ]
    <> map observation valueObservations
  where
    spans = [0, 1, 296, 297, 1290, 1291, 65536, 1663496, 1663497, 7230584, 7230585, 2 ^ (50 :: Int)]
    observation (params, width, items, result) =
      ( unwords
          ( ["obs", show (brPass result), show (pLinePenalty params), show (pAdjDemerits params), show (pDoubleHyphenDemerits params)]
              <> [sp (pEndStretch params), sp (pEmergencyStretch params), flag (pPullInFirst params), flag (pProtrusion params), sp width]
              <> map itemToken items
              <> ["|"]
              <> map show (brPositions result)
          ),
        unwords
          ( (if brPass result < 4 then show (brDemerits result) else "-")
              : [show (numerator r) <> "/" <> show (denominator r) <> ":" <> sp (lineOverflow l) | l <- brLines result, let r = lineRatio l]
          )
      )

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
    ["--values"] -> mapM_ (\(i, o) -> putStrLn ("in " <> i) >> putStrLn ("out " <> o)) valueLines
    _ -> die "usage: CheckCaptionAssembly [--lean | --values]"
