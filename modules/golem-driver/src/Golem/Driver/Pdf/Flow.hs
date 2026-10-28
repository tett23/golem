{-# LANGUAGE MultiWayIf #-}

-- | The flow of the PDF: composition, line breaking and pagination (golem-driver ADR 0002).
module Golem.Driver.Pdf.Flow
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
    flowLines,
    layoutPdf,
    gridLine,
    runningMetadata,
    runningHeadLines,
    numberedTitle,
    pagesOf,
    pageMasters,
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
    listNumberDiagnostics,
    Assumed (..),
    fixpoint,
    rubyStyleOf,
    listBullets,
    textBullets,
    RuledInfo (..),
    fitFigure,
    figureRect,
    imageRect,
    turnedFrame,
    styleFileId,
    pdfXPeople,
    loadIntent,
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
import Data.Either (fromRight, isLeft)
import Data.Foldable (toList)
import Data.Int (Int64)
import Data.List (groupBy, intercalate, mapAccumL, nub, sortOn, zip4)
import Data.List.NonEmpty (NonEmpty, nonEmpty)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble
import Golem.Doc.Bibliography (EntryPart (..))
import Golem.Doc.IR
import Golem.Doc.ListMarkers
import Golem.Doc.Numbering (numberSeparator)
import Golem.Doc.Numerals (circled)
import Golem.Driver.Overhang (lineOverhang, reachesBackground)
import Golem.Driver.Pdf.Fonts
import Golem.Driver.Svg (markerMessage, markerSegmentsMessage, svgDrawing, unsupportedMessage)
import Golem.Html (codeTokens)
import Golem.Layout.Aki (AkiSet, resolveAkiSet)
import Golem.Layout.Code
import Golem.Layout.Hyphenation.EnUs (englishUS)
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
import Golem.Pdf qualified as P
import Golem.Project
import Golem.Project.Paths (PathError (..), pathErrorMessage, resolveInRoot)
import Golem.Project.Style
import Golem.Svg qualified as S
import Golem.Syntax
import Golem.Syntax.Length qualified as L
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
    slSidenotes :: ![(SrcSpan, [Line])]
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
    -- | along the lines before the figure was fitted: the measure (golem-driver ADR 0034)
    pfFullAlong :: !Sp,
    -- | how a figure turned onto a page of its own is turned
    pfTurn :: !(Maybe P.Turn)
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
    plRules :: !(Map Int RuledInfo)
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
    bHeadingNames :: Map Int (SrcSpan, Text)
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
      let (lk, Indent s f) = paraLook st geom (Just name),
      let size = lkSize lk,
      columnMeasure geom - s - max 0 f < 8 * size
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
    lf <- loadFonts provider (piRoot inp) (piStyleFile inp) (piStyle inp) (Map.elems (piLocalStyles inp))
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
   in case sidenoteDiagnostics geom (piBook inp) <> listNumberDiagnostics (piStyle inp) (pgVertical geom) (piBook inp) of
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
    Right (built, pages) ->
      -- sidenotes are placed once, on the settled pages (golem-driver ADR 0006)
      -- in the size of the document of each sidenote (docs/adr ADR 0014)
      let metricsOf sp = let (_, size, pitch) = sidenoteMetrics (docStyle inp (spanFile sp)) geom in (pitch, size)
          placed = [(poNumber p, placePageSidenotes geom metricsOf (bLines built) p) | p <- pages]
          -- the pages of the table of contents, once, on the settled pages (golem-driver ADR 0009)
          hPages = headingPages (bHeadingSpans built) pages
          tg = tocGeometry (piStyle inp) geom fonts
          env = composeEnv (piStyle inp) geom fonts (Assumed Map.empty Map.empty) (bodyLook (piStyle inp) (pgFontSize geom))
          -- the leader and the page number are at the heading of the entry (golem-cli ADR 0008)
          atHeading hs tp = tp {tpLeader = withBoxSource (SourceGrid, hs) (tpLeader tp), tpNumber = withBoxSource (SourceGrid, hs) (tpNumber tp)}
          tocPages = Map.fromList [(lid, atHeading hs (tocPage tg e (pageNumberLine env n))) | (lid, (hs, e)) <- Map.toList (bTocLines built), Just n <- [Map.lookup hs hPages]]
       in case concat [ds | (_, Left ds) <- placed] of
            [] -> Right (PdfLayout pages (bLines built) (bFigures built) (bHeadings built) (Map.fromList [(n, ps) | (n, Right ps@(_ : _)) <- placed]) (bTableLines built) (bTables built) tocPages (bLineFiles built) (bHeadingSpans built) (bCodes built) (bNotices built <> ruledNotices (bFlow built) (bRules built) pages <> unmetWarnings (bHeadingNames built) pages) (bLineSpans built) (bRules built))
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

{- | The text of the keys of [metadata] a running head can show
(golem-driver ADR 0022): the keys of @meta@ but creators, an array.
-}
runningMetadata :: Metadata -> Map Text Text
runningMetadata md =
  Map.fromList $
    [ ("id", mdId md),
      ("title", mdTitle md),
      ("language", mdLanguage md),
      ("date", T.pack (show (mdDate md)))
    ]
      <> [("title_reading", r) | Just r <- [mdTitleReading md]]
      <> [("edition", e) | Just e <- [mdEdition md]]
      <> [("publisher", p) | Just p <- [mdPublisher md]]

{- | The lines of a running head drawn on a page (golem-driver ADR 0014,
0022), from the text of the metadata, the variables of the page's file,
the content, the headings in effect at the start of the page by level,
and the headings that start on the page. A line with a slot without @?@
and without a value is left out; a slot with @?@ and without a value is
empty; a line is trimmed of spaces (U+0020, U+3000) and left out when
nothing is left.
-}
runningHeadLines :: Map Text Text -> Map [Text] Text -> RunningContent -> Map Int (Maybe HeadingInfo) -> [HeadingInfo] -> [Text]
runningHeadLines meta vars content start started = case content of
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
      recto h = maybe False hsRectoBreak (Map.lookup (hiLevel h) (stHeadings (piStyle inp)))
      one p st m fid
        | poBlank p || any recto (startedOn p) = []
        | otherwise = case m >>= mgRunningHead of
            Nothing -> []
            Just (co, ce, _, _) ->
              runningHeadLines meta (Map.findWithDefault Map.empty fid (piRunningVars inp)) (if odd (poNumber p) then co else ce) st (startedOn p)
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
plainWidth fonts role size txt = sum [L.zwToSp size (shAdvance g) | g <- lfShape fonts (Shaping role False []) txt]

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
      leader = Line [Box u (BoxContent "…" False 0 0 (fromEnum KindText) (tgLook tg) 0 0 [] 0 0 noBoxSource) | _ <- [1 .. k]] 0 (fromInteger k * u) 0 (0, 0) False (0, 0)
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
   in Line boxes 0 w 0 (0, 0) False (0, 0)

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
    lf <- loadFonts provider (piRoot inp) (piStyleFile inp) (piStyle inp) (Map.elems (piLocalStyles inp))
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
it has none; a URL is in the character style url (golem-doc ADR 0005).
-}
bibliographyLines :: Map Text [EntryPart] -> [(Text, Int)] -> [[Inline]]
bibliographyLines bib cites =
  [ merged (EntryText ("[" <> T.pack (show n) <> "] ") : fromMaybe [EntryText k] (Map.lookup k bib))
  | (k, n) <- cites
  ]
  where
    sp0 = mkSpan (FileId 0) 0 0
    merged = \case
      EntryText a : EntryText b : rest -> merged (EntryText (a <> b) : rest)
      EntryText a : rest -> Text sp0 a : merged rest
      EntryUrl u : rest -> CharStyle sp0 "url" [Text sp0 u] : merged rest
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
    siteBlock b@(Block _ _ body) = case body of
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
    site (Block sp l body) =
      [(name, sp) | Just name <- [l]] <> case body of
        BulletList items -> concatMap (concatMap site . itemBlocks) items
        OrderedList items -> concatMap (concatMap site . itemBlocks) items
        DefList gs -> concatMap (concatMap (concatMap site) . dgDefs) gs
        FigureBlock fig -> concatMap site (figCaption fig)
        _ -> []

