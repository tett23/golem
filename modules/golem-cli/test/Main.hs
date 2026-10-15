{- | The exit codes and the Japanese usage messages of golem (golem-cli ADR
0004), and golem --version (docs/adr/0004).
-}
module Main (main) where

import Data.Aeson qualified as J
import Data.ByteString.Lazy qualified as BL
import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver.Explain (catalog)
import Golem.Driver.Version (golemVersion)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

-- | Runs golem in an empty directory; the output is stdout followed by stderr.
golem :: [String] -> IO (ExitCode, String)
golem args = withSystemTempDirectory "golem-cli" $ \tmp -> do
  (code, out, err) <- readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} ""
  pure (code, out <> err)

exitsWith :: ExitCode -> [String] -> TestTree
exitsWith expected args = testCase (unwords ("golem" : args)) $ do
  (code, out) <- golem args
  assertEqual out expected code

-- | English that must not reach the user.
english :: [String]
english =
  [ "Usage:",
    "Available options",
    "Available commands",
    "Invalid option",
    "Invalid argument",
    "Missing:",
    "Did you mean",
    "expects an argument",
    "option --",
    "Show this help text",
    "unknown ",
    "typesetting system",
    "Build the targets",
    "Create a project",
    "Build profile",
    "Diagnostic format"
  ]

-- | Runs golem in an empty directory and keeps stdout and stderr apart.
golemSplit :: [String] -> IO (ExitCode, String, String)
golemSplit args = withSystemTempDirectory "golem-cli" $ \tmp ->
  readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} ""

versionTests :: TestTree
versionTests =
  testGroup
    "golem --version (docs/adr/0004)"
    [ testCase "prints golem and the version on stdout and exits with 0" $ do
        (code, out, err) <- golemSplit ["--version"]
        code @?= ExitSuccess
        out @?= T.unpack ("golem " <> golemVersion <> "\n")
        err @?= "",
      testCase "the version is the content of VERSION" $ do
        v <- T.strip <$> TIO.readFile "../../VERSION"
        (_, out, _) <- golemSplit ["--version"]
        out @?= T.unpack ("golem " <> v <> "\n"),
      testCase "no English in golem --version" $ do
        (_, out, err) <- golemSplit ["--version"]
        case filter (`isInfixOf` (out <> err)) english of
          [] -> pure ()
          found -> assertFailure (show found <> "\n" <> out <> err),
      testCase "golem --help shows --version" $ do
        (_, out) <- golem ["--help"]
        assertBool out ("--version" `isInfixOf` out && "版を表示する" `isInfixOf` out),
      exitsWith (ExitFailure 2) ["build", "--version"]
    ]

messages :: [(String, [String])]
messages =
  [ ("help", ["--help"]),
    ("no-arguments", []),
    ("build-help", ["build", "--help"]),
    ("unknown-option", ["build", "--nope"]),
    ("unknown-command", ["nope"]),
    ("misspelt-command", ["buld"]),
    ("bad-profile", ["build", "--profile", "nope"]),
    ("missing-value", ["build", "--profile"]),
    ("explain-help", ["explain", "--help"]),
    ("explain-unknown-code", ["explain", "G9999"]),
    ("explain-bad-code", ["explain", "nope"])
  ]

