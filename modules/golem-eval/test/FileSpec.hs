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
import Golem.Project.Paths (PathError (..))
import Golem.Project.Style (LineBreaks (..), LocalStyles (..), RegexStyleDef (..), Style (..), defaultStyle, dimToSp, paraLineBreaks, parseDim, parseStyle)
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
          [ ("images/a.png", AssetPresent),
            ("images/a.pdf", AssetPresent),
            ("data.csv", AssetText "a,b\n1,\"x,y\"\n"),
            ("src/Main.hs", AssetText "l1\nl2\nl3\n"),
            ("empty.csv", AssetText ""),
            ("blank.csv", AssetText "\n\n"),
            ("ragged.csv", AssetText "a,b\n1\n"),
            ("/tmp/a.png", AssetInvalid Absolute),
            ("https://example.com/a.png", AssetInvalid Url),
            ("../outside.txt", AssetInvalid EscapesRoot),
            ("gone.txt", AssetInvalid Missing)
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

-- | The code, message, start and end of each diagnostic (golem-eval ADR 0003).
diags :: Text -> [(Text, Text, Int, Int)]
diags = diagsWith ctx

diagsWith :: EvalContext -> Text -> [(Text, Text, Int, Int)]
diagsWith c src =
  let (file, _, pds) = parseAst (FileId 1) src
   in [(code, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- pds <> erDiagnostics (evalFile c file), let DiagnosticCode code = diagCode d]

-- | The code and message of each diagnostic.
msgs :: Text -> [(Text, Text)]
msgs src = [(c, m) | (c, m, _, _) <- diags src]

paraInlines :: BlockBody -> Maybe [Inline]
paraInlines = \case
  Paragraph _ is -> Just is
  _ -> Nothing

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

-- | The rubies of a paragraph: the base and the reading of each segment.
rubiesOf :: Text -> [[([Text], Maybe Text)]]
rubiesOf src = case body src of
  [Paragraph Nothing is] -> [[(baseText b, r) | RubySegment b r <- segs] | Ruby _ _ segs <- is]
  other -> error (show other)
  where
    baseText :: [InlineNoRuby] -> [Text]
    baseText = concatMap $ \case
      Text _ t -> [t]
      CharStyle _ n xs -> ("<" <> n <> ">") : baseText xs
      other -> [T.pack (show other)]

-- | The index entries of a paragraph.
indexOf :: Text -> [IndexEntry]
indexOf src = case body src of
  [Paragraph Nothing is] -> [e | IndexMark _ e <- is]
  other -> error (show other)

-- | Escaped characters (golem-parser ADR 0010).
escapeTests :: TestTree
escapeTests =
  testGroup
    "escaped characters (golem-parser ADR 0010)"
    [ testCase "\\/ in the base of a ruby is no separator" $ do
        rubiesOf "[ruby: a\\/b|えー]\n" @?= [[(["a/b"], Just "えー")]]
        errs "[ruby: a\\/b|えー]\n" @?= [],
      testCase "\\/ in the reading is a / of the reading" $
        rubiesOf "[ruby: 漢字|かん\\/じ]\n" @?= [[(["漢字"], Just "かん/じ")]],
      testCase "the reading of one segment against a base of two is G0215" $
        errs "[ruby: 漢/字|かん\\/じ]\n" @?= ["G0215"],
      testCase "the separators written in the source are as before" $ do
        errs "[ruby: 東京|とう/きょう]\n" @?= ["G0215"]
        rubiesOf "[ruby: 漢/字|かん/]\n" @?= [[(["漢"], Just "かん"), (["字"], Nothing)]]
        rubiesOf "[ruby: [bold: 漢/字]|かんじ]\n" @?= [[(["<bold>", "漢/字"], Just "かんじ")]],
      testCase "a / in the value of an expression is no separator" $ do
        rubiesOf "[ruby: [= \"a/b\"]|えー]\n" @?= [[(["a/b"], Just "えー")]]
        errs "[ruby: [= \"a/b\"]|えー]\n" @?= [],
      testCase "\\/ in the term of an index is no separator" $ do
        indexOf "[index reading=えー: a\\/b]\n" @?= [IndexEntry ["a/b"] ["えー"]]
        errs "[index reading=えー: a\\/b]\n" @?= []
        indexOf "[index reading=くみはん/わぶん: 組版/和文]\n" @?= [IndexEntry ["組版", "和文"] ["くみはん", "わぶん"]],
      testCase "the IR of escaped text is as before: one text, one span" $
        case body "a\\[b\\\\c\n" of
          [Paragraph Nothing [Text sp t]] -> (t, spanStart sp, spanEnd sp) @?= ("a[b\\c", 0, 7)
          other -> assertFailure (show other)
    ]

tests :: TestTree
tests =
  testGroup
    "file evaluation, S0 (ADR 0002)"
    [ verseTests,
      diagnosticTests,
      settingsTests,
      noticeTests,
      styleTests,
      separatorTests,
      hardBreakTests,
      breakTests,
      escapeTests,
      testCase "variables, expressions and meta" $
        paraOf "@set x = 2\n\n[= x * 3] と [= meta.title]\n" @?= ["6 と 本の題"],
      testCase "redefinition and use before definition are errors" $ do
        errs "@set x = 1\n\n@set x = 2\n" @?= ["G0224"]
        errs "[= y]\n\n@set y = 1\n" @?= ["G0202"],
      testCase "imports bind a namespace" $
        paraOf "@import common/values.gm as v\n\n[= v.price + 1]\n" @?= ["101"],
      testCase "an expression as the path of @import is G0309 (golem-project ADR 0006)" $ do
        errs "@import [= 1] as x\n" @?= ["G0309"]
        errs "@import \"common/values.gm\" as v\n" @?= [],
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
        -- no G0240; the digits make the notice G0263 (golem-syntax ADR 0002)
        errs "[tcy: 1\n2]\n" @?= ["G0263"],
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
      testCase "[code: ...] is [style code: ...] (golem-driver ADR 0017)" $ do
        let c = ctx {ctxCharStyles = Set.insert "code" (ctxCharStyles ctx)}
        fst (run c "[code: manifest.toml]\n") @?= [Paragraph Nothing [CharStyle (mkSpan (FileId 1) 0 21) "code" [Text (mkSpan (FileId 1) 7 20) "manifest.toml"]]]
        map (fmap stripSpans . paraInlines) (fst (run c "[code: manifest.toml]\n")) @?= map (fmap stripSpans . paraInlines) (fst (run c "[style code: manifest.toml]\n")),
      testCase "@style code is G0266 (golem-driver ADR 0017)" $ do
        let c = ctx {ctxParaStyles = Map.insert "code" JoinLines (ctxParaStyles ctx)}
        snd (run c "@style code\nx\n") @?= ["G0266"]
        snd (run c "@style code\n  x\n") @?= ["G0266"]
        [m | (code', m, _, _) <- diagsWith c "@style code\nx\n", code' == "G0266"] @?= ["code はコードブロックの段落スタイルです。コードは ``` か @listing で書きます"],
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

-- | The notices of the evaluation (golem-syntax ADR 0002).
noticeTests :: TestTree
noticeTests =
  testGroup
    "notices (golem-syntax ADR 0002)"
    [ testCase "G0262: a @style-def over a style of style.toml or a built-in one" $ do
        let at src = [(c, m, s) | (c, m, s, _) <- diagsWith sctx src, c == "G0262"]
        at "@style-def paragraph body indent=1zw\n\nx\n" @?= [("G0262", "ファイルの中の定義が段落スタイルの body を上書きしています", 0)]
        at "@style-def paragraph letter based-on=body\n\nx\n" @?= []
        let headingStyle = either (error . show) id (parseStyle (FileId 9) "[fonts.heading]\nja = \"fonts/h.otf\"\n")
            hctx = ctx {ctxStyle = headingStyle, ctxCharStyles = Map.keysSet (stCharStyles headingStyle), ctxParaStyles = paraLineBreaks headingStyle}
        [c | (c, _, _, _) <- diagsWith hctx "@style-def character bold font=heading\n\n[bold: x]\n"] @?= ["G0262"]
        at "@style-def paragraph letter indent=1zw\n@style-def paragraph quote indent=2zw\n\nx\n" @?= [("G0262", "ファイルの中の定義が段落スタイルの quote を上書きしています", 39)],
      testCase "G0262 is a notice" $ do
        let (_, ds, _) = runS sctx "@style-def paragraph body indent=1zw\n\nx\n"
        map diagSeverity ds @?= [Notice],
      testCase "G0263: [tcy: ...] of ASCII digits only" $ do
        [(c, m, s, e) | (c, m, s, e) <- diags "a[tcy: 10]b\n", c == "G0263"] @?= [("G0263", "数の縦中横は [number-text 10 style=tcy] でも書けます", 1, 10)]
        errs "[tcy: !?]\n" @?= []
        errs "[tcy: 1a]\n" @?= []
        errs "[number-text 10 style=tcy]\n" @?= [],
      testCase "G0264: an escaped space at the start of a line of a paragraph that keeps its lines" $ do
        [(c, m, s) | (c, m, s, _) <- diags "@style verse\n  a\n  \\ x\n", c == "G0264"]
          @?= [("G0264", "行頭のエスケープした空白は無視されます。字下げには全角の空白を使います", 19)]
        errs "@style verse\n  \\ x\n" @?= ["G0264"]
        errs "@style quote\n  \\ x\n" @?= []
        errs "\\ x\n" @?= []
        errs "@style verse\n  a\\ b\n" @?= []
        -- the escaped space is dropped as before (golem-parser ADR 0010)
        verseOf "@style verse\n  a\n  \\ x\n" @?= [[["a"], ["x"]]],
      testCase "G0265: @listing src=, and the content is the same" $ do
        [(c, m, s, e) | (c, m, s, e) <- diags "@listing src=src/Main.hs\n", c == "G0265"]
          @?= [("G0265", "@listing の src= は廃止予定です。パスを最初の引数に書きます", 9, 24)]
        errs "@listing src/Main.hs\n" @?= []
        body "@listing src=src/Main.hs lines=2-3\n" @?= body "@listing src/Main.hs lines=2-3\n",
      testCase "the span of each @number by the span of its block" $ do
        let (file, _, _) = parseAst (FileId 1) "+ a\n@number 3\n+ b\n\n@number 2\n# h\n"
            r = evalFile ctx file
        Map.toList (erNumberSites r) @?= [(mkSpan (FileId 1) 14 18, mkSpan (FileId 1) 4 14), (mkSpan (FileId 1) 29 33, mkSpan (FileId 1) 19 29)]
    ]

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
        -- the first overrides quote of style.toml (golem-syntax ADR 0002)
        codesS "@style-def paragraph quote\n@style-def paragraph quote indent=1zw\n" @?= ["G0253", "G0262"],
      testCase "a style of style.toml or a built-in style may be overridden" $ do
        let ok src name = do
              let (_, ds, r) = runS sctx src
              -- G0262 tells the override (golem-syntax ADR 0002)
              map diagCode ds @?= [DiagnosticCode "G0262"]
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
      testCase "@style-def regex adds a regex style for the file (docs/adr ADR 0015)" $ do
        let (bs, ds, _) = runS sctx "@style-def regex body pattern=\"\\\\d+\" style=bold\n\na1\n"
        map stripped bs @?= [(Nothing, ["a", "<bold>", "1"])]
        ds @?= []
        let (bs', _, _) = runS sctx "a1\n"
        map stripped bs' @?= [(Nothing, ["a1"])],
      testCase "the errors of @style-def regex (docs/adr ADR 0015)" $ do
        codesS "@style-def regex nope pattern=x style=bold\n" @?= ["G0313"]
        codesS "@style-def regex body style=bold\n" @?= ["G0306"]
        codesS "@style-def regex body pattern=\"\\\\1\" style=bold\n" @?= ["G0315"]
        codesS "@style-def regex body\n" @?= ["G0306"]
        codesS "@style-def regex body pattern=x style=nope\n" @?= ["G0313"]
        codesS "@style-def regex body pattern=x style=bold colour=x\n" @?= ["G0306"]
        codesS "@style-def regex body pattern=x pattern=y style=bold\n" @?= ["G0252"],
      testCase "a wrong regex style is reported at its line and dropped, the others stay" $ do
        let src = "@style-def regex body pattern=a style=bold\n@style-def regex body pattern=\"\\\\1\" style=bold\n@style-def regex body pattern=b style=nope\n\nab\n"
            (bs, ds, r) = runS sctx src
        [(x, spanStart (diagSpan d)) | d <- ds, let { DiagnosticCode x = diagCode d }] @?= [("G0315", 43), ("G0313", 90)]
        Map.lookup "body" (lsRegexStyles (erStyles r)) @?= Just [RegexStyleDef "a" "bold"]
        map stripped bs @?= [(Nothing, ["<bold>", "a", "b"])],
      testCase "the regex styles of a file are added in the order written, not G0253" $ do
        let (bs, ds, r) = runS sctx "@style-def regex body pattern=\"[0-9]+\" style=bold\n@style-def regex body pattern=2 style=italic\n\n12\n"
        ds @?= []
        Map.lookup "body" (lsRegexStyles (erStyles r)) @?= Just [RegexStyleDef "[0-9]+" "bold", RegexStyleDef "2" "italic"]
        map stripped bs @?= [(Nothing, ["<bold>", "1", "<bold>", "<italic>", "2"])],
      testCase "a regex style may use a character style and a paragraph style of the file" $ do
        let (bs, ds, _) = runS sctx "@style-def character n synthetic-bold=true\n@style-def paragraph letter\n@style-def regex letter pattern=x style=n\n\n@style letter\naxb\n"
        ds @?= []
        map stripped bs @?= [(Just "letter", ["a", "<n>", "x", "b"])],
      testCase "a word of digits is read as the pattern" $ do
        let (bs, ds, _) = runS sctx "@style-def regex body pattern=12 style=bold\n\na12\n"
        ds @?= []
        map stripped bs @?= [(Nothing, ["a", "<bold>", "12"])],
      testCase "a regex style of style.toml applies" $ do
        let st = either (error . show) id (parseStyle (FileId 0) "[paragraph-styles.body]\nregex-styles = [{ pattern = '[0-9]+', style = \"bold\" }]\n")
            c = sctx {ctxStyle = st}
            (bs, ds, _) = runS c "第12章\n"
        ds @?= []
        map stripped bs @?= [(Nothing, ["第", "<bold>", "12", "章"])],
      testCase "the text a filter gives is matched too" $ do
        let hook = noPlugins {phApplyFilters = \_ (Document f bs0) -> Right (Document f (bs0 <> [Block (mkSpan f 0 1) Nothing (Paragraph Nothing [Text (mkSpan f 0 1) "x9"])]), [])}
            (bs, ds, _) = runS sctx {ctxPlugins = hook} "@style-def regex body pattern=\"[0-9]\" style=bold\n\na\n"
        ds @?= []
        map stripped bs @?= [(Nothing, ["a"]), (Nothing, ["x", "<bold>", "9"])],
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

-- | Forced page breaks (docs/adr ADR 0017).
breakTests :: TestTree
breakTests =
  testGroup
    "forced breaks (docs/adr ADR 0017)"
    [ testCase "each kind of break is a block" $ do
        run ctx "@page-break\n\na\n" @?= ([ForcedBreak BreakPage, Paragraph Nothing [Text (mkSpan (FileId 1) 13 14) "a"]], [])
        run ctx "@page-break recto\n" @?= ([ForcedBreak BreakRecto], [])
        run ctx "@page-break verso\n" @?= ([ForcedBreak BreakVerso], [])
        run ctx "@column-break\n" @?= ([ForcedBreak BreakColumn], []),
      testCase "a break right before a block goes before it, without G0211" $ do
        let (bs, es) = run ctx "@page-break recto\n# h\n"
        es @?= []
        map shape bs @?= ["break BreakRecto", "heading"],
      testCase "a label skips the break and goes to the block, wherever the break stands" $ do
        let check src = do
              let (bs, es) = blocksOf src
              es @?= []
              [(blockLabel b, shape (blockBody b)) | b <- bs] @?= [(Nothing, "break BreakPage"), (Just "x", "heading")]
        check "@page-break\n@label x\n# h\n"
        check "@label x\n@page-break\n# h\n",
      testCase "a label with only a break after it has no target" $
        errs "@label x\n@page-break\n\na\n" @?= ["G0210"],
      testCase "wrong arguments are G0258" $ do
        mapM_
          (\src -> assertEqual (T.unpack src) ["G0258"] (errs src))
          [ "@page-break page\n",
            "@page-break recto verso\n",
            "@page-break x=1\n",
            "@column-break recto\n",
            "@page-break\n  a\n"
          ],
      testCase "a break not at the top of the document is G0259 and dropped" $ do
        mapM_
          ( \src -> do
              let (bs, es) = blocksOf src
              assertEqual (T.unpack src) ["G0259"] es
              assertBool (T.unpack src) (not (any hasBreak bs))
          )
          [ "- a\n\n  @page-break\n",
            "= t\n  @page-break\n",
            "@figure images/a.png alt=a\n  @page-break\n"
          ]
        errs "@style quote\n  @page-break\n" @?= ["G0245"]
    ]
  where
    blocksOf src =
      let (file, _, pds) = parseAst (FileId 1) src
          r = evalFile ctx file
       in (docBlocks (erDocument r), [x | d <- pds <> erDiagnostics r, let DiagnosticCode x = diagCode d])
    shape :: BlockBody -> Text
    shape = \case
      ForcedBreak k -> "break " <> T.pack (show k)
      Heading {} -> "heading"
      Paragraph {} -> "paragraph"
      other -> T.pack (show other)
    hasBreak (Block _ _ b) = case b of
      ForcedBreak _ -> True
      BulletList items -> any (any hasBreak . itemBlocks) items
      OrderedList items -> any (any hasBreak . itemBlocks) items
      DefList gs -> any (any (any hasBreak) . dgDefs) gs
      FigureBlock f -> any hasBreak (figCaption f)
      _ -> False

-- | The codes, messages and positions of golem-eval ADR 0003.
diagnosticTests :: TestTree
diagnosticTests =
  testGroup
    "diagnostic codes (golem-eval ADR 0003)"
    [ testCase "G0223: a reserved word as a name" $ do
        diags "@set doc = 1\n" @?= [("G0223", "予約語は変数の名前に使えません: doc", 5, 8)]
        diags "@import common/values.gm as meta\n" @?= [("G0223", "予約語は名前空間に使えません: meta", 28, 32)],
      testCase "G0225: the depth of @toc" $ do
        mapM_ (\src -> (src, errs src) @?= (src, ["G0225"])) ["@toc depth=0\n", "@toc depth=4\n", "@toc depth=x\n"]
        msgs "@toc depth=0\n" @?= [("G0225", "@toc の depth は 1 から 3 の整数です")]
        errs "@toc\n" @?= []
        errs "@toc depth=3\n" @?= [],
      testCase "G0226: the names of labels" $ do
        let labelMsg = "@label にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます"
            refMsg = "参照にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます"
        msgs "@label Intro\n# x\n" @?= [("G0226", labelMsg)]
        msgs "@label a b\n# x\n" @?= [("G0226", labelMsg)]
        msgs "[ref-number Intro]\n" @?= [("G0226", refMsg)]
        msgs "[ref-number]\n" @?= [("G0226", refMsg)],
      testCase "G0227: @number" $ do
        errs "@number x\n# x\n" @?= ["G0227"]
        errs "@number 1 2\n# x\n" @?= ["G0227"]
        msgs "@number x\n# x\n" @?= [("G0227", "@number には整数を一つ書きます")]
        errs "@number 3\n+ a\n" @?= [],
      testCase "G0230, G0232, G0234" $ do
        msgs "@figure images/a.png alt=x wrap=left width=10mm\n" @?= [("G0230", "wrap は start か end です: left")]
        msgs "@figure alt=x\n" @?= [("G0232", "@figure には画像のパスを一つ書きます")]
        errs "@figure images/a.png images/b.png alt=x\n" @?= ["G0232"]
        msgs "@table data.csv\n" @?= [("G0234", "@table には src が必要です")],
      testCase "G0235: CSV that is not a table" $ do
        msgs "@table src=empty.csv\n" @?= [("G0235", "CSV が空です")]
        msgs "@table src=blank.csv\n" @?= [("G0235", "CSV が空です")]
        diags "@table src=ragged.csv\n" @?= [("G0235", "CSV の行ごとのセルの数が一致しません", 0, 22)],
      testCase "G0236: @listing without a path" $ do
        msgs "@listing\n" @?= [("G0236", "@listing にはファイルのパスが必要です")]
        -- src= is read, with the notice G0265 (golem-syntax ADR 0002)
        errs "@listing src=src/Main.hs\n" @?= ["G0265"],
      testCase "G0238: the number of prose slots" $ do
        msgs "[strong]\n" @?= [("G0238", "strong には散文スロットが一つ必要です")]
        msgs "[strong: a|b]\n" @?= [("G0238", "strong には散文スロットが一つ必要です")]
        msgs "[index reading=a]\n" @?= [("G0238", "index には散文スロットが一つ必要です")]
        msgs "[ruby: a]\n" @?= [("G0238", "ruby には散文スロットが二つ必要です")],
      testCase "[aki] puts a fixed space (docs/adr ADR 0019)" $ do
        let akiOf src = case body src of
              [Paragraph Nothing is] -> [(spanStart s, spanEnd s, a) | Aki s a <- is]
              other -> error (show other)
        akiOf "a[aki 五分]b\n" @?= [(1, 13, AkiZw (1 / 5))]
        akiOf "[aki 0.25zw][aki 12.5%][aki 全角]\n" @?= [(0, 12, AkiZw (1 / 4)), (12, 23, AkiZw (1 / 8)), (23, 35, AkiZw 1)]
        akiOf "3[aki 1mm]kg\n" @?= [(1, 10, AkiAbs (maybe 0 (dimToSp 0) (parseDim "1mm")))]
        akiOf "[aki \"2pt\"]\n" @?= [(0, 11, AkiAbs (2 * 65536))]
        errs "a[aki 五分]b\n" @?= [],
      testCase "G0255: [aki] needs one amount and no prose slot" $ do
        let g0255 src = do
              let ms = msgs src
              assertBool (show ms) (not (null ms) && all ((== "G0255") . fst) ms && all (("ベタ、全角、二分" `T.isInfixOf`) . snd) ms)
              body src @?= [Paragraph Nothing [Text (mkSpan (FileId 1) 0 1) "a"]]
        g0255 "a[aki]\n"
        g0255 "a[aki 十分]\n"
        g0255 "a[aki 四分: 語]\n"
        g0255 "a[aki 四分 二分]\n"
        g0255 "a[aki -1zw]\n"
        g0255 "a[aki x=四分]\n"
        g0255 "a[aki [= 1]]\n",
      testCase "G0238: commands that take no prose slot" $ do
        msgs "[number-text 1: x]\n" @?= [("G0238", "number-text は散文スロットを取りません")]
        msgs "[ref-number intro: x]\n" @?= [("G0238", "ref-number は散文スロットを取りません")]
        msgs "[ref-title intro: x]\n" @?= [("G0238", "ref-title は散文スロットを取りません")]
        msgs "[ref-page intro: x]\n" @?= [("G0238", "ref-page は散文スロットを取りません")]
        diags "[cite knuth1981: x]\n" @?= [("G0238", "cite は散文スロットを取りません", 0, 19)]
        body "[cite knuth1981: x]\n" @?= [Paragraph Nothing []]
        errs "# [ref-number intro: x]\n" @?= ["G0214"],
      testCase "G0239, G0240, G0241, G0243" $ do
        msgs "[kenten shape=star: a]\n" @?= [("G0239", "未知の圏点の形です: star")]
        msgs "[tcy: [strong: 12]]\n" @?= [("G0240", "縦中横の中身は地の文に限ります")]
        errs "a[tcy: %% c %%]b\n" @?= []
        paraOf "a[tcy: %% c %%]b\n" @?= ["ab"]
        msgs "[index reading=あ: [strong: 語]]\n" @?= [("G0241", "索引の語は地の文に限ります")]
        msgs "[ruby: 字|[strong: じ]]\n" @?= [("G0243", "ルビの読みは地の文に限ります")],
      testCase "G0205: kept in dev, a warning over the comment in prod" $ do
        errs "本文%%= メモ %%\n" @?= []
        case body "本文%%= メモ %%\n" of
          [Paragraph Nothing [Text _ "本文", ProofComment _ _]] -> pure ()
          other -> assertFailure (show other)
        let (file, _, _) = parseAst (FileId 1) "本文%%= メモ %%\n"
        [(diagCode d, diagSeverity d, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- erDiagnostics (evalFile ctx {ctxProfile = Prod} file)]
          @?= [(DiagnosticCode "G0205", Warning, 6, 19)],
      testCase "G0209: the position is the name" $
        diags "@nope\n" @?= [("G0209", "未知のブロックコマンドです: @nope", 1, 5)],
      testCase "G0210: no block after attributes" $ do
        diags "@label a\n" @?= [("G0210", "@label の後にブロックがありません", 0, 9)]
        diags "@label a\n@notoc\n" @?= [("G0210", "属性の後にブロックがありません", 0, 16)]
        diags "@style verse\n" @?= [("G0210", "@style の後にブロックがありません", 0, 13)],
      testCase "G0211: the other commands of the group are evaluated" $ do
        msgs "@label a\n@set x = 1\n# [= x]\n" @?= [("G0211", "属性のまとまりに属性でないコマンドがあります")]
        case body "@label a\n@set x = 1\n# [= x]\n" of
          [Heading 1 _ is] -> stripSpans is @?= ["1"]
          other -> assertFailure (show other),
      testCase "G0212: each repeated attribute line" $ do
        diags "@label a\n@notoc\n@label b\n# x\n" @?= [("G0212", "同じ属性を二度書いています", 16, 25)]
        map (\(c, _, s, e) -> (c, s, e)) (diags "@label a\n@label b\n@label c\n# x\n") @?= [("G0212", 9, 18), ("G0212", 18, 27)],
      testCase "G0213: attributes on the wrong block" $ do
        diags "@notoc\n本文。\n" @?= [("G0213", "@notoc はこのブロックには付けられません", 0, 7)]
        diags "@figure images/a.png alt=x\n  @style quote\n  キャプション。\n" @?= [("G0213", "@style は図版のキャプションには付けられません", 27, 42)],
      testCase "G0215: every ruby split into segments must match" $ do
        msgs "[ruby: 東京|とう/きょう]\n" @?= [("G0215", "モノルビの対象と読みのセグメントの数が一致しません")]
        errs "[ruby: 五月雨|さみだれ]\n" @?= []
        errs "[ruby: お/父/さん|/とう/]\n" @?= [],
      testCase "G0217, G0218, G0221: an argument that is not a name" $ do
        msgs "[color [= \"x\"]: a]\n" @?= [("G0217", "color にはスウォッチの名前を一つ書きます")]
        msgs "[style [= \"x\"]: a]\n" @?= [("G0218", "style には文字スタイルの名前を一つ書きます")]
        msgs "[cite [= \"x\"]]\n" @?= [("G0221", "cite には書誌データのキーを一つ書きます")]
        msgs "[color red: x]\n" @?= [("G0217", "style.toml にないスウォッチです: red")]
        msgs "[cite nope]\n" @?= [("G0221", "書誌データにないキーです: nope")],
      testCase "G0219: number-text" $ do
        msgs "[number-text]\n" @?= [("G0219", "number-text には整数を一つ書きます")]
        msgs "[number-text 1.5]\n" @?= [("G0219", "number-text に渡せるのは整数だけです")]
        errs "[number-text [= 1 / 0]]\n" @?= ["G0203"],
      testCase "G0222: the position is the name" $ do
        diags "[nope: x]\n" @?= [("G0222", "未知のコマンドです: nope", 1, 5)]
        case phCallCommand noPlugins "nope" [] [] (mkSpan (FileId 1) 0 3) of
          Left [d] -> diagCode d @?= DiagnosticCode "G0222"
          other -> assertFailure (show (fmap fst other)),
      testCase "G0233: missing files" $ do
        msgs "@listing images/none.txt\n" @?= [("G0233", "ファイルがありません: images/none.txt")]
        msgs "@table src=none.csv\n" @?= [("G0233", "ファイルがありません: none.csv")]
        msgs "@listing gone.txt\n" @?= [("G0233", "ファイルがありません: gone.txt")],
      testCase "G0260: paths that cannot be used" $ do
        msgs "@figure /tmp/a.png alt=x\n" @?= [("G0260", "絶対パスは使えません: /tmp/a.png")]
        msgs "@figure images/a.png web=\"https://example.com/a.png\" alt=x\n" @?= [("G0260", "URL は使えません: https://example.com/a.png")]
        diags "@listing ../outside.txt\n" @?= [("G0260", "プロジェクトルートの外を指しています: ../outside.txt", 0, 24)]
    ]
