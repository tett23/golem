{- | The exit codes and the Japanese usage messages of golem (golem-cli ADR
0004), and golem --version (docs/adr/0004).
-}
module Main (main) where

import Control.Monad (filterM)
import Data.ByteString.Lazy qualified as BL
import Data.Char (isDigit)
import Data.List (isInfixOf, isSuffixOf, nub, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver.Version (golemVersion)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
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
    ("missing-value", ["build", "--profile"])
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
      diagnosticsDocTests
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

{- | Every diagnostic code in the sources has a section in docs/diagnostics.md
(the codes that golem explain will use). Paths are relative to the package
directory, where cabal runs the tests.
-}
diagnosticsDocTests :: TestTree
diagnosticsDocTests =
  testGroup
    "docs/diagnostics.md"
    [ testCase "every code in the sources has a heading" $ do
        used <- sourceCodes
        documented <- docCodes
        assertBool "no code found in the sources" (not (null used))
        case filter (`notElem` documented) used of
          [] -> pure ()
          missing -> assertFailure ("codes missing from docs/diagnostics.md: " <> unwords (map T.unpack missing)),
      testCase "the headings are unique and in order" $ do
        documented <- docCodes
        documented @?= sort (nub documented)
    ]

sourceCodes :: IO [T.Text]
sourceCodes = do
  pkgs <- listDirectory "../../modules"
  let roots = ["../../modules" </> p </> "src" | p <- pkgs] <> ["../../modules/golem-cli/app"]
  files <- concat <$> (filterM doesDirectoryExist roots >>= mapM haskellFiles)
  codes <- mapM (fmap quotedCodes . TIO.readFile) files
  pure (sort (nub (concat codes)))

haskellFiles :: FilePath -> IO [FilePath]
haskellFiles dir = do
  entries <- map (dir </>) <$> listDirectory dir
  dirs <- filterM doesDirectoryExist entries
  nested <- concat <$> mapM haskellFiles dirs
  pure ([e | e <- entries, ".hs" `isSuffixOf` e, e `notElem` dirs] <> nested)

-- | The strings @"G@ followed by four digits and @"@.
quotedCodes :: T.Text -> [T.Text]
quotedCodes src =
  [ code
  | (_, rest) <- T.breakOnAll "\"G" src,
    let code = T.take 5 (T.drop 1 rest),
    isCode code,
    T.take 1 (T.drop 6 rest) == "\""
  ]

isCode :: T.Text -> Bool
isCode t = T.length t == 5 && T.take 1 t == "G" && T.all isDigit (T.drop 1 t)

docCodes :: IO [T.Text]
docCodes = do
  doc <- TIO.readFile "../../docs/diagnostics.md"
  pure [c | l <- T.lines doc, Just rest <- [T.stripPrefix "## " l], let c = T.strip rest, isCode c]
