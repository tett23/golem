{- | Comparison operators, the integer forms of the built-in functions and
the boundaries of the numeric model (golem-eval ADR 0001, docs/markup.md
"式文脈" and "数の規則"). Small tests: each case evaluates one expression.
-}
module OperatorSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Expr
import Golem.Eval.Value
import Golem.Parser (parseAst)
import Golem.Parser.AST
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

-- | The expression of "[= src]".
exprOf :: Text -> Located Expr
exprOf src =
  let (File _ bs, _, ds) = parseAst (FileId 0) ("[= " <> src <> "]\n")
   in case (ds, map locValue bs) of
        ([], [Paragraph [Located _ (Expr e)]]) -> e
        other -> error (show other)

-- | The value, or the code of the diagnostic.
ev :: Text -> Either Text Value
ev src = either (Left . (\(DiagnosticCode c) -> c) . diagCode) Right (evalExpr (Env Map.empty Map.empty) (exprOf src))

-- | The text the value is embedded as in prose, or the code of the diagnostic.
shown :: Text -> Either Text Text
shown src =
  ev src >>= either (Left . (\(DiagnosticCode c) -> c) . diagCode) Right . embedValue (mkSpan (FileId 0) 0 0)

-- | One test per row: the source of the expression and its value.
table :: String -> [(Text, Either Text Value)] -> TestTree
table name rows = testGroup name [testCase (T.unpack src) (ev src @?= expected) | (src, expected) <- rows]

tests :: TestTree
tests =
  testGroup
    "operators, built-ins and numeric boundaries (golem-eval ADR 0001)"
    [ comparisons,
      integerBuiltins,
      powers,
      numericBoundaries
    ]

comparisons :: TestTree
comparisons =
  testGroup
    "comparison operators"
    [ table
        "ordering of numbers"
        [ ("3 <= 3", Right (VBool True)),
          ("4 <= 3", Right (VBool False)),
          ("3 > 2", Right (VBool True)),
          ("2 > 2", Right (VBool False)),
          ("2 >= 2", Right (VBool True)),
          ("1 >= 2", Right (VBool False)),
          ("1 < 2", Right (VBool True)),
          ("2 < 2", Right (VBool False))
        ],
      table
        "an integer compared with a float is converted to a float"
        [ ("1 < 1.5", Right (VBool True)),
          ("2.5 > 2", Right (VBool True)),
          ("2 <= 2.0", Right (VBool True)),
          ("3 >= 3.5", Right (VBool False)),
          -- 2^53 + 1 converts to 2^53, the nearest double
          ("9007199254740993 == 9007199254740992.0", Right (VBool True))
        ],
      table
        "two integers are compared exactly, beyond the precision of a double"
        [ ("9007199254740993 == 9007199254740992", Right (VBool False)),
          ("9007199254740993 > 9007199254740992", Right (VBool True))
        ],
      table
        "strings are ordered by code point"
        [ ("\"b\" > \"a\"", Right (VBool True)),
          ("\"a\" <= \"a\"", Right (VBool True)),
          ("\"ab\" < \"b\"", Right (VBool True)),
          ("\"a\" >= \"ab\"", Right (VBool False)),
          -- U+FF71 < U+1F600; in UTF-16 the surrogate D83D would come first
          ("\"ｱ\" < \"😀\"", Right (VBool True))
        ],
      table
        "!= is the negation of =="
        [ ("1 != 2", Right (VBool True)),
          ("1 != 1.0", Right (VBool False)),
          ("\"a\" != \"b\"", Right (VBool True)),
          ("nil != nil", Right (VBool False)),
          ("true != false", Right (VBool True))
        ],
      table
        "equality of values of other types"
        [ ("true == true", Right (VBool True)),
          ("nil == nil", Right (VBool True)),
          ("\"1\" == 1", Right (VBool False)),
          ("[1, 2] == [1, 2]", Right (VBool True)),
          ("{a: 1} == {a: 2}", Right (VBool False))
        ],
      table
        "ordering is only for numbers and for strings"
        [ ("1 < \"a\"", Left "G0201"),
          ("true < false", Left "G0201"),
          ("nil >= nil", Left "G0201"),
          ("[1] > [0]", Left "G0201")
        ]
    ]

