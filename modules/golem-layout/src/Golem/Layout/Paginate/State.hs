{- | The state of placing lines on pages (golem-layout ADR 0003) and the
operations that move it on: putting lines, blocks and figures in the
current column, closing a column, and going to the next column or page.
The queries 'free' and 'isEmpty' read the current column.
-}
module Golem.Layout.Paginate.State
  ( Env (..),
    St (..),
    initialState,
    top,
    cap,
    free,
    isEmpty,
    addUnmet,
    keep,
    parityStart,
    blankPage,
    putSlot,
    putLine,
    putLineKeeping,
    putBlock,
    closePage,
    nextColumn,
    nextPage,
    startSet,
    pageFigure,
    isPageFigure,
    flushDeferred,
    flushFigures,
  )
where

import Data.Text (Text)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Paginate.Types
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Syntax (SrcSpan)

{- | What stays the same through one pagination: the most grid lines a
column may have after 'FAdjustLines' (docs/adr ADR 0030), the grid lines
of the footnote separator (golem-driver ADR 0024), the columns of the
page (docs/adr ADR 0025) and the grid lines of a column.
-}
data Env = Env
  { envMaxLines :: !Int,
    -- | a footnote line always fits under the separator and one line of text
    envSeparator :: !Int,
    envBase :: !ColumnSet,
    envCapacity :: !Int
  }

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
    sLastDeferred :: !Bool,
    -- | whether the column has nothing but headings placed from its top (golem-layout ADR 0019)
    sHeadingOnly :: !Bool
  }

-- | Page 1, column 0, nothing placed, in the columns of the page.
initialState :: Env -> St
initialState env = St 1 0 0 0 [] [] [] [] [] [] [] [] [] (envBase env) {csFirstLine = 0} 0 [] Nothing Nothing 0 [] Nothing [] False False False

-- | The first grid line of the set of columns on this page.
top :: St -> Int
top st = csFirstLine (sSet st)

-- | The grid lines of the current column (docs/adr ADR 0030).
cap :: Env -> St -> Int
cap env st = envCapacity env + sAdjust st

-- | The grid lines left in the current column.
free :: Env -> St -> Int
free env st = cap env st - sUsed st - sNoteLines st

-- | Whether nothing is placed in the current column.
isEmpty :: St -> Bool
isEmpty st = sUsed st == top st && null (sNotes st)

addUnmet :: Unmet -> St -> St
addUnmet u st = st {sUnmet = sUnmet st <> [u]}

-- | The next column, unless @n@ grid lines are free or the column is empty.
keep :: Env -> St -> Int -> St
keep env st n = if n > free env st && not (isEmpty st) then nextColumn env st else st

-- | Start in column 0 of a page whose number satisfies p, after a blank page if needed.
parityStart :: Env -> (Int -> Bool) -> St -> St
parityStart env p st =
  let st1 = if isEmpty st && sColumn st == 0 then st else nextPage env st
   in if p (sPage st1) then st1 else blankPage env st1

blankPage :: Env -> St -> St
blankPage env st = st {sDone = PageOut (sPage st) 0 True [] [] [] [] [] (sSet st) {csFirstLine = 0} [] (envCapacity env) [] : sDone st, sPage = sPage st + 1}

putSlot :: St -> Int -> Slotted -> [Text] -> [SrcSpan] -> St
putSlot st n s labels marks = st {sSlots = sSlots st <> [(sUsed st, s)], sUsed = sUsed st + n, sLabels = sLabels st <> labels, sMarks = sMarks st <> marks, sHeadingOnly = False}

putLine :: Env -> St -> LineBox -> St
putLine env = putLineKeeping env 0

-- | A line, its notes in the room left after @reserve@ more grid lines of its block.
putLineKeeping :: Env -> Int -> St -> LineBox -> St
putLineKeeping env reserve st l =
  let noteLines = sum (map nbLines (lbNotes l))
      sep = if sNoteLines st == 0 && noteLines > 0 then envSeparator env else 0
      room = cap env st - sUsed st - 1 - reserve - sNoteLines st - sep
      (shown, pending) = splitNotes room (lbNotes l)
   in st
        { sSlots = sSlots st <> [(sUsed st, SLine (lbId l))],
          sUsed = sUsed st + 1,
          sNoteLines = sNoteLines st + (if null shown && reserve > 0 then 0 else sep) + sum [c | (_, _, c) <- shown],
          sNotes = sNotes st <> shown,
          sPendingNotes = sPendingNotes st <> pending,
          sLabels = sLabels st <> lbLabels l,
          sMarks = sMarks st <> lbMarks l,
          sHeadingOnly = False
        }

