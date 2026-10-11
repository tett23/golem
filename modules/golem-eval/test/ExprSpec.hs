module ExprSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Expr
import Golem.Eval.Number
import Golem.Eval.Value
import Golem.Parser (parseAst)
import Golem.Parser.AST
import Golem.Syntax
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit hiding (assert)
import Test.Tasty.Hedgehog

-- Parse "[= src]" and return the expression.
exprOf :: Text -> Located Expr
exprOf src =
  let (File _ bs, _, ds) = parseAst (FileId 0) ("[= " <> src <> "]\n")
   in case (ds, map locValue bs) of
        ([], [Paragraph [Located _ (Expr e)]]) -> e
        other -> error (show other)

env :: Env
env =
  Env
    (Map.fromList [("x", VInt 10)])
    (Map.fromList [("values", Map.fromList [("price", VInt 100)])])

ev :: Text -> Either Text Value
ev src = either (Left . (\(DiagnosticCode c) -> c) . diagCode) Right (evalExpr env (exprOf src))

shown :: Text -> Either Text Text
shown src = case ev src of
  Left c -> Left c
  Right v -> either (Left . T.pack . show) Right (embedValue (mkSpan (FileId 0) 0 0) v)

tests :: TestTree
tests =
  testGroup
    "expressions and numerics (ADR 0001)"
    [ testCase "boundary values" $ do
        shown "round(2.675, 2)" @?= Right "2.68"
        shown "round(-2.5)" @?= Right "-3"
        shown "fixed(1.5, 2)" @?= Right "1.50"
        shown "10 / 2" @?= Right "5"
        shown "0.01" @?= Right "0.01"
        shown "1000000000000000000000.0" @?= Right "1000000000000000000000"
        shown "-0.0" @?= Right "0"
        shown "0.1 + 0.2" @?= Right "0.30000000000000004",
      testCase "errors" $ do
        ev "1 / 0" @?= Left "G0203"
        ev "sqrt(-1)" @?= Left "G0204"
        ev "2 ** 0.5" @?= Left "G0206"
        ev "div(1.5, 1)" @?= Left "G0201"
        ev "10.0 ** 400" @?= Left "G0204"
        ev "y" @?= Left "G0202"
        ev "nope(1)" @?= Left "G0207",
      testCase "precedence through evaluation" $ do
        ev "-2 ** 2" @?= Right (VInt (-4))
        ev "2 ** 3 ** 2" @?= Right (VInt 512)
        ev "1 - 2 - 3" @?= Right (VInt (-4))
        ev "2 ** -1" @?= Right (VFloat 0.5),
      testCase "names, namespaces, comparisons" $ do
        ev "x * 2" @?= Right (VInt 20)
        ev "values.price >= 100" @?= Right (VBool True)
        ev "\"a\" < \"b\"" @?= Right (VBool True)
        ev "1 == 1.0" @?= Right (VBool True)
        ev "len(\"漢字\")" @?= Right (VInt 2)
        ev "max(1, 2.5, 2)" @?= Right (VFloat 2.5),
      testCase "embedding rejects non-text values" $ do
        shown "true" @?= Left "Diagnostic {diagCode = DiagnosticCode \"G0208\", diagSeverity = Error, diagSpan = SrcSpan {spanFile = FileId 0, spanStart = 0, spanEnd = 0}, diagMessage = \"\\30495\\20605\\20516 \\12399\\26412\\25991\\12395\\22475\\12417\\36796\\12417\\12414\\12379\\12435\", diagRelated = [], diagFixes = []}"
        either (const True) (const False) (shown "[1]") @?= True,
      testProperty "a == div(a, b) * b + a % b" $ property $ do
        a <- forAll (Gen.integral (Range.linearFrom 0 (-1000) 1000))
        b <- forAll (Gen.filter (/= 0) (Gen.integral (Range.linearFrom 0 (-50) 50)))
        a === floorDiv a b * b + floorMod a b,
      testProperty "rendering reads back to the same double" $ property $ do
        d <- forAll (Gen.double (Range.exponentialFloatFrom 0 (-1e30) 1e30))
        case finite d of
          Nothing -> success
          Just x -> do
            let t = renderDouble x
            annotate (T.unpack t)
            assert (not (T.isInfixOf "e" t))
            (read (T.unpack (if T.isInfixOf "." t then t else t <> ".0")) :: Double) === x
    ]
