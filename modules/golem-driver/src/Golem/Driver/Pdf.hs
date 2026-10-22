{-# LANGUAGE MultiWayIf #-}

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
    ClusterPart (..),
    GlyphFrame (..),
    offsetOrigin,
    Shaping (..),
    shapingOf,
    noFontProvider,
    bodyRole,
    bodyFontDiagnostics,
    usedRoles,
    bookHasCode,
    codeStyles,
    codeFontNotice,
    kentenRubyNotices,
    syntheticStroke,
    headingDefaults,
    syntheticStrokeJa,
    syntheticStrokeLatin,
    styleFileId,
    PdfInput (..),
    SetLine (..),
    CodeInfo (..),
    PlacedFigure (..),
    PlacedSidenote (..),
    PdfLayout (..),
    TableGeometry (..),
    sidenoteDiagnostics,
    styleLayoutDiagnostics,
    listNumberDiagnostics,
    placePageSidenotes,
    layoutPdf,
    layoutPages,
    indexLines,
    bibliographyLines,
    pdfXPeople,
    Assumed (..),
    fixpoint,
    labelSpans,
    TocGeometry (..),
    TocPage (..),
    tocPage,
    headingPages,
    headingsOnPages,
    numberedTitle,
    runningHeadLines,
    runningHeads,
    runningMetadata,
    runningHeadNotices,
    hiddenFolios,
    drawsFolio,
    figureRect,
    fitFigure,
    renderPdf,
    renderPdfView,
    flowLines,
    pdfFileName,
    instanceIdInputs,
    producer,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (evaluate)
import Control.Monad (join, mfilter)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAlphaNum, isAscii, isSpace)
import Data.Either (fromRight, isLeft, lefts)
import Data.Foldable (toList)
import Data.Function (on)
import Data.Int (Int64)
import Data.List (groupBy, intercalate, mapAccumL, nub, nubBy, sortOn, zip3, zip4)
import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (toGregorian)
import Golem.Doc.Assemble
import Golem.Doc.Bibliography (EntryPart (..))
import Golem.Doc.IR
import Golem.Doc.ListMarkers
import Golem.Doc.Numbering (numberSeparator)
import Golem.Doc.Numerals (circled, formatNumber)
import Golem.Driver.Overhang (kentenAcross, lineOverhang, reachesBackground, rubyAcross)
import Golem.Driver.RuleShape (ruleMarks, ruleShapes, ruleThinnest)
import Golem.Driver.Svg (svgDrawing, unsupportedMessage)
import Golem.Driver.TextLayer (ClusterPart (..), actualTextOf, toUnicodeOf)
import Golem.Driver.Version (golemVersion)
import Golem.Html (codeTokens)
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
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Layout.Sidenotes (SidenoteError (..), placeSidenotes)
import Golem.Layout.Table (SetCell (..), SetTable (..), TableError (..), layoutTable)
import Golem.Layout.Wrap (Exclusion (..), exclusion, wrappedLineWidth)
import Golem.LayoutSpec (Anchor (..), HiddenFolioGeometry (..), MasterGeometry (..), PageGeometry (..), Rect (..), Side (..), baselineRatio, columnsFor, gutterSide, pageGeometry, runningHeadBaselines, sidenoteAreaFor, typeAreaFor)
import Golem.LayoutSpec qualified as LS
import Golem.Pdf qualified as P
import Golem.Preflight.View qualified as V
import Golem.Project
import Golem.Project.Paths (PathError (..), pathErrorMessage, resolveInRoot)
import Golem.Project.Style
import Golem.Svg qualified as S
import Golem.Syntax
import Numeric (showHex)
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
    vertical use, with the glyphs used and their text; IO, since the
    subset is made as the PDF is written (docs/adr ADR 0034); a font that
    cannot be embedded is a diagnostic (G0818, golem-pdf ADR 0011)
    -} lfEmbed :: Int -> Bool -> [(Int, Text)] -> IO (Either Diagnostic P.Font),
    {- | the height of the centre of the ideographic em box above the
    baseline of a face number, in em (golem-driver ADR 0015)
    -} lfEmBoxCentral :: Int -> Rational,
    {- | the path of the file of a face number and its form, @cff@ or
    @truetype@ (golem-cli ADR 0006)
    -} lfFaceFile :: Int -> (FilePath, Text),
    {- | the ink box of a glyph of a face number: xMin, yMin, xMax, yMax in
    em (golem-driver ADR 0019)
    -} lfInkBox :: Int -> Int -> Maybe (Rational, Rational, Rational, Rational)
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
    shCluster :: !Int,
    {- | the GPOS offset (x, y) in em, in the coordinates of the direction the
    glyph is drawn in, y up (golem-driver ADR 0020)
    -} shOffset :: !(Rational, Rational),
    -- | which glyph of its cluster the glyph is, for ToUnicode (golem-driver ADR 0030)
    shPart :: !ClusterPart
  }
  deriving stock (Eq, Show)

-- | How a glyph is drawn, for its offset (golem-driver ADR 0020).
data GlyphFrame
  = -- | horizontal, with the horizontal scale of a scaled run (0 for none)
    FrameHorizontal !Int
  | -- | upright in vertical text
    FrameUpright
  | -- | turned 90° clockwise in vertical text
    FrameTurned
  deriving stock (Eq, Show)

-- | The origin of a glyph moved by its offset at a size (golem-driver ADR 0020).
offsetOrigin :: Integer -> GlyphFrame -> (Rational, Rational) -> (Integer, Integer) -> (Integer, Integer)
offsetOrigin size frame (dx, dy) (gx, gy) = case frame of
  FrameHorizontal scale -> (gx + sp (dx * toRational (1000 + scale) / 1000), gy + sp dy)
  FrameUpright -> (gx + sp dx, gy + sp dy)
  FrameTurned -> (gx + sp dy, gy - sp dx)
  where
    sp a = round (a * toRational size)

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
    piBibliography :: !(Map Text [EntryPart]),
    -- | the crop marks (golem-pdf ADR 0004)
    piMarks :: !(Maybe P.MarkStyle),
    -- | the styles each file defines (docs/adr ADR 0014)
    piLocalStyles :: !(Map FileId LocalStyles),
    -- | the master page of each chapter file that names one (golem-driver ADR 0014)
    piMasters :: !(Map FileId Text),
    {- | where diagnostics about style.toml point: style.toml, or the
    manifest without one (golem-driver ADR 0016)
    -} piStyleFile :: !FileId,
    {- | the variables of each chapter file that its running heads show,
    as text, by their names with the namespace (golem-driver ADR 0022)
    -} piRunningVars :: !(Map FileId (Map [Text] Text))
  }

-- | The language of the book, [metadata] language (golem-html ADR 0002).
bookLanguage :: PdfInput -> Text
bookLanguage = mdLanguage . manifestMetadata . projectManifest . piProject

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

{- | The glyphs of a kenten mark (golem-driver ADR 0019): the character of
the shape in the Japanese face of a role, in the direction of the text.
-}
kentenShaped :: LoadedFonts -> Bool -> Text -> KentenShape -> [Shaped]
kentenShaped fonts vertical role shape = lfShape fonts (Shaping role vertical []) (T.singleton (kentenChar shape))

{- | G0809 (golem-driver ADR 0019): a role whose Japanese face has no glyph
for a kenten shape used in it, once for each role and shape, at the top
of @fid@.
-}
kentenGlyphDiagnostics :: FileId -> Bool -> LoadedFonts -> PdfLayout -> [Diagnostic]
kentenGlyphDiagnostics fid vertical fonts layout =
  [ diagnostic "G0809" Error (mkSpan fid 0 0) ("役割 " <> role <> " の和文の書体に圏点の形 " <> kentenShapeName shape <> " の字（U+" <> codePoint (kentenChar shape) <> "）がありません")
  | (role, shape) <- Set.toAscList (Set.fromList [(lkFace (bcLook c), shape) | l <- layoutLines layout, Box _ c <- lineItems l, boxKind c == KindKenten, Just shape <- [lkKenten (bcLook c)]]),
    let gs = kentenShaped fonts vertical role shape,
    null gs || any ((== 0) . shGlyph) gs
  ]
  where
    codePoint ch = T.justifyRight 4 '0' (T.toUpper (T.pack (showHex (fromEnum ch) "")))

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

{- | G0745 (golem-driver ADR 0019): kenten in the base of a ruby, at the
kenten, and ruby in kenten, at the ruby. The PDF draws no kenten there;
HTML and EPUB draw both.
-}
kentenRubyNotices :: Book -> [Diagnostic]
kentenRubyNotices book =
  [ notice "G0745" sp "ルビの親文字の圏点は PDF では描きません"
  | Document _ bs <- bookDocs book,
    is <- concatMap blockInlineLists bs,
    sp <- concatMap (sites False) is
  ]
  where
    -- ruby inside kenten, and kenten in the bases of a ruby
    sites :: Bool -> Inline -> [SrcSpan]
    sites inKenten = \case
      Kenten _ _ xs -> concatMap (sites True) xs
      Ruby sp _ segs -> [sp | inKenten] <> concat [concatMap kentenIn b | RubySegment b _ <- segs]
      Color _ _ xs -> concatMap (sites inKenten) xs
      CharStyle _ _ xs -> concatMap (sites inKenten) xs
      Note _ _ xs -> concatMap (sites False) xs
      Sidenote _ _ xs -> concatMap (sites False) xs
      _ -> []
    -- the outermost kenten in a base
    kentenIn :: InlineF r -> [SrcSpan]
    kentenIn = \case
      Kenten sp _ _ -> [sp]
      Color _ _ xs -> concatMap kentenIn xs
      CharStyle _ _ xs -> concatMap kentenIn xs
      _ -> []

