module Main (main) where

import Data.Ratio ((%))
import ExportSpec (exportTests)
import FmtSpec (fmtTests)
import GmFigureSpec (gmFigureTests)
import Golem.Doc.IR qualified as D
import Golem.Emet.IR qualified as IR
import Golem.Syntax.Span (FileId (..), mkSpan)
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Golem.TestSupport.Watchdog (watchTests)
import IdeSpec (ideTests)
import LanguageSpec (languageTests)
import LintSpec (lintTests)
import RequirementSpec (requirementTests)
import Support qualified as S
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
    [ testCase "root ADR 0479 I4: Emet identity preserves both TCY contents" $ do
        let sp = mkSpan (FileId 1) 0 1
            input = [D.Tcy sp (D.TcyLiteral "001"), D.Tcy sp (D.TcyNumber (1 % 3))]
            (encoded, carried) = IR.runEnc (IR.encodeInlines input)
        IR.decodeInlines carried sp encoded @?= Right input,
      testCase "root ADR 0479 I4: an actual Emet identity keeps both TCY contents" $ do
        let sp = S.callSpan
            input = [D.Tcy sp (D.TcyLiteral "001"), D.Tcy sp (D.TcyNumber (1 % 3))]
            (encoded, carried) = IR.runEnc (IR.encodeInlines input)
        result <- S.call "identity :: Inlines -> Inlines\nidentity xs = xs\n" "identity" [encoded] >>= S.ok
        IR.decodeInlines carried sp result @?= Right input,
      testCase "root ADR 0479 I3, I4: Emet constructs literal and normalized numeric TCY" $ do
        result <- S.call "make :: Inlines\nmake = [Inline.Tcy (Inline.TcyLiteral \"001\"), Inline.Tcy (Inline.TcyNumber (1 / 10))]\n" "make" [] >>= S.ok
        IR.decodeInlines IR.emptyCarried S.callSpan result @?= Right [D.Tcy S.callSpan (D.TcyLiteral "001"), D.Tcy S.callSpan (D.TcyNumber (1 % 10))],
      testCase "root ADR 0479 I3: Emet Number TateChuYoko is rejected" $ do
        result <- S.call "make :: Inlines\nmake = [Inline.Number 12 (Just Inline.TateChuYoko)]\n" "make" [] >>= S.ok
        case IR.decodeInlines IR.emptyCarried S.callSpan result of
          Left _ -> pure ()
          Right nodes -> assertFailure (show nodes),
      languageTests,
      requirementTests,
      exportTests,
      lintTests,
      fmtTests,
      gmFigureTests,
      ideTests,
      testCase "root ADR 0379 I1: Emet identity preserves both readings and formatting" $ do
        let sp = mkSpan (FileId 1) 0 1
            opts = D.defaultRubyOptions {D.roSide = D.RubyBoth, D.roSize = Just (D.RubySizeRelative (3 / 4))}
            seg = (D.RubySegment [D.Text sp "漢"] (Just "かん")) {D.rsOtherReading = Just "Kan", D.rsOptions = opts}
            input = [D.Ruby sp () [seg]]
            (encoded, carried) = IR.runEnc (IR.encodeInlines input)
        IR.decodeInlines carried sp encoded @?= Right input
    ]
