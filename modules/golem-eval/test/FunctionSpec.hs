{- | The table of the functions of .emet in a .gm (docs/adr/0162): the
namespaces of @import, the values a function takes from .gm and the
errors of the .gm side (G02119 to G02123), the expression context, and a
.emet that could not be loaded. The functions here are written in
Haskell; golem-driver tests the ones of .emet.
-}
module FunctionSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Eval.Functions
import Golem.Eval.Value
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The .emet of the tests: functions/book.emet.
book :: FunctionNamespace
book =
  FunctionNamespace
    { fnInline =
        Map.fromList
          [ ("tax-included", InlineFunction (Params [ArgNat] Nothing []) 0 "" (\vs _ sp -> Right [Text sp (shown vs)])),
            ("price", InlineFunction (Params [ArgNat] Nothing [KeywordParam "tax" ArgBool (VBool True), KeywordParam "unit" ArgString (VString "円")]) 0 "" (\vs _ sp -> Right [Text sp (shown vs)])),
            ("tags", InlineFunction (Params [ArgString] (Just ArgString) []) 0 "" (\vs _ sp -> Right [Text sp (shown vs)])),
            ("emph-twice", InlineFunction noParams 1 "" (\_ slots sp -> Right [CharStyle sp "strong" (concat slots)])),
            ("styled", InlineFunction noParams 0 "" (\_ _ sp -> Right [CharStyle sp "nonexistent" [Text sp "x"]]))
          ],
      fnBlock =
        Map.fromList
          [ ("word-table", BlockFunction (Params [ArgString] Nothing []) True "" (\_ body _ -> Right body)),
            ("rule", BlockFunction noParams False "" (\_ _ sp -> Right [Block sp Nothing (Paragraph Nothing [Text sp "―"])])),
            ("styled", BlockFunction noParams False "" (\_ _ sp -> Right [Block sp Nothing (Paragraph (Just "nonexistent") [Text sp "x"])]))
          ],
      fnExpr =
        Map.fromList
          [ ("total", ExprFunction (Params [ArgList ArgNat] Nothing []) ArgNat "" (\vs _ -> Right (VNat (sum [n | VArray xs <- vs, VNat n <- xs])))),
            ("sum", ExprFunction (Params [] (Just ArgNat) []) ArgNat "" (\vs _ -> Right (VNat (sum [n | VArray xs <- vs, VNat n <- xs]))))
          ],
      fnOthers = Map.fromList [("helper", "pub だけの関数です")]
    }
  where
    shown = foldMap valueShown
    valueShown = \case
      VNat n -> "N" <> tshow n
      VInt n -> "I" <> tshow n
      VString t -> "S" <> t <> ";"
      VBool b -> if b then "T" else "F"
      VArray xs -> "[" <> foldMap valueShown xs <> "]"
      _ -> "?"
    tshow :: (Show a) => a -> Text
    tshow = Data.Text.pack . show

functionCtx :: EvalContext
functionCtx = baseCtx {ctxFunctions = FunctionTable (Map.singleton "functions/book.emet" book) False Set.empty, ctxCharStyles = Set.singleton "strong"}

withImport :: Text -> Text
withImport body = "@import functions/book.emet as book\n\n" <> body

codesOf :: Text -> [Text]
codesOf src = map diagCodeText (fst (evalSource functionCtx (withImport src)))

texts :: Text -> [Text]
texts src = [t | Block _ _ (Paragraph _ is) <- resultBlocks (evalResult functionCtx (withImport src)), Text _ t <- is]

