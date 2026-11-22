-- | Retain book parts by trying only their flow at the current pagination state.
module Golem.Layout.Paginate.BookParts (placeBookPart, flattenBookParts, flowSlotIds) where

import Data.IntSet qualified as IS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Layout.Paginate.State
import Golem.Layout.Paginate.Types
import Golem.Project.Style (KeepParts (..))
import Golem.Syntax (SrcSpan)

-- | Failed trial states are discarded together with their unmet controls and notes.
placeBookPart :: Env -> (St -> [Flow] -> St) -> St -> KeepParts -> SrcSpan -> Text -> [Int] -> [Flow] -> St
placeBookPart env run initial unit span' kind retained body
  | IS.null wanted = run initial body
  | unit == KeepColumn = if fits emptyTrial then ordinary else report ordinary
  | fits ordinary = ordinary
  | fits movedTrial = movedTrial
  | emptyUnit initial = report (run initial body)
  | otherwise = report (run moved body)
  where
    wanted = IS.fromList retained
    plain = flattenBookParts body
    ordinary = if unit == KeepColumn then run initial body else trial initial
    moved = nextUnit initial
    movedTrial = trial moved
    emptyTrial = if emptyUnit initial then ordinary else movedTrial
    nested = any hasNested body
    hasNested FBookPart {} = True
    hasNested (FBoxed _ _ _ contents) = any hasNested contents
    hasNested _ = False
    whole = IS.fromList (concatMap flowSlotIds plain) `IS.isSubsetOf` wanted
    trial state =
      let placed = run state plain
          completed = if unit == KeepColumn then placed else flushFigures env placed
       in if whole || not nested || not (fits completed) then completed else flushFigures env (run state body)
    report = addUnmet (SplitBookPart span' kind unit)
    fits state =
      let columns = takeWhile ((>= sPage initial) . poNumber) (sDone state)
          entries = [(poNumber p, poColumn p, poSlots p) | p <- columns] <> [(sPage state, sColumn state, sSlots state)]
          found = Map.fromListWith min [(ident, key p c) | (p, c, slots) <- entries, (_, slot) <- slots, ident <- slotIds slot, IS.member ident wanted]
       in IS.size wanted == Map.size found && case Map.elems found of [] -> True; first : rest -> all (== first) rest
    key p c = case unit of
      KeepColumn -> (p, c)
      KeepPage -> (p, 0)
      KeepSpread -> (if p == 1 then 0 else p `div` 2, 0)
    emptyUnit state =
      isEmpty state && top state == 0 && case unit of
        KeepColumn -> True
        KeepPage -> sColumn state == 0
        KeepSpread -> sColumn state == 0 && (sPage state == 1 || even (sPage state))
    nextUnit state = case unit of
      KeepColumn -> nextColumn env state
      KeepPage -> nextPage env state
      KeepSpread ->
        let target = if sPage state == 1 then 2 else 2 * (sPage state `div` 2 + 1)
            go here = let next = nextPage env here in if sPage next < target then go next else next
         in go state

flattenBookParts :: [FlowAt position] -> [FlowAt position]
flattenBookParts = concatMap $ \case
  FBookPart _ _ _ _ body -> flattenBookParts body
  FBoxed i before after body -> [FBoxed i before after (flattenBookParts body)]
  flow -> [flow]

flowSlotIds :: FlowAt position -> [Int]
flowSlotIds = \case
  FBookPart _ _ _ _ body -> concatMap flowSlotIds body
  FParagraph _ ls -> map lbId ls
  FContinued _ ls -> map lbId ls
  FDefTerm ls -> map lbId ls
  FStanza _ vs -> map lbId (concat vs)
  FHeading _ _ _ ls -> map lbId (take 1 ls)
  FFigure i _ _ _ -> [i]
  FPageFigure i _ _ -> [i]
  FWrapped i _ _ _ beside -> i : map lbId beside
  FTable _ _ header rows caption _ -> map lbId (header <> concat rows <> caption)
  FCode _ _ _ _ rows -> map lbId rows
  FRuled {frBody = body} -> case body of RuledLines _ ls -> map lbId ls; RuledHeading _ _ ls -> map lbId (take 1 ls)
  FBoxed _ _ _ body -> concatMap flowSlotIds body
  _ -> []

slotIds :: Slotted -> [Int]
slotIds = \case
  SLine i -> [i]
  SFigure i -> [i]
  SWrapped i -> [i]
  SPageFigure i -> [i]
  SHeading i _ -> [i]
  SCode i count _ -> [i .. i + count - 1]
