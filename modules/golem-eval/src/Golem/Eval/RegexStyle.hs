{- | Regex styles (docs/adr ADR 0015): the matches of the regex styles of a
paragraph style, laid on the semantic IR as 'CharStyle' at the end of the
evaluation of a file, so that every medium shows the same result.

Each paragraph is matched alone. Its target is the text of its inlines:
the characters of 'Text', the bases of 'Ruby' (not the readings), one
replacement character (U+FFFC) for an element that cannot be split or
whose text is not known yet ('Tcy', 'Number', 'Ref', 'Deferred', 'Cite'), for 'Aki'
and for 'Note' and 'Sidenote', a newline for 'LineBreak', and nothing for
'IndexMark' and 'ProofComment'.
-}
module Golem.Eval.RegexStyle
  ( RegexRules,
    regexRules,
    applyRegexStyles,
  )
where

import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (groupBy)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Project.Style (ParaStyleDef (..), RegexStyleDef (..), Style (..), paraStyle)
import Golem.Regex (Regex, compile, matches)
import Golem.Syntax

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
a caption those of caption, the body of a sidenote those of sidenote.
Headings, the terms of definition lists, table cells and the bodies of
notes are left as they are.
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
      Paragraph st is -> Paragraph st (paragraph (rulesOf (fromMaybe (fromMaybe "body" st) forced)) is)
      BulletList items -> BulletList (map item items)
      OrderedList items -> OrderedList (map item items)
      DefList groups -> DefList [g {dgDefs = map (map (block Nothing)) (dgDefs g)} | g <- groups]
      FigureBlock fig -> FigureBlock fig {figCaption = map (block (Just "caption")) (figCaption fig)}
      other -> other
    item i = i {itemBlocks = map (block Nothing) (itemBlocks i)}
    paragraph :: [(Regex, Text)] -> [InlineF r] -> [InlineF r]
    paragraph rs is = wrap rs (map sidenotes is)
    -- the bodies of sidenotes, with the regex styles of sidenote
    sidenotes :: InlineF r -> InlineF r
    sidenotes = \case
      Sidenote sp n xs -> Sidenote sp n (paragraph (rulesOf "sidenote") xs)
      Kenten sp k xs -> Kenten sp k (map sidenotes xs)
      Color sp c xs -> Color sp c (map sidenotes xs)
      CharStyle sp c xs -> CharStyle sp c (map sidenotes xs)
      Ruby sp r segs -> Ruby sp r [s {rsBase = map sidenotes (rsBase s)} | s <- segs]
      other -> other

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
  LineBreak _ -> "\n"
  IndexMark _ _ -> ""
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
  x@(LineBreak _) -> [(Nothing, x)]
  x@(Note {}) -> [(Nothing, x)]
  x@(Sidenote {}) -> [(Nothing, x)]
  x@(IndexMark {}) -> [(Nothing, x)]
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
  Number s _ _ -> s
  Ref s _ _ -> s
  Deferred s _ -> s
  Note s _ _ -> s
  Sidenote s _ _ -> s
  IndexMark s _ -> s
  Cite s _ -> s
  ProofComment s _ -> s
  LineBreak s -> s
  Aki s _ -> s
