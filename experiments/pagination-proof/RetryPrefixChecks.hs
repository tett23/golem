{-# LANGUAGE GHC2021 #-}

-- Root ADR 0352 I4: count and retry-bound contracts of the native trial.
module Main where

import Control.Monad (forM, forM_, unless)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical
import Golem.Length (Sp (..))

settings :: Int -> PhysicalSettings
settings capacity = PhysicalSettings 10 10 (Sp (fromIntegral (capacity * 10))) (Sp (fromIntegral (capacity * 10 + 20))) 4 (ColumnSet 1 0 0 0) Map.empty Map.empty Map.empty Map.empty Map.empty Nothing Set.empty noAvoid

main :: IO ()
main = do
  let inputs = [(capacity, rowCount, cutoff, keep, start, prefilled) | capacity <- [1, 2, 3, 6], rowCount <- [0 .. 6], cutoff <- [Nothing, Just 0, Just 1, Just 3], keep <- [Keep 1 1 False, Keep 2 2 False, Keep 1 1 True], start <- [False, True], prefilled <- [False, True]]
  observed <- forM inputs $ \(capacity, rowCount, cutoff, keep, start, prefilled) -> do
    let cfg = settings capacity
        rows = [LineBox i [] [] [] 0 | i <- [1 .. rowCount]]
        initial = startPhysicalCursor cfg
    cursor <- if prefilled then either (error . show) pure (stepPhysicalCursor cfg initial [FParagraph defaultKeep [LineBox 0 [] [] [] 0]]) else pure initial
    case trialParagraphPartLimit cfg Nothing cutoff keep start cursor rows of
      Left refusal -> error (show refusal)
      Right (PhysicalMoved _ _) -> pure (False, False)
      Right (PhysicalPlaced count _ relaxed) -> do
        unless (0 <= count && count <= rowCount) (error "root ADR 0352 I4: native trial count outside source rows")
        forM_ [0, 1, 3] $ \lastWanted -> do
          let front = count - max lastWanted (max 1 (kLast relaxed))
              minimumFront = if start then max (if lastWanted > 0 then 2 else 1) (kFirst keep) else 1
              oldRank = fromMaybe (rowCount + 1) cutoff
              admissible = maybe True (> 0) cutoff
          unless (not (admissible && rowCount <= count && minimumFront <= front) || front < oldRank) (error "root ADR 0352 I4: native front retry does not decrease cutoff")
        let zeroCounter = capacity == 6 && not prefilled && start && cutoff == Just 0 && kFirst keep == 2 && kLast keep == 2 && not (kAll relaxed) && count == 4 && rowCount == 4 && 2 <= count - max 0 (max 1 (kLast relaxed))
        pure (True, zeroCounter)
  unless (any snd observed) (error "root ADR 0352 I4: missing external zero-cutoff counterexample")
  putStrLn ("root ADR 0352 I4: " <> show (length observed) <> " native trials; " <> show (length (filter fst observed)) <> " placed and " <> show (length (filter (not . fst) observed)) <> " moved; positive-cutoff front ranks pass; external zero-cutoff counterexample retained")
