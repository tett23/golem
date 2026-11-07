{- | The invariants of pagination checked on every small input
(docs/adr/0204): the enumeration of the inputs, the predicates I1 to I8
on outputs made by hand, and every input up to the depth of
@GOLEM_ENUM_DEPTH@ elements, with the known bugs excluded by an explicit
list whose counterexamples are counted.
-}
module PaginateInvariantsSpec (invariantTests, prDepth) where

import Data.List (intercalate)
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
30 seconds longer, so the pull requests check 3).
The nightly job raises it with GOLEM_ENUM_DEPTH.
-}
prDepth :: Int
prDepth = 3

-- | The depth: GOLEM_ENUM_DEPTH, a whole number of 0 or more, or 'prDepth'.
enumDepth :: IO Int
enumDepth =
  lookupEnv "GOLEM_ENUM_DEPTH" >>= \case
    Nothing -> pure prDepth
    Just "" -> pure prDepth
    Just s -> case readMaybe s of
      Just n | n >= 0 -> pure n
      _ -> assertFailure ("GOLEM_ENUM_DEPTH is not a whole number of 0 or more: " <> show s)

enumerationTests :: [TestTree]
enumerationTests =
  [ testCase "in columns of 3 grid lines there are 17 elements" $
      -- paragraphs of 1 to 4 lines, with and without a note, a heading
      -- with and without a note, a heading at a recto, figures of 1 to 4
      -- lines, a space and a break
      length (elementsFor 3) @?= 4 + 4 + 3 + (3 + 1) + 2,
    testCase "in columns of 3 grid lines, the flows of up to 2 elements are as many as the elements allow" $ do
      let m = length (elementsFor 3)
          made = [i | t <- upTo 2 inputs, i <- t, inLines i == 3]
      length made @?= 2 * sum [m ^ n | n <- [0 .. 2 :: Int]]
      length [i | i <- made, inColumns i == 2] @?= sum [m ^ n | n <- [0 .. 2 :: Int]],
    testCase "tier n holds the flows of n elements, over 6 sizes of column and 2 numbers of columns" $
      map length (upTo 2 inputs) @?= [12, sum [2 * length (elementsFor c) | c <- [3 .. 8]], sum [2 * length (elementsFor c) ^ (2 :: Int) | c <- [3 .. 8]]],
    testCase "the lines are numbered from 0 in the order of the flow, the figures from 1000" $
      enumFlows [EPara 2, EFigure 3, ENotedHeading, ESpace, EBreak, EFigure 1, ERecto]
        @?= [ FParagraph [LineBox 0 [] [] [] 0, LineBox 1 [] [] [] 0],
              FFigure 1000 3 [] [],
              FHeading 2 False 1 [LineBox 2 [NoteBody (noteOf 2) 1] [] [] 0],
              FSpace 1,
              FBreak BreakPage,
              FFigure 1001 1 [] [],
              FHeading 1 True 1 [LineBox 3 [] [] [] 0]
            ]
  ]

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
        testCase "I2: a figure taller than the column is not judged" $
          broken [FFigure 1000 4 [] []] [column 1 0 3 [SFigure 1000]] @?= [],
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
        testCase "I4: the first line after nothing but a heading is not judged" $
          broken [heading 0, para 1 3] [column 1 0 2 [SHeading 0 1, SLine 1], column 2 0 2 [SLine 2, SLine 3]] @?= []
      ],
    testGroup
      "I5 no widow"
      [ testCase "I5: the last line of three alone in the next column" $
          broken [para 0 1, para 1 3] [column 1 0 3 (map SLine [0 .. 2]), column 2 0 3 [SLine 3]] @?= [I5],
        testCase "I5: a paragraph that starts an empty column and fills it is not broken" $
          broken [para 0 4] [column 1 0 3 (map SLine [0 .. 2]), column 2 0 3 [SLine 3]] @?= [],
        testCase "I5: the lines after nothing but a heading are not judged" $
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
        testCase "I6: a heading before a heading at a recto is not judged" $
          broken [para 0 1, heading 1, recto 2] [column 1 0 2 [SLine 0, SHeading 1 1], blank 2, column 3 0 2 [SHeading 2 1]] @?= []
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
        testCase "I8: after the figures sent on is not judged" $
          broken [para 0 1, FFigure 1000 1 [] [], recto 1] [column 1 0 3 [SLine 0], blank 2, column 3 0 3 [SFigure 1000, SHeading 1 1]] @?= []
      ],
    testCase "I6: the output before golem-layout ADR 0013 and ADR 0019, a heading alone at the end of a page, is broken" $ do
      -- five lines, a heading whose note did not count, two lines on the next page
      let flows = [para 0 5, FHeading 2 False 1 [notedLine 20], para 30 2]
          before0013 = [withNotes [(noteOf 20, 0, 1)] (columnAt 1 0 8 (zip [0 ..] (map SLine [0 .. 4]) <> [(5, SHeading 20 1)])), column 2 0 8 [SLine 30, SLine 31]]
      broken flows before0013 @?= [I6]
  ]

-- every input

{- | A known bug (the specification, 「既知の不具合」): the shape of the
inputs it is excused in, the breaches it excuses there, and how many
inputs up to each depth have them. The item goes when the ADR that fixes
the bug is in.
-}
data KnownBug = KnownBug
  { kbItem :: String,
    kbShape :: Input -> Bool,
    kbExcuses :: Input -> Breach -> Bool,
    kbCounts :: [(Int, Int)]
  }

