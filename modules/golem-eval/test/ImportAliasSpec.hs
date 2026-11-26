{- | The aliases of the names listed by @import (root ADR 0458): @{ f as g }@
puts the definition of f in as g, the checks fall on the original name or
on the alias, and the form of an alias follows the rules of the spaces of
use of the original name.
-}
module ImportAliasSpec (tests) where

import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Eval.Functions
import Golem.Eval.Value
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

{- | functions/book.emet: x is an inline command, a block command and a
function of the expressions; toc and toc2 are block commands; meta is a
function of the expressions, with a reserved name.
-}
book :: FunctionNamespace
book =
  FunctionNamespace
    { fnInline =
        Map.fromList
          [ ("tax-included", inline 0 "TAX"),
            ("x", inline 0 "XI"),
            ("my-code", inline 1 "MC"),
            ("n", inline 0 "N")
          ],
      fnBlock =
        Map.fromList
          [ ("x", block "XB"),
            ("word-table", block "WT"),
            ("toc", block "TOC"),
            ("toc2", block "TOC2")
          ],
      fnExpr =
        Map.fromList
          [ ("total", ExprFunction (Params [ArgList ArgNat] Nothing []) ArgNat "" (\vs _ -> Right (VNat (sum [k | VArray xs <- vs, VNat k <- xs])))),
            ("join", ExprFunction noParams ArgString "" (\_ _ -> Right (VString "J"))),
            ("price", ExprFunction noParams ArgNat "" (\_ _ -> Right (VNat 7))),
            ("meta", ExprFunction noParams ArgString "" (\_ _ -> Right (VString "M"))),
            ("x", ExprFunction noParams ArgString "" (\_ _ -> Right (VString "XE")))
          ],
      fnOthers = Map.empty
    }
  where
    inline slotCount t = InlineFunction (Params [] (Just ArgNat) []) slotCount "" (\vs slots sp -> Right [Text sp (t <> T.concat [T.pack (show k) | VArray xs <- vs, VNat k <- xs] <> T.concat [s | sl <- slots, Text _ s <- sl])])
    block t = BlockFunction noParams True "" (\_ body sp -> Right (Block sp Nothing Nothing (Paragraph Nothing [Text sp t]) : body))

ctx :: EvalContext
ctx =
  baseCtx
    { ctxFunctions = FunctionTable (Map.fromList [("functions/book.emet", book), ("functions/other.emet", book)]) False Set.empty,
      ctxImports = ResolvedImports (Map.fromList [("common/values.gm", Map.fromList [("price", VInt 100), ("toc", VString "T"), ("rate", VNat 8), ("n", VNat 3)])])
    }

-- | A .emet that could not be loaded, and an evaluation that does not resolve the variable files.
unloaded, unresolved :: EvalContext
unloaded = ctx {ctxFunctions = (ctxFunctions ctx) {ftUnloaded = True}}
unresolved = ctx {ctxImports = UnresolvedImports}

texts :: EvalContext -> Text -> [Text]
texts c src = [T.concat [t | Text _ t <- is] | Paragraph _ is <- resultBodies (evalResult c src)]

codes :: EvalContext -> Text -> [Text]
codes c src = map diagCodeText (fst (evalSource c src))

-- | The code and the text of the source each diagnostic covers.
sites :: EvalContext -> Text -> [(Text, Text)]
sites c src = [(diagCodeText d, covered d) | d <- fst (evalSource c src)]
  where
    covered d = T.take (spanEnd (diagSpan d) - spanStart (diagSpan d)) (T.drop (spanStart (diagSpan d)) src)

-- | The diagnostics without their positions, as a sorted list.
unplaced :: EvalContext -> Text -> [(Text, Text)]
unplaced c src = sort [(diagCodeText d, diagMessage d) | d <- fst (evalSource c src)]

emet, vars :: Text -> Text -> Text
emet items body = "@import functions/book.emet { " <> items <> " }\n\n" <> body
vars items body = "@import common/values.gm { " <> items <> " }\n\n" <> body

-- | The result of a source: its diagnostics without their places and its texts.
result :: EvalContext -> Text -> ([(Text, Text)], [Text])
result c src = (unplaced c src, texts c src)

