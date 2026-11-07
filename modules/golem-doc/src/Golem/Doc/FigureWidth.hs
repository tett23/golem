{- | The width of a figure as written (docs/adr/0190): a length in mm, pt,
Q, H or in, a number of characters of the body (zw), or a percentage of
the measure. The one reader of the width of every figure, wrapped or not:
the evaluation checks it (G02133), the PDF sets the figure by it, and HTML
and EPUB write it on the image.
-}
module Golem.Doc.FigureWidth
  ( FigureWidth (..),
    parseFigureWidth,
    figureWidthSp,
  )
where

import Data.Char (isDigit)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Length (Sp (..), Unit (..), toSp, zwToSp)

-- | A width: an absolute length, characters of the body, or a percentage of the measure.
data FigureWidth
  = WidthLength !Sp
  | WidthZw !Rational
  | WidthPercent !Rational
  deriving stock (Eq, Show)

{- | Reads a width: an unsigned integer or decimal and its unit, @mm@, @pt@,
@Q@, @H@, @in@, @zw@ or @%@. A length becomes sp once, rounded half to
even, as the dimensions of style.toml (golem-project ADR 0010). A width
of 0, or a length that is 0sp, is not a width.
-}
parseFigureWidth :: Text -> Maybe FigureWidth
parseFigureWidth t =
  let (num, unit) = T.span (\c -> isDigit c || c == '.') (T.strip t)
   in do
        r <- decimal num
        w <- case unit of
          "pt" -> Just (WidthLength (toSp Pt r))
          "in" -> Just (WidthLength (toSp In r))
          "mm" -> Just (WidthLength (toSp Mm r))
          "Q" -> Just (WidthLength (toSp Q r))
          "H" -> Just (WidthLength (toSp H r))
          "zw" -> Just (WidthZw r)
          "%" -> Just (WidthPercent r)
          _ -> Nothing
        if positive w then Just w else Nothing
  where
    positive = \case
      WidthLength s -> s > 0
      WidthZw r -> r > 0
      WidthPercent r -> r > 0
    decimal s = case T.splitOn "." s of
      [i] | not (T.null i) -> Just (fromInteger (read (T.unpack i)))
      [i, f] | not (T.null i), not (T.null f) -> Just (read (T.unpack (i <> f)) % (10 ^ T.length f))
      _ -> Nothing

{- | A width in sp, for the body size and the measure: zw rounded half to
even as the dimensions of style.toml, a percentage truncated to sp from
the exact rational (docs/adr/0002).
-}
figureWidthSp :: Sp -> Sp -> FigureWidth -> Sp
figureWidthSp fontSize measure = \case
  WidthLength s -> s
  WidthZw r -> zwToSp fontSize r
  WidthPercent r -> Sp (floor (fromInteger (unSp measure) * r / 100))
