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
    AdjustLimit (..),
    TableSegment (..),
    RuledBody (..),
    PlacedRule (..),
    HeadingBlock (..),
    headingBlock,
    Need (..),
    lookAhead,
    keptLookAhead,
    paginate,
    paginateIn,
    paginateWithin,
    pageLabels,
    labelPages,
    markPages,
    resolvePageRefs,
    maxIterations,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Ratio ((%))
import Data.Text (Text)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry, codeSpan)
import Golem.Layout.PageLabel
import Golem.Layout.Paginate.Decide
import Golem.Layout.Paginate.State
import Golem.Layout.Paginate.Types
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..), ruleAfter, ruleAfterAtEnd)
import Golem.Length (Sp (..))
import Golem.Syntax (SrcSpan)

{- | The pitch, span and offset of a heading of size @s@ and @m@ lines on
a grid of font size @fs@ and pitch @p@: the body's ratio of pitch to
size is kept, the span is the fewest grid lines that hold it but at
least @least@ (golem-driver ADR 0032), and the heading is centred in
them. One rounding.
-}
headingBlock :: Sp -> Sp -> Sp -> Int -> Int -> HeadingBlock
headingBlock (Sp fs) (Sp p) (Sp s) m least =
  let hp = round (p * s % fs)
      extent = toInteger (max 1 m - 1) * hp + s
      n = max (toInteger (max 1 least)) ((extent + p - fs + p - 1) `div` p)
      area = (n - 1) * p + fs
   in HeadingBlock (Sp hp) (fromInteger n) (Sp ((area - extent) `div` 2))

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
lookAheadEnv = Env maxBound 1 (ColumnSet 1 0 0 0)

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
paginateWithin maxLines separatorLines base capacity flows =
  let -- a footnote line always fits under the separator and one line of text
      env = Env maxLines (max 1 (min separatorLines (capacity - 2))) base capacity
      final = closePage env (placeAll env (initialState env) flows)
      done = reverse (sDone final)
      -- controls not met in a column that made no output go with the last column
      leftover = sUnmet final
   in case reverse done of
        [] -> [PageOut 1 0 False [] [] [] [] [] base [] capacity leftover []]
        lastPage : earlier -> withSections (sSections final) (reverse (lastPage {poUnmet = poUnmet lastPage <> leftover} : earlier))

{- | The sections on the first column of the page each opened
(docs/adr/0260). A section whose page has no column, the book ending
there, has no page.
-}
withSections :: [(Int, Int)] -> [PageOut] -> [PageOut]
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
  let st1 = maybe st (\(sp, _, _, _) -> addUnmet (UnmetNoBreak sp) st) (sNoBreak st)
      st2 = st1 {sBreaks = [], sNeed = Nothing, sNeedAt = Nothing, sNoBreak = Nothing, sBlank = []}
      dropBlanks s = foldl' (\s' (sp, _) -> addUnmet (DroppedBlank sp) s') s (sBlank st1)
   in if null (sBlank st1)
        then flushDeferred env st2
        else
          if null (sDeferred st2)
            then flushDeferred env (dropBlanks st2)
            else flushDeferred env (dropBlanks (nextColumn env st2))
placeAll env st (f : rest) = case f of
  -- a no-break with nothing before it, or after a figure sent on, cannot be met
  FNoBreak sp
    | not (sSeen st) || sLastDeferred st -> placeAll env (addUnmet (UnmetNoBreak sp) st) rest
    | otherwise -> placeAll env st {sNoBreak = Just (sp, sPage st, sColumn st, length (sSlots st))} rest
  -- the larger need-lines is kept; one larger than the need-lines judged is judged again (golem-layout ADR 0035),
  -- before the spaces placed after the block before it (golem-layout ADR 0043)
  FNeedLines sp n -> placeAll env (needMore env sp n st) rest
  FAdjustLines sp k -> placeAll env (adjustLines env (applyBreaks env st) sp k) rest
  -- blank lines with nothing after them that places anything are the end of the book's (docs/adr ADR 0046)
  FBlank sp n
    | all waitsFor rest -> placeAll env st rest
    | otherwise -> placeAll env st {sBlank = sBlank st <> [(sp, n)]} rest
  FBreak _ -> placeAll env (place env st f rest) rest
  FSection {} -> placeAll env (place env st f rest) rest
  -- the space between paragraphs is not the flow a no-break waits for;
  -- need-lines is judged before it, the space not counted (golem-layout ADR 0027)
  -- nor the spaces before it, written after the block before (golem-layout ADR 0043)
  FSpace n -> placeAll env (placeSpace env (needBeforeSpaces env (applyBreaks env st)) n) rest
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
     in placeAll env st1 {sSeen = True, sLastDeferred = deferred, sSpaces = spaces} rest

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
  FBreak _ -> True
  FSection {} -> True
  FNoBreak _ -> True
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

