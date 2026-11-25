{- | The two forms of @import (root ADR 0451): a namespace written with
@* as@, and names listed in braces, which .gm uses without a namespace;
the clashes of the listed names in each space of use, and a .emet that
could not be loaded.
-}
module ImportListSpec (tests) where

import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (maybeToList)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Builtin (pluginCommandName)
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
          [ ("tax-included", inline "TAX"),
            ("x", inline "XI"),
            -- the names of a fixed built-in inline command (root ADR 0453) and of a plugin's
            ("link", inline "S"),
            ("pc", inline "P")
          ],
      fnBlock =
        Map.fromList
          [ ("x", block "XB"),
            ("word-table", block "WT"),
            -- @frame is built in and fixed (root ADR 0453), @grid a plugin's
            ("frame", block "FRAME"),
            ("grid", block "G")
          ],
      fnExpr =
        Map.fromList
          [ ("total", ExprFunction (Params [ArgList ArgNat] Nothing []) ArgNat "" (\vs _ -> Right (VNat (sum [n | VArray xs <- vs, VNat n <- xs])))),
            ("join", ExprFunction noParams ArgString "" (\_ _ -> Right (VString "J"))),
            ("price", ExprFunction noParams ArgNat "" (\_ _ -> Right (VNat 7)))
          ],
      fnOthers = Map.fromList [("helper", "pub だけの関数です")]
    }
  where
    inline t = InlineFunction (Params [] (Just ArgNat) []) 0 "" (\vs _ sp -> Right [Text sp (t <> T.concat [T.pack (show n) | VArray xs <- vs, VNat n <- xs])])
    block t = BlockFunction noParams True "" (\_ body sp -> Right (Block sp Nothing Nothing (Paragraph Nothing [Text sp t]) : body))

-- | A plugin with the inline command pc and the block command grid.
plugins :: PluginHook
plugins =
  noPlugins
    { phCommands = Map.fromList [(n, PluginCommand (\_ _ sp -> Right ([Text sp "PLUGIN"], []))) | n <- maybeToList (pluginCommandName "pc")],
      phBlocks = Map.fromList [("grid", PluginBlockCommand (\_ _ sp -> Right ([Block sp Nothing Nothing (Paragraph Nothing [Text sp "PLUGIN"])], Map.empty, [])))]
    }

ctx :: EvalContext
ctx =
  baseCtx
    { ctxFunctions = FunctionTable (Map.fromList [("functions/book.emet", book), ("functions/other.emet", book)]) False Set.empty,
      ctxImports = Map.fromList [("common/values.gm", Map.fromList [("price", VInt 100), ("toc", VString "T"), ("rate", VNat 8)])],
      ctxPlugins = plugins
    }

-- | The texts of the paragraphs of a source.
texts :: EvalContext -> Text -> [Text]
texts c src = [T.concat [t | Text _ t <- is] | Paragraph _ is <- resultBodies (evalResult c src)]

codes :: EvalContext -> Text -> [Text]
codes c src = map diagCodeText (fst (evalSource c src))

-- | The code and the span of each diagnostic, as the text of the source it covers.
sites :: Text -> [(Text, Text)]
sites src = [(diagCodeText d, covered d) | d <- fst (evalSource ctx src)]
  where
    covered d = T.take (spanEnd (diagSpan d) - spanStart (diagSpan d)) (T.drop (spanStart (diagSpan d)) src)

-- | The diagnostics without their positions, as a sorted list.
unplaced :: Text -> [(Text, Text)]
unplaced src = sort [(diagCodeText d, diagMessage d) | d <- fst (evalSource ctx src)]

emetAll, emetList :: Text -> Text
emetAll body = "@import functions/book.emet * as book\n\n" <> body
emetList body = "@import functions/book.emet { tax-included, x, word-table, total }\n\n" <> body

