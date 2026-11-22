module Main (main) where

import ExportSpec (exportTests)
import FmtSpec (fmtTests)
import Golem.Doc.IR qualified as D
import Golem.Emet.IR qualified as IR
import Golem.Syntax.Span (FileId (..), mkSpan)
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Golem.TestSupport.Watchdog (watchTests)
import IdeSpec (ideTests)
import LanguageSpec (languageTests)
import LintSpec (lintTests)
import RequirementSpec (requirementTests)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Runners (NumThreads (..))

{- | The tests run one at a time, under the watchdog (docs/adr ADR 0207).

On aarch64, GHC's threaded runtime (9.10.3 to 9.14.1, GHC issue #28001)
rarely stops every Haskell thread or applies a null closure when tests
that parse .emet run at the same time in one process. The outermost
'localOption' overrides @-j@, so tasty runs one test at a time. The
binary keeps @-threaded@ and @-N@, so the test that evaluates in
parallel still runs on several cores. A test that runs for more than 300
seconds, or a process that does not end 300 seconds after its last test,
aborts with the name of the test (docs/adr ADR 0117). The restriction
works around a GHC bug and is not a property of Golem: an ADR lifts it
once a GHC that fixes #28001 is in use.
-}
main :: IO ()
main = enterPackageDirectory >> defaultMain (watchTests 300 (localOption (NumThreads 1) tests))

tests :: TestTree
tests =
  testGroup
    "golem-emet"
    [ languageTests,
      requirementTests,
      exportTests,
      lintTests,
      fmtTests,
      ideTests,
      testCase "root ADR 0379 I1: Emet identity preserves both readings and formatting" $ do
        let sp = mkSpan (FileId 1) 0 1
            opts = D.defaultRubyOptions {D.roSide = D.RubyBoth, D.roSize = Just (D.RubySizeRelative (3 / 4))}
            seg = (D.RubySegment [D.Text sp "漢"] (Just "かん")) {D.rsOtherReading = Just "Kan", D.rsOptions = opts}
            input = [D.Ruby sp () [seg]]
            (encoded, carried) = IR.runEnc (IR.encodeInlines input)
        IR.decodeInlines carried sp encoded @?= Right input
    ]
