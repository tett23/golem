module LowerSpec (tests) where

import Data.Text (Text)
import Golem.Parser
import Golem.Parser.AST
import Golem.Parser.CST
import Golem.Parser.Lower (lower)
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

fid :: FileId
fid = FileId 0

ast :: Text -> [Block]
ast src = let (File _ bs, _, _) = parseAst fid src in map locValue bs

inl :: [Located Inline] -> [Inline]
inl = map locValue

paraTexts :: Text -> [[Inline]]
paraTexts src = [inl is | Paragraph is <- ast src]

-- | The paragraphs with their escapes made text (golem-parser ADR 0010).
plainParas :: Text -> [[Inline]]
plainParas src = [inl (plainEscapes is) | Paragraph is <- ast src]

stripE :: Located Expr -> Expr
stripE (Located _ e) = case e of
  EBinary o a b -> EBinary o (Located dummy (stripE a)) (Located dummy (stripE b))
  EUnary o a -> EUnary o (Located dummy (stripE a))
  other -> other
  where
    dummy = mkSpan fid 0 0

exprOf :: Text -> Expr
exprOf src = case paraTexts src of
  [[Expr e]] -> stripE e
  other -> error (show other)

-- | The AST without spans, for comparing sources that differ only in position.
shape :: Text -> String
shape src = erase (show (ast src))
  where
    erase t = case breakOn "SrcSpan {" t of
      (pre, "") -> pre
      (pre, rest) -> pre <> erase (drop 1 (dropWhile (/= '}') rest))
    breakOn pat = go ""
      where
        go acc rest@(c : cs)
          | take (length pat) rest == pat = (reverse acc, rest)
          | otherwise = go (c : acc) cs
        go acc [] = (reverse acc, "")

whitespaceTests :: TestTree
whitespaceTests =
  testGroup
    "insignificant whitespace (ADR 0006)"
    [ testCase "trailing whitespace of lines is dropped" $ do
        shape "本文。  \n続き\t\n" @?= shape "本文。\n続き\n"
        shape "# 見出し   \n" @?= shape "# 見出し\n"
        paraTexts "word  \n" @?= [[Text "word"]],
      testCase "table cell edges" $
        shape "| a|b |\n|---|---|\n| 1 | 2|\n" @?= shape "| a | b |\n|---|---|\n| 1 | 2 |\n",
      testCase "the end of prose slots" $
        shape "[ruby 漢字: かん | じ]\n" @?= shape "[ruby 漢字: かん|じ]\n",
      testCase "escaped and ideographic spaces stay" $ do
        plainParas "a\\ \n" @?= [[Text "a "]]
        paraTexts "a\x3000\n" @?= [[Text "a\x3000"]]
        shape "| \\ a |\n|---|\n" /= shape "| a |\n|---|\n" @?= True
    ]

-- | golem-parser ADR 0010.
escapeTests :: TestTree
escapeTests =
  testGroup
    "escaped characters stay in the AST (ADR 0010)"
    [ testCase "an escape is Escaped, and the text around it is not joined to it" $
        paraTexts "\\# 見出しではない \\[ x \\\\\n" @?= [[Escaped '#', Text " 見出しではない ", Escaped '[', Text " x ", Escaped '\\']],
      testCase "\\/ in the base of a ruby, with the span of its two bytes" $ case ast "[ruby: a\\/b|えー]\n" of
        [Paragraph [Located _ (Command _ [] [base, reading])]] -> do
          inl base @?= [Text "a", Escaped '/', Text "b"]
          [(spanStart sp, spanEnd sp) | Located sp (Escaped _) <- base] @?= [(8, 10)]
          inl reading @?= [Text "えー"]
        other -> assertFailure (show other),
      testCase "the name of the command does not matter" $ case paraTexts "[bold: a\\/b]\n" of
        [[Command _ [] [slot]]] -> inl slot @?= [Text "a", Escaped '/', Text "b"]
        other -> assertFailure (show other),
      testCase "\\%% is an escaped % and a text %" $
        paraTexts "a\\%%b\n" @?= [[Text "a", Escaped '%', Text "%b"]],
      testCase "plainEscapes gives what the escapes were before" $ do
        plainParas "\\# 見出しではない \\[ x \\\\\n" @?= [[Text "# 見出しではない [ x \\"]]
        plainParas "a\\%%b\n" @?= [[Text "a%%b"]]
        plainParas "[bold: a\\/b]\n" @?= paraTexts "[bold: a\\/b]\n",
      testCase "plainEscapes joins the spans as the text did" $ case ast "x\\[y\n" of
        [Paragraph is] -> plainEscapes is @?= [Located (mkSpan fid 0 4) (Text "x[y")]
        other -> assertFailure (show other),
      testCase "plainEscapesIn makes only the characters that match text, in the whole file" $ do
        let (f, _, _) = parseAst fid "\\あ\\/[bold: \\い\\/]\n"
            File _ bs1 = plainEscapesIn (== 'あ') f
            File _ bs2 = plainEscapesIn (== 'い') f
        case map locValue bs1 of
          [Paragraph is] -> take 2 (inl is) @?= [Text "あ", Escaped '/']
          other -> assertFailure (show other)
        case map locValue bs2 of
          [Paragraph [_, _, Located _ (Command _ _ [slot])]] -> inl slot @?= [Text "い", Escaped '/']
          other -> assertFailure (show other)
    ]

