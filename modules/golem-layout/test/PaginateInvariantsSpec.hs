-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program: those
-- would hold every input checked (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The invariants of pagination checked on every small input
(docs/adr/0204): the enumeration of the inputs, the predicates I1 to I8,
P1 to P4 (golem-layout ADR 0025), P5 (golem-layout ADR 0026) and P9
(golem-layout ADR 0043) on outputs made by hand, and every
input up to the depth of
@GOLEM_ENUM_DEPTH@ elements, with the known bugs excluded by an explicit
list whose counterexamples are counted.

The enumeration is the one shortened by docs/adr/0208 (its section 3):
columns of 3 to 5 grid lines and figures of 1, C − 1 and C lines, checked
on every processor in one scan that also counts the known bugs. The
inputs it leaves out are drawn from the enumeration of docs/adr/0204,
one element past the depth: @GOLEM_ENUM_PAGINATION_SAMPLES@ of them.
-}
module PaginateInvariantsSpec (invariantTests, prDepth, KnownBug (..), knownBugs) where

import Data.List (intercalate, nub)
import Data.Set qualified as Set
import Data.Word (Word64)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Paginate
import Golem.TestSupport.Enum
import PaginateEnum
import PaginateInvariants
import System.Environment (lookupEnv)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Read (readMaybe)

invariantTests :: TestTree
invariantTests =
  testGroup
    "pagination invariants on every small input (docs/adr/0204)"
    [ testGroup "the enumeration of the inputs" enumerationTests,
      testGroup "the predicates" predicateTests,
      testGroup "every input" exhaustiveTests
    ]

{- | The elements of the flows of pull requests (docs/adr/0204, the
decision 3 of the maintainer: 4 elements made the tests of golem-layout
about 50 seconds longer on the x86-64 runner of CI, so the pull requests
check 3). The nightly job raises it with GOLEM_ENUM_DEPTH.
-}
prDepth :: Int
prDepth = 3

-- | The depth: GOLEM_ENUM_DEPTH, a whole number of 0 or more, or 'prDepth'.
enumDepth :: IO Int
enumDepth = wholeNumber "GOLEM_ENUM_DEPTH" prDepth

{- | The inputs drawn one element past the depth (docs/adr/0208):
GOLEM_ENUM_PAGINATION_SAMPLES, or none.
-}
enumSamples :: IO Int
enumSamples = wholeNumber "GOLEM_ENUM_PAGINATION_SAMPLES" 0

-- | The seed of the inputs drawn: the same inputs on every run of a commit.
sampleSeed :: Word64
sampleSeed = 0x0208

-- | A variable that holds a whole number of 0 or more, or the default when it is unset or empty.
wholeNumber :: String -> Int -> IO Int
wholeNumber name def =
  lookupEnv name >>= \case
    Nothing -> pure def
    Just "" -> pure def
    Just s -> case readMaybe s of
      Just n | n >= 0 -> pure n
      _ -> assertFailure (name <> " is not a whole number of 0 or more: " <> show s)

