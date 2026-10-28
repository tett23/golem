{- | Placing sidenotes in the sidenote column (golem-layout ADR 0006).
Positions are measured downwards from the top of the column.
-}
module Golem.Layout.Sidenotes
  ( placeSidenotes,
    SidenoteError (..),
  )
where

import Golem.Length (Sp)

data SidenoteError
  = -- | the sidenote at this index is taller than the column
    TooTall !Int
  | -- | the sidenote at this index does not fit even after packing upwards
    DoesNotFit !Int
  deriving stock (Eq, Show)

{- | Given the column height, the gap between notes (half the line pitch)
and each note's wanted top and height in order of appearance, returns
the tops. Notes are pushed down past the previous one, then pulled up
from the bottom if the last overflows; order is kept and no note rises
above the column.
-}
placeSidenotes :: Sp -> Sp -> [(Sp, Sp)] -> Either SidenoteError [Sp]
placeSidenotes columnH gap notes
  | Just i <- lookupIndex (\(_, h) -> h > columnH) notes = Left (TooTall i)
  | otherwise =
      let down = reverse (snd (foldl' pushDown (Nothing, []) notes))
          heights = map snd notes
          up = pullUp (zip down heights)
          -- pushing down once more from the top shows which note cannot fit
          final = reverse (snd (foldl' pushDown (Nothing, []) (zip up heights)))
       in case [i | (i, (t, h)) <- zip [0 ..] (zip final heights), t < 0 || t + h > columnH] of
            (i : _) -> Left (DoesNotFit i)
            [] -> Right final
  where
    pushDown (prevBottom, acc) (want, h) =
      let top = maybe (max 0 want) (\b -> max (max 0 want) (b + gap)) prevBottom
       in (Just (top + h), top : acc)
    -- from the last note upwards: each bottom must stay above the next top
    pullUp placed =
      let go [] _ = []
          go ((t, h) : rest) limit =
            let t' = max 0 (min t (limit - h))
             in t' : go rest (t' - gap)
       in reverse (go (reverse placed) columnH)
    lookupIndex p xs = case [i | (i, x) <- zip [0 ..] xs, p x] of
      (i : _) -> Just i
      [] -> Nothing
