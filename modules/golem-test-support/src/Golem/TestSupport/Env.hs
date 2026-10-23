{- | The environment variables that switch tests (docs/adr ADR 0074).

A switch is on when its value is @1@, and off otherwise: unset, empty,
@0@, @yes@ and @true@ alike. @GOLEM_REQUIRE_EXTERNAL_TOOLS@ and
@GOLEM_PD_BOOKS@ are read this way.
-}
module Golem.TestSupport.Env
  ( envFlag,
    envFlagBy,
  )
where

import System.Environment (lookupEnv)

-- | Whether the switch of the name is on: its value is @1@.
envFlag :: String -> IO Bool
envFlag name = envFlagBy <$> lookupEnv name

-- | Whether a value of a switch turns it on: @1@ only.
envFlagBy :: Maybe String -> Bool
envFlagBy = (== Just "1")
