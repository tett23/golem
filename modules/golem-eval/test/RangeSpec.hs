{- | The closed range a...b (docs/adr ADR 0113): the value of the
expression language, and the ranges of lines= of @listing and highlight=
of a code block, as words, strings and expressions.
-}
module RangeSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.Analysis (StaticType (..), inferExpr)
import Golem.Eval.Expr (Env (..), evalExpr)
import Golem.Eval.File (Asset (..), EvalContext (..))
import Golem.Eval.Value (Value (..))
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Syntax (FileId (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The expression of "[= src]".
exprOf :: Text -> A.Located A.Expr
exprOf src =
  let (A.File _ bs, _, ds) = parseAst (FileId 0) ("[= " <> src <> "]\n")
   in case (ds, map A.locValue bs) of
        ([], [A.Paragraph [A.Located _ (A.Expr e)]]) -> e
        other -> error (show other)

-- | An environment with r = 2...3, as @set r = 2...3 makes it.
rangeEnv :: Env
rangeEnv = Env (Map.fromList [("r", VRange 2 3)]) Map.empty

-- | The value of an expression in 'rangeEnv', or the code of its diagnostic.
ev :: Text -> Either Text Value
ev src = either (Left . diagCodeText) Right (evalExpr rangeEnv (exprOf src))

-- | The codes and messages of the diagnostics of a source.
msgs :: Text -> [(Text, Text)]
msgs src = [(c, m) | (c, m, _, _) <- map diagSite (fst (evalSource listingCtx src))]

codes :: Text -> [Text]
codes = map fst . msgs

-- | The codes and the spans of the diagnostics of a source.
sites :: Text -> [(Text, Int, Int)]
sites src = [(c, s, e) | (c, _, s, e) <- map diagSite (fst (evalSource listingCtx src))]

-- | A context with the file src/Main.hs of three lines, for @listing.
listingCtx :: EvalContext
listingCtx = baseCtx {ctxAssets = Map.fromList [("src/Main.hs", AssetText (FileId 22) "l1\nl2\nl3\n")]}

-- | The lines of the code blocks of a source, the lines highlighted, and the first number.
codeOf :: Text -> [([Text], [Text], Maybe Int)]
codeOf src = mapMaybe lns (resultBodies (evalResult listingCtx src))
  where
    lns = \case
      CodeBlock c -> Just (map clText (codeLines c), [clText l | l <- codeLines c, clHighlight l], take1 [fromIntegral n | CodeLine {clNumber = Just n} <- codeLines c])
      _ -> Nothing
    take1 = \case
      (n : _) -> Just n
      [] -> Nothing

-- | The lines highlighted in a code block of the lines a to e.
highlighted :: Text -> [[Text]]
highlighted arg = [h | (_, h, _) <- codeOf ("``` " <> arg <> "\na\nb\nc\nd\ne\nf\ng\n```\n")]

listing :: Text -> Text
listing arg = "@listing src/Main.hs " <> arg <> "\n"

tests :: TestTree
tests =
  testGroup
    "the range literal (docs/adr ADR 0113)"
    [ testGroup
        "the value"
        [ testCase "the value of a range" $ do
            ev "2...3" @?= Right (VRange 2 3)
            ev "1...4 / 2" @?= Right (VRange 1 2)
            ev "-2...3" @?= Right (VRange (-2) 3)
            ev "5...5" @?= Right (VRange 5 5),
          testCase "equality: both ends equal" $ do
            ev "r == (2...3)" @?= Right (VBool True)
            ev "(1...2) == (1...3)" @?= Right (VBool False)
            ev "(1...2) == [1, 2]" @?= Right (VBool False)
            ev "(1...2) != (1...3)" @?= Right (VBool True),
          testCase "the type of a range is SRange" $ do
            inferExpr rangeEnv (exprOf "r") @?= Just SRange
            inferExpr rangeEnv (exprOf "1...3") @?= Just SRange
            inferExpr rangeEnv (exprOf "\"a\"...3") @?= Nothing,
          testCase "comparison and the operators" $ do
            codes "[= (1...2) < (1...3)]\n" @?= ["G02001"]
            codes "[= (1...2) + 1]\n" @?= ["G02001"]
            codes "[= len(1...3)]\n" @?= ["G02007"],
          testCase "a range is not embedded in prose" $
            msgs "[= 1...3]\n" @?= [("G02008", "範囲 は本文に埋め込めません")],
          testCase "an end that is no number is G02110" $ do
            codes "[= \"a\"...3]\n" @?= ["G02110"]
            codes "[= true...3]\n" @?= ["G02110"]
            codes "@set x = \"a\"\n\n@set r = x...3\n" @?= ["G02110"],
          testCase "an end that is not an integer is G02104" $ do
            codes "@set r = 1.5...3\n" @?= ["G02104"]
            codes "@set r = 1...7 / 2\n" @?= ["G02104"]
            msgs "@set r = 1...7 / 2\n" @?= [("G02104", "範囲の端には整数を書きます（書かれた値 3.5 は整数ではありません）")],
          testCase "ends of an integral value and negative ends are taken" $ do
            codes "@set r = 1...4 / 2\n" @?= []
            codes "@set r = -2...3\n" @?= [],
          testCase "the start after the end is G02106" $
            msgs "@set r = 7...3\n" @?= [("G02106", "範囲の始め 7 が終わり 3 より大きくなっています")],
          testCase "a range of a name is not embedded either" $
            codes "@set r = 1...3\n\n[= r]\n" @?= ["G02008"]
        ],
      testGroup
        "lines="
        [ testCase "a range as a word, a string and an expression" $
            mapM_
              (\src -> (src, codeOf src) @?= (src, [(["l2", "l3"], [], Just 2)]))
              [ listing "lines=2...3",
                listing "lines=\"2...3\"",
                listing "lines=[= 2...3]",
                "@set n = 2\n\n" <> listing "lines=[= n...n + 1]",
                "@set r = 2...3\n\n" <> listing "lines=[= r]"
              ],
          testCase "one line" $
            mapM_ (\src -> (src, codeOf src) @?= (src, [(["l2"], [], Just 2)])) [listing "lines=2", listing "lines=[= 2]", listing "lines=2...2"],
          testCase "a negative end, one not an integer and one past the limit" $ do
            codes (listing "lines=3...-1") @?= ["G02103"]
            codes (listing "lines=[= 3...0 - 1]") @?= ["G02103"]
            codes (listing "lines=1...1.5") @?= ["G02104"]
            codes (listing "lines=1...1e1301") @?= ["G02086"]
            msgs (listing "lines=[= 1...3 / 2]") @?= msgs (listing "lines=1...1.5"),
          testCase "a range without an end or with an end that cannot be read is G02110" $
            mapM_
              (\a -> (a, codes (listing a)) @?= (a, ["G02110"]))
              ["lines=1...", "lines=...3", "lines=1...2...3", "lines=1...2..3", "lines=a...3", "lines=1-2...3", "lines=1....2", "lines=[= \"a\"...3]"],
          testCase "the message of G02110 names the item" $
            msgs (listing "lines=a...3") @?= [("G02110", "範囲の端には数を書きます: a...3")],
          testCase "neither a line nor a range is G02105" $ do
            codes (listing "lines=abc") @?= ["G02105"]
            codes (listing "lines=[= true]") @?= ["G02105"]
            msgs (listing "lines=abc") @?= [("G02105", "@listing の lines には行の番号か範囲を書きます: abc")],
          testCase "the start after the end is G02106" $ do
            codes (listing "lines=7...3") @?= ["G02106"]
            codes (listing "lines=[= 7...3]") @?= ["G02106"],
          testCase "two items or an array is G02107" $ do
            codes (listing "lines=1,3") @?= ["G02107"]
            codes (listing "lines=[= [1...2]]") @?= ["G02107"]
            codes (listing "lines=[= [1, 2]]") @?= ["G02107"]
            msgs (listing "lines=1,3") @?= [("G02107", "@listing の lines には範囲を一つだけ書きます: 1,3")],
          testCase "a range out of the file is G02037" $ do
            msgs (listing "lines=2...9") @?= [("G02037", "@listing の lines の範囲がファイルの行（1〜3）を外れています: 2...9")]
            codes (listing "lines=0...2") @?= ["G02037"],
          testCase ".. is G01100 at the argument" $ do
            sites (listing "lines=1..3") @?= [("G01100", 21, 31)]
            codes (listing "lines=\"1..3\"") @?= ["G01100"],
          testCase "the range of - is taken with the notice G02108" $ do
            codeOf (listing "lines=2-3") @?= [(["l2", "l3"], [], Just 2)]
            codeOf (listing "lines=\"2-3\"") @?= [(["l2", "l3"], [], Just 2)]
            msgs (listing "lines=2-3") @?= [("G02108", "- で区切った範囲は廃止予定です。2...3 のように ... で区切ります")]
            codes (listing "lines=3--1") @?= ["G02108", "G02103"]
        ],
      testGroup
        "highlight="
        [ testCase "lines and ranges as a word, a string and an array" $
            mapM_ (\a -> (a, highlighted a) @?= (a, [["c", "e", "f", "g"]])) ["highlight=3,5...7", "highlight=\"3,5...7\"", "highlight=[= [3, 5...7]]"],
          testCase "an array of two numbers is two lines" $
            highlighted "highlight=[= [2, 4]]" @?= [["b", "d"]],
          testCase "neither a line nor a range is G02105" $ do
            codes "``` highlight=3,,5\na\n```\n" @?= ["G02105"]
            codes "``` highlight=[= nil]\na\n```\n" @?= ["G02105"]
            codes "``` highlight=[= [true]]\na\n```\n" @?= ["G02105"],
          testCase "the start after the end is G02106" $
            codes "``` highlight=7...3\na\n```\n" @?= ["G02106"],
          testCase ".. is G01100" $
            codes "``` highlight=3,5..7\na\n```\n" @?= ["G01100"],
          testCase "the range of - is taken with one notice G02108 an argument" $ do
            highlighted "highlight=3,5-7" @?= [["c", "e", "f", "g"]]
            highlighted "highlight=[= \"5-7\"]" @?= [["e", "f", "g"]]
            codes "``` highlight=3,5-7\na\nb\nc\nd\ne\nf\ng\n```\n" @?= ["G02108"]
            codes "``` highlight=[= \"5-7\"]\na\nb\nc\nd\ne\nf\ng\n```\n" @?= ["G02108"]
            codes "``` highlight=1-2,4-5\na\nb\nc\nd\ne\n```\n" @?= ["G02108"]
        ],
      testCase "numbers= takes no range" $ do
        mapM_ (\a -> (a, codes ("``` " <> a <> "\na\n```\n")) @?= (a, ["G02069"])) ["numbers=5-5", "numbers=5...5", "numbers=[= 1...3]"]
        mapM_ (\a -> (a, codes ("``` " <> a <> "\na\n```\n")) @?= (a, [])) ["numbers=5", "numbers=[= 5]", "numbers=true"]
        [n | (_, _, n) <- codeOf "``` numbers=5\na\n```\n"] @?= [Just 5]
    ]
