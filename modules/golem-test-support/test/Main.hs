{- | Tests of "Golem.TestSupport.ExternalTool" (docs/adr/0028).

The wrapped tests are run directly with 'run', and whether tools are
required is passed as an argument instead of through the environment
("Golem.TestSupport.ExternalTool.Internal"). Only the tests of the
variable itself set it, with 'withEnv' (docs/adr ADR 0092).
-}
module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (Exception, SomeException, evaluate, throwIO, try)
import Control.Monad (replicateM)
import Data.ByteString qualified as BS
import Data.IORef (modifyIORef, newIORef, readIORef)
import Data.List (isPrefixOf)
import Data.Text qualified as T
import Golem.TestSupport.Bytes
import Golem.TestSupport.Env
import Golem.TestSupport.ExternalTool
import Golem.TestSupport.ExternalTool.Internal
import Golem.TestSupport.Gen
import Golem.TestSupport.Manifest
import Golem.TestSupport.Parallel
import Golem.TestSupport.Skipped
import Golem.TestSupport.TimeLimit
import Hedgehog.Gen qualified as Gen
import System.CPUTime (getCPUTime)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.Options (OptionSet, singleOption)
import Test.Tasty.Providers (IsTest (..))
import Test.Tasty.Runners (Result (..), TestTree (..), resultSuccessful)

main :: IO ()
main =
  defaultMain $
    testGroup
      "golem-test-support"
      [ needsToolTests,
        optionalToolTests,
        requiredByEnvTests,
        envFlagTests,
        withEnvTests,
        parallelTests,
        raceFactorTests,
        hexTests,
        genTextTests,
        manifestTests,
        skippedTests,
        timeLimitTests
      ]

found, missing :: IO (Maybe FilePath)
found = pure (Just "/usr/bin/tool")
missing = pure Nothing

-- | The results of every single test of a tree, in order.
runAll :: TestTree -> IO [(String, Result)]
runAll = runAllWith mempty

-- | 'runAll' with the options given.
runAllWith :: OptionSet -> TestTree -> IO [(String, Result)]
runAllWith opts = \case
  SingleTest n t -> (\r -> [(n, r)]) <$> run opts t (const (pure ()))
  TestGroup _ ts -> concat <$> mapM (runAllWith opts) ts
  _ -> pure []

runOne :: TestTree -> IO Result
runOne tree =
  runAll tree >>= \case
    [(_, r)] -> pure r
    rs -> fail ("expected one test, got " <> show (length rs))

passing :: IO FilePath -> TestTree
passing _ = testCase "inner" (pure ())

failing :: IO FilePath -> TestTree
failing _ = testCase "inner" (assertFailure "inner failure")

needsToolTests :: TestTree
needsToolTests =
  testGroup
    "needsToolWith"
    [ testCase "found, passing: success, not SKIP" $ do
        r <- runOne (needsToolWith (pure False) "tool" found passing)
        assertBool "successful" (resultSuccessful r)
        assertBool "not SKIP" (resultShortDescription r /= "SKIP"),
      testCase "found, failing: failure" $ do
        r <- runOne (needsToolWith (pure False) "tool" found failing)
        assertBool "failed" (not (resultSuccessful r)),
      testCase "found: the test gets the path" $ do
        ref <- newIORef []
        let mk path = testCase "inner" (path >>= \p -> modifyIORef ref (p :))
        r <- runOne (needsToolWith (pure False) "tool" found mk)
        assertBool "successful" (resultSuccessful r)
        readIORef ref >>= (@?= ["/usr/bin/tool"]),
      testCase "missing, not required: SKIP" $ do
        r <- runOne (needsToolWith (pure False) "tool" missing failing)
        assertBool "successful" (resultSuccessful r)
        resultShortDescription r @?= "SKIP"
        resultDescription r @?= "tool is not installed; GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes this a failure",
      testCase "missing, required: failure" $ do
        r <- runOne (needsToolWith (pure True) "tool" missing passing)
        assertBool "failed" (not (resultSuccessful r))
        resultDescription r @?= "tool is not installed, and GOLEM_REQUIRE_EXTERNAL_TOOLS=1 requires it",
      testCase "every single test of nested groups is wrapped" $ do
        let mk p = testGroup "outer" [passing p, testGroup "inner" [failing p, passing p]]
        rs <- runAll (needsToolWith (pure False) "tool" missing mk)
        length rs @?= 3
        map (resultShortDescription . snd) rs @?= ["SKIP", "SKIP", "SKIP"]
        assertBool "all successful" (all (resultSuccessful . snd) rs),
      testCase "missingTool" $ do
        resultShortDescription (missingTool "qpdf" False) @?= "SKIP"
        assertBool "not required: success" (resultSuccessful (missingTool "qpdf" False))
        assertBool "required: failure" (not (resultSuccessful (missingTool "qpdf" True)))
        resultDescription (missingTool "qpdf" True) @?= "qpdf is not installed, and GOLEM_REQUIRE_EXTERNAL_TOOLS=1 requires it"
    ]

