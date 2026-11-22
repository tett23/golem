{- | SVG figures for the PDF (golem-pdf ADR 0009): the drawing of
golem-svg as the drawing of golem-pdf, and the wording of G08011.
golem-pdf does not depend on golem-svg; this module joins them.
-}
module Golem.Typeset.Svg
  ( svgDrawing,
    recolorFigure,
    drawingSvg,
    figureColor,
    unsupportedMessage,
    markerMessage,
    markerSegmentsMessage,
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Length.Decimal (showRationalDigits)
import Golem.Pdf qualified as P
import Golem.Project.Style (Style (..), Swatch (..))
import Golem.Svg qualified as S
import Golem.Typeset.FigureColor (Cmyk, rgbTone)

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

{- | G08011: the first thing outside the subset, with where it is, and how
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

{- | G08016 and G08017 (docs/adr ADR 0054): the first reference to a marker,
with where the shape that holds it is and the id it places, and how many
more.
-}
markerMessage :: Text -> Text -> NonEmpty S.MarkerRef -> Text
markerMessage lead path (r :| rest) =
  lead
    <> path
    <> ":"
    <> tshow (S.mrLine r)
    <> ":"
    <> tshow (S.mrColumn r)
    <> "（"
    <> S.mrId r
    <> "）"
    <> (if null rest then "" else "ほか " <> tshow (length rest) <> " 件")
  where
    tshow :: Int -> Text
    tshow = T.pack . show

{- | G08101 (docs/adr ADR 0084): the path of the figure and the segments its
markers draw; no line and column, since the count is of the whole drawing.
-}
markerSegmentsMessage :: Text -> Integer -> Text
markerSegmentsMessage path n = "SVG の図版の marker が描くパスの区間が 1000000 を超えます: " <> path <> "（" <> T.pack (show n) <> "）"

-- | Grayscale has priority over a single chromatic colour (root ADR 0403).
recolorFigure :: Cmyk -> P.FigureContent -> P.FigureContent
recolorFigure swatch figure@(P.SvgFigure drawing)
  | Set.null used = figure
  | all gray (Set.toList used) = paint (\(r, _, _) -> rgbTone swatch (fromIntegral r / 255))
  | Set.size used == 1 = paint (const (rgbTone swatch 0))
  | otherwise = figure
  where
    used = Set.fromList (concatMap colors (P.drItems drawing))
    gray (r, g, b) = r == g && g == b
    colors (P.DrawPath p _) = maybe [] pure (P.ppFill p) <> maybe [] (pure . P.psColor) (P.ppStroke p)
    colors (P.DrawGroup _ _ items) = concatMap colors items
    paint convert = P.SvgFigure drawing {P.drItems = map (replace convert) (P.drItems drawing)}
    replace convert (P.DrawPath p segments) = P.DrawPath p {P.ppFill = convert <$> P.ppFill p, P.ppStroke = (\stroke -> stroke {P.psColor = convert (P.psColor stroke)}) <$> P.ppStroke p} segments
    replace convert (P.DrawGroup matrix clip items) = P.DrawGroup matrix clip (map (replace convert) items)
recolorFigure _ figure = figure

-- | A self-contained SVG of the supported drawing subset, preserving geometry.
drawingSvg :: P.Drawing -> Text
drawingSvg (P.Drawing (width, height) items) =
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" <> number width <> "\" height=\"" <> number height <> "\" viewBox=\"0 0 " <> number width <> " " <> number height <> "\">" <> children "g" items <> "</svg>"
  where
    number = showRationalDigits 12
    point (x, y) = number x <> " " <> number y
    attribute key value = " " <> key <> "=\"" <> value <> "\""
    rgb (r, g, b) = "rgb(" <> T.intercalate "," (map (T.pack . show) [r, g, b]) <> ")"
    children prefix xs = T.concat [item (prefix <> "-" <> T.pack (show i)) x | (i, x) <- zip [0 :: Int ..] xs]
    item ident = \case
      P.DrawGroup matrix clip xs ->
        "<g"
          <> attribute "transform" ("matrix(" <> T.intercalate " " (map number matrix) <> ")")
          <> ">"
          <> maybe "" (\(x, y, w, h) -> "<defs><clipPath" <> attribute "id" ident <> "><rect" <> attribute "x" (number x) <> attribute "y" (number y) <> attribute "width" (number w) <> attribute "height" (number h) <> "/></clipPath></defs><g" <> attribute "clip-path" ("url(#" <> ident <> ")") <> ">") clip
          <> children ident xs
          <> maybe "" (const "</g>") clip
          <> "</g>"
      P.DrawPath paint segments ->
        "<path"
          <> attribute "d" (T.intercalate " " (map segment segments))
          <> attribute "fill" (maybe "none" rgb (P.ppFill paint))
          <> attribute "fill-rule" (if P.ppEvenOdd paint then "evenodd" else "nonzero")
          <> maybe (attribute "stroke" "none") stroke (P.ppStroke paint)
          <> "/>"
    segment = \case
      P.SegMove p -> "M " <> point p
      P.SegLine p -> "L " <> point p
      P.SegCurve a b c -> "C " <> point a <> " " <> point b <> " " <> point c
      P.SegClose -> "Z"
    stroke s =
      attribute "stroke" (rgb (P.psColor s))
        <> attribute "stroke-width" (number (P.psWidth s))
        <> attribute "stroke-linecap" (case P.psCap s of 1 -> "round"; 2 -> "square"; _ -> "butt")
        <> attribute "stroke-linejoin" (case P.psJoin s of 1 -> "round"; 2 -> "bevel"; _ -> "miter")
        <> attribute "stroke-miterlimit" (number (P.psMiterLimit s))
        <> attribute "stroke-dasharray" (if null (P.psDash s) then "none" else T.intercalate " " (map number (P.psDash s)))
        <> attribute "stroke-dashoffset" (number (P.psDashOffset s))

-- | The explicitly selected swatch, independent of page furniture and rules.
figureColor :: Style -> Maybe Cmyk
figureColor style = do
  name <- stFigureColor style
  Swatch components <- Map.lookup name (stSwatches style)
  pure components
