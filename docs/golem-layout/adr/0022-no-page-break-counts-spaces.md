# ADR 0022: `@no-page-break` の先読みで、空きの行を数える

ステータス: 採択（未実装）

## 文脈

仕様書は、見出しを後と離さない規則と `@no-page-break` の先読みが、行アキと空きの行を後のものの量に足すと定める（[docs/specifications.md](../../specifications.md) の「行アキ」と「段落の前後の空き」の節。[ADR 0189](../../adr/0189-paragraph-alignment-spacing-and-end-indent.md)）。
足した量は、段の行の格子の数を上限とする。

見出しの先読みの `nextNeed` は、空き（`FSpace`）を後の量に足す（[`Decide.hs`](https://github.com/tett23/golem/blob/c53026fd559f21ed64b89fadf76875d091c2a6c7/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L70-L71)）。
この枝は [ADR 0180](../../adr/0180-verse-spacing-and-stanza-breaks.md) の実装で足された（[ADR 0205](../../adr/0205-rules-added-by-the-implementation-of-adr-0180.md)）。

`@no-page-break` の先読みの `keptNeed` は、`@no-page-break` の前と後の `FSpace` を、`FNeedLines` と `FAdjustLines` とともに `soft` として読み飛ばしてから、`nextNeed` を呼ぶ（[`Decide.hs`](https://github.com/tett23/golem/blob/c53026fd559f21ed64b89fadf76875d091c2a6c7/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L97-L109)）。
読み飛ばした空きは、量に入らない。
`@no-page-break` の前の段落は、最後の 2 行と、後の最初の部分を同じ段に置こうとするが、あいだの空きを数えないので、空きの行の分だけ段からあふれうる。
あふれた分は、後の最初の部分が次の段に送られる形で表に出る。

`soft` は、`@no-page-break` が何を待つかを決めるためのものでもある。
仕様書は「行アキを置いたことは、`@no-page-break` が待つものを置いたことにならない」と定めており、待つものを決めるときに空きを飛ばすのは正しい。
食い違いは、量を数えるときにも同じ `soft` で飛ばしていることにある。

[ADR 0180](../../adr/0180-verse-spacing-and-stanza-breaks.md) の実装の報告が、この食い違いを挙げた。
[ADR 0189](../../adr/0189-paragraph-alignment-spacing-and-end-indent.md) の範囲なので、その実装では変えなかった。

## 実装すること

- `keptNeed` を、待つものを見つける部分と、量を数える部分に分ける。
  - 待つもの：今のとおり、`soft` を飛ばした後の最初の要素が `FNoBreak` かで決める。
  - 量：`@no-page-break` の前の `soft` の並びにある `FSpace` の行の数と、`@no-page-break` の後の並びを `nextNeed` に渡した量の和にする。`nextNeed` は、後の `FSpace`、`FNeedLines`、`FAdjustLines` を自分で扱うので、後の並びからは何も飛ばさずに渡す。
  - 和は、段の行の格子の数を上限とする（`nextNeed` の `FSpace` の枝と同じ）。
- [docs/specifications.md](../../specifications.md) の「改ページの手での制御」の節の `@no-page-break` の文に、前後の空きの行を後の量に数えることを書く。今の「行アキ」と「段落の前後の空き」の節の文は、このとおりなので変えない。
- PDF のバイト列が変わる本があれば、`scripts/determinism/hashes.txt`、golden、見た目の回帰テストの参照を、変わったページを目で確かめてから改める。

## 実装しないこと

- **`@no-page-break` が待つものの決め方**：空きを置いても待つものを置いたことにならない、という今の規則を変えない。
- **`FBlank`（`@blank`）**：`FBlank` は `soft` に入っておらず、段落と `@no-page-break` のあいだに `FBlank` があれば、`keptNeed` は `Nothing` を返し、段落は後を待たない。仕様書がこの場合を決めていないので、この ADR では変えない。docs/roadmap.md の「未決事項」に足す。
- **見出しの先読み**：`nextNeed` は空きを数えているので変えない。

## 不変条件

段の行の数を C とする。

- **N1**：`keptNeed` が返す量の格子の行の数は、`@no-page-break` の前後の `FSpace` の行の数の和と、後の最初の部分の行の数の和に等しい。ただし C を超えない。
- **N2**：`@no-page-break` の前の段落が段に置かれ、後の最初の部分が同じ段に置かれたなら、その段の段落の行、空きの行、後の部分の行と、それらの注の本文の行の和は、C を超えない。
- **N3**：`@no-page-break` の前後に空きがなければ、`keptNeed` の量は今と同じである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 空きの位置 | なし、`@no-page-break` の前、後、前と後の両方 |
| 空きの行の数 | 1、C − 1、C、C + 1 |
| 段の残り | 段落の最後の 2 行と後の 2 行がちょうど入る、空きの分だけ足りない |
| 前の飛ばすもの | `FNeedLines`、`FAdjustLines` を空きと混ぜたもの |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、N1 から N3 の番号を入れる。

- **N1**：上の境界の入力の組で、`keptNeed` の量が式どおりであること。
- **N2**：段の行の数 10 で、8 行の段落、`@no-page-break`、`FSpace 1`、5 行の段落を並べると、前の段落の最後の 2 行が、空きと後の段落の最初の 2 行とともに次の段に送られること。今は空きを数えずに前の段落の 8 行をすべて置き、空きの後に残る 1 行には後の段落が孤立行の規則で入らないので、後の段落だけが次の段に送られ、失敗する。
- **N3**：今の `PaginateSpec` の `@no-page-break` のテストが、変わらず通ること。
- 空きを置いても `@no-page-break` が待ち続けること（今のテスト「no-break keeps the last lines with what follows across need-lines and a space before it」）が、変わらず通ること。

## トレードオフ

`@no-page-break` の前の段落の最後の 2 行を次の段に送る場面が、空きの行の分だけ増える。
段の末尾の空きが増えるが、仕様書のとおりであり、後の最初の部分が段の境で切れるよりよい。

`keptNeed` を二つに分けると、待つものの判定と量の計算が別の関数になる。
二つの役目を一つの `soft` で兼ねていたことが、この食い違いの原因なので、分けたほうがよい。

## メンテナーが決めること

なし。
仕様書がすでに決めていることを、実装に合わせる ADR である。

## 決めたことの記録

- **採択**（2026-11-08、メンテナー）：決めることはなく、このとおり採択した。

## 参考文献

- [docs/specifications.md](../../specifications.md) の「改ページの手での制御」「行アキ」「段落の前後の空き」の節
- [docs/adr/0030](../../adr/0030-manual-page-break-control.md)、[ADR 0189](../../adr/0189-paragraph-alignment-spacing-and-end-indent.md)、[ADR 0180](../../adr/0180-verse-spacing-and-stanza-breaks.md)、[ADR 0205](../../adr/0205-rules-added-by-the-implementation-of-adr-0180.md)
- [ADR 0180](../../adr/0180-verse-spacing-and-stanza-breaks.md) の実装のプルリクエスト（[#623](https://github.com/tett23/golem/pull/623)）の報告