-- | A paragraph before a no-break keeps its last lines with what follows.
placeFlow :: Env -> St -> Flow -> [Flow] -> St
placeFlow env st f rest = case (f, keptNeed env rest) of
  (FParagraph ls, Just n) -> placeKept env (placeLines env) st True ls n
  -- a stanza keeps its last verse lines as a paragraph its last lines (docs/adr/0205)
  (FStanza vs, Just n) -> placeKept env (placeStanza env) st True vs n
  (FContinued ls, Just n) -> placeKept env (placeLines env) st False ls n
  (FDefTerm ls, Just n) -> placeKept env (placeLines env) (keep env st (\s -> needIn env s (termNeed ls) (nextNeed env rest))) True ls n
  _ -> place env st f rest

{- | The last two lines, or the whole paragraph of three lines or fewer, go
to the next column, not from an empty one; of a stanza, its verse lines
(docs/adr/0205).
-}
placeKept :: Env -> (St -> Bool -> [a] -> St) -> St -> Bool -> [a] -> Need -> St
placeKept env placeIn st isStart ls n =
  let st1 = placeIn st isStart ls
      len = length ls
      (front, back) = splitAt (len - (if len <= 3 then len else 2)) ls
      stA = placeIn st isStart front
      here = placeIn stA (isStart && null front) back
      fits s = needIn env s mempty n <= free env s
      fitsHere = sPage here == sPage stA && sColumn here == sColumn stA && fits here
   in if fits st1
        then st1
        else
          if fitsHere
            then here
            else if isEmpty stA then st1 else placeIn (nextColumn env stA) (isStart && null front) back

-- | The flow after a no-break must start in the column where the flow before it ended.
checkNoBreak :: St -> St
checkNoBreak st = case sNoBreak st of
  Nothing -> st
  Just (sp, p, c, n) ->
    let grew po = poNumber po == p && poColumn po == c && length (poSlots po) > n
        met
          | (sPage st, sColumn st) == (p, c) = length (sSlots st) > n
          | otherwise = any grew (sDone st)
     in (if met then st else addUnmet (UnmetNoBreak sp) st) {sNoBreak = Nothing}

applyBreaks :: Env -> St -> St
applyBreaks env st = foldl' (applyBreak env) st {sBreaks = []} (sBreaks st)

applyBreak :: Env -> St -> Pending -> St
applyBreak env st = \case
  PendingBreak k -> applyBreakKind env st k
  PendingSection i start -> sectionStart env st i start

