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
    ColumnSet (..),
    NoteId (..),
    NoteBody (..),
    Flow (..),
    Slotted (..),
    PageOut (..),
    Unmet (..),
    TableSegment (..),
    RuledBody (..),
    PlacedRule (..),
    HeadingBlock (..),
    headingBlock,
    paginate,
    paginateIn,
    paginateWithin,
    labelPages,
    markPages,
    resolvePageRefs,
    maxIterations,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, listToMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry, codeSpan)
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..), ruleAfter, ruleAfterAtEnd, ruleBefore, ruleBeforeAtStart, rulesJoined)
import Golem.Syntax (SrcSpan)

{- | A footnote in the book (golem-driver ADR 0018): the span of the note,
and its place among the notes of the same span in one paragraph (from
0). Notes numbered in different files never share a key.
-}
data NoteId = NoteId !SrcSpan !Int
  deriving stock (Eq, Ord, Show)

data NoteBody = NoteBody {nbId :: !NoteId, nbLines :: !Int}
  deriving stock (Eq, Show)

data LineBox = LineBox
  { lbId :: !Int,
    lbNotes :: ![NoteBody],
    lbLabels :: ![Text],
    -- | index marks on the line (golem-driver ADR 0007)
    lbMarks :: ![SrcSpan],
    {- | how far the ruby and kenten of the line reach out of the face of
    the line toward the line before it, in sp (golem-driver ADR 0033);
    pagination does not read it
    -} lbOverhang :: !Integer
  }
  deriving stock (Eq, Show)

data Flow
  = FParagraph [LineBox]
  | -- | a heading, placed whole over 'fhSpan' grid lines (golem-driver ADR 0003)
    FHeading {fhLevel :: !Int, fhRecto :: !Bool, fhSpan :: !Int, fhLines :: [LineBox]}
  | FDefTerm [LineBox]
  | -- | a figure with its caption, in grid lines
    FFigure {ffId :: !Int, ffLines :: !Int, ffLabels :: ![Text], ffMarks :: ![SrcSpan]}
  | -- | a wrapped figure and the shortened lines set beside it (ADR 0004)
    FWrapped {fwId :: !Int, fwLines :: !Int, fwLabels :: ![Text], fwMarks :: ![SrcSpan], fwBeside :: [LineBox]}
  | {- | a figure turned onto a page of its own (golem-driver ADR 0034): on
    the page if nothing is on it, else waiting with the figures sent on,
    at the start of a later page
    -}
    FPageFigure {fpId :: !Int, fpLabels :: ![Text], fpMarks :: ![SrcSpan]}
  | {- | the rest of a paragraph whose first lines are beside a wrapped
    figure: no orphan rule for its first line (golem-driver ADR 0005)
    -}
    FContinued [LineBox]
  | {- | a table: the grid lines of space before it (not at the first line
    of a column), its header row (none when empty) and body rows, in grid
    lines (golem-driver ADR 0008, 0031)
    -}
    FTable {ftId :: !Int, ftSpaceBefore :: !Int, ftHeader :: ![LineBox], ftRows :: ![[LineBox]]}
  | {- | empty grid lines, as between stanzas of verse (docs/adr ADR 0003);
    nothing at the top of a page
    -}
    FSpace !Int
  | -- | a forced break before what follows (docs/adr ADR 0017)
    FBreak !BreakKind
  | {- | a code block: its rows, broken between any two of them; each part
    takes the grid lines of 'codeSpan' (golem-driver ADR 0017). The first
    part has the grid lines of the caption above it and at least
    'fcFirst' rows; with 'fcContinued', each part but the last has a row
    more for the text that it continues (golem-driver ADR 0023).
    -}
    FCode
      { fcGeometry :: !CodeGeometry,
        fcCaption :: !Int,
        fcFirst :: !Int,
        fcContinued :: !Bool,
        fcRows :: [LineBox]
      }
  | {- | a paragraph or a heading with rules (golem-driver ADR 0027): the
    areas of its rules, its lines and the areas are placed as one block,
    not broken between columns. 'frId' names its rules in 'PlacedRule';
    with 'frJoined', its rule before shares one area with the rule after
    of the ruled block just before it; 'frNextOverhang' is the overhang of
    the first line after it.
    -}
    FRuled
      { frId :: !Int,
        frBefore :: !(Maybe RuleSide),
        frAfter :: !(Maybe RuleSide),
        frJoined :: !Bool,
        frGrid :: !RuleGrid,
        frNextOverhang :: !Integer,
        frBody :: !RuledBody
      }
  | -- | the start of the index in its own columns (docs/adr ADR 0025)
    FSwitchColumns !ColumnSet
  | -- | the end of the index: the next page, in the columns of the page
    FRestoreColumns
  | -- | no page or column break between the flows around (docs/adr ADR 0030)
    FNoBreak !SrcSpan
  | -- | go to the next column unless this many grid lines are free
    FNeedLines !SrcSpan !Int
  | -- | change the grid lines of the current column
    FAdjustLines !SrcSpan !Int
  | {- | blank lines before what follows (docs/adr ADR 0046), in its
    column; dropped at the top of a column
    -}
    FBlank !SrcSpan !Int
  deriving stock (Eq, Show)