enumerationTests :: [TestTree]
enumerationTests =
  [ testCase "I2: in columns of 3 grid lines there are 20 elements, no figure taller than the column" $ do
      -- paragraphs of 1 to 4 lines, with and without a note, a heading
      -- with and without a note, a heading at a recto, figures of 1 to 3
      -- lines, a space and a break (docs/adr/0206), need-lines of 2 and
      -- blank lines of 1 and 2 lines (golem-layout ADR 0025), need-lines
      -- of c − 1 lines (golem-layout ADR 0035)
      length (elementsFor 3) @?= 4 + 4 + 3 + 3 + 2 + 4
      [n | EFigure n <- elementsFor 3] @?= [1 .. 3],
    testCase "P1, P3: the need-lines is of 2 lines, the blank lines of 1 and 2 (golem-layout ADR 0025)" $
      [e | e <- elementsFor 3, e `elem` [ENeedLines, EBlank 1, EBlank 2]] @?= [ENeedLines, EBlank 1, EBlank 2],
    testCase "N1: the larger need-lines is of c − 1 lines, and none in columns of 2 grid lines or fewer (golem-layout ADR 0035)" $ do
      [n | ENeedLinesMore n <- elementsFor 3] @?= [2]
      [n | ENeedLinesMore n <- elementsFor 5] @?= [4]
      [n | ENeedLinesMore n <- elementsFor 8] @?= [7]
      [n | ENeedLinesMore n <- elementsFor 2] @?= []
      [n | ENeedLinesMore n <- shortElementsFor 5] @?= [4]
      enumFlows [ENeedLines, ENeedLinesMore 4] @?= [FNeedLines (controlSpan 0) 2, FNeedLines (controlSpan 1) 4],
    testCase "in columns of 3 grid lines, the flows of up to 2 elements are as many as the elements allow" $ do
      let m = length (elementsFor 3)
          made = [i | t <- upTo 2 fullInputs, i <- t, inLines i == 3]
      length made @?= 2 * sum [m ^ n | n <- [0 .. 2 :: Int]]
      length [i | i <- made, inColumns i == 2] @?= sum [m ^ n | n <- [0 .. 2 :: Int]],
    testCase "tier n holds the flows of n elements, over 6 sizes of column and 2 numbers of columns" $
      map length (upTo 2 fullInputs) @?= [12, sum [2 * length (elementsFor c) | c <- [3 .. 8]], sum [2 * length (elementsFor c) ^ (2 :: Int) | c <- [3 .. 8]]],
    testCase "the lines are numbered from 0 in the order of the flow, the figures from 1000, the controls from 0" $
      enumFlows [EPara 2, EFigure 3, ENeedLines, ENotedHeading, ESpace, EBreak, EBlank 2, EFigure 1, EBlank 1, ERecto]
        @?= [ FParagraph [LineBox 0 [] [] [] 0, LineBox 1 [] [] [] 0],
              FFigure 1000 3 [] [],
              FNeedLines (controlSpan 0) 2,
              FHeading 2 False 1 [LineBox 2 [NoteBody (noteOf 2) 1] [] [] 0],
              FSpace 1,
              FBreak BreakPage,
              FBlank (controlSpan 1) 2,
              FFigure 1001 1 [] [],
              FBlank (controlSpan 2) 1,
              FHeading 1 True 1 [LineBox 3 [] [] [] 0]
            ],
    testCase "the shortened enumeration has columns of 3 to 5 grid lines, and figures of 1, C - 1 and C lines (docs/adr/0208)" $ do
      [n | EFigure n <- shortElementsFor 3] @?= [1, 2, 3]
      [n | EFigure n <- shortElementsFor 4] @?= [1, 3, 4]
      [n | EFigure n <- shortElementsFor 5] @?= [1, 4, 5]
      [e | e <- shortElementsFor 5, not (isFigure e)] @?= [e | e <- elementsFor 5, not (isFigure e)]
      nub [(inLines i, inColumns i) | i <- concat (upTo 1 inputs)] @?= [(c, k) | c <- [3 .. 5], k <- [1, 2]]
      map length (upTo 3 inputs) @?= [6, 6 * 20, 6 * 20 ^ (2 :: Int), 6 * 20 ^ (3 :: Int)],
    testCase "E5: each input of the shortened enumeration up to 3 elements is in the same tier of the enumeration of docs/adr/0204" $ do
      -- tier n of the enumeration of docs/adr/0204 holds the flows of n of
      -- the elements of their column, in columns of 3 to 8 lines, of one or
      -- two columns: up to 2 elements, against the tiers themselves
      let inTier n i = inLines i `elem` [3 .. 8] && inColumns i `elem` [1, 2] && length (inElements i) == n && all (`elem` elementsFor (inLines i)) (inElements i)
      sequence_
        [ (k, Set.fromList (map show full)) @?= (k, Set.fromList [show i | i <- concat (upTo 2 fullInputs), inTier k i])
        | (k, full) <- zip [0 :: Int ..] (upTo 2 fullInputs)
        ]
      sequence_
        [ assertBool ("tier " <> show k <> ": " <> show i) (inTier k i)
        | (k, short) <- zip [0 :: Int ..] (upTo 3 inputs),
          i <- short
        ],
    testCase "E5: the shortened enumeration keeps the order of the enumeration of docs/adr/0204" $
      sequence_
        [ (k, short) @?= (k, filter (`elem` short) full)
        | (k, short, full) <- zip3 [0 :: Int ..] (upTo 2 inputs) (upTo 2 fullInputs)
        ],
    testCase "E6: the smallest counterexamples of PR #641 are in the same tier of the shortened enumeration" $
      sequence_
        [ assertBool (name <> ": " <> show i) (i `elem` (upTo 4 inputs !! length (inElements i)))
        | (name, i) <-
            [ ("the heading past the figures (I6)", Input 3 1 [EPara 2, EFigure 2, EHeading, EPara 1]),
              ("the heading at a recto after a figure sent on (I8)", Input 3 1 [EPara 1, EFigure 3, ERecto]),
              ("the note of a heading after the figures sent on (I7)", Input 3 1 [EPara 1, EFigure 3, EFigure 1, ENotedHeading]),
              ("the heading before a paragraph of three lines, before golem-layout ADR 0021 (I6)", Input 4 1 [EPara 1, EHeading, EPara 3])
            ]
        ],
    testCase "an input drawn has the elements given, from the enumeration of docs/adr/0204 (docs/adr/0208)" $ do
      let drawn = sampleT 1 300 (drawInput 4)
      length drawn @?= 300
      assertBool "every input has 4 elements" (all ((== 4) . length . inElements) drawn)
      assertBool "every element is of its column" (all (\i -> all (`elem` elementsFor (inLines i)) (inElements i)) drawn)
      nub (map inLines drawn) `sameSet` [3 .. 8]
      nub (map inColumns drawn) `sameSet` [1, 2]
      assertBool "columns of 6 to 8 grid lines and figures left out of the shortened enumeration are drawn" (any (\i -> any (`notElem` shortElementsFor (inLines i)) (inElements i)) drawn)
      drawn @?= sampleT 1 300 (drawInput 4)
  ]
  where
    isFigure = \case
      EFigure _ -> True
      _ -> False
    sameSet as bs = assertBool (show as) (all (`elem` bs) as && all (`elem` as) bs)

