{- | The diagnostics that follow from another error (root ADR 0461): a
call or a reference of a name of a .emet that could not be loaded
(G02279), of a name of G02272 (G02280), of a name imported in the
evaluation of a file without manifest (G02281), and a name a plugin might
have given after the plugins failed (G02282), one at each expression,
inline command and block command; and G02011 and G02123 by the same rules
in a group with a name the evaluation does not resolve.
-}
module FollowOnSpec (tests) where

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

-- | functions/book.emet: total and price of the expressions, n an inline command, b a block command.
book :: FunctionNamespace
book =
  FunctionNamespace
    { fnInline = Map.fromList [("n", InlineFunction noParams 0 "" (\_ _ sp -> Right [Text sp "N"]))],
      fnBlock = Map.fromList [("b", BlockFunction noParams False "" (\_ _ sp -> Right [Block sp Nothing Nothing (Paragraph Nothing [Text sp "B"])]))],
      fnExpr =
        Map.fromList
          [ ("total", ExprFunction (Params [ArgNat] Nothing []) ArgNat "" (\vs _ -> Right (case vs of [VNat k] -> VNat k; _ -> VNat 0))),
            ("price", ExprFunction noParams ArgNat "" (\_ _ -> Right (VNat 7)))
          ],
      fnOthers = Map.empty
    }

ctx :: EvalContext
ctx =
  baseCtx
    { ctxFunctions = FunctionTable (Map.fromList [("functions/book.emet", book), ("functions/other.emet", book)]) False Set.empty,
      ctxImports = ResolvedImports (Map.fromList [("common/values.gm", Map.fromList [("price", VInt 100)])])
    }

-- | The .emet could not be loaded; the evaluation of a file without manifest; the plugins failed to load.
unloaded, loose, failed :: EvalContext
unloaded = ctx {ctxFunctions = (ctxFunctions ctx) {ftUnloaded = True}}
loose = ctx {ctxImports = UnresolvedImports, ctxFunctions = noFunctions}
failed = ctx {ctxPlugins = noPlugins {phFailed = True}}

codes :: EvalContext -> Text -> [Text]
codes c s = map diagCodeText (fst (evalSource c s))

count :: Text -> EvalContext -> Text -> Int
count code c s = length (filter (== code) (codes c s))

messages :: Text -> EvalContext -> Text -> [Text]
messages code c s = [diagMessage d | d <- fst (evalSource c s), diagCodeText d == code]

-- | G02011 and G02123 alone.
grouped :: EvalContext -> Text -> [Text]
grouped c s = filter (`elem` ["G02011", "G02123"]) (codes c s)

listed :: Text -> Text
listed items = "@import functions/book.emet { " <> items <> " }\n\n"

