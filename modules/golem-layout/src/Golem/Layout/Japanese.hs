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
    composeInlines,
    lineStartProhibited,
    lineEndProhibited,
    protrusionRatio,
    verticalSidenotes,
    punctSpace,
  )
where

import Data.Char (isAscii, isSpace)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Doc.Numerals (kanji, kanjiDigits)
import Golem.Layout.Hyphenation
import Golem.Layout.KnuthPlass
import Golem.Layout.Look
import Golem.Layout.Ruby
import Golem.Syntax (Diagnostic, Severity (..), SrcSpan, diagnostic)

-- | JLReq character classes used by the rules (cl-01 … cl-27).
data CharClass
  = Opening -- cl-01
  | Closing -- cl-02
  | Hyphen -- cl-03
  | Dividing -- cl-04
  | MiddleDot -- cl-05
  | FullStop -- cl-06
  | Comma -- cl-07
  | Inseparable -- cl-08
  | Iteration -- cl-09
  | ProlongedSound -- cl-10
  | SmallKana -- cl-11
  | IdeographicSpace -- cl-14
  | Kana -- cl-15, cl-16
  | Ideograph -- cl-19 and other full-width characters
  | Western -- cl-27
  deriving stock (Eq, Show)

charClass :: Char -> CharClass
charClass c
  | c `elem` ("「『（［｛〈《【〔〘〖〝‘“｟«" :: String) = Opening
  | c `elem` ("」』）］｝〉》】〕〙〗〟’”｠»" :: String) = Closing
  | c `elem` ("‐‑〜゠–" :: String) = Hyphen
  | c `elem` ("？！‼⁇⁈⁉" :: String) = Dividing
  | c `elem` ("・：；" :: String) = MiddleDot
  | c `elem` ("。．" :: String) = FullStop
  | c `elem` ("、，" :: String) = Comma
  | c `elem` ("—…‥〳〴〵" :: String) = Inseparable
  | c `elem` ("ヽヾゝゞ々〻" :: String) = Iteration
  | c == 'ー' = ProlongedSound
  | c `elem` ("ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ" :: String) = SmallKana
  | c == '\x3000' = IdeographicSpace
  | (c >= '\x3041' && c <= '\x309F') || (c >= '\x30A0' && c <= '\x30FF') = Kana
  | isAscii c || (c >= '\x00A0' && c <= '\x024F') || (c >= '\x0370' && c <= '\x04FF') = Western
  | otherwise = Ideograph

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
    -} ceExplicitHyphenPenalty :: !Int
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
      ceExplicitHyphenPenalty = 50
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
  = AnchorNote !Int !Int [Inline] -- item index, note number, body
  | AnchorSidenote !Int !Int !SrcSpan [Inline] -- item index, sidenote number, span, body
  | AnchorPageRef !Int !Text
  | AnchorIndex !Int !SrcSpan IndexEntry -- item index, the mark, the entry
  deriving stock (Eq, Show)

{- | What a box shows (kept in 'bcTag').
'KindRuby' is a mono ruby, 'KindGroupRuby' a group ruby (golem-layout ADR 0009).
-}
data BoxKind = KindText | KindRuby | KindTcy | KindRotated | KindKenten | KindPunctuation | KindGroupRuby
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
      normalized = normalize env items
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
  Note _ n body -> [PAnchor (\i -> AnchorNote i n body), PBox lk ("*" <> T.pack (show n)) KindText (lkSize lk `div` 2)]
  Sidenote sp n body ->
    PAnchor (\i -> AnchorSidenote i n sp body) : case ceSidenoteMarker env of
      MarkerNumber -> [PBox lk (T.pack (show n)) KindText (lkSize lk `div` 2)]
      MarkerSymbol -> [PBox lk "※" KindText (lkSize lk)]
      MarkerNone -> []
  IndexMark sp e -> [PAnchor (\i -> AnchorIndex i sp e)]
  Cite _ k -> textPieces lk False ("[" <> maybe k (T.pack . show) (ceCiteNumber env k) <> "]")
  ProofComment {} -> []
  -- the lines of a keep style are split before they are composed (docs/adr
  -- ADR 0005); what reaches here is a hard break (docs/adr ADR 0016)
  LineBreak {} -> [PForcedBreak]
  where
    lk = ceLook env
    -- the look inside: the inner setting wins, the rest is inherited (golem-driver ADR 0004)
    restyled = concatMap (piecesOf env {ceLook = ceRestyle env lk inl} kenten)

