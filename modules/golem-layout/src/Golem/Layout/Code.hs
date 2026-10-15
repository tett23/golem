{- | Code blocks (golem-driver ADR 0017): the lines of code set as they
are written. Spaces are kept, a tab goes to the next stop every two
spaces from the text start, nothing is justified, hyphenated or spaced
by the aki set, and a line longer than the measure wraps at a cluster
boundary. A block takes the fewest grid lines that hold its rows and its
padding, with the rows centred in them.
-}
module Golem.Layout.Code
  ( CodeAtom (..),
    codeAtoms,
    CodePiece (..),
    CodeRow (..),
    layoutCodeLine,
    codeContinuation,
    CodeGeometry (..),
    codeGeometry,
    codeExtent,
    codeSpan,
    codeRowsTop,
  )
where

import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Layout.CharClass (CharClass (..), charClass)
import Golem.Layout.Japanese (isVariationSelector)

type Sp = Integer

-- | A part of a line of code: a space, a tab, or a cluster of glyphs with its advance.
data CodeAtom
  = ASpace
  | ATab
  | -- | the text of the cluster, its advance and whether it is Latin text
    AGlyph !Text !Sp !Bool
  deriving stock (Eq, Show)

{- | The atoms of a line of code: spaces and tabs, and the clusters of each
run of Latin or other text as @shape@ gives them (the run's Latin flag and
its text to the text and the advance of each cluster). A variation
selector stays with the character before it (golem-pdf ADR 0006).
-}
codeAtoms :: (Bool -> Text -> [(Text, Sp)]) -> Text -> [CodeAtom]
codeAtoms shape = concatMap atoms . T.groupBy sameRun
  where
    latin c = charClass c == Western
    blank c = c == ' ' || c == '\t'
    sameRun a b
      | blank a || blank b = False
      | otherwise = isVariationSelector b || latin a == latin b
    atoms r = case T.unpack r of
      " " -> [ASpace]
      "\t" -> [ATab]
      (c : _) -> [AGlyph t w (latin c) | (t, w) <- shape (latin c) r]
      [] -> []

-- | Glyphs placed on a row, from the text start: the offset, the text, its advance and whether it is Latin.
data CodePiece = CodePiece
  { cpOffset :: !Sp,
    cpText :: !Text,
    cpWidth :: !Sp,
    cpLatin :: !Bool
  }
  deriving stock (Eq, Show)

-- | One row of a code block: a line, or a part of a wrapped line.
newtype CodeRow = CodeRow {crPieces :: [CodePiece]}
  deriving stock (Eq, Show)

{- | Where a wrapped line continues, from the text start: the width of the
spaces and tabs at the start of the line and two spaces, or two spaces when
eight spaces would not be left after it.
-}
codeContinuation :: Sp -> Sp -> [CodeAtom] -> Sp
codeContinuation s avail atoms =
  let lead = foldl' (advance s) 0 (takeWhile (not . isGlyph) atoms)
   in if avail - (lead + 2 * s) >= 8 * s then lead + 2 * s else 2 * s

isGlyph :: CodeAtom -> Bool
isGlyph = \case
  AGlyph {} -> True
  _ -> False

-- | The text position after an atom; a tab goes to the next stop after the position.
advance :: Sp -> Sp -> CodeAtom -> Sp
advance s x = \case
  ASpace -> x + s
  ATab -> let unit = 2 * s in if unit <= 0 then x else (x `div` unit + 1) * unit
  AGlyph _ w _ -> x + w

{- | The rows of a line of code with the space advance @s@ and @avail@ for
the text: a glyph that would end past @avail@ starts a new row at
'codeContinuation', unless it is the first glyph of its row. Spaces and
tabs never start a row.
-}
layoutCodeLine :: Sp -> Sp -> [CodeAtom] -> [CodeRow]
layoutCodeLine s avail atoms = go 0 False [] [] atoms
  where
    cont = codeContinuation s avail atoms
    close acc = CodeRow (reverse acc)
    go _ _ acc rows [] = reverse (close acc : rows)
    go x hasGlyph acc rows (a : rest) = case a of
      AGlyph t w l
        | x + w > avail && hasGlyph -> go cont False [] (close acc : rows) (a : rest)
        | otherwise -> go (x + w) True (place x t w l acc) rows rest
      _ -> go (advance s x a) hasGlyph acc rows rest
    -- a glyph right after one of the same side joins its piece
    place x t w l = \case
      CodePiece o pt pw pl : acc
        | pl == l && o + pw == x -> CodePiece o (pt <> t) (pw + w) pl : acc
      acc -> CodePiece x t w l : acc

{- | The sizes a code block is set with: the size and pitch of the grid,
the size of the code, the pitch of its rows and the padding.
-}
data CodeGeometry = CodeGeometry
  { cgGridSize :: !Sp,
    cgGridPitch :: !Sp,
    cgSize :: !Sp,
    cgPitch :: !Sp,
    cgPadding :: !Sp
  }
  deriving stock (Eq, Show)

{- | The geometry of code of size @s@ and padding @pad@ on a grid of size
@fs@ and pitch @p@: the rows keep the body's ratio of pitch to size, as
captions do (golem-driver ADR 0010).
-}
codeGeometry :: Sp -> Sp -> Sp -> Sp -> CodeGeometry
codeGeometry fs p s = CodeGeometry fs p s (if fs <= 0 then p else round (p * s % fs))

-- | The rows and the padding above and below them, from the top of the first row's padding.
codeExtent :: CodeGeometry -> Int -> Sp
codeExtent g k = toInteger (max 1 k - 1) * cgPitch g + cgSize g + 2 * cgPadding g

{- | The grid lines @k@ rows take: the fewest whose area (the line pitch
each, from the space above the first line to the space below the last)
holds the rows and the padding.
-}
codeSpan :: CodeGeometry -> Int -> Int
codeSpan g k =
  let p = max 1 (cgGridPitch g)
   in fromInteger (max 1 ((codeExtent g k + p - 1) `div` p))

{- | From the top of the area of @k@ rows to the top of the first row: the
rows are centred in the area.
-}
codeRowsTop :: CodeGeometry -> Int -> Sp
codeRowsTop g k = (toInteger (codeSpan g k) * cgGridPitch g - codeExtent g k) `div` 2 + cgPadding g
