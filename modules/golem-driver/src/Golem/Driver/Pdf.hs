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
    noFontProvider,
    bodyRole,
    usedRoles,
    PdfInput (..),
    SetLine (..),
    PlacedFigure (..),
    PdfLayout (..),
    layoutPdf,
    figureRect,
    renderPdf,
    pdfFileName,
  )
where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (evaluate)
import Control.Monad (join)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAlphaNum, isAscii)
import Data.Either (fromRight, isLeft)
import Data.List (groupBy, nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (toGregorian)
import Golem.Doc.Assemble
import Golem.Doc.IR
import Golem.Doc.Numerals (formatNumber)
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass hiding (Sp)
import Golem.Layout.Look
import Golem.Layout.Paginate
import Golem.Layout.Wrap (Exclusion (..), exclusion, wrappedLineWidth)
import Golem.LayoutSpec (Anchor (..), MasterGeometry (..), PageGeometry (..), Rect (..), baselineRatio, pageGeometry, typeAreaFor)
import Golem.LayoutSpec qualified as LS
import Golem.Pdf qualified as P
import Golem.Project
import Golem.Project.Style
import Golem.Syntax
import System.FilePath (takeBaseName)

{- | Fonts ready for layout and output. Advances are in em. The first
argument of the measuring and shaping functions is the font role
(golem-driver ADR 0003); a role that is not loaded is the body role.
-}
data LoadedFonts = LoadedFonts
  { lfAdvance :: Text -> Char -> Rational,
    -- | a Latin word as shaped (kerning, ligatures)
    lfWordAdvance :: Text -> Text -> Rational,
    {- | shaping: for each glyph the face number, glyph id, advance in em
    (downwards when vertical) and the text it stands for
    -} lfShape :: Text -> Bool -> Text -> [(Int, Int, Rational, Text)],
    -- | the character code of a glyph in the PDF (its CID in a CID-keyed font)
    lfCode :: Int -> Int -> Int,
    {- | the embedded (subset) font of a face number, for horizontal or
    vertical use, with the glyphs used and their text
    -} lfEmbed :: Int -> Bool -> [(Int, Text)] -> P.Font
  }

newtype FontProvider = FontProvider
  { loadFonts :: FilePath -> Style -> IO (Either [Diagnostic] LoadedFonts)
  }

noFontProvider :: FontProvider
noFontProvider =
  FontProvider $ \_ _ ->
    pure (Left [diagnostic "G0801" Error (mkSpan (FileId 0) 0 0) "フォントの処理（golem-font ADR 0001、0002）が未実装のため、PDF を出力できません"])

data PdfInput = PdfInput
  { piRoot :: !FilePath,
    piProject :: !Project,
    piStyle :: !Style,
    piBook :: !Book,
    piParallel :: !Bool,
    -- | bytes of every input, for the instance ID
    piInputs :: ![ByteString]
  }

-- | The body font role: @body@, or the first role when there is none.
bodyRole :: Style -> Text
bodyRole style
  | Map.member "body" (stFonts style) = "body"
  | otherwise = maybe "body" fst (Map.lookupMin (stFonts style))

{- | The font roles the PDF uses, body first, then the others by name:
headings (golem-driver ADR 0003), bold, italic and character styles
(ADR 0004).
-}
usedRoles :: Style -> [Text]
usedRoles style =
  let body = bodyRole style
      named =
        [f | HeadingStyle {hsFont = Just f} <- Map.elems (stHeadings style)]
          <> maybe [] pure (stBoldFont style)
          <> maybe [] pure (stItalicFont style)
          <> [f | CharStyleDef {csFont = Just f} <- Map.elems (stCharStyles style)]
      others = Set.toAscList (Set.delete body (Set.fromList named))
   in body : others

{- | The look inside an inline element (golem-driver ADR 0004): strong as
bold or italic, bold and italic in their roles or synthetic, character
styles' role and size, and colour. The inner setting wins; the rest is
inherited.
-}
restyle :: Style -> Look -> Inline -> Look
restyle style lk = \case
  Strong {} -> if stStrongAs style == "italic" then italic else bold
  Bold {} -> bold
  Italic {} -> italic
  CharStyle _ name _ -> case Map.lookup name (stCharStyles style) of
    Just cs ->
      let lk1 = maybe lk (\f -> lk {lkFace = f, lkLatinFace = f}) (csFont cs)
       in maybe lk1 (\d -> lk1 {lkSize = dimToSp (lkSize lk) d}) (csSize cs)
    Nothing -> lk
  Color _ sw _ -> lk {lkColor = Just sw}
  _ -> lk
  where
    bold = maybe lk {lkEmbolden = True} (\f -> lk {lkFace = f, lkLatinFace = f}) (stBoldFont style)
    italic = case stItalicFont style of
      Nothing -> lk {lkSlant = True}
      Just f ->
        let fr = Map.lookup f (stFonts style)
            hasJa = isJust (fr >>= frJa)
            hasLatin = isJust (fr >>= frLatin)
         in lk
              { lkFace = if hasJa then f else lkFace lk,
                lkLatinFace = if hasLatin then f else lkLatinFace lk,
                -- the side the role does not cover is slanted
                lkSlant = lkSlant lk || not (hasJa && hasLatin)
              }

-- | The slant of synthetic italic: 1/5, about 11.3 degrees (golem-driver ADR 0004).
syntheticSlant :: Rational
syntheticSlant = 1 / 5

-- | The outline stroke of synthetic bold: 1/40 of the size.
syntheticStroke :: Sp -> Sp
syntheticStroke size = size `div` 40

-- | The role and size of the headings of a level (golem-driver ADR 0003).
headingFace :: Style -> PageGeometry -> Int -> (Text, Sp)
headingFace style geom level =
  let hs = Map.lookup level (stHeadings style)
      fs = pgFontSize geom
   in (fromMaybe (bodyRole style) (hs >>= hsFont), maybe fs (dimToSp fs) (hs >>= hsSize))

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
    slNotes :: ![(Int, [Line])]
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
    -- | the exclusion area of a wrapped figure
    pfExclusion :: !(Maybe Exclusion)
  }

