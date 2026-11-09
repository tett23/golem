module Main (main) where

import BoxSpec (boxTests)
import GlyphRunsSpec (glyphRunsTests)
import MemoSpec (memoTests)
import RuleShapeSpec (ruleShapeTests)
import TcySpec (tcyTests)
import Test.Tasty
import WrapMarkSpec (wrapMarkTests)

main :: IO ()
main = defaultMain tests

-- | The tests of the modules of golem-typeset that need no evaluation (docs/adr/0192).
tests :: TestTree
tests =
  testGroup
    "golem-typeset"
    [ memoTests,
      testGroup "the shapes of the line styles of a rule (ADR 0028)" ruleShapeTests,
      testGroup "the glyph runs of a box in the order of its text (docs/adr ADR 0227)" glyphRunsTests,
      testGroup "the fit of a tate-chu-yoko in its box (golem-driver ADR 0045)" tcyTests,
      testGroup "the shape and the colour of the wrap mark of inline code (golem-layout ADR 0042)" wrapMarkTests,
      testGroup "the boxes of paragraph styles (docs/adr/0271)" boxTests
    ]
