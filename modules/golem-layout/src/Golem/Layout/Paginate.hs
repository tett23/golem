{- | Placing lines on pages (golem-layout ADR 0003): greedy page breaking
on the line grid, no orphans or widows, headings and definition terms
kept with what follows, recto starts, figures moved to the next page
when they do not fit, footnotes on the page of their marker, and the
fixed point of page-number references (S2).

Everything is counted in grid lines: a footnote line takes one grid
line from the bottom of the page and the footnote area is separated
from the text by the grid lines of the separator, one unless
[notes.rule] asks for more (golem-driver ADR 0024).

A page may have several columns (docs/adr ADR 0018): the unit of the
break is the column, the flow goes through the columns of a page in
order and then to the next page, and each 'PageOut' is one column of a
page.
-}
module Golem.Layout.Paginate
  ( LineBox (..),
    ColumnSet,
    ColumnSetAt (..),
    NoteId (..),
    NoteBody (..),
    Flow,
    FlowAt (..),
    Slotted (..),
    PageOut,
    PageOutAt (..),
    Unmet (..),
    AdjustLimit (..),
    TableSegment,
    TableSegmentAt (..),
    BoxSegment,
    BoxSegmentAt (..),
    RuledBody,
    RuledBodyAt (..),
    PlacedRule (..),
    HeadingBlock (..),
    Keep (..),
    defaultKeep,
    flowSlotIds,
    StartOf (..),
    Part (..),
    splitAtBreak,
    firstPart,
    headingBlock,
    headingBlockAligned,
    Need (..),
    lookAhead,
    keptLookAhead,
    paginate,
    paginateIn,
    paginateWithin,
    paginateHeld,
    paginateAvoiding,
    AvoidAt,
    noAvoid,
    clearFrom,
    Spot (..),
    pageLabels,
    labelPages,
    markPages,
    resolvePageRefs,
    maxIterations,
  )
where

import Control.Applicative ((<|>))
import Data.Bifunctor (bimap)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Ratio ((%))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry, codeSpan)
import Golem.Layout.PageLabel
import Golem.Layout.Paginate.BookParts (flattenBookParts, flowSlotIds, placeBookPart)
import Golem.Layout.Paginate.Decide
import Golem.Layout.Paginate.State
import Golem.Layout.Paginate.Types
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..), ruleAfter, ruleAfterAtEnd)
import Golem.Length (Sp (..))
import Golem.Project.Style (HeadingBlockAlign (..), KeepParts (..))
import Golem.Syntax (SrcSpan)

{- | The pitch, span and offset of a heading of size @s@ and @m@ lines on
a grid of font size @fs@ and pitch @p@: the body's ratio of pitch to
size is kept, the span is the fewest grid lines that hold it but at
least @least@ (golem-driver ADR 0032), and the heading is centred in
them. One rounding.
-}
headingBlock :: Sp -> Sp -> Sp -> Int -> Int -> HeadingBlock
headingBlock = headingBlockAligned HeadingCenter

headingBlockAligned :: HeadingBlockAlign -> Sp -> Sp -> Sp -> Int -> Int -> HeadingBlock
headingBlockAligned alignment (Sp fs) (Sp p) (Sp s) m least =
  let hp = round (p * s % fs)
      extent = toInteger (max 1 m - 1) * hp + s
      n = max (toInteger (max 1 least)) ((extent + p - fs + p - 1) `div` p)
      area = (n - 1) * p + fs
      availableSpace = max 0 (area - extent)
      offset = case alignment of
        HeadingStart -> 0
        HeadingCenter -> availableSpace `div` 2
        HeadingEnd -> availableSpace
   in HeadingBlock (Sp hp) (fromInteger n) (Sp offset)

{- | The first part of what follows that a heading keeps with it, in a
column of @capacity@ grid lines: its grid lines and the lines of its
notes (golem-layout ADR 0019, 0021).
-}
lookAhead :: Int -> [Flow] -> Need
lookAhead = nextNeed . lookAheadEnv

{- | What a paragraph before a no-break keeps with it, in a column of
@capacity@ grid lines; nothing when no no-break follows (golem-layout ADR 0022).
-}
keptLookAhead :: Int -> [Flow] -> Maybe Need
keptLookAhead = keptNeed . lookAheadEnv

-- | A page of one column of the given grid lines.
lookAheadEnv :: Int -> Env
lookAheadEnv capacity = Env maxBound 1 (ColumnSet 1 0 0 0) KeepColumn Nothing capacity Set.empty noAvoid

{- | Lays the flow out on pages of @columns@ columns of @capacity@ grid
lines each (docs/adr ADR 0018).
-}
paginate :: Int -> Int -> [Flow] -> [PageOut]
paginate columns = paginateIn 1 (ColumnSet columns 0 0 0)

{- | 'paginate' with the grid lines of the footnote separator
(golem-driver ADR 0024) and the columns of the page as a set (docs/adr ADR 0025):
'FSwitchColumns' starts another set of columns, after the lines used on
a page of one column or on the next page otherwise, and
'FRestoreColumns' goes back to @base@ on the next page.
-}
paginateIn :: Int -> ColumnSet -> Int -> [Flow] -> [PageOut]
paginateIn = paginateWithin maxBound

{- | 'paginateIn' with the most grid lines a column may have after
'FAdjustLines' (docs/adr ADR 0030).

The figures given are assumed to be no taller than a column: golem-driver
shrinks a figure to fit an empty column (golem-driver ADR 0034). A taller
one is placed in an empty column, past its end; that is not a rule
(docs/adr/0206).
-}
paginateWithin :: Int -> Int -> ColumnSet -> Int -> [Flow] -> [PageOut]
paginateWithin = paginateHeld Set.empty

{- | 'paginateWithin' with the spans of the keep-with-next of the visible
separators (root ADR 0398 I7): a separator hold goes with what the block
after it keeps, and that block does not leave the hold for its own keeps.
-}
paginateHeld :: Set SrcSpan -> Int -> Int -> ColumnSet -> Int -> [Flow] -> [PageOut]
paginateHeld = paginateAvoiding noAvoid

{- | 'paginateHeld' with the areas of the frames of wrap around of each
column (root ADR 0456): the tables, code blocks and figures are placed
off them, the tables and code blocks broken before them as between
columns, a table without its header row again after them.
-}
paginateAvoiding :: AvoidAt Int -> Set SrcSpan -> Int -> Int -> ColumnSet -> Int -> [Flow] -> [PageOut]
paginateAvoiding avoid held maxLines separatorLines base capacity flows =
  let -- a footnote line always fits under the separator and one line of text
      env = Env maxLines (max 1 (min separatorLines (capacity - 2))) base KeepColumn Nothing capacity held avoid
      final = closePage env (placeAll env (initialState env) flows)
      done = reverse (sDone final)
      -- controls not met in a column that made no output go with the last column
      leftover = sUnmet final
   in case reverse done of
        [] -> [PageOut 1 0 False [] [] [] [] [] base [] capacity leftover [] []]
        lastPage : earlier -> withSections (sSections final) (reverse (lastPage {poUnmet = poUnmet lastPage <> leftover} : earlier))

