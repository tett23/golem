module ParserSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Parser
import Golem.Parser.CST
import Golem.Syntax
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

fid :: FileId
fid = FileId 0

parseOk :: Text -> Assertion
parseOk src = do
  let (cst, ds) = parse fid src
  render cst @?= src
  assertEqual ("diagnostics for:\n" <> T.unpack src <> "\n" <> T.unpack (pretty cst)) [] (map diagCode ds)

kinds :: Node -> [SyntaxKind]
kinds n = nodeKind n : concat [kinds m | ElemNode m <- nodeChildren n]

-- Fragments that exercise every construct, combined at random.
fragment :: Gen Text
fragment =
  Gen.element
    [ "本文",
      "[",
      "]",
      "[= 1 + 2]",
      "[ruby: 東/京|とう/きょう]",
      "\n",
      "\n\n",
      "# ",
      "- ",
      "+ ",
      "= ",
      "=:",
      "| a | b |",
      "|---|---|",
      "```",
      "@set x = 1",
      "@label a",
      "%%",
      "%%=",
      "\\[",
      "  ",
      "\t",
      "[strong: x",
      "[note id=a: y]",
      "😀",
      "{",
      ":",
      "*[x]"
    ]

tests :: TestTree
tests =
  testGroup
    "parser (ADR 0002-0004)"
    [ testProperty "lossless and total on arbitrary fragments" $ withTests 500 $ property $ do
        src <- forAll (T.concat <$> Gen.list (Range.linear 0 30) fragment)
        let (cst, _) = parse fid src
        render cst === src,
      testProperty "lossless on random unicode" $ withTests 200 $ property $ do
        src <- forAll (Gen.text (Range.linear 0 100) (Gen.frequency [(5, Gen.element (T.unpack "[]=:|@#-+\n %\\{}\"*`ab漢")), (1, Gen.unicode)]))
        render (fst (parse fid src)) === src,
      testCase "paragraphs and inline commands" $
        parseOk "Golem は[ruby: 組/版|くみ/はん]の結果を出力する[note: 決定性。]。\n本書は第[= version]版である。\n%% 図 %%\n",
      testCase "headings" $ parseOk "# はじめに\n\n## 節\n\n### 項\n",
      testCase "attributes and block commands" $
        parseOk "@import common/values.gm as values\n@set version = \"1.0\"\n\n@label intro\n@nonumber\n# はじめに\n\n本文。\n",
      testCase "lists" $ parseOk "- 印刷用の PDF\n- 電子書籍\n  - EPUB\n  - HTML\n\n+ 一\n+ 二\n",
      testCase "definition lists" $
        parseOk "= 決定性\n  同じ入力から同じ出力を得る性質。\n\n= HTTP\n= HyperText Transfer Protocol\n  共有する。\n\n= モナド\n  圏論。\n=:\n  プログラミング。\n",
      testCase "tables" $ parseOk "| 形式 | 用途 |\n|:---|---:|\n| PDF | 印刷 |\n| EPUB | 電子書籍 |\n",
      testCase "code blocks keep their content raw" $ do
        parseOk "```haskell\nmain = putStrLn \"[%%\\\"\n```\n"
        let (cst, _) = parse fid "```\n[x\n```\n"
        assertBool "no command inside code" (NInlineCommand `notElem` kinds cst),
      testCase "figure with caption body" $
        parseOk "@label fig-arch\n@figure images/arch.pdf web=images/arch.png alt=\"構成図\"\n  構成図のキャプション。\n",
      testCase "expressions" $ parseOk "[= -2 ** 2] [= round(2.675, 2)] [= [1, 2]] [= {a: 1, \"b\": true}] [= values.price >= 10]\n",
      testCase "splat and keyword arguments" $ parseOk "[number-text 10 style=tcy] [f *[xs] **[kw]: 本文 | 二つ目]\n",
      testCase "escapes" $ parseOk "\\# 見出しではない \\[ 50% \\\\\n",
      testCase "unclosed bracket is local to its paragraph" $ do
        let src = "前の段落。\n\n壊れた[strong: 段落\n\n後の段落。\n"
            (cst, ds) = parse fid src
        render cst @?= src
        map diagCode ds @?= [DiagnosticCode "G0117"]
        length [() | ElemNode n <- nodeChildren cst, nodeKind n == NParagraph] @?= 3,
      testCase "a bare bracket is an error" $ do
        let (_, ds) = parse fid "本文 [ だけ\n"
        map diagCode ds @?= [DiagnosticCode "G0121"],
      testCase "heading level four is an error and the next block survives" $ do
        let (cst, ds) = parse fid "#### 深すぎる\n\n# 正しい\n"
        map diagCode ds @?= [DiagnosticCode "G0112"]
        assertBool "heading parsed" (NHeading `elem` kinds cst),
      testCase "tab indentation is an error" $ do
        let (_, ds) = parse fid "- a\n\t- b\n"
        map diagCode ds @?= [DiagnosticCode "G0111"],
      testCase "odd indentation at top level is an error" $ do
        let (_, ds) = parse fid " 一つ空けた段落\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G0111"],
      testCase "orphan =: is an error" $ do
        let (_, ds) = parse fid "=:\n  説明\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G0113"],
      testCase "unclosed comment" $ do
        let (_, ds) = parse fid "本文 %% 閉じない\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G0118"],
      testCase "positional after keyword" $ do
        let (_, ds) = parse fid "[f a=1 b]\n"
        map diagCode ds @?= [DiagnosticCode "G0119"],
      testCase "mismatched table cells" $ do
        let (_, ds) = parse fid "| a | b |\n|---|---|\n| 1 |\n"
        map diagCode ds @?= [DiagnosticCode "G0115"],
      testCase "unclosed code block" $ do
        let (_, ds) = parse fid "```\nx\n"
        map diagCode ds @?= [DiagnosticCode "G0116"]
    ]
