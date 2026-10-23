module FileSpec (tests) where

import Control.Exception (evaluate)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble (ChannelDecl (..), ChannelOrder (..))
import Golem.Doc.IR
import Golem.Doc.Validate (validateDocument)
import Golem.Eval.Builtin (OverridableBuiltin (..), pluginCommandName)
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Parser (parseAst)
import Golem.Parser.SourceSettings
import Golem.Project.Paths (PathError (..))
import Golem.Project.Style (LineBreaks (..), LocalStyles (..), RegexStyleDef (..), Style (..), defaultStyle, dimToSp, paraLineBreaks, parseDim, parseStyle)
import Golem.Syntax
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

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
            ("images/a.PDF", AssetPresent),
            ("images/a.gif", AssetPresent),
            ("images/b.pdf", AssetPresent),
            ("images/b.svg", AssetPresent),
            ("images/b.jpg", AssetPresent),
            ("data.csv", AssetText (FileId 21) "a,b\n1,\"x,y\"\n"),
            ("src/Main.hs", AssetText (FileId 22) "l1\nl2\nl3\n"),
            ("x.hs", AssetText (FileId 23) (T.unlines ["line " <> T.pack (show i) | i <- [1 :: Int .. 25]])),
            ("empty.csv", AssetText (FileId 24) ""),
            ("blank.csv", AssetText (FileId 25) "\n\n"),
            ("ragged.csv", AssetText (FileId 26) "a,b\n1\n"),
            ("ctl.csv", AssetText (FileId 27) "a,b\n1,x\STXy\n"),
            ("ctl.hs", AssetText (FileId 28) "l1\nl\ETX2\n"),
            ("tab.hs", AssetText (FileId 29) "a\tb\nc\n"),
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

-- | A plugin command that answers PLUGIN at the call.
pluginOutput :: PluginCommand
pluginOutput = PluginCommand (\_ _ sp -> Right ([Text sp "PLUGIN"], []))

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

-- | The texts of each paragraph of a verse, with their spans.
verseTexts :: Text -> [[(Text, Int, Int)]]
verseTexts src = [[(t, spanStart tsp, spanEnd tsp) | Text tsp t <- is] | Paragraph (Just "verse") is <- body src]

-- | The notices of a source: code, message, start and end.
notices :: Text -> [(Text, Text, Int, Int)]
notices src = [d | d@(c, _, _, _) <- diags src, c `elem` ["G02064", "G02079"]]

fst3 :: (a, b, c) -> a
fst3 (a, _, _) = a

fst4 :: (a, b, c, d) -> a
fst4 (a, _, _, _) = a

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
      testCase "the reading of one segment against a base of two is G02015" $
        errs "[ruby: 漢/字|かん\\/じ]\n" @?= ["G02015"],
      testCase "the separators written in the source are as before" $ do
        errs "[ruby: 東京|とう/きょう]\n" @?= ["G02015"]
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

-- | The characters that cannot be written to the output are G02089 (docs/adr ADR 0042).
outputCharTests :: TestTree
outputCharTests =
  testGroup
    "characters that cannot be written to the output (docs/adr ADR 0042)"
    [ testCase "U+0001 in a paragraph is G02089 at the text of the paragraph" $
        [(c, s, e, "U+0001" `T.isInfixOf` m) | (c, m, s, e) <- diags "前\SOH後\n"] @?= [("G02089", 0, 7, True)],
      testCase "one G02089 for each string, with the first character" $
        [(c, "U+0001" `T.isInfixOf` m) | (c, m, _, _) <- diags "a\SOHb\USc\n\n# d\SOe\n"] @?= [("G02089", True), ("G02089", False)],
      testCase "U+0002 in a cell of a table file is G02089" $
        [(c, "U+0002" `T.isInfixOf` m) | (c, m, _, _) <- diags "@table src=ctl.csv\n"] @?= [("G02089", True)],
      testCase "U+0003 in the file of @listing is G02089" $
        [(c, "U+0003" `T.isInfixOf` m) | (c, m, _, _) <- diags "@listing ctl.hs\n"] @?= [("G02089", True)],
      testCase "a tab and a newline pass" $ do
        errs "@listing tab.hs\n" @?= []
        errs "a\tb\n" @?= [],
      testCase "U+007F and U+0085 pass" $
        errs "a\DELb\x85\&c\n" @?= []
    ]

tests :: TestTree
tests =
  testGroup
    "file evaluation, S0 (ADR 0002)"
    [ verseTests,
      outputCharTests,
      printingsTests,
      diagnosticTests,
      settingsTests,
      noticeTests,
      styleTests,
      separatorTests,
      hardBreakTests,
      breakTests,
      pageControlTests,
      blankLineTests,
      codeTests,
      escapeTests,
      duplicateKeyTests,
      shorthandTests,
      int64Tests,
      channelCommandTests,
      powDiagnosticTests,
      testCase "variables, expressions and meta" $
        paraOf "@set x = 2\n\n[= x * 3] と [= meta.title]\n" @?= ["6 と 本の題"],
      testCase "redefinition and use before definition are errors" $ do
        errs "@set x = 1\n\n@set x = 2\n" @?= ["G02024"]
        errs "[= y]\n\n@set y = 1\n" @?= ["G02002"],
      testCase "imports bind a namespace" $
        paraOf "@import common/values.gm as v\n\n[= v.price + 1]\n" @?= ["101"],
      testCase "an expression as the path of @import is G03009 (golem-project ADR 0006)" $ do
        errs "@import [= 1] as x\n" @?= ["G03009"]
        errs "@import \"common/values.gm\" as v\n" @?= [],
      testCase "doc becomes a deferred expression; forbidden in headings" $ do
        paraOf "@set n = 1\n\n[= doc.chapters.count + n]\n" @?= ["<deferred>"]
        errs "# 全 [= doc.chapters.count] 章\n" @?= ["G02014"]
        errs "# [ref-title intro]\n" @?= ["G02014"],
      testCase "notes are numbered per file" $
        paraOf "a[note: 一]b[note: 二]\n" @?= ["a", "<note 1>", "一", "b", "<note 2>", "二"],
      testCase "ruby segments" $ do
        paraOf "[ruby: 東/京|とう/きょう][ruby: 五月雨|さみだれ][ruby: お/父/さん|/とう/]\n" @?= ["<ruby 2>", "<ruby 1>", "<ruby 3>"]
        errs "[ruby: 東/京|とう]\n" @?= ["G02015"]
        errs "[ruby: [ruby: a|b]|c]\n" @?= ["G02016"],
      testCase "number-text" $ do
        paraOf "[number-text 10 style=tcy]\n" @?= ["<number 10 Just StyleTcy>"]
        errs "[number-text 1.5]\n" @?= ["G02019"]
        errs "[number-text 1 style=roman]\n" @?= ["G02019"],
      testCase "references and citations" $ do
        paraOf "[ref-number intro][cite knuth1981]\n" @?= ["<ref RefNumber intro>", "Cite (SrcSpan {spanFile = FileId 1, spanStart = 18, spanEnd = 34}) \"knuth1981\""]
        errs "[cite nope]\n" @?= ["G02021"],
      testCase "styles and swatches must exist" $ do
        errs "[color accent: x][style term: y]\n" @?= []
        errs "[color red: x]\n" @?= ["G02017"]
        errs "[style nope: x]\n" @?= ["G02018"],
      testCase "index requires a reading" $ do
        errs "[index reading=くみはん: 組版]\n" @?= []
        errs "[index: 組版]\n" @?= ["G02020"]
        errs "[index reading=あ/い/う: a/b/c]\n" @?= ["G02042"],
      testCase "unknown commands" $ do
        errs "[nope: x]\n" @?= ["G02022"]
        errs "@nope\n" @?= ["G02009"],
      testCase "attributes attach to the next block" $
        case body "@label intro\n@nonumber\n@toc-title 短い\n# はじめに\n" of
          [Heading 1 (HeadingAttrs (Just t) Nothing True False) _] -> stripSpans t @?= ["短い"]
          other -> assertFailure (show other),
      testCase "attribute errors" $ do
        errs "@label a\n@label b\n# x\n" @?= ["G02012"]
        errs "@label a\n" @?= ["G02010"]
        errs "@nonumber\n本文。\n" @?= ["G02013"]
        errs "@label a\n@set x = 1\n# x\n" @?= ["G02011"],
      testCase "figures" $ do
        errs "@figure images/a.png alt=\"x\"\n  キャプション。\n" @?= []
        errs "@figure images/a.png\n" @?= ["G02028"]
        errs "@figure images/a.pdf alt=x\n" @?= ["G02029"]
        errs "@figure images/none.png alt=x\n" @?= ["G02033"]
        errs "@figure images/a.png alt=x wrap=end\n" @?= ["G02031"],
      testCase "the formats of a figure and its web image (golem-pdf ADR 0008)" $ do
        msgs "@figure images/a.gif alt=\"x\"\n" @?= [("G02074", "図版の形式は PDF、PNG、JPEG、SVG です: images/a.gif")]
        errs "@figure images/a.PDF web=images/a.png alt=\"x\"\n" @?= []
        msgs "@figure images/a.pdf web=images/b.pdf alt=\"x\"\n" @?= [("G02073", "web の代替画像は PNG、JPEG、SVG です: images/b.pdf")]
        errs "@figure images/a.png web=images/b.jpg alt=\"x\"\n" @?= []
        case body "@figure images/a.png web=images/b.jpg alt=\"x\"\n" of
          [FigureBlock f] -> (figWeb f, figPage f) @?= (Just "images/b.jpg", Nothing)
          other -> assertFailure (show other),
      testCase "SVG figures and web images (golem-pdf ADR 0009)" $ do
        errs "@figure images/b.svg alt=\"x\"\n" @?= []
        errs "@figure images/a.pdf web=images/b.svg alt=\"x\"\n" @?= []
        errs "@figure images/b.svg page=1 alt=\"x\"\n" @?= ["G02075"],
      testCase "the page of a PDF figure (golem-pdf ADR 0008)" $ do
        case body "@figure images/a.pdf page=2 web=images/a.png alt=\"x\"\n" of
          [FigureBlock f] -> figPage f @?= Just 2
          other -> assertFailure (show other)
        msgs "@figure images/a.pdf page=0 web=images/a.png alt=\"x\"\n" @?= [("G02075", "page は PDF の図版のページを 1 から数えた整数で書きます: 0")]
        errs "@figure images/a.pdf page=x web=images/a.png alt=\"x\"\n" @?= ["G02075"]
        errs "@figure images/a.png page=1 alt=\"x\"\n" @?= ["G02075"],
      testCase "a figure turned to take a page of its own (golem-driver ADR 0034)" $ do
        let rotateOf src = case body src of
              [FigureBlock f] -> pure (figRotate f)
              other -> assertFailure (show other)
        rotateOf "@figure images/a.png alt=\"x\" rotate=true\n" >>= (@?= True)
        rotateOf "@figure images/a.png alt=\"x\" rotate=false\n" >>= (@?= False)
        rotateOf "@figure images/a.png alt=\"x\"\n" >>= (@?= False)
        msgs "@figure images/a.png alt=\"x\" rotate=yes\n" @?= [("G02087", "rotate は true か false です: yes")]
        msgs "@figure images/a.png alt=\"x\" rotate=true wrap=end width=4zw\n" @?= [("G02087", "回して置く図版は回り込ませられません")],
      testCase "csv tables and listings" $ do
        case body "@table src=data.csv\n" of
          [Table _ h [r]] -> (map stripSpans h, map stripSpans r) @?= ([["a"], ["b"]], [["1"], ["x,y"]])
          other -> assertFailure (show other)
        map (fmap codeText . codeOf) (body "@listing src/Main.hs lines=2-3\n") @?= [Just "l2\nl3"]
        errs "@listing src/Main.hs lines=3-9\n" @?= ["G02037"],
      testCase "proofreading comments: kept in dev, warned and dropped in prod" $ do
        errs "本文%%= メモ %%\n" @?= []
        snd (run ctx {ctxProfile = Prod} "本文%%= メモ %%\n") @?= ["G02005"],
      testCase "a plugin may override a built-in command when declared" $ do
        let hook = noPlugins {phOverrides = Map.fromList [(BStrong, pluginOutput)]}
        fst (run ctx {ctxPlugins = hook} "[strong: x]\n") @?= [Paragraph Nothing [Text (mkSpan (FileId 1) 0 11) "PLUGIN"]],
      testCase "a plugin command with a name of its own (docs/adr ADR 0027)" $ do
        greet <- maybe (assertFailure "greet is not built in") pure (pluginCommandName "greet")
        let hook = noPlugins {phCommands = Map.fromList [(greet, pluginOutput)]}
        fst (run ctx {ctxPlugins = hook} "[greet: x]\n") @?= [Paragraph Nothing [Text (mkSpan (FileId 1) 0 10) "PLUGIN"]]
        diagsWith ctx {ctxPlugins = hook} "[nope: x]\n" @?= [("G02022", "未知のコマンドです: nope", 1, 5)]
    ]