tests :: TestTree
tests =
  testGroup
    "golem-cli (ADR 0004)"
    [ testGroup
        "exit codes"
        [ exitsWith (ExitFailure 2) ["build", "--nope"],
          exitsWith (ExitFailure 2) ["nope"],
          exitsWith (ExitFailure 2) ["new", "--language", "fr", "book"],
          exitsWith (ExitFailure 2) ["build", "--profile", "nope"],
          exitsWith (ExitFailure 2) ["build", "--target", "nope"],
          exitsWith (ExitFailure 2) ["inspect", "a.gm", "--as", "nope"],
          exitsWith (ExitFailure 2) [],
          exitsWith ExitSuccess ["--help"],
          testCase "a bad option to golem new creates nothing" $ withSystemTempDirectory "golem-cli" $ \tmp -> do
            (code, _) <- readCreateProcessWithExitCode (proc "golem" ["new", "--language", "fr", "book"]) {cwd = Just tmp} "" >>= \(c, o, e) -> pure (c, o <> e)
            code @?= ExitFailure 2
            doesDirectoryExist (tmp </> "book") >>= assertBool "no directory" . not
        ],
      testGroup
        "messages"
        ( [ goldenVsString name ("test/golden/" <> name <> ".txt") (BL.fromStrict . TE.encodeUtf8 . T.pack . snd <$> golem args)
          | (name, args) <- messages
          ]
            <> [ testCase ("no English in " <> name) $ do
                   (_, out) <- golem args
                   case filter (`isInfixOf` out) english of
                     [] -> pure ()
                     found -> assertFailure (show found <> "\n" <> out)
               | (name, args) <- messages
               ]
        ),
      versionTests,
      testCase "golem fmt leaves @verse alone (golem-fmt ADR 0002)" $ withSystemTempDirectory "golem-cli" $ \tmp -> do
        writeFile (tmp </> "a.gm") "@verse\n  Full fathom five\n"
        (code, _, _) <- readCreateProcessWithExitCode (proc "golem" ["fmt", "--check", "a.gm"]) {cwd = Just tmp} ""
        code @?= ExitSuccess
        (code', _, _) <- readCreateProcessWithExitCode (proc "golem" ["fmt", "a.gm"]) {cwd = Just tmp} ""
        code' @?= ExitSuccess
        readFile (tmp </> "a.gm") >>= (@?= "@verse\n  Full fathom five\n"),
      missingFontTests,
      marksTests,
      explainTests,
      noticeTests,
      -- golem-parser ADR 0010
      testCase "a backslash after the last | of a table row is G0124, not G0110" $
        mapM_
          ( \src -> do
              (code, err) <- golemIn [(p, if p == "a.gm" then src else c) | (p, c) <- syntaxErrorFiles] ["check"]
              assertEqual err (ExitFailure 1) code
              assertBool err ("error[G0124]" `isInfixOf` err && not ("error[G0110]" `isInfixOf` err))
          )
          ["| a | b |\\\n|---|---|\n| c | d |\n", "| a | b |\n|---|---|\n| c | d |\\\n| e | f |\n"]
    ]

-- | Runs golem in a project whose body font is missing (golem-project ADR 0004).
inMissingProject :: [String] -> IO (ExitCode, String)
inMissingProject args = withSystemTempDirectory "golem-cli" $ \tmp -> do
  createDirectoryIfMissing True (tmp </> "chapters")
  TIO.writeFile (tmp </> "manifest.toml") "chapters = [\"chapters/01.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"
  TIO.writeFile (tmp </> "style.toml") "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 12\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n[fonts.body]\nja = \"fonts/missing.otf\"\n"
  TIO.writeFile (tmp </> "chapters/01.gm") "# はじめに\n\n本文。\n"
  (code, _, err) <- readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} ""
  pure (code, err)

missingFontTests :: TestTree
missingFontTests =
  testGroup
    "files of style.toml per target (golem-project ADR 0004)"
    [ testCase "golem check fails with G0802 and G0310" $ do
        (code, err) <- inMissingProject ["check"]
        assertEqual err (ExitFailure 1) code
        assertBool err ("G0802" `isInfixOf` err && "G0310" `isInfixOf` err),
      testCase "golem build --target html succeeds with G0310" $ do
        (code, err) <- inMissingProject ["build", "--target", "html"]
        assertEqual err ExitSuccess code
        assertBool err ("G0310" `isInfixOf` err)
    ]

-- | A project without bleed: a manifest with the HTML and PDF targets and one chapter.
projectFiles :: [(FilePath, String)]
projectFiles =
  [ ( "manifest.toml",
      "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n\n[targets.pdf]\n"
    ),
    ("a.gm", "本文。\n")
  ]

