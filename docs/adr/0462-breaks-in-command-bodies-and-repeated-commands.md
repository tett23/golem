# ADR 0462: ブロックコマンドの本体の中の改ページと、続けて二度書いたコマンドの扱いをそろえる

Status: accepted-pending

## 文脈

[root ADR 0459](0459-take-the-next-block-as-the-body-without-indentation.md) と [root ADR 0460](0460-let-style-take-any-blocks-as-its-body.md) の実装（PR #1185）の後、二つの扱いが、コマンドによってそろっていないことが分かった。

一つは、ブロックコマンドの本体の中の、改ページの仲間（`@page-break`、`@column-break`、`@no-page-break`、`@need-lines`、`@page-lines`）、`@blank-line`、区切り（`@separator`、`---`）の扱いである。
`@style` の本体ではそのまま出力し、`@lang` の本体では G02059、G02071、G02093、G02159 にして捨てる。
`@frame` の本体では、書き方によって G02256 になるか、黙って消える。

もう一つは、一つのまとまりに同じコマンドを二度書いたときの扱いである。
どれも G02012 を出すが、`@style` は先に書いたものが、`@lang` と属性は後に書いたものが、エラーの後の評価で残る。

メンテナーは、2026-11-26 に、例外が増えるなら ADR で決めること、G02012 を出したうえでどちらかを残す扱いの意味が無いことを示した。
また、同じコードでも、当てはまる箇所ごとに一つずつ出すと決めた（[root ADR 0461](0461-report-the-diagnostics-that-follow-from-another-error.md)）。

この ADR は、二つの扱いを、本体の種類ごとの一つの規則にそろえる。

## 調査した事項

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）で、次のことを確かめた。
実行の結果は、impl-0459 のビルド（71172ba26）の `golem inspect --as ir` を、調べを受け持ったエージェントが動かしたものである。