{- | The sections on the first column of the page each opened
(docs/adr/0260). A section whose page has no column, the book ending
there, has no page.
-}
withSections :: [(Int, Int)] -> [PageOutAt position] -> [PageOutAt position]
withSections starts = go Nothing
  where
    firsts = sectionFirstPages starts
    go _ [] = []
    go prev (p : rest)
      | prev == Just (poNumber p) = p : go prev rest
      | otherwise = p {poSections = Map.findWithDefault [] (poNumber p) firsts} : go (Just (poNumber p)) rest

{- | Each flow in turn. Breaks, need-lines and blank lines left at the end
of the book are dropped (docs/adr ADR 0017, 0030, 0046). The blank lines
left there passed over figures that wait, with nothing after them to go
with: those at the end of the book are dropped where they are written.
They are dropped at the top of the column the figures waiting start in,
or of the column a break placed them in, and recorded (golem-layout ADR
0026).
-}
placeAll :: Env -> St -> [Flow] -> St
placeAll env st [] =
  let st1 = foldl' (\s' (u, _, _, _, _) -> addUnmet u s') st (sNoBreak st)
      st2 = st1 {sBreaks = [], sNeed = Nothing, sNeedAt = Nothing, sNoBreak = [], sBlank = []}
      dropBlanks s = foldl' (\s' (sp, _) -> addUnmet (DroppedBlank sp) s') s (sBlank st1)
   in if null (sBlank st1)
        then flushDeferred env st2
        else
          if null (sDeferred st2)
            then flushDeferred env (dropBlanks st2)
            else flushDeferred env (dropBlanks (nextColumn env st2))
placeAll env st (f : rest) = placeAll env (step env st f rest) rest

{- | One flow placed, with the flows after it to look ahead to; inside a
box, those of its body and those after the box (docs/adr/0271).
-}
step :: Env -> St -> Flow -> [Flow] -> St
step env st f rest = case f of
  FBookPart unit sp kind retained body ->
    let run = go
          where
            go here [] = here
            go here (g : more) = go (step env {envKeepParts = unit, envBookPartSpan = Just sp} here g (more <> rest)) more
     in placeBookPart env run (if null retained then st else applyBreaks env st) unit sp kind retained body
  -- a no-break with nothing before it, or after a figure sent on, cannot be met
  FNoBreakLines _ 0 -> st
  FNoBreakLines sp _ -> step env st (FNoBreak sp) rest
  FNoBreak sp
    | not (sSeen st) || sLastDeferred st -> addUnmet (UnmetNoBreak sp) st
    | otherwise -> waitFor (UnmetNoBreak sp) (1, False) st
  -- a keep-with-next as a no-break, the first part of what follows in the column (docs/adr/0261)
  FKeepNext sp n
    | not (sSeen st) || sLastDeferred st -> addUnmet (UnmetKeepNext sp) st
    | otherwise -> waitFor (UnmetKeepNext sp) (nextFirstLines n rest) st
  -- the larger need-lines is kept; one larger than the need-lines judged is judged again (golem-layout ADR 0035),
  -- before the spaces placed after the block before it (golem-layout ADR 0043)
  FNeedLines sp n -> needMore env sp n st
  -- the continued notes take the room added first (root ADR 0444)
  FAdjustLines sp k -> drainPendingNotes env (adjustLines env (applyBreaks env st) sp k)
  -- blank lines with nothing after them that places anything are the end of the book's (docs/adr ADR 0046)
  FBlank sp n
    | all waitsFor rest -> st
    | otherwise -> st {sBlank = sBlank st <> [(sp, n)]}
  FBreak _ -> place env st f rest
  FSection {} -> place env st f rest
  -- the space between paragraphs is not the flow a no-break waits for;
  -- need-lines is judged before it, the space not counted (golem-layout ADR 0027)
  -- nor the spaces before it, written after the block before (golem-layout ADR 0043)
  FSpace n -> placeSpace env (needBeforeSpaces env (applyBreaks env st)) n
  _ ->
    let -- the breaks first: going on to the next page places the figures waiting, and this one may not wait
        stB = applyBreaks env st
        waiting = waitsBehind stB f
        -- a figure that waits takes neither the need-lines nor the blank lines before it (golem-layout ADR 0026)
        st1
          | waiting = checkNoBreak (place env stB f rest)
          | otherwise = checkNoBreak (placeFlow env (placeBlank env (needBefore env stB (f : rest)) f rest) f rest)
        deferred = case f of
          FFigure i _ _ _ -> any (\case FFigure j _ _ _ -> i == j; _ -> False) (sDeferred st1)
          -- the flow after a turned figure is never on its page
          FPageFigure {} -> True
          _ -> False
        -- the spaces before a need-lines are those after the last block (golem-layout ADR 0043), a figure sent on by
        -- itself one too: a figure that waits keeps them, unless the breaks before it go on from their column (golem-layout ADR 0047)
        spaces = if waiting && null (sBreaks st) then sSpaces st1 else []
     in st1 {sSeen = True, sLastDeferred = deferred, sSpaces = spaces}

{- | Need-lines after need-lines, with no block between: the larger is
kept. When it is larger than the one judged before a space, the column
it was judged in is forgotten, so that the larger is judged before the
next space or before the block (golem-layout ADR 0035); one no larger is
met already. A need-lines kept after spaces placed after the block
before it is judged before them, as before a space after it, the spaces
not counted (golem-layout ADR 0043).
-}
needMore :: Env -> SrcSpan -> Int -> St -> St
needMore env sp n st = case sNeed st of
  Just (_, n0)
    | n <= n0 -> st
  _ -> needAfterSpaces env st {sNeed = Just (sp, n), sNeedAt = Nothing}

{- | A need-lines after the spaces written after the block before it,
with no break between, is judged before them ('needBeforeSpaces'), as
before a space after it (golem-layout ADR 0043). After a break, the
spaces are in a column the flow leaves, and the need-lines waits for the
next space or block.
-}
needAfterSpaces :: Env -> St -> St
needAfterSpaces env st
  | null (sSpaces st) || not (null (sBreaks st)) = st
  | otherwise = needBeforeSpaces env st

