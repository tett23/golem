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
import Golem.Syntax (FileId (..), mkSpan)

lines' :: Int -> Int -> [LineBox]
lines' base n = [LineBox (base + i) [] [] [] 0 | i <- [0 .. n - 1]]

-- A paragraph, a figure, a heading of one line over one grid line, a
-- need-lines, a no-break, a no-break of so many lines and a keep-with-next.
data Element = Para Int Int | Fig Int Int | Head Int | NeedLines Int | NoBreak | NoBreakLines Int | KeepNext Int

flowOf :: Element -> Flow
flowOf = \case
  Para base n -> FParagraph defaultKeep (lines' base n)
  Fig ident n -> FFigure ident n [] []
  Head base -> FHeading 2 False 1 (lines' base 1)
  NeedLines n -> FNeedLines control n
  NoBreak -> FNoBreak control
  NoBreakLines n -> FNoBreakLines control n
  KeepNext n -> FKeepNext control n
  where
    control = mkSpan (FileId 1) 0 1

showElement :: Element -> String
showElement = \case
  Para base n -> "P" <> show base <> ":" <> show n
  Fig ident n -> "F" <> show ident <> ":" <> show n
  Head base -> "H" <> show base
  NeedLines n -> "N" <> show n
  NoBreak -> "B"
  NoBreakLines n -> "B" <> show n
  KeepNext n -> "K" <> show n

-- The inputs in the order Boundary.lean lists them.
inputs :: [(Int, [Element])]
inputs =
  [(c, e) | c <- [1 .. 3], e <- [[], [Para 0 1]]]
    <> [(c, paragraphs s) | c <- [1 .. 3], s <- [[a] | a <- [1 .. 5]] <> [[a, b] | a <- [1 .. 4], b <- [1 .. 4]]]
    <> [(3, [Fig 1 3]), (3, [Para 0 1, Fig 1 3]), (3, [Fig 1 4]), (3, [Para 0 1, Fig 1 4, Para 10 1])]
    <> [(c, figureInput s) | c <- [3, 4], s <- figureShapes c]
    <> [(c, controlInput s n) | c <- [2 .. 4], s <- controlShapes, n <- [1 .. 3]]
  where
    paragraphs = zipWith (\k n -> Para (10 * k) n) [0 ..]
    figureShapes c =
      [ shape
      | count <- [1 .. 4],
        shape <- replicateM count (Left <$> [1 .. 3] <|> Right <$> [1 .. c]),
        length [() | Right _ <- shape] `elem` [1 .. 3]
      ]
    figureInput = zipWith (\k -> either (Para (10 * k)) (Fig (100 + k))) [0 ..]
    -- one to three elements, each a paragraph of one to five lines, a
    -- heading, a need-lines of two or three lines, a no-break, a no-break
    -- of three lines or a keep-with-next of one or two lines, before a
    -- last paragraph of one to three lines
    controlShapes = [shape | count <- [1 .. 3], shape <- replicateM count controlChoices]
    controlChoices = map Left [1 .. 5] <> map Right [Nothing, Just (Left 2), Just (Left 3), Just (Right Nothing), Just (Left 0), Just (Right (Just 1)), Just (Right (Just 2))]
    controlInput shape n = zipWith controlElement [0 ..] shape <> [Para (10 * length shape) n]
    controlElement k = \case
      Left n -> Para (10 * k) n
      Right Nothing -> Head (10 * k)
      Right (Just (Left 0)) -> NoBreakLines 3
      Right (Just (Left n)) -> NeedLines n
      Right (Just (Right Nothing)) -> NoBreak
      Right (Just (Right (Just n))) -> KeepNext n

slot :: (Int, Slotted) -> String
slot (g, s) = show g <> ":" <> case s of
  SLine i -> "L" <> show i
  SFigure i -> "F" <> show i
  SHeading i n -> "H" <> show i <> ":" <> show n
  other -> show other

unmet :: Unmet -> String
unmet = \case
  UnmetNeedLines _ n -> "!need" <> show n
  UnmetNoBreak _ -> "!nobreak"
  UnmetKeepNext _ -> "!keepnext"
  DroppedBlank _ -> "!dropped"
  TallHeading i n f -> "!tall" <> show i <> ":" <> show n <> ":" <> show f
  SplitKept i -> "!split" <> show i
  ShortPart FirstPart i w g -> "!first" <> show i <> ":" <> show w <> ":" <> show g
  ShortPart LastPart i w g -> "!last" <> show i <> ":" <> show w <> ":" <> show g
  other -> "!" <> show other

page :: PageOut -> String
page p = "  " <> unwords ([show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-"] <> map slot (poSlots p) <> map unmet (poUnmet p))

main :: IO ()
main = mapM_ run inputs
  where
    run (c, es) = do
      putStrLn (show c <> " [" <> intercalate " " (map showElement es) <> "]")
      mapM_ (putStrLn . page) (paginate 1 c (map flowOf es))
