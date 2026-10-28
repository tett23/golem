{- | The three number types of the expression language and their exact
arithmetic (docs/adr ADR 0101): natural numbers, integers and rationals,
the type of a result decided by the types of the arguments, the rounding
to 17 significant digits, and the text of a number in prose.
-}
module RationalSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Ratio (denominator, numerator, (%))
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

-- | The expression of "[= src]".
exprOf :: Text -> Located Expr
exprOf src =
  let (File _ bs, _, ds) = parseAst (FileId 0) ("[= " <> src <> "]\n")
   in case (ds, map locValue bs) of
        ([], [Paragraph [Located _ (Expr e)]]) -> e
        other -> error (show other)

-- | The value, or the code of the diagnostic.
ev :: Text -> Either Text Value
ev src = either (Left . code) Right (evalExpr (Env Map.empty Map.empty) (exprOf src))

code :: Diagnostic -> Text
code d = let DiagnosticCode c = diagCode d in c

-- | The text the value is embedded as in prose, or the code of the diagnostic.
shown :: Text -> Either Text Text
shown src = ev src >>= either (Left . code) Right . embedValue (mkSpan (FileId 0) 0 0)

-- | The code and the message of a failed evaluation or embedding.
shownm :: Text -> Either (Text, Text) Text
shownm src = case evalExpr (Env Map.empty Map.empty) (exprOf src) of
  Left d -> Left (code d, diagMessage d)
  Right v -> either (\d -> Left (code d, diagMessage d)) Right (embedValue (mkSpan (FileId 0) 0 0) v)

table :: String -> [(Text, Either Text Value)] -> TestTree
table name rows = testGroup name [testCase (T.unpack src) (ev src @?= expected) | (src, expected) <- rows]

texts :: String -> [(Text, Either Text Text)] -> TestTree
texts name rows = testGroup name [testCase (T.unpack src) (shown src @?= expected) | (src, expected) <- rows]

-- | Fails a test that does not end within a second.
withinASecond :: TestTree -> TestTree
withinASecond = localOption (mkTimeout 1000000)