{- | Numbers of list items that the number format of their depth cannot
write (golem-driver ADR 0013): G07029 at the item, whatever the target.
-}
listNumberDiagnostics :: Style -> Bool -> Book -> [Diagnostic]
listNumberDiagnostics style vertical book =
  [ diagnostic "G07029" Error (lsiSpan s) ("リストの番号 " <> T.pack (show (lsiNumber s)) <> " は、書式 " <> renderNumberFormat f <> " で表せません")
  | s <- listSites (concat [bs | Document _ bs <- bookDocs book]),
    let f = atDepth formats (lsiDepth s),
    null (formatListNumber (nfStyle f) (lsiNumber s))
  ]
  where
    formats = fromMaybe (pure (defaultNumberFormat vertical)) (lsNumbers (stLists style))

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
          ceWordAdvance = \lk t -> lfWordAdvance fonts (maybe (Shaping (lkLatinFace lk) False []) (shaping lk . fst) (T.uncons t)) t,
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
          cePageOf = (`Map.lookup` asLabels assumed),
          ceSidenoteMarker = case snMarker <$> stSidenotes style of
            Just "symbol" -> MarkerSymbol
            Just "none" -> MarkerNone
            _ -> MarkerNumber,
          -- Latin words: US English patterns (golem-layout ADR 0001)
          cePatterns = Just englishUS,
          -- the set of body; a paragraph, a caption and a sidenote take their style's (docs/adr ADR 0019)
          ceAkiSet = akiSetOf style Nothing,
          -- the size and text of note marks (golem-driver ADR 0025)
          ceNoteMarkSize = stNotesMarkSize style,
          ceNoteMarkFormat = stNotesMarkFormat style
        }

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
withNoteMark :: SrcSpan -> Text -> Int -> [Inline] -> [Inline]
withNoteMark sp format n body = Text sp (noteMarkText format n) : Aki sp (AkiZw (1 / 4)) : body

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
    -- | the definition that decided the size of 'uLook' (golem-cli ADR 0008)
    uSource :: SizeSource
  }

{- | How the messages of G07024 and G07100 name a heading, or the title of
the notes (golem-driver ADR 0003, 0026; golem-layout ADR 0020).
-}
headingName :: UnitKind -> Maybe Text
headingName = \case
  UHeading l short _ -> Just (T.pack (show l) <> " の見出し: " <> short)
  UNotesTitle title -> Just ("注の一覧の見出し: " <> title)
  _ -> Nothing

-- | The indent of the lines of a paragraph in sp (docs/adr ADR 0006). inFirst may be negative; inStart + inFirst >= 0.
data Indent = Indent {inStart :: !Sp, inFirst :: !Sp}
  deriving stock (Eq, Show)

noIndent :: Indent
noIndent = Indent 0 0

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
   in (withFeatures d (plainLook role size), Indent (sp' psIndent) (sp' psFirstLineIndent))

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

{- | The bullets of [lists] by depth in PDF, HTML and EPUB: those written,
or • without bullets (golem-driver ADR 0044).
-}
listBullets :: ListStyle -> NonEmpty Text
listBullets = bulletsOr "•"

-- | The bullets of [lists] by depth in plain text: those written, or ・ without bullets (golem-driver ADR 0044).
textBullets :: ListStyle -> NonEmpty Text
textBullets = bulletsOr "・"

