{- | The CBOR of the deferred expressions the generators make (golem-doc
ADR 0001): every kind of expression survives the round trip, and has the
shape of the @expr@ rule of schema/golem-doc.cddl, checked without the
external cddl CLI. These properties of golem-doc are here, not in the test
suite of golem-doc, since that suite cannot depend on this package, which
depends on golem-doc (docs/adr/0197).
-}
module CborExprSpec (tests) where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm)
import Data.ByteString.Lazy qualified as BL
import Golem.Doc.Cbor
import Golem.Doc.IR
import Golem.DocGen (genExpr)
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Hedgehog
import Test.Tasty
import Test.Tasty.Hedgehog

-- sp, deferred and wireExpr are copies of those of the test suite of
-- golem-doc (docs/adr/0197).

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

deferred :: AST.Located AST.Expr -> [Inline]
deferred e = [Deferred sp (DeferredExpr e)]

-- | The bytes of one deferred expression, read back as a generic CBOR term.
wireExpr :: AST.Located AST.Expr -> Term
wireExpr e = case deserialiseFromBytes decodeTerm (BL.fromStrict (encodeInlines (deferred e))) of
  Right (_, TList [TList [_, _, t]]) -> t
  other -> error (show other)

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
        assert (isExpr t)
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

-- rational = #6.30([numerator: int64, denominator: 1..9223372036854775807])
isRational :: Term -> Bool
isRational = \case
  TTagged 30 (TList [n, d]) -> isInt n && isInt d && termInteger d >= 1
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

{- | expr = [0, span, int64] / [2, span, tstr] / [3, span, bool]
/ [4, span] / [5, span, [* expr]] / [6, span, [* [tstr, expr]]] / [7, span, [+ tstr]]
/ [8, span, tstr, [* expr]] / [9, span, expr] / [10, span, 0..11, expr, expr] / [11, span]
/ [12, span, uint64] / [13, span, rational]; the host writes no [1, span, float]
-}
isExpr :: Term -> Bool
isExpr = \case
  TList (tag : s : fields) | isSpan s -> case (termInteger tag, fields) of
    (0, [x]) -> isInt x
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
    (12, [x]) -> isUint x
    (13, [x]) -> isRational x
    (14, [a, b]) -> isExpr a && isExpr b
    _ -> False
  _ -> False
  where
    isEntry = \case
      TList [k, v] -> isTstr k && isExpr v
      _ -> False
