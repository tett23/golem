{-# LANGUAGE LambdaCase #-}

-- Root ADR 0352, the free placement of root ADR 0397: prints boundary
-- inputs of golem-layout's paginatePhysical as "in" lines, each followed
-- by the pages it gives as "out" lines.  PhysicalBoundary.lean reads the
-- "in" lines, evaluates Physical.lean's paginate and prints the same
-- "out" lines; check.sh compares the two with diff.
module Main (main) where

import Control.Exception (AllocationLimitExceeded (..), evaluate, try)
import Control.Monad (replicateM)
import Data.Int (Int64)
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified
import GHC.Conc (disableAllocationLimit, enableAllocationLimit, setAllocationCounter)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry (..), codeSpan)
import Golem.Layout.Look (NoteId (..))
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Length (Sp (..))
import Golem.Project.Style (KeepParts (..))
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)
import System.Timeout (timeout)

-- | The column: capacity, separator and columns; the pitch and the face
-- of the lines whose id is at least 900 are 14 and 12 sp, and the heading
-- whose first line is 385 has the bounds 4 and 16 sp; the lines 702 and
-- 705 have a gap of 3 sp before them beside a wrapped figure, 712 of 5 sp;
-- the box 170 has a padding of 3 sp.
data Column = Column Int Int Int

settingsOf :: Column -> PhysicalSettings
settingsOf (Column cap sep cols) =
  PhysicalSettings 10 10 (Sp (fromIntegral cap)) (Sp (fromIntegral cap + 20)) (Sp (fromIntegral sep)) (ColumnSet cols 0 0 0) tall faces padding gaps bounds Nothing Set.empty noAvoid
  where
    tall = Map.fromList [(i, 14) | i <- [900 .. 999]]
    faces = Map.fromList [(i, 12) | i <- [900 .. 999]]
    bounds = Map.fromList [(385, (4, 16))]
    gaps = Map.fromList [(702, 3), (705, 3), (712, 5)]
    padding = Map.fromList [(170, 3)]

span0 :: SrcSpan
span0 = mkSpan (FileId 1) 0 1

line :: Int -> LineBox
line i = LineBox i [] [] [] 0

lines' :: Int -> Int -> [LineBox]
lines' base n = [line (base + i) | i <- [0 .. n - 1]]

