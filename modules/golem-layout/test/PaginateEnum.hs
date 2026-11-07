{- | Every small input of 'paginateWithin' (docs/adr/0204): columns of 3
to 8 grid lines, pages of one or two columns, a footnote separator of
one grid line, and flows of the elements of 'elementsFor', tier n
holding the flows of n elements.

The lines are numbered from 0 in the order of the flow, the figures
from 1000. A paragraph with a note has it on its first line; a note
takes one line, and its marker is named after the line.
-}
module PaginateEnum
  ( Element (..),
    Input (..),
    elementsFor,
    inputs,
    enumFlows,
    paginateInput,
    noteOf,
    renderInput,
    renderCase,
  )
where

import Data.List (intercalate)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Paginate
import Golem.Syntax (FileId (..), mkSpan)
import Golem.TestSupport.Enum

-- | One element of a flow.
data Element
  = -- | a paragraph of n lines without notes
    EPara !Int
  | -- | a paragraph of n lines whose first line has a note of one line
    ENotedPara !Int
  | -- | a heading of one line on one grid line
    EHeading
  | -- | a heading of one line whose line has a note of one line
    ENotedHeading
  | -- | a heading at a recto (@page-break = "recto"@)
    ERecto
  | -- | a figure of n grid lines
    EFigure !Int
  | -- | a space of one grid line
    ESpace
  | -- | a page break
    EBreak
  deriving stock (Eq, Show)

-- | The grid lines of a column, the columns of a page and the elements of the flow.
data Input = Input {inLines :: !Int, inColumns :: !Int, inElements :: ![Element]}
  deriving stock (Eq, Show)

-- | The elements of a flow in columns of c grid lines: figures up to one line more than the column.
elementsFor :: Int -> [Element]
elementsFor c =
  map EPara [1 .. 4]
    <> map ENotedPara [1 .. 4]
    <> [EHeading, ENotedHeading, ERecto]
    <> map EFigure [1 .. c + 1]
    <> [ESpace, EBreak]

{- | Every input, tier n holding the flows of n elements, the columns of
fewer grid lines and the pages of fewer columns first.
-}
inputs :: Tiers Input
inputs = foldr1 (\/) [mapT (Input c k) (listsOf (Tiers [elementsFor c])) | c <- [3 .. 8], k <- [1, 2]]

-- | The note of the line i.
noteOf :: Int -> NoteId
noteOf i = NoteId (mkSpan (FileId 0) i (i + 1)) 0

-- | The flow of the elements: lines numbered from 0, figures from 1000.
enumFlows :: [Element] -> [Flow]
enumFlows = go 0 1000
  where
    go :: Int -> Int -> [Element] -> [Flow]
    go _ _ [] = []
    go i j (e : rest) = case e of
      EPara n -> FParagraph (plain i n) : go (i + n) j rest
      ENotedPara n -> FParagraph (noted i : plain (i + 1) (n - 1)) : go (i + n) j rest
      EHeading -> FHeading 2 False 1 (plain i 1) : go (i + 1) j rest
      ENotedHeading -> FHeading 2 False 1 [noted i] : go (i + 1) j rest
      ERecto -> FHeading 1 True 1 (plain i 1) : go (i + 1) j rest
      EFigure n -> FFigure j n [] [] : go i (j + 1) rest
      ESpace -> FSpace 1 : go i j rest
      EBreak -> FBreak BreakPage : go i j rest
    plain base n = [LineBox (base + k) [] [] [] 0 | k <- [0 .. n - 1]]
    noted i = LineBox i [NoteBody (noteOf i) 1] [] [] 0

-- | The columns of the input.
paginateInput :: Input -> [PageOut]
paginateInput (Input c k es) = paginateWithin maxBound 1 (ColumnSet k 0 0 0) c (enumFlows es)

-- | The input as the Haskell expression that lays it out.
renderInput :: Input -> String
renderInput (Input c k es) =
  "paginateWithin maxBound 1 (ColumnSet " <> show k <> " 0 0 0) " <> show c <> " (enumFlows " <> show es <> ")"

{- | A test case for PaginateSpec that fixes what the input lays out
now: page, column and what starts in each column.
-}
renderCase :: String -> Input -> String
renderCase name input =
  intercalate
    "\n"
    [ "testCase " <> show name <> " $ do",
      "  let ps = " <> renderInput input,
      "  [(poNumber p, poColumn p, map snd (poSlots p)) | p <- ps]",
      "    @?= " <> show [(poNumber p, poColumn p, map snd (poSlots p)) | p <- paginateInput input]
    ]
