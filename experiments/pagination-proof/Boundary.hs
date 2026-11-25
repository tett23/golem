{-# LANGUAGE LambdaCase #-}

-- Root ADR 0352: prints the pages golem-layout's paginate gives for the
-- inputs of boundaryTableTests (modules/golem-layout/test/PaginateSpec.hs),
-- in the format Boundary.lean prints for Whole.lean's paginate.
-- check.sh compares the two outputs with diff.
module Main (main) where

import Control.Applicative ((<|>))
import Control.Monad (guard, replicateM)
import Data.List (intercalate)
import Golem.Layout.Code (CodeGeometry (..))
import Golem.Layout.Look (NoteId (..))
import Golem.Layout.Paginate
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Length (Sp (..))
import Golem.Syntax (FileId (..), mkSpan)

lines' :: Int -> Int -> [LineBox]
lines' base n = [LineBox (base + i) [] [] [] 0 | i <- [0 .. n - 1]]

-- A paragraph, a figure, a heading of one line over one grid line, a
-- need-lines, a no-break, a no-break of so many lines and a keep-with-next;
-- a box, a space, a table, a code block, a ruled block, a stanza, a
-- wrapped figure and a paragraph with a footnote; a page-lines, a switch of
-- the columns and a wrapped figure whose side lines have a footnote.
data Element
  = Para Int Int
  | Fig Int Int
  | Head Int
  | NeedLines Int
  | NoBreak
  | NoBreakLines Int
  | KeepNext Int
  | -- | id, grid lines before and after, body
    Boxed Int Int Int [Element]
  | Space Int
  | -- | first line, space before, header lines, lines of each row, caption lines, caption below
    Table Int Int Int [Int] Int Bool
  | -- | geometry (0 or 1), caption, first rows, continued, first row, rows
    Code Int Int Int Bool Int Int
  | -- | id, rule before, rule after, joined, body (lines, or a heading over so many grid lines), first line
    Ruled Int Bool Bool Bool (Either Int Int) Int
  | -- | keep all, first line, lines of each verse line
    Stanza Bool Int [Int]
  | -- | id, grid lines, first line beside, lines beside
    Wrapped Int Int Int Int
  | -- | first line, lines, the line with the note, lines of the note
    Noted Int Int Int Int
  | -- | the grid lines @page-lines changes the column by
    Adjust Int
  | -- | the columns switched to
    Switch Int
  | -- | id, grid lines, first line beside, lines beside, the line with the note, lines of the note
    WrappedNoted Int Int Int Int Int Int

flowOf :: Element -> Flow
flowOf = \case
  Para base n -> FParagraph defaultKeep (lines' base n)
  Fig ident n -> FFigure ident n [] []
  Head base -> FHeading 2 False 1 (lines' base 1)
  NeedLines n -> FNeedLines control n
  NoBreak -> FNoBreak control
  NoBreakLines n -> FNoBreakLines control n
  KeepNext n -> FKeepNext control n
  Boxed i b a body -> FBoxed i b a (map flowOf body)
  Space n -> FSpace n
  Table base sp h rows c below ->
    let rowLines = zipWith lines' (scanl (+) (base + h) rows) rows
     in FTable base sp (lines' base h) rowLines (lines' (base + h + sum rows) c) below
  Code g c f cont base n -> FCode (geometry g) c f cont (lines' base n)
  Ruled i b a j body base ->
    FRuled i (sideOf i <$ guard b) (sideOf i <$ guard a) j ruleGrid 0 $ case body of
      Left n -> RuledLines defaultKeep (lines' base n)
      Right n -> RuledHeading False n (lines' base 1)
  Stanza kAll base vs -> FStanza (Keep 2 2 kAll) (zipWith lines' (scanl (+) base vs) vs)
  Wrapped i n base b -> FWrapped i n [] [] (lines' base b)
  Noted base n at m -> FParagraph defaultKeep (noted base n at m)
  Adjust k -> FAdjustLines control k
  Switch n -> FSwitchColumns (ColumnSet n 0 0 0)
  WrappedNoted i n base b at m -> FWrapped i n [] [] (noted base b at m)
  where
    noted base n at m = [if j == at then l {lbNotes = [NoteBody (NoteId control (500 + base)) m]} else l | (j, l) <- zip [0 ..] (lines' base n)]
    control = mkSpan (FileId 1) 0 1

-- | The code geometries: rows of one grid line each, with no padding (0)
-- or with half a line of padding above and below (1).
geometry :: Int -> CodeGeometry
geometry g = CodeGeometry 10 10 10 10 (if g == 0 then 0 else 5)

-- | The rule grid and side of every ruled block: an area of 1 grid line
-- inside a column, of 2 at its start or its end, and of 3 joined.
ruleGrid :: RuleGrid
ruleGrid = RuleGrid 10 8

side :: RuleSide
side = RuleSide 0 0 12 False Nothing

-- | The rules of the blocks of id 200 or more may go out of the column by
-- 20 sp (keep-in-column = false): no line at the start of the page's first
-- column or at the end of a column without notes.
sideOf :: Int -> RuleSide
sideOf i = if i >= 200 then side {rsdOutside = Just 20} else side

showElement :: Element -> String
showElement = \case
  Para base n -> "P" <> show base <> ":" <> show n
  Fig ident n -> "F" <> show ident <> ":" <> show n
  Head base -> "H" <> show base
  NeedLines n -> "N" <> show n
  NoBreak -> "B"
  NoBreakLines n -> "B" <> show n
  KeepNext n -> "K" <> show n
  Boxed i b a body -> "X" <> show i <> ":" <> show b <> ":" <> show a <> "(" <> intercalate " " (map showElement body) <> ")"
  Space n -> "_" <> show n
  Table base sp h rows c below -> "T" <> show base <> ":" <> show sp <> ":" <> show h <> ":" <> intercalate "," (map show rows) <> ":" <> show c <> (if below then "b" else "a")
  Code g c f cont base n -> "C" <> show base <> ":" <> show g <> ":" <> show c <> ":" <> show f <> ":" <> bit cont <> ":" <> show n
  Ruled i b a j body base -> "R" <> show i <> ":" <> bit b <> bit a <> bit j <> ":" <> either (("L" <>) . show) (("H" <>) . show) body <> ":" <> show base
  Stanza kAll base vs -> "V" <> show base <> ":" <> bit kAll <> ":" <> intercalate "," (map show vs)
  Wrapped i n base b -> "W" <> show i <> ":" <> show n <> ":" <> show base <> ":" <> show b
  Noted base n at m -> "Q" <> show base <> ":" <> show n <> ":" <> show at <> ":" <> show m
  Adjust k -> "A" <> show k
  Switch n -> "S" <> show n
  WrappedNoted i n base b at m -> "Y" <> show i <> ":" <> show n <> ":" <> show base <> ":" <> show b <> ":" <> show at <> ":" <> show m
  where
    bit b = if b then "1" else "0"

-- The inputs in the order Boundary.lean lists them.
inputs :: [(Int, [Element])]
inputs =
  [(c, e) | c <- [1 .. 3], e <- [[], [Para 0 1]]]
    <> [(c, paragraphs s) | c <- [1 .. 3], s <- [[a] | a <- [1 .. 5]] <> [[a, b] | a <- [1 .. 4], b <- [1 .. 4]]]
    <> [(3, [Fig 1 3]), (3, [Para 0 1, Fig 1 3]), (3, [Fig 1 4]), (3, [Para 0 1, Fig 1 4, Para 10 1])]
    <> [(c, figureInput s) | c <- [3, 4], s <- figureShapes c]
    <> [(c, controlInput s n) | c <- [2 .. 4], s <- controlShapes, n <- [1 .. 3]]
  where
    paragraphs = zipWith (\k n -> Para (10 * k) n) [0 ..]
    figureShapes c =
      [ shape
      | count <- [1 .. 4],
        shape <- replicateM count (Left <$> [1 .. 3] <|> Right <$> [1 .. c]),
        length [() | Right _ <- shape] `elem` [1 .. 3]
      ]
    figureInput = zipWith (\k -> either (Para (10 * k)) (Fig (100 + k))) [0 ..]
    -- one to three elements, each a paragraph of one to five lines, a
    -- heading, a need-lines of two or three lines, a no-break, a no-break
    -- of three lines or a keep-with-next of one or two lines, before a
    -- last paragraph of one to three lines
    controlShapes = [shape | count <- [1 .. 3], shape <- replicateM count controlChoices]
    controlChoices = map Left [1 .. 5] <> map Right [Nothing, Just (Left 2), Just (Left 3), Just (Right Nothing), Just (Left 0), Just (Right (Just 1)), Just (Right (Just 2))]
    controlInput shape n = zipWith controlElement [0 ..] shape <> [Para (10 * length shape) n]
    controlElement k = \case
      Left n -> Para (10 * k) n
      Right Nothing -> Head (10 * k)
      Right (Just (Left 0)) -> NoBreakLines 3
      Right (Just (Left n)) -> NeedLines n
      Right (Just (Right Nothing)) -> NoBreak
      Right (Just (Right (Just n))) -> KeepNext n

-- The inputs of the other kinds of flows, in the order Boundary.lean lists
-- them: one kind between a paragraph of none to two lines and a last
-- paragraph of one to three lines, in columns of 2 to 5 lines; and two
-- of a few of each kind and of the controls, before a last paragraph of
-- one or two lines, in columns of 2 to 4 lines; and each kind before or
-- after a heading, a keep-with-next, a no-break or a need-lines, after a
-- paragraph of one or two lines and before a last paragraph of one or
-- three lines, in columns of 3 to 5 lines.
kindInputs :: [(Int, [Element])]
kindInputs =
  [ (c, [Para 0 p | p > 0] <> [kind 1] <> [Para 20 n])
  | c <- [2 .. 5],
    p <- [0 .. 2],
    kind <- kindChoices,
    n <- [1 .. 3]
  ]
    <> [ (c, [a 0, b 1, Para 20 n])
       | c <- [2 .. 4],
         a <- pairChoices,
         b <- pairChoices,
         n <- [1, 2]
       ]
    <> [ (c, [Para 0 p] <> (if kindFirst then [kind 1, control 2] else [control 1, kind 2]) <> [Para 30 n])
       | c <- [3 .. 5],
         p <- [1, 2],
         control <- [Head . (10 *), const (KeepNext 1), const NoBreak, const (NeedLines 3)],
         kind <- kindChoices,
         kindFirst <- [True, False],
         n <- [1, 3]
       ]

-- root ADR 0444: a note going on takes the room @page-lines adds first;
-- root ADR 0441: the columns of a set started after @page-lines end at the
-- type area or above the notes of the column before; root ADR 0443: a
-- wrapped figure fits with the notes of its side lines.
adjustInputs :: [(Int, [Element])]
adjustInputs =
  [ (c, [Noted 0 1 0 m, Adjust a] <> more <> [Para 20 n])
  | c <- [3 .. 5],
    m <- [2 .. 6],
    a <- [-1, 1, 2, 3, 4],
    more <- [[], [Noted 10 1 0 1], [WrappedNoted 100 2 10 2 0 1], [Switch 2, Para 10 3]],
    n <- [1, 3]
  ]
    <> [ (c, [if m == 0 then Para 0 p else Noted 0 p 0 m, Adjust a, Switch s, Para 10 q, Para 20 1])
       | c <- [3 .. 5],
         p <- [1, 2],
         m <- [0 .. 2],
         a <- [-2, -1, 1, 2],
         s <- [2, 3],
         q <- [1 .. 6]
       ]
    <> [ (c, [Para 0 p | p > 0] <> [WrappedNoted 100 n 10 b at m, Para 20 k])
       | c <- [2 .. 5],
         p <- [0 .. 2],
         n <- [1 .. 3],
         b <- [1 .. 3],
         at <- [0 .. b - 1],
         m <- [1 .. 3],
         k <- [1 .. 3]
       ]
    <> [ (c, [Para 0 p, control, WrappedNoted 100 n 10 b 0 m, Para 20 1])
       | c <- [3 .. 5],
         p <- [1, 2],
         control <- [Head 40, KeepNext 1, NoBreak, NeedLines 3],
         n <- [1, 2],
         b <- [1, 2],
         m <- [1 .. 3]
       ]

-- Boxes whose last part has no text line, after a note continued over
-- them (root ADR 0444): the room the box gives back goes to that note.
boxInputs :: [(Int, [Element])]
boxInputs =
  [ (c, [Boxed 100 b a [Noted 0 1 0 m, end], Noted 20 1 0 1, Para 30 n])
  | c <- [3 .. 5],
    b <- [0, 1],
    a <- [1 .. 3],
    m <- [1 .. 4],
    end <- [Code g 0 1 False 10 k | g <- [0, 1], k <- [1, 2]] <> [Wrapped 101 w 10 0 | w <- [1, 2]],
    n <- [1, 2]
  ]

-- Two ruled blocks whose rules may share an area, the first ending at or
-- near the end of a column, between paragraphs: the places of the rules
-- (poRules); the same with rules that may go out of the column, after a
-- paragraph with a note or not; and a ruled block before a switch of the
-- columns; and a ruled heading whose rule after may share an area with a
-- ruled paragraph or heading after it (root ADR 0449).
ruleInputs :: [(Int, [Element])]
ruleInputs =
  [ (c, [Para 0 p | p > 0] <> [Ruled 100 b1 True False (Left n) 10, Ruled 101 True a2 True second 20, Para 30 k])
  | c <- [2 .. 6],
    p <- [0 .. 2],
    b1 <- [False, True],
    n <- [1 .. 3],
    a2 <- [False, True],
    second <- [Left 1, Left 2, Right 1],
    k <- [1, 2]
  ]
    <> [ (c, lead <> [Ruled 200 b1 True False (Left n) 10, second, Para 30 k])
       | c <- [2 .. 6],
         lead <- [[], [Para 0 1], [Noted 0 1 0 1]],
         b1 <- [False, True],
         n <- [1 .. 3],
         second <- [Ruled 201 True a2 True s 20 | a2 <- [False, True], s <- [Left 1, Left 2, Right 1]] <> [Para 20 1],
         k <- [1, 2]
       ]
    <> [ (c, [Para 0 p | p > 0] <> [Ruled r True True False (Left n) 10, Switch cs, Ruled (r + 1) True True True (Left 1) 20, Para 30 2])
       | c <- [3 .. 6],
         p <- [0, 1],
         r <- [100, 200],
         n <- [1, 2],
         cs <- [1, 2]
       ]
    <> [ (c, [Para 0 p | p > 0] <> [Ruled 300 b1 True False (Right h) 10, Ruled 301 True a2 True second 20, Para 30 1])
       | c <- [2 .. 6],
         p <- [0 .. 2],
         b1 <- [False, True],
         h <- [1, 2],
         a2 <- [False, True],
         second <- [Left 1, Left 2, Right 1, Right 2]
       ]

kindChoices :: [Int -> Element]
kindChoices =
  [\k -> Boxed (100 + k) b a [Para (10 * k) n] | (b, a) <- [(0, 0), (1, 1), (1, 0)], n <- [1 .. 4]]
    <> [\k -> Boxed (100 + k) 1 1 [Para (10 * k) 1, Space 1, Para (10 * k + 5) 2]]
    <> [ \k -> Table (10 * k) sp h rows c below
       | sp <- [0, 1],
         h <- [0, 1],
         rows <- [[1], [1, 1], [1, 1, 1], [2, 1]],
         (c, below) <- [(0, False), (1, False), (1, True)]
       ]
    <> [\k -> Code g c f cont (10 * k) n | g <- [0, 1], c <- [0, 1], f <- [1, 2], cont <- [False, True], n <- [1 .. 4]]
    <> [\k -> Ruled (100 + k) b a False body (10 * k) | b <- [False, True], a <- [False, True], body <- [Left 1, Left 2, Left 3, Right 1, Right 2]]
    <> [\k -> Stanza kAll (10 * k) vs | kAll <- [False, True], vs <- [[1], [1, 1], [1, 1, 1], [2, 1], [1, 2, 1], [1, 1, 1, 1]]]
    <> [\k -> Wrapped (100 + k) n (10 * k) b | n <- [1 .. 3], b <- [0 .. 3]]
    <> [\k -> Noted (10 * k) n at m | n <- [1 .. 3], at <- [0 .. n - 1], m <- [1 .. 3]]

pairChoices :: [Int -> Element]
pairChoices =
  [ \k -> Boxed (100 + k) 1 1 [Para (10 * k) 2],
    \k -> Boxed (100 + k) 1 0 [Para (10 * k) 3],
    \k -> Table (10 * k) 1 1 [1, 1] 1 True,
    \k -> Table (10 * k) 0 0 [2, 1] 1 False,
    \k -> Code 1 1 2 True (10 * k) 3,
    \k -> Code 0 0 1 False (10 * k) 2,
    \k -> Ruled (100 + k) True True False (Left 2) (10 * k),
    \k -> Ruled (100 + k) True True True (Left 1) (10 * k),
    \k -> Ruled (100 + k) True False True (Right 1) (10 * k),
    \k -> Ruled (100 + k) False True False (Left 2) (10 * k),
    \k -> Stanza False (10 * k) [1, 1, 1],
    \k -> Stanza True (10 * k) [2, 1],
    \k -> Wrapped (100 + k) 2 (10 * k) 3,
    \k -> Wrapped (100 + k) 3 (10 * k) 1,
    \k -> Noted (10 * k) 2 1 2,
    \k -> Noted (10 * k) 1 0 3,
    const (KeepNext 1),
    const (KeepNext 2),
    const NoBreak,
    const (NoBreakLines 3),
    const (NeedLines 2),
    \k -> Para (10 * k) 2
  ]

slot :: (Int, Slotted) -> String
slot (g, s) = show g <> ":" <> case s of
  SLine i -> "L" <> show i
  SFigure i -> "F" <> show i
  SHeading i n -> "H" <> show i <> ":" <> show n
  SWrapped i -> "W" <> show i
  SCode i k _ -> "C" <> show i <> ":" <> show k
  other -> show other

unmet :: Unmet -> String
unmet = \case
  UnmetNeedLines _ n -> "!need" <> show n
  UnmetNoBreak _ -> "!nobreak"
  UnmetKeepNext _ -> "!keepnext"
  DroppedBlank _ -> "!dropped"
  TallHeading i n f -> "!tall" <> show i <> ":" <> show n <> ":" <> show f
  SplitKept i -> "!split" <> show i
  ShortPart FirstPart i w g -> "!first" <> show i <> ":" <> show w <> ":" <> show g
  ShortPart LastPart i w g -> "!last" <> show i <> ":" <> show w <> ":" <> show g
  UnplaceableFootnote (NoteId _ i) n -> "!unplaceable" <> show i <> ":" <> show n
  UnmetAdjust _ n limit -> "!adjust" <> show n <> ":" <> show limit
  other -> "!" <> show other

page :: PageOut -> String
page p = "  " <> unwords ([show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-"] <> map slot (poSlots p) <> map note (poFootnotes p) <> map rule (poRules p) <> map unmet (poUnmet p))
  where
    note (NoteId _ i, first, n) = "n" <> show i <> ":" <> show first <> ":" <> show n
    rule r = "r" <> show (prId r) <> (if prBefore r then "b" else "a") <> ":" <> show (unSp (prAt r))

main :: IO ()
main = mapM_ run (inputs <> kindInputs <> adjustInputs <> boxInputs <> ruleInputs)
  where
    run (c, es) = do
      putStrLn (show c <> " [" <> intercalate " " (map showElement es) <> "]")
      mapM_ (putStrLn . page) (paginate 1 c (map flowOf es))