noted :: Int -> Int -> Int -> Int -> [LineBox]
noted base n at m = [if j == at then l {lbNotes = [NoteBody (NoteId span0 (500 + base)) m]} else l | (j, l) <- zip [0 ..] (lines' base n)]

keeps :: [Keep]
keeps = [defaultKeep, Keep 1 1 False, Keep 2 2 True, Keep 3 2 False]

sides :: [RuleSide]
sides = [RuleSide 2 2 1 False Nothing, RuleSide 0 0 12 False (Just 5), RuleSide 0 0 12 False (Just 20), RuleSide 3 1 2 True Nothing]

ruled :: Int -> Maybe RuleSide -> Maybe RuleSide -> Bool -> Keep -> [LineBox] -> FlowAt Sp
ruled i b a j k ls = FRuled i b a j (RuleGrid 10 8) 0 (RuledLines k ls)

ruledHeading :: Int -> Maybe RuleSide -> Maybe RuleSide -> Bool -> Int -> [LineBox] -> FlowAt Sp
ruledHeading i b a recto e ls = FRuled i b a False (RuleGrid 10 8) 0 (RuledHeading recto (Sp (fromIntegral e)) ls)

para :: Int -> Int -> FlowAt Sp
para base n = FParagraph defaultKeep (lines' base n)

-- One to three paragraphs of each keep, in columns of 2 to 4 lines.
paragraphInputs :: [(Column, [FlowAt Sp])]
paragraphInputs =
  [ (Column cap 0 cols, zipWith (\j (k, n) -> FParagraph k (lines' (10 * j) n)) [0 ..] shape)
  | cap <- [20, 25, 30, 40],
    cols <- [1, 2],
    count <- [1 .. 3],
    shape <- replicateM count [(k, n) | k <- keeps, n <- [1 .. 5]],
    count < 3 || all ((<= 3) . snd) shape
  ]
    <> [ (Column cap 0 1, [FContinued k (lines' 0 n), para 10 m])
       | cap <- [20, 30],
         k <- keeps,
         n <- [1 .. 4],
         m <- [1, 2]
       ]
    <> [ (Column cap 0 1, [FParagraph k (lines' 900 n), para 10 m])
       | cap <- [25, 30, 42],
         k <- keeps,
         n <- [1 .. 4],
         m <- [1, 2]
       ]

-- Paragraphs, figures and turned figures in columns of 3 and 4 lines.
figureInputs :: [(Column, [FlowAt Sp])]
figureInputs =
  [ (Column cap 0 cols, zipWith element [0 ..] shape)
  | cap <- [30, 40],
    cols <- [1, 2],
    count <- [1 .. 4],
    shape <- replicateM count choices,
    length [() | Right _ <- shape] `elem` [1 .. 3]
  ]
  where
    choices = map Left [1 .. 3] <> map Right [Just 5, Just 10, Just 20, Just 30, Nothing]
    element j = \case
      Left n -> para (10 * j) n
      Right (Just e) -> FFigure (100 + j) e [] []
      Right Nothing -> FPageFigure (200 + j) [] []

-- One control between paragraphs, two controls before a last paragraph.
controlInputs :: [(Column, [FlowAt Sp])]
controlInputs =
  [ (Column cap 0 cols, [para 0 p | p > 0] <> [c] <> [para 20 n])
  | cap <- [20, 30, 40],
    cols <- [1, 2],
    p <- [0 .. 3],
    c <- controls,
    n <- [1 .. 3]
  ]
    <> [ (Column cap 0 1, [para 0 p, a, b, para 20 n])
       | cap <- [30, 40],
         p <- [1, 2],
         a <- controls,
         b <- controls,
         n <- [1, 3]
       ]
  where
    controls =
      [FSpace 5, FSpace 10, FBlank span0 1, FBlank span0 2, FNeedLines span0 2, FNeedLines span0 5]
        <> [FAdjustLines span0 (-1), FAdjustLines span0 1, FAdjustLines span0 3]
        <> [FNoBreak span0, FNoBreakLines span0 3, FNoBreakLines span0 0, FKeepNext span0 1, FKeepNext span0 2]
        <> [FBreak k | k <- [BreakColumn, BreakPage, BreakRecto, BreakVerso]]
        <> [FFigure 100 15 [] []]

-- A paragraph with a note before a last paragraph, with a separator of 0
-- and of 4 sp.
noteInputs :: [(Column, [FlowAt Sp])]
noteInputs =
  [ (Column cap sep cols, [para 0 p | p > 0] <> [FParagraph k (noted 10 n at m)] <> more <> [para 40 l])
  | cap <- [30, 40, 50],
    sep <- [0, 4],
    cols <- [1, 2],
    p <- [0 .. 2],
    k <- [defaultKeep, Keep 1 1 False],
    n <- [1 .. 3],
    at <- [0 .. n - 1],
    m <- [1 .. 5],
    more <- [[], [FFigure 100 20 [] []], [FBreak BreakPage]],
    l <- [1, 2]
  ]

-- Ruled blocks after a paragraph, alone and joined, before a last paragraph.
ruledInputs :: [(Column, [FlowAt Sp])]
ruledInputs =
  [ (Column cap 0 cols, [para 0 p | p > 0] <> [ruled 100 b a False k (lines' 10 n)] <> [para 20 l])
  | cap <- [30, 40, 60],
    cols <- [1, 2],
    p <- [0 .. 3],
    b <- Nothing : map Just sides,
    a <- Nothing : map Just sides,
    k <- [defaultKeep, Keep 2 2 True],
    n <- [1 .. 3],
    l <- [1, 2]
  ]
    <> [ (Column cap 0 1, [para 0 p] <> [ruled 100 (Just s) (Just s) False defaultKeep (lines' 10 n), ruled 101 (Just t) (Just t) True defaultKeep (lines' 20 m)] <> after <> [para 30 1])
       | cap <- [40, 60, 80],
         p <- [1 .. 3],
         s <- sides,
         t <- sides,
         n <- [1, 2],
         m <- [1, 2],
         after <- [[], [FKeepNext span0 1], [FNoBreak span0]]
       ]
    <> [ (Column cap 0 1, [para 0 p, ruled 100 (Just s) (Just s) False defaultKeep (lines' 900 n), para 30 1])
       | cap <- [40, 60],
         p <- [1, 2],
         s <- sides,
         n <- [1, 2]
       ]
    -- a spaced rule after that may go out of the column (root ADR 0450): it
    -- goes `inner` after the end of the face, at or past the end of the
    -- column, within the margin or past it
    <> [ (Column cap 0 1, [para 0 p | p > 0] <> [block] <> [para 30 1])
       | cap <- [30, 40, 50, 60],
         p <- [0 .. 3],
         s <- [RuleSide 2 0 3 True (Just 10), RuleSide 6 0 3 True (Just 4)],
         block <-
           [ruled 100 Nothing (Just s) False defaultKeep (lines' 10 n) | n <- [1 .. 3]]
             <> [ruledHeading 100 Nothing (Just s) False e ls | (e, ls) <- [(10, [line 300]), (20, [line 385])]]
       ]
    -- a ruled paragraph before a ruled heading marked as sharing its rule
    -- before, which shares the area of the rule after (root ADR 0449)
    <> [ (Column cap 0 1, [para 0 p, ruled 100 (Just s) (Just s) False defaultKeep (lines' 10 n), FRuled 101 (Just t) (Just t) True (RuleGrid 10 8) 0 (RuledHeading False (Sp e) (lines' 20 1)), para 30 1])
       | cap <- [40, 60],
         p <- [1, 2],
         s <- sides,
         t <- take 2 sides,
         n <- [1, 2],
         e <- [10, 20]
       ]
    -- the four pairs of a ruled paragraph or heading with a rule after and
    -- a ruled paragraph or heading with a rule before that joins it, with
    -- no space or a space between, in columns where the second block fits
    -- with the shared area, overflows it, or drops its rules (root ADR 0449)
    <> [ (Column cap 0 1, [para 0 p, first] <> between <> [second, para 30 1])
       | cap <- [36, 44, 60],
         p <- [1, 2],
         s <- [sides !! 0, sides !! 3],
         t <- [sides !! 0, sides !! 1],
         first <-
           [ruled 100 (Just s) (Just s) False defaultKeep (lines' 10 n) | n <- [1, 2]]
             <> [ruledHeading 100 (Just s) (Just s) False e ls | (e, ls) <- [(10, [line 300]), (20, [line 385])]],
         between <- [[], [FSpace 5]],
         second <-
           [ruled 101 (Just t) (Just t) True defaultKeep (lines' 20 m) | m <- [1, 2]]
             <> [FRuled 101 (Just t) (Just t) True (RuleGrid 10 8) 0 (RuledHeading False (Sp e) [line 310]) | e <- [10, 24]]
       ]
    -- a ruled paragraph with a note on one of its lines, whose lines keep
    -- the later lines and the area of the rule after out of their notes
    <> [ (Column cap 2 1, [para 0 p | p > 0] <> [ruled 100 Nothing (Just s) False (Keep 1 1 False) (noted 10 n at m), para 30 1])
       | cap <- [40, 60],
         p <- [0, 1],
         s <- sides,
         n <- [2, 3],
         at <- [0, 1],
         m <- [1 .. 4]
       ]
    -- a ruled paragraph taller than the room of the empty second column
    -- of a set switched to in the page, which fit keeps: it is broken
    -- there without rules (PR #1150, G07046)
    <> [ (Column 40 0 1, [para 0 2, FSwitchColumns (ColumnSet 2 0 0 0), para 10 2, ruled 100 Nothing (Just s) False defaultKeep (lines' 20 n), para 30 1])
       | s <- sides,
         n <- [2, 3]
       ]

-- A column made shorter before a tall line or a need-lines; chains of
-- keep-with-next and no-break; keeps before a paragraph with a note.
chainInputs :: [(Column, [FlowAt Sp])]
chainInputs =
  [ (Column cap 0 1, [para 0 p | p > 0] <> [FAdjustLines span0 a, f, para 60 1])
  | cap <- [20, 30],
    p <- [0, 1],
    a <- [-1, -2, -3],
    f <- [FParagraph defaultKeep (lines' 900 1), FParagraph (Keep 1 1 False) (lines' 900 2), FNeedLines span0 2, FNeedLines span0 3]
  ]
    <> [ (Column cap 0 1, [para 50 r | r > 0] <> [para 0 p, c1, para 10 q, c2, para 20 n])
       | cap <- [30, 40, 50],
         r <- [0 .. 2],
         p <- [1 .. 3],
         q <- [1, 2],
         n <- [1 .. 3],
         c1 <- [FKeepNext span0 1, FNoBreak span0, FKeepNext span0 2],
         c2 <- [FKeepNext span0 1, FNoBreak span0, FNoBreakLines span0 2]
       ]
    <> [ (Column cap sep 1, [para 50 r | r > 0] <> [para 0 p, c, FParagraph defaultKeep (noted 10 n 0 m), para 20 1])
       | cap <- [30, 40, 50],
         r <- [0 .. 2],
         sep <- [0, 4],
         p <- [1 .. 3],
         c <- [FKeepNext span0 1, FNoBreak span0, FBlank span0 1],
         n <- [1, 2],
         m <- [1 .. 3]
       ]

-- Inputs that fail: a footnote taller than the column with its separator,
-- a line taller than the column, a figure taller than the column.
failureInputs :: [(Column, [FlowAt Sp])]
failureInputs =
  [(Column 12 4 1, [para 0 1, FParagraph defaultKeep (noted 10 2 1 1)]), (Column 13 0 1, [para 0 1, FParagraph defaultKeep (lines' 900 1)])]
    <> [(Column 30 0 c, [para 0 1, FFigure 100 e [] []]) | c <- [1, 2], e <- [29, 30, 31]]

-- Starts of sections, and columns switched and restored, after paragraphs,
-- a figure sent on, a note carried on or a column break.
startInputs :: [(Column, [FlowAt Sp])]
startInputs =
  [ (Column cap 4 cols, pre <> ctl <> [para 20 n])
  | cap <- [30, 40],
    cols <- [1, 2],
    pre <- [[], [para 0 1], [para 0 3], [para 0 2, FFigure 100 20 [] []], [FParagraph defaultKeep (noted 0 2 1 3)], [para 0 1, FBreak BreakColumn]],
    ctl <- [[FSection (OfSection 1) k] | k <- kinds] <> [FSwitchColumns (ColumnSet c 0 0 0) : mid <> end | c <- [1, 2, 3], mid <- [[], [para 10 2], [para 10 5, FFigure 101 25 [] []]], end <- [[], [FRestoreColumns]]],
    n <- [1 .. 3]
  ]
    <> [ (Column 30 4 cols, [para 0 p, FSwitchColumns (ColumnSet 2 0 0 0), para 10 q, FSection (OfSection 2) k, para 20 1, FRestoreColumns, FSection (OfSection 3) k, para 30 2])
       | cols <- [1, 2],
         p <- [1 .. 3],
         q <- [1 .. 4],
         k <- kinds
       ]
    -- root ADR 0444: a note going on takes the room @page-lines adds first;
    -- root ADR 0441: the columns of a set started after @page-lines end at
    -- the type area or above the notes of the column before
    <> [ (Column cap sep cols, [FParagraph defaultKeep (noted 0 1 0 m), FAdjustLines span0 a] <> more <> [para 20 n])
       | cap <- [30, 50],
         sep <- [0, 10],
         cols <- [1, 2],
         m <- [3, 5],
         a <- [-1, 1, 2, 3, 4],
         more <- [[], [FParagraph defaultKeep (noted 10 1 0 1)], [FSwitchColumns (ColumnSet 2 0 0 0), para 10 3]],
         n <- [1, 3]
       ]
    <> [ (Column cap sep 1, [if m == 0 then para 0 p else FParagraph defaultKeep (noted 0 p 0 m), FAdjustLines span0 a, FSwitchColumns (ColumnSet c 0 0 0), para 10 q, para 20 1])
       | cap <- [30, 40],
         sep <- [0, 4],
         p <- [1, 2],
         m <- [0, 1, 2],
         a <- [-2, -1, 1, 2],
         c <- [2, 3],
         q <- [1 .. 6]
       ]
  where
    kinds = [BreakColumn, BreakPage, BreakRecto, BreakVerso]

-- Headings and definition terms after paragraphs, before what they keep.
headingInputs :: [(Column, [FlowAt Sp])]
headingInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [FSpace 5 | space] <> [FHeading 1 recto e ls] <> after <> [para 20 n])
  | cap <- [20, 30, 40],
    cols <- [1, 2],
    p <- [0, 1, 3],
    space <- [False, True],
    recto <- [False, True],
    (e, ls) <- [(10, [line 300]), (16, [line 300]), (24, lines' 300 2), (32, lines' 300 2), (16, noted 300 1 0 2)],
    after <- [[], [FHeading 2 False 12 [line 310]], [FKeepNext span0 2, FParagraph (Keep 1 1 False) (lines' 350 3)], [FSpace 5], [FDefTerm (lines' 320 1)], [ruled 100 (Just (sides !! 0)) Nothing False defaultKeep (lines' 330 1)], [FFigure 100 15 [] []], [FParagraph (Keep 2 2 True) (lines' 340 3)]],
    n <- [1 .. 3]
  ]
    <> [ (Column cap 4 cols, [para 0 p | p > 0] <> [FDefTerm (lines' 300 k)] <> after <> [para 20 n])
       | cap <- [20, 30, 35, 40],
         cols <- [1, 2],
         p <- [0 .. 3],
         k <- [1, 2],
         after <- [[], [FDefTerm (lines' 310 1)], [FKeepNext span0 2], [ruled 100 (Just (sides !! 3)) Nothing False defaultKeep (lines' 330 1)]],
         n <- [1 .. 3]
       ]
    <> [ (Column cap 4 1, [para 0 p | p > 0] <> [FAdjustLines span0 a, FHeading 1 False e [line 300], para 20 1])
       | cap <- [20, 30],
         p <- [0, 1],
         a <- [-1, -2],
         e <- [15, 20, 25, 30]
       ]
    <> [ (Column cap sep 1, [para 0 1, FHeading 1 False e (noted 300 1 0 m), para 20 2])
       | cap <- [30, 40],
         sep <- [0, 4],
         e <- [10, 20],
         m <- [1 .. 5]
       ]
    <> [ (Column cap sep 1, [FAdjustLines span0 (-1), FHeading 1 False e (noted 300 1 0 m), para 20 1])
       | cap <- [30, 40],
         sep <- [0, 4],
         e <- [10, 20],
         m <- [1 .. 5]
       ]
    <> [(Column 20 0 1, [para 0 1, FHeading 1 False 25 [line 300]])]

-- Turned figures with breaks, figures sent on and columns switched around them.
turnedInputs :: [(Column, [FlowAt Sp])]
turnedInputs =
  [ (Column cap 0 cols, pre <> [FPageFigure 200 [] []] <> mid <> [para 20 n])
  | cap <- [30, 40],
    cols <- [1, 2],
    pre <- [[], [para 0 1], [para 0 3], [para 0 1, FBreak BreakColumn], [para 0 2, FFigure 100 25 [] []], [para 0 1, FSwitchColumns (ColumnSet 2 0 0 0)]],
    mid <- [[], [FBreak BreakColumn], [FBreak BreakPage], [FFigure 101 20 [] []], [FPageFigure 201 [] []], [FSection (OfSection 1) BreakPage], [FBreak BreakColumn, FPageFigure 201 [] []], [para 10 1, FBreak BreakColumn]],
    n <- [1, 2]
  ]

-- Stanzas after paragraphs or a heading, before what they keep.
stanzaInputs :: [(Column, [FlowAt Sp])]
stanzaInputs =
  [ (Column cap 4 cols, pre <> [FStanza k (verses 10 shape)] <> after <> [para 40 n])
  | cap <- [20, 30, 40],
    cols <- [1, 2],
    pre <- [[], [para 0 1], [para 0 2], [FHeading 1 False 10 [line 300]]],
    k <- keeps,
    shape <- [[1], [1, 1], [2, 1], [1, 2, 1], [2, 2], [1, 1, 1, 1], [3, 1], [1, 3]],
    after <- [[], [FKeepNext span0 2], [FNoBreak span0]],
    n <- [1, 2]
  ]
    <> [ (Column 30 4 1, [para 0 p, FKeepNext span0 w, FStanza k (verses 10 shape), para 40 1])
       | p <- [1, 2],
         w <- [1, 3],
         k <- keeps,
         shape <- [[1, 1], [2, 1], [1, 2, 1]]
       ]
  where
    verses base shape = [lines' (base + 10 * j) m | (j, m) <- zip [0 ..] shape]

-- Code blocks of one and of padded grid lines a row, with captions and
-- continuation rows, after paragraphs and keeps.
codeInputs :: [(Column, [FlowAt Sp])]
codeInputs =
  [ (Column cap 0 cols, [para 0 p | p > 0] <> [FCode g c f k (lines' 600 r)] <> after <> [para 20 1])
  | cap <- [30, 40],
    cols <- [1, 2],
    p <- [0, 1, 3],
    g <- geometries,
    c <- [0, 10],
    f <- [1, 2],
    k <- [False, True],
    r <- [1 .. 5],
    after <- [[], [FKeepNext span0 1]]
  ]
    <> [ (Column cap 0 1, [para 0 p, ctl, FCode g 0 f False (lines' 600 r), para 20 1])
       | cap <- [30, 40],
         p <- [1, 2],
         ctl <- [FKeepNext span0 1, FKeepNext span0 3, FBlank span0 1],
         g <- geometries,
         f <- [1, 3],
         r <- [2, 4]
       ]
    <> [(Column 30 0 1, [FBlank span0 b, FCode g 0 1 False (lines' 600 r), para 20 1]) | b <- [1, 2], g <- geometries, r <- [2, 3]]
    <> [(Column 20 0 1, [para 0 1, FCode (geometries !! 1) 10 1 False (lines' 600 2)])]
  where
    geometries = [CodeGeometry 10 10 10 10 0, CodeGeometry 10 10 10 10 5]

-- Ruled headings after paragraphs, before what they keep, in a column made
-- shorter, and kept with a paragraph before them.
ruledHeadingInputs :: [(Column, [FlowAt Sp])]
ruledHeadingInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [ruledHeading 100 b a recto e ls] <> after <> [para 20 n])
  | cap <- [20, 30, 40],
    cols <- [1, 2],
    p <- [0, 1, 3],
    b <- hsides,
    a <- hsides,
    recto <- [False, True],
    (e, ls) <- [(10, [line 300]), (24, lines' 300 2), (20, [line 385]), (16, noted 300 1 0 2)],
    after <- [[], [FKeepNext span0 2, FParagraph (Keep 1 1 False) (lines' 350 3)], [FSpace 5], [ruledHeading 101 (Just (sides !! 0)) Nothing False 10 [line 310]], [FHeading 2 False 12 [line 320]]],
    n <- [1, 2]
  ]
    <> [ (Column cap 4 1, [para 0 p | p > 0] <> [FAdjustLines span0 j, ruledHeading 100 b a False e [line 300], para 20 1])
       | cap <- [20, 30],
         p <- [0, 1],
         j <- [-1, -2],
         b <- hsides,
         a <- hsides,
         e <- [10, 15, 20]
       ]
    <> [ (Column cap 4 1, [para 0 p, ctl, ruledHeading 100 b Nothing recto 10 [line 300], para 20 2])
       | cap <- [30, 40],
         p <- [1, 2, 3],
         ctl <- [FKeepNext span0 1, FNoBreak span0, FSpace 5],
         b <- hsides,
         recto <- [False, True]
       ]
    <> [ (Column cap 4 1, [para 0 1, FHeading 1 False 10 [line 300], ruledHeading 100 (Just s) (Just s) False 10 [line 310], para 20 n])
       | cap <- [30, 40],
         s <- sides,
         n <- [1, 2]
       ]
    <> [ (Column cap 4 1, [para 50 1, para 0 n, ctl, ruledHeading 100 (Just (sides !! 0)) Nothing recto 10 [line 300], para 20 2])
       | cap <- [40, 50, 60],
         n <- [3 .. 5],
         ctl <- [FKeepNext span0 1, FNoBreak span0],
         recto <- [False, True]
       ]
    <> [ (Column cap 4 1, pre <> [ruledHeading 100 b a False e (noted 300 1 0 m), para 20 1])
       | cap <- [30, 40, 60],
         pre <- [[], [FAdjustLines span0 (-1)], [FAdjustLines span0 (-2)], [para 0 1]],
         b <- hsides,
         a <- hsides,
         e <- [10, 20],
         m <- [1 .. 5]
       ]
  where
    hsides = [Nothing, Just (sides !! 0), Just (sides !! 1), Just (sides !! 3)]

-- The rules of ruled headings in the middle of a column (PR #1151, #1152):
-- a rule before after a plain line, a ruled paragraph's rule after or a
-- taller line takes the gap between the faces or the edge of the
-- heading's area, the outside only at the top of an empty column; a rule
-- after takes the gap before the next line with its outer space and the
-- next line's overhang, or the end of the column when that does not fit or
-- the next block has a rule before of its own.
ruledHeadingRuleInputs :: [(Column, [FlowAt Sp])]
ruledHeadingRuleInputs =
  [ (Column cap 0 1, lead <> [FRuled 100 b a False (RuleGrid 10 8) o (RuledHeading False (Sp e) ls)] <> next)
  | cap <- [30, 36, 60],
    lead <- [[], [para 0 1], [ruled 50 Nothing (Just (sides !! 0)) False defaultKeep (lines' 60 1)], [FParagraph defaultKeep (lines' 900 1)]],
    b <- [Nothing, Just (RuleSide 0 0 12 False (Just 20)), Just (sides !! 3)],
    a <- [Nothing, Just (RuleSide 4 6 2 True Nothing), Just (RuleSide 0 0 12 False Nothing), Just (sides !! 1)],
    o <- [0, 3],
    (e, ls) <- [(20, [line 300]), (20, [line 385]), (24, lines' 950 2)],
    next <- [[para 20 1], [FParagraph defaultKeep (lines' 960 2)], [ruledHeading 101 (Just (sides !! 0)) Nothing False 10 [line 310], para 30 1], [FSpace 5, para 20 1]]
  ]

-- Wrapped figures and the lines beside them after paragraphs, before what
-- follows, and after a figure sent on, a blank, a column made shorter, a
-- keep and a heading.  After a figure sent on, the line that does not fit
-- beside the figure has a note: it fits the next column, which the figure
-- sent on starts, but its note does not.
wrappedInputs :: [(Column, [FlowAt Sp])]
wrappedInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [FWrapped 150 (Sp e) [] [] ls] <> after <> [para 20 n])
  | cap <- [30, 40, 60],
    cols <- [1, 2],
    p <- [0, 1, 3],
    e <- [10, 25, 40, 61],
    ls <- [lines' 700 m | m <- [0 .. 5]] <> [noted 700 3 1 m | m <- [1, 3]] <> [lines' 710 3],
    after <- [[], [FFigure 100 15 [] []], [FKeepNext span0 1, para 30 2], [FSpace 5]],
    n <- [1, 2]
  ]
    <> [ (Column cap 4 1, [para 0 p] <> pre <> [FWrapped 150 (Sp e) [] [] (lines' 700 m), para 20 1])
       | cap <- [30, 40],
         p <- [1, 2],
         pre <- [[FFigure 100 25 [] []], [FBlank span0 1], [FAdjustLines span0 (-1)], [FKeepNext span0 1], [FHeading 1 False 10 [line 300]], [FSpace 5]],
         e <- [10, 25],
         m <- [1, 3]
       ]
    <> [ (Column 40 4 1, [para 0 2, FFigure 100 25 [] [], FWrapped 150 (Sp e) [] [] (noted 720 3 2 m), para 20 1])
       | e <- [10, 15],
         m <- [1, 2]
       ]

-- Tables after paragraphs, with and without a header, a caption above
-- and below, rows of one to three lines and with a note, before what
-- follows; a header with a note; a space before a table, and after a
-- figure sent on, a space before a table whose first part fits the column
-- without the space but neither with it nor in the next column; and a
-- header whose line is taller than the page pitch, which
-- paginatePhysical repeats for ever when the next row does not fit.
tableInputs :: [(Column, [FlowAt Sp])]
tableInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [FTable 160 (Sp b) header rows caption below] <> after <> [para 20 n])
  | cap <- [30, 40, 60],
    cols <- [1, 2],
    p <- [0, 1, 3],
    b <- [0, 5],
    header <- [[], [line 800], lines' 800 2],
    rows <- [[lines' 810 1], [lines' 810 1, lines' 820 2], [lines' 810 1, lines' 820 1, lines' 830 1, lines' 840 1], [lines' 810 3, lines' 820 1], [noted 810 1 0 2, lines' 820 1]],
    caption <- [[], [line 850]],
    below <- [False, True],
    after <- [[], [FKeepNext span0 1, para 30 2]],
    n <- [1, 2]
  ]
    <> [ (Column cap 4 1, [para 0 p | p > 0] <> [FTable 160 0 (noted 800 1 0 m) rows caption below, para 20 1])
       | cap <- [40, 50, 60],
         p <- [0 .. 3],
         m <- [1 .. 4],
         rows <- [[lines' 810 1, lines' 820 1], [noted 810 1 0 2, lines' 820 1], [noted 810 2 1 3], [lines' 810 1, noted 820 1 0 3]],
         caption <- [[], [line 850]],
         below <- [False, True]
       ]
    <> [ (Column cap 4 1, [para 0 p, gap, FTable 160 5 [line 800] [lines' 810 1, lines' 820 1] [] False, para 20 1])
       | cap <- [30, 40],
         p <- [1 .. 3],
         gap <- [FSpace 5, FSpace 10, FBlank span0 1]
       ]
    <> [ (Column 40 4 1, [para 0 2, FFigure 100 25 [] [], FSpace 5, FTable 160 0 header rows [] False, para 20 1])
       | (header, rows) <- [([], [lines' 810 2]), ([line 800], [lines' 810 1, lines' 820 1])]
       ]
    <> [ (Column cap 4 1, [para 0 p, FTable 160 0 [line 905] rows [] False, para 20 1])
       | cap <- [30, 40],
         p <- [1, 2],
         rows <- [[lines' 810 1, lines' 820 2], [lines' 810 2, lines' 820 1]]
       ]

-- Boxes of one paragraph or one stanza, with a padding and with the
-- lengths of the flow, after paragraphs and before what follows, and kept
-- with the paragraph before them.
boxInputs :: [(Column, [FlowAt Sp])]
boxInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [box] <> after <> [para 20 n])
  | cap <- [30, 40, 60],
    cols <- [1, 2],
    p <- [0, 1, 3],
    box <- boxes,
    after <- [[], [FKeepNext span0 1, para 30 2]],
    n <- [1, 2]
  ]
    <> [ (Column cap 4 1, [para 50 1, para 0 3, ctl, box, para 20 1])
       | cap <- [40, 50],
         ctl <- [FKeepNext span0 1, FNoBreak span0],
         box <- boxes
       ]
  where
    boxes =
      [FBoxed i b a [FParagraph k ls] | i <- [170, 171], (b, a) <- [(5, 5), (0, 10)], k <- keeps, ls <- [lines' 400 m | m <- [1 .. 4]] <> [noted 400 2 1 2]]
        <> [FBoxed i b a [FStanza k [lines' (400 + 10 * j) m | (j, m) <- zip [0 ..] shape]] | i <- [170, 171], (b, a) <- [(5, 5), (0, 10)], k <- keeps, shape <- [[1], [1, 1], [2, 1], [1, 2, 1], [3, 1], [5]]]

-- Boxes of paragraphs, stanzas, spaces and keeps, and boxes of any other
-- body, nested boxes among them, after paragraphs and before what follows.
mixedBoxInputs :: [(Column, [FlowAt Sp])]
mixedBoxInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [FBoxed i 5 5 body] <> after <> [para 20 n])
  | cap <- [30, 40, 60],
    cols <- [1, 2],
    p <- [0, 1, 3],
    i <- [170, 171],
    body <- bodies,
    after <- [[], [FKeepNext span0 1, para 30 2]],
    n <- [1, 2]
  ]
  where
    bodies =
      [[FParagraph k (lines' 400 m), FSpace s, FParagraph k2 (lines' 410 m2)] | k <- [defaultKeep, Keep 2 2 True], k2 <- [Keep 1 1 False, Keep 3 2 False], m <- [1, 3], s <- [0, 5], m2 <- [1, 2]]
        <> [[FParagraph k (lines' 400 m), FKeepNext span0 w, FParagraph defaultKeep (lines' 410 2)] | k <- keeps, m <- [1 .. 3], w <- [1, 2]]
        <> [[FStanza k [lines' 400 1, lines' 410 2], FSpace 5, FParagraph defaultKeep (lines' 420 2)] | k <- keeps]
        <> [[FParagraph defaultKeep (noted 400 2 1 2), FSpace 5, FParagraph (Keep 2 2 True) (lines' 410 3)], [FSpace 5], [], [FParagraph defaultKeep [], FSpace 5, FParagraph (Keep 1 1 False) (lines' 400 2)]]
        <> [ [FParagraph (Keep 1 1 True) (lines' 400 3), FSpace 5, FParagraph defaultKeep (lines' 410 2)],
             [FParagraph (Keep 2 2 True) (lines' 400 5), FParagraph (Keep 1 1 False) (lines' 410 2)],
             [FStanza defaultKeep [lines' 400 6, lines' 410 1], FSpace 5, FParagraph defaultKeep (lines' 420 2)],
             [FStanza (Keep 1 1 True) [lines' 400 2, lines' 410 2, lines' 420 2], FSpace 5, FStanza defaultKeep [lines' 430 1]],
             [FParagraph defaultKeep (lines' 400 2), FSpace 5, FStanza (Keep 2 2 True) [lines' 410 1, lines' 420 5]],
             [FStanza (Keep 2 2 True) [lines' 400 5], FSpace 5, FParagraph defaultKeep (lines' 410 1)],
             [FStanza defaultKeep [lines' 400 7], FSpace 5, FParagraph defaultKeep (lines' 410 1)]
           ]

genericBoxInputs :: [(Column, [FlowAt Sp])]
genericBoxInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [FBoxed i 5 5 body] <> after <> [para 20 n])
  | cap <- [30, 40, 60],
    cols <- [1, 2],
    p <- [0, 1, 3],
    i <- [170, 171],
    body <- bodies,
    after <- [[], [FKeepNext span0 1, para 30 2]],
    n <- [1, 2]
  ]
  where
    bodies =
      [ [para 400 2, FFigure 100 15 [] []],
        [FHeading 1 False 10 [line 400], para 410 2],
        [para 400 1, FCode (CodeGeometry 10 10 10 10 0) 0 1 False (lines' 410 3)],
        [FDefTerm (lines' 400 1), para 410 2],
        [ruled 100 (Just (sides !! 0)) Nothing False defaultKeep (lines' 400 2)],
        [FBoxed 172 5 5 [para 400 2], para 410 1],
        [FBoxed 172 0 10 [FBoxed 173 5 5 [para 400 1, FSpace 5, para 410 2]]],
        [FContinued defaultKeep (lines' 400 3)],
        [FTable 160 0 [line 400] [lines' 410 1, lines' 420 1] [] False],
        [para 400 2, FBreak BreakColumn, para 410 1],
        [FWrapped 150 25 [] [] (lines' 700 3)],
        [FStanza defaultKeep [lines' 400 1], FFigure 100 15 [] []],
        [FParagraph defaultKeep (noted 400 2 1 2), FFigure 100 15 [] []],
        [FNeedLines span0 2, para 400 2]
      ]

-- Book parts of each unit after paragraphs that fill part of a page, with
-- the ids of all their slots or of their first slot, and tables in book
-- parts with the ids golem-typeset gives them.
bookPartInputs :: [(Column, [FlowAt Sp])]
bookPartInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [FBookPart unit span0 (Data.Text.pack "part") (pick body) body] <> after <> [para 20 n])
  | cap <- [30, 40],
    cols <- [1, 2],
    p <- [0, 2, 5, 9],
    unit <- [KeepColumn, KeepPage, KeepSpread],
    (body, pick) <- bodies,
    after <- [[], [FKeepNext span0 1, para 30 2]],
    n <- [1, 3]
  ]
  where
    allIds = concatMap flowSlotIds
    firstId = take 1 . concatMap flowSlotIds
    bodies =
      [ ([para 400 2], allIds),
        ([para 400 4], allIds),
        ([para 400 4], firstId),
        ([FDefTerm (lines' 400 1), para 410 3], \b -> 400 : take 1 (concatMap flowSlotIds (drop 1 b))),
        ([para 400 2, FFigure 100 25 [] []], allIds),
        ([FHeading 1 False 10 [line 400], para 410 2], allIds),
        ([FBookPart KeepPage span0 (Data.Text.pack "part") [410, 411, 412] [para 410 3], para 420 1], allIds),
        ([FBoxed 172 5 5 [para 400 2], para 410 1], allIds),
        ([FTable 160 0 [line 400] [lines' 410 2, lines' 420 1] [line 430] True], \_ -> [400, 410, 411]),
        ([FParagraph defaultKeep (noted 400 2 1 2), para 410 1], allIds)
      ]

tableAcrossInputs :: [(Column, [FlowAt Sp])]
tableAcrossInputs =
  [ (Column cap 4 cols, [para 0 p | p > 0] <> [FBookPart unit span0 (Data.Text.pack "table") ids [FTable 160 b header rows caption below]] <> [para 20 1])
  | cap <- [30, 40],
    cols <- [1, 2],
    p <- [0, 2, 5],
    unit <- [KeepPage, KeepSpread],
    b <- [0, 5],
    header <- [[], [line 800], lines' 800 2],
    rows <- [[lines' 810 1], [lines' 810 1, lines' 820 2], [lines' 810 2, lines' 820 1, lines' 830 2], [noted 810 1 0 2, lines' 820 1]],
    caption <- [[], [line 850]],
    below <- [False, True],
    let ids = map lbId ((if below then [] else caption) <> header <> concat (take 1 rows))
  ]

flowToken :: FlowAt Sp -> String
flowToken = \case
  FParagraph k ls -> "p:" <> keepToken k <> ":" <> linesToken ls
  FContinued k ls -> "c:" <> keepToken k <> ":" <> linesToken ls
  FFigure i e _ _ -> "f:" <> show i <> ":" <> show (unSp e)
  FTable i b h rs c below -> "g:" <> show i <> ":" <> show (unSp b) <> ":" <> linesToken h <> ":" <> intercalate "/" (map linesToken rs) <> ":" <> linesToken c <> ":" <> bit below
  FBoxed i b a [FParagraph k ls] -> "X:" <> show i <> ":" <> show (unSp b) <> ":" <> show (unSp a) <> ":" <> keepToken k <> ":" <> linesToken ls
  FBoxed i b a [FStanza k vs] -> "Y:" <> show i <> ":" <> show (unSp b) <> ":" <> show (unSp a) <> ":" <> keepToken k <> ":" <> intercalate "/" (map linesToken vs)
  FBookPart unit _ _ ids body -> unwords (("P:" <> unitToken unit <> ":" <> (if null ids then "-" else intercalate "," (map show ids)) <> ":" <> show (length body)) : map flowToken body)
  FBoxed i b a body -> unwords (("O:" <> show i <> ":" <> show (unSp b) <> ":" <> show (unSp a) <> ":" <> show (length body)) : map flowToken body)
  FWrapped i e _ _ ls -> "w:" <> show i <> ":" <> show (unSp e) <> ":" <> linesToken ls
  FPageFigure i _ _ -> "t:" <> show i
  FSpace n -> "s:" <> show (unSp n)
  FBlank _ n -> "b:" <> show n
  FBreak k -> "k:" <> breakToken k
  FNeedLines _ n -> "n:" <> show n
  FAdjustLines _ n -> "a:" <> show n
  FNoBreak _ -> "B"
  FNoBreakLines _ n -> "L:" <> show n
  FKeepNext _ n -> "K:" <> show n
  FRuled i b a j _ o (RuledLines k ls) ->
    "r:" <> show i <> ":" <> sideToken b <> ":" <> sideToken a <> ":" <> bit j <> ":" <> show (unSp o) <> ":" <> keepToken k <> ":" <> linesToken ls
  FRuled i b a j _ o (RuledHeading recto e ls) ->
    "q:" <> show i <> ":" <> sideToken b <> ":" <> sideToken a <> ":" <> bit j <> ":" <> show (unSp o) <> ":" <> bit recto <> ":" <> show (unSp e) <> ":" <> linesToken ls
  FHeading _ recto e ls -> "h:" <> bit recto <> ":" <> show (unSp e) <> ":" <> linesToken ls
  FDefTerm ls -> "d:" <> linesToken ls
  FCode g c f k ls -> "x:" <> show (unSp c) <> ":" <> show f <> ":" <> bit k <> ":" <> intercalate "," [show (codeSpan g n) | n <- [0 .. length ls + 1]] <> ":" <> linesToken ls
  FStanza k vs -> "v:" <> keepToken k <> ":" <> intercalate "/" (map linesToken vs)
  FSection _ k -> "S:" <> breakToken k
  FSwitchColumns (ColumnSet c _ _ _) -> "W:" <> show c
  FRestoreColumns -> "R"
  where
    breakToken = \case
      BreakColumn -> "c"
      BreakPage -> "p"
      BreakRecto -> "r"
      BreakVerso -> "v"
    bit b = if b then "1" else "0"
    unitToken = \case
      KeepColumn -> "c"
      KeepPage -> "p"
      KeepSpread -> "s"
    keepToken (Keep f l a) = show f <> "," <> show l <> "," <> bit a
    linesToken ls = intercalate "," (map lineToken ls)
    lineToken l = show (lbId l) <> concat ["^" <> show i <> "." <> show n | NoteBody (NoteId _ i) n <- lbNotes l]
    sideToken Nothing = "-"
    sideToken (Just (RuleSide i o w s out)) = intercalate "," [show (unSp i), show (unSp o), show (unSp w), bit s, maybe "-" (show . unSp) out]

slotToken :: (Sp, Slotted) -> String
slotToken (at, s) = show (unSp at) <> ":" <> case s of
  SLine i -> "L" <> show i
  SFigure i -> "F" <> show i
  SPageFigure i -> "T" <> show i
  SHeading i n -> "H" <> show i <> "." <> show n
  SCode i n g -> "C" <> show i <> "." <> show n <> "." <> show g
  SWrapped i -> "W" <> show i

unmetToken :: Unmet -> String
unmetToken = \case
  UnmetNeedLines _ n -> "!need" <> show n
  UnmetNoBreak _ -> "!nobreak"
  UnmetKeepNext _ -> "!keepnext"
  UnmetAdjust _ n why -> "!adjust" <> show n <> ":" <> case why of
    AdjustNoRoom -> "room"
    AdjustLinesPlaced -> "placed"
    AdjustOneLine -> "one"
  DroppedBlank _ -> "!dropped"
  SplitKept i -> "!split" <> show i
  ShortPart FirstPart i w g -> "!first" <> show i <> ":" <> show w <> ":" <> show g
  ShortPart LastPart i w g -> "!last" <> show i <> ":" <> show w <> ":" <> show g
  TallHeadingExtent i e r -> "!tall" <> show i <> ":" <> show (unSp e) <> ":" <> show (unSp r)
  SplitBookPart _ kind unit -> "!splitpart:" <> (if kind == Data.Text.pack "表の末尾とキャプション" then "table" else "part") <> ":" <> case unit of
    KeepColumn -> "c"
    KeepPage -> "p"
    KeepSpread -> "s"
  other -> "!" <> show other

pageToken :: PageOutAt Sp -> String
pageToken p =
  unwords
    ( ["out", show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-", show (unSp (poLines p))]
        <> map slotToken (poSlots p)
        <> ["n" <> show i <> ":" <> show f <> ":" <> show n | (NoteId _ i, f, n) <- poFootnotes p]
        <> map unmetToken (poUnmet p)
    )

-- A paragraph part on trial beside a wrapped figure: the flows before it
-- placed, the figure begun, then trialParagraphPartLimit with the region of
-- the figure, a prefix limit, a keep and whether the part starts the
-- paragraph. A part moved on is tried once more in the next column.
wrapTrialInputs :: [(Column, [FlowAt Sp], Int, Maybe Int, Keep, Bool, [LineBox])]
wrapTrialInputs =
  [ (Column cap 4 cols, pre, e, lim, k, s, rows)
  | cap <- [30, 40, 60],
    cols <- [1, 2],
    pre <- [[], [para 0 1], [para 0 3]],
    e <- [15, 25, 35],
    lim <- [Nothing, Just 1, Just 2],
    k <- keeps,
    s <- [True, False],
    rows <- [lines' 700 m | m <- [1 .. 4]] <> [noted 700 3 1 2, noted 700 3 0 1, noted 700 2 0 3, lines' 900 2]
  ]

-- | The bytes an input may allocate before it is printed as a loop: 100 MB,
-- over 400 times the most that an input which ends allocates (about 240 KB
-- under runghc), and reached by the looping inputs within a second.
loopAllocation :: Int64
loopAllocation = 100000000

-- | The wall-clock guard against a loop that does not allocate: 120 s.
hangGuard :: Int
hangGuard = 120000000

main :: IO ()
main = mapM_ runWrap wrapTrialInputs >> mapM_ run (paragraphInputs <> figureInputs <> controlInputs <> noteInputs <> ruledInputs <> chainInputs <> startInputs <> headingInputs <> turnedInputs <> stanzaInputs <> codeInputs <> ruledHeadingInputs <> ruledHeadingRuleInputs <> wrappedInputs <> tableInputs <> boxInputs <> mixedBoxInputs <> genericBoxInputs <> bookPartInputs <> tableAcrossInputs <> failureInputs)
  where
    run (column@(Column cap sep cols), flows) = do
      putStrLn (unwords (["in", show cap, show sep, show cols] <> map flowToken flows))
      let out = case paginatePhysical (settingsOf column) flows of
            Left failure -> ["out fail " <> failureToken failure]
            Right pages -> map pageToken pages
      -- an input on which paginatePhysical allocates more than
      -- loopAllocation bytes is printed as a loop, which Physical.lean
      -- gives as noProgress; the count of allocated bytes does not depend
      -- on the load of the machine, as a wall-clock timeout would.  An
      -- input that runs hangGuard microseconds without reaching the limit
      -- is printed as a hang, which Physical.lean never prints.
      setAllocationCounter loopAllocation
      enableAllocationLimit
      done <- timeout hangGuard (try (evaluate (length (concat out))))
      disableAllocationLimit
      mapM_ putStrLn $ case done of
        Nothing -> ["out fail hang"]
        Just (Left AllocationLimitExceeded) -> ["out fail loop"]
        Just (Right _) -> out
    runWrap (column@(Column cap sep cols), pre, e, lim, k, s, rows) = do
      putStrLn (unwords (["tw", show cap, show sep, show cols, show e, maybe "-" show lim, flowToken (FParagraph k rows), if s then "1" else "0"] <> map flowToken pre))
      let cfg = settingsOf column
          keepOf (Keep f l a) = show f <> "," <> show l <> "," <> (if a then "1" else "0")
          shown again = \case
            Left failure -> ["out fail " <> failureToken failure]
            Right (region, PhysicalMoved c kk) ->
              ("part moved " <> keepOf kk) : if again then shown False ((,) region <$> trialParagraphPartLimit cfg (Just region) lim kk s c rows) else map pageToken (finishPhysicalCursor cfg c)
            Right (_, PhysicalPlaced n c kk) -> ("part placed " <> show n <> " " <> keepOf kk) : map pageToken (finishPhysicalCursor cfg c)
          trial = do
            c1 <- stepPhysicalCursor cfg (startPhysicalCursor cfg) pre
            (c2, region) <- beginPhysicalWrap cfg c1 150 (Sp (fromIntegral e)) [] []
            (,) region <$> trialParagraphPartLimit cfg (Just region) lim k s c2 rows
      mapM_ putStrLn (shown True trial)
    failureToken = \case
      PhysicalLineTooTall i -> "line" <> show i
      PhysicalFootnoteTooTall (NoteId _ i) -> "note" <> show i
      PhysicalFigureTooTall i -> "figure" <> show i
      PhysicalHeadingTooTall i -> "heading" <> show i
      PhysicalCodeTooTall i -> "code" <> show i
      PhysicalTableTooTall i -> "table" <> show i
      PhysicalTableCaptionTooTall i -> "tablecaption" <> show i
      PhysicalBoxTooTall i -> "box" <> show i