tests :: TestTree
tests =
  testGroup
    "the aliases of the listed names (root ADR 0458)"
    [ testCase "root ADR 0458 I1: an alias of each kind refers as the original name does" $ do
        let pairs =
              [ (emet "tax-included as tax" "[tax 5]\n", emet "tax-included" "[tax-included 5]\n"),
                (emet "word-table as wt" "@wt\n  本文\n", emet "word-table" "@word-table\n  本文\n"),
                (emet "total as sum" "[= sum([1, 2])]\n", emet "total" "[= total([1, 2])]\n"),
                (emet "x as y" "[y 1]\n\n@y\n\n[= y()]\n", emet "x" "[x 1]\n\n@x\n\n[= x()]\n"),
                (vars "price as cost" "[= cost + 1]\n", vars "price" "[= price + 1]\n")
              ]
        mapM_ (\(aliased, plain) -> result ctx aliased @?= result ctx plain) pairs
        result ctx (emet "total as sum" "[= sum([1, 2])]\n") @?= ([], ["3"]),
      testCase "root ADR 0458 I1: one original name under itself and an alias, or under two aliases" $ do
        result ctx (emet "total as sum, total" "[= sum([1]) + total([2])]\n") @?= ([], ["3"])
        result ctx (emet "total as sum, total as amount" "[= sum([1]) + amount([2])]\n") @?= ([], ["3"]),
      testCase "root ADR 0458 I1: an alias written as the original name is the item without one" $
        result ctx (emet "total as total" "[= total([4])]\n") @?= result ctx (emet "total" "[= total([4])]\n"),
      testCase "root ADR 0458 I2: the original name of an aliased item is not put in" $ do
        codes ctx (emet "total as sum" "[= total([1])]\n") @?= codes ctx "[= total([1])]\n"
        codes ctx (emet "tax-included as tax" "[tax-included 1]\n") @?= ["G02022"]
        codes ctx (emet "word-table as wt" "@word-table\n") @?= ["G02009"]
        codes ctx (vars "price as cost" "[= price]\n") @?= codes ctx "[= price]\n",
      testCase "root ADR 0458 I2: { toc as mytoc } leaves @toc the built-in table of contents" $ do
        case resultBodies (evalResult ctx (emet "toc as mytoc" "@toc\n\n@mytoc\n")) of
          [ChannelOutput (TocOutput 2), Paragraph Nothing [Text _ "TOC"]] -> pure ()
          other -> assertFailure (show other),
      testCase "root ADR 0458 I3: G02276 falls on the original name" $ do
        sites ctx (emet "nothing as y" "") @?= [("G02276", "nothing")]
        sites ctx (vars "nothing as y" "") @?= [("G02276", "nothing")],
      testCase "root ADR 0458 I3: a reserved original name may be put in under an alias" $
        result ctx (emet "meta as m" "[= m()]\n") @?= ([], ["M"]),
      testCase "root ADR 0458 I3: G02275 falls on the alias" $ do
        sites ctx (emet "total as meta" "") @?= [("G02275", "meta")]
        sites ctx (vars "price as nil" "") @?= [("G02275", "nil")],
      testCase "root ADR 0458 I3: the clashes fall on the alias" $ do
        sites ctx (emet "join as j" "[= j()]\n") @?= []
        sites ctx (emet "x as join" "") @?= [("G02277", "join")]
        sites ctx (emet "total as sum, price as sum" "") @?= [("G02273", "sum")]
        sites ctx ("@set amount = 1\n" <> emet "total as amount" "") @?= [("G02274", "amount")]
        sites ctx (emet "x as frame" "") @?= [("G02270", "frame")]
        sites ctx (emet "total as rate" "" <> vars "rate" "") @?= [("G02272", "rate"), ("G02272", "rate")],
      testCase "root ADR 0458 I3: the clash codes of an alias are those of the name listed without one" $ do
        let other = FunctionNamespace (Map.fromList [("join", fnInline book Map.! "x")]) (Map.fromList [("frame", fnBlock book Map.! "x")]) (Map.fromList [("join", fnExpr book Map.! "x")]) Map.empty
            c = ctx {ctxFunctions = FunctionTable (Map.fromList [("functions/book.emet", book), ("functions/same.emet", other)]) False Set.empty}
            same n = "@import functions/same.emet { " <> n <> " }\n"
        map fst (sites c (emet "x as join" "")) @?= map fst (sites c (same "join"))
        map fst (sites c (emet "x as frame" "")) @?= map fst (sites c (same "frame")),
      testCase "root ADR 0458 I3: an alias overrides a built-in command as 0453 says" $ do
        result ctx (emet "toc2 as toc" "@toc\n") @?= ([], ["TOC2"])
        sites ctx (emet "x as set" "") @?= [("G02270", "set")],
      testCase "root ADR 0458 I4: an item of an original name and an alias, read by its place" $ do
        sites ctx (emet "as" "") @?= [("G02276", "as")]
        sites ctx (emet "as as y" "") @?= [("G02276", "as")]
        result ctx (emet "total as as" "[= as([1])]\n") @?= ([], ["1"])
        sites ctx (emet "total, as" "") @?= [("G02276", "as")]
        mapM_ (\items -> codes ctx (emet items "") @?= ["G03009"]) ["a as", "a as b as c", "a b", "as as"],
      testCase "root ADR 0458 I5: an alias that breaks the rules of a space of use is G02278 once" $ do
        sites ctx (emet "total as a.b" "") @?= [("G02278", "a.b")]
        sites ctx (emet "total as tax-inc" "") @?= [("G02278", "tax-inc")]
        sites ctx (emet "tax-included as Tax" "") @?= [("G02278", "Tax")]
        sites ctx (emet "x as my-x" "") @?= [("G02278", "my-x")]
        sites ctx (emet "x as my_x" "") @?= [("G02278", "my_x")]
        sites ctx (vars "price as my-price" "") @?= [("G02278", "my-price")]
        [diagMessage d | d <- fst (evalSource ctx (emet "total as a.b" ""))] @?= ["別名の形が不正です: a.b"],
      testCase "root ADR 0458 I5: an alias that keeps the rules of all the spaces is put in" $
        result ctx (emet "x as myx" "[myx 1]\n\n@myx\n\n[= myx()]\n") @?= result ctx (emet "x" "[x 1]\n\n@x\n\n[= x()]\n"),
      testCase "root ADR 0458 I5: an alias of G02278 is not put in and clashes with nothing" $ do
        sites ctx (emet "x as my_x" "" <> "@import functions/other.emet { total as my_x }\n") @?= [("G02278", "my_x")]
        sites ctx ("@import functions/other.emet { total as my_x }\n" <> emet "x as my_x" "") @?= [("G02278", "my_x")],
      testCase "root ADR 0458 I8, root ADR 0461 I2: the order of the @import lines with aliases changes no diagnostic nor output" $ do
        let a = "@import functions/book.emet { total as sum, x as y }\n"
            b = "@import functions/other.emet { total as sum }\n"
            c = "@import common/values.gm { price as cost, rate }\n"
            body = "\n[= sum([1])][y 1][= cost + rate]\n\n@y\n"
            orders = [a <> b <> c, a <> c <> b, b <> a <> c, b <> c <> a, c <> a <> b, c <> b <> a]
        mapM_ (\src -> result ctx (src <> body) @?= result ctx (a <> b <> c <> body)) orders
        fst (result ctx (a <> b <> c <> body)) @?= replicate 2 ("G02272", "ほかの @import が並べた名前と同じです: sum") <> [("G02280", "ほかの @import と重なった名前を呼んでいます: sum")],
      testCase "root ADR 0458 I8: an alias that clashes with another @import's name, in either order" $ do
        let a = "@import functions/book.emet { total as n }\n"
            b = "@import common/values.gm { n }\n"
        unplaced ctx (a <> b) @?= unplaced ctx (b <> a)
        map fst (sites ctx (a <> b)) @?= ["G02272", "G02272"],
      testCase "root ADR 0458 I9, root ADR 0461 I1: an alias of a .emet that could not be loaded is not checked, and each call is G02279" $ do
        sites unloaded (emet "total as sum" "[= sum([1])]\n") @?= [("G02279", "sum([1])")]
        codes unloaded (emet "nothing as a.b" "") @?= []
        sites unloaded (emet "total as meta" "") @?= [("G02275", "meta")]
        sites unloaded (emet "x as y" "[y 1]\n\n@y\n") @?= [("G02279", "y"), ("G02279", "y")]
        codes unloaded (emet "total as sum" "[= total([1])]\n") @?= codes unloaded "[= total([1])]\n",
      testCase "root ADR 0458 I9, root ADR 0461 I1: { x as toc } of a .emet that could not be loaded puts out nothing at @toc, with G02279" $ do
        resultBodies (evalResult unloaded (emet "x as toc" "@toc\n")) @?= []
        codes unloaded (emet "x as toc" "@toc\n") @?= ["G02279"],
      testCase "root ADR 0458 I9, root ADR 0461 I3: an alias of a variable file the evaluation does not resolve" $ do
        codes unresolved (vars "price as p" "[= p]\n") @?= ["G02281"]
        codes unresolved (vars "price as my-p" "") @?= []
        sites unresolved (vars "price as meta" "") @?= [("G02275", "meta")]
        codes unresolved (vars "price as p" "[p]\n") @?= codes unresolved (vars "price" "[price]\n"),
      testCase "root ADR 0458 I12: the checks of an item stop at the first that falls" $ do
        sites ctx (emet "nothing as a.b" "") @?= [("G02276", "nothing")]
        sites ctx (emet "nothing as meta" "") @?= [("G02275", "meta")]
        sites ctx (emet "total as Join_" "") @?= []
        sites ctx (emet "x as j.oin" "" <> "@import functions/other.emet { x as j.oin }\n") @?= [("G02278", "j.oin"), ("G02278", "j.oin")],
      testCase "root ADR 0458: the preprocessing of a built-in name follows the alias" $ do
        texts ctx (emet "my-code as code" "[code: **a**]\n") @?= ["MC**a**"]
        texts ctx (emet "n as number-text" "##3##\n") @?= texts ctx (emet "n as number-text" "[number-text 3]\n")
        texts ctx (emet "n as number-text" "##3##\n") @?= ["N3"],
      testCase "root ADR 0458: the lint counts the aliases, at the aliases" $ do
        let u = erUsage (evalResult ctx (emet "total as sum, x as y" "[= sum([1])]\n"))
        [(a, o) | (a, o, _, _) <- usageListed u] @?= [("sum", "total"), ("y", "x")]
        usageListedRefs u @?= Set.fromList ["sum"]
        usageListedRefs (erUsage (evalResult ctx (vars "price as cost" "[= cost]\n"))) @?= Set.fromList ["cost"]
    ]
