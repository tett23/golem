-- | Script predicates used by bibliography sort-key warnings (root ADR 0470).
module Golem.Unicode.Script (isHanOrKana) where

import Golem.Unicode.Ranges (RangeTable, lookupRange, rangeTable)
import Golem.Unicode.ScriptTable (hanOrKanaRanges)

-- | Whether Unicode Script is Han, Hiragana or Katakana.
isHanOrKana :: Char -> Bool
isHanOrKana = lookupRange False scriptTable

scriptTable :: RangeTable Bool
scriptTable = rangeTable hanOrKanaRanges
