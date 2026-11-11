{- | golem new, inspect, fmt, plugin lock and fetch, and preflight, run as
a process in a temporary directory (golem-cli ADR 0001, ADR 0003, ADR
0006, golem-fmt ADR 0001, golem-plugin ADR 0002). Nothing connects to the
network: golem new runs with --no-fonts, and the plugin commands use URLs
that are rejected or artifacts that are already in the cache.
-}
module CommandsSpec (commandsTests) where

import Control.Monad (forM_)
import Data.Aeson qualified as J
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isDigit)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf, sort, stripPrefix)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Cli.BuildCommand (BuildMode (..), jsonResult, runBuild)
import Golem.Doc.Cbor (encodeDocument)
import Golem.Driver (CropMarks (NoMarks), Evaluated (..), Target (TargetHtml), evaluateProject)
import Golem.Eval.File (EvalResult (..))
import Golem.Project (Project (..), ProjectFailure (..), SourceFile (..))
import Golem.Syntax (Diagnostic (..), FileId (..), Profile (..))
import Golem.Syntax.ShowTree (showTree)
import Golem.TestSupport.Heading (headingLimitSource)
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory, removeDirectoryRecursive)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), StdStream (..), createProcess, proc, readCreateProcessWithExitCode, waitForProcess)
import Test.Tasty
import Test.Tasty.HUnit

commandsTests :: TestTree
commandsTests =
  testGroup
    "commands on a project"
    [replTests, newTests, templateBuildTests, tablePathTests, headingLimitTests, inspectTests, fmtTests, pluginTests, preflightTests]

replTests :: TestTree
replTests =
  testGroup
    "Emet REPL (Golem ADR 0348)"
    [ testCase "R1/R3/R4: a pipe prints each complete value, including the final unterminated line" $
        runRepl "1 +\n2\n9" >>= (@?= (ExitSuccess, "3\n9\n", "")),
      testCase "R1: both input and displayed string can exceed 4096 bytes" $ do
        let literal = "\"" <> replicate 4097 'a' <> "\""
        runRepl literal >>= (@?= (ExitSuccess, literal <> "\n", "")),
      testCase "R5: 100000000 steps and 10000 frames succeed; one more fails and the next input gets a fresh budget" $ do
        (code, out, err) <-
          runRepl $
            unlines
              [ "discard :: List Int -> Nat",
                "discard xs = 7",
                "work :: Int -> Nat",
                "work n = discard (List.range 1 n)",
                "depth :: Int -> Int",
                "depth 0 = 0",
                "depth n = 1 + depth (n - 1)",
                "",
                "work 99999995",
                "work 99999996",
                "depth 9999",
                "depth 10000",
                "42"
              ]
        (code, lines out) @?= (ExitFailure 1, ["7", "9999", "42"])
        map (take 6) (lines err) @?= ["E04100", "E04101"],
      testCase "R6: a rejected import preserves public functions and does not expose private names" $
        withSystemTempDirectory "golem-repl" $ \dir -> do
          writeFiles dir [("double.emet", "pub twice :: Nat -> Nat\ntwice n = hidden n\nhidden :: Nat -> Nat\nhidden n = n + n\n")]
          (code, out, err) <-
            readCreateProcessWithExitCode
              (proc "golem" ["repl", "emet"]) {cwd = Just dir}
              "import \"double.emet\"\ntwice 3\nimport \"../outside.emet\"\nhidden 2\ntwice 4\n"
          (code, lines out) @?= (ExitFailure 1, ["6", "8"])
          length (lines err) @?= 2
          assertBool err ("G03003" `isInfixOf` err),
      testCase "R6: failed replacement leaves the checked definition callable" $ do
        (code, out, _) <- runRepl "twice :: Nat -> Nat\ntwice n = n + n\n\ntwice 3\ntwice :: Nat -> Nat\ntwice n = False\n\ntwice 4\n"
        (code, out) @?= (ExitFailure 1, "6\n8\n"),
      testCase "R2: recover after a syntax error without consuming the next expression" $ do
        (code, out, err) <- runRepl "1 + )\n42\n"
        (code, out) @?= (ExitFailure 1, "42\n")
        assertBool err ("E01100" `isInfixOf` err)
    ]
  where
    runRepl input = withSystemTempDirectory "golem-repl" $ \dir ->
      readCreateProcessWithExitCode (proc "golem" ["repl", "emet"]) {cwd = Just dir} input

-- ------------------------------------------------------------------ helpers

-- | Writes UTF-8 files, making their directories.
writeFiles :: FilePath -> [(FilePath, String)] -> IO ()
writeFiles dir = mapM_ $ \(p, c) -> do
  createDirectoryIfMissing True (takeDirectory (dir </> p))
  BS.writeFile (dir </> p) (TE.encodeUtf8 (T.pack c))

readUtf8 :: FilePath -> IO String
readUtf8 p = T.unpack . TE.decodeUtf8 <$> BS.readFile p

-- | The line of putHuman that points to golem explain.
explainLine :: String -> String
explainLine code = "コードの説明は golem explain <コード> で表示できます（例: golem explain " <> code <> "）\n"

-- | Runs golem in a directory; exit code, stdout and stderr.
golemAt :: FilePath -> [String] -> IO (ExitCode, String, String)
golemAt dir args = readCreateProcessWithExitCode (proc "golem" args) {cwd = Just dir} ""

