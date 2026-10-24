{- | Expressions that refer to doc are deferred to S1 with the S0 values
substituted (docs/markup.md "予約された名前空間", golem-eval ADR 0002).
The substitution is observed through 'evalFile': the expression of the
'Deferred' inline in the document.
-}
module DeferredSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Expr (Env (..), evalExpr)
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Syntax
import Hedgehog (annotateShow, failure, forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Support
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

ctx :: EvalContext
ctx =
  baseCtx
    { ctxMeta = Map.fromList [("title", VString "本の題")]
    }

-- | The deferred expressions of a file, in order.
deferredOf :: Text -> [A.Located A.Expr]
deferredOf src = [e | Block _ _ (Paragraph _ is) <- resultBlocks (evalResult ctx src), Deferred _ (DeferredExpr e) <- is]

-- | An expression without its positions.
data E
  = I Integer
  | F Double
  | S Text
  | B Bool
  | Nil
  | Arr [E]
  | Hash [(Text, E)]
  | Var [Text]
  | Call Text [E]
  | Neg E
  | Bin A.BinaryOp E E
  | Err
  deriving stock (Eq, Show)

shape :: A.Located A.Expr -> E
shape (A.Located _ e) = case e of
  A.EInt i -> I i
  A.EFloat d -> F d
  A.EString s -> S s
  A.EBool b -> B b
  A.ENil -> Nil
  A.EArray xs -> Arr (map shape xs)
  A.EHash kvs -> Hash [(k, shape v) | (k, v) <- kvs]
  A.EVar ns -> Var ns
  A.ECall f xs -> Call f (map shape xs)
  A.EUnary A.Negate x -> Neg (shape x)
  A.EBinary o a b -> Bin o (shape a) (shape b)
  A.EError -> Err

deferredShapes :: Text -> [E]
deferredShapes = map shape . deferredOf

docX :: E
docX = Var ["doc", "x"]

tests :: TestTree
tests =
  testGroup
    "deferred expressions (S0 values substituted)"
    [ testCase "a variable in a binary expression becomes its value" $
        deferredShapes "@set n = 2\n\n[= doc.x + n]\n" @?= [Bin A.Add docX (I 2)],
      testCase "a variable inside an array becomes its value" $
        deferredShapes "@set n = 2\n\n[= [doc.x, n]]\n" @?= [Arr [docX, I 2]],
      testCase "a variable inside a hash becomes its value" $
        deferredShapes "@set n = 2\n\n[= {a: doc.x, b: n}]\n" @?= [Hash [("a", docX), ("b", I 2)]],
      testCase "a variable among the arguments of a call becomes its value" $
        deferredShapes "@set n = 2\n\n[= max(doc.x, n)]\n" @?= [Call "max" [docX, I 2]],
      testCase "a variable under a unary minus becomes its value" $
        deferredShapes "@set n = 2\n\n[= doc.x * -n]\n" @?= [Bin A.Mul docX (Neg (I 2))],
      testCase "a meta reference becomes its value" $
        deferredShapes "[= [doc.x, meta.title]]\n" @?= [Arr [docX, S "本の題"]],
      testCase "an array value becomes an array literal" $
        deferredShapes "@set a = [1, [2.5]]\n\n[= [doc.x, a]]\n" @?= [Arr [docX, Arr [I 1, Arr [F 2.5]]]],
      testCase "a hash value becomes a hash literal with its keys in order" $
        deferredShapes "@set h = {z: true, a: nil}\n\n[= [doc.x, h]]\n" @?= [Arr [docX, Hash [("a", Nil), ("z", B True)]]],
      testCase "a string value becomes a string literal" $
        deferredShapes "@set s = \"x\"\n\n[= [doc.x, s]]\n" @?= [Arr [docX, S "x"]],
      testCase "the value of an expression is substituted, not its source" $
        deferredShapes "@set n = 1 + 2\n\n[= doc.x + n]\n" @?= [Bin A.Add docX (I 3)],
      testCase "a literal stays as it is" $
        deferredShapes "[= doc.x + 1.5]\n" @?= [Bin A.Add docX (F 1.5)],
      testCase "the substituted literal keeps the position of the name" $
        -- "@set n = 2\n\n" is 12 bytes; "[= doc.x + n]" puts n at 12 + 11
        [A.locSpan b | A.Located _ (A.EBinary _ _ b) <- deferredOf "@set n = 2\n\n[= doc.x + n]\n"] @?= [mkSpan (FileId 1) 23 24],
      testProperty "evaluating the deferred expression gives the value of the original one" $ property $ do
        a <- forAll (Gen.integral (Range.linearFrom 0 (-1000) 1000))
        b <- forAll (Gen.integral (Range.linearFrom 0 (-1000) 1000))
        x <- forAll (Gen.integral (Range.linearFrom 0 (-1000) 1000))
        op <- forAll (Gen.element ["+", "-", "*", "<", "=="])
        let body = "[= [a, doc.x " <> op <> " b, {k: max(a, -b)}]]\n"
            src = "@set a = " <> tshow a <> "\n@set b = " <> tshow b <> "\n\n" <> body
            docNs = Map.fromList [("doc", Map.fromList [("x", VInt x)])]
            original = case parseAst (FileId 1) body of
              (A.File _ [A.Located _ (A.Paragraph [A.Located _ (A.Expr e)])], _, _) -> e
              other -> error (show other)
        deferred <- case deferredOf src of
          [e] -> pure e
          other -> annotateShow other >> failure
        evalExpr (Env Map.empty docNs) deferred
          === evalExpr (Env (Map.fromList [("a", VInt a), ("b", VInt b)]) docNs) original
    ]
  where
    tshow :: Integer -> Text
    tshow i = T.pack (show i)
