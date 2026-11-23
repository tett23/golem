{- | Physical line boxes and decoration extents (root ADR 0397).
All arguments and results are integer sp; no grid rounding is applied.
-}
module Golem.Layout.FreeGeometry
  ( faceOffset,
    centerDistance,
    columnExtent,
    rowExtent,
    intersects,
    boxExtras,
    ruleBeforeExtra,
    ruleAfterExtra,
    ruleBetweenExtra,
    ruleBeforeGap,
    ruleAfterGap,
    rulesSharedGap,
    ruleBeforeEdge,
    ruleAfterEdge,
  )
where

import Golem.Layout.RuleArea (RuleSide (..))
import Golem.Length (Sp (..))

half :: Sp -> Sp
half (Sp n) = Sp (n `div` 2)

-- | The virtual face starts here relative to the beginning of its line box.
faceOffset :: Sp -> Sp -> Sp
faceOffset pitch face = half pitch - half face

centerDistance :: Sp -> Sp -> Sp -> Sp
centerDistance before after gap = before - half before + half after + gap

columnExtent :: Int -> Sp -> Sp -> Sp
columnExtent lines' pitch face = fromIntegral (lines' - 1) * pitch + face

-- | The union of the line box and its virtual face, for wrapped figures.
rowExtent :: Sp -> Sp -> Sp -> (Sp, Sp)
rowExtent start pitch face =
  let a = faceOffset pitch face
   in (start + min 0 a, start + max pitch (a + face))

intersects :: (Sp, Sp) -> (Sp, Sp) -> Bool
intersects (a, b) (c, d) = max a c < min b d

{- | Extra occupied lengths around a box fragment; leading already present
inside the first and last rows contributes to the requested padding.
-}
boxExtras :: Sp -> Sp -> Sp -> Sp -> Sp -> (Sp, Sp)
boxExtras firstPitch firstFace lastPitch lastFace padding =
  ( max 0 (padding - faceOffset firstPitch firstFace),
    max 0 (padding - (lastPitch - lastFace - faceOffset lastPitch lastFace))
  )

ruleBeforeExtra :: Sp -> Sp -> Sp -> Sp -> Sp -> Sp
ruleBeforeExtra pitch face inner weight overhang = max 0 (inner + weight + overhang - faceOffset pitch face)

ruleAfterExtra :: Sp -> Sp -> Sp -> Sp -> Sp
ruleAfterExtra pitch face inner weight = max 0 (inner + weight - (pitch - face - faceOffset pitch face))

ruleBetweenExtra :: Sp -> Sp -> Sp -> Sp -> Sp -> Sp
ruleBetweenExtra faceGap inner weight outer overhang = max 0 (inner + weight + outer + overhang - faceGap)

{- | One rule in a physical face-to-face gap. Positions are measured from
the end of the preceding face; an odd remainder goes to the outer side.
-}
ruleBeforeGap :: Sp -> RuleSide -> Sp -> (Sp, Sp)
ruleBeforeGap gap side overhang =
  let extra = max 0 (rsdInner side + rsdWeight side + rsdOuter side + overhang - gap)
      distance = gap + extra
      rest = distance - overhang - rsdWeight side
      position = if rsdSpaced side then distance - overhang - rsdInner side - rsdWeight side else rest - half rest
   in (extra, position)

ruleAfterGap :: Sp -> RuleSide -> Sp -> (Sp, Sp)
ruleAfterGap gap side overhang =
  let extra = max 0 (rsdInner side + rsdWeight side + rsdOuter side + overhang - gap)
      rest = gap + extra - overhang - rsdWeight side
   in (extra, if rsdSpaced side then rsdInner side else half rest)

-- | Two rules share one face-to-face gap; indivisible sp goes between them.
rulesSharedGap :: Sp -> RuleSide -> RuleSide -> Sp -> (Sp, Sp, Sp)
rulesSharedGap gap before afterSide overhang =
  let extra = max 0 (rsdInner before + rsdWeight before + max (rsdOuter before) (rsdOuter afterSide) + rsdWeight afterSide + rsdInner afterSide + overhang - gap)
      distance = gap + extra
      rest = distance - overhang - rsdWeight before - rsdWeight afterSide
      third = Sp (unSp rest `div` 3)
   in if rsdSpaced before || rsdSpaced afterSide
        then (extra, rsdInner before, distance - overhang - rsdInner afterSide - rsdWeight afterSide)
        else (extra, third, distance - overhang - rsdWeight afterSide - third)

{- | A rule at a genuine type-area edge. The caller removes rsdOutside at
an interior column start, or at an end adjoining footnotes. Positions
are relative to the original line-box start, after adding any extra.
-}
ruleBeforeEdge :: Sp -> Sp -> RuleSide -> Sp -> (Sp, Sp)
ruleBeforeEdge pitch face side overhang =
  let leading = faceOffset pitch face
      exact = leading - overhang - rsdInner side - rsdWeight side
      outside = if rsdSpaced side then exact else min (negate (rsdWeight side)) exact
      extra = ruleBeforeExtra pitch face (rsdInner side) (rsdWeight side) overhang
      rest = leading + extra - overhang - rsdWeight side
      inside = if rsdSpaced side then exact + extra else rest - half rest
   in case rsdOutside side of
        Just available | outside + rsdWeight side <= 0 && negate outside <= available -> (0, outside)
        _ -> (extra, inside)

ruleAfterEdge :: Sp -> Sp -> RuleSide -> (Sp, Sp)
ruleAfterEdge pitch face side =
  let faceEnd = faceOffset pitch face + face
      exact = faceEnd + rsdInner side
      outside = if rsdSpaced side then exact else max pitch exact
      extra = ruleAfterExtra pitch face (rsdInner side) (rsdWeight side)
      rest = pitch + extra - faceEnd - rsdWeight side
      inside = if rsdSpaced side then exact else faceEnd + half rest
   in case rsdOutside side of
        Just available | outside >= pitch && outside + rsdWeight side - pitch <= available -> (0, outside)
        _ -> (extra, inside)