-- | Runs golem in a directory holding the project; the output is stderr.
golemIn :: [(FilePath, String)] -> [String] -> IO (ExitCode, String)
golemIn files args = withSystemTempDirectory "golem-cli" $ \tmp -> do
  mapM_ (\(p, c) -> BL.writeFile (tmp </> p) (BL.fromStrict (TE.encodeUtf8 (T.pack c)))) files
  (code, _, err) <- readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} ""
  pure (code, err)

marksTests :: TestTree
marksTests =
  testGroup
    "--marks (golem-pdf ADR 0004)"
    [ testCase "golem build --marks nope is a usage error" $ do
        (code, out) <- golem ["build", "--marks", "nope"]
        assertEqual out (ExitFailure 2) code
        assertBool out ("未知のトンボの形です: nope" `isInfixOf` out),
      testCase "golem check --marks nope is a usage error" $ do
        (code, out) <- golem ["check", "--marks", "nope"]
        assertEqual out (ExitFailure 2) code
        assertBool out ("未知のトンボの形です: nope" `isInfixOf` out),
      exitsWith (ExitFailure 2) ["build", "--marks"],
      testCase "Japanese marks without bleed: G0702 for PDF, nothing for HTML" $ do
        (code, err) <- golemIn projectFiles ["build", "--target", "pdf", "--marks", "japanese"]
        assertEqual err (ExitFailure 1) code
        assertBool err ("G0702" `isInfixOf` err)
        (code', err') <- golemIn projectFiles ["build", "--target", "html", "--marks", "japanese"]
        assertEqual err' ExitSuccess code'
    ]

-- | golem explain and the hint after the diagnostics (ADR 0005).
explainTests :: TestTree
explainTests =
  testGroup
    "golem explain (ADR 0005)"
    [ testCase "golem explain G0117 prints the section and exits with 0" $ do
        (code, out, _) <- golemSplit ["explain", "G0117"]
        code @?= ExitSuccess
        assertBool out ("## G0117\n" `isPrefixOf` out),
      testCase "the code is case-insensitive" $ do
        (_, upper, _) <- golemSplit ["explain", "G0117"]
        (code, lower, _) <- golemSplit ["explain", "g0117"]
        code @?= ExitSuccess
        lower @?= upper,
      testCase "a retired code is shown and exits with 0" $ do
        (code, out, _) <- golemSplit ["explain", "G0244"]
        code @?= ExitSuccess
        assertBool out ("## G0244\n" `isPrefixOf` out && "- 状態: 廃止" `isInfixOf` out),
      testCase "golem explain lists every code, the retired ones marked" $ do
        (code, out, _) <- golemSplit ["explain"]
        code @?= ExitSuccess
        length (lines out) @?= Map.size catalog
        assertBool out (any (\l -> "G0244  " `isPrefixOf` l && "（廃止）" `isSuffixOf` l) (lines out))
        map (take 5) (lines out) @?= map T.unpack (Map.keys catalog),
      exitsWith (ExitFailure 2) ["explain", "G9999"],
      exitsWith (ExitFailure 2) ["explain", "nope"],
      testCase "golem check with a syntax error ends with the hint" $ do
        (code, err) <- golemIn syntaxErrorFiles ["check"]
        assertEqual err (ExitFailure 1) code
        last (lines err) @?= "コードの説明は golem explain <コード> で表示できます（例: golem explain G0117）"
        assertEqual err 1 (length (filter ("golem explain" `isInfixOf`) (lines err))),
      testCase "golem check --format json writes only JSON" $ do
        (code, err) <- golemIn syntaxErrorFiles ["check", "--format", "json"]
        assertEqual err (ExitFailure 1) code
        assertBool err (isJust (J.decode (BL.fromStrict (TE.encodeUtf8 (T.pack err))) :: Maybe J.Value))
    ]

-- | A project whose only chapter has an unclosed bracket (G0117).
syntaxErrorFiles :: [(FilePath, String)]
syntaxErrorFiles =
  [ ( "manifest.toml",
      "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"
    ),
    ("a.gm", "[strong: 閉じない\n")
  ]