tests :: TestTree
tests =
  testGroup
    "the functions of .emet in .gm (docs/adr/0162)"
    [ testCase "an inline command of a namespace gets its values" $ do
        texts "[book.tax-included 1000]\n" @?= ["N1000"]
        codesOf "[book.tax-included 1000]\n" @?= [],
      testCase "the namespace is the file's: without @import, G02022" $ do
        let (ds, _) = evalSource functionCtx "[book.tax-included 1000]\n"
        map diagCodeText ds @?= ["G02022"],
      testCase "a name the namespace has not is G02022, a block one G02009" $ do
        codesOf "[book.nothing]\n" @?= ["G02022"]
        codesOf "@book.nothing\n" @?= ["G02009"],
      testCase "keyword arguments take their defaults, and the values given" $ do
        texts "[book.price 1000]\n" @?= ["N1000TS円;"]
        texts "[book.price 1000 tax=false unit=\" 円\"]\n" @?= ["N1000FS 円;"]
        codesOf "[book.price 1000 rate=1]\n" @?= ["G02119"],
      testCase "a keyword argument written twice is G02077, as for a built-in command" $
        codesOf "[book.price 1000 tax=false tax=true]\n" @?= ["G02077"],
      testCase "G02120 for the number of positional arguments, G02121 for a type" $ do
        codesOf "[book.tax-included]\n" @?= ["G02120"]
        codesOf "[book.tax-included 1 2]\n" @?= ["G02120"]
        codesOf "[book.tax-included abc]\n" @?= ["G02121"]
        codesOf "[book.price 1 tax=abc]\n" @?= ["G02121"],
      testCase "variable arguments are a list of the rest, maybe empty" $ do
        texts "[book.tags ・ 組版 校正]\n" @?= ["S・;[S組版;S校正;]"]
        texts "[book.tags ・]\n" @?= ["S・;[]"]
        codesOf "[book.tags]\n" @?= ["G02120"]
        codesOf "[book.tags ・ 1]\n" @?= ["G02121"],
      testCase "the prose slots go to the function, and the number of them is G02122" $ do
        let r = evalResult functionCtx (withImport "[book.emph-twice: 本文[note: 注]]\n")
        [length xs | Block _ _ (Paragraph _ [CharStyle _ _ xs]) <- resultBlocks r] @?= [2]
        [n | Block _ _ (Paragraph _ [CharStyle _ _ [_, Note _ n _]]) <- resultBlocks r] @?= [1]
        codesOf "[book.emph-twice]\n" @?= ["G02122"],
      testCase "the body goes to a block command; a body to one that takes none is G02123" $ do
        let r = evalResult functionCtx (withImport "@book.word-table data/words.tsv\n  本体\n")
        [t | Block _ _ (Paragraph _ [Text _ t]) <- resultBlocks r] @?= ["本体"]
        codesOf "@book.rule\n  本体\n" @?= ["G02123"],
      testCase "@label goes to the first block a block command returns" $ do
        let r = evalResult functionCtx (withImport "@label rule\n@book.rule\n")
        [l | Block _ l _ <- resultBlocks r] @?= [Just "rule"],
      testCase "the names a function returns are checked as those of the built-in commands" $ do
        codesOf "[book.styled]\n" @?= ["G02018"]
        codesOf "@book.styled\n" @?= ["G02047"],
      testCase "a pub fn in the expression context" $ do
        texts "[= book.total([1, 2])]\n" @?= ["3"]
        texts "[= book.sum(1, 2, 3)]\n" @?= ["6"]
        texts "[= book.sum()]\n" @?= ["0"]
        codesOf "[= book.total(1)]\n" @?= ["G02121"]
        codesOf "[= book.total()]\n" @?= ["G02120"],
      testCase "a function that is no pub fn in an expression is G02002, which tells why" $ do
        let (ds, _) = evalSource functionCtx (withImport "[= book.helper(1)]\n")
        map diagCodeText ds @?= ["G02002"]
        assertBool "says pub fn" (any (Data.Text.isInfixOf "pub fn" . diagMessage) ds),
      testCase "a call through a namespace whose .emet could not be loaded reports nothing" $ do
        let ctx = baseCtx {ctxFunctions = FunctionTable Map.empty True Set.empty}
            (ds, _) = evalSource ctx (withImport "[book.x 1]\n\n@book.y\n\n[= book.z(1)]\n")
        map diagCodeText ds @?= [],
      testCase "a function is not called after an error of its arguments" $ do
        let f = InlineFunction (Params [ArgNat] Nothing []) 0 "" (\_ _ sp -> Left [diagnostic "G99999" Error sp "called"])
            ctx = baseCtx {ctxFunctions = FunctionTable (Map.singleton "functions/book.emet" emptyNamespace {fnInline = Map.singleton "f" f}) False Set.empty}
            (ds, _) = evalSource ctx (withImport "[book.f abc]\n[book.f]\n[book.f 1 x=1]\n")
        map diagCodeText ds @?= ["G02121", "G02120", "G02119"],
      testCase "the namespace of an .emet counts as used" $ do
        let r = evalResult functionCtx (withImport "[book.tax-included 1]\n")
        Map.keys (usageNamespaceRefs (erUsage r)) @?= ["book"]
        [ns | (ns, _, _) <- usageImports (erUsage r)] @?= ["book"]
    ]
