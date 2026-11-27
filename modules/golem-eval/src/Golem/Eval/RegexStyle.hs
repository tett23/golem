{- | Regex styles (docs/adr ADR 0015): the matches of the regex styles of a
paragraph style, laid on the semantic IR as 'CharStyle' at the end of the
evaluation of a file, so that every medium shows the same result.

Each paragraph is matched alone. Its target is the text of its inlines:
the characters of 'Text', the bases of 'Ruby' (not the readings), one
replacement character (U+FFFC) for an element that cannot be split or
whose text is not known yet ('Tcy', 'Number', 'Ref', 'Deferred', 'Cite'), for 'Aki'
and for 'Note', 'Sidenote' and 'Endnote', a newline for 'LineBreak', and nothing for
'IndexMark', 'ProofComment' and 'ChannelItem' (golem-doc ADR 0007).
-}
module Golem.Eval.RegexStyle
  ( RegexRules,
    regexRules,
    applyRegexStyles,
    applyInitialStyles,
  )
where

import Data.Char (GeneralCategory (..), generalCategory)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (groupBy)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Project.Style (LocalValue (..), ParaStyleDef (..), RegexStyleDef (..), Style (..), headingParaStyle, paraStyle, paraStyleWith)
import Golem.Regex (Regex, compile, matches)
import Golem.Syntax
import Golem.Unicode.Grapheme (graphemeClusters)

-- | The compiled regex styles by paragraph style (body included), in order.
type RegexRules = Map Text [(Regex, Text)]

{- | Every paragraph style of a style, resolved through based-on, with its
regex styles compiled; a style without any is left out. The patterns were
checked when the style was read, so none fails to compile (one that does
is left out).
-}
regexRules :: Style -> RegexRules
regexRules style =
  Map.fromList
    [ (n, compiled)
    | n <- Map.keys (stParaStyles style),
      Just ParaStyleDef {psRegexStyles = Just rs} <- [paraStyle style (Just n)],
      let compiled = [(r, rdStyle d) | d <- rs, Right r <- [compile (rdPattern d)]],
      not (null compiled)
    ]

{- | The regex styles laid on every paragraph of a document: a paragraph
gets those of its paragraph style (body when it has none), a paragraph of
a caption those of caption, the body of a sidenote those of sidenote,
each cell of a table those of the paragraph style of its cells, table
when it has none (docs/adr/0262). A heading, each term of a definition
list and each paragraph of the body of a note get those of body, each
matched alone: the generated number of a heading and the mark of a note
are not in its text, and the mark of a note in a paragraph is one
character there (docs/adr/0368). The captions of tables and code blocks
are left as they are.
-}
applyRegexStyles :: RegexRules -> Document -> Document
applyRegexStyles rules d
  | Map.null rules = d
  | otherwise = d {docBlocks = map (block Nothing) (docBlocks d)}
  where
    rulesOf n = Map.findWithDefault [] n rules
    -- forced: the paragraph style of the paragraphs of a caption
    block forced b = b {blockBody = body forced (blockBody b)}
    body forced = \case
      Paragraph st is -> Paragraph st (paragraph (rulesOf (fromMaybe (fromMaybe "body" (styleRefNameOf st)) forced)) is)
      Heading level attrs is -> Heading level attrs (paragraph (rulesOf "body") is)
      BulletList items -> BulletList (map item items)
      OrderedList items -> OrderedList (map item items)
      DefList groups -> DefList [g {dgTerms = map (paragraph (rulesOf "body")) (dgTerms g), dgDefs = map (map (block Nothing)) (dgDefs g)} | g <- groups]
      FigureBlock fig -> FigureBlock fig {figCaption = map (block (Just "caption")) (figCaption fig)}
      FrameBlock name bs -> FrameBlock name (map (block Nothing) bs)
      TableBlock t ->
        let cell = paragraph (rulesOf (fromMaybe "table" (styleRefNameOf (tableStyle t))))
         in TableBlock t {tableHeader = map cell (tableHeader t), tableRows = map (map cell) (tableRows t)}
      other -> other
    item i = i {itemBlocks = map (block Nothing) (itemBlocks i)}
    paragraph :: [(Regex, Text)] -> [InlineF r] -> [InlineF r]
    paragraph rs is = wrap rs (map sidenotes is)
    -- the bodies of notes and sidenotes
    sidenotes :: InlineF r -> InlineF r
    sidenotes = \case
      -- the paragraphs of the body of a note, with the regex styles of body (docs/adr/0368)
      Note sp n lbl bs -> Note sp n lbl [b {blockBody = case blockBody b of Paragraph st is -> Paragraph st (paragraph (rulesOf "body") is); other -> other} | b <- bs]
      Sidenote sp n lbl bs -> Sidenote sp n lbl [b {blockBody = case blockBody b of Paragraph st is -> Paragraph st (paragraph (rulesOf "sidenote") is); other -> other} | b <- bs]
      -- the body of an endnote, as that of a note (root ADR 0412)
      Endnote sp n lbl bs -> Endnote sp n lbl [b {blockBody = case blockBody b of Paragraph st is -> Paragraph st (paragraph (rulesOf "body") is); other -> other} | b <- bs]
      Kenten sp k xs -> Kenten sp k (map sidenotes xs)
      Color sp c xs -> Color sp c (map sidenotes xs)
      CharStyle sp c xs -> CharStyle sp c (map sidenotes xs)
      Link sp u xs -> Link sp u (map sidenotes xs)
      Lang sp l xs -> Lang sp l (map sidenotes xs)
      Resolved sp k l xs -> Resolved sp k l (map sidenotes xs)
      Ruby sp r segs -> Ruby sp r [s {rsBase = map sidenotes (rsBase s)} | s <- segs]
      other -> other