tests :: TestTree
tests =
  testGroup
    "the names listed by @import (root ADR 0451)"
    [ testCase "root ADR 0451 I1: * as ns reads the namespace as the old form did" $ do
        texts ctx (emetAll "[book.tax-included 1000]\n") @?= ["TAX1000"]
        texts ctx (emetAll "[= book.total([1, 2])]\n") @?= ["3"]
        texts ctx "@import common/values.gm * as v\n\n[= v.price]\n" @?= ["100"]
        codes ctx (emetAll "[book.tax-included 1000]\n\n[= book.total([1, 2])]\n") @?= [],
      testCase "root ADR 0451 I2: a listed name of each kind is the namespace's" $ do
        let pairs =
              [ ("[tax-included 5]\n", "[book.tax-included 5]\n"),
                ("[x 1]\n", "[book.x 1]\n"),
                ("@x\n", "@book.x\n"),
                ("@word-table\n  本文\n", "@book.word-table\n  本文\n"),
                ("[= total([1, 2, 3])]\n", "[= book.total([1, 2, 3])]\n")
              ]
        mapM_ (\(listed, qualified) -> (texts ctx (emetList listed), codes ctx (emetList listed)) @?= (texts ctx (emetAll qualified), codes ctx (emetAll qualified))) pairs,
      testCase "root ADR 0451 I2: one name, two names and the list without spaces" $ do
        texts ctx "@import functions/book.emet { total }\n\n[= total([4])]\n" @?= ["4"]
        texts ctx "@import functions/book.emet { tax-included, total }\n\n[tax-included 1][= total([4])]\n" @?= ["TAX14"]
        texts ctx "@import functions/book.emet {tax-included,total}\n\n[tax-included 1][= total([4])]\n" @?= ["TAX14"]
        codes ctx "@import functions/book.emet {tax-included,total}\n\n[tax-included 1][= total([4])]\n" @?= [],
      testCase "root ADR 0451 I2: a name of an inline and a block command imports both" $ do
        texts ctx "@import functions/book.emet { x }\n\n[x 2]\n\n@x\n" @?= ["XI2", "XB"]
        codes ctx "@import functions/book.emet { x }\n\n[x 2]\n\n@x\n" @?= [],
      testCase "root ADR 0451 I2: a listed variable is the namespace's" $ do
        texts ctx "@import common/values.gm { price }\n\n[= price]\n" @?= texts ctx "@import common/values.gm * as v\n\n[= v.price]\n"
        codes ctx "@import common/values.gm { price }\n\n[= price + 1]\n" @?= [],
      testCase "root ADR 0451 I2: a listed name is seen after the @import line only" $
        codes ctx "[= total([1])]\n\n@import functions/book.emet { total }\n\n[= total([1])]\n" @?= ["G02061"],
      testCase "root ADR 0451 I2: a path may be imported in both forms" $ do
        texts ctx "@import functions/book.emet * as book\n@import functions/book.emet { total }\n\n[= total([1]) + book.total([2])]\n" @?= ["3"]
        codes ctx "@import functions/book.emet * as book\n@import functions/book.emet { total }\n\n[= total([1]) + book.total([2])]\n" @?= [],
      testCase "root ADR 0451 I3: a built-in command's name is G02270, at the name" $ do
        sites "@import functions/book.emet { frame }\n" @?= [("G02270", "frame")]
        sites "@import functions/book.emet { link }\n" @?= [("G02270", "link")],
      testCase "root ADR 0451 I3: the built-in command keeps its name" $
        [u | Paragraph _ is <- resultBodies (evalResult ctx "@import functions/book.emet { link }\n\n[link \"https://example.com/\": a]\n"), Link _ u _ <- is] @?= ["https://example.com/"],
      testCase "root ADR 0451 I3: a plugin command's name is G02271" $ do
        sites "@import functions/book.emet { grid }\n" @?= [("G02271", "grid")]
        sites "@import functions/book.emet { pc }\n" @?= [("G02271", "pc")],
      testCase "root ADR 0451 I3: a name another @import lists is G02272" $ do
        sites "@import functions/book.emet { total }\n@import functions/other.emet { total }\n" @?= [("G02272", "total"), ("G02272", "total")]
        sites "@import functions/book.emet { price }\n@import common/values.gm { price }\n" @?= [("G02272", "price"), ("G02272", "price")],
      testCase "root ADR 0451 I3: a name written before in the list is G02273" $
        sites "@import functions/book.emet { total, total }\n" @?= [("G02273", "total")],
      testCase "root ADR 0451 I3: a variable of @set is G02274, before or after the @import" $ do
        sites "@set price = 1\n@import common/values.gm { price }\n" @?= [("G02274", "price")]
        sites "@import common/values.gm { price }\n@set price = 1\n\n[= price]\n" @?= [("G02274", "price")],
      testCase "root ADR 0451 I3: a built-in name of the expressions is G02277" $
        sites "@import functions/book.emet { join }\n" @?= [("G02277", "join")],
      testCase "root ADR 0451 I3: the spaces of use are apart: the variable toc is no block" $ do
        sites "@import common/values.gm { toc }\n\n[= toc]\n" @?= []
        texts ctx "@import common/values.gm { toc }\n\n[= toc]\n" @?= ["T"],
      testCase "root ADR 0451 I3, I7: each kind of clash gives its code once at each name" $ do
        let clashes = ["@import functions/book.emet { frame, grid, total, total }\n@import functions/other.emet { total }\n"]
        mapM_ (\src -> sort (map fst (sites src)) @?= ["G02270", "G02271", "G02272", "G02272", "G02272", "G02273"]) clashes,
      testCase "root ADR 0451 I4: a reserved name is G02275 alone" $ do
        sites "@import functions/book.emet { meta }\n" @?= [("G02275", "meta")]
        sites "@import common/values.gm { nil }\n" @?= [("G02275", "nil")],
      testCase "root ADR 0451 I4: a name the file does not give is G02276 alone" $ do
        sites "@import functions/book.emet { nothing }\n" @?= [("G02276", "nothing")]
        sites "@import functions/book.emet { helper }\n" @?= [("G02276", "helper")]
        sites "@import common/values.gm { nothing }\n" @?= [("G02276", "nothing")],
      testCase "root ADR 0451 I7: the order of the @import lines changes no diagnostic nor output" $ do
        let a = "@import functions/book.emet { total, x }\n"
            b = "@import functions/other.emet { total }\n"
            c = "@import common/values.gm { price, rate }\n"
            body = "\n[= total([1])][x 1][= price + rate]\n\n@x\n"
            orders = [a <> b <> c, a <> c <> b, b <> a <> c, b <> c <> a, c <> a <> b, c <> b <> a]
            results src = (unplaced (src <> body), texts ctx (src <> body))
        mapM_ (\src -> results src @?= results (a <> b <> c)) orders
        fst (results (a <> b <> c)) @?= replicate 2 ("G02272", "ほかの @import が並べた名前と同じです: total"),
      testCase "root ADR 0451 I7: a @set after or before the @import lines gives the same" $
        unplaced "@import common/values.gm { price }\n@set price = 1\n" @?= unplaced "@set price = 1\n@import common/values.gm { price }\n",
      testCase "root ADR 0451 I8: a .emet that could not be loaded reports nothing for its names" $ do
        let unloaded = ctx {ctxFunctions = (ctxFunctions ctx) {ftUnloaded = True}}
        codes unloaded "@import functions/book.emet { total, nothing, frame }\n\n[= total([1])][x 1]\n\n@word-table\n" @?= ["G02022", "G02009"]
        codes unloaded "@import functions/book.emet { total, x, word-table }\n\n[= total([1])][x 1]\n\n@word-table\n" @?= []
    ]