-- | Every list of inlines of a block, captions and nested blocks included.
blockInlineLists :: Block -> [[Inline]]
blockInlineLists (Block _ _ body) = case body of
  Paragraph _ is -> [is]
  Heading _ _ is -> [is]
  BulletList items -> concatMap (concatMap blockInlineLists . itemBlocks) items
  OrderedList items -> concatMap (concatMap blockInlineLists . itemBlocks) items
  DefList gs -> concat [dgTerms g <> concatMap (concatMap blockInlineLists) (dgDefs g) | g <- gs]
  Table _ h rows -> h <> concat rows
  FigureBlock fig -> concatMap blockInlineLists (figCaption fig)
  _ -> []

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
              lkCode = lkCode lk || code,
              -- the background and the padding of inline code; zw is the size of the style (golem-driver ADR 0029)
              lkBackground = if code then charStyleBackground style name else lkBackground lk,
              lkPadding = if code then maybe 0 (max 0 . dimToSp size) (csPadding cs) else lkPadding lk,
              -- a URL breaks as code, after the last slash of a run (golem-doc ADR 0005)
              lkUrl = lkUrl lk || isUrlCharStyle style name
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

{- | The role and size of the headings of a level (golem-driver ADR 0003):
the size of the book's language by default (golem-driver ADR 0032).
-}
headingFace :: Text -> Style -> PageGeometry -> Int -> (Text, Sp)
headingFace lang style geom level =
  let hs = Map.lookup level (stHeadings style)
   in faceFor style geom (hs >>= hsFont) (Just (fromMaybe (fst (headingDefaults lang level)) (hs >>= hsSize)))

{- | The least grid lines the headings of a level take: @lines@ of
style.toml, or the default of the book's language cut to the grid lines
of a page (golem-driver ADR 0032).
-}
headingLines :: Text -> Style -> Int -> Int -> Int
headingLines lang style capacity level =
  fromMaybe (min capacity (snd (headingDefaults lang level))) (Map.lookup level (stHeadings style) >>= hsLines)

{- | The default size and least grid lines of a heading by the book's
language and the level (golem-driver ADR 0032): a book whose language
starts with ja takes fewer lines, its pitch being farther from its size.
-}
headingDefaults :: Text -> Int -> (Dim, Int)
headingDefaults lang level = case level of
  1 -> (Zw (3 % 2), if ja then 5 else 6)
  2 -> (Zw (5 % 4), if ja then 3 else 4)
  3 -> (Zw 1, 2)
  _ -> (Zw 1, 1)
  where
    ja = "ja" `T.isPrefixOf` T.toLower lang

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
    -- | the notices of the layout (G0730)
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
    -- | errors found while building (G0722, G0723, G0724, G0741, G0742)
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
    -- | notices (G0730)
    bNotices :: [Diagnostic],
    -- | the block of each unit by the id of its first line (golem-cli ADR 0006)
    bLineSpans :: Map Int SrcSpan,
    -- | the rules of each ruled block by its first line (golem-driver ADR 0027)
    bRules :: Map Int RuledInfo
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
renderPdf provider inp = fmap (\(bytes, notices, _) -> (bytes, notices)) <$> renderPdfView provider inp

{- | 'renderPdf' with the view of the PDF that golem preflight checks
(golem-cli ADR 0006). The view is lazy: golem build never forces it.
-}
renderPdfView :: FontProvider -> PdfInput -> IO (Either [Diagnostic] (ByteString, [Diagnostic], V.View))
renderPdfView provider inp0 = case checkedGeometry inp of
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
          Right intent -> do
            laid <- layoutPdf inp geom fonts
            -- a kenten shape the font has no glyph for stops the PDF (G0809, golem-driver ADR 0019)
            case laid of
              Left ds -> pure (Left ds)
              Right layout -> case kentenGlyphDiagnostics (piStyleFile inp) (pgVertical geom) fonts layout of
                [] -> do
                  let (used, finish) = writeDocumentView inp geom fonts layout intent
                  -- the fonts are subset and embedded here, at the writing edge (docs/adr ADR 0034)
                  embedded <- Map.traverseWithKey (\(P.FontRef k) gts -> lfEmbed fonts (k `div` 2) (odd k) gts) used
                  -- a face used horizontally and vertically is reported once
                  case nub (lefts (Map.elems embedded)) of
                    [] -> do
                      let (bytes, view) = finish (Map.mapMaybe (either (const Nothing) Just) embedded)
                      pure (Right (bytes, plNotices layout <> runningHeadNotices inp geom fonts layout, view))
                    ds -> pure (Left ds)
                ds -> pure (Left ds)
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
          -- a figure that cannot be placed stops the PDF (G0810, golem-pdf ADR 0008)
          case figureDiagnostics inp loaded of
            ds@(_ : _) -> pure (Left ds)
            [] -> layoutFigures inp geom fonts (Map.mapMaybe (either (const Nothing) Just) loaded)

-- | 'layoutPdf' with the figures read.
layoutFigures :: PdfInput -> PageGeometry -> LoadedFonts -> Map (Text, Int) P.FigureContent -> IO (Either [Diagnostic] PdfLayout)
layoutFigures inp geom fonts figures = do
  -- S2: compose with assumed page numbers until they settle
  -- the names of the marks for G0721: the terms of the index, the bodies of the entries of channels (golem-doc ADR 0007)
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
          tocPages = Map.fromList [(lid, tocPage tg e (pageNumberLine env n)) | (lid, (hs, e)) <- Map.toList (bTocLines built), Just n <- [Map.lookup hs hPages]]
       in case concat [ds | (_, Left ds) <- placed] of
            [] -> Right (PdfLayout pages (bLines built) (bFigures built) (bHeadings built) (Map.fromList [(n, ps) | (n, Right ps@(_ : _)) <- placed]) (bTableLines built) (bTables built) tocPages (bLineFiles built) (bHeadingSpans built) (bCodes built) (bNotices built <> ruledNotices (bFlow built) (bRules built) pages <> unmetWarnings pages) (bLineSpans built) (bRules built))
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
        | pgVertical geom = all (\r -> rectX r + rectW r - at k - fs `div` 2 >= 0) areas
        | otherwise = all (\r -> rectY r + rectH r - at k - (fs - round (toRational fs * baselineRatio)) >= 0) areas
   in n + length (takeWhile inside [n .. n + 999])

{- | The position of grid line @k@ from the type area, past its last line
too (docs/adr ADR 0030).
-}
gridLine :: PageGeometry -> Int -> Sp
gridLine geom k = case (drop k grid, grid) of
  (g : _, _) -> g
  (_, g0 : _) -> g0 + toInteger k * pgLinePitch geom
  _ -> toInteger k * pgLinePitch geom
  where
    grid = pgLineGrid geom

{- | G0737: the manual controls of page breaks not met (docs/adr ADR
0030); G0747: the blank lines dropped (docs/adr ADR 0046).
-}
unmetWarnings :: [PageOut] -> [Diagnostic]
unmetWarnings pages =
  [ case u of
      UnmetNoBreak sp -> diagnostic "G0737" Warning sp "ここで改ページを止められませんでした"
      UnmetNeedLines sp k -> diagnostic "G0737" Warning sp ("@need-lines " <> T.pack (show k) <> " は段の行数 " <> T.pack (show (poLines p)) <> " を超えます")
      UnmetAdjust sp k -> diagnostic "G0737" Warning sp ("@page-lines の増減を " <> T.pack (show k) <> " 行に切り詰めました")
      -- G0747: blank lines dropped at the top of a column (docs/adr ADR 0046)
      DroppedBlank sp -> notice "G0747" sp "段の先頭に来た @blank-line の空きを捨てました"
  | p <- pages,
    u <- poUnmet p
  ]