{- | The break before a section (docs/adr/0260), and the page it opens
recorded as the first page of the section: to an odd page for an odd
start and to an even page for an even one, as @page-break recto and
verso; without a start, to the next page unless the page is empty. The
figures sent on and the continued notes are placed first, before the
first page of the section.
-}
sectionStart :: Env -> St -> Int -> Maybe Integer -> St
sectionStart env st i start =
  let st1 = case start of
        Just s -> parityStart env (if odd s then odd else even) st
        Nothing ->
          let st0 = flushDeferred env st
           in if isEmpty st0 && sColumn st0 == 0 then st0 else nextPage env st0
   in st1 {sSections = sSections st1 <> [(i, sPage st1)]}

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
  FRuled {} -> placeRuled env st f rest
  FParagraph ls -> placeLines env st True ls
  FStanza vs -> placeStanza env st True vs
  FContinued ls -> placeLines env st False ls
  -- the space before a table only below the first line of a column (golem-driver ADR 0031);
  -- in the columns gone on to, the header and the first row are kept together (golem-layout ADR 0025)
  -- the caption with the lines it touches (docs/adr/0262)
  FTable i sp0 h rows capt below ->
    let sp = if sUsed st == top st then 0 else sp0
        headed = tableHead h rows capt below
        st1
          | sp + headed <= free env st || isEmpty st = st {sUsed = sUsed st + min sp (free env st)}
          | otherwise = keep env (nextColumn env st) (const headed)
     in placeTable env st1 i h rows capt below
  FDefTerm ls -> placeLines env (keep env st (\s -> needIn env s (termNeed ls) need)) True ls
  -- the notes of a heading count as the notes of a line do (golem-layout ADR 0013)
  FHeading _ recto n ls ->
    let st1 = if recto then parityStart env odd st else keep env st (\s -> needIn env s (Need n (noteLinesOf ls)) need)
        st2 = if headingNeed env st1 n ls <= free env st1 || isEmpty st1 then st1 else nextColumn env st1
     in putBlock env st2 n ls
  -- figures keep the order written: after a figure sent on, the next ones wait too (golem-layout ADR 0015)
  FFigure i n labels marks
    | not (null (sDeferred st)) -> st {sDeferred = sDeferred st <> [f]}
    | n <= free env st || isEmpty st -> putSlot st n (SFigure i) labels marks
    | otherwise -> st {sDeferred = sDeferred st <> [f]}
  -- a turned figure takes a page with nothing on it, or waits (golem-driver ADR 0034)
  FPageFigure i labels marks
    | null (sDeferred st) && sColumn st == 0 && sUsed st == 0 && null (sNotes st) && sNoteLines st == 0 -> pageFigure env st {sAdjust = 0} i labels marks
    | otherwise -> st {sDeferred = sDeferred st <> [f]}
  FWrapped i n labels marks beside ->
    let st0 = flushFigures env st
        size = max n (length beside)
        -- the continued notes take the foot of the columns gone on to (golem-layout ADR 0025)
        st1 = keep env st0 (const size)
        st2 = putSlot st1 0 (SWrapped i) labels marks
     in (placeLines env st2 False beside) {sUsed = max (sUsed st1 + size) (sUsed (placeLines env st2 False beside))}
  FBreak k -> st {sBreaks = sBreaks st <> [PendingBreak k]}
  FSection i start -> st {sBreaks = sBreaks st <> [PendingSection i start]}
  FCode g caption first cont ls -> placeCode env st (g, caption, first, cont) True ls
  FSwitchColumns set ->
    let st1 = flushDeferred env st
     in if (csColumns (envBase env) == 1 && free env st1 > 0) || (isEmpty st1 && sColumn st1 == 0)
          then startSet env st1 set (sUsed st1)
          else (nextPage env st1) {sSet = set {csFirstLine = 0}}
  FRestoreColumns
    | isEmpty st && sColumn st == 0 && top st == 0 -> st {sSet = (envBase env) {csFirstLine = 0}}
    | otherwise -> (nextPage env st) {sSet = (envBase env) {csFirstLine = 0}}
  FSpace n
    | sUsed st == top st -> st
    | otherwise -> st {sUsed = sUsed st + max 0 (min n (free env st))}
  -- the controls of page breaks are handled in placeAll (docs/adr ADR 0030)
  FNoBreak _ -> st
  FNeedLines _ _ -> st
  FAdjustLines _ _ -> st
  FBlank _ _ -> st
  where
    need = nextNeed env rest

{- | A code block: as many rows as their grid lines fit in the column, the
rest in the next column; at least one row in an empty column (golem-driver ADR 0017).
The first part has its caption and its first rows; a part before the
last has a row for the text that it continues (golem-driver ADR 0023).
-}
placeCode :: Env -> St -> (CodeGeometry, Int, Int, Bool) -> Bool -> [LineBox] -> St
placeCode _ st _ _ [] = st
placeCode env st c@(g, cap0, first, cont) isFirst ls@(l0 : _) =
  let len = length ls
      captionRows = if isFirst then cap0 else 0
      least = if isFirst then min len (max 1 first) else 1
      spanOf j = captionRows + codeSpan g (j + (if cont && j < len then 1 else 0))
      k0 = length (takeWhile (\j -> spanOf j <= free env st) [1 .. len])
      k
        | k0 >= least = k0
        | isEmpty st = least
        | otherwise = 0
      (part, rest) = splitAt k ls
      n = spanOf k
      st1 = putSlot st n (SCode (lbId l0) k n) (concatMap lbLabels part) (concatMap lbMarks part)
   in if k == 0
        then placeCode env (nextColumn env st) c isFirst ls
        else if null rest then st1 else placeCode env (nextColumn env st1) c False rest

-- | Lines of one paragraph; orphans and widows are moved.
placeLines :: Env -> St -> Bool -> [LineBox] -> St
placeLines _ st _ [] = st
placeLines env st isStart ls =
  let n = length ls
      k0 = fitting env st ls
      k2 = splitAtBreak isStart n k0
      -- a column of nothing but headings places a line as an empty one does,
      -- when the line and a line of its notes are left room (golem-layout ADR 0019)
      k = if k2 == 0 && (isEmpty st || (sHeadingOnly st && roomForLine env st ls)) then max 1 (min n k0) else k2
   in if k >= n
        then foldl' (putLine env) st ls
        else
          let st1 = foldl' (putLine env) st (take k ls)
           in placeLines env (nextColumn env st1) (isStart && k == 0) (drop k ls)

