module ExprSpec (tests) where

import Control.Monad (when)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)
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
      -- docs/adr ADR 0033
      testCase "join joins strings with a separator; anything else is G0201" $ do
        ev "join([\"a\", \"b\"], \"、\")" @?= Right (VString "a、b")
        ev "join([], \"、\")" @?= Right (VString "")
        ev "join([1], \"、\")" @?= Left "G0201"
        ev "join(\"a\", \"、\")" @?= Left "G0201"
        ev "join([\"a\"], 1)" @?= Left "G0201",
      testCase "an expression that cannot be evaluated reports its diagnostic code" $ do
        ev "1 / 0" @?= Left "G0203"
        ev "sqrt(-1)" @?= Left "G0204"
        ev "2 ** 0.5" @?= Left "G0206"
        ev "div(1.5, 1)" @?= Left "G0201"
        ev "10.0 ** 400" @?= Left "G0204"
        ev "y" @?= Left "G0202"
        ev "nope(1)" @?= Left "G0261",
      diagnosticTests,
      overflowTests,
      exactLimitTests,
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
      localOption (mkTimeout 10000000) $ testCase "G0286: integers below 2^4096 and at most 1000 digits (docs/adr ADR 0035)" $ do
        let big = ("G0286", "整数が大きすぎます（絶対値は 2 の 4096 乗未満に限ります）")
            digits = ("G0286", "小数の桁数が多すぎます（1000 桁までです）")
        evm "10 ** 100000000" @?= Left big
        evm "2 ** 4096" @?= Left big
        evm "(-2) ** 4097" @?= Left big
        evm "(2 ** 4095) * (2 ** 4095)" @?= Left big
        evm "2 ** 4095 + 2 ** 4095" @?= Left big
        evm "-(2 ** 4095) - 2 ** 4095" @?= Left big
        ev "2 ** 4095 - 1 + 2 ** 4095" @?= Right (VInt (2 ^ (4096 :: Int) - 1))
        ev "1 ** 100000000000" @?= Right (VInt 1)
        ev "(-1) ** 100000000001" @?= Right (VInt (-1))
        ev "0 ** 100000000000" @?= Right (VInt 0)
        evm "round(1.5, 100000000)" @?= Left digits
        evm "fixed(1.5, 1001)" @?= Left digits
        either (const (assertFailure "fixed(1.5, 1000)")) (const (pure ())) (evm "fixed(1.5, 1000)"),
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

-- | The bits of the double of an expression, or the code of its error.
bitsOf :: Text -> Either Text Word64
bitsOf src = case ev src of
  Left c -> Left c
  Right (VFloat d) -> Right (castDoubleToWord64 d)
  Right v -> Left (T.pack (show v))

-- | The bits of a double.
bits :: Double -> Either Text Word64
bits = Right . castDoubleToWord64

-- | Evaluates within a second, or fails.
withinASecond :: TestTree -> TestTree
withinASecond = localOption (mkTimeout 1000000)

