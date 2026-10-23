-- | Reading CSV and TSV files for @table, and where their errors point (golem-eval ADR 0004).
module TableFilesSpec (tableFileTests) where

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
import Support
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

manifestOf :: [FilePath] -> BS.ByteString
manifestOf chapters =
  "chapters = [" <> BS.intercalate ", " ["\"" <> TE.encodeUtf8 (T.pack c) <> "\"" | c <- chapters] <> "]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"

-- | A project of the given files, chapters first, with a style.toml.
withTables :: [(FilePath, BS.ByteString)] -> [(FilePath, BS.ByteString)] -> (FilePath -> IO a) -> IO a
withTables chapters files act = withSystemTempDirectory "golem-tables" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (manifestOf (map fst chapters))
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  forM_ (chapters <> files) $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  act tmp

check :: FilePath -> IO BuildResult
check tmp = build (defaultOptions tmp) {optCheckOnly = True, optTargets = Just [TargetHtml]}

codesOf :: BuildResult -> [Text]
codesOf r = [c | d <- brDiagnostics r, let DiagnosticCode c = diagCode d]

-- | The blocks of each chapter, by path.
blocksOf :: FilePath -> IO (Map.Map FilePath [BlockBody])
blocksOf tmp = do
  e <- evaluateProject Dev tmp >>= either (const (assertFailure "the project does not load")) pure
  pure (Map.fromList [(sfPath sf, maybe [] (map blockBody . docBlocks . erDocument) (Map.lookup fid (evResults e))) | (fid, sf) <- Map.toList (projectSources (evProject e))])

oneTable :: FilePath -> BS.ByteString -> IO [BlockBody]
oneTable path bytes = withTables [("a.gm", TE.encodeUtf8 ("@table src=" <> T.pack path <> "\n"))] [(path, bytes)] $ \tmp -> do
  r <- check tmp
  codesOf r @?= []
  Map.findWithDefault [] "a.gm" <$> blocksOf tmp

headerTexts :: [BlockBody] -> [[Text]]
headerTexts bs = [[t | Text _ t <- c] | Table _ h _ <- bs, c <- h]

