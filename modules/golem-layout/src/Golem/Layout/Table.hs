{- | Tables on the line grid (golem-driver ADR 0008): column widths from
the cells' minimum and natural widths, cells broken into lines at their
column width, rows as high as their tallest cell. Integer sp only.

Lengths are along the lines ("widths") whatever the writing direction.
-}
module Golem.Layout.Table
  ( cellExtent,
    TableError (..),
    columnWidths,
    SetCell (..),
    SetTable (..),
    layoutTable,
  )
where

import Golem.Doc.IR (Alignment (..))
import Golem.Layout.KnuthPlass

{- | The minimum width of a cell (its widest piece between break
opportunities: glue after a box, or a penalty below infinity that is not
a pattern hyphen; an explicit hyphen is one, golem-layout ADR 0008) and
its natural width (boxes and glue on one line).
-}
cellExtent :: [Item] -> (Sp, Sp)
cellExtent items = (maximum (0 : segments), natural)
  where
    natural = sum [w | Box w _ <- items] + sum [w | Glue w y _ <- items, y < filStretch]
    segments = go 0 Nothing items
    go acc _ [] = [acc]
    go acc prev (x : xs) = case x of
      Box w _ -> go (acc + w) (Just x) xs
      Glue w _ _
        | isBox prev -> acc : go 0 (Just x) xs
        | otherwise -> go (acc + w) (Just x) xs
      Penalty _ p h
        | p < infPenalty && not (isPatternHyphen h) -> acc : go 0 (Just x) xs
        | otherwise -> go acc (Just x) xs
    isBox = \case
      Just Box {} -> True
      _ -> False

-- | The minimum widths do not fit: their sum and the width available.
data TableError = ColumnsTooWide !Sp !Sp
  deriving stock (Eq, Show)

{- | Column widths from the width available and each column's (minimum,
natural) width: natural widths when they fit; otherwise the minimum plus
a share of the rest in proportion to (natural − minimum), rounded down,
the remainder given 1sp at a time from the first column.
-}
columnWidths :: Sp -> [(Sp, Sp)] -> Either TableError [Sp]
columnWidths available cols
  | sum (map snd cols) <= available = Right (map snd cols)
  | sumMin <= available =
      let rest = available - sumMin
          diffs = [nat - mn | (mn, nat) <- cols]
          total = sum diffs
          shares = [if total > 0 then rest * d `div` total else 0 | d <- diffs]
          leftover = rest - sum shares
       in Right [mn + sh + (if toInteger i < leftover then 1 else 0) | (i, (mn, _), sh) <- zip3 [0 :: Int ..] cols shares]
  | otherwise = Left (ColumnsTooWide sumMin available)
  where
    sumMin = sum (map fst cols)

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
between columns, the alignments, the items of the header cells and of
each row's cells. Cells never protrude or hang into the gaps.
-}
layoutTable :: Params -> Sp -> Sp -> [Alignment] -> [[Item]] -> [[[Item]]] -> Either TableError SetTable
layoutTable params measure gap aligns header rows = do
  let ncols = maximum (0 : map length (header : rows))
      cell r c = case drop c r of
        (x : _) -> x
        [] -> []
      columns = [[cellExtent (cell r c) | r <- header : rows] | c <- [0 .. ncols - 1]]
      extents = [(maximum (0 : map fst col), maximum (0 : map snd col)) | col <- columns]
      available = measure - gap * toInteger (max 0 (ncols - 1))
  widths <- columnWidths available extents
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
                    AlignCenter -> room `div` 2
                    _ -> 0
            shifts = map shift ls
            first = case shifts of
              (x : _) -> x
              [] -> 0
         in SetCell (positions !! c + first) ls [s - first | s <- shifts]
      setRow r = [setCell r c | c <- [0 .. ncols - 1]]
      height cs = maximum (1 : map (length . scLines) cs)
      headerCells = setRow header
      rowCells = map setRow rows
  pure
    SetTable
      { stWidths = widths,
        stWidth = sum widths + gap * toInteger (max 0 (ncols - 1)),
        stHeader = headerCells,
        stRows = rowCells,
        stHeaderLines = height headerCells,
        stRowLines = map height rowCells
      }

-- | Where the last box of a set line ends.
contentWidth :: Line -> Sp
contentWidth l = case [(w, x) | (Box w _, x) <- placeLine l] of
  [] -> 0
  bs -> let (w, x) = last bs in x + w
