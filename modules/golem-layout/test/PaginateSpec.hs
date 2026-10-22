{- | Pagination (golem-layout ADR 0003): keeping headings with what
follows, widow and orphan boundaries, forced page breaks at the page
end, the fixed point of page references (S2), and invariants of
'paginate' as properties.

The footnote separator is changing (golem-driver ADR 0024), so these
tests assert on which page a note is, never on how many lines its
separator takes.
-}
module PaginateSpec (paginateTests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry (..))
import Golem.Layout.Paginate
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

paginateTests :: TestTree
paginateTests =
  testGroup
    "pagination boundaries (golem-layout ADR 0003)"
    [ testGroup "a heading kept with what follows" keepWithNextTests,
      testGroup "a heading with footnotes (golem-driver ADR 0003)" headingNoteTests,
      testGroup "widows, orphans and the page end" widowOrphanTests,
      testGroup "page references that do not settle (S2)" pageRefTests,
      testGroup "figures in the order written (golem-layout ADR 0015)" figureOrderTests,
      testGroup "turned figures on pages of their own (golem-driver ADR 0034)" pageFigureTests,
      testGroup "manual control of page breaks (docs/adr ADR 0030)" pageControlTests,
      testGroup "blank lines (docs/adr ADR 0046)" blankLineTests,
      testGroup "paragraphs and headings with rules (golem-driver ADR 0027)" ruledTests,
      testGroup "invariants" propertyTests
    ]

-- | n plain lines numbered from base.
lines' :: Int -> Int -> [LineBox]
lines' base n = [LineBox (base + i) [] [] [] 0 | i <- [0 .. n - 1]]