-- | Runs golem with the plugin cache (XDG_CACHE_HOME) in the given directory.
golemWithCache :: FilePath -> FilePath -> [String] -> IO (ExitCode, String, String)
golemWithCache cache dir args = do
  env <- getEnvironment
  let env' = ("XDG_CACHE_HOME", cache) : filter ((/= "XDG_CACHE_HOME") . fst) env
  readCreateProcessWithExitCode (proc "golem" args) {cwd = Just dir, env = Just env'} ""

-- | Every file under a directory, relative to it, sorted.
filesUnder :: FilePath -> IO [FilePath]
filesUnder root = sort <$> go ""
  where
    go rel = do
      names <- listDirectory (root </> rel)
      concat
        <$> mapM
          ( \n -> do
              let p = if null rel then n else rel </> n
              isDir <- doesDirectoryExist (root </> p)
              if isDir then go p else pure [p]
          )
          names

-- | Runs golem in a directory; exit code and the bytes of stdout.
golemBytesAt :: FilePath -> [String] -> IO (ExitCode, BS.ByteString)
golemBytesAt dir args = do
  (_, Just hout, _, ph) <- createProcess (proc "golem" args) {cwd = Just dir, std_out = CreatePipe}
  out <- BS.hGetContents hout
  code <- waitForProcess ph
  pure (code, out)

{- | The leaves of the 'show' of a value: every run of digits, and the
pieces of every string literal between characters that are escaped.
-}
leaves :: String -> [T.Text]
leaves = \case
  [] -> []
  s@(c : _) | isDigit c -> let (d, r) = span isDigit s in T.pack d : leaves r
  s@('"' : _) | [(str, r)] <- (reads s :: [(String, String)]) -> map T.pack (filter (not . null) (splitEscaped str)) <> leaves r
  _ : r -> leaves r
  where
    splitEscaped str = case break (\x -> x `elem` ("\"\\" :: String) || x < ' ') str of
      (a, []) -> [a]
      (a, _ : r) -> a : splitEscaped r

-- | A project of two chapters, a.gm and b.gm (golem-cli ADR 0007).
twoChapters :: [(FilePath, String)]
twoChapters = [("manifest.toml", manifestWith ["a.gm", "b.gm"]), ("style.toml", ""), ("a.gm", "一章。\n"), ("b.gm", "二章。\n")]

manifestWith :: [T.Text] -> String
manifestWith chapters = T.unpack (manifestToml testManifest {tmChapters = chapters})

{- | Compare each command with literal source spans. In particular, do
not deduplicate or sort its diagnostics before checking them.
-}
headingLimitTests :: TestTree
headingLimitTests =
  testGroup
    "heading-limit"
    [ testCase ("G3/H1/H2/C1: " <> scenario <> " " <> name) $
        withSystemTempDirectory "golem-heading" $ \dir -> do
          let manifest = T.replace "chapters = [\"a.gm\"]" ("chapters = " <> chapters) (manifestToml testManifest)
          writeFiles dir (("manifest.toml", T.unpack manifest) : [(file, T.unpack text) | (file, text) <- files])
          (exit, err) <- jsonResult <$> runBuild dir mode Dev NoMarks False False
          assertEqual (T.unpack err) (ExitFailure 1) exit
          let decoded = J.eitherDecodeStrict (TE.encodeUtf8 err) :: Either String [J.Value]
              spans = decoded >>= parseEither (mapM headingSpan)
          fmap concat spans @?= Right wanted
    | (scenario, chapters, files, wanted) <- scenarios,
      (name, mode) <- [("check", CheckOnly), ("build --target html", WriteTargets [TargetHtml])]
    ]
  where
    two file = [expected file 23 29 5, expected file 46 49 9]
    one file = [expected file 23 29 5]
    firstHeading = T.unlines (take 5 (T.lines headingLimitSource))
    importing = "@import shared.gm as common\n"
    scenarios =
      [ ("single", "[\"a.gm\"]", [("a.gm", headingLimitSource)], two "a.gm"),
        ("nested", "[[\"a.gm\"]]", [("a.gm", headingLimitSource)], two "a.gm"),
        ("repeat", "[\"a.gm\", \"a.gm\"]", [("a.gm", headingLimitSource)], two "a.gm"),
        ("two", "[\"a.gm\", \"b.gm\"]", [("a.gm", headingLimitSource), ("b.gm", firstHeading)], two "a.gm" <> one "b.gm"),
        ("shared", "[\"a.gm\", \"b.gm\"]", [("a.gm", importing), ("b.gm", importing), ("shared.gm", firstHeading)], one "shared.gm"),
        ("chapter-import", "[\"a.gm\", \"shared.gm\"]", [("a.gm", importing), ("shared.gm", firstHeading)], one "shared.gm")
      ]
    headingSpan :: J.Value -> Parser [J.Value]
    headingSpan = J.withObject "diagnostic" $ \d -> do
      code <- d J..: "code"
      if code == ("G01012" :: T.Text) then pure <$> d J..: "span" else pure []
    expected :: T.Text -> Int -> Int -> Int -> J.Value
    expected file start end line = J.object ["file" J..= file, "start" J..= start, "end" J..= end, "line" J..= line, "column" J..= (7 :: Int)]

-- ------------------------------------------------------------------ golem new (golem-cli ADR 0003, ADR 0006)

newTests :: TestTree
newTests =
  testGroup
    "golem new (golem-cli ADR 0003)"
    [ testCase "--no-fonts writes the five files of the template and exits with 0" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        (code, _, err) <- golemAt tmp ["new", "book", "--no-fonts"]
        assertEqual err ExitSuccess code
        files <- filesUnder (tmp </> "book")
        files @?= [".gitignore", "chapters/01.gm", "manifest.toml", "preflight.toml", "style.toml"],
      testCase "--no-fonts names the Japanese font and its licence to place, with their URLs" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        (_, _, err) <- golemAt tmp ["new", "book", "--no-fonts"]
        lines err
          @?= [ "フォントを取得しませんでした。次のファイルを置いてください。",
                "  book/fonts/NotoSerifJP-Regular.otf (https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Serif/SubsetOTF/JP/NotoSerifJP-Regular.otf)",
                "  book/fonts/LICENSE-NotoSerifJP.txt (https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Serif/LICENSE)"
              ],
      testCase "--language en --no-fonts names the Latin font and its licence" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        (_, _, err) <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        lines err
          @?= [ "フォントを取得しませんでした。次のファイルを置いてください。",
                "  book/fonts/SourceSerif4-Regular.otf (https://raw.githubusercontent.com/adobe-fonts/source-serif/4.005R/OTF/SourceSerif4-Regular.otf)",
                "  book/fonts/LICENSE-SourceSerif4.md (https://raw.githubusercontent.com/adobe-fonts/source-serif/4.005R/LICENSE.md)"
              ],
      testCase "the manifest is in the language of the template" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "ja", "--no-fonts"]
        _ <- golemAt tmp ["new", "en", "--language", "en", "--no-fonts"]
        ja <- readUtf8 (tmp </> "ja/manifest.toml")
        en <- readUtf8 (tmp </> "en/manifest.toml")
        (filter ("language = " `isPrefixOf`) (lines ja), filter ("language = " `isPrefixOf`) (lines en))
          @?= (["language = \"ja\""], ["language = \"en\""]),
      testCase "the manifest writes paragraph-separator = \"line\" in [source] for ja and en (docs/adr/0193)" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "ja", "--no-fonts"]
        _ <- golemAt tmp ["new", "en", "--language", "en", "--no-fonts"]
        let source = takeWhile (not . ("[" `isPrefixOf`)) . drop 1 . dropWhile (/= "[source]") . lines
        ja <- source <$> readUtf8 (tmp </> "ja/manifest.toml")
        en <- source <$> readUtf8 (tmp </> "en/manifest.toml")
        (filter (not . null) ja, filter (not . null) en) @?= (["paragraph-separator = \"line\""], ["paragraph-separator = \"line\""]),
      testCase "two projects get different ids" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "a", "--no-fonts"]
        _ <- golemAt tmp ["new", "b", "--no-fonts"]
        a <- filter ("id = \"urn:uuid:" `isPrefixOf`) . lines <$> readUtf8 (tmp </> "a/manifest.toml")
        b <- filter ("id = \"urn:uuid:" `isPrefixOf`) . lines <$> readUtf8 (tmp </> "b/manifest.toml")
        map length a @?= [length ("id = \"urn:uuid:" :: String) + 36 + 1]
        assertBool (show (a, b)) (a /= b),
      testCase "preflight.toml is based on print, with a Japanese header for ja (golem-cli ADR 0006)" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--no-fonts"]
        rules <- lines <$> readUtf8 (tmp </> "book/preflight.toml")
        take 4 rules
          @?= [ "# golem preflight の設定です（入稿の前の検査）。",
                "# 書かなかった値は based-on の設定から引き継ぎます。",
                "# 印刷所から設定のファイルを受け取ったら、このファイルをそれに置き換えます。",
                "based-on = \"print\""
              ],
      testCase "preflight.toml has an English header for en (golem-cli ADR 0006)" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        rules <- lines <$> readUtf8 (tmp </> "book/preflight.toml")
        take 4 rules
          @?= [ "# The rules of golem preflight (the checks before handing off to the printer).",
                "# A value not written here comes from the rules of based-on.",
                "# When your printer gives you a file of rules, replace this file with it.",
                "based-on = \"print\""
              ],
      testCase "with the named font in place, golem check passes on the ja template" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--no-fonts"]
        -- golem check looks for the font file and does not read it
        writeFiles (tmp </> "book") [("fonts/NotoSerifJP-Regular.otf", "font")]
        (code, _, err) <- golemAt (tmp </> "book") ["check"]
        (code, err) @?= (ExitSuccess, ""),
      testCase "with the named font in place, golem check passes on the en template" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        writeFiles (tmp </> "book") [("fonts/SourceSerif4-Regular.otf", "font")]
        (code, _, err) <- golemAt (tmp </> "book") ["check"]
        (code, err) @?= (ExitSuccess, ""),
      testCase "the style.toml of the template has a bleed: 3mm for ja, 0.125in for en (golem-pdf ADR 0010)" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "ja", "--no-fonts"]
        _ <- golemAt tmp ["new", "en", "--language", "en", "--no-fonts"]
        let bleedOf p = filter ("bleed = " `isPrefixOf`) . takeWhile (/= "") . drop 1 . dropWhile (/= "[page]") . lines <$> readUtf8 p
        ja <- bleedOf (tmp </> "ja/style.toml")
        en <- bleedOf (tmp </> "en/style.toml")
        (ja, en) @?= (["bleed = \"3mm\""], ["bleed = \"0.125in\""]),
      testCase "the en template builds a PDF with Japanese marks, without G07002 (golem-pdf ADR 0010)" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        font <- BL.readFile "../golem-font/test/fonts/SourceSansPro-Regular.otf"
        createDirectoryIfMissing True (tmp </> "book/fonts")
        BL.writeFile (tmp </> "book/fonts/SourceSerif4-Regular.otf") font
        (code, _, err) <- golemAt (tmp </> "book") ["build", "--target", "pdf", "--marks", "japanese"]
        assertBool err (not ("G07002" `isInfixOf` err))
        assertEqual err ExitSuccess code
        pdfs <- filter (".pdf" `isSuffixOf`) <$> listDirectory (tmp </> "book/build/pdf")
        length pdfs @?= 1,
      -- docs/adr/0273
      testCase "I1, I7: a directory of other files gets the template: 0, and its files are left alone" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        writeFiles tmp [("book/notes.txt", "mine")]
        (code, _, _) <- golemAt tmp ["new", "book", "--no-fonts"]
        code @?= ExitSuccess
        files <- filesUnder (tmp </> "book")
        files @?= [".gitignore", "chapters/01.gm", "manifest.toml", "notes.txt", "preflight.toml", "style.toml"]
        readUtf8 (tmp </> "book/notes.txt") >>= (@?= "mine"),
      testCase "I5: G03131 for each project file, nothing else" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        writeFiles tmp [("book/manifest.toml", "x"), ("book/style.toml", "x"), ("book/preflight.toml", "x")]
        (code, _, err) <- golemAt tmp ["new", "book", "--no-fonts"]
        (code, err)
          @?= ( ExitFailure 1,
                "book/manifest.toml:1:1: error[G03131]: プロジェクトのファイルがすでにあります: book/manifest.toml\n  | \n"
                  <> "book/style.toml:1:1: error[G03131]: プロジェクトのファイルがすでにあります: book/style.toml\n  | \n"
                  <> explainLine "G03131"
              ),
      testCase "I5: golem new . names the path without ./" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        writeFiles tmp [("manifest.toml", "x")]
        (code, _, err) <- golemAt tmp ["new", ".", "--no-fonts"]
        (code, err) @?= (ExitFailure 1, "manifest.toml:1:1: error[G03131]: プロジェクトのファイルがすでにあります: manifest.toml\n  | \n" <> explainLine "G03131"),
      testCase "I5: G03132 for each taken path, in order" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        writeFiles tmp [("book/preflight.toml", "x"), ("book/chapters/01.gm", "x")]
        (code, _, err) <- golemAt tmp ["new", "book", "--no-fonts"]
        (code, err)
          @?= ( ExitFailure 1,
                "book/chapters/01.gm:1:1: error[G03132]: 雛形のファイルを書くパスに、すでにエントリがあります: book/chapters/01.gm\n  | \n"
                  <> "book/preflight.toml:1:1: error[G03132]: 雛形のファイルを書くパスに、すでにエントリがあります: book/preflight.toml\n  | \n"
                  <> explainLine "G03132"
              )
        filesUnder (tmp </> "book") >>= (@?= ["chapters/01.gm", "preflight.toml"]),
      testCase "I5: G03133 for an argument that is a file, without an exception" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        writeFiles tmp [("afile", "x")]
        (code, _, err) <- golemAt tmp ["new", "afile", "--no-fonts"]
        (code, err) @?= (ExitFailure 1, "afile:1:1: error[G03133]: ディレクトリではありません: afile\n  | \n" <> explainLine "G03133")
        (code', _, err') <- golemAt tmp ["new", "afile/book", "--no-fonts"]
        (code', err') @?= (ExitFailure 1, "afile/book:1:1: error[G03133]: ディレクトリではありません: afile/book\n  | \n" <> explainLine "G03133"),
      testCase "I5: G03134 for an existing .gitignore, which is left alone: 0" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        writeFiles tmp [("book/.gitignore", "node_modules/\n")]
        (code, _, err) <- golemAt tmp ["new", "book", "--no-fonts"]
        code @?= ExitSuccess
        take 3 (lines err)
          @?= [ "book/.gitignore:1:1: notice[G03134]: .gitignore がすでにあるので書きませんでした。build/ を除外してください: book/.gitignore",
                "  | ",
                init (explainLine "G03134")
              ]
        readUtf8 (tmp </> "book/.gitignore") >>= (@?= "node_modules/\n")
    ]