optionalToolTests :: TestTree
optionalToolTests =
  testGroup
    "optionalToolWith"
    [ testCase "found: the path" $
        optionalToolWith (pure True) "tool" found >>= (@?= Just "/usr/bin/tool"),
      testCase "missing, not required: Nothing" $
        optionalToolWith (pure False) "tool" missing >>= (@?= Nothing),
      testCase "missing, required: throws" $ do
        r <- try (optionalToolWith (pure True) "tool" missing) :: IO (Either SomeException (Maybe FilePath))
        case r of
          Left _ -> pure ()
          Right v -> assertFailure ("expected an exception, got " <> show v)
    ]

{- | 'needsTool' and 'optionalTool' read @GOLEM_REQUIRE_EXTERNAL_TOOLS@
(docs/adr ADR 0092). The variable is set with 'withEnv' and set back
afterwards: CI runs the tests with it set to @1@. golem-test-support-test
is not -threaded, so nothing else reads it at the same time. The values
in full are the tests of 'envFlagBy'.
-}
requiredByEnvTests :: TestTree
requiredByEnvTests =
  testGroup
    "GOLEM_REQUIRE_EXTERNAL_TOOLS (docs/adr ADR 0092)"
    [ testCase "needsTool, missing, 1: failure" $ do
        r <- withRequired "1" (runOne (needsTool "tool" missing passing))
        assertBool "failed" (not (resultSuccessful r))
        resultDescription r @?= "tool is not installed, and GOLEM_REQUIRE_EXTERNAL_TOOLS=1 requires it",
      testCase "needsTool, missing, 0: SKIP" $ do
        r <- withRequired "0" (runOne (needsTool "tool" missing failing))
        assertBool "successful" (resultSuccessful r)
        resultShortDescription r @?= "SKIP",
      testCase "needsTool, missing, true: SKIP" $ do
        r <- withRequired "true" (runOne (needsTool "tool" missing failing))
        assertBool "successful" (resultSuccessful r)
        resultShortDescription r @?= "SKIP",
      testCase "optionalTool, missing, 1: throws" $ do
        r <- try (withRequired "1" (optionalTool "tool" missing)) :: IO (Either SomeException (Maybe FilePath))
        case r of
          Left _ -> pure ()
          Right v -> assertFailure ("expected an exception, got " <> show v),
      testCase "optionalTool, missing, 0: Nothing" $
        withRequired "0" (optionalTool "tool" missing) >>= (@?= Nothing)
    ]
  where
    withRequired = withEnv "GOLEM_REQUIRE_EXTERNAL_TOOLS"

envFlagTests :: TestTree
envFlagTests =
  testGroup
    "envFlagBy (docs/adr ADR 0074)"
    [ testCase "1: on" $ envFlagBy (Just "1") @?= True,
      testCase "unset: off" $ envFlagBy Nothing @?= False,
      testCase "empty: off" $ envFlagBy (Just "") @?= False,
      testCase "0: off" $ envFlagBy (Just "0") @?= False,
      testCase "yes: off" $ envFlagBy (Just "yes") @?= False,
      testCase "true: off" $ envFlagBy (Just "true") @?= False
    ]

parallelTests :: TestTree
parallelTests =
  testGroup
    "inParallel"
    [ testCase "the results come in the order of the actions" $
        inParallel [pure n | n <- [1 .. 8 :: Int]] >>= (@?= map Right [1 .. 8]),
      testCase "a failing action gives Left with its exception; the others are not affected" $
        inParallel [pure ("a" :: String), ioError (userError "boom"), pure "c"] >>= (@?= [Right "a", Left "user error (boom)", Right "c"]),
      testCase "a result that throws when evaluated gives Left" $ do
        rs <- inParallel [pure [1, 2 :: Int], pure (error "late")]
        case rs of
          [Right [1, 2], Left e] | "late" `isPrefixOf` e -> pure ()
          _ -> assertFailure (show rs)
    ]

