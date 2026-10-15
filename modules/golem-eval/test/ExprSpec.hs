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
    ( Map.fromList
        [ ("values", Map.fromList [("price", VInt 100)]),
          ("ns", Map.fromList [("x", VInt 1)]),
          ("meta", Map.fromList [("title", VString "t")])
        ]
    )

ev :: Text -> Either Text Value
ev src = either (Left . (\(DiagnosticCode c) -> c) . diagCode) Right (evalExpr env (exprOf src))

-- | The code and the message of the diagnostic of a failed evaluation.
evm :: Text -> Either (Text, Text) Value
evm src = either (Left . codeMsg) Right (evalExpr env (exprOf src))

codeMsg :: Diagnostic -> (Text, Text)
codeMsg d = let DiagnosticCode c = diagCode d in (c, diagMessage d)

-- | The code and the message of embedding the value of an expression.
embm :: Text -> Either (Text, Text) Text
embm src = case evalExpr env (exprOf src) of
  Left d -> Left (codeMsg d)
  Right v -> either (Left . codeMsg) Right (embedValue (mkSpan (FileId 0) 0 0) v)

shown :: Text -> Either Text Text
shown src = case ev src of
  Left c -> Left c
  Right v -> either (Left . T.pack . show) Right (embedValue (mkSpan (FileId 0) 0 0) v)

tests :: TestTree
tests =
  testGroup
    "expressions and numerics (ADR 0001)"
    [ testCase "an EError is G0120 at its position (golem-parser ADR 0009)" $ do
        let sp = mkSpan (FileId 2) 5 6
        either (\d -> Just (diagCode d, diagSpan d)) (const Nothing) (evalExpr env (Located sp EError))
          @?= Just (DiagnosticCode "G0120", sp),
      testCase "boundary values" $ do
        shown "round(2.675, 2)" @?= Right "2.68"
        shown "round(-2.5)" @?= Right "-3"
        shown "fixed(1.5, 2)" @?= Right "1.50"
        shown "10 / 2" @?= Right "5"
        shown "0.01" @?= Right "0.01"
        shown "1000000000000000000000.0" @?= Right "1000000000000000000000"
        shown "-0.0" @?= Right "0"
        shown "0.1 + 0.2" @?= Right "0.30000000000000004",
      testCase "an expression that cannot be evaluated reports its diagnostic code" $ do
        ev "1 / 0" @?= Left "G0203"
        ev "sqrt(-1)" @?= Left "G0204"
        ev "2 ** 0.5" @?= Left "G0206"
        ev "div(1.5, 1)" @?= Left "G0201"
        ev "10.0 ** 400" @?= Left "G0204"
        ev "y" @?= Left "G0202"
        ev "nope(1)" @?= Left "G0261",
      diagnosticTests,
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
        shown "true" @?= Left "Diagnostic {diagCode = DiagnosticCode \"G0208\", diagSeverity = Error, diagSpan = SrcSpan {spanFile = FileId 0, spanStart = 0, spanEnd = 0}, diagMessage = \"\\30495\\20605\\20516 \\12399\\26412\\25991\\12395\\22475\\12417\\36796\\12417\\12414\\12379\\12435\", diagRelated = [], diagFixes = [], diagFacts = []}"
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

-- | The codes, messages and positions of golem-eval ADR 0003.
diagnosticTests :: TestTree
diagnosticTests =
  testGroup
    "diagnostic codes (golem-eval ADR 0003)"
    [ testCase "G0201" $ do
        evm "-\"a\"" @?= Left ("G0201", "- は 文字列 に使えません")
        evm "1 + \"a\"" @?= Left ("G0201", "整数 と 文字列 にこの演算子は使えません")
        evm "1.5 % 2" @?= Left ("G0201", "% は整数にだけ使えます")
        evm "div(1.5, 1)" @?= Left ("G0201", "div は整数にだけ使えます")
        evm "sqrt(\"a\")" @?= Left ("G0201", "文字列 は数ではありません")
        evm "ns.x.y" @?= Left ("G0201", "整数 の要素は参照できません"),
      testCase "G0202" $ do
        evm "y" @?= Left ("G0202", "未定義の名前 y です")
        evm "nons.x" @?= Left ("G0202", "未定義の名前空間 nons です")
        evm "meta.nope" @?= Left ("G0202", "未定義の名前 nope です")
        either (Left . codeMsg) Right (evalExpr env (Located (mkSpan (FileId 0) 0 0) (EVar []))) @?= Left ("G0202", "名前がありません"),
      testCase "G0203" $
        mapM_
          (\src -> (src, evm src) @?= (src, Left ("G0203", "0 で割っています")))
          ["1 / 0", "1 / 0.0", "5 % 0", "div(1, 0)", "0 ** -1", "0.0 ** -1"],
      testCase "G0204" $ do
        evm "10.0 ** 400" @?= Left ("G0204", "結果が NaN か無限大になる演算です")
        evm "sqrt(-1)" @?= Left ("G0204", "負の数の平方根です"),
      testCase "G0206 comes before type errors" $ do
        evm "2 ** 0.5" @?= Left ("G0206", "** の指数は整数に限ります")
        evm "\"a\" ** 0.5" @?= Left ("G0206", "** の指数は整数に限ります"),
      testCase "G0207" $ do
        evm "sqrt()" @?= Left ("G0207", "sqrt の引数が不正です")
        evm "sqrt(1, 2)" @?= Left ("G0207", "sqrt の引数が不正です")
        evm "min()" @?= Left ("G0207", "min の引数が不正です")
        evm "max()" @?= Left ("G0207", "max の引数が不正です")
        evm "round(1.5, -1)" @?= Left ("G0207", "round の引数が不正です"),
      testCase "G0261: an undefined function" $
        evm "nope(1)" @?= Left ("G0261", "未定義の関数 nope です"),
      testCase "G0208" $ do
        embm "[1, 2]" @?= Left ("G0208", "配列 は本文に埋め込めません")
        embm "{a: 1}" @?= Left ("G0208", "連想配列 は本文に埋め込めません")
        embm "true" @?= Left ("G0208", "真偽値 は本文に埋め込めません")
        embm "nil" @?= Left ("G0208", "nil は本文に埋め込めません"),
      testCase "the position is that of the subexpression, parentheses included" $
        case evalExpr env (exprOf "1 + (2 / 0)") of
          Left d -> (spanStart (diagSpan d), spanEnd (diagSpan d)) @?= (7, 14)
          Right v -> assertFailure (show v)
    ]
