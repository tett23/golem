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
    ComposeEnv (..),
    SidenoteMarker (..),
    defaultComposeEnv,
    Anchor (..),
    BoxKind (..),
    boxKind,
    noteMarkSize,
    composeInlines,
    lineStartProhibited,
    lineEndProhibited,
    protrusionRatio,
    verticalSidenotes,
    punctSpace,
  )
where

import Data.Char (isSpace)
import Data.Maybe (fromMaybe)
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
    ceVerticalNumbers :: !(Maybe NumberStyle),
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
    ceCiteNumber :: Text -> Maybe Int,
    {- | the penalty of a break after a hyphen or dash in a Latin word;
    10000 or more means no such break (golem-layout ADR 0008)
    -} ceExplicitHyphenPenalty :: !Int,
    -- | the aki set of the paragraph (docs/adr ADR 0019)
    ceAkiSet :: !AkiSet
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
      ceVerticalNumbers = Nothing,
      cePatterns = Nothing,
      cePageOf = const Nothing,
      ceLook = plainLook "body" fs,
      ceRestyle = const,
      ceSidenoteMarker = MarkerNumber,
      ceCiteNumber = const Nothing,
      ceExplicitHyphenPenalty = 50,
      ceAkiSet = defaultAkiSet
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

{- | The text of a box without its trailing variation selectors, unless
nothing else is left: the character classes come from the base character.
-}
withoutSelectors :: Text -> Text
withoutSelectors t = case T.dropWhileEnd isVariationSelector t of
  base | T.null base -> t
  base -> base

-- | Things the pagination must know about, at an item index.
data Anchor
  = AnchorNote !Int !Int !SrcSpan [Inline] -- item index, note number, span, body
  | AnchorSidenote !Int !Int !SrcSpan [Inline] -- item index, sidenote number, span, body
  | AnchorPageRef !Int !Text
  | AnchorIndex !Int !SrcSpan IndexEntry -- item index, the mark, the entry
  deriving stock (Eq, Show)

{- | What a box shows (kept in 'bcTag').
'KindRuby' is a mono ruby, 'KindGroupRuby' a group ruby (golem-layout ADR 0009).
-}
data BoxKind = KindText | KindRuby | KindTcy | KindRotated | KindKenten | KindPunctuation | KindGroupRuby | KindNoteMark
  deriving stock (Eq, Show, Enum, Bounded)

boxKind :: BoxContent -> BoxKind
boxKind = toEnum . bcTag

-- ------------------------------------------------------------------ pieces

-- One unit of composition before items are generated, with its look.
data Piece
  = PChar !Look !Char !Text !Bool -- the character, its variation selectors, kenten
  | PWord !Look !Text -- a Latin word (no spaces)
  | PSpace !Look -- an inter-word space
  | PBox !Look !Text !BoxKind !Sp -- ruby, tcy, …: an unbreakable box of a given width
  | PRuby !Look !RubyKind !Text !(Maybe Text) -- ruby: the base and the reading (none for a segment without one)
  | PRubyBreak -- a break allowed between mono ruby bases
  | PForcedBreak -- a hard line break: the line ends as a paragraph does (docs/adr ADR 0016)
  | PAki !Look !AkiAmount -- [aki]: a fixed space, no break around it (docs/adr ADR 0019)
  | PCode !Look !Text -- a run of code without spaces and tabs (golem-driver ADR 0017)
  | PAnchor (Int -> Anchor)

composeInlines :: ComposeEnv -> [Inline] -> ([Item], [Anchor])
composeInlines env inls =
  let pieces = concatMap (piecesOf env False) inls
      (items, anchors) = foldl' emit ([], []) (zip3 prevs pieces nexts)
      emit (acc, as) (_, PAnchor f, _) = (acc, (length acc, f) : as)
      emit (acc, as) (pv, p, nx) = (acc <> itemsFor env pv p nx, as)
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

