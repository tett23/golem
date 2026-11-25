{- | The formatter (golem-fmt ADR 0001). It rewrites the lossless CST and
never changes the AST: every rule is checked against the AST of the
original source and a rule that would change it is not applied. The rule
that removes escapes is checked with the escapes it may remove made text
(golem-parser ADR 0010).
-}
module Golem.Fmt
  ( preprocess,
    formatTable,
    format,
    FormatResult (..),
    astFingerprint,
    astFingerprintWith,
    removableEscape,
    rules,
  )
where

import Data.Char (isAscii, isPunctuation, isSpace, isSymbol)
import Data.ByteString qualified as BS
import Data.List (sortOn, stripPrefix)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Parser (parse, parseAst)
import Golem.Parser.AST (plainEscapesIn)
import Golem.Parser.AST qualified as A
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
preprocess = T.intercalate "\n" . map untab . T.splitOn "\n" . normalizeLineEndings . stripOneBOM
  where
    stripOneBOM text = fromMaybe text (T.stripPrefix "\xFEFF" text)
    untab l =
      let (ind, rest) = T.span (\c -> c == ' ' || c == '\t') l
       in T.concatMap (\c -> if c == '\t' then "  " else T.singleton c) ind <> rest

-- | Remove the complete leading BOM run from a table file (Golem ADR 0354).
formatTable :: Text -> Text
formatTable = normalizeLineEndings . T.dropWhile (== '\xFEFF')

normalizeLineEndings :: Text -> Text
normalizeLineEndings = T.replace "\r" "\n" . T.replace "\r\n" "\n"

-- | The AST without source positions.
astFingerprint :: Text -> Text
astFingerprint = astFingerprintWith (const False)

{- | The AST without source positions, with the escaped characters that
match made text (golem-parser ADR 0010).
-}
astFingerprintWith :: (Char -> Bool) -> Text -> Text
astFingerprintWith p src =
  let (f, _, _) = parseAst (FileId 0) src
   in T.pack (eraseSpans (show (plainEscapesIn p f)))
  where
    -- Skip records only outside the quoted Text and Char literals of Show.
    eraseSpans input
      | Just rest <- stripPrefix "SrcSpan {" input =
          eraseSpans (drop 1 (dropWhile (/= '}') rest))
    eraseSpans (c : rest)
      | c == '"' || c == '\'' = c : quoted c rest
      | otherwise = c : eraseSpans rest
    eraseSpans [] = []
    quoted delimiter ('\\' : c : rest) = '\\' : c : quoted delimiter rest
    quoted delimiter (c : rest)
      | c == delimiter = c : eraseSpans rest
      | otherwise = c : quoted delimiter rest
    quoted _ [] = []

{- | Formats a source. The AST of the preprocessed source is what every
rule must keep.
-}
format :: Text -> FormatResult
format src0 =
  let src1 = preprocess src0
      (_, diags) = parse (FileId 0) src1
      -- the forms of @import are written first; they change the AST (root ADR 0451)
      rewritten = importForms src1
      src = if hasErrors (snd (parse (FileId 0) rewritten)) then src1 else rewritten
      (root, _) = parse (FileId 0) src
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

