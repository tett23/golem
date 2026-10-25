{- | The environment variables of the tests.

The switches of tests (docs/adr ADR 0074): a switch is on when its value
is @1@, and off otherwise: unset, empty, @0@, @yes@ and @true@ alike.
@GOLEM_REQUIRE_EXTERNAL_TOOLS@ and @GOLEM_PD_BOOKS@ are read this way.

'withEnv' sets a variable for an action and sets it back afterwards
(docs/adr ADR 0072).
-}
module Golem.TestSupport.Env
  ( envFlag,
    envFlagBy,
    withEnv,
  )
where

import Control.Exception (finally)
import System.Environment (lookupEnv, setEnv, unsetEnv)

-- | Whether the switch of the name is on: its value is @1@.
envFlag :: String -> IO Bool
envFlag name = envFlagBy <$> lookupEnv name

-- | Whether a value of a switch turns it on: @1@ only.
envFlagBy :: Maybe String -> Bool
envFlagBy = (== Just "1")

{- | Runs an action with an environment variable set, and sets it back
afterwards, or unsets it where it was not set (docs/adr ADR 0072).
-}
withEnv :: String -> String -> IO a -> IO a
withEnv name value act = do
  old <- lookupEnv name
  (setEnv name value >> act) `finally` maybe (unsetEnv name) (setEnv name) old