{- | What a ruled block holds (golem-driver ADR 0027): the lines of a
paragraph, or a heading (recto, grid lines, lines) as 'FHeading'.
-}
data RuledBody
  = RuledLines ![LineBox]
  | RuledHeading {rhRecto :: !Bool, rhSpan :: !Int, rhLines :: ![LineBox]}
  deriving stock (Eq, Show)

{- | A rule placed in a column (golem-driver ADR 0027): the block it
belongs to, whether it is the rule before, and the place of the start of
its weight across the lines in sp from the start of the em box of the
first grid line of the page (negative out of the column).
-}
data PlacedRule = PlacedRule {prId :: !Int, prBefore :: !Bool, prAt :: !Integer}
  deriving stock (Eq, Show)

{- | A set of columns (docs/adr ADR 0025): from which grid line of the
page, how many columns, of which measure and gap.
-}
data ColumnSet = ColumnSet
  { -- | the number of columns
    csColumns :: !Int,
    -- | the measure of a column (sp)
    csMeasure :: !Integer,
    -- | the gap between columns (sp)
    csGap :: !Integer,
    -- | the grid line of the page where the columns start, from 0
    csFirstLine :: !Int
  }
  deriving stock (Eq, Show)

data Slotted
  = SLine !Int
  | SFigure !Int
  | SWrapped !Int
  | -- | a figure turned onto the whole page (golem-driver ADR 0034)
    SPageFigure !Int
  | -- | a heading block: its first line and how many lines it has
    SHeading !Int !Int
  | -- | a part of a code block: its first row, how many rows it has and the grid lines it takes (golem-driver ADR 0017)
    SCode !Int !Int !Int
  deriving stock (Eq, Show)

-- | How a heading sits on the line grid (golem-driver ADR 0003).
data HeadingBlock = HeadingBlock
  { -- | the line pitch of the heading
    hbPitch :: !Integer,
    -- | how many grid lines it takes
    hbSpan :: !Int,
    -- | from its first grid line to the top of its first line
    hbOffset :: !Integer
  }
  deriving stock (Eq, Show)

{- | The pitch, span and offset of a heading of size @s@ and @m@ lines on
a grid of font size @fs@ and pitch @p@: the body's ratio of pitch to
size is kept, the span is the fewest grid lines that hold it but at
least @least@ (golem-driver ADR 0032), and the heading is centred in
them. Integer sp; one rounding.
-}
headingBlock :: Integer -> Integer -> Integer -> Int -> Int -> HeadingBlock
headingBlock fs p s m least =
  let hp = round (p * s % fs)
      extent = toInteger (max 1 m - 1) * hp + s
      n = max (toInteger (max 1 least)) ((extent + p - fs + p - 1) `div` p)
      area = (n - 1) * p + fs
   in HeadingBlock hp (fromInteger n) ((area - extent) `div` 2)

-- | One column of a page (docs/adr ADR 0018).
data PageOut = PageOut
  { poNumber :: !Int,
    -- | the column, from 0 in the order of 'pgColumns'
    poColumn :: !Int,
    poBlank :: !Bool,
    -- | grid line index and what starts there
    poSlots :: ![(Int, Slotted)],
    -- | note id, first line of the body shown here, number of lines
    poFootnotes :: ![(NoteId, Int, Int)],
    poLabels :: ![Text],
    -- | the index marks placed on the page (golem-driver ADR 0007)
    poMarks :: ![SrcSpan],
    -- | the parts of tables on the page (golem-driver ADR 0008)
    poTables :: ![TableSegment],
    -- | the set of columns the column belongs to (docs/adr ADR 0025)
    poColumnSet :: !ColumnSet,
    -- | the rules of paragraphs and headings in the column (golem-driver ADR 0027)
    poRules :: ![PlacedRule],
    -- | the grid lines of the column, changed by 'FAdjustLines' (docs/adr ADR 0030)
    poLines :: !Int,
    -- | the manual controls of page breaks not met in the column
    poUnmet :: ![Unmet]
  }
  deriving stock (Eq, Show)

-- | A manual control of page breaks that could not be met (docs/adr ADR 0030).
data Unmet
  = UnmetNoBreak !SrcSpan
  | -- | the lines asked for
    UnmetNeedLines !SrcSpan !Int
  | -- | the lines the column was changed by
    UnmetAdjust !SrcSpan !Int
  | -- | blank lines dropped at the top of a column (docs/adr ADR 0046)
    DroppedBlank !SrcSpan
  deriving stock (Eq, Show)

-- | The part of a table on a page, in grid lines.
data TableSegment = TableSegment
  { tsTable :: !Int,
    tsFirst :: !Int,
    -- | the last grid line of the header row; none for a table without one (golem-driver ADR 0031)
    tsHeaderEnd :: !(Maybe Int),
    tsLast :: !Int
  }
  deriving stock (Eq, Show)

