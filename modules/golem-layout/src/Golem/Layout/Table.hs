{- | Tables on the line grid (golem-driver ADR 0008): column widths from
the cells' minimum and natural widths, cells broken into lines at their
column width, rows as high as their tallest cell.

Lengths are 'Sp', along the lines ("widths") whatever the writing direction.
-}
module Golem.Layout.Table
  ( cellExtent,
    TableError (..),
    columnWidths,
    specifiedWidth,
    tableColumnWidths,
    SetCell (..),
    SetTable (..),
    layoutTable,
  )
where

import Data.Maybe (catMaybes, isJust)
import Golem.Doc.IR (Alignment (..), ColumnWidth (..))
import Golem.Layout.KnuthPlass

{- | The minimum width of a cell (its widest piece between break
opportunities: glue after a box, or a penalty below infinity that is not
a pattern hyphen; an explicit hyphen is one, golem-layout ADR 0008; a
piece that ends at a penalty holds its width, the wrap mark of a break of
code that a line broken there ends with, golem-layout ADR 0034 and 0045,
docs/adr ADR 0255)
and its natural width (boxes and glue on one line).
-}
cellExtent :: [Item] -> (Sp, Sp)
cellExtent items = (maximum (0 : segments), natural)
  where
    natural = sum [w | Box w _ <- items] + sum [w | Glue w y _ _ _ <- items, y < filStretch]
    segments = go 0 Nothing items
    go acc _ [] = [acc]
    go acc prev (x : xs) = case x of
      Box w _ -> go (acc + w) (Just x) xs
      Glue {itemWidth = w}
        | isBox prev -> acc : go 0 (Just x) xs
        | otherwise -> go (acc + w) (Just x) xs
      Penalty w p h
        | p < infPenalty && not (isPatternHyphen h) -> acc + w : go 0 (Just x) xs
        | otherwise -> go acc (Just x) xs
    isBox = \case
      Just Box {} -> True
      _ -> False

{- | Why the columns of a table cannot be set: the minimum widths of the
auto columns do not fit, their sum and the width available (G07041); the
specified widths exceed the width the columns share, their sum and that
width (G07114, docs/adr/0262); a column specified narrower than its
minimum width, its index from 0, its width and its minimum width
(G07115).
-}
data TableError
  = ColumnsTooWide !Sp !Sp
  | WidthsTooWide !Sp !Sp
  | ColumnTooNarrow !Int !Sp !Sp
  deriving stock (Eq, Show)

{- | Column widths from the width available and each column's (minimum,
natural) width (golem-driver ADR 0037): natural widths when they fit;
otherwise each column up to the largest level C whose widths, C held
between the minimum and the natural width, still fit, so that the short
columns are filled and the long ones share the rest; the remainder is
given 1sp at a time from the first column at the level, its minimum width
at most C and its natural width wider (docs/adr ADR 0295): a column wider
than C for its minimum takes none, so that no column narrows as the width
available grows. The columns at the level are S(C + 1) − S(C), more than
the remainder as C is the largest.
-}
columnWidths :: Sp -> [(Sp, Sp)] -> Either TableError [Sp]
columnWidths available cols
  | sum (map snd cols) <= available = Right (map snd cols)
  | sumMin <= available =
      let level = search 0 (maximum (map snd cols))
          widths = map (clampTo level) cols
          leftover = available - sum widths
          atLevel = [mn <= level && level < nat | (mn, nat) <- cols]
          ranks = scanl (+) 0 [if a then 1 else 0 | a <- atLevel]
       in Right [w + (if a && k < leftover then 1 else 0) | (w, a, k) <- zip3 widths atLevel ranks]
  | otherwise = Left (ColumnsTooWide sumMin available)
  where
    sumMin = sum (map fst cols)
    clampTo c (mn, nat) = max mn (min c nat)
    fits c = sum (map (clampTo c) cols) <= available
    -- the largest c in [lo, hi] that fits; lo fits
    search lo hi
      | lo >= hi = lo
      | otherwise = let mid = Sp (unSp (lo + hi + 1) `div` 2) in if fits mid then search mid hi else search lo (mid - 1)

{- | A specified width in sp (docs/adr/0262): zw of the size of the cells,
a percentage of the width the columns share, each truncated to sp;
Nothing for auto.
-}
specifiedWidth :: Sp -> Sp -> ColumnWidth -> Maybe Sp
specifiedWidth size shared = \case
  ColumnAuto -> Nothing
  ColumnZw q -> Just (Sp (floor (fromInteger (unSp size) * q)))
  ColumnAbs x -> Just x
  ColumnPercent q -> Just (Sp (floor (fromInteger (unSp shared) * q / 100)))

