{-# LANGUAGE ExistentialQuantification #-}

{- | Tests that need an external tool (qpdf, cddl, openssl).

Where the tool is not found, such a test is reported as SKIP with the
reason, instead of passing as if it had checked something. With
@GOLEM_REQUIRE_EXTERNAL_TOOLS=1@, which CI sets, a missing tool is a
failure, so that a runner without the tool cannot pass the check.

The test suites of golem-doc, golem-pdf, golem-driver and golem-plugin
use it (docs/adr/0028).
-}
module Golem.TestSupport.ExternalTool
  ( needsTool,
    optionalTool,
    toolsRequired,
    needsToolWith,
    optionalToolWith,
    missingTool,
    toolsRequiredBy,
  )
where

import System.Environment (lookupEnv)
import Test.Tasty.Providers (IsTest (..), testFailed, testPassed)
import Test.Tasty.Runners (Result (..), TestTree (..))

-- | A test that runs only where its tool is found.
data NeedsTool = forall t. (IsTest t) => NeedsTool (IO Bool) String (IO (Maybe FilePath)) t

instance IsTest NeedsTool where
  run opts (NeedsTool required name locate t) progress =
    locate >>= \case
      Just _ -> run opts t progress
      Nothing -> missingTool name <$> required
  testOptions = pure []

{- | @needsTool name locate tests@: every test of @tests@ runs where
@locate@ finds the tool, and is a SKIP (a failure where tools are
required) where it does not. The tests get the path of the tool.
-}
needsTool :: String -> IO (Maybe FilePath) -> (IO FilePath -> TestTree) -> TestTree
needsTool = needsToolWith toolsRequired

{- | 'needsTool' with whether a missing tool fails the test given as the
first argument instead of read from the environment.
-}
needsToolWith :: IO Bool -> String -> IO (Maybe FilePath) -> (IO FilePath -> TestTree) -> TestTree
needsToolWith required name locate mk = wrap (mk path)
  where
    path = locate >>= maybe (ioError (userError (notInstalled name))) pure
    wrap = \case
      SingleTest n t -> SingleTest n (NeedsTool required name locate t)
      TestGroup n ts -> TestGroup n (map wrap ts)
      other -> other

{- | The path of the tool, or 'Nothing' where it is missing and tools are
not required. For a check inside a test that checks other things too;
a missing tool that is required throws, and fails the test.
-}
optionalTool :: String -> IO (Maybe FilePath) -> IO (Maybe FilePath)
optionalTool = optionalToolWith toolsRequired

{- | 'optionalTool' with whether a missing tool fails the test given as
the first argument instead of read from the environment.
-}
optionalToolWith :: IO Bool -> String -> IO (Maybe FilePath) -> IO (Maybe FilePath)
optionalToolWith required name locate =
  locate >>= \case
    Just p -> pure (Just p)
    Nothing ->
      required >>= \case
        True -> ioError (userError (notInstalled name <> requiresIt))
        False -> pure Nothing

-- | Whether a missing tool fails the test: @GOLEM_REQUIRE_EXTERNAL_TOOLS=1@.
toolsRequired :: IO Bool
toolsRequired = toolsRequiredBy <$> lookupEnv "GOLEM_REQUIRE_EXTERNAL_TOOLS"

-- | Whether the value of @GOLEM_REQUIRE_EXTERNAL_TOOLS@ requires the tools.
toolsRequiredBy :: Maybe String -> Bool
toolsRequiredBy = (== Just "1")

{- | The result of a test whose tool is @name@ and is missing: a failure
where tools are required, a SKIP where they are not.
-}
missingTool :: String -> Bool -> Result
missingTool name = \case
  True -> testFailed (notInstalled name <> requiresIt)
  False -> (testPassed (notInstalled name <> "; GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes this a failure")) {resultShortDescription = "SKIP"}

notInstalled :: String -> String
notInstalled name = name <> " is not installed"

requiresIt :: String
requiresIt = ", and GOLEM_REQUIRE_EXTERNAL_TOOLS=1 requires it"