{- | The template of golem new, with a font in place of the one it names,
builds every target without a diagnostic, notices included: the first
output that a user sees is not a warning. The smoke check of a release
checks the same with the fonts that golem new fetches
(docs/adr/0080-release-smoke-checks-diagnostics.md).

The ja template gets the very font that golem new fetches: the Noto Serif
JP of the kanikosen fixture has the SHA-256 of templateFonts. The Source
Serif 4 of the en template is not in the repository; the Source Sans Pro of
the tests has every glyph of its text, which G08100 checks.
-}
templateBuildTests :: TestTree
templateBuildTests =
  testGroup
    "the template builds without diagnostics (docs/adr/0080)"
    [ testCase tag $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp (["new", "book", "--no-fonts"] <> language)
        font <- BL.readFile testFont
        createDirectoryIfMissing True (tmp </> "book/fonts")
        BL.writeFile (tmp </> "book/fonts" </> templateFont) font
        (code, _, err) <- golemAt (tmp </> "book") ["build", "--format", "json"]
        (code, err) @?= (ExitSuccess, "[]\n")
        forM_ ["html", "epub", "text", "pdf"] $ \t ->
          listDirectory (tmp </> "book/build" </> t) >>= assertBool ("no " <> t <> " output") . not . null
    | (tag, language, templateFont, testFont) <-
        [ ("ja", [], "NotoSerifJP-Regular.otf", "../golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"),
          ("en", ["--language", "en"], "SourceSerif4-Regular.otf", "../golem-font/test/fonts/SourceSansPro-Regular.otf")
        ]
    ]

