-- | TSV and CSV tables, align= and cells= of @table (golem-eval ADR 0004).
module TableSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Parser (parseAst)
import Golem.Parser.SourceSettings
import Golem.Project.Style (defaultStyle, paraLineBreaks)
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

fid :: FileId
fid = FileId 9

-- | A table file, read without errors, as rows; or the code, message and span of the error.
type Parsed = Either (Text, Text, Int, Int) [[Text]]

parsed :: Either Diagnostic [[Text]] -> Parsed
parsed = either (\d -> let DiagnosticCode c = diagCode d in Left (c, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d))) Right

tsv :: Text -> Parsed
tsv = parsed . parseTsv fid

csv :: Text -> Parsed
csv = parsed . parseCsv fid

ctx :: EvalContext
ctx =
  EvalContext
    { ctxFile = FileId 1,
      ctxPath = "ch/01.gm",
      ctxProfile = Dev,
      ctxMeta = Map.empty,
      ctxImports = Map.empty,
      ctxSwatches = Set.empty,
      ctxCharStyles = Set.empty,
      ctxParaStyles = paraLineBreaks defaultStyle,
      ctxDefaultKenten = "sesame",
      ctxCiteKeys = Set.empty,
      ctxAssets =
        Map.fromList
          [ ("x.tsv", AssetText (FileId 5) "a\tb\tc\n1\t2\t3\n"),
            ("x.TSV", AssetText (FileId 6) "a\tb\tc\n1\t2\t3\n"),
            ("x.csv", AssetText (FileId 7) "a,b,c\n1,2,3\n"),
            ("x.txt", AssetText (FileId 8) "a,b,c\n1,2,3\n"),
            ("t.txt", AssetText (FileId 10) "a\tb\tc\n1\t2\t3\n"),
            ("c.tsv", AssetText (FileId 11) "a,b,c\n1,2,3\n"),
            ("empty-cell.tsv", AssetText (FileId 12) "a\tb\n\tx\n"),
            ("empty-cell.csv", AssetText (FileId 13) "a,b\n,x\n"),
            ("ragged.tsv", AssetText (FileId 14) "a\tb\nc\n"),
            ("bad.tsv", AssetTableUnreadable (FileId 15) "a\rb\n")
          ],
      ctxPlugins = noPlugins,
      ctxSource = defaultSourceSettings,
      ctxStyle = defaultStyle
    }

