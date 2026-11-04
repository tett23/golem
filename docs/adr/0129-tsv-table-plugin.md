# ADR 0129: TSV から表を組む見本のプラグイン

ステータス: 採択（未実装）

## 文脈

rc4 の見本のプラグインの一つに、TSV から表を組むコマンドがある（[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4）。
データは [docs/adr/0105](0105-plugin-data.md) のとおりバイト列で受け取り、組み込みの `@table` と同じ表のブロックを返す。

同じことは `@table src=data/sales.tsv` でもうできる（[golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md)）。
このプラグインの役目は、表を組む新しい手段を足すことより、プラグインの仕組みを実際の用途で通すことにある。
ブロックを返し、データを複数受け取り、キーワード引数を読み、大きな入力を扱う。
組み込みの `@table` という比べる相手があるので、出力が同じか、速さと上限がどれだけ違うかを測れる。

書き始めると、今の仕組みでは書けないことが三つわかった。

- コマンドはインラインの列しか返せない。表はブロックなので返せない。[docs/adr/0122](0122-block-commands-in-plugins.md) で、行頭の `@name` で呼ぶブロックコマンドを足した。
- ホストはキーワード引数のキーを捨てていた。`align=left` を受け取れない。[docs/adr/0110](0110-keyword-arguments-to-plugins.md) で直した。
- プラグインは受け取るデータの名前を前もって宣言するので、表ごとの TSV を渡せない。[docs/adr/0119](0119-plugin-data-of-any-name.md) で、どんな名前も受け取る宣言 `*` を足した。

この ADR は、この三つの草稿が採択されることを前提に、プラグインそのものを決める。

### 試しに実装して分かったこと

採択の前に実装を試した（ブランチ `plugins-tsv-table`）。

- **大きさ**：`tsv-table.wasm` は 86,351 バイトである（記述をマップにした後。[docs/adr/0107](0107-named-describe-fields.md)）。`lookup`（76,860 バイト）とほぼ同じで、大半は std の書式化と dlmalloc である。
- **出力の同一性**：同じ TSV を `@tsv-table` と `@table` で組むと、セルの文字列と揃えの同じ表になった。PDF は文書の ID（`/ID` の二つめ）を除いて同じバイト列だった。違いはノードのソース位置だけで、`@table` のセルは TSV のファイルの中を、プラグインのセルは呼び出しの行を指す。
- **命令数の上限**：一回の呼び出しの fuel（約 10 億命令、[`defaultFuel`](https://github.com/tett23/golem/blob/fa55dc76be6fef7189cb80883fd0bb0b0630911f/modules/golem-plugin/src/Golem/Plugin.hs#L77-L78)）が、メモリより先に当たる上限だった。
数字は「上限と速さ」の節に書く。
行の上限を外した版では、4 列の表が 30,000 行で通り、35,000 行で G06009（命令数の上限）になった。
- **メモリ**：64 MiB（[docs/adr/0105](0105-plugin-data.md) の上限ちょうど）のデータを渡しても、メモリの上限（256 MiB）でトラップしなかった。プラグインは大きさを見て、自分の上限の diagnostic を返した。
- **diagnostic の位置**：プラグインは TSV の中の位置を指せない。diagnostic の位置は要求の位置（呼び出しの行）に限られる（[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md)）。`@table` は G02085 を TSV の行に出すが、プラグインはメッセージに行の番号を書くしかない。
- **diagnostic のコード**：割り当てられた G06024 から G06027 は使わなかった。試しの実装では、`lookup` に倣って `tsv-table-cells` のような文字列にした。この ADR のコードは、ホストがプラグインの宣言の名前を前置する [docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md) に従う。

## 実装すること

### 呼び方と宣言

```toml
[plugins.tsv-table]
url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/tsv-table.wasm"
data = { sales = "data/sales.tsv", costs = "data/costs.tsv" }
```

```
@label sales
@tsv-table sales align=left,right,right
```

- `golem_describe` は、ブロックコマンド `tsv-table` と、データの名前 `*` を宣言する。インラインのコマンドとフィルタは持たない。
- 位置引数はちょうど一つで、表にするデータの名前（文字列）である。ないとき、二つ以上のとき、文字列でないときは `tsv-table-name` とする。
- キーワード引数は `align` だけである。ほかのキーは `tsv-table-key` とする。
- 字下げした行（本体）は取らない。あれば `tsv-table-body` とする。
- 名前のデータが渡されていなければ `tsv-table-no-data` とする。

列や行を選ぶ引数は持たない。
範囲の書き方（`a...b`）が rc4 で動いているので、範囲を引数に取る形はその採択を待って決める。

### TSV の読み方

`@table` の TSV と同じ規則で読む（[golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md)、[`parseTsv`](https://github.com/tett23/golem/blob/fa55dc76be6fef7189cb80883fd0bb0b0630911f/modules/golem-eval/src/Golem/Eval/File.hs#L1259)）。

- 文字コードは UTF-8 に限る。UTF-8 でなければ `tsv-table-utf8` とし、メッセージに最初の誤りの行の番号を書く。
- 先頭の BOM は読み飛ばす。
- 行の終わりは LF か CRLF である。LF の前にない CR は `tsv-table-cr` とする。
- ファイルの末尾の行の終わりを一つだけ捨てる。途中の空の行は、空のセルを一つ持つ行である。
- タブでセルを区切る。引用符もエスケープもなく、`"` と `\` は書いたままの文字である。
- 一行目が見出しの行である。見出しの行を持たない表は作らない（IR の表は見出しの行を持つ）。
- すべての行のセルの数は、見出しの行と同じでなければならない。違えば `tsv-table-cells` とし、メッセージに行の番号と二つのセルの数を書く。
- 空のファイル（BOM と行の終わりだけのものを含む）は `tsv-table-empty` とする。

セルは地の文として扱い、インラインの記法を解釈しない。
空のセルはインラインを持たない。
すべてのノードの位置は呼び出しの位置である。

`align` は `@table` の `align` と同じく、`left`、`center`、`right`、`default` をカンマで区切って列の順に並べる。
一つだけ書けばすべての列に当てる。
値の誤りと数の不一致は `tsv-table-align` とする。

誤りのあるときは、ブロックを一つも返さない。
diagnostic はすべてエラーであり、位置は呼び出しの位置である。

### 上限と速さ

`@table` の上限（[docs/adr/0043](0043-table-file-size-limits.md)）のうち、行の数（見出しの行を含めて 10,000）と一行のセルの数（256）はそのまま使う。
加えて、表のセルの合計を 50,000 まで、TSV の大きさを 8 MiB（8,388,608 バイト）までとする。
どれかを超えれば `tsv-table-limit` とし、メッセージに超えた上限と行の番号を書く。

二つの上限を足したのは、命令数の上限で止まらないためである。
命令数の上限を超えても G06009 として決定的に止まるが、メッセージ（「命令数の上限を超えました」）からは、表のどこを減らせばよいかがわからない。
プラグインの上限を命令数の上限の内側に置けば、利用者が読む diagnostic はいつもプラグインの上限のほうになる。

上限は、命令数を測って決めた。
golem-plugin の `loadPluginWith` で fuel を変え、通る最小の fuel を二分探索で求めた（Apple M1 Max、macOS、`tsv-table.wasm` は `opt-level = "s"`）。
8 MiB を超える三行は、大きさの上限を 16 MiB にした版で測った。

| TSV | 大きさ | 命令数 |
|---|---:|---:|
| 1 行、1 列 | 5 B | 47,951 |
| 100 行、4 列 | 2,368 B | 2,893,446 |
| 10,000 行、4 列 | 315,576 B | 288,330,077 |
| 1,000 行、4 列、セルに `x` を 4,000 字 | 16.0 MB | 398,925,781 |
| 10,000 行、5 列、セルに `x` を 320 字 | 16.4 MB | 754,882,812 |
| 10,000 行、5 列、セルに `あ` を 107 字 | 16.4 MB | 1,094,726,562 |
| 10,000 行、5 列、セルに `あ` を 52 字 | 8.2 MB | 719,726,562 |

命令数は、おおよそ「セル一つあたり 7,000」と「ASCII の 1 バイトあたり 24、日本語の 1 バイトあたり 45」の和である。
セル一つあたりの大半は、セルごとの `String`、IR の値、CBOR の値の割り当てと、応答の符号化である。
データを要求から読み出すだけなら、1 バイトあたり 3 命令で済んだ。

16 MiB のままでは、日本語の 50,000 セルの表が命令数の上限を超えた（上の表の六行め）。
8 MiB にすると、最も重い形（日本語、50,000 セル）で約 7.2 億命令になり、上限との差は約 28% ある。
golem-driver のテストは、この形の表が G06009 にならないことを確かめる。

最初の版は CR を一バイトずつ探していた。
`match_indices` で語の単位で探すように変えると、16 MiB の ASCII の表で 9.8 億命令が 7.5 億命令に減った。
`opt-level = 3` で作り直すと、セル一つあたりの命令数は約 15% 減った。
見本のプラグインの profile はほかのプラグインと共有なので、この ADR では変えない。

組むのにかかる時間は、`golem check` と `golem build --target text` の壁時計の時間で `@table` と比べた（一回の計測、4 列の表、ほかの原稿はなし）。

| 原稿 | `@tsv-table` | `@table` |
|---|---:|---:|
| 100 行の表を一つ | 0.13 秒 | 0.13 秒 |
| 10,000 行の表を一つ | 0.30 秒 | 0.16 秒 |
| 100 行の表を 1,000 個 | 1.49 秒 | 0.58 秒 |
| 10,000 行の表を 10 個 | 1.48 秒 | 0.45 秒 |
| 10,000 行の表を 100 個 | 13.84 秒 | 3.53 秒 |
| 1,000 行の TSV を 100 個のデータとして渡し、表を一つずつ | 1.64 秒 | 0.52 秒 |

表一つあたりでは、`@table` の三倍から四倍かかる。
呼び出しごとにインスタンスを作り、要求と応答を CBOR で往復し、出力を検査するからである。
本の表の数（数十）と大きさ（数百行）では、ビルドの時間に目立つ差は出ない。

### 置き場所と配布

[docs/adr/0106](0106-sample-plugins-in-rust.md) のとおり、`plugins/tsv-table/` に置き、`plugins/wasm/tsv-table.wasm` をコミットする。
依存するのは `golem-plugin-sdk` だけで、外のクレートを使わない。

## 実装しないこと

- CSV。`@table` が読めるので、見本としては TSV で足りる。
- 引用符で囲んだセル、セルの中のタブと改行。TSV の規則（IANA text/tab-separated-values）にないからである。
- セルをインラインの記法として読むこと（`@table` の `cells=markup` にあたる）。
- 見出しの行のない表。
- 列や行の選択、並べ替え、集計。
- `opt-level` を上げること、CBOR の値を経ずに応答を直接書くこと。どちらも命令数を減らせるが、上の上限で困っていない。
- `@table` を置き換えること。

## テスト設計

テストは実装と同時に書いた。

Rust の単体テスト（`plugins/tsv-table/src/lib.rs`、`cargo test -p tsv-table`）では、次のことを確かめる。

- CRLF、BOM、末尾の行の終わりのない TSV、`"` と `\`、途中の空の行、末尾の空の行、空のセルを `@table` と同じに読む。
- 空、行の終わりだけ、BOM だけ、セルの数の不一致（行の番号と数）、LF の前にない CR（行の番号）、UTF-8 でないバイト（行の番号）を拒む。
- 10,000 行は通り、10,001 行めで止まる。256 セルは通り、257 セルで止まる。10,000 行 5 列は通り、6 列は 8,334 行めで合計の上限に当たる。8 MiB を 1 バイト超えると止まる。
- `align` の一つの値、空白を含む三つの値、数の不一致、未知の値、空の値。
- 表のノードの位置が呼び出しの位置で、ラベルを持たない。
- `tsv-table-name`（なし、二つ、整数）、`tsv-table-no-data`、`tsv-table-key`、`tsv-table-align`、`tsv-table-empty`、`tsv-table-cells`、`tsv-table-body` のコード。誤りのときにブロックを返さない。

golem-driver のテスト（`modules/golem-driver/test/PluginsSpec.hs`）では、`plugins/wasm/tsv-table.wasm` を使い、次のことを確かめる。

- `@tsv-table sales align=left,right,center` と `@table src=data/sales.tsv align=left,right,center` が、揃えとセルの文字列の同じ表になる（`"`、`\`、空のセルを含む）。
- 表とそのセルの位置が呼び出しの行である。
- 二つのデータから二つの表を組む。`@label` が表に付く。箇条書きの項目の中に置ける。
- TSV の誤りとデータの名前の誤りが、プラグインの diagnostic として、その順に報告され、表を作らない。
- 64 MiB のデータを渡すと、トラップせずに `tsv-table-limit` になる。
- 日本語の 8 MiB、50,000 セルの TSV が G06009 にならず、表になる。
- `golem build --target text` の出力にセルの文字列が入る。

手で確かめたこと：`golem new` で作ったプロジェクトに `tsv-table` を宣言し（キャッシュと `plugins.lock` は手で置いた）、二つの TSV から本文と箇条書きの項目に表を組んで、`golem build --target pdf` で PDF にした。
同じ表を `@table` に変えた PDF と、`/ID` を除いて同じバイト列だった。
上の時間と命令数も、この手順で測った。

## トレードオフ

`@table` と同じ規則で読むので、利用者は二つの読み方を覚えずに済む。
その代わり、プラグインならではの読み方（CSV の方言、列の選択）を見本では示さない。

上限が `@table` と違う（16 MiB に対して 8 MiB、セルの合計の上限がある）。
同じ TSV が `@table` では表になり、`@tsv-table` ではならないことがある。
上限を揃えるには、命令数の上限を上げるか、プラグインの命令数を減らす必要がある。
前者はほかのプラグインの暴走の検出を遅らせ、後者は見本の簡潔さを損なうので、上限の違いを受け入れた。

diagnostic の位置が呼び出しの行に限られるので、TSV のどの行が誤っているかは、メッセージの行の番号で探すことになる。
`@table` なら誤りの行に跳べる。
データのファイルの中の位置を指せるようにするかは、[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md) で決める。

## 決めたことの記録

- **上限の違い**（メンテナー、2026-10-29）：8 MiB とセルの合計 50,000 個の上限が `@table` と違うことを、当面は受け入れる。上限の境界を調べて揃えるかは、[docs/roadmap.md](../roadmap.md) の「未決事項」に置いた。

## 参考文献

- IANA, Media Type text/tab-separated-values. https://www.iana.org/assignments/media-types/text/tab-separated-values
- wasmtime, `Config::consume_fuel`. https://docs.wasmtime.dev/api/wasmtime/struct.Config.html#method.consume_fuel
