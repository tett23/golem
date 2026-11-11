{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

module PaginateElementsEnum (paginateElementsTests) where

import Control.Monad (replicateM)
import Data.List (sort)
import Golem.Layout.Code (codeGeometry)
import Golem.Layout.Paginate
import Golem.Layout.RuleArea
import Golem.Syntax (FileId (..), mkSpan)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)

data Piece = Rule | Code | Columns | Restore | NeedRows | Blank | Adjust | KeepTogether | Table | Wrapped
  deriving stock (Eq, Show, Enum, Bounded)

flow :: Int -> Piece -> (Flow, [Int])
flow index piece =
  let identifier = index * 10
      line = LineBox identifier [] [] [] 0
      at = mkSpan (FileId 0) index (index + 1)
   in case piece of
        Rule -> (FRuled identifier (Just (RuleSide 0 0 1 False Nothing)) Nothing False (RuleGrid 10 8) 0 (RuledLines defaultKeep [line]), [identifier])
        Code -> (FCode (codeGeometry 8 10 8 0) 0 1 False [line], [identifier])
        Columns -> (FSwitchColumns (ColumnSet 2 0 0 0), [])
        Restore -> (FRestoreColumns, [])
        NeedRows -> (FNeedLines at 2, [])
        Blank -> (FBlank at 1, [])
        Adjust -> (FAdjustLines at (-1), [])
        KeepTogether -> (FNoBreak at, [])
        Table -> (FTable identifier 0 [] [[line]] [] False, [identifier])
        Wrapped -> (FWrapped (1000 + identifier) 1 [] [] [line], [identifier])

cases :: [(Int, [Piece])]
cases = [(capacity, pieces) | capacity <- [3 .. 5], count <- [0 .. 3], pieces <- replicateM count [minBound .. maxBound]]

lineIds :: Slotted -> [Int]
lineIds = \case
  SLine identifier -> [identifier]
  SCode first count _ -> [first .. first + count - 1]
  _ -> []

paginateElementsTests :: TestTree
paginateElementsTests = testGroup "Golem ADR 0313"
  [ testCase "P1: every body line and wrapped figure occurs exactly once" $
      mapM_ (\(capacity, pieces) -> do
        let entries = zipWith flow [1 ..] pieces
            slots = concatMap poSlots (paginate 1 capacity (map fst entries))
            context = show (capacity, pieces)
        assertEqual context (sort (concatMap snd entries)) (sort (concatMap (lineIds . snd) slots))
        assertEqual context [1000 + index * 10 | (index, Wrapped) <- zip [1 ..] pieces]
          (sort [identifier | (_, SWrapped identifier) <- slots])) cases,
    testCase "P2: every output item starts inside its effective column" $
      mapM_ (\(capacity, pieces) -> do
        let pages = paginate 1 capacity (map fst (zipWith flow [1 ..] pieces))
        assertBool (show (capacity, pieces))
          (all (\page -> all (\(row, _) -> row >= 0 && row < poLines page) (poSlots page)) pages)) cases
  ]