-- outputs made by hand

-- | A column of a page: its page, its column, its grid lines and its slots.
column :: Int -> Int -> Int -> [Slotted] -> PageOut
column page c n ss = PageOut page c False (zip [0 ..] ss) [] [] [] [] (ColumnSet 1 0 0 0) [] n []

-- | A column whose slots start at the grid lines given.
columnAt :: Int -> Int -> Int -> [(Int, Slotted)] -> PageOut
columnAt page c n ss = (column page c n []) {poSlots = ss}

blank :: Int -> PageOut
blank page = (column page 0 3 []) {poBlank = True}

withNotes :: [(NoteId, Int, Int)] -> PageOut -> PageOut
withNotes ns p = p {poFootnotes = ns}

plainLines :: Int -> Int -> [LineBox]
plainLines base n = [LineBox (base + k) [] [] [] 0 | k <- [0 .. n - 1]]

para :: Int -> Int -> Flow
para base n = FParagraph (plainLines base n)

heading :: Int -> Flow
heading i = FHeading 2 False 1 (plainLines i 1)

recto :: Int -> Flow
recto i = FHeading 1 True 1 (plainLines i 1)

notedLine :: Int -> LineBox
notedLine i = LineBox i [NoteBody (noteOf i) 1] [] [] 0

-- | The invariants broken, with a separator of one grid line.
broken :: [Flow] -> [PageOut] -> [Invariant]
broken flows ps = map breachOf (breaches 1 flows ps)