{- | The variable only these tests use. golem-test-support-test is not
-threaded, so nothing else reads it at the same time.
-}
withEnvVar :: String
withEnvVar = "GOLEM_TEST_SUPPORT_WITH_ENV"

withEnvTests :: TestTree
withEnvTests =
  testGroup
    "withEnv (docs/adr ADR 0072, ADR 0086)"
    [ testCase "the value is set inside, and the old one comes back afterwards" $ do
        setEnv withEnvVar "old"
        inside <- withEnv withEnvVar "new" (lookupEnv withEnvVar)
        inside @?= Just "new"
        lookupEnv withEnvVar >>= (@?= Just "old")
        unsetEnv withEnvVar,
      testCase "a variable that was not set is unset again afterwards" $ do
        unsetEnv withEnvVar
        inside <- withEnv withEnvVar "new" (lookupEnv withEnvVar)
        inside @?= Just "new"
        lookupEnv withEnvVar >>= (@?= Nothing),
      testCase "the old value comes back when the action throws" $ do
        setEnv withEnvVar "old"
        r <- try (withEnv withEnvVar "new" (throwIO (userError "boom"))) :: IO (Either IOError ())
        either (const (pure ())) (const (assertFailure "expected an exception")) r
        lookupEnv withEnvVar >>= (@?= Just "old")
        unsetEnv withEnvVar,
      testCase "a variable that was not set is unset again when the action throws" $ do
        unsetEnv withEnvVar
        r <- try (withEnv withEnvVar "new" (throwIO (userError "boom"))) :: IO (Either IOError ())
        either (const (pure ())) (const (assertFailure "expected an exception")) r
        lookupEnv withEnvVar >>= (@?= Nothing)
    ]

raceFactorTests :: TestTree
raceFactorTests =
  testGroup
    "raceFactorBy (docs/adr ADR 0075, ADR 0086)"
    ( [ testCase "unset: 1" $ raceFactorBy Nothing @?= Right 1,
        testCase "40: 40" $ raceFactorBy (Just "40") @?= Right 40
      ]
        <> [ testCase (show v <> ": refused") $
               raceFactorBy (Just v) @?= Left ("GOLEM_RACE_TESTS must be an integer of 1 or more, not " <> show v)
           | v <- ["", "0", "07", "x", "1234567"]
           ]
    )

hexTests :: TestTree
hexTests =
  testGroup
    "hex (docs/adr ADR 0087)"
    [ testCase "empty: empty" $ hex BS.empty @?= "",
      testCase "two lower-case digits a byte" $ hex (BS.pack [0x00, 0x0f, 0xff]) @?= "000fff"
    ]

genTextTests :: TestTree
genTextTests =
  testCase "genText: the characters of the set, from 0 to 80 of them (docs/adr ADR 0087)" $ do
    ts <- replicateM 100 (Gen.sample genText)
    let chars = "ab 漢字かな\r\n😀𠮷x" :: String
    assertBool "every character is of the set" (all (T.all (`elem` chars)) ts)
    assertBool "from 0 to 80 characters" (all (\t -> T.length t >= 0 && T.length t <= 80) ts)

{- | The manifests that 'manifestToml' makes, against the literals of the
tests it replaced, copied as they were (docs/adr ADR 0087): changing
'manifestToml' fails these.
-}
manifestTests :: TestTree
manifestTests =
  testGroup
    "manifestToml (docs/adr ADR 0087)"
    [ testCase "testManifest: the manifest of golem-lsp's TableWatchSpec" $
        manifestToml testManifest
          @?= "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n",
      testCase "three targets: the manifest of golem-driver's DiagnosticsSpec" $
        manifestToml testManifest {tmTargets = ["html", "epub", "text"]}
          @?= "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\n",
      testCase "two chapters: golem-cli's manifestWith of a.gm and b.gm" $
        manifestToml testManifest {tmChapters = ["a.gm", "b.gm"]}
          @?= T.pack
            ( "chapters = "
                <> "[\"a.gm\", \"b.gm\"]"
                <> "\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"
            ),
      testCase "sections after the date: the manifest of golem-lsp's creators test" $
        manifestToml
          testManifest
            { tmTitle = "LSP",
              tmExtra = "\n[[metadata.creators]]\nname = \"A\"\nrole = \"author\"\n\n[[metadata.contributors]]\nname = \"B\"\nrole = \"cover-designer\"\n\n[[metadata.printings]]\nedition = 1\nprinting = 1\ndate = 2026-10-16\n"
            }
          @?= "chapters = [\"a.gm\"]\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"LSP\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[[metadata.creators]]\nname = \"A\"\nrole = \"author\"\n\n[[metadata.contributors]]\nname = \"B\"\nrole = \"cover-designer\"\n\n[[metadata.printings]]\nedition = 1\nprinting = 1\ndate = 2026-10-16\n\n[targets.html]\n",
      testCase "testBookId" $ testBookId @?= "urn:uuid:11111111-2222-4333-8444-555555555555"
    ]

