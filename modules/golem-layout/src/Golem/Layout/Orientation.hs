{- | The orientation of characters in vertical text: the Vertical_Orientation
property of UAX #50 (golem-driver ADR 0015). The table is generated from
Unicode's VerticalOrientation.txt by scripts/gen-vertical-orientation.sh.
-}
module Golem.Layout.Orientation
  ( Orientation (..),
    verticalOrientation,
    turnsInVertical,
    orientationRanges,
    orientationVersion,
  )
where

import Data.Map.Strict qualified as Map
import Golem.Layout.Orientation.Table

-- | Vertical_Orientation of UAX #50.
data Orientation = Upright | Rotated | TransformedUpright | TransformedRotated
  deriving stock (Eq, Show)

-- | The ranges of the table as code points, ascending and disjoint.
orientationRanges :: [(Int, Int, Orientation)]
orientationRanges = [(lo, hi, fromVo v) | (lo, hi, v) <- voRanges]

-- | The file the table comes from, such as @VerticalOrientation-18.0.0.txt@.
orientationVersion :: String
orientationVersion = unicodeVersion

fromVo :: Vo -> Orientation
fromVo = \case
  U -> Upright
  R -> Rotated
  Tu -> TransformedUpright
  Tr -> TransformedRotated

-- | The ranges by their first code point, searched by bisection.
table :: Map.Map Int (Int, Orientation)
table = Map.fromDistinctAscList [(lo, (hi, o)) | (lo, hi, o) <- orientationRanges]

{- | The value of a character; one the file does not list takes the value
of its @missing line.
-}
verticalOrientation :: Char -> Orientation
verticalOrientation c =
  let cp = fromEnum c
   in case Map.lookupLE cp table of
        Just (_, (hi, o)) | cp <= hi -> o
        _ -> fromVo missingValue

-- | R and Tr: turned 90° clockwise when the font has no vertical form.
turnsInVertical :: Char -> Bool
turnsInVertical c = verticalOrientation c `elem` [Rotated, TransformedRotated]
