{-# LANGUAGE CPP #-}

module Main (main) where

import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import InMemoryWritesSpec (inMemoryWritesTests)
import LocaleSpec
#ifdef GOLEM_PLUGINS
import PluginsSpec
#endif
import System.Environment (lookupEnv)
import Test.Tasty

{- | The tests of golem-driver that change the state of the process:
the plugin tests set XDG_CACHE_HOME, and the locale tests set the locale
encoding. The suite is not -threaded, so tasty runs them one after another
and no test reads the state another has half changed; golem-driver-test,
which is -threaded, has none of them (docs/adr/0146).
-}
main :: IO ()
main = enterPackageDirectory >> lookupEnv "XDG_CACHE_HOME" >>= defaultMainReportingSkips . const . tests

-- | The tests, with XDG_CACHE_HOME as it was when the suite started (docs/adr ADR 0072).
tests :: Maybe String -> TestTree
#ifdef GOLEM_PLUGINS
tests cacheHome =
#else
tests _ =
#endif
  testGroup
    "golem-driver: the tests that change the state of the process (docs/adr/0146)"
    ( -- the plugins only with them, as the library (docs/adr ADR 0300)
#ifdef GOLEM_PLUGINS
      [ testGroup "plugins (golem-plugin ADR 0001, 0002)" pluginTests,
        cacheHomeRestored cacheHome
      ]
        <>
#endif
        [ localeTests,
          inMemoryWritesTests
        ]
    )
