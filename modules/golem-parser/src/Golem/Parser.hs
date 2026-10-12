{- | The Golem parser (golem-parser ADR 0002): reading, recovering parse,
conversion to the Golem CST, and syntax diagnostics.
-}
module Golem.Parser
  ( parse,
    parseFile,
    parseAst,
    syntaxErrorDiagnostic,
    labelCode,
  )
where

import Data.ByteString (ByteString)
import Data.Text (Text)
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
   in (convert tree, map (syntaxErrorDiagnostic fid) errs)

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
  Just "block" -> ("G0110", "このブロックを解釈できません")
  Just "indent" -> ("G0111", "インデントが不正です（タブ、または 2 の倍数でない空白）")
  Just "heading_level" -> ("G0112", "見出しの階層は 3 までです")
  Just "def_orphan" -> ("G0113", "用語のない =: があります")
  Just "table_delimiter" -> ("G0114", "表の 2 行目は区切りの行でなければなりません")
  Just "table_cells" -> ("G0115", "表のセルの数が見出しの行と一致しません")
  Just "code_close" -> ("G0116", "コードブロックが閉じていません")
  Just "close" -> ("G0117", "閉じ括弧 ] がありません")
  Just "comment_close" -> ("G0118", "コメントが段落の中で閉じていません")
  Just "arg_order" -> ("G0119", "キーワード引数の後に位置引数があります")
  Just "expr" -> ("G0120", "式を解釈できません")
  Just "bracket" -> ("G0121", "[ の後にはコマンド名か = が必要です。本文の [ は \\[ と書きます")
  Just "table_row" -> ("G0123", "表の行は | で始まり | で終わります")
  Just other -> ("G0129", "構文エラー（" <> other <> "）")
  Nothing -> ("G0122", "解釈できない入力が残っています")

syntaxErrorDiagnostic :: FileId -> SyntaxError -> Diagnostic
syntaxErrorDiagnostic fid e =
  let (s, en) = syntaxErrorRange e
      (code, msg) = labelCode (syntaxErrorLabel e)
   in diagnostic code Error (mkSpan fid s en) msg
