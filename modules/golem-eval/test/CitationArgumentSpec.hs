module CitationArgumentSpec (tests) where

import Control.Monad (forM_)
import Golem.Doc.IR
import Golem.Eval.CitationArgument
import Golem.Eval.Value (Value (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "citation argument values"
    [ testCase "root ADR 0385 I1: each of the 26 locator names retains its label" $
        forM_ [minBound .. maxBound] $ \label ->
          decodeCitationArgument (locatorLabelName label) (VNat 5) @?= Just (CitationLocator (Locator label (LocNumber 5))),
      testCase "root ADR 0385 I1: existing page values retain numbers, ranges and text" $ do
        decodeCitationArgument "page" (VInt 0) @?= Just (CitationLocator (Locator LocatorPage (LocNumber 0)))
        decodeCitationArgument "page" (VRat 5) @?= Just (CitationLocator (Locator LocatorPage (LocNumber 5)))
        decodeCitationArgument "chapter" (VRange 2 4) @?= Just (CitationLocator (Locator LocatorChapter (LocRange 2 4)))
        decodeCitationArgument "page" (VString "xii") @?= Just (CitationLocator (Locator LocatorPage (LocText "xii"))),
      testCase "root ADR 0385 I1: prefix and suffix retain literal Unicode and punctuation" $ do
        decodeCitationArgument "prefix" (VString "参照: {x} ") @?= Just (CitationPrefix "参照: {x} ")
        decodeCitationArgument "suffix" (VString "!? ") @?= Just (CitationSuffix "!? "),
      testCase "root ADR 0385 I1: explicit empty affixes are retained" $ do
        decodeCitationArgument "prefix" (VString "") @?= Just (CitationPrefix "")
        decodeCitationArgument "suffix" (VString "") @?= Just (CitationSuffix ""),
      testCase "root ADR 0385 I1: unknown or unconsumed values leave policy to the caller" $ do
        decodeCitationArgument "unknown" (VString "x") @?= Nothing
        decodeCitationArgument "prefix" (VNat 1) @?= Nothing
        decodeCitationArgument "page" (VInt (-1)) @?= Nothing
        decodeCitationArgument "page" (VRat (1 / 2)) @?= Nothing
        decodeCitationArgument "page" (VString "") @?= Nothing
    ]
