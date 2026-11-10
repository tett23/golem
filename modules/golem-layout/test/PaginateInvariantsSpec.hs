-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program: those
-- would hold every input checked (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The invariants of pagination checked on every small input
(docs/adr/0204): the enumeration of the inputs, the predicates I1 to I8,
PL1, PL2, PL3 and PL7 (I1, I2, I3 and I7 of docs/adr/0260),
P1 to P4 (golem-layout ADR 0025), P5 (golem-layout ADR 0026), P9
(golem-layout ADR 0043, P9′ of golem-layout ADR 0047), W3 (golem-layout
ADR 0044) and P11 (golem-layout ADR 0047) on outputs made by hand, and every
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

import Data.Bits (xor)
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
      testGroup "every input" exhaustiveTests,
      testGroup "the keep options of paragraph styles (docs/adr/0261)" keepTests,
      testGroup "the boxes of paragraph styles (docs/adr/0271)" boxTests
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

{- | The depth of the keep options (docs/adr/0261), an area of its own
(docs/adr ADR 0304): GOLEM_ENUM_KEEP_DEPTH, a whole number of 0 or more,
or 'prDepth'.
-}
keepDepth :: IO Int
keepDepth = wholeNumber "GOLEM_ENUM_KEEP_DEPTH" prDepth

{- | The inputs of the keep options drawn one element past their depth
(docs/adr ADR 0304): GOLEM_ENUM_KEEP_SAMPLES, or none.
-}
keepSamples :: IO Int
keepSamples = wholeNumber "GOLEM_ENUM_KEEP_SAMPLES" 0

-- | The seed of the inputs of the keep options drawn (docs/adr ADR 0304).
keepSeed :: Word64
keepSeed = 0x0304

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
  [ testCase "I2: in columns of 3 grid lines there are 23 elements, no figure taller than the column" $ do
      -- paragraphs of 1 to 4 lines, with and without a note, a heading
      -- with and without a note, a heading at a recto, figures of 1 to 3
      -- lines, a space and a break (docs/adr/0206), need-lines of 2 and
      -- blank lines of 1 and 2 lines (golem-layout ADR 0025), need-lines
      -- of c − 1 lines (golem-layout ADR 0035), and the starts of sections
      -- without a start and with 1 and 2 (docs/adr/0260)
      length (elementsFor 3) @?= 4 + 4 + 3 + 3 + 2 + 4 + 3
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
        @?= [ FParagraph defaultKeep [LineBox 0 [] [] [] 0, LineBox 1 [] [] [] 0],
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
    testCase "PL1, PL2, PL3, PL7: the sections start without a start and at 1 and 2, numbered among the controls (docs/adr/0260)" $ do
      [e | e@(ESection _) <- elementsFor 3] @?= [ESection Nothing, ESection (Just 1), ESection (Just 2)]
      enumFlows [ENeedLines, ESection (Just 2), EBlank 1, ESection Nothing] @?= [FNeedLines (controlSpan 0) 2, sectionFlow 1 (Just 2), FBlank (controlSpan 2) 1, sectionFlow 3 Nothing],
    testCase "the shortened enumeration has columns of 3 to 5 grid lines, and figures of 1, C - 1 and C lines (docs/adr/0208)" $ do
      [n | EFigure n <- shortElementsFor 3] @?= [1, 2, 3]
      [n | EFigure n <- shortElementsFor 4] @?= [1, 3, 4]
      [n | EFigure n <- shortElementsFor 5] @?= [1, 4, 5]
      [e | e <- shortElementsFor 5, not (isFigure e)] @?= [e | e <- elementsFor 5, not (isFigure e)]
      nub [(inLines i, inColumns i) | i <- concat (upTo 1 inputs)] @?= [(c, k) | c <- [3 .. 5], k <- [1, 2]]
      -- 23 elements of each column: 20 and the three starts of sections (docs/adr/0260)
      map length (upTo 3 inputs) @?= [6, 6 * 23, 6 * 23 ^ (2 :: Int), 6 * 23 ^ (3 :: Int)],
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
column page c n ss = PageOut page c False (zip [0 ..] ss) [] [] [] [] (ColumnSet 1 0 0 0) [] n [] [] []

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
para base n = FParagraph defaultKeep (plainLines base n)

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
          broken [FParagraph defaultKeep [notedLine 0, LineBox 1 [] [] [] 0]] [withNotes [(noteOf 0, 0, 1)] (column 1 0 3 [SLine 0, SLine 1])] @?= [I2],
        testCase "I2: a figure that ends past the column" $
          broken [para 0 2, FFigure 1000 2 [] []] [column 1 0 3 [SLine 0, SLine 1, SFigure 1000]] @?= [I2],
        testCase "I2: a column filled exactly is not broken" $
          broken [FParagraph defaultKeep [notedLine 0]] [withNotes [(noteOf 0, 0, 1)] (column 1 0 3 [SLine 0])] @?= [],
        testCase "I2: a heading recorded as taller than its column is not judged" $
          broken [FHeading 2 False 4 (plainLines 0 1)] [(column 1 0 3 [SHeading 0 1]) {poUnmet = [TallHeading 0 4 3]}] @?= [],
        testCase "I2: a figure taller than the column is broken" $
          broken [FFigure 1000 4 [] []] [column 1 0 3 [SFigure 1000]] @?= [I2],
        testCase "I2: the first line of a paragraph in an empty column, its note continued, is not judged" $
          broken
            [FParagraph defaultKeep [LineBox 0 [NoteBody (noteOf 0) 5] [] [] 0]]
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
          broken [FParagraph defaultKeep [notedLine 0]] [column 1 0 3 [SLine 0], withNotes [(noteOf 0, 0, 1)] (column 2 0 3 [])] @?= [I7],
        testCase "I7: a note continued on the next page is not broken" $
          broken
            [FParagraph defaultKeep [LineBox 0 [NoteBody (noteOf 0) 2] [] [] 0]]
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
      "PL1, PL2, PL3, PL7 the page labels and the breaks before sections (I1, I2, I3, I7 of docs/adr/0260)"
      [ testCase "PL1: a section at 2 that starts on an odd page" $
          broken [para 0 1, sectionFlow 0 (Just 2), para 1 1] [column 1 0 3 [SLine 0], blank 2, (column 3 0 3 [SLine 1]) {poSections = [0]}] @?= [PL1],
        testCase "PL1, PL2, PL3, PL7: a section at 1 on page 3 after a blank page breaks nothing" $
          broken [para 0 1, sectionFlow 0 (Just 1), para 1 1] [column 1 0 3 [SLine 0], blank 2, (column 3 0 3 [SLine 1]) {poSections = [0]}] @?= [],
        testCase "PL2: the pages after the first page of a section are numbered on from it" $
          broken [sectionFlow 0 (Just 3), para 0 4] [(column 1 0 3 (map SLine [0 .. 2])) {poSections = [0]}, column 2 0 3 [SLine 3]] @?= [],
        testCase "PL3: of two sections on one page, the last numbers it" $
          broken [para 0 1, sectionFlow 0 (Just 1), sectionFlow 1 Nothing, para 1 1] [column 1 0 3 [SLine 0], blank 2, (column 3 0 3 [SLine 1]) {poSections = [0, 1]}] @?= [],
        testCase "PL7: a line after a section on a page before its first page" $
          broken [para 0 1, sectionFlow 0 Nothing, para 1 1] [column 1 0 3 [SLine 0, SLine 1], (column 2 0 3 []) {poSections = [0]}] @?= [PL7],
        testCase "PL7: a line before a section on its first page" $
          broken [para 0 1, sectionFlow 0 Nothing, para 1 1] [(column 1 0 3 [SLine 0, SLine 1]) {poSections = [0]}] @?= [PL7],
        testCase "PL7: a section with no page and a line placed after it" $
          broken [para 0 1, sectionFlow 0 Nothing, para 1 1] [column 1 0 3 [SLine 0], column 2 0 3 [SLine 1]] @?= [PL7]
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
          broken [FParagraph defaultKeep [notedLine 0], FNeedLines (controlSpan 0) 2, para 1 1] [withNotes [(noteOf 0, 0, 1)] (column 1 0 4 [SLine 0, SLine 1])] @?= [P1],
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
      ],
    testGroup
      "P9′ a space moved after the need-lines past the figures that wait lays out the same (golem-layout ADR 0047)"
      [ testCase "P9′: the figure between the space and the need-lines is read as waiting" $
          waitingFigures passing passingOut @?= [1001],
        testCase "P9′: the same output for the input with the space moved past the figure that waits breaks nothing" $
          p9SpaceMoved (const passingOut) passing passingOut @?= [],
        testCase "P9′: another output for the input with the space moved past the figure that waits is a breach" $
          map breachOf (p9SpaceMoved (const []) passing passingOut) @?= [P9],
        testCase "P9′: the input laid out again has the space right after the need-lines, the figure that waits before them" $
          p9SpaceMoved (\fs -> if fs == [para 0 1, FFigure 1000 3 [] [], FFigure 1001 1 [] [], need 0, FSpace 1, para 1 1] then passingOut else []) passing passingOut @?= [],
        testCase "P9′: a space with a figure that does not wait, or a break, between it and the need-lines is not moved" $ do
          p9SpaceMoved (const []) [para 0 1, FFigure 1000 1 [] [], FSpace 1, FFigure 1001 1 [] [], need 0, para 1 1] [columnAt 1 0 5 [(0, SLine 0), (1, SFigure 1000), (3, SFigure 1001), (4, SLine 1)]] @?= []
          p9SpaceMoved (const []) [para 0 1, FFigure 1000 3 [] [], FSpace 1, FFigure 1001 1 [] [], FBreak BreakPage, need 0, para 1 1] passingOut @?= []
      ],
    testGroup
      "P11 the figures that wait do not part the space from the need-lines (golem-layout ADR 0047)"
      [ testCase "P11: the same output for the input with the figure before the space breaks nothing" $
          p11WaitingBeforeSpace (const passingOut) passing passingOut @?= [],
        testCase "P11: another output for the input with the figure before the space is a breach" $
          map breachOf (p11WaitingBeforeSpace (const []) passing passingOut) @?= [P11],
        testCase "P11: the input laid out again has the figure that waits before the space, and where the figure is is not compared" $
          p11WaitingBeforeSpace
            (\fs -> if fs == [para 0 1, FFigure 1000 3 [] [], FFigure 1001 1 [] [], FSpace 1, need 0, para 1 1] then take 2 passingOut <> [column 3 0 3 []] else [])
            passing
            passingOut
            @?= [],
        testCase "P11: a space with no figure that waits before the need-lines is not judged" $
          p11WaitingBeforeSpace (const []) moving out @?= []
      ],
    testGroup
      "W3 the figures that wait are read alike wherever the space is (golem-layout ADR 0044)"
      [ testCase "W3: an input moved that lays out otherwise is not judged" $
          w3WaitingAlike (const []) waitingMoved waitingOut @?= [],
        testCase "W3: the figures that wait read alike from the input with the space moved break nothing" $
          w3WaitingAlike (const waitingOut) waitingMoved waitingOut @?= [],
        testCase "W3: the smallest input of the section 「テスト設計」, a figure sent on, a space and need-lines 2, reads no figure waiting either way" $ do
          let input = Input 3 1 [EPara 2, EFigure 2, ESpace, ENeedLines, EFigure 1]
              flows = enumFlows (inElements input)
              ps = paginateInput input
          map breachWhy (w3WaitingAlike (paginateFlowsOf input) flows ps) @?= []
          waitingFigures flows ps @?= []
      ]
  ]
  where
    need m = FNeedLines (controlSpan m) 2
    moving = [para 0 1, FSpace 1, need 0, para 1 1]
    out = [columnAt 1 0 3 [(0, SLine 0), (2, SLine 1)]]
    -- a figure sent on behind a figure placed, with the space and the need-lines on either side
    waitingMoved = [para 0 1, FFigure 1000 1 [] [], FSpace 1, need 0, FFigure 1001 1 [] []]
    waitingOut = [columnAt 1 0 3 [(0, SLine 0), (1, SFigure 1000), (2, SFigure 1001)]]
    -- a figure sent on, a space, a figure that waits, need-lines 2 and the paragraph on line 2 of page 1 (golem-layout ADR 0047)
    passing = [para 0 1, FFigure 1000 3 [] [], FSpace 1, FFigure 1001 1 [] [], need 0, para 1 1]
    passingOut = [columnAt 1 0 3 [(0, SLine 0), (2, SLine 1)], column 2 0 3 [SFigure 1000], column 3 0 3 [SFigure 1001]]

-- the keep options (docs/adr/0261)

{- | The hash of the placements of every input of 'inputs' up to 3
elements, the 'ShortPart' recorded by docs/adr/0261 left out: pinned from
the implementation before docs/adr/0261 (K7). FNV-1a of 64 bits over the
characters of 'show' of each placement.
-}
placementsHash :: Word64
placementsHash = foldl' step 14695981039346656037 [c | t <- upTo 3 inputs, i <- t, c <- show (map placed (paginateInput i))]
  where
    step h c = (h `xor` fromIntegral (fromEnum c)) * 1099511628211
    placed p = (poNumber p, poColumn p, poBlank p, poSlots p, poFootnotes p, poLabels p, poMarks p, poTables p, poLines p, filter (not . isShort) (poUnmet p), poSections p)
    isShort = \case
      ShortPart {} -> True
      _ -> False

-- | The keep options: K1 to K6 by hand, every input of the keep options, and K7.
keepTests :: [TestTree]
keepTests =
  [ testCase "K7: every input of the enumeration of docs/adr/0208 up to 3 elements is placed as before docs/adr/0261" $
      placementsHash @?= 3327068915294146639,
    testCase "the elements of the keep options: 35 in columns of 3 grid lines" $ do
      length (keepElementsFor 3) @?= 15 + 6 + 2 + 4 + 4 + 4
      -- a keep-with-next only after a paragraph or a stanza, a start only before one
      enumFlows [EHeading, EKeepNext 2, EStart BreakPage, EPara 1] @?= [FHeading 2 False 1 [LineBox 0 [] [] [] 0], FSection (OfParagraph (controlSpan 1)) BreakPage, FParagraph defaultKeep [LineBox 1 [] [] [] 0]]
      enumFlows [EPara 1, EKeepNext 2, EStart BreakPage, EHeading] @?= [FParagraph defaultKeep [LineBox 0 [] [] [] 0], FKeepNext (controlSpan 0) 2, FHeading 2 False 1 [LineBox 1 [] [] [] 0]],
    testCase "KS3, KS4: an input of the keep options drawn with 5 elements is of their enumeration, and the same seed draws the same inputs (docs/adr ADR 0304)" $ do
      let drawn = sampleT 1 1000 (drawKeepInput 5)
      length drawn @?= 1000
      assertBool "every input has 5 elements" (all ((== 5) . length . inElements) drawn)
      assertBool "every input has a column of 3 to 5 grid lines" (all ((`elem` [3 .. 5]) . inLines) drawn)
      assertBool "every input has pages of one or two columns" (all ((`elem` [1, 2]) . inColumns) drawn)
      assertBool "every element is of the keep options of its column" (all (\i -> all (`elem` keepElementsFor (inLines i)) (inElements i)) drawn)
      -- the bounds: columns of 3 and 5 grid lines, one and two columns, the first and the last element
      assertBool "columns of 3 and 5 grid lines are drawn" (all (\c -> any ((== c) . inLines) drawn) [3, 5])
      assertBool "pages of one and two columns are drawn" (all (\k -> any ((== k) . inColumns) drawn) [1, 2])
      assertBool "the first and the last element are drawn" (all (\pick -> any (\i -> pick (keepElementsFor (inLines i)) `elem` inElements i) drawn) [(!! 0), \es -> es !! (length es - 1)])
      drawn @?= sampleT 1 1000 (drawKeepInput 5),
    testGroup
      "K1 to K6 by hand"
      [ testCase "K1 first part: one line of a paragraph of keep-first-lines 3 left at the end of a column" $
          keepBroken [FParagraph (Keep 3 1 False) (plainLines 0 4)] [column 1 0 3 [SLine 9, SLine 9, SLine 0], column 2 0 3 (map SLine [1 .. 3])] @?= [K1],
        testCase "K1, K2: a short part from an empty column with ShortPart recorded is not broken" $
          keepBroken [FParagraph (Keep 3 3 False) (plainLines 0 4)] [(column 1 0 3 (map SLine [0 .. 2])) {poUnmet = [ShortPart LastPart 0 3 1]}, column 2 0 3 [SLine 3]] @?= [],
        testCase "K2 last part: one line of a paragraph of keep-last-lines 3 alone in the next column" $
          keepBroken [para 9 1, FParagraph (Keep 1 3 False) (plainLines 0 4)] [column 1 0 4 [SLine 9, SLine 0, SLine 1, SLine 2], column 2 0 4 [SLine 3]] @?= [K2],
        testCase "K3 keep-all-lines: a paragraph broken from a column that was not empty" $
          keepBroken [para 9 1, FParagraph (Keep 2 2 True) (plainLines 0 4)] [column 1 0 3 [SLine 9, SLine 0, SLine 1], column 2 0 3 [SLine 2, SLine 3]] @?= [K3],
        testCase "K3: broken from an empty column with SplitKept recorded is not broken" $
          keepBroken [FParagraph (Keep 2 2 True) (plainLines 0 4)] [(column 1 0 3 (map SLine [0 .. 2])) {poUnmet = [SplitKept 0, ShortPart LastPart 0 2 1]}, column 2 0 3 [SLine 3]] @?= [],
        testCase "K4 keep-with-next: held and not recorded breaks nothing; held and recorded is broken" $ do
          let flows = [para 0 1, FKeepNext (controlSpan 0) 2, para 1 2]
          keepBroken flows [column 1 0 3 [SLine 0, SLine 1, SLine 2]] @?= []
          keepBroken flows [(column 1 0 3 [SLine 0, SLine 1, SLine 2]) {poUnmet = [UnmetKeepNext (controlSpan 0)]}] @?= [K4],
        testCase "K4: apart and recorded breaks nothing; apart and not recorded is broken" $ do
          let flows = [para 0 1, FKeepNext (controlSpan 0) 2, para 1 2]
          keepBroken flows [(column 1 0 3 [SLine 0]) {poUnmet = [UnmetKeepNext (controlSpan 0)]}, column 2 0 3 [SLine 1, SLine 2]] @?= []
          keepBroken flows [column 1 0 3 [SLine 0], column 2 0 3 [SLine 1, SLine 2]] @?= [K4],
        testCase "K5 start: a paragraph of a start of a page after a line of its page" $
          keepBroken [para 0 1, FSection (OfParagraph (controlSpan 0)) BreakPage, para 1 1] [column 1 0 3 [SLine 0, SLine 1]] @?= [K5],
        testCase "K5: of a recto on an even page" $
          keepBroken [para 0 1, FSection (OfParagraph (controlSpan 0)) BreakRecto, para 1 1] [column 1 0 3 [SLine 0], column 2 0 3 [SLine 1]] @?= [K5, K6],
        testCase "K6: a start of a page that skips a page" $
          keepBroken [para 0 1, FSection (OfParagraph (controlSpan 0)) BreakPage, para 1 1] [column 1 0 3 [SLine 0], blank 2, column 3 0 3 [SLine 1]] @?= [K6],
        testCase "K5, K6: a start of a column in the next column breaks nothing" $
          keepBroken [para 0 1, FSection (OfParagraph (controlSpan 0)) BreakColumn, para 1 1] [column 1 0 3 [SLine 0], column 1 1 3 [SLine 1]] @?= []
      ],
    testCase "K1 to K6 and I1 to I8 but I4 and I5 hold for every input of the keep options up to GOLEM_ENUM_KEEP_DEPTH elements (docs/adr ADR 0304)" $ do
      depth <- keepDepth
      -- keepInputs of docs/adr/0261: columns of 3 to 5 grid lines and
      -- 'keepElementsFor'; built here, not in a value of its own, which
      -- would hold every input checked (hundreds of millions at the depth
      -- of the nightly job, more than the memory of its runner)
      case checkAllPar depth (inputsOver [3 .. 5] keepElementsFor) keepViolations of
        Passed _ -> pure ()
        Failed k input vs -> assertFailure (report ("the smallest input of the keep options that breaks an invariant has " <> show k <> " elements") input vs),
    testCase "K1 to K6 and I1 to I8 but I4 and I5 hold for every input of the keep options drawn one element past GOLEM_ENUM_KEEP_DEPTH, GOLEM_ENUM_KEEP_SAMPLES of them (docs/adr ADR 0304)" $ do
      depth <- keepDepth
      count <- keepSamples
      let drawn = Tiers [sampleT keepSeed count (drawKeepInput (depth + 1))]
      case checkAllPar 0 drawn keepViolations of
        Passed _ -> pure ()
        Failed _ input _ ->
          let small = shrinkKeepInput input
           in assertFailure
                ( report
                    ( "an input of the keep options drawn with "
                        <> show (depth + 1)
                        <> " elements breaks an invariant; with elements taken out as long as it still does, it has "
                        <> show (length (inElements small))
                    )
                    small
                    (keepViolations small)
                )
  ]
  where
    keepBroken flows ps = map breachOf (keepBreaches 1 flows ps)

-- | The boxes: the elements, B1 to B3 by hand, examples, and every input of boxes.
boxTests :: [TestTree]
boxTests =
  [ testCase "the elements of boxes: 19 in columns of 3 grid lines" $ do
      length (boxElementsFor 3) @?= 8 + 2 + 4 + 5
      enumFlows [EPara 1, EBoxed 1 2, EBoxedPair 0]
        @?= [ para 0 1,
              FBoxed 1 1 1 [FParagraph defaultKeep (plainLines 1 2)],
              FBoxed 3 0 0 [FParagraph defaultKeep (plainLines 3 2), FSpace 1, FParagraph defaultKeep (plainLines 5 2)]
            ],
    testGroup
      "B1 to B3 by hand"
      [ testCase "B1 shape: a part one grid line short before its first line breaks B1 only" $
          boxBroken [boxed 0 1 2] [inBoxes [BoxSegment 0 1 3] (columnAt 1 0 5 [(1, SLine 0), (2, SLine 1)])] @?= [B1],
        testCase "B1: a part k grid lines before and after its lines breaks nothing" $
          boxBroken [boxed 0 1 2] [inBoxes [BoxSegment 0 0 3] (columnAt 1 0 5 [(1, SLine 0), (2, SLine 1)])] @?= [],
        testCase "B2 no overflow: a part whose grid lines after go past the column breaks B2 only" $
          boxBroken [boxed 0 1 2] [inBoxes [BoxSegment 0 1 4] (columnAt 1 0 4 [(2, SLine 0), (3, SLine 1)])] @?= [B2],
        testCase "B3 no empty part: a part with no line of its box breaks B3 only" $
          boxBroken [para 9 1, boxed 0 0 1] [inBoxes [BoxSegment 0 1 1] (columnAt 1 0 3 [(0, SLine 9)]), inBoxes [BoxSegment 0 0 0] (columnAt 2 0 3 [(0, SLine 0)])] @?= [B3],
        testCase "B3: a line of a box in no part of it breaks B3 only" $
          boxBroken [boxed 0 0 1] [columnAt 1 0 3 [(0, SLine 0)]] @?= [B3]
      ],
    testGroup
      "examples"
      [ testCase "a box at the top of a column takes its k grid lines before, the space before it dropped" $ do
          let ps = paginate 1 5 [FSpace 1, boxed 0 1 2]
          [(poSlots p, poBoxes p) | p <- ps] @?= [([(1, SLine 0), (2, SLine 1)], [BoxSegment 0 0 3])],
        testCase "a box that the last grid lines of a column do not hold starts the next column" $ do
          let ps = paginate 1 5 [para 10 3, boxed 0 1 1]
          [(poNumber p, poSlots p, poBoxes p) | p <- ps] @?= [(1, [(0, SLine 10), (1, SLine 11), (2, SLine 12)], []), (2, [(1, SLine 0)], [BoxSegment 0 0 2])],
        testCase "each part of a box broken between columns takes k grid lines before and after" $ do
          let ps = paginate 1 5 [boxed 0 1 6]
          [(poNumber p, map fst (poSlots p), poBoxes p) | p <- ps] @?= [(1, [1, 2, 3], [BoxSegment 0 0 4]), (2, [1, 2, 3], [BoxSegment 0 0 4])],
        testCase "a box in the middle of a column broken between its two paragraphs: each part takes k grid lines before and after" $ do
          let ps = paginate 1 5 [para 10 1, FBoxed 0 1 1 [FParagraph defaultKeep (plainLines 0 2), FSpace 1, FParagraph defaultKeep (plainLines 2 2)]]
          [(poNumber p, poSlots p, poBoxes p) | p <- ps] @?= [(1, [(0, SLine 10), (2, SLine 0), (3, SLine 1)], [BoxSegment 0 1 4]), (2, [(1, SLine 2), (2, SLine 3)], [BoxSegment 0 0 3])]
      ],
    testCase "B1 to B3 and I1 to I8, P1 to P5, PL1, PL2, PL3, PL7 hold for every input of boxes up to GOLEM_ENUM_DEPTH elements" $ do
      depth <- enumDepth
      -- boxInputs of docs/adr/0271: columns of 3 to 5 grid lines and
      -- 'boxElementsFor'; built here, not in a value of its own, which
      -- would hold every input checked
      case checkAllPar depth (inputsOver [3 .. 5] boxElementsFor) (\input -> [Violation (show (breachOf b)) (breachWhy b) | b <- boxBreaches 1 (enumFlows (inElements input)) (paginateInput input)]) of
        Passed _ -> pure ()
        Failed k input vs -> assertFailure (report ("the smallest input of boxes that breaks an invariant has " <> show k <> " elements") input vs)
  ]
  where
    boxBroken flows ps = map breachOf (boxBreaches 1 flows ps)
    boxed i k n = FBoxed i k k [FParagraph defaultKeep (plainLines i n)]
    inBoxes bs p = p {poBoxes = bs}

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

{- | The breaches of an input: of the predicates over its output, of P9
(golem-layout ADR 0043, P9′ of golem-layout ADR 0047), which lays out
again the input with a space moved after the need-lines after it, of W3
(golem-layout ADR 0044), which reads the figures that wait from that
input when it lays out the same, and of P11 (golem-layout ADR 0047),
which lays out again the input with the figures that wait between a
space and a need-lines written before the space.
-}
breachesOf :: Input -> [Breach]
breachesOf input =
  let flows = enumFlows (inElements input)
      ps = paginateInput input
      lay = paginateFlowsOf input
      once = seen flows ps
   in breachesIn 1 once <> movedBreaches lay once

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
drawInput = drawOver [3 .. 8] elementsFor

{- | An input of n elements drawn from the enumeration of the keep options
(docs/adr/0261, docs/adr ADR 0304): its column of 3 to 5 grid lines, its
pages of one or two columns, then each element of 'keepElementsFor'.
-}
drawKeepInput :: Int -> SplitMix -> (Input, SplitMix)
drawKeepInput = drawOver [3 .. 5] keepElementsFor

-- | An input of n elements: its column of one of cs grid lines, its pages of one or two columns, then each element of its column.
drawOver :: [Int] -> (Int -> [Element]) -> Int -> SplitMix -> (Input, SplitMix)
drawOver cs els n g0 =
  let (c, g1) = oneOf cs g0
      (k, g2) = oneOf [1, 2] g1
      go 0 g = ([], g)
      go m g = let (e, g') = oneOf (els c) g; (es, g'') = go (m - 1 :: Int) g' in (e : es, g'')
      (es0, g3) = go n g2
   in (Input c k es0, g3)

{- | The input with elements taken out as long as it still breaks an
invariant no known bug excuses ('shrinkList'): a counterexample drawn is
not the smallest, and this one is smaller.
-}
shrinkInput :: Input -> Input
shrinkInput (Input c k es) = Input c k (shrinkList (violates . Input c k) es)

-- | The keep options and the invariants but I4 and I5 an input of them breaks (docs/adr/0261).
keepViolations :: Input -> [Violation]
keepViolations input = [Violation (show (breachOf b)) (breachWhy b) | b <- keepBreaches 1 (enumFlows (inElements input)) (paginateInput input)]

-- | 'shrinkInput' for the keep options: elements taken out as long as the input still breaks an invariant (docs/adr ADR 0304).
shrinkKeepInput :: Input -> Input
shrinkKeepInput (Input c k es) = Input c k (shrinkList (not . null . keepViolations . Input c k) es)

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
  [ testCase "I1 to I8, P1 to P5, P9 (P9′), P11, W3, and PL1, PL2, PL3, PL7 (I1, I2, I3, I7 of docs/adr/0260) hold for every input up to GOLEM_ENUM_DEPTH elements, but the known bugs, which excuse as many inputs as pinned" $ do
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
    testCase "I1 to I8, P1 to P5, P9 (P9′), P11, W3, and PL1, PL2, PL3, PL7 (docs/adr/0260) hold for every input drawn from the enumeration of docs/adr/0204 one element past GOLEM_ENUM_DEPTH, GOLEM_ENUM_PAGINATION_SAMPLES of them, but the known bugs" $ do
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
