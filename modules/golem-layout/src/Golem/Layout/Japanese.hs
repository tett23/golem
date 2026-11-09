{- | Japanese composition (golem-layout ADR 0002): JLReq character classes,
line-start and line-end prohibitions, punctuation spacing, spacing
between Japanese and Latin text, ruby, kenten and tate-chu-yoko, turned
into Knuth–Plass items. Glyph advances come from a metrics function
(shaping is golem-font's job).
-}
module Golem.Layout.Japanese
  ( CharClass (..),
    charClass,
    lookClass,
    isVariationSelector,
    isExtending,
    clusters,
    ComposeEnv (..),
    SidenoteMarker (..),
    defaultComposeEnv,
    Anchor (..),
    BoxKind (..),
    boxKind,
    joinedDashes,
    noteMarkSize,
    wrapMarkScale,
    wrapMarkSize,
    shapedWrapMark,
    MarkPart (..),
    markParts,
    markInlines,
    markPartsText,
    -- | the format of [notes] mark-format, for the users of 'ComposeEnv' (docs/adr/0177)
    MarkFormat (..),
    parseMarkFormat,
    composeInlines,
    composeInlinesTree,
    softHyphenSites,
    SoftHyphenNote (..),
    trailingSpaces,
    inlineStructure,
    InlineNode (..),
    InlineRole (..),
    lineStartProhibited,
    lineEndProhibited,
    protrusionRatio,
    verticalSidenotes,
    punctSpace,
  )
where

import Data.Char (GeneralCategory (..), generalCategory, isDigit, isLetter, isSpace)
import Data.IntMap.Strict qualified as IntMap
import Data.IntSet qualified as IntSet
import Data.List (groupBy, mapAccumL, sort, zip4, zip5)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Unsafe (lengthWord8)
import Golem.Doc.IR
import Golem.Layout.Aki (AkiPos (..), AkiSet, akiBetween, defaultAkiSet, noAki)
import Golem.Layout.Aki qualified as A
import Golem.Layout.CharClass
import Golem.Layout.Hyphenation
import Golem.Layout.KnuthPlass
import Golem.Layout.Look
import Golem.Layout.Ruby
import Golem.Length qualified as L
import Golem.Numerals (kanji, kanjiDigits)
import Golem.Numerals.Format (MarkFormat (..), defaultMarkFormat, parseMarkFormat)
import Golem.Numerals.Notation (Notation, arabic, writeNumber)
import Golem.Project.Style (Dim (..), dimToSp)
import Golem.Syntax (Diagnostic, Severity (..), SrcSpan (..), diagnostic, mkSpan, spanLength)

{- | The class of a character in a look: of the language of its span
(docs/adr ADR 0187), 'charClass' outside one.
-}
lookClass :: Look -> Char -> CharClass
lookClass = charClassIn . lkLang

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
    {- | advance of one character of a Latin word in the font the word is
    set in, alone (no tracking, no kerning), in em: the base of its
    protrusion (docs/adr/0222)
    -} ceWordCharAdvance :: Look -> Text -> Char -> Rational,
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
    -- | the notation of a page reference in vertical text; Nothing sets the digits sideways (docs/adr/0118)
    ceRefPageNumbers :: !(Maybe VerticalNumbers),
    {- | the patterns of the Latin words of a language span, from its
    language; Nothing is outside a span (docs/adr ADR 0187)
    -} cePatterns :: Maybe Text -> Maybe Patterns,
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
    -- | [notes] mark-format: the text of a note mark, its number in a notation (golem-driver ADR 0025, docs/adr/0177)
    ceNoteMarkFormat :: !MarkFormat,
    -- | the look of a mark in the text from the look of its place: [notes] mark-style applied (docs/adr/0177)
    ceNoteMarkLook :: Look -> Look,
    -- | the size source of a mark in the text from that of its place (golem-cli ADR 0008, docs/adr/0177)
    ceNoteMarkSource :: SizeSource -> SizeSource,
    -- | the definition that decided the size of 'ceLook' (golem-cli ADR 0008)
    ceSizeSource :: !SizeSource,
    -- | the size source inside an inline element, as 'ceRestyle' is the look inside it
    ceSizeSourceOf :: SizeSource -> Inline -> SizeSource,
    -- | the source of the boxes of the piece 'itemsFor' makes; set by 'composeInlines'
    ceBoxSource :: !BoxSource,
    {- | where a character of a text is in the source (docs/adr ADR 0195):
    the span and the text of a 'Text' inline and the index of a character
    in the text give a byte offset in the file of the span, or -1 when the
    source does not have the character. The text may not be the source
    as it is (newlines dropped, escapes, values); the default is the
    start of the span. Applied to a span and a text once per inline, so
    that the work can be shared.
    -} ceSourceAt :: SrcSpan -> Text -> Int -> Int,
    -- | where the character at an index of the piece 'itemsFor' makes is in the source; set by 'composeInlines'
    ceBoxAt :: Int -> Int,
    -- | the place of the composition in the structure tree of the PDF (docs/adr ADR 0183); empty for none
    ceSite :: ![Int],
    -- | the leaf of the boxes of the piece 'itemsFor' makes; set by 'composeInlines'
    ceLeaf :: !Int,
    -- | how many inlines at the start are a label, such as the mark of a note (docs/adr ADR 0183)
    ceLabelInlines :: !Int
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
      ceWordCharAdvance = \_ _ -> defaultAdvance,
      ceKern = \_ _ _ -> 0,
      ceVertical = False,
      ceKinsokuStrict = True,
      ceHanging = False,
      ceProtrusion = False,
      ceRuby = defaultRubyStyle fs,
      ceVerticalNumbers = VerticalFixed StyleKanji,
      ceRefPageNumbers = Just (VerticalFixed StyleKanji),
      cePatterns = const Nothing,
      cePageOf = const Nothing,
      ceLook = plainLook "body" fs,
      ceRestyle = const,
      ceSidenoteMarker = MarkerNumber,
      ceCiteNumber = \_ _ -> Nothing,
      ceExplicitHyphenPenalty = 50,
      ceAkiSet = defaultAkiSet,
      ceNoteMarkFormat = defaultMarkFormat,
      ceNoteMarkLook = \lk -> lk {lkSize = noteMarkSize (Zw (1 % 2)) (lkSize lk)},
      ceNoteMarkSource = const SourceNoteMark,
      ceSizeSource = SourceGrid,
      ceSizeSourceOf = const,
      ceBoxSource = noBoxSource,
      ceSourceAt = \sp _ _ -> spanStart sp,
      ceBoxAt = const 0,
      ceSite = [],
      ceLeaf = 0,
      ceLabelInlines = 0
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
'KindNoteMark' the mark of a note (golem-driver ADR 0018) and 'KindDashes'
a run of full-width dashes (docs/adr ADR 0172); they come last so that
the values before them keep their 'fromEnum'.
-}
data BoxKind = KindText | KindRuby | KindTcy | KindRotated | KindKenten | KindPunctuation | KindGroupRuby | KindAki | KindNoteMark | KindDashes
  deriving stock (Eq, Show, Enum, Bounded)

boxKind :: BoxContent -> BoxKind
boxKind = toEnum . bcTag

-- ------------------------------------------------------------------ pieces

-- One unit of composition before items are generated, with its look.
data Piece
  = PChar !Look !Char !Text -- the character and its variation selectors; kenten is in the look
  | PWord !Look !Text ![Int] -- a Latin word (no spaces), and where the soft hyphens taken out of it were (docs/adr ADR 0272)
  | PSpace !Look -- an inter-word space
  | PBox !Look !Text !BoxKind !Sp -- ruby, tcy, …: an unbreakable box of a given width
  | PRuby !Look !RubyKind !Text ![Look] !(Maybe Text) -- ruby: the base, the look of each base character (golem-layout ADR 0011) and the reading (none for a segment without one)
  | PRubyBreak -- a break allowed between mono ruby bases
  | PForcedBreak -- a hard line break: the line ends as a paragraph does (docs/adr ADR 0016)
  | PAki !Look !AkiAmount -- [aki]: a fixed space, no break around it (docs/adr ADR 0019)
  | PCode !Look !Text !Sp !Sp -- a run of code without spaces and tabs (golem-driver ADR 0017), the padding before and after it (golem-driver ADR 0029)
  | PDashes !Look !Text -- a run of two or more full-width dashes: one box, an em for each (docs/adr ADR 0172)
  | PMark !Look !Look ![MarkPart] !Sp !Sp -- the mark of a note in the text: the look of its place, its own, its parts and the padding of code before and after it (docs/adr/0177)
  | PAnchor (Int -> Anchor)
  | PShy !SoftHyphenNote -- a soft hyphen that is not a break, and why (docs/adr ADR 0272): no items

composeInlines :: ComposeEnv -> [Inline] -> ([Item], [Anchor])
composeInlines env inls = let (items, anchors, _) = composeInlinesTree env inls in (items, anchors)