-- ------------------------------------------------------------------ the first character

{- | The character style of initial-style laid on the first character of
each paragraph at the top of a document (docs/adr/0374): the paragraphs
of the file and of the body form of @style, not those of lists, tables,
captions and notes. The first character is counted as a regex style
counts characters: an element that cannot be split is one character and
is wrapped whole, an element without a character is not counted, and the
styles written by hand are split and copied inside it.
-}
applyInitialStyles :: Style -> Document -> Document
applyInitialStyles style d = d {docBlocks = map block (docBlocks d)}
  where
    block b = case blockBody b of
      Paragraph st is | Just c <- refStyle st >>= psInitialStyle -> b {blockBody = Paragraph st (initialStyled c is)}
      Heading level attrs is | Just c <- headingParaStyle style level >>= psInitialStyle -> b {blockBody = Heading level attrs (headingInitialStyled c is)}
      _ -> b
    -- the style of a paragraph, the keys of @style over it (root ADR 0467)
    refStyle st = paraStyleWith style (styleRefNameOf st) (maybe [] refValues st)
    refValues r = [(k, case v of StyleWord w -> LocalWord w; StyleString t -> LocalString t) | (k, v) <- Map.toAscList (styleRefKeys r)]

{- | The inlines with their first character wrapped in a character style:
a base character and the combining characters after it (golem-driver
ADR 0036). Inlines without a character are left as they are.
-}
initialStyled :: Text -> [InlineF r] -> [InlineF r]
initialStyled name is = case T.uncons (T.concat (map targetOf is)) of
  Just (c, rest) | c /= '\n' -> wrapRuns (Labels [name] (IntMap.fromList [(p, [0]) | p <- [0 .. T.length (T.takeWhile isExtending rest)]])) 0 is
  _ -> is
  where
    isExtending x = generalCategory x `elem` [NonSpacingMark, SpacingCombiningMark, EnclosingMark]

-- | A heading's initial style covers one whole grapheme (root ADR 0468).
headingInitialStyled :: Text -> [InlineF r] -> [InlineF r]
headingInitialStyled name is = case graphemeClusters (T.concat (map targetOf is)) of
  first : _ | first /= "\n" -> wrapRuns (Labels [name] (IntMap.fromList [(p, [0]) | p <- [0 .. T.length first - 1]])) 0 is
  _ -> is

