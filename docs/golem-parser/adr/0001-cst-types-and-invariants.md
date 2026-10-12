# ADR 0001: CST の型と不変条件

ステータス: 採択

## 文脈

パーサーの出力は、コンパイラ、fmt、lint、LSP の四者が使う。
コンパイラに必要なのは意味だけだが、fmt はコメントと空白を含めて原稿を書き戻す必要があり、LSP は書きかけで構文エラーを含む原稿からも構文木を得る必要がある。
コメントと空白を捨てる AST だけを出力すると、fmt は作れず、エラーで止まるパーサーでは LSP の補完も診断も出せない。
そこで、パーサーはコメントと空白を保持し、エラーを含んでも木を作る CST を出力し、AST はそこから導出すると決めている。

パーサー本体は PEG のライブラリ（別のリポジトリで開発する peg-hs）に依存し、そのライブラリのエラーからの回復の機能を待つ必要がある。
一方、CST の型と、木が満たすべき不変条件は、パーサーがなくても定義でき、検査できる。
この ADR は CST の型と不変条件だけを扱い、パーサーより先に実装を完了させる。
パーサー本体は [ADR 0002](0002-parser-on-peg-hs.md) で扱う。

## 実装すること

### データ構造

```haskell
data SyntaxKind
  = -- トークン
    KText | KWhitespace | KNewline | KComment | KProofComment
  | KLBracket | KRBracket | KColon | KPipe | KEquals | KAt | KHash | ...
  | KError
    -- ノード
  | NFile | NParagraph | NHeading | NBulletList | NOrderedList | NListItem
  | NDefList | NDefTerm | NDefBody | NTable | NTableRow | NCodeBlock
  | NBlockCommand | NInlineCommand | NExpr | NProseSlot | NArgument
  | NErrorNode
  | ...

data Token = Token
  { tokKind :: !SyntaxKind
  , tokText :: !Text
  }

data Node = Node
  { nodeKind     :: !SyntaxKind
  , nodeWidth    :: !Int            -- 子のテキストの UTF-8 のバイト数の合計
  , nodeChildren :: ![Element]
  }

data Element = ElemNode !Node | ElemToken !Token
```

- ノードは自分の絶対位置を持たず、幅だけを持つ。絶対位置は、木をたどるときに親から計算する。一部を書き換えた木を再利用しやすくするためである。
- 空白、改行、コメント（`%%`、`%%=`）はトリビアのトークンとして、木の中の現れた位置に置く。
- 構文エラーの箇所は、`KError` のトークンか `NErrorNode` のノードとして木に残す。
- `SyntaxKind` の構成子の一覧は、文法の ADR で記法を追加するたびに増やす。この ADR では、上に挙げた種類を最初の集合とする。

### 操作

- `node :: SyntaxKind -> [Element] -> Node`：子から幅を計算してノードを作る。幅を外から与える構成子は公開しない。
- `render :: Node -> Text`：すべてのトークンのテキストを順に連結する。
- `withPositions :: FileId -> Node -> ...`：木をたどり、各ノードとトークンに golem-syntax の `SrcSpan` を付けて返す。
- 人が読める形への変換（字下げした種類とテキストの一覧）。golden テストと `golem inspect` で使う。

### 不変条件

- **幅の整合**：各ノードの `nodeWidth` は、子の幅の合計に等しい。`node` 以外にノードを作る手段がないことで保証する。
- **位置の整合**：`withPositions` が付ける位置は重ならず、隙間なく並び、最後の位置は `render` の結果の長さと一致する。

ロスレス性（`render` の結果が入力と一致すること）は、入力を持つパーサーの性質なので [ADR 0002](0002-parser-on-peg-hs.md) で扱う。

## 実装しないこと

- パーサー本体と文法。[ADR 0002](0002-parser-on-peg-hs.md) と後続の ADR で扱う。
- CST から AST への変換。後続の ADR で扱う。
- インクリメンタルな再解析。

## テスト設計

- hedgehog で任意の CST を生成し、すべてのノードで幅が子の合計と一致することを確かめる。
- 生成した CST で、`withPositions` の位置が重ならず隙間なく並び、`render` の長さと一致することを確かめる。
- 日本語と 4 バイトの文字を含むトークンで、幅が UTF-8 のバイト数で数えられていることを確かめる。
- 人が読める形への変換を golden テストで固定する。

## トレードオフ

CST と AST の二つの木を持つと、メモリと変換の手間が増える。
その代わり、コンパイラは意味だけを扱う AST を使え、fmt と LSP は情報を失わない CST を使える。
一つの木で両方を賄おうとすると、コンパイラの全段がトリビアを読み飛ばす処理を抱えることになる。

型と不変条件をパーサーと別の ADR にすると、文法を加えるたびに `SyntaxKind` を二つの ADR の範囲にまたがって増やすことになる。
それでも、peg-hs を待たずに土台を完成させられることのほうが、並行して実装を進めるうえで価値が大きい。
