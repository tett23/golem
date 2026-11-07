{- | Every small input of 'paginateWithin' (docs/adr/0204): columns of 3
to 8 grid lines, pages of one or two columns, a footnote separator of
one grid line, and flows of the elements of 'elementsFor', tier n
holding the flows of n elements ('fullInputs'). The tests check the
enumeration shortened by docs/adr/0208 ('inputs'), and draw inputs from
the whole one.

The lines are numbered from 0 in the order of the flow, the figures
from 1000. A paragraph with a note has it on its first line; a note
takes one line, and its marker is named after the line. A need-lines and
blank lines have the span of their place among the controls of the flow
(golem-layout ADR 0025).
-}
module PaginateEnum
  ( Element (..),
    Input (..),
    elementsFor,
    shortElementsFor,
    inputsOver,
    fullInputs,
    inputs,
    enumFlows,
    paginateInput,
    noteOf,
    controlSpan,
    renderInput,
    renderCase,
  )
where

import Data.List (intercalate)
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Paginate
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)
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
  | -- | @need-lines 2@ (golem-layout ADR 0025)
    ENeedLines
  | -- | blank lines of n lines (golem-layout ADR 0025)
    EBlank !Int
  deriving stock (Eq, Show)

-- | The grid lines of a column, the columns of a page and the elements of the flow.
data Input = Input {inLines :: !Int, inColumns :: !Int, inElements :: ![Element]}
  deriving stock (Eq, Show)

{- | The elements of a flow in columns of c grid lines: figures of up to
c lines, as golem-driver shrinks a figure to fit an empty column
(docs/adr/0206), and need-lines of 2 and blank lines of 1 and 2 lines
(golem-layout ADR 0025).
-}
elementsFor :: Int -> [Element]
elementsFor c =
  map EPara [1 .. 4]
    <> map ENotedPara [1 .. 4]
    <> [EHeading, ENotedHeading, ERecto]
    <> map EFigure [1 .. c]
    <> [ESpace, EBreak]
    <> [ENeedLines, EBlank 1, EBlank 2]

{- | The elements of the flows of the shortened enumeration (docs/adr/0208,
its section 3): those of 'elementsFor', with the figures of 1, c − 1 and
c lines only, the values of the table of the boundary inputs of
docs/adr/0204 (its c + 1 is taller than the column, which 'elementsFor'
no longer makes, docs/adr/0206).
-}
shortElementsFor :: Int -> [Element]
shortElementsFor c = filter boundary (elementsFor c)
  where
    boundary = \case
      EFigure n -> n `elem` [1, c - 1, c]
      _ -> True

{- | Every input of the columns of the grid lines given, of one and two
columns, and of the elements given for each column, tier n holding the
flows of n elements, the columns of fewer grid lines and the pages of
fewer columns first.

The tiers of an enumeration that is a value of its own, as 'inputs' and
'fullInputs' are, stay as long as the program once they are made; the
tests that check millions of inputs call this function where they check
them instead, so that only the inputs being checked are held.
-}
inputsOver :: [Int] -> (Int -> [Element]) -> Tiers Input
inputsOver cs els = foldr1 (\/) [mapT (Input c k) (listsOf (Tiers [els c])) | c <- cs, k <- [1, 2]]

-- | The inputs of docs/adr/0204: columns of 3 to 8 grid lines and every element of 'elementsFor'.
fullInputs :: Tiers Input
fullInputs = inputsOver [3 .. 8] elementsFor

-- | The inputs of the shortened enumeration (docs/adr/0208): columns of 3 to 5 grid lines and 'shortElementsFor'.
inputs :: Tiers Input
inputs = inputsOver [3 .. 5] shortElementsFor

-- | The note of the line i.
noteOf :: Int -> NoteId
noteOf i = NoteId (mkSpan (FileId 0) i (i + 1)) 0

-- | The span of the control m of a flow, from 0.
controlSpan :: Int -> SrcSpan
controlSpan m = mkSpan (FileId 1) m (m + 1)

-- | The flow of the elements: lines numbered from 0, figures from 1000, controls from 0.
enumFlows :: [Element] -> [Flow]
enumFlows = go 0 1000 0
  where
    go :: Int -> Int -> Int -> [Element] -> [Flow]
    go _ _ _ [] = []
    go i j m (e : rest) = case e of
      EPara n -> FParagraph (plain i n) : go (i + n) j m rest
      ENotedPara n -> FParagraph (noted i : plain (i + 1) (n - 1)) : go (i + n) j m rest
      EHeading -> FHeading 2 False 1 (plain i 1) : go (i + 1) j m rest
      ENotedHeading -> FHeading 2 False 1 [noted i] : go (i + 1) j m rest
      ERecto -> FHeading 1 True 1 (plain i 1) : go (i + 1) j m rest
      EFigure n -> FFigure j n [] [] : go i (j + 1) m rest
      ESpace -> FSpace 1 : go i j m rest
      EBreak -> FBreak BreakPage : go i j m rest
      ENeedLines -> FNeedLines (controlSpan m) 2 : go i j (m + 1) rest
      EBlank n -> FBlank (controlSpan m) n : go i j (m + 1) rest
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
