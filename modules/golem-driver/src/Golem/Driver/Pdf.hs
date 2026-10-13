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
    PlacedSidenote (..),
    PdfLayout (..),
    sidenoteDiagnostics,
    placePageSidenotes,
    layoutPdf,
    layoutPages,
    indexLines,
    bibliographyLines,
    Assumed (..),
    TocGeometry (..),
    TocPage (..),
    tocPage,
    headingPages,
    figureRect,
    renderPdf,
    flowLines,
    pdfFileName,
    instanceIdInputs,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (evaluate)
import Control.Monad (join)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAlphaNum, isAscii)
import Data.Either (fromRight, isLeft)
import Data.List (groupBy, intercalate, nub, sortOn, zip4)
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
import Golem.Driver.Version (golemVersion)
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass hiding (Sp)
import Golem.Layout.Look
import Golem.Layout.Paginate
import Golem.Layout.Ruby (RubyKind (..), RubyPlacement (..), RubyStyle (..), placeRuby)
import Golem.Layout.Ruby qualified as R
import Golem.Layout.Sidenotes (SidenoteError (..), placeSidenotes)
import Golem.Layout.Table (SetCell (..), SetTable (..), TableError (..), layoutTable)
import Golem.Layout.Wrap (Exclusion (..), exclusion, wrappedLineWidth)
import Golem.LayoutSpec (Anchor (..), MasterGeometry (..), PageGeometry (..), Rect (..), baselineRatio, pageGeometry, sidenoteAreaFor, typeAreaFor)
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

{- | What the instance ID is computed from: the bytes of every input, the
embedded font programs and, last, @golem-@ and the version of Golem
(docs/adr/0004; the version is part of the input, docs/adr/0002).
-}
instanceIdInputs :: [ByteString] -> [ByteString] -> [ByteString]
instanceIdInputs inputs programs = inputs <> programs <> [TE.encodeUtf8 ("golem-" <> golemVersion)]

