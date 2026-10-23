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
  Just "block" -> ("G01010", "このブロックを解釈できません")
  Just "indent" -> ("G01011", "インデントが不正です（タブ、またはブロックの深さより多い空白）")
  Just "heading_level" -> ("G01012", "見出しの階層は 3 までです")
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
  Just other -> ("G01029", "構文エラー（" <> other <> "）")
  Nothing -> ("G01022", "解釈できない入力が残っています")

syntaxErrorDiagnostic :: FileId -> SyntaxError -> Diagnostic
syntaxErrorDiagnostic fid e =
  let (s, en) = syntaxErrorRange e
      (code, msg) = labelCode (syntaxErrorLabel e)
   in diagnostic code Error (mkSpan fid s en) msg
