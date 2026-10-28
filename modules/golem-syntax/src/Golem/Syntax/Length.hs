{- | Lengths: the type of sp, the conversions of the units and the text
of a length (docs/adr ADR 0103). The ratios of the units are written in
this module only: 1pt = 65536sp, 1in = 72pt = 25.4mm, 1Q = 1H = 0.25mm.

A written length becomes sp once, from its exact rational, rounded half to
even. A length is shown in mm to two decimals in diagnostics, and in pt
and em to at most four decimals in the output; both round half to even.
-}
module Golem.Syntax.Length
  ( Sp (..),
    Unit (..),
    toSp,
    zwToSp,
    fromSp,
    mmText,
    mmRationalText,
    ptText,
    emText,
  )
where

import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax.Text (showRationalDigits)

-- | Scaled points: 1pt = 65536sp. A newtype, so as not to be taken for another integer.
newtype Sp = Sp {unSp :: Integer}
  deriving newtype (Eq, Ord, Show, Num)

-- | The units of absolute lengths a writer may write.
data Unit = Pt | Mm | In | Q | H
  deriving stock (Eq, Show)

-- | How many sp one of the unit is: an exact rational.
spPer :: Unit -> Rational
spPer = \case
  Pt -> 65536
  In -> 72 * spPer Pt
  Mm -> spPer In / (254 % 10)
  Q -> spPer Mm / 4
  H -> spPer Mm / 4

-- | A written amount (an exact rational) in sp, rounded once, half to even.
toSp :: Unit -> Rational -> Sp
toSp u r = Sp (round (r * spPer u))

-- | An amount in zw at a size of type, in sp, rounded once, half to even.
zwToSp :: Sp -> Rational -> Sp
zwToSp (Sp size) r = Sp (round (r * fromInteger size))

-- | Sp as the exact rational of a unit, unrounded.
fromSp :: Unit -> Sp -> Rational
fromSp u (Sp s) = fromInteger s / spPer u

-- | A length in mm for a diagnostic: two decimals, half to even, @3.00mm@.
mmText :: Sp -> Text
mmText = mmRationalText . fromSp Mm

{- | An exact length in mm, written as 'mmText' writes it: two decimals,
rounded half to even from the absolute value, the trailing zeros kept, a
sign only when the rounded value is not 0, no space before the unit.
-}
mmRationalText :: Rational -> Text
mmRationalText mm =
  let hundredths = round (abs mm * 100) :: Integer
      (i, f) = hundredths `quotRem` 100
      sign = if mm < 0 && hundredths /= 0 then "-" else ""
   in sign <> T.pack (show i) <> "." <> T.justifyRight 2 '0' (T.pack (show f)) <> "mm"

-- | Sp as a number of pt for the output: at most four decimals, half to even.
ptText :: Sp -> Text
ptText = showRationalDigits 4 . fromSp Pt

-- | A ratio (em) as a number for the output: at most four decimals, half to even.
emText :: Rational -> Text
emText = showRationalDigits 4
