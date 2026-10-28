-- | The font roles of the PDF and their diagnostics (golem-driver ADR 0002).
module Golem.Driver.Pdf.Fonts
  ( Shaping (..),
    LoadedFonts (..),
    Shaped (..),
    GlyphFrame (..),
    offsetOrigin,
    FontProvider (..),
    noFontProvider,
    instanceIdInputs,
    producer,
    PdfInput (..),
    bookLanguage,
    docStyle,
    bodyRole,
    bodyFontDiagnostics,
    usedRoles,
    bookHasCode,
    codeStyles,
    codeInput,
    codeFontNotice,
    kentenShaped,
    kentenRubyNotices,
    blockInlineLists,
    restyle,
    restyleSource,
    withBoxSource,
    noteIdSpan,
    withFeatures,
    shapingOf,
    thickRule,
    thinRule,
    syntheticSlant,
    syntheticStrokeJa,
    syntheticStrokeLatin,
    syntheticStroke,
    headingFace,
    headingLines,
    headingDefaults,
    faceFor,
    paraFace,
    pdfFileName,
    emBoxCentralOf,
  )
where

import Control.Applicative ((<|>))
import Data.ByteString (ByteString)
import Data.Char (isAlphaNum, isAscii)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Doc.Assemble
import Golem.Doc.Bibliography (EntryPart (..))
import Golem.Doc.IR
import Golem.Driver.TextLayer (ClusterPart (..))
import Golem.Driver.Version (golemVersion)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass hiding (Sp)
import Golem.Layout.Look hiding (Kerning (..))
import Golem.Layout.Look qualified as L
import Golem.Layout.Paginate
import Golem.LayoutSpec (PageGeometry (..))
import Golem.Pdf qualified as P
import Golem.Project
import Golem.Project.Style
import Golem.Syntax
import Golem.Syntax.Length (zwToSp)

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
    cannot be embedded is a diagnostic (G08018, golem-pdf ADR 0011)
    -} lfEmbed :: Int -> Bool -> [(Int, Text)] -> IO (Either Diagnostic P.Font),
    {- | the height of the centre of the ideographic em box above the
    baseline of a face number, in em (golem-driver ADR 0015)
    -} lfEmBoxCentral :: Int -> Rational,
    {- | the path of the file of a face number and its form, @cff@, @cff2@ or
    @truetype@ (golem-cli ADR 0006, golem-font ADR 0003)
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
offsetOrigin :: Sp -> GlyphFrame -> (Rational, Rational) -> (Sp, Sp) -> (Sp, Sp)
offsetOrigin size frame (dx, dy) (gx, gy) = case frame of
  FrameHorizontal scale -> (gx + sp (dx * toRational (1000 + scale) / 1000), gy + sp dy)
  FrameUpright -> (gx + sp dx, gy + sp dy)
  FrameTurned -> (gx + sp dy, gy - sp dx)
  where
    sp = zwToSp size

newtype FontProvider = FontProvider
  { {- | the root, style.toml and the styles of the files (docs/adr ADR 0014)
    and the file of the diagnostics about style.toml (golem-driver ADR 0016)
    -} loadFonts :: FilePath -> FileId -> Style -> [LocalStyles] -> IO (Either [Diagnostic] LoadedFonts)
  }

noFontProvider :: FontProvider
noFontProvider =
  FontProvider $ \_ fid _ _ ->
    pure (Left [diagnostic "G08001" Error (mkSpan fid 0 0) "フォントを読まない設定（noFontProvider）では PDF を出力できません"])

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

{- | G08007 (golem-driver ADR 0016): style.toml sets no body font, or the
body role has no file, at the top of @fid@.
-}
bodyFontDiagnostics :: FileId -> Style -> [Diagnostic]
bodyFontDiagnostics fid style
  | Map.null (stFonts style) = [err "style.toml に本文のフォントがありません。[fonts.body] を書いてください"]
  | Just (FontRole Nothing Nothing _) <- Map.lookup body (stFonts style) = [err ("[fonts." <> body <> "] にフォントのファイルがありません")]
  | otherwise = []
  where
    body = bodyRole style
    err = diagnostic "G08007" Error (mkSpan fid 0 0)

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

{- | G08008 (golem-driver ADR 0017): the book has code, [fonts.code] is
missing and a style code names the role code; at the top of @fid@.
-}
codeFontNotice :: FileId -> Style -> Book -> [Diagnostic]
codeFontNotice fid style book =
  [ notice "G08008" (mkSpan fid 0 0) "コードの書体の役割 code がないので、本文の書体で組みます"
  | bookHasCode (const style) book,
    Map.notMember "code" (stFonts style),
    (paraStyle style (Just "code") >>= psFont) == Just "code" || (charStyle style "code" >>= csFont) == Just "code"
  ]

{- | The glyphs of a kenten mark (golem-driver ADR 0019): the character of
the shape in the Japanese face of a role, in the direction of the text.
-}
kentenShaped :: LoadedFonts -> Bool -> Text -> KentenShape -> [Shaped]
kentenShaped fonts vertical role shape = lfShape fonts (Shaping role vertical []) (T.singleton (kentenChar shape))

{- | G07045 (golem-driver ADR 0019): kenten in the base of a ruby, at the
kenten, and ruby in kenten, at the ruby. The PDF draws no kenten there;
HTML and EPUB draw both.
-}
kentenRubyNotices :: Book -> [Diagnostic]
kentenRubyNotices book =
  [ notice "G07045" sp "ルビの親文字の圏点は PDF では描きません"
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

{- | The size source inside an inline element (golem-cli ADR 0008), as
'restyle' is the look inside it: a character style that writes a size
(itself or through based-on) decides the size of its characters.
-}
restyleSource :: Style -> SizeSource -> Inline -> SizeSource
restyleSource style src = \case
  CharStyle _ name _ | Just n <- charSizeSource style name -> SourceCharacterStyle n
  _ -> src

-- | The boxes of a line with a source (golem-cli ADR 0008).
withBoxSource :: BoxSource -> Line -> Line
withBoxSource src l = l {lineItems = map one (lineItems l)}
  where
    one = \case
      Box w c -> Box w c {bcSource = src}
      x -> x

-- | The span of the marker of a note.
noteIdSpan :: NoteId -> SrcSpan
noteIdSpan (NoteId sp _) = sp

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
spaces keeps its full width (docs/adr ADR 0053): palt and vpal are not
added to it, and -palt and -vpal after the role's features turn off a
palt or vpal of the role.
-}
shapingOf :: Bool -> Look -> Char -> Shaping
shapingOf vertical lk c
  | charClass c == Western = Shaping (lkLatinFace lk) False ["-kern" | lkKerning lk == L.KernNone]
  | otherwise = Shaping (lkFace lk) vertical extra
  where
    spaced = punctSpace (charClass c) /= (0, 0)
    proportional
      | spaced = ["-palt", "-vpal"]
      | otherwise = [if vertical then "vpal" else "palt" | lkProportional lk]
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
syntheticStroke r size = Sp (floor (toRational (unSp size) * r))

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

-- | The centre of the em box of the Japanese characters of a look above the baseline, in em (golem-driver ADR 0033).
emBoxCentralOf :: LoadedFonts -> Look -> Rational
emBoxCentralOf fonts look = lfEmBoxCentral fonts (maybe 0 shFace (listToMaybe (lfShape fonts (Shaping (lkFace look) False []) "漢")))