{- | The two forms of @import (root ADR 0451): the form without @*@,
@path as ns@, is written @path * as ns@, and a list of names is written
@{ a, b }@, a space inside the braces and after each comma. This is the
one rewriting that changes the AST, so it is applied before the rules.
An @import with anything but spaces between its words (a comment), with
a body, or of another form is left as it is.
-}
importForms :: Text -> Text
importForms src =
  let (A.File _ bs, _, _) = parseAst (FileId 0) src
   in splice (concatMap site bs)
  where
    bytes = TE.encodeUtf8 src
    slice s e = TE.decodeUtf8Lenient (BS.take (e - s) (BS.drop s bytes))
    site (A.Located _ b) = case b of
      A.BlockCommand (A.Located _ "import") (path : rest@(_ : _)) [] -> edit path rest
      A.Attributed cmds _ -> concatMap site cmds
      _ -> []
    edit (A.Located psp pathArg) rest = case (pathArg, traverse word rest) of
      (A.Positional v, Just ws)
        | isPath v,
          let start = spanEnd psp
              end = maximum (map (spanEnd . A.locSpan) rest)
              written = slice start end,
          T.words written == ws,
          Just new <- shape ws,
          new /= written ->
            [(start, end, new)]
      _ -> []
    isPath = \case
      A.Word _ -> True
      A.StringLit _ -> True
      _ -> False
    word = \case
      A.Located _ (A.Positional (A.Word w)) -> Just w
      _ -> Nothing
    shape = \case
      ["as", ns] -> Just (" * as " <> ns)
      ws -> (\ns -> " { " <> T.intercalate ", " ns <> " }") <$> listed (concatMap pieces ws)
    pieces w = case T.uncons w of
      Nothing -> []
      Just (c, rest)
        | isMark c -> Left c : pieces rest
        | otherwise -> let (n, rest') = T.break isMark w in Right n : pieces rest'
    isMark c = c == '{' || c == '}' || c == ','
    listed = \case
      Left '{' : Right n : rest -> (n :) <$> more rest
      _ -> Nothing
    more = \case
      [Left '}'] -> Just []
      Left ',' : Right n : rest -> (n :) <$> more rest
      _ -> Nothing
    splice edits =
      let go from = \case
            [] -> [BS.drop from bytes]
            (s, e, new) : es -> BS.take (s - from) (BS.drop from bytes) : TE.encodeUtf8 new : go e es
       in TE.decodeUtf8 (BS.concat (go 0 (sortOn (\(s, _, _) -> s) edits)))

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
    (none, commentSpacing),
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

{- | Spaces around comments in argument lists and manuscript expressions
(Golem ADR 0339). The trivia token itself is kept byte for byte.
-}
commentSpacing :: Node -> Node
commentSpacing = go
  where
    go n =
      let cs = map descend (nodeChildren n)
          k = nodeKind n
          eligible = k `elem` [NInlineCommand, NBlockCommand, NCodeBlock, NExpr, NRangeExpr, NBinaryExpr, NUnaryExpr, NCallExpr, NVarExpr, NArrayExpr, NHashExpr, NHashEntry, NParenExpr]
       in node k (if eligible then adjust cs else cs)
    descend (ElemNode n) = ElemNode (go n)
    descend e = e
    adjust cs = case cs of
      (a : ElemToken (Token KWhitespace _) : b : rest)
        | edgeLast a `elem` map Just [KExprOpen, KLParen, KLBracket, KLBrace], edgeFirst b == Just KComment -> a : adjust (b : rest)
      (a : ElemToken (Token KWhitespace _) : b : rest)
        | edgeLast a == Just KComment, edgeFirst b `elem` map Just [KRBracket, KRParen, KRBrace, KColon] -> a : adjust (b : rest)
      (a : ElemToken (Token KWhitespace _) : b : rest)
        | boundary a b -> a : token KWhitespace " " : adjust (b : rest)
      (a : b : rest)
        | boundary a b -> a : token KWhitespace " " : adjust (b : rest)
      (a : rest) -> a : adjust rest
      [] -> []
    boundary a b =
      let left = edgeLast a
          right = edgeFirst b
          comment = left == Just KComment || right == Just KComment
          tight =
            left `elem` map Just [KExprOpen, KLParen, KLBracket, KLBrace]
              || right `elem` map Just [KRBracket, KRParen, KRBrace, KColon, KNewline]
       in comment && not tight && left /= Just KWhitespace && right /= Just KWhitespace
    edgeFirst = \case
      ElemToken t -> Just (tokKind t)
      ElemNode n -> case nodeChildren n of
        (e : _) -> edgeFirst e
        [] -> Nothing
    edgeLast = \case
      ElemToken t -> Just (tokKind t)
      ElemNode n -> case reverse (nodeChildren n) of
        (e : _) -> edgeLast e
        [] -> Nothing

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