{- | The widths of the columns (docs/adr/0262): from the width the columns
share, the size of the cells, the specified widths ([] is every column
auto) and each column's (minimum, natural) width. A specified width is
used as it is; the auto columns share what the specified ones leave, as
'columnWidths'. Every error found is returned: G07114 when the specified
widths exceed the width, G07115 for each column specified narrower than
its minimum, and G07041 for the auto columns only when neither of the
others is.
-}
tableColumnWidths :: Sp -> Sp -> [ColumnWidth] -> [(Sp, Sp)] -> Either [TableError] [Sp]
tableColumnWidths shared size specs cols =
  let specified = zipWith (\w _ -> specifiedWidth size shared w) (specs <> repeat ColumnAuto) cols
      fixedSum = sum (catMaybes specified)
      -- only widths written exceed: without them, the auto columns are G07041
      over = [WidthsTooWide fixedSum shared | any isJust specified, fixedSum > shared]
      narrow = [ColumnTooNarrow i w mn | (i, Just w, (mn, _)) <- zip3 [0 ..] specified cols, w < mn]
      autos = [c | (Nothing, c) <- zip specified cols]
   in case over <> narrow of
        [] -> case columnWidths (shared - fixedSum) autos of
          Left e -> Left [e]
          Right ws -> Right (fill specified ws)
        errs -> Left errs
  where
    fill (Just w : rest) ws = w : fill rest ws
    fill (Nothing : rest) (w : ws) = w : fill rest ws
    fill _ _ = []

data SetCell = SetCell
  { -- | from the start of the table: the column's position and the alignment of the first line
    scOffset :: !Sp,
    scLines :: ![Line],
    -- | the alignment of each line beyond 'scOffset' (justified lines need none)
    scShifts :: ![Sp]
  }
  deriving stock (Eq, Show)

data SetTable = SetTable
  { stWidths :: ![Sp],
    -- | the columns and the gaps between them
    stWidth :: !Sp,
    stHeader :: ![SetCell],
    stRows :: ![[SetCell]],
    -- | the height of the header row in grid lines
    stHeaderLines :: !Int,
    stRowLines :: ![Int]
  }
  deriving stock (Eq, Show)

{- | Lays out a table: the line breaking parameters, the measure, the gap
between columns (one character of the cells), the specified widths of
the columns (docs/adr/0262), the alignments, the items of the header
cells and of each row's cells. Cells never protrude or hang into the gaps.
-}
layoutTable :: Params -> Sp -> Sp -> [ColumnWidth] -> [Alignment] -> [[Item]] -> [[[Item]]] -> Either [TableError] SetTable
layoutTable params measure gap specs aligns header rows = do
  let ncols = maximum (0 : map length (header : rows))
      cell r c = case drop c r of
        (x : _) -> x
        [] -> []
      columns = [[cellExtent (cell r c) | r <- header : rows] | c <- [0 .. ncols - 1]]
      extents = [(maximum (0 : map fst col), maximum (0 : map snd col)) | col <- columns]
      available = measure - gap * fromIntegral (max 0 (ncols - 1))
  widths <- tableColumnWidths available gap specs extents
  let positions = scanl (\p w -> p + w + gap) 0 widths
      ps = params {pProtrusion = False}
      alignOf c = case drop c aligns of
        (a : _) -> a
        [] -> AlignDefault
      setCell r c =
        let w = widths !! c
            items = cell r c
            ls = if null items then [] else brLines (breakParagraph ps (const w) items)
            shift l =
              let room = max 0 (w - contentWidth l)
               in case alignOf c of
                    AlignRight -> room
                    AlignCenter -> Sp (unSp room `div` 2)
                    _ -> 0
            shifts = map shift ls
            first = case shifts of
              (x : _) -> x
              [] -> 0
         in SetCell (positions !! c + first) ls [s - first | s <- shifts]
      setRow r = [setCell r c | c <- [0 .. ncols - 1]]
      height cs = maximum (1 : map (length . scLines) cs)
      -- an empty header is a table without a header row (golem-driver ADR 0031)
      headerCells = if null header then [] else setRow header
      rowCells = map setRow rows
  pure
    SetTable
      { stWidths = widths,
        stWidth = sum widths + gap * fromIntegral (max 0 (ncols - 1)),
        stHeader = headerCells,
        stRows = rowCells,
        stHeaderLines = if null header then 0 else height headerCells,
        stRowLines = map height rowCells
      }

-- | Where the last box of a set line ends.
contentWidth :: Line -> Sp
contentWidth l = case [(w, x) | (Box w _, x) <- placeLine l] of
  [] -> 0
  bs -> let (w, x) = last bs in x + w