knownBugs :: [KnownBug]
knownBugs =
  [ KnownBug
      { kbItem = "BUG-A recto after a figure sent on",
        kbShape = \i -> any (\(k, e) -> e == ERecto && any isFigure (take k (inElements i))) (zip [0 ..] (inElements i)),
        kbExcuses = \i b -> breachOf b `elem` [I6, I8] && maybe False (\k -> inElements i !! k == ERecto && any isFigure (take k (inElements i))) (elementOf i b),
        kbCounts = []
      },
    KnownBug
      { kbItem = "BUG-B heading before a paragraph of three lines",
        kbShape = \i -> any (\(k, e) -> isHeadingElement e && threeLinesAfter i k) (zip [0 ..] (inElements i)),
        kbExcuses = \i b -> breachOf b == I6 && maybe False (threeLinesAfter i) (elementOf i b),
        kbCounts = []
      },
    KnownBug
      { kbItem = "BUG-C note of a heading after figures sent on",
        kbShape = \i -> any (\(k, e) -> e == ENotedHeading && any isFigure (take k (inElements i))) (zip [0 ..] (inElements i)),
        kbExcuses = \i b -> breachOf b == I7 && maybe False (\k -> inElements i !! k == ENotedHeading && any isFigure (take k (inElements i))) (elementOf i b),
        kbCounts = []
      },
    KnownBug
      { kbItem = "BUG-D heading after a figure",
        kbShape = \i -> any (\(k, e) -> isHeadingElement e && any isFigure (take k (inElements i))) (zip [0 ..] (inElements i)),
        kbExcuses = \i b -> breachOf b == I6 && maybe False (\k -> isHeadingElement (inElements i !! k) && any isFigure (take k (inElements i))) (elementOf i b),
        kbCounts = []
      }
  ]

isFigure :: Element -> Bool
isFigure = \case
  EFigure _ -> True
  _ -> False

isHeadingElement :: Element -> Bool
isHeadingElement e = e == EHeading || e == ENotedHeading

-- | Whether the headings after the element k end in a paragraph of three lines.
threeLinesAfter :: Input -> Int -> Bool
threeLinesAfter i k = any isThreeLines (take 1 (dropWhile isHeadingElement (drop (k + 1) (inElements i))))

isThreeLines :: Element -> Bool
isThreeLines e = e == EPara 3 || e == ENotedPara 3

-- | The lines of an element.
elementLines :: Element -> Int
elementLines = \case
  EPara n -> n
  ENotedPara n -> n
  EHeading -> 1
  ENotedHeading -> 1
  ERecto -> 1
  _ -> 0

-- | The index of the element whose first line is the first line of the breach.
elementOf :: Input -> Breach -> Maybe Int
elementOf i b = case breachAt b of
  l : _ ->
    let starts = scanl (+) 0 (map elementLines (inElements i))
     in lookup l [(st, k) | (k, (st, e)) <- zip [0 ..] (zip starts (inElements i)), elementLines e > 0]
  [] -> Nothing

-- | The breaches of an input.
breachesOf :: Input -> [Breach]
breachesOf input = breaches 1 (enumFlows (inElements input)) (paginateInput input)

-- | The breaches no known bug excuses.
unexcused :: [KnownBug] -> Input -> [Breach]
unexcused bugs input =
  let excusing = [b | b <- bugs, kbShape b input]
   in [br | br <- breachesOf input, not (any (\b -> kbExcuses b input br) excusing)]

-- | How many inputs up to the depth each known bug excuses, in the order of the list.
excusedCounts :: Int -> [KnownBug] -> [Int]
excusedCounts depth bugs =
  let excusedBy i =
        let shaped = [b | b <- bugs, kbShape b i]
            bs = if null shaped then [] else breachesOf i
         in [not (null shaped) && kbShape b i && any (kbExcuses b i) bs | b <- bugs]
   in foldl' (zipWith (\n e -> if e then n + 1 else n)) (map (const 0) bugs) (map excusedBy (concat (upTo depth inputs)))

report :: Int -> Input -> [Violation] -> String
report k input vs =
  intercalate
    "\n"
    ( ("the smallest input that breaks an invariant has " <> show k <> " elements:")
        : map (\v -> "  " <> violationRule v <> ": " <> violationDetail v) vs
        <> ["", "As a case of PaginateSpec:", "", renderCase name input]
    )
  where
    name = case vs of
      v : _ -> violationRule v <> ": " <> violationDetail v
      [] -> "no violation"

exhaustiveTests :: [TestTree]
exhaustiveTests =
  [ testCase "I1 to I8 hold for every input up to GOLEM_ENUM_DEPTH elements, but the known bugs" $ do
      depth <- enumDepth
      case checkAll depth inputs (map (\b -> Violation (show (breachOf b)) (breachWhy b)) . unexcused knownBugs) of
        Passed _ -> pure ()
        Failed k input vs -> assertFailure (report k input vs),
    testCase "each known bug excuses as many inputs as pinned" $ do
      depth <- enumDepth
      let counted = zip knownBugs (excusedCounts depth knownBugs)
          wrong = [(kbItem b, lookup depth (kbCounts b), n) | (b, n) <- counted, lookup depth (kbCounts b) /= Just n]
      if null wrong
        then pure ()
        else
          assertFailure
            ( "at depth " <> show depth <> ", the inputs each known bug excuses differ from the counts pinned (item, pinned, counted):\n"
                <> intercalate "\n" (map show wrong)
            )
  ]
