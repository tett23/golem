module FileSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Doc.Validate (validateDocument)
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Parser (parseAst)
import Golem.Parser.SourceSettings
import Golem.Project.Style (LineBreaks (..), LocalStyles (..), Style (..), defaultStyle, paraLineBreaks, parseStyle)
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
      ctxPlugins = noPlugins,
      ctxSource = defaultSourceSettings,
      ctxStyle = defaultStyle
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
      settingsTests,
      styleTests,
      separatorTests,
      hardBreakTests,
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
        errs "@verse\n  A\n" @?= ["G0209"]
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

-- | The style.toml of the tests of the file settings: a swatch and quote.
settingsStyle :: Style
settingsStyle =
  either (error . show) id (parseStyle (FileId 9) "[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n\n[paragraph-styles.quote]\nindent = \"1zw\"\n")

-- | A context whose styles are those of 'settingsStyle'.
sctx :: EvalContext
sctx =
  ctx
    { ctxStyle = settingsStyle,
      ctxCharStyles = Map.keysSet (stCharStyles settingsStyle),
      ctxParaStyles = paraLineBreaks settingsStyle
    }

runS :: EvalContext -> Text -> ([BlockBody], [Diagnostic], EvalResult)
runS c src =
  let (file, _, pds) = parseAst (FileId 1) src
      r = evalFile c file
   in (map blockBody (docBlocks (erDocument r)), pds <> erDiagnostics r, r)

codesS :: Text -> [Text]
codesS src = let (_, ds, _) = runS sctx src in [x | d <- ds, let DiagnosticCode x = diagCode d]