-- | The result of the layout, read by the writer and the tests.
data PdfLayout = PdfLayout
  { plPages :: ![PageOut],
    plLines :: !(Map Int SetLine),
    plFigures :: !(Map Int PlacedFigure),
    -- | heading blocks by their first line (golem-driver ADR 0003)
    plHeadings :: !(Map Int HeadingBlock)
  }

data Built = Built
  { bFlow :: [Flow],
    bLines :: Map Int SetLine,
    bFigures :: Map Int PlacedFigure,
    -- | heading blocks by their first line
    bHeadings :: Map Int HeadingBlock,
    -- | errors found while building (G0722, G0723, G0724)
    bErrors :: [Diagnostic]
  }

renderPdf :: FontProvider -> PdfInput -> IO (Either [Diagnostic] ByteString)
renderPdf provider inp = case pageGeometry (piStyle inp) of
  Left ds -> pure (Left ds)
  Right geom -> do
    lf <- loadFonts provider (piRoot inp) (piStyle inp)
    case lf of
      Left ds -> pure (Left ds)
      Right fonts -> do
        result <- layoutPdf inp geom fonts
        case result of
          Left ds -> pure (Left ds)
          Right layout -> do
            intent <- loadIntent inp
            pure (Right (writeDocument inp geom fonts layout intent))

-- | Composition, line breaking and pagination, with page references resolved (S2).
layoutPdf :: PdfInput -> PageGeometry -> LoadedFonts -> IO (Either [Diagnostic] PdfLayout)
layoutPdf inp geom fonts = do
  figures <- loadFigures inp
  -- S2: compose with assumed page numbers until they settle
  result <- fixpoint geom (buildFlow inp geom fonts figures)
  pure $ case result of
    Left ds -> Left ds
    Right (built, pages) -> Right (PdfLayout pages (bLines built) (bFigures built) (bHeadings built))

fixpoint :: PageGeometry -> (Map Text Integer -> IO Built) -> IO (Either [Diagnostic] (Built, [PageOut]))
fixpoint geom layoutWith = go (1 :: Int) Map.empty
  where
    capacity = length (pgLineGrid geom)
    go i assumed = do
      built <- layoutWith assumed
      let pages = paginate capacity (bFlow built)
          actual = labelPages pages
      if not (null (bErrors built))
        then pure (Left (bErrors built))
        else
          if actual == assumed
            then pure (Right (built, pages))
            else
              if i >= maxIterations
                then pure (Left [diagnostic "G0721" Error (mkSpan (FileId 0) 0 0) ("ページ番号の参照が収束しません: " <> T.intercalate ", " (Map.keys (Map.filter id (Map.unionWith (/=) (Map.map (const True) actual) (Map.map (const False) assumed)))))])
                else go (i + 1) actual

