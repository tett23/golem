-- | Lookups in the generated tables of ranges (docs/adr/0411).
module Golem.Unicode.Ranges
  ( RangeTable,
    rangeTable,
    lookupRange,
  )
where

import Data.Char (ord)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap

-- | Ranges keyed by their first code point, each with its last one and value.
newtype RangeTable a = RangeTable (IntMap (Int, a))

-- | The table of ascending, disjoint ranges.
rangeTable :: [(Int, Int, a)] -> RangeTable a
rangeTable rs = RangeTable (IntMap.fromDistinctAscList [(lo, (hi, v)) | (lo, hi, v) <- rs])

-- | The value of the range of a character, or the default outside them.
lookupRange :: a -> RangeTable a -> Char -> a
lookupRange def (RangeTable m) c =
  case IntMap.lookupLE n m of
    Just (_, (hi, v)) | n <= hi -> v
    _ -> def
  where
    n = ord c
