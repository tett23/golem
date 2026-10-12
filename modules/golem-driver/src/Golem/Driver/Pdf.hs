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
    PdfInput (..),
    renderPdf,
    flowLines,
    pdfFileName,
  )
where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (evaluate)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAlphaNum, isAscii)
import Data.List (intercalate, nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
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
import Golem.Layout.Paginate
import Golem.LayoutSpec (Anchor (..), MasterGeometry (..), PageGeometry (..), Rect (..), pageGeometry, typeAreaFor)
import Golem.LayoutSpec qualified as LS
import Golem.Pdf qualified as P
import Golem.Project
import Golem.Project.Style
import Golem.Syntax
import System.FilePath (takeBaseName)

-- | Fonts ready for layout and output. Advances are in em.
data LoadedFonts = LoadedFonts
  { lfAdvance :: Char -> Rational,
    -- | a Latin word as shaped (kerning, ligatures)
    lfWordAdvance :: Text -> Rational,
    {- | shaping: for each glyph the font index, glyph id, advance in em
    (downwards when vertical) and the text it stands for
    -} lfShape :: Bool -> Text -> [(Int, Int, Rational, Text)],
    -- | the character code of a glyph in the PDF (its CID in a CID-keyed font)
    lfCode :: Int -> Int -> Int,
    {- | the embedded (subset) font of a font index, for horizontal or
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

-- | The file name of the PDF, from the book's identifier.
pdfFileName :: Text -> FilePath
pdfFileName bookId =
  let clean = T.map (\c -> if isAscii c && isAlphaNum c then c else '-') bookId
   in T.unpack (T.dropAround (== '-') clean) <> ".pdf"

-- ------------------------------------------------------------------ flow

-- One line of the flow, with what is needed to draw it.
data SetLine = SetLine
  { slLine :: !Line,
    slSize :: !Sp,
    slNotes :: ![(Int, [Line])],
    -- | where the line starts, from the start of the measure
    slIndent :: !Sp
  }

data Built = Built
  { bFlow :: [Flow],
    bLines :: Map Int SetLine,
    bFigures :: Map Int (P.ImageData, Sp, Sp)
  }

renderPdf :: FontProvider -> PdfInput -> IO (Either [Diagnostic] ByteString)
renderPdf provider inp = case pageGeometry (piStyle inp) of
  Left ds -> pure (Left ds)
  Right geom -> do
    lf <- loadFonts provider (piRoot inp) (piStyle inp)
    case lf of
      Left ds -> pure (Left ds)
      Right fonts -> do
        figures <- loadFigures inp
        let layoutWith = buildFlow inp geom fonts figures
        -- S2: compose with assumed page numbers until they settle
        result <- fixpoint geom layoutWith
        case result of
          Left ds -> pure (Left ds)
          Right (built, pages) -> do
            intent <- loadIntent inp
            pure (Right (writeDocument inp geom fonts built pages intent))

{- | The flow and its lines as (line length, indent), in order, laid out
with no page numbers assumed (for tests).
-}
flowLines :: FontProvider -> PdfInput -> IO (Either [Diagnostic] ([Flow], [(Sp, Sp)]))
flowLines provider inp = case pageGeometry (piStyle inp) of
  Left ds -> pure (Left ds)
  Right geom -> do
    lf <- loadFonts provider (piRoot inp) (piStyle inp)
    case lf of
      Left ds -> pure (Left ds)
      Right fonts -> do
        figures <- loadFigures inp
        built <- buildFlow inp geom fonts figures Map.empty
        pure (Right (bFlow built, [(lineTarget (slLine sl), slIndent sl) | sl <- Map.elems (bLines built)]))

fixpoint :: PageGeometry -> (Map Text Integer -> IO Built) -> IO (Either [Diagnostic] (Built, [PageOut]))
fixpoint geom layoutWith = go (1 :: Int) Map.empty
  where
    capacity = length (pgLineGrid geom)
    go i assumed = do
      built <- layoutWith assumed
      let pages = paginate capacity (bFlow built)
          actual = labelPages pages
      if actual == assumed
        then pure (Right (built, pages))
        else
          if i >= maxIterations
            then pure (Left [diagnostic "G0721" Error (mkSpan (FileId 0) 0 0) ("ページ番号の参照が収束しません: " <> T.intercalate ", " (Map.keys (Map.filter id (Map.unionWith (/=) (Map.map (const True) actual) (Map.map (const False) assumed)))))])
            else go (i + 1) actual

composeEnv :: Style -> PageGeometry -> LoadedFonts -> Map Text Integer -> ComposeEnv
composeEnv style geom fonts assumed =
  let comp = stComposition style
      fs = pgFontSize geom
   in (defaultComposeEnv fs)
        { ceAdvance = lfAdvance fonts,
          ceWordAdvance = lfWordAdvance fonts,
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
    uInlines :: [Inline]
  }

data UnitKind
  = UPara
  | UHeading Int Text Bool
  | UTerm
  | UFigure Figure
  | -- | a line of verse: the indent and the hang in sp (docs/adr ADR 0003)
    UVerseLine Sp Sp
  | -- | grid lines between stanzas
    UGap Int

unitsOf :: Book -> PageGeometry -> Style -> [Unit]
unitsOf book geom style = concatMap doc (bookDocs book)
  where
    sp0 = mkSpan (FileId 0) 0 0
    txt = Text sp0
    doc (Document _ bs) = concatMap block bs
    block (Block sp lbl body) = case body of
      Paragraph is -> [Unit UPara lbl is]
      Heading l attrs is ->
        let num = Map.lookup sp (bookHeadings book) >>= hiNumberText
            title = maybe [] (\n -> [txt (n <> "　")]) (if haNoNumber attrs then Nothing else num) <> is
            recto = maybe False hsRectoBreak (Map.lookup l (stHeadings style))
         in [Unit (UHeading l (T.concat (map inlineText is)) recto) lbl title]
      BulletList items -> concat [prefixFirst "・" (concatMap block (itemBlocks it)) | it <- items]
      OrderedList items -> concat [prefixFirst (T.pack (show n) <> ". ") (concatMap block (itemBlocks it)) | (n, it) <- zip [1 :: Integer ..] items]
      DefList gs -> concat [[Unit UTerm Nothing t | t <- dgTerms g] <> concatMap (concatMap block) (dgDefs g) | g <- gs]
      Table _ h rows -> [Unit UPara lbl (cells r) | r <- h : rows]
      CodeBlock _ code -> [Unit UPara lbl [txt l] | l <- T.lines code]
      FigureBlock fig -> [Unit (UFigure fig) lbl []]
      VerseBlock stanzas ->
        let vs = stVerse style
            fs = pgFontSize geom
            kind = UVerseLine (dimToSp fs (vsIndent vs)) (dimToSp fs (vsHang vs))
            stanzaUnits = [[Unit kind Nothing l | l <- st] | st <- stanzas]
            labelled = case intercalate [Unit (UGap (vsStanzaGap vs)) Nothing []] stanzaUnits of
              (u : us) -> u {uLabel = lbl} : us
              [] -> []
         in labelled
      ChannelOutput (TocOutput depth) -> [Unit UPara Nothing (maybe [] (\n -> [txt (n <> "　")]) (teNumber e) <> teTitle e) | e <- bookToc book, teLevel e <= depth]
      ChannelOutput _ -> []
    cells r = concat [c <> [txt "　"] | c <- r]
    prefixFirst p (Unit UPara l is : rest) = Unit UPara l (txt p : is) : rest
    prefixFirst _ us = us

buildFlow :: PdfInput -> PageGeometry -> LoadedFonts -> Map Text (Maybe (P.ImageData, Sp, Sp)) -> Map Text Integer -> IO Built
buildFlow inp geom fonts figures assumed = do
  let style = piStyle inp
      env = composeEnv style geom fonts assumed
      params = kpParams style geom
      measure = case pgColumns geom of
        (c : _) -> if pgVertical geom then rectH c else rectW c
        [] -> 0
      units = unitsOf (piBook inp) geom style
      -- L*(i): verse lines are shortened by the indent, and their continuations also by the hang
      widthOf = \case
        UVerseLine ind hang -> \i -> if i == 0 then measure - ind else measure - ind - hang
        _ -> const measure
      indentOf = \case
        UVerseLine ind hang -> \k -> if k == (0 :: Int) then ind else ind + hang
        _ -> const 0
      breakOne (UGap _) _ = ([], [], [], [])
      breakOne kind is =
        let (items, anchors) = composeInlines env is
            lines' = brLines (breakParagraph params (widthOf kind) items)
            notes = [(n, brLines (breakParagraph params (const measure) (fst (composeInlines env body)))) | AnchorNote _ n body <- anchors]
         in (lines', notes, anchors, items)
      force (ls, ns, as, is) = evaluate (length (show (map lineRatio ls)) + length ns + length as + length is) >> pure (ls, ns, as, is)
      mapper = if piParallel inp then mapConcurrently else mapM
  broken <- mapper (\u -> force (breakOne (uKind u) (uInlines u))) units
  -- number the lines in document order
  let step (nextId, flows, lineAcc, figAcc) (u, (ls, notes, anchors, items)) =
        let ids = [nextId .. nextId + length ls - 1]
            -- notes belong to the line containing their anchor
            lineOfItem = lineIndexOfItems items ls
            noteLines = Map.fromListWith (<>) [(lineOfItem i, [(n, nls)]) | (AnchorNote i n _, (_, nls)) <- zip [a | a@AnchorNote {} <- anchors] notes]
            boxes = [LineBox lid [NoteBody n (length nls) | (n, nls) <- Map.findWithDefault [] k noteLines] (if k == 0 then maybe [] pure (uLabel u) else []) | (k, lid) <- zip [0 ..] ids]
            set = Map.fromList [(lid, SetLine l (pgFontSize geom) (Map.findWithDefault [] k noteLines) (indentOf (uKind u) k)) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
            flowOf = case uKind u of
              UPara -> [FParagraph boxes]
              UHeading l short recto -> [FHeading l short recto boxes]
              UTerm -> [FDefTerm boxes]
              UVerseLine _ _ -> [FParagraph boxes]
              UGap n -> [FSpace n]
              UFigure fig -> case Map.lookup (figSource fig) figures of
                Just (Just (_, _, h)) ->
                  let pitch = pgLinePitch geom
                   in [FFigure nextId (fromInteger ((h + pitch - 1) `div` pitch)) (maybe [] pure (uLabel u))]
                _ -> []
            figAcc' = case uKind u of
              UFigure fig | Just (Just f) <- Map.lookup (figSource fig) figures -> Map.insert nextId f figAcc
              _ -> figAcc
            used = max (length ls) (case uKind u of UFigure _ -> 1; _ -> 0)
         in (nextId + used, flows <> flowOf, Map.union lineAcc set, figAcc')
      (_, flow, lineMap, figMap) = foldl step (0, [], Map.empty, Map.empty) (zip units broken)
  pure (Built flow lineMap figMap)

-- | Which line (0-based) contains the item at an index.
lineIndexOfItems :: [Item] -> [Line] -> Int -> Int
lineIndexOfItems _ ls i =
  let counts = scanl1 (+) (map (length . lineItems) ls)
   in length (takeWhile (<= i) counts) `min` max 0 (length ls - 1)

loadFigures :: PdfInput -> IO (Map Text (Maybe (P.ImageData, Sp, Sp)))
loadFigures inp = do
  let srcs = nub [figSource f | Document _ bs <- bookDocs (piBook inp), f <- figuresIn bs]
      fs = maybe 0 (dimToSp 0 . gridFontSize) (stPage (piStyle inp) >>= pageGrid)
      measure = maybe 0 (\g -> fs * toInteger (gridCharacters g)) (stPage (piStyle inp) >>= pageGrid)
  pairs <- mapM (\s -> (s,) <$> loadOne measure s) srcs
  pure (Map.fromList pairs)
  where
    figuresIn = concatMap (\(Block _ _ b) -> case b of FigureBlock f -> [f]; _ -> [])
    loadOne measure s = do
      bytes <- BS.readFile (piRoot inp <> "/" <> T.unpack s)
      pure $ case P.readImage bytes of
        Right img ->
          let w = measure
              h = w * toInteger (P.imgHeight img) `div` max 1 (toInteger (P.imgWidth img))
           in Just (img, w, h)
        Left _ -> Nothing

loadIntent :: PdfInput -> IO (Maybe P.PdfX)
loadIntent inp = case stIntent (piStyle inp) of
  Nothing -> pure Nothing
  Just path -> do
    bytes <- BS.readFile (piRoot inp <> "/" <> path)
    let md = manifestMetadata (projectManifest (piProject inp))
        condition = if "JapanColor2001Coated" `T.isInfixOf` T.pack path then "JC200103" else T.pack (takeBaseName path)
    pure (Just (P.PdfX bytes condition [crName c | c <- mdCreators md]))

-- ------------------------------------------------------------------ drawing

writeDocument :: PdfInput -> PageGeometry -> LoadedFonts -> Built -> [PageOut] -> Maybe P.PdfX -> ByteString
writeDocument inp geom fonts built pages intent =
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
      -- glyph marks of a text starting at a point, and the glyphs used
      runAt v rotated size scale (x0, y0) txt =
        let gs = lfShape fonts (v && not rotated) txt
            advs = scanl (+) 0 [toSp size a | (_, _, a, _) <- gs]
            placed = [(ix, g, t, off) | ((ix, g, _, t), off) <- zip gs advs]
            byFont = Map.fromListWith (flip (<>)) [(ix, [(g, t, off)]) | (ix, g, t, off) <- placed]
            mark ix xs
              | v && rotated = P.RotatedGlyphRun (ref ix False) size [(code ix g, x0, y0 - off) | (g, _, off) <- xs]
              | v = P.GlyphRun (ref ix True) size [(code ix g, x0, y0 - off) | (g, _, off) <- xs]
              | scale /= 0 = P.ScaledGlyphRun (ref ix False) size (1000 + scale) [(code ix g, x0 + off, y0) | (g, _, off) <- xs]
              | otherwise = P.GlyphRun (ref ix False) size [(code ix g, x0 + off, y0) | (g, _, off) <- xs]
            code = lfCode fonts
         in ([mark ix xs | (ix, xs) <- Map.toList byFont], [(ref ix (v && not rotated), g, t) | (ix, g, t, _) <- placed])
      drawLine ta slot sl =
        let l = slLine sl
            size = slSize sl
            origin off0
              | vertical = (rectX ta + rectW ta - gridAt slot, rectY ta + rectH ta - off)
              | otherwise = (rectX ta + off, rectY ta + rectH ta - gridAt slot)
              where
                off = off0 + slIndent sl
            advance sz t = sum [toSp sz a | (_, _, a, _) <- lfShape fonts (vertical && not (T.all ((== Western) . charClass) t)) t]
            -- a point beside the line at a distance across it: right of a
            -- vertical line, above a horizontal baseline
            beside (ox, oy) dist
              | vertical = (ox + dist, oy)
              | otherwise = (ox, oy + dist)
            placed = placeLine l
            lastIx = length placed - 1
            boxRun (i, (it, off)) = case it of
              Box w c -> case boxKind c of
                KindRuby ->
                  -- the base centred in the box, the reading at half size beside it
                  let (base, reading) = T.breakOn "|" (bcText c)
                      rt = T.drop 1 reading
                      rsize = size `div` 2
                      baseStart = off + (w - advance size base) `div` 2
                      readStart = off + (w - advance rsize rt) `div` 2
                      (bx, by) = origin baseStart
                      (b1, u1) = runAt vertical False size 0 (bx, by) base
                      (b2, u2) = runAt vertical False rsize 0 (beside (origin readStart) (if vertical then size `div` 2 + rsize `div` 2 else size)) rt
                   in (b1 <> b2, u1 <> u2)
                KindKenten ->
                  -- the character, and a sesame dot centred beside it
                  let dsize = size `div` 2
                      (b1, u1) = runAt vertical False size 0 (origin off) (bcText c)
                      (b2, u2) = runAt vertical False dsize 0 (beside (origin (off + (size - dsize) `div` 2)) (if vertical then size `div` 2 + dsize `div` 2 else size)) "﹅"
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
                   in runAt vertical rotated size (if bcExpandable c then lineExpansion l else 0) pt (bcText c)
              -- a word broken at the line end gets its hyphen
              Penalty hw _ True
                | i == lastIx && hw > 0 ->
                    let (ox, oy) = origin off
                     in runAt vertical vertical size 0 (if vertical then (ox - size * 3 `div` 10, oy) else (ox, oy)) "-"
              _ -> ([], [])
            parts = zipWith (curry boxRun) [0 ..] placed
         in (concatMap fst parts, concatMap snd parts)
      textAt anchor size txt =
        let w = sum [toSp size a | (_, _, a, _) <- lfShape fonts False txt]
            x0 = case anAlign anchor of
              LS.AlignStart -> anX anchor
              LS.AlignCenter -> anX anchor - w `div` 2
              LS.AlignEnd -> anX anchor - w
         in runAt False False size 0 (x0, anY anchor) txt
      drawPage p =
        let n = poNumber p
            ta = typeAreaFor geom n
            lineParts = [drawLine ta slot sl | (slot, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (bLines built)]]
            figMarks = [P.Image (P.ImageRef fid) (figureRect ta slot w h) | (slot, SFigure fid) <- poSlots p, Just (_, w, h) <- [Map.lookup fid (bFigures built)]]
            noteLines = concat [take cnt (drop from (concat [ls | sl <- Map.elems (bLines built), (nid', ls) <- slNotes sl, nid' == nid])) | (nid, from, cnt) <- poFootnotes p]
            bottomSlots = drop (length grid - length noteLines) [0 .. length grid - 1]
            noteParts = [drawLine ta slot (SetLine l (pgFontSize geom) [] 0) | (slot, l) <- zip bottomSlots noteLines]
            masterParts = if poBlank p then [] else masterMarks n (poRunningHead p)
            allParts = lineParts <> noteParts <> masterParts
         in (concatMap fst allParts <> figMarks, concatMap snd allParts)
      figureRect ta slot w h =
        let top = rectY ta + rectH ta - gridAt slot + pgFontSize geom
         in Rect (rectX ta) (top - h) w h
      masterMarks n heading = case master of
        Nothing -> []
        Just m ->
          let pick (_, a1, a2) = if odd n then a1 else a2
              size = pgFontSize geom
              folio = [textAt (pick f) size (formatNumber fmt [toInteger n] Nothing) | f@(fmt, _, _) <- maybe [] pure (mgFolio m)]
              runningHead = [textAt (pick r) size h | r <- maybe [] pure (mgRunningHead m), Just h <- [heading]]
           in runningHead <> folio
      drawn = map drawPage pages
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
            P.docImages = Map.fromList [(P.ImageRef i, img) | (i, (img, _, _)) <- Map.toList (bFigures built)],
            P.docTitle = mdTitle md,
            P.docDate = (y, mo, d),
            P.docId = P.documentId (mdId md),
            P.docInstanceId = P.instanceId (piInputs inp <> programs <> [TE.encodeUtf8 "golem-0.1.0.0"]),
            P.docPdfX = intent
          }
   in P.writePdf doc