skippedTests :: TestTree
skippedTests =
  testGroup
    "the line of the tests skipped (docs/adr ADR 0074)"
    [ testCase "one line for each reason, the count first" $
        skippedLines [("tests skipped: qpdf is not installed (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)", 3)]
          @?= ["3 tests skipped: qpdf is not installed (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)"],
      testCase "nothing skipped: no line" $ skippedLines [] @?= [],
      testCase "the reasons in order" $
        skippedLines [("b", 1), ("a", 2)] @?= ["2 a", "1 b"],
      testCase "a test of a missing tool not required is counted by its name, in the counter of the run" $ do
        skips <- newSkips
        let counted = runAllWith (singleOption (SkipCounter (Just skips)))
        _ <- counted (needsToolWith (pure False) "tool" missing passing)
        _ <- counted (needsToolWith (pure False) "tool" missing failing)
        _ <- counted (needsToolWith (pure True) "tool" missing passing)
        _ <- counted (needsToolWith (pure False) "tool" found passing)
        _ <- optionalToolWith (pure False) "tool" missing
        skippedSoFar skips >>= (@?= [("tests skipped: tool is not installed (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)", 2)]),
      testCase "without a counter nothing is counted" $ do
        skips <- newSkips
        _ <- runAll (needsToolWith (pure False) "tool" missing passing)
        skippedSoFar skips >>= (@?= [])
    ]

-- | The CPU time of the process, in seconds.
cpuNow :: IO Double
cpuNow = (/ 1e12) . fromInteger <$> getCPUTime

-- | The exception an action ends with, or the value it returns.
outcome :: (Exception e) => IO a -> IO (Either e a)
outcome = try

{- | 'withinTimeLimits' (docs/adr ADR 0091). golem-test-support-test is
not -threaded, so the CPU time of the process is the test's.
-}
timeLimitTests :: TestTree
timeLimitTests =
  testGroup
    "withinTimeLimits (docs/adr ADR 0091)"
    [ testCase "a computation that does not end fails by the CPU time, in less than 3 seconds of it" $ do
        t0 <- cpuNow
        start <- evaluate (0 :: Integer)
        r <- outcome (withinTimeLimits (TimeLimits 1 60) (evaluate (length [start ..])))
        t1 <- cpuNow
        case r of
          Left (CpuTimeExceeded 1) -> pure ()
          Left e -> assertFailure ("another limit: " <> show e)
          Right n -> assertFailure ("ended with " <> show n)
        assertBool ("used " <> show (t1 - t0) <> " s") (t1 - t0 < 3),
      testCase "sleeping for 2 seconds does not use the CPU time, and ends" $
        withinTimeLimits (TimeLimits 1 60) (threadDelay 2000000 >> pure "slept") >>= (@?= ("slept" :: String)),
      testCase "sleeping for 60 seconds fails by the wall-clock time, with less than 1 second of CPU time" $ do
        t0 <- cpuNow
        r <- outcome (withinTimeLimits (TimeLimits 60 1) (threadDelay 60000000))
        t1 <- cpuNow
        case r of
          Left (WallTimeExceeded 1) -> pure ()
          Left e -> assertFailure ("another limit: " <> show e)
          Right () -> assertFailure "slept for 60 seconds"
        assertBool ("used " <> show (t1 - t0) <> " s") (t1 - t0 < 1),
      testCase "the value of the action is returned" $
        withinTimeLimits hangLimits (pure (42 :: Int)) >>= (@?= 42),
      testCase "the exception of the action comes out as it is" $ do
        r <- try (withinTimeLimits hangLimits (throwIO (userError "boom") :: IO ()))
        r @?= Left (userError "boom"),
      testCase "the messages" $ do
        show (CpuTimeExceeded 60) @?= "used more than 60 seconds of CPU time"
        show (WallTimeExceeded 300) @?= "took more than 300 seconds of wall-clock time",
      testCase "hangLimits: 60 seconds of CPU time, 300 of wall-clock time" $
        (cpuSeconds hangLimits, wallSeconds hangLimits) @?= (60, 300)
    ]
