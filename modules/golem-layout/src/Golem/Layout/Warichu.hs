-- | The two source-preserving lines of a cutting note (root ADR 0380).
module Golem.Layout.Warichu (splitWarichu) where

import Data.List (minimumBy)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Length (Sp)
import Golem.Unicode.Grapheme (graphemeClusters)

{- | Measure each grapheme once, then minimise the wider sum of advances.
The stable minimum keeps the earliest boundary on a tie, including the
boundary before a one-grapheme note. Empty text has the sole boundary 0.
-}
splitWarichu :: (Text -> Sp) -> Text -> (Text, Text)
splitWarichu measure text = (T.concat first, T.concat second)
  where
    units = graphemeClusters text
    advances = map measure units
    prefixes = scanl (+) 0 advances
    total = sum advances
    width (_, before) = max before (total - before)
    (boundary, _) = minimumBy (comparing width) (zip [0 ..] prefixes)
    (first, second) = splitAt boundary units