{- | A project with a notice only (G0263). The body font is a file that is
not a font: golem check looks for it and does not read it.
-}
noticeFiles :: [(FilePath, String)]
noticeFiles =
  [ ( "manifest.toml",
      "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n\n[targets.text]\n"
    ),
    ("style.toml", "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 12\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n[fonts.body]\nja = \"a.otf\"\n"),
    ("a.otf", "not a font"),
    ("a.gm", "[tcy: 10]\n")
  ]

-- | The notices with an error (G0222) and a warning (G0205 in prod).
mixedFiles :: [(FilePath, String)]
mixedFiles = [(p, if p == "a.gm" then "[tcy: 10]\n\n[unknown: x] %%= 校正 %%\n" else c) | (p, c) <- noticeFiles]

-- | Runs golem in the project and returns the exit code, stderr and the files under build/.
golemOutputs :: [(FilePath, String)] -> [String] -> IO (ExitCode, String, [(FilePath, BL.ByteString)])
golemOutputs files args = withSystemTempDirectory "golem-cli" $ \tmp -> do
  mapM_ (\(p, c) -> BL.writeFile (tmp </> p) (BL.fromStrict (TE.encodeUtf8 (T.pack c)))) files
  (code, _, err) <- readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} ""
  outs <- mapM (\p -> (p,) <$> BL.readFile (tmp </> "build" </> p)) ["html/a.xhtml", "text/vertical/a.txt", "text/horizontal/a.txt"]
  pure (code, err, outs)

-- | The notices (golem-syntax ADR 0002).
noticeTests :: TestTree
noticeTests =
  testGroup
    "notices (golem-syntax ADR 0002)"
    [ testCase "notices alone exit with 0, in dev and in prod" $
        mapM_
          ( \args -> do
              (code, err) <- golemIn noticeFiles args
              assertEqual (unwords args <> "\n" <> err) ExitSuccess code
              assertBool err ("notice[G0263]" `isInfixOf` err)
          )
          [build, ["check"], ["lint"], build <> ["--profile", "prod"], ["check", "--profile", "prod"], ["lint", "--profile", "prod"]],
      testCase "--no-notices drops the notices and keeps errors and warnings" $
        mapM_
          ( \cmd -> do
              (_, err) <- golemIn mixedFiles (cmd <> ["--profile", "prod", "--no-notices"])
              assertBool err (not ("notice[" `isInfixOf` err))
              assertBool err ("error[G0222]" `isInfixOf` err && "warning[G0205]" `isInfixOf` err)
              (_, json) <- golemIn mixedFiles (cmd <> ["--profile", "prod", "--no-notices", "--format", "json"])
              assertBool json (not ("\"notice\"" `isInfixOf` json))
              assertBool json ("\"G0222\"" `isInfixOf` json && "\"G0205\"" `isInfixOf` json)
              (_, loud) <- golemIn mixedFiles (cmd <> ["--profile", "prod", "--format", "json"])
              assertBool loud ("\"severity\":\"notice\"" `isInfixOf` loud)
          )
          [build, ["check"], ["lint"]],
      testCase "the hint follows notices alone, and not --no-notices" $ do
        (_, err) <- golemIn noticeFiles ["check"]
        last (lines err) @?= "コードの説明は golem explain <コード> で表示できます（例: golem explain G0263）"
        (code, quiet) <- golemIn noticeFiles ["check", "--no-notices"]
        code @?= ExitSuccess
        quiet @?= "",
      testCase "golem build --no-notices writes the same bytes" $ do
        (_, _, loud) <- golemOutputs noticeFiles build
        (_, err, quiet) <- golemOutputs noticeFiles (build <> ["--no-notices"])
        err @?= ""
        quiet @?= loud,
      exitsWith (ExitFailure 2) ["fmt", "--no-notices"],
      exitsWith (ExitFailure 2) ["explain", "--no-notices"]
    ]
  where
    -- the PDF needs a real font, so golem build writes the other targets
    build = ["build", "--target", "html", "--target", "text"]
