{- | The placement of ruby (golem-layout ADR 0009): the width of a ruby
box and where each base character and each reading character sits in
it. Composition (the box width) and the PDF drawing (the positions)
share these functions, so they always agree.
-}
module Golem.Layout.Ruby
  ( RubyAlign (..),
    RubyStyle (..),
    defaultRubyStyle,
    RubyKind (..),
    RubyPlacement (..),
    placeRuby,
  )
where

import Data.Ratio ((%))

type Sp = Integer

-- | How characters are spread over a longer width (JLReq 1:2:1, 0:1:0, centred, at the start).
data RubyAlign = Align121 | Align010 | AlignCenter | AlignStart
  deriving stock (Eq, Show)

data RubyStyle = RubyStyle
  { -- | a mono ruby shorter than its base
    rsMonoAlign :: !RubyAlign,
    -- | a group ruby shorter than its base
    rsGroupAlign :: !RubyAlign,
    -- | the base under a reading longer than it
    rsBaseSpacing :: !RubyAlign,
    -- | the most a reading may overhang a neighbour, on one side
    rsOverhang :: !Sp,
    -- | overhang onto kana (False: never overhang)
    rsOverhangOntoKana :: !Bool
  }
  deriving stock (Eq, Show)

-- | The defaults, from the size of the paragraph: JLReq's usual setting, half an em of overhang.
defaultRubyStyle :: Sp -> RubyStyle
defaultRubyStyle fs = RubyStyle AlignCenter Align121 Align121 (fs `div` 2) True

-- | Mono ruby (one base character per reading) or group ruby (a reading over several).
data RubyKind = MonoRuby | GroupRuby
  deriving stock (Eq, Show)

data RubyPlacement = RubyPlacement
  { -- | the width of the box
    rpWidth :: !Sp,
    -- | how far the reading overhangs on each side (the same on both)
    rpOverhang :: !Sp,
    -- | each base character, from the start of the box
    rpBase :: ![Sp],
    -- | each reading character; negative when it overhangs at the start
    rpReading :: ![Sp]
  }
  deriving stock (Eq, Show)

{- | Places a ruby from the advances of its base characters, the advances
of its reading characters and how far it may overhang at the start and
at the end. A reading no longer than its base is spread over the base;
a longer one overhangs both sides equally (centred) and the rest spaces
the base.
-}
placeRuby :: RubyStyle -> RubyKind -> [Sp] -> [Sp] -> (Sp, Sp) -> RubyPlacement
placeRuby style kind base reading (a, b)
  | r <= w0 =
      let align = case kind of
            MonoRuby -> rsMonoAlign style
            GroupRuby -> rsGroupAlign style
       in RubyPlacement w0 0 (distribute AlignStart w0 base) (distribute align w0 reading)
  | otherwise =
      let o = max 0 (minimum [a, b, (r - w0) `div` 2])
          w = max w0 (r - 2 * o)
          start = negate ((r - w) `div` 2)
       in RubyPlacement w o (distribute (rsBaseSpacing style) w base) (map (+ start) (distribute AlignStart r reading))
  where
    w0 = sum base
    r = sum reading

{- | The start of each of @n@ characters spread over a width: the spare
space split by the alignment. Positions are exact rationals rounded
down once per character, so rounding never accumulates.
-}
distribute :: RubyAlign -> Sp -> [Sp] -> [Sp]
distribute align width advances =
  let n = toInteger (length advances)
      e = width - sum advances
      (first, gap) = case align of
        Align121 | n >= 1 -> (e % (2 * n), e % n)
        Align010 | n >= 2 -> (0, e % (n - 1))
        AlignStart -> (0, 0)
        _ -> (e % 2, 0)
      starts = scanl (\pos adv -> pos + toRational adv + gap) first advances
   in map floor (take (length advances) starts)
