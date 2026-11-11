-- | The two CLI paths through the build pipeline (Golem ADR 0337).
module Golem.Cli.BuildCommand (BuildMode (..), runBuild, jsonResult) where

import Data.Text (Text)
import Golem.Driver
import Golem.Syntax
import System.Exit (ExitCode (..))

data BuildMode = CheckOnly | WriteTargets [Target]

runBuild :: FilePath -> BuildMode -> Profile -> CropMarks -> Bool -> Bool -> IO BuildResult
runBuild root mode profile marks quiet verbose =
  let (checkOnly, targets) = case mode of
        CheckOnly -> (True, allTargets)
        WriteTargets [] -> (False, allTargets)
        WriteTargets ts -> (False, ts)
   in build (defaultOptions root) {optTargets = Just targets, optProfile = profile, optCheckOnly = checkOnly, optMarks = marks, optNoNotices = quiet, optVerbose = verbose}

jsonResult :: BuildResult -> (ExitCode, Text)
jsonResult r =
  let ds = brDiagnostics r
   in (if hasErrors ds then ExitFailure 1 else ExitSuccess, renderJson (brSources r) ds)
