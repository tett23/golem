{- | The numbers between the host and a plugin (docs/adr ADR 0101): the
arguments of the three number types as a plugin receives them, and the
floats a plugin writes in a deferred expression.
-}
module NumbersSpec (numberTests) where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Ratio ((%))
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.Cbor (documentTerm)
import Golem.Doc.IR hiding (abiVersion)
import Golem.Eval.Value (Value (..))
import Golem.Parser.AST qualified as A
import Golem.Plugin
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

cbor :: Term -> ByteString
cbor = toStrictByteString . encodeTerm

callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 10 20

load :: FilePath -> IO Plugin
load name = do
  src <- TIO.readFile ("test/plugins/" <> name)
  wasm <- watToWasm src >>= either (assertFailure . T.unpack) pure
  loadPlugin wasm >>= either (assertFailure . show) pure

-- | fixed.wat answering every call with the response; shout and upper.
answering :: ByteString -> IO Plugin
answering response = do
  src <- TIO.readFile "test/plugins/fixed.wat"
  let describe = cbor (TList [TList [TString "shout"], TList [TString "upper"], TList []])
      escape = T.pack . concatMap (printf "\\%02x") . BS.unpack
      filled =
        T.replace "{{ABI}}" (T.pack (show abiVersion))
          . T.replace "{{DESCRIBE}}" (escape describe)
          . T.replace "{{DESCRIBE_LEN}}" (T.pack (show (BS.length describe)))
          . T.replace "{{RESPONSE}}" (escape response)
          . T.replace "{{RESPONSE_LEN}}" (T.pack (show (BS.length response)))
          $ src
  wasm <- watToWasm filled >>= either (assertFailure . T.unpack) pure
  loadPlugin wasm >>= either (assertFailure . show) pure

-- | The arguments of a command request as echo.wat sends them back.
argumentsSent :: Plugin -> [Value] -> IO [Term]
argumentsSent p vs = do
  req <- either (assertFailure . show) pure (commandRequest "echo" vs [] callSpan)
  out <- either (assertFailure . show) pure (invokeRaw p req)
  case deserialiseFromBytes decodeTerm (BL.fromStrict out) of
    Right (_, TList [_, _, TList args, _, _]) -> pure [v | TList [_, v] <- args]
    other -> assertFailure (show other)

-- | A deferred expression with its term replaced by the given one.
deferredWith :: Term -> Term
deferredWith e = TList [TList [TInt 11, spanT, e]]
  where
    spanT = TList [TInt 1, TInt 10, TInt 20]

floatExpr :: Term -> Term
floatExpr = TList . ([TInt 1, TList [TInt 1, TInt 10, TInt 20]] <>) . pure

numberTests :: TestTree
numberTests =
  testGroup
    "numbers between the host and a plugin (docs/adr ADR 0101)"
    [ testCase "a rational argument is tag 30, an integral one too; a natural number is an integer" $ do
        p <- load "echo.wat"
        args <- argumentsSent p [VRat (1 % 2), VRat 5, VNat 5, VInt (-5)]
        args @?= [TTagged 30 (TList [TInt 1, TInt 2]), TTagged 30 (TList [TInt 5, TInt 1]), TInt 5, TInt (-5)],
      testCase "a double in the answer is its exact rational, equal to the one of the request" $ do
        let half = DeferredExpr (A.Located callSpan (A.ERat (1 % 2)))
        p <- answering (cbor (TList [deferredWith (floatExpr (TDouble 0.5)), TList []]))
        fmap fst (callCommand p "shout" [] [[Deferred callSpan half]] callSpan) @?= Right [Deferred callSpan half],
      testCase "a double whose rational the request does not have is a DeferredExpr not in it" $ do
        let half = DeferredExpr (A.Located callSpan (A.ERat (1 % 2)))
        p <- answering (cbor (TList [deferredWith (floatExpr (TDouble 1e-300)), TList []]))
        callCommand p "shout" [] [[Deferred callSpan half]] callSpan @?= Left (BadOutput "要求にない DeferredExpr を含んでいます"),
      testCase "NaN and the infinities in the answer of a command" $
        mapM_
          ( \(t, v) -> do
              p <- answering (cbor (TList [deferredWith (floatExpr t), TList []]))
              callCommand p "shout" [] [] callSpan @?= Left (NonFiniteFloat v)
          )
          nonFinite,
      testCase "NaN and the infinities in the answer of a filter" $
        mapM_
          ( \(t, v) -> do
              let doc = Document (FileId 1) [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])]
                  body = TList [TInt 10, TNull, deferredWith (floatExpr t)]
              docT <- case documentTerm doc of
                TList [ver, f, TList [TList [s, l, _]]] -> pure (TList [ver, f, TList [TList [s, l, body]]])
                other -> assertFailure (show other)
              p <- answering (cbor (TList [docT, TList []]))
              applyFilter p "upper" doc @?= Left (NonFiniteFloat v)
          )
          nonFinite,
      -- the audit of 2026-10-28, F-02 and F-09: the decoder rejects what the
      -- types Rational and Natural cannot hold, before Golem.Doc.Validate
      testCase "a rational not in lowest terms in the answer is rejected by the decoder" $ do
        p <- answering (cbor (TList [deferredWith (TList [TInt 13, TList [TInt 1, TInt 10, TInt 20], TTagged 30 (TList [TInt 2, TInt 4])]), TList []]))
        callCommand p "shout" [] [] callSpan @?= Left (BadOutput "スキーマに合いません: 有理数が既約ではありません"),
      testCase "a negative natural number in the answer is rejected by the decoder" $ do
        p <- answering (cbor (TList [TList [TList [TInt 18, TList [TInt 1, TInt 10, TInt 20], TNull, TInt (-1)]], TList []]))
        callCommand p "shout" [] [] callSpan @?= Left (BadOutput "スキーマに合いません: 自然数"),
      testCase "the reason of a float without a finite value" $
        describePluginError (NonFiniteFloat "NaN") @?= "遅延した式に有限でない浮動小数点数（NaN）があります",
      testCase "nonfinite.wat answers a command and a filter with NaN, Infinity and -Infinity" $ do
        p <- load "nonfinite.wat"
        let doc = Document (FileId 1) [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])]
        mapM_
          ( \(name, v) -> do
              callCommand p name [] [] callSpan @?= Left (NonFiniteFloat v)
              applyFilter p name doc @?= Left (NonFiniteFloat v)
          )
          [("nan", "NaN"), ("inf", "Infinity"), ("ninf", "-Infinity")]
    ]
  where
    nonFinite = [(TDouble (0 / 0), "NaN"), (TDouble (1 / 0), "Infinity"), (TDouble (negate (1 / 0)), "-Infinity"), (TFloat (1 / 0), "Infinity"), (THalf (0 / 0), "NaN")]