{- | G0746 (golem-driver ADR 0027): a ruled paragraph broken between
columns, or a ruled heading that lost a rule, because an empty column
could not hold its block.
-}
ruledNotices :: [Flow] -> Map Int RuledInfo -> [PageOut] -> [Diagnostic]
ruledNotices flow infos pages =
  [ if riHeading info
      then notice "G0746" (riSpan info) ("罫線を持つ見出しが版面に入らないため、罫線を省きました（" <> riOwner info <> "）")
      else notice "G0746" (riSpan info) ("罫線を持つ段落が版面に入らないため、罫線を省いて分けて組みました（" <> riOwner info <> "）")
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

{- | G0751 (golem-driver ADR 0022): a line of a running head wider than the
type area of its page, once for each text, at the top of style.toml. The
line is drawn as it is, out into the margin.
-}
runningHeadNotices :: PdfInput -> PageGeometry -> LoadedFonts -> PdfLayout -> [Diagnostic]
runningHeadNotices inp geom fonts layout =
  [ diagnostic "G0751" Warning (mkSpan (piStyleFile inp) 0 0) ("柱の行が版面の幅を超えています（" <> T.pack (show n) <> " ページ）: " <> t)
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
plainWidth fonts role size txt = sum [round (shAdvance g * toRational size) | g <- lfShape fonts (Shaping role False []) txt]

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
      leader = Line [Box u (BoxContent "…" False 0 0 (fromEnum KindText) (tgLook tg) 0 0 [] 0 0) | _ <- [1 .. k]] 0 (k * u) 0 (0, 0) False (0, 0)
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
withNoteMark :: Text -> Int -> [Inline] -> [Inline]
withNoteMark format n body = Text sp (noteMarkText format n) : Aki sp (AkiZw (1 / 4)) : body
  where
    sp = mkSpan (FileId 0) 0 0

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
    uRules :: (Maybe RuleSpec, Maybe RuleSpec)
  }

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
unitsOf :: Text -> Book -> PageGeometry -> Maybe ColumnSet -> (FileId -> Style) -> (SrcSpan -> Maybe Integer) -> Map Text [EntryPart] -> [Unit]
unitsOf lang book geom indexSet styleOf pageOf bib = concat (snd (mapAccumL chapter 0 (bookChapters book)))
  where
    sp0 = mkSpan (FileId 0) 0 0
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
         in Unit (UNotesTitle title) Nothing [Text sp0 title] sp (uncurry (styleLook style Nothing) (headingFace lang style geom 2)) style [] Nothing Nothing (Nothing, Nothing)
              : [Unit (UPara noIndent) Nothing (withNoteMark (stNotesMarkFormat style) n xs) nsp (bodyLook style fs) style [] Nothing Nothing (Nothing, Nothing) | (nsp, n, xs) <- ns]
    {- a list of blocks inside the lists @ctx@, from the list number @n@:
    paragraphs of the same style in a row are apart by its space-between
    (docs/adr ADR 0005); in a list item, paragraphs are not indented by
    their style (docs/adr ADR 0006) but by the lists (golem-driver ADR 0013) -}
    blocks style ctx n bs =
      let (n', uss) = mapAccumL (\k (prev, b) -> (gapBefore style ctx prev b <>) <$> block style ctx k b) n (zip (scanl before Nothing bs) bs)
       in (n', concat uss)
    gapBefore style ctx (Just (Block _ _ (Paragraph s1 _))) (Block sp _ (Paragraph s2 _))
      | s1 == s2, Just g <- paraStyle style s2 >>= psSpaceBetween, g > 0 = [Unit (UGap g) Nothing [] sp (bodyLook style fs) style ctx Nothing Nothing (Nothing, Nothing)]
    gapBefore _ _ _ _ = []
    -- the block before, past the controls of page breaks (docs/adr ADR 0030)
    before prev b = case blockBody b of
      PageControl _ -> prev
      _ -> Just b
    block style ctx n (Block sp lbl body) =
      let unit kind l is face = Unit kind l is sp face style ctx Nothing Nothing (Nothing, Nothing)
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
                  -- a paragraph in a list has no rules (golem-driver ADR 0027)
                  (rb, ra) = if null ctx then paraRules style st else (Nothing, Nothing)
                  rulesOf i = (if i == 0 then rb else Nothing, if i == length parts - 1 then ra else Nothing)
               in (n, [(unit (UPara (if null ctx then ind else noIndent)) (if i == 0 then lbl else Nothing) part face) {uParaStyle = st, uRules = rulesOf i} | (i, part) <- zip [0 :: Int ..] parts])
            Heading l attrs is ->
              let num = Map.lookup sp (bookHeadings book) >>= hiNumberText
                  title = numberedTitle lang sp0 (if haNoNumber attrs then Nothing else num) is
                  recto = maybe False hsRectoBreak (Map.lookup l (stHeadings style))
                  rules = maybe (Nothing, Nothing) (\h -> (hsRuleBefore h, hsRuleAfter h)) (Map.lookup l (stHeadings style))
               in (n, [(unit (UHeading l (T.concat (map inlineText is)) recto) lbl title (uncurry (styleLook style Nothing) (headingFace lang style geom l))) {uRules = rules}])
            BulletList items -> list style ctx n (map (Nothing,) items)
            OrderedList items -> list style ctx n (zip (map Just (itemNumbers items)) items)
            DefList gs ->
              let group k g = ([plainUnit (UTerm noIndent) Nothing t | t <- dgTerms g] <>) <$> blocksOf k (dgDefs g)
                  blocksOf k ds = let (k', dss) = mapAccumL (blocks style ctx) k ds in (k', concat dss)
                  (n', uss) = mapAccumL group n gs
               in (n', concat uss)
            Table aligns h rows -> (n, [plainUnit (UTable aligns h rows) lbl []])
            -- always in the paragraph style code (golem-driver ADR 0017)
            CodeBlock code -> (n, [unit (UCode 0 code) lbl [] (codeLook style geom)])
            FigureBlock fig -> (n, [plainUnit (UFigure fig) lbl []])
            -- the index marks of a title are counted at the heading, not in the table of contents
            ChannelOutput (TocOutput depth) -> (n, [plainUnit (UTocEntry (teLevel e) (teSpan e)) Nothing (numberedTitle lang sp0 (teNumber e) (filter (not . isMark) (teTitle e))) | e <- bookToc book, teLevel e <= depth])
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
               in (n, [(unit (UPara (if null ctx then ind else noIndent)) Nothing is face) {uParaStyle = st} | is <- channelLines (pgVertical geom) pageOf locators (channelAt book sp)])
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
      tocIndent l = toInteger (l - 1) * fs
      -- a mark without an assumed page yet stands at page 1 in the first round
      markPage sp = Map.lookup sp (asMarks assumed) <|> (if Map.null (asMarks assumed) then Just 1 else Nothing)
      rawUnits = unitsOf (bookLanguage inp) (piBook inp) geom (indexColumnSet style geom) (docStyle inp) markPage (piBibliography inp)
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
           in boxes <> [Box (innerOf u - w) (BoxContent "" False 0 0 (fromEnum KindText) (ceLook env) 0 0 [] 0 0)]
      compose lineWidth u =
        let env = (styledEnv (uStyle u) (envFor (uLook u))) {ceAkiSet = akiSetOf (uStyle u) (uParaStyle u)}
            bodyEnv' = (styledEnv (uStyle u) (envFor (bodyLook (uStyle u) fs))) {ceAkiSet = akiSetOf (uStyle u) Nothing}
            marker = markerItems env u
            -- the anchors count the items of the text; the marker comes first
            shift = length marker
            (textItems, anchors) = composeInlines env (uInlines u)
            items = marker <> textItems
            lines' = brLines (breakParagraph params lineWidth items)
            -- notes at the end of the chapter are paragraphs of their own (golem-driver ADR 0026)
            notes = [(k, brLines (breakParagraph params (const measure) (fst (composeInlines bodyEnv' (withNoteMark (stNotesMarkFormat (uStyle u)) n nbody))))) | not atEnd, (_, k, n, nbody) <- noteAnchors anchors]
            sidenotes = [(i + shift, sp, sidenoteLines (uStyle u) n snBody) | AnchorSidenote i n sp snBody <- anchors]
            marks =
              [(i + shift, sp) | AnchorIndex i sp _ <- anchors]
                <> [(i + shift, sp) | not atEnd, AnchorNote i _ _ nbody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines bodyEnv' nbody)]
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
            (captionItems, captionAnchors) = composeInlines ((styledEnv (uStyle u) (envFor (styleLook (uStyle u) (Just "caption") captionRole cs))) {ceAkiSet = akiSetOf (uStyle u) (Just "caption")}) captionInlines
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
              Just _ -> (alongSp, floor (fromInteger alongSp * ratio), False)
            m = fromInteger ((across + pitch - 1) `div` pitch)
            -- the size the figure would take turned, to tell the writer (golem-driver ADR 0034)
            turnedArea =
              let s = snd (captionSpanOf (length (captionAt frameAlong)))
                  (a, c, _) = fitOf frameAlong frameLines s
               in if s >= frameLines then 0 else a * c
            hint = if not turned && turnedArea > alongFit * across then "。rotate=true で回して一ページに置くと、より大きく置けます" else ""
            place' = if turned then "ページ" else "段"
            tooDeep = isNothing (figWrap fig) && n > 0 && span' >= gridLines
            notices =
              [ notice "G0739" (uSpan u) ("図版を" <> place' <> "に収めるため " <> T.pack (show (alongFit * 100 `div` max 1 alongSp)) <> "% に縮めました" <> hint)
              | fitted,
                not tooDeep
              ]
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
              -- a caption that leaves no line for the image (golem-driver ADR 0034)
              _
                | tooDeep -> [diagnostic "G0738" Error (uSpan u) ("図版のキャプションが" <> place' <> "の行数を超えます（" <> T.pack (show span') <> " 行。" <> place' <> "は " <> T.pack (show gridLines) <> " 行）")]
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
      frameLines = fromInteger (max 0 (frameAcross - fs) `div` pitch) + 1
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
            noteBody n b = brLines (breakParagraph params (const measure) (fst (composeInlines env (withNoteMark (stNotesMarkFormat style) n b))))
            marksIn b = [sp | AnchorIndex _ sp _ <- snd (composeInlines env b)]
         in ( Map.fromListWith (flip (<>)) [(lineOf i, [(k, noteBody n b)]) | not atEnd, (i, k, n, b) <- noteAnchors anchors],
              Map.fromListWith (flip (<>)) [(lineOf i, [(sp, sidenoteLines st n b)]) | AnchorSidenote i n sp b <- anchors],
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
        f@FCode {} : rest -> case infos of
          ci : more -> f : [FSpace 1 | painted ci, reaches ci rest] <> spaceAfterCode more rest
          [] -> f : spaceAfterCode [] rest
        f : rest -> f : spaceAfterCode infos rest
        [] -> []
        where
          painted ci = isJust (ciBackground ci) || not (null (ciBands ci)) || isJust (ciBorder ci)
          reaches ci rest = case rest of
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
              let flow = case c of
                    NoBreak -> FNoBreak (uSpan u)
                    NeedLines k -> FNeedLines (uSpan u) k
                    AdjustLines k -> FAdjustLines (uSpan u) k
               in (nextId, flows <> [flow], lineAcc, figAcc, headAcc, errs)
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
                    UHeading l short _ ->
                      ( Map.insert nextId hb headAcc,
                        errs <> [diagnostic "G0724" Error (uSpan u) ("見出しが版面に入りません（" <> T.pack (show l) <> " の見出し: " <> short <> "）") | hbSpan hb > capacity]
                      )
                    -- the title of the notes is in neither the headings nor the running heads (golem-driver ADR 0026)
                    UNotesTitle title ->
                      ( Map.insert nextId hb headAcc,
                        errs <> [diagnostic "G0724" Error (uSpan u) ("見出しが版面に入りません（注の一覧の見出し: " <> title <> "）") | hbSpan hb > capacity]
                      )
                    _ -> (headAcc, errs)
               in (nextId + length ls, flows <> flowOf, Map.union lineAcc set, figAcc, headAcc', errs')
      -- code blocks, set line by line (golem-driver ADR 0017)
      codeBlocks = Map.fromList [(i, codeBlockOf geom fonts measure capacity u lead code (codeCaptionOf u lead code)) | (i, u@Unit {uKind = UCode lead code}) <- units]
      {- the caption of a code block: the listing number, an ideographic
      space and the caption, set as the caption of a figure over the width of
      the block (golem-driver ADR 0023) -}
      codeCaptionOf u lead code = case codeCaption code of
        Nothing -> CodeCaption [] fs pitch 0 []
        Just is ->
          let number = Map.lookup (uSpan u) (bookListings (piBook inp))
              captionInlines = maybe [] (\num -> [Text (uSpan u) (num <> "　")]) number <> is
              (captionRole, cs) = paraFace (uStyle u) geom "caption"
              captionParams = params {pEmergencyStretch = dimToSp cs (compEmergencyStretch (stComposition style))}
              (captionItems, captionAnchors) = composeInlines ((styledEnv (uStyle u) (envFor (styleLook (uStyle u) (Just "caption") captionRole cs))) {ceAkiSet = akiSetOf (uStyle u) (Just "caption")}) captionInlines
              ls = brLines (breakParagraph captionParams (const (measure - lead)) captionItems)
              cb = headingBlock fs pitch cs (length ls) 1
           in CodeCaption ls cs (hbPitch cb) (if null ls then 0 else hbSpan cb) [sp | AnchorIndex _ sp _ <- captionAnchors]
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
      ruledInfoOf u = case uKind u of
        UHeading l _ _ -> uncurry (RuledInfo "見出しの罫線" ("見出し " <> T.pack (show l)) True (lkSize (uLook u))) (uRules u) (uSpan u)
        _ -> uncurry (RuledInfo "段落の罫線" ("段落スタイル " <> fromMaybe "body" (uParaStyle u)) False (lkSize (uLook u))) (uRules u) (uSpan u)
  pure (Built flow' lineMap figMap headMap errors tableLines tableWidths headingSpans tocLines lineFiles codeInfos (codeNotices <> figureNotices) lineSpans ruledInfos)

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
preflight, whose rules they are for G0746, whether it is a heading, the
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
    -- | G0743
    cbErrors :: [Diagnostic],
    -- | G0730
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
      toSp a = round (a * toRational size) :: Sp
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
      emptyBox w = Box w (BoxContent "" False 0 0 (fromEnum KindText) lk 0 0 [] 0 0)
      -- pieces at offsets from the padding: (offset, text, width, Latin, swatch)
      lineOf pieces =
        let go _ [] = []
            go x ((o, t, w, latin, col) : rest) =
              [emptyBox (o - x) | o > x]
                <> [Box w (BoxContent t False 0 0 (tagOf latin) (lookOf col) 0 0 [] 0 0)]
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
        [diagnostic "G0743" Error (uSpan u) "コードブロックの行長が足りません" | avail < 8 * size]
          <> [diagnostic "G0743" Error (uSpan u) "コードブロックの一行が一ページに収まりません" | codeSpan g (if isJust continuedLine then 2 else 1) > capacity]
      rows = fileRows <> codeRows
   in SetCode
        { cbRows = rows,
          cbSize = size,
          cbIndent = lead + pad,
          cbInfo =
            CodeInfo
              { ciGeometry = g,
                ciStart = lead,
                ciBackground = background,
                ciFirst = 0,
                ciRows = length rows,
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
          cbNotices = [notice "G0730" (uSpan u) ("コードの行を折り返しました（" <> T.pack (show wrapped) <> " 行）") | wrapped > 0]
        }

-- | Which line (0-based) contains the item at an index.
lineIndexOfItems :: [Item] -> [Line] -> Int -> Int
lineIndexOfItems _ ls i =
  let counts = scanl1 (+) (map (length . lineItems) ls)
   in length (takeWhile (<= i) counts) `min` max 0 (length ls - 1)

-- | A figure by its file and its page (1 unless a PDF figure says otherwise).
figureKey :: Figure -> (Text, Int)
figureKey f = (figSource f, fromMaybe 1 (figPage f))

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
  let across0 = floor (fromInteger along0 * ratio)
      acrossMax = max 0 $ case captionSpan of
        Just s -> toInteger (l - s) * p
        Nothing -> toInteger (l - 1) * p + fs
   in if across0 <= acrossMax then (along0, across0, False) else (floor (fromInteger acrossMax / ratio), acrossMax, True)

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

-- | Why a figure cannot be placed: G0810 with the reason, or G0811 (golem-pdf ADR 0008, 0009).
data Unplaced = Unplaced !Text | UnsupportedSvg !(NonEmpty S.Unsupported)

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
          | ".pdf" `T.isSuffixOf` T.toLower s -> either (Left . Unplaced . P.importErrorText) (Right . P.VectorFigure) (P.importPage page bytes)
          | ".svg" `T.isSuffixOf` T.toLower s -> case S.readSvg bytes of
              Left (S.SvgMalformed why) -> Left (Unplaced why)
              Left (S.SvgUnsupported us) -> Left (UnsupportedSvg us)
              Right svg -> Right (P.SvgFigure (svgDrawing svg))
          | otherwise -> either (Left . Unplaced . T.pack) (Right . P.RasterFigure) (P.readImage bytes)

-- | The @figure blocks of a book, with their spans.
figureBlocks :: Book -> [(SrcSpan, Figure)]
figureBlocks book = [(sp, f) | Document _ bs <- bookDocs book, Block sp _ (FigureBlock f) <- bs]

{- | G0810: a figure that cannot be placed in the PDF, and G0811: an SVG
figure with things outside the subset; one per @figure (golem-pdf ADR
0008, 0009).
-}
figureDiagnostics :: PdfInput -> Map (Text, Int) (Either Unplaced P.FigureContent) -> [Diagnostic]
figureDiagnostics inp loaded =
  [ case why of
      Unplaced reason -> diagnostic "G0810" Error sp ("図版を PDF に置けません: " <> figSource f <> "（" <> reason <> "）")
      UnsupportedSvg us -> diagnostic "G0811" Error sp (unsupportedMessage (figSource f) us)
  | (sp, f) <- figureBlocks (piBook inp),
    Just (Left why) <- [Map.lookup (figureKey f) loaded]
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
  let d = toInteger slot * pgLinePitch geom
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
        | otherwise = toInteger (pfImageLines pf) * pgLinePitch geom + toInteger (length (pfCaption pf) - 1) * pfCaptionPitch pf + pfCaptionSize pf
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
        pure (Right (Just (uncurry (P.PdfX bytes condition) (pdfXPeople md))))
  where
    intentMessage = \case
      Missing -> "出力インテントの ICC プロファイルがありません"
      e -> pathErrorMessage e

-- ------------------------------------------------------------------ drawing

{- | A glyph drawn: its font reference, glyph and text (for embedding),
and its face, size, swatch and role (for the view of golem preflight).
-}
data GlyphUse = GlyphUse
  { guRef :: !P.FontRef,
    guGlyph :: !Int,
    guText :: !Text,
    guFace :: !Int,
    guSize :: !Sp,
    guColor :: !(Maybe Text),
    guRole :: !Text,
    -- | which glyph of its cluster the glyph is (golem-driver ADR 0030)
    guPart :: !ClusterPart
  }

{- | A line drawn, for the view of golem preflight (golem-cli ADR 0006): what
it is, its block, its face and how far it sticks out of its measure.
-}
data LineRec = LineRec
  { lrKind :: !Text,
    lrSpan :: !SrcSpan,
    lrRect :: !(Maybe Rect),
    lrOverfull :: !(Maybe Sp),
    -- | the swatches of the backgrounds of inline code on the line (golem-driver ADR 0029)
    lrBackgrounds :: ![P.Swatch]
  }

-- | What one page draws.
data PageDrawn = PageDrawn
  { pdMarks :: [P.Mark],
    pdUses :: [GlyphUse],
    pdLines :: [(LineRec, [GlyphUse])],
    pdImages :: [(Rect, PlacedFigure)],
    pdRules :: [(Text, Rect, Sp)],
    pdBlank :: Bool,
    pdNumber :: Int,
    pdBackgrounds :: [P.Swatch]
  }

{- | The PDF and its view for golem preflight (golem-cli ADR 0006), from the
values drawn; the view costs nothing until it is used. The fonts are
embedded in IO between the two halves (docs/adr ADR 0034): the glyphs
used in each font and their text, then the PDF and its view from the
embedded fonts.
-}
writeDocumentView :: PdfInput -> PageGeometry -> LoadedFonts -> PdfLayout -> Maybe P.PdfX -> (Map P.FontRef [(Int, Text)], Map P.FontRef P.Font -> (ByteString, V.View))
writeDocumentView inp geom fonts layout intent =
  let md = manifestMetadata (projectManifest (piProject inp))
      (pw, ph) = pgPageSize geom
      vertical = pgVertical geom
      -- the master page and the running head of each page (golem-driver ADR 0014)
      masters = pageMasters inp geom layout
      heads = runningHeads inp geom layout
      grid = pgLineGrid geom
      baseSet = pageColumnSet (piStyle inp) geom
      gridAt = gridLine geom
      -- font index × direction: even refs horizontal, odd refs vertical
      ref ix v = P.FontRef (2 * ix + (if v then 1 else 0))
      toSp size a = round (a * toRational size) :: Integer
      style = piStyle inp
      body = bodyRole style
      isLatin = (== Western) . charClass
      {- the runs of a text in a look: its role and whether it is a Latin
      run; split into Latin and other runs where the two sides differ in
      role or in synthetic bold and slant (golem-driver ADR 0004, docs/adr ADR 0005);
      a combining character stays with the character before it, variation
      selectors among them (golem-pdf ADR 0006, golem-driver ADR 0036) -}
      runsOf look txt
        | lkFace look == lkLatinFace look && lkSynthetic look == lkLatinSynthetic look && not (synBold (lkSynthetic look) || synBold (lkLatinSynthetic look)) = [(lkFace look, txt, False)]
        | otherwise = [(if latin then lkLatinFace look else lkFace look, r, latin) | r <- T.groupBy (\a b -> isExtending b || isLatin a == isLatin b) txt, not (T.null r), let latin = isLatin (T.head r)]
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
                [ [(ix, g, a, t, (synSlant s, strokeOf latin s), tu, extra, o, part) | (Shaped ix g a t tu _ o part, extra) <- zip shaped (trackingAfter r shaped)]
                | (role, r, latin) <- runsOf look txt,
                  let s = syntheticOf look latin
                      shaped = lfShape fonts (shapingFor role r) r
                ]
            advs = scanl (+) 0 [toSp size a + extra | (_, _, a, _, _, _, extra, _, _) <- gs]
            -- a glyph turned in vertical text: drawn with the horizontal font (golem-driver ADR 0015)
            placed = [(ix, g, t, sb, tu && v && not rotated, off, o, part) | ((ix, g, _, t, sb, tu, _, o, part), off) <- zip gs advs]
            byFont seg = Map.fromListWith (flip (<>)) [((ix, sb, tu), [(g, t, off, o)]) | (ix, g, t, sb, tu, off, o, _) <- seg]
            marksOf seg = [mark k xs | (k, xs) <- Map.toList (byFont seg)]
            refOf ix tu = ref ix (v && not rotated && not tu)
            {- the occurrences of the clusters drawn, each with its text when the
            ToUnicode entries of its font do not give it back: such a cluster
            is drawn alone inside ActualText (golem-driver ADR 0030) -}
            occurrences = \case
              [] -> []
              x@(_, _, _, _, _, _, _, ClusterLead) : rest ->
                let (more, rest') = span (\(_, _, _, _, _, _, _, part) -> part == ClusterRest) rest
                 in (x : more) : occurrences rest'
              x : rest -> [x] : occurrences rest
            replacement occ = case occ of
              (ix, _, _, _, tu, _, _, _) : _
                | [(_, Just t)] <- actualTextOf (Map.findWithDefault Map.empty (refOf ix tu) textEntries) [(g, t', part) | (_, g, t', _, _, _, _, part) <- occ] -> Just t
              _ -> Nothing
            segments = \case
              [] -> []
              occ : rest
                | Just t <- replacement occ -> [P.ActualText t (marksOf occ)] <> segments rest
                | otherwise ->
                    let (plain, rest') = break (isJust . replacement) rest
                     in marksOf (concat (occ : plain)) <> segments rest'
            -- each glyph moved by its GPOS offset, by how it is drawn (golem-driver ADR 0020)
            frameOf turned
              | v && (rotated || turned) = FrameTurned
              | v = FrameUpright
              | otherwise = FrameHorizontal scale
            moved turned = offsetOrigin size (frameOf turned)
            at off = if v then (x0, y0 - off) else (x0 + off, y0)
            -- the baseline of a turned glyph: left of the centre line by the centre of its em box
            turnedAt ix off = (x0 - toSp size (lfEmBoxCentral fonts ix), y0 - off)
            mark (ix, (sl, stroke), turned) xs
              | sl || stroke > 0 =
                  let rs = P.RunStyle (if v then 1000 else 1000 + scale) (v && (rotated || turned)) (if sl then syntheticSlant else 0) stroke
                      pos off = if turned then turnedAt ix off else at off
                   in P.StyledGlyphRun rs (ref ix (v && not rotated && not turned)) size [(code ix g, gx, gy) | (g, _, off, o) <- xs, let (gx, gy) = moved turned o (pos off)]
              | turned = P.RotatedGlyphRun (ref ix False) size [(code ix g, gx, gy) | (g, _, off, o) <- xs, let (gx, gy) = moved turned o (turnedAt ix off)]
              | v && rotated = P.RotatedGlyphRun (ref ix False) size [(code ix g, gx, gy) | (g, _, off, o) <- xs, let (gx, gy) = moved turned o (x0, y0 - off)]
              | v = P.GlyphRun (ref ix True) size [(code ix g, gx, gy) | (g, _, off, o) <- xs, let (gx, gy) = moved turned o (x0, y0 - off)]
              | scale /= 0 = P.ScaledGlyphRun (ref ix False) size (1000 + scale) [(code ix g, gx, gy) | (g, _, off, o) <- xs, let (gx, gy) = moved turned o (x0 + off, y0)]
              | otherwise = P.GlyphRun (ref ix False) size [(code ix g, gx, gy) | (g, _, off, o) <- xs, let (gx, gy) = moved turned o (x0 + off, y0)]
            code = lfCode fonts
         in (segments (occurrences placed), [(refOf ix tu, g, t, part) | (ix, g, t, _, tu, _, _, part) <- placed])
      {- the mark of a kenten shape in a role at a size, the centre of the
      ink box of its glyph at a point (golem-driver ADR 0019): horizontal,
      in the vertical font (its glyph origin at (1/2, 0.88) em of the
      glyph, as golem-pdf writes W2), or turned -}
      kentenMark role shape d (cx, cy) =
        let place Shaped {shFace = ix, shGlyph = g, shText = t, shTurned = tu} =
              let (x0, y0, x1, y1) = fromMaybe (0, 0, 0, 0) (lfInkBox fonts ix g)
                  (mx, my) = ((x0 + x1) / 2, (y0 + y1) / 2)
                  code = lfCode fonts ix g
                  -- the mark is a cluster of one glyph; in ActualText when its entry is another text (golem-driver ADR 0030)
                  -- the use does not wait for the entries, which come from the uses of every page
                  withText r m =
                    ( case actualTextOf (Map.findWithDefault Map.empty r textEntries) [(g, t, ClusterWhole)] of
                        [(_, Just t')] -> P.ActualText t' [m]
                        _ -> m,
                      (r, g, t, ClusterWhole)
                    )
               in case (vertical, tu) of
                    (False, _) -> withText (ref ix False) (P.GlyphRun (ref ix False) d [(code, cx - toSp d mx, cy - toSp d my)])
                    (True, False) -> withText (ref ix True) (P.GlyphRun (ref ix True) d [(code, cx - toSp d (mx - 1 / 2), cy - toSp d (my - 88 / 100))])
                    -- turned 90 degrees clockwise: (x, y) of the glyph is (y, -x) on the page
                    (True, True) -> withText (ref ix False) (P.RotatedGlyphRun (ref ix False) d [(code, cx - toSp d my, cy + toSp d mx)])
         in unzip (map place (kentenShaped fonts vertical role shape))
      -- the face that sets the Japanese text of a look: that of an ideograph
      japaneseFace look = maybe 0 shFace (listToMaybe (lfShape fonts (Shaping (lkFace look) False []) "漢"))
      -- the swatch of a look, when it names one (golem-driver ADR 0004)
      swatchOf look = do
        name <- lkColor look
        Swatch (cc, cm, cy, ck) <- Map.lookup name (stSwatches style)
        pure (P.Swatch cc cm cy ck)
      -- a line at a distance across the type area: the baseline from its
      -- top edge, or the centre line from its right edge
      -- runAt with the face, size, swatch and role of each glyph, for the view (golem-cli ADR 0006)
      runAtU look v rotated scale pt txt = usesOf look (runAt look v rotated scale pt txt)
      usesOf look (ms, us) = (ms, [GlyphUse r g t (k `div` 2) (lkSize look) (lkColor look) (lkFace look) part | (r@(P.FontRef k), g, t, part) <- us])
      lineStart ta cross
        | vertical = (rectX ta + rectW ta - cross, rectY ta + rectH ta)
        | otherwise = (rectX ta, rectY ta + rectH ta - cross)
      -- a line drawn with its record for the view (golem-cli ADR 0006)
      entry kind sp ta cross = entryAt kind sp (lineStart ta cross)
      entryAt kind sp start sl = (LineRec kind sp (lineFace start sl) (overfullOf sl) (map fst (codeBackgrounds start sl)), drawLineAt start sl)
      {- the backgrounds of inline code on a line (golem-driver ADR 0029): each
      run of boxes of one swatch, with the spaces between them, from the
      start of its first box to the end of its last, across the face of the
      line; a run of code ends at a box with padding after it or before
      the next one -}
      codeBackgrounds (x0, y0) sl =
        let size = slSize sl
            boxes = [(off, w, c) | (Box w c, off) <- placeLine (slLine sl)]
            breaksBefore (_, _, p) (_, _, c) = bcPadEnd p > 0 || bcPadStart c > 0 || lkBackground (bcLook p) /= lkBackground (bcLook c)
            runs = groupWhen (\a b -> not (breaksBefore a b)) boxes
            rectOf s0 e0
              | vertical = Rect (x0 - size `div` 2) (y0 - e0) size (e0 - s0)
              | otherwise = Rect (x0 + s0) (y0 - (size - round (toRational size * baselineRatio))) (e0 - s0) size
         in [ (sw, rectOf (slIndent sl + s0) (slIndent sl + e0))
            | run@((s0, _, c) : _) <- runs,
              Just name <- [lkBackground (bcLook c)],
              Just (Swatch (cc, cm, cy, ck)) <- [Map.lookup name (stSwatches style)],
              let sw = P.Swatch cc cm cy ck
                  e0 = maximum [o + w | (o, w, _) <- run]
            ]
      -- the face of a line: from its first box to the end of its last, the height of its size
      lineFace (x0, y0) sl =
        let boxes = [(off, w) | (Box w _, off) <- placeLine (slLine sl)]
            size = slSize sl
            s0 = slIndent sl + minimum (map fst boxes)
            e0 = slIndent sl + maximum [o + w | (o, w) <- boxes]
         in if null boxes
              then Nothing
              else
                Just
                  ( if vertical
                      then Rect (x0 - size `div` 2) (y0 - e0) size (e0 - s0)
                      else Rect (x0 + s0) (y0 - (size - round (toRational size * baselineRatio))) (e0 - s0) size
                  )
      overfullOf sl =
        let l = slLine sl
            end = maximum (0 : [o + w | (Box w _, o) <- placeLine l])
         in if lineOverfull l then Just (max 0 (end - lineTarget l)) else Nothing
      styleSpan = mkSpan (piStyleFile inp) 0 0
      -- the block of a line: the unit whose first line is at or before it
      spanOfLine lid = maybe styleSpan snd (Map.lookupLE lid (plLineSpans layout))
      noteSpan nid = case [lid | (lid, sl) <- Map.toList (plLines layout), (nid', _) <- slNotes sl, nid' == nid] of
        (lid : _) -> spanOfLine lid
        [] -> styleSpan
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
                            -- each base and reading character where placeRuby puts it (golem-layout ADR 0009);
                            -- each base character in its own look (golem-layout ADR 0011)
                            let (base, reading) = T.breakOn "|" (bcText c)
                                rt = T.drop 1 reading
                                rsize = lkSize half
                                -- a base character with its combining characters is one base (golem-driver ADR 0036)
                                baseUnits = clusters base
                                baseLooks = zipWith const (bcBaseLooks c <> repeat look) baseUnits
                                advOf lk u = case T.uncons u of
                                  Just (ch, rest) | T.null rest -> toSp (lkSize lk) (lfAdvance fonts (shapingOf vertical lk ch) ch)
                                  Just (ch, _) -> toSp (lkSize lk) (lfWordAdvance fonts (shapingOf vertical lk ch) u)
                                  Nothing -> 0
                                baseAdv = zipWith advOf baseLooks baseUnits
                                readAdv = map (advOf half . T.singleton) (T.unpack rt)
                                excess = max 0 (sum readAdv - w)
                                rp = placeRuby (rubyStyleOf style (lkSize look)) (if kind == KindRuby then MonoRuby else GroupRuby) baseAdv readAdv (excess `div` 2, excess `div` 2)
                                -- the reading sits beside the largest base character
                                big = if null baseLooks then size else maximum (map lkSize baseLooks)
                                across = rubyAcross vertical big rsize
                                -- a base character of another colour than the box is drawn in its own
                                inColour lk (marks, glyphs)
                                  | lkColor lk /= lkColor look, Just sw <- swatchOf lk = ([P.Saved (P.SetColor sw : marks)], glyphs)
                                  | otherwise = (marks, glyphs)
                                placed1 = [inColour lk (runAtU lk vertical False 0 (origin (off + pos)) u) | (u, lk, pos) <- zip3 baseUnits baseLooks (rpBase rp)]
                                placed2 = [runAtU half vertical False 0 (beside (origin (off + pos)) across) (T.singleton ch) | (ch, pos) <- zip (T.unpack rt) (rpReading rp)]
                             in (concatMap fst (placed1 <> placed2), concatMap snd (placed1 <> placed2))
                      KindKenten ->
                        {- the character, and the mark of its shape, half its size, the
                        centre of its ink box beside the em box (golem-driver ADR 0019):
                        above the middle of the advance in horizontal text, right of
                        the middle of the box in vertical text -}
                        let (b1, u1) = runAtU look vertical False 0 (origin off) (bcText c)
                            d = lkSize half
                            shift = lkBaselineShift look
                            parent = lfShape fonts (shapingOf vertical look (T.head (bcText c))) (bcText c)
                            centre
                              | vertical = beside (origin (off + size `div` 2)) (shift + kentenAcross True size 0 d)
                              | otherwise =
                                  let adv = toSp size (sum (map shAdvance parent))
                                      central = maybe 0 (lfEmBoxCentral fonts . shFace) (listToMaybe parent)
                                   in beside (origin (off + adv `div` 2)) (shift + kentenAcross False size central d)
                            (b2, u2) = maybe ([], []) (\sh -> usesOf (look {lkSize = d}) (kentenMark (lkFace look) sh d centre)) (lkKenten look)
                         in (b1 <> b2, u1 <> u2)
                      KindNoteMark ->
                        {- a note mark at the mark size, aligned to the em box of the
                        text: its top in horizontal text, its right end in vertical
                        text, where it is set across as horizontal text (golem-driver ADR 0018) -}
                        let m = noteMarkSize (stNotesMarkSize style) size
                            markLook = look {lkSize = m}
                            txt = bcText c
                            central = lfEmBoxCentral fonts (japaneseFace look)
                            (ox, oy) = origin off
                            markWidth = toSp m (lfWordAdvance fonts (shapingOf False markLook (maybe '0' fst (T.uncons txt))) txt)
                         in if vertical
                              then runAtU markLook {lkBaselineShift = 0} False False 0 (ox + size `div` 2 - markWidth + lkBaselineShift look, oy - m `div` 2 - toSp m central) txt
                              else runAtU markLook False False 0 (ox, oy + toSp (size - m) (central + 1 / 2)) txt
                      -- the empty box of an [aki] draws nothing (golem-layout ADR 0012)
                      KindAki -> ([], [])
                      _ ->
                        let pre = case T.unpack (bcText c) of
                              [ch] | boxKind c == KindPunctuation -> toSp size (fst (punctSpace (charClass ch)))
                              _ -> 0
                            rotated = boxKind c == KindRotated
                            -- the glyphs of inline code after its padding (golem-driver ADR 0029)
                            (ox, oy) = origin (off + bcPadStart c - pre)
                            -- vertical glyph origins sit on the centre line; rotated Latin sits on a baseline beside it
                            pt
                              | vertical && rotated = (ox - size * 3 `div` 10, oy)
                              | otherwise = (ox, oy) -- Identity-V: the origin is the top centre of the em box
                         in runAtU look vertical rotated (if bcExpandable c then lineExpansion l else 0) pt (bcText c)
              -- a word broken at the line end gets its hyphen
              Penalty hw _ (PatternHyphen _)
                | i == lastIx && hw > 0 ->
                    let (ox, oy) = origin off
                        look = lookBefore i
                        size = lkSize look
                     in (lkColor look, runAtU look vertical vertical 0 (if vertical then (ox - size * 3 `div` 10, oy) else (ox, oy)) "-")
              _ -> (Nothing, ([], []))
            -- by the glyphs used, not the marks: the marks need the ToUnicode entries of every page (golem-driver ADR 0030)
            parts = filter (not . null . snd . snd) (zipWith (curry boxRun) [0 ..] placed)
            -- boxes of the same swatch in a row share one saved colour
            coloured = groupBy (\a b -> fst a == fst b) parts
            marksOf grp = case grp of
              ((Just name, _) : _)
                | Just sw <- swatchOf (plainLook body 0) {lkColor = Just name} -> [P.Saved (P.SetColor sw : concatMap (fst . snd) grp)]
              _ -> concatMap (fst . snd) grp
            -- the backgrounds of inline code before the text of the line (golem-driver ADR 0029)
            backs = [P.Saved [P.SetColor sw, P.Rule r] | (sw, r) <- codeBackgrounds (x0, y0) sl]
         in (backs <> concatMap marksOf coloured, concatMap (snd . snd) parts)
      textAt kind anchor size txt =
        let w = plainWidth fonts body size txt
            x0 = case anAlign anchor of
              LS.AlignStart -> anX anchor
              LS.AlignCenter -> anX anchor - w `div` 2
              LS.AlignEnd -> anX anchor - w
            face = Rect x0 (anY anchor - (size - round (toRational size * baselineRatio))) w size
         in (LineRec kind styleSpan (Just face) Nothing [], runAtU (plainLook body size) False False 0 (x0, anY anchor) txt)
      -- the lines of each footnote by its key (golem-driver ADR 0018)
      noteBodies = Map.fromList [note | sl <- Map.elems (plLines layout), note <- slNotes sl]
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
              [entry (if Map.member lid (plTocPages layout) then "目次の行" else "本文の行") (spanOfLine lid) ta (gridAt slot) sl | (slot, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines layout)]]
                -- the leader and page number of a table of contents entry (golem-driver ADR 0009)
                <> [ entry "目次の行" (spanOfLine lid) ta (gridAt slot) (SetLine l (pgFontSize geom) start [] [])
                   | (slot, SLine lid) <- poSlots p,
                     Just tp <- [Map.lookup lid (plTocPages layout)],
                     (l, start) <- [(tpLeader tp, tpLeaderStart tp), (tpNumber tp, tpNumberStart tp)]
                   ]
                <> [entry "表の行" (spanOfLine lid) ta (gridAt slot) cell | (slot, SLine lid) <- poSlots p, cell <- Map.findWithDefault [] lid (plTableLines layout)]
                <> [ entry "見出しの行" (spanOfLine lid) ta (headingLineAt slot hb j sl) sl
                   | (slot, SHeading lid m) <- poSlots p,
                     Just hb <- [Map.lookup lid (plHeadings layout)],
                     (j, Just sl) <- [(j, Map.lookup (lid + j) (plLines layout)) | j <- [0 .. m - 1]]
                   ]
                <> [ entry "キャプションの行" (pfSpan pf) ta (captionLineAt slot pf j) (SetLine l (pfCaptionSize pf) (captionIndent ta pf) [] [])
                   | (slot, fid) <- placedFigures p,
                     Just pf <- [Map.lookup fid (plFigures layout)],
                     (j, l) <- zip [0 ..] (pfCaption pf)
                   ]
                -- the rows of code blocks (golem-driver ADR 0017)
                <> [ entry "コードの行" (spanOfLine lid) ta (codeRowAt codeSlot (ciGeometry ci) k' j sl) sl
                   | (slot, SCode lid k _) <- poSlots p,
                     Just ci <- [Map.lookup lid (plCodes layout)],
                     let (_, codeSlot, k', _) = codePartOf slot lid k ci,
                     (j, Just sl) <- [(j, Map.lookup (lid + j) (plLines layout)) | j <- [0 .. k - 1]]
                   ]
                -- the text at the end of a part that continues, and the caption above the first part (golem-driver ADR 0023)
                <> [ entry "コードの行" (spanOfLine lid) ta (codeRowAt codeSlot (ciGeometry ci) k' k sl) sl
                   | (slot, SCode lid k _) <- poSlots p,
                     Just ci <- [Map.lookup lid (plCodes layout)],
                     let (_, codeSlot, k', cont) = codePartOf slot lid k ci,
                     cont,
                     Just l <- [ciContinued ci],
                     let sl = SetLine l (ciSize ci) (ciIndent ci) [] []
                   ]
                <> [ entry "キャプションの行" (spanOfLine lid) ta (codeCaptionLineAt slot ci j) (SetLine l (ciCaptionSize ci) (ciStart ci) [] [])
                   | (slot, SCode lid _ _) <- poSlots p,
                     Just ci <- [Map.lookup lid (plCodes layout)],
                     lid == ciFirst ci,
                     (j, l) <- zip [0 ..] (ciCaption ci)
                   ]
            -- the backgrounds, the bands and the borders of code blocks, drawn before everything (golem-driver ADR 0017, 0023)
            backgrounds =
              concat
                [ [(sw, P.Saved [P.SetColor sw, P.Rule rect]) | Just sw <- [ciBackground ci]]
                    <> [ (sw, P.Saved [P.SetColor sw, P.Rule (codeBand ta codeSlot (ciGeometry ci) k' (from - here) (to - from) (ciStart ci))])
                       | (r0, m, sw) <- ciBands ci,
                         let from = max r0 here
                             to = min (r0 + m) (here + k),
                         to > from
                       ]
                    <> [(sw, P.Saved (P.SetColor sw : map P.Rule (borderRects rect w))) | Just (sw, w) <- [ciBorder ci]]
                | (slot, SCode lid k spanLines) <- poSlots p,
                  Just ci <- [Map.lookup lid (plCodes layout)],
                  let (isFirst, codeSlot, k', _) = codePartOf slot lid k ci
                      here = lid - ciFirst ci
                      rect = codeRect ta codeSlot (spanLines - (if isFirst then ciCaptionSpan ci else 0)) (ciStart ci)
                ]
            figures = [(fid, figureRect geom n ta slot pf, pf) | (slot, fid) <- placedFigures p, Just pf <- [Map.lookup fid (plFigures layout)]]
            {- a figure turned onto the page (golem-driver ADR 0034): its image
            and caption in its frame, turned into the type area; the view
            sees them where they land -}
            turnedOut =
              [ let pageTa = typeAreaFor geom n
                    (paper, area) = turnedFrame geom t pageTa pf
                    imageR = imageRect geom paper area 0 pf
                    captions = [entry "キャプションの行" (pfSpan pf) area (captionLineAt 0 pf j) (SetLine l (pfCaptionSize pf) 0 [] []) | (j, l) <- zip [0 ..] (pfCaption pf)]
                    onPage (rec, (_, uses)) = (rec {lrRect = P.turnRect t pageTa <$> lrRect rec}, ([], uses))
                 in (P.Turned t pageTa (figureMark fid imageR pf : concatMap (fst . snd) captions), (P.turnRect t pageTa imageR, pf), map onPage captions)
              | (_, SPageFigure fid) <- poSlots p,
                Just pf <- [Map.lookup fid (plFigures layout)],
                Just t <- [pfTurn pf]
              ]
            figMarks = [figureMark fid r pf | (fid, r, pf) <- figures]
            -- one note's lines are in one line of the flow (golem-driver ADR 0018)
            noteLines = concat [[(nid, l) | l <- take cnt (drop from (Map.findWithDefault [] nid noteBodies))] | (nid, from, cnt) <- poFootnotes p]
            -- the foot of the column, of its lines with @page-lines (docs/adr ADR 0030)
            bottomSlots = drop (poLines p - length noteLines) [0 .. poLines p - 1]
            noteParts = [entry "脚注の行" (noteSpan nid) ta (gridAt slot) (SetLine l (pgFontSize geom) 0 [] []) | (slot, (nid, l)) <- zip bottomSlots noteLines]
            {- each rule with its band, the weight of its thinnest part, its
            marks and its swatch (golem-driver ADR 0028) -}
            rules =
              [("表の罫線", r, t, [P.Rule r], Nothing) | seg <- poTables p, Just tg <- [Map.lookup (tsTable seg) tableInks], (r, t) <- tableRules ta seg tg]
                -- the rules of paragraphs and headings (golem-driver ADR 0027, 0028)
                <> [ (riKind info, band, ruleThinnest (rsWeight spec) (rsStyle spec), ruleMarks sw (ruleShapes vertical band (rsStyle spec)), sw)
                   | pr <- poRules p,
                     Just info <- [Map.lookup (prId pr) (plRules layout)],
                     Just spec <- [if prBefore pr then riBefore info else riAfter info],
                     let band = paragraphRule ta (riSize info) spec (prAt pr)
                         sw = ruleSwatch spec
                   ]
                <> [ ("脚注の罫線", r, ruleThinnest t (rsStyle rule), ruleMarks sw (ruleShapes vertical r (rsStyle rule)), sw)
                   | not (null noteLines),
                     Just rule <- [stNotesRule style],
                     let (r, t) = noteRule ta rule (poLines p - length noteLines)
                         sw = ruleSwatch rule
                   ]
         in ( lineParts <> noteParts <> concat [cs | (_, _, cs) <- turnedOut],
              (figMarks <> [m | (m, _, _) <- turnedOut], [(r, pf) | (_, r, pf) <- figures] <> [i | (_, i, _) <- turnedOut]),
              (concat [ms | (_, _, _, ms, _) <- rules], [(k, r, t) | (k, r, t, _, _) <- rules]),
              (map snd backgrounds, map fst backgrounds <> [sw | (_, _, _, _, Just sw) <- rules])
            )
      -- the columns of a page, its sidenotes and, once, its running head and folio
      drawPage ps master = case ps of
        [] -> PageDrawn [] [] [] [] [] True 0 []
        (p : _) ->
          let n = poNumber p
              columns = map drawColumn ps
              masterParts = masterMarks n (poBlank p) master (Map.findWithDefault [] n heads)
              -- the hidden folio, after everything else of the page (golem-driver ADR 0021)
              hiddenParts = hiddenMarks n
              -- sidenotes in the sidenote column of the page (golem-driver ADR 0006)
              sidenoteParts =
                [ entryAt "傍注の行" (psSpan ps') (rectX area, rectY area + rectH area - (psTop ps' + toInteger j * snPitch + round (toRational snSize' * baselineRatio))) (SetLine l snSize' 0 [] [])
                | Just area <- [sidenoteAreaFor geom n],
                  ps' <- Map.findWithDefault [] n (plSidenotes layout),
                  let (_, snSize', snPitch) = sidenoteMetrics (docStyle inp (spanFile (psSpan ps'))) geom,
                  (j, l) <- zip [0 :: Int ..] (psLines ps')
                ]
              columnParts = concat [t | (t, _, _, _) <- columns]
              allParts = columnParts <> sidenoteParts <> masterParts
              images = concat [snd f | (_, f, _, _) <- columns]
              rules = concat [snd r | (_, _, r, _) <- columns]
              backs = concat [fst b | (_, _, _, b) <- columns]
           in PageDrawn
                { pdMarks = backs <> concatMap (fst . snd) allParts <> concat [fst f | (_, f, _, _) <- columns] <> concat [fst r | (_, _, r, _) <- columns] <> concatMap fst hiddenParts,
                  pdUses = concatMap (snd . snd) allParts <> concatMap snd hiddenParts,
                  pdLines = [(rec, snd part) | (rec, part) <- allParts],
                  pdImages = images,
                  pdRules = rules,
                  -- nothing but the master page (golem-cli ADR 0006)
                  pdBlank = null columnParts && null sidenoteParts && null images && null rules && null backs,
                  pdNumber = n,
                  pdBackgrounds = concat [snd b | (_, _, _, b) <- columns] <> concat [lrBackgrounds rec | (rec, _) <- allParts]
                }
      {- the band of a paragraph or heading rule in a column (golem-driver ADR
      0027): along the line from the start of the column and start-indent,
      its length or the rest of the measure; across from the start of the
      em box of the first grid line -}
      paragraphRule ta size spec at =
        let measure = if vertical then rectH ta else rectW ta
            start = dimToSp size (rsStartIndent spec)
            len = maybe (measure - start - maybe 0 (dimToSp size) (rsEndIndent spec)) (dimToSp size) (rsLength spec)
            w = rsWeight spec
         in if vertical
              then Rect (rectX ta + rectW ta - at - w) (rectY ta + rectH ta - start - len) w len
              else Rect (rectX ta + start) (rectY ta + rectH ta - at - w) len w
      -- the swatch of a rule, if it has one (golem-driver ADR 0028)
      ruleSwatch rule = do
        name <- rsColor rule
        Swatch (c, m, y, k) <- Map.lookup name (stSwatches style)
        pure (P.Swatch c m y k)
      {- the rule before the footnotes from grid line first (golem-driver ADR
      0024): without spaces through the middle of the em box of the line
      before; with them space-after above the em box of the first
      footnote line. From the start of the line of the column, its near
      edge and far edge measured from the top (the right in vertical text). -}
      noteRule ta rule first =
        let p = pgLinePitch geom
            fs = pgFontSize geom
            w = rsWeight rule
            len = maybe 0 (dimToSp fs) (rsLength rule)
            far = case rsSpaceAfter rule of
              Nothing -> toInteger (first - 1) * p + fs `div` 2 - w `div` 2
              Just a -> toInteger first * p - dimToSp fs a - w
         in if vertical
              then (Rect (rectX ta + rectW ta - far - w) (rectY ta + rectH ta - len) w len, w)
              else (Rect (rectX ta) (rectY ta + rectH ta - far - w) len w, w)
      {- the rules of a table on a page (golem-driver ADR 0008, 0031): c
      outside the ink of the table, half the space between the ink of two
      lines; in vertical text the ink is the em box -}
      tableRules ta seg tg =
        let p = pgLinePitch geom
            fs = pgFontSize geom
            (a, d)
              | vertical = (fs `div` 2, fs - fs `div` 2)
              | otherwise = (tgAscent tg, tgDescent tg)
            c = max 0 ((p - a - d) `div` 2)
            base k = toInteger k * p + (if vertical then fs `div` 2 else round (toRational fs * baselineRatio))
            before k = base k - a - c
            after k = base k + d + c
            w = tgWidth tg
            rule cy t
              | vertical = (Rect (rectX ta + rectW ta - cy - t `div` 2) (rectY ta + rectH ta - w) t w, t)
              | otherwise = (Rect (rectX ta) (rectY ta + rectH ta - cy - t `div` 2) w t, t)
         in [rule (before (tsFirst seg)) thickRule] <> [rule (after e) thinRule | Just e <- [tsHeaderEnd seg]] <> [rule (after (tsLast seg)) thickRule]
      {- a and d of each table (golem-driver ADR 0031): the ink of the glyphs
      drawn in its cells, or the em box when none has ink -}
      tableInks = Map.mapWithKey tableInk (plTables layout)
      tableInk tid tg =
        let fs = pgFontSize geom
            inks =
              [ (toRational (guSize u) * y1, toRational (guSize u) * negate y0)
              | lid <- [tid .. tid + tgLines tg - 1],
                sl <- Map.findWithDefault [] lid (plTableLines layout),
                u <- snd (drawLineAt (0, 0) sl),
                Just (_, y0, _, y1) <- [lfInkBox fonts (guFace u) (guGlyph u)]
              ]
            emA = round (toRational fs * baselineRatio)
         in if null inks
              then tg {tgAscent = emA, tgDescent = fs - emA}
              else tg {tgAscent = round (maximum (map fst inks)), tgDescent = round (maximum (map snd inks))}
      {- row j of the k rows of a code block from grid line slot: the area
      starts half the leading above the grid line, and the rows are centred
      in it (golem-driver ADR 0017) -}
      codeRowAt slot g k j sl =
        let s = slSize sl
            areaTop = toInteger slot * pgLinePitch geom - (pgLinePitch geom - pgFontSize geom) `div` 2
            top = areaTop + codeRowsTop g k + toInteger j * cgPitch g
         in top + (if vertical then s `div` 2 else round (toRational s * baselineRatio))
      {- a part of a code block from grid line slot with k rows (golem-driver
      ADR 0023): whether it is the first part, the grid line of its rows
      (after the caption), the rows it is centred as and whether it ends
      with the text that it continues -}
      codePartOf slot lid k ci =
        let isFirst = lid == ciFirst ci
            cont = isJust (ciContinued ci) && lid + k < ciFirst ci + ciRows ci
         in (isFirst, slot + (if isFirst then ciCaptionSpan ci else 0), k + (if cont then 1 else 0), cont)
      -- line j of the caption of a code block: from the top of its grid line, j caption pitches on
      codeCaptionLineAt slot ci j =
        let cs = ciCaptionSize ci
            top = toInteger slot * pgLinePitch geom + toInteger (j :: Int) * ciCaptionPitch ci
         in top + (if vertical then cs `div` 2 else round (toRational cs * baselineRatio))
      -- the band of m rows from row j of the k rows of a part, a code pitch each, from start to the end of the line
      codeBand ta slot g k j m start =
        let p = pgLinePitch geom
            areaTop = toInteger slot * p - (p - pgFontSize geom) `div` 2
            top = areaTop + codeRowsTop g k + toInteger j * cgPitch g - (cgPitch g - cgSize g) `div` 2
            depth = toInteger m * cgPitch g
            measure = if vertical then rectH ta else rectW ta
         in if vertical
              then Rect (rectX ta + rectW ta - top - depth) (rectY ta + rectH ta - measure) depth (measure - start)
              else Rect (rectX ta + start) (rectY ta + rectH ta - top - depth) (measure - start) depth
      -- the lines of a border of width t, centred on the sides of a rectangle
      borderRects (Rect x y w h) t =
        let half = t `div` 2
         in [Rect (x - half) (y + h - half) (w + t) t, Rect (x - half) (y - half) (w + t) t, Rect (x - half) (y - half) t (h + t), Rect (x + w - half) (y - half) t (h + t)]
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
        [ runAtU (plainLook body size) False False 0 (cx - w `div` 2, cy + size `div` 2 - round (toRational size * baselineRatio)) txt
        | Just hg <- [pgHiddenFolio geom],
          let size = hgSize hg,
          (c, (cx, cy)) <- Map.findWithDefault [] n hidden,
          let txt = T.singleton c
              w = sum [toSp size (shAdvance g) | g <- lfShape fonts (Shaping body False []) txt]
        ]
      masterMarks n blank master headLines = case master of
        Nothing -> []
        Just m ->
          let pick a1 a2 = if odd n then a1 else a2
              size = pgFontSize geom
              folio = [textAt "ノンブル" (pick a1 a2) size (formatNumber fmt [toInteger n] Nothing) | drawsFolio blank master, Just (fmt, a1, a2) <- [mgFolio m]]
              -- the lines of the running head from the type area out (golem-driver ADR 0022)
              runningHead =
                [ textAt "柱" a {anY = hy} size h
                | not blank,
                  Just (_, _, a1, a2) <- [mgRunningHead m],
                  let a = pick a1 a2,
                  (h, hy) <- zip headLines (runningHeadBaselines ph (pgLinePitch geom) a (length headLines))
                ]
           in runningHead <> folio
      -- the columns of a page come together from 'paginate' (docs/adr ADR 0018)
      drawn = zipWith drawPage (pagesOf (plPages layout)) masters
      -- one Form XObject per file and page of the PDF figures (golem-pdf ADR 0008)
      formKeys = nubBy ((==) `on` fst) [((pfSource pf, pfPage pf), fc) | pf <- Map.elems (plFigures layout), Just fc <- [formOf (pfContent pf)]]
      formOf = \case
        P.VectorFigure ip -> Just (P.ImportedForm ip)
        P.SvgFigure d -> Just (P.DrawnForm d)
        P.RasterFigure _ -> Nothing
      formRefs = Map.fromList [(k, P.FormRef n) | ((k, _), n) <- zip formKeys [1 ..]]
      figureMark fid r pf = case pfContent pf of
        P.RasterFigure _ -> P.Image (P.ImageRef fid) r
        _ -> P.Form (Map.findWithDefault (P.FormRef 0) (pfSource pf, pfPage pf) formRefs) r
      -- the bleed and the crop marks around each page (golem-pdf ADR 0004)
      bleed = maybe 0 pageBleed (stPage style)
      pdfPages = [P.framePage (piMarks inp) bleed (pw, ph) (pdMarks pd) | pd <- drawn]
      {- each glyph once per font, with the text of its cluster; a whole
      cluster wins, then the first drawn (golem-driver ADR 0030) -}
      used = Map.map toUnicodeOf (Map.fromListWith (<>) [(guRef u, [(guGlyph u, guText u, guPart u)]) | pd <- reverse drawn, u <- reverse (pdUses pd)])
      -- the ToUnicode entries the marks are checked against for ActualText (golem-driver ADR 0030)
      textEntries = Map.map Map.fromList used
      -- the PDF and its view from the fonts embedded (docs/adr ADR 0034)
      finish fontsUsed =
        let programs = [case P.fontProgram f of P.TrueTypeProgram b -> b; P.CffProgram b -> b | f <- Map.elems fontsUsed]
            (y, mo, d) = toGregorian (mdDate md)
            doc =
              P.Document
                { P.docPages = pdfPages,
                  P.docFonts = fontsUsed,
                  P.docImages = Map.fromList [(P.ImageRef i, img) | (i, PlacedFigure {pfContent = P.RasterFigure img}) <- Map.toList (plFigures layout)],
                  P.docForms = Map.fromList [(P.FormRef n, ip) | ((_, ip), n) <- zip formKeys [1 ..]],
                  P.docTitle = mdTitle md,
                  P.docDate = (y, mo, d),
                  P.docId = P.documentId (mdId md),
                  P.docInstanceId = P.instanceId (instanceIdInputs (piInputs inp) programs),
                  P.docProducer = producer,
                  P.docPdfX = intent
                }
            bytes = P.writePdf doc
            -- the view of golem preflight (golem-cli ADR 0006)
            swatchOfName name = (\(Swatch c) -> (name, c)) <$> Map.lookup name (stSwatches style)
            faceFile = fst . lfFaceFile fonts
            glyphView sp u =
              V.GlyphView
                { V.gvText = guText u,
                  V.gvFont = T.pack (faceFile (guFace u)),
                  V.gvGlyph = guGlyph u,
                  V.gvSize = guSize u,
                  V.gvColor = guColor u >>= swatchOfName,
                  V.gvStyle = guRole u <> " " <> T.pack (show (guSize u)),
                  V.gvSpan = sp
                }
            bindingRight = maybe False pageBindingRight (stPage style)
            pageView i pd =
              V.PageView
                { V.pvIndex = i,
                  V.pvTrim = Rect 0 0 pw ph,
                  V.pvImages = [V.ImageView r (pfContent pf) (pfSpan pf) (pfSource pf) (isJust (pfTurn pf)) | (r, pf) <- pdImages pd],
                  V.pvLines = [V.LineView r (lrKind rec) (lrSpan rec) (lrOverfull rec) | (rec, _) <- pdLines pd, Just r <- [lrRect rec]],
                  V.pvGlyphs = [glyphView (lrSpan rec) u | (rec, us) <- pdLines pd, u <- us],
                  V.pvRules = [V.RuleView k t r | (k, r, t) <- pdRules pd],
                  V.pvBlank = pdBlank pd,
                  V.pvGutterLeft = gutterSide bindingRight (pdNumber pd) == SideLeft
                }
            swatchName sw = listToMaybe [n | (n, Swatch (c, m, y', k)) <- Map.toList (stSwatches style), P.Swatch c m y' k == sw]
            used' = nub ([c | pd <- drawn, u <- pdUses pd, Just c <- [guColor u]] <> [n | pd <- drawn, sw <- pdBackgrounds pd, Just n <- [swatchName sw]])
            view =
              V.View
                { V.vwPages = zipWith pageView [1 ..] drawn,
                  V.vwFonts = [let (path, form) = lfFaceFile fonts ix in V.FontView (T.pack path) form | ix <- nub [k `div` 2 | P.FontRef k <- Map.keys fontsUsed]],
                  V.vwSwatchesUsed = Map.fromList (mapMaybe swatchOfName used'),
                  V.vwBleed = bleed,
                  V.vwIntentProfile = P.pxProfile <$> intent,
                  V.vwX4 = P.verify (P.documentObjects doc),
                  V.vwPdf = bytes,
                  V.vwStyleSpan = styleSpan,
                  V.vwManifestSpan = mkSpan (projectManifestFile (piProject inp)) 0 0
                }
         in (bytes, view)
   in (used, finish)

-- | The centre of the em box of the Japanese characters of a look above the baseline, in em (golem-driver ADR 0033).
emBoxCentralOf :: LoadedFonts -> Look -> Rational
emBoxCentralOf fonts look = lfEmBoxCentral fonts (maybe 0 shFace (listToMaybe (lfShape fonts (Shaping (lkFace look) False []) "漢")))

-- | Groups of neighbours: a new group starts where the predicate fails between two neighbours.
groupWhen :: (a -> a -> Bool) -> [a] -> [[a]]
groupWhen same = foldr step []
  where
    step x = \case
      (g@(y : _) : gs) | same x y -> (x : g) : gs
      gs -> [x] : gs
