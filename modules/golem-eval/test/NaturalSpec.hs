{- | The places that take a natural number and the analysis before the
evaluation (docs/adr ADR 0102): G02103 for a negative number, G02104 for
a number that is not an integer, words and expressions alike, and the
types the analysis infers.
-}
module NaturalSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Analysis
import Golem.Eval.Expr (Env (..), evalExpr)
import Golem.Eval.Value
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Syntax
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Support
import Test.Tasty
import Test.Tasty.HUnit hiding (assert)
import Test.Tasty.Hedgehog

-- | The expression of "[= src]".
exprOf :: Text -> A.Located A.Expr
exprOf src =
  let (A.File _ bs, _, ds) = parseAst (FileId 0) ("[= " <> src <> "]\n")
   in case (ds, map A.locValue bs) of
        ([], [A.Paragraph [A.Located _ (A.Expr e)]]) -> e
        other -> error (show other)

-- | The environment of the analysis: n = 3 by @set, and doc.
typeEnv :: Env
typeEnv = Env (Map.fromList [("n", VNat 3)]) Map.empty

inferred :: Text -> Maybe StaticType
inferred = inferExpr typeEnv . exprOf

-- | The codes and messages of the diagnostics of a source.
msgs :: Text -> [(Text, Text)]
msgs src = [(c, m) | (c, m, _, _) <- map diagSite (fst (evalSource baseCtx src))]

codes :: Text -> [Text]
codes = map fst . msgs

-- | The blank lines a source puts out.
blankLines :: Text -> [Integer]
blankLines src = [toInteger n | BlankLines n <- resultBodies (evalResult baseCtx src)]

tests :: TestTree
tests =
  testGroup
    "natural numbers (docs/adr ADR 0102)"
    [ testGroup
        "the analysis infers the type of an expression"
        [ testCase "natural numbers" $
            map inferred ["len(\"a\")", "abs(0 - 3)", "7 % 3", "doc.chapters.count", "n"] @?= replicate 5 (Just (SNum TNat)),
          testCase "integers" $
            map inferred ["3 - 1", "doc.chapters.count - 1", "n - 1"] @?= replicate 3 (Just (SNum TInt)),
          testCase "rationals" $
            inferred "6 / 2" @?= Just (SNum TRat)
        ],
      testCase "a deferred expression with a negative number of digits is G02103 at S0" $
        codes "[= round(1 / 3, 0 - 1) + doc.chapters.count]\n" @?= ["G02103"],
      testCase "a deferred expression whose digits refer to doc has no diagnostic at S0" $
        codes "[= round(1 / 3, doc.chapters.count - 5)]\n" @?= [],
      testCase "a negative argument is G02103 in every place" $
        mapM_
          (\src -> (src, codes src) @?= (src, ["G02103"]))
          [ "@blank-line [= 0 - 1]\n",
            "@need-lines [= 0 - 1]\n",
            "@toc depth=[= 0 - 1]\n",
            "@number [= 0 - 1]\n# a\n",
            "[= round(1.25, 0 - 1)]\n",
            "```haskell numbers=[= 0 - 1]\nx\n```\n"
          ],
      testCase "a word and an expression of the same negative value give the same diagnostic" $ do
        msgs "@blank-line -1\n" @?= [("G02103", "@blank-line の引数には 0 以上の整数を書きます（書かれた値は -1）")]
        msgs "@blank-line [= 0 - 1]\n" @?= msgs "@blank-line -1\n",
      testCase "a number that is not an integer is G02104, with its value" $ do
        msgs "@blank-line 1.5\n" @?= [("G02104", "@blank-line の引数には 0 以上の整数を書きます（書かれた値 1.5 は整数ではありません）")]
        msgs "@blank-line [= 3 / 2]\n" @?= msgs "@blank-line 1.5\n"
        msgs "@blank-line [= 7 / 3]\n" @?= [("G02104", "@blank-line の引数には 0 以上の整数を書きます（書かれた値 7/3 は整数ではありません）")],
      testCase "0 and a word that is no number stay G02092" $ do
        codes "@blank-line 0\n" @?= ["G02092"]
        codes "@blank-line x\n" @?= ["G02092"],
      testCase "a rational of a natural value is taken" $ do
        blankLines "@blank-line [= 4 / 2]\n" @?= [2]
        blankLines "@blank-line 2.0\n" @?= [2],
      testCase "an expression of a name of @set" $
        blankLines "@set n = 3\n\n@blank-line [= n - 1]\n" @?= [2],
      testCase "the digits of round" $ do
        codes "[= round(1.25, 0 - 1)]\n" @?= ["G02103"]
        codes "[= round(1.25, 1.5)]\n" @?= ["G02104"]
        codes "[= round(1.25, 1001)]\n" @?= ["G02086"]
        msgs "[= round(1.25, 0 - 1)]\n" @?= [("G02103", "round の桁数には 0 以上の整数を書きます（書かれた値は -1）")],
      testCase "a negative number-text is set as before" $ do
        codes "[number-text [= 0 - 5]]\n" @?= []
        [n | Paragraph _ is <- resultBodies (evalResult baseCtx "[number-text [= 0 - 5]]\n"), Number _ n _ <- is] @?= [-5],
      testProperty "the constructor of a value is the type the analysis infers" $ property $ do
        e <- forAll genExpr
        case (evalExpr (Env Map.empty Map.empty) (exprOf e), inferExpr typeEnv (exprOf e)) of
          (Right v, Just t) -> do
            annotateShow (v, t)
            constructorType v === Just t
          (Right v, Nothing) -> annotateShow v >> failure
          (Left _, _) -> success
    ]

-- | The static type of the constructor of a number.
constructorType :: Value -> Maybe StaticType
constructorType = \case
  VNat _ -> Just (SNum TNat)
  VInt _ -> Just (SNum TInt)
  VRat _ -> Just (SNum TRat)
  _ -> Nothing

-- | An expression of number literals, +, -, *, /, **, div, %, abs, floor and min.
genExpr :: Gen Text
genExpr =
  Gen.recursive
    Gen.choice
    [ T.pack . show <$> Gen.int (Range.linear 0 20),
      (\a b -> T.pack (show a) <> "." <> T.pack (show b)) <$> Gen.int (Range.linear 0 9) <*> Gen.int (Range.linear 0 9),
      (\a k -> T.pack (show a) <> "e" <> T.pack (show k)) <$> Gen.int (Range.linear 0 9) <*> Gen.int (Range.linear (-2) 2)
    ]
    [ bin "+",
      bin "-",
      bin "*",
      bin "/",
      bin "%",
      (\a -> "(" <> a <> ") ** 2") <$> genExpr,
      (\a -> "(" <> a <> ") ** (0 - 1)") <$> genExpr,
      (\a -> "-(" <> a <> ")") <$> genExpr,
      call1 "abs",
      call1 "floor",
      (\a b -> "div(" <> a <> ", " <> b <> ")") <$> genExpr <*> genExpr,
      (\a b -> "min(" <> a <> ", " <> b <> ")") <$> genExpr <*> genExpr
    ]
  where
    bin op = (\a b -> "(" <> a <> ") " <> op <> " (" <> b <> ")") <$> genExpr <*> genExpr
    call1 f = (\a -> f <> "(" <> a <> ")") <$> genExpr
