{- | Pagination (golem-layout ADR 0003): keeping headings with what
follows, widow and orphan boundaries, forced page breaks at the page
end, the fixed point of page references (S2), and invariants of
'paginate' as properties.

The footnote separator is changing (golem-driver ADR 0024), so these
tests assert on which page a note is, never on how many lines its
separator takes.
-}
module PaginateSpec (paginateTests) where

import Control.Exception (evaluate)
import Control.Monad (forM_, replicateM, when)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry (..))
import Golem.Layout.PageLabel (PageLabel (..), Section (..), pageLabelText)
import Golem.Layout.Paginate
import Golem.Layout.Paginate.State qualified as S
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Length (Sp (..))
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import PaginateEnum (Element (..), Input (..), controlSpan, enumFlows, noteOf, paginateInput, sectionFlow)
import PaginateInvariants (Breach (..), Invariant (..), breaches, p11WaitingBeforeSpace, p9SpaceMoved, w3WaitingAlike, waitingFigures)
import System.Timeout (timeout)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

headingRoundingCases :: [(Integer, Integer, Integer, Int, Int)]
headingRoundingCases =
  [ (fontSize, bodyPitch, headingSize, linesCount, minimumLines)
  | fontSize <- [1 .. 4],
    bodyPitch <- [fontSize .. 6],
    headingSize <- [1 .. 8],
    linesCount <- [1 .. 3],
    minimumLines <- [1 .. 3]
  ]

paginateTests :: TestTree
paginateTests =
  testGroup
    "pagination boundaries (golem-layout ADR 0003)"
    [ testCase "L2 (Golem ADR 0312): heading pitches round within half a sp and ties to even" $
        forM_ headingRoundingCases $ \(fontSize, bodyPitch, headingSize, linesCount, minimumLines) -> do
          let HeadingBlock (Sp pitch) _ _ = headingBlock (Sp fontSize) (Sp bodyPitch) (Sp headingSize) linesCount minimumLines
              distance = abs (pitch * fontSize - bodyPitch * headingSize)
          assertBool
            (show (fontSize, bodyPitch, headingSize, linesCount, minimumLines))
            (2 * distance <= fontSize && (2 * distance /= fontSize || even pitch)),
      testCase "L3 (Golem ADR 0312): heading span is minimal and vertical remainder is at most one sp" $
        forM_ headingRoundingCases $ \(fontSize, bodyPitch, headingSize, linesCount, minimumLines) -> do
          let HeadingBlock (Sp pitch) spanLines (Sp top) = headingBlock (Sp fontSize) (Sp bodyPitch) (Sp headingSize) linesCount minimumLines
              extent = toInteger (linesCount - 1) * pitch + headingSize
              area n = toInteger (n - 1) * bodyPitch + fontSize
              remainder = area spanLines - extent - 2 * top
          assertBool
            (show (fontSize, bodyPitch, headingSize, linesCount, minimumLines))
            ( spanLines >= minimumLines
                && area spanLines >= extent
                && (spanLines == minimumLines || area (spanLines - 1) < extent)
                && remainder `elem` [0, 1]
            ),
      testGroup "a heading kept with what follows" keepWithNextTests,
      testGroup "a heading with footnotes (golem-driver ADR 0003)" headingNoteTests,
      testGroup "keeping with what follows counts its footnotes (golem-layout ADR 0019)" keepNoteTests,
      testGroup "widows, orphans and the page end" widowOrphanTests,
      testGroup "stanzas of verse (docs/adr/0180)" stanzaTests,
      testGroup "the look-ahead counts the first part that can be split (golem-layout ADR 0021)" splitPartTests,
      testGroup "the look-ahead of a no-break counts the spaces (golem-layout ADR 0022)" keptSpaceTests,
      testGroup "the rules added by the implementation of ADR 0180 (docs/adr/0205)" addedRuleTests,
      testGroup "page references that do not settle (S2)" pageRefTests,
      testGroup "figures in the order written (golem-layout ADR 0015)" figureOrderTests,
      testGroup "turned figures on pages of their own (golem-driver ADR 0034)" pageFigureTests,
      testGroup "manual control of page breaks (docs/adr ADR 0030)" pageControlTests,
      testGroup "blank lines (docs/adr ADR 0046)" blankLineTests,
      testGroup "paragraphs and headings with rules (golem-driver ADR 0027)" ruledTests,
      testGroup "a heading taller than its column (golem-layout ADR 0020)" tallHeadingTests,
      testGroup "the points the invariants did not decide (docs/adr/0206)" undecidedPointTests,
      testGroup "a heading sent on is checked again after the figures sent on (golem-layout ADR 0023)" keepAfterFiguresTests,
      testGroup "keep goes on until the need fits (golem-layout ADR 0023)" keepTests,
      testGroup "a recto starts after the figures sent on and the continued notes (golem-layout ADR 0024)" rectoAfterFiguresTests,
      testGroup "need-lines, blank lines, tables and wrapped figures go on after what is sent on (golem-layout ADR 0025)" afterSentOnTests,
      testGroup "the figures that wait take no need-lines and no blank lines before them (golem-layout ADR 0026)" waitingFigureTests,
      testGroup "need-lines is judged again in the column a block goes on to after spaces (golem-layout ADR 0027)" spaceAfterNeedTests,
      testGroup "the figures that wait are read from the placement (golem-layout ADR 0033)" waitingReadTests,
      testGroup "a larger need-lines after one judged is judged again (golem-layout ADR 0035)" largerNeedTests,
      testGroup "the spaces before need-lines are not counted either (golem-layout ADR 0043)" spaceBeforeNeedTests,
      testGroup "the spaces before need-lines are not counted with figures that wait between (golem-layout ADR 0047)" spaceBeforeWaitingTests,
      testGroup "the breaks before sections and the page labels (docs/adr/0260)" sectionTests,
      testGroup "the keep options of paragraph styles (docs/adr/0261)" keepOptionTests,
      testGroup "invariants" propertyTests
    ]

