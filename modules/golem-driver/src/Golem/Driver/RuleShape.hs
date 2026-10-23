{- | The shapes of the line styles of a rule (golem-driver ADR 0028): a
rule of length L and weight w is drawn inside its band as filled
rectangles, discs and closed curves, never stroked, so that golem
preflight sees the weights of filled shapes only. Every length is an
integer of sp, each division done once (docs/adr/0002).
-}
module Golem.Driver.RuleShape
  ( RuleShape (..),
    ruleShapes,
    ruleThinnest,
    ruleMarks,
  )
where

import Golem.LayoutSpec (Rect (..))
import Golem.Pdf qualified as P
import Golem.Project.Style (RuleStyle (..), Sp)

-- | A filled shape on the page.
data RuleShape
  = ShapeRect !Rect
  | -- | centre x, centre y, radius
    ShapeDisc !Sp !Sp !Sp
  | -- | the start and the cubic curves of a closed path: two control points and the end each
    ShapeCurve !(Sp, Sp) ![((Sp, Sp), (Sp, Sp), (Sp, Sp))]
  deriving stock (Eq, Show)

{- | A shape in the coordinates of the band: along the rule from its
start, and across it from its before edge (the top, the right in
vertical text).
-}
data Local
  = -- | from, length along; from, thickness across
    LRect !Sp !Sp !Sp !Sp
  | -- | centre along, centre across, radius
    LDisc !Sp !Sp !Sp
  | LCurve !(Sp, Sp) ![((Sp, Sp), (Sp, Sp), (Sp, Sp))]

{- | The shapes of a rule of a style in its band, in vertical text when
the first argument is true: the band then runs down from its top and its
before edge is the right.
-}
ruleShapes :: Bool -> Rect -> RuleStyle -> [RuleShape]
ruleShapes vertical band style = map place (localShapes len w style)
  where
    (len, w) = if vertical then (rectH band, rectW band) else (rectW band, rectH band)
    point (s, t)
      | vertical = (rectX band + w - t, rectY band + len - s)
      | otherwise = (rectX band + s, rectY band + w - t)
    place = \case
      LRect s ls t lt
        | vertical -> ShapeRect (Rect (rectX band + w - t - lt) (rectY band + len - s - ls) lt ls)
        | otherwise -> ShapeRect (Rect (rectX band + s) (rectY band + w - t - lt) ls lt)
      LDisc s t r -> let (x, y) = point (s, t) in ShapeDisc x y r
      LCurve start cs -> ShapeCurve (point start) [(point a, point b, point c) | (a, b, c) <- cs]

-- | The shapes of a style for a band of length len and weight w.
localShapes :: Sp -> Sp -> RuleStyle -> [Local]
localShapes len w = \case
  RuleSolid -> [LRect 0 len 0 w]
  RuleMulti ratios ->
    let u = toInteger (sum ratios)
        edges = [(c * w) `div` u | c <- scanl (+) 0 (map toInteger ratios)]
     in [LRect 0 len a (b - a) | (i, a, b) <- zip3 [0 :: Int ..] edges (drop 1 edges), even i]
  RuleDashed d g ->
    let n = max 1 (roundDiv (len + g) (d + g))
        total = n * d + (n - 1) * g
     in if n == 1
          then [LRect 0 len 0 w]
          else
            [ LRect a (b - a) 0 w
            | i <- [0 .. n - 1],
              let a = (i * (d + g) * len) `div` total
                  b = ((i * (d + g) + d) * len) `div` total
            ]
  RuleDotted g -> [LDisc c (w `div` 2) (w `div` 2) | c <- dots g]
  RuleJapaneseDots g -> [LRect (c - w `div` 2) w 0 w | c <- dots g]
  RuleWavy ->
    let t = w `div` 4
        a = (w - t) `div` 2
        m = max 1 (roundDiv len (2 * w))
        bounds = [(j * len) `div` m | j <- [0 .. m]]
        centre = t `div` 2 + a
        lift = 4 * a `div` 3
        -- the half periods of the centre line shifted across by off; crests toward the before edge
        edge off =
          [ ((s0 + h `div` 3, c - sign * lift), (s0 + (2 * h) `div` 3, c - sign * lift), (s1, c))
          | (j, s0, s1) <- zip3 [0 :: Integer ..] bounds (drop 1 bounds),
            let h = s1 - s0
                sign = if even j then 1 else -1
                c = centre + off
          ]
        upper = edge (negate (t `div` 2))
        lowerOff = t - t `div` 2
        lower = edge lowerOff
        reversed = reverseCurves (0, centre + lowerOff) lower
        line p q = (p, q, q)
     in [LCurve (0, centre - t `div` 2) (upper <> [line (len, centre + lowerOff) (len, centre + lowerOff)] <> reversed)]
  where
    -- the centres of the dots: the first and the last inside the ends
    dots g =
      let n = max 1 (roundDiv (len - w) (w + g) + 1)
       in if n == 1
            then [len `div` 2]
            else [w `div` 2 + (i * (len - w)) `div` (n - 1) | i <- [0 .. n - 1]]

-- | The curves of a path from start, run backwards from its end.
reverseCurves :: (Sp, Sp) -> [((Sp, Sp), (Sp, Sp), (Sp, Sp))] -> [((Sp, Sp), (Sp, Sp), (Sp, Sp))]
reverseCurves start cs =
  let starts = start : [e | (_, _, e) <- cs]
   in reverse [(b, a, s) | (s, (a, b, _)) <- zip starts cs]

-- | a / b rounded half up, for positive b.
roundDiv :: Integer -> Integer -> Integer
roundDiv a b = (2 * a + b) `div` (2 * b)

{- | The weight of the thinnest part of a rule of weight w, which golem
preflight checks (G09018).
-}
ruleThinnest :: Sp -> RuleStyle -> Sp
ruleThinnest w = \case
  RuleMulti ratios ->
    let u = toInteger (sum ratios)
        edges = [(c * w) `div` u | c <- scanl (+) 0 (map toInteger ratios)]
     in minimum (w : [b - a | (i, a, b) <- zip3 [0 :: Int ..] edges (drop 1 edges), even i])
  RuleWavy -> w `div` 4
  _ -> w

-- | The marks of the shapes, filled with a swatch inside q and Q when there is one.
ruleMarks :: Maybe P.Swatch -> [RuleShape] -> [P.Mark]
ruleMarks sw shapes = maybe id (\c ms -> [P.Saved (P.SetColor c : ms)]) sw (map mark shapes)
  where
    mark = \case
      ShapeRect r -> P.Rule r
      ShapeDisc x y r -> P.Disc x y r
      ShapeCurve start cs -> P.CurveFill start cs
