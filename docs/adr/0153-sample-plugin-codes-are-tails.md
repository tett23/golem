# ADR 0153: 見本のプラグインの ADR の表に書いたコードを、プラグインが返す後ろの部分として読む

ステータス: 採択

## 文脈

[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md) は、プラグインが返す diagnostic のコードを後ろの部分だけとし、ホストがその前に `<プラグインの宣言の名前>/` を置くと決めた。
`lookup` と宣言したプラグインの `no-key` は、`lookup/no-key` と表示される。

見本のプラグインの ADR のうち五つは、コードを、プラグインの名前を前に付けた形で表に書いている。

| ADR | 表の書き方 | 今のプラグインが返すもの |
|---|---|---|
| [0125](0125-kansuji-plugin-overrides-number-text.md)（kansuji） | `kansuji-arity`、`kansuji-not-number` など | `arity`、`not-number` など |
| [0128](0128-auto-tcy-filter.md)（auto-tcy） | `auto-tcy-split`、`auto-tcy-config-key` など | `split`、`config-key` など |
| [0129](0129-tsv-table-plugin.md)（tsv-table） | `tsv-table-name`、`tsv-table-cells` など | `name`、`cells` など |
| [0130](0130-sou-ruby-plugin.md)（sou-ruby） | `sou-ruby-no-words`、`sou-ruby-dict`、`sou-ruby-unread` | `no-words`、`dict`、`unread` |
| [0131](0131-first-occurrence-ruby-plugin.md)（first-ruby） | `first-ruby-no-words`、`first-ruby-utf8`、`first-ruby-tsv` | `no-words`、`utf8`、`tsv` |

0125、0128、0129 は、表の書き方とは別に、コードは 0108 に従うと本文か「決めたことの記録」に書いた。
0128 は、プラグインが `split` などの後ろの部分を返すと明記した。
実装は、最初から後ろの部分を返した。

