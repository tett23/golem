{- | The closed range a...b (docs/adr ADR 0113): the value of the
expression language, and the ranges of lines= of @listing and highlight=
of a code block, as words, strings and expressions.
-}
module RangeSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Analysis (StaticType (..), inferExpr)
import Golem.Eval.Expr (Env, evalExpr, plainEnv)
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
rangeEnv = plainEnv (Map.fromList [("r", VRange 2 3)]) Map.empty

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
            codes (listing "lines=3...-1") @?= ["G02110"]
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
          testCase "ADR 0342 I1: multiple items are accepted in order" $ do
            codeOf (listing "lines=1,3") @?= [(["l1", "l3"], [], Just 1)]
            codeOf (listing "lines=[= [1...2]]") @?= [(["l1", "l2"], [], Just 1)]
            codeOf (listing "lines=[= [1, 2]]") @?= [(["l1", "l2"], [], Just 1)],
          testCase "a range out of the file is G02037" $ do
            msgs (listing "lines=2...9") @?= [("G02037", "@listing の lines の範囲がファイルの行（1〜3）を外れています: 2...9")]
            codes (listing "lines=0...2") @?= ["G02037"],
          testCase ".. is G01100 at the argument" $ do
            sites (listing "lines=1..3") @?= [("G01100", 21, 31)]
            codes (listing "lines=\"1..3\"") @?= ["G01100"],
          testCase "ADR 0342 I2: a dash separator is an error" $ do
            codeOf (listing "lines=2-3") @?= []
            codeOf (listing "lines=\"2-3\"") @?= []
            msgs (listing "lines=2-3") @?= [("G02251", "- で区切った範囲は使えません。2...3 のように両端を残して ... で区切ります")]
            codes (listing "lines=3--1") @?= ["G02110"]
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
          testCase "ADR 0342 I2: highlight reports one error per argument" $ do
            codes "``` highlight=3,5-7\na\nb\nc\nd\ne\nf\ng\n```\n" @?= ["G02251"]
            codes "``` highlight=[= \"5-7\"]\na\nb\nc\nd\ne\nf\ng\n```\n" @?= ["G02251"]
            codes "``` highlight=1-2,4-5\na\nb\nc\nd\ne\n```\n" @?= ["G02251"]
        ],
      testCase "ADR 0342 I1 I2: line ranges use three dots and allow lists" $ do
        codes (listing "lines=1...1") @?= []
        codes (listing "lines=2-3") @?= ["G02251"]
        codes (listing "lines=[= \"2-3\"]") @?= ["G02251"]
        codes (listing "lines=1-2,2-3") @?= ["G02251"]
        codeOf (listing "lines=1...2,3") @?= [(["l1", "l2", "l3"], [], Just 1)]
        codeOf (listing "lines=\"1...2, 3\"") @?= [(["l1", "l2", "l3"], [], Just 1)]
        [map clNumber (codeLines c) | CodeBlock c <- resultBodies (evalResult listingCtx (listing "lines=1,3"))]
          @?= [[Just 1, Just 3]]
        codes (listing "lines=3--1") @?= ["G02110"]
        codes (listing "lines=\"1...-2\"") @?= ["G02110"],
      testCase "ADR 0342 I1: a contiguous listing keeps diff line numbers" $ do
        let patchCtx = baseCtx {ctxAssets = Map.fromList [("patch.txt", AssetText (FileId 23) "+a\n-b\n c\n")]}
            numbers = [map clNumber (codeLines c) | CodeBlock c <- resultBodies (evalResult patchCtx "@listing patch.txt lines=1...3 diff=true\n")]
        numbers @?= [[Just 1, Nothing, Just 2]],
      adr0342Tests,
      testCase "numbers= takes no range" $ do
        codes "``` numbers=5-5\na\n```\n" @?= ["G02069"]
        -- a range where no range is taken is G02113 (docs/adr ADR 0111)
        mapM_ (\a -> (a, codes ("``` " <> a <> "\na\n```\n")) @?= (a, ["G02113"])) ["numbers=5...5", "numbers=[= 1...3]"]
        mapM_ (\a -> (a, codes ("``` " <> a <> "\na\n```\n")) @?= (a, [])) ["numbers=5", "numbers=[= 5]", "numbers=true"]
        [n | (_, _, n) <- codeOf "``` numbers=5\na\n```\n"] @?= [Just 5]
    ]

