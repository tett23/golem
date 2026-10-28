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
    grid,
    termNeed,
    needIn,
    headingNeed,
    fitting,
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

import Data.Maybe (isJust, listToMaybe)
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
  (FParagraph ls : _) -> linesNeed (take 2 ls)
  (FContinued ls : _) -> linesNeed (take 2 ls)
  (FTable _ sp h rows : _) -> grid (sp + length h + maybe 0 length (listToMaybe rows))
  (FDefTerm ls : _) -> termNeed ls
  -- a heading keeps what follows it, a heading after it too (golem-driver ADR 0032)
  (FHeading _ _ n ls : rest) -> Need n (noteLinesOf ls) <> nextNeed env rest
  (FFigure _ n _ _ : _) -> grid (min n capacity)
  (FPageFigure {} : _) -> mempty
  (FWrapped _ n _ _ ls : _) -> grid (max n (length ls))
  (FSpace _ : _) -> mempty
  (FBreak _ : _) -> mempty
  -- the controls of page breaks are skipped (docs/adr ADR 0030)
  (FNoBreak _ : rest) -> nextNeed env rest
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
          RuledLines _ -> grid size
  [] -> mempty
  where
    capacity = envCapacity env

-- | What a paragraph before a no-break keeps with it: the first part of what follows the no-break.
keptNeed :: Env -> [Flow] -> Maybe Need
keptNeed env rest = case dropWhile soft rest of
  FNoBreak _ : more -> Just (nextNeed env (dropWhile soft more))
  _ -> Nothing

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
  RuledLines ls -> ls
  RuledHeading _ _ ls -> ls

bodySize :: RuledBody -> Int
bodySize = \case
  RuledLines ls -> length ls
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
  RuledLines ls -> grid (k1 + length ls + k2)
  RuledHeading _ n ls -> Need (k1 + n + k2) (noteLinesOf ls)
