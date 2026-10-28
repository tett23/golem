module ParserSpec (tests, fragments, fragment) where

import Data.ByteString qualified as BS
import Data.Either (fromLeft)
import Data.List (nub, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Parser
import Golem.Parser.AST qualified
import Golem.Parser.CST
import Golem.Parser.Read (checkText, readSource)
import Golem.Syntax
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

fid :: FileId
fid = FileId 0

parseOk :: Text -> Assertion
parseOk src = do
  let (cst, ds) = parse fid src
  render cst @?= src
  assertEqual ("diagnostics for:\n" <> T.unpack src <> "\n" <> T.unpack (pretty cst)) [] (map diagCode ds)

codes :: Text -> [DiagnosticCode]
codes src = map diagCode (snd (parse fid src))

astOf :: Text -> [Golem.Parser.AST.Located Golem.Parser.AST.Block]
astOf src = let (f, _, _) = parseAst fid src in Golem.Parser.AST.fileBlocks f

-- | The cells of a table without their spans; other blocks are Nothing.
tableShape :: Golem.Parser.AST.Located Golem.Parser.AST.Block -> Maybe [[[Golem.Parser.AST.Inline]]]
tableShape (Golem.Parser.AST.Located _ b) = case b of
  Golem.Parser.AST.Table _ h rows -> Just [map (map Golem.Parser.AST.locValue) r | r <- h : rows]
  _ -> Nothing

-- | The labels the grammar declares with @%recover@.
grammarLabels :: IO [Text]
grammarLabels = do
  grammar <- TIO.readFile "grammar/Golem.hpeg"
  pure [l | ("%recover" : l : _) <- map T.words (T.lines grammar)]

kinds :: Node -> [SyntaxKind]
kinds n = nodeKind n : concat [kinds m | ElemNode m <- nodeChildren n]

-- Fragments that exercise every construct, combined at random.

-- | Pieces of source that touch every construct of the grammar.
fragments :: [Text]
fragments =
  [ "本文",
    "[",
    "]",
    "[= 1 + 2]",
    "[ruby: 東/京|とう/きょう]",
    "\n",
    "\n\n",
    "# ",
    "- ",
    "+ ",
    "= ",
    "=:",
    "| a | b |",
    "|---|---|",
    "```",
    "@set x = 1",
    "@label a",
    "%%",
    "%%=",
    "\\[",
    "  ",
    "\t",
    "[strong: x",
    "[note id=a: y]",
    "😀",
    "{",
    ":",
    "*[x]",
    "\\"
  ]

fragment :: Gen Text
fragment = Gen.element fragments

tests :: TestTree
tests =
  testGroup
    "parser (ADR 0002-0004)"
    [ testProperty "lossless and total on arbitrary fragments" $ withTests 500 $ property $ do
        src <- forAll (T.concat <$> Gen.list (Range.linear 0 30) fragment)
        let (cst, _) = parse fid src
        render cst === src,
      testProperty "lossless on random unicode" $ withTests 200 $ property $ do
        src <- forAll (Gen.text (Range.linear 0 100) (Gen.frequency [(5, Gen.element (T.unpack "[]=:|@#-+\n %\\{}\"*`ab漢")), (1, Gen.unicode)]))
        render (fst (parse fid src)) === src,
      testCase "paragraphs and inline commands" $
        parseOk "Golem は[ruby: 組/版|くみ/はん]の結果を出力する[note: 決定性。]。\n本書は第[= version]版である。\n%% 図 %%\n",
      testCase "headings" $ parseOk "# はじめに\n\n## 節\n\n### 項\n",
      testCase "attributes and block commands" $
        parseOk "@import common/values.gm as values\n@set version = \"1.0\"\n\n@label intro\n@nonumber\n# はじめに\n\n本文。\n",
      testCase "lists" $ parseOk "- 印刷用の PDF\n- 電子書籍\n  - EPUB\n  - HTML\n\n+ 一\n+ 二\n",
      testCase "definition lists" $
        parseOk "= 決定性\n  同じ入力から同じ出力を得る性質。\n\n= HTTP\n= HyperText Transfer Protocol\n  共有する。\n\n= モナド\n  圏論。\n=:\n  プログラミング。\n",
      testCase "tables" $ parseOk "| 形式 | 用途 |\n|:---|---:|\n| PDF | 印刷 |\n| EPUB | 電子書籍 |\n",
      testCase "code blocks keep their content raw" $ do
        parseOk "```haskell\nmain = putStrLn \"[%%\\\"\n```\n"
        let (cst, _) = parse fid "```\n[x\n```\n"
        assertBool "no command inside code" (NInlineCommand `notElem` kinds cst),
      -- golem-driver ADR 0023
      testCase "code blocks take keyword arguments after the language" $ do
        parseOk "```haskell numbers=10 file=\"src/Main.hs\" highlight=12,14-15 callouts=true\nmain = pure ()\n```\n"
        parseOk "``` numbers=true\nx\n```\n",
      testCase "figure with caption body" $
        parseOk "@label fig-arch\n@figure images/arch.pdf web=images/arch.png alt=\"構成図\"\n  構成図のキャプション。\n",
      testCase "expressions" $ parseOk "[= -2 ** 2] [= round(2.675, 2)] [= [1, 2]] [= {a: 1, \"b\": true}] [= values.price >= 10]\n",
      testCase "splat and keyword arguments" $ parseOk "[number-text 10 style=tcy] [f *[xs] **[kw]: 本文 | 二つ目]\n",
      testCase "escapes" $ parseOk "\\# 見出しではない \\[ 50% \\\\\n",
      testCase "unclosed bracket is local to its paragraph" $ do
        let src = "前の段落。\n\n壊れた[strong: 段落\n\n後の段落。\n"
            (cst, ds) = parse fid src
        render cst @?= src
        map diagCode ds @?= [DiagnosticCode "G01017"]
        length [() | ElemNode n <- nodeChildren cst, nodeKind n == NParagraph] @?= 3,
      testCase "a bare bracket is an error" $ do
        let (_, ds) = parse fid "本文 [ だけ\n"
        map diagCode ds @?= [DiagnosticCode "G01021"],
      testCase "heading level four is an error and the next block survives" $ do
        let (cst, ds) = parse fid "#### 深すぎる\n\n# 正しい\n"
        map diagCode ds @?= [DiagnosticCode "G01012"]
        assertBool "heading parsed" (NHeading `elem` kinds cst),
      testCase "tab indentation is an error" $ do
        let (_, ds) = parse fid "- a\n\t- b\n"
        map diagCode ds @?= [DiagnosticCode "G01011"],
      testCase "odd indentation at top level is an error" $ do
        let (_, ds) = parse fid " 一つ空けた段落\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G01011"],
      testCase "orphan =: is an error" $ do
        let (_, ds) = parse fid "=:\n  説明\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G01013"],
      testCase "unclosed comment" $ do
        let (_, ds) = parse fid "本文 %% 閉じない\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G01018"],
      testCase "positional after keyword" $ do
        let (_, ds) = parse fid "[f a=1 b]\n"
        map diagCode ds @?= [DiagnosticCode "G01019"],
      testCase "mismatched table cells" $ do
        let (_, ds) = parse fid "| a | b |\n|---|---|\n| 1 |\n"
        map diagCode ds @?= [DiagnosticCode "G01015"],
      testCase "unclosed code block" $ do
        let (_, ds) = parse fid "```\nx\n"
        map diagCode ds @?= [DiagnosticCode "G01016"],
      -- golem-parser ADR 0007
      testCase "empty and blank-only files are accepted" $
        mapM_ parseOk ["", "\n", "\n\n", "  \n"],
      testCase "a trailing whitespace-only line without a newline is blank" $ do
        mapM_ parseOk ["a\n\n  ", "# h\n  ", "a\n\n\t"]
        astOf "a\n\n  " @?= astOf "a\n"
        astOf "# h\n  " @?= astOf "# h\n"
        astOf "a\n\n\t" @?= astOf "a\n",
      testCase "*[ always starts a splat" $ do
        -- The splat and the command it is in both lack their ].
        nub (codes "[f *[x y]]\n") @?= [DiagnosticCode "G01017"]
        codes "[f *[= 1]]\n" @?= [DiagnosticCode "G01020"]
        codes "[f **[= 1]]\n" @?= [DiagnosticCode "G01020"]
        parseOk "[f * x]\n",
      testCase "a line starting with | that is not a table row" $ do
        codes "| a |\n|---|\n|abc\n" @?= [DiagnosticCode "G01023"]
        let (cst, ds) = parse fid "| a |\n|---|\n|abc\n\n次の段落。\n"
        map diagCode ds @?= [DiagnosticCode "G01023"]
        length [() | ElemNode n <- nodeChildren cst, nodeKind n == NParagraph] @?= 1,
      testCase "an empty item followed by a trailing blank line is an error" $ do
        assertBool "- \\n is an error" (not (null (codes "- \n")))
        codes "- \n  " @?= codes "- \n",
      testCase "every grammar label has its own diagnostic code" $ do
        ls <- grammarLabels
        assertBool "table_row is a label" ("table_row" `elem` ls)
        let cs = map (fst . labelCode . Just) ls
        assertBool "no label falls back to G01029" ("G01029" `notElem` cs)
        sort (nub cs) @?= sort cs
        fst (labelCode (Just "table_row")) @?= "G01023",
      -- docs/adr ADR 0016
      testCase "a backslash at the end of a line is a hard break" $ do
        parseOk "a\\\nb\n"
        assertBool "a HardBreak node" (NHardBreak `elem` kinds (fst (parse fid "a\\\nb\n")))
        parseOk "a  \\\n  b\n"
        parseOk "- a\\\n  b\n",
      testCase "a hard break needs the next line of the paragraph" $
        mapM_ (\src -> assertEqual (show src) [DiagnosticCode "G01024"] (nub (codes src))) ["a\\\n\nb\n", "a\\\n", "a\\", "a\\\n# h\n"],
      testCase "headings, terms and cells have no hard breaks" $ do
        mapM_ (\src -> assertBool (show (src, codes src)) (DiagnosticCode "G01024" `elem` codes src)) ["# h\\\n", "= t\\\n  d\n"]
        -- a row that ends in a backslash is no row: the table is a block that cannot be parsed
        codes "| a\\\n|---|\n" @?= [DiagnosticCode "G01010"],
      testCase "a hard break in a prose slot is not a syntax error" $ do
        parseOk "[note: a\\\nb]\n"
        assertBool "a HardBreak node" (NHardBreak `elem` kinds (fst (parse fid "[note: a\\\nb]\n"))),
      testCase "hard_break has its code" $
        fst (labelCode (Just "hard_break")) @?= "G01024",
      -- golem-parser ADR 0010
      testGroup
        "a backslash after the last | of a table row (ADR 0010)"
        [ -- right after the backslash, where BadBreak reports it in a heading too ("# h\\" is at 4)
          testCase "in the header row: G01024 only, at the backslash" $ do
            parsed "| a | b |\\\n|---|---|\n| c | d |\n" @?= [(g "G01024", 10, 10)]
            parsed "# h\\\n" @?= [(g "G01024", 4, 4)],
          testCase "in a body row: G01024 only, and the table keeps its rows" $ do
            parsed "| a | b |\n|---|---|\n| c | d |\\\n| e | f |\n" @?= [(g "G01024", 30, 30)]
            map tableShape (astOf "| a | b |\n|---|---|\n| c | d |\\\n| e | f |\n")
              @?= map tableShape (astOf "| a | b |\n|---|---|\n| c | d |\n| e | f |\n"),
          testCase "on the last line without a newline" $
            parsed "| a | b |\n|---|---|\n| c | d |\\" @?= [(g "G01024", 30, 30)],
          testCase "a row without its last | is still G01015" $
            codes "| a | b |\n|---|---|\n| c | d \\\n" @?= [g "G01015"],
          testCase "the message is the one of the hard break" $
            messageOf "| a | b |\\\n|---|---|\n" (snd (labelCode (Just "hard_break")))
        ],
      codeTests,
      numberShorthandTests,
      reservedSyntaxTests,
      rangeTests
    ]