tests :: TestTree
tests =
  testGroup
    "natural numbers, integers and rationals (docs/adr ADR 0101)"
    [ table
        "the type of a value is decided by the expression"
        [ ("5", Right (VNat 5)),
          ("-5", Right (VInt (-5))),
          ("5 - 2", Right (VInt 3)),
          ("10 / 2", Right (VRat 5)),
          ("3.0", Right (VRat 3)),
          ("abs(0 - 3)", Right (VNat 3)),
          ("floor(7 / 2)", Right (VInt 3)),
          ("div(7, 2)", Right (VNat 3)),
          ("div(0 - 7, 2)", Right (VInt (-4))),
          ("(0 - 7) % 2", Right (VNat 1)),
          ("2 ** 3", Right (VNat 8)),
          ("2 ** (3 - 1)", Right (VRat 4)),
          ("min(1, 1.0)", Right (VRat 1)),
          ("len(\"ab\")", Right (VNat 2)),
          ("7 / 2", Right (VRat (7 % 2))),
          ("15e-1", Right (VRat (3 % 2)))
        ],
      table
        "numbers are compared by their values"
        [ ("5 == 10 / 2", Right (VBool True)),
          ("5 == 5.0", Right (VBool True)),
          ("[1] == [1.0]", Right (VBool True)),
          ("{\"a\": 1} == {\"a\": 2 / 2}", Right (VBool True)),
          ("[1] != [1.0]", Right (VBool False)),
          ("0.1 + 0.2 == 0.3", Right (VBool True))
        ],
      texts
        "exact arithmetic in prose"
        [ ("0.1 + 0.2", Right "0.3"),
          ("1.1 ** 10", Right "2.5937424601"),
          ("2 ** -3", Right "0.125"),
          ("10 / 2", Right "5"),
          ("7 / 2", Right "3.5"),
          ("1.5e3", Right "1500")
        ],
      texts
        "a repeating decimal is rounded to 17 significant digits in prose"
        [ ("1 / 3", Right "0.33333333333333333"),
          ("2 / 3", Right "0.66666666666666667"),
          ("10 / 3", Right "3.3333333333333333"),
          ("0 - 1 / 3", Right "-0.33333333333333333"),
          ("10 ** 30 / 3", Right (T.replicate 30 "3")),
          ("1 / 3 * 3", Right "1"),
          ("round(1 / 3, 4)", Right "0.3333"),
          ("fixed(2 / 3, 2)", Right "0.67")
        ],
      testGroup
        "the digits in prose are at most 1000 after the point"
        [ testCase "2 ** -1001 is G02102" $
            shownm "2 ** -1001" @?= Left ("G02102", "小数点以下が 1000 桁を超える数は本文に埋め込めません。round か fixed で桁数を決めます"),
          testCase "2 ** -1000 has 1000 digits" $
            fmap (T.length . T.drop 2) (shown "2 ** -1000") @?= Right 1000,
          testCase "1 / (3 * 10 ** 980) has 997 digits" $
            fmap (T.length . T.drop 2) (shown "1 / (3 * 10 ** 980)") @?= Right 997,
          testCase "1 / (3 * 10 ** 990) is G02102" $
            shown "1 / (3 * 10 ** 990)" @?= Left "G02102"
        ],
      texts
        "round and fixed round the exact value, ties away from zero"
        [ ("round(2.675, 2)", Right "2.68"),
          ("round(0 - 2.5)", Right "-3"),
          ("fixed(1.005, 2)", Right "1.01"),
          ("fixed(3, 2)", Right "3.00")
        ],
      table
        "the type of round, floor, ceil and abs"
        [ ("round(2.5)", Right (VInt 3)),
          ("round(3)", Right (VNat 3)),
          ("round(0 - 3)", Right (VInt (-3))),
          ("round(1.25, 1)", Right (VRat (13 % 10))),
          ("round(3, 1)", Right (VNat 3)),
          ("ceil(0 - 2.5)", Right (VInt (-2))),
          ("abs(0 - 2.5)", Right (VRat (5 % 2)))
        ],
      texts
        "pi, e and sqrt"
        [ ("pi", Right "3.1415926535897932"),
          ("e", Right "2.7182818284590452"),
          ("sqrt(2)", Right "1.414213562373095"),
          ("sqrt(9 / 4)", Right "1.5"),
          ("sqrt(10 ** 100)", Right ("1" <> T.replicate 50 "0")),
          ("sqrt(2 * 10 ** 40)", Right "141421356237309504880")
        ],
      testCase "the square root of a negative number is G02101" $
        shownm "sqrt(0 - 1)" @?= Left ("G02101", "負の数の平方根は求められません"),
      table
        "div and % take integral values only"
        [ ("div(4.0, 2)", Right (VInt 2)),
          ("div(1.5, 1)", Left "G02001"),
          ("4.5 % 2", Left "G02001"),
          ("2 ** 2.0", Right (VRat 4)),
          ("2 ** 0.5", Left "G02006")
        ],
      withinASecond $
        table
          "the limit of 2^4096 on numerators and denominators"
          [ ("1 / 2 ** 4095 / 2", Left "G02086"),
            ("(3 / 2) ** 2585", Left "G02086"),
            ("(3 / 2) ** 4096", Left "G02086"),
            ("1e1301", Left "G02086"),
            ("1e-1301", Left "G02086"),
            ("(3 / 2) ** 100000000000", Left "G02086")
          ],
      testCase "the limit lets the values below it through" $ do
        assertBool "(2 ** 4095) / 3" (isRight (ev "(2 ** 4095) / 3"))
        assertBool "(3 / 2) ** 2584" (isRight (ev "(3 / 2) ** 2584")),
      testCase "the messages of G02086" $
        shownm "2 ** 4096" @?= Left ("G02086", "数が大きすぎます（整数と、分数の分子と分母の絶対値は 2 の 4096 乗未満に限ります）"),
      testCase "typeName names the three types" $
        map typeName [VNat 3, VInt 3, VInt (-3), VRat 3] @?= ["自然数", "整数", "整数", "有理数"],
      testProperty "rounding to 17 digits never meets a tie" $ property $ do
        q <- forAll repeating
        -- the two candidates are k digits apart; q is never halfway
        let r = round17 q
            k = toInteger (max 0 (16 - decimalExponent (abs q)))
            unit = 1 % (10 ^ k)
        annotateShow (r, k)
        assert (abs (q - r) < unit / 2)
        abs (q - r) /== unit / 2,
      testProperty "a finite decimal in prose reads back as the same number" $ property $ do
        n <- forAll (Gen.integral (Range.linearFrom 0 (-(10 ^ (30 :: Int))) (10 ^ (30 :: Int))))
        a <- forAll (Gen.int (Range.linear 0 60))
        b <- forAll (Gen.int (Range.linear 0 60))
        let q = n % (2 ^ a * 5 ^ b)
        case embedValue (mkSpan (FileId 0) 0 0) (VRat q) of
          Left d -> annotateShow d >> failure
          Right t -> do
            annotate (T.unpack t)
            let (neg, body) = maybe (False, t) (True,) (T.stripPrefix "-" t)
                lit = if T.any (== '.') body then body else body <> ".0"
            case evalExpr (Env Map.empty Map.empty) (exprOf lit) of
              Right v -> ((if neg then negate else id) <$> asRat v) === Just q
              Left d -> annotateShow d >> failure,
      testProperty "x + y - y == x, and x / x == 1" $ property $ do
        x <- forAll rational
        y <- forAll rational
        let lit q = "(" <> T.pack (show (numerator q)) <> " / " <> T.pack (show (denominator q)) <> ")"
            lit' q = if numerator q < 0 then "(0 - " <> lit (negate q) <> ")" else lit q
        ev (lit' x <> " + " <> lit' y <> " - " <> lit' y <> " == " <> lit' x) === Right (VBool True)
        if x /= 0 then ev (lit' x <> " / " <> lit' x <> " == 1") === Right (VBool True) else success,
      testProperty "a == div(a, b) * b + a % b" $ property $ do
        a <- forAll (Gen.integral (Range.linearFrom 0 (-1000) 1000))
        b <- forAll (Gen.filter (/= 0) (Gen.integral (Range.linearFrom 0 (-50) 50)))
        let lit n = if n < 0 then "(0 - " <> T.pack (show (negate n :: Integer)) <> ")" else T.pack (show n)
        q <- evalEither (ev ("div(" <> lit a <> ", " <> lit b <> ")"))
        r <- evalEither (ev (lit a <> " % " <> lit b))
        case (asRat q, asRat r) of
          (Just q', Just r') -> do
            fromInteger a === q' * fromInteger b + r'
            assert (abs r' < abs (fromInteger b))
          other -> annotateShow other >> failure
    ]
  where
    isRight = either (const False) (const True)

-- | The value of a number.
asRat :: Value -> Maybe Rational
asRat = \case
  VNat n -> Just (toRational n)
  VInt i -> Just (fromInteger i)
  VRat q -> Just q
  _ -> Nothing

-- | The exponent p with 10^p <= q < 10^(p+1), for q > 0.
decimalExponent :: Rational -> Int
decimalExponent q = case [p | p <- [-2000 .. 2000], 10 ^^ p <= q, q < 10 ^^ (p + 1)] of
  (p : _) -> p
  [] -> error "decimalExponent: out of range"

-- | A rational whose denominator has a prime factor other than 2 and 5.
repeating :: Gen Rational
repeating = do
  n <- Gen.filter (/= 0) (Gen.integral (Range.exponentialFrom 1 (-(10 ^ (40 :: Int))) (10 ^ (40 :: Int))))
  p <- Gen.element [3, 7, 11, 13, 17, 19, 23, 9973]
  a <- Gen.int (Range.linear 0 30)
  b <- Gen.int (Range.linear 0 30)
  e <- Gen.int (Range.linear 1 5)
  let q = n % (p ^ e * 2 ^ a * 5 ^ b)
  if denominator q `mod` p == 0 then pure q else Gen.discard

rational :: Gen Rational
rational = do
  n <- Gen.integral (Range.linearFrom 0 (-(10 ^ (20 :: Int))) (10 ^ (20 :: Int)))
  d <- Gen.integral (Range.linear 1 (10 ^ (20 :: Int)))
  pure (n % d)