{- | The need-lines judged before the spaces written after the block
before ('needBeforeSpace'), their grid lines not counted
(golem-layout ADR 0043). In the column judged in, the spaces stay where
they are; when the flow goes on to a later column, they are placed again
there, as the spaces after a need-lines are: dropped at the top of the
column, and after the figures sent on placed there.
-}
needBeforeSpaces :: Env -> St -> St
needBeforeSpaces env st =
  let k = sum (map snd (sSpaces st))
      st1 = needBeforeSpace env st {sUsed = sUsed st - k}
   in if (sPage st1, sColumn st1) == (sPage st, sColumn st)
        then st1 {sUsed = sUsed st1 + k}
        else foldl' (placeSpace env) st1 (map fst (sSpaces st))

-- | A space of n grid lines, kept with the grid lines it took (golem-layout ADR 0043).
placeSpace :: Env -> St -> Int -> St
placeSpace env st n =
  let st1 = place env st (FSpace n) []
   in st1 {sSpaces = sSpaces st <> [(n, sUsed st1 - sUsed st)]}

{- | Need-lines before a space is judged there, the space not counted,
and kept with the column it was judged in: the block after the spaces is
judged again (golem-layout ADR 0027). Judged once in a column; judged
again if a break has gone on from it.
-}
needBeforeSpace :: Env -> St -> St
needBeforeSpace env st = case sNeed st of
  Nothing -> st
  Just (sp, n)
    | sNeedAt st == Just (sPage st, sColumn st) -> st
    | n > cap env st -> applyNeed env st {sNeedAt = Nothing}
    | otherwise ->
        let st1 = applyNeed env st {sNeedAt = Nothing}
         in st1 {sNeed = Just (sp, n), sNeedAt = Just (sPage st1, sColumn st1)}

{- | The need-lines before a block, after the breaks. Judged before the
spaces in the column the block is in, it holds when the first part of the
block fits there after them; else the block goes on, and in the columns
gone on to the need-lines is judged again, after the figures sent on and
the continued notes (golem-layout ADR 0025, 0027). Otherwise it is
judged here ('applyNeed').
-}
needBefore :: Env -> St -> [Flow] -> St
needBefore env st flows = case (sNeed st, sNeedAt st) of
  (Just (_, n), Just at)
    | at == (sPage st, sColumn st) ->
        keep env st {sNeed = Nothing, sNeedAt = Nothing} (\s -> if (sPage s, sColumn s) == at then needIn env s mempty (nextNeed env flows) else n)
  _ -> applyNeed env st {sNeedAt = Nothing}

{- | Whether a figure waits, placing nothing where it is in the flow: a
figure after a figure sent on, or a turned figure that cannot take the
page now ('place', golem-layout ADR 0015, golem-driver ADR 0034).
-}
waitsBehind :: St -> Flow -> Bool
waitsBehind st = \case
  FFigure {} -> not (null (sDeferred st))
  FPageFigure {} -> not (null (sDeferred st) && sColumn st == 0 && sUsed st == 0 && null (sNotes st) && sNoteLines st == 0)
  _ -> False

-- | The flows that place nothing of their own: the breaks, the controls of page breaks, the blank lines and the spaces.
waitsFor :: Flow -> Bool
waitsFor = \case
  FBookPart _ _ _ _ body -> all waitsFor body
  FBreak _ -> True
  FSection {} -> True
  FNoBreak _ -> True
  FNoBreakLines {} -> True
  FKeepNext {} -> True
  FNeedLines _ _ -> True
  FAdjustLines _ _ -> True
  FBlank _ _ -> True
  FSpace _ -> True
  _ -> False

{- | The blank lines go in the column of the first part of what follows;
at the top of a column they are dropped and recorded, never cut
(docs/adr ADR 0046). A heading at a recto starts its page first. The
next columns are gone on to until the blank lines and the first part fit
or the column is at its top: the figures sent on take the top of a
column gone on to and the continued notes its foot, and a column with
figures sent on is not at its top (golem-layout ADR 0025). The going on
stops at the top of a column, one with continued notes only too, where
the blank lines would be dropped anyway (docs/adr/0211).
-}
placeBlank :: Env -> St -> Flow -> [Flow] -> St
placeBlank env st0 f rest = case sBlank st0 of
  [] -> st0
  blanks ->
    let capacity = envCapacity env
        st1 = if startsRecto f then parityStart env odd st0 else st0
        total = foldl' (\a (_, n) -> min capacity (a + min capacity n)) 0 blanks
        -- at the top of a column the blank lines are dropped: nothing more is needed for them
        st2 = keep env st1 (\s -> if sUsed s == top s then 0 else total + needIn env s mempty (nextNeed env (f : rest)))
     in if sUsed st2 == top st2
          then foldl' (\s' (sp, _) -> addUnmet (DroppedBlank sp) s') st2 {sBlank = []} blanks
          else st2 {sUsed = sUsed st2 + total, sBlank = []}

{- | A need-lines beyond the grid lines of the column is unmet and goes to
the next column; any other goes on until its lines are free or the
column is empty, the figures sent on and the continued notes counted in
the columns gone on to (golem-layout ADR 0025).
-}
applyNeed :: Env -> St -> St
applyNeed env st = case sNeed st of
  Nothing -> st
  Just (sp, n)
    | n > cap env st ->
        let st1 = addUnmet (UnmetNeedLines sp n) st {sNeed = Nothing}
         in if isEmpty st1 then st1 else nextColumn env st1
    | otherwise -> keep env st {sNeed = Nothing} (const n)

-- | At least one line and the lines placed, at most maxLines.
adjustLines :: Env -> St -> SrcSpan -> Int -> St
adjustLines env st sp k =
  let capacity = envCapacity env
      want = sAdjust st + k
      placed = sUsed st + sNoteLines st
      got = max (max 1 placed - capacity) (min (envMaxLines env - capacity) want)
      st1 = st {sAdjust = got}
      limit
        | got < want = AdjustNoRoom
        | placed >= 1 = AdjustLinesPlaced
        | otherwise = AdjustOneLine
   in if got /= want then addUnmet (UnmetAdjust sp got limit) st1 else st1

-- | A paragraph before a no-break or a keep-with-next keeps its last lines with what follows.
placeFlow :: Env -> St -> Flow -> [Flow] -> St
placeFlow env st f rest = case (f, keptNeed env rest) of
  (FParagraph kp ls, Just n) -> placeKept env (previousKeep kp) (placeLines env kp) st True ls n
  -- a stanza keeps its last verse lines as a paragraph its last lines (docs/adr/0205)
  (FStanza kp vs, Just n) -> placeKept env kp (placeStanza env kp) st True vs n
  (FContinued kp ls, Just n) -> placeKept env (previousKeep kp) (placeLines env kp) st False ls n
  (FDefTerm ls, Just n) ->
    let initial = case keepAhead rest of
          Just (_, requested, _, _) | requested > 0 -> st
          _ -> keep env st (\s -> needIn env s (termNeed ls) (nextNeed env rest))
     in placeKept env (previousKeep defaultKeep) (placeLines env defaultKeep) initial True ls n
  _ -> place env st f rest
  where
    previousKeep kp = case keepAhead rest of
      Just (_, requested, _, _)
        | requested > 0 ->
            kp {kLast = max (kLast kp) requested, kFirst = max 2 (kFirst kp)}
      _ -> kp