-- | The expression of [= src], without its spans.
rangeAst :: Text -> Golem.Parser.AST.Expr
rangeAst src = case astOf ("[= " <> src <> "]\n") of
  [Golem.Parser.AST.Located _ (Golem.Parser.AST.Paragraph [Golem.Parser.AST.Located _ (Golem.Parser.AST.Expr e)])] -> unspanned e
  other -> error (show other)
  where
    unspanned (Golem.Parser.AST.Located _ e) = case e of
      Golem.Parser.AST.ERange a b -> Golem.Parser.AST.ERange (at0 (unspanned a)) (at0 (unspanned b))
      Golem.Parser.AST.EBinary o a b -> Golem.Parser.AST.EBinary o (at0 (unspanned a)) (at0 (unspanned b))
      Golem.Parser.AST.EUnary o a -> Golem.Parser.AST.EUnary o (at0 (unspanned a))
      Golem.Parser.AST.EArray xs -> Golem.Parser.AST.EArray (map (at0 . unspanned) xs)
      other -> other

-- | A value at no position.
at0 :: a -> Golem.Parser.AST.Located a
at0 = Golem.Parser.AST.Located (mkSpan fid 0 0)

-- | The closed range a...b and the reserved .. (docs/adr ADR 0113).
rangeTests :: TestTree
rangeTests =
  testGroup
    "the range literal (docs/adr ADR 0113)"
    [ testCase "ranges parse" $
        mapM_ parseOk ["[= 1...10]\n", "[= 1.5...2]\n", "[= 1e-3...2]\n", "[= n...n + 4]\n", "[= -1...3]\n", "[= (1...3)]\n", "[= [3, 5...7]]\n", "[= (1...2) == (1...2)]\n", "[= a...b]\n", "[= meta.x...meta.y]\n", "@set r = 1...3\n"],
      -- The recovery of reserved skips the rest of the paragraph, the ] of
      -- [= ...] too, which is then G01017 (docs/adr ADR 0115).
      testCase ".. is G01100 from the .." $ do
        map (\(c, s, _) -> (c, s)) (parsed "[= 1..3]\n") @?= [(g "G01100", 4), (g "G01017", 8)]
        map (\(c, s, _) -> (c, s)) (parsed "[= a..b]\n") @?= [(g "G01100", 4), (g "G01017", 8)]
        map (\(c, s, _) -> (c, s)) (parsed "@set r = 1..3\n") @?= [(g "G01100", 10)]
        map (\(c, s, _) -> (c, s)) (parsed "[= ..5]\n") @?= [(g "G01100", 3), (g "G01017", 7)]
        map (\(c, s, _) -> (c, s)) (parsed "[= 5..]\n") @?= [(g "G01100", 4), (g "G01017", 7)],
      testCase "a range without an end, or with an end that cannot be read, is G02110" $
        mapM_ (\src -> (src, nub (codes src)) @?= (src, [g "G02110"])) ["[= 1....2]\n", "[= 1...2...3]\n", "[= 1...2..3]\n", "[= 5...]\n", "[= ...5]\n"],
      testCase "a comparison is no end, nor a range a side of a comparison" $ do
        codes "[= 1 < 2...3]\n" @?= [g "G01017"]
        codes "[= 1...2 == 1...2]\n" @?= [g "G01017"],
      testCase "the AST of a range" $ do
        let n = at0 . Golem.Parser.AST.ENat
            v x = at0 (Golem.Parser.AST.EVar x)
            r = Golem.Parser.AST.ERange
        rangeAst "1...10" @?= r (n 1) (n 10)
        rangeAst "1.5...2" @?= r (at0 (Golem.Parser.AST.ERat 1.5)) (n 2)
        rangeAst "1e-3...2" @?= r (at0 (Golem.Parser.AST.ERat 0.001)) (n 2)
        rangeAst "n...n + 4" @?= r (v ["n"]) (at0 (Golem.Parser.AST.EBinary Golem.Parser.AST.Add (v ["n"]) (n 4)))
        rangeAst "-1...3" @?= r (at0 (Golem.Parser.AST.EUnary Golem.Parser.AST.Negate (n 1))) (n 3)
        rangeAst "(1...3)" @?= r (n 1) (n 3)
        rangeAst "[3, 5...7]" @?= Golem.Parser.AST.EArray [n 3, at0 (r (n 5) (n 7))]
        rangeAst "(1...2) == (1...2)" @?= Golem.Parser.AST.EBinary Golem.Parser.AST.OpEq (at0 (r (n 1) (n 2))) (at0 (r (n 1) (n 2)))
        rangeAst "a...b" @?= r (v ["a"]) (v ["b"])
        rangeAst "meta.x...meta.y" @?= r (v ["meta", "x"]) (v ["meta", "y"]),
      testCase "literals and names without a range are as before" $ do
        rangeAst "1.5" @?= Golem.Parser.AST.ERat 1.5
        rangeAst "1e-3" @?= Golem.Parser.AST.ERat 0.001
        rangeAst "meta.title" @?= Golem.Parser.AST.EVar ["meta", "title"],
      testCase "range_end has its code" $
        fst (labelCode (Just "range_end")) @?= "G02110"
    ]

