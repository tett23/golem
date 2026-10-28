-- | Lowering the CST to the AST (golem-parser ADR 0005).
module Golem.Parser.Lower
  ( lower,
    numberWord,
  )
where

import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Parser.AST
import Golem.Parser.CST
import Golem.Syntax.Span
import Golem.Syntax.Text (isSpaceTab)

-- A CST with absolute spans.
data P
  = PN !SyntaxKind !SrcSpan [P]
  | PT !SyntaxKind !SrcSpan !Text

pspan :: P -> SrcSpan
pspan (PN _ s _) = s
pspan (PT _ s _) = s

pkind :: P -> SyntaxKind
pkind (PN k _ _) = k
pkind (PT k _ _) = k

annotate :: FileId -> Node -> P
annotate fid = goNode 0
  where
    goNode start n = PN (nodeKind n) (mkSpan fid start (start + nodeWidth n)) (goChildren start (nodeChildren n))
    goChildren _ [] = []
    goChildren start (e : es) =
      let w = elementWidth e
          here = case e of
            ElemNode m -> goNode start m
            ElemToken t -> PT (tokKind t) (mkSpan fid start (start + w)) (tokText t)
       in here : goChildren (start + w) es

isTriviaP :: P -> Bool
isTriviaP p = pkind p `elem` [KWhitespace, KComment, KNewline]

significant :: [P] -> [P]
significant = filter (not . isTriviaP)

lower :: FileId -> Node -> File
lower fid root = case annotate fid root of
  PN _ _ cs -> File fid (blocks cs)
  PT {} -> File fid []

-- ------------------------------------------------------------------ blocks

blocks :: [P] -> [Located Block]
blocks = mapMaybe block

block :: P -> Maybe (Located Block)
block p@(PN k sp cs) = case k of
  NParagraph -> case inlines cs of
    [] -> Nothing
    is -> Just (Located sp (Paragraph is))
  NHeading -> Just (Located sp (Heading (headingLevel cs) (inlines [c | c <- cs, pkind c /= KHash])))
  NBulletList -> Just (Located sp (BulletList (items cs)))
  NOrderedList -> Just (Located sp (OrderedList (items cs)))
  NDefList -> Just (Located sp (DefList [defGroup gs | PN NDefGroup _ gs <- cs]))
  NTable -> Just (Located sp (table cs))
  NCodeBlock -> Just (Located sp (codeBlock cs))
  NAttributed -> Just (attributed p)
  NBlockCommand -> Just (blockCommand p)
  NErrorNode -> Just (Located sp ErrorBlock)
  _ -> Nothing
block (PT KError sp _) = Just (Located sp ErrorBlock)
block PT {} = Nothing

headingLevel :: [P] -> Int
headingLevel cs = case [t | PT KHash _ t <- cs] of
  (t : _) -> T.length t
  [] -> 1

items :: [P] -> [ListItem]
items cs = [item ics | PN NListItem _ ics <- cs]
  where
    item ics =
      let (first, rest) = break isBlockNode (dropMarker ics)
          firstPara = case inlines first of
            [] -> []
            is -> [Located (coverSpan (pspan <$> first)) (Paragraph is)]
       in firstPara <> blocks rest
    dropMarker = filter (\c -> pkind c `notElem` [KDash, KPlus])

isBlockNode :: P -> Bool
isBlockNode = \case
  PN k _ _ -> k `elem` [NParagraph, NHeading, NBulletList, NOrderedList, NDefList, NTable, NCodeBlock, NAttributed, NBlockCommand, NErrorNode]
  PT KError _ _ -> True
  _ -> False

coverSpan :: [SrcSpan] -> SrcSpan
coverSpan [] = mkSpan (FileId 0) 0 0
coverSpan sps@(s0 : _) = mkSpan (spanFile s0) (minimum (map spanStart sps)) (maximum (map spanEnd sps))

defGroup :: [P] -> DefGroup
defGroup cs =
  DefGroup
    { dgTerms = [inlines [c | c <- tcs, pkind c /= KEquals] | PN NDefTerm _ tcs <- cs],
      dgDefs = [blocks bcs | PN NDefBody _ bcs <- cs]
    }

