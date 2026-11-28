{- | Locale-independent Latin bibliography keys (root ADR 0470).
The Unicode 17 tables remove canonical accents only from Latin bases.
They do not transliterate strokes or ligatures, normalize other scripts,
or remove variation selectors and other marks with combining class zero.
-}
module Golem.Unicode.Latin
  ( stripLatinDiacritics,
    latinSortKey,
  )
where

import Data.Char (chr, ord)
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Unicode.Grapheme (graphemeClusters)
import Golem.Unicode.LatinTable (latinBases, latinLowercase, latinRanges, nonstarterRanges)
import Golem.Unicode.Ranges (RangeTable, lookupRange, rangeTable)

-- | Keep case and non-Latin text while removing canonical Latin accents.
stripLatinDiacritics :: Text -> Text
stripLatinDiacritics = T.concat . map stripCluster . graphemeClusters
  where
    stripCluster cluster = case T.uncons cluster of
      Nothing -> ""
      Just (first, rest) ->
        let base = chr (IntMap.findWithDefault (ord first) (ord first) bases)
         in if lookupRange False latinCharacters base
              then T.cons base (T.filter (not . lookupRange False nonstarters) rest)
              else cluster

-- | Lowercase with Latin diacritics removed, without consulting a locale.
latinSortKey :: Text -> Text
latinSortKey = T.map lower . T.toLower . stripLatinDiacritics
  where
    -- Include Latin mappings newer than the host text/Char tables.
    lower character = chr (IntMap.findWithDefault (ord character) (ord character) lowercase)

bases :: IntMap.IntMap Int
bases = IntMap.fromDistinctAscList latinBases

lowercase :: IntMap.IntMap Int
lowercase = IntMap.fromDistinctAscList latinLowercase

latinCharacters, nonstarters :: RangeTable Bool
latinCharacters = rangeTable latinRanges
nonstarters = rangeTable nonstarterRanges