-- | The reserved syntax [! and @! (docs/adr ADR 0115).
reservedSyntaxTests :: TestTree
reservedSyntaxTests =
  testGroup
    "reserved syntax (docs/adr ADR 0115)"
    [ testCase "[! is G01100 from the [" $ do
        map (\(c, s, _) -> (c, s)) (parsed "a [!foo bar] b\n") @?= [(g "G01100", 2)]
        map (\(c, s, _) -> (c, s)) (parsed "a [!] b\n") @?= [(g "G01100", 2)]
        map (\(c, s, _) -> (c, s)) (parsed "[! x]\n") @?= [(g "G01100", 0)],
      testCase "[! in a heading, a prose slot, a cell and an argument" $ do
        map (\(c, s, _) -> (c, s)) (parsed "# 題 [!x]\n") @?= [(g "G01100", 6)]
        -- the recovery skips the ] of strong too, as for G01021 (the same SkipParagraph)
        map (\(c, s, _) -> (c, s)) (parsed "[strong: [!x]]\n") @?= [(g "G01100", 9), (g "G01017", 15)]
        map (\(c, _, _) -> c) (parsed "[strong: [A]]\n") @?= [g "G01021", g "G01017"]
        -- In a cell, the recovery of SkipParagraph reads past the end of the
        -- row, as it does for G01021: the table fails as a block.
        codes "| [!x] |\n|---|\n| a |\n" @?= codes "| [A] |\n|---|\n| a |\n"
        map (\(c, s, _) -> (c, s)) (parsed "@caption [!x]\n") @?= [(g "G01100", 9)],
      testCase "@! at the start of a block is G01100 from the @" $ do
        map (\(c, s, _) -> (c, s)) (parsed "@!foo\n") @?= [(g "G01100", 0)]
        map (\(c, s, _) -> (c, s)) (parsed "@note\n  @!foo\n") @?= [(g "G01100", 8)]
        map (\(c, s, _) -> (c, s)) (parsed "本文\n@!foo\n") @?= [(g "G01100", 7)]
        map (\(c, s, _) -> (c, s)) (parsed "@style x\n@!foo\n") @?= [(g "G01100", 9)],
      testCase "the message" $ do
        messageOf "a [!x] b\n" "予約された記法です。今のバージョンでは使えません"
        messageOf "@!foo\n" "予約された記法です。今のバージョンでは使えません",
      testCase "@! in the middle of a line, escapes, code, comments are text" $ do
        mapM_ parseOk ["a@!b\n", "\\[!x]\n", "\\@!foo\n", "```\n[!x]\n@!foo\n```\n", "a %% [!x] %%\n"]
        map inlinesOf (astOf "a@!b\n") @?= [[Golem.Parser.AST.Text "a@!b"]]
        map inlinesOf (astOf "\\[!x]\n") @?= [[Golem.Parser.AST.Escaped '[', Golem.Parser.AST.Text "!x]"]]
        map inlinesOf (astOf "\\@!foo\n") @?= [[Golem.Parser.AST.Escaped '@', Golem.Parser.AST.Text "!foo"]],
      testCase "[ followed by another character is still G01021" $
        codes "a [A] b\n" @?= [g "G01021"],
      testCase "reserved has its code" $
        labelCode (Just "reserved") @?= ("G01100", "予約された記法です。今のバージョンでは使えません")
    ]
  where
    inlinesOf (Golem.Parser.AST.Located _ b) = case b of
      Golem.Parser.AST.Paragraph is -> map Golem.Parser.AST.locValue is
      _ -> []

