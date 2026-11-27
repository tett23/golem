{-# LANGUAGE GHC2021 #-}

-- Root ADR 0352 I4: a positive cutoff need not reduce the placed count.
module Main where

import Control.Monad (forM_, unless)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical
import Golem.Length (Sp (..))

main :: IO ()
main = do
  let cfg = PhysicalSettings 10 10 (Sp 30) (Sp 50) 4 (ColumnSet 1 0 0 0) Map.empty Map.empty Map.empty Map.empty Map.empty Nothing Set.empty noAvoid
      rows = [LineBox i [] [] [] 0 | i <- [1 .. 5]]
  forM_ [Nothing, Just 2, Just 1] $ \cutoff ->
    case trialParagraphPartLimit cfg Nothing cutoff (Keep 2 4 False) True (startPhysicalCursor cfg) rows of
      Right (PhysicalPlaced count _ relaxed) ->
        unless
          (count == 3 && kFirst relaxed == 2 && kLast relaxed == 4)
          (error "expected the last-part retry counterexample to keep placing three rows")
      _ -> error "expected three placed rows"
  putStrLn "root ADR 0352 I4: last-part retry counterexample has three rows for cutoffs None, 2, and 1"