{- | The path of @table as the first argument builds the same outputs as
src=, byte for byte, in the four targets; src= gives the notice G02129
(docs/adr/0184). The instance ID of the PDF (the second of /ID) is the
hash of the bytes of every input (docs/adr/0002), the source among them,
and differs with the source; it alone is left out of the comparison
(docs/adr/0211).
-}
tablePathTests :: TestTree
tablePathTests =
  testGroup
    "the path of @table as the first argument (docs/adr/0184)"
    [ testCase "golem build writes the same files for @table data/t.csv and @table src=data/t.csv" $ withSystemTempDirectory "golem-table" $ \tmp -> do
        -- one project for both, as golem new gives each project its own identifier
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        font <- BL.readFile "../golem-font/test/fonts/SourceSansPro-Regular.otf"
        createDirectoryIfMissing True (tmp </> "book/fonts")
        BL.writeFile (tmp </> "book/fonts/SourceSerif4-Regular.otf") font
        chapter <- readUtf8 (tmp </> "book/chapters/01.gm")
        let buildWith line = do
              writeFiles (tmp </> "book") [("chapters/01.gm", chapter <> "\n" <> line <> "\n"), ("data/t.csv", "Name,Size\nA,1\nB,2\n")]
              (code, _, err) <- golemAt (tmp </> "book") ["build", "--format", "json"]
              assertEqual err ExitSuccess code
              files <- filesUnder (tmp </> "book/build")
              outputs <- mapM (\p -> (p,) <$> BS.readFile (tmp </> "book/build" </> p)) files
              removeDirectoryRecursive (tmp </> "book/build")
              pure (Map.fromList outputs, err)
        (positional, perr) <- buildWith "@table data/t.csv"
        (keyword, kerr) <- buildWith "@table src=data/t.csv"
        perr @?= "[]\n"
        assertBool kerr ("G02129" `isInfixOf` kerr)
        forM_ ["html", "epub", "text", "pdf"] $ \t ->
          assertBool ("no " <> t <> " output") (any ((t <> "/") `isPrefixOf`) (Map.keys positional))
        Map.keys positional @?= Map.keys keyword
        forM_ (Map.toList positional) $ \(p, bytes) -> assertBool p (fmap withoutInstanceId (Map.lookup p keyword) == Just (withoutInstanceId bytes))
    ]
  where
    -- /ID [<document ID> <instance ID>], the instance ID as zeros
    withoutInstanceId bytes = case BS.breakSubstring "/ID [<" bytes of
      (before, rest)
        | not (BS.null rest) ->
            let (docId, afterDoc) = BS.break (== 0x3E) (BS.drop 6 rest)
                (sep, instanceAndRest) = BS.break (== 0x3C) afterDoc
                (instanceId, afterInstance) = BS.break (== 0x3E) (BS.drop 1 instanceAndRest)
             in BS.concat [before, "/ID [<", docId, sep, "<", BS.map (const 0x30) instanceId, afterInstance]
      _ -> bytes

