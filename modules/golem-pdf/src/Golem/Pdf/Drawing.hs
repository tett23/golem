{- | Drawings of SVG figures in PDF operators (golem-pdf ADR 0009): paths
with their fill and stroke, and groups with a matrix and a clip. Colours
are sRGB, written in the ICCBased colour space GolemSRGB; there is no
text, transparency, pattern or shading. Coordinates and matrices are
rounded to 1/65536 when they are written.
-}
module Golem.Pdf.Drawing
  ( Drawing (..),
    DrawItem (..),
    PathPaint (..),
    PathStroke (..),
    PathSeg (..),
    drawingContent,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.Ratio ((%))
import Data.Text.Encoding qualified as TE
import Golem.Pdf.Number (showRationalDigits)

-- | A drawing: its width and height, and what it draws, y downwards from the top left.
data Drawing = Drawing
  { drSize :: !(Rational, Rational),
    drItems :: ![DrawItem]
  }
  deriving stock (Eq, Show)

data DrawItem
  = DrawPath !PathPaint ![PathSeg]
  | -- | the matrix [a b c d e f], a clip (x, y, width, height) in the coordinates of the group, the items inside
    DrawGroup ![Rational] !(Maybe (Rational, Rational, Rational, Rational)) ![DrawItem]
  deriving stock (Eq, Show)

data PathPaint = PathPaint
  { -- | sRGB from 0 to 255
    ppFill :: !(Maybe (Int, Int, Int)),
    ppEvenOdd :: !Bool,
    ppStroke :: !(Maybe PathStroke)
  }
  deriving stock (Eq, Show)

data PathStroke = PathStroke
  { psColor :: !(Int, Int, Int),
    psWidth :: !Rational,
    -- | 0 butt, 1 round, 2 square (J)
    psCap :: !Int,
    -- | 0 miter, 1 round, 2 bevel (j)
    psJoin :: !Int,
    psMiterLimit :: !Rational,
    -- | empty for a solid line
    psDash :: ![Rational],
    psDashOffset :: !Rational
  }
  deriving stock (Eq, Show)

data PathSeg
  = SegMove !(Rational, Rational)
  | SegLine !(Rational, Rational)
  | SegCurve !(Rational, Rational) !(Rational, Rational) !(Rational, Rational)
  | SegClose
  deriving stock (Eq, Show)

-- | A number rounded to 1/65536.
fixed :: Rational -> B.Builder
fixed v = B.byteString (TE.encodeUtf8 (showRationalDigits 6 (round (v * 65536) % 65536)))

-- | A colour component from 0 to 255 as 0 to 1.
component :: Int -> B.Builder
component c = B.byteString (TE.encodeUtf8 (showRationalDigits 4 (toInteger c % 255)))

{- | The content stream of a drawing: y turned upwards over its height,
then each item. Fill colours use @sc@ and stroke colours @SC@ in the
colour space GolemSRGB, which the resources must name.
-}
drawingContent :: Drawing -> ByteString
drawingContent (Drawing (_, h) items) =
  BL.toStrict (B.toLazyByteString ("1 0 0 -1 0 " <> fixed h <> " cm\n/GolemSRGB cs /GolemSRGB CS\n" <> mconcat (map item items)))
  where
    sp = B.char7 ' '
    nl = B.char7 '\n'
    point (x, y) = fixed x <> sp <> fixed y
    item = \case
      DrawGroup m clip inner ->
        "q "
          <> mconcat [fixed v <> sp | v <- m]
          <> "cm"
          <> nl
          <> maybe mempty (\(x, y, w, hh) -> fixed x <> sp <> fixed y <> sp <> fixed w <> sp <> fixed hh <> " re W n" <> nl) clip
          <> mconcat (map item inner)
          <> "Q"
          <> nl
      DrawPath p segs ->
        let rgb (r, g, b) = component r <> sp <> component g <> sp <> component b
            fill = maybe mempty (\c -> rgb c <> " sc" <> nl) (ppFill p)
            stroke = case ppStroke p of
              Nothing -> mempty
              Just s ->
                rgb (psColor s)
                  <> " SC "
                  <> fixed (psWidth s)
                  <> " w "
                  <> B.intDec (psCap s)
                  <> " J "
                  <> B.intDec (psJoin s)
                  <> " j "
                  <> fixed (psMiterLimit s)
                  <> " M ["
                  <> mconcat (zipWith (\i d -> (if i == (0 :: Int) then mempty else sp) <> fixed d) [0 ..] (psDash s))
                  <> "] "
                  <> fixed (psDashOffset s)
                  <> " d"
                  <> nl
            path = mconcat (map seg segs)
            op = case (ppFill p, ppStroke p) of
              (Just _, Just _) -> if ppEvenOdd p then "B*" else "B"
              (Just _, Nothing) -> if ppEvenOdd p then "f*" else "f"
              (Nothing, Just _) -> "S"
              (Nothing, Nothing) -> "n"
         in "q" <> nl <> fill <> stroke <> path <> op <> nl <> "Q" <> nl
    seg = \case
      SegMove p -> point p <> " m" <> nl
      SegLine p -> point p <> " l" <> nl
      SegCurve a b c -> point a <> sp <> point b <> sp <> point c <> " c" <> nl
      SegClose -> "h" <> nl
