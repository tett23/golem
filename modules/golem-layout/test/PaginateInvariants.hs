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
    k1FirstPart,
    k2LastPart,
    k3KeepAll,
    k4KeepNext,
    k5Start,
    k6NoExtraStart,
    keepInvariants,
    keepBreaches,
    b1BoxShape,
    b2BoxNoOverflow,
    b3BoxParts,
    boxInvariants,
    boxBreaches,
    pl1Parity,
    pl2Continues,
    pl3SectionStart,
    pl7SectionBreak,
    p9SpaceMoved,
    p11WaitingBeforeSpace,
    w3WaitingAlike,
    waitingFigures,
    invariants,
    breaches,
    Seen,
    seen,
    breachesIn,
    movedBreaches,
  )
where

import Data.List (sortOn, tails)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, listToMaybe, mapMaybe)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.PageLabel (PageLabel (..), Section (..))
import Golem.Layout.Paginate
import Golem.Syntax (SrcSpan)
import PaginateEnum (startOfKind)

{- | The invariants of docs/adr/0204 and of golem-layout ADR 0025, 0026,
0043, 0044 and 0047, by their numbers: P9 is P9′ of golem-layout ADR
0047, which has P9 of ADR 0043 as its case with no figure that waits.
PL1, PL2, PL3 and PL7 are I1, I2, I3 and I7 of docs/adr/0260, of the
page labels and the breaks before sections.
-}
data Invariant = I1 | I2 | I3 | I4 | I5 | I6 | I7 | I8 | P1 | P2 | P3 | P4 | P5 | P9 | P11 | W3 | PL1 | PL2 | PL3 | PL7 | K1 | K2 | K3 | K4 | K5 | K6 | B1 | B2 | B3
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | An invariant broken: the lines or figures concerned, and how.
data Breach = Breach {breachOf :: !Invariant, breachAt :: ![Int], breachWhy :: !String}
  deriving stock (Eq, Show)

-- | A predicate over the flow and the columns, read through 'Seen'.
type Check = Seen -> [Breach]

{- | The flow and the columns, with what several predicates read of them:
each is made once for an input, however many predicates read it, since
every predicate is judged on every input (docs/adr ADR 0281, its section
4: the tests are made faster by not making the same thing again). Each
field is what the function named in its comment returns.
-}
data Seen = Seen
  { seenFlows :: [Flow],
    seenOut :: [PageOut],
    -- | 'ordered'
    seenOrdered :: [PageOut],
    -- | 'slotsOf'
    seenSlots :: [(Place, PageOut, Slotted)],
    -- | 'linePlacesOf'
    seenLinePlaces :: Map Int (Place, PageOut),
    -- | 'figurePlacesOf'
    seenFigurePlaces :: Map Int Place,
    -- | 'waitingFigures'
    seenWaitingFigures :: [Int],
    -- | 'waitingAndLeftWith'
    seenWaitingAndLeft :: ([([Flow], Flow)], [Flow]),
    -- | 'blanksBeforeWith'
    seenBlanksBefore :: [([SrcSpan], Int, Flow)],
    -- | 'droppedBlanks'
    seenDropped :: Map SrcSpan Int,
    -- | 'labelsOf'
    seenLabels :: [(Int, PageLabel)],
    -- | 'firstsOf'
    seenFirsts :: Map Int [Int],
    -- | 'extentIn'
    seenExtent :: Slotted -> Int,
    -- | 'noteMarks'
    seenNoteMarks :: Map NoteId Int
  }

-- | The flow and the columns, with nothing read of them yet: each field is made when a predicate first reads it.
seen :: [Flow] -> [PageOut] -> Seen
seen flows ps =
  let cols = ordered ps
      placed = slotsOf cols
      extent = extentIn flows
      figures = waitingFiguresWith cols placed extent flows ps
      held = waitingAndLeftWith figures flows
   in Seen
        { seenFlows = flows,
          seenOut = ps,
          seenOrdered = cols,
          seenSlots = placed,
          seenLinePlaces = linePlacesOf placed,
          seenFigurePlaces = figurePlacesOf placed,
          seenWaitingFigures = figures,
          seenWaitingAndLeft = held,
          seenBlanksBefore = blanksBeforeWith (fst held) ps,
          seenDropped = droppedBlanks ps,
          seenLabels = labelsOf flows ps,
          seenFirsts = firstsOf ps,
          seenExtent = extent,
          seenNoteMarks = noteMarks flows
        }

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
    (P5, p5BlankBeforeWaiting),
    (PL1, pl1Parity),
    (PL2, pl2Continues),
    (PL3, pl3SectionStart),
    (PL7, pl7SectionBreak)
  ]

-- | The breaches of every invariant, I1 first.
breaches :: Int -> [Flow] -> [PageOut] -> [Breach]
breaches separator flows ps = breachesIn separator (seen flows ps)

-- | 'breaches' of an input read through 'Seen'.
breachesIn :: Int -> Seen -> [Breach]
breachesIn separator judged = concatMap (\(_, c) -> c judged) (invariants separator)

