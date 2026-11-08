{- | golem fmt and the table files that @table reads (docs/adr/0186): the
preprocessing keeps the table the reader makes, and golem fmt fixes the
BOM and the line breaks of the table files.
-}
module FmtTableSpec (fmtTableTests) where

import Data.ByteString qualified as BS
import Data.List (isInfixOf, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Eval.File (parseCsv, parseTsv)
import Golem.Fmt (formatTable)
import Golem.Syntax (FileId (..))
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

fmtTableTests :: TestTree
fmtTableTests = testGroup "golem fmt and the table files (docs/adr/0186)" [propertyTests, commandTests]

{- | The text of a table file without a lone CR: a BOM or none, then cells,
separators, quotes and line breaks.
-}
tableText :: Gen Text
tableText = do
  bom <- Gen.element ["", "\xFEFF"]
  body <- T.concat <$> Gen.list (Range.linear 0 30) (Gen.element ["a", "x y", " ", ",", "\t", "\"", "\n", "\r\n", "\xFEFF", "語"])
  pure (bom <> (if "\xFEFF" `T.isPrefixOf` body then "a" <> body else body))

-- | The table the reader makes, or none when it stops.
tableOf :: (FileId -> Text -> Either e [[Text]]) -> Text -> Maybe [[Text]]
tableOf parse = either (const Nothing) Just . parse (FileId 0)

propertyTests :: TestTree
propertyTests =
  testGroup
    "the preprocessing keeps the table"
    [ testProperty "CSV" $ property $ do
        src <- forAll tableText
        tableOf parseCsv (formatTable src) === tableOf parseCsv src,
      testProperty "TSV" $ property $ do
        src <- forAll tableText
        tableOf parseTsv (formatTable src) === tableOf parseTsv src
    ]

manifest :: String
manifest = T.unpack (manifestToml testManifest {tmChapters = ["a.gm"]})

{- | Runs the commands of golem one after another in a directory holding
the files; the exit code, stdout and stderr of each, and the files
afterwards.
-}
golemSteps :: [(FilePath, Text)] -> [[String]] -> IO ([(ExitCode, String, String)], [(FilePath, Text)])
golemSteps files steps = withSystemTempDirectory "golem-cli" $ \tmp -> do
  mapM_ (\(p, c) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) (TE.encodeUtf8 c)) files
  rs <- mapM (\args -> readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} "") steps
  result <- mapM (\(p, _) -> (p,) . TE.decodeUtf8 <$> BS.readFile (tmp </> p)) files
  pure (rs, result)

-- | Three table files: BOM and CRLF, CRLF, and a lone CR in quotes.
tables :: [(FilePath, Text)]
tables =
  [ ("manifest.toml", T.pack manifest),
    ("a.gm", "@table data/a.csv\n\n@table data/b.tsv\n\n@table data/c.csv\n"),
    ("data/a.csv", "\xFEFF\&a,b\r\n\"x\r\ny\",2\r\n"),
    ("data/b.tsv", "a\tb\r\nx\t\r\n"),
    ("data/c.csv", "a,b\n\"p\rq\",2\n")
  ]