piecesOf :: ComposeEnv -> Bool -> Inline -> [Piece]
piecesOf env kenten inl = case inl of
  Text _ t -> textPieces lk kenten t
  Color _ _ xs -> restyled xs
  CharStyle _ _ xs -> restyled xs
  Kenten _ _ xs -> concatMap (piecesOf env True) xs
  Ruby _ _ segs -> rubyPieces env segs
  Tcy _ t -> [PBox lk t KindTcy (lkSize lk)]
  Number _ n style -> numberPieces env n style
  Ref _ RefPage l ->
    let n = fromMaybe 1 (cePageOf env l)
     in PAnchor (`AnchorPageRef` l) : textPieces lk False (T.pack (show n))
  Ref _ _ l -> textPieces lk False l
  Deferred {} -> []
  Note sp n body -> [PAnchor (\i -> AnchorNote i n sp body), markPiece ("*" <> T.pack (show n))]
  Sidenote sp n body ->
    PAnchor (\i -> AnchorSidenote i n sp body) : case ceSidenoteMarker env of
      MarkerNumber -> [markPiece (T.pack (show n))]
      MarkerSymbol -> [PBox lk "※" KindText (lkSize lk)]
      MarkerNone -> []
  IndexMark sp e -> [PAnchor (\i -> AnchorIndex i sp e)]
  Cite _ k -> textPieces lk False ("[" <> maybe k (T.pack . show) (ceCiteNumber env k) <> "]")
  ProofComment {} -> []
  -- the lines of a keep style are split before they are composed (docs/adr
  -- ADR 0005); what reaches here is a hard break (docs/adr ADR 0016)
  LineBreak {} -> [PForcedBreak]
  Aki _ a -> [PAki lk a]
  where
    lk = ceLook env
    -- the look inside: the inner setting wins, the rest is inherited (golem-driver ADR 0004)
    restyled = concatMap (piecesOf env {ceLook = ceRestyle env lk inl} kenten)
    {- the mark of a note or a numbered sidenote (golem-driver ADR 0018):
    set at half the size, as wide as its advance across, half the size
    down; the box keeps the look of its place -}
    markPiece t =
      let m = noteMarkSize (lkSize lk)
          w
            | ceVertical env = m
            | otherwise = round (ceWordAdvance env lk {lkSize = m} t * toRational m)
       in PBox lk t KindNoteMark w

-- | The size of a note mark in text of a size (golem-driver ADR 0018).
noteMarkSize :: Sp -> Sp
noteMarkSize s = s `div` 2

