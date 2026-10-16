{- | Tests of "Golem.TestSupport.ExternalTool" (docs/adr/0028).

The wrapped tests are run directly with 'run', and whether tools are
required is passed as an argument instead of through the environment.
-}
module Main (main) where

import Control.Exception (SomeException, try)
import Data.IORef (modifyIORef, newIORef, readIORef)
import Golem.TestSupport.ExternalTool
import Test.Tasty (TestTree, defaultMain, testGroup)
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
        requiredTests
      ]

found, missing :: IO (Maybe FilePath)
found = pure (Just "/usr/bin/tool")
missing = pure Nothing

-- | The results of every single test of a tree, in order.
runAll :: TestTree -> IO [(String, Result)]
runAll = \case
  SingleTest n t -> (\r -> [(n, r)]) <$> run mempty t (const (pure ()))
  TestGroup _ ts -> concat <$> mapM runAll ts
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