-- | The examples of the keep options of paragraph styles (docs/adr/0261).
keepOptionTests :: [TestTree]
keepOptionTests =
  [ testCase "K7: splitAtBreak of defaultKeep is the rule before, for 1 to 8 lines and every number that fits" $
      sequence_
        [ (n, k, splitAtBreak defaultKeep start n k) @?= (n, k, old start n k)
        | start <- [False, True],
          n <- [1 .. 8],
          k <- [0 .. n]
        ],
    testCase "K1: five lines of keep-first-lines 3 with two lines free go whole to the next column" $
      lineIds (paginate 1 4 [FParagraph defaultKeep (lines' 0 2), FParagraph (Keep 3 1 False) (lines' 10 5)]) @?= [[0, 1], [10, 11, 12, 13], [14]],
    testCase "K2: keep-last-lines 3 with four lines free places two" $
      lineIds (paginate 1 4 [FParagraph (Keep 1 3 False) (lines' 10 5)]) @?= [[10, 11], [12, 13, 14]],
    testCase "K3: keep-all-lines of C + 1 lines from the middle of a column starts the next and is split there, SplitKept recorded" $ do
      let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 1), FParagraph (Keep 2 2 True) (lines' 10 4)]
      lineIds ps @?= [[0], [10, 11], [12, 13]]
      unmets ps @?= [SplitKept 10],
    testCase "K4: keep-with-next 3 keeps the first three lines of six with the last line before" $ do
      -- in a column of five from the top, the paragraph before is not sent on: the keep is recorded
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FKeepNext mk 3, FParagraph defaultKeep (lines' 10 6)]
      lineIds ps @?= [[0, 1, 2, 10, 11], [12, 13, 14, 15]]
      unmets ps @?= [UnmetKeepNext mk]
      -- in a column of six, the paragraph before goes with them
      lineIds (paginate 1 6 [FParagraph defaultKeep (lines' 90 4), FParagraph defaultKeep (lines' 0 3), FKeepNext mk 3, FParagraph defaultKeep (lines' 10 6)])
        @?= [[90, 91, 92, 93], [0, 1, 2, 10, 11, 12], [13, 14, 15]],
    testCase "K4: a chain of keep-with-next longer than the column moves its first paragraph, and the keep that cannot be held is recorded once" $ do
      let ps = paginate 1 4 [FParagraph defaultKeep (lines' 90 1), FParagraph defaultKeep (lines' 0 2), FKeepNext mk 2, FParagraph defaultKeep (lines' 10 2), FKeepNext mk2 2, FParagraph defaultKeep (lines' 20 2)]
      lineIds ps @?= [[90], [0, 1], [10, 11, 20, 21]]
      unmets ps @?= [UnmetKeepNext mk],
    testCase "K5, K6: page-break page right after @page-break makes no blank page; recto after an even page makes one" $ do
      let page = FSection (OfParagraph mk) BreakPage
          recto = FSection (OfParagraph mk) BreakRecto
      [(poNumber p, poBlank p) | p <- paginate 1 3 [FParagraph defaultKeep (lines' 0 1), FBreak BreakPage, page, FParagraph defaultKeep (lines' 10 1)]] @?= [(1, False), (2, False)]
      [(poNumber p, poBlank p) | p <- paginate 1 3 [FParagraph defaultKeep (lines' 0 1), FBreak BreakPage, recto, FParagraph defaultKeep (lines' 10 1)]] @?= [(1, False), (2, True), (3, False)]
      -- after a line of an even page, the next odd page with no blank page
      [(poNumber p, poBlank p) | p <- paginate 1 3 [FParagraph defaultKeep (lines' 0 3), FParagraph defaultKeep (lines' 5 1), recto, FParagraph defaultKeep (lines' 10 1)]] @?= [(1, False), (2, False), (3, False)],
    testCase "I6, K4: a heading before a paragraph that is all its first part and keeps with the next goes on with them" $ do
      -- the nightly enumeration's counterexample: the heading counts the first part kept with the paragraph after it
      let ps = paginate 1 3 [FParagraph (Keep 1 1 False) (lines' 0 1), headingAt 1, FParagraph (Keep 1 1 False) (lines' 2 1), FKeepNext mk 2, FParagraph (Keep 1 1 False) (lines' 3 1)]
      map (map snd . poSlots) ps @?= [[SLine 0], [SHeading 1 1, SLine 2, SLine 3]]
      unmets ps @?= [],
    testCase "K5: a heading right before a paragraph of page-break page stays on the page before, unrecorded" $ do
      let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 1), headingAt 20, FSection (OfParagraph mk) BreakPage, FParagraph defaultKeep (lines' 10 2)]
      map (map snd . poSlots) ps @?= [[SLine 0, SHeading 20 1], [SLine 10, SLine 11]]
      unmets ps @?= []
  ]
  where
    old start n k =
      let k1 = if n - k == 1 && k > 0 then k - 1 else k
       in if start && k1 == 1 && n >= 2 then 0 else k1
    headingAt i = FHeading 2 False 1 (lines' i 1)

{- | The break before a section (docs/adr/0260) after each of the four
pages before it (empty or not, odd or even), with each start, and each
first block of its file: a paragraph, a heading at a recto, and nothing
(the next file's paragraph follows). The first page of the section, the
blank pages and the page of the first line after it (I1, I3, I7 of the
ADR) in columns of three grid lines.
-}
sectionTests :: [TestTree]
sectionTests =
  [ testCase ("I1, I3, I7: after " <> prevName <> ", start " <> maybe "omitted" show start <> ", " <> blockName) $ do
      let ps = paginate 1 3 (before <> [sectionFlow 0 start] <> block)
          firstPage = [poNumber p | p <- ps, 0 `elem` poSections p]
          blanks = [poNumber p | p <- ps, poBlank p]
          lineAt = [poNumber p | p <- ps, (_, s) <- poSlots p, s `elem` [SLine 100, SHeading 100 1]]
          labels = Map.elems (pageLabels (Map.fromList [(0, Section start Nothing)]) ps)
          recto = blockName == "a heading at a recto"
          blockPage = if recto && even f then f + 1 else f
      firstPage @?= [f]
      blanks @?= bs <> [f | recto, even f]
      lineAt @?= [blockPage]
      -- I1: every number has the parity of its page; I3: the first page is the start, or counts on
      [plIndex l | l <- labels, odd (plNumber l) /= odd (plIndex l)] @?= []
      map plNumber (filter ((== f) . plIndex) labels) @?= [fromMaybe (toInteger f) start]
  | (prevName, before, table) <- prevs,
    (start, (f, bs)) <- table,
    (blockName, block) <- blocks
  ]
    <> [ testCase "two sections after an empty file: the later starts on a page of its own when its parity asks" $ do
           let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 1), sectionFlow 0 Nothing, sectionFlow 1 (Just 1), FParagraph defaultKeep (lines' 100 1)]
           [(poNumber p, poSections p, poBlank p) | p <- ps] @?= [(1, [], False), (2, [0], True), (3, [1], False)],
         testCase "two sections on one page: both are recorded on it, and the later numbers it" $ do
           let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 1), sectionFlow 0 (Just 1), sectionFlow 1 Nothing, FParagraph defaultKeep (lines' 100 1)]
               sections = Map.fromList [(0, Section (Just 1) Nothing), (1, Section Nothing Nothing)]
           [(poNumber p, poSections p) | p <- ps] @?= [(1, []), (2, []), (3, [0, 1])]
           -- the later, without a start, counts on: the start of the earlier is not used
           map plNumber (Map.elems (pageLabels sections ps)) @?= [1, 2, 3],
         testCase "a section at the end of the book has no page" $ do
           let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 1), sectionFlow 0 (Just 1)]
           [(poNumber p, poSections p) | p <- ps] @?= [(1, [])],
         testCase "a section at 1 after two pages numbers its pages from 1 again" $ do
           let ps = paginate 1 3 [sectionFlow 0 Nothing, FParagraph defaultKeep (lines' 0 4), sectionFlow 1 (Just 1), FParagraph defaultKeep (lines' 100 4)]
               sections = Map.fromList [(0, Section Nothing Nothing), (1, Section (Just 1) Nothing)]
           [(plIndex l, plNumber l, pageLabelText l) | l <- Map.elems (pageLabels sections ps)] @?= [(1, 1, "1"), (2, 2, "2"), (3, 1, "1"), (4, 2, "2")]
       ]
  where
    -- the page before: its flows, and by start the first page and the blank pages before it
    prevs =
      [ ("an empty odd page", [], [(Nothing, (1, [])), (Just 1, (1, [])), (Just 2, (2, [1]))]),
        ("an empty even page", [FParagraph defaultKeep (lines' 0 1), FBreak BreakPage], [(Nothing, (2, [])), (Just 1, (3, [2])), (Just 2, (2, []))]),
        ("an odd page with a line", [FParagraph defaultKeep (lines' 0 1)], [(Nothing, (2, [])), (Just 1, (3, [2])), (Just 2, (2, []))]),
        ("an even page with a line", [FParagraph defaultKeep (lines' 0 3), FParagraph defaultKeep (lines' 3 1)], [(Nothing, (3, [])), (Just 1, (3, [])), (Just 2, (4, [3]))])
      ]
    blocks =
      [ ("a paragraph", [FParagraph defaultKeep (lines' 100 1)]),
        ("a heading at a recto", [FHeading 1 True 1 (lines' 100 1)]),
        ("nothing, the next file after it", [FParagraph defaultKeep (lines' 100 1)])
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
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), heading 20, FFigure 99 2 [] []]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SFigure 99]],
    testCase "a heading stays at the page end when the figure after it fits after it" $ do
      -- 2 free: heading 1 + figure 1 = 2
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), heading 20, FFigure 99 1 [] []]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SHeading 20 1, SFigure 99]],
    testCase "a heading before a table keeps the header and the first row, not only the header" $ do
      -- 3 free: heading 1 + header 1 + first row 2 = 4 > 3
      let ps = paginate 1 6 [FParagraph defaultKeep (lines' 0 3), heading 20, FTable 100 0 (lines' 30 1) [lines' 40 2] [] False]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 30, SLine 40, SLine 41]],
    testCase "a heading before a code block keeps the grid lines of its first row with padding" $ do
      -- 2 free: heading 1 + one row with padding 2 = 3 > 2; three rows take 4 lines
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), heading 20, FCode paddedCode 0 1 False (lines' 30 3)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SCode 30 3 4]],
    testCase "a heading stays when the first row of the code block after it fits; the rest goes on" $ do
      -- 3 free: heading 1 + one row 2 = 3; the other two rows take 3 lines on page 2
      let ps = paginate 1 6 [FParagraph defaultKeep (lines' 0 3), heading 20, FCode paddedCode 0 1 False (lines' 30 3)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SHeading 20 1, SCode 30 1 2], [SCode 31 2 3]],
    testCase "a heading before a heading of two grid lines counts that span" $ do
      -- 2 free: heading 1 + the next heading's span 2 = 3 > 2
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), heading 20, FHeading 3 False 2 (lines' 25 1), FParagraph defaultKeep (lines' 30 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SHeading 25 1, SLine 30, SLine 31]],
    testCase "a definition term before a code block keeps its first row" $ do
      -- 2 free: term 1 + one row 2 = 3 > 2
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FDefTerm (lines' 20 1), FCode paddedCode 0 1 False (lines' 30 1)]
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
      let ps = paginate 1 8 [headingWithNote 20 (nid 900), FParagraph defaultKeep (lines' 30 2)]
      notesByPage ps @?= [(1, [nid 900])],
    testCase "a heading sent to the next page takes its note with it" $ do
      -- 2 free after six lines: heading 1 + two lines = 3 > 2
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 6), headingWithNote 20 (nid 900), FParagraph defaultKeep (lines' 30 2)]
      notesByPage ps @?= [(1, []), (2, [nid 900])],
    testCase "a heading whose note does not fit goes to the next page with its note (golem-layout ADR 0013)" $ do
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 5), FHeading 2 False 1 [LineBox 20 [NoteBody (nid 900) 3] [] [] 0], FParagraph defaultKeep (lines' 30 2)]
      notesByPage ps @?= [(1, []), (2, [nid 900])]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 3, SLine 4], [SHeading 20 1, SLine 30, SLine 31]],
    testCase "the note of a heading counts in keeping it with what follows (golem-layout ADR 0013)" $ do
      -- 3 free: heading 1 + note 1 + separator, then no room for two lines
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 5), headingWithNote 20 (nid 900), FParagraph defaultKeep (lines' 30 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 3, SLine 4], [SHeading 20 1, SLine 30, SLine 31]]
      notesByPage ps @?= [(1, []), (2, [nid 900])],
    testCase "a heading whose note fits stays on the page" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 2), headingWithNote 20 (nid 900), FParagraph defaultKeep (lines' 30 2)]
      notesByPage ps @?= [(1, [nid 900])],
    testCase "a heading in an empty page keeps its place and its note continues on the next page" $ do
      let ps = paginate 1 5 [FHeading 2 False 1 [LineBox 20 [NoteBody (nid 900) 6] [] [] 0]]
      notesByPage ps @?= [(1, [nid 900]), (2, [nid 900])]
      contents ps @?= [[SHeading 20 1], []],
    testCase "in two columns, a heading whose note does not fit goes to the next column (golem-layout ADR 0013)" $ do
      let ps = paginate 2 8 [FParagraph defaultKeep (lines' 0 5), FHeading 2 False 1 [LineBox 20 [NoteBody (nid 900) 3] [] [] 0], FParagraph defaultKeep (lines' 30 2)]
      [(poNumber p, poColumn p, [i | (i, _, _) <- poFootnotes p]) | p <- ps] @?= [(1, 0, []), (1, 1, [nid 900])]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 3, SLine 4], [SHeading 20 1, SLine 30, SLine 31]],
    testCase "a heading on a page that has notes counts no second separator for its note (golem-layout ADR 0013)" $ do
      -- separator 1: three lines, the separator and a note take 5 of 9; heading 1 + its note 1 + two lines = 4 fit
      let ps = paginateIn 1 (ColumnSet 1 0 0 0) 9 [FParagraph defaultKeep (LineBox 0 [NoteBody (nid 800) 1] [] [] 0 : lines' 1 2), headingWithNote 20 (nid 900), FParagraph defaultKeep (lines' 30 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SHeading 20 1, SLine 30, SLine 31]]
      notesByPage ps @?= [(1, [nid 800, nid 900])],
    testCase "the label of a heading sent to the next page is on that page" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FHeading 2 False 1 [LineBox 20 [] ["sec"] [] 0], FParagraph defaultKeep (lines' 30 2)]
      Map.map plIndex (labelPages Map.empty ps) @?= Map.fromList [("sec", 2)]
  ]

-- | A line whose footnote has k lines.
noted :: Int -> Int -> LineBox
noted i k = LineBox i [NoteBody (nid 900) k] [] [] 0

keepNoteTests :: [TestTree]
keepNoteTests =
  [ testCase "Golem ADR 0352 I4: a one-line note terminates at capacities 1, 2, and 3" $ do
      results <-
        mapM
          (\capacity -> timeout 1000000 (evaluate (length (paginate 1 capacity [FParagraph defaultKeep [noted 0 1]]))))
          [1 .. 3]
      map isJust results @?= [True, True, True]
      map (unmets . (\capacity -> paginate 1 capacity [FParagraph defaultKeep [noted 0 1]])) [1, 2]
        @?= [[UnplaceableFootnote (nid 900) 1], [UnplaceableFootnote (nid 900) 2]],
    testCase "Golem ADR 0353 I2: capacities 1 and 2 remain valid without footnotes" $
      map (\capacity -> (contents (paginate 1 capacity [FParagraph defaultKeep (lines' 0 1)]), unmets (paginate 1 capacity [FParagraph defaultKeep (lines' 0 1)]))) [1, 2]
        @?= [([[SLine 0]], []), ([[SLine 0]], [])],
    testCase "Golem ADR 0353 I1: page-lines leaves marker and note together in the next full column" $ do
      let ps = paginate 1 3 [FAdjustLines mk (-1), FParagraph defaultKeep [noted 0 1]]
      [(poNumber p, [i | (i, _, _) <- poFootnotes p]) | p <- ps, not (null (poSlots p))]
        @?= [(2, [nid 900])]
      unmets ps @?= [],
    testCase "Golem ADR 0352 I3: relaxedAfterHeadings model fixture places one body line" $ do
      let ps = paginate 1 3 [heading 20, FParagraph defaultKeep (lines' 30 3)]
      contents ps @?= [[SHeading 20 1, SLine 30, SLine 31], [SLine 32]],
    testCase "Golem ADR 0352 I3: headingFigureFits model fixture keeps the figure" $ do
      let ps = paginate 1 3 [heading 20, FFigure 99 2 [] [], FParagraph defaultKeep (lines' 30 1)]
      contents ps @?= [[SHeading 20 1, SFigure 99], [SLine 30]],
    testCase "Golem ADR 0352 I3: headingFigureWaits model fixture sends the figure" $ do
      let ps = paginate 1 3 [heading 20, FFigure 99 3 [] [], FParagraph defaultKeep (lines' 30 1)]
      contents ps @?= [[SHeading 20 1, SLine 30], [SFigure 99]],
    testCase "a heading goes on with a line whose note does not fit after it" $ do
      -- 4 free: heading 1 + two lines + note 3 + separator > 4
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 4), heading 20, FParagraph defaultKeep (noted 30 3 : lines' 31 1)]
      contents ps @?= [map SLine [0 .. 3], [SHeading 20 1, SLine 30, SLine 31]]
      notesByPage ps @?= [(1, []), (2, [nid 900])],
    testCase "in two columns, the heading goes to the next column with the line and its note" $ do
      let ps = paginate 2 8 [FParagraph defaultKeep (lines' 0 4), heading 20, FParagraph defaultKeep (noted 30 3 : lines' 31 1)]
      [(poNumber p, poColumn p, [i | (i, _, _) <- poFootnotes p]) | p <- ps] @?= [(1, 0, []), (1, 1, [nid 900])]
      contents ps @?= [map SLine [0 .. 3], [SHeading 20 1, SLine 30, SLine 31]],
    testCase "the note of a heading after a heading counts" $ do
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 4), heading 20, FHeading 2 False 1 [LineBox 25 [NoteBody (nid 900) 2] [] [] 0], FParagraph defaultKeep (lines' 30 2)]
      contents ps @?= [map SLine [0 .. 3], [SHeading 20 1, SHeading 25 1, SLine 30, SLine 31]],
    testCase "a definition term goes on with a line whose note does not fit after it" $ do
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 4), FDefTerm (lines' 20 1), FParagraph defaultKeep (noted 30 3 : lines' 31 1)]
      contents ps @?= [map SLine [0 .. 3], map SLine [20, 30, 31]],
    testCase "no-break: the paragraph before goes on with a line whose note does not fit after it" $ do
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 4), FParagraph defaultKeep (lines' 20 2), FNoBreak mk, FParagraph defaultKeep (noted 30 3 : lines' 31 1)]
      lineIds ps @?= [[0 .. 3], [20, 21, 30, 31]]
      unmets ps @?= [],
    testCase "a heading alone in its column takes the next line, its note continues on the next page" $ do
      -- the note of 10 lines does not fit even an empty page
      let ps = paginate 1 8 [heading 20, FParagraph defaultKeep (noted 30 10 : lines' 31 1)]
      contents ps @?= [[SHeading 20 1, SLine 30], [SLine 31]]
      notesByPage ps @?= [(1, [nid 900]), (2, [nid 900])],
    testCase "a heading sent to the next page takes the line whose note does not fit any page" $ do
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 4), heading 20, FParagraph defaultKeep (noted 30 10 : lines' 31 1)]
      take 2 (contents ps) @?= [map SLine [0 .. 3], [SHeading 20 1, SLine 30]],
    testCase "the separator is counted once for the notes of a heading and of the line after it" $ do
      -- separator 1, 6 free: heading 1 + its note 1 + two lines + their note 1 + separator 1 = 6
      let ps = paginateIn 1 (ColumnSet 1 0 0 0) 10 [FParagraph defaultKeep (lines' 0 4), headingWithNote 20 (nid 800), FParagraph defaultKeep (noted 30 1 : lines' 31 1)]
      contents ps @?= [map SLine [0 .. 3] <> [SHeading 20 1, SLine 30, SLine 31]],
    testCase "no separator is counted on a page that has notes" $ do
      -- separator 1: three lines, the separator and a note take 5 of 9; heading 1 + two lines + note 1 = 4 fit
      let ps = paginateIn 1 (ColumnSet 1 0 0 0) 9 [FParagraph defaultKeep (LineBox 0 [NoteBody (nid 800) 1] [] [] 0 : lines' 1 2), heading 20, FParagraph defaultKeep (noted 30 1 : lines' 31 1)]
      contents ps @?= [map SLine [0 .. 2] <> [SHeading 20 1, SLine 30, SLine 31]],
    testCase "a ruled heading goes on with a line whose note does not fit after it" $ do
      let h = FRuled 20 (Just (spaced 5 10)) Nothing False ruleGrid 0 (RuledHeading False 1 (lines' 20 1))
          ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 4), h, FParagraph defaultKeep (noted 30 3 : lines' 31 1)]
      contents ps @?= [map SLine [0 .. 3], [SHeading 20 1, SLine 30, SLine 31]]
      notesByPage ps @?= [(1, []), (2, [nid 900])]
  ]

-- | The line ids on each page.
lineIds :: [PageOut] -> [[Int]]
lineIds = map (\p -> [i | (_, SLine i) <- poSlots p])

-- | A stanza of verse lines of the given numbers of lines, numbered from base.
stanza :: Int -> [Int] -> Flow
stanza base ns = FStanza defaultKeep [lines' (base + 10 * i) n | (i, n) <- zip [0 ..] ns]

stanzaTests :: [TestTree]
stanzaTests =
  [ testCase "a stanza of four verse lines with three lines left: two here, two in the next column" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 2), stanza 100 [1, 1, 1, 1]]
      contents ps @?= [[SLine 0, SLine 1, SLine 100, SLine 110], [SLine 120, SLine 130]],
    testCase "the same stanza with one line left goes whole to the next column" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 4), stanza 100 [1, 1, 1, 1]]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 3], [SLine 100, SLine 110, SLine 120, SLine 130]],
    testCase "a stanza of three verse lines stays with three lines left and goes whole with two" $ do
      let three = paginate 1 5 [FParagraph defaultKeep (lines' 0 2), stanza 100 [1, 1, 1]]
      contents three @?= [[SLine 0, SLine 1, SLine 100, SLine 110, SLine 120]]
      let two = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), stanza 100 [1, 1, 1]]
      contents two @?= [[SLine 0, SLine 1, SLine 2], [SLine 100, SLine 110, SLine 120]],
    testCase "a verse line broken into lines is not broken between columns" $ do
      -- four lines left: the third verse line of four lines would start in them
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 4), stanza 100 [1, 1, 4, 1, 1]]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 3, SLine 100, SLine 110], [SLine 120, SLine 121, SLine 122, SLine 123, SLine 130, SLine 140]],
    testCase "the second verse line broken in two stays whole" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 2), stanza 100 [1, 2, 1, 1]]
      contents ps @?= [[SLine 0, SLine 1, SLine 100, SLine 110, SLine 111], [SLine 120, SLine 130]],
    testCase "a stanza taller than an empty column: as many verse lines as fit" $ do
      let ps = paginate 1 3 [stanza 100 [2, 2]]
      contents ps @?= [[SLine 100, SLine 101], [SLine 110, SLine 111]],
    testCase "a heading keeps the first two verse lines of the stanza after it" $ do
      -- two lines left: the heading and one verse line would fit
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), heading 20, stanza 100 [1, 1, 1, 1]]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 100, SLine 110, SLine 120, SLine 130]]
      -- three lines left: the heading and two verse lines, the rest in the next column
      let qs = paginate 1 5 [FParagraph defaultKeep (lines' 0 2), heading 20, stanza 100 [1, 1, 1, 1]]
      contents qs @?= [[SLine 0, SLine 1, SHeading 20 1, SLine 100, SLine 110], [SLine 120, SLine 130]],
    testCase "a heading keeps the space before the stanza and its first two verse lines (docs/adr/0205)" $ do
      -- three lines left: the heading, the space and one verse line would fit
      let ps = paginate 1 6 [FParagraph defaultKeep (lines' 0 3), heading 20, FSpace 1, stanza 100 [1, 1, 1, 1]]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 100, SLine 110, SLine 120, SLine 130]]
      -- four lines left: they all fit after the heading
      let qs = paginate 1 6 [FParagraph defaultKeep (lines' 0 2), heading 20, FSpace 1, stanza 100 [1, 1, 1, 1]]
      contents qs @?= [[SLine 0, SLine 1, SHeading 20 1, SLine 100, SLine 110], [SLine 120, SLine 130]],
    testCase "a stanza before a no-break keeps its last two verse lines with what follows (docs/adr/0205)" $ do
      let ps = paginate 1 6 [FParagraph defaultKeep (lines' 0 1), stanza 100 [1, 1, 1, 1], FNoBreak mk, FParagraph defaultKeep (lines' 200 2)]
      contents ps @?= [[SLine 0, SLine 100, SLine 110], [SLine 120, SLine 130, SLine 200, SLine 201]]
  ]

widowOrphanTests :: [TestTree]
widowOrphanTests =
  [ testCase "a two-line paragraph with one line left goes whole to the next page" $
      lineIds (paginate 1 5 [FParagraph defaultKeep (lines' 0 4), FParagraph defaultKeep (lines' 10 2)]) @?= [[0, 1, 2, 3], [10, 11]],
    testCase "a three-line paragraph with two lines left goes whole: no widow, then no orphan" $
      lineIds (paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FParagraph defaultKeep (lines' 10 3)]) @?= [[0, 1, 2], [10, 11, 12]],
    testCase "a five-line paragraph with four lines left leaves two for the next page, not one" $
      lineIds (paginate 1 5 [FParagraph defaultKeep (lines' 0 1), FParagraph defaultKeep (lines' 10 5)]) @?= [[0, 10, 11, 12], [13, 14]],
    testCase "a three-line paragraph with one line left goes whole to the next page" $
      lineIds (paginate 1 5 [FParagraph defaultKeep (lines' 0 4), FParagraph defaultKeep (lines' 10 3)]) @?= [[0, 1, 2, 3], [10, 11, 12]],
    testCase "a four-line paragraph with two lines left is split two and two" $
      lineIds (paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FParagraph defaultKeep (lines' 10 4)]) @?= [[0, 1, 2, 10, 11], [12, 13]],
    testCase "a one-line paragraph takes the last line of the page" $
      lineIds (paginate 1 5 [FParagraph defaultKeep (lines' 0 4), FParagraph defaultKeep (lines' 10 1)]) @?= [[0, 1, 2, 3, 10]],
    testCase "a paragraph that fills the page exactly makes one page" $
      lineIds (paginate 1 5 [FParagraph defaultKeep (lines' 0 5)]) @?= [[0, 1, 2, 3, 4]],
    testCase "on pages of one line the widow and orphan rules give way" $
      lineIds (paginate 1 1 [FParagraph defaultKeep (lines' 0 2)]) @?= [[0], [1]],
    testCase "a page break right after a full page adds no blank page" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 5), FBreak BreakPage, FParagraph defaultKeep (lines' 10 1)]
      map poBlank ps @?= [False, False]
      lineIds ps @?= [[0, 1, 2, 3, 4], [10]],
    testCase "a figure that takes exactly the lines left stays on the page" $
      contents (paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FFigure 99 2 [] []]) @?= [[SLine 0, SLine 1, SLine 2, SFigure 99]],
    testCase "two figures sent on that do not fit one page together go to successive pages" $ do
      -- 2 free on page 1: both figures of 3 lines are sent on, the text moves up
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FFigure 98 3 [] [], FFigure 99 3 [] [], FParagraph defaultKeep (lines' 10 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 10, SLine 11], [SFigure 98], [SFigure 99]]
  ]

pageFigureTests :: [TestTree]
pageFigureTests =
  [ testCase "a turned figure in the middle of the text: the text fills the page, the figure takes the next one" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FPageFigure 50 ["f"] [], FParagraph defaultKeep (lines' 10 4)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 10, SLine 11], [SPageFigure 50], [SLine 12, SLine 13]]
      Map.map plIndex (labelPages Map.empty ps) @?= Map.fromList [("f", 2)],
    testCase "a turned figure met on an empty page takes that page" $
      contents (paginate 1 5 [FPageFigure 50 [] [], FParagraph defaultKeep (lines' 0 2)]) @?= [[SPageFigure 50], [SLine 0, SLine 1]],
    testCase "a figure after a turned figure waits even when it fits, and goes to the page after it" $
      contents (paginate 1 5 [FParagraph defaultKeep (lines' 0 2), FPageFigure 50 [] [], FFigure 60 1 [] [], FParagraph defaultKeep (lines' 10 2)])
        @?= [[SLine 0, SLine 1, SLine 10, SLine 11], [SPageFigure 50], [SFigure 60]],
    testCase "a waiting turned figure is placed before a forced page break" $
      contents (paginate 1 5 [FParagraph defaultKeep (lines' 0 2), FPageFigure 50 [] [], FBreak BreakPage, FParagraph defaultKeep (lines' 10 1)])
        @?= [[SLine 0, SLine 1], [SPageFigure 50], [SLine 10]],
    testCase "a waiting turned figure is placed before a column break" $
      [(poNumber p, poColumn p, map snd (poSlots p)) | p <- paginate 2 5 [FParagraph defaultKeep (lines' 0 2), FPageFigure 50 [] [], FBreak BreakColumn, FParagraph defaultKeep (lines' 10 1)]]
        @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SPageFigure 50]), (3, 0, [SLine 10])],
    testCase "a column break with only an unturned figure waiting goes to the next column (golem-driver ADR 0039)" $
      [(poNumber p, poColumn p, map snd (poSlots p)) | p <- paginate 2 5 [FParagraph defaultKeep (lines' 0 4), FFigure 60 3 [] [], FBreak BreakColumn, FParagraph defaultKeep (lines' 10 1)]]
        @?= [(1, 0, [SLine 0, SLine 1, SLine 2, SLine 3]), (1, 1, [SFigure 60, SLine 10])],
    testCase "a page break right after a turned figure met on an empty page adds no blank page (golem-driver ADR 0039)" $ do
      let ps = paginate 1 5 [FPageFigure 50 [] [], FBreak BreakPage, FParagraph defaultKeep (lines' 10 1)]
      contents ps @?= [[SPageFigure 50], [SLine 10]]
      map poBlank ps @?= [False, False],
    testCase "two or three page breaks after a waiting turned figure add no blank page (golem-driver ADR 0039)" $ do
      let flows k = [FParagraph defaultKeep (lines' 0 2), FPageFigure 50 [] []] <> replicate k (FBreak BreakPage) <> [FParagraph defaultKeep (lines' 10 1)]
      mapM_
        ( \k -> do
            let ps = paginate 1 5 (flows k)
            contents ps @?= [[SLine 0, SLine 1], [SPageFigure 50], [SLine 10]]
            any poBlank ps @?= False
        )
        [2, 3],
    testCase "a recto break after a turned figure on page 1 makes page 2 blank (golem-driver ADR 0039)" $ do
      let ps = paginate 1 5 [FPageFigure 50 [] [], FBreak BreakRecto, FParagraph defaultKeep (lines' 10 1)]
      [(poNumber p, poBlank p, map snd (poSlots p)) | p <- ps] @?= [(1, False, [SPageFigure 50]), (2, True, []), (3, False, [SLine 10])],
    testCase "a verso break after a turned figure on page 2 makes page 3 blank (golem-driver ADR 0039)" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 1), FPageFigure 50 [] [], FBreak BreakVerso, FParagraph defaultKeep (lines' 10 1)]
      [(poNumber p, poBlank p, map snd (poSlots p)) | p <- ps]
        @?= [(1, False, [SLine 0]), (2, False, [SPageFigure 50]), (3, True, []), (4, False, [SLine 10])],
    testCase "a page break on an empty first page without a turned figure still makes a blank page (golem-driver ADR 0039)" $ do
      let ps = paginate 1 5 [FBreak BreakPage, FParagraph defaultKeep (lines' 10 1)]
      map poBlank ps @?= [True, False]
      contents ps @?= [[], [SLine 10]],
    testCase "a waiting turned figure is placed before a heading at a recto" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 2), FPageFigure 50 [] [], FParagraph defaultKeep (lines' 10 1), FHeading 1 True 1 (lines' 20 1)]
      [(poNumber p, map snd (poSlots p)) | p <- ps, not (poBlank p)] @?= [(1, [SLine 0, SLine 1, SLine 10]), (2, [SPageFigure 50]), (3, [SHeading 20 1])],
    testCase "a footnote continued from the page before skips the page of a turned figure" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep [LineBox 0 [NoteBody (nid 900) 5] [] [] 0], FPageFigure 50 [] [], FParagraph defaultKeep (lines' 10 2)]
      contents ps @?= [[SLine 0], [SPageFigure 50], [SLine 10, SLine 11]]
      notesByPage ps @?= [(1, [nid 900]), (2, []), (3, [nid 900])]
  ]

{- | The label "x" on the last of k one-line pages before it, where k is
the page assumed for "x" capped at cap: the page of "x" is k + 1.
-}
creeping :: Integer -> Map.Map Text Integer -> [PageOut]
creeping cap assumed =
  let k = fromInteger (min cap (Map.findWithDefault 0 "x" assumed))
   in paginate 1 1 ([FParagraph defaultKeep [LineBox i [] [] [] 0] | i <- [0 .. k - 1]] <> [FParagraph defaultKeep [LineBox 999 [] ["x"] [] 0]])

pageRefTests :: [TestTree]
pageRefTests =
  [ testCase "a label that settles in the fifth round is resolved" $
      -- x moves 1, 2, 3, 4 and stays at 4 in round 5
      fmap (Map.map plIndex . labelPages Map.empty) (resolvePageRefs (creeping 3)) @?= Right (Map.fromList [("x", 4)]),
    testCase "a label still moving after the fifth round is named" $
      -- x moves 1, 2, 3, 4, 5
      resolvePageRefs (creeping 4) @?= Left ["x"],
    testCase "only the labels whose pages still move are named, in the order of their names" $ do
      -- "stable" fills page 1; "b" and "a" jump between page 11 and page 3
      let layout assumed =
            let fillers = if Map.findWithDefault 1 "a" assumed < 10 then 9 else 1
             in paginate 1 5 $
                  FParagraph defaultKeep (LineBox 0 [] ["stable"] [] 0 : lines' 1 4)
                    : replicate fillers (FParagraph defaultKeep (lines' 10 5))
                      <> [FParagraph defaultKeep [LineBox 999 [] ["b", "a"] [] 0]]
      resolvePageRefs layout @?= Left ["a", "b"]
  ]

-- | A block of the generated flows: a paragraph of n lines, or a heading of one line and a span.
data Block = Para !Int | Head !Int
  deriving stock (Show)

genBlocks :: Gen [Block]
genBlocks = Gen.list (Range.linear 0 30) (Gen.choice [Para <$> Gen.int (Range.linear 1 7), Head <$> Gen.int (Range.linear 1 2)])

-- | The flows of the blocks with their lines numbered in order from 0.
flowsOf :: [Block] -> [Flow]
flowsOf = go 0
  where
    go _ [] = []
    go i (Para n : rest) = FParagraph defaultKeep (lines' i n) : go (i + n) rest
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
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 9), FParagraph defaultKeep (lines' 10 5)]) @?= [[0 .. 8], [10 .. 14]]
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 9), FNoBreak mk, FParagraph defaultKeep (lines' 10 5)]
      lineIds ps @?= [[0 .. 6], [7, 8, 10, 11, 12, 13, 14]]
      unmets ps @?= [],
    testCase "no-break: a paragraph of two lines, or of three, goes whole" $ do
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 7), FParagraph defaultKeep (lines' 20 2), FNoBreak mk, FParagraph defaultKeep (lines' 30 5)])
        @?= [[0 .. 6], [20, 21, 30, 31, 32, 33, 34]]
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 6), FParagraph defaultKeep (lines' 20 3), FNoBreak mk, FParagraph defaultKeep (lines' 30 5)])
        @?= [[0 .. 5], [20, 21, 22, 30, 31, 32, 33, 34]],
    testCase "no-break: a paragraph of four lines leaves two and sends the last two (docs/adr ADR 0055)" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 5), FParagraph defaultKeep (lines' 20 4), FNoBreak mk, FParagraph defaultKeep (lines' 30 5)]
      lineIds ps @?= [[0, 1, 2, 3, 4, 20, 21], [22, 23, 30, 31, 32, 33, 34]]
      unmets ps @?= [],
    testCase "no-break: nothing is sent from an empty column, and the control is unmet" $ do
      let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 3), FNoBreak mk, FParagraph defaultKeep (lines' 10 5)]
      lineIds ps @?= [[0, 1, 2], [10, 11, 12], [13, 14]]
      unmets ps @?= [UnmetNoBreak mk],
    testCase "no-break after a figure sent on is unmet" $
      unmets (paginate 1 5 [FParagraph defaultKeep (lines' 0 4), FFigure 99 3 [] [], FNoBreak mk, FParagraph defaultKeep (lines' 10 2)]) @?= [UnmetNoBreak mk],
    testCase "the controls after a heading do not change keeping it with what follows" $ do
      let plain = [FParagraph defaultKeep (lines' 0 3), heading 20, FParagraph defaultKeep (lines' 30 2)]
          marked = [FParagraph defaultKeep (lines' 0 3), heading 20, FNeedLines mk 1, FNoBreak mk, FParagraph defaultKeep (lines' 30 2)]
      contents (paginate 1 5 marked) @?= contents (paginate 1 5 plain)
      unmets (paginate 1 5 marked) @?= [],
    testCase "need-lines goes to the next column only when the column is short" $ do
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 6), FNeedLines mk 5, FParagraph defaultKeep (lines' 10 2)]) @?= [[0 .. 5], [10, 11]]
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 6), FNeedLines mk 4, FParagraph defaultKeep (lines' 10 2)]) @?= [[0, 1, 2, 3, 4, 5, 10, 11]]
      lineIds (paginate 1 10 [FNeedLines mk 5, FParagraph defaultKeep (lines' 0 2)]) @?= [[0, 1]],
    testCase "need-lines in two columns goes to the next column" $
      columnsOf (paginate 2 10 [FParagraph defaultKeep (lines' 0 6), FNeedLines mk 5, FParagraph defaultKeep (lines' 10 2)]) @?= [(1, 0, [0 .. 5]), (1, 1, [10, 11])],
    testCase "need-lines beyond the column is unmet and goes to the next column" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 6), FNeedLines mk 20, FParagraph defaultKeep (lines' 10 2)]
      lineIds ps @?= [[0 .. 5], [10, 11]]
      unmets ps @?= [UnmetNeedLines mk 20],
    testCase "controls at the end of the book make no page; the last no-break is unmet" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 2), FNeedLines mk 3, FNoBreak mk]
      lineIds ps @?= [[0, 1]]
      unmets ps @?= [UnmetNoBreak mk],
    testCase "page-lines +1 gives the column one more line, and the next column its own" $ do
      let ps = paginate 1 10 [FAdjustLines mk 1, FParagraph defaultKeep (lines' 0 11), FParagraph defaultKeep (lines' 20 3)]
      lineIds ps @?= [[0 .. 10], [20, 21, 22]]
      map poLines ps @?= [11, 10]
      unmets ps @?= [],
    testCase "page-lines -1 leaves the column a line short" $ do
      let ps = paginate 1 10 [FAdjustLines mk (-1), FParagraph defaultKeep (lines' 0 12)]
      lineIds ps @?= [[0 .. 8], [9, 10, 11]]
      map poLines ps @?= [9, 10],
    testCase "page-lines beyond the limit is cut to it and unmet" $ do
      let ps = paginateWithin 11 1 (ColumnSet 1 0 0 0) 10 [FAdjustLines mk 1, FAdjustLines mk 1, FParagraph defaultKeep (lines' 0 12)]
      map poLines ps @?= [11, 10]
      unmets ps @?= [UnmetAdjust mk 1 AdjustNoRoom],
    testCase "page-lines below the lines placed is cut to them and unmet" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 8), FAdjustLines mk (-5), FParagraph defaultKeep (lines' 10 2)]
      lineIds ps @?= [[0 .. 7], [10, 11]]
      map poLines ps @?= [8, 10]
      unmets ps @?= [UnmetAdjust mk (-2) AdjustLinesPlaced],
    testCase "the footnotes of a column of page-lines +1 use its last line" $ do
      -- nine lines, the separator and a note of one line take eleven lines
      let flow = [FAdjustLines mk 1, FParagraph defaultKeep (LineBox 0 [NoteBody (nid 900) 1] [] [] 0 : lines' 1 8)]
          ps = paginate 1 10 flow
      map poLines ps @?= [11]
      notesByPage ps @?= [(1, [nid 900])]
      lineIds ps @?= [[0 .. 8]],
    testCase "no-break at the start of the book has nothing before it and is unmet" $
      unmets (paginate 1 10 [FNoBreak mk, FParagraph defaultKeep (lines' 0 2)]) @?= [UnmetNoBreak mk],
    testCase "no-break before a figure that waits behind one sent on is unmet" $ do
      -- 2 free: figure 98 of 4 lines is sent on, the line moves up, figure 99 waits behind 98
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FFigure 98 4 [] [], FParagraph defaultKeep (lines' 10 1), FNoBreak mk, FFigure 99 1 [] []]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 10], [SFigure 98, SFigure 99]]
      unmets ps @?= [UnmetNoBreak mk],
    testCase "no-break keeps the last lines with what follows across need-lines and a space before it" $ do
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 9), FNeedLines mk 1, FNoBreak mk, FParagraph defaultKeep (lines' 10 5)]) @?= [[0 .. 6], [7, 8, 10, 11, 12, 13, 14]]
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 9), FSpace 1, FNoBreak mk, FParagraph defaultKeep (lines' 10 5)]) @?= [[0 .. 6], [7, 8, 10, 11, 12, 13, 14]],
    testCase "page-lines after a heading does not change keeping it with what follows" $
      -- 2 free: heading 1 + two lines = 3 > 2, as without page-lines
      contents (paginate 1 5 [FParagraph defaultKeep (lines' 0 3), heading 20, FAdjustLines mk 1, FParagraph defaultKeep (lines' 30 2)])
        @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 30, SLine 31]],
    testCase "of two need-lines in a row the larger applies" $ do
      -- 4 free: 3 would stay, 5 goes to the next column, whichever comes first
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 6), FNeedLines mk 3, FNeedLines mk2 5, FParagraph defaultKeep (lines' 10 2)]) @?= [[0 .. 5], [10, 11]]
      lineIds (paginate 1 10 [FParagraph defaultKeep (lines' 0 6), FNeedLines mk2 5, FNeedLines mk 3, FParagraph defaultKeep (lines' 10 2)]) @?= [[0 .. 5], [10, 11]],
    testCase "need-lines of exactly the lines of a column is met" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 6), FNeedLines mk 10, FParagraph defaultKeep (lines' 10 2)]
      lineIds ps @?= [[0 .. 5], [10, 11]]
      unmets ps @?= [],
    testCase "page-lines leaves a column at least one line" $ do
      let ps = paginate 1 10 [FAdjustLines mk (-10), FParagraph defaultKeep (lines' 0 3)]
      take 1 (map poLines ps) @?= [1]
      -- the first line alone in a column of one line is a short first part (docs/adr/0261)
      unmets ps @?= [UnmetAdjust mk (-9) AdjustOneLine, ShortPart FirstPart 0 2 1]
  ]

-- | On one column of ten grid lines (docs/adr ADR 0046).
blankLineTests :: [TestTree]
blankLineTests =
  [ testCase "blank lines take grid lines before what follows" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 3), FBlank mk 2, FParagraph defaultKeep (lines' 10 2)]
      gridLines ps @?= [[0, 1, 2, 5, 6]]
      unmets ps @?= [],
    testCase "blank lines and the first part of what follows go to the next column together, and the blank lines are dropped there" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 9), FBlank mk 1, FParagraph defaultKeep (lines' 10 3)]
      lineIds ps @?= [[0 .. 8], [10, 11, 12]]
      gridLines ps @?= [[0 .. 8], [0, 1, 2]]
      unmets ps @?= [DroppedBlank mk],
    testCase "blank lines after a full column are dropped" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 10), FBlank mk 1, FParagraph defaultKeep (lines' 10 2)]
      gridLines ps @?= [[0 .. 9], [0, 1]]
      unmets ps @?= [DroppedBlank mk],
    testCase "blank lines after a page break are dropped" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 2), FBreak BreakPage, FBlank mk 3, FParagraph defaultKeep (lines' 10 2)]
      gridLines ps @?= [[0, 1], [0, 1]]
      unmets ps @?= [DroppedBlank mk],
    testCase "blank lines at the start of the book are dropped" $ do
      let ps = paginate 1 10 [FBlank mk 2, FParagraph defaultKeep (lines' 0 2)]
      gridLines ps @?= [[0, 1]]
      unmets ps @?= [DroppedBlank mk],
    testCase "each blank line dropped is recorded" $
      unmets (paginate 1 10 [FBlank mk 1, FBlank mk2 2, FParagraph defaultKeep (lines' 0 2)]) @?= [DroppedBlank mk, DroppedBlank mk2],
    testCase "blank lines longer than the rest of the column are dropped whole, not cut" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 3), FBlank mk 20, FParagraph defaultKeep (lines' 10 2)]
      gridLines ps @?= [[0, 1, 2], [0, 1]]
      unmets ps @?= [DroppedBlank mk],
    testCase "blank lines before a heading that starts at a recto are dropped at the recto" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 3), FBlank mk 2, FHeading 1 True 1 (lines' 20 1), FParagraph defaultKeep (lines' 30 2)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [], [SHeading 20 1, SLine 30, SLine 31]]
      map poBlank ps @?= [False, True, False]
      gridLines ps @?= [[0, 1, 2], [], [0, 1, 2]]
      unmets ps @?= [DroppedBlank mk],
    testCase "a heading is kept with the blank lines and the first two lines after it" $ do
      gridLines (paginate 1 10 [FParagraph defaultKeep (lines' 0 5), heading 20, FBlank mk 2, FParagraph defaultKeep (lines' 30 2)]) @?= [[0, 1, 2, 3, 4, 5, 8, 9]]
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 6), heading 20, FBlank mk 2, FParagraph defaultKeep (lines' 30 2)]
      gridLines ps @?= [[0 .. 5], [0, 3, 4]]
      unmets ps @?= [],
    testCase "a no-break keeps the last lines, the blank lines and the first lines after it together" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 9), FNoBreak mk, FBlank mk2 1, FParagraph defaultKeep (lines' 10 5)]
      lineIds ps @?= [[0 .. 6], [7, 8, 10, 11, 12, 13, 14]]
      gridLines ps @?= [[0 .. 6], [0, 1, 3, 4, 5, 6, 7]]
      unmets ps @?= [],
    testCase "a table after blank lines keeps its space before" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 2), FBlank mk 1, FTable 50 1 [] [lines' 30 1] [] False]
      map (map tsFirst . poTables) ps @?= [[4]]
  ]

figureOrderTests :: [TestTree]
figureOrderTests =
  [ testCase "Golem ADR 0352 I3: two figures and one blank use the modeled source order" $ do
      let line = FParagraph defaultKeep (lines' 0 1)
          first = FFigure 1000 2 [] []
          second = FFigure 1001 1 [] []
          cases =
            [ ([line, FBlank mk 1, first, second], [0, 2, 4], []),
              ([line, first, FBlank mk 1, second], [0, 1, 4], []),
              ([line, first, second, FBlank mk 1], [0, 1, 3], [])
            ]
      forM_ cases $ \(flows, positions, dropped) -> do
        let ps = paginate 1 5 flows
        contents ps @?= [[SLine 0, SFigure 1000, SFigure 1001]]
        gridLines ps @?= [positions]
        unmets ps @?= dropped,
    testCase "a figure after a figure sent on is sent on after it" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 3), FFigure 98 3 [] [], FParagraph defaultKeep (lines' 10 1), FFigure 99 1 [] []]
      contents ps @?= [[SLine 0, SLine 1, SLine 2, SLine 10], [SFigure 98, SFigure 99]],
    testCase "in two columns, a figure after a figure sent on goes to the next column after it" $ do
      let ps = paginate 2 5 [FParagraph defaultKeep (lines' 0 3), FFigure 98 3 [] [], FParagraph defaultKeep (lines' 10 1), FFigure 99 1 [] []]
      [(poNumber p, poColumn p, map snd (poSlots p)) | p <- ps]
        @?= [(1, 0, [SLine 0, SLine 1, SLine 2, SLine 10]), (1, 1, [SFigure 98, SFigure 99])],
    testCase "a wrapped figure after a figure sent on goes with its lines after it" $ do
      let ps = paginate 1 6 [FParagraph defaultKeep (lines' 0 3), FFigure 98 4 [] [], FWrapped 99 2 [] [] (lines' 10 2), FParagraph defaultKeep (lines' 20 1)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SFigure 98, SWrapped 99, SLine 10, SLine 11], [SLine 20]]
  ]

-- | A block of the generated flows with figures: a paragraph, a figure of n lines, or a wrapped figure of n lines with k lines beside it.
data FigBlock = FPara !Int | FFig !Int | FWrap !Int !Int
  deriving stock (Show)

genFigBlocks :: Gen [FigBlock]
genFigBlocks =
  Gen.list
    (Range.linear 0 30)
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
    go i j (FPara n : rest) = FParagraph defaultKeep (lines' i n) : go (i + n) j rest
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
      capacity <- forAll (Gen.int (Range.linear 1 9))
      columns <- forAll (Gen.int (Range.linear 1 2))
      placedFigures (paginate columns capacity (figFlowsOf blocks)) === [1000 .. 1000 + figBlockFigures blocks - 1],
    testProperty "every line and every figure is placed exactly once" $ property $ do
      blocks <- forAll genFigBlocks
      capacity <- forAll (Gen.int (Range.linear 1 9))
      columns <- forAll (Gen.int (Range.linear 1 2))
      let ps = paginate columns capacity (figFlowsOf blocks)
      placedIds ps === [0 .. figBlockLines blocks - 1]
      length (placedFigures ps) === figBlockFigures blocks,
    testProperty "every line of paragraphs and headings is placed once, in the order written" $ property $ do
      blocks <- forAll genBlocks
      capacity <- forAll (Gen.int (Range.linear 1 9))
      placedIds (paginate 1 capacity (flowsOf blocks)) === [0 .. lineCount blocks - 1],
    testProperty "an empty flow gives one empty page (docs/adr/0067)" $ property $ do
      capacity <- forAll (Gen.int (Range.linear 1 9))
      columns <- forAll (Gen.int (Range.linear 1 2))
      [(poNumber p, poSlots p) | p <- paginate columns capacity []] === [(1, [])],
    testProperty "pages are numbered from 1 without gaps" $ property $ do
      blocks <- forAll genBlocks
      capacity <- forAll (Gen.int (Range.linear 1 9))
      let ps = paginate 1 capacity (flowsOf blocks)
      map poNumber ps === [1 .. length ps],
    testProperty "every slot starts on a grid line of the page" $ property $ do
      blocks <- forAll genBlocks
      capacity <- forAll (Gen.int (Range.linear 1 9))
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

-- | A heading placed in an empty column it does not fit is recorded (golem-layout ADR 0020).
tallHeadingTests :: [TestTree]
tallHeadingTests =
  [ testCase "a heading of two grid lines on a page of one line" $ do
      let ps = paginate 1 1 [FHeading 2 False 2 (lines' 0 1), FParagraph defaultKeep (lines' 10 1)]
      map poUnmet ps @?= [[TallHeading 0 2 1], []]
      contents ps @?= [[SHeading 0 1], [SLine 10]],
    testCase "a heading of five grid lines in a column cut to one line by page-lines" $ do
      let ps = paginate 1 16 [FAdjustLines mk (-15), FHeading 1 False 5 (lines' 0 1), FParagraph defaultKeep (lines' 10 1)]
      unmets ps @?= [TallHeading 0 5 1]
      contents ps @?= [[SHeading 0 1], [SLine 10]]
      map poLines ps @?= [1, 16],
    testCase "a heading of five grid lines in a column of five lines is not recorded" $ do
      let ps = paginate 1 16 [FAdjustLines mk (-11), FHeading 1 False 5 (lines' 0 1), FParagraph defaultKeep (lines' 10 1)]
      unmets ps @?= []
      contents ps @?= [[SHeading 0 1], [SLine 10]],
    testCase "a heading that does not fit a column with lines goes to the next column and is not recorded" $ do
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 4), FHeading 2 False 2 (lines' 10 1), FParagraph defaultKeep (lines' 20 1)]
      unmets ps @?= []
      contents ps @?= [map SLine [0 .. 3], [SHeading 10 1, SLine 20]],
    testCase "a ruled heading that does not fit a column of one line without its rules is recorded" $ do
      let h = FRuled 20 (Just (spaced 5 10)) (Just (spaced 5 10)) False ruleGrid 0 (RuledHeading False 2 (lines' 20 1))
          ps = paginate 1 1 [h, FParagraph defaultKeep (lines' 30 1)]
      unmets ps @?= [TallHeading 20 2 1]
      contents ps @?= [[SHeading 20 1], [SLine 30]],
    testCase "a heading whose grid lines fit and whose note does not is not recorded" $ do
      let ps = paginate 1 5 [FHeading 2 False 1 [LineBox 20 [NoteBody (nid 900) 6] [] [] 0]]
      unmets ps @?= [],
    testProperty "the headings recorded are those that end past the column" $ property $ do
      blocks <- forAll genBlocks
      capacity <- forAll (Gen.int (Range.linear 1 9))
      let ps = paginate 1 capacity (flowsOf blocks)
          spans = Map.fromList (headingSpansOf 0 blocks)
          past = [l | p <- ps, (k, SHeading l _) <- poSlots p, k + Map.findWithDefault 1 l spans > capacity]
      [l | TallHeading l _ _ <- unmets ps] === past
  ]
  where
    headingSpansOf :: Int -> [Block] -> [(Int, Int)]
    headingSpansOf _ [] = []
    headingSpansOf i (Para n : rest) = headingSpansOf (i + n) rest
    headingSpansOf i (Head k : rest) = (i, k) : headingSpansOf (i + 1) rest

-- | Size 10pt, pitch 17pt, in sp.
ruleGrid :: RuleGrid
ruleGrid = RuleGrid (17 * 65536) (10 * 65536)

-- | A rule of 0.5pt with an inner and an outer space in pt.
spaced :: Sp -> Sp -> RuleSide
spaced i o = RuleSide (i * 65536) (o * 65536) 32768 True Nothing

-- | A rule of 0.3pt without spaces: no grid line inside a column.
bare :: RuleSide
bare = RuleSide 0 0 19661 False Nothing

-- | A paragraph with rules: its id is that of its first line.
ruled :: Maybe RuleSide -> Maybe RuleSide -> [LineBox] -> Flow
ruled b a ls = FRuled (maybe 0 lbId (listToMaybe' ls)) b a False ruleGrid 0 (RuledLines defaultKeep ls)
  where
    listToMaybe' = foldr (const . Just) Nothing

-- | The slots of each page.
gridLines :: [PageOut] -> [[Int]]
gridLines = map (map fst . poSlots)

ruledTests :: [TestTree]
ruledTests =
  [ testCase "keep-in-column = false at the start of columns that start mid-page: in the column, as keep-in-column = true (golem-driver ADR 0040)" $ do
      let outside = (spaced 5 10) {rsdOutside = Just (100 * 65536)}
          flows b = [FParagraph defaultKeep (lines' 0 2), FSwitchColumns (ColumnSet 2 0 0 0), ruled (Just b) Nothing (lines' 10 1)]
          inside = paginateIn 1 (ColumnSet 1 0 0 0) 10 (flows (spaced 5 10))
          out = paginateIn 1 (ColumnSet 1 0 0 0) 10 (flows outside)
      map poRules out @?= map poRules inside
      gridLines out @?= gridLines inside
      -- the area of the rule takes a grid line after the two lines before
      gridLines out @?= [[0, 1], [3]],
    testCase "a ruled paragraph that does not fit goes whole to the next column, its rule counted at the start" $ do
      -- 3 free; a line of area before (inner 5pt, outer 10pt) and 3 lines
      let ps = paginate 1 5 [FParagraph defaultKeep (lines' 0 2), ruled (Just (spaced 5 10)) Nothing (lines' 10 3)]
      gridLines ps @?= [[0, 1], [1, 2, 3]]
      map poRules ps @?= [[], [PlacedRule 10 True (17 * 65536 - 5 * 65536 - 32768)]],
    testCase "a paragraph is split at the column end, a ruled one is not" $ do
      gridLines (paginate 1 8 [FParagraph defaultKeep (lines' 0 4), FParagraph defaultKeep (lines' 10 6)]) @?= [[0 .. 7], [0, 1]]
      gridLines (paginate 1 8 [FParagraph defaultKeep (lines' 0 4), ruled Nothing (Just bare) (lines' 10 6)]) @?= [[0 .. 3], [0 .. 5]],
    testCase "a ruled paragraph stays where it is; the note that does not fit goes to the next page" $ do
      let withNote = LineBox 10 [NoteBody (nid 900) 4] [] [] 0
          ps = paginate 1 6 [FParagraph defaultKeep (lines' 0 2), ruled (Just bare) Nothing (withNote : lines' 11 1)]
      gridLines ps @?= [[0, 1, 2, 3], []]
      -- the rest of the note is on the next page
      map poFootnotes ps @?= [[(nid 900, 0, 1)], [(nid 900, 1, 3)]],
    testCase "a ruled heading whose note does not fit goes on with its note and its rule (golem-layout ADR 0013)" $ do
      let h = FRuled 20 (Just (spaced 5 10)) Nothing False ruleGrid 0 (RuledHeading False 1 [LineBox 20 [NoteBody (nid 900) 2] [] [] 0])
          ps = paginate 1 6 [FParagraph defaultKeep (lines' 0 3), h, FParagraph defaultKeep (lines' 30 1)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 30]]
      gridLines ps @?= [[0, 1, 2], [1, 2]]
      notesByPage ps @?= [(1, []), (2, [nid 900])],
    testCase "a heading before a ruled paragraph of 5 lines goes on with it" $ do
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 3), heading 20, ruled (Just bare) Nothing (lines' 30 5)]
      contents ps @?= [[SLine 0, SLine 1, SLine 2], SHeading 20 1 : map SLine [30 .. 34]],
    testCase "a rule after and a rule before in a row share one area; with space-between they do not" $ do
      let a = ruled Nothing (Just (spaced 2 3)) (lines' 0 2)
          b = FRuled 10 (Just (spaced 2 6)) Nothing True ruleGrid 0 (RuledLines defaultKeep (lines' 10 2))
          b' = FRuled 10 (Just (spaced 2 6)) Nothing False ruleGrid 0 (RuledLines defaultKeep (lines' 10 2))
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
          b joined = FRuled 10 (Just (spaced 2 6)) (Just (spaced 2 6)) joined ruleGrid 0 (RuledLines defaultKeep (lines' 10 8))
          rules = concatMap poRules (paginate 1 5 [a, b True])
      [(prId r, prBefore r) | r <- rules] @?= [(0, False)]
      rules @?= concatMap poRules (paginate 1 5 [a, FSpace 0, b False]),
    testCase "the rule before after a split paragraph is a rule of its own (golem-driver ADR 0035)" $ do
      let b = FRuled 10 (Just (spaced 2 6)) (Just (spaced 2 6)) False ruleGrid 0 (RuledLines defaultKeep (lines' 10 6))
          c joined = FRuled 30 (Just (spaced 2 6)) Nothing joined ruleGrid 0 (RuledLines defaultKeep (lines' 30 1))
          rulesOf j = map poRules (paginate 1 5 [b, c j])
      [(prId r, prBefore r) | r <- concat (rulesOf True)] @?= [(30, True)]
      rulesOf True @?= rulesOf False,
    testCase "a ruled paragraph that ends at the column end counts its rule at the edge" $ do
      -- inside: inner 5pt, outer 30pt take 2 lines; at the end 1 line
      let ps = paginate 1 4 [ruled Nothing (Just (spaced 5 30)) (lines' 0 3)]
      gridLines ps @?= [[0, 1, 2]]
      map poRules ps @?= [[PlacedRule 0 False (2 * 17 * 65536 + 10 * 65536 + 5 * 65536)]]
  ]

-- | The flows of n lines of each kind a heading keeps the first part of, numbered from 30.
splittable :: Int -> [(String, Flow)]
splittable n = [("paragraph", FParagraph defaultKeep (lines' 30 n)), ("continued", FContinued defaultKeep (lines' 30 n)), ("stanza", stanza 30 (replicate n 1))]

-- | The lines a look-ahead keeps of n lines (or verse lines): all of three or fewer, two of more.
keptOf :: Int -> Int
keptOf n = if n >= 4 then 2 else n

-- | The ids of the lines from 30 on, on each page.
laterIds :: [PageOut] -> [[Int]]
laterIds = map (filter (>= 30)) . lineIds

splitPartTests :: [TestTree]
splitPartTests =
  [ testCase "K3: the look-ahead counts all of three lines or fewer and two of more" $
      sequence_
        [ assertEqual (kind <> " of " <> show n) (keptOf n) (needGrid (lookAhead 20 [f]))
        | n <- [1 .. 6],
          (kind, f) <- splittable n
        ],
    testCase "K3: the look-ahead of a stanza counts the lines its verse lines are broken into" $ do
      needGrid (lookAhead 20 [stanza 30 [1, 2, 1]]) @?= 4
      needGrid (lookAhead 20 [stanza 30 [2, 1, 1, 1]]) @?= 3
      needGrid (lookAhead 20 [stanza 30 [1, 1, 3, 1, 1]]) @?= 2,
    testCase "K3: the look-ahead counts the notes of the lines it counts" $ do
      needNotes (lookAhead 20 [FParagraph defaultKeep (lines' 30 1 <> [noted 31 2] <> lines' 32 1)]) @?= 2
      needNotes (lookAhead 20 [FParagraph defaultKeep (lines' 30 2 <> [noted 32 2] <> lines' 33 1)]) @?= 0,
    testCase "K2: with room for the look-ahead, at least the first two lines are placed in the column" $
      sequence_
        [ assertBool (kind <> " of " <> show n <> " with " <> show r <> " lines left") (length (concat (take 1 (laterIds ps))) >= min 2 n)
        | n <- [1 .. 6],
          r <- [0 .. 8],
          (kind, f) <- splittable n,
          r >= needGrid (lookAhead 10 [f]),
          let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 (10 - r)), f]
        ],
    testCase "K1: a heading goes on with a paragraph of three lines that cannot leave two of them" $
      contents (paginate 1 8 [FParagraph defaultKeep (lines' 0 5), heading 20, FParagraph defaultKeep (lines' 30 3)])
        @?= [map SLine [0 .. 4], [SHeading 20 1, SLine 30, SLine 31, SLine 32]],
    testCase "K1: a heading goes on with the three lines that continue a paragraph after a figure" $
      contents (paginate 1 8 [FParagraph defaultKeep (lines' 0 5), heading 20, FContinued defaultKeep (lines' 30 3)])
        @?= [map SLine [0 .. 4], [SHeading 20 1, SLine 30, SLine 31, SLine 32]],
    testCase "K1: a heading goes on with a stanza of three verse lines" $
      contents (paginate 1 8 [FParagraph defaultKeep (lines' 0 5), heading 20, stanza 30 [1, 1, 1]])
        @?= [map SLine [0 .. 4], [SHeading 20 1, SLine 30, SLine 40, SLine 50]],
    testCase "K1: a paragraph before a no-break goes on with a paragraph of three lines" $ do
      let ps = paginate 1 8 [FParagraph defaultKeep (lines' 0 4), FParagraph defaultKeep (lines' 20 2), FNoBreak mk, FParagraph defaultKeep (lines' 30 3)]
      lineIds ps @?= [[0 .. 3], [20, 21, 30, 31, 32]]
      unmets ps @?= [],
    testCase "K1: a heading goes on with a paragraph of three lines whose second line has a note" $ do
      -- 5 left: heading 1 + three lines + note 1 + separator 1 = 6; two lines would fit but leave a widow
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 5), heading 20, FParagraph defaultKeep (lines' 30 1 <> [noted 31 1] <> lines' 32 1)]
      contents ps @?= [map SLine [0 .. 4], [SHeading 20 1, SLine 30, SLine 31, SLine 32]]
      notesByPage ps @?= [(1, []), (2, [nid 900])],
    testCase "K1: a heading still stays with the first two lines of a paragraph of four" $
      contents (paginate 1 8 [FParagraph defaultKeep (lines' 0 5), heading 20, FParagraph defaultKeep (lines' 30 4)])
        @?= [map SLine [0 .. 4] <> [SHeading 20 1, SLine 30, SLine 31], [SLine 32, SLine 33]]
  ]

keptSpaceTests :: [TestTree]
keptSpaceTests =
  [ testCase "N1: the look-ahead of a no-break counts the spaces before and after it, at most a column" $
      sequence_
        [ assertEqual (show (a, b)) (Just (min 10 (sum a + sum b + 2))) (needGrid <$> keptLookAhead 10 flows)
        | a <- spaces,
          b <- spaces,
          before <- [map FSpace a, [FNeedLines mk 1] <> map FSpace a <> [FAdjustLines mk 0]],
          let flows = before <> [FNoBreak mk] <> map FSpace b <> [FParagraph defaultKeep (lines' 30 5)]
        ],
    testCase "N1: without a no-break after the spaces nothing is kept" $
      needGrid <$> keptLookAhead 10 [FSpace 1, FParagraph defaultKeep (lines' 30 5)] @?= Nothing,
    testCase "N2: the last two lines go on with the space and the first two lines after the no-break" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 8), FNoBreak mk, FSpace 1, FParagraph defaultKeep (lines' 10 5)]
      lineIds ps @?= [[0 .. 5], [6, 7, 10, 11, 12, 13, 14]]
      gridLines ps @?= [[0 .. 5], [0, 1, 3, 4, 5, 6, 7]]
      unmets ps @?= [],
    testCase "N2: the same with the space before the no-break" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 8), FSpace 1, FNoBreak mk, FParagraph defaultKeep (lines' 10 5)]
      lineIds ps @?= [[0 .. 5], [6, 7, 10, 11, 12, 13, 14]]
      unmets ps @?= [],
    testCase "N2: the lines stay when the space and the first two lines after it just fit" $ do
      let ps = paginate 1 10 [FParagraph defaultKeep (lines' 0 7), FNoBreak mk, FSpace 1, FParagraph defaultKeep (lines' 10 5)]
      lineIds ps @?= [[0 .. 6] <> [10, 11], [12, 13, 14]]
      unmets ps @?= []
  ]
  where
    -- no space, and spaces of 1, C - 1, C and C + 1 lines in a column of 10
    spaces = [[], [1], [9], [10], [11]]

addedRuleTests :: [TestTree]
addedRuleTests =
  [ testCase "R1: the space after a heading counts in what follows, at most a column" $ do
      needGrid (lookAhead 10 [FParagraph defaultKeep (lines' 30 5)]) @?= 2
      needGrid (lookAhead 10 [FSpace 1, FParagraph defaultKeep (lines' 30 5)]) @?= 3
      needGrid (lookAhead 10 [FSpace 9, FParagraph defaultKeep (lines' 30 5)]) @?= 10
      needGrid (lookAhead 10 [FSpace 10, FParagraph defaultKeep (lines' 30 5)]) @?= 10,
    testCase "R2: a stanza before a no-break keeps its last part with what follows" $
      sequence_
        [ assertEqual (show v <> " verse lines") [[0 .. f - 1] <> take (v - k) verses, drop (v - k) verses <> [200, 201]] (lineIds ps)
        | v <- [1 .. 4],
          let k = if v <= 3 then v else 2
              f = 5 - v
              verses = [100 + 10 * i | i <- [0 .. v - 1]]
              ps = paginate 1 6 [FParagraph defaultKeep (lines' 0 f), stanza 100 (replicate v 1), FNoBreak mk, FParagraph defaultKeep (lines' 200 2)]
        ],
    testCase "R2: a stanza stays when its last part and what follows just fit" $
      sequence_
        [ assertEqual (show v <> " verse lines") [[0 .. 3 - v] <> [100 + 10 * i | i <- [0 .. v - 1]] <> [200, 201]] (lineIds (paginate 1 6 [FParagraph defaultKeep (lines' 0 (4 - v)), stanza 100 (replicate v 1), FNoBreak mk, FParagraph defaultKeep (lines' 200 2)]))
        | v <- [1 .. 3]
        ],
    testCase "R2: a stanza from an empty column is not sent on" $ do
      let ps = paginate 1 4 [stanza 100 [1, 1, 1], FNoBreak mk, FParagraph defaultKeep (lines' 200 2)]
      lineIds ps @?= [[100, 110, 120], [200, 201]]
      unmets ps @?= [UnmetNoBreak mk]
  ]

-- | Page, column and the slots of each column of an input of PaginateEnum.
placedIn :: Input -> [(Int, Int, [Slotted])]
placedIn input = [(poNumber p, poColumn p, map snd (poSlots p)) | p <- paginateInput input]

undecidedPointTests :: [TestTree]
undecidedPointTests =
  [ testCase "D1: a heading before a heading at a recto counts nothing after it" $ do
      let flows = [heading 20, FHeading 1 True 1 (lines' 21 1), FParagraph defaultKeep (lines' 30 1)]
      needGrid (lookAhead 3 flows) @?= 1
      needNotes (lookAhead 3 flows) @?= 0
      needGrid (lookAhead 3 [FHeading 1 True 1 (lines' 21 1), FParagraph defaultKeep (lines' 30 1)]) @?= 0,
    testCase "D1: a heading before a heading at a recto stays at the end of its page, and page 2 is blank" $ do
      let input = Input 3 1 [EPara 2, EHeading, ERecto, EPara 1]
      placedIn input
        @?= [(1, 0, [SLine 0, SLine 1, SHeading 2 1]), (2, 0, []), (3, 0, [SHeading 3 1, SLine 4])]
      [(poNumber p, poBlank p) | p <- paginateInput input] @?= [(1, False), (2, True), (3, False)],
    testCase "D2: a column of nothing but a heading places the lines of the paragraph after it, as an empty column does" $
      placedIn (Input 3 1 [EHeading, EPara 3])
        @?= [(1, 0, [SHeading 0 1, SLine 1, SLine 2]), (2, 0, [SLine 3])]
  ]

-- | The page, column, slots and notes of each column.
placedWithNotes :: [PageOut] -> [(Int, Int, [Slotted], [NoteId])]
placedWithNotes ps = [(poNumber p, poColumn p, map snd (poSlots p), [n | (n, _, _) <- poFootnotes p]) | p <- ps]

-- | A term of one line.
term :: Int -> Flow
term i = FDefTerm (lines' i 1)

-- | A ruled heading of one line without rules.
ruledHeading :: Bool -> Int -> Flow
ruledHeading recto i = FRuled i Nothing Nothing False ruleGrid 0 (RuledHeading recto 1 (lines' i 1))

keepAfterFiguresTests :: [TestTree]
keepAfterFiguresTests =
  [ testCase "F1: a heading after a figure sent on goes on past it with its paragraph" $
      placedIn (Input 3 1 [EPara 2, EFigure 2, EHeading, EPara 1])
        @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000]), (3, 0, [SHeading 2 1, SLine 3])],
    testCase "F1: a heading after two figures sent on goes on past both" $
      placedIn (Input 3 1 [EPara 2, EFigure 2, EFigure 2, EHeading, EPara 1])
        @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000]), (3, 0, [SFigure 1001]), (4, 0, [SHeading 2 1, SLine 3])],
    testCase "F1: in two columns, a heading after a figure sent on goes on past it" $
      placedIn (Input 3 2 [EPara 2, EFigure 2, EHeading, EPara 1])
        @?= [(1, 0, [SLine 0, SLine 1]), (1, 1, [SFigure 1000]), (2, 0, [SHeading 2 1, SLine 3])],
    testCase "F1: in two columns, a heading after two figures sent on goes on past both" $
      placedIn (Input 3 2 [EPara 2, EFigure 2, EFigure 2, EHeading, EPara 1])
        @?= [(1, 0, [SLine 0, SLine 1]), (1, 1, [SFigure 1000]), (2, 0, [SFigure 1001]), (2, 1, [SHeading 2 1, SLine 3])],
    testCase "F2: a heading with a note after a figure sent on goes on with its note" $
      placedWithNotes (paginateInput (Input 3 1 [EPara 1, EFigure 3, EFigure 1, ENotedHeading]))
        @?= [(1, 0, [SLine 0], []), (2, 0, [SFigure 1000], []), (3, 0, [SFigure 1001], []), (4, 0, [SHeading 1 1], [noteOf 1])],
    testCase "F1: a term after a figure sent on goes on past it with what follows" $
      contents (paginate 1 3 [FParagraph defaultKeep (lines' 0 2), FFigure 1000 2 [] [], term 2, FParagraph defaultKeep (lines' 3 1)])
        @?= [[SLine 0, SLine 1], [SFigure 1000], [SLine 2, SLine 3]],
    testCase "F1: a ruled heading after a figure sent on goes on past it with what follows" $
      contents (paginate 1 3 [FParagraph defaultKeep (lines' 0 2), FFigure 1000 2 [] [], ruledHeading False 2, FParagraph defaultKeep (lines' 3 1)])
        @?= [[SLine 0, SLine 1], [SFigure 1000], [SHeading 2 1, SLine 3]]
  ]

{- | 'S.keep' from a column with one line, the figures of the lengths
given and a continued note of the lines given waiting, and a need.
-}
keepFrom :: Int -> Int -> [Int] -> Int -> Int -> (S.St, S.St)
keepFrom cols c figs noteLen need =
  let env = S.Env maxBound 1 (ColumnSet cols 0 0 0) c
      st0 = S.putLine env (S.initialState env) (LineBox 0 [] [] [] 0)
      st = st0 {S.sDeferred = [FFigure (1000 + j) n [] [] | (j, n) <- zip [0 ..] figs], S.sPendingNotes = [(nid 900, 0, noteLen) | noteLen > 0]}
   in (st, S.keep env st (const need))

keepTests :: [TestTree]
keepTests =
  [ -- golem-layout ADR 0023 bounds the columns gone on by the figures and
    -- note lines waiting; the first column gone on, from the column that
    -- the need does not fit, takes none of them, so one more
    testCase "F3, F4: keep stops where the need fits or the column is empty, after one column and a column at most for each figure and note line waiting" $
      sequence_
        [ assertBool (show (cols, c, figs, noteLen, need, advanced)) (fitsOrEmpty && advanced <= 1 + length figs + noteLen)
        | cols <- [1, 2],
          c <- [3 .. 5],
          k <- [0 .. 3],
          figs <- replicateM k [1 .. c],
          noteLen <- [0 .. 2],
          need <- [1 .. c + 1],
          let (st, r) = keepFrom cols c figs noteLen need
              env = S.Env maxBound 1 (ColumnSet cols 0 0 0) c
              fitsOrEmpty = need <= S.free env r || S.isEmpty r
              advanced = (S.sPage r - S.sPage st) * cols + S.sColumn r - S.sColumn st
        ],
    -- A6 of docs/adr/0211: with nothing waiting, a need that does not fit
    -- goes on one column, to an empty one, and no more
    testCase "A6: keep with nothing waiting and a need that does not fit goes on exactly one column" $
      sequence_
        [ assertEqual (show (cols, c, need)) 1 advanced
        | cols <- [1, 2],
          c <- [3 .. 5],
          need <- [c, c + 1],
          let (st, r) = keepFrom cols c [] 0 need
              advanced = (S.sPage r - S.sPage st) * cols + S.sColumn r - S.sColumn st
        ]
  ]

{- | R3 and R4: a blank page holds nothing, and every figure is in a
column before the column of the line given (the heading at a recto, or
the first line after a break).
-}
rectoChecks :: Int -> [PageOut] -> Assertion
rectoChecks marker ps = do
  let cols = zip [0 :: Int ..] (sortOn (\p -> (poNumber p, poColumn p)) ps)
      at f = [c | (c, p) <- cols, (_, s) <- poSlots p, f s]
      lineAt = at (\case SLine i -> i == marker; SHeading i _ -> i == marker; _ -> False)
      figures = at (\case SFigure _ -> True; _ -> False)
  assertEqual "R3: the blank pages hold nothing" [] [poNumber p | (_, p) <- cols, poBlank p, not (null (poSlots p) && null (poFootnotes p))]
  case lineAt of
    [c] -> assertBool ("R4: the figures are before column " <> show c) (all (< c) figures)
    found -> assertFailure ("line " <> show marker <> " is in the columns " <> show found)

rectoAfterFiguresTests :: [TestTree]
rectoAfterFiguresTests =
  [ testCase "R1: a figure sent on before a heading at a recto takes the page before it" $ do
      let input = Input 3 1 [EPara 1, EFigure 3, ERecto]
      placedIn input @?= [(1, 0, [SLine 0]), (2, 0, [SFigure 1000]), (3, 0, [SHeading 1 1])]
      rectoChecks 1 (paginateInput input),
    testCase "R1: a figure sent on to an odd page before a heading at a recto, a blank page after it" $ do
      let input = Input 3 1 [EPara 3, EPara 1, EFigure 3, ERecto, EPara 1]
      placedIn input @?= [(1, 0, [SLine 0, SLine 1, SLine 2]), (2, 0, [SLine 3]), (3, 0, [SFigure 1000]), (4, 0, []), (5, 0, [SHeading 4 1, SLine 5])]
      rectoChecks 4 (paginateInput input),
    testCase "R1: in two columns, a figure sent on before a heading at a recto takes the next column" $ do
      let input = Input 3 2 [EPara 1, EFigure 3, ERecto]
      placedIn input @?= [(1, 0, [SLine 0]), (1, 1, [SFigure 1000]), (2, 0, []), (3, 0, [SHeading 1 1])]
      rectoChecks 1 (paginateInput input),
    testCase "R1: a ruled heading at a recto after a figure sent on" $ do
      let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 1), FFigure 1000 3 [] [], ruledHeading True 1]
      contents ps @?= [[SLine 0], [SFigure 1000], [SHeading 1 1]]
      rectoChecks 1 ps,
    testCase "R2: a recto break after a figure sent on, the new page odd" $ do
      let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 1), FFigure 1000 3 [] [], FBreak BreakRecto, FParagraph defaultKeep (lines' 1 1)]
      [(poNumber p, map snd (poSlots p)) | p <- ps] @?= [(1, [SLine 0]), (2, [SFigure 1000]), (3, [SLine 1])]
      rectoChecks 1 ps,
    testCase "R2: a recto break after a figure sent on, the new page even" $ do
      let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 3), FParagraph defaultKeep (lines' 3 1), FFigure 1000 3 [] [], FBreak BreakRecto, FParagraph defaultKeep (lines' 4 1)]
      [(poNumber p, map snd (poSlots p)) | p <- ps] @?= [(1, map SLine [0 .. 2]), (2, [SLine 3]), (3, [SFigure 1000]), (4, []), (5, [SLine 4])]
      rectoChecks 4 ps,
    testCase "R2: a verso break after a figure sent on, the new page odd" $ do
      let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 1), FFigure 1000 3 [] [], FBreak BreakVerso, FParagraph defaultKeep (lines' 1 1)]
      [(poNumber p, map snd (poSlots p)) | p <- ps] @?= [(1, [SLine 0]), (2, [SFigure 1000]), (3, []), (4, [SLine 1])]
      rectoChecks 1 ps,
    testCase "R2: a verso break after a figure sent on, the new page even" $ do
      let ps = paginate 1 3 [FParagraph defaultKeep (lines' 0 3), FParagraph defaultKeep (lines' 3 1), FFigure 1000 3 [] [], FBreak BreakVerso, FParagraph defaultKeep (lines' 4 1)]
      [(poNumber p, map snd (poSlots p)) | p <- ps] @?= [(1, map SLine [0 .. 2]), (2, [SLine 3]), (3, [SFigure 1000]), (4, [SLine 4])]
      rectoChecks 4 ps,
    testCase "R3: a note continued before a heading at a recto ends on the page before it" $ do
      let ps = paginate 1 4 [FParagraph defaultKeep [LineBox 0 [NoteBody (nid 900) 4] [] [] 0], FHeading 1 True 1 (lines' 1 1)]
      [(poNumber p, map snd (poSlots p), poFootnotes p) | p <- ps]
        @?= [(1, [SLine 0], [(nid 900, 0, 2)]), (2, [], [(nid 900, 2, 2)]), (3, [SHeading 1 1], [])]
      rectoChecks 1 ps
  ]

-- | Page, column and what starts in each column.
placed :: [PageOut] -> [(Int, Int, [Slotted])]
placed ps = [(poNumber p, poColumn p, map snd (poSlots p)) | p <- ps]

-- | The invariants of the list broken by the output, with a separator of one grid line.
brokenOf :: [Invariant] -> [Flow] -> [PageOut] -> [Invariant]
brokenOf which flows ps = [breachOf b | b <- breaches 1 flows ps, breachOf b `elem` which]

{- | golem-layout ADR 0025: the reproductions of its section 「文脈」, a
paragraph of three lines and a figure of three lines sent on, in columns
of four grid lines, and the smallest inputs found for tables and wrapped
figures.
-}
afterSentOnTests :: [TestTree]
afterSentOnTests =
  [ testCase "P1: need-lines 2 after a figure sent on goes on past the column the figure takes, with no warning" $ do
      let flows = [FParagraph defaultKeep (lines' 0 3), FFigure 1000 3 [] [], FNeedLines mk 2, FParagraph defaultKeep (lines' 3 1)]
          ps = paginate 1 4 flows
      placed ps @?= [(1, 0, map SLine [0 .. 2]), (2, 0, [SFigure 1000]), (3, 0, [SLine 3])]
      unmets ps @?= []
      brokenOf [P1, P2] flows ps @?= [],
    testCase "P1: in two columns, need-lines 2 after a figure sent on goes on past its column" $ do
      let flows = [FParagraph defaultKeep (lines' 0 3), FFigure 1000 3 [] [], FNeedLines mk 2, FParagraph defaultKeep (lines' 3 1)]
          ps = paginate 2 4 flows
      placed ps @?= [(1, 0, map SLine [0 .. 2]), (1, 1, [SFigure 1000]), (2, 0, [SLine 3])]
      unmets ps @?= []
      brokenOf [P1, P2] flows ps @?= [],
    testCase "P2: need-lines 2 after a figure sent on is not recorded; need-lines 5 in columns of 4 is recorded once" $ do
      unmets (paginate 1 4 [FParagraph defaultKeep (lines' 0 3), FFigure 1000 3 [] [], FNeedLines mk 2, FParagraph defaultKeep (lines' 3 1)]) @?= []
      let flows = [FParagraph defaultKeep (lines' 0 3), FFigure 1000 3 [] [], FNeedLines mk 5, FParagraph defaultKeep (lines' 3 1)]
          ps = paginate 1 4 flows
      unmets ps @?= [UnmetNeedLines mk 5]
      brokenOf [P2] flows ps @?= [],
    testCase "P3: blank lines after a figure sent on do not overflow its column" $ do
      let flows = [FParagraph defaultKeep (lines' 0 3), FFigure 1000 3 [] [], FBlank mk 2, FParagraph defaultKeep (lines' 3 1)]
          ps = paginate 1 4 flows
      brokenOf [I2, P3] flows ps @?= [],
    testCase "P4: blank lines after a figure sent on are dropped at the top of the next column and recorded" $ do
      let flows = [FParagraph defaultKeep (lines' 0 3), FFigure 1000 3 [] [], FBlank mk 2, FParagraph defaultKeep (lines' 3 1)]
          ps = paginate 1 4 flows
      placed ps @?= [(1, 0, map SLine [0 .. 2]), (2, 0, [SFigure 1000]), (3, 0, [SLine 3])]
      gridLines ps @?= [[0, 1, 2], [0], [0]]
      unmets ps @?= [DroppedBlank mk]
      brokenOf [P3, P4] flows ps @?= [],
    testCase "P4: blank lines and the paragraph that fit after a figure sent on are placed after it, in its column" $ do
      -- 1 left on page 1: the figure is sent on, and 2 blank lines and the line take the 3 after it on page 2
      let flows = [FParagraph defaultKeep (lines' 0 5), FFigure 1000 3 [] [], FBlank mk 2, FParagraph defaultKeep (lines' 5 1)]
          ps = paginate 1 6 flows
      placed ps @?= [(1, 0, map SLine [0 .. 4]), (2, 0, [SFigure 1000, SLine 5])]
      gridLines ps @?= [[0 .. 4], [0, 5]]
      unmets ps @?= []
      brokenOf [P3, P4] flows ps @?= [],
    -- A5 of docs/adr/0211: a column that holds only continued notes is at
    -- its top; the blank lines after a figure sent on are dropped there and
    -- recorded, and the column is not gone past
    testCase "A5: blank lines at the top of a column of continued notes only are dropped and recorded there" $ do
      let flows = [FParagraph defaultKeep [LineBox 0 [NoteBody (nid 900) 5] [] [] 0], FFigure 1000 3 [] [], FBlank mk 2, FParagraph defaultKeep (lines' 1 1)]
          ps = paginate 1 4 flows
      -- page 1: the line and 2 lines of the note, 1 left; the figure is
      -- sent on and the blank lines and the line do not fit. Page 2 holds
      -- the continued note only: its top, where the blank lines are dropped
      -- and the line is set, not on page 3
      [(poNumber p, map snd (poSlots p)) | p <- ps] @?= [(1, [SLine 0]), (2, [SLine 1]), (3, []), (4, [SFigure 1000])]
      gridLines ps @?= [[0], [0], [], [0]]
      unmets ps @?= [DroppedBlank mk]
      brokenOf [P3, P4] flows ps @?= [],
    testCase "I2: a table after a figure sent on goes on past the column the figure takes" $ do
      let flows = [FParagraph defaultKeep (lines' 0 3), FFigure 1000 3 [] [], FTable 50 0 (lines' 10 1) [lines' 20 1, lines' 21 1] [] False]
          ps = paginate 1 4 flows
      placed ps @?= [(1, 0, map SLine [0 .. 2]), (2, 0, [SFigure 1000]), (3, 0, [SLine 10, SLine 20, SLine 21])]
      brokenOf [I2] flows ps @?= [],
    testCase "I2: the part of a table after a figure sent on goes on past the column the figure takes, its header repeated" $ do
      let flows = [FParagraph defaultKeep (lines' 0 2), FFigure 1000 3 [] [], FTable 50 0 (lines' 10 1) [lines' 20 1, lines' 21 1] [] False]
          ps = paginate 1 4 flows
      placed ps @?= [(1, 0, [SLine 0, SLine 1, SLine 10, SLine 20]), (2, 0, [SFigure 1000]), (3, 0, [SLine 10, SLine 21])]
      map (map tsFirst . poTables) ps @?= [[2], [], [0]]
      brokenOf [I2] flows ps @?= [],
    testCase "I2: a wrapped figure after a note continued goes on past the columns the note takes" $ do
      let flows = [FParagraph defaultKeep [LineBox 0 [NoteBody (nid 900) 5] [] [] 0], FWrapped 2000 3 [] [] []]
          ps = paginate 1 4 flows
      [(poNumber p, map snd (poSlots p), poFootnotes p) | p <- ps]
        @?= [(1, [SLine 0], [(nid 900, 0, 2)]), (2, [], [(nid 900, 2, 2)]), (3, [], [(nid 900, 4, 1)]), (4, [SWrapped 2000], [])]
  ]

-- | The invariants of the list broken by an input of PaginateEnum, with a separator of one grid line.
brokenIn :: [Invariant] -> Input -> [Invariant]
brokenIn which input = brokenOf which (enumFlows (inElements input)) (paginateInput input)

{- | golem-layout ADR 0026: the reproductions of its section 「確かめたこと」
and the cases of its section 「テスト設計」. A figure that waits behind a
figure sent on takes neither the need-lines nor the blank lines before
it: they go to the next block of the flow that does not wait.
-}
waitingFigureTests :: [TestTree]
waitingFigureTests =
  [ testCase "P3', P4', P5: blank lines before a figure that waits, with nothing after it, are not placed and are recorded once" $ do
      let input = Input 3 1 [EPara 1, EFigure 3, EBlank 1, EFigure 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0]), (2, 0, [SFigure 1000]), (3, 0, [SFigure 1001])]
      gridLines ps @?= [[0], [0], [0]]
      unmets ps @?= [DroppedBlank (controlSpan 0)]
      brokenIn [P3, P4, P5] input @?= [],
    testCase "P4': blank lines before a figure that waits go with the paragraph after it, in its column" $ do
      let input = Input 4 1 [EPara 2, EFigure 3, EBlank 1, EFigure 2, EPara 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1, SLine 2]), (2, 0, [SFigure 1000]), (3, 0, [SFigure 1001])]
      gridLines ps @?= [[0, 1, 3], [0], [0]]
      unmets ps @?= []
      brokenIn [P3, P4, P5] input @?= [],
    testCase "P1': need-lines before a figure that waits is judged for the paragraph after it" $ do
      let input = Input 4 1 [EPara 2, EFigure 3, ENeedLines, EFigure 1, EPara 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1, SLine 2]), (2, 0, [SFigure 1000, SFigure 1001])]
      unmets ps @?= []
      brokenIn [P1, P2] input @?= [],
    testCase "P6: a break before the controls places the figures sent on first; the figure after them does not wait and has its blank line" $ do
      let input = Input 5 1 [EPara 3, EFigure 3, EBreak, EBlank 1, EFigure 1, EPara 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1, SLine 2]), (2, 0, [SFigure 1000, SFigure 1001]), (3, 0, [SLine 3])]
      gridLines ps @?= [[0, 1, 2], [0, 4], [0]]
      unmets ps @?= []
      brokenIn [P3, P4, P5] input @?= [],
    testCase "P5: blank lines before a figure that waits, the figures placed by a break after it, are recorded once" $ do
      -- the drawn input of the nightly job: the break places the figures waiting, and nothing follows to go with the blank line
      let input = Input 5 2 [EFigure 5, EFigure 2, EBlank 1, EFigure 3, EBreak, ESpace]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SFigure 1000]), (2, 0, [SFigure 1001, SFigure 1002])]
      unmets ps @?= [DroppedBlank (controlSpan 0)]
      brokenIn [P3, P4, P5] input @?= [],
    testCase "P1': need-lines before a figure that waits behind a figure sent on by itself after a break is not judged for it" $ do
      -- the drawn input of the nightly job: the break places the first figure sent on, the third is sent on by itself, and the fourth waits
      let input = Input 7 1 [EFigure 6, EFigure 6, EBreak, EFigure 6, ENeedLines, EFigure 1]
      placedIn input @?= [(1, 0, [SFigure 1000]), (2, 0, [SFigure 1001]), (3, 0, [SFigure 1002, SFigure 1003])]
      brokenIn [P1, P2] input @?= [],
    testCase "P4': blank lines before a turned figure that waits go with the paragraph after it" $ do
      -- page 1 has 2 grid lines left: the figure of 3 is sent on, and the turned figure waits;
      -- the blank line and the paragraph of 2 lines go after the figure on page 2
      let flows = [FParagraph defaultKeep (lines' 0 4), FFigure 1000 3 [] [], FBlank mk 1, FPageFigure 2000 [] [], FParagraph defaultKeep (lines' 4 2)]
          ps = paginate 1 6 flows
      placed ps @?= [(1, 0, map SLine [0 .. 3]), (2, 0, [SFigure 1000, SLine 4, SLine 5]), (3, 0, [SPageFigure 2000])]
      gridLines ps @?= [[0 .. 3], [0, 4, 5], [0]]
      unmets ps @?= []
      brokenOf [P3, P4, P5] flows ps @?= []
  ]

{- | golem-layout ADR 0033: the three counterexamples of its section
「文脈」, which the reading of golem-layout ADR 0026 got wrong. The
figures that wait are read from the input and the output (W1, W2), and
P1', P4' and P5 hold for them.
-}
waitingReadTests :: [TestTree]
waitingReadTests =
  [ testCase "W1, P4': a figure that waits is placed before the paragraph after it, which goes on to the next column" $ do
      let input = Input 6 1 [EPara 2, EFigure 5, EBlank 2, EFigure 1, ENotedPara 2]
      waitingFigures (enumFlows (inElements input)) (paginateInput input) @?= [1001]
      brokenIn [P3, P4, P5] input @?= [],
    testCase "W1, P1': a figure sent on by itself after a break does not wait, the figure after it does" $ do
      let input = Input 7 1 [EFigure 6, EFigure 6, EBreak, EFigure 6, ENeedLines, EFigure 1]
      waitingFigures (enumFlows (inElements input)) (paginateInput input) @?= [1003]
      brokenIn [P1, P2] input @?= [],
    testCase "W1, P5: a figure after the break before a section at an odd page is where the flow comes to, the first page of the section (docs/adr/0260)" $ do
      -- the nightly enumeration's counterexample: the section goes past the blank page 2 to page 3
      let input = Input 3 1 [EPara 1, ESection (Just 1), EFigure 1, EBlank 1, EFigure 1]
      placedIn input @?= [(1, 0, [SLine 0]), (2, 0, []), (3, 0, [SFigure 1000, SFigure 1001])]
      waitingFigures (enumFlows (inElements input)) (paginateInput input) @?= []
      brokenIn [P3, P4, P5] input @?= [],
    testCase "W1, P4: a figure after the break before a section at an odd page, in two columns, does not wait, and the blank line before the next figure goes with it (docs/adr/0260)" $ do
      let input = Input 8 2 [EFigure 8, ESection (Just 1), EFigure 7, EBlank 1, EFigure 2, EHeading]
      waitingFigures (enumFlows (inElements input)) (paginateInput input) @?= []
      brokenIn [P3, P4, P5] input @?= [],
    testCase "W1, P5: a figure after the break before a section at an even page after an even page does not wait (docs/adr/0260)" $ do
      let input = Input 3 1 [EPara 3, EPara 1, ESection (Just 2), EFigure 1, EBlank 1, EFigure 1]
      placedIn input @?= [(1, 0, [SLine 0, SLine 1, SLine 2]), (2, 0, [SLine 3]), (3, 0, []), (4, 0, [SFigure 1000, SFigure 1001])]
      waitingFigures (enumFlows (inElements input)) (paginateInput input) @?= []
      brokenIn [P3, P4, P5] input @?= [],
    testCase "W1, P5: a figure at the end of the book that fits where it is written does not wait" $
      forM_ [Input l c [EPara 1, EBlank 1, EFigure 1] | l <- [3 .. 5], c <- [1, 2]] $ \input -> do
        waitingFigures (enumFlows (inElements input)) (paginateInput input) @?= []
        brokenIn [P3, P4, P5] input @?= []
  ]

{- | golem-layout ADR 0035: need-lines 2 judged before a space, then k
spaces, a second need-lines of m lines, a space and a block, in one
column of 6 grid lines. r grid lines are left after the k spaces. A
larger second one is judged again (N1); a second one no larger changes
nothing (N2). The second is judged before the k spaces, r + k grid lines
left, as golem-layout ADR 0043 decides: the spaces before a need-lines
are not counted either.
-}
largerNeedTests :: [TestTree]
largerNeedTests =
  [ testCase "Golem ADR 0352 I3: needMoreSome model fixture keeps the paragraph" $ do
      let flows = [FParagraph defaultKeep (lines' 0 1), FNeedLines mk 1, FSpace 1, FNeedLines mk2 3, FParagraph defaultKeep (lines' 1 1)]
          ps = paginate 1 4 flows
      placed ps @?= [(1, 0, [SLine 0, SLine 1])]
      brokenOf [P1, P2] flows ps @?= [],
    testCase "N1: need-lines 4 after need-lines 2 judged, one grid line left after the space, sends the paragraph to the next column" $ do
      let flows = [FParagraph defaultKeep (lines' 0 3), FNeedLines mk 2, FSpace 1, FNeedLines mk2 4, FSpace 1, FParagraph defaultKeep (lines' 3 1)]
          ps = paginate 1 6 flows
      placed ps @?= [(1, 0, map SLine [0 .. 2]), (2, 0, [SLine 3])]
      unmets ps @?= []
      brokenOf [P1, P2] flows ps @?= [],
    testCase "W4, P1: the counterexample of golem-layout ADR 0044: need-lines 5 after a space, judged before it, goes on to the column of the figure sent on, and the figure after is not read as waiting" $ do
      let input = Input 6 1 [EPara 2, EFigure 6, ESpace, ENeedLinesMore 5, EFigure 4, EHeading]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000]), (3, 0, [SFigure 1001, SHeading 2 1])]
      unmets ps @?= []
      waitingFigures (enumFlows (inElements input)) ps @?= []
      brokenIn [minBound .. maxBound] input @?= [],
    testCase "W4, P5: the counterexample of golem-layout ADR 0044 in two columns: need-lines 7 after a space and blank lines goes on to column 2, and the figure after the figure sent on there is not read as waiting" $ do
      let input = Input 8 2 [EFigure 8, EFigure 1, ESpace, EBlank 2, ENeedLinesMore 7, EFigure 3]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SFigure 1000]), (1, 1, [SFigure 1001, SFigure 1002])]
      unmets ps @?= []
      waitingFigures (enumFlows (inElements input)) ps @?= []
      brokenIn [minBound .. maxBound] input @?= [],
    testCase "W5, P5: the counterexample of golem-layout ADR 0044: need-lines met before the space, the figure that does not fit after it moved to page 2, and the figure after is not read as waiting" $ do
      let input = Input 6 1 [EPara 4, ENeedLines, ESpace, EFigure 2, EBlank 1, EFigure 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1, SLine 2, SLine 3]), (2, 0, [SFigure 1000, SFigure 1001])]
      unmets ps @?= []
      waitingFigures (enumFlows (inElements input)) ps @?= []
      brokenIn [minBound .. maxBound] input @?= [],
    testGroup "the boundary inputs" (map boundary cases)
  ]
  where
    c = 6
    blocks = [("a paragraph", FParagraph defaultKeep (lines' 100 1)), ("a figure", FFigure 1000 1 [] []), ("a table", FTable 50 0 [] [lines' 200 1] [] False)]
    cases =
      [ (m, k, r, name, block)
      | m <- [1, 2, 3, c, c + 1],
        k <- [0, 1, 2],
        r <- feasible m k,
        (name, block) <- blocks
      ]
    -- the lines left where the second is judged: m and one fewer, those the paragraph before can leave with need-lines 2 met before the spaces
    feasible m k = case [r | r <- [m, m - 1], let p = c - k - r, p >= 1, c - p >= 2] of
      [] -> [c - k - 1]
      rs -> rs
    boundaryFlows m k r block = [FParagraph defaultKeep (lines' 0 (c - k - r)), FNeedLines mk 2] <> replicate k (FSpace 1) <> [FNeedLines mk2 m, FSpace 1, block]
    pageOfBlock ps = last [poNumber p | p <- ps, not (null (poSlots p))]
    boundary (m, k, r, name, block) =
      testCase (boundaryName m k r name) $ do
        brokenOf [P1, P2] flows ps @?= []
        placement
      where
        flows = boundaryFlows m k r block
        ps = paginate 1 c flows
        placement
          | m <= 2 = ps @?= paginate 1 c (filter (/= FNeedLines mk2 m) flows)
          | m > c = do
              unmets ps @?= [UnmetNeedLines mk2 m]
              pageOfBlock ps @?= 2
          | otherwise = pageOfBlock ps @?= (if r + k >= m then 1 else 2)
    boundaryName m k r name =
      (if m <= 2 then "N2: " else "N1: ")
        <> ("need-lines " <> show m <> " after " <> show k <> " spaces, " <> show r <> " grid lines left, before " <> name)

{- | golem-layout ADR 0027: the reproductions of its section 「確かめたこと」
and the cases of its section 「テスト設計」. Need-lines is judged before
the spaces after it, the spaces not counted, and judged again in the
column the block goes on to when its first part does not fit after them.
-}
spaceAfterNeedTests :: [TestTree]
spaceAfterNeedTests =
  [ testCase "Golem ADR 0352 I3: needSpaceSome model fixture keeps the paragraph" $ do
      let flows = [FParagraph defaultKeep (lines' 0 1), FNeedLines mk 2, FSpace 1, FParagraph defaultKeep (lines' 1 1)]
          ps = paginate 1 3 flows
      placed ps @?= [(1, 0, [SLine 0, SLine 1])]
      brokenOf [P1, P2] flows ps @?= [],
    testCase "P1: the paragraph after need-lines and two spaces goes past the figure sent on, to page 3" $ do
      let input = Input 4 1 [EPara 2, EFigure 3, ENeedLines, ESpace, ESpace, EPara 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000]), (3, 0, [SLine 2])]
      unmets ps @?= []
      brokenIn [P1, P2] input @?= [],
    testCase "P1: in two columns, the paragraph after need-lines and two spaces goes past the column of the figure sent on" $ do
      let input = Input 4 2 [EPara 2, EFigure 3, ENeedLines, ESpace, ESpace, EPara 1]
      placedIn input @?= [(1, 0, [SLine 0, SLine 1]), (1, 1, [SFigure 1000]), (2, 0, [SLine 2])]
      brokenIn [P1, P2] input @?= [],
    testCase "P7: a paragraph whose first part fits after the space stays in the column need-lines was judged in" $ do
      let input = Input 4 1 [EPara 2, ENeedLines, ESpace, EPara 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1, SLine 2])]
      gridLines ps @?= [[0, 1, 3]]
      brokenIn [P1, P2] input @?= [],
    testCase "P1: a paragraph whose first two lines do not fit after the spaces goes on until need-lines is met" $ do
      -- one line is left after the spaces on page 1: the paragraph of four lines goes on, past the figure on page 2
      let input = Input 5 1 [EPara 2, EFigure 4, ENeedLines, ESpace, ESpace, EPara 4]
      placedIn input @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000]), (3, 0, map SLine [2 .. 5])]
      brokenIn [P1, P2, I4, I5] input @?= [],
    testCase "P8: in the column gone on to after the spaces, no space is placed at its top" $ do
      let ps = paginateInput (Input 4 1 [EPara 2, EFigure 3, ENeedLines, ESpace, ESpace, EPara 1])
      gridLines ps @?= [[0, 1], [0], [0]]
  ]

{- | golem-layout ADR 0043: the spaces between the block before and
need-lines are not counted either. Need-lines is judged before them, as
before the spaces after it (golem-layout ADR 0027), and the block after
is placed in the column judged in when its first part fits after the
spaces (P10). Moving the spaces after the need-lines lays out the same
(P9). The cases of its section 「テスト設計」 and of its table of the
boundary inputs, in columns of 6 grid lines for the table, and the
counterexamples of golem-layout ADR 0044, which reads the figures moved
by need-lines judged before spaces (W4, W5): every invariant is checked
on the boundary inputs, with the figures that wait read alike wherever
the space is (W3).
-}
spaceBeforeNeedTests :: [TestTree]
spaceBeforeNeedTests =
  [ testCase "P10: the paragraph after a space and need-lines 2 stays on page 1, after the space" $ do
      let input = Input 3 1 [EPara 1, ESpace, ENeedLines, EPara 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1])]
      gridLines ps @?= [[0, 2]]
      unmets ps @?= []
      brokenIn [minBound .. maxBound] input @?= [],
    testCase "P9: the space before need-lines and the space after it lay out the same, and without the space the paragraph is on line 2" $ do
      placedIn (Input 3 1 [EPara 1, ESpace, ENeedLines, EPara 1]) @?= placedIn (Input 3 1 [EPara 1, ENeedLines, ESpace, EPara 1])
      gridLines (paginateInput (Input 3 1 [EPara 1, ENeedLines, ESpace, EPara 1])) @?= [[0, 2]]
      gridLines (paginateInput (Input 3 1 [EPara 1, ENeedLines, EPara 1])) @?= [[0, 1]],
    testCase "P9: moving the space after the need-lines lays out the same, in the first form of golem-layout ADR 0043" $ do
      let flows = enumFlows [EPara 1, ESpace, ENeedLines, EPara 1]
          lay = paginate 1 3
      p9SpaceMoved lay flows (lay flows) @?= [],
    testCase "P5: the counterexample of the nightly job: the figure after the space, the next at the top of column 2, the blank line dropped and recorded" $ do
      -- the enum.yml run 42530629702 of 2026-11-09
      forM_ [ENeedLinesMore 2, ENeedLines] $ \n -> do
        let input = Input 3 2 [EPara 1, ESpace, n, EFigure 1, EBlank 1, EFigure 1]
            ps = paginateInput input
        placedIn input @?= [(1, 0, [SLine 0, SFigure 1000]), (1, 1, [SFigure 1001])]
        gridLines ps @?= [[0, 2], [0]]
        [(poColumn p, poUnmet p) | p <- ps] @?= [(0, []), (1, [DroppedBlank (controlSpan 1)])]
        waitingFigures (enumFlows (inElements input)) ps @?= []
        brokenIn [minBound .. maxBound] input @?= []
        p9SpaceMoved (paginateIn 1 (ColumnSet 2 0 0 0) 3) (enumFlows (inElements input)) ps @?= [],
    testCase "W4, P1: the counterexample of golem-layout ADR 0044: need-lines 5 after a space, judged before it, goes on to the column of the figure sent on, and the figure after is not read as waiting" $ do
      let input = Input 6 1 [EPara 2, EFigure 6, ESpace, ENeedLinesMore 5, EFigure 4, EHeading]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000]), (3, 0, [SFigure 1001, SHeading 2 1])]
      unmets ps @?= []
      waitingFigures (enumFlows (inElements input)) ps @?= []
      brokenIn [minBound .. maxBound] input @?= [],
    testCase "W4, P5: the counterexample of golem-layout ADR 0044 in two columns: need-lines 7 after a space and blank lines goes on to column 2, and the figure after the figure sent on there is not read as waiting" $ do
      let input = Input 8 2 [EFigure 8, EFigure 1, ESpace, EBlank 2, ENeedLinesMore 7, EFigure 3]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SFigure 1000]), (1, 1, [SFigure 1001, SFigure 1002])]
      unmets ps @?= []
      waitingFigures (enumFlows (inElements input)) ps @?= []
      brokenIn [minBound .. maxBound] input @?= [],
    testCase "W5, P5: the counterexample of golem-layout ADR 0044: need-lines met before the space, the figure that does not fit after it moved to page 2, and the figure after is not read as waiting" $ do
      let input = Input 6 1 [EPara 4, ENeedLines, ESpace, EFigure 2, EBlank 1, EFigure 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1, SLine 2, SLine 3]), (2, 0, [SFigure 1000, SFigure 1001])]
      unmets ps @?= []
      waitingFigures (enumFlows (inElements input)) ps @?= []
      brokenIn [minBound .. maxBound] input @?= [],
    testGroup "the boundary inputs" (map boundary cases)
  ]
  where
    c = 6
    need = 2
    blocks = [("a paragraph of 1 line", FParagraph defaultKeep (lines' 100 1), 1), ("a paragraph of 2 lines", FParagraph defaultKeep (lines' 100 2), 2), ("a figure of 1 line", FFigure 1000 1 [] [], 1), ("a figure of C lines", FFigure 1000 c [] [], c)]
    afters = [("", []), (", blank lines and a figure", [FBlank mk2 1, FFigure 1001 1 [] []])]
    -- columns, spaces before, the lines left before them, spaces after
    cases =
      [ (k, s, r, a)
      | k <- [1, 2],
        s <- [0, 1, 2, 3],
        r <- nubInts [need - 1, need, need + s - 1, need + s, s],
        r >= 1,
        r <= c - 1,
        r >= s,
        a <- [0, 1]
      ]
    nubInts = foldr (\x xs -> x : filter (/= x) xs) []
    boundary (k, s, r, a) =
      testCase (boundaryName k s r a) $
        forM_ [(name <> what, block, first, rest) | (name, block, first) <- blocks, (what, rest) <- afters] $ \(name, block, first, rest) -> do
          let flows = [FParagraph defaultKeep (lines' 0 (c - r))] <> replicate s (FSpace 1) <> [FNeedLines mk need] <> replicate a (FSpace 1) <> [block] <> rest
              lay = paginateIn 1 (ColumnSet k 0 0 0) c
              ps = lay flows
              firstAt = take 1 [(poNumber p, poColumn p) | p <- ps, (_, sl) <- poSlots p, sl `elem` [SLine 100, SFigure 1000]]
          assertEqual ("the invariants, before " <> name) [] (brokenOf [minBound .. maxBound] flows ps)
          assertEqual ("P9, before " <> name) [] (map breachWhy (p9SpaceMoved lay flows ps))
          assertEqual ("W3, before " <> name) [] (map breachWhy (w3WaitingAlike lay flows ps))
          when (s > 0 && r >= need && first <= r - s - a) $
            assertEqual ("P10, the column of " <> name) [(1, 0)] firstAt
    boundaryName k s r a =
      (if s > 0 then "P9, P10, W3: " else "P9, W3: ")
        <> (show k <> " column" <> (if k > 1 then "s, " else ", "))
        <> (show s <> " spaces before need-lines 2, " <> show r <> " grid lines left before them, " <> show a <> " after")

{- | golem-layout ADR 0047: a figure that waits between the spaces and a
need-lines does not clear the record of the spaces, and the need-lines
is judged before them as with no figure between. The rows of 「確かめた出力」
of its section 「文脈」 (P11, P9′), and its table of the boundary inputs in
columns of 6 grid lines: every invariant is checked, with P9′ and P11,
and the paragraph after is placed in the column judged in when its first
line fits after the spaces.
-}
spaceBeforeWaitingTests :: [TestTree]
spaceBeforeWaitingTests =
  [ testCase "P11: a space, a figure that waits and need-lines 2: the paragraph after is on line 2 of page 1, as with the figure before the space" $ do
      let input = Input 3 1 [EPara 1, EFigure 3, ESpace, EFigure 1, ENeedLines, EPara 1]
          ps = paginateInput input
      placedIn input @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000]), (3, 0, [SFigure 1001])]
      gridLines ps @?= [[0, 2], [0], [0]]
      unmets ps @?= []
      brokenIn [minBound .. maxBound] input @?= []
      p11WaitingBeforeSpace (paginate 1 3) (enumFlows (inElements input)) ps @?= [],
    testCase "P11, P9′: the rows of 「確かめた出力」 of golem-layout ADR 0047 all lay out alike" $ do
      let rows =
            [ [EPara 1, EFigure 3, ESpace, EFigure 1, ENeedLines, EPara 1],
              [EPara 1, EFigure 3, EFigure 1, ESpace, ENeedLines, EPara 1],
              [EPara 1, EFigure 3, ESpace, ENeedLines, EFigure 1, EPara 1],
              [EPara 1, EFigure 3, ENeedLines, ESpace, EFigure 1, EPara 1]
            ]
      forM_ rows $ \es -> placedIn (Input 3 1 es) @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000]), (3, 0, [SFigure 1001])]
      placedIn (Input 3 1 [EPara 1, EFigure 3, ESpace, ENeedLines, EPara 1]) @?= [(1, 0, [SLine 0, SLine 1]), (2, 0, [SFigure 1000])],
    testCase "P9′: the space moved after the need-lines past the figure that waits lays out the same, the input of six elements" $ do
      let flows = enumFlows [EPara 1, EFigure 3, ESpace, EFigure 1, ENeedLines, EPara 1]
          lay = paginate 1 3
          ps = lay flows
      waitingFigures flows ps @?= [1001]
      map breachWhy (p9SpaceMoved lay flows ps) @?= []
      map breachWhy (w3WaitingAlike lay flows ps) @?= [],
    testCase "a break between the space and the figure that waits clears the record: need-lines 2 is judged in the column gone on to, after the figure sent on, the space of the column left not taken off" $ do
      -- 1 line is left on page 2 after the figure sent on: with the space of page 1 taken off, 2 would be
      let flows = [FParagraph defaultKeep (lines' 0 2), FFigure 1000 5 [] [], FFigure 1001 5 [] [], FSpace 1, FBreak BreakPage, FFigure 1002 1 [] [], FNeedLines mk 2, FParagraph defaultKeep (lines' 100 1)]
          ps = paginateIn 1 (ColumnSet 1 0 0 0) 6 flows
      [(poNumber p, map snd (poSlots p)) | p <- ps] @?= [(1, [SLine 0, SLine 1]), (2, [SFigure 1000]), (3, [SFigure 1001, SFigure 1002]), (4, [SLine 100])]
      unmets ps @?= []
      waitingFigures flows ps @?= [1001, 1002]
      brokenOf [minBound .. maxBound] flows ps @?= [],
    testCase "a figure sent on by itself between the space and need-lines clears the record: need-lines 2 is judged after the space, as before golem-layout ADR 0047" $ do
      -- 1 line is left after the space on page 1: the paragraph goes on to page 2, after the figure
      let flows = [FParagraph defaultKeep (lines' 0 4), FSpace 1, FFigure 1000 3 [] [], FNeedLines mk 2, FParagraph defaultKeep (lines' 100 1)]
          ps = paginateIn 1 (ColumnSet 1 0 0 0) 6 flows
      [(poNumber p, map snd (poSlots p)) | p <- ps] @?= [(1, [SLine 0, SLine 1, SLine 2, SLine 3]), (2, [SFigure 1000, SLine 100])]
      gridLines ps @?= [[0, 1, 2, 3], [0, 3]]
      unmets ps @?= []
      waitingFigures flows ps @?= []
      brokenOf [minBound .. maxBound] flows ps @?= [],
    testGroup "the boundary inputs" (map boundary cases)
  ]
  where
    c = 6
    need = 2
    blocks = [("a paragraph of 1 line", FParagraph defaultKeep (lines' 100 1)), ("a figure", FFigure 1100 1 [] [])]
    -- columns, figures that wait between, their grid lines, spaces, the lines left before the spaces
    cases =
      [ (k, w, h, s, r)
      | k <- [1, 2],
        w <- [0, 1, 2],
        h <- if w == 0 then [1] else [1, c],
        s <- [1, 2],
        r <- nubInts [need - 1, need, need + s - 1, need + s],
        r >= 1,
        r <= c - 1
      ]
    nubInts = foldr (\x xs -> x : filter (/= x) xs) []
    boundary (k, w, h, s, r) =
      testCase (boundaryName k w h s r) $
        forM_ blocks $ \(name, block) -> do
          -- the figure of C lines does not fit in the r lines left: it is sent on, and the figures after it wait
          let flows =
                [FParagraph defaultKeep (lines' 0 (c - r)), FFigure 1000 c [] []]
                  <> replicate s (FSpace 1)
                  <> [FFigure (1001 + i) h [] [] | i <- [0 .. w - 1]]
                  <> [FNeedLines mk need, block]
              lay = paginateIn 1 (ColumnSet k 0 0 0) c
              ps = lay flows
              firstAt = take 1 [(poNumber p, poColumn p) | p <- ps, (_, sl) <- poSlots p, sl == SLine 100]
          assertEqual ("the figures that wait, before " <> name) [1001 .. 1000 + w] (take w (waitingFigures flows ps))
          assertEqual ("the invariants, before " <> name) [] (brokenOf [minBound .. maxBound] flows ps)
          assertEqual ("P9′, before " <> name) [] (map breachWhy (p9SpaceMoved lay flows ps))
          assertEqual ("P11, before " <> name) [] (map breachWhy (p11WaitingBeforeSpace lay flows ps))
          assertEqual ("W3, before " <> name) [] (map breachWhy (w3WaitingAlike lay flows ps))
          when (name == "a paragraph of 1 line" && r >= need && 1 <= r - s) $
            assertEqual ("P11, the column of " <> name) [(1, 0)] firstAt
    boundaryName k w h s r =
      "P9′, P11: "
        <> (show k <> " column" <> (if k > 1 then "s, " else ", "))
        <> (show w <> " figures of " <> show h <> " lines waiting between " <> show s <> " spaces and need-lines 2, ")
        <> (show r <> " grid lines left before the spaces")
