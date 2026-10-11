module FileSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Parser (parseAst)
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

ctx :: EvalContext
ctx =
  EvalContext
    { ctxFile = FileId 1,
      ctxPath = "ch/01.gm",
      ctxProfile = Dev,
      ctxMeta = Map.fromList [("title", VString "本の題")],
      ctxImports = Map.fromList [("common/values.gm", Map.fromList [("price", VInt 100)])],
      ctxSwatches = Set.fromList ["accent"],
      ctxCharStyles = Set.fromList ["term"],
      ctxDefaultKenten = "sesame",
      ctxCiteKeys = Set.fromList ["knuth1981"],
      ctxAssets =
        Map.fromList
          [ ("images/a.png", Nothing),
            ("images/a.pdf", Nothing),
            ("data.csv", Just "a,b\n1,\"x,y\"\n"),
            ("src/Main.hs", Just "l1\nl2\nl3\n")
          ],
      ctxPlugins = noPlugins
    }

run :: EvalContext -> Text -> ([BlockBody], [Text])
run c src =
  let (file, _, pds) = parseAst (FileId 1) src
      r = evalFile c file
   in (map blockBody (docBlocks (erDocument r)), map code (pds <> erDiagnostics r))
  where
    code d = let DiagnosticCode x = diagCode d in x

body :: Text -> [BlockBody]
body = fst . run ctx

errs :: Text -> [Text]
errs = snd . run ctx

stripSpans :: [Inline] -> [Text]
stripSpans = concatMap go
  where
    go = \case
      Text _ t -> [t]
      Strong _ xs -> "<strong>" : stripSpans xs
      Note _ n xs -> ("<note " <> tshow n <> ">") : stripSpans xs
      Ruby _ _ segs -> ["<ruby " <> tshow (length segs) <> ">"]
      Number _ n st -> ["<number " <> tshow n <> " " <> tshow st <> ">"]
      Ref _ k l -> ["<ref " <> tshow k <> " " <> l <> ">"]
      Deferred _ _ -> ["<deferred>"]
      other -> [tshow other]
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show

paraOf :: Text -> [Text]
paraOf src = case body src of
  [Paragraph is] -> stripSpans is
  other -> error (show other)

tests :: TestTree
tests =
  testGroup
    "file evaluation, S0 (ADR 0002)"
    [ testCase "variables, expressions and meta" $
        paraOf "@set x = 2\n\n[= x * 3] と [= meta.title]\n" @?= ["6 と 本の題"],
      testCase "redefinition and use before definition are errors" $ do
        errs "@set x = 1\n\n@set x = 2\n" @?= ["G0224"]
        errs "[= y]\n\n@set y = 1\n" @?= ["G0202"],
      testCase "imports bind a namespace" $
        paraOf "@import common/values.gm as v\n\n[= v.price + 1]\n" @?= ["101"],
      testCase "doc becomes a deferred expression; forbidden in headings" $ do
        paraOf "@set n = 1\n\n[= doc.chapters.count + n]\n" @?= ["<deferred>"]
        errs "# 全 [= doc.chapters.count] 章\n" @?= ["G0214"]
        errs "# [ref-title intro]\n" @?= ["G0214"],
      testCase "notes are numbered per file" $
        paraOf "a[note: 一]b[note: 二]\n" @?= ["a", "<note 1>", "一", "b", "<note 2>", "二"],
      testCase "ruby segments" $ do
        paraOf "[ruby: 東/京|とう/きょう][ruby: 五月雨|さみだれ][ruby: お/父/さん|/とう/]\n" @?= ["<ruby 2>", "<ruby 1>", "<ruby 3>"]
        errs "[ruby: 東/京|とう]\n" @?= ["G0215"]
        errs "[ruby: [ruby: a|b]|c]\n" @?= ["G0216"],
      testCase "number-text" $ do
        paraOf "[number-text 10 style=tcy]\n" @?= ["<number 10 Just StyleTcy>"]
        errs "[number-text 1.5]\n" @?= ["G0219"]
        errs "[number-text 1 style=roman]\n" @?= ["G0219"],
      testCase "references and citations" $ do
        paraOf "[ref-number intro][cite knuth1981]\n" @?= ["<ref RefNumber intro>", "Cite (SrcSpan {spanFile = FileId 1, spanStart = 18, spanEnd = 34}) \"knuth1981\""]
        errs "[cite nope]\n" @?= ["G0221"],
      testCase "styles and swatches must exist" $ do
        errs "[color accent: x][style term: y]\n" @?= []
        errs "[color red: x]\n" @?= ["G0217"]
        errs "[style nope: x]\n" @?= ["G0218"],
      testCase "index requires a reading" $ do
        errs "[index reading=くみはん: 組版]\n" @?= []
        errs "[index: 組版]\n" @?= ["G0220"]
        errs "[index reading=あ/い/う: a/b/c]\n" @?= ["G0242"],
      testCase "unknown commands" $ do
        errs "[nope: x]\n" @?= ["G0222"]
        errs "@nope\n" @?= ["G0209"],
      testCase "attributes attach to the next block" $
        case body "@label intro\n@nonumber\n@toc-title 短い\n# はじめに\n" of
          [Heading 1 (HeadingAttrs (Just t) Nothing True False) _] -> stripSpans t @?= ["短い"]
          other -> assertFailure (show other),
      testCase "attribute errors" $ do
        errs "@label a\n@label b\n# x\n" @?= ["G0212"]
        errs "@label a\n" @?= ["G0210"]
        errs "@nonumber\n本文。\n" @?= ["G0213"]
        errs "@label a\n@set x = 1\n# x\n" @?= ["G0211"],
      testCase "figures" $ do
        errs "@figure images/a.png alt=\"x\"\n  キャプション。\n" @?= []
        errs "@figure images/a.png\n" @?= ["G0228"]
        errs "@figure images/a.pdf alt=x\n" @?= ["G0229"]
        errs "@figure images/none.png alt=x\n" @?= ["G0233"]
        errs "@figure images/a.png alt=x wrap=end\n" @?= ["G0231"],
      testCase "csv tables and listings" $ do
        case body "@table src=data.csv\n" of
          [Table _ h [r]] -> (map stripSpans h, map stripSpans r) @?= ([["a"], ["b"]], [["1"], ["x,y"]])
          other -> assertFailure (show other)
        body "@listing src/Main.hs lines=2-3\n" @?= [CodeBlock Nothing "l2\nl3"]
        errs "@listing src/Main.hs lines=3-9\n" @?= ["G0237"],
      testCase "proofreading comments: kept in dev, warned and dropped in prod" $ do
        errs "本文%%= メモ %%\n" @?= []
        snd (run ctx {ctxProfile = Prod} "本文%%= メモ %%\n") @?= ["G0205"],
      testCase "a plugin may override a built-in command when declared" $ do
        let hook =
              noPlugins
                { phCommands = Set.fromList ["strong"],
                  phOverrides = Set.fromList ["strong"],
                  phCallCommand = \_ _ _ sp -> Right ([Text sp "PLUGIN"], [])
                }
        fst (run ctx {ctxPlugins = hook} "[strong: x]\n") @?= [Paragraph [Text (mkSpan (FileId 1) 0 11) "PLUGIN"]]
    ]
