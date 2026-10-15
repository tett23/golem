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
import Golem.Syntax (FileId (..), mkSpan)
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
      testGroup "invariants" propertyTests
    ]

-- | n plain lines numbered from base.
lines' :: Int -> Int -> [LineBox]
lines' base n = [LineBox (base + i) [] [] [] | i <- [0 .. n - 1]]

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
      let ps = paginate 1 6 [FParagraph (lines' 0 3), heading 20, FTable 100 (lines' 30 1) [lines' 40 2]]
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
headingWithNote i note = FHeading 2 False 1 [LineBox i [NoteBody note 1] [] []]

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
    testCase "the label of a heading sent to the next page is on that page" $ do
      let ps = paginate 1 5 [FParagraph (lines' 0 3), FHeading 2 False 1 [LineBox 20 [] ["sec"] []], FParagraph (lines' 30 2)]
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

{- | The label "x" on the last of k one-line pages before it, where k is
the page assumed for "x" capped at cap: the page of "x" is k + 1.
-}
creeping :: Integer -> Map.Map Text Integer -> [PageOut]
creeping cap assumed =
  let k = fromInteger (min cap (Map.findWithDefault 0 "x" assumed))
   in paginate 1 1 ([FParagraph [LineBox i [] [] []] | i <- [0 .. k - 1]] <> [FParagraph [LineBox 999 [] ["x"] []]])

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
                  FParagraph (LineBox 0 [] ["stable"] [] : lines' 1 4)
                    : replicate fillers (FParagraph (lines' 10 5))
                      <> [FParagraph [LineBox 999 [] ["b", "a"] []]]
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

propertyTests :: [TestTree]
propertyTests =
  [ testProperty "every line of paragraphs and headings is placed once, in the order written" $ property $ do
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
      filter (\k -> k < 0 || k >= capacity) starts === []
  ]
