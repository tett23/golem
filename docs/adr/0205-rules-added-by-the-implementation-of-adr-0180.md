# ADR 0205: [ADR 0180](0180-verse-spacing-and-stanza-breaks.md) の実装で足した二つの規則を記録する

ステータス: 採択

## 文脈

[ADR 0180](0180-verse-spacing-and-stanza-breaks.md) は、韻文の前後に空きを入れ、連をページの境で分ける規則を決めた。
その実装（[#623](https://github.com/tett23/golem/pull/623)、マージのコミット `1362d5f9`）は、ADR に書かれていない二つの規則を足した。
どちらもマージ済みで、仕様書にも書かれているが、決めた ADR がない。
この ADR は、二つを決めたこととして記録する。

### 見出しの先読みが、空きを後の量に数える

`verse` に `space-before` を持たせると、見出しと連のあいだに空き（`FSpace`）が入る。
それまでの見出しの先読み（`nextNeed`）は、`FSpace` に当たると量を 0 にしていた。
そのため、Snark の 7 ページと 13 ページで、見出しがページの末尾に一つだけ残った。

[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) と仕様書は、見出しを後と離さない規則が空きの行を後の量に足すと定めていたが、`nextNeed` はそうしていなかった。
実装は、`FSpace n` の後の量に n を足し、段の行の格子の数を上限とした（[`Decide.hs`](https://github.com/tett23/golem/blob/c53026fd559f21ed64b89fadf76875d091c2a6c7/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L70-L71)）。
これは [ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) の実装の漏れを埋めたものである。

### `@no-page-break` の前の連

[ADR 0180](0180-verse-spacing-and-stanza-breaks.md) は、`@no-page-break` の前に連がある場合を書いていない。
実装の前は、連の最後の韻文の行が一つの段落として扱われ、その段落の最後の 2 行が後と同じ段に置かれていた。
連を一つの要素（`FStanza`）にした後に何もしなければ、連は後を待たなくなり、前より悪くなる。
実装は、段落の `placeKept` と同じく、連の最後の 2 つの韻文の行（3 つ以下の連なら全体）を、後に続くものと同じ段に置いた（[`Paginate.hs`](https://github.com/tett23/golem/blob/c53026fd559f21ed64b89fadf76875d091c2a6c7/modules/golem-layout/src/Golem/Layout/Paginate.hs#L169-L176)）。
仕様書の「韻文」の節にも、この規則が書かれた。

## 実装すること

二つの規則は、どちらも main に入っている（`c53026fd` で確かめた）。

- 見出しの先読みの空き：`nextNeed` の `FSpace` の枝。テストは `PaginateSpec` の「a heading keeps the space before the stanza and its first two verse lines (docs/adr/0189)」。
- `@no-page-break` の前の連：`placeFlow` の `FStanza` の枝と `placeKept`。テストは `PaginateSpec` の「a stanza before a no-break keeps its last two verse lines with what follows」。仕様書の「韻文」の節の文。

この ADR の実装は、次のことだけである。

- コードとテストの注釈で、二つの規則の出どころを `docs/adr/0180` と `docs/adr/0189` から、この ADR に改める。
- [ADR 0180](0180-verse-spacing-and-stanza-breaks.md) と [ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) のステータスの行に、この ADR が足した規則を書く。
- 仕様書の二つの文に、この ADR へのリンクを足す。

## 実装しないこと

- **`@no-page-break` の先読みの空き**：`keptNeed` が空きを数えないことは、[golem-layout ADR 0022](../golem-layout/adr/0022-no-page-break-counts-spaces.md) で直す。
- **見出しの先読みと、孤立行と寡婦行の食い違い**：[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) で直す。
- **規則の振る舞いを変えること**：記録だけを行う。

## 不変条件

段の行の数を C とする。

- **R1**：見出しの先読みは、見出しと後の段落のあいだの空きの行の数を、後の量に足す。足した量は C を超えない。
- **R2**：`@no-page-break` の前の連が段に置かれ、後に続くものの最初の部分が同じ段に置かれるなら、連の最後の min(2, v) 個の韻文の行（v は連の韻文の行の数、v ≤ 3 なら全体）も同じ段に置かれる。ただし、連が空の段から始まるときは除く。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 見出しの後の空きの行 | 0、1、C − 1、C |
| 連の韻文の行の数 | 1、2、3、4 |
| 段の残り | 連の最後の 2 つの韻文の行と後の最初の部分がちょうど入る、一行足りない |

## テスト設計

R1 と R2 には、上に挙げた今のテストがある。
この ADR では、境界の入力の表の残りを足す。
テストの名前には、R1 と R2 の番号を入れる。

- **R1**：空きの行が C − 1 と C のとき、量が C を上限とすること。
- **R2**：韻文の行が 1、2、3、4 の連で、最後の部分が後と同じ段に置かれること。連が空の段から始まるときは、送らないこと。

どれも今の実装で通る見込みで、先に失敗させることはできない。
今の振る舞いを固定するテストである。

## トレードオフ

実装の後で ADR を書くので、規則を決める前に代わりの案を比べていない。
二つとも、仕様書の規則（[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md)）と、段落の既存の規則（`placeKept`）に合わせたもので、新しい選択は少ない。
ADR のないまま残すと、どの ADR が決めた規則かを注釈からたどれず、規則を変える ADR を書くときに見落とす。

## メンテナーが決めること

1. **二つの規則をこのまま採るか**：推奨は、このまま採ることである。どちらも、[ADR 0180](0180-verse-spacing-and-stanza-breaks.md) の前の振る舞いより悪くしないための最小の足し方である。
   - 退けた案は、`@no-page-break` の前の連を、待たない（後と離れてよい）とすることである。実装の前より悪くなる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0180](0180-verse-spacing-and-stanza-breaks.md)、[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md)、[docs/adr/0030](0030-manual-page-break-control.md)
- [golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md)、[golem-layout ADR 0022](../golem-layout/adr/0022-no-page-break-counts-spaces.md)
- [#623](https://github.com/tett23/golem/pull/623) の報告
