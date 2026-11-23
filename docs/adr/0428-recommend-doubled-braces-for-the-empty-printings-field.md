# ADR 0428: [printings] の空の欄の直し方も、{{ と }} を勧める

Status: accepted-pending

## 文脈

`style.toml` の `[printings]` の `format` では、文字としての波括弧を `{{` と `}}` で書く（[root ADR 0375](0375-printings-format.md)）。
[root ADR 0424](0424-fix-the-low-findings-of-the-audit-that-need-an-adr.md) は、閉じていない `{`（G03267）と、対応する `{` のない `}`（G03268）のメッセージを、`{{` と `}}` を勧める形に直した。

一方、空の欄 `{}`（G03269）の diagnostic の一覧の説明は、今も `\{` と `\}` を勧めている。
G03269 は 0424 の対象に入っていなかったので、同じ書式の三つの誤りで、勧める書き方がそろっていない。
この ADR は、G03269 の説明を G03267 と G03268 にそろえる。

## 調査した事項

origin/main（[522b1b68c](https://github.com/tett23/golem/commit/522b1b68cf9bbc30c3333ae2d99f8b858747cccb)）で、次のことを確かめた。

- docs/diagnostics.md の G03269 の項（8691 行から）は、主な原因に「文字の `{}` をエスケープしなかった」、直し方に「欄の名前を書くか、文字の `{` と `}` を `\{` と `\}` と書く」と書いている。
  ADR の行は、0413 と 0375 だけを挙げる。
- 同じ一覧の G03267 と G03268 は、主な原因に「文字の `{` を `{{` と書かなかった」と書き、直し方で `{{` と `}}` を勧めている。
  ADR の行には、文言を直した 0424 も挙げている。
- G03269 を選ぶのは [Style.hs#L2965](https://github.com/tett23/golem/blob/522b1b68cf9bbc30c3333ae2d99f8b858747cccb/modules/golem-project/src/Golem/Project/Style.hs#L2965) である。
  メッセージ `空の差し込み {} があります` は [Format.hs#L133](https://github.com/tett23/golem/blob/522b1b68cf9bbc30c3333ae2d99f8b858747cccb/modules/golem-numerals/src/Golem/Numerals/Format.hs#L133) が作り、文字の波括弧の書き方には触れていない。
- `[printings]` の `format` は `{{` と `}}` を文字の波括弧に読み、`\{` と `\}` もどの書式でも文字の波括弧に読む（[Format.hs#L116-L121](https://github.com/tett23/golem/blob/522b1b68cf9bbc30c3333ae2d99f8b858747cccb/modules/golem-numerals/src/Golem/Numerals/Format.hs#L116-L121)）。
- 仕様書は、`[printings]` の `format` だけが `{{` と `}}` を今の書き方として読むと書き（2208 行）、G03267 と G03268 のメッセージがそれを勧めると書いている（2215 行）。
  G03269 の説明については書いていない。
- `golem explain` は、docs/diagnostics.md の組み込みの写しの項を、直し方の段まで出す。
  写しが docs/diagnostics.md と同じかは、CI と golem-driver の `DiagnosticsSpec.hs` が確かめる。
- マニュアルの付録 E は、G03264 から G03271 を一つの項にまとめていて、G03269 の直し方として `\{` を勧めていない。
  その項は、G03267 と G03268 のメッセージが `{{` を勧めることと、`\{` と `\}` とも書けることを書いており、この ADR の後も正しい。

指示者は 2026-11-23 に、この ADR を書くよう求めた。

## 実装すること

docs/diagnostics.md の G03269 の項を、次のように直す。

- 主な原因の「文字の `{}` をエスケープしなかった」を、「文字の `{}` を `{{}}` と書かなかった」にする。
- 直し方を、「欄の名前を書くか、文字の `{` と `}` を `{{` と `}}` と書く」にする。
- ADR の行に、直し方を直したこの ADR を足す。

G03269 のメッセージは変えない。
メッセージは、文字の波括弧の書き方に触れていないためである。

`golem explain` が出す文は docs/diagnostics.md の写しなので、`scripts/gen-embedded.sh` で写しを作り直す。
仕様書には、メッセージの文とは別の文として、「diagnostic の一覧の G03267 から G03269 の直し方は、`[printings]` の `format` の文字の波括弧を `{{` と `}}` で書くよう勧める」と、この ADR へのリンクを付けて書き足す。
マニュアルの付録 E は直さない。

### ステータスの行

どの ADR のステータスの行も変えない。
0375 の決定（文字の波括弧を `{{` と `}}` で書く）に合わせるだけで、0413 と 0424 が決めたコードとメッセージも変えないためである。

## 実装しないこと

`[printings]` の `format` が `\{` と `\}` を読むことは変えない。
G03269 のメッセージと、ほかの書式（柱、リストの番号、注の印など）の文言は変えない。
新しい diagnostic のコードを足さない。

## 不変条件

- I1: `golem explain G03269` の出力の主な原因と直し方の段は `{{` と `}}` を勧め、`\{` と `\}` を勧めない。
- I2: `golem explain G03267` と `golem explain G03268` の出力は、この ADR の前と同じである。
- I3: `[printings]` の `format` に `{}` を含む入力の G03269 のメッセージは、この ADR の前と同じである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `golem explain G03269` | 主な原因と直し方が `{{` と `}}` を勧める | I1 |
| `golem explain G03267` | この ADR の前と同じ | I2 |
| `golem explain G03268` | この ADR の前と同じ | I2 |
| `format = "{}"` | 今と同じ G03269 のメッセージ | I3 |
| `format = "a{}b"` | 今と同じ G03269 のメッセージ | I3 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0428 I1 から I3 を名前の先頭に置いたテストを足す。
I1 と I2 は、golem-driver の `DiagnosticsSpec.hs` の `explainTests` で、`lookupExplanation` が返す `exBody` の主な原因と直し方の段を確かめる。
I2 は、変える前の段を期待として書き、変えた後も一致することを確かめる。
I3 は、golem-project の `StyleCauseCodesSpec.hs` の G03269 の行と、`a{}b` の新しい行が、変える前と同じメッセージで通ることで確かめる。
実装の前に落ちるのは I1 だけで、I2 と I3 は変えていないことを確かめるテストである。

## トレードオフ

`\{` と `\}` も `[printings]` の `format` で使えるので、今の説明は誤りではない。
それでも、同じ書式の三つの誤りで勧める書き方がそろっていないと、読み手は二つの書き方のどちらを使えばよいか迷う。
0375 が `{{` と `}}` を `[printings]` の書き方と決めたので、それにそろえる。

## 参考文献

- [root ADR 0375](0375-printings-format.md)
- [root ADR 0413](0413-new-codes-for-font-axes-and-printing-formats.md)
- [root ADR 0424](0424-fix-the-low-findings-of-the-audit-that-need-an-adr.md)