{- | The composition environment of a unit set in a font role at a size
(golem-driver ADR 0003).
-}
composeEnv :: Style -> PageGeometry -> LoadedFonts -> Map Text Integer -> Text -> Sp -> ComposeEnv
composeEnv style geom fonts assumed role fs =
  let comp = stComposition style
   in (defaultComposeEnv fs)
        { ceAdvance = \look c -> lfAdvance fonts (if charClass c == Western then lkLatinFace look else lkFace look) c,
          ceWordAdvance = lfWordAdvance fonts . lkLatinFace,
          ceLook = plainLook role fs,
          ceRestyle = restyle style,
          ceVertical = pgVertical geom,
          ceKinsokuStrict = compKinsokuStrict comp,
          ceHanging = compHanging comp,
          ceProtrusion = compProtrusion comp,
          ceRubyOverhang = dimToSp fs (compRubyOverhang comp),
          ceVerticalNumbers = case stNumbersVertical style of
            "kanji-digits" -> Just StyleKanjiDigits
            "tcy" -> Just StyleTcy
            _ -> Just StyleKanji,
          cePageOf = (`Map.lookup` assumed),
          -- Latin words: US English patterns (golem-layout ADR 0001)
          cePatterns = Just englishUS
        }

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

-- | A paragraph unit to break: the inlines and a prefix (list markers).
data Unit = Unit
  { uKind :: UnitKind,
    uLabel :: Maybe Text,
    uInlines :: [Inline],
    -- | the block the unit comes from, for diagnostics
    uSpan :: SrcSpan
  }

data UnitKind = UPara | UHeading Int Text Bool | UTerm | UFigure Figure