-- ------------------------------------------------------------------ wrapping

-- | The names of the regex styles and the regex styles of each position of the target.
data Labels = Labels ![Text] !(IntMap [Int])

{- | The inlines of a paragraph with the regex styles laid on them: the
characters the same set of regex styles matched form a run, wrapped at
the level of the inlines given, the first regex style outermost.
-}
wrap :: [(Regex, Text)] -> [InlineF r] -> [InlineF r]
wrap [] is = is
wrap rs is =
  let target = T.concat (map targetOf is)
      hits = [(p, i) | (i, (r, _)) <- zip [0 :: Int ..] rs, (a, b) <- matches r target, p <- [a .. b - 1]]
      labels = Labels (map snd rs) (IntMap.fromListWith (<>) [(p, [i]) | (p, i) <- hits])
   in wrapRuns labels 0 is

-- | The text an inline stands for in the target.
targetOf :: InlineF r -> Text
targetOf = \case
  Text _ x -> x
  Ruby _ _ segs -> T.concat [T.concat (map targetOf (rsBase s)) | s <- segs]
  Kenten _ _ xs -> T.concat (map targetOf xs)
  Color _ _ xs -> T.concat (map targetOf xs)
  CharStyle _ _ xs -> T.concat (map targetOf xs)
  -- the text of a link, as that of a character style (docs/adr ADR 0182)
  Link _ _ xs -> T.concat (map targetOf xs)
  -- the text of a language span, likewise (docs/adr ADR 0187)
  Lang _ _ xs -> T.concat (map targetOf xs)
  -- the text of a resolved reference, likewise (docs/adr/0215)
  Resolved _ _ _ xs -> T.concat (map targetOf xs)
  LineBreak _ -> "\n"
  IndexMark _ _ -> ""
  ChannelItem _ _ -> ""
  ProofComment _ _ -> ""
  _ -> "\xFFFC"

width :: InlineF r -> Int
width = T.length . targetOf

-- | The regex styles of a position, in the order of the list.
labelAt :: Labels -> Int -> [Int]
labelAt (Labels _ m) p = reverse (IntMap.findWithDefault [] p m)

{- | A piece of the inlines: the regex styles all its characters have, or
Nothing for an inline that is never wrapped and cuts a run.
-}
type Piece r = (Maybe [Int], InlineF r)

-- | The inlines starting at a position of the target, each run of the same regex styles wrapped.
wrapRuns :: Labels -> Int -> [InlineF r] -> [InlineF r]
wrapRuns labels@(Labels names _) start is =
  concatMap run (groupBy sameRun (piecesOf labels start is))
  where
    sameRun (a, _) (b, _) = a == b && isJust a
    run = \case
      ps@((Just (l : ls), _) : _) -> [wrapIn (names !! l) [names !! x | x <- ls] (map snd ps)]
      ps -> map snd ps

-- | The inlines wrapped in character styles, the first outermost; the span runs from the first to the last.
wrapIn :: Text -> [Text] -> [InlineF r] -> InlineF r
wrapIn outer inner xs =
  let sp = case (xs, reverse xs) of
        (x : _, y : _) -> mkSpan (spanFile (spanOf x)) (spanStart (spanOf x)) (spanEnd (spanOf y))
        _ -> mkSpan (FileId 0) 0 0
   in CharStyle sp outer (foldr (\s content -> [CharStyle sp s content]) xs inner)

-- | The pieces of the inlines starting at a position of the target.
piecesOf :: Labels -> Int -> [InlineF r] -> [Piece r]
piecesOf labels = go
  where
    go _ [] = []
    go p (x : xs) = piecesOfOne labels p x <> go (p + width x) xs