-- ------------------------------------------------------------------ golem inspect (golem-cli ADR 0001)

inspectTests :: TestTree
inspectTests =
  testGroup
    "golem inspect (golem-cli ADR 0001)"
    [ testCase "the CST is the default, on stdout" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "本文。\n")]
        (code, out, err) <- golemAt tmp ["inspect", "a.gm"]
        (code, err) @?= (ExitSuccess, "")
        lines out
          @?= [ "NFile@0..10",
                "  NParagraph@0..10",
                "    KWhitespace@0..0 \"\"",
                "    KText@0..9 \"本文。\"",
                "    KNewline@9..10 \"\\n\"",
                "    KWhitespace@10..10 \"\""
              ],
      testCase "--as cst is the default" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "# 見出し\n\n本文。\n")]
        (_, byDefault, _) <- golemAt tmp ["inspect", "a.gm"]
        (code, cst, _) <- golemAt tmp ["inspect", "a.gm", "--as", "cst"]
        code @?= ExitSuccess
        cst @?= byDefault,
      -- docs/adr ADR 0031
      testCase "--cst, --ast and --ir are no options: a usage error, 2" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "本文。\n")]
        forM_ ["--cst", "--ast", "--ir"] $ \flag -> do
          (code, _, _) <- golemAt tmp ["inspect", "a.gm", flag]
          code @?= ExitFailure 2,
      testCase "--as ast shows the AST of the file as a tree" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "本文。\n")]
        (code, out, _) <- golemAt tmp ["inspect", "a.gm", "--as", "ast"]
        code @?= ExitSuccess
        assertBool out ("File" `isPrefixOf` out && "Paragraph" `isInfixOf` out && "本文。" `isInfixOf` out && not ("SrcSpan" `isInfixOf` out)),
      testCase "syntax errors are written as the other commands write them, with 1 (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "[strong: x\n")]
        (code, out, err) <- golemAt tmp ["inspect", "a.gm"]
        code @?= ExitFailure 1
        assertBool out ("NFile@" `isPrefixOf` out)
        assertBool err ("a.gm:2:1: error[G01017]: " `isPrefixOf` err && "golem explain" `isInfixOf` err && not ("Diagnostic {" `isInfixOf` err))
        (code', out', _) <- golemAt tmp ["inspect", "a.gm", "--as", "ast"]
        code' @?= ExitFailure 1
        assertBool out' ("File" `isPrefixOf` out'),
      testCase "a file that is not there is G03002 (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        (code, out, err) <- golemAt tmp ["inspect", "nope.gm"]
        (code, out) @?= (ExitFailure 1, "")
        take 1 (lines err) @?= ["nope.gm:1:1: error[G03002]: ファイルがありません: nope.gm"]
        assertBool err (not ("withBinaryFile" `isInfixOf` err) && not ("backtrace" `isInfixOf` err)),
      testCase "a directory is G03002 (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        createDirectoryIfMissing True (tmp </> "d.gm")
        (code, _, err) <- golemAt tmp ["inspect", "d.gm"]
        code @?= ExitFailure 1
        assertBool err ("error[G03002]" `isInfixOf` err),
      testCase "a file that is not UTF-8 is G01001 in the human format (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        BS.writeFile (tmp </> "b.gm") (BS.pack [0x61, 0xff, 0x0a])
        (code, _, err) <- golemAt tmp ["inspect", "b.gm"]
        code @?= ExitFailure 1
        assertBool err ("b.gm:1:2: error[G01001]: " `isPrefixOf` err),
      testCase "--as ir shows the document of the file, without the CBOR line (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp twoChapters
        (code, out, err) <- golemAt tmp ["inspect", "b.gm", "--as", "ir"]
        (code, err) @?= (ExitSuccess, "")
        assertBool out ("Document" `isPrefixOf` out && "二章" `isInfixOf` out && not ("一章" `isInfixOf` out) && not ("CBOR:" `isInfixOf` out))
        (_, dotted, _) <- golemAt tmp ["inspect", "./b.gm", "--as", "ir"]
        dotted @?= out,
      testCase "--as ir of a file that is not a chapter evaluates it in the project (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp (twoChapters <> [("c.gm", "三章の[style note: 注]。\n"), ("style.toml", "[character-styles.note]\n")])
        (code, out, err) <- golemAt tmp ["inspect", "c.gm", "--as", "ir"]
        (code, err) @?= (ExitSuccess, "")
        assertBool out ("三章" `isInfixOf` out && "CharStyle" `isInfixOf` out && "\"note\"" `isInfixOf` out)
        e <- evaluateProject Dev tmp >>= either (const (assertFailure "project")) pure
        let used = [n | FileId n <- Map.keys (projectSources (evProject e))]
            docFile = [read (takeWhile isDigit rest) :: Int | l <- lines out, Just rest <- [stripPrefix "docFile = FileId " (dropWhile (== ' ') l)]]
        assertBool (show (docFile, used)) (length docFile == 1 && all (> maximum used) docFile),
      testCase "the errors of the other chapters are not written for a file that is not a chapter (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp (twoChapters <> [("a.gm", "一章の[nosuch: x]。\n"), ("c.gm", "三章。\n")])
        (code, _, err) <- golemAt tmp ["inspect", "c.gm", "--as", "ir"]
        (code, err) @?= (ExitSuccess, ""),
      testCase "the errors of a file that is not a chapter (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp (twoChapters <> [("c.gm", "三章の[nosuch: x]。\n")])
        (code, out, err) <- golemAt tmp ["inspect", "c.gm", "--as", "ir"]
        code @?= ExitFailure 1
        assertBool err ("c.gm:1:" `isPrefixOf` err && "error[G02022]" `isInfixOf` err)
        assertBool out ("Document" `isPrefixOf` out),
      testCase "--as ir without manifest.toml evaluates the file alone (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("x.gm", "単独。\n")]
        (code, out, err) <- golemAt tmp ["inspect", "x.gm", "--as", "ir"]
        (code, err) @?= (ExitSuccess, "")
        assertBool out ("Document" `isPrefixOf` out && "単独。" `isInfixOf` out),
      testCase "--as ir of a project that cannot be loaded writes its errors and nothing else (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp (twoChapters <> [("style.toml", "[page\n")])
        (code, out, err) <- golemAt tmp ["inspect", "b.gm", "--as", "ir"]
        (code, out) @?= (ExitFailure 1, "")
        assertBool err ("style.toml:" `isInfixOf` err && "error[" `isInfixOf` err),
      testCase "--as ir of a chapter writes the errors of the project (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp (twoChapters <> [("a.gm", "一章の[ref-title nolabel]。\n")])
        (code, out, err) <- golemAt tmp ["inspect", "b.gm", "--as", "ir"]
        code @?= ExitFailure 1
        assertBool err ("error[G04003]" `isInfixOf` err)
        assertBool out ("二章" `isInfixOf` out),
      testCase "--as cbor writes the CBOR of the document (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp twoChapters
        (code, out) <- golemBytesAt tmp ["inspect", "b.gm", "--as", "cbor"]
        code @?= ExitSuccess
        e <- evaluateProject Dev tmp >>= either (const (assertFailure "project")) pure
        let docs = [encodeDocument (erDocument r) | (fid, sf) <- Map.toList (projectSources (evProject e)), sfPath sf == "b.gm", Just r <- [Map.lookup fid (evResults e)]]
        docs @?= [out],
      testCase "the AST and the IR of a fixture are read as trees, with every leaf in them (golem-cli ADR 0007)" $ do
        e <- evaluateProject Dev "../golem-driver/test/fixtures/sample" >>= either (assertFailure . show . map diagMessage . pfDiagnostics) pure
        let shown =
              [show (sfAst sf) | sf <- Map.elems (projectSources (evProject e))]
                <> [show (erDocument r) | r <- Map.elems (evResults e)]
        assertBool (show (length shown)) (length shown >= 4)
        mapM_
          ( \s -> do
              let t = showTree (FileId 1) s
              assertBool (take 200 s) (length s <= 100 || T.unpack t /= s)
              mapM_ (\leaf -> assertBool (T.unpack leaf) (leaf `T.isInfixOf` t)) (leaves s)
          )
          shown,
      testCase "--as with an unknown value is a usage error" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "本文。\n")]
        (code, _, _) <- golemAt tmp ["inspect", "a.gm", "--as", "nope"]
        code @?= ExitFailure 2
    ]

