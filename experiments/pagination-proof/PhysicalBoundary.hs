{-# LANGUAGE LambdaCase #-}

-- Root ADR 0352, the free placement of root ADR 0397: prints boundary
-- inputs of golem-layout's paginatePhysical as "in" lines, each followed
-- by the pages it gives as "out" lines.  PhysicalBoundary.lean reads the
-- "in" lines, evaluates Physical.lean's paginate and prints the same
-- "out" lines; check.sh compares the two with diff.
module Main (main) where

import Control.Monad (replicateM)
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Look (NoteId (..))
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Length (Sp (..))
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)

-- | The column: capacity, separator and columns; the pitch and the face
-- of the lines whose id is at least 900 are 14 and 12 sp.
data Column = Column Int Int Int

settingsOf :: Column -> PhysicalSettings
settingsOf (Column cap sep cols) =
  PhysicalSettings 10 10 (Sp (fromIntegral cap)) (Sp (fromIntegral cap + 20)) (Sp (fromIntegral sep)) (ColumnSet cols 0 0 0) tall faces Map.empty Map.empty Map.empty Nothing
  where
    tall = Map.fromList [(i, 14) | i <- [900 .. 999]]
    faces = Map.fromList [(i, 12) | i <- [900 .. 999]]

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

flowToken :: FlowAt Sp -> String
flowToken = \case
  FParagraph k ls -> "p:" <> keepToken k <> ":" <> linesToken ls
  FContinued k ls -> "c:" <> keepToken k <> ":" <> linesToken ls
  FFigure i e _ _ -> "f:" <> show i <> ":" <> show (unSp e)
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
  FHeading _ recto e ls -> "h:" <> bit recto <> ":" <> show (unSp e) <> ":" <> linesToken ls
  FDefTerm ls -> "d:" <> linesToken ls
  FStanza k vs -> "v:" <> keepToken k <> ":" <> intercalate "/" (map linesToken vs)
  FSection _ k -> "S:" <> breakToken k
  FSwitchColumns (ColumnSet c _ _ _) -> "W:" <> show c
  FRestoreColumns -> "R"
  other -> error ("no token for " <> show other)
  where
    breakToken = \case
      BreakColumn -> "c"
      BreakPage -> "p"
      BreakRecto -> "r"
      BreakVerso -> "v"
    bit b = if b then "1" else "0"
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
  other -> show other

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
  other -> "!" <> show other

pageToken :: PageOutAt Sp -> String
pageToken p =
  unwords
    ( ["out", show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-", show (unSp (poLines p))]
        <> map slotToken (poSlots p)
        <> ["n" <> show i <> ":" <> show f <> ":" <> show n | (NoteId _ i, f, n) <- poFootnotes p]
        <> map unmetToken (poUnmet p)
    )

main :: IO ()
main = mapM_ run (paragraphInputs <> figureInputs <> controlInputs <> noteInputs <> ruledInputs <> chainInputs <> startInputs <> headingInputs <> turnedInputs <> stanzaInputs <> failureInputs)
  where
    run (column@(Column cap sep cols), flows) = do
      putStrLn (unwords (["in", show cap, show sep, show cols] <> map flowToken flows))
      case paginatePhysical (settingsOf column) flows of
        Left failure -> putStrLn ("out fail " <> failureToken failure)
        Right pages -> mapM_ (putStrLn . pageToken) pages
    failureToken = \case
      PhysicalLineTooTall i -> "line" <> show i
      PhysicalFootnoteTooTall (NoteId _ i) -> "note" <> show i
      PhysicalFigureTooTall i -> "figure" <> show i
      PhysicalHeadingTooTall i -> "heading" <> show i
      other -> show other