predicateTests :: [TestTree]
predicateTests =
  [ testGroup
      "I1 every line and figure placed once"
      [ testCase "I1: a line not placed" $
          broken [para 0 2] [column 1 0 3 [SLine 0]] @?= [I1],
        testCase "I1: a line placed twice" $
          broken [para 0 1] [column 1 0 3 [SLine 0, SLine 0]] @?= [I1],
        testCase "I1: a figure not placed" $
          broken [para 0 1, FFigure 1000 1 [] []] [column 1 0 3 [SLine 0]] @?= [I1],
        testCase "I1: a blank page that holds a line" $
          broken [para 0 1] [(column 1 0 3 [SLine 0]) {poBlank = True}] @?= [I1],
        testCase "I1: the lines of a heading of two lines are placed by its slot" $
          broken [FHeading 2 False 1 (plainLines 0 2)] [column 1 0 3 [SHeading 0 2]] @?= []
      ],
    testGroup
      "I2 no column overflows"
      [ testCase "I2: four lines in a column of three" $
          broken [para 0 4] [column 1 0 3 (map SLine [0 .. 3])] @?= [I2],
        testCase "I2: two lines, a note and its separator in a column of three" $
          broken [FParagraph [notedLine 0, LineBox 1 [] [] [] 0]] [withNotes [(noteOf 0, 0, 1)] (column 1 0 3 [SLine 0, SLine 1])] @?= [I2],
        testCase "I2: a figure that ends past the column" $
          broken [para 0 2, FFigure 1000 2 [] []] [column 1 0 3 [SLine 0, SLine 1, SFigure 1000]] @?= [I2],
        testCase "I2: a column filled exactly is not broken" $
          broken [FParagraph [notedLine 0]] [withNotes [(noteOf 0, 0, 1)] (column 1 0 3 [SLine 0])] @?= [],
        testCase "I2: a heading recorded as taller than its column is not judged" $
          broken [FHeading 2 False 4 (plainLines 0 1)] [(column 1 0 3 [SHeading 0 1]) {poUnmet = [TallHeading 0 4 3]}] @?= [],
        testCase "I2: a figure taller than the column is broken" $
          broken [FFigure 1000 4 [] []] [column 1 0 3 [SFigure 1000]] @?= [I2],
        testCase "I2: the first line of a paragraph in an empty column, its note continued, is not judged" $
          broken
            [FParagraph [LineBox 0 [NoteBody (noteOf 0) 5] [] [] 0]]
            [withNotes [(noteOf 0, 0, 3)] (column 1 0 3 [SLine 0]), withNotes [(noteOf 0, 3, 2)] (column 2 0 3 [])]
            @?= []
      ],
    testGroup
      "I3 the order of the input"
      [ testCase "I3: two paragraphs swapped" $
          broken [para 0 1, para 1 1] [column 1 0 3 [SLine 1, SLine 0]] @?= [I3],
        testCase "I3: two figures swapped" $
          broken [FFigure 1000 1 [] [], FFigure 1001 1 [] []] [column 1 0 3 [SFigure 1001, SFigure 1000]] @?= [I3],
        testCase "I3: a figure before the line that precedes it" $
          broken [para 0 1, FFigure 1000 1 [] []] [column 1 0 3 [SFigure 1000, SLine 0]] @?= [I3],
        testCase "I3: a figure after the line that follows it (sent on) is not broken" $
          broken [FFigure 1000 3 [] [], para 0 1] [column 1 0 3 [SLine 0], column 2 0 3 [SFigure 1000]] @?= []
      ],
    testGroup
      "I4 no orphan"
      [ testCase "I4: the first line of three alone at the end of a column" $
          broken [para 0 1, para 1 3] [column 1 0 2 [SLine 0, SLine 1], column 2 0 2 [SLine 2, SLine 3]] @?= [I4],
        testCase "I4: in two columns of a page" $
          broken [para 0 1, para 1 3] [column 1 0 2 [SLine 0, SLine 1], column 1 1 2 [SLine 2, SLine 3]] @?= [I4],
        testCase "I4: the first line alone in an empty column is not broken" $
          broken [para 0 3] [column 1 0 3 [SLine 0], column 2 0 3 [SLine 1, SLine 2]] @?= [],
        testCase "I4: the first line after nothing but a heading is allowed, as in an empty column" $
          broken [heading 0, para 1 3] [column 1 0 2 [SHeading 0 1, SLine 1], column 2 0 2 [SLine 2, SLine 3]] @?= []
      ],
    testGroup
      "I5 no widow"
      [ testCase "I5: the last line of three alone in the next column" $
          broken [para 0 1, para 1 3] [column 1 0 3 (map SLine [0 .. 2]), column 2 0 3 [SLine 3]] @?= [I5],
        testCase "I5: a paragraph that starts an empty column and fills it is not broken" $
          broken [para 0 4] [column 1 0 3 (map SLine [0 .. 2]), column 2 0 3 [SLine 3]] @?= [],
        testCase "I5: the lines after nothing but a heading are allowed, as in an empty column" $
          broken [heading 0, para 1 3] [column 1 0 3 [SHeading 0 1, SLine 1, SLine 2], column 2 0 3 [SLine 3]] @?= []
      ],
    testGroup
      "I6 a heading with what follows"
      [ testCase "I6: a heading at the end of a column, the paragraph in the next" $
          broken [para 0 1, heading 1, para 2 2] [column 1 0 2 [SLine 0, SHeading 1 1], column 2 0 2 [SLine 2, SLine 3]] @?= [I6],
        testCase "I6: a heading apart from the second line of the paragraph after it" $
          broken [para 0 1, heading 1, para 2 3] [column 1 0 3 [SLine 0, SHeading 1 1, SLine 2], column 2 0 3 [SLine 3, SLine 4]] @?= [I4, I6],
        testCase "I6: a heading apart from the heading after it" $
          broken [para 0 1, heading 1, heading 2, para 3 1] [column 1 0 2 [SLine 0, SHeading 1 1], column 2 0 2 [SHeading 2 1, SLine 3]] @?= [I6],
        testCase "I6: a heading first in its column is not broken" $
          broken [heading 0, heading 1, para 2 2] [column 1 0 2 [SHeading 0 1], column 2 0 3 [SHeading 1 1, SLine 2, SLine 3]] @?= [],
        testCase "I6: a heading with a paragraph of one line in its column is not broken" $
          broken [para 0 1, heading 1, para 2 1] [column 1 0 3 [SLine 0, SHeading 1 1, SLine 2]] @?= [],
        testCase "I6: a heading apart from the third line of a paragraph of three lines" $
          broken [para 0 1, heading 1, para 2 3] [column 1 0 4 [SLine 0, SHeading 1 1, SLine 2, SLine 3], column 2 0 4 [SLine 4]] @?= [I5, I6],
        testCase "I6: a heading apart from the third line of a paragraph of four lines is not broken" $
          broken [para 0 1, heading 1, para 2 4] [column 1 0 4 [SLine 0, SHeading 1 1, SLine 2, SLine 3], column 2 0 4 [SLine 4, SLine 5]] @?= [],
        testCase "I6: a heading before a heading at a recto, left at the end of its column, is not broken" $
          broken [para 0 1, heading 1, recto 2, para 3 1] [column 1 0 2 [SLine 0, SHeading 1 1], blank 2, column 3 0 2 [SHeading 2 1, SLine 3]] @?= [],
        testCase "I6: the headings before a heading at a recto, apart, are broken" $
          broken [para 0 1, heading 1, heading 2, recto 3] [column 1 0 2 [SLine 0, SHeading 1 1], column 2 0 2 [SHeading 2 1], column 3 0 2 [SHeading 3 1]] @?= [I6]
      ],
    testGroup
      "I7 a note on the page of its mark"
      [ testCase "I7: the note of a line on the next page" $
          broken [FParagraph [notedLine 0]] [column 1 0 3 [SLine 0], withNotes [(noteOf 0, 0, 1)] (column 2 0 3 [])] @?= [I7],
        testCase "I7: a note continued on the next page is not broken" $
          broken
            [FParagraph [LineBox 0 [NoteBody (noteOf 0) 2] [] [] 0]]
            [withNotes [(noteOf 0, 0, 1)] (column 1 0 3 [SLine 0]), withNotes [(noteOf 0, 1, 1)] (column 2 0 3 [])]
            @?= [],
        testCase "I7: the note of a heading in the other column of its page is not broken" $
          broken [FHeading 2 False 1 [notedLine 0]] [column 1 0 3 [SHeading 0 1], withNotes [(noteOf 0, 0, 1)] (column 1 1 3 [])] @?= []
      ],
    testGroup
      "I8 a heading at a recto"
      [ testCase "I8: on an even page" $
          broken [para 0 1, recto 1] [column 1 0 3 [SLine 0], column 2 0 3 [SHeading 1 1]] @?= [I8],
        testCase "I8: after a line of its page" $
          broken [para 0 1, recto 1] [column 1 0 3 [SLine 0, SHeading 1 1]] @?= [I8],
        testCase "I8: in the second column" $
          broken [para 0 1, recto 1] [column 1 0 3 [SLine 0], column 1 1 3 [SHeading 1 1]] @?= [I8],
        testCase "I8: first on an odd page after a blank page is not broken" $
          broken [para 0 1, recto 1] [column 1 0 3 [SLine 0], blank 2, column 3 0 3 [SHeading 1 1]] @?= [],
        testCase "I8: after the figures sent on is broken" $
          broken [para 0 1, FFigure 1000 1 [] [], recto 1] [column 1 0 3 [SLine 0], blank 2, column 3 0 3 [SFigure 1000, SHeading 1 1]] @?= [I8]
      ],
    testGroup
      "P1 need-lines met"
      [ testCase "P1: the block after need-lines 2 with one grid line left before it" $
          broken [para 0 3, FNeedLines (controlSpan 0) 2, para 3 1] [column 1 0 4 (map SLine [0 .. 3])] @?= [P1],
        testCase "P1: the block after need-lines 2 after a figure, one grid line left" $
          broken [para 0 3, FFigure 1000 3 [] [], FNeedLines (controlSpan 0) 2, para 3 1] [column 1 0 4 (map SLine [0 .. 2]), columnAt 2 0 4 [(0, SFigure 1000), (3, SLine 3)]] @?= [P1],
        testCase "P1: the block first in an empty column is not broken" $
          broken [para 0 3, FNeedLines (controlSpan 0) 2, para 3 1] [column 1 0 4 (map SLine [0 .. 2]), column 2 0 4 [SLine 3]] @?= [],
        testCase "P1: the notes before the block count" $
          broken [FParagraph [notedLine 0], FNeedLines (controlSpan 0) 2, para 1 1] [withNotes [(noteOf 0, 0, 1)] (column 1 0 4 [SLine 0, SLine 1])] @?= [P1],
        testCase "P1: a need-lines beyond the column is not judged" $
          broken [para 0 3, FNeedLines (controlSpan 0) 5, para 3 1] [(column 1 0 4 (map SLine [0 .. 3])) {poUnmet = [UnmetNeedLines (controlSpan 0) 5]}] @?= []
      ],
    testGroup
      "P2 need-lines recorded only when beyond the column"
      [ testCase "P2: a need-lines met is recorded" $
          broken [para 0 1, FNeedLines (controlSpan 0) 2, para 1 1] [(column 1 0 4 [SLine 0, SLine 1]) {poUnmet = [UnmetNeedLines (controlSpan 0) 2]}] @?= [P2],
        testCase "P2: a need-lines beyond the column not recorded" $
          broken [para 0 1, FNeedLines (controlSpan 0) 5, para 1 1] [column 1 0 4 [SLine 0], column 2 0 4 [SLine 1]] @?= [P2],
        testCase "P2: a need-lines beyond the column recorded twice" $
          broken [para 0 1, FNeedLines (controlSpan 0) 5, para 1 1] [(column 1 0 4 [SLine 0]) {poUnmet = [UnmetNeedLines (controlSpan 0) 5]}, (column 2 0 4 [SLine 1]) {poUnmet = [UnmetNeedLines (controlSpan 0) 5]}] @?= [P2]
      ],
    testGroup
      "P3 and P4 blank lines"
      [ testCase "P3, P4: blank lines not dropped and not before their block" $
          broken [para 0 3, FFigure 1000 3 [] [], FBlank (controlSpan 0) 2, para 3 1] [column 1 0 4 (map SLine [0 .. 2]), column 2 0 4 [SFigure 1000], column 3 0 4 [SLine 3]] @?= [P3, P4],
        testCase "P3: blank lines before their block, the column overflowing" $
          broken [para 0 1, FBlank (controlSpan 0) 2, para 1 2] [columnAt 1 0 4 [(0, SLine 0), (3, SLine 1), (4, SLine 2)]] @?= [I2, P3],
        testCase "P4: blank lines dropped, their block not first in its column" $
          broken [para 0 1, FBlank (controlSpan 0) 1, para 1 1] [(column 1 0 4 [SLine 0, SLine 1]) {poUnmet = [DroppedBlank (controlSpan 0)]}] @?= [P4],
        testCase "P4: one of two blank lines dropped" $
          broken [para 0 1, FBlank (controlSpan 0) 1, FBlank (controlSpan 1) 1, para 1 1] [column 1 0 4 [SLine 0], (column 2 0 4 [SLine 1]) {poUnmet = [DroppedBlank (controlSpan 0)]}] @?= [P4],
        testCase "P3, P4: blank lines dropped at the top of a column, recorded once each, are not broken" $
          broken [para 0 4, FBlank (controlSpan 0) 1, FBlank (controlSpan 1) 1, para 4 1] [column 1 0 4 (map SLine [0 .. 3]), (column 2 0 4 [SLine 4]) {poUnmet = [DroppedBlank (controlSpan 0), DroppedBlank (controlSpan 1)]}] @?= [],
        testCase "P3, P4: blank lines right before their block are not broken" $
          broken [para 0 1, FBlank (controlSpan 0) 2, para 1 1] [columnAt 1 0 4 [(0, SLine 0), (3, SLine 1)]] @?= []
      ],
    testGroup
      "the figures that wait are passed over (golem-layout ADR 0026)"
      [ testCase "P1': a figure sent on by itself does not wait, the figure after it does" $
          waitingFigures [para 0 2, FFigure 1000 3 [] [], FFigure 1001 1 [] [], para 2 1] [column 1 0 4 (map SLine [0 .. 2]), columnAt 2 0 4 [(0, SFigure 1000), (3, SFigure 1001)]] @?= [1001],
        testCase "P1': a figure that waits placed before the paragraph after it, which goes on to the next column, waits" $
          -- page 1 has 2 grid lines left: the figure of 3 is sent on, the figure of 1 waits, and the paragraph of 3 lines goes to page 2 after them
          waitingFigures [para 0 2, FFigure 1000 3 [] [], FFigure 1001 1 [] [], para 2 3] [column 1 0 4 [SLine 0, SLine 1], columnAt 2 0 4 [(0, SFigure 1000), (3, SFigure 1001)], column 3 0 4 (map SLine [2 .. 4])] @?= [1001],
        testCase "P1': a figure moved by the need-lines before it does not wait, nor does the figure after it" $
          waitingFigures [para 0 3, FNeedLines (controlSpan 0) 2, FFigure 1000 3 [] [], FFigure 1001 1 [] []] [column 1 0 4 (map SLine [0 .. 2]), columnAt 2 0 4 [(0, SFigure 1000), (3, SFigure 1001)]] @?= [],
        testCase "P1': a figure placed before the paragraph written after it does not wait" $
          waitingFigures [para 0 1, FFigure 1000 1 [] [], para 1 1] [column 1 0 3 [SLine 0, SFigure 1000, SLine 1]] @?= [],
        testCase "P5: a figure at the end of the book placed where the flow before it ends does not wait" $
          waitingFigures [para 0 1, FFigure 1000 1 [] []] [column 1 0 3 [SLine 0, SFigure 1000]] @?= [],
        testCase "P5: the figure at the end of the book after a figure sent on waits" $
          waitingFigures [para 0 2, FFigure 1000 3 [] [], FFigure 1001 1 [] []] [column 1 0 3 [SLine 0, SLine 1], column 2 0 3 [SFigure 1000], column 3 0 3 [SFigure 1001]] @?= [1001],
        testCase "P1': need-lines before a figure that waits is judged for the paragraph after it, not for the figure" $
          broken
            [para 0 2, FFigure 1000 3 [] [], FNeedLines (controlSpan 0) 2, FFigure 1001 1 [] [], para 2 1]
            [column 1 0 4 (map SLine [0 .. 2]), columnAt 2 0 4 [(0, SFigure 1000), (3, SFigure 1001)]]
            @?= [],
        testCase "P1': need-lines before a figure that waits, the paragraph after it with one grid line left, is broken" $
          broken
            [para 0 3, FFigure 1000 3 [] [], FNeedLines (controlSpan 0) 2, FFigure 1001 1 [] [], para 3 1]
            [column 1 0 4 (map SLine [0 .. 3]), column 2 0 4 [SFigure 1000], column 3 0 4 [SFigure 1001]]
            @?= [P1],
        testCase "P4': blank lines before a figure that waits are judged with the paragraph after it" $
          broken
            [para 0 2, FFigure 1000 3 [] [], FBlank (controlSpan 0) 1, FFigure 1001 2 [] [], para 2 1]
            [columnAt 1 0 4 [(0, SLine 0), (1, SLine 1), (3, SLine 2)], column 2 0 4 [SFigure 1000], column 3 0 4 [SFigure 1001]]
            @?= [],
        testCase "P5: blank lines before figures that wait to the end of the book, not recorded, are broken" $
          broken
            [para 0 1, FFigure 1000 3 [] [], FBlank (controlSpan 0) 1, FFigure 1001 1 [] []]
            [column 1 0 3 [SLine 0], column 2 0 3 [SFigure 1000], column 3 0 3 [SFigure 1001]]
            @?= [P5],
        testCase "P5: blank lines before figures that wait to the end of the book, recorded twice, are broken" $
          broken
            [para 0 1, FFigure 1000 3 [] [], FBlank (controlSpan 0) 1, FFigure 1001 1 [] []]
            [column 1 0 3 [SLine 0], (column 2 0 3 [SFigure 1000]) {poUnmet = [DroppedBlank (controlSpan 0), DroppedBlank (controlSpan 0)]}, column 3 0 3 [SFigure 1001]]
            @?= [P5],
        testCase "P5: blank lines before figures that wait to the end of the book, recorded once, are not broken" $
          broken
            [para 0 1, FFigure 1000 3 [] [], FBlank (controlSpan 0) 1, FFigure 1001 1 [] []]
            [column 1 0 3 [SLine 0], (column 2 0 3 [SFigure 1000]) {poUnmet = [DroppedBlank (controlSpan 0)]}, column 3 0 3 [SFigure 1001]]
            @?= [],
        testCase "P5: blank lines at the end of the book, after the figures that wait, are not judged" $
          broken
            [para 0 1, FFigure 1000 3 [] [], FBlank (controlSpan 0) 1]
            [column 1 0 3 [SLine 0], column 2 0 3 [SFigure 1000]]
            @?= []
      ],
    testCase "I6: the output before golem-layout ADR 0013 and ADR 0019, a heading alone at the end of a page, is broken" $ do
      -- five lines, a heading whose note did not count, two lines on the next page
      let flows = [para 0 5, FHeading 2 False 1 [notedLine 20], para 30 2]
          before0013 = [withNotes [(noteOf 20, 0, 1)] (columnAt 1 0 8 (zip [0 ..] (map SLine [0 .. 4]) <> [(5, SHeading 20 1)])), column 2 0 8 [SLine 30, SLine 31]]
      broken flows before0013 @?= [I6],
    testGroup
      "P9 a space moved after the need-lines after it lays out the same (golem-layout ADR 0043)"
      [ testCase "P9: the same output for the input with the space moved breaks nothing" $
          p9SpaceMoved (const out) moving out @?= [],
        testCase "P9: another output for the input with the space moved is a breach" $
          map breachOf (p9SpaceMoved (const []) moving out) @?= [P9],
        testCase "P9: the input laid out again has the space after the need-lines" $
          p9SpaceMoved (\fs -> if fs == [para 0 1, need 0, FSpace 1, para 1 1] then out else []) moving out @?= [],
        testCase "P9: each space right before a need-lines is moved by itself" $
          map breachOf (p9SpaceMoved (const []) [para 0 1, FSpace 1, need 0, FSpace 1, need 1, para 1 1] out) @?= [P9, P9],
        testCase "P9: a space after the need-lines, or with a break, a no-break or a page-lines among the controls between the blocks, is not moved" $ do
          p9SpaceMoved (const []) [para 0 1, need 0, FSpace 1, para 1 1] out @?= []
          p9SpaceMoved (const []) [para 0 1, FBreak BreakPage, FSpace 1, need 0, para 1 1] out @?= []
          p9SpaceMoved (const []) [para 0 1, FSpace 1, need 0, FNoBreak (controlSpan 1), para 1 1] out @?= []
          p9SpaceMoved (const []) [para 0 1, FSpace 1, need 0, FAdjustLines (controlSpan 1) 1, para 1 1] out @?= []
          -- a break past the block after does not count
          map breachOf (p9SpaceMoved (const []) [para 0 1, FSpace 1, need 0, para 1 1, FBreak BreakPage] out) @?= [P9]
      ]
  ]
  where
    need m = FNeedLines (controlSpan m) 2
    moving = [para 0 1, FSpace 1, need 0, para 1 1]
    out = [columnAt 1 0 3 [(0, SLine 0), (2, SLine 1)]]

