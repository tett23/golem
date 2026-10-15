{- | The PDF pipeline (golem-driver ADR 0002): page geometry, fonts,
composition and line breaking per paragraph (optionally in parallel),
pagination with page references resolved to a fixed point (S2), font
subsetting and the PDF/X-4 writer.

Fonts come from a 'FontProvider'. The real provider is golem-font
(HarfBuzz and FreeType, golem-font ADR 0001 and 0002), which is not
implemented yet; 'noFontProvider' reports that.
-}
module Golem.Driver.Pdf
  ( FontProvider (..),
    LoadedFonts (..),
    Shaped (..),
    Shaping (..),
    shapingOf,
    noFontProvider,
    bodyRole,
    bodyFontDiagnostics,
    usedRoles,
    bookHasCode,
    codeStyles,
    codeFontNotice,
    syntheticStroke,
    syntheticStrokeJa,
    syntheticStrokeLatin,
    styleFileId,
    PdfInput (..),
    SetLine (..),
    CodeInfo (..),
    PlacedFigure (..),
    PlacedSidenote (..),
    PdfLayout (..),
    sidenoteDiagnostics,
    styleLayoutDiagnostics,
    listNumberDiagnostics,
    placePageSidenotes,
    layoutPdf,
    layoutPages,
    indexLines,
    bibliographyLines,
    Assumed (..),
    fixpoint,
    TocGeometry (..),
    TocPage (..),
    tocPage,
    headingPages,
    headingsOnPages,
    runningHeadText,
    runningHeads,
    hiddenFolios,
    drawsFolio,
    figureRect,
    renderPdf,
    flowLines,
    pdfFileName,
    instanceIdInputs,
    producer,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (evaluate)
import Control.Monad (join)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAlphaNum, isAscii)
import Data.Either (fromRight, isLeft)
import Data.List (groupBy, intercalate, mapAccumL, nub, sortOn, zip4)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (toGregorian)
import Golem.Doc.Assemble
import Golem.Doc.IR
import Golem.Doc.ListMarkers
import Golem.Doc.Numerals (formatNumber)
import Golem.Driver.Version (golemVersion)
import Golem.Layout.Aki (AkiSet, resolveAkiSet)
import Golem.Layout.Code
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass hiding (Sp)
import Golem.Layout.Look hiding (Kerning (..))
import Golem.Layout.Look qualified as L
import Golem.Layout.Paginate
import Golem.Layout.Ruby (RubyKind (..), RubyPlacement (..), RubyStyle (..), placeRuby)
import Golem.Layout.Ruby qualified as R
import Golem.Layout.Sidenotes (SidenoteError (..), placeSidenotes)
import Golem.Layout.Table (SetCell (..), SetTable (..), TableError (..), layoutTable)
import Golem.Layout.Wrap (Exclusion (..), exclusion, wrappedLineWidth)
import Golem.LayoutSpec (Anchor (..), HiddenFolioGeometry (..), MasterGeometry (..), PageGeometry (..), Rect (..), Side (..), baselineRatio, columnsFor, gutterSide, pageGeometry, sidenoteAreaFor, typeAreaFor)
import Golem.LayoutSpec qualified as LS
import Golem.Pdf qualified as P
import Golem.Project
import Golem.Project.Paths (PathError (..), pathErrorMessage, resolveInRoot)
import Golem.Project.Style
import Golem.Syntax
import System.FilePath (takeBaseName)

{- | How a text is shaped (docs/adr/0020): the font role (golem-driver ADR
0003; a role that is not loaded is the body role), the direction, and
the features added after the role's features (HarfBuzz lets a later
feature override an earlier one of the same tag).
-}
data Shaping = Shaping
  { shRole :: !Text,
    shVertical :: !Bool,
    -- | the features added after the role's features
    shExtra :: ![Text]
  }
  deriving stock (Eq, Ord, Show)

{- | Fonts ready for layout and output. Advances are in em. The first
argument of the measuring and shaping functions is how the text is
shaped (docs/adr/0020).
-}
data LoadedFonts = LoadedFonts
  { lfAdvance :: Shaping -> Char -> Rational,
    -- | a Latin word as shaped (kerning, ligatures)
    lfWordAdvance :: Shaping -> Text -> Rational,
    {- | the pair kerning of two characters: the pair shaped together less
    the two shaped apart (docs/adr/0020)
    -} lfPairKern :: Shaping -> Char -> Char -> Rational,
    -- | shaping: the glyphs of a text
    lfShape :: Shaping -> Text -> [Shaped],
    -- | the character code of a glyph in the PDF (its CID in a CID-keyed font)
    lfCode :: Int -> Int -> Int,
    {- | the embedded (subset) font of a face number, for horizontal or
    vertical use, with the glyphs used and their text
    -} lfEmbed :: Int -> Bool -> [(Int, Text)] -> P.Font,
    {- | the height of the centre of the ideographic em box above the
    baseline of a face number, in em (golem-driver ADR 0015)
    -} lfEmBoxCentral :: Int -> Rational
  }

-- | A glyph from shaping.
data Shaped = Shaped
  { shFace :: !Int,
    shGlyph :: !Int,
    -- | the advance in em along the line
    shAdvance :: !Rational,
    -- | the text the glyph stands for
    shText :: !Text,
    -- | drawn turned 90° clockwise in vertical text (golem-driver ADR 0015)
    shTurned :: !Bool,
    -- | the index of the first character of the glyph's cluster in the shaped text (docs/adr/0020)
    shCluster :: !Int
  }
  deriving stock (Eq, Show)

newtype FontProvider = FontProvider
  { {- | the root, style.toml and the styles of the files (docs/adr ADR 0014)
    and the file of the diagnostics about style.toml (golem-driver ADR 0016)
    -} loadFonts :: FilePath -> FileId -> Style -> [LocalStyles] -> IO (Either [Diagnostic] LoadedFonts)
  }

noFontProvider :: FontProvider
noFontProvider =
  FontProvider $ \_ fid _ _ ->
    pure (Left [diagnostic "G0801" Error (mkSpan fid 0 0) "フォントを読まない設定（noFontProvider）では PDF を出力できません"])

{- | What the instance ID is computed from: the bytes of every input, the
embedded font programs and, last, @golem-@ and the version of Golem
(docs/adr/0004; the version is part of the input, docs/adr/0002).
-}
instanceIdInputs :: [ByteString] -> [ByteString] -> [ByteString]
instanceIdInputs inputs programs = inputs <> programs <> [TE.encodeUtf8 ("golem-" <> golemVersion)]

{- | The Producer of the PDF: @Golem @ and the version, from VERSION only
(golem-pdf ADR 0005).
-}
producer :: Text
producer = "Golem " <> golemVersion

data PdfInput = PdfInput
  { piRoot :: !FilePath,
    piProject :: !Project,
    piStyle :: !Style,
    piBook :: !Book,
    piParallel :: !Bool,
    -- | bytes of every input, for the instance ID
    piInputs :: ![ByteString],
    -- | the formatted entries of the bibliography by key (golem-driver ADR 0007)
    piBibliography :: !(Map Text Text),
    -- | the crop marks (golem-pdf ADR 0004)
    piMarks :: !(Maybe P.MarkStyle),
    -- | the styles each file defines (docs/adr ADR 0014)
    piLocalStyles :: !(Map FileId LocalStyles),
    -- | the master page of each chapter file that names one (golem-driver ADR 0014)
    piMasters :: !(Map FileId Text),
    {- | where diagnostics about style.toml point: style.toml, or the
    manifest without one (golem-driver ADR 0016)
    -} piStyleFile :: !FileId
  }

-- | The style of a document: style.toml with the styles its file defines (docs/adr ADR 0014).
docStyle :: PdfInput -> FileId -> Style
docStyle inp fid = maybe (piStyle inp) (withLocalStyles (piStyle inp)) (Map.lookup fid (piLocalStyles inp))

-- | The body font role: @body@, or the first role when there is none.
bodyRole :: Style -> Text
bodyRole style
  | Map.member "body" (stFonts style) = "body"
  | otherwise = maybe "body" fst (Map.lookupMin (stFonts style))

{- | G0807 (golem-driver ADR 0016): style.toml sets no body font, or the
body role has no file, at the top of @fid@.
-}
bodyFontDiagnostics :: FileId -> Style -> [Diagnostic]
bodyFontDiagnostics fid style
  | Map.null (stFonts style) = [err "style.toml に本文のフォントがありません。[fonts.body] を書いてください"]
  | Just (FontRole Nothing Nothing _) <- Map.lookup body (stFonts style) = [err ("[fonts." <> body <> "] にフォントのファイルがありません")]
  | otherwise = []
  where
    body = bodyRole style
    err = diagnostic "G0807" Error (mkSpan fid 0 0)

{- | The font roles the PDF uses, body first, then the others by name:
headings (golem-driver ADR 0003), character styles (ADR 0004) and
paragraph styles, built-in ones included (docs/adr ADR 0005), and the styles
the files define (docs/adr ADR 0014).
-}
usedRoles :: Style -> [LocalStyles] -> [Text]
usedRoles style locals =
  let body = bodyRole style
      -- the role code of the styles code without [fonts.code] is the body role (golem-driver ADR 0017)
      fallback n f = n == "code" && f == "code" && Map.notMember "code" (stFonts style)
      named =
        [f | HeadingStyle {hsFont = Just f} <- Map.elems (stHeadings style)]
          <> [f | (n, CharStyleDef {csFont = Just f}) <- Map.toList (stCharStyles style), not (fallback n f)]
          <> [f | (n, ParaStyleDef {psFont = Just f}) <- Map.toList (stParaStyles style), not (fallback n f)]
          <> [f | ls <- locals, CharStyleDef {csFont = Just f} <- Map.elems (lsCharStyles ls)]
          <> [f | ls <- locals, ParaStyleDef {psFont = Just f} <- Map.elems (lsParaStyles ls)]
      others = Set.toAscList (Set.delete body (Set.fromList named))
   in body : others

{- | Whether a book has code (golem-driver ADR 0017): a code block, or a
character of a character style that is code or based on it, in the style
of its document.
-}
bookHasCode :: (FileId -> Style) -> Book -> Bool
bookHasCode styleOf book = or [any (blockHas (styleOf fid)) bs | Document fid bs <- bookDocs book]
  where
    blockHas :: Style -> Block -> Bool
    blockHas st (Block _ _ body) = case body of
      CodeBlock {} -> True
      Paragraph _ is -> any (inlineHas st) is
      Heading _ _ is -> any (inlineHas st) is
      BulletList items -> any (any (blockHas st) . itemBlocks) items
      OrderedList items -> any (any (blockHas st) . itemBlocks) items
      DefList gs -> or [any (any (inlineHas st)) (dgTerms g) || any (any (blockHas st)) (dgDefs g) | g <- gs]
      Table _ h rows -> any (any (inlineHas st)) (h <> concat rows)
      FigureBlock fig -> any (blockHas st) (figCaption fig)
      _ -> False
    inlineHas :: Style -> InlineF r -> Bool
    inlineHas st = \case
      CharStyle _ n xs -> isCodeCharStyle st n || any (inlineHas st) xs
      Color _ _ xs -> any (inlineHas st) xs
      Kenten _ _ xs -> any (inlineHas st) xs
      Note _ _ xs -> any (inlineHas st) xs
      Sidenote _ _ xs -> any (inlineHas st) xs
      Ruby _ _ segs -> or [any (inlineHas st) b | RubySegment b _ <- segs]
      _ -> False

