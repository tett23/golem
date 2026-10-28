{- | The areas of the rules of paragraphs and headings (golem-driver ADR
0027): how many grid lines a rule takes and where it is drawn. The
grid is not moved: a rule area is a whole number of grid lines, the
inner space is kept exactly and what rounding up adds goes to the outer
space. The overhang r of the ruby and kenten of the line after an area
is counted as part of that line. Lengths are 'Sp'; each division once
(docs/adr/0002).
-}
module Golem.Layout.RuleArea
  ( RuleGrid (..),
    RuleSide (..),
    ruleBefore,
    ruleAfter,
    ruleBeforeAtStart,
    ruleAfterAtEnd,
    rulesJoined,
  )
where

import Golem.Length (Sp (..))

-- | The line pitch p and the height h of the em box of a grid line, in sp.
data RuleGrid = RuleGrid {rgPitch :: !Sp, rgFace :: !Sp}
  deriving stock (Eq, Show)

-- | The measures of one rule, in sp.
data RuleSide = RuleSide
  { -- | the space between the rule and its paragraph
    rsdInner :: !Sp,
    -- | the space between the rule and what is before or after it
    rsdOuter :: !Sp,
    rsdWeight :: !Sp,
    -- | whether either space was written; without them the rule is centred
    rsdSpaced :: !Bool,
    -- | keep-in-column = false: the room outside the column on the side of the rule
    rsdOutside :: !(Maybe Sp)
  }
  deriving stock (Eq, Show)

-- | The fewest whole lines that hold n sp, not fewer than 0.
linesFor :: Sp -> Sp -> Int
linesFor (Sp p) (Sp n) = fromInteger (max 0 (negate (negate n `div` p)))

-- | Sp divided by a whole number, rounded toward negative infinity.
divSp :: Sp -> Integer -> Sp
divSp (Sp x) n = Sp (x `div` n)

{- | The rule before a paragraph inside a column, r the overhang of its
first line: the grid lines k of the area and the place of the rule (the
start of its weight) from the end of the em box of the line before.
The distance between the two em boxes, k × p + (p − h), holds the outer
space, the weight, the inner space and r.
-}
ruleBefore :: RuleGrid -> RuleSide -> Sp -> (Int, Sp)
ruleBefore (RuleGrid p h) s r =
  let k = linesFor p (rsdInner s + rsdWeight s + rsdOuter s + r - (p - h))
      d = fromIntegral k * p + (p - h)
   in (k, if rsdSpaced s then d - r - rsdInner s - rsdWeight s else (d - r - rsdWeight s) `divSp` 2)

{- | The rule after a paragraph inside a column, r the overhang of the
line after it: the grid lines of the area and the place of the rule from
the end of the em box of the last line of the paragraph.
-}
ruleAfter :: RuleGrid -> RuleSide -> Sp -> (Int, Sp)
ruleAfter (RuleGrid p h) s r =
  let k = linesFor p (rsdInner s + rsdWeight s + rsdOuter s + r - (p - h))
      d = fromIntegral k * p + (p - h)
   in (k, if rsdSpaced s then rsdInner s else (d - r - rsdWeight s) `divSp` 2)

{- | The rule before a paragraph at the start of a column, r the overhang
of its first line: at least one line, the outer space not counted, the
place from the edge of the column (the start of the em box of its first
grid line). Out of the column when it may go out and the room holds the
inner space, the weight and r: no line, a negative place.
-}
ruleBeforeAtStart :: RuleGrid -> RuleSide -> Sp -> (Int, Sp)
ruleBeforeAtStart (RuleGrid p _) s r = case rsdOutside s of
  Just room | rsdInner s + rsdWeight s + r <= room -> (0, negate (r + rsdInner s + rsdWeight s))
  _ ->
    let k = max 1 (linesFor p (rsdInner s + rsdWeight s + r))
        d = fromIntegral k * p
     in (k, if rsdSpaced s then d - r - rsdInner s - rsdWeight s else (d - r - rsdWeight s) `divSp` 2)

{- | The rule after a paragraph at the end of a column: at least one line,
the outer space not counted, the place from the end of the em box of the
last line of the paragraph. Out of the column when it may go out and the
room holds the inner space and the weight: no line.
-}
ruleAfterAtEnd :: RuleGrid -> RuleSide -> (Int, Sp)
ruleAfterAtEnd (RuleGrid p _) s = case rsdOutside s of
  Just room | rsdInner s + rsdWeight s <= room -> (0, rsdInner s)
  _ ->
    let k = max 1 (linesFor p (rsdInner s + rsdWeight s))
        d = fromIntegral k * p
     in (k, if rsdSpaced s then rsdInner s else (d - rsdWeight s) `divSp` 2)

{- | The rule a after a paragraph and the rule b before the next one in
one area, rb the overhang of the first line of the next paragraph: the
grid lines and the places of a and b from the end of the em box of the
last line of the first paragraph. The larger outer space is the least
space between the two rules; without any space the distance less rb is
cut in three, the remainder in the middle.
-}
rulesJoined :: RuleGrid -> RuleSide -> RuleSide -> Sp -> (Int, Sp, Sp)
rulesJoined (RuleGrid p h) a b rb =
  let k = linesFor p (rsdInner a + rsdWeight a + max (rsdOuter a) (rsdOuter b) + rsdWeight b + rsdInner b + rb - (p - h))
      d = fromIntegral k * p + (p - h)
      rest = d - rb - rsdWeight a - rsdWeight b
      third = rest `divSp` 3
   in if rsdSpaced a || rsdSpaced b
        then (k, rsdInner a, d - rb - rsdInner b - rsdWeight b)
        else (k, third, third + rsdWeight a + third + Sp (unSp rest `mod` 3))