commandTests :: TestTree
commandTests =
  testGroup
    "golem fmt"
    [ testCase "without arguments, the table files become LF only, and golem check reports no G02082" $ do
        ([(code, _, err), (_, _, err')], files') <- golemSteps tables [["fmt"], ["check"]]
        assertEqual err ExitSuccess code
        lookup "data/a.csv" files' @?= Just "a,b\n\"x\ny\",2\n"
        lookup "data/b.tsv" files' @?= Just "a\tb\nx\t\n"
        lookup "data/c.csv" files' @?= Just "a,b\n\"p\nq\",2\n"
        assertBool err' (not ("G02082" `isInfixOf` err')),
      testCase "--check shows the three table files and rewrites nothing" $ do
        ([(code, out, err)], files') <- golemSteps tables [["fmt", "--check"]]
        assertEqual err (ExitFailure 1) code
        sort (lines out) @?= ["data/a.csv", "data/b.tsv", "data/c.csv"]
        files' @?= tables,
      testCase "a .tsv given keeps the tab at the start of a line" $ do
        ([(code, _, err)], files') <- golemSteps [("data/s.tsv", "a\tb\r\n\tz  \r\n")] [["fmt", "data/s.tsv"]]
        assertEqual err ExitSuccess code
        lookup "data/s.tsv" files' @?= Just "a\tb\n\tz  \n",
      testCase "a .CSV given is a table file" $ do
        ([(code, _, err)], files') <- golemSteps [("data/t.CSV", "a,b\r\n\"x\n\n\ny  \",1\r\n")] [["fmt", "data/t.CSV"]]
        assertEqual err ExitSuccess code
        lookup "data/t.CSV" files' @?= Just "a,b\n\"x\n\n\ny  \",1\n",
      testCase "without arguments, a table file of format=tsv named .txt is a table file" $ do
        let files = [("manifest.toml", T.pack manifest), ("a.gm", "@table data/export.txt format=tsv\n"), ("data/export.txt", "a\tb\r\n\tz  \r\n")]
        ([(code, _, err)], files') <- golemSteps files [["fmt"]]
        assertEqual err ExitSuccess code
        lookup "data/export.txt" files' @?= Just "a\tb\n\tz  \n",
      testCase "without arguments, a file only @listing reads keeps its CRLF" $ do
        let files = [("manifest.toml", T.pack manifest), ("a.gm", "@listing src/x.hs\n"), ("src/x.hs", "main = pure ()\r\n")]
        ([(ccode, out, cerr), (code, _, err)], files') <- golemSteps files [["fmt", "--check"], ["fmt"]]
        assertEqual cerr ExitSuccess ccode
        out @?= ""
        assertEqual err ExitSuccess code
        lookup "src/x.hs" files' @?= Just "main = pure ()\r\n",
      testCase "without arguments, a source stopping the load at its CR and a table file with CRLF are both fixed" $ do
        let files = [("manifest.toml", T.pack manifest), ("a.gm", "本文。\r\n\r\n@table data/a.csv\r\n"), ("data/a.csv", "a,b\r\n1,2\r\n")]
        ([(code, _, err)], files') <- golemSteps files [["fmt"]]
        assertEqual err ExitSuccess code
        lookup "a.gm" files' @?= Just "本文。\n\n@table data/a.csv\n"
        lookup "data/a.csv" files' @?= Just "a,b\n1,2\n",
      testCase "without arguments, a table file not UTF-8 is not formatted, with 1" $ do
        ([(code, _, err)], _) <- withBytes [("manifest.toml", TE.encodeUtf8 (T.pack manifest)), ("a.gm", "@table data/a.csv\n"), ("data/a.csv", "a,b\r\n\xff,2\r\n")] [["fmt"]]
        assertEqual err (ExitFailure 1) code
        assertBool err ("data/a.csv: UTF-8 として読めないため整形しません" `isInfixOf` err),
      -- A4 of docs/adr/0211: golem fmt removes the BOM of a table file that
      -- @listing reads too, and @listing then takes its first line without it
      testCase "A4: after golem fmt, @listing of a table file it shares with @table starts without the BOM" $
        withSystemTempDirectory "golem-cli" $ \tmp -> do
          let files = [("manifest.toml", manifestToml testManifest {tmChapters = ["a.gm"], tmTargets = ["html"]}), ("a.gm", "@table data/x.csv\n\n@listing data/x.csv\n"), ("data/x.csv", "\xFEFF\&a,b\n1,2\n")]
          mapM_ (\(p, c) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) (TE.encodeUtf8 c)) files
          let golem args = readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} ""
          (code0, _, err0) <- golem ["build", "--target", "html"]
          assertEqual err0 ExitSuccess code0
          before <- TE.decodeUtf8 <$> BS.readFile (tmp </> "build" </> "html" </> "a.xhtml")
          assertBool "the BOM is in @listing before golem fmt" ("\xFEFF" `T.isInfixOf` before)
          (code1, _, err1) <- golem ["fmt"]
          assertEqual err1 ExitSuccess code1
          (code2, _, err2) <- golem ["build", "--target", "html"]
          assertEqual err2 ExitSuccess code2
          after <- TE.decodeUtf8 <$> BS.readFile (tmp </> "build" </> "html" </> "a.xhtml")
          assertBool "no BOM in @listing after golem fmt" (not ("\xFEFF" `T.isInfixOf` after))
          assertBool "the first line of @listing is there" ("a,b" `T.isInfixOf` after),
      testCase "without arguments, a missing table file and one outside the root are left to the build" $ do
        let files = [("manifest.toml", T.pack manifest), ("a.gm", "@table data/none.csv\n\n@table ../out.csv\n")]
        ([(code, out, err)], _) <- golemSteps files [["fmt"]]
        assertEqual (out <> err) ExitSuccess code
        out <> err @?= ""
    ]
  where
    withBytes files steps = withSystemTempDirectory "golem-cli" $ \tmp -> do
      mapM_ (\(p, c) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) c) files
      rs <- mapM (\args -> readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} "") steps
      pure (rs, ())
