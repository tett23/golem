{- | The decisions of placing lines on pages (golem-layout ADR 0003):
what the flows after a place need, how many lines fit, and the plan of a
ruled block. They read the state and never change it.
-}
module Golem.Layout.Paginate.Decide
  ( Need (..),
    Plan,
    noteLinesOf,
    nextNeed,
    keptNeed,
    keepAhead,
    nextFirstLines,
    splitAtBreak,
    firstPart,
    grid,
    termNeed,
    needIn,
    headingNeed,
    fitting,
    tableHead,
    roomForLine,
    afterPageFigure,
    startsRecto,
    isRecto,
    isHeadingBody,
    planOf,
    planNeed,
    planParts,
  )
where

import Data.List (find)
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Golem.Layout.Code (codeSpan)
import Golem.Layout.Paginate.State
import Golem.Layout.Paginate.Types
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..), ruleAfter, ruleAfterAtEnd, ruleBefore, ruleBeforeAtStart, rulesJoined)
import Golem.Length (Sp)

{- | The first part of what follows a heading, a term or a kept paragraph:
its grid lines and the lines of the notes of its lines (golem-layout ADR 0019).
-}
data Need = Need {needGrid :: !Int, needNotes :: !Int}

instance Semigroup Need where
  Need a b <> Need c d = Need (a + c) (b + d)

instance Monoid Need where
  mempty = Need 0 0

{- | The plan of a ruled block: the grid lines of the area of its rule
before, its rules placed before it, the grid lines of the area of its rule
after, its rules placed after it, and the rule after that waits for the
next block.
-}
type Plan = (Int, [PlacedRule], Int, [PlacedRule], Maybe (Int, RuleGrid, RuleSide, Int))

-- | The lines of the notes of some lines.
noteLinesOf :: [LineBox] -> Int
noteLinesOf = sum . map nbLines . concatMap lbNotes

-- | The first part of what follows, with the notes of its lines (golem-layout ADR 0019).
nextNeed :: Env -> [Flow] -> Need
nextNeed env = \case
  -- a heading at a recto starts a page of its own: nothing before it keeps it (docs/adr/0206)
  (f : _) | startsRecto f -> mempty
  -- the first part that can be split from the rest (golem-layout ADR 0021)
  -- with the keep of the paragraph (docs/adr/0261)
  (FParagraph kp ls : _) -> linesNeed (take (firstPart kp True (length ls)) ls)
  (FContinued kp ls : _) -> linesNeed (take (firstPart kp False (length ls)) ls)
  -- of a stanza, its verse lines (docs/adr/0180, golem-layout ADR 0021)
  (FStanza kp vs : _) -> linesNeed (concat (take (firstPart kp True (length vs)) vs))
  (FTable _ sp h rows capt below : _) -> grid (sp + tableHead h rows capt below)
  (FDefTerm ls : _) -> termNeed ls
  -- a heading keeps what follows it, a heading after it too (golem-driver ADR 0032)
  (FHeading _ _ n ls : rest) -> Need n (noteLinesOf ls) <> nextNeed env rest
  (FFigure _ n _ _ : _) -> grid (min n capacity)
  (FPageFigure {} : _) -> mempty
  (FWrapped _ n _ _ ls : _) -> grid (max n (length ls))
  -- the space before a paragraph goes with what follows it (docs/adr/0205)
  (FSpace n : rest) -> spaced env n (nextNeed env rest)
  (FBreak _ : _) -> mempty
  (FSection {} : _) -> mempty
  -- the controls of page breaks are skipped (docs/adr ADR 0030)
  (FNoBreak _ : rest) -> nextNeed env rest
  (FKeepNext _ _ : rest) -> nextNeed env rest
  (FNeedLines _ _ : rest) -> nextNeed env rest
  (FAdjustLines _ _ : rest) -> nextNeed env rest
  -- blank lines go with what follows, at most a column (docs/adr ADR 0046)
  (FBlank _ n : rest) -> let r = nextNeed env rest in r {needGrid = min capacity (min capacity n + needGrid r)}
  (FCode g caption first cont ls : _)
    | null ls -> mempty
    | otherwise -> let k = min (length ls) (max 1 first) in grid (caption + codeSpan g (k + (if cont && k < length ls then 1 else 0)))
  -- a heading before the index columns on a page of one column keeps their first line
  (FSwitchColumns _ : rest) | csColumns (envBase env) == 1 -> nextNeed env rest
  (FSwitchColumns _ : _) -> mempty
  (FRestoreColumns : _) -> mempty
  -- a ruled block keeps whole, its areas counted inside a column (golem-driver ADR 0027);
  -- a ruled heading counts its notes, a ruled paragraph does not
  (fr@FRuled {} : _) ->
    let size = fst (insideBefore fr) + bodySize (frBody fr) + fst (insideAfter fr)
     in case frBody fr of
          RuledHeading _ _ ls -> Need size (noteLinesOf ls)
          RuledLines _ _ -> grid size
  -- a box: its grid lines before and the first part of its body, and its grid lines after when that is all of it (docs/adr/0271)
  (FBoxed _ kb ka body : _) ->
    let n = nextNeed env body
        whole = case body of
          [FParagraph kp ls] -> firstPart kp True (length ls) >= length ls
          [FStanza kp vs] -> firstPart kp True (length vs) >= length vs
          _ -> False
     in n {needGrid = kb + needGrid n + (if whole then ka else 0)}
  [] -> mempty
  where
    capacity = envCapacity env

