{- | Tests of "Golem.TestSupport.ExternalTool" (docs/adr/0028).

The wrapped tests are run directly with 'run', and whether tools are
required is passed as an argument instead of through the environment.
-}
module Main (main) where

import Control.Exception (SomeException, try)
import Data.IORef (modifyIORef, newIORef, readIORef)
import Golem.TestSupport.Env
import Golem.TestSupport.ExternalTool
import Golem.TestSupport.Skipped
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.Options (OptionSet, singleOption)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.Providers (IsTest (..))
import Test.Tasty.Runners (Result (..), TestTree (..), resultSuccessful)

main :: IO ()
main =
  defaultMain $
    testGroup
      "golem-test-support"
      [ needsToolTests,
        optionalToolTests,
        requiredTests,
        envFlagTests,
        skippedTests
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

requiredTests :: TestTree
requiredTests =
  testGroup
    "toolsRequiredBy"
    [ testCase "1: required" $ toolsRequiredBy (Just "1") @?= True,
      testCase "unset: not required" $ toolsRequiredBy Nothing @?= False,
      testCase "0: not required" $ toolsRequiredBy (Just "0") @?= False,
      testCase "empty: not required" $ toolsRequiredBy (Just "") @?= False,
      testCase "true: not required" $ toolsRequiredBy (Just "true") @?= False
    ]

envFlagTests :: TestTree
envFlagTests =
  testGroup
    "envFlagBy (docs/adr ADR 0074)"
    [ testCase "1: on" $ envFlagBy (Just "1") @?= True,
      testCase "unset: off" $ envFlagBy Nothing @?= False,
      testCase "empty: off" $ envFlagBy (Just "") @?= False,
      testCase "0: off" $ envFlagBy (Just "0") @?= False,
      testCase "yes: off" $ envFlagBy (Just "yes") @?= False
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
