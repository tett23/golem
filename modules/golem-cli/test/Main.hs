{- | The exit codes and the Japanese usage messages of golem (golem-cli ADR
0004), and golem --version (docs/adr/0004).
-}
module Main (main) where

import Data.ByteString.Lazy qualified as BL
import Data.List (isInfixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver.Version (golemVersion)
import System.Directory (doesDirectoryExist)
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
      versionTests
    ]
