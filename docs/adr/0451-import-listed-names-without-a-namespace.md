# ADR 0451: `@import` で、並べた名前を名前空間なしで取り込めるようにする

Status: superseded [{"part":"名前が重なったとき","by":["docs/adr/0455-resolve-variable-imports-through-the-import-graph.md"],"kind":"supplement"},{"part":"名前が重なったとき","by":["docs/adr/0453-override-built-in-commands-by-listed-imports-and-plugins.md"],"kind":"replace"},{"part":"ツール","by":["docs/adr/0454-rename-set-variables-in-the-language-server.md"],"kind":"supplement"},{"part":"実装しないこと","by":["docs/adr/0458-rename-listed-imports-with-as.md"],"kind":"replace"},{"part":"書き方","by":["docs/adr/0458-rename-listed-imports-with-as.md"],"kind":"supplement"},{"part":"名前が重なったとき","by":["docs/adr/0461-report-the-diagnostics-that-follow-from-another-error.md"],"kind":"replace"}]

## 文脈

`.gm` の `@import` は、`@set` で定義した変数と `.emet` の関数を、名前空間を付けて取り込む（`@import パス as 名前空間`）。
取り込んだ定義は名前空間を通してだけ参照でき、`.emet` の関数は `@s.foo`、`[s.foo …]`、`[= s.foo(x)]` のように呼ぶ。
名前空間を付けずに定義を展開する取り込みは認めていない（[docs/adr/0185](0185-project-wide-variables.md)、[docs/adr/0162](0162-calling-emet-functions-from-gm.md)）。
その理由は、どの名前がどこから来たかを名前の形だけで分かるようにし、組み込みのコマンドやプラグインのコマンドと名前が重ならないようにするためである。

メンテナーは、取り込んだ関数を `@foo` のように名前空間なしで呼べるようにしたいと述べた。
今の名前空間つきの取り込みは、`@import パス * as 名前空間` という書き方に変える。
メンテナーは、次の四つも決めた（2026-11-26）。

- 名前空間なしの取り込みは、使う名前を並べて書く。どの名前がどのファイルから来たかを、原稿の `@import` の行から読めるようにするためである。
- 名前空間なしで取り込んだ名前が、組み込みのコマンド、プラグインのコマンド、ほかの取り込みの名前と同じなら、エラーにする。
- `.gm` の変数の取り込みも、`.emet` の関数の取り込みと同じ書き方にする。
- 今の書き方 `@import パス as 名前空間`（`*` のないもの）はエラーにし、直し方を示す。

この ADR は、書き方、並べる名前の意味、名前の重なり、diagnostic、ツールの扱い、今の原稿の移し方を決める。

## 調査した事項