{- | 'composeInlines' with the structure of the inlines (docs/adr ADR 0183):
the leaves of the boxes, numbered in the order of the inlines, inside the
elements of ruby, references, notes and code.
-}
composeInlinesTree :: ComposeEnv -> [Inline] -> ([Item], [Anchor], [InlineNode])
composeInlinesTree env inls =
  let (nodes, sourced0) = structured env inls
      sourced = [(src, p) | (_, src, p) <- sourced0]
      leaves = [l | (l, _, _) <- sourced0]
      -- padCode keeps one piece for each piece
      pieces = padCode (map snd sourced)
      (items, anchors, codeSpaces) = foldl' emit ([], [], IntSet.empty) (zip5 leaves (map fst sourced) prevs pieces nexts)
      emit (acc, as, cs) (_, _, _, PAnchor f, _) = (acc, (length acc, f) : as, cs)
      -- the boxes of a piece carry its source (golem-cli ADR 0008) and its leaf (docs/adr ADR 0183)
      emit (acc, as, cs) (l, (src, offs), pv, p, nx) =
        let new = itemsFor env {ceBoxSource = src, ceBoxAt = offs, ceLeaf = l} pv p nx
            -- the glue of a space of inline code, by its index (golem-layout ADR 0037)
            cs' = case p of
              PSpace lk | lkCode lk -> IntSet.union cs (IntSet.fromList [length acc + k | (k, Glue {}) <- zip [0 ..] new])
              _ -> cs
         in (acc <> new, as, cs')
      -- the neighbours of each piece, anchors and breaks between mono ruby bases skipped
      solid = \case
        PAnchor _ -> False
        PShy _ -> False
        PRubyBreak -> False
        _ -> True
      prevs = scanl (\acc p -> if solid p then Just p else acc) Nothing pieces
      nexts = drop 1 (scanr (\p acc -> if solid p then Just p else acc) Nothing pieces)
      spaced = normalize env codeSpaces (kernPairs env items)
      -- anchors index the normalized items: the spacing inserted before a box shifts it, a space taken out the items after it
      positions = alignPositions items spaced
      {- the spaces between words (golem-layout ADR 0032) and the spaces of
      inline code (golem-layout ADR 0037) before the end of the paragraph
      and before a forced break go; kernPairs keeps the items one for one -}
      dropped = trailingSpaces (IntSet.fromList [j | (i, j) <- positions, IntSet.member i codeSpaces]) spaced
      normalized = [x | (k, x) <- zip [0 ..] spaced, not (IntSet.member k dropped)]
      at0 i = let j = fromMaybe (length spaced) (lookup i positions) in j - IntSet.size (fst (IntSet.split j dropped))
      -- the ranges that do not break (docs/adr ADR 0272): a penalty goes before each space they hold
      (kept, held) = keepRanges normalized
      at i = let j = at0 i in j + IntSet.size (fst (IntSet.split j held))
   in (finish kept, [f (at i) | (i, f) <- reverse anchors], nodes)
  where
    finish its = its <> lineEnd

-- | The structure of the inlines of 'composeInlinesTree', without composing them.
inlineStructure :: ComposeEnv -> [Inline] -> [InlineNode]
inlineStructure env = fst . structured env

{- | The soft hyphens of inlines that are not breaks (docs/adr ADR 0272),
those in the bodies of their notes and sidenotes among them, in the order
of the inlines: the span of the text each is in, where it is in the
source ('ceSourceAt'; -1 where the source does not have it), and why.
-}
softHyphenSites :: ComposeEnv -> [Inline] -> [(SrcSpan, Int, SoftHyphenNote)]
softHyphenSites env inls =
  let (nodes, sourced) = structured env inls
      here = [(snd src, offs 0, note) | (_, (src, offs), PShy note) <- sourced]
   in here <> concatMap (softHyphenSites env) (concatMap bodies nodes)
  where
    bodies = \case
      NodeNote _ _ _ b -> [b]
      NodeSidenote _ _ b -> [b]
      NodeElem _ ns -> concatMap bodies ns
      NodeLink _ _ ns -> concatMap bodies ns
      NodeLeaf _ -> []

{- | The structure of composed inlines (docs/adr ADR 0183): leaves of
content, and the elements Golem makes from the inlines.
-}
data InlineNode
  = NodeLeaf !Int
  | NodeElem !InlineRole ![InlineNode]
  | {- | the body of a note marked here: its span, its place among the notes
    of that span ('noteAnchors' of golem-driver), its number and its body
    -}
    NodeNote !SrcSpan !Int !Int [Inline]
  | -- | the body of a sidenote marked here: its span, its number and its body
    NodeSidenote !SrcSpan !Int [Inline]
  | -- | a link (docs/adr ADR 0182): its URL, its inlines and what it holds
    NodeLink !Text [Inline] [InlineNode]
  deriving stock (Eq, Show)

-- | The elements of inlines: the label of 'ceLabelInlines', ruby, its base and reading, a reference, code and a language span (docs/adr ADR 0187).
data InlineRole = RoleLabel | RoleRuby | RoleRubyBase | RoleRubyText | RoleReference | RoleCode | RoleLang !Text
  deriving stock (Eq, Show)

-- the state of 'structured': the next leaf, the leaf of the content, the notes seen by their span
data LeafState = LeafState !Int !Int !(Map.Map SrcSpan Int)

{- | The pieces of inlines with their leaves and sources, and the structure
of the inlines. Leaf 0 is the content at the start; each element takes
new leaves, and the content after it a new one.
-}
structured :: ComposeEnv -> [Inline] -> ([InlineNode], [(Int, Sourced, Piece)])
structured env inls =
  let (labelled, rest) = splitAt (ceLabelInlines env) inls
      st0 = LeafState 1 0 Map.empty
   in if null labelled
        then let (_, ns, ps) = walkAll env st0 rest in (NodeLeaf 0 : ns, ps)
        else
          let (st1, ns1, ps1) = walkAll env st0 labelled
              (st2, after) = freshLeaf st1
              (_, ns2, ps2) = walkAll env st2 rest
           in (NodeElem RoleLabel (NodeLeaf 0 : ns1) : after : ns2, ps1 <> ps2)

walkAll :: ComposeEnv -> LeafState -> [Inline] -> (LeafState, [InlineNode], [(Int, Sourced, Piece)])
walkAll env st0 = foldl' step (st0, [], [])
  where
    step (st, ns, ps) inl = let (st', ns', ps') = walk env st inl in (st', ns <> ns', ps <> ps')

-- a new leaf for the content after an element
freshLeaf :: LeafState -> (LeafState, InlineNode)
freshLeaf (LeafState next _ seen) = (LeafState (next + 1) next seen, NodeLeaf next)

-- | The pieces and the structure of one inline.
walk :: ComposeEnv -> LeafState -> Inline -> (LeafState, [InlineNode], [(Int, Sourced, Piece)])
walk env st@(LeafState next cur seen) inl = case inl of
  Color _ _ xs -> walkAll restyledEnv st xs
  CharStyle _ _ xs
    -- code inside text that is not code is an element (docs/adr ADR 0183)
    | lkCode (ceLook restyledEnv) && not (lkCode lk) -> element RoleCode (\st' -> walkAll restyledEnv st' xs)
    | otherwise -> walkAll restyledEnv st xs
  Kenten _ sh xs -> walkAll env {ceLook = lk {lkKenten = Just (fromMaybe KentenSesame (sh >>= kentenShapeFromName))}} st xs
  -- a language span is an element of its language (docs/adr ADR 0187)
  Lang _ l xs -> element (RoleLang l) (\st' -> walkAll env {ceLook = lk {lkLang = Just l}} st' xs)
  Ruby _ _ segs -> rubySegments segs
  Note sp num body ->
    let k = Map.findWithDefault 0 sp seen
        (anchor, mark) = splitAt 1 (piecesOf env inl)
        st1 = LeafState (next + 1) cur (Map.insert sp (k + 1) seen)
        (st2, after) = freshLeaf st1
     in (st2, [NodeElem RoleReference [NodeLeaf next], NodeNote sp k num (inLangOf lk sp body), after], [(cur, src, p) | (src, p) <- anchor] <> [(next, src, p) | (src, p) <- mark])
  Sidenote sp n body ->
    let (anchor, mark) = splitAt 1 (piecesOf env inl)
        st1 = LeafState (next + 1) cur seen
        (st2, after) = freshLeaf st1
        ref = [NodeElem RoleReference [NodeLeaf next] | not (null mark)]
     in (st2, ref <> [NodeSidenote sp n (inLangOf lk sp body), after], [(cur, src, p) | (src, p) <- anchor] <> [(next, src, p) | (src, p) <- mark])
  -- a link is an element; its look is that of the link (docs/adr ADR 0182)
  Link _ u xs ->
    let (st1, ns, ps) = walkAll restyledEnv (LeafState (next + 1) next seen) xs
        LeafState next1 _ seen1 = st1
        (st2, after) = freshLeaf (LeafState next1 cur seen1)
     in (st2, [NodeLink u xs (NodeLeaf next : ns), after], ps)
  Ref {} -> element RoleReference (\st' -> (st', [], [(leafOf st', src, p) | (src, p) <- piecesOf env inl]))
  -- [ref-number] and [ref-title] resolved: a reference, with what it holds inside (docs/adr/0215)
  Resolved _ _ _ xs -> element RoleReference (\st' -> walkAll env st' xs)
  Cite {} -> element RoleReference (\st' -> (st', [], [(leafOf st', src, p) | (src, p) <- piecesOf env inl]))
  _ -> (st, [], [(cur, src, p) | (src, p) <- piecesOf env inl])
  where
    lk = ceLook env
    restyledEnv = env {ceLook = ceRestyle env lk inl, ceSizeSource = ceSizeSourceOf env (ceSizeSource env) inl}
    leafOf (LeafState _ c _) = c
    -- an element: its first leaf for what it holds, then a new leaf for what follows
    element role inner =
      let (st1, ns, ps) = inner (LeafState (next + 1) next seen)
          LeafState next1 _ seen1 = st1
          (st2, after) = freshLeaf (LeafState next1 cur seen1)
       in (st2, [NodeElem role (NodeLeaf next : ns), after], ps)
    {- each segment with a reading is a Ruby of its base and reading, the
    reading the leaf after the base; a segment without one is content -}
    rubySegments segs =
      let go (s, ns, ps) (seg, segPieces) = case rsReading seg of
            Just _ ->
              let LeafState n c sn = s
                  (s', after) = freshLeaf (LeafState (n + 2) c sn)
               in (s', ns <> [NodeElem RoleRuby [NodeElem RoleRubyBase [NodeLeaf n], NodeElem RoleRubyText [NodeLeaf (n + 1)]], after], ps <> [(n, src, p) | (src, p) <- segPieces])
            Nothing -> let LeafState _ c _ = s in (s, ns, ps <> [(c, src, p) | (src, p) <- segPieces])
       in foldl' go (st, [], []) (zip segs (chunks (piecesOf env inl)))
    -- the pieces of each segment: each ends with its PRuby, the break before it included
    chunks ps = case break isRuby ps of
      (pre, r : rest) -> (pre <> [r]) : chunks rest
      ([], []) -> []
      (pre, []) -> [pre]
    isRuby (_, p) = case p of
      PRuby {} -> True
      _ -> False

-- | The end of a paragraph, and of a line broken by a hard break: the rest of the line is fill.
lineEnd :: [Item]
lineEnd = [Penalty 0 infPenalty NoHyphen, Glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]

{- | The ranges of text that do not break (docs/adr ADR 0272): a break
whose nearest character before it and nearest character after it are
both of such a range is not taken. A penalty of it becomes one of 10000,
as wide as it was; a penalty of 10000 goes before a glue of it. Forced
breaks stay, and nothing else changes: the boxes, the glue, the widths,
the spacing, the prohibitions. The items, and the indices of the glue a
penalty went before.
-}
keepRanges :: [Item] -> ([Item], IntSet.IntSet)
keepRanges its
  | not (or [lkNoBreak (bcLook c) | Box _ c <- its]) = (its, IntSet.empty)
  | otherwise = (concat (zipWith3 keep afterBox its around), IntSet.fromList [k | (k, b, x, ar) <- zip4 [0 ..] afterBox its around, heldGlue b x ar])
  where
    -- whether the nearest character before (after) an item is of a range; Nothing for no character
    nearest = \case
      Box _ c | not (T.null (bcText c)) -> Just (lkNoBreak (bcLook c))
      _ -> Nothing
    befores = scanl (\acc x -> maybe acc Just (nearest x)) Nothing its
    afters = drop 1 (scanr (\x acc -> maybe acc Just (nearest x)) Nothing its)
    around = zip befores afters
    -- whether the item before is a box: a glue there is a break
    afterBox = False : map isBox its
    isBox = \case
      Box {} -> True
      _ -> False
    inside (b, a) = b == Just True && a == Just True
    heldGlue b x ar = case x of
      Glue {} -> b && inside ar
      _ -> False
    keep b x ar = case x of
      Penalty w p h | p < infPenalty && p > negate infPenalty && inside ar -> [Penalty w infPenalty h]
      Glue {} | heldGlue b x ar -> [Penalty 0 infPenalty NoHyphen, x]
      _ -> [x]

{- | The items of the spaces between words before the end of a paragraph
and before each forced break (golem-layout ADR 0032), and of the spaces of
inline code there (golem-layout ADR 0037), by their indices: where no box
comes between a space and the end, the glue of each space between words
there, the glue of each space of code, which the indices given are of, and
the penalties of 10000 kinsoku put before them (golem-layout ADR 0028).
Glue that is not of a space stays, even if it neither stretches nor
shrinks; so does all else.
-}
trailingSpaces :: IntSet.IntSet -> [Item] -> IntSet.IntSet
trailingSpaces codeSpaces its = IntSet.fromList (concatMap before ends)
  where
    indexed = zip [0 :: Int ..] its
    ends = [k | (k, _) <- indexed, isLineEnd (drop k its)] <> [length its]
    -- the items back from an end to the box or the line end before it
    before e =
      let run = takeWhile (not . stops . snd) (reverse (take e indexed))
          isSpace' k x = isWordSpace x || (IntSet.member k codeSpaces && isGlue x)
       in if any (uncurry isSpace') run then [k | (k, x) <- run, isSpace' k x || isKept x] else []
    isGlue = \case
      Glue {} -> True
      _ -> False
    stops = \case
      Box {} -> True
      Penalty _ p _ -> p <= negate infPenalty
      _ -> False
    isKept = \case
      Penalty _ p NoHyphen -> p >= infPenalty
      _ -> False
    isLineEnd = \case
      Penalty _ p NoHyphen : Glue 0 y 0 : Penalty _ q NoHyphen : _ -> p >= infPenalty && y == filStretch && q <= negate infPenalty
      _ -> False
    isWordSpace = \case
      Glue _ y _ -> y > 0 && y < filStretch
      _ -> False

{- | Where each item ends up after 'normalize', which only inserts items
before boxes and spaces and takes out the breaks after written hyphens
that a prohibition applies across (golem-layout ADR 0028): a box is the
next box of the normalized items, a break taken out the place of the
next item, anything else is the next item.
-}
alignPositions :: [Item] -> [Item] -> [(Int, Int)]
alignPositions = go 0 0
  where
    go _ _ [] _ = []
    go i j (x : xs) ys = case x of
      Box {} -> case break isBox ys of
        (skipped, _ : rest) -> let j' = j + length skipped in (i, j') : go (i + 1) (j' + 1) xs rest
        (_, []) -> []
      Penalty _ _ ExplicitHyphen | not (isExplicit ys) -> (i, j) : go (i + 1) j xs ys
      Glue {} | Penalty _ p NoHyphen : y : rest <- ys, p >= infPenalty, y == x -> (i, j + 1) : go (i + 1) (j + 2) xs rest
      _ -> case ys of
        (_ : rest) -> (i, j) : go (i + 1) (j + 1) xs rest
        [] -> []
    isBox = \case
      Box {} -> True
      _ -> False
    isExplicit = \case
      Penalty _ _ ExplicitHyphen : _ -> True
      _ -> False

{- | The source of a piece (golem-cli ADR 0008), and where each of its
characters is in the source (docs/adr ADR 0195): the start of the span
for a piece that is not of a text.
-}
type Sourced = (BoxSource, Int -> Int)

{- | The pieces of an inline, each with its source (golem-cli ADR 0008): the
size source of the look it is set in and the span of the inline it
comes from.
-}
piecesOf :: ComposeEnv -> Inline -> [(Sourced, Piece)]
piecesOf env inl = case inl of
  Text sp t ->
    let offs = ceSourceAt env sp t
     in [(((ceSizeSource env, pieceSpan sp t (at' 0) p), offs . at'), p) | (at', p) <- textPiecesAt lk t]
  Color _ _ xs -> restyled xs
  CharStyle _ _ xs -> restyled xs
  -- the target of a link is a look of the characters inside (docs/adr ADR 0182)
  Link _ _ xs -> restyled xs
  -- the language likewise; the inner span wins (docs/adr ADR 0187)
  Lang _ l xs -> concatMap (piecesOf env {ceLook = lk {lkLang = Just l}}) xs
  -- a resolved reference is set as what it holds (docs/adr/0215)
  Resolved _ _ _ xs -> concatMap (piecesOf env) xs
  -- the shape is a look of the characters inside; the inner kenten wins (golem-driver ADR 0019)
  Kenten _ sh xs -> concatMap (piecesOf env {ceLook = lk {lkKenten = Just (fromMaybe KentenSesame (sh >>= kentenShapeFromName))}}) xs
  Ruby sp _ segs -> at sp (rubyPieces env segs)
  Tcy sp t -> at sp [PBox lk t KindTcy (lkSize lk)]
  Number sp n style -> at sp (numberPieces env n style)
  Ref sp RefPage l ->
    let n = fromMaybe 1 (cePageOf env l)
        -- a number as any other, in the notation of [numbers] ref-page (docs/adr/0118)
        digits = case ceRefPageNumbers env of
          Just v | ceVertical env -> numberPieces env {ceVerticalNumbers = v} n Nothing
          _ -> textPieces lk (T.pack (show n))
     in at sp (PAnchor (`AnchorPageRef` l) : digits)
  Ref sp _ l -> at sp (textPieces lk l)
  Deferred {} -> []
  -- a mark is set in the character style of [notes] mark-style (docs/adr/0177)
  Note sp n body ->
    let MarkFormat pre notation suf = ceNoteMarkFormat env
     in [(((ceSizeSource env, sp), const (spanStart sp)), PAnchor (\i -> AnchorNote i n sp (inLangOf lk sp body))), (((markSource, sp), const (spanStart sp)), markPiece (markParts (ceVertical env) pre notation (toInteger n) suf))]
  Sidenote sp n body ->
    (((ceSizeSource env, sp), const (spanStart sp)), PAnchor (\i -> AnchorSidenote i n sp (inLangOf lk sp body))) : case ceSidenoteMarker env of
      -- the number alone, neither the format nor the notation of [notes] (docs/adr/0177)
      MarkerNumber -> [(((markSource, sp), const (spanStart sp)), markPiece (markParts (ceVertical env) "" arabic (toInteger n) ""))]
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
    at sp = map (((ceSizeSource env, sp), const (spanStart sp)),)
    -- the look inside: the inner setting wins, the rest is inherited (golem-driver ADR 0004)
    restyled = concatMap (piecesOf env {ceLook = ceRestyle env lk inl, ceSizeSource = ceSizeSourceOf env (ceSizeSource env) inl})
    -- the mark of a note or a numbered sidenote (golem-driver ADR 0018) in the look of mark-style (docs/adr/0177)
    markPiece parts = PMark lk (ceNoteMarkLook env lk) parts 0 0
    markSource = ceNoteMarkSource env (ceSizeSource env)

{- | The body of a note or a sidenote in the language of the place of its
mark, if that has one (docs/adr ADR 0187).
-}
inLangOf :: Look -> SrcSpan -> [Inline] -> [Inline]
inLangOf lk sp body = maybe body (\l -> [Lang sp l body]) (lkLang lk)

{- | The size of a note mark in text of a size (golem-driver ADR 0018,
0025): the mark size of style.toml, at least 1sp and at most the size of
the text.
-}
noteMarkSize :: Dim -> Sp -> Sp
noteMarkSize d s = max 1 (min s (dimToSp s d))

-- | A part of a mark (docs/adr/0177): text set as other text, or a number set tate-chu-yoko.
data MarkPart = MarkText !Text | MarkTcy !Text
  deriving stock (Eq, Show)

{- | The parts of a mark of a number (docs/adr/0177): the text before, the
number in its notation and the text after. In vertical text an Arabic
number of up to two digits is tate-chu-yoko, as the number of a marker
of a list (golem-driver ADR 0013); longer ones are Latin text. A number
the notation cannot write (G07029, G07102) is in Arabic numerals.
-}
markParts :: Bool -> Text -> Notation -> Integer -> Text -> [MarkPart]
markParts vertical pre notation n suf =
  let written = fromMaybe (T.pack (show n)) (writeNumber notation n)
      number
        | vertical, notation == arabic, n >= 0, T.length written <= 2 = MarkTcy written
        | otherwise = MarkText written
   in case number of
        -- text around text is one text, as the format writes it
        MarkText t -> [MarkText (pre <> t <> suf)]
        _ -> [MarkText pre | not (T.null pre)] <> [number] <> [MarkText suf | not (T.null suf)]

-- | The parts of a mark as inlines: text, and tate-chu-yoko (docs/adr/0177).
markInlines :: SrcSpan -> [MarkPart] -> [Inline]
markInlines sp = map $ \case
  MarkText t -> Text sp t
  MarkTcy t -> Tcy sp t

-- | The text of the parts of a mark.
markPartsText :: [MarkPart] -> Text
markPartsText = T.concat . map (\case MarkText t -> t; MarkTcy t -> t)

{- | The source of a piece of a text at a character of it: the run of
dashes itself when the text is its source byte for byte (G07101, docs/adr
ADR 0172), the text otherwise.
-}
pieceSpan :: SrcSpan -> Text -> Int -> Piece -> SrcSpan
pieceSpan sp t i = \case
  PDashes _ d
    | spanLength sp == lengthWord8 t ->
        let s = spanStart sp + lengthWord8 (T.take i t)
         in mkSpan (spanFile sp) s (s + lengthWord8 d)
  _ -> sp

{- | The characters a run of which in Japanese text is one box, an em for
each, drawn as one line (docs/adr ADR 0172): the full-width dashes. The
one list of them; more characters are added here.
-}
joinedDashes :: [Char]
joinedDashes = "\x2014\x2015"

textPieces :: Look -> Text -> [Piece]
textPieces lk = map snd . textPiecesAt lk

-- | The soft hyphen, U+00AD (docs/adr ADR 0272).
softHyphen :: Char
softHyphen = '\xAD'

{- | What a soft hyphen that is not a break is reported as (docs/adr ADR
0272): one without a letter of its element on either side (G07123), or
one in text that does not break, code, a URL, a link or a range that
does not break (G07124).
-}
data SoftHyphenNote = ShyNotBetweenLetters | ShyInUnbreakable
  deriving stock (Eq, Ord, Show)

{- | The pieces of a text, each with where its characters are in the
text: the index in the text of the character at an index of the piece.
The soft hyphens (U+00AD) are taken out of the text before its pieces
are made (docs/adr ADR 0272), so that the classes, the spacing and the
words are those of the text without them; a word keeps where they were,
and each soft hyphen that will not be a break leaves a piece of no items
that says why ('PShy'), at the end.
-}
textPiecesAt :: Look -> Text -> [(Int -> Int, Piece)]
textPiecesAt lk t
  | not (T.any (== softHyphen) t) = [((i +), p) | (i, p) <- strippedPieces lk [] t]
  | otherwise =
      [((\k -> orig (i + k)), p) | (i, p) <- strippedPieces lk shys stripped]
        <> [(const j, PShy note) | (j, note) <- notes]
  where
    stripped = T.filter (/= softHyphen) t
    indexed = zip [0 :: Int ..] (T.unpack t)
    -- the index in the text of each character left, and of the end
    origs = IntMap.fromList (zip [0 ..] [j | (j, c) <- indexed, c /= softHyphen])
    orig k = IntMap.findWithDefault (T.length t) k origs
    -- each soft hyphen: how many characters are left before it, and its index in the text
    shys = concat (snd (mapAccumL (\n (j, c) -> if c == softHyphen then (n, [(n, j)]) else (n + 1, [])) 0 indexed))
    notes = softHyphenNotes lk shys stripped

{- | Why each soft hyphen given (how many characters of the text without
them are before it, and its index in the text) is not a break, by its
index in the text (docs/adr ADR 0272): none for a break and for one before
the first letter of its element.
-}
softHyphenNotes :: Look -> [(Int, Int)] -> Text -> [(Int, SoftHyphenNote)]
softHyphenNotes lk shys stripped
  | breaksAsCode lk = [(j, ShyInUnbreakable) | (_, j) <- shys]
  | otherwise =
      [ (j, note)
      | (pos, j) <- shys,
        Just note <- [maybe (Just orphan) (\(start, w) -> roleNote (shyRole lk w (pos - start))) (wordAt pos)]
      ]
  where
    words' = [(i, w) | (i, PWord _ w _) <- strippedPieces lk [] stripped]
    -- the word a soft hyphen is in, before its first character or after its last
    wordAt pos = listToMaybe [(i, w) | (i, w) <- words', pos >= i, pos <= i + T.length w]
    orphan = if unbreakable lk then ShyInUnbreakable else ShyNotBetweenLetters
    roleNote = \case
      ShyCut | unbreakable lk -> Just ShyInUnbreakable
      ShyCut -> Nothing
      ShyHead -> Nothing
      ShyStray -> Just orphan

-- | Whether a break between two characters of a look is never taken, but a forced one.
unbreakable :: Look -> Bool
unbreakable lk = breaksAsCode lk || isJust (lkLink lk) || lkNoBreak lk

{- | What a soft hyphen in a Latin word is (docs/adr ADR 0272): a break,
where a letter (general category L, its combining characters with it) of
its element is on either side of it; nothing, before the first letter of
its element; a soft hyphen that is not a break, anywhere else. A soft
hyphen right after a hyphen or dash written in the word is in the element
after it, one after the word in its last element.
-}
data ShyRole = ShyCut | ShyHead | ShyStray
  deriving stock (Eq, Show)

-- | The role of a soft hyphen in a word, by the characters of the word before it.
shyRole :: Look -> Text -> Int -> ShyRole
shyRole lk word pos
  | isJust (lkLink lk) = if head' then ShyHead else ShyStray
  | head' = ShyHead
  | letterBefore && letterAfter = ShyCut
  | otherwise = ShyStray
  where
    (start, _) = elementSpan word pos
    inElement = T.drop start (T.take pos word)
    head' = not (T.any isLetter inElement)
    -- the base of the character before it, past its combining characters
    letterBefore = maybe False isLetter (T.find (not . isExtending) (T.reverse (T.take pos word)))
    letterAfter = case T.uncons (T.drop pos word) of
      Just (c, _) -> isLetter c && not (isExtending c)
      Nothing -> False

{- | The element of a word a position is in (the start and the end of it in
the word): the elements of 'explicitParts', a position at the start of an
element in that element, the end of the word in the last.
-}
elementSpan :: Text -> Int -> (Int, Int)
elementSpan word pos =
  let ls = map T.length (if T.null word then [word] else explicitParts word)
      spans = zip (scanl (+) 0 ls) (drop 1 (scanl (+) 0 ls))
   in case [sp | sp@(a, b) <- spans, pos >= a, pos < b] of
        sp : _ -> sp
        [] -> fromMaybe (0, T.length word) (listToMaybe (reverse spans))

{- | The breaks of soft hyphens in a word (docs/adr ADR 0272): the positions
given that are breaks, each once, in order.
-}
softHyphenCuts :: Look -> Text -> [Int] -> [Int]
softHyphenCuts lk word shys = IntSet.toAscList (IntSet.fromList [p | p <- shys, shyRole lk word p == ShyCut])

-- | The pieces of a text without soft hyphens, each with the index of its first character in it, the soft hyphens given in the words they are in.
strippedPieces :: Look -> [(Int, Int)] -> Text -> [(Int, Piece)]
strippedPieces lk shys t
  | breaksAsCode lk = codePieces lk t
  | otherwise = joinDashes (go (zip3 offsets units latinish))
  where
    {- the units of the text: a base character and the combining characters
    after it, variation selectors among them (golem-pdf ADR 0006,
    golem-driver ADR 0036); the classes come from the base characters -}
    units = [(T.head u, T.tail u) | u <- clusters t]
    offsets = scanl (\n (_, marks) -> n + 1 + T.length marks) 0 units
    cs = map fst units
    -- in a language span, the characters of both scripts are of its language (docs/adr ADR 0187)
    isLatinWordChar c = lookClass lk c == Western && not (isSpace c)
    -- outside a span, quotation marks, apostrophes, hyphens and dashes join a
    -- Latin word when the nearest letter on either side is Latin (I’ll,
    -- “Mercy”—“We”, lime‐tree, 1990–2000; golem-layout ADR 0008)
    isJoiner c = isNothing (lkLang lk) && isJoinerCharacter c
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
    go ((i, (c, marks), l) : rest)
      | c == ' ' = (i, PSpace lk) : go (dropWhile (\(_, (b, _), _) -> b == ' ') rest)
      | l =
          let (w, rest') = span (\(_, _, latin) -> latin) ((i, (c, marks), l) : rest)
              word = T.concat [T.cons b m | (_, (b, m), _) <- w]
              -- the soft hyphens before its first character to after its last (docs/adr ADR 0272)
              inWord = [p - i | (p, _) <- shys, p >= i, p <= i + T.length word]
           in (i, PWord lk word inWord) : go rest'
      | otherwise = (i, PChar lk c marks) : go rest
    -- two or more dashes in a row, without combining characters, are one piece (docs/adr ADR 0172)
    joinDashes = \case
      (i, p) : rest
        | Just c <- dash p,
          (more@(_ : _), rest') <- span (isJust . dash . snd) rest ->
            (i, PDashes lk (T.pack (c : [d | (_, q) <- more, Just d <- [dash q]]))) : joinDashes rest'
      x : rest -> x : joinDashes rest
      [] -> []
    dash = \case
      PChar _ c marks | T.null marks, c `elem` joinedDashes -> Just c
      _ -> Nothing

{- | The text of code (golem-driver ADR 0017): spaces as breaks of a fixed
width (golem-layout ADR 0017), a
tab as other text has it, and each run of the rest as one piece.
-}
codePieces :: Look -> Text -> [(Int, Piece)]
codePieces lk = go 0
  where
    -- each piece with the index of its first character in the text
    go i t = case T.uncons t of
      Nothing -> []
      Just (' ', _) -> let (sps, rest) = T.span (== ' ') t in (i, PSpace lk) : go (i + T.length sps) rest
      Just ('\t', rest) -> (i, PChar lk '\t' "") : go (i + 1) rest
      Just _ ->
        let (run, rest) = T.break (\c -> c == ' ' || c == '\t') t
         in (i, PCode lk run 0 0) : go (i + T.length run) rest

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
  Link _ _ xs -> inner xs
  -- a language span in a base: the look of its characters is of its language (docs/adr ADR 0187)
  Lang _ l xs -> concatMap (baseChars env lk {lkLang = Just l}) xs
  Resolved _ _ _ xs -> concatMap (baseChars env lk) xs
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
  Link s u xs -> Link s u (map withRuby xs)
  Lang s l xs -> Lang s l (map withRuby xs)
  Resolved s k l xs -> Resolved s k l (map withRuby xs)

-- | The advance of a character in a look, in sp.
advance :: ComposeEnv -> Look -> Char -> Sp
advance env lk c = L.zwToSp (lkSize lk) (ceAdvance env lk c)

-- | The tracking of a look in sp: lkTracking thousandths of its size (docs/adr/0020).
tracking :: Look -> Sp
tracking lk = Sp (round (toInteger (lkTracking lk) * unSp (lkSize lk) % 1000))

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
        let k = L.zwToSp (lkSize (bcLook p)) (ceKern env (bcLook p) a b)
         in Box (w + k) p {bcEdgeEnd = bcEdgeEnd p - k} : kernPairs env rest
  x : rest -> x : kernPairs env rest
  [] -> []
  where
    single c = case T.unpack (baseText (bcText c)) of
      [ch]
        | boxKind c `elem` [KindText, KindKenten],
          lookClass (bcLook c) ch `notElem` [Western, Opening, Closing, FullStop, Comma, MiddleDot, Inseparable] ->
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
      _ -> L.zwToSp (lkSize l) (ceWordAdvance env l u)

-- | The advances of the reading characters: half the size of the base, as drawn.
readingAdvances :: ComposeEnv -> Look -> Maybe Text -> [Sp]
readingAdvances env lk = maybe [] (map (advance env lk {lkSize = Sp (unSp (lkSize lk) `div` 2)}) . T.unpack)

itemsFor :: ComposeEnv -> Maybe Piece -> Piece -> Maybe Piece -> [Item]
itemsFor env prev p next = case p of
  PChar lk c vs ->
    let cls = lookClass lk c
        fs = lkSize lk
        (pre, post) = punctSpace cls
        -- with variation selectors: shaped together with them
        full
          | T.null vs = advance env lk c
          | otherwise = L.zwToSp fs (ceWordAdvance env lk (T.cons c vs))
        w = full - L.zwToSp fs (pre + post)
        -- tracking after the character, given back at the line end (docs/adr/0020)
        t = tracking lk
        -- kenten on characters other than punctuation and separators (golem-driver ADR 0019)
        tag
          | isJust (lkKenten lk) && takesKenten c = KindKenten
          | ceVertical env && cls == Western = KindRotated
          | pre + post > 0 = KindPunctuation
          | otherwise = KindText
        hang = if ceHanging env && cls `elem` [FullStop, Comma] then w else 0
     in [Box (w + t) (BoxContent (T.cons c vs) False 0 hang (fromEnum tag) lk 0 (negate t) [] 0 0 (ceBoxSource env) Nothing (Leaf (ceSite env) (ceLeaf env)) (ceBoxAt env 0))]
  PWord lk word shys -> wordItems env lk word shys
  PSpace lk ->
    let sw = advance env lk ' '
     in if lkCode lk
          then [Glue (sw + tracking lk) 0 0] -- a space of inline code neither stretches nor shrinks (golem-layout ADR 0017)
          else [Glue (sw + tracking lk) (Sp (unSp sw `div` 2)) (Sp (unSp sw `div` 3))]
  PBox lk t kind w -> [Box w (BoxContent t False 0 0 (fromEnum kind) lk 0 0 [] 0 0 (ceBoxSource env) Nothing (Leaf (ceSite env) (ceLeaf env)) (ceBoxAt env 0))]
  PRuby lk kind base looks reading ->
    let style = ceRuby env
        rp = placeRuby style kind (baseAdvances env lk looks base) (readingAdvances env lk reading) (allowance True prev, allowance False next)
        -- how far the reading may overhang a neighbour: kana up to half its
        -- advance, the free space of a neighbouring reading, nothing else;
        -- a neighbouring base is measured in the looks of its characters
        allowance before = \case
          _ | not (rsOverhangOntoKana style) -> 0
          Just (PChar lk' c _) | isNothing (lkKenten lk'), isKanaClass (charClass c) -> min (rsOverhang style) (Sp (unSp (advance env lk' c) `div` 2))
          Just (PRuby lk' _ b ls Nothing) -> case (if before then reverse else id) (zip (map T.head (clusters b)) (ls <> repeat lk')) of
            (c, lc) : _ | isKanaClass (charClass c) -> min (rsOverhang style) (Sp (unSp (advance env lc c) `div` 2))
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
     in [Box (rpWidth rp) (BoxContent (base <> maybe "" ("|" <>) reading) False 0 0 (fromEnum tag) lk (rpOverhang rp) (rpOverhang rp) looks 0 0 (ceBoxSource env) Nothing (Leaf (ceSite env) (ceLeaf env)) (ceBoxAt env 0))]
  PRubyBreak -> [Penalty 0 0 NoHyphen]
  -- normalize sees no box next to these items: the spacing is that of the line's edge
  PForcedBreak -> lineEnd
  -- zw is the size of the type at its place; an empty box: no break between it and a neighbouring box (golem-layout ADR 0012)
  PAki lk a ->
    let w = case a of
          AkiZw r -> L.zwToSp (lkSize lk) r
          AkiAbs x -> x
     in [Box w (BoxContent "" False 0 0 (fromEnum KindAki) lk 0 0 [] 0 0 (ceBoxSource env) Nothing (Leaf (ceSite env) (ceLeaf env)) (ceBoxAt env 0))]
  PCode lk run ps pe -> codeItems env lk run ps pe
  {- a run of dashes: an em for each, whatever the font's advance; inseparable
  at both ends, so the spacing and the breaks around it are those of one
  dash; the tracking once, after it (docs/adr ADR 0172) -}
  PDashes lk d ->
    let t = tracking lk
        w = lkSize lk * fromIntegral (T.length d)
     in [Box (w + t) (BoxContent d False 0 0 (fromEnum KindDashes) lk 0 (negate t) [] 0 0 (ceBoxSource env) Nothing (Leaf (ceSite env) (ceLeaf env)) (ceBoxAt env 0))]
  PMark place lk parts ps pe -> [markItem env place lk parts ps pe]
  PAnchor _ -> []
  PShy _ -> []

{- | The box of the mark of a note in the text (golem-driver ADR 0018,
docs/adr/0177): one box, nothing breaks it and no aki set spaces it. Its
characters in the look of the mark, with its kerning, tracking and
proportional metrics; the tracking after each character but the last.
Across in horizontal text, as wide as its text; along the line in
vertical text, each part in its own box: a Japanese character upright,
Latin text turned, a tate-chu-yoko number an em of the mark.
-}
markItem :: ComposeEnv -> Look -> Look -> [MarkPart] -> Sp -> Sp -> Item
markItem env place lk parts ps pe =
  let m = lkSize lk
      tr = tracking lk
      txt = markPartsText parts
      units
        | ceVertical env = concatMap vertical parts
        | otherwise = [(KindText, txt, L.zwToSp m (ceWordAdvance env lk txt), T.length txt)]
      vertical = \case
        MarkTcy t -> [(KindTcy, t, m, 1)]
        MarkText t -> concatMap units' (groupBy (\a b -> latin a == latin b) (clusters t))
      -- a run of Latin text is turned as one; each other character stands in its own box
      units' us@(u : _)
        | latin u = let run = T.concat us in [(KindRotated, run, L.zwToSp m (ceWordAdvance env lk run), T.length run)]
      units' us = [(KindText, u, advanceOf u, T.length u) | u <- us]
      advanceOf u = case T.unpack u of
        [c] -> advance env lk c
        _ -> L.zwToSp m (ceWordAdvance env lk u)
      latin u = maybe False ((== Western) . lookClass lk . fst) (T.uncons u)
      chars = sum [k | (_, _, _, k) <- units]
      -- each unit after the one before it and the tracking of that one's characters
      starts = scanl (\o (_, _, u, k) -> o + u + tr * fromIntegral k) ps units
      parts' = [(fromEnum kind, t, o) | ((kind, t, _, _), o) <- zip units starts]
      w = sum [u | (_, _, u, _) <- units] + tr * fromIntegral (max 0 (chars - 1)) + ps + pe
   in Box w (BoxContent txt False 0 0 (fromEnum KindNoteMark) lk 0 0 [] ps pe (ceBoxSource env) (Just (MarkBox place parts')) (Leaf (ceSite env) (ceLeaf env)) (ceBoxAt env 0))

{- | A run of code (golem-driver ADR 0017): a box for each part of Latin
text, cut after each slash and run of low lines, and in code after each
run of hyphen-minus signs and full stops where it may break (golem-layout
ADR 0045), and in code a box for each character of other text, a base
character with its combining characters (golem-layout ADR 0034);
'normalize' decides the breaks between the boxes. No hyphenation,
protrusion or expansion.
-}
codeItems :: ComposeEnv -> Look -> Text -> Sp -> Sp -> [Item]
codeItems env lk run padStart padEnd =
  [ Box (w + tr * fromIntegral (trackedChars seg) + ps + pe) (BoxContent seg False 0 0 (fromEnum tag) lk 0 (negate tr) [] ps pe (ceBoxSource env) Nothing (Leaf (ceSite env) (ceLeaf env)) (ceBoxAt env k))
  | let segs = [unit | part <- slashParts run, seg <- T.groupBy sameSide part, unit <- if isCodeJapanese seg then clusters seg else [seg]]
        lastIx = length segs - 1,
    -- the index of the first character of each part in the run (docs/adr ADR 0195)
    (i, k, seg) <- zip3 [0 :: Int ..] (scanl (\n x -> n + T.length x) 0 segs) segs,
    let latin = maybe False ((== Western) . lookClass lk . fst) (T.uncons seg)
        w = L.zwToSp (lkSize lk) (ceWordAdvance env lk seg)
        tag = if ceVertical env && latin then KindRotated else KindText
        ps = if i == 0 then padStart else 0
        pe = if i == lastIx then padEnd else 0
  ]
  where
    tr = tracking lk
    {- the tracking after each character: a Japanese character of code
    is one box with its combining characters, of its advance and one
    tracking (golem-layout ADR 0034, C7); the Latin parts take one for
    each character -}
    trackedChars seg = if isCodeJapanese seg then 1 else T.length seg
    sameSide a b = isExtending b || (lookClass lk a == Western) == (lookClass lk b == Western)
    -- a run of Japanese characters of code, not of a URL (golem-layout ADR 0034)
    isCodeJapanese seg = lkCode lk && not (lkUrl lk) && maybe False ((/= Western) . lookClass lk . fst) (T.uncons seg)
    slashParts = if lkUrl lk then urlParts else codeParts
    {- code breaks after each slash (golem-driver ADR 0017), after the runs
    of low lines of the run but its first and its last (golem-layout ADR
    0031), and after its runs of hyphen-minus signs and full stops between
    two Latin characters (golem-layout ADR 0045) -}
    codeParts t = concatMap slashes (splitAtCuts (sort (lowLineCuts t <> stopCuts lk t)) 0 t)
    slashes t = case T.breakOn "/" t of
      (a, rest)
        | T.null rest -> [a | not (T.null a)]
        | otherwise -> (a <> "/") : slashes (T.drop 1 rest)

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
      PMark _ l _ _ _ -> key l
      PRuby l _ _ _ _ -> key l
      PRubyBreak -> Nothing
      _ -> Nothing
    key l = if lkCode l then Just (lkBackground l, lkPadding l) else Nothing
    transparent = \case
      PAnchor _ -> True
      PShy _ -> True
      PRubyBreak -> True
      _ -> False
    -- the padding goes on the first and the last piece when they are code
    padded run = case [i | (i, q) <- zip [0 :: Int ..] run, not (transparent q)] of
      [] -> run
      ixs@(firstIx : _) ->
        let lastIx = last ixs
            set i = \case
              PCode l t _ _ -> PCode l t (if i == firstIx then lkPadding l else 0) (if i == lastIx then lkPadding l else 0)
              PMark p l parts _ _ -> PMark p l parts (if i == firstIx then lkPadding l else 0) (if i == lastIx then lkPadding l else 0)
              q -> q
         in zipWith set [0 ..] run

{- | A Latin word: broken after its explicit hyphens and dashes (golem-layout
ADR 0008), and inside each element where the patterns allow (docs/adr/0179).
The patterns see the letters of each element only (docs/adr/0222): from
its first letter (a character of the general category L) to the first
character after it that is not a letter; what comes before and after
them goes back on the first and the last piece. An element with a hyphen
or dash left in it but its trailing ones, or a word kept whole by
explicit-hyphen-penalty 10000, gets no pattern hyphens. A word with a low
line is cut after its runs of low lines instead, with no hyphen, and gets
no pattern hyphens (golem-layout ADR 0031). A word of a link
is one box (docs/adr ADR 0182). A character at an end of a box protrudes
by its advance in the font of the box (docs/adr/0222).
-}
wordItems :: ComposeEnv -> Look -> Text -> [Int] -> [Item]
wordItems env lk word shys =
  let explicitP = ceExplicitHyphenPenalty env
      explicitPen = Penalty 0 explicitP ExplicitHyphen
      patternPen = Penalty (advance env lk '-') 50 (PatternHyphen (protAt snd '-'))
      -- a break at a soft hyphen: as one of the patterns, but the first pass takes it (docs/adr ADR 0272)
      softPen = Penalty (advance env lk '-') 50 (SoftHyphen (protAt snd '-'))
      isHyphen = isHyphenCharacter
      {- an element's pieces: the patterns' cuts of its letters, what is
      before them back on the first piece and what is after them (the
      trailing hyphens among it) on the last (docs/adr/0222) -}
      pieces el =
        let units = clusters el
            (stemUnits, _) = spanEnd (\u -> let b = T.filter (not . isExtending) u in not (T.null b) && T.all isHyphen b) units
            (preUnits, rest) = break isLetterUnit units
            (letterUnits, postUnits) = span isLetterUnit rest
            (pre, letters, post) = (T.concat preUnits, T.concat letterUnits, T.concat postUnits)
         in case cePatterns env (lkLang lk) of
              Just p | not (T.null letters), not (T.any isHyphen (T.concat stemUnits)) -> onFirst (pre <>) (onLast (<> post) (hyphenateUnits p letters))
              _ -> [el]
      -- a letter with its combining characters
      isLetterUnit u = maybe False (isLetter . fst) (T.uncons u)
      spanEnd f xs = let (b, a) = span f (reverse xs) in (reverse a, reverse b)
      onLast f xs = case reverse xs of
        x : rest -> reverse (f x : rest)
        [] -> [f ""]
      onFirst f = \case
        x : rest -> f x : rest
        [] -> [f ""]
      -- a break after a run of low lines: no hyphen (golem-layout ADR 0031)
      lowLinePen = Penalty 0 100 NoHyphen
      lowLined = T.any (== '_') word
      -- the pen inside an element without soft hyphens
      innerPen = if lowLined then lowLinePen else patternPen
      -- the parts of a word with a low line at its written hyphens, each with the index of its first character in the word
      hyphenParts = if explicitP >= infPenalty || not (T.any isHyphen word) then [word] else explicitParts word
      {- the soft hyphens (docs/adr ADR 0272): an element with one is cut at
      those that are breaks, and at nothing else; the elements are those of
      the written hyphens, which a word kept whole by explicit-hyphen-penalty
      10000 is not broken at -}
      cuts = softHyphenCuts lk word shys
      shyElements = IntSet.fromList [fst (elementSpan word p) | p <- shys]
      withShys o part = if IntSet.member o shyElements then (softPen, splitAtCuts cuts o part) else (innerPen, if lowLined then splitAtCuts (lowLineCuts word) o part else pieces part)
      elements
        | isJust (lkLink lk) = [(innerPen, [word])]
        | not (null shys) && explicitP >= infPenalty = [(softPen, splitAtCuts cuts 0 word)]
        | not (null shys) = [withShys o part | (o, part) <- offsetsOf (if T.any isHyphen word then explicitParts word else [word])]
        | lowLined = [(lowLinePen, splitAtCuts (lowLineCuts word) o part) | (o, part) <- offsetsOf hyphenParts]
        | T.any isHyphen word = if explicitP >= infPenalty then [(innerPen, [word])] else map ((innerPen,) . pieces) (explicitParts word)
        | otherwise = [(innerPen, pieces word)]
      offsetsOf ps = zip (scanl (+) 0 (map T.length ps)) ps
      rotated = ceVertical env
      tag = fromEnum (if rotated then KindRotated else KindText)
      tr = tracking lk
      -- the tracking after each character, given back at the line end (docs/adr/0020)
      box (k, t) =
        let w = L.zwToSp (lkSize lk) (ceWordAdvance env lk t)
            ps = maybe 0 (min w . protIn t fst . fst) (T.uncons t)
            pe = maybe 0 (min w . protIn t snd . snd) (T.unsnoc t)
         in Box (w + tr * fromIntegral (T.length t)) (BoxContent t True ps pe tag lk 0 (negate tr) [] 0 0 (ceBoxSource env) Nothing (Leaf (ceSite env) (ceLeaf env)) (ceBoxAt env k))
      -- the advance of the character at the line end, without tracking, by its ratio (golem-layout ADR 0014)
      protAt pick c = if ceProtrusion env then Sp (unSp (advance env lk c) * pick (protrusionRatio c) `div` 1000) else 0
      -- that of a character at an end of a box, in the font of the box (docs/adr/0222)
      protIn t pick c = if ceProtrusion env then Sp (unSp (L.zwToSp (lkSize lk) (ceWordCharAdvance env lk t c)) * pick (protrusionRatio c) `div` 1000) else 0
      withPens pen = concat . zipWith (\i x -> (if i > (0 :: Int) then pen else []) <> x) [0 ..]
      -- each box with the index of its first character in the word (docs/adr ADR 0195)
      indexed = snd (mapAccumL (\k (pen, ts) -> let (k', ixs) = mapAccumL (\k0 t -> (k0 + T.length t, (k0, t))) k ts in (k', (pen, ixs))) 0 elements)
   in withPens [explicitPen] [withPens [pen] (map (pure . box) ixs) | (pen, ixs) <- indexed]

{- | Where a word is cut after its runs of low lines (golem-layout ADR
0031): after each run that has a character before it and one after it in
the word (a_|b, a__|b; not _a, a_ or __init__), as 'explicitParts' cuts
after hyphens; a combining character after a low line stays with it.
-}
lowLineCuts :: Text -> [Int]
lowLineCuts word = [end | (i, g, end) <- zip3 [0 :: Int ..] groups ends, i > 0, i < lastIx, T.all (== '_') (T.filter (not . isExtending) g)]
  where
    groups = map T.concat (groupBy (\a b -> (T.head a == '_') == (T.head b == '_')) (clusters word))
    ends = drop 1 (scanl (+) 0 (map T.length groups))
    lastIx = length groups - 1

{- | Where a run of code between spaces is cut after its runs of
hyphen-minus signs and full stops (golem-layout ADR 0045): after each run
with a character before it and one after it in the run, both Latin, neither
a slash nor a low line, and not both digits (attest-|build-|provenance,
a--|b; not -n, foo., a/-b, a-_b nor 1.0). A combining character after a
sign stays with it.
-}
stopCuts :: Look -> Text -> [Int]
stopCuts lk word =
  [ end
  | (i, g, end) <- zip3 [0 :: Int ..] groups ends,
    i > 0,
    i < lastIx,
    all (isCodeStop . T.head) g,
    Just x <- [lastBase (groups !! (i - 1))],
    Just y <- [T.head <$> listToMaybe (groups !! (i + 1))],
    stopBreaksBetween lk x y
  ]
  where
    groups = groupBy (\a b -> isCodeStop (T.head a) == isCodeStop (T.head b)) (clusters word)
    ends = drop 1 (scanl (+) 0 (map (sum . map T.length) groups))
    lastIx = length groups - 1
    lastBase g = T.head <$> listToMaybe (reverse g)

-- | The characters of the runs code breaks after (golem-layout ADR 0045): the hyphen-minus sign and the full stop.
isCodeStop :: Char -> Bool
isCodeStop c = c == '-' || c == '.'

{- | Whether code breaks after a run of hyphen-minus signs and full stops
between the characters given, the one before the run and the one after it
(golem-layout ADR 0045): both Latin, neither a slash nor a low line, and
not both digits.
-}
stopBreaksBetween :: Look -> Char -> Char -> Bool
stopBreaksBetween lk x y =
  lookClass lk x == Western
    && lookClass lk y == Western
    && all (\c -> c /= '/' && c /= '_') [x, y]
    && not (isDigit x && isDigit y)
    && not (isCodeStop y)

-- | A part of a word that starts at an index of the word, cut at those of the indices given inside it.
splitAtCuts :: [Int] -> Int -> Text -> [Text]
splitAtCuts cuts o part = case [c - o | c <- cuts, c > o, c < o + T.length part] of
  [] -> [part]
  inside -> go 0 inside part
  where
    go at (c : cs) t = let (a, b) = T.splitAt (c - at) t in a : go c cs b
    go _ [] t = [t]

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
  | -- | a box, and whether a box comes right before it
    AfterBox !BoxContent !Bool

{- | Inserts break opportunities and spacing between neighbouring boxes:
no break where a prohibition applies (golem-layout ADR 0002), and the
spacing of the aki set of the paragraph (docs/adr ADR 0019). The spaces
of the line start and the line end are the edges of the boxes. An [aki]
is an empty box between its neighbours: the set adds no space there, and
it has no edges (golem-layout ADR 0012). The indices given are those of
the glue of the spaces of inline code among the items (golem-layout ADR
0038).
-}
normalize :: ComposeEnv -> IntSet.IntSet -> [Item] -> [Item]
normalize env codeSpaces = go (0 :: Int) AtStart True
  where
    set = ceAkiSet env
    go _ _ _ [] = []
    go k before first (x : rest) = case x of
      -- an [aki]: no spacing around it, no edges; the paragraph's first character is still to come
      Box _ c | boxKind c == KindAki -> x : go (k + 1) AfterAki first rest
      {- a note mark joins the box before it (golem-driver ADR 0018): no
      break and no spacing before it, and the spacing of the pair around
      it after it; it has no edges -}
      Box w c
        | boxKind c == KindNoteMark ->
            let before' = case before of
                  AtStart -> AfterStartMark
                  other -> other
             in Penalty 0 infPenalty NoHyphen : Box w c {bcEdgeStart = 0, bcEdgeEnd = 0} : go (k + 1) before' first rest
      Box w c ->
        let spacing = case before of
              -- inside code: a break after a slash, no spacing (golem-driver ADR 0017)
              -- inside a URL: a break after the characters of url.sty's breaks (golem-layout ADR 0018)
              AfterBox p _ | lkUrl (bcLook p) && lkUrl (bcLook c) -> [Penalty 0 n NoHyphen | Just n <- [urlBreakAfter (bcText p)]]
              {- inside code: also a break of 100 after a run of low lines, but
              the first of the run, a box of low lines alone with no box before
              it (golem-layout ADR 0031) -}
              {- inside code, where a Japanese character is on either side: a
              break where no prohibition applies, of 100 after a low line and
              0 otherwise, the only one there (golem-layout ADR 0034) -}
              AfterBox p _
                | codeOnly p && codeOnly c && japaneseAt (lastClass p) (firstClass c) ->
                    [codeBreak p (if "_" `T.isSuffixOf` baseOf p then 100 else 0) | not (prohibitedAcross True p c)]
              {- inside code: also a break of 100 after a run of hyphen-minus
              signs and full stops between two Latin characters, but where a
              slash, a low line or two digits are beside it (golem-layout ADR
              0045); 'codeItems' cuts the boxes there -}
              AfterBox p afterBox
                | breaksAsCode (bcLook p) && breaksAsCode (bcLook c) ->
                    [codeBreak p 0 | "/" `T.isSuffixOf` bcText p]
                      <> [codeBreak p 100 | "_" `T.isSuffixOf` baseOf p, afterBox || T.any (/= '_') (baseOf p)]
                      <> [codeBreak p 100 | codeOnly p && codeOnly c, afterStops p c]
              AfterBox p _ -> between p c
              AtStart -> leading c
              -- the space of the paragraph start, after the mark: no break there
              AfterStartMark -> case leading c of
                [] -> []
                l -> Penalty 0 infPenalty NoHyphen : l
              AfterAki -> []
         in spacing <> [Box w (withEdges first c)] <> go (k + 1) (AfterBox c (isBoxBefore before)) False rest
      {- a space between words: no break at it where the character after it
      may not start a line or the one before it may not end one; its width
      and the spacing after it as before (golem-layout ADR 0028); a space
      of inline code likewise, which still neither stretches nor shrinks
      (golem-layout ADR 0038) -}
      Glue {}
        | wordSpace x || IntSet.member k codeSpaces,
          AfterBox p _ <- before,
          Just c <- nextBox rest,
          prohibitedAcross False p c ->
            Penalty 0 infPenalty NoHyphen : x : go (k + 1) AtStart first rest
      -- a break after a written hyphen or dash: none where a prohibition applies across it (golem-layout ADR 0028)
      Penalty _ _ ExplicitHyphen
        | AfterBox p _ <- before,
          Box _ c : _ <- rest,
          prohibitedAcross True p c ->
            go (k + 1) AtStart first rest
      _ -> x : go (k + 1) AtStart first rest
    isBoxBefore = \case
      AfterBox {} -> True
      _ -> False
    -- a box of code, not of a URL (golem-layout ADR 0034)
    codeOnly b = lkCode (bcLook b) && not (lkUrl (bcLook b))
    -- a box of code that ends with a run of hyphen-minus signs and full stops after a character, before one code breaks after the run at (golem-layout ADR 0045)
    afterStops p c =
      let stops = T.takeWhileEnd isCodeStop (baseOf p)
          body = T.dropWhileEnd isCodeStop (baseOf p)
       in not (T.null stops) && case (T.unsnoc body, T.uncons (baseOf c)) of
            (Just (_, x), Just (y, _)) -> stopBreaksBetween (bcLook p) x y
            _ -> False
    japaneseAt a b = maybe False (/= Western) a || maybe False (/= Western) b
    {- a break inside code other than at a space: in code, as wide as the
    wrap mark of the box before it, which the line ends with when it
    breaks there (golem-layout ADR 0034) -}
    codeBreak p n
      | codeOnly p, let m = lkWrapMark (bcLook p), not (T.null m) = Penalty (wrapMarkWidth (bcLook p) m) n (WrapMark m)
      | otherwise = Penalty 0 n NoHyphen
    {- the width of the wrap mark, 3/5 of the size of the code: the square
    of the shape of the default mark, or the advance of the text of another
    at that size (golem-layout ADR 0042) -}
    wrapMarkWidth lk m
      | m == shapedWrapMark = wrapMarkSize (lkSize lk)
      | otherwise = L.zwToSp (wrapMarkSize (lkSize lk)) (ceWordAdvance env lk m)
    -- the glue of a space between words: it stretches, but not as the glue that fills the last line; a space of code does not
    wordSpace = \case
      Glue _ y _ -> y > 0 && y < filStretch
      _ -> False
    -- the box after the spaces, if a box of text comes next
    nextBox = \case
      g : more | wordSpace g -> nextBox more
      Box _ c : _ | boxKind c `notElem` [KindAki, KindNoteMark] -> Just c
      _ -> Nothing
    {- the prohibitions across a space or a written hyphen: the line start
    and the line end, and two inseparable characters across a written
    hyphen only; not the rule that keeps two Latin words together -}
    prohibitedAcross hyphen p c =
      let pk = breakClass lastChar lastClass p
          ck = startClass c
       in maybe False (lineStartProhibited (ceKinsokuStrict env)) ck
            || maybe False lineEndProhibited pk
            || (hyphen && pk == Just Inseparable && ck == Just Inseparable)
    sizeOf = lkSize . bcLook
    glueOf base (A.Aki n o m) =
      let sp = L.zwToSp base
       in [Glue (sp o) (sp m - sp o) (sp o - sp n)]
    -- the space before the first box of a paragraph, in the box's size
    leading c = case akiFirst c of
      Just b | a <- akiBetween set AkiParagraphStart (AkiChar b), a /= noAki -> glueOf (sizeOf c) a
      _ -> []
    -- the line start (but not the paragraph start) and the line end are fixed, in the box's size
    withEdges first c = case (akiFirst c, akiLast c) of
      (Just f, Just l) ->
        let edge a = L.zwToSp (sizeOf c) (A.akiOptimum a)
         in c
              { bcEdgeStart = bcEdgeStart c + (if first then 0 else edge (akiBetween set AkiLineStart (AkiChar f))),
                bcEdgeEnd = bcEdgeEnd c + edge (akiBetween set (AkiChar l) AkiLineEnd)
              }
      _ -> c
    -- the classes come from the base characters, without combining characters (golem-driver ADR 0036)
    baseOf = baseText . bcText
    firstChar c = case T.uncons (baseOf c) of
      Just (ch, _) | not (isRuby c) -> Just ch
      _ -> Nothing
    lastChar c = case T.unsnoc (baseOf c) of
      Just (_, ch) | not (isRuby c) -> Just ch
      _ -> Nothing
    firstClass c = lookClass (bcLook c) <$> firstChar c
    lastClass c = lookClass (bcLook c) <$> lastChar c
    {- a character of both scripts in a Latin span (docs/adr ADR 0187): no
    aki beside it, and the line breaks beside it as beside the Japanese
    character, by the kinsoku of its Japanese class (docs/adr/0211) -}
    latinDual c = \case
      Just ch -> isDualCharacter ch && maybe False (not . spanIsJapanese) (lkLang (bcLook c))
      Nothing -> False
    breakClass edge cls c = if latinDual c (edge c) then dualJapaneseClass <$> edge c else cls c
    {- the class of the first character of a box for kinsoku: an apostrophe
    at the start of a Latin word, U+2019 with a letter or a digit after it
    (its combining characters left out), is Latin, in no span and in a
    Latin one alike (golem-layout ADR 0030) -}
    startClass c
      | bcExpandable c,
        Just ('\x2019', more) <- T.uncons (baseOf c),
        Just (n, _) <- T.uncons more,
        isLetter n || generalCategory n == DecimalNumber =
          Just Western
      | otherwise = breakClass firstChar firstClass c
    isRuby c = boxKind c `elem` [KindRuby, KindGroupRuby]
    -- a Latin word is Latin text at both ends, quotation marks and dashes included
    akiFirst c = if bcExpandable c then Just Western else firstClass c
    akiLast c = if bcExpandable c then Just Western else lastClass c
    isPunct k = k `elem` [Opening, Closing, FullStop, Comma, MiddleDot]
    between p c =
      let pc = lastClass p
          cc = firstClass c
          pk = breakClass lastChar lastClass p
          ck = startClass c
          strict = ceKinsokuStrict env
          noBreak =
            maybe False (lineStartProhibited strict) ck
              || maybe False lineEndProhibited pk
              || (pk == Just Inseparable && ck == Just Inseparable)
              || (pc == Just Western && cc == Just Western && bcExpandable p && bcExpandable c)
          noAkiHere = latinDual p (lastChar p) || latinDual c (firstChar c)
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
              | not noAkiHere,
                aki <- akiBetween set (AkiChar a) (AkiChar b),
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
      Lang _ _ xs -> concatMap go xs
      Resolved _ _ _ xs -> concatMap go xs
      Note _ _ xs -> concatMap go xs
      _ -> []

{- | The size of the wrap mark of inline code against the size of the code
(golem-layout ADR 0042): the breaking of lines and the drawing both use it.
-}
wrapMarkScale :: Rational
wrapMarkScale = 3 / 5

-- | The size of the wrap mark of code of the size given: 'wrapMarkScale' of it, rounded down (golem-layout ADR 0042).
wrapMarkSize :: Sp -> Sp
wrapMarkSize (Sp s) = Sp (floor (toRational s * wrapMarkScale))

{- | The wrap mark drawn as a shape, not as a glyph: U+23CE, the default of
the character style code. Any other text is drawn in its glyphs
(golem-layout ADR 0042).
-}
shapedWrapMark :: Text
shapedWrapMark = "\x23CE"