run :: Text -> ([BlockBody], [(Text, Text, Int, Int)])
run src =
  let (file, _, pds) = parseAst (FileId 1) src
      r = evalFile ctx file
   in ( map blockBody (docBlocks (erDocument r)),
        [(c, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- pds <> erDiagnostics r, let DiagnosticCode c = diagCode d]
      )

-- | The cells of the table of a source, without spans, and its alignments.
table :: Text -> Maybe ([Alignment], [[Text]], [[[Text]]])
table src = case run src of
  ([Table al h rs], []) -> Just (al, map texts h, map (map texts) rs)
  _ -> Nothing
  where
    texts = map (\case Text _ t -> t; _ -> "?")

codes :: Text -> [Text]
codes src = [c | (c, _, _, _) <- snd (run src)]

tests :: TestTree
tests = testGroup "tables (golem-eval ADR 0004)" [tsvTests, csvTests, argTests]

tsvTests :: TestTree
tsvTests =
  testGroup
    "TSV"
    [ testCase "tabs and LF" $ do
        tsv "a\tb\nc\td\n" @?= Right [["a", "b"], ["c", "d"]]
        tsv "a\tb\nc\td" @?= Right [["a", "b"], ["c", "d"]],
      testCase "CRLF, and LF and CRLF mixed" $ do
        tsv "a\tb\r\nc\td\r\n" @?= Right [["a", "b"], ["c", "d"]]
        tsv "a\tb\r\nc\td\n" @?= Right [["a", "b"], ["c", "d"]],
      testCase "the header row alone" $ tsv "a\tb\n" @?= Right [["a", "b"]],
      testCase "empty files" $ do
        tsv "" @?= Left ("G0285", "TSV が空です", 0, 0)
        tsv "\n" @?= Left ("G0285", "TSV が空です", 0, 0)
        tsv "\r\n" @?= Left ("G0285", "TSV が空です", 0, 0),
      testCase "a row with another number of cells" $ do
        tsv "a\tb\nc\n" @?= Left ("G0285", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 5)
        tsv "a\tb\r\nc\r\n" @?= Left ("G0285", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 5, 6),
      testCase "the first such row alone" $
        tsv "a\tb\nc\td\te\nf\n" @?= Left ("G0285", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 3）", 4, 9),
      testCase "empty lines are rows of one empty cell" $ do
        tsv "a\tb\n\n" @?= Left ("G0285", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 4)
        tsv "a\n\nb\n" @?= Right [["a"], [""], ["b"]],
      testCase "an empty cell" $ tsv "a\t\tb" @?= Right [["a", "", "b"]],
      testCase "quotes and backslashes are as written" $ do
        tsv "\"a,b\"\t\"c" @?= Right [["\"a,b\"", "\"c"]]
        tsv "C:\\new\tx" @?= Right [["C:\\new", "x"]],
      testCase "spaces around a cell are kept" $ tsv " a \tb" @?= Right [[" a ", "b"]],
      testCase "a lone CR is G0282" $
        tsv "a\rb\tc" @?= Left ("G0282", "単独の CR があります。表のファイルの改行は LF か CRLF に限ります", 1, 2),
      testCase "positions are in bytes" $
        -- 表 is 3 bytes, the combining mark U+3099 is 3 bytes
        tsv "表\tか\x3099\nx\n" @?= Left ("G0285", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 11, 12),
      testCase "a BOM at the start is skipped and counted" $ do
        tsv "\xFEFF\&a\tb\n" @?= Right [["a", "b"]]
        tsv "\xFEFF\&a\tb\nc\n" @?= Left ("G0285", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 7, 8)
    ]

csvTests :: TestTree
csvTests =
  testGroup
    "CSV"
    [ testCase "CRLF and LF" $ do
        csv "a,b\r\nc,d\r\n" @?= Right [["a", "b"], ["c", "d"]]
        csv "a,b\nc,d\n" @?= Right [["a", "b"], ["c", "d"]],
      testCase "CRLF in quotes stays in the cell, as before" $
        csv "\"x\r\ny\",b" @?= Right [["x\ny", "b"]],
      testCase "quoted fields as before" $
        csv "a,b\n1,\"x,y\"\n\"q\"\"r\",s\n" @?= Right [["a", "b"], ["1", "x,y"], ["q\"r", "s"]],
      testCase "a row with another number of cells" $
        csv "a,b\nc\n" @?= Left ("G0285", "CSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 5),
      testCase "a record over lines" $
        csv "a,b\n\"c\nd\"\n" @?= Left ("G0285", "CSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 9),
      testCase "empty files" $ do
        csv "" @?= Left ("G0285", "CSV が空です", 0, 0)
        csv "\n\n" @?= Left ("G0285", "CSV が空です", 0, 0),
      testCase "an unclosed quote is G0283" $
        csv "a,\"b" @?= Left ("G0283", "CSV の引用符が閉じていません", 2, 3),
      testCase "a lone CR is G0282, in quotes or not" $ do
        csv "\"a\rb\"" @?= Left ("G0282", "単独の CR があります。表のファイルの改行は LF か CRLF に限ります", 2, 3)
        csv "a\rb" @?= Left ("G0282", "単独の CR があります。表のファイルの改行は LF か CRLF に限ります", 1, 2),
      testCase "a quote outside quotes is as written" $ csv "a\"b,c" @?= Right [["a\"b", "c"]],
      testCase "empty lines are dropped" $ csv "a,b\n\n1,2\n\n" @?= Right [["a", "b"], ["1", "2"]],
      testCase "a BOM at the start is skipped" $ csv "\xFEFF\&a,b\n" @?= Right [["a", "b"]]
    ]

argTests :: TestTree
argTests =
  testGroup
    "format, align and cells"
    [ testCase "the extension tells TSV" $ do
        fmap cellsOf (table "@table src=x.tsv\n") @?= Just abc
        fmap cellsOf (table "@table src=x.TSV\n") @?= Just abc,
      testCase "anything else is CSV" $ do
        fmap cellsOf (table "@table src=x.csv\n") @?= Just abc
        fmap cellsOf (table "@table src=x.txt\n") @?= Just abc,
      testCase "format= comes first" $ do
        fmap cellsOf (table "@table src=t.txt format=tsv\n") @?= Just abc
        fmap cellsOf (table "@table src=c.tsv format=csv\n") @?= Just abc,
      testCase "G0280" $
        run "@table src=x.csv format=xml\n" @?= ([], [("G0280", "format は csv か tsv です: xml", 17, 27)]),
      testCase "the same CSV and TSV give the same table" $
        fst (run "@table src=x.tsv\n") @?= fst (run "@table src=x.csv\n"),
      testCase "empty cells differ, on purpose" $ do
        case run "@table src=empty-cell.tsv\n" of
          ([Table _ _ [[c, _]]], []) -> c @?= []
          other -> assertFailure (show other)
        case run "@table src=empty-cell.csv\n" of
          ([Table _ _ [[[Text _ ""], _]]], []) -> pure ()
          other -> assertFailure (show other),
      testCase "the default alignment" $
        fmap alignOf (table "@table src=x.tsv\n") @?= Just [AlignDefault, AlignDefault, AlignDefault],
      testCase "align= by column" $ do
        fmap alignOf (table "@table src=x.tsv align=left,center,right\n") @?= Just [AlignLeft, AlignCenter, AlignRight]
        fmap alignOf (table "@table src=x.tsv align=\"left, default ,right\"\n") @?= Just [AlignLeft, AlignDefault, AlignRight],
      testCase "one value for every column" $
        fmap alignOf (table "@table src=x.tsv align=right\n") @?= Just [AlignRight, AlignRight, AlignRight],
      testCase "G0281: the number of values" $
        run "@table src=x.tsv align=left,right\n" @?= ([], [("G0281", "align の値の数が表の列の数と違います（列は 3、align は 2）", 17, 33)]),
      testCase "G0281: values" $ do
        run "@table src=x.tsv align=left,,right\n" @?= ([], [("G0281", "align の値は left、center、right、default のどれかです: left,,right", 17, 34)])
        codes "@table src=x.tsv align=middle\n" @?= ["G0281"]
        codes "@table src=x.tsv align=Left\n" @?= ["G0281"]
        codes "@table src=x.tsv align=[= \"left\"]\n" @?= ["G0281"],
      testCase "cells=text is the default" $
        table "@table src=x.tsv cells=text\n" @?= table "@table src=x.tsv\n",
      testCase "G0284" $ do
        run "@table src=x.tsv cells=markup\n" @?= ([], [("G0284", "cells=markup はまだ実装していません", 17, 29)])
        run "@table src=x.tsv cells=html\n" @?= ([], [("G0284", "cells は text です: html", 17, 27)]),
      testCase "CSV and TSV take the same alignment" $
        fmap alignOf (table "@table src=x.tsv align=left,center,right\n") @?= fmap alignOf (table "@table src=x.csv align=left,center,right\n"),
      testCase "G0285 at the table file" $
        snd (run "@table src=ragged.tsv\n") @?= [("G0285", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 5)],
      testCase "a file that failed the reading stage gives no table and no more diagnostics" $
        run "@table src=bad.tsv\n" @?= ([], [])
    ]
  where
    abc = ([["a"], ["b"], ["c"]], [[["1"], ["2"], ["3"]]])
    cellsOf (_, h, rs) = (h, rs)
    alignOf (al, _, _) = al