{- | The rows of the v1.0.0 table of ADR 0342: the codes, their sites
(the argument) and their number, and the lines taken or highlighted.
-}
adr0342Tests :: TestTree
adr0342Tests =
  testGroup
    "ADR 0342: lines= and highlight= with three dots and lists"
    [ testCase "ADR 0342 I1: a line and a range of one line are as before" $ do
        mapM_ (\a -> (a, sevenSites (sevenListing a), sevenCode (sevenListing a)) @?= (a, [], [["l1"]])) ["lines=1", "lines=1...1", "lines=\"1\"", "lines=[= 1...1]"]
        mapM_ (\a -> (a, sevenSites (block a), highlightedOf (block a)) @?= (a, [], [["a"]])) ["highlight=1", "highlight=1...1"],
      testCase "ADR 0342 I1: a list of ranges takes the lines in the order written" $ do
        sevenCode (sevenListing "lines=\"1...3, 5...7\"") @?= [["l1", "l2", "l3", "l5", "l6", "l7"]]
        sevenCode (sevenListing "lines=1...3,5...7") @?= [["l1", "l2", "l3", "l5", "l6", "l7"]]
        sevenCode (sevenListing "lines=\"5...7, 1\"") @?= [["l5", "l6", "l7", "l1"]]
        sevenCode (sevenListing "lines=[= [6, 2...3]]") @?= [["l6", "l2", "l3"]]
        sevenSites (sevenListing "lines=\"1...3, 5...7\"") @?= []
        highlightedOf (block "highlight=\"1...3, 5...7\"") @?= [["a", "b", "c", "e", "f", "g"]],
      testCase "ADR 0342 I1: a space is allowed only after a comma" $ do
        sevenCode (sevenListing "lines=\"1,  3\"") @?= [["l1", "l3"]]
        map fst3 (sevenSites (sevenListing "lines=\"1 ,3\"")) @?= ["G02105"]
        map fst3 (sevenSites (sevenListing "lines=\" 1,3\"")) @?= ["G02105"],
      testCase "ADR 0342 I2: one G02251 at the argument, however many dashes" $
        mapM_
          (\(src, arg) -> (src, sevenSites src) @?= (src, [("G02251", argStart src arg, argStart src arg + T.length arg)]))
          [ (sevenListing "lines=1-2", "lines=1-2"),
            (sevenListing "lines=1-2,4-5", "lines=1-2,4-5"),
            (sevenListing "lines=\"1-2, 4-5\"", "lines=\"1-2, 4-5\""),
            (sevenListing "lines=1...2,4-5", "lines=1...2,4-5"),
            (block "highlight=1-2", "highlight=1-2"),
            (block "highlight=1-2,4-5", "highlight=1-2,4-5"),
            (block "highlight=3,5-7", "highlight=3,5-7")
          ],
      testCase "ADR 0342 I2: a string returned by an expression is read as a word" $ do
        let src = "@set r = \"1-2,4-5\"\n\n" <> sevenListing "lines=[= r]"
        sevenSites src @?= [("G02251", argStart src "lines=[= r]", argStart src "lines=[= r]" + T.length "lines=[= r]")]
        sevenCode src @?= []
        let hl = block "highlight=[= \"4-5\"]"
        sevenSites hl @?= [("G02251", argStart hl "highlight=", argStart hl "highlight=" + T.length "highlight=[= \"4-5\"]")],
      testCase "ADR 0342 I2: the message keeps both ends of the first dash range" $
        [m | (_, m) <- sevenMsgs (sevenListing "lines=1...2,4-5,6-7")]
          @?= ["- で区切った範囲は使えません。4...5 のように両端を残して ... で区切ります"],
      testCase "ADR 0342 I2: a dash range takes no code" $ do
        sevenCode (sevenListing "lines=1-2") @?= []
        highlightedOf (block "highlight=1-2") @?= [[]],
      testCase "ADR 0342 I1: a written negative end is G02110 at the argument" $
        mapM_
          (\arg -> let src = sevenListing arg in (src, sevenSites src) @?= (src, [("G02110", argStart src arg, argStart src arg + T.length arg)]))
          ["lines=3--1", "lines=-1", "lines=\"1...-2\"", "lines=\"1, -2\""],
      testCase "ADR 0342 I1: 1.,.3, 5..,7 and 5..7 are syntax errors" $ do
        map fst3 (sevenSites (sevenListing "lines=\"1.,.3, 5..,7\"")) @?= ["G02105"]
        map fst3 (sevenSites (sevenListing "lines=5..7")) @?= ["G01100"],
      testCase "ADR 0342 I1: an evaluated end of 0 or -1 fails after evaluation" $ do
        map fst3 (sevenSites ("@set n = 0\n\n" <> sevenListing "lines=[= n]")) @?= ["G02037"]
        map fst3 (sevenSites ("@set n = 0 - 1\n\n" <> sevenListing "lines=[= n]")) @?= ["G02103"]
        sevenCode ("@set n = 0\n\n" <> sevenListing "lines=[= n]") @?= []
        map fst3 (sevenSites ("@set n = 0\n\n" <> block "highlight=[= n]")) @?= ["G02069"]
        map fst3 (sevenSites ("@set n = 0 - 1\n\n" <> block "highlight=[= n]")) @?= ["G02103"],
      testCase "ADR 0342 I1: a negative end of a range in a general expression is unchanged" $
        ev "-2...3" @?= Right (VRange (-2) 3)
    ]
  where
    sevenCtx = baseCtx {ctxAssets = Map.fromList [("seven.txt", AssetText (FileId 24) "l1\nl2\nl3\nl4\nl5\nl6\nl7\n")]}
    sevenListing arg = "@listing seven.txt " <> arg <> "\n"
    block arg = "``` " <> arg <> "\na\nb\nc\nd\ne\nf\ng\n```\n"
    sevenDiags src = map diagSite (fst (evalSource sevenCtx src))
    sevenSites src = [(c, s, e) | (c, _, s, e) <- sevenDiags src]
    sevenMsgs src = [(c, m) | (c, m, _, _) <- sevenDiags src]
    blocks src = [c | CodeBlock c <- resultBodies (evalResult sevenCtx src)]
    sevenCode src = [map clText (codeLines c) | c <- blocks src]
    highlightedOf src = [[clText l | l <- codeLines c, clHighlight l] | c <- blocks src]
    argStart src arg = T.length (fst (T.breakOn arg src))
    fst3 (a, _, _) = a