{- | The invariants of the inputs of the keep options (docs/adr/0261): those
of 'invariants' with I4 and I5 replaced by K1 and K2, which read the keep
of each paragraph, and K3 to K6.
-}
keepInvariants :: Int -> [(Invariant, Check)]
keepInvariants separator =
  [(i, c) | (i, c) <- invariants separator, i `notElem` [I4, I5]]
    <> [(K1, k1FirstPart), (K2, k2LastPart), (K3, k3KeepAll), (K4, k4KeepNext), (K5, k5Start), (K6, k6NoExtraStart)]

-- | The breaches of 'keepInvariants'.
keepBreaches :: Int -> [Flow] -> [PageOut] -> [Breach]
keepBreaches separator flows ps = let judged = seen flows ps in concatMap (\(_, c) -> c judged) (keepInvariants separator)

{- | The invariants of the inputs of boxes (docs/adr/0271): those of
'invariants' and B1 to B3.
-}
boxInvariants :: Int -> [(Invariant, Check)]
boxInvariants separator = invariants separator <> [(B1, b1BoxShape), (B2, b2BoxNoOverflow separator), (B3, b3BoxParts)]

-- | The breaches of 'boxInvariants'.
boxBreaches :: Int -> [Flow] -> [PageOut] -> [Breach]
boxBreaches separator flows ps = let judged = seen flows ps in concatMap (\(_, c) -> c judged) (boxInvariants separator)

-- the input

-- | The flows with the body of each box in its place (docs/adr/0271).
unboxed :: [Flow] -> [Flow]
unboxed = concatMap $ \case
  FBoxed {fbBody = body} -> unboxed body
  f -> [f]

-- | The lines of a flow; of a box, those of its body.
flowLines :: Flow -> [LineBox]
flowLines = \case
  FBoxed {fbBody = body} -> concatMap flowLines body
  FParagraph _ ls -> ls
  FContinued _ ls -> ls
  FStanza _ vs -> concat vs
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

-- | Every slot with its place and its column, of the columns in order ('ordered').
slotsOf :: [PageOut] -> [(Place, PageOut, Slotted)]
slotsOf cols = [((c, k), p, s) | (c, p) <- zip [0 ..] cols, (k, (_, s)) <- zip [0 ..] (poSlots p)]

-- | The place of each line placed (the first, if placed more than once), of the slots given ('slotsOf').
linePlacesOf :: [(Place, PageOut, Slotted)] -> Map Int (Place, PageOut)
linePlacesOf placed = Map.fromListWith (\_ old -> old) [(i, (pl, p)) | (pl, p, s) <- placed, i <- slotLines s]