piecesOfOne :: Labels -> Int -> InlineF r -> [Piece r]
piecesOfOne labels p = \case
  Text sp x
    | T.null x -> [(Just [], Text sp x)]
    | otherwise ->
        [ (Just l, Text sp (T.pack (map snd run)))
        | run@((l, _) : _) <- groupBy (\a b -> fst a == fst b) [(labelAt labels i, c) | (i, c) <- zip [p ..] (T.unpack x)]
        ]
  Kenten sp k xs -> container (Kenten sp k) xs
  Color sp c xs -> container (Color sp c) xs
  CharStyle sp c xs -> container (CharStyle sp c) xs
  x@(Ruby sp r segs) -> case [labelAt labels i | i <- [p .. p + width x - 1]] of
    [] -> [(Just [], x)]
    l : rest
      | all (== l) rest -> [(Just l, x)]
      | otherwise ->
          -- a boundary inside the base: each base is wrapped inside, and the ruby is not wrapped
          let starts = scanl (+) p [sum (map width (rsBase s)) | s <- segs]
           in [(Nothing, Ruby sp r [s {rsBase = wrapRuns labels q (rsBase s)} | (s, q) <- zip segs starts])]
  {- a link is not split (docs/adr ADR 0182): wrapped whole when its
  characters have the same regex styles, otherwise wrapped inside -}
  x@(Link sp u xs) -> case [labelAt labels i | i <- [p .. p + width x - 1]] of
    [] -> [(Just [], x)]
    l : rest
      | all (== l) rest -> [(Just l, x)]
      | otherwise -> [(Nothing, Link sp u (wrapRuns labels p xs))]
  -- a language span likewise, so that it stays one span as written (docs/adr ADR 0187)
  x@(Lang sp l xs) -> case [labelAt labels i | i <- [p .. p + width x - 1]] of
    [] -> [(Just [], x)]
    lb : rest
      | all (== lb) rest -> [(Just lb, x)]
      | otherwise -> [(Nothing, Lang sp l (wrapRuns labels p xs))]
  -- a resolved reference likewise, so that it stays one reference (docs/adr/0215)
  x@(Resolved sp k l xs) -> case [labelAt labels i | i <- [p .. p + width x - 1]] of
    [] -> [(Just [], x)]
    lb : rest
      | all (== lb) rest -> [(Just lb, x)]
      | otherwise -> [(Nothing, Resolved sp k l (wrapRuns labels p xs))]
  x@(LineBreak _) -> [(Nothing, x)]
  x@(Note {}) -> [(Nothing, x)]
  x@(Sidenote {}) -> [(Nothing, x)]
  x@(Endnote {}) -> [(Nothing, x)]
  x@(IndexMark {}) -> [(Nothing, x)]
  x@(ChannelItem {}) -> [(Nothing, x)]
  x@(ProofComment {}) -> [(Nothing, x)]
  x -> [(Just (labelAt labels p), x)]
  where
    -- a style written by hand is split at the boundaries and copied, inside the regex styles
    container mk xs = case groupBy (\a b -> fst a == fst b) (piecesOf labels p xs) of
      [] -> [(Just [], mk [])]
      groups -> [(l, mk (map snd ps)) | ps@((l, _) : _) <- groups]

spanOf :: InlineF r -> SrcSpan
spanOf = \case
  Text s _ -> s
  Ruby s _ _ -> s
  Kenten s _ _ -> s
  Color s _ _ -> s
  CharStyle s _ _ -> s
  Tcy s _ -> s
  Warichu s _ -> s
  Upright s _ -> s
  Number s _ _ -> s
  Ref s _ _ -> s
  Deferred s _ -> s
  Note s _ _ _ -> s
  Sidenote s _ _ _ -> s
  Endnote s _ _ _ -> s
  IndexMark s _ -> s
  Cite s _ -> s
  ProofComment s _ -> s
  LineBreak s -> s
  Aki s _ -> s
  ChannelItem s _ -> s
  Link s _ _ -> s
  Lang s _ _ -> s
  Resolved s _ _ _ -> s