-- | The tokens of each ##…## of a source (golem-parser ADR 0011).
shorthandNodes :: Text -> [[(SyntaxKind, Text)]]
shorthandNodes src = go (fst (parse fid src))
  where
    go n
      | nodeKind n == NNumberShorthand = [[(tokKind t, tokText t) | ElemToken t <- nodeChildren n]]
      | otherwise = concat [go m | ElemNode m <- nodeChildren n]

-- | The kinds of the children of the first node of a kind, without whitespace.
childKindsOf :: SyntaxKind -> Text -> [SyntaxKind]
childKindsOf k src = case go (fst (parse fid src)) of
  (cs : _) -> cs
  [] -> []
  where
    go n
      | nodeKind n == k = [filter (/= KWhitespace) (map elemKind (nodeChildren n))]
      | otherwise = concat [go m | ElemNode m <- nodeChildren n]
    elemKind = \case
      ElemNode m -> nodeKind m
      ElemToken t -> tokKind t

numberShorthandTests :: TestTree
numberShorthandTests =
  testGroup
    "number shorthand ##…## (golem-parser ADR 0011)"
    [ testCase "in the middle of text" $ do
        parseOk "本文##12##本文\n"
        childKindsOf NParagraph "本文##12##本文\n" @?= [KText, NNumberShorthand, KText, KNewline]
        shorthandNodes "本文##12##本文\n" @?= [[(KNumberMark, "##"), (KNumberBody, "12"), (KNumberMark, "##")]],
      testCase "a line that starts with ##1## is a paragraph" $ do
        parseOk "##1##年\n"
        take 1 (childKindsOf NParagraph "##1##年\n") @?= [NNumberShorthand],
      testCase "a heading with a number in its title" $ do
        parseOk "## 第##1##節\n"
        case astOf "## 第##1##節\n" of
          [Golem.Parser.AST.Located _ (Golem.Parser.AST.Heading 2 is)] ->
            map Golem.Parser.AST.locValue is @?= [Golem.Parser.AST.Text "第", Golem.Parser.AST.NumberShorthand "##1##", Golem.Parser.AST.Text "節"]
          other -> assertFailure (show other),
      testCase "###1## and #1 are G01010, #### is G01012 as before" $ do
        codes "###1##\n" @?= [DiagnosticCode "G01010"]
        codes "#1\n" @?= [DiagnosticCode "G01010"]
        codes "#### x\n" @?= [DiagnosticCode "G01012"],
      testCase "the contents are not checked by the grammar" $ do
        mapM_ (\src -> (src, codes src, length (shorthandNodes src)) @?= (src, [], 1)) ["##0##\n", "##007##\n", "##1.5##\n", "##1,000##\n", "##1 2##\n", "##12年\n"]
        shorthandNodes "##12年\n" @?= [[(KNumberMark, "##"), (KNumberBody, "12年")]],
      testCase "the contents stop at | in a cell and a slot" $ do
        parseOk "| ##12|x |\n|---|---|\n| a | b |\n"
        shorthandNodes "| ##12|x |\n|---|---|\n| a | b |\n" @?= [[(KNumberMark, "##"), (KNumberBody, "12")]]
        parseOk "[ruby: ##12|じゅうに]\n"
        shorthandNodes "[ruby: ##12|じゅうに]\n" @?= [[(KNumberMark, "##"), (KNumberBody, "12")]],
      testCase "## not followed by an ASCII digit is text" $
        mapM_
          (\src -> (src, codes src, shorthandNodes src) @?= (src, [], []))
          ["C##\n", "a##]\n", "a####\n", "a##見出し##\n", "a##１２##\n", "a##-3##\n", "\\##1##\n"],
      testCase "in items, definitions, cells and slots" $
        mapM_
          (\src -> (src, codes src, length (shorthandNodes src)) @?= (src, [], 1))
          ["- ##1##つ目\n", "= ##1##\n  説明\n", "| ##1## | a |\n|---|---|\n| b | c |\n", "[ruby: ##12##|じゅうに]\n", "[note: ##1##]\n", "[code: ##1##]\n"],
      testCase "not in arguments, expressions, strings, comments and code blocks" $ do
        case astOf "[number-text ##1##]\n" of
          [Golem.Parser.AST.Located _ (Golem.Parser.AST.Paragraph [Golem.Parser.AST.Located _ (Golem.Parser.AST.Command _ [Golem.Parser.AST.Located _ a] _)])] ->
            a @?= Golem.Parser.AST.Positional (Golem.Parser.AST.Word "##1##")
          other -> assertFailure (show other)
        mapM_ (\src -> (src, shorthandNodes src) @?= (src, [])) ["[= \"##1##\"]\n", "a %% ##1## %%\n", "```\n##1##\n```\n"]
    ]