-- | The place of each figure placed, of the slots given ('slotsOf').
figurePlacesOf :: [(Place, PageOut, Slotted)] -> Map Int Place
figurePlacesOf placed = Map.fromListWith (\_ old -> old) [(i, pl) | (pl, _, s) <- placed, Just i <- [slotFigure s]]

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
i1PlacedOnce sn@Seen {seenFlows = flows} =
  let placedLines = Map.fromListWith (+) [(i, 1 :: Int) | (_, _, s) <- seenSlots sn, i <- slotLines s]
      placedFigures = Map.fromListWith (+) [(i, 1 :: Int) | (_, _, s) <- seenSlots sn, Just i <- [slotFigure s]]
      once what counts i = case Map.findWithDefault 0 i counts of
        1 -> []
        n -> [Breach I1 [i] (what <> " " <> show i <> " placed " <> show n <> " times")]
   in concatMap (once "line" placedLines) (inputLines flows)
        <> concatMap (once "figure" placedFigures . fst) (inputFigures flows)
        <> [ Breach I1 [] ("blank page " <> show (poNumber p) <> " holds something")
           | p <- seenOrdered sn,
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
i2NoOverflow separator sn@Seen {seenFlows = flows} =
  let firstLines = [l | FParagraph _ (l : _) <- flows]
      extent = seenExtent sn
      cols = seenOrdered sn
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
i3Order sn@Seen {seenFlows = flows} =
  let index = Map.fromList (zip (inputLines flows) [0 :: Int ..])
      figIndex = Map.fromList (zip (map fst (inputFigures flows)) [0 :: Int ..])
      textOut = [i | (_, _, s) <- seenSlots sn, i <- slotLines s]
      figsOut = [i | (_, _, s) <- seenSlots sn, Just i <- [slotFigure s]]
      inversions ix what out =
        [ Breach I3 [a, b] (what <> " " <> show b <> " comes out after " <> show a)
        | (a, b) <- zip out (drop 1 out),
          Just x <- [Map.lookup a ix],
          Just y <- [Map.lookup b ix],
          y < x
        ]
      places = seenLinePlaces sn
      figPlaces = seenFigurePlaces sn
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
paragraphs flows = [map lbId ls | FParagraph _ ls <- unboxed flows, length ls >= 2]

{- | I4: the first line of a paragraph of two lines or more is not left
alone at the end of a column with the rest in a later column, unless
nothing is before it in its column (an empty column), or nothing but
headings placed from the top of the column: such a column places lines
as an empty one does (docs/adr/0206).
-}
i4NoOrphan :: Check
i4NoOrphan sn@Seen {seenFlows = flows} =
  let places = seenLinePlaces sn
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
i5NoWidow sn@Seen {seenFlows = flows} =
  let places = seenLinePlaces sn
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
i6HeadingKept sn@Seen {seenFlows = flows} =
  let places = seenLinePlaces sn
      isHeading = \case
        FHeading {fhRecto = False} -> True
        _ -> False
      firstOf kp ls = take (firstPart kp True (length ls)) ls
      kept rest =
        let run = takeWhile isHeading rest
            after = drop (length run) rest
            para = case after of
              FParagraph kp ls : _ -> map lbId (firstOf kp ls)
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
i7NoteOnPage sn@Seen {seenFlows = flows} =
  let places = seenLinePlaces sn
      cols = seenOrdered sn
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
i8Recto sn@Seen {seenFlows = flows} =
  let places = seenLinePlaces sn
   in [ Breach I8 [lbId l] ("heading " <> show (lbId l) <> " at a recto is on page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " after " <> show k <> " slots")
      | FHeading {fhRecto = True, fhLines = l : _} <- flows,
        Just ((_, k), p) <- [Map.lookup (lbId l) places],
        even (poNumber p) || poColumn p /= 0 || k /= 0
      ]

-- page labels and sections (docs/adr/0260)

-- | The sections of a flow, of no notation: the page labels need only their starts.
flowSections :: [Flow] -> Map Int Section
flowSections flows = Map.fromList [(i, Section (startOfKind k) Nothing) | FSection (OfSection i) k <- flows]

-- | The label of each page, by its number.
labelsOf :: [Flow] -> [PageOut] -> [(Int, PageLabel)]
labelsOf flows ps = Map.toList (pageLabels (flowSections flows) ps)

-- | The sections whose first page each page is, in the order of the flow.
firstsOf :: [PageOut] -> Map Int [Int]
firstsOf ps = Map.fromListWith (flip (<>)) [(poNumber p, poSections p) | p <- ps, not (null (poSections p))]

-- | PL1 (I1 of docs/adr/0260): the number of the label of every page has the parity of the page.
pl1Parity :: Check
pl1Parity sn =
  [ Breach PL1 [] ("page " <> show p <> " is numbered " <> show (plNumber l))
  | (p, l) <- seenLabels sn,
    odd (plNumber l) /= odd p
  ]

{- | PL2 (I2 of docs/adr/0260): a page that is no first page of a section
is numbered one more than the page before, in its notation.
-}
pl2Continues :: Check
pl2Continues sn =
  let ls = seenLabels sn
      firsts = seenFirsts sn
   in [ Breach PL2 [] ("page " <> show p <> " is numbered " <> show (plNumber l) <> " after " <> show (plNumber l0))
      | ((_, l0), (p, l)) <- zip ls (drop 1 ls),
        Map.notMember p firsts,
        plNumber l /= plNumber l0 + 1 || plNotation l /= plNotation l0
      ]

{- | PL3 (I3 of docs/adr/0260): the first page of a section with a start
is numbered its start; of one without, one more than the page before, or
1 on the first page. Of the sections that start on one page, the last.
-}
pl3SectionStart :: Check
pl3SectionStart sn@Seen {seenFlows = flows} =
  let ls = Map.fromList (seenLabels sn)
      starts = Map.fromList [(i, startOfKind k) | FSection (OfSection i) k <- flows]
   in [ Breach PL3 [] ("page " <> show p <> " of section " <> show s <> " is numbered " <> show (plNumber l))
      | (p, ss@(_ : _)) <- Map.toList (seenFirsts sn),
        let s = last ss,
        Just l <- [Map.lookup p ls],
        plNumber l /= expectedOf ls starts p s
      ]
  where
    expectedOf ls starts p s = case Map.findWithDefault Nothing s starts of
      Just n -> n
      Nothing -> maybe 1 ((+ 1) . plNumber) (Map.lookup (p - 1) ls)

{- | PL7 (I7 of docs/adr/0260): the lines and figures after a section are
on its first page or later; those before it, on pages before its first
page. A section with no first page has nothing placed after it.
-}
pl7SectionBreak :: Check
pl7SectionBreak sn@Seen {seenFlows = flows, seenOut = ps} =
  let lines' = Map.map (poNumber . snd) (seenLinePlaces sn)
      figures = Map.fromListWith (\_ old -> old) [(i, poNumber p) | (_, p, s) <- seenSlots sn, Just i <- [slotFigure s]]
      pagesOfFlow f = [n | l <- flowLines f, Just n <- [Map.lookup (lbId l) lines']] <> [n | FFigure i _ _ _ <- [f], Just n <- [Map.lookup i figures]]
      firstPage = Map.fromList [(s, poNumber p) | p <- ps, s <- poSections p]
   in concat
        [ case Map.lookup i firstPage of
            Just f ->
              [Breach PL7 [] ("a block before section " <> show i <> " is on page " <> show n <> ", not before " <> show f) | n <- before, n >= f]
                <> [Breach PL7 [] ("a block after section " <> show i <> " is on page " <> show n <> ", before " <> show f) | n <- after, n < f]
            Nothing -> [Breach PL7 [] ("section " <> show i <> " has no page, a block after it is on page " <> show n) | n <- take 1 after]
        | (k, FSection (OfSection i) _) <- zip [0 :: Int ..] flows,
          let before = concatMap pagesOfFlow (take k flows)
              after = concatMap pagesOfFlow (drop (k + 1) flows)
        ]

-- the keep options of paragraph styles (docs/adr/0261)

-- | The paragraphs and stanzas of a flow: their keep, and their verse lines (a line each for a paragraph).
keptBlocks :: [Flow] -> [(Keep, [[Int]])]
keptBlocks flows =
  [(kp, [[lbId l] | l <- ls]) | FParagraph kp ls <- flows, not (null ls)]
    <> [(kp, map (map lbId) vs) | FStanza kp vs <- flows, not (null vs)]

{- | The parts of a block: for each column it is placed in, in order, the
column, the verse lines whose first line is there, whether the column
held nothing but headings and figures before the first of them ("from an
empty column"), and the column.
-}
partsOf :: Map Int (Place, PageOut) -> [[Int]] -> [(Int, Int, Bool, PageOut)]
partsOf places verses =
  let firsts = [(c, k, p) | (v : _) <- verses, Just ((c, k), p) <- [Map.lookup v places]]
      grouped = foldr (\(c, k, p) acc -> case acc of ((c', n, _, _) : more) | c' == c -> (c, n + 1, k, p) : more; _ -> (c, 1 :: Int, k, p) : acc) [] firsts
   in [(c, n, all (\sl -> isHeadingSlot sl || isFigureSlot sl) (slotsBefore p k), p) | (c, n, k, p) <- grouped]

-- | Whether a slot holds a figure.
isFigureSlot :: Slotted -> Bool
isFigureSlot = \case
  SFigure _ -> True
  SPageFigure _ -> True
  _ -> False

-- | Whether the output records an unmet control.
recordsUnmet :: [PageOut] -> Unmet -> Bool
recordsUnmet ps u = any (elem u . poUnmet) ps

{- | K1: the first part of a block broken into two parts or more has
kFirst verse lines or more, unless it is placed from an empty column and
the output records its 'ShortPart'.
-}
k1FirstPart :: Check
k1FirstPart sn@Seen {seenFlows = flows, seenOut = ps} =
  [ Breach K1 (concat (take n vs)) ("the first part of the block of line " <> show pid <> " has " <> show n <> " verse lines, fewer than " <> show (kFirst kp))
  | (kp, vs@((pid : _) : _)) <- keptBlocks flows,
    (_, n, fromEmpty, _) : _ : _ <- [partsOf (seenLinePlaces sn) vs],
    n < kFirst kp,
    not (fromEmpty && recordsUnmet ps (ShortPart FirstPart pid (kFirst kp) n))
  ]

{- | K2: the last part of a block broken into two parts or more has kLast
verse lines or more, unless the part before it is placed from an empty
column, its column holds nothing of the flow after its headings but lines
of the block, and the output records its 'ShortPart'.
-}
k2LastPart :: Check
k2LastPart sn@Seen {seenFlows = flows, seenOut = ps} =
  [ Breach K2 (concat (drop (length vs - n) vs)) ("the last part of the block of line " <> show pid <> " has " <> show n <> " verse lines, fewer than " <> show (kLast kp))
  | (kp, vs@((pid : _) : _)) <- keptBlocks flows,
    let parts = partsOf (seenLinePlaces sn) vs,
    length parts >= 2,
    let (_, n, _, _) = last parts
        (_, _, fromEmpty, pb) = last (init parts)
        own = all ((\sl -> isHeadingSlot sl || (all (`elem` concat vs) (slotLines sl) && not (null (slotLines sl)))) . snd) (poSlots pb),
    n < kLast kp,
    not (fromEmpty && own && recordsUnmet ps (ShortPart LastPart pid (kLast kp) n))
  ]

{- | K3: a block of keep-all-lines is in one column, unless its first part
is placed from an empty column and the output records its 'SplitKept'.
-}
k3KeepAll :: Check
k3KeepAll sn@Seen {seenFlows = flows, seenOut = ps} =
  [ Breach K3 [pid] ("the block of line " <> show pid <> " of keep-all-lines is in " <> show (length parts) <> " columns")
  | (kp, vs@((pid : _) : _)) <- keptBlocks flows,
    kAll kp,
    let parts = partsOf (seenLinePlaces sn) vs,
    (_, _, fromEmpty, _) : _ : _ <- [parts],
    not (fromEmpty && recordsUnmet ps (SplitKept pid))
  ]

{- | The flows after a keep-with-next past which the next block is found:
the controls of page breaks, the spaces, the blank lines, the breaks and
the starts.
-}
passedByKeep :: Flow -> Bool
passedByKeep = \case
  FSpace _ -> True
  FNeedLines {} -> True
  FAdjustLines {} -> True
  FNoBreak _ -> True
  FKeepNext {} -> True
  FBlank {} -> True
  FBreak _ -> True
  FSection {} -> True
  _ -> False

{- | K4: for a keep-with-next of n lines after a paragraph or a stanza P,
exactly one of: the last line of P and the first part of the block after
it (of a paragraph or a stanza, its first part made at least n lines; the
first line or figure of anything else) are in one column, and the output
records 'UnmetKeepNext'.
-}
k4KeepNext :: Check
k4KeepNext sn@Seen {seenFlows = flows, seenOut = ps} =
  [ Breach K4 [] ("the keep-with-next " <> show sp <> (if held then " is held and recorded" else " is not held and not recorded"))
  | (k, FKeepNext sp n) <- zip [0 :: Int ..] flows,
    Just prev <- [lastText (take k flows)],
    l <- take 1 (reverse (flowLines prev)),
    let after = drop (k + 1) flows
        target = colOfLine (lbId l)
        firstOf kp len = max (firstPart kp True len) (min n len)
        nextCols = case dropWhile passedByKeep after of
          FParagraph kp ls : _ -> map (colOfLine . lbId) (take (firstOf kp (length ls)) ls)
          FContinued kp ls : _ -> map (colOfLine . lbId) (take (max (firstPart kp False (length ls)) (min n (length ls))) ls)
          FStanza kp vs : _ -> map (colOfLine . lbId) (concat (take (firstOf kp (length vs)) vs))
          FFigure i _ _ _ : _ -> [fst <$> Map.lookup i (seenFigurePlaces sn)]
          b : _ -> [colOfLine (lbId x) | x <- take 1 (flowLines b)]
          [] -> [Nothing]
        held = isJust target && not (null nextCols) && all (== target) nextCols,
    held == recordsUnmet ps (UnmetKeepNext sp)
  ]
  where
    colOfLine i = fst . fst <$> Map.lookup i (seenLinePlaces sn)
    lastText before = case reverse (filter (not . passedByKeep) before) of
      f@FParagraph {} : _ -> Just f
      f@FStanza {} : _ -> Just f
      _ -> Nothing

-- | Each start of a paragraph and the first line of the paragraph after it, with the flows before it.
startsOf :: [Flow] -> [([Flow], BreakKind, Int)]
startsOf flows =
  [ (take k flows, kind, lbId l)
  | (k, FSection (OfParagraph _) kind) <- zip [0 ..] flows,
    l : _ <- [concatMap flowLines (take 1 (dropWhile passedByKeep (drop (k + 1) flows)))]
  ]

{- | K5: the first line of a paragraph after a start of a column has before
it in its column nothing but figures; of a page, nothing but figures in
any column of its page before it; of a recto or a verso, on an odd or an
even page too.
-}
k5Start :: Check
k5Start sn@Seen {seenFlows = flows, seenOut = ps} =
  [ Breach K5 [l] ("line " <> show l <> " after a start of " <> show kind <> " is on page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " after " <> show k <> " slots")
  | (_, kind, l) <- startsOf flows,
    Just ((_, k), p) <- [Map.lookup l (seenLinePlaces sn)],
    let columnClear = all isFigureSlot (slotsBefore p k)
        pageClear = columnClear && and [all (isFigureSlot . snd) (poSlots q) | q <- ps, poNumber q == poNumber p, poColumn q < poColumn p]
        ok = case kind of
          BreakColumn -> columnClear
          BreakPage -> pageClear
          BreakRecto -> pageClear && odd (poNumber p)
          BreakVerso -> pageClear && even (poNumber p),
    not ok
  ]

{- | K6: a start goes no further than it must: a column to the column the
flow came to (that of the last line or figure placed before it, or the
first column), when that holds nothing else but figures, or to the next
column; a page to the page the flow came to, when it holds nothing else
but figures, or to the next page; a recto or a verso to the first page of
its parity from there. Starts after a break or another start are not
judged.
-}
k6NoExtraStart :: Check
k6NoExtraStart sn@Seen {seenFlows = flows} =
  [ Breach K6 [l] ("line " <> show l <> " after a start of " <> show kind <> " went past the column the flow came to")
  | (before, kind, l) <- startsOf flows,
    not (any (\case FBreak _ -> True; FSection {} -> True; _ -> False) (takeWhile passedByKeep (reverse before))),
    Just ((c, _), p) <- [Map.lookup l (seenLinePlaces sn)],
    let placedBefore = [pl | f <- before, pl <- placesOf f]
        cols = seenOrdered sn
        (came, cameP) = case placedBefore of
          [] -> (0, 1)
          _ -> let (c0, _) = maximum placedBefore in (c0, poNumber (cols !! c0))
        firstPageFrom q par = if par q then q else q + 1
        -- the page the flow came to, or the next when that one holds something
        froms = [cameP, cameP + 1]
        ok = case kind of
          BreakColumn -> c == came || c == came + 1
          BreakPage -> poNumber p `elem` froms
          BreakRecto -> poNumber p `elem` map (`firstPageFrom` odd) froms
          BreakVerso -> poNumber p `elem` map (`firstPageFrom` even) froms,
    not ok
  ]
  where
    placesOf f = [pl | i <- map lbId (flowLines f), Just (pl, _) <- [Map.lookup i (seenLinePlaces sn)]] <> [pl | FFigure i _ _ _ <- [f], Just pl <- [Map.lookup i (seenFigurePlaces sn)]]

-- need-lines and blank lines (golem-layout ADR 0025)

{- | Whether a flow waits for the next one: the breaks, the controls of
page breaks, the blank lines and the spaces place nothing of their own
before it (docs/adr ADR 0017, 0030, 0046).
-}
waits :: Flow -> Bool
waits = \case
  FBreak _ -> True
  FSection {} -> True
  FNoBreak _ -> True
  FNeedLines _ _ -> True
  FAdjustLines _ _ -> True
  FBlank _ _ -> True
  FSpace _ -> True
  _ -> False

{- | Each flow that places something, with the flows that wait for it, in
the order of the flow: its next block. The figures that wait, given
('waitingFigures'), are passed over (golem-layout ADR 0026): they are not
the next block of the flows before them, and those wait on for the block
after them. The flows left waiting at the end of the book have nothing
to wait for and are dropped. And second, the flows left waiting at the
end of the book, in their order, with the figures that wait passed over
among them.
-}
waitingAndLeftWith :: [Int] -> [Flow] -> ([([Flow], Flow)], [Flow])
waitingAndLeftWith passed = go []
  where
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
first column of the page each break written after them goes on to. The
break before a section goes on to the first page of the section, which
the output records, past a blank page when the parity of its start asks
for one (docs/adr/0260): the flow comes to the first column of that page.
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
waitingFigures flows ps = let cols = ordered ps in waitingFiguresWith cols (slotsOf cols) (extentIn flows) flows ps

-- | 'waitingFigures' with the columns in order, their slots and the grid lines of a slot ('extentIn') given.
waitingFiguresWith :: [PageOut] -> [(Place, PageOut, Slotted)] -> (Slotted -> Int) -> [Flow] -> [PageOut] -> [Int]
waitingFiguresWith cols placed extent flows ps = go Nothing 0 Nothing [] flows
  where
    places = [((c, k), s) | ((c, k), _, s) <- placed]
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
      pure (poLines p - endBefore extent p (k + 1) - notes - (if notes > 0 then 1 else 0))
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
    -- the first column of the first page of a section, as the output records it
    sectionColumn s = listToMaybe [c | p <- ps, s `elem` poSections p, (c, q) <- zip [0 ..] cols, poNumber q == poNumber p]
    withoutNeeds = filter (\case FNeedLines _ _ -> False; _ -> True)
    -- the last line placed, the breaks after it, the figure held, the controls right before, the flows left
    go _ _ _ _ [] = []
    go lastText breaks held before (f : rest) = case f of
      FBreak _ -> go lastText (breaks + 1) held (before <> [f]) rest
      -- the break before a section goes on to the first page of the section, past a blank page for its parity (docs/adr/0260)
      FSection (OfSection s) _
        | Just c <- sectionColumn s -> go (Just (c, -1)) 0 held (before <> [f]) rest
      FSection {} -> go lastText (breaks + 1) held (before <> [f]) rest
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
  FStanza _ vs -> concat vs
  FTable {ftHeader = h, ftRows = rows, ftCaption = c} -> c <> h <> concat rows
  FCode {fcRows = ls} -> ls
  FRuled {frBody = RuledLines _ ls} -> ls
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
firstSlotOf :: [(Place, PageOut, Slotted)] -> Flow -> Maybe (Int, Int, PageOut)
firstSlotOf placed f = listToMaybe [(c, k, p) | ((c, k), p, s) <- placed, startsBlock f s]

-- | The grid lines a slot takes, as 'i2NoOverflow' counts them.
extentIn :: [Flow] -> Slotted -> Int
extentIn flows =
  let spans = headingSpans flows
      figures = Map.fromList (inputFigures flows)
   in \case
        SHeading l _ -> Map.findWithDefault 1 l spans
        SFigure i -> Map.findWithDefault 1 i figures
        _ -> 1

-- | The grid line after the slots of the column before the slot k, each taking the grid lines given ('extentIn'): the first grid line of the column if none.
endBefore :: (Slotted -> Int) -> PageOut -> Int -> Int
endBefore extent p k = maximum (csFirstLine (poColumnSet p) : [at + extent s | (at, s) <- take k (poSlots p)])

-- | The line that has the mark of each note.
noteMarks :: [Flow] -> Map NoteId Int
noteMarks flows = Map.fromList [(nbId nb, lbId l) | f <- flows, l <- blockLines f, nb <- lbNotes l]

{- | The lines of the notes of the column before the slot k, and the
separator if there are any: the notes continued from a column before and
the notes of the lines of the slots before k, their marks given
('noteMarks').
-}
notesBefore :: Int -> Map NoteId Int -> PageOut -> Int -> Int
notesBefore separator marks p k =
  let before = concatMap (slotLines . snd) (take k (poSlots p))
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
p1NeedLinesMet separator sn =
  [ Breach P1 (blockIds b) ("need-lines " <> show n <> " has " <> show room <> " grid lines left before its block on page " <> show (poNumber p) <> " column " <> show (poColumn p))
  | (ws, b) <- fst (seenWaitingAndLeft sn),
    FNeedLines _ n <- ws,
    Just (_, k, p) <- [firstSlotOf (seenSlots sn) b],
    n <= poLines p,
    let notes = notesBefore separator (seenNoteMarks sn) p k
        room = poLines p - endBefore (seenExtent sn) p k - notes,
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
p2NeedLinesRecorded sn@Seen {seenFlows = flows} =
  let recorded = [(sp, n, p) | p <- seenOrdered sn, UnmetNeedLines sp n <- poUnmet p]
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
        | (ws, b) <- fst (seenWaitingAndLeft sn),
          Just (_, _, p) <- [firstSlotOf (seenSlots sn) b],
          let big = [(sp, n) | FNeedLines sp n <- ws, n > poLines p],
          not (null big),
          not (any ((`Map.member` counts) . fst) big)
        ]
   in wrong <> twice <> missing

{- | The blank lines before each block: the spans, the grid lines of all
of them as the paginator counts them, and the block, of the next blocks
given ('waitingAndLeftWith').
-}
blanksBeforeWith :: [([Flow], Flow)] -> [PageOut] -> [([SrcSpan], Int, Flow)]
blanksBeforeWith held ps =
  let capacity = maximum (1 : map poLines ps)
   in [ (map fst bs, foldl' (\a (_, n) -> min capacity (a + min capacity n)) 0 bs, b)
      | (ws, b) <- held,
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
p3BlankNoOverflow separator sn =
  let dropped = seenDropped sn
   in [ Breach P3 ids why
      | (sps, total, b) <- seenBlanksBefore sn,
        not (any (`Map.member` dropped) sps),
        Just (_, k, p) <- [firstSlotOf (seenSlots sn) b],
        let ids = blockIds b
            start = maybe 0 fst (listToMaybe (drop k (poSlots p)))
            before = endBefore (seenExtent sn) p k
            used = maximum (0 : [at + seenExtent sn s | (at, s) <- poSlots p])
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
p4BlankWithNext sn@Seen {seenFlows = flows} =
  let dropped = seenDropped sn
      written = [sp | FBlank sp _ <- flows]
      judged =
        [ Breach P4 ids why
        | (sps, total, b) <- seenBlanksBefore sn,
          Just (_, k, p) <- [firstSlotOf (seenSlots sn) b],
          let ids = blockIds b
              counts = map (\sp -> Map.findWithDefault 0 sp dropped) sps
              start = maybe 0 fst (listToMaybe (drop k (poSlots p)))
              at = "page " <> show (poNumber p) <> " column " <> show (poColumn p),
          why <-
            if all (== 1) counts
              then ["the blank lines are dropped, and their block is after slot " <> show k <> " of " <> at | k > 0]
              else
                if all (== 0) counts
                  then ["the blank lines are not in the column of their block, " <> at | start - endBefore (seenExtent sn) p k < total]
                  else ["the blank lines are recorded as dropped " <> show counts <> " times"]
        ]
      stray = [Breach P4 [] ("a blank line at " <> show sp <> " not written is recorded as dropped") | sp <- Map.keys dropped, sp `notElem` written]
   in judged <> stray

{- | P5 (golem-layout ADR 0026): blank lines with no next block, nothing
but figures that wait after them to the end of the book, are placed in
no column: each @blank-line is recorded once as dropped.
-}
p5BlankBeforeWaiting :: Check
p5BlankBeforeWaiting sn =
  let dropped = seenDropped sn
      (_, left) = seenWaitingAndLeft sn
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
p9SpaceMoved :: ([Flow] -> [PageOut]) -> [Flow] -> [PageOut] -> [Breach]
p9SpaceMoved lay flows ps = p9Of (spaceMovedLaid lay (seen flows ps))

-- | 'p9SpaceMoved' of the inputs laid out again ('spaceMovedLaid').
p9Of :: ([(Int, [Flow], [OutShape])], Seen) -> [Breach]
p9Of (laid, s) =
  [ Breach P9 [] ("the space at flow " <> show k <> " moved after the need-lines after it lays out " <> show moved <> ", not " <> show here)
  | (k, _, moved) <- laid,
    moved /= here
  ]
  where
    here = outShape (seenOut s)

{- | Each input 'spacesMoved' makes, with the slots and records it lays
out: P9 and W3 read the same inputs, laid out once for both.
-}
spaceMovedLaid :: ([Flow] -> [PageOut]) -> Seen -> ([(Int, [Flow], [OutShape])], Seen)
spaceMovedLaid lay s = ([(k, swapped, outShape (lay swapped)) | (k, swapped) <- spacesMoved (seenWaitingFigures s) (seenFlows s)], s)

{- | W3 of golem-layout ADR 0044, its section 「不変条件」: for each input
P9 (P9′ of golem-layout ADR 0047) lays out again, with the space moved after the need-lines, that lays
out the same, 'waitingFigures' reads the same figures from the two
inputs and the one output.
-}
w3WaitingAlike :: ([Flow] -> [PageOut]) -> [Flow] -> [PageOut] -> [Breach]
w3WaitingAlike lay flows ps = w3Of (spaceMovedLaid lay (seen flows ps))

-- | 'w3WaitingAlike' of the inputs laid out again ('spaceMovedLaid').
w3Of :: ([(Int, [Flow], [OutShape])], Seen) -> [Breach]
w3Of (laid, s) =
  [ Breach W3 (here <> there) ("the space at flow " <> show k <> " moved after the need-lines after it lays out the same, and the figures that wait are read as " <> show there <> ", not " <> show here)
  | (k, swapped, moved) <- laid,
    moved == outShape (seenOut s),
    let there = waitingFigures swapped (seenOut s),
    there /= here
  ]
  where
    here = seenWaitingFigures s

-- | The slots and records of a column, P9 compares.
type OutShape = (Int, Int, [(Int, Slotted)], [Unmet])

-- | The slots and records of every column, P9 compares.
outShape :: [PageOut] -> [OutShape]
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
p11WaitingBeforeSpace :: ([Flow] -> [PageOut]) -> [Flow] -> [PageOut] -> [Breach]
p11WaitingBeforeSpace lay flows ps = p11Of lay (seen flows ps)

-- | 'p11WaitingBeforeSpace' of an input read through 'Seen'.
p11Of :: ([Flow] -> [PageOut]) -> Seen -> [Breach]
p11Of lay s =
  [ Breach P11 ids ("the figures that wait " <> show ids <> " written before the space at flow " <> show k <> " lay out " <> show moved <> ", not " <> show here)
  | (k, ids, swapped) <- waitingMovedBefore (seenWaitingFigures s) (seenFlows s),
    let here = withoutFigures ids (outShape (seenOut s))
        moved = withoutFigures ids (outShape (lay swapped)),
    moved /= here
  ]
  where
    withoutFigures ids = map (\(n, c, sl, u) -> (n, c, [x | x@(_, sl') <- sl, not (any (\i -> sl' == SFigure i || sl' == SPageFigure i) ids)], u))

{- | The breaches of P9, W3 and P11, in that order, of an input read
through 'Seen': the inputs P9 and W3 lay out again are laid out once.
-}
movedBreaches :: ([Flow] -> [PageOut]) -> Seen -> [Breach]
movedBreaches lay s = let laid = spaceMovedLaid lay s in p9Of laid <> w3Of laid <> p11Of lay s

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
  FSection {} -> True
  FNoBreak _ -> True
  FAdjustLines _ _ -> True
  _ -> False

-- boxes (docs/adr/0271)

-- | The boxes of a flow: id, grid lines before and after, and the ids of their lines.
inputBoxes :: [Flow] -> [(Int, Int, Int, [Int])]
inputBoxes flows = [(i, kb, ka, map lbId (concatMap flowLines body)) | FBoxed i kb ka body <- flows]

-- | The grid lines of the lines of a box in a column.
boxLinesIn :: [Int] -> PageOut -> [Int]
boxLinesIn ids p = [g | (g, SLine i) <- poSlots p, i `elem` ids]

{- | B1: the first grid line of a part of a box is k before the grid line
of the first line of the box in its column, and the last k after that of
the last.
-}
b1BoxShape :: Check
b1BoxShape sn@Seen {seenFlows = flows} =
  [ Breach B1 [i] ("part " <> show (bsFirst seg, bsLast seg) <> " of box " <> show i <> " on page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " has its lines on " <> show gs)
  | (i, kb, ka, ids) <- inputBoxes flows,
    p <- seenOrdered sn,
    seg <- poBoxes p,
    bsBox seg == i,
    let gs = boxLinesIn ids p,
    not (null gs),
    bsFirst seg /= minimum gs - kb || bsLast seg /= maximum gs + ka
  ]

{- | B2: the grid lines placed in a column, the grid lines of the parts of
boxes included, the lines of its notes and the separator, if it has
notes, do not exceed its grid lines: I2 with the grid lines of boxes.
-}
b2BoxNoOverflow :: Int -> Check
b2BoxNoOverflow separator sn =
  let extent = seenExtent sn
      tall p = or [True | TallHeading {} <- poUnmet p]
   in [ Breach B2 (concatMap (slotLines . snd) (poSlots p)) ("page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " uses " <> show total <> " of " <> show (poLines p) <> " grid lines with its boxes")
      | p <- seenOrdered sn,
        not (poBlank p),
        not (null (poBoxes p)),
        let used = maximum (0 : [k + extent s | (k, s) <- poSlots p] <> [bsLast b + 1 | b <- poBoxes p])
            notes = sum [n | (_, _, n) <- poFootnotes p]
            total = used + notes + (if null (poFootnotes p) then 0 else separator),
        total > poLines p,
        not (tall p)
      ]

{- | B3: every part of a box holds a line of the box, and every line of a
box is in exactly one part of it.
-}
b3BoxParts :: Check
b3BoxParts sn@Seen {seenFlows = flows} =
  [ Breach B3 [i] ("part " <> show (bsFirst seg, bsLast seg) <> " of box " <> show i <> " on page " <> show (poNumber p) <> " column " <> show (poColumn p) <> " holds no line of it")
  | (i, _, _, ids) <- inputBoxes flows,
    p <- seenOrdered sn,
    seg <- poBoxes p,
    bsBox seg == i,
    null [g | g <- boxLinesIn ids p, g >= bsFirst seg, g <= bsLast seg]
  ]
    <> [ Breach B3 [i, l] ("line " <> show l <> " of box " <> show i <> " is in " <> show n <> " parts of it")
       | (i, _, _, ids) <- inputBoxes flows,
         p <- seenOrdered sn,
         (g, SLine l) <- poSlots p,
         l `elem` ids,
         let n = length [() | seg <- poBoxes p, bsBox seg == i, g >= bsFirst seg, g <= bsLast seg],
         n /= 1
       ]