0130 と 0131 の実装は、はじめ表の字面のとおりに名前を含むコードを返した。
ホストが前置するので、利用者には `sou-ruby/sou-ruby-unread` と見え、`[plugins.ruby]` と宣言すれば `ruby/sou-ruby-unread` と見えた。
2026-11-04 の一度めの監査（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-38）がこれを指摘し、PR [#504](https://github.com/tett23/golem/pull/504) が後ろの部分だけを返すように直した（[sou-ruby/lib.rs#L152-L189](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/plugins/sou-ruby/src/lib.rs#L152-L189)、[first-ruby/lib.rs#L78-L107](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/plugins/first-ruby/src/lib.rs#L78-L107)）。
golem-driver のテストは、表示される形を `sou-ruby/unread`、`sou-ruby/dict`、`first-ruby/tsv`、`first-ruby/no-words` で固定している（[PluginsSpec.hs#L932-L959](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/test/PluginsSpec.hs#L932-L959)）。
仕様書もこの形で書かれている。

PR #504 は、0125、0128、0129 と同じ読み替えだとして、ADR を変えなかった。
直したことそのものは 0108 に沿う。
しかし、0130 と 0131 には 0108 に従うとする一文がなく（0131 の一文は表の後にあり、表の字面と食い違う）、ステータスの行は素の `採択` のままである。
この読み替えに触れているのは、[docs/adr/0136](0136-missing-plugin-data-at-load.md) の「ルビの二つの見本のコードの前置き（監査の F-38）を別の変更が直すときは、その形に従う」という条件の一文だけである。
0130 と 0131 を読む人は、実機が出さないコードを見る。
2026-11-04 の二度めの監査（[PR #525](https://github.com/tett23/golem/pull/525) の docs/audits/2026-11-04-rc4-followup-conformance.md の F-22）は、これを記録のない決定とした。

コミット済みの ADR は、ステータスの行を除いて変えられない。
決定と違う形にしたことは、新しい ADR とステータスの行の句で記録する。

## 実装すること

### 読み方

見本のプラグインの ADR の表と本文に `<プラグインの名前>-<後ろの部分>` と書いたコードは、プラグインが `<後ろの部分>` を返し、ホストが `<宣言の名前>/<後ろの部分>` と表示するものと読む。
`<プラグインの名前>` は、ADR が例に使った宣言の名前で、コードの一部ではない。

対象は 0125、0128、0129、0130、0131 の五つである。
0130 と 0131 は、PR #504 の後の今の実装がこの読み方に合う。
0125、0128、0129 は、実装の初めからこの読み方に合っていた。

### コードの対応

0130 と 0131 の表と本文のコードは、次のとおりに読む。

| ADR の字面 | プラグインが返すもの | 既定の宣言の名前での表示 |
|---|---|---|
| `sou-ruby-no-words` | `no-words` | `sou-ruby/no-words` |
| `sou-ruby-dict` | `dict` | `sou-ruby/dict` |
| `sou-ruby-unread` | `unread` | `sou-ruby/unread` |
| `first-ruby-no-words` | `no-words` | `first-ruby/no-words` |
| `first-ruby-utf8` | `utf8` | `first-ruby/utf8` |
| `first-ruby-tsv` | `tsv` | `first-ruby/tsv` |

### ステータスの行の句

次の句を、それぞれの ADR のステータスの行に足す。
今のステータスの行はどれも `採択` である。

- [docs/adr/0130](0130-sou-ruby-plugin.md)：`採択→diagnostic のコードは後ろの部分（`no-words`、`dict`、`unread`）を返すことは [ADR 0153](0153-sample-plugin-codes-are-tails.md)`
- [docs/adr/0131](0131-first-occurrence-ruby-plugin.md)：`採択→diagnostic のコードは後ろの部分（`no-words`、`utf8`、`tsv`）を返すことは [ADR 0153](0153-sample-plugin-codes-are-tails.md)`
- [docs/adr/0125](0125-kansuji-plugin-overrides-number-text.md)、[0128](0128-auto-tcy-filter.md)、[0129](0129-tsv-table-plugin.md)：`採択→表のコードを後ろの部分として読むことは [ADR 0153](0153-sample-plugin-codes-are-tails.md)`

0125、0128、0129 の句は、決定を変えるものではなく、読み方を一か所に集めるものである。
三つの本文はすでに 0108 に従うと書いているので、句を足さなくても決定は辿れる。
足すのは、表を読む人が、ステータスの行だけを見て字面と表示の違いに気づけるようにするためである。

[docs/adr/0136](0136-missing-plugin-data-at-load.md) の条件の一文は、PR #504 で満たされた。
0136 のステータスの行は変えない。

### 文書

仕様書、docs/diagnostics.md、両マニュアルは、すでに後ろの部分と表示の形で書かれている。
変えない。

## 実装しないこと

- 0130 と 0131 の表と本文を書き換えること。コミット済みの ADR は、ステータスの行のほかは変えられない。
- `no-command`（コマンドとして呼ばれたフィルタのコード。sou-ruby、first-ruby、auto-tcy が返す）を ADR に記録すること。0128 は `auto-tcy-no-command` を表に持つが、0130 と 0131 にはない。一度めの監査の F-41 の範囲で、ここでは扱わない。
- bar-chart のコードの名前を記録すること。二度めの監査の「横断的な所見」が挙げた別の件である。
- コードの形やプラグインの振る舞いを変えること。

## テスト設計

コードは変えないので、新しい自動テストはない。
次を確かめる。

- 実装のプルリクエストで、`adr-guard check-status` と `adr-guard links` が通ること。足した句のリンクが壊れていないこと。
- `docs/adr/` と `docs/audits/` のほかに、`sou-ruby-no-words` のような名前を前に付けた形のコードが、リポジトリのどこにもないこと（`rg '(kansuji|auto-tcy|tsv-table|sou-ruby|first-ruby)-(no-words|unread|utf8|tsv|dict|arity|not-number|split|config|name|cells)'` が `docs/adr/` と `docs/audits/` の外に何も出さない）。2026-11-04 の main（4f86b945）では何も出ないことを、この草案を書くときに確かめた。
- 表示の形は、golem-driver の `PluginsSpec` と `plugins/` の `cargo test --locked` がすでに固定している。変えずに通ること。

## トレードオフ

- 0130 と 0131 の表は、字面のまま残る。読む人は、ステータスの行の句からこの ADR に来て、読み替えを知る必要がある。ADR の不変を保つための代価である。
- 0125、0128、0129 に句を足すと、決定の変わっていない ADR のステータスの行が長くなる。足さなければ、五つの ADR のうち二つだけに句があり、同じ書き方の表の読み方が ADR によって違って見える。そろえるほうを選ぶ。
- PR #504 の変更は、ADR なしにマージされた後で、この ADR で記録される。順序は逆だが、変更そのものは 0108 に沿い、監査も求めたものである。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-04）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-38、F-41）
- [PR #525](https://github.com/tett23/golem/pull/525) の docs/audits/2026-11-04-rc4-followup-conformance.md（F-22）
- PR [#504](https://github.com/tett23/golem/pull/504)（マージのコミット 26f7171e）
- [docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md)、[docs/adr/0125](0125-kansuji-plugin-overrides-number-text.md)、[docs/adr/0128](0128-auto-tcy-filter.md)、[docs/adr/0129](0129-tsv-table-plugin.md)、[docs/adr/0130](0130-sou-ruby-plugin.md)、[docs/adr/0131](0131-first-occurrence-ruby-plugin.md)、[docs/adr/0136](0136-missing-plugin-data-at-load.md)