data St = St
  { sPage :: !Int,
    sColumn :: !Int,
    sUsed :: !Int, -- grid lines used from the top
    sNoteLines :: !Int, -- footnote lines used from the bottom (separator included)
    sSlots :: ![(Int, Slotted)],
    sNotes :: ![(NoteId, Int, Int)],
    sLabels :: ![Text],
    sMarks :: ![SrcSpan],
    sTables :: ![TableSegment],
    sDone :: ![PageOut],
    sDeferred :: ![Flow],
    sPendingNotes :: ![(NoteId, Int, Int)], -- note id, next line, remaining

    -- | forced breaks not applied yet, in the order written (docs/adr ADR 0017)
    sBreaks :: ![BreakKind],
    -- | the set of columns in effect, its first line on this page (docs/adr ADR 0025)
    sSet :: !ColumnSet,
    -- | footnote lines that every column of the set leaves at the foot of this page
    sReserved :: !Int,
    -- | the rules placed in the column (golem-driver ADR 0027)
    sRules :: ![PlacedRule],
    {- | the rule after of the ruled block just placed, waiting for the
    block after it to share its area: id, grid, rule and last grid line
    -} sJoin :: !(Maybe (Int, RuleGrid, RuleSide, Int)),
    -- | the largest need-lines not applied yet (docs/adr ADR 0030)
    sNeed :: !(Maybe (SrcSpan, Int)),
    -- | the grid lines the current column is changed by
    sAdjust :: !Int,
    -- | the controls not met, for the next column closed
    sUnmet :: ![Unmet],
    -- | a no-break waiting for the next flow: page, column and slots before it
    sNoBreak :: !(Maybe (SrcSpan, Int, Int, Int)),
    -- | the blank lines not placed yet, in the order written (docs/adr ADR 0046)
    sBlank :: ![(SrcSpan, Int)],
    -- | whether any flow has been placed
    sSeen :: !Bool,
    -- | whether the last flow was a figure sent on
    sLastDeferred :: !Bool
  }

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
-}
paginateWithin :: Int -> Int -> ColumnSet -> Int -> [Flow] -> [PageOut]
paginateWithin maxLines separatorLines base capacity flows =
  let st0 = St 1 0 0 0 [] [] [] [] [] [] [] [] [] base {csFirstLine = 0} 0 [] Nothing Nothing 0 [] Nothing [] False False
      final = closePage (go st0 flows)
      done = reverse (sDone final)
      -- controls not met in a column that made no output go with the last column
      leftover = sUnmet final
   in case reverse done of
        [] -> [PageOut 1 0 False [] [] [] [] [] base [] capacity leftover]
        lastPage : earlier -> reverse (lastPage {poUnmet = poUnmet lastPage <> leftover} : earlier)
  where
    columns = csColumns base
    -- a footnote line always fits under the separator and one line of text
    separator = max 1 (min separatorLines (capacity - 2))
    top st = csFirstLine (sSet st)
    -- breaks, need-lines and blank lines left at the end of the book are dropped (docs/adr ADR 0017, 0030, 0046)
    go st [] =
      let st1 = maybe st (\(sp, _, _, _) -> addUnmet (UnmetNoBreak sp) st) (sNoBreak st)
       in flushDeferred st1 {sBreaks = [], sNeed = Nothing, sNoBreak = Nothing, sBlank = []}
    go st (f : rest) = case f of
      -- a no-break with nothing before it, or after a figure sent on, cannot be met
      FNoBreak sp
        | not (sSeen st) || sLastDeferred st -> go (addUnmet (UnmetNoBreak sp) st) rest
        | otherwise -> go st {sNoBreak = Just (sp, sPage st, sColumn st, length (sSlots st))} rest
      FNeedLines sp n -> go st {sNeed = Just (maybe (sp, n) (\(s0, n0) -> if n > n0 then (sp, n) else (s0, n0)) (sNeed st))} rest
      FAdjustLines sp k -> go (adjustLines (applyBreaks st) sp k) rest
      FBlank sp n -> go st {sBlank = sBlank st <> [(sp, n)]} rest
      FBreak _ -> go (place st f rest) rest
      -- the space between paragraphs is not the flow a no-break waits for
      FSpace _ -> go (place (ready st) f rest) rest
      _ ->
        let st1 = checkNoBreak (placeFlow (placeBlank (ready st) f rest) f rest)
            deferred = case f of
              FFigure i _ _ _ -> any (\case FFigure j _ _ _ -> i == j; _ -> False) (sDeferred st1)
              -- the flow after a turned figure is never on its page
              FPageFigure {} -> True
              _ -> False
         in go st1 {sSeen = True, sLastDeferred = deferred} rest
    -- the breaks written so far, then the need-lines, apply before anything but another break
    ready = applyNeed . applyBreaks
    {- the blank lines go in the column of the first part of what follows;
    at the top of a column they are dropped and recorded, never cut
    (docs/adr ADR 0046). A heading at a recto starts its page first. -}
    placeBlank st0 f rest = case sBlank st0 of
      [] -> st0
      blanks ->
        let st1 = if startsRecto f then parityStart odd st0 else st0
            total = foldl' (\a (_, n) -> min capacity (a + min capacity n)) 0 blanks
            st2 = if sUsed st1 /= top st1 && total + nextNeed (f : rest) > free st1 then nextColumn st1 else st1
         in if sUsed st2 == top st2
              then foldl' (\s' (sp, _) -> addUnmet (DroppedBlank sp) s') st2 {sBlank = []} blanks
              else st2 {sUsed = sUsed st2 + total, sBlank = []}
    startsRecto = \case
      FHeading {fhRecto = True} -> True
      FRuled {frBody = RuledHeading {rhRecto = True}} -> True
      _ -> False
    addUnmet u st = st {sUnmet = sUnmet st <> [u]}
    -- the grid lines of the current column (docs/adr ADR 0030)
    cap st = capacity + sAdjust st
    applyNeed st = case sNeed st of
      Nothing -> st
      Just (sp, n)
        | n > cap st ->
            let st1 = addUnmet (UnmetNeedLines sp n) st {sNeed = Nothing}
             in if isEmpty st1 then st1 else nextColumn st1
        | free st < n && not (isEmpty st) -> nextColumn st {sNeed = Nothing}
        | otherwise -> st {sNeed = Nothing}
    -- at least one line and the lines placed, at most maxLines
    adjustLines st sp k =
      let want = sAdjust st + k
          got = max (max 1 (sUsed st + sNoteLines st) - capacity) (min (maxLines - capacity) want)
          st1 = st {sAdjust = got}
       in if got /= want then addUnmet (UnmetAdjust sp got) st1 else st1
    -- a paragraph before a no-break keeps its last lines with what follows
    placeFlow st f rest = case (f, keptNeed rest) of
      (FParagraph ls, Just n) -> placeKept st True ls n
      (FContinued ls, Just n) -> placeKept st False ls n
      (FDefTerm ls, Just n) -> placeKept (keep st (length ls + nextNeed rest)) True ls n
      _ -> place st f rest
    keptNeed rest = case dropWhile soft rest of
      FNoBreak _ : more -> Just (nextNeed (dropWhile soft more))
      _ -> Nothing
    soft = \case
      FNeedLines {} -> True
      FAdjustLines {} -> True
      FSpace _ -> True
      _ -> False
    -- the last two lines, or the whole paragraph of three lines or fewer, go to the next column, not from an empty one
    placeKept st isStart ls n =
      let st1 = placeLines st isStart ls
          len = length ls
          (front, back) = splitAt (len - (if len <= 3 then len else 2)) ls
          stA = placeLines st isStart front
          here = placeLines stA (isStart && null front) back
          fitsHere = sPage here == sPage stA && sColumn here == sColumn stA && n <= free here
       in if n <= free st1
            then st1
            else
              if fitsHere
                then here
                else if isEmpty stA then st1 else placeLines (nextColumn stA) (isStart && null front) back
    -- the flow after a no-break must start in the column where the flow before it ended
    checkNoBreak st = case sNoBreak st of
      Nothing -> st
      Just (sp, p, c, n) ->
        let grew po = poNumber po == p && poColumn po == c && length (poSlots po) > n
            met
              | (sPage st, sColumn st) == (p, c) = length (sSlots st) > n
              | otherwise = any grew (sDone st)
         in (if met then st else addUnmet (UnmetNoBreak sp) st) {sNoBreak = Nothing}
    applyBreaks st = foldl' applyBreak st {sBreaks = []} (sBreaks st)
    applyBreak st = \case
      BreakPage -> breakPage st
      BreakRecto -> parityStart odd st
      BreakVerso -> parityStart even st
      BreakColumn
        -- a waiting turned figure is placed first, on a page of its own (golem-driver ADR 0034)
        | csColumns (sSet st) > 1 && not (any isPageFigure (sDeferred st)) -> nextColumn st
        | otherwise -> breakPage st
    breakPage st
      -- the page is closed even when empty; an empty page is blank
      | isEmpty st && sColumn st == 0 && not (afterPageFigure st) = blankPage st
      -- the page after a turned figure is already a new page (golem-driver ADR 0034)
      | isEmpty st && sColumn st == 0 = st
      | otherwise = nextPage st
    afterPageFigure st = case sDone st of
      (po : _) -> poNumber po == sPage st - 1 && any (\case (_, SPageFigure _) -> True; _ -> False) (poSlots po)
      [] -> False
    nextNeed = \case
      (FParagraph ls : _) -> min 2 (length ls)
      (FContinued ls : _) -> min 2 (length ls)
      (FTable _ sp h rows : _) -> sp + length h + maybe 0 length (listToMaybe rows)
      (FDefTerm ls : _) -> length ls
      -- a heading keeps what follows it, a heading after it too (golem-driver ADR 0032)
      (FHeading _ _ n _ : rest) -> n + nextNeed rest
      (FFigure _ n _ _ : _) -> min n capacity
      (FPageFigure {} : _) -> 0
      (FWrapped _ n _ _ ls : _) -> max n (length ls)
      (FSpace _ : _) -> 0
      (FBreak _ : _) -> 0
      -- the controls of page breaks are skipped (docs/adr ADR 0030)
      (FNoBreak _ : rest) -> nextNeed rest
      (FNeedLines _ _ : rest) -> nextNeed rest
      (FAdjustLines _ _ : rest) -> nextNeed rest
      -- blank lines go with what follows, at most a column (docs/adr ADR 0046)
      (FBlank _ n : rest) -> min capacity (min capacity n + nextNeed rest)
      (FCode g cap first cont ls : _)
        | null ls -> 0
        | otherwise -> let k = min (length ls) (max 1 first) in cap + codeSpan g (k + (if cont && k < length ls then 1 else 0))
      -- a heading before the index columns on a page of one column keeps their first line
      (FSwitchColumns _ : rest) | columns == 1 -> nextNeed rest
      (FSwitchColumns _ : _) -> 0
      (FRestoreColumns : _) -> 0
      -- a ruled block keeps whole, its areas counted inside a column (golem-driver ADR 0027)
      (fr@FRuled {} : _) -> fst (insideBefore fr) + bodySize (frBody fr) + fst (insideAfter fr)
      [] -> 0
    free st = cap st - sUsed st - sNoteLines st
    isEmpty st = sUsed st == top st && null (sNotes st)
    place st f rest = case f of
      FRuled {} -> placeRuled st f rest
      FParagraph ls -> placeLines st True ls
      FContinued ls -> placeLines st False ls
      -- the space before a table only below the first line of a column (golem-driver ADR 0031)
      FTable i sp0 h rows ->
        let sp = if sUsed st == top st then 0 else sp0
            st1
              | sp + length h + maybe 0 length (listToMaybe rows) <= free st || isEmpty st = st {sUsed = sUsed st + min sp (free st)}
              | otherwise = nextColumn st
         in placeTable st1 i h rows
      FDefTerm ls -> placeLines (keep st (length ls + need)) True ls
      -- the notes of a heading count as the notes of a line do (golem-layout ADR 0013)
      FHeading _ recto n ls ->
        let st1 = if recto then parityStart odd st else keep st (headingNeed st n ls + need)
            st2 = if headingNeed st1 n ls <= free st1 || isEmpty st1 then st1 else nextColumn st1
         in putBlock st2 n ls
      -- figures keep the order written: after a figure sent on, the next ones wait too (golem-layout ADR 0015)
      FFigure i n labels marks
        | not (null (sDeferred st)) -> st {sDeferred = sDeferred st <> [f]}
        | n <= free st || isEmpty st -> putSlot st n (SFigure i) labels marks
        | otherwise -> st {sDeferred = sDeferred st <> [f]}
      -- a turned figure takes a page with nothing on it, or waits (golem-driver ADR 0034)
      FPageFigure i labels marks
        | null (sDeferred st) && sColumn st == 0 && sUsed st == 0 && null (sNotes st) && sNoteLines st == 0 -> pageFigure st {sAdjust = 0} i labels marks
        | otherwise -> st {sDeferred = sDeferred st <> [f]}
      FWrapped i n labels marks beside ->
        let st0 = flushFigures st
            size = max n (length beside)
            st1 = if size <= free st0 || isEmpty st0 then st0 else nextColumn st0
            st2 = putSlot st1 0 (SWrapped i) labels marks
         in (placeLines st2 False beside) {sUsed = max (sUsed st1 + size) (sUsed (placeLines st2 False beside))}
      FBreak k -> st {sBreaks = sBreaks st <> [k]}
      FCode g cap first cont ls -> placeCode st (g, cap, first, cont) True ls
      FSwitchColumns set ->
        let st1 = flushDeferred st
         in if (columns == 1 && free st1 > 0) || (isEmpty st1 && sColumn st1 == 0)
              then startSet st1 set (sUsed st1)
              else (nextPage st1) {sSet = set {csFirstLine = 0}}
      FRestoreColumns
        | isEmpty st && sColumn st == 0 && top st == 0 -> st {sSet = base {csFirstLine = 0}}
        | otherwise -> (nextPage st) {sSet = base {csFirstLine = 0}}
      FSpace n
        | sUsed st == top st -> st
        | otherwise -> st {sUsed = sUsed st + max 0 (min n (free st))}
      -- the controls of page breaks are handled in go (docs/adr ADR 0030)
      FNoBreak _ -> st
      FNeedLines _ _ -> st
      FAdjustLines _ _ -> st
      FBlank _ _ -> st
      where
        need = nextNeed rest
    -- the set starts at line @first@ of the page, above the footnotes already there
    startSet st set first =
      (closePage st)
        { sSet = set {csFirstLine = first},
          sColumn = 0,
          sUsed = first,
          sReserved = sNoteLines st,
          sSlots = [],
          sNotes = [],
          sLabels = [],
          sMarks = [],
          sTables = [],
          sRules = [],
          sJoin = Nothing
        }
    -- the grid lines of a heading, the lines of its notes and the separator if they are the first notes
    headingNeed st n ls =
      let noteLines = sum (map nbLines (concatMap lbNotes ls))
          sep = if sNoteLines st == 0 && noteLines > 0 then separator else 0
       in n + noteLines + sep
    keep st n = if n > free st && not (isEmpty st) then nextColumn st else st
    {- a code block: as many rows as their grid lines fit in the column, the
    rest in the next column; at least one row in an empty column (golem-driver ADR 0017).
    The first part has its caption and its first rows; a part before the
    last has a row for the text that it continues (golem-driver ADR 0023) -}
    placeCode st _ _ [] = st
    placeCode st c@(g, cap0, first, cont) isFirst ls@(l0 : _) =
      let len = length ls
          cap = if isFirst then cap0 else 0
          least = if isFirst then min len (max 1 first) else 1
          spanOf j = cap + codeSpan g (j + (if cont && j < len then 1 else 0))
          k0 = length (takeWhile (\j -> spanOf j <= free st) [1 .. len])
          k
            | k0 >= least = k0
            | isEmpty st = least
            | otherwise = 0
          (part, rest) = splitAt k ls
          n = spanOf k
          st1 = putSlot st n (SCode (lbId l0) k n) (concatMap lbLabels part) (concatMap lbMarks part)
       in if k == 0
            then placeCode (nextColumn st) c isFirst ls
            else if null rest then st1 else placeCode (nextColumn st1) c False rest
    -- start in column 0 of a page whose number satisfies p, after a blank page if needed
    parityStart p st =
      let st1 = if isEmpty st && sColumn st == 0 then st else nextPage st
       in if p (sPage st1) then st1 else blankPage st1
    blankPage st = st {sDone = PageOut (sPage st) 0 True [] [] [] [] [] (sSet st) {csFirstLine = 0} [] capacity [] : sDone st, sPage = sPage st + 1}
    putSlot st n s labels marks = st {sSlots = sSlots st <> [(sUsed st, s)], sUsed = sUsed st + n, sLabels = sLabels st <> labels, sMarks = sMarks st <> marks}
    -- lines of one paragraph; orphans and widows are moved
    placeLines st _ [] = st
    placeLines st isStart ls =
      let n = length ls
          k0 = fitting st ls
          k1 = if n - k0 == 1 && k0 > 0 then k0 - 1 else k0 -- widow
          k2 = if isStart && k1 == 1 && n >= 2 then 0 else k1 -- orphan
          k = if k2 == 0 && isEmpty st then max 1 (min n k0) else k2
       in if k >= n
            then foldl' putLine st ls
            else
              let st1 = foldl' putLine st (take k ls)
               in placeLines (nextColumn st1) (isStart && k == 0) (drop k ls)
    -- how many lines fit, with their notes
    fitting st ls = length (takeWhile id (snd (foldl' step ((sUsed st, sNoteLines st), []) ls)))
      where
        step ((u, nl), acc) l =
          let noteLines = sum (map nbLines (lbNotes l))
              sep = if nl == 0 && noteLines > 0 then separator else 0
              u' = u + 1
              nl' = nl + noteLines + sep
              ok = u' + nl' <= cap st && (null acc || last acc)
           in ((u', nl'), acc <> [ok])
    putLine = putLineKeeping 0
    -- a line, its notes in the room left after @reserve@ more grid lines of its block
    putLineKeeping reserve st l =
      let noteLines = sum (map nbLines (lbNotes l))
          sep = if sNoteLines st == 0 && noteLines > 0 then separator else 0
          room = cap st - sUsed st - 1 - reserve - sNoteLines st - sep
          (shown, pending) = splitNotes room (lbNotes l)
       in st
            { sSlots = sSlots st <> [(sUsed st, SLine (lbId l))],
              sUsed = sUsed st + 1,
              sNoteLines = sNoteLines st + (if null shown && reserve > 0 then 0 else sep) + sum [c | (_, _, c) <- shown],
              sNotes = sNotes st <> shown,
              sPendingNotes = sPendingNotes st <> pending,
              sLabels = sLabels st <> lbLabels l,
              sMarks = sMarks st <> lbMarks l
            }
    {- a paragraph or heading with rules (golem-driver ADR 0027): the area of
    its rule before, its lines and the area of its rule after as one block.
    A paragraph's block fits by its grid lines alone, its notes go on when
    they do not fit; a heading's counts its notes (golem-layout ADR 0013).
    A block that ends at the end of the column counts its rule after at
    the edge; one that does not fit an empty column is broken. -}
    placeRuled st fr rest = case sJoin st of
      Just j
        | frJoined fr,
          Just b <- frBefore fr,
          not (isRecto (frBody fr)),
          let plan = planOf st fr rest (Just (j, b)),
          planNeed st fr plan <= free st ->
            commitRuled st fr plan
      Just _ -> placeRuled (flushJoin st) fr rest
      Nothing ->
        let st1 = if isRecto (frBody fr) then parityStart odd st else st
            st2 = if isHeadingBody (frBody fr) && not (isRecto (frBody fr)) then keep st1 (planNeed st1 fr (planOf st1 fr rest Nothing) + nextNeed rest) else st1
            plan2 = planOf st2 fr rest Nothing
         in if planNeed st2 fr plan2 <= free st2
              then commitRuled st2 fr plan2
              else
                if isEmpty st2
                  then splitRuled st2 fr rest
                  else
                    let st3 = nextColumn st2
                        plan3 = planOf st3 fr rest Nothing
                     in if planNeed st3 fr plan3 <= free st3 then commitRuled st3 fr plan3 else splitRuled st3 fr rest
    isRecto = \case
      RuledHeading True _ _ -> True
      _ -> False
    isHeadingBody = \case
      RuledHeading {} -> True
      _ -> False
    bodyLines = \case
      RuledLines ls -> ls
      RuledHeading _ _ ls -> ls
    bodySize = \case
      RuledLines ls -> length ls
      RuledHeading _ n _ -> n
    firstOverhang fr = maybe 0 lbOverhang (listToMaybe (bodyLines (frBody fr)))
    -- the areas inside a column, for nextNeed
    insideBefore fr = maybe (0, 0) (\b -> ruleBefore (frGrid fr) b (firstOverhang fr)) (frBefore fr)
    insideAfter fr = maybe (0, 0) (\a -> ruleAfter (frGrid fr) a (frNextOverhang fr)) (frAfter fr)
    -- whether the rule after waits for the next block to share its area
    joinsNext fr rest =
      isJust (frAfter fr) && case rest of
        (FRuled {frJoined = True, frBefore = Just _} : _) -> True
        _ -> False
    {- the plan of a block at the place of the column: the lines of its
    areas, its rules placed before and after it, and the rule after that
    waits for the next block -}
    planOf st fr rest joined =
      let g@(RuleGrid p h) = frGrid fr
          u = sUsed st
          n = bodySize (frBody fr)
          r1 = firstOverhang fr
          (k1, before) = case (joined, frBefore fr) of
            (Just ((aid, ga, a, aLast), b), _) ->
              let (k, offA, offB) = rulesJoined ga a b r1
                  base = toInteger aLast * p + h
               in (k, [PlacedRule aid False (base + offA), PlacedRule (frId fr) True (base + offB)])
            (Nothing, Just b)
              | u == top st ->
                  let (k, off) = ruleBeforeAtStart g b {rsdOutside = if top st == 0 then rsdOutside b else Nothing} r1
                   in (k, [PlacedRule (frId fr) True (toInteger u * p + off)])
              | otherwise ->
                  let (k, off) = ruleBefore g b r1
                   in (k, [PlacedRule (frId fr) True (toInteger (u - 1) * p + h + off)])
            (Nothing, Nothing) -> (0, [])
          lastLine = u + k1 + n - 1
          (k2, after) = case frAfter fr of
            Just a
              | not (joinsNext fr rest) ->
                  let (ki, offi) = ruleAfter g a (frNextOverhang fr)
                      notes = sNoteLines st > 0 || not (all (null . lbNotes) (bodyLines (frBody fr)))
                      (k, off)
                        | lastLine + 1 + ki >= cap st - sNoteLines st = ruleAfterAtEnd g a {rsdOutside = if notes then Nothing else rsdOutside a}
                        | otherwise = (ki, offi)
                   in (k, [PlacedRule (frId fr) False (toInteger lastLine * p + h + off)])
            _ -> (0, [])
          waiting = case frAfter fr of
            Just a | joinsNext fr rest -> Just (frId fr, g, a, lastLine)
            _ -> Nothing
       in (k1, before, k2, after, waiting)
    planNeed st fr (k1, _, k2, _, _) = case frBody fr of
      RuledLines ls -> k1 + length ls + k2
      RuledHeading _ n ls -> k1 + headingNeed st n ls + k2
    commitRuled st fr (k1, before, k2, after, waiting) =
      let st1 = st {sRules = sRules st <> before, sUsed = sUsed st + k1, sJoin = Nothing}
          st2 = case frBody fr of
            RuledLines ls -> foldl' (\s' (j, l) -> putLineKeeping (length ls - 1 - j + k2) s' l) st1 (zip [0 ..] ls)
            RuledHeading _ n ls -> putBlock st1 n ls
       in st2 {sRules = sRules st2 <> after, sUsed = min (sUsed st2 + k2) (max (sUsed st2) (cap st2 - sNoteLines st2)), sJoin = waiting}
    {- a block that does not fit an empty column (golem-driver ADR 0027,
    0035): the lines of a paragraph are broken as any paragraph's, without
    its rules and their areas; a heading drops its rule after, then its
    rule before, until it fits -}
    splitRuled st0 fr rest =
      let st = if isEmpty st0 then st0 else nextColumn st0
          (k1, before, _, _, _) = planOf st fr rest Nothing
       in case frBody fr of
            RuledLines ls -> placeLines st True ls
            RuledHeading _ n ls ->
              let (_, _, k2, after, _) = planOf st fr [] Nothing
               in if k1 + headingNeed st n ls + k2 <= free st
                    then commitRuled st fr (k1, before, k2, after, Nothing)
                    else
                      if k1 + headingNeed st n ls <= free st
                        then commitRuled st fr (k1, before, 0, [], Nothing)
                        else putBlock st n ls
    -- the rule after of the block before, in its own area: nothing shares it
    flushJoin st = case sJoin st of
      Nothing -> st
      Just (aid, g@(RuleGrid p h), a, aLast) ->
        let (ki, offi) = ruleAfter g a 0
            (k, off)
              | aLast + 1 + ki >= cap st - sNoteLines st = ruleAfterAtEnd g a {rsdOutside = if sNoteLines st > 0 then Nothing else rsdOutside a}
              | otherwise = (ki, offi)
         in st {sRules = sRules st <> [PlacedRule aid False (toInteger aLast * p + h + off)], sUsed = sUsed st + min k (free st), sJoin = Nothing}
    -- a table: rows whole, a page break between rows repeats the header
    -- without its labels, notes and marks (golem-driver ADR 0008)
    placeTable st i h rows =
      let start = sUsed st
          st1 = foldl' putLine st h
          go stc first [] = segment stc first
          go stc first (r : rest)
            | fitting stc r >= length r || sUsed stc == first + length h = go (foldl' putLine stc r) first rest
            | otherwise =
                let closed = segment stc first
                    fresh = nextColumn closed
                    repeated = foldl' putLine fresh [l {lbNotes = [], lbLabels = [], lbMarks = []} | l <- h]
                 in go repeated (sUsed fresh) (r : rest)
          headerEnd first = if null h then Nothing else Just (first + length h - 1)
          segment stc first = stc {sTables = sTables stc <> [TableSegment i first (headerEnd first) (sUsed stc - 1)]}
       in go st1 start rows
    -- a heading: one block of n grid lines; the notes of its lines as in putLine
    putBlock st _ [] = st
    putBlock st n ls@(l0 : _) =
      let notes = concatMap lbNotes ls
          noteLines = sum (map nbLines notes)
          sep = if sNoteLines st == 0 && noteLines > 0 then separator else 0
          room = cap st - sUsed st - n - sNoteLines st - sep
          (shown, pending) = splitNotes room notes
       in st
            { sSlots = sSlots st <> [(sUsed st, SHeading (lbId l0) (length ls))],
              sUsed = sUsed st + n,
              sNoteLines = sNoteLines st + (if null shown then 0 else sep) + sum [c | (_, _, c) <- shown],
              sNotes = sNotes st <> shown,
              sPendingNotes = sPendingNotes st <> pending,
              sLabels = sLabels st <> concatMap lbLabels ls,
              sMarks = sMarks st <> concatMap lbMarks ls
            }
    -- a note longer than the room continues on the next page
    splitNotes = go'
      where
        go' _ [] = ([], [])
        go' r (NoteBody i len : rest)
          | len <= r = let (a, b) = go' (r - len) rest in ((i, 0, len) : a, b)
          | r > 0 = ([(i, 0, r)], (i, r, len - r) : [(j, 0, m) | NoteBody j m <- rest])
          | otherwise = ([], (i, 0, len) : [(j, 0, m) | NoteBody j m <- rest])
    -- an empty column makes no output
    closePage st =
      if null (sSlots st) && null (sNotes st)
        then st
        else st {sDone = PageOut (sPage st) (sColumn st) False (sSlots st) (sNotes st) (sLabels st) (sMarks st) (sTables st) (sSet st) (sRules st) (cap st) (sUnmet st) : sDone st, sUnmet = []}
    -- the next column of the page, or column 0 of the next page
    nextColumn st = advance (sColumn st + 1 >= csColumns (sSet st)) st
    nextPage = advance True
    advance toPage st =
      let closed = closePage st
          -- a page left with nothing in any column is blank
          written = any ((== sPage st) . poNumber) (sDone closed)
          closed' = if toPage && not written then closed {sDone = PageOut (sPage st) 0 True [] [] [] [] [] (sSet st) {csFirstLine = 0} [] capacity [] : sDone closed} else closed
          fresh =
            closed'
              { sPage = if toPage then sPage st + 1 else sPage st,
                sColumn = if toPage then 0 else sColumn st + 1,
                sSet = if toPage then (sSet st) {csFirstLine = 0} else sSet st,
                sReserved = if toPage then 0 else sReserved st,
                sAdjust = 0,
                sUsed = if toPage then 0 else top st,
                sNoteLines = if toPage then 0 else sReserved st,
                sSlots = [],
                sNotes = [],
                sLabels = [],
                sMarks = [],
                sTables = [],
                sRules = [],
                sJoin = Nothing,
                sPendingNotes = []
              }
          -- the turned figures waiting first take pages of their own before the notes go on (golem-driver ADR 0034)
          (turned, waiting) = if toPage then span isPageFigure (sDeferred st) else ([], sDeferred st)
          fresh' = foldl' (\s' (i, labels, marks) -> pageFigure s' i labels marks) fresh [(i, labels, marks) | FPageFigure i labels marks <- turned]
          withNotes = foldl' carryNote fresh' (sPendingNotes st)
       in placeDeferred withNotes {sDeferred = []} waiting
    isPageFigure = \case
      FPageFigure {} -> True
      _ -> False
    -- a page of nothing but a turned figure; the next page starts empty
    pageFigure st i labels marks =
      st
        { sDone = PageOut (sPage st) 0 False [(0, SPageFigure i)] [] labels marks [] (sSet st) {csFirstLine = 0} [] capacity [] : sDone st,
          sPage = sPage st + 1
        }
    carryNote st (i, from, len) =
      let sep = if sNoteLines st == 0 then separator else 0
          room = cap st - sNoteLines st - sep - 1
          shown = min len room
       in st
            { sNotes = sNotes st <> [(i, from, shown)],
              sNoteLines = sNoteLines st + sep + shown,
              sPendingNotes = sPendingNotes st <> [(i, from + shown, len - shown) | shown < len]
            }
    placeDeferred st [] = st
    placeDeferred st (FFigure i n labels marks : rest)
      | n <= free st || isEmpty st = placeDeferred (putSlot st n (SFigure i) labels marks) rest
      | otherwise = st {sDeferred = FFigure i n labels marks : rest}
    -- a turned figure waits for the next page, and the figures after it with it (golem-driver ADR 0034)
    placeDeferred st rest@(FPageFigure {} : _) = st {sDeferred = rest}
    placeDeferred st (_ : rest) = placeDeferred st rest
    flushDeferred st
      | null (sDeferred st) && null (sPendingNotes st) = st
      | otherwise = flushDeferred (nextColumn st)
    -- the figures sent on are placed, the continued notes may go on beside them (golem-layout ADR 0015)
    flushFigures st
      | null (sDeferred st) = st
      | otherwise = flushFigures (nextColumn st)

-- | The page of each label.
labelPages :: [PageOut] -> Map Text Integer
labelPages ps = Map.fromList [(l, toInteger (poNumber p)) | p <- ps, l <- poLabels p]

-- | The page of each index mark (golem-driver ADR 0007).
markPages :: [PageOut] -> Map SrcSpan Integer
markPages ps = Map.fromList [(m, toInteger (poNumber p)) | p <- ps, m <- poMarks p]

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
          actual = labelPages pages
       in if actual == assumed || (i > 1 && actual `Map.isSubmapOf` assumed && assumed `Map.isSubmapOf` actual)
            then Right pages
            else
              if i >= maxIterations
                then Left (Map.keys (Map.filter id (Map.mergeWithKey (\_ a b -> Just (a /= b)) (Map.map (const True)) (Map.map (const True)) actual assumed)))
                else go (i + 1) actual
