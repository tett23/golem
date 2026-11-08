{- | How a tate-chu-yoko in vertical text fits its box (golem-driver ADR
0045): its characters set horizontally side by side, as wide as the
sum of their advances, or squeezed horizontally to the size of its box
when they are wider than it. Lengths in sp.
-}
module Golem.Typeset.Tcy
  ( TcyFit (..),
    tcyFit,
    squeezed,
  )
where

-- | The fit of a tate-chu-yoko: its horizontal scale in permille and its width as drawn.
data TcyFit = TcyFit
  { -- | 1000 when the characters fit the box, ⌊1000 × s / W⌋ when they do not
    tfScale :: !Int,
    -- | the sum of the advances with the scale, W' ≤ s
    tfWidth :: !Integer,
    -- | where each glyph starts from the left of the first, with the scale
    tfOffsets :: ![Integer]
  }
  deriving stock (Eq, Show)

{- | The fit of the advances of the glyphs of a tate-chu-yoko in a box of
size s: unscaled when their sum W is at most s; otherwise scaled by
⌊1000 × s / W⌋ permille, so that W' is at most s.
-}
tcyFit :: Integer -> [Integer] -> TcyFit
tcyFit s advances =
  let w = sum advances
      scale
        | w <= s = 1000
        | otherwise = fromInteger ((1000 * s) `div` w)
   in TcyFit scale (squeezed scale w) (map (squeezed scale) (init (scanl (+) 0 advances)))

-- | A length along the line with a horizontal scale in permille, rounded towards negative infinity.
squeezed :: Int -> Integer -> Integer
squeezed scale x = (x * toInteger scale) `div` 1000