- G02059、G02071、G02093、G02159 は `belowTop` が出す（[File.hs#L1833-L1841](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L1833-L1841)）。
  `belowTop` を使うのは二か所である。
  - ファイルの評価の最後の `nestedBreaks` は、最上位の改ページ、行アキ、区切りを残し、箇条書き、定義リスト、図版のキャプション、フレームの中を調べる（[File.hs#L1822-L1846](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L1822-L1846)）。
  - `@lang` の本体は、本体の各ブロックに `belowTop` を当てる（[File.hs#L1806-L1810](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L1806-L1810)）。
    これは [docs/adr/0187](0187-inline-language-switch.md) の「ブロックの `@lang`」が決めたことである。
- `@style` の本体は、評価した結果を平らにしてそのまま返す（[File.hs#L2151-L2162](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L2151-L2162)）。
  `.emet` のブロック関数とプラグインのブロックコマンドも、本体の結果を関数に渡し、関数の出力の改ページはその場の段に残る。
- 注の本文とフレームの中身は、段落のほかのブロックを、それぞれ G02141 と G02256 にする（[File.hs#L2004](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L2004)、[File.hs#L2039](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L2039)）。
  ただし、改ページを前に置いた段落は、評価の後で段落だけを残すので、改ページが黙って消える（[File.hs#L2034](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L2034)）。
- 実行の結果は次のとおりである。
  - `@lang en` の本体に `@page-break`、`@blank-line`、`@separator s`、段落：G02059、G02093、G02159 の三つで、段落だけが残った。
  - `@style body` の本体に同じ四つ：エラーなしで、改ページ、行アキ、区切りがそのまま残った。
  - `.emet` の `pub block` の本体に `@page-break` と段落：エラーなしで、改ページが残った。
  - `@frame f` の本体の `@page-break` と、空行の後の段落：G02256 になった。
  - `@frame f` の本体の `@page-break` と、そのすぐ次の行の段落：エラーなしで、改ページが黙って消えた。
- 一つのまとまりに二度書いたコマンドは、`once`、`repeated`、`dropped` で扱う（[File.hs#L1347-L1351](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L1347-L1351)）。
  G02012 は、先に同じ名前がある二つ目以降の各コマンドに出る。
  捨てるコマンドは、`@style` では後に書いたもの、ほかでは先に書いたものである。
  最初の `@style` を残すことは、[golem-eval ADR 0003](../golem-eval/adr/0003-evaluation-diagnostic-codes.md) が決めた（113 行）。
  0459 の境界の表も、`@style a`、`@style b`、段落を「G02012（今と同じ）」とする。

## 実装すること

### 本体の二つの種類

ブロックコマンドの本体を、その結果の置き方で二つに分ける。

- **結果をその場に置く本体**：`@style`、`@lang`、`.emet` のブロック関数、プラグインのブロックコマンドの本体。
  コマンドの結果は、コマンドを書いた位置のブロックの並びに置かれる。
- **入れ物を作る本体**：`@frame`、`@note`、`@endnote`、図版のキャプションの本体。
  コマンドの結果は、本体を中に持つ一つの入れ物で、本体のブロックはその入れ物の中に置かれる。

### 結果をその場に置く本体の中の改ページ、行アキ、区切り

結果をその場に置く本体の中の改ページ、行アキ、区切りは、誤りにせず、結果の同じ順の位置に残す。
置かれた後の位置が最上位でなければ（箇条書きの項目の中など）、今と同じく、ファイルの評価の最後の検査が G02059、G02071、G02093、G02159 にする。
そのため、`@lang` の本体の中の改ページは、`@style` の本体の中と同じく、最上位に置かれれば誤りにならない。

### 入れ物を作る本体の中の改ページ、行アキ、区切り

入れ物を作る本体の中の改ページ、行アキ、区切りは、今の検査のコードのまま、一つごとに報告して捨てる。
`@frame` の中身は G02256、`@note` と `@endnote` の本文は G02141、図版のキャプションは今の G02059、G02071、G02093、G02159 である。
単独のブロックとして書いたときも、段落の前に置いて同じまとまりにしたときも、同じく報告する。
改ページを黙って捨てる今の扱いは、この ADR でやめる。

### 二度書いたコマンド

一つのまとまりに、同じ属性か、同じ `@style` か `@lang` を二度以上書けば、先に同じものがある二つ目以降の各コマンドに、G02012 を一つずつ出す。
エラーの後の評価では、どのコマンドも、最後に書いたものを残す。
0459 の組み合わせ方では、後に書いたコマンドほど内側にあるので、0460 の「内側の段落スタイルを残す」と同じく、最後に書いた `@style` が残る。
0459 の境界の表の `@style a`、`@style b`、段落の行は、G02012 が一つ出ることは変わらず、残るスタイルが `b` になる。

### 文書

仕様書の、ブロックコマンドの本体の中の改ページ、行アキ、区切りの記述を、この ADR の二つの種類で書き改める。
`docs/diagnostics.md` の G02012、G02059、G02071、G02093、G02141、G02159、G02256 の説明を直す。

採択したら、次の ADR のステータスに記録する。
どの記録も `"by":["docs/adr/0462-breaks-in-command-bodies-and-repeated-commands.md"]` を持つ。

- [docs/adr/0017](0017-forced-page-breaks.md)：`{"part":"記法","kind":"replace"}`（ブロックコマンドの本体の中に置けないとした決まり）
- [docs/adr/0046](0046-blank-line-command.md)：`{"part":"記法","kind":"replace"}`（本体の形の `@style` の中を G02045 とした決まり）
- 0187：`{"part":"ブロックの `@lang`","kind":"replace"}`
- [golem-eval ADR 0003](../golem-eval/adr/0003-evaluation-diagnostic-codes.md)：`{"part":"ブロックコマンドと属性（`Golem.Eval.File`）","kind":"replace"}`（最初の `@style` を残す決まり）
- 0459：`{"part":"続けて書いたコマンドを一つのコマンドとして読む","kind":"supplement"}`
- 0460：`{"part":"本体のブロック","kind":"supplement"}`

## 実装しないこと

最上位の改ページ、行アキ、区切りの意味は変えない。
箇条書き、定義リストの中の扱いは変えない（今と同じく誤り）。
G02012、G02141、G02256 のコードと文言は変えない。

## 不変条件

- I1: 結果をその場に置く本体の中の改ページ、行アキ、区切りは、そのコマンドを書いた位置が最上位なら、どれも誤りにならず、結果の同じ順の位置に残る。
- I2: 入れ物を作る本体の中の改ページ、行アキ、区切りの数を k とすると、その入れ物の検査のコードの diagnostic がちょうど k 個出て、出力にそれらは残らない。
- I3: 一つのまとまりに同じコマンドを n 回書けば、G02012 がちょうど n − 1 個出る。
- I4: 二度書いたコマンドのエラーの後の評価では、最後に書いたコマンドが残る。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `@lang en` の本体に `@page-break` と段落 | 誤りなし。改ページと段落が残る | I1 |
| `@style body` の本体に `@blank-line` | 誤りなし（今と同じ） | I1 |
| 箇条書きの項目の中の `@lang en` の本体に `@page-break` | G02059 | I1 |
| `@frame f` の本体に `@page-break` と、すぐ次の行の段落 | G02256（今は黙って消える） | I2 |
| `@frame f` の本体に `@page-break` を二つ | G02256 が二つ | I2 |
| `@frame f` の本体に `@need-lines 3` | G02256 | I2 |
| `@note n` の本体に `@separator s` | G02141 | I2 |
| 図版のキャプションに `@blank-line` | G02093（今と同じ） | I2 |
| `@label a`、`@label b`、`@label c`、段落 | G02012 が二つ。ラベルは c | I3, I4 |
| `@style a`、`@style b`、段落 | G02012 が一つ。スタイルは b（今は a） | I3, I4 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0462 I1 から I4 を名前の先頭に置いたテストを golem-eval に足す。
表の入力を評価し、diagnostic のコードと数と出力を確かめる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

`@lang` の本体の中の改ページを誤りにしなくなるので、`@lang` で囲んだ範囲の途中で改ページできる。
`@style` と同じく、本体の結果はその場に置かれるので、改ページの意味は本体を書かなかったときと同じである。

入れ物を作る本体は、改ページを、ほかの段落でないブロックと同じコードで報告する。
原因は「入れ物の中には段落だけを書ける」で一つなので、ブロックの種類でコードを分けない。

二度書いたコマンドは誤りなので、残すコマンドを決める意味は、エラーの後の評価で出す diagnostic の数を保つことにある。
規則を一つにすると、どのコマンドでも残るものが同じになり、書き手が diagnostic を読むときに迷わない。

## 参考文献

- [root ADR 0459](0459-take-the-next-block-as-the-body-without-indentation.md)
- [root ADR 0460](0460-let-style-take-any-blocks-as-its-body.md)
- [root ADR 0461](0461-report-the-diagnostics-that-follow-from-another-error.md)
- [docs/adr/0017](0017-forced-page-breaks.md)
- [docs/adr/0046](0046-blank-line-command.md)
- [docs/adr/0187](0187-inline-language-switch.md)
- [golem-eval ADR 0003](../golem-eval/adr/0003-evaluation-diagnostic-codes.md)
