{- | The CBOR of deferred expressions (golem-doc ADR 0001): the round trip
over every kind of expression, the shape of the @expr@ rule of
schema/golem-doc.cddl checked without the external cddl CLI, and the
shortest encoding of floats at the edges of half and single precision.
-}
module CborExprSpec (tests) where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Ratio (denominator, numerator)
import Data.Word (Word8)
import GHC.Float (double2Float, float2Double)
import Gen (genExpr, genFloat)
import Golem.Doc.Cbor
import Golem.Doc.IR
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Hedgehog
import Test.Tasty
import Test.Tasty.HUnit hiding (assert)
import Test.Tasty.Hedgehog

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

deferred :: AST.Located AST.Expr -> [Inline]
deferred e = [Deferred sp (DeferredExpr e)]

-- | The bytes of one deferred expression, read back as a generic CBOR term.
wireExpr :: AST.Located AST.Expr -> Term
wireExpr e = case deserialiseFromBytes decodeTerm (BL.fromStrict (encodeInlines (deferred e))) of
  Right (_, TList [TList [_, _, t]]) -> t
  other -> error (show other)

-- | Encoded bytes of a single term.
bytes :: Term -> [Word8]
bytes = BS.unpack . toStrictByteString . encodeTerm

-- | The bytes of a deferred inline whose expression is the given term.
inlineWith :: Term -> BS.ByteString
inlineWith t = toStrictByteString (encodeTerm (TList [TList [TInt 11, spanTerm, t]]))

spanTerm :: Term
spanTerm = TList [TInt 0, TInt 0, TInt 1]

tests :: TestTree
tests =
  testGroup
    "deferred expressions in CBOR (golem-doc ADR 0001)"
    [ testProperty "every kind of expression survives the round trip" $ withTests 300 $ property $ do
        e <- forAll genExpr
        decodeInlines (encodeInlines (deferred e)) === Right (deferred e),
      testProperty "every expression has the shape of the expr rule of the CDDL" $ withTests 300 $ property $ do
        e <- forAll genExpr
        let t = wireExpr e
        annotateShow t
        assert (isExpr t),
      testProperty "a float is in the shortest of half, single and double that keeps it" $ property $ do
        d <- forAll genFloat
        let t = floatTerm d
        annotateShow t
        floatWidth t === expectedWidth d,
      intEncodings,
      floatEncodings,
      decoderRejects
    ]

-- ------------------------------------------------------------------ the CDDL, transcribed

-- span = [file: uint, start: uint, end: uint]
isSpan :: Term -> Bool
isSpan = \case
  TList [a, b, c] -> all isUint [a, b, c]
  _ -> False

-- the CDDL int64: -2^63 .. 2^63-1 (golem-doc ADR 0006)
isInt :: Term -> Bool
isInt = \case
  TInt _ -> True
  TInteger i -> i >= -9223372036854775808 && i <= 9223372036854775807
  _ -> False

isUint :: Term -> Bool
isUint t = isInt t && termInteger t >= 0

termInteger :: Term -> Integer
termInteger = \case
  TInt i -> toInteger i
  TInteger i -> i
  _ -> -1

isFloat :: Term -> Bool
isFloat = \case
  THalf _ -> True
  TFloat _ -> True
  TDouble _ -> True
  _ -> False

isTstr :: Term -> Bool
isTstr = \case
  TString _ -> True
  TStringI _ -> True
  _ -> False

isBool :: Term -> Bool
isBool = \case
  TBool _ -> True
  _ -> False

{- | expr = [0, span, int] / [1, span, float] / [2, span, tstr] / [3, span, bool]
/ [4, span] / [5, span, [* expr]] / [6, span, [* [tstr, expr]]] / [7, span, [+ tstr]]
/ [8, span, tstr, [* expr]] / [9, span, expr] / [10, span, 0..11, expr, expr] / [11, span]
-}
isExpr :: Term -> Bool
isExpr = \case
  TList (tag : s : fields) | isSpan s -> case (termInteger tag, fields) of
    (0, [x]) -> isInt x
    (1, [x]) -> isFloat x
    (2, [x]) -> isTstr x
    (3, [x]) -> isBool x
    (4, []) -> True
    (5, [TList xs]) -> all isExpr xs
    (6, [TList kvs]) -> all isEntry kvs
    (7, [TList ns@(_ : _)]) -> all isTstr ns
    (8, [f, TList xs]) -> isTstr f && all isExpr xs
    (9, [x]) -> isExpr x
    (10, [op, a, b]) -> isInt op && termInteger op >= 0 && termInteger op <= 11 && isExpr a && isExpr b
    (11, []) -> True
    _ -> False
  _ -> False
  where
    isEntry = \case
      TList [k, v] -> isTstr k && isExpr v
      _ -> False

