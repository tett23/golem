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
    paginate,
    labelPages,
    resolvePageRefs,
    maxIterations,
  )
where

import Control.Applicative ((<|>))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)

data NoteBody = NoteBody {nbId :: !Int, nbLines :: !Int}
  deriving stock (Eq, Show)

data LineBox = LineBox
  { lbId :: !Int,
    lbNotes :: ![NoteBody],
    lbLabels :: ![Text]
  }
  deriving stock (Eq, Show)

data Flow
  = FParagraph [LineBox]
  | FHeading {fhLevel :: !Int, fhShort :: !Text, fhRecto :: !Bool, fhLines :: [LineBox]}
  | FDefTerm [LineBox]
  | -- | a figure with its caption, in grid lines
    FFigure {ffId :: !Int, ffLines :: !Int, ffLabels :: ![Text]}
  | -- | a wrapped figure and the shortened lines set beside it (ADR 0004)
    FWrapped {fwId :: !Int, fwLines :: !Int, fwLabels :: ![Text], fwBeside :: [LineBox]}
  deriving stock (Eq, Show)

data Slotted = SLine !Int | SFigure !Int | SWrapped !Int
  deriving stock (Eq, Show)

data PageOut = PageOut
  { poNumber :: !Int,
    poBlank :: !Bool,
    -- | grid line index and what starts there
    poSlots :: ![(Int, Slotted)],
    -- | note id, first line of the body shown here, number of lines
    poFootnotes :: ![(Int, Int, Int)],
    poRunningHead :: !(Maybe Text),
    poLabels :: ![Text]
  }
  deriving stock (Eq, Show)

data St = St
  { sPage :: !Int,
    sUsed :: !Int, -- grid lines used from the top
    sNoteLines :: !Int, -- footnote lines used from the bottom (separator included)
    sSlots :: ![(Int, Slotted)],
    sNotes :: ![(Int, Int, Int)],
    sLabels :: ![Text],
    sDone :: ![PageOut],
    sDeferred :: ![Flow],
    sPendingNotes :: ![(Int, Int, Int)], -- note id, next line, remaining
    sHead :: !(Maybe Text),
    sPageHead :: !(Maybe Text)
  }

-- | Lays the flow out on pages of @capacity@ grid lines.
paginate :: Int -> [Flow] -> [PageOut]
paginate capacity flows =
  let st0 = St 1 0 0 [] [] [] [] [] [] Nothing Nothing
      final = closePage (go st0 flows)
   in reverse (sDone final)
  where
    go st [] = flushDeferred st
    go st (f : rest) = go (place st f (nextNeed rest)) rest
    nextNeed = \case
      (FParagraph ls : _) -> min 2 (length ls)
      (FDefTerm ls : _) -> length ls
      (FHeading _ _ _ ls : _) -> length ls
      (FFigure _ n _ : _) -> min n capacity
      (FWrapped _ n _ ls : _) -> max n (length ls)
      [] -> 0
    free st = capacity - sUsed st - sNoteLines st
    isEmpty st = sUsed st == 0 && null (sNotes st)
    place st f need = case f of
      FParagraph ls -> placeLines st True ls
      FDefTerm ls -> placeLines (keep st (length ls + need)) True ls
      FHeading lvl short recto ls ->
        let st1 = if recto then rectoStart st else keep st (length ls + need)
            st2 = if lvl == 1 then st1 {sHead = Just short, sPageHead = sPageHead st1 <|> Just short} else st1
         in placeLines st2 True ls
      FFigure i n labels
        | n <= free st || isEmpty st -> putSlot st n (SFigure i) labels
        | otherwise -> st {sDeferred = sDeferred st <> [f]}
      FWrapped i n labels beside ->
        let size = max n (length beside)
            st1 = if size <= free st || isEmpty st then st else newPage st
            st2 = putSlot st1 0 (SWrapped i) labels
         in (placeLines st2 False beside) {sUsed = max (sUsed st1 + size) (sUsed (placeLines st2 False beside))}
    keep st n = if n > free st && not (isEmpty st) then newPage st else st
    rectoStart st =
      let st1 = if isEmpty st then st else newPage st
       in if even (sPage st1) then blankPage st1 else st1
    blankPage st = st {sDone = PageOut (sPage st) True [] [] Nothing [] : sDone st, sPage = sPage st + 1}
    putSlot st n s labels = st {sSlots = sSlots st <> [(sUsed st, s)], sUsed = sUsed st + n, sLabels = sLabels st <> labels}
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
              sLabels = sLabels st <> lbLabels l
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
        else st {sDone = PageOut (sPage st) False (sSlots st) (sNotes st) (pageHead st) (sLabels st) : sDone st}
    pageHead st = sPageHead st <|> sHead st
    newPage st =
      let closed = closePage st
          fresh = closed {sPage = sPage st + 1, sUsed = 0, sNoteLines = 0, sSlots = [], sNotes = [], sLabels = [], sPendingNotes = [], sPageHead = Nothing}
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
    placeDeferred st (FFigure i n labels : rest)
      | n <= free st || isEmpty st = placeDeferred (putSlot st n (SFigure i) labels) rest
      | otherwise = st {sDeferred = FFigure i n labels : rest}
    placeDeferred st (_ : rest) = placeDeferred st rest
    flushDeferred st
      | null (sDeferred st) && null (sPendingNotes st) = st
      | otherwise = flushDeferred (newPage st)

-- | The page of each label.
labelPages :: [PageOut] -> Map Text Integer
labelPages ps = Map.fromList [(l, toInteger (poNumber p)) | p <- ps, l <- poLabels p]

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