-- ------------------------------------------------------------------ golem fmt over the project (golem-fmt ADR 0001)

-- | A project of two chapters; the second has two blank lines too many and trailing spaces.
fmtProject :: [(FilePath, String)]
fmtProject =
  [ ("manifest.toml", manifestWith ["chapters/01.gm", "chapters/02.gm"]),
    ("chapters/01.gm", "# はじめに\n\n本文。\n"),
    ("chapters/02.gm", "# 次に\n\n\n\n本文。  \n")
  ]

fmtTests :: TestTree
fmtTests =
  testGroup
    "golem fmt over the project (golem-fmt ADR 0001)"
    [ testCase "--check names only the unformatted chapter on stdout and exits with 1" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        (code, out, _) <- golemAt tmp ["fmt", "--check"]
        (code, out) @?= (ExitFailure 1, "chapters/02.gm\n"),
      testCase "--check leaves the file as it was" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        _ <- golemAt tmp ["fmt", "--check"]
        readUtf8 (tmp </> "chapters/02.gm") >>= (@?= "# 次に\n\n\n\n本文。  \n"),
      testCase "without --check, every chapter of the manifest is formatted in place and the exit code is 0" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        (code, out, err) <- golemAt tmp ["fmt"]
        (code, out, err) @?= (ExitSuccess, "", "")
        readUtf8 (tmp </> "chapters/02.gm") >>= (@?= "# 次に\n\n本文。\n"),
      testCase "a chapter already formatted is not rewritten" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        _ <- golemAt tmp ["fmt"]
        readUtf8 (tmp </> "chapters/01.gm") >>= (@?= "# はじめに\n\n本文。\n"),
      testCase "after golem fmt, --check passes with nothing on stdout" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        _ <- golemAt tmp ["fmt"]
        (code, out, _) <- golemAt tmp ["fmt", "--check"]
        (code, out) @?= (ExitSuccess, ""),
      testCase "after golem fmt, a chapter with a lone CR passes golem check without G01003 (golem-fmt ADR 0003)" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp (fmtProject <> [("chapters/01.gm", "# はじめに\r\r本文。\r")])
        (code0, _, err0) <- golemAt tmp ["check"]
        assertBool err0 (code0 /= ExitSuccess && "G01003" `isInfixOf` err0)
        -- the file is named: without arguments, loading the project stops at G01003
        _ <- golemAt tmp ["fmt", "chapters/01.gm"]
        readUtf8 (tmp </> "chapters/01.gm") >>= (@?= "# はじめに\n\n本文。\n")
        -- the project has no style.toml, so check still fails, on other codes
        (_, out, err) <- golemAt tmp ["check"]
        assertBool (out <> err) (not ("G01003" `isInfixOf` (out <> err))),
      testCase "without a manifest: G03016 and 1" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        (code, _, err) <- golemAt tmp ["fmt"]
        code @?= ExitFailure 1
        assertBool err ("error[G03016]: manifest.toml がありません" `isInfixOf` err),
      testCase "a file that is not UTF-8 is left alone with 1" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        BS.writeFile (tmp </> "b.gm") (BS.pack [0xff, 0xfe])
        (code, _, err) <- golemAt tmp ["fmt", "b.gm"]
        (code, err) @?= (ExitFailure 1, "b.gm: UTF-8 として読めないため整形しません\n")
        BS.readFile (tmp </> "b.gm") >>= (@?= BS.pack [0xff, 0xfe]),
      testCase "a file that is not there is G03002 (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        (code, _, err) <- golemAt tmp ["fmt", "nope.gm"]
        code @?= ExitFailure 1
        take 1 (lines err) @?= ["nope.gm:1:1: error[G03002]: ファイルがありません: nope.gm"]
        assertBool err (not ("withBinaryFile" `isInfixOf` err) && not ("backtrace" `isInfixOf` err)),
      testCase "the other files are formatted after a file that is not there (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp [("ok.gm", "本文。  \n")]
        (code, _, err) <- golemAt tmp ["fmt", "nope.gm", "ok.gm"]
        code @?= ExitFailure 1
        assertBool err ("error[G03002]" `isInfixOf` err)
        readUtf8 (tmp </> "ok.gm") >>= (@?= "本文。\n"),
      testCase "a directory is G03002 (golem-cli ADR 0007)" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        createDirectoryIfMissing True (tmp </> "d.gm")
        (code, _, err) <- golemAt tmp ["fmt", "--check", "d.gm"]
        code @?= ExitFailure 1
        assertBool err ("error[G03002]" `isInfixOf` err),
      testCase "a file with the reserved [! is left alone with G01100 and 1 (docs/adr ADR 0115)" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp [("r.gm", "本文   [!foo]   です。\n")]
        (code, _, err) <- golemAt tmp ["fmt", "r.gm"]
        code @?= ExitFailure 1
        assertBool err ("error[G01100]" `isInfixOf` err)
        readUtf8 (tmp </> "r.gm") >>= (@?= "本文   [!foo]   です。\n")
    ]

