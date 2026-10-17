{- | SVG figures for the PDF (golem-pdf ADR 0009): the drawing of
golem-svg as the drawing of golem-pdf, and the wording of G0811.
golem-pdf does not depend on golem-svg; this module joins them.
-}
module Golem.Driver.Svg
  ( svgDrawing,
    unsupportedMessage,
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Pdf qualified as P
import Golem.Svg qualified as S

-- | The drawing of an SVG in the terms of golem-pdf.
svgDrawing :: S.Svg -> P.Drawing
svgDrawing s = P.Drawing (S.svgSize s) (map item (S.svgDrawing s))
  where
    item = \case
      S.DPath p segs -> P.DrawPath (paint p) (map seg segs)
      S.DGroup (S.Matrix a b c d e f) clip ops -> P.DrawGroup [a, b, c, d, e, f] ((\(S.ClipRect x y w h) -> (x, y, w, h)) <$> clip) (map item ops)
    rgb (S.Color r g b) = (r, g, b)
    paint p =
      P.PathPaint
        { P.ppFill = rgb <$> S.paFill p,
          P.ppEvenOdd = S.paFillRule p == S.EvenOdd,
          P.ppStroke = stroke <$> S.paStroke p
        }
    stroke st =
      P.PathStroke
        { P.psColor = rgb (S.stColor st),
          P.psWidth = S.stWidth st,
          P.psCap = case S.stCap st of S.CapButt -> 0; S.CapRound -> 1; S.CapSquare -> 2,
          P.psJoin = case S.stJoin st of S.JoinMiter -> 0; S.JoinRound -> 1; S.JoinBevel -> 2,
          P.psMiterLimit = S.stMiterLimit st,
          P.psDash = S.stDash st,
          P.psDashOffset = S.stDashOffset st
        }
    seg = \case
      S.MoveTo p -> P.SegMove p
      S.LineTo p -> P.SegLine p
      S.CurveTo a b c -> P.SegCurve a b c
      S.ClosePath -> P.SegClose

{- | G0811: the first thing outside the subset, with where it is, and how
many more (golem-pdf ADR 0009).
-}
unsupportedMessage :: Text -> NonEmpty S.Unsupported -> Text
unsupportedMessage path (u :| rest) =
  "SVG の図版に扱えないものがあります: "
    <> path
    <> ":"
    <> tshow (S.unLine u)
    <> ":"
    <> tshow (S.unColumn u)
    <> "（"
    <> S.unName u
    <> (if S.unText u then ": 文字は輪郭にして書き出してください" else "")
    <> "）"
    <> (if null rest then "" else "ほか " <> tshow (length rest) <> " 件")
  where
    tshow :: Int -> Text
    tshow = T.pack . show
