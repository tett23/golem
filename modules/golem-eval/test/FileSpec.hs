module FileSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Parser (parseAst)
import Golem.Project.Style (LineBreaks (..))
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
      ctxCharStyles = Set.fromList ["term", "strong", "bold", "italic"],
      ctxParaStyles = Map.fromList [("body", JoinLines), ("verse", KeepLines), ("caption", JoinLines), ("sidenote", JoinLines), ("quote", JoinLines)],
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
      CharStyle _ n xs -> ("<" <> n <> ">") : stripSpans xs
      LineBreak _ -> ["<br>"]
      Note _ n xs -> ("<note " <> tshow n <> ">") : stripSpans xs
      Ruby _ _ segs -> ["<ruby " <> tshow (length segs) <> ">"]
      Number _ n st -> ["<number " <> tshow n <> " " <> tshow st <> ">"]
      Ref _ k l -> ["<ref " <> tshow k <> " " <> l <> ">"]
      Deferred _ _ -> ["<deferred>"]
      other -> [tshow other]
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show

-- | The paragraphs of a verse: each a list of lines (split at line breaks).
verseOf :: Text -> [[[Text]]]
verseOf src = map stanza (body src)
  where
    stanza = \case
      Paragraph (Just "verse") is -> map stripSpans (splitBreaks is)
      other -> error (show other)
    splitBreaks is = case break isBreak is of
      (l, []) -> [l]
      (l, _ : rest) -> l : splitBreaks rest
    isBreak = \case
      LineBreak _ -> True
      _ -> False

paraOf :: Text -> [Text]
paraOf src = case body src of
  [Paragraph Nothing is] -> stripSpans is
  other -> error (show other)

tests :: TestTree
tests =
  testGroup
    "file evaluation, S0 (ADR 0002)"
    [ verseTests,
      styleTests,
      testCase "variables, expressions and meta" $
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
        fst (run ctx {ctxPlugins = hook} "[strong: x]\n") @?= [Paragraph Nothing [Text (mkSpan (FileId 1) 0 11) "PLUGIN"]]
    ]

verseTests :: TestTree
verseTests =
  testGroup
    "verse and newlines in paragraphs (docs/adr ADR 0003, 0005)"
    [ testCase "newlines in a paragraph produce nothing" $
        body "吾輩は猫である。\n名前はまだ無い。\n" @?= [Paragraph Nothing [Text (mkSpan (FileId 1) 0 49) "吾輩は猫である。名前はまだ無い。"]],
      testCase "newlines are dropped before the tcy check" $
        errs "[tcy: 1\n2]\n" @?= [],
      testCase "lines and stanzas" $
        verseOf "@style verse\n  A\n  B\n\n  C\n" @?= [[["A"], ["B"]], [["C"]]],
      testCase "whitespace at the start of a line is ignored, the ideographic space is not" $ do
        verseOf "@style verse\n  A\n    B\n" @?= [[["A"], ["B"]]]
        verseOf "@style verse\n  A\n  \x3000B\n" @?= [[["A"], ["\x3000B"]]],
      testCase "newlines inside a command produce nothing" $
        verseOf "@style verse\n  [italic: a\n  b] c\n" @?= [[["<italic>", "ab", " c"]]],
      testCase "lines of only comments are dropped" $
        verseOf "@style verse\n  A %% x %%\n  %% y %%\n  B\n" @?= [[["A"], ["B"]]],
      testCase "notes in verse are numbered with the paragraphs around it" $ do
        let notes = [n | b <- body "a[note: 一]\n\n@style verse\n  b[note: 二]\n  c\n\nd[note: 三]\n", n <- noteNumbers b]
        notes @?= [1, 2, 3]
    ]
  where
    noteNumbers = \case
      Paragraph _ is -> [n | Note _ n _ <- is]
      _ -> []

-- | Character and paragraph styles (docs/adr ADR 0005).
styleTests :: TestTree
styleTests =
  testGroup
    "character and paragraph styles (docs/adr ADR 0005)"
    [ testCase "emphasis is a built-in character style" $ do
        let strong = [Paragraph Nothing [CharStyle (mkSpan (FileId 1) 0 11) "strong" [Text (mkSpan (FileId 1) 9 10) "a"]]]
        body "[strong: a]\n" @?= strong
        paraOf "[style strong: a]\n" @?= ["<strong>", "a"]
        paraOf "[bold: a]\n" @?= ["<bold>", "a"]
        paraOf "[style bold: a]\n" @?= ["<bold>", "a"]
        paraOf "[italic: a]\n" @?= ["<italic>", "a"]
        paraOf "[style italic: a]\n" @?= ["<italic>", "a"],
      testCase "the body form" $
        map stripped (body "@style verse\n  A\n  B\n\n  C\n") @?= [(Just "verse", ["A", "<br>", "B"]), (Just "verse", ["C"])],
      testCase "the attribute form" $
        map stripped (body "@style verse\nA\nB\n") @?= [(Just "verse", ["A", "<br>", "B"])],
      testCase "a join style joins the lines" $
        map stripped (body "@style quote\nab\ncd\n") @?= [(Just "quote", ["abcd"])],
      testCase "body is no style" $
        map stripped (body "@style body\nx\n") @?= [(Nothing, ["x"])],
      testCase "errors" $ do
        errs "@style nope\nx\n" @?= ["G0247"]
        map stripped (body "@style nope\nx\n") @?= [(Nothing, ["x"])]
        errs "@style\n  x\n" @?= ["G0247"]
        errs "@verse\n  A\n" @?= ["G0248"]
        errs "@style verse\n  - a\n" @?= ["G0245"]
        errs "@style verse\n  %% c %%\n" @?= ["G0246"]
        errs "@style verse\n" @?= ["G0210"],
      testCase "a style on a block that is not a paragraph" $ do
        errs "@style quote\n# 見出し\n" @?= ["G0213"]
        case body "@style quote\n# 見出し\n" of
          [Heading 1 _ _] -> pure ()
          other -> assertFailure (show other),
      testCase "a block command after attributes is their target" $ do
        errs "@label song\n@style verse\n  A\n" @?= []
        labels "@label song\n@style verse\n  A\n\n  B\n" @?= [Just "song", Nothing]
        errs "@label fig\n@figure images/a.png alt=x\n  キャプション。\n" @?= []
        case blocksOf "@label fig\n@figure images/a.png alt=x\n  キャプション。\n" of
          [Block _ (Just "fig") (FigureBlock _)] -> pure ()
          other -> assertFailure (show other)
        errs "@label a\n@set x = 1\n@figure images/a.png alt=x\n" @?= ["G0211"],
      testCase "a style inside a caption" $
        errs "@figure images/a.png alt=x\n  @style quote\n  キャプション。\n" @?= ["G0213"],
      testCase "a filter must not invent paragraph styles" $ do
        let hook = noPlugins {phApplyFilters = \_ (Document f bs) -> Right (Document f (bs <> [Block (mkSpan f 0 1) Nothing (Paragraph (Just "nope") [])]), [])}
        snd (run ctx {ctxPlugins = hook} "x\n") @?= ["G0247"]
    ]
  where
    stripped = \case
      Paragraph st is -> (st, stripSpans is)
      other -> error (show other)
    blocksOf src =
      let (file, _, _) = parseAst (FileId 1) src
       in docBlocks (erDocument (evalFile ctx file))
    labels = map blockLabel . blocksOf
