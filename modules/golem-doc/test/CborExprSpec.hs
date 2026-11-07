{- | The CBOR of deferred expressions (golem-doc ADR 0001): the range, the
integers, the number literals of the three types, and the floats a plugin
may write (docs/adr ADR 0101). The properties over every kind of
expression, which use the generators, are in the test suite of
golem-doc-gen (docs/adr/0197).
-}
module CborExprSpec (tests) where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Ratio ((%))
import Data.Text qualified as T
import Golem.Doc.Cbor
import Golem.Doc.IR
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

deferred :: AST.Located AST.Expr -> [Inline]
deferred e = [Deferred sp (DeferredExpr e)]

-- | The bytes of one deferred expression, read back as a generic CBOR term.
wireExpr :: AST.Located AST.Expr -> Term
wireExpr e = case deserialiseFromBytes decodeTerm (BL.fromStrict (encodeInlines (deferred e))) of
  Right (_, TList [TList [_, _, t]]) -> t
  other -> error (show other)

-- | The bytes of a deferred inline whose expression is the given term.
inlineWith :: Term -> BS.ByteString
inlineWith t = toStrictByteString (encodeTerm (TList [TList [TInt 11, spanTerm, t]]))

spanTerm :: Term
spanTerm = TList [TInt 0, TInt 0, TInt 1]

tests :: TestTree
tests =
  testGroup
    "deferred expressions in CBOR (golem-doc ADR 0001)"
    [ -- docs/adr ADR 0113
      testCase "a range is [14, span, expr, expr], not an operator of 10, and comes back" $ do
        let e = AST.Located sp (AST.ERange (AST.Located sp (AST.ENat 1)) (AST.Located sp (AST.EInt (-3))))
        wireExpr e @?= TList [TInt 14, spanTerm, TList [TInt 12, spanTerm, TInt 1], TList [TInt 0, spanTerm, TInt (-3)]]
        decodeInlines (encodeInlines (deferred e)) @?= Right (deferred e),
      intEncodings,
      numberLiterals,
      pluginFloats,
      decoderRejects
    ]

-- ------------------------------------------------------------------ numbers

-- | The number literals of the three types (docs/adr ADR 0101).
numberLiterals :: TestTree
numberLiterals =
  testGroup
    "number literals of the three types (docs/adr ADR 0101)"
    [ testCase "a rational is tag 30 in lowest terms" $
        wireExpr (AST.Located sp (AST.ERat (1 % 3))) @?= TList [TInt 13, spanTerm, TTagged 30 (TList [TInt 1, TInt 3])],
      testCase "an integral rational keeps tag 30 with the denominator 1" $
        wireExpr (AST.Located sp (AST.ERat 5)) @?= TList [TInt 13, spanTerm, TTagged 30 (TList [TInt 5, TInt 1])],
      testCase "a natural number is expression 12" $
        wireExpr (AST.Located sp (AST.ENat 5)) @?= TList [TInt 12, spanTerm, TInt 5],
      testCase "the three read back as they were" $ do
        let e = AST.Located sp (AST.EArray [AST.Located sp x | x <- [AST.ERat (1 % 3), AST.ERat 5, AST.ERat (negate (7 % 2)), AST.ENat 5, AST.EInt 5, AST.EInt (-5)]])
        decodeInlines (encodeInlines (deferred e)) @?= Right (deferred e),
      testCase "a rational not in lowest terms is rejected" $
        decodeInlines (inlineWith (TList [TInt 13, spanTerm, TTagged 30 (TList [TInt 2, TInt 4])])) @?= Left "スキーマに合いません: 有理数が既約ではありません",
      testCase "a denominator of 0 is rejected" $
        decodeInlines (inlineWith (TList [TInt 13, spanTerm, TTagged 30 (TList [TInt 1, TInt 0])])) @?= Left "スキーマに合いません: 有理数",
      testCase "a negative natural number is rejected" $
        decodeInlines (inlineWith (TList [TInt 12, spanTerm, TInt (-1)])) @?= Left "スキーマに合いません: 自然数"
    ]

