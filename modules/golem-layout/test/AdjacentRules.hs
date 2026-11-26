{- | The boundary inputs of root ADR 0449: a ruled block (a paragraph or a
heading) with a rule after, directly followed by a ruled block with a rule
before, in the grid placement and in the free placement. The grid has a
pitch of 20 and an em box of 10; the free placement has a line pitch of
20 sp and a face of 10 sp, whose face starts 5 sp into its line box.
-}
module AdjacentRules
  ( Adjacent (..),
    adjacentCases,
    adjacentGrid,
    adjacentFree,
    adjacentFreeSettings,
    gridShared,
    freeShared,
    rulesOverlap,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical (PhysicalSettings (..))
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Length (Sp (..))

{- | One input: the kinds of the two blocks (0 and 1 a paragraph of one or
two lines, 2 and 3 a heading of one or two line pitches), the side of the
rule after of the first and of the rule before of the second, the
overhang of the second block's first line, keep-in-column = false,
`space-between` between the blocks, the capacity of the column in line
pitches, and a paragraph before the first block.
-}
data Adjacent = Adjacent
  { adFirst :: !Int,
    adSecond :: !Int,
    adSideA :: !RuleSide,
    adSideB :: !RuleSide,
    adOverhang :: !Sp,
    adOutside :: !Bool,
    adSpace :: !Bool,
    adCapacity :: !Int,
    adLead :: !Bool
  }
  deriving stock (Show)

-- | Thin and thick rules without spaces, and spaced rules with and without an outer space.
adjacentSides :: [RuleSide]
adjacentSides = [RuleSide 0 0 1 False Nothing, RuleSide 0 0 12 False Nothing, RuleSide 4 6 2 True Nothing, RuleSide 2 0 12 True Nothing]

adjacentCases :: [Adjacent]
adjacentCases =
  [ Adjacent a b sa sb r o s c l
  | a <- [0 .. 3],
    b <- [0, 2, 3],
    sa <- adjacentSides,
    sb <- adjacentSides,
    r <- [0, 3],
    o <- [False, True],
    s <- [False, True],
    c <- [2, 3, 4, 6],
    l <- [False, True]
  ]

idA, idB :: Adjacent -> Int
idA ad = if adOutside ad then 200 else 100
idB ad = idA ad + 1

sideOf :: Adjacent -> RuleSide -> RuleSide
sideOf ad side = side {rsdOutside = if adOutside ad then Just 20 else Nothing}

-- | The last line of the first block.
lastOfFirst :: Adjacent -> Int
lastOfFirst ad = if odd (adFirst ad) then 11 else 10

bodyOf :: position -> Int -> Int -> Sp -> RuledBodyAt position
bodyOf pitch kind first r =
  let firstLine = LineBox first [] [] [] r
      second = LineBox (first + 1) [] [] [] 0
   in case kind of
        0 -> RuledLines defaultKeep [firstLine]
        1 -> RuledLines defaultKeep [firstLine, second]
        2 -> RuledHeading False pitch [firstLine]
        _ -> RuledHeading False pitch [firstLine, second]

adjacentFlows :: (Int -> position) -> position -> Adjacent -> [FlowAt position]
adjacentFlows pitches space ad =
  [FParagraph defaultKeep [LineBox 0 [] [] [] 0] | adLead ad]
    <> [FRuled (idA ad) Nothing (Just (sideOf ad (adSideA ad))) False (RuleGrid 20 10) (adOverhang ad) (bodyOf (pitches (1 + adFirst ad `mod` 2)) (adFirst ad) 10 0)]
    <> [FSpace space | adSpace ad]
    <> [FRuled (idB ad) (Just (sideOf ad (adSideB ad))) Nothing (not (adSpace ad)) (RuleGrid 20 10) 0 (bodyOf (pitches (1 + adSecond ad `mod` 2)) (adSecond ad) 20 (adOverhang ad))]
    <> [FParagraph defaultKeep [LineBox 40 [] [] [] 0]]

adjacentGrid :: Adjacent -> [Flow]
adjacentGrid = adjacentFlows id 1

adjacentFree :: Adjacent -> [FlowAt Sp]
adjacentFree = adjacentFlows (\n -> 20 * fromIntegral n) 20

adjacentFreeSettings :: Adjacent -> PhysicalSettings
adjacentFreeSettings ad =
  let c = 20 * fromIntegral (adCapacity ad)
   in PhysicalSettings 20 10 c c 0 (ColumnSet 1 0 0 0) Map.empty Map.empty Map.empty Map.empty Map.empty Nothing Set.empty noAvoid

-- | The length the two rules need between the faces: iA + wA + max(oA, oB) + wB + iB + rB.
needOf :: Adjacent -> Sp
needOf ad =
  let a = adSideA ad
      b = adSideB ad
   in rsdInner a + rsdWeight a + max (rsdOuter a) (rsdOuter b) + rsdWeight b + rsdInner b + adOverhang ad

-- | The places of the two rules from the end of the first face, for a distance d between the faces.
sharedPlaces :: Adjacent -> Sp -> (Sp, Sp)
sharedPlaces ad d =
  let a = adSideA ad
      b = adSideB ad
      r = adOverhang ad
      rest = d - r - rsdWeight a - rsdWeight b
      third = Sp (unSp rest `div` 3)
   in if rsdSpaced a || rsdSpaced b
        then (rsdInner a, d - r - rsdInner b - rsdWeight b)
        else (third, d - r - rsdWeight b - third)

-- | The rules of the two blocks in the column that holds the first block's last line and the second block's first.
bothIn :: Adjacent -> PageOutAt position -> Maybe (Sp, Sp)
bothIn ad p = case ([prAt r | r <- poRules p, prId r == idA ad, not (prBefore r)], [prAt r | r <- poRules p, prId r == idB ad, prBefore r]) of
  ([ruleA], [ruleB]) -> Just (ruleA, ruleB)
  _ -> Nothing

{- | Whether the grid placement put the two rules in one area: Nothing when
the second block does not go on in the column of the first, or a rule is
not there (golem-driver ADR 0035). The area takes
k = max(0, ceil((need - (p - h)) / p)) grid lines.
-}
gridShared :: Adjacent -> [PageOut] -> Maybe Bool
gridShared ad pages = case [(la, sb, rules) | p <- pages, la <- lastLines p, sb <- firstLines p, Just rules <- [bothIn ad p]] of
  (la, sb, (ruleA, ruleB)) : _ ->
    let k = max 0 (negate (negate (unSp (needOf ad) - 10) `div` 20))
        d = fromIntegral k * 20 + 10
        (placeA, placeB) = gridPlaces d
        base = fromIntegral la * 20 + 10
     in Just (sb == la + 1 + fromIntegral k && ruleA == base + placeA && ruleB == base + placeB)
  [] -> Nothing
  where
    lastLines p = [at | (at, SLine n) <- poSlots p, n == lastOfFirst ad] <> [at + n - 1 | (at, SHeading 10 n) <- poSlots p]
    firstLines p = [at | (at, SLine 20) <- poSlots p] <> [at | (at, SHeading 20 _) <- poSlots p]
    -- the grid placement puts the indivisible sp between the rules: the second rule after the first, its weight and another third
    gridPlaces d =
      let a = adSideA ad
          b = adSideB ad
          rest = d - adOverhang ad - rsdWeight a - rsdWeight b
          third = Sp (unSp rest `div` 3)
       in if rsdSpaced a || rsdSpaced b
            then sharedPlaces ad d
            else (third, third + rsdWeight a + third + Sp (unSp rest `mod` 3))

{- | Whether the free placement put the two rules in one area: Nothing as in
'gridShared'. The faces are 10 sp apart without rules; the area adds
max(0, need - 10) sp.
-}
freeShared :: Adjacent -> [PageOutAt Sp] -> Maybe Bool
freeShared ad pages = case [(faceEnd, faceStart, rules) | p <- pages, faceEnd <- faceEnds p, faceStart <- faceStarts p, Just rules <- [bothIn ad p]] of
  (faceEnd, faceStart, (ruleA, ruleB)) : _ ->
    let d = 10 + max 0 (needOf ad - 10)
        (placeA, placeB) = sharedPlaces ad d
     in Just (faceStart - faceEnd == d && ruleA == faceEnd + placeA && ruleB == faceEnd + placeB)
  [] -> Nothing
  where
    faceEnds p = [at + 15 | (at, SLine n) <- poSlots p, n == lastOfFirst ad] <> [at + 20 * fromIntegral n - 5 | (at, SHeading 10 n) <- poSlots p]
    faceStarts p = [at + 5 | (at, SLine 20) <- poSlots p] <> [at + 5 | (at, SHeading 20 _) <- poSlots p]

-- | The rules of a column that overlap another rule of it in the direction of the line pitch.
rulesOverlap :: Adjacent -> PageOutAt position -> [(PlacedRule, PlacedRule)]
rulesOverlap ad p =
  let weight r = rsdWeight (if prId r == idA ad then adSideA ad else adSideB ad)
      rules = poRules p
   in [(x, y) | (i, x) <- zip [0 :: Int ..] rules, (j, y) <- zip [0 ..] rules, i < j, prAt x < prAt y + weight y, prAt y < prAt x + weight x]
