{- | Placing lines on pages (golem-layout ADR 0003): greedy page breaking
on the line grid, no orphans or widows, headings and definition terms
kept with what follows, recto starts, figures moved to the next page
when they do not fit, footnotes on the page of their marker, and the
fixed point of page-number references (S2).

Everything is counted in grid lines: a footnote line takes one grid
line from the bottom of the page and the footnote area is separated
from the text by one grid line.
-}
module Golem.Layout.Paginate
  ( LineBox (..),
    NoteBody (..),
    Flow (..),
    Slotted (..),
    PageOut (..),
    TableSegment (..),
    HeadingBlock (..),
    headingBlock,
    paginate,
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
import Golem.Syntax (SrcSpan)

data NoteBody = NoteBody {nbId :: !Int, nbLines :: !Int}
  deriving stock (Eq, Show)

data LineBox = LineBox
  { lbId :: !Int,
    lbNotes :: ![NoteBody],
    lbLabels :: ![Text],
    -- | index marks on the line (golem-driver ADR 0007)
    lbMarks :: ![SrcSpan]
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
  | -- | a table: its header row and body rows, in grid lines (golem-driver ADR 0008)
    FTable {ftId :: !Int, ftHeader :: ![LineBox], ftRows :: ![[LineBox]]}
  | {- | empty grid lines, as between stanzas of verse (docs/adr ADR 0003);
    nothing at the top of a page
    -}
    FSpace !Int
  deriving stock (Eq, Show)

data Slotted
  = SLine !Int
  | SFigure !Int
  | SWrapped !Int
  | -- | a heading block: its first line and how many lines it has
    SHeading !Int !Int
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
size is kept, the span is the fewest grid lines that hold it, and the
heading is centred in them. Integer sp; one rounding.
-}
headingBlock :: Integer -> Integer -> Integer -> Int -> HeadingBlock
headingBlock fs p s m =
  let hp = round (p * s % fs)
      extent = toInteger (max 1 m - 1) * hp + s
      n = max 1 ((extent + p - fs + p - 1) `div` p)
      area = (n - 1) * p + fs
   in HeadingBlock hp (fromInteger n) ((area - extent) `div` 2)

data PageOut = PageOut
  { poNumber :: !Int,
    poBlank :: !Bool,
    -- | grid line index and what starts there
    poSlots :: ![(Int, Slotted)],
    -- | note id, first line of the body shown here, number of lines
    poFootnotes :: ![(Int, Int, Int)],
    poLabels :: ![Text],
    -- | the index marks placed on the page (golem-driver ADR 0007)
    poMarks :: ![SrcSpan],
    -- | the parts of tables on the page (golem-driver ADR 0008)
    poTables :: ![TableSegment]
  }
  deriving stock (Eq, Show)

-- | The part of a table on a page, in grid lines.
data TableSegment = TableSegment
  { tsTable :: !Int,
    tsFirst :: !Int,
    -- | the last grid line of the header row
    tsHeaderEnd :: !Int,
    tsLast :: !Int
  }
  deriving stock (Eq, Show)

data St = St
  { sPage :: !Int,
    sUsed :: !Int, -- grid lines used from the top
    sNoteLines :: !Int, -- footnote lines used from the bottom (separator included)
    sSlots :: ![(Int, Slotted)],
    sNotes :: ![(Int, Int, Int)],
    sLabels :: ![Text],
    sMarks :: ![SrcSpan],
    sTables :: ![TableSegment],
    sDone :: ![PageOut],
    sDeferred :: ![Flow],
    sPendingNotes :: ![(Int, Int, Int)] -- note id, next line, remaining
  }

-- | Lays the flow out on pages of @capacity@ grid lines.
paginate :: Int -> [Flow] -> [PageOut]
paginate capacity flows =
  let st0 = St 1 0 0 [] [] [] [] [] [] [] []
      final = closePage (go st0 flows)
   in reverse (sDone final)
  where
    go st [] = flushDeferred st
    go st (f : rest) = go (place st f (nextNeed rest)) rest
    nextNeed = \case
      (FParagraph ls : _) -> min 2 (length ls)
      (FContinued ls : _) -> min 2 (length ls)
      (FTable _ h rows : _) -> length h + maybe 0 length (listToMaybe rows)
      (FDefTerm ls : _) -> length ls
      (FHeading _ _ n _ : _) -> n
      (FFigure _ n _ _ : _) -> min n capacity
      (FWrapped _ n _ _ ls : _) -> max n (length ls)
      (FSpace _ : _) -> 0
      [] -> 0
    free st = capacity - sUsed st - sNoteLines st
    isEmpty st = sUsed st == 0 && null (sNotes st)
    place st f need = case f of
      FParagraph ls -> placeLines st True ls
      FContinued ls -> placeLines st False ls
      FTable i h rows ->
        let st1 = if length h + maybe 0 length (listToMaybe rows) > free st && not (isEmpty st) then newPage st else st
         in placeTable st1 i h rows
      FDefTerm ls -> placeLines (keep st (length ls + need)) True ls
      FHeading _ recto n ls ->
        let st1 = if recto then rectoStart st else keep st (n + need)
            st2 = if n <= free st1 || isEmpty st1 then st1 else newPage st1
         in putBlock st2 n ls
      FFigure i n labels marks
        | n <= free st || isEmpty st -> putSlot st n (SFigure i) labels marks
        | otherwise -> st {sDeferred = sDeferred st <> [f]}
      FWrapped i n labels marks beside ->
        let size = max n (length beside)
            st1 = if size <= free st || isEmpty st then st else newPage st
            st2 = putSlot st1 0 (SWrapped i) labels marks
         in (placeLines st2 False beside) {sUsed = max (sUsed st1 + size) (sUsed (placeLines st2 False beside))}
      FSpace n
        | sUsed st == 0 -> st
        | otherwise -> st {sUsed = sUsed st + max 0 (min n (free st))}
    keep st n = if n > free st && not (isEmpty st) then newPage st else st
    rectoStart st =
      let st1 = if isEmpty st then st else newPage st
       in if even (sPage st1) then blankPage st1 else st1
    blankPage st = st {sDone = PageOut (sPage st) True [] [] [] [] [] : sDone st, sPage = sPage st + 1}
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
               in placeLines (newPage st1) (isStart && k == 0) (drop k ls)
    -- how many lines fit, with their notes
    fitting st ls = length (takeWhile id (snd (foldl' step ((sUsed st, sNoteLines st), []) ls)))
      where
        step ((u, nl), acc) l =
          let noteLines = sum (map nbLines (lbNotes l))
              sep = if nl == 0 && noteLines > 0 then 1 else 0
              u' = u + 1
              nl' = nl + noteLines + sep
              ok = u' + nl' <= capacity && (null acc || last acc)
           in ((u', nl'), acc <> [ok])
    putLine st l =
      let noteLines = sum (map nbLines (lbNotes l))
          sep = if sNoteLines st == 0 && noteLines > 0 then 1 else 0
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
                    fresh = newPage closed
                    repeated = foldl' putLine fresh [l {lbNotes = [], lbLabels = [], lbMarks = []} | l <- h]
                 in go repeated (sUsed fresh) (r : rest)
          segment stc first = stc {sTables = sTables stc <> [TableSegment i first (first + length h - 1) (sUsed stc - 1)]}
       in go st1 start rows
    -- a heading: one block of n grid lines; the notes of its lines as in putLine
    putBlock st _ [] = st
    putBlock st n ls@(l0 : _) =
      let notes = concatMap lbNotes ls
          noteLines = sum (map nbLines notes)
          sep = if sNoteLines st == 0 && noteLines > 0 then 1 else 0
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
    closePage st =
      if null (sSlots st) && null (sNotes st) && not (null (sDone st))
        then st
        else st {sDone = PageOut (sPage st) False (sSlots st) (sNotes st) (sLabels st) (sMarks st) (sTables st) : sDone st}
    newPage st =
      let closed = closePage st
          fresh = closed {sPage = sPage st + 1, sUsed = 0, sNoteLines = 0, sSlots = [], sNotes = [], sLabels = [], sMarks = [], sTables = [], sPendingNotes = []}
          withNotes = foldl' carryNote fresh (sPendingNotes st)
       in placeDeferred withNotes {sDeferred = []} (sDeferred st)
    carryNote st (i, from, len) =
      let sep = if sNoteLines st == 0 then 1 else 0
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
      | otherwise = flushDeferred (newPage st)

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