-- | The file settings: @manifest and @style-def (docs/adr ADR 0014).
settingsTests :: TestTree
settingsTests =
  testGroup
    "file settings (docs/adr ADR 0014)"
    [ testCase "@style-def paragraph defines a style for the file" $ do
        let (bs, ds, r) = runS sctx "@style-def paragraph letter line-breaks=keep\n\n@style letter\na\nb\n"
        map stripped bs @?= [(Just "letter", ["a", "<br>", "b"])]
        ds @?= []
        assertBool "erStyles" (Map.member "letter" (lsParaStyles (erStyles r))),
      testCase "a local style inherits through based-on" $ do
        let (bs, ds, _) = runS sctx "@style-def paragraph letter based-on=verse\n\n@style letter\na\nb\n"
        map stripped bs @?= [(Just "letter", ["a", "<br>", "b"])]
        ds @?= [],
      testCase "@style-def character defines a character style for the file" $ do
        let (bs, ds, _) = runS sctx "@style-def character term color=accent\n\n[style term: x]\n"
        map stripped bs @?= [(Nothing, ["<term>", "x"])]
        ds @?= []
        let (_, ds', _) = runS sctx "[style term: x]\n"
        map (\d -> let DiagnosticCode c = diagCode d in c) ds' @?= ["G0218"]
        assertBool "message" (all (T.isInfixOf "定義されていない" . diagMessage) ds'),
      testCase "the file settings may run into the next block without a blank line" $ do
        let (bs, ds, _) = runS sctx "@style-def paragraph letter\n@style letter\na\n"
        map stripped bs @?= [(Just "letter", ["a"])]
        ds @?= []
        let (bs', ds', _) = runS sctx "%% 設定 %%\n@style-def paragraph letter\n@label p\na\n"
        map stripped bs' @?= [(Nothing, ["a"])]
        ds' @?= [],
      testCase "character and paragraph styles are separate name spaces" $
        codesS "@style-def character note\n@style-def paragraph note\n\nx\n" @?= [],
      testCase "a name defined twice in a file is G0253" $ do
        codesS "@style-def paragraph a\n@style-def paragraph a\n" @?= ["G0253"]
        codesS "@style-def paragraph quote\n@style-def paragraph quote indent=1zw\n" @?= ["G0253"],
      testCase "a style of style.toml or a built-in style may be overridden" $ do
        let ok src name = do
              let (_, ds, r) = runS sctx src
              ds @?= []
              assertBool (T.unpack name) (Map.member name (lsParaStyles (erStyles r)) || Map.member name (lsCharStyles (erStyles r)))
        ok "@style-def paragraph body indent=1zw\n\nx\n" "body"
        ok "@style-def character strong synthetic-italic=true\n\n[strong: x]\n" "strong"
        ok "@style-def paragraph quote indent=1zw\n\n@style quote\nx\n" "quote",
      testCase "an override of verse changes how its newlines are read" $ do
        let (bs, _, _) = runS sctx "@style-def paragraph verse line-breaks=join\n\n@style verse\na\nb\n"
        map stripped bs @?= [(Just "verse", ["ab"])]
        let (bs', _, _) = runS sctx "@style verse\na\nb\n"
        map stripped bs' @?= [(Just "verse", ["a", "<br>", "b"])],
      testCase "the arguments of @style-def and @manifest are G0252" $ do
        mapM_
          (\src -> (src, codesS src) @?= (src, ["G0252"]))
          [ "@style-def\n",
            "@style-def table a\n",
            "@style-def paragraph\n",
            "@style-def paragraph a b\n",
            "@style-def paragraph a font=[= \"x\"]\n",
            "@style-def paragraph a indent=1zw indent=2zw\n",
            "@style-def paragraph a\n  x\n",
            "@manifest line\n",
            "@manifest\n",
            "@manifest title=x title=x\n",
            "@manifest title=[= \"x\"]\n",
            "@manifest title=x\n  a\n"
          ],
      testCase "@manifest overrides only the keys of [source] (G0250)" $ do
        codesS "@manifest title=x\n" @?= ["G0250"]
        codesS "@manifest paragraph-separater=line\n" @?= ["G0250"]
        let (bs, ds, _) = runS sctx "@manifest title=x\n@label p\na\n"
        map (\d -> let DiagnosticCode c = diagCode d in c) ds @?= ["G0250"]
        map stripped bs @?= [(Nothing, ["a"])],
      testCase "regular expression styles are not implemented yet (G0254)" $
        codesS "@style-def regex body pattern=\"[0-9]+\" style=strong\n" @?= ["G0254"],
      testCase "an invalid definition is reported at its @style-def and dropped" $ do
        let at src = let (_, ds, _) = runS sctx src in [(x, spanStart (diagSpan d)) | d <- ds, let DiagnosticCode x = diagCode d]
        at "@style-def paragraph Letter\n" @?= [("G0306", 0)]
        at "@style-def paragraph a line-breaks=x\n" @?= [("G0306", 0)]
        at "@style-def paragraph a based-on=nope\n" @?= [("G0313", 0)]
        codesS "@style-def paragraph a based-on=nope\n\n@style a\nx\n" @?= ["G0313", "G0247"],
      testCase "@manifest and @style-def elsewhere are G0249" $ do
        codesS "a\n\n@style-def paragraph letter\n" @?= ["G0249"]
        codesS "@label x\n@style-def paragraph letter\na\n" @?= ["G0249"]
        codesS "a\n\n@manifest paragraph-separator=line\n" @?= ["G0249"],
      testCase "@manifest overrides how the file is read" $ do
        let paras c src = let (bs, _, _) = runS c src in map stripped bs
            lineS = sctx {ctxSource = SourceSettings LineSeparated}
            (_, ds, r) = runS sctx "@manifest paragraph-separator=line\n\na\nb\n"
        paras sctx "@manifest paragraph-separator=line\n\na\nb\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])]
        ds @?= []
        erSource r @?= SourceSettings LineSeparated
        paras sctx "@manifest paragraph-separator=\"line\"\na\nb\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])]
        codesS "@manifest paragraph-separator=\"line\"\na\nb\n" @?= []
        paras sctx "%% 設定 %%\n@manifest paragraph-separator=line\n\na\nb\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])]
        let (file, _, _) = parseAst (FileId 1) "@manifest paragraph-separator=line\n@label p\na\nb\n"
        map blockLabel (docBlocks (erDocument (evalFile sctx file))) @?= [Just "p", Nothing]
        paras lineS "@manifest paragraph-separator=blank-line\n\na\nb\n" @?= [(Nothing, ["ab"])],
      testCase "@manifest elsewhere does not apply" $ do
        let (_, ds, r) = runS sctx "a\n\n@manifest paragraph-separator=line\n"
        map (\d -> let DiagnosticCode c = diagCode d in c) ds @?= ["G0249"]
        erSource r @?= ctxSource sctx,
      testCase "the keys and values of @manifest (G0250, G0251, G0252)" $ do
        codesS "@manifest title=x\n" @?= ["G0250"]
        codesS "@manifest paragraph-separater=line\n" @?= ["G0250"]
        codesS "@manifest paragraph-separator=lines\n" @?= ["G0251"]
        mapM_
          (\src -> (src, codesS src) @?= (src, ["G0252"]))
          [ "@manifest paragraph-separator=line paragraph-separator=line\n",
            "@manifest paragraph-separator=[= \"line\"]\n",
            "@manifest paragraph-separator=line\n  a\n"
          ]
        let (bs, ds, _) = runS sctx "@manifest title=x paragraph-separator=line\n\na\nb\n"
        map (\d -> let DiagnosticCode c = diagCode d in c) ds @?= ["G0250"]
        map stripped bs @?= [(Nothing, ["a"]), (Nothing, ["b"])],
      testCase "@manifest and @style-def together, without a blank line" $ do
        let (bs, ds, _) = runS sctx "@manifest paragraph-separator=line\n@style-def paragraph letter\n@style letter\na\nb\n"
        map stripped bs @?= [(Just "letter", ["a"]), (Nothing, ["b"])]
        ds @?= [],
      testCase "a filter may give the paragraph styles of the file" $ do
        let hook = noPlugins {phApplyFilters = \_ (Document f bs) -> Right (Document f (bs <> [Block (mkSpan f 0 1) Nothing (Paragraph (Just "letter") [])]), [])}
        codesS "x\n" @?= []
        let (_, ds, _) = runS sctx {ctxPlugins = hook} "@style-def paragraph letter\n\nx\n"
        ds @?= []
        let (_, ds', _) = runS sctx {ctxPlugins = hook} "x\n"
        map (\d -> let DiagnosticCode c = diagCode d in c) ds' @?= ["G0247"]
    ]
  where
    stripped = \case
      Paragraph st is -> (st, stripSpans is)
      other -> error (show other)

-- ------------------------------------------------------------------ paragraph separator

-- | The context of the line style (docs/adr ADR 0013).
lineCtx :: EvalContext
lineCtx = ctx {ctxSource = SourceSettings LineSeparated}

-- | The blocks of a source in a context.
blocksIn :: EvalContext -> Text -> [Block]
blocksIn c src = let (file, _, _) = parseAst (FileId 1) src in docBlocks (erDocument (evalFile c file))

-- | Each block as its paragraph style and text, or its constructor.
shapes :: EvalContext -> Text -> [(Maybe Text, [Text])]
shapes c = map (shapeOf . blockBody) . blocksIn c

shapeOf :: BlockBody -> (Maybe Text, [Text])
shapeOf = \case
  Paragraph st is -> (st, stripSpans is)
  Heading _ _ is -> (Just "#", stripSpans is)
  other -> (Just "?", [T.pack (show other)])

separatorTests :: TestTree
separatorTests =
  testGroup
    "paragraph separator (docs/adr ADR 0013)"
    [ testCase "one newline separates paragraphs in the line style only" $ do
        shapes lineCtx "a\nb\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])]
        shapes ctx "a\nb\n" @?= [(Nothing, ["ab"])],
      testCase "blank lines separate paragraphs in both styles" $ do
        shapes lineCtx "a\n\n\nb\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])]
        shapes ctx "a\n\n\nb\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])],
      testCase "spaces and tabs at the start of a line go; the ideographic space stays" $ do
        shapes lineCtx "a\n  b\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])]
        shapes lineCtx "a\n\tb\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])]
        shapes lineCtx "a\n\x3000b\n" @?= [(Nothing, ["a"]), (Nothing, ["\x3000b"])],
      testCase "a line of comments makes no paragraph; a comment across lines does not separate" $ do
        shapes lineCtx "a\n%% c %%\nb\n" @?= [(Nothing, ["a"]), (Nothing, ["b"])]
        length (shapes lineCtx "a %% x\ny %% b\n") @?= 1,
      testCase "a proofreading comment alone on a line stays a paragraph" $
        length (shapes lineCtx "a\n%%= c %%\nb\n") @?= 3,
      testCase "newlines in a prose slot neither separate nor make characters" $
        shapes lineCtx "[note: x\ny] z\nw\n" @?= [(Nothing, ["<note 1>", "xy", " z"]), (Nothing, ["w"])],
      testCase "an attribute goes to the first line only" $ do
        let bs = blocksIn lineCtx "@label p\na\nb\n"
        map blockLabel bs @?= [Just "p", Nothing]
        map (shapeOf . blockBody) bs @?= [(Nothing, ["a"]), (Nothing, ["b"])],
      testCase "a keep style keeps its lines; its stanzas are separated by blank lines" $ do
        shapes lineCtx "@style verse\na\nb\n" @?= [(Just "verse", ["a", "<br>", "b"])]
        shapes lineCtx "@style verse\n  a\n  b\n\n  c\n" @?= [(Just "verse", ["a", "<br>", "b"]), (Just "verse", ["c"])],
      testCase "the body of a join style is split" $
        shapes lineCtx "@style quote\n  a\n  b\n" @?= [(Just "quote", ["a"]), (Just "quote", ["b"])],
      testCase "the continuation line of a list item is the next paragraph of the item" $
        case map blockBody (blocksIn lineCtx "- a\n  b\n") of
          [BulletList [ListItem Nothing bs]] -> map (shapeOf . blockBody) bs @?= [(Nothing, ["a"]), (Nothing, ["b"])]
          other -> assertFailure (show other),
      testCase "a block starts at the start of a line in both styles" $ do
        shapes lineCtx "a\n# h\nb\n" @?= [(Nothing, ["a"]), (Just "#", ["h"]), (Nothing, ["b"])]
        shapes ctx "a\n# h\nb\n" @?= [(Nothing, ["a"]), (Just "#", ["h"]), (Nothing, ["b"])],
      testCase "a caption of a figure is split" $
        case map blockBody (blocksIn lineCtx "@figure images/a.png alt=a\n  c1\n  c2\n") of
          [FigureBlock f] -> map (shapeOf . blockBody) (figCaption f) @?= [(Nothing, ["c1"]), (Nothing, ["c2"])]
          other -> assertFailure (show other),
      testCase "erSource is the settings of the context" $ do
        let (file, _, _) = parseAst (FileId 1) "a\n"
        erSource (evalFile lineCtx file) @?= SourceSettings LineSeparated
        erSource (evalFile ctx file) @?= defaultSourceSettings
    ]

-- ------------------------------------------------------------------ hard breaks

-- | Hard line breaks (docs/adr ADR 0016), in both paragraph separators.
hardBreakTests :: TestTree
hardBreakTests =
  testGroup
    "hard line breaks (docs/adr ADR 0016)"
    [ testCase "a backslash at the end of a line breaks the line" $
        mapM_ (\c -> shapes c "a\\\nb\n" @?= [(Nothing, ["a", "<br>", "b"])]) [ctx, lineCtx],
      testCase "the line style makes the two lines one paragraph" $
        shapes lineCtx "a\\\nb\nc\n" @?= [(Nothing, ["a", "<br>", "b"]), (Nothing, ["c"])],
      testCase "the blank-line style joins the next newline" $
        shapes ctx "a\\\nb\nc\n" @?= [(Nothing, ["a", "<br>", "bc"])],
      testCase "a keep style has one break per line" $
        mapM_ (\c -> shapes c "@style verse\n  a\\\n  b\n" @?= [(Just "verse", ["a", "<br>", "b"])]) [ctx, lineCtx],
      testCase "a join style breaks the line" $
        mapM_ (\c -> shapes c "@style quote\na\\\nb\n" @?= [(Just "quote", ["a", "<br>", "b"])]) [ctx, lineCtx],
      testCase "an item of a list" $
        mapM_
          ( \c -> case map blockBody (blocksIn c "- a\\\n  b\n") of
              [BulletList [ListItem Nothing bs]] -> map (shapeOf . blockBody) bs @?= [(Nothing, ["a", "<br>", "b"])]
              other -> assertFailure (show other)
          )
          [ctx, lineCtx],
      testCase "a caption of a figure" $
        mapM_
          ( \c -> case map blockBody (blocksIn c "@figure images/a.png alt=a\n  c1\\\n  c2\n") of
              [FigureBlock f] -> map (shapeOf . blockBody) (figCaption f) @?= [(Nothing, ["c1", "<br>", "c2"])]
              other -> assertFailure (show other)
          )
          [ctx, lineCtx],
      testCase "a hard break in a prose slot is G0256" $ do
        errs "[note: a\\\nb] c\n" @?= ["G0256"]
        paraOf "[note: a\\\nb] c\n" @?= ["<note 1>", "ab", " c"],
      testCase "an empty line is G0257 and the paragraph is valid" $
        mapM_
          ( \c ->
              mapM_
                ( \src -> do
                    let (bs, es) = run c src
                    assertEqual (show src) ["G0257"] es
                    validateDocument (const (Just 1000)) [] (Document (FileId 1) [Block (mkSpan (FileId 1) 0 1) Nothing b | b <- bs]) @?= []
                )
                ["\\\na\n", "a\\\n\\\nb\n", "a\\\n%% c %%\nb\n"]
          )
          [ctx, lineCtx],
      testCase "erSource of the line style stays" $ do
        let (file, _, _) = parseAst (FileId 1) "a\\\nb\n"
        erSource (evalFile lineCtx file) @?= SourceSettings LineSeparated
    ]