{- | The last kLast lines, or the whole paragraph of kLast lines or fewer
or of fewer than kFirst + kLast, go to the next column, not from an
empty one; of a stanza, its verse lines (docs/adr/0205, docs/adr/0261).
With 'defaultKeep', the last two lines, or the whole of three or fewer.
-}
placeKept :: Env -> Keep -> (St -> Bool -> [a] -> St) -> St -> Bool -> [a] -> Need -> St
placeKept env kp placeIn st isStart ls n =
  let st1 = placeIn st isStart ls
      len = length ls
      (front, back) = splitAt (len - (if kAll kp || len <= kLast kp || len - kLast kp < kFirst kp then len else kLast kp)) ls
      stA = placeIn st isStart front
      here = placeIn stA (isStart && null front) back
      fits s = needIn env s mempty n <= free env s
      fitsHere = sPage here == sPage stA && sColumn here == sColumn stA && fits here
   in if fits st1
        then st1
        else
          if fitsHere
            then here
            else if isEmpty stA || heldHere env stA then st1 else placeIn (nextColumn env stA) (isStart && null front) back

{- | A no-break or a keep-with-next waiting for the next flow
(docs/adr/0261): at the place of the first, the larger of the lines they
ask for.
-}
waitFor :: Unmet -> (Int, Bool) -> St -> St
waitFor u k st = case sNoBreak st of
  [] -> st {sNoBreak = [(u, sPage st, sColumn st, length (sSlots st), k)]}
  ws@((_, p, c, n, (k0, l0)) : _) ->
    let both = bimap (max k0) (l0 ||) k
     in st {sNoBreak = [(u', p, c, n, both) | (u', _, _, _, _) <- ws <> [(u, p, c, n, k)]]}

