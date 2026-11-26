{- | Text wrapped around figures (golem-layout ADR 0004): an exclusion
area beside the text, rounded up to whole grid lines, turned into the
line lengths L*(i) of the paragraph that follows.

The area is its side and the text-side edge it has within a band across
the lines (root ADR 0464): a rectangle has the same edge in every band,
the width of the figure, so its lines lose what they lost before; a
figure with an outline has the edge of the outline placed on its image,
clipped to the image, together with the rectangle of its caption. A line
loses the edge within its band widened by the wrap gap on both sides,
and the gap.
-}
module Golem.Layout.Wrap
  ( Wrap (..),
    Exclusion (..),
    exclusion,
    PlacedOutline (..),
    placeOutline,
    outlinedExclusion,
    lineTake,
    wrappedLineWidth,
  )
where

import Golem.Doc.IR (Wrap (..))
import Golem.Geometry (FillRule (..))
import Golem.Geometry.Polygon (RPoint, flattenPathWith, indexPolygons, reachInIndex)
import Golem.Layout.KnuthPlass (Sp (..))
import Golem.Project.PathData (Path)

{- | An exclusion area: its side, the most a line loses, how many grid
lines it covers, the wrap gap, and its edge in a band (root ADR 0464):
given the start and the end of a band across the lines (from the top of
the area), the text-side edge of the area within it, as a distance from
the edge of the column on its side, or Nothing where the band does not
meet the area.
-}
data Exclusion = Exclusion
  { exSide :: !Wrap,
    -- | across the lines: the figure width plus the gap, the most a line loses
    exWidth :: !Sp,
    -- | how many grid lines the area covers
    exLines :: !Int,
    -- | the wrap gap
    exGap :: !Sp,
    -- | the text-side edge within a band across the lines (root ADR 0464): see 'Exclusion'
    exEdge :: Rational -> Rational -> Maybe Rational
  }

instance Show Exclusion where
  showsPrec d ex =
    showParen (d > 10) $
      showString "Exclusion "
        . showsPrec 11 (exSide ex)
        . showString " "
        . showsPrec 11 (exWidth ex)
        . showString " "
        . showsPrec 11 (exLines ex)
        . showString " "
        . showsPrec 11 (exGap ex)

{- | The exclusion area of a figure: its size (with caption) plus the wrap
gap; the extent along the line progression is rounded up to grid lines.
Its edge is the width of the figure in every band.
-}
exclusion :: Wrap -> Sp -> Sp -> Sp -> Sp -> Exclusion
exclusion side pitch gap figWidth figDepth =
  Exclusion side (figWidth + gap) (areaLines pitch gap figDepth) gap (\_ _ -> Just (fromInteger (unSp figWidth)))

areaLines :: Sp -> Sp -> Sp -> Int
areaLines pitch gap figDepth = fromInteger (unSp (figDepth + gap + pitch - 1) `div` unSp pitch)

{- | An outline placed on its figure (root ADR 0464), in the coordinates
of the area: along the lines from the edge of the column on the side of
the figure, across them from the top of the area.
-}
data PlacedOutline = PlacedOutline
  { -- | the polygons of the outline, filled by the nonzero rule
    poPolygons :: ![[RPoint]],
    -- | the image: its length along the lines and across them
    poImage :: !(Rational, Rational),
    -- | the caption: from where to where across the lines, along the lines as the image
    poCaption :: !(Maybe (Rational, Rational))
  }
  deriving stock (Eq, Show)

{- | An outline placed on its figure, in horizontal or vertical writing,
on its side: each point of the path as stored is taken by @toImage@ to the
coordinates of the image (the origin at the top left, y down), whose size
is @(w, h)@, and the image is scaled in each direction to the length
@along@ along the lines and @across@ across them it is placed at.
@toImage@ divides by 'Golem.Project.PathData.outlineScale', and for an
SVG maps the viewBox into the viewport too.
-}
placeOutline :: Bool -> Wrap -> ((Rational, Rational) -> (Rational, Rational)) -> (Rational, Rational) -> (Sp, Sp) -> Path -> [[RPoint]]
placeOutline vertical side toImage (w, h) (Sp along, Sp across) = flattenPathWith toArea
  where
    alongR = fromInteger along
    acrossR = fromInteger across
    -- the image across x and y as it is placed: in vertical writing x goes across the lines
    (placedX, placedY) = if vertical then (acrossR, alongR) else (alongR, acrossR)
    toArea (Sp x, Sp y) =
      let (ix, iy) = toImage (fromInteger x, fromInteger y)
          px = ix * placedX / w
          py = iy * placedY / h
          fromSide a = if side == WrapStart then a else alongR - a
       in if vertical then (fromSide py, acrossR - px) else (fromSide px, py)

{- | The exclusion area of a figure with an outline (root ADR 0464): as
'exclusion' for its extent and its widest line, but its edge in a band is
the furthest the outline (clipped to the image) and the caption reach
along the lines within it.
-}
outlinedExclusion :: Wrap -> Sp -> Sp -> Sp -> Sp -> PlacedOutline -> Exclusion
outlinedExclusion side pitch gap figWidth figDepth placed =
  (exclusion side pitch gap figWidth figDepth) {exEdge = edge}
  where
    (imageAlong, imageAcross) = poImage placed
    -- the edges indexed once for every band
    edges = indexPolygons (poPolygons placed)
    edge b0 b1 =
      let image = reachInIndex NonZero edges (0, imageAlong) (max 0 b0, min imageAcross b1)
          caption = [imageAlong | Just (c0, c1) <- [poCaption placed], max b0 c0 <= min b1 c1]
       in case maybe caption (: caption) image of
            [] -> Nothing
            es -> Just (maximum es)

{- | What a line loses on the side of the area (root ADR 0464), its band
from @start@ for @face@ across the lines, from the top of the area: the
edge within the band widened by the gap on each side, rounded up to sp,
and the gap; 0 where the widened band does not meet the area.
-}
lineTake :: Exclusion -> Sp -> Sp -> Sp
lineTake ex start face =
  let g = exGap ex
   in maybe 0 (\e -> Sp (ceiling e) + g) (exEdge ex (fromInteger (unSp (start - g))) (fromInteger (unSp (start + face + g))))

{- | L*(i) for a paragraph starting @offset@ grid lines after the top of
the exclusion area.
-}
wrappedLineWidth :: Sp -> Exclusion -> Int -> Int -> Sp
wrappedLineWidth full ex offset i
  | offset + i < exLines ex = full - exWidth ex
  | otherwise = full
