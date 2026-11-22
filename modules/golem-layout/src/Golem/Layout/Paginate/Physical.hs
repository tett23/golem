{- | Pagination in integer sp without snapping positions to the line grid
(root ADR 0397). The grid paginator remains a separate implementation.
-}
module Golem.Layout.Paginate.Physical
  ( PhysicalSettings (..),
    PhysicalFailure (..),
    paginatePhysical,
    PhysicalCursor,
    PhysicalPart (..),
    PhysicalWrap (..),
    startPhysicalCursor,
    physicalCursorPosition,
    physicalCursorIsEmpty,
    finishPhysicalUnit,
    recordPhysicalUnmet,
    keepPhysicalNext,
    fitsPhysicalFollowing,
    physicalFollowingRows,
    physicalParagraphOrigin,
    movePhysicalCursor,
    stepPhysicalCursor,
    stepPhysicalPrefix,
    physicalKeepAhead,
    finishPhysicalCursor,
    beginPhysicalWrap,
    beginPhysicalWrapAfter,
    endPhysicalWrap,
    trialParagraphPart,
    trialParagraphPartLimit,
  )
where

import Control.Applicative ((<|>))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text qualified
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry, codeSpan)
import Golem.Layout.FreeGeometry (boxExtras, faceOffset, ruleAfterEdge, ruleAfterGap, ruleBeforeEdge, ruleBeforeGap, rulesSharedGap)
import Golem.Layout.Paginate.Decide qualified as Decide
import Golem.Layout.Paginate.Types
import Golem.Layout.RuleArea (RuleSide (..))
import Golem.Length (Sp (..))
import Golem.Syntax qualified

{- | Page geometry and resolved body line pitches. A missing pitch uses the
page pitch. All lengths, including the separator, are integer sp.
-}
data PhysicalSettings = PhysicalSettings
  { physicalPagePitch :: !Sp,
    physicalFontSize :: !Sp,
    physicalCapacity :: !Sp,
    physicalMaxCapacity :: !Sp,
    physicalSeparator :: !Sp,
    physicalColumns :: !(ColumnSetAt Sp),
    physicalPitches :: !(Map Int Sp),
    physicalFaces :: !(Map Int Sp),
    physicalBoxPadding :: !(Map Int Sp),
    physicalWrappedBefore :: !(Map Int Sp),
    physicalHeadingBounds :: !(Map Int (Sp, Sp))
  }

data PhysicalFailure
  = PhysicalLineTooTall !Int
  | PhysicalFootnoteTooTall !NoteId
  | PhysicalHeadingTooTall !Int
  | PhysicalTableTooTall !Int
  | PhysicalTableCaptionTooTall !Int
  | PhysicalCodeTooTall !Int
  | PhysicalBoxTooTall !Int
  | PhysicalFigureTooTall !Int
  deriving stock (Eq, Show)

data PhysicalState = PhysicalState
  { psPage :: !Int,
    psColumn :: !Int,
    psSet :: !(ColumnSetAt Sp),
    psUsed :: !Sp,
    psNotesUsed :: !Sp,
    psSlots :: ![(Sp, Slotted)],
    psNotes :: ![(NoteId, Int, Int)],
    psCarry :: ![(NoteId, Int, Int)],
    psDeferred :: ![(Int, Sp, [Data.Text.Text], [Golem.Syntax.SrcSpan])],
    psLabels :: ![Data.Text.Text],
    psMarks :: ![Golem.Syntax.SrcSpan],
    psDone :: ![PageOutAt Sp],
    psAdjustment :: !Sp,
    psUnmet :: ![Unmet],
    psPendingSpace :: !Sp,
    psBlankActive :: !Bool,
    psBlankSpans :: ![Golem.Syntax.SrcSpan],
    psTables :: ![TableSegmentAt Sp],
    psBoxes :: ![BoxSegmentAt Sp],
    psRules :: ![PlacedRule],
    psJoin :: !(Maybe (Int, RuleSide, LineBox, Sp)),
    psWaits :: ![(Unmet, Int, Int, Int, Int, Bool)],
    psSections :: ![(Int, Int)]
  }

{- | A complete, immutable placement snapshot, including notes, labels,
marks, diagnostics, deferred figures and the columns already closed.
-}
newtype PhysicalCursor = PhysicalCursor PhysicalState

data PhysicalPart
  = PhysicalMoved !PhysicalCursor !Keep
  | PhysicalPlaced !Int !PhysicalCursor !Keep

-- | An exclusion exists only in its original physical column.
data PhysicalWrap = PhysicalWrap !Int !Int !Sp
  deriving stock (Eq, Show)

startPhysicalCursor :: PhysicalSettings -> PhysicalCursor
startPhysicalCursor = PhysicalCursor . initial

physicalCursorPosition :: PhysicalCursor -> (Int, Int, Sp)
physicalCursorPosition (PhysicalCursor st) = (psPage st, psColumn st, psUsed st)

physicalCursorIsEmpty :: PhysicalCursor -> Bool
physicalCursorIsEmpty (PhysicalCursor st) = empty st

finishPhysicalUnit :: PhysicalCursor -> PhysicalCursor
finishPhysicalUnit (PhysicalCursor st) = PhysicalCursor (checkWaits st)

recordPhysicalUnmet :: [Unmet] -> PhysicalCursor -> PhysicalCursor
recordPhysicalUnmet problems (PhysicalCursor st) = PhysicalCursor st {psUnmet = psUnmet st <> problems}

keepPhysicalNext :: Golem.Syntax.SrcSpan -> Int -> Bool -> PhysicalCursor -> PhysicalCursor
keepPhysicalNext span' wanted linesOnly (PhysicalCursor st) = PhysicalCursor (waitForPrior (UnmetKeepNext span') (max 1 wanted, linesOnly) st)

physicalFollowingRows :: Int -> [FlowAt Sp] -> (Int, Bool)
physicalFollowingRows = followingRows

fitsPhysicalFollowing :: PhysicalSettings -> PhysicalCursor -> Int -> [FlowAt Sp] -> Bool
fitsPhysicalFollowing cfg (PhysicalCursor st) = fitsFollowing cfg st

physicalParagraphOrigin :: PhysicalCursor -> Sp
physicalParagraphOrigin (PhysicalCursor st) = psUsed st + if empty st then 0 else psPendingSpace st

activeWrapEnd :: Maybe PhysicalWrap -> PhysicalState -> Sp
activeWrapEnd (Just (PhysicalWrap page column end)) st
  | (page, column) == (psPage st, psColumn st) = end
activeWrapEnd _ _ = 0

endPhysicalWrap :: Maybe PhysicalWrap -> PhysicalCursor -> PhysicalCursor
endPhysicalWrap region (PhysicalCursor st) = PhysicalCursor st {psUsed = max (psUsed st) (activeWrapEnd region st)}

movePhysicalCursor :: PhysicalSettings -> Maybe PhysicalWrap -> PhysicalCursor -> PhysicalCursor
movePhysicalCursor cfg region cursor = case endPhysicalWrap region cursor of
  PhysicalCursor st -> PhysicalCursor (nextColumn cfg st)

stepPhysicalCursor :: PhysicalSettings -> PhysicalCursor -> [FlowAt Sp] -> Either PhysicalFailure PhysicalCursor
stepPhysicalCursor cfg (PhysicalCursor st) flows = do
  checkPhysicalNotes cfg flows
  PhysicalCursor <$> placeAll cfg st flows

{- | Place a prefix with actual, newly composed lookahead, without placing
that lookahead or retaining any effects of its hypothetical placement.
-}
stepPhysicalPrefix :: PhysicalSettings -> PhysicalCursor -> [FlowAt Sp] -> [FlowAt Sp] -> Either PhysicalFailure PhysicalCursor
stepPhysicalPrefix cfg (PhysicalCursor st0) prefix following = do
  checkPhysicalNotes cfg prefix
  PhysicalCursor <$> go st0 prefix
  where
    go st [] = Right st
    go st (flow : rest) = do
      next <- placeNext cfg st flow (rest <> following)
      go next rest

physicalKeepAhead :: [FlowAt Sp] -> Maybe (Int, Int, [FlowAt Sp])
physicalKeepAhead = keepAhead

beginPhysicalWrap :: PhysicalSettings -> PhysicalCursor -> Int -> Sp -> [Data.Text.Text] -> [Golem.Syntax.SrcSpan] -> Either PhysicalFailure (PhysicalCursor, PhysicalWrap)
beginPhysicalWrap cfg (PhysicalCursor st) ident extent labels marks
  | extent > physicalCapacity cfg = Left (PhysicalFigureTooTall ident)
  | otherwise =
      let ready = fit cfg st extent
          start = psUsed ready
       in Right (PhysicalCursor (checkWaits (putSlot ready 0 (SWrapped ident) labels marks)), PhysicalWrap (psPage ready) (psColumn ready) (start + extent))

{- | Resolve the preceding holding group with the figure as its lookahead,
then open the exclusion at the exact committed anchor. The placeholder
is inspected by keep calculations but never placed twice.
-}
beginPhysicalWrapAfter :: PhysicalSettings -> PhysicalCursor -> [FlowAt Sp] -> Int -> Sp -> [Data.Text.Text] -> [Golem.Syntax.SrcSpan] -> Either PhysicalFailure (PhysicalCursor, PhysicalWrap)
beginPhysicalWrapAfter cfg (PhysicalCursor initialState) prefix ident extent labels marks = do
  checkPhysicalNotes cfg prefix
  go initialState (prefix <> [FWrapped ident extent labels marks []])
  where
    go st [] = beginPhysicalWrap cfg (PhysicalCursor st) ident extent labels marks
    go st [_] = beginPhysicalWrap cfg (PhysicalCursor st) ident extent labels marks
    go st (flow : rest) = do
      next <- placeNext cfg st flow rest
      go next rest

finishPhysicalCursor :: PhysicalSettings -> PhysicalCursor -> [PageOutAt Sp]
finishPhysicalCursor cfg (PhysicalCursor st) =
  let closed = close cfg (drainCarry cfg st)
   in case reverse (psDone closed) of
        [] -> [PageOut 1 0 False [] [] [] [] [] (physicalColumns cfg) [] (physicalCapacity cfg) [] [] []]
        pages -> decorateSections (psSections closed) pages

initial :: PhysicalSettings -> PhysicalState
initial cfg = PhysicalState 1 0 (physicalColumns cfg) 0 0 [] [] [] [] [] [] [] 0 [] 0 False [] [] [] [] Nothing [] []

limit :: PhysicalSettings -> PhysicalState -> Sp
limit cfg st = physicalCapacity cfg + psAdjustment st

room :: PhysicalSettings -> PhysicalState -> Sp
room cfg st = limit cfg st - psUsed st - psNotesUsed st

empty :: PhysicalState -> Bool
empty st = null (psSlots st) && null (psNotes st) && psUsed st == csFirstLine (psSet st)

pitchOf :: PhysicalSettings -> LineBox -> Sp
pitchOf cfg line = Map.findWithDefault (physicalPagePitch cfg) (lbId line) (physicalPitches cfg)