-- ------------------------------------------------------------------ golem plugin lock / fetch (golem-plugin ADR 0002)

-- | The SHA-256 of "AAA".
hashOfAAA :: String
hashOfAAA = "cb1ad2119d8fafb69566510ee712661f9f14b83385006ef92aec47f523a38358"

-- | A lock that names one plugin by a URL that cannot be reached.
lockOfAAA :: String
lockOfAAA = "[plugins.a]\nurl = \"https://example.invalid/a.wasm\"\nsha256 = \"" <> hashOfAAA <> "\"\n"

-- | Runs golem in a project with a plugin cache of its own.
inPluginProject :: [(FilePath, String)] -> [(FilePath, BS.ByteString)] -> [String] -> (FilePath -> (ExitCode, String, String) -> IO ()) -> IO ()
inPluginProject files cached args check = withSystemTempDirectory "golem-plugin" $ \tmp -> do
  let cache = tmp </> "cache"
  createDirectoryIfMissing True (cache </> "golem/plugins")
  mapM_ (\(p, b) -> BS.writeFile (cache </> "golem/plugins" </> p) b) cached
  createDirectoryIfMissing True (tmp </> "project")
  writeFiles (tmp </> "project") files
  r <- golemWithCache cache (tmp </> "project") args
  check (tmp </> "project") r