table :: [P] -> Block
table cs =
  let rows = [[inlines (trimStart ccs) | PN NTableCell _ ccs <- rcs] | PN NTableRow _ rcs <- cs]
      aligns = concat [[alignment t | PT KDelim _ t <- dcs] | PN NTableDelimiter _ dcs <- cs]
   in case rows of
        (h : body) -> Table aligns h body
        [] -> Table aligns [] []
  where
    alignment t =
      let s = T.strip t
       in case (T.isPrefixOf ":" s, T.isSuffixOf ":" s) of
            (True, True) -> AlignCenter
            (True, False) -> AlignLeft
            (False, True) -> AlignRight
            _ -> AlignDefault

codeBlock :: [P] -> Block
codeBlock cs =
  let ind = case cs of
        (PT KWhitespace _ t : _) -> T.length t
        _ -> 0
      lang = case [t | PT KWord _ t <- cs] of
        (t : _) -> Just t
        [] -> Nothing
      ls = [Located (withoutNewline sp t) (dropNewline (stripIndent ind t)) | PT KCodeText sp t <- cs]
   in CodeBlock lang (arguments (significant cs)) ls
  where
    stripIndent n t = let (pre, rest) = T.splitAt n t in if T.all (== ' ') pre then rest else t
    dropNewline t = fromMaybe t (T.stripSuffix "\n" t)
    withoutNewline sp t = if "\n" `T.isSuffixOf` t then mkSpan (spanFile sp) (spanStart sp) (spanEnd sp - 1) else sp

attributed :: P -> Located Block
attributed (PN _ sp cs) =
  let cmds = [blockCommand c | c@(PN NBlockCommand _ _) <- cs]
      target = case filter (\c -> isBlockNode c && pkind c /= NBlockCommand) cs of
        (b : _) -> block b
        [] -> Nothing
   in case (cmds, target) of
        ([single], Nothing) -> single
        _ -> Located sp (Attributed cmds target)
attributed p = Located (pspan p) ErrorBlock

blockCommand :: P -> Located Block
blockCommand (PN _ sp cs) =
  let sig = significant cs
   in case [(s, t) | PT KIdent s t <- sig] of
        ((_, "set") : (vsp, var) : _)
          | any ((== KEquals) . pkind) sig ->
              Located sp (SetVar (Located vsp var) (exprOf sp [c | c <- sig, isExprNode c]))
        ((nsp, name) : _) ->
          Located sp (BlockCommand (Located nsp name) (arguments sig) (concat [blocks bcs | PN NCommandBody _ bcs <- cs]))
        [] -> Located sp ErrorBlock
blockCommand p = Located (pspan p) ErrorBlock

-- ------------------------------------------------------------------ inlines

{- | A newline between the lines of a paragraph or a prose slot becomes
'SoftBreak' (docs/adr ADR 0003); the newline that ends the inlines does not.
A hard break stays even at the edges; the evaluation reports it there
(docs/adr ADR 0016).
-}
inlines :: [P] -> [Located Inline]
inlines = joinText . dropEdgeBreaks . concatMap inline . trimEnds
  where
    dropEdgeBreaks = reverse . dropWhile isBreak . reverse . dropWhile isBreak
    isBreak (Located _ SoftBreak) = True
    isBreak _ = False

