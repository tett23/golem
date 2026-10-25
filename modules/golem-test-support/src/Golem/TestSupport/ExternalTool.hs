{- | Tests that need an external tool (qpdf, cddl, openssl).

Where the tool is not found, such a test is reported as SKIP with the
reason, instead of passing as if it had checked something. With
@GOLEM_REQUIRE_EXTERNAL_TOOLS=1@, which CI sets, a missing tool is a
failure, so that a runner without the tool cannot pass the check.
Where it is not, each test skipped is counted in the 'SkipCounter' of the
run ("Golem.TestSupport.Skipped"), and the suite writes the counts after
its results (docs/adr ADR 0074).

The test suites of golem-doc, golem-pdf, golem-driver and golem-plugin
use it (docs/adr/0028).
-}
module Golem.TestSupport.ExternalTool
  ( needsTool,
    optionalTool,
  )
where

import Golem.TestSupport.Env (envFlag)
import Golem.TestSupport.ExternalTool.Internal (needsToolWith, optionalToolWith)
import Test.Tasty.Runners (TestTree)

{- | @needsTool name locate tests@: every test of @tests@ runs where
@locate@ finds the tool, and is a SKIP (a failure where tools are
required) where it does not. The tests get the path of the tool.
-}
needsTool :: String -> IO (Maybe FilePath) -> (IO FilePath -> TestTree) -> TestTree
needsTool = needsToolWith toolsRequired

{- | The path of the tool, or 'Nothing' where it is missing and tools are
not required. For a check inside a test that checks other things too;
a missing tool that is required throws, and fails the test.
-}
optionalTool :: String -> IO (Maybe FilePath) -> IO (Maybe FilePath)
optionalTool = optionalToolWith toolsRequired

-- | Whether a missing tool fails the test: @GOLEM_REQUIRE_EXTERNAL_TOOLS=1@.
toolsRequired :: IO Bool
toolsRequired = envFlag "GOLEM_REQUIRE_EXTERNAL_TOOLS"