-- every input

{- | A known bug: its item in 「既知の不具合」 of the specification, the
shape of the inputs it is excused in, the breaches it excuses there, and
how many inputs up to each depth have them. The item goes when the ADR
that fixes the bug is in.
-}
data KnownBug = KnownBug
  { kbItem :: String,
    kbShape :: Input -> Bool,
    kbExcuses :: Input -> Breach -> Bool,
    kbCounts :: [(Int, Int)]
  }

-- | The known bugs, in the order of 「既知の不具合」: none since golem-layout ADR 0027.
knownBugs :: [KnownBug]
knownBugs = []

{- | The breaches of an input: of the predicates over its output, and of
P9 (golem-layout ADR 0043), which lays out again the input with a space
moved after the need-lines after it.
-}
breachesOf :: Input -> [Breach]
breachesOf input =
  let flows = enumFlows (inElements input)
      ps = paginateInput input
   in breaches 1 flows ps <> p9SpaceMoved (paginateFlowsOf input) flows ps

-- | The flows given laid out on the page of the input.
paginateFlowsOf :: Input -> [Flow] -> [PageOut]
paginateFlowsOf (Input c k _) = paginateWithin maxBound 1 (ColumnSet k 0 0 0) c

-- | The breaches no known bug excuses.
unexcused :: [KnownBug] -> Input -> [Breach]
unexcused bugs input = fst (judged bugs input)

