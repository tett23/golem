{- | How far ruby and kenten reach out of the face of a line, toward the
line before it (golem-driver ADR 0033): above the face in horizontal
text, right of it in vertical text. The drawing of the PDF places the
readings and the marks with the same functions, so that the overhang the
layout reckons is the one drawn.
-}
module Golem.Driver.Overhang
  ( rubyAcross,
    rubyOverhang,
    kentenAcross,
    kentenOverhang,
    lineOverhang,
    reachesBackground,
  )
where

import Data.Text qualified as T
import Golem.Layout.Japanese (BoxKind (..), boxKind, clusters)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.LayoutSpec (baselineRatio)
import Golem.Length (Sp (..), zwToSp)

{- | The reading of a ruby across the line from its base (golem-layout ADR
0011): its baseline the size of the largest base character above the
base's in horizontal text; its centre line half of that and half of the
reading right of the base's in vertical text.
-}
rubyAcross :: Bool -> Sp -> Sp -> Sp
rubyAcross vertical big rsize
  | vertical = Sp (unSp big `div` 2) + Sp (unSp rsize `div` 2)
  | otherwise = big

{- | How far the reading of a ruby reaches out of the face of a line of the
size @h@: the outer edge of the em box of the reading (its top at 0.88 of
the size, or its right edge) less the edge of the face of the line.
-}
rubyOverhang :: Bool -> Sp -> Sp -> Sp -> Sp -> Sp
rubyOverhang vertical h big rsize shift
  | vertical = shift + rubyAcross True big rsize + Sp (unSp rsize `div` 2) - Sp (unSp h `div` 2)
  | otherwise = shift + rubyAcross False big rsize + zwToSp (rsize - h) baselineRatio

{- | The centre of a kenten mark of the size @d@ across the line from the
baseline (the centre line) of its character of the size @size@ whose em
box is centred @central@ em above the baseline (golem-driver ADR 0019).
-}
kentenAcross :: Bool -> Sp -> Rational -> Sp -> Sp
kentenAcross vertical size central d
  | vertical = Sp (unSp size `div` 2) + Sp (unSp d `div` 2)
  | otherwise = zwToSp size (central + 1 / 2) + Sp (unSp d `div` 2)

-- | How far a kenten mark reaches out of the face of a line of the size @h@: half the size of its character.
kentenOverhang :: Bool -> Sp -> Sp -> Rational -> Sp -> Sp
kentenOverhang vertical h size central shift =
  let d = Sp (unSp size `div` 2)
      face = if vertical then Sp (unSp h `div` 2) else zwToSp h baselineRatio
   in shift + kentenAcross vertical size central d + Sp (unSp d `div` 2) - face

{- | The largest overhang of the ruby and kenten of a line set at the size
@h@, 0 for none; @central@ gives the centre of the em box of the
characters of a look (golem-driver ADR 0033).
-}
lineOverhang :: Bool -> Sp -> (Look -> Rational) -> Line -> Sp
lineOverhang vertical h central l = maximum (0 : concatMap boxOverhang (lineItems l))
  where
    boxOverhang = \case
      Box _ c -> case boxKind c of
        kind
          | kind `elem` [KindRuby, KindGroupRuby],
            (base, reading) <- T.breakOn "|" (bcText c),
            T.length reading > 1 ->
              let look = bcLook c
                  looks = zipWith const (bcBaseLooks c <> repeat look) (clusters base)
                  big = if null looks then lkSize look else maximum (map lkSize looks)
               in [rubyOverhang vertical h big (Sp (unSp (lkSize look) `div` 2)) (lkBaselineShift look)]
        KindKenten
          | Just _ <- lkKenten (bcLook c) ->
              let look = bcLook c
               in [kentenOverhang vertical h (lkSize look) (central look) (lkBaselineShift look)]
        _ -> []
      _ -> []

{- | Whether an overhang @r@ reaches the background of a code block that
spreads half the leading past its grid lines of the pitch @p@ and the
size @h@, less half the width @b@ of its border: @r > (p - h)/2 - b/2@.
-}
reachesBackground :: Sp -> Sp -> Sp -> Sp -> Bool
reachesBackground p h b r = 2 * r > p - h - b