data PdfInput = PdfInput
  { piRoot :: !FilePath,
    piProject :: !Project,
    piStyle :: !Style,
    piBook :: !Book,
    piParallel :: !Bool,
    -- | bytes of every input, for the instance ID
    piInputs :: ![ByteString],
    -- | the formatted entries of the bibliography by key (golem-driver ADR 0007)
    piBibliography :: !(Map Text Text)
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

-- | The rules at the top and bottom of a table: 0.6pt (golem-driver ADR 0008).
thickRule :: Sp
thickRule = 39322

-- | The rule below the header row of a table: 0.3pt.
thinRule :: Sp
thinRule = 19661

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
    slNotes :: ![(Int, [Line])],
    -- | the sidenotes marked in the line, in order (golem-driver ADR 0006)
    slSidenotes :: ![(SrcSpan, [Line])]
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
    plTocPages :: !(Map Int TocPage)
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
    bTocLines :: Map Int (SrcSpan, Sp)
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
        built <- buildFlow inp geom fonts figures (Assumed Map.empty Map.empty)
        pure (Right (bFlow built, [(lineTarget (slLine sl), slIndent sl) | sl <- Map.elems (bLines built)]))

-- | Composition, line breaking and pagination, with page references resolved (S2).
layoutPdf :: PdfInput -> PageGeometry -> LoadedFonts -> IO (Either [Diagnostic] PdfLayout)
layoutPdf inp geom fonts = case sidenoteDiagnostics geom (piBook inp) of
  ds@(_ : _) -> pure (Left ds)
  [] -> do
    figures <- loadFigures inp
    -- S2: compose with assumed page numbers until they settle
    let terms = Map.fromList [(sp, T.intercalate " / " (igTerms g)) | g <- bookIndex (piBook inp), (_, sp) <- igLocations g]
    result <- fixpoint geom (\sp -> Map.findWithDefault "" sp terms) (buildFlow inp geom fonts figures)
    pure $ case result of
      Left ds -> Left ds
      Right (built, pages) ->
        -- sidenotes are placed once, on the settled pages (golem-driver ADR 0006)
        let (size, pitch) = sidenoteMetrics (piStyle inp) geom
            placed = [(poNumber p, placePageSidenotes geom pitch size (bLines built) p) | p <- pages]
            -- the pages of the table of contents, once, on the settled pages (golem-driver ADR 0009)
            hPages = headingPages (bHeadingSpans built) pages
            tg = tocGeometry (piStyle inp) geom fonts
            env = composeEnv (piStyle inp) geom fonts (Assumed Map.empty Map.empty) (bodyRole (piStyle inp)) (pgFontSize geom)
            tocPages = Map.fromList [(lid, tocPage tg e (pageNumberLine env n)) | (lid, (hs, e)) <- Map.toList (bTocLines built), Just n <- [Map.lookup hs hPages]]
         in case concat [ds | (_, Left ds) <- placed] of
              [] -> Right (PdfLayout pages (bLines built) (bFigures built) (bHeadings built) (Map.fromList [(n, ps) | (n, Right ps@(_ : _)) <- placed]) (bTableLines built) (bTables built) tocPages)
              ds -> Left ds

{- | The page of each heading (golem-driver ADR 0009): the page where the
first line of its block is placed, keyed by the span of the block.
-}
headingPages :: Map Int SrcSpan -> [PageOut] -> Map SrcSpan Integer
headingPages spans ps =
  Map.fromList [(hs, toInteger (poNumber p)) | p <- ps, (_, SHeading lid _) <- poSlots p, Just hs <- [Map.lookup lid spans]]

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
      env = composeEnv style geom fonts (Assumed Map.empty Map.empty) (bodyRole style) fs
      (w, u) = tocMetrics env
   in TocGeometry (columnMeasure geom) w (fs `div` 2) u (stTocLeader style == "dots") (ceLook env)

{- | The text of the lines of each page, as far as the layout goes
(golem-driver ADR 0007): the boxes of a line joined.
-}
layoutPages :: FontProvider -> PdfInput -> IO (Either [Diagnostic] [[Text]])
layoutPages provider inp = case pageGeometry (piStyle inp) of
  Left ds -> pure (Left ds)
  Right geom -> do
    lf <- loadFonts provider (piRoot inp) (piStyle inp)
    case lf of
      Left ds -> pure (Left ds)
      Right fonts -> fmap texts <$> layoutPdf inp geom fonts
  where
    texts layout =
      [ [ case Map.lookup lid (plTableLines layout) of
            Just cells -> T.intercalate " " (map setLineText cells)
            Nothing -> setLineText sl
            <> maybe "" (\tp -> boxesText (tpLeader tp) <> boxesText (tpNumber tp)) (Map.lookup lid (plTocPages layout))
        | (_, s) <- poSlots p,
          lid <- case s of
            SLine l -> [l]
            SHeading l m -> [l .. l + m - 1]
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

-- | The size and line pitch of sidenotes: the body pitch scaled to the size.
sidenoteMetrics :: Style -> PageGeometry -> (Sp, Sp)
sidenoteMetrics style geom =
  let fs = pgFontSize geom
      size = maybe fs (dimToSp fs) (stSidenotes style >>= snSize)
   in (size, pgLinePitch geom * size `div` fs)

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
      Paragraph is -> [is]
      Heading _ _ is -> [is]
      BulletList items -> concatMap (concatMap blockInlines . itemBlocks) items
      OrderedList items -> concatMap (concatMap blockInlines . itemBlocks) items
      DefList gs -> concat [dgTerms g <> concatMap (concatMap blockInlines) (dgDefs g) | g <- gs]
      Table _ h rows -> h <> concat rows
      FigureBlock fig -> concatMap blockInlines (figCaption fig)
      VerseBlock stanzas -> concat stanzas
      _ -> []
    -- each sidenote, and whether it is in the text flow
    sites = concatMap siteBlock blocks
    siteBlock b@(Block _ _ body) = case body of
      FigureBlock fig -> [(sp, False) | is <- concatMap blockInlines (figCaption fig), (sp, _) <- concatMap (inlineSites True) is]
      _ -> [x | is <- blockInlines b, x <- concatMap (inlineSites True) is]
    inlineSites flow = \case
      Sidenote sp _ xs -> (sp, flow) : concatMap (inlineSites flow) xs
      Note _ _ xs -> concatMap (inlineSites False) xs
      Strong _ xs -> concatMap (inlineSites flow) xs
      Bold _ xs -> concatMap (inlineSites flow) xs
      Italic _ xs -> concatMap (inlineSites flow) xs
      Kenten _ _ xs -> concatMap (inlineSites flow) xs
      Color _ _ xs -> concatMap (inlineSites flow) xs
      CharStyle _ _ xs -> concatMap (inlineSites flow) xs
      _ -> []

{- | Places the sidenotes of a page in its sidenote column (golem-driver
ADR 0006): each wants the top of the line of its marker; they keep their
order, half a body pitch apart. Takes the sidenote pitch and size.
-}
placePageSidenotes :: PageGeometry -> Sp -> Sp -> Map Int SetLine -> PageOut -> Either [Diagnostic] [PlacedSidenote]
placePageSidenotes geom pitch size lineMap p =
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
      height ls = toInteger (max 1 (length ls) - 1) * pitch + size
      columnH = maybe 0 rectH (sidenoteAreaFor geom (poNumber p))
      at i = case drop i notes of
        ((sp, _, _) : _) -> sp
        [] -> mkSpan (FileId 0) 0 0
   in if null notes
        then Right []
        else case placeSidenotes columnH (bodyPitch `div` 2) [(want, height ls) | (_, want, ls) <- notes] of
          Right tops -> Right [PlacedSidenote sp t ls | ((sp, _, ls), t) <- zip notes tops]
          Left (TooTall i) -> Left [diagnostic "G0733" Error (at i) "傍注が傍注欄より高く、収まりません"]
          Left (DoesNotFit i) -> Left [diagnostic "G0733" Error (at i) "このページの傍注が傍注欄に収まりません"]

-- | The page numbers assumed in a round of S2: of labels and of index marks (golem-driver ADR 0007).
data Assumed = Assumed
  { asLabels :: !(Map Text Integer),
    asMarks :: !(Map SrcSpan Integer)
  }
  deriving stock (Eq, Show)

fixpoint :: PageGeometry -> (SrcSpan -> Text) -> (Assumed -> IO Built) -> IO (Either [Diagnostic] (Built, [PageOut]))
fixpoint geom termOf layoutWith = go (1 :: Int) (Assumed Map.empty Map.empty)
  where
    capacity = length (pgLineGrid geom)
    go i assumed = do
      built <- layoutWith assumed
      let pages = paginate capacity (bFlow built)
          actual = Assumed (labelPages pages) (markPages pages)
      if not (null (bErrors built))
        then pure (Left (bErrors built))
        else
          if actual == assumed
            then pure (Right (built, pages))
            else
              if i >= maxIterations
                then pure (Left [diagnostic "G0721" Error (mkSpan (FileId 0) 0 0) ("ページ番号の参照が収束しません: " <> T.intercalate ", " (moved actual asLabels id <> nub (moved actual asMarks termOf)))])
                else go (i + 1) actual
      where
        moved :: (Ord k) => Assumed -> (Assumed -> Map k Integer) -> (k -> Text) -> [Text]
        moved now field name = [name k | k <- Map.keys (Map.union (field now) (field assumed)), Map.lookup k (field now) /= Map.lookup k (field assumed)]

{- | The composition environment of a unit set in a font role at a size
(golem-driver ADR 0003).
-}
composeEnv :: Style -> PageGeometry -> LoadedFonts -> Assumed -> Text -> Sp -> ComposeEnv
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
          ceRuby = rubyStyleOf style fs,
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
          cePatterns = Just englishUS
        }

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

-- | A paragraph unit to break: the inlines and a prefix (list markers).
data Unit = Unit
  { uKind :: UnitKind,
    uLabel :: Maybe Text,
    uInlines :: [Inline],
    -- | the block the unit comes from, for diagnostics
    uSpan :: SrcSpan
  }

data UnitKind
  = UPara
  | UHeading Int Text Bool
  | UTerm
  | UFigure Figure
  | UTable [Alignment] [[Inline]] [[[Inline]]]
  | -- | a line of verse: the indent and the hang in sp (docs/adr ADR 0003)
    UVerseLine Sp Sp
  | -- | grid lines between stanzas
    UGap Int
  | -- | an entry of the table of contents: its level and its heading (golem-driver ADR 0009)
    UTocEntry Int SrcSpan

unitsOf :: Book -> PageGeometry -> Style -> (SrcSpan -> Maybe Integer) -> Map Text Text -> [Unit]
unitsOf book geom style pageOf bib = concatMap doc (bookDocs book)
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
      Table aligns h rows -> [Unit (UTable aligns h rows) lbl []]
      CodeBlock _ code -> [Unit UPara lbl [txt l] | l <- T.lines code]
      FigureBlock fig -> [Unit (UFigure fig) lbl []]
      VerseBlock stanzas ->
        let vs = stVerse style
            fs = pgFontSize geom
            kind = UVerseLine (dimToSp fs (vsIndent vs)) (dimToSp fs (vsHang vs))
            stanzaUnits = [[Unit kind Nothing l | l <- st] | st <- stanzas]
         in case intercalate [Unit (UGap (vsStanzaGap vs)) Nothing []] stanzaUnits of
              (u : us) -> (\s -> (u s) {uLabel = lbl}) : us
              [] -> []
      -- the index marks of a title are counted at the heading, not in the table of contents
      ChannelOutput (TocOutput depth) -> [Unit (UTocEntry (teLevel e) (teSpan e)) Nothing (maybe [] (\n -> [txt (n <> "　")]) (teNumber e) <> filter (not . isMark) (teTitle e)) | e <- bookToc book, teLevel e <= depth]
      ChannelOutput IndexOutput -> [Unit UPara Nothing is | is <- indexLines (pgVertical geom) pageOf (bookIndex book)]
      ChannelOutput BibliographyOutput -> [Unit UPara Nothing is | is <- bibliographyLines bib (bookCitations book)]
    prefixFirst p (Unit UPara l is s' : rest) = Unit UPara l (txt p : is) s' : rest
    prefixFirst _ us = us
    isMark = \case
      IndexMark {} -> True
      _ -> False

-- | A unit composed and broken into lines.
data Composed = Composed
  { cLines :: [Line],
    cNotes :: [(Int, [Line])],
    -- | sidenote bodies: the item index of the marker, the span and the lines
    cSidenotes :: [(Int, SrcSpan, [Line])],
    -- | index marks: the item index they belong to (a note's marks go with the note) and the mark
    cMarks :: [(Int, SrcSpan)],
    cAnchors :: [Golem.Layout.Japanese.Anchor],
    cItems :: [Item]
  }

buildFlow :: PdfInput -> PageGeometry -> LoadedFonts -> Map Text (Maybe P.ImageData) -> Assumed -> IO Built
buildFlow inp geom fonts images assumed = do
  let style = piStyle inp
      body = bodyRole style
      fs = pgFontSize geom
      pitch = pgLinePitch geom
      capacity = length (pgLineGrid geom)
      vertical = pgVertical geom
      cites = Map.fromList (bookCitations (piBook inp))
      -- citations show their numbers (golem-driver ADR 0007)
      envFor role size = (composeEnv style geom fonts assumed role size) {ceCiteNumber = (`Map.lookup` cites)}
      bodyEnv = envFor body fs
      params = kpParams style geom
      measure = columnMeasure geom
      -- the reserve for the page number of a table of contents entry: W and two em (golem-driver ADR 0009)
      tocReserve = fst (tocMetrics bodyEnv) + 2 * fs
      tocIndent l = toInteger (l - 1) * fs
      -- a mark without an assumed page yet stands at page 1 in the first round
      markPage sp = Map.lookup sp (asMarks assumed) <|> (if Map.null (asMarks assumed) then Just 1 else Nothing)
      units = zip [0 :: Int ..] (unitsOf (piBook inp) geom style markPage (piBibliography inp))
      unitAt = Map.fromList units
      -- L*(i): verse lines are shortened by the indent, and their continuations also by the hang (docs/adr ADR 0003)
      widthOf = \case
        UVerseLine ind hang -> \k -> if k == 0 then measure - ind else measure - ind - hang
        UTocEntry l _ -> const (measure - tocIndent l - tocReserve)
        _ -> const measure
      lineIndent = \case
        UVerseLine ind hang -> \k -> if k == (0 :: Int) then ind else ind + hang
        UTocEntry l _ -> const (tocIndent l)
        _ -> const 0
      -- the role and size a unit is set in
      faceOf u = case uKind u of
        UHeading l _ _ -> headingFace style geom l
        _ -> (body, fs)
      compose lineWidth u =
        let (role, size) = faceOf u
            env = envFor role size
            (items, anchors) = composeInlines env (uInlines u)
            lines' = brLines (breakParagraph params lineWidth items)
            notes = [(n, brLines (breakParagraph params (const measure) (fst (composeInlines bodyEnv nbody)))) | AnchorNote _ n nbody <- anchors]
            sidenotes = [(i, sp, sidenoteLines n snBody) | AnchorSidenote i n sp snBody <- anchors]
            marks =
              [(i, sp) | AnchorIndex i sp _ <- anchors]
                <> [(i, sp) | AnchorNote i _ nbody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines bodyEnv nbody)]
                <> [(i, sp) | AnchorSidenote i _ _ snBody <- anchors, AnchorIndex _ sp _ <- snd (composeInlines bodyEnv snBody)]
         in Composed lines' notes sidenotes marks anchors items
      -- sidenote bodies: their size, the column width, the marker first (golem-driver ADR 0006)
      (snSize', _) = sidenoteMetrics style geom
      snEnv = envFor body snSize'
      snParams = params {pEmergencyStretch = dimToSp snSize' (compEmergencyStretch (stComposition style))}
      snMeasure = maybe 0 (rectW . fst) (pgSidenotes geom)
      sidenoteLines n snBody =
        let prefix = case ceSidenoteMarker bodyEnv of
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
            captionInlines = maybe [] (\num -> [Text (uSpan u) (num <> "　")]) number <> concat [is | Block _ _ (Paragraph is) <- figCaption fig]
            (captionItems, captionAnchors) = composeInlines bodyEnv captionInlines
            caption = if null captionInlines then [] else brLines (breakParagraph params (const alongSp) captionItems)
            captionMarks = [sp | AnchorIndex _ sp _ <- captionAnchors]
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
         in (PlacedFigure img alongSp across (figWrap fig) m caption ex, errs, captionMarks)
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
      jobs = [(i, ex) | (i, (pf, [], _)) <- Map.toList figures, Just ex <- [pfExclusion pf]]
  besides <- Map.fromList . concat <$> mapper (uncurry wrapJob) jobs
  -- 2. every other unit on its own
  let rest = [(i, u) | (i, u) <- units, Map.notMember i besides, not (isFigure u), not (isTable u), not (isGap u)]
      isGap u = case uKind u of
        UGap _ -> True
        _ -> False
      isFigure u = case uKind u of
        UFigure _ -> True
        _ -> False
      isTable u = case uKind u of
        UTable {} -> True
        _ -> False
      -- the notes, sidenotes and index marks of composed inlines, by the line that holds them
      attached items anchors ls =
        let lineOf = lineIndexOfItems items ls
            noteBody b = brLines (breakParagraph params (const measure) (fst (composeInlines bodyEnv b)))
            marksIn b = [sp | AnchorIndex _ sp _ <- snd (composeInlines bodyEnv b)]
         in ( Map.fromListWith (flip (<>)) [(lineOf i, [(n, noteBody b)]) | AnchorNote i n b <- anchors],
              Map.fromListWith (flip (<>)) [(lineOf i, [(sp, sidenoteLines n b)]) | AnchorSidenote i n sp b <- anchors],
              Map.fromListWith (flip (<>)) ([(lineOf i, [sp]) | AnchorIndex i sp _ <- anchors] <> [(lineOf i, sps) | AnchorNote i _ b <- anchors, let { sps = marksIn b }, not (null sps)] <> [(lineOf i, sps) | AnchorSidenote i _ _ b <- anchors, let sps = marksIn b, not (null sps)])
            )
      -- a table: every cell at the body size, no hanging punctuation (golem-driver ADR 0008)
      composeTable aligns h rows =
        let env = bodyEnv {ceHanging = False}
            cellOf = composeInlines env
            hCells = map cellOf h
            rCells = map (map cellOf) rows
            rowAttached cells setCells height =
              let perCell = [attached items anchors (scLines sc) | ((items, anchors), sc) <- zip cells setCells]
               in [(concat [Map.findWithDefault [] k ns | (ns, _, _) <- perCell], concat [Map.findWithDefault [] k sn | (_, sn, _) <- perCell], concat [Map.findWithDefault [] k ms | (_, _, ms) <- perCell]) | k <- [0 .. height - 1]]
         in case layoutTable params measure fs aligns (map fst hCells) (map (map fst) rCells) of
              Left e -> Left e
              Right t -> Right (t, rowAttached hCells (stHeader t) (stHeaderLines t) : zipWith3 rowAttached rCells (stRows t) (stRowLines t))
      tableUnits = [(i, aligns, h, rows) | (i, Unit {uKind = UTable aligns h rows}) <- units]
  _ <- mapper (\(_, (pf, _, _)) -> evaluate (length (show (map lineRatio (pfCaption pf))))) (Map.toList figures)
  singles <- Map.fromList . zip (map fst rest) <$> mapper (\(_, u) -> force (compose (widthOf (uKind u)) u)) rest
  tables <- Map.fromList <$> mapper (\(i, aligns, h, rows) -> let r = composeTable aligns h rows in evaluate (length (show (fmap fst r))) >> pure (i, r)) tableUnits
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
            sidenoteLinesOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [(sp, sls)]) | (i, sp, sls) <- cSidenotes c]
            marksOf = Map.fromListWith (flip (<>)) [(lineOfItem i, [sp]) | (i, sp) <- cMarks c]
            boxes = [LineBox lid [NoteBody n (length nls) | (n, nls) <- Map.findWithDefault [] k noteLines] (if k == 0 then label u else []) (Map.findWithDefault [] k marksOf) | (k, lid) <- zip [0 ..] ids]
            set = Map.fromList [(lid, SetLine l size (indentOf k) (Map.findWithDefault [] k noteLines) (Map.findWithDefault [] k sidenoteLinesOf)) | (k, (lid, l)) <- zip [0 ..] (zip ids ls)]
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
                      [ ( [LineBox lid [NoteBody n (length nls) | (n, nls) <- ns] (if lid == nextId then label u else []) ms | (lid, (ns, _, ms)) <- zip ids att],
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
                          go (nid, boxAcc, setAcc) (j, c, off) =
                            let (bs, set) = numbered nid (unitAt Map.! j) c (indentOf off)
                             in (nid + length (cLines c), boxAcc <> bs, Map.union setAcc set)
                          (nextId', allBoxes, sets) = foldl go (nextId + 1, [], Map.empty) paras
                          (beside, continued) = splitAt (exLines ex) allBoxes
                       in ( nextId',
                            flows <> [FWrapped nextId (exLines ex) (label u) fmarks beside] <> [FContinued continued | not (null continued)],
                            Map.union lineAcc sets,
                            Map.insert nextId pf figAcc,
                            headAcc,
                            errs
                          )
                _ -> (nextId + 1, flows <> [FFigure nextId (pfImageLines pf + length (pfCaption pf)) (label u) fmarks], lineAcc, Map.insert nextId pf figAcc, headAcc, errs <> ferrs)
            UGap n -> (nextId, flows <> [FSpace n], lineAcc, figAcc, headAcc, errs)
            _ ->
              let c = singles Map.! i
                  ls = cLines c
                  (boxes, set) = numbered nextId u c (lineIndent (uKind u))
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
      (_, flow, lineMap, figMap, headMap, errors, (tableLines, tableWidths), (headingSpans, tocLines)) = foldl step (0, [], Map.empty, Map.empty, Map.empty, [], (Map.empty, Map.empty), (Map.empty, Map.empty)) units
  pure (Built flow lineMap figMap headMap errors tableLines tableWidths headingSpans tocLines)

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
                                advOf lk ch = toSp (lkSize lk) (lfAdvance fonts (if isLatin ch then lkLatinFace lk else lkFace lk) ch)
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
                <> [ drawLine ta (gridAt (slot + pfImageLines pf + j)) (SetLine l (pgFontSize geom) (captionIndent ta pf) [] [])
                   | (slot, fid) <- placedFigures p,
                     Just pf <- [Map.lookup fid (plFigures layout)],
                     (j, l) <- zip [0 ..] (pfCaption pf)
                   ]
            figMarks = [P.Image (P.ImageRef fid) (figureRect geom ta slot pf) | (slot, fid) <- placedFigures p, Just pf <- [Map.lookup fid (plFigures layout)]]
            noteLines = concat [take cnt (drop from (concat [ls | sl <- Map.elems (plLines layout), (nid', ls) <- slNotes sl, nid' == nid])) | (nid, from, cnt) <- poFootnotes p]
            bottomSlots = drop (length grid - length noteLines) [0 .. length grid - 1]
            noteParts = [drawLine ta (gridAt slot) (SetLine l (pgFontSize geom) 0 [] []) | (slot, l) <- zip bottomSlots noteLines]
            masterParts = if poBlank p then [] else masterMarks n (poRunningHead p)
            -- sidenotes in the sidenote column of the page (golem-driver ADR 0006)
            (snSize', snPitch) = sidenoteMetrics style geom
            sidenoteParts =
              [ drawLineAt (rectX area, rectY area + rectH area - (psTop ps + toInteger j * snPitch + round (toRational snSize' * baselineRatio))) (SetLine l snSize' 0 [] [])
              | Just area <- [sidenoteAreaFor geom n],
                ps <- Map.findWithDefault [] n (plSidenotes layout),
                (j, l) <- zip [0 :: Int ..] (psLines ps)
              ]
            allParts = lineParts <> noteParts <> sidenoteParts <> masterParts
            ruleMarks = concat [tableRules ta seg w | seg <- poTables p, Just w <- [Map.lookup (tsTable seg) (plTables layout)]]
         in (concatMap fst allParts <> figMarks <> ruleMarks, concatMap snd allParts)
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
            P.docInstanceId = P.instanceId (instanceIdInputs (piInputs inp) programs),
            P.docPdfX = intent
          }
   in P.writePdf doc
