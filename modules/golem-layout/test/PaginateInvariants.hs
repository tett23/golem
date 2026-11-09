{- | The invariants of pagination (docs/adr/0204, its section 「不変条件」),
as predicates over the flow that goes in and the columns that come out,
read as docs/adr/0206 (its section 6) decides, and the invariants P1 to
P4 of need-lines and blank lines (golem-layout ADR 0025, its section
「不変条件」), their next block read as golem-layout ADR 0026 decides
(P1′, P3′ and P4′ of its section 「不変条件」), with its P5. They read nothing of the paginator but its input and
output, and every case is judged. P9 of golem-layout ADR 0043, widened
to P9′ by golem-layout ADR 0047, and its P11 alone compare the output
with that of another input, laid out by the paginator they are given;
W3 of golem-layout ADR 0044 compares the figures that wait read from the
two inputs when the outputs are the same.

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
    p1NeedLinesMet,
    p2NeedLinesRecorded,
    p3BlankNoOverflow,
    p4BlankWithNext,
    p5BlankBeforeWaiting,
    p9SpaceMoved,
    p11WaitingBeforeSpace,
    w3WaitingAlike,
    waitingFigures,
    invariants,
    breaches,
  )
where

import Data.List (sortOn, tails)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, listToMaybe, mapMaybe)
import Golem.Layout.Paginate
import Golem.Syntax (SrcSpan)

{- | The invariants of docs/adr/0204 and of golem-layout ADR 0025, 0026,
0043, 0044 and 0047, by their numbers: P9 is P9′ of golem-layout ADR
0047, which has P9 of ADR 0043 as its case with no figure that waits.
-}
data Invariant = I1 | I2 | I3 | I4 | I5 | I6 | I7 | I8 | P1 | P2 | P3 | P4 | P5 | P9 | P11 | W3
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
    (I8, i8Recto),
    (P1, p1NeedLinesMet separator),
    (P2, p2NeedLinesRecorded),
    (P3, p3BlankNoOverflow separator),
    (P4, p4BlankWithNext),
    (P5, p5BlankBeforeWaiting)
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

-- need-lines and blank lines (golem-layout ADR 0025)

{- | Whether a flow waits for the next one: the breaks, the controls of
page breaks, the blank lines and the spaces place nothing of their own
before it (docs/adr ADR 0017, 0030, 0046).
-}
waits :: Flow -> Bool
waits = \case
  FBreak _ -> True
  FNoBreak _ -> True
  FNeedLines _ _ -> True
  FAdjustLines _ _ -> True
  FBlank _ _ -> True
  FSpace _ -> True
  _ -> False

{- | Each flow that places something, with the flows that wait for it, in
the order of the flow: its next block. The figures that wait are passed
over (golem-layout ADR 0026): they are not the next block of the flows
before them, and those wait on for the block after them. The flows left
waiting at the end of the book have nothing to wait for and are dropped.
-}
waiting :: [Flow] -> [PageOut] -> [([Flow], Flow)]
waiting flows ps = fst (waitingAndLeft flows ps)

{- | 'waiting', and the flows left waiting at the end of the book, in their
order, with the figures that wait passed over among them.
-}
waitingAndLeft :: [Flow] -> [PageOut] -> ([([Flow], Flow)], [Flow])
waitingAndLeft flows ps = go [] flows
  where
    passed = waitingFigures flows ps
    -- the flows that wait and the figures passed over since the last block
    go held [] = ([], held)
    go held (f : rest)
      | waits f || any (`elem` passed) (figureIds f) = go (held <> [f]) rest
      | otherwise = let (bs, end) = go [] rest in ((filter waits held, f) : bs, end)

-- | The figure a flow is.
figureIds :: Flow -> [Int]
figureIds = \case
  FFigure {ffId = i} -> [i]
  FPageFigure {fpId = i} -> [i]
  _ -> []

