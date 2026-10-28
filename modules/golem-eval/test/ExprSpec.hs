module ExprSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Expr
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
    (Map.fromList [("x", VNat 10)])
    ( Map.fromList
        [ ("values", Map.fromList [("price", VNat 100)]),
          ("ns", Map.fromList [("x", VNat 1)]),
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
    [ testCase "an EError is G01020 at its position (golem-parser ADR 0009)" $ do
        let sp = mkSpan (FileId 2) 5 6
        either (\d -> Just (diagCode d, diagSpan d)) (const Nothing) (evalExpr env (Located sp EError))
          @?= Just (DiagnosticCode "G01020", sp),
      testCase "boundary values" $ do
        shown "round(2.675, 2)" @?= Right "2.68"
        shown "round(-2.5)" @?= Right "-3"
        shown "fixed(1.5, 2)" @?= Right "1.50"
        shown "10 / 2" @?= Right "5"
        shown "0.01" @?= Right "0.01"
        shown "1000000000000000000000.0" @?= Right "1000000000000000000000"
        shown "-0.0" @?= Right "0"
        shown "0.1 + 0.2" @?= Right "0.3",
      -- docs/adr ADR 0033
      testCase "join joins strings with a separator; anything else is G02001" $ do
        ev "join([\"a\", \"b\"], \"、\")" @?= Right (VString "a、b")
        ev "join([], \"、\")" @?= Right (VString "")
        ev "join([1], \"、\")" @?= Left "G02001"
        ev "join(\"a\", \"、\")" @?= Left "G02001"
        ev "join([\"a\"], 1)" @?= Left "G02001",
      testCase "an expression that cannot be evaluated reports its diagnostic code" $ do
        ev "1 / 0" @?= Left "G02003"
        ev "sqrt(-1)" @?= Left "G02101"
        ev "2 ** 0.5" @?= Left "G02006"
        ev "div(1.5, 1)" @?= Left "G02001"
        ev "y" @?= Left "G02002"
        ev "nope(1)" @?= Left "G02061",
      diagnosticTests,
      testCase "precedence through evaluation" $ do
        ev "-2 ** 2" @?= Right (VInt (-4))
        ev "2 ** 3 ** 2" @?= Right (VNat 512)
        ev "1 - 2 - 3" @?= Right (VInt (-4))
        ev "2 ** -1" @?= Right (VRat 0.5),
      testCase "names, namespaces, comparisons" $ do
        ev "x * 2" @?= Right (VNat 20)
        ev "values.price >= 100" @?= Right (VBool True)
        ev "\"a\" < \"b\"" @?= Right (VBool True)
        ev "1 == 1.0" @?= Right (VBool True)
        ev "len(\"漢字\")" @?= Right (VNat 2)
        ev "max(1, 2.5, 2)" @?= Right (VRat 2.5),
      testCase "embedding rejects non-text values" $ do
        shown "true" @?= Left "Diagnostic {diagCode = DiagnosticCode \"G02008\", diagSeverity = Error, diagSpan = SrcSpan {spanFile = FileId 0, spanStart = 0, spanEnd = 0}, diagMessage = \"\\30495\\20605\\20516 \\12399\\26412\\25991\\12395\\22475\\12417\\36796\\12417\\12414\\12379\\12435\", diagRelated = [], diagFixes = [], diagFacts = []}"
        -- the code and the message name the type of every value that is not text
        [either (Just . codeMsg) (const Nothing) (embedValue (mkSpan (FileId 0) 0 0) v) | v <- [VBool False, VNil, VArray [VNat 1], VHash Map.empty]]
          @?= [Just ("G02008", t <> " は本文に埋め込めません") | t <- ["真偽値", "nil", "配列", "連想配列"]],
      -- the identity alone holds for truncation as well; the remainder takes
      -- the sign of the divisor only when the quotient is floored
      testProperty "a == div(a, b) * b + a % b, the remainder with the sign of b" $ property $ do
        a <- forAll (Gen.integral (Range.linearFrom 0 (-1000) 1000))
        b <- forAll (Gen.filter (/= 0) (Gen.integral (Range.linearFrom 0 (-50) 50)))
        let lit n = "(" <> T.pack (show (n :: Integer)) <> ")"
        q <- evalEither (ev ("div(" <> lit a <> ", " <> lit b <> ")"))
        r <- evalEither (ev (lit a <> " % " <> lit b))
        case (intOf q, intOf r) of
          (Just q', Just r') -> do
            a === q' * b + r'
            assert (abs r' < abs b)
            assert (r' == 0 || signum r' == signum b)
          other -> annotateShow other >> failure
    ]

-- | The codes, messages and positions of golem-eval ADR 0003.
diagnosticTests :: TestTree
diagnosticTests =
  testGroup
    "diagnostic codes (golem-eval ADR 0003)"
    [ testCase "G02001" $ do
        evm "-\"a\"" @?= Left ("G02001", "- は 文字列 に使えません")
        evm "1 + \"a\"" @?= Left ("G02001", "自然数 と 文字列 にこの演算子は使えません")
        evm "(0 - 1) + \"a\"" @?= Left ("G02001", "整数 と 文字列 にこの演算子は使えません")
        evm "1.5 + \"a\"" @?= Left ("G02001", "有理数 と 文字列 にこの演算子は使えません")
        evm "1.5 % 2" @?= Left ("G02001", "% は整数にだけ使えます")
        evm "div(1.5, 1)" @?= Left ("G02001", "div は整数にだけ使えます")
        evm "sqrt(\"a\")" @?= Left ("G02001", "文字列 は数ではありません")
        evm "ns.x.y" @?= Left ("G02001", "自然数 の要素は参照できません"),
      testCase "G02002" $ do
        evm "y" @?= Left ("G02002", "未定義の名前 y です")
        evm "nons.x" @?= Left ("G02002", "未定義の名前空間 nons です")
        evm "meta.nope" @?= Left ("G02002", "未定義の名前 nope です")
        either (Left . codeMsg) Right (evalExpr env (Located (mkSpan (FileId 0) 0 0) (EVar []))) @?= Left ("G02002", "名前がありません"),
      testCase "G02003" $
        mapM_
          (\src -> (src, evm src) @?= (src, Left ("G02003", "0 で割っています")))
          ["1 / 0", "1 / 0.0", "5 % 0", "div(1, 0)", "0 ** -1", "0.0 ** -1"],
      testCase "G02101" $
        evm "sqrt(-1)" @?= Left ("G02101", "負の数の平方根は求められません"),
      testCase "G02006 comes before type errors" $ do
        evm "2 ** 0.5" @?= Left ("G02006", "** の指数は整数に限ります")
        evm "\"a\" ** 0.5" @?= Left ("G02006", "** の指数は整数に限ります"),
      testCase "G02007" $ do
        evm "sqrt()" @?= Left ("G02007", "sqrt の引数が不正です")
        evm "sqrt(1, 2)" @?= Left ("G02007", "sqrt の引数が不正です")
        evm "min()" @?= Left ("G02007", "min の引数が不正です")
        evm "max()" @?= Left ("G02007", "max の引数が不正です")
        -- a negative number of digits is G02103 (docs/adr ADR 0102)
        evm "round(1.5, -1)" @?= Left ("G02103", "round の桁数には 0 以上の整数を書きます（書かれた値は -1）"),
      localOption (mkTimeout 30000000) $ testCase "G02086: integers below 2^4096 and at most 1000 digits (docs/adr ADR 0035)" $ do
        let big = ("G02086", "数が大きすぎます（整数と、分数の分子と分母の絶対値は 2 の 4096 乗未満に限ります）")
            digits = ("G02086", "小数の桁数が多すぎます（1000 桁までです）")
        evm "10 ** 100000000" @?= Left big
        evm "2 ** 4096" @?= Left big
        evm "(-2) ** 4097" @?= Left big
        evm "(2 ** 4095) * (2 ** 4095)" @?= Left big
        evm "2 ** 4095 + 2 ** 4095" @?= Left big
        evm "-(2 ** 4095) - 2 ** 4095" @?= Left big
        ev "2 ** 4095 - 1 + 2 ** 4095" @?= Right (VInt (2 ^ (4096 :: Int) - 1))
        ev "1 ** 100000000000" @?= Right (VNat 1)
        ev "(-1) ** 100000000001" @?= Right (VInt (-1))
        ev "0 ** 100000000000" @?= Right (VNat 0)
        evm "round(1.5, 100000000)" @?= Left digits
        evm "fixed(1.5, 1001)" @?= Left digits
        either (const (assertFailure "fixed(1.5, 1000)")) (const (pure ())) (evm "fixed(1.5, 1000)"),
      testCase "G02061: an undefined function" $
        evm "nope(1)" @?= Left ("G02061", "未定義の関数 nope です"),
      testCase "G02008" $ do
        embm "[1, 2]" @?= Left ("G02008", "配列 は本文に埋め込めません")
        embm "{a: 1}" @?= Left ("G02008", "連想配列 は本文に埋め込めません")
        embm "true" @?= Left ("G02008", "真偽値 は本文に埋め込めません")
        embm "nil" @?= Left ("G02008", "nil は本文に埋め込めません"),
      testCase "the position is that of the subexpression, parentheses included" $
        case evalExpr env (exprOf "1 + (2 / 0)") of
          Left d -> (spanStart (diagSpan d), spanEnd (diagSpan d)) @?= (7, 14)
          Right v -> assertFailure (show v)
    ]

-- | The value of an integral number.
intOf :: Value -> Maybe Integer
intOf = \case
  VNat n -> Just (toInteger n)
  VInt i -> Just i
  _ -> Nothing
