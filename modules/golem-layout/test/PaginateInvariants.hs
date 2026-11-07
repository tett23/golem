{- | The invariants of pagination (docs/adr/0204, its section 「不変条件」),
as predicates over the flow that goes in and the columns that come out,
read as docs/adr/0206 (its section 6) decides. They read nothing of the
paginator but its input and output, and every case is judged.

The columns are taken in the order of their page and their column. A
grid line, a heading or a figure is at a place: its column in that
order and its slot in the column.
-}
module PaginateInvariants
  ( Invariant (..),
    Breach (..),
    Check,
    i1PlacedOnce,
    i2NoOverflow,
    i3Order,
    i4NoOrphan,
    i5NoWidow,
    i6HeadingKept,
    i7NoteOnPage,
    i8Recto,
    invariants,
    breaches,
  )
where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Golem.Layout.Paginate

-- | The invariants of docs/adr/0204, by their numbers.
data Invariant = I1 | I2 | I3 | I4 | I5 | I6 | I7 | I8
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | An invariant broken: the lines or figures concerned, and how.
data Breach = Breach {breachOf :: !Invariant, breachAt :: ![Int], breachWhy :: !String}
  deriving stock (Eq, Show)

-- | A predicate over the flow and the columns.
type Check = [Flow] -> [PageOut] -> [Breach]

-- | Every invariant, with a footnote separator of the grid lines given.
invariants :: Int -> [(Invariant, Check)]
invariants separator =
  [ (I1, i1PlacedOnce),
    (I2, i2NoOverflow separator),
    (I3, i3Order),
    (I4, i4NoOrphan),
    (I5, i5NoWidow),
    (I6, i6HeadingKept),
    (I7, i7NoteOnPage),
    (I8, i8Recto)
  ]

-- | The breaches of every invariant, I1 first.
breaches :: Int -> Check
breaches separator flows ps = concatMap (\(_, c) -> c flows ps) (invariants separator)

-- the input

-- | The lines of a flow.
flowLines :: Flow -> [LineBox]
flowLines = \case
  FParagraph ls -> ls
  FContinued ls -> ls
  FDefTerm ls -> ls
  FHeading {fhLines = ls} -> ls
  _ -> []

-- | The ids of the lines in the order of the flow.
inputLines :: [Flow] -> [Int]
inputLines = map lbId . concatMap flowLines

-- | The figures and their grid lines, in the order of the flow.
inputFigures :: [Flow] -> [(Int, Int)]
inputFigures flows = [(i, n) | FFigure i n _ _ <- flows]

-- | The grid lines of each heading, by the id of its first line.
headingSpans :: [Flow] -> Map Int Int
headingSpans flows = Map.fromList [(lbId l, n) | FHeading {fhSpan = n, fhLines = l : _} <- flows]

-- the output

-- | The columns in the order of their page and their column.
ordered :: [PageOut] -> [PageOut]
ordered = sortOn (\p -> (poNumber p, poColumn p))

-- | A place: the column in order and the slot in the column.
type Place = (Int, Int)

-- | The lines a slot holds.
slotLines :: Slotted -> [Int]
slotLines = \case
  SLine i -> [i]
  SHeading l m -> [l .. l + m - 1]
  _ -> []

-- | The figure a slot holds.
slotFigure :: Slotted -> Maybe Int
slotFigure = \case
  SFigure i -> Just i
  _ -> Nothing

-- | Every slot with its place and its column.
slots :: [PageOut] -> [(Place, PageOut, Slotted)]
slots ps = [((c, k), p, s) | (c, p) <- zip [0 ..] (ordered ps), (k, (_, s)) <- zip [0 ..] (poSlots p)]

-- | The place of each line placed (the first, if placed more than once).
linePlaces :: [PageOut] -> Map Int (Place, PageOut)
linePlaces ps = Map.fromListWith (\_ old -> old) [(i, (pl, p)) | (pl, p, s) <- slots ps, i <- slotLines s]

-- | The place of each figure placed.
figurePlaces :: [PageOut] -> Map Int Place
figurePlaces ps = Map.fromListWith (\_ old -> old) [(i, pl) | (pl, _, s) <- slots ps, Just i <- [slotFigure s]]

-- | The column of a line, in order.
columnOf :: Map Int (Place, PageOut) -> Int -> Maybe Int
columnOf places i = fst . fst <$> Map.lookup i places

-- | The slots of the column before the slot k.
slotsBefore :: PageOut -> Int -> [Slotted]
slotsBefore p k = map snd (take k (poSlots p))

isHeadingSlot :: Slotted -> Bool
isHeadingSlot = \case
  SHeading {} -> True
  _ -> False

