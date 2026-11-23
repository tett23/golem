{- | Extended grapheme clusters by the GB rules of UAX #29, Unicode 17.0.0
(docs/adr/0411).

The rules follow src/character.c of libgrapheme 3.0.0
(https://libs.suckless.org/libgrapheme/, Copyright 2019-2025 Laslo
Hunhold, ISC license; LICENSE-libgrapheme of this package): one cluster is
read from its first character with a fresh state, which carries the flags
of GB11 and GB12/GB13 and the level of GB9c from one pair of characters to
the next.
-}
module Golem.Unicode.Grapheme
  ( graphemeClusters,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Unicode.Ranges (RangeTable, lookupRange, rangeTable)
import Golem.Unicode.Table (GraphemeBreak (..), graphemeBreakRanges)

{- | The extended grapheme clusters of the text, in order; each is non-empty,
and together they are the text.
-}
graphemeClusters :: Text -> [Text]
graphemeClusters t = case T.uncons t of
  Nothing -> []
  Just (c, rest) ->
    let n = clusterLength (property c) (map property (T.unpack rest))
        (cluster, after) = T.splitAt n t
     in cluster : graphemeClusters after

property :: Char -> GraphemeBreak
property = lookupRange GbOther table

table :: RangeTable GraphemeBreak
table = rangeTable graphemeBreakRanges

-- | What the pairs before carry to the next pair of characters.
data State = State
  { gb11Flag :: Bool,
    gb12Flag :: Bool,
    gb9cLevel :: Int
  }

{- | The number of characters of the cluster that starts with the first
property and goes on with the others.
-}
clusterLength :: GraphemeBreak -> [GraphemeBreak] -> Int
clusterLength = go 1 (State False False 0)
  where
    go n st p0 = \case
      [] -> n
      p1 : ps ->
        let st' = advance st p0 p1
         in if joins st' p0 p1 then go (n + 1) st' p1 ps else n

-- | The state after the pair of the two properties.
advance :: State -> GraphemeBreak -> GraphemeBreak -> State
advance st p0 p1 =
  State
    { gb11Flag = gb11 (gb11Flag st),
      gb12Flag = not (gb12Flag st) && p0 == GbRegionalIndicator && p1 == GbRegionalIndicator,
      gb9cLevel = gb9c (gb9cLevel st)
    }
  where
    -- GB11: Extended_Pictographic Extend* ZWJ, seen up to the pair
    gb11 = \case
      False -> p0 == GbExtendedPictographic && isExtendOrZwj p1
      True ->
        (isZwj p0 && p1 == GbExtendedPictographic)
          || (isExtend p0 && isExtendOrZwj p1)
          || (p0 == GbExtendedPictographic && isExtendOrZwj p1)
    -- GB9c: 1 after a consonant, 2 after InCB Extend, 3 after a linker
    gb9c level
      | level == 0 && p0 == GbInCBConsonant = 1
      | (level == 1 || level == 2) && isInCBExtend p0 = 2
      | (level == 1 || level == 2) && isInCBLinker p0 = 3
      | level == 3 && (isInCBExtend p0 || isInCBLinker p0) = 3
      | p0 == GbInCBConsonant = 1
      | otherwise = 0

-- | Whether no boundary falls between the two characters.
joins :: State -> GraphemeBreak -> GraphemeBreak -> Bool
joins st p0 p1
  -- GB3
  | p0 == GbCR && p1 == GbLF = True
  -- GB4
  | isControl p0 = False
  -- GB5
  | isControl p1 = False
  -- GB6
  | p0 == GbL && p1 `elem` [GbL, GbV, GbLV, GbLVT] = True
  -- GB7
  | p0 `elem` [GbLV, GbV] && p1 `elem` [GbV, GbT] = True
  -- GB8
  | p0 `elem` [GbLVT, GbT] && p1 == GbT = True
  -- GB9
  | isExtendOrZwj p1 = True
  -- GB9a
  | p1 == GbSpacingMark = True
  -- GB9b
  | p0 == GbPrepend = True
  -- GB9c
  | gb9cLevel st == 3 && p1 == GbInCBConsonant = True
  -- GB11
  | gb11Flag st && isZwj p0 && p1 == GbExtendedPictographic = True
  -- GB12, GB13
  | gb12Flag st = True
  -- GB999
  | otherwise = False

isControl :: GraphemeBreak -> Bool
isControl p = p == GbControl || p == GbCR || p == GbLF

isExtend :: GraphemeBreak -> Bool
isExtend p = p == GbExtend || p == GbExtendInCBExtend || p == GbExtendInCBLinker

isZwj :: GraphemeBreak -> Bool
isZwj p = p == GbZWJ || p == GbZWJInCBExtend

isExtendOrZwj :: GraphemeBreak -> Bool
isExtendOrZwj p = isExtend p || isZwj p

isInCBExtend :: GraphemeBreak -> Bool
isInCBExtend p = p == GbInCBExtend || p == GbZWJInCBExtend || p == GbExtendInCBExtend

isInCBLinker :: GraphemeBreak -> Bool
isInCBLinker p = p == GbInCBLinker || p == GbExtendInCBLinker
