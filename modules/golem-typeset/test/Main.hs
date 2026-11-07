module Main (main) where

import MemoSpec (memoTests)
import RuleShapeSpec (ruleShapeTests)
import Test.Tasty

main :: IO ()
main = defaultMain tests

-- | The tests of the modules of golem-typeset that need no evaluation (docs/adr/0192).
tests :: TestTree
tests =
  testGroup
    "golem-typeset"
    [ memoTests,
      testGroup "the shapes of the line styles of a rule (ADR 0028)" ruleShapeTests
    ]