unitsOf :: Book -> PageGeometry -> Style -> [Unit]
unitsOf book _ style = concatMap doc (bookDocs book)
  where
    sp0 = mkSpan (FileId 0) 0 0
    txt = Text sp0
    doc (Document _ bs) = concatMap block bs
    block (Block sp lbl body) = map ($ sp) $ case body of
      Paragraph is -> [Unit UPara lbl is]
      Heading l attrs is ->
        let num = Map.lookup sp (bookHeadings book) >>= hiNumberText
            title = maybe [] (\n -> [txt (n <> "　")]) (if haNoNumber attrs then Nothing else num) <> is
            recto = maybe False hsRectoBreak (Map.lookup l (stHeadings style))
         in [Unit (UHeading l (T.concat (map inlineText is)) recto) lbl title]
      BulletList items -> map const (concat [prefixFirst "・" (concatMap block (itemBlocks it)) | it <- items])
      OrderedList items -> map const (concat [prefixFirst (T.pack (show n) <> ". ") (concatMap block (itemBlocks it)) | (n, it) <- zip [1 :: Integer ..] items])
      DefList gs -> map const (concat [[Unit UTerm Nothing t sp | t <- dgTerms g] <> concatMap (concatMap block) (dgDefs g) | g <- gs])
      Table _ h rows -> [Unit UPara lbl (cells r) | r <- h : rows]
      CodeBlock _ code -> [Unit UPara lbl [txt l] | l <- T.lines code]
      FigureBlock fig -> [Unit (UFigure fig) lbl []]
      ChannelOutput (TocOutput depth) -> [Unit UPara Nothing (maybe [] (\n -> [txt (n <> "　")]) (teNumber e) <> teTitle e) | e <- bookToc book, teLevel e <= depth]
      ChannelOutput _ -> []
    cells r = concat [c <> [txt "　"] | c <- r]
    prefixFirst p (Unit UPara l is s' : rest) = Unit UPara l (txt p : is) s' : rest
    prefixFirst _ us = us

-- | A unit composed and broken into lines.
data Composed = Composed
  { cLines :: [Line],
    cNotes :: [(Int, [Line])],
    cAnchors :: [Golem.Layout.Japanese.Anchor],
    cItems :: [Item]
  }

buildFlow :: PdfInput -> PageGeometry -> LoadedFonts -> Map Text (Maybe P.ImageData) -> Map Text Integer -> IO Built
buildFlow inp geom fonts images assumed = do
  let style = piStyle inp
      body = bodyRole style
      fs = pgFontSize geom
      pitch = pgLinePitch geom
      capacity = length (pgLineGrid geom)
      vertical = pgVertical geom
      bodyEnv = composeEnv style geom fonts assumed body fs
      params = kpParams style geom
      measure = case pgColumns geom of
        (c : _) -> if vertical then rectH c else rectW c
        [] -> 0
      units = zip [0 :: Int ..] (unitsOf (piBook inp) geom style)
      unitAt = Map.fromList units
      -- the role and size a unit is set in
      faceOf u = case uKind u of
        UHeading l _ _ -> headingFace style geom l
        _ -> (body, fs)
      compose lineWidth u =
        let (role, size) = faceOf u
            env = composeEnv style geom fonts assumed role size
            (items, anchors) = composeInlines env (uInlines u)
            lines' = brLines (breakParagraph params lineWidth items)
            notes = [(n, brLines (breakParagraph params (const measure) (fst (composeInlines bodyEnv nbody)))) | AnchorNote _ n nbody <- anchors]
         in Composed lines' notes anchors items
      force c = evaluate (length (show (map lineRatio (cLines c))) + length (cNotes c) + length (cAnchors c) + length (cItems c)) >> pure c
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
            captionInlines = maybe [] (\num -> [Text (uSpan u) (num <> "　")]) number <> concat [is | Block _ _ (Paragraph is) <- figCaption fig]
            caption = if null captionInlines then [] else brLines (breakParagraph params (const alongSp) (fst (composeInlines bodyEnv captionInlines)))
            n = length caption
            depth = if n > 0 then toInteger (m + n - 1) * pitch + fs else across
            gap = dimToSp fs (stWrapGap style)
            ex = (\side -> exclusion side pitch gap alongSp depth) <$> figWrap fig
            errs = case (figWrap fig, ex) of
              (Just _, Just e)
                | isLeft along || measure - exWidth e < 8 * fs ->
                    [diagnostic "G0722" Error (uSpan u) ("回り込む図版の幅が不正です。寸法で書き、行の残りを本文の 8 字分以上にしてください: " <> fromMaybe "" (figWidth fig))]
                | exLines e > capacity -> [diagnostic "G0723" Error (uSpan u) ("回り込む図版の除外領域が一ページの行数を超えます（" <> T.pack (show (exLines e)) <> " 行）")]
              _ -> []
         in (PlacedFigure img alongSp across (figWrap fig) m caption ex, errs)
      figures = Map.fromList [(i, f) | (i, u@Unit {uKind = UFigure fig}) <- units, Just f <- [figureOf u fig]]
      -- 1. a job per wrapped figure: the paragraphs right after it, in order, beside the exclusion
      wrapJob i ex = go (i + 1) 0
        where
          go j offset
            | offset >= exLines ex = pure []
            | Just u@Unit {uKind = UPara} <- Map.lookup j unitAt = do
                c <- force (compose (wrappedLineWidth measure ex offset) u)
                ((j, (c, offset)) :) <$> go (j + 1) (offset + length (cLines c))
            | otherwise = pure []
      jobs = [(i, ex) | (i, (pf, [])) <- Map.toList figures, Just ex <- [pfExclusion pf]]
  besides <- Map.fromList . concat <$> mapper (uncurry wrapJob) jobs
  -- 2. every other unit on its own
  let rest = [(i, u) | (i, u) <- units, Map.notMember i besides, not (isFigure u)]
      isFigure u = case uKind u of
        UFigure _ -> True
        _ -> False
  _ <- mapper (\(_, (pf, _)) -> evaluate (length (show (map lineRatio (pfCaption pf))))) (Map.toList figures)
  singles <- Map.fromList . zip (map fst rest) <$> mapper (force . compose (const measure) . snd) rest
  -- 3. number the lines in document order
  let label u = maybe [] pure (uLabel u)
      -- the lines of a paragraph-like unit from an id; indent of line k
      numbered nextId u c indentOf =
        let ls = cLines c
            ids = [nextId .. nextId + length ls - 1]
            (_, size) = faceOf u
            -- notes belong to the line containing their anchor
            lineOfItem = lineIndexOfItems (cItems c) ls
            noteLines = Map.fromListWith (<>) [(lineOfItem i, [(n, nls)]) | (AnchorNote i n _, (_, nls)) <- zip [a | a@AnchorNote {} <- cAnchors c] (cNotes c)]
            boxes = [LineBox lid [NoteBody n (length nls) | (n, nls) <- Map.findWithDefault [] k noteLines] (if k == 0 then label u else []) | (k, lid) <- zip [0 ..] ids]
            set = Map.fromList [(lid, SetLine l size (indentOf k) (Map.findWithDefault [] k noteLines)) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
         in (boxes, set)
      step st@(nextId, flows, lineAcc, figAcc, headAcc, errs) (i, u)
        | Map.member i besides = st -- set beside its figure
        | otherwise = case uKind u of
            UFigure _ -> case Map.lookup i figures of
              Nothing -> st
              Just (pf, ferrs) -> case pfExclusion pf of
                Just ex
                  | null ferrs ->
                      -- the figure and the lines beside it; the rest of a paragraph cut short continues
                      let paras = [(j, c, off) | j <- takeWhile (`Map.member` besides) [i + 1 ..], let (c, off) = besides Map.! j]
                          indentOf off k = if pfWrap pf == Just WrapStart && off + k < exLines ex then exWidth ex else 0
                          go (nid, boxAcc, setAcc) (j, c, off) =
                            let (bs, set) = numbered nid (unitAt Map.! j) c (indentOf off)
                             in (nid + length (cLines c), boxAcc <> bs, Map.union setAcc set)
                          (nextId', allBoxes, sets) = foldl go (nextId + 1, [], Map.empty) paras
                          (beside, continued) = splitAt (exLines ex) allBoxes
                       in ( nextId',
                            flows <> [FWrapped nextId (exLines ex) (label u) beside] <> [FContinued continued | not (null continued)],
                            Map.union lineAcc sets,
                            Map.insert nextId pf figAcc,
                            headAcc,
                            errs
                          )
                _ -> (nextId + 1, flows <> [FFigure nextId (pfImageLines pf + length (pfCaption pf)) (label u)], lineAcc, Map.insert nextId pf figAcc, headAcc, errs <> ferrs)
            _ ->
              let c = singles Map.! i
                  ls = cLines c
                  (boxes, set) = numbered nextId u c (const 0)
                  (_, size) = faceOf u
                  hb = headingBlock fs pitch size (length ls)
                  flowOf = case uKind u of
                    UHeading l short recto -> [FHeading l short recto (hbSpan hb) boxes]
                    UTerm -> [FDefTerm boxes]
                    _ -> [FParagraph boxes]
                  (headAcc', errs') = case uKind u of
                    UHeading l short _ ->
                      ( Map.insert nextId hb headAcc,
                        errs <> [diagnostic "G0724" Error (uSpan u) ("見出しが版面に入りません（" <> T.pack (show l) <> " の見出し: " <> short <> "）") | hbSpan hb > capacity]
                      )
                    _ -> (headAcc, errs)
               in (nextId + length ls, flows <> flowOf, Map.union lineAcc set, figAcc, headAcc', errs')
      (_, flow, lineMap, figMap, headMap, errors) = foldl step (0, [], Map.empty, Map.empty, Map.empty, []) units
  pure (Built flow lineMap figMap headMap errors)

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

loadIntent :: PdfInput -> IO (Maybe P.PdfX)
loadIntent inp = case stIntent (piStyle inp) of
  Nothing -> pure Nothing
  Just path -> do
    bytes <- BS.readFile (piRoot inp <> "/" <> path)
    let md = manifestMetadata (projectManifest (piProject inp))
        condition = if "JapanColor2001Coated" `T.isInfixOf` T.pack path then "JC200103" else T.pack (takeBaseName path)
    pure (Just (P.PdfX bytes condition [crName c | c <- mdCreators md]))

-- ------------------------------------------------------------------ drawing

writeDocument :: PdfInput -> PageGeometry -> LoadedFonts -> PdfLayout -> Maybe P.PdfX -> ByteString
writeDocument inp geom fonts layout intent =
  let md = manifestMetadata (projectManifest (piProject inp))
      (pw, ph) = pgPageSize geom
      pageRect = Rect 0 0 pw ph
      vertical = pgVertical geom
      master = case Map.elems (pgMasters geom) of
        (m : _) -> Just m
        [] -> Nothing
      grid = pgLineGrid geom
      gridAt sl = case drop sl grid of
        (g : _) -> g
        [] -> 0
      -- font index × direction: even refs horizontal, odd refs vertical
      ref ix v = P.FontRef (2 * ix + (if v then 1 else 0))
      toSp size a = round (a * toRational size) :: Integer
      style = piStyle inp
      body = bodyRole style
      isLatin = (== Western) . charClass
      -- the role of a run of text in a look: Latin or Japanese (golem-driver ADR 0004)
      runsOf look txt
        | lkFace look == lkLatinFace look = [(lkFace look, txt)]
        | otherwise = [(if isLatin (T.head r) then lkLatinFace look else lkFace look, r) | r <- T.groupBy (\a b -> isLatin a == isLatin b) txt, not (T.null r)]
      -- synthetic slant applies where the italic role does not set the text
      slantedIn look role = lkSlant look && Just role /= stItalicFont style
      -- glyph marks of a text in a look starting at a point, and the glyphs used
      runAt look v rotated scale (x0, y0) txt =
        let size = lkSize look
            gs = concat [[(ix, g, a, t, slantedIn look role) | (ix, g, a, t) <- lfShape fonts role (v && not rotated) r] | (role, r) <- runsOf look txt]
            advs = scanl (+) 0 [toSp size a | (_, _, a, _, _) <- gs]
            placed = [(ix, g, t, sl, off) | ((ix, g, _, t, sl), off) <- zip gs advs]
            byFont = Map.fromListWith (flip (<>)) [((ix, sl), [(g, t, off)]) | (ix, g, t, sl, off) <- placed]
            at off = if v then (x0, y0 - off) else (x0 + off, y0)
            mark (ix, sl) xs
              | sl || lkEmbolden look =
                  let rs = P.RunStyle (if v then 1000 else 1000 + scale) (v && rotated) (if sl then syntheticSlant else 0) (if lkEmbolden look then syntheticStroke size else 0)
                   in P.StyledGlyphRun rs (ref ix (v && not rotated)) size [(code ix g, gx, gy) | (g, _, off) <- xs, let (gx, gy) = at off]
              | v && rotated = P.RotatedGlyphRun (ref ix False) size [(code ix g, x0, y0 - off) | (g, _, off) <- xs]
              | v = P.GlyphRun (ref ix True) size [(code ix g, x0, y0 - off) | (g, _, off) <- xs]
              | scale /= 0 = P.ScaledGlyphRun (ref ix False) size (1000 + scale) [(code ix g, x0 + off, y0) | (g, _, off) <- xs]
              | otherwise = P.GlyphRun (ref ix False) size [(code ix g, x0 + off, y0) | (g, _, off) <- xs]
            code = lfCode fonts
         in ([mark k xs | (k, xs) <- Map.toList byFont], [(ref ix (v && not rotated), g, t) | (ix, g, t, _, _) <- placed])
      -- the swatch of a look, when it names one (golem-driver ADR 0004)
      swatchOf look = do
        name <- lkColor look
        Swatch (cc, cm, cy, ck) <- Map.lookup name (stSwatches style)
        pure (P.Swatch cc cm cy ck)
      -- a line at a distance across the type area: the baseline from its
      -- top edge, or the centre line from its right edge
      drawLine ta cross sl =
        let l = slLine sl
            origin off0
              | vertical = (rectX ta + rectW ta - cross, rectY ta + rectH ta - off)
              | otherwise = (rectX ta + off, rectY ta + rectH ta - cross)
              where
                off = off0 + slIndent sl
            advance look t = sum [toSp (lkSize look) a | (role, r) <- runsOf look t, (_, _, a, _) <- lfShape fonts role (vertical && not (T.all isLatin r)) r]
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
                      KindRuby ->
                        -- the base centred in the box, the reading at half size beside it
                        let (base, reading) = T.breakOn "|" (bcText c)
                            rt = T.drop 1 reading
                            rsize = lkSize half
                            baseStart = off + (w - advance look base) `div` 2
                            readStart = off + (w - advance half rt) `div` 2
                            (bx, by) = origin baseStart
                            (b1, u1) = runAt look vertical False 0 (bx, by) base
                            (b2, u2) = runAt half vertical False 0 (beside (origin readStart) (if vertical then size `div` 2 + rsize `div` 2 else size)) rt
                         in (b1 <> b2, u1 <> u2)
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
              Penalty hw _ True
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
        let w = sum [toSp size a | (_, _, a, _) <- lfShape fonts body False txt]
            x0 = case anAlign anchor of
              LS.AlignStart -> anX anchor
              LS.AlignCenter -> anX anchor - w `div` 2
              LS.AlignEnd -> anX anchor - w
         in runAt (plainLook body size) False False 0 (x0, anY anchor) txt
      drawPage p =
        let n = poNumber p
            ta = typeAreaFor geom n
            lineParts =
              [drawLine ta (gridAt slot) sl | (slot, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines layout)]]
                <> [ drawLine ta (headingLineAt slot hb j sl) sl
                   | (slot, SHeading lid m) <- poSlots p,
                     Just hb <- [Map.lookup lid (plHeadings layout)],
                     (j, Just sl) <- [(j, Map.lookup (lid + j) (plLines layout)) | j <- [0 .. m - 1]]
                   ]
                <> [ drawLine ta (gridAt (slot + pfImageLines pf + j)) (SetLine l (pgFontSize geom) (captionIndent ta pf) [])
                   | (slot, fid) <- placedFigures p,
                     Just pf <- [Map.lookup fid (plFigures layout)],
                     (j, l) <- zip [0 ..] (pfCaption pf)
                   ]
            figMarks = [P.Image (P.ImageRef fid) (figureRect geom ta slot pf) | (slot, fid) <- placedFigures p, Just pf <- [Map.lookup fid (plFigures layout)]]
            noteLines = concat [take cnt (drop from (concat [ls | sl <- Map.elems (plLines layout), (nid', ls) <- slNotes sl, nid' == nid])) | (nid, from, cnt) <- poFootnotes p]
            bottomSlots = drop (length grid - length noteLines) [0 .. length grid - 1]
            noteParts = [drawLine ta (gridAt slot) (SetLine l (pgFontSize geom) 0 []) | (slot, l) <- zip bottomSlots noteLines]
            masterParts = if poBlank p then [] else masterMarks n (poRunningHead p)
            allParts = lineParts <> noteParts <> masterParts
         in (concatMap fst allParts <> figMarks, concatMap snd allParts)
      -- line j of a heading block from grid line k (golem-driver ADR 0003)
      headingLineAt k hb j sl =
        let s = slSize sl
            top = toInteger k * pgLinePitch geom + hbOffset hb + toInteger j * hbPitch hb
         in top + (if vertical then s `div` 2 else round (toRational s * baselineRatio))
      placedFigures p = [(slot, fid) | (slot, s) <- poSlots p, fid <- case s of SFigure f -> [f]; SWrapped f -> [f]; _ -> []]
      -- caption lines start where the image starts (golem-driver ADR 0005)
      captionIndent ta pf
        | pfWrap pf == Just WrapEnd = (if vertical then rectH ta else rectW ta) - pfAlong pf
        | otherwise = 0
      masterMarks n heading = case master of
        Nothing -> []
        Just m ->
          let pick (_, a1, a2) = if odd n then a1 else a2
              size = pgFontSize geom
              folio = [textAt (pick f) size (formatNumber fmt [toInteger n] Nothing) | f@(fmt, _, _) <- maybe [] pure (mgFolio m)]
              runningHead = [textAt (pick r) size h | r <- maybe [] pure (mgRunningHead m), Just h <- [heading]]
           in runningHead <> folio
      drawn = map drawPage (plPages layout)
      pdfPages = [P.Page pageRect pageRect pageRect marks | (marks, _) <- drawn]
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
            P.docInstanceId = P.instanceId (piInputs inp <> programs <> [TE.encodeUtf8 "golem-0.1.0.0"]),
            P.docPdfX = intent
          }
   in P.writePdf doc
