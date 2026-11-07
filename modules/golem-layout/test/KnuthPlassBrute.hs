{- | The naive search of L7 of docs/adr/0209: every subset of the breaks
of a paragraph, each line judged by the formulas golem-layout exports
('badness', 'fitnessOf', 'lineDemerits'), and the least sum of the
demerits. It checks the search of 'breakParagraph' (its dynamic
programming and the pruning of its active nodes), not its formulas.

Only paragraphs without glyph expansion and protrusion: the amounts of
those are not exported, and writing them again would check a copy of
the formulas (docs/adr/0209, the decision 7 of the maintainer).
-}
module KnuthPlassBrute
  ( breakCandidates,
    Path (..),
    feasiblePaths,
    bruteDemerits,
  )
where

import Data.Bits (testBit)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Golem.Layout.KnuthPlass

{- | The breaks of a pass, by index: the penalties less than infinite and
the glue after a box, as 'breakParagraph' takes them; the first pass
leaves out the hyphens of the patterns (golem-layout ADR 0008).
-}
breakCandidates :: Int -> [Item] -> [Int]
breakCandidates pass items =
  [ i
  | (i, it) <- zip [0 ..] items,
    case it of
      Penalty _ p h -> p < infPenalty && (pass /= 1 || not (isPatternHyphen h))
      Glue {} -> i > 0 && isBox (arr Map.! (i - 1))
      Box {} -> False
  ]
  where
    arr = Map.fromList (zip [0 ..] items)

isBox :: Item -> Bool
isBox = \case
  Box {} -> True
  _ -> False

-- | A way to break a paragraph: its breaks, the sum of its demerits.
data Path = Path {pathBreaks :: ![Int], pathDemerits :: !Integer}
  deriving stock (Eq, Show)

{- | Every path of a pass whose lines are all feasible: each subset of the
breaks that holds every forced break, in the order of the subsets.
-}
feasiblePaths :: Params -> Sp -> Int -> [Item] -> [Path]
feasiblePaths ps width pass items =
  [ Path bs d
  | mask <- [0 :: Integer .. 2 ^ length optional - 1],
    let bs = sort (forced <> [b | (k, b) <- zip [0 ..] optional, testBit mask k]),
    -- the paragraph ends at its last item, as every path of 'breakParagraph' does
    not (null bs),
    last bs == n - 1,
    Just d <- [demeritsOf bs]
  ]
  where
    n = length items
    arr = Map.fromList (zip [0 ..] items)
    at i = arr Map.! i
    candidates = breakCandidates pass items
    isForced i = case at i of
      Penalty _ p _ -> p <= negate infPenalty
      _ -> False
    forced = filter isForced candidates
    optional = filter (not . isForced) candidates
    tol = if pass == 1 then pPretolerance ps else pTolerance ps
    -- the totals of the items [0, i): width, stretch, shrink
    prefix = Map.fromList (zip [0 ..] (scanl add (0, 0, 0) items))
    add (w, y, z) = \case
      Box w' _ -> (w + w', y, z)
      Glue w' y' z' -> (w + w', y + y', z + z')
      Penalty {} -> (w, y, z)
    sumsTo i = prefix Map.! i
    -- where a line after a break at i starts: what can be discarded is skipped
    after i
      | i < 0 = 0
      | otherwise = skip (i + 1)
      where
        skip j
          | j >= n = j
          | otherwise = case at j of
              Box {} -> j
              Penalty _ p _ | p <= negate infPenalty -> j
              _ -> skip (j + 1)
    firstBox s b = [c | j <- [s .. b - 1], Box _ c <- [at j]]
    lastBox s b = [c | j <- [b - 1, b - 2 .. s], Box _ c <- [at j]]
    flagged i = case at i of
      Penalty _ _ h -> h /= NoHyphen
      _ -> False
    -- the demerits of the lines from the start to the breaks, or Nothing if one is not feasible
    demeritsOf bs = go (-1) 2 False 0 bs
      where
        go _ _ _ total [] = Just total
        go prev prevFit prevFlagged total (b : rest) =
          let s = after prev
              (tw, ty, tz) = sumsTo b
              (sw, sy, sz) = sumsTo s
              penW = case at b of
                Penalty w _ _ -> w
                _ -> 0
              edgeS = sum (map bcEdgeStart (take 1 (firstBox s b)))
              edgeE = sum (map bcEdgeEnd (take 1 (lastBox s b)))
              natural = tw - sw + penW + edgeS + edgeE
              stretch = ty - sy + pEndStretch ps
              shrink = tz - sz
              shortfall = width - natural
              (bad, shrinking, overfull)
                | shortfall > 0 = (badness shortfall stretch, False, False)
                | shortfall == 0 = (0, False, False)
                | negate shortfall > shrink = (10000, True, True)
                | otherwise = (badness (negate shortfall) shrink, True, False)
              fit = fitnessOf shrinking bad
              pen = case at b of
                Penalty _ p _ -> p
                _ -> 0
              d =
                lineDemerits ps bad pen
                  + (if prevFlagged && flagged b then toInteger (pDoubleHyphenDemerits ps) else 0)
                  + (if abs (fit - prevFit) > 1 then toInteger (pAdjDemerits ps) else 0)
           in if overfull || bad > tol then Nothing else go b fit (flagged b) (total + d) rest

{- | The least demerits of the feasible paths of a pass, of lines of the
width given; Nothing when no path is feasible.
-}
bruteDemerits :: Params -> Sp -> Int -> [Item] -> Maybe Integer
bruteDemerits ps width pass items = case map pathDemerits (feasiblePaths ps width pass items) of
  [] -> Nothing
  ds -> Just (minimum ds)