integerBuiltins :: TestTree
integerBuiltins =
  testGroup
    "built-in functions"
    [ table
        "floor, ceil, round and abs keep an integer an integer"
        [ ("floor(3)", Right (VInt 3)),
          ("ceil(-3)", Right (VInt (-3))),
          ("round(7)", Right (VInt 7)),
          ("abs(-5)", Right (VInt 5)),
          ("abs(5)", Right (VInt 5))
        ],
      table
        "floor, ceil and round of a float are integers"
        [ ("floor(-2.5)", Right (VInt (-3))),
          ("ceil(-2.5)", Right (VInt (-2))),
          ("floor(2.5)", Right (VInt 2)),
          ("ceil(2.1)", Right (VInt 3)),
          ("round(2.5)", Right (VInt 3)),
          ("round(-0.4)", Right (VInt 0))
        ],
      table
        "abs of a float is a float"
        [ ("abs(-2.5)", Right (VFloat 2.5)),
          ("abs(0.0)", Right (VFloat 0))
        ],
      table
        "round with digits is a float rounded half away from zero"
        [ ("round(1.25, 1)", Right (VFloat 1.3)),
          ("round(-1.25, 1)", Right (VFloat (-1.3))),
          ("round(2, 1)", Right (VFloat 2)),
          ("round(1.5, 0)", Right (VFloat 2)),
          ("round(0.125, 5)", Right (VFloat 0.125))
        ],
      testGroup
        "fixed pads to the digits"
        [ testCase "fixed(2, 3)" $ shown "fixed(2, 3)" @?= Right "2.000",
          testCase "fixed(-0.5, 0)" $ shown "fixed(-0.5, 0)" @?= Right "-1",
          testCase "fixed(0.05, 1)" $ shown "fixed(0.05, 1)" @?= Right "0.1",
          testCase "fixed(-0.04, 1) drops the sign of a zero" $ shown "fixed(-0.04, 1)" @?= Right "0.0"
        ],
      table
        "len of an array and of a string"
        [ ("len([1, 2, 3])", Right (VInt 3)),
          ("len([])", Right (VInt 0)),
          ("len(\"\")", Right (VInt 0)),
          ("len(\"😀a\")", Right (VInt 2))
        ],
      table
        "min and max"
        [ ("min(3, 1, 2)", Right (VInt 1)),
          ("max(-1, -2.5)", Right (VInt (-1))),
          ("min(4)", Right (VInt 4)),
          ("min(1, \"a\")", Left "G0201")
        ],
      table
        "div rounds toward negative infinity"
        [ ("div(7, 2)", Right (VInt 3)),
          ("div(-7, 2)", Right (VInt (-4))),
          ("div(7, -2)", Right (VInt (-4))),
          ("-7 % 2", Right (VInt 1)),
          ("7 % -2", Right (VInt (-1)))
        ],
      table
        "an argument of the wrong kind is G0207"
        [ ("len(1)", Left "G0207"),
          ("floor(\"a\")", Left "G0207"),
          ("abs(nil)", Left "G0207"),
          ("fixed(1.5)", Left "G0207"),
          ("fixed(1.5, -1)", Left "G0207"),
          ("round(1.5, 1.0)", Left "G0207"),
          ("div(1)", Left "G0207")
        ],
      table
        "the constants are the nearest doubles"
        [ ("pi", Right (VFloat 3.141592653589793)),
          ("e", Right (VFloat 2.718281828459045))
        ]
    ]

powers :: TestTree
powers =
  table
    "** with an integer exponent"
    [ ("2 ** 0", Right (VInt 1)),
      ("0 ** 0", Right (VInt 1)),
      ("(-2) ** 3", Right (VInt (-8))),
      ("2 ** 100", Right (VInt 1267650600228229401496703205376)),
      ("2 ** -2", Right (VFloat 0.25)),
      ("(-2) ** -1", Right (VFloat (-0.5))),
      ("2.0 ** -2", Right (VFloat 0.25)),
      ("1.5 ** 2", Right (VFloat 2.25)),
      ("2.0 ** 0", Right (VFloat 1)),
      ("\"a\" ** 2", Left "G0201")
    ]

numericBoundaries :: TestTree
numericBoundaries =
  testGroup
    "numeric boundaries"
    [ table
        "integers have arbitrary precision"
        [ ("9223372036854775807 + 1", Right (VInt 9223372036854775808)),
          ("-9223372036854775808 - 1", Right (VInt (-9223372036854775809))),
          ("18446744073709551616 * 18446744073709551616", Right (VInt 340282366920938463463374607431768211456))
        ],
      table
        "a float that overflows is G0204"
        [ ("2.0 ** 1023", Right (VFloat 8.98846567431158e307)),
          ("2.0 ** 1024", Left "G0204"),
          -- 10^309 is beyond the largest double when converted
          ("10 ** 309 + 0.5", Left "G0204"),
          ("10 ** 309 / 1", Left "G0204")
        ],
      testGroup
        "embedding"
        [ testCase "a small float is written positionally" $ shown "0.0000001" @?= Right "0.0000001",
          testCase "a negative float uses the ASCII minus" $ shown "-1.5" @?= Right "-1.5",
          testCase "a negative zero from multiplication is 0" $ shown "-1.0 * 0" @?= Right "0",
          testCase "the largest double is written without an exponent" $
            shown "2.0 ** 1023"
              @?= Right "89884656743115800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
          testCase "an integer is written with all its digits" $ shown "2 ** 70" @?= Right "1180591620717411303424",
          testCase "a string is embedded as it is" $ shown "\"[x]\"" @?= Right "[x]"
        ]
    ]