-- | A heading of one line, on one grid line, not at a recto.
heading :: Int -> Flow
heading i = FHeading 2 False 1 (lines' i 1)

-- | What starts on each page, in order.
contents :: [PageOut] -> [[Slotted]]
contents = map (map snd . poSlots)

{- | Code on a grid of pitch 10 with rows of pitch 10 and size 10 and a
padding of 5 above and below: k rows take 10k + 10, so k + 1 grid lines.
-}
paddedCode :: CodeGeometry
paddedCode = CodeGeometry 10 10 10 10 5

keepWithNextTests :: [TestTree]
keepWithNextTests =
  [ testCase "a heading goes to the next page when the figure after it does not fit after it" $ do
      -- 3 lines used, 2 free: heading 1 + figure 2 = 3 > 2
      let ps = paginate 1 5 [FParagraph (lines' 0 3), heading 20, FFigure 99 2 [] []]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SFigure 99]],
    testCase "a heading stays at the page end when the figure after it fits after it" $ do
      -- 2 free: heading 1 + figure 1 = 2
      let ps = paginate 1 5 [FParagraph (lines' 0 3), heading 20, FFigure 99 1 [] []]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SHeading 20 1, SFigure 99]],
    testCase "a heading before a table keeps the header and the first row, not only the header" $ do
      -- 3 free: heading 1 + header 1 + first row 2 = 4 > 3
      let ps = paginate 1 6 [FParagraph (lines' 0 3), heading 20, FTable 100 0 (lines' 30 1) [lines' 40 2]]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 30, SLine 40, SLine 41]],
    testCase "a heading before a code block keeps the grid lines of its first row with padding" $ do
      -- 2 free: heading 1 + one row with padding 2 = 3 > 2; three rows take 4 lines
      let ps = paginate 1 5 [FParagraph (lines' 0 3), heading 20, FCode paddedCode 0 1 False (lines' 30 3)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SCode 30 3 4]],
    testCase "a heading stays when the first row of the code block after it fits; the rest goes on" $ do
      -- 3 free: heading 1 + one row 2 = 3; the other two rows take 3 lines on page 2
      let ps = paginate 1 6 [FParagraph (lines' 0 3), heading 20, FCode paddedCode 0 1 False (lines' 30 3)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SHeading 20 1, SCode 30 1 2], [SCode 31 2 3]],
    testCase "a heading before a heading of two grid lines counts that span" $ do
      -- 2 free: heading 1 + the next heading's span 2 = 3 > 2
      let ps = paginate 1 5 [FParagraph (lines' 0 3), heading 20, FHeading 3 False 2 (lines' 25 1), FParagraph (lines' 30 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SHeading 25 1, SLine 30, SLine 31]],
    testCase "a definition term before a code block keeps its first row" $ do
      -- 2 free: term 1 + one row 2 = 3 > 2
      let ps = paginate 1 5 [FParagraph (lines' 0 3), FDefTerm (lines' 20 1), FCode paddedCode 0 1 False (lines' 30 1)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SLine 20, SCode 30 1 2]]
  ]

-- | The ids of the notes on each page.
notesByPage :: [PageOut] -> [(Int, [NoteId])]
notesByPage ps = [(poNumber p, [i | (i, _, _) <- poFootnotes p]) | p <- ps]

-- | A heading of one line whose line has a footnote of one line.
headingWithNote :: Int -> NoteId -> Flow
headingWithNote i note = FHeading 2 False 1 [LineBox i [NoteBody note 1] [] [] 0]

-- | The note of the marker at offset k of a source file.
nid :: Int -> NoteId
nid k = NoteId (mkSpan (FileId 0) k (k + 1)) 0

headingNoteTests :: [TestTree]
headingNoteTests =
  [ testCase "the note of a heading is on the page of the heading" $ do
      let ps = paginate 1 8 [headingWithNote 20 (nid 900), FParagraph (lines' 30 2)]
      notesByPage ps @?= [(1, [nid 900])],
    testCase "a heading sent to the next page takes its note with it" $ do
      -- 2 free after six lines: heading 1 + two lines = 3 > 2
      let ps = paginate 1 8 [FParagraph (lines' 0 6), headingWithNote 20 (nid 900), FParagraph (lines' 30 2)]
      notesByPage ps @?= [(1, []), (2, [nid 900])],
    testCase "a heading whose note does not fit goes to the next page with its note (golem-layout ADR 0013)" $ do
      let ps = paginate 1 8 [FParagraph (lines' 0 5), FHeading 2 False 1 [LineBox 20 [NoteBody (nid 900) 3] [] [] 0], FParagraph (lines' 30 2)]
      notesByPage ps @?= [(1, []), (2, [nid 900])]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 3, SLine 4], [SHeading 20 1, SLine 30, SLine 31]],
    testCase "the note of a heading counts in keeping it with what follows (golem-layout ADR 0013)" $ do
      -- 3 free: heading 1 + note 1 + separator, then no room for two lines
      let ps = paginate 1 8 [FParagraph (lines' 0 5), headingWithNote 20 (nid 900), FParagraph (lines' 30 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 3, SLine 4], [SHeading 20 1, SLine 30, SLine 31]]
      notesByPage ps @?= [(1, []), (2, [nid 900])],
    testCase "a heading whose note fits stays on the page" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 2), headingWithNote 20 (nid 900), FParagraph (lines' 30 2)]
      notesByPage ps @?= [(1, [nid 900])],
    testCase "a heading in an empty page keeps its place and its note continues on the next page" $ do
      let ps = paginate 1 5 [FHeading 2 False 1 [LineBox 20 [NoteBody (nid 900) 6] [] [] 0]]
      notesByPage ps @?= [(1, [nid 900]), (2, [nid 900])]
      contents ps @?= [[SHeading 20 1], []],
    testCase "in two columns, a heading whose note does not fit goes to the next column (golem-layout ADR 0013)" $ do
      let ps = paginate 2 8 [FParagraph (lines' 0 5), FHeading 2 False 1 [LineBox 20 [NoteBody (nid 900) 3] [] [] 0], FParagraph (lines' 30 2)]
      [(poNumber p, poColumn p, [i | (i, _, _) <- poFootnotes p]) | p <- ps] @?= [(1, 0, []), (1, 1, [nid 900])]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 3, SLine 4], [SHeading 20 1, SLine 30, SLine 31]],
    testCase "a heading on a page that has notes counts no second separator for its note (golem-layout ADR 0013)" $ do
      -- separator 1: three lines, the separator and a note take 5 of 9; heading 1 + its note 1 + two lines = 4 fit
      let ps = paginateIn 1 (ColumnSet 1 0 0 0) 9 [FParagraph (LineBox 0 [NoteBody (nid 800) 1] [] [] 0 : lines' 1 2), headingWithNote 20 (nid 900), FParagraph (lines' 30 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SHeading 20 1, SLine 30, SLine 31]]
      notesByPage ps @?= [(1, [nid 800, nid 900])],
    testCase "the label of a heading sent to the next page is on that page" $ do
      let ps = paginate 1 5 [FParagraph (lines' 0 3), FHeading 2 False 1 [LineBox 20 [] ["sec"] [] 0], FParagraph (lines' 30 2)]
      labelPages ps @?= Map.fromList [("sec", 2)]
  ]

-- | The line ids on each page.
lineIds :: [PageOut] -> [[Int]]
lineIds = map (\p -> [i | (_, SLine i) <- poSlots p])

widowOrphanTests :: [TestTree]
widowOrphanTests =
  [ testCase "a two-line paragraph with one line left goes whole to the next page" $
      lineIds (paginate 1 5 [FParagraph (lines' 0 4), FParagraph (lines' 10 2)]) @?= [[0, 1, 2, 3], [10, 11]],
    testCase "a three-line paragraph with two lines left goes whole: no widow, then no orphan" $
      lineIds (paginate 1 5 [FParagraph (lines' 0 3), FParagraph (lines' 10 3)]) @?= [[0, 1, 2], [10, 11, 12]],
    testCase "a five-line paragraph with four lines left leaves two for the next page, not one" $
      lineIds (paginate 1 5 [FParagraph (lines' 0 1), FParagraph (lines' 10 5)]) @?= [[0, 10, 11, 12], [13, 14]],
    testCase "a three-line paragraph with one line left goes whole to the next page" $
      lineIds (paginate 1 5 [FParagraph (lines' 0 4), FParagraph (lines' 10 3)]) @?= [[0, 1, 2, 3], [10, 11, 12]],
    testCase "a four-line paragraph with two lines left is split two and two" $
      lineIds (paginate 1 5 [FParagraph (lines' 0 3), FParagraph (lines' 10 4)]) @?= [[0, 1, 2, 10, 11], [12, 13]],
    testCase "a one-line paragraph takes the last line of the page" $
      lineIds (paginate 1 5 [FParagraph (lines' 0 4), FParagraph (lines' 10 1)]) @?= [[0, 1, 2, 3, 10]],
    testCase "a paragraph that fills the page exactly makes one page" $
      lineIds (paginate 1 5 [FParagraph (lines' 0 5)]) @?= [[0, 1, 2, 3, 4]],
    testCase "on pages of one line the widow and orphan rules give way" $
      lineIds (paginate 1 1 [FParagraph (lines' 0 2)]) @?= [[0], [1]],
    testCase "a page break right after a full page adds no blank page" $ do
      let ps = paginate 1 5 [FParagraph (lines' 0 5), FBreak BreakPage, FParagraph (lines' 10 1)]
      map poBlank ps @?= [False, False]
      lineIds ps @?= [[0, 1, 2, 3, 4], [10]],
    testCase "a figure that takes exactly the lines left stays on the page" $
      contents (paginate 1 5 [FParagraph (lines' 0 3), FFigure 99 2 [] []]) @?= [[SLine 0, SLine 1, SLine 2, SFigure 99]],
    testCase "two figures sent on that do not fit one page together go to successive pages" $ do
      -- 2 free on page 1: both figures of 3 lines are sent on, the text moves up
      let ps = paginate 1 5 [FParagraph (lines' 0 3), FFigure 98 3 [] [], FFigure 99 3 [] [], FParagraph (lines' 10 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 10, SLine 11], [SFigure 98], [SFigure 99]]
  ]

pageFigureTests :: [TestTree]
pageFigureTests =
  [ testCase "a turned figure in the middle of the text: the text fills the page, the figure takes the next one" $ do
      let ps = paginate 1 5 [FParagraph (lines' 0 3), FPageFigure 50 ["f"] [], FParagraph (lines' 10 4)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 10, SLine 11], [SPageFigure 50], [SLine 12, SLine 13]]
      labelPages ps @?= Map.fromList [("f", 2)],
    testCase "a turned figure met on an empty page takes that page" $
      contents (paginate 1 5 [FPageFigure 50 [] [], FParagraph (lines' 0 2)]) @?= [[SPageFigure 50], [SLine 0, SLine 1]],
    testCase "a figure after a turned figure waits even when it fits, and goes to the page after it" $
      contents (paginate 1 5 [FParagraph (lines' 0 2), FPageFigure 50 [] [], FFigure 60 1 [] [], FParagraph (lines' 10 2)])
        @?= [[SLine 0, SLine 1, SLine 10, SLine 11], [SPageFigure 50], [SFigure 60]],
    testCase "a waiting turned figure is placed before a forced page break" $
      contents (paginate 1 5 [FParagraph (lines' 0 2), FPageFigure 50 [] [], FBreak BreakPage, FParagraph (lines' 10 1)])
        @?= [[SLine 0, SLine 1], [SPageFigure 50], [SLine 10]],
    testCase "a waiting turned figure is placed before a column break" $
      [(poNumber p, poColumn p, map snd (poSlots p)) | p <- paginate 2 5 [FParagraph (lines' 0 2), FPageFigure 50 [] [], FBreak BreakColumn, FParagraph (lines' 10 1)]]
        @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SPageFigure 50]), (3, 0, [SLine 10])],
    testCase "a column break with only an unturned figure waiting goes to the next column (golem-driver ADR 0039)" $
      [(poNumber p, poColumn p, map snd (poSlots p)) | p <- paginate 2 5 [FParagraph (lines' 0 4), FFigure 60 3 [] [], FBreak BreakColumn, FParagraph (lines' 10 1)]]
        @?= [(1, 0, [SLine 0, SLine 1, SLine 2, SLine 3]), (1, 1, [SFigure 60, SLine 10])],
    testCase "a page break right after a turned figure met on an empty page adds no blank page (golem-driver ADR 0039)" $ do
      let ps = paginate 1 5 [FPageFigure 50 [] [], FBreak BreakPage, FParagraph (lines' 10 1)]
      contents ps @?= [[SPageFigure 50], [SLine 10]]
      map poBlank ps @?= [False, False],
    testCase "two or three page breaks after a waiting turned figure add no blank page (golem-driver ADR 0039)" $ do
      let flows k = [FParagraph (lines' 0 2), FPageFigure 50 [] []] <> replicate k (FBreak BreakPage) <> [FParagraph (lines' 10 1)]
      mapM_
        ( \k -> do
            let ps = paginate 1 5 (flows k)
            contents ps @?= [[SLine 0, SLine 1], [SPageFigure 50], [SLine 10]]
            any poBlank ps @?= False
        )
        [2, 3],
    testCase "a recto break after a turned figure on page 1 makes page 2 blank (golem-driver ADR 0039)" $ do
      let ps = paginate 1 5 [FPageFigure 50 [] [], FBreak BreakRecto, FParagraph (lines' 10 1)]
      [(poNumber p, poBlank p, map snd (poSlots p)) | p <- ps] @?= [(1, False, [SPageFigure 50]), (2, True, []), (3, False, [SLine 10])],
    testCase "a verso break after a turned figure on page 2 makes page 3 blank (golem-driver ADR 0039)" $ do
      let ps = paginate 1 5 [FParagraph (lines' 0 1), FPageFigure 50 [] [], FBreak BreakVerso, FParagraph (lines' 10 1)]
      [(poNumber p, poBlank p, map snd (poSlots p)) | p <- ps]
        @?= [(1, False, [SLine 0]), (2, False, [SPageFigure 50]), (3, True, []), (4, False, [SLine 10])],
    testCase "a page break on an empty first page without a turned figure still makes a blank page (golem-driver ADR 0039)" $ do
      let ps = paginate 1 5 [FBreak BreakPage, FParagraph (lines' 10 1)]
      map poBlank ps @?= [True, False]
      contents ps @?= [[], [SLine 10]],
    testCase "a waiting turned figure is placed before a heading at a recto" $ do
      let ps = paginate 1 5 [FParagraph (lines' 0 2), FPageFigure 50 [] [], FParagraph (lines' 10 1), FHeading 1 True 1 (lines' 20 1)]
      [(poNumber p, map snd (poSlots p)) | p <- ps, not (poBlank p)] @?= [(1, [SLine 0, SLine 1, SLine 10]), (2, [SPageFigure 50]), (3, [SHeading 20 1])],
    testCase "a footnote continued from the page before skips the page of a turned figure" $ do
      let ps = paginate 1 5 [FParagraph [LineBox 0 [NoteBody (nid 900) 5] [] [] 0], FPageFigure 50 [] [], FParagraph (lines' 10 2)]
      contents ps @?= [[SLine 0], [SPageFigure 50], [SLine 10, SLine 11]]
      notesByPage ps @?= [(1, [nid 900]), (2, []), (3, [nid 900])]
  ]

{- | The label "x" on the last of k one-line pages before it, where k is
the page assumed for "x" capped at cap: the page of "x" is k + 1.
-}
creeping :: Integer -> Map.Map Text Integer -> [PageOut]
creeping cap assumed =
  let k = fromInteger (min cap (Map.findWithDefault 0 "x" assumed))
   in paginate 1 1 ([FParagraph [LineBox i [] [] [] 0] | i <- [0 .. k - 1]] <> [FParagraph [LineBox 999 [] ["x"] [] 0]])

pageRefTests :: [TestTree]
pageRefTests =
  [ testCase "a label that settles in the fifth round is resolved" $
      -- x moves 1, 2, 3, 4 and stays at 4 in round 5
      fmap labelPages (resolvePageRefs (creeping 3)) @?= Right (Map.fromList [("x", 4)]),
    testCase "a label still moving after the fifth round is named" $
      -- x moves 1, 2, 3, 4, 5
      resolvePageRefs (creeping 4) @?= Left ["x"],
    testCase "only the labels whose pages still move are named, in the order of their names" $ do
      -- "stable" fills page 1; "b" and "a" jump between page 11 and page 3
      let layout assumed =
            let fillers = if Map.findWithDefault 1 "a" assumed < 10 then 9 else 1
             in paginate 1 5 $
                  FParagraph (LineBox 0 [] ["stable"] [] 0 : lines' 1 4)
                    : replicate fillers (FParagraph (lines' 10 5))
                      <> [FParagraph [LineBox 999 [] ["b", "a"] [] 0]]
      resolvePageRefs layout @?= Left ["a", "b"]
  ]

-- | A block of the generated flows: a paragraph of n lines, or a heading of one line and a span.
data Block = Para !Int | Head !Int
  deriving stock (Show)

genBlocks :: Gen [Block]
genBlocks = Gen.list (Range.linear 1 30) (Gen.choice [Para <$> Gen.int (Range.linear 1 7), Head <$> Gen.int (Range.linear 1 2)])

-- | The flows of the blocks with their lines numbered in order from 0.
flowsOf :: [Block] -> [Flow]
flowsOf = go 0
  where
    go _ [] = []
    go i (Para n : rest) = FParagraph (lines' i n) : go (i + n) rest
    go i (Head s : rest) = FHeading 2 False s (lines' i 1) : go (i + 1) rest

-- | The lines of the blocks.
lineCount :: [Block] -> Int
lineCount = sum . map (\case Para n -> n; Head _ -> 1)

-- | Every line id in the output, page by page, slot by slot.
placedIds :: [PageOut] -> [Int]
placedIds ps =
  [ i
  | p <- ps,
    (_, s) <- poSlots p,
    i <- case s of
      SLine l -> [l]
      SHeading l m -> [l .. l + m - 1]
      _ -> []
  ]

-- | The span of a marker.
mk :: SrcSpan
mk = mkSpan (FileId 0) 0 1

-- | The span of another marker.
mk2 :: SrcSpan
mk2 = mkSpan (FileId 0) 5 6

-- | The unmet controls of all columns.
unmets :: [PageOut] -> [Unmet]
unmets = concatMap poUnmet

-- | Page, column and line ids of each column.
columnsOf :: [PageOut] -> [(Int, Int, [Int])]
columnsOf ps = [(poNumber p, poColumn p, [i | (_, SLine i) <- poSlots p]) | p <- ps]

pageControlTests :: [TestTree]
pageControlTests =
  [ testCase "no-break: the last two lines go on with the paragraph after" $ do
      lineIds (paginate 1 10 [FParagraph (lines' 0 9), FParagraph (lines' 10 5)]) @?= [[0 .. 8], [10 .. 14]]
      let ps = paginate 1 10 [FParagraph (lines' 0 9), FNoBreak mk, FParagraph (lines' 10 5)]
      lineIds ps @?= [[0 .. 6], [7, 8, 10, 11, 12, 13, 14]]
      unmets ps @?= [],
    testCase "no-break: a paragraph of two lines, or of three, goes whole" $ do
      lineIds (paginate 1 10 [FParagraph (lines' 0 7), FParagraph (lines' 20 2), FNoBreak mk, FParagraph (lines' 30 5)])
        @?= [[0 .. 6], [20, 21, 30, 31, 32, 33, 34]]
      lineIds (paginate 1 10 [FParagraph (lines' 0 6), FParagraph (lines' 20 3), FNoBreak mk, FParagraph (lines' 30 5)])
        @?= [[0 .. 5], [20, 21, 22, 30, 31, 32, 33, 34]],
    testCase "no-break: nothing is sent from an empty column, and the control is unmet" $ do
      let ps = paginate 1 3 [FParagraph (lines' 0 3), FNoBreak mk, FParagraph (lines' 10 5)]
      lineIds ps @?= [[0, 1, 2], [10, 11, 12], [13, 14]]
      unmets ps @?= [UnmetNoBreak mk],
    testCase "no-break after a figure sent on is unmet" $
      unmets (paginate 1 5 [FParagraph (lines' 0 4), FFigure 99 3 [] [], FNoBreak mk, FParagraph (lines' 10 2)]) @?= [UnmetNoBreak mk],
    testCase "the controls after a heading do not change keeping it with what follows" $ do
      let plain = [FParagraph (lines' 0 3), heading 20, FParagraph (lines' 30 2)]
          marked = [FParagraph (lines' 0 3), heading 20, FNeedLines mk 1, FNoBreak mk, FParagraph (lines' 30 2)]
      contents (paginate 1 5 marked) @?= contents (paginate 1 5 plain)
      unmets (paginate 1 5 marked) @?= [],
    testCase "need-lines goes to the next column only when the column is short" $ do
      lineIds (paginate 1 10 [FParagraph (lines' 0 6), FNeedLines mk 5, FParagraph (lines' 10 2)]) @?= [[0 .. 5], [10, 11]]
      lineIds (paginate 1 10 [FParagraph (lines' 0 6), FNeedLines mk 4, FParagraph (lines' 10 2)]) @?= [[0, 1, 2, 3, 4, 5, 10, 11]]
      lineIds (paginate 1 10 [FNeedLines mk 5, FParagraph (lines' 0 2)]) @?= [[0, 1]],
    testCase "need-lines in two columns goes to the next column" $
      columnsOf (paginate 2 10 [FParagraph (lines' 0 6), FNeedLines mk 5, FParagraph (lines' 10 2)]) @?= [(1, 0, [0 .. 5]), (1, 1, [10, 11])],
    testCase "need-lines beyond the column is unmet and goes to the next column" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 6), FNeedLines mk 20, FParagraph (lines' 10 2)]
      lineIds ps @?= [[0 .. 5], [10, 11]]
      unmets ps @?= [UnmetNeedLines mk 20],
    testCase "controls at the end of the book make no page; the last no-break is unmet" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 2), FNeedLines mk 3, FNoBreak mk]
      lineIds ps @?= [[0, 1]]
      unmets ps @?= [UnmetNoBreak mk],
    testCase "page-lines +1 gives the column one more line, and the next column its own" $ do
      let ps = paginate 1 10 [FAdjustLines mk 1, FParagraph (lines' 0 11), FParagraph (lines' 20 3)]
      lineIds ps @?= [[0 .. 10], [20, 21, 22]]
      map poLines ps @?= [11, 10]
      unmets ps @?= [],
    testCase "page-lines -1 leaves the column a line short" $ do
      let ps = paginate 1 10 [FAdjustLines mk (-1), FParagraph (lines' 0 12)]
      lineIds ps @?= [[0 .. 8], [9, 10, 11]]
      map poLines ps @?= [9, 10],
    testCase "page-lines beyond the limit is cut to it and unmet" $ do
      let ps = paginateWithin 11 1 (ColumnSet 1 0 0 0) 10 [FAdjustLines mk 1, FAdjustLines mk 1, FParagraph (lines' 0 12)]
      map poLines ps @?= [11, 10]
      unmets ps @?= [UnmetAdjust mk 1],
    testCase "page-lines below the lines placed is cut to them and unmet" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 8), FAdjustLines mk (-5), FParagraph (lines' 10 2)]
      lineIds ps @?= [[0 .. 7], [10, 11]]
      map poLines ps @?= [8, 10]
      unmets ps @?= [UnmetAdjust mk (-2)],
    testCase "the footnotes of a column of page-lines +1 use its last line" $ do
      -- nine lines, the separator and a note of one line take eleven lines
      let flow = [FAdjustLines mk 1, FParagraph (LineBox 0 [NoteBody (nid 900) 1] [] [] 0 : lines' 1 8)]
          ps = paginate 1 10 flow
      map poLines ps @?= [11]
      notesByPage ps @?= [(1, [nid 900])]
      lineIds ps @?= [[0 .. 8]],
    testCase "no-break at the start of the book has nothing before it and is unmet" $
      unmets (paginate 1 10 [FNoBreak mk, FParagraph (lines' 0 2)]) @?= [UnmetNoBreak mk],
    testCase "no-break before a figure that waits behind one sent on is unmet" $ do
      -- 2 free: figure 98 of 4 lines is sent on, the line moves up, figure 99 waits behind 98
      let ps = paginate 1 5 [FParagraph (lines' 0 3), FFigure 98 4 [] [], FParagraph (lines' 10 1), FNoBreak mk, FFigure 99 1 [] []]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 10], [SFigure 98, SFigure 99]]
      unmets ps @?= [UnmetNoBreak mk],
    testCase "no-break keeps the last lines with what follows across need-lines and a space before it" $ do
      lineIds (paginate 1 10 [FParagraph (lines' 0 9), FNeedLines mk 1, FNoBreak mk, FParagraph (lines' 10 5)]) @?= [[0 .. 6], [7, 8, 10, 11, 12, 13, 14]]
      lineIds (paginate 1 10 [FParagraph (lines' 0 9), FSpace 1, FNoBreak mk, FParagraph (lines' 10 5)]) @?= [[0 .. 6], [7, 8, 10, 11, 12, 13, 14]],
    testCase "page-lines after a heading does not change keeping it with what follows" $
      -- 2 free: heading 1 + two lines = 3 > 2, as without page-lines
      contents (paginate 1 5 [FParagraph (lines' 0 3), heading 20, FAdjustLines mk 1, FParagraph (lines' 30 2)])
        @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 30, SLine 31]],
    testCase "of two need-lines in a row the larger applies" $ do
      -- 4 free: 3 would stay, 5 goes to the next column, whichever comes first
      lineIds (paginate 1 10 [FParagraph (lines' 0 6), FNeedLines mk 3, FNeedLines mk2 5, FParagraph (lines' 10 2)]) @?= [[0 .. 5], [10, 11]]
      lineIds (paginate 1 10 [FParagraph (lines' 0 6), FNeedLines mk2 5, FNeedLines mk 3, FParagraph (lines' 10 2)]) @?= [[0 .. 5], [10, 11]],
    testCase "need-lines of exactly the lines of a column is met" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 6), FNeedLines mk 10, FParagraph (lines' 10 2)]
      lineIds ps @?= [[0 .. 5], [10, 11]]
      unmets ps @?= [],
    testCase "page-lines leaves a column at least one line" $ do
      let ps = paginate 1 10 [FAdjustLines mk (-10), FParagraph (lines' 0 3)]
      take 1 (map poLines ps) @?= [1]
      unmets ps @?= [UnmetAdjust mk (-9)]
  ]

-- | On one column of ten grid lines (docs/adr ADR 0046).
blankLineTests :: [TestTree]
blankLineTests =
  [ testCase "blank lines take grid lines before what follows" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 3), FBlank mk 2, FParagraph (lines' 10 2)]
      gridLines ps @?= [[0, 1, 2, 5, 6]]
      unmets ps @?= [],
    testCase "blank lines and the first part of what follows go to the next column together, and the blank lines are dropped there" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 9), FBlank mk 1, FParagraph (lines' 10 3)]
      lineIds ps @?= [[0 .. 8], [10, 11, 12]]
      gridLines ps @?= [[0 .. 8], [0, 1, 2]]
      unmets ps @?= [DroppedBlank mk],
    testCase "blank lines after a full column are dropped" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 10), FBlank mk 1, FParagraph (lines' 10 2)]
      gridLines ps @?= [[0 .. 9], [0, 1]]
      unmets ps @?= [DroppedBlank mk],
    testCase "blank lines after a page break are dropped" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 2), FBreak BreakPage, FBlank mk 3, FParagraph (lines' 10 2)]
      gridLines ps @?= [[0, 1], [0, 1]]
      unmets ps @?= [DroppedBlank mk],
    testCase "blank lines at the start of the book are dropped" $ do
      let ps = paginate 1 10 [FBlank mk 2, FParagraph (lines' 0 2)]
      gridLines ps @?= [[0, 1]]
      unmets ps @?= [DroppedBlank mk],
    testCase "each blank line dropped is recorded" $
      unmets (paginate 1 10 [FBlank mk 1, FBlank mk2 2, FParagraph (lines' 0 2)]) @?= [DroppedBlank mk, DroppedBlank mk2],
    testCase "blank lines longer than the rest of the column are dropped whole, not cut" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 3), FBlank mk 20, FParagraph (lines' 10 2)]
      gridLines ps @?= [[0, 1, 2], [0, 1]]
      unmets ps @?= [DroppedBlank mk],
    testCase "blank lines before a heading that starts at a recto are dropped at the recto" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 3), FBlank mk 2, FHeading 1 True 1 (lines' 20 1), FParagraph (lines' 30 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [], [SHeading 20 1, SLine 30, SLine 31]]
      map poBlank ps @?= [False, True, False]
      gridLines ps @?= [[0, 1, 2], [], [0, 1, 2]]
      unmets ps @?= [DroppedBlank mk],
    testCase "a heading is kept with the blank lines and the first two lines after it" $ do
      gridLines (paginate 1 10 [FParagraph (lines' 0 5), heading 20, FBlank mk 2, FParagraph (lines' 30 2)]) @?= [[0, 1, 2, 3, 4, 5, 8, 9]]
      let ps = paginate 1 10 [FParagraph (lines' 0 6), heading 20, FBlank mk 2, FParagraph (lines' 30 2)]
      gridLines ps @?= [[0 .. 5], [0, 3, 4]]
      unmets ps @?= [],
    testCase "a no-break keeps the last lines, the blank lines and the first lines after it together" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 9), FNoBreak mk, FBlank mk2 1, FParagraph (lines' 10 5)]
      lineIds ps @?= [[0 .. 6], [7, 8, 10, 11, 12, 13, 14]]
      gridLines ps @?= [[0 .. 6], [0, 1, 3, 4, 5, 6, 7]]
      unmets ps @?= [],
    testCase "a table after blank lines keeps its space before" $ do
      let ps = paginate 1 10 [FParagraph (lines' 0 2), FBlank mk 1, FTable 50 1 [] [lines' 30 1]]
      map (map tsFirst . poTables) ps @?= [[4]]
  ]

figureOrderTests :: [TestTree]
figureOrderTests =
  [ testCase "a figure after a figure sent on is sent on after it" $ do
      let ps = paginate 1 5 [FParagraph (lines' 0 3), FFigure 98 3 [] [], FParagraph (lines' 10 1), FFigure 99 1 [] []]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 10], [SFigure 98, SFigure 99]],
    testCase "in two columns, a figure after a figure sent on goes to the next column after it" $ do
      let ps = paginate 2 5 [FParagraph (lines' 0 3), FFigure 98 3 [] [], FParagraph (lines' 10 1), FFigure 99 1 [] []]
      [(poNumber p, poColumn p, map snd (poSlots p)) | p <- ps]
        @?= [(1, 0, [SLine 0, SLine 1, SLine 2, SLine 10]), (1, 1, [SFigure 98, SFigure 99])],
    testCase "a wrapped figure after a figure sent on goes with its lines after it" $ do
      let ps = paginate 1 6 [FParagraph (lines' 0 3), FFigure 98 4 [] [], FWrapped 99 2 [] [] (lines' 10 2), FParagraph (lines' 20 1)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SFigure 98, SWrapped 99, SLine 10, SLine 11], [SLine 20]]
  ]

-- | A block of the generated flows with figures: a paragraph, a figure of n lines, or a wrapped figure of n lines with k lines beside it.
data FigBlock = FPara !Int | FFig !Int | FWrap !Int !Int
  deriving stock (Show)

genFigBlocks :: Gen [FigBlock]
genFigBlocks =
  Gen.list
    (Range.linear 1 30)
    ( Gen.choice
        [ FPara <$> Gen.int (Range.linear 1 7),
          FFig <$> Gen.int (Range.linear 1 6),
          do
            n <- Gen.int (Range.linear 1 4)
            FWrap n <$> Gen.int (Range.linear 1 n)
        ]
    )

{- | The flows of the blocks: lines numbered in order from 0, figures
numbered in order from 1000.
-}
figFlowsOf :: [FigBlock] -> [Flow]
figFlowsOf = go 0 1000
  where
    go _ _ [] = []
    go i j (FPara n : rest) = FParagraph (lines' i n) : go (i + n) j rest
    go i j (FFig n : rest) = FFigure j n [] [] : go i (j + 1) rest
    go i j (FWrap n k : rest) = FWrapped j n [] [] (lines' i k) : go (i + k) (j + 1) rest

-- | The figures in the output, column by column, slot by slot.
placedFigures :: [PageOut] -> [Int]
placedFigures ps = [i | p <- ps, (_, s) <- poSlots p, i <- case s of SFigure f -> [f]; SWrapped f -> [f]; _ -> []]

figBlockLines :: [FigBlock] -> Int
figBlockLines = sum . map (\case FPara n -> n; FWrap _ k -> k; FFig _ -> 0)

figBlockFigures :: [FigBlock] -> Int
figBlockFigures = length . filter (\case FPara _ -> False; _ -> True)

propertyTests :: [TestTree]
propertyTests =
  [ testProperty "figures and wrapped figures are placed in the order written (golem-layout ADR 0015)" $ property $ do
      blocks <- forAll genFigBlocks
      capacity <- forAll (Gen.int (Range.linear 2 9))
      columns <- forAll (Gen.int (Range.linear 1 2))
      placedFigures (paginate columns capacity (figFlowsOf blocks)) === [1000 .. 1000 + figBlockFigures blocks - 1],
    testProperty "every line and every figure is placed exactly once" $ property $ do
      blocks <- forAll genFigBlocks
      capacity <- forAll (Gen.int (Range.linear 2 9))
      columns <- forAll (Gen.int (Range.linear 1 2))
      let ps = paginate columns capacity (figFlowsOf blocks)
      placedIds ps === [0 .. figBlockLines blocks - 1]
      length (placedFigures ps) === figBlockFigures blocks,
    testProperty "every line of paragraphs and headings is placed once, in the order written" $ property $ do
      blocks <- forAll genBlocks
      capacity <- forAll (Gen.int (Range.linear 2 9))
      placedIds (paginate 1 capacity (flowsOf blocks)) === [0 .. lineCount blocks - 1],
    testProperty "pages are numbered from 1 without gaps" $ property $ do
      blocks <- forAll genBlocks
      capacity <- forAll (Gen.int (Range.linear 2 9))
      let ps = paginate 1 capacity (flowsOf blocks)
      map poNumber ps === [1 .. length ps],
    testProperty "every slot starts on a grid line of the page" $ property $ do
      blocks <- forAll genBlocks
      capacity <- forAll (Gen.int (Range.linear 2 9))
      let starts = [k | p <- paginate 1 capacity (flowsOf blocks), (k, _) <- poSlots p]
      filter (\k -> k < 0 || k >= capacity) starts === [],
    -- the bounds of the starts alone pass when a heading of two grid lines
    -- starts on the last one, or when two slots share a grid line
    testProperty "the slots of a page do not overlap and end within the page" $ property $ do
      blocks <- forAll genBlocks
      capacity <- forAll (Gen.int (Range.linear 2 9))
      let spans = Map.fromList (headingSpans 0 blocks)
          extent = \case
            SHeading l _ -> Map.findWithDefault 1 l spans
            _ -> 1
      mapM_
        ( \p -> do
            let slots = [(k, k + extent s) | (k, s) <- poSlots p]
            annotateShow (poNumber p, slots)
            -- each slot starts at or after the end of the one before it
            and (zipWith (\(_, e) (k, _) -> e <= k) slots (drop 1 slots)) === True
            filter (\(_, e) -> e > capacity) slots === []
        )
        (paginate 1 capacity (flowsOf blocks))
  ]
  where
    -- the grid lines each heading takes, by the id of its line
    headingSpans :: Int -> [Block] -> [(Int, Int)]
    headingSpans _ [] = []
    headingSpans i (Para n : rest) = headingSpans (i + n) rest
    headingSpans i (Head k : rest) = (i, k) : headingSpans (i + 1) rest

-- | Size 10pt, pitch 17pt, in sp.
ruleGrid :: RuleGrid
ruleGrid = RuleGrid (17 * 65536) (10 * 65536)

-- | A rule of 0.5pt with an inner and an outer space in pt.
spaced :: Integer -> Integer -> RuleSide
spaced i o = RuleSide (i * 65536) (o * 65536) 32768 True Nothing

-- | A rule of 0.3pt without spaces: no grid line inside a column.
bare :: RuleSide
bare = RuleSide 0 0 19661 False Nothing

-- | A paragraph with rules: its id is that of its first line.
ruled :: Maybe RuleSide -> Maybe RuleSide -> [LineBox] -> Flow
ruled b a ls = FRuled (maybe 0 lbId (listToMaybe' ls)) b a False ruleGrid 0 (RuledLines ls)
  where
    listToMaybe' = foldr (const . Just) Nothing

-- | The slots of each page.
gridLines :: [PageOut] -> [[Int]]
gridLines = map (map fst . poSlots)

ruledTests :: [TestTree]
ruledTests =
  [ testCase "keep-in-column = false at the start of columns that start mid-page: in the column, as keep-in-column = true (golem-driver ADR 0040)" $ do
      let outside = (spaced 5 10) {rsdOutside = Just (100 * 65536)}
          flows b = [FParagraph (lines' 0 2), FSwitchColumns (ColumnSet 2 0 0 0), ruled (Just b) Nothing (lines' 10 1)]
          inside = paginateIn 1 (ColumnSet 1 0 0 0) 10 (flows (spaced 5 10))
          out = paginateIn 1 (ColumnSet 1 0 0 0) 10 (flows outside)
      map poRules out @?= map poRules inside
      gridLines out @?= gridLines inside
      -- the area of the rule takes a grid line after the two lines before
      gridLines out @?= [[0, 1], [3]],
    testCase "a ruled paragraph that does not fit goes whole to the next column, its rule counted at the start" $ do
      -- 3 free; a line of area before (inner 5pt, outer 10pt) and 3 lines
      let ps = paginate 1 5 [FParagraph (lines' 0 2), ruled (Just (spaced 5 10)) Nothing (lines' 10 3)]
      gridLines ps @?= [[0, 1], [1, 2, 3]]
      map poRules ps @?= [[], [PlacedRule 10 True (17 * 65536 - 5 * 65536 - 32768)]],
    testCase "a paragraph is split at the column end, a ruled one is not" $ do
      gridLines (paginate 1 8 [FParagraph (lines' 0 4), FParagraph (lines' 10 6)]) @?= [[0 .. 7], [0, 1]]
      gridLines (paginate 1 8 [FParagraph (lines' 0 4), ruled Nothing (Just bare) (lines' 10 6)]) @?= [[0 .. 3], [0 .. 5]],
    testCase "a ruled paragraph stays where it is; the note that does not fit goes to the next page" $ do
      let withNote = LineBox 10 [NoteBody (nid 900) 4] [] [] 0
          ps = paginate 1 6 [FParagraph (lines' 0 2), ruled (Just bare) Nothing (withNote : lines' 11 1)]
      gridLines ps @?= [[0, 1, 2, 3], []]
      -- the rest of the note is on the next page
      map poFootnotes ps @?= [[(nid 900, 0, 1)], [(nid 900, 1, 3)]],
    testCase "a ruled heading whose note does not fit goes on with its note and its rule (golem-layout ADR 0013)" $ do
      let h = FRuled 20 (Just (spaced 5 10)) Nothing False ruleGrid 0 (RuledHeading False 1 [LineBox 20 [NoteBody (nid 900) 2] [] [] 0])
          ps = paginate 1 6 [FParagraph (lines' 0 3), h, FParagraph (lines' 30 1)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 30]]
      gridLines ps @?= [[0, 1, 2], [1, 2]]
      notesByPage ps @?= [(1, []), (2, [nid 900])],
    testCase "a heading before a ruled paragraph of 5 lines goes on with it" $ do
      let ps = paginate 1 8 [FParagraph (lines' 0 3), heading 20, ruled (Just bare) Nothing (lines' 30 5)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], SHeading 20 1 : map SLine [30 .. 34]],
    testCase "a rule after and a rule before in a row share one area; with space-between they do not" $ do
      let a = ruled Nothing (Just (spaced 2 3)) (lines' 0 2)
          b = FRuled 10 (Just (spaced 2 6)) Nothing True ruleGrid 0 (RuledLines (lines' 10 2))
          b' = FRuled 10 (Just (spaced 2 6)) Nothing False ruleGrid 0 (RuledLines (lines' 10 2))
          p = 17 * 65536
          face = 10 * 65536
      let joined = paginate 1 20 [a, b]
      gridLines joined @?= [[0, 1, 3, 4]]
      map poRules joined @?= [[PlacedRule 0 False (p + face + 2 * 65536), PlacedRule 10 True (p + face + 24 * 65536 - 2 * 65536 - 32768)]]
      gridLines (paginate 1 20 [a, FSpace 1, b']) @?= [[0, 1, 4, 5]],
    testCase "a ruled paragraph split between columns has no rules and takes no lines for them (golem-driver ADR 0035)" $ do
      let ps = paginate 1 4 [ruled (Just (spaced 5 10)) (Just (spaced 5 10)) (lines' 0 6)]
      -- the first part starts at the first grid line; the room after the last part is not used
      gridLines ps @?= [[0, 1, 2, 3], [0, 1]]
      map poRules ps @?= [[], []],
    testCase "the rule after before a split paragraph takes its own area (golem-driver ADR 0035)" $ do
      let a = ruled Nothing (Just (spaced 2 3)) (lines' 0 1)
          b = FRuled 10 (Just (spaced 2 6)) (Just (spaced 2 6)) True ruleGrid 0 (RuledLines (lines' 10 8))
          rules = concatMap poRules (paginate 1 5 [a, b])
      [(prId r, prBefore r) | r <- rules] @?= [(0, False)]
      rules @?= concatMap poRules (paginate 1 5 [a, FSpace 0, b {frJoined = False}]),
    testCase "the rule before after a split paragraph is a rule of its own (golem-driver ADR 0035)" $ do
      let b = FRuled 10 (Just (spaced 2 6)) (Just (spaced 2 6)) False ruleGrid 0 (RuledLines (lines' 10 6))
          c joined = FRuled 30 (Just (spaced 2 6)) Nothing joined ruleGrid 0 (RuledLines (lines' 30 1))
          rulesOf j = map poRules (paginate 1 5 [b, c j])
      [(prId r, prBefore r) | r <- concat (rulesOf True)] @?= [(30, True)]
      rulesOf True @?= rulesOf False,
    testCase "a ruled paragraph that ends at the column end counts its rule at the edge" $ do
      -- inside: inner 5pt, outer 30pt take 2 lines; at the end 1 line
      let ps = paginate 1 4 [ruled Nothing (Just (spaced 5 30)) (lines' 0 3)]
      gridLines ps @?= [[0, 1, 2]]
      map poRules ps @?= [[PlacedRule 0 False (2 * 17 * 65536 + 10 * 65536 + 5 * 65536)]]
  ]
