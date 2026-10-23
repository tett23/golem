{- | The exit codes and the Japanese usage messages of golem (golem-cli ADR
0004), and golem --version (docs/adr/0004).
-}
module Main (main) where

import CommandsSpec (commandsTests)
import Data.Aeson qualified as J
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isHexDigit)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver.Explain (catalog)
import Golem.Driver.Version (golemVersion)
import Golem.Syntax.Sha256 (sha256)
import LocaleSpec (localeTests)
import RtsSpec (rtsTests)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit
import Text.Printf (printf)

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
        assertBool out ("--version" `isInfixOf` out && "バージョンを表示する" `isInfixOf` out),
      exitsWith (ExitFailure 2) ["build", "--version"]
    ]

messages :: [(String, [String])]
messages =
  [ ("help", ["--help"]),
    ("build-help", ["build", "--help"]),
    ("unknown-option", ["build", "--nope"]),
    ("unknown-command", ["nope"]),
    ("misspelt-command", ["buld"]),
    ("bad-profile", ["build", "--profile", "nope"]),
    ("missing-value", ["build", "--profile"]),
    ("explain-help", ["explain", "--help"]),
    ("explain-unknown-code", ["explain", "G99999"]),
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
        ( [ goldenVsString (name <> "." <> stream) ("test/golden/" <> name <> "." <> stream <> ".txt") (BL.fromStrict . TE.encodeUtf8 . T.pack . pick <$> golemSplit args)
          | (name, args) <- messages,
            (stream, pick) <- [("stdout", \(_, out, _) -> out), ("stderr", \(_, _, err) -> err)]
          ]
            <> [ testCase "golem --help: 0, the usage on stdout, nothing on stderr (golem-cli ADR 0001)" $ do
                   (code, out, err) <- golemSplit ["--help"]
                   code @?= ExitSuccess
                   assertBool "usage on stdout" ("使い方: golem COMMAND" `isPrefixOf` out)
                   err @?= "",
                 testCase "golem with no argument: 2, the usage of --help on stderr, nothing on stdout (golem-cli ADR 0001, 0004)" $ do
                   (_, help, _) <- golemSplit ["--help"]
                   (code, out, err) <- golemSplit []
                   code @?= ExitFailure 2
                   out @?= ""
                   err @?= help
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
      fmtCrTests,
      missingFontTests,
      marksTests,
      preflightTests,
      explainTests,
      tomlMessageTests,
      noticeTests,
      commandsTests,
      localeTests,
      rtsTests,
      testCase "golem lint reports G05001 after the spaces at the end of a line (golem-lint ADR 0002)" $ do
        (_, err) <- golemIn [(p, if p == "a.gm" then "word  \nword\n" else c) | (p, c) <- projectFiles] ["lint"]
        assertBool err ("error[G05001]" `isInfixOf` err),
      -- golem-parser ADR 0010
      testCase "a backslash after the last | of a table row is G01024, not G01010" $
        mapM_
          ( \src -> do
              (code, err) <- golemIn [(p, if p == "a.gm" then src else c) | (p, c) <- syntaxErrorFiles] ["check"]
              assertEqual err (ExitFailure 1) code
              assertBool err ("error[G01024]" `isInfixOf` err && not ("error[G01010]" `isInfixOf` err))
          )
          ["| a | b |\\\n|---|---|\n| c | d |\n", "| a | b |\n|---|---|\n| c | d |\\\n| e | f |\n"]
    ]

-- | A manifest whose chapters are the given files.
crManifest :: [FilePath] -> String
crManifest chs =
  "chapters = ["
    <> T.unpack (T.intercalate ", " [T.pack (show c) | c <- chs])
    <> "]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"

{- | Runs the commands of golem one after another in a directory holding
the project; the exit code, stdout and stderr of each, and the files
afterwards.
-}
golemSteps :: [(FilePath, String)] -> [[String]] -> IO ([(ExitCode, String, String)], [(FilePath, String)])
golemSteps files steps = withSystemTempDirectory "golem-cli" $ \tmp -> do
  mapM_ (\(p, c) -> BL.writeFile (tmp </> p) (BL.fromStrict (TE.encodeUtf8 (T.pack c)))) files
  rs <- mapM (\args -> readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} "") steps
  result <- mapM (\(p, _) -> (p,) . T.unpack . TE.decodeUtf8 <$> BS.readFile (tmp </> p)) files
  pure (rs, result)

-- | golem fmt without arguments and the CR of the sources (golem-fmt ADR 0004).
fmtCrTests :: TestTree
fmtCrTests =
  testGroup
    "golem fmt without arguments fixes CR (golem-fmt ADR 0004)"
    [ testCase "a lone CR in a chapter is fixed, and golem check reports no G01003" $ do
        ([(code, _, err), (_, _, err')], files') <- golemSteps [("manifest.toml", crManifest ["a.gm"]), ("a.gm", "本文。\r次。\n")] [["fmt"], ["check"]]
        assertEqual err ExitSuccess code
        lookup "a.gm" files' @?= Just "本文。\n次。\n"
        assertBool err' (not ("G01003" `isInfixOf` err')),
      testCase "two chapters with CRLF, neither importing the other, are both fixed" $ do
        ([(code, _, err)], files') <- golemSteps [("manifest.toml", crManifest ["a.gm", "b.gm"]), ("a.gm", "一。\r\n二。\r\n"), ("b.gm", "三。\r\n")] [["fmt"]]
        assertEqual err ExitSuccess code
        lookup "a.gm" files' @?= Just "一。\n二。\n"
        lookup "b.gm" files' @?= Just "三。\n",
      testCase "a file read only by @import is fixed too" $ do
        ([(code, _, err)], files') <- golemSteps [("manifest.toml", crManifest ["a.gm"]), ("a.gm", "@import c.gm as c\n\n本文。\n"), ("c.gm", "一。\r\n")] [["fmt"]]
        assertEqual err ExitSuccess code
        lookup "c.gm" files' @?= Just "一。\n"
        lookup "a.gm" files' @?= Just "@import c.gm as c\n\n本文。\n",
      testCase "a CR in manifest.toml is G01003, and nothing is rewritten" $ do
        let files = [("manifest.toml", T.unpack (T.replace "\n" "\r\n" (T.pack (crManifest ["a.gm"])))), ("a.gm", "本文。\r\n")]
        ([(code, _, err)], files') <- golemSteps files [["fmt"]]
        assertEqual err (ExitFailure 1) code
        assertBool err ("error[G01003]" `isInfixOf` err)
        files' @?= files,
      testCase "a CR and another syntax error in a chapter: nothing is rewritten" $ do
        let files = [("manifest.toml", crManifest ["a.gm"]), ("a.gm", "[strong: 閉じない\r\n")]
        ([(code, _, err)], files') <- golemSteps files [["fmt"]]
        assertEqual err (ExitFailure 1) code
        files' @?= files,
      testCase "golem fmt --check shows a chapter with a CR and rewrites nothing" $ do
        let files = [("manifest.toml", crManifest ["a.gm"]), ("a.gm", "本文。\r\n")]
        ([(code, out, err)], files') <- golemSteps files [["fmt", "--check"]]
        assertEqual err (ExitFailure 1) code
        lines out @?= ["a.gm"]
        files' @?= files
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
    [ testCase "golem check fails with G08002 and G03010" $ do
        (code, err) <- inMissingProject ["check"]
        assertEqual err (ExitFailure 1) code
        assertBool err ("G08002" `isInfixOf` err && "G03010" `isInfixOf` err),
      testCase "golem build --target html succeeds with G03010" $ do
        (code, err) <- inMissingProject ["build", "--target", "html"]
        assertEqual err ExitSuccess code
        assertBool err ("G03010" `isInfixOf` err)
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
      testCase "Japanese marks without bleed: G07002 for PDF, nothing for HTML" $ do
        (code, err) <- golemIn projectFiles ["build", "--target", "pdf", "--marks", "japanese"]
        assertEqual err (ExitFailure 1) code
        assertBool err ("G07002" `isInfixOf` err)
        (code', err') <- golemIn projectFiles ["build", "--target", "html", "--marks", "japanese"]
        assertEqual err' ExitSuccess code',
      -- golem check checks the four targets, whatever the targets of the
      -- manifest (golem-pdf ADR 0010); without style.toml it also fails
      -- with G08007, so the test looks at G07002, not at the exit code
      testCase "golem check --marks japanese is G07002 without [targets.pdf] in the manifest (golem-pdf ADR 0010)" $ do
        (_, err) <- golemIn htmlOnlyFiles ["check", "--marks", "japanese"]
        assertBool err ("G07002" `isInfixOf` err),
      testCase "golem check --marks western is not G07002 without [targets.pdf] (golem-pdf ADR 0010)" $ do
        (_, err) <- golemIn htmlOnlyFiles ["check", "--marks", "western"]
        assertBool err (not ("G07002" `isInfixOf` err))
    ]
  where
    htmlOnlyFiles = [(p, if p == "manifest.toml" then T.unpack (T.replace "\n\n[targets.pdf]\n" "\n" (T.pack c)) else c) | (p, c) <- projectFiles]

-- | golem explain and the hint after the diagnostics (ADR 0005).
explainTests :: TestTree
explainTests =
  testGroup
    "golem explain (ADR 0005)"
    [ testCase "golem explain G01017 prints the section and exits with 0" $ do
        (code, out, _) <- golemSplit ["explain", "G01017"]
        code @?= ExitSuccess
        assertBool out ("## G01017\n" `isPrefixOf` out),
      testCase "the code is case-insensitive" $ do
        (_, upper, _) <- golemSplit ["explain", "G01017"]
        (code, lower, _) <- golemSplit ["explain", "g01017"]
        code @?= ExitSuccess
        lower @?= upper,
      testCase "a retired code is shown and exits with 0" $ do
        (code, out, _) <- golemSplit ["explain", "G02044"]
        code @?= ExitSuccess
        assertBool out ("## G02044\n" `isPrefixOf` out && "- 状態: 廃止" `isInfixOf` out),
      testCase "golem explain lists every code, the retired ones marked" $ do
        (code, out, _) <- golemSplit ["explain"]
        code @?= ExitSuccess
        length (lines out) @?= Map.size catalog
        assertBool out (any (\l -> "G02044  " `isPrefixOf` l && "（廃止）" `isSuffixOf` l) (lines out))
        map (take 6) (lines out) @?= map T.unpack (Map.keys catalog),
      testCase "golem explain G02058 prints the section of G02058 (docs/adr 0061)" $ do
        (code, out, _) <- golemSplit ["explain", "G02058"]
        code @?= ExitSuccess
        assertBool out ("## G02058\n" `isPrefixOf` out),
      testCase "a code of four digits is a usage error (docs/adr 0061)" $ do
        (code, out, err) <- golemSplit ["explain", "G0258"]
        code @?= ExitFailure 2
        out @?= ""
        assertBool err ("診断のコードは G と 5 桁の数字です: G0258" `isPrefixOf` err),
      exitsWith (ExitFailure 2) ["explain", "G99999"],
      exitsWith (ExitFailure 2) ["explain", "nope"],
      testCase "golem check with a syntax error ends with the hint" $ do
        (code, err) <- golemIn syntaxErrorFiles ["check"]
        assertEqual err (ExitFailure 1) code
        last (lines err) @?= "コードの説明は golem explain <コード> で表示できます（例: golem explain G01017）"
        assertEqual err 1 (length (filter ("golem explain" `isInfixOf`) (lines err))),
      -- golem-parser ADR 0011
      testCase "golem check reports ##1.5## as G02078" $ do
        (code, err) <- golemIn [(p, if p == "a.gm" then "数は ##1.5## です。\n" else c) | (p, c) <- syntaxErrorFiles] ["check"]
        assertEqual err (ExitFailure 1) code
        assertBool err ("error[G02078]" `isInfixOf` err),
      testCase "golem check --format json writes only JSON" $ do
        (code, err) <- golemIn syntaxErrorFiles ["check", "--format", "json"]
        assertEqual err (ExitFailure 1) code
        assertBool err (isJust (J.decode (BL.fromStrict (TE.encodeUtf8 (T.pack err))) :: Maybe J.Value))
    ]

-- | The TOML messages are Japanese in the output of golem check (golem-project ADR 0007).
tomlMessageTests :: TestTree
tomlMessageTests =
  testGroup
    "TOML messages in Japanese (golem-project ADR 0007)"
    [ testCase "G03001 and G03006 show no message of toml-parser" $ do
        (code, err) <- golemIn [("manifest.toml", T.unpack (T.replace "title = \"T\"\n" "" (T.pack manifestText))), ("a.gm", "本文。\n")] ["check"]
        assertEqual err (ExitFailure 1) code
        assertBool err ("G03001" `isInfixOf` err && "必須のキーがありません: metadata.title" `isInfixOf` err)
        (code', err') <- golemIn [("manifest.toml", manifestText), ("style.toml", "[page]\nsize = \"A5\"\nbindng = \"left\"\n"), ("a.gm", "本文。\n")] ["check"]
        assertEqual err' (ExitFailure 1) code'
        assertBool err' ("G03006" `isInfixOf` err' && "知らないキーです: page.bindng" `isInfixOf` err')
        mapM_
          (\w -> assertBool (w <> " in " <> err <> err') (not (w `isInfixOf` (err <> err'))))
          ["unexpected key", "missing key", "expected ", "lexical error", "parse error"],
      -- golem-project ADR 0008: the errors of style.toml are at their value
      testCase "a padding without a unit is at the value of padding" $ do
        (code, err) <- golemIn [("manifest.toml", manifestText), ("style.toml", "[page]\nsize = \"A5\"\n\n[paragraph-styles.code]\npadding = \"0\"\n"), ("a.gm", "本文。\n")] ["check"]
        assertEqual err (ExitFailure 1) code
        assertBool err (not ("style.toml:1:1" `isInfixOf` err))
        assertBool err ("style.toml:5:11: error[G03006]" `isPrefixOf` err),
      testCase "a paragraph style larger than the grid is at the value of size" $ do
        let style = "[page]\nsize = \"A5\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 40\nlines = 30\nline-pitch = \"16pt\"\nposition = { top = \"14mm\", gutter = \"14mm\" }\n\n[paragraph-styles.body]\nsize = \"30Q\"\n"
        (code, err) <- golemIn [("manifest.toml", manifestText), ("style.toml", style), ("a.gm", "本文。\n")] ["check"]
        assertEqual err (ExitFailure 1) code
        assertBool err ("style.toml:11:8: error[G03011]" `isInfixOf` err)
    ]
  where
    manifestText = "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"

-- | A project whose only chapter has an unclosed bracket (G01017).
syntaxErrorFiles :: [(FilePath, String)]
syntaxErrorFiles =
  [ ( "manifest.toml",
      "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"
    ),
    ("a.gm", "[strong: 閉じない\n")
  ]

{- | A project with a notice only (G02063). The body font is a file that is
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

-- | The notices with an error (G02022) and a warning (G02005 in prod).
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
              assertBool err ("notice[G02063]" `isInfixOf` err)
          )
          [build, ["check"], ["lint"], build <> ["--profile", "prod"], ["check", "--profile", "prod"], ["lint", "--profile", "prod"]],
      testCase "--no-notices drops the notices and keeps errors and warnings" $
        mapM_
          ( \cmd -> do
              (_, err) <- golemIn mixedFiles (cmd <> ["--profile", "prod", "--no-notices"])
              assertBool err (not ("notice[" `isInfixOf` err))
              assertBool err ("error[G02022]" `isInfixOf` err && "warning[G02005]" `isInfixOf` err)
              (_, json) <- golemIn mixedFiles (cmd <> ["--profile", "prod", "--no-notices", "--format", "json"])
              assertBool json (not ("\"notice\"" `isInfixOf` json))
              assertBool json ("\"G02022\"" `isInfixOf` json && "\"G02005\"" `isInfixOf` json)
              (_, loud) <- golemIn mixedFiles (cmd <> ["--profile", "prod", "--format", "json"])
              assertBool loud ("\"severity\":\"notice\"" `isInfixOf` loud)
          )
          [build, ["check"], ["lint"]],
      testCase "the hint follows notices alone, and not --no-notices" $ do
        (_, err) <- golemIn noticeFiles ["check"]
        last (lines err) @?= "コードの説明は golem explain <コード> で表示できます（例: golem explain G02063）"
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

-- ------------------------------------------------------------------ golem preflight (golem-cli ADR 0006)

-- | A Latin book with a real font, 3mm of bleed and an output intent, so that print passes.
preflightProject :: String -> [(FilePath, String)]
preflightProject body =
  [ ("manifest.toml", "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"en\"\ndate = 2026-10-11\n\n[targets.pdf]\n"),
    ("style.toml", "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\nbleed = \"3mm\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 30\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"25mm\", gutter = \"20mm\" }\n\n[fonts.body]\nlatin = \"fonts/latin.otf\"\n\n[color]\nintent = \"intent.icc\"\n"),
    ("intent.icc", "fake profile"),
    ("a.gm", body)
  ]

-- | Runs golem in the project with the font copied in; stdout and stderr apart.
golemPreflight :: [(FilePath, String)] -> [String] -> IO (ExitCode, String, String, FilePath -> IO BL.ByteString)
golemPreflight files = golemPreflightWith files []

golemPreflightWith :: [(FilePath, String)] -> [(FilePath, BL.ByteString)] -> [String] -> IO (ExitCode, String, String, FilePath -> IO BL.ByteString)
golemPreflightWith files bins args = do
  font <- BL.readFile "../golem-font/test/fonts/SourceSansPro-Regular.otf"
  withSystemTempDirectory "golem-cli" $ \tmp -> do
    createDirectoryIfMissing True (tmp </> "fonts")
    BL.writeFile (tmp </> "fonts/latin.otf") font
    mapM_ (\(p, c) -> BL.writeFile (tmp </> p) (BL.fromStrict (TE.encodeUtf8 (T.pack c)))) files
    mapM_ (\(p, b) -> BL.writeFile (tmp </> p) b) bins
    (code, out, err) <- readCreateProcessWithExitCode (proc "golem" args) {cwd = Just tmp} ""
    -- the PDF of golem build in the same project, read before the directory goes
    pdf <- do
      _ <- readCreateProcessWithExitCode (proc "golem" ["build", "--target", "pdf", "--profile", "prod"]) {cwd = Just tmp} ""
      let pdfPath = tmp </> "build/pdf/urn-uuid-11111111-2222-4333-8444-555555555555.pdf"
      exists <- doesFileExist pdfPath
      if exists then BL.readFile pdfPath else pure ""
    pure (code, out, err, const (pure pdf))

preflightTests :: TestTree
preflightTests =
  testGroup
    "golem preflight (golem-cli ADR 0006)"
    [ testCase "no error: 0, and the summary names the PDF built with --profile prod" $ do
        (code, _, err, built) <- golemPreflight (preflightProject "Body text.\n") ["preflight"]
        assertEqual err ExitSuccess code
        let summary = last (lines err)
        assertBool summary ("プリフライト（" `isPrefixOf` summary)
        let digest = takeWhile isHexDigit (T.unpack (T.drop (T.length "SHA-256: ") (snd (T.breakOn "SHA-256: " (T.pack summary)))))
        length digest @?= 64
        pdf <- built ""
        digest @?= sha256Hex (BL.toStrict pdf),
      testCase "warnings only: 0" $ do
        (code, _, err, _) <- golemPreflight (("preflight.toml", "[bleed-size]\nseverity = \"warning\"\nmin = \"5mm\"\n") : preflightProject "Body text.\n") ["preflight"]
        assertEqual err ExitSuccess code
        assertBool err ("warning[G09010]" `isInfixOf` err),
      testCase "G09002: 1" $ do
        (code, _, err, _) <- golemPreflight (preflightProject "Body \xE000 text.\n") ["preflight"]
        assertEqual err (ExitFailure 1) code
        assertBool err ("error[G09002]" `isInfixOf` err),
      exitsWith (ExitFailure 2) ["preflight", "--profile", "dev"],
      exitsWith (ExitFailure 2) ["preflight", "--rules"],
      testCase "--format json: valid, no summary, G09006 with ppi" $ do
        img <- BL.readFile "../golem-pdf/test/fixtures/tiny.jpg"
        let files = preflightProject "# Chapter\n\n@figure tiny.jpg alt=\"t\"\n\nBody text.\n"
        (_, _, err, _) <- golemPreflightWith files [("tiny.jpg", img)] ["preflight", "--format", "json"]
        case J.eitherDecode (BL.fromStrict (TE.encodeUtf8 (T.pack err))) :: Either String J.Value of
          Left e -> assertFailure (e <> "\n" <> err)
          Right _ -> pure ()
        assertBool err (not ("プリフライト（" `isInfixOf` err))
        assertBool err ("\"code\":\"G09006\"" `isInfixOf` err && "\"facts\":{" `isInfixOf` err && "\"ppi\":" `isInfixOf` err),
      testCase "--rules reads a file out of the project, and a missing one is G09001" $ withSystemTempDirectory "golem-rules" $ \other -> do
        writeFile (other </> "printer.toml") "based-on = \"none\"\nname = \"Printer\"\n"
        (code, _, err, _) <- golemPreflight (preflightProject "Body \xE000 text.\n") ["preflight", "--rules", other </> "printer.toml"]
        assertEqual err ExitSuccess code
        assertBool err ("設定: Printer、基にした設定: none" `isInfixOf` err)
        (code', _, err', _) <- golemPreflight (preflightProject "Body text.\n") ["preflight", "--rules", other </> "missing.toml"]
        assertEqual err' (ExitFailure 1) code'
        assertBool err' ("error[G09001]" `isInfixOf` err')
    ]

-- | Lower-case hexadecimal SHA-256.
sha256Hex :: BS.ByteString -> String
sha256Hex = concatMap (printf "%02x") . BS.unpack . sha256