{- | The flow after a no-break must start in the column where the flow
before it ended; after a keep-with-next, its first part (docs/adr/0261).
Each control waiting that is not met is recorded.
-}
checkNoBreak :: St -> St
checkNoBreak st = case sNoBreak st of
  [] -> st
  ws@((_, p, c, n, (k, linesOnly)) : _) ->
    let linesIn = sum . map (slotLineCount linesOnly . snd) . drop n
        added
          | (sPage st, sColumn st) == (p, c) = linesIn (sSlots st)
          | otherwise = maximum (0 : [linesIn (poSlots po) | po <- sDone st, poNumber po == p, poColumn po == c])
        met = added >= max 1 k
     in (if met then st else foldl' (\s' (u, _, _, _, _) -> addUnmet u s') st ws) {sNoBreak = []}

-- | The lines a slot holds; one for a figure or a code block, none when only the lines count.
slotLineCount :: Bool -> Slotted -> Int
slotLineCount linesOnly = \case
  SLine _ -> 1
  SHeading _ m -> max 1 m
  _ -> if linesOnly then 0 else 1

applyBreaks :: Env -> St -> St
applyBreaks env st = foldl' (applyBreak env) st {sBreaks = []} (sBreaks st)

applyBreak :: Env -> St -> Pending -> St
applyBreak env st = \case
  PendingBreak k -> applyBreakKind env st k
  PendingStart of_ k -> startBefore env st of_ k

{- | The start of a section (docs/adr/0260) or of a paragraph of a style
with page-break (docs/adr/0261): to the next column unless the column is
empty; to the next page unless the page is empty; to an odd or an even
page, as @page-break recto and verso. Before a page, the figures sent on
and the continued notes are placed first. The page a section starts on
is recorded as its first page.
-}
startBefore :: Env -> St -> StartOf -> BreakKind -> St
startBefore env st of_ k =
  let st1 = case k of
        BreakColumn -> if isEmpty st then st else nextColumn env st
        BreakPage ->
          let st0 = flushDeferred env st
           in if isEmpty st0 && sColumn st0 == 0 then st0 else nextPage env st0
        BreakRecto -> parityStart env odd st
        BreakVerso -> parityStart env even st
   in case of_ of
        OfSection i -> st1 {sSections = sSections st1 <> [(i, sPage st1)]}
        OfParagraph _ -> st1

applyBreakKind :: Env -> St -> BreakKind -> St
applyBreakKind env st = \case
  BreakPage -> breakPage env st
  BreakRecto -> parityStart env odd st
  BreakVerso -> parityStart env even st
  BreakColumn
    -- a waiting turned figure is placed first, on a page of its own (golem-driver ADR 0034, 0039)
    | csColumns (sSet st) > 1 && not (any isPageFigure (sDeferred st)) -> nextColumn env st
    | otherwise -> breakPage env st

breakPage :: Env -> St -> St
breakPage env st
  -- the page is closed even when empty; an empty page is blank
  | isEmpty st && sColumn st == 0 && not (afterPageFigure st) = blankPage env st
  -- the page after a turned figure is already a new page (golem-driver ADR 0039)
  | isEmpty st && sColumn st == 0 = st
  | otherwise = nextPage env st

place :: Env -> St -> Flow -> [Flow] -> St
place env st f rest = case f of
  FBookPart _ _ _ _ body -> foldBody st body
  FRuled {} -> placeRuled env st f rest
  FParagraph kp ls -> placeLines env kp st True ls
  FStanza kp vs -> placeStanza env kp st True vs
  FContinued kp ls -> placeLines env kp st False ls
  -- the space before a table only below the first line of a column (golem-driver ADR 0031);
  -- in the columns gone on to, the header and the first row are kept together (golem-layout ADR 0025)
  -- the caption with the lines it touches (docs/adr/0262)
  FTable i sp0 h rows capt below
    | envKeepParts env /= KeepColumn ->
        let space = if sUsed st == top st then 0 else sp0
            started = if space <= free env st then st {sUsed = sUsed st + space} else nextColumn env st
         in placeTableAcross env started i h rows capt below
    | otherwise ->
        let sp = if sUsed st == top st then 0 else sp0
            headed = tableHead h rows capt below
         in if sp + headed <= free env st || isEmpty st
              then tableAt env st i (sUsed st + max 0 (min sp (free env st))) headed (\s -> placeTable env s i h rows capt below)
              else let st1 = keep env (nextColumn env st) (const headed) in tableAt env st1 i (sUsed st1) headed (\s -> placeTable env s i h rows capt below)
  FDefTerm ls
    | envKeepParts env /= KeepColumn -> placeLines env (Keep 1 1 False) st True ls
    | otherwise -> placeLines env defaultKeep (keep env st (\s -> needIn env s (termNeed ls) need)) True ls
  -- the notes of a heading count as the notes of a line do (golem-layout ADR 0013)
  FHeading _ recto n ls ->
    let st1 = if recto then parityStart env odd st else keep env st (\s -> needIn env s (Need n (noteLinesOf ls)) need)
        st2 = if headingNeed env st1 n ls <= free env st1 || isEmpty st1 then st1 else nextColumn env st1
     in putBlock env st2 n ls
  -- figures keep the order written: after a figure sent on, the next ones wait too (golem-layout ADR 0015)
  FFigure i n labels marks
    | not (null (sDeferred st)) -> st {sDeferred = sDeferred st <> [f]}
    | otherwise -> case spotOf env st i n of
        SpotAt u -> putSlot st {sUsed = u} n (SFigure i) labels marks
        -- left out of an empty column by the frames of wrap around (root ADR 0456)
        SpotUnplaced -> addUnmet (UnplacedBlock i) st
        SpotNone -> st {sDeferred = sDeferred st <> [f]}
  -- a turned figure takes a page with nothing on it, or waits (golem-driver ADR 0034)
  FPageFigure i labels marks
    | null (sDeferred st) && sColumn st == 0 && sUsed st == 0 && null (sNotes st) && sNoteLines st == 0 -> pageFigure env st {sAdjust = 0} i labels marks
    | otherwise -> st {sDeferred = sDeferred st <> [f]}
  FWrapped i n labels marks beside ->
    let st0 = flushFigures env st
        size = max n (length beside)
        -- the continued notes take the foot of the columns gone on to (golem-layout ADR 0025);
        -- the figure fits with the notes of its side lines and their separator (root ADR 0443)
        kept = keep env st0 (\s -> needIn env s (Need size (noteLinesOf beside)) mempty)
     in case spotOf env kept i n of
          -- past the frames of wrap around it overlaps, with its side lines (root ADR 0456)
          SpotAt u ->
            let st1 = kept {sUsed = u}
                st2 = putSlot st1 0 (SWrapped i) labels marks
                placed = placeLines env defaultKeep st2 False beside
                -- the side lines their notes send on take the next column from its top (golem-driver ADR 0005)
                sentOn = (sPage placed, sColumn placed) /= (sPage st2, sColumn st2)
             in if sentOn then placed else placed {sUsed = max (sUsed st1 + size) (sUsed placed)}
          SpotNone -> place env (nextColumn env kept) f rest
          -- left out, its side lines are lines of the column (root ADR 0456)
          SpotUnplaced -> placeLines env defaultKeep (addUnmet (UnplacedBlock i) kept) False beside
  FBreak k -> st {sBreaks = sBreaks st <> [PendingBreak k]}
  FSection of_ k -> st {sBreaks = sBreaks st <> [PendingStart of_ k]}
  FCode g caption first cont ls -> placeCode env st (g, caption, first, cont) True ls
  FSwitchColumns set ->
    let st1 = flushDeferred env st
     in -- the set ends at the type area or above the footnotes, whichever comes first (root ADR 0025, root ADR 0030, root ADR 0441)
        if (csColumns (envBase env) == 1 && typeAreaFree env st1 > 0) || (isEmpty st1 && sColumn st1 == 0)
          then startSet env st1 set (sUsed st1)
          else (nextPage env st1) {sSet = set {csFirstLine = 0}}
  FRestoreColumns
    | isEmpty st && sColumn st == 0 && top st == 0 -> st {sSet = (envBase env) {csFirstLine = 0}}
    | otherwise -> (nextPage env st) {sSet = (envBase env) {csFirstLine = 0}}
  -- nothing at the top of a column, nor of a part of a box (docs/adr/0271)
  FSpace n
    | sUsed st == top st || atBoxStart st -> st
    | otherwise -> st {sUsed = sUsed st + max 0 (min n (free env st))}
  -- the controls of page breaks are handled in placeAll (docs/adr ADR 0030)
  FNoBreak _ -> st
  FNoBreakLines {} -> st
  FKeepNext {} -> st
  FNeedLines _ _ -> st
  FAdjustLines _ _ -> st
  FBlank _ _ -> st
  {- a box (docs/adr/0271): where its grid lines before, the first part
  of its body and its grid lines after fit; its body placed as outside a
  box, each part of it in a column closed by its grid lines after; the
  room kept for those that its last part does not take, as when that part
  has no text line, goes to the continued notes first (root ADR 0444) -}
  FBoxed i kb ka body ->
    let st1 = keep env st (\s -> kb + ka + needIn env s mempty (nextNeed env body))
        inBox = foldBody (openBox st1 {sBox = Just (BoxAt i kb ka 0 False)}) body
        closed = closeBox inBox
        ends = [bsLast b + 1 | b <- drop (length (sBoxes inBox)) (sBoxes closed)]
     in drainPendingNotes env closed {sBox = Nothing, sUsed = maximum (sUsed closed : ends)}
  where
    need = nextNeed env rest
    foldBody s0 body = foldl' (\s (g, more) -> step env s g (more <> rest)) s0 [(g, drop k body) | (k, g) <- zip [1 ..] body]

{- | A code block: as many rows as their grid lines fit in the column, the
rest in the next column; at least one row in an empty column (golem-driver ADR 0017).
The first part has its caption and its first rows; a part before the
last has a row for the text that it continues (golem-driver ADR 0023).
-}
placeCode :: Env -> St -> (CodeGeometry, Int, Int, Bool) -> Bool -> [LineBox] -> St
placeCode env st0 c isFirst ls = placeCodeFrom env st0 (maybe 0 lbId (listToMaybe ls)) c isFirst ls

{- | 'placeCode' of a code block by the id of its first row: a part ends
before an area of a frame of wrap around as at the end of a column, and
the next part is placed past it in the column (root ADR 0456). An empty
column that the least part fits without the frames, but past them not,
leaves the code block out.
-}
placeCodeFrom :: Env -> St -> Int -> (CodeGeometry, Int, Int, Bool) -> Bool -> [LineBox] -> St
placeCodeFrom _ st _ _ _ [] = st
placeCodeFrom env st ident c@(g, cap0, first, cont) isFirst ls =
  let len = length ls
      captionRows = if isFirst then cap0 else 0
      least = if isFirst then min len (max 1 first) else 1
      spanOf j = captionRows + codeSpan g (j + (if cont && j < len then 1 else 0))
      areas = avoidHere env st ident
      -- the areas of the frames that end the room of the column before its end
      cutsRoom s = [a | (a, b) <- areas, b > sUsed s, a < sUsed s + free env s]
      room = minimum (free env st : [max 0 (a - sUsed st) | a <- cutsRoom st])
      k0 = length (takeWhile (\j -> spanOf j <= room) [1 .. len])
      put k =
        let (part, rest) = splitAt k ls
            n = spanOf k
            l0 = maybe 0 lbId (listToMaybe part)
            st1 = putSlot st n (SCode l0 k n) (concatMap lbLabels part) (concatMap lbMarks part)
         in -- the next part past the frame in the column, or in the next column
            if null rest then st1 else placeCodeFrom env (if null (cutsRoom st1) then nextColumn env st1 else st1) ident c False rest
   in if k0 >= least
        then put k0
        else
          if null (cutsRoom st)
            then if isEmpty st then put least else placeCodeFrom env (nextColumn env st) ident c isFirst ls
            else case spotOf env st ident (spanOf least) of
              SpotAt v
                | v /= sUsed st -> placeCodeFrom env st {sUsed = v} ident c isFirst ls
                -- an empty column that it does not fit even without the frames
                | otherwise -> put least
              SpotUnplaced -> addUnmet (UnplacedBlock ident) st
              SpotNone -> placeCodeFrom env (nextColumn env st) ident c isFirst ls

{- | Lines of one paragraph; orphans and widows are moved, by the keep of
the paragraph (docs/adr/0261). A paragraph of keep-all-lines that its
column does not hold starts the next column; one that an empty column
does not hold either is broken, and that is recorded ('SplitKept'). A
part shorter than its keep placed in an empty column is recorded
('ShortPart').
-}
placeLines :: Env -> Keep -> St -> Bool -> [LineBox] -> St
placeLines _ _ st _ [] = st
placeLines env kp0 st0 isStart0 ls0@(l0 : _) = go kp0 st0 isStart0 ls0
  where
    pid = lbId l0
    go _ st _ [] = st
    go kp st isStart ls =
      let n = length ls
          k0 = fitting env st ls
          -- a column of nothing but headings places a line as an empty one does,
          -- when the line and a line of its notes are left room (golem-layout ADR 0019)
          emptyish = isEmpty st || (sHeadingOnly st && roomForLine env st ls)
          k2 = splitAtBreak kp isStart n k0
          forced = k2 == 0 && emptyish
          k = if forced then max 1 (min n k0) else k2
       in if sAdjust st < 0 && isEmpty st && not (roomForLine env st ls)
            then go kp (nextColumn env st) isStart ls
            else
              if kAll kp && isStart && k0 < n
                then
                  if isEmpty st || sHeadingOnly st
                    then go kp {kAll = False} (addUnmet (SplitKept pid) st) isStart ls
                    else go kp (nextColumn env st) isStart ls
                else
                  if k >= n
                    then foldl' (putLine env) st ls
                    else
                      let short =
                            [ShortPart FirstPart pid (kFirst kp) k | forced, isStart, k < kFirst kp]
                              <> [ShortPart LastPart pid (kLast kp) (n - k) | forced, n - k < kLast kp]
                          st1 = foldl' (flip addUnmet) (foldl' (putLine env) st (take k ls)) short
                       in go kp (nextColumn env st1) (isStart && k == 0) (drop k ls)