bulletsOr :: Text -> ListStyle -> NonEmpty Text
bulletsOr def = fromMaybe (pure def) . lsBullets

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
        written = fromMaybe (T.pack (show n)) (formatListNumber st n)
        number = case st of
          NsBook -> Number sp0 n Nothing
          NsArabic | vertical, n >= 0, T.length written <= 2 -> Tcy sp0 written
          _ -> Text sp0 written
     in [Text sp0 pre | not (T.null pre)] <> [number] <> [Text sp0 suf | not (T.null suf)]
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
    doc n (Document fid bs) = blocks (styleOf fid) [] n bs
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
         in Unit (UNotesTitle title) Nothing [Text sp title] sp (uncurry (styleLook style Nothing) (headingFace lang style geom 2)) style [] Nothing Nothing (Nothing, Nothing) (SourceHeading 2)
              : [Unit (UPara noIndent) Nothing (withNoteMark nsp (stNotesMarkFormat style) n xs) nsp (bodyLook style fs) style [] Nothing Nothing (Nothing, Nothing) SourceGrid | (nsp, n, xs) <- ns]
    {- a list of blocks inside the lists @ctx@, from the list number @n@:
    paragraphs of the same style in a row are apart by its space-between
    (docs/adr ADR 0005); in a list item, paragraphs are not indented by
    their style (docs/adr ADR 0006) but by the lists (golem-driver ADR 0013) -}
    blocks style ctx n bs =
      let (n', uss) = mapAccumL (\k (prev, b) -> (gapBefore style ctx prev b <>) <$> block style ctx k b) n (zip (scanl before Nothing bs) bs)
       in (n', concat uss)
    gapBefore style ctx (Just (Block _ _ (Paragraph s1 _))) (Block sp _ (Paragraph s2 _))
      | s1 == s2, Just g <- paraStyle style s2 >>= psSpaceBetween, g > 0 = [Unit (UGap g) Nothing [] sp (bodyLook style fs) style ctx Nothing Nothing (Nothing, Nothing) SourceGrid]
    gapBefore _ _ _ _ = []
    -- the block before, past the controls of page breaks (docs/adr ADR 0030)
    before prev b = case blockBody b of
      PageControl _ -> prev
      _ -> Just b
    block style ctx n (Block sp lbl body) =
      let unit kind l is face = Unit kind l is sp face style ctx Nothing Nothing (Nothing, Nothing)
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
               in (n, [(unit (UPara (if null ctx then ind else noIndent)) (if i == 0 then lbl else Nothing) part face (paraSizeSource style st)) {uParaStyle = st, uRules = rulesOf i} | (i, part) <- zip [0 :: Int ..] parts])
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
              let group k g = ([plainUnit (UTerm noIndent) Nothing t | t <- dgTerms g] <>) <$> blocksOf k (dgDefs g)
                  blocksOf k ds = let (k', dss) = mapAccumL (blocks style ctx) k ds in (k', concat dss)
                  (n', uss) = mapAccumL group n gs
               in (n', concat uss)
            Table aligns h rows -> (n, [plainUnit (UTable aligns h rows) lbl []])
            -- always in the paragraph style code (golem-driver ADR 0017)
            CodeBlock code -> (n, [unit (UCode 0 code) lbl [] (codeLook style geom) (paraSizeSource style (Just "code"))])
            FigureBlock fig -> (n, [plainUnit (UFigure fig) lbl []])
            -- the index marks of a title are counted at the heading, not in the table of contents
            ChannelOutput (TocOutput depth) -> (n, [plainUnit (UTocEntry (teLevel e) (teSpan e)) Nothing (numberedTitle lang (teSpan e) (teNumber e) (filter (not . isMark) (teTitle e))) | e <- bookToc book, teLevel e <= depth])
            ChannelOutput IndexOutput ->
              let entries kind = [plainUnit kind Nothing is | is <- indexLines (pgVertical geom) pageOf (indexAt book sp)]
               in case indexSet of
                    Nothing -> (n, entries (UPara noIndent))
                    -- the index in its own columns (docs/adr ADR 0025)
                    Just set -> (n, [plainUnit (UColumns (Just set)) Nothing []] <> entries (UIndexEntry (csMeasure set)) <> [plainUnit (UColumns Nothing) Nothing []])
            -- each entry of a channel of a plugin a paragraph of its style (golem-doc ADR 0007)
            ChannelOutput (CustomOutput name st) ->
              let (face, ind) = paraLook style geom st
                  locators = maybe False channelLocators (Map.lookup name (bookChannelDecls book))
               in (n, [(unit (UPara (if null ctx then ind else noIndent)) Nothing is face (paraSizeSource style st)) {uParaStyle = st} | is <- channelLines (pgVertical geom) pageOf locators (channelAt book sp)])
            ChannelOutput BibliographyOutput -> (n, [plainUnit (UPara noIndent) Nothing is | is <- bibliographyLines bib (bibliographyAt book sp)])
            ForcedBreak k -> (n, [plainUnit (UBreak k) Nothing []])
            PageControl c -> (n, [plainUnit (UPageControl c) Nothing []])
            BlankLines k -> (n, [plainUnit (UBlank k) Nothing []])
    {- the items of the list numbered n: their units are inside it, the first
    unit of an item that starts with a paragraph carries the marker -}
    list style ctx n items =
      let ctx' = ctx <> [n]
          marker = listMarker style (pgVertical geom) (length ctx')
          item k (num, it) =
            let (k', us) = blocks style ctx' k (itemBlocks it)
             in (k', if startsWithParagraph it then markFirst (marker num) us else us)
          (n', uss) = mapAccumL item (n + 1) items
       in (n', concat uss)
    startsWithParagraph it = case itemBlocks it of
      (Block _ _ (Paragraph {}) : _) -> True
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
    isMark = \case
      IndexMark {} -> True
      _ -> False

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

buildFlow :: PdfInput -> PageGeometry -> LoadedFonts -> Map (Text, Int) P.FigureContent -> Assumed -> IO Built
buildFlow inp geom fonts images assumed = do
  let style = piStyle inp
      fs = pgFontSize geom
      pitch = pgLinePitch geom
      capacity = length (pgLineGrid geom)
      vertical = pgVertical geom
      -- notes at the end of the chapter, not at the foot of the page (golem-driver ADR 0026)
      atEnd = stNotesPlacement style == PlaceChapterEnd
      -- citations show their numbers (golem-driver ADR 0007)
      envFor lk = (composeEnv style geom fonts assumed lk) {ceCiteNumber = citeNumber (piBook inp)}
      bodyEnv = envFor (bodyLook style fs)
      params = kpParams style geom
      measure = columnMeasure geom
      -- the reserve for the page number of a table of contents entry: W and two em (golem-driver ADR 0009)
      tocReserve = fst (tocMetrics bodyEnv) + 2 * fs
      tocIndent l = fromIntegral (l - 1) * fs
      -- a mark without an assumed page yet stands at page 1 in the first round
      markPage sp = Map.lookup sp (asMarks assumed) <|> (if Map.null (asMarks assumed) then Just 1 else Nothing)
      rawUnits = unitsOf (bookLanguage inp) (piBook inp) geom (indexColumnSet style geom) (docStyle inp) markPage (piBibliography inp)
      -- the character styles of the unit's document (docs/adr ADR 0014)
      styledEnv st e = e {ceRestyle = restyle st, ceSizeSourceOf = restyleSource st}
      -- the marker width M of each list, and the indents of the units in lists (golem-driver ADR 0013)
      widths = listWidths (\u -> (styledEnv (uStyle u) (envFor (uLook u))) {ceAkiSet = akiSetOf (uStyle u) (uParaStyle u)}) fs (lsGap (stLists style)) rawUnits
      widthOfList lid = Map.findWithDefault 0 lid widths
      -- O: the widths of the lists around a unit; Mi: the width of the innermost one
      outerOf u = sum (map widthOfList (uLists u))
      innerOf u = case reverse (uLists u) of
        (lid : _) -> widthOfList lid
        [] -> 0
      withListIndent u
        | null (uLists u) = u
        | otherwise = case uKind u of
            UPara _ -> u {uKind = UPara (Indent (outerOf u) (if isJust (uMarker u) then negate (innerOf u) else 0))}
            UTerm _ -> u {uKind = UTerm (Indent (outerOf u) 0)}
            UCode _ code -> u {uKind = UCode (outerOf u) code}
            _ -> u
      units = zip [0 :: Int ..] (map withListIndent rawUnits)
      unitAt = Map.fromList units
      -- L*(i): the first line is shortened by the indent and the first-line indent, the others by the indent (docs/adr ADR 0006);
      -- a table of contents entry also by the reserve for its page number (golem-driver ADR 0009)
      widthOf kind k = case kind of
        UIndexEntry m -> m
        _ -> measure - lineIndent kind k - (case kind of UTocEntry {} -> tocReserve; _ -> 0)
      lineIndent = \case
        UPara (Indent s f) -> \k -> if k == (0 :: Int) then s + f else s
        UTerm (Indent s _) -> const s
        UTocEntry l _ -> const (tocIndent l)
        _ -> const 0
      -- the role and size a unit is set in (docs/adr ADR 0005)
      faceOf u = (lkFace (uLook u), lkSize (uLook u))
      {- the marker of a list item: its boxes and an empty box up to Mi, before
      the text with no glue or penalty between them (golem-driver ADR 0013) -}
      markerItems env u = case uMarker u of
        Nothing -> []
        Just m ->
          let boxes = [b | b@Box {} <- fst (composeInlines env m)]
              w = sum (map itemWidth boxes)
           in boxes <> [Box (innerOf u - w) (BoxContent "" False 0 0 (fromEnum KindText) (ceLook env) 0 0 [] 0 0 (uSource u, uSpan u))]
      compose lineWidth u =
        let env = (styledEnv (uStyle u) (envFor (uLook u))) {ceAkiSet = akiSetOf (uStyle u) (uParaStyle u), ceSizeSource = uSource u}
            bodyEnv' = (styledEnv (uStyle u) (envFor (bodyLook (uStyle u) fs))) {ceAkiSet = akiSetOf (uStyle u) Nothing}
            marker = markerItems env u
            -- the anchors count the items of the text; the marker comes first
            shift = length marker
            (textItems, anchors) = composeInlines env (uInlines u)
            items = marker <> textItems
            lines' = brLines (breakParagraph params lineWidth items)
            -- notes at the end of the chapter are paragraphs of their own (golem-driver ADR 0026)
            notes = [(k, brLines (breakParagraph params (const measure) (fst (composeInlines bodyEnv' (withNoteMark (noteIdSpan k) (stNotesMarkFormat (uStyle u)) n nbody))))) | not atEnd, (_, k, n, nbody) <- noteAnchors anchors]
            sidenotes = [(i + shift, sp, sidenoteLines (uStyle u) sp n snBody) | AnchorSidenote i n sp snBody <- anchors]
            marks =
              [(i + shift, sp) | AnchorIndex i sp _ <- anchors]
                <> [(i + shift, sp) | not atEnd, AnchorNote i _ _ nbody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines bodyEnv' nbody)]
                <> [(i + shift, sp) | AnchorSidenote i _ _ snBody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines bodyEnv' snBody)]
         in Composed lines' notes sidenotes marks anchors items shift
      -- sidenote bodies: their size, the column width, the marker first (golem-driver ADR 0006)
      -- in the role and size of the paragraph style sidenote of the document (docs/adr ADR 0014)
      snMeasure = maybe 0 (rectW . fst) (pgSidenotes geom)
      sidenoteLines st sp n snBody =
        let (snRole, snSize', _) = sidenoteMetrics st geom
            snEnv = (styledEnv st (envFor (styleLook st (Just "sidenote") snRole snSize'))) {ceAkiSet = akiSetOf st (Just "sidenote"), ceSizeSource = paraSizeSource st (Just "sidenote")}
            snParams = params {pEmergencyStretch = dimToSp snSize' (compEmergencyStretch (stComposition style))}
            -- the number is at the sidenote (golem-cli ADR 0008)
            prefix = case ceSidenoteMarker bodyEnv of
              MarkerNumber -> [Text sp (T.pack (show n) <> " ")]
              MarkerSymbol -> [Text sp "※ "]
              MarkerNone -> []
         in brLines (breakParagraph snParams (const snMeasure) (fst (composeInlines snEnv (prefix <> snBody))))
      force c = evaluate (length (show (map lineRatio (cLines c))) + length (cNotes c) + length (show [map lineRatio ls | (_, _, ls) <- cSidenotes c]) + length (cAnchors c) + length (cItems c)) >> pure c
      mapper :: (a -> IO b) -> [a] -> IO [b]
      mapper = if piParallel inp then mapConcurrently else mapM
      -- figures: the image, its size, its caption and its exclusion (golem-driver ADR 0005)
      figureOf u fig = placeFigure u fig <$> Map.lookup (figureKey fig) images
      placeFigure u fig content =
        let -- a figure turned onto a page of its own is set in its frame (golem-driver ADR 0034)
            turned = figRotate fig && isNothing (figWrap fig)
            along = case figWrap fig of
              Nothing -> Right (if turned then frameAlong else measure)
              Just _ -> maybe (Left ()) (Right . dimToSp fs) (figWidth fig >>= parseDim)
            alongSp = fromRight measure along
            -- the pixels of an image, the crop box of a PDF figure after its rotation (golem-pdf ADR 0008)
            (w, h) = figureProportions content
            -- across the lines for each sp along them
            ratio = if vertical then w / h else h / w
            number = Map.lookup (uSpan u) (bookFigures (piBook inp))
            captionInlines = numberedTitle (bookLanguage inp) (uSpan u) number (concat [is | Block _ _ (Paragraph _ is) <- figCaption fig])
            -- the caption in the role and size of the paragraph style caption (golem-driver ADR 0010)
            (captionRole, cs) = paraFace (uStyle u) geom "caption"
            captionParams = params {pEmergencyStretch = dimToSp cs (compEmergencyStretch (stComposition style))}
            (captionItems, captionAnchors) = composeInlines ((styledEnv (uStyle u) (envFor (styleLook (uStyle u) (Just "caption") captionRole cs))) {ceAkiSet = akiSetOf (uStyle u) (Just "caption"), ceSizeSource = paraSizeSource (uStyle u) (Just "caption")}) captionInlines
            captionAt len = if null captionInlines then [] else brLines (breakParagraph captionParams (const len) captionItems)
            -- the grid lines a caption of k lines takes: the fewest that hold it, its pitch in the body's ratio of pitch to size
            captionSpanOf k = if k == 0 then (pitch, 0) else let cb' = headingBlock fs pitch cs k 1 in (hbPitch cb', hbSpan cb')
            -- the caption in the measure before fitting (golem-driver ADR 0034)
            caption = captionAt alongSp
            captionMarks = [sp | AnchorIndex _ sp _ <- captionAnchors]
            n = length caption
            (cp, span') = captionSpanOf n
            -- the grid lines of the column, or of the frame
            gridLines = if turned then frameLines else capacity
            fitOf len k s = fitFigure ratio len k pitch fs (if s == 0 then Nothing else Just s)
            (alongFit, across, fitted) = case figWrap fig of
              Nothing -> fitOf alongSp gridLines span'
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
                | isLeft along || measure - exWidth e < 8 * fs ->
                    [diagnostic "G07022" Error (uSpan u) ("回り込む図版の幅が不正です。寸法で書き、行の残りを本文の 8 字分以上にしてください: " <> fromMaybe "" (figWidth fig))]
                | exLines e > capacity -> [diagnostic "G07023" Error (uSpan u) ("回り込む図版の除外領域が一ページの行数を超えます（" <> T.pack (show (exLines e)) <> " 行）")]
              -- a caption that leaves no line for the image (golem-driver ADR 0034)
              _
                | tooDeep -> [diagnostic "G07038" Error (uSpan u) ("図版のキャプションが" <> place' <> "の行数に達します（" <> T.pack (show span') <> " 行。" <> place' <> "は " <> T.pack (show gridLines) <> " 行）")]
                | otherwise -> []
            turn
              | not turned = Nothing
              | vertical = Just P.TurnedRight
              | otherwise = Just P.TurnedLeft
         in (PlacedFigure content alongFit across (figWrap fig) m caption cs cp span' ex (figSource fig) (snd (figureKey fig)) (uSpan u) alongSp turn, errs, notices, captionMarks)
      figures = Map.fromList [(i, f) | (i, u@Unit {uKind = UFigure fig}) <- units, Just f <- [figureOf u fig]]
      figureNotices = concat [ns | (_, _, ns, _) <- Map.elems figures]
      {- the frame of a figure turned onto a page of its own (golem-driver
      ADR 0034): the type area turned, the lines along its height in
      horizontal text and its width in vertical text -}
      typeArea = pgTypeArea geom
      (frameAlong, frameAcross) = if vertical then (rectW typeArea, rectH typeArea) else (rectH typeArea, rectW typeArea)
      frameLines = fromInteger (unSp (max 0 (frameAcross - fs)) `div` unSp pitch) + 1
      -- 1. a job per wrapped figure: the paragraphs right after it, in order, beside the exclusion
      wrapJob i ex = go (i + 1) 0
        where
          go j offset
            | offset >= exLines ex = pure []
            -- a paragraph with rules is not set beside a figure (golem-driver ADR 0027)
            | Just u@Unit {uKind = UPara _, uRules = (Nothing, Nothing)} <- Map.lookup j unitAt = do
                c <- force (compose (\k -> wrappedLineWidth measure ex offset k - lineIndent (uKind u) k) u)
                ((j, (c, offset)) :) <$> go (j + 1) (offset + length (cLines c))
            | otherwise = pure []
      jobs = [(i, ex) | (i, (pf, [], _, _)) <- Map.toList figures, Just ex <- [pfExclusion pf]]
  besides <- Map.fromList . concat <$> mapper (uncurry wrapJob) jobs
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
      -- the notes, sidenotes and index marks of composed inlines, by the line that holds them
      attached st items anchors ls =
        let lineOf = lineIndexOfItems items ls
            env = styledEnv st bodyEnv
            noteBody k n b = brLines (breakParagraph params (const measure) (fst (composeInlines env (withNoteMark (noteIdSpan k) (stNotesMarkFormat style) n b))))
            marksIn b = [sp | AnchorIndex _ sp _ <- snd (composeInlines env b)]
         in ( Map.fromListWith (flip (<>)) [(lineOf i, [(k, noteBody k n b)]) | not atEnd, (i, k, n, b) <- noteAnchors anchors],
              Map.fromListWith (flip (<>)) [(lineOf i, [(sp, sidenoteLines st sp n b)]) | AnchorSidenote i n sp b <- anchors],
              Map.fromListWith (flip (<>)) ([(lineOf i, [sp]) | AnchorIndex i sp _ <- anchors] <> [(lineOf i, sps) | not atEnd, AnchorNote i _ _ b <- anchors, let { sps = marksIn b }, not (null sps)] <> [(lineOf i, sps) | AnchorSidenote i _ _ b <- anchors, let sps = marksIn b, not (null sps)])
            )
      -- a table: every cell at the body size, no hanging punctuation (golem-driver ADR 0008)
      composeTable st aligns h rows =
        let env = (styledEnv st bodyEnv) {ceHanging = False}
            -- no break between the last two Japanese characters of a cell (golem-driver ADR 0037)
            cellOf = first keepLastTwo . composeInlines env
            hCells = map cellOf h
            rCells = map (map cellOf) rows
            rowAttached cells setCells height =
              let perCell = [attached st items anchors (scLines sc) | ((items, anchors), sc) <- zip cells setCells]
               in [(concat [Map.findWithDefault [] k ns | (ns, _, _) <- perCell], concat [Map.findWithDefault [] k sn | (_, sn, _) <- perCell], concat [Map.findWithDefault [] k ms | (_, _, ms) <- perCell]) | k <- [0 .. height - 1]]
            {- a header row of empty cells: a table without a header row
            (golem-driver ADR 0031) -}
            blank = \case
              Box _ c -> T.all isSpace (bcText c)
              _ -> True
            header = if all (all blank . fst) hCells then [] else hCells
         in case layoutTable params measure fs aligns (map fst header) (map (map fst) rCells) of
              Left e -> Left e
              Right t -> Right (t, rowAttached header (stHeader t) (stHeaderLines t) : zipWith3 rowAttached rCells (stRows t) (stRowLines t))
      tableUnits = [(i, uStyle u, aligns, h, rows) | (i, u@Unit {uKind = UTable aligns h rows}) <- units]
  _ <- mapper (\(_, (pf, _, _, _)) -> evaluate (length (show (map lineRatio (pfCaption pf))))) (Map.toList figures)
  singles <- Map.fromList . zip (map fst rest) <$> mapper (\(_, u) -> force (compose (widthOf (uKind u)) u)) rest
  tables <- Map.fromList <$> mapper (\(i, st, aligns, h, rows) -> let r = composeTable st aligns h rows in evaluate (length (show (fmap fst r))) >> pure (i, r)) tableUnits
  -- 3. number the lines in document order
  let label u = maybe [] pure (uLabel u)
      -- the lines of a paragraph-like unit from an id; indent of line k
      numbered nextId u c indentOf =
        let ls = cLines c
            ids = [nextId .. nextId + length ls - 1]
            (_, size) = faceOf u
            -- notes belong to the line containing their anchor
            lineOfItem = lineIndexOfItems (cItems c) ls
            noteLines = Map.fromListWith (flip (<>)) [(lineOfItem (i + cShift c), [(k, nls)]) | ((i, _, _, _), (k, nls)) <- zip (noteAnchors (cAnchors c)) (cNotes c)]
            sidenoteLinesOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [(sp, sls)]) | (i, sp, sls) <- cSidenotes c]
            marksOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [sp]) | (i, sp) <- cMarks c]
            boxes = [LineBox lid [NoteBody key (length nls) | (key, nls) <- Map.findWithDefault [] k noteLines] (if k == 0 then label u else []) (Map.findWithDefault [] k marksOf) (overhangOf l) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
            set = Map.fromList [(lid, SetLine l size (indentOf k) (Map.findWithDefault [] k noteLines) (Map.findWithDefault [] k sidenoteLinesOf)) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
         in (boxes, set)
      emptyLine = Line [] 0 0 0 (0, 0) False (0, 0)
      {- a rule of a paragraph or heading for pagination (golem-driver ADR
      0027): the spaces at the size of the grid, the inner space next to the
      paragraph, and the room out of the column when it may go out -}
      ruleSide before spec =
        let sp = maybe 0 (dimToSp fs)
            (inner, outer)
              | before = (sp (rsSpaceAfter spec), sp (rsSpaceBefore spec))
              | otherwise = (sp (rsSpaceBefore spec), sp (rsSpaceAfter spec))
         in RuleSide inner outer (rsWeight spec) (isJust (rsSpaceBefore spec) || isJust (rsSpaceAfter spec)) (if rsKeepInColumn spec then Nothing else Just (marginAcross geom before))
      -- how far the ruby and kenten of a line reach toward the line before (golem-driver ADR 0033)
      overhangOf = lineOverhang vertical fs (emBoxCentralOf fonts)
      {- a grid line of space after a code block with a background, a band or
      a border whose next line reaches it with ruby or kenten (golem-driver
      ADR 0033); the code blocks of the flow are those of the units, in order -}
      spaceAfterCode infos = \case
        f@FCode {} : remaining -> case infos of
          ci : more -> f : [FSpace 1 | painted ci, reaches ci remaining] <> spaceAfterCode more remaining
          [] -> f : spaceAfterCode [] remaining
        f : remaining -> f : spaceAfterCode infos remaining
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
            FHeading {fhLines = l : _} -> Just l
            FDefTerm (l : _) -> Just l
            FTable {ftSpaceBefore = 0, ftHeader = l : _} -> Just l
            _ -> Nothing
      step (nextId, flows, lineAcc, figAcc, headAcc, errs, tabAcc, ext) (i, u) = case uKind u of
        UTable {} -> case Map.lookup i tables of
          Just (Left (ColumnsTooWide mn avail)) ->
            (nextId, flows, lineAcc, figAcc, headAcc, errs <> [diagnostic "G07041" Error (uSpan u) ("表の列の最小の幅の合計（" <> L.mmText mn <> "）が使える幅（" <> L.mmText avail <> "）に収まりません")], tabAcc, ext)
          Just (Right (t, atts))
            | tall@(_ : _) <- [r | (r, h) <- zip [1 :: Int ..] (stRowLines t), stHeaderLines t + h > capacity] ->
                (nextId, flows, lineAcc, figAcc, headAcc, errs <> [diagnostic "G07042" Error (uSpan u) ("表の " <> T.pack (show r) <> " 行目が見出しの行とともに一ページに収まりません") | r <- tall], tabAcc, ext)
            | otherwise ->
                let heights = stHeaderLines t : stRowLines t
                    starts = scanl (+) nextId heights
                    rowsOut =
                      [ ( [ LineBox lid [NoteBody key (length nls) | (key, nls) <- ns] (if lid == nextId then label u else []) ms (maximum (0 : [overhangOf l | c <- cells, (j, l) <- zip [0 :: Int ..] (scLines c), j == k]))
                          | (k, (lid, (ns, _, ms))) <- zip [0 ..] (zip ids att)
                          ],
                          Map.fromList [(lid, SetLine emptyLine fs 0 ns sn) | (lid, (ns, sn, _)) <- zip ids att],
                          Map.fromList [(lid, [SetLine l fs (scOffset c + sh) [] [] | c <- cells, (j, (l, sh)) <- zip [0 :: Int ..] (zip (scLines c) (scShifts c)), j == k]) | (k, lid) <- zip [0 ..] ids]
                        )
                      | (start, h, cells, att) <- zip4 starts heights (stHeader t : stRows t) atts,
                        let ids = [start .. start + h - 1]
                      ]
                    (headerBoxes, rowBoxes) = case [bs | (bs, _, _) <- rowsOut] of
                      (hb : rbs) -> (hb, rbs)
                      [] -> ([], [])
                    (tl, tw) = tabAcc
                    {- a grid line of space before and after a table; none
                    after a heading, one between two tables (golem-driver ADR 0031) -}
                    spaceBefore = case reverse flows of
                      (FHeading {} : _) -> 0
                      (FRuled {frBody = RuledHeading {}} : _) -> 0
                      (FSpace _ : FTable {} : _) -> 0
                      _ -> 1
                 in ( nextId + sum heights,
                      flows <> [FTable nextId spaceBefore headerBoxes rowBoxes, FSpace 1],
                      Map.unions (lineAcc : [m | (_, m, _) <- rowsOut]),
                      figAcc,
                      headAcc,
                      errs,
                      (Map.unions (tl : [m | (_, _, m) <- rowsOut]), Map.insert nextId (TableGeometry (stWidth t) 0 0 (sum heights)) tw),
                      ext
                    )
          Nothing -> (nextId, flows, lineAcc, figAcc, headAcc, errs, tabAcc, ext)
        _ -> let (a, b, c', d, e, f) = step' (nextId, flows, lineAcc, figAcc, headAcc, errs) (i, u) in (a, b, c', d, e, f, tabAcc, extras nextId i u ext)
      -- headings and table of contents entries by their lines (golem-driver ADR 0009)
      extras nextId i u (hAcc, tAcc) = case uKind u of
        UHeading {} -> (Map.insert nextId (uSpan u) hAcc, tAcc)
        UTocEntry l hs
          | Just c <- Map.lookup i singles,
            ls@(_ : _) <- cLines c ->
              let end = case [off + w | (Box w _, off) <- placeLine (last ls)] of
                    [] -> 0
                    ends -> last ends
               in (hAcc, Map.insert (nextId + length ls - 1) (hs, tocIndent l + end) tAcc)
        _ -> (hAcc, tAcc)
      step' st@(nextId, flows, lineAcc, figAcc, headAcc, errs) (i, u)
        | Map.member i besides = st -- set beside its figure
        | otherwise = case uKind u of
            UFigure _ -> case Map.lookup i figures of
              Nothing -> st
              Just (pf, ferrs, _, fmarks) -> case pfExclusion pf of
                Just ex
                  | null ferrs ->
                      -- the figure and the lines beside it; the rest of a paragraph cut short continues
                      let paras = [(j, c, off) | j <- takeWhile (`Map.member` besides) [i + 1 ..], let (c, off) = besides Map.! j]
                          indentOf off k = if pfWrap pf == Just WrapStart && off + k < exLines ex then exWidth ex else 0
                          -- beside the figure the paragraph indent adds to the exclusion (docs/adr ADR 0006)
                          go (nid, boxAcc, setAcc) (j, c, off) =
                            let (bs, set) = numbered nid (unitAt Map.! j) c (\k -> indentOf off k + lineIndent (uKind (unitAt Map.! j)) k)
                             in (nid + length (cLines c), boxAcc <> bs, Map.union setAcc set)
                          tooNarrow =
                            [ if null (uLists (unitAt Map.! j))
                                then diagnostic "G07028" Error (uSpan (unitAt Map.! j)) "回り込む図版の脇で、字下げを引くと行が残りません"
                                else listTooDeep (uSpan (unitAt Map.! j))
                            | (j, c, off) <- paras,
                              any (\k -> wrappedLineWidth measure ex off k - lineIndent (uKind (unitAt Map.! j)) k <= 0) [0 .. length (cLines c) - 1]
                            ]
                          (nextId', allBoxes, sets) = foldl go (nextId + 1, [], Map.empty) paras
                          (beside, continued) = splitAt (exLines ex) allBoxes
                       in ( nextId',
                            flows <> [FWrapped nextId (exLines ex) (label u) fmarks beside] <> [FContinued continued | not (null continued)],
                            Map.union lineAcc sets,
                            Map.insert nextId pf figAcc,
                            headAcc,
                            errs <> tooNarrow
                          )
                -- a turned figure takes a page of its own (golem-driver ADR 0034)
                _ | isJust (pfTurn pf) -> (nextId + 1, flows <> [FPageFigure nextId (label u) fmarks], lineAcc, Map.insert nextId pf figAcc, headAcc, errs <> ferrs)
                _ -> (nextId + 1, flows <> [FFigure nextId (pfImageLines pf + pfCaptionSpan pf) (label u) fmarks], lineAcc, Map.insert nextId pf figAcc, headAcc, errs <> ferrs)
            UGap n -> (nextId, flows <> [FSpace n], lineAcc, figAcc, headAcc, errs)
            UCode {} -> case Map.lookup i codeBlocks of
              Nothing -> st
              Just cb ->
                let ids = [nextId .. nextId + length (cbRows cb) - 1]
                    -- the label and the index marks of the caption on the first row (golem-driver ADR 0023)
                    boxes = [LineBox lid [] (if k == 0 then label u else []) (if k == 0 then cbMarks cb else []) 0 | (k, lid) <- zip [0 :: Int ..] ids]
                    set = Map.fromList [(lid, SetLine l (cbSize cb) (cbIndent cb) [] []) | (lid, l) <- zip ids (cbRows cb)]
                    info = cbInfo cb
                 in (nextId + length ids, flows <> [FCode (ciGeometry info) (ciCaptionSpan info) (cbFirstRows cb) (isJust (ciContinued info)) boxes], Map.union lineAcc set, figAcc, headAcc, errs)
            UBreak k -> (nextId, flows <> [FBreak k], lineAcc, figAcc, headAcc, errs)
            UPageControl c ->
              let control = case c of
                    NoBreak -> FNoBreak (uSpan u)
                    NeedLines k -> FNeedLines (uSpan u) k
                    AdjustLines k -> FAdjustLines (uSpan u) k
               in (nextId, flows <> [control], lineAcc, figAcc, headAcc, errs)
            UColumns set -> (nextId, flows <> [maybe FRestoreColumns FSwitchColumns set], lineAcc, figAcc, headAcc, errs)
            UBlank k -> (nextId, flows <> [FBlank (uSpan u) (fromIntegral k)], lineAcc, figAcc, headAcc, errs)
            _ ->
              let c = singles Map.! i
                  ls = cLines c
                  (boxes, set) = numbered nextId u c (lineIndent (uKind u))
                  (_, size) = faceOf u
                  least = case uKind u of
                    UHeading l _ _ -> headingLines (bookLanguage inp) (uStyle u) capacity l
                    UNotesTitle _ -> headingLines (bookLanguage inp) (uStyle u) capacity 2
                    _ -> 1
                  hb = headingBlock fs pitch size (length ls) least
                  ruledOf = FRuled nextId (ruleSide True <$> fst (uRules u)) (ruleSide False <$> snd (uRules u)) False (RuleGrid pitch fs) 0
                  flowOf = case uKind u of
                    UHeading _ _ recto | uRules u /= (Nothing, Nothing) -> [ruledOf (RuledHeading recto (hbSpan hb) boxes)]
                    UPara _ | uRules u /= (Nothing, Nothing) -> [ruledOf (RuledLines boxes)]
                    UHeading l _ recto -> [FHeading l recto (hbSpan hb) boxes]
                    UNotesTitle _ -> [FHeading 2 False (hbSpan hb) boxes]
                    UTerm _ -> [FDefTerm boxes]
                    _ -> [FParagraph boxes]
                  (headAcc', errs') = case uKind u of
                    -- the title of the notes is in neither the headings nor the running heads (golem-driver ADR 0026)
                    k
                      | Just name <- headingName k ->
                          ( Map.insert nextId hb headAcc,
                            errs <> [diagnostic "G07024" Error (uSpan u) ("見出しが版面に入りません（" <> name <> "）") | hbSpan hb > capacity]
                          )
                    _ -> (headAcc, errs)
               in (nextId + length ls, flows <> flowOf, Map.union lineAcc set, figAcc, headAcc', errs')
      -- code blocks, set line by line (golem-driver ADR 0017)
      codeBlocks = Map.fromList [(i, codeBlockOf geom fonts measure capacity u lead code (codeCaptionOf u lead code)) | (i, u@Unit {uKind = UCode lead code}) <- units]
      {- the caption of a code block: the listing number, the separator of
      the language of the book (golem-driver ADR 0042) and the caption, set
      as the caption of a figure over the width of the block (golem-driver
      ADR 0023) -}
      codeCaptionOf u lead code = case codeCaption code of
        Nothing -> CodeCaption [] fs pitch 0 []
        Just is ->
          let number = Map.lookup (uSpan u) (bookListings (piBook inp))
              captionInlines = numberedTitle (bookLanguage inp) (uSpan u) number is
              (captionRole, cs) = paraFace (uStyle u) geom "caption"
              captionParams = params {pEmergencyStretch = dimToSp cs (compEmergencyStretch (stComposition style))}
              (captionItems, captionAnchors) = composeInlines ((styledEnv (uStyle u) (envFor (styleLook (uStyle u) (Just "caption") captionRole cs))) {ceAkiSet = akiSetOf (uStyle u) (Just "caption"), ceSizeSource = paraSizeSource (uStyle u) (Just "caption")}) captionInlines
              ls = brLines (breakParagraph captionParams (const (measure - lead)) captionItems)
              cb = headingBlock fs pitch cs (length ls) 1
           in CodeCaption ls cs (hbPitch cb) (if null ls then 0 else hbSpan cb) [sp | AnchorIndex _ sp _ <- captionAnchors]
      codeErrors = concatMap cbErrors (Map.elems codeBlocks)
      -- the text of a list item leaves 8 characters of the type area (golem-driver ADR 0013)
      listTooDeep sp = diagnostic "G07027" Error sp "リストの入れ子が深く、項目の本文の行長が足りません。行長を本文の文字の大きさの 8 字分以上残してください"
      deepLists =
        nub
          [ listTooDeep (uSpan u)
          | (_, u) <- units,
            not (null (uLists u)),
            case uKind u of
              UPara _ -> True
              UTerm _ -> True
              _ -> False,
            measure - outerOf u < 8 * fs
          ]
      -- the block (and so the file) of each unit that has an id, by its first id (golem-driver ADR 0014)
      stepFiles (acc@(n0, _, _, _, _, _, _, _), spans) iu@(_, u) =
        let acc'@(n1, _, _, _, _, _, _, _) = step acc iu
         in (acc', if n1 > n0 then Map.insert n0 (uSpan u) spans else spans)
      lineFiles = Map.map spanFile lineSpans
      ((_, flow, lineMap, figMap, headMap, errors, (tableLines, tableWidths), (headingSpans, tocLines)), lineSpans) = foldl stepFiles ((0, [], Map.empty, Map.empty, Map.empty, deepLists <> codeErrors, (Map.empty, Map.empty), (Map.empty, Map.empty)), Map.empty) units
      -- the code blocks of the flow are those of the units, in order
      codeInfos = Map.fromList [(lbId b, (cbInfo cb) {ciFirst = lbId b0}) | (bs@(b0 : _), cb) <- zip [fcRows f | f@FCode {} <- flow] (Map.elems codeBlocks), b <- bs]
      codeNotices = concatMap cbNotices (Map.elems codeBlocks)
      flow' = ruledLinks (spaceAfterCode (map cbInfo (Map.elems codeBlocks)) flow)
      -- the rules of each ruled block by its first line, from the unit of its block (golem-driver ADR 0027)
      rulesBySpan = Map.fromList [(uSpan u, ruledInfoOf u) | (_, u) <- units, uRules u /= (Nothing, Nothing)]
      ruledInfos = Map.fromList [(frId f, info) | f@FRuled {} <- flow', Just sp <- [Map.lookup (frId f) lineSpans], Just info <- [Map.lookup sp rulesBySpan]]
      -- the span and the name of each heading by its first line, for G07100 (golem-layout ADR 0020)
      namesBySpan = Map.fromList [(uSpan u, (uSpan u, name)) | (_, u) <- units, Just name <- [headingName (uKind u)]]
      headingNames = Map.mapMaybe (`Map.lookup` namesBySpan) lineSpans
      ruledInfoOf u = case uKind u of
        UHeading l _ _ -> uncurry (RuledInfo "見出しの罫線" ("見出し " <> T.pack (show l)) True (lkSize (uLook u))) (uRules u) (uSpan u)
        _ -> uncurry (RuledInfo "段落の罫線" ("段落スタイル " <> fromMaybe "body" (uParaStyle u)) False (lkSize (uLook u))) (uRules u) (uSpan u)
  pure (Built flow' lineMap figMap headMap errors tableLines tableWidths headingSpans tocLines lineFiles codeInfos (codeNotices <> figureNotices) lineSpans ruledInfos headingNames)

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
codeBlockOf :: PageGeometry -> LoadedFonts -> Sp -> Int -> Unit -> Sp -> Code -> CodeCaption -> SetCode
codeBlockOf geom fonts measure capacity u lead code caption =
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
        [] -> [CodeLine "" (Just 1) Nothing False []]
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
      emptyBox w = Box w (BoxContent "" False 0 0 (fromEnum KindText) lk 0 0 [] 0 0 source)
      -- pieces at offsets from the padding: (offset, text, width, Latin, swatch)
      lineOf pieces =
        let go _ [] = []
            go x ((o, t, w, latin, col) : rest) =
              [emptyBox (o - x) | o > x]
                <> [Box w (BoxContent t False 0 0 (tagOf latin) (lookOf col) 0 0 [] 0 0 source)]
                <> go (o + w) rest
         in Line (go 0 (sortOn (\(o, _, _, _, _) -> o) pieces)) 0 (measure - lead - 2 * pad) 0 (0, 0) False (0, 0)
      at o col t = [(o + cpOffset p, cpText p, cpWidth p, cpLatin p, col) | p <- oneRow t]
      lineNumberColor = cdLineNumberColor cs
      rowLine l n (i, (row, markAt)) =
        lineOf
          ( concat [at (numberWidth - widthOf num) lineNumberColor num | i == 0, numbered, Just k <- [clNumber l], let num = T.pack (show k)]
              <> concat [at numberColumn Nothing m | i == 0, Just m <- [diffMark (clDiff l)]]
              <> [(codeStart + cpOffset p, cpText p, cpWidth p, cpLatin p, cpColor p) | p <- crPieces row]
              <> concat [at (codeStart + avail) lineNumberColor wrapMark | i < n - 1, not (T.null wrapMark)]
              <> [(codeStart + o + cpOffset p, cpText p, cpWidth p, cpLatin p, Nothing) | Just o <- [markAt], p <- marksOf (clCallouts l)]
          )
      diffMark = \case
        Just DiffAdded -> Just "+"
        Just DiffRemoved -> Just "-"
        _ -> Nothing
      fileRows = [lineOf (at codeStart Nothing f) | Just f <- [codeFile code]]
      codeRows = concat [zipWith (curry (rowLine l (length rs))) [0 :: Int ..] rs | (l, rs) <- zip ls perLine]
      -- the bands of the highlight (K 15% by default) and of the diff
      bandOf l
        | clHighlight l = Just (fromMaybe (P.Swatch 0 0 0 15) (cdHighlight cs >>= swatchOf))
        | clDiff l == Just DiffAdded = cdAdded cs >>= swatchOf
        | clDiff l == Just DiffRemoved = cdRemoved cs >>= swatchOf
        | otherwise = Nothing
      firsts = scanl (+) (length fileRows) (map length perLine)
      bands = [(r0, length rs, sw) | (l, rs, r0) <- zip3 ls perLine firsts, Just sw <- [bandOf l]]
      continued = cdContinued cs
      continuedLine = if T.null continued then Nothing else Just (lineOf (at (codeStart + full - widthOf continued) Nothing continued))
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
      [ch] -> boxKind c `elem` [KindText, KindPunctuation, KindKenten] && charClass ch /= Western
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
      bytes <- BS.readFile (piRoot inp <> "/" <> T.unpack s)
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
figureBlocks book = [(sp, f) | Document _ bs <- bookDocs book, Block sp _ (FigureBlock f) <- bs]

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

-- | The FileId of style.toml: the one after the files of the project.
styleFileId :: Project -> FileId
styleFileId p = FileId (length (fileTableEntries (projectFiles p)))

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
    r <- resolveInRoot (piRoot inp) path
    case r of
      Left e -> pure (Left [diagnostic "G08006" Error (mkSpan (styleFileId (piProject inp)) 0 0) (T.pack (intentMessage e <> ": " <> path))])
      Right rel -> do
        bytes <- BS.readFile (piRoot inp <> "/" <> rel)
        let md = manifestMetadata (projectManifest (piProject inp))
            condition = if "JapanColor2001Coated" `T.isInfixOf` T.pack path then "JC200103" else T.pack (takeBaseName path)
        pure (Right (Just (uncurry (P.PdfX bytes condition) (pdfXPeople md))))
  where
    intentMessage = \case
      Missing -> "出力インテントの ICC プロファイルがありません"
      e -> pathErrorMessage e
