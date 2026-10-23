# ADR 0002: peg-hs によるパーサー本体

ステータス: 採択→診断コードの割り当てと、単独の CR の扱いは [ADR 0009](0009-syntax-diagnostic-codes.md)

## 文脈

[ADR 0001](0001-cst-types-and-invariants.md) で CST の型と不変条件を定めた。
この ADR は、原稿のテキストから CST を作るパーサーの骨格を定める。
文法の個々の規則（ブロック層とインライン層の記法がどの木になるか）は、[ADR 0003](0003-block-grammar.md) と [ADR 0004](0004-inline-grammar.md) で扱う。

パーサーは PEG で記述し、別のリポジトリで開発する peg-hs を使う。
peg-hs はスタンドアロンの生成器であり、`.peg` の文法から Haskell のモジュールを生成する。
生成したモジュールが実行時に依存するのは peg-runtime だけであり、生成物はリポジトリにコミットできる（[peg-hs ADR 0002](https://github.com/tett23/peg-hs/blob/main/docs/adr/0002-standalone-code-generator.md)）。
peg-hs は、トリビアを保持する構文木（[peg-hs ADR 0019](https://github.com/tett23/peg-hs/blob/main/docs/adr/0019-lossless-syntax-tree.md)）と、ラベル付きの失敗による構文エラーからの回復（[peg-hs ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md)）を提供する。
[peg-hs ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md) は、Golem のこの ADR の要件（全域性、ロスレス性、空行での再開、段落の終わりで閉じたとみなす回復）を入力として書かれている。

## 前提

[peg-hs ADR 0019](https://github.com/tett23/peg-hs/blob/main/docs/adr/0019-lossless-syntax-tree.md)（構文木）と [ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md)（回復）は採択され、実装されている。
peg-hs は Hackage への公開前なので、生成器と peg-runtime は、リリースの版が出るまで Git のコミットで固定する。

## 実装すること

### 読み込みの段階

パーサーに渡す前に、ファイルのバイト列を検査する。

- UTF-8 として不正なバイト列はエラーとする。
- BOM があればエラーとする。
- CRLF を含めばエラーとし、`golem fmt` で LF に直せることを診断の修正案に載せる。

### 文法と生成物

- 文法は `modules/golem-parser/grammar/golem.peg` に置き、`%syntax` を指定して構文木を生成させる。
- 空白、改行、コメント（`%%`、`%%=`）の規則には `%token` と `%trivia` を付ける。
- 生成した Haskell のモジュールはリポジトリにコミットする。CI で文法から生成し直し、コミットされた生成物とバイト単位で一致することを検査する。
- peg-hs の生成器と peg-runtime の版（リリースの前は Git のコミット）は固定し、版を上げるときは ADR を作成する。

### 二つの入口の使い分け

Golem は、コンパイル、fmt、lint、LSP のすべてで、回復するモードの入口 `parseSyntaxRecover` を使う。
四者が同じ CST を前提にできるようにするためである。
構文エラーが一つでもあれば、コンパイルはその後の段階に進まずに失敗する。

### 回復の方針

[peg-hs ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md) の記法で、文法に次の二種類のラベルと回復の規則を書く。

- **ブロックの回復**：ブロックの規則にラベルを付け、失敗したら次の空行（またはファイルの終わり）まで読み飛ばす回復の規則を与える。エラーの影響はそのブロックの中に閉じる。
- **括弧の回復**：命令文脈と式文脈の閉じ括弧にラベルを付け、入力を消費せず、段落の終わりで閉じたとみなす回復の規則を与える。幅が 0 の誤りのノードになる。

どの位置にラベルを付けるかは、文法の ADR（[ADR 0003](0003-block-grammar.md) と [ADR 0004](0004-inline-grammar.md)）でブロックと構文ごとに定める。
ラベルは、その位置で失敗したらどの選択肢でも成功しえない場所にだけ付ける。
ラベルの送出は順序付き選択の後戻りを止めるので、誤った位置に付けると、正しい原稿が受理されなくなる。

### peg-hs の構文木から Golem の CST への変換

peg-hs の構文木（`SyntaxNode`）を、[ADR 0001](0001-cst-types-and-invariants.md) の Golem の CST（`Node`）に変換する。

- peg-hs の規則ごとの種類を、Golem の `SyntaxKind` に写す。対応表は golem-parser の中に一箇所で持つ。
- peg-hs の `ERROR` のノードは `NErrorNode` に写す。
- peg-hs の型付きの層（規則ごとのノードを包む型）は使わない。Golem は AST を Golem の CST から自分で導出する。

### 診断

peg-hs の `SyntaxError` を、golem-syntax の `Diagnostic` に変換する。

- ラベルの名前から診断コード（`G01xxx`）と日本語のメッセージへの対応表を、golem-parser の中に一箇所で持つ。
- ラベルを持たない構文エラー（開始規則の後に残った入力、開始規則の失敗）にも、それぞれ診断コードを割り当てる。
- 診断の位置は、`SyntaxError` の範囲から作る。範囲が空の場合（挿入の回復）は、その位置を指す幅 0 の位置とする。

### インターフェース

```haskell
parse :: FileId -> Text -> (Node, [Diagnostic])
```

### 不変条件

- **ロスレス性**：`render (fst (parse f t)) == t` が、エラーを含む入力も含めて常に成り立つ。
- **全域性**：読み込みの段階を通過した任意のテキストに対して、`parse` は必ず終了し、木を返し、例外を投げない。[peg-hs ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md) の `parseSyntaxRecover` の全域性に依拠する。

## 実装しないこと

- 文法の個々の規則。[ADR 0003](0003-block-grammar.md) と [ADR 0004](0004-inline-grammar.md) で扱う。
- CST から AST への変換。[ADR 0005](0005-cst-to-ast.md) で扱う。
- インクリメンタルな再解析。
- peg-hs の回復しないモードの使用。

## テスト設計

- **ロスレス性**：正しい原稿、壊れた原稿、無作為なテキストを生成し、`render` の結果が入力と一致することをプロパティテストする。
- **全域性**：無作為なテキストで `parse` が必ず終了することを確かめる。
- **回復の局所性**：正しい段落の間に壊れた段落を一つ挟んだ原稿で、壊れた段落だけが `NErrorNode` になり、前後の段落は正しく解析されることを確かめる。
- **挿入の回復**：閉じていない角括弧を含む段落で、幅が 0 の `NErrorNode` と診断が一つずつ生じ、次の段落が正しく解析されることを確かめる。
- **言語の不変**：正しい原稿の集合（docs/markup.md の例を含む）が、構文エラーなしで解析されることを確かめる。ラベルの付け方が安全であることの確認である。
- **生成物の一致**：CI で文法から生成し直したモジュールが、コミットされた生成物と一致することを確かめる。
- **診断の対応**：対応表のすべてのラベルが文法に現れ、文法のすべてのラベルが対応表にあることを確かめる。
- 読み込みの段階：不正な UTF-8、BOM、CRLF のそれぞれが診断になることを確かめる。

## トレードオフ

コンパイルでも回復するモードを使うと、[peg-hs ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md) が述べるとおり、回復しないモードより解析が遅くなる。
その代わり、コンパイル、fmt、lint、LSP が同じ入口と同じ木を使い、構文エラーの報告も四者で一致する。
解析の速度がビルド全体の律速になると分かった場合は、コンパイルにだけ回復しないモードを使う変更を ADR で検討する。

peg-hs の構文木をそのまま Golem の CST として使わず、Golem の型に変換する。
変換の手間と、一時的に二つの木がメモリに載ることを受け入れる代わりに、Golem の CST の型が peg-hs の版の変更から独立し、[ADR 0001](0001-cst-types-and-invariants.md) を peg-hs なしで完了できる。