{- | The verse lines of a stanza (docs/adr/0180): a verse line is not
broken between columns, and a column neither ends with the first verse
line of a stanza alone nor starts with its last alone, as 'placeLines'
counts lines. A stanza that cannot be placed so in an empty column, or in
a column of nothing but headings, places as many verse lines as fit, or
breaks its first verse line as a paragraph when none fits.
-}
placeStanza :: Env -> Keep -> St -> Bool -> [[LineBox]] -> St
placeStanza _ _ st _ [] = st
placeStanza env kp0 st0 isStart0 vs0 = go kp0 st0 isStart0 vs0
  where
    pid = maybe 0 lbId (listToMaybe (concat vs0))
    go _ st _ [] = st
    go kp st isStart vs =
      let n = length vs
          room = fitting env st (concat vs)
          k0 = length (takeWhile (<= room) (drop 1 (scanl (+) 0 (map length vs))))
          k2 = splitAtBreak kp isStart n k0
          putVerses s = foldl' (putLine env) s . concat
          split forced k =
            let short =
                  [ShortPart FirstPart pid (kFirst kp) k | forced, isStart, k < kFirst kp]
                    <> [ShortPart LastPart pid (kLast kp) (n - k) | forced, n - k < kLast kp]
             in go kp (nextColumn env (foldl' (flip addUnmet) (putVerses st (take k vs)) short)) False (drop k vs)
          emptyish = isEmpty st || (sHeadingOnly st && roomForLine env st (concat vs))
       in if kAll kp && isStart && k0 < n
            then
              if isEmpty st || sHeadingOnly st
                then go kp {kAll = False} (addUnmet (SplitKept pid) st) isStart vs
                else go kp (nextColumn env st) isStart vs
            else
              if k2 >= n
                then putVerses st vs
                else
                  if k2 > 0
                    then split False k2
                    else
                      if emptyish
                        then case vs of
                          v : more
                            | k0 == 0 ->
                                let st1 = placeLines env defaultKeep st isStart v
                                    short = [ShortPart LastPart pid (kLast kp) (n - 1) | n - 1 < kLast kp, not (null more)]
                                 in go kp (foldl' (flip addUnmet) st1 short) False more
                          _ -> split True k0
                        else go kp (nextColumn env st) isStart vs

{- | A paragraph or heading with rules (golem-driver ADR 0027): the area of
its rule before, its lines and the area of its rule after as one block.
A paragraph's block fits by its grid lines alone, its notes go on when
they do not fit; a heading's counts its notes (golem-layout ADR 0013).
A block that ends at the end of the column counts its rule after at
the edge; one that does not fit an empty column is broken.
-}
placeRuled :: Env -> St -> Flow -> [Flow] -> St
placeRuled env st fr rest = case sJoin st of
  Just j
    | frJoined fr,
      Just b <- frBefore fr,
      not (isRecto (frBody fr)),
      Just placed <- settleRuled env st fr rest (Just (j, b)) ->
        placed
  -- a block that cannot share the area in this column starts in the next one, after the rule of its own (root ADR 0449)
  Just _
    | frJoined fr,
      isJust (frBefore fr),
      not (isRecto (frBody fr)) ->
        placeRuled env (nextColumn env (flushJoin env st)) fr rest
  Just _ -> placeRuled env (flushJoin env st) fr rest
  Nothing ->
    let st1 = if isRecto (frBody fr) then parityStart env odd st else st
        -- a ruled paragraph of keep-with-next goes whole with the first part of what follows (docs/adr/0261)
        keepNext = case (frBody fr, keepAhead rest) of
          (RuledLines {}, Just (_, _, n, _)) | n > 0 -> keptNeed env rest
          _ -> Nothing
        st2
          | isHeadingBody (frBody fr) && not (isRecto (frBody fr)) = keep env st1 (\s -> needIn env s (planParts fr (planOf env s fr rest Nothing)) (nextNeed env rest))
          | Just kn <- keepNext = keep env st1 (\s -> needIn env s (planParts fr (planOf env s fr rest Nothing)) kn)
          | otherwise = st1
     in case settleRuled env st2 fr rest Nothing of
          Just placed -> placed
          Nothing
            | isEmpty st2 -> splitRuled env st2 fr rest
            | otherwise ->
                let st3 = nextColumn env st2
                 in fromMaybe (splitRuled env st3 fr rest) (settleRuled env st3 fr rest Nothing)

{- | A block placed here when its block fits the room. Its rule after
shares an area with the next block's rule before only when that block
goes on in this column (golem-driver ADR 0027, 「隣り合う罫線」);
otherwise the area is its own and is counted in the block, so that the
rule stays in the column.
-}
settleRuled :: Env -> St -> Flow -> [Flow] -> Maybe ((Int, RuleGrid, RuleSide, Int), RuleSide) -> Maybe St
settleRuled env st fr rest joined =
  let fits plan = planNeed env st fr plan <= free env st
      shared = planOf env st fr rest joined
      own = planOf env st fr [] joined
      placed = commitRuled env st fr shared
   in if fits shared && settlesAfter env placed rest
        then Just placed
        else if fits own then Just (commitRuled env st fr own) else Nothing

{- | Whether the rule after that waits stays in the column: the next block
takes it into its area in this column, or its own area fits the room.
-}
settlesAfter :: Env -> St -> [Flow] -> Bool
settlesAfter env st rest = case sJoin st of
  Nothing -> True
  Just j -> case flattenBookParts rest of
    next@FRuled {frJoined = True, frBefore = Just b} : later
      | not (isRecto (frBody next)),
        isJust (settleRuled env st next later (Just (j, b))) ->
          True
    _ -> maybe True ((<= free env st) . snd) (ownAfter env st)

commitRuled :: Env -> St -> Flow -> Plan -> St
commitRuled env st fr (k1, before, k2, after, waiting) =
  let st1 = st {sRules = sRules st <> before, sUsed = sUsed st + k1, sJoin = Nothing}
      st2 = case frBody fr of
        RuledLines _ ls -> foldl' (\s' (j, l) -> putLineKeeping env (length ls - 1 - j + k2) s' l) st1 (zip [0 ..] ls)
        RuledHeading _ n ls -> (putBlock env st1 n ls) {sHeadingOnly = isEmpty st || sHeadingOnly st}
   in st2 {sRules = sRules st2 <> after, sUsed = min (sUsed st2 + k2) (max (sUsed st2) (cap env st2 - sNoteLines st2)), sJoin = waiting}

{- | A block that does not fit an empty column (golem-driver ADR 0027,
0035): the lines of a paragraph are broken as any paragraph's, without
its rules and their areas; a heading drops its rule after, then its
rule before, until it fits.
-}
splitRuled :: Env -> St -> Flow -> [Flow] -> St
splitRuled env st0 fr rest =
  let st = if isEmpty st0 then st0 else nextColumn env st0
      (k1, before, _, _, _) = planOf env st fr rest Nothing
   in case frBody fr of
        RuledLines kp ls -> placeLines env kp st True ls
        RuledHeading _ n ls ->
          let (_, _, k2, after, _) = planOf env st fr [] Nothing
           in if k1 + headingNeed env st n ls + k2 <= free env st
                then commitRuled env st fr (k1, before, k2, after, Nothing)
                else
                  if k1 + headingNeed env st n ls <= free env st
                    then commitRuled env st fr (k1, before, 0, [], Nothing)
                    else putBlock env st n ls

-- | The rule after of the block before, in its own area: nothing shares it.
flushJoin :: Env -> St -> St
flushJoin env st = case ownAfter env st of
  Nothing -> st
  Just (rule, k) -> st {sRules = sRules st <> [rule], sUsed = sUsed st + min k (free env st), sJoin = Nothing}

-- | The rule after that waits, in its own area: the rule and the grid lines of the area.
ownAfter :: Env -> St -> Maybe (PlacedRule, Int)
ownAfter env st = case sJoin st of
  Nothing -> Nothing
  Just (aid, g@(RuleGrid p h), a, aLast) ->
    let (ki, offi) = ruleAfter g a 0
        (k, off)
          | aLast + 1 + ki >= cap env st - sNoteLines st = ruleAfterAtEnd g a {rsdOutside = if sNoteLines st > 0 then Nothing else rsdOutside a}
          | otherwise = (ki, offi)
     in Just (PlacedRule aid False (fromIntegral aLast * p + h + off), k)

{- | A table: rows whole, a page break between rows repeats the header
without its labels, notes and marks (golem-driver ADR 0008). The
repeated header and the next row go on past the columns that the figures
sent on and the continued notes leave too little of (golem-layout ADR 0025).
-}
placeTable :: Env -> St -> Int -> [LineBox] -> [[LineBox]] -> [LineBox] -> Bool -> St
placeTable env st i h rows capt below =
  let st0 = if below then st else foldl' (putLine env) st capt
      start = sUsed st0
      st1 = foldl' (putLine env) st0 h
      -- the last row takes the caption below with it (docs/adr/0262)
      withCaption rest r = if below && null rest then r <> capt else r
      -- a part of the table: from its first grid line, with the header row or not
      rowsFrom stc first headed [] = segment stc first headed
      rowsFrom stc first headed (r : rest)
        -- a row over a frame of wrap around goes on past it in the column, without the header row again (root ADR 0456)
        | past /= sUsed stc && length r' <= cap env stc - past - sNoteLines stc =
            rowsFrom (segment stc first headed) {sUsed = past} past False (r : rest)
        | past == sUsed stc && (fitting env stc r' >= length r' || sUsed stc == first + (if headed then length h else 0)) = rowsFrom (foldl' (putLine env) stc r) first headed rest
        | otherwise =
            let closed = segment stc first headed
                fresh0 = keep env (nextColumn env closed) (const (length h + length r'))
                -- the header row again and the row off the frames of wrap around (root ADR 0456)
                fresh = case spotOf env fresh0 i (length h + length r') of
                  SpotAt v -> fresh0 {sUsed = v}
                  _ -> fresh0
                repeated = foldl' (putLine env) fresh [l {lbNotes = [], lbLabels = [], lbMarks = []} | l <- h]
             in rowsFrom repeated (sUsed fresh) True (r : rest)
        where
          r' = withCaption rest r
          past = clearFrom (avoidHere env stc i) (sUsed stc) (length r')
      headerEnd first headed = if null h || not headed then Nothing else Just (first + length h - 1)
      segment stc first headed
        | sUsed stc <= first = stc
        | otherwise = stc {sTables = sTables stc <> [TableSegment i first (headerEnd first headed) (sUsed stc - 1)]}
      placed = rowsFrom st1 start True rows
   in if below then foldl' (putLine env) placed capt else placed

{- | A table from grid line @u@ of its column, placed by @continue@ (root
ADR 0456): there when its header row and first row (@headed@ grid lines)
miss the areas of the frames of wrap around; else past them when they fit
there, else in the next column. An empty column that they fit without the
frames, but past them not, leaves the table out.
-}
tableAt :: Env -> St -> Int -> Int -> Int -> (St -> St) -> St
tableAt env st i u headed continue = case spotFrom env st i u headed of
  SpotAt v -> continue st {sUsed = v}
  SpotUnplaced -> addUnmet (UnplacedBlock i) st
  SpotNone ->
    let st1 = keep env (nextColumn env st) (const headed)
     in tableAt env st1 i (sUsed st1) headed continue

{- | Within page/spread retention, a header is repeated when a physical
page changes, while columns of the same page may separate whole rows.
-}
placeTableAcross :: Env -> St -> Int -> [LineBox] -> [[LineBox]] -> [LineBox] -> Bool -> St
placeTableAcross env initial ident header rows caption below =
  finish (go True initial (sUsed initial) Nothing groups)
  where
    groups = [(False, caption) | not below && not (null caption)] <> [(True, header) | not (null header)] <> [(False, row) | row <- rows] <> [(False, caption) | below && not (null caption)]
    repeated = [line {lbNotes = [], lbLabels = [], lbMarks = []} | line <- header]
    record state first headerEnd
      | sUsed state <= first = state
      | otherwise =
          let segment = TableSegment ident first headerEnd (sUsed state - 1)
           in case reverse (sTables state) of
                previous : earlier
                  | tsTable previous == ident && tsLast previous + 1 == first ->
                      state {sTables = reverse earlier <> [previous {tsLast = tsLast segment, tsHeaderEnd = tsHeaderEnd previous <|> headerEnd}]}
                _ -> state {sTables = sTables state <> [segment]}
    finish (state, first, headerEnd) = record state first headerEnd
    go _ state first headerEnd [] = (state, first, headerEnd)
    go True state first headerEnd tailGroups@[(False, row), (False, captionLines)]
      | below,
        not (null caption),
        captionLines == caption,
        Just source <- envBookPartSpan env =
          let closed = record state first headerEnd
              run start _ =
                let mustRepeat = sPage start /= sPage state && not (null repeated)
                    withHeader = if mustRepeat then foldl' (putLine env) start repeated else start
                    headingEnd = if mustRepeat then Just (sUsed withHeader - 1) else Nothing
                 in finish (go False withHeader (sUsed start) headingEnd tailGroups)
              retained = map lbId (row <> captionLines)
              kept = placeBookPart env run closed (envKeepParts env) source "表の末尾とキャプション" retained [FContinued defaultKeep (row <> captionLines)]
           in (kept, sUsed kept, Nothing)
    go retain state first headerEnd ((isHeader, lines') : remaining) = placeGroup False state first headerEnd
      where
        placeGroup retried here beginning headingEnd
          | fitting env here lines' >= length lines' || isEmpty here =
              let isCaption = not (null caption) && lines' == caption
                  bordered = if isCaption && below then record here beginning headingEnd else here
                  after = foldl' (putLine env) bordered lines'
                  beginning' = if isCaption then sUsed after else beginning
                  headingEnd'
                    | isCaption = Nothing
                    | isHeader = Just (sUsed after - 1)
                    | otherwise = headingEnd
               in go retain after beginning' headingEnd' remaining
          | otherwise =
              let closed = record here beginning headingEnd
                  fresh = nextColumn env closed
                  mustRepeat = sPage fresh /= sPage here && not isHeader && not retried && not (null repeated)
                  afterHeader = if mustRepeat then foldl' (putLine env) fresh repeated else fresh
                  endHeader = if mustRepeat then Just (sUsed afterHeader - 1) else Nothing
               in placeGroup (retried || mustRepeat) afterHeader (sUsed fresh) endHeader

{- | The label of each page by its number (docs/adr/0260), from the
sections given and the first pages the pagination recorded.
-}
pageLabels :: Map Int Section -> [PageOutAt position] -> Map Int PageLabel
pageLabels sections ps =
  pageLabelsOf sections (Map.fromListWith (flip (<>)) [(poNumber p, poSections p) | p <- ps]) (maximum (0 : map poNumber ps))

-- | The page label of each label (docs/adr/0260).
labelPages :: Map Int Section -> [PageOutAt position] -> Map Text PageLabel
labelPages sections ps =
  let labels = pageLabels sections ps
   in Map.fromList [(l, Map.findWithDefault (plainLabel (poNumber p)) (poNumber p) labels) | p <- ps, l <- poLabels p]

-- | The page label of each index mark (golem-driver ADR 0007, docs/adr/0260).
markPages :: Map Int Section -> [PageOutAt position] -> Map SrcSpan PageLabel
markPages sections ps =
  let labels = pageLabels sections ps
   in Map.fromList [(m, Map.findWithDefault (plainLabel (poNumber p)) (poNumber p) labels) | p <- ps, m <- poMarks p]

maxIterations :: Int
maxIterations = 5

{- | Lays out with assumed page numbers until the page numbers no longer
change (S2). References start with a one-digit stand-in. After
'maxIterations' rounds, the labels whose pages still move are returned.
-}
resolvePageRefs :: (Map Text Integer -> [PageOut]) -> Either [Text] [PageOut]
resolvePageRefs layout = go 1 Map.empty
  where
    go i assumed =
      let pages = layout assumed
          actual = Map.map (toInteger . plIndex) (labelPages Map.empty pages)
       in if actual == assumed || (i > 1 && actual `Map.isSubmapOf` assumed && assumed `Map.isSubmapOf` actual)
            then Right pages
            else
              if i >= maxIterations
                then Left (Map.keys (Map.filter id (Map.mergeWithKey (\_ a b -> Just (a /= b)) (Map.map (const True)) (Map.map (const True)) actual assumed)))
                else go (i + 1) actual
