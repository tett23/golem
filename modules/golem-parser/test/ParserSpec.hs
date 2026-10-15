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
  g <- TIO.readFile "grammar/Golem.hpeg"
  pure [l | ("%recover" : l : _) <- map T.words (T.lines g)]

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
      testCase "figure with caption body" $
        parseOk "@label fig-arch\n@figure images/arch.pdf web=images/arch.png alt=\"構成図\"\n  構成図のキャプション。\n",
      testCase "expressions" $ parseOk "[= -2 ** 2] [= round(2.675, 2)] [= [1, 2]] [= {a: 1, \"b\": true}] [= values.price >= 10]\n",
      testCase "splat and keyword arguments" $ parseOk "[number-text 10 style=tcy] [f *[xs] **[kw]: 本文 | 二つ目]\n",
      testCase "escapes" $ parseOk "\\# 見出しではない \\[ 50% \\\\\n",
      testCase "unclosed bracket is local to its paragraph" $ do
        let src = "前の段落。\n\n壊れた[strong: 段落\n\n後の段落。\n"
            (cst, ds) = parse fid src
        render cst @?= src
        map diagCode ds @?= [DiagnosticCode "G0117"]
        length [() | ElemNode n <- nodeChildren cst, nodeKind n == NParagraph] @?= 3,
      testCase "a bare bracket is an error" $ do
        let (_, ds) = parse fid "本文 [ だけ\n"
        map diagCode ds @?= [DiagnosticCode "G0121"],
      testCase "heading level four is an error and the next block survives" $ do
        let (cst, ds) = parse fid "#### 深すぎる\n\n# 正しい\n"
        map diagCode ds @?= [DiagnosticCode "G0112"]
        assertBool "heading parsed" (NHeading `elem` kinds cst),
      testCase "tab indentation is an error" $ do
        let (_, ds) = parse fid "- a\n\t- b\n"
        map diagCode ds @?= [DiagnosticCode "G0111"],
      testCase "odd indentation at top level is an error" $ do
        let (_, ds) = parse fid " 一つ空けた段落\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G0111"],
      testCase "orphan =: is an error" $ do
        let (_, ds) = parse fid "=:\n  説明\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G0113"],
      testCase "unclosed comment" $ do
        let (_, ds) = parse fid "本文 %% 閉じない\n\n次。\n"
        map diagCode ds @?= [DiagnosticCode "G0118"],
      testCase "positional after keyword" $ do
        let (_, ds) = parse fid "[f a=1 b]\n"
        map diagCode ds @?= [DiagnosticCode "G0119"],
      testCase "mismatched table cells" $ do
        let (_, ds) = parse fid "| a | b |\n|---|---|\n| 1 |\n"
        map diagCode ds @?= [DiagnosticCode "G0115"],
      testCase "unclosed code block" $ do
        let (_, ds) = parse fid "```\nx\n"
        map diagCode ds @?= [DiagnosticCode "G0116"],
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
        nub (codes "[f *[x y]]\n") @?= [DiagnosticCode "G0117"]
        codes "[f *[= 1]]\n" @?= [DiagnosticCode "G0120"]
        codes "[f **[= 1]]\n" @?= [DiagnosticCode "G0120"]
        parseOk "[f * x]\n",
      testCase "a line starting with | that is not a table row" $ do
        codes "| a |\n|---|\n|abc\n" @?= [DiagnosticCode "G0123"]
        let (cst, ds) = parse fid "| a |\n|---|\n|abc\n\n次の段落。\n"
        map diagCode ds @?= [DiagnosticCode "G0123"]
        length [() | ElemNode n <- nodeChildren cst, nodeKind n == NParagraph] @?= 1,
      testCase "an empty item followed by a trailing blank line is an error" $ do
        assertBool "- \\n is an error" (not (null (codes "- \n")))
        codes "- \n  " @?= codes "- \n",
      testCase "every grammar label has its own diagnostic code" $ do
        ls <- grammarLabels
        assertBool "table_row is a label" ("table_row" `elem` ls)
        let cs = map (fst . labelCode . Just) ls
        assertBool "no label falls back to G0129" ("G0129" `notElem` cs)
        sort (nub cs) @?= sort cs
        fst (labelCode (Just "table_row")) @?= "G0123",
      -- docs/adr ADR 0016
      testCase "a backslash at the end of a line is a hard break" $ do
        parseOk "a\\\nb\n"
        assertBool "a HardBreak node" (NHardBreak `elem` kinds (fst (parse fid "a\\\nb\n")))
        parseOk "a  \\\n  b\n"
        parseOk "- a\\\n  b\n",
      testCase "a hard break needs the next line of the paragraph" $
        mapM_ (\src -> assertEqual (show src) [DiagnosticCode "G0124"] (nub (codes src))) ["a\\\n\nb\n", "a\\\n", "a\\", "a\\\n# h\n"],
      testCase "headings, terms and cells have no hard breaks" $ do
        mapM_ (\src -> assertBool (show (src, codes src)) (DiagnosticCode "G0124" `elem` codes src)) ["# h\\\n", "= t\\\n  d\n"]
        -- a row that ends in a backslash is no row: the table is a block that cannot be parsed
        codes "| a\\\n|---|\n" @?= [DiagnosticCode "G0110"],
      testCase "a hard break in a prose slot is not a syntax error" $ do
        parseOk "[note: a\\\nb]\n"
        assertBool "a HardBreak node" (NHardBreak `elem` kinds (fst (parse fid "[note: a\\\nb]\n"))),
      testCase "hard_break has its code" $
        fst (labelCode (Just "hard_break")) @?= "G0124",
      -- golem-parser ADR 0010
      testGroup
        "a backslash after the last | of a table row (ADR 0010)"
        [ -- right after the backslash, where BadBreak reports it in a heading too ("# h\\" is at 4)
          testCase "in the header row: G0124 only, at the backslash" $ do
            parsed "| a | b |\\\n|---|---|\n| c | d |\n" @?= [(g "G0124", 10, 10)]
            parsed "# h\\\n" @?= [(g "G0124", 4, 4)],
          testCase "in a body row: G0124 only, and the table keeps its rows" $ do
            parsed "| a | b |\n|---|---|\n| c | d |\\\n| e | f |\n" @?= [(g "G0124", 30, 30)]
            map tableShape (astOf "| a | b |\n|---|---|\n| c | d |\\\n| e | f |\n")
              @?= map tableShape (astOf "| a | b |\n|---|---|\n| c | d |\n| e | f |\n"),
          testCase "on the last line without a newline" $
            parsed "| a | b |\n|---|---|\n| c | d |\\" @?= [(g "G0124", 30, 30)],
          testCase "a row without its last | is still G0115" $
            codes "| a | b |\n|---|---|\n| c | d \\\n" @?= [g "G0115"],
          testCase "the message is the one of the hard break" $
            messageOf "| a | b |\\\n|---|---|\n" (snd (labelCode (Just "hard_break")))
        ],
      codeTests
    ]

