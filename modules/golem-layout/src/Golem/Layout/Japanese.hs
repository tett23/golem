{- | Japanese composition (golem-layout ADR 0002): JLReq character classes,
line-start and line-end prohibitions, punctuation spacing, spacing
between Japanese and Latin text, ruby, kenten and tate-chu-yoko, turned
into Knuth–Plass items. Glyph advances come from a metrics function
(shaping is golem-font's job).
-}
module Golem.Layout.Japanese
  ( CharClass (..),
    charClass,
    isVariationSelector,
    isExtending,
    clusters,
    ComposeEnv (..),
    SidenoteMarker (..),
    defaultComposeEnv,
    Anchor (..),
    BoxKind (..),
    boxKind,
    noteMarkSize,
    noteMarkText,
    composeInlines,
    lineStartProhibited,
    lineEndProhibited,
    protrusionRatio,
    verticalSidenotes,
    punctSpace,
  )
where

import Data.Char (GeneralCategory (..), generalCategory, isSpace)
import Data.List (groupBy, zip4)
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Doc.Numerals (kanji, kanjiDigits)
import Golem.Layout.Aki (AkiPos (..), AkiSet, akiBetween, defaultAkiSet, noAki)
import Golem.Layout.Aki qualified as A
import Golem.Layout.CharClass
import Golem.Layout.Hyphenation
import Golem.Layout.KnuthPlass
import Golem.Layout.Look
import Golem.Layout.Ruby
import Golem.Project.Style (Dim (..), dimToSp)
import Golem.Syntax (Diagnostic, Severity (..), SrcSpan, diagnostic)

lineStartProhibited :: Bool -> CharClass -> Bool
lineStartProhibited strict = \case
  Closing -> True
  Hyphen -> True
  Dividing -> True
  MiddleDot -> True
  FullStop -> True
  Comma -> True
  Iteration -> True
  ProlongedSound -> strict
  SmallKana -> strict
  _ -> False

lineEndProhibited :: CharClass -> Bool
lineEndProhibited = (== Opening)

{- | How far Latin punctuation may stick out of the line, in permille of
its width (ADR 0005): (start, end).
-}
protrusionRatio :: Char -> (Integer, Integer)
protrusionRatio = \case
  '-' -> (0, 700)
  '‐' -> (0, 700)
  '–' -> (0, 500)
  '—' -> (0, 200)
  ',' -> (0, 700)
  '.' -> (0, 700)
  ';' -> (0, 500)
  ':' -> (0, 500)
  '!' -> (0, 200)
  '?' -> (0, 200)
  '“' -> (700, 0)
  '‘' -> (700, 0)
  '”' -> (0, 700)
  '’' -> (0, 700)
  '"' -> (500, 500)
  '\'' -> (500, 500)
  _ -> (0, 0)

data ComposeEnv = ComposeEnv
  { {- | the size of the paragraph: the base of the inter-character
    stretch and the quarter em between Japanese and Latin text
    -} ceFontSize :: !Sp,
    -- | advance of a character in a look, in em (1 for full-width characters)
    ceAdvance :: Look -> Char -> Rational,
    -- | advance of a Latin word in a look, in em, as shaped (kerning, ligatures)
    ceWordAdvance :: Look -> Text -> Rational,
    -- | the pair kerning of two Japanese characters in a look, in em (docs/adr/0020)
    ceKern :: Look -> Char -> Char -> Rational,
    ceVertical :: !Bool,
    ceKinsokuStrict :: !Bool,
    ceHanging :: !Bool,
    ceProtrusion :: !Bool,
    -- | the placement of ruby (golem-layout ADR 0009)
    ceRuby :: !RubyStyle,
    -- | the number notation of vertical text when the source names none
    ceVerticalNumbers :: !VerticalNumbers,
    cePatterns :: !(Maybe Patterns),
    -- | page numbers of labels decided so far (S2); unknown labels take a one-digit stand-in
    cePageOf :: Text -> Maybe Integer,
    -- | the look of the paragraph (golem-driver ADR 0004)
    ceLook :: !Look,
    -- | the look inside an inline element (strong, bold, italic, style, colour)
    ceRestyle :: Look -> Inline -> Look,
    -- | how a sidenote is marked in the text (golem-driver ADR 0006)
    ceSidenoteMarker :: !SidenoteMarker,
    -- | the number of a cited work (golem-driver ADR 0007)
    ceCiteNumber :: SrcSpan -> Text -> Maybe Int,
    {- | the penalty of a break after a hyphen or dash in a Latin word;
    10000 or more means no such break (golem-layout ADR 0008)
    -} ceExplicitHyphenPenalty :: !Int,
    -- | the aki set of the paragraph (docs/adr ADR 0019)
    ceAkiSet :: !AkiSet,
    -- | [notes] mark-size: the size of note marks (golem-driver ADR 0025)
    ceNoteMarkSize :: !Dim,
    -- | [notes] mark-format: the text of a note mark, {n} its number (golem-driver ADR 0025)
    ceNoteMarkFormat :: !Text,
    -- | the definition that decided the size of 'ceLook' (golem-cli ADR 0008)
    ceSizeSource :: !SizeSource,
    -- | the size source inside an inline element, as 'ceRestyle' is the look inside it
    ceSizeSourceOf :: SizeSource -> Inline -> SizeSource,
    -- | the source of the boxes of the piece 'itemsFor' makes; set by 'composeInlines'
    ceBoxSource :: !BoxSource
  }

-- | The mark of a sidenote in the text: its number, ※ or nothing.
data SidenoteMarker = MarkerNumber | MarkerSymbol | MarkerNone
  deriving stock (Eq, Show)

defaultComposeEnv :: Sp -> ComposeEnv
defaultComposeEnv fs =
  ComposeEnv
    { ceFontSize = fs,
      ceAdvance = const defaultAdvance,
      ceWordAdvance = const (sum . map defaultAdvance . T.unpack),
      ceKern = \_ _ _ -> 0,
      ceVertical = False,
      ceKinsokuStrict = True,
      ceHanging = False,
      ceProtrusion = False,
      ceRuby = defaultRubyStyle fs,
      ceVerticalNumbers = VerticalFixed StyleKanji,
      cePatterns = Nothing,
      cePageOf = const Nothing,
      ceLook = plainLook "body" fs,
      ceRestyle = const,
      ceSidenoteMarker = MarkerNumber,
      ceCiteNumber = \_ _ -> Nothing,
      ceExplicitHyphenPenalty = 50,
      ceAkiSet = defaultAkiSet,
      ceNoteMarkSize = Zw (1 % 2),
      ceNoteMarkFormat = "*{n}",
      ceSizeSource = SourceGrid,
      ceSizeSourceOf = const,
      ceBoxSource = noBoxSource
    }
  where
    defaultAdvance c
      | charClass c == Western = if isSpace c then 1 / 4 else 1 / 2
      | otherwise = 1

{- | Variation selectors (U+FE00–U+FE0F) and ideographic variation
selectors (U+E0100–U+E01EF): they join the box of the character before
them (golem-pdf ADR 0006).
-}
isVariationSelector :: Char -> Bool
isVariationSelector c = (c >= '\xFE00' && c <= '\xFE0F') || (c >= '\xE0100' && c <= '\xE01EF')

{- | The text of a box without its trailing combining characters
(variation selectors among them), unless nothing else is left: the
character classes come from the base character (golem-pdf ADR 0006,
golem-driver ADR 0036).
-}
baseText :: Text -> Text
baseText t = case T.dropWhileEnd isExtending t of
  base | T.null base -> t
  base -> base

-- | Things the pagination must know about, at an item index.
data Anchor
  = AnchorNote !Int !Int !SrcSpan [Inline] -- item index, note number, span, body
  | AnchorSidenote !Int !Int !SrcSpan [Inline] -- item index, sidenote number, span, body
  | AnchorPageRef !Int !Text
  | -- | item index, the mark, the entry; an item of a channel has an empty entry (golem-doc ADR 0007)
    AnchorIndex !Int !SrcSpan IndexEntry
  deriving stock (Eq, Show)

{- | What a box shows (kept in 'bcTag').
'KindRuby' is a mono ruby, 'KindGroupRuby' a group ruby (golem-layout ADR 0009).
'KindAki' is the empty box of an [aki] (golem-layout ADR 0012) and
'KindNoteMark' the mark of a note (golem-driver ADR 0018); they come last
so that the values before them keep their 'fromEnum'.
-}
data BoxKind = KindText | KindRuby | KindTcy | KindRotated | KindKenten | KindPunctuation | KindGroupRuby | KindAki | KindNoteMark
  deriving stock (Eq, Show, Enum, Bounded)

boxKind :: BoxContent -> BoxKind
boxKind = toEnum . bcTag

-- ------------------------------------------------------------------ pieces

-- One unit of composition before items are generated, with its look.
data Piece
  = PChar !Look !Char !Text -- the character and its variation selectors; kenten is in the look
  | PWord !Look !Text -- a Latin word (no spaces)
  | PSpace !Look -- an inter-word space
  | PBox !Look !Text !BoxKind !Sp -- ruby, tcy, …: an unbreakable box of a given width
  | PRuby !Look !RubyKind !Text ![Look] !(Maybe Text) -- ruby: the base, the look of each base character (golem-layout ADR 0011) and the reading (none for a segment without one)
  | PRubyBreak -- a break allowed between mono ruby bases
  | PForcedBreak -- a hard line break: the line ends as a paragraph does (docs/adr ADR 0016)
  | PAki !Look !AkiAmount -- [aki]: a fixed space, no break around it (docs/adr ADR 0019)
  | PCode !Look !Text !Sp !Sp -- a run of code without spaces and tabs (golem-driver ADR 0017), the padding before and after it (golem-driver ADR 0029)
  | PAnchor (Int -> Anchor)

composeInlines :: ComposeEnv -> [Inline] -> ([Item], [Anchor])
composeInlines env inls =
  let sourced = concatMap (piecesOf env) inls
      -- padCode keeps one piece for each piece
      pieces = padCode (map snd sourced)
      (items, anchors) = foldl' emit ([], []) (zip4 (map fst sourced) prevs pieces nexts)
      emit (acc, as) (_, _, PAnchor f, _) = (acc, (length acc, f) : as)
      -- the boxes of a piece carry its source (golem-cli ADR 0008)
      emit (acc, as) (src, pv, p, nx) = (acc <> itemsFor env {ceBoxSource = src} pv p nx, as)
      -- the neighbours of each piece, anchors and breaks between mono ruby bases skipped
      solid = \case
        PAnchor _ -> False
        PRubyBreak -> False
        _ -> True
      prevs = scanl (\acc p -> if solid p then Just p else acc) Nothing pieces
      nexts = drop 1 (scanr (\p acc -> if solid p then Just p else acc) Nothing pieces)
      normalized = normalize env (kernPairs env items)
      -- anchors index the normalized items: the spacing inserted before a box shifts it
      positions = alignPositions items normalized
      at i = fromMaybe (length normalized) (lookup i positions)
   in (finish normalized, [f (at i) | (i, f) <- reverse anchors])
  where
    finish its = its <> lineEnd

-- | The end of a paragraph, and of a line broken by a hard break: the rest of the line is fill.
lineEnd :: [Item]
lineEnd = [Penalty 0 infPenalty NoHyphen, Glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]

{- | Where each item ends up after 'normalize', which only inserts items
before boxes: a box is the next box of the normalized items, anything
else is the next item.
-}
alignPositions :: [Item] -> [Item] -> [(Int, Int)]
alignPositions = go 0 0
  where
    go _ _ [] _ = []
    go i j (x : xs) ys = case x of
      Box {} -> case break isBox ys of
        (skipped, _ : rest) -> let j' = j + length skipped in (i, j') : go (i + 1) (j' + 1) xs rest
        (_, []) -> []
      _ -> case ys of
        (_ : rest) -> (i, j) : go (i + 1) (j + 1) xs rest
        [] -> []
    isBox = \case
      Box {} -> True
      _ -> False

{- | The pieces of an inline, each with its source (golem-cli ADR 0008): the
size source of the look it is set in and the span of the inline it
comes from.
-}
piecesOf :: ComposeEnv -> Inline -> [(BoxSource, Piece)]
piecesOf env inl = case inl of
  Text sp t -> at sp (textPieces lk t)
  Color _ _ xs -> restyled xs
  CharStyle _ _ xs -> restyled xs
  -- the shape is a look of the characters inside; the inner kenten wins (golem-driver ADR 0019)
  Kenten _ sh xs -> concatMap (piecesOf env {ceLook = lk {lkKenten = Just (fromMaybe KentenSesame (sh >>= kentenShapeFromName))}}) xs
  Ruby sp _ segs -> at sp (rubyPieces env segs)
  Tcy sp t -> at sp [PBox lk t KindTcy (lkSize lk)]
  Number sp n style -> at sp (numberPieces env n style)
  Ref sp RefPage l ->
    let n = fromMaybe 1 (cePageOf env l)
     in at sp (PAnchor (`AnchorPageRef` l) : textPieces lk (T.pack (show n)))
  Ref sp _ l -> at sp (textPieces lk l)
  Deferred {} -> []
  -- a mark is set at the mark size of [notes] (golem-driver ADR 0025)
  Note sp n body -> [((ceSizeSource env, sp), PAnchor (\i -> AnchorNote i n sp body)), ((SourceNoteMark, sp), markPiece (noteMarkText (ceNoteMarkFormat env) n))]
  Sidenote sp n body ->
    ((ceSizeSource env, sp), PAnchor (\i -> AnchorSidenote i n sp body)) : case ceSidenoteMarker env of
      MarkerNumber -> [((SourceNoteMark, sp), markPiece (T.pack (show n)))]
      MarkerSymbol -> at sp [PBox lk "※" KindText (lkSize lk)]
      MarkerNone -> []
  IndexMark sp e -> at sp [PAnchor (\i -> AnchorIndex i sp e)]
  -- nothing shows; its page is followed like that of an index mark (golem-doc ADR 0007)
  ChannelItem sp _ -> at sp [PAnchor (\i -> AnchorIndex i sp (IndexEntry [] []))]
  Cite sp k -> at sp (textPieces lk ("[" <> maybe k (T.pack . show) (ceCiteNumber env sp k) <> "]"))
  ProofComment {} -> []
  -- the lines of a keep style are split before they are composed (docs/adr
  -- ADR 0005); what reaches here is a hard break (docs/adr ADR 0016)
  LineBreak sp -> at sp [PForcedBreak]
  Aki sp a -> at sp [PAki lk a]
  where
    lk = ceLook env
    at sp = map ((ceSizeSource env, sp),)
    -- the look inside: the inner setting wins, the rest is inherited (golem-driver ADR 0004)
    restyled = concatMap (piecesOf env {ceLook = ceRestyle env lk inl, ceSizeSource = ceSizeSourceOf env (ceSizeSource env) inl})
    {- the mark of a note or a numbered sidenote (golem-driver ADR 0018):
    set at the mark size (golem-driver ADR 0025), as wide as its advance
    across, the mark size down; the box keeps the look of its place -}
    markPiece t =
      let m = noteMarkSize (ceNoteMarkSize env) (lkSize lk)
          w
            | ceVertical env = m
            | otherwise = round (ceWordAdvance env lk {lkSize = m} t * toRational m)
       in PBox lk t KindNoteMark w

{- | The size of a note mark in text of a size (golem-driver ADR 0018,
0025): the mark size of style.toml, at least 1sp and at most the size of
the text.
-}
noteMarkSize :: Dim -> Sp -> Sp
noteMarkSize d s = max 1 (min s (dimToSp s d))

-- | The text of a note mark: {n} of the format replaced by the number (golem-driver ADR 0025).
noteMarkText :: Text -> Int -> Text
noteMarkText format n = T.replace "{n}" (T.pack (show n)) format

textPieces :: Look -> Text -> [Piece]
textPieces lk t
  | breaksAsCode lk = codePieces lk t
  | otherwise = go (zip units latinish)
  where
    {- the units of the text: a base character and the combining characters
    after it, variation selectors among them (golem-pdf ADR 0006,
    golem-driver ADR 0036); the classes come from the base characters -}
    units = [(T.head u, T.tail u) | u <- clusters t]
    cs = map fst units
    isLatinWordChar c = charClass c == Western && not (isSpace c)
    -- quotation marks, apostrophes, hyphens and dashes join a Latin word when
    -- the nearest letter on either side is Latin (I’ll, “Mercy”—“We”,
    -- lime‐tree, 1990–2000; golem-layout ADR 0008)
    isJoiner c = c `elem` ("‘’“”—‐‑–" :: String)
    latinish =
      [ isLatinWordChar c || (isJoiner c && (side (reverse before) || side after))
      | (i, c) <- zip [0 :: Int ..] cs,
        let before = take i cs
            after = drop (i + 1) cs
      ]
    side rest = case dropWhile isJoiner rest of
      (c : _) -> isLatinWordChar c
      [] -> False
    go [] = []
    go (((c, marks), l) : rest)
      | c == ' ' = PSpace lk : go (dropWhile ((== ' ') . fst . fst) rest)
      | l =
          let (w, rest') = span snd (((c, marks), l) : rest)
           in PWord lk (T.concat [T.cons b m | ((b, m), _) <- w]) : go rest'
      | otherwise = PChar lk c marks : go rest

{- | The text of code (golem-driver ADR 0017): spaces as breaks of a fixed
width (golem-layout ADR 0017), a
tab as other text has it, and each run of the rest as one piece.
-}
codePieces :: Look -> Text -> [Piece]
codePieces lk = go
  where
    go t = case T.uncons t of
      Nothing -> []
      Just (' ', _) -> PSpace lk : go (T.dropWhile (== ' ') t)
      Just ('\t', rest) -> PChar lk '\t' "" : go rest
      Just _ ->
        let (run, rest) = T.break (\c -> c == ' ' || c == '\t') t
         in PCode lk run 0 0 : go rest

numberPieces :: ComposeEnv -> Integer -> Maybe NumberStyle -> [Piece]
numberPieces env n style
  | not (ceVertical env) = textPieces lk (T.pack (show n))
  | otherwise = case fromMaybe (verticalStyleOf (ceVerticalNumbers env) n) style of
      StyleKanji -> textPieces lk (kanji n)
      StyleKanjiDigits -> textPieces lk (kanjiDigits n)
      StyleTcy -> [PBox lk (T.pack (show n)) KindTcy (lkSize lk)]
  where
    lk = ceLook env

{- | Ruby: half-size reading above the base. Several segments, or one
base character, are mono ruby; one segment over several characters is a
group ruby (golem-layout ADR 0009). Mono ruby may break between bases.
The width is decided with the neighbours ('itemsFor').
-}
rubyPieces :: ComposeEnv -> [RubySegment] -> [Piece]
rubyPieces env segs = concat (zipWith piece [0 :: Int ..] segs)
  where
    -- no kenten on a ruby base (golem-layout ADR 0011, golem-driver ADR 0019)
    lk = (ceLook env) {lkKenten = Nothing}
    piece i (RubySegment base reading) =
      let chars = concatMap (baseChars env lk) base
          baseStr = T.concat (map fst chars)
          kind = if length segs >= 2 || length chars == 1 then MonoRuby else GroupRuby
       in [PRubyBreak | i > 0] <> [PRuby lk kind baseStr (map snd chars) reading]

{- | The characters of a ruby base, each with its look (golem-layout ADR
0011): a character style or colour inside restyles its characters as
outside a ruby; kenten, tate-chu-yoko and numbers keep the look around
them; notes, index marks and the rest give no characters.
-}
baseChars :: ComposeEnv -> Look -> InlineNoRuby -> [(Text, Look)]
baseChars env lk inl = case inl of
  Text _ t -> each t
  Color _ _ xs -> inner xs
  CharStyle _ _ xs -> inner xs
  Kenten _ _ xs -> concatMap (baseChars env lk) xs
  Tcy _ t -> each t
  Number _ n _ -> each (T.pack (show n))
  _ -> []
  where
    -- a base character with its combining characters is one base (golem-driver ADR 0036)
    each t = [(u, lk) | u <- clusters t]
    inner = concatMap (baseChars env (ceRestyle env lk (withRuby inl)))

-- | An inline without ruby as an inline: the 'Ruby' constructor cannot occur.
withRuby :: InlineNoRuby -> Inline
withRuby = \case
  Text s t -> Text s t
  Kenten s sh xs -> Kenten s sh (map withRuby xs)
  Color s c xs -> Color s c (map withRuby xs)
  CharStyle s c xs -> CharStyle s c (map withRuby xs)
  Tcy s t -> Tcy s t
  Number s n st -> Number s n st
  Ref s k l -> Ref s k l
  Deferred s e -> Deferred s e
  Note s n xs -> Note s n (map withRuby xs)
  Sidenote s n xs -> Sidenote s n (map withRuby xs)
  IndexMark s e -> IndexMark s e
  Cite s k -> Cite s k
  ProofComment s t -> ProofComment s t
  LineBreak s -> LineBreak s
  Aki s a -> Aki s a
  ChannelItem s c -> ChannelItem s c

-- | The advance of a character in a look, in sp.
advance :: ComposeEnv -> Look -> Char -> Sp
advance env lk c = round (ceAdvance env lk c * toRational (lkSize lk))

-- | The tracking of a look in sp: lkTracking thousandths of its size (docs/adr/0020).
tracking :: Look -> Sp
tracking lk = round (toInteger (lkTracking lk) * lkSize lk % 1000)

{- | The pair kerning of Japanese characters (docs/adr/0020): two boxes of
one Japanese character each, side by side, of the same look with metrics
kerning and neither of them punctuation or an inseparable character
(golem-driver ADR 0020), whose spacing the rules of
JLReq decide. The kerning widens (narrows) the first box and is given
back at its end edge, so that it does not count at the end of a line.
-}
kernPairs :: ComposeEnv -> [Item] -> [Item]
kernPairs env = \case
  Box w p : rest@(Box _ c : _)
    | Just a <- single p,
      Just b <- single c,
      bcLook p == bcLook c,
      lkKerning (bcLook p) == KernMetrics,
      not (lkCode (bcLook p)) ->
        let k = round (ceKern env (bcLook p) a b * toRational (lkSize (bcLook p)))
         in Box (w + k) p {bcEdgeEnd = bcEdgeEnd p - k} : kernPairs env rest
  x : rest -> x : kernPairs env rest
  [] -> []
  where
    single c = case T.unpack (baseText (bcText c)) of
      [ch]
        | boxKind c `elem` [KindText, KindKenten],
          charClass ch `notElem` [Western, Opening, Closing, FullStop, Comma, MiddleDot, Inseparable] ->
            Just ch
      _ -> Nothing

-- ------------------------------------------------------------------ items

{- | Space before and after a punctuation glyph, in em (JLReq: the glyph
sits in half of its full-width cell).
-}
punctSpace :: CharClass -> (Rational, Rational)
punctSpace = \case
  Opening -> (1 / 2, 0)
  Closing -> (0, 1 / 2)
  FullStop -> (0, 1 / 2)
  Comma -> (0, 1 / 2)
  MiddleDot -> (1 / 4, 1 / 4)
  _ -> (0, 0)

{- | Whether a character takes kenten (golem-driver ADR 0019): not
punctuation (P), a separator (Z) or a control or format character (Cc,
Cf), as CSS text-emphasis has it.
-}
takesKenten :: Char -> Bool
takesKenten c = case generalCategory c of
  ConnectorPunctuation -> False
  DashPunctuation -> False
  OpenPunctuation -> False
  ClosePunctuation -> False
  InitialQuote -> False
  FinalQuote -> False
  OtherPunctuation -> False
  Space -> False
  LineSeparator -> False
  ParagraphSeparator -> False
  Control -> False
  Format -> False
  _ -> True

-- | Kana a ruby may overhang: hiragana, katakana, small kana and the long vowel mark.
isKanaClass :: CharClass -> Bool
isKanaClass cls = cls `elem` [Kana, SmallKana, ProlongedSound]

{- | The advances of the base characters of a ruby (a base character with
its combining characters, golem-driver ADR 0036), each in its own look
(golem-layout ADR 0011); characters without one take the ruby's look.
-}
baseAdvances :: ComposeEnv -> Look -> [Look] -> Text -> [Sp]
baseAdvances env lk looks = zipWith unit (looks <> repeat lk) . clusters
  where
    -- a base character and its combining characters, shaped together (golem-driver ADR 0036)
    unit l u = case T.unpack u of
      [c] -> advance env l c
      _ -> round (ceWordAdvance env l u * toRational (lkSize l))

-- | The advances of the reading characters: half the size of the base, as drawn.
readingAdvances :: ComposeEnv -> Look -> Maybe Text -> [Sp]
readingAdvances env lk = maybe [] (map (advance env lk {lkSize = lkSize lk `div` 2}) . T.unpack)

itemsFor :: ComposeEnv -> Maybe Piece -> Piece -> Maybe Piece -> [Item]
itemsFor env prev p next = case p of
  PChar lk c vs ->
    let cls = charClass c
        fs = lkSize lk
        (pre, post) = punctSpace cls
        -- with variation selectors: shaped together with them
        full
          | T.null vs = advance env lk c
          | otherwise = round (ceWordAdvance env lk (T.cons c vs) * toRational fs)
        w = full - round ((pre + post) * toRational fs)
        -- tracking after the character, given back at the line end (docs/adr/0020)
        t = tracking lk
        -- kenten on characters other than punctuation and separators (golem-driver ADR 0019)
        tag
          | isJust (lkKenten lk) && takesKenten c = KindKenten
          | ceVertical env && cls == Western = KindRotated
          | pre + post > 0 = KindPunctuation
          | otherwise = KindText
        hang = if ceHanging env && cls `elem` [FullStop, Comma] then w else 0
     in [Box (w + t) (BoxContent (T.cons c vs) False 0 hang (fromEnum tag) lk 0 (negate t) [] 0 0 (ceBoxSource env))]
  PWord lk word -> wordItems env lk word
  PSpace lk ->
    let sw = advance env lk ' '
     in if lkCode lk
          then [Glue (sw + tracking lk) 0 0] -- a space of inline code neither stretches nor shrinks (golem-layout ADR 0017)
          else [Glue (sw + tracking lk) (sw `div` 2) (sw `div` 3)]
  PBox lk t kind w -> [Box w (BoxContent t False 0 0 (fromEnum kind) lk 0 0 [] 0 0 (ceBoxSource env))]
  PRuby lk kind base looks reading ->
    let style = ceRuby env
        rp = placeRuby style kind (baseAdvances env lk looks base) (readingAdvances env lk reading) (allowance True prev, allowance False next)
        -- how far the reading may overhang a neighbour: kana up to half its
        -- advance, the free space of a neighbouring reading, nothing else;
        -- a neighbouring base is measured in the looks of its characters
        allowance before = \case
          _ | not (rsOverhangOntoKana style) -> 0
          Just (PChar lk' c _) | isNothing (lkKenten lk'), isKanaClass (charClass c) -> min (rsOverhang style) (advance env lk' c `div` 2)
          Just (PRuby lk' _ b ls Nothing) -> case (if before then reverse else id) (zip (map T.head (clusters b)) (ls <> repeat lk')) of
            (c, lc) : _ | isKanaClass (charClass c) -> min (rsOverhang style) (advance env lc c `div` 2)
            _ -> 0
          Just (PRuby lk' k b ls r@(Just _)) ->
            let ras = readingAdvances env lk' r
                placed = placeRuby style k (baseAdvances env lk' ls b) ras (0, 0)
                room = case (rpReading placed, reverse (zip (rpReading placed) ras)) of
                  (firstPos : _, (lastPos, lastAdv) : _) -> if before then rpWidth placed - (lastPos + lastAdv) else firstPos
                  _ -> 0
             in min (rsOverhang style) (max 0 room)
          _ -> 0
        tag = case kind of
          MonoRuby -> KindRuby
          GroupRuby -> KindGroupRuby
     in [Box (rpWidth rp) (BoxContent (base <> maybe "" ("|" <>) reading) False 0 0 (fromEnum tag) lk (rpOverhang rp) (rpOverhang rp) looks 0 0 (ceBoxSource env))]
  PRubyBreak -> [Penalty 0 0 NoHyphen]
  -- normalize sees no box next to these items: the spacing is that of the line's edge
  PForcedBreak -> lineEnd
  -- zw is the size of the type at its place; an empty box: no break between it and a neighbouring box (golem-layout ADR 0012)
  PAki lk a ->
    let w = case a of
          AkiZw r -> round (r * toRational (lkSize lk))
          AkiAbs x -> x
     in [Box w (BoxContent "" False 0 0 (fromEnum KindAki) lk 0 0 [] 0 0 (ceBoxSource env))]
  PCode lk run ps pe -> codeItems env lk run ps pe
  PAnchor _ -> []

{- | A run of code (golem-driver ADR 0017): a box for each part of Latin or
other text, cut after each slash; 'normalize' allows a break after a
slash and nothing else between the boxes. No hyphenation, protrusion or
expansion.
-}
codeItems :: ComposeEnv -> Look -> Text -> Sp -> Sp -> [Item]
codeItems env lk run padStart padEnd =
  [ Box (w + tr * toInteger (T.length seg) + ps + pe) (BoxContent seg False 0 0 (fromEnum tag) lk 0 (negate tr) [] ps pe (ceBoxSource env))
  | let segs = [seg | part <- slashParts run, seg <- T.groupBy sameSide part]
        lastIx = length segs - 1,
    (i, seg) <- zip [0 :: Int ..] segs,
    let latin = maybe False ((== Western) . charClass . fst) (T.uncons seg)
        w = round (ceWordAdvance env lk seg * toRational (lkSize lk))
        tag = if ceVertical env && latin then KindRotated else KindText
        ps = if i == 0 then padStart else 0
        pe = if i == lastIx then padEnd else 0
  ]
  where
    tr = tracking lk
    sameSide a b = isExtending b || (charClass a == Western) == (charClass b == Western)
    slashParts = if lkUrl lk then urlParts else codeParts
    -- code breaks after each slash (golem-driver ADR 0017)
    codeParts t = case T.breakOn "/" t of
      (a, rest)
        | T.null rest -> [a | not (T.null a)]
        | otherwise -> (a <> "/") : codeParts (T.drop 1 rest)

{- | A URL cut after each character it may break after (golem-layout ADR
0018): the characters of url.sty's breaks, but not a slash or a colon
before a slash, so that a run of slashes and "https://" stay whole.
-}
urlParts :: Text -> [Text]
urlParts t = filter (not . T.null) (go (T.unpack t))
  where
    go s = case cut s of
      (a, []) -> [T.pack a]
      (a, rest) -> T.pack a : go rest
    cut = \case
      [] -> ([], [])
      c : rest@(d : _) | c `elem` urlBreakChars, not (d == '/' && c `elem` ("/:" :: String)) -> ([c], rest)
      c : rest -> let (a, r) = cut rest in (c : a, r)

-- | The characters a URL may break after (golem-layout ADR 0018): url.sty's \UrlBreaks and \UrlBigBreaks.
urlBreakChars :: String
urlBreakChars = "/.@!_|;>]),?&'+=#:"

{- | The penalty of a break inside a URL after the text of a box, if it
may break there (golem-layout ADR 0018): 0 after a slash, 100 after the
other characters of 'urlBreakChars'.
-}
urlBreakAfter :: Text -> Maybe Int
urlBreakAfter t = case T.unsnoc t of
  Just (_, '/') -> Just 0
  Just (_, c) | c `elem` urlBreakChars -> Just 100
  _ -> Nothing

{- | Whether text breaks as code: only at spaces and after a slash, with
no hyphenation and no aki inside (golem-driver ADR 0017, golem-doc ADR 0005).
-}
breaksAsCode :: Look -> Bool
breaksAsCode lk = lkCode lk || lkUrl lk

{- | The padding of inline code (golem-driver ADR 0029): in each run of
pieces of code with the same background and padding (spaces, tabs, note
marks and ruby included, anchors skipped), the first piece takes the
padding before it and the last the padding after it when they are runs
of code.
-}
padCode :: [Piece] -> [Piece]
padCode = \case
  [] -> []
  p : rest
    | Just k <- codeKey p ->
        let (run, rest') = span (\q -> transparent q || codeKey q == Just k) rest
         in padded (p : run) <> padCode rest'
    | otherwise -> p : padCode rest
  where
    codeKey = \case
      PCode l _ _ _ -> key l
      PSpace l -> key l
      PChar l _ _ -> key l
      PBox l _ KindNoteMark _ -> key l
      PRuby l _ _ _ _ -> key l
      PRubyBreak -> Nothing
      _ -> Nothing
    key l = if lkCode l then Just (lkBackground l, lkPadding l) else Nothing
    transparent = \case
      PAnchor _ -> True
      PRubyBreak -> True
      _ -> False
    -- the padding goes on the first and the last piece when they are code
    padded run = case [i | (i, q) <- zip [0 :: Int ..] run, not (transparent q)] of
      [] -> run
      ixs@(firstIx : _) ->
        let lastIx = last ixs
            set i = \case
              PCode l t _ _ -> PCode l t (if i == firstIx then lkPadding l else 0) (if i == lastIx then lkPadding l else 0)
              q -> q
         in zipWith set [0 ..] run

{- | A Latin word: broken after its explicit hyphens and dashes, or else
where the patterns allow. A word with a hyphen or dash in it gets no
pattern hyphens, as in TeX (golem-layout ADR 0008).
-}
wordItems :: ComposeEnv -> Look -> Text -> [Item]
wordItems env lk word =
  let explicitP = ceExplicitHyphenPenalty env
      (parts, pen)
        | T.any (`elem` ("-‐‑–—" :: String)) word =
            (if explicitP >= infPenalty then [word] else explicitParts word, Penalty 0 explicitP ExplicitHyphen)
        | otherwise = (maybe [word] (`hyphenateUnits` word) (cePatterns env), Penalty (advance env lk '-') 50 (PatternHyphen (protAt snd '-')))
      rotated = ceVertical env
      tag = fromEnum (if rotated then KindRotated else KindText)
      tr = tracking lk
      -- the tracking after each character, given back at the line end (docs/adr/0020)
      box t =
        let w = round (ceWordAdvance env lk t * toRational (lkSize lk))
            ps = maybe 0 (min w . protAt fst . fst) (T.uncons t)
            pe = maybe 0 (min w . protAt snd . snd) (T.unsnoc t)
         in Box (w + tr * toInteger (T.length t)) (BoxContent t True ps pe tag lk 0 (negate tr) [] 0 0 (ceBoxSource env))
      -- the advance of the character at the line end, without tracking, by its ratio (golem-layout ADR 0014)
      protAt pick c = if ceProtrusion env then advance env lk c * pick (protrusionRatio c) `div` 1000 else 0
   in concat [box part : [pen | i < length parts - 1] | (i, part) <- zip [0 :: Int ..] parts]

{- | A word cut after each run of hyphens and dashes that has a character
before it and one after it (lime-|tree, a--|b; not -5 or pre-).
-}
explicitParts :: Text -> [Text]
explicitParts word = go [] (zip [0 :: Int ..] groups)
  where
    isExplicit c = c `elem` ("-‐–—" :: String)
    -- a combining character after a hyphen stays with the hyphen (golem-driver ADR 0036)
    groups = map T.concat (groupBy (\a b -> isExplicit (T.head a) == isExplicit (T.head b)) (clusters word))
    lastIx = length groups - 1
    cutAfter i g = i > 0 && i < lastIx && T.all isExplicit (T.filter (not . isExtending) g)
    go acc [] = [T.concat (reverse acc) | not (null acc)]
    go acc ((i, g) : rest)
      | cutAfter i g = T.concat (reverse (g : acc)) : go [] rest
      | otherwise = go (g : acc) rest

{- | A word hyphenated by the patterns (golem-driver ADR 0036): the
patterns see the word without its combining characters, and each cut
goes after as many base characters, with their combining characters, in
the word itself; no part starts with a combining character.
-}
hyphenateUnits :: Patterns -> Text -> [Text]
hyphenateUnits p word
  | T.any isExtending word = cut (map T.length (hyphenate p (T.filter (not . isExtending) word))) (clusters word)
  | otherwise = hyphenate p word
  where
    bases u = if maybe False (isExtending . fst) (T.uncons u) then 0 else 1 :: Int
    -- the last part takes the rest
    cut ns us = case ns of
      n : rest@(_ : _) -> let (a, b) = takeBases n us in T.concat a : cut rest b
      _ -> [T.concat us | not (null us)]
    takeBases n = \case
      u : us
        | n > 0 || bases u == 0 -> let (a, b) = takeBases (n - bases u) us in (u : a, b)
      us -> ([], us)

-- | What comes before an item in 'normalize'.
data Before
  = -- | the start of the paragraph, or an item that is neither a box nor an [aki]
    AtStart
  | -- | a note mark at the start of the paragraph (golem-driver ADR 0018)
    AfterStartMark
  | -- | the box of an [aki] (docs/adr ADR 0019, golem-layout ADR 0012)
    AfterAki
  | AfterBox !BoxContent

{- | Inserts break opportunities and spacing between neighbouring boxes:
no break where a prohibition applies (golem-layout ADR 0002), and the
spacing of the aki set of the paragraph (docs/adr ADR 0019). The spaces
of the line start and the line end are the edges of the boxes. An [aki]
is an empty box between its neighbours: the set adds no space there, and
it has no edges (golem-layout ADR 0012).
-}
normalize :: ComposeEnv -> [Item] -> [Item]
normalize env = go AtStart True
  where
    set = ceAkiSet env
    go _ _ [] = []
    go before first (x : rest) = case x of
      -- an [aki]: no spacing around it, no edges; the paragraph's first character is still to come
      Box _ c | boxKind c == KindAki -> x : go AfterAki first rest
      {- a note mark joins the box before it (golem-driver ADR 0018): no
      break and no spacing before it, and the spacing of the pair around
      it after it; it has no edges -}
      Box w c
        | boxKind c == KindNoteMark ->
            let before' = case before of
                  AtStart -> AfterStartMark
                  other -> other
             in Penalty 0 infPenalty NoHyphen : Box w c {bcEdgeStart = 0, bcEdgeEnd = 0} : go before' first rest
      Box w c ->
        let spacing = case before of
              -- inside code: a break after a slash, no spacing (golem-driver ADR 0017)
              -- inside a URL: a break after the characters of url.sty's breaks (golem-layout ADR 0018)
              AfterBox p | lkUrl (bcLook p) && lkUrl (bcLook c) -> [Penalty 0 n NoHyphen | Just n <- [urlBreakAfter (bcText p)]]
              AfterBox p | breaksAsCode (bcLook p) && breaksAsCode (bcLook c) -> [Penalty 0 0 NoHyphen | "/" `T.isSuffixOf` bcText p]
              AfterBox p -> between p c
              AtStart -> leading c
              -- the space of the paragraph start, after the mark: no break there
              AfterStartMark -> case leading c of
                [] -> []
                l -> Penalty 0 infPenalty NoHyphen : l
              AfterAki -> []
         in spacing <> [Box w (withEdges first c)] <> go (AfterBox c) False rest
      _ -> x : go AtStart first rest
    sizeOf = lkSize . bcLook
    glueOf base (A.Aki n o m) =
      let sp r = round (r * toRational base)
       in [Glue (sp o) (sp m - sp o) (sp o - sp n)]
    -- the space before the first box of a paragraph, in the box's size
    leading c = case akiFirst c of
      Just b | a <- akiBetween set AkiParagraphStart (AkiChar b), a /= noAki -> glueOf (sizeOf c) a
      _ -> []
    -- the line start (but not the paragraph start) and the line end are fixed, in the box's size
    withEdges first c = case (akiFirst c, akiLast c) of
      (Just f, Just l) ->
        let edge a = round (A.akiOptimum a * toRational (sizeOf c))
         in c
              { bcEdgeStart = bcEdgeStart c + (if first then 0 else edge (akiBetween set AkiLineStart (AkiChar f))),
                bcEdgeEnd = bcEdgeEnd c + edge (akiBetween set (AkiChar l) AkiLineEnd)
              }
      _ -> c
    -- the classes come from the base characters, without combining characters (golem-driver ADR 0036)
    baseOf = baseText . bcText
    firstClass c = case T.uncons (baseOf c) of
      Just (ch, _) | not (isRuby c) -> Just (charClass ch)
      _ -> Nothing
    lastClass c = case T.unsnoc (baseOf c) of
      Just (_, ch) | not (isRuby c) -> Just (charClass ch)
      _ -> Nothing
    isRuby c = boxKind c `elem` [KindRuby, KindGroupRuby]
    -- a Latin word is Latin text at both ends, quotation marks and dashes included
    akiFirst c = if bcExpandable c then Just Western else firstClass c
    akiLast c = if bcExpandable c then Just Western else lastClass c
    isPunct k = k `elem` [Opening, Closing, FullStop, Comma, MiddleDot]
    between p c =
      let pc = lastClass p
          cc = firstClass c
          strict = ceKinsokuStrict env
          noBreak =
            maybe False (lineStartProhibited strict) cc
              || maybe False lineEndProhibited pc
              || (pc == Just Inseparable && cc == Just Inseparable)
              || (pc == Just Western && cc == Just Western && bcExpandable p && bcExpandable c)
          pen = [Penalty 0 infPenalty NoHyphen | noBreak]
          -- a ruby is an ideograph next to punctuation, so that the punctuation keeps its space
          classes = case (akiLast p, akiFirst c) of
            (Nothing, Just b) | isPunct b -> Just (Ideograph, b)
            (Just a, Nothing) | isPunct a -> Just (a, Ideograph)
            (Just a, Just b) -> Just (a, b)
            _ -> Nothing
          -- zw: the punctuation's size, the larger of two, or the paragraph's
          base a b
            | isPunct a && isPunct b = max (sizeOf p) (sizeOf c)
            | isPunct a = sizeOf p
            | isPunct b = sizeOf c
            | otherwise = ceFontSize env
       in case classes of
            Just (a, b)
              | aki <- akiBetween set (AkiChar a) (AkiChar b),
                aki /= noAki ->
                  pen <> glueOf (base a b) aki
            Just _ -> [Penalty 0 0 NoHyphen | not noBreak]
            Nothing -> if noBreak then [] else [Penalty 0 0 NoHyphen | not (bcExpandable p && bcExpandable c)]

-- | Sidenotes in vertical text are compile errors (ADR 0006; the message is golem-driver ADR 0016).
verticalSidenotes :: ComposeEnv -> [Inline] -> [Diagnostic]
verticalSidenotes env inls
  | not (ceVertical env) = []
  | otherwise = concatMap go inls
  where
    msg = "縦組みの版面では傍注を使えません。脚注に替えてください"
    go = \case
      Sidenote sp _ _ -> [diagnostic "G07032" Error sp msg]
      Kenten _ _ xs -> concatMap go xs
      Color _ _ xs -> concatMap go xs
      CharStyle _ _ xs -> concatMap go xs
      Note _ _ xs -> concatMap go xs
      _ -> []
