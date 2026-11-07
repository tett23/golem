-- | The drawing of the PDF: the pages as drawn and the PDF written (golem-driver ADR 0002).
module Golem.Typeset.Draw
  ( renderPdf,
    renderPdfView,
    renderPdfStructure,
  )
where

import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Containers.ListUtils (nubOrdOn)
import Data.Either (lefts)
import Data.List (groupBy, nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (toGregorian)
import Golem.Assemble (Book (..))
import Golem.Doc.IR
import Golem.Layout.Code
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass hiding (Sp)
import Golem.Layout.Look hiding (Kerning (..))
import Golem.Layout.Paginate
import Golem.Layout.Ruby (RubyKind (..), RubyPlacement (..), placeRuby)
import Golem.LayoutSpec (Anchor (..), HiddenFolioGeometry (..), MasterGeometry (..), PageGeometry (..), Rect (..), Side (..), baselineRatio, columnsFor, gutterSide, runningHeadBaselines, sidenoteAreaFor, typeAreaFor)
import Golem.LayoutSpec qualified as LS
import Golem.Length (zwToSp)
import Golem.Numerals.Format (formatNumber)
import Golem.Pdf qualified as P
import Golem.Preflight.View qualified as V
import Golem.Project
import Golem.Project.Style
import Golem.Syntax
import Golem.Syntax.LanguageTag (isLanguageTag)
import Golem.Typeset.Flow
import Golem.Typeset.Fonts
import Golem.Typeset.Overhang (kentenAcross, rubyAcross)
import Golem.Typeset.RuleShape (ruleMarks, ruleShapes, ruleThinnest)
import Golem.Typeset.Structure (linksOfLeaves, structureTree)
import Golem.Typeset.TextLayer (ClusterPart (..), actualTextOf, toUnicodeOf)
import Text.Printf (printf)

{- | The PDF and the notices of its layout (G07030), or the errors that
stopped it. The first argument is the version of Golem, for the Producer
and the instance ID (docs/adr/0192).
-}
renderPdf :: Text -> FontProvider -> PdfInput -> IO (Either [Diagnostic] (ByteString, [Diagnostic]))
renderPdf version provider inp = fmap (\(bytes, notices, _) -> (bytes, notices)) <$> renderPdfView version provider inp

{- | 'renderPdf' with the view of the PDF that golem preflight checks
(golem-cli ADR 0006). The view is lazy: golem build forces only the
characters of its pages, for G08100 (docs/adr 0081).
-}
renderPdfView :: Text -> FontProvider -> PdfInput -> IO (Either [Diagnostic] (ByteString, [Diagnostic], V.View))
renderPdfView version provider inp = fmap (\(bytes, notices, view, _) -> (bytes, notices, view)) <$> renderPdfAll version provider inp

-- | The structure tree of the PDF as text (docs/adr ADR 0183), for the tests.
renderPdfStructure :: Text -> FontProvider -> PdfInput -> IO (Either [Diagnostic] Text)
renderPdfStructure version provider inp = fmap (\(_, _, _, st) -> st) <$> renderPdfAll version provider inp

-- | The PDF, its notices, its view and its structure tree as text.
renderPdfAll :: Text -> FontProvider -> PdfInput -> IO (Either [Diagnostic] (ByteString, [Diagnostic], V.View, Text))
renderPdfAll version provider inp0 = case (declarationErrors inp, checkedGeometry inp) of
  (ds, Left gs) -> pure (Left (ds <> gs))
  (ds@(_ : _), Right _) -> pure (Left ds)
  ([], Right geom) -> do
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
            -- a kenten shape the font has no glyph for stops the PDF (G08009, golem-driver ADR 0019)
            case laid of
              Left ds -> pure (Left ds)
              Right layout -> case kentenGlyphDiagnostics (piStyleFile inp) (pgVertical geom) fonts layout of
                [] -> do
                  let (used, privateUse, finish) = writeDocumentView version inp geom fonts layout intent
                  -- G07104 stops the PDF/A-2a before its fonts are embedded (docs/adr ADR 0183)
                  if not (null privateUse)
                    then pure (Left privateUse)
                    else do
                      -- the fonts are subset and embedded here, at the writing edge (docs/adr ADR 0034)
                      embedded <- Map.traverseWithKey (\(P.FontRef k) gts -> lfEmbed fonts (k `div` 2) (odd k) gts) used
                      -- a face used horizontally and vertically is reported once
                      case nub (lefts (Map.elems embedded)) of
                        [] -> do
                          let (bytes, view, structure) = finish (Map.mapMaybe (either (const Nothing) Just) embedded)
                          -- G07101: dashes without ink (docs/adr ADR 0172)
                          pure (Right (bytes, plNotices layout <> runningHeadNotices inp geom fonts layout <> dashInkNotices (pgVertical geom) fonts layout, view, structure))
                        ds -> pure (Left ds)
                ds -> pure (Left ds)
  where
    inp = codeInput inp0

{- | What a book that declares PDF/A or PDF/UA must meet before its PDF is
set (docs/adr ADR 0183), in dev and prod alike: an output intent for PDF/A
(G03113, at the value of pdfa), [metadata] language in the form of a
language tag (G03119, at its value), and for PDF/UA headings that start at
level 1 and never go two levels deeper (G07103, at the heading). The
document itself is level 0 before the first heading.
-}
declarationErrors :: PdfInput -> [Diagnostic]
declarationErrors inp =
  [ diagnostic "G03113" Error (valueSpan ["targets", "pdf", "pdfa"]) "PDF/A には [color] の intent が要ります"
  | isJust pdfA,
    isNothing (stIntent (piStyle inp))
  ]
    <> [ diagnostic "G03119" Error (valueSpan ["metadata", "language"]) ("PDF/A と PDF/UA には、language を言語のタグの形で書きます: " <> mdLanguage md)
       | isJust pdfA || isJust pdfUa,
         not (isLanguageTag (mdLanguage md))
       ]
    <> [ diagnostic "G07103" Error sp ("PDF/UA では見出しの段を飛ばせません: " <> tshow' before <> " から " <> tshow' l)
       | isJust pdfUa,
         let levels = [(l, sp) | Document _ bs <- bookDocs (piBook inp), Block sp _ (Heading l _ _) <- blocksWithin bs],
         (before, (l, sp)) <- zip (0 : map fst levels) levels,
         l > before + 1
       ]
  where
    project = piProject inp
    manifest = projectManifest project
    md = manifestMetadata manifest
    pdfA = tgPdfA (manifestTargets manifest)
    pdfUa = tgPdfUa (manifestTargets manifest)
    fid = projectManifestFile project
    valueSpan keys = fromMaybe (mkSpan fid 0 0) (manifestValueSpan fid (projectManifestText project) keys)
    tshow' = T.pack . show

-- | Every block in document order, with the blocks inside lists and figures.
blocksWithin :: [Block] -> [Block]
blocksWithin = concatMap $ \b ->
  b : case blockBody b of
    BulletList items -> blocksWithin (concatMap itemBlocks items)
    OrderedList items -> blocksWithin (concatMap itemBlocks items)
    DefList gs -> blocksWithin (concat (concatMap dgDefs gs))
    FigureBlock f -> blocksWithin (figCaption f)
    _ -> []

{- | G07104 (docs/adr ADR 0183): each character of the private use area a
glyph of a PDF/A-2a stands for, once for each place in the source.
-}
privateUseErrors :: [(Text, SrcSpan)] -> [Diagnostic]
privateUseErrors uses =
  [ diagnostic "G07104" Error sp (T.pack (printf "PDF/A-2a の PDF に私用領域の字は書けません: U+%04X" (fromEnum c)))
  | (c, sp) <- nubOrdOn id [(c, sp) | (t, sp) <- uses, c <- T.unpack t, privateUse c]
  ]
  where
    privateUse c = (c >= '\xE000' && c <= '\xF8FF') || (c >= '\xF0000' && c <= '\xFFFFD') || (c >= '\x100000' && c <= '\x10FFFD')

{- | A glyph drawn: its font reference, glyph and text (for embedding),
and its face, size and swatch (for the view of golem preflight).
-}
data GlyphUse = GlyphUse
  { guRef :: !P.FontRef,
    guGlyph :: !Int,
    guText :: !Text,
    guFace :: !Int,
    guSize :: !Sp,
    guColor :: !(Maybe Text),
    -- | which glyph of its cluster the glyph is (golem-driver ADR 0030)
    guPart :: !ClusterPart,
    -- | the definition that decided the size, the part and the place in the source (golem-cli ADR 0008)
    guSizeSource :: !SizeSource,
    guGlyphPart :: !V.GlyphPart,
    guSpan :: !SrcSpan
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
    lrBackgrounds :: ![P.Swatch],
    {- | the rectangles of the links on the line, on the page, in the order of
    the line (docs/adr ADR 0182), each with the leaf of its first box (docs/adr ADR 0183)
    -} lrLinks :: ![(LinkTarget, Maybe Leaf, Rect)]
  }

-- | What one page draws.
data PageDrawn = PageDrawn
  { pdContent :: [P.Content],
    pdUses :: [GlyphUse],
    pdLines :: [(LineRec, [GlyphUse])],
    pdImages :: [(Rect, PlacedFigure)],
    pdRules :: [(Text, Rect, Sp)],
    pdBlank :: Bool,
    pdNumber :: Int,
    pdBackgrounds :: [P.Swatch],
    -- | the links of the page, in the order drawn (docs/adr ADR 0182)
    pdLinks :: [(LinkTarget, Maybe Leaf, Rect)]
  }

{- | What the drawing of a document shares: the input, the page geometry,
the fonts and the layout, and the values computed once from them. The
ToUnicode entries come from the glyphs of every page, so they are read
lazily while the pages are drawn.
-}
data DrawEnv = DrawEnv
  { deInput :: PdfInput,
    deGeom :: PageGeometry,
    deFonts :: LoadedFonts,
    deLayout :: PdfLayout,
    -- | the running head of each page (golem-driver ADR 0014)
    deHeads :: Map Int [Text],
    -- | the column set of the page geometry; the pages of an index may set another (docs/adr ADR 0025)
    deBaseSet :: ColumnSet,
    -- | the ToUnicode entries the marks are checked against for ActualText (golem-driver ADR 0030)
    deTextEntries :: Map P.FontRef (Map Int Text),
    -- | the lines of each footnote by its key (golem-driver ADR 0018)
    deNoteBodies :: Map NoteId [Line],
    {- | a and d of each table (golem-driver ADR 0031): the ink of the glyphs
    drawn in its cells, or the em box when none has ink
    -} deTableInks :: Map Int TableGeometry,
    -- | each digit of the hidden folio of each page and its point (golem-driver ADR 0021)
    deHidden :: Map Int [(Char, (Sp, Sp))],
    -- | the Form XObject of each file and page of the PDF figures (golem-pdf ADR 0008)
    deFormRefs :: Map (Text, Int) P.FormRef,
    -- | the page and column where each line of the flow is first drawn (docs/adr ADR 0183)
    deFirstPlace :: Map Int (Int, Int)
  }

{- | The PDF and its view for golem preflight (golem-cli ADR 0006), from the
values drawn; the view costs nothing until it is used. The fonts are
embedded in IO between the two halves (docs/adr ADR 0034): the glyphs
used in each font and their text, then the PDF and its view from the
embedded fonts.
-}
writeDocumentView :: Text -> PdfInput -> PageGeometry -> LoadedFonts -> PdfLayout -> Maybe P.PdfX -> (Map P.FontRef [(Int, Text)], [Diagnostic], Map P.FontRef P.Font -> (ByteString, V.View, Text))
writeDocumentView version inp geom fonts layout intent =
  let md = manifestMetadata (projectManifest (piProject inp))
      (pw, ph) = pgPageSize geom
      -- the master page of each page (golem-driver ADR 0014)
      masters = pageMasters inp geom layout
      style = piStyle inp
      styleSpan = mkSpan (piStyleFile inp) 0 0
      env =
        DrawEnv
          { deInput = inp,
            deGeom = geom,
            deFonts = fonts,
            deLayout = layout,
            deHeads = runningHeads inp geom layout,
            deBaseSet = pageColumnSet (piStyle inp) geom,
            deTextEntries = textEntries,
            deNoteBodies = Map.fromList [note | sl <- Map.elems (plLines layout), note <- slNotes sl],
            deTableInks = Map.mapWithKey (tableInk env) (plTables layout),
            deHidden = hiddenFolios inp geom layout,
            deFormRefs = formRefs,
            deFirstPlace = Map.fromListWith (\_ old -> old) [(lid, (poNumber p, poColumn p)) | p <- plPages layout, (_, SLine lid) <- poSlots p]
          }
      -- the columns of a page come together from 'paginate' (docs/adr ADR 0018)
      drawn = zipWith (drawPage env) (pagesOf (plPages layout)) masters
      -- one Form XObject per file and page of the PDF figures (golem-pdf ADR 0008)
      formKeys = nubOrdOn fst [((pfSource pf, pfPage pf), fc) | pf <- Map.elems (plFigures layout), Just fc <- [formOf (pfContent pf)]]
      formOf = \case
        P.VectorFigure ip -> Just (P.ImportedForm ip)
        P.SvgFigure d -> Just (P.DrawnForm d)
        P.RasterFigure _ -> Nothing
      formRefs = Map.fromList [(k, P.FormRef n) | ((k, _), n) <- zip formKeys [1 ..]]
      -- the bleed and the crop marks around each page (golem-pdf ADR 0004)
      bleed = maybe 0 pageBleed (stPage style)
      -- the link annotations, each of the Link of the structure tree that holds the first box of its line (docs/adr ADR 0183)
      pdfPages =
        [ P.framePageWith (piMarks inp) bleed (pw, ph) (pdContent pd) [P.LinkAnnotation r (P.UriAction u) aid (aid >>= (`Map.lookup` linkContents)) | (LinkUri u, lf, r) <- pdLinks pd, let aid = lf >>= leafOf >>= (`Map.lookup` linkOfLeaf)]
        | pd <- drawn
        ]
      (structure, linkContents) = structureTree (plFlowEnv layout) (plUnits layout) figureAttrs
      linkOfLeaf = linksOfLeaves structure
      {- the BBox of the Figure of each figure where it is first drawn, in the
      space of its page, and its placement (docs/adr ADR 0183) -}
      origin = P.frameOrigin (piMarks inp) bleed (pw, ph)
      figureBoxes = Map.fromListWith (\_ old -> old) [(pfUnit pf, r) | pd <- drawn, (r, pf) <- pdImages pd]
      figureAttrs i = [P.Attribute "Layout" [("BBox", P.rectObj (r {rectX = rectX r + origin, rectY = rectY r + origin})), ("Placement", P.OName "Block")] | Just r <- [Map.lookup i figureBoxes]]
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
                  P.docInstanceId = P.instanceId (instanceIdInputs version (piInputs inp) programs),
                  P.docProducer = producer version,
                  P.docPdfX = intent,
                  P.docLang = mdLanguage md,
                  P.docPdfUa = case tgPdfUa (manifestTargets (projectManifest (piProject inp))) of
                    Just PdfUa1 -> Just P.PdfUa1
                    Nothing -> Nothing,
                  P.docStructure = structure
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
                  V.gvSizeSource = guSizeSource u,
                  V.gvPart = guGlyphPart u,
                  V.gvSpan = guSpan u,
                  V.gvLineSpan = sp
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
         in (bytes, view, P.structureText doc)
      -- the characters of the private use area in a PDF/A-2a (G07104, docs/adr ADR 0183)
      privateUse = case P.pxPdfA =<< intent of
        Just _ -> privateUseErrors [(guText u, guSpan u) | pd <- drawn, u <- pdUses pd]
        Nothing -> []
   in (used, privateUse, finish)

-- font index × direction: even refs horizontal, odd refs vertical
ref :: Int -> Bool -> P.FontRef
ref ix v = P.FontRef (2 * ix + (if v then 1 else 0))

toSp :: Sp -> Rational -> Sp
toSp = zwToSp

isLatin :: Char -> Bool
isLatin = (== Western) . charClass

{- the runs of a text in a look: its role and whether it is a Latin
run; split into Latin and other runs where the two sides differ in
role or in synthetic bold and slant (golem-driver ADR 0004, docs/adr ADR 0005);
a combining character stays with the character before it, variation
selectors among them (golem-pdf ADR 0006, golem-driver ADR 0036) -}
runsOf :: Look -> Text -> [(Text, Text, Bool)]
runsOf look txt
  | lkFace look == lkLatinFace look && lkSynthetic look == lkLatinSynthetic look && not (synBold (lkSynthetic look) || synBold (lkLatinSynthetic look)) = [(lkFace look, txt, False)]
  | otherwise = [(if latin then lkLatinFace look else lkFace look, r, latin) | r <- T.groupBy (\a b -> isExtending b || isLatin a == isLatin b) txt, not (T.null r), let latin = isLatin (T.head r)]

-- the synthetic bold and slant of a run
syntheticOf :: Look -> Bool -> Synthetic
syntheticOf look latin = if latin then lkLatinSynthetic look else lkSynthetic look

-- glyph marks of a text in a look starting at a point, and the glyphs used
runAt :: DrawEnv -> Look -> Bool -> Bool -> Int -> (Sp, Sp) -> Text -> ([P.Mark], [(P.FontRef, Int, Text, ClusterPart)])
runAt env look v rotated scale (bx, by) txt =
  let size = lkSize look
      -- the baseline shift: up in horizontal text, right in vertical text (docs/adr/0020)
      shift = lkBaselineShift look
      (x0, y0) = if v then (bx + shift, by) else (bx, by + shift)
      -- shaped with the features of the look; rotated Latin is shaped horizontally
      vv = v && not rotated
      shapingFor role r = (shapingOf vv look (maybe ' ' fst (T.uncons r))) {shRole = role, shVertical = vv}
      {- the tracking after the last glyph of each cluster, for each of its
      characters, as the boxes count it (docs/adr/0020) -}
      tr = fromIntegral (lkTracking look) * size
      trackingAfter r shaped =
        let starts = map shCluster shaped
            nexts = drop 1 starts <> [T.length r]
            cluster c = minimum (T.length r : filter (> c) starts) - c
         in [if n /= c then Sp (round (fromIntegral (cluster c) * unSp tr % 1000)) else 0 | (c, n) <- zip starts nexts]
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
          | [(_, Just t)] <- actualTextOf (Map.findWithDefault Map.empty (refOf ix tu) (deTextEntries env)) [(g, t', part) | (_, g, t', _, _, _, _, part) <- occ] -> Just t
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
  where
    fonts = deFonts env

{- | A run of full-width dashes from the start of its box (docs/adr ADR
0172): each dash shaped alone in an em of its own, its glyph scaled along
the line by the text matrix so that its ink fills the em, and so the
lines meet; across the line, as an unscaled glyph. Upright in vertical
text with a vertical form, turned otherwise (golem-driver ADR 0015); a
glyph without ink is drawn unscaled at the start of its em (G07101).
-}
dashesAt :: DrawEnv -> Look -> Bool -> (Sp, Sp) -> Text -> ([P.Mark], [(P.FontRef, Int, Text, ClusterPart)])
dashesAt env look v (bx, by) txt =
  let size = lkSize look
      shift = lkBaselineShift look
      (x0, y0) = if v then (bx + shift, by) else (bx, by + shift)
      syn = lkSynthetic look
      slant = if synSlant syn then syntheticSlant else 0
      stroke = if synBold syn then syntheticStroke syntheticStrokeJa size else 0
      em = toSp size
      cell k ch =
        let start = size * fromInteger k
         in case dashShaped fonts v look ch of
              [g] -> Right (glyph start g)
              -- not one glyph: drawn as other text, at the start of its em
              _ -> Left (runAt env look v False 0 (if v then (bx, by - start) else (bx + start, by)) (T.singleton ch))
      glyph start g@Shaped {shFace = ix, shGlyph = gl, shText = t, shPart = part} =
        let turned = v && shTurned g
            r = ref ix (v && not turned)
            ink = dashInk fonts v g
            -- the scale that makes the ink an em long
            s = maybe 1 (\(a, b) -> 1 / (b - a)) ink
            (matrix, origin)
              | not v = ((s, 0, slant, 1), (x0 + start - maybe 0 (\(a, _) -> em (s * a)) ink, y0))
              -- the x of the glyph goes down the line, its baseline left of the centre line (golem-driver ADR 0015)
              | turned = ((0, negate s, 1, negate slant), (x0 - em (lfEmBoxCentral fonts ix), y0 - start + maybe 0 (\(a, _) -> em (s * a)) ink))
              -- Identity-V: the glyph origin is 0.88 em below the top of the em box (golem-pdf W2)
              | otherwise = ((1, 0, slant * s, s), (x0, y0 - start - maybe 0 (\(_, b) -> em (s * (b - 88 / 100))) ink))
            drawnAt = (matrix, lfCode fonts ix gl, fst origin, snd origin)
            replacement = case actualTextOf (Map.findWithDefault Map.empty r (deTextEntries env)) [(gl, t, part)] of
              [(_, Just t')] -> Just t'
              _ -> Nothing
         in (r, replacement, drawnAt, (r, gl, t, part))
      cells = zipWith cell [0 :: Integer ..] (T.unpack txt)
      -- the glyphs of a font in a row are one run; a glyph whose text is not its ToUnicode entry is drawn alone in ActualText (golem-driver ADR 0030)
      marksOf = \case
        [] -> []
        Left (ms, _) : rest -> ms <> marksOf rest
        Right (r, Just t', e, _) : rest -> P.ActualText t' [P.TransformedGlyphRun r size stroke [e]] : marksOf rest
        Right (r, Nothing, e, _) : rest ->
          let (same, rest') = span (\case Right (r', Nothing, _, _) -> r' == r; _ -> False) rest
           in P.TransformedGlyphRun r size stroke (e : [e' | Right (_, _, e', _) <- same]) : marksOf rest'
      uses = concat [either snd (\(_, _, _, u) -> [u]) c | c <- cells]
   in (marksOf cells, uses)
  where
    fonts = deFonts env

{- the mark of a kenten shape in a role at a size, the centre of the
ink box of its glyph at a point (golem-driver ADR 0019): horizontal,
in the vertical font (its glyph origin at (1/2, 0.88) em of the
glyph, as golem-pdf writes W2), or turned -}
kentenMark :: DrawEnv -> Text -> KentenShape -> Sp -> (Sp, Sp) -> ([P.Mark], [(P.FontRef, Int, Text, ClusterPart)])
kentenMark env role shape d (cx, cy) =
  let place Shaped {shFace = ix, shGlyph = g, shText = t, shTurned = tu} =
        let (x0, y0, x1, y1) = fromMaybe (0, 0, 0, 0) (lfInkBox fonts ix g)
            (mx, my) = ((x0 + x1) / 2, (y0 + y1) / 2)
            code = lfCode fonts ix g
            -- the mark is a cluster of one glyph; in ActualText when its entry env is another text (golem-driver ADR 0030)
            -- the use does not wait for the entries, which come from the uses of every page
            withText r m =
              ( case actualTextOf (Map.findWithDefault Map.empty r (deTextEntries env)) [(g, t, ClusterWhole)] of
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
  where
    fonts = deFonts env
    vertical = pgVertical (deGeom env)

-- the face that sets the Japanese text of a look: that of an ideograph
japaneseFace :: DrawEnv -> Look -> Int
japaneseFace env look = maybe 0 shFace (listToMaybe (lfShape fonts (Shaping (lkFace look) False []) "漢"))
  where
    fonts = deFonts env

-- the swatch of a look, when it names one (golem-driver ADR 0004)
swatchOf :: DrawEnv -> Look -> Maybe P.Swatch
swatchOf env look = do
  name <- lkColor look
  Swatch (cc, cm, cy, ck) <- Map.lookup name (stSwatches style)
  pure (P.Swatch cc cm cy ck)
  where
    style = piStyle (deInput env)

-- runAt env with the face, size, swatch and role of each glyph, for the view (golem-cli ADR 0006)
-- who: the size source, the part and the span of the glyphs (golem-cli ADR 0008)
runAtU :: DrawEnv -> (SizeSource, V.GlyphPart, SrcSpan) -> Look -> Bool -> Bool -> Int -> (Sp, Sp) -> Text -> ([P.Mark], [GlyphUse])
runAtU env who look v rotated scale pt txt = usesOf who look (runAt env look v rotated scale pt txt)

usesOf :: (SizeSource, V.GlyphPart, SrcSpan) -> Look -> ([P.Mark], [(P.FontRef, Int, Text, ClusterPart)]) -> ([P.Mark], [GlyphUse])
usesOf (src, gp, sp) look (ms, us) = (ms, [GlyphUse r g t (k `div` 2) (lkSize look) (lkColor look) part src gp sp | (r@(P.FontRef k), g, t, part) <- us])

-- the glyphs of a box, of a part
whoOf :: V.GlyphPart -> BoxContent -> (SizeSource, V.GlyphPart, SrcSpan)
whoOf gp c = (fst (bcSource c), gp, snd (bcSource c))

-- a line at a distance across the type area: the baseline from its
-- top edge, or the centre line from its right edge
lineStart :: DrawEnv -> Rect -> Sp -> (Sp, Sp)
lineStart env ta cross
  | vertical = (rectX ta + rectW ta - cross, rectY ta + rectH ta)
  | otherwise = (rectX ta, rectY ta + rectH ta - cross)
  where
    vertical = pgVertical (deGeom env)

-- a line drawn with its record for the view (golem-cli ADR 0006)
entry :: DrawEnv -> Text -> SrcSpan -> Rect -> Sp -> SetLine -> (LineRec, ([P.Content], [GlyphUse]))
entry env kind sp ta cross = entryAt env kind sp (lineStart env ta cross)

entryAt :: DrawEnv -> Text -> SrcSpan -> (Sp, Sp) -> SetLine -> (LineRec, ([P.Content], [GlyphUse]))
entryAt env kind sp start sl = (LineRec kind sp (lineFace env start sl) (overfullOf sl) (map fst (codeBackgrounds env start sl)) (linkRects env start sl), drawLineAt env start sl)

{- the backgrounds of inline code on a line (golem-driver ADR 0029): each
run of boxes of one swatch, with the spaces between them, from the
start of its first box to the end of its last, across the face of the
line; a run of code ends at a box with padding after it or before
the next one -}
codeBackgrounds :: DrawEnv -> (Sp, Sp) -> SetLine -> [(P.Swatch, Rect)]
codeBackgrounds env (x0, y0) sl =
  let size = slSize sl
      boxes = [(off, w, c) | (Box w c, off) <- placeLine (slLine sl)]
      breaksBefore (_, _, p) (_, _, c) = bcPadEnd p > 0 || bcPadStart c > 0 || lkBackground (bcLook p) /= lkBackground (bcLook c)
      runs = groupWhen (\a b -> not (breaksBefore a b)) boxes
      rectOf = faceRect vertical size (x0, y0)
   in [ (sw, rectOf (slIndent sl + s0) (slIndent sl + e0))
      | run@((s0, _, c) : _) <- runs,
        Just name <- [lkBackground (bcLook c)],
        Just (Swatch (cc, cm, cy, ck)) <- [Map.lookup name (stSwatches style)],
        let sw = P.Swatch cc cm cy ck
            e0 = maximum [o + w | (o, w, _) <- run]
      ]
  where
    style = piStyle (deInput env)
    vertical = pgVertical (deGeom env)

{- the rectangle of the face of a line of a size from s0 to e0 along it: in
horizontal text the height of the size, the baseline at the ratio; in
vertical text the width of the size, centred on the line -}
faceRect :: Bool -> Sp -> (Sp, Sp) -> Sp -> Sp -> Rect
faceRect vertical size (x0, y0) s0 e0
  | vertical = Rect (x0 - Sp (unSp size `div` 2)) (y0 - e0) size (e0 - s0)
  | otherwise = Rect (x0 + s0) (y0 - (size - zwToSp size baselineRatio)) (e0 - s0) size

{- the links on a line (docs/adr ADR 0182): each run of boxes of one
target, with the glue between them, from the start of its first box to
the end of its last, across the face of the line, as 'codeBackgrounds';
the reading of a ruby is not in it -}
linkRects :: DrawEnv -> (Sp, Sp) -> SetLine -> [(LinkTarget, Maybe Leaf, Rect)]
linkRects env start sl =
  [ (t, Just (bcLeaf c), faceRect vertical (slSize sl) start (slIndent sl + s0) (slIndent sl + e0))
  | run@((s0, _, c) : _) <- groupWhen (\(_, _, p) (_, _, c) -> lkLink (bcLook p) == lkLink (bcLook c)) boxes,
    let e0 = maximum [o + w | (o, w, _) <- run],
    Just t <- [lkLink (bcLook c)]
  ]
  where
    boxes = [(off, w, c) | (Box w c, off) <- placeLine (slLine sl)]
    vertical = pgVertical (deGeom env)

-- the face of a line: from its first box to the end of its last, the height of its size
lineFace :: DrawEnv -> (Sp, Sp) -> SetLine -> Maybe Rect
lineFace env (x0, y0) sl =
  let boxes = [(off, w) | (Box w _, off) <- placeLine (slLine sl)]
      size = slSize sl
      s0 = slIndent sl + minimum (map fst boxes)
      e0 = slIndent sl + maximum [o + w | (o, w) <- boxes]
   in if null boxes
        then Nothing
        else
          Just
            ( if vertical
                then Rect (x0 - Sp (unSp size `div` 2)) (y0 - e0) size (e0 - s0)
                else Rect (x0 + s0) (y0 - (size - zwToSp size baselineRatio)) (e0 - s0) size
            )
  where
    vertical = pgVertical (deGeom env)

overfullOf :: SetLine -> Maybe Sp
overfullOf sl =
  let l = slLine sl
      end = maximum (0 : [o + w | (Box w _, o) <- placeLine l])
   in if lineOverfull l then Just (max 0 (end - lineTarget l)) else Nothing

-- the block of a line: the unit whose first line is at or before it
spanOfLine :: DrawEnv -> Int -> SrcSpan
spanOfLine env lid = maybe styleSpan snd (Map.lookupLE lid (plLineSpans layout))
  where
    layout = deLayout env
    styleSpan = mkSpan (piStyleFile (deInput env)) 0 0

noteSpan :: DrawEnv -> NoteId -> SrcSpan
noteSpan env nid = case [lid | (lid, sl) <- Map.toList (plLines layout), (nid', _) <- slNotes sl, nid' == nid] of
  (lid : _) -> spanOfLine env lid
  [] -> styleSpan
  where
    layout = deLayout env
    styleSpan = mkSpan (piStyleFile (deInput env)) 0 0

-- a line from its start point: on the baseline, or on the centre line

{- | A line from its start point: its tagged content and artifacts
(docs/adr ADR 0183). The boxes of one leaf next to each other are one
piece of tagged content; the reading of a ruby is the leaf after its base;
the mark of kenten and the backgrounds of inline code are artifacts.
-}
drawLineAt :: DrawEnv -> (Sp, Sp) -> SetLine -> ([P.Content], [GlyphUse])
drawLineAt env (x0, y0) sl =
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
      -- and its source
      whoBefore i = case [c | (Box _ c, _) <- reverse (take i placed)] of
        (c : _) -> whoOf V.PartBase c
        [] -> (SourceGrid, V.PartBase, styleSpan)
      boxRun (i, (it, off)) = case it of
        Box w c ->
          let look = bcLook c
              size = lkSize look
              half = look {lkSize = Sp (unSp size `div` 2)}
              leaf = leafOf (bcLeaf c)
              whole r = ([(leaf, fst r)], snd r)
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
                          rp = placeRuby (rubyStyleOf style (lkSize look)) (if kind == KindRuby then MonoRuby else GroupRuby) baseAdv readAdv (Sp (unSp excess `div` 2), Sp (unSp excess `div` 2))
                          -- the reading sits beside the largest base character
                          big = if null baseLooks then size else maximum (map lkSize baseLooks)
                          across = rubyAcross vertical big rsize
                          -- a base character of another colour than the box is drawn in its own
                          inColour lk (marks, glyphs)
                            | lkColor lk /= lkColor look, Just sw <- swatchOf env lk = ([P.Saved (P.SetColor sw : marks)], glyphs)
                            | otherwise = (marks, glyphs)
                          placed1 = [inColour lk (runAtU env (whoOf V.PartBase c) lk vertical False 0 (origin (off + pos)) u) | (u, lk, pos) <- zip3 baseUnits baseLooks (rpBase rp)]
                          placed2 = [runAtU env (whoOf V.PartRuby c) half vertical False 0 (beside (origin (off + pos)) across) (T.singleton ch) | (ch, pos) <- zip (T.unpack rt) (rpReading rp)]
                       in ([(leaf, concatMap fst placed1), (leafOf (rubyTextLeaf (bcLeaf c)), concatMap fst placed2)], concatMap snd (placed1 <> placed2))
                KindKenten ->
                  {- the character, and the mark of its shape, half its size, the
                  centre of its ink box beside the em box (golem-driver ADR 0019):
                  above the middle of the advance in horizontal text, right of
                  the middle of the box in vertical text -}
                  let (b1, u1) = runAtU env (whoOf V.PartBase c) look vertical False 0 (origin off) (bcText c)
                      d = lkSize half
                      shift = lkBaselineShift look
                      parent = lfShape fonts (shapingOf vertical look (T.head (bcText c))) (bcText c)
                      centre
                        | vertical = beside (origin (off + Sp (unSp size `div` 2))) (shift + kentenAcross True size 0 d)
                        | otherwise =
                            let adv = toSp size (sum (map shAdvance parent))
                                central = maybe 0 (lfEmBoxCentral fonts . shFace) (listToMaybe parent)
                             in beside (origin (off + Sp (unSp adv `div` 2))) (shift + kentenAcross False size central d)
                      (b2, u2) = maybe ([], []) (\sh -> usesOf (whoOf V.PartKenten c) (look {lkSize = d}) (kentenMark env (lkFace look) sh d centre)) (lkKenten look)
                   in ([(leaf, b1), (Nothing, b2)], u1 <> u2)
                KindNoteMark ->
                  {- the mark of a note in the look of mark-style (docs/adr/0177),
                  placed by the look of its place, the size s of the text and m of
                  the mark: in horizontal text the top of its em box at the top of
                  that of the text, s × (c_t + 1/2) − m × (c_m + 1/2) above the
                  baseline; in vertical text its parts along the line, their
                  column right-aligned with the em box of the text, (s − m)/2
                  right of the centre line (golem-driver ADR 0018). The baseline
                  shift of the mark moves it further, as other text. -}
                  let place = maybe look mbPlace (bcMark c)
                      s = lkSize place
                      (ox, oy) = origin off
                      emCentre lk = lfEmBoxCentral fonts (japaneseFace env lk)
                      above = Sp (round (toRational (unSp s) * (emCentre place + 1 / 2) - toRational (unSp size) * (emCentre look + 1 / 2)))
                      column = ox + Sp (unSp (s - size) `div` 2)
                      part (tag, t, o)
                        | toEnum tag == KindRotated = runAtU env (whoOf V.PartBase c) look True True 0 (column - Sp (unSp (size * 3) `div` 10), oy - o) t
                        | otherwise = runAtU env (whoOf V.PartBase c) look True False 0 (column, oy - o) t
                   in whole $
                        if vertical
                          then mconcat (map part (maybe [(fromEnum KindText, bcText c, bcPadStart c)] mbParts (bcMark c)))
                          else runAtU env (whoOf V.PartBase c) look False False 0 (ox + bcPadStart c, oy + above) (bcText c)
                -- the empty box of an [aki] draws nothing (golem-layout ADR 0012)
                KindAki -> ([], [])
                -- a run of full-width dashes: one line from end to end of its box (docs/adr ADR 0172)
                KindDashes -> whole (usesOf (whoOf V.PartBase c) look (dashesAt env look vertical (origin off) (bcText c)))
                _ ->
                  let pre = case T.unpack (bcText c) of
                        [ch] | boxKind c == KindPunctuation -> toSp size (fst (punctSpace (charClass ch)))
                        _ -> 0
                      rotated = boxKind c == KindRotated
                      -- the glyphs of inline code after its padding (golem-driver ADR 0029)
                      (ox, oy) = origin (off + bcPadStart c - pre)
                      -- vertical glyph origins sit on the centre line; rotated Latin sits on a baseline beside it
                      pt
                        | vertical && rotated = (ox - Sp (unSp (size * 3) `div` 10), oy)
                        | otherwise = (ox, oy) -- Identity-V: the origin is the top centre of the em box
                   in whole (runAtU env (whoOf V.PartBase c) look vertical rotated (if bcExpandable c then lineExpansion l else 0) pt (bcText c))
        -- a word broken at the line end gets its hyphen
        Penalty hw _ (PatternHyphen _)
          | i == lastIx && hw > 0 ->
              let (ox, oy) = origin off
                  look = lookBefore i
                  size = lkSize look
                  -- the hyphen is of the leaf of the box before it
                  leafBefore = case [bcLeaf c | (Box _ c, _) <- reverse (take i placed)] of
                    (lf : _) -> leafOf lf
                    [] -> Nothing
                  r = runAtU env (whoBefore i) look vertical vertical 0 (if vertical then (ox - Sp (unSp (size * 3) `div` 10), oy) else (ox, oy)) "-"
               in (lkColor look, ([(leafBefore, fst r)], snd r))
        _ -> (Nothing, ([], []))
      -- by the glyphs used, not the marks: the marks need the ToUnicode entries of every page (golem-driver ADR 0030)
      parts = filter (not . null . snd . snd) (zipWith (curry boxRun) [0 ..] placed)
      -- each piece of a box with its leaf and swatch, in order
      pieces = [(lf, col, ms) | (col, (ps, _)) <- parts, (lf, ms) <- ps, not (null ms)]
      -- boxes of the same swatch in a row share one saved colour, inside the content of their leaf
      coloured grp = case grp of
        ((_, Just name, _) : _)
          | Just sw <- swatchOf env (plainLook body 0) {lkColor = Just name} -> [P.Saved (P.SetColor sw : concat [ms | (_, _, ms) <- grp])]
        _ -> concat [ms | (_, _, ms) <- grp]
      contentOf grp@((lf, _, _) : _) =
        let ms = concatMap coloured (groupBy (\(_, a, _) (_, b, _) -> a == b) grp)
         in maybe (P.Artifact P.Layout ms) (`P.Tagged` ms) lf
      contentOf [] = P.Artifact P.Layout []
      -- the backgrounds of inline code before the text of the line (golem-driver ADR 0029)
      backs = [P.Artifact P.Layout [P.Saved [P.SetColor sw, P.Rule rr] | (sw, rr) <- codeBackgrounds env (x0, y0) sl] | not (null (codeBackgrounds env (x0, y0) sl))]
   in (backs <> map contentOf (groupBy (\(a, _, _) (b, _, _) -> a == b) pieces), concatMap (snd . snd) parts)
  where
    fonts = deFonts env
    style = piStyle (deInput env)
    vertical = pgVertical (deGeom env)
    body = bodyRole (piStyle (deInput env))
    styleSpan = mkSpan (piStyleFile (deInput env)) 0 0

-- | The leaf of the structure tree of a box: none for a box of no place, an artifact (docs/adr ADR 0183).
leafOf :: Leaf -> Maybe P.LeafId
leafOf = \case
  Leaf [] _ -> Nothing
  Leaf site k -> Just (P.LeafId (site <> [k]))

-- | The leaf of the reading of a ruby box: the one after its base (golem-layout 'composeInlinesTree').
rubyTextLeaf :: Leaf -> Leaf
rubyTextLeaf (Leaf site k) = Leaf site (k + 1)

-- | A running head or a folio: an artifact of pagination (docs/adr ADR 0183).
textAt :: DrawEnv -> Text -> LS.Anchor -> Sp -> Text -> (LineRec, ([P.Content], [GlyphUse]))
textAt env kind anchor size txt =
  let w = plainWidth fonts body size txt
      x0 = case anAlign anchor of
        LS.AlignStart -> anX anchor
        LS.AlignCenter -> anX anchor - Sp (unSp w `div` 2)
        LS.AlignEnd -> anX anchor - w
      face = Rect x0 (anY anchor - (size - zwToSp size baselineRatio)) w size
   in (LineRec kind styleSpan (Just face) Nothing [] [], first (pure . P.Artifact P.Pagination) (runAtU env (SourceGrid, V.PartBase, styleSpan) (plainLook body size) False False 0 (x0, anY anchor) txt))
  where
    fonts = deFonts env
    body = bodyRole (piStyle (deInput env))
    styleSpan = mkSpan (piStyleFile (deInput env)) 0 0

{- one column of a page, against the rectangle of the column (docs/adr
ADR 0018): its text, its images and its rules -}
drawColumn :: DrawEnv -> PageOut -> ([(LineRec, ([P.Content], [GlyphUse]))], ([P.Content], [(Rect, PlacedFigure)]), ([P.Content], [(Text, Rect, Sp)]), ([P.Content], [P.Swatch]))
drawColumn env p =
  let n = poNumber p
      -- the columns of the page, or of the index (docs/adr ADR 0025)
      rects = if poColumnSet p == deBaseSet env then columnsFor geom n else columnSetRects geom n (poColumnSet p)
      ta = case drop (poColumn p) rects of
        (c : _) -> c
        [] -> typeAreaFor geom n
      -- a line drawn again on a later page, the header row of a table, is an artifact (docs/adr ADR 0183)
      again lid = maybe False (/= (n, poColumn p)) (Map.lookup lid (deFirstPlace env))
      orAgain lid e = if again lid then asArtifact P.Pagination e else e
      lineParts =
        [orAgain lid (entry env (if Map.member lid (plTocPages layout) then "目次の行" else "本文の行") (spanOfLine env lid) ta (gridAt slot) sl) | (slot, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines layout)]]
          {- the leader and page number of a table of contents entry (golem-driver
          ADR 0009): the page number in the leaf of the end of the entry, the
          leader an artifact (docs/adr ADR 0183) -}
          <> [ entry env "目次の行" (spanOfLine env lid) ta (gridAt slot) (SetLine l (pgFontSize geom) start [] [] Nothing)
             | (slot, SLine lid) <- poSlots p,
               let lastLeaf = listToMaybe (reverse [bcLeaf c | Just sl <- [Map.lookup lid (plLines layout)], Box _ c <- lineItems (slLine sl), bcLeaf c /= noLeaf]),
               Just tp <- [Map.lookup lid (plTocPages layout)],
               (l, start) <- [(tpLeader tp, tpLeaderStart tp), (maybe id withLeaf lastLeaf (tpNumber tp), tpNumberStart tp)]
             ]
          <> [orAgain lid (entry env "表の行" (spanOfLine env lid) ta (gridAt slot) cell) | (slot, SLine lid) <- poSlots p, cell <- Map.findWithDefault [] lid (plTableLines layout)]
          <> [ entry env "見出しの行" (spanOfLine env lid) ta (headingLineAt env slot hb j sl) sl
             | (slot, SHeading lid m) <- poSlots p,
               Just hb <- [Map.lookup lid (plHeadings layout)],
               (j, Just sl) <- [(j, Map.lookup (lid + j) (plLines layout)) | j <- [0 .. m - 1]]
             ]
          <> [ entry env "キャプションの行" (pfSpan pf) ta (captionLineAt env slot pf j) (SetLine l (pfCaptionSize pf) (captionIndent env ta pf) [] [] Nothing)
             | (slot, fid) <- placedFigures p,
               Just pf <- [Map.lookup fid (plFigures layout)],
               (j, l) <- zip [0 ..] (pfCaption pf)
             ]
          -- the rows of code blocks (golem-driver ADR 0017)
          <> [ entry env "コードの行" (spanOfLine env lid) ta (codeRowAt env codeSlot (ciGeometry ci) k' j sl) sl
             | (slot, SCode lid k _) <- poSlots p,
               Just ci <- [Map.lookup lid (plCodes layout)],
               let (_, codeSlot, k', _) = codePartOf slot lid k ci,
               (j, Just sl) <- [(j, Map.lookup (lid + j) (plLines layout)) | j <- [0 .. k - 1]]
             ]
          -- the text at the end of a part that continues (an artifact, docs/adr ADR 0183), and the caption above the first part (golem-driver ADR 0023)
          <> [ asArtifact P.Pagination (entry env "コードの行" (spanOfLine env lid) ta (codeRowAt env codeSlot (ciGeometry ci) k' k sl) sl)
             | (slot, SCode lid k _) <- poSlots p,
               Just ci <- [Map.lookup lid (plCodes layout)],
               let (_, codeSlot, k', cont) = codePartOf slot lid k ci,
               cont,
               Just l <- [ciContinued ci],
               let sl = SetLine l (ciSize ci) (ciIndent ci) [] [] Nothing
             ]
          <> [ entry env "キャプションの行" (spanOfLine env lid) ta (codeCaptionLineAt env slot ci j) (SetLine l (ciCaptionSize ci) (ciStart ci) [] [] Nothing)
             | (slot, SCode lid _ _) <- poSlots p,
               Just ci <- [Map.lookup lid (plCodes layout)],
               lid == ciFirst ci,
               (j, l) <- zip [0 ..] (ciCaption ci)
             ]
      -- the backgrounds, the bands and the borders of code blocks, drawn before everything (golem-driver ADR 0017, 0023)
      backgrounds =
        concat
          [ [(sw, P.Saved [P.SetColor sw, P.Rule rect]) | Just sw <- [ciBackground ci]]
              <> [ (sw, P.Saved [P.SetColor sw, P.Rule (codeBand env ta codeSlot (ciGeometry ci) k' (from - here) (to - from) (ciStart ci))])
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
                rect = codeRect env ta codeSlot (spanLines - (if isFirst then ciCaptionSpan ci else 0)) (ciStart ci)
          ]
      figures = [(fid, figureRect geom n ta slot pf, pf) | (slot, fid) <- placedFigures p, Just pf <- [Map.lookup fid (plFigures layout)]]
      {- a figure turned onto the page (golem-driver ADR 0034): its image
      and caption in its frame, turned into the type area; the view
      sees them where they land -}
      turnedOut =
        [ let pageTa = typeAreaFor geom n
              (paper, area) = turnedFrame geom t pageTa pf
              imageR = imageRect geom paper area 0 pf
              captions = [entry env "キャプションの行" (pfSpan pf) area (captionLineAt env 0 pf j) (SetLine l (pfCaptionSize pf) 0 [] [] Nothing) | (j, l) <- zip [0 ..] (pfCaption pf)]
              onPage (rec, (_, uses)) = (rec {lrRect = P.turnRect t pageTa <$> lrRect rec, lrLinks = [(lt, lf, P.turnRect t pageTa r) | (lt, lf, r) <- lrLinks rec]}, ([], uses))
           in (P.Moved (P.MoveTurn t pageTa) (figureMark env fid imageR pf : concatMap (fst . snd) captions), (P.turnRect t pageTa imageR, pf), map onPage captions)
        | (_, SPageFigure fid) <- poSlots p,
          Just pf <- [Map.lookup fid (plFigures layout)],
          Just t <- [pfTurn pf]
        ]
      figMarks = [figureMark env fid r pf | (fid, r, pf) <- figures]
      -- one note's lines are in one line of the flow (golem-driver ADR 0018)
      noteLines = concat [[(nid, l) | l <- take cnt (drop from (Map.findWithDefault [] nid (deNoteBodies env)))] | (nid, from, cnt) <- poFootnotes p]
      -- the foot of the column, of its lines with @page-lines (docs/adr ADR 0030)
      bottomSlots = drop (poLines p - length noteLines) [0 .. poLines p - 1]
      noteParts = [entry env "脚注の行" (noteSpan env nid) ta (gridAt slot) (SetLine l (pgFontSize geom) 0 [] [] Nothing) | (slot, (nid, l)) <- zip bottomSlots noteLines]
      {- each rule with its band, the weight of its thinnest part, its
      marks and its swatch (golem-driver ADR 0028) -}
      rules =
        [("表の罫線", r, t, [P.Rule r], Nothing) | seg <- poTables p, Just tg <- [Map.lookup (tsTable seg) (deTableInks env)], (r, t) <- tableRules env ta seg tg]
          -- the rules of paragraphs and headings (golem-driver ADR 0027, 0028)
          <> [ (riKind info, band, ruleThinnest (rsWeight spec) (rsStyle spec), ruleMarks sw (ruleShapes vertical band (rsStyle spec)), sw)
             | pr <- poRules p,
               Just info <- [Map.lookup (prId pr) (plRules layout)],
               Just spec <- [if prBefore pr then riBefore info else riAfter info],
               let band = paragraphRule env ta (riSize info) spec (prAt pr)
                   sw = ruleSwatch env spec
             ]
          <> [ ("脚注の罫線", r, ruleThinnest t (rsStyle rule), ruleMarks sw (ruleShapes vertical r (rsStyle rule)), sw)
             | not (null noteLines),
               Just rule <- [stNotesRule style],
               let (r, t) = noteRule env ta rule (poLines p - length noteLines)
                   sw = ruleSwatch env rule
             ]
   in ( lineParts <> noteParts <> concat [cs | (_, _, cs) <- turnedOut],
        (figMarks <> [m | (m, _, _) <- turnedOut], [(r, pf) | (_, r, pf) <- figures] <> [i | (_, i, _) <- turnedOut]),
        -- rules and the backgrounds of code are artifacts of layout (docs/adr ADR 0183)
        ([P.Artifact P.Layout (concat [ms | (_, _, _, ms, _) <- rules]) | not (null rules)], [(k, r, t) | (k, r, t, _, _) <- rules]),
        ([P.Artifact P.Layout (map snd backgrounds) | not (null backgrounds)], map fst backgrounds <> [sw | (_, _, _, _, Just sw) <- rules])
      )
  where
    geom = deGeom env
    layout = deLayout env
    style = piStyle (deInput env)
    vertical = pgVertical (deGeom env)
    gridAt = gridLine (deGeom env)

-- the columns of a page, its sidenotes and, once, its running head and folio
drawPage :: DrawEnv -> [PageOut] -> Maybe MasterGeometry -> PageDrawn
drawPage env ps master = case ps of
  [] -> PageDrawn [] [] [] [] [] True 0 [] []
  (p : _) ->
    let n = poNumber p
        columns = map (drawColumn env) ps
        masterParts = masterMarks env n (poBlank p) master (Map.findWithDefault [] n (deHeads env))
        -- the (deHidden env) folio, after everything else of the page (golem-driver ADR 0021)
        hiddenParts = hiddenMarks env n
        -- sidenotes in the sidenote column of the page (golem-driver ADR 0006)
        sidenoteParts =
          [ entryAt env "傍注の行" (psSpan ps') (rectX area, rectY area + rectH area - (psTop ps' + fromIntegral j * snPitch + zwToSp snSize' baselineRatio)) (SetLine l snSize' 0 [] [] Nothing)
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
          { pdContent = backs <> concatMap (fst . snd) allParts <> concat [fst f | (_, f, _, _) <- columns] <> concat [fst r | (_, _, r, _) <- columns] <> concatMap fst hiddenParts,
            pdUses = concatMap (snd . snd) allParts <> concatMap snd hiddenParts,
            pdLines = [(rec, snd part) | (rec, part) <- allParts],
            pdImages = images,
            pdRules = rules,
            -- nothing but the master page (golem-cli ADR 0006)
            pdBlank = null columnParts && null sidenoteParts && null images && null rules && null backs,
            pdNumber = n,
            pdBackgrounds = concat [snd b | (_, _, _, b) <- columns] <> concat [lrBackgrounds rec | (rec, _) <- allParts],
            pdLinks = concat [lrLinks rec | (rec, _) <- allParts]
          }
  where
    inp = deInput env
    geom = deGeom env
    layout = deLayout env

{- the band of a paragraph or heading rule in a column (golem-driver ADR
0027): along the line from the start of the column and start-indent,
its length or the rest of the measure; across from the start of the
em box of the first grid line -}
paragraphRule :: DrawEnv -> Rect -> Sp -> RuleSpec -> Sp -> Rect
paragraphRule env ta size spec at =
  let measure = if vertical then rectH ta else rectW ta
      start = dimToSp size (rsStartIndent spec)
      len = maybe (measure - start - maybe 0 (dimToSp size) (rsEndIndent spec)) (dimToSp size) (rsLength spec)
      w = rsWeight spec
   in if vertical
        then Rect (rectX ta + rectW ta - at - w) (rectY ta + rectH ta - start - len) w len
        else Rect (rectX ta + start) (rectY ta + rectH ta - at - w) len w
  where
    vertical = pgVertical (deGeom env)

-- the swatch of a rule, if it has one (golem-driver ADR 0028)
ruleSwatch :: DrawEnv -> RuleSpec -> Maybe P.Swatch
ruleSwatch env rule = do
  name <- rsColor rule
  Swatch (c, m, y, k) <- Map.lookup name (stSwatches style)
  pure (P.Swatch c m y k)
  where
    style = piStyle (deInput env)

{- the rule before the footnotes from grid line firstLine (golem-driver ADR
0024): without spaces through the middle of the em box of the line
before; with them space-after above the em box of the first
footnote line. From the start of the line of the column, its near
edge and far edge measured from the top (the right in vertical text). -}
noteRule :: DrawEnv -> Rect -> RuleSpec -> Int -> (Rect, Sp)
noteRule env ta rule firstLine =
  let p = pgLinePitch geom
      fs = pgFontSize geom
      w = rsWeight rule
      len = maybe 0 (dimToSp fs) (rsLength rule)
      far = case rsSpaceAfter rule of
        Nothing -> fromIntegral (firstLine - 1) * p + Sp (unSp fs `div` 2) - Sp (unSp w `div` 2)
        Just a -> fromIntegral firstLine * p - dimToSp fs a - w
   in if vertical
        then (Rect (rectX ta + rectW ta - far - w) (rectY ta + rectH ta - len) w len, w)
        else (Rect (rectX ta) (rectY ta + rectH ta - far - w) len w, w)
  where
    geom = deGeom env
    vertical = pgVertical (deGeom env)

{- the rules of a table on a page (golem-driver ADR 0008, 0031): c
outside the ink of the table, half the space between the ink of two
lines; in vertical text the ink is the em box -}
tableRules :: DrawEnv -> Rect -> TableSegment -> TableGeometry -> [(Rect, Sp)]
tableRules env ta seg tg =
  let p = pgLinePitch geom
      fs = pgFontSize geom
      (a, d)
        | vertical = (Sp (unSp fs `div` 2), fs - Sp (unSp fs `div` 2))
        | otherwise = (tgAscent tg, tgDescent tg)
      c = max 0 (Sp (unSp (p - a - d) `div` 2))
      base k = fromIntegral k * p + (if vertical then Sp (unSp fs `div` 2) else zwToSp fs baselineRatio)
      before k = base k - a - c
      after k = base k + d + c
      w = tgWidth tg
      rule cy t
        | vertical = (Rect (rectX ta + rectW ta - cy - Sp (unSp t `div` 2)) (rectY ta + rectH ta - w) t w, t)
        | otherwise = (Rect (rectX ta) (rectY ta + rectH ta - cy - Sp (unSp t `div` 2)) w t, t)
   in [rule (before (tsFirst seg)) thickRule] <> [rule (after e) thinRule | Just e <- [tsHeaderEnd seg]] <> [rule (after (tsLast seg)) thickRule]
  where
    geom = deGeom env
    vertical = pgVertical (deGeom env)

tableInk :: DrawEnv -> Int -> TableGeometry -> TableGeometry
tableInk env tid tg =
  let fs = pgFontSize geom
      inks =
        [ (toRational (unSp (guSize u)) * y1, toRational (unSp (guSize u)) * negate y0)
        | lid <- [tid .. tid + tgLines tg - 1],
          sl <- Map.findWithDefault [] lid (plTableLines layout),
          u <- snd (drawLineAt env (0, 0) sl),
          Just (_, y0, _, y1) <- [lfInkBox fonts (guFace u) (guGlyph u)]
        ]
      emA = zwToSp fs baselineRatio
   in if null inks
        then tg {tgAscent = emA, tgDescent = fs - emA}
        else tg {tgAscent = Sp (round (maximum (map fst inks))), tgDescent = Sp (round (maximum (map snd inks)))}
  where
    geom = deGeom env
    fonts = deFonts env
    layout = deLayout env

{- row j of the k rows of a code block from grid line slot: the area
starts half the leading above the grid line, and the rows are centred
in it (golem-driver ADR 0017) -}
codeRowAt :: DrawEnv -> Int -> CodeGeometry -> Int -> Int -> SetLine -> Sp
codeRowAt env slot g k j sl =
  let s = slSize sl
      areaTop = fromIntegral slot * pgLinePitch geom - Sp (unSp (pgLinePitch geom - pgFontSize geom) `div` 2)
      top = areaTop + codeRowsTop g k + fromIntegral j * cgPitch g
   in top + (if vertical then Sp (unSp s `div` 2) else zwToSp s baselineRatio)
  where
    geom = deGeom env
    vertical = pgVertical (deGeom env)

{- a part of a code block from grid line slot with k rows (golem-driver
ADR 0023): whether it is the first part, the grid line of its rows
(after the caption), the rows it is centred as and whether it ends
with the text that it continues -}
codePartOf :: Int -> Int -> Int -> CodeInfo -> (Bool, Int, Int, Bool)
codePartOf slot lid k ci =
  let isFirst = lid == ciFirst ci
      cont = isJust (ciContinued ci) && lid + k < ciFirst ci + ciRows ci
   in (isFirst, slot + (if isFirst then ciCaptionSpan ci else 0), k + (if cont then 1 else 0), cont)

-- line j of the caption of a code block: from the top of its grid line, j caption pitches on
codeCaptionLineAt :: DrawEnv -> Int -> CodeInfo -> Int -> Sp
codeCaptionLineAt env slot ci j =
  let cs = ciCaptionSize ci
      top = fromIntegral slot * pgLinePitch geom + fromIntegral (j :: Int) * ciCaptionPitch ci
   in top + (if vertical then Sp (unSp cs `div` 2) else zwToSp cs baselineRatio)
  where
    geom = deGeom env
    vertical = pgVertical (deGeom env)

-- the band of m rows from row j of the k rows of a part, a code pitch each, from start to the end of the line
codeBand :: DrawEnv -> Rect -> Int -> CodeGeometry -> Int -> Int -> Int -> Sp -> Rect
codeBand env ta slot g k j m start =
  let p = pgLinePitch geom
      areaTop = fromIntegral slot * p - Sp (unSp (p - pgFontSize geom) `div` 2)
      top = areaTop + codeRowsTop g k + fromIntegral j * cgPitch g - Sp (unSp (cgPitch g - cgSize g) `div` 2)
      depth = fromIntegral m * cgPitch g
      measure = if vertical then rectH ta else rectW ta
   in if vertical
        then Rect (rectX ta + rectW ta - top - depth) (rectY ta + rectH ta - measure) depth (measure - start)
        else Rect (rectX ta + start) (rectY ta + rectH ta - top - depth) (measure - start) depth
  where
    geom = deGeom env
    vertical = pgVertical (deGeom env)

-- the lines of a border of width t, centred on the sides of a rectangle
borderRects :: Rect -> Sp -> [Rect]
borderRects (Rect x y w h) t =
  let half = Sp (unSp t `div` 2)
   in [Rect (x - half) (y + h - half) (w + t) t, Rect (x - half) (y - half) (w + t) t, Rect (x - half) (y - half) t (h + t), Rect (x + w - half) (y - half) t (h + t)]

-- the area of a code block of n grid lines from grid line slot, from start to the end of the line
codeRect :: DrawEnv -> Rect -> Int -> Int -> Sp -> Rect
codeRect env ta slot n start =
  let p = pgLinePitch geom
      areaTop = fromIntegral slot * p - Sp (unSp (p - pgFontSize geom) `div` 2)
      across = fromIntegral n * p
      measure = if vertical then rectH ta else rectW ta
   in if vertical
        then Rect (rectX ta + rectW ta - areaTop - across) (rectY ta + rectH ta - measure) across (measure - start)
        else Rect (rectX ta + start) (rectY ta + rectH ta - areaTop - across) (measure - start) across
  where
    geom = deGeom env
    vertical = pgVertical (deGeom env)

-- line j of a heading block from grid line k (golem-driver ADR 0003)
headingLineAt :: DrawEnv -> Int -> HeadingBlock -> Int -> SetLine -> Sp
headingLineAt env k hb j sl =
  let s = slSize sl
      top = fromIntegral k * pgLinePitch geom + hbOffset hb + fromIntegral j * hbPitch hb
   in top + (if vertical then Sp (unSp s `div` 2) else zwToSp s baselineRatio)
  where
    geom = deGeom env
    vertical = pgVertical (deGeom env)

placedFigures :: PageOut -> [(Int, Int)]
placedFigures p = [(slot, fid) | (slot, s) <- poSlots p, fid <- case s of SFigure f -> [f]; SWrapped f -> [f]; _ -> []]

{- line j of a caption: from the top of the grid line after the image,
j caption pitches on, at the top of its lines (golem-driver ADR 0010) -}
captionLineAt :: DrawEnv -> Int -> PlacedFigure -> Int -> Sp
captionLineAt env slot pf j =
  let cs = pfCaptionSize pf
      top = fromIntegral (slot + pfImageLines pf) * pgLinePitch geom + fromIntegral (j :: Int) * pfCaptionPitch pf
   in top + (if vertical then Sp (unSp cs `div` 2) else zwToSp cs baselineRatio)
  where
    geom = deGeom env
    vertical = pgVertical (deGeom env)

-- caption lines start where the image starts (golem-driver ADR 0005)
captionIndent :: DrawEnv -> Rect -> PlacedFigure -> Sp
captionIndent env ta pf
  | pfWrap pf == Just WrapEnd = (if vertical then rectH ta else rectW ta) - pfAlong pf
  | otherwise = 0
  where
    vertical = pgVertical (deGeom env)

-- each digit of a hidden folio, its advance centred on its point (golem-driver ADR 0021)
hiddenMarks :: DrawEnv -> Int -> [([P.Content], [GlyphUse])]
hiddenMarks env n =
  [ first (pure . P.Artifact P.Pagination) $
      runAtU env (SourceHiddenFolio, V.PartBase, styleSpan) (plainLook body size) False False 0 (cx - Sp (unSp w `div` 2), cy + Sp (unSp size `div` 2) - zwToSp size baselineRatio) txt
  | Just hg <- [pgHiddenFolio geom],
    let size = hgSize hg,
    (c, (cx, cy)) <- Map.findWithDefault [] n (deHidden env),
    let txt = T.singleton c
        w = sum [toSp size (shAdvance g) | g <- lfShape fonts (Shaping body False []) txt]
  ]
  where
    geom = deGeom env
    fonts = deFonts env
    body = bodyRole (piStyle (deInput env))
    styleSpan = mkSpan (piStyleFile (deInput env)) 0 0

masterMarks :: DrawEnv -> Int -> Bool -> Maybe MasterGeometry -> [Text] -> [(LineRec, ([P.Content], [GlyphUse]))]
masterMarks env n blank master headLines = case master of
  Nothing -> []
  Just m ->
    let pick a1 a2 = if odd n then a1 else a2
        size = pgFontSize geom
        folio = [textAt env "ノンブル" (pick a1 a2) size (formatNumber fmt [toInteger n] Nothing) | drawsFolio blank master, Just (fmt, a1, a2) <- [mgFolio m]]
        -- the lines of the running head from the type area out (golem-driver ADR 0022)
        runningHead =
          [ textAt env "柱" a {anY = hy} size h
          | not blank,
            Just (_, _, a1, a2) <- [mgRunningHead m],
            let a = pick a1 a2,
            (h, hy) <- zip headLines (runningHeadBaselines ph (pgLinePitch geom) a (length headLines))
          ]
     in runningHead <> folio
  where
    geom = deGeom env
    ph = snd (pgPageSize (deGeom env))

-- | The image of a figure: the content of its Figure (docs/adr ADR 0183).
figureMark :: DrawEnv -> Int -> Rect -> PlacedFigure -> P.Content
figureMark env fid r pf = P.Tagged (P.LeafId (figureSite (pfUnit pf) <> [0])) $ pure $ case pfContent pf of
  P.RasterFigure _ -> P.Image (P.ImageRef fid) r
  _ -> P.Form (Map.findWithDefault (P.FormRef 0) (pfSource pf, pfPage pf) (deFormRefs env)) r

-- | A line drawn as an artifact of a kind (docs/adr ADR 0183).
asArtifact :: P.ArtifactKind -> (LineRec, ([P.Content], [GlyphUse])) -> (LineRec, ([P.Content], [GlyphUse]))
asArtifact k (rec, (cs, us)) = (rec, ([P.Artifact k (concatMap P.contentMarks cs) | not (null cs)], us))

-- | A line whose boxes are all of one leaf.
withLeaf :: Leaf -> Line -> Line
withLeaf lf l = l {lineItems = [case it of Box w c -> Box w c {bcLeaf = lf}; x -> x | it <- lineItems l]}

-- | Groups of neighbours: a new group starts where the predicate fails between two neighbours.
groupWhen :: (a -> a -> Bool) -> [a] -> [[a]]
groupWhen same = foldr step []
  where
    step x = \case
      (g@(y : _) : gs) | same x y -> (x : g) : gs
      gs -> [x] : gs