-- A heading is allowed to occupy the top of an otherwise empty column
-- without making an impossible paragraph keep orphan the heading.
headingOnly :: PhysicalState -> Bool
headingOnly st = not (null (psSlots st)) && all (\case (_, SHeading {}) -> True; _ -> False) (psSlots st)

faceOf :: PhysicalSettings -> LineBox -> Sp
faceOf cfg line = Map.findWithDefault (physicalFontSize cfg) (lbId line) (physicalFaces cfg)

-- | A closed page records the physical start of each occupied box.
close :: PhysicalSettings -> PhysicalState -> PhysicalState
close cfg st
  | null (psSlots st) && null (psNotes st) = st
  | otherwise = st {psDone = page : psDone st, psUnmet = []}
  where
    page = PageOut (psPage st) (psColumn st) False (psSlots st) (psNotes st) (psLabels st) (psMarks st) (psTables st) (psSet st) (psRules st) (limit cfg st) (psUnmet st) [] (psBoxes st)

nextColumn :: PhysicalSettings -> PhysicalState -> PhysicalState
nextColumn cfg st =
  let closed = close cfg st
      pageEnd = psColumn st + 1 >= csColumns (psSet st)
      newSet = if pageEnd then (psSet st) {csFirstLine = 0} else psSet st
      fresh =
        closed
          { psPage = psPage st + if pageEnd then 1 else 0,
            psColumn = if pageEnd then 0 else psColumn st + 1,
            psSet = newSet,
            psUsed = csFirstLine newSet,
            psNotesUsed = 0,
            psSlots = [],
            psNotes = [],
            psLabels = [],
            psMarks = [],
            psAdjustment = 0,
            psPendingSpace = 0,
            psBlankActive = False,
            psTables = [],
            psBoxes = [],
            psRules = [],
            psJoin = Nothing
          }
   in carryInto cfg (placeDeferred cfg fresh)

nextPage :: PhysicalSettings -> PhysicalState -> PhysicalState
nextPage cfg st =
  let s = close cfg st
      set = (psSet st) {csFirstLine = 0}
   in carryInto cfg (placeDeferred cfg (s {psPage = psPage st + 1, psColumn = 0, psSet = set, psUsed = 0, psNotesUsed = 0, psSlots = [], psNotes = [], psLabels = [], psMarks = [], psAdjustment = 0, psPendingSpace = 0, psBlankActive = False, psTables = [], psBoxes = [], psRules = [], psJoin = Nothing}))

placeDeferred :: PhysicalSettings -> PhysicalState -> PhysicalState
placeDeferred cfg st = case psDeferred st of
  [] -> st
  (ident, extent, labels, marks) : later
    | extent <= room cfg st -> placeDeferred cfg ((putSlot st extent (SFigure ident) labels marks) {psDeferred = later})
  _ -> st

carryInto :: PhysicalSettings -> PhysicalState -> PhysicalState
carryInto cfg st
  | null (psCarry st) = st
  | otherwise =
      let available = limit cfg st - psUsed st - physicalSeparator cfg
          count = max 0 (fromInteger (unSp available `div` unSp (physicalPagePitch cfg)))
          (shown, remaining) = splitCarried count (psCarry st)
          extent = physicalSeparator cfg + fromIntegral (sum [n | (_, _, n) <- shown]) * physicalPagePitch cfg
       in st {psNotes = shown, psCarry = remaining, psNotesUsed = if null shown then 0 else extent}

