-- | Reading CSV and TSV files for @table, and where their errors point (golem-eval ADR 0004).
module TableFilesSpec (tableFileTests) where

import Control.Exception (evaluate)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Doc.IR
import Golem.Driver
import Golem.Eval.File (EvalResult (..))
import Golem.Project (Project (..), SourceFile (..))
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Mem (getAllocationCounter, setAllocationCounter)
import Test.Tasty
import Test.Tasty.HUnit

manifestOf :: [FilePath] -> BS.ByteString
manifestOf chapters = TE.encodeUtf8 (manifestToml testManifest {tmChapters = map T.pack chapters})

-- | A project of the given files, chapters first, with a style.toml.
withTables :: [(FilePath, BS.ByteString)] -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withTables chapters files act = withSystemTempDirectory "golem-tables" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (manifestOf (map fst chapters))
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  writeFiles tmp (chapters <> files)
  act tmp

check :: FilePath -> IO BuildResult
check tmp = build (defaultOptions tmp) {optCheckOnly = True, optTargets = Just [TargetHtml]}

-- | The blocks of each chapter, by path.
blocksOf :: FilePath -> IO (Map.Map FilePath [BlockBody])
blocksOf tmp = do
  e <- evaluateProject Dev tmp >>= either (const (assertFailure "the project does not load")) pure
  pure (Map.fromList [(sfPath sf, maybe [] (map blockBody . docBlocks . erDocument) (Map.lookup fid (evResults e))) | (fid, sf) <- Map.toList (projectSources (evProject e))])

oneTable :: FilePath -> BS.ByteString -> IO [BlockBody]
oneTable path bytes = withTables [("a.gm", TE.encodeUtf8 ("@table " <> T.pack path <> "\n"))] [(path, bytes)] $ \tmp -> do
  r <- check tmp
  codesOf (brDiagnostics r) @?= []
  Map.findWithDefault [] "a.gm" <$> blocksOf tmp

headerTexts :: [BlockBody] -> [[Text]]
headerTexts bs = [[t | Text _ t <- c] | Table _ h _ <- bs, c <- h]

