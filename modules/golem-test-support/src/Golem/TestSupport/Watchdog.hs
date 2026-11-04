{- | A wall-clock limit for the tests of a suite that does not depend on
the Haskell runtime (docs/adr ADR 0117). Not written yet: the tree is
returned as it is.
-}
module Golem.TestSupport.Watchdog
  ( watchTests,
    watchedName,
  )
where

import Data.List (intercalate)
import Test.Tasty.Providers (TestName)
import Test.Tasty.Runners (TestTree)

{- | The name the watchdog gives a test: the names of its groups, outermost
first, and its own, joined with /.
-}
watchedName :: [TestName] -> TestName -> String
watchedName groups name = intercalate "/" (groups <> [name])

-- | Every test of the tree under the watchdog, with a limit in seconds.
watchTests :: Integer -> TestTree -> TestTree
watchTests _ = id