textPieces :: Look -> Bool -> Text -> [Piece]
textPieces lk kenten t
  | lkCode lk = codePieces lk t
  | otherwise = reverse (foldl' attach [] (go (zip cs latinish)))
  where
    -- variation selectors join the character or word before them (golem-pdf ADR 0006)
    attach acc p = case (acc, p) of
      (PChar l c vs k : rest, PChar _ v "" _) | isVariationSelector v -> PChar l c (T.snoc vs v) k : rest
      (PWord l w : rest, PChar _ v "" _) | isVariationSelector v -> PWord l (T.snoc w v) : rest
      _ -> p : acc
    cs = T.unpack t
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
    go ((c, l) : rest)
      | c == ' ' = PSpace lk : go (dropWhile ((== ' ') . fst) rest)
      | l =
          let (w, rest') = span snd ((c, l) : rest)
           in PWord lk (T.pack (map fst w)) : go rest'
      | otherwise = PChar lk c "" kenten : go rest

{- | The text of code (golem-driver ADR 0017): spaces as between words, a
tab as other text has it, and each run of the rest as one piece.
-}
codePieces :: Look -> Text -> [Piece]
codePieces lk = go
  where
    go t = case T.uncons t of
      Nothing -> []
      Just (' ', _) -> PSpace lk : go (T.dropWhile (== ' ') t)
      Just ('\t', rest) -> PChar lk '\t' "" False : go rest
      Just _ ->
        let (run, rest) = T.break (\c -> c == ' ' || c == '\t') t
         in PCode lk run : go rest

numberPieces :: ComposeEnv -> Integer -> Maybe NumberStyle -> [Piece]
numberPieces env n style
  | not (ceVertical env) = textPieces lk False (T.pack (show n))
  | otherwise = case style <|> ceVerticalNumbers env of
      Just StyleKanji -> textPieces lk False (kanji n)
      Just StyleKanjiDigits -> textPieces lk False (kanjiDigits n)
      Just StyleTcy -> [PBox lk (T.pack (show n)) KindTcy (lkSize lk)]
      Nothing -> textPieces lk False (kanji n)
  where
    lk = ceLook env
    Nothing <|> b = b
    a <|> _ = a

{- | Ruby: half-size reading above the base. Several segments, or one
base character, are mono ruby; one segment over several characters is a
group ruby (golem-layout ADR 0009). Mono ruby may break between bases.
The width is decided with the neighbours ('itemsFor').
-}
rubyPieces :: ComposeEnv -> [RubySegment] -> [Piece]
rubyPieces env segs = concat (zipWith piece [0 :: Int ..] segs)
  where
    lk = ceLook env
    piece i (RubySegment base reading) =
      let baseText = T.concat (map plain base)
          kind = if length segs >= 2 || T.length baseText == 1 then MonoRuby else GroupRuby
       in [PRubyBreak | i > 0] <> [PRuby lk kind baseText reading]
    plain = \case
      Text _ t -> t
      Color _ _ xs -> T.concat (map plain xs)
      CharStyle _ _ xs -> T.concat (map plain xs)
      Kenten _ _ xs -> T.concat (map plain xs)
      Tcy _ t -> t
      Number _ n _ -> T.pack (show n)
      _ -> ""

-- | The advance of a character in a look, in sp.
advance :: ComposeEnv -> Look -> Char -> Sp
advance env lk c = round (ceAdvance env lk c * toRational (lkSize lk))

-- | The tracking of a look in sp: lkTracking thousandths of its size (docs/adr/0020).
tracking :: Look -> Sp
tracking lk = round (toInteger (lkTracking lk) * lkSize lk % 1000)

{- | The pair kerning of Japanese characters (docs/adr/0020): two boxes of
one Japanese character each, side by side, of the same look with metrics
kerning and neither of them punctuation, whose spacing the rules of
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
    single c = case T.unpack (withoutSelectors (bcText c)) of
      [ch]
        | boxKind c `elem` [KindText, KindKenten],
          charClass ch `notElem` [Western, Opening, Closing, FullStop, Comma, MiddleDot] ->
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

-- | Kana a ruby may overhang: hiragana, katakana, small kana and the long vowel mark.
isKanaClass :: CharClass -> Bool
isKanaClass cls = cls `elem` [Kana, SmallKana, ProlongedSound]

-- | The advances of the base characters of a ruby, in the look of the paragraph.
baseAdvances :: ComposeEnv -> Look -> Text -> [Sp]
baseAdvances env lk = map (advance env lk) . T.unpack

-- | The advances of the reading characters: half the size of the base, as drawn.
readingAdvances :: ComposeEnv -> Look -> Maybe Text -> [Sp]
readingAdvances env lk = maybe [] (map (advance env lk {lkSize = lkSize lk `div` 2}) . T.unpack)

itemsFor :: ComposeEnv -> Maybe Piece -> Piece -> Maybe Piece -> [Item]
itemsFor env prev p next = case p of
  PChar lk c vs kenten ->
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
        tag
          | kenten = KindKenten
          | ceVertical env && cls == Western = KindRotated
          | pre + post > 0 = KindPunctuation
          | otherwise = KindText
        hang = if ceHanging env && cls `elem` [FullStop, Comma] then w else 0
     in [Box (w + t) (BoxContent (T.cons c vs) False 0 hang (fromEnum tag) lk 0 (negate t))]
  PWord lk word -> wordItems env lk word
  PSpace lk ->
    let sw = advance env lk ' '
     in [Glue (sw + tracking lk) (sw `div` 2) (sw `div` 3)]
  PBox lk t kind w -> [Box w (BoxContent t False 0 0 (fromEnum kind) lk 0 0)]
  PRuby lk kind base reading ->
    let style = ceRuby env
        rp = placeRuby style kind (baseAdvances env lk base) (readingAdvances env lk reading) (allowance True prev, allowance False next)
        -- how far the reading may overhang a neighbour: kana up to half its
        -- advance, the free space of a neighbouring reading, nothing else
        allowance before = \case
          _ | not (rsOverhangOntoKana style) -> 0
          Just (PChar lk' c _ False) | isKanaClass (charClass c) -> min (rsOverhang style) (advance env lk' c `div` 2)
          Just (PRuby lk' _ b Nothing) -> case (if before then T.unsnoc b else (\(h, t) -> (t, h)) <$> T.uncons b) of
            Just (_, c) | isKanaClass (charClass c) -> min (rsOverhang style) (advance env lk' c `div` 2)
            _ -> 0
          Just (PRuby lk' k b r@(Just _)) ->
            let ras = readingAdvances env lk' r
                p = placeRuby style k (baseAdvances env lk' b) ras (0, 0)
                room = case (rpReading p, reverse (zip (rpReading p) ras)) of
                  (firstPos : _, (lastPos, lastAdv) : _) -> if before then rpWidth p - (lastPos + lastAdv) else firstPos
                  _ -> 0
             in min (rsOverhang style) (max 0 room)
          _ -> 0
        tag = case kind of
          MonoRuby -> KindRuby
          GroupRuby -> KindGroupRuby
     in [Box (rpWidth rp) (BoxContent (base <> maybe "" ("|" <>) reading) False 0 0 (fromEnum tag) lk (rpOverhang rp) (rpOverhang rp))]
  PRubyBreak -> [Penalty 0 0 NoHyphen]
  -- normalize sees no box next to these items: the spacing is that of the line's edge
  PForcedBreak -> lineEnd
  -- zw is the size of the type at its place; the penalty and the glue after it keep the line whole
  PAki lk a ->
    let w = case a of
          AkiZw r -> round (r * toRational (lkSize lk))
          AkiAbs x -> x
     in [Penalty 0 infPenalty NoHyphen, Glue w 0 0]
  PCode lk run -> codeItems env lk run
  PAnchor _ -> []

{- | A run of code (golem-driver ADR 0017): a box for each part of Latin or
other text, cut after each slash; 'normalize' allows a break after a
slash and nothing else between the boxes. No hyphenation, protrusion or
expansion.
-}
codeItems :: ComposeEnv -> Look -> Text -> [Item]
codeItems env lk run =
  [ Box (w + tr * toInteger (T.length seg)) (BoxContent seg False 0 0 (fromEnum tag) lk 0 (negate tr))
  | part <- slashParts run,
    seg <- T.groupBy sameSide part,
    let latin = maybe False ((== Western) . charClass . fst) (T.uncons seg)
        w = round (ceWordAdvance env lk seg * toRational (lkSize lk))
        tag = if ceVertical env && latin then KindRotated else KindText
  ]
  where
    tr = tracking lk
    sameSide a b = isVariationSelector b || (charClass a == Western) == (charClass b == Western)
    slashParts t = case T.breakOn "/" t of
      (a, rest)
        | T.null rest -> [a | not (T.null a)]
        | otherwise -> (a <> "/") : slashParts (T.drop 1 rest)

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
        | otherwise = (maybe [word] (`hyphenate` word) (cePatterns env), Penalty (advance env lk '-') 50 PatternHyphen)
      rotated = ceVertical env
      tag = fromEnum (if rotated then KindRotated else KindText)
      tr = tracking lk
      -- the tracking after each character, given back at the line end (docs/adr/0020)
      box t =
        let w = round (ceWordAdvance env lk t * toRational (lkSize lk))
            (ps, _) = maybe (0, 0) (protrusionRatio . fst) (T.uncons t)
            (_, pe) = maybe (0, 0) (protrusionRatio . snd) (T.unsnoc t)
            prot r = if ceProtrusion env then min w (w * r `div` 1000) else 0
         in Box (w + tr * toInteger (T.length t)) (BoxContent t True (prot' ps t prot) (prot' pe t prot) tag lk 0 (negate tr))
      prot' r t f = if T.null t then 0 else f r
   in concat [box part : [pen | i < length parts - 1] | (i, part) <- zip [0 :: Int ..] parts]

{- | A word cut after each run of hyphens and dashes that has a character
before it and one after it (lime-|tree, a--|b; not -5 or pre-).
-}
explicitParts :: Text -> [Text]
explicitParts word = go [] (zip [0 :: Int ..] groups)
  where
    isExplicit c = c `elem` ("-‐–—" :: String)
    groups = T.groupBy (\a b -> isExplicit a == isExplicit b) word
    lastIx = length groups - 1
    cutAfter i g = i > 0 && i < lastIx && T.all isExplicit g
    go acc [] = [T.concat (reverse acc) | not (null acc)]
    go acc ((i, g) : rest)
      | cutAfter i g = T.concat (reverse (g : acc)) : go [] rest
      | otherwise = go (g : acc) rest

-- | What comes before an item in 'normalize'.
data Before
  = -- | the start of the paragraph, or an item that is neither a box nor an [aki]
    AtStart
  | -- | a note mark at the start of the paragraph (golem-driver ADR 0018)
    AfterStartMark
  | -- | the glue of an [aki] (docs/adr ADR 0019)
    AfterAki
  | AfterBox !BoxContent

{- | Inserts break opportunities and spacing between neighbouring boxes:
no break where a prohibition applies (golem-layout ADR 0002), and the
spacing of the aki set of the paragraph (docs/adr ADR 0019). The spaces
of the line start and the line end are the edges of the boxes. An [aki]
is the space between its neighbours: the set adds none there.
-}
normalize :: ComposeEnv -> [Item] -> [Item]
normalize env = go AtStart True
  where
    set = ceAkiSet env
    go _ _ [] = []
    go before first (x : rest) = case x of
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
              AfterBox p | lkCode (bcLook p) && lkCode (bcLook c) -> [Penalty 0 0 NoHyphen | "/" `T.isSuffixOf` bcText p]
              AfterBox p -> between p c
              AtStart -> leading c
              -- the space of the paragraph start, after the mark: no break there
              AfterStartMark -> case leading c of
                [] -> []
                l -> Penalty 0 infPenalty NoHyphen : l
              AfterAki -> []
         in spacing <> [Box w (withEdges first c)] <> go (AfterBox c) False rest
      -- the glue of an [aki], after its penalty
      Glue _ 0 0 -> x : go AfterAki first rest
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
    -- the classes come from the base characters, without variation selectors (golem-pdf ADR 0006)
    baseText = withoutSelectors . bcText
    firstClass c = case T.uncons (baseText c) of
      Just (ch, _) | not (isRuby c) -> Just (charClass ch)
      _ -> Nothing
    lastClass c = case T.unsnoc (baseText c) of
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
      Sidenote sp _ _ -> [diagnostic "G0732" Error sp msg]
      Kenten _ _ xs -> concatMap go xs
      Color _ _ xs -> concatMap go xs
      CharStyle _ _ xs -> concatMap go xs
      Note _ _ xs -> concatMap go xs
      _ -> []
