{- | The places that take a natural number and the analysis before the
evaluation (docs/adr ADR 0102): G02103 for a negative number, G02104 for
a number that is not an integer, words and expressions alike, and the
types the analysis infers.
-}
module NaturalSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Analysis
import Golem.Eval.Expr (Env (..), evalExpr)
import Golem.Eval.File (Asset (..), EvalContext (..))
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

-- | A context with the file src/Main.hs of three lines, for @listing.
listingCtx :: EvalContext
listingCtx = baseCtx {ctxAssets = Map.fromList [("src/Main.hs", AssetText (FileId 22) "l1\nl2\nl3\n")]}

-- | The codes and messages of a source with src/Main.hs.
listingMsgs :: Text -> [(Text, Text)]
listingMsgs src = [(c, m) | (c, m, _, _) <- map diagSite (fst (evalSource listingCtx src))]

-- | The lines of the code blocks of a source with src/Main.hs, and the lines highlighted.
codeLinesOf :: Text -> [([Text], [Text])]
codeLinesOf src = mapMaybe lns (resultBodies (evalResult listingCtx src))
  where
    lns = \case
      CodeBlock c -> Just (map clText (codeLines c), [clText l | l <- codeLines c, clHighlight l])
      _ -> Nothing

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
      -- the audit of 2026-10-28, F-01: one code for a literal past the limit (docs/adr ADR 0101)
      testCase "a word past the limit of the evaluator is G02086, as the expression is" $ do
        let big = ("G02086", "数が大きすぎます（整数と、分数の分子と分母の絶対値は 2 の 4096 乗未満に限ります）")
        msgs "@blank-line [= 1e1301]\n" @?= [big]
        msgs "@blank-line 1e1301\n" @?= [big]
        msgs "@blank-line 1e-1301\n" @?= [big]
        msgs "@need-lines 1e1301\n" @?= [big]
        msgs "@toc depth=1e1301\n" @?= [big]
        msgs "@blank-line 1e1300\n" @?= [big]
        listingMsgs "@listing src/Main.hs lines=1-1e1301\n" @?= [big]
        listingMsgs "``` highlight=1e1301\na\n```\n" @?= [big]
        listingMsgs "``` numbers=1e1301\na\n```\n" @?= [big],
      -- the audit of 2026-10-28, F-08: the ends of lines= and highlight= take expressions
      testCase "lines= takes a natural number or a range of two, as a word and as an expression" $ do
        codeLinesOf "@listing src/Main.hs lines=2\n" @?= [(["l2"], [])]
        codeLinesOf "@listing src/Main.hs lines=[= 2]\n" @?= [(["l2"], [])]
        codeLinesOf "@listing src/Main.hs lines=[= [1, 2]]\n" @?= [(["l1", "l2"], [])]
        codeLinesOf "@set n = 3\n\n@listing src/Main.hs lines=[= [n - 1, n]]\n" @?= [(["l2", "l3"], [])]
        codeLinesOf "@listing src/Main.hs lines=[= [4 / 2, 3]]\n" @?= [(["l2", "l3"], [])]
        codeLinesOf "@listing src/Main.hs lines=[= \"1-2\"]\n" @?= [(["l1", "l2"], [])]
        codeLinesOf "@listing src/Main.hs lines=2e0-3\n" @?= [(["l2", "l3"], [])],
      testCase "a negative end of lines= is G02103, one not an integer G02104, word and expression alike" $ do
        let neg = [("G02103", "@listing の lines には 0 以上の整数を書きます（書かれた値は -1）")]
        listingMsgs "@listing src/Main.hs lines=-1\n" @?= neg
        listingMsgs "@listing src/Main.hs lines=3--1\n" @?= neg
        listingMsgs "@listing src/Main.hs lines=-1-2\n" @?= neg
        listingMsgs "@listing src/Main.hs lines=[= 0 - 1]\n" @?= neg
        listingMsgs "@listing src/Main.hs lines=[= [1, 0 - 1]]\n" @?= neg
        listingMsgs "@listing src/Main.hs lines=1-1.5\n" @?= [("G02104", "@listing の lines には 0 以上の整数を書きます（書かれた値 1.5 は整数ではありません）")]
        listingMsgs "@listing src/Main.hs lines=[= [1, 3 / 2]]\n" @?= listingMsgs "@listing src/Main.hs lines=1-1.5\n",
      testCase "lines= out of the file, reversed or not a range stays G02037" $ do
        map fst (listingMsgs "@listing src/Main.hs lines=2-9\n") @?= ["G02037"]
        map fst (listingMsgs "@listing src/Main.hs lines=[= [3, 2]]\n") @?= ["G02037"]
        map fst (listingMsgs "@listing src/Main.hs lines=[= [1, 2, 3]]\n") @?= ["G02037"]
        map fst (listingMsgs "@listing src/Main.hs lines=1,2\n") @?= ["G02037"]
        map fst (listingMsgs "@listing src/Main.hs lines=0-1\n") @?= ["G02037"]
        map fst (listingMsgs "@listing src/Main.hs lines=a-2\n") @?= ["G02037"],
      testCase "highlight= takes a natural number or a range of two as an expression" $ do
        codeLinesOf "``` highlight=[= 2]\na\nb\nc\n```\n" @?= [(["a", "b", "c"], ["b"])]
        codeLinesOf "``` highlight=[= [2, 3]]\na\nb\nc\n```\n" @?= [(["a", "b", "c"], ["b", "c"])]
        codeLinesOf "@set n = 1\n\n``` highlight=[= [n, n + 1]]\na\nb\nc\n```\n" @?= [(["a", "b", "c"], ["a", "b"])],
      testCase "a negative end of highlight= or numbers= is G02103, word and expression alike" $ do
        let neg k = [("G02103", "コードブロックの " <> k <> " には 0 以上の整数を書きます（書かれた値は -1）")]
        listingMsgs "``` highlight=-1\na\n```\n" @?= neg "highlight"
        listingMsgs "``` highlight=1,2--1\na\nb\n```\n" @?= neg "highlight"
        listingMsgs "``` highlight=[= [1, 0 - 1]]\na\n```\n" @?= neg "highlight"
        listingMsgs "``` numbers=-1\na\n```\n" @?= neg "numbers"
        listingMsgs "``` numbers=[= 0 - 1]\na\n```\n" @?= neg "numbers",
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
