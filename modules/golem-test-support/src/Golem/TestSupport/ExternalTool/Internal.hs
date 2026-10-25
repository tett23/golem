{-# LANGUAGE ExistentialQuantification #-}

{- | The functions under 'Golem.TestSupport.ExternalTool.needsTool' and
'Golem.TestSupport.ExternalTool.optionalTool', with whether a missing tool
fails the test given as an argument instead of read from the environment.

This module is for the tests of golem-test-support itself, which check
every combination of a tool found or missing and required or not without
setting the environment. The tests of the other packages do not import
it: they use 'Golem.TestSupport.ExternalTool.needsTool' and
'Golem.TestSupport.ExternalTool.optionalTool'. It is outside the public
interface of the package and may change without notice (docs/adr ADR
0092).
-}
module Golem.TestSupport.ExternalTool.Internal
  ( needsToolWith,
    optionalToolWith,
    missingTool,
  )
where

import Golem.TestSupport.Skipped (SkipCounter (..), countSkipped)
import Test.Tasty.Options (lookupOption)
import Test.Tasty.Providers (IsTest (..), testFailed, testPassed)
import Test.Tasty.Runners (Result (..), TestTree (..))

-- | A test that runs only where its tool is found.
data NeedsTool = forall t. (IsTest t) => NeedsTool (IO Bool) String (IO (Maybe FilePath)) t

instance IsTest NeedsTool where
  run opts (NeedsTool required name locate t) progress =
    locate >>= \case
      Just _ -> run opts t progress
      Nothing -> do
        r <- required
        case lookupOption opts of
          SkipCounter (Just skips) | not r -> countSkipped skips (skippedReason name)
          _ -> pure ()
        pure (missingTool name r)
  testOptions = pure []

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

-- | The reason of the line of the count of the tests of 'needsTool' skipped: @tests skipped: qpdf is not installed (…)@.
skippedReason :: String -> String
skippedReason name = "tests skipped: " <> notInstalled name <> " (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)"

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