{- | Whitespace at the end of a line, and at the end of the inlines (a
block's last line, a table cell, a prose slot) is not text (ADR 0006).
Escaped spaces are separate tokens and stay.
-}
trimEnds :: [P] -> [P]
trimEnds = \case
  [] -> []
  -- the line after a hard break starts without spaces and tabs (docs/adr ADR 0016)
  (h@(PN NHardBreak _ _) : PT KText sp t : rest) ->
    let t' = T.dropWhile isSpaceTab t
        sp' = mkSpan (spanFile sp) (spanEnd sp - utf8Len t') (spanEnd sp)
     in h : trimEnds ([PT KText sp' t' | not (T.null t')] <> rest)
  (PT KText sp t : rest)
    | atLineEnd rest ->
        let t' = T.dropWhileEnd isSpaceTab t
            sp' = mkSpan (spanFile sp) (spanStart sp) (spanEnd sp - utf8Len (T.drop (T.length t') t))
         in [PT KText sp' t' | not (T.null t')] <> trimEnds rest
  (p : rest) -> p : trimEnds rest
  where
    atLineEnd = \case
      [] -> True
      (PT KNewline _ _ : _) -> True
      (PN NHardBreak _ _ : _) -> True
      (PT KWhitespace _ _ : more) -> atLineEnd more
      _ -> False

-- | Whitespace at the start of a table cell (ADR 0006).
trimStart :: [P] -> [P]
trimStart = \case
  (PT KText sp t : rest) ->
    let t' = T.dropWhile isSpaceTab t
        sp' = mkSpan (spanFile sp) (spanEnd sp - utf8Len t') (spanEnd sp)
     in [PT KText sp' t' | not (T.null t')] <> rest
  (PT KWhitespace _ _ : rest) -> trimStart rest
  ps -> ps

utf8Len :: Text -> Int
utf8Len = BS.length . TE.encodeUtf8

inline :: P -> [Located Inline]
inline = \case
  PT KText sp t -> [Located sp (Text t)]
  -- the escaped character stays apart from the text (golem-parser ADR 0010)
  PT KEscape sp t -> case T.uncons (T.drop 1 t) of
    Just (c, rest) | T.null rest -> [Located sp (Escaped c)]
    _ -> [Located sp (Text (T.drop 1 t))]
  PT KProofComment sp t -> [Located sp (ProofComment (proofText t))]
  PT KError sp _ -> [Located sp ErrorInline]
  PT KNewline sp _ -> [Located sp SoftBreak]
  PT {} -> []
  PN NBlankLines _ _ -> []
  PN NExpr sp cs -> [Located sp (Expr (exprOf sp (filter isExprNode cs)))]
  p@(PN NInlineCommand _ _) -> [command p]
  -- from the backslash to the end of the newline; the newline is no SoftBreak
  PN NHardBreak sp cs ->
    let end = case [spanEnd s | PT KNewline s _ <- cs] of
          (e : _) -> e
          [] -> spanEnd sp
     in [Located (mkSpan (spanFile sp) (spanStart sp) end) HardBreak]
  PN NErrorNode sp _ -> [Located sp ErrorInline]
  -- the source text, read by the evaluation (golem-parser ADR 0011)
  PN NNumberShorthand sp cs -> [Located sp (NumberShorthand (T.concat [t | PT _ _ t <- cs]))]
  PN _ _ cs -> concatMap inline cs

proofText :: Text -> Text
proofText = T.strip . dropEnd . T.drop 3
  where
    dropEnd t = fromMaybe t (T.stripSuffix "%%" t)

command :: P -> Located Inline
command (PN _ sp cs) =
  let sig = significant cs
      name = case [Located s t | PT KIdent s t <- sig] of
        (n : _) -> n
        [] -> Located sp ""
      slots = [inlines scs | PN NProseSlot _ scs <- cs]
   in Located sp (Command name (arguments sig) slots)
command p = Located (pspan p) ErrorInline

arguments :: [P] -> [Located Argument]
arguments = mapMaybe arg
  where
    arg = \case
      PN NArgument sp acs -> case significant acs of
        (v : _) -> Located sp . Positional <$> argValue v
        [] -> Nothing
      PN NKeywordArgument sp acs -> case significant acs of
        (PT KWord ksp k : _ : v : _) -> Located sp . Keyword (Located ksp k) <$> argValue v
        _ -> Nothing
      PN NSplatArgument sp acs ->
        let isDouble = any (\case PT KStar _ t -> t == "**["; _ -> False) acs
            e = exprOf sp (filter isExprNode acs)
         in Just (Located sp (if isDouble then SplatKeyword e else SplatPositional e))
      _ -> Nothing

argValue :: P -> Maybe ArgValue
argValue = \case
  PT KString _ t -> Just (StringLit (unquote t))
  PT KWord _ t -> Just (Word t)
  PN NExpr sp cs -> Just (ExprArg (Located sp (locValue (exprOf sp (filter isExprNode cs)))))
  p@(PN NInlineCommand _ _) -> Just (CommandArg (command p))
  _ -> Nothing

unquote :: Text -> Text
unquote t = go (T.unpack (T.dropEnd 1 (T.drop 1 t)))
  where
    go ('\\' : c : rest) = T.cons c (go rest)
    go (c : rest) = T.cons c (go rest)
    go [] = T.empty

-- ------------------------------------------------------------------ expressions

isExprNode :: P -> Bool
isExprNode = \case
  PN k _ _ -> k `elem` [NBinaryExpr, NUnaryExpr, NCallExpr, NLiteral, NVarExpr, NArrayExpr, NHashExpr, NParenExpr, NErrorNode]
  PT KError _ _ -> True
  _ -> False

{- | The first expression of a slot; with none, an error of width zero at
the start of the slot @sp@ (golem-parser ADR 0009).
-}
exprOf :: SrcSpan -> [P] -> Located Expr
exprOf _ (p : _) = expr p
exprOf sp [] = Located (mkSpan (spanFile sp) (spanStart sp) (spanStart sp)) EError

expr :: P -> Located Expr
expr p = Located (pspan p) $ case p of
  PN NBinaryExpr _ cs -> case significant cs of
    [a, PT KOperator _ op, b] -> EBinary (binop op) (expr a) (expr b)
    [a] -> locValue (expr a)
    _ -> EError
  PN NUnaryExpr _ cs -> case significant cs of
    [PT KOperator _ _, a] -> EUnary Negate (expr a)
    [a] -> locValue (expr a)
    _ -> EError
  PN NLiteral _ cs -> case significant cs of
    [PT KNumber _ t] -> number t
    [PT KString _ t] -> EString (unquote t)
    [PT KKeyword _ "true"] -> EBool True
    [PT KKeyword _ "false"] -> EBool False
    [PT KKeyword _ "nil"] -> ENil
    _ -> EError
  PN NVarExpr _ cs -> EVar [t | PT KIdent _ t <- cs]
  PN NCallExpr _ cs -> case significant cs of
    (PT KIdent _ f : rest) -> ECall f [expr e | e <- rest, isExprNode e]
    _ -> EError
  PN NArrayExpr _ cs -> EArray [expr e | e <- cs, isExprNode e]
  PN NHashExpr _ cs -> EHash [entry ecs | PN NHashEntry _ ecs <- cs]
  PN NParenExpr _ cs -> locValue (exprOf (pspan p) (filter isExprNode cs))
  _ -> EError
  where
    entry ecs = case significant ecs of
      (k : _ : v : _) -> (keyText k, expr v)
      _ -> ("", Located (pspan p) EError)
    keyText = \case
      PT KString _ t -> unquote t
      PT _ _ t -> t
      PN {} -> ""

binop :: Text -> BinaryOp
binop = \case
  "+" -> Add
  "-" -> Sub
  "*" -> Mul
  "/" -> Div
  "%" -> Mod
  "**" -> Pow
  "==" -> OpEq
  "!=" -> OpNe
  "<" -> OpLt
  "<=" -> OpLe
  ">" -> OpGt
  _ -> OpGe

{- | A word read as a number literal, with a leading - allowed (docs/adr
ADR 0102): the value of @-1@, @1.5@ or @1e3@; Nothing for a word that is
no number.
-}
numberWord :: Text -> Maybe Rational
numberWord w = case T.uncons w of
  Just ('-', rest) -> negate <$> unsigned rest
  _ -> unsigned w
  where
    unsigned t = case number t of
      ENat n -> Just (toRational n)
      ERat q -> Just q
      _ -> Nothing

{- | A number literal (docs/adr ADR 0101): digits are a natural number; a
decimal or an exponent is the exact rational, never rounded. An exponent
over 1300 in absolute value puts the literal past the limit of the
evaluator (2^4096) whatever the digits, so the power of 10 is not made:
the literal is 2^4096 or its reciprocal, which the evaluator reports as
G02086.
-}
number :: Text -> Expr
number t = case T.splitOn "e" t of
  [m] -> mantissa m
  [m, x] -> case (mantissa m, exponentOf x) of
    (_, Nothing) -> EError
    (_, Just k)
      | abs k > 1300 -> ERat (if k > 0 then 2 ^ (4096 :: Int) else 1 % 2 ^ (4096 :: Int))
    (ENat n, Just k) -> ERat (toRational n * 10 ^^ k)
    (ERat q, Just k) -> ERat (q * 10 ^^ k)
    _ -> EError
  _ -> EError
  where
    mantissa m = case T.splitOn "." m of
      [i] | Just n <- digits i -> ENat (fromInteger n)
      [i, f] | Just n <- digits (i <> f) -> ERat (n % 10 ^ T.length f)
      _ -> EError
    digits d
      | not (T.null d) && T.all isDigit d = Just (read (T.unpack d) :: Integer)
      | otherwise = Nothing
    exponentOf x = case T.uncons x of
      Just ('+', d) -> digits d
      Just ('-', d) -> negate <$> digits d
      _ -> digits x