pluginTests :: TestTree
pluginTests =
  testGroup
    "golem plugin lock and fetch (golem-plugin ADR 0002)"
    [ testCase "lock with no plugin declared writes an empty plugins.lock and exits with 0" $
        inPluginProject [("manifest.toml", manifestWith [])] [] ["plugin", "lock"] $ \dir (code, _, err) -> do
          (code, err) @?= (ExitSuccess, "")
          BS.readFile (dir </> "plugins.lock") >>= (@?= ""),
      testCase "lock with an HTTP URL: 1, and plugins.lock is left as it was"
        $ inPluginProject
          [ ("manifest.toml", manifestWith [] <> "\n[plugins.ruby]\nurl = \"http://example.invalid/a.wasm\"\n"),
            ("plugins.lock", lockOfAAA)
          ]
          []
          ["plugin", "lock"]
        $ \dir (code, _, err) -> do
          (code, err) @?= (ExitFailure 1, "ruby: HTTPS の URL だけを使えます: http://example.invalid/a.wasm\n")
          readUtf8 (dir </> "plugins.lock") >>= (@?= lockOfAAA),
      testCase "lock skips a plugin of the project's path: nothing to fetch, nothing in plugins.lock (docs/adr/0109)" $
        inPluginProject [("manifest.toml", manifestWith [] <> "\n[plugins.local]\npath = \"plugins/local.wasm\"\n")] [] ["plugin", "lock"] $ \dir (code, _, err) -> do
          (code, err) @?= (ExitSuccess, "")
          BS.readFile (dir </> "plugins.lock") >>= (@?= ""),
      testCase "fetch without plugins.lock has nothing to do and exits with 0" $
        inPluginProject [("manifest.toml", manifestWith [])] [] ["plugin", "fetch"] $ \_ (code, _, err) ->
          (code, err) @?= (ExitSuccess, ""),
      testCase "fetch with a plugins.lock that is not TOML: G06011 at its place in plugins.lock" $
        inPluginProject [("manifest.toml", manifestWith []), ("plugins.lock", "[plugins.a\n")] [] ["plugin", "fetch"] $ \_ (code, _, err) -> do
          code @?= ExitFailure 1
          take 1 (lines err) @?= ["plugins.lock:1:11: error[G06011]: TOML の誤りです: ここに行末は書けません"],
      testCase "fetch of an artifact already in the cache needs no network" $
        inPluginProject [("manifest.toml", manifestWith []), ("plugins.lock", lockOfAAA)] [(hashOfAAA <> ".wasm", "AAA")] ["plugin", "fetch"] $ \_ (code, _, err) ->
          (code, err) @?= (ExitSuccess, ""),
      testCase "fetch of an artifact missing from the cache downloads it, and an HTTP URL is refused" $
        inPluginProject [("manifest.toml", manifestWith []), ("plugins.lock", "[plugins.a]\nurl = \"http://example.invalid/a.wasm\"\nsha256 = \"" <> hashOfAAA <> "\"\n")] [] ["plugin", "fetch"] $ \_ (code, _, err) ->
          (code, err) @?= (ExitFailure 1, "a: HTTPS の URL だけを使えます: http://example.invalid/a.wasm\n"),
      testCase "fetch does not take a cached artifact whose hash differs from plugins.lock"
        $ inPluginProject
          [("manifest.toml", manifestWith []), ("plugins.lock", "[plugins.a]\nurl = \"http://example.invalid/a.wasm\"\nsha256 = \"" <> hashOfAAA <> "\"\n")]
          [(hashOfAAA <> ".wasm", "BBB")]
          ["plugin", "fetch"]
        $ \_ (code, _, err) ->
          -- the cached bytes are refused, so fetch goes to the URL, which is refused in turn
          (code, err) @?= (ExitFailure 1, "a: HTTPS の URL だけを使えます: http://example.invalid/a.wasm\n")
    ]

-- ------------------------------------------------------------------ golem preflight (golem-cli ADR 0006)

preflightTests :: TestTree
preflightTests =
  testGroup
    "golem preflight (golem-cli ADR 0006)"
    [ testCase "no PDF made: 1, and no summary line" $ withSystemTempDirectory "golem-preflight" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        (code, _, err) <- golemAt (tmp </> "book") ["preflight"]
        code @?= ExitFailure 1
        assertBool err ("error[G08002]" `isInfixOf` err)
        assertBool err (not ("プリフライト（" `isInfixOf` err)),
      testCase "the summary of a new project names its preflight.toml, based on print, and counts the errors" $ withSystemTempDirectory "golem-preflight" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        font <- BL.readFile "../golem-font/test/fonts/SourceSansPro-Regular.otf"
        createDirectoryIfMissing True (tmp </> "book/fonts")
        BL.writeFile (tmp </> "book/fonts/SourceSerif4-Regular.otf") font
        (code, _, err) <- golemAt (tmp </> "book") ["preflight"]
        -- the template has a bleed (golem-pdf ADR 0010), and no output intent (G09014)
        code @?= ExitFailure 1
        assertBool err ("G09014" `isInfixOf` err)
        assertBool err (not ("G09010" `isInfixOf` err))
        let summary = last (lines err)
        assertBool summary ("プリフライト（設定: preflight.toml、基にした設定: print）: エラー 1、警告 0。" `isPrefixOf` summary)
    ]