tableFileTests :: TestTree
tableFileTests =
  testGroup
    "table files (golem-eval ADR 0004)"
    [ -- docs/adr/0184
      testCase "assetRefs collects the path of @table as the first argument, and as src=" $
        withTables [("a.gm", "@table data/t.csv\n\n@table src=data/u.csv\n")] [("data/t.csv", "a\n"), ("data/u.csv", "a\n")] $ \tmp -> do
          e <- evaluateProject Dev tmp >>= either (const (assertFailure "the project does not load")) pure
          [r | sf <- Map.elems (projectSources (evProject e)), sfPath sf == "a.gm", r <- assetRefs (sfAst sf)]
            @?= [("data/t.csv", UseTable), ("data/u.csv", UseTable)],
      testCase "a BOM at the start of a TSV or a CSV is skipped" $ do
        withBom <- oneTable "data/x.tsv" "\xEF\xBB\xBF\&a\tb\n1\t2\n"
        without <- oneTable "data/x.tsv" "a\tb\n1\t2\n"
        withBom @?= without
        headerTexts withBom @?= [["a"], ["b"]]
        csvBom <- oneTable "data/x.csv" "\xEF\xBB\xBF\&a,b\n1,2\n"
        headerTexts csvBom @?= [["a"], ["b"]],
      testCase "G02085 after a BOM counts its bytes" $
        withTables [("a.gm", "@table data/x.tsv\n")] [("data/x.tsv", "\xEF\xBB\xBF\&a\tb\nc\n")] $ \tmp -> do
          r <- check tmp
          [(c, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- brDiagnostics r, let { DiagnosticCode c = diagCode d }] @?= [("G02085", 7, 8)],
      testCase "a BOM at the start of a source file is still G01002" $
        withTables [("a.gm", "\xEF\xBB\xBF\&x\n")] [] $ \tmp -> do
          r <- check tmp
          codesOf (brDiagnostics r) @?= ["G01002"],
      testCase "U+FEFF elsewhere stays in the cell" $ do
        bs <- oneTable "data/x.tsv" "a\tb\xEF\xBB\xBF\n1\t2\n"
        headerTexts bs @?= [["a"], ["b\xFEFF"]],
      testCase "CRLF TSV and CSV are tables" $ do
        t <- oneTable "data/x.tsv" "a\tb\r\n1\t2\r\n"
        c <- oneTable "data/x.csv" "a,b\r\n1,2\r\n"
        headerTexts t @?= [["a"], ["b"]]
        headerTexts c @?= [["a"], ["b"]],
      testCase "a lone CR is G02082, not G01003" $
        forM_ ["data/x.tsv", "data/x.csv"] $ \p ->
          withTables [("a.gm", TE.encodeUtf8 ("@table " <> T.pack p <> "\n"))] [(p, "a\rb\n")] $ \tmp -> do
            r <- check tmp
            codesOf (brDiagnostics r) @?= ["G02082"],
      testCase "Shift_JIS is G01001" $
        forM_ ["data/x.tsv", "data/x.csv"] $ \p ->
          withTables [("a.gm", TE.encodeUtf8 ("@table " <> T.pack p <> "\n"))] [(p, "\x95\x5C\n")] $ \tmp -> do
            r <- check tmp
            codesOf (brDiagnostics r) @?= ["G01001"],
      testCase "the table file is shown in human and JSON output" $
        withTables [("a.gm", "@table data/x.tsv\n\n@table data/x.csv\n")] [("data/x.tsv", "a\tb\nc\n"), ("data/x.csv", "a,b\nc\n")] $ \tmp -> do
          r <- check tmp
          let human = renderHuman (brSources r) (brDiagnostics r)
              json = renderJson (brSources r) (brDiagnostics r)
          assertBool (T.unpack human) ("data/x.tsv:2:1: error[G02085]" `T.isInfixOf` human)
          assertBool (T.unpack human) ("data/x.csv:2:1: error[G02085]" `T.isInfixOf` human)
          assertBool (T.unpack json) ("\"data/x.tsv\"" `T.isInfixOf` json && "\"data/x.csv\"" `T.isInfixOf` json),
      testCase "a file referred to twice gives its reading error once" $
        withTables [("a.gm", "@table data/x.tsv\n\n@table data/x.tsv\n")] [("data/x.tsv", "a\rb\n")] $ \tmp -> do
          r <- check tmp
          codesOf (brDiagnostics r) @?= ["G02082"],
      testCase "FileIds do not depend on the order the files were made" $ do
        let files = [("data/b.tsv", "a\tb\nc\n"), ("data/a.csv", "a,b\nc\n"), ("src/x.hs", "x\n")]
            src = "@table data/b.tsv\n\n@table data/a.csv\n\n@listing src/x.hs\n"
            spans fs = withTables [("a.gm", src)] fs $ \tmp -> do
              r <- check tmp
              pure (sort [(siPath si, fid) | (fid, si) <- Map.toList (brSources r)], sort (map diagSpan (brDiagnostics r)))
        a <- spans files
        b <- spans (reverse files)
        a @?= b,
      testCase "a table file that fails to be read makes no table; the other chapters are evaluated" $
        withTables [("a.gm", "@table data/x.tsv\n"), ("b.gm", TE.encodeUtf8 "本文。\n")] [("data/x.tsv", "a\rb\n")] $ \tmp -> do
          r <- check tmp
          codesOf (brDiagnostics r) @?= ["G02082"]
          byPath <- blocksOf tmp
          Map.lookup "a.gm" byPath @?= Just []
          fmap length (Map.lookup "b.gm" byPath) @?= Just 1,
      testCase "@listing of a table file reads it as before, BOM included" $
        withTables [("a.gm", "@table data/x.csv\n\n@listing data/x.csv\n")] [("data/x.csv", "\xEF\xBB\xBF\&a,b\n1,2\n")] $ \tmp -> do
          r <- check tmp
          codesOf (brDiagnostics r) @?= []
          bs <- Map.findWithDefault [] "a.gm" <$> blocksOf tmp
          [codeText c | CodeBlock c <- bs] @?= ["\xFEFF\&a,b\n1,2"],
      testCase "align=right reaches HTML, and the PDF sets it as a | table with ---:" $ do
        written <- withTables [("a.gm", "@table data/x.csv align=right\n")] [("data/x.csv", TE.encodeUtf8 "項目,値\n幅,10\n")] $ \tmp -> do
          r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
          mapM (fmap TE.decodeUtf8 . BS.readFile) (filter (".xhtml" `isSuffixOf`) (brWritten r))
        assertBool "align-right" (any ("class=\"align-right\"" `T.isInfixOf`) written)
        fromCsv <- miniPdf fakeProvider True horizontalStyle "@table data.csv align=right\n" [("data.csv", TE.encodeUtf8 "項目,値\n幅,10\n")] >>= fmap BS.concat . inflateAll
        fromBars <- miniPdf fakeProvider True horizontalStyle "| 項目 | 値 |\n|---:|---:|\n| 幅 | 10 |\n" [] >>= fmap BS.concat . inflateAll
        sort (drawnGlyphs fromCsv) @?= sort (drawnGlyphs fromBars),
      -- the time-out detects a build that does not stop (docs/adr ADR 0073)
      localOption (mkTimeout 30000000) $
        testCase "a large table is G02088, and the text build ends (docs/adr ADR 0043)" $
          withTables [("a.gm", "@table data/big.tsv\n")] [("data/big.tsv", BS.concat (replicate 200000 "a\tb\tc\n"))] $ \tmp -> do
            r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
            [(c, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- brDiagnostics r, let DiagnosticCode c = diagCode d]
              @?= [("G02088", "表のファイルが行の数の上限を超えます: data/big.tsv（10001 行目、上限は 10000 行）", 0, 20)],
      testCase "a table file over 16 MiB is G02088 and is not read (docs/adr ADR 0043)" $
        -- bytes that are not UTF-8 would be G01001 if the file were read
        withTables [("a.gm", "@table data/big.csv\n")] [("data/big.csv", BS.replicate (2 ^ (24 :: Int)) 0x61 <> "\xFF")] $ \tmp -> do
          r <- check tmp
          [(c, diagMessage d) | d <- brDiagnostics r, let DiagnosticCode c = diagCode d]
            @?= [("G02088", "表のファイルが大きさの上限を超えます: data/big.csv（16777217 バイト、上限は 16777216 バイト）")],
      testCase "a table file of 16 MiB is read" $
        withTables [("a.gm", "@table data/big.csv\n")] [("data/big.csv", BS.replicate (2 ^ (24 :: Int) - 1) 0x61 <> "\n")] $ \tmp -> do
          r <- check tmp
          codesOf (brDiagnostics r) @?= [],
      cellLimitTests
    ]

{- | The limit of the cells of a table set in PDF (docs/adr/0224): N =
100,000 cells a table, counted before any cell is composed, whatever the
source of the table.
-}
cellLimitTests :: TestTree
cellLimitTests =
  testGroup
    "the cells of a table set in PDF (docs/adr/0224)"
    [ -- the time-out detects a table composed before it is refused (docs/adr ADR 0073)
      localOption (mkTimeout 30000000) $
        testCase "T1, T2: a table of 10,000 rows of 256 cells is G07108 alone, without composing its cells" $ do
          -- the security audit of 2026-11-08, T-01: 57 s and 96 GB before G07041.
          -- Not in parallel, so that the allocation counter of this thread
          -- counts all the work. Reading and evaluating the table alone
          -- allocates more than 1 GiB (1.3 GB for golem check, 4.6 GB for
          -- this build on macOS aarch64), so the bound is 8 GiB, a twelfth
          -- of what composing its cells took.
          (ds, bytes) <- allocatedBy (pdfDiagnostics False [("a.gm", "@table data/max.csv\n"), ("data/max.csv", csvOf (replicate 10000 256))])
          [(c, m) | (c, m, _) <- ds] @?= [("G07108", tooMany 2560000)]
          assertBool ("allocated " <> show bytes <> " bytes") (bytes <= 8 * 2 ^ (30 :: Int)),
      localOption (mkTimeout 30000000) $
        testCase "T1, T3: N cells are composed as before (G07041); N + 1 are G07108 alone, at the block of the table" $ do
          atN <- pdfDiagnostics False [("a.gm", "@table data/t.csv\n"), ("data/t.csv", csvOf (replicate 400 250))]
          [c | (c, _, _) <- atN] @?= ["G07041"]
          overN <- pdfDiagnostics False [("a.gm", "@table data/t.csv\n"), ("data/t.csv", csvOf (replicate 9091 11))]
          [(c, m) | (c, m, _) <- overN] @?= [("G07108", tooMany 100001)]
          -- at the block of the table, where G07041 is
          [sp | (_, _, sp) <- overN] @?= [sp | (_, _, sp) <- atN],
      localOption (mkTimeout 30000000) $
        testCase "T1: the cells of a header row of empty cells, a table without a header row, are counted" $ do
          ds <- pdfDiagnostics False [("a.gm", fromEmet "blank-header"), emetFile]
          [(c, m) | (c, m, _) <- ds] @?= [("G07108", tooMany 100001)],
      -- every source makes rows as long as the header row (G02085, G01015,
      -- E06104, and the output of a plugin), so no test of rows of
      -- different lengths reaches the PDF
      localOption (mkTimeout 30000000) $
        testCase "T4: a table of N + 1 cells from a CSV, a TSV, a | table of .gm and Block.table of Emet is the same G07108" $ do
          -- 100,001 = 9,091 rows of 11 cells, the header row one of them
          let rows = replicate 9091 11
          csv <- pdfDiagnostics False [("a.gm", "@table data/t.csv\n"), ("data/t.csv", csvOf rows)]
          tsv <- pdfDiagnostics False [("a.gm", "@table data/t.tsv\n"), ("data/t.tsv", tsvOf rows)]
          bars <- pdfDiagnostics False [("a.gm", barsOf rows)]
          emet <- pdfDiagnostics False [("a.gm", fromEmet "big"), emetFile]
          forM_ [csv, tsv, bars, emet] $ \ds -> [(c, m) | (c, m, _) <- ds] @?= [("G07108", tooMany 100001)],
      localOption (mkTimeout 30000000) $
        testCase "T5: HTML and text set a table of N + 1 cells without G07108" $
          forM_ [TargetHtml, TargetText] $ \target ->
            withTables [("a.gm", "@table data/t.csv\n")] [("data/t.csv", csvOf (replicate 9091 11))] $ \tmp -> do
              r <- build (defaultOptions tmp) {optTargets = Just [target]}
              codesOf (brDiagnostics r) @?= []
              assertBool (show target <> " writes its output") (not (null (brWritten r))),
      localOption (mkTimeout 30000000) $
        testCase "T6: the diagnostics of a table over N and a small one are the same in parallel and not" $ do
          let files = [("a.gm", "@table data/big.csv\n\n@table data/small.csv\n"), ("data/big.csv", csvOf (replicate 9091 11)), ("data/small.csv", csvOf [2, 2])]
          one <- pdfDiagnostics False files
          many <- pdfDiagnostics True files
          [c | (c, _, _) <- one] @?= ["G07108"]
          many @?= one
    ]
  where
    tooMany :: Int -> Text
    tooMany n = "表のセルが多すぎて PDF に組めません（" <> T.pack (show n) <> " 個、上限は 100000 個）"
    rowOf sep n = T.intercalate sep (replicate n "x") <> "\n"
    csvOf = TE.encodeUtf8 . T.concat . map (rowOf ",")
    tsvOf = TE.encodeUtf8 . T.concat . map (rowOf "\t")
    barsOf ns = case ns of
      [] -> ""
      h : rest -> TE.encodeUtf8 (T.concat (bar h : T.concat ["|", T.replicate h "---|", "\n"] : map bar rest))
    bar n = "| " <> T.intercalate " | " (replicate n "x") <> " |\n"
    fromEmet name = "@import functions/book.emet as book\n\n@book." <> name <> "\n"
    -- tables of Emet of 9,091 rows of 11 cells (N + 1)
    emetFile =
      ( "functions/book.emet",
        TE.encodeUtf8 . T.unlines $
          [ "pub block big :: Blocks",
            "big = Block.table (cells 11) (List.map (row 11) (List.range 1 9090))",
            "",
            "pub block \"blank-header\" blankHeader :: Blocks",
            "blankHeader = Block.table (List.map blank (List.range 1 11)) (List.map (row 11) (List.range 1 9090))",
            "",
            "blank :: Int -> Inlines",
            "blank _ = Inline.text \"\"",
            "",
            "row :: Int -> Int -> List Inlines",
            "row n _ = cells n",
            "",
            "cells :: Int -> List Inlines",
            "cells n = List.map cell (List.range 1 n)",
            "",
            "cell :: Int -> Inlines",
            "cell _ = Inline.text \"x\""
          ]
      )
    -- the diagnostics of a PDF build of the files (a.gm first): code, message, position
    pdfDiagnostics :: Bool -> [(FilePath, BS.ByteString)] -> IO [(Text, Text, SrcSpan)]
    pdfDiagnostics parallel files = withTables (take 1 files) (drop 1 files) $ \tmp -> do
      writeStyleWithFont tmp horizontalStyle
      r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optParallel = parallel}
      _ <- evaluate (length (show (brDiagnostics r)))
      pure [(c, diagMessage d, diagSpan d) | d <- brDiagnostics r, let DiagnosticCode c = diagCode d, isError d]
    -- the bytes the calling thread allocates for a result
    allocatedBy act = do
      setAllocationCounter 0
      x <- act
      after <- getAllocationCounter
      pure (x, fromIntegral (negate after) :: Int)
