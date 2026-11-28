module CitationArgumentSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.CitationArgument
import Golem.Eval.Value (Value (..))
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "citation argument values"
    [ testCase "root ADR 0385 I1: all locator kinds accept one nonnegative number, range or nonempty text" $
        forM_ labels $ \label -> forM_ [VNat 0, VInt 5, VRat 2, VRange 2 5, VRange 2 2, VString "xii"] $ \value ->
          problems [kw 10 (locatorLabelName label) value] @?= [],
      testCase "root ADR 0385 I1: every distinct locator pair points at the conflicting keyword" $
        forM_ [(a, b) | a <- labels, b <- labels, a /= b] $ \(a, b) ->
          problems [kw 10 (locatorLabelName a) (VNat 1), kw 20 (locatorLabelName b) (VNat 2)] @?= [("G02295", at 20)],
      testCase "root ADR 0385 I1: every repeated locator points at the duplicate keyword" $
        forM_ labels $ \label ->
          problems [kw 10 (locatorLabelName label) (VNat 1), kw 20 (locatorLabelName label) (VNat 2)] @?= [("G02296", at 20)],
      testCase "root ADR 0385 I1: unknown keywords point at their names" $
        problems [kw 10 "pages" (VNat 5), kw 20 "unknown" VNil] @?= [("G02297", at 10), ("G02297", at 20)],
      testCase "root ADR 0385 I1: page and general invalid values retain distinct codes and value sites" $
        forM_ labels $ \label -> forM_ invalidValues $ \value ->
          problems [kw 10 (locatorLabelName label) value] @?= [(if label == LocatorPage then "G02148" else "G02298", at 12)],
      testCase "root ADR 0385 I1: reversed locator ranges have their own cause at the value" $
        forM_ labels $ \label ->
          problems [kw 10 (locatorLabelName label) (VRange 5 2)] @?= [("G02106", at 12)],
      testCase "root ADR 0385 I1: mixed keyword errors remain in input order" $
        problems [kw 10 "page" (VNat 1), kw 20 "unknown" VNil, kw 30 "chapter" (VInt (-1)), kw 40 "page" (VNat 2)]
          @?= [("G02297", at 20), ("G02295", at 30), ("G02298", at 32), ("G02296", at 40)],
      testCase "root ADR 0385 I1: affix and form types remain for their own validators" $
        forM_ ["prefix", "suffix", "form"] $ \name -> forM_ (VString "text" : invalidValues) $ \value ->
          problems [kw 10 name value] @?= [],
      testCase "root ADR 0385 I1: each of the 26 locator names retains its label" $
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

labels :: [LocatorLabel]
labels = [minBound .. maxBound]

invalidValues :: [Value]
invalidValues = [VInt (-1), VRat (1 / 2), VString "", VBool True, VNil, VArray [], VHash Map.empty, VRange (-1) 2, VRange 0 (-1)]

at :: Int -> SrcSpan
at start = mkSpan (FileId 7) start (start + 1)

kw :: Int -> Text -> Value -> CitationKeyword
kw start = CitationKeyword (at start) (at (start + 2))

problems :: [CitationKeyword] -> [(Text, SrcSpan)]
problems = map (\d -> (let DiagnosticCode code = diagCode d in code, diagSpan d)) . validateCitationLocatorArguments