splitCarried :: Int -> [(NoteId, Int, Int)] -> ([(NoteId, Int, Int)], [(NoteId, Int, Int)])
splitCarried _ [] = ([], [])
splitCarried room' allNotes@((ident, offset, count) : rest)
  | room' <= 0 = ([], allNotes)
  | count <= room' = let (a, b) = splitCarried (room' - count) rest in ((ident, offset, count) : a, b)
  | otherwise = ([(ident, offset, room')], (ident, offset + room', count - room') : rest)

{- | Move a pending boundary space together with its next block. If it does
not fit, the new column starts with the block and drops that space.
-}
fit :: PhysicalSettings -> PhysicalState -> Sp -> PhysicalState
fit cfg st amount
  | empty st && amount <= room cfg st = dropAtTop st
  | empty st && psAdjustment st < 0 = dropAtTop (nextColumn cfg st)
  | amount + psPendingSpace st <= room cfg st = st {psUsed = psUsed st + psPendingSpace st, psPendingSpace = 0, psBlankActive = False, psBlankSpans = []}
  | empty st = dropAtTop st
  | otherwise = dropAtTop (nextColumn cfg st)
  where
    dropAtTop current = current {psPendingSpace = 0, psBlankActive = False, psBlankSpans = [], psUnmet = psUnmet current <> map DroppedBlank (psBlankSpans current)}

putSlot :: PhysicalState -> Sp -> Slotted -> [Data.Text.Text] -> [Golem.Syntax.SrcSpan] -> PhysicalState
putSlot st extent slot labels marks =
  st {psSlots = psSlots st <> [(psUsed st, slot)], psUsed = psUsed st + extent, psLabels = psLabels st <> labels, psMarks = psMarks st <> marks}

{- | The first line of a note must reserve its separator once. A note's
unplaced suffix remains in line counts so its continuation is exact.
-}
putLine :: PhysicalSettings -> PhysicalState -> LineBox -> Either PhysicalFailure PhysicalState
putLine = putLineWithReserve False

putLineWithReserve :: Bool -> PhysicalSettings -> PhysicalState -> LineBox -> Either PhysicalFailure PhysicalState
putLineWithReserve allowNoteContinuation cfg st line = do
  let pitch = pitchOf cfg line
      notes = lbNotes line
      noteCount = sum (map nbLines notes)
      separator = if noteCount > 0 && psNotesUsed st == 0 then physicalSeparator cfg else 0
      available = limit cfg st - psUsed st - pitch - psNotesUsed st - separator
      noteRoom = max 0 (fromIntegral (max 0 (unSp available `div` unSp (physicalPagePitch cfg))))
      (shown, carry) = splitNotes noteRoom notes
      shownCount = sum [n | (_, _, n) <- shown]
      noteLength = fromIntegral shownCount * physicalPagePitch cfg
  if pitch > physicalCapacity cfg
    then Left (PhysicalLineTooTall (lbId line))
    else
      if noteCount > 0 && null shown && empty st && not allowNoteContinuation && pitch + separator + physicalPagePitch cfg > limit cfg st
        then case notes of
          firstNote : _ -> Left (PhysicalFootnoteTooTall (nbId firstNote))
          [] -> Right st
        else
          Right
            ( (putSlot st pitch (SLine (lbId line)) (lbLabels line) (lbMarks line))
                { psNotesUsed = psNotesUsed st + (if null shown then 0 else separator) + noteLength,
                  psNotes = psNotes st <> shown,
                  psCarry = psCarry st <> carry
                }
            )

splitNotes :: Int -> [NoteBody] -> ([(NoteId, Int, Int)], [(NoteId, Int, Int)])
splitNotes = go
  where
    go _ [] = ([], [])
    go capacity (NoteBody ident count : rest)
      | count <= capacity = let (a, b) = go (capacity - count) rest in ((ident, 0, count) : a, b)
      | capacity > 0 = ([(ident, 0, capacity)], (ident, capacity, count - capacity) : [(nbId x, 0, nbLines x) | x <- rest])
      | otherwise = ([], (ident, 0, count) : [(nbId x, 0, nbLines x) | x <- rest])

-- | Number of consecutive lines whose boxes and newly referenced notes fit.
fitting :: PhysicalSettings -> PhysicalState -> [LineBox] -> Int
fitting cfg st = length . takeWhile id . snd . foldl' step ((psUsed st + if empty st then 0 else psPendingSpace st, psNotesUsed st), [])
  where
    step ((used, notesUsed), oks) line =
      let pitch = pitchOf cfg line
          notes = sum (map nbLines (lbNotes line))
          sep = if notes > 0 && notesUsed == 0 then physicalSeparator cfg else 0
          used' = used + pitch
          notes' = notesUsed + sep + fromIntegral notes * physicalPagePitch cfg
          ok = used' + notes' <= limit cfg st && (null oks || last oks)
       in ((used', notes'), oks <> [ok])

fittingWrapped :: PhysicalSettings -> PhysicalState -> Sp -> [LineBox] -> Int
fittingWrapped cfg st figureEnd = length . takeWhile id . snd . foldl' step ((psUsed st, psNotesUsed st), [])
  where
    step ((used, notesUsed), oks) line =
      let gap = Map.findWithDefault 0 (lbId line) (physicalWrappedBefore cfg)
          notes = sum (map nbLines (lbNotes line))
          separator = if notes > 0 && notesUsed == 0 then physicalSeparator cfg else 0
          used' = used + gap + pitchOf cfg line
          available = limit cfg st - max figureEnd used' - notesUsed - separator
          fittingNotes = max 0 (min notes (fromInteger (unSp available `div` unSp (physicalPagePitch cfg))))
          notes' = notesUsed + (if fittingNotes == 0 then 0 else separator + fromIntegral fittingNotes * physicalPagePitch cfg)
          ok = max figureEnd used' + notesUsed + (if notes > 0 then separator + physicalPagePitch cfg else 0) <= limit cfg st && (null oks || last oks)
       in ((used', notes'), oks <> [ok])

putWrappedLine :: PhysicalSettings -> Sp -> PhysicalState -> LineBox -> Either PhysicalFailure PhysicalState
putWrappedLine cfg figureEnd st line = do
  let reserve = max 0 (figureEnd - psUsed st - pitchOf cfg line)
      adjusted = st {psAdjustment = psAdjustment st - reserve}
  placed <- putLine cfg adjusted line
  pure placed {psAdjustment = psAdjustment st}

placeWrappedOverflow :: PhysicalSettings -> PhysicalState -> [LineBox] -> Either PhysicalFailure PhysicalState
placeWrappedOverflow _ st [] = Right st
placeWrappedOverflow cfg st (line : rest) = do
  let gap = if empty st then 0 else Map.findWithDefault 0 (lbId line) (physicalWrappedBefore cfg)
      withGap = st {psPendingSpace = psPendingSpace st + gap}
      ready = if fitting cfg withGap [line] == 0 && not (empty st) then nextColumn cfg st else st
      readyGap = ready {psPendingSpace = psPendingSpace ready + if empty ready then 0 else gap}
      atLine = fit cfg readyGap (pitchOf cfg line)
  placed <- putLine cfg atLine line
  placeWrappedOverflow cfg placed rest

splitAtBreak :: Keep -> Bool -> Int -> Int -> Int
splitAtBreak keep isStart total count
  | count >= total = count
  | kAll keep = 0
  | otherwise =
      let widow = if total - count < kLast keep then max 0 (total - kLast keep) else count
       in if isStart && widow > 0 && widow < kFirst keep then 0 else widow

{- | A verse line is kept whole when it fits; the keep counts verse lines,
rather than the wrapped display rows inside each verse line.
-}
placeStanza :: PhysicalSettings -> Keep -> PhysicalState -> [[LineBox]] -> Either PhysicalFailure PhysicalState
placeStanza cfg keep0 = go keep0 True
  where
    go _ _ st [] = Right st
    go keep start st verses@(firstVerse : remainingVerses) = do
      let count = fitting cfg st (concat verses)
          whole = length (takeWhile (<= count) (drop 1 (scanl (+) 0 (map length verses))))
          selected = splitAtBreak keep start (length verses) whole
          emptyish = empty st || (headingOnly st && count > 0)
      if kAll keep && start && whole < length verses
        then
          if empty st || headingOnly st
            then go (keep {kAll = False}) start (st {psUnmet = psUnmet st <> [SplitKept (maybe 0 lbId (safeHead firstVerse))]}) verses
            else go keep start (nextColumn cfg st) verses
        else
          if selected == 0 && not emptyish
            then go keep start (nextColumn cfg st) verses
            else
              if selected == 0 && whole > 0
                then do
                  let firstId = maybe 0 lbId (safeHead firstVerse)
                      short =
                        [ShortPart FirstPart firstId (kFirst keep) whole | start, whole < kFirst keep]
                          <> [ShortPart LastPart firstId (kLast keep) (length verses - whole) | length verses - whole < kLast keep]
                  placed <- placeLines cfg defaultKeep start st (concat (take whole verses))
                  let warned = placed {psUnmet = psUnmet placed <> short}
                  if whole == length verses
                    then Right warned
                    else go keep False (nextColumn cfg warned) (drop whole verses)
                else
                  if selected == 0
                    then do
                      placed <- placeLines cfg defaultKeep True st firstVerse
                      go keep False placed remainingVerses
                    else do
                      placed <- placeLines cfg (Keep 1 1 False) start st (concat (take selected verses))
                      if selected == length verses
                        then Right placed
                        else go keep False (nextColumn cfg placed) (drop selected verses)

{- | Trial only the next part. A caller may rebreak the unconsumed source
items after a move, using the new physical column's available width.
-}
trialParagraphPart :: PhysicalSettings -> Maybe PhysicalWrap -> Keep -> Bool -> PhysicalCursor -> [LineBox] -> Either PhysicalFailure PhysicalPart
trialParagraphPart cfg region = trialParagraphPartLimit cfg region Nothing

{- | A finite local prefix restriction lets the composer retain a widow
after the remaining source is rebroken at a wider column. The ordinary
paginator passes no restriction and retains its original decisions.
-}
trialParagraphPartLimit :: PhysicalSettings -> Maybe PhysicalWrap -> Maybe Int -> Keep -> Bool -> PhysicalCursor -> [LineBox] -> Either PhysicalFailure PhysicalPart
trialParagraphPartLimit cfg region prefixLimit keep0 start0 cursor0 rows0 = do
  checkPhysicalNotes cfg [FParagraph keep0 rows0]
  go keep0 start0 cursor0 rows0
  where
    fittingHere st rows
      | activeWrapEnd region st == 0 = fitting cfg st rows
      | otherwise =
          let end = activeWrapEnd region st
              step ((used, notesUsed), oks) line =
                let used' = used + pitchOf cfg line
                    notes = sum (map nbLines (lbNotes line))
                    separator = if notes > 0 && notesUsed == 0 then physicalSeparator cfg else 0
                    notes' = notesUsed + separator + fromIntegral notes * physicalPagePitch cfg
                    ok = max end used' + notes' <= limit cfg st && (null oks || last oks)
                 in ((used', notes'), oks <> [ok])
           in length (takeWhile id (snd (foldl' step ((psUsed st + if empty st then 0 else psPendingSpace st, psNotesUsed st), []) rows)))
    go keep _ cursor [] = Right (PhysicalPlaced 0 cursor keep)
    go keep start cursor@(PhysicalCursor st) rows@(firstLine : _) = do
      let total = length rows
          count = fittingHere st rows
          selected = maybe id min prefixLimit (splitAtBreak keep start total count)
          emptyish = empty st || (headingOnly st && count > 0)
          move = Right (PhysicalMoved (movePhysicalCursor cfg region cursor) keep)
      if pitchOf cfg firstLine > physicalCapacity cfg
        then Left (PhysicalLineTooTall (lbId firstLine))
        else
          if kAll keep && start && count < total
            then
              if empty st || headingOnly st
                then go (keep {kAll = False}) start (PhysicalCursor st {psUnmet = psUnmet st <> [SplitKept (lbId firstLine)]}) rows
                else move
            else
              if (empty st && psAdjustment st < 0 && count == 0) || (selected == 0 && not emptyish)
                then move
                else do
                  let takeCount = if selected == 0 then max 1 count else selected
                      here = take takeCount rows
                      forced = selected == 0 && emptyish && takeCount < total
                      short =
                        [ShortPart FirstPart (lbId firstLine) (kFirst keep) takeCount | forced, start, takeCount < kFirst keep]
                          <> [ShortPart LastPart (lbId firstLine) (kLast keep) (total - takeCount) | forced, total - takeCount < kLast keep]
                      ready = fit cfg st (sum (map (pitchOf cfg) here))
                      put s line = if activeWrapEnd region s > 0 then putWrappedLine cfg (activeWrapEnd region s) s line else putLine cfg s line
                  placed <- foldl' (\acc line -> acc >>= \s -> put s line) (Right ready) here
                  Right (PhysicalPlaced takeCount (PhysicalCursor placed {psUnmet = psUnmet placed <> short}) keep)

placeLines :: PhysicalSettings -> Keep -> Bool -> PhysicalState -> [LineBox] -> Either PhysicalFailure PhysicalState
placeLines cfg keep0 start0 st0 = go keep0 start0 (PhysicalCursor st0)
  where
    go _ _ (PhysicalCursor st) [] = Right st
    go keep start cursor rows = do
      part <- trialParagraphPart cfg Nothing keep start cursor rows
      case part of
        PhysicalMoved next relaxed -> go relaxed start next rows
        PhysicalPlaced count next@(PhysicalCursor placed) relaxed ->
          if count == length rows
            then Right placed
            else go relaxed False (movePhysicalCursor cfg Nothing next) (drop count rows)

checkPhysicalNotes :: PhysicalSettings -> [FlowAt Sp] -> Either PhysicalFailure ()
checkPhysicalNotes cfg flows = do
  let impossibleNote = physicalSeparator cfg + physicalPagePitch cfg > physicalCapacity cfg
      notes = [nbId n | line <- concatMap flowLines flows, n <- lbNotes line]
  case (impossibleNote, notes) of
    (True, n : _) -> Left (PhysicalFootnoteTooTall n)
    _ -> Right ()

paginatePhysical :: PhysicalSettings -> [FlowAt Sp] -> Either PhysicalFailure [PageOutAt Sp]
paginatePhysical cfg flows = do
  checkPhysicalNotes cfg flows
  final <- placeAll cfg (initial cfg) flows
  pure (finishPhysicalCursor cfg (PhysicalCursor final))

decorateSections :: [(Int, Int)] -> [PageOutAt Sp] -> [PageOutAt Sp]
decorateSections starts = go Nothing
  where
    go _ [] = []
    go previous (page : rest)
      | previous == Just (poNumber page) = page : go previous rest
      | otherwise = page {poSections = [ident | (ident, number) <- starts, number == poNumber page]} : go (Just (poNumber page)) rest

drainCarry :: PhysicalSettings -> PhysicalState -> PhysicalState
drainCarry cfg st
  | null (psCarry st) && null (psDeferred st) = st
  | otherwise = drainCarry cfg (nextColumn cfg st)

placeAll :: PhysicalSettings -> PhysicalState -> [FlowAt Sp] -> Either PhysicalFailure PhysicalState
placeAll _ st [] = Right st
placeAll cfg st (flow : rest) = do
  next <- placeNext cfg st flow rest
  placeAll cfg next rest

placeNext :: PhysicalSettings -> PhysicalState -> FlowAt Sp -> [FlowAt Sp] -> Either PhysicalFailure PhysicalState
placeNext cfg st flow rest = do
  let boundaryNeed = min (physicalCapacity cfg) (psPendingSpace st + firstNeed cfg (psNotesUsed st > 0) 1 (flow : rest))
      afterBlank = if psBlankActive st && occupies flow && not (empty st) && boundaryNeed > room cfg st then nextColumn cfg st else st
      before = case flow of
        FRuled {} -> afterBlank
        _ -> afterBlank {psJoin = Nothing}
  placed <- case (flow, keepAhead rest) of
    (FParagraph keep lines', Just (lastCount, firstCount, later)) -> placeWithNext cfg keep True before lines' lastCount firstCount later
    (FContinued keep lines', Just (lastCount, firstCount, later)) -> placeWithNext cfg keep False before lines' lastCount firstCount later
    (FStanza keep verses, Just (lastCount, firstCount, later)) -> placeStanzaWithNext cfg keep before verses lastCount firstCount later
    (FNoBreak span', _) -> Right (waitForPrior (UnmetNoBreak span') (followingRows 0 rest) before)
    (FNoBreakLines span' n, _) | n > 0 -> Right (waitForPrior (UnmetNoBreak span') (followingRows 0 rest) before)
    (FKeepNext span' n, _) -> Right (waitForPrior (UnmetKeepNext span') (followingRows n rest) before)
    (FDefTerm lines', _) ->
      let extent = sum (map (pitchOf cfg) lines')
          ready = keepFollowing cfg False before extent lines' rest
       in placeLines cfg defaultKeep True ready lines'
    (FHeading _ recto extent lines', _) ->
      let ready = if recto then parityStart cfg odd before else keepFollowing cfg True before extent lines' rest
       in placeHeading cfg ready (maybe 0 lbId (safeHead lines')) extent lines'
    (ruled@FRuled {}, _) -> placeRuledKeeping cfg before ruled rest
    _ -> placeFlow cfg before flow
  pure (if occupies flow then checkWaits placed else placed)

occupies :: FlowAt Sp -> Bool
occupies = \case
  FParagraph {} -> True
  FContinued {} -> True
  FStanza {} -> True
  FDefTerm {} -> True
  FHeading {} -> True
  FFigure {} -> True
  FWrapped {} -> True
  FPageFigure {} -> True
  FTable {} -> True
  FCode {} -> True
  FRuled {} -> True
  FBoxed {} -> True
  _ -> False

checkWaits :: PhysicalState -> PhysicalState
checkWaits st = foldl' check (st {psWaits = []}) (psWaits st)
  where
    check acc (unmet, page, column, priorSlots, required, linesOnly) =
      let current = psPage acc == page && psColumn acc == column
          added slots = sum [case slot of SLine {} -> 1; SHeading _ n -> max 1 n; _ -> if linesOnly then 0 else 1 | (_, slot) <- drop priorSlots slots]
          inCurrent = if current then added (psSlots acc) else 0
          inDone = maximum (0 : [added (poSlots out) | out <- psDone acc, poNumber out == page, poColumn out == column])
       in if max inCurrent inDone >= max 1 required
            then acc
            else
              if current
                then acc {psUnmet = psUnmet acc <> [unmet]}
                else acc {psDone = [if poNumber out == page && poColumn out == column then out {poUnmet = poUnmet out <> [unmet]} else out | out <- psDone acc]}

followingRows :: Int -> [FlowAt Sp] -> (Int, Bool)
followingRows wanted = \case
  FParagraph keep lines' : _ -> (max (Decide.firstPart keep True (length lines')) (min wanted (length lines')), True)
  FContinued keep lines' : _ -> (max (Decide.firstPart keep False (length lines')) (min wanted (length lines')), True)
  FStanza keep verses : _ -> (length (concat (take (max (Decide.firstPart keep True (length verses)) (min wanted (length verses))) verses)), True)
  FSpace {} : rest -> followingRows wanted rest
  FNeedLines {} : rest -> followingRows wanted rest
  FAdjustLines {} : rest -> followingRows wanted rest
  FNoBreak {} : rest -> followingRows wanted rest
  FNoBreakLines {} : rest -> followingRows wanted rest
  FKeepNext {} : rest -> followingRows wanted rest
  _ -> (1, False)

keepAhead :: [FlowAt Sp] -> Maybe (Int, Int, [FlowAt Sp])
keepAhead flows = case span soft flows of
  (before, control : rest) | Just (lastCount, firstCount) <- counts control -> Just (collect before lastCount firstCount rest)
  _ -> Nothing
  where
    soft = \case
      FSpace {} -> True
      FNeedLines {} -> True
      FAdjustLines {} -> True
      FNoBreakLines _ 0 -> True
      _ -> False
    counts = \case
      FNoBreak _ -> Just (2, 0)
      FNoBreakLines _ n -> Just (n, 0)
      FKeepNext _ n -> Just (0, n)
      _ -> Nothing
    collect before lastCount firstCount rest = case span soft rest of
      (between, control : later) | Just (lastMore, firstMore) <- counts control -> collect (before <> between) (max lastCount lastMore) (max firstCount firstMore) later
      _ -> (lastCount, firstCount, before <> rest)

firstNeed :: PhysicalSettings -> Bool -> Int -> [FlowAt Sp] -> Sp
firstNeed cfg hasNotes wanted = \case
  FParagraph keep lines' : rest -> paragraphNeed keep True lines' rest
  FContinued keep lines' : rest -> paragraphNeed keep False lines' rest
  FStanza keep verses : rest ->
    let count = prefixCount keep True (length verses)
        chosen = concat (take count verses)
     in lineNeed chosen + followingNeed (count == length verses) chosen rest
  FSpace space : rest -> space + firstNeed cfg hasNotes wanted rest
  FBlank _ n : rest -> fromIntegral n * physicalPagePitch cfg + firstNeed cfg hasNotes wanted rest
  FNeedLines _ _ : rest -> firstNeed cfg hasNotes wanted rest
  FAdjustLines _ _ : rest -> firstNeed cfg hasNotes wanted rest
  FNoBreak _ : rest -> firstNeed cfg hasNotes wanted rest
  FNoBreakLines _ _ : rest -> firstNeed cfg hasNotes wanted rest
  FKeepNext _ _ : rest -> firstNeed cfg hasNotes wanted rest
  FHeading {fhRecto = True} : _ -> 0
  FHeading {fhSpan = extent, fhLines = lines'} : rest -> extent + noteNeed lines' + firstNeed cfg (hasNotes || not (all (null . lbNotes) lines')) 1 rest
  FDefTerm lines' : _ -> lineNeed lines'
  FFigure {ffLines = extent} : _ -> extent
  FWrapped {fwLines = extent} : _ -> extent
  FTable {ftSpaceBefore = before, ftHeader = header, ftRows = rows, ftCaption = caption, ftCaptionBelow = below} : _ ->
    let chosen = header <> fromMaybe [] (safeHead rows) <> (if not below || length rows <= 1 then caption else [])
        extent = before + fromIntegral (length chosen) * physicalPagePitch cfg
        complete = extent + noteNeed chosen
        noted = not (all (null . lbNotes) chosen)
        minimumNotes = if noted then physicalPagePitch cfg + (if hasNotes then 0 else physicalSeparator cfg) else 0
     in if complete <= physicalCapacity cfg then complete else extent + minimumNotes
  FCode {fcGeometry = geometry, fcCaption = caption, fcFirst = first, fcContinued = continued, fcRows = rows} : _ ->
    let count = min (length rows) (max first (max 1 wanted))
        continuation = if continued && count < length rows then 1 else 0
     in caption + fromIntegral (codeSpan geometry (count + continuation)) * physicalPagePitch cfg
  _ -> 0
  where
    prefixCount keep start total =
      case [n | n <- [max (Decide.firstPart keep start total) (min total (max 1 wanted)) .. total], splitAtBreak keep start total n == n] of
        n : _ -> n
        [] -> total
    paragraphNeed keep start lines' rest =
      let count = prefixCount keep start (length lines')
          chosen = take count lines'
       in lineNeed chosen + followingNeed (count == length lines') chosen rest
    followingNeed whole chosen rest = case (whole, keepAhead rest) of
      (True, Just (_, firstCount, later)) ->
        let withNotes = hasNotes || not (all (null . lbNotes) chosen)
         in firstNeed cfg withNotes firstCount later
      _ -> 0
    lineNeed lines' = sum (map (pitchOf cfg) lines') + noteNeed lines'
    noteNeed lines' =
      let noteCount = sum [nbLines note | line <- lines', note <- lbNotes line]
          separator = if noteCount > 0 && not hasNotes then physicalSeparator cfg else 0
       in separator + fromIntegral noteCount * physicalPagePitch cfg

-- A ruled block's added space depends on the actual preceding face. Try
-- that pure placement to judge a keep; measuring it as an edge would either
-- lose the keep or move an exactly fitting block unnecessarily.
fitsFollowing :: PhysicalSettings -> PhysicalState -> Int -> [FlowAt Sp] -> Bool
fitsFollowing cfg st wanted = go 0
  where
    go extra = \case
      FSpace space : rest -> go (extra + space) rest
      FNeedLines {} : rest -> go extra rest
      FAdjustLines {} : rest -> go extra rest
      FNoBreak {} : rest -> go extra rest
      FNoBreakLines {} : rest -> go extra rest
      FKeepNext {} : rest -> go extra rest
      FHeading {fhRecto = True} : _ -> True
      FRuled {frBody = RuledHeading True _ _} : _ -> True
      heading@FHeading {fhSpan = extent, fhLines = lines'} : rest
        | extra + psPendingSpace st + firstNeed cfg (psNotesUsed st > 0) 1 [heading] <= room cfg st ->
            case placeHeading cfg (st {psPendingSpace = psPendingSpace st + extra}) (maybe 0 lbId (safeHead lines')) extent lines' of
              Right placed -> sameColumn placed && fitsFollowing cfg placed 1 rest
              Left _ -> False
        | otherwise -> False
      ruled@FRuled {} : rest ->
        case placeRuled cfg (st {psPendingSpace = psPendingSpace st + extra}) ruled rest of
          Right placed -> sameColumn placed
          Left _ -> False
      boxed@FBoxed {} : _ ->
        case placeFlow cfg (st {psPendingSpace = psPendingSpace st + extra}) boxed of
          Right placed ->
            let prior = length (psSlots st)
             in (sameColumn placed && length (psSlots placed) > prior)
                  || any (\page -> (poNumber page, poColumn page) == (psPage st, psColumn st) && length (poSlots page) > prior) (psDone placed)
          Left _ -> False
      rest -> extra + firstNeed cfg (psNotesUsed st > 0) wanted rest <= room cfg st
    sameColumn placed = (psPage placed, psColumn placed) == (psPage st, psColumn st)

-- Keep the first usable part of the following block with a heading or
-- definition term. An empty column is the finite relaxation boundary.
keepFollowing :: PhysicalSettings -> Bool -> PhysicalState -> Sp -> [LineBox] -> [FlowAt Sp] -> PhysicalState
keepFollowing cfg heading st extent lines' later =
  let noteCount = sum [nbLines note | line <- lines', note <- lbNotes line]
      notes = fromIntegral noteCount * physicalPagePitch cfg + (if noteCount > 0 && psNotesUsed st == 0 then physicalSeparator cfg else 0)
      origin = psUsed st + psPendingSpace st
      virtualSlots =
        if heading
          then [(origin, SHeading (maybe 0 lbId (safeHead lines')) (length lines'))]
          else zip (scanl (+) origin (map (pitchOf cfg) lines')) (map (SLine . lbId) lines')
      virtual = st {psUsed = origin + extent, psNotesUsed = psNotesUsed st + notes, psSlots = psSlots st <> virtualSlots, psPendingSpace = 0}
      (wanted, following) = case keepAhead later of
        Just (_, n, rest) -> (n, rest)
        Nothing -> (1, later)
   in if not (empty st) && not (fitsFollowing cfg virtual wanted following)
        then nextColumn cfg st
        else st

placeWithNext :: PhysicalSettings -> Keep -> Bool -> PhysicalState -> [LineBox] -> Int -> Int -> [FlowAt Sp] -> Either PhysicalFailure PhysicalState
placeWithNext cfg keep start st lines' lastCount firstCount later = do
  full <- placeLines cfg keep start st lines'
  if fitsFollowing cfg full firstCount later
    then Right full
    else do
      let length' = length lines'
          requested = max lastCount (kLast keep)
          minimumFirst = if lastCount > 0 then max 2 (kFirst keep) else kFirst keep
          backCount = if kAll keep || length' <= requested || length' - requested < minimumFirst then length' else requested
          (front, back) = splitAt (length' - backCount) lines'
      if null back
        then Right full
        else do
          before <- placeLines cfg keep start st front
          let next = if empty before then before else nextColumn cfg before
          placeLines cfg keep (start && null front) next back

placeStanzaWithNext :: PhysicalSettings -> Keep -> PhysicalState -> [[LineBox]] -> Int -> Int -> [FlowAt Sp] -> Either PhysicalFailure PhysicalState
placeStanzaWithNext cfg keep st verses lastCount firstCount later = do
  full <- placeStanza cfg keep st verses
  if fitsFollowing cfg full firstCount later
    then Right full
    else do
      let total = length verses
          requested = max lastCount (kLast keep)
          backCount = if kAll keep || total <= requested || total - requested < kFirst keep then total else requested
          (front, back) = splitAt (total - backCount) verses
      before <- placeStanza cfg keep st front
      if null back || empty before
        then Right full
        else placeStanza cfg keep (nextColumn cfg before) back

placeFlow :: PhysicalSettings -> PhysicalState -> FlowAt Sp -> Either PhysicalFailure PhysicalState
placeFlow cfg st = \case
  FParagraph keep lines' -> placeLines cfg keep True st lines'
  FContinued keep lines' -> placeLines cfg keep False st lines'
  FDefTerm lines' -> placeLines cfg defaultKeep True st lines'
  FStanza keep verses -> placeStanza cfg keep st verses
  FSpace n -> Right st {psPendingSpace = if psBlankActive st then psPendingSpace st else psPendingSpace st + max 0 n}
  FBlank span' n -> Right st {psPendingSpace = (if psBlankActive st then psPendingSpace st else 0) + fromIntegral n * physicalPagePitch cfg, psBlankActive = True, psBlankSpans = psBlankSpans st <> [span' | n > 0]}
  FFigure ident extent labels marks
    | extent > physicalCapacity cfg -> Left (PhysicalFigureTooTall ident)
    | not (null (psDeferred st)) ->
        Right st {psDeferred = psDeferred st <> [(ident, extent, labels, marks)]}
    | extent + psPendingSpace st > room cfg st && not (empty st) ->
        Right st {psDeferred = psDeferred st <> [(ident, extent, labels, marks)], psPendingSpace = 0, psBlankActive = False}
    | otherwise -> Right (putSlot (fit cfg st extent) extent (SFigure ident) labels marks)
  FWrapped ident extent labels marks beside -> do
    let beforeLine line = Map.findWithDefault 0 (lbId line) (physicalWrappedBefore cfg)
    if extent > physicalCapacity cfg
      then Left (PhysicalFigureTooTall ident)
      else do
        let start = fit cfg st extent
            origin = psUsed start
            withFigure = putSlot start 0 (SWrapped ident) labels marks
            count = fittingWrapped cfg withFigure (origin + extent) beside
            (alongside, later) = splitAt count beside
        placed <- foldl' (\acc line -> acc >>= \s -> putWrappedLine cfg (origin + extent) (s {psUsed = psUsed s + beforeLine line}) line) (Right withFigure) alongside
        let afterFigure = placed {psUsed = max (psUsed placed) (origin + extent)}
        if null later then Right afterFigure else placeWrappedOverflow cfg (nextColumn cfg afterFigure) later
  FHeading _ recto extent lines' ->
    let firstId = maybe 0 lbId (safeHead lines')
        headingState = if recto then parityStart cfg odd st else st
     in placeHeading cfg headingState firstId extent lines'
  FBreak kind -> Right (breakAt cfg kind st)
  FSection startOf kind ->
    let settled = drainCarry cfg st
        started = case kind of
          BreakColumn | empty settled -> settled
          BreakPage | empty settled && psColumn settled == 0 -> settled
          _ -> breakAt cfg kind settled
     in Right $ case startOf of
          OfSection ident -> started {psSections = psSections started <> [(ident, psPage started)]}
          OfParagraph _ -> started
  FNeedLines span' n ->
    let required = fromIntegral n * physicalPagePitch cfg
        bounded = min required (physicalCapacity cfg)
        tooMuch = required > physicalCapacity cfg
        marked = if tooMuch then st {psUnmet = psUnmet st <> [UnmetNeedLines span' n]} else st
        judge current
          | bounded <= room cfg current = current
          | empty current && psAdjustment current < 0 = judge (nextColumn cfg current)
          | empty current = current
          | otherwise = judge (nextColumn cfg current)
     in Right (judge marked)
  FAdjustLines span' n ->
    let Sp pagePitch = physicalPagePitch cfg
        Sp baseLength = physicalCapacity cfg
        Sp maximumLength = physicalMaxCapacity cfg
        Sp usedLength = psUsed st + psNotesUsed st
        Sp faceLength = physicalFontSize cfg
        Sp oldAdjustment = psAdjustment st
        wanted = oldAdjustment `div` pagePitch + fromIntegral n
        lower = ceilDiv (max faceLength usedLength - baseLength) pagePitch
        upper = (maximumLength - baseLength) `div` pagePitch
        chosen = max lower (min upper wanted)
        limitReason
          | chosen < wanted = AdjustNoRoom
          | usedLength > faceLength = AdjustLinesPlaced
          | otherwise = AdjustOneLine
        limited = [UnmetAdjust span' (fromInteger chosen) limitReason | chosen /= wanted]
     in Right st {psAdjustment = fromInteger chosen * physicalPagePitch cfg, psUnmet = psUnmet st <> limited}
  FNoBreak span' -> Right (waitForPrior (UnmetNoBreak span') (1, False) st)
  FNoBreakLines _ n | n <= 0 -> Right st
  FNoBreakLines span' _ -> Right (waitForPrior (UnmetNoBreak span') (1, False) st)
  FKeepNext span' _ -> Right (waitForPrior (UnmetKeepNext span') (1, False) st)
  FRestoreColumns -> Right ((nextPage cfg st) {psSet = physicalColumns cfg})
  FSwitchColumns set ->
    let settled = drainCarry cfg st
     in if (csColumns (physicalColumns cfg) == 1 && room cfg settled > 0) || (empty settled && psColumn settled == 0)
          then
            let first = psUsed settled
                closed = close cfg settled
             in Right closed {psSet = set {csFirstLine = first}, psColumn = 0, psUsed = first, psSlots = [], psNotes = [], psLabels = [], psMarks = [], psTables = [], psBoxes = [], psRules = [], psJoin = Nothing, psPendingSpace = 0, psBlankActive = False, psBlankSpans = []}
          else let fresh = nextPage cfg settled in Right fresh {psSet = set {csFirstLine = 0}}
  FPageFigure ident labels marks -> let fresh = if empty st then st else nextPage cfg st in Right (nextPage cfg (putSlot fresh (physicalCapacity cfg) (SPageFigure ident) labels marks))
  FTable ident before header rows caption below -> placeTable cfg st ident before header rows caption below
  FCode geometry caption first continued rows -> placeCode cfg st geometry caption first continued rows
  ruled@FRuled {} -> placeRuled cfg st ruled []
  FBoxed ident before after [FParagraph keep lines'] -> placeBoxedParagraph cfg st ident before after keep [(0, line) | line <- lines']
  FBoxed ident before after [FStanza keep verses] -> placeBoxedStanza cfg st ident before after keep verses
  FBoxed ident before after body | Just (gaps, units) <- collectMixedBoxUnits body -> placeBoxedStanzaWith (boxKeepMarks body) (boxKeepCounts body) (boxUnitKeeps body) gaps cfg st ident before after (Keep 1 1 False) units
  FBoxed ident before after body -> do
    let padding = Map.findWithDefault 0 ident (physicalBoxPadding cfg)
        lines' = concatMap flowLines body
        (beforeExtra, afterExtra) = case (safeHead lines', safeHead (reverse lines')) of
          (Just first, Just last') -> boxExtras (pitchOf cfg first) (faceOf cfg first) (pitchOf cfg last') (faceOf cfg last') padding
          _ -> (before, after)
        minimumSize = case safeHead lines' of
          Nothing -> 0
          Just first -> let (a, b) = boxExtras (pitchOf cfg first) (faceOf cfg first) (pitchOf cfg first) (faceOf cfg first) padding in a + pitchOf cfg first + b
    if minimumSize > physicalCapacity cfg
      then Left (PhysicalBoxTooTall ident)
      else do
        let start = fit cfg st minimumSize
        placed <- foldl' (\acc flow -> acc >>= \s -> placeFlow cfg s flow) (Right (start {psUsed = psUsed start + beforeExtra})) body
        let end = psUsed placed + afterExtra
        pure placed {psUsed = end, psBoxes = psBoxes placed <> [BoxSegment ident (psUsed start) end]}

flowLines :: FlowAt Sp -> [LineBox]
flowLines = \case
  FParagraph _ ls -> ls
  FContinued _ ls -> ls
  FStanza _ verses -> concat verses
  FDefTerm ls -> ls
  FHeading {fhLines = ls} -> ls
  FWrapped {fwBeside = ls} -> ls
  FTable {ftHeader = header, ftRows = rows, ftCaption = caption} -> header <> concat rows <> caption
  FCode {fcRows = ls} -> ls
  FRuled {frBody = RuledLines _ ls} -> ls
  FRuled {frBody = RuledHeading _ _ ls} -> ls
  FBoxed {fbBody = body} -> concatMap flowLines body
  _ -> []

boxKeepLinks :: [FlowAt Sp] -> [(Int, Golem.Syntax.SrcSpan, Int)]
boxKeepLinks = go Nothing
  where
    go _ [] = []
    go prior (FSpace {} : rest) = go prior rest
    go prior (FKeepNext span' wanted : rest) =
      [(ident, span', fst (followingRows wanted rest)) | ident <- maybe [] pure prior] <> go prior rest
    go prior (flow : rest) =
      let lastRow = lbId <$> safeHead (reverse (flowLines flow))
       in go (lastRow <|> prior) rest

boxKeepMarks :: [FlowAt Sp] -> Map Int [Golem.Syntax.SrcSpan]
boxKeepMarks body = Map.fromListWith (<>) [(ident, [span']) | (ident, span', _) <- boxKeepLinks body]

-- The following prefix counts display rows, including whole selected verse lines.
boxKeepCounts :: [FlowAt Sp] -> Map Int Int
boxKeepCounts body = Map.fromListWith max [(ident, count) | (ident, _, count) <- boxKeepLinks body]

-- Equal box decorations do not combine the paragraphs' individual keep policies.
data BoxUnitKeep = BoxUnitKeep
  { bukKeep :: !Keep,
    bukParagraph :: !Int,
    bukIndex :: !Int,
    bukCount :: !Int
  }

boxUnitKeeps :: [FlowAt Sp] -> Map Int BoxUnitKeep
boxUnitKeeps body =
  Map.fromList
    [ (lbId firstLine, BoxUnitKeep keep paragraph index (length units))
    | flow <- body,
      (keep, rawUnits) <- case flow of
        FParagraph k lines' -> [(k, [[line] | line <- lines'])]
        FStanza k verses -> [(k, verses)]
        _ -> [],
      let units = filter (not . null) rawUnits,
      paragraph <- maybe [] (pure . lbId) (safeHead (concat units)),
      (index, unit) <- zip [0 ..] units,
      firstLine <- maybe [] pure (safeHead unit)
    ]

collectMixedBoxUnits :: [FlowAt Sp] -> Maybe (Map Int Sp, [[LineBox]])
collectMixedBoxUnits = go 0 Map.empty []
  where
    go _ gaps units [] = Just (gaps, reverse units)
    go pending gaps units (FSpace n : rest) = go (pending + n) gaps units rest
    go pending gaps units (FParagraph _ lines' : rest) = append pending gaps units [[line] | line <- lines'] rest
    go pending gaps units (FStanza _ verses : rest) = append pending gaps units verses rest
    go pending gaps units (FKeepNext _ _ : rest) = go pending gaps units rest
    go _ _ _ _ = Nothing
    append pending gaps units rawUnits rest =
      let incoming = filter (not . null) rawUnits
       in case safeHead (concat incoming) of
            Nothing -> go pending gaps units rest
            Just first -> go 0 (if pending == 0 then gaps else Map.insert (lbId first) pending gaps) (reverse incoming <> units) rest

placeBoxedParagraph :: PhysicalSettings -> PhysicalState -> Int -> Sp -> Sp -> Keep -> [(Sp, LineBox)] -> Either PhysicalFailure PhysicalState
placeBoxedParagraph = placeBoxedParagraphWithKeeps Map.empty

placeBoxedParagraphWithKeeps :: Map Int [Golem.Syntax.SrcSpan] -> PhysicalSettings -> PhysicalState -> Int -> Sp -> Sp -> Keep -> [(Sp, LineBox)] -> Either PhysicalFailure PhysicalState
placeBoxedParagraphWithKeeps keepMarks cfg starting ident fallbackBefore fallbackAfter keep0 = go keep0 True starting
  where
    padding = Map.findWithDefault 0 ident (physicalBoxPadding cfg)
    extras first last' =
      if Map.member ident (physicalBoxPadding cfg)
        then boxExtras (pitchOf cfg first) (faceOf cfg first) (pitchOf cfg last') (faceOf cfg last') padding
        else (fallbackBefore, fallbackAfter)
    fragmentSize st ls = case (safeHead ls, safeHead (reverse ls)) of
      (Just (_, first), Just (_, last')) ->
        let (a, b) = extras first last'
            notes = sum [nbLines note | (_, line) <- ls, note <- lbNotes line]
            separator = if notes > 0 && psNotesUsed st == 0 then physicalSeparator cfg else 0
         in a + sum [pitchOf cfg line + if index == (0 :: Int) then 0 else gap | (index, (gap, line)) <- zip [0 ..] ls] + b + separator + fromIntegral notes * physicalPagePitch cfg
      _ -> 0
    bareLineSize first = let (a, b) = extras first first in a + pitchOf cfg first + b
    go _ _ st [] = Right st
    go keep isStart st lines'@((_, first) : _) =
      let firstSize = bareLineSize first
          firstNote = safeHead (filter ((> 0) . nbLines) (lbNotes first))
          candidates = [k | k <- [1 .. length lines'], fragmentSize st (take k lines') + psPendingSpace st <= room cfg st]
          available = if null candidates then 0 else last candidates
          selected = splitAtBreak keep isStart (length lines') available
          candidateCount = if selected == 0 then max 1 available else selected
          crossing =
            if candidateCount < length lines'
              then case safeHead (reverse (take candidateCount lines')) of
                Just (_, lastHere) -> Map.lookup (lbId lastHere) keepMarks
                Nothing -> Nothing
              else Nothing
       in if firstSize > physicalCapacity cfg
            then Left (PhysicalBoxTooTall ident)
            else
              if firstSize + physicalSeparator cfg + physicalPagePitch cfg > physicalCapacity cfg && isJust firstNote
                then maybe (Left (PhysicalBoxTooTall ident)) (Left . PhysicalFootnoteTooTall . nbId) firstNote
                else
                  if kAll keep && isStart && available < length lines'
                    then
                      if empty st
                        then go (keep {kAll = False}) isStart (st {psUnmet = psUnmet st <> [SplitKept (lbId first)]}) lines'
                        else go keep isStart (nextColumn cfg st) lines'
                    else
                      if (selected == 0 || (isJust crossing && candidateCount == 1)) && not (empty st)
                        then go keep isStart (nextColumn cfg st) lines'
                        else
                          let count = if isJust crossing && candidateCount > 1 then candidateCount - 1 else candidateCount
                              (here, rest) = splitAt count lines'
                              forced = selected == 0 && empty st && not (null rest)
                              short =
                                [ShortPart FirstPart (lbId first) (kFirst keep) count | forced, isStart, count < kFirst keep]
                                  <> [ShortPart LastPart (lbId first) (kLast keep) (length rest) | forced, length rest < kLast keep]
                                  <> [UnmetKeepNext span' | candidateCount == 1, empty st, spans <- maybe [] pure crossing, span' <- spans]
                           in case (safeHead here, safeHead (reverse here)) of
                                (Just (_, firstHere), Just (_, lastHere)) -> do
                                  let (beforeExtra, afterExtra) = extras firstHere lastHere
                                      ready = fit cfg st (fragmentSize st here)
                                      origin = psUsed ready
                                      bodyState = ready {psUsed = origin + beforeExtra, psAdjustment = psAdjustment ready - afterExtra}
                                  placed <- foldl' (\acc (index, (gap, line)) -> acc >>= \s -> putLine cfg (s {psUsed = psUsed s + if index == (0 :: Int) then 0 else gap}) line) (Right bodyState) (zip [0 ..] here)
                                  let end = psUsed placed + afterExtra
                                      finished = placed {psUsed = end, psAdjustment = psAdjustment ready, psBoxes = psBoxes placed <> [BoxSegment ident origin end], psUnmet = psUnmet placed <> short}
                                  if null rest then Right finished else go keep False (nextColumn cfg finished) rest
                                _ -> Right st

placeBoxedStanza :: PhysicalSettings -> PhysicalState -> Int -> Sp -> Sp -> Keep -> [[LineBox]] -> Either PhysicalFailure PhysicalState
placeBoxedStanza cfg starting ident before afterSide keep verses =
  placeBoxedStanzaWith Map.empty Map.empty Map.empty Map.empty cfg starting ident before afterSide keep (filter (not . null) verses)

placeBoxedStanzaWith :: Map Int [Golem.Syntax.SrcSpan] -> Map Int Int -> Map Int BoxUnitKeep -> Map Int Sp -> PhysicalSettings -> PhysicalState -> Int -> Sp -> Sp -> Keep -> [[LineBox]] -> Either PhysicalFailure PhysicalState
placeBoxedStanzaWith keepMarks keepCounts unitKeeps gaps cfg starting ident fallbackBefore fallbackAfter keep0 = go keep0 True [] Nothing starting
  where
    padding = Map.lookup ident (physicalBoxPadding cfg)
    extras first last' = maybe (fallbackBefore, fallbackAfter) (boxExtras (pitchOf cfg first) (faceOf cfg first) (pitchOf cfg last') (faceOf cfg last')) padding
    size st open verses = case (safeHead (concat verses), safeHead (reverse (concat verses))) of
      (Just first, Just last') ->
        let (a, b) = extras first last'
            notes = sum [nbLines note | line <- concat verses, note <- lbNotes line]
            separator = if notes > 0 && psNotesUsed st == 0 then physicalSeparator cfg else 0
            betweenUnits = sum [Map.findWithDefault 0 (lbId firstLine) gaps | (index, firstLine : _) <- zip [0 :: Int ..] verses, index > 0 || hasOpen open]
         in (if hasOpen open then 0 else a) + sum (map (pitchOf cfg) (concat verses)) + betweenUnits + b + separator + fromIntegral notes * physicalPagePitch cfg
      _ -> 0
    go _ _ _ open st [] = Right (seal open st)
    go keep isStart relaxed open st verses@(firstVerse : _) =
      let candidates = [k | k <- [1 .. length verses], size st open (take k verses) + psPendingSpace st <= room cfg st]
          available = if null candidates then 0 else last candidates
          selected
            | Map.null unitKeeps = splitAtBreak keep isStart (length verses) available
            | otherwise = maximum (0 : [n | n <- [1 .. available], legalBreak relaxed verses n])
          paragraphCount
            | Map.null unitKeeps = splitAtBreak keep isStart (length verses) available
            | otherwise = maximum (0 : [n | n <- [1 .. available], paragraphBreak relaxed verses n])
       in if selected == 0 && not (empty st)
            then go keep isStart relaxed Nothing (nextColumn cfg (seal open st)) verses
            else
              if selected == 0 && paragraphCount == 0 && empty st && kAll keep && isStart
                then go (keep {kAll = False}) isStart relaxed open (st {psUnmet = psUnmet st <> [SplitKept (maybe 0 lbId (safeHead firstVerse))]}) verses
                else
                  if selected == 0 && paragraphCount == 0 && empty st && maybe False (\bounds -> kAll (bukKeep bounds) && bukParagraph bounds `notElem` relaxed) (boundsOf firstVerse)
                    then
                      let paragraph = maybe 0 bukParagraph (boundsOf firstVerse)
                       in go keep isStart (paragraph : relaxed) open (st {psUnmet = psUnmet st <> [SplitKept paragraph]}) verses
                    else
                      if selected == 0 && available == 0
                        then do
                          let unitKeep = fallbackKeep relaxed firstVerse
                          placed <- placeBoxedParagraph cfg st ident fallbackBefore fallbackAfter unitKeep [(0, line) | line <- firstVerse]
                          let (resumed, continuing) = reopen firstVerse placed
                          go keep False relaxed continuing resumed (drop 1 verses)
                        else do
                          let count
                                | selected > 0 = selected
                                | paragraphCount > 0 = paragraphCount
                                | otherwise = available
                              (here, later) = splitAt count verses
                              rows = concat here
                              forced = selected == 0 && not (null later)
                              firstId = maybe 0 lbId (safeHead firstVerse)
                              short =
                                ( if Map.null unitKeeps
                                    then
                                      [ShortPart FirstPart firstId (kFirst keep) count | forced, isStart, count < kFirst keep]
                                        <> [ShortPart LastPart firstId (kLast keep) (length later) | forced, length later < kLast keep]
                                    else boundaryWarnings forced verses count
                                )
                                  <> [UnmetKeepNext span' | forced, span' <- linkBreaks verses count]
                          case (safeHead rows, safeHead (reverse rows)) of
                            (Just first, Just last') -> do
                              let (beforeExtra, afterExtra) = extras first last'
                                  ready = fit cfg st (size st open here)
                                  origin = maybe (psUsed ready) (bsFirst . fst) open
                                  firstGap = if hasOpen open then Map.findWithDefault 0 (lbId first) gaps else 0
                                  before = if hasOpen open then 0 else beforeExtra
                                  bodyState = ready {psUsed = psUsed ready + before + firstGap, psAdjustment = psAdjustment ready - afterExtra}
                              placed <-
                                foldl'
                                  ( \acc (index, verse) ->
                                      acc >>= \s ->
                                        let gap = if index == (0 :: Int) then 0 else maybe 0 (\line -> Map.findWithDefault 0 (lbId line) gaps) (safeHead verse)
                                         in foldl' (\lineAcc line -> lineAcc >>= \lineState -> putLine cfg lineState line) (Right (s {psUsed = psUsed s + gap})) verse
                                  )
                                  (Right bodyState)
                                  (zip [0 :: Int ..] here)
                              let end = psUsed placed + afterExtra
                                  finished = placed {psUsed = end, psAdjustment = psAdjustment ready, psBoxes = psBoxes placed <> [BoxSegment ident origin end], psUnmet = psUnmet placed <> short}
                              if null later then Right finished else go keep False relaxed Nothing (nextColumn cfg finished) later
                            _ -> Right st

    hasOpen = isJust
    seal Nothing st = st
    seal (Just (segment, after)) st = st {psUsed = psUsed st + after, psBoxes = psBoxes st <> [segment]}
    reopen verse st = case (reverse (psBoxes st), safeHead (reverse verse)) of
      (segment : earlier, Just lastLine)
        | bsBox segment == ident,
          bsLast segment == psUsed st ->
            let (_, after) = extras lastLine lastLine
             in (st {psUsed = psUsed st - after, psBoxes = reverse earlier}, Just (segment, after))
      _ -> (st, Nothing)
    boundsOf unit = safeHead unit >>= (\line -> Map.lookup (lbId line) unitKeeps)
    fallbackKeep relaxed unit = case boundsOf unit of
      Just bounds -> let value = bukKeep bounds in if bukParagraph bounds `elem` relaxed then value {kAll = False} else value
      Nothing -> Keep 1 1 False
    atGroupStart verses bounds = case [bukIndex value | Just value <- map boundsOf verses, bukParagraph value == bukParagraph bounds] of
      index : _ -> index == 0
      [] -> False
    boundary verses n = case (drop (n - 1) verses, drop n verses) of
      (before : _, afterUnit : _) -> case (boundsOf before, boundsOf afterUnit) of
        (Just a, Just b) | bukParagraph a == bukParagraph b -> Just (a, b)
        _ -> Nothing
      _ -> Nothing
    legalBreak relaxed verses n = paragraphBreak relaxed verses n && null (linkBreaks verses n)
    linkBreaks verses n
      | n >= length verses = []
      | otherwise =
          let cut = length (concat (take n verses))
           in [span' | (index, line) <- zip [0 ..] (concat verses), index < cut, Just wanted <- [Map.lookup (lbId line) keepCounts], wanted > cut - index - 1, span' <- Map.findWithDefault [] (lbId line) keepMarks]
    paragraphBreak relaxed verses n = case boundary verses n of
      Nothing -> True
      Just (a, b) ->
        let keep = bukKeep a
            firstCount = bukIndex a + 1
            lastCount = bukCount b - bukIndex b
         in (not (kAll keep) || bukParagraph a `elem` relaxed)
              && (not (atGroupStart verses a) || firstCount >= kFirst keep)
              && lastCount >= kLast keep
    boundaryWarnings forced verses n = case boundary verses n of
      Just (a, b)
        | forced ->
            let keep = bukKeep a
                firstCount = bukIndex a + 1
                lastCount = bukCount b - bukIndex b
             in [ShortPart FirstPart (bukParagraph a) (kFirst keep) firstCount | atGroupStart verses a, firstCount < kFirst keep]
                  <> [ShortPart LastPart (bukParagraph b) (kLast keep) lastCount | lastCount < kLast keep]
      _ -> []

placeRuledKeeping :: PhysicalSettings -> PhysicalState -> FlowAt Sp -> [FlowAt Sp] -> Either PhysicalFailure PhysicalState
placeRuledKeeping cfg st ruled@FRuled {} later = do
  full <- placeRuled cfg st ruled later
  let following = case keepAhead later of
        Just (_, wanted, rest) -> Just (wanted, rest)
        Nothing -> case frBody ruled of
          RuledHeading {} -> Just (1, later)
          _ -> Nothing
  case following of
    Just (wanted, rest)
      | not (empty st),
        not (fitsFollowing cfg full wanted rest) ->
          placeRuled cfg (nextColumn cfg (flushPendingRule cfg st)) ruled {frJoined = False} later
    _ -> Right full
placeRuledKeeping cfg st flow later = placeRuled cfg st flow later

placeRuled :: PhysicalSettings -> PhysicalState -> FlowAt Sp -> [FlowAt Sp] -> Either PhysicalFailure PhysicalState
placeRuled cfg st ruled@FRuled {} laterFlows = case frBody ruled of
  RuledLines keep lines' -> case (safeHead lines', safeHead (reverse lines')) of
    (Just first, Just last') -> do
      let firstPitch = pitchOf cfg first
          lastPitch = pitchOf cfg last'
          beforeGeometry side = case psJoin st of
            Just (priorId, prior, priorLine, priorExtra)
              | frJoined ruled ->
                  let previousPitch = pitchOf cfg priorLine
                      previousFace = faceOf cfg priorLine
                      priorEnd = psUsed st - priorExtra - previousPitch + faceOffset previousPitch previousFace + previousFace
                      gap = psUsed st + faceOffset firstPitch (faceOf cfg first) - priorEnd
                      (extra, priorPosition, currentPosition) = rulesSharedGap gap prior side (lbOverhang first)
                   in (extra, priorEnd + currentPosition, [PlacedRule priorId False (priorEnd + priorPosition)])
            _ -> case safeHead (reverse (psSlots st)) of
              Just (priorAt, SLine priorId)
                | psPendingSpace st == 0 ->
                    let priorLine = LineBox priorId [] [] [] 0
                        priorEnd = priorAt + faceOffset (pitchOf cfg priorLine) (faceOf cfg priorLine) + faceOf cfg priorLine
                        gap = psUsed st + faceOffset firstPitch (faceOf cfg first) - priorEnd
                        (extra, position) = ruleBeforeGap gap side (lbOverhang first)
                     in (extra, priorEnd + position, [])
              _ ->
                let (extra, position) = ruleBeforeEdge firstPitch (faceOf cfg first) (if empty st && psUsed st == 0 then side else side {rsdOutside = Nothing}) (lbOverhang first)
                 in (extra, psUsed st + position, [])
          beforeExtra = maybe 0 (\side -> let (extra, _, _) = beforeGeometry side in extra) (frBefore ruled)
          joiningNext = case laterFlows of
            FRuled {frJoined = True, frBefore = Just _} : _ -> True
            _ -> False
          afterGeometry side = case laterFlows of
            nextFlow : _
              | nextLine : _ <- flowLines nextFlow ->
                  let gap = lastPitch - faceOf cfg last' - faceOffset lastPitch (faceOf cfg last') + faceOffset (pitchOf cfg nextLine) (faceOf cfg nextLine)
                      (extra, position) = ruleAfterGap gap side (frNextOverhang ruled)
                   in (extra, faceOffset lastPitch (faceOf cfg last') + faceOf cfg last' + position)
            _ -> ruleAfterEdge lastPitch (faceOf cfg last') side {rsdOutside = Nothing}
          afterExtra = if joiningNext then 0 else maybe 0 (fst . afterGeometry) (frAfter ruled)
          bodyExtent = sum (map (pitchOf cfg) lines')
          extent = beforeExtra + bodyExtent + afterExtra
      if frJoined ruled && isJust (psJoin st) && extent + psPendingSpace st > room cfg st && not (empty st)
        then
          placeRuled cfg (nextColumn cfg (flushPendingRule cfg st)) ruled {frJoined = False} laterFlows
        else
          if extent > physicalCapacity cfg
            then placeLines cfg keep True st lines'
            else do
              let ready = fit cfg st extent
              if (psPage ready, psColumn ready) /= (psPage st, psColumn st)
                then placeRuled cfg ready ruled laterFlows
                else do
                  let origin = psUsed ready
                      withBefore = ready {psUsed = origin + beforeExtra, psAdjustment = psAdjustment ready - afterExtra}
                  placed <- foldl' (\acc line -> acc >>= \s -> putLineWithReserve True cfg s line) (Right withBefore) lines'
                  let sharedRules = concat [prior | side <- maybe [] pure (frBefore ruled), let (_, _, prior) = beforeGeometry side]
                      startRule = [PlacedRule (frId ruled) True position | side <- maybe [] pure (frBefore ruled), let (_, position, _) = beforeGeometry side]
                      endRule = [PlacedRule (frId ruled) False (psUsed placed - lastPitch + snd (afterGeometry side)) | not joiningNext, side <- maybe [] pure (frAfter ruled)]
                      waiting = if joiningNext then (frId ruled,,last',afterExtra) <$> frAfter ruled else Nothing
                  pure placed {psUsed = psUsed placed + afterExtra, psAdjustment = psAdjustment ready, psRules = psRules placed <> sharedRules <> startRule <> endRule, psJoin = waiting}
    _ -> Right st
  RuledHeading recto extent lines' -> do
    let headingState = if recto then parityStart cfg odd st else keepFollowing cfg True st extent lines' laterFlows
    let firstId = maybe 0 lbId (safeHead lines')
        firstLine = safeHead lines'
        lastLine = safeHead (reverse lines')
        beforeGeometry side line =
          let size = faceOf cfg line
              virtualPitch = maybe (pitchOf cfg line) (\(firstFaceAt, _) -> 2 * firstFaceAt + size) (Map.lookup firstId (physicalHeadingBounds cfg))
           in ruleBeforeEdge virtualPitch size side (lbOverhang line)
        afterGeometry side line = case Map.lookup firstId (physicalHeadingBounds cfg) of
          Nothing ->
            let (extra, position) = ruleAfterEdge (pitchOf cfg line) (faceOf cfg line) side {rsdOutside = Nothing}
             in (extra, extent - pitchOf cfg line + position)
          Just (_, lastFaceEnd) ->
            let size = faceOf cfg line
                trailing = extent - lastFaceEnd
                virtualPitch = 2 * trailing + size
                (extra, position) = ruleAfterEdge virtualPitch size side {rsdOutside = Nothing}
             in (extra, lastFaceEnd - size - trailing + position)
        beforeExtra = maybe 0 (\side -> maybe 0 (fst . beforeGeometry side) firstLine) (frBefore ruled)
        afterExtra = maybe 0 (\side -> maybe 0 (fst . afterGeometry side) lastLine) (frAfter ruled)
        noteCount = sum [nbLines note | line <- lines', note <- lbNotes line]
        headingNotes = fromIntegral noteCount * physicalPagePitch cfg + (if noteCount > 0 then physicalSeparator cfg else 0)
    if extent > physicalCapacity cfg
      then Left (PhysicalHeadingTooTall firstId)
      else
        if beforeExtra + extent + afterExtra + headingNotes > physicalCapacity cfg
          then case frAfter ruled of
            Just _ -> placeRuled cfg headingState ruled {frAfter = Nothing} laterFlows
            Nothing -> case frBefore ruled of
              Just _ -> placeRuled cfg headingState ruled {frBefore = Nothing} laterFlows
              Nothing -> placeHeading cfg headingState firstId extent lines'
          else do
            let headingSize = beforeExtra + headingNeed cfg headingState extent lines' + afterExtra
                adjustedException = empty headingState && psAdjustment headingState < 0 && headingSize > room cfg headingState && headingSize <= physicalCapacity cfg - psUsed headingState - psNotesUsed headingState
                ready =
                  if adjustedException
                    then headingState {psPendingSpace = 0, psBlankActive = False, psBlankSpans = [], psUnmet = psUnmet headingState <> [TallHeadingExtent firstId extent (room cfg headingState)]}
                    else fit cfg headingState headingSize
            if (psPage ready, psColumn ready) /= (psPage headingState, psColumn headingState)
              then placeRuled cfg ready ruled laterFlows
              else do
                let origin = psUsed ready
                placed0 <- putHeading cfg (ready {psUsed = origin + beforeExtra, psAdjustment = psAdjustment ready - afterExtra}) firstId extent lines'
                let placed = placed0 {psAdjustment = psAdjustment ready}
                    startRule = [PlacedRule (frId ruled) True (origin + snd (beforeGeometry (if empty ready && origin == 0 then side else side {rsdOutside = Nothing}) line)) | side <- maybe [] pure (frBefore ruled), line <- maybe [] pure firstLine]
                    endRule = [PlacedRule (frId ruled) False (psUsed placed - extent + snd (afterGeometry side line)) | side <- maybe [] pure (frAfter ruled), line <- maybe [] pure lastLine]
                pure placed {psUsed = psUsed placed + afterExtra, psRules = psRules placed <> startRule <> endRule}
placeRuled _ st _ _ = Right st

safeHead :: [a] -> Maybe a
safeHead [] = Nothing
safeHead (x : _) = Just x

flushPendingRule :: PhysicalSettings -> PhysicalState -> PhysicalState
flushPendingRule cfg st = case psJoin st of
  Nothing -> st
  Just (ident, side, lastLine, priorExtra) ->
    let pitch = pitchOf cfg lastLine
        face = faceOf cfg lastLine
        firstAt = psUsed st - priorExtra - pitch
        (extra, position) = ruleAfterEdge pitch face side {rsdOutside = Nothing}
     in st {psUsed = psUsed st + max 0 (extra - priorExtra), psRules = psRules st <> [PlacedRule ident False (firstAt + position)], psJoin = Nothing}

waitFor :: Unmet -> (Int, Bool) -> PhysicalState -> PhysicalState
waitFor unmet (required, linesOnly) st =
  let combined = maximum (required : [n | (_, _, _, _, n, _) <- psWaits st])
      onlyLines = linesOnly || or [flag | (_, _, _, _, _, flag) <- psWaits st]
      prior = [(u, page, column, count, combined, onlyLines) | (u, page, column, count, _, _) <- psWaits st]
   in st {psWaits = prior <> [(unmet, psPage st, psColumn st, length (psSlots st), combined, onlyLines)]}

waitForPrior :: Unmet -> (Int, Bool) -> PhysicalState -> PhysicalState
waitForPrior unmet required st
  | empty st || not (null (psDeferred st)) = st {psUnmet = psUnmet st <> [unmet]}
  | otherwise = waitFor unmet required st

ceilDiv :: Integer -> Integer -> Integer
ceilDiv numerator denominator = negate (negate numerator `div` denominator)

{- | A heading remains one slot, while its note bodies use the same physical
reservation and continuation rules as body lines.
-}
putHeading :: PhysicalSettings -> PhysicalState -> Int -> Sp -> [LineBox] -> Either PhysicalFailure PhysicalState
putHeading cfg st firstId extent lines' = do
  let line = LineBox firstId (concatMap lbNotes lines') (concatMap lbLabels lines') (concatMap lbMarks lines') 0
      settings = cfg {physicalPitches = Map.insert firstId extent (physicalPitches cfg)}
  placed <- putLine settings st line
  pure placed {psSlots = psSlots st <> [(psUsed st, SHeading firstId (length lines'))]}

headingNeed :: PhysicalSettings -> PhysicalState -> Sp -> [LineBox] -> Sp
headingNeed cfg st extent lines' =
  let notes = sum [nbLines note | line <- lines', note <- lbNotes line]
      separator = if notes > 0 && psNotesUsed st == 0 then physicalSeparator cfg else 0
      complete = extent + separator + fromIntegral notes * physicalPagePitch cfg
   in if complete <= physicalCapacity cfg
        then complete
        else extent + separator + (if notes > 0 then physicalPagePitch cfg else 0)

placeHeading :: PhysicalSettings -> PhysicalState -> Int -> Sp -> [LineBox] -> Either PhysicalFailure PhysicalState
placeHeading cfg st firstId extent lines'
  | extent > physicalCapacity cfg = Left (PhysicalHeadingTooTall firstId)
  | empty st && psAdjustment st < 0 && required > room cfg st && required <= physicalCapacity cfg - psUsed st - psNotesUsed st =
      let ready = st {psPendingSpace = 0, psBlankActive = False, psBlankSpans = [], psUnmet = psUnmet st <> [TallHeadingExtent firstId extent (room cfg st)]}
       in putHeading cfg ready firstId extent lines'
  | otherwise = putHeading cfg (fit cfg st required) firstId extent lines'
  where
    required = headingNeed cfg st extent lines'

placeCode :: PhysicalSettings -> PhysicalState -> CodeGeometry -> Sp -> Int -> Bool -> [LineBox] -> Either PhysicalFailure PhysicalState
placeCode cfg st0 geometry caption first continued = go st0 True
  where
    pitch = physicalPagePitch cfg
    go st isFirst rows = case rows of
      [] -> Right st
      firstRow : _ ->
        let total = length rows
            captionLength = if isFirst then caption else 0
            minimumRows = if isFirst then min total (max 1 first) else 1
            spanOf n = captionLength + fromIntegral (codeSpan geometry (n + if continued && n < total then 1 else 0)) * pitch
            minimumExtent = spanOf minimumRows
            boundarySpace = if empty st then 0 else psPendingSpace st
            fittingRows = length (takeWhile (\n -> spanOf n + boundarySpace <= room cfg st) [1 .. total])
            count = if fittingRows >= minimumRows then fittingRows else 0
         in if minimumExtent > physicalCapacity cfg
              then Left (PhysicalCodeTooTall (lbId firstRow))
              else
                if count == 0
                  then go (nextColumn cfg st) isFirst rows
                  else
                    let (here, later) = splitAt count rows
                        gridLines = codeSpan geometry (count + if continued && not (null later) then 1 else 0)
                        ready = fit cfg st (spanOf count)
                        placed = putSlot ready (spanOf count) (SCode (lbId firstRow) count gridLines) (concatMap lbLabels here) (concatMap lbMarks here)
                     in if null later then Right placed else go (nextColumn cfg placed) False later

{- | Reserve each indivisible table part before accepting its notes. A
header's note cannot consume the space needed by the first body row.
-}
tableNeed :: PhysicalSettings -> PhysicalState -> Bool -> [LineBox] -> Sp
tableNeed cfg st complete lines' =
  let count = sum [nbLines note | line <- lines', note <- lbNotes line]
      notes = if complete then count else min 1 count
      separator = if count > 0 && psNotesUsed st == 0 then physicalSeparator cfg else 0
   in fromIntegral (length lines' + notes) * physicalPagePitch cfg + separator

checkTableNotes :: PhysicalSettings -> [LineBox] -> Either PhysicalFailure ()
checkTableNotes cfg lines' =
  case [nbId note | line <- lines', note <- lbNotes line] of
    ident : _ | tableNeed cfg (initial cfg) False lines' > physicalCapacity cfg -> Left (PhysicalFootnoteTooTall ident)
    _ -> Right ()

tableReady :: PhysicalSettings -> PhysicalState -> Sp -> [LineBox] -> PhysicalState
tableReady cfg st before lines' =
  let space = if empty st then 0 else before
      required = tableNeed cfg st False lines'
   in if required + space + (if empty st then 0 else psPendingSpace st) <= room cfg st
        then fit cfg st (required + space)
        else tableReady cfg (nextColumn cfg st) before lines'

placeTable :: PhysicalSettings -> PhysicalState -> Int -> Sp -> [LineBox] -> [[LineBox]] -> [LineBox] -> Bool -> Either PhysicalFailure PhysicalState
placeTable cfg st0 ident before header rows caption below = do
  let pitch = physicalPagePitch cfg
      firstRow = fromMaybe [] (safeHead rows)
      captionRows = if not below || length rows <= 1 then caption else []
      firstPart = (if below then [] else caption) <> header <> firstRow <> (if below then captionRows else [])
      minimumExtent = fromIntegral (length firstPart) * pitch
      failKind = if not (null captionRows) then PhysicalTableCaptionTooTall ident else PhysicalTableTooTall ident
      rowTooTall = any (\row -> fromIntegral (length header + length row) * pitch > physicalCapacity cfg) rows
      lastRow = fromMaybe [] (safeHead (reverse rows))
      lastCaptionTooTall = below && fromIntegral (length header + length lastRow + length caption) * pitch > physicalCapacity cfg
      repeated = [line {lbNotes = [], lbLabels = [], lbMarks = []} | line <- header]
      remainingParts = [repeated <> row <> (if below && index == length rows - 1 then caption else []) | (index, row) <- zip [1 ..] (drop 1 rows)]
  if minimumExtent > physicalCapacity cfg
    then Left failKind
    else
      if rowTooTall
        then Left (PhysicalTableTooTall ident)
        else
          if lastCaptionTooTall
            then Left (PhysicalTableCaptionTooTall ident)
            else do
              mapM_ (checkTableNotes cfg) (firstPart : remainingParts)
              let ready = tableReady cfg st0 before firstPart
                  start = ready {psUsed = psUsed ready + if empty ready then 0 else before}
                  reserve = fromIntegral (length header + length firstRow) * pitch
              placedCaption <- if below then Right start else placeTableLinesReserved cfg reserve start caption
              placeTableRows cfg ident header rows caption below placedCaption

placeTableLinesReserved :: PhysicalSettings -> Sp -> PhysicalState -> [LineBox] -> Either PhysicalFailure PhysicalState
placeTableLinesReserved cfg reserve = go
  where
    go st [] = Right st
    go st (line : rest) = do
      let later = reserve + fromIntegral (length rest) * physicalPagePitch cfg
          adjusted = st {psAdjustment = psAdjustment st - later}
      placed <- putLineWithReserve True cfg adjusted line
      go (placed {psAdjustment = psAdjustment st}) rest

placeTableRows :: PhysicalSettings -> Int -> [LineBox] -> [[LineBox]] -> [LineBox] -> Bool -> PhysicalState -> Either PhysicalFailure PhysicalState
placeTableRows cfg ident header rows caption below startingState = do
  let headerStart = psUsed startingState
      following = fromMaybe [] (safeHead rows) <> (if below && length rows <= 1 then caption else [])
  withHeader <- placeTableLinesReserved cfg (fromIntegral (length following) * pitch) startingState header
  go headerStart withHeader rows
  where
    pitch = physicalPagePitch cfg
    finish start st =
      let segment = TableSegment ident start (if null header then Nothing else Just (start + fromIntegral (length header - 1) * pitch)) (psUsed st - pitch)
       in st {psTables = psTables st <> [segment]}
    go start st [] = if below then placeTableLinesReserved cfg 0 (finish start st) caption else Right (finish start st)
    go start st (row : rest) = do
      let lastCaption = if below && null rest then caption else []
          withLastCaption = row <> lastCaption
          firstRow = psUsed st == start + fromIntegral (length header) * pitch
      if tableNeed cfg st True withLastCaption <= room cfg st || firstRow
        then do
          placed <- placeTableLinesReserved cfg (fromIntegral (length lastCaption) * pitch) st row
          go start placed rest
        else do
          let fresh = nextColumn cfg (finish start st)
              repeated = [line {lbNotes = [], lbLabels = [], lbMarks = []} | line <- header]
              ready = tableReady cfg fresh 0 (repeated <> withLastCaption)
          withHeader <- placeTableLinesReserved cfg (fromIntegral (length withLastCaption) * pitch) ready repeated
          go (psUsed ready) withHeader (row : rest)

breakAt :: PhysicalSettings -> BreakKind -> PhysicalState -> PhysicalState
breakAt cfg kind st = case kind of
  BreakColumn -> nextColumn cfg st
  BreakPage -> nextPage cfg st
  BreakRecto -> parity odd
  BreakVerso -> parity even
  where
    parity accept = parityStart cfg accept st

parityStart :: PhysicalSettings -> (Int -> Bool) -> PhysicalState -> PhysicalState
parityStart cfg accept st =
  let settled = drainCarry cfg st
      next = if empty settled && psColumn settled == 0 then settled else nextPage cfg settled
   in if accept (psPage next)
        then next
        else
          if empty next
            then next {psDone = PageOut (psPage next) 0 True [] [] [] [] [] (psSet next) [] (limit cfg next) [] [] [] : psDone next, psPage = psPage next + 1}
            else nextPage cfg next
