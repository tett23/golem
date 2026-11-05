{- | fmt of .emet (docs/adr/0160). Indentation has no meaning in .emet, so
fmt decides it: two spaces a level; a line after @{@ and before @}@ of
@case@ and @where@, whose items are a level below the line of @{@; the
guards on lines of their own, a level below the line of the name. A line
that goes on from the line before (a newline that is white space) is a
level below the item it belongs to.

The newlines are the writer's: fmt neither adds nor removes a newline
that separates items, and keeps every newline of a line that goes on.
The newlines it adds (after @{@, before @}@ and before a guard) are those
the grammar reads the same with or without. Lines are not wrapped. Runs
of blank lines become one. A BOM is removed and CR becomes LF (G01002,
G01003).

fmt works on the tokens of the lossless syntax tree, so comments stay
where they are; the tree tells a newline that separates (SepNl) from one
that is white space (Nl).

The requirements of a row (docs/adr/0161) are put in the order of their
kinds and paths, as @<file "a.tsv", file "b.tsv"|e>@. A row with a
comment or a newline in it is left as it is, as fmt does not move a
comment.
-}
module Golem.Emet.Fmt
  ( formatEmet,
  )
where

import Data.List (sortOn)
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet.Generated qualified as G
import Golem.Emet.Parse (parseModule)
import Golem.Syntax
import Peg.Runtime.Syntax (syntaxTokens, tokenKind, tokenText)

data Tok = Tok !TokKind !Text

data TokKind = KWs | KNl | KSep | KComment | KOpen | KClose | KGuard | KOther
  deriving stock (Eq)

-- | How a line starts: a new item, a line that goes on, or after a break fmt added.
data LineKind = ItemLine | ContLine
  deriving stock (Eq)

-- | The formatted text, or the errors that keep the file from being read.
formatEmet :: Text -> Either [Diagnostic] Text
formatEmet raw = do
  let src = T.replace "\r" "\n" (T.replace "\r\n" "\n" (fromMaybe raw (T.stripPrefix "\xFEFF" raw)))
  _ <- parseModule (FileId 0) src
  tree <- either (const (Left [])) Right (G.parseSyntax src)
  let raws = [(G.nameOfSyntaxKind (tokenKind t), tokenText t) | t <- syntaxTokens tree]
      toks = [Tok (kindOf k) x | (k, x) <- sortRows raws]
  pure (render (layout (splitLines toks)))

{- | The requirements of each row in the order of their kinds and paths,
over the tokens by the names of their kinds. A row already in order, or
with a comment or a newline in it, keeps its tokens.
-}
sortRows :: [(Text, Text)] -> [(Text, Text)]
sortRows = \case
  [] -> []
  open@("RowOpen", _) : rest ->
    let (inside, after) = break ((== "RowClose") . fst) rest
     in case after of
          close : more -> row open inside close <> sortRows more
          [] -> open : inside
  t : rest -> t : sortRows rest
  where
    row open inside close
      | any ((`elem` ["Comment", "Nl", "SepNl"]) . fst) inside = open : inside <> [close]
      | otherwise =
          let (reqPart, tailPart) = break ((== "|") . snd) inside
              items = map trim (splitItems reqPart)
              sorted = sortOn key items
           in if map key sorted == map key items
                then open : inside <> [close]
                else open : joinWith [(",", ","), ("Ws", " ")] sorted <> tailPart <> [close]
    -- the words of a requirement: its kind and its literals
    key = map (T.concat . map snd) . filter (not . null) . splitOnWs
    splitOnWs ts = case break ((== "Ws") . fst) ts of
      (w, []) -> [w]
      (w, _ : more) -> w : splitOnWs more
    trim = reverse . dropWhile ((== "Ws") . fst) . reverse . dropWhile ((== "Ws") . fst)
    splitItems ts = case break ((== ",") . snd) ts of
      ([], []) -> []
      (item, []) -> [item]
      (item, _ : more) -> item : splitItems more
    joinWith sep = \case
      [] -> []
      x : xs -> x <> concatMap (sep <>) xs

kindOf :: Text -> TokKind
kindOf = \case
  "Ws" -> KWs
  "Nl" -> KNl
  "SepNl" -> KSep
  "Comment" -> KComment
  "OpenBlock" -> KOpen
  "CloseBlock" -> KClose
  "GuardBar" -> KGuard
  _ -> KOther

isCode :: Tok -> Bool
isCode (Tok k _) = k `notElem` [KWs, KComment]

{- | The lines of the tokens, without their newlines, each with how it
starts: the breaks of the writer, and those fmt adds after @{@, before
@}@ and before a guard.
-}
splitLines :: [Tok] -> [(LineKind, [Tok])]
splitLines = finish . foldl' step ([], ItemLine, [], False)
  where
    -- (done lines reversed, kind of the current line, current line reversed, break before the next code)
    step (done, kind, cur, brk) t@(Tok k _) = case k of
      KNl -> ((kind, reverse cur) : done, ContLine, [], False)
      KSep -> ((kind, reverse cur) : done, ItemLine, [], False)
      KWs -> (done, kind, t : cur, brk)
      KComment -> (done, kind, t : cur, brk)
      _ ->
        let here = any isCode cur
            (done', kind', cur')
              | here && brk = ((kind, reverse cur) : done, ItemLine, [])
              | here && k == KClose = ((kind, reverse cur) : done, ItemLine, [])
              | here && k == KGuard = ((kind, reverse cur) : done, ContLine, [])
              | otherwise = (done, kind, cur)
         in (done', kind', t : cur', k == KOpen)
    finish (done, kind, cur, _) = reverse ((kind, reverse cur) : done)

{- | Each line with its indentation: an item starts at the level of its
block, a line that goes on is a level below, and @}@ is at the level of
the line of its @{@. Nothing for a blank line.
-}
layout :: [(LineKind, [Tok])] -> [Maybe (Int, [Tok])]
layout = go []
  where
    go _ [] = []
    go stack ((kind, l) : ls) =
      case dropWhile isWs l of
        [] -> Nothing : go stack ls
        code@(Tok first _ : _) ->
          let base = case stack of
                o : _ -> o + 1
                [] -> 0
              indent
                | first == KClose = case stack of
                    o : _ -> o
                    [] -> 0
                | kind == ItemLine = base
                | otherwise = base + 1
              stack' = foldl' (advance indent) stack code
           in Just (indent, code) : go stack' ls
    advance indent stack (Tok k _) = case k of
      KOpen -> indent : stack
      KClose -> drop 1 stack
      _ -> stack
    isWs (Tok k _) = k == KWs

-- | The text: runs of blank lines as one, none at the start or the end.
render :: [Maybe (Int, [Tok])] -> Text
render ls =
  let texts = squeeze (map line ls)
      trimmed = reverse (dropWhile isNothing (reverse (dropWhile isNothing texts)))
   in T.unlines (map (fromMaybe "") trimmed)
  where
    line = fmap (\(n, toks) -> T.replicate (2 * n) " " <> T.stripEnd (T.concat [t | Tok _ t <- toks]))
    squeeze = \case
      Nothing : rest@(Nothing : _) -> squeeze rest
      x : rest -> x : squeeze rest
      [] -> []
