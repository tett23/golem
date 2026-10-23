-- | TSV and CSV tables, align= and cells= of @table (golem-eval ADR 0004).
module TableSpec (tests) where

import Control.Exception (evaluate)
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import GHC.Stats (RTSStats (..), getRTSStats, getRTSStatsEnabled)
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Parser (parseAst)
import Golem.Parser.SourceSettings
import Golem.Project.Style (defaultStyle, paraLineBreaks)
import Golem.Syntax
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.Mem (performGC)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

fid :: FileId
fid = FileId 9

-- | A table file, read without errors, as rows; or the code, message and span of the error.
type Parsed = Either (Text, Text, Int, Int) [[Text]]

parsed :: Either TableError [[Text]] -> Parsed
parsed = either (\e -> let d = tableDiagnostic (mkSpan (FileId 1) 0 0) "t" e; DiagnosticCode c = diagCode d in Left (c, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d))) Right

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
            ("bad.tsv", AssetTableUnreadable (FileId 15) "a\rb\n"),
            -- the limits of a table file (docs/adr ADR 0043)
            ("max-bytes.tsv", AssetText (FileId 16) (T.replicate tableMaxBytes "a")),
            ("over-bytes.tsv", AssetText (FileId 17) (T.replicate tableMaxBytes "a" <> "\n")),
            ("max-rows.tsv", AssetText (FileId 18) (T.unlines (replicate tableMaxRows "a"))),
            ("over-rows.tsv", AssetText (FileId 19) (T.unlines (replicate (tableMaxRows + 1) "a"))),
            ("max-cells.csv", AssetText (FileId 20) (T.intercalate "," (replicate tableMaxCells "a") <> "\n")),
            ("over-cells.csv", AssetText (FileId 21) (T.intercalate "," (replicate (tableMaxCells + 1) "a") <> "\n")),
            ("too-large.csv", AssetTableTooLarge 16777217 Nothing)
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
tests = testGroup "tables (golem-eval ADR 0004)" [tsvTests, csvTests, argTests, roundTrips, limitTests, allocationTests]

{- | Rows of the same number of cells, at least @minCols@, the first cell not empty (an empty
file is G02085), from characters that a table file treats in different ways.
-}
genGrid :: Int -> [Char] -> Gen [[Text]]
genGrid minCols cs = do
  cols <- Gen.int (Range.linear minCols 4)
  rows <- Gen.int (Range.linear 1 5)
  let cell = T.pack <$> Gen.string (Range.linear 0 6) (Gen.element cs)
  first <- T.pack <$> Gen.string (Range.linear 1 6) (Gen.element cs)
  header <- (first :) <$> Gen.list (Range.singleton (cols - 1)) cell
  (header :) <$> Gen.list (Range.singleton (rows - 1)) (Gen.list (Range.singleton cols) cell)

-- | LF or CRLF, chosen for each line.
genEol :: Gen Text
genEol = Gen.element ["\n", "\r\n"]