{- | The figures that wait, read from the output (golem-layout ADR 0026,
its section 「実装すること」 3), in the order of the flow: the figures
written while a figure before them is held, not yet placed, and the
turned figures that cannot take the page where they are written.

A figure is held from where it is written until it is placed. One that
waits is held; so is one sent on by itself, placed in a column after the
column the flow has come to with nothing right before it to move it
there, or placed after the first part of the next block written after it
that is not a figure. A figure held is placed when it is in a column no
later than the one the flow has come to.

The column the flow has come to is that of the last slot placed of the
blocks before and of the figures placed where they are written, or of the
first column of the page each break written after them goes on to.
Blank lines right before a figure that does not wait move it; a
need-lines does when the grid lines left after the last slot, its notes
and their separator counted, are fewer than it asks for. A need-lines
is judged before the spaces after the block before, whether they are
before it or after it (docs/adr ADR 0030, golem-layout ADR 0043 and
ADR 0044): with fewer lines left, the flow comes to the next column,
and a figure held is placed when it is in that column or before. A
need-lines met there also moves a figure written after it and spaces
when the lines left, less those of the spaces, are fewer than the
figure's (golem-layout ADR 0027 and ADR 0044, W5): the figure does not
fit after the spaces, so the flow goes on to the next column for it.

The ADR reads a figure as waiting when it is placed after the first part
of the block written after it. That misses a figure that waits and is
placed before that block, when the block goes on to a later column and
places the figures waiting first, and it counts a figure sent on by
itself, to which the need-lines before it applies; the figures read here
are those 'place' makes wait. golem-layout ADR 0033 records this
reading: the figures are read from the flow and the output only (W1, W2).
golem-layout ADR 0044 adds the need-lines judged before a space written
after it (W4) and the figures that do not fit after the spaces (W5); the
lines of the spaces are those written in the input, not read from the
output, which counts also the spaces dropped at the top of a column.
A figure that waits does not clear the spaces before it: the need-lines
after it is judged before them (golem-layout ADR 0047).
-}
waitingFigures :: [Flow] -> [PageOut] -> [Int]
waitingFigures flows ps = go Nothing 0 Nothing [] flows
  where
    cols = ordered ps
    places = [((c, k), s) | ((c, k), _, s) <- slots ps]
    placeOf f = listToMaybe [pl | (pl, s) <- places, startsBlock f s]
    lastOf f = case [pl | (pl, s) <- places, ownedBy f s] of
      [] -> Nothing
      pls -> Just (maximum pls)
    -- a column the flow has come to may make no output: it is after the last one
    pageOf c = maybe (maximum (0 : map poNumber cols) + 1) poNumber (listToMaybe (drop c cols))
    -- the grid lines left after a slot in its column, its notes and their separator counted
    leftAt place = do
      (c, k) <- place
      p <- listToMaybe (drop c cols)
      let notes = sum [n | (_, _, n) <- poFootnotes p]
      pure (poLines p - endBefore flows p (k + 1) - notes - (if notes > 0 then 1 else 0))
    -- the column the flow has come to: of the last line placed, or of the first column of the page the breaks after it go on to
    reached lastText breaks = case lastText of
      Nothing -> Nothing
      Just (c, _)
        | breaks == 0 -> Just c
        | otherwise -> listToMaybe [c' | (c', p) <- zip [0 ..] cols, poNumber p >= pageOf c + breaks]
    {- need-lines judged before a space: with fewer lines left after the
    last slot than the largest asked for, the flow comes to the next
    column, and the figure held there or before is placed. The same
    judgement whether the space is before the need-lines or after it. -}
    judgedBeforeSpace lastText breaks held ns = case lastText of
      Just (c, _)
        | breaks == 0,
          not (null ns),
          maybe False (< maximum ns) (leftAt lastText) ->
            let held' = case held of
                  Just (hc, _) | hc > c + 1 -> held
                  _ -> Nothing
             in Just (Just (c + 1, -1), held')
      _ -> Nothing
    withoutNeeds = filter (\case FNeedLines _ _ -> False; _ -> True)
    -- the last line placed, the breaks after it, the figure held, the controls right before, the flows left
    go _ _ _ _ [] = []
    go lastText breaks held before (f : rest) = case f of
      FBreak _ -> go lastText (breaks + 1) held (before <> [f]) rest
      -- a need-lines after a space or before one is judged before it (golem-layout ADR 0043, 0044)
      FSpace _
        | Just (lastText', held') <- judgedBeforeSpace lastText breaks held [n | FNeedLines _ n <- before] ->
            go lastText' 0 held' (withoutNeeds before <> [f]) rest
      FNeedLines _ n
        | not (null [() | FSpace _ <- before]),
          Just (lastText', held') <- judgedBeforeSpace lastText breaks held (n : [m | FNeedLines _ m <- before]) ->
            go lastText' 0 held' (withoutNeeds before) rest
      _
        | waits f -> go lastText breaks held (before <> [f]) rest
        | [i] <- figureIds f,
          Just at@(c, _) <- placeOf f ->
            let came = reached lastText breaks
                later = maybe False (c >) came
                stillHeld = case held of
                  Just (hc, _) -> maybe True (hc >) came
                  Nothing -> False
                next = listToMaybe [pl | b <- rest, not (waits b), null (figureIds b), Just pl <- [placeOf b]]
                afterNext = maybe False (at >) next
                -- blank lines move a figure that does not wait; need-lines only when the lines left are fewer, or the figure does not fit after the spaces (golem-layout ADR 0044)
                needs = [n | FNeedLines _ n <- before]
                spaces = sum [k | FSpace k <- before]
                pastSpaces = case f of
                  FFigure {ffLines = h} -> breaks == 0 && spaces > 0 && maybe False (\l -> l - spaces < h) (leftAt lastText)
                  _ -> False
                moved =
                  not (null [() | FBlank _ _ <- before])
                    || (not (null needs) && (pastSpaces || maybe True (< maximum needs) (leftAt lastText)))
                turned = case f of
                  FPageFigure {} -> True
                  _ -> False
                waitsHere
                  | turned = stillHeld || maybe False (\cc -> pageOf c > pageOf cc) came
                  | otherwise = stillHeld
                bySelf = not waitsHere && not turned && (afterNext || (later && not moved))
                held' = if waitsHere || bySelf then Just at else Nothing
                -- a figure placed where it is written is where the flow has come to
                (lastText', breaks') = if waitsHere || isJust held' then (lastText, breaks) else (Just at, 0)
                -- a figure that waits keeps the spaces before it (golem-layout ADR 0047)
                before' = if waitsHere then [s | s@(FSpace _) <- before] else []
             in [i | waitsHere] <> go lastText' breaks' held' before' rest
        | null (figureIds f),
          Just end <- lastOf f ->
            let held' = case held of
                  Just h | h > end -> held
                  _ -> Nothing
             in go (Just end) 0 held' [] rest
        | otherwise -> go lastText breaks held [] rest

-- | Whether a slot holds part of a block.
ownedBy :: Flow -> Slotted -> Bool
ownedBy f s = case s of
  SLine j -> j `elem` ids
  SHeading j _ -> j `elem` ids
  SCode j _ _ -> j `elem` ids
  _ -> startsBlock f s
  where
    ids = map lbId (blockLines f)

-- | The lines of a block, in their order.
blockLines :: Flow -> [LineBox]
blockLines = \case
  FStanza vs -> concat vs
  FTable {ftHeader = h, ftRows = rows} -> h <> concat rows
  FCode {fcRows = ls} -> ls
  FRuled {frBody = RuledLines ls} -> ls
  FRuled {frBody = RuledHeading {rhLines = ls}} -> ls
  f -> flowLines f

-- | The first line of a block, or the figure it is.
blockIds :: Flow -> [Int]
blockIds = \case
  FFigure {ffId = i} -> [i]
  FWrapped {fwId = i} -> [i]
  FPageFigure {fpId = i} -> [i]
  f -> map lbId (take 1 (blockLines f))

-- | Whether a slot is the first of a block.
startsBlock :: Flow -> Slotted -> Bool
startsBlock f s = case (f, s) of
  (FFigure {ffId = i}, SFigure j) -> i == j
  (FWrapped {fwId = i}, SWrapped j) -> i == j
  (FPageFigure {fpId = i}, SPageFigure j) -> i == j
  (_, SLine j) -> first == Just j
  (_, SHeading j _) -> first == Just j
  (_, SCode j _ _) -> first == Just j
  _ -> False
  where
    first = lbId <$> listToMaybe (blockLines f)

-- | The first slot of a block: its column, its slot in the column and the column.
firstSlotOf :: [PageOut] -> Flow -> Maybe (Int, Int, PageOut)
firstSlotOf ps f = listToMaybe [(c, k, p) | ((c, k), p, s) <- slots ps, startsBlock f s]

-- | The grid lines a slot takes, as 'i2NoOverflow' counts them.
extentIn :: [Flow] -> Slotted -> Int
extentIn flows =
  let spans = headingSpans flows
      figures = Map.fromList (inputFigures flows)
   in \case
        SHeading l _ -> Map.findWithDefault 1 l spans
        SFigure i -> Map.findWithDefault 1 i figures
        _ -> 1

-- | The grid line after the slots of the column before the slot k: the first grid line of the column if none.
endBefore :: [Flow] -> PageOut -> Int -> Int
endBefore flows p k = maximum (csFirstLine (poColumnSet p) : [at + extentIn flows s | (at, s) <- take k (poSlots p)])

-- | The line that has the mark of each note.
noteMarks :: [Flow] -> Map NoteId Int
noteMarks flows = Map.fromList [(nbId nb, lbId l) | f <- flows, l <- blockLines f, nb <- lbNotes l]

{- | The lines of the notes of the column before the slot k, and the
separator if there are any: the notes continued from a column before and
the notes of the lines of the slots before k.
-}
notesBefore :: Int -> [Flow] -> PageOut -> Int -> Int
notesBefore separator flows p k =
  let marks = noteMarks flows
      before = concatMap (slotLines . snd) (take k (poSlots p))
      counted = [n | (note, from, n) <- poFootnotes p, from > 0 || maybe False (`elem` before) (Map.lookup note marks)]
   in if null counted then 0 else sum counted + separator

{- | P1: the first block after @need-lines N@, N no more than the grid
lines of its column, is placed in a column that has N grid lines or more
left before it, unless it is the first slot of a column with nothing in
it. The grid lines left are counted from the end of the slots before it
and the lines of the notes before it: the blank lines and the spaces
after the need-lines are not counted (docs/adr ADR 0046).
-}
p1NeedLinesMet :: Int -> Check
p1NeedLinesMet separator flows ps =
  [ Breach P1 (blockIds b) ("need-lines " <> show n <> " has " <> show room <> " grid lines left before its block on page " <> show (poNumber p) <> " column " <> show (poColumn p))
  | (ws, b) <- waiting flows ps,
    FNeedLines _ n <- ws,
    Just (_, k, p) <- [firstSlotOf ps b],
    n <= poLines p,
    let notes = notesBefore separator flows p k
        room = poLines p - endBefore flows p k - notes,
    k > 0 || notes > 0,
    room < n
  ]

{- | P2: a need-lines is recorded as unmet only when it asks for more
than the grid lines of the column it is recorded in, once, and of the
need-lines before a block one asking for more than the grid lines of the
column of the block is recorded (the larger of two in a row applies,
docs/adr ADR 0030).
-}
p2NeedLinesRecorded :: Check
p2NeedLinesRecorded flows ps =
  let recorded = [(sp, n, p) | p <- ordered ps, UnmetNeedLines sp n <- poUnmet p]
      written = [(sp, n) | FNeedLines sp n <- flows]
      counts = Map.fromListWith (+) [(sp, 1 :: Int) | (sp, _, _) <- recorded]
      wrong =
        [ Breach P2 [] ("need-lines " <> show n <> " is recorded in page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " of " <> show (poLines p) <> " grid lines")
        | (sp, n, p) <- recorded,
          n <= poLines p || (sp, n) `notElem` written
        ]
      twice = [Breach P2 [] ("need-lines at " <> show sp <> " is recorded " <> show c <> " times") | (sp, c) <- Map.toList counts, c > 1]
      missing =
        [ Breach P2 [] ("need-lines " <> show [n | (_, n) <- big] <> " is not recorded")
        | (ws, b) <- waiting flows ps,
          Just (_, _, p) <- [firstSlotOf ps b],
          let big = [(sp, n) | FNeedLines sp n <- ws, n > poLines p],
          not (null big),
          not (any ((`Map.member` counts) . fst) big)
        ]
   in wrong <> twice <> missing

-- | The blank lines before each block: the spans, the grid lines of all of them as the paginator counts them, and the block.
blanksBefore :: [Flow] -> [PageOut] -> [([SrcSpan], Int, Flow)]
blanksBefore flows ps =
  let capacity = maximum (1 : map poLines ps)
   in [ (map fst bs, foldl' (\a (_, n) -> min capacity (a + min capacity n)) 0 bs, b)
      | (ws, b) <- waiting flows ps,
        let bs = [(sp, n) | FBlank sp n <- ws],
        not (null bs)
      ]

-- | The blank lines recorded as dropped, by their span.
droppedBlanks :: [PageOut] -> Map SrcSpan Int
droppedBlanks ps = Map.fromListWith (+) [(sp, 1 :: Int) | p <- ps, DroppedBlank sp <- poUnmet p]

{- | P3: blank lines that are not dropped do not overflow their column:
the grid lines placed in it, the blank lines, the lines of its notes and
the separator do not exceed its grid lines. The output shows blank lines
only as the grid lines left empty before the block after them, so blank
lines not dropped and not seen there are a breach: no column is seen to
hold them.
-}
p3BlankNoOverflow :: Int -> Check
p3BlankNoOverflow separator flows ps =
  let dropped = droppedBlanks ps
   in [ Breach P3 ids why
      | (sps, total, b) <- blanksBefore flows ps,
        not (any (`Map.member` dropped) sps),
        Just (_, k, p) <- [firstSlotOf ps b],
        let ids = blockIds b
            start = maybe 0 fst (listToMaybe (drop k (poSlots p)))
            before = endBefore flows p k
            used = maximum (0 : [at + extentIn flows s | (at, s) <- poSlots p])
            notes = sum [n | (_, _, n) <- poFootnotes p]
            sep = if null (poFootnotes p) then 0 else separator
            whole = max used (before + total) + notes + sep,
        why <-
          [ "the blank lines of " <> show total <> " grid lines are not before their block on page " <> show (poNumber p) <> " column " <> show (poColumn p)
          | start - before < total
          ]
            <> [ "page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " uses " <> show whole <> " of " <> show (poLines p) <> " grid lines with its blank lines"
               | start - before >= total,
                 whole > poLines p
               ]
      ]

{- | P4: blank lines are in the column of the block after them, right
before its first slot, or dropped at the top of a column, its first slot
being the first of the column, each @blank-line recorded once as
dropped. A blank line is recorded only when it is dropped.
-}
p4BlankWithNext :: Check
p4BlankWithNext flows ps =
  let dropped = droppedBlanks ps
      written = [sp | FBlank sp _ <- flows]
      judged =
        [ Breach P4 ids why
        | (sps, total, b) <- blanksBefore flows ps,
          Just (_, k, p) <- [firstSlotOf ps b],
          let ids = blockIds b
              counts = map (\sp -> Map.findWithDefault 0 sp dropped) sps
              start = maybe 0 fst (listToMaybe (drop k (poSlots p)))
              at = "page " <> show (poNumber p) <> " column " <> show (poColumn p),
          why <-
            if all (== 1) counts
              then ["the blank lines are dropped, and their block is after slot " <> show k <> " of " <> at | k > 0]
              else
                if all (== 0) counts
                  then ["the blank lines are not in the column of their block, " <> at | start - endBefore flows p k < total]
                  else ["the blank lines are recorded as dropped " <> show counts <> " times"]
        ]
      stray = [Breach P4 [] ("a blank line at " <> show sp <> " not written is recorded as dropped") | sp <- Map.keys dropped, sp `notElem` written]
   in judged <> stray

{- | P5 (golem-layout ADR 0026): blank lines with no next block, nothing
but figures that wait after them to the end of the book, are placed in
no column: each @blank-line is recorded once as dropped.
-}
p5BlankBeforeWaiting :: Check
p5BlankBeforeWaiting flows ps =
  let dropped = droppedBlanks ps
      (_, left) = waitingAndLeft flows ps
   in [ Breach P5 figs ("the blank line at " <> show sp <> " before the figures that wait " <> show figs <> " is recorded as dropped " <> show c <> " times")
      | (FBlank sp _, after) <- zip left (drop 1 (tails left)),
        let figs = concatMap figureIds after,
        not (null figs),
        let c = Map.findWithDefault 0 sp dropped,
        c /= 1
      ]

{- | P9 of golem-layout ADR 0043, its section 「不変条件」, widened to P9′
by golem-layout ADR 0047: a space between the block before and a
need-lines, moved after the need-lines past the figures that wait
between them ('waitingFigures'), lays out the same slots ('poSlots') and
records ('poUnmet') in every column. Each space before a need-lines with
nothing but figures that wait between them is moved by itself, the
input laid out again by the paginator given. Only the inputs with no
break, no no-break and no page-lines among the controls between the
block before and the block after, the figures that wait passed over,
are judged. With no figure that waits between, this is P9 of ADR 0043.
-}
p9SpaceMoved :: ([Flow] -> [PageOut]) -> Check
p9SpaceMoved lay flows ps =
  [ Breach P9 [] ("the space at flow " <> show k <> " moved after the need-lines after it lays out " <> show moved <> ", not " <> show here)
  | (k, swapped) <- spacesMoved (waitingFigures flows ps) flows,
    let moved = outShape (lay swapped),
    moved /= here
  ]
  where
    here = outShape ps

{- | W3 of golem-layout ADR 0044, its section 「不変条件」: for each input
P9 (P9′ of golem-layout ADR 0047) lays out again, with the space moved after the need-lines, that lays
out the same, 'waitingFigures' reads the same figures from the two
inputs and the one output.
-}
w3WaitingAlike :: ([Flow] -> [PageOut]) -> Check
w3WaitingAlike lay flows ps =
  [ Breach W3 (here <> there) ("the space at flow " <> show k <> " moved after the need-lines after it lays out the same, and the figures that wait are read as " <> show there <> ", not " <> show here)
  | (k, swapped) <- spacesMoved (waitingFigures flows ps) flows,
    outShape (lay swapped) == outShape ps,
    let there = waitingFigures swapped ps,
    there /= here
  ]
  where
    here = waitingFigures flows ps

-- | The slots and records of every column, P9 compares.
outShape :: [PageOut] -> [(Int, Int, [(Int, Slotted)], [Unmet])]
outShape = map (\p -> (poNumber p, poColumn p, poSlots p, poUnmet p))

{- | The flows with each space before a need-lines moved right after it,
by itself, with where the space is: the space is followed by nothing but
the figures that wait of the ids given and then the need-lines. Only
those of the inputs with no break, no no-break and no page-lines among
the controls between the block before and the block after, the figures
that wait passed over, are moved (P9 of golem-layout ADR 0043, P9′ of
golem-layout ADR 0047).
-}
spacesMoved :: [Int] -> [Flow] -> [(Int, [Flow])]
spacesMoved waitingIds flows =
  [ (k, before <> between <> (n : s : after))
  | (k, (before, s@(FSpace _) : rest)) <- zip [0 ..] (map (`splitAt` flows) [0 .. length flows - 1]),
    let (between, more) = span (isWaiting waitingIds) rest,
    not (any manual (reverse (takeWhile (passedOver waitingIds) (reverse before)) <> takeWhile (passedOver waitingIds) (s : rest))),
    n@(FNeedLines _ _) : after <- [more]
  ]

{- | P11 of golem-layout ADR 0047, its section 「不変条件」: a space with
nothing but figures that wait between it and a need-lines lays out as
the input with those figures written before the space, but where the
figures are: the slots of the figures moved taken out, the slots
('poSlots') and records ('poUnmet') of every column are the same. Only
the inputs P9′ judges are judged.
-}
p11WaitingBeforeSpace :: ([Flow] -> [PageOut]) -> Check
p11WaitingBeforeSpace lay flows ps =
  [ Breach P11 ids ("the figures that wait " <> show ids <> " written before the space at flow " <> show k <> " lay out " <> show moved <> ", not " <> show here)
  | (k, ids, swapped) <- waitingMovedBefore waitingIds flows,
    let here = withoutFigures ids (outShape ps)
        moved = withoutFigures ids (outShape (lay swapped)),
    moved /= here
  ]
  where
    waitingIds = waitingFigures flows ps
    withoutFigures ids = map (\(n, c, sl, u) -> (n, c, [x | x@(_, sl') <- sl, not (any (\i -> sl' == SFigure i || sl' == SPageFigure i) ids)], u))

{- | The flows with the figures that wait between a space and a need-lines
written before the space, with where the space is and the figures: the
inputs 'spacesMoved' moves, with at least one figure between.
-}
waitingMovedBefore :: [Int] -> [Flow] -> [(Int, [Int], [Flow])]
waitingMovedBefore waitingIds flows =
  [ (k, concatMap figureIds between, before <> between <> (s : more))
  | (k, (before, s@(FSpace _) : rest)) <- zip [0 ..] (map (`splitAt` flows) [0 .. length flows - 1]),
    let (between, more) = span (isWaiting waitingIds) rest,
    not (null between),
    not (any manual (reverse (takeWhile (passedOver waitingIds) (reverse before)) <> takeWhile (passedOver waitingIds) (s : rest))),
    FNeedLines _ _ : _ <- [more]
  ]

-- | Whether a flow is a figure that waits, of the ids given.
isWaiting :: [Int] -> Flow -> Bool
isWaiting waitingIds f = case figureIds f of
  [i] -> i `elem` waitingIds
  _ -> False

-- | The flows that place nothing of their own between two blocks, and the figures that wait among them.
passedOver :: [Int] -> Flow -> Bool
passedOver waitingIds f = waits f || isWaiting waitingIds f

-- | The controls P9 does not judge across: a break, a no-break, a page-lines.
manual :: Flow -> Bool
manual = \case
  FBreak _ -> True
  FNoBreak _ -> True
  FAdjustLines _ _ -> True
  _ -> False
