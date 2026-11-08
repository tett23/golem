{-# LANGUAGE MultiWayIf #-}

-- | The flow of the PDF: composition, line breaking and pagination (golem-driver ADR 0002).
module Golem.Typeset.Flow
  ( SetLine (..),
    CodeInfo (..),
    PlacedSidenote (..),
    PlacedFigure (..),
    TableGeometry (..),
    PdfLayout (..),
    styleLayoutDiagnostics,
    pageColumnSet,
    columnSetRects,
    checkedGeometry,
    kentenGlyphDiagnostics,
    dashInkNotices,
    flowLines,
    layoutPdf,
    gridLine,
    runningHeadLines,
    numberedTitle,
    pagesOf,
    pageMasters,
    pageStarts,
    runningHeads,
    runningHeadNotices,
    plainWidth,
    drawsFolio,
    hiddenFolios,
    TocGeometry (..),
    TocPage (..),
    tocPage,
    layoutPages,
    indexLines,
    bibliographyLines,
    sidenoteMetrics,
    labelSpans,
    noteNumberDiagnostics,
    Assumed (..),
    fixpoint,
    rubyStyleOf,
    RuledInfo (..),
    fitFigure,
    figureRect,
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
    sidenoteSite,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (evaluate)
import Control.Monad (join, mfilter)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.Char (isSpace)
import Data.Containers.ListUtils (nubOrdOn)
import Data.Either (fromRight)
import Data.Foldable (toList)
import Data.Int (Int64)
import Data.List (groupBy, intercalate, mapAccumL, nub, sortOn, unsnoc, zip4)
import Data.List.NonEmpty (nonEmpty)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Assemble
import Golem.Assemble.ListMarkers
import Golem.Assemble.Numbering (numberSeparator)
import Golem.Bibliography (EntryPart (..))
import Golem.Doc.FigureWidth (figureWidthSp, parseFigureWidth)
import Golem.Doc.IR
import Golem.Doc.Url (checkUrl)
import Golem.Html (codeTokens)
import Golem.Layout.Aki (AkiSet, resolveAkiSet)
import Golem.Layout.Align qualified as A
import Golem.Layout.Code
import Golem.Layout.Hyphenation.Languages (patternsFor)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass hiding (Sp)
import Golem.Layout.Look hiding (Kerning (..))
import Golem.Layout.Look qualified as L
import Golem.Layout.Paginate
import Golem.Layout.Ruby (RubyStyle (..))
import Golem.Layout.Ruby qualified as R
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Layout.Sidenotes (SidenoteError (..), placeSidenotes)
import Golem.Layout.Table (SetCell (..), SetTable (..), TableError (..), layoutTable)
import Golem.Layout.Wrap (Exclusion (..), exclusion, wrappedLineWidth)
import Golem.LayoutSpec (HiddenFolioGeometry (..), MasterGeometry (..), PageGeometry (..), Rect (..), Side (..), baselineRatio, gutterSide, pageGeometry, sidenoteAreaFor, typeAreaFor)
import Golem.Length qualified as L
import Golem.Numerals (circled)
import Golem.Numerals.Format (renderMarkFormat)
import Golem.Numerals.Notation (writeNumber)
import Golem.Pdf qualified as P
import Golem.Project
import Golem.Project.Files (Files (..))
import Golem.Project.Paths (PathError (..), normalizeRelative, pathErrorMessage)
import Golem.Project.Style
import Golem.Svg qualified as S
import Golem.Syntax
import Golem.Typeset.Fonts
import Golem.Typeset.Overhang (lineOverhang, reachesBackground)
import Golem.Typeset.Pages (sourceAt)
import Golem.Typeset.Svg (markerMessage, markerSegmentsMessage, svgDrawing, unsupportedMessage)
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
    slSidenotes :: ![(SrcSpan, [Line])],
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
    ciCaption :: ![Line],
    ciCaptionSize :: !Sp,
    ciCaptionPitch :: !Sp,
    ciCaptionSpan :: !Int,
    -- | the row at the end of a part before the last, with [code] continued
    ciContinued :: !(Maybe Line),
    -- | the bands: the first row from the first row of the block, how many rows and the colour
    ciBands :: ![(Int, Int, P.Swatch)],
    -- | the colour and the width of the border
    ciBorder :: !(Maybe (P.Swatch, Sp)),
    -- | where the rows start from the line start of the column, and the size of the code
    ciIndent :: !Sp,
    ciSize :: !Sp
  }
  deriving stock (Show)

-- | The caption of a code block as set (golem-driver ADR 0023): its lines, size, pitch, grid lines and index marks.
data CodeCaption = CodeCaption
  { ccLines :: [Line],
    ccSize :: Sp,
    ccPitch :: Sp,
    ccSpan :: Int,
    ccMarks :: [SrcSpan]
  }

-- | A sidenote placed in the sidenote column (golem-driver ADR 0006).
data PlacedSidenote = PlacedSidenote
  { psSpan :: !SrcSpan,
    -- | from the top of the column
    psTop :: !Sp,
    psLines :: ![Line]
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
    pfCaption :: ![Line],
    -- | the size of the caption (cs; golem-driver ADR 0010)
    pfCaptionSize :: !Sp,
    -- | the line pitch of the caption (cp)
    pfCaptionPitch :: !Sp,
    -- | the grid lines the caption takes (N)
    pfCaptionSpan :: !Int,
    -- | the exclusion area of a wrapped figure
    pfExclusion :: !(Maybe Exclusion),
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
  { plPages :: ![PageOut],
    plLines :: !(Map Int SetLine),
    plFigures :: !(Map Int PlacedFigure),
    -- | heading blocks by their first line (golem-driver ADR 0003)
    plHeadings :: !(Map Int HeadingBlock),
    -- | sidenotes by page number (golem-driver ADR 0006)
    plSidenotes :: !(Map Int [PlacedSidenote]),
    -- | the cell lines on each grid line of a table, shifted to their columns (golem-driver ADR 0008)
    plTableLines :: !(Map Int [SetLine]),
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
    -- | the units of the book by their indices, and the composition: what the structure tree is made of (docs/adr ADR 0183)
    plUnits :: ![(Int, Unit)],
    plFlowEnv :: FlowEnv
  }

data Built = Built
  { bFlow :: [Flow],
    bLines :: Map Int SetLine,
    bFigures :: Map Int PlacedFigure,
    -- | heading blocks by their first line
    bHeadings :: Map Int HeadingBlock,
    -- | errors found while building (G07022, G07023, G07024, G07041, G07042)
    bErrors :: [Diagnostic],
    bTableLines :: Map Int [SetLine],
    bTables :: Map Int TableGeometry,
    -- | the span of each heading block by its first line (golem-driver ADR 0009)
    bHeadingSpans :: Map Int SrcSpan,
    -- | the heading and the end of the title of each table of contents entry, by its last line
    bTocLines :: Map Int (SrcSpan, Sp),
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
    -- | the span and the name in messages of each heading by its first line (golem-layout ADR 0020)
    bHeadingNames :: Map Int (SrcSpan, Text),
    -- | the units by their indices, and the composition (docs/adr ADR 0183)
    bUnits :: [(Int, Unit)],
    bFlowEnv :: FlowEnv
  }

{- | What style.toml alone decides before the layout (golem-driver ADR
0016): the page geometry (G07001) and the indent of each paragraph style
(G07025), at the top of @fid@. The driver reports them for golem check too.
-}
styleLayoutDiagnostics :: FileId -> Bool -> Style -> [LocalStyles] -> [Diagnostic]
styleLayoutDiagnostics fid marks style locals = either id (\geom -> indentDiagnostics fid style locals geom <> indexDiagnostics fid style geom <> codeMeasureDiagnostics fid style locals geom) (pageGeometry fid marks style)

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
columnSetRects :: PageGeometry -> Int -> ColumnSet -> [Rect]
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
sidenote do not indent, and G07043 checks code (golem-driver ADR 0043).
-}
indentDiagnostics :: FileId -> Style -> [LocalStyles] -> PageGeometry -> [Diagnostic]
indentDiagnostics fid style locals geom =
  nub
    [ diagnostic "G07025" Error (mkSpan fid 0 0) ("段落スタイルの字下げが大きすぎます。行長を段落の文字の大きさの 8 字分以上残してください: " <> name)
    | st <- style : map (withLocalStyles style) locals,
      name <- Map.keys (stParaStyles st),
      name `notElem` ["caption", "sidenote", "code"],
      let (lk, Indent s f e _) = paraLook st geom (Just name),
      let size = lkSize lk,
      -- the end indent counts (docs/adr/0189)
      columnMeasure geom - s - max 0 f - e < 8 * size
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
  | (role, shape) <- Set.toAscList (Set.fromList [(lkFace (bcLook c), shape) | l <- layoutLines layout, Box _ c <- lineItems l, boxKind c == KindKenten, Just shape <- [lkKenten (bcLook c)]]),
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

-- | Every line of a layout: of the text, notes, sidenotes, tables, captions and the table of contents.
layoutLines :: PdfLayout -> [Line]
layoutLines layout =
  concat
    [ concat [slLine sl : concatMap snd (slNotes sl) <> concatMap snd (slSidenotes sl) | sl <- Map.elems (plLines layout)],
      [slLine sl | sls <- Map.elems (plTableLines layout), sl <- sls],
      concatMap pfCaption (Map.elems (plFigures layout)),
      concatMap psLines (concat (Map.elems (plSidenotes layout))),
      concat [[tpLeader tp, tpNumber tp] | tp <- Map.elems (plTocPages layout)]
    ]

{- | The flow and its lines as (line length, indent), in order, laid out
with no page numbers assumed (for tests).
-}
flowLines :: FontProvider -> PdfInput -> IO (Either [Diagnostic] ([Flow], [(Sp, Sp)]))
flowLines provider inp0 = case checkedGeometry inp of
  Left ds -> pure (Left ds)
  Right geom -> do
    lf <- loadFonts provider (piFiles inp) (piStyleFile inp) (piStyle inp) (Map.elems (piLocalStyles inp))
    case lf of
      Left ds -> pure (Left ds)
      Right fonts -> do
        figures <- Map.mapMaybe (either (const Nothing) Just) <$> loadFigures inp
        built <- buildFlow inp geom fonts figures (Assumed Map.empty Map.empty)
        pure (Right (bFlow built, [(lineTarget (slLine sl), slIndent sl) | sl <- Map.elems (bLines built)]))
  where
    inp = codeInput inp0

-- | Composition, line breaking and pagination, with page references resolved (S2).
layoutPdf :: PdfInput -> PageGeometry -> LoadedFonts -> IO (Either [Diagnostic] PdfLayout)
layoutPdf inp0 geom fonts =
  let inp = codeInput inp0
   in case sidenoteDiagnostics geom (piBook inp) <> listNumberDiagnostics (lsNumbers (stLists (piStyle inp))) (pgVertical geom) (piBook inp) <> noteNumberDiagnostics (piStyle inp) (piBook inp) of
        ds@(_ : _) -> pure (Left ds)
        [] -> do
          loaded <- loadFigures inp
          -- a figure that cannot be placed stops the PDF (G08010, golem-pdf ADR 0008)
          case figureDiagnostics inp loaded of
            ds@(_ : _) -> pure (Left ds)
            [] -> layoutFigures inp geom fonts (Map.mapMaybe (either (const Nothing) Just) loaded)

-- | 'layoutPdf' with the figures read.
layoutFigures :: PdfInput -> PageGeometry -> LoadedFonts -> Map (Text, Int) P.FigureContent -> IO (Either [Diagnostic] PdfLayout)
layoutFigures inp geom fonts figures = do
  -- S2: compose with assumed page numbers until they settle
  -- the names of the marks for G07021: the terms of the index, the bodies of the entries of channels (golem-doc ADR 0007)
  let terms =
        Map.fromList
          ( [(sp, T.intercalate " / " (igTerms g)) | g <- indexGroups (bookDocs (piBook inp)), (_, sp) <- igLocations g]
              <> [(sp, T.concat (map inlineText (ceBody e))) | (_, _, es) <- bookChannels (piBook inp), e <- es, (_, sp) <- ceLocations e]
          )
  let capacity = length (pgLineGrid geom)
      round' assumed = do
        built <- buildFlow inp geom fonts figures assumed
        pure (if null (bErrors built) then Right (built, paginateWithin (adjustLimit geom) (pgNoteSeparator geom) (pageColumnSet (piStyle inp) geom) capacity (bFlow built)) else Left (bErrors built))
      labels = labelSpans (piBook inp)
      labelSpan l = Map.findWithDefault (mkSpan (piStyleFile inp) 0 0) l labels
  result <- fixpoint labelSpan (\sp -> Map.findWithDefault "" sp terms) round'
  pure $ case result of
    Left ds -> Left ds
    Right (built0, pages) ->
      -- sidenotes are placed once, on the settled pages (golem-driver ADR 0006)
      -- in the size of the document of each sidenote (docs/adr ADR 0014)
      let -- the lines towards and away from the spine on their pages (docs/adr/0189)
          built = built0 {bLines = alignToSpine geom pages (bLines built0)}
          metricsOf sp = let (_, size, pitch) = sidenoteMetrics (docStyle inp (spanFile sp)) geom in (pitch, size)
          placed = [(poNumber p, placePageSidenotes geom metricsOf (bLines built) p) | p <- pages]
          -- the pages of the table of contents, once, on the settled pages (golem-driver ADR 0009)
          hPages = headingPages (bHeadingSpans built) pages
          tg = tocGeometry (piStyle inp) geom fonts
          env = composeEnv (piStyle inp) geom fonts (Assumed Map.empty Map.empty) (bodyLook (piStyle inp) (pgFontSize geom))
          -- the leader and the page number are at the heading of the entry (golem-cli ADR 0008)
          atHeading hs tp = tp {tpLeader = withBoxSource (SourceGrid, hs) (tpLeader tp), tpNumber = withBoxSource (SourceGrid, hs) (tpNumber tp)}
          tocPages = Map.fromList [(lid, atHeading hs (tocPage tg e (pageNumberLine env n))) | (lid, (hs, e)) <- Map.toList (bTocLines built), Just n <- [Map.lookup hs hPages]]
       in case concat [ds | (_, Left ds) <- placed] of
            [] -> Right (PdfLayout pages (bLines built) (bFigures built) (bHeadings built) (Map.fromList [(n, ps) | (n, Right ps@(_ : _)) <- placed]) (bTableLines built) (bTables built) tocPages (bLineFiles built) (bHeadingSpans built) (bCodes built) (bNotices built <> ruledNotices (bFlow built) (bRules built) pages <> unmetWarnings (bHeadingNames built) pages) (bLineSpans built) (bRules built) (bUnits built) (bFlowEnv built))
            ds -> Left ds

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
unmetWarnings :: Map Int (SrcSpan, Text) -> [PageOut] -> [Diagnostic]
unmetWarnings names pages =
  [ d
  | p <- pages,
    u <- poUnmet p,
    d <- case u of
      UnmetNoBreak sp -> [diagnostic "G07037" Warning sp "ここで改ページを止められませんでした"]
      UnmetNeedLines sp k -> [diagnostic "G07037" Warning sp ("@need-lines " <> T.pack (show k) <> " は段の行数 " <> T.pack (show (poLines p)) <> " を超えます")]
      UnmetAdjust sp k limit -> [diagnostic "G07037" Warning sp (adjustReason limit <> "@page-lines の増減を " <> T.pack (show k) <> " 行に切り詰めました")]
      -- G07047: blank lines dropped at the top of a column (docs/adr ADR 0046), an info (docs/adr 0104)
      DroppedBlank sp -> [infoDiagnostic "G07047" sp "段の先頭に来た @blank-line の空きを捨てました"]
      TallHeading i n room ->
        [ notice "G07100" sp ("見出しが段に入りません（" <> name <> "。見出しは " <> T.pack (show n) <> " 行、段の残りは " <> T.pack (show room) <> " 行）")
        | Just (sp, name) <- [Map.lookup i names]
        ]
  ]

{- | G07046 (golem-driver ADR 0027): a ruled paragraph broken between
columns, or a ruled heading that lost a rule, because an empty column
could not hold its block.
-}
ruledNotices :: [Flow] -> Map Int RuledInfo -> [PageOut] -> [Diagnostic]
ruledNotices flow infos pages =
  [ if riHeading info
      then notice "G07046" (riSpan info) ("罫線を持つ見出しが版面に入らないため、罫線を省きました（" <> riOwner info <> "）")
      else notice "G07046" (riSpan info) ("罫線を持つ段落が版面に入らないため、罫線を省いて分けて組みました（" <> riOwner info <> "）")
  | f@FRuled {} <- flow,
    let ids = case frBody f of
          RuledLines ls -> map lbId ls
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
headingPages :: Map Int SrcSpan -> [PageOut] -> Map SrcSpan Integer
headingPages spans ps =
  Map.fromList [(hs, toInteger (poNumber p)) | p <- ps, (_, SHeading lid _) <- poSlots p, Just hs <- [Map.lookup lid spans]]

{- | The headings that start on each page (golem-driver ADR 0014), in the
order they are placed, looked up by the first line of their block.
-}
headingsOnPages :: (Int -> Maybe HeadingInfo) -> [PageOut] -> Map Int [HeadingInfo]
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
runningHeadLines meta projectVars vars content start started = case content of
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
              HeadNumbered -> Just (maybe (short h) (\n -> n <> numberSeparator (Map.findWithDefault "" "language" meta) n <> short h) (hiNumberText h))
              HeadNumber -> hiNumberText h
         in chosen >>= render

{- | The inlines of a numbered title (golem-html ADR 0002): the number, the
separator of the language of the book and the title; the title alone
without a number.
-}
numberedTitle :: Text -> SrcSpan -> Maybe Text -> [Inline] -> [Inline]
numberedTitle lang sp num is = maybe [] (\n -> [Text sp (n <> numberSeparator lang n)]) num <> is

-- | The columns of each page, in order (docs/adr ADR 0018).
pagesOf :: [PageOut] -> [[PageOut]]
pagesOf = groupBy (\a b -> poNumber a == poNumber b)

{- | The file of each page, in order (golem-driver ADR 0014): the file of
the unit of its first line; a page without lines has the file of the page
before it, and the first chapter's file when it is the first page.
-}
pageFiles :: PdfInput -> PdfLayout -> [FileId]
pageFiles inp layout = drop 1 (scanl next firstFile (pagesOf (plPages layout)))
  where
    firstFile = maybe (FileId 0) fst (listToMaybe (projectChapters (piProject inp)))
    -- through the columns of the page in order (docs/adr ADR 0018)
    firstLine ps = listToMaybe [lid | p <- ps, (_, s) <- poSlots p, lid <- case s of SLine l -> [l]; SHeading l _ -> [l]; SCode l _ _ -> [l]; _ -> []]
    next prev p = fromMaybe prev (firstLine p >>= \lid -> snd <$> Map.lookupLE lid (plLineFiles layout))

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
    firstPart lid = maybe False ((== lid) . ciFirst) (Map.lookup lid (plCodes layout))
    lineStart lid =
      let block = snd <$> Map.lookupLE lid (plLineSpans layout)
          sets = fromMaybe (maybe [] pure (Map.lookup lid (plLines layout))) (Map.lookup lid (plTableLines layout))
          -- a block of no length (a heading) holds whatever of its file its line shows
          inside b c = spanFile (snd (bcSource c)) == spanFile b && bcAt c >= 0 && (spanLength b == 0 || (spanStart b <= bcAt c && bcAt c <= spanEnd b))
       in case block of
            Just b | firstPart lid -> Just (spanFile b, spanStart b)
            Just b -> case [bcAt c | sl <- sets, Box _ c <- lineItems (slLine sl), inside b c] of
              off : _ -> Just (spanFile b, off)
              [] -> Just (spanFile b, spanStart b)
            Nothing -> Nothing

{- | The master page of each page, in order: the one its file names in the
manifest, otherwise @body@, otherwise the first by name.
-}
pageMasters :: PdfInput -> PageGeometry -> PdfLayout -> [Maybe MasterGeometry]
pageMasters inp geom layout = map masterOf (pageFiles inp layout)
  where
    ms = pgMasters geom
    masterOf fid =
      (Map.lookup fid (piMasters inp) >>= (`Map.lookup` ms))
        <|> Map.lookup "body" ms
        <|> fmap snd (Map.lookupMin ms)

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
              runningHeadLines meta projectVars (Map.findWithDefault Map.empty fid (piRunningVars inp)) (if odd (poNumber p) then co else ce) st (startedOn p)
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
    wide =
      [ (t, n)
      | (n, ls) <- Map.toList (runningHeads inp geom layout),
        t <- ls,
        plainWidth fonts (bodyRole (piStyle inp)) (pgFontSize geom) t > rectW (typeAreaFor geom n)
      ]

-- | The width of a text set in a role at a size, unjustified.
plainWidth :: LoadedFonts -> Text -> Sp -> Text -> Sp
plainWidth fonts role size txt = sum [L.zwToSp size (shAdvance g) | g <- lfShape fonts (Shaping role False [] False) txt]

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
      leader = Line [Box u (BoxContent "…" False 0 0 (fromEnum KindText) (tgLook tg) 0 0 [] 0 0 noBoxSource Nothing noLeaf 0) | _ <- [1 .. k]] 0 (fromInteger k * u) 0 (0, 0) 0 (0, 0)
   in TocPage (le - fromInteger k * u) leader ns number

-- | The measure of a column of the page.
columnMeasure :: PageGeometry -> Sp
columnMeasure geom = case pgColumns geom of
  (c : _) -> if pgVertical geom then rectH c else rectW c
  [] -> 0

-- | A page number set as a number in the body (golem-driver ADR 0009): its boxes as a line.
pageNumberLine :: ComposeEnv -> Integer -> Line
pageNumberLine env n =
  let boxes = [b | b@Box {} <- fst (composeInlines env [Number (mkSpan (FileId 0) 0 0) n Nothing])]
      w = sum (map itemWidth boxes)
   in Line boxes 0 w 0 (0, 0) 0 (0, 0)

-- | W and u, measured once in the body role at the type size.
tocMetrics :: ComposeEnv -> (Sp, Sp)
tocMetrics env =
  let width is = sum [w | Box w _ <- fst (composeInlines env is)]
      sp0 = mkSpan (FileId 0) 0 0
   in (width [Number sp0 999 Nothing], width [Text sp0 "…"])

tocGeometry :: Style -> PageGeometry -> LoadedFonts -> TocGeometry
tocGeometry style geom fonts =
  let fs = pgFontSize geom
      env = composeEnv style geom fonts (Assumed Map.empty Map.empty) (bodyLook style fs)
      (w, u) = tocMetrics env
   in TocGeometry (columnMeasure geom) w (Sp (unSp fs `div` 2)) u (stTocLeader style == "dots") (ceLook env)

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
            Just cells -> T.intercalate " " (map setLineText cells)
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

{- | The lines of the index (golem-driver ADR 0007): a main entry and its
pages, sub-entries indented by a full-width space below their main entry
(which is shown once, without pages when it has no mark of its own).
Pages are numbers, in order, each once; a mark without a page is left
out. The groups come sorted from S1.
-}
indexLines :: Bool -> (SrcSpan -> Maybe Integer) -> [IndexGroup] -> [[Inline]]
indexLines vertical pageOf = go Nothing
  where
    sp0 = mkSpan (FileId 0) 0 0
    txt = Text sp0
    go _ [] = []
    go prevMain (g : gs) = case (igTerms g, igReadings g) of
      ([t], [r]) -> entry [] t (pageNumbersOf g) : go (Just (t, r)) gs
      ([t, sub], [r, _]) -> [[txt t] | prevMain /= Just (t, r)] <> [entry [txt "　"] sub (pageNumbersOf g)] <> go (Just (t, r)) gs
      _ -> go prevMain gs
    pageNumbersOf g = Set.toAscList (Set.fromList [n | (_, sp) <- igLocations g, Just n <- [pageOf sp]])
    entry prefix term ps =
      prefix <> [txt term] <> (if null ps then [] else txt "　" : intercalate [txt (if vertical then "、" else ", ")] [[Number sp0 n Nothing] | n <- ps])

{- | The lines of the list of a channel of a plugin (golem-doc ADR 0007):
the body of each entry, and with locators an ideographic space and its
pages as in the index.
-}
channelLines :: Bool -> (SrcSpan -> Maybe Integer) -> Bool -> [ChannelEntry] -> [[Inline]]
channelLines vertical pageOf locators = map line
  where
    sp0 = mkSpan (FileId 0) 0 0
    line e =
      let ps = Set.toAscList (Set.fromList [n | (_, sp) <- ceLocations e, Just n <- [pageOf sp]])
       in ceBody e <> (if not locators || null ps then [] else Text sp0 "　" : intercalate [Text sp0 (if vertical then "、" else ", ")] [[Number sp0 n Nothing] | n <- ps])

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
      Sidenote sp _ xs -> (sp, flow) : concatMap (inlineSites flow) xs
      Note _ _ xs -> concatMap (inlineSites False) xs
      Kenten _ _ xs -> concatMap (inlineSites flow) xs
      Color _ _ xs -> concatMap (inlineSites flow) xs
      CharStyle _ _ xs -> concatMap (inlineSites flow) xs
      _ -> []

-- | The block of each label, where G07021 points (golem-driver ADR 0016).
labelSpans :: Book -> Map Text SrcSpan
labelSpans book = Map.fromListWith (\_ old -> old) (concatMap site (concat [bs | Document _ bs <- bookDocs book]))
  where
    site (Block sp l lang body) =
      [(name, sp) | Just name <- [l]] <> case body of
        BulletList items -> concatMap (concatMap site . itemBlocks) items
        OrderedList items -> concatMap (concatMap site . itemBlocks) items
        DefList gs -> concatMap (concatMap (concatMap site) . dgDefs) gs
        FigureBlock fig -> concatMap site (figCaption fig)
        _ -> []

{- | Numbers of notes that the notation of [notes] mark-format cannot
write (docs/adr/0177): G07102 at the note, whatever the target.
-}
noteNumberDiagnostics :: Style -> Book -> [Diagnostic]
noteNumberDiagnostics style book =
  [ diagnostic "G07102" Error sp ("注の番号 " <> T.pack (show n) <> " は、[notes] の mark-format " <> renderMarkFormat fmt <> " で表せません")
  | d <- bookDocs book,
    (sp, n, _) <- documentNotes d,
    null (writeNumber (mfNotation fmt) (toInteger n))
  ]
  where
    fmt = stNotesMarkFormat style

{- | Places the sidenotes of a page in its sidenote column (golem-driver
ADR 0006): each wants the top of the line of its marker; they keep their
order, half a body pitch apart. Takes the sidenote pitch and size of a
sidenote by its span (docs/adr ADR 0014).
-}
placePageSidenotes :: PageGeometry -> (SrcSpan -> (Sp, Sp)) -> Map Int SetLine -> PageOut -> Either [Diagnostic] [PlacedSidenote]
placePageSidenotes geom metricsOf lineMap p =
  let bodyPitch = pgLinePitch geom
      lineIds = \case
        SLine lid -> [lid]
        SHeading lid m -> [lid .. lid + m - 1]
        _ -> []
      notes =
        [ (sp, fromIntegral slot * bodyPitch, ls)
        | (slot, s) <- sortOn fst (poSlots p),
          lid <- lineIds s,
          Just sl <- [Map.lookup lid lineMap],
          (sp, ls) <- slSidenotes sl
        ]
      height sp ls = let (pitch, size) = metricsOf sp in fromIntegral (max 1 (length ls) - 1) * pitch + size
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

-- | The page numbers assumed in a round of S2: of labels and of index marks (golem-driver ADR 0007).
data Assumed = Assumed
  { asLabels :: !(Map Text Integer),
    asMarks :: !(Map SrcSpan Integer)
  }
  deriving stock (Eq, Show)

{- | S2: lays out with assumed page numbers until the pages of the labels
and index marks settle. A round that fails stops it with its errors;
after 'maxIterations' rounds, G07021 names what still moves and is at the
first of them (golem-driver ADR 0016): the block of a label (@labelSpan@)
or an index mark.
-}
fixpoint :: (Text -> SrcSpan) -> (SrcSpan -> Text) -> (Assumed -> IO (Either [Diagnostic] (b, [PageOut]))) -> IO (Either [Diagnostic] (b, [PageOut]))
fixpoint labelSpan termOf layoutWith = go (1 :: Int) (Assumed Map.empty Map.empty)
  where
    go i assumed = do
      r <- layoutWith assumed
      case r of
        Left ds -> pure (Left ds)
        Right (built, pages) ->
          let actual = Assumed (labelPages pages) (markPages pages)
           in if actual == assumed
                then pure (Right (built, pages))
                else
                  if i >= maxIterations
                    then pure (Left [notSettled (moved actual asLabels) (moved actual asMarks)])
                    else go (i + 1) actual
      where
        moved :: (Ord k) => Assumed -> (Assumed -> Map k Integer) -> [k]
        moved now field = [k | k <- Map.keys (Map.union (field now) (field assumed)), Map.lookup k (field now) /= Map.lookup k (field assumed)]
    notSettled labels marks =
      let named = [(labelSpan l, l) | l <- labels] <> nubOrdOn snd [(m, termOf m) | m <- marks]
          sites = map fst named
       in (diagnostic "G07021" Error (fromMaybe (mkSpan (FileId 0) 0 0) (listToMaybe sites)) ("ページ番号の参照が収束しません: " <> T.intercalate ", " (map snd named)))
            { diagRelated = [(sp, "ページが定まりません") | sp <- drop 1 sites]
            }

{- | The composition environment of a unit set in a font role at a size
(golem-driver ADR 0003).
-}
composeEnv :: Style -> PageGeometry -> LoadedFonts -> Assumed -> Look -> ComposeEnv
composeEnv style geom fonts assumed look =
  let comp = stComposition style
      shaping = shapingOf (pgVertical geom)
   in (defaultComposeEnv (lkSize look))
        { ceAdvance = \lk c -> lfAdvance fonts (shaping lk c) c,
          ceWordAdvance = \lk t -> lfWordAdvance fonts (maybe (Shaping (lkLatinFace lk) False [] False) (shaping lk . fst) (T.uncons t)) t,
          ceKern = \lk a b -> lfPairKern fonts (shaping lk a) a b,
          ceLook = look,
          ceRestyle = restyle style,
          ceSizeSourceOf = restyleSource style,
          ceVertical = pgVertical geom,
          ceKinsokuStrict = compKinsokuStrict comp,
          ceHanging = compHanging comp,
          ceProtrusion = compProtrusion comp,
          ceExplicitHyphenPenalty = compExplicitHyphenPenalty comp,
          ceRuby = rubyStyleOf style (lkSize look),
          ceVerticalNumbers = verticalNumbersNamed (stNumbersVertical style),
          ceRefPageNumbers = case fromMaybe (stNumbersVertical style) (stNumbersRefPage style) of
            "sideways" -> Nothing
            v -> Just (verticalNumbersNamed v),
          cePageOf = (`Map.lookup` asLabels assumed),
          ceSidenoteMarker = case snMarker <$> stSidenotes style of
            Just "symbol" -> MarkerSymbol
            Just "none" -> MarkerNone
            _ -> MarkerNumber,
          -- Latin words: the patterns of the language of their span, US English outside one (golem-layout ADR 0001, docs/adr ADR 0187)
          cePatterns = patternsFor,
          -- the set of body; a paragraph, a caption and a sidenote take their style's (docs/adr ADR 0019)
          ceAkiSet = akiSetOf style Nothing,
          -- the text of note marks (golem-driver ADR 0025) and their character style (docs/adr/0177)
          ceNoteMarkFormat = stNotesMarkFormat style,
          ceNoteMarkLook = noteMarkLook style,
          ceNoteMarkSource = noteMarkSource style
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
noteAnchors :: [Golem.Layout.Japanese.Anchor] -> [(Int, NoteId, Int, [Inline])]
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
withNoteMark style vertical sp n body = styled (markInlines sp (markParts vertical pre notation (toInteger n) suf)) <> (Aki sp (AkiZw (1 / 4)) : body)
  where
    MarkFormat pre notation suf = stNotesMarkFormat style
    -- in the character style of [notes] body-mark-style (docs/adr/0177)
    styled xs = maybe xs (\name -> [CharStyle sp name xs]) (stNotesBodyMarkStyle style)

-- | How many inlines the mark of a note is in 'withNoteMark': the label of the Note (docs/adr ADR 0183).
noteMarkCount :: Style -> Bool -> SrcSpan -> Int -> Int
noteMarkCount style vertical sp n = length (withNoteMark style vertical sp n []) - 1

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
    uLang :: Maybe Text
  }

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
  | {- | a note at the end of a chapter, by its span, and how many inlines
    its mark is: in the tree after its mark
    -}
    FEndNote !SrcSpan !Int
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
  UPara i -> case inAlign i of
    ParaLeft -> A.Ragged A.LineStart
    ParaCenter -> A.Ragged A.LineCenter
    ParaRight -> A.Ragged A.LineEnd
    ParaLeftJustified -> A.Justified (Just A.LineStart)
    ParaCenterJustified -> A.Justified (Just A.LineCenter)
    ParaRightJustified -> A.Justified (Just A.LineEnd)
    ParaFullyJustified -> A.Justified Nothing
    ParaTowardsSpine -> A.Ragged A.LineStart
    ParaAwayFromSpine -> A.Ragged A.LineStart
  _ -> A.Justified (Just A.LineStart)

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
alignToSpine :: PageGeometry -> [PageOut] -> Map Int SetLine -> Map Int SetLine
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
  | UHeading Int Text Bool
  | -- | the title of the notes at the end of a chapter, set as a heading of level 2 (golem-driver ADR 0026)
    UNotesTitle Text
  | -- | a term of a definition list; indented in a list item (golem-driver ADR 0013)
    UTerm !Indent
  | UFigure Figure
  | UTable [Alignment] [[Inline]] [[[Inline]]]
  | -- | grid lines between paragraphs of a style (docs/adr ADR 0005)
    UGap Int
  | -- | an entry of the table of contents: its level and its heading (golem-driver ADR 0009)
    UTocEntry Int SrcSpan
  | -- | a forced break (docs/adr ADR 0017)
    UBreak !BreakKind
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
unitsOf :: Text -> Book -> PageGeometry -> Maybe ColumnSet -> (FileId -> Style) -> (SrcSpan -> Maybe Integer) -> Map Text [EntryPart] -> [Unit]
unitsOf lang book geom indexSet styleOf pageOf bib = concat (snd (mapAccumL chapter 0 (bookChapters book)))
  where
    fs = pgFontSize geom
    doc n (Document fid bs) = blocks (styleOf fid) [] True n bs
    {- the documents of a chapter of the manifest; at the end of the chapter,
    before the breaks that end its last file, its notes when they are set
    there (golem-driver ADR 0026) -}
    chapter n docs =
      let (n', uss) = mapAccumL doc n docs
          us = concat uss
       in (n',) $ case reverse docs of
            (Document fid _ : _)
              | stNotesPlacement (styleOf fid) == PlaceChapterEnd ->
                  let (breaks, body) = span isBreakUnit (reverse us)
                   in reverse body <> notesList (styleOf fid) docs <> reverse breaks
            _ -> us
    -- blank lines at the end of a file go before the first block of the next (docs/adr ADR 0046)
    isBreakUnit u = case uKind u of
      UBreak _ -> True
      UBlank _ -> True
      _ -> False
    -- the title and a paragraph for each note, its mark first, as at the foot of a page
    notesList style docs = case concatMap documentNotes docs of
      [] -> []
      ns@((sp, _, _) : _) ->
        let title = notesTitle lang
         in Unit (UNotesTitle title) Nothing [Text sp title] sp (uncurry (styleLook style Nothing) (headingFace lang style geom 2)) style [] Nothing Nothing (Nothing, Nothing) Nothing (SourceHeading 2) [] 0 Nothing
              : [Unit (UPara noIndent) Nothing (withNoteMark style (pgVertical geom) nsp n xs) nsp (bodyLook style fs) style [] Nothing Nothing (Nothing, Nothing) Nothing SourceGrid [frame 0 (FEndNote nsp (noteMarkCount style (pgVertical geom) nsp n))] 0 Nothing | (nsp, n, xs) <- ns]
    {- a list of blocks inside the lists @ctx@, from the list number @n@,
    with the spaces before and after of paragraphs when @spaced@ (not in a
    definition list): in a list item, paragraphs are not indented by their
    style (docs/adr ADR 0006) but by the lists (golem-driver ADR 0013) -}
    blocks style ctx spaced n bs =
      let (n', uss) = mapAccumL (\k (prev, b) -> (gapBefore style ctx spaced prev b <>) <$> block style ctx k b) n (zip (scanl before Nothing bs) bs)
       in (n', concat uss)
    gapBefore style ctx spaced prev (Block sp _ _ b) = case prev of
      Just (Block _ _ _ a)
        | g <- gapLines style ctx spaced a b,
          g > 0 ->
            [Unit (UGap g) Nothing [] sp (bodyLook style fs) style ctx Nothing Nothing (Nothing, Nothing) Nothing SourceGrid [] 0 Nothing]
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
      (BlankLines _, _) -> 0
      (_, BlankLines _) -> 0
      (_, ForcedBreak _) -> 0
      (_, PageControl _) -> 0
      (Paragraph s1 _, Paragraph s2 _) | s1 == s2 -> fromMaybe 0 (paraStyle style s2 >>= psSpaceBetween)
      _ -> max (spaceOf psSpaceAfter a) (spaceOf psSpaceBefore b)
      where
        spaceOf key = \case
          Paragraph st _ | spaced, null ctx -> fromMaybe 0 (paraStyle style st >>= key)
          _ -> 0
    -- the block before, past the controls of page breaks (docs/adr ADR 0030)
    before prev b = case blockBody b of
      PageControl _ -> prev
      _ -> Just b
    -- a block with a language: the language of its characters and the /Lang of its element (docs/adr ADR 0187)
    block style ctx n b = withBlockLang (blockLang b) <$> blockUnits style ctx n b
    blockUnits style ctx n (Block sp lbl _ body) =
      let unit kind l is face src = Unit kind l is sp face style ctx Nothing Nothing (Nothing, Nothing) Nothing src [] 0 Nothing
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
                  us = [(unit (UPara (if null ctx then ind else noIndent)) (if i == 0 then lbl else Nothing) part face (paraSizeSource style st)) {uParaStyle = st, uRules = rulesOf i, uStanza = stanzaOf i} | (i, part) <- zip [0 :: Int ..] parts]
               in -- the lines of the paragraph are one P (docs/adr ADR 0183)
                  if length parts > 1 then (n + 1, inFrame (frame n FPara) us) else (n, us)
            Heading l attrs is ->
              let num = Map.lookup sp (bookHeadings book) >>= hiNumberText
                  -- the number is at the heading (golem-cli ADR 0008)
                  title = numberedTitle lang sp (if haNoNumber attrs then Nothing else num) is
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
            Table aligns h rows -> (n, [plainUnit (UTable aligns h rows) lbl []])
            -- always in the paragraph style code (golem-driver ADR 0017)
            CodeBlock code -> (n, [unit (UCode 0 code) lbl [] (codeLook style geom) (paraSizeSource style (Just "code"))])
            FigureBlock fig -> (n, [plainUnit (UFigure fig) lbl []])
            -- S1 has dropped the index marks and channel items of the title (docs/adr/0145)
            ChannelOutput (TocOutput depth) -> (n + 1, inFrame (frame n FToc) [plainUnit (UTocEntry (teLevel e) (teSpan e)) Nothing (numberedTitle lang (teSpan e) (teNumber e) (teTitle e)) | e <- bookToc book, teLevel e <= depth])
            ChannelOutput IndexOutput ->
              let entries kind = inFrame (frame n FIndex) [plainUnit kind Nothing is | is <- indexLines (pgVertical geom) pageOf (indexAt book sp)]
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
            PageControl c -> (n, [plainUnit (UPageControl c) Nothing []])
            BlankLines k -> (n, [plainUnit (UBlank k) Nothing []])
    {- the items of the list numbered n: their units are inside it, the first
    unit of an item that starts with a paragraph carries the marker -}
    list style ctx n items =
      let ctx' = ctx <> [n]
          marker = listMarker style (pgVertical geom) (length ctx')
          item k (j, (num, it)) =
            let (k', us) = blocks style ctx' True k (itemBlocks it)
             in (k', inFrame (frame j FItem) (if startsWithParagraph it then markFirst (marker num) us else us))
          (n', uss) = mapAccumL item (n + 1) (zip [0 ..] items)
          numbered = any (isJust . fst) items
       in (n', inFrame (frame n (FList numbered)) (concat uss))
    startsWithParagraph it = case itemBlocks it of
      (Block _ _ _ (Paragraph {}) : _) -> True
      _ -> False
    -- the marker is at the block of its paragraph (golem-cli ADR 0008)
    markFirst m = \case
      (u : rest) -> u {uMarker = Just (map (atSpan (uSpan u)) m)} : rest
      [] -> []
    atSpan s = \case
      Text _ t -> Text s t
      Number _ k st -> Number s k st
      Tcy _ t -> Tcy s t
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
    cSidenotes :: [(Int, SrcSpan, [Line])],
    -- | index marks: the item index they belong to (a note's marks go with the note) and the mark
    cMarks :: [(Int, SrcSpan)],
    cAnchors :: [Golem.Layout.Japanese.Anchor],
    cItems :: [Item],
    -- | the items of a list marker before the text: the item indices of the anchors are shifted by it (golem-driver ADR 0013)
    cShift :: Int
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
    feSourceAt :: SrcSpan -> Text -> Int -> Int
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
          feSourceAt = sourceAt (Map.map (TE.encodeUtf8 . sfText) (projectSources (piProject inp)))
        }

-- | The composition of a look; citations show their numbers (golem-driver ADR 0007).
lookEnv :: FlowEnv -> Look -> ComposeEnv
lookEnv fe lk = (composeEnv (piStyle (feInput fe)) (feGeom fe) (feFonts fe) (feAssumed fe) lk) {ceCiteNumber = citeNumber (piBook (feInput fe)), ceSourceAt = feSourceAt fe}

-- | A composition with the character styles of the style of a document (docs/adr ADR 0014).
withDocStyle :: Style -> ComposeEnv -> ComposeEnv
withDocStyle st e = e {ceRestyle = restyle st, ceSizeSourceOf = restyleSource st}

-- | The composition of the text of a unit: its look, its document's style and the aki set of its paragraph style.
unitEnv :: FlowEnv -> Unit -> ComposeEnv
unitEnv fe u = (withDocStyle (uStyle u) (lookEnv fe (uLook u))) {ceAkiSet = akiSetOf (uStyle u) (uParaStyle u), ceLabelInlines = unitLabelInlines u}

{- | How many inlines at the start of a unit are its label (docs/adr ADR
0183): the mark and its space of a note at the end of a chapter, the
number of an entry of the bibliography.
-}
unitLabelInlines :: Unit -> Int
unitLabelInlines u = case [k | Frame _ k _ <- uFrames u] of
  ks
    | (k : _) <- [k | FEndNote _ k <- ks] -> k
    | FBibliography `elem` ks -> 1
    | otherwise -> 0

{- | The units of the body in order, numbered from 0, and the marker width
M of each list; a unit in lists is indented by them (golem-driver ADR 0013).
-}
flowUnits :: FlowEnv -> ([(Int, Unit)], Map Int Sp)
flowUnits fe = ([(i, (withListIndent u) {uIndex = i}) | (i, u) <- zip [0 :: Int ..] rawUnits], widths)
  where
    inp = feInput fe
    geom = feGeom fe
    style = piStyle inp
    -- a mark without an assumed page yet stands at page 1 in the first round
    markPage sp = Map.lookup sp (asMarks (feAssumed fe)) <|> (if Map.null (asMarks (feAssumed fe)) then Just 1 else Nothing)
    rawUnits = unitsOf (bookLanguage inp) (piBook inp) geom (indexColumnSet style geom) (docStyle inp) markPage (piBibliography inp)
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
  _ -> feMeasure fe - unitLineIndent (pgFontSize (feGeom fe)) kind k - unitEndIndent kind - (case kind of UTocEntry {} -> feTocReserve fe; _ -> 0)

-- | The end indent of the lines of a unit of the kind (docs/adr/0189).
unitEndIndent :: UnitKind -> Sp
unitEndIndent = \case
  UPara i -> inEnd i
  _ -> 0

-- | How far line k of a unit of the kind starts from the line start, at the font size of the grid.
unitLineIndent :: Sp -> UnitKind -> Int -> Sp
unitLineIndent fs = \case
  UPara (Indent s f _ _) -> \k -> if k == (0 :: Int) then s + f else s
  UTerm (Indent s _ _ _) -> const s
  UTocEntry l _ -> const (tocIndent fs l)
  _ -> const 0

-- | The indent of a table of contents entry of a level (golem-driver ADR 0009).
tocIndent :: Sp -> Int -> Sp
tocIndent fs l = fromIntegral (l - 1) * fs

{- | The marker of a list item: its boxes and an empty box up to Mi, before
the text with no glue or penalty between them (golem-driver ADR 0013).
-}
markerItems :: ComposeEnv -> Sp -> Unit -> [Item]
markerItems env inner u = case uMarker u of
  Nothing -> []
  Just m ->
    let boxes = [b | b@Box {} <- fst (composeInlines env {ceSite = markerSite (uIndex u), ceLabelInlines = 0} m)]
        w = sum (map itemWidth boxes)
     in boxes <> [Box (inner - w) (BoxContent "" False 0 0 (fromEnum KindText) (ceLook env) 0 0 [] 0 0 (uSource u, uSpan u) Nothing noLeaf (spanStart (uSpan u)))]

-- | Composes a unit and breaks it into lines of the widths, with its notes, sidenotes and index marks.
composeUnit :: FlowEnv -> Map Int Sp -> (Int -> Sp) -> Unit -> Composed
composeUnit fe widths lineWidth u =
  let env = (unitEnv fe u) {ceSizeSource = uSource u, ceSite = unitSiteOf u}
      marker = markerItems env (listInner widths u) u
      -- the anchors count the items of the text; the marker comes first
      shift = length marker
      (textItems, anchors) = composeInlines env (uInlines u)
      items = marker <> textItems
      lines' = brLines (A.breakAligned (layoutAlign (uKind u)) (feParams fe) lineWidth items)
   in Composed lines' (unitNotes fe u anchors) (unitSidenotes fe u shift anchors) (unitMarks fe u shift anchors) anchors items shift

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
   in (withDocStyle (uStyle u) (lookEnv fe ((styleLook (uStyle u) (Just "caption") captionRole cs) {lkLang = lkLang (uLook u)}))) {ceAkiSet = akiSetOf (uStyle u) (Just "caption"), ceSizeSource = paraSizeSource (uStyle u) (Just "caption"), ceSite = captionSite (uIndex u)}

-- | The composition of the cells of a table: the body size, no hanging punctuation (golem-driver ADR 0008), in the language of the table (docs/adr ADR 0187).
tableEnv :: FlowEnv -> Style -> Maybe Text -> ComposeEnv
tableEnv fe st lang = let env = withDocStyle st (feBodyEnv fe) in env {ceHanging = False, ceLook = (ceLook env) {lkLang = lang}}

-- | The composition of the notes and sidenotes of a unit: the body size of its document's style.
noteEnv :: FlowEnv -> Style -> ComposeEnv
noteEnv fe st = (withDocStyle st (lookEnv fe (bodyLook st (pgFontSize (feGeom fe))))) {ceAkiSet = akiSetOf st Nothing}

-- | The footnotes of a unit, each a paragraph of its own; none when the notes are at the end of the chapter (golem-driver ADR 0026).
unitNotes :: FlowEnv -> Unit -> [Golem.Layout.Japanese.Anchor] -> [(NoteId, [Line])]
unitNotes fe u anchors =
  [ (k, brLines (breakParagraph (feParams fe) (const (feMeasure fe)) (fst (composeInlines (noteEnv fe (uStyle u)) {ceSite = noteSite k, ceLabelInlines = noteMarkCount (uStyle u) (pgVertical (feGeom fe)) (noteIdSpan k) n} (withNoteMark (uStyle u) (pgVertical (feGeom fe)) (noteIdSpan k) n nbody)))))
  | not (feNotesAtEnd fe),
    (_, k, n, nbody) <- noteAnchors anchors
  ]

-- | The sidenotes of a unit: the item index of the marker after the list marker, the span and the lines.
unitSidenotes :: FlowEnv -> Unit -> Int -> [Golem.Layout.Japanese.Anchor] -> [(Int, SrcSpan, [Line])]
unitSidenotes fe u shift anchors = [(i + shift, sp, sidenoteLines fe (uStyle u) sp n snBody) | AnchorSidenote i n sp snBody <- anchors]

-- | The index marks of a unit, those of its notes and sidenotes with the item of their marker.
unitMarks :: FlowEnv -> Unit -> Int -> [Golem.Layout.Japanese.Anchor] -> [(Int, SrcSpan)]
unitMarks fe u shift anchors =
  [(i + shift, sp) | AnchorIndex i sp _ <- anchors]
    <> [(i + shift, sp) | not (feNotesAtEnd fe), AnchorNote i _ _ nbody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines env nbody)]
    <> [(i + shift, sp) | AnchorSidenote i _ _ snBody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines env snBody)]
  where
    env = noteEnv fe (uStyle u)

{- | The lines of a sidenote body: their size, the column width, the marker
first (golem-driver ADR 0006), in the role and size of the paragraph style
sidenote of the document (docs/adr ADR 0014).
-}
sidenoteLines :: FlowEnv -> Style -> SrcSpan -> Int -> [Inline] -> [Line]
sidenoteLines fe st sp n snBody =
  let geom = feGeom fe
      (_, snSize', _) = sidenoteMetrics st geom
      prefix = sidenotePrefix fe sp n
      snEnv = (sidenoteEnv fe st) {ceSite = sidenoteSite sp n, ceLabelInlines = length prefix}
      snParams = (feParams fe) {pEmergencyStretch = dimToSp snSize' (compEmergencyStretch (stComposition (piStyle (feInput fe))))}
      snMeasure = maybe 0 (rectW . fst) (pgSidenotes geom)
   in brLines (breakParagraph snParams (const snMeasure) (fst (composeInlines snEnv (prefix <> snBody))))

-- | The composition of sidenotes: the role and size of the paragraph style sidenote of the document (docs/adr ADR 0014).
sidenoteEnv :: FlowEnv -> Style -> ComposeEnv
sidenoteEnv fe st =
  let (snRole, snSize', _) = sidenoteMetrics st (feGeom fe)
   in (withDocStyle st (lookEnv fe (styleLook st (Just "sidenote") snRole snSize'))) {ceAkiSet = akiSetOf st (Just "sidenote"), ceSizeSource = paraSizeSource st (Just "sidenote")}

-- | The number of a sidenote before its body; it is at the sidenote (golem-cli ADR 0008).
sidenotePrefix :: FlowEnv -> SrcSpan -> Int -> [Inline]
sidenotePrefix fe sp n = case ceSidenoteMarker (feBodyEnv fe) of
  MarkerNumber -> [Text sp (T.pack (show n) <> " ")]
  MarkerSymbol -> [Text sp "※ "]
  MarkerNone -> []

{- | The notes, sidenotes and index marks of composed inlines in the body
size of a document's style, by the line that holds them.
-}
anchoredByLine :: FlowEnv -> Style -> [Item] -> [Golem.Layout.Japanese.Anchor] -> [Line] -> (Map Int [(NoteId, [Line])], Map Int [(SrcSpan, [Line])], Map Int [SrcSpan])
anchoredByLine fe st items anchors ls =
  let lineOf = lineIndexOfItems items ls
      env = withDocStyle st (feBodyEnv fe)
      noteBody k n b = brLines (breakParagraph (feParams fe) (const (feMeasure fe)) (fst (composeInlines env {ceSite = noteSite k, ceLabelInlines = noteMarkCount (piStyle (feInput fe)) (ceVertical env) (noteIdSpan k) n} (withNoteMark (piStyle (feInput fe)) (ceVertical env) (noteIdSpan k) n b))))
      marksIn b = [sp | AnchorIndex _ sp _ <- snd (composeInlines env b)]
      atEnd = feNotesAtEnd fe
   in ( Map.fromListWith (flip (<>)) [(lineOf i, [(k, noteBody k n b)]) | not atEnd, (i, k, n, b) <- noteAnchors anchors],
        Map.fromListWith (flip (<>)) [(lineOf i, [(sp, sidenoteLines fe st sp n b)]) | AnchorSidenote i n sp b <- anchors],
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
      captionInlines = numberedTitle (bookLanguage inp) (uSpan u) number (concat [is | Block _ _ _ (Paragraph _ is) <- figCaption fig])
      -- the caption in the role and size of the paragraph style caption (golem-driver ADR 0010)
      (_, cs) = paraFace (uStyle u) geom "caption"
      captionParams = (feParams fe) {pEmergencyStretch = dimToSp cs (compEmergencyStretch (stComposition style))}
      (captionItems, captionAnchors) = composeInlines (captionEnv fe u) captionInlines
      captionAt len = if null captionInlines then [] else brLines (breakParagraph captionParams (const len) captionItems)
      -- the grid lines a caption of k lines takes: the fewest that hold it, its pitch in the body's ratio of pitch to size
      captionSpanOf k = if k == 0 then (pitch, 0) else let cb' = headingBlock fs pitch cs k 1 in (hbPitch cb', hbSpan cb')
      -- the caption in the measure before fitting (golem-driver ADR 0034)
      caption = captionAt (if isJust (figWrap fig) then alongSp else lineLen)
      captionMarks = [sp | AnchorIndex _ sp _ <- captionAnchors]
      n = length caption
      (cp, span') = captionSpanOf n
      -- the grid lines of the column, or of the frame
      gridLines = if turned then frameLines else capacity
      fitOf len k s = fitFigure ratio len k pitch fs (if s == 0 then Nothing else Just s)
      -- step 1 of golem-driver ADR 0034 as docs/adr/0190 has it: along1 is along0 within the measure; fitted when the last along is shorter than along0
      (alongFit, across, fitted) = case figWrap fig of
        Nothing -> let (a, c, _) = fitOf (min alongSp lineLen) gridLines span' in (a, c, a < alongSp)
        Just _ -> (alongSp, Sp (floor (fromInteger (unSp alongSp) * ratio)), False)
      m = fromInteger (unSp (across + pitch - 1) `div` unSp pitch)
      -- the size the figure would take turned, to tell the writer (golem-driver ADR 0034)
      turnedArea =
        let s = snd (captionSpanOf (length (captionAt frameAlong)))
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
      errs = case (figWrap fig, ex) of
        -- no wrapping on a page of columns (docs/adr ADR 0018)
        (Just _, _)
          | length (pgColumns geom) > 1 -> [diagnostic "G07026" Error (uSpan u) "段組みの版面では図版を回り込ませられません。wrap を外すか、columns を 1 にしてください"]
        (Just _, Just e)
          | isNothing written || measure - exWidth e < 8 * fs ->
              [diagnostic "G07022" Error (uSpan u) ("回り込む図版の幅が不正です。行の残りを本文の 8 字分以上にしてください: " <> fromMaybe "" (figWidth fig))]
          | exLines e > capacity -> [diagnostic "G07023" Error (uSpan u) ("回り込む図版の除外領域が一ページの行数を超えます（" <> T.pack (show (exLines e)) <> " 行）")]
        -- a caption that leaves no line for the image (golem-driver ADR 0034)
        _
          | tooDeep -> [diagnostic "G07038" Error (uSpan u) ("図版のキャプションが" <> place' <> "の行数に達します（" <> T.pack (show span') <> " 行。" <> place' <> "は " <> T.pack (show gridLines) <> " 行）")]
          | otherwise -> []
      turn
        | not turned = Nothing
        | pgVertical geom = Just P.TurnedRight
        | otherwise = Just P.TurnedLeft
   in (PlacedFigure content alongFit across (figWrap fig) m caption cs cp span' ex (figSource fig) (snd (figureKey fig)) (uSpan u) (if isJust (figWrap fig) then alongSp else lineLen) turn (uIndex u), errs, notices, captionMarks)

{- | The paragraphs right after a wrapped figure, in order, composed beside
its exclusion: each by its index, with the line of the exclusion it starts
at. A paragraph with rules is not set beside a figure (golem-driver ADR
0027).
-}
composeBeside :: FlowEnv -> Map Int Sp -> Map Int Unit -> Int -> Exclusion -> IO [(Int, (Composed, Int))]
composeBeside fe widths unitAt i ex = go (i + 1) 0
  where
    go j offset
      | offset >= exLines ex = pure []
      | Just u@Unit {uKind = UPara _, uRules = (Nothing, Nothing)} <- Map.lookup j unitAt = do
          c <- forceComposed (composeUnit fe widths (\k -> wrappedLineWidth (feMeasure fe) ex offset k - unitLineIndent (pgFontSize (feGeom fe)) (uKind u) k - unitEndIndent (uKind u)) u)
          ((j, (c, offset)) :) <$> go (j + 1) (offset + length (cLines c))
      | otherwise = pure []

-- | A composed unit evaluated, so that the work is done where it is run.
forceComposed :: Composed -> IO Composed
forceComposed c = evaluate (length (show (map lineRatio (cLines c))) + length (cNotes c) + length (show [map lineRatio ls | (_, _, ls) <- cSidenotes c]) + length (cAnchors c) + length (cItems c)) >> pure c

{- | A table: every cell at the body size, no hanging punctuation
(golem-driver ADR 0008), with the notes, sidenotes and index marks of each
line of each row, the header row first.
-}
composeTable :: FlowEnv -> Int -> Style -> Maybe Text -> [Alignment] -> [[Inline]] -> [[[Inline]]] -> Either TableRefusal (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [Line])], [SrcSpan])]])
composeTable fe i st lang aligns h rows
  -- counted before any cell is composed (docs/adr/0224)
  | cells > maxTableCells = Left (TooManyCells cells)
  | otherwise = first LayoutRefused (composeTableCells fe i st lang aligns h rows)
  where
    -- a header row of empty cells too, which is composed
    cells = length h + sum (map length rows)

{- | The most cells of a table set in PDF, the header row's included
(docs/adr/0224, G07108).
-}
maxTableCells :: Int
maxTableCells = 100000

-- | Why a table is not set: too many cells (G07108), or its layout (G07041).
data TableRefusal
  = TooManyCells !Int
  | LayoutRefused !TableError
  deriving stock (Show)

composeTableCells :: FlowEnv -> Int -> Style -> Maybe Text -> [Alignment] -> [[Inline]] -> [[[Inline]]] -> Either TableError (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [Line])], [SrcSpan])]])
composeTableCells fe i st lang aligns h rows =
  let env = tableEnv fe st lang
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
   in case layoutTable (feParams fe) (feMeasure fe) (pgFontSize (feGeom fe)) aligns (map fst header) (map (map fst) rCells) of
        Left e -> Left e
        Right t -> Right (t, rowAttached header (stHeader t) (stHeaderLines t) : zipWith3 rowAttached rCells (stRows t) (stRowLines t))

{- | The caption of a code block: the listing number, the separator of the
language of the book (golem-driver ADR 0042) and the caption, set as the
caption of a figure over the width of the block (golem-driver ADR 0023).
-}
codeCaptionOf :: FlowEnv -> Unit -> Sp -> Code -> CodeCaption
codeCaptionOf fe u lead code = case codeCaption code of
  Nothing -> CodeCaption [] fs pitch 0 []
  Just is ->
    let inp = feInput fe
        number = Map.lookup (uSpan u) (bookListings (piBook inp))
        captionInlines = numberedTitle (bookLanguage inp) (uSpan u) number is
        (_, cs) = paraFace (uStyle u) (feGeom fe) "caption"
        captionParams = (feParams fe) {pEmergencyStretch = dimToSp cs (compEmergencyStretch (stComposition (piStyle inp)))}
        (captionItems, captionAnchors) = composeInlines (captionEnv fe u) captionInlines
        ls = brLines (breakParagraph captionParams (const (feMeasure fe - lead)) captionItems)
        cb = headingBlock fs pitch cs (length ls) 1
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
    cuTables :: Map Int (Either TableRefusal (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [Line])], [SrcSpan])]])),
    cuCodeBlocks :: Map Int SetCode
  }

{- | The flow numbered so far, in document order (golem-driver ADR 0009):
the next line id, the flow, the set lines, the figures and the heading
blocks by their first lines, the errors, the lines and the geometry of
tables, and the headings and the table of contents entries by their lines.
-}
data Numbered = Numbered
  { nuNext :: Int,
    nuFlow :: [Flow],
    nuLines :: Map Int SetLine,
    nuFigures :: Map Int PlacedFigure,
    nuHeadings :: Map Int HeadingBlock,
    nuErrors :: [Diagnostic],
    nuTableLines :: Map Int [SetLine],
    nuTables :: Map Int TableGeometry,
    nuHeadingSpans :: Map Int SrcSpan,
    nuTocLines :: Map Int (SrcSpan, Sp)
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
      lineOfItem = lineIndexOfItems (cItems c) ls
      noteLines = Map.fromListWith (flip (<>)) [(lineOfItem (i + cShift c), [(k, nls)]) | ((i, _, _, _), (k, nls)) <- zip (noteAnchors (cAnchors c)) (cNotes c)]
      sidenoteLinesOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [(sp, sls)]) | (i, sp, sls) <- cSidenotes c]
      marksOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [sp]) | (i, sp) <- cMarks c]
      boxes = [LineBox lid [NoteBody key (length nls) | (key, nls) <- Map.findWithDefault [] k noteLines] (if k == 0 then unitLabel u else []) (Map.findWithDefault [] k marksOf) (lineReach fe l) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
      -- a line not justified moves by its alignment (docs/adr/0189)
      shiftOf k = A.lineShift (layoutAlign (uKind u)) (k == length ls - 1)
      set = Map.fromList [(lid, SetLine l size (indentOf k + shiftOf k l) (Map.findWithDefault [] k noteLines) (Map.findWithDefault [] k sidenoteLinesOf) (spineOf (uKind u))) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
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
spaceAfterCode :: Sp -> Sp -> [CodeInfo] -> [Flow] -> [Flow]
spaceAfterCode pitch fs infos = \case
  f@FCode {} : remaining -> case infos of
    ci : more -> f : [FSpace 1 | painted ci, reaches ci remaining] <> spaceAfterCode pitch fs more remaining
    [] -> f : spaceAfterCode pitch fs [] remaining
  f : remaining -> f : spaceAfterCode pitch fs infos remaining
  [] -> []
  where
    painted ci = isJust (ciBackground ci) || not (null (ciBands ci)) || isJust (ciBorder ci)
    reaches ci remaining = case remaining of
      next : _ | Just l <- firstLineOf next -> reachesBackground pitch fs (maybe 0 snd (ciBorder ci)) (lbOverhang l)
      _ -> False
    firstLineOf = \case
      FRuled {frBody = RuledLines (l : _)} -> Just l
      FRuled {frBody = RuledHeading _ _ (l : _)} -> Just l
      FParagraph (l : _) -> Just l
      FStanza vs | l : _ <- concat vs -> Just l
      FHeading {fhLines = l : _} -> Just l
      FDefTerm (l : _) -> Just l
      FTable {ftSpaceBefore = 0, ftHeader = l : _} -> Just l
      _ -> Nothing

-- | Numbers the lines of the next unit in document order.
numberUnit :: FlowEnv -> ComposedUnits -> Numbered -> (Int, Unit) -> Numbered
numberUnit fe cu nb (i, u) = case uKind u of
  UTable {} -> maybe nb (\r -> numberTable fe u r nb) (Map.lookup i (cuTables cu))
  _ -> headingAndTocLines (pgFontSize (feGeom fe)) cu (nuNext nb) i u (numberOther fe cu nb (i, u))

-- | Numbers the lines of a table, or adds its error (G07108, G07041, G07042).
numberTable :: FlowEnv -> Unit -> Either TableRefusal (SetTable, [[([(NoteId, [Line])], [(SrcSpan, [Line])], [SrcSpan])]]) -> Numbered -> Numbered
numberTable fe u r nb = case r of
  Left (TooManyCells n) ->
    nb {nuErrors = nuErrors nb <> [diagnostic "G07108" Error (uSpan u) ("表のセルが多すぎて PDF に組めません（" <> T.pack (show n) <> " 個、上限は " <> T.pack (show maxTableCells) <> " 個）")]}
  Left (LayoutRefused (ColumnsTooWide mn avail)) ->
    nb {nuErrors = nuErrors nb <> [diagnostic "G07041" Error (uSpan u) ("表の列の最小の幅の合計（" <> L.mmText mn <> "）が使える幅（" <> L.mmText avail <> "）に収まりません")]}
  Right (t, atts)
    | tall@(_ : _) <- [row | (row, h) <- zip [1 :: Int ..] (stRowLines t), stHeaderLines t + h > capacity] ->
        nb {nuErrors = nuErrors nb <> [diagnostic "G07042" Error (uSpan u) ("表の " <> T.pack (show row) <> " 行目が見出しの行とともに一ページに収まりません") | row <- tall]}
    | otherwise ->
        let heights = stHeaderLines t : stRowLines t
            starts = scanl (+) nextId heights
            rowsOut =
              [ ( [ LineBox lid [NoteBody key (length nls) | (key, nls) <- ns] (if lid == nextId then unitLabel u else []) ms (maximum (0 : [lineReach fe l | c <- cells, (j, l) <- zip [0 :: Int ..] (scLines c), j == k]))
                  | (k, (lid, (ns, _, ms))) <- zip [0 ..] (zip ids att)
                  ],
                  Map.fromList [(lid, SetLine emptyLine fs 0 ns sn Nothing) | (lid, (ns, sn, _)) <- zip ids att],
                  Map.fromList [(lid, [SetLine l fs (scOffset c + sh) [] [] Nothing | c <- cells, (j, (l, sh)) <- zip [0 :: Int ..] (zip (scLines c) (scShifts c)), j == k]) | (k, lid) <- zip [0 ..] ids]
                )
              | (start, h, cells, att) <- zip4 starts heights (stHeader t : stRows t) atts,
                let ids = [start .. start + h - 1]
              ]
            (headerBoxes, rowBoxes) = case [bs | (bs, _, _) <- rowsOut] of
              (hb : rbs) -> (hb, rbs)
              [] -> ([], [])
            {- a grid line of space before and after a table; none
            after a heading, one between two tables (golem-driver ADR 0031) -}
            spaceBefore = case reverse (nuFlow nb) of
              (FHeading {} : _) -> 0
              (FRuled {frBody = RuledHeading {}} : _) -> 0
              (FSpace _ : FTable {} : _) -> 0
              _ -> 1
         in nb
              { nuNext = nextId + sum heights,
                nuFlow = nuFlow nb <> [FTable nextId spaceBefore headerBoxes rowBoxes, FSpace 1],
                nuLines = Map.unions (nuLines nb : [m | (_, m, _) <- rowsOut]),
                nuTableLines = Map.unions (nuTableLines nb : [m | (_, _, m) <- rowsOut]),
                nuTables = Map.insert nextId (TableGeometry (stWidth t) 0 0 (sum heights)) (nuTables nb)
              }
  where
    nextId = nuNext nb
    fs = pgFontSize (feGeom fe)
    capacity = length (pgLineGrid (feGeom fe))
    emptyLine = Line [] 0 0 0 (0, 0) 0 (0, 0)

-- | Headings and table of contents entries by their lines (golem-driver ADR 0009); @fs@ is the font size of the grid.
headingAndTocLines :: Sp -> ComposedUnits -> Int -> Int -> Unit -> Numbered -> Numbered
headingAndTocLines fs cu nextId i u nb = case uKind u of
  UHeading {} -> nb {nuHeadingSpans = Map.insert nextId (uSpan u) (nuHeadingSpans nb)}
  UTocEntry l hs
    | Just c <- Map.lookup i (cuSingles cu),
      ls@(_ : _) <- cLines c ->
        let end = case [off + w | (Box w _, off) <- placeLine (last ls)] of
              [] -> 0
              ends -> last ends
         in nb {nuTocLines = Map.insert (nextId + length ls - 1) (hs, tocIndent fs l + end) (nuTocLines nb)}
  _ -> nb

-- | Numbers the lines of a unit that is not a table: figures, code blocks, the controls of the flow and the units of text.
numberOther :: FlowEnv -> ComposedUnits -> Numbered -> (Int, Unit) -> Numbered
numberOther fe cu nb (i, u)
  | Map.member i (cuBesides cu) = nb -- set beside its figure
  | otherwise = case uKind u of
      UFigure _ -> maybe nb (\placed -> numberFigure fe cu i u placed nb) (Map.lookup i (cuFigures cu))
      UGap n -> nb {nuFlow = nuFlow nb <> [FSpace n]}
      UCode {} -> maybe nb (\cb -> numberCode u cb nb) (Map.lookup i (cuCodeBlocks cu))
      UBreak k -> nb {nuFlow = nuFlow nb <> [FBreak k]}
      UPageControl c ->
        let control = case c of
              NoBreak -> FNoBreak (uSpan u)
              NeedLines k -> FNeedLines (uSpan u) k
              AdjustLines k -> FAdjustLines (uSpan u) k
         in nb {nuFlow = nuFlow nb <> [control]}
      UColumns set -> nb {nuFlow = nuFlow nb <> [maybe FRestoreColumns FSwitchColumns set]}
      UBlank k -> nb {nuFlow = nuFlow nb <> [FBlank (uSpan u) (fromIntegral k)]}
      _ -> numberText fe u (cuSingles cu Map.! i) nb

{- | Numbers a figure; a wrapped figure with the lines beside it, and the
rest of a paragraph cut short continues after it.
-}
numberFigure :: FlowEnv -> ComposedUnits -> Int -> Unit -> (PlacedFigure, [Diagnostic], [Diagnostic], [SrcSpan]) -> Numbered -> Numbered
numberFigure fe cu i u (pf, ferrs, _, fmarks) nb = case pfExclusion pf of
  Just ex
    | null ferrs ->
        let besides = cuBesides cu
            unitAt = cuUnits cu
            fs = pgFontSize (feGeom fe)
            paras = [(j, c, off) | j <- takeWhile (`Map.member` besides) [i + 1 ..], let (c, off) = besides Map.! j]
            indentOf off k = if pfWrap pf == Just WrapStart && off + k < exLines ex then exWidth ex else 0
            -- beside the figure the paragraph indent adds to the exclusion (docs/adr ADR 0006)
            go (nid, boxAcc, setAcc) (j, c, off) =
              let (bs, set) = numberedLines fe nid (unitAt Map.! j) c (\k -> indentOf off k + unitLineIndent fs (uKind (unitAt Map.! j)) k)
               in (nid + length (cLines c), boxAcc <> bs, Map.union setAcc set)
            tooNarrow =
              [ if null (uLists (unitAt Map.! j))
                  then diagnostic "G07028" Error (uSpan (unitAt Map.! j)) "回り込む図版の脇で、字下げを引くと行が残りません"
                  else listTooDeep (uSpan (unitAt Map.! j))
              | (j, c, off) <- paras,
                any (\k -> wrappedLineWidth (feMeasure fe) ex off k - unitLineIndent fs (uKind (unitAt Map.! j)) k - unitEndIndent (uKind (unitAt Map.! j)) <= 0) [0 .. length (cLines c) - 1]
              ]
            (nextId', allBoxes, sets) = foldl go (nextId + 1, [], Map.empty) paras
            (beside, continued) = splitAt (exLines ex) allBoxes
         in nb
              { nuNext = nextId',
                nuFlow = nuFlow nb <> [FWrapped nextId (exLines ex) (unitLabel u) fmarks beside] <> [FContinued continued | not (null continued)],
                nuLines = Map.union (nuLines nb) sets,
                nuFigures = Map.insert nextId pf (nuFigures nb),
                nuErrors = nuErrors nb <> tooNarrow
              }
  -- a turned figure takes a page of its own (golem-driver ADR 0034)
  _ | isJust (pfTurn pf) -> placed (FPageFigure nextId (unitLabel u) fmarks)
  _ -> placed (FFigure nextId (pfImageLines pf + pfCaptionSpan pf) (unitLabel u) fmarks)
  where
    nextId = nuNext nb
    placed f = nb {nuNext = nextId + 1, nuFlow = nuFlow nb <> [f], nuFigures = Map.insert nextId pf (nuFigures nb), nuErrors = nuErrors nb <> ferrs}

-- | Numbers the rows of a code block; the label and the index marks of the caption on the first row (golem-driver ADR 0023).
numberCode :: Unit -> SetCode -> Numbered -> Numbered
numberCode u cb nb =
  let nextId = nuNext nb
      ids = [nextId .. nextId + length (cbRows cb) - 1]
      boxes = [LineBox lid [] (if k == 0 then unitLabel u else []) (if k == 0 then cbMarks cb else []) 0 | (k, lid) <- zip [0 :: Int ..] ids]
      set = Map.fromList [(lid, SetLine l (cbSize cb) (cbIndent cb) [] [] Nothing) | (lid, l) <- zip ids (cbRows cb)]
      info = cbInfo cb
   in nb {nuNext = nextId + length ids, nuFlow = nuFlow nb <> [FCode (ciGeometry info) (ciCaptionSpan info) (cbFirstRows cb) (isJust (ciContinued info)) boxes], nuLines = Map.union (nuLines nb) set}

{- | Numbers the lines of a unit of text: a paragraph, a heading, the title
of the notes, a term, an entry; a heading too large for the type area is
G07024.
-}
numberText :: FlowEnv -> Unit -> Composed -> Numbered -> Numbered
numberText fe u c nb =
  let inp = feInput fe
      geom = feGeom fe
      fs = pgFontSize geom
      pitch = pgLinePitch geom
      capacity = length (pgLineGrid geom)
      nextId = nuNext nb
      ls = cLines c
      (boxes, set) = numberedLines fe nextId u c (unitLineIndent fs (uKind u))
      size = lkSize (uLook u)
      least = case uKind u of
        UHeading l _ _ -> headingLines (bookLanguage inp) (uStyle u) capacity l
        UNotesTitle _ -> headingLines (bookLanguage inp) (uStyle u) capacity 2
        _ -> 1
      hb = headingBlock fs pitch size (length ls) least
      ruledOf = FRuled nextId (ruleSide geom True <$> fst (uRules u)) (ruleSide geom False <$> snd (uRules u)) False (RuleGrid pitch fs) 0
      flowOf = case uKind u of
        UHeading _ _ recto | uRules u /= (Nothing, Nothing) -> [ruledOf (RuledHeading recto (hbSpan hb) boxes)]
        UPara _ | uRules u /= (Nothing, Nothing) -> [ruledOf (RuledLines boxes)]
        UHeading l _ recto -> [FHeading l recto (hbSpan hb) boxes]
        UNotesTitle _ -> [FHeading 2 False (hbSpan hb) boxes]
        UTerm _ -> [FDefTerm boxes]
        _ -> [FParagraph boxes]
      -- a verse line after the first joins the stanza of the lines before it (docs/adr/0180)
      flow' = case (uStanza u, unsnoc (nuFlow nb)) of
        (Just i, Just (earlier, FStanza vs)) | i > 0 -> earlier <> [FStanza (vs <> [boxes])]
        (Just _, _) -> nuFlow nb <> [FStanza [boxes]]
        _ -> nuFlow nb <> flowOf
      (headAcc', errs') = case uKind u of
        -- the title of the notes is in neither the headings nor the running heads (golem-driver ADR 0026)
        k
          | Just name <- headingName k ->
              ( Map.insert nextId hb (nuHeadings nb),
                nuErrors nb <> [diagnostic "G07024" Error (uSpan u) ("見出しが版面に入りません（" <> name <> "）") | hbSpan hb > capacity]
              )
        _ -> (nuHeadings nb, nuErrors nb)
   in nb {nuNext = nextId + length ls, nuFlow = flow', nuLines = Map.union (nuLines nb) set, nuHeadings = headAcc', nuErrors = errs'}

-- | The rules of a ruled unit, for the diagnostics of the layout (golem-driver ADR 0027).
ruledInfoOf :: Unit -> RuledInfo
ruledInfoOf u = case uKind u of
  UHeading l _ _ -> uncurry (RuledInfo "見出しの罫線" ("見出し " <> T.pack (show l)) True (lkSize (uLook u))) (uRules u) (uSpan u)
  _ -> uncurry (RuledInfo "段落の罫線" ("段落スタイル " <> fromMaybe "body" (uParaStyle u)) False (lkSize (uLook u))) (uRules u) (uSpan u)

buildFlow :: PdfInput -> PageGeometry -> LoadedFonts -> Map (Text, Int) P.FigureContent -> Assumed -> IO Built
buildFlow inp geom fonts images assumed = do
  let fe = flowEnv inp geom fonts assumed
      (units, widths) = flowUnits fe
      unitAt = Map.fromList units
      mapper :: (a -> IO b) -> [a] -> IO [b]
      mapper = if piParallel inp then mapConcurrently else mapM
      -- figures: the image, its size, its caption and its exclusion (golem-driver ADR 0005)
      figures = Map.fromList [(i, f) | (i, u@Unit {uKind = UFigure fig}) <- units, Just f <- [placeFigure fe u fig <$> Map.lookup (figureKey fig) images]]
      figureNotices = concat [ns | (_, _, ns, _) <- Map.elems figures]
      -- 1. a job per wrapped figure: the paragraphs right after it, in order, beside the exclusion
      jobs = [(i, ex) | (i, (pf, [], _, _)) <- Map.toList figures, Just ex <- [pfExclusion pf]]
  besides <- Map.fromList . concat <$> mapper (uncurry (composeBeside fe widths unitAt)) jobs
  -- 2. every other unit on its own
  let rest = [(i, u) | (i, u) <- units, Map.notMember i besides, not (isFigure u), not (isTable u), not (isGap u)]
      -- gaps and breaks are not composed
      isGap u = case uKind u of
        UGap _ -> True
        UBreak _ -> True
        UPageControl _ -> True
        UBlank _ -> True
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
      tableUnits = [(i, uStyle u, lkLang (uLook u), aligns, h, rows) | (i, u@Unit {uKind = UTable aligns h rows}) <- units]
  _ <- mapper (\(_, (pf, _, _, _)) -> evaluate (length (show (map lineRatio (pfCaption pf))))) (Map.toList figures)
  singles <- Map.fromList . zip (map fst rest) <$> mapper (\(_, u) -> forceComposed (composeUnit fe widths (unitLineWidth fe (uKind u)) u)) rest
  tables <- Map.fromList <$> mapper (\(i, st, l, aligns, h, rows) -> let r = composeTable fe i st l aligns h rows in evaluate (length (show (fmap fst r))) >> pure (i, r)) tableUnits
  -- 3. number the lines in document order
  let codeBlocks = codeBlocksOf fe units
      composed = ComposedUnits unitAt besides figures singles tables codeBlocks
      codeErrors = concatMap cbErrors (Map.elems codeBlocks)
      -- the block (and so the file) of each unit that has an id, by its first id (golem-driver ADR 0014)
      stepFiles (nb, spans) iu@(_, u) =
        let nb' = numberUnit fe composed nb iu
         in (nb', if nuNext nb' > nuNext nb then Map.insert (nuNext nb) (uSpan u) spans else spans)
      lineFiles = Map.map spanFile lineSpans
      start = Numbered 0 [] Map.empty Map.empty Map.empty (deepListErrors fe widths units <> codeErrors) Map.empty Map.empty Map.empty Map.empty
      (numbered, lineSpans) = foldl stepFiles (start, Map.empty) units
      flow = nuFlow numbered
      -- the code blocks of the flow are those of the units, in order
      codeInfos = Map.fromList [(lbId b, (cbInfo cb) {ciFirst = lbId b0}) | (bs@(b0 : _), cb) <- zip [fcRows f | f@FCode {} <- flow] (Map.elems codeBlocks), b <- bs]
      codeNotices = concatMap cbNotices (Map.elems codeBlocks)
      flow' = ruledLinks (spaceAfterCode (pgLinePitch geom) (pgFontSize geom) (map cbInfo (Map.elems codeBlocks)) flow)
      -- the rules of each ruled block by its first line, from the unit of its block (golem-driver ADR 0027)
      rulesBySpan = Map.fromList [(uSpan u, ruledInfoOf u) | (_, u) <- units, uRules u /= (Nothing, Nothing)]
      ruledInfos = Map.fromList [(frId f, info) | f@FRuled {} <- flow', Just sp <- [Map.lookup (frId f) lineSpans], Just info <- [Map.lookup sp rulesBySpan]]
      -- the span and the name of each heading by its first line, for G07100 (golem-layout ADR 0020)
      namesBySpan = Map.fromList [(uSpan u, (uSpan u, name)) | (_, u) <- units, Just name <- [headingName (uKind u)]]
      headingNames = Map.mapMaybe (`Map.lookup` namesBySpan) lineSpans
  pure (Built flow' (nuLines numbered) (nuFigures numbered) (nuHeadings numbered) (nuErrors numbered) (nuTableLines numbered) (nuTables numbered) (nuHeadingSpans numbered) (nuTocLines numbered) lineFiles codeInfos (codeNotices <> figureNotices) lineSpans ruledInfos headingNames units fe)

{- | The links between ruled blocks (golem-driver ADR 0027): a block whose
rule before follows right after a block with a rule after shares its
area; each block knows the overhang of the first line after it.
-}
ruledLinks :: [Flow] -> [Flow]
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
      FRuled {frBody = RuledLines (l : _)} -> Just l
      FRuled {frBody = RuledHeading _ _ (l : _)} -> Just l
      FParagraph (l : _) -> Just l
      FStanza vs | l : _ <- concat vs -> Just l
      FContinued (l : _) -> Just l
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
      side latin = shapingOf vertical lk (if latin then 'a' else '\x6F22')
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
      emptyBox off w = Box w (BoxContent "" False 0 0 (fromEnum KindText) lk 0 0 [] 0 0 source Nothing noLeaf off)
      {- pieces at offsets from the padding: (offset, text, width, Latin,
      swatch, leaf); line numbers and wrap marks are of no leaf: artifacts
      (docs/adr ADR 0183); every box of a row is at the source of its row
      (docs/adr/0218) -}
      lineOf off pieces =
        let go _ [] = []
            go x ((o, t, w, latin, col, leaf) : rest) =
              [emptyBox off (o - x) | o > x]
                <> [Box w (BoxContent t False 0 0 (tagOf latin) (lookOf col) 0 0 [] 0 0 source Nothing leaf off)]
                <> go (o + w) rest
         in Line (go 0 (sortOn (\(o, _, _, _, _, _) -> o) pieces)) 0 (measure - lead - 2 * pad) 0 (0, 0) 0 (0, 0)
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
      background = codeStyle >>= psBackground >>= swatchOf
      border = do
        sw <- codeStyle >>= psBorder >>= swatchOf
        pure (sw, dimToSp size (fromMaybe (Abs 16384) (codeStyle >>= psBorderWidth)))
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
data Unplaced = Unplaced !Text | UnsupportedSvg !S.SvgProblems | ContentTooLarge

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
      pure $
        if
          | ".pdf" `T.isSuffixOf` T.toLower s -> case P.importPage page bytes of
              Left (P.ContentTooLarge _) -> Left ContentTooLarge
              Left e -> Left (Unplaced (P.importErrorText e))
              Right ip -> Right (P.VectorFigure ip)
          | ".svg" `T.isSuffixOf` T.toLower s -> case S.readSvg bytes of
              Left (S.SvgMalformed why) -> Left (Unplaced why)
              Left (S.SvgUnsupported us) -> Left (UnsupportedSvg us)
              Right svg -> Right (P.SvgFigure (svgDrawing svg))
          | otherwise -> either (Left . Unplaced . T.pack) (Right . P.RasterFigure) (P.readImage bytes)

-- | The @figure blocks of a book, with their spans.
figureBlocks :: Book -> [(SrcSpan, Figure)]
figureBlocks book = [(sp, f) | Document _ bs <- bookDocs book, Block sp _ _ (FigureBlock f) <- bs]

{- | G08010: a figure that cannot be placed in the PDF; G08011: an SVG figure
with things outside the subset, G08016: with markers in a cycle, G08017: with
markers nested too deep, G08101: with markers that draw too many segments,
each that applies in this order; G08015: a PDF figure whose page content
joined is over 256 MiB; one of each per @figure (golem-pdf ADR 0008, 0009,
docs/adr ADR 0051, 0054, 0084).
-}
figureDiagnostics :: PdfInput -> Map (Text, Int) (Either Unplaced P.FigureContent) -> [Diagnostic]
figureDiagnostics inp loaded =
  [ d
  | (sp, f) <- figureBlocks (piBook inp),
    Just (Left why) <- [Map.lookup (figureKey f) loaded],
    d <- case why of
      Unplaced reason -> [diagnostic "G08010" Error sp ("図版を PDF に置けません: " <> figSource f <> "（" <> reason <> "）")]
      UnsupportedSvg ps ->
        [diagnostic "G08011" Error sp (unsupportedMessage (figSource f) us) | Just us <- [nonEmpty (S.spUnsupported ps)]]
          <> [diagnostic "G08016" Error sp (markerMessage "SVG の図版の marker が循環しています: " (figSource f) rs) | Just rs <- [nonEmpty (S.spMarkerCycles ps)]]
          <> [diagnostic "G08017" Error sp (markerMessage "SVG の図版の marker の入れ子が 9 段を超えます: " (figSource f) rs) | Just rs <- [nonEmpty (S.spMarkerDepth ps)]]
          <> [diagnostic "G08101" Error sp (markerSegmentsMessage (figSource f) n) | Just n <- [S.spMarkerSegments ps]]
      ContentTooLarge -> [diagnostic "G08015" Error sp ("図版の PDF のページの内容をつなぐと 256 MiB を超えます: " <> figSource f)]
  ]

{- | The rectangle of a figure's image on page @page@ from grid line @slot@
of the column @ta@ (golem-driver ADR 0005, 0034). A figure turned onto a
page of its own is in the type area @ta@ turned, and its rectangle is
where it lands on the page.
-}
figureRect :: PageGeometry -> Int -> Rect -> Int -> PlacedFigure -> Rect
figureRect geom _ ta slot pf = case pfTurn pf of
  Nothing -> imageRect geom (paperOf geom) ta slot pf
  Just t ->
    let (paper, area) = turnedFrame geom t ta pf
     in P.turnRect t ta (imageRect geom paper area slot pf)

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
imageRect geom paper ta slot pf =
  let d = fromIntegral slot * pgLinePitch geom
      along = pfAlong pf
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
      frame = Rect 0 0 (rectH ta) (rectW ta)
      paper = unturnRect t ta (paperOf geom)
      depth
        | null (pfCaption pf) = pfAcross pf
        | otherwise = fromIntegral (pfImageLines pf) * pgLinePitch geom + fromIntegral (length (pfCaption pf) - 1) * pfCaptionPitch pf + pfCaptionSize pf
      spare = max 0 ((if vertical then rectW frame else rectH frame) - depth)
      -- the end across the lines: the left of the frame in vertical text, its bottom in horizontal text
      endNearer
        | vertical = rectX frame - rectX paper < (rectX paper + rectW paper) - (rectX frame + rectW frame)
        | otherwise = rectY frame - rectY paper < (rectY paper + rectH paper) - (rectY frame + rectH frame)
      shift = if spare > 0 && endNearer then spare else 0
      area
        | vertical = frame {rectW = rectW frame - shift}
        | otherwise = frame {rectH = rectH frame - shift}
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

-- | The output intent; a profile that cannot be read is G08006 (golem-project ADR 0004).
loadIntent :: PdfInput -> IO (Either [Diagnostic] (Maybe P.PdfX))
loadIntent inp = case stIntent (piStyle inp) of
  Nothing -> pure (Right Nothing)
  Just path -> do
    r <- filesResolve (piFiles inp) path
    case r of
      Left e -> pure (Left [diagnostic "G08006" Error (mkSpan (styleFileId (piProject inp)) 0 0) (T.pack (intentMessage e <> ": " <> path))])
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