-- | A heading: one block of n grid lines; the notes of its lines as in 'putLine'.
putBlock :: Env -> St -> Int -> [LineBox] -> St
putBlock _ st _ [] = st
putBlock env st n ls@(l0 : _) =
  let tall = [TallHeading (lbId l0) n (free env st) | n > free env st]
      notes = concatMap lbNotes ls
      noteLines = sum (map nbLines notes)
      sep = if sNoteLines st == 0 && noteLines > 0 then envSeparator env else 0
      room = cap env st - sUsed st - n - sNoteLines st - sep
      (shown, pending) = splitNotes room notes
   in st
        { sSlots = sSlots st <> [(sUsed st, SHeading (lbId l0) (length ls))],
          sUsed = sUsed st + n,
          sNoteLines = sNoteLines st + (if null shown then 0 else sep) + sum [c | (_, _, c) <- shown],
          sNotes = sNotes st <> shown,
          sPendingNotes = sPendingNotes st <> pending,
          sLabels = sLabels st <> concatMap lbLabels ls,
          sMarks = sMarks st <> concatMap lbMarks ls,
          sHeadingOnly = isEmpty st || sHeadingOnly st,
          sUnmet = sUnmet st <> tall
        }

-- | A note longer than the room continues on the next page.
splitNotes :: Int -> [NoteBody] -> ([(NoteId, Int, Int)], [(NoteId, Int, Int)])
splitNotes = go'
  where
    go' _ [] = ([], [])
    go' r (NoteBody i len : rest)
      | len <= r = let (a, b) = go' (r - len) rest in ((i, 0, len) : a, b)
      | r > 0 = ([(i, 0, r)], (i, r, len - r) : [(j, 0, m) | NoteBody j m <- rest])
      | otherwise = ([], (i, 0, len) : [(j, 0, m) | NoteBody j m <- rest])

-- | An empty column makes no output.
closePage :: Env -> St -> St
closePage env st =
  if null (sSlots st) && null (sNotes st)
    then st
    else st {sDone = PageOut (sPage st) (sColumn st) False (sSlots st) (sNotes st) (sLabels st) (sMarks st) (sTables st) (sSet st) (sRules st) (cap env st) (sUnmet st) : sDone st, sUnmet = []}

-- | The next column of the page, or column 0 of the next page.
nextColumn :: Env -> St -> St
nextColumn env st = advance env (sColumn st + 1 >= csColumns (sSet st)) st

nextPage :: Env -> St -> St
nextPage env = advance env True

advance :: Env -> Bool -> St -> St
advance env toPage st =
  let closed = closePage env st
      -- a page left with nothing in any column is blank
      written = any ((== sPage st) . poNumber) (sDone closed)
      closed' = if toPage && not written then closed {sDone = PageOut (sPage st) 0 True [] [] [] [] [] (sSet st) {csFirstLine = 0} [] (envCapacity env) [] : sDone closed} else closed
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
            sPendingNotes = [],
            sHeadingOnly = False
          }
      -- the turned figures waiting first take pages of their own before the notes go on (golem-driver ADR 0034)
      (turned, waiting) = if toPage then span isPageFigure (sDeferred st) else ([], sDeferred st)
      fresh' = foldl' (\s' (i, labels, marks) -> pageFigure env s' i labels marks) fresh [(i, labels, marks) | FPageFigure i labels marks <- turned]
      withNotes = foldl' (carryNote env) fresh' (sPendingNotes st)
   in placeDeferred env withNotes {sDeferred = []} waiting

-- | The set starts at line @first@ of the page, above the footnotes already there.
startSet :: Env -> St -> ColumnSet -> Int -> St
startSet env st set first =
  (closePage env st)
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
      sJoin = Nothing,
      sHeadingOnly = False
    }

isPageFigure :: Flow -> Bool
isPageFigure = \case
  FPageFigure {} -> True
  _ -> False

-- | A page of nothing but a turned figure; the next page starts empty.
pageFigure :: Env -> St -> Int -> [Text] -> [SrcSpan] -> St
pageFigure env st i labels marks =
  st
    { sDone = PageOut (sPage st) 0 False [(0, SPageFigure i)] [] labels marks [] (sSet st) {csFirstLine = 0} [] (envCapacity env) [] : sDone st,
      sPage = sPage st + 1
    }

carryNote :: Env -> St -> (NoteId, Int, Int) -> St
carryNote env st (i, from, len) =
  let sep = if sNoteLines st == 0 then envSeparator env else 0
      room = cap env st - sNoteLines st - sep - 1
      shown = min len room
   in st
        { sNotes = sNotes st <> [(i, from, shown)],
          sNoteLines = sNoteLines st + sep + shown,
          sPendingNotes = sPendingNotes st <> [(i, from + shown, len - shown) | shown < len]
        }

placeDeferred :: Env -> St -> [Flow] -> St
placeDeferred _ st [] = st
placeDeferred env st (FFigure i n labels marks : rest)
  | n <= free env st || isEmpty st = placeDeferred env (putSlot st n (SFigure i) labels marks) rest
  | otherwise = st {sDeferred = FFigure i n labels marks : rest}
-- a turned figure waits for the next page, and the figures after it with it (golem-driver ADR 0034)
placeDeferred _ st rest@(FPageFigure {} : _) = st {sDeferred = rest}
placeDeferred env st (_ : rest) = placeDeferred env st rest

flushDeferred :: Env -> St -> St
flushDeferred env st
  | null (sDeferred st) && null (sPendingNotes st) = st
  | otherwise = flushDeferred env (nextColumn env st)

-- | The figures sent on are placed, the continued notes may go on beside them (golem-layout ADR 0015).
flushFigures :: Env -> St -> St
flushFigures env st
  | null (sDeferred st) = st
  | otherwise = flushFigures env (nextColumn env st)
