{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE LambdaCase #-}

{- | Tests that need an external tool (qpdf, cddl, openssl).

Where the tool is not found, such a test is reported as SKIP with the
reason, instead of passing as if it had checked something. With
@GOLEM_REQUIRE_EXTERNAL_TOOLS=1@, which CI sets, a missing tool is a
failure, so that a runner without the tool cannot pass the check.

The same module is in the test directory of each package that uses it
(golem-doc, golem-pdf, golem-driver, golem-plugin).
-}
module ExternalTool (needsTool, optionalTool, toolsRequired) where

import System.Environment (lookupEnv)
import Test.Tasty.Providers (IsTest (..), testFailed, testPassed)
import Test.Tasty.Runners (Result (..), TestTree (..))

-- | A test that runs only where its tool is found.
data NeedsTool = forall t. (IsTest t) => NeedsTool String (IO (Maybe FilePath)) t

instance IsTest NeedsTool where
  run opts (NeedsTool name locate t) progress =
    locate >>= \case
      Just _ -> run opts t progress
      Nothing -> missingTool name <$> toolsRequired
  testOptions = pure []

{- | @needsTool name locate tests@: every test of @tests@ runs where
@locate@ finds the tool, and is a SKIP (a failure where tools are
required) where it does not. The tests get the path of the tool.
-}
needsTool :: String -> IO (Maybe FilePath) -> (IO FilePath -> TestTree) -> TestTree
needsTool name locate mk = wrap (mk path)
  where
    path = locate >>= maybe (ioError (userError (notInstalled name))) pure
    wrap = \case
      SingleTest n t -> SingleTest n (NeedsTool name locate t)
      TestGroup n ts -> TestGroup n (map wrap ts)
      other -> other

{- | The path of the tool, or 'Nothing' where it is missing and tools are
not required. For a check inside a test that checks other things too;
a missing tool that is required throws, and fails the test.
-}
optionalTool :: String -> IO (Maybe FilePath) -> IO (Maybe FilePath)
optionalTool name locate =
  locate >>= \case
    Just p -> pure (Just p)
    Nothing -> do
      required <- toolsRequired
      if required then ioError (userError (notInstalled name <> requiredBy)) else pure Nothing

-- | Whether a missing tool fails the test: @GOLEM_REQUIRE_EXTERNAL_TOOLS=1@.
toolsRequired :: IO Bool
toolsRequired = (== Just "1") <$> lookupEnv "GOLEM_REQUIRE_EXTERNAL_TOOLS"

missingTool :: String -> Bool -> Result
missingTool name = \case
  True -> testFailed (notInstalled name <> requiredBy)
  False -> (testPassed (notInstalled name <> "; GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes this a failure")) {resultShortDescription = "SKIP"}

notInstalled :: String -> String
notInstalled name = name <> " is not installed"

requiredBy :: String
requiredBy = ", and GOLEM_REQUIRE_EXTERNAL_TOOLS=1 requires it"
