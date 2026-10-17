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
    TableSegment (..),
    HeadingBlock (..),
    headingBlock,
    paginate,
    paginateIn,
    labelPages,
    markPages,
    resolvePageRefs,
    maxIterations,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (CodeGeometry, codeSpan)
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
  | -- | the start of the index in its own columns (docs/adr ADR 0025)
    FSwitchColumns !ColumnSet
  | -- | the end of the index: the next page, in the columns of the page
    FRestoreColumns
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
    poColumnSet :: !ColumnSet
  }
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
    sReserved :: !Int
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
paginateIn separatorLines base capacity flows =
  let st0 = St 1 0 0 0 [] [] [] [] [] [] [] [] [] base {csFirstLine = 0} 0
      final = closePage (go st0 flows)
      done = reverse (sDone final)
   in if null done then [PageOut 1 0 False [] [] [] [] [] base] else done
  where
    columns = csColumns base
    -- a footnote line always fits under the separator and one line of text
    separator = max 1 (min separatorLines (capacity - 2))
    top st = csFirstLine (sSet st)
    -- breaks left at the end of the book are dropped (docs/adr ADR 0017)
    go st [] = flushDeferred st {sBreaks = []}
    go st (f : rest) = go (place (ready f st) f (nextNeed rest)) rest
    -- the breaks written so far apply before anything but another break
    ready = \case
      FBreak _ -> id
      _ -> applyBreaks
    applyBreaks st = foldl' applyBreak st {sBreaks = []} (sBreaks st)
    applyBreak st = \case
      BreakPage -> breakPage st
      BreakRecto -> parityStart odd st
      BreakVerso -> parityStart even st
      BreakColumn
        | csColumns (sSet st) > 1 -> nextColumn st
        | otherwise -> breakPage st
    breakPage st
      -- the page is closed even when empty; an empty page is blank
      | isEmpty st && sColumn st == 0 = blankPage st
      | otherwise = nextPage st
    nextNeed = \case
      (FParagraph ls : _) -> min 2 (length ls)
      (FContinued ls : _) -> min 2 (length ls)
      (FTable _ sp h rows : _) -> sp + length h + maybe 0 length (listToMaybe rows)
      (FDefTerm ls : _) -> length ls
      -- a heading keeps what follows it, a heading after it too (golem-driver ADR 0032)
      (FHeading _ _ n _ : rest) -> n + nextNeed rest
      (FFigure _ n _ _ : _) -> min n capacity
      (FWrapped _ n _ _ ls : _) -> max n (length ls)
      (FSpace _ : _) -> 0
      (FBreak _ : _) -> 0
      (FCode g cap first cont ls : _)
        | null ls -> 0
        | otherwise -> let k = min (length ls) (max 1 first) in cap + codeSpan g (k + (if cont && k < length ls then 1 else 0))
      -- a heading before the index columns on a page of one column keeps their first line
      (FSwitchColumns _ : rest) | columns == 1 -> nextNeed rest
      (FSwitchColumns _ : _) -> 0
      (FRestoreColumns : _) -> 0
      [] -> 0
    free st = capacity - sUsed st - sNoteLines st
    isEmpty st = sUsed st == top st && null (sNotes st)
    place st f need = case f of
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
          sTables = []
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
    blankPage st = st {sDone = PageOut (sPage st) 0 True [] [] [] [] [] (sSet st) {csFirstLine = 0} : sDone st, sPage = sPage st + 1}
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
              ok = u' + nl' <= capacity && (null acc || last acc)
           in ((u', nl'), acc <> [ok])
    putLine st l =
      let noteLines = sum (map nbLines (lbNotes l))
          sep = if sNoteLines st == 0 && noteLines > 0 then separator else 0
          room = capacity - sUsed st - 1 - sNoteLines st - sep
          (shown, pending) = splitNotes room (lbNotes l)
       in st
            { sSlots = sSlots st <> [(sUsed st, SLine (lbId l))],
              sUsed = sUsed st + 1,
              sNoteLines = sNoteLines st + sep + sum [c | (_, _, c) <- shown],
              sNotes = sNotes st <> shown,
              sPendingNotes = sPendingNotes st <> pending,
              sLabels = sLabels st <> lbLabels l,
              sMarks = sMarks st <> lbMarks l
            }
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
          room = capacity - sUsed st - n - sNoteLines st - sep
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
        else st {sDone = PageOut (sPage st) (sColumn st) False (sSlots st) (sNotes st) (sLabels st) (sMarks st) (sTables st) (sSet st) : sDone st}
    -- the next column of the page, or column 0 of the next page
    nextColumn st = advance (sColumn st + 1 >= csColumns (sSet st)) st
    nextPage = advance True
    advance toPage st =
      let closed = closePage st
          -- a page left with nothing in any column is blank
          written = any ((== sPage st) . poNumber) (sDone closed)
          closed' = if toPage && not written then closed {sDone = PageOut (sPage st) 0 True [] [] [] [] [] (sSet st) {csFirstLine = 0} : sDone closed} else closed
          fresh =
            closed'
              { sPage = if toPage then sPage st + 1 else sPage st,
                sColumn = if toPage then 0 else sColumn st + 1,
                sSet = if toPage then (sSet st) {csFirstLine = 0} else sSet st,
                sReserved = if toPage then 0 else sReserved st,
                sUsed = if toPage then 0 else top st,
                sNoteLines = if toPage then 0 else sReserved st,
                sSlots = [],
                sNotes = [],
                sLabels = [],
                sMarks = [],
                sTables = [],
                sPendingNotes = []
              }
          withNotes = foldl' carryNote fresh (sPendingNotes st)
       in placeDeferred withNotes {sDeferred = []} (sDeferred st)
    carryNote st (i, from, len) =
      let sep = if sNoteLines st == 0 then separator else 0
          room = capacity - sNoteLines st - sep - 1
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
