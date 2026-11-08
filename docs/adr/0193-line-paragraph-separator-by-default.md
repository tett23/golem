# ADR 0193: 段落の区切り方の既定を改行の様式にする

ステータス: 採択→決定性の検査の期待値の一行は [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)

## 文脈

[docs/adr/0013](0013-paragraph-separator.md) は、段落の区切り方を `manifest.toml` の `[source]` の `paragraph-separator` で選べるようにした。
値は、空行で段落を区切る `"blank-line"`（空行の様式）と、改行ひとつで区切る `"line"`（改行の様式）の二つである。
[ADR 0013](0013-paragraph-separator.md) は、既定を `"blank-line"` とし、`[metadata]` の `language` からは推定しないと決めた。
既存の原稿の出力を変えないためと、言語を変えただけで段落の数が変わるのを避けるためである。
`golem new` の雛形にも `[source]` を書かず、`--language ja` でも空行の様式のままとした。

既定は `defaultSourceSettings` の一か所で決まる（[`SourceSettings.hs`](https://github.com/tett23/golem/blob/6086e7c509e3ca73a23f975899c05ada066282d6/modules/golem-parser/src/Golem/Parser/SourceSettings.hs#L24-L25)）。

日本語の原稿は、一つの段落を一行に書き、改行で段落を区切ることが多い。
Golem の fixture でも、日本語の本は、蟹工船と、パブリックドメインの日本語の五冊（haru-to-shura、ichiaku-no-suna、koya-hijiri、taira-no-masakado、ushiyama-hotel）が、どれも `paragraph-separator = "line"` を書いている。
Golem の使い手は日本語の本を書くことが多いので、メンテナーは既定を改行の様式にすると決めた（「決めたことの記録」）。

### 既定に頼っているプロジェクト

`paragraph-separator` を書いていないプロジェクトは、既定が変わると、段落の区切り方が変わる。
空行の様式で書いた原稿で、一つの段落を複数の行に折り返していれば、改行の様式では行ごとに別の段落になる。
リポジトリの中で既定に頼っているのは、次のものである（`manifest.toml` を `rg` で調べた。2026-11-07、`6086e7c5`）。

- 使い手のマニュアル（`manual/`）と開発者のマニュアル（`manual-dev/`）
- fixture の bibliographies、emet-samples、figures、functions、sample、tempest
- パブリックドメインの fixture の elements-of-style、frogs、merry-wives、nightmare-abbey、snark

## 実装すること

### 既定を変える

- `defaultSourceSettings` の既定を `LineSeparated` にする。
- ファイルの中の上書き、章の項目、`[source]`、既定の順で最初に見つかった値を使う規則（[ADR 0013](0013-paragraph-separator.md)）は変えない。既定だけが変わる。
- `[metadata]` の `language` からは推定しない（[ADR 0013](0013-paragraph-separator.md) のまま）。英語の本も、`paragraph-separator` を書かなければ改行の様式になる。

### 既存のプロジェクトの出力を変えない

- 上の「既定に頼っているプロジェクト」のすべての `manifest.toml` の `[source]` に、`paragraph-separator = "blank-line"` を書き足す（「メンテナーが決めること」の 1）。原稿は書き換えない。
- これで、マニュアルと fixture の出力のバイト列、見た目の回帰テストの参照、ゴールデン、決定性の検査の期待値は変わらない。

### 書いていないことを知らせる

- `[source]` に `paragraph-separator` を書いていないプロジェクトには、notice（G03120、`段落の区切り方を書いていないので、改行の様式（paragraph-separator = "line"）で読みます`）を出す（「メンテナーが決めること」の 2）。位置は `manifest.toml` の先頭とする。原稿の読み方が既定に依ることを、既定が変わったことを知らない書き手に知らせるためである。
- 章の項目かファイルの中の上書きで、すべての原稿の値が決まっていても、`[source]` に書いていなければ出す。判定を `manifest.toml` だけで決めるためである。
- G03023（`style.toml` がない）と同じく notice とし、`silence-notices` で抑えられる。

### `golem new`

- `golem new` の雛形の `manifest.toml` に、`[source]` と `paragraph-separator = "line"` を書く（「メンテナーが決めること」の 3）。`--language ja` でも `en` でも同じとする。新しいプロジェクトが G03120 を出さないようにし、読み方を設定の中で見えるようにするためである。

### 文書

- [docs/specifications.md](../specifications.md) と [docs/markup.md](../markup.md) の「既定は空行の様式である」を、改行の様式に直す。
- 使い手のマニュアル（第 4 章と付録 A、付録 B）の `paragraph-separator` の説明で、既定と例を直す。例は、改行の様式を既定とし、空行の様式を書く場合の例に入れ替える。マニュアルの見た目の参照（`scripts/visual/pages/`）は、CI の成果物から写して直す。
- [docs/diagnostics.md](../diagnostics.md) に G03120 を加える。
- [ADR 0013](0013-paragraph-separator.md) のステータスの行に、既定と `golem new` の雛形をこの ADR が改めたことを書く。

## 実装しないこと

- 既定を `[metadata]` の `language` で変えること（[ADR 0013](0013-paragraph-separator.md) のまま）。
- マニュアルと fixture の原稿を改行の様式に書き換えること。
- `paragraph-separator` の値を増やすこと。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

- golem-parser：`defaultSourceSettings` が `LineSeparated` であること。
- golem-project：`[source]` のない `manifest.toml` の `manifestSource` が改行の様式になること。`[source]` に `paragraph-separator` を書いた値が、今のとおり使われること。
- golem-driver：`paragraph-separator` を書いていないプロジェクトで G03120 が出て、書いたプロジェクト（`"blank-line"` と `"line"` の両方）で出ないこと。章の項目だけに書いたプロジェクトでも出ること。`silence-notices` で抑えられること。二行に折り返した段落が、書いていないプロジェクトでは二つの段落になること。
- golem-cli：`golem new` の `ja` と `en` の雛形が `paragraph-separator = "line"` を持ち、`golem build` が G03120 を出さないこと。
- 既存のプロジェクト：マニュアルと fixture の出力、見た目の回帰テストの参照、ゴールデン、決定性の検査の期待値が変わらないこと。

## トレードオフ

`paragraph-separator` を書いていない既存のプロジェクトは、Golem を上げると段落の区切り方が変わる。
空行の様式で段落を折り返して書いた原稿は、段落が細かく分かれる。
G03120 で書いていないことを知らせ、原稿を書き換えずに `"blank-line"` を一行書けば元に戻る。
1.0.0 より前なので、互換を壊してよい（[docs/adr/0174](0174-compatibility-promises-for-1-0.md) の草案の、1.0.0 の前の扱い）。

英語の本も既定では改行の様式になる。
英語の原稿は、段落の中で改行して折り返すことが多いので、英語の本は `"blank-line"` を書くことになる。
言語で既定を変えれば避けられるが、言語を変えただけで段落の数が変わる問題（[ADR 0013](0013-paragraph-separator.md) が避けたこと）が戻る。

G03120 は、`paragraph-separator` を書くまで出続ける。
既定に任せたい書き手には余計な notice だが、`silence-notices` で抑えられ、`golem new` で作ったプロジェクトでは出ない。

## 決めたことの記録

- **既定を改行の様式にすること**（2026-11-07、メンテナー）：日本語を書くことが多いので、`[source]` の `paragraph-separator = "line"` を既定にすると決めた。
- **残りの項目**（2026-11-07、メンテナー）：「メンテナーが決めること」の 1 から 3 を、推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **既定に頼っているリポジトリの中のプロジェクト**：決めた。推奨のとおり、マニュアルと fixture の `manifest.toml` に `paragraph-separator = "blank-line"` を書き足し、出力を変えないことである。採らなかった案は、原稿を改行の様式に書き換えることである。出力が変わらないことを確かめにくく、この ADR の目的（既定の変更）と関係のない差分が大きくなる。
2. **書いていないことを知らせるか**：決めた。推奨のとおり、notice（G03120）を出すことである。既定が変わったことを知らない書き手が、段落が細かく分かれた理由に気付けるようにする。採らなかった案は、(a) 何も出さないこと（出力が黙って変わる。「緩い規則より厳しい規則」と、出力を黙って変えない原則に反する）、(b) エラーにして `paragraph-separator` を必ず書かせること（既定の意味がなくなる）、(c) 1.0.0 までの移行の期間だけ出すこと（期間の終わりを決める必要がある）である。
3. **`golem new` の雛形**：決めた。推奨のとおり、`[source]` と `paragraph-separator = "line"` を書くことである。[ADR 0013](0013-paragraph-separator.md) の「雛形に `[source]` を書かない」を改める。採らなかった案は、雛形に書かず既定に任せることである。新しいプロジェクトが G03120 を出すことになる。

## 参考文献

- [docs/adr/0013](0013-paragraph-separator.md)
- [docs/adr/0014](0014-in-file-settings.md)
