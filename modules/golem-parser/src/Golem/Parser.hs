{- | The Golem parser (golem-parser ADR 0002): reading, recovering parse,
conversion to the Golem CST, and syntax diagnostics.
-}
module Golem.Parser
  ( parse,
    parseFile,
    parseAst,
    commentBoundaryInfos,
    labelCode,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (sortOn)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Parser.AST (File)
import Golem.Parser.CST
import Golem.Parser.Convert (convert)
import Golem.Parser.Generated qualified as G
import Golem.Parser.Lower (lower)
import Golem.Parser.Read (readSource)
import Golem.Syntax
import Peg.Runtime (SyntaxError (..))

-- | Total and lossless: @render (fst (parse f t)) == t@ for every input.
parse :: FileId -> Text -> (Node, [Diagnostic])
parse fid src =
  let (tree, errs) = G.parseSyntaxRecover src
      cst = convert tree
      recovered = recoverExpressionComments fid cst
      extra = commentDiagnostics fid cst <> recovered
      unclosedAt p =
        any
          ( \x ->
              spanEnd (posSpan x) == p && case posText x of
                Just t | posKind x == KComment -> not ("%%" `T.isInfixOf` T.drop 2 t)
                Just t | posKind x == KProofComment -> not ("%%" `T.isInfixOf` T.drop 3 t)
                _ -> False
          )
          (withPositions fid cst)
      covered d =
        ( diagCode d `elem` [DiagnosticCode "G01018", DiagnosticCode "G01017"]
            && unclosedAt (spanStart (diagSpan d))
            && any (\e -> diagCode e `elem` [DiagnosticCode "G01018", DiagnosticCode "G01101"] && spanEnd (diagSpan e) == spanStart (diagSpan d) && spanLength (diagSpan e) > 0) extra
        )
          || ( diagCode d `elem` [DiagnosticCode "G01010", DiagnosticCode "G01017", DiagnosticCode "G01020"]
                 && any (spanContains (diagSpan d) . diagSpan) recovered
             )
   in (cst, sortOn (spanStart . diagSpan) (filter (not . covered) (map (syntaxErrorDiagnostic fid) errs) <> extra))

-- Diagnostics whose spans and suggested edits depend on the lossless tokens.
commentDiagnostics :: FileId -> Node -> [Diagnostic]
commentDiagnostics fid = walk False 0
  where
    walk inExpr start n =
      let k = nodeKind n
          expr = inExpr || k == NExpr || (k == NBlockCommand && any isSet (nodeChildren n))
          context
            | expr = Just "式"
            | k `elem` [NInlineCommand, NBlockCommand, NCodeBlock] = Just "引数列"
            | otherwise = Nothing
          children = snd (foldl' (step expr context) (start, []) (nodeChildren n))
          wordsHere = case k of
            NArgument -> wordValues start (nodeChildren n)
            NKeywordArgument -> drop 1 (wordValues start (nodeChildren n))
            _ -> []
       in mapMaybe quoteDiagnostic wordsHere <> children
    step expr context (offset, ds) e =
      let ds' = case e of
            ElemNode n -> walk expr offset n
            ElemToken t
              | tokKind t == KProofComment,
                Just whereAt <- context ->
                  [diagnostic "G01101" Error (mkSpan fid offset (offset + elementWidth e)) (whereAt <> "では校正コメントを使えません")]
              | tokKind t == KComment,
                Just whereAt <- context,
                not ("%%" `T.isInfixOf` T.drop 2 (tokText t)) ->
                  [diagnostic "G01018" Error (mkSpan fid offset (offset + elementWidth e)) (whereAt <> "のコメントが閉じていません")]
            _ -> []
       in (offset + elementWidth e, ds <> ds')
    wordValues start = snd . foldl' stepWord (start, [])
    stepWord (offset, ws) e =
      let ws' = case e of
            ElemToken (Token KWord t) -> [(offset, t)]
            _ -> []
       in (offset + elementWidth e, ws <> ws')
    quoteDiagnostic (start, value)
      | "%%" `T.isInfixOf` value =
          let full = mkSpan fid start (start + BS.length (TE.encodeUtf8 value))
           in Just
                ( (diagnostic "G01102" Error full "引用符なしの値に %% が含まれています。値全体を引用符で囲みます")
                    { diagFixes = [Fix "値を引用符で囲む" [(full, "\"" <> value <> "\"")] | not (T.any (`elem` ['\n', '"']) value)]
                    }
                )
      | otherwise = Nothing
    isSet (ElemToken (Token KIdent "set")) = True
    isSet _ = False

-- An operator before an unclosed expression comment may make PEG backtrack
-- to a shorter expression. Recover its comment from the retained error token.
recoverExpressionComments :: FileId -> Node -> [Diagnostic]
recoverExpressionComments fid = walk False 0
  where
    walk inExpr start n = snd (foldl' step (start, []) (nodeChildren n))
      where
        step (offset, ds) e =
          let found = case e of
                ElemNode m -> walk (inExpr || nodeKind m == NExpr) offset m
                ElemToken (Token KError t)
                  | inExpr || isSetLine t ->
                      let (prefix, body) = if inExpr then ("", t) else let (p, v) = T.breakOn "=" t in (p <> "=", T.drop 1 v)
                       in case unclosedMarker body of
                            Just (before, proof) ->
                              let from = offset + BS.length (TE.encodeUtf8 (prefix <> before))
                                  sp = mkSpan fid from (offset + elementWidth e)
                                  code = if proof then "G01101" else "G01018"
                                  msg = if proof then "式では校正コメントを使えません" else "式のコメントが閉じていません"
                               in [diagnostic code Error sp msg]
                            Nothing -> []
                _ -> []
           in (offset + elementWidth e, ds <> found)
    unclosedMarker = scan "" False
      where
        scan before quoted rest = case T.uncons rest of
          Nothing -> Nothing
          Just ('\\', tailText) | quoted -> case T.uncons tailText of
            Just (c, xs) -> scan (before <> "\\" <> T.singleton c) quoted xs
            Nothing -> Nothing
          Just ('"', xs) -> scan (before <> "\"") (not quoted) xs
          Just ('%', xs)
            | not quoted,
              Just ('%', after) <- T.uncons xs ->
                let proof = "=" `T.isPrefixOf` after
                    content = if proof then T.drop 1 after else after
                 in if "%%" `T.isInfixOf` content
                      then let (_, suffix) = T.breakOn "%%" content in scan (before <> "%%" <> (if proof then "=" else "") <> T.take (T.length content - T.length suffix) content <> "%%") False (T.drop 2 suffix)
                      else Just (before, proof)
          Just (c, xs) -> scan (before <> T.singleton c) quoted xs
    isSetLine t =
      let line = T.dropWhile (`elem` [' ', '\t']) t
       in "@set " `T.isPrefixOf` line || "@set\t" `T.isPrefixOf` line

-- | Parse and lower to the AST in one step.
parseAst :: FileId -> Text -> (File, Node, [Diagnostic])
parseAst fid src =
  let (cst, ds) = parse fid src
   in (lower fid cst, cst, ds)

-- | Reading stage followed by 'parse'.
parseFile :: FileId -> ByteString -> Either [Diagnostic] (Node, [Diagnostic])
parseFile fid bs = parse fid <$> readSource fid bs

{- | Label to diagnostic code and message. Every label of the grammar is
listed here; the test suite checks both directions.
-}
labelCode :: Maybe Text -> (Text, Text)
labelCode = \case
  Just "block" -> ("G01010", "このブロックを解釈できません")
  Just "indent" -> ("G01011", "インデントが不正です（タブ、またはブロックの深さより多い空白）")
  Just "heading_level" -> ("G01012", "見出しの階層は 6 までです")
  Just "def_orphan" -> ("G01013", "用語のない =: があります")
  Just "table_delimiter" -> ("G01014", "表の 2 行目は区切りの行でなければなりません")
  Just "table_cells" -> ("G01015", "表のセルの数が見出しの行と一致しません")
  Just "code_close" -> ("G01016", "コードブロックが閉じていません")
  Just "close" -> ("G01017", "ここに閉じ括弧 ] が必要です")
  Just "comment_close" -> ("G01018", "コメントが段落の中で閉じていません")
  Just "arg_order" -> ("G01019", "位置引数と *[...] は、key=value と **[...] より前に書きます")
  Just "expr" -> ("G01020", "式を解釈できません")
  Just "bracket" -> ("G01021", "[ の後にはコマンド名か = が必要です。本文の [ は \\[ と書きます")
  Just "table_row" -> ("G01023", "表の行は | で始まり | で終わります")
  Just "hard_break" -> ("G01024", "行末の \\ は段落の中の強制改行です。次の行に段落の続きが要ります。本文の \\ は \\\\ と書きます")
  Just "reserved" -> ("G01100", "予約された記法です。今のバージョンでは使えません")
  Just "range_end" -> ("G02110", "範囲の端には数を書きます")
  Just other -> ("G01029", "構文エラー（" <> other <> "）")
  Nothing -> ("G01022", "解釈できない入力が残っています")

syntaxErrorDiagnostic :: FileId -> SyntaxError -> Diagnostic
syntaxErrorDiagnostic fid e =
  let (s, en) = syntaxErrorRange e
      (code, msg) = labelCode (syntaxErrorLabel e)
   in diagnostic code Error (mkSpan fid s en) msg

-- | Each missing separator at a comment boundary is one lint info.
commentBoundaryInfos :: FileId -> Node -> [Diagnostic]
commentBoundaryInfos fid = go 0
  where
    go start n =
      let cs = childrenAt start (nodeChildren n)
          nested = concat [go offset m | (offset, ElemNode m) <- cs]
          eligible = nodeKind n `elem` [NInlineCommand, NBlockCommand, NCodeBlock, NExpr, NRangeExpr, NBinaryExpr, NUnaryExpr, NCallExpr, NVarExpr, NArrayExpr, NHashExpr, NHashEntry, NParenExpr]
          missing = if eligible then mapMaybe boundary (zip cs (drop 1 cs)) else []
       in missing <> nested
    childrenAt start = snd . foldl' (\(offset, xs) e -> (offset + elementWidth e, xs <> [(offset, e)])) (start, [])
    boundary ((_, a), (offset, b))
      | let left = edgeLast a,
        let right = edgeFirst b,
        left == Just KComment || right == Just KComment,
        left `notElem` map Just [KWhitespace, KExprOpen, KLParen, KLBracket, KLBrace],
        right `notElem` map Just [KWhitespace, KRBracket, KRParen, KRBrace, KColon, KNewline],
        elementWidth a > 0,
        elementWidth b > 0 =
          let sp = mkSpan fid offset offset
           in Just ((infoDiagnostic "G05100" sp "コメントとの間に半角スペースを入れます") {diagFixes = [Fix "半角スペースを入れる" [(sp, " ")]]})
      | otherwise = Nothing
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
