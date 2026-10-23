{- | The whole AST, without spans, of the sources the parser tests only
check for diagnostics. A parser that drops, reorders or misreads a
construct gives a different tree.
-}
module AstShapeSpec (tests) where

import Data.Text (Text)
import Golem.Parser
import Golem.Parser.AST
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

fid :: FileId
fid = FileId 0

-- | Every span of the tree is this one.
noSpan :: SrcSpan
noSpan = mkSpan fid 0 0

l :: a -> Located a
l = Located noSpan

-- | The blocks of a source with every span set to 'noSpan'; the source must have no diagnostics.
blocksOf :: Text -> IO [Block]
blocksOf src = do
  let (File _ bs, _, ds) = parseAst fid src
  map diagCode ds @?= []
  pure (map (block . locValue) bs)

unspan :: (a -> b) -> Located a -> Located b
unspan f (Located _ a) = Located noSpan (f a)

block :: Block -> Block
block = \case
  Paragraph is -> Paragraph (inlines is)
  Heading n is -> Heading n (inlines is)
  BulletList items -> BulletList (map (map (unspan block)) items)
  OrderedList items -> OrderedList (map (map (unspan block)) items)
  DefList gs -> DefList [DefGroup (map inlines ts) (map (map (unspan block)) ds) | DefGroup ts ds <- gs]
  Table al h rows -> Table al (map inlines h) (map (map inlines) rows)
  CodeBlock lang args ls -> CodeBlock lang (map (unspan argument) args) (map (unspan id) ls)
  SetVar n e -> SetVar (unspan id n) (unspan expr e)
  BlockCommand n args body -> BlockCommand (unspan id n) (map (unspan argument) args) (map (unspan block) body)
  Attributed as b -> Attributed (map (unspan block) as) (fmap (unspan block) b)
  ErrorBlock -> ErrorBlock

inlines :: [Located Inline] -> [Located Inline]
inlines = map (unspan inline)

inline :: Inline -> Inline
inline = \case
  Expr e -> Expr (unspan expr e)
  Command n args slots -> Command (unspan id n) (map (unspan argument) args) (map inlines slots)
  other -> other

argument :: Argument -> Argument
argument = \case
  Positional v -> Positional (argValue v)
  Keyword k v -> Keyword (unspan id k) (argValue v)
  SplatPositional e -> SplatPositional (unspan expr e)
  SplatKeyword e -> SplatKeyword (unspan expr e)

argValue :: ArgValue -> ArgValue
argValue = \case
  ExprArg e -> ExprArg (unspan expr e)
  CommandArg i -> CommandArg (unspan inline i)
  other -> other

expr :: Expr -> Expr
expr = \case
  EArray es -> EArray (map (unspan expr) es)
  EHash kvs -> EHash [(k, unspan expr v) | (k, v) <- kvs]
  ECall f es -> ECall f (map (unspan expr) es)
  EUnary o e -> EUnary o (unspan expr e)
  EBinary o a b -> EBinary o (unspan expr a) (unspan expr b)
  other -> other

para :: [Inline] -> Block
para = Paragraph . map l

txt :: Text -> Located Inline
txt = l . Text

cmd :: Text -> [Argument] -> [[Located Inline]] -> Located Inline
cmd n args = l . Command (l n) (map l args)

int :: Integer -> Located Expr
int = l . EInt

bin :: BinaryOp -> Located Expr -> Located Expr -> Located Expr
bin o a b = l (EBinary o a b)

shapeOf :: Text -> [Block] -> Assertion
shapeOf src expected = blocksOf src >>= (@?= expected)