-- ------------------------------------------------------------------ floats

data Width = Half | Single | Double
  deriving stock (Eq, Show)

floatWidth :: Term -> Maybe Width
floatWidth = \case
  THalf _ -> Just Half
  TFloat _ -> Just Single
  TDouble _ -> Just Double
  _ -> Nothing

{- | The width an exact value needs, from its rational value: binary16 has
11 significant bits, exponents down to 2^-24 and a largest value of 65504.
-}
expectedWidth :: Double -> Maybe Width
expectedWidth d
  | halfExact = Just Half
  | float2Double (double2Float d) == d = Just Single
  | otherwise = Just Double
  where
    r = abs (toRational d)
    scaled = r * 2 ^ (24 :: Int)
    halfExact = r <= 65504 && denominator scaled == 1 && oddPart (numerator scaled) < 2 ^ (11 :: Int)
    oddPart n
      | n == 0 = 0
      | even n = oddPart (n `div` 2)
      | otherwise = n

floatEncodings :: TestTree
floatEncodings =
  testGroup
    "floats at the edges of half and single precision"
    [ testCase "65504, the largest half, is a half" $ bytes (floatTerm 65504) @?= [0xf9, 0x7b, 0xff],
      testCase "65520 is past the largest half: a single" $ bytes (floatTerm 65520) @?= [0xfa, 0x47, 0x7f, 0xf0, 0x00],
      testCase "2^-14, the smallest normal half, is a half" $ bytes (floatTerm 6.103515625e-5) @?= [0xf9, 0x04, 0x00],
      testCase "2^-24, the smallest subnormal half, is a half" $ bytes (floatTerm 5.960464477539063e-8) @?= [0xf9, 0x00, 0x01],
      testCase "2^-25 is below the halves: a single" $ bytes (floatTerm 2.9802322387695312e-8) @?= [0xfa, 0x33, 0x00, 0x00, 0x00],
      testCase "1 + 2^-10 keeps its bits in a half" $ bytes (floatTerm 1.0009765625) @?= [0xf9, 0x3c, 0x01],
      testCase "1 + 2^-11 needs a single" $ bytes (floatTerm 1.00048828125) @?= [0xfa, 0x3f, 0x80, 0x10, 0x00],
      testCase "3 * 2^-24, a subnormal half with two bits, is a half" $ bytes (floatTerm 1.7881393432617188e-7) @?= [0xf9, 0x00, 0x03],
      testCase "a negative half keeps its sign" $ bytes (floatTerm (-2.5)) @?= [0xf9, 0xc1, 0x00],
      testCase "5e-324, the smallest double, is a double" $ bytes (floatTerm 5.0e-324) @?= [0xfb, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01],
      testCase "the edges read back to the same value" $
        decodeInlines (encodeInlines (deferred (AST.Located sp (AST.EArray [AST.Located sp (AST.EFloat x) | x <- [65504, 65520, 5.960464477539063e-8, 2.9802322387695312e-8, 5.0e-324]]))))
          @?= Right (deferred (AST.Located sp (AST.EArray [AST.Located sp (AST.EFloat x) | x <- [65504, 65520, 5.960464477539063e-8, 2.9802322387695312e-8, 5.0e-324]])))
    ]

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
      testCase "expression tag 12" $
        decodeInlines (inlineWith (TList [TInt 12, spanTerm])) @?= Left "スキーマに合いません: 式",
      testCase "an error expression with a field" $
        decodeInlines (inlineWith (TList [TInt 11, spanTerm, TInt 0])) @?= Left "スキーマに合いません: 式",
      testCase "a hash entry that is not a pair" $
        decodeInlines (inlineWith (TList [TInt 6, spanTerm, TList [TList [TString "k"]]])) @?= Left "スキーマに合いません: 連想配列の要素",
      testCase "a float given as an integer" $
        decodeInlines (inlineWith (TList [TInt 1, spanTerm, TInt 1])) @?= Left "スキーマに合いません: 浮動小数点数",
      testCase "the well-formed counterpart is accepted" $
        decodeInlines (inlineWith (TList [TInt 10, spanTerm, TInt 11, int1, int1]))
          @?= Right (deferred (AST.Located sp (AST.EBinary AST.OpGe (AST.Located sp (AST.EInt 1)) (AST.Located sp (AST.EInt 1)))))
    ]
  where
    int1 = TList [TInt 0, spanTerm, TInt 1]
