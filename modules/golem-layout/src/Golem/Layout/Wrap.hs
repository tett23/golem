{- | Text wrapped around figures (golem-layout ADR 0004): an exclusion
area beside the text, rounded up to whole grid lines, turned into the
line lengths L*(i) of the paragraph that follows.
-}
module Golem.Layout.Wrap
  ( Wrap (..),
    Exclusion (..),
    exclusion,
    wrappedLineWidth,
  )
where

import Golem.Doc.IR (Wrap (..))
import Golem.Layout.KnuthPlass (Sp (..))

data Exclusion = Exclusion
  { exSide :: !Wrap,
    -- | across the lines: the figure width plus the gap
    exWidth :: !Sp,
    -- | how many grid lines the area covers
    exLines :: !Int
  }
  deriving stock (Eq, Show)

{- | The exclusion area of a figure: its size (with caption) plus the wrap
gap; the extent along the line progression is rounded up to grid lines.
-}
exclusion :: Wrap -> Sp -> Sp -> Sp -> Sp -> Exclusion
exclusion side pitch gap figWidth figDepth =
  Exclusion side (figWidth + gap) (fromInteger (unSp (figDepth + gap + pitch - 1) `div` unSp pitch))

{- | L*(i) for a paragraph starting @offset@ grid lines after the top of
the exclusion area.
-}
wrappedLineWidth :: Sp -> Exclusion -> Int -> Int -> Sp
wrappedLineWidth full ex offset i
  | offset + i < exLines ex = full - exWidth ex
  | otherwise = full
