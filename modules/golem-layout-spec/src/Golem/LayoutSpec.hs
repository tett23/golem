{- | Page geometry from style.toml (golem-layout-spec ADR 0001): the type
area, its position, the line grid, columns, the sidenote column and the
positions of running heads and folios. All lengths are sp; the origin
is the bottom-left corner of the page, as in PDF.
-}
module Golem.LayoutSpec
  ( Rect (..),
    Side (..),
    Align (..),
    Anchor (..),
    MasterGeometry (..),
    PageGeometry (..),
    pageGeometry,
    gutterSide,
    typeAreaFor,
    columnsFor,
    sidenoteAreaFor,
    baselineRatio,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.Style
import Golem.Syntax

data Rect = Rect {rectX :: !Sp, rectY :: !Sp, rectW :: !Sp, rectH :: !Sp}
  deriving stock (Eq, Show)

data Side = SideLeft | SideRight
  deriving stock (Eq, Show)

data Align = AlignStart | AlignCenter | AlignEnd
  deriving stock (Eq, Show)

-- | A point and how text is aligned to it horizontally.
data Anchor = Anchor {anX :: !Sp, anY :: !Sp, anAlign :: !Align}
  deriving stock (Eq, Show)

data MasterGeometry = MasterGeometry
  { -- | the contents of odd and even pages and their anchors (golem-driver ADR 0014)
    mgRunningHead :: !(Maybe (RunningContent, RunningContent, Anchor, Anchor)),
    -- | number format and the anchors on odd and even pages
    mgFolio :: !(Maybe (Text, Anchor, Anchor))
  }
  deriving stock (Eq, Show)

data PageGeometry = PageGeometry
  { pgPageSize :: !(Sp, Sp),
    pgVertical :: !Bool,
    pgBindingRight :: !Bool,
    pgFontSize :: !Sp,
    pgLinePitch :: !Sp,
    -- | the type area of odd pages
    pgTypeArea :: !Rect,
    -- | the type area of even pages
    pgTypeAreaEven :: !Rect,
    {- | line positions measured from the type area: in horizontal writing
    the baselines from its top edge, in vertical writing the centre
    lines from its right edge. The same on every page and column, so
    lines align across a spread.
    -} pgLineGrid :: ![Sp],
    -- | columns of odd pages, in reading order
    pgColumns :: ![Rect],
    pgColumnsEven :: ![Rect],
    -- | the sidenote column of odd and even pages
    pgSidenotes :: !(Maybe (Rect, Rect)),
    pgMasters :: !(Map Text MasterGeometry)
  }
  deriving stock (Eq, Show)

{- | The baseline of horizontal text sits this far down the em box (the
ideographic em box of common Japanese fonts: ascent 880, descent 120).
-}
baselineRatio :: Rational
baselineRatio = 88 / 100

{- | Which side of the page the gutter is on. Pages of a right-bound book
turn to the left, so an odd page is the left page of a spread and its
binding edge is on its right; a left-bound book is the mirror image.
-}
gutterSide :: Bool -> Int -> Side
gutterSide bindingRight page
  | bindingRight == odd page = SideRight
  | otherwise = SideLeft

typeAreaFor :: PageGeometry -> Int -> Rect
typeAreaFor g p = if odd p then pgTypeArea g else pgTypeAreaEven g

columnsFor :: PageGeometry -> Int -> [Rect]
columnsFor g p = if odd p then pgColumns g else pgColumnsEven g

sidenoteAreaFor :: PageGeometry -> Int -> Maybe Rect
sidenoteAreaFor g p = (\(o, e) -> if odd p then o else e) <$> pgSidenotes g

{- | The page geometry, or G0701 at the top of @fid@: style.toml, or the
manifest without one (golem-driver ADR 0016). The first condition that
fails is reported, alone. The page size and the positions of master
pages were checked when style.toml was read (G0317, G0318).
-}
pageGeometry :: FileId -> Style -> Either [Diagnostic] PageGeometry
pageGeometry fid style = case stPage style of
  Nothing -> Left [err "style.toml に [page] がないため、版面を計算できません"]
  Just page -> case pageGrid page of
    Nothing -> Left [err "style.toml に [page.grid] がないため、版面を計算できません"]
    Just grid -> geometry page grid (pageTrimSize page)
  where
    err = diagnostic "G0701" Error (mkSpan fid 0 0)
    geometry page grid (pw, ph) = do
      fs <- case gridFontSize grid of
        Abs s | s > 0 -> Right s
        _ -> Left [err "文字の大きさは絶対的な寸法で書いてください"]
      let n = toInteger (gridCharacters grid)
          nLines = toInteger (gridLines grid)
          cols = toInteger (gridColumns grid)
          pitch = dimToSp fs (gridLinePitch grid)
          gap = maybe 0 (dimToSp fs) (gridColumnGap grid)
          vertical = pageVertical page
          lineDepth = pitch * (nLines - 1) + fs -- across the lines
          columnLength = fs * n -- along a line
          (taW, taH)
            | vertical = (lineDepth, cols * columnLength + (cols - 1) * gap)
            | otherwise = (cols * columnLength + (cols - 1) * gap, lineDepth)
          top = dimToSp fs (gridTop grid)
          gutter = dimToSp fs (gridGutter grid)
          bindingRight = pageBindingRight page
          areaOn p =
            let y = ph - top - taH
                x = case gutterSide bindingRight p of
                  SideLeft -> gutter
                  SideRight -> pw - gutter - taW
             in Rect x y taW taH
          odd' = areaOn 1
          even' = areaOn 2
          columnsOf (Rect x y _ _)
            | vertical = [Rect x (y + taH - (i + 1) * columnLength - i * gap) taW columnLength | i <- [0 .. cols - 1]]
            | otherwise =
                -- columns run in the line direction: left to right
                [Rect (x + i * (columnLength + gap)) y columnLength taH | i <- [0 .. cols - 1]]
          grid'
            | vertical = [i * pitch + fs `div` 2 | i <- [0 .. nLines - 1]]
            | otherwise = [i * pitch + round (fromInteger fs * baselineRatio) | i <- [0 .. nLines - 1]]
          overflow (Rect x y w h) = x < 0 || y < 0 || x + w > pw || y + h > ph
      if n <= 0 || nLines <= 0 || cols <= 0 || pitch < fs
        then Left [err "字数、行数、段数は 1 以上、行送りは文字の大きさ以上にしてください"]
        else
          if overflow odd' || overflow even'
            then Left [err "版面がページからはみ出しています"]
            else do
              sidenotes <- case stSidenotes style of
                Nothing -> Right Nothing
                Just _ | vertical -> Left [err "縦組みの版面には傍注欄を設けられません"]
                -- no sidenote column on a page of columns (docs/adr ADR 0018)
                Just _ | cols > 1 -> Left [err "段組みの版面には傍注欄を設けられません"]
                Just sn -> do
                  let w = dimToSp fs (snWidth sn)
                      g = dimToSp fs (snGap sn)
                      placeOn p r@(Rect x y _ h) = case gutterSide bindingRight p of
                        SideLeft -> Rect (x + rectW r + g) y w h -- fore-edge on the right
                        SideRight -> Rect (x - g - w) y w h
                      so = placeOn 1 odd'
                      se = placeOn 2 even'
                  if overflow so || overflow se
                    then Left [err "版面と傍注欄の合計がページからはみ出しています"]
                    else Right (Just (so, se))
              let masters = Map.map (masterGeometry ph bindingRight odd' even') (stMasters style)
              Right
                PageGeometry
                  { pgPageSize = (pw, ph),
                    pgVertical = vertical,
                    pgBindingRight = bindingRight,
                    pgFontSize = fs,
                    pgLinePitch = pitch,
                    pgTypeArea = odd',
                    pgTypeAreaEven = even',
                    pgLineGrid = grid',
                    pgColumns = columnsOf odd',
                    pgColumnsEven = columnsOf even',
                    pgSidenotes = sidenotes,
                    pgMasters = masters
                  }

{- | Positions such as @top-outside@: vertically the middle of the head or
foot margin; horizontally the outer (fore-edge), inner (gutter) edge or
the centre of the type area.
-}
masterGeometry :: Sp -> Bool -> Rect -> Rect -> MasterDef -> MasterGeometry
masterGeometry ph bindingRight oddArea evenArea md =
  MasterGeometry (head' <$> mdRunningHead md) (place <$> mdFolio md)
  where
    head' rh = (rhOdd rh, rhEven rh, anchor (rhPosition rh) 1 oddArea, anchor (rhPosition rh) 2 evenArea)
    place (pos, content) = (content, anchor pos 1 oddArea, anchor pos 2 evenArea)
    anchor pos p (Rect x y w h) =
      let (vert, horiz) = T.breakOn "-" pos
          ay = if vert == "top" then (y + h + ph) `div` 2 else y `div` 2
          gutterLeft = gutterSide bindingRight p == SideLeft
          (ax, al) = case horiz of
            "-outside" -> if gutterLeft then (x + w, AlignEnd) else (x, AlignStart)
            "-inside" -> if gutterLeft then (x, AlignStart) else (x + w, AlignEnd)
            _ -> (x + w `div` 2, AlignCenter)
       in Anchor ax ay al
