{- | The mark of a citation in the text, in the default style of numbers
(docs/adr/0266). Every output sets the same pieces: the PDF and the plain
text join their text, the HTML links each number to its entry.
-}
module Golem.Doc.Citation
  ( CitePiece (..),
    citationPieces,
    citationText,
  )
where

import Data.List (sortOn)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR

{- | A piece of a mark: a number and the key it stands for, text, or the
label of a locator and its value (docs/adr/0277), which the PDF does not
break between and the HTML joins with U+00A0.
-}
data CitePiece
  = CiteNumber !Text !Int -- a number and the key it stands for
  | CiteText !Text -- text: brackets, separators, an unnumbered key
  | CiteLocator !Text !Text -- the label of a locator and its value: "pp." "5–7"
  deriving stock (Eq, Show)

{- | The pieces of the mark of a citation, from its items with their
numbers, in the order written:

1. Without a locator, the numbers ascending, three or more consecutive
   ones as @a–b@ (U+2013), the rest separated by @, @: @[1, 3–5, 7]@.
2. With a locator in any item, the items as written, separated by @; @,
   each number followed by @, @ and its locator: @[1, p. 5]@.
3. A page is @p. 5@, @p. xii@, and a range @pp. 5–7@; a range of equal
   ends is @p. 5@.

An item without a number stands as its key, after the numbers in rule 1;
the PDF sets it so, the HTML and the plain text leave the mark out. The
prefix and the suffix, which no output sets yet, are not in the pieces.
-}
citationPieces :: [(CiteItem r, Maybe Int)] -> [CitePiece]
citationPieces items =
  [CiteText "["] <> body <> [CiteText "]"]
  where
    body
      | any (isJust . citLocator . fst) items = joinWith "; " (map located items)
      | otherwise =
          let numbered = sortOn snd [(citKey i, n) | (i, Just n) <- items]
              unnumbered = [[CiteText (citKey i)] | (i, Nothing) <- items]
           in joinWith ", " (map runPieces (runs numbered) <> unnumbered)
    located (i, n) =
      maybe (CiteText (citKey i)) (CiteNumber (citKey i)) n
        : maybe [] (\l -> [CiteText ", ", locatorPiece l]) (citLocator i)
    runPieces = \case
      [(k, n)] -> [CiteNumber k n]
      run@((k, n) : _ : _ : _) | (k', n') <- last run -> [CiteNumber k n, CiteText "\x2013", CiteNumber k' n']
      run -> joinWith ", " [[CiteNumber k n] | (k, n) <- run]
    joinWith sep = \case
      [] -> []
      [x] -> x
      x : rest -> x <> [CiteText sep] <> joinWith sep rest

-- | The runs of consecutive numbers of a list of ascending numbers.
runs :: [(Text, Int)] -> [[(Text, Int)]]
runs = foldr step []
  where
    step x@(_, n) = \case
      (r@((_, m) : _) : rest) | m == n + 1 -> (x : r) : rest
      rs -> [x] : rs

-- | The piece of a locator: the page in the default style, its label and its value (docs/adr/0277).
locatorPiece :: Locator -> CitePiece
locatorPiece (Locator label v) = case (label, v) of
  (LocatorPage, LocRange a b) | a /= b -> CiteLocator "pp." (tshow a <> "\x2013" <> tshow b)
  (LocatorPage, _) -> CiteLocator "p." (valueText v)
  -- the other kinds are not set yet and have no label: Validate stops them before an output
  (_, _) -> CiteText (valueText v)
  where
    valueText = \case
      LocNumber n -> tshow n
      LocRange a _ -> tshow a
      LocText t -> t
    tshow :: Integer -> Text
    tshow = T.pack . show

-- | The text of the pieces joined, as the PDF and the plain text set it.
citationText :: [CitePiece] -> Text
citationText = T.concat . map piece
  where
    piece = \case
      CiteNumber _ n -> T.pack (show n)
      CiteText t -> t
      CiteLocator l v -> l <> " " <> v