-- | Floating-point overflow and the exact rules of golem-eval ADR 0005.
overflowTests :: TestTree
overflowTests =
  testGroup
    "floating-point overflow (golem-eval ADR 0005)"
    [ testCase "negative exponents" $ do
        bitsOf "2.0 ** -1074" @?= bits (encodeFloat 1 (-1074))
        bitsOf "2 ** -1074" @?= bits (encodeFloat 1 (-1074))
        -- halfway, to the even side
        bitsOf "2 ** -1075" @?= bits 0
        bitsOf "2.0 ** -1075" @?= bits 0
        bitsOf "3 ** -2" @?= bits (1 / 9)
        -- not a negative zero
        bitsOf "(-2.0) ** -1075" @?= bits 0,
      testCase "a floating-point base" $ do
        bitsOf "1.1 ** 10" @?= bits 2.5937424601000023
        bitsOf "0.5 ** 1074" @?= bits (encodeFloat 1 (-1074))
        bitsOf "2.0 ** 1023" @?= bits (encodeFloat 1 1023)
        bitsOf "2.0 ** 1024" @?= Left "G0204"
        -- (1e200) ** 2 of the ADR; the language has no exponent notation
        bitsOf "(10.0 ** 200) ** 2" @?= Left "G0204"
        bitsOf "0.1 ** 400" @?= bits 0,
      withinASecond $ testCase "large exponents" $ do
        -- over the limit before the range (golem-eval ADR 0006)
        ev "1.5 ** 100000000" @?= Left "G0295"
        ev "0.75 ** -100000000" @?= Left "G0295"
        bitsOf "0.5 ** 100000000" @?= bits 0
        evm "1.0000001 ** 100000" @?= Left (overLimit (52 * 100000))
        bitsOf "1.0 ** 100000000" @?= bits 1
        bitsOf "0.5 ** -1000" @?= bits (encodeFloat 1 1000),
      testProperty "a power is the exact power rounded once" $ property $ do
        a <- forAll (Gen.filter (/= 0) (Gen.double (Range.exponentialFloat (-1e300) 1e300)))
        k <- forAll (Gen.filter (/= 0) (Gen.integral (Range.linear (-64) 64)))
        let exact = fromRational (toRational a ^^ k) :: Double
            -- a float literal: renderDouble writes an integral double without a point
            lit = let r = renderDouble (abs a) in if T.any (== '.') r then r else r <> ".0"
            src = "(" <> (if a < 0 then "-" else "") <> lit <> ") ** " <> T.pack (show k)
        if isInfinite exact
          then bitsOf src === Left "G0204"
          else bitsOf src === bits (if exact == 0 then 0 else exact),
      testCase "the division of integers" $ do
        bitsOf "10 ** 309 / 10 ** 308" @?= bits 10
        bitsOf "(2 ** 53 + 1) / 1" @?= bits (encodeFloat 1 53)
        bitsOf "10 ** 400 / 3" @?= Left "G0204",
      testProperty "the division of integers up to 2^53 is as before" $ property $ do
        let int = Gen.integral (Range.linearFrom 0 (-(2 ^ (53 :: Int))) (2 ^ (53 :: Int)))
        a <- forAll int
        b <- forAll (Gen.filter (/= 0) int)
        bitsOf (T.pack (show a) <> " / (" <> T.pack (show b) <> ")") === bits (fromMaybe 0 (finite (fromInteger a / fromInteger b))),
      testCase "integers converted to floating point" $ do
        let tooLarge = Left ("G0204", "整数が大きすぎて浮動小数点数に変換できません")
        evm "10 ** 309 + 0.5" @?= tooLarge
        evm "sqrt(10 ** 309)" @?= tooLarge
        bitsOf "(2 ** 54 + 3) + 0.0" @?= bits (encodeFloat 1 54 + 4),
      testCase "integers and floating point compared exactly" $ do
        ev "10 ** 309 > 1.0" @?= Right (VBool True)
        ev "2 ** 53 + 1 > 9007199254740992.0" @?= Right (VBool True)
        ev "2 ** 53 + 1 != 9007199254740992.0" @?= Right (VBool True)
        ev "2 ** 53 == 9007199254740992.0" @?= Right (VBool True)
        ev "10 ** 400 < 10.0 ** 308" @?= Right (VBool False),
      testCase "min and max" $ do
        ev "max(10 ** 309, 10 ** 310)" @?= Right (VInt (10 ^ (310 :: Int)))
        ev "max(2 ** 53, 2 ** 53 + 1)" @?= Right (VInt (2 ^ (53 :: Int) + 1))
        ev "max(2 ** 53 + 1, 9007199254740992.0)" @?= Right (VInt (2 ^ (53 :: Int) + 1))
        ev "max(9007199254740992.0, 2 ** 53 + 1)" @?= Right (VInt (2 ^ (53 :: Int) + 1))
        ev "min(1, 1.0)" @?= Right (VInt 1)
    ]

