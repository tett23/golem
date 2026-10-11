module CSTSpec (tests, genNode) where

import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Parser.CST
import Golem.Syntax.Span
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit hiding (assert)
import Test.Tasty.Hedgehog

genToken :: Gen Element
genToken =
  token
    <$> Gen.element [KText, KWhitespace, KNewline, KComment, KLBracket]
    <*> (T.pack <$> Gen.list (Range.linear 0 6) (Gen.element ("a 漢😀\n[" :: String)))

genNode :: Gen Node
genNode =
  Gen.recursive
    Gen.choice
    [node <$> Gen.element [NParagraph, NFile] <*> Gen.list (Range.linear 0 5) genToken]
    [ node
        <$> Gen.element [NParagraph, NHeading, NInlineCommand, NFile]
        <*> Gen.list (Range.linear 0 5) (Gen.choice [genToken, ElemNode <$> genNode])
    ]

nodesOf :: Node -> [Node]
nodesOf n = n : concat [nodesOf m | ElemNode m <- nodeChildren n]

tests :: TestTree
tests =
  testGroup
    "CST (ADR 0001)"
    [ testProperty "width equals the sum of children" $ property $ do
        n <- forAll genNode
        assert (all (\m -> nodeWidth m == sum (map elementWidth (nodeChildren m))) (nodesOf n)),
      testProperty "width counts UTF-8 bytes of the rendering" $ property $ do
        n <- forAll genNode
        nodeWidth n === BS.length (TE.encodeUtf8 (render n)),
      testProperty "token positions tile the rendering without gaps" $ property $ do
        n <- forAll genNode
        let toks = [p | p <- withPositions (FileId 0) n, Just _ <- [posText p]]
            starts = map (spanStart . posSpan) toks
            ends = map (spanEnd . posSpan) toks
        case (starts, reverse ends) of
          (s0 : _, eLast : _) -> do
            s0 === 0
            drop 1 starts === take (length ends - 1) ends
            eLast === nodeWidth n
          _ -> nodeWidth n === 0,
      testProperty "every child span lies within its parent" $ property $ do
        n <- forAll genNode
        case withPositions (FileId 0) n of
          root : rest -> assert (all (spanContains (posSpan root) . posSpan) rest)
          [] -> failure,
      testCase "pretty form" $ do
        let n = node NParagraph [token KText "漢字", ElemNode (node NInlineCommand [token KLBracket "[", token KIdent "b"])]
        pretty n
          @?= T.unlines
            [ "NParagraph@0..8",
              "  KText@0..6 \"漢字\"",
              "  NInlineCommand@6..8",
              "    KLBracket@6..7 \"[\"",
              "    KIdent@7..8 \"b\""
            ]
    ]