-- | (code, start, end) of each diagnostic.
located :: [Diagnostic] -> [(DiagnosticCode, Int, Int)]
located = map (\d -> (diagCode d, spanStart (diagSpan d), spanEnd (diagSpan d)))

g01019 :: Text
g01019 = "位置引数と *[...] は、key=value と **[...] より前に書きます"

parsed :: Text -> [(DiagnosticCode, Int, Int)]
parsed = located . snd . parse fid

readDiags :: BS.ByteString -> [Diagnostic]
readDiags = fromLeft [] . readSource fid

messageOf :: Text -> Text -> Assertion
messageOf src msg = map diagMessage (snd (parse fid src)) @?= [msg]

g :: Text -> DiagnosticCode
g = DiagnosticCode

-- | Codes, messages and positions of the syntax stage (golem-parser ADR 0009).
codeTests :: TestTree
codeTests =
  testGroup
    "syntax diagnostic codes (ADR 0009)"
    [ testCase "G01001 points at the first invalid byte" $ do
        located (readDiags "ab\xFF\n") @?= [(g "G01001", 2, 3)]
        map diagMessage (readDiags "ab\xFF\n") @?= ["UTF-8 として不正なバイト列があります"]
        located (readDiags "a\xE3\x81") @?= [(g "G01001", 1, 2)],
      testCase "G01002 for a BOM, checked before UTF-8 and CR" $ do
        located (readDiags (BS.pack [0xEF, 0xBB, 0xBF] <> TE.encodeUtf8 "本文\n")) @?= [(g "G01002", 0, 3)]
        map diagMessage (readDiags "\xEF\xBB\xBF\n") @?= ["ファイルの先頭に BOM があります。BOM を取り除いてください"]
        located (readDiags "\xEF\xBB\xBF\xFF\r\n") @?= [(g "G01002", 0, 3)],
      testCase "G01003 for CRLF and a lone CR, with a fix title" $ do
        mapM_
          ( \src -> do
              located (readDiags src) @?= [(g "G01003", 1, 2)]
              map (map fixTitle . diagFixes) (readDiags src) @?= [["golem fmt で LF に直す"]]
          )
          ["a\r\nb\r\n", "a\rb\n"],
      testCase "a BOM after the start is accepted" $
        readSource fid "a\n\xEF\xBB\xBF\&b\n" @?= Right "a\n\xFEFF\&b\n",
      testCase "checking a text gives the diagnostics of reading its bytes" $
        mapM_
          (\t -> checkText fid t @?= readDiags (TE.encodeUtf8 t))
          ["\xFEFF本文\n", "本文\r\n", "本文\n"],
      testCase "G01010" $ parsed "= a\n=:\n" @?= [(g "G01010", 0, 6)],
      testCase "G01011 starts at the extra space or tab, with its message" $ do
        map (\(c, s, _) -> (c, s)) (parsed "  二つ空け\n") @?= [(g "G01011", 0)]
        map (\(c, s, _) -> (c, s)) (parsed "- a\n\t- b\n") @?= [(g "G01011", 4)]
        messageOf "  二つ空け\n" "インデントが不正です（タブ、またはブロックの深さより多い空白）",
      testCase "three spaces continue an item" $ parsed "- a\n   - b\n" @?= [],
      testCase "G01012 starts at the fourth #" $ map (\(c, s, _) -> (c, s)) (parsed "#### x\n") @?= [(g "G01012", 3)],
      testCase "G01013 starts at =:" $ map (\(c, s, _) -> (c, s)) (parsed "=:\n  説明\n") @?= [(g "G01013", 0)],
      testCase "G01014 starts at the second line" $ do
        map (\(c, s, _) -> (c, s)) (parsed "| a |\n") @?= [(g "G01014", 6)]
        map (\(c, s, _) -> (c, s)) (parsed "| a |\nx\n") @?= [(g "G01014", 6)],
      testCase "G01015 at the end of the row" $ parsed "| a |\n|---|\n| 1 | 2 |\n" @?= [(g "G01015", 21, 21)],
      testCase "G01016 at the end of the file" $ parsed "```\nx\n" @?= [(g "G01016", 6, 6)],
      testCase "G01017 where ] is wanted, with its message" $ do
        map (\(c, s, _) -> (c, s)) (parsed "[= 1 ? 2]\n") @?= [(g "G01017", 5)]
        messageOf "[= 1 ? 2]\n" "ここに閉じ括弧 ] が必要です"
        let twice = parsed "[f *[x y]]\n"
        map (\(c, _, _) -> c) twice @?= [g "G01017", g "G01017"]
        assertBool "different positions" (nub twice == twice),
      testCase "G01018 at the end of the paragraph" $ do
        parsed "本文 %% x\n\n次\n" @?= [(g "G01018", 11, 11)]
        parsed "# 見出し %% x\n\n次\n" @?= [(g "G01018", 16, 16)],
      testCase "G01019" $ do
        parsed "[f a=1 b]\n" @?= [(g "G01019", 6, 8)]
        messageOf "[f a=1 b]\n" g01019,
      -- golem-parser ADR 0013
      testCase "**[...] may follow keyword arguments" $ do
        parsed "[f k=v **[h]]\n" @?= []
        parsed "[f k=1 **[h] j=2 **[i]]\n" @?= [],
      testCase "the same key twice is left to evaluation" $ parsed "[f k=1 k=2]\n" @?= [],
      testCase "a positional argument after **[...] is G01019" $ do
        parsed "[f **[h] x]\n" @?= [(g "G01019", 8, 10)]
        messageOf "[f **[h] x]\n" g01019,
      testCase "*[...] after **[...] is G01019" $ parsed "[f **[h] *[g]]\n" @?= [(g "G01019", 8, 13)],
      testCase "**[...] after keyword arguments on block and code lines" $ do
        parsed "@b k=v **[h]\n" @?= []
        parsed "``` text k=v **[h]\ncode\n```\n" @?= [],
      testCase "G01020 where an expression is wanted" $ do
        parsed "[=]\n" @?= [(g "G01020", 2, 2)]
        parsed "[= ]\n" @?= [(g "G01020", 3, 3)]
        parsed "@set x = +\n" @?= [(g "G01020", 9, 10)]
        sort (parsed "本文 [=\n") @?= [(g "G01017", 9, 9), (g "G01020", 9, 9)],
      testCase "G01021 starts at [" $ do
        map (\(c, s, _) -> (c, s)) (parsed "本文 [ だけ\n") @?= [(g "G01021", 7)]
        map (\(c, s, _) -> (c, s)) (parsed "[A]\n") @?= [(g "G01021", 0)],
      testCase "G01022 and G01029" $ do
        labelCode Nothing @?= ("G01022", "解釈できない入力が残っています")
        labelCode (Just "nonexistent") @?= ("G01029", "構文エラー（nonexistent）")
    ]