tests :: TestTree
tests =
  testGroup
    "the whole AST of a source (ADR 0002-0005)"
    [ testCase "paragraphs and inline commands" $
        shapeOf
          "Golem は[ruby: 組/版|くみ/はん]の結果を出力する[note: 決定性。]。\n本書は第[= version]版である。\n%% 図 %%\n"
          [ Paragraph
              [ txt "Golem は",
                cmd "ruby" [] [[txt "組/版"], [txt "くみ/はん"]],
                txt "の結果を出力する",
                cmd "note" [] [[txt "決定性。"]],
                txt "。",
                l SoftBreak,
                txt "本書は第",
                l (Expr (l (EVar ["version"]))),
                -- the line of only a comment adds no break
                txt "版である。"
              ]
          ],
      testCase "headings" $
        shapeOf "# はじめに\n\n## 節\n\n### 項\n" [Heading 1 [txt "はじめに"], Heading 2 [txt "節"], Heading 3 [txt "項"]],
      testCase "attributes and block commands" $
        shapeOf
          "@import common/values.gm as values\n@set version = \"1.0\"\n\n@label intro\n@nonumber\n# はじめに\n\n本文。\n"
          [ -- lines of commands without a block after them are a group without a target
            Attributed
              [ l (BlockCommand (l "import") (map l [Positional (Word "common/values.gm"), Positional (Word "as"), Positional (Word "values")]) []),
                l (SetVar (l "version") (l (EString "1.0")))
              ]
              Nothing,
            Attributed
              [l (BlockCommand (l "label") [l (Positional (Word "intro"))] []), l (BlockCommand (l "nonumber") [] [])]
              (Just (l (Heading 1 [txt "はじめに"]))),
            para [Text "本文。"]
          ],
      testCase "lists" $
        shapeOf
          "- 印刷用の PDF\n- 電子書籍\n  - EPUB\n  - HTML\n\n+ 一\n+ 二\n"
          [ BulletList
              [ [l (para [Text "印刷用の PDF"])],
                [l (para [Text "電子書籍"]), l (BulletList [[l (para [Text "EPUB"])], [l (para [Text "HTML"])]])]
              ],
            OrderedList [[l (para [Text "一"])], [l (para [Text "二"])]]
          ],
      testCase "definition lists" $
        shapeOf
          "= 決定性\n  同じ入力から同じ出力を得る性質。\n\n= HTTP\n= HyperText Transfer Protocol\n  共有する。\n\n= モナド\n  圏論。\n=:\n  プログラミング。\n"
          [ DefList
              [ DefGroup [[txt "決定性"]] [[l (para [Text "同じ入力から同じ出力を得る性質。"])]],
                DefGroup [[txt "HTTP"], [txt "HyperText Transfer Protocol"]] [[l (para [Text "共有する。"])]],
                DefGroup [[txt "モナド"]] [[l (para [Text "圏論。"])], [l (para [Text "プログラミング。"])]]
              ]
          ],
      testCase "tables" $
        shapeOf
          "| 形式 | 用途 |\n|:---|---:|\n| PDF | 印刷 |\n| EPUB | 電子書籍 |\n"
          [Table [AlignLeft, AlignRight] [[txt "形式"], [txt "用途"]] [[[txt "PDF"], [txt "印刷"]], [[txt "EPUB"], [txt "電子書籍"]]]],
      testCase "a table without alignment marks" $
        shapeOf "| a | b |\n|---|---|\n| 1 | 2 |\n" [Table [AlignDefault, AlignDefault] [[txt "a"], [txt "b"]] [[[txt "1"], [txt "2"]]]],
      testCase "code blocks keep their content raw" $
        shapeOf "```haskell\nmain = putStrLn \"[%%\\\"\n```\n" [CodeBlock (Just "haskell") [] [l "main = putStrLn \"[%%\\\""]],
      testCase "an empty code block has no lines" $
        shapeOf "```\n```\n" [CodeBlock Nothing [] []],
      testCase "code blocks take keyword arguments after the language" $
        shapeOf
          "```haskell numbers=10 file=\"src/Main.hs\" highlight=12,14-15 callouts=true\nmain = pure ()\n```\n"
          [ CodeBlock
              (Just "haskell")
              [ l (Keyword (l "numbers") (Word "10")),
                l (Keyword (l "file") (StringLit "src/Main.hs")),
                l (Keyword (l "highlight") (Word "12,14-15")),
                l (Keyword (l "callouts") (Word "true"))
              ]
              [l "main = pure ()"]
          ],
      testCase "figure with caption body" $
        shapeOf
          "@label fig-arch\n@figure images/arch.pdf web=images/arch.png alt=\"構成図\"\n  構成図のキャプション。\n"
          [ -- the figure is the last command of the group, with its body
            Attributed
              [ l (BlockCommand (l "label") [l (Positional (Word "fig-arch"))] []),
                l
                  ( BlockCommand
                      (l "figure")
                      (map l [Positional (Word "images/arch.pdf"), Keyword (l "web") (Word "images/arch.png"), Keyword (l "alt") (StringLit "構成図")])
                      [l (para [Text "構成図のキャプション。"])]
                  )
              ]
              Nothing
          ],
      testCase "expressions" $
        shapeOf
          "[= -2 ** 2] [= round(2.675, 2)] [= [1, 2]] [= {a: 1, \"b\": true}] [= values.price >= 10]\n"
          [ para
              [ Expr (l (EUnary Negate (bin Pow (int 2) (int 2)))),
                Text " ",
                Expr (l (ECall "round" [l (EFloat 2.675), int 2])),
                Text " ",
                Expr (l (EArray [int 1, int 2])),
                Text " ",
                Expr (l (EHash [("a", int 1), ("b", l (EBool True))])),
                Text " ",
                Expr (bin OpGe (l (EVar ["values", "price"])) (int 10))
              ]
          ],
      testCase "binary operators and their precedence" $
        shapeOf
          "[= 1 + 2 * 3 % 4 / 5 - 6]\n[= 1 == 2][= 1 != 2][= 1 < 2][= 1 <= 2][= 1 > 2][= 1 >= 2 + 3]\n"
          [ para
              [ Expr (bin Sub (bin Add (int 1) (bin Div (bin Mod (bin Mul (int 2) (int 3)) (int 4)) (int 5))) (int 6)),
                SoftBreak,
                Expr (bin OpEq (int 1) (int 2)),
                Expr (bin OpNe (int 1) (int 2)),
                Expr (bin OpLt (int 1) (int 2)),
                Expr (bin OpLe (int 1) (int 2)),
                Expr (bin OpGt (int 1) (int 2)),
                Expr (bin OpGe (int 1) (bin Add (int 2) (int 3)))
              ]
          ],
      testCase "splat and keyword arguments" $
        shapeOf
          "[number-text 10 style=tcy] [f *[xs] **[kw]: 本文 | 二つ目]\n"
          [ para
              [ Command (l "number-text") (map l [Positional (Word "10"), Keyword (l "style") (Word "tcy")]) [],
                Text " ",
                Command (l "f") (map l [SplatPositional (l (EVar ["xs"])), SplatKeyword (l (EVar ["kw"]))]) [[txt "本文"], [txt "二つ目"]]
              ]
          ],
      testCase "arguments that are expressions, strings and commands" $
        shapeOf
          "[f [= 1 + 2] \"a b\" [g x]]\n"
          [ para
              [ Command
                  (l "f")
                  ( map
                      l
                      [ Positional (ExprArg (bin Add (int 1) (int 2))),
                        Positional (StringLit "a b"),
                        Positional (CommandArg (cmd "g" [Positional (Word "x")] []))
                      ]
                  )
                  []
              ]
          ],
      testCase "escapes" $
        shapeOf "\\# 見出しではない \\[ 50% \\\\\n" [para [Escaped '#', Text " 見出しではない ", Escaped '[', Text " 50% ", Escaped '\\']],
      testCase "a proofreading comment and a comment" $
        shapeOf "a%% x %%b%%= 校正 %%c\n" [para [Text "ab", ProofComment "校正", Text "c"]]
    ]