{- | The styles code of a style as the PDF uses them (golem-driver ADR
0017): without code in the book they name no role, so that the role code
is not loaded; without [fonts.code], the role code they name by default is
left out, and code is set in the body role (or the role around it).
-}
codeStyles :: Bool -> Map Text FontRole -> Style -> Style
codeStyles hasCode fonts st =
  st
    { stParaStyles = Map.adjust (\d -> d {psFont = keep (psFont d)}) "code" (stParaStyles st),
      stCharStyles = Map.adjust (\d -> d {csFont = keep (csFont d)}) "code" (stCharStyles st)
    }
  where
    keep f
      | not hasCode = Nothing
      | f == Just "code" && Map.notMember "code" fonts = Nothing
      | otherwise = f

-- | 'codeStyles' on the styles a file defines.
codeLocalStyles :: Bool -> Map Text FontRole -> LocalStyles -> LocalStyles
codeLocalStyles hasCode fonts ls =
  let st = codeStyles hasCode fonts defaultStyle {stParaStyles = lsParaStyles ls, stCharStyles = lsCharStyles ls}
   in ls {lsParaStyles = stParaStyles st, lsCharStyles = stCharStyles st}

-- | The input of the PDF with the styles code as the PDF uses them (golem-driver ADR 0017).
codeInput :: PdfInput -> PdfInput
codeInput inp =
  let fonts = stFonts (piStyle inp)
      hasCode = bookHasCode (docStyle inp) (piBook inp)
   in inp
        { piStyle = codeStyles hasCode fonts (piStyle inp),
          piLocalStyles = Map.map (codeLocalStyles hasCode fonts) (piLocalStyles inp)
        }

{- | G0808 (golem-driver ADR 0017): the book has code, [fonts.code] is
missing and a style code names the role code; at the top of @fid@.
-}
codeFontNotice :: FileId -> Style -> Book -> [Diagnostic]
codeFontNotice fid style book =
  [ notice "G0808" (mkSpan fid 0 0) "コードの書体の役割 code がないので、本文の書体で組みます"
  | bookHasCode (const style) book,
    Map.notMember "code" (stFonts style),
    (paraStyle style (Just "code") >>= psFont) == Just "code" || (charStyle style "code" >>= csFont) == Just "code"
  ]

{- | The look inside an inline element (golem-driver ADR 0004, docs/adr ADR
0005): a character style's role on the sides the role has, synthetic bold
and slant on the sides it does not have (on both without a role), its
size and colour; and colour. The inner setting wins; the rest is
inherited.
-}
restyle :: Style -> Look -> Inline -> Look
restyle style lk = \case
  CharStyle _ name _ -> case charStyle style name of
    Just cs ->
      let fr = csFont cs >>= (`Map.lookup` stFonts style)
          -- the sides the role sets; without a role (or one not loaded), neither
          (hasJa, hasLatin) = case (csFont cs, fr) of
            (Just _, Just r) -> (isJust (frJa r), isJust (frLatin r))
            (Just _, Nothing) -> (True, True)
            (Nothing, _) -> (False, False)
          role = fromMaybe (lkFace lk) (csFont cs)
          size = maybe (lkSize lk) (dimToSp (lkSize lk)) (csSize cs)
          side covered setting old = case setting of
            Just True -> not covered
            Just False -> False
            Nothing -> old
          synth covered s =
            Synthetic
              { synBold = side covered (csSyntheticBold cs) (synBold s),
                synSlant = side covered (csSyntheticItalic cs) (synSlant s)
              }
       in lk
            { lkFace = if hasJa then role else lkFace lk,
              lkLatinFace = if hasLatin then role else lkLatinFace lk,
              lkSize = size,
              lkSynthetic = synth hasJa (lkSynthetic lk),
              lkLatinSynthetic = synth hasLatin (lkLatinSynthetic lk),
              lkColor = csColor cs <|> lkColor lk,
              -- kerning, tracking, proportional metrics and baseline shift (docs/adr/0020)
              -- code: no kerning (golem-driver ADR 0017)
              lkKerning = if code then L.KernNone else maybe (lkKerning lk) lookKerning (csKerning cs),
              lkTracking = fromMaybe (lkTracking lk) (csTracking cs),
              lkProportional = fromMaybe (lkProportional lk) (csProportional cs),
              lkBaselineShift = maybe (lkBaselineShift lk) (dimToSp size) (csBaselineShift cs),
              -- code breaks at spaces and after a slash (golem-driver ADR 0017)
              lkCode = lkCode lk || code
            }
      where
        code = isCodeCharStyle style name
    Nothing -> lk
  Color _ sw _ -> lk {lkColor = Just sw}
  _ -> lk

-- | The kerning method of style.toml in a look; optical is rejected before layout (docs/adr/0020).
lookKerning :: Kerning -> L.Kerning
lookKerning = \case
  KernJapaneseEqualWidth -> L.KernJapaneseEqualWidth
  KernNone -> L.KernNone
  _ -> L.KernMetrics

{- | A look with the kerning, tracking, proportional metrics and baseline
shift of a resolved paragraph style (docs/adr/0020); zw is the size of the look.
-}
withFeatures :: Maybe ParaStyleDef -> Look -> Look
withFeatures d lk =
  lk
    { lkKerning = maybe (lkKerning lk) lookKerning (d >>= psKerning),
      lkTracking = fromMaybe (lkTracking lk) (d >>= psTracking),
      lkProportional = fromMaybe (lkProportional lk) (d >>= psProportional),
      lkBaselineShift = maybe (lkBaselineShift lk) (dimToSp (lkSize lk)) (d >>= psBaselineShift)
    }

{- | How a character of a look is shaped (docs/adr/0020): in its role, in
vertical text when it is Japanese in a vertical paragraph (Latin is turned
and shaped horizontally), with the features of the kerning method and the
proportional metrics after the role's. Japanese punctuation that JLReq
spaces keeps its full width: palt and vpal are not added to it.
-}
shapingOf :: Bool -> Look -> Char -> Shaping
shapingOf vertical lk c
  | charClass c == Western = Shaping (lkLatinFace lk) False ["-kern" | lkKerning lk == L.KernNone]
  | otherwise = Shaping (lkFace lk) vertical extra
  where
    proportional = [if vertical then "vpal" else "palt" | lkProportional lk, punctSpace (charClass c) == (0, 0)]
    extra = case lkKerning lk of
      L.KernJapaneseEqualWidth -> ["-kern", "-vkrn", "-palt", "-vpal"]
      L.KernNone -> ["-kern", "-vkrn"] <> proportional
      L.KernMetrics -> proportional

-- | The rules at the top and bottom of a table: 0.6pt (golem-driver ADR 0008).
thickRule :: Sp
thickRule = 39322

-- | The rule below the header row of a table: 0.3pt.
thinRule :: Sp
thinRule = 19661

-- | The slant of synthetic italic: 1/5, about 11.3 degrees (golem-driver ADR 0004).
syntheticSlant :: Rational
syntheticSlant = 1 / 5

-- | The outline stroke of synthetic bold for Japanese: 1/80 of the size (golem-driver ADR 0012).
syntheticStrokeJa :: Rational
syntheticStrokeJa = 1 / 80

-- | The outline stroke of synthetic bold for Latin: 1/60 of the size.
syntheticStrokeLatin :: Rational
syntheticStrokeLatin = 1 / 60

-- | The stroke of a size, rounded down to whole sp.
syntheticStroke :: Rational -> Sp -> Sp
syntheticStroke r size = floor (toRational size * r)

-- | The role and size of the headings of a level (golem-driver ADR 0003).
headingFace :: Style -> PageGeometry -> Int -> (Text, Sp)
headingFace style geom level =
  let hs = Map.lookup level (stHeadings style)
   in faceFor style geom (hs >>= hsFont) (hs >>= hsSize)

{- | The role and size of a font role and a size of style.toml: the body
role and the size of the grid when they are not given (golem-driver ADR
0010).
-}
faceFor :: Style -> PageGeometry -> Maybe Text -> Maybe Dim -> (Text, Sp)
faceFor style geom font size =
  (fromMaybe (bodyRole style) font, maybe (pgFontSize geom) (dimToSp (pgFontSize geom)) size)

-- | The role and size of a paragraph style (golem-driver ADR 0010): of captions, sidenotes and paragraphs.
paraFace :: Style -> PageGeometry -> Text -> (Text, Sp)
paraFace style geom name =
  let d = paraStyle style (Just name)
   in faceFor style geom (d >>= psFont) (d >>= psSize)

-- | The file name of the PDF, from the book's identifier.
pdfFileName :: Text -> FilePath
pdfFileName bookId =
  let clean = T.map (\c -> if isAscii c && isAlphaNum c then c else '-') bookId
   in T.unpack (T.dropAround (== '-') clean) <> ".pdf"

-- ------------------------------------------------------------------ flow

-- | One line of the flow, with what is needed to draw it.
data SetLine = SetLine
  { slLine :: !Line,
    slSize :: !Sp,
    -- | how far the line starts from the line start of the column (golem-driver ADR 0005)
    slIndent :: !Sp,
    slNotes :: ![(Int, [Line])],
    -- | the sidenotes marked in the line, in order (golem-driver ADR 0006)
    slSidenotes :: ![(SrcSpan, [Line])]
  }
  deriving stock (Show)

{- | What a code block needs to be drawn (golem-driver ADR 0017): its
geometry, where its background starts from the line start of the column,
and the colour of its background.
-}
data CodeInfo = CodeInfo
  { ciGeometry :: !CodeGeometry,
    ciStart :: !Sp,
    ciBackground :: !(Maybe P.Swatch)
  }
  deriving stock (Show)

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
  { pfImage :: !P.ImageData,
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
    pfExclusion :: !(Maybe Exclusion)
  }

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
    -- | the width of each table
    plTables :: !(Map Int Sp),
    -- | the leader and page number of each table of contents entry, by its last line (golem-driver ADR 0009)
    plTocPages :: !(Map Int TocPage),
    -- | the file of the unit of each first line (golem-driver ADR 0014)
    plLineFiles :: !(Map Int FileId),
    -- | the span of each heading block by its first line
    plHeadingSpans :: !(Map Int SrcSpan),
    -- | the code block of each row of code (golem-driver ADR 0017)
    plCodes :: !(Map Int CodeInfo),
    -- | the notices of the layout (G0730)
    plNotices :: ![Diagnostic]
  }

data Built = Built
  { bFlow :: [Flow],
    bLines :: Map Int SetLine,
    bFigures :: Map Int PlacedFigure,
    -- | heading blocks by their first line
    bHeadings :: Map Int HeadingBlock,
    -- | errors found while building (G0722, G0723, G0724, G0741, G0742)
    bErrors :: [Diagnostic],
    bTableLines :: Map Int [SetLine],
    bTables :: Map Int Sp,
    -- | the span of each heading block by its first line (golem-driver ADR 0009)
    bHeadingSpans :: Map Int SrcSpan,
    -- | the heading and the end of the title of each table of contents entry, by its last line
    bTocLines :: Map Int (SrcSpan, Sp),
    -- | the file of each unit by the id of its first line (golem-driver ADR 0014)
    bLineFiles :: Map Int FileId,
    -- | the code block of each row of code (golem-driver ADR 0017)
    bCodes :: Map Int CodeInfo,
    -- | notices (G0730)
    bNotices :: [Diagnostic]
  }

{- | What style.toml alone decides before the layout (golem-driver ADR
0016): the page geometry (G0701) and the indent of each paragraph style
(G0725), at the top of @fid@. The driver reports them for golem check too.
-}
styleLayoutDiagnostics :: FileId -> Bool -> Style -> [LocalStyles] -> [Diagnostic]
styleLayoutDiagnostics fid marks style locals = either id (\geom -> indentDiagnostics fid style locals geom <> indexDiagnostics fid style geom <> codeMeasureDiagnostics fid style locals geom) (pageGeometry fid marks style)