{- | The lines joined with LF or CRLF, and at times without one after the
last line. An empty last line keeps its end, without which it is no line.
-}
genFile :: [Text] -> Gen Text
genFile ls = do
  es <- Gen.list (Range.singleton (length ls)) genEol
  lastEol <- Gen.element [True, False]
  let es' = if lastEol || maybe True T.null (lastMay ls) then es else take (length ls - 1) es <> [""]
  pure (T.concat (zipWith (<>) ls es'))
  where
    lastMay = foldl (const Just) Nothing

-- | A CSV field, quoted when it has a comma, a quote or a line feed.
csvField :: Text -> Text
csvField t
  | T.any (`elem` (",\"\n" :: String)) t = "\"" <> T.replace "\"" "\"\"" t <> "\""
  | otherwise = t

roundTrips :: TestTree
roundTrips =
  testGroup
    "written and read back"
    [ testProperty "a TSV written with tabs and LF or CRLF, the last one optional, reads back as its rows" $ property $ do
        -- no tab, CR or LF in a cell; quotes, commas, backslashes and spaces are as written
        g <- forAll (genGrid 1 "a 表\"\\,")
        file <- forAll (genFile (map (T.intercalate "\t") g))
        tsv file === Right g,
      testProperty "a CSV written with quotes where needed, the last line end optional, reads back as its rows" $ property $ do
        -- two columns at least, so that no row is an empty line, which CSV drops
        g <- forAll (genGrid 2 "a 表\",\n\t")
        file <- forAll (genFile (map (T.intercalate "," . map csvField) g))
        csv file === Right g
    ]

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
        tsv "" @?= Left ("G02085", "TSV が空です", 0, 0)
        tsv "\n" @?= Left ("G02085", "TSV が空です", 0, 0)
        tsv "\r\n" @?= Left ("G02085", "TSV が空です", 0, 0),
      testCase "a row with another number of cells" $ do
        tsv "a\tb\nc\n" @?= Left ("G02085", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 5)
        tsv "a\tb\r\nc\r\n" @?= Left ("G02085", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 5, 6),
      testCase "the first such row alone" $
        tsv "a\tb\nc\td\te\nf\n" @?= Left ("G02085", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 3）", 4, 9),
      testCase "empty lines are rows of one empty cell" $ do
        tsv "a\tb\n\n" @?= Left ("G02085", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 4)
        tsv "a\n\nb\n" @?= Right [["a"], [""], ["b"]],
      testCase "an empty cell" $ tsv "a\t\tb" @?= Right [["a", "", "b"]],
      testCase "quotes and backslashes are as written" $ do
        tsv "\"a,b\"\t\"c" @?= Right [["\"a,b\"", "\"c"]]
        tsv "C:\\new\tx" @?= Right [["C:\\new", "x"]],
      testCase "spaces around a cell are kept" $ tsv " a \tb" @?= Right [[" a ", "b"]],
      testCase "a lone CR is G02082" $
        tsv "a\rb\tc" @?= Left ("G02082", "単独の CR があります。表のファイルの改行は LF か CRLF に限ります", 1, 2),
      testCase "positions are in bytes" $
        -- 表 is 3 bytes, the combining mark U+3099 is 3 bytes
        tsv "表\tか\x3099\nx\n" @?= Left ("G02085", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 11, 12),
      testCase "a BOM at the start is skipped and counted" $ do
        tsv "\xFEFF\&a\tb\n" @?= Right [["a", "b"]]
        tsv "\xFEFF\&a\tb\nc\n" @?= Left ("G02085", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 7, 8)
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
        csv "a,b\nc\n" @?= Left ("G02085", "CSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 5),
      testCase "a record over lines" $
        csv "a,b\n\"c\nd\"\n" @?= Left ("G02085", "CSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 9),
      testCase "empty files" $ do
        csv "" @?= Left ("G02085", "CSV が空です", 0, 0)
        csv "\n\n" @?= Left ("G02085", "CSV が空です", 0, 0),
      testCase "an unclosed quote is G02083" $
        csv "a,\"b" @?= Left ("G02083", "CSV の引用符が閉じていません", 2, 3),
      testCase "a lone CR is G02082, in quotes or not" $ do
        csv "\"a\rb\"" @?= Left ("G02082", "単独の CR があります。表のファイルの改行は LF か CRLF に限ります", 2, 3)
        csv "a\rb" @?= Left ("G02082", "単独の CR があります。表のファイルの改行は LF か CRLF に限ります", 1, 2),
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
      testCase "G02080" $
        run "@table src=x.csv format=xml\n" @?= ([], [("G02080", "format は csv か tsv です: xml", 17, 27)]),
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
      testCase "G02081: the number of values" $
        run "@table src=x.tsv align=left,right\n" @?= ([], [("G02081", "align の値の数が表の列の数と違います（列は 3、align は 2）", 17, 33)]),
      testCase "G02081: values" $ do
        run "@table src=x.tsv align=left,,right\n" @?= ([], [("G02081", "align の値は left、center、right、default のどれかです: left,,right", 17, 34)])
        codes "@table src=x.tsv align=middle\n" @?= ["G02081"]
        codes "@table src=x.tsv align=Left\n" @?= ["G02081"]
        codes "@table src=x.tsv align=[= \"left\"]\n" @?= ["G02081"],
      testCase "cells=text is the default" $
        table "@table src=x.tsv cells=text\n" @?= table "@table src=x.tsv\n",
      testCase "G02084" $ do
        run "@table src=x.tsv cells=markup\n" @?= ([], [("G02084", "cells=markup はまだ実装していません", 17, 29)])
        run "@table src=x.tsv cells=html\n" @?= ([], [("G02084", "cells は text です: html", 17, 27)]),
      testCase "CSV and TSV take the same alignment" $
        fmap alignOf (table "@table src=x.tsv align=left,center,right\n") @?= fmap alignOf (table "@table src=x.csv align=left,center,right\n"),
      testCase "G02085 at the table file" $
        snd (run "@table src=ragged.tsv\n") @?= [("G02085", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 5)],
      testCase "a file that failed the reading stage gives no table and no more diagnostics" $
        run "@table src=bad.tsv\n" @?= ([], [])
    ]
  where
    abc = ([["a"], ["b"], ["c"]], [[["1"], ["2"], ["3"]]])
    cellsOf (_, h, rs) = (h, rs)
    alignOf (al, _, _) = al

-- | The limits of a table file, G02088 (docs/adr ADR 0043).
limitTests :: TestTree
limitTests =
  testGroup
    "the limits of a table file (docs/adr ADR 0043)"
    [ testCase "the limits" $ (tableMaxBytes, tableMaxRows, tableMaxCells) @?= (16777216, 10000, 256),
      testCase "16 MiB is read, and one byte more is G02088 at @table" $ do
        fmap (\(_, h, rs) -> (length h, length rs)) (table "@table src=max-bytes.tsv\n") @?= Just (1, 0)
        run "@table src=over-bytes.tsv\n" @?= ([], [("G02088", "表のファイルが大きさの上限を超えます: over-bytes.tsv（16777217 バイト、上限は 16777216 バイト）", 0, 26)]),
      testCase "a file the driver did not read for its size is G02088" $
        run "@table src=too-large.csv\n" @?= ([], [("G02088", "表のファイルが大きさの上限を超えます: too-large.csv（16777217 バイト、上限は 16777216 バイト）", 0, 25)]),
      testCase "10,000 rows are read, and 10,001 are G02088" $ do
        fmap (\(_, h, rs) -> (length h, length rs)) (table "@table src=max-rows.tsv\n") @?= Just (1, 9999)
        run "@table src=over-rows.tsv\n" @?= ([], [("G02088", "表のファイルが行の数の上限を超えます: over-rows.tsv（10001 行目、上限は 10000 行）", 0, 25)]),
      testCase "256 cells are read, and 257 are G02088" $ do
        fmap (\(_, h, _) -> length h) (table "@table src=max-cells.csv\n") @?= Just 256
        run "@table src=over-cells.csv\n" @?= ([], [("G02088", "表のファイルがセルの数の上限を超えます: over-cells.csv（1 行目、上限は 1 行に 256 個）", 0, 26)]),
      testCase "the rows and cells are counted as the file is read, and the rest is not" $ do
        -- a G02085 or G02083 after the row over the limit is not reached
        tsv (T.unlines (replicate (tableMaxRows + 1) "a") <> "a\tb\n") @?= Left ("G02088", "表のファイルが行の数の上限を超えます: t（10001 行目、上限は 10000 行）", 0, 0)
        csv (T.intercalate "," (replicate (tableMaxCells + 1) "a") <> ",\"x\n") @?= Left ("G02088", "表のファイルがセルの数の上限を超えます: t（1 行目、上限は 1 行に 256 個）", 0, 0)
        -- a G02085 before it is
        tsv ("a\tb\n" <> T.unlines (replicate tableMaxRows "a")) @?= Left ("G02085", "TSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 5),
      testCase "the empty lines a CSV drops are not rows" $
        fmap length (csv (T.unlines (replicate tableMaxRows "a,b") <> "\n\n")) @?= Right tableMaxRows,
      testCase "a table of 10,000 rows of a CSV, as a cell over lines" $
        fmap length (csv (T.concat (replicate tableMaxRows "\"a\r\nb\",c\r\n"))) @?= Right tableMaxRows
    ]

{- | The reading of a table allocates at most 16 times the size of the file
(docs/adr ADR 0043), measured by GHC.Stats (the test suite runs with +RTS -T).
-}
allocationTests :: TestTree
allocationTests =
  testGroup
    "the memory of reading a table (docs/adr ADR 0043)"
    [ testCase "a CSV of 1 MiB allocates at most 16 MiB" $ do
        let row = T.intercalate "," ["\"東京都, 千代田区\"", "12345", "2026-10-19", "a short note", "\"q\"\"r\""] <> "\r\n"
            n = (2 ^ (20 :: Int)) `div` utf8Len row
            file = T.concat (replicate n row)
        _ <- evaluate (T.length file)
        bytes <- allocated (either (const 0) (sum . map (sum . map T.length)) (parseCsv fid file))
        assertBool ("allocated " <> show bytes <> " bytes for " <> show (utf8Len file)) (bytes <= 16 * fromIntegral (utf8Len file)),
      testCase "a TSV of 1 MiB allocates at most 16 MiB" $ do
        let row = T.intercalate "\t" ["東京都千代田区", "12345", "2026-10-19", "a short note", "q\"r"] <> "\n"
            n = (2 ^ (20 :: Int)) `div` utf8Len row
            file = T.concat (replicate n row)
        _ <- evaluate (T.length file)
        bytes <- allocated (either (const 0) (sum . map (sum . map T.length)) (parseTsv fid file))
        assertBool ("allocated " <> show bytes <> " bytes for " <> show (utf8Len file)) (bytes <= 16 * fromIntegral (utf8Len file))
    ]
  where
    utf8Len = BS.length . TE.encodeUtf8
    allocated x = do
      enabled <- getRTSStatsEnabled
      unless enabled (assertFailure "run with +RTS -T")
      performGC
      start <- allocated_bytes <$> getRTSStats
      _ <- evaluate x
      performGC
      end <- allocated_bytes <$> getRTSStats
      pure (end - start)