-- | The floats a plugin writes in an expression are their exact rationals (docs/adr ADR 0101).
pluginFloats :: TestTree
pluginFloats =
  testGroup
    "floats written by a plugin (docs/adr ADR 0101)"
    [ testCase "a double is its exact rational" $
        decodeInlines (inlineWith (TList [TInt 1, spanTerm, TDouble 0.1])) @?= Right (deferred (AST.Located sp (AST.ERat (3602879701896397 % 36028797018963968)))),
      testCase "a half and a single too" $ do
        decodeInlines (inlineWith (TList [TInt 1, spanTerm, THalf 0.5])) @?= Right (deferred (AST.Located sp (AST.ERat (1 % 2))))
        decodeInlines (inlineWith (TList [TInt 1, spanTerm, TFloat 0.25])) @?= Right (deferred (AST.Located sp (AST.ERat (1 % 4)))),
      testCase "a negative zero is 0" $
        decodeInlines (inlineWith (TList [TInt 1, spanTerm, TDouble (-0.0)])) @?= Right (deferred (AST.Located sp (AST.ERat 0))),
      testCase "NaN and the infinities have no rational" $ do
        let nonFinite t = either Just (const Nothing) (termInlinesE =<< firstTerm (inlineWith (TList [TInt 1, spanTerm, t])))
        nonFinite (TDouble (0 / 0)) @?= Just (FloatNotFinite "NaN")
        nonFinite (TDouble (1 / 0)) @?= Just (FloatNotFinite "Infinity")
        nonFinite (TDouble (negate (1 / 0))) @?= Just (FloatNotFinite "-Infinity")
        nonFinite (THalf (1 / 0)) @?= Just (FloatNotFinite "Infinity")
    ]
  where
    firstTerm b = case deserialiseFromBytes decodeTerm (BL.fromStrict b) of
      Right (_, t) -> Right t
      Left e -> Left (SchemaError (T.pack (show e)))

intEncodings :: TestTree
intEncodings =
  testGroup
    "integers of an expression use the major types of the CDDL int64 (golem-doc ADR 0006)"
    [ testCase "2^63 - 1 is an unsigned integer of 8 bytes" $
        lastBytes 9 (AST.EInt 9223372036854775807) @?= 0x1b : 0x7f : replicate 7 0xff,
      testCase "-2^63 is a negative integer of 8 bytes" $
        lastBytes 9 (AST.EInt (-9223372036854775808)) @?= 0x3b : 0x7f : replicate 7 0xff,
      testCase "-25 is a negative integer of 1 byte" $
        lastBytes 2 (AST.EInt (-25)) @?= [0x38, 0x18]
    ]
  where
    -- the integer is the last field of the encoded inline
    lastBytes n e = BS.unpack (BS.takeEnd n (encodeInlines (deferred (AST.Located sp e))))

decoderRejects :: TestTree
decoderRejects =
  testGroup
    "the decoder rejects expressions outside the CDDL"
    [ testCase "operator 12" $
        decodeInlines (inlineWith (TList [TInt 10, spanTerm, TInt 12, int1, int1])) @?= Left "スキーマに合いません: 演算子",
      testCase "operator -1" $
        decodeInlines (inlineWith (TList [TInt 10, spanTerm, TInt (-1), int1, int1])) @?= Left "スキーマに合いません: 演算子",
      testCase "an error expression with a field" $
        decodeInlines (inlineWith (TList [TInt 11, spanTerm, TInt 0])) @?= Left "スキーマに合いません: 式",
      testCase "a hash entry that is not a pair" $
        decodeInlines (inlineWith (TList [TInt 6, spanTerm, TList [TList [TString "k"]]])) @?= Left "スキーマに合いません: 連想配列の要素",
      testCase "a float given as an integer" $
        decodeInlines (inlineWith (TList [TInt 1, spanTerm, TInt 1])) @?= Left "スキーマに合いません: 浮動小数点数",
      testCase "expression tag 15, and the range 14 without its ends (docs/adr ADR 0113)" $ do
        decodeInlines (inlineWith (TList [TInt 15, spanTerm])) @?= Left "スキーマに合いません: 式"
        decodeInlines (inlineWith (TList [TInt 14, spanTerm])) @?= Left "スキーマに合いません: 式",
      testCase "the well-formed counterpart is accepted" $
        decodeInlines (inlineWith (TList [TInt 10, spanTerm, TInt 11, int1, int1]))
          @?= Right (deferred (AST.Located sp (AST.EBinary AST.OpGe (AST.Located sp (AST.EInt 1)) (AST.Located sp (AST.EInt 1)))))
    ]
  where
    int1 = TList [TInt 0, spanTerm, TInt 1]