{- | G0743 (golem-driver ADR 0017): the measure of a column less the padding
on both sides leaves 8 characters of code, in style.toml and in the style
of each file; at the top of @fid@.
-}
codeMeasureDiagnostics :: FileId -> Style -> [LocalStyles] -> PageGeometry -> [Diagnostic]
codeMeasureDiagnostics fid style locals geom =
  nub
    [ diagnostic "G0743" Error (mkSpan fid 0 0) "コードブロックの行長が足りません"
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
  n <- ixColumns ix
  let ta = pgTypeArea geom
      w = if pgVertical geom then rectH ta else rectW ta
      gap = maybe (pageColumnGap style geom) (dimToSp (pgFontSize geom)) (ixColumnGap ix)
  if n == length (pgColumns geom)
    then Nothing
    else Just (ColumnSet n ((w - toInteger (n - 1) * gap) `div` toInteger n) gap 0)

{- | G0744: the columns of the index leave 8 characters of the type
area's size (docs/adr ADR 0025), at the value of [index] columns.
-}
indexDiagnostics :: FileId -> Style -> PageGeometry -> [Diagnostic]
indexDiagnostics fid style geom =
  [ diagnostic "G0744" Error (mkSpan fid at at) "索引の段の行長が足りません。columns を減らすか column-gap を狭めてください"
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
   in [ if pgVertical geom then Rect x (y + h - (i + 1) * m - i * g) w m else Rect (x + i * (m + g)) y m h
      | i <- [0 .. toInteger (csColumns set) - 1]
      ]

{- | G0725: every paragraph style leaves 8 characters of its own size on a
line of a column (docs/adr ADR 0006, golem-driver ADR 0005 and 0016), in
style.toml and in the style of each file (docs/adr ADR 0014).
-}
indentDiagnostics :: FileId -> Style -> [LocalStyles] -> PageGeometry -> [Diagnostic]
indentDiagnostics fid style locals geom =
  nub
    [ diagnostic "G0725" Error (mkSpan fid 0 0) ("段落スタイルの字下げが大きすぎます。行長を段落の文字の大きさの 8 字分以上残してください: " <> name)
    | st <- style : map (withLocalStyles style) locals,
      name <- Map.keys (stParaStyles st),
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

{- | The PDF and the notices of its layout (G0730), or the errors that
stopped it.
-}
renderPdf :: FontProvider -> PdfInput -> IO (Either [Diagnostic] (ByteString, [Diagnostic]))
renderPdf provider inp0 = case checkedGeometry inp of
  Left ds -> pure (Left ds)
  Right geom -> do
    lf <- loadFonts provider (piRoot inp) (piStyleFile inp) (piStyle inp) (Map.elems (piLocalStyles inp))
    case lf of
      Left ds -> pure (Left ds)
      Right fonts -> do
        -- a missing profile is reported before any time is spent on the layout (golem-project ADR 0004)
        li <- loadIntent inp
        case li of
          Left ds -> pure (Left ds)
          Right intent -> fmap (\layout -> (writeDocument inp geom fonts layout intent, plNotices layout)) <$> layoutPdf inp geom fonts
  where
    inp = codeInput inp0

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
        figures <- loadFigures inp
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
          figures <- loadFigures inp
          -- S2: compose with assumed page numbers until they settle
          let terms = Map.fromList [(sp, T.intercalate " / " (igTerms g)) | g <- bookIndex (piBook inp), (_, sp) <- igLocations g]
          let capacity = length (pgLineGrid geom)
              round' assumed = do
                built <- buildFlow inp geom fonts figures assumed
                pure (if null (bErrors built) then Right (built, paginateIn (pageColumnSet (piStyle inp) geom) capacity (bFlow built)) else Left (bErrors built))
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
                  tocPages = Map.fromList [(lid, tocPage tg e (pageNumberLine env n)) | (lid, (hs, e)) <- Map.toList (bTocLines built), Just n <- [Map.lookup hs hPages]]
               in case concat [ds | (_, Left ds) <- placed] of
                    [] -> Right (PdfLayout pages (bLines built) (bFigures built) (bHeadings built) (Map.fromList [(n, ps) | (n, Right ps@(_ : _)) <- placed]) (bTableLines built) (bTables built) tocPages (bLineFiles built) (bHeadingSpans built) (bCodes built) (bNotices built))
                    ds -> Left ds

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

{- | The text of a running head (golem-driver ADR 0014) from the title of
the book, the content, the headings in effect at the start of the page
by level, and the headings that start on the page.
-}
runningHeadText :: Text -> RunningContent -> Map Int (Maybe HeadingInfo) -> [HeadingInfo] -> Maybe Text
runningHeadText title content start started = case content of
  RunningNone -> Nothing
  RunningTitle -> if T.null title then Nothing else Just title
  RunningHeading l form pick ->
    let here = [h | h <- started, hiLevel h == l]
        atEnd = foldl' activeAfter start started
        chosen = case pick of
          PickFirst -> listToMaybe here <|> join (Map.lookup l start)
          PickLast -> listToMaybe (reverse here) <|> join (Map.lookup l atEnd)
        short h = T.concat (map inlineText (hiTitle h))
        render h = case form of
          HeadShort -> short h
          HeadNumbered -> maybe (short h) (\n -> n <> "\x3000" <> short h) (hiNumberText h)
     in render <$> chosen

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

{- | The running head drawn on each page, by page number (golem-driver ADR
0014). None on blank pages, on pages where a recto heading starts, and
on pages whose master page has no running head.
-}
runningHeads :: PdfInput -> PageGeometry -> PdfLayout -> Map Int (Maybe Text)
runningHeads inp geom layout =
  let pages = [p | (p : _) <- pagesOf (plPages layout)]
      infoOf lid = Map.lookup lid (plHeadingSpans layout) >>= (`Map.lookup` bookHeadings (piBook inp))
      started = headingsOnPages infoOf (plPages layout)
      startedOn p = Map.findWithDefault [] (poNumber p) started
      starts = scanl (foldl' activeAfter) Map.empty (map startedOn pages)
      title = mdTitle (manifestMetadata (projectManifest (piProject inp)))
      recto h = maybe False hsRectoBreak (Map.lookup (hiLevel h) (stHeadings (piStyle inp)))
      one p st m
        | poBlank p || any recto (startedOn p) = Nothing
        | otherwise = do
            (co, ce, _, _) <- m >>= mgRunningHead
            runningHeadText title (if odd (poNumber p) then co else ce) st (startedOn p)
   in Map.fromList [(poNumber p, one p st m) | (p, st, m) <- zip3 pages starts (pageMasters inp geom layout)]

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
       in [(c, (x, ph `div` 2 + (toInteger (k - 1 - 2 * i) * size) `div` 2)) | (i, c) <- zip [0 ..] digits]

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
      k0 = if tgLeaders tg && u > 0 then max 0 ((le - (e + g)) `div` u) else 0
      (ns, k) = if ns0 < e + g then (e + g, 0) else (ns0, k0)
      leader = Line [Box u (BoxContent "…" False 0 0 (fromEnum KindText) (tgLook tg) 0 0) | _ <- [1 .. k]] 0 (k * u) 0 (0, 0) False (0, 0)
   in TocPage (le - k * u) leader ns number

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
   in TocGeometry (columnMeasure geom) w (fs `div` 2) u (stTocLeader style == "dots") (ceLook env)

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
      ([t], [r]) -> entry [] t (pagesOf g) : go (Just (t, r)) gs
      ([t, sub], [r, _]) -> [[txt t] | prevMain /= Just (t, r)] <> [entry [txt "　"] sub (pagesOf g)] <> go (Just (t, r)) gs
      _ -> go prevMain gs
    pagesOf g = Set.toAscList (Set.fromList [n | (_, sp) <- igLocations g, Just n <- [pageOf sp]])
    entry prefix term ps =
      prefix <> [txt term] <> (if null ps then [] else txt "　" : intercalate [txt (if vertical then "、" else ", ")] [[Number sp0 n Nothing] | n <- ps])

-- | The lines of the bibliography: @[n] @ and the entry, or the key when it has none.
bibliographyLines :: Map Text Text -> [(Text, Int)] -> [[Inline]]
bibliographyLines bib cites =
  [[Text (mkSpan (FileId 0) 0 0) ("[" <> T.pack (show n) <> "] " <> fromMaybe k (Map.lookup k bib))] | (k, n) <- cites]

{- | The role, size and line pitch of sidenotes: the role and size of the
paragraph style sidenote (golem-driver ADR 0011), the body pitch scaled
to the size.
-}
sidenoteMetrics :: Style -> PageGeometry -> (Text, Sp, Sp)
sidenoteMetrics style geom =
  let (role, size) = paraFace style geom "sidenote"
   in (role, size, pgLinePitch geom * size `div` pgFontSize geom)

{- | Sidenotes the PDF cannot place (golem-driver ADR 0006): in vertical
writing (G0732), without a sidenote column (G0734), or in a footnote or
a caption (G0735).
-}
sidenoteDiagnostics :: PageGeometry -> Book -> [Diagnostic]
sidenoteDiagnostics geom book
  | pgVertical geom = concatMap (verticalSidenotes (defaultComposeEnv 0) {ceVertical = True}) inlineLists
  | otherwise = case pgSidenotes geom of
      Nothing -> [diagnostic "G0734" Error sp "傍注欄（style.toml の [sidenotes]）のない版面では傍注を使えません" | (sp, _) <- sites]
      Just _ -> [diagnostic "G0735" Error sp "PDF では、脚注の本文と図版のキャプションの中に傍注を置けません" | (sp, False) <- sites]
  where
    blocks = concat [bs | Document _ bs <- bookDocs book]
    -- every list of inlines of the book, captions included
    inlineLists = concatMap blockInlines blocks
    blockInlines (Block _ _ body) = case body of
      Paragraph _ is -> [is]
      Heading _ _ is -> [is]
      BulletList items -> concatMap (concatMap blockInlines . itemBlocks) items
      OrderedList items -> concatMap (concatMap blockInlines . itemBlocks) items
      DefList gs -> concat [dgTerms g <> concatMap (concatMap blockInlines) (dgDefs g) | g <- gs]
      Table _ h rows -> h <> concat rows
      FigureBlock fig -> concatMap blockInlines (figCaption fig)
      _ -> []
    -- each sidenote, and whether it is in the text flow
    sites = concatMap siteBlock blocks
    siteBlock b@(Block _ _ body) = case body of
      FigureBlock fig -> [(sp, False) | is <- concatMap blockInlines (figCaption fig), (sp, _) <- concatMap (inlineSites True) is]
      _ -> [x | is <- blockInlines b, x <- concatMap (inlineSites True) is]
    inlineSites flow = \case
      Sidenote sp _ xs -> (sp, flow) : concatMap (inlineSites flow) xs
      Note _ _ xs -> concatMap (inlineSites False) xs
      Kenten _ _ xs -> concatMap (inlineSites flow) xs
      Color _ _ xs -> concatMap (inlineSites flow) xs
      CharStyle _ _ xs -> concatMap (inlineSites flow) xs
      _ -> []

-- | The block of each label, where G0721 points (golem-driver ADR 0016).
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
write (golem-driver ADR 0013): G0729 at the item, whatever the target.
-}
listNumberDiagnostics :: Style -> Bool -> Book -> [Diagnostic]
listNumberDiagnostics style vertical book =
  [ diagnostic "G0729" Error (lsiSpan s) ("リストの番号 " <> T.pack (show (lsiNumber s)) <> " は、書式 " <> renderNumberFormat f <> " で表せません")
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
        [ (sp, toInteger slot * bodyPitch, ls)
        | (slot, s) <- sortOn fst (poSlots p),
          lid <- lineIds s,
          Just sl <- [Map.lookup lid lineMap],
          (sp, ls) <- slSidenotes sl
        ]
      height sp ls = let (pitch, size) = metricsOf sp in toInteger (max 1 (length ls) - 1) * pitch + size
      columnH = maybe 0 rectH (sidenoteAreaFor geom (poNumber p))
      at i = case drop i notes of
        ((sp, _, _) : _) -> sp
        [] -> mkSpan (FileId 0) 0 0
   in if null notes
        then Right []
        else case placeSidenotes columnH (bodyPitch `div` 2) [(want, height sp ls) | (sp, want, ls) <- notes] of
          Right tops -> Right [PlacedSidenote sp t ls | ((sp, _, ls), t) <- zip notes tops]
          Left (TooTall i) -> Left [diagnostic "G0733" Error (at i) "傍注が傍注欄より高く、収まりません"]
          Left (DoesNotFit i) -> Left [diagnostic "G0733" Error (at i) "このページの傍注が傍注欄に収まりません"]

-- | The page numbers assumed in a round of S2: of labels and of index marks (golem-driver ADR 0007).
data Assumed = Assumed
  { asLabels :: !(Map Text Integer),
    asMarks :: !(Map SrcSpan Integer)
  }
  deriving stock (Eq, Show)

{- | S2: lays out with assumed page numbers until the pages of the labels
and index marks settle. A round that fails stops it with its errors;
after 'maxIterations' rounds, G0721 names what still moves and is at the
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
      let named = [(labelSpan l, l) | l <- labels] <> nubOn snd [(m, termOf m) | m <- marks]
          sites = map fst named
       in (diagnostic "G0721" Error (fromMaybe (mkSpan (FileId 0) 0 0) (listToMaybe sites)) ("ページ番号の参照が収束しません: " <> T.intercalate ", " (map snd named)))
            { diagRelated = [(sp, "ページが定まりません") | sp <- drop 1 sites]
            }
    nubOn key = reverse . fst . foldl (\(acc, seen) x -> if key x `elem` seen then (acc, seen) else (x : acc, key x : seen)) ([], [])

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
          ceVertical = pgVertical geom,
          ceKinsokuStrict = compKinsokuStrict comp,
          ceHanging = compHanging comp,
          ceProtrusion = compProtrusion comp,
          ceExplicitHyphenPenalty = compExplicitHyphenPenalty comp,
          ceRuby = rubyStyleOf style (lkSize look),
          ceVerticalNumbers = case stNumbersVertical style of
            "kanji-digits" -> Just StyleKanjiDigits
            "tcy" -> Just StyleTcy
            _ -> Just StyleKanji,
          cePageOf = (`Map.lookup` asLabels assumed),
          ceSidenoteMarker = case snMarker <$> stSidenotes style of
            Just "symbol" -> MarkerSymbol
            Just "none" -> MarkerNone
            _ -> MarkerNumber,
          -- Latin words: US English patterns (golem-layout ADR 0001)
          cePatterns = Just englishUS,
          -- the set of body; a paragraph, a caption and a sidenote take their style's (docs/adr ADR 0019)
          ceAkiSet = akiSetOf style Nothing
        }

{- | The aki set of a paragraph style (docs/adr ADR 0019): its aki-set,
inherited through based-on; Nothing is body.
-}
akiSetOf :: Style -> Maybe Text -> AkiSet
akiSetOf style st = resolveAkiSet (stAkiSets style) (fromMaybe defaultAkiSetName (paraStyle style st >>= psAkiSet))

-- | Larger than the number of notes of any file (see noteKey).
noteKeyBase :: Int
noteKeyBase = 1000000

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
    uParaStyle :: Maybe Text
  }

-- | The indent of the lines of a paragraph in sp (docs/adr ADR 0006). inFirst may be negative; inStart + inFirst >= 0.
data Indent = Indent {inStart :: !Sp, inFirst :: !Sp}
  deriving stock (Eq, Show)

noIndent :: Indent
noIndent = Indent 0 0

data UnitKind
  = UPara !Indent
  | UHeading Int Text Bool
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
  | -- | a code block: how far it starts from the line start (in a list) and its text (golem-driver ADR 0017)
    UCode !Sp Text
  | -- | an entry of the index in its own columns, of their measure (docs/adr ADR 0025)
    UIndexEntry !Sp
  | -- | the start (with the set) and the end of the columns of the index
    UColumns !(Maybe ColumnSet)

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

{- | The marker of an item of a list at a depth (golem-driver ADR 0013): the
bullet of the depth, or the number in the format of the depth. @{n}@ is a
'Number'; in vertical writing an Arabic number of up to two digits is
tate-chu-yoko and other Latin is rotated as Latin text is.
-}
listMarker :: Style -> Bool -> Int -> Maybe Integer -> [Inline]
listMarker style vertical depth = \case
  Nothing -> [Text sp0 (atDepth (lsBullets (stLists style)) depth)]
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
unitsOf :: Book -> PageGeometry -> Maybe ColumnSet -> (FileId -> Style) -> (SrcSpan -> Maybe Integer) -> Map Text Text -> [Unit]
unitsOf book geom indexSet styleOf pageOf bib = concat (snd (mapAccumL doc 0 (bookDocs book)))
  where
    sp0 = mkSpan (FileId 0) 0 0
    txt = Text sp0
    fs = pgFontSize geom
    doc n (Document fid bs) = blocks (styleOf fid) [] n bs
    {- a list of blocks inside the lists @ctx@, from the list number @n@:
    paragraphs of the same style in a row are apart by its space-between
    (docs/adr ADR 0005); in a list item, paragraphs are not indented by
    their style (docs/adr ADR 0006) but by the lists (golem-driver ADR 0013) -}
    blocks style ctx n bs =
      let (n', uss) = mapAccumL (\k (prev, b) -> (gapBefore style ctx prev b <>) <$> block style ctx k b) n (zip (Nothing : map Just bs) bs)
       in (n', concat uss)
    gapBefore style ctx (Just (Block _ _ (Paragraph s1 _))) (Block sp _ (Paragraph s2 _))
      | s1 == s2, Just g <- paraStyle style s2 >>= psSpaceBetween, g > 0 = [Unit (UGap g) Nothing [] sp (bodyLook style fs) style ctx Nothing Nothing]
    gapBefore _ _ _ _ = []
    block style ctx n (Block sp lbl body) =
      let unit kind l is face = Unit kind l is sp face style ctx Nothing Nothing
          plainUnit kind l is = unit kind l is (bodyLook style fs)
       in case body of
            -- a style that keeps its lines: a unit for each line, each indented as a
            -- paragraph (docs/adr ADR 0005, 0006); otherwise the line breaks are
            -- hard breaks inside one unit, and only its first line has the
            -- first-line indent (docs/adr ADR 0016)
            Paragraph st is ->
              let (face, ind) = paraLook style geom st
                  keeps = (paraStyle style st >>= psLineBreaks) == Just KeepLines
                  parts = if keeps then splitBreaks is else [is]
               in (n, [(unit (UPara (if null ctx then ind else noIndent)) (if i == 0 then lbl else Nothing) part face) {uParaStyle = st} | (i, part) <- zip [0 :: Int ..] parts])
            Heading l attrs is ->
              let num = Map.lookup sp (bookHeadings book) >>= hiNumberText
                  title = maybe [] (\h -> [txt (h <> "　")]) (if haNoNumber attrs then Nothing else num) <> is
                  recto = maybe False hsRectoBreak (Map.lookup l (stHeadings style))
               in (n, [unit (UHeading l (T.concat (map inlineText is)) recto) lbl title (uncurry (styleLook style Nothing) (headingFace style geom l))])
            BulletList items -> list style ctx n (map (Nothing,) items)
            OrderedList items -> list style ctx n (zip (map Just (itemNumbers items)) items)
            DefList gs ->
              let group k g = ([plainUnit (UTerm noIndent) Nothing t | t <- dgTerms g] <>) <$> blocksOf k (dgDefs g)
                  blocksOf k ds = let (k', dss) = mapAccumL (blocks style ctx) k ds in (k', concat dss)
                  (n', uss) = mapAccumL group n gs
               in (n', concat uss)
            Table aligns h rows -> (n, [plainUnit (UTable aligns h rows) lbl []])
            -- always in the paragraph style code (golem-driver ADR 0017)
            CodeBlock _ code -> (n, [unit (UCode 0 code) lbl [] (codeLook style geom)])
            FigureBlock fig -> (n, [plainUnit (UFigure fig) lbl []])
            -- the index marks of a title are counted at the heading, not in the table of contents
            ChannelOutput (TocOutput depth) -> (n, [plainUnit (UTocEntry (teLevel e) (teSpan e)) Nothing (maybe [] (\h -> [txt (h <> "　")]) (teNumber e) <> filter (not . isMark) (teTitle e)) | e <- bookToc book, teLevel e <= depth])
            ChannelOutput IndexOutput ->
              let entries kind = [plainUnit kind Nothing is | is <- indexLines (pgVertical geom) pageOf (bookIndex book)]
               in case indexSet of
                    Nothing -> (n, entries (UPara noIndent))
                    -- the index in its own columns (docs/adr ADR 0025)
                    Just set -> (n, [plainUnit (UColumns (Just set)) Nothing []] <> entries (UIndexEntry (csMeasure set)) <> [plainUnit (UColumns Nothing) Nothing []])
            ChannelOutput BibliographyOutput -> (n, [plainUnit (UPara noIndent) Nothing is | is <- bibliographyLines bib (bookCitations book)])
            ForcedBreak k -> (n, [plainUnit (UBreak k) Nothing []])
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
    markFirst m = \case
      (u : rest) -> u {uMarker = Just m} : rest
      [] -> []
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
              | otherwise -> fs `div` 2,
      lid <- take 1 (reverse (uLists u))
    ]
  where
    roundUp x = ((x + fs - 1) `div` fs) * fs

-- | w: the width of the boxes of a marker.
markerWidth :: ComposeEnv -> [Inline] -> Sp
markerWidth env m = sum [w | Box w _ <- fst (composeInlines env m)]

-- | A unit composed and broken into lines.
data Composed = Composed
  { cLines :: [Line],
    cNotes :: [(Int, [Line])],
    -- | sidenote bodies: the item index of the marker, the span and the lines
    cSidenotes :: [(Int, SrcSpan, [Line])],
    -- | index marks: the item index they belong to (a note's marks go with the note) and the mark
    cMarks :: [(Int, SrcSpan)],
    cAnchors :: [Golem.Layout.Japanese.Anchor],
    cItems :: [Item],
    -- | the items of a list marker before the text: the item indices of the anchors are shifted by it (golem-driver ADR 0013)
    cShift :: Int
  }

buildFlow :: PdfInput -> PageGeometry -> LoadedFonts -> Map Text (Maybe P.ImageData) -> Assumed -> IO Built
buildFlow inp geom fonts images assumed = do
  let style = piStyle inp
      fs = pgFontSize geom
      pitch = pgLinePitch geom
      capacity = length (pgLineGrid geom)
      vertical = pgVertical geom
      cites = Map.fromList (bookCitations (piBook inp))
      -- citations show their numbers (golem-driver ADR 0007)
      envFor lk = (composeEnv style geom fonts assumed lk) {ceCiteNumber = (`Map.lookup` cites)}
      bodyEnv = envFor (bodyLook style fs)
      params = kpParams style geom
      measure = columnMeasure geom
      -- the reserve for the page number of a table of contents entry: W and two em (golem-driver ADR 0009)
      tocReserve = fst (tocMetrics bodyEnv) + 2 * fs
      tocIndent l = toInteger (l - 1) * fs
      -- a mark without an assumed page yet stands at page 1 in the first round
      markPage sp = Map.lookup sp (asMarks assumed) <|> (if Map.null (asMarks assumed) then Just 1 else Nothing)
      rawUnits = unitsOf (piBook inp) geom (indexColumnSet style geom) (docStyle inp) markPage (piBibliography inp)
      -- the character styles of the unit's document (docs/adr ADR 0014)
      styledEnv st e = e {ceRestyle = restyle st}
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
           in boxes <> [Box (innerOf u - w) (BoxContent "" False 0 0 (fromEnum KindText) (ceLook env) 0 0)]
      compose lineWidth u =
        let env = (styledEnv (uStyle u) (envFor (uLook u))) {ceAkiSet = akiSetOf (uStyle u) (uParaStyle u)}
            bodyEnv' = (styledEnv (uStyle u) (envFor (bodyLook (uStyle u) fs))) {ceAkiSet = akiSetOf (uStyle u) Nothing}
            marker = markerItems env u
            -- the anchors count the items of the text; the marker comes first
            shift = length marker
            (textItems, anchors) = composeInlines env (uInlines u)
            items = marker <> textItems
            lines' = brLines (breakParagraph params lineWidth items)
            notes = [(n, brLines (breakParagraph params (const measure) (fst (composeInlines bodyEnv' nbody)))) | AnchorNote _ n nbody <- anchors]
            sidenotes = [(i + shift, sp, sidenoteLines (uStyle u) n snBody) | AnchorSidenote i n sp snBody <- anchors]
            marks =
              [(i + shift, sp) | AnchorIndex i sp _ <- anchors]
                <> [(i + shift, sp) | AnchorNote i _ nbody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines bodyEnv' nbody)]
                <> [(i + shift, sp) | AnchorSidenote i _ _ snBody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines bodyEnv' snBody)]
         in Composed lines' notes sidenotes marks anchors items shift
      -- sidenote bodies: their size, the column width, the marker first (golem-driver ADR 0006)
      -- in the role and size of the paragraph style sidenote of the document (docs/adr ADR 0014)
      snMeasure = maybe 0 (rectW . fst) (pgSidenotes geom)
      sidenoteLines st n snBody =
        let (snRole, snSize', _) = sidenoteMetrics st geom
            snEnv = (styledEnv st (envFor (styleLook st (Just "sidenote") snRole snSize'))) {ceAkiSet = akiSetOf st (Just "sidenote")}
            snParams = params {pEmergencyStretch = dimToSp snSize' (compEmergencyStretch (stComposition style))}
            prefix = case ceSidenoteMarker bodyEnv of
              MarkerNumber -> [Text (mkSpan (FileId 0) 0 0) (T.pack (show n) <> " ")]
              MarkerSymbol -> [Text (mkSpan (FileId 0) 0 0) "※ "]
              MarkerNone -> []
         in brLines (breakParagraph snParams (const snMeasure) (fst (composeInlines snEnv (prefix <> snBody))))
      force c = evaluate (length (show (map lineRatio (cLines c))) + length (cNotes c) + length (show [map lineRatio ls | (_, _, ls) <- cSidenotes c]) + length (cAnchors c) + length (cItems c)) >> pure c
      mapper :: (a -> IO b) -> [a] -> IO [b]
      mapper = if piParallel inp then mapConcurrently else mapM
      -- figures: the image, its size, its caption and its exclusion (golem-driver ADR 0005)
      figureOf u fig = do
        img <- join (Map.lookup (figSource fig) images)
        pure (placeFigure u fig img)
      placeFigure u fig img =
        let along = case figWrap fig of
              Nothing -> Right measure
              Just _ -> maybe (Left ()) (Right . dimToSp fs) (figWidth fig >>= parseDim)
            alongSp = fromRight measure along
            (w, h) = (toInteger (P.imgWidth img), toInteger (P.imgHeight img))
            across = if vertical then alongSp * w `div` max 1 h else alongSp * h `div` max 1 w
            m = fromInteger ((across + pitch - 1) `div` pitch)
            number = Map.lookup (uSpan u) (bookFigures (piBook inp))
            captionInlines = maybe [] (\num -> [Text (uSpan u) (num <> "　")]) number <> concat [is | Block _ _ (Paragraph _ is) <- figCaption fig]
            -- the caption in the role and size of the paragraph style caption (golem-driver ADR 0010)
            (captionRole, cs) = paraFace (uStyle u) geom "caption"
            captionParams = params {pEmergencyStretch = dimToSp cs (compEmergencyStretch (stComposition style))}
            (captionItems, captionAnchors) = composeInlines ((styledEnv (uStyle u) (envFor (styleLook (uStyle u) (Just "caption") captionRole cs))) {ceAkiSet = akiSetOf (uStyle u) (Just "caption")}) captionInlines
            caption = if null captionInlines then [] else brLines (breakParagraph captionParams (const alongSp) captionItems)
            captionMarks = [sp | AnchorIndex _ sp _ <- captionAnchors]
            n = length caption
            -- its pitch keeps the body's ratio of pitch to size; it takes the fewest grid lines that hold it
            cb = headingBlock fs pitch cs n
            (cp, span') = if n == 0 then (pitch, 0) else (hbPitch cb, hbSpan cb)
            depth = if n > 0 then toInteger m * pitch + toInteger (n - 1) * cp + cs else across
            gap = dimToSp fs (stWrapGap style)
            ex = (\side -> exclusion side pitch gap alongSp depth) <$> figWrap fig
            errs = case (figWrap fig, ex) of
              -- no wrapping on a page of columns (docs/adr ADR 0018)
              (Just _, _)
                | length (pgColumns geom) > 1 -> [diagnostic "G0726" Error (uSpan u) "段組みの版面では図版を回り込ませられません。wrap を外すか、columns を 1 にしてください"]
              (Just _, Just e)
                | isLeft along || measure - exWidth e < 8 * fs ->
                    [diagnostic "G0722" Error (uSpan u) ("回り込む図版の幅が不正です。寸法で書き、行の残りを本文の 8 字分以上にしてください: " <> fromMaybe "" (figWidth fig))]
                | exLines e > capacity -> [diagnostic "G0723" Error (uSpan u) ("回り込む図版の除外領域が一ページの行数を超えます（" <> T.pack (show (exLines e)) <> " 行）")]
              _ -> []
         in (PlacedFigure img alongSp across (figWrap fig) m caption cs cp span' ex, errs, captionMarks)
      figures = Map.fromList [(i, f) | (i, u@Unit {uKind = UFigure fig}) <- units, Just f <- [figureOf u fig]]
      -- 1. a job per wrapped figure: the paragraphs right after it, in order, beside the exclusion
      wrapJob i ex = go (i + 1) 0
        where
          go j offset
            | offset >= exLines ex = pure []
            | Just u@Unit {uKind = UPara _} <- Map.lookup j unitAt = do
                c <- force (compose (\k -> wrappedLineWidth measure ex offset k - lineIndent (uKind u) k) u)
                ((j, (c, offset)) :) <$> go (j + 1) (offset + length (cLines c))
            | otherwise = pure []
      jobs = [(i, ex) | (i, (pf, [], _)) <- Map.toList figures, Just ex <- [pfExclusion pf]]
  besides <- Map.fromList . concat <$> mapper (uncurry wrapJob) jobs
  -- 2. every other unit on its own
  let rest = [(i, u) | (i, u) <- units, Map.notMember i besides, not (isFigure u), not (isTable u), not (isGap u)]
      -- gaps and breaks are not composed
      isGap u = case uKind u of
        UGap _ -> True
        UBreak _ -> True
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
            noteBody b = brLines (breakParagraph params (const measure) (fst (composeInlines env b)))
            marksIn b = [sp | AnchorIndex _ sp _ <- snd (composeInlines env b)]
         in ( Map.fromListWith (flip (<>)) [(lineOf i, [(n, noteBody b)]) | AnchorNote i n b <- anchors],
              Map.fromListWith (flip (<>)) [(lineOf i, [(sp, sidenoteLines st n b)]) | AnchorSidenote i n sp b <- anchors],
              Map.fromListWith (flip (<>)) ([(lineOf i, [sp]) | AnchorIndex i sp _ <- anchors] <> [(lineOf i, sps) | AnchorNote i _ b <- anchors, let { sps = marksIn b }, not (null sps)] <> [(lineOf i, sps) | AnchorSidenote i _ _ b <- anchors, let sps = marksIn b, not (null sps)])
            )
      -- a table: every cell at the body size, no hanging punctuation (golem-driver ADR 0008)
      composeTable st aligns h rows =
        let env = (styledEnv st bodyEnv) {ceHanging = False}
            cellOf = composeInlines env
            hCells = map cellOf h
            rCells = map (map cellOf) rows
            rowAttached cells setCells height =
              let perCell = [attached st items anchors (scLines sc) | ((items, anchors), sc) <- zip cells setCells]
               in [(concat [Map.findWithDefault [] k ns | (ns, _, _) <- perCell], concat [Map.findWithDefault [] k sn | (_, sn, _) <- perCell], concat [Map.findWithDefault [] k ms | (_, _, ms) <- perCell]) | k <- [0 .. height - 1]]
         in case layoutTable params measure fs aligns (map fst hCells) (map (map fst) rCells) of
              Left e -> Left e
              Right t -> Right (t, rowAttached hCells (stHeader t) (stHeaderLines t) : zipWith3 rowAttached rCells (stRows t) (stRowLines t))
      tableUnits = [(i, uStyle u, aligns, h, rows) | (i, u@Unit {uKind = UTable aligns h rows}) <- units]
  _ <- mapper (\(_, (pf, _, _)) -> evaluate (length (show (map lineRatio (pfCaption pf))))) (Map.toList figures)
  singles <- Map.fromList . zip (map fst rest) <$> mapper (\(_, u) -> force (compose (widthOf (uKind u)) u)) rest
  tables <- Map.fromList <$> mapper (\(i, st, aligns, h, rows) -> let r = composeTable st aligns h rows in evaluate (length (show (fmap fst r))) >> pure (i, r)) tableUnits
  -- 3. number the lines in document order
  let label u = maybe [] pure (uLabel u)
      -- the key of a footnote in the book: its number counts in its file,
      -- so the line of its marker tells it from a note of another file
      -- with the same number
      noteKey lid n = lid * noteKeyBase + n
      noteKeys lid = map (first (noteKey lid))
      -- the lines of a paragraph-like unit from an id; indent of line k
      numbered nextId u c indentOf =
        let ls = cLines c
            ids = [nextId .. nextId + length ls - 1]
            (_, size) = faceOf u
            -- notes belong to the line containing their anchor
            lineOfItem = lineIndexOfItems (cItems c) ls
            noteLines = Map.fromListWith (<>) [(lineOfItem (i + cShift c), [(n, nls)]) | (AnchorNote i n _, (_, nls)) <- zip [a | a@AnchorNote {} <- cAnchors c] (cNotes c)]
            sidenoteLinesOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [(sp, sls)]) | (i, sp, sls) <- cSidenotes c]
            marksOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [sp]) | (i, sp) <- cMarks c]
            boxes = [LineBox lid [NoteBody (noteKey lid n) (length nls) | (n, nls) <- Map.findWithDefault [] k noteLines] (if k == 0 then label u else []) (Map.findWithDefault [] k marksOf) | (k, lid) <- zip [0 ..] ids]
            set = Map.fromList [(lid, SetLine l size (indentOf k) (noteKeys lid (Map.findWithDefault [] k noteLines)) (Map.findWithDefault [] k sidenoteLinesOf)) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
         in (boxes, set)
      emptyLine = Line [] 0 0 0 (0, 0) False (0, 0)
      mm sp = let tenths = round (toRational sp * 254 / (72 * 65536)) :: Integer in T.pack (show (tenths `div` 10) <> "." <> show (tenths `mod` 10))
      step (nextId, flows, lineAcc, figAcc, headAcc, errs, tabAcc, ext) (i, u) = case uKind u of
        UTable {} -> case Map.lookup i tables of
          Just (Left (ColumnsTooWide mn avail)) ->
            (nextId, flows, lineAcc, figAcc, headAcc, errs <> [diagnostic "G0741" Error (uSpan u) ("表の列の最小の幅の合計（" <> mm mn <> " mm）が使える幅（" <> mm avail <> " mm）に収まりません")], tabAcc, ext)
          Just (Right (t, atts))
            | tall@(_ : _) <- [r | (r, h) <- zip [1 :: Int ..] (stRowLines t), stHeaderLines t + h > capacity] ->
                (nextId, flows, lineAcc, figAcc, headAcc, errs <> [diagnostic "G0742" Error (uSpan u) ("表の " <> T.pack (show r) <> " 行目が見出しの行とともに一ページに収まりません") | r <- tall], tabAcc, ext)
            | otherwise ->
                let heights = stHeaderLines t : stRowLines t
                    starts = scanl (+) nextId heights
                    rowsOut =
                      [ ( [LineBox lid [NoteBody (noteKey lid n) (length nls) | (n, nls) <- ns] (if lid == nextId then label u else []) ms | (lid, (ns, _, ms)) <- zip ids att],
                          Map.fromList [(lid, SetLine emptyLine fs 0 (noteKeys lid ns) sn) | (lid, (ns, sn, _)) <- zip ids att],
                          Map.fromList [(lid, [SetLine l fs (scOffset c + sh) [] [] | c <- cells, (j, (l, sh)) <- zip [0 :: Int ..] (zip (scLines c) (scShifts c)), j == k]) | (k, lid) <- zip [0 ..] ids]
                        )
                      | (start, h, cells, att) <- zip4 starts heights (stHeader t : stRows t) atts,
                        let ids = [start .. start + h - 1]
                      ]
                    (headerBoxes, rowBoxes) = case [bs | (bs, _, _) <- rowsOut] of
                      (hb : rbs) -> (hb, rbs)
                      [] -> ([], [])
                    (tl, tw) = tabAcc
                 in ( nextId + sum heights,
                      flows <> [FTable nextId headerBoxes rowBoxes],
                      Map.unions (lineAcc : [m | (_, m, _) <- rowsOut]),
                      figAcc,
                      headAcc,
                      errs,
                      (Map.unions (tl : [m | (_, _, m) <- rowsOut]), Map.insert nextId (stWidth t) tw),
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
              Just (pf, ferrs, fmarks) -> case pfExclusion pf of
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
                                then diagnostic "G0728" Error (uSpan (unitAt Map.! j)) "回り込む図版の脇で、字下げを引くと行が残りません"
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
                _ -> (nextId + 1, flows <> [FFigure nextId (pfImageLines pf + pfCaptionSpan pf) (label u) fmarks], lineAcc, Map.insert nextId pf figAcc, headAcc, errs <> ferrs)
            UGap n -> (nextId, flows <> [FSpace n], lineAcc, figAcc, headAcc, errs)
            UCode {} -> case Map.lookup i codeBlocks of
              Nothing -> st
              Just cb ->
                let ids = [nextId .. nextId + length (cbRows cb) - 1]
                    boxes = [LineBox lid [] (if k == 0 then label u else []) [] | (k, lid) <- zip [0 :: Int ..] ids]
                    set = Map.fromList [(lid, SetLine l (cbSize cb) (cbIndent cb) [] []) | (lid, l) <- zip ids (cbRows cb)]
                 in (nextId + length ids, flows <> [FCode (ciGeometry (cbInfo cb)) boxes], Map.union lineAcc set, figAcc, headAcc, errs)
            UBreak k -> (nextId, flows <> [FBreak k], lineAcc, figAcc, headAcc, errs)
            UColumns set -> (nextId, flows <> [maybe FRestoreColumns FSwitchColumns set], lineAcc, figAcc, headAcc, errs)
            _ ->
              let c = singles Map.! i
                  ls = cLines c
                  (boxes, set) = numbered nextId u c (lineIndent (uKind u))
                  (_, size) = faceOf u
                  hb = headingBlock fs pitch size (length ls)
                  flowOf = case uKind u of
                    UHeading l _ recto -> [FHeading l recto (hbSpan hb) boxes]
                    UTerm _ -> [FDefTerm boxes]
                    _ -> [FParagraph boxes]
                  (headAcc', errs') = case uKind u of
                    UHeading l short _ ->
                      ( Map.insert nextId hb headAcc,
                        errs <> [diagnostic "G0724" Error (uSpan u) ("見出しが版面に入りません（" <> T.pack (show l) <> " の見出し: " <> short <> "）") | hbSpan hb > capacity]
                      )
                    _ -> (headAcc, errs)
               in (nextId + length ls, flows <> flowOf, Map.union lineAcc set, figAcc, headAcc', errs')
      -- code blocks, set line by line (golem-driver ADR 0017)
      codeBlocks = Map.fromList [(i, codeBlockOf geom fonts measure capacity u lead code) | (i, u@Unit {uKind = UCode lead code}) <- units]
      codeErrors = concatMap cbErrors (Map.elems codeBlocks)
      -- the text of a list item leaves 8 characters of the type area (golem-driver ADR 0013)
      listTooDeep sp = diagnostic "G0727" Error sp "リストの入れ子が深く、項目の本文の行長が足りません。行長を本文の文字の大きさの 8 字分以上残してください"
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
      -- the file of each unit that has an id, by its first id (golem-driver ADR 0014)
      stepFiles (acc@(n0, _, _, _, _, _, _, _), files) iu@(_, u) =
        let acc'@(n1, _, _, _, _, _, _, _) = step acc iu
         in (acc', if n1 > n0 then Map.insert n0 (spanFile (uSpan u)) files else files)
      ((_, flow, lineMap, figMap, headMap, errors, (tableLines, tableWidths), (headingSpans, tocLines)), lineFiles) = foldl stepFiles ((0, [], Map.empty, Map.empty, Map.empty, deepLists <> codeErrors, (Map.empty, Map.empty), (Map.empty, Map.empty)), Map.empty) units
      -- the code blocks of the flow are those of the units, in order
      codeInfos = Map.fromList [(lbId b, cbInfo cb) | (bs, cb) <- zip [bs | FCode _ bs <- flow] (Map.elems codeBlocks), b <- bs]
      codeNotices = concatMap cbNotices (Map.elems codeBlocks)
  pure (Built flow lineMap figMap headMap errors tableLines tableWidths headingSpans tocLines lineFiles codeInfos codeNotices)

-- | A code block set (golem-driver ADR 0017).
data SetCode = SetCode
  { cbRows :: [Line],
    cbSize :: Sp,
    -- | where the rows start from the line start of the column: the list and the padding
    cbIndent :: Sp,
    cbInfo :: CodeInfo,
    -- | G0743
    cbErrors :: [Diagnostic],
    -- | G0730
    cbNotices :: [Diagnostic]
  }

{- | Sets a code block of a unit that starts @lead@ from the line start in
a column of @measure@ and @capacity@ grid lines (golem-driver ADR 0017):
each line as 'layoutCodeLine' wraps it, from the clusters of shaping in
the role of the paragraph style code, spaces of its Latin face.
-}
codeBlockOf :: PageGeometry -> LoadedFonts -> Sp -> Int -> Unit -> Sp -> Text -> SetCode
codeBlockOf geom fonts measure capacity u lead code =
  let lk = uLook u
      size = lkSize lk
      vertical = pgVertical geom
      toSp a = round (a * toRational size) :: Sp
      -- the shaping of each side: Latin, or Japanese ('漢')
      side latin = shapingOf vertical lk (if latin then 'a' else '\x6F22')
      shape latin r =
        let gs = lfShape fonts (side latin) r
            starts = Set.toAscList (Set.fromList (map shCluster gs))
            ends = drop 1 starts <> [T.length r]
         in [(T.take (e - c) (T.drop c r), sum [toSp (shAdvance x) | x <- gs, shCluster x == c]) | (c, e) <- zip starts ends]
      s = toSp (lfAdvance fonts (side True) ' ')
      pad = codePadding (uStyle u) size
      avail = measure - lead - 2 * pad
      rowsOf l = layoutCodeLine s avail (codeAtoms shape l)
      perLine = map rowsOf (T.splitOn "\n" code)
      wrapped = length (filter ((> 1) . length) perLine)
      tagOf latin = fromEnum (if vertical && latin then KindRotated else KindText)
      emptyBox w = Box w (BoxContent "" False 0 0 (fromEnum KindText) lk 0 0)
      lineOf row =
        let go _ [] = []
            go x (pc : rest) =
              [emptyBox (cpOffset pc - x) | cpOffset pc > x]
                <> [Box (cpWidth pc) (BoxContent (cpText pc) False 0 0 (tagOf (cpLatin pc)) lk 0 0)]
                <> go (cpOffset pc + cpWidth pc) rest
         in Line (go 0 (crPieces row)) 0 avail 0 (0, 0) False (0, 0)
      g = codeGeometry (pgFontSize geom) (pgLinePitch geom) size pad
      background = do
        name <- paraStyle (uStyle u) (Just "code") >>= psBackground
        Swatch (cc, cm, cy, ck) <- Map.lookup name (stSwatches (uStyle u))
        pure (P.Swatch cc cm cy ck)
      errs =
        [diagnostic "G0743" Error (uSpan u) "コードブロックの行長が足りません" | avail < 8 * size]
          <> [diagnostic "G0743" Error (uSpan u) "コードブロックの一行が一ページに収まりません" | codeSpan g 1 > capacity]
   in SetCode
        { cbRows = map lineOf (concat perLine),
          cbSize = size,
          cbIndent = lead + pad,
          cbInfo = CodeInfo g lead background,
          cbErrors = take 1 errs,
          cbNotices = [notice "G0730" (uSpan u) ("コードの行を折り返しました（" <> T.pack (show wrapped) <> " 行）") | wrapped > 0]
        }

-- | Which line (0-based) contains the item at an index.
lineIndexOfItems :: [Item] -> [Line] -> Int -> Int
lineIndexOfItems _ ls i =
  let counts = scanl1 (+) (map (length . lineItems) ls)
   in length (takeWhile (<= i) counts) `min` max 0 (length ls - 1)

-- | The images of the figures, read once; sizes are worked out per figure.
loadFigures :: PdfInput -> IO (Map Text (Maybe P.ImageData))
loadFigures inp = do
  let srcs = nub [figSource f | Document _ bs <- bookDocs (piBook inp), f <- figuresIn bs]
  pairs <- mapM (\s -> (s,) <$> loadOne s) srcs
  pure (Map.fromList pairs)
  where
    figuresIn = concatMap (\(Block _ _ b) -> case b of FigureBlock f -> [f]; _ -> [])
    loadOne s = do
      bytes <- BS.readFile (piRoot inp <> "/" <> T.unpack s)
      pure (either (const Nothing) Just (P.readImage bytes))

{- | The rectangle of a figure's image from grid line @slot@ (golem-driver
ADR 0005): its top (in vertical writing its right) edge at the top of the
line at that grid line; at the line start, or at the line end for
@wrap=end@.
-}
figureRect :: PageGeometry -> Rect -> Int -> PlacedFigure -> Rect
figureRect geom ta slot pf =
  let d = toInteger slot * pgLinePitch geom
      atEnd = pfWrap pf == Just WrapEnd
      along = pfAlong pf
      across = pfAcross pf
   in if pgVertical geom
        then
          let right = rectX ta + rectW ta - d
           in Rect (right - across) (if atEnd then rectY ta else rectY ta + rectH ta - along) across along
        else
          let top = rectY ta + rectH ta - d
           in Rect (if atEnd then rectX ta + rectW ta - along else rectX ta) (top - across) along across

-- | The FileId of style.toml: the one after the files of the project.
styleFileId :: Project -> FileId
styleFileId p = FileId (length (fileTableEntries (projectFiles p)))

-- | The output intent; a profile that cannot be read is G0806 (golem-project ADR 0004).
loadIntent :: PdfInput -> IO (Either [Diagnostic] (Maybe P.PdfX))
loadIntent inp = case stIntent (piStyle inp) of
  Nothing -> pure (Right Nothing)
  Just path -> do
    r <- resolveInRoot (piRoot inp) path
    case r of
      Left e -> pure (Left [diagnostic "G0806" Error (mkSpan (styleFileId (piProject inp)) 0 0) (T.pack (intentMessage e <> ": " <> path))])
      Right rel -> do
        bytes <- BS.readFile (piRoot inp <> "/" <> rel)
        let md = manifestMetadata (projectManifest (piProject inp))
            condition = if "JapanColor2001Coated" `T.isInfixOf` T.pack path then "JC200103" else T.pack (takeBaseName path)
        pure (Right (Just (P.PdfX bytes condition [crName c | c <- mdCreators md])))
  where
    intentMessage = \case
      Missing -> "出力インテントの ICC プロファイルがありません"
      e -> pathErrorMessage e

-- ------------------------------------------------------------------ drawing

writeDocument :: PdfInput -> PageGeometry -> LoadedFonts -> PdfLayout -> Maybe P.PdfX -> ByteString
writeDocument inp geom fonts layout intent =
  let md = manifestMetadata (projectManifest (piProject inp))
      (pw, ph) = pgPageSize geom
      vertical = pgVertical geom
      -- the master page and the running head of each page (golem-driver ADR 0014)
      masters = pageMasters inp geom layout
      heads = runningHeads inp geom layout
      grid = pgLineGrid geom
      baseSet = pageColumnSet (piStyle inp) geom
      gridAt sl = case drop sl grid of
        (g : _) -> g
        [] -> 0
      -- font index × direction: even refs horizontal, odd refs vertical
      ref ix v = P.FontRef (2 * ix + (if v then 1 else 0))
      toSp size a = round (a * toRational size) :: Integer
      style = piStyle inp
      body = bodyRole style
      isLatin = (== Western) . charClass
      {- the runs of a text in a look: its role and whether it is a Latin
      run; split into Latin and other runs where the two sides differ in
      role or in synthetic bold and slant (golem-driver ADR 0004, docs/adr ADR 0005);
      a variation selector stays with the character before it (golem-pdf ADR 0006) -}
      runsOf look txt
        | lkFace look == lkLatinFace look && lkSynthetic look == lkLatinSynthetic look && not (synBold (lkSynthetic look) || synBold (lkLatinSynthetic look)) = [(lkFace look, txt, False)]
        | otherwise = [(if latin then lkLatinFace look else lkFace look, r, latin) | r <- T.groupBy (\a b -> isVariationSelector b || isLatin a == isLatin b) txt, not (T.null r), let latin = isLatin (T.head r)]
      -- the synthetic bold and slant of a run
      syntheticOf look latin = if latin then lkLatinSynthetic look else lkSynthetic look
      -- glyph marks of a text in a look starting at a point, and the glyphs used
      runAt look v rotated scale (bx, by) txt =
        let size = lkSize look
            -- the baseline shift: up in horizontal text, right in vertical text (docs/adr/0020)
            shift = lkBaselineShift look
            (x0, y0) = if v then (bx + shift, by) else (bx, by + shift)
            -- shaped with the features of the look; rotated Latin is shaped horizontally
            vv = v && not rotated
            shapingFor role r = (shapingOf vv look (maybe ' ' fst (T.uncons r))) {shRole = role, shVertical = vv}
            {- the tracking after the last glyph of each cluster, for each of its
            characters, as the boxes count it (docs/adr/0020) -}
            tr = toInteger (lkTracking look) * size
            trackingAfter r shaped =
              let starts = map shCluster shaped
                  nexts = drop 1 starts <> [T.length r]
                  cluster c = minimum (T.length r : filter (> c) starts) - c
               in [if n /= c then round (toInteger (cluster c) * tr % 1000) else 0 | (c, n) <- zip starts nexts]
            -- the stroke of synthetic bold of a side: Latin or Japanese (golem-driver ADR 0012)
            strokeOf latin s
              | synBold s = syntheticStroke (if latin then syntheticStrokeLatin else syntheticStrokeJa) size
              | otherwise = 0
            gs =
              concat
                [ [(ix, g, a, t, (synSlant s, strokeOf latin s), tu, extra) | (Shaped ix g a t tu _, extra) <- zip shaped (trackingAfter r shaped)]
                | (role, r, latin) <- runsOf look txt,
                  let s = syntheticOf look latin
                      shaped = lfShape fonts (shapingFor role r) r
                ]
            advs = scanl (+) 0 [toSp size a + extra | (_, _, a, _, _, _, extra) <- gs]
            -- a glyph turned in vertical text: drawn with the horizontal font (golem-driver ADR 0015)
            placed = [(ix, g, t, sb, tu && v && not rotated, off) | ((ix, g, _, t, sb, tu, _), off) <- zip gs advs]
            byFont = Map.fromListWith (flip (<>)) [((ix, sb, tu), [(g, t, off)]) | (ix, g, t, sb, tu, off) <- placed]
            at off = if v then (x0, y0 - off) else (x0 + off, y0)
            -- the baseline of a turned glyph: left of the centre line by the centre of its em box
            turnedAt ix off = (x0 - toSp size (lfEmBoxCentral fonts ix), y0 - off)
            mark (ix, (sl, stroke), turned) xs
              | sl || stroke > 0 =
                  let rs = P.RunStyle (if v then 1000 else 1000 + scale) (v && (rotated || turned)) (if sl then syntheticSlant else 0) stroke
                      pos off = if turned then turnedAt ix off else at off
                   in P.StyledGlyphRun rs (ref ix (v && not rotated && not turned)) size [(code ix g, gx, gy) | (g, _, off) <- xs, let (gx, gy) = pos off]
              | turned = P.RotatedGlyphRun (ref ix False) size [(code ix g, gx, gy) | (g, _, off) <- xs, let (gx, gy) = turnedAt ix off]
              | v && rotated = P.RotatedGlyphRun (ref ix False) size [(code ix g, x0, y0 - off) | (g, _, off) <- xs]
              | v = P.GlyphRun (ref ix True) size [(code ix g, x0, y0 - off) | (g, _, off) <- xs]
              | scale /= 0 = P.ScaledGlyphRun (ref ix False) size (1000 + scale) [(code ix g, x0 + off, y0) | (g, _, off) <- xs]
              | otherwise = P.GlyphRun (ref ix False) size [(code ix g, x0 + off, y0) | (g, _, off) <- xs]
            code = lfCode fonts
         in ([mark k xs | (k, xs) <- Map.toList byFont], [(ref ix (v && not rotated && not tu), g, t) | (ix, g, t, _, tu, _) <- placed])
      -- the swatch of a look, when it names one (golem-driver ADR 0004)
      swatchOf look = do
        name <- lkColor look
        Swatch (cc, cm, cy, ck) <- Map.lookup name (stSwatches style)
        pure (P.Swatch cc cm cy ck)
      -- a line at a distance across the type area: the baseline from its
      -- top edge, or the centre line from its right edge
      drawLine ta cross sl
        | vertical = drawLineAt (rectX ta + rectW ta - cross, rectY ta + rectH ta) sl
        | otherwise = drawLineAt (rectX ta, rectY ta + rectH ta - cross) sl
      -- a line from its start point: on the baseline, or on the centre line
      drawLineAt (x0, y0) sl =
        let l = slLine sl
            origin off0
              | vertical = (x0, y0 - off)
              | otherwise = (x0 + off, y0)
              where
                off = off0 + slIndent sl
            -- a point beside the line at a distance across it: right of a
            -- vertical line, above a horizontal baseline
            beside (ox, oy) dist
              | vertical = (ox + dist, oy)
              | otherwise = (ox, oy + dist)
            placed = placeLine l
            lastIx = length placed - 1
            -- the look of the last box before an item (a hyphen is drawn in it)
            lookBefore i = case [bcLook c | (Box _ c, _) <- reverse (take i placed)] of
              (lk : _) -> lk
              [] -> plainLook body (slSize sl)
            boxRun (i, (it, off)) = case it of
              Box w c ->
                let look = bcLook c
                    size = lkSize look
                    half = look {lkSize = size `div` 2}
                 in (,) (lkColor look) $ case boxKind c of
                      kind
                        | kind `elem` [KindRuby, KindGroupRuby] ->
                            -- each base and reading character where placeRuby puts it (golem-layout ADR 0009)
                            let (base, reading) = T.breakOn "|" (bcText c)
                                rt = T.drop 1 reading
                                rsize = lkSize half
                                advOf lk ch = toSp (lkSize lk) (lfAdvance fonts (shapingOf vertical lk ch) ch)
                                baseAdv = map (advOf look) (T.unpack base)
                                readAdv = map (advOf half) (T.unpack rt)
                                excess = max 0 (sum readAdv - w)
                                rp = placeRuby (rubyStyleOf style (lkSize look)) (if kind == KindRuby then MonoRuby else GroupRuby) baseAdv readAdv (excess `div` 2, excess `div` 2)
                                across = if vertical then size `div` 2 + rsize `div` 2 else size
                                placed1 = [runAt look vertical False 0 (origin (off + pos)) (T.singleton ch) | (ch, pos) <- zip (T.unpack base) (rpBase rp)]
                                placed2 = [runAt half vertical False 0 (beside (origin (off + pos)) across) (T.singleton ch) | (ch, pos) <- zip (T.unpack rt) (rpReading rp)]
                             in (concatMap fst (placed1 <> placed2), concatMap snd (placed1 <> placed2))
                      KindKenten ->
                        -- the character, and a sesame dot centred beside it
                        let dsize = lkSize half
                            (b1, u1) = runAt look vertical False 0 (origin off) (bcText c)
                            (b2, u2) = runAt half vertical False 0 (beside (origin (off + (size - dsize) `div` 2)) (if vertical then size `div` 2 + dsize `div` 2 else size)) "﹅"
                         in (b1 <> b2, u1 <> u2)
                      _ ->
                        let pre = case T.unpack (bcText c) of
                              [ch] | boxKind c == KindPunctuation -> toSp size (fst (punctSpace (charClass ch)))
                              _ -> 0
                            rotated = boxKind c == KindRotated
                            (ox, oy) = origin (off - pre)
                            -- vertical glyph origins sit on the centre line; rotated Latin sits on a baseline beside it
                            pt
                              | vertical && rotated = (ox - size * 3 `div` 10, oy)
                              | otherwise = (ox, oy) -- Identity-V: the origin is the top centre of the em box
                         in runAt look vertical rotated (if bcExpandable c then lineExpansion l else 0) pt (bcText c)
              -- a word broken at the line end gets its hyphen
              Penalty hw _ PatternHyphen
                | i == lastIx && hw > 0 ->
                    let (ox, oy) = origin off
                        look = lookBefore i
                        size = lkSize look
                     in (lkColor look, runAt look vertical vertical 0 (if vertical then (ox - size * 3 `div` 10, oy) else (ox, oy)) "-")
              _ -> (Nothing, ([], []))
            parts = filter (not . null . fst . snd) (zipWith (curry boxRun) [0 ..] placed)
            -- boxes of the same swatch in a row share one saved colour
            coloured = groupBy (\a b -> fst a == fst b) parts
            marksOf grp = case grp of
              ((Just name, _) : _)
                | Just sw <- swatchOf (plainLook body 0) {lkColor = Just name} -> [P.Saved (P.SetColor sw : concatMap (fst . snd) grp)]
              _ -> concatMap (fst . snd) grp
         in (concatMap marksOf coloured, concatMap (snd . snd) parts)
      textAt anchor size txt =
        let w = sum [toSp size (shAdvance g) | g <- lfShape fonts (Shaping body False []) txt]
            x0 = case anAlign anchor of
              LS.AlignStart -> anX anchor
              LS.AlignCenter -> anX anchor - w `div` 2
              LS.AlignEnd -> anX anchor - w
         in runAt (plainLook body size) False False 0 (x0, anY anchor) txt
      {- one column of a page, against the rectangle of the column (docs/adr
      ADR 0018): its text, its images and its rules -}
      drawColumn p =
        let n = poNumber p
            -- the columns of the page, or of the index (docs/adr ADR 0025)
            rects = if poColumnSet p == baseSet then columnsFor geom n else columnSetRects geom n (poColumnSet p)
            ta = case drop (poColumn p) rects of
              (c : _) -> c
              [] -> typeAreaFor geom n
            lineParts =
              [drawLine ta (gridAt slot) sl | (slot, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines layout)]]
                -- the leader and page number of a table of contents entry (golem-driver ADR 0009)
                <> [ drawLine ta (gridAt slot) (SetLine l (pgFontSize geom) start [] [])
                   | (slot, SLine lid) <- poSlots p,
                     Just tp <- [Map.lookup lid (plTocPages layout)],
                     (l, start) <- [(tpLeader tp, tpLeaderStart tp), (tpNumber tp, tpNumberStart tp)]
                   ]
                <> [drawLine ta (gridAt slot) cell | (slot, SLine lid) <- poSlots p, cell <- Map.findWithDefault [] lid (plTableLines layout)]
                <> [ drawLine ta (headingLineAt slot hb j sl) sl
                   | (slot, SHeading lid m) <- poSlots p,
                     Just hb <- [Map.lookup lid (plHeadings layout)],
                     (j, Just sl) <- [(j, Map.lookup (lid + j) (plLines layout)) | j <- [0 .. m - 1]]
                   ]
                <> [ drawLine ta (captionLineAt slot pf j) (SetLine l (pfCaptionSize pf) (captionIndent ta pf) [] [])
                   | (slot, fid) <- placedFigures p,
                     Just pf <- [Map.lookup fid (plFigures layout)],
                     (j, l) <- zip [0 ..] (pfCaption pf)
                   ]
                -- the rows of code blocks (golem-driver ADR 0017)
                <> [ drawLine ta (codeRowAt slot (ciGeometry ci) k j sl) sl
                   | (slot, SCode lid k _) <- poSlots p,
                     Just ci <- [Map.lookup lid (plCodes layout)],
                     (j, Just sl) <- [(j, Map.lookup (lid + j) (plLines layout)) | j <- [0 .. k - 1]]
                   ]
            -- the backgrounds of code blocks, drawn before everything
            backMarks =
              [ P.Saved [P.SetColor sw, P.Rule (codeRect ta slot spanLines (ciStart ci))]
              | (slot, SCode lid _ spanLines) <- poSlots p,
                Just ci <- [Map.lookup lid (plCodes layout)],
                Just sw <- [ciBackground ci]
              ]
            figMarks = [P.Image (P.ImageRef fid) (figureRect geom ta slot pf) | (slot, fid) <- placedFigures p, Just pf <- [Map.lookup fid (plFigures layout)]]
            noteLines = concat [take cnt (drop from (concat [ls | sl <- Map.elems (plLines layout), (nid', ls) <- slNotes sl, nid' == nid])) | (nid, from, cnt) <- poFootnotes p]
            bottomSlots = drop (length grid - length noteLines) [0 .. length grid - 1]
            noteParts = [drawLine ta (gridAt slot) (SetLine l (pgFontSize geom) 0 [] []) | (slot, l) <- zip bottomSlots noteLines]
            ruleMarks = concat [tableRules ta seg w | seg <- poTables p, Just w <- [Map.lookup (tsTable seg) (plTables layout)]]
         in (lineParts <> noteParts, figMarks, ruleMarks, backMarks)
      -- the columns of a page, its sidenotes and, once, its running head and folio
      drawPage ps master = case ps of
        [] -> ([], [])
        (p : _) ->
          let n = poNumber p
              columns = map drawColumn ps
              masterParts = masterMarks n (poBlank p) master (join (Map.lookup n heads))
              -- the hidden folio, after everything else of the page (golem-driver ADR 0021)
              hiddenParts = hiddenMarks n
              -- sidenotes in the sidenote column of the page (golem-driver ADR 0006)
              sidenoteParts =
                [ drawLineAt (rectX area, rectY area + rectH area - (psTop ps' + toInteger j * snPitch + round (toRational snSize' * baselineRatio))) (SetLine l snSize' 0 [] [])
                | Just area <- [sidenoteAreaFor geom n],
                  ps' <- Map.findWithDefault [] n (plSidenotes layout),
                  let (_, snSize', snPitch) = sidenoteMetrics (docStyle inp (spanFile (psSpan ps'))) geom,
                  (j, l) <- zip [0 :: Int ..] (psLines ps')
                ]
              allParts = concat [t | (t, _, _, _) <- columns] <> sidenoteParts <> masterParts
           in (concat [b | (_, _, _, b) <- columns] <> concatMap fst allParts <> concat [f | (_, f, _, _) <- columns] <> concat [r | (_, _, r, _) <- columns] <> concatMap fst hiddenParts, concatMap snd (allParts <> hiddenParts))
      -- the rules of a table on a page, centred in the space between grid lines (golem-driver ADR 0008)
      tableRules ta seg w =
        let p = pgLinePitch geom
            fs = pgFontSize geom
            half = (p - fs) `div` 2
            before k = toInteger k * p - half
            after k = toInteger k * p + fs + half
            rule c t
              | vertical = P.Rule (Rect (rectX ta + rectW ta - c - t `div` 2) (rectY ta + rectH ta - w) t w)
              | otherwise = P.Rule (Rect (rectX ta) (rectY ta + rectH ta - c - t `div` 2) w t)
         in [rule (before (tsFirst seg)) thickRule, rule (after (tsHeaderEnd seg)) thinRule, rule (after (tsLast seg)) thickRule]
      {- row j of the k rows of a code block from grid line slot: the area
      starts half the leading above the grid line, and the rows are centred
      in it (golem-driver ADR 0017) -}
      codeRowAt slot g k j sl =
        let s = slSize sl
            areaTop = toInteger slot * pgLinePitch geom - (pgLinePitch geom - pgFontSize geom) `div` 2
            top = areaTop + codeRowsTop g k + toInteger j * cgPitch g
         in top + (if vertical then s `div` 2 else round (toRational s * baselineRatio))
      -- the area of a code block of n grid lines from grid line slot, from start to the end of the line
      codeRect ta slot n start =
        let p = pgLinePitch geom
            areaTop = toInteger slot * p - (p - pgFontSize geom) `div` 2
            across = toInteger n * p
            measure = if vertical then rectH ta else rectW ta
         in if vertical
              then Rect (rectX ta + rectW ta - areaTop - across) (rectY ta + rectH ta - measure) across (measure - start)
              else Rect (rectX ta + start) (rectY ta + rectH ta - areaTop - across) (measure - start) across
      -- line j of a heading block from grid line k (golem-driver ADR 0003)
      headingLineAt k hb j sl =
        let s = slSize sl
            top = toInteger k * pgLinePitch geom + hbOffset hb + toInteger j * hbPitch hb
         in top + (if vertical then s `div` 2 else round (toRational s * baselineRatio))
      placedFigures p = [(slot, fid) | (slot, s) <- poSlots p, fid <- case s of SFigure f -> [f]; SWrapped f -> [f]; _ -> []]
      {- line j of a caption: from the top of the grid line after the image,
      j caption pitches on, at the top of its lines (golem-driver ADR 0010) -}
      captionLineAt slot pf j =
        let cs = pfCaptionSize pf
            top = toInteger (slot + pfImageLines pf) * pgLinePitch geom + toInteger (j :: Int) * pfCaptionPitch pf
         in top + (if vertical then cs `div` 2 else round (toRational cs * baselineRatio))
      -- caption lines start where the image starts (golem-driver ADR 0005)
      captionIndent ta pf
        | pfWrap pf == Just WrapEnd = (if vertical then rectH ta else rectW ta) - pfAlong pf
        | otherwise = 0
      -- each digit of a hidden folio, its advance centred on its point (golem-driver ADR 0021)
      hidden = hiddenFolios inp geom layout
      hiddenMarks n =
        [ runAt (plainLook body size) False False 0 (cx - w `div` 2, cy + size `div` 2 - round (toRational size * baselineRatio)) txt
        | Just hg <- [pgHiddenFolio geom],
          let size = hgSize hg,
          (c, (cx, cy)) <- Map.findWithDefault [] n hidden,
          let txt = T.singleton c
              w = sum [toSp size (shAdvance g) | g <- lfShape fonts (Shaping body False []) txt]
        ]
      masterMarks n blank master heading = case master of
        Nothing -> []
        Just m ->
          let pick a1 a2 = if odd n then a1 else a2
              size = pgFontSize geom
              folio = [textAt (pick a1 a2) size (formatNumber fmt [toInteger n] Nothing) | drawsFolio blank master, Just (fmt, a1, a2) <- [mgFolio m]]
              runningHead = [textAt (pick a1 a2) size h | not blank, Just (_, _, a1, a2) <- [mgRunningHead m], Just h <- [heading]]
           in runningHead <> folio
      -- the columns of a page come together from 'paginate' (docs/adr ADR 0018)
      drawn = zipWith drawPage (pagesOf (plPages layout)) masters
      -- the bleed and the crop marks around each page (golem-pdf ADR 0004)
      bleed = maybe 0 pageBleed (stPage style)
      pdfPages = [P.framePage (piMarks inp) bleed (pw, ph) marks | (marks, _) <- drawn]
      -- each glyph once per font, with the text of its first occurrence (golem-font ADR 0002)
      used = Map.map Map.toList (Map.fromListWith (Map.unionWith (\_ old -> old)) [(r, Map.singleton g t) | (_, us) <- reverse drawn, (r, g, t) <- reverse us])
      fontsUsed = Map.fromList [(r, lfEmbed fonts ix (odd k) gts) | (r@(P.FontRef k), gts) <- Map.toList used, let ix = k `div` 2]
      programs = [case P.fontProgram f of P.TrueTypeProgram b -> b; P.CffProgram b -> b; P.OpenTypeProgram b -> b | f <- Map.elems fontsUsed]
      (y, mo, d) = toGregorian (mdDate md)
      doc =
        P.Document
          { P.docPages = pdfPages,
            P.docFonts = fontsUsed,
            P.docImages = Map.fromList [(P.ImageRef i, pfImage pf) | (i, pf) <- Map.toList (plFigures layout)],
            P.docTitle = mdTitle md,
            P.docDate = (y, mo, d),
            P.docId = P.documentId (mdId md),
            P.docInstanceId = P.instanceId (instanceIdInputs (piInputs inp) programs),
            P.docProducer = producer,
            P.docPdfX = intent
          }
   in P.writePdf doc