-- | (code, start, end) of each diagnostic.
located :: [Diagnostic] -> [(DiagnosticCode, Int, Int)]
located = map (\d -> (diagCode d, spanStart (diagSpan d), spanEnd (diagSpan d)))

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
    [ testCase "G0101 points at the first invalid byte" $ do
        located (readDiags "ab\xFF\n") @?= [(g "G0101", 2, 3)]
        map diagMessage (readDiags "ab\xFF\n") @?= ["UTF-8 として不正なバイト列があります"]
        located (readDiags "a\xE3\x81") @?= [(g "G0101", 1, 2)],
      testCase "G0102 for a BOM, checked before UTF-8 and CR" $ do
        located (readDiags (BS.pack [0xEF, 0xBB, 0xBF] <> TE.encodeUtf8 "本文\n")) @?= [(g "G0102", 0, 3)]
        map diagMessage (readDiags "\xEF\xBB\xBF\n") @?= ["ファイルの先頭に BOM があります。BOM を取り除いてください"]
        located (readDiags "\xEF\xBB\xBF\xFF\r\n") @?= [(g "G0102", 0, 3)],
      testCase "G0103 for CRLF and a lone CR, with a fix title" $ do
        mapM_
          ( \src -> do
              located (readDiags src) @?= [(g "G0103", 1, 2)]
              map (map fixTitle . diagFixes) (readDiags src) @?= [["golem fmt で LF に直す"]]
          )
          ["a\r\nb\r\n", "a\rb\n"],
      testCase "a BOM after the start is accepted" $
        readSource fid "a\n\xEF\xBB\xBF\&b\n" @?= Right "a\n\xFEFF\&b\n",
      testCase "checkText gives what readSource gives" $
        mapM_
          (\t -> checkText fid t @?= readDiags (TE.encodeUtf8 t))
          ["\xFEFF本文\n", "本文\r\n", "本文\n"],
      testCase "G0110" $ parsed "= a\n=:\n" @?= [(g "G0110", 0, 6)],
      testCase "G0111 starts at the extra space or tab, with its message" $ do
        map (\(c, s, _) -> (c, s)) (parsed "  二つ空け\n") @?= [(g "G0111", 0)]
        map (\(c, s, _) -> (c, s)) (parsed "- a\n\t- b\n") @?= [(g "G0111", 4)]
        messageOf "  二つ空け\n" "インデントが不正です（タブ、またはブロックの深さより多い空白）",
      testCase "three spaces continue an item" $ parsed "- a\n   - b\n" @?= [],
      testCase "G0112 starts at the fourth #" $ map (\(c, s, _) -> (c, s)) (parsed "#### x\n") @?= [(g "G0112", 3)],
      testCase "G0113 starts at =:" $ map (\(c, s, _) -> (c, s)) (parsed "=:\n  説明\n") @?= [(g "G0113", 0)],
      testCase "G0114 starts at the second line" $ do
        map (\(c, s, _) -> (c, s)) (parsed "| a |\n") @?= [(g "G0114", 6)]
        map (\(c, s, _) -> (c, s)) (parsed "| a |\nx\n") @?= [(g "G0114", 6)],
      testCase "G0115 at the end of the row" $ parsed "| a |\n|---|\n| 1 | 2 |\n" @?= [(g "G0115", 21, 21)],
      testCase "G0116 at the end of the file" $ parsed "```\nx\n" @?= [(g "G0116", 6, 6)],
      testCase "G0117 where ] is wanted, with its message" $ do
        map (\(c, s, _) -> (c, s)) (parsed "[= 1 ? 2]\n") @?= [(g "G0117", 5)]
        messageOf "[= 1 ? 2]\n" "ここに閉じ括弧 ] が必要です"
        let twice = parsed "[f *[x y]]\n"
        map (\(c, _, _) -> c) twice @?= [g "G0117", g "G0117"]
        assertBool "different positions" (nub twice == twice),
      testCase "G0118 at the end of the paragraph" $ do
        parsed "本文 %% x\n\n次\n" @?= [(g "G0118", 11, 11)]
        parsed "# 見出し %% x\n\n次\n" @?= [(g "G0118", 16, 16)],
      testCase "G0119" $ parsed "[f a=1 b]\n" @?= [(g "G0119", 6, 8)],
      testCase "G0120 where an expression is wanted" $ do
        parsed "[=]\n" @?= [(g "G0120", 2, 2)]
        parsed "[= ]\n" @?= [(g "G0120", 3, 3)]
        parsed "@set x = +\n" @?= [(g "G0120", 9, 10)]
        sort (parsed "本文 [=\n") @?= [(g "G0117", 9, 9), (g "G0120", 9, 9)],
      testCase "G0121 starts at [" $ do
        map (\(c, s, _) -> (c, s)) (parsed "本文 [ だけ\n") @?= [(g "G0121", 7)]
        map (\(c, s, _) -> (c, s)) (parsed "[A]\n") @?= [(g "G0121", 0)],
      testCase "G0122 and G0129" $ do
        labelCode Nothing @?= ("G0122", "解釈できない入力が残っています")
        labelCode (Just "nonexistent") @?= ("G0129", "構文エラー（nonexistent）")
    ]
