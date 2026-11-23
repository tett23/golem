{-# LANGUAGE LambdaCase #-}

-- Root ADR 0352: prints the pages golem-layout's paginate gives for the
-- inputs of boundaryTableTests (modules/golem-layout/test/PaginateSpec.hs),
-- in the format Boundary.lean prints for Whole.lean's paginate.
-- check.sh compares the two outputs with diff.
module Main (main) where

import Control.Applicative ((<|>))
import Control.Monad (replicateM)
import Data.List (intercalate)
import Golem.Layout.Paginate

lines' :: Int -> Int -> [LineBox]
lines' base n = [LineBox (base + i) [] [] [] 0 | i <- [0 .. n - 1]]

data Element = Para Int Int | Fig Int Int

flowOf :: Element -> Flow
flowOf = \case
  Para base n -> FParagraph defaultKeep (lines' base n)
  Fig ident n -> FFigure ident n [] []

showElement :: Element -> String
showElement = \case
  Para base n -> "P" <> show base <> ":" <> show n
  Fig ident n -> "F" <> show ident <> ":" <> show n

-- The inputs in the order Boundary.lean lists them.
inputs :: [(Int, [Element])]
inputs =
  [(c, e) | c <- [1 .. 3], e <- [[], [Para 0 1]]]
    <> [(c, paragraphs s) | c <- [1 .. 3], s <- [[a] | a <- [1 .. 5]] <> [[a, b] | a <- [1 .. 4], b <- [1 .. 4]]]
    <> [(3, [Fig 1 3]), (3, [Para 0 1, Fig 1 3]), (3, [Fig 1 4]), (3, [Para 0 1, Fig 1 4, Para 10 1])]
    <> [(c, figureInput s) | c <- [3, 4], s <- figureShapes c]
  where
    paragraphs = zipWith (\k n -> Para (10 * k) n) [0 ..]
    figureShapes c =
      [ shape
      | count <- [1 .. 4],
        shape <- replicateM count (Left <$> [1 .. 3] <|> Right <$> [1 .. c]),
        length [() | Right _ <- shape] `elem` [1 .. 3]
      ]
    figureInput = zipWith (\k -> either (Para (10 * k)) (Fig (100 + k))) [0 ..]

slot :: (Int, Slotted) -> String
slot (g, s) = show g <> ":" <> case s of
  SLine i -> "L" <> show i
  SFigure i -> "F" <> show i
  other -> show other

page :: PageOut -> String
page p = "  " <> unwords ([show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-"] <> map slot (poSlots p))

main :: IO ()
main = mapM_ run inputs
  where
    run (c, es) = do
      putStrLn (show c <> " [" <> intercalate " " (map showElement es) <> "]")
      mapM_ (putStrLn . page) (paginate 1 c (map flowOf es))