tests :: TestTree
tests =
  testGroup
    "CST to AST (ADR 0005)"
    [ whitespaceTests,
      testGroup
        "newlines in a paragraph become SoftBreak (docs/adr ADR 0003)"
        [ testCase "a paragraph" $
            paraTexts "a\nb\n" @?= [[Text "a", SoftBreak, Text "b"]],
          testCase "whitespace before the newline is dropped" $
            paraTexts "a  \nb\n" @?= [[Text "a", SoftBreak, Text "b"]],
          testCase "a prose slot" $ case paraTexts "[note: a\nb]\n" of
            [[Command _ [] [slot]]] -> inl slot @?= [Text "a", SoftBreak, Text "b"]
            other -> assertFailure (show other),
          testCase "Japanese text is not joined by the parser" $
            paraTexts "吾輩は猫である。\n名前はまだ無い。\n" @?= [[Text "吾輩は猫である。", SoftBreak, Text "名前はまだ無い。"]],
          testCase "the body of @verse" $ case ast "@verse\n  A\n  B\n\n  C\n" of
            [BlockCommand n [] [Located _ (Paragraph p1), Located _ (Paragraph p2)]] -> do
              locValue n @?= "verse"
              inl p1 @?= [Text "A", SoftBreak, Text "B"]
              inl p2 @?= [Text "C"]
            other -> assertFailure (show other)
        ],
      testGroup
        "hard breaks (docs/adr ADR 0016)"
        [ testCase "a backslash at the end of a line" $
            paraTexts "a\\\nb\n" @?= [[Text "a", HardBreak, Text "b"]],
          testCase "spaces and tabs around it are not text; the ideographic space is" $ do
            paraTexts "a  \\\n  b\n" @?= [[Text "a", HardBreak, Text "b"]]
            paraTexts "a\t\\\n\tb\n" @?= [[Text "a", HardBreak, Text "b"]]
            paraTexts "a\\\n\x3000\&b\n" @?= [[Text "a", HardBreak, Text "\x3000\&b"]],
          testCase "an escaped space is not a hard break" $
            plainParas "a\\ \nb\n" @?= [[Text "a ", SoftBreak, Text "b"]],
          testCase "an escaped backslash is not a hard break" $
            plainParas "a\\\\\nb\n" @?= [[Text "a\\", SoftBreak, Text "b"]],
          testCase "a hard break in a prose slot stays in the slot" $ case paraTexts "[note: a\\\nb]\n" of
            [[Command _ [] [slot]]] -> inl slot @?= [Text "a", HardBreak, Text "b"]
            other -> assertFailure (show other),
          testCase "a hard break at the start of a paragraph stays" $
            paraTexts "\\\na\n" @?= [[HardBreak, Text "a"]],
          testCase "the span is from the backslash to the end of the newline" $ case ast "a\\\nb\n" of
            [Paragraph [_, Located sp HardBreak, _]] -> (spanStart sp, spanEnd sp) @?= (1, 3)
            other -> assertFailure (show other)
        ],
      escapeTests,
      testCase "comments vanish, proofreading comments stay" $
        paraTexts "本文。%% 消える %%続き。%%= 校正 %%\n" @?= [[Text "本文。続き。", ProofComment "校正"]],
      testCase "a paragraph of only a comment is dropped" $
        ast "%% メモ %%\n\n本文。\n" @?= [Paragraph [Located (mkSpan fid 14 23) (Text "本文。")]],
      testCase "heading level" $ case ast "## 節の題\n" of
        [Heading 2 is] -> inl is @?= [Text "節の題"]
        other -> assertFailure (show other),
      testCase "operator precedence" $ do
        let lit = Located (mkSpan fid 0 0) . EInt
        exprOf "[= -2 ** 2]\n" @?= EUnary Negate (Located (mkSpan fid 0 0) (EBinary Pow (lit 2) (lit 2)))
        exprOf "[= 1 - 2 - 3]\n" @?= EBinary Sub (Located (mkSpan fid 0 0) (EBinary Sub (lit 1) (lit 2))) (lit 3)
        exprOf "[= 2 ** 3 ** 2]\n" @?= EBinary Pow (lit 2) (Located (mkSpan fid 0 0) (EBinary Pow (lit 3) (lit 2))),
      testCase "literals" $ do
        exprOf "[= 2.675]\n" @?= EFloat 2.675
        exprOf "[= \"a\\\"b\"]\n" @?= EString "a\"b"
        exprOf "[= nil]\n" @?= ENil,
      testCase "commands with arguments and slots" $ case paraTexts "[number-text 10 style=tcy][ruby: 東/京|とう/きょう]\n" of
        [[Command n1 a1 [], Command n2 [] [s1, s2]]] -> do
          locValue n1 @?= "number-text"
          map locValue a1 @?= [Positional (Word "10"), Keyword (Located (mkSpan fid 16 21) "style") (Word "tcy")]
          locValue n2 @?= "ruby"
          (inl s1, inl s2) @?= ([Text "東/京"], [Text "とう/きょう"])
        other -> assertFailure (show other),
      testCase "set and attributed blocks" $ case ast "@set price = 100\n\n@label intro\n@nonumber\n# はじめに\n" of
        [SetVar n _, Attributed cmds (Just (Located _ (Heading 1 _)))] -> do
          locValue n @?= "price"
          length cmds @?= 2
        other -> assertFailure (show other),
      testCase "lists with nesting" $ case ast "- a\n- b\n  - c\n" of
        [BulletList [[Located _ (Paragraph _)], [Located _ (Paragraph _), Located _ (BulletList [_])]]] -> pure ()
        other -> assertFailure (show other),
      testCase "definition list groups" $ case ast "= A\n= B\n  共有。\n=:\n  二つ目。\n" of
        [DefList [DefGroup ts ds]] -> (length ts, length ds) @?= (2, 2)
        other -> assertFailure (show other),
      testCase "table alignments" $ case ast "| a | b | c |\n|:---|:---:|---:|\n| 1 | 2 | 3 |\n" of
        [Table al h [r]] -> (al, length h, length r) @?= ([AlignLeft, AlignCenter, AlignRight], 3, 3)
        other -> assertFailure (show other),
      testCase "code block content" $
        ast "- x\n\n  ```hs\n  a\n    b\n  ```\n" @?= ast "- x\n\n  ```hs\n  a\n    b\n  ```\n",
      testCase "code block in item strips indentation" $ case ast "```hs\na\n  b\n```\n" of
        [CodeBlock l c] -> (l, c) @?= (Just "hs", "a\n  b")
        other -> assertFailure (show other),
      testCase "figure caption becomes the command body" $ case ast "@figure a.png alt=\"x\"\n  キャプション。\n" of
        [BlockCommand n args [Located _ (Paragraph _)]] -> (locValue n, length args) @?= ("figure", 2)
        other -> assertFailure (show other),
      -- golem-parser ADR 0009
      testCase "an expression slot with no expression is an error at the slot" $ do
        let cst = node NFile [ElemToken (Token KText "ab"), ElemNode (node NParagraph [ElemNode (node NExpr [token KExprOpen "[=", token KRBracket "]"])]), token KNewline "\n"]
            other = FileId 3
        case map locValue (fileBlocks (lower other cst)) of
          [Paragraph [Located _ (Expr (Located sp EError))]] -> sp @?= mkSpan other 2 2
          bs -> assertFailure (show bs)
    ]
