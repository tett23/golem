{- | Diagnostic sites of the evaluator that no other test reaches:
G02046 for a @style body whose paragraphs all come out empty, and G03020
for an aki amount in a dimension of @style-def.
-}
module DiagnosticSitesSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Parser (parseAst)
import Golem.Parser.SourceSettings
import Golem.Project.Style (LineBreaks (..), defaultStyle)
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

ctx :: EvalContext
ctx =
  EvalContext
    { ctxFile = FileId 1,
      ctxPath = "ch/01.gm",
      ctxProfile = Dev,
      ctxMeta = Map.empty,
      ctxImports = Map.empty,
      ctxSwatches = Set.empty,
      ctxCharStyles = Set.empty,
      ctxParaStyles = Map.fromList [("body", JoinLines), ("verse", KeepLines)],
      ctxDefaultKenten = "sesame",
      ctxCiteKeys = Set.empty,
      ctxAssets = Map.empty,
      ctxPlugins = noPlugins,
      ctxSource = defaultSourceSettings,
      ctxStyle = defaultStyle
    }

-- | The code, message, start and end of each diagnostic of the parser and the evaluator.
diags :: Text -> [(Text, Text, Int, Int)]
diags src =
  let (file, _, pds) = parseAst (FileId 1) src
   in [(code, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- pds <> erDiagnostics (evalFile ctx file), let DiagnosticCode code = diagCode d]

blocks :: Text -> [BlockBody]
blocks src = let (file, _, _) = parseAst (FileId 1) src in map blockBody (docBlocks (erDocument (evalFile ctx file)))

styleBodyTests :: TestTree
styleBodyTests =
  testGroup
    "G02046: a @style body with no paragraph left"
    [ testCase "a keep-lines body whose only line is an unknown command reports G02022 and then G02046 on the @style" $
        diags "@style verse\n  [nope]\n"
          @?= [ ("G02022", "未知のコマンドです: nope", 16, 20),
                ("G02046", "@style の本体に段落がありません", 0, 22)
              ],
      testCase "the @style with no paragraph left makes no block" $
        blocks "@style verse\n  [nope]\n" @?= []
    ]

styleDefTests :: TestTree
styleDefTests =
  testGroup
    "G03020: an aki amount where @style-def wants a dimension (docs/adr ADR 0019)"
    [ testCase "an aki name in indent is G03020 (ADR 0019: indent = 二分)" $
        [c | (c, _, _, _) <- diags "@style-def paragraph letter indent=二分\n\nx\n"] @?= ["G03020"],
      testCase "the message names the value and how to write a dimension" $
        [m | (_, m, _, _) <- diags "@style-def paragraph letter indent=二分\n\nx\n"]
          @?= ["@style-def の値が不正です: アキの量の指定が正しくありません: アキの量の名前と百分率は、アキの量を書く欄でだけ使えます。寸法は 0.5zw や 2mm のように書きます: 二分 (indent)"]
    ]

tests :: TestTree
tests = testGroup "diagnostic sites" [styleBodyTests, styleDefTests]