verseTests :: TestTree
verseTests =
  testGroup
    "verse and newlines in paragraphs (docs/adr ADR 0003, 0005)"
    [ testCase "newlines in a paragraph produce nothing" $
        body "吾輩は猫である。\n名前はまだ無い。\n" @?= [Paragraph Nothing [Text (mkSpan (FileId 1) 0 49) "吾輩は猫である。名前はまだ無い。"]],
      testCase "newlines are dropped before the tcy check" $
        -- no G02040; the digits make the notice G02063 (golem-syntax ADR 0002)
        errs "[tcy: 1\n2]\n" @?= ["G02063"],
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
      testCase "@style code is G02066 (golem-driver ADR 0017)" $ do
        let c = ctx {ctxParaStyles = Map.insert "code" JoinLines (ctxParaStyles ctx)}
        snd (run c "@style code\nx\n") @?= ["G02066"]
        snd (run c "@style code\n  x\n") @?= ["G02066"]
        [m | (code', m, _, _) <- diagsWith c "@style code\nx\n", code' == "G02066"] @?= ["code はコードブロックの段落スタイルです。コードは ``` か @listing で書きます"],
      testCase "the body form" $
        map stripped (body "@style verse\n  A\n  B\n\n  C\n") @?= [(Just "verse", ["A", "<br>", "B"]), (Just "verse", ["C"])],
      testCase "the attribute form" $
        map stripped (body "@style verse\nA\nB\n") @?= [(Just "verse", ["A", "<br>", "B"])],
      testCase "a join style joins the lines" $
        map stripped (body "@style quote\nab\ncd\n") @?= [(Just "quote", ["abcd"])],
      testCase "body is no style" $
        map stripped (body "@style body\nx\n") @?= [(Nothing, ["x"])],
      testCase "a wrong @style block is a diagnostic: an unknown or missing name, an unknown command, a list or comment inside, no body" $ do
        errs "@style nope\nx\n" @?= ["G02047"]
        map stripped (body "@style nope\nx\n") @?= [(Nothing, ["x"])]
        errs "@style\n  x\n" @?= ["G02047"]
        errs "@verse\n  A\n" @?= ["G02009"]
        errs "@style verse\n  - a\n" @?= ["G02045"]
        errs "@style verse\n  %% c %%\n" @?= ["G02046"]
        errs "@style verse\n" @?= ["G02010"],
      testCase "a style on a block that is not a paragraph" $ do
        errs "@style quote\n# 見出し\n" @?= ["G02013"]
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
        errs "@label a\n@set x = 1\n@figure images/a.png alt=x\n" @?= ["G02011"],
      testCase "a style inside a caption" $
        errs "@figure images/a.png alt=x\n  @style quote\n  キャプション。\n" @?= ["G02013"],
      testCase "a filter must not invent paragraph styles" $ do
        let hook = noPlugins {phApplyFilters = \_ (Document f bs) -> Right (Document f (bs <> [Block (mkSpan f 0 1) Nothing (Paragraph (Just "nope") [])]), [])}
        snd (run ctx {ctxPlugins = hook} "x\n") @?= ["G02047"]
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

-- | The number shorthand ##…## (golem-parser ADR 0011).
shorthandTests :: TestTree
shorthandTests =
  testGroup
    "the number shorthand ##…## (golem-parser ADR 0011)"
    [ testProperty "##N## is [number-text N]" $ property $ do
        n <- forAll (Gen.integral (Range.linear 0 (10 ^ (15 :: Int))))
        let t = T.pack (show (n :: Integer))
        paraOf ("##" <> t <> "##\n") === paraOf ("[number-text " <> t <> "]\n")
        errs ("##" <> t <> "##\n") === [],
      testCase "##10## is a Number at the whole shorthand" $
        body "a##10##b\n" @?= [Paragraph Nothing [Text (mkSpan (FileId 1) 0 1) "a", Number (mkSpan (FileId 1) 1 7) 10 Nothing, Text (mkSpan (FileId 1) 7 8) "b"]],
      testCase "anything but ASCII digits is G02078 at the whole shorthand" $ do
        let msg = "## と ## のあいだには算用数字だけを書きます。本文の ## は \\## と書きます"
        mapM_
          (\(src, e) -> (src, diags src) @?= (src, [("G02078", msg, 0, e)]))
          [("##007##\n", 7), ("##1.5##\n", 7), ("##1,000##\n", 9), ("##1 2##\n", 7), ("##12年\n", 7)]
        body "##1.5##\n" @?= [Paragraph Nothing []],
      testCase "inside [code: ...] it is text" $ do
        let c = ctx {ctxCharStyles = Set.fromList ["code", "strong", "note"]}
        fst (run c "[code: ##1##]\n") @?= [Paragraph Nothing [CharStyle (mkSpan (FileId 1) 0 13) "code" [Text (mkSpan (FileId 1) 7 12) "##1##"]]]
        snd (run c "[code: ##1.5##]\n") @?= []
        snd (run c "[code: [strong: ##12年]]\n") @?= []
        map (fmap stripSpans . paraInlines) (fst (run c "[style code: ##1##]\n")) @?= [Just ["<code>", "##1##"]]
        map (fmap stripSpans . paraInlines) (fst (run c "[style note: ##1##]\n")) @?= [Just ["<note>", "<number 1 Nothing>"]],
      testCase "a plugin over code gets the text; a plugin over number-text gets the call" $ do
        let slotText = PluginCommand (\_ slots sp -> Right ([Text sp (T.concat [t | Text _ t <- concat slots])], []))
            overCode = noPlugins {phOverrides = Map.fromList [(BCode, slotText)]}
            overNumber = noPlugins {phOverrides = Map.fromList [(BNumberText, pluginOutput)]}
        map (fmap stripSpans . paraInlines) (fst (run ctx {ctxPlugins = overCode} "[code: ##1##]\n")) @?= [Just ["##1##"]]
        map (fmap stripSpans . paraInlines) (fst (run ctx {ctxPlugins = overNumber} "a##1##\n")) @?= [Just ["aPLUGIN"]],
      testCase "a ruby base takes a number; a reading does not, as [number-text 1]" $ do
        case body "[ruby: 第##1##|だいいち]\n" of
          [Paragraph Nothing [Ruby _ _ segs]] -> assertBool (show segs) (or [True | RubySegment b _ <- segs, Number {} <- b])
          other -> assertFailure (show other)
        errs "[ruby: 一|##1##]\n" @?= errs "[ruby: 一|[number-text 1]]\n"
        assertBool "G02043" ("G02043" `elem` errs "[ruby: 一|##1##]\n"),
      testCase "[tcy: ##10##] is G02040 as [tcy: [number-text 10]]" $ do
        errs "[tcy: ##10##]\n" @?= errs "[tcy: [number-text 10]]\n"
        assertBool "G02040" ("G02040" `elem` errs "[tcy: ##10##]\n")
    ]

-- | @channel, the list of a channel of a plugin (golem-doc ADR 0007).
channelCommandTests :: TestTree
channelCommandTests =
  testGroup
    "@channel (golem-doc ADR 0007)"
    [ testCase "a declared channel is its list, with the style of its entries" $ do
        fst (run withGlossary "@channel glossary\n") @?= [ChannelOutput (CustomOutput "glossary" Nothing)]
        fst (run withGlossary "@channel glossary style=quote\n") @?= [ChannelOutput (CustomOutput "glossary" (Just "quote"))]
        fst (run withGlossary "@channel glossary style=body\n") @?= [ChannelOutput (CustomOutput "glossary" Nothing)]
        snd (run withGlossary "@channel glossary\n") @?= [],
      testCase "G02090: a channel no plugin declares, at the command" $ do
        diagsWith withGlossary "@channel unknown\n" @?= [("G02090", "宣言されていないチャネルです: unknown", 0, 17)]
        msgs "@channel glossary\n" @?= [("G02090", "宣言されていないチャネルです: glossary")],
      testCase "G02090: no name, or two" $ do
        [(c, m) | (c, m, _, _) <- diagsWith withGlossary "@channel\n"] @?= [("G02090", "@channel にはチャネルの名前を一つ書きます")]
        [(c, m) | (c, m, _, _) <- diagsWith withGlossary "@channel a b\n"] @?= [("G02090", "@channel にはチャネルの名前を一つ書きます")]
        fst (run withGlossary "@channel a b\n") @?= [],
      testCase "G02047: a paragraph style not defined" $
        snd (run withGlossary "@channel glossary style=nope\n") @?= ["G02047"]
    ]
  where
    withGlossary = ctx {ctxPlugins = noPlugins {phChannels = Map.fromList [("glossary", ChannelDecl "glossary" OrderReading False)]}}

-- | The integers of the IR are int64; one out of range is G02091 (golem-doc ADR 0006).
int64Tests :: TestTree
int64Tests =
  testGroup
    "G02091: an integer out of the range of the IR (golem-doc ADR 0006)"
    [ testCase "[number-text] at the ends of int64" $ do
        paraOf "[number-text [= 2 ** 63 - 1]]\n" @?= ["<number 9223372036854775807 Nothing>"]
        paraOf "[number-text [= -(2 ** 63)]]\n" @?= ["<number -9223372036854775808 Nothing>"]
        errs "[number-text [= 2 ** 63 - 1]]\n" @?= [],
      testCase "[number-text] beyond int64 is G02091 at the command and puts out nothing" $ do
        diags "[number-text [= 2 ** 63]]\n" @?= [("G02091", msg, 0, 25)]
        msgs "[number-text [= -(2 ** 63) - 1]]\n" @?= [("G02091", msg)]
        paraOf "a[number-text [= 2 ** 63]]b\n" @?= ["ab"]
        msgs "##9223372036854775808##\n" @?= [("G02091", msg)],
      testCase "@number beyond int64 is G02091 at its line and numbers as without it" $ do
        let src = "@number 9223372036854775808\n# h\n"
        diags src @?= [("G02091", msg, 0, 28)]
        [haNumber a | Heading _ a _ <- body src] @?= [Nothing]
        msgs "@number 9223372036854775807\n# h\n" @?= [],
      testCase "numbers= whose last line is beyond int64 is G02091 and numbers as without it" $ do
        let src = "``` numbers=9223372036854775807\na\nb\n```\n"
            (bs, ds) = run ctx src
        ds @?= ["G02091"]
        bs @?= fst (run ctx "```\na\nb\n```\n")
        [c | (c, _, s, _) <- diags src, s == 0] @?= ["G02091"]
        snd (run ctx "``` numbers=9223372036854775806\na\nb\n```\n") @?= [],
      testCase "an aki beyond int64 is G02091 and puts out nothing" $ do
        msgs "a[aki 99999999999999999999mm]b\n" @?= [("G02091", msg)]
        paraOf "a[aki 99999999999999999999mm]b\n" @?= ["ab"],
      testCase "a deferred expression with an integer beyond int64 is G02091" $ do
        msgs "@set n = 2 ** 70\n\n[= n + doc.chapters.count]\n" @?= [("G02091", msg)]
        body "@set n = 2 ** 70\n\n[= n + doc.chapters.count]\n" @?= [Paragraph Nothing []]
        errs "@set n = 2 ** 62\n\n[= n + doc.chapters.count]\n" @?= []
        -- a value in prose is text, not an integer of the IR
        paraOf "[= 2 ** 70]\n" @?= ["1180591620717411303424"],
      testCase "a plugin command with an argument beyond int64 is G02091 and is not called" $ do
        greet <- maybe (assertFailure "greet is not built in") pure (pluginCommandName "greet")
        let hook = noPlugins {phCommands = Map.fromList [(greet, pluginOutput)]}
            c = ctx {ctxPlugins = hook}
        run c "[greet [= 2 ** 63]: x]\n" @?= ([Paragraph Nothing []], ["G02091"])
        run c "[greet [= [1, 2 ** 63]]: x]\n" @?= ([Paragraph Nothing []], ["G02091"])
        snd (run c "[greet [= 2 ** 63 - 1]: x]\n") @?= []
    ]
  where
    msg = "整数が意味論 IR に書ける範囲を超えています（-2 の 63 乗以上、2 の 63 乗未満に限ります）"

-- | The same key twice among the keyword arguments (golem-parser ADR 0013).
duplicateKeyTests :: TestTree
duplicateKeyTests =
  testGroup
    "the same key twice is G02077 (golem-parser ADR 0013)"
    [ testCase "a built-in command keeps the first" $ do
        -- "[number-text 10 style=kanji style=tcy]": the second style=tcy is bytes 28 to 37
        [d | d@(c, _, _, _) <- diags "[number-text 10 style=kanji style=tcy]\n", c == "G02077"]
          @?= [("G02077", "同じキーを二度書いています: style", 28, 37)]
        paraOf "[number-text 10 style=kanji style=tcy]\n" @?= ["<number 10 Just StyleKanji>"],
      testCase "a block command keeps the first" $ do
        let (bs, ds) = run ctx "@toc depth=1 depth=3\n"
        ds @?= ["G02077"]
        bs @?= [ChannelOutput (TocOutput 1)],
      testCase "the line that opens a code block" $
        do
          -- "``` text" would make text a positional argument (G02069); the language follows the fence
          errs "```text numbers=true numbers=false\na\n```\n" @?= ["G02077"]
          filter (== "G02077") (errs "``` text numbers=true numbers=false\na\n```\n") @?= ["G02077"],
      testCase "a plugin command" $ do
        broken <- maybe (assertFailure "broken is built in") pure (pluginCommandName "broken")
        let hook = noPlugins {phCommands = Map.fromList [(broken, pluginOutput)]}
        snd (run ctx {ctxPlugins = hook} "[broken k=1 k=2]\n") @?= ["G02077"],
      testCase "every key after the first" $
        [(s, e) | (c, _, s, e) <- diags "[f k=1 k=2 k=3]\n", c == "G02077"] @?= [(7, 10), (11, 14)],
      testCase "different keys and an unexpanded **[...] are not" $ do
        filter (== "G02077") (errs "[f k=1 j=1]\n") @?= []
        filter (== "G02077") (errs "[f k=1 **[h]]\n") @?= [],
      testCase "@style-def keeps G02052" $
        codesS "@style-def character x weight=bold weight=normal\n" @?= ["G02052"]
    ]

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
    [ testCase "G02062: a @style-def over a style of style.toml or a built-in one" $ do
        let at src = [(c, m, s) | (c, m, s, _) <- diagsWith sctx src, c == "G02062"]
        at "@style-def paragraph body indent=1zw\n\nx\n" @?= [("G02062", "ファイルの中の定義が段落スタイルの body を上書きしています", 0)]
        at "@style-def paragraph letter based-on=body\n\nx\n" @?= []
        let headingStyle = either (error . show) id (parseStyle (FileId 9) "[fonts.heading]\nja = \"fonts/h.otf\"\n")
            hctx = ctx {ctxStyle = headingStyle, ctxCharStyles = Map.keysSet (stCharStyles headingStyle), ctxParaStyles = paraLineBreaks headingStyle}
        [c | (c, _, _, _) <- diagsWith hctx "@style-def character bold font=heading\n\n[bold: x]\n"] @?= ["G02062"]
        at "@style-def paragraph letter indent=1zw\n@style-def paragraph quote indent=2zw\n\nx\n" @?= [("G02062", "ファイルの中の定義が段落スタイルの quote を上書きしています", 39)],
      -- golem-driver ADR 0043
      testCase "G03100: a zero indent of caption or sidenote in @style-def, at the keyword" $ do
        let at src = [(c, m, st) | (c, m, st, _) <- diagsWith sctx src, c == "G03100"]
        at "@style-def paragraph caption indent=0zw\n\nx\n" @?= [("G03100", "キャプションと傍注は字下げを掛けないので、caption.indent = 0zw は効果がありません", 29)]
        at "@style-def paragraph sidenote first-line-indent=\"0mm\"\n\nx\n" @?= [("G03100", "キャプションと傍注は字下げを掛けないので、sidenote.first-line-indent = \"0mm\" は効果がありません", 30)]
        at "@style-def paragraph quote indent=0zw\n\nx\n" @?= []
        [c | (c, _, _, _) <- diagsWith sctx "@style-def paragraph caption indent=1zw\n\nx\n"] @?= ["G03006"]
        let (_, ds, _) = runS sctx "@style-def paragraph caption indent=0zw\n\nx\n"
        sort [(diagCode d, diagSeverity d) | d <- ds] @?= [(DiagnosticCode "G02062", Notice), (DiagnosticCode "G03100", Notice)],
      testCase "G02062 is a notice" $ do
        let (_, ds, _) = runS sctx "@style-def paragraph body indent=1zw\n\nx\n"
        map diagSeverity ds @?= [Notice],
      testCase "G02063: [tcy: ...] of ASCII digits only" $ do
        [(c, m, s, e) | (c, m, s, e) <- diags "a[tcy: 10]b\n", c == "G02063"] @?= [("G02063", "数の縦中横は [number-text 10 style=tcy] でも書けます", 1, 10)]
        errs "[tcy: !?]\n" @?= []
        errs "[tcy: 1a]\n" @?= []
        errs "[number-text 10 style=tcy]\n" @?= [],
      -- golem-parser ADR 0012
      testCase "G02079: an escaped space at the end of a line of a paragraph that keeps its lines" $ do
        -- "@style verse\n" is 13 bytes; "ab\\ " starts at 13
        verseTexts "@style verse\nab\\ \n" @?= [[("ab", 13, 15)]]
        notices "@style verse\nab\\ \n" @?= [("G02079", "行末のエスケープした空白は無視されます", 15, 16)]
        verseTexts "@style verse\ncd\\ \\ \n" @?= [[("cd", 13, 15)]]
        notices "@style verse\ncd\\ \\ \n" @?= [("G02079", "行末のエスケープした空白は無視されます", 15, 16)]
        map (map fst3) (verseTexts "@style verse\nef\\\t\n") @?= [["ef"]]
        map fst4 (notices "@style verse\nef\\\t\n") @?= ["G02079"],
      testCase "G02079: plain spaces after the escape" $ do
        map (map fst3) (verseTexts "@style verse\ngh\\    \n") @?= [["gh"]]
        map fst4 (notices "@style verse\ngh\\    \n") @?= ["G02079"],
      testCase "no G02079 for plain spaces at the end of a line" $ do
        map (map fst3) (verseTexts "@style verse\nij  \n") @?= [["ij"]]
        notices "@style verse\nij  \n" @?= [],
      testCase "an escaped indent: G02064 only, and the text starts at its first letter" $ do
        verseTexts "@style verse\n\\ gh\n" @?= [[("gh", 15, 17)]]
        map fst4 (notices "@style verse\n\\ gh\n") @?= ["G02064"]
        map (map fst3) (verseTexts "@style verse\n\\ \\ gh\n") @?= [["gh"]]
        map fst4 (notices "@style verse\n\\ \\ gh\n") @?= ["G02064"]
        map (map fst3) (verseTexts "@style verse\n\\  \\ gh\n") @?= [["gh"]]
        map fst4 (notices "@style verse\n\\  \\ gh\n") @?= ["G02064"],
      testCase "a line of an escaped space alone is G02064 only, not G02079 too" $ do
        -- "@style verse\na\n" is 15 bytes; the escape of the second line is at 15
        notices "@style verse\na\n\\ \n" @?= [("G02064", "行頭のエスケープした空白は無視されます。字下げには全角の空白を使います", 15, 16)],
      testCase "an escape at each end of one line is G02064 and G02079" $
        -- "@style verse\n" is 13 bytes; "\\ gh\\ ": the escapes at 13 and 17
        [(c, s) | (c, _, s, _) <- notices "@style verse\n\\ gh\\ \n"] @?= [("G02064", 13), ("G02079", 17)],
      testCase "G02079 once for each line that ends in an escape" $
        -- "@style verse\n" is 13 bytes; "ab\\ \n" is 5, so "cd\\ " starts at 18
        [(c, s) | (c, _, s, _) <- notices "@style verse\nab\\ \ncd\\ \n"] @?= [("G02079", 15), ("G02079", 20)],
      testCase "an escaped space inside a line stays" $ do
        map (map fst3) (verseTexts "@style verse\na\\ b\n") @?= [["a b"]]
        notices "@style verse\na\\ b\n" @?= [],
      testCase "a paragraph that joins its lines keeps the escaped space" $ do
        paraOf "ij\\ \nkl\n" @?= ["ij kl"]
        errs "ij\\ \nkl\n" @?= [],
      testCase "G02064: an escaped space at the start of a line of a paragraph that keeps its lines" $ do
        [(c, m, s) | (c, m, s, _) <- diags "@style verse\n  a\n  \\ x\n", c == "G02064"]
          @?= [("G02064", "行頭のエスケープした空白は無視されます。字下げには全角の空白を使います", 19)]
        errs "@style verse\n  \\ x\n" @?= ["G02064"]
        errs "@style quote\n  \\ x\n" @?= []
        errs "\\ x\n" @?= []
        errs "@style verse\n  a\\ b\n" @?= []
        -- the escaped space is dropped as before (golem-parser ADR 0010)
        verseOf "@style verse\n  a\n  \\ x\n" @?= [[["a"], ["x"]]],
      testCase "G02065: @listing src=, and the content is the same" $ do
        [(c, m, s, e) | (c, m, s, e) <- diags "@listing src=src/Main.hs\n", c == "G02065"]
          @?= [("G02065", "@listing の src= は廃止予定です。パスを最初の引数に書きます", 9, 24)]
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
        map (\d -> let DiagnosticCode c = diagCode d in c) ds' @?= ["G02018"]
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
      testCase "a name defined twice in a file is G02053" $ do
        codesS "@style-def paragraph a\n@style-def paragraph a\n" @?= ["G02053"]
        -- the first overrides quote of style.toml (golem-syntax ADR 0002)
        codesS "@style-def paragraph quote\n@style-def paragraph quote indent=1zw\n" @?= ["G02053", "G02062"],
      testCase "a style of style.toml or a built-in style may be overridden" $ do
        let ok src name = do
              let (_, ds, r) = runS sctx src
              -- G02062 tells the override (golem-syntax ADR 0002)
              map diagCode ds @?= [DiagnosticCode "G02062"]
              assertBool (T.unpack name) (Map.member name (lsParaStyles (erStyles r)) || Map.member name (lsCharStyles (erStyles r)))
        ok "@style-def paragraph body indent=1zw\n\nx\n" "body"
        ok "@style-def character strong synthetic-italic=true\n\n[strong: x]\n" "strong"
        ok "@style-def paragraph quote indent=1zw\n\n@style quote\nx\n" "quote",
      testCase "an override of verse changes how its newlines are read" $ do
        let (bs, _, _) = runS sctx "@style-def paragraph verse line-breaks=join\n\n@style verse\na\nb\n"
        map stripped bs @?= [(Just "verse", ["ab"])]
        let (bs', _, _) = runS sctx "@style verse\na\nb\n"
        map stripped bs' @?= [(Just "verse", ["a", "<br>", "b"])],
      testCase "the arguments of @style-def and @manifest are G02052" $ do
        mapM_
          (\src -> (src, codesS src) @?= (src, ["G02052"]))
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
      testCase "@manifest overrides only the keys of [source] (G02050)" $ do
        codesS "@manifest title=x\n" @?= ["G02050"]
        codesS "@manifest paragraph-separater=line\n" @?= ["G02050"]
        let (bs, ds, _) = runS sctx "@manifest title=x\n@label p\na\n"
        map (\d -> let DiagnosticCode c = diagCode d in c) ds @?= ["G02050"]
        map stripped bs @?= [(Nothing, ["a"])],
      testCase "@style-def regex adds a regex style for the file (docs/adr ADR 0015)" $ do
        let (bs, ds, _) = runS sctx "@style-def regex body pattern=\"\\\\d+\" style=bold\n\na1\n"
        map stripped bs @?= [(Nothing, ["a", "<bold>", "1"])]
        ds @?= []
        let (bs', _, _) = runS sctx "a1\n"
        map stripped bs' @?= [(Nothing, ["a1"])],
      testCase "a value of the wrong type in @style-def is in Japanese (golem-project ADR 0007)" $ do
        let (_, ds, _) = runS sctx "@style-def character term font=1\n\nx\n"
        [(x, diagMessage d) | d <- ds, let { DiagnosticCode x = diagCode d }] @?= [("G03006", "@style-def の値が不正です: font には文字列を書きます（整数が書かれています）")],
      testCase "the errors of @style-def regex (docs/adr ADR 0015)" $ do
        codesS "@style-def regex nope pattern=x style=bold\n" @?= ["G03013"]
        codesS "@style-def regex body style=bold\n" @?= ["G03006"]
        codesS "@style-def regex body pattern=\"\\\\1\" style=bold\n" @?= ["G03015"]
        codesS "@style-def regex body\n" @?= ["G03006"]
        codesS "@style-def regex body pattern=x style=nope\n" @?= ["G03013"]
        codesS "@style-def regex body pattern=x style=bold colour=x\n" @?= ["G03006"]
        codesS "@style-def regex body pattern=x pattern=y style=bold\n" @?= ["G02052"],
      testCase "a wrong regex style is reported at its line and dropped, the others stay" $ do
        let src = "@style-def regex body pattern=a style=bold\n@style-def regex body pattern=\"\\\\1\" style=bold\n@style-def regex body pattern=b style=nope\n\nab\n"
            (bs, ds, r) = runS sctx src
        [(x, spanStart (diagSpan d)) | d <- ds, let { DiagnosticCode x = diagCode d }] @?= [("G03015", 43), ("G03013", 90)]
        Map.lookup "body" (lsRegexStyles (erStyles r)) @?= Just [RegexStyleDef "a" "bold"]
        map stripped bs @?= [(Nothing, ["<bold>", "a", "b"])],
      testCase "the regex styles of a file are added in the order written, not G02053" $ do
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
        at "@style-def paragraph Letter\n" @?= [("G03006", 0)]
        at "@style-def paragraph a line-breaks=x\n" @?= [("G03006", 0)]
        at "@style-def paragraph a based-on=nope\n" @?= [("G03013", 0)]
        -- the paths of style.toml are not used for a file (golem-project ADR 0008)
        let grid = either (error . show) id (parseStyle (FileId 0) "[page]\nsize = \"A5\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 40\nlines = 30\nline-pitch = \"16pt\"\nposition = { top = \"14mm\", gutter = \"14mm\" }\n")
            (_, gds, _) = runS sctx {ctxStyle = grid} "@style-def paragraph big size=30Q\n\na\n"
        [(x, spanStart (diagSpan d)) | d <- gds, let { DiagnosticCode x = diagCode d }, x == "G03011"] @?= [("G03011", 0)]
        codesS "@style-def paragraph a based-on=nope\n\n@style a\nx\n" @?= ["G03013", "G02047"],
      testCase "@manifest and @style-def elsewhere are G02049" $ do
        codesS "a\n\n@style-def paragraph letter\n" @?= ["G02049"]
        codesS "@label x\n@style-def paragraph letter\na\n" @?= ["G02049"]
        codesS "a\n\n@manifest paragraph-separator=line\n" @?= ["G02049"],
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
        map (\d -> let DiagnosticCode c = diagCode d in c) ds @?= ["G02049"]
        erSource r @?= ctxSource sctx,
      testCase "the keys and values of @manifest (G02050, G02051, G02052)" $ do
        codesS "@manifest title=x\n" @?= ["G02050"]
        codesS "@manifest paragraph-separater=line\n" @?= ["G02050"]
        codesS "@manifest paragraph-separator=lines\n" @?= ["G02051"]
        mapM_
          (\src -> (src, codesS src) @?= (src, ["G02052"]))
          [ "@manifest paragraph-separator=line paragraph-separator=line\n",
            "@manifest paragraph-separator=[= \"line\"]\n",
            "@manifest paragraph-separator=line\n  a\n"
          ]
        let (bs, ds, _) = runS sctx "@manifest title=x paragraph-separator=line\n\na\nb\n"
        map (\d -> let DiagnosticCode c = diagCode d in c) ds @?= ["G02050"]
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
        map (\d -> let DiagnosticCode c = diagCode d in c) ds' @?= ["G02047"]
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
      testCase "an evaluated file records the paragraph separator of its context" $ do
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
      testCase "a hard break in a prose slot is G02056" $ do
        errs "[note: a\\\nb] c\n" @?= ["G02056"]
        paraOf "[note: a\\\nb] c\n" @?= ["<note 1>", "ab", " c"],
      testCase "an empty line is G02057 and the paragraph is valid" $
        mapM_
          ( \c ->
              mapM_
                ( \src -> do
                    let (bs, es) = run c src
                    assertEqual (show src) ["G02057"] es
                    validateDocument (const (Just 1000)) [] (Document (FileId 1) [Block (mkSpan (FileId 1) 0 1) Nothing b | b <- bs]) @?= []
                )
                ["\\\na\n", "a\\\n\\\nb\n", "a\\\n%% c %%\nb\n"]
          )
          [ctx, lineCtx],
      testCase "a file with a hard break still records the line-separated paragraphs" $ do
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
      testCase "a break right before a block goes before it, without G02011" $ do
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
        errs "@label x\n@page-break\n\na\n" @?= ["G02010"],
      testCase "a wrong argument of @page-break is G02058 (docs/adr ADR 0060)" $ do
        mapM_
          (\src -> assertEqual (T.unpack src) [("G02058", "@page-break の引数は recto か verso です")] (msgs src))
          [ "@page-break page\n",
            "@page-break recto verso\n",
            "@page-break x=1\n"
          ],
      testCase "an argument of @column-break is G02096 (docs/adr ADR 0060)" $
        msgs "@column-break recto\n" @?= [("G02096", "@column-break は引数を取りません")],
      testCase "a body under a break is G02097 at its first block (docs/adr ADR 0060)" $ do
        diags "@page-break\n  a\n" @?= [("G02097", "@page-break は本体を持てません", 12, 16)]
        msgs "@column-break\n  a\n" @?= [("G02097", "@column-break は本体を持てません")],
      testCase "an argument and a body are G02096 then G02097 (docs/adr ADR 0060)" $
        map fst (msgs "@column-break recto\n  a\n") @?= ["G02096", "G02097"],
      testCase "a break not at the top of the document is G02059 and dropped" $ do
        mapM_
          ( \src -> do
              let (bs, es) = blocksOf src
              assertEqual (T.unpack src) ["G02059"] es
              assertBool (T.unpack src) (not (any hasBreak bs))
          )
          [ "- a\n\n  @page-break\n",
            "= t\n  @page-break\n",
            "@figure images/a.png alt=a\n  @page-break\n"
          ]
        errs "@style quote\n  @page-break\n" @?= ["G02045"]
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

-- | Manual control of page breaks (docs/adr ADR 0030).
pageControlTests :: TestTree
pageControlTests =
  testGroup
    "manual control of page breaks (docs/adr ADR 0030)"
    [ testCase "each control is a block" $ do
        run ctx "a\n\n@no-page-break\n\nb\n" @?= ([Paragraph Nothing [Text (mkSpan (FileId 1) 0 1) "a"], PageControl NoBreak, Paragraph Nothing [Text (mkSpan (FileId 1) 19 20) "b"]], [])
        run ctx "@need-lines 5\n" @?= ([PageControl (NeedLines 5)], [])
        run ctx "@page-lines +1\n" @?= ([PageControl (AdjustLines 1)], [])
        run ctx "@page-lines -2\n" @?= ([PageControl (AdjustLines (-2))], []),
      testCase "a label skips the control and goes to the block" $ do
        let (file, _, pds) = parseAst (FileId 1) "@need-lines 3\n@label x\n# h\n"
            r = evalFile ctx file
        map diagCode (pds <> erDiagnostics r) @?= []
        [(blockLabel b, isControl (blockBody b)) | b <- docBlocks (erDocument r)] @?= [(Nothing, True), (Just "x", False)],
      testCase "a wrong argument of @need-lines is G02070 (docs/adr ADR 0060)" $
        mapM_
          (\src -> assertEqual (T.unpack src) [("G02070", "@need-lines の引数は 1 以上の整数です")] (msgs src))
          ["@need-lines\n", "@need-lines 0\n", "@need-lines 2.5\n", "@need-lines 3 4\n", "@need-lines n=3\n"],
      testCase "a wrong argument of @page-lines is G02099 (docs/adr ADR 0060)" $
        mapM_
          (\src -> assertEqual (T.unpack src) [("G02099", "@page-lines の引数は +1 や -1 のように符号を付けた 0 でない整数です")] (msgs src))
          ["@page-lines\n", "@page-lines 1\n", "@page-lines +0\n", "@page-lines +1 +2\n", "@page-lines n=+1\n"],
      testCase "an argument of @no-page-break is G02096 (docs/adr ADR 0060)" $
        msgs "@no-page-break x\n" @?= [("G02096", "@no-page-break は引数を取りません")],
      testCase "a body under a control is G02097 (docs/adr ADR 0060)" $
        mapM_
          (\(src, name) -> assertEqual (T.unpack src) [("G02097", "@" <> name <> " は本体を持てません")] (msgs src))
          [("@no-page-break\n  a\n", "no-page-break"), ("@need-lines 3\n  a\n", "need-lines"), ("@page-lines +1\n  a\n", "page-lines")],
      testCase "a wrong argument and a body are both reported (docs/adr ADR 0060)" $ do
        map fst (msgs "@no-page-break x\n  a\n") @?= ["G02096", "G02097"]
        map fst (msgs "@page-lines 1\n  a\n") @?= ["G02099", "G02097"],
      testCase "a control not at the top of the document is G02071 and dropped" $ do
        let (bs, es) = run ctx "- a\n\n  @no-page-break\n"
        es @?= ["G02071"]
        assertBool "no control" (not (any hasControl bs)),
      testCase "a control and a forced break at the same place are G02072" $ do
        mapM_
          (\src -> assertEqual (T.unpack src) ["G02072"] (errs src))
          [ "@no-page-break\n@page-break\n",
            "@column-break\n\n@no-page-break\n",
            "@no-page-break\n@need-lines 2\n@page-break\n"
          ]
        errs "@no-page-break\n\na\n\n@page-break\n" @?= []
    ]
  where
    isControl = \case
      PageControl _ -> True
      _ -> False
    hasControl = \case
      PageControl _ -> True
      BulletList items -> any (any (hasControl . blockBody) . itemBlocks) items
      _ -> False

-- | Blank lines between blocks (docs/adr ADR 0046).
blankLineTests :: TestTree
blankLineTests =
  testGroup
    "blank lines (docs/adr ADR 0046)"
    [ testCase "@blank-line is a block, in both styles of the paragraph separator" $
        mapM_
          ( \c -> do
              outline c "あ\n@blank-line\nい\n" @?= (["p あ", "blank 1", "p い"], [])
              outline c "あ\n\n@blank-line 2\n\nい\n" @?= (["p あ", "blank 2", "p い"], [])
              outline c "あ\n@blank-line 9223372036854775807\n" @?= (["p あ", "blank 9223372036854775807"], [])
          )
          [ctx, lineCtx],
      testCase "wrong arguments and a body are G02092 and give no block" $
        mapM_
          (\src -> assertEqual (T.unpack src) ([], ["G02092"]) (outline ctx src))
          [ "@blank-line 0\n",
            "@blank-line -1\n",
            "@blank-line 1.5\n",
            "@blank-line x\n",
            "@blank-line 1 2\n",
            "@blank-line lines=2\n",
            "@blank-line +1\n",
            "@blank-line\n  あ\n"
          ],
      testCase "an integer out of int64 is G02091" $
        outline ctx "@blank-line 9223372036854775808\n" @?= ([], ["G02091"]),
      testCase "the messages of G02092" $ do
        msgs "@blank-line 0\n" @?= [("G02092", "@blank-line の引数は 1 以上の整数を一つだけ書きます")]
        msgs "@blank-line\n  あ\n" @?= [("G02092", "@blank-line は本体を持てません")],
      testCase "@blank-line not at the top of the document is G02093 and dropped" $ do
        mapM_
          ( \src -> do
              let (bs, es) = blocksWith src
              assertEqual (T.unpack src) ["G02093"] es
              assertBool (T.unpack src) (not (any hasBlank bs))
          )
          [ "- あ\n\n  @blank-line\n  い\n",
            "@figure images/a.png alt=a\n  c\n\n  @blank-line\n",
            "= t\n  @blank-line\n"
          ]
        msgs "- あ\n\n  @blank-line\n  い\n" @?= [("G02093", "@blank-line は文書の最上位にだけ置けます")],
      testCase "@blank-line in the body of @style is G02045" $
        errs "@style verse\n  あ\n\n  @blank-line\n" @?= ["G02045"],
      testCase "in an attribute group, the blank lines go before the target and the attributes skip them" $ do
        labelled "@blank-line\n@label x\n# 見出し\n" @?= ([(Nothing, "blank 1"), (Just "x", "heading")], [])
        labelled "@label x\n@blank-line\n# 見出し\n" @?= ([(Nothing, "blank 1"), (Just "x", "heading")], [])
        snd (labelled "@label x\n@blank-line\n") @?= ["G02010"],
      testCase "blank lines written in a row are the notice G02094 at the later ones" $ do
        outline ctx "@blank-line\n@blank-line 2\nあ\n" @?= (["blank 1", "blank 2", "p あ"], ["G02094"])
        [(c, m, s) | (c, m, s, _) <- diags "@blank-line\n@blank-line 2\nあ\n"] @?= [("G02094", "続けて書いた @blank-line は @blank-line <N> にまとめて書けます", 12)]
        snd (outline ctx "@blank-line\n@need-lines 3\n@blank-line\nあ\n") @?= ["G02094"]
        snd (outline ctx "@blank-line\n@no-page-break\n@page-lines +1\n@blank-line\nあ\n") @?= ["G02094"]
        snd (outline ctx "@blank-line\n@blank-line\n@blank-line\nあ\n") @?= ["G02094", "G02094"]
        snd (outline ctx "@blank-line\nあ\n@blank-line\nい\n") @?= []
        snd (outline ctx "@blank-line\n@page-break\n@blank-line\nい\n") @?= [],
      testCase "G02094 is a notice" $ do
        let (_, ds, _) = runS ctx "@blank-line\n@blank-line\n"
        [diagSeverity d | d <- ds] @?= [Notice]
        assertBool "a notice code" (DiagnosticCode "G02094" `elem` noticeCodes),
      testCase "an inline [blank-line] is an unknown command" $
        assertBool "an error" (not (null (errs "あ[blank-line]い\n")))
    ]
  where
    outline c src = let (bs, es) = run c src in (map shape bs, es)
    shape = \case
      Paragraph _ is -> "p " <> T.concat (stripSpans is)
      BlankLines n -> "blank " <> T.pack (show n)
      Heading {} -> "heading"
      other -> T.pack (show other)
    labelled src =
      let (file, _, pds) = parseAst (FileId 1) src
          r = evalFile ctx file
       in ([(blockLabel b, shape (blockBody b)) | b <- docBlocks (erDocument r)], [x | d <- pds <> erDiagnostics r, let DiagnosticCode x = diagCode d])
    blocksWith src =
      let (file, _, pds) = parseAst (FileId 1) src
          r = evalFile ctx file
       in (docBlocks (erDocument r), [x | d <- pds <> erDiagnostics r, let DiagnosticCode x = diagCode d])
    hasBlank (Block _ _ b) = case b of
      BlankLines _ -> True
      BulletList items -> any (any hasBlank . itemBlocks) items
      OrderedList items -> any (any hasBlank . itemBlocks) items
      DefList gs -> any (any (any hasBlank) . dgDefs) gs
      FigureBlock f -> any hasBlank (figCaption f)
      _ -> False

-- | The code of a code block.
codeOf :: BlockBody -> Maybe Code
codeOf = \case
  CodeBlock c -> Just c
  _ -> Nothing

-- | The code of the only code block of a source.
oneCode :: Text -> IO Code
oneCode src = case run ctx src of
  ([CodeBlock c], []) -> pure c
  other -> assertFailure (show other) >> error "unreachable"

{- | The lines of code: text, number, diff mark, highlight and callouts
(golem-driver ADR 0023).
-}
linesOf :: Code -> [(Text, Maybe Integer, Maybe DiffMark, Bool, [Int])]
linesOf c = [(clText l, clNumber l, clDiff l, clHighlight l, clCallouts l) | l <- codeLines c]

-- | Code blocks for technical books (golem-driver ADR 0023).
codeTests :: TestTree
codeTests =
  testGroup
    "code blocks for technical books (golem-driver ADR 0023)"
    [ testCase "numbers=10: the lines are 10, 11, 12" $ do
        c <- oneCode "```haskell numbers=10\na\nb\nc\n```\n"
        map clNumber (codeLines c) @?= [Just 10, Just 11, Just 12]
        codeNumbers c @?= Just True
        codeLang c @?= Just "haskell",
      testCase "numbers=true: 1, 2, 3; numbers=false: Just False; nothing written: Nothing" $ do
        c <- oneCode "``` numbers=true\na\nb\nc\n```\n"
        map clNumber (codeLines c) @?= [Just 1, Just 2, Just 3]
        codeNumbers c @?= Just True
        codeLang c @?= Nothing
        f <- oneCode "``` numbers=false\na\n```\n"
        codeNumbers f @?= Just False
        n <- oneCode "```\na\nb\n```\n"
        codeNumbers n @?= Nothing
        map clNumber (codeLines n) @?= [Just 1, Just 2],
      testCase "@listing lines=20-22 numbers the lines 20, 21, 22; numbers=5 makes them 5, 6, 7" $ do
        c <- oneCode "@listing x.hs lines=20-22\n"
        linesOf c @?= [("line 20", Just 20, Nothing, False, []), ("line 21", Just 21, Nothing, False, []), ("line 22", Just 22, Nothing, False, [])]
        d <- oneCode "@listing x.hs lines=20-22 numbers=5\n"
        map clNumber (codeLines d) @?= [Just 5, Just 6, Just 7],
      testCase "highlight=2,4-5: lines 2, 4 and 5; highlight=9 in three lines is G02069" $ do
        c <- oneCode "``` highlight=2,4-5\na\nb\nc\nd\ne\n```\n"
        map clHighlight (codeLines c) @?= [False, True, False, True, True]
        msgs "``` highlight=9\na\nb\nc\n```\n" @?= [("G02069", "highlight の行 9 はこのコードにありません")]
        l <- oneCode "@listing x.hs lines=20-22 highlight=21\n"
        map clHighlight (codeLines l) @?= [False, True, False],
      localOption (mkTimeout 10000000) $ testCase "a highlight range far beyond the code ends at once (docs/adr ADR 0035)" $ do
        msgs "``` highlight=2-1000000000000\na\nb\nc\n```\n" @?= [("G02069", "highlight の行 4 はこのコードにありません")]
        -- the blocks too, highlight and all, as the LSP keeps them
        size <- evaluate (length (show (run ctx "``` highlight=2-1000000000000\na\nb\nc\n```\n")))
        assertBool "evaluated" (size > 0)
        c <- oneCode "``` highlight=2-3\na\nb\nc\n```\n"
        map clHighlight (codeLines c) @?= [False, True, True],
      testCase "diff=true: +, -, space and an empty line" $ do
        c <- oneCode "``` diff=true\n+a\n-b\n c\n\n```\n"
        codeDiff c @?= True
        linesOf c
          @?= [ ("a", Just 1, Just DiffAdded, False, []),
                ("b", Nothing, Just DiffRemoved, False, []),
                ("c", Just 2, Just DiffContext, False, []),
                ("", Just 3, Just DiffContext, False, [])
              ],
      testCase "diff=true: a line that starts with another character is G02069 at the line" $
        diags "``` diff=true\n+a\nxa\n```\n" @?= [("G02069", "diff=true のコードの行は +、-、空白のどれかで始めます", 17, 19)],
      testCase "a removed line cannot be highlighted" $
        msgs "``` diff=true highlight=2\n+a\n-b\n```\n" @?= [("G02069", "highlight の行 2 はこのコードにありません")],
      testCase "callouts=true: <1> at the line end, several, the spaces before them" $ do
        c <- oneCode "``` callouts=true\nfoo  <1>\nbar <2> <3>\nbaz\n```\n"
        linesOf c @?= [("foo", Just 1, Nothing, False, [1]), ("bar", Just 2, Nothing, False, [2, 3]), ("baz", Just 3, Nothing, False, [])]
        diags "``` callouts=true\nfoo <51>\n```\n" @?= [("G02069", "注釈の印の番号は 1 から 50 までです: 51", 18, 26)],
      testCase "without callouts, <1> stays in the text" $ do
        c <- oneCode "```\nList<1>\nfoo <1>\n```\n"
        map clText (codeLines c) @?= ["List<1>", "foo <1>"]
        map clCallouts (codeLines c) @?= [[], []],
      testCase "@caption: inlines, code style included" $ do
        c <- oneCode "@caption 設定の [code: x] の読み込み\n```\na\n```\n"
        fmap stripSpans (codeCaption c) @?= Just ["設定の ", "<code>", "x", " の読み込み"],
      testCase "@caption on a paragraph is G02013; with no text G02069" $ do
        errs "@caption 説明\n段落。\n" @?= ["G02013"]
        msgs "@caption\n```\na\n```\n" @?= [("G02069", "@caption には本文を書きます")],
      testCase "@caption and @label before @listing" $ do
        case body "@label cfg\n@caption 設定\n@listing x.hs lines=1-2\n" of
          [CodeBlock c] -> fmap stripSpans (codeCaption c) @?= Just ["設定"]
          other -> assertFailure (show other)
        case run ctx "@label cfg\n@caption 設定\n@listing x.hs lines=1-2\n" of
          (_, ds) -> ds @?= [],
      testCase "the wrong arguments are G02069" $ do
        msgs "```haskell foo\na\n```\n" @?= [("G02069", "コードブロックの開始の行には、言語の名前とキーワード引数だけを書けます")]
        msgs "``` unknown=1\na\n```\n" @?= [("G02069", "コードブロックに書けないキーです: unknown。numbers、file、highlight、diff、callouts（@listing では lang も）を書けます")]
        msgs "``` numbers=-1\na\n```\n" @?= [("G02069", "numbers の値が正しくありません: -1")]
        msgs "``` numbers=abc\na\n```\n" @?= [("G02069", "numbers の値が正しくありません: abc")]
        msgs "``` diff=yes\na\n```\n" @?= [("G02069", "diff の値が正しくありません: yes")]
        msgs "@listing x.hs unknown=1\n" @?= [("G02069", "コードブロックに書けないキーです: unknown。numbers、file、highlight、diff、callouts（@listing では lang も）を書けます")],
      testCase "lang= of @listing is the language; on the fence it is G02069" $ do
        c <- oneCode "@listing x.hs lines=1-1 lang=haskell\n"
        codeLang c @?= Just "haskell"
        errs "``` lang=haskell\na\n```\n" @?= ["G02069"],
      testCase "file= is the file name" $ do
        c <- oneCode "```haskell file=\"src/Main.hs\"\na\n```\n"
        codeFile c @?= Just "src/Main.hs"
        l <- oneCode "@listing x.hs lines=1-1 file=x.hs\n"
        codeFile l @?= Just "x.hs",
      testCase "a code block without arguments is as before" $ do
        c <- oneCode "```hs\na\n  b\n```\n"
        c @?= Code (Just "hs") Nothing Nothing Nothing False [CodeLine "a" (Just 1) Nothing False [], CodeLine "  b" (Just 2) Nothing False []]
    ]

-- | The codes, messages and positions of golem-eval ADR 0003.
diagnosticTests :: TestTree
diagnosticTests =
  testGroup
    "diagnostic codes (golem-eval ADR 0003)"
    [ testCase "G02023: a reserved word as a name" $ do
        diags "@set doc = 1\n" @?= [("G02023", "予約語は変数の名前に使えません: doc", 5, 8)]
        diags "@import common/values.gm as meta\n" @?= [("G02023", "予約語は名前空間に使えません: meta", 28, 32)],
      testCase "G02025: the depth of @toc" $ do
        mapM_ (\src -> (src, errs src) @?= (src, ["G02025"])) ["@toc depth=0\n", "@toc depth=4\n", "@toc depth=x\n"]
        msgs "@toc depth=0\n" @?= [("G02025", "@toc の depth は 1 から 3 の整数です")]
        errs "@toc\n" @?= []
        errs "@toc depth=3\n" @?= [],
      testCase "G02026: the names of labels" $ do
        let labelMsg = "@label にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます"
            refMsg = "参照にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます"
        msgs "@label Intro\n# x\n" @?= [("G02026", labelMsg)]
        msgs "@label a b\n# x\n" @?= [("G02026", labelMsg)]
        msgs "[ref-number Intro]\n" @?= [("G02026", refMsg)]
        msgs "[ref-number]\n" @?= [("G02026", refMsg)],
      testCase "G02027: @number" $ do
        errs "@number x\n# x\n" @?= ["G02027"]
        errs "@number 1 2\n# x\n" @?= ["G02027"]
        msgs "@number x\n# x\n" @?= [("G02027", "@number には整数を一つ書きます")]
        errs "@number 3\n+ a\n" @?= [],
      testCase "G02030, G02032, G02034" $ do
        msgs "@figure images/a.png alt=x wrap=left width=10mm\n" @?= [("G02030", "wrap は start か end です: left")]
        msgs "@figure alt=x\n" @?= [("G02032", "@figure には画像のパスを一つ書きます")]
        errs "@figure images/a.png images/b.png alt=x\n" @?= ["G02032"]
        msgs "@table data.csv\n" @?= [("G02034", "@table には src が必要です")],
      testCase "G02085: CSV that is not a table, in the file (golem-eval ADR 0004)" $ do
        msgs "@table src=empty.csv\n" @?= [("G02085", "CSV が空です")]
        msgs "@table src=blank.csv\n" @?= [("G02085", "CSV が空です")]
        diags "@table src=ragged.csv\n" @?= [("G02085", "CSV の行のセルの数が見出しの行と違います（見出しの行は 2、この行は 1）", 4, 5)],
      testCase "G02036: @listing without a path" $ do
        msgs "@listing\n" @?= [("G02036", "@listing にはファイルのパスが必要です")]
        -- src= is read, with the notice G02065 (golem-syntax ADR 0002)
        errs "@listing src=src/Main.hs\n" @?= ["G02065"],
      testCase "G02038: the number of prose slots" $ do
        msgs "[strong]\n" @?= [("G02038", "strong には散文スロットが一つ必要です")]
        msgs "[strong: a|b]\n" @?= [("G02038", "strong には散文スロットが一つ必要です")]
        msgs "[index reading=a]\n" @?= [("G02038", "index には散文スロットが一つ必要です")]
        msgs "[ruby: a]\n" @?= [("G02038", "ruby には散文スロットが二つ必要です")],
      testCase "[aki] puts a fixed space (docs/adr ADR 0019)" $ do
        let akiOf src = case body src of
              [Paragraph Nothing is] -> [(spanStart s, spanEnd s, a) | Aki s a <- is]
              other -> error (show other)
        akiOf "a[aki 五分]b\n" @?= [(1, 13, AkiZw (1 / 5))]
        akiOf "[aki 0.25zw][aki 12.5%][aki 全角]\n" @?= [(0, 12, AkiZw (1 / 4)), (12, 23, AkiZw (1 / 8)), (23, 35, AkiZw 1)]
        akiOf "3[aki 1mm]kg\n" @?= [(1, 10, AkiAbs (maybe 0 (dimToSp 0) (parseDim "1mm")))]
        akiOf "[aki \"2pt\"]\n" @?= [(0, 11, AkiAbs (2 * 65536))]
        errs "a[aki 五分]b\n" @?= [],
      testCase "G02055: [aki] needs one amount and no prose slot" $ do
        let g02055 src = do
              let ms = msgs src
              assertBool (show ms) (not (null ms) && all ((== "G02055") . fst) ms && all (("ベタ、全角、二分" `T.isInfixOf`) . snd) ms)
              body src @?= [Paragraph Nothing [Text (mkSpan (FileId 1) 0 1) "a"]]
        g02055 "a[aki]\n"
        g02055 "a[aki 十分]\n"
        g02055 "a[aki 四分: 語]\n"
        g02055 "a[aki 四分 二分]\n"
        g02055 "a[aki -1zw]\n"
        g02055 "a[aki x=四分]\n"
        g02055 "a[aki [= 1]]\n",
      testCase "G02038: commands that take no prose slot" $ do
        msgs "[number-text 1: x]\n" @?= [("G02038", "number-text は散文スロットを取りません")]
        msgs "[ref-number intro: x]\n" @?= [("G02038", "ref-number は散文スロットを取りません")]
        msgs "[ref-title intro: x]\n" @?= [("G02038", "ref-title は散文スロットを取りません")]
        msgs "[ref-page intro: x]\n" @?= [("G02038", "ref-page は散文スロットを取りません")]
        diags "[cite knuth1981: x]\n" @?= [("G02038", "cite は散文スロットを取りません", 0, 19)]
        body "[cite knuth1981: x]\n" @?= [Paragraph Nothing []]
        errs "# [ref-number intro: x]\n" @?= ["G02014"],
      testCase "kenten without a shape takes the default of style.toml (golem-driver ADR 0019)" $ do
        let kentenOf c src = case fst (run c src) of
              [Paragraph Nothing [Kenten _ sh _]] -> sh
              other -> error (show other)
        kentenOf ctx {ctxDefaultKenten = "circle"} "[kenten: 語]\n" @?= Just "circle"
        kentenOf ctx "[kenten: 語]\n" @?= Just "sesame"
        kentenOf ctx {ctxDefaultKenten = "circle"} "[kenten shape=dot: 語]\n" @?= Just "dot",
      testCase "the four added kenten shapes (golem-driver ADR 0019)" $ do
        mapM_ (\sh -> errs ("[kenten shape=" <> sh <> ": a]\n") @?= []) ["double-circle", "open-double-circle", "triangle", "open-triangle"]
        kentenShapes @?= ["sesame", "open-sesame", "dot", "open-dot", "circle", "open-circle", "double-circle", "open-double-circle", "triangle", "open-triangle"],
      testCase "G02039, G02040, G02041, G02043" $ do
        msgs "[kenten shape=star: a]\n" @?= [("G02039", "未知の圏点の形です: star")]
        msgs "[tcy: [strong: 12]]\n" @?= [("G02040", "縦中横の中身は地の文に限ります")]
        errs "a[tcy: %% c %%]b\n" @?= []
        paraOf "a[tcy: %% c %%]b\n" @?= ["ab"]
        msgs "[index reading=あ: [strong: 語]]\n" @?= [("G02041", "索引の語は地の文に限ります")]
        msgs "[ruby: 字|[strong: じ]]\n" @?= [("G02043", "ルビの読みは地の文に限ります")],
      testCase "G02005: kept in dev, a warning over the comment in prod" $ do
        errs "本文%%= メモ %%\n" @?= []
        case body "本文%%= メモ %%\n" of
          [Paragraph Nothing [Text _ "本文", ProofComment _ _]] -> pure ()
          other -> assertFailure (show other)
        let (file, _, _) = parseAst (FileId 1) "本文%%= メモ %%\n"
        [(diagCode d, diagSeverity d, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- erDiagnostics (evalFile ctx {ctxProfile = Prod} file)]
          @?= [(DiagnosticCode "G02005", Warning, 6, 19)],
      testCase "G02009: the position is the name" $
        diags "@nope\n" @?= [("G02009", "未知のブロックコマンドです: @nope", 1, 5)],
      testCase "G02010: no block after attributes" $ do
        diags "@label a\n" @?= [("G02010", "@label の後にブロックがありません", 0, 9)]
        diags "@label a\n@notoc\n" @?= [("G02010", "属性の後にブロックがありません", 0, 16)]
        diags "@style verse\n" @?= [("G02010", "@style の後にブロックがありません", 0, 13)],
      testCase "G02011: the other commands of the group are evaluated" $ do
        msgs "@label a\n@set x = 1\n# [= x]\n" @?= [("G02011", "属性のまとまりに属性でないコマンドがあります")]
        case body "@label a\n@set x = 1\n# [= x]\n" of
          [Heading 1 _ is] -> stripSpans is @?= ["1"]
          other -> assertFailure (show other),
      testCase "G02012: each repeated attribute line" $ do
        diags "@label a\n@notoc\n@label b\n# x\n" @?= [("G02012", "同じ属性を二度書いています", 16, 25)]
        map (\(c, _, s, e) -> (c, s, e)) (diags "@label a\n@label b\n@label c\n# x\n") @?= [("G02012", 9, 18), ("G02012", 18, 27)],
      testCase "G02013: attributes on the wrong block" $ do
        diags "@notoc\n本文。\n" @?= [("G02013", "@notoc はこのブロックには付けられません", 0, 7)]
        diags "@figure images/a.png alt=x\n  @style quote\n  キャプション。\n" @?= [("G02013", "@style は図版のキャプションには付けられません", 27, 42)],
      testCase "G02015: every ruby split into segments must match" $ do
        msgs "[ruby: 東京|とう/きょう]\n" @?= [("G02015", "モノルビの対象と読みのセグメントの数が一致しません")]
        errs "[ruby: 五月雨|さみだれ]\n" @?= []
        errs "[ruby: お/父/さん|/とう/]\n" @?= [],
      testCase "G02017, G02018, G02021: an argument that is not a name" $ do
        msgs "[color [= \"x\"]: a]\n" @?= [("G02017", "color にはスウォッチの名前を一つ書きます")]
        msgs "[style [= \"x\"]: a]\n" @?= [("G02018", "style には文字スタイルの名前を一つ書きます")]
        msgs "[cite [= \"x\"]]\n" @?= [("G02021", "cite には書誌データのキーを一つ書きます")]
        msgs "[color red: x]\n" @?= [("G02017", "style.toml にないスウォッチです: red")]
        msgs "[cite nope]\n" @?= [("G02021", "書誌データにないキーです: nope")],
      testCase "G02019: number-text" $ do
        msgs "[number-text]\n" @?= [("G02019", "number-text には整数を一つ書きます")]
        msgs "[number-text 1.5]\n" @?= [("G02019", "number-text に渡せるのは整数だけです")]
        errs "[number-text [= 1 / 0]]\n" @?= ["G02003"],
      testCase "G02022: the position is the name" $ do
        diags "[nope: x]\n" @?= [("G02022", "未知のコマンドです: nope", 1, 5)],
      testCase "G02033: missing files" $ do
        msgs "@listing images/none.txt\n" @?= [("G02033", "ファイルがありません: images/none.txt")]
        msgs "@table src=none.csv\n" @?= [("G02033", "ファイルがありません: none.csv")]
        msgs "@listing gone.txt\n" @?= [("G02033", "ファイルがありません: gone.txt")],
      testCase "G02060: paths that cannot be used" $ do
        msgs "@figure /tmp/a.png alt=x\n" @?= [("G02060", "絶対パスは使えません: /tmp/a.png")]
        msgs "@figure images/a.png web=\"https://example.com/a.png\" alt=x\n" @?= [("G02060", "URL は使えません: https://example.com/a.png")]
        diags "@listing ../outside.txt\n" @?= [("G02060", "プロジェクトルートの外を指しています: ../outside.txt", 0, 24)]
    ]

-- | A printing as meta.printings has it (docs/adr ADR 0033).
printingValue :: Integer -> Integer -> (Integer, Integer, Integer) -> Value
printingValue e n (y, m, d) =
  VHash (Map.fromList [("edition", VInt e), ("number", VInt n), ("year", VInt y), ("month", VInt m), ("day", VInt d), ("date", VString "")])

-- | The context of a book of a language with three printings.
printingsCtx :: Text -> EvalContext
printingsCtx lang =
  ctx
    { ctxMeta =
        Map.fromList
          [ ("language", VString lang),
            ("printings", VArray [printingValue 1 1 (2026, 10, 16), printingValue 1 2 (2027, 4, 1), printingValue 2 1 (2028, 1, 10)])
          ]
    }

-- | The text of a paragraph with its numbers in digits.
plainOf :: [Inline] -> Text
plainOf = T.concat . map (\case Text _ t -> t; Number _ n _ -> T.pack (show n); _ -> "")

printingsTests :: TestTree
printingsTests =
  testGroup
    "@printings (docs/adr ADR 0033)"
    [ testCase "three printings are three paragraphs; edition 1 is 初版, 2 is 第2版" $ do
        let (bs, es) = run (printingsCtx "ja") "@printings\n"
        es @?= []
        [plainOf is | Paragraph Nothing is <- bs] @?= ["2026年10月16日\x3000初版第1刷発行", "2027年4月1日\x3000初版第2刷発行", "2028年1月10日\x3000第2版第1刷発行"],
      testCase "the year is kanji-digits, the other numbers follow the default" $
        case run (printingsCtx "ja") "@printings\n" of
          (Paragraph _ is : _, _) -> [(n, st) | Number _ n st <- is] @?= [(2026, Just StyleKanjiDigits), (10, Nothing), (16, Nothing), (1, Nothing)]
          other -> assertFailure (show other),
      testCase "@style applies to every paragraph" $
        [st | Paragraph st _ <- fst (run (printingsCtx "ja") "@style quote\n@printings\n")] @?= [Just "quote", Just "quote", Just "quote"],
      testCase "a book not in Japanese is G02076 alone and sets nothing" $ do
        run (printingsCtx "en") "@printings\n" @?= ([], ["G02076"])
        [m | (_, m, _, _) <- diagsWith (printingsCtx "en") "@printings\n"] @?= ["@printings は日本語の本（language = \"ja\"）でだけ使えます"],
      testCase "a Japanese book without printings is G02098 alone and sets nothing" $ do
        let noPrintings = (printingsCtx "ja") {ctxMeta = Map.fromList [("language", VString "ja")]}
        run noPrintings "@printings\n" @?= ([], ["G02098"])
        [m | (_, m, _, _) <- diagsWith noPrintings "@printings\n"] @?= ["マニフェストに [[metadata.printings]] がありません"],
      testCase "an argument is G02096 and sets nothing" $ do
        run (printingsCtx "ja") "@printings 1\n" @?= ([], ["G02096"])
        [(c, m, s) | (c, m, s, _) <- diagsWith (printingsCtx "ja") "@printings 1\n"] @?= [("G02096", "@printings は引数を取りません", 0)]
        run (printingsCtx "ja") "@printings key=1\n" @?= ([], ["G02096"]),
      testCase "a body is G02097 at its first block and sets nothing" $ do
        run (printingsCtx "ja") "@printings\n  本文\n" @?= ([], ["G02097"])
        [(c, m, s) | (c, m, s, _) <- diagsWith (printingsCtx "ja") "@printings\n  本文\n"] @?= [("G02097", "@printings は本体を持てません", 11)],
      testCase "an argument and a body are G02096 then G02097" $
        run (printingsCtx "ja") "@printings 1\n  本文\n" @?= ([], ["G02096", "G02097"]),
      testCase "every cause is reported, in the order of the table" $
        run (printingsCtx "en") {ctxMeta = Map.fromList [("language", VString "en")]} "@printings 1\n" @?= ([], ["G02096", "G02076", "G02098"])
    ]

{- | The diagnostics of a power depend on the input alone: alone, after
other expressions, and twice in one file (golem-eval ADR 0006).
-}
powDiagnosticTests :: TestTree
powDiagnosticTests =
  testProperty "the diagnostics of a power depend on the input alone (golem-eval ADR 0006)" $ property $ do
    base <- forAll (Gen.element ["1.5", "1.50", "0.75", "3", "1.0000001", "1.000000417232513427734375", "0.99999998509883880615234375", "2.0", "(-3.0)"])
    k <- forAll (Gen.choice [Gen.integral (Range.linearFrom 0 (-1100) 1100), Gen.integral (Range.exponentialFrom 0 (negate (2 ^ (40 :: Int))) (2 ^ (40 :: Int)))])
    let e = "[= " <> base <> " ** " <> T.pack (show (k :: Integer)) <> "]"
        cm = map (\(c, m, _, _) -> (c, m))
        alone = cm (diags (e <> "\n"))
    cm (diags ("[= 1 + 1] [= 2.0 ** 3]\n\n" <> e <> "\n")) === alone
    cm (diags (e <> "\n\n" <> e <> "\n")) === alone <> alone
