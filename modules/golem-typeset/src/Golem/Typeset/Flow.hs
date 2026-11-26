{-# LANGUAGE MultiWayIf #-}

-- | The flow of the PDF: composition, line breaking and pagination (golem-driver ADR 0002).
module Golem.Typeset.Flow
  ( SetLine (..),
    loadScreenFigures,
    CodeInfo (..),
    CodeCaption (..),
    PlacedSidenote (..),
    PlacedFrame (..),
    PartLine (..),
    PlacedFigure (..),
    TableGeometry (..),
    PdfLayout (..),
    DestAnchor (..),
    styleLayoutDiagnostics,
    pageColumnSet,
    columnSetRects,
    checkedGeometry,
    sidenoteIndentDiagnostics,
    kentenGlyphDiagnostics,
    dashInkNotices,
    punctuationInkNotices,
    flowLines,
    TableRefusal (..),
    forceTable,
    composedTables,
    layoutPdf,
    layoutPdfWith,
    layoutPdfUnnumbered,
    bookNoteSites,
    gridLine,
    runningHeadLines,
    numberedTitle,
    bookNumberedTitle,
    pagesOf,
    bookSections,
    layoutLabels,
    pageMasters,
    pageMasterNames,
    pageStarts,
    runningHeads,
    runningHeadNotices,
    plainWidth,
    lookWidth,
    runsOf,
    isLatin,
    masterLook,
    drawsFolio,
    hiddenFolios,
    TocGeometry (..),
    TocPage (..),
    tocPage,
    layoutPages,
    IndexLine (..),
    indexLines,
    indexLineInlines,
    indexRangeDiagnostics,
    bibliographyLines,
    sidenoteMetrics,
    labelSpans,
    noteNumberDiagnostics,
    Assumed (..),
    composeEnv,
    paraLook,
    fixpoint,
    fixpointWith,
    rubyStyleOf,
    RuledInfo (..),
    BoxInfo (..),
    fitFigure,
    figureRect,
    figureRectAt,
    imageRect,
    turnedFrame,
    pdfXPeople,
    loadIntent,
    -- the structure tree of the PDF (docs/adr ADR 0183)
    FlowEnv (..),
    Unit (..),
    UnitKind (..),
    Frame (..),
    FrameKind (..),
    unitEnv,
    noteEnv,
    sidenoteEnv,
    sidenotePrefix,
    captionEnv,
    tableEnv,
    withNoteMark,
    noteMarkCount,
    unitSite,
    markerSite,
    cellSite,
    captionSite,
    codeRowSite,
    codeFileSite,
    figureSite,
    noteSite,
    noteParagraphSite,
    sidenoteSite,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (evaluate)
import Control.Monad (join, mfilter)
import Data.Bifunctor (bimap, first, second)
import Data.ByteString qualified as BS
import Data.Char (isSpace)
import Data.Containers.ListUtils (nubOrdOn)
import Data.Either (fromRight, lefts)
import Data.Foldable (toList)
import Data.Int (Int64)
import Data.List (groupBy, intercalate, mapAccumL, mapAccumR, nub, sortOn, unsnoc, zip4)
import Data.List.NonEmpty (nonEmpty)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Ord (Down (..))
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Assemble
import Golem.Assemble.ListMarkers
import Golem.Assemble.Numbering (titleSeparator)
import Golem.Bibliography (EntryPart (..))
import Golem.Doc.FigureWidth (figureWidthSp, parseFigureWidth)
import Golem.Doc.IR
import Golem.Doc.Url (checkUrl)
import Golem.Doc.Validate (inlineSpan)
import Golem.Geometry (Path (..), Segment (..), SubPath (..), rectPath)
import Golem.Geometry.Polygon (flattenPath)
import Golem.Html (codeTokens)
import Golem.Layout.Aki (AkiSet, resolveAkiSet)
import Golem.Layout.Align qualified as A
import Golem.Layout.BoxModel (BoxOverflow (..), LineSlot (..), Writing (..), flowInBox, textBox)
import Golem.Layout.Code
import Golem.Layout.FreeGeometry (boxExtras, faceOffset, intersects, rowExtent)
import Golem.Layout.Hyphenation.Languages (exceptionPatterns)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass hiding (Sp)
import Golem.Layout.Look hiding (Kerning (..))
import Golem.Layout.Look qualified as L
import Golem.Layout.PageLabel
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical (PhysicalFailure (..), PhysicalPart (..), PhysicalSettings (..), PhysicalWrap (..), beginPhysicalWrapAfter, endPhysicalWrap, finishPhysicalCursor, finishPhysicalUnit, fitsPhysicalFollowing, keepPhysicalNext, movePhysicalCursor, paginatePhysical, physicalCursorIsEmpty, physicalCursorPosition, physicalFollowingRows, physicalKeepAhead, physicalParagraphOrigin, recordPhysicalUnmet, retainPhysicalPart, startPhysicalCursor, stepPhysicalCursor, stepPhysicalPrefix, trialParagraphPart, trialParagraphPartLimit)
import Golem.Layout.Ruby (RubyStyle (..))
import Golem.Layout.Ruby qualified as R
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Layout.Sidenotes (SidenoteError (..), placeSidenotes)
import Golem.Layout.Table (SetCell (..), SetTable (..), TableError (..), layoutTable)
import Golem.Layout.Wrap (Exclusion (..), exclusion)
import Golem.LayoutSpec (HiddenFolioGeometry (..), MasterGeometry (..), PageGeometry (..), Rect (..), Side (..), baselineRatio, gutterSide, gutterSideFor, pageGeometry, pgBindingRight, sidenoteAreaFor, typeAreaFor)
import Golem.Length qualified as L
import Golem.Numerals (circled)
import Golem.Numerals.Format (renderMarkFormat)
import Golem.Numerals.Notation (writeNumber)
import Golem.Pdf qualified as P
import Golem.Project
import Golem.Project.Files (Files (..))
import Golem.Project.Paths (PathError (..), normalizeRelative, pathErrorMessage)
import Golem.Project.Position (Position (..))
import Golem.Project.Style
import Golem.Svg qualified as S
import Golem.Syntax
import Golem.Typeset.Box (BoxPaint (..), boxLineRange, boxLinesAround, groupBoxes)
import Golem.Typeset.FigureColor (RasterAnalysis (..), analyzeRaster, forceImportedPage, guardColorConversion, safeAnalyzeRaster, safeRecolorRasterBytes)
import Golem.Typeset.Fonts
import Golem.Typeset.Overhang (lineOverhang, reachesBackground)
import Golem.Typeset.Pages (sourceAt)
import Golem.Typeset.PdfColor (recolorImportedPage)
import Golem.Typeset.Svg (drawingImportedPage, figureColor, markerMessage, markerSegmentsMessage, recolorFigure, svgDrawing, unsupportedMessage)
import System.FilePath (takeBaseName)

-- | One line of the flow, with what is needed to draw it.
data SetLine = SetLine
  { slLine :: !Line,
    slSize :: !Sp,
    -- | how far the line starts from the line start of the column (golem-driver ADR 0005)
    slIndent :: !Sp,
    -- | the footnotes marked in the line, by their keys (golem-driver ADR 0018)
    slNotes :: ![(NoteId, [Line])],
    -- | the sidenotes marked in the line, in order (golem-driver ADR 0006)
    slSidenotes :: ![(SrcSpan, [PartLine])],
    {- | a line aligned towards the spine (True) or away from it (False),
    shifted when its page is known (docs/adr/0189)
    -} slSpine :: !(Maybe Bool)
  }
  deriving stock (Show)

{- | What a code block needs to be drawn (golem-driver ADR 0017): its
geometry, where its background starts from the line start of the column,
and the colour of its background. Its first row and the number of its
rows, its caption, the text of a part that continues, the bands of its
rows and its border (golem-driver ADR 0023).
-}
data CodeInfo = CodeInfo
  { ciGeometry :: !CodeGeometry,
    ciStart :: !Sp,
    ciBackground :: !(Maybe P.Swatch),
    -- | the id of the first row
    ciFirst :: !Int,
    ciRows :: !Int,
    -- | the lines of the caption, their size and pitch, and the grid lines they take
    ciCaption :: ![PartLine],
    ciCaptionSize :: !Sp,
    ciCaptionPitch :: !Sp,
    ciCaptionSpan :: !Int,
    -- | the row at the end of a part before the last, with [code] continued
    ciContinued :: !(Maybe Line),
    -- | the bands: the first row from the first row of the block, how many rows and the colour
    ciBands :: ![(Int, Int, P.Swatch)],
    -- | the colour and the width of the border
    ciBorder :: !(Maybe (P.Swatch, Sp)),
    -- | the line style, the sides and the radius of the corners of the border (docs/adr/0271)
    ciBorderStyle :: !RuleStyle,
    ciBorderSides :: ![BoxSide],
    ciRadius :: !Sp,
    -- | where the rows start from the line start of the column, and the size of the code
    ciIndent :: !Sp,
    ciSize :: !Sp
  }
  deriving stock (Show)

-- | The caption of a code block as set (golem-driver ADR 0023): its lines, size, pitch, grid lines and index marks.
data CodeCaption = CodeCaption
  { ccLines :: [PartLine],
    ccSize :: Sp,
    ccPitch :: Sp,
    ccSpan :: Int,
    ccMarks :: [SrcSpan]
  }

{- | A line of a caption or of a sidenote (docs/adr/0367): its row from
the first line of the part, the rows of space-between included; how far
it starts from the line start of the part, by the indents of its
paragraph style; and the line.
-}
data PartLine = PartLine
  { ptRow :: !Int,
    ptIndent :: !Sp,
    ptLine :: !Line
  }
  deriving stock (Eq, Show)

-- | The rows the lines of a part take: one after the row of its last line, none without a line.
partRows :: [PartLine] -> Int
partRows ls = case reverse ls of
  l : _ -> ptRow l + 1
  [] -> 0

{- | The lines of the paragraphs of a caption or a sidenote in the
paragraph style of the name, over the inner width of the part, set as the
paragraphs of the body are (docs/adr/0367): every line less the end
indent, the first line of a paragraph less the indent and the first-line
indent, the others less the indent. A style that keeps its lines sets
each line between line breaks as a paragraph of its own, with no
space-between inside; otherwise a line break is a forced break. The
paragraphs are space-between rows apart; an empty one has no line. The
breaking takes the index of the part, the width of each of its lines and
its inlines.
-}
partLines :: Style -> PageGeometry -> Text -> Sp -> (Int -> (Int -> Sp) -> [Inline] -> [Line]) -> [[Inline]] -> [PartLine]
partLines st geom name inner breakPart paras =
  let (_, Indent s f e _) = paraLook st geom (Just name)
      d = paraStyle st (Just name)
      keeps = (d >>= psLineBreaks) == Just KeepLines
      between = maybe 0 (max 0) (d >>= psSpaceBetween)
      startOf k = if k == (0 :: Int) then s + f else s
      parts = [if keeps then splitAtLineBreaks p else [p] | p <- paras, not (null p)]
      numbered = snd (mapAccumL (\j ps -> (j + length ps, zip [j ..] ps)) 0 parts)
      linesOf (j, part) = zipWith (\k l -> (startOf k, l)) [0 ..] (breakPart j (\k -> inner - startOf k - e) part)
      place _ [] = []
      place row (ls : rest) = zipWith (\r (i, l) -> PartLine r i l) [row ..] ls <> place (row + length ls + between) rest
   in place 0 (map (concatMap linesOf) numbered)

-- | A sidenote placed in the sidenote column (golem-driver ADR 0006).
data PlacedSidenote = PlacedSidenote
  { psSpan :: !SrcSpan,
    -- | from the top of the column
    psTop :: !Sp,
    psLines :: ![PartLine]
  }
  deriving stock (Show)

{- | A text frame as placed on a page (root ADR 0438): its name, where it
was asked for (the @frame, or the frame of style.toml a master page puts),
whether its lines are vertical, whether a master page puts it, and the
rectangle on the page of each of its lines with the line set there.
-}
data PlacedFrame = PlacedFrame
  { pfrName :: !Text,
    pfrSpan :: !SrcSpan,
    pfrVertical :: !Bool,
    pfrMaster :: !Bool,
    pfrLines :: ![(Rect, SetLine)]
  }
  deriving stock (Show)

-- | A figure as placed: the image, its size and its caption lines (golem-driver ADR 0005).
data PlacedFigure = PlacedFigure
  { -- | the image, or the page of a PDF figure (golem-pdf ADR 0008)
    pfContent :: !P.FigureContent,
    -- | along the lines
    pfAlong :: !Sp,
    -- | across the lines
    pfAcross :: !Sp,
    pfWrap :: !(Maybe Wrap),
    -- | the grid lines the image takes (m)
    pfImageLines :: !Int,
    pfCaption :: ![PartLine],
    -- | the size of the caption (cs; golem-driver ADR 0010)
    pfCaptionSize :: !Sp,
    -- | the line pitch of the caption (cp)
    pfCaptionPitch :: !Sp,
    -- | the grid lines the caption takes (N)
    pfCaptionSpan :: !Int,
    -- | the exclusion area of a wrapped figure
    pfExclusion :: !(Maybe Exclusion),
    pfExclusionLength :: !Sp,
    -- | the path of the image and the @figure block (golem-cli ADR 0006)
    pfSource :: !Text,
    -- | the page of a PDF figure, from 1 (golem-pdf ADR 0008)
    pfPage :: !Int,
    pfSpan :: !SrcSpan,
    -- | the measure the figure is set against: of the column, or of the frame (golem-driver ADR 0034, docs/adr/0190)
    pfFullAlong :: !Sp,
    -- | how a figure turned onto a page of its own is turned
    pfTurn :: !(Maybe P.Turn),
    -- | the unit of the figure: the place of its image and caption in the structure tree (docs/adr ADR 0183)
    pfUnit :: !Int
  }

{- | A table by its first line (golem-driver ADR 0031): its width, the
height a of its ink above the baseline and the depth d below it, and the
grid lines of its rows. The writer fills a and d from the glyphs it
draws in the cells; the layout leaves them 0.
-}
data TableGeometry = TableGeometry
  { tgWidth :: !Sp,
    tgAscent :: !Sp,
    tgDescent :: !Sp,
    tgLines :: !Int
  }
  deriving stock (Eq, Show)

-- | The result of the layout, read by the writer and the tests.
data PdfLayout = PdfLayout
  { plPages :: ![PageOutAt Sp],
    plLinePitches :: !(Map Int Sp),
    plLines :: !(Map Int SetLine),
    plFigures :: !(Map Int PlacedFigure),
    -- | heading blocks by their first line (golem-driver ADR 0003)
    plHeadings :: !(Map Int HeadingBlock),
    -- | sidenotes by page number (golem-driver ADR 0006)
    plSidenotes :: !(Map Int [PlacedSidenote]),
    {- | the cell lines on each grid line of a table, shifted to their
    columns (golem-driver ADR 0008), each with its place among the lines of
    its row: 0 for a cell at the size of the grid, whose lines are on grid
    lines of their own; the lines of cells of another size are on the first
    grid line of their row, a pitch of their size apart (docs/adr/0262)
    -} plTableLines :: !(Map Int [(Int, SetLine)]),
    -- | the width of each table and its grid lines (golem-driver ADR 0031)
    plTables :: !(Map Int TableGeometry),
    -- | the leader and page number of each table of contents entry, by its last line (golem-driver ADR 0009)
    plTocPages :: !(Map Int TocPage),
    -- | the file of the unit of each first line (golem-driver ADR 0014)
    plLineFiles :: !(Map Int FileId),
    -- | the span of each heading block by its first line
    plHeadingSpans :: !(Map Int SrcSpan),
    -- | the code block of each row of code (golem-driver ADR 0017)
    plCodes :: !(Map Int CodeInfo),
    -- | the notices of the layout (G07030)
    plNotices :: ![Diagnostic],
    -- | the block of the unit of each first line (golem-cli ADR 0006)
    plLineSpans :: !(Map Int SrcSpan),
    -- | the rules of each ruled block by its first line (golem-driver ADR 0027)
    plRules :: !(Map Int RuledInfo),
    -- | visible rule separators by the id of their occupied line (root ADR 0398)
    plSeparatorRules :: !(Map Int SeparatorAppearance),
    -- | the units of the book by their indices, and the composition: what the structure tree is made of (docs/adr ADR 0183)
    plUnits :: ![(Int, Unit)],
    plFlowEnv :: FlowEnv,
    -- | the caption of each table by its first grid line (docs/adr/0262)
    plTableCaptions :: !(Map Int CodeCaption),
    -- | the boxes of paragraphs by their ids (docs/adr/0271)
    plBoxes :: !(Map Int BoxInfo),
    {- | where each destination of a link inside the document is drawn
    (docs/adr/0267): the destinations of labels, headings, index marks and
    entries of the bibliography; those of notes are found from their marks
    -} plDestAnchors :: !(Map LinkDest DestAnchor),
    -- | the page number of each entry of the table of contents as set, by its unit (docs/adr/0267)
    plTocNumbers :: !(Map Int Text),
    -- | the text frames by page number (root ADR 0438)
    plFrames :: !(Map Int [PlacedFrame])
  }

{- | What a destination of a link inside the document is drawn as first
(docs/adr/0267): a line by its id (with what is drawn for it: the cells
of a row, the caption of a table or a code block above it), or the image
of a figure by its unit.
-}
data DestAnchor = AnchorLine !Int | AnchorFigure !Int
  deriving stock (Eq, Show)

data Built = Built
  { bFlow :: [FlowAt Sp],
    bLines :: Map Int SetLine,
    bFigures :: Map Int PlacedFigure,
    -- | heading blocks by their first line
    bHeadings :: Map Int HeadingBlock,
    -- | errors found while building (G07022, G07023, G07024, G07041, G07042)
    bErrors :: [Diagnostic],
    bTableLines :: Map Int [(Int, SetLine)],
    bTables :: Map Int TableGeometry,
    -- | the span of each heading block by its first line (golem-driver ADR 0009)
    bHeadingSpans :: Map Int SrcSpan,
    -- | the heading and the end of the title of each table of contents entry, by its last line
    bTocLines :: Map Int (SrcSpan, Sp, Int),
    -- | the file of each unit by the id of its first line (golem-driver ADR 0014)
    bLineFiles :: Map Int FileId,
    -- | the code block of each row of code (golem-driver ADR 0017)
    bCodes :: Map Int CodeInfo,
    -- | notices (G07030)
    bNotices :: [Diagnostic],
    -- | the block of each unit by the id of its first line (golem-cli ADR 0006)
    bLineSpans :: Map Int SrcSpan,
    -- | the rules of each ruled block by its first line (golem-driver ADR 0027)
    bRules :: Map Int RuledInfo,
    bSeparatorLines :: Map Int SeparatorAppearance,
    -- | the span and the name in messages of each heading by its first line (golem-layout ADR 0020)
    bHeadingNames :: Map Int (SrcSpan, Text),
    -- | the units by their indices, and the composition (docs/adr ADR 0183)
    bUnits :: [(Int, Unit)],
    bFlowEnv :: FlowEnv,
    -- | the units composed and the marker widths of the lists, for the next round of S2 to reuse (docs/adr ADR 0251)
    bComposed :: ComposedUnits,
    bWidths :: Map Int Sp,
    bTableCaptions :: Map Int CodeCaption,
    -- | the boxes by their ids (docs/adr/0271)
    bBoxes :: Map Int BoxInfo,
    -- | where the destinations of links are drawn (docs/adr/0267)
    bDestAnchors :: Map LinkDest DestAnchor,
    -- | G07127: the captions whose indents leave no character, also when the layout stops (docs/adr/0389)
    bCaptionWarnings :: [Diagnostic],
    bLinePitches :: Map Int Sp,
    bBoxPadding :: Map Int Sp,
    bWrappedBefore :: Map Int Sp,
    bFreePages :: Maybe (Either PhysicalFailure [PageOutAt Sp]),
    bUnitFirsts :: Map Int Int,
    bRetainedFlow :: [FlowAt Sp]
  }

{- | What style.toml alone decides before the layout (golem-driver ADR
0016): the page geometry (G07001) and the indent of each paragraph style
(G07025), at the top of @fid@. The driver reports them for golem check too.
-}
styleLayoutDiagnostics :: FileId -> Bool -> Style -> [LocalStyles] -> [Diagnostic]
styleLayoutDiagnostics fid marks style locals = either id (\geom -> indentDiagnostics fid style locals geom <> indexDiagnostics fid style geom <> codeMeasureDiagnostics fid style locals geom) (pageGeometry fid marks style)

{- | Whether indents leave no character of the size @z@ on a line of a
part of the inner width @w@ (docs/adr/0389): @w@ holds one, and the
narrowest line, @w@ less the indent, a positive first-line indent and the
end indent, does not. A negative first-line indent only widens the first
line.
-}
leavesNoCharacter :: Sp -> Indent -> Sp -> Bool
leavesNoCharacter w (Indent s f e _) z = w >= z && w - s - max 0 f - e < z

{- | G07128 (docs/adr/0389): the indents of the paragraph style sidenote
leave no character on a line of the sidenote column, in style.toml or in
the style of a file; at most once, at the top of @fid@. Neither a page
without [sidenotes] nor a vertical page is checked (G07034, G07032). It
does not stop the layout: neither 'checkedGeometry' nor the driver holds
the PDF back before the layout for it.
-}
sidenoteIndentDiagnostics :: FileId -> Bool -> Style -> [LocalStyles] -> [Diagnostic]
sidenoteIndentDiagnostics fid marks style locals = case pageGeometry fid marks style of
  Right geom
    | not (pgVertical geom),
      Just (area, _) <- pgSidenotes geom ->
        take
          1
          [ diagnostic "G07128" Warning (mkSpan fid 0 0) "傍注の字下げが傍注の領域の幅を使い切ります。字下げを小さくするか、[sidenotes] の width を広げてください"
          | st <- style : map (withLocalStyles style) locals,
            let (lk, ind) = paraLook st geom (Just "sidenote"),
            leavesNoCharacter (rectW area) ind (lkSize lk)
          ]
  _ -> []

{- | G07127 (docs/adr/0389): a caption of a unit with a line or more, set
over the inner width @w@, whose indents of caption in the style of its
file leave no character; at the block of the unit.
-}
captionIndentWarnings :: FlowEnv -> Unit -> Sp -> [PartLine] -> [Diagnostic]
captionIndentWarnings fe u w ls =
  [ diagnostic "G07127" Warning (uSpan u) "キャプションの字下げが行の幅を使い切ります。段落スタイル caption の字下げを小さくしてください"
  | not (null ls),
    let (lk, ind) = paraLook (uStyle u) (feGeom fe) (Just "caption"),
    leavesNoCharacter w ind (lkSize lk)
  ]

{- | G07043 (golem-driver ADR 0017): the measure of a column less the padding
on both sides leaves 8 characters of code, in style.toml and in the style
of each file; at the top of @fid@.
-}
codeMeasureDiagnostics :: FileId -> Style -> [LocalStyles] -> PageGeometry -> [Diagnostic]
codeMeasureDiagnostics fid style locals geom =
  nub
    [ diagnostic "G07043" Error (mkSpan fid 0 0) "コードブロックの行長が足りません"
    | st <- style : map (withLocalStyles style) locals,
      let lk = codeLook st geom
          size = lkSize lk,
      columnMeasure geom - 2 * codePadding st size < 8 * size
    ]

{- | The columns of the page as a set (docs/adr ADR 0025): their number,
measure and gap, from line 0.
-}
pageColumnSet :: Style -> PageGeometry -> ColumnSet
pageColumnSet style geom = ColumnSet (length (pgColumns geom)) (columnMeasure geom) (pageColumnGap style geom) 0

-- | The column-gap of [page.grid] in sp; 0 without one.
pageColumnGap :: Style -> PageGeometry -> Sp
pageColumnGap style geom = maybe 0 (dimToSp (pgFontSize geom)) (stPage style >>= pageGrid >>= gridColumnGap)

{- | The columns of the index (docs/adr ADR 0025), when [index] columns
differs from the columns of the page: the width of the type area (its
columns and their gaps, without the sidenote column) cut into that many
columns @column-gap@ apart, rounded down to sp.
-}
indexColumnSet :: Style -> PageGeometry -> Maybe ColumnSet
indexColumnSet style geom = do
  ix <- stIndex style
  -- at most the largest Int (Golem.Project.Style)
  n <- fromIntegral <$> ixColumns ix
  let ta = pgTypeArea geom
      w = if pgVertical geom then rectH ta else rectW ta
      gap = maybe (pageColumnGap style geom) (dimToSp (pgFontSize geom)) (ixColumnGap ix)
  if n == length (pgColumns geom)
    then Nothing
    else Just (ColumnSet n (Sp (unSp (w - fromIntegral (n - 1) * gap) `div` toInteger n)) gap 0)

{- | G07044: the columns of the index leave 8 characters of the type
area's size (docs/adr ADR 0025), at the value of [index] columns.
-}
indexDiagnostics :: FileId -> Style -> PageGeometry -> [Diagnostic]
indexDiagnostics fid style geom =
  [ diagnostic "G07044" Error (mkSpan fid at at) "索引の段の行長が足りません。columns を減らすか column-gap を狭めてください"
  | Just set <- [indexColumnSet style geom],
    csMeasure set < 8 * pgFontSize geom,
    let at = maybe 0 ixColumnsAt (stIndex style)
  ]

{- | The rectangles of the columns of a set on page @n@ (docs/adr ADR
0025): in the type area, left to right in horizontal writing and top to
bottom in vertical writing.
-}
columnSetRects :: PageGeometry -> Int -> ColumnSetAt position -> [Rect]
columnSetRects geom n set =
  let Rect x y w h = typeAreaFor geom n
      m = csMeasure set
      g = csGap set
   in [ if pgVertical geom then Rect x (y + h - fromInteger (i + 1) * m - fromInteger i * g) w m else Rect (x + fromInteger i * (m + g)) y m h
      | i <- [0 .. toInteger (csColumns set) - 1]
      ]

{- | G07025: every paragraph style leaves 8 characters of its own size on a
line of a column (docs/adr ADR 0006, golem-driver ADR 0005 and 0016), in
style.toml and in the style of each file (docs/adr ADR 0014). caption and
sidenote are set over the inner widths of their parts, not the column
(docs/adr/0367), and G07043 checks code (golem-driver ADR 0043).
-}
indentDiagnostics :: FileId -> Style -> [LocalStyles] -> PageGeometry -> [Diagnostic]
indentDiagnostics fid style locals geom =
  nub
    [ diagnostic "G07025" Error (mkSpan fid 0 0) ("段落スタイルの字下げが大きすぎます。行長を段落の文字の大きさの 8 字分以上残してください: " <> name)
    | st <- style : map (withLocalStyles style) locals,
      name <- Map.keys (stParaStyles st),
      name `notElem` ["caption", "sidenote", "code"],
      -- the entries of the table of contents are checked by G07117, with the reserve of the page number (docs/adr/0264)
      not ("toc-" `T.isPrefixOf` name),
      let (lk, Indent s f e _) = paraLook st geom (Just name),
      let size = lkSize lk,
      -- the padding on both sides of a box counts (docs/adr/0271)
      let pad = case paraStyle st (Just name) of
            Just d | hasBox d -> 2 * dimToSp size (fromMaybe (Zw (1 % 2)) (psPadding d))
            _ -> 0,
      -- the end indent counts (docs/adr/0189)
      columnMeasure geom - s - max 0 f - e - pad < 8 * size
    ]

-- | The page geometry, when style.toml passes 'styleLayoutDiagnostics'.
checkedGeometry :: PdfInput -> Either [Diagnostic] PageGeometry
checkedGeometry inp = do
  geom <- pageGeometry (piStyleFile inp) (isJust (piMarks inp)) (piStyle inp)
  case indentDiagnostics (piStyleFile inp) (piStyle inp) (Map.elems (piLocalStyles inp)) geom <> indexDiagnostics (piStyleFile inp) (piStyle inp) geom <> codeMeasureDiagnostics (piStyleFile inp) (piStyle inp) (Map.elems (piLocalStyles inp)) geom of
    [] -> Right geom
    ds -> Left ds

{- | G08009 (golem-driver ADR 0019): a role whose Japanese face has no glyph
for a kenten shape used in it, once for each role and shape, at the top
of @fid@.
-}
kentenGlyphDiagnostics :: FileId -> Bool -> LoadedFonts -> PdfLayout -> [Diagnostic]
kentenGlyphDiagnostics fid vertical fonts layout =
  [ diagnostic "G08009" Error (mkSpan fid 0 0) ("役割 " <> role <> " の和文の書体に圏点の形 " <> kentenShapeName shape <> " の字（" <> codePointText (kentenChar shape) <> "）がありません")
  | (role, shape) <-
      Set.toAscList
        ( Set.fromList
            ( concat
                [ let look = bcLook c
                      opts = lkRubyOptions look
                   in [(lkFace look, shape) | boxKind c == KindKenten, Just shape <- [lkKenten look]]
                        <> [(lkFace (readingLook look), shape) | boxKind c `elem` [KindRuby, KindGroupRuby], Just name <- roReadingKenten opts <> roOtherKenten opts, Just shape <- [kentenShapeFromName name]]
                | l <- layoutLines layout,
                  Box _ c <- lineItems l
                ]
            )
        ),
    let gs = kentenShaped fonts vertical role shape,
    null gs || any ((== 0) . shGlyph) gs
  ]

{- | G07101 (docs/adr ADR 0172): a run of dashes with a dash whose glyph has
no ink, once for each run, at its first dash. Such a glyph is drawn
unscaled.
-}
dashInkNotices :: Bool -> LoadedFonts -> PdfLayout -> [Diagnostic]
dashInkNotices vertical fonts layout =
  [ notice "G07101" (snd (bcSource c)) ("ダッシュの字形に線がないので、二倍ダッシュの線をつながずに描きます: " <> codePointText ch <> "（" <> T.pack (fst (lfFaceFile fonts (shFace g))) <> "）")
  | l <- layoutLines layout,
    Box _ c <- lineItems l,
    boxKind c == KindDashes,
    (ch, g) <- take 1 [(ch, g) | ch <- T.unpack (bcText c), g <- dashShaped fonts vertical (bcLook c) ch, isNothing (dashInk fonts vertical g)]
  ]

{- | G07126 (docs/adr/0302): the ink of a glyph of JLReq's punctuation
reaches a box next to it on its line. The ink is out of the box of the
punctuation, tracking aside, by more than the space between the two
boxes; an overlap that the tracking alone makes is not reported, nor ink
out at the end of a line. Once for each font file and character, at the
first such character of the source.
-}
punctuationInkNotices :: Bool -> LoadedFonts -> PdfLayout -> [Diagnostic]
punctuationInkNotices vertical fonts layout =
  [ notice "G07126" sp ("約物の字面が隣の字にかかります: " <> codePointText ch <> "（" <> T.pack path <> "）")
  | (_, (sp, ch, path)) <- Map.toAscList (Map.fromListWith min [((path, ch), (sp, ch, path)) | (sp, ch, path) <- overlaps])
  ]
  where
    overlaps = [o | l <- layoutLines layout, o <- lineOverlaps (placeLine l)]
    lineOverlaps placed =
      [ (charSpan c ch, ch, fst (lfFaceFile fonts (shFace g)))
      | (i, (Box _ c, s)) <- zip [0 :: Int ..] placed,
        boxKind c == KindPunctuation,
        [ch] <- [T.unpack (bcText c)],
        let look = bcLook c
            size = lkSize look
            gs = lfShape fonts (shapingForFonts fonts vertical look ch) (T.singleton ch),
        g : _ <- [gs],
        Just (lo, hi) <- [inkAlong g],
        let x = s - punctuationPre fonts vertical look ch
            inkStart = x + L.zwToSp size lo
            inkEnd = x + L.zwToSp size hi
            t = trackingOf look
            boxesBefore = [(s' + w', bcLook c') | (Box w' c', s') <- reverse (take i placed)]
            boxesAfter = [s' | (Box _ _, s') <- drop (i + 1) placed],
        or [inkEnd > next + max 0 (negate t) | next : _ <- [boxesAfter]]
          || or [inkStart < prevEnd - max 0 (trackingOf prevLook) | (prevEnd, prevLook) : _ <- [boxesBefore]]
      ]
    -- the ink along the line, in em from the origin of the glyph
    inkAlong g = do
      (x0, y0, x1, y1) <- lfInkBox fonts (shFace g) (shGlyph g)
      let top = lfEmBoxCentral fonts (shFace g) + 1 / 2
          (a, b) = if vertical && not (shTurned g) then (top - y1, top - y0) else (x0 + fst (shOffset g), x1 + fst (shOffset g))
      if b > a then Just (a, b) else Nothing
    trackingOf lk = L.Sp (round (toInteger (lkTracking lk) * L.unSp (lkSize lk) % 1000))
    -- the character itself where the source has it (docs/adr ADR 0195), else the span of the box
    charSpan c ch
      | bcAt c >= 0 = mkSpan (spanFile (snd (bcSource c))) (bcAt c) (bcAt c + BS.length (TE.encodeUtf8 (T.singleton ch)))
      | otherwise = snd (bcSource c)

-- | Every line of a layout: of the text, notes, sidenotes, tables, captions and the table of contents.
layoutLines :: PdfLayout -> [Line]
layoutLines layout =
  concat
    [ concat [slLine sl : concatMap snd (slNotes sl) <> map ptLine (concatMap snd (slSidenotes sl)) | sl <- Map.elems (plLines layout)],
      [slLine sl | sls <- Map.elems (plTableLines layout), (_, sl) <- sls],
      map ptLine (concatMap pfCaption (Map.elems (plFigures layout))),
      map ptLine (concatMap psLines (concat (Map.elems (plSidenotes layout)))),
      concat [[tpLeader tp, tpNumber tp] | tp <- Map.elems (plTocPages layout)]
    ]

{- | The flow and its lines as (line length, indent), in order, laid out
with no page numbers assumed (for tests).
-}
flowLines :: FontProvider -> PdfInput -> IO (Either [Diagnostic] ([FlowAt Sp], [(Sp, Sp)]))
flowLines provider inp0 = case checkedGeometry inp of
  Left ds -> pure (Left ds)
  Right geom -> do
    lf <- loadFonts provider (piFiles inp) (piStyleFile inp) (piStyle inp) (Map.elems (piLocalStyles inp))
    case lf of
      Left ds -> pure (Left ds)
      Right fonts -> do
        figures <- Map.mapMaybe (either (const Nothing) Just) <$> loadFigures inp
        built <- buildFlow inp geom fonts figures Nothing (Assumed Map.empty Map.empty Map.empty Map.empty)
        pure (Right (bFlow built, [(lineTarget (slLine sl), slIndent sl) | sl <- Map.elems (bLines built)]))
  where
    inp = codeInput inp0

-- | Composition, line breaking and pagination, with page references resolved (S2).
layoutPdf :: PdfInput -> PageGeometry -> LoadedFonts -> IO (Either [Diagnostic] PdfLayout)
layoutPdf = layoutPdfWith True

{- | 'layoutPdf' with the compositions of the units that did not change
reused between the rounds of S2 or not (docs/adr ADR 0251): the result is
the same, and the tests compare the two.
-}
layoutPdfWith :: Bool -> PdfInput -> PageGeometry -> LoadedFonts -> IO (Either [Diagnostic] PdfLayout)
layoutPdfWith reuse = layoutPdfNumbering reuse True

{- | 'layoutPdf' without numbering the notes per page once the pages are
settled (docs/adr/0383): the marks keep the numbers of the book. The
tests compare it with 'layoutPdf' to see that numbering the pages lays
out nothing again.
-}
layoutPdfUnnumbered :: PdfInput -> PageGeometry -> LoadedFonts -> IO (Either [Diagnostic] PdfLayout)
layoutPdfUnnumbered = layoutPdfNumbering True False

-- | 'layoutPdfWith', numbering the notes per page or not (docs/adr/0383).
layoutPdfNumbering :: Bool -> Bool -> PdfInput -> PageGeometry -> LoadedFonts -> IO (Either [Diagnostic] PdfLayout)
layoutPdfNumbering reuse numbered inp0 geom fonts =
  let inp = codeInput inp0
   in case sidenoteDiagnostics geom (piBook inp) <> listNumberDiagnostics (lsNumbers (stLists (piStyle inp))) (pgVertical geom) (piBook inp) <> noteNumberDiagnostics True (piStyle inp) (piBook inp) of
        ds@(_ : _) -> pure (Left ds)
        [] -> do
          loaded <- loadFigures inp
          -- a figure that cannot be placed stops the PDF (G08010, golem-pdf ADR 0008)
          case figureDiagnostics inp loaded of
            ds@(_ : _) -> pure (Left ds)
            [] -> layoutFigures reuse numbered inp geom fonts (Map.mapMaybe (either (const Nothing) Just) loaded)

-- | 'layoutPdf' with the figures read.
layoutFigures :: Bool -> Bool -> PdfInput -> PageGeometry -> LoadedFonts -> Map (Text, Int) P.FigureContent -> IO (Either [Diagnostic] PdfLayout)
layoutFigures reuse numbered inp geom fonts figures = do
  -- S2: compose with assumed page numbers until they settle
  -- the names of the marks for G07021: the terms of the index, the bodies of the entries of channels (golem-doc ADR 0007)
  let terms =
        Map.fromList
          ( [(sp, T.intercalate " / " (igTerms g)) | g <- indexGroups (bookDocs (piBook inp)), l <- igLocators g, (_, sp) <- locatorMarks l]
              <> [(sp, T.concat (map inlineText (ceBody e))) | (_, _, es) <- bookChannels (piBook inp), e <- es, (_, sp) <- ceLocations e]
              -- the labels of the notes, whose pages are those of their marks (root ADR 0422)
              <> Map.toList (noteLabelSpans (piBook inp))
          )
  let capacity = length (pgLineGrid geom)
      -- the round before, whose compositions of the units that did not change are reused (docs/adr ADR 0251)
      round' prev assumed = do
        built <- buildFlow inp geom fonts figures (if reuse then prev else Nothing) assumed
        pure $
          if not (null (bErrors built))
            then Left (bErrors built <> bCaptionWarnings built)
            else
              let pagesResult = paginateBuilt inp geom capacity built
                  pages = fromRight [] pagesResult
                  errors =
                    [ diagnostic "G07125" Error sp ("脚注の印、区切りの領域と脚注本文の一行が " <> T.pack (show n) <> " 行の段に収まりません")
                    | p <- pages,
                      UnplaceableFootnote (NoteId sp _) n <- poUnmet p
                    ]
                      <> separatorHoldErrors built pages
               in case pagesResult of
                    Left ds -> Left (ds <> bCaptionWarnings built)
                    Right _ -> if null errors then Right (built, pages) else Left (errors <> bCaptionWarnings built)
      labels = labelSpans (piBook inp)
      labelSpan l = Map.findWithDefault (mkSpan (piStyleFile inp) 0 0) l labels
  result <- fixpointWith (bookSections inp) labelSpan (\sp -> Map.findWithDefault "" sp terms) (\built pages -> fst (aroundCuts inp geom built pages)) (assumedMasters inp geom) round'
  pure $ case result of
    Left ds -> Left ds
    -- the ranges of the index on the settled pages stop the PDF (docs/adr/0265)
    Right (built, pages)
      | ds@(_ : _) <- indexRangeDiagnostics (piBook inp) (`Map.lookup` markPages (bookSections inp) pages) -> Left (sortDiagnostics ds <> bCaptionWarnings built)
    Right (built0, pages) ->
      -- sidenotes are placed once, on the settled pages (golem-driver ADR 0006)
      -- in the size of the document of each sidenote (docs/adr ADR 0014)
      let -- the lines towards and away from the spine on their pages (docs/adr/0189)
          -- numbered per page, the marks take the numbers of their pages, once the pages are settled (docs/adr/0383)
          built = (if numbered then renumberPageNotes pages else id) (built0 {bLines = alignToSpine geom pages (bLines built0)})
          metricsOf sp = let (_, size, pitch) = sidenoteMetrics (docStyle inp (spanFile sp)) geom in (pitch, size)
          placed = [(poNumber p, placePageSidenotes geom metricsOf (bLines built) p) | p <- pages]
          -- the pages of the table of contents, once, on the settled pages (golem-driver ADR 0009)
          hPages = headingPages (bHeadingSpans built) pages
          pageLbls = pageLabels (bookSections inp) pages
          unitsAt = Map.fromList (bUnits built)
          -- the leader and the page number are at the heading of the entry (golem-cli ADR 0008)
          atHeading hs tp = tp {tpLeader = withBoxSource (SourceGrid, hs) (tpLeader tp), tpNumber = withBoxSource (SourceGrid, hs) (tpNumber tp)}
          -- each entry in the look of its paragraph style, its page number in toc-page-number (docs/adr/0264)
          tocEntries =
            [ (lid, ui, atHeading hs (tocPage (entryGeometry (pgFontSize geom) (bFlowEnv built) (piStyle inp) u) e (pageNumberLine (unitEnv (bFlowEnv built) u) l)))
            | (lid, (hs, e, ui)) <- Map.toList (bTocLines built),
              Just u <- [Map.lookup ui unitsAt],
              Just n <- [Map.lookup hs hPages],
              let l = Map.findWithDefault (plainLabel (fromInteger n)) (fromInteger n) pageLbls
            ]
          tocPages = Map.fromList [(lid, tp) | (lid, _, tp) <- tocEntries]
          -- the page number of each entry as set, for the text of its link (docs/adr/0267)
          tocNumbers = Map.fromList [(ui, T.concat [bcText c | Box _ c <- lineItems (tpNumber tp)]) | (_, ui, tp) <- tocEntries]
       in case pageNoteNumberDiagnostics (piStyle inp) (piBook inp) (pageNoteNumbers pages built0) <> concat [ds | (_, Left ds) <- placed] of
            [] ->
              let layout0 = PdfLayout pages (bLinePitches built) (bLines built) (bFigures built) (bHeadings built) (Map.fromList [(n, ps) | (n, Right ps@(_ : _)) <- placed]) (bTableLines built) (bTables built) tocPages (bLineFiles built) (bHeadingSpans built) (bCodes built) (bNotices built <> bCaptionWarnings built <> ruledNotices (bFlow built) (bRules built) pages <> unmetWarnings (pgLinePitch geom) (maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle inp) >>= pageGrid)) (`Set.member` separatorSpans built) (bHeadingNames built) (paraOfLine built) (styleAtSpan built) pages <> heldNeedNotices (bUnits built) <> softHyphenNotices inp <> (if numbered then chapterPageNoteWarnings inp (pageNoteNumbers pages built0) else [])) (bLineSpans built) (bRules built) (bSeparatorLines built) (bUnits built) (bFlowEnv built) (bTableCaptions built) (bBoxes built) (bDestAnchors built) tocNumbers Map.empty
                  -- the text frames, once, on the settled pages (root ADR 0438)
                  (frameErrors0, frames) = layoutFrames inp geom layout0
                  frameErrors = snd (aroundCuts inp geom built0 pages) <> unplacedErrors built0 pages <> frameErrors0
               in if null frameErrors then Right layout0 {plFrames = frames} else Left (frameErrors <> bCaptionWarnings built)
            ds -> Left (ds <> bCaptionWarnings built)

{- | G07142: a table, a code block or a figure that the pagination left out
of an empty column, as no place of it keeps its least part off the frames
of wrap around (root ADR 0456); at its block, once.
-}
unplacedErrors :: Built -> [PageOutAt Sp] -> [Diagnostic]
unplacedErrors built pages =
  nubOrdOn
    diagSpan
    [ diagnostic "G07142" Error sp "回り込むフレームのまわりに、このブロックを置ける空きがありません"
    | p <- pages,
      UnplacedBlock ident <- poUnmet p,
      let sp = maybe (maybe (mkSpan (FileId 0) 0 0) snd (Map.lookupLE ident (bLineSpans built))) pfSpan (Map.lookup ident (bFigures built))
    ]

-- Ordinary paragraph keep options may fall back when no empty column fits.
-- A visible separator instead requires its whole chain and the first display
-- line of the next block in one column (root ADR 0398 I7).
separatorHoldErrors :: Built -> [PageOutAt Sp] -> [Diagnostic]
separatorHoldErrors built pages =
  [ diagnostic "G07134" Error site "区切りと後続ブロックの最初の行を同じ段に配置できません"
  | (site, identifiers) <- groups [] (bUnits built),
    placed : remaining <- [mapMaybe (`Map.lookup` places) identifiers],
    any (/= placed) remaining
  ]
  where
    places = Map.fromListWith (\_ old -> old) [(ident, (poNumber page, poColumn page)) | page <- pages, (_, slot) <- poSlots page, ident <- ids slot]
    ids = \case
      SLine ident -> [ident]
      SFigure ident -> [ident]
      SWrapped ident -> [ident]
      SPageFigure ident -> [ident]
      SHeading ident count -> take count [ident ..]
      SCode ident count _ -> take count [ident ..]
    groups _ [] = []
    groups pending ((index, unit) : rest) = case uKind unit of
      USeparator _ -> case Map.lookup index (bUnitFirsts built) of
        Just ident -> groups ((uSpan unit, ident) : pending) rest
        Nothing -> groups pending rest
      UBreak _ -> groups [] rest
      USection _ _ -> groups [] rest
      UColumns _ -> groups [] rest
      UGap _ -> groups pending rest
      UBlank _ -> groups pending rest
      UKeepNext _ -> groups pending rest
      UPageControl _ -> groups pending rest
      UHeldNeedLines {} -> groups pending rest
      _ -> case (reverse pending, Map.lookup index (bUnitFirsts built)) of
        ((site, _) : _, Just ident) -> (site, reverse (map snd pending) <> [ident]) : groups [] rest
        _ -> groups pending rest

-- | The spans of the visible separators, those of their keeps too (root ADR 0398 I7).
separatorSpans :: Built -> Set.Set SrcSpan
separatorSpans built = Set.fromList [uSpan u | (_, u) <- bUnits built, USeparator _ <- [uKind u]]

paginateBuilt :: PdfInput -> PageGeometry -> Int -> Built -> Either [Diagnostic] [PageOutAt Sp]
paginateBuilt inp geom capacity built
  | free = either (Left . pure . physicalError) Right (fromMaybe (paginatePhysical settings (bRetainedFlow built)) (bFreePages built))
  | otherwise = Right (map normalize (paginateAvoiding (avoidLines inp geom built) (separatorSpans built) (adjustLimit geom) (pgNoteSeparator geom) (pageColumnSet (piStyle inp) geom) capacity (map (fmap gridUnits) (bRetainedFlow built))))
  where
    pitch = pgLinePitch geom
    face = pgFontSize geom
    height = fromIntegral (max 0 (capacity - 1)) * pitch + face
    free = maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle inp) >>= pageGrid)
    gridUnits n = fromInteger (unSp n `div` unSp pitch)
    normalize page =
      let scaled = fmap (\n -> fromIntegral n * pitch) page
       in scaled {poBoxes = [b {bsLast = bsLast b + pitch} | b <- poBoxes scaled]}
    settings = physicalSettings inp geom capacity built
    atLine ident = Map.findWithDefault (mkSpan (piStyleFile inp) 0 0) ident (bLineSpans built)
    physicalError failure = case failure of
      PhysicalLineTooTall ident ->
        let (sp, name) = fromMaybe (atLine ident, "body") (paraOfLine built ident)
         in diagnostic "G07129" Error sp ("段落スタイル " <> name <> " の一行が段に収まりません")
      PhysicalFootnoteTooTall (NoteId sp _) -> diagnostic "G07130" Error sp "脚注の最初の一行を段に配置できません"
      PhysicalHeadingTooTall ident -> diagnostic "G07024" Error (atLine ident) "見出しが版面に入りません"
      PhysicalTableTooTall ident -> diagnostic "G07042" Error (atLine ident) "表の最小部分が段に収まりません"
      PhysicalTableCaptionTooTall ident -> diagnostic "G07116" Error (atLine ident) "表とキャプションの最小部分が段に収まりません"
      PhysicalCodeTooTall ident -> diagnostic "G07043" Error (atLine ident) "コードの最小部分が段に収まりません"
      PhysicalBoxTooTall ident -> diagnostic "G07121" Error (atLine ident) "囲みの一行と padding が段に収まりません"
      PhysicalFigureTooTall ident -> diagnostic (if height < pitch then "G07131" else "G07038") Error (atLine ident) "図版の一行分の領域が段に収まりません"

-- | Resolve the same physical geometry for a causal trial and final pagination.
physicalSettings :: PdfInput -> PageGeometry -> Int -> Built -> PhysicalSettings
physicalSettings inp geom capacity built =
  PhysicalSettings pitch face height (fromIntegral (max 0 (adjustLimit geom - 1)) * pitch + face) (fromIntegral (pgNoteSeparator geom) * pitch) (fmap (\n -> fromIntegral n * pitch) (pageColumnSet (piStyle inp) geom)) (bLinePitches built) (Map.map slSize (bLines built)) (bBoxPadding built) (bWrappedBefore built) headingBounds Nothing (separatorSpans built) (avoidAcross inp geom built)
  where
    pitch = pgLinePitch geom
    face = pgFontSize geom
    height = fromIntegral (max 0 (capacity - 1)) * pitch + face
    headingBounds = Map.fromList (concatMap boundsInFlow (bFlow built))
    boundsInFlow flow = case flow of
      FHeading {fhLines = rows} -> boundsOf rows
      FRuled {frBody = RuledHeading {rhLines = rows}} -> boundsOf rows
      FBoxed {fbBody = body} -> concatMap boundsInFlow body
      _ -> []
    boundsOf rows = case rows of
      firstRow : _
        | Just block <- Map.lookup (lbId firstRow) (bHeadings built),
          Just lastRow <- listToMaybe (reverse rows),
          Just lastSet <- Map.lookup (lbId lastRow) (bLines built) ->
            let firstOffset = faceOffset pitch face + hbOffset block
                lastEnd = firstOffset + fromIntegral (length rows - 1) * hbPitch block + slSize lastSet
             in [(lbId firstRow, (firstOffset, lastEnd))]
      _ -> []

-- | Warn once per chapter when its collected notes repeat a page-local number (root ADR 0402).
chapterPageNoteWarnings :: PdfInput -> Map (NoteChannel, Int) Int -> [Diagnostic]
chapterPageNoteWarnings inp numbers = mapMaybe chapter (bookChapters (piBook inp))
  where
    chapter docs = case reverse docs of
      Document fid _ : _
        | let style = docStyle inp fid,
          stNotesNumbering style == NumberPerPage,
          stNotesPlacement style == PlaceChapterEnd ->
            repeated Set.empty (concatMap documentNotes docs)
      _ -> Nothing
    repeated _ [] = Nothing
    repeated seen ((sp, n, _) : rest) = case Map.lookup (ChannelNote, n) numbers of
      Nothing -> repeated seen rest
      Just k
        | Set.member k seen -> Just (diagnostic "G07132" Warning sp "ページごとの注番号のため、章末の注の一覧に同じ番号が重なります。[notes] の numbering を \"chapter\" か \"book\" にすると、一覧の番号を区別できます")
        | otherwise -> repeated (Set.insert k seen) rest

{- | The marks of notes numbered per page with their numbers (docs/adr/0383),
on the settled pages: each page numbers the notes and the sidenotes it
calls apart, from 1 in the order of the book, which is that of their
numbers before the pages were known; the mark at the start of the body
takes the number of its mark in the text. A mark keeps the width it
reserved, so no line and no page changes: nothing is laid out again. A
layout of another numbering has no such marks and is as it is.
-}
renumberPageNotes :: [PageOutAt Sp] -> Built -> Built
renumberPageNotes pages built
  | isNothing (feMarkReserve fe) = built
  | otherwise =
      built
        { bLines = Map.map setLine (bLines built),
          bTableLines = Map.map (map (fmap setLine)) (bTableLines built),
          bFigures = Map.map (\pf -> pf {pfCaption = map partLine (pfCaption pf)}) (bFigures built),
          bCodes = Map.map (\ci -> ci {ciCaption = map partLine (ciCaption ci), ciContinued = line <$> ciContinued ci}) (bCodes built),
          bTableCaptions = Map.map (\cc -> cc {ccLines = map partLine (ccLines cc)}) (bTableCaptions built)
        }
  where
    fe = bFlowEnv built
    numbers = pageNoteNumbers pages built
    numberOf ch n = Map.findWithDefault n (ch, n) numbers
    env = feBodyEnv fe
    line l = l {lineItems = map item (lineItems l)}
    item = \case
      Box w c -> Box w (renumberMark env numberOf c)
      other -> other
    partLine pl = pl {ptLine = line (ptLine pl)}
    setLine sl = sl {slLine = line (slLine sl), slNotes = [(k, map line ls) | (k, ls) <- slNotes sl], slSidenotes = [(sp, map partLine ls) | (sp, ls) <- slSidenotes sl]}

{- | The number each note and sidenote takes on its page (docs/adr/0383),
by its channel and its number in the book: its place among the marks in
the text of its channel on the page where its mark is first set (a
header row of a table is set again on later pages), in the order of the
book. The marks are those of the lines of the text, the headings, the
tables and their captions, the captions of figures and code blocks.
-}
pageNoteNumbers :: [PageOutAt Sp] -> Built -> Map (NoteChannel, Int) Int
pageNoteNumbers pages built =
  Map.fromList
    [ ((ch, n), k)
    | (_, calls) <- Map.toAscList byPage,
      (ch, ns) <- Map.toList (Map.fromListWith (<>) [(ch, [n]) | (ch, n) <- calls]),
      (k, n) <- zip [1 ..] (Set.toAscList (Set.fromList ns))
    ]
  where
    -- the first page of each call, then the calls of each page
    firstPages = Map.fromListWith min [(call, poNumber p) | p <- pages, l <- columnLines p, call <- callsIn l]
    byPage = Map.fromListWith (<>) [(pg, [call]) | (call, pg) <- Map.toList firstPages]
    callsIn l = [(mnChannel mn, mnNumber mn) | Box _ c <- lineItems l, Just mb <- [bcMark c], Just mn <- [mbNumber mb], mnCall mn]
    lineAt lid = slLine <$> Map.lookup lid (bLines built)
    columnLines p =
      concat
        [ case s of
            SLine lid ->
              maybe [] pure (lineAt lid)
                <> map (slLine . snd) (Map.findWithDefault [] lid (bTableLines built))
                <> maybe [] (map ptLine . ccLines) (Map.lookup lid (bTableCaptions built))
            SHeading lid m -> mapMaybe lineAt [lid .. lid + m - 1]
            SCode lid k _ ->
              mapMaybe lineAt [lid .. lid + k - 1]
                <> [ptLine pl | Just ci <- [Map.lookup lid (bCodes built)], lid == ciFirst ci, pl <- ciCaption ci]
            SFigure fid -> figureCaption fid
            SWrapped fid -> figureCaption fid
            SPageFigure fid -> figureCaption fid
        | (_, s) <- sortOn fst (poSlots p)
        ]
    figureCaption fid = maybe [] (map ptLine . pfCaption) (Map.lookup fid (bFigures built))

{- | The most grid lines a column may have with @page-lines (docs/adr ADR
0030): the grid goes on past the type area in the direction of the
lines, as long as the face of a line stays inside the trimmed page.
-}
adjustLimit :: PageGeometry -> Int
adjustLimit geom =
  let n = length (pgLineGrid geom)
      fs = pgFontSize geom
      at = gridLine geom
      areas = [pgTypeArea geom, pgTypeAreaEven geom]
      inside k
        | pgVertical geom = all (\r -> rectX r + rectW r - at k - Sp (unSp fs `div` 2) >= 0) areas
        | otherwise = all (\r -> rectY r + rectH r - at k - (fs - L.zwToSp fs baselineRatio) >= 0) areas
   in n + length (takeWhile inside [n .. n + 999])

{- | The position of grid line @k@ from the type area, past its last line
too (docs/adr ADR 0030).
-}
gridLine :: PageGeometry -> Int -> Sp
gridLine geom k = case (drop k grid, grid) of
  (g : _, _) -> g
  (_, g0 : _) -> g0 + fromIntegral k * pgLinePitch geom
  _ -> fromIntegral k * pgLinePitch geom
  where
    grid = pgLineGrid geom

-- | why @page-lines was cut short, at the head of G07037 (docs/adr ADR 0030)
adjustReason :: AdjustLimit -> Text
adjustReason = \case
  AdjustNoRoom -> "段に余りがないため、"
  AdjustLinesPlaced -> "段にすでに行を置いているため、"
  AdjustOneLine -> "段には少なくとも 1 行を残すため、"

{- | G07037: the manual controls of page breaks not met (docs/adr ADR
0030); G07047: the blank lines dropped (docs/adr ADR 0046); G07100: the
headings taller than the rest of their columns, named by @names@
(golem-layout ADR 0020).
-}

-- | The block and the paragraph style of the unit of a line (docs/adr/0261).
paraOfLine :: Built -> Int -> Maybe (SrcSpan, Text)
paraOfLine built lid = (\(_, sp) -> (sp, styleAtSpan built sp)) <$> Map.lookupLE lid (bLineSpans built)

-- | The paragraph style of the paragraph of a block, body without one (docs/adr/0261).
styleAtSpan :: Built -> SrcSpan -> Text
styleAtSpan built sp = fromMaybe "body" (listToMaybe [n | (_, u) <- bUnits built, uSpan u == sp, Just n <- [uParaStyle u]])

{- | G07037: a need-lines in a separator hold that no column fits with the
lines of the hold before it (root ADR 0398 I7).
-}
heldNeedNotices :: [(Int, Unit)] -> [Diagnostic]
heldNeedNotices units =
  [ diagnostic "G07037" Warning (uSpan u) ("区切りからの " <> T.pack (show before) <> " 行と合わせると、@need-lines " <> T.pack (show k) <> " は段の行数 " <> T.pack (show columnLines) <> " を超えます")
  | (_, u@Unit {uKind = UHeldNeedLines before k columnLines}) <- units
  ]

unmetWarnings :: Sp -> Bool -> (SrcSpan -> Bool) -> Map Int (SrcSpan, Text) -> (Int -> Maybe (SrcSpan, Text)) -> (SrcSpan -> Text) -> [PageOutAt Sp] -> [Diagnostic]
unmetWarnings pagePitch free held names paraOf styleAt pages =
  [ d
  | p <- pages,
    u <- poUnmet p,
    d <- case u of
      SplitBookPart sp kind unit -> [notice "G07133" sp (kind <> "が空の保持単位にも収まらないため、" <> keepName unit <> " の保持を外して通常の位置で分けました")]
      UnmetNoBreak sp -> [diagnostic "G07037" Warning sp "ここで改ページを止められませんでした"]
      -- the need-lines asked for before a separator hold, at the span of
      -- the separator, is not written by the author: it reports nothing
      -- of its own (root ADR 0398 I7)
      UnmetNeedLines sp _ | held sp -> []
      -- the keep of a separator is not written by the author either: a
      -- hold not met is G07134 (root ADR 0398 I7)
      UnmetKeepNext sp | held sp -> []
      UnmetNeedLines sp k ->
        [ diagnostic
            "G07037"
            Warning
            sp
            ( if free
                then "@need-lines " <> T.pack (show k) <> " の長さ " <> L.ptText (fromIntegral k * pagePitch) <> "pt は段の長さ " <> L.ptText (poLines p) <> "pt を超えます"
                else "@need-lines " <> T.pack (show k) <> " は段の行数 " <> T.pack (show (unSp (poLines p) `div` unSp pagePitch)) <> " を超えます"
            )
        ]
      UnmetAdjust sp k limit -> [diagnostic "G07037" Warning sp (adjustReason limit <> "@page-lines の増減を " <> T.pack (show k) <> " 行に切り詰めました")]
      -- G07047: blank lines dropped at the top of a column (docs/adr ADR 0046), an info (docs/adr 0104)
      DroppedBlank sp -> [infoDiagnostic "G07047" sp "段の先頭に来た @blank-line の空きを捨てました"]
      -- G07142 is an error of the layout (root ADR 0456)
      UnplacedBlock _ -> []
      TallHeading i n room ->
        [ notice "G07100" sp ("見出しが段に入りません（" <> name <> "。見出しは " <> T.pack (show n) <> " 行、段の残りは " <> T.pack (show room) <> " 行）")
        | Just (sp, name) <- [Map.lookup i names]
        ]
      TallHeadingExtent i extent remaining ->
        [ notice "G07100" sp ("見出しが段に入りません（" <> name <> "。見出しの長さ " <> L.ptText extent <> "pt、段の残り " <> L.ptText remaining <> "pt）")
        | Just (sp, name) <- [Map.lookup i names]
        ]
      -- G07111, G07112, G07113: the keep options not met (docs/adr/0261)
      UnmetKeepNext sp -> [diagnostic "G07111" Warning sp ("段落スタイル " <> styleAt sp <> " の keep-with-next を守れませんでした")]
      UnplaceableFootnote {} -> []
      SplitKept i -> [notice "G07112" sp ("段落スタイル " <> name <> " の段落が段に入らないので、keep-all-lines を外して分けました") | Just (sp, name) <- [paraOf i]]
      ShortPart part i asked placed ->
        [ notice "G07113" sp ("段の行が足りないので、段落の" <> (if part == FirstPart then "最初" else "最後") <> "の部分を " <> T.pack (show placed) <> " 行にしました（keep-" <> (if part == FirstPart then "first" else "last") <> "-lines = " <> T.pack (show asked) <> "）")
        | Just (sp, _) <- [paraOf i]
        ]
  ]

keepName :: KeepParts -> Text
keepName = \case KeepColumn -> "column"; KeepPage -> "page"; KeepSpread -> "spread"

{- | G07046 (golem-driver ADR 0027): a ruled paragraph broken between
columns, or a ruled heading that lost a rule, because an empty column
could not hold its block.
-}
ruledNotices :: [FlowAt Sp] -> Map Int RuledInfo -> [PageOutAt Sp] -> [Diagnostic]
ruledNotices flow infos pages =
  [ if riHeading info
      then notice "G07046" (riSpan info) ("罫線を持つ見出しが版面に入らないため、罫線を省きました（" <> riOwner info <> "）")
      else notice "G07046" (riSpan info) ("罫線を持つ段落が版面に入らないため、罫線を省いて分けて組みました（" <> riOwner info <> "）")
  | f@FRuled {} <- flow,
    let ids = case frBody f of
          RuledLines _ ls -> map lbId ls
          RuledHeading {} -> []
        columns = length [() | p <- pages, any (\case (_, SLine l) -> l `elem` ids; _ -> False) (poSlots p)]
        placed b = any (any (\r -> prId r == frId f && prBefore r == b) . poRules) pages
        lost = (isJust (frBefore f) && not (placed True)) || (isJust (frAfter f) && not (placed False)),
    columns > 1 || lost,
    Just info <- [Map.lookup (frId f) infos]
  ]

{- | The page of each heading (golem-driver ADR 0009): the page where the
first line of its block is placed, keyed by the span of the block.
-}
headingPages :: Map Int SrcSpan -> [PageOutAt Sp] -> Map SrcSpan Integer
headingPages spans ps =
  Map.fromList [(hs, toInteger (poNumber p)) | p <- ps, (_, SHeading lid _) <- poSlots p, Just hs <- [Map.lookup lid spans]]

{- | The headings that start on each page (golem-driver ADR 0014), in the
order they are placed, looked up by the first line of their block.
-}
headingsOnPages :: (Int -> Maybe HeadingInfo) -> [PageOutAt Sp] -> Map Int [HeadingInfo]
headingsOnPages infoOf ps =
  -- the columns of a page in their order (docs/adr ADR 0018)
  Map.fromListWith (flip (<>)) [(poNumber p, [h | (_, SHeading lid _) <- poSlots p, Just h <- [infoOf lid]]) | p <- ps]

{- | The headings in effect after a heading: it is the one of its level,
and the levels below it have none.
-}
activeAfter :: Map Int (Maybe HeadingInfo) -> HeadingInfo -> Map Int (Maybe HeadingInfo)
activeAfter m h = Map.insert (hiLevel h) (Just h) (Map.mapWithKey (\l v -> if l > hiLevel h then Nothing else v) m)

{- | The lines of a running head drawn on a page (golem-driver ADR 0014,
0022), from the text of the metadata, the variables of [vars] by their
paths (docs/adr/0185), the variables of the page's file, the content, the headings in effect at the start of the page by level,
and the headings that start on the page. A line with a slot without @?@
and without a value is left out; a slot with @?@ and without a value is
empty; a line is trimmed of spaces (U+0020, U+3000) and left out when
nothing is left.
-}
runningHeadLines :: Map Text Text -> Map [Text] Text -> Map [Text] Text -> RunningContent -> Map Int (Maybe HeadingInfo) -> [HeadingInfo] -> [Text]
runningHeadLines = runningHeadLinesWith (const Nothing)

runningHeadLinesWith :: (HeadingInfo -> Maybe Text) -> Map Text Text -> Map [Text] Text -> Map [Text] Text -> RunningContent -> Map Int (Maybe HeadingInfo) -> [HeadingInfo] -> [Text]
runningHeadLinesWith separator meta projectVars vars content start started = case content of
  RunningNone -> []
  RunningLines ls -> mapMaybe line (toList ls)
  where
    line parts = do
      pieces <- traverse piece parts
      let t = T.dropAround (`elem` [' ', '\x3000']) (T.concat pieces)
      if T.null t then Nothing else Just t
    piece = \case
      PartText t -> Just t
      PartRef r optional -> case mfilter (not . T.null) (value r) of
        Just v -> Just v
        Nothing -> if optional then Just "" else Nothing
    value = \case
      RefMeta k -> Map.lookup k meta
      RefVar n -> Map.lookup n vars
      RefProjectVar n -> Map.lookup n projectVars
      RefHeading l form pick ->
        let here = [h | h <- started, hiLevel h == l]
            atEnd = foldl' activeAfter start started
            chosen = case pick of
              PickFirst -> listToMaybe here <|> join (Map.lookup l start)
              PickLast -> listToMaybe (reverse here) <|> join (Map.lookup l atEnd)
            short h = T.concat (map inlineText (hiTitle h))
            render h = case form of
              HeadShort -> Just (short h)
              -- the separator of the language of the book (golem-html ADR 0002)
              HeadNumbered -> Just (maybe (short h) (\n -> n <> titleSeparator (Map.findWithDefault "" "language" meta) (separator h) n (short h) <> short h) (hiNumberText h))
              HeadNumber -> hiNumberText h
         in chosen >>= render

{- | The inlines of a numbered title (golem-html ADR 0002): the number, the
separator of the language of the book and the title; the title alone
without a number.
-}
numberedTitle :: Text -> SrcSpan -> Maybe Text -> [Inline] -> [Inline]
numberedTitle lang sp num is = numberedTitleWith Nothing lang sp num is is

{- | 'numberedTitle' with the separator the style of the file of the span
gives for the level of a heading, or for a caption with no level (Golem
ADR 0372).
-}
bookNumberedTitle :: Book -> Maybe Int -> Text -> SrcSpan -> Maybe Text -> [Inline] -> [Inline]
bookNumberedTitle book level lang sp num is = numberPrefix book level lang sp num is <> is

{- | The number and the separator alone; the separator is left out when the
title (the last argument, only its text is read) is empty (Golem ADR 0372).
-}
numberPrefix :: Book -> Maybe Int -> Text -> SrcSpan -> Maybe Text -> [Inline] -> [Inline]
numberPrefix book level lang sp num title = numberedTitleWith (Map.lookup (spanFile sp, level) (bookTitleSeparators book)) lang sp num title []

numberedTitleWith :: Maybe Text -> Text -> SrcSpan -> Maybe Text -> [Inline] -> [Inline] -> [Inline]
numberedTitleWith separator lang sp num title is = maybe [] (\n -> [Text sp (n <> titleSeparator lang separator n (foldMap inlineText title))]) num <> is

{- | The sections of the book (docs/adr/0260): the page-numbering of each
chapter file, by its place among the chapter files.
-}
bookSections :: PdfInput -> Map Int Section
bookSections inp =
  Map.fromList
    [ (i, Section (pnStart n) (pnNotation n))
    | (i, Just n) <- zip [0 ..] (chapterNumberings (manifestChapters (projectManifest (piProject inp))))
    ]

-- | The label of each page of a layout, by its number (docs/adr/0260).
layoutLabels :: PdfInput -> PdfLayout -> Map Int PageLabel
layoutLabels inp layout = pageLabels (bookSections inp) (plPages layout)

-- | The columns of each page, in order (docs/adr ADR 0018).
pagesOf :: [PageOutAt Sp] -> [[PageOutAt Sp]]
pagesOf = groupBy (\a b -> poNumber a == poNumber b)

{- | The file of each page, in order (golem-driver ADR 0014): the file of
the unit of its first line; a page without lines has the file of the page
before it, and the first chapter's file when it is the first page.
-}
pageFiles :: PdfInput -> PdfLayout -> [FileId]
pageFiles inp layout = pageFilesOf inp (plLineFiles layout) (plPages layout)

-- | 'pageFiles' of pages, from the file of the unit of each first line.
pageFilesOf :: PdfInput -> Map Int FileId -> [PageOutAt Sp] -> [FileId]
pageFilesOf inp lineFiles pages = drop 1 (scanl next firstFile (pagesOf pages))
  where
    firstFile = maybe (FileId 0) fst (listToMaybe (projectChapters (piProject inp)))
    -- through the columns of the page in order (docs/adr ADR 0018)
    firstLine ps = listToMaybe [lid | p <- ps, (_, s) <- poSlots p, lid <- case s of SLine l -> [l]; SHeading l _ -> [l]; SCode l _ _ -> [l]; _ -> []]
    next prev p = fromMaybe prev (firstLine p >>= \lid -> snd <$> Map.lookupLE lid lineFiles)

{- | Where each page starts in the source, in order (docs/adr ADR 0195):
the first character of its first line (through the columns of the page
in order, as 'pageFiles'), as a file and a byte offset. Characters the
source does not have (the number of a heading, a list marker) are
skipped; without a character of the source inside the block of the line
(a table of contents entry, the cells of a table read from a file), the
start of the block. A page that starts with the first part of a code
block starts at the block; one that starts with a later part, at the
first character of its first row (docs/adr/0218). A page without lines
has none.
-}
pageStarts :: PdfLayout -> [Maybe (FileId, Int)]
pageStarts layout = map start (pagesOf (plPages layout))
  where
    start ps = listToMaybe [lid | p <- ps, (_, s) <- poSlots p, lid <- case s of { SLine l -> [l]; SHeading l _ -> [l]; SCode l _ _ -> [l]; _ -> [] }] >>= lineStart
    -- the first part of a code block: the caption and the file name come before its lines (docs/adr/0218)
    firstCodePart lid = maybe False ((== lid) . ciFirst) (Map.lookup lid (plCodes layout))
    lineStart lid =
      let block = snd <$> Map.lookupLE lid (plLineSpans layout)
          sets = maybe (maybe [] pure (Map.lookup lid (plLines layout))) (map snd) (Map.lookup lid (plTableLines layout))
          -- a block of no length (a heading) holds whatever of its file its line shows
          inside b c = spanFile (snd (bcSource c)) == spanFile b && bcAt c >= 0 && (spanLength b == 0 || (spanStart b <= bcAt c && bcAt c <= spanEnd b))
       in case block of
            Just b | firstCodePart lid -> Just (spanFile b, spanStart b)
            Just b -> case [bcAt c | sl <- sets, Box _ c <- lineItems (slLine sl), inside b c] of
              off : _ -> Just (spanFile b, off)
              [] -> Just (spanFile b, spanStart b)
            Nothing -> Nothing

{- | The master page of each page, in order: the one its file names in the
manifest, otherwise @body@, otherwise the first by name.
-}
pageMasters :: PdfInput -> PageGeometry -> PdfLayout -> [Maybe MasterGeometry]
pageMasters inp geom layout = map (fmap snd) (pageMasterNames inp geom layout)

-- | 'pageMasters' with the name of each master page (docs/adr/0213).
pageMasterNames :: PdfInput -> PageGeometry -> PdfLayout -> [Maybe (Text, MasterGeometry)]
pageMasterNames inp geom layout = masterNamesOf inp geom (pageFiles inp layout)

-- | 'pageMasterNames' of the files of the pages.
masterNamesOf :: PdfInput -> PageGeometry -> [FileId] -> [Maybe (Text, MasterGeometry)]
masterNamesOf inp geom = map masterOf
  where
    ms = pgMasters geom
    named n = (n,) <$> Map.lookup n ms
    masterOf fid =
      (Map.lookup fid (piMasters inp) >>= named)
        <|> named "body"
        <|> Map.lookupMin ms

{- | The lines of the running head drawn on each page, by page number
(golem-driver ADR 0014, 0022). None on blank pages, on pages where a
recto heading starts, and on pages whose master page has no running head.
-}
runningHeads :: PdfInput -> PageGeometry -> PdfLayout -> Map Int [Text]
runningHeads inp geom layout =
  let pages = [p | (p : _) <- pagesOf (plPages layout)]
      infoOf lid = Map.lookup lid (plHeadingSpans layout) >>= (`Map.lookup` bookHeadings (piBook inp))
      started = headingsOnPages infoOf (plPages layout)
      startedOn p = Map.findWithDefault [] (poNumber p) started
      starts = scanl (foldl' activeAfter) Map.empty (map startedOn pages)
      meta = runningMetadata (manifestMetadata (projectManifest (piProject inp)))
      projectVars = piProjectVars inp
      recto h = maybe False hsRectoBreak (Map.lookup (hiLevel h) (stHeadings (piStyle inp)))
      one p st m fid
        | poBlank p || any recto (startedOn p) = []
        | otherwise = case m >>= mgRunningHead of
            Nothing -> []
            Just (co, ce, _, _) ->
              runningHeadLinesWith (\h -> Map.lookup (hiFile h, Just (hiLevel h)) (bookTitleSeparators (piBook inp))) meta projectVars (Map.findWithDefault Map.empty fid (piRunningVars inp)) (if odd (poNumber p) then co else ce) st (startedOn p)
   in Map.fromList [(poNumber p, one p st m fid) | (p, st, m, fid) <- zip4 pages starts (pageMasters inp geom layout) (pageFiles inp layout)]

{- | G07051 (golem-driver ADR 0022): a line of a running head wider than the
type area of its page, once for each text, at the top of style.toml. The
line is drawn as it is, out into the margin.
-}
runningHeadNotices :: PdfInput -> PageGeometry -> LoadedFonts -> PdfLayout -> [Diagnostic]
runningHeadNotices inp geom fonts layout =
  [ diagnostic "G07051" Warning (mkSpan (piStyleFile inp) 0 0) ("柱の行が版面の幅を超えています（" <> T.pack (show n) <> " ページ）: " <> t)
  | (n, t) <- sortOn id [(n, t) | (t, n) <- Map.toList (Map.fromListWith min wide)]
  ]
  where
    masters = Map.fromList [(poNumber p, m) | (p : _, Just m) <- zip (pagesOf (plPages layout)) (pageMasters inp geom layout)]
    wide =
      [ (t, n)
      | (n, ls) <- Map.toList (runningHeads inp geom layout),
        let look = masterLook (piStyle inp) (pgFontSize geom) (Map.lookup n masters >>= mgHeadStyle),
        t <- ls,
        lookWidth fonts look t > rectW (typeAreaFor geom n)
      ]

{- | The look of a running head or a folio (docs/adr/0364): the character
style the component of the master names applied over the body role at the
size of the grid, as 'restyle' applies one inside a paragraph; the body
role at that size without one. A size in zw is measured against the size
of the grid.
-}
masterLook :: Style -> Sp -> Maybe Text -> Look
masterLook style grid name =
  let base = plainLook (bodyRole style) grid
   in maybe base (\n -> restyle style base (CharStyle (mkSpan (FileId 0) 0 0) n [])) name

-- | The width of a text set in a role at a size, unjustified.
plainWidth :: LoadedFonts -> Text -> Sp -> Text -> Sp
plainWidth fonts role size txt = sum [L.zwToSp size (shAdvance g) | g <- lfShape fonts (Shaping role False [] False) txt]

-- | Whether a character is Latin in a look: of the language of its span (docs/adr ADR 0187).
isLatin :: Look -> Char -> Bool
isLatin look = (== Western) . lookClass look

{- the runs of a text in a look: its role and whether it is a Latin
run; split into Latin and other runs where the two sides differ in
role or in synthetic bold and slant (golem-driver ADR 0004, docs/adr ADR 0005);
a combining character stays with the character before it, variation
selectors among them (golem-pdf ADR 0006, golem-driver ADR 0036) -}
runsOf :: Look -> Text -> [(Text, Text, Bool)]
runsOf look txt
  | lkFace look == lkLatinFace look && lkSynthetic look == lkLatinSynthetic look && not (synBold (lkSynthetic look) || synBold (lkLatinSynthetic look)) = [(lkFace look, txt, False)]
  | otherwise = [(if latin then lkLatinFace look else lkFace look, r, latin) | r <- T.groupBy (\a b -> isExtending b || isLatin look a == isLatin look b) txt, not (T.null r), let latin = isLatin look (T.head r)]

{- | The width of a horizontal text in a look, unjustified, as
'Golem.Typeset.Draw' draws it: each run in the role of its side
('runsOf'), shaped with the features of the look, and the tracking of
the look after each character (docs/adr/0020, docs/adr/0364).
-}
lookWidth :: LoadedFonts -> Look -> Text -> Sp
lookWidth fonts look txt =
  sum [L.zwToSp size (shAdvance g) | (role, r, _) <- runsOf look txt, c <- take 1 (T.unpack r), g <- lfShape fonts ((shapingOf (lfRoleFeatures fonts) False look c) {shRole = role, shVertical = False}) r]
    + Sp (round (fromIntegral (T.length txt) * unSp tr % 1000))
  where
    size = lkSize look
    tr = fromIntegral (lkTracking look) * size

{- | Whether a page gets its folio (golem-driver ADR 0021): not a blank
page, and its master page has a folio. 'masterMarks' and 'hiddenFolios'
share it.
-}
drawsFolio :: Bool -> Maybe MasterGeometry -> Bool
drawsFolio blank master = not blank && isJust (master >>= mgFolio)

{- | The hidden folios of each page by its number (golem-driver ADR 0021):
each digit of the page number and the centre of its advance box, in the
trimmed page. Only with crop marks and when enabled; on the pages without
a folio, or on every page. The digits run from top to bottom one size
apart, on the line @gutter@ from the trim line of the gutter, and the
column is centred on the height of the page.
-}
hiddenFolios :: PdfInput -> PageGeometry -> PdfLayout -> Map Int [(Char, (Sp, Sp))]
hiddenFolios inp geom layout = case (piMarks inp, pgHiddenFolio geom) of
  (Just _, Just hg) ->
    Map.fromList
      [ (n, column hg n)
      | (p : _, m) <- zip (pagesOf (plPages layout)) (pageMasters inp geom layout),
        let n = poNumber p,
        hgAll hg || not (drawsFolio (poBlank p) m)
      ]
  _ -> Map.empty
  where
    (pw, ph) = pgPageSize geom
    column hg n =
      let size = hgSize hg
          digits = show n
          k = length digits
          x = case gutterSide (pgBindingRight geom) n of
            SideLeft -> hgGutter hg
            SideRight -> pw - hgGutter hg
       in [(c, (x, Sp (unSp ph `div` 2 + (fromIntegral (k - 1 - 2 * i) * unSp size) `div` 2))) | (i, c) <- zip [0 ..] digits]

-- | How the last line of a table of contents entry ends (golem-driver ADR 0009).
data TocGeometry = TocGeometry
  { -- | the measure of the column
    tgMeasure :: !Sp,
    -- | W: the width of the page number 999
    tgReserve :: !Sp,
    -- | g: the space on either side of the leader
    tgGap :: !Sp,
    -- | u: the advance of one leader character
    tgLeaderUnit :: !Sp,
    -- | [toc] leader is "dots"
    tgLeaders :: !Bool,
    -- | the look the leader is set in
    tgLook :: !Look
  }
  deriving stock (Show)

-- | The leader and the page number of the last line of an entry.
data TocPage = TocPage
  { -- | from the line start to the start of the leader
    tpLeaderStart :: !Sp,
    -- | the leader characters (possibly none)
    tpLeader :: !Line,
    -- | from the line start to the start of the page number
    tpNumberStart :: !Sp,
    -- | the page number as set
    tpNumber :: !Line
  }
  deriving stock (Show)

{- | Places the leader and the page number on the last line of an entry
whose title ends at @e@ from the line start (indent included). The page
number ends at the measure; the leader ends a gap before the reserve (or
before a wider number) so that leaders line up; integer sp only.
-}
tocPage :: TocGeometry -> Sp -> Line -> TocPage
tocPage tg e number =
  let w = sum [bw | Box bw _ <- lineItems number]
      g = tgGap tg
      u = tgLeaderUnit tg
      ns0 = tgMeasure tg - w
      le = tgMeasure tg - max (tgReserve tg) w - g
      k0 = if tgLeaders tg && u > 0 then max 0 (unSp (le - (e + g)) `div` unSp u) else 0
      (ns, k) = if ns0 < e + g then (e + g, 0) else (ns0, k0)
      leader = Line [Box u (BoxContent "…" False 0 0 (fromEnum KindText) (tgLook tg) 0 0 [] 0 0 noBoxSource Nothing noLeaf 0 Nothing) | _ <- [1 .. k]] 0 (fromInteger k * u) 0 (0, 0) 0 (0, 0) Nothing AdjustUniform
   in TocPage (le - fromInteger k * u) leader ns number

-- | The measure of a column of the page.
columnMeasure :: PageGeometry -> Sp
columnMeasure geom = case pgColumns geom of
  (c : _) -> if pgVertical geom then rectH c else rectW c
  [] -> 0

{- | A page number of the table of contents (golem-driver ADR 0009): the
page label as 'pageLabelInlines' writes it (docs/adr/0260) in the
character style toc-page-number (docs/adr/0264), its boxes as a line.
-}
pageNumberLine :: ComposeEnv -> PageLabel -> Line
pageNumberLine env l =
  let sp0 = mkSpan (FileId 0) 0 0
      boxes = [b | b@Box {} <- fst (composeInlines env [CharStyle sp0 "toc-page-number" (pageLabelInlines sp0 l)])]
      w = sum (map itemWidth boxes)
   in Line boxes 0 w 0 (0, 0) 0 (0, 0) Nothing AdjustUniform

{- | How the last line of an entry of the table of contents ends
(docs/adr/0264): the reserve W of every level, the gap, and the leader in
the look of the paragraph style of the entry.
-}
entryGeometry :: Sp -> FlowEnv -> Style -> Unit -> TocGeometry
entryGeometry fs fe style u =
  let env = unitEnv fe u
      reserve = case uKind u of
        UTocEntry _ _ _ r -> r - 2 * fs
        _ -> 0
      sp0 = mkSpan (FileId 0) 0 0
      leaderUnit = sum [w | Box w _ <- fst (composeInlines env [Text sp0 "…"])]
   in TocGeometry (feMeasure fe) reserve (Sp (unSp fs `div` 2)) leaderUnit (stTocLeader style == "dots") (ceLook env)

{- | G07117 (docs/adr/0264): for each level of the entries of the table of
contents, once, when the length of a line of its entries (the measure
less the larger indent of a line, the end indent and R) is less than a
character of its style; at the table of toc-<l> in style.toml when it is
written there, at the @toc otherwise.
-}
tocLineErrors :: FlowEnv -> [(Int, Unit)] -> [Diagnostic]
tocLineErrors fe units =
  [ diagnostic "G07117" Error (fromMaybe (uSpan u) (written l)) ("目次の階層 " <> T.pack (show l) <> " の項目の行の長さが、段落スタイル " <> tocStyleName l <> " の一字に足りません。indent、first-line-indent、end-indent を狭めてください")
  | (l, u) <- Map.toList (Map.fromListWith (\_ first' -> first') [(l, u) | (_, u) <- units, UTocEntry l _ _ _ <- [uKind u]]),
    UTocEntry _ _ (Indent st f e _) r <- [uKind u],
    feMeasure fe - max (st + f) st - e - r < lkSize (uLook u)
  ]
  where
    inp = feInput fe
    written l = manifestValueSpan (piStyleFile inp) (piStyleText inp) ["paragraph-styles", tocStyleName l]

{- | W (docs/adr/0264): the width of the page number 999 in the look of the
entries of each level from 1 to the depth, with toc-page-number on it, the
widest; in the style of the document of the table of contents.
-}
tocReserveWidth :: FlowEnv -> Style -> Int -> Sp
tocReserveWidth fe style depth =
  let sp0 = mkSpan (FileId 0) 0 0
      widthAt l =
        let (lk, _) = paraLook style (feGeom fe) (Just (tocStyleName l))
            env = (withDocStyle style (lookEnv fe lk)) {ceAkiSet = akiSetOf style (Just (tocStyleName l))}
         in sum [w | Box w _ <- fst (composeInlines env [CharStyle sp0 "toc-page-number" [Number sp0 999 Nothing]])]
   in maximum (0 : map widthAt [1 .. max 1 (min 6 depth)])

-- | W and u, measured once in the body role at the type size.
tocMetrics :: ComposeEnv -> (Sp, Sp)
tocMetrics env =
  let width is = sum [w | Box w _ <- fst (composeInlines env is)]
      sp0 = mkSpan (FileId 0) 0 0
   in (width [Number sp0 999 Nothing], width [Text sp0 "…"])

{- | The text of the lines of each page, as far as the layout goes
(golem-driver ADR 0007): the boxes of a line joined.
-}
layoutPages :: FontProvider -> PdfInput -> IO (Either [Diagnostic] [[Text]])
layoutPages provider inp0 = case checkedGeometry inp of
  Left ds -> pure (Left ds)
  Right geom -> do
    lf <- loadFonts provider (piFiles inp) (piStyleFile inp) (piStyle inp) (Map.elems (piLocalStyles inp))
    case lf of
      Left ds -> pure (Left ds)
      Right fonts -> fmap texts <$> layoutPdf inp geom fonts
  where
    inp = codeInput inp0
    texts layout =
      [ [ case Map.lookup lid (plTableLines layout) of
            Just cells -> T.intercalate " " (map (setLineText . snd) cells)
            Nothing -> setLineText sl
            <> maybe "" (\tp -> boxesText (tpLeader tp) <> boxesText (tpNumber tp)) (Map.lookup lid (plTocPages layout))
        | (_, s) <- poSlots p,
          lid <- case s of
            SLine l -> [l]
            SHeading l m -> [l .. l + m - 1]
            SCode l k _ -> [l .. l + k - 1]
            _ -> [],
          Just sl <- [Map.lookup lid (plLines layout)]
        ]
      | p <- plPages layout
      ]
    setLineText = boxesText . slLine
    boxesText l = T.concat [bcText c | Box _ c <- lineItems l]

{- | A line of the index (docs/adr/0265): the heading of a section, or an
entry.
-}
data IndexLine = IndexHeadingLine ![Inline] | IndexEntryLine ![Inline]
  deriving stock (Eq, Show)

-- | The inlines of a line of the index.
indexLineInlines :: IndexLine -> [Inline]
indexLineInlines = \case
  IndexHeadingLine is -> is
  IndexEntryLine is -> is

{- | The lines of the index (golem-driver ADR 0007, docs/adr/0265): with
headings, the heading of each section in the built-in character style
strong before its entries; a main entry and its pages, sub-entries
indented by a full-width space below their main entry (which is shown
once, without pages when it has no mark of its own); the references of an
entry after its pages. Pages are page labels written by 'pageLabelInlines'
(docs/adr/0260), as 'indexPageRuns' puts them; a mark without a page is
left out. The sections come sorted from S1.
-}
indexLines :: Bool -> Bool -> (SrcSpan -> Maybe PageLabel) -> [IndexSection] -> [IndexLine]
indexLines vertical headings pageOf = go Nothing
  where
    sp0 = mkSpan (FileId 0) 0 0
    txt = Text sp0
    go _ [] = []
    go prevMain (s : ss) =
      let (prevMain', entries) = mapAccumL entryLines prevMain (isGroups s)
       in [IndexHeadingLine [CharStyle sp0 "strong" [txt (isHeading s)]] | headings] <> concat entries <> go prevMain' ss
    entryLines prevMain g = case (igTerms g, igReadings g) of
      ([t], [r]) -> (Just (t, r), [IndexEntryLine (entry [] t g)])
      ([t, sub], [r, _]) -> (Just (t, r), [IndexEntryLine [txt t] | prevMain /= Just (t, r)] <> [IndexEntryLine (entry [txt "　"] sub g)])
      _ -> (prevMain, [])
    entry prefix term g =
      let runs = indexPageRuns (mapMaybe ends (igLocators g))
          refs = indexReferences (not (null (igLocators g))) (igSee g)
          -- the marks of the entry with their pages, in the order of its locators; the ends of ranges marked
          marks = concat [[(l, m, isEnd) | Just l <- [pageOf m]] | (m, isEnd) <- concatMap markEnds (igLocators g)]
          firstOn p onlyEnds = listToMaybe [m | (l, m, isEnd) <- marks, plIndex l == plIndex p, isEnd || not onlyEnds]
          -- a page number a link to the first mark of the entry on its page; the end of a range to an end mark there (docs/adr/0267)
          linked target l = case target of
            Just m -> [Resolved m RefPage "" (pageLabelInlines sp0 l)]
            Nothing -> pageLabelInlines sp0 l
          run (a, b)
            | plIndex a == plIndex b = linked (firstOn a False) a
            | otherwise = linked (firstOn a False) a <> [txt (if vertical then "〜" else "\x2013")] <> linked (firstOn b True <|> firstOn b False) b
       in prefix
            <> [txt term]
            <> (if null runs then [] else txt "　" : intercalate [txt (if vertical then "、" else ", ")] (map run runs))
            <> [txt refs | not (T.null refs)]
    markEnds = \case
      AtMark (_, m) -> [(m, False)]
      Between (_, a) (_, b) -> [(a, False), (b, True)]
    ends = \case
      AtMark (_, m) -> (\l -> (l, l)) <$> pageOf m
      Between (_, a) (_, b) -> case (pageOf a, pageOf b) of
        (Just la, Just lb) -> Just (la, lb)
        (Just la, Nothing) -> Just (la, la)
        (Nothing, Just lb) -> Just (lb, lb)
        (Nothing, Nothing) -> Nothing

{- | The pages of the locators of an entry (docs/adr/0265), each a page or
the pages from its first to its last: the pages they cover cut into the
longest runs of pages next to each other, a page after the first page of a
section in a run of its own, by their places in the book. A run of two
pages or more is a range; one of one page is that page. A range whose end
is before its begin, or in another section (G07118, G07119), is its two
pages.
-}
indexPageRuns :: [(PageLabel, PageLabel)] -> [(PageLabel, PageLabel)]
indexPageRuns locs = merge (sortOn (bimap plIndex plIndex) (concatMap split locs))
  where
    split (a, b)
      | plIndex b < plIndex a || plSectionFirst a /= plSectionFirst b = [(a, a), (b, b)]
      | otherwise = [(a, b)]
    merge = \case
      (a, b) : (c, d) : rest
        | plIndex c <= plIndex b || (plIndex c == plIndex b + 1 && plSectionFirst c == plSectionFirst b) ->
            merge ((a, if plIndex d > plIndex b then d else b) : rest)
      x : rest -> x : merge rest
      [] -> []

{- | G07118 and G07119 of the ranges of the index on the settled pages
(docs/adr/0265), at their begin marks: the end on a page before the
begin, and the two ends in two sections.
-}
indexRangeDiagnostics :: Book -> (SrcSpan -> Maybe PageLabel) -> [Diagnostic]
indexRangeDiagnostics book pageOf =
  concat
    [ range (T.intercalate "/" (igTerms g)) a b
    | (_, sections) <- bookIndexes book,
      g <- concatMap isGroups sections,
      Between (_, a) (_, b) <- igLocators g
    ]
  where
    range name a b = case (pageOf a, pageOf b) of
      (Just la, Just lb)
        | plIndex lb < plIndex la -> [diagnostic "G07118" Error a ("索引の範囲の終わりのページが、始めのページより前にあります: " <> name)]
        | plSectionFirst la /= plSectionFirst lb -> [diagnostic "G07119" Error a ("索引の範囲の始めと終わりが、ノンブルの別のセクションにあります: " <> name)]
      _ -> []

{- | Page labels in the order of the pages, each page once (docs/adr/0260):
by their places, not their numbers, for iii and 3 have one number.
-}
labelsInOrder :: [PageLabel] -> [PageLabel]
labelsInOrder ls = Map.elems (Map.fromList [(plIndex l, l) | l <- ls])

{- | The lines of the list of a channel of a plugin (golem-doc ADR 0007):
the body of each entry, and with locators an ideographic space and its
pages as in the index.
-}
channelLines :: Bool -> (SrcSpan -> Maybe PageLabel) -> Bool -> [ChannelEntry] -> [[Inline]]
channelLines vertical pageOf locators = map line
  where
    sp0 = mkSpan (FileId 0) 0 0
    line e =
      let ps = labelsInOrder [l | (_, sp) <- ceLocations e, Just l <- [pageOf sp]]
       in ceBody e <> (if not locators || null ps then [] else Text sp0 "　" : intercalate [Text sp0 (if vertical then "、" else ", ")] (map (pageLabelInlines sp0) ps))

{- | The lines of the bibliography: @[n] @ and the entry, or the key when
it has none; a URL is in the character style url (golem-doc ADR 0005),
and a link when it passes the checks of [link] (docs/adr ADR 0182).
-}
bibliographyLines :: Map Text [EntryPart] -> [(Text, Int)] -> [[Inline]]
bibliographyLines bib cites =
  -- the number its own inline: the label of the entry (docs/adr ADR 0183)
  [ Text sp0 ("[" <> T.pack (show n) <> "] ") : merged (fromMaybe [EntryText k] (Map.lookup k bib))
  | (k, n) <- cites
  ]
  where
    sp0 = mkSpan (FileId 0) 0 0
    merged = \case
      EntryText a : EntryText b : rest -> merged (EntryText (a <> b) : rest)
      EntryText a : rest -> Text sp0 a : merged rest
      EntryUrl u : rest
        | Nothing <- checkUrl u -> Link sp0 u [CharStyle sp0 "url" [Text sp0 u]] : merged rest
        | otherwise -> CharStyle sp0 "url" [Text sp0 u] : merged rest
      [] -> []

{- | G07123 and G07124 (docs/adr ADR 0272): a notice for each soft hyphen
of the book that is not a break, at the soft hyphen ([shy] where it is
written so), in the order of the documents and their blocks. A soft
hyphen without a letter of its element on either side is G07123, one in
text that does not break, or next to it with a letter on either side,
G07124 (docs/adr ADR 0297); one before the first letter of its
element is neither. The lines Golem makes are not read: what they show is
written in the source, and reported there.
-}
softHyphenNotices :: PdfInput -> [Diagnostic]
softHyphenNotices inp =
  [ notice code (siteSpan sp off) msg
  | Document fid bs <- bookDocs (piBook inp),
    let env = (defaultComposeEnv 0) {ceRestyle = restyle (docStyle inp fid), ceSourceAt = sourceAt sources},
    b <- bs,
    is <- blockInlineLists b,
    (sp, off, note) <- softHyphenSites env is,
    let (code, msg) = case note of
          ShyNotBetweenLetters -> ("G07123", "ソフトハイフンの前か後ろが語の字でないので、分割の候補にしません")
          ShyInUnbreakable -> ("G07124", "改行しない文字（コード、URL、リンク、改行しない範囲）の中か隣のソフトハイフンなので、分割の候補にしません")
  ]
  where
    sources = Map.map (TE.encodeUtf8 . sfText) (projectSources (piProject inp))
    -- the soft hyphen in the source: U+00AD, or [shy]
    siteSpan sp off
      | off < 0 = sp
      | otherwise =
          let len = case Map.lookup (spanFile sp) sources of
                Just src | "[shy]" `BS.isPrefixOf` BS.drop off src -> 5
                _ -> 2
           in mkSpan (spanFile sp) off (off + len)

{- | The role, size and line pitch of sidenotes: the role and size of the
paragraph style sidenote (golem-driver ADR 0011), the body pitch scaled
to the size.
-}
sidenoteMetrics :: Style -> PageGeometry -> (Text, Sp, Sp)
sidenoteMetrics style geom =
  let (role, size) = paraFace style geom "sidenote"
   in (role, size, Sp (unSp (pgLinePitch geom) * unSp size `div` unSp (pgFontSize geom)))

{- | Sidenotes the PDF cannot place (golem-driver ADR 0006): in vertical
writing (G07032), without a sidenote column (G07034), or in a footnote or
a caption (G07035).
-}
sidenoteDiagnostics :: PageGeometry -> Book -> [Diagnostic]
sidenoteDiagnostics geom book
  | pgVertical geom = concatMap (verticalSidenotes (defaultComposeEnv 0) {ceVertical = True}) inlineLists
  | otherwise = case pgSidenotes geom of
      Nothing -> [diagnostic "G07034" Error sp "傍注の領域（style.toml の [sidenotes]）のない版面では傍注を使えません" | (sp, _) <- sites]
      Just _ -> [diagnostic "G07035" Error sp "PDF では、脚注の本文と図版のキャプションの中に傍注を置けません" | (sp, False) <- sites]
  where
    blocks = concat [bs | Document _ bs <- bookDocs book]
    -- every list of inlines of the book, captions included
    inlineLists = concatMap blockInlineLists blocks
    -- each sidenote, and whether it is in the text flow
    sites = concatMap siteBlock blocks
    siteBlock b@(Block _ _ _ body) = case body of
      FigureBlock fig -> [(sp, False) | is <- concatMap blockInlineLists (figCaption fig), (sp, _) <- concatMap (inlineSites True) is]
      _ -> [x | is <- blockInlineLists b, x <- concatMap (inlineSites True) is]
    inlineSites flow = \case
      Sidenote sp _ _ nb -> (sp, flow) : concatMap (inlineSites flow) (concat (noteParagraphs nb))
      Note _ _ _ nb -> concatMap (inlineSites False) (concat (noteParagraphs nb))
      Endnote _ _ _ nb -> concatMap (inlineSites False) (concat (noteParagraphs nb))
      Kenten _ _ xs -> concatMap (inlineSites flow) xs
      Color _ _ xs -> concatMap (inlineSites flow) xs
      CharStyle _ _ xs -> concatMap (inlineSites flow) xs
      Resolved _ _ _ xs -> concatMap (inlineSites flow) xs
      _ -> []

-- | The block of each label, where G07021 points (golem-driver ADR 0016).
labelSpans :: Book -> Map Text SrcSpan
labelSpans book = Map.fromListWith (\_ old -> old) (concatMap site (concat [bs | Document _ bs <- bookDocs book]))
  where
    site (Block sp l _ body) =
      [(name, sp) | Just name <- [l]] <> case body of
        BulletList items -> concatMap (concatMap site . itemBlocks) items
        OrderedList items -> concatMap (concatMap site . itemBlocks) items
        DefList gs -> concatMap (concatMap (concatMap site) . dgDefs) gs
        FigureBlock fig -> concatMap site (figCaption fig)
        _ -> []

{- | Numbers of notes that the notation of [notes] mark-format cannot
write (docs/adr/0177): G07102 at the note, whatever the target. Numbered
per page, the numbers of the book are those of HTML, EPUB and plain text
alone, and the PDF checks the numbers of its pages once it knows them
(docs/adr/0383): the first argument says whether the targets are the PDF
alone, whose book numbers are then not checked.
-}
noteNumberDiagnostics :: Bool -> Style -> Book -> [Diagnostic]
noteNumberDiagnostics pdfOnly style book =
  [ diagnostic "G07102" Error sp ("注の番号 " <> T.pack (show n) <> " は、[notes] の mark-format " <> renderMarkFormat fmt <> " で表せません")
  | -- numbered per page, the numbers of the pages are checked once they are known (docs/adr/0383)
    not pdfOnly || stNotesNumbering style /= NumberPerPage,
    d <- bookDocs book,
    (sp, n, _) <- documentNotes d,
    null (writeNumber (mfNotation fmt) (toInteger n))
  ]
  where
    fmt = stNotesMarkFormat style

{- | G07102 for notes numbered per page (docs/adr/0383): a number of a page
that the notation of [notes] mark-format cannot write, at the note.
-}
pageNoteNumberDiagnostics :: Style -> Book -> Map (NoteChannel, Int) Int -> [Diagnostic]
pageNoteNumberDiagnostics style book numbers =
  [ diagnostic "G07102" Error sp ("注の番号 " <> T.pack (show k) <> " は、[notes] の mark-format " <> renderMarkFormat fmt <> " で表せません")
  | stNotesNumbering style == NumberPerPage,
    d <- bookDocs book,
    (sp, n, _) <- documentNotes d,
    Just k <- [Map.lookup (ChannelNote, n) numbers],
    null (writeNumber (mfNotation fmt) (toInteger k))
  ]
  where
    fmt = stNotesMarkFormat style

{- | Places the sidenotes of a page in its sidenote column (golem-driver
ADR 0006): each wants the top of the line of its marker; they keep their
order, half a body pitch apart. Takes the sidenote pitch and size of a
sidenote by its span (docs/adr ADR 0014).
-}
placePageSidenotes :: PageGeometry -> (SrcSpan -> (Sp, Sp)) -> Map Int SetLine -> PageOutAt Sp -> Either [Diagnostic] [PlacedSidenote]
placePageSidenotes geom metricsOf lineMap p =
  let bodyPitch = pgLinePitch geom
      lineIds = \case
        SLine lid -> [lid]
        SHeading lid m -> [lid .. lid + m - 1]
        _ -> []
      notes =
        [ (sp, slot, ls)
        | (slot, s) <- sortOn fst (poSlots p),
          lid <- lineIds s,
          Just sl <- [Map.lookup lid lineMap],
          (sp, ls) <- slSidenotes sl
        ]
      height sp ls = let (pitch, size) = metricsOf sp in fromIntegral (max 1 (partRows ls) - 1) * pitch + size
      columnH = maybe 0 rectH (sidenoteAreaFor geom (poNumber p))
      at i = case drop i notes of
        ((sp, _, _) : _) -> sp
        [] -> mkSpan (FileId 0) 0 0
   in if null notes
        then Right []
        else case placeSidenotes columnH (Sp (unSp bodyPitch `div` 2)) [(want, height sp ls) | (sp, want, ls) <- notes] of
          Right tops -> Right [PlacedSidenote sp t ls | ((sp, _, ls), t) <- zip notes tops]
          Left (TooTall i) -> Left [diagnostic "G07033" Error (at i) "傍注が傍注の領域より高く、収まりません"]
          Left (DoesNotFit i) -> Left [diagnostic "G07033" Error (at i) "このページの傍注が傍注の領域に収まりません"]

-- | The marks of a locator of the index: a mark, or the two ends of a range (docs/adr/0265).
locatorMarks :: IndexLocator -> [(FileId, SrcSpan)]
locatorMarks = \case
  AtMark m -> [m]
  Between a b -> [a, b]

{- | A text frame asked for on a page (root ADR 0438): its name, where it
was asked for, whether a master page asks, the style of its paragraphs
and its paragraphs.
-}
data FrameAsk = FrameAsk
  { faName :: !Text,
    faSpan :: !SrcSpan,
    faMaster :: !Bool,
    faStyle :: !Style,
    faParagraphs :: ![[Inline]]
  }

{- | The text frames of the settled pages (root ADR 0438), by page number,
and their errors. A master page puts its frames on each of its pages,
each holding the text of its [frames.<name>]. A @frame puts its frame on
the page of the last line of the nearest block before it in its file that
has lines; without one, on the page of the first line of the nearest
block after it; without either, on the first page of its file. A page
holds the frames of its master page first, then those of the @frame in
the order of the book.

A name a page already holds is G07140, and the frame is not put again. A
@frame of a frame of wrap = "around" is G07137. Content that does not fit
the shape of its frame ('flowInBox') is G07139, and the frame is left
empty; that of a master page is reported once for each frame.
-}
layoutFrames :: PdfInput -> PageGeometry -> PdfLayout -> ([Diagnostic], Map Int [PlacedFrame])
layoutFrames inp geom layout =
  let style = piStyle inp
      defs = stFrames style
      firsts = [p | (p : _) <- pagesOf (plPages layout)]
      numbers = map poNumber firsts
      files = pageFiles inp layout
      tableSpan name = fromMaybe (mkSpan (piStyleFile inp) 0 0) (manifestValueSpan (piStyleFile inp) (piStyleText inp) ["frames", name])
      masterText name sp = [[Text sp t] | Just f <- [Map.lookup name defs], Just t <- [frText f], not (T.null t)]
      masterAsks =
        [ (n, FrameAsk name sp True style (masterText name sp))
        | (n, Just (m, _)) <- zip numbers (pageMasterNames inp geom layout),
          Just md <- [Map.lookup m (stMasters style)],
          name <- mdFrames md,
          let sp = tableSpan name
        ]
      blocks = [(fid, sp, name, bs) | Document fid docBlocks <- bookDocs (piBook inp), Block sp _ _ (FrameBlock name bs) <- frameBlocksIn docBlocks]
      -- the lines of the pages: each line on the page it is first drawn on, with the block of its unit
      linePages = Map.fromListWith min [(lid, poNumber p) | p <- plPages layout, (_, s) <- poSlots p, lid <- linesOf s]
      lineBlocks = [(lid, n, b) | (lid, n) <- Map.toList linePages, Just (_, b) <- [Map.lookupLE lid (plLineSpans layout)]]
      pageOf fid sp =
        let inFile = [(lid, n, b) | (lid, n, b) <- lineBlocks, spanFile b == fid]
            before = [(lid, n) | (lid, n, b) <- inFile, spanStart b < spanStart sp]
            after = [(lid, n) | (lid, n, b) <- inFile, spanStart b > spanStart sp]
         in fmap snd (listToMaybe (sortOn (Down . fst) before))
              <|> fmap snd (listToMaybe (sortOn fst after))
              <|> listToMaybe [n | (n, f) <- zip numbers files, f == fid]
              <|> listToMaybe numbers
      blockAsks = [(n, FrameAsk name sp False (docStyle inp fid) [is | Block _ _ _ (Paragraph _ is) <- bs]) | (fid, sp, name, bs) <- blocks, Just n <- [pageOf fid sp]]
      aroundErrors =
        [ diagnostic "G07137" Error sp ("@frame のフレームには wrap = \"around\" を使えません: " <> name)
        | (_, sp, name, _) <- blocks,
          Just f <- [Map.lookup name defs],
          frWrap f == FrameWrapAround
        ]
      asked = Map.fromListWith (flip (<>)) [(n, [a]) | (n, a) <- masterAsks <> blockAsks]
      -- the frames of a page, a name once
      onPage n as =
        let go _ [] = ([], [])
            go seen (a : rest)
              | faName a `elem` seen = first (diagnostic "G07140" Error (faSpan a) ("一つのページに同じ名前のフレームが二つ置かれます: " <> faName a) :) (go seen rest)
              | otherwise = second (a :) (go (faName a : seen) rest)
            (dups, kept) = go [] as
         in (dups, [(n, a, placeFrame geom (plFlowEnv layout) n a) | a <- kept])
      results = [onPage n as | (n, as) <- Map.toList asked]
      placedAll = concatMap snd results
      overflowOf a = diagnostic "G07139" Error (faSpan a) ("フレームの中身がフレームの形に収まりません: " <> faName a)
      overflows = nubOrdOn diagMessage [overflowOf a | (_, a, Nothing) <- placedAll, faMaster a] <> [overflowOf a | (_, a, Nothing) <- placedAll, not (faMaster a)]
   in ( aroundErrors <> concatMap fst results <> overflows,
        Map.fromListWith (flip (<>)) [(n, [pf]) | (n, _, Just pf) <- placedAll]
      )
  where
    linesOf = \case
      SLine l -> [l]
      SHeading l c -> take c [l ..]
      SCode l c _ -> take c [l ..]
      _ -> []

-- | The text frames among blocks, at any depth, in order (root ADR 0438).
frameBlocksIn :: [Block] -> [Block]
frameBlocksIn = concatMap $ \b -> case blockBody b of
  FrameBlock {} -> [b]
  BulletList items -> frameBlocksIn (concatMap itemBlocks items)
  OrderedList items -> frameBlocksIn (concatMap itemBlocks items)
  DefList gs -> frameBlocksIn (concat (concatMap dgDefs gs))
  _ -> []

{- | A text frame on page n (root ADR 0438), or Nothing when its content
does not fit its shape. Its shape is the rectangle or the path of its
[frames.<name>], the origin at the top of the trimmed page and y going
down; x-from inside and outside mirror it on the pages whose spine is on
the right and on the left. Its paragraphs are set in its paragraph style
(body without one) and writing mode, from the edge its lines start from,
a line pitch of the paragraph style apart ('flowInBox'). A frame without
a shape (an error of style.toml) holds nothing.
-}
placeFrame :: PageGeometry -> FlowEnv -> Int -> FrameAsk -> Maybe PlacedFrame
placeFrame geom fe n a = case Map.lookup (faName a) (stFrames (faStyle a)) >>= \f -> (f,) <$> frameShape f of
  Nothing -> Just empty
  Just (f, shape) ->
    let st = faStyle a
        para = frParagraphStyle f
        (role, size) = paraFace st geom (fromMaybe "body" para)
        vertical = maybe (pgVertical geom) (== "vertical") (frWritingMode f)
        pitch = fromMaybe (pgLinePitch geom) (paraStyle st para >>= resolvedParagraphPitch st)
        path = frameOutline geom st n f shape
        box = textBox (if vertical then Vertical else Horizontal) path
        env = (withDocStyle st (lookEnv fe (styleLook st para role size))) {ceAkiSet = akiSetOf st para, ceSizeSource = paraSizeSource st para, ceVertical = vertical}
        params = adjustedParams st para (feParams fe)
     in case flowInBox params box size pitch (map (fst . composeInlines env) (faParagraphs a)) of
          Left BoxOverflow -> Nothing
          Right lss -> Just empty {pfrVertical = vertical, pfrLines = [(slotRect slot, SetLine l size 0 [] [] Nothing) | ls <- lss, (slot, l) <- ls]}
  where
    empty = PlacedFrame (faName a) (faSpan a) (pgVertical geom) (faMaster a) []

{- | The cuts of the lines of the body under the frames of wrap = "around"
(root ADR 0438), by the unit and the line of the unit: how much of the
start and of the end of the line the frame takes; and the errors. On
each page, each frame of wrap around of its master page shortens, in
each column its bounding rectangle overlaps, the lines whose em box
crosses the rectangle across the lines, by the overlap of the rectangle
and the column along the lines (the part over the margin does not
count): the lines of paragraphs, of headings and beside a wrapped
figure, but not those of tables, which go past the frames (root ADR
0456). The overlap holds the start or the end edge of the column, or it
is G07136 at the frame; a line left shorter than 8 characters of the
size of the grid is G07138 at its block, beside a wrapped figure at its
paragraph once the exclusion of the figure is taken on its side too
(root ADR 0456).
-}
aroundCuts :: PdfInput -> PageGeometry -> Built -> [PageOutAt Sp] -> (Map Int (Map Int (Sp, Sp)), [Diagnostic])
aroundCuts inp geom built pages =
  let framesOf = aroundFramesByPage inp geom built pages
      tableSpan name = fromMaybe (mkSpan (piStyleFile inp) 0 0) (manifestValueSpan (piStyleFile inp) (piStyleText inp) ["frames", name])
      vertical = pgVertical geom
      free = maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle inp) >>= pageGrid)
      firstOf = Map.fromList [(lid, i) | (i, lid) <- Map.toList (bUnitFirsts built)]
      -- the lines of tables go past the frames (root ADR 0456)
      tableLines = Set.fromList (concat [map lbId (h <> concat rs <> c) | FTable {ftHeader = h, ftRows = rs, ftCaption = c} <- bFlow built])
      beside = besideLines built
      -- the em box of a line across the column, from its start edge, by its baseline
      emBox base size = if vertical then (base - Sp (unSp size `div` 2), base + Sp (unSp size `div` 2)) else (base - L.zwToSp size baselineRatio, base + size - L.zwToSp size baselineRatio)
      toBaseline size = if vertical then Sp (unSp size `div` 2) else L.zwToSp size baselineRatio
      across lid pos sl =
        let size = slSize sl
            pitch = Map.findWithDefault (pgLinePitch geom) lid (bLinePitches built)
            base
              | free = pos + faceOffset pitch size + toBaseline size
              | otherwise = pos + sum (take 1 (pgLineGrid geom))
         in emBox base size
      -- the lines of a heading block, each at its place in the block (golem-driver ADR 0003)
      headingAcross lid j pos sl =
        let size = slSize sl
            hb = Map.lookup lid (bHeadings built)
            top = pos + (if free then faceOffset (pgLinePitch geom) (pgFontSize geom) else 0) + maybe 0 hbOffset hb + fromIntegral j * maybe 0 hbPitch hb
         in emBox (top + toBaseline size) size
      slotLines pos = \case
        SLine lid | Set.notMember lid tableLines -> [(lid, across lid pos sl) | Just sl <- [Map.lookup lid (bLines built)]]
        SHeading lid count -> [(lid + j, headingAcross lid j pos sl) | j <- [0 .. count - 1], Just sl <- [Map.lookup (lid + j) (bLines built)]]
        _ -> []
      results =
        [ case cutOf col bounds of
            Nothing -> Left (diagnostic "G07136" Error (tableSpan name) ("回り込むフレームが段の始まりの辺にも終わりの辺にも接していません: " <> name))
            Just cut -> Right [((ui, lid - firstId), lid, cut, col) | (lid, (c0, c1)) <- lineSpans, c0 < bx1 && c1 > bx0, Just (firstId, ui) <- [Map.lookupLE lid firstOf]]
        | p <- pages,
          let n = poNumber p,
          (name, boundsOn) <- Map.findWithDefault [] n framesOf,
          let bounds = boundsOn n,
          col <- take 1 (drop (poColumn p) (columnSetRects geom n (poColumnSet p))),
          rectsOverlap col bounds,
          let (bx0, bx1) = acrossColumn geom col bounds
              lineSpans = concat [slotLines pos s | (pos, s) <- poSlots p]
        ]
      cuts = Map.fromListWith (Map.unionWith (\(a, b) (c, d) -> (max a c, max b d))) [(ui, Map.singleton k cut) | Right xs <- results, ((ui, k), _, cut, _) <- xs]
      measureOf col = if vertical then rectH col else rectW col
      -- what the line loses: beside a wrapped figure, the exclusion on its side too
      takes lid (s, e) = case Map.lookup lid beside of
        Just (_, Just (WrapStart, w)) -> (max s w, e)
        Just (_, Just (WrapEnd, w)) -> (s, max e w)
        _ -> (s, e)
      siteOf ui lid = case Map.lookup lid beside of
        Just (sp, _) -> Just sp
        Nothing -> Map.lookup ui (bUnitFirsts built) >>= (`Map.lookup` bLineSpans built)
      short =
        nubOrdOn
          diagSpan
          [ diagnostic "G07138" Error sp "回り込むフレームで短くした本文の行が、本文の文字の大きさの 8 字に満たなくなります"
          | Right xs <- results,
            ((ui, _), lid, cut, col) <- xs,
            let (s, e) = takes lid cut,
            measureOf col - s - e < 8 * pgFontSize geom,
            Just sp <- [siteOf ui lid]
          ]
   in (cuts, nubOrdOn diagSpan (lefts results) <> short)
  where
    -- along the lines, from the start of the column: what the frame takes at the start or at the end
    cutOf (Rect cx cy cw ch) (Rect bx by bw bh) =
      let (measure, a0, a1)
            | pgVertical geom = (ch, cy + ch - min (by + bh) (cy + ch), cy + ch - max by cy)
            | otherwise = (cw, max bx cx - cx, min (bx + bw) (cx + cw) - cx)
       in if a0 <= 0
            then Just (a1, 0)
            else if a1 >= measure then Just (0, measure - a0) else Nothing

-- | Whether a bounding rectangle and a column overlap in an area.
rectsOverlap :: Rect -> Rect -> Bool
rectsOverlap (Rect cx cy cw ch) (Rect bx by bw bh) = bx < cx + cw && bx + bw > cx && by < cy + ch && by + bh > cy

{- | A bounding rectangle across the lines, from the start edge of the
column: from its top in horizontal writing, from its right in vertical
writing.
-}
acrossColumn :: PageGeometry -> Rect -> Rect -> (Sp, Sp)
acrossColumn geom (Rect cx cy cw ch) (Rect bx by bw bh)
  | pgVertical geom = (cx + cw - (bx + bw), cx + cw - bx)
  | otherwise = (cy + ch - (by + bh), cy + ch - by)

{- | The lines set beside a wrapped figure (root ADR 0456): by their ids,
the block of their paragraph and, for the lines beside the exclusion,
its side and its width.
-}
besideLines :: Built -> Map Int (SrcSpan, Maybe (Wrap, Sp))
besideLines built =
  let cu = bComposed built
      units = cuUnits cu
      free = maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle (feInput (bFlowEnv built))) >>= pageGrid)
      narrow = Map.fromList [(lbId l, fid) | FWrapped {fwId = fid, fwBeside = ls} <- bFlow built, l <- ls]
      exclusionOf fid = Map.lookup fid (bFigures built) >>= fmap (\ex -> (exSide ex, exWidth ex)) . pfExclusion
      -- the lines of the paragraphs beside each figure, from the line after it (in free placement, by their own units)
      paragraphs =
        [ (u, firstLine, length (cLines c))
        | (i, _) <- Map.toList (cuFigures cu),
          Just figureFirst <- [Map.lookup i (bUnitFirsts built)],
          j <- besideParagraphs units (cuBesides cu) i,
          Just (c, off) <- [Map.lookup j (cuBesides cu)],
          let firstLine = if free then Map.findWithDefault (figureFirst + 1 + off) j (bUnitFirsts built) else figureFirst + 1 + off,
          Just u <- [Map.lookup j units]
        ]
   in Map.fromList [(lid, (uSpan u, Map.lookup lid narrow >>= exclusionOf)) | (u, firstLine, count) <- paragraphs, lid <- take count [firstLine ..]]

{- | The frames of wrap around of the master page of each page (root ADR
0438): by page number, each by its name and its bounding rectangle on a
page.
-}
aroundFramesByPage :: PdfInput -> PageGeometry -> Built -> [PageOutAt Sp] -> Map Int [(Text, Int -> Rect)]
aroundFramesByPage inp geom built pages = Map.map (maybe [] (aroundFramesOf inp geom)) (pageMastersOf inp geom built pages)

-- | The frames of wrap around of a master page, each by its name and its bounding rectangle on a page (root ADR 0438).
aroundFramesOf :: PdfInput -> PageGeometry -> Text -> [(Text, Int -> Rect)]
aroundFramesOf inp geom m =
  let style = piStyle inp
   in [ (name, frameBounds geom style f shape)
      | Just md <- [Map.lookup m (stMasters style)],
        name <- mdFrames md,
        Just f <- [Map.lookup name (stFrames style)],
        frWrap f == FrameWrapAround,
        Just shape <- [frameShape f]
      ]

-- | The name of the master page of each page by its number, from the files of its first lines.
pageMastersOf :: PdfInput -> PageGeometry -> Built -> [PageOutAt Sp] -> Map Int (Maybe Text)
pageMastersOf inp geom built pages =
  let firstPages = [p | (p : _) <- pagesOf pages]
   in Map.fromList (zip (map poNumber firstPages) (map (fmap fst) (masterNamesOf inp geom (pageFilesOf inp (bLineFiles built) pages))))

{- | The master pages of the pages a round of S2 assumes (root ADR 0456):
none when no master page has a frame of wrap around, so that the rounds
of a book without them are those before.
-}
assumedMasters :: PdfInput -> PageGeometry -> Built -> [PageOutAt Sp] -> Map Int (Maybe Text)
assumedMasters inp geom built pages
  | hasAroundFrames inp geom = pageMastersOf inp geom built pages
  | otherwise = Map.empty

-- | Whether a master page of the style has a frame of wrap around (root ADR 0456).
hasAroundFrames :: PdfInput -> PageGeometry -> Bool
hasAroundFrames inp geom = not (all (null . aroundFramesOf inp geom) (Map.keys (stMasters (piStyle inp))))

{- | The areas of the frames of wrap around that a block that cannot be
shortened is not placed over (root ADR 0456), in sp from the start edge of
the column: on page n, in column c of the set, those of the master page
the page had in the round before, or of the master page of the file of
the block when the round before has none; for each frame whose bounding
rectangle overlaps the column and the block along the lines, its
rectangle across the lines. Along the lines, a table and a code block
take the measure of the column; a figure takes its image, and the
measure of the column with a caption, but for a wrapped figure, whose
caption is as wide as its image.
-}
avoidAcross :: PdfInput -> PageGeometry -> Built -> AvoidAt Sp
avoidAcross inp geom built n c set ident
  | not (hasAroundFrames inp geom) = []
  | otherwise =
      let file = maybe (FileId 0) snd (Map.lookupLE ident (bLineFiles built))
          master = case Map.lookup n (asMasters (feAssumed (bFlowEnv built))) of
            Just m -> m
            Nothing -> fst <$> join (listToMaybe (masterNamesOf inp geom [file]))
          alongOf col = case Map.lookup ident (bFigures built) of
            Just pf
              | isJust (pfWrap pf) || null (pfCaption pf) -> imageRectAt geom (paperOf geom) col 0 pf
            _ -> col
          along (Rect cx cy cw ch) (Rect bx by bw bh)
            | pgVertical geom = by < cy + ch && by + bh > cy
            | otherwise = bx < cx + cw && bx + bw > cx
       in [ acrossColumn geom col bounds
          | Just m <- [master],
            (_, boundsOn) <- aroundFramesOf inp geom m,
            let bounds = boundsOn n,
            col <- take 1 (drop c (columnSetRects geom n set)),
            rectsOverlap col bounds,
            along (alongOf col) bounds
          ]

{- | 'avoidAcross' in grid lines (root ADR 0456): for each area, the grid
lines whose em box of the size of the grid crosses it.
-}
avoidLines :: PdfInput -> PageGeometry -> Built -> AvoidAt Int
avoidLines inp geom built n c set ident =
  let Sp pitch = pgLinePitch geom
      face = pgFontSize geom
      Sp top0 = sum (take 1 (pgLineGrid geom)) - (if pgVertical geom then Sp (unSp face `div` 2) else L.zwToSp face baselineRatio)
   in [ (lo, hi)
      | (Sp x0, Sp x1) <- avoidAcross inp geom built n c (fmap (\k -> fromIntegral k * Sp pitch) set) ident,
        let lo = max 0 (fromInteger ((x0 - top0 - unSp face) `div` pitch) + 1)
            hi = fromInteger (negate ((top0 - x1) `div` pitch)),
        lo < hi
      ]

{- | The outline of a text frame on page n (root ADR 0438): the rectangle
or the path of its [frames.<name>], the origin at the top of the trimmed
page and y going down, its lengths in the size of its paragraph style;
x-from inside and outside mirror it on the pages whose spine is on the
right and on the left.
-}
frameOutline :: PageGeometry -> Style -> Int -> FrameDef -> FrameShape -> Path
frameOutline geom st n f shape =
  let size = snd (paraFace st geom (fromMaybe "body" (frParagraphStyle f)))
      (pw, ph) = pgPageSize geom
      mirrored = case (frXFrom f, gutterSideFor (pgLayout geom) n) of
        (FromInside, Just SideRight) -> True
        (FromOutside, Just SideLeft) -> True
        _ -> False
      resolve = dimToSp size
   in case shape of
        FrameRect x y w h ->
          let (x', y', w', h') = (resolve x, resolve y, resolve w, resolve h)
           in rectPath (Rect (if mirrored then pw - x' - w' else x') (ph - y' - h') w' h')
        FramePath p -> mapPathPoints (\(px, py) -> (if mirrored then pw - px else px, ph - py)) p

{- | The bounding rectangle of a frame on each page: of its outline made a
polygon, rounded out to sp.
-}
frameBounds :: PageGeometry -> Style -> FrameDef -> FrameShape -> Int -> Rect
frameBounds geom st f shape n =
  let pts = concat (flattenPath (frameOutline geom st n f shape))
      xs = map fst pts
      ys = map snd pts
   in case pts of
        [] -> Rect 0 0 0 0
        _ ->
          let x0 = floor (minimum xs)
              y0 = floor (minimum ys)
           in Rect (Sp x0) (Sp y0) (Sp (ceiling (maximum xs) - x0)) (Sp (ceiling (maximum ys) - y0))

-- | A path with each of its points moved.
mapPathPoints :: ((Sp, Sp) -> (Sp, Sp)) -> Path -> Path
mapPathPoints f (Path subs) = Path [SubPath (f s) (map seg segs) c | SubPath s segs c <- subs]
  where
    seg = \case
      LineTo p -> LineTo (f p)
      CurveTo p q r -> CurveTo (f p) (f q) (f r)

-- | The page labels assumed in a round of S2: of labels and of index marks (golem-driver ADR 0007, docs/adr/0260).
data Assumed = Assumed
  { asLabels :: !(Map Text PageLabel),
    asMarks :: !(Map SrcSpan PageLabel),
    -- | the cuts of the lines under the frames of wrap around, by unit and line (root ADR 0438)
    asCuts :: !(Map Int (Map Int (Sp, Sp))),
    -- | the master page of each page, when a master page has frames of wrap around (root ADR 0456)
    asMasters :: !(Map Int (Maybe Text))
  }
  deriving stock (Eq, Show)

{- | S2: lays out with assumed page numbers until the pages of the labels
and index marks settle. A round that fails stops it with its errors;
after 'maxIterations' rounds, G07021 names what still moves and is at the
first of them (golem-driver ADR 0016): the block of a label (@labelSpan@)
or an index mark.
-}
fixpoint :: Map Int Section -> (Text -> SrcSpan) -> (SrcSpan -> Text) -> (b -> [PageOutAt position] -> Map Int (Map Int (Sp, Sp))) -> (Maybe b -> Assumed -> IO (Either [Diagnostic] (b, [PageOutAt position]))) -> IO (Either [Diagnostic] (b, [PageOutAt position]))
fixpoint sections labelSpan termOf cutsOf = fixpointWith sections labelSpan termOf cutsOf (\_ _ -> Map.empty)

{- | 'fixpoint' with the master pages of the pages laid out (root ADR
0456): the pagination of a round places the blocks that cannot be
shortened off the frames of wrap around of the master pages the round
before ended with, and the rounds go on until they settle too.
-}
fixpointWith :: Map Int Section -> (Text -> SrcSpan) -> (SrcSpan -> Text) -> (b -> [PageOutAt position] -> Map Int (Map Int (Sp, Sp))) -> (b -> [PageOutAt position] -> Map Int (Maybe Text)) -> (Maybe b -> Assumed -> IO (Either [Diagnostic] (b, [PageOutAt position]))) -> IO (Either [Diagnostic] (b, [PageOutAt position]))
fixpointWith sections labelSpan termOf cutsOf mastersOf layoutWith = go (1 :: Int) Nothing (Assumed Map.empty Map.empty Map.empty Map.empty)
  where
    -- each round is given the value of the round just before it, and of no other (docs/adr ADR 0251)
    go i prev assumed = do
      r <- layoutWith prev assumed
      case r of
        Left ds -> pure (Left ds)
        Right (built, pages) ->
          -- the labels of the pages: a first page of a section that moves moves them too (docs/adr/0260)
          let actual = Assumed (labelPages sections pages) (markPages sections pages) (cutsOf built pages) (mastersOf built pages)
           in if actual == assumed
                then pure (Right (built, pages))
                else
                  if i >= maxIterations
                    then pure (Left [if null (moved actual asLabels) && null (moved actual asMarks) then cutsNotSettled else notSettled (moved actual asLabels) (moved actual asMarks)])
                    else go (i + 1) (Just built) actual
      where
        moved :: (Ord k) => Assumed -> (Assumed -> Map k PageLabel) -> [k]
        moved now field = [k | k <- Map.keys (Map.union (field now) (field assumed)), Map.lookup k (field now) /= Map.lookup k (field assumed)]
    -- the lines under the frames of wrap around move with their cuts (root ADR 0438), the blocks past them with the master pages (root ADR 0456)
    cutsNotSettled = diagnostic "G07141" Error (mkSpan (FileId 0) 0 0) "回り込むフレームで短くする本文の行が定まりません"
    notSettled labels marks =
      let named = [(labelSpan l, l) | l <- labels] <> nubOrdOn snd [(m, termOf m) | m <- marks]
          sites = map fst named
       in (diagnostic "G07021" Error (fromMaybe (mkSpan (FileId 0) 0 0) (listToMaybe sites)) ("ページ番号の参照が収束しません: " <> T.intercalate ", " (map snd named)))
            { diagRelated = [(sp, "ページが定まりません") | sp <- drop 1 sites]
            }

{- | The composition environment of a unit set in a font role at a size
(golem-driver ADR 0003), in a book of a language (the language of its
manifest, docs/adr ADR 0276).
-}
composeEnv :: Text -> Style -> PageGeometry -> LoadedFonts -> Assumed -> Look -> ComposeEnv
composeEnv bookLang style geom fonts assumed look =
  let comp = stComposition style
      shaping = shapingForFonts fonts (pgVertical geom)
   in (defaultComposeEnv (lkSize look))
        { ceAdvance = \lk c -> lfAdvance fonts (shaping lk c) c,
          ceCellRatio = maybe 1 (\d -> toRational (unSp (dimToSp (pgFontSize geom) d)) / toRational (unSp (pgFontSize geom))) (stPage style >>= pageGrid >>= gridCharacterAdvance),
          ceWordAdvance = \lk t -> lfWordAdvance fonts (maybe (Shaping (lkLatinFace lk) False [] False) (shaping lk . fst) (T.uncons t)) t,
          -- a character of a word alone, in the shaping of the word (docs/adr/0222)
          ceWordCharAdvance = \lk t c -> lfAdvance fonts (maybe (Shaping (lkLatinFace lk) False [] False) (shaping lk . fst) (T.uncons t)) c,
          ceKern = \lk a b -> lfPairKern fonts (shaping lk a) a b,
          ceLook = look,
          ceRestyle = restyle style,
          ceSizeSourceOf = restyleSource style,
          ceVertical = pgVertical geom,
          ceKinsokuStrict = compKinsokuStrict comp,
          ceHanging = compHanging comp,
          ceProtrusion = compProtrusion comp,
          ceExplicitHyphenPenalty = compExplicitHyphenPenalty comp,
          ceNumberUnitPenalty = compNumberUnitPenalty comp,
          ceRuby = rubyStyleOf style (lkSize look),
          ceRubyReading = styledReading style,
          ceVerticalNumbers = verticalNumbersNamed (stNumbersVertical style),
          ceRefPageNumbers = case fromMaybe (stNumbersVertical style) (stNumbersRefPage style) of
            "sideways" -> Nothing
            v -> Just (verticalNumbersNamed v),
          cePageOf = (`Map.lookup` asLabels assumed),
          ceSidenoteMarker = case snMarker <$> stSidenotes style of
            Just "symbol" -> MarkerSymbol
            Just "none" -> MarkerNone
            _ -> MarkerNumber,
          ceSidenoteMarkStyle = stSidenotes style >>= snMarkerStyle,
          {- Latin words: the patterns of the language of their span, and
          outside one those of the language of the book, or US English when
          none is bundled for it (golem-layout ADR 0001, docs/adr ADR 0187,
          docs/adr ADR 0276), with the exceptions of the book over the
          bundled ones (docs/adr ADR 0272); the text of a file takes those
          of the file too ('withFileExceptions') -}
          cePatterns = exceptionPatterns bookLang Map.empty (compHyphenationExceptions comp),
          -- the set of body; a paragraph, a caption and a sidenote take their style's (docs/adr ADR 0019)
          ceAkiSet = akiSetOf style Nothing,
          -- the text of note marks (golem-driver ADR 0025) and their character style (docs/adr/0177)
          ceNoteMarkFormat = stNotesMarkFormat style,
          -- the kanji of the numbers set flat in vertical text (docs/adr/0381)
          ceNoteMarkFlat = stNotesMarkFlat style,
          {- a range of superscript or subscript is in the glyphs of the font when
          sups (subs) changes the glyph of every character of it (docs/adr/0269) -}
          ceScriptGlyphs = \pos cs ->
            let feature = if pos == PositionSubscript then "subs" else "sups"
                glyphs s c = map shGlyph (lfShape fonts s (T.singleton c))
                replaced (lk, c) =
                  let s = shaping lk c
                   in glyphs s c /= glyphs s {shExtra = normalTexts (shExtra s <> [feature])} c
             in all replaced cs,
          ceNoteMarkLook = noteMarkLook style,
          ceNoteMarkSource = noteMarkSource style,
          -- the marks of the endnotes, of [endnotes] (root ADR 0412)
          ceEndnoteMarkFormat = stNotesMarkFormat (endnoteStyle style),
          ceEndnoteMarkFlat = stNotesMarkFlat (endnoteStyle style),
          ceEndnoteMarkLook = noteMarkLook (endnoteStyle style),
          ceEndnoteMarkSource = noteMarkSource (endnoteStyle style)
        }

{- | The look of the mark of a note in the text from the look of its place
(docs/adr/0177): [notes] mark-style applied as any character style; the
retired mark-size, when written, is its size, at most that of the place
(golem-driver ADR 0025). Measuring and drawing the mark both take it.
-}
noteMarkLook :: Style -> Look -> Look
noteMarkLook style lk =
  let styled = restyle style lk (CharStyle noSpan (stNotesMarkStyle style) [])
   in maybe styled (\d -> styled {lkSize = noteMarkSize d (lkSize lk)}) (stNotesMarkSize style)
  where
    noSpan = mkSpan (FileId 0) 0 0

-- | The size source of the mark of a note in the text (golem-cli ADR 0008): mark-size, or what decides the size of mark-style (docs/adr/0177).
noteMarkSource :: Style -> SizeSource -> SizeSource
noteMarkSource style src = case stNotesMarkSize style of
  Just _ -> SourceNoteMark
  Nothing -> restyleSource style src (CharStyle (mkSpan (FileId 0) 0 0) (stNotesMarkStyle style) [])

{- | The aki set of a paragraph style (docs/adr ADR 0019): its aki-set,
inherited through based-on; Nothing is body.
-}
akiSetOf :: Style -> Maybe Text -> AkiSet
akiSetOf style st = resolveAkiSet (stAkiSets style) (fromMaybe defaultAkiSetName (paraStyle style st >>= psAkiSet))

{- | The notes among the anchors of composed inlines (golem-driver ADR
0018): the item index of the mark, the key, the number and the body. The
key is the span of the note and its place among the notes of that span.
-}
noteAnchors :: [Golem.Layout.Japanese.Anchor] -> [(Int, NoteId, Int, [[Inline]])]
noteAnchors anchors = snd (mapAccumL key Map.empty [(i, n, sp, b) | AnchorNote i n sp b <- anchors])
  where
    key seen (i, n, sp, b) =
      let k = Map.findWithDefault 0 sp seen
       in (Map.insert sp (k + 1) seen, (i, NoteId sp k, n, b))

{- | The body of a footnote after the mark of its number (golem-driver ADR
0018), as a sidenote has its mark (ADR 0006); the mark in the format of
[notes] mark-format (golem-driver ADR 0025). A quarter em [aki] keeps the
body apart from the mark: it neither stretches nor breaks (golem-layout
ADR 0018).
-}
withNoteMark :: Style -> Bool -> SrcSpan -> Int -> [Inline] -> [Inline]
withNoteMark style vertical sp n body = styled mark <> (Aki sp (AkiZw (1 / 4)) : body)
  where
    parts = markPartsShaped vertical (stNotesMarkFlat style) pre notation (toInteger n) suf
    {- numbered per page, the mark is one text, which 'markLabelBox' makes one
    box of the reserved width (docs/adr/0383); a mark whose number is set
    flat too, which the box sets flat (docs/adr/0381) -}
    mark
      | noteMarkBoxed style vertical n = [Text sp (markPartsText parts)]
      | otherwise = markInlines sp parts
    MarkFormat pre notation suf = stNotesMarkFormat style
    -- in the character style of [notes] body-mark-style (docs/adr/0177)
    styled xs = maybe xs (\name -> [CharStyle sp name xs]) (stNotesBodyMarkStyle style)

{- | Whether the mark at the start of the body of a note n is one box that
'markLabelBox' makes: numbered per page (docs/adr/0383), or with its
number in kanji set flat in vertical text (docs/adr/0381).
-}
noteMarkBoxed :: Style -> Bool -> Int -> Bool
noteMarkBoxed style vertical n =
  stNotesNumbering style == NumberPerPage
    || any (\case MarkFlat _ -> True; _ -> False) (markPartsShaped vertical (stNotesMarkFlat style) pre notation (toInteger n) suf)
  where
    MarkFormat pre notation suf = stNotesMarkFormat style

-- | How many inlines the mark of a note is in 'withNoteMark': the label of the Note (docs/adr ADR 0183).
noteMarkCount :: Style -> Bool -> SrcSpan -> Int -> Int
noteMarkCount style vertical sp n = length (withNoteMark style vertical sp n []) - 1

{- | The look of the reading of a ruby set in a look, in the character style
of [composition.ruby] reading-style (docs/adr/0369); Nothing without one,
for 'readingLook'. The style is applied over the look of the reading: the
font and the colour the style does not write are those around, and the
size it does not write is half the base. A size it writes, in zw too, is
measured against the base (its nominal size in a range of superscript or
subscript), not against the half.
-}
styledReading :: Style -> Look -> Maybe Look
styledReading style outer = do
  name <- rdReadingStyle (compRuby (stComposition style))
  def <- charStyle style name
  let reading = readingLook outer {lkRubyReading = Nothing}
      full = if lkPosition outer == PositionNormal then lkSize outer else lkNominalSize outer
      under = if isJust (csSize def) then reading {lkSize = full, lkNominalSize = full} else reading
  pure (restyle style under (CharStyle (mkSpan (FileId 0) 0 0) name [])) {lkRubyReading = Nothing}

{- | The placement of ruby from [composition.ruby] (golem-layout ADR
0009); @zw@ is the size of the paragraph.
-}
rubyStyleOf :: Style -> Sp -> RubyStyle
rubyStyleOf style fs =
  let rd = compRuby (stComposition style)
      align = \case
        "1:2:1" -> R.Align121
        "0:1:0" -> R.Align010
        "start" -> R.AlignStart
        _ -> R.AlignCenter
   in RubyStyle (align (rdMonoAlign rd)) (align (rdGroupAlign rd)) (align (rdBaseSpacing rd)) (dimToSp fs (rdOverhang rd)) (rdOverhangOnto rd == "kana")

{- | The parameters of the breaking of a paragraph of a paragraph style
(docs/adr/0274): its line-adjustment, pulling in first unless it is
balanced, and its stretch-limit in permille, from the same paragraph style
as the aki set ('akiSetOf'); and the order its lines shrink and stretch
in, its shrink-order and stretch-order, those of body for a style there
is not (docs/adr/0278).
-}
adjustedParams :: Style -> Maybe Text -> Params -> Params
adjustedParams style st ps =
  let d = paraStyle style st
      orderOf key = maybe [] (map (mapMaybe kindNamed)) ((d <|> paraStyle style Nothing) >>= key)
   in ps
        { pPullInFirst = (d >>= psLineAdjustment) /= Just Balanced,
          pStretchLimit = (\m -> toInteger m % 1000) <$> (d >>= psStretchLimit),
          pAdjustOrder = AdjustStaged (orderOf psShrinkOrder) (orderOf psStretchOrder)
        }

-- | The kind of glue of a name of shrink-order and stretch-order (docs/adr/0278).
kindNamed :: Text -> Maybe GlueKind
kindNamed n = lookup n [(name, k) | k <- [minBound .. maxBound], Just name <- [glueKindName k]]

kpParams :: Style -> PageGeometry -> Params
kpParams style geom =
  let comp = stComposition style
   in defaultParams
        { pPretolerance = compPretolerance comp,
          pTolerance = compTolerance comp,
          pEmergencyStretch = dimToSp (pgFontSize geom) (compEmergencyStretch comp),
          pExpansion = compExpansion comp,
          pProtrusion = compProtrusion comp || compHanging comp
        }

-- | A paragraph unit to break: the inlines, and the lists around it.
data Unit = Unit
  { uKind :: UnitKind,
    uLabel :: Maybe Text,
    uInlines :: [Inline],
    -- | the block the unit comes from, for diagnostics
    uSpan :: SrcSpan,
    -- | the role and the size the unit is set in (docs/adr ADR 0005)
    uLook :: Look,
    -- | the style of its document (docs/adr ADR 0014)
    uStyle :: Style,
    -- | the numbers of the lists around the unit, outermost first; lists are numbered from 0 in document order (golem-driver ADR 0013)
    uLists :: [Int],
    -- | the marker of the first paragraph of a list item
    uMarker :: Maybe [Inline],
    -- | the paragraph style of a paragraph, whose aki set it is set with; Nothing is body (docs/adr ADR 0019)
    uParaStyle :: Maybe Text,
    -- | the rules before and after a paragraph or a heading (golem-driver ADR 0027)
    uRules :: (Maybe RuleSpec, Maybe RuleSpec),
    -- | the place of a verse line in its stanza, a paragraph of line-breaks = "keep" without rules (docs/adr/0180)
    uStanza :: Maybe Int,
    -- | the definition that decided the size of 'uLook' (golem-cli ADR 0008)
    uSource :: SizeSource,
    -- | the frames of the structure tree around the unit, outermost first (docs/adr ADR 0183)
    uFrames :: [Frame],
    -- | the place of the unit among the units of the book, from 0 (docs/adr ADR 0183)
    uIndex :: Int,
    -- | the /Lang of the element of the unit, of a block with a language (docs/adr ADR 0187)
    uLang :: Maybe Text,
    -- | the box of a paragraph at the top of the document of a style with one (docs/adr/0271)
    uBox :: Maybe UnitBox
  }
  -- the units of two rounds of S2 are compared (docs/adr ADR 0251)
  deriving stock (Eq)

{- | The box of a paragraph (docs/adr/0271), resolved in sp: two
paragraphs one after the other go into one box when theirs are equal.
-}
data UnitBox = UnitBox
  { ubBackground :: !(Maybe Text),
    ubPadding :: !Sp,
    ubBorder :: !(Maybe Text),
    ubBorderWidth :: !Sp,
    -- | its lengths found from the width
    ubBorderStyle :: !RuleStyle,
    -- | in the order of 'BoxSide'
    ubSides :: ![BoxSide],
    ubRadius :: !Sp,
    -- | the indent and the end indent of the paragraph: from where to where along the line the box is
    ubStart :: !Sp,
    ubEnd :: !Sp
  }
  deriving stock (Eq, Show)

{- | A box of the flow by its id (docs/adr/0271): what it paints, from
where to where along the line of the column it is, the ids of its first
and its last line, and the paragraph style of its first paragraph.
-}
data BoxInfo = BoxInfo
  { bxPaint :: !BoxPaint,
    bxStart :: !Sp,
    bxEnd :: !Sp,
    bxFirst :: !Int,
    bxLast :: !Int,
    bxStyle :: !Text
  }
  deriving stock (Eq, Show)

{- | A frame of the structure tree of the PDF around units (docs/adr ADR
0183): a list, an item, the table of contents and so on. Its number tells
it from the frames of the same kind next to it, and its language the
/Lang of its element, of a block with a language (docs/adr ADR 0187).
-}
data Frame = Frame !Int !FrameKind !(Maybe Text)
  deriving stock (Eq, Show)

-- | A frame of no language of its own: its element takes that of the element around it (docs/adr ADR 0187).
frame :: Int -> FrameKind -> Frame
frame n k = Frame n k Nothing

data FrameKind
  = -- | a list, numbered or not
    FList !Bool
  | FItem
  | FDefList
  | -- | a group of a definition list: its terms and its definitions
    FDefItem
  | FDefBody
  | FToc
  | FIndex
  | FBibliography
  | FChannel
  | -- | the lines of a paragraph of a style that keeps its lines
    FPara
  | {- | a note at the end of a chapter, by its channel (a note or an
    endnote, root ADR 0412), its span, how many inlines its mark is and its
    number: in the tree after its mark
    -}
    FEndNote !NoteChannel !SrcSpan !Int !Int
  | {- | a paragraph after the first of a note at the end of a chapter, by
    the span of the note (docs/adr/0263): in the tree after the first
    -}
    FEndNoteMore !SrcSpan
  deriving stock (Eq, Show)

-- | The place of the text of a unit (docs/adr ADR 0183).
unitSite :: Int -> [Int]
unitSite i = [i, 0]

-- | The place of the marker of the first paragraph of a list item.
markerSite :: Int -> [Int]
markerSite i = [i, 1]

-- | The place of a cell of a table: its row (the header row is 0) and its column.
cellSite :: Int -> Int -> Int -> [Int]
cellSite i r c = [i, 2, r, c]

-- | The place of the caption of a figure or a code block.
captionSite :: Int -> [Int]
captionSite i = [i, 3]

-- | The place of a line of code, its rows when it wraps.
codeRowSite :: Int -> Int -> [Int]
codeRowSite i j = [i, 4, j]

-- | The place of the file name of a code block.
codeFileSite :: Int -> [Int]
codeFileSite i = [i, 6]

-- | The place of the image of a figure.
figureSite :: Int -> [Int]
figureSite i = [i, 7]

-- | The place of the body of a footnote, by its key: the same wherever its mark is.
noteSite :: NoteId -> [Int]
noteSite (NoteId sp k) = [-8, fileNumber (spanFile sp), spanStart sp, spanEnd sp, k]

-- | The place of a paragraph after the first of the body of a footnote (docs/adr/0263).
noteParagraphSite :: NoteId -> Int -> [Int]
noteParagraphSite k j = noteSite k <> [-1, j]

-- | The place of the body of a sidenote, by its span and its number.
sidenoteSite :: SrcSpan -> Int -> [Int]
sidenoteSite sp n = [-9, fileNumber (spanFile sp), spanStart sp, spanEnd sp, n]

fileNumber :: FileId -> Int
fileNumber (FileId f) = f

-- | The units in a frame: the frame outside the frames they have.
inFrame :: Frame -> [Unit] -> [Unit]
inFrame f = map (\u -> u {uFrames = f : uFrames u})

{- | How the messages of G07024 and G07100 name a heading, or the title of
the notes (golem-driver ADR 0003, 0026; golem-layout ADR 0020).
-}
headingName :: UnitKind -> Maybe Text
headingName = \case
  UHeading l short _ -> Just (T.pack (show l) <> " の見出し: " <> short)
  UNotesTitle title -> Just ("注の一覧の見出し: " <> title)
  _ -> Nothing

{- | The indent of the lines of a paragraph in sp (docs/adr ADR 0006). inFirst may be negative; inStart + inFirst >= 0.
The end indent and the alignment of the lines (docs/adr/0189).
-}
data Indent = Indent {inStart :: !Sp, inFirst :: !Sp, inEnd :: !Sp, inAlign :: !ParaAlign}
  deriving stock (Eq, Show)

noIndent :: Indent
noIndent = Indent 0 0 0 ParaLeftJustified

{- | How golem-layout breaks and sets the lines of a unit (docs/adr/0189): a
paragraph by the align of its style, those towards and away from the
spine as left until their page is known; any other unit left-justified.
-}
layoutAlign :: UnitKind -> A.ParaAlign
layoutAlign = \case
  UPara i -> alignOf i
  USeparator appearance -> A.Ragged $ case appearance of
    SeparatorTextAppearance _ _ "start" _ _ -> A.LineStart
    SeparatorTextAppearance _ _ "end" _ _ -> A.LineEnd
    SeparatorRuleAppearance _ _ "start" _ _ _ _ -> A.LineStart
    SeparatorRuleAppearance _ _ "end" _ _ _ _ -> A.LineEnd
    _ -> A.LineCenter
  -- an entry of the table of contents by the align of its style (docs/adr/0264)
  UTocEntry _ _ i _ -> alignOf i
  _ -> A.Justified (Just A.LineStart)
  where
    alignOf i = case inAlign i of
      ParaLeft -> A.Ragged A.LineStart
      ParaCenter -> A.Ragged A.LineCenter
      ParaRight -> A.Ragged A.LineEnd
      ParaLeftJustified -> A.Justified (Just A.LineStart)
      ParaCenterJustified -> A.Justified (Just A.LineCenter)
      ParaRightJustified -> A.Justified (Just A.LineEnd)
      ParaFullyJustified -> A.Justified Nothing
      ParaTowardsSpine -> A.Ragged A.LineStart
      ParaAwayFromSpine -> A.Ragged A.LineStart

-- | Whether the lines of a unit go towards the spine (True) or away from it (False) (docs/adr/0189).
spineOf :: UnitKind -> Maybe Bool
spineOf = \case
  UPara Indent {inAlign = ParaTowardsSpine} -> Just True
  UPara Indent {inAlign = ParaAwayFromSpine} -> Just False
  _ -> Nothing

{- | The lines aligned towards or away from the spine, moved on the page
they are set on (docs/adr/0189): to the side of the spine of the page or
to the other side, by 'gutterSide' as the running heads and sidenotes.
The books are horizontal, so the start of a line is its left.
-}
alignToSpine :: PageGeometry -> [PageOutAt Sp] -> Map Int SetLine -> Map Int SetLine
alignToSpine geom pages lines' = foldl' move lines' [(lid, poNumber p) | p <- pages, (_, SLine lid) <- poSlots p]
  where
    move m (lid, n) = Map.adjust (at n) lid m
    at n sl = case slSpine sl of
      Just towards ->
        let gutterLeft = gutterSide (pgBindingRight geom) n == SideLeft
            toEnd = towards /= gutterLeft
         in sl {slIndent = slIndent sl + (if toEnd then A.lineSlack (slLine sl) else 0), slSpine = Nothing}
      Nothing -> sl

data UnitKind
  = UPara !Indent
  | USeparator !SeparatorAppearance
  | UHeading Int Text Bool
  | -- | the title of the notes at the end of a chapter, set as a heading of level 2 (golem-driver ADR 0026)
    UNotesTitle Text
  | -- | a term of a definition list; indented in a list item (golem-driver ADR 0013)
    UTerm !Indent
  | UFigure Figure
  | UTable Table
  | -- | grid lines between paragraphs of a style (docs/adr ADR 0005)
    UGap Sp
  | -- | an entry of the table of contents: its level and its heading (golem-driver ADR 0009)
    UTocEntry Int SrcSpan Indent Sp
  | -- | a forced break (docs/adr ADR 0017)
    UBreak !BreakKind
  | -- | the start of a section: the place of its file among the chapter files, and its start (docs/adr/0260)
    USection !Int !(Maybe Integer)
  | -- | a code block: how far it starts from the line start (in a list) and its code (golem-driver ADR 0017, 0023)
    UCode !Sp Code
  | -- | an entry of the index in its own columns, of their measure (docs/adr ADR 0025)
    UIndexEntry !Sp
  | -- | the start (with the set) and the end of the columns of the index
    UColumns !(Maybe ColumnSet)
  | -- | a manual control of page breaks (docs/adr ADR 0030)
    UPageControl !PageControl
  | -- | blank lines before what follows (docs/adr ADR 0046)
    UBlank !Int64
  | -- | the paragraph before kept with so many lines of what follows: a heading of the index (docs/adr/0265)
    UKeepNext !Int
  | {- | a need-lines in a separator hold that no column fits with the lines
    of the hold before it, in a column of so many lines: it places
    nothing and is reported, G07037 (root ADR 0398 I7)
    -}
    UHeldNeedLines !Int !Int !Int
  deriving stock (Eq)

{- | The look and the indent of a paragraph style (docs/adr ADR 0005, 0006):
its role, its size, and its kerning, tracking, proportional metrics and
baseline shift (docs/adr/0020).
-}
paraLook :: Style -> PageGeometry -> Maybe Text -> (Look, Indent)
paraLook style geom st =
  let d = paraStyle style st
      (role, size) = faceFor style geom (d >>= psFont) (d >>= psSize)
      sp' f = dimToSp size (fromMaybe (Zw 0) (d >>= f))
   in (withFeatures d (plainLook role size), Indent (sp' psIndent) (sp' psFirstLineIndent) (sp' psEndIndent) (fromMaybe ParaLeftJustified (d >>= psAlign)))

paragraphSpace :: Style -> Maybe Text -> (ParaStyleDef -> Maybe Int) -> (ParaStyleDef -> Maybe Dim) -> Sp
paragraphSpace style name countOf dimOf = fromMaybe 0 $ do
  d <- paraStyle style name
  amount <- (SpacingDim <$> dimOf d) <|> (SpacingLines <$> countOf d)
  resolvedParagraphSpacing style d amount

{- | The indent of a paragraph that starts with an opening bracket
(docs/adr/0374): with opening-indent = "half", the start of the first line
(the indent and the first-line indent) less half the size of the
paragraph, 0 at the least; otherwise the indent as it is. The bracket is
the first character of the inlines, inside styles, links, language spans
and the bases of ruby, past the elements without a character; its class
is found in the language of the paragraph.
-}
openingIndent :: Maybe OpeningIndent -> Look -> Maybe Text -> Indent -> [Inline] -> Indent
openingIndent oi face blang ind@(Indent s f e a) is
  | oi == Just OpeningHalf,
    Just (spanLang, c) <- firstCharOf Nothing is,
    lookClass face {lkLang = spanLang <|> lkLang face <|> blang} c == Opening =
      let Sp size = lkSize face in Indent s (max (negate s) (f - Sp (size `div` 2))) e a
  | otherwise = ind

-- | The first character of inlines, with the language of the span it is in.
firstCharOf :: Maybe Text -> [InlineF r] -> Maybe (Maybe Text, Char)
firstCharOf lang = \case
  [] -> Nothing
  x : xs ->
    let inner l ys = firstCharOf l ys <|> firstCharOf lang xs
     in case x of
          Text _ t -> maybe (firstCharOf lang xs) (\(c, _) -> Just (lang, c)) (T.uncons t)
          Kenten _ _ ys -> inner lang ys
          Color _ _ ys -> inner lang ys
          CharStyle _ _ ys -> inner lang ys
          Link _ _ ys -> inner lang ys
          Lang _ l ys -> inner (Just l) ys
          Resolved _ _ _ ys -> inner lang ys
          Ruby _ _ segs -> firstCharOf lang (concatMap rsBase segs) <|> firstCharOf lang xs
          IndexMark {} -> firstCharOf lang xs
          ProofComment {} -> firstCharOf lang xs
          ChannelItem {} -> firstCharOf lang xs
          _ -> Nothing

{- | The look of code blocks (golem-driver ADR 0017): the role and size of
the paragraph style code, no kerning.
-}
codeLook :: Style -> PageGeometry -> Look
codeLook style geom =
  let d = paraStyle style (Just "code")
      (role, size) = faceFor style geom (d >>= psFont) (d >>= psSize)
   in (plainLook role size) {lkKerning = L.KernNone}

-- | The padding of code blocks; zw is the size of the code (golem-driver ADR 0017).
codePadding :: Style -> Sp -> Sp
codePadding style size = dimToSp size (fromMaybe (Zw (1 % 2)) (paraStyle style (Just "code") >>= psPadding))

-- | The look of the body role at a size, with the keys of the paragraph style body (docs/adr/0020).
bodyLook :: Style -> Sp -> Look
bodyLook style = styleLook style Nothing (bodyRole style)

-- | A role at a size with the keys of a paragraph style (docs/adr/0020).
styleLook :: Style -> Maybe Text -> Text -> Sp -> Look
styleLook style st role size = withFeatures (paraStyle style st) (plainLook role size)

{- | The marker of an item of a list at a depth (golem-driver ADR 0013): the
bullet of the depth, or the number in the format of the depth. @{n}@ is a
'Number'; in vertical writing an Arabic number of up to two digits is
tate-chu-yoko and other Latin is rotated as Latin text is.
-}
listMarker :: Style -> Bool -> Int -> Maybe Integer -> [Inline]
listMarker style vertical depth = \case
  Nothing -> [Text sp0 (atDepth (listBullets (stLists style)) depth)]
  Just n ->
    let NumberFormat pre st suf = atDepth (fromMaybe (pure (defaultNumberFormat vertical)) (lsNumbers (stLists style))) depth
     in case st of
          NsBook -> [Text sp0 pre | not (T.null pre)] <> [Number sp0 n Nothing] <> [Text sp0 suf | not (T.null suf)]
          -- set as the marks of notes are (docs/adr/0177)
          NsNotation notation -> markInlines sp0 (markParts vertical pre notation n suf)
  where
    sp0 = mkSpan (FileId 0) 0 0

{- | The units of the book. Each document is set in its own style: style.toml
with the styles its file defines (docs/adr ADR 0014). Lists are numbered
in document order; the units inside a list know the lists around them
(golem-driver ADR 0013).
-}

{- | The blocks without their text frames, at any depth: a frame takes no
room in the flow (root ADR 0438).
-}
withoutFrames :: [Block] -> [Block]
withoutFrames = concatMap $ \b -> case blockBody b of
  FrameBlock {} -> []
  BulletList items -> [b {blockBody = BulletList [i {itemBlocks = withoutFrames (itemBlocks i)} | i <- items]}]
  OrderedList items -> [b {blockBody = OrderedList [i {itemBlocks = withoutFrames (itemBlocks i)} | i <- items]}]
  DefList gs -> [b {blockBody = DefList [g {dgDefs = map withoutFrames (dgDefs g)} | g <- gs]}]
  _ -> [b]

unitsOf :: Text -> Book -> PageGeometry -> Maybe ColumnSet -> (FileId -> Style) -> (SrcSpan -> Maybe PageLabel) -> Map Text [EntryPart] -> Map Int (Maybe Integer) -> [Unit]
unitsOf lang book geom indexSet styleOf pageOf bib sections = concat (snd (mapAccumL chapter 0 indexedChapters))
  where
    fs = pgFontSize geom
    -- the documents with their places in the book, the places of the chapter files (docs/adr/0260)
    indexedChapters = snd (mapAccumL (\k ds -> (k + length ds, zip [k ..] ds)) 0 (bookChapters book))
    -- a file that starts a section starts with its break (docs/adr/0260)
    doc n (k, Document fid bs0) =
      let style = styleOf fid
          -- a text frame takes no room in the flow: the blocks around it are set as without it (root ADR 0438 I3)
          bs = withoutFrames bs0
          start = [Unit (USection k st) Nothing [] (mkSpan fid 0 0) (bodyLook style fs) style [] Nothing Nothing (Nothing, Nothing) Nothing SourceGrid [] 0 Nothing Nothing | Just st <- [Map.lookup k sections]]
       in (start <>) <$> blocks style [] True n bs
    {- the documents of a chapter of the manifest; at the end of the chapter,
    before the breaks that end its last file, its notes when they are set
    there (golem-driver ADR 0026) -}
    chapter n idocs =
      let docs = map snd idocs
          (n', uss) = mapAccumL doc n idocs
          us = concat uss
       in (n',) $ case reverse docs of
            (Document fid _ : _)
              | let notes = [notesList ChannelNote (notesTitle lang) (noteStyleFor PlaceChapterEnd (styleOf fid)) (concatMap documentNotes docs) | stNotesPlacement (styleOf fid) == PlaceChapterEnd]
                    -- the endnotes after the notes, always (root ADR 0412)
                    endnotes = notesList ChannelEndnote (endnotesTitle lang) (endnoteStyle (styleOf fid)) (concatMap documentEndnotes docs),
                not (all null notes) || not (null endnotes) ->
                  let (breaks, body) = span isBreakUnit (reverse us)
                   in reverse body <> concat notes <> endnotes <> reverse breaks
            _ -> us
    -- blank lines at the end of a file go before the first block of the next (docs/adr ADR 0046)
    isBreakUnit u = case uKind u of
      UBreak _ -> True
      UBlank _ -> True
      -- an empty file that starts a section: its break comes after the notes (docs/adr/0260)
      USection {} -> True
      _ -> False
    -- the title and a paragraph for each note, its mark first, as at the foot of a page
    notesList ch title style notes =
      case notes of
        [] -> []
        ns@((sp, _, _) : _) ->
          let -- the paragraph styles of [notes] heading-style and body-style (docs/adr/0366)
              (titleLook, titleSource) = notesTitleLook lang style geom
              bodyStyle = stNotesBodyStyle style
              look = noteBodyLook style geom
              source = noteBodySource style
           in Unit (UNotesTitle title) Nothing [Text sp title] sp titleLook style [] Nothing (stNotesHeadingStyle style) (Nothing, Nothing) Nothing titleSource [] 0 Nothing Nothing
                -- the first paragraph after the mark, the others without one and without space between (docs/adr/0263)
                : concat
                  [ Unit (UPara noIndent) Nothing (withNoteMark style (pgVertical geom) nsp n para0) nsp look style [] Nothing bodyStyle (Nothing, Nothing) Nothing source [frame 0 (FEndNote ch nsp (noteMarkCount style (pgVertical geom) nsp n) n)] 0 Nothing Nothing
                      : [Unit (UPara noIndent) Nothing more nsp look style [] Nothing bodyStyle (Nothing, Nothing) Nothing source [frame 0 (FEndNoteMore nsp)] 0 Nothing Nothing | more <- rest]
                  | (nsp, n, para0 : rest) <- ns
                  ]
    {- a list of blocks inside the lists @ctx@, from the list number @n@,
    with the spaces before and after of paragraphs when @spaced@ (not in a
    definition list): in a list item, paragraphs are not indented by their
    style (docs/adr ADR 0006) but by the lists (golem-driver ADR 0013) -}
    blocks style ctx spaced n bs =
      let (n', uss) = mapAccumL (\k (prev, b) -> (gapBefore style ctx spaced prev b <>) <$> block style ctx k b) n (zip (scanl before Nothing bs) bs)
       in (n', holdSeparatorNeeds (spaceSeparators (concat uss)))
    {- A need-lines inside a separator hold is asked for before the first
    separator too, with the lines of the hold before it and the blank lines
    before the hold, at most a column: the keep of a separator looks past
    a need-lines, so without it the hold stays where the need-lines then
    sends the next block on (root ADR 0398 I7). The need-lines written stays
    where it is, unless no column fits it with the lines of the hold before
    it: it is not part of the hold, so it does not send the next block away
    from the separator, and it is reported unmet ('heldNeedNotices'). The
    one asked for has the span of the separator, so that it reports nothing
    of its own ('unmetWarnings'). -}
    holdSeparatorNeeds units = case break isSeparator units of
      (leading, []) -> leading
      (leading, opening : rest) ->
        let (chain, after) = span inHold rest
            hold = opening : chain
            columnLines = length (pgLineGrid geom)
            blanks = sum [fromIntegral k | Unit {uKind = UBlank k} <- takeWhile isBlank (reverse leading)]
            inner = scanl (+) 0 (map holdLines hold)
            wanted = [blanks + at + k | (at, Unit {uKind = UPageControl (NeedLines k)}) <- zip inner hold]
            hoisted = case wanted of
              [] -> []
              _ -> [opening {uKind = UPageControl (NeedLines (min columnLines (maximum wanted))), uInlines = []}]
            settle at u = case uKind u of
              UPageControl (NeedLines k) | at + k > columnLines -> u {uKind = UHeldNeedLines at k columnLines}
              _ -> u
         in leading <> hoisted <> zipWith settle inner hold <> holdSeparatorNeeds after
      where
        isSeparator u = case uKind u of
          USeparator _ -> True
          _ -> False
        isBlank u = case uKind u of
          UBlank _ -> True
          _ -> False
        inHold u = case uKind u of
          USeparator _ -> True
          UGap _ -> True
          UBlank _ -> True
          UKeepNext _ -> True
          UPageControl _ -> True
          UHeldNeedLines {} -> True
          _ -> False
        holdLines u = case uKind u of
          USeparator _ -> 1
          UBlank k -> fromIntegral k
          UGap g -> fromInteger ((unSp g + unSp (pgLinePitch geom) - 1) `div` unSp (pgLinePitch geom))
          _ -> 0 :: Int
    -- A visible separator owns its boundary spacing. Explicit blank lines
    -- at that boundary and the two separator requests take the maximum.
    spaceSeparators = go Nothing []
      where
        beforeOf = \case
          USeparator (SeparatorTextAppearance n _ _ _ _) -> n
          USeparator (SeparatorRuleAppearance n _ _ _ _ _ _) -> n
          _ -> 0
        afterOf = \case
          USeparator (SeparatorTextAppearance _ n _ _ _) -> Just n
          USeparator (SeparatorRuleAppearance _ n _ _ _ _ _) -> Just n
          _ -> Nothing
        go previous pending [] = case previous of
          Just _ -> []
          Nothing -> pending
        go previous pending (u : rest) = case uKind u of
          UBlank _ -> go previous (pending <> [u]) rest
          UBreak _ -> pending <> (u : go Nothing [] rest)
          kind ->
            let explicit = sum [k | Unit {uKind = UBlank k} <- pending]
                requested = max explicit (fromIntegral (beforeOf kind))
                spacing = max requested (fromIntegral (maybe 0 snd previous))
                visibleBoundary = isJust previous || beforeOf kind > 0
                source = case pending of
                  initial : _ -> initial
                  [] -> u
                gap
                  | visibleBoundary && spacing > 0 =
                      [source {uKind = if isJust previous then UGap (fromIntegral spacing * pgLinePitch geom) else UBlank spacing, uInlines = []}]
                  | visibleBoundary = []
                  | otherwise = pending
                -- the keep has the span of the separator, so that the
                -- paginator knows it holds a separator (root ADR 0398 I7)
                keep = case previous of
                  Just (sp, _) -> [u {uKind = UKeepNext 1, uInlines = [], uSpan = sp}]
                  Nothing -> []
             in keep <> gap <> [u] <> go ((uSpan u,) <$> afterOf kind) [] rest
    gapBefore style ctx spaced prev (Block sp _ _ b) = case prev of
      Just (Block _ _ _ a)
        | g <- gapLines style ctx spaced a b,
          g > 0 ->
            [Unit (UGap g) Nothing [] sp (bodyLook style fs) style ctx Nothing Nothing (Nothing, Nothing) Nothing SourceGrid [] 0 Nothing Nothing]
      _ -> []
    {- the grid lines between two blocks (docs/adr/0189): only the blank
    lines across them; none before a forced break or a control of page
    breaks; between paragraphs of the same style its space-between (docs/adr
    ADR 0005); otherwise the greater of the space after of the block before
    and the space before of the block, which only paragraphs outside lists
    and definition lists have. Nothing before the breaks, and nothing
    across the boundary of two files, whose blocks are not siblings
    (docs/adr/0211) -}
    gapLines style ctx spaced a b = case (a, b) of
      (Separator _, _) -> 0
      (_, Separator _) -> 0
      (BlankLines _, _) -> 0
      (_, BlankLines _) -> 0
      (_, ForcedBreak _) -> 0
      (_, PageControl _) -> 0
      (Paragraph s1 _, Paragraph s2 _) | s1 == s2 -> paragraphSpace style s2 psSpaceBetween psSpaceBetweenDim
      _ -> max (spaceOf psSpaceAfter psSpaceAfterDim a) (spaceOf psSpaceBefore psSpaceBeforeDim b)
      where
        spaceOf key dimKey = \case
          Paragraph st _ | spaced, null ctx -> paragraphSpace style st key dimKey
          _ -> 0
    -- the block before, past the controls of page breaks (docs/adr ADR 0030)
    before prev b = case blockBody b of
      PageControl _ -> prev
      _ -> Just b
    -- a block with a language: the language of its characters and the /Lang of its element (docs/adr ADR 0187)
    block style ctx n b = withBlockLang (blockLang b) <$> blockUnits style ctx n b
    blockUnits style ctx n (Block sp lbl blang body) =
      let unit kind l is face src = Unit kind l is sp face style ctx Nothing Nothing (Nothing, Nothing) Nothing src [] 0 Nothing Nothing
          -- the body role at the size of the grid (golem-cli ADR 0008)
          plainUnit kind l is = unit kind l is (bodyLook style fs) SourceGrid
       in case body of
            -- a style that keeps its lines: a unit for each line, each indented as a
            -- paragraph (docs/adr ADR 0005, 0006); otherwise the line breaks are
            -- hard breaks inside one unit, and only its first line has the
            -- first-line indent (docs/adr ADR 0016)
            Paragraph st is ->
              let (face, ind) = paraLook style geom st
                  keeps = (paraStyle style st >>= psLineBreaks) == Just KeepLines
                  parts = if keeps then splitBreaks is else [is]
                  -- a paragraph in a list has no rules (golem-driver ADR 0027)
                  (rb, ra) = if null ctx then paraRules style st else (Nothing, Nothing)
                  rulesOf i = (if i == 0 then rb else Nothing, if i == length parts - 1 then ra else Nothing)
                  -- the verse lines of a paragraph without rules are one stanza (docs/adr/0180)
                  stanzaOf i = if keeps && (rb, ra) == (Nothing, Nothing) then Just i else Nothing
                  -- each part starts as a paragraph, with the indent of an opening bracket (docs/adr/0374)
                  indentOf = openingIndent (paraStyle style st >>= psOpeningIndent) face blang ind
                  us = [(unit (UPara (if null ctx then indentOf part else noIndent)) (if i == 0 then lbl else Nothing) part face (paraSizeSource style st)) {uParaStyle = st, uRules = rulesOf i, uStanza = stanzaOf i} | (i, part) <- zip [0 :: Int ..] parts]
               in -- the lines of the paragraph are one P (docs/adr ADR 0183)
                  if length parts > 1 then (n + 1, inFrame (frame n FPara) us) else (n, us)
            Heading l attrs is ->
              let num = Map.lookup sp (bookHeadings book) >>= hiNumberText
                  -- the number is at the heading (golem-cli ADR 0008)
                  title = bookNumberedTitle book (Just l) lang sp (if haNoNumber attrs then Nothing else num) is
                  recto = maybe False hsRectoBreak (Map.lookup l (stHeadings style))
                  rules = maybe (Nothing, Nothing) (\h -> (hsRuleBefore h, hsRuleAfter h)) (Map.lookup l (stHeadings style))
               in (n, [(unit (UHeading l (T.concat (map inlineText is)) recto) lbl title (uncurry (styleLook style Nothing) (headingFace lang style geom l)) (SourceHeading l)) {uRules = rules}])
            BulletList items -> list style ctx n (map (Nothing,) items)
            OrderedList items -> list style ctx n (zip (map Just (itemNumbers items)) items)
            DefList gs ->
              let group k (j, g) = (\us -> inFrame (frame j FDefItem) ([plainUnit (UTerm noIndent) Nothing t | t <- dgTerms g] <> inFrame (frame 0 FDefBody) us)) <$> blocksOf k (dgDefs g)
                  blocksOf k ds = let (k', dss) = mapAccumL (blocks style ctx False) k ds in (k', concat dss)
                  (n', uss) = mapAccumL group (n + 1) (zip [0 ..] gs)
               in (n', inFrame (frame n FDefList) (concat uss))
            TableBlock t -> (n, [plainUnit (UTable t) lbl []])
            -- always in the paragraph style code (golem-driver ADR 0017)
            CodeBlock code -> (n, [unit (UCode 0 code) lbl [] (codeLook style geom) (paraSizeSource style (Just "code"))])
            FigureBlock fig -> (n, [plainUnit (UFigure fig) lbl []])
            -- S1 has dropped the index marks and channel items of the title (docs/adr/0145)
            -- each entry a paragraph of the style toc-<l> of its level (docs/adr/0264); its reserve is filled by flowUnits
            ChannelOutput (TocOutput depth) ->
              let entries = [e | e <- bookToc book, teLevel e <= depth]
                  styleOf' e = Just (tocStyleName (teLevel e))
                  -- an entry a link to its heading, its lines from the first box to the page number (docs/adr/0267)
                  entryUnit e =
                    let st = styleOf' e
                        (face, ind) = paraLook style geom st
                     in (unit (UTocEntry (teLevel e) (teSpan e) ind 0) Nothing (bookNumberedTitle book (Just (teLevel e)) lang (teSpan e) (teNumber e) (teTitle e)) face {lkLink = Just (LinkTo (DestHeading (teSpan e)))} SourceGrid) {uParaStyle = st, uRules = paraRules style st}
                  spaceOf key dimKey st = paragraphSpace style st key dimKey
                  gapUnit g = [Unit (UGap g) Nothing [] sp (bodyLook style fs) style ctx Nothing Nothing (Nothing, Nothing) Nothing SourceGrid [] 0 Nothing Nothing | g > 0]
                  -- the spaces before the first entry, between the entries and after the last (docs/adr/0264)
                  between a b
                    | styleOf' a == styleOf' b = spaceOf psSpaceBetween psSpaceBetweenDim (styleOf' b)
                    | otherwise = max (spaceOf psSpaceAfter psSpaceAfterDim (styleOf' a)) (spaceOf psSpaceBefore psSpaceBeforeDim (styleOf' b))
                  tocUnits = \case
                    [] -> []
                    es@(e0 : _) ->
                      gapUnit (spaceOf psSpaceBefore psSpaceBeforeDim (styleOf' e0))
                        <> [entryUnit e0]
                        <> concat [gapUnit (between a b) <> [entryUnit b] | (a, b) <- zip es (drop 1 es)]
                        <> concat [gapUnit (spaceOf psSpaceAfter psSpaceAfterDim (styleOf' l)) | l : _ <- [reverse es]]
               in (n + 1, inFrame (frame n FToc) (tocUnits entries))
            {- a heading a paragraph of the kind of the entries kept with the first of them,
            a grid line before every heading but the first (docs/adr/0265) -}
            ChannelOutput IndexOutput ->
              let lineUnits kind seen = \case
                    IndexHeadingLine is -> (seen + 1, [plainUnit (UGap (pgLinePitch geom)) Nothing [] | seen > (0 :: Int)] <> [plainUnit kind Nothing is, plainUnit (UKeepNext 1) Nothing []])
                    IndexEntryLine is -> (seen, [plainUnit kind Nothing is])
                  ls = indexLines (pgVertical geom) (indexSectionHeadings style) pageOf (indexAt book sp)
                  entries kind = inFrame (frame n FIndex) (concat (snd (mapAccumL (lineUnits kind) 0 ls)))
               in case indexSet of
                    Nothing -> (n + 1, entries (UPara noIndent))
                    -- the index in its own columns (docs/adr ADR 0025)
                    Just set -> (n + 1, [plainUnit (UColumns (Just set)) Nothing []] <> entries (UIndexEntry (csMeasure set)) <> [plainUnit (UColumns Nothing) Nothing []])
            -- each entry of a channel of a plugin a paragraph of its style (golem-doc ADR 0007)
            ChannelOutput (CustomOutput name st) ->
              let (face, ind) = paraLook style geom st
                  locators = maybe False channelLocators (Map.lookup name (bookChannelDecls book))
               in (n + 1, inFrame (frame n FChannel) [(unit (UPara (if null ctx then ind else noIndent)) Nothing is face (paraSizeSource style st)) {uParaStyle = st} | is <- channelLines (pgVertical geom) pageOf locators (channelAt book sp)])
            ChannelOutput BibliographyOutput -> (n + 1, inFrame (frame n FBibliography) [plainUnit (UPara noIndent) Nothing is | is <- bibliographyLines bib (bibliographyAt book sp)])
            ForcedBreak k -> (n, [plainUnit (UBreak k) Nothing []])
            PageControl (NoBreakLines 0) -> (n, [])
            PageControl c -> (n, [plainUnit (UPageControl c) Nothing []])
            BlankLines k -> (n, [plainUnit (UBlank k) Nothing []])
            Separator name ->
              case Map.lookup (sp, name) (bookSeparators book) of
                Just appearance ->
                  let content = case appearance of
                        SeparatorTextAppearance _ _ _ t Nothing -> [CharStyle sp "no-break" [Text sp t]]
                        SeparatorTextAppearance _ _ _ t (Just characterName) -> [CharStyle sp "no-break" [CharStyle sp characterName [Text sp t]]]
                        SeparatorRuleAppearance {} -> [Text sp "\x200B"]
                   in (n, [plainUnit (USeparator appearance) Nothing content])
                Nothing -> (n, [])
            -- left out by withoutFrames; set in their frames (root ADR 0438)
            FrameBlock {} -> (n, [])
    {- the items of the list numbered n: their units are inside it, the first
    unit of an item that starts with a paragraph carries the marker -}
    list style ctx n items =
      let ctx' = ctx <> [n]
          marker = listMarker style (pgVertical geom) (length ctx')
          item k (j, (num, it)) =
            let (k', us) = blocks style ctx' True k (itemBlocks it)
             in (k', inFrame (frame j FItem) (if startsWithParagraph it then markFirst (lsMarkerStyle (stLists style)) (marker num) us else us))
          (n', uss) = mapAccumL item (n + 1) (zip [0 ..] items)
          numbered = any (isJust . fst) items
       in (n', inFrame (frame n (FList numbered)) (concat uss))
    startsWithParagraph it = case itemBlocks it of
      (Block _ _ _ (Paragraph {}) : _) -> True
      _ -> False
    -- the marker is at the block of its paragraph (golem-cli ADR 0008)
    markFirst name m = \case
      (u : rest) ->
        let sp = uSpan u
            xs = map (atSpan sp) m
         in u {uMarker = Just (maybe xs (\n -> [CharStyle sp n xs]) name)} : rest
      [] -> []
    atSpan s = \case
      Text _ t -> Text s t
      Number _ k st -> Number s k st
      Tcy _ t -> Tcy s t
      Warichu _ t -> Warichu s t
      Upright _ t -> Upright s t
      x -> x
    splitBreaks is = case break isBreak is of
      (l, []) -> [l]
      (l, _ : rest) -> l : splitBreaks rest
    isBreak = \case
      LineBreak _ -> True
      _ -> False

{- | The units of a block with a language (docs/adr ADR 0187): the
characters of each unit in it, unless the unit is of a block inside of a
language of its own; the /Lang on the element of the block, the frame it
makes (a list, a paragraph that keeps its lines, a list of a channel) or
else its unit.
-}
withBlockLang :: Maybe Text -> [Unit] -> [Unit]
withBlockLang lang us = case lang of
  Nothing -> us
  Just l ->
    let looked = [u {uLook = (uLook u) {lkLang = lkLang (uLook u) <|> Just l}} | u <- us]
        made = case [f | u <- us, f@(Frame _ k _) : _ <- [uFrames u], outer k] of
          f : _ -> Just f
          [] -> Nothing
        outer = \case
          FList _ -> True
          FDefList -> True
          FToc -> True
          FIndex -> True
          FChannel -> True
          FBibliography -> True
          FPara -> True
          _ -> False
     in case made of
          Just f@(Frame j k _) -> [case uFrames u of g : rest | g == f -> u {uFrames = Frame j k (Just l) : rest}; _ -> u | u <- looked]
          Nothing -> [u {uLang = Just l} | u <- looked]

{- | The marker width M of each list, by its number (golem-driver ADR 0013):
the widest marker w of the list and the gap G, rounded up to whole
characters of the type area's size @fs@. G is @gap@ (zw of the
paragraph's size), or 0 after punctuation with its own space and fs / 2
otherwise. A list without a marker has no width.
-}
listWidths :: (Unit -> ComposeEnv) -> Sp -> Maybe Dim -> [Unit] -> Map Int Sp
listWidths envOf fs gap units =
  Map.fromListWith
    max
    [ (lid, roundUp (markerWidth (envOf u) m + g))
    | u <- units,
      Just m <- [uMarker u],
      let g = case gap of
            Just d -> dimToSp (lkSize (uLook u)) d
            Nothing
              | endsWithSpacedPunctuation (T.concat (map inlineText m)) -> 0
              | otherwise -> Sp (unSp fs `div` 2),
      lid <- take 1 (reverse (uLists u))
    ]
  where
    roundUp x = Sp (unSp (x + fs - 1) `div` unSp fs) * fs

-- | w: the width of the boxes of a marker.
markerWidth :: ComposeEnv -> [Inline] -> Sp
markerWidth env m = sum [w | Box w _ <- fst (composeInlines env m)]

-- | A unit composed and broken into lines.
data Composed = Composed
  { cLines :: [Line],
    cNotes :: [(NoteId, [Line])],
    -- | sidenote bodies: the item index of the marker, the span and the lines
    cSidenotes :: [(Int, SrcSpan, [PartLine])],
    -- | index marks: the item index they belong to (a note's marks go with the note) and the mark
    cMarks :: [(Int, SrcSpan)],
    cAnchors :: [Golem.Layout.Japanese.Anchor],
    cItems :: [Item],
    -- | the items of a list marker before the text: the item indices of the anchors are shifted by it (golem-driver ADR 0013)
    cShift :: Int,
    -- | Original shaped-item break positions, including discarded glue and penalties.
    cBreakPositions :: [Int],
    -- | The source prefix already committed by causal free wrapping.
    cItemStart :: Int,
    cReflowed :: Bool,
    cActualIndents :: Maybe [Sp]
  }

{- | The environment in which the units of the body are set (docs/adr/0173):
the input, the page geometry, the fonts, the pages assumed for the marks,
and what follows from them for every unit.
-}
data FlowEnv = FlowEnv
  { feInput :: PdfInput,
    feGeom :: PageGeometry,
    feFonts :: LoadedFonts,
    feAssumed :: Assumed,
    feParams :: Params,
    -- | the measure of a column
    feMeasure :: Sp,
    -- | notes at the end of the chapter, not at the foot of the page (golem-driver ADR 0026)
    feNotesAtEnd :: Bool,
    -- | the composition of the body size of style.toml
    feBodyEnv :: ComposeEnv,
    -- | the reserve for the page number of a table of contents entry: W and two em (golem-driver ADR 0009)
    feTocReserve :: Sp,
    -- | where the characters of a text are in the sources (docs/adr ADR 0195)
    feSourceAt :: SrcSpan -> Text -> Int -> Int,
    -- | with notes numbered per page, how many notes and sidenotes the book has (docs/adr/0383)
    feMarkReserve :: Maybe (Int, Int)
  }

flowEnv :: PdfInput -> PageGeometry -> LoadedFonts -> Assumed -> FlowEnv
flowEnv inp geom fonts assumed = fe
  where
    style = piStyle inp
    fs = pgFontSize geom
    body = lookEnv fe (bodyLook style fs)
    fe =
      FlowEnv
        { feInput = inp,
          feGeom = geom,
          feFonts = fonts,
          feAssumed = assumed,
          feParams = kpParams style geom,
          feMeasure = columnMeasure geom,
          feNotesAtEnd = stNotesPlacement style == PlaceChapterEnd,
          feBodyEnv = body,
          feTocReserve = fst (tocMetrics body) + 2 * fs,
          feSourceAt = sourceAt (Map.map (TE.encodeUtf8 . sfText) (projectSources (piProject inp))),
          feMarkReserve = if stNotesNumbering style == NumberPerPage then Just (noteCounts (piBook inp)) else Nothing
        }

-- | The composition of a look; citations show their numbers (golem-driver ADR 0007).
lookEnv :: FlowEnv -> Look -> ComposeEnv
lookEnv fe lk = (composeEnv (bookLanguage (feInput fe)) (piStyle (feInput fe)) (feGeom fe) (feFonts fe) (feAssumed fe) lk) {ceCiteNumber = citeNumber (piBook (feInput fe)), ceCiteLink = citeLink (piBook (feInput fe)), ceSourceAt = feSourceAt fe, ceMarkReserve = feMarkReserve fe, cePageOf = labelPageOf (piBook (feInput fe)) (feAssumed fe), ceNoteRefOf = \l -> feMarkReserve fe >> pageNumberedNote (piBook (feInput fe)) l}

{- | The page of a label (docs/adr/0260): of the block it is on, or of the
mark of the note it is on, followed as an index mark by its span (root
ADR 0422).
-}
labelPageOf :: Book -> Assumed -> Text -> Maybe PageLabel
labelPageOf book assumed l = case Map.lookup l (bookLabels book) of
  Just LabelTarget {ltNote = Just _, ltSpan = sp} -> Map.lookup sp (asMarks assumed)
  _ -> Map.lookup l (asLabels assumed)

{- | The channel and the number in the book of the note a label is on, when
the channel is numbered per page (root ADR 0422): a note or a sidenote;
the endnotes never are.
-}
pageNumberedNote :: Book -> Text -> Maybe (NoteChannel, Int)
pageNumberedNote book l = case Map.lookup l (bookLabels book) >>= ltNote of
  Just (NoteTarget FootnoteChannel n) -> Just (ChannelNote, n)
  Just (NoteTarget SidenoteChannel n) -> Just (ChannelSidenote, n)
  _ -> Nothing

-- | The label of each note that has one, by the span of the note (root ADR 0422).
noteLabelSpans :: Book -> Map SrcSpan Text
noteLabelSpans book = Map.fromList [(ltSpan t, l) | (l, t@LabelTarget {ltNote = Just _}) <- Map.toList (bookLabels book)]

{- | How many notes and how many sidenotes the book has (docs/adr/0383):
numbered per page, the book numbers them in its order before the pages
are known, so the largest number of each is how many there are.
-}
noteCounts :: Book -> (Int, Int)
noteCounts book =
  let found = bookNoteSites book
   in (maximum (0 : [n | (ChannelNote, n, _) <- found]), maximum (0 : [n | (ChannelSidenote, n, _) <- found]))

-- | The notes and the sidenotes of the book in its order: the channel, the number and the span of each (docs/adr/0383).
bookNoteSites :: Book -> [(NoteChannel, Int, SrcSpan)]
bookNoteSites book = concatMap (concatMap inlineNotes) (concatMap blockInlineLists (concat [bs | Document _ bs <- bookDocs book]))
  where
    inlineNotes = \case
      Note sp n _ nb -> (ChannelNote, n, sp) : concatMap inlineNotes (concat (noteParagraphs nb))
      Sidenote sp n _ nb -> (ChannelSidenote, n, sp) : concatMap inlineNotes (concat (noteParagraphs nb))
      -- the endnotes are not numbered per page: their bodies alone (root ADR 0412)
      Endnote _ _ _ nb -> concatMap inlineNotes (concat (noteParagraphs nb))
      Kenten _ _ xs -> concatMap inlineNotes xs
      Color _ _ xs -> concatMap inlineNotes xs
      CharStyle _ _ xs -> concatMap inlineNotes xs
      Lang _ _ xs -> concatMap inlineNotes xs
      Link _ _ xs -> concatMap inlineNotes xs
      Resolved _ _ _ xs -> concatMap inlineNotes xs
      _ -> []

{- | The link of the number of a cited work (docs/adr/0267): to its entry
in the @bibliography its mark belongs to; none without @bibliography.
-}
citeLink :: Book -> SrcSpan -> Text -> Maybe LinkTarget
citeLink book sp k = case Map.lookup (spanFile sp, sp) (bookCiteMarks book) of
  Just (Just (_, at), _) | isJust (citeNumber book sp k) -> Just (LinkTo (DestBibEntry at k))
  _ -> Nothing

-- | A composition with the character styles of the style of a document (docs/adr ADR 0014).
withDocStyle :: Style -> ComposeEnv -> ComposeEnv
withDocStyle st e = e {ceRestyle = restyle st, ceRubyReading = styledReading st, ceSizeSourceOf = restyleSource st}

-- | The composition of the text of a unit: its look, its document's style and the aki set of its paragraph style.
unitEnv :: FlowEnv -> Unit -> ComposeEnv
unitEnv fe u = (exceptionsOf (withDocStyle (uStyle u) (lookEnv fe (uLook u)))) {ceAkiSet = akiSetOf (uStyle u) (uParaStyle u), ceLabelInlines = unitLabelInlines u, ceLabelLink = unitLabelLink u}
  where
    exceptionsOf = if madeByGolem u then id else withFileExceptions fe (spanFile (uSpan u))

{- | The hyphenation exceptions of a file, of its @hyphenation-exceptions
lines, over those of the book (docs/adr ADR 0272): the text of a block
takes those of the file it is written in, an imported block those of the
imported file, the body of a note and a caption those of the file of the
note and the figure.
-}
withFileExceptions :: FlowEnv -> FileId -> ComposeEnv -> ComposeEnv
withFileExceptions fe fid e =
  let inp = feInput fe
      file = maybe Map.empty lsHyphenationExceptions (Map.lookup fid (piLocalStyles inp))
   in e {cePatterns = exceptionPatterns (bookLanguage inp) file (compHyphenationExceptions (stComposition (piStyle inp)))}

{- | Whether Golem makes the lines of a unit (docs/adr ADR 0272): the table
of contents, the index, the bibliography, the list of a channel and the
title of the notes at the end of a chapter, which take the exceptions of
the book alone.
-}
madeByGolem :: Unit -> Bool
madeByGolem u = case uKind u of
  UNotesTitle {} -> True
  UTocEntry {} -> True
  UIndexEntry {} -> True
  _ -> any made (uFrames u)
  where
    made (Frame _ k _) = case k of
      FToc -> True
      FIndex -> True
      FBibliography -> True
      FChannel -> True
      _ -> False

{- | How many inlines at the start of a unit are its label (docs/adr ADR
0183): the mark and its space of a note at the end of a chapter, the
number of an entry of the bibliography.
-}
unitLabelInlines :: Unit -> Int
unitLabelInlines u = case [k | Frame _ k _ <- uFrames u] of
  ks
    | (k : _) <- [k | FEndNote _ _ k _ <- ks] -> k
    | FBibliography `elem` ks -> 1
    | otherwise -> 0

{- | The link of the label of a unit (docs/adr/0267): the mark of a note at
the end of a chapter goes back to its mark in the text.
-}
unitLabelLink :: Unit -> Maybe LinkTarget
unitLabelLink u = listToMaybe [LinkTo (DestNoteMark (NoteId sp 0)) | Frame _ (FEndNote _ sp _ _) _ <- uFrames u]

{- | The units of the body in order, numbered from 0, and the marker width
M of each list; a unit in lists is indented by them (golem-driver ADR 0013).
-}
flowUnits :: FlowEnv -> ([(Int, Unit)], Map Int Sp)
flowUnits fe = ([(i, (withBox (withReserve (withListIndent u))) {uIndex = i}) | (i, u) <- zip [0 :: Int ..] rawUnits], widths)
  where
    {- the box of a paragraph at the top of the document (docs/adr/0271): its
    lines the padding inside the box, which is from the indent to the end indent -}
    withBox u = case (uKind u, paraStyle (uStyle u) (uParaStyle u)) of
      (UPara (Indent s f e a), Just d)
        | topParagraph u,
          uParaStyle u /= Just "code",
          hasBox d ->
            let size = lkSize (uLook u)
                pad = dimToSp size (fromMaybe (Zw (1 % 2)) (psPadding d))
                w = dimToSp size (fromMaybe (Abs 16384) (psBorderWidth d))
                sides = [x | x <- [minBound .. maxBound], x `elem` fromMaybe [minBound .. maxBound] (psBorderSides d)]
                ub = UnitBox (join (psBackground d)) pad (join (psBorder d)) w (borderStyleAt w (fromMaybe RuleSolid (psBorderStyle d))) sides (maybe 0 (dimToSp size) (psBorderRadius d)) s e
                (s', e') = boxLineRange s e pad
             in u {uKind = UPara (Indent s' f e' a), uBox = Just ub}
      _ -> u
    -- R = W + 2fs of the entries of the table of contents, of the depth of @toc, in the style of its document (docs/adr/0264)
    tocDepth = fromMaybe 6 (bookTocDepth (piBook inp))
    reserves = Map.fromList [(spanFile (uSpan u), tocReserveWidth fe (uStyle u) tocDepth + 2 * pgFontSize geom) | u <- rawUnits, UTocEntry {} <- [uKind u]]
    withReserve u = case uKind u of
      UTocEntry l hs ind _ -> u {uKind = UTocEntry l hs ind (Map.findWithDefault 0 (spanFile (uSpan u)) reserves)}
      _ -> u
    inp = feInput fe
    geom = feGeom fe
    style = piStyle inp
    -- a mark without an assumed page yet stands at page 1 in the first round
    markPage sp = Map.lookup sp (asMarks (feAssumed fe)) <|> (if Map.null (asMarks (feAssumed fe)) then Just (plainLabel 1) else Nothing)
    rawUnits = unitsOf (bookLanguage inp) (piBook inp) geom (indexColumnSet style geom) (docStyle inp) markPage (piBibliography inp) (Map.map secStart (bookSections inp))
    widths = listWidths (unitEnv fe) (pgFontSize geom) (lsGap (stLists style)) rawUnits
    withListIndent u
      | null (uLists u) = u
      | otherwise = case uKind u of
          UPara _ -> u {uKind = UPara (Indent (listsOuter widths u) (if isJust (uMarker u) then negate (listInner widths u) else 0) 0 ParaLeftJustified)}
          UTerm _ -> u {uKind = UTerm (Indent (listsOuter widths u) 0 0 ParaLeftJustified)}
          UCode _ code -> u {uKind = UCode (listsOuter widths u) code}
          _ -> u

-- | O: the widths of the lists around a unit (golem-driver ADR 0013).
listsOuter :: Map Int Sp -> Unit -> Sp
listsOuter widths u = sum [Map.findWithDefault 0 lid widths | lid <- uLists u]

-- | Mi: the width of the innermost list around a unit (golem-driver ADR 0013).
listInner :: Map Int Sp -> Unit -> Sp
listInner widths u = case reverse (uLists u) of
  (lid : _) -> Map.findWithDefault 0 lid widths
  [] -> 0

{- | L*(i): the width of line k of a unit of the kind; the first line is
shortened by the indent and the first-line indent, the others by the
indent (docs/adr ADR 0006), every line by the end indent (docs/adr/0189);
a table of contents entry also by the reserve for its page number
(golem-driver ADR 0009).
-}
unitLineWidth :: FlowEnv -> UnitKind -> Int -> Sp
unitLineWidth fe kind k = case kind of
  UIndexEntry m -> m
  -- the reserve of the page number of an entry of the table of contents (docs/adr/0264)
  _ -> feMeasure fe - unitLineIndent (pgFontSize (feGeom fe)) kind k - unitEndIndent kind - (case kind of UTocEntry _ _ _ r -> r; _ -> 0)

-- | The end indent of the lines of a unit of the kind (docs/adr/0189).
unitEndIndent :: UnitKind -> Sp
unitEndIndent = \case
  UPara i -> inEnd i
  UTocEntry _ _ i _ -> inEnd i
  _ -> 0

-- | How far line k of a unit of the kind starts from the line start, at the font size of the grid.
unitLineIndent :: Sp -> UnitKind -> Int -> Sp
unitLineIndent _ = \case
  UPara (Indent s f _ _) -> \k -> if k == (0 :: Int) then s + f else s
  UTerm (Indent s _ _ _) -> const s
  -- an entry of the table of contents by its style (docs/adr/0264)
  UTocEntry _ _ (Indent s f _ _) _ -> \k -> if k == (0 :: Int) then s + f else s
  _ -> const 0

{- | The marker of a list item: its boxes and an empty box up to Mi, before
the text with no glue or penalty between them (golem-driver ADR 0013).
-}
markerItems :: ComposeEnv -> Sp -> Unit -> [Item]
markerItems env inner u = case uMarker u of
  Nothing -> []
  Just m ->
    let boxes = [b | b@Box {} <- fst (composeInlines env {ceSite = markerSite (uIndex u), ceLabelInlines = 0} m)]
        w = sum (map itemWidth boxes)
     in boxes <> [Box (inner - w) (BoxContent "" False 0 0 (fromEnum KindText) (ceLook env) 0 0 [] 0 0 (uSource u, uSpan u) Nothing noLeaf (spanStart (uSpan u)) Nothing)]

{- | Composes a unit and breaks it into lines of the widths, with its notes,
sidenotes and index marks. A unit in a box is composed and broken as with
hanging-punctuation = false: its edge is the inner edge of the box, not the
type area (docs/adr/0279).
-}
composeUnit :: FlowEnv -> Map Int Sp -> (Int -> Sp) -> Unit -> Composed
composeUnit fe widths lineWidth u =
  let boxed = isJust (uBox u)
      env = (unitEnv fe u) {ceSizeSource = uSource u, ceSite = unitSiteOf u, ceHanging = ceHanging (unitEnv fe u) && not boxed}
      params
        | boxed = (feParams fe) {pProtrusion = compProtrusion (stComposition (piStyle (feInput fe)))}
        | otherwise = feParams fe
      marker = markerItems env (listInner widths u) u
      -- the anchors count the items of the text; the marker comes first
      shift = length marker
      (textItems0, anchors) = composeInlines env (uInlines u)
      {- numbered per page, the mark of a note at the end of a chapter is one
      box of the reserved width (docs/adr/0383); one box too when its
      number is set flat (docs/adr/0381) -}
      textItems = case [(ch, n) | Frame _ (FEndNote ch _ _ n) _ <- uFrames u] of
        (ch, n) : _ | noteMarkBoxed (uStyle u) (ceVertical env) n -> markLabelBox env ch n textItems0
        _ -> textItems0
      items = marker <> textItems
      breaks = A.breakAligned (layoutAlign (uKind u)) (adjustedParams (uStyle u) (uParaStyle u) params) lineWidth items
      lines' = brLines breaks
   in Composed lines' (unitNotes fe u anchors) (unitSidenotes fe u shift anchors) (unitMarks fe u shift anchors) anchors items shift (brPositions breaks) 0 False Nothing

{- | The place of the text of a unit in the structure tree (docs/adr ADR
0183): none for the title of the notes at the end of a chapter, which is
an artifact.
-}
unitSiteOf :: Unit -> [Int]
unitSiteOf u = case uKind u of
  UNotesTitle _ -> []
  _ -> unitSite (uIndex u)

{- | The composition of the caption of a figure or a code block: the role
and size of the paragraph style caption (golem-driver ADR 0010), at the
place of the caption (docs/adr ADR 0183).
-}
captionEnv :: FlowEnv -> Unit -> ComposeEnv
captionEnv fe u =
  let (captionRole, cs) = paraFace (uStyle u) (feGeom fe) "caption"
   in (withFileExceptions fe (spanFile (uSpan u)) (withDocStyle (uStyle u) (lookEnv fe ((styleLook (uStyle u) (Just "caption") captionRole cs) {lkLang = lkLang (uLook u)})))) {ceAkiSet = akiSetOf (uStyle u) (Just "caption"), ceSizeSource = paraSizeSource (uStyle u) (Just "caption"), ceSite = captionSite (uIndex u)}

{- | The composition of the cells of a table: the role, the size, the aki
set and the keys of the paragraph style of its cells, table when it has
none (docs/adr/0262), no hanging punctuation (golem-driver ADR 0008), in
the language of the table (docs/adr ADR 0187).
-}
tableEnv :: FlowEnv -> Style -> Maybe Text -> Table -> ComposeEnv
tableEnv fe st lang t =
  let name = tableStyleName t
      (role, ts) = paraFace st (feGeom fe) name
   in (withDocStyle st (lookEnv fe ((styleLook st (Just name) role ts) {lkLang = lang}))) {ceHanging = False, ceAkiSet = akiSetOf st (Just name), ceSizeSource = paraSizeSource st (Just name)}

-- | The paragraph style of the cells of a table (docs/adr/0262).
tableStyleName :: Table -> Text
tableStyleName = fromMaybe "table" . tableStyle

-- | The size of the cells of a table (docs/adr/0262).
tableCellSize :: FlowEnv -> Style -> Table -> Sp
tableCellSize fe st t = snd (paraFace st (feGeom fe) (tableStyleName t))

{- | The composition of the notes of a unit: the paragraph style of
[notes] body-style in its document's style, or the body size of its
document's style without one (docs/adr/0366).
-}
noteEnv :: FlowEnv -> Style -> ComposeEnv
noteEnv fe st0 = let st = noteStyleFor PlaceFoot st0 in (withDocStyle st (lookEnv fe (noteBodyLook st (feGeom fe)))) {ceAkiSet = akiSetOf st (stNotesBodyStyle st), ceSizeSource = noteBodySource st}

{- | The look of the bodies of footnotes and of notes at the end of a
chapter (docs/adr/0366): the role, the size and the keys of the paragraph
style of [notes] body-style; the body role at the size of the grid without
one. The marks in the text do not take it.
-}
noteBodyLook :: Style -> PageGeometry -> Look
noteBodyLook st geom = case stNotesBodyStyle st of
  Nothing -> bodyLook st (pgFontSize geom)
  Just n -> uncurry (styleLook st (Just n)) (paraFace st geom n)

-- | The definition that decides the size of the bodies of notes (docs/adr/0366).
noteBodySource :: Style -> SizeSource
noteBodySource st = maybe SourceGrid (paraSizeSource st . Just) (stNotesBodyStyle st)

{- | The look of the title of the list of notes at the end of a chapter
and the definition of its size (docs/adr/0366): the role, the size and the
keys of the paragraph style of [notes] heading-style; those of the
headings of level 2 without one.
-}
notesTitleLook :: Text -> Style -> PageGeometry -> (Look, SizeSource)
notesTitleLook lang st geom = case stNotesHeadingStyle st of
  Nothing -> (uncurry (styleLook st Nothing) (headingFace lang st geom 2), SourceHeading 2)
  Just n -> (uncurry (styleLook st (Just n)) (paraFace st geom n), paraSizeSource st (Just n))

-- | The footnotes of a unit, each a paragraph of its own; none when the notes are at the end of the chapter (golem-driver ADR 0026).
unitNotes :: FlowEnv -> Unit -> [Golem.Layout.Japanese.Anchor] -> [(NoteId, [Line])]
unitNotes fe u anchors =
  [ (k, footnoteLines fe (withFileExceptions fe (spanFile (noteIdSpan k)) (noteEnv fe (uStyle u))) (uStyle u) k n nbody)
  | not (feNotesAtEnd fe),
    (_, k, n, nbody) <- noteAnchors anchors
  ]

{- | The lines of the body of a footnote (docs/adr/0263): its paragraphs
broken one after another at the measure, the mark of its number at the
start of the first (golem-driver ADR 0018), the others from the start of
the line without a mark, no indent and no space between them.
-}
footnoteLines :: FlowEnv -> ComposeEnv -> Style -> NoteId -> Int -> [[Inline]] -> [Line]
footnoteLines fe env st0 k n ps =
  let st = noteStyleFor PlaceFoot st0
   in concat
        [ brLines (breakParagraph (adjustedParams st (stNotesBodyStyle st) (feParams fe)) (const (feMeasure fe)) (labelled (fst (composeInlines env' is))))
        | (j, para) <- zip [0 :: Int ..] ps,
          let (env', is) =
                if j == 0
                  then (env {ceSite = noteSite k, ceLabelInlines = noteMarkCount st (ceVertical env) (noteIdSpan k) n, ceLabelLink = Just (LinkTo (DestNoteMark k))}, withNoteMark st (ceVertical env) (noteIdSpan k) n para)
                  else (env {ceSite = noteParagraphSite k j, ceLabelInlines = 0}, para),
          -- numbered per page, the mark at the start is one box of the reserved width (docs/adr/0383); set flat, one box too (docs/adr/0381)
          let labelled = if j == 0 && noteMarkBoxed st (ceVertical env) n then markLabelBox env' ChannelNote n else id
        ]

-- | The sidenotes of a unit: the item index of the marker after the list marker, the span and the lines.
unitSidenotes :: FlowEnv -> Unit -> Int -> [Golem.Layout.Japanese.Anchor] -> [(Int, SrcSpan, [PartLine])]
unitSidenotes fe u shift anchors = [(i + shift, sp, sidenoteLines fe (uStyle u) sp n (concat snBody)) | AnchorSidenote i n sp snBody <- anchors]

-- | The index marks of a unit, those of its notes and sidenotes with the item of their marker.
unitMarks :: FlowEnv -> Unit -> Int -> [Golem.Layout.Japanese.Anchor] -> [(Int, SrcSpan)]
unitMarks fe u shift anchors =
  [(i + shift, sp) | AnchorIndex i sp _ <- anchors]
    <> [(i + shift, sp) | not (feNotesAtEnd fe), AnchorNote i _ _ nbody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines env (concat nbody))]
    <> [(i + shift, sp) | AnchorSidenote i _ _ snBody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines env (concat snBody))]
  where
    env = noteEnv fe (uStyle u)

{- | The lines of a sidenote body: their size, the column width, the marker
first (golem-driver ADR 0006), in the role and size of the paragraph style
sidenote of the document (docs/adr ADR 0014), set as a paragraph of
sidenote (docs/adr/0367).
-}
sidenoteLines :: FlowEnv -> Style -> SrcSpan -> Int -> [Inline] -> [PartLine]
sidenoteLines fe st sp n snBody =
  let geom = feGeom fe
      (_, snSize', _) = sidenoteMetrics st geom
      prefix = sidenotePrefix fe sp n
      snEnv = (withFileExceptions fe (spanFile sp) (sidenoteEnv fe st)) {ceSite = sidenoteSite sp n, ceLabelInlines = length prefix}
      snParams = (adjustedParams st (Just "sidenote") (feParams fe)) {pEmergencyStretch = dimToSp snSize' (compEmergencyStretch (stComposition (piStyle (feInput fe))))}
      snMeasure = maybe 0 (rectW . fst) (pgSidenotes geom)
      -- numbered per page, the number at the start is one box of the reserved width (docs/adr/0383)
      labelled j = case ceSidenoteMarker (feBodyEnv fe) of
        MarkerNumber | j == 0, isJust (feMarkReserve fe) -> markLabelBox snEnv ChannelSidenote n
        _ -> id
   in -- the paragraph of the body, the number first, in the indents of sidenote (docs/adr/0367)
      partLines st geom "sidenote" snMeasure (\j width is -> brLines (breakParagraph snParams width (labelled j (fst (composeInlines (if j == 0 then snEnv else snEnv {ceLabelInlines = 0}) is))))) [prefix <> snBody]

-- | The composition of sidenotes: the role and size of the paragraph style sidenote of the document (docs/adr ADR 0014).
sidenoteEnv :: FlowEnv -> Style -> ComposeEnv
sidenoteEnv fe st =
  let (snRole, snSize', _) = sidenoteMetrics st (feGeom fe)
   in (withDocStyle st (lookEnv fe (styleLook st (Just "sidenote") snRole snSize'))) {ceAkiSet = akiSetOf st (Just "sidenote"), ceSizeSource = paraSizeSource st (Just "sidenote")}

-- | The number of a sidenote before its body; it is at the sidenote (golem-cli ADR 0008).
sidenotePrefix :: FlowEnv -> SrcSpan -> Int -> [Inline]
sidenotePrefix fe sp n = case ceSidenoteMarker (feBodyEnv fe) of
  -- numbered per page, the number is an inline of its own, the label (docs/adr/0383)
  MarkerNumber | isJust (feMarkReserve fe) -> [Text sp (T.pack (show n)), Text sp " "]
  MarkerNumber -> [Text sp (T.pack (show n) <> " ")]
  MarkerSymbol -> [Text sp "※ "]
  MarkerNone -> []

{- | The notes, sidenotes and index marks of composed inlines in the body
size of a document's style, by the line that holds them.
-}
anchoredByLine :: FlowEnv -> Style -> [Item] -> [Golem.Layout.Japanese.Anchor] -> [Line] -> (Map Int [(NoteId, [Line])], Map Int [(SrcSpan, [PartLine])], Map Int [SrcSpan])
anchoredByLine fe st items anchors ls =
  let lineOf = lineIndexOfItems items ls
      env = withDocStyle st (feBodyEnv fe)
      footnote k = footnoteLines fe (withFileExceptions fe (spanFile (noteIdSpan k)) env) (piStyle (feInput fe)) k
      marksIn b = [sp | AnchorIndex _ sp _ <- snd (composeInlines env (concat b))]
      atEnd = feNotesAtEnd fe
   in ( Map.fromListWith (flip (<>)) [(lineOf i, [(k, footnote k n b)]) | not atEnd, (i, k, n, b) <- noteAnchors anchors],
        Map.fromListWith (flip (<>)) [(lineOf i, [(sp, sidenoteLines fe st sp n (concat b))]) | AnchorSidenote i n sp b <- anchors],
        Map.fromListWith (flip (<>)) ([(lineOf i, [sp]) | AnchorIndex i sp _ <- anchors] <> [(lineOf i, sps) | not atEnd, AnchorNote i _ _ b <- anchors, let { sps = marksIn b }, not (null sps)] <> [(lineOf i, sps) | AnchorSidenote i _ _ b <- anchors, let sps = marksIn b, not (null sps)])
      )

{- | The frame of a figure turned onto a page of its own (golem-driver ADR
0034): the type area turned, its length along the lines, and the lines
along its height in horizontal text and its width in vertical text.
-}
figurePageFrame :: PageGeometry -> (Sp, Int)
figurePageFrame geom = (frameAlong, fromInteger (unSp (max 0 (frameAcross - pgFontSize geom)) `div` unSp (pgLinePitch geom)) + 1)
  where
    typeArea = pgTypeArea geom
    (frameAlong, frameAcross) = if pgVertical geom then (rectW typeArea, rectH typeArea) else (rectH typeArea, rectW typeArea)

{- | A figure placed: the image, its size, its caption and its exclusion
(golem-driver ADR 0005), with its errors, its notices and the index marks
of its caption.
-}
placeFigure :: FlowEnv -> Unit -> Figure -> P.FigureContent -> (PlacedFigure, [Diagnostic], [Diagnostic], [SrcSpan])
placeFigure fe u fig content =
  let inp = feInput fe
      geom = feGeom fe
      style = piStyle inp
      fs = pgFontSize geom
      pitch = pgLinePitch geom
      capacity = length (pgLineGrid geom)
      free = maybe False ((== AlignFree) . gridAlignment) (stPage style >>= pageGrid)
      height = fromIntegral (max 0 (capacity - 1)) * pitch + fs
      measure = feMeasure fe
      (frameAlong, frameLines) = figurePageFrame geom
      -- a figure turned onto a page of its own is set in its frame (golem-driver ADR 0034)
      turned = figRotate fig && isNothing (figWrap fig)
      -- the measure of the column, or of the frame (golem-driver ADR 0034)
      lineLen = if turned then frameAlong else measure
      -- the width along the lines as written, or the measure (docs/adr/0190); the evaluation has checked it (G02133)
      written = figureWidthSp fs lineLen <$> (figWidth fig >>= parseFigureWidth)
      -- along0: for a wrapped figure its width, for any other the width or the measure
      alongSp = fromMaybe lineLen written
      -- the pixels of an image, the crop box of a PDF figure after its rotation (golem-pdf ADR 0008)
      (w, h) = figureProportions content
      -- across the lines for each sp along them
      ratio = if pgVertical geom then w / h else h / w
      number = Map.lookup (uSpan u) (bookFigures (piBook inp))
      -- the paragraphs of the caption, the number before the first (docs/adr/0367);
      -- the separator only when some paragraph has text (Golem ADR 0372)
      paras = [is | Block _ _ _ (Paragraph _ is) <- figCaption fig]
      prefix = numberPrefix (piBook inp) Nothing (bookLanguage inp) (uSpan u) number (concat paras)
      captionParas = case paras of
        [] -> [prefix]
        p : ps -> (prefix <> p) : ps
      captionInlines = concat captionParas
      -- the caption in the role and size of the paragraph style caption (golem-driver ADR 0010)
      (_, cs) = paraFace (uStyle u) geom "caption"
      captionParams = (adjustedParams style (Just "caption") (feParams fe)) {pEmergencyStretch = dimToSp cs (compEmergencyStretch (stComposition style))}
      captionAnchors = snd (composeInlines (captionEnv fe u) captionInlines)
      -- the caption as paragraphs of caption over the inner width (docs/adr/0367)
      -- in the style of the file of the caption (docs/adr/0389)
      captionAt len = partLines (uStyle u) geom "caption" len (\_ width is -> brLines (breakParagraph captionParams width (fst (composeInlines (captionEnv fe u) is)))) captionParas
      -- the grid lines a caption of k lines takes: the fewest that hold it, its pitch in the body's ratio of pitch to size
      captionSpanOf k = if k == 0 then (pitch, 0) else let cb' = headingBlock fs pitch cs k 1 in (hbPitch cb', hbSpan cb')
      -- the caption in the measure before fitting (golem-driver ADR 0034)
      caption = captionAt (if isJust (figWrap fig) then alongSp else lineLen)
      captionMarks = [sp | AnchorIndex _ sp _ <- captionAnchors]
      -- the rows of the caption, those of space-between included (docs/adr/0367)
      n = partRows caption
      (cp, span') = captionSpanOf n
      -- the grid lines of the column, or of the frame
      gridLines
        | turned = frameLines
        | free = fromInteger (unSp height `div` unSp pitch)
        | otherwise = capacity
      fitOf len k s = fitFigure ratio len k pitch fs (if s == 0 then Nothing else Just s)
      -- step 1 of golem-driver ADR 0034 as docs/adr/0190 has it: along1 is along0 within the measure; fitted when the last along is shorter than along0
      (alongFit, across, fitted) = case figWrap fig of
        Nothing -> let (a, c, _) = fitOf (min alongSp lineLen) gridLines span' in (a, c, a < alongSp)
        Just _ -> (alongSp, Sp (floor (fromInteger (unSp alongSp) * ratio)), False)
      m = fromInteger (unSp (across + pitch - 1) `div` unSp pitch)
      -- the size the figure would take turned, to tell the writer (golem-driver ADR 0034)
      turnedArea =
        let s = snd (captionSpanOf (partRows (captionAt frameAlong)))
            (a, c, _) = fitOf frameAlong frameLines s
         in if s >= frameLines then 0 else a * c
      hint = if not turned && turnedArea > alongFit * across then "。rotate=true で回して一ページに置くと、より大きく置けます" else ""
      place' = if turned then "ページ" else "段"
      tooDeep = isNothing (figWrap fig) && n > 0 && span' >= gridLines
      notices =
        [ notice "G07039" (uSpan u) ("図版を" <> place' <> "に収めるため " <> T.pack (show (unSp alongFit * 100 `div` max 1 (unSp alongSp))) <> "% に縮めました" <> hint)
        | fitted,
          not tooDeep
        ]
      depth = if n > 0 then fromIntegral m * pitch + fromIntegral (n - 1) * cp + cs else across
      gap = dimToSp fs (stWrapGap style)
      ex = (\side -> exclusion side pitch gap alongSp depth) <$> figWrap fig
      -- the length across the lines before fitting (root ADR 0440)
      across0 = case figWrap fig of
        Nothing -> Sp (floor (fromInteger (unSp (min alongSp lineLen)) * ratio))
        Just _ -> Sp (floor (fromInteger (unSp alongSp) * ratio))
      noLine = isNothing (figWrap fig) && free && gridLines == 0
      -- a figure of no length across the lines draws nothing, so it is not placed (root ADR 0440)
      zeroErrs = [zeroAcrossError (uSpan u) | across0 == 0, not tooDeep, not noLine]
      errs = (<> zeroErrs) $ case (figWrap fig, ex) of
        (Nothing, _) | noLine -> [diagnostic "G07131" Error (uSpan u) "図版の一行分の領域が段に収まりません"]
        -- no wrapping on a page of columns (docs/adr ADR 0018)
        (Just _, _)
          | length (pgColumns geom) > 1 -> [diagnostic "G07026" Error (uSpan u) "段組みの版面では図版を回り込ませられません。wrap を外すか、columns を 1 にしてください"]
        (Just _, Just e)
          | isNothing written || measure - exWidth e < 8 * fs ->
              [diagnostic "G07022" Error (uSpan u) ("回り込む図版の幅が不正です。行の残りを本文の 8 字分以上にしてください: " <> fromMaybe "" (figWidth fig))]
          | (if free then depth + gap > height else exLines e > capacity) ->
              [diagnostic "G07023" Error (uSpan u) (if free then "回り込む図版の除外領域（長さ " <> L.ptText (depth + gap) <> "pt）が段の長さ " <> L.ptText height <> "pt を超えます" else "回り込む図版の除外領域が一ページの行数を超えます（" <> T.pack (show (exLines e)) <> " 行）")]
        -- a caption that leaves no line for the image (golem-driver ADR 0034)
        _
          | tooDeep -> [diagnostic "G07038" Error (uSpan u) ("図版のキャプションが" <> place' <> "の行数に達します（" <> T.pack (show span') <> " 行。" <> place' <> "は " <> T.pack (show gridLines) <> " 行）")]
          | otherwise -> []
      turn
        | not turned = Nothing
        | pgVertical geom = Just P.TurnedRight
        | otherwise = Just P.TurnedLeft
   in (PlacedFigure content alongFit across (figWrap fig) m caption cs cp span' ex (depth + gap) (figSource fig) (snd (figureKey fig)) (uSpan u) (if isJust (figWrap fig) then alongSp else lineLen) turn (uIndex u), errs, notices, captionMarks)

-- | The error of a figure whose length across the lines before fitting is 0 sp (root ADR 0440).
zeroAcrossError :: SrcSpan -> Diagnostic
zeroAcrossError sp = diagnostic "G07135" Error sp "図版の行の方向の長さと画像の縦横の比から求めた、行の送りの方向の長さが 0 になります"

{- | Whether the errors of a figure keep it off the pages: G07135, of a
figure that draws nothing (root ADR 0440).
-}
keepsOffPages :: [Diagnostic] -> Bool
keepsOffPages = any ((== DiagnosticCode "G07135") . diagCode)

{- | The paragraphs right after a wrapped figure, in order, composed beside
its exclusion: each by its index, with the line of the exclusion it starts
at. A paragraph with rules is not set beside a figure (golem-driver ADR
0027).
-}
composeBeside :: FlowEnv -> Map Int Sp -> Map Int Unit -> Int -> PlacedFigure -> IO [(Int, (Composed, Int))]
composeBeside fe widths unitAt i pf = go (i + 1) 0 0
  where
    itemPath u = case [take (n + 1) (uFrames u) | (n, Frame _ FItem _) <- zip [0 ..] (uFrames u)] of
      [] -> []
      contexts -> fromMaybe [] (listToMaybe (reverse contexts))
    sameItem u = compKeepParts (stComposition (piStyle (feInput fe))) == KeepColumn || itemPath u == maybe [] itemPath (Map.lookup i unitAt)
    ex = fromMaybe (error "composeBeside: figure without exclusion") (pfExclusion pf)
    pagePitch = pgLinePitch (feGeom fe)
    pageFace = pgFontSize (feGeom fe)
    free = maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle (feInput fe)) >>= pageGrid)
    outside = (0, pfExclusionLength pf)
    unitPitch u = fromMaybe pagePitch (paraStyle (uStyle u) (uParaStyle u) >>= resolvedParagraphPitch (uStyle u))
    narrowed u distance k =
      if free
        then intersects (rowExtent (distance + fromIntegral k * unitPitch u) (unitPitch u) (lkSize (uLook u))) outside
        else distance + fromIntegral k * pagePitch < fromIntegral (exLines ex) * pagePitch
    go j offset distance
      | not free && offset >= exLines ex = pure []
      | Just u@Unit {uKind = UPara _, uRules = (Nothing, Nothing), uBox = Nothing} <- Map.lookup j unitAt,
        sameItem u = do
          -- the exclusion and the frames of wrap around, the larger on each side (root ADR 0456)
          let taken k =
                let (s, e) = besideCut fe i j offset k
                    narrow = if narrowed u distance k then exWidth ex else 0
                 in if exSide ex == WrapStart then max narrow s + e else s + max narrow e
          c <- forceComposed (composeUnit fe widths (\k -> feMeasure fe - taken k - unitLineIndent pageFace (uKind u) k - unitEndIndent (uKind u)) u)
          ((j, (c, offset)) :) <$> go (j + 1) (offset + length (cLines c)) (distance + fromIntegral (length (cLines c)) * unitPitch u)
      | free, Just u <- Map.lookup j unitAt, Just controls <- besideControlFlow u = go (j + 1) offset (distance + sum [gap | FSpace gap <- controls])
      | otherwise = pure []

{- | The cuts of the frames of wrap around of line k of the paragraph j
set beside the wrapped figure of the unit i, from line @offset@ of its
side lines (root ADR 0456): by the unit of the paragraph in free
placement, by the unit of the figure on the grid, whose lines follow it.
-}
besideCut :: FlowEnv -> Int -> Int -> Int -> Int -> (Sp, Sp)
besideCut fe i j offset k =
  let free = maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle (feInput fe)) >>= pageGrid)
      (unit, line) = if free then (j, k) else (i, offset + k + 1)
   in fromMaybe (0, 0) (Map.lookup unit (asCuts (feAssumed fe)) >>= Map.lookup line)

-- | Paragraphs in one figure's side job; physical paragraph gaps may lie between them.
besideParagraphs :: Map Int Unit -> Map Int (Composed, Int) -> Int -> [Int]
besideParagraphs units beside = go . (+ 1)
  where
    go j
      | Map.member j beside = j : go (j + 1)
      | Just u <- Map.lookup j units, isJust (besideControlFlow u) = go (j + 1)
      | otherwise = []

{- | Controls with no shaped content preserve an active exclusion. Hard
layout blocks such as rules, boxes, tables and column changes end it.
-}
besideControlFlow :: Unit -> Maybe [FlowAt Sp]
besideControlFlow u = case uKind u of
  UGap n -> Just [FSpace n]
  UBreak kind -> Just [FBreak kind]
  UPageControl control ->
    Just
      [ case control of
          NoBreak -> FNoBreak (uSpan u)
          NoBreakLines n -> FNoBreakLines (uSpan u) (fromInteger (min (toInteger n) (toInteger (maxBound :: Int))))
          NeedLines n -> FNeedLines (uSpan u) n
          AdjustLines n -> FAdjustLines (uSpan u) n
      ]
  UBlank n -> Just [FBlank (uSpan u) (fromIntegral n)]
  UKeepNext n -> Just [FKeepNext (uSpan u) n]
  UHeldNeedLines {} -> Just []
  _ -> Nothing

-- | A composed unit evaluated, so that the work is done where it is run.
forceComposed :: Composed -> IO Composed
forceComposed c = evaluate (length (show (map lineRatio (cLines c))) + length (cNotes c) + length (show [map (lineRatio . ptLine) ls | (_, _, ls) <- cSidenotes c]) + length (cAnchors c) + length (cItems c)) >> pure c

{- | A table: every cell at the body size, no hanging punctuation
(golem-driver ADR 0008), with the notes, sidenotes and index marks of each
line of each row, the header row first.
-}
composeTable :: FlowEnv -> Int -> FileId -> Style -> Maybe Text -> Table -> Either TableRefusal (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [PartLine])], [SrcSpan])]])
composeTable fe i fid st lang t
  -- counted before any cell is composed (docs/adr/0224)
  | cells > maxTableCells = Left (TooManyCells cells)
  | otherwise = first LayoutRefused (composeTableCells fe i fid st lang t)
  where
    -- a header row of empty cells too, which is composed
    cells = length (tableHeader t) + sum (map length (tableRows t))

{- | The most cells of a table set in PDF, the header row's included
(docs/adr/0224, G07108).
-}
maxTableCells :: Int
maxTableCells = 100000

-- | Why a table is not set: too many cells (G07108), or its layout (G07041, G07114, G07115).
data TableRefusal
  = TooManyCells !Int
  | LayoutRefused ![TableError]
  deriving stock (Eq, Show)

{- | A composed table evaluated, so that the work is done where it is run
(docs/adr ADR 0299), without turning it into a string: the refusal, or the
widths of the columns, the heights in grid lines, and every line of every
cell with the alignments of its lines, each to weak head normal form, as
'forceComposed' evaluates the lines of a paragraph. A line's fields are
strict, so its line breaking is done.
-}
forceTable :: Either TableRefusal (SetTable, a) -> IO (Either TableRefusal (SetTable, a))
forceTable r = evaluate (either refusal (table . fst) r) >> pure r
  where
    refusal = \case
      TooManyCells n -> n `seq` ()
      LayoutRefused es -> spine es
    table st = spine (stWidths st) `seq` stHeaderLines st `seq` spine (stRowLines st) `seq` foldr cell () (stHeader st <> concat (stRows st))
    cell c rest = spine (scLines c) `seq` spine (scShifts c) `seq` rest
    -- every element to weak head normal form
    spine :: [b] -> ()
    spine = foldr seq ()

{- | The tables of the book composed as 'flowLines' composes them, in their
order, for the tests of 'forceTable' (docs/adr ADR 0299).
-}
composedTables :: PdfInput -> PageGeometry -> LoadedFonts -> [Either TableRefusal (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [PartLine])], [SrcSpan])]])]
composedTables inp geom fonts = [composeTable fe i (spanFile (uSpan u)) (uStyle u) (lkLang (uLook u)) t | (i, u@Unit {uKind = UTable t}) <- fst (flowUnits fe)]
  where
    fe = flowEnv inp geom fonts (Assumed Map.empty Map.empty Map.empty Map.empty)

composeTableCells :: FlowEnv -> Int -> FileId -> Style -> Maybe Text -> Table -> Either [TableError] (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [PartLine])], [SrcSpan])]])
composeTableCells fe i fid st lang t =
  let env = withFileExceptions fe fid (tableEnv fe st lang t)
      h = tableHeader t
      rows = tableRows t
      -- no break between the last two Japanese characters of a cell (golem-driver ADR 0037); each cell its place (docs/adr ADR 0183)
      cellOf r c is = first keepLastTwo (composeInlines env {ceSite = cellSite i r c} is)
      hCells = zipWith (cellOf 0) [0 ..] h
      rCells = [zipWith (cellOf r) [0 ..] row | (r, row) <- zip [1 ..] rows]
      rowAttached cells setCells height =
        let perCell = [anchoredByLine fe st items anchors (scLines sc) | ((items, anchors), sc) <- zip cells setCells]
         in [(concat [Map.findWithDefault [] k ns | (ns, _, _) <- perCell], concat [Map.findWithDefault [] k sn | (_, sn, _) <- perCell], concat [Map.findWithDefault [] k ms | (_, _, ms) <- perCell]) | k <- [0 .. height - 1]]
      {- a header row of empty cells: a table without a header row
      (golem-driver ADR 0031) -}
      blank = \case
        Box _ c -> T.all isSpace (bcText c)
        _ -> True
      header = if all (all blank . fst) hCells then [] else hCells
   in -- the gap between columns: one character of the cells (docs/adr/0262)
      case layoutTable (adjustedParams st (Just (tableStyleName t)) (feParams fe)) (feMeasure fe) (tableCellSize fe st t) (tableWidths t) (tableAligns t) (map fst header) (map (map fst) rCells) of
        Left e -> Left e
        Right set -> Right (set, rowAttached header (stHeader set) (stHeaderLines set) : zipWith3 rowAttached rCells (stRows set) (stRowLines set))

{- | The caption of a table (docs/adr/0262): the table number, the
separator of the language of the book (golem-driver ADR 0042) and the
caption, set as the caption of a code block over the measure.
-}
tableCaptionOf :: FlowEnv -> Unit -> Table -> CodeCaption
tableCaptionOf fe u t = captionLinesOf fe u 0 (Map.lookup (uSpan u) (bookTables (piBook (feInput fe)))) (tableCaption t)

{- | The caption of a code block: the listing number, the separator of the
language of the book (golem-driver ADR 0042) and the caption, set as the
caption of a figure over the width of the block (golem-driver ADR 0023).
-}
codeCaptionOf :: FlowEnv -> Unit -> Sp -> Code -> CodeCaption
codeCaptionOf fe u lead code = captionLinesOf fe u lead (Map.lookup (uSpan u) (bookListings (piBook (feInput fe)))) (codeCaption code)

-- | A caption of a code block or a table: its number, if any, and its inlines, over the measure less the lead.
captionLinesOf :: FlowEnv -> Unit -> Sp -> Maybe Text -> Maybe [Inline] -> CodeCaption
captionLinesOf fe u lead number = \case
  Nothing -> CodeCaption [] fs pitch 0 []
  Just is ->
    let inp = feInput fe
        captionInlines = bookNumberedTitle (piBook inp) Nothing (bookLanguage inp) (uSpan u) number is
        (_, cs) = paraFace (uStyle u) (feGeom fe) "caption"
        captionParams = (adjustedParams (piStyle inp) (Just "caption") (feParams fe)) {pEmergencyStretch = dimToSp cs (compEmergencyStretch (stComposition (piStyle inp)))}
        captionAnchors = snd (composeInlines (captionEnv fe u) captionInlines)
        -- a paragraph of caption over the measure less the lead (docs/adr/0367)
        -- in the style of the file of the caption (docs/adr/0389)
        ls = partLines (uStyle u) (feGeom fe) "caption" (feMeasure fe - lead) (\_ width xs -> brLines (breakParagraph captionParams width (fst (composeInlines (captionEnv fe u) xs)))) [captionInlines]
        cb = headingBlock fs pitch cs (partRows ls) 1
     in CodeCaption ls cs (hbPitch cb) (if null ls then 0 else hbSpan cb) [sp | AnchorIndex _ sp _ <- captionAnchors]
  where
    fs = pgFontSize (feGeom fe)
    pitch = pgLinePitch (feGeom fe)

-- | The code blocks of the units, set line by line, by the index of their units (golem-driver ADR 0017).
codeBlocksOf :: FlowEnv -> [(Int, Unit)] -> Map Int SetCode
codeBlocksOf fe units =
  Map.fromList [(i, codeBlockOf (feSourceAt fe) (feGeom fe) (feFonts fe) (feMeasure fe) (length (pgLineGrid (feGeom fe))) u lead code (codeCaptionOf fe u lead code)) | (i, u@Unit {uKind = UCode lead code}) <- units]

-- | G07027: the text of a list item leaves 8 characters of the type area (golem-driver ADR 0013).
listTooDeep :: SrcSpan -> Diagnostic
listTooDeep sp = diagnostic "G07027" Error sp "リストの入れ子が深く、項目の本文の行長が足りません。行長を本文の文字の大きさの 8 字分以上残してください"

-- | G07027 for each paragraph and term in lists too deep for the measure.
deepListErrors :: FlowEnv -> Map Int Sp -> [(Int, Unit)] -> [Diagnostic]
deepListErrors fe widths units =
  nub
    [ listTooDeep (uSpan u)
    | (_, u) <- units,
      not (null (uLists u)),
      case uKind u of
        UPara _ -> True
        UTerm _ -> True
        _ -> False,
      feMeasure fe - listsOuter widths u < 8 * pgFontSize (feGeom fe)
    ]

-- | The units composed, by their indices: what the numbering of the lines reads.
data ComposedUnits = ComposedUnits
  { cuUnits :: Map Int Unit,
    -- | the paragraphs set beside a wrapped figure, with the line of the exclusion they start at
    cuBesides :: Map Int (Composed, Int),
    -- | the figures with their errors, notices and index marks
    cuFigures :: Map Int (PlacedFigure, [Diagnostic], [Diagnostic], [SrcSpan]),
    -- | the other units of text
    cuSingles :: Map Int Composed,
    cuTables :: Map Int (Either TableRefusal (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [PartLine])], [SrcSpan])]])),
    cuCodeBlocks :: Map Int SetCode,
    cuBesideControls :: Set.Set Int
  }

{- | The flow numbered so far, in document order (golem-driver ADR 0009):
the next line id, the flow, the set lines, the figures and the heading
blocks by their first lines, the errors, the lines and the geometry of
tables, and the headings and the table of contents entries by their lines.
-}
data Numbered = Numbered
  { nuNext :: Int,
    nuFlow :: [FlowAt Sp],
    nuLines :: Map Int SetLine,
    nuFigures :: Map Int PlacedFigure,
    nuHeadings :: Map Int HeadingBlock,
    nuErrors :: [Diagnostic],
    nuTableLines :: Map Int [(Int, SetLine)],
    nuTables :: Map Int TableGeometry,
    nuHeadingSpans :: Map Int SrcSpan,
    -- | the heading, the end of the title and the unit of each table of contents entry, by its last line
    nuTocLines :: Map Int (SrcSpan, Sp, Int),
    -- | the caption of each table by its first grid line (docs/adr/0262)
    nuTableCaptions :: Map Int CodeCaption,
    -- | each box by its id, and its settings (docs/adr/0271)
    nuBoxes :: Map Int (BoxInfo, UnitBox),
    nuWrappedBefore :: Map Int Sp
  }

-- | The label of a unit, on its first line.
unitLabel :: Unit -> [Text]
unitLabel u = maybe [] pure (uLabel u)

-- | How far the ruby and kenten of a line reach toward the line before (golem-driver ADR 0033).
lineReach :: FlowEnv -> Line -> Sp
lineReach fe = lineOverhang (pgVertical (feGeom fe)) (pgFontSize (feGeom fe)) (emBoxCentralOf (feFonts fe))

{- | The lines of a paragraph-like unit numbered from an id, with the notes,
sidenotes and index marks of each line; indentOf k is the indent of line k.
-}
numberedLines :: FlowEnv -> Int -> Unit -> Composed -> (Int -> Sp) -> ([LineBox], Map Int SetLine)
numberedLines fe nextId u c indentOf =
  let ls = cLines c
      ids = [nextId .. nextId + length ls - 1]
      size = lkSize (uLook u)
      -- notes belong to the line containing their anchor
      lineOfItem index
        | cReflowed c = min (max 0 (length ls - 1)) (length (takeWhile (< index) (cBreakPositions c)))
        | otherwise = lineIndexOfItems (cItems c) ls index
      noteLines = Map.fromListWith (flip (<>)) [(lineOfItem (i + cShift c), [(k, nls)]) | ((i, _, _, _), (k, nls)) <- zip (noteAnchors (cAnchors c)) (cNotes c), not (cReflowed c) || i + cShift c >= cItemStart c]
      sidenoteLinesOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [(sp, sls)]) | (i, sp, sls) <- cSidenotes c, not (cReflowed c) || i >= cItemStart c]
      marksOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [sp]) | (i, sp) <- cMarks c, not (cReflowed c) || i >= cItemStart c]
      boxes = [LineBox lid [NoteBody key (length nls) | (key, nls) <- Map.findWithDefault [] k noteLines] (if k == 0 && cItemStart c == 0 then unitLabel u else []) (Map.findWithDefault [] k marksOf) (lineReach fe l) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
      -- a line not justified moves by its alignment (docs/adr/0189)
      shiftOf k = A.lineShift (layoutAlign (uKind u)) (k == length ls - 1)
      set = Map.fromList [(lid, SetLine l size (maybe (indentOf k) (!! k) (cActualIndents c) + shiftOf k l) (Map.findWithDefault [] k noteLines) (Map.findWithDefault [] k sidenoteLinesOf) (spineOf (uKind u))) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
   in (boxes, set)

{- | A rule of a paragraph or heading for pagination (golem-driver ADR
0027): the spaces at the size of the grid, the inner space next to the
paragraph, and the room out of the column when it may go out.
-}
ruleSide :: PageGeometry -> Bool -> RuleSpec -> RuleSide
ruleSide geom before spec =
  let sp = maybe 0 (dimToSp (pgFontSize geom))
      (inner, outer)
        | before = (sp (rsSpaceAfter spec), sp (rsSpaceBefore spec))
        | otherwise = (sp (rsSpaceBefore spec), sp (rsSpaceAfter spec))
   in RuleSide inner outer (rsWeight spec) (isJust (rsSpaceBefore spec) || isJust (rsSpaceAfter spec)) (if rsKeepInColumn spec then Nothing else Just (marginAcross geom before))

{- | A grid line of space after a code block with a background, a band or a
border whose next line reaches it with ruby or kenten (golem-driver ADR
0033); the code blocks of the flow are those of the units, in order.
-}
spaceAfterCode :: Sp -> Sp -> [CodeInfo] -> [FlowAt Sp] -> [FlowAt Sp]
spaceAfterCode pitch fs infos = \case
  f@FCode {} : remaining -> case infos of
    ci : more -> f : [FSpace pitch | painted ci, reaches ci remaining] <> spaceAfterCode pitch fs more remaining
    [] -> f : spaceAfterCode pitch fs [] remaining
  f : remaining -> f : spaceAfterCode pitch fs infos remaining
  [] -> []
  where
    painted ci = isJust (ciBackground ci) || not (null (ciBands ci)) || isJust (ciBorder ci)
    reaches ci remaining = case remaining of
      next : _ | Just l <- firstLineOf next -> reachesBackground pitch fs (maybe 0 snd (ciBorder ci)) (lbOverhang l)
      _ -> False
    firstLineOf = \case
      FBoxed {fbBody = f : _} -> firstLineOf f
      FRuled {frBody = RuledLines _ (l : _)} -> Just l
      FRuled {frBody = RuledHeading _ _ (l : _)} -> Just l
      FParagraph _ (l : _) -> Just l
      FStanza _ vs | l : _ <- concat vs -> Just l
      FHeading {fhLines = l : _} -> Just l
      FDefTerm (l : _) -> Just l
      FTable {ftSpaceBefore = 0, ftHeader = l : _} -> Just l
      _ -> Nothing

-- | Numbers the lines of the next unit in document order.
numberUnit :: FlowEnv -> ComposedUnits -> Numbered -> (Int, Unit) -> Numbered
numberUnit fe cu nb (i, u) = case uKind u of
  UTable t -> maybe nb (\r -> numberTable fe u t r nb) (Map.lookup i (cuTables cu))
  _ -> headingAndTocLines (pgFontSize (feGeom fe)) cu (nuNext nb) i u (numberOther fe cu nb (i, u))

-- | Numbers the lines of a table, or adds its errors (G07108, G07041, G07042, G07114, G07115, G07116).
numberTable :: FlowEnv -> Unit -> Table -> Either TableRefusal (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [PartLine])], [SrcSpan])]]) -> Numbered -> Numbered
numberTable fe u tbl r nb = case r of
  Left (TooManyCells n) ->
    nb {nuErrors = nuErrors nb <> [diagnostic "G07108" Error (uSpan u) ("表のセルが多すぎて PDF に組めません（" <> T.pack (show n) <> " 個、上限は " <> T.pack (show maxTableCells) <> " 個）")]}
  Left (LayoutRefused errs) -> nb {nuErrors = nuErrors nb <> map layoutError errs}
  Right (t, atts)
    | not (null tall && null captionTall) ->
        nb
          { nuErrors =
              nuErrors nb
                <> [diagnostic "G07042" Error (uSpan u) ("表の " <> T.pack (show row) <> " 行目が見出しの行とともに一ページに収まりません") | row <- tall]
                <> captionTall
          }
    | otherwise ->
        let cap = tableCaptionOf fe u tbl
            capIds = if below then [rowsEnd .. rowsEnd + capN - 1] else [nextId .. nextId + capN - 1]
            rowsStart = if below then nextId else nextId + capN
            rowsEnd = rowsStart + sum heights
            starts = scanl (+) rowsStart heights
            -- the grid line of the j-th line of a row: its own at the size of the grid, else where it starts
            gridOf j = if sized then j else min (gridLines j - 1) (unSp (fromIntegral j * cellPitch) `div'` unSp pitch)
            rowsOut =
              [ ( [ LineBox lid [NoteBody key (length nls) | (key, nls) <- ns] (if lid == nextId then unitLabel u else []) ms (maximum (0 : [lineReach fe l | c <- cells, (j, l) <- zip [0 :: Int ..] (scLines c), gridOf j == k]))
                  | (k, lid) <- zip [0 ..] ids,
                    let here = [a | (j, a) <- zip [0 :: Int ..] att, gridOf j == k]
                        ns = concat [x | (x, _, _) <- here]
                        ms = concat [x | (_, _, x) <- here]
                  ],
                  Map.fromList [(lid, SetLine emptyLine fs 0 (concat [x | (j, (x, _, _)) <- zip [0 :: Int ..] att, gridOf j == k]) (concat [x | (j, (_, x, _)) <- zip [0 :: Int ..] att, gridOf j == k]) Nothing) | (k, lid) <- zip [0 ..] ids],
                  Map.fromList [(lid, [(if sized then 0 else j, SetLine l ts (scOffset c + sh) [] [] Nothing) | c <- cells, (j, (l, sh)) <- zip [0 :: Int ..] (zip (scLines c) (scShifts c)), gridOf j == k]) | (k, lid) <- zip [0 ..] ids]
                )
              | (start, h, cells, att) <- zip4 starts heights (stHeader t : stRows t) atts,
                let ids = [start .. start + h - 1]
              ]
            (headerBoxes, rowBoxes) = case [bs | (bs, _, _) <- rowsOut] of
              (hb : rbs) -> (hb, rbs)
              [] -> ([], [])
            -- the grid lines of the caption, with its index marks on the first; the label on the first line of the table
            captionBoxes = [LineBox lid [] (if lid == nextId then unitLabel u else []) (if k == (0 :: Int) then ccMarks cap else []) 0 | (k, lid) <- zip [0 ..] capIds]
            {- a grid line of space before and after a table; none
            after a heading, one between two tables (golem-driver ADR 0031) -}
            spaceBefore :: Int
            spaceBefore = case reverse (nuFlow nb) of
              (FHeading {} : _) -> 0
              (FRuled {frBody = RuledHeading {}} : _) -> 0
              (FSpace _ : FTable {} : _) -> 0
              _ -> 1
         in nb
              { nuNext = nextId + capN + sum heights,
                nuFlow = nuFlow nb <> [FTable rowsStart (fromIntegral spaceBefore * pitch) headerBoxes rowBoxes captionBoxes below, FSpace pitch],
                nuLines = Map.unions (nuLines nb : Map.fromList [(lid, SetLine emptyLine fs 0 [] [] Nothing) | lid <- capIds] : [m | (_, m, _) <- rowsOut]),
                nuTableLines = Map.unions (nuTableLines nb : [m | (_, _, m) <- rowsOut]),
                nuTables = Map.insert rowsStart (TableGeometry (stWidth t) 0 0 (sum heights)) (nuTables nb),
                nuTableCaptions = Map.union (Map.fromList [(c0, cap) | c0 <- take 1 capIds]) (nuTableCaptions nb)
              }
    where
      -- the grid lines of a row of m lines: the least that hold them, as a caption (docs/adr/0262)
      gridLines m = if sized then max 1 m else hbSpan (headingBlock fs pitch ts m 1)
      -- a table without a header row takes no grid line for it (golem-driver ADR 0031)
      headerLines = if null (stHeader t) then 0 else gridLines (stHeaderLines t)
      heights = headerLines : map gridLines (stRowLines t)
      rowLines = map gridLines (stRowLines t)
      tall = [row | (row, h) <- zip [1 :: Int ..] rowLines, h > capacity || headerLines > capacity || toInteger headerLines + toInteger h > retentionCapacity]
      capN = ccSpan (tableCaptionOf fe u tbl)
      -- the row the caption is kept with: the first above, the last below; none when it is too tall itself
      touching = if below then lastOf rowLines else take 1 rowLines
      lastOf xs = [last xs | not (null xs)]
      captionTall =
        [ diagnostic "G07116" Error (uSpan u) ("表のキャプションが、" <> (if below then "見出しの行と本体の最後の行" else "見出しの行と本体の最初の行") <> "とともに一つの段に収まりません")
        | capN > 0,
          all (\h -> h <= capacity && headerLines <= capacity && toInteger headerLines + toInteger h <= retentionCapacity) touching,
          capN > capacity || (compKeepParts (stComposition (piStyle (feInput fe))) == KeepColumn && toInteger headerLines + sum (map toInteger touching) + toInteger capN > retentionCapacity)
        ]
  where
    nextId = nuNext nb
    fs = pgFontSize (feGeom fe)
    pitch = pgLinePitch (feGeom fe)
    ts = tableCellSize fe (uStyle u) tbl
    sized = ts == fs
    cellPitch = Sp (round (toRational (unSp pitch) * toRational (unSp ts) / toRational (unSp fs)))
    div' a b = fromInteger (a `div` b)
    below = stTableCaption (piStyle (feInput fe)) == CaptionBelow
    capacity = length (pgLineGrid (feGeom fe))
    -- In one column the header repeats on every continuation page, so the header
    -- and each row must fit one column even within page or spread retention.
    retentionCapacity = toInteger capacity * toInteger columns
    columns = case compKeepParts (stComposition (piStyle (feInput fe))) of
      KeepColumn -> 1
      _ -> max 1 (length (pgColumns (feGeom fe)))
    emptyLine = Line [] 0 0 0 (0, 0) 0 (0, 0) Nothing AdjustUniform
    layoutError = \case
      ColumnsTooWide mn avail -> diagnostic "G07041" Error (uSpan u) ("表の列の最小の幅の合計（" <> L.mmText mn <> "）が使える幅（" <> L.mmText avail <> "）に収まりません")
      WidthsTooWide total avail -> diagnostic "G07114" Error (uSpan u) ("表の列に指定した幅の合計（" <> L.mmText total <> "）が、列の間隔を除いた行長（" <> L.mmText avail <> "）を超えます")
      ColumnTooNarrow c w mn -> diagnostic "G07115" Error (uSpan u) ("表の " <> T.pack (show (c + 1)) <> " 列目に指定した幅（" <> L.mmText w <> "）が、列のセルの最小の幅（" <> L.mmText mn <> "）より狭くなっています")

-- | Headings and table of contents entries by their lines (golem-driver ADR 0009); @fs@ is the font size of the grid.
headingAndTocLines :: Sp -> ComposedUnits -> Int -> Int -> Unit -> Numbered -> Numbered
headingAndTocLines fs cu nextId i u nb = case uKind u of
  UHeading {} -> nb {nuHeadingSpans = Map.insert nextId (uSpan u) (nuHeadingSpans nb)}
  UTocEntry _ hs _ _
    | Just c <- Map.lookup i (cuSingles cu),
      ls@(_ : _) <- cLines c ->
        let end = case [off + w | (Box w _, off) <- placeLine (last ls)] of
              [] -> 0
              ends -> last ends
         in nb {nuTocLines = Map.insert (nextId + length ls - 1) (hs, unitLineIndent fs (uKind u) (length ls - 1) + end, i) (nuTocLines nb)}
  _ -> nb

-- | Numbers the lines of a unit that is not a table: figures, code blocks, the controls of the flow and the units of text.
numberOther :: FlowEnv -> ComposedUnits -> Numbered -> (Int, Unit) -> Numbered
numberOther fe cu nb (i, u)
  | Set.member i (cuBesideControls cu) = nb
  | Map.member i (cuBesides cu) = nb -- set beside its figure
  | Just Unit {uKind = UGap _} <- Map.lookup i (cuUnits cu),
    Map.member (i - 1) (cuBesides cu) || Map.member (i - 1) (cuFigures cu),
    Map.member (i + 1) (cuBesides cu) =
      nb -- included in the figure's side job
  | otherwise = case uKind u of
      UFigure _ -> maybe nb (\placed -> numberFigure fe cu i u placed nb) (Map.lookup i (cuFigures cu))
      UGap n -> nb {nuFlow = nuFlow nb <> [FSpace n]}
      UCode {} -> maybe nb (\cb -> numberCode (pgLinePitch (feGeom fe)) u cb nb) (Map.lookup i (cuCodeBlocks cu))
      UBreak k -> nb {nuFlow = nuFlow nb <> [FBreak k]}
      -- Facing pages align start parity; single pages start normally (root ADR 0400).
      USection k start -> nb {nuFlow = nuFlow nb <> [FSection (OfSection k) (if pgLayout (feGeom fe) == SinglePage then BreakPage else maybe BreakPage (\s -> if odd s then BreakRecto else BreakVerso) start)]}
      UPageControl c ->
        let control = case c of
              NoBreak -> FNoBreak (uSpan u)
              NoBreakLines k -> FNoBreakLines (uSpan u) (fromInteger (min (toInteger k) (toInteger (maxBound :: Int))))
              NeedLines k -> FNeedLines (uSpan u) k
              AdjustLines k -> FAdjustLines (uSpan u) k
         in nb {nuFlow = nuFlow nb <> [control]}
      UColumns set -> nb {nuFlow = nuFlow nb <> [maybe FRestoreColumns (FSwitchColumns . fmap (\n -> fromIntegral n * pgLinePitch (feGeom fe))) set]}
      UBlank k -> nb {nuFlow = nuFlow nb <> [FBlank (uSpan u) (fromIntegral k)]}
      UKeepNext k -> nb {nuFlow = nuFlow nb <> [FKeepNext (uSpan u) k]}
      UHeldNeedLines {} -> nb
      _ -> numberText fe (partsAround cu i u) u (cuSingles cu Map.! i) nb

{- | Numbers a figure; a wrapped figure with the lines beside it, and the
rest of a paragraph cut short continues after it.
-}
numberFigure :: FlowEnv -> ComposedUnits -> Int -> Unit -> (PlacedFigure, [Diagnostic], [Diagnostic], [SrcSpan]) -> Numbered -> Numbered
numberFigure fe cu i u (pf, ferrs, _, fmarks) nb = case pfExclusion pf of
  -- a figure of no rows does not reach the pagination; it has its error (root ADR 0440 I1)
  _
    | keepsOffPages ferrs || (not (null ferrs) && isNothing (pfTurn pf) && pfImageLines pf + pfCaptionSpan pf == 0) ->
        nb {nuErrors = nuErrors nb <> ferrs}
  Just ex
    | null ferrs ->
        let besides = cuBesides cu
            unitAt = cuUnits cu
            fs = pgFontSize (feGeom fe)
            pagePitch = pgLinePitch (feGeom fe)
            free = maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle (feInput fe)) >>= pageGrid)
            excluded = (0, pfExclusionLength pf)
            unitPitch j = fromMaybe pagePitch (paraStyle (uStyle (unitAt Map.! j)) (uParaStyle (unitAt Map.! j)) >>= resolvedParagraphPitch (uStyle (unitAt Map.! j)))
            paras = [(j, c, off) | j <- besideParagraphs unitAt besides i, let (c, off) = besides Map.! j]
            gapBetween prior j = sum [gap | k <- [prior + 1 .. j - 1], Just Unit {uKind = UGap gap} <- [Map.lookup k unitAt]]
            parasAt =
              snd
                ( mapAccumL
                    ( \(prior, distance) (j, c, off) ->
                        let gap = gapBetween prior j
                            start = distance + gap
                         in ((j, start + fromIntegral (length (cLines c)) * unitPitch j), (j, c, off, start, gap))
                    )
                    (i, 0)
                    paras
                )
            narrowed j off distance k
              | free = intersects (rowExtent (distance + fromIntegral k * unitPitch j) (unitPitch j) (lkSize (uLook (unitAt Map.! j)))) excluded
              | otherwise = off + k < exLines ex
            -- the frames of wrap around at the start of the line too, the larger (root ADR 0456)
            indentOf j off distance k = max (if pfWrap pf == Just WrapStart && narrowed j off distance k then exWidth ex else 0) (fst (besideCut fe i j off k))
            -- beside the figure the paragraph indent adds to the exclusion (docs/adr ADR 0006)
            go (nid, boxAcc, setAcc, gapAcc) (j, c, off, distance, gap) =
              let (bs, set) = numberedLines fe nid (unitAt Map.! j) c (\k -> indentOf j off distance k + unitLineIndent fs (uKind (unitAt Map.! j)) k)
                  before = if gap > 0 && not (null bs) then Map.singleton nid gap else Map.empty
               in (nid + length (cLines c), boxAcc <> bs, Map.union setAcc set, Map.union gapAcc before)
            tooNarrow =
              [ if null (uLists (unitAt Map.! j))
                  then diagnostic "G07028" Error (uSpan (unitAt Map.! j)) "回り込む図版の脇で、字下げを引くと行が残りません"
                  else listTooDeep (uSpan (unitAt Map.! j))
              | (j, c, off, distance, _) <- parasAt,
                any (\k -> if free && isJust (cActualIndents c) then lineTarget (cLines c !! k) <= 0 else feMeasure fe - (if narrowed j off distance k then exWidth ex else 0) - unitLineIndent fs (uKind (unitAt Map.! j)) k - unitEndIndent (uKind (unitAt Map.! j)) <= 0) [0 .. length (cLines c) - 1]
              ]
            (nextId', allBoxes, sets, wrappedBefore) = foldl go (nextId + 1, [], Map.empty, Map.empty) parasAt
            narrowCount = if free then length (takeWhile id [narrowed j off distance k | (j, c, off, distance, _) <- parasAt, k <- [0 .. length (cLines c) - 1]]) else exLines ex
            (beside, continued) = splitAt narrowCount allBoxes
            extent = if free then pfExclusionLength pf else fromIntegral (exLines ex) * pagePitch
         in nb
              { nuNext = nextId',
                nuFlow = nuFlow nb <> [FWrapped nextId extent (unitLabel u) fmarks beside] <> [FContinued (maybe defaultKeep (\(j, _, _) -> keepOf (unitAt Map.! j)) (listToMaybe (reverse paras))) continued | not (null continued)],
                nuLines = Map.union (nuLines nb) sets,
                nuFigures = Map.insert nextId pf (nuFigures nb),
                nuErrors = nuErrors nb <> tooNarrow,
                nuWrappedBefore = Map.union (nuWrappedBefore nb) wrappedBefore
              }
  -- a turned figure takes a page of its own (golem-driver ADR 0034)
  _ | isJust (pfTurn pf) -> placed (FPageFigure nextId (unitLabel u) fmarks)
  _ -> placed (FFigure nextId (fromIntegral (pfImageLines pf + pfCaptionSpan pf) * pgLinePitch (feGeom fe)) (unitLabel u) fmarks)
  where
    nextId = nuNext nb
    placed f = nb {nuNext = nextId + 1, nuFlow = nuFlow nb <> [f], nuFigures = Map.insert nextId pf (nuFigures nb), nuErrors = nuErrors nb <> ferrs}

-- | Numbers the rows of a code block; the label and the index marks of the caption on the first row (golem-driver ADR 0023).
numberCode :: Sp -> Unit -> SetCode -> Numbered -> Numbered
numberCode pitch u cb nb =
  let nextId = nuNext nb
      ids = [nextId .. nextId + length (cbRows cb) - 1]
      boxes = [LineBox lid [] (if k == 0 then unitLabel u else []) (if k == 0 then cbMarks cb else []) 0 | (k, lid) <- zip [0 :: Int ..] ids]
      set = Map.fromList [(lid, SetLine l (cbSize cb) (cbIndent cb) [] [] Nothing) | (lid, l) <- zip ids (cbRows cb)]
      info = cbInfo cb
   in nb {nuNext = nextId + length ids, nuFlow = nuFlow nb <> [FCode (ciGeometry info) (fromIntegral (ciCaptionSpan info) * pitch) (cbFirstRows cb) (isJust (ciContinued info)) boxes], nuLines = Map.union (nuLines nb) set}

{- | Numbers the lines of a unit of text: a paragraph, a heading, the title
of the notes, a term, an entry; a heading too large for the type area is
G07024.
-}

{- | Whether a unit is the first and the last unit of its block: the units
of a paragraph of a style that keeps its lines share the span of the
paragraph (docs/adr/0261).
-}
partsAround :: ComposedUnits -> Int -> Unit -> (Bool, Bool)
partsAround cu i u =
  let same j = maybe False (\v -> uSpan v == uSpan u && isParaKind (uKind v)) (Map.lookup j (cuUnits cu))
   in (not (same (i - 1)), not (same (i + 1)))
  where
    isParaKind = \case
      UPara _ -> True
      _ -> False

{- | The keep of a paragraph of a style (docs/adr/0261): keep-first-lines,
keep-last-lines and keep-all-lines, those of body when not written.
-}
keepOf :: Unit -> Keep
keepOf u = case paraStyle (uStyle u) (uParaStyle u) of
  Just d -> Keep (fromMaybe 2 (psKeepFirstLines d)) (fromMaybe 2 (psKeepLastLines d)) (fromMaybe False (psKeepAllLines d))
  Nothing -> defaultKeep

{- | Whether a paragraph takes keep-with-next and page-break
(docs/adr/0261): one at the top of the document, not in a list, a
definition list, a note at the end of a chapter or a list of a channel.
-}
topParagraph :: Unit -> Bool
topParagraph u = null (uLists u) && all (\(Frame _ k _) -> k == FPara) (uFrames u)

{- | The start of a paragraph of a style with page-break, and its
keep-with-next (docs/adr/0261), for a paragraph at the top of the document.
-}
paraStartAndKeep :: Unit -> (Maybe BreakKind, Int)
paraStartAndKeep u
  | not (topParagraph u) = (Nothing, 0)
  | otherwise = case paraStyle (uStyle u) (uParaStyle u) of
      Just d ->
        ( case psPageBreak d of
            Just StartColumn -> Just BreakColumn
            Just StartPage -> Just BreakPage
            Just StartRecto -> Just BreakRecto
            Just StartVerso -> Just BreakVerso
            _ -> Nothing,
          fromMaybe 0 (psKeepWithNext d)
        )
      Nothing -> (Nothing, 0)

numberText :: FlowEnv -> (Bool, Bool) -> Unit -> Composed -> Numbered -> Numbered
numberText fe (firstOfBlock, lastOfBlock) u c nb =
  let inp = feInput fe
      geom = feGeom fe
      fs = pgFontSize geom
      pitch = pgLinePitch geom
      capacity = length (pgLineGrid geom)
      nextId = nuNext nb
      ls = cLines c
      -- a line under a frame of wrap around at the start of its column starts after it (root ADR 0438)
      startCut k = maybe 0 fst (Map.lookup (uIndex u) (asCuts (feAssumed fe)) >>= Map.lookup k)
      (boxes, set) = numberedLines fe nextId u c (\k -> unitLineIndent fs (uKind u) k + startCut k)
      size = lkSize (uLook u)
      headingLevel = case uKind u of
        UHeading l _ _ -> Just l
        UNotesTitle _ -> Just 2
        _ -> Nothing
      least = maybe 1 (headingLines (bookLanguage inp) (uStyle u) capacity) headingLevel
      alignment = maybe HeadingCenter hsBlockAlign (headingLevel >>= flip Map.lookup (stHeadings (uStyle u)))
      hb = headingBlockAligned alignment fs pitch size (length ls) least
      ruledOf = FRuled nextId (ruleSide geom True <$> fst (uRules u)) (ruleSide geom False <$> snd (uRules u)) False (RuleGrid pitch fs) 0
      kp = keepOf u
      flowOf = case uKind u of
        UHeading _ _ recto | uRules u /= (Nothing, Nothing) -> [ruledOf (RuledHeading recto (fromIntegral (hbSpan hb) * pitch) boxes)]
        UPara _ | uRules u /= (Nothing, Nothing) -> [ruledOf (RuledLines kp boxes)]
        -- an entry of the table of contents with the rules of its style (docs/adr/0264)
        UTocEntry {} | uRules u /= (Nothing, Nothing) -> [ruledOf (RuledLines kp boxes)]
        UHeading l _ recto -> [FHeading l recto (fromIntegral (hbSpan hb) * pitch) boxes]
        UNotesTitle _ -> [FHeading 2 False (fromIntegral (hbSpan hb) * pitch) boxes]
        UTerm _ -> [FDefTerm boxes]
        _ -> [FParagraph kp boxes]
      -- the start before the first part of a paragraph and the keep-with-next after its last (docs/adr/0261)
      (start, keepNext) = case uKind u of
        UPara _ -> paraStartAndKeep u
        _ -> (Nothing, 0)
      before = [FSection (OfParagraph (uSpan u)) k | firstOfBlock, Just k <- [start]]
      after = [FKeepNext (uSpan u) keepNext | lastOfBlock, keepNext > 0]
      -- a paragraph with a box is a box of its own; joinBoxes joins those one after the other (docs/adr/0271)
      around = maybe 0 (boxLinesAround pitch fs . ubPadding) (uBox u)
      boxed fs' = case uBox u of
        Just _ -> [FBoxed nextId (fromIntegral around * pitch) (fromIntegral around * pitch) fs']
        Nothing -> fs'
      lastLine = nextId + length ls - 1
      -- a verse line after the first joins the stanza of the lines before it (docs/adr/0180)
      flow' = case (uStanza u, unsnoc (nuFlow nb)) of
        (Just i, Just (earlier, FStanza k' vs)) | i > 0 -> earlier <> [FStanza k' (vs <> [boxes])] <> after
        -- in a box (docs/adr/0271)
        (Just i, Just (earlier, FBoxed bid kb ka [FStanza k' vs])) | i > 0 -> earlier <> [FBoxed bid kb ka [FStanza k' (vs <> [boxes])]] <> after
        (Just _, _) -> nuFlow nb <> before <> boxed [FStanza kp [boxes]] <> after
        _ -> nuFlow nb <> before <> boxed flowOf <> after
      boxes' = case (uBox u, uStanza u, unsnoc (nuFlow nb)) of
        (Just _, Just i, Just (_, FBoxed {fbId = bid})) | i > 0 -> Map.adjust (\(bi, ub) -> (bi {bxLast = lastLine}, ub)) bid (nuBoxes nb)
        (Just ub, _, _) -> Map.insert nextId (boxInfoOf (uStyle u) (fromMaybe "body" (uParaStyle u)) ub nextId lastLine, ub) (nuBoxes nb)
        _ -> nuBoxes nb
      (headAcc', errs') = case uKind u of
        -- the title of the notes is in neither the headings nor the running heads (golem-driver ADR 0026)
        k
          | Just name <- headingName k ->
              ( Map.insert nextId hb (nuHeadings nb),
                nuErrors nb <> [diagnostic "G07024" Error (uSpan u) ("見出しが版面に入りません（" <> name <> "）") | hbSpan hb > capacity]
              )
        _ -> (nuHeadings nb, nuErrors nb)
   in nb {nuNext = nextId + length ls, nuFlow = flow', nuLines = Map.union (nuLines nb) set, nuHeadings = headAcc', nuErrors = errs', nuBoxes = boxes'}

{- | What a box paints and where it is (docs/adr/0271), of a paragraph
style of a style, from its first line to its last.
-}
boxInfoOf :: Style -> Text -> UnitBox -> Int -> Int -> BoxInfo
boxInfoOf st name ub firstLine lastLine =
  let swatchOf n = do
        Swatch (c, m, y, k) <- Map.lookup n (stSwatches st)
        pure (P.Swatch c m y k)
      border = do
        sw <- ubBorder ub >>= swatchOf
        pure (sw, ubBorderWidth ub, ubBorderStyle ub)
   in BoxInfo (BoxPaint (ubBackground ub >>= swatchOf) border (ubSides ub) (ubRadius ub)) (ubStart ub) (ubEnd ub) firstLine lastLine name

{- | The boxes of the paragraphs one after the other joined (docs/adr/0271,
B4): a box and the next of equal settings, with nothing but the spaces
around paragraphs and keep-with-next between them, are one box, those
between them in it. The box joined keeps the id of the first and the
last line of the last.
-}
joinBoxes :: Map Int (BoxInfo, UnitBox) -> [FlowAt Sp] -> ([FlowAt Sp], Map Int BoxInfo)
joinBoxes boxes flow =
  let keyOf = \case
        FBoxed {fbId = i} -> snd <$> Map.lookup i boxes
        _ -> Nothing
      passable = \case
        FSpace _ -> True
        FKeepNext {} -> True
        _ -> False
      bodyOf = \case
        FBoxed {fbBody = b} -> b
        f -> [f]
      groups = groupBoxes keyOf passable flow
      joined = \case
        Left f -> ([f], [])
        Right (_, fs@(FBoxed i kb ka _ : _)) ->
          let ids = [j | FBoxed {fbId = j} <- fs]
           in ([FBoxed i kb ka (concatMap bodyOf fs)], [(i, last ids)])
        Right (_, fs) -> (fs, [])
      (flows, spans) = unzip (map joined groups)
      infos = Map.map fst boxes
      lastOf j = maybe 0 bxLast (Map.lookup j infos)
   in (concat flows, foldl' (\m (i, j) -> Map.adjust (\bi -> bi {bxLast = lastOf j}) i m) infos (concat spans))

{- | G07121 (docs/adr/0271): a box whose grid lines before and after and
one line do not fit an empty column, at the first paragraph of its
paragraph style, once for each paragraph style.
-}
boxErrors :: FlowEnv -> [(Int, Unit)] -> [Diagnostic]
boxErrors fe units =
  let geom = feGeom fe
      capacity = length (pgLineGrid geom)
      pagePitch = pgLinePitch geom
      height = fromIntegral (max 0 (capacity - 1)) * pagePitch + pgFontSize geom
      free u = maybe False ((== AlignFree) . gridAlignment) (stPage (uStyle u) >>= pageGrid)
      exceeds u ub
        | free u =
            let pitch = fromMaybe pagePitch (paraStyle (uStyle u) (uParaStyle u) >>= resolvedParagraphPitch (uStyle u))
                (before, after) = boxExtras pitch (lkSize (uLook u)) pitch (lkSize (uLook u)) (ubPadding ub)
             in before + pitch + after > height
        | otherwise = 2 * boxLinesAround pagePitch (pgFontSize geom) (ubPadding ub) + 1 > capacity
      tooTall =
        [ (fromMaybe "body" (uParaStyle u), uSpan u)
        | (_, u) <- units,
          Just ub <- [uBox u],
          exceeds u ub
        ]
   in [diagnostic "G07121" Error sp ("段落スタイル " <> name <> " の囲みの一行と上下の padding が段に収まりません") | (name, sp) <- nubOrdOn fst tooTall]

-- | The rules of a ruled unit, for the diagnostics of the layout (golem-driver ADR 0027).
ruledInfoOf :: Unit -> RuledInfo
ruledInfoOf u = case uKind u of
  UHeading l _ _ -> uncurry (RuledInfo "見出しの罫線" ("見出し " <> T.pack (show l)) True (lkSize (uLook u))) (uRules u) (uSpan u)
  _ -> uncurry (RuledInfo "段落の罫線" ("段落スタイル " <> fromMaybe "body" (uParaStyle u)) False (lkSize (uLook u))) (uRules u) (uSpan u)

{- | Composes the units of the body with the pages assumed, and numbers
their lines. With the round before (docs/adr ADR 0251), a unit equal to the
unit at its place in that round and with no reference to a page is not
composed again: its composition is that of the round before, which the
same unit gives again, since only the references to pages and the units
made from the pages of the index read the pages assumed.
-}
buildFlow :: PdfInput -> PageGeometry -> LoadedFonts -> Map (Text, Int) P.FigureContent -> Maybe Built -> Assumed -> IO Built
buildFlow inp geom fonts images prev assumed = do
  let fe = flowEnv inp geom fonts assumed
      (units, widths) = flowUnits fe
      unitAt = Map.fromList units
      -- the units the round before composed the same way: none if the number of the units or the widths of the list markers differ (docs/adr ADR 0256)
      unchanged = case prev of
        Just p
          | length (bUnits p) == length units && bWidths p == widths ->
              Set.fromList [i | ((i, u), (_, u')) <- zip units (bUnits p), u == u', not (refersToPage u), Map.lookup i (asCuts assumed) == Map.lookup i (asCuts (feAssumed (bFlowEnv p)))]
        _ -> Set.empty
      reused :: (ComposedUnits -> Map Int a) -> Int -> Maybe a
      reused field i = if Set.member i unchanged then Map.lookup i . field . bComposed =<< prev else Nothing
      -- the paragraphs beside a wrapped figure, when the figure, they and the unit after them are unchanged
      reusedBeside i = do
        p <- prev
        let before = cuBesides (bComposed p)
            js = besideParagraphs unitAt before i
            -- the figure, the paragraphs beside it, and the unit after them, if there is one
            around = [k | k <- [i .. maybe (i + 1) (+ 1) (listToMaybe (reverse js))], k < length units]
        if all (`Set.member` unchanged) around then Just [(j, before Map.! j) | j <- js] else Nothing
      mapper :: (a -> IO b) -> [a] -> IO [b]
      mapper = if piParallel inp then mapConcurrently else mapM
      -- figures: the image, its size, its caption and its exclusion (golem-driver ADR 0005)
      figures = Map.fromList [(i, f) | (i, u@Unit {uKind = UFigure fig}) <- units, Just f <- [placeFigure fe u fig <$> Map.lookup (figureKey fig) images]]
      -- 1. a job per wrapped figure: the paragraphs right after it, in order, beside the exclusion
      jobs = [(i, pf) | (i, (pf, [], _, _)) <- Map.toList figures, isJust (pfExclusion pf)]
  besides <- Map.fromList . concat <$> mapper (\(i, pf) -> maybe (composeBeside fe widths unitAt i pf) pure (reusedBeside i)) jobs
  -- 2. every other unit on its own
  let rest = [(i, u) | (i, u) <- units, Map.notMember i besides, not (isFigure u), not (isTable u), not (isGap u)]
      -- gaps and breaks are not composed
      isGap u = case uKind u of
        UGap _ -> True
        UBreak _ -> True
        USection {} -> True
        UPageControl _ -> True
        UBlank _ -> True
        UKeepNext _ -> True
        UHeldNeedLines {} -> True
        -- code blocks are set by codeBlocks (golem-driver ADR 0017)
        UCode {} -> True
        UColumns _ -> True
        _ -> False
      isFigure u = case uKind u of
        UFigure _ -> True
        _ -> False
      isTable u = case uKind u of
        UTable {} -> True
        _ -> False
      tableUnits = [(i, spanFile (uSpan u), uStyle u, lkLang (uLook u), t) | (i, u@Unit {uKind = UTable t}) <- units]
  _ <- mapper (\(_, (pf, _, _, _)) -> evaluate (length (show (map (lineRatio . ptLine) (pfCaption pf))))) (Map.toList figures)
  -- the lines under the frames of wrap around are shorter by their cuts (root ADR 0438)
  let cutWidth i k = maybe 0 (uncurry (+)) (Map.lookup i (asCuts assumed) >>= Map.lookup k)
  singles <- Map.fromList . zip (map fst rest) <$> mapper (\(i, u) -> maybe (forceComposed (composeUnit fe widths (\k -> unitLineWidth fe (uKind u) k - cutWidth i k) u)) pure (reused cuSingles i)) rest
  tables <- Map.fromList <$> mapper (\(i, fid, st, l, t) -> maybe (let r = composeTable fe i fid st l t in forceTable r >> pure (i, r)) (pure . (i,)) (reused cuTables i)) tableUnits
  -- Numbering is pure and can be repeated for an uncommitted physical
  -- paragraph trial without reshaping its source or changing a snapshot.
  let ownedControls =
        if not free
          then Set.empty
          else
            Set.fromList
              [k | (i, _) <- jobs, let paras = besideParagraphs unitAt besides i, lastPara <- maybe [] pure (listToMaybe (reverse paras)), k <- [i + 1 .. lastPara - 1], Just u <- [Map.lookup k unitAt], isJust (besideControlFlow u)]
      composed = ComposedUnits unitAt besides figures singles tables (codeBlocksOf fe units) ownedControls
      built = numberComposedFlow inp geom fe units widths composed
      free = maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle inp) >>= pageGrid)
  pure $
    if free && not (null jobs)
      then case causalFreeFlow inp geom fe units widths (map fst jobs) built of
        Left err -> built {bFreePages = Just (Left err)}
        Right final -> final
      else built

numberComposedFlow :: PdfInput -> PageGeometry -> FlowEnv -> [(Int, Unit)] -> Map Int Sp -> ComposedUnits -> Built
numberComposedFlow inp geom fe units widths composed =
  let unitAt = cuUnits composed
      besides = cuBesides composed
      figures = cuFigures composed
      singles = cuSingles composed
      codeBlocks = cuCodeBlocks composed
      figureNotices = concat [ns | (_, _, ns, _) <- Map.elems figures]
      codeErrors = concatMap cbErrors (Map.elems codeBlocks)
      dimensionalBetween st name = maybe False (isJust . psSpaceBetweenDim) (paraStyle st (Just name))
      internalSpacingErrors =
        [ diagnostic "G03006" Error (uSpan u) "キャプション内部の space-between には整数行を指定してください"
        | (_, u) <- units,
          dimensionalBetween (uStyle u) "caption",
          case uKind u of
            UFigure fig -> not (null (figCaption fig))
            UTable tbl -> isJust (tableCaption tbl)
            UCode _ code -> isJust (codeCaption code)
            _ -> False
        ]
          <> [ diagnostic "G03006" Error sp "傍注内部の space-between には整数行を指定してください"
             | (i, c) <- Map.toList singles <> [(i, c) | (i, (c, _)) <- Map.toList besides],
               Just u <- [Map.lookup i unitAt],
               dimensionalBetween (uStyle u) "sidenote",
               (_, sp, _) <- cSidenotes c
             ]
      {- the block (and so the file) of each unit that has an id, by its first
      id (golem-driver ADR 0014), and the first id of each such unit (docs/adr/0267) -}
      stepFiles (nb, spans, firsts) iu@(i, u) =
        let nb' = numberUnit fe composed nb iu
         in if nuNext nb' > nuNext nb then (nb', Map.insert (nuNext nb) (uSpan u) spans, Map.insert i (nuNext nb) firsts) else (nb', spans, firsts)
      lineFiles = Map.map spanFile lineSpans
      separatorErrors =
        concat
          [ case appearance of
              SeparatorTextAppearance {} ->
                [diagnostic "G07134" Error (uSpan u) "区切りの約物が一行に収まりません" | length ls /= 1 || any ((> 0) . lineOverflow) ls]
                  <> [diagnostic "G07134" Error (uSpan u) "区切りの文字サイズが行送りを超えます" | maximum (lkSize (uLook u) : [lkSize (bcLook c) | l <- ls, Box _ c <- lineItems l]) > pgLinePitch geom]
              SeparatorRuleAppearance _ _ _ len weight _ _ ->
                [diagnostic "G07134" Error (uSpan u) "区切りの罫線が行長または行送りを超えます" | maybe False (> unSp (feMeasure fe)) len || weight > unSp (pgLinePitch geom)]
          | (i, u) <- units,
            let ls = maybe [] cLines (Map.lookup i (cuSingles composed)),
            USeparator appearance <- [uKind u]
          ]
      start = Numbered 0 [] Map.empty Map.empty Map.empty (deepListErrors fe widths units <> codeErrors <> internalSpacingErrors <> tocLineErrors fe units <> boxErrors fe units <> separatorErrors) Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty
      (numbered, baseSpans, baseFirsts) = foldl stepFiles (start, Map.empty, Map.empty) units
      free = maybe False ((== AlignFree) . gridAlignment) (stPage (piStyle inp) >>= pageGrid)
      besideFirsts =
        if not free
          then []
          else
            concat
              [ snd (mapAccumL (\ident j -> let (c, _) = cuBesides composed Map.! j in (ident + length (cLines c), (j, ident))) (firstId + 1) (besideParagraphs unitAt besides i))
              | (i, firstId) <- Map.toList baseFirsts,
                Map.member i figures
              ]
      unitFirsts = Map.union (Map.fromList besideFirsts) baseFirsts
      lineSpans = Map.union (Map.fromList [(ident, uSpan (unitAt Map.! i)) | (i, ident) <- besideFirsts]) baseSpans
      flow = nuFlow numbered
      -- the code blocks of the flow are those of the units, in order
      codeInfos = Map.fromList [(lbId b, (cbInfo cb) {ciFirst = lbId b0}) | (bs@(b0 : _), cb) <- zip [fcRows f | f@FCode {} <- flow] (Map.elems codeBlocks), b <- bs]
      codeNotices = concatMap cbNotices (Map.elems codeBlocks)
      -- G07127: each caption over its inner width, in the order of the units (docs/adr/0389)
      captionWarnings =
        concat
          [ case uKind u of
              UFigure _ | Just (pf, _, _, _) <- Map.lookup i figures -> captionIndentWarnings fe u (pfFullAlong pf) (pfCaption pf)
              UTable t -> captionIndentWarnings fe u (feMeasure fe) (ccLines (tableCaptionOf fe u t))
              UCode lead _ | Just cb <- Map.lookup i codeBlocks -> captionIndentWarnings fe u (feMeasure fe - lead) (ciCaption (cbInfo cb))
              _ -> []
          | (i, u) <- units
          ]
      -- the paragraphs one after the other in one box (docs/adr/0271)
      (boxedFlow, boxes) = joinBoxes (nuBoxes numbered) flow
      flow' = ruledLinks (spaceAfterCode (pgLinePitch geom) (pgFontSize geom) (map cbInfo (Map.elems codeBlocks)) boxedFlow)
      -- the rules of each ruled block by its first line, from the unit of its block (golem-driver ADR 0027)
      rulesBySpan = Map.fromList [(uSpan u, ruledInfoOf u) | (_, u) <- units, uRules u /= (Nothing, Nothing)]
      ruledInfos = Map.fromList [(frId f, info) | f@FRuled {} <- flow', Just sp <- [Map.lookup (frId f) lineSpans], Just info <- [Map.lookup sp rulesBySpan]]
      separatorLines = Map.fromList [(lid, appearance) | (i, u) <- units, USeparator appearance@(SeparatorRuleAppearance {}) <- [uKind u], Just lid <- [Map.lookup i unitFirsts]]
      -- the span and the name of each heading by its first line, for G07100 (golem-layout ADR 0020)
      namesBySpan = Map.fromList [(uSpan u, (uSpan u, name)) | (_, u) <- units, Just name <- [headingName (uKind u)]]
      headingNames = Map.mapMaybe (`Map.lookup` namesBySpan) lineSpans
      normalPitch u = case uKind u of
        UPara _
          | not (madeByGolem u),
            all (\(Frame _ k _) -> case k of FEndNote {} -> False; FEndNoteMore {} -> False; _ -> True) (uFrames u) ->
              paraStyle (uStyle u) (uParaStyle u) >>= resolvedParagraphPitch (uStyle u)
        _ -> Nothing
      ordinaryPitches =
        [ (lid, pitch)
        | (i, u) <- units,
          Just pitch <- [normalPitch u],
          Just firstId <- [Map.lookup i unitFirsts],
          Just c <- [Map.lookup i (cuSingles composed)],
          lid <- take (length (cLines c)) [firstId ..]
        ]
      wrappedPitches =
        concat
          [ snd
              ( mapAccumL
                  ( \lid j ->
                      let (c, _) = cuBesides composed Map.! j
                          count = length (cLines c)
                          u' = cuUnits composed Map.! j
                          p = fromMaybe (pgLinePitch geom) (normalPitch u')
                       in (lid + count, [(n, p) | n <- take count [lid ..]])
                  )
                  (firstId + 1)
                  paras
              )
          | (i, u) <- units,
            UFigure _ <- [uKind u],
            Just firstId <- [Map.lookup i unitFirsts],
            Just (pf, ferrs, _, _) <- [Map.lookup i figures],
            isJust (pfExclusion pf),
            null ferrs,
            let paras = besideParagraphs (cuUnits composed) (cuBesides composed) i
          ]
      pitches = Map.fromList (ordinaryPitches <> concat wrappedPitches)
      padding = Map.map (ubPadding . snd) (nuBoxes numbered)
   in Built flow' (nuLines numbered) (nuFigures numbered) (nuHeadings numbered) (nuErrors numbered) (nuTableLines numbered) (nuTables numbered) (nuHeadingSpans numbered) (nuTocLines numbered) lineFiles codeInfos (codeNotices <> figureNotices) lineSpans ruledInfos separatorLines headingNames units fe composed widths (nuTableCaptions numbered) boxes (destAnchors (piBook inp) units unitFirsts (nuFigures numbered) (nuHeadingSpans numbered) flow') captionWarnings pitches padding (nuWrappedBefore numbered) Nothing unitFirsts (markBookParts (compKeepParts (stComposition (piStyle inp))) units unitFirsts flow')

{- | Rebreak only unconsumed original items. The positions returned by the
breaker stay in the original item coordinate system, so discarded glue,
discretionary hyphens and forced breaks are consumed exactly once.
-}
rebreakComposed :: FlowEnv -> Unit -> (Int -> Sp) -> Int -> Composed -> Composed
rebreakComposed fe u width start source =
  let boxed = isJust (uBox u)
      params = if boxed then (feParams fe) {pProtrusion = compProtrusion (stComposition (piStyle (feInput fe)))} else feParams fe
      result = A.breakAligned (layoutAlign (uKind u)) (adjustedParams (uStyle u) (uParaStyle u) params) width (drop start (cItems source))
   in source {cLines = brLines result, cBreakPositions = map (+ start) (brPositions result), cItemStart = start, cReflowed = True, cActualIndents = Nothing}

itemAfterBreak :: Composed -> Int -> Int
itemAfterBreak source index = skip (index + 1) (drop (index + 1) (cItems source))
  where
    skip n [] = n
    skip n (Box {} : _) = n
    skip n (Penalty _ penalty _ : _) | penalty <= negate infPenalty = n
    skip n (_ : rest) = skip (n + 1) rest

{- | Commit physical paragraph parts in document order. Each width is read
from the current placement snapshot; moving to another column rebreaks
only the original source suffix that has not been committed.
-}
causalFreeFlow :: PdfInput -> PageGeometry -> FlowEnv -> [(Int, Unit)] -> Map Int Sp -> [Int] -> Built -> Either PhysicalFailure Built
causalFreeFlow inp geom fe units widths jobs initialBuilt = jobsFrom Nothing Nothing initialBuilt (startPhysicalCursor (settings initialBuilt)) jobs
  where
    settings = physicalSettings inp geom (length (pgLineGrid geom))
    rebuild = numberComposedFlow inp geom fe units widths
    keepUnit = compKeepParts (stComposition (piStyle inp))
    retaining = keepUnit /= KeepColumn
    -- the retention groups of page and spread (root ADR 0401); column keeps the flow as it was
    retain built = if retaining then markBookParts keepUnit units (bUnitFirsts built) else id
    remaining prior built = map (\(_, _, f) -> f) (remainingKeyed prior Nothing built)
    -- each flow with its outermost list item; after a finished item, what follows it
    remainingKeyed prior done built =
      let keyed = [(u >>= listToMaybe . itemPaths, u, f) | (u, f) <- itemOwners units (bUnitFirsts built) (bFlow built)]
          afterPrior = case prior >>= (`Map.lookup` bUnitFirsts built) of
            Nothing -> keyed
            Just ident -> case dropWhile (\(_, _, f) -> not (isWrapped ident f)) keyed of
              [] -> []
              _ : (_, _, FContinued {}) : rest -> rest
              _ : rest -> rest
       in maybe afterPrior (\key -> dropWhile (\(k, _, _) -> k == Just key) afterPrior) done
    flowOf (_, _, f) = f
    isWrapped ident = \case FWrapped {fwId = candidate} -> ident == candidate; _ -> False
    jobsFrom prior done built cursor [] = do
      finalCursor <- stepPhysicalCursor (settings built) cursor (retain built (map flowOf (remainingKeyed prior done built)))
      Right built {bFreePages = Just (Right (finishPhysicalCursor (settings built) finalCursor))}
    jobsFrom prior done built cursor (job : rest) = do
      let ident = bUnitFirsts built Map.! job
          (before, atJob) = break (isWrapped ident . flowOf) (remainingKeyed prior done built)
      case [key | retaining, (Just key, _, _) <- take 1 atJob] of
        key : _ -> do
          -- the figure is in a list item: the whole item is composed again at each trial cursor
          let inside = reverse (takeWhile (\(k, _, _) -> k == Just key) (reverse before))
              outside = take (length before - length inside) before
              source = case [uSpan u | (_, Just u, _) <- inside <> atJob] of
                sp : _ -> sp
                [] -> mkSpan (fst key) 0 0
          ready <- stepPhysicalCursor (settings built) cursor (retain built (map flowOf outside))
          ((placedBuilt, lastJob, later), placedCursor) <-
            retainPhysicalPart (settings built) keepUnit source "リスト項目" ready $ \at -> do
              (firstBuilt, firstCursor) <- runJob (map flowOf inside) job built at
              itemJobs key job firstBuilt firstCursor rest
          jobsFrom (Just lastJob) (Just key) placedBuilt placedCursor later
        [] -> do
          (placedBuilt, placedCursor) <- runJob (retain built (map flowOf before)) job built cursor
          jobsFrom (Just job) Nothing placedBuilt placedCursor rest
    -- the later figures of the same item, then the rest of the item
    itemJobs key prior built cursor later = case later of
      next : more
        | (before, (Just k, _, _) : _) <- break (isWrapped (bUnitFirsts built Map.! next) . flowOf) (remainingKeyed (Just prior) Nothing built),
          k == key -> do
            (nextBuilt, nextCursor) <- runJob (map flowOf before) next built cursor
            itemJobs key next nextBuilt nextCursor more
      _ -> do
        let rest = takeWhile (\(k, _, _) -> k == Just key) (remainingKeyed (Just prior) Nothing built)
            ids = concat [flowSlotIds f | (Just k, _, f) <- remainingKeyed Nothing Nothing built, k == key]
        final <- stepPhysicalCursor (settings built) cursor (map flowOf rest)
        Right ((built, prior, later), ids, final)
    runJob prefix job built cursor = do
      let composed = bComposed built
          (pf, _, _, marks) = cuFigures composed Map.! job
          unit = cuUnits composed Map.! job
          ident = bUnitFirsts built Map.! job
          cfg = settings built
      (anchored, region) <- beginPhysicalWrapAfter cfg cursor prefix ident (pfExclusionLength pf) (unitLabel unit) marks
      let (_, _, origin) = physicalCursorPosition anchored
          paras = besideParagraphs (cuUnits composed) (cuBesides composed) job
      (placedBuilt, placedCursor) <- paragraphs job pf origin region job built anchored paras
      Right (placedBuilt, endPhysicalWrap (Just region) placedCursor)
    controlsBetween composed prior index = concat [flows | i <- [prior + 1 .. index - 1], Just u <- [Map.lookup i (cuUnits composed)], Just flows <- [besideControlFlow u]]
    bindingAfter index composed styleWanted =
      let later = takeWhile (isJust . besideControlFlow . snd) (Map.toAscList (Map.filterWithKey (\i _ -> i > index) (cuUnits composed)))
          controls = concat [flows | (_, u) <- later, Just flows <- [besideControlFlow u]]
       in case physicalKeepAhead controls of
            Nothing -> (0, styleWanted)
            Just (lastCount, firstCount, _) -> (lastCount, max firstCount styleWanted)
    paragraphs _ _ _ _ _ built cursor [] = Right (built, cursor)
    paragraphs job pf origin region prior built cursor (index : later) = do
      let composed = bComposed built
          unit = cuUnits composed Map.! index
          controls = controlsBetween composed prior index
          (startBreak, _) = paraStartAndKeep unit
          prefix = controls <> [FSection (OfParagraph (uSpan unit)) kind | kind <- maybe [] pure startBreak]
      preliminary <- stepPhysicalCursor (settings built) cursor prefix
      case uStanza unit of
        Nothing -> do
          let source = fst (cuBesides composed Map.! index)
              (trial, indents) = composeAt pf origin region unit preliminary 0 0 source
              updated = rebuild (composed {cuBesides = Map.adjust (\(_, offset) -> (trial {cActualIndents = Just indents}, offset)) index (cuBesides composed)})
              (rows, _) = numberedLines fe (bUnitFirsts updated Map.! index) unit trial (indents !!)
              (lastWanted, wanted) = bindingAfter index composed (snd (paraStartAndKeep unit))
          ready <- stepPhysicalPrefix (settings updated) cursor prefix [FParagraph (keepOf unit) rows]
          (nextBuilt, nextCursor) <- paragraph job pf origin region index later unit (keepOf unit) lastWanted wanted built ready
          paragraphs job pf origin region index nextBuilt nextCursor later
        Just _ -> do
          let sameVerse i = let v = cuUnits composed Map.! i in isJust (uStanza v) && uSpan v == uSpan unit
              (verseIndices, afterVerses) = span sameVerse (index : later)
          trials <- tryVerses job pf origin region built preliminary verseIndices
          let trialBuilt = maybe built fst (listToMaybe (reverse trials))
              rowsAt i = let c = fst (cuBesides (bComposed trialBuilt) Map.! i); u = cuUnits composed Map.! i in fst (numberedLines fe (bUnitFirsts trialBuilt Map.! i) u c (maybe (unitLineIndent (pgFontSize geom) (uKind u)) (!!) (cActualIndents c)))
          ready <- stepPhysicalPrefix (settings trialBuilt) cursor prefix [FStanza (keepOf unit) (map rowsAt verseIndices)]
          (nextBuilt, nextCursor) <- stanza job pf origin region verseIndices afterVerses (keepOf unit) True built ready
          paragraphs job pf origin region (last verseIndices) nextBuilt nextCursor afterVerses
    composeAt pf origin region unit at countBefore start source =
      let PhysicalWrap page column end = region
          (actualPage, actualColumn, _) = physicalCursorPosition at
          pitch = fromMaybe (pgLinePitch geom) (paraStyle (uStyle unit) (uParaStyle unit) >>= resolvedParagraphPitch (uStyle unit))
          face = lkSize (uLook unit)
          exclusionWidth = maybe 0 exWidth (pfExclusion pf)
          narrowed k = (page, column) == (actualPage, actualColumn) && intersects (rowExtent (physicalParagraphOrigin at + fromIntegral k * pitch) pitch face) (origin, end)
          indent k = unitLineIndent (pgFontSize geom) (uKind unit) (countBefore + k)
          width k = feMeasure fe - (if narrowed k then exclusionWidth else 0) - indent k - unitEndIndent (uKind unit)
          tailComposed = rebreakComposed fe unit width start source
          tailIndents = [indent k + if pfWrap pf == Just WrapStart && narrowed k then exclusionWidth else 0 | k <- [0 .. length (cLines tailComposed) - 1]]
       in (tailComposed, tailIndents)
    probeNext job pf origin region index later built cursor wanted = case later of
      [] ->
        let following = remaining (Just job) built
            closed = endPhysicalWrap (Just region) cursor
            (required, linesOnly) = physicalFollowingRows wanted following
         in Right (required, linesOnly, fitsPhysicalFollowing (settings built) closed wanted following)
      nextIndex : more -> do
        let composed = bComposed built
            unit = cuUnits composed Map.! nextIndex
            controls = controlsBetween composed index nextIndex
            (startBreak, _) = paraStartAndKeep unit
            sameColumn a b = let (p, c, _) = physicalCursorPosition a; (p', c', _) = physicalCursorPosition b in (p, c) == (p', c')
        ready <- stepPhysicalCursor (settings built) cursor (controls <> [FSection (OfParagraph (uSpan unit)) kind | kind <- maybe [] pure startBreak])
        case uStanza unit of
          Just _ -> do
            let sameVerse i = let v = cuUnits composed Map.! i in isJust (uStanza v) && uSpan v == uSpan unit
                (verses, afterVerses) = span sameVerse (nextIndex : more)
                wantedVerses = max (firstPart (keepOf unit) True (length verses)) (min wanted (length verses))
            trials <- tryVerses job pf origin region built ready verses
            let actual = maybe built fst (listToMaybe (reverse (take wantedVerses trials)))
                required = sum [length (cLines c) | i <- take wantedVerses verses, let (c, _) = cuBesides (bComposed actual) Map.! i]
                prefixFits = sameColumn cursor ready && length trials >= wantedVerses
            chainFits <-
              if prefixFits && wantedVerses == length verses
                then case listToMaybe (reverse trials) of
                  Just (updated, placed) -> probeChain job pf origin region (last verses) afterVerses updated placed
                  Nothing -> Right True
                else Right True
            Right (required, True, prefixFits && chainFits)
          Nothing -> do
            let source = fst (cuBesides composed Map.! nextIndex)
                (trial, indents) = composeAt pf origin region unit ready 0 0 source
                updated = rebuild (composed {cuBesides = Map.adjust (\(_, offset) -> (trial {cActualIndents = Just indents}, offset)) nextIndex (cuBesides composed)})
                keep = keepOf unit
                required = fst (physicalFollowingRows wanted [FParagraph keep rows])
                (rows, _) = numberedLines fe (bUnitFirsts updated Map.! nextIndex) unit trial (indents !!)
            result <- trialParagraphPart (settings updated) (Just region) keep {kFirst = max (kFirst keep) required} True ready rows
            case result of
              PhysicalMoved {} -> Right (required, True, False)
              PhysicalPlaced count placed _ -> do
                let prefixFits = sameColumn cursor ready && sameColumn ready placed && count >= required
                chainFits <- if prefixFits && count == length rows then probeChain job pf origin region nextIndex more updated placed else Right True
                Right (required, True, prefixFits && chainFits)
    probeChain job pf origin region index later built cursor =
      let unit = cuUnits (bComposed built) Map.! index
          (lastWanted, wanted) = bindingAfter index (bComposed built) (snd (paraStartAndKeep unit))
       in if wanted > 0 || lastWanted > 0
            then (\(_, _, fits) -> fits) <$> probeNext job pf origin region index later built cursor wanted
            else Right True
    -- Whole verse lines are the counting units of a stanza. Each trial is
    -- composed at its own actual cursor, and its snapshot is committed only
    -- after the original-verse keep has selected a legal prefix.
    tryVerses _ _ _ _ _ _ [] = Right []
    tryVerses job pf origin region built cursor (index : later) = do
      let composed = bComposed built
          unit = cuUnits composed Map.! index
          source = fst (cuBesides composed Map.! index)
          (trial, indents) = composeAt pf origin region unit cursor 0 0 source
          updated = rebuild (composed {cuBesides = Map.adjust (\(_, offset) -> (trial {cActualIndents = Just indents}, offset)) index (cuBesides composed)})
          (rows, _) = numberedLines fe (bUnitFirsts updated Map.! index) unit trial (indents !!)
          sameColumn a b = let (p, c, _) = physicalCursorPosition a; (p', c', _) = physicalCursorPosition b in (p, c) == (p', c')
      result <- trialParagraphPart (settings updated) (Just region) (Keep 1 1 False) True cursor rows
      case result of
        PhysicalPlaced count placed _ | count == length rows && sameColumn cursor placed -> ((updated, placed) :) <$> tryVerses job pf origin region updated placed later
        _ -> Right []
    stanza _ _ _ _ [] _ _ _ built cursor = Right (built, finishPhysicalUnit cursor)
    stanza job pf origin region indices@(firstIndex : _) later keep isStart built cursor = do
      trials <- tryVerses job pf origin region built cursor indices
      let whole = length trials
          total = length indices
          selected = splitAtBreak keep isStart total whole
          firstId = bUnitFirsts built Map.! firstIndex
          firstUnit = cuUnits (bComposed built) Map.! firstIndex
          move = stanza job pf origin region indices later keep isStart built (movePhysicalCursor (settings built) (Just region) cursor)
          accept count problems =
            let (chosenBuilt, placed) = trials !! (count - 1)
                warned = recordPhysicalUnmet problems placed
                remainingVerses = drop count indices
             in if null remainingVerses
                  then do
                    let settled = finishPhysicalUnit warned
                        lastIndex = last indices
                        lastUnit = cuUnits (bComposed chosenBuilt) Map.! lastIndex
                        (lastWanted, wanted) = bindingAfter lastIndex (bComposed chosenBuilt) (snd (paraStartAndKeep lastUnit))
                    (required, linesOnly, fits) <- if wanted > 0 || lastWanted > 0 then probeNext job pf origin region lastIndex later chosenBuilt settled wanted else Right (0, True, True)
                    let held = if snd (paraStartAndKeep lastUnit) > 0 then keepPhysicalNext (uSpan lastUnit) required linesOnly settled else settled
                        front = count - max lastWanted (max 1 (kLast keep))
                    if fits
                      then Right (chosenBuilt, held)
                      else
                        if front >= (if isStart then max 1 (kFirst keep) else 1) && not (kAll keep)
                          then accept front []
                          else if not (physicalCursorIsEmpty cursor) then move else Right (chosenBuilt, held)
                  else stanza job pf origin region remainingVerses later keep False chosenBuilt (movePhysicalCursor (settings chosenBuilt) (Just region) warned)
      if kAll keep && isStart && whole < total
        then
          if physicalCursorIsEmpty cursor
            then stanza job pf origin region indices later keep {kAll = False} isStart built (recordPhysicalUnmet [SplitKept firstId] cursor)
            else move
        else
          if selected > 0
            then accept selected []
            else
              if not (physicalCursorIsEmpty cursor)
                then move
                else
                  if whole > 0
                    then accept whole ([ShortPart FirstPart firstId (kFirst keep) whole | isStart, whole < kFirst keep] <> [ShortPart LastPart firstId (kLast keep) (total - whole) | total - whole < kLast keep])
                    else do
                      -- One original verse itself exceeds an empty column; use the
                      -- existing display-row fallback, then consume that verse.
                      (nextBuilt, nextCursor) <- paragraph job pf origin region firstIndex (drop 1 indices <> later) firstUnit defaultKeep 0 0 built cursor
                      stanza job pf origin region (drop 1 indices) later keep False nextBuilt nextCursor
    paragraph job pf origin region index later unit initialKeep lastWanted wanted built cursor = parts Nothing initialKeep True 0 [] [] [] built cursor
      where
        source = fst (cuBesides (bComposed built) Map.! index)
        -- Every retry reduces the uncommitted prefix bound, consumes source
        -- items, or moves the current holding group to its next column.
        parts prefixLimit keep isStart start committed breaks indents current at = do
          let countBefore = length committed
              (tailComposed, tailIndents) = composeAt pf origin region unit at countBefore start source
              combined = source {cLines = committed <> cLines tailComposed, cBreakPositions = breaks <> cBreakPositions tailComposed, cItemStart = 0, cReflowed = True, cActualIndents = Just (indents <> tailIndents)}
              updated = rebuild ((bComposed current) {cuBesides = Map.adjust (\(_, offset) -> (combined, offset)) index (cuBesides (bComposed current))})
              cfg = settings updated
              firstId = bUnitFirsts updated Map.! index + countBefore
              (rows, _) = numberedLines fe firstId unit tailComposed (tailIndents !!)
              retry limit = parts limit keep isStart start committed breaks indents current at
              movePart = parts Nothing keep isStart start committed breaks indents current (movePhysicalCursor cfg (Just region) at)
              minimumFront = if isStart then max (if lastWanted > 0 then 2 else 1) (kFirst keep) else 1
          result <- trialParagraphPartLimit cfg (Just region) prefixLimit keep isStart at rows
          case result of
            PhysicalMoved moved relaxed -> parts Nothing relaxed isStart start committed breaks indents current moved
            PhysicalPlaced count placed relaxed
              | count >= length rows -> do
                  let settled = finishPhysicalUnit placed
                  (required, linesOnly, followingFits) <- if wanted > 0 || lastWanted > 0 then probeNext job pf origin region index later updated settled wanted else Right (0, True, True)
                  let held = if snd (paraStartAndKeep unit) > 0 then keepPhysicalNext (uSpan unit) required linesOnly settled else settled
                      front = count - max lastWanted (max 1 (kLast relaxed))
                  if followingFits || null rows
                    then Right (updated, held)
                    else
                      if front >= minimumFront && not (kAll relaxed)
                        then retry (Just front)
                        else
                          if not (physicalCursorIsEmpty at)
                            then movePart
                            else Right (updated, held)
              | otherwise ->
                  let consumedBreaks = take count (cBreakPositions tailComposed)
                      nextStart = itemAfterBreak source (last consumedBreaks)
                      next = movePhysicalCursor cfg (Just region) placed
                      (remainder, _) = composeAt pf origin region unit next (countBefore + count) nextStart source
                   in if length (cLines remainder) < kLast relaxed
                        then
                          if count > minimumFront
                            then retry (Just (count - 1))
                            else
                              if not (physicalCursorIsEmpty at)
                                then movePart
                                else continue consumedBreaks nextStart next
                        else continue consumedBreaks nextStart next
              where
                continue consumedBreaks nextStart = parts Nothing relaxed False nextStart (committed <> take count (cLines tailComposed)) (breaks <> consumedBreaks) (indents <> take count tailIndents) updated

-- | The list items a unit is in, from the outermost (root ADR 0401).
itemPaths :: Unit -> [(FileId, [Frame])]
itemPaths u = [(spanFile (uSpan u), take (n + 1) (uFrames u)) | (n, Frame _ FItem _) <- zip [0 ..] (uFrames u)]

{- | The unit each flow belongs to. A control between two flows of the same
outermost list item belongs to that item.
-}
itemOwners :: [(Int, Unit)] -> Map Int Int -> [FlowAt position] -> [(Maybe Unit, FlowAt position)]
itemOwners units firsts flows = annotated
  where
    owners = Map.fromList [(leading, u) | (i, u) <- units, Just leading <- [Map.lookup i firsts]]
    owner f = listToMaybe (flowSlotIds f) >>= \ident -> snd <$> Map.lookupLE ident owners
    raw = [(owner f, f) | f <- flows]
    (_, future) = mapAccumR (\next (u, f) -> (u <|> next, (u, next, f))) Nothing raw
    (_, annotated) = mapAccumL fill Nothing future
    fill previous (u, next, f) =
      let inherited = do
            before <- previous
            after <- next
            leading <- listToMaybe (itemPaths before)
            following <- listToMaybe (itemPaths after)
            if leading == following then Just before else Nothing
       in (u <|> previous, (u <|> inherited, f))

-- | Build retention groups without changing the original flow used by painting and links.
markBookParts :: KeepParts -> [(Int, Unit)] -> Map Int Int -> [FlowAt position] -> [FlowAt position]
markBookParts unit units firsts flows = special (wrapLists 0 annotated)
  where
    owners = Map.fromList [(leading, u) | (i, u) <- units, Just leading <- [Map.lookup i firsts]]
    owner f = listToMaybe (flowSlotIds f) >>= \ident -> snd <$> Map.lookupLE ident owners
    paths = itemPaths
    key depth (u, _) = u >>= (listToMaybe . drop depth . paths)
    annotated = itemOwners units firsts flows
    wrapLists _ [] = []
    wrapLists depth allFlows@(leading : _) = case key depth leading of
      Just wanted ->
        let (inside, rest) = span ((== Just wanted) . key depth) allFlows
            body = special (wrapLists (depth + 1) inside)
            source = maybe (mkSpan (fst wanted) 0 0) uSpan (fst leading)
         in retained source "リスト項目" (concatMap flowSlotIds body) body : wrapLists depth rest
      Nothing ->
        let (plain, rest) = span (isNothing . key depth) allFlows
         in map snd plain <> wrapLists depth rest
    retained = FBookPart unit
    sourceOf f = case owner f of
      Just u -> case uKind u of
        UTerm _ -> maybe (uSpan u) inlineSpan (listToMaybe (uInlines u))
        _ -> uSpan u
      Nothing -> mkSpan (FileId 0) 0 0
    defKey f = do
      u <- owner f
      n <- listToMaybe [i | (i, Frame _ FDefItem _) <- zip [0 ..] (uFrames u)]
      pure (spanFile (uSpan u), take (n + 1) (uFrames u))
    isTerm FDefTerm {} = True
    isTerm _ = False
    special [] = []
    special allFlows@(leading@FDefTerm {} : _) =
      let (terms, following) = span (\f -> isTerm f && defKey f == defKey leading) allFlows
          (controls, material) = span (null . flowSlotIds) following
          (description0, rest) = case material of
            next : more | not (isTerm next) && defKey next == defKey leading -> ([next], more)
            _ -> ([], material)
          description = special description0
          body = terms <> controls <> description
          firstIds = case description of
            [FBookPart _ _ _ keptIds _] -> keptIds
            _ -> take 1 (concatMap flowSlotIds description)
          ids = concatMap flowSlotIds terms <> firstIds
       in retained (sourceOf leading) "定義用語と説明" ids body : special rest
    special (f@FTable {ftHeader = header, ftRows = rows, ftCaption = caption, ftCaptionBelow = below} : rest) =
      let ids = map lbId ((if below then [] else caption) <> header <> concat (take 1 rows))
       in retained (sourceOf f) "表の見出しと最初の行" ids [f] : special rest
    special (FBoxed i before after body : rest) = FBoxed i before after (special body) : special rest
    special (f : rest) = f : special rest

{- | Where the destinations of links inside the document are drawn first
(docs/adr/0267): a label at the line or the figure that carries it, an
index mark at the line or the figure it is placed with, a heading at its
first line, an entry of a @bibliography at the first line of its unit,
each the first in the order of the flow.
-}
destAnchors :: Book -> [(Int, Unit)] -> Map Int Int -> Map Int PlacedFigure -> Map Int SrcSpan -> [FlowAt Sp] -> Map LinkDest DestAnchor
destAnchors book units firsts figs headingSpans flow =
  Map.fromListWith (\_ old -> old) (concatMap ofFlow flow <> headings <> entries)
  where
    headings = [(DestHeading sp, AnchorLine lid) | (lid, sp) <- Map.toAscList headingSpans]
    -- the units of each @bibliography in order, one for each of its entries
    entries =
      concat
        [ [(DestBibEntry sp k, AnchorLine lid) | ((k, _), Just lid) <- zip (bibliographyAt book sp) (map (`Map.lookup` firsts) is)]
        | (sp, is) <- Map.toList (Map.fromListWith (flip (<>)) [(uSpan u, [i]) | (i, u) <- units, any (\(Frame _ k _) -> k == FBibliography) (uFrames u)])
        ]
    -- a label of a note is at the mark of the note (root ADR 0422)
    noteLabels = noteLabelSpans book
    marked m = [DestIndexMark m] <> [DestLabel l | Just l <- [Map.lookup m noteLabels]]
    ofBox lb = [(DestLabel l, AnchorLine (lbId lb)) | l <- lbLabels lb] <> [(d, AnchorLine (lbId lb)) | m <- lbMarks lb, d <- marked m]
    ofFigure fid labels marks = case Map.lookup fid figs of
      Just pf -> [(DestLabel l, AnchorFigure (pfUnit pf)) | l <- labels] <> [(d, AnchorFigure (pfUnit pf)) | m <- marks, d <- marked m]
      Nothing -> []
    ofFlow = \case
      FParagraph _ lbs -> concatMap ofBox lbs
      FStanza _ lbss -> concatMap ofBox (concat lbss)
      FHeading {fhLines = lbs} -> concatMap ofBox lbs
      FDefTerm lbs -> concatMap ofBox lbs
      FFigure {ffId = fid, ffLabels = ls, ffMarks = ms} -> ofFigure fid ls ms
      FWrapped {fwId = fid, fwLabels = ls, fwMarks = ms, fwBeside = lbs} -> ofFigure fid ls ms <> concatMap ofBox lbs
      FPageFigure {fpId = fid, fpLabels = ls, fpMarks = ms} -> ofFigure fid ls ms
      FContinued _ lbs -> concatMap ofBox lbs
      FTable {ftHeader = h, ftRows = rs, ftCaption = c, ftCaptionBelow = below} -> concatMap ofBox (if below then h <> concat rs <> c else c <> h <> concat rs)
      FCode {fcRows = lbs} -> concatMap ofBox lbs
      FRuled {frBody = RuledLines _ lbs} -> concatMap ofBox lbs
      FRuled {frBody = RuledHeading {rhLines = lbs}} -> concatMap ofBox lbs
      FBoxed {fbBody = fs} -> concatMap ofFlow fs
      _ -> []

{- | Whether a unit refers to a page (docs/adr ADR 0251): a [ref-page]
anywhere in its inlines, its list marker, the cells of its table or the
caption of its figure, in notes, sidenotes, ruby and spans too. Its
composition reads the pages assumed, so it is composed in every round.
-}
refersToPage :: Unit -> Bool
refersToPage u =
  inlinesReferToPage (uInlines u) || maybe False inlinesReferToPage (uMarker u) || case uKind u of
    UTable t -> any inlinesReferToPage (fromMaybe [] (tableCaption t) : tableHeader t <> concat (tableRows t))
    UFigure fig -> any (any inlinesReferToPage . blockInlineLists) (figCaption fig)
    _ -> False

-- | Whether inlines hold a [ref-page], at any depth.
inlinesReferToPage :: [InlineF r] -> Bool
inlinesReferToPage = any $ \case
  Ref _ RefPage _ -> True
  Resolved _ RefPage _ _ -> True
  Resolved _ _ _ is -> inlinesReferToPage is
  Ruby _ _ segs -> any (inlinesReferToPage . rsBase) segs
  Kenten _ _ is -> inlinesReferToPage is
  Color _ _ is -> inlinesReferToPage is
  CharStyle _ _ is -> inlinesReferToPage is
  Note _ _ _ nb -> inlinesReferToPage (concat (noteParagraphs nb))
  Sidenote _ _ _ nb -> inlinesReferToPage (concat (noteParagraphs nb))
  Endnote _ _ _ nb -> inlinesReferToPage (concat (noteParagraphs nb))
  Link _ _ is -> inlinesReferToPage is
  Lang _ _ is -> inlinesReferToPage is
  ChannelItem _ ci -> inlinesReferToPage (ciBody ci)
  _ -> False

{- | The links between ruled blocks (golem-driver ADR 0027): a block whose
rule before follows right after a block with a rule after shares its
area; each block knows the overhang of the first line after it.
-}
ruledLinks :: [FlowAt Sp] -> [FlowAt Sp]
ruledLinks = go Nothing
  where
    go prev = \case
      f@FRuled {} : rest ->
        let joined = case prev of
              Just FRuled {frAfter = Just _} -> isJust (frBefore f)
              _ -> False
            f' = f {frJoined = joined, frNextOverhang = maybe 0 lbOverhang (listToMaybe rest >>= firstLine)}
         in f' : go (Just f') rest
      f : rest -> f : go (Just f) rest
      [] -> []
    firstLine = \case
      FBoxed {fbBody = f : _} -> firstLine f
      FRuled {frBody = RuledLines _ (l : _)} -> Just l
      FRuled {frBody = RuledHeading _ _ (l : _)} -> Just l
      FParagraph _ (l : _) -> Just l
      FStanza _ vs | l : _ <- concat vs -> Just l
      FContinued _ (l : _) -> Just l
      FHeading {fhLines = l : _} -> Just l
      FDefTerm (l : _) -> Just l
      _ -> Nothing

{- | The room out of the type area across the lines on the side of a rule
(golem-driver ADR 0027): before the lines (the head, the right in
vertical text) or after them; the narrower of odd and even pages.
-}
marginAcross :: PageGeometry -> Bool -> Sp
marginAcross geom before =
  let (pw, ph) = pgPageSize geom
      side (Rect x y w h)
        | pgVertical geom = if before then pw - x - w else x
        | otherwise = if before then ph - y - h else y
   in min (side (pgTypeArea geom)) (side (pgTypeAreaEven geom))

{- | The rules of a ruled block (golem-driver ADR 0027): the kind for golem
preflight, whose rules they are for G07046, whether it is a heading, the
size zw is resolved by, the rules and the block.
-}
data RuledInfo = RuledInfo
  { riKind :: !Text,
    riOwner :: !Text,
    riHeading :: !Bool,
    riSize :: !Sp,
    riBefore :: !(Maybe RuleSpec),
    riAfter :: !(Maybe RuleSpec),
    riSpan :: !SrcSpan
  }
  deriving stock (Eq, Show)

-- | A code block set (golem-driver ADR 0017).
data SetCode = SetCode
  { cbRows :: [Line],
    cbSize :: Sp,
    -- | where the rows start from the line start of the column: the list and the padding
    cbIndent :: Sp,
    cbInfo :: CodeInfo,
    -- | the rows the first part takes at least: the file name with the first line of code (golem-driver ADR 0023)
    cbFirstRows :: Int,
    -- | the index marks of the caption
    cbMarks :: [SrcSpan],
    -- | G07043
    cbErrors :: [Diagnostic],
    -- | G07030
    cbNotices :: [Diagnostic]
  }

{- | Sets a code block of a unit that starts @lead@ from the line start in
a column of @measure@ and @capacity@ grid lines (golem-driver ADR 0017):
each line as 'layoutCodeLine' wraps it, from the clusters of shaping in
the role of the paragraph style code, spaces of its Latin face.

Inside the padding, the columns of the line numbers and of the diff marks
come before the code; the file name is a row of its own; the callouts
are lined up after the longest line that has one when they fit; the wrap
mark ends the rows that continue; the tokens of [code.colors] are in
their swatches (golem-driver ADR 0023).
-}
codeBlockOf :: (SrcSpan -> Text -> Int -> Int) -> PageGeometry -> LoadedFonts -> Sp -> Int -> Unit -> Sp -> Code -> CodeCaption -> SetCode
codeBlockOf atSource geom fonts measure capacity u lead code caption =
  let lk = uLook u
      size = lkSize lk
      vertical = pgVertical geom
      st = uStyle u
      cs = stCode st
      toSp = L.zwToSp size
      -- the shaping of each side: Latin, or Japanese ('漢')
      side latin = shapingForFonts fonts vertical lk (if latin then 'a' else '\x6F22')
      shape latin r =
        let gs = lfShape fonts (side latin) r
            starts = Set.toAscList (Set.fromList (map shCluster gs))
            ends = drop 1 starts <> [T.length r]
         in [(T.take (e - c) (T.drop c r), sum [toSp (shAdvance x) | x <- gs, shCluster x == c]) | (c, e) <- zip starts ends]
      s = toSp (lfAdvance fonts (side True) ' ')
      pad = codePadding st size
      -- a text on one row, from 0, and its width
      oneRow t = concatMap crPieces (take 1 (layoutCodeLine s (10 ^ (12 :: Int)) (codeAtoms shape t)))
      endOf ps = case reverse ps of
        (p : _) -> cpOffset p + cpWidth p
        [] -> 0
      widthOf = endOf . oneRow
      ls = case codeLines code of
        [] -> [CodeLine "" (Just 1) Nothing False [] Nothing]
        xs -> xs
      numbered = fromMaybe (cdLineNumbers cs) (codeNumbers code)
      numberWidth = maximum (0 : [widthOf (T.pack (show n)) | numbered, Just n <- map clNumber ls])
      numberColumn = if numbered then numberWidth + 2 * s else 0
      diffColumn = if codeDiff code then 2 * s else 0
      codeStart = numberColumn + diffColumn
      -- the code column, and the measure the lines wrap at: less the wrap mark
      full = measure - lead - 2 * pad - codeStart
      wrapMark = cdWrapMark cs
      avail = full - (if T.null wrapMark then 0 else widthOf wrapMark)
      swatchOf name = do
        Swatch (cc, cm, cy, ck) <- Map.lookup name (stSwatches st)
        pure (P.Swatch cc cm cy ck)
      -- the tokens of each line in their swatches; the colour of the text without [code.colors]
      tokens = case codeTokens (codeLang code) (T.intercalate "\n" (map clText ls)) of
        Just tls
          | not (Map.null (cdColors cs)),
            length tls == length ls ->
              [[(kind >>= (`Map.lookup` cdColors cs), t) | (kind, t) <- tl] | tl <- tls]
        _ -> [[(Nothing, clText l)] | l <- ls]
      atomsOf = map (codeAtomsColored shape) tokens
      laid = map (layoutCodeLine s avail) atomsOf
      marksOf ns = oneRow (T.intercalate " " (map circled ns))
      -- the callouts: at one column when every line fits them, else after each line
      withMarks = [(rows, ns) | (rows, l) <- zip laid ls, let ns = clCallouts l, not (null ns)]
      lastEnd rows = maybe 0 (endOf . crPieces) (listToMaybe (reverse rows))
      markColumn = maximum (0 : [lastEnd rows | (rows, _) <- withMarks]) + 2 * s
      aligned = all (\(_, ns) -> markColumn + endOf (marksOf ns) <= full) withMarks
      placed atoms rows ns
        | null ns = [(r, Nothing) | r <- rows]
        | aligned = [(r, Nothing) | r <- init rows] <> [(last rows, Just markColumn)]
        | lastEnd rows + 2 * s + endOf (marksOf ns) <= full = [(r, Nothing) | r <- init rows] <> [(last rows, Just (lastEnd rows + 2 * s))]
        | otherwise = [(r, Nothing) | r <- rows] <> [(CodeRow [], Just (codeContinuation s avail atoms))]
      perLine = [placed atoms rows (clCallouts l) | (atoms, rows, l) <- zip3 atomsOf laid ls]
      wrapped = length (filter ((> 1) . length) perLine)
      tagOf latin = fromEnum (if vertical && latin then KindRotated else KindText)
      lookOf col = lk {lkColor = col}
      -- the size of the paragraph style code, at the code block (golem-cli ADR 0008)
      source = (uSource u, uSpan u)
      blockStart = spanStart (snd source)
      emptyBox off w = Box w (BoxContent "" False 0 0 (fromEnum KindText) lk 0 0 [] 0 0 source Nothing noLeaf off Nothing)
      {- pieces at offsets from the padding: (offset, text, width, Latin,
      swatch, leaf); line numbers and wrap marks are of no leaf: artifacts
      (docs/adr ADR 0183); every box of a row is at the source of its row
      (docs/adr/0218) -}
      lineOf off pieces =
        let go _ [] = []
            go x ((o, t, w, latin, col, leaf) : rest) =
              [emptyBox off (o - x) | o > x]
                <> [Box w (BoxContent t False 0 0 (tagOf latin) (lookOf col) 0 0 [] 0 0 source Nothing leaf off Nothing)]
                <> go (o + w) rest
         in Line (go 0 (sortOn (\(o, _, _, _, _, _) -> o) pieces)) 0 (measure - lead - 2 * pad) 0 (0, 0) 0 (0, 0) Nothing AdjustUniform
      at leaf o col t = [(o + cpOffset p, cpText p, cpWidth p, cpLatin p, col, leaf) | p <- oneRow t]
      rowLeaf j = Leaf (codeRowSite (uIndex u) j) 0
      lineNumberColor = cdLineNumberColor cs
      rowLine j l n off (i, (row, markAt)) =
        lineOf
          off
          ( concat [at noLeaf (numberWidth - widthOf num) lineNumberColor num | i == 0, numbered, Just k <- [clNumber l], let num = T.pack (show k)]
              <> concat [at (rowLeaf j) numberColumn Nothing m | i == 0, Just m <- [diffMark (clDiff l)]]
              <> [(codeStart + cpOffset p, cpText p, cpWidth p, cpLatin p, cpColor p, rowLeaf j) | p <- crPieces row]
              <> concat [at noLeaf (codeStart + avail) lineNumberColor wrapMark | i < n - 1, not (T.null wrapMark)]
              <> [(codeStart + o + cpOffset p, cpText p, cpWidth p, cpLatin p, Nothing, rowLeaf j) | Just o <- [markAt], p <- marksOf (clCallouts l)]
          )
      diffMark = \case
        Just DiffAdded -> Just "+"
        Just DiffRemoved -> Just "-"
        _ -> Nothing
      fileRows = [lineOf blockStart (at (Leaf (codeFileSite (uIndex u)) 0) codeStart Nothing f) | Just f <- [codeFile code]]
      codeRows = concat [zipWith3 (\i a r -> rowLine j l (length rs) a (i, r)) [0 :: Int ..] (rowSources l atoms rs) rs | (j, (l, atoms, rs)) <- zip [0 ..] (zip3 ls atomsOf perLine)]
      {- where each row of a line starts in the source (docs/adr/0218): the
      first character of its text, the start of the line when it is empty,
      the block when the line is not in the source (@listing, Emet) -}
      rowSources l atoms rs = case clSpan l of
        Nothing -> map (const blockStart) rs
        Just lsp
          | T.null (clText l) -> map (const (spanStart lsp)) rs
          | otherwise ->
              let t = clText l
                  find = atSource lsp t
                  lastAt = find (T.length t - 1) + BS.length (TE.encodeUtf8 (T.takeEnd 1 t))
                  offAt i = if i < T.length t then find i else lastAt
                  ok o = if o < 0 then blockStart else o
               in map (ok . offAt) (codeRowStarts atoms [r | (r, _) <- rs])
      -- the bands of the highlight (K 15% by default) and of the diff
      bandOf l
        | clHighlight l = Just (fromMaybe (P.Swatch 0 0 0 15) (cdHighlight cs >>= swatchOf))
        | clDiff l == Just DiffAdded = cdAdded cs >>= swatchOf
        | clDiff l == Just DiffRemoved = cdRemoved cs >>= swatchOf
        | otherwise = Nothing
      firsts = scanl (+) (length fileRows) (map length perLine)
      bands = [(r0, length rs, sw) | (l, rs, r0) <- zip3 ls perLine firsts, Just sw <- [bandOf l]]
      continued = cdContinued cs
      continuedLine = if T.null continued then Nothing else Just (lineOf blockStart (at noLeaf (codeStart + full - widthOf continued) Nothing continued))
      g = codeGeometry (pgFontSize geom) (pgLinePitch geom) size pad
      codeStyle = paraStyle st (Just "code")
      background = join (codeStyle >>= psBackground) >>= swatchOf
      borderWidth = dimToSp size (fromMaybe (Abs 16384) (codeStyle >>= psBorderWidth))
      border = do
        sw <- join (codeStyle >>= psBorder) >>= swatchOf
        pure (sw, borderWidth)
      errs =
        [diagnostic "G07043" Error (uSpan u) "コードブロックの行長が足りません" | avail < 8 * size]
          <> [diagnostic "G07043" Error (uSpan u) "コードブロックの一行が一ページに収まりません" | codeSpan g (if isJust continuedLine then 2 else 1) > capacity]
      blockRows = fileRows <> codeRows
   in SetCode
        { cbRows = blockRows,
          cbSize = size,
          cbIndent = lead + pad,
          cbInfo =
            CodeInfo
              { ciGeometry = g,
                ciStart = lead,
                ciBackground = background,
                ciFirst = 0,
                ciRows = length blockRows,
                ciCaption = ccLines caption,
                ciCaptionSize = ccSize caption,
                ciCaptionPitch = ccPitch caption,
                ciCaptionSpan = ccSpan caption,
                ciContinued = continuedLine,
                ciBands = bands,
                ciBorder = border,
                ciBorderStyle = borderStyleAt borderWidth (fromMaybe RuleSolid (codeStyle >>= psBorderStyle)),
                ciBorderSides = fromMaybe [minBound .. maxBound] (codeStyle >>= psBorderSides),
                ciRadius = maybe 0 (dimToSp size) (codeStyle >>= psBorderRadius),
                ciIndent = lead + pad,
                ciSize = size
              },
          cbFirstRows = length fileRows + 1,
          cbMarks = ccMarks caption,
          cbErrors = take 1 errs,
          cbNotices = [notice "G07030" (uSpan u) ("コードの行を折り返しました（" <> T.pack (show wrapped) <> " 行）") | wrapped > 0]
        }

{- | The index in the text of a line of code of the first character of
each of its rows (docs/adr/0218): a row after the first starts at the
glyph after those of the rows before it, since 'layoutCodeLine' starts a
row at a glyph only; a row without glyphs after them (the callouts on a
row of their own) at the end of the text.
-}
codeRowStarts :: [CodeAtom] -> [CodeRow] -> [Int]
codeRowStarts atoms rows = zipWith startOf [0 :: Int ..] (scanl (+) 0 (map glyphs rows))
  where
    glyphs = sum . map (T.length . cpText) . crPieces
    total = sum [atomLength a | a <- atoms]
    atomLength = \case
      AGlyph t _ _ _ -> T.length t
      _ -> 1
    -- the index of each glyph atom and the glyph characters before it
    glyphAt = go 0 0 atoms
      where
        go _ _ [] = []
        go i g (a : rest) = case a of
          AGlyph t _ _ _ -> (g, i) : go (i + T.length t) (g + T.length t) rest
          _ -> go (i + 1) g rest
    startOf 0 _ = 0
    startOf _ g = maybe total snd (listToMaybe [x | x@(g', _) <- glyphAt, g' == g])

-- | Which line (0-based) contains the item at an index.
lineIndexOfItems :: [Item] -> [Line] -> Int -> Int
lineIndexOfItems _ ls i =
  let counts = scanl1 (+) (map (length . lineItems) ls)
   in length (takeWhile (<= i) counts) `min` max 0 (length ls - 1)

-- | A figure by its file and its page (1 unless a PDF figure says otherwise).
figureKey :: Figure -> (Text, Int)
figureKey f = (figSource f, maybe 1 fromIntegral (figPage f))

{- | The width and the height of a figure, by which its size is worked out:
the pixels of an image, the crop box of a PDF figure after its rotation
(golem-pdf ADR 0008). Never zero.
-}
figureProportions :: P.FigureContent -> (Rational, Rational)
figureProportions = \case
  P.RasterFigure img -> (fromIntegral (max 1 (P.imgWidth img)), fromIntegral (max 1 (P.imgHeight img)))
  P.VectorFigure ip -> let (w, h) = P.ipSize ip in (max (1 / 65536) w, max (1 / 65536) h)
  P.SvgFigure d -> let (w, h) = P.drSize d in (max (1 / 65536) w, max (1 / 65536) h)

{- | The size of a figure that does not wrap (golem-driver ADR 0034): along
and across the lines and whether it was fitted. It takes the measure
@along0@ unless it is then deeper than the grid lines of the column, @l@
lines of pitch @p@ for the body size @fs@, leave it: those the caption
takes, or the depth of the column without one. A deeper figure is made
that deep, keeping its proportions (@ratio@ across for each along).
-}
fitFigure :: Rational -> Sp -> Int -> Sp -> Sp -> Maybe Int -> (Sp, Sp, Bool)
fitFigure ratio along0 l p fs captionSpan =
  let across0 = Sp (floor (fromInteger (unSp along0) * ratio))
      acrossMax = max 0 $ case captionSpan of
        Just s -> fromIntegral (l - s) * p
        Nothing -> fromIntegral (l - 1) * p + fs
   in if across0 <= acrossMax then (along0, across0, False) else (Sp (floor (fromInteger (unSp acrossMax) / ratio)), acrossMax, True)

{- | The items of a cell without a break between its last two boxes when
both are one Japanese character (golem-driver ADR 0037): a penalty
between them becomes infinite, and a glue gets an infinite penalty
before it, as the line start rule does (golem-layout ADR 0002).
-}
keepLastTwo :: [Item] -> [Item]
keepLastTwo items = case reverse boxes of
  (lastIx : prevIx : _)
    | lastIx `elem` jaBoxes && prevIx `elem` jaBoxes ->
        let (before, rest) = splitAt (prevIx + 1) items
            (between, after) = splitAt (lastIx - prevIx - 1) rest
         in before <> concatMap hold between <> after
  _ -> items
  where
    boxes = [i | (i, Box {}) <- zip [0 :: Int ..] items]
    jaBoxes = [i | (i, Box _ c) <- zip [0 :: Int ..] items, japanese c]
    japanese c = case T.unpack (bcText c) of
      [ch] -> boxKind c `elem` [KindText, KindPunctuation, KindKenten] && lookClass (bcLook c) ch /= Western
      _ -> False
    hold = \case
      Penalty w p h | p < infPenalty -> [Penalty w infPenalty h]
      g@Glue {} -> [Penalty 0 infPenalty NoHyphen, g]
      x -> [x]

{- | Why a figure cannot be placed: G08010 with the reason, what an SVG
figure cannot be drawn for, G08011, G08016, G08017 and G08101 (golem-pdf ADR
0008, 0009, docs/adr ADR 0054, 0084), or G08015, the joined content of a PDF page over
256 MiB (docs/adr ADR 0051).
-}
data Unplaced = Unplaced !Text | ColorConversion !Text | EncryptedPdf | MissingPdfPage !Int !Int | UnsupportedSvg !S.SvgProblems | ContentTooLarge | StreamNumberTooLarge !Int64

{- | The figures, read once by file and page; why one cannot be placed
(golem-pdf ADR 0008). The format follows the extension, as golem-eval
checked it: a PDF page, an SVG drawing (golem-pdf ADR 0009), or a PNG or
JPEG image.
-}
loadFigures :: PdfInput -> IO (Map (Text, Int) (Either Unplaced P.FigureContent))
loadFigures inp = do
  let keys = nub [figureKey f | (_, f) <- figureBlocks (piBook inp)]
  pairs <- mapM (\k -> (k,) <$> loadOne k) keys
  pure (Map.fromList pairs)
  where
    loadOne (s, page) = do
      -- the image a plugin made, or the file (docs/adr/0123)
      -- the path as golem-eval resolved it, normalised (docs/adr/0199)
      let path = T.unpack s
      bytes <- maybe (filesRead (piFiles inp) (fromRight path (normalizeRelative path))) pure (Map.lookup s (bookImages (piBook inp)))
      if
        | ".pdf" `T.isSuffixOf` T.toLower s -> case P.importPage page bytes of
            Left P.Encrypted -> pure (Left EncryptedPdf)
            Left (P.NoSuchPage requested count) -> pure (Left (MissingPdfPage requested count))
            Left (P.ContentTooLarge _) -> pure (Left ContentTooLarge)
            Left (P.StreamNumberTooLarge k) -> pure (Left (StreamNumberTooLarge k))
            Left e -> pure (Left (Unplaced (P.importErrorText e)))
            Right ip -> recolorPdf (P.VectorFigure ip) ip
        | ".svg" `T.isSuffixOf` T.toLower s -> case S.readSvg bytes of
            Left (S.SvgMalformed why) -> pure (Left (unreadable why))
            Left (S.SvgUnsupported us) -> pure $ Left $ case figureColor (piStyle inp) of
              Nothing -> UnsupportedSvg us
              Just _ -> ColorConversion "SVG の色の変換で扱えない要素または属性があります"
            Right svg ->
              let drawing = svgDrawing svg
               in recolorPdf (P.SvgFigure drawing) (drawingImportedPage drawing)
        | otherwise -> case P.readImage bytes of
            Left why -> pure (Left (unreadable (T.pack why)))
            Right image -> case figureColor (piStyle inp) of
              Nothing -> pure (Right (P.RasterFigure image))
              Just swatch -> do
                analysis <- safeAnalyzeRaster swatch image
                pure $ case analysis of
                  Left why -> Left (ColorConversion why)
                  Right result -> Right (P.RasterFigure (fromMaybe image (raImage result)))

    unreadable why = case figureColor (piStyle inp) of
      Nothing -> Unplaced why
      Just _ -> ColorConversion why

    recolorPdf original page = case figureColor (piStyle inp) of
      Nothing -> pure (Right original)
      Just swatch -> do
        changed <- guardColorConversion (maybe () forceImportedPage) (recolorImportedPage swatch (analyzeRaster swatch) page)
        pure $ case changed of
          Left why -> Left (ColorConversion why)
          Right result -> Right (maybe original P.VectorFigure result)

{- | The figures of the PDF for the screen whose colours [figures] color
changes as HTML changes them (root ADR 0445), by file and page: an SVG
figure recoloured in sRGB as the SVG of HTML, a PNG or JPEG figure as the
pixels of the PNG of HTML, its alpha with them. PDF figures, and a figure
whose colours do not change or cannot be read, are not here: the PDF for
the screen keeps those of the PDF for print.
-}
loadScreenFigures :: PdfInput -> IO (Map (Text, Int) P.FigureContent)
loadScreenFigures inp = case figureColor (piStyle inp) of
  Nothing -> pure Map.empty
  Just swatch -> do
    let keys = nub [figureKey f | (_, f) <- figureBlocks (piBook inp)]
    pairs <- mapM (\k -> fmap (k,) <$> loadOne swatch k) keys
    pure (Map.fromList (catMaybes pairs))
  where
    loadOne swatch (s, _) = do
      let path = T.unpack s
          lower = T.toLower s
      bytes <- maybe (filesRead (piFiles inp) (fromRight path (normalizeRelative path))) pure (Map.lookup s (bookImages (piBook inp)))
      if
        | ".pdf" `T.isSuffixOf` lower -> pure Nothing
        | ".svg" `T.isSuffixOf` lower -> pure $ case S.readSvg bytes of
            Right svg -> Just (recolorFigure swatch (P.SvgFigure (svgDrawing svg)))
            Left _ -> Nothing
        | otherwise -> do
            recolored <- safeRecolorRasterBytes swatch bytes
            pure $ case recolored of
              Right (Just (_, png)) -> either (const Nothing) (Just . P.RasterFigure) (P.readImage png)
              _ -> Nothing

-- | The @figure blocks of a book, with their spans.
figureBlocks :: Book -> [(SrcSpan, Figure)]
figureBlocks book = concat [concatMap collect bs | Document _ bs <- bookDocs book]
  where
    collect (Block sp _ _ body) = case body of
      FigureBlock figure -> [(sp, figure)]
      BulletList items -> concatMap (concatMap collect . itemBlocks) items
      OrderedList items -> concatMap (concatMap collect . itemBlocks) items
      DefList groups -> concatMap (concatMap (concatMap collect) . dgDefs) groups
      _ -> []

{- | G08010: a figure that cannot be placed in the PDF; G08011: an SVG figure
with things outside the subset, G08016: with markers in a cycle, G08017: with
markers nested too deep, G08101: with markers that draw too many segments,
each that applies in this order; G08015: a PDF figure whose page content
joined is over 256 MiB; G08020: a PDF figure whose page names twice a
stream numbered over 2^31 - 1; one of each per @figure (golem-pdf ADR 0008,
0009, docs/adr ADR 0051, 0054, 0084, 0259).
-}
figureDiagnostics :: PdfInput -> Map (Text, Int) (Either Unplaced P.FigureContent) -> [Diagnostic]
figureDiagnostics inp loaded =
  [ d
  | (sp, f) <- figureBlocks (piBook inp),
    Just (Left why) <- [Map.lookup (figureKey f) loaded],
    d <- case why of
      Unplaced reason -> [diagnostic "G08010" Error sp ("図版を PDF に置けません: " <> figSource f <> "（" <> reason <> "）")]
      ColorConversion reason -> [diagnostic "G08113" Error sp ("図版の色を変換できません: " <> figSource f <> "（" <> reason <> "）")]
      EncryptedPdf -> [diagnostic "G08105" Error sp ("暗号化された PDF の図版は使えません: " <> figSource f)]
      MissingPdfPage requested count -> [diagnostic "G08106" Error sp ("図版の PDF に " <> T.pack (show requested) <> " ページ目がありません（全 " <> T.pack (show count) <> " ページ）: " <> figSource f)]
      UnsupportedSvg ps ->
        [diagnostic "G08011" Error sp (unsupportedMessage (figSource f) us) | Just us <- [nonEmpty (S.spUnsupported ps)]]
          <> [diagnostic "G08016" Error sp (markerMessage "SVG の図版の marker が循環しています: " (figSource f) rs) | Just rs <- [nonEmpty (S.spMarkerCycles ps)]]
          <> [diagnostic "G08017" Error sp (markerMessage "SVG の図版の marker の入れ子が 9 段を超えます: " (figSource f) rs) | Just rs <- [nonEmpty (S.spMarkerDepth ps)]]
          <> [diagnostic "G08101" Error sp (markerSegmentsMessage (figSource f) n) | Just n <- [S.spMarkerSegments ps]]
      ContentTooLarge -> [diagnostic "G08015" Error sp ("図版の PDF のページの内容をつなぐと 256 MiB を超えます: " <> figSource f)]
      StreamNumberTooLarge k -> [diagnostic "G08020" Error sp ("図版の PDF のページが二度以上名指すストリームのオブジェクトの番号が 2147483647 を超えます: " <> figSource f <> "（" <> T.pack (show k) <> "）")]
  ]

{- | The rectangle of a figure's image on page @page@ from grid line @slot@
of the column @ta@ (golem-driver ADR 0005, 0034). A figure turned onto a
page of its own is in the type area @ta@ turned, and its rectangle is
where it lands on the page.
-}
figureRect :: PageGeometry -> Int -> Rect -> Int -> PlacedFigure -> Rect
figureRect geom n ta slot = figureRectAt geom n ta (fromIntegral slot * pgLinePitch geom)

figureRectAt :: PageGeometry -> Int -> Rect -> Sp -> PlacedFigure -> Rect
figureRectAt geom _ ta slot pf = case pfTurn pf of
  Nothing -> imageRectAt geom (paperOf geom) ta slot pf
  Just t ->
    let (paper, area) = turnedFrame geom t ta pf
     in P.turnRect t ta (imageRectAt geom paper area slot pf)

-- | The trimmed page.
paperOf :: PageGeometry -> Rect
paperOf geom = let (pw, ph) = pgPageSize geom in Rect 0 0 pw ph

{- | The rectangle of a figure's image from grid line @slot@ of an area
(golem-driver ADR 0005, 0034): its top (in vertical writing its right)
edge at the top of the line at that grid line; at the line start, or at
the line end for @wrap=end@. A fitted figure goes to the end of the line
whose edge is nearer the edge of the @paper@, to the start when they are
as near.
-}
imageRect :: PageGeometry -> Rect -> Rect -> Int -> PlacedFigure -> Rect
imageRect geom paper ta slot = imageRectAt geom paper ta (fromIntegral slot * pgLinePitch geom)

imageRectAt :: PageGeometry -> Rect -> Rect -> Sp -> PlacedFigure -> Rect
imageRectAt geom paper ta d pf =
  let along = pfAlong pf
      across = pfAcross pf
      atEnd = case pfWrap pf of
        Just WrapEnd -> True
        Just WrapStart -> False
        Nothing -> along < pfFullAlong pf && nearerEnd (pgVertical geom) paper ta
   in if pgVertical geom
        then
          let right = rectX ta + rectW ta - d
           in Rect (right - across) (if atEnd then rectY ta else rectY ta + rectH ta - along) across along
        else
          let top = rectY ta + rectH ta - d
           in Rect (if atEnd then rectX ta + rectW ta - along else rectX ta) (top - across) along across

{- | Whether the end of the lines of an area is nearer the edge of the
paper than their start (golem-driver ADR 0034): the bottom against the
top in vertical text, the right against the left in horizontal text.
-}
nearerEnd :: Bool -> Rect -> Rect -> Bool
nearerEnd vertical paper ta
  | vertical = rectY ta - rectY paper < (rectY paper + rectH paper) - (rectY ta + rectH ta)
  | otherwise = (rectX paper + rectW paper) - (rectX ta + rectW ta) < rectX ta - rectX paper

{- | The frame of a figure turned onto the type area @ta@ (golem-driver ADR
0034), in its own coordinates: the paper, and the area the figure and its
caption are set in. The frame is as wide as the type area is high; the
lines of the frame start at its start across the lines, or at its end
when that is nearer the edge of the paper and the figure leaves room.
-}
turnedFrame :: PageGeometry -> P.Turn -> Rect -> PlacedFigure -> (Rect, Rect)
turnedFrame geom t ta pf =
  let vertical = pgVertical geom
      turned = Rect 0 0 (rectH ta) (rectW ta)
      paper = unturnRect t ta (paperOf geom)
      depth
        | null (pfCaption pf) = pfAcross pf
        | otherwise = fromIntegral (pfImageLines pf) * pgLinePitch geom + fromIntegral (partRows (pfCaption pf) - 1) * pfCaptionPitch pf + pfCaptionSize pf
      spare = max 0 ((if vertical then rectW turned else rectH turned) - depth)
      -- the end across the lines: the left of the frame in vertical text, its bottom in horizontal text
      endNearer
        | vertical = rectX turned - rectX paper < (rectX paper + rectW paper) - (rectX turned + rectW turned)
        | otherwise = rectY turned - rectY paper < (rectY paper + rectH paper) - (rectY turned + rectH turned)
      shift = if spare > 0 && endNearer then spare else 0
      area
        | vertical = turned {rectW = rectW turned - shift}
        | otherwise = turned {rectH = rectH turned - shift}
   in (paper, area)

-- | Where a rectangle of the page is in the frame of 'P.Turned': the inverse of 'P.turnRect'.
unturnRect :: P.Turn -> Rect -> Rect -> Rect
unturnRect t (Rect x y w h) (Rect px py a b) = case t of
  P.TurnedRight -> Rect (y + h - py - b) (px - x) b a
  P.TurnedLeft -> Rect (py - y) (x + w - px - a) b a

{- | The names XMP takes as dc:creator and dc:contributor: without the
printer and the binder, without roles (docs/adr ADR 0033).
-}
pdfXPeople :: Metadata -> ([Text], [Text])
pdfXPeople md = (names (mdCreators md), names (mdContributors md))
  where
    names cs = [crName c | c <- cs, inMetadata (crRole c)]

-- | The output intent; a missing profile is G08006 (golem-project ADR 0004), one outside the project G03279 (docs/adr/0421).
loadIntent :: PdfInput -> IO (Either [Diagnostic] (Maybe P.PdfX))
loadIntent inp = case stIntent (piStyle inp) of
  Nothing -> pure (Right Nothing)
  Just path -> do
    r <- filesResolve (piFiles inp) path
    case r of
      -- a path outside the project is its own cause (docs/adr/0421)
      Left e -> pure (Left [diagnostic (if e == Missing then "G08006" else "G03279") Error (mkSpan (styleFileId (piProject inp)) 0 0) (T.pack (intentMessage e <> ": " <> path))])
      Right rel -> do
        bytes <- filesRead (piFiles inp) rel
        let md = manifestMetadata (projectManifest (piProject inp))
            condition = if "JapanColor2001Coated" `T.isInfixOf` T.pack path then "JC200103" else T.pack (takeBaseName path)
            -- PDF/A on top of PDF/X-4 (docs/adr ADR 0183)
            pdfA = case tgPdfA (manifestTargets (projectManifest (piProject inp))) of
              Just PdfA2a -> Just P.PdfA2a
              Nothing -> Nothing
        pure (Right (Just (uncurry (P.PdfX bytes condition) (pdfXPeople md) pdfA)))
  where
    intentMessage = \case
      Missing -> "出力インテントの ICC プロファイルがありません"
      e -> pathErrorMessage e
