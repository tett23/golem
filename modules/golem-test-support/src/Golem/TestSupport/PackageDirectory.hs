{- | The working directory of a test suite on wasm32 (docs/adr/0293).

The tests read their files by paths relative to the directory of their
package, as cabal test runs them there, and some reach other packages
(@../golem-font/test/fonts/@). WASI has no working directory of the
process: wasi-libc resolves a relative path from @/@ at first.
scripts/wasm/run-tests.mjs preopens the root of the repository at @/@ and a
fresh temporary directory at @/tmp@, removes it after the suite ends, and
passes @GOLEM_TEST_PACKAGE_DIR=/modules/<package>@; the @main@ of each
suite of the packages of golem.wasm calls 'enterPackageDirectory' first.
-}
module Golem.TestSupport.PackageDirectory
  ( enterPackageDirectory,
  )
where

import Control.Monad (when)
import System.Directory (setCurrentDirectory)
import System.Environment (lookupEnv)
import System.Info (arch)

{- | On wasm32, moves to the directory of @GOLEM_TEST_PACKAGE_DIR@ where
it is set, and stays where it is not set. On the other targets it does
nothing, whatever the environment: cabal test has started the suite in
the directory of its package.
-}
enterPackageDirectory :: IO ()
enterPackageDirectory = when (arch == "wasm32") (lookupEnv "GOLEM_TEST_PACKAGE_DIR" >>= mapM_ setCurrentDirectory)