origin/main（[ef9dac6](https://github.com/tett23/golem/commit/ef9dac683de7bb8494308eeddedb32b424605e06)）で、次のことを確かめた。

- `@import` に専用の文法はない。汎用のブロックコマンド（`At Ident Arguments`）として読む（[Golem.hpeg#L594-L595](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-parser/grammar/Golem.hpeg#L594-L595)）。
- 形は構文解析の後で検査する。`importSite` は、位置引数の「語か文字列のパス」「語 `as`」「語の名前空間」の三つだけを受け、それ以外は G03009 とする（[Imports.hs#L48-L56](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-project/src/Golem/Project/Imports.hs#L48-L56)）。
- 引数の語（`Word`）は、空白、`]`、`:`、`|`、`=`、`[`、`"`、`\` を含まない文字の連なりである（[Golem.hpeg#L387-L391](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-parser/grammar/Golem.hpeg#L387-L391)）。
  そのため、`*`、`{`、`}`、`,` は、引数の位置では語の一部か一つの語として読まれ、ほかの意味を持たない。
  `{total,price}` は一つの語、`{ total, price }` は `{`、`total,`、`price`、`}` の四つの語になる。
  `*[` と `**[` だけが展開の記号になる（[Golem.hpeg#L372-L378](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-parser/grammar/Golem.hpeg#L372-L378)）。
- 評価は、`.emet` の取り込みを `stFunctions` に、変数の取り込みを `stNamespaces` に、`@import` の行を評価したときに登録する（[File.hs#L601-L622](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-eval/src/Golem/Eval/File.hs#L601-L622)）。
  そのため、取り込んだ名前空間は `@import` の行より後で見える。
  同じ名前空間を二度取り込むと、後の取り込みで上書きされ、diagnostic は出ない。
- 名前空間を付けないブロックコマンド `@foo` とインラインのコマンド `[foo …]` は、組み込みとプラグインのコマンドだけを探す（[File.hs#L652-L657](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-eval/src/Golem/Eval/File.hs#L652-L657)、[File.hs#L2592-L2598](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-eval/src/Golem/Eval/File.hs#L2592-L2598)）。
- 予約語は `doc`、`meta`、`vars`、`true`、`false`、`nil` で、名前空間に使うと G02023 になる（[File.hs#L239-L240](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-eval/src/Golem/Eval/File.hs#L239-L240)）。
- 仕様書の関数の種類の表では、`.gm` から使えるのは `pub inline`（インラインのコマンド）、`pub block`（ブロックコマンド）、`pub fn`（式の関数）である。
  インラインとブロックのコマンドの名前は、種類の語の後ろに文字列で書ける（`pub inline "tax-included"` など）。
  インラインのコマンドとブロックコマンドは名前の空間が別なので、同じ名前を持てる（0162 の「コマンドの名前」）。
- `.emet` の読み込みか型の検査に誤りがあるときは、その `.emet` の関数を通した呼び出しで G02022、G02009、G02002 を報告しない（0162 と仕様書の「`.gm` から関数を使う」の節）。
- 使われていない `@import` は G05003（エラー）、どの取り込みからも参照されない `@set` の変数は G05002 で、golem-lint が出す（[Lint.hs#L146-L150](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-lint/src/Golem/Lint.hs#L146-L150)、[Lint.hs#L164-L170](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-lint/src/Golem/Lint.hs#L164-L170)、[golem-lint ADR 0001](../golem-lint/adr/0001-lint-rules.md)）。
- `.emet` の中の `import` は別の文法で、名前空間なしで取り込む（[Emet.hpeg#L131](https://github.com/tett23/golem/blob/ef9dac683de7bb8494308eeddedb32b424605e06/modules/golem-emet/grammar/Emet.hpeg#L131)）。
- `@import パス as 名前空間` の形は、`modules/` の 35 ファイルに 76 か所（ほとんどはテストの Haskell の文字列）、二冊のマニュアルと `functions/` に合わせて 33 か所ある（`git grep -c -E '@import [^ ]+ as '`）。

## 実装すること

### 書き方

`@import` は、次の二つの形のどちらかで書く。

```
@import functions/book.emet * as book
@import functions/book.emet { tax-included, word-table, total }
```

- **名前空間つきの取り込み**：`@import パス * as 名前空間`。今の `@import パス as 名前空間` と同じ意味である。取り込んだ定義は、今と同じく名前空間を通してだけ参照できる。
- **名前を並べた取り込み**：`@import パス { 名前, 名前, … }`。並べた名前を、名前空間なしで参照できるようにする。

名前の並びは、`{` で始め `}` で終え、名前を `,` で区切る。
`{`、`}`、`,` の前後の空白は、あってもなくてもよい。
パスの後ろの引数を、語の境目と、語の中の `{`、`}`、`,` で区切って字句に分ける。
字句の並びは、`{`、名前、（`,`、名前）の繰り返し、`}` の順でなければならない。
たとえば `{ a b }` は、名前と名前のあいだに `,` がないので誤りである。
それぞれの名前の位置は、その名前を含む語の中の位置から求める。
並びは一つ以上の名前を持ち、最後の名前の後に `,` を置かない。
この形にならない並び、二つの形を混ぜたもの（`* { a }`、`{ a } as ns` など）、`*` だけのものは、今と同じく G03009 とし、メッセージに二つの形を示す。

パスの拡張子が `.emet` なら関数の取り込み、そうでなければ変数の取り込みとすることは、今と変えない。

### 並べる名前

並べる名前は、`.gm` から使うときの名前である。

- `.emet` からは、`pub inline` と `pub block` のコマンドの名前（文字列で名前を書いたものはその名前）と、`pub fn` の関数の名前を並べられる。
- 一つの名前が、インラインのコマンド、ブロックコマンド、式の関数のうち二つ以上の種類で公開されていれば、その名前を並べると、公開されたすべての種類を取り込む。
- 変数のファイルからは、`@set` の変数の名前を並べられる。

### 名前の参照

名前を並べて取り込んだ名前は、`@import` を書いたファイルの中で、`@import` の行より後で、名前空間なしで参照できる。
見える範囲は、名前空間つきの取り込みと同じである。

- インラインのコマンドは `[foo …]`、ブロックコマンドは `@foo`、式の関数は `[= foo(x)]` で呼ぶ。
- 変数は、そのファイルで `@set` した変数と同じ書き方で参照する（`[= price]`、柱の書式の `{set.price}` など）。

同じファイルで、同じパスを名前空間つきと名前を並べた形の両方で取り込んでよい。

### 名前が重なったとき

名前を並べて取り込んだ名前は、使う場所ごとに、次のものと重なればエラーにする。
使う場所は、インラインのコマンド、ブロックコマンド、式（式の関数と変数）の三つで、別々に調べる。
たとえば、変数 `toc` は式で使う名前なので、ブロックコマンド `@toc` とは重ならない。

| 重なる相手 | 調べる場所 | コード |
| --- | --- | --- |
| 組み込みのコマンドの名前（`@import`、`@set`、`@toc` など、名前空間なしで評価が組み込みとして扱うすべての名前） | インライン、ブロック | G02270 |
| プロジェクトが宣言したプラグインのコマンドの名前 | インライン、ブロック | G02271 |
| 同じファイルのほかの `@import` が並べた名前 | 三つとも | G02272 |
| 同じ並びの中で前に書いた名前 | 三つとも | G02273 |
| 同じファイルで `@set` した変数の名前 | 式 | G02274 |
| 組み込みの式の名前（関数の `join` と定数の `pi`、`e` など） | 式 | G02277 |

並べた名前が予約語（`doc`、`meta`、`vars`、`true`、`false`、`nil`）なら G02275 とし、この名前のほかの検査はしない。
予約語でなく、取り込む先にその名前が公開されていなければ G02276 とし、この名前の重なりは調べない。
それ以外の名前は、重なる相手の種類ごとに、表のコードを一つずつ出す。
どの diagnostic も、`@import` の行のその名前の位置で報告する。
G02274 は、`@set` と `@import` のどちらが先に書かれていても出す。
`@set` の変数は組み込みの式の名前を隠せるが、名前を並べた取り込みでは重なりをエラーにする。
`@set` の変数は同じファイルの中で定義が見えるのに対し、取り込んだ名前の定義は別のファイルにあり、組み込みの名前を隠していることに書き手が気づきにくいためである。
`@import` を書いた順や名前を探す順で、どの定義を呼ぶかが変わらないようにするためである。

`.emet` のどれかの読み込みか型の検査に誤りがあるときは、`.emet` から並べたすべての名前の G02276 と重なりの検査をせず、それらの名前空間なしの呼び出しでも G02022、G02009、G02002 を報告しない。
今の仕様書が、どれか一つの `.emet` に誤りがあればすべての `.emet` の名前空間を同じく扱うのに合わせる。
名前空間つきの取り込みと同じく、誤りの元を `.emet` の中の位置で報告するためである。

名前空間つきの取り込みの規則（名前空間の予約語は G02023 など）は変えない。

### 今の書き方

`*` のない `@import パス as 名前空間` は、G03295（エラー）とする。
メッセージは、`@import パス * as 名前空間` に直すよう示す。
`golem fmt` は、この形を `@import パス * as 名前空間` に書き換える。

### ツール

- **golem lint**：
  - 名前を並べた取り込みで、並べた名前のうち使われていないものを、その名前の位置で G05003 とする。
  - 名前を並べて取り込み、名前空間なしで参照した変数は、G05002 の検査で参照されたと数える。
- **golem fmt**：名前の並びを `{ 名前, 名前 }`（`{` の後と `}` の前に空白を一つ、`,` の後に空白を一つ）に整える。
- **LSP**：
  - 名前の並びの中で、取り込む先の公開された名前を補完する。
  - 名前を並べて取り込んだ名前を、取り込んだファイルの中で名前空間なしで補完する。
  - 名前を並べて取り込んだ名前の参照から、定義へ移動する。
  - 関数と `@set` の変数の改名は、`.gm` に出す名前が変わるときだけ、名前の並びと名前空間なしの呼び出しも書き換える。文字列で名前を書いた `pub inline` と `pub block` は、仕様書の改名の規則のとおり `.gm` を書き換えない。
  - ファイルの移動と改名は、今と同じくパスだけを書き換える。

### 文書と移行

仕様書は、次の箇所を書き換える。

- 「定義の取り込み」の節を二つの形に書き換え、「名前空間を付けずに定義を展開する取り込みは認めない」の文を消す。
- 「名前のスコープ」の `@set` の変数の項（ほかのファイルからは名前空間を通してのみ見える）を、名前を並べた取り込みに合わせる。
- 柱の書式の表の `{set.<名前>}` と `{set.<名前空間>.<名前>}` を、二つの形に合わせる。
- 「`.gm` から関数を使う」の節、LSP の補完と改名の記述、lint の節の `.emet` の名前空間の G05003 の記述、semantic tokens の名前空間付きの式の呼び出しの記述（名前空間なしの式の呼び出しも `function` にする）。

`@import … as` を `* as` に書き換えるのは、二冊のマニュアル、`docs/markup.md`、`docs/golem-emet/grammar.md`、`docs/manual-policy.md`、`docs/diagnostics.md` の例、`functions/README.md` と `functions/*.emet` のコメント、テストの原稿（Haskell の文字列を含む）である。
コミット済みの ADR と監査の記録は書き換えない。
`docs/diagnostics.md` に G02270 から G02277 と G03295 を足し、G03009 のメッセージと G05003 の説明（名前ごとの報告）を直す。

採択したら、次の三つの ADR のステータスに記録する。
どれも、この ADR が書き直していない規則（パスとファイルの同一性、`vars` の予約など）は残るので、置き換えではなく補足と注記として記録する。
0162 と 0185 は今 `superseded [...]` なので配列に要素を足し、0142 は今 `accepted` なので `superseded [<注記>]` にする。

```text
docs/adr/0162: {"part":"取り込み","by":["docs/adr/0451-import-listed-names-without-a-namespace.md"],"kind":"supplement"}
docs/adr/0162: {"part":"呼び方","by":["docs/adr/0451-import-listed-names-without-a-namespace.md"],"kind":"supplement"}
docs/adr/0162: {"part":"LSP","by":["docs/adr/0451-import-listed-names-without-a-namespace.md"],"kind":"supplement"}
docs/adr/0162: {"part":"lint","by":["docs/adr/0451-import-listed-names-without-a-namespace.md"],"kind":"supplement"}
docs/adr/0185: {"part":"参照の書き方と名前空間","by":["docs/adr/0451-import-listed-names-without-a-namespace.md"],"kind":"supplement"}
docs/adr/0142: {"part":null,"by":[],"kind":"note","note":"@import の形は、root ADR 0451 で「パス * as 名前空間」と「パス { 名前, … }」になった。展開を G03009 とする決定は変わらない。"}
```

## 実装しないこと

`.emet` の中の `import` の文法と意味は変えない。
名前空間つきの取り込みで、同じ名前空間を二度取り込んだときに後の取り込みで上書きされる今の振る舞いは、この ADR では変えない。
マニフェストの `[vars]` の変数を名前空間なしで読む書き方は足さない。
取り込んだ名前に別名を付ける書き方（`{ total as sum }` など）は足さない。
公開された名前をすべて名前空間なしで取り込む形は足さない（トレードオフ）。

## 不変条件

- I1: `@import パス * as ns` で取り込んだ定義の参照の結果は、今の `@import パス as ns` の結果と同じである。
- I2: `@import パス { n1, …, nk }` で取り込んだ各名前 ni の、各種類（インライン、ブロック、式）の名前空間なしの参照の結果は、同じパスを `* as ns` で取り込んだときの同じ種類の `ns.ni` の参照の結果と同じである。
- I3: 予約語でなく取り込む先に公開されている並べた名前について、表の重なる相手の種類ごとに、重なりがあればその種類のコードがちょうど一つ、その名前の位置で出て、重なりがなければ出ない。
- I4: 並べた名前が予約語なら G02275 だけが、予約語でなく取り込む先に公開されていなければ G02276 だけが、その名前の位置で出る。
- I5: `*` のない `@import パス as ns` は G03295 になり、`golem fmt` で `* as ns` に書き換えた原稿は G03295 を出さず、I1 の結果を返す。
- I6: パスの後ろの引数が、`* as 名前空間` の形でも、「一つ以上の名前を `,` で区切り `{` と `}` で囲む」形でもないときは G03009 になる。
- I7: 同じ名前空間を二度取り込まない原稿で、すべての参照より前にある `@import` の行どうしの順を入れ替えても、diagnostics の集合（位置を除く）と出力は変わらない。
- I8: どれかの `.emet` を読み込めないとき、`.emet` から並べた名前について、G02276、表のコード、名前空間なしの呼び出しの G02022、G02009、G02002 は出ない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `{ total }`（一つ） | `[= total(x)]` を呼べる | I2 |
| `{ tax-included, total }`（二つ） | どちらも呼べる | I2 |
| `{tax-included,total}`（空白なし） | 前の行と同じ | I2 |
| インラインとブロックの両方で公開された `{ x }` | `[x]` と `@x` の両方を呼べる | I2 |
| `{ }`（空） | G03009 | I6 |
| `{ total, }`（最後に `,`） | G03009 | I6 |
| `* { total }`、`{ total } as ns`、`*` だけ | G03009 | I6 |
| `{ toc }`（ブロックの組み込みと重なる `pub block "toc"`） | G02270 | I3 |
| プラグインのコマンドと同じ名前 | G02271 | I3 |
| `{ total, total }` | G02273 | I3 |
| `{ a b }`（`,` がない） | G03009 | I6 |
| 二つの `@import` が同じ名前を並べる | G02272、順を入れ替えても同じ | I3, I7 |
| `@set price` の後と前の `{ price }` | どちらも G02274 | I3, I7 |
| `{ join }`（`pub fn join`） | G02277 | I3 |
| 変数 `toc` を `{ toc }` で取り込む | 重ならない | I3 |
| `{ meta }` | G02275 だけ | I4 |
| `{ nothing }`（取り込む先にない） | G02276 だけ | I4 |
| `@import p as s` | G03295、fmt で `* as s` | I5 |
| `@import p * as s` | 今の `as s` と同じ結果 | I1 |
| 型の誤りのある `.emet` から `{ total }` | G02276 も重なりのコードも出ない | I8 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0451 I1 から I8 を名前の先頭に置いたテストを足す。
golem-project の `importSite` のテストで、I5 と I6 の形を表の入力で確かめる。
golem-eval のテストで、`.emet` と変数のファイルを、名前を並べた形と `* as` の形で取り込み、I1 と I2 の結果の一致を、三つの種類ごとに確かめる。
I3、I4、I7 は、重なる相手の五つの種類と予約語と公開されていない名前、三つの使う場所、`@import` の行どうしの順の入れ替えを列挙して確かめる。
I8 は、型の誤りのある `.emet` を取り込む原稿で確かめる。
golem-fmt のテストで `as` の書き換えと並びの整形を、golem-lint のテストで使われていない名前の G05003 と G05002 の数え方を、golem-lsp のテストで補完、定義への移動、改名を確かめる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

名前を並べて書くので、取り込む名前が増えると `@import` の行が長くなる。
その代わりに、名前空間なしの名前がどこから来たかを、原稿の `@import` の行から読める。

取り込む先の公開された名前をすべて名前空間なしで取り込む形（`@import パス`）も考えた。
書き方は短いが、名前の出どころを `.emet` を開かずに知れず、取り込む先に名前が足されると、取り込む側で重なりのエラーが新しく出る。
そのためメンテナーは採らなかった。

今の書き方 `as` を残さずエラーにするので、今の原稿とテストは書き換えが要る。
原稿は `golem fmt` で書き換えられるが、テストの Haskell の文字列は手で書き換える（調査した事項の数）。

## 参考文献

- [docs/adr/0162](0162-calling-emet-functions-from-gm.md)
- [docs/adr/0185](0185-project-wide-variables.md)
- [docs/adr/0142](0142-import-arguments-are-not-spread.md)
- [golem-project ADR 0001](../golem-project/adr/0001-manifest-and-import-graph.md)
- [golem-project ADR 0006](../golem-project/adr/0006-project-diagnostic-codes.md)
