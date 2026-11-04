{-# LANGUAGE CApiFFI #-}

{- | A wall-clock limit for the tests of a suite that does not depend on
the Haskell runtime (docs/adr ADR 0117).

'watchTests' records each test of a tree in a table in C when it starts
and when it ends. A POSIX thread of its own reads the table once a
second. When a test has run for longer than the limit, or when no test
has run for longer than the limit since the last one ended (a process
that does not exit), it writes to the standard error the names of the
tests that run, how long ago the Haskell runtime last ran a thread, and
aborts the process:

> watchdog: "group/name" has run for more than 300 seconds of wall-clock time
> watchdog: the Haskell runtime last ran a thread 812.3 seconds ago (it is stuck, not only the tests)
> watchdog: aborting the process

The first test starts a Haskell thread that tells the watchdog every 0.1
second that the runtime runs; the runtime is called stuck when it has
not for 2 seconds. A stuck runtime and tests that wait for each other
are different bugs, and the line tells them apart.

The thread takes no capability and calls no Haskell, so it fires when
every Haskell thread waits, when the runtime itself waits for a garbage
collection that never starts, and on SIGTERM-deaf processes. tasty's
'Test.Tasty.mkTimeout' and "Golem.TestSupport.TimeLimit" need a running
runtime and cannot.

The limit only detects a suite that does not end (docs/adr ADR 0073): a
test that ends within it is not fast for that.
-}
module Golem.TestSupport.Watchdog
  ( watchTests,
    watchedName,
  )
where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (bracket)
import Control.Monad (forever, void, when)
import Data.Coerce (coerce)
import Data.List (intercalate)
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt (..), CLong (..))
import Test.Tasty.Providers (IsTest (..), TestName)
import Test.Tasty.Runners (TestTree (..))

foreign import capi unsafe "golem_watchdog.h golem_watchdog_start" c_start :: CLong -> IO CInt

foreign import capi unsafe "golem_watchdog.h golem_watchdog_enter" c_enter :: CString -> IO CInt

foreign import capi unsafe "golem_watchdog.h golem_watchdog_leave" c_leave :: CInt -> IO ()

foreign import capi unsafe "golem_watchdog.h golem_watchdog_beat" c_beat :: IO ()

-- | A test that the watchdog sees under a name: the names of its groups and its own, joined with /.
data Watched t = Watched Integer String t

instance (IsTest t) => IsTest (Watched t) where
  run opts (Watched limit name t) progress = do
    started <- c_start (fromInteger limit)
    when (started < 0) (ioError (userError "watchTests: the watchdog thread could not be started"))
    -- the first test starts the heartbeat, which tells a stuck runtime from stuck tests
    when (started == 1) (void (forkIO (forever (c_beat >> threadDelay 100000))))
    bracket (withCString name c_enter) c_leave $ \slot -> do
      when (slot < 0) (ioError (userError "watchTests: more than 1024 tests run at once"))
      run opts t progress

  -- the options of the test inside: Tagged's type is phantom, so coerce changes it
  testOptions = coerce (testOptions @t)

{- | The name the watchdog gives a test: the names of its groups, outermost
first, and its own, joined with /.
-}
watchedName :: [TestName] -> TestName -> String
watchedName groups name = intercalate "/" (groups <> [name])

{- | Every test of the tree under the watchdog, with a limit in seconds
(the first limit of a process is kept). The tree is otherwise the same.
-}
watchTests :: Integer -> TestTree -> TestTree
watchTests limit = go []
  where
    go groups = \case
      SingleTest name t -> SingleTest name (Watched limit (watchedName groups name) t)
      TestGroup name ts -> TestGroup name (map (go (groups <> [name])) ts)
      PlusTestOptions f t -> PlusTestOptions f (go groups t)
      WithResource spec k -> WithResource spec (go groups . k)
      AskOptions k -> AskOptions (go groups . k)
      After d p t -> After d p (go groups t)
