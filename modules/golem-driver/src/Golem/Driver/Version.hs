{- | The version of Golem (docs/adr/0004). The VERSION file at the root of
the repository is the one source of the version. scripts/gen-embedded.sh
writes it into "Golem.Driver.Version.Embedded" (docs/adr/0203), so the
version depends only on the source and not on the state of Git at build
time.
-}
module Golem.Driver.Version
  ( golemVersion,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Driver.Version.Embedded (versionText)

-- | The content of VERSION, such as @0.1.0@ or @0.1.0-rc1@.
golemVersion :: Text
golemVersion = T.strip versionText
