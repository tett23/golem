-- | The namespace vars of [vars] of manifest.toml (docs/adr/0185).
module VarsSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Project.Manifest (ProjectVar (..))
import Golem.Syntax (FileId (..), diagMessage)
import Support
import Test.Tasty
import Test.Tasty.HUnit

vars :: Map.Map Text ProjectVar
vars =
  Map.fromList
    [ ("product", VarString "Golem"),
      ("count", VarInteger 3),
      ("minus", VarInteger (-2)),
      ("beta", VarBool True),
      ("released", VarDate (read "2026-11-06")),
      ("list", VarArray [VarString "a", VarInteger 1]),
      ("author", VarTable (Map.fromList [("short", VarString "tett23")]))
    ]

ctxAt :: Int -> FilePath -> EvalContext
ctxAt n path = baseCtx {ctxFile = FileId n, ctxPath = path, ctxVars = projectVarValues vars}

-- | The texts of the blocks of a source.
textsOf :: EvalContext -> Text -> [[Text]]
textsOf c src = map texts (resultBodies (evalResult c src))
  where
    texts = \case
      Paragraph _ is -> [T.concat [t | Text _ t <- is]]
      Heading _ _ is -> [T.concat [t | Text _ t <- is]]
      _ -> []

codesOf :: Text -> [(Text, Text)]
codesOf src = [(diagCodeText d, diagMessage d) | d <- fst (evalSource (ctxAt 1 "a.gm") src)]

tests :: TestTree
tests =
  testGroup
    "[vars] as the namespace vars (docs/adr/0185)"
    [ testCase "the TOML values become values of expressions" $
        projectVarValues vars
          @?= Map.fromList
            [ ("product", VString "Golem"),
              ("count", VNat 3),
              ("minus", VInt (-2)),
              ("beta", VBool True),
              ("released", VString "2026-11-06"),
              ("list", VArray [VString "a", VNat 1]),
              ("author", VHash (Map.fromList [("short", VString "tett23")]))
            ],
      testCase "two chapter files read vars.product alike, without @import" $ do
        textsOf (ctxAt 1 "a.gm") "[= vars.product] の使い方\n" @?= [["Golem の使い方"]]
        textsOf (ctxAt 2 "b.gm") "[= vars.product] [= vars.count]\n" @?= [["Golem 3"]],
      testCase "vars.product is evaluated in a heading (S0)" $
        textsOf (ctxAt 1 "a.gm") "# [= vars.product] 入門\n" @?= [["Golem 入門"]],
      testCase "@set product and vars.product are different names" $
        textsOf (ctxAt 1 "a.gm") "@set product = \"x\"\n\n[= product] [= vars.product]\n" @?= [["x Golem"]],
      testCase "vars is a reserved word: G02023" $ do
        map fst (codesOf "@set vars = 1\n") @?= ["G02023"]
        map fst (codesOf "@import a.gm as vars\n") @?= ["G02023"],
      testCase "a key not in [vars] is G02002" $
        codesOf "[= vars.missing]\n" @?= [("G02002", "未定義の名前 missing です")],
      testCase "vars.author.short reads a value in a table" $
        textsOf (ctxAt 1 "a.gm") "[= vars.author.short]\n" @?= [["tett23"]],
      testCase "without [vars] vars is an empty namespace" $
        [diagCodeText d | d <- fst (evalSource baseCtx "[= vars.product]\n")] @?= ["G02002"]
    ]
