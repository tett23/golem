# ADR 0005: CST から AST への変換

ステータス: 採択

## 文脈

CST はコメントと空白を含めて原稿を忠実に保持するが、評価器に必要なのは意味だけである。
評価器が CST を直接読むと、すべての段でトリビアを読み飛ばし、エスケープを解除し、改行の規則を適用する処理を重複して持つことになる。
そこで、CST から意味だけを取り出した AST に変換し、評価器は AST だけを読む。

AST は評価の前の表現であり、式と命令をそのまま持つ。
評価が済んだ表現である意味論 IR（golem-doc）とは別の型である。

## 実装すること

### データ構造

```haskell
data File = File { fileId :: !FileId, fileBlocks :: ![Located Block] }

data Located a = Located { locSpan :: !SrcSpan, locValue :: !a }

data Block
  = Paragraph [Located Inline]
  | Heading !Int [Located Inline]
  | BulletList [ListItem]
  | OrderedList [ListItem]
  | DefList [DefGroup]
  | Table [Alignment] [[Located Inline]] [[[Located Inline]]]
  | CodeBlock (Maybe Text) Text
  | BlockCommand Name [Located Argument] [Located Block]   -- 本体
  | Attributed [Located BlockCommandCall] (Maybe (Located Block))
  | ErrorBlock

data Inline
  = Text Text
  | Expr (Located Expr)
  | Command Name [Located Argument] [[Located Inline]]       -- 散文スロット
  | ErrorInline

data Argument
  = Positional ArgValue
  | Keyword Name ArgValue
  | SplatPositional (Located Expr)
  | SplatKeyword (Located Expr)

data ArgValue = Word Text | StringLit Text | ExprArg (Located Expr) | CommandArg (Located Inline)

data Expr
  = EInt Integer | EFloat Double | EString Text | EBool Bool | ENil
  | EArray [Located Expr] | EHash [(Text, Located Expr)]
  | EVar [Name]                       -- a.b.c
  | ECall Name [Located Expr]
  | EUnary UnaryOp (Located Expr)
  | EBinary BinaryOp (Located Expr) (Located Expr)
```

- すべてのノードは `SrcSpan` を持つ。
- `ErrorBlock` と `ErrorInline` は CST の `NErrorNode` に対応する。構文エラーを含むファイルからも、LSP のために AST を作れるようにするためである。

### 変換の規則

- トリビア（空白、コメント）は捨てる。校正用のコメント（`%%=`）は、dev のプロファイルで出力に現れるため、`ProofComment Text` のインラインとして残す。
- エスケープを解除し、`\` の後の文字を地の文にする。
- 段落内の改行は文字を生まない規則に従い、改行のトークンを捨てて、前後の地の文をそのまま連結する。隣り合う `Text` は一つにまとめる。
- 中身が空の段落（コメントだけの段落など）は捨てる。ただし、校正用のコメントだけの段落は残す。
- 浮動小数点数のリテラルは、十進の文字列から最も近い倍精度の値に、正しい丸めで変換する（[golem-eval ADR 0001](../../golem-eval/adr/0001-expression-language-and-numerics.md)）。
- コードブロックの中身からは、ブロックのインデントの分だけ行頭の空白を取り除く。

### 意味論 IR との関係

AST は式（`Expr`）を直接持つ。
評価器は AST の式を評価し、式を含まない意味論 IR を作る。
以前の設計にあった「意味論 IR が式の表を参照する（ExprRef）」という形は採らない。
意味論 IR は評価が済んだ値だけを持つと決めており（[golem-doc ADR 0001](../../golem-doc/adr/0001-semantic-ir-in-cddl.md)）、式の表を参照する必要がなくなったためである。
文書構造（S1）に評価を遅らせる式の扱いは、[golem-eval ADR 0002](../../golem-eval/adr/0002-file-evaluation.md) で定める。

## 実装しないこと

- コマンドの意味の解釈と、引数の検査。
- 属性のまとまりの検査（属性として付けられないコマンド、後ろにブロックのないまとまり）。評価の段階で行う。

## テスト設計

- 改行の除去：`吾輩は猫である。` と `名前はまだ無い。` の二行の段落が、一つの `Text` になることを確かめる。
- エスケープの解除：`\[`、`\\`、`\%%`、行頭の `\#` が地の文になることを確かめる。
- コメントが消え、校正用のコメントが `ProofComment` として残ることを確かめる。
- 中身が空の段落が捨てられることを確かめる。
- 位置：AST のすべてのノードの位置が、元の CST の対応するノードの範囲に含まれることをプロパティテストする。
- エラーを含む原稿から、エラーの箇所を `ErrorBlock` と `ErrorInline` にした AST ができることを確かめる。

## トレードオフ

AST を CST とは別の型にすると、記法を一つ加えるたびに CST の種類、文法、AST の型、変換の四箇所を直すことになる。
その代わり、評価器は記法の表面の違い（エスケープ、改行、コメント）から切り離され、評価の規則だけを扱える。
