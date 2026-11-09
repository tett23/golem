{- | The widths of the columns of a table and the pagination of a table with
a caption (docs/adr/0262): I5, I6 and I7 by every small set of widths,
and I8 by every small table in every small column.
-}
module TableCaptionSpec (tableCaptionTests) where

import Control.Monad (forM_, unless)
import Data.List (nub)
import Golem.Doc.IR (ColumnWidth (..))
import Golem.Layout.Paginate
import Golem.Layout.Table
import Golem.Length (Sp (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | Every (minimum, natural) width of a column up to n, the minimum at most the natural.
extents :: Int -> [(Sp, Sp)]
extents n = [(fromIntegral mn, fromIntegral nat) | nat <- [0 .. n], mn <- [0 .. nat]]

-- | Auto, or a width in sp from 1 to n.
specs :: Int -> [ColumnWidth]
specs n = ColumnAuto : [ColumnAbs (fromIntegral w) | w <- [1 .. n]]

-- | Every table of 1 to 3 columns: the width the columns share, the widths specified and the extents.
cases :: [(Sp, [ColumnWidth], [(Sp, Sp)])]
cases =
  [ (fromIntegral shared, ws, es)
  | k <- [1 .. 3],
    shared <- [0 .. 7 :: Int],
    ws <- sequenceA (replicate k (specs 4)),
    es <- sequenceA (replicate k (extents 3))
  ]

fixed :: ColumnWidth -> Maybe Sp
fixed = specifiedWidth 10 0

tableCaptionTests :: TestTree
tableCaptionTests =
  testGroup
    "tables with captions and widths (docs/adr/0262)"
    [ testCase "I5: with no error, a specified column has its width and the widths fit the shared width" $
        forM_ cases $ \(shared, ws, es) -> case tableColumnWidths shared 10 ws es of
          Right got -> do
            assertEqual (show (shared, ws, es)) [w | Just w <- map fixed ws] [g | (g, Just _) <- zip got (map fixed ws)]
            assertBool (show (shared, ws, es, got)) (sum got <= shared)
          Left _ -> pure (),
      testCase "I6: the widths of a table of auto columns are those of columnWidths" $
        forM_ cases $ \(shared, _, es) -> do
          let autos = map (const ColumnAuto) es
              want = either (Left . pure) Right (columnWidths shared es)
          tableColumnWidths shared 10 [] es @?= want
          tableColumnWidths shared 10 autos es @?= want,
      testCase "I7: G07114 exactly when the widths specified exceed the shared width; a G07115 for each column narrower than its minimum" $
        forM_ cases $ \(shared, ws, es) -> do
          let errs = either id (const []) (tableColumnWidths shared 10 ws es)
              total = sum [w | Just w <- map fixed ws]
              narrow = length [() | (Just w, (mn, _)) <- zip (map fixed ws) es, w < mn]
          assertEqual (show (shared, ws, es)) (total > shared) (not (null [() | WidthsTooWide {} <- errs]))
          assertEqual (show (shared, ws, es)) narrow (length [() | ColumnTooNarrow {} <- errs]),
      testCase "zw is of the size of the cells and % of the shared width, each truncated to sp" $ do
        specifiedWidth 10 99 (ColumnZw (3 / 4)) @?= Just 7
        specifiedWidth 10 99 (ColumnPercent 50) @?= Just 49
        specifiedWidth 10 100 (ColumnPercent 50) @?= Just 50
        specifiedWidth 10 100 ColumnAuto @?= Nothing
        tableColumnWidths 100 10 [ColumnPercent 50, ColumnPercent 50] [(0, 0), (0, 0)] @?= Right [50, 50]
        tableColumnWidths 100 10 [ColumnPercent 50, ColumnPercent 51] [(0, 0), (0, 0)] @?= Left [WidthsTooWide 101 100]
        tableColumnWidths 100 10 [ColumnPercent 49, ColumnPercent 50] [(0, 0), (0, 0)] @?= Right [49, 50],
      testCase "the auto columns share what the specified ones leave; G07041 when their minimums do not fit it" $ do
        tableColumnWidths 10 1 [ColumnAbs 4, ColumnAuto] [(1, 2), (3, 9)] @?= Right [4, 6]
        tableColumnWidths 10 1 [ColumnAbs 8, ColumnAuto] [(1, 2), (3, 9)] @?= Left [ColumnsTooWide 3 2]
        tableColumnWidths 10 1 [ColumnAbs 11, ColumnAuto] [(1, 2), (3, 9)] @?= Left [WidthsTooWide 11 10],
      testCase "I8: above, a table whose caption, header and first row just fit stays; a line short, it goes on with its caption" $ do
        let lb i = [LineBox i [] [] [] 0]
            tbl = FTable 50 0 (lb 100) [lb 200, lb 201] (lb 900) False
            slots ps = map (map snd . poSlots) ps
        slots (paginate 1 4 [FParagraph (lb 0), tbl]) @?= [[SLine 0, SLine 900, SLine 100, SLine 200], [SLine 100, SLine 201]]
        slots (paginate 1 4 [FParagraph [LineBox i [] [] [] 0 | i <- [0, 1]], tbl]) @?= [[SLine 0, SLine 1], [SLine 900, SLine 100, SLine 200, SLine 201]]
        -- the rules: the first of the table under the caption
        map poTables (paginate 1 4 [FParagraph (lb 0), tbl]) @?= [[TableSegment 50 2 (Just 2) 3], [TableSegment 50 0 (Just 0) 1]],
      testCase "I8: below, the last row goes on with the caption when they do not fit together, after the header repeated" $ do
        let lb i = [LineBox i [] [] [] 0]
            tbl = FTable 50 0 (lb 100) [lb 200, lb 201, lb 202] (lb 900) True
            slots ps = map (map snd . poSlots) ps
        slots (paginate 1 5 [tbl]) @?= [[SLine 100, SLine 200, SLine 201, SLine 202, SLine 900]]
        slots (paginate 1 4 [tbl]) @?= [[SLine 100, SLine 200, SLine 201], [SLine 100, SLine 202, SLine 900]]
        map poTables (paginate 1 4 [tbl]) @?= [[TableSegment 50 0 (Just 0) 2], [TableSegment 50 0 (Just 0) 1]]
        -- a table of one row keeps the header, the row and the caption together
        slots (paginate 1 4 [FParagraph (lb 0), FParagraph (lb 1), FTable 50 0 (lb 100) [lb 200] (lb 900) True]) @?= [[SLine 0, SLine 1], [SLine 100, SLine 200, SLine 900]],
      testCase "I8: the caption keeps to the lines it touches, every small table in every small column" $
        forM_ tableCases $ \c@(cap, lead, below, h, rows) -> do
          let caption = [LineBox (900 + i) [] [] [] 0 | i <- [0 .. cap - 1]]
              header = [LineBox (100 + i) [] [] [] 0 | i <- [0 .. h - 1]]
              body = [[LineBox (200 + 10 * r + i) [] [] [] 0 | i <- [0 .. n - 1]] | (r, n) <- zip [0 ..] rows]
              flow = [FParagraph [LineBox i [] [] [] 0 | i <- [0 .. lead - 1]] | lead > 0] <> [FTable 50 0 header body caption below]
              ps = paginate 1 capacity flow
              columnsOf lid = [(poNumber p, poColumn p) | p <- ps, (_, SLine l) <- poSlots p, l == lid]
              firstColumn lid = take 1 (columnsOf lid)
              touching = if below then map lbId (last body) else map lbId header <> map lbId (head' body)
              capColumns = nub (concatMap (firstColumn . lbId) caption)
          -- the caption is in one column, once
          assertEqual (show c) 1 (length capColumns)
          forM_ caption $ \l -> assertEqual (show c) 1 (length (columnsOf (lbId l)))
          -- the caption is in the column of the lines it touches
          forM_ touching $ \lid -> unless (null (columnsOf lid)) (assertBool (show (c, lid)) (any (`elem` capColumns) (columnsOf lid)))
    ]
  where
    head' = \case
      (x : _) -> x
      [] -> []

capacity :: Int
capacity = 6

{- | The tables whose caption fits an empty column with the lines it
touches, without G07042 or G07116: the grid lines of the caption, the
lines before the table, the side of the caption, the header lines and
the lines of each row.
-}
tableCases :: [(Int, Int, Bool, Int, [Int])]
tableCases =
  [ (cap, lead, below, h, rows)
  | cap <- [1, 2],
    lead <- [0 .. capacity],
    below <- [False, True],
    h <- [0, 1],
    k <- [1 .. 3],
    rows <- sequenceA (replicate k [1, 2]),
    all (\r -> h + r <= capacity) rows,
    h + sum (take 1 (if below then reverse rows else rows)) + cap <= capacity
  ]