{- | The breaches no known bug excuses, and for each known bug, in the
order of the list, whether it excuses a breach of the input: the input
is laid out once for both (docs/adr/0208).
-}
judged :: [KnownBug] -> Input -> ([Breach], [Bool])
judged bugs input =
  let shaped = map (`kbShape` input) bugs
      bs = breachesOf input
      excuses b br = kbShape b input && kbExcuses b input br
   in ( [br | br <- bs, not (any (`excuses` br) bugs)],
        [sh && any (kbExcuses b input) bs | (b, sh) <- zip bugs shaped]
      )

{- | The inputs each known bug excuses, in the order of the list. Strict,
so that the count of millions of inputs is a list of numbers.
-}
newtype Excused = Excused [Int]
  deriving stock (Eq, Show)

instance Semigroup Excused where
  Excused as <> Excused bs = let cs = add as bs in foldr seq () cs `seq` Excused cs
    where
      add (x : xs) (y : ys) = x + y : add xs ys
      add xs [] = xs
      add [] ys = ys

instance Monoid Excused where
  mempty = Excused []

-- | The violations of an input and the known bugs that excuse it.
judge :: [KnownBug] -> Input -> ([Violation], Excused)
judge bugs input =
  let (bs, excused) = judged bugs input
   in (map (\b -> Violation (show (breachOf b)) (breachWhy b)) bs, Excused (map fromEnum excused))

