{-# LANGUAGE CPP #-}

module Main (main) where

import CallsSpec (callsTests)
import CliSpec
import DiagnosticSitesSpec
import DiagnosticsSpec
import ExceptionsSpec (exceptionsTests)
import FunctionLibrarySpec (functionLibraryTests)
import FunctionsSpec (functionsTests)
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
#ifdef GOLEM_PLUGINS
import NewPlanSpec (newPlanTests)
#endif
import NumberUnitBuildSpec (numberUnitBuildTests)
import PathDrawingSpec (pathDrawingTests)
import SecuritySpec
import Test.Tasty
import UnwritableNumbersSpec (unwritableNumbersTests)
import VarsSpec (varsTests)

main :: IO ()
main = enterPackageDirectory >> defaultMainReportingSkips (const tests)

{- | The tests of diagnostics, functions, plugins, projects and the
commands near the CLI. golem-driver-test was split into four suites, each
with this first group, so that the names of the tests did not change (root
ADR 0416). The suite is -threaded and tasty runs them at the same time:
none of them changes the state of the process (environment variables, the
locale encoding, the current directory). Those that do are in
golem-driver-global-test (GlobalMain.hs, docs/adr/0146).
-}
tests :: TestTree
tests =
  testGroup
    "golem-driver (ADR 0001)"
    ( [ explainTests,
        noticeTests,
        testGroup "project diagnostics (golem-project ADR 0006)" projectDiagnosticTests,
        testGroup "reading stage (golem-parser ADR 0009)" readingTests,
        evalDiagnosticTests,
        functionsTests,
        callsTests,
        pathDrawingTests,
        varsTests,
        unwritableNumbersTests,
        numberUnitBuildTests,
        functionLibraryTests,
        testGroup "output and layout diagnostic codes (golem-driver ADR 0016)" outputDiagnosticTests,
        securityTests,
        exceptionsTests
      ]
        <> newTests
        <> [ testGroup "golem preflight (golem-cli ADR 0006)" preflightTests,
             diagnosticSiteTests
           ]
    )

-- | The tests of golem new, only with the plugins, as the library (docs/adr ADR 0300).
newTests :: [TestTree]
#ifdef GOLEM_PLUGINS
newTests = [newProjectTests, newPlanTests]
#else
newTests = []
#endif
