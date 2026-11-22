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
    placeRubyMinimum,
    placeRubyAtEdges,
    rubyStyleWith,
  )
where

import Data.Ratio ((%))
import Golem.Doc.IR (RubyOptions (..))
import Golem.Length (Sp (..))

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
defaultRubyStyle fs = RubyStyle AlignCenter Align121 Align121 (Sp (unSp fs `div` 2)) True

-- | Mono ruby (one base character per reading) or group ruby (a reading over several).
data RubyKind = MonoRuby | GroupRuby
  deriving stock (Eq, Show)

data RubyPlacement = RubyPlacement
  { -- | the width of the box
    rpWidth :: !Sp,
    -- | the larger of the start and end overhangs
    rpOverhang :: !Sp,
    -- | each base character, from the start of the box
    rpBase :: ![Sp],
    -- | each reading character; negative when it overhangs at the start
    rpReading :: ![Sp],
    rpOverhangStart :: !Sp,
    rpOverhangEnd :: !Sp
  }
  deriving stock (Eq, Show)

{- | Places a ruby from the advances of its base characters, the advances
of its reading characters and how far it may overhang at the start and
at the end. A reading no longer than its base is spread over the base;
a longer one uses the allowed sides, balanced when both permit it,
and the rest spaces the base (root ADR 0379).
-}
placeRuby :: RubyStyle -> RubyKind -> [Sp] -> [Sp] -> (Sp, Sp) -> RubyPlacement
placeRuby = placeRubyMinimum 0

placeRubyMinimum :: Sp -> RubyStyle -> RubyKind -> [Sp] -> [Sp] -> (Sp, Sp) -> RubyPlacement
placeRubyMinimum minimumWidth style kind base reading (a, b)
  | r <= w0 =
      let align = case kind of
            MonoRuby -> rsMonoAlign style
            GroupRuby -> rsGroupAlign style
       in RubyPlacement w0 0 (distribute (if w0 > sum base then rsBaseSpacing style else AlignStart) w0 base) (distribute align w0 reading) 0 0
  | otherwise =
      let allowedStart = max 0 (min (rsOverhang style) a)
          allowedEnd = max 0 (min (rsOverhang style) b)
          total = min (r - w0) (allowedStart + allowedEnd)
          start = min allowedStart (max (Sp (unSp total `div` 2)) (total - allowedEnd))
          end = total - start
          w = r - total
       in RubyPlacement w (max start end) (distribute (rsBaseSpacing style) w base) (map (subtract start) (distribute AlignStart r reading)) start end
  where
    w0 = max minimumWidth (sum base)
    r = sum reading

{- | At a physical line edge the reading stays inside and the base meets
the edge. The caller supplies the width recovered from the edge allowance.
-}
placeRubyAtEdges :: (Bool, Bool) -> Sp -> RubyStyle -> RubyKind -> [Sp] -> [Sp] -> (Sp, Sp) -> RubyPlacement
placeRubyAtEdges (atStart, atEnd) width style kind base reading (a, b) =
  let rp = placeRubyMinimum width style kind base reading (if atStart then 0 else a, if atEnd then 0 else b)
      positions = rpBase rp
      shift
        | atStart = case positions of firstPosition : _ -> negate firstPosition; [] -> 0
        | atEnd = case reverse (zip positions base) of (position, advance) : _ -> rpWidth rp - position - advance; [] -> 0
        | otherwise = 0
      aligned
        | atStart && atEnd && length base > 1 = distribute Align010 (rpWidth rp) base
        | otherwise = map (+ shift) positions
   in rp {rpBase = aligned}

-- | An inline alignment overrides the corresponding style choices together.
rubyStyleWith :: RubyOptions -> RubyStyle -> RubyStyle
rubyStyleWith options style = case roAlign options >>= (\n -> lookup n [("start", AlignStart), ("center", AlignCenter), ("1-2-1", Align121), ("0-1-0", Align010)]) of
  Nothing -> style
  Just align -> style {rsMonoAlign = align, rsGroupAlign = align, rsBaseSpacing = align}

{- | The start of each of @n@ characters spread over a width: the spare
space split by the alignment. Positions are exact rationals rounded
down once per character, so rounding never accumulates.
-}
distribute :: RubyAlign -> Sp -> [Sp] -> [Sp]
distribute align (Sp width) spAdvances =
  let advances = map unSp spAdvances
      n = toInteger (length advances)
      e = width - sum advances
      (first, gap) = case align of
        Align121 | n >= 1 -> (e % (2 * n), e % n)
        Align010 | n >= 2 -> (0, e % (n - 1))
        AlignStart -> (0, 0)
        _ -> (e % 2, 0)
      starts = scanl (\pos adv -> pos + toRational adv + gap) first advances
   in map (Sp . floor) (take (length advances) starts)