-- | The code and the message of a power over the limit of the exact computation.
overLimit :: Integer -> (Text, Text)
overLimit n = ("G0295", "累乗の計算が大きすぎます（正確な計算に要るビットの数 " <> T.pack (show n) <> " が、上限の 1048576（2 の 20 乗）を超えます）")

-- | The bits of the odd part of the absolute value of a rational, less one.
oddBitsLess1 :: Rational -> Integer
oddBitsLess1 q =
  let oddPart = until odd (`div` 2) . abs
      m = max (oddPart (numerator q)) (oddPart (denominator q))
   in bitsLess1 m
  where
    bitsLess1 n = if n <= 1 then 0 else 1 + bitsLess1 (n `div` 2)

-- | A double as a float literal of the language, with its sign in front.
floatLit :: Double -> Text
floatLit a =
  -- renderDouble writes an integral double without a point
  let r = renderDouble (abs a)
      l = if T.any (== '.') r then r else r <> ".0"
   in "(" <> (if a < 0 then "-" else "") <> l <> ")"

-- | A double that is not 0, of any size.
anyDouble :: Gen Double
anyDouble =
  Gen.choice
    [ Gen.filter (/= 0) (Gen.double (Range.exponentialFloat (-1e300) 1e300)),
      Gen.filter (/= 0) (Gen.double (Range.linearFrac (-4) 4)),
      -- near 1, so that the odd part is large and the result near the range
      (\s e -> s * (1 + e)) <$> Gen.element [1, -1] <*> Gen.double (Range.exponentialFloat (-1e-3) 1e-3),
      (\s f -> s * encodeFloat 1 f) <$> Gen.element [1, -1] <*> Gen.int (Range.linear (-1074) 1023)
    ]

-- | An exponent that is not 0, often near the limit for the base, up to 2^40.
exponentFor :: Double -> Gen Integer
exponentFor a = do
  let b = oddBitsLess1 (toRational a)
      limit = 2 ^ (20 :: Int) :: Integer
  n <-
    Gen.choice
      ( Gen.integral (Range.exponential 1 (2 ^ (40 :: Int)))
          : [(\d -> max 1 (limit `div` b + d)) <$> Gen.integral (Range.linear (-3) 3) | b > 0]
      )
  s <- Gen.element [1, -1]
  pure (s * n)

