module BookPartsSpec (tests) where

import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Paginate
import Golem.Project.Style (KeepParts (..))
import Golem.Syntax (FileId (..), mkSpan)
import Hedgehog qualified as H
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "root ADR 0401 retention boundaries"
    [ testProperty "root ADR 0377 inv1_keep_book_parts_property: oversized items terminate without losing lines" $ H.property $ do
        capacity <- H.forAll (Gen.int (Range.linear 1 8))
        columns <- H.forAll (Gen.int (Range.linear 1 3))
        count <- H.forAll (Gen.int (Range.linear 0 60))
        unit <- H.forAll (Gen.element [KeepColumn, KeepPage, KeepSpread])
        let pages = paginate columns capacity [part unit 10 count]
            identifiers = [i | page <- pages, (_, SLine i) <- poSlots page]
        H.annotateShow (slots pages)
        identifiers H.=== [10 .. 10 + count - 1]
        H.assert (length pages <= count + columns)
        H.assert (length (concatMap poUnmet pages) <= 1),
      testCase "root ADR 0401 I3: an empty first page retries the larger following spread" $ do
        let pages = paginate 1 3 [part KeepSpread 10 5]
        slots pages @?= [(2, 0, [10, 11, 12]), (3, 0, [13, 14])]
        concatMap poUnmet pages @?= [],
      testCase "root ADR 0401 I2: a term and first description may cross columns in their page" $ do
        let pages = paginate 2 3 [para 0 2, FBookPart KeepPage sp "definition" [10, 11, 20] [FDefTerm (boxes 10 2), para 20 2]]
        slots pages @?= [(1, 0, [0, 1, 10]), (1, 1, [11, 20, 21])],
      testCase "root ADR 0401 I2: discarded trials preserve final notes labels and index marks" $ do
        let note = NoteId sp 0
            marked = [LineBox 10 [NoteBody note 1] ["only"] [sp] 0, LineBox 11 [] [] [] 0, LineBox 12 [] [] [] 0]
            body = FParagraph defaultKeep marked
            retained = paginate 2 5 [para 0 8, FBookPart KeepPage sp "list item" [10, 11, 12] [body]]
            explicit = paginate 2 5 [para 0 8, FBreak BreakPage, body]
        retained @?= explicit
        concatMap poFootnotes retained @?= [(note, 0, 1)]
        concatMap poLabels retained @?= ["only"]
        concatMap poMarks retained @?= [sp],
      testCase "root ADR 0401 I2: a lower table caption stays in the last row's page" $ do
        let pages = paginate 2 2 [FBookPart KeepPage sp "table" [10, 11] [FTable 10 0 [] [boxes 10 2, boxes 20 1] (boxes 30 2) True]]
        slots pages @?= [(1, 0, [10, 11]), (2, 0, [20]), (2, 1, [30, 31])],
      testCase "root ADR 0401 I2: a spread repeats table headers on the next physical page only" $ do
        let header = boxes 10 1
            rows = [boxes 20 2, boxes 30 2, boxes 40 2]
            pages = paginate 2 3 [FBreak BreakPage, FBookPart KeepSpread sp "table" [10, 20, 21] [FTable 10 0 header rows [] False]]
        slots pages @?= [(2, 0, [10, 20, 21]), (2, 1, [30, 31]), (3, 0, [10, 40, 41])],
      testCase "root ADR 0401 I2: a table caption can share its page across a column boundary" $ do
        let header = boxes 10 1
            row = boxes 20 1
            caption = boxes 30 1
            before = paginate 2 2 [FBookPart KeepPage sp "table" [10, 20, 30] [FTable 10 0 header [row] caption False]]
            captionBelow = paginate 2 2 [FBookPart KeepPage sp "table" [10, 20, 30] [FTable 10 0 header [row] caption True]]
        slots before @?= [(1, 0, [30, 10]), (1, 1, [20])]
        map poTables before @?= [[TableSegment 10 1 (Just 1) 1], [TableSegment 10 0 Nothing 0]]
        slots captionBelow @?= [(1, 0, [10, 20]), (1, 1, [30])]
        map poTables captionBelow @?= [[TableSegment 10 0 (Just 0) 1], []],
      testCase "root ADR 0401 I2: a table header and first data row cross columns within a page" $ do
        let header = boxes 10 2
            row = boxes 20 2
            pages = paginate 2 3 [FBookPart KeepPage sp "table" [10, 11, 20, 21] [FTable 10 0 header [row] [] False]]
        slots pages @?= [(1, 0, [10, 11]), (1, 1, [20, 21])],
      testCase "root ADR 0401 I1: column retains the existing placement" $ do
        let before = [para 0 4, para 10 3]
        paginate 2 3 [para 0 4, part KeepColumn 10 3] @?= paginate 2 3 before,
      testCase "root ADR 0401 I2: page permits the column boundary within the same page" $
        slots (paginate 2 3 [para 0 2, part KeepPage 10 3]) @?= [(1, 0, [0, 1, 10]), (1, 1, [11, 12])],
      testCase "root ADR 0401 I2: page moves the item across a physical page boundary" $
        slots (paginate 2 3 [para 0 4, part KeepPage 10 3]) @?= [(1, 0, [0, 1, 2]), (1, 1, [3]), (2, 0, [10, 11, 12])],
      testCase "root ADR 0401 I2: spread permits physical pages two and three" $
        slots (paginate 1 3 [FBreak BreakPage, para 0 2, part KeepSpread 10 3]) @?= [(2, 0, [0, 1, 10]), (3, 0, [11, 12])],
      testCase "root ADR 0401 I2: spread moves an item from three to four" $
        slots (paginate 1 3 [FBreak BreakPage, para 0 5, part KeepSpread 10 2]) @?= [(2, 0, [0, 1, 2]), (3, 0, [3, 4]), (4, 0, [10, 11])],
      testCase "root ADR 0401 I3: an oversized item moves once and produces one notice" $ do
        let pages = paginate 1 3 [para 0 2, part KeepPage 10 7]
        slots pages @?= [(1, 0, [0, 1]), (2, 0, [10, 11, 12]), (3, 0, [13, 14, 15]), (4, 0, [16])]
        concatMap poUnmet pages @?= [SplitBookPart sp "list item" KeepPage],
      testCase "root ADR 0401 I3: an empty unit is not retried with identical conditions" $ do
        let pages = paginate 1 3 [part KeepPage 10 7]
        slots pages @?= [(1, 0, [10, 11, 12]), (2, 0, [13, 14, 15]), (3, 0, [16])]
        concatMap poUnmet pages @?= [SplitBookPart sp "list item" KeepPage]
    ]
  where
    sp = mkSpan (FileId 0) 0 1
    part unit start count = FBookPart unit sp "list item" [start .. start + count - 1] [para start count]
    boxes start count = [LineBox i [] [] [] 0 | i <- [start .. start + count - 1]]
    para start count = FParagraph (Keep 1 1 False) [LineBox i [] [] [] 0 | i <- [start .. start + count - 1]]
    slots pages = [(poNumber p, poColumn p, [i | (_, SLine i) <- poSlots p]) | p <- pages, not (null (poSlots p))]
