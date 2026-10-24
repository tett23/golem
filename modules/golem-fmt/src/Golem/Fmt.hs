{- | The formatter (golem-fmt ADR 0001). It rewrites the lossless CST and
never changes the AST: every rule is checked against the AST of the
original source and a rule that would change it is not applied. The rule
that removes escapes is checked with the escapes it may remove made text
(golem-parser ADR 0010).
-}
module Golem.Fmt
  ( preprocess,
    format,
    FormatResult (..),
    astFingerprint,
    astFingerprintWith,
    removableEscape,
    rules,
  )
where

import Data.Char (isAscii, isPunctuation, isSpace, isSymbol)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Parser (parse, parseAst)
import Golem.Parser.AST (plainEscapesIn)
import Golem.Parser.CST
import Golem.Syntax
import Golem.Syntax.Text (isSpaceTab)

data FormatResult
  = Formatted Text
  | -- | syntax errors remain after preprocessing; the file is left alone
    Unformattable [Diagnostic]
  deriving stock (Show)

{- | Text-level fixes for what the reader rejects: BOM, CRLF, a lone CR
(golem-fmt ADR 0003) and tab indentation (one tab = two spaces). CRLF is
made one LF before the lone CRs, or it would become two line breaks.
-}
preprocess :: Text -> Text
preprocess t0 =
  let t1 = fromMaybe t0 (T.stripPrefix "\xFEFF" t0)
      t2 = T.replace "\r" "\n" (T.replace "\r\n" "\n" t1)
   in T.intercalate "\n" (map untab (T.splitOn "\n" t2))
  where
    untab l =
      let (ind, rest) = T.span (\c -> c == ' ' || c == '\t') l
       in T.concatMap (\c -> if c == '\t' then "  " else T.singleton c) ind <> rest

-- | The AST without source positions.
astFingerprint :: Text -> Text
astFingerprint = astFingerprintWith (const False)

{- | The AST without source positions, with the escaped characters that
match made text (golem-parser ADR 0010).
-}
astFingerprintWith :: (Char -> Bool) -> Text -> Text
astFingerprintWith p src =
  let (f, _, _) = parseAst (FileId 0) src
   in eraseSpans (T.pack (show (plainEscapesIn p f)))
  where
    eraseSpans t = case T.breakOn "SrcSpan {" t of
      (pre, rest)
        | T.null rest -> pre
        | otherwise -> pre <> eraseSpans (T.drop 1 (T.dropWhile (/= '}') rest))

{- | Formats a source. The AST of the preprocessed source is what every
rule must keep.
-}
format :: Text -> FormatResult
format src0 =
  let src = preprocess src0
      (root, diags) = parse (FileId 0) src
   in if hasErrors diags
        then Unformattable diags
        else Formatted (foldl' (apply src) (render root) rulesWith)
  where
    -- the AST of the rule's result against the original's, compared with
    -- the escapes the rule may remove made text (golem-parser ADR 0010)
    apply orig cur (removable, rule) =
      let (r, _) = parse (FileId 0) cur
          next = render (rule r)
       in if next /= cur && astFingerprintWith removable next == astFingerprintWith removable orig && not (hasErrors (snd (parse (FileId 0) next)))
            then next
            else cur

-- | The rules, in the order they are applied.
rules :: [Node -> Node]
rules = map snd rulesWith

{- | The rules with the escaped characters each may remove. Only 'escapes'
removes escapes, of the characters 'removableEscape' allows.
-}
rulesWith :: [(Char -> Bool, Node -> Node)]
rulesWith =
  [ (none, blankLines),
    (none, trailingWhitespace),
    (none, commandSpacing),
    (none, tableSpacing),
    (removableEscape, escapes),
    (none, finalNewline)
  ]
  where
    none = const False

-- ------------------------------------------------------------------ helpers

mapChildren :: ([Element] -> [Element]) -> Node -> Node
mapChildren f n = node (nodeKind n) (f (map deep (nodeChildren n)))
  where
    deep (ElemNode m) = ElemNode (mapChildren f m)
    deep e = e

isTok :: SyntaxKind -> Element -> Bool
isTok k (ElemToken t) = tokKind t == k
isTok _ _ = False

isNode :: SyntaxKind -> Element -> Bool
isNode k (ElemNode m) = nodeKind m == k
isNode _ _ = False

-- ------------------------------------------------------------------ rules

-- | One blank line between blocks; none at the start or the end of the file.
blankLines :: Node -> Node
blankLines root =
  let inner = mapChildren (map collapse) root
      cs = nodeChildren inner
      trimmed = reverse (dropWhile (isNode NBlankLines) (reverse (dropWhile (isNode NBlankLines) cs)))
   in node (nodeKind inner) trimmed
  where
    collapse e@(ElemNode m)
      | nodeKind m == NBlankLines = ElemNode (node NBlankLines [token KNewline "\n"])
      | otherwise = e
    collapse e = e

-- | Trailing whitespace of the last text token among elements.
trimLastText :: [Element] -> [Element]
trimLastText es = case break isText (reverse es) of
  (after, ElemToken (Token KText t) : before)
    | all isTrivia after ->
        let t' = T.dropWhileEnd isSpaceTab t
         in reverse before <> [token KText t' | not (T.null t')] <> reverse after
  _ -> es
  where
    isText = isTok KText
    isTrivia = isTok KWhitespace