textPieces :: Look -> Bool -> Text -> [Piece]
textPieces lk kenten t = reverse (foldl' attach [] (go (zip cs latinish)))
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
        tag
          | kenten = KindKenten
          | ceVertical env && cls == Western = KindRotated
          | pre + post > 0 = KindPunctuation
          | otherwise = KindText
        hang = if ceHanging env && cls `elem` [FullStop, Comma] then w else 0
     in [Box w (BoxContent (T.cons c vs) False 0 hang (fromEnum tag) lk 0 0)]
  PWord lk word -> wordItems env lk word
  PSpace lk ->
    let sw = advance env lk ' '
     in [Glue sw (sw `div` 2) (sw `div` 3)]
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
  PAnchor _ -> []

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
      box t =
        let w = round (ceWordAdvance env lk t * toRational (lkSize lk))
            (ps, _) = maybe (0, 0) (protrusionRatio . fst) (T.uncons t)
            (_, pe) = maybe (0, 0) (protrusionRatio . snd) (T.unsnoc t)
            prot r = if ceProtrusion env then min w (w * r `div` 1000) else 0
         in Box w (BoxContent t True (prot' ps t prot) (prot' pe t prot) tag lk 0 0)
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

{- | Inserts break opportunities and spacing between neighbouring items
following JLReq: no break where a prohibition applies, punctuation
spaces combined, quarter-em spaces between Japanese and Latin text.
-}
normalize :: ComposeEnv -> [Item] -> [Item]
normalize env = go Nothing
  where
    fs = ceFontSize env
    em r = round (r * toRational fs)
    go _ [] = []
    go prev (x : rest) = case (prev, x) of
      (Just p, Box _ c) -> between p c <> [x] <> go (Just c) rest
      (_, Box _ c) -> leading c <> [x] <> go (Just c) rest
      _ -> x : go Nothing rest
    -- punctuation spaces are in the size of their own box (golem-driver ADR 0004)
    sizeOf c = toRational (lkSize (bcLook c))
    leading c = case textClass c of
      Just cls | fst (punctSpace cls) > 0 -> let w = round (fst (punctSpace cls) * sizeOf c) in [Glue w 0 w]
      _ -> []
    trailingSpace c = maybe 0 (snd . punctSpace) (textClass c) * sizeOf c
    leadingSpace c = maybe 0 (fst . punctSpace) (textClass c) * sizeOf c
    -- the classes come from the base characters, without variation selectors (golem-pdf ADR 0006)
    baseText = withoutSelectors . bcText
    textClass c = case T.unsnoc (baseText c) of
      Just (_, ch) | boxKind c `elem` [KindText, KindPunctuation, KindKenten] && T.length (baseText c) == 1 -> Just (charClass ch)
      _ -> Nothing
    firstClass c = case T.uncons (baseText c) of
      Just (ch, _) | not (isRuby c) -> Just (charClass ch)
      _ -> Nothing
    lastClass c = case T.unsnoc (baseText c) of
      Just (_, ch) | not (isRuby c) -> Just (charClass ch)
      _ -> Nothing
    isRuby c = boxKind c `elem` [KindRuby, KindGroupRuby]
    between p c =
      let pc = lastClass p
          cc = firstClass c
          strict = ceKinsokuStrict env
          noBreak =
            maybe False (lineStartProhibited strict) cc
              || maybe False lineEndProhibited pc
              || (pc == Just Inseparable && cc == Just Inseparable)
              || (pc == Just Western && cc == Just Western && bcExpandable p && bcExpandable c)
          space = combined (trailingSpace p) (leadingSpace c) pc cc
          isJa k = (k /= Just Western)
          waou = (pc == Just Western && isJa cc && isJust cc && space == 0 && notPunct cc) || (cc == Just Western && isJa pc && isJust pc && space == 0 && notPunct pc)
          notPunct = maybe True (\cl -> punctSpace cl == (0, 0))
          pen = ([Penalty 0 infPenalty NoHyphen | noBreak])
       in if space > 0
            then pen <> [Glue (round space) 0 (round space)]
            else
              if waou
                then pen <> [Glue (em (1 / 4)) (em (1 / 4)) (em (1 / 8))]
                else
                  if noBreak
                    then []
                    else
                      if bothJapanese pc cc
                        then [Glue 0 (fs `div` 10) 0] -- inter-character: adjusted last
                        else [Penalty 0 0 NoHyphen | interBox p c]
    bothJapanese pc cc = maybe False (/= Western) pc && maybe False (/= Western) cc
    interBox p c = not (bcExpandable p && bcExpandable c)
    -- JLReq: closing followed by opening keeps a half em; other adjacent
    -- punctuation spaces collapse; middle dots keep their quarters. In sp,
    -- unrounded: each space is in the size of its own box.
    combined post pre pc cc
      | post == 0 = pre
      | pre == 0 = if cc `elem` map Just [Closing, FullStop, Comma] then 0 else post
      | pc `elem` map Just [Closing, FullStop, Comma] && cc == Just Opening = max post pre
      | pc == Just MiddleDot || cc == Just MiddleDot = post + pre
      | otherwise = 0

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
