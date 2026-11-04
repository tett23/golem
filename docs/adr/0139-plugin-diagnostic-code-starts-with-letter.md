# ADR 0139: プラグインの diagnostic のコードを英小文字で始める

ステータス: 採択

## 文脈

[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md) は、プラグインが返す diagnostic のコードを `<英小文字、数字、- の列>` とし、ホストが `<プラグインの宣言の名前>/<コード>` の形に組み立てると決めた。
実装は、この文言のとおり、空でなく、英小文字、数字、`-` だけからなる列を通す（[`pluginCode`](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-plugin/src/Golem/Plugin.hs#L816-L819)）。
先頭の文字は区別しないので、`-`、`0`、`--`、`404` も通る。
実装者はこれを申告し、2026-11-04 の監査（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-08）は、ADR の文言には忠実だとした。

一方、プラグインの宣言のほかの名前は、どれも英小文字で始まる。

- データの名前（[docs/adr/0105](0105-plugin-data.md)、[`dataName`](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-plugin/src/Golem/Plugin.hs#L201-L207)）
- 画像の名前（[docs/adr/0123](0123-figures-from-plugins.md)。データの名前と同じ形）
- ブロックコマンドの名前（[docs/adr/0122](0122-block-commands-in-plugins.md)）

監査は、コードだけが緩いことを「緩い規則より厳しい規則」の原則から不ぞろいとし、厳しくするなら修正の ADR が要るとした。

先頭の `-` と数字を許す利点は見当たらない。
`glossary/-` や `x/404` は、書き手がコードとして読み、`golem explain` に渡し、CI のログで探すには紛らわしい。
今の見本のプラグインのコードは、どれも英小文字で始まる。
プラグインの ABI 8 はまだリリースしていない（v0.1.0-rc3 は 7）ので、規則を狭めても、リリースしたプラグインは壊れない。

## 実装すること

プラグインの diagnostic のコードを、データの名前と同じ形に限る。

- 英小文字で始まり、英小文字、数字、`-` だけからなる。
- 形の誤りは、今と同じく不正な出力（G06009、`診断のコードの形が不正です: <コード>`）とする。
- コマンド、ブロックコマンド、フィルタの diagnostic と、`golem_check_data` の diagnostic（[docs/adr/0120](0120-plugin-data-check-at-load.md)）のすべてに当てる。今と同じく `pluginCode` の一か所で判定する。
- 判定には `dataName` を使う。名前の形の規則を一つにし、二つの関数が食い違わないようにする。

ABI のバージョンは 8 のままとする（[docs/adr/0052](0052-plugin-abi-version-bump-rule.md)）。

### 文書

- docs/specifications.md と docs/diagnostics.md の「`<英小文字、数字、- の列>`」を、「英小文字で始まり、英小文字、数字、`-` だけからなる列」に改める。仕様書の 2070 行めと「プラグイン」の節、diagnostics.md の冒頭（今の 10 行め）と G06009 の節である。
- manual-dev の 05-plugins.gm のコードの形の記述を、同じ文に改める。
- [docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md) のステータスの行に、「コードの先頭の文字は [ADR 0139](0139-plugin-diagnostic-code-starts-with-letter.md)」を足す。

## 実装しないこと

- `--` の連続や末尾の `-` を拒むこと。データの名前も拒んでいない。拒むなら、データの名前、画像の名前と合わせて別に決める。
- コードの長さの上限。
- `golem explain` が `/` の前の部分を何でも受けること（監査の F-10）。マニフェストの宣言の名前に形の規則がないので、ここでは扱わない。

## テスト設計

先に次のテストを書き、今の main で失敗することを確かめてから実装する。

- golem-plugin の `ResponseSpec` の `a code of Golem, an upper case letter, a / or nothing is bad output`（[ResponseSpec.hs の 126 行めから 132 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-plugin/test/ResponseSpec.hs#L126-L132)）の不正なコードの列に、`-`、`-x`、`0`、`404`、`2x` を足す。今の main では、どれも通って失敗する。
- golem-plugin の `CheckDataSpec` で、`golem_check_data` の応答の `404` と `-x` が同じメッセージの不正な出力になる。
- `no-key-2`、`a`、`a-` が今と同じく通る。

`cargo test --locked`（`plugins/`）と golem-driver の `PluginsSpec` が変えずに通ることで、見本のプラグインのコードが新しい規則に合うことを確かめる。

## トレードオフ

数字で始まるコード（HTTP の状態の番号の `404` など）を使いたいプラグインは、`http-404` のように英字を前に付ける必要がある。
コードは利用者が読み、探すための名前なので、名前の規則に揃える利点のほうが大きい。

規則を狭めるので、リリースの前にこの形のコードを返すプラグインを書いた人がいれば、その出力は不正になる。
ABI 8 はまだリリースしていないので、影響はリポジトリの中の wat と見本に限られ、テストで確かめられる。

## 決めたことの記録

- **採択**：メンテナーが、この ADR の案のとおり採択した（2026-11-04）。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-08）