-- | Leading whitespace of the first text token among elements.
trimFirstText :: [Element] -> [Element]
trimFirstText = \case
  (ElemToken (Token KText t) : rest) ->
    let t' = T.dropWhile isSpaceTab t
     in [token KText t' | not (T.null t')] <> rest
  es -> es

-- | Whitespace at the end of a line.
trailingWhitespace :: Node -> Node
trailingWhitespace = mapChildren go
  where
    go (w : nl : rest) | isTok KWhitespace w && isTok KNewline nl = go (nl : rest)
    -- text ending a line: its trailing whitespace is not text (golem-parser ADR 0006)
    go (ElemToken (Token KText t) : nl : rest)
      | isTok KNewline nl =
          let t' = T.dropWhileEnd isSpaceTab t
           in [token KText t' | not (T.null t')] <> go (nl : rest)
    go [w] | isTok KWhitespace w && not (isEmptyTok w) = []
    go (e : rest) = e : go rest
    go [] = []
    isEmptyTok (ElemToken t) = T.null (tokText t)
    isEmptyTok _ = False

{- | One space between a command name and its arguments and between
arguments, none before @:@, one after @:@ and @|@, none before @]@.
-}
commandSpacing :: Node -> Node
commandSpacing = rewrite
  where
    rewrite n
      | nodeKind n `elem` [NInlineCommand, NBlockCommand] =
          node (nodeKind n) (fixCommand (nodeKind n) (map deep (nodeChildren n)))
      | otherwise = node (nodeKind n) (map deep (nodeChildren n))
    deep (ElemNode m) = ElemNode (rewrite m)
    deep e = e
    fixCommand _ cs =
      -- the indentation, '[' and '@' before the name are not touched
      let (pre, body) = break (isTok KIdent) cs
       in pre <> spaced body
    spaced = \case
      (sl : rest@(nx : _)) | isNode NProseSlot sl -> slotEnd (isTok KPipe nx) sl : spaced rest
      (w : c : rest) | isTok KWhitespace w && isTok KColon c -> spaced (c : rest)
      (c : rest) | isTok KColon c || isTok KPipe c -> c : oneSpace rest
      (w : r : rest) | isTok KWhitespace w && isTok KRBracket r -> r : spaced rest
      (w : rest) | isTok KWhitespace w && not (null rest) && not (startsLine rest) -> token KWhitespace " " : spaced rest
      (e : rest) -> e : spaced rest
      [] -> []
    -- a prose slot ends without whitespace; before '|' one space follows (ADR 0006)
    slotEnd nextIsPipe = \case
      ElemNode m
        | nodeKind m == NProseSlot ->
            let trimmed = trimLastText (nodeChildren m)
             in ElemNode (node NProseSlot (trimmed <> [token KText " " | nextIsPipe, not (null trimmed)]))
      e -> e
    oneSpace = \case
      (w : rest) | isTok KWhitespace w -> token KWhitespace " " : spaced rest
      rest@(s : _) | isNode NProseSlot s -> token KWhitespace " " : spaced rest
      rest -> spaced rest
    startsLine = \case
      (e : _) -> isTok KNewline e || isTok KEquals e || isNode NCommandBody e
      [] -> True

{- | One space on each side of every @|@ of a table row; column widths are
not aligned (golem-fmt ADR 0001).
-}
tableSpacing :: Node -> Node
tableSpacing = rewrite
  where
    rewrite n
      | nodeKind n == NTableCell =
          let inner = trimLastText (trimFirstText (nodeChildren n))
           in node NTableCell ([token KText " "] <> inner <> [token KText " " | not (null inner)])
      | otherwise = node (nodeKind n) (map deep (nodeChildren n))
    deep (ElemNode m) = ElemNode (rewrite m)
    deep e = e

-- | Escapes of characters that mean nothing special are removed.
escapes :: Node -> Node
escapes = mapChildren (map unescape)
  where
    unescape e@(ElemToken t)
      | tokKind t == KEscape,
        Just (_, c) <- T.uncons (tokText t) >>= T.uncons . snd >>= \(c', r) -> if T.null r then Just ((), c') else Nothing,
        removableEscape c =
          token KText (T.singleton c)
      | otherwise = e
    unescape e = e

{- | A character whose escape the formatter may remove: not a space, an
ASCII punctuation or symbol, or a digit. Every character the evaluation
tells apart by an escape (@/@, the space and the tab) must stay out of it,
or formatting could change the meaning of a source (golem-parser ADR 0010).
-}
removableEscape :: Char -> Bool
removableEscape c = not (isSpace c || (isAscii c && (isPunctuation c || isSymbol c || c `elem` ['0' .. '9'])))

-- | The file ends with exactly one newline.
finalNewline :: Node -> Node
finalNewline root
  | T.null (render root) = root
  | T.isSuffixOf "\n" (render root) = root
  | otherwise = node (nodeKind root) (nodeChildren root <> [token KNewline "\n"])