tests :: TestTree
tests =
  testGroup
    "root ADR 0461"
    [ testCase "root ADR 0461 I1: { total } of a .emet with an error and [= total(1)] twice is G02279 twice" $
        codes unloaded (listed "total" <> "[= total(1)]\n\n[= total(1)]\n") @?= ["G02279", "G02279"],
      testCase "root ADR 0461 I1: [= total(1) + total(2)] is one G02279, the evaluation stopping at the first" $
        codes unloaded (listed "total" <> "[= total(1) + total(2)]\n") @?= ["G02279"],
      testCase "root ADR 0461 I1: a name of each of two .emet, one called once each, is G02279 twice" $
        codes unloaded "@import functions/book.emet { total }\n@import functions/other.emet { price }\n\n[= total(1)]\n\n[= price()]\n" @?= ["G02279", "G02279"],
      testCase "root ADR 0461 I1: * as s and @s.b three times is G02279 three times" $ do
        codes unloaded "@import functions/book.emet * as s\n\n@s.b\n\n@s.b\n\n@s.b\n" @?= ["G02279", "G02279", "G02279"]
        messages "G02279" unloaded "@import functions/book.emet * as s\n\n@s.b\n" @?= [".emet の誤りのため、この名前を呼べません: @s.b"],
      testCase "root ADR 0461 I1: { total as sum } and [= sum(1)] is one G02279 of the name sum" $
        messages "G02279" unloaded (listed "total as sum" <> "[= sum(1)]\n") @?= [".emet の誤りのため、この名前を呼べません: sum"],
      testCase "root ADR 0461 I1: each inline command, block command and expression of the namespace or the list is one" $ do
        count "G02279" unloaded "@import functions/book.emet * as s\n\n[s.n] [s.n]\n\n[= s.total(1)]\n" @?= 3
        count "G02279" unloaded (listed "n, b" <> "[n][n]\n\n@b\n\n@b\n") @?= 4
        messages "G02279" unloaded (listed "n" <> "[n]\n") @?= [".emet の誤りのため、この名前を呼べません: n"],
      testCase "root ADR 0461 I1: a call of G02279 puts out nothing" $
        resultBodies (evalResult unloaded (listed "b" <> "@b\n")) @?= [],
      testCase "root ADR 0461 I1: no G02276 nor clash for a name of a .emet that could not be loaded" $
        codes unloaded (listed "nothing") @?= [],
      testCase "root ADR 0461 I2, I6: two @import listing { n } and [n] once is G02272 twice and G02280 once" $ do
        let s = "@import functions/book.emet { n }\n@import functions/other.emet { n }\n\n[n]\n"
        codes ctx s @?= ["G02272", "G02272", "G02280"]
        messages "G02280" ctx s @?= ["ほかの @import と重なった名前を呼んでいます: n"],
      testCase "root ADR 0461 I2: each call and reference of a name of G02272 is one G02280" $ do
        let two = "@import functions/book.emet { b, total }\n@import functions/other.emet { b, total }\n\n"
        count "G02280" ctx (two <> "@b\n\n@b\n\n[= total(1) + total(2)]\n") @?= 3
        count "G02272" ctx (two <> "@b\n") @?= 4,
      testCase "root ADR 0461 I3: { price } of a variable file and [= price], [= price + 1] without manifest is G02281 twice" $ do
        let s = "@import common/values.gm { price }\n\n[= price]\n\n[= price + 1]\n"
        codes loose s @?= ["G02281", "G02281"]
        messages "G02281" loose s @?= replicate 2 "マニフェストの無いファイルでは、取り込んだ名前を解きません: price",
      testCase "root ADR 0461 I3, I6: @set y = price, [= y] without manifest is G02281 once and G02002 once" $
        codes loose "@import common/values.gm { price }\n\n@set y = price\n\n[= y]\n" @?= ["G02281", "G02002"],
      testCase "root ADR 0461 I3: { total } of a .emet and [= total(1)] without manifest is one G02281" $
        codes loose (listed "total" <> "[= total(1)]\n") @?= ["G02281"],
      testCase "root ADR 0461 I3: a reference through the namespace of a variable file without manifest is G02281" $
        messages "G02281" loose "@import common/values.gm * as v\n\n[= v.price]\n" @?= ["マニフェストの無いファイルでは、取り込んだ名前を解きません: v.price"],
      testCase "root ADR 0461 I4: two unknown inline commands after the plugins failed are G02282 twice" $ do
        codes failed "[nope] [nada]\n" @?= ["G02282", "G02282"]
        messages "G02282" failed "[nope]\n" @?= ["プラグインの誤りのため、この名前のコマンドがあるかを決められません: nope"],
      testCase "root ADR 0461 I4: an unknown block command and an undeclared channel after the plugins failed are G02282" $ do
        codes failed "@nope\n\n@channel side\n" @?= ["G02282", "G02282"]
        messages "G02282" failed "@nope\n" @?= ["プラグインの誤りのため、この名前のコマンドがあるかを決められません: @nope"]
        messages "G02282" failed "@channel side\n" @?= ["プラグインの誤りのため、この名前のコマンドがあるかを決められません: side"],
      testCase "root ADR 0461 I4: the same sites are G02022, G02009 and G02090 when the plugins loaded" $
        codes ctx "[nope] [nada]\n\n@nope\n\n@channel side\n" @?= ["G02022", "G02022", "G02009", "G02090"],
      testCase "root ADR 0461 I5: @b of a .emet not loaded, @lang en, @toc and a paragraph is G02011" $ do
        let s = listed "b" <> "@b\n@lang en\n@toc\n段落\n"
        grouped unloaded s @?= ["G02011"]
        grouped unloaded s @?= grouped ctx "@index\n@lang en\n@toc\n段落\n",
      testCase "root ADR 0461 I5: @label x, @b, @toc and a paragraph is G02011" $ do
        let s = listed "b" <> "@label x\n@b\n@toc\n段落\n"
        grouped unloaded s @?= ["G02011"]
        grouped unloaded s @?= grouped ctx "@label x\n@index\n@toc\n段落\n",
      testCase "root ADR 0461 I5: @b of a .emet not loaded and the next block, or ::: after it, as @index" $ do
        grouped unloaded (listed "b" <> "@b\n段落\n") @?= grouped ctx "@index\n段落\n"
        grouped unloaded (listed "b" <> "@b\n:::\n段落\n:::\n") @?= grouped ctx "@index\n:::\n段落\n:::\n"
        grouped unloaded "@import functions/book.emet * as s\n\n@label x\n@s.b\n@toc\n段落\n" @?= grouped ctx "@label x\n@index\n@toc\n段落\n",
      testCase "root ADR 0461 I5: a name of G02272 and an unknown block command after the plugins failed, as @index" $ do
        let two = "@import functions/book.emet { b }\n@import functions/other.emet { b }\n\n"
        grouped ctx (two <> "@label x\n@b\n@toc\n段落\n") @?= grouped ctx "@label x\n@index\n@toc\n段落\n"
        grouped failed "@label x\n@nope\n@toc\n段落\n" @?= grouped ctx "@label x\n@index\n@toc\n段落\n",
      testCase "root ADR 0461 I6: the calls of a .emet loaded without errors are as before" $ do
        codes ctx (listed "total, n, b" <> "[= total(3)] [n]\n\n@b\n") @?= []
        [T.concat [t | Text _ t <- is] | Paragraph _ is <- resultBodies (evalResult ctx (listed "total, n, b" <> "[= total(3)] [n]\n\n@b\n"))] @?= ["3 N", "B"]
    ]