{- | The limit of the exact computation is judged first, by integers alone
(golem-eval ADR 0006).
-}
exactLimitTests :: TestTree
exactLimitTests =
  testGroup
    "the exact limit before the range (golem-eval ADR 0006)"
    [ withinASecond $ testCase "the estimate no longer decides the code" $ do
        -- 1 + 7 * 2^-24 and 1 - 2^-26 written exactly
        let up = "1.000000417232513427734375"
            down = "0.99999998509883880615234375"
        evm (up <> " ** 1702829922") @?= Left (overLimit (24 * 1702829922))
        evm (up <> " ** 1702829923") @?= Left (overLimit (24 * 1702829923))
        evm (down <> " ** 50051559810") @?= Left (overLimit (25 * 50051559810))
        evm (down <> " ** 50051559811") @?= Left (overLimit (25 * 50051559811)),
      testProperty "G0295 if and only if the bits of the exact computation are over 2^20" $ property $ do
        a <- forAll anyDouble
        k <- forAll (exponentFor a)
        let n = oddBitsLess1 (toRational a) * abs k
            r = evm (floatLit a <> " ** " <> T.pack (show k))
        annotateShow r
        (either fst (const "") r == "G0295") === (n > 2 ^ (20 :: Int))
        when (n > 2 ^ (20 :: Int)) (r === Left (overLimit n)),
      testProperty "the diagnostic of a power depends on the input alone" $ property $ do
        a <- forAll anyDouble
        k <- forAll (exponentFor a)
        let e = floatLit a <> " ** " <> T.pack (show k)
            alone = evm e
        case alone of
          Left cm -> do
            -- after another expression, and twice in one expression
            evm ("[1, " <> e <> "]") === Left cm
            evm ("0 + " <> e) === Left cm
            evm (e <> " + " <> e) === Left cm
          Right v -> evm ("[1, " <> e <> "]") === Right (VArray [VInt 1, v]),
      testCase "the same value written differently gives the same diagnostic" $ do
        let forms = ["1.5", "1.50", "1.500000", "(3 / 2)"]
        mapM_ (\b -> evm (b <> " ** 1048577") @?= Left (overLimit 1048577)) forms
        mapM_ (\b -> ev (b <> " ** 1048576") @?= Left "G0204") forms
        mapM_ (\b -> bitsOf (b <> " ** -1048576") @?= bits 0) forms,
      testProperty "a base that is a power of 2 is 2^(f * k) rounded once" $ property $ do
        f <- forAll (Gen.integral (Range.linearFrom 0 (-1074) 1023))
        s <- forAll (Gen.element [1, -1 :: Integer])
        k <- forAll (Gen.filter (/= 0) (Gen.choice [Gen.integral (Range.linear (-2200) 2200), Gen.integral (Range.exponentialFrom 0 (negate (2 ^ (4000 :: Int))) (2 ^ (4000 :: Int)))]))
        let a = fromInteger s * encodeFloat 1 (fromInteger f) :: Double
            e = f * k
            neg = s < 0 && odd k
            r = bitsOf (floatLit a <> " ** " <> T.pack (show k))
        r === expected e neg,
      withinASecond $ testCase "the boundaries of overflow" $ do
        bitsOf "2.0 ** 1023" @?= bits (encodeFloat 1 1023)
        ev "2.0 ** 1024" @?= Left "G0204"
        ev "0.5 ** -1024" @?= Left "G0204"
        bitsOf "3.0 ** 646" @?= bits 1.6608505280233425e308
        ev "3.0 ** 647" @?= Left "G0204",
      withinASecond $ testCase "the boundaries of underflow" $ do
        bitsOf "2.0 ** -1074" @?= bits (encodeFloat 1 (-1074))
        bitsOf "2 ** -1074" @?= bits (encodeFloat 1 (-1074))
        bitsOf "2.0 ** -1075" @?= bits 0
        bitsOf "(-2) ** -1075" @?= bits 0
        bitsOf "3.0 ** -678" @?= bits (encodeFloat 1 (-1074))
        bitsOf "3 ** -679" @?= bits 0,
      withinASecond $ testCase "the boundaries of the limit" $ do
        assertBool "1.0000001 ** 20164 is a value" (isValue (ev "1.0000001 ** 20164"))
        evm "1.0000001 ** 20165" @?= Left (overLimit 1048580)
        ev "1.5 ** 1048576" @?= Left "G0204"
        evm "1.5 ** 1048577" @?= Left (overLimit 1048577)
        bitsOf "1.5 ** -1048576" @?= bits 0
        evm "1.5 ** -1048577" @?= Left (overLimit 1048577)
        bitsOf "3 ** -1048576" @?= bits 0
        evm "3 ** -1048577" @?= Left (overLimit 1048577),
      withinASecond $ testCase "a power of 2 with a large exponent" $ do
        ev "2.0 ** 100000000000" @?= Left "G0204"
        bitsOf "0.5 ** 100000000000" @?= bits 0
        bitsOf "2 ** -100000000000" @?= bits 0
    ]
  where
    isValue = either (const False) (const True)
    expected e neg
      | e >= 1024 = Left "G0204"
      | e <= -1075 = bits 0
      | otherwise = bits ((if neg then negate else id) (encodeFloat 1 (fromInteger e)))