tableFileTests :: TestTree
tableFileTests =
  testGroup
    "table files (golem-eval ADR 0004)"
    [ testCase "a BOM at the start of a TSV or a CSV is skipped" $ do
        withBom <- oneTable "data/x.tsv" "\xEF\xBB\xBF\&a\tb\n1\t2\n"
        without <- oneTable "data/x.tsv" "a\tb\n1\t2\n"
        withBom @?= without
        headerTexts withBom @?= [["a"], ["b"]]
        csvBom <- oneTable "data/x.csv" "\xEF\xBB\xBF\&a,b\n1,2\n"
        headerTexts csvBom @?= [["a"], ["b"]],
      testCase "G02085 after a BOM counts its bytes" $
        withTables [("a.gm", "@table src=data/x.tsv\n")] [("data/x.tsv", "\xEF\xBB\xBF\&a\tb\nc\n")] $ \tmp -> do
          r <- check tmp
          [(c, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- brDiagnostics r, let { DiagnosticCode c = diagCode d }] @?= [("G02085", 7, 8)],
      testCase "a BOM at the start of a source file is still G01002" $
        withTables [("a.gm", "\xEF\xBB\xBF\&x\n")] [] $ \tmp -> do
          r <- check tmp
          codesOf r @?= ["G01002"],
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
          withTables [("a.gm", TE.encodeUtf8 ("@table src=" <> T.pack p <> "\n"))] [(p, "a\rb\n")] $ \tmp -> do
            r <- check tmp
            codesOf r @?= ["G02082"],
      testCase "Shift_JIS is G01001" $
        forM_ ["data/x.tsv", "data/x.csv"] $ \p ->
          withTables [("a.gm", TE.encodeUtf8 ("@table src=" <> T.pack p <> "\n"))] [(p, "\x95\x5C\n")] $ \tmp -> do
            r <- check tmp
            codesOf r @?= ["G01001"],
      testCase "the table file is shown in human and JSON output" $
        withTables [("a.gm", "@table src=data/x.tsv\n\n@table src=data/x.csv\n")] [("data/x.tsv", "a\tb\nc\n"), ("data/x.csv", "a,b\nc\n")] $ \tmp -> do
          r <- check tmp
          let human = renderHuman (brSources r) (brDiagnostics r)
              json = renderJson (brSources r) (brDiagnostics r)
          assertBool (T.unpack human) ("data/x.tsv:2:1: error[G02085]" `T.isInfixOf` human)
          assertBool (T.unpack human) ("data/x.csv:2:1: error[G02085]" `T.isInfixOf` human)
          assertBool (T.unpack json) ("\"data/x.tsv\"" `T.isInfixOf` json && "\"data/x.csv\"" `T.isInfixOf` json),
      testCase "a file referred to twice gives its reading error once" $
        withTables [("a.gm", "@table src=data/x.tsv\n\n@table src=data/x.tsv\n")] [("data/x.tsv", "a\rb\n")] $ \tmp -> do
          r <- check tmp
          codesOf r @?= ["G02082"],
      testCase "FileIds do not depend on the order the files were made" $ do
        let files = [("data/b.tsv", "a\tb\nc\n"), ("data/a.csv", "a,b\nc\n"), ("src/x.hs", "x\n")]
            src = "@table src=data/b.tsv\n\n@table src=data/a.csv\n\n@listing src/x.hs\n"
            spans fs = withTables [("a.gm", src)] fs $ \tmp -> do
              r <- check tmp
              pure (sort [(siPath si, fid) | (fid, si) <- Map.toList (brSources r)], sort (map diagSpan (brDiagnostics r)))
        a <- spans files
        b <- spans (reverse files)
        a @?= b,
      testCase "a table file that fails to be read makes no table; the other chapters are evaluated" $
        withTables [("a.gm", "@table src=data/x.tsv\n"), ("b.gm", TE.encodeUtf8 "本文。\n")] [("data/x.tsv", "a\rb\n")] $ \tmp -> do
          r <- check tmp
          codesOf r @?= ["G02082"]
          byPath <- blocksOf tmp
          Map.lookup "a.gm" byPath @?= Just []
          fmap length (Map.lookup "b.gm" byPath) @?= Just 1,
      testCase "@listing of a table file reads it as before, BOM included" $
        withTables [("a.gm", "@table src=data/x.csv\n\n@listing data/x.csv\n")] [("data/x.csv", "\xEF\xBB\xBF\&a,b\n1,2\n")] $ \tmp -> do
          r <- check tmp
          codesOf r @?= []
          bs <- Map.findWithDefault [] "a.gm" <$> blocksOf tmp
          [codeText c | CodeBlock c <- bs] @?= ["\xFEFF\&a,b\n1,2"],
      testCase "align=right reaches HTML, and the PDF sets it as a | table with ---:" $ do
        written <- withTables [("a.gm", "@table src=data/x.csv align=right\n")] [("data/x.csv", TE.encodeUtf8 "項目,値\n幅,10\n")] $ \tmp -> do
          r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
          mapM (fmap TE.decodeUtf8 . BS.readFile) (filter (".xhtml" `isSuffixOf`) (brWritten r))
        assertBool "align-right" (any ("class=\"align-right\"" `T.isInfixOf`) written)
        fromCsv <- miniPdf fakeProvider True horizontalStyle "@table src=data.csv align=right\n" [("data.csv", TE.encodeUtf8 "項目,値\n幅,10\n")] >>= fmap BS.concat . inflateAll
        fromBars <- miniPdf fakeProvider True horizontalStyle "| 項目 | 値 |\n|---:|---:|\n| 幅 | 10 |\n" [] >>= fmap BS.concat . inflateAll
        sort (drawnGlyphs fromCsv) @?= sort (drawnGlyphs fromBars),
      -- the time-out detects a build that does not stop (docs/adr ADR 0073)
      localOption (mkTimeout 30000000) $
        testCase "a large table is G02088, and the text build ends (docs/adr ADR 0043)" $
          withTables [("a.gm", "@table src=data/big.tsv\n")] [("data/big.tsv", BS.concat (replicate 200000 "a\tb\tc\n"))] $ \tmp -> do
            r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
            [(c, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- brDiagnostics r, let DiagnosticCode c = diagCode d]
              @?= [("G02088", "表のファイルが行の数の上限を超えます: data/big.tsv（10001 行目、上限は 10000 行）", 0, 24)],
      testCase "a table file over 16 MiB is G02088 and is not read (docs/adr ADR 0043)" $
        -- bytes that are not UTF-8 would be G01001 if the file were read
        withTables [("a.gm", "@table src=data/big.csv\n")] [("data/big.csv", BS.replicate (2 ^ (24 :: Int)) 0x61 <> "\xFF")] $ \tmp -> do
          r <- check tmp
          [(c, diagMessage d) | d <- brDiagnostics r, let DiagnosticCode c = diagCode d]
            @?= [("G02088", "表のファイルが大きさの上限を超えます: data/big.csv（16777217 バイト、上限は 16777216 バイト）")],
      testCase "a table file of 16 MiB is read" $
        withTables [("a.gm", "@table src=data/big.csv\n")] [("data/big.csv", BS.replicate (2 ^ (24 :: Int) - 1) 0x61 <> "\n")] $ \tmp -> do
          r <- check tmp
          codesOf r @?= []
    ]
