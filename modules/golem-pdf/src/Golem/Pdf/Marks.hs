{- | Crop marks and bleed (ADR 0004): the page boxes of a sheet, the lines
of Japanese and Western crop marks, and a page framed with them.

Everything is in integer sp. The millimetre constants are rounded once
from exact rationals, as Golem.Project.Style.parseDim does.
-}
module Golem.Pdf.Marks
  ( MarkStyle (..),
    Sheet (..),
    sheet,
    markRules,
    framePage,
    registrationRects,
    checkRegistration,
  )
where

import Golem.LayoutSpec (Rect (..))
import Golem.Pdf.Writer (Mark (..), Page (..), Sp)

data MarkStyle = Japanese | Western
  deriving stock (Eq, Show)

-- | The boxes of one page, and where the trimmed page starts in the MediaBox.
data Sheet = Sheet
  { shMedia :: !Rect,
    shTrim :: !Rect,
    shBleed :: !Rect,
    -- | the lower left corner of the trimmed page, on both axes
    shOrigin :: !Sp
  }
  deriving stock (Eq, Show)

-- | 3mm, 10mm and 13mm in sp.
mm3, mm10, mm13 :: Sp
mm3 = 557314
mm10 = 1857713
mm13 = 2415027

-- | The thickness of a line (0.25pt) and its half.
thickness, halfThickness :: Sp
thickness = 16384
halfThickness = 8192

-- | The length of a line.
lineLength :: Sp
lineLength = mm10

-- | How far from the trimmed page the marks start.
startOf :: MarkStyle -> Sp -> Sp
startOf Japanese bleed = bleed
startOf Western bleed = max bleed mm3

{- | The boxes of a page of size @(w, h)@ with the given marks and bleed.
The MediaBox starts at the origin.
-}
sheet :: Maybe MarkStyle -> Sp -> (Sp, Sp) -> Sheet
sheet marks bleed (w, h) =
  let m = maybe bleed (\st -> startOf st bleed + mm13) marks
   in Sheet
        { shMedia = Rect 0 0 (w + 2 * m) (h + 2 * m),
          shTrim = Rect m m w h,
          shBleed = Rect (m - bleed) (m - bleed) (w + 2 * bleed) (h + 2 * bleed),
          shOrigin = m
        }

{- | The lines of the crop marks as thin filled rectangles, in coordinates
whose origin is the lower left corner of the trimmed page. Corner marks
come first (lower left, lower right, upper right, upper left), then centre
marks (bottom, right, top, left).
-}
markRules :: MarkStyle -> Sp -> (Sp, Sp) -> [Rect]
markRules style bleed (w, h) = concatMap corner corners <> centres
  where
    o = startOf style bleed
    l = lineLength
    t = thickness
    half = halfThickness
    -- a horizontal line on y from x0 to x0 + len, and a vertical one
    horizontal x0 y len = Rect x0 (y - half) len t
    vertical x y0 = Rect (x - half) y0 t
    -- the lower left corner: the trim lines, then the bleed lines (Japanese only)
    lowerLeft =
      [horizontal (-(o + l)) 0 l]
        <> [horizontal (-(o + l)) (-bleed) l | style == Japanese]
        <> [vertical 0 (-(o + l)) l]
        <> [vertical (-bleed) (-(o + l)) l | style == Japanese]
    mirrorX (Rect x y rw rh) = Rect (w - x - rw) y rw rh
    mirrorY (Rect x y rw rh) = Rect x (h - y - rh) rw rh
    corners = [id, mirrorX, mirrorX . mirrorY, mirrorY]
    corner f = map f lowerLeft
    cx = w `div` 2
    cy = h `div` 2
    hl = l `div` 2
    centres =
      [ -- bottom: the line across the edge, then the one along it
        vertical cx (-(o + l)) l,
        horizontal (cx - hl) (-(o + hl)) l,
        -- right
        horizontal (w + o) cy l,
        vertical (w + o + hl) (cy - hl) l,
        -- top
        vertical cx (h + o) l,
        horizontal (cx - hl) (h + o + hl) l,
        -- left
        horizontal (-(o + l)) cy l,
        vertical (-(o + hl)) (cy - hl) l
      ]

{- | A page of size @(w, h)@ with its content, framed by the bleed and the
marks. The content is moved to the trimmed page; the marks are drawn
after it in the registration colour (ADR 0007).
-}
framePage :: Maybe MarkStyle -> Sp -> (Sp, Sp) -> [Mark] -> Page
framePage marks bleed size content =
  let s = sheet marks bleed size
      m = shOrigin s
      drawn = [RegistrationRules (markRules st bleed size) | Just st <- [marks]]
      content'
        | m == 0 = content
        | otherwise = [Translated m m (content <> drawn)]
   in Page (shMedia s) (shTrim s) (shBleed s) content'

{- | The rectangles of the 'RegistrationRules' in page content, in page
coordinates: the moves of 'Translated' are added (ADR 0007).
-}
registrationRects :: [Mark] -> [Rect]
registrationRects = concatMap (go 0 0)
  where
    go dx dy = \case
      RegistrationRules rs -> [Rect (x + dx) (y + dy) w h | Rect x y w h <- rs]
      Saved ms -> concatMap (go dx dy) ms
      ActualText _ ms -> concatMap (go dx dy) ms
      Translated x y ms -> concatMap (go (dx + x) (dy + y)) ms
      _ -> []

{- | The numbers (from 1) of the pages whose registration colour meets the
interior of their BleedBox; empty when the colour stays in the marks
(ADR 0007).
-}
checkRegistration :: [Page] -> [Int]
checkRegistration pages =
  [n | (n, p) <- zip [1 ..] pages, any (overlaps (pageBleedBox p)) (registrationRects (pageContent p))]
  where
    overlaps (Rect x y w h) (Rect x' y' w' h') = x < x' + w' && x' < x + w && y < y' + h' && y' < y + h
