{- | Every small input of 'paginateWithin' (docs/adr/0204): columns of 3
to 8 grid lines, pages of one or two columns, a footnote separator of
one grid line, and flows of the elements of 'elementsFor', tier n
holding the flows of n elements ('fullInputs'). The tests check the
enumeration shortened by docs/adr/0208 ('inputs'), and draw inputs from
the whole one.

The lines are numbered from 0 in the order of the flow, the figures
from 1000, the sections of docs/adr/0260 by their place among the
controls. A paragraph with a note has it on its first line; a note
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
    sectionFlow,
    startOfKind,
    keepElementsFor,
    keepInputs,
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
  | {- | @need-lines n@ of n = c − 1 lines in columns of c grid lines, more
    than 'ENeedLines' (golem-layout ADR 0035)
    -}
    ENeedLinesMore !Int
  | -- | blank lines of n lines (golem-layout ADR 0025)
    EBlank !Int
  | -- | the start of a section, with the number of its first page or without (docs/adr/0260)
    ESection !(Maybe Integer)
  | -- | a paragraph of n lines broken by a keep (docs/adr/0261)
    EKept !Keep !Int
  | -- | a stanza of the verse lines of so many lines each, broken by a keep (docs/adr/0261)
    EStanza !Keep ![Int]
  | -- | the paragraph or stanza before kept with the first part of what follows, of n lines (docs/adr/0261)
    EKeepNext !Int
  | -- | the paragraph after started in the next column or on the next page of the kind (docs/adr/0261)
    EStart !BreakKind
  deriving stock (Eq, Show)

-- | The grid lines of a column, the columns of a page and the elements of the flow.
data Input = Input {inLines :: !Int, inColumns :: !Int, inElements :: ![Element]}
  deriving stock (Eq, Show)

{- | The elements of a flow in columns of c grid lines: figures of up to
c lines, as golem-driver shrinks a figure to fit an empty column
(docs/adr/0206), need-lines of 2 and blank lines of 1 and 2 lines
(golem-layout ADR 0025), and need-lines of c − 1 lines in columns of more
than 2 grid lines (golem-layout ADR 0035).
-}
elementsFor :: Int -> [Element]
elementsFor c =
  map EPara [1 .. 4]
    <> map ENotedPara [1 .. 4]
    <> [EHeading, ENotedHeading, ERecto]
    <> map EFigure [1 .. c]
    <> [ESpace, EBreak]
    <> [ENeedLines]
    <> [ENeedLinesMore (c - 1) | c > 2]
    <> [EBlank 1, EBlank 2]
    <> [ESection Nothing, ESection (Just 1), ESection (Just 2)]

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

{- | The elements of the flows of the keep options (docs/adr/0261) in
columns of c grid lines: paragraphs of 1 to 5 lines of the keeps
(1, 1), (3, 3) and all lines, stanzas of three and four verse lines of a
line and one whose second verse line has two, of the default keep and of
all lines, keep-with-next of 2 and 3 lines, the four starts, paragraphs
of 1 to 4 lines of the default keep, a heading, a figure of c lines, a
space and a break.
-}
keepElementsFor :: Int -> [Element]
keepElementsFor c =
  [EKept kp n | kp <- [Keep 1 1 False, Keep 3 3 False, Keep 2 2 True], n <- [1 .. 5]]
    <> [EStanza kp vs | kp <- [defaultKeep, Keep 2 2 True], vs <- [[1, 1, 1], [1, 1, 1, 1], [1, 2, 1]]]
    <> [EKeepNext 2, EKeepNext 3]
    <> map EStart [BreakColumn, BreakPage, BreakRecto, BreakVerso]
    <> map EPara [1 .. 4]
    <> [EHeading, EFigure c, ESpace, EBreak]

-- | The inputs of the keep options (docs/adr/0261): columns of 3 to 5 grid lines and 'keepElementsFor'.
keepInputs :: Tiers Input
keepInputs = inputsOver [3 .. 5] keepElementsFor

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
enumFlows = placed . go 0 1000 0
  where
    -- a keep-with-next only right after a paragraph or a stanza, a start only right before one (docs/adr/0261)
    placed fs = [f | (prev, f, next) <- zip3 (Nothing : map Just fs) fs (map Just (drop 1 fs) <> [Nothing]), fits prev f next]
    fits prev f next = case f of
      FKeepNext {} -> maybe False isText prev
      FSection (OfParagraph _) _ -> maybe False isText next
      _ -> True
    isText = \case
      FParagraph {} -> True
      FStanza {} -> True
      _ -> False
    go :: Int -> Int -> Int -> [Element] -> [Flow]
    go _ _ _ [] = []
    go i j m (e : rest) = case e of
      EPara n -> FParagraph defaultKeep (plain i n) : go (i + n) j m rest
      ENotedPara n -> FParagraph defaultKeep (noted i : plain (i + 1) (n - 1)) : go (i + n) j m rest
      EHeading -> FHeading 2 False 1 (plain i 1) : go (i + 1) j m rest
      ENotedHeading -> FHeading 2 False 1 [noted i] : go (i + 1) j m rest
      ERecto -> FHeading 1 True 1 (plain i 1) : go (i + 1) j m rest
      EFigure n -> FFigure j n [] [] : go i (j + 1) m rest
      ESpace -> FSpace 1 : go i j m rest
      EBreak -> FBreak BreakPage : go i j m rest
      ENeedLines -> FNeedLines (controlSpan m) 2 : go i j (m + 1) rest
      ENeedLinesMore n -> FNeedLines (controlSpan m) n : go i j (m + 1) rest
      EBlank n -> FBlank (controlSpan m) n : go i j (m + 1) rest
      ESection start -> sectionFlow m start : go i j (m + 1) rest
      EKept kp n -> FParagraph kp (plain i n) : go (i + n) j m rest
      EStanza kp vs -> FStanza kp (verses i vs) : go (i + sum vs) j m rest
      -- the span of the control stands for the span of the paragraph before
      EKeepNext n -> FKeepNext (controlSpan m) n : go i j (m + 1) rest
      EStart k -> FSection (OfParagraph (controlSpan m)) k : go i j (m + 1) rest
    plain base n = [LineBox (base + k) [] [] [] 0 | k <- [0 .. n - 1]]
    verses base vs = [plain b v | (b, v) <- zip (scanl (+) base vs) vs]
    noted i = LineBox i [NoteBody (noteOf i) 1] [] [] 0

{- | The start of a section of a number of a page (docs/adr/0260): to an
odd page for an odd start, an even page for an even one, the next page
without one.
-}
sectionFlow :: Int -> Maybe Integer -> Flow
sectionFlow i start = FSection (OfSection i) (maybe BreakPage (\s -> if odd s then BreakRecto else BreakVerso) start)

{- | The start of a section a start of the enumeration stands for: 1 for
an odd page, 2 for an even one, none for the next page.
-}
startOfKind :: BreakKind -> Maybe Integer
startOfKind = \case
  BreakRecto -> Just 1
  BreakVerso -> Just 2
  _ -> Nothing

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