{- | What a paragraph before a no-break keeps with it: the spaces before
the no-break and the first part of what follows it, its spaces too, at
most a column (golem-layout ADR 0022).
-}
keptNeed :: Env -> [Flow] -> Maybe Need
keptNeed env rest = (\(before, n, after) -> spaced env (sum [max 0 k | FSpace k <- before]) (followNeed env n after)) <$> keepAhead rest

{- | The flows before a no-break or a keep-with-next (docs/adr/0261) that
the paragraph before waits past, the lines of the keep-with-next (0 for a
no-break alone; the larger of two at one place), and the flows after
them; nothing when the paragraph does not wait.
-}
keepAhead :: [Flow] -> Maybe ([Flow], Int, [Flow])
keepAhead rest = case span soft rest of
  (before, c : after) | Just n <- control c -> Just (go before n after)
  _ -> Nothing
  where
    control = \case
      FNoBreak _ -> Just 0
      FKeepNext _ n -> Just n
      _ -> Nothing
    go before n after = case span soft after of
      (more, c : after') | Just m <- control c -> go (before <> more) (max n m) after'
      _ -> (before, n, after)

{- | The first part of what follows a keep-with-next of @n@ lines
(docs/adr/0261): of a paragraph or a stanza, its first part made at
least @n@ lines (verse lines), at most the whole; when that is the whole
and it keeps with what follows it too, that too, at most a column. With
@n@ = 0, the first part of 'nextNeed'.
-}
followNeed :: Env -> Int -> [Flow] -> Need
followNeed env n after
  | n <= 0 = nextNeed env after
  | otherwise = case after of
      FParagraph kp ls : more -> chain (length ls) (max (firstPart kp True (length ls)) (min n (length ls))) (\k -> linesNeed (take k ls)) more
      FContinued kp ls : more -> chain (length ls) (max (firstPart kp False (length ls)) (min n (length ls))) (\k -> linesNeed (take k ls)) more
      FStanza kp vs : more -> chain (length vs) (max (firstPart kp True (length vs)) (min n (length vs))) (\k -> linesNeed (concat (take k vs))) more
      _ -> nextNeed env after
  where
    chain total k needOf more =
      let base = needOf k
       in case keepAhead more of
            Just (before, m, after')
              | k >= total,
                m > 0 ->
                  let r = spaced env (sum [max 0 x | FSpace x <- before]) (followNeed env m after')
                   in Need (min (envCapacity env) (needGrid base + needGrid r)) (needNotes base + needNotes r)
            _ -> base

{- | The lines of the first part of what follows a keep-with-next of @n@
lines that must be in the column of the paragraph before
(docs/adr/0261): of a paragraph, its first part made at least @n@ lines;
of a stanza, the lines of its first verse lines so made; one slot of
anything else. With whether only the lines count, not the figures placed
in the column.
-}
nextFirstLines :: Int -> [Flow] -> (Int, Bool)
nextFirstLines n after = case dropWhile skipped after of
  -- of a box, those of its body (docs/adr/0271)
  FBoxed {fbBody = body} : _ -> nextFirstLines n body
  FParagraph kp ls : _ -> (max (firstPart kp True (length ls)) (min n (length ls)), True)
  FContinued kp ls : _ -> (max (firstPart kp False (length ls)) (min n (length ls)), True)
  FStanza kp vs : _ -> (length (concat (take (max (firstPart kp True (length vs)) (min n (length vs))) vs)), True)
  _ -> (1, False)
  where
    skipped = \case
      FSpace _ -> True
      FNeedLines {} -> True
      FAdjustLines {} -> True
      FNoBreak _ -> True
      FKeepNext {} -> True
      FBlank {} -> True
      _ -> False

-- | @n@ lines of space before what follows, at most a column.
spaced :: Env -> Int -> Need -> Need
spaced env n r = r {needGrid = min (envCapacity env) (max 0 n + needGrid r)}

{- | Of @n@ lines (or verse lines) of which @k@ fit before a break, how
many go before it (golem-layout ADR 0003): the last line does not go
alone after the break (a widow), and the first line of a paragraph that
starts here does not stay alone before it (an orphan).
-}
splitAtBreak :: Keep -> Bool -> Int -> Int -> Int
splitAtBreak kp isStart n k
  | k >= n = k
  -- keep-all-lines (docs/adr/0261)
  | kAll kp = 0
  | otherwise =
      let k1 = if n - k < kLast kp then max 0 (n - kLast kp) else k -- widow: the last part at least kLast
       in if isStart && k1 > 0 && k1 < kFirst kp then 0 else k1 -- orphan: the first part at least kFirst

{- | The first part of @n@ lines that what comes before keeps with it: the
fewest lines, at least kFirst, that 'splitAtBreak' places before a break
(golem-layout ADR 0021, docs/adr/0261); all of a paragraph of
keep-all-lines. With 'defaultKeep', all of three lines or fewer, two of more.
-}
firstPart :: Keep -> Bool -> Int -> Int
firstPart kp isStart n
  | kAll kp = n
  | otherwise = fromMaybe n (find (\k -> splitAtBreak kp isStart n k == k) [min (kFirst kp) n .. n])

-- | The flows a no-break looks past.
soft :: Flow -> Bool
soft = \case
  FNeedLines {} -> True
  FAdjustLines {} -> True
  FSpace _ -> True
  _ -> False

grid :: Int -> Need
grid n = Need n 0

linesNeed :: [LineBox] -> Need
linesNeed ls = Need (length ls) (noteLinesOf ls)

termNeed :: [LineBox] -> Need
termNeed = linesNeed

{- | The need of a heading or a term @a@ and what follows it @b@ in the
column of @st@: the separator once, if the column has no notes yet and
either has notes (golem-layout ADR 0013, 0019).
-}
needIn :: Env -> St -> Need -> Need -> Int
needIn env st a b =
  let notes = needNotes a + needNotes b
      sep = if sNoteLines st == 0 && notes > 0 then envSeparator env else 0
   in needGrid a + needGrid b + notes + sep

-- | The grid lines of a heading, the lines of its notes and the separator if they are the first notes.
headingNeed :: Env -> St -> Int -> [LineBox] -> Int
headingNeed env st n ls = needIn env st (Need n (noteLinesOf ls)) mempty

{- | The grid lines a table keeps together at its start (golem-layout ADR
0025, docs/adr/0262): its header row and first row, and its caption above
them, or below them when the first row is the last.
-}
tableHead :: [LineBox] -> [[LineBox]] -> [LineBox] -> Bool -> Int
tableHead h rows capt below =
  length h + maybe 0 length (listToMaybe rows) + (if not below || length rows <= 1 then length capt else 0)

-- | How many lines fit, with their notes.
fitting :: Env -> St -> [LineBox] -> Int
fitting env st ls = length (takeWhile id (snd (foldl' step ((sUsed st, sNoteLines st), []) ls)))
  where
    step ((u, nl), acc) l =
      let noteLines = sum (map nbLines (lbNotes l))
          sep = if nl == 0 && noteLines > 0 then envSeparator env else 0
          u' = u + 1
          nl' = nl + noteLines + sep
          ok = u' + nl' <= cap env st && (null acc || last acc)
       in ((u', nl'), acc <> [ok])

-- | Room for the first line, the separator and a line of its notes if it has any.
roomForLine :: Env -> St -> [LineBox] -> Bool
roomForLine env st ls =
  let noteLines = noteLinesOf (take 1 ls)
      sep = if sNoteLines st == 0 && noteLines > 0 then envSeparator env else 0
   in free env st >= 1 + (if noteLines > 0 then sep + 1 else 0)

-- | Whether the page before is a turned figure (golem-driver ADR 0039).
afterPageFigure :: St -> Bool
afterPageFigure st = case sDone st of
  (po : _) -> poNumber po == sPage st - 1 && any (\case (_, SPageFigure _) -> True; _ -> False) (poSlots po)
  [] -> False

-- | Whether the flow is a heading at a recto.
startsRecto :: Flow -> Bool
startsRecto = \case
  FHeading {fhRecto = True} -> True
  FRuled {frBody = RuledHeading {rhRecto = True}} -> True
  _ -> False

isRecto :: RuledBody -> Bool
isRecto = \case
  RuledHeading True _ _ -> True
  _ -> False

isHeadingBody :: RuledBody -> Bool
isHeadingBody = \case
  RuledHeading {} -> True
  _ -> False

bodyLines :: RuledBody -> [LineBox]
bodyLines = \case
  RuledLines _ ls -> ls
  RuledHeading _ _ ls -> ls

bodySize :: RuledBody -> Int
bodySize = \case
  RuledLines _ ls -> length ls
  RuledHeading _ n _ -> n

firstOverhang :: Flow -> Sp
firstOverhang fr = maybe 0 lbOverhang (listToMaybe (bodyLines (frBody fr)))

-- | The areas inside a column, for 'nextNeed'.
insideBefore, insideAfter :: Flow -> (Int, Sp)
insideBefore fr = maybe (0, 0) (\b -> ruleBefore (frGrid fr) b (firstOverhang fr)) (frBefore fr)
insideAfter fr = maybe (0, 0) (\a -> ruleAfter (frGrid fr) a (frNextOverhang fr)) (frAfter fr)

-- | Whether the rule after waits for the next block to share its area.
joinsNext :: Flow -> [Flow] -> Bool
joinsNext fr rest =
  isJust (frAfter fr) && case rest of
    (FRuled {frJoined = True, frBefore = Just _} : _) -> True
    _ -> False

{- | The plan of a block at the place of the column: the lines of its
areas, its rules placed before and after it, and the rule after that
waits for the next block.
-}
planOf :: Env -> St -> Flow -> [Flow] -> Maybe ((Int, RuleGrid, RuleSide, Int), RuleSide) -> Plan
planOf env st fr rest joined =
  let g@(RuleGrid p h) = frGrid fr
      u = sUsed st
      n = bodySize (frBody fr)
      r1 = firstOverhang fr
      (k1, before) = case (joined, frBefore fr) of
        (Just ((aid, ga, a, aLast), b), _) ->
          let (k, offA, offB) = rulesJoined ga a b r1
              joinBase = fromIntegral (aLast :: Int) * p + h
           in (k, [PlacedRule aid False (joinBase + offA), PlacedRule (frId fr) True (joinBase + offB)])
        (Nothing, Just b)
          | u == top st ->
              let (k, off) = ruleBeforeAtStart g b {rsdOutside = if top st == 0 then rsdOutside b else Nothing} r1
               in (k, [PlacedRule (frId fr) True (fromIntegral u * p + off)])
          | otherwise ->
              let (k, off) = ruleBefore g b r1
               in (k, [PlacedRule (frId fr) True (fromIntegral (u - 1) * p + h + off)])
        (Nothing, Nothing) -> (0, [])
      lastLine = u + k1 + n - 1
      (k2, after) = case frAfter fr of
        Just a
          | not (joinsNext fr rest) ->
              let (ki, offi) = ruleAfter g a (frNextOverhang fr)
                  notes = sNoteLines st > 0 || not (all (null . lbNotes) (bodyLines (frBody fr)))
                  (k, off)
                    | lastLine + 1 + ki >= cap env st - sNoteLines st = ruleAfterAtEnd g a {rsdOutside = if notes then Nothing else rsdOutside a}
                    | otherwise = (ki, offi)
               in (k, [PlacedRule (frId fr) False (fromIntegral lastLine * p + h + off)])
        _ -> (0, [])
      waiting = case frAfter fr of
        Just a | joinsNext fr rest -> Just (frId fr, g, a, lastLine)
        _ -> Nothing
   in (k1, before, k2, after, waiting)

planNeed :: Env -> St -> Flow -> Plan -> Int
planNeed env st fr plan = needIn env st (planParts fr plan) mempty

-- | A paragraph's block fits by its grid lines alone, a heading's counts its notes.
planParts :: Flow -> Plan -> Need
planParts fr (k1, _, k2, _, _) = case frBody fr of
  RuledLines _ ls -> grid (k1 + length ls + k2)
  RuledHeading _ n ls -> Need (k1 + n + k2) (noteLinesOf ls)
