{- | Whether a character is a letter or a number by its General_Category
(L* or N*) of Unicode 17.0.0 (docs/adr/0411), the table of the word count
of the manuscript statistics (docs/adr/0355). Unlike 'Data.Char.generalCategory',
the version does not follow GHC's base.
-}
module Golem.Unicode.Category
  ( isLetterOrNumber,
  )
where

import Golem.Unicode.Ranges (RangeTable, lookupRange, rangeTable)
import Golem.Unicode.Table (letterOrNumberRanges)

-- | Whether the General_Category of the character starts with L or N.
isLetterOrNumber :: Char -> Bool
isLetterOrNumber = lookupRange False table

table :: RangeTable Bool
table = rangeTable [(lo, hi, True) | (lo, hi) <- letterOrNumberRanges]
