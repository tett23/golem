{-# LANGUAGE TemplateHaskell #-}

{- | The version of Golem (docs/adr/0004). The VERSION file at the root of
the repository is the one source of the version; it is embedded when
compiling, so the version depends only on the source and not on the state
of Git at build time.
-}
module Golem.Driver.Version
  ( golemVersion,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Language.Haskell.TH (litE, stringL)
import Language.Haskell.TH.Syntax (addDependentFile, runIO)

-- | The content of VERSION, such as @0.1.0@ or @0.1.0-rc1@.
golemVersion :: Text
golemVersion =
  T.strip
    ( T.pack
        $( do
             -- modules/golem-driver/VERSION links to VERSION at the root
             let path = "VERSION"
             addDependentFile path
             runIO (readFile path) >>= litE . stringL
         )
    )