-- | Whether an input has a breach no known bug excuses.
violates :: Input -> Bool
violates = not . null . unexcused knownBugs

{- | An input of n elements drawn from the enumeration of docs/adr/0204:
its column of 3 to 8 grid lines, its pages of one or two columns, then
each element.
-}
drawInput :: Int -> SplitMix -> (Input, SplitMix)
drawInput n g0 =
  let (c, g1) = oneOf [3 .. 8] g0
      (k, g2) = oneOf [1, 2] g1
      go 0 g = ([], g)
      go m g = let (e, g') = oneOf (elementsFor c) g; (es, g'') = go (m - 1 :: Int) g' in (e : es, g'')
      (els, g3) = go n g2
   in (Input c k els, g3)

{- | The input with elements taken out as long as it still breaks an
invariant no known bug excuses ('shrinkList'): a counterexample drawn is
not the smallest, and this one is smaller.
-}
shrinkInput :: Input -> Input
shrinkInput (Input c k es) = Input c k (shrinkList (violates . Input c k) es)

report :: String -> Input -> [Violation] -> String
report what input vs =
  intercalate
    "\n"
    ( (what <> ":")
        : map (\v -> "  " <> violationRule v <> ": " <> violationDetail v) vs
          <> ["", "As a case of PaginateSpec:", "", renderCase name input]
    )
  where
    name = case vs of
      v : _ -> violationRule v <> ": " <> violationDetail v
      [] -> "no violation"

exhaustiveTests :: [TestTree]
exhaustiveTests =
  [ testCase "I1 to I8, P1 to P5 and P9 hold for every input up to GOLEM_ENUM_DEPTH elements, but the known bugs, which excuse as many inputs as pinned" $ do
      depth <- enumDepth
      -- built here, not in a value of its own, so that it is not held
      case tallyAllPar depth (inputsOver [3 .. 5] shortElementsFor) (judge knownBugs) of
        (Failed k input vs, _) -> assertFailure (report ("the smallest input that breaks an invariant has " <> show k <> " elements") input vs)
        (Passed _, Excused counted) -> do
          let wrong =
                [ (kbItem b, lookup depth (kbCounts b), n)
                | (b, n) <- zip knownBugs (counted <> repeat 0),
                  lookup depth (kbCounts b) /= Just n
                ]
          if null wrong
            then pure ()
            else
              assertFailure
                ( "at depth "
                    <> show depth
                    <> ", the inputs a known bug excuses differ from the count pinned:\n"
                    <> intercalate "\n" [item <> ": pinned " <> maybe "nothing" show pinned <> ", counted " <> show n | (item, pinned, n) <- wrong]
                ),
    testCase "I1 to I8, P1 to P5 and P9 hold for every input drawn from the enumeration of docs/adr/0204 one element past GOLEM_ENUM_DEPTH, GOLEM_ENUM_PAGINATION_SAMPLES of them, but the known bugs" $ do
      depth <- enumDepth
      count <- enumSamples
      let drawn = Tiers [sampleT sampleSeed count (drawInput (depth + 1))]
      case checkAllPar 0 drawn (fst . judge knownBugs) of
        Passed _ -> pure ()
        Failed _ input _ ->
          let small = shrinkInput input
           in assertFailure
                ( report
                    ( "an input drawn with "
                        <> show (depth + 1)
                        <> " elements breaks an invariant; with elements taken out as long as it still does, it has "
                        <> show (length (inElements small))
                    )
                    small
                    (fst (judge knownBugs small))
                ),
    testCase "a counterexample drawn is shrunk to one that breaks the invariant without any one of its elements" $ do
      -- an input that breaks no invariant is left as it is; a predicate of
      -- the input breaks with its elements taken out from the first on
      shrinkInput (Input 3 1 [EPara 1, EPara 2]) @?= Input 3 1 [EPara 1, EPara 2]
      let breaksWith4 (Input _ _ es) = length es >= 2 && EFigure 3 `elem` es
      inElements (Input 3 1 (shrinkList (breaksWith4 . Input 3 1) [EPara 1, EFigure 3, EPara 2, EHeading])) @?= [EFigure 3, EHeading]
  ]