{- | I1: every line and every figure of the input is placed exactly once,
and a blank page holds nothing.
-}
i1PlacedOnce :: Check
i1PlacedOnce flows ps =
  let placedLines = Map.fromListWith (+) [(i, 1 :: Int) | (_, _, s) <- slots ps, i <- slotLines s]
      placedFigures = Map.fromListWith (+) [(i, 1 :: Int) | (_, _, s) <- slots ps, Just i <- [slotFigure s]]
      once what counts i = case Map.findWithDefault 0 i counts of
        1 -> []
        n -> [Breach I1 [i] (what <> " " <> show i <> " placed " <> show n <> " times")]
   in concatMap (once "line" placedLines) (inputLines flows)
        <> concatMap (once "figure" placedFigures . fst) (inputFigures flows)
        <> [ Breach I1 [] ("blank page " <> show (poNumber p) <> " holds something")
           | p <- ordered ps,
             poBlank p,
             not (null (poSlots p) && null (poFootnotes p))
           ]

{- | I2: the grid lines placed in a column, the lines of its notes and
the separator, if it has notes, do not exceed its grid lines.

Allowed: a column with a heading taller than an empty column (recorded
as 'TallHeading'), and a column whose first slot is the first line of a
paragraph whose note continues in a later column. A figure is never
taller than the column: golem-driver shrinks it to fit an empty one, and
the input of pagination has none (docs/adr/0206).
-}
i2NoOverflow :: Int -> Check
i2NoOverflow separator flows ps =
  let spans = headingSpans flows
      figures = Map.fromList (inputFigures flows)
      firstLines = [l | FParagraph (l : _) <- flows]
      extent = \case
        SHeading l _ -> Map.findWithDefault 1 l spans
        SFigure i -> Map.findWithDefault 1 i figures
        _ -> 1
      cols = ordered ps
      continuedLater c note = or [k > 0 | p <- drop (c + 1) cols, (n, k, _) <- poFootnotes p, n == note]
      noteContinues c p = case poSlots p of
        (_, SLine i) : _ -> or [continuedLater c (nbId nb) | l <- firstLines, lbId l == i, nb <- lbNotes l]
        _ -> False
      tall p = or [True | TallHeading {} <- poUnmet p]
      check (c, p) =
        let used = maximum (0 : [k + extent s | (k, s) <- poSlots p])
            notes = sum [n | (_, _, n) <- poFootnotes p]
            sep = if null (poFootnotes p) then 0 else separator
            total = used + notes + sep
         in [ Breach I2 (concatMap (slotLines . snd) (poSlots p)) ("page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " uses " <> show total <> " of " <> show (poLines p) <> " grid lines")
            | not (poBlank p),
              total > poLines p,
              not (tall p),
              not (noteContinues c p)
            ]
   in concatMap check (zip [0 ..] cols)

{- | I3: the lines come out in the order of the input, and so do the
figures; a figure may come out after the text that follows it in the
input, never before the text that precedes it.
-}
i3Order :: Check
i3Order flows ps =
  let index = Map.fromList (zip (inputLines flows) [0 :: Int ..])
      figIndex = Map.fromList (zip (map fst (inputFigures flows)) [0 :: Int ..])
      textOut = [i | (_, _, s) <- slots ps, i <- slotLines s]
      figsOut = [i | (_, _, s) <- slots ps, Just i <- [slotFigure s]]
      inversions ix what out =
        [ Breach I3 [a, b] (what <> " " <> show b <> " comes out after " <> show a)
        | (a, b) <- zip out (drop 1 out),
          Just x <- [Map.lookup a ix],
          Just y <- [Map.lookup b ix],
          y < x
        ]
      places = linePlaces ps
      figPlaces = figurePlaces ps
      -- the last line before each figure in the input
      before = go Nothing flows
        where
          go _ [] = []
          go lastLine (f : rest) = case f of
            FFigure i _ _ _ -> (i, lastLine) : go lastLine rest
            _ -> go (maybe lastLine (Just . lbId) (lastMaybe (flowLines f))) rest
      lastMaybe xs = if null xs then Nothing else Just (last xs)
      early =
        [ Breach I3 [l, i] ("figure " <> show i <> " comes out before line " <> show l)
        | (i, Just l) <- before,
          Just pf <- [Map.lookup i figPlaces],
          Just (pl, _) <- [Map.lookup l places],
          pl >= pf
        ]
   in inversions index "line" textOut <> inversions figIndex "figure" figsOut <> early

-- | The paragraphs of two lines or more.
paragraphs :: [Flow] -> [[Int]]
paragraphs flows = [map lbId ls | FParagraph ls <- flows, length ls >= 2]

{- | I4: the first line of a paragraph of two lines or more is not left
alone at the end of a column with the rest in a later column, unless
nothing is before it in its column (an empty column), or nothing but
headings placed from the top of the column: such a column places lines
as an empty one does (docs/adr/0206).
-}
i4NoOrphan :: Check
i4NoOrphan flows ps =
  let places = linePlaces ps
   in [ Breach I4 [l1, l2] ("line " <> show l1 <> " is alone at the end of page " <> show (poNumber p) <> " column " <> show (poColumn p))
      | l1 : l2 : _ <- paragraphs flows,
        Just ((c1, k), p) <- [Map.lookup l1 places],
        Just c2 <- [columnOf places l2],
        c2 /= c1,
        let before = slotsBefore p k,
        not (null before),
        not (all isHeadingSlot before)
      ]

{- | I5: the last line of a paragraph of two lines or more is not alone
in a column, unless the column before starts empty, or with nothing but
headings, and holds nothing else but lines of the paragraph: such a
column places lines as an empty one does (docs/adr/0206).
-}
i5NoWidow :: Check
i5NoWidow flows ps =
  let places = linePlaces ps
   in [ Breach I5 [lp, ln] ("line " <> show ln <> " is alone at the start of page " <> show (poNumber pn) <> " column " <> show (poColumn pn))
      | ls <- paragraphs flows,
        let ln = last ls
            lp = last (init ls),
        Just ((cn, _), pn) <- [Map.lookup ln places],
        Just ((cp, _), pp) <- [Map.lookup lp places],
        cn /= cp,
        let rest = dropWhile isHeadingSlot (map snd (poSlots pp))
            own = all (\s -> all (`elem` ls) (slotLines s) && not (null (slotLines s))) rest,
        not own
      ]

{- | I6: a heading is in the column of the headings that follow it, up
to a heading at a recto, and of the first part of the paragraph after
them (golem-layout ADR 0021: all of three lines or fewer, two of more),
unless it is the first slot of its column (nothing is sent on from an
empty column). A heading at a recto ends the run: the paragraph after
it is not counted (docs/adr/0206).
-}
i6HeadingKept :: Check
i6HeadingKept flows ps =
  let places = linePlaces ps
      isHeading = \case
        FHeading {fhRecto = False} -> True
        _ -> False
      firstPart ls = if length ls <= 3 then ls else take 2 ls
      kept rest =
        let run = takeWhile isHeading rest
            after = drop (length run) rest
            para = case after of
              FParagraph ls : _ -> map lbId (firstPart ls)
              _ -> []
         in mapMaybe (fmap lbId . firstLine) run <> para
      firstLine f = case flowLines f of
        l : _ -> Just l
        [] -> Nothing
      go [] = []
      go (f : rest) = case f of
        FHeading {fhLines = l : _}
          | let members = kept rest,
            Just ((c, k), p) <- Map.lookup (lbId l) places,
            k > 0,
            let away = [m | m <- members, Just cm <- [columnOf places m], cm /= c],
            not (null away) ->
              Breach I6 (lbId l : away) ("heading " <> show (lbId l) <> " on page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " is apart from " <> show away)
                : go rest
        _ -> go rest
   in go flows

-- | I7: the first line of the body of a note is on the page of the line with its mark.
i7NoteOnPage :: Check
i7NoteOnPage flows ps =
  let places = linePlaces ps
      cols = ordered ps
      firstPage note = case [poNumber p | p <- cols, (n, 0, _) <- poFootnotes p, n == note] of
        pg : _ -> Just pg
        [] -> Nothing
   in [ Breach I7 [lbId l] ("the note of line " <> show (lbId l) <> " starts on " <> maybe "no page" (("page " <>) . show) pg <> ", the line is on page " <> show (poNumber p))
      | f <- flows,
        l <- flowLines f,
        nb <- lbNotes l,
        let pg = firstPage (nbId nb),
        Just (_, p) <- [Map.lookup (lbId l) places],
        pg /= Just (poNumber p)
      ]

{- | I8: a heading at a recto is on an odd page, in its first column, its
first slot: no line and no figure sent on is before it (docs/adr/0206).
-}
i8Recto :: Check
i8Recto flows ps =
  let places = linePlaces ps
   in [ Breach I8 [lbId l] ("heading " <> show (lbId l) <> " at a recto is on page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " after " <> show k <> " slots")
      | FHeading {fhRecto = True, fhLines = l : _} <- flows,
        Just ((_, k), p) <- [Map.lookup (lbId l) places],
        even (poNumber p) || poColumn p /= 0 || k /= 0
      ]