{- | The verse lines of a stanza (docs/adr/0180): a verse line is not
broken between columns, and a column neither ends with the first verse
line of a stanza alone nor starts with its last alone, as 'placeLines'
counts lines. A stanza that cannot be placed so in an empty column, or in
a column of nothing but headings, places as many verse lines as fit, or
breaks its first verse line as a paragraph when none fits.
-}
placeStanza :: Env -> St -> Bool -> [[LineBox]] -> St
placeStanza _ st _ [] = st
placeStanza env st isStart vs =
  let n = length vs
      room = fitting env st (concat vs)
      k0 = length (takeWhile (<= room) (drop 1 (scanl (+) 0 (map length vs))))
      k2 = splitAtBreak isStart n k0
      putVerses s = foldl' (putLine env) s . concat
      split k = placeStanza env (nextColumn env (putVerses st (take k vs))) False (drop k vs)
   in if k2 >= n
        then putVerses st vs
        else
          if k2 > 0
            then split k2
            else
              if isEmpty st || (sHeadingOnly st && roomForLine env st (concat vs))
                then case vs of
                  v : more | k0 == 0 -> placeStanza env (placeLines env st isStart v) False more
                  _ -> split k0
                else placeStanza env (nextColumn env st) isStart vs

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
      let plan = planOf env st fr rest (Just (j, b)),
      planNeed env st fr plan <= free env st ->
        commitRuled env st fr plan
  Just _ -> placeRuled env (flushJoin env st) fr rest
  Nothing ->
    let st1 = if isRecto (frBody fr) then parityStart env odd st else st
        st2 = if isHeadingBody (frBody fr) && not (isRecto (frBody fr)) then keep env st1 (\s -> needIn env s (planParts fr (planOf env s fr rest Nothing)) (nextNeed env rest)) else st1
        plan2 = planOf env st2 fr rest Nothing
     in if planNeed env st2 fr plan2 <= free env st2
          then commitRuled env st2 fr plan2
          else
            if isEmpty st2
              then splitRuled env st2 fr rest
              else
                let st3 = nextColumn env st2
                    plan3 = planOf env st3 fr rest Nothing
                 in if planNeed env st3 fr plan3 <= free env st3 then commitRuled env st3 fr plan3 else splitRuled env st3 fr rest

commitRuled :: Env -> St -> Flow -> Plan -> St
commitRuled env st fr (k1, before, k2, after, waiting) =
  let st1 = st {sRules = sRules st <> before, sUsed = sUsed st + k1, sJoin = Nothing}
      st2 = case frBody fr of
        RuledLines ls -> foldl' (\s' (j, l) -> putLineKeeping env (length ls - 1 - j + k2) s' l) st1 (zip [0 ..] ls)
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
        RuledLines ls -> placeLines env st True ls
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
flushJoin env st = case sJoin st of
  Nothing -> st
  Just (aid, g@(RuleGrid p h), a, aLast) ->
    let (ki, offi) = ruleAfter g a 0
        (k, off)
          | aLast + 1 + ki >= cap env st - sNoteLines st = ruleAfterAtEnd g a {rsdOutside = if sNoteLines st > 0 then Nothing else rsdOutside a}
          | otherwise = (ki, offi)
     in st {sRules = sRules st <> [PlacedRule aid False (fromIntegral aLast * p + h + off)], sUsed = sUsed st + min k (free env st), sJoin = Nothing}

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
      rowsFrom stc first [] = segment stc first
      rowsFrom stc first (r : rest)
        | fitting env stc r' >= length r' || sUsed stc == first + length h = rowsFrom (foldl' (putLine env) stc r) first rest
        | otherwise =
            let closed = segment stc first
                fresh = keep env (nextColumn env closed) (const (length h + length r'))
                repeated = foldl' (putLine env) fresh [l {lbNotes = [], lbLabels = [], lbMarks = []} | l <- h]
             in rowsFrom repeated (sUsed fresh) (r : rest)
        where
          r' = withCaption rest r
      headerEnd first = if null h then Nothing else Just (first + length h - 1)
      segment stc first = stc {sTables = sTables stc <> [TableSegment i first (headerEnd first) (sUsed stc - 1)]}
      placed = rowsFrom st1 start rows
   in if below then foldl' (putLine env) placed capt else placed

{- | The label of each page by its number (docs/adr/0260), from the
sections given and the first pages the pagination recorded.
-}
pageLabels :: Map Int Section -> [PageOut] -> Map Int PageLabel
pageLabels sections ps =
  pageLabelsOf sections (Map.fromListWith (flip (<>)) [(poNumber p, poSections p) | p <- ps]) (maximum (0 : map poNumber ps))

-- | The page label of each label (docs/adr/0260).
labelPages :: Map Int Section -> [PageOut] -> Map Text PageLabel
labelPages sections ps =
  let labels = pageLabels sections ps
   in Map.fromList [(l, Map.findWithDefault (plainLabel (poNumber p)) (poNumber p) labels) | p <- ps, l <- poLabels p]

-- | The page label of each index mark (golem-driver ADR 0007, docs/adr/0260).
markPages :: Map Int Section -> [PageOut] -> Map SrcSpan PageLabel
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
