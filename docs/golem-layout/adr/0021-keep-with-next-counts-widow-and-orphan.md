# ADR 0021: 見出しの先読みで、段落を段で分けられる最初の部分を数える

ステータス: 採択

## 文脈

仕様書の「改ページ」の節は、見出しを、続く見出しのすべてと、その後の段落の最初の 2 行までと同じ段に置くと定める（[docs/specifications.md](../../specifications.md)、[golem-driver ADR 0032](../../golem-driver/adr/0032-default-heading-styles.md)）。
同じ節は、段落の最初の 1 行だけが段の末尾に残るなら次の段に送り（孤立行）、最後の 1 行だけが次の段に送られるなら前の段の最後の行も送る（寡婦行）とも定める。

見出しの先読みは、後に続く段落の最初の 2 行を、後の量として数える（[`Decide.hs`](https://github.com/tett23/golem/blob/c53026fd559f21ed64b89fadf76875d091c2a6c7/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L57-L62)）。
一方で、段落を置く `placeLines` は、入る行の数を求めた後に、寡婦行と孤立行の規則で減らす（[`Paginate.hs`](https://github.com/tett23/golem/blob/c53026fd559f21ed64b89fadf76875d091c2a6c7/modules/golem-layout/src/Golem/Layout/Paginate.hs#L309-L324)）。
3 行の段落の前に、見出しと 2 行の空きが残っているとする。
先読みは 2 行で足りると判断して見出しをその段に置く。
段落を置く段では、2 行を置くと最後の 1 行が寡婦行になるので 1 行に減らし、その 1 行は孤立行になるので 0 行に減らす。
段落は丸ごと次の段に送られ、見出しだけが段の末尾に残る。

[ADR 0180](../../adr/0180-verse-spacing-and-stanza-breaks.md) の実装で、使い手のマニュアルの 80 ページで、「段落のあいだを空ける」（`manual/chapters/03-markup.gm` の 873 行め）の見出しが、この形でページの末尾に残った。
韻文の空きで組版の位置がずれて表に出たもので、規則そのものは前からある。

同じことは、段落と同じ規則で置くほかの要素でも起きる。

- 回り込む図版の後の段落の続き（`FContinued`）は、最初の行に孤立行の規則を当てないが、寡婦行の規則は当てる。3 行の続きの前に 2 行の空きがあれば、1 行だけを置き、見出しは 1 行としか同じ段にならない。
- 連（`FStanza`、[ADR 0180](../../adr/0180-verse-spacing-and-stanza-breaks.md)）は、韻文の行を単位に同じ規則を当てる。先読みは最初の 2 つの韻文の行を数える。
- `@no-page-break` の先読み（`keptNeed`）も、後の量を `nextNeed` で求める。

先読みの数える量が、段落を置くときに実際に置ける量より少ないことが、原因である。

## 実装すること

### 1. 段で分けられる最初の部分

行（または韻文の行）が n 個の段落を段で分けるとき、前の段に置ける行の数 k は、次の両方を満たす。

- 孤立行の規則：k = 0 か、k ≥ 2（`FContinued` は k ≥ 1）。
- 寡婦行の規則：k = n か、n − k ≥ 2。

見出しの先読みが数える量を、この規則で置ける k のうち、min(2, n) 以上で最も小さいものにする。
`FParagraph`、`FContinued`、`FStanza` のどれでも、その値は次のとおりになる。

| n | 数える量 |
| --- | --- |
| 1 | 1 |
| 2 | 2 |
| 3 | 3（全体） |
| 4 以上 | 2 |

`FStanza` では、韻文の行の数で上の表を引き、その韻文の行に含まれる行（折り返しを含む）の数を量にする。
注の本文の行は、今のとおり、数える行の注を数える（[golem-layout ADR 0019](0019-keep-with-next-counts-footnotes.md)）。

`nextNeed` のこの三つの枝を変える。
関数は golem-layout の `Golem.Layout.Paginate.Decide` に置き、`placeLines` と `placeStanza` の規則と同じ式から求める（「メンテナーが決めること」の 1）。
`keptNeed` は `nextNeed` を使うので、`@no-page-break` の先読みも同じく変わる。

### 2. 仕様書

[docs/specifications.md](../../specifications.md) の「改ページ」の節の「その後の段落の最初の 2 行まで」を、「その後の段落の最初の 2 行まで（3 行の段落では全体。孤立行と寡婦行の規則で 2 行だけを置けないため）」に改める。
連の文（「連の最初の 2 つの韻文の行を、後に続くものの量として数える」）と、`@no-page-break` の文も、同じく改める。

### 3. 出力の変化

見出しを次の段に送る場面が増えるので、PDF のバイト列が変わる本がある。
`scripts/determinism/hashes.txt`、golden、見た目の回帰テストの参照（`scripts/visual/pages/`）を、変わったページを目で確かめてから改める。
マニュアルの 80 ページの見出しが、段落とともに次のページに移ることを確かめる。

[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の実装が、この形の違反を既知の不具合の一覧に入れていれば、その項目と、仕様書の「既知の不具合」と docs/roadmap.md の項目を消す。

## 実装しないこと

- **孤立行と寡婦行の規則そのものを変えること**：仕様書のとおりとする。
- **見出しの後の量を 3 行以上にすること**：4 行以上の段落では、今のとおり 2 行とする。
- **定義リストの用語（`FDefTerm`）**：用語の全体を数える今の扱いを変えない。
- **空の段と、見出しだけの段の扱い**：入るだけの行を置く規則（[golem-layout ADR 0019](0019-keep-with-next-counts-footnotes.md)）を変えない。

## 不変条件

段の行の数を C とする。

- **K1**：見出しが段の最初の要素でなく、その段に見出しが置かれたなら、続く段落（`FParagraph`、`FContinued`、`FStanza`）の最初の min(2, n) 個の行（連では韻文の行）も同じ段に置かれる。
- **K2**：どの n と、どの段の残りの行についても、`nextNeed` の数える行の数を置ける残りがあれば、`placeLines`（`placeStanza`）がその段に置く行の数は min(2, n) 以上である。
- **K3**：`nextNeed` の数える行の数は、n が 4 以上なら 2、そうでなければ n である。

K1 は [ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の I6 と同じ性質である。
K2 は先読みと置き方の対応で、この ADR が直す食い違いそのものである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 段落の行の数 n | 1、2、3、4、5 |
| 見出しの後の段の残り | 0、1、2、3、4 |
| 要素 | `FParagraph`、`FContinued`、`FStanza`（韻文の行の一つが 2 行に折り返すものを含む） |
| 注 | なし、2 行めに注 |
| 先読みの元 | 見出し、`@no-page-break` |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、K1 から K3 の番号を入れる。

- **K3**：`nextNeed` に、行の数が 1 から 6 の `FParagraph`、`FContinued`、`FStanza` を渡し、表の値を返すこと。折り返した韻文の行を含む連では、その行の数を返すこと。
- **K2**：n が 1 から 6、残りの行が 0 から 8 のすべての組で、K2 が成り立つこと（hedgehog ではなく、すべての組を回す）。
- **K1**：段の行の数 8 で、5 行の段落、見出し、3 行の段落を並べると、見出しが 3 行の段落とともに 2 ページめに置かれること。今は見出しが 1 ページの末尾に残るので失敗する。
- 同じ形を `FContinued`（3 行の続き）、`FStanza`（3 つの韻文の行）、`@no-page-break` の前の段落、2 行めに注を持つ 3 行の段落でも確かめる。
- 4 行の段落では、今のとおり見出しと最初の 2 行が同じ段に置かれ、出力が変わらないこと。

## トレードオフ

見出しを次の段に送る場面が増え、段の末尾に空きが残る場面も増える。
それでも、見出しだけが段の末尾に残るより読みやすく、仕様書の規則（見出しを段落の最初の 2 行と同じ段に置く）に合う。

先読みの量を、置き方の規則と同じ式から求めるので、孤立行と寡婦行の規則を変えるときは、先読みも一緒に変わる。
二つを別々に書く今の形では、片方だけを変えると、今回と同じ食い違いが起きる。

## メンテナーが決めること

1. **先読みの量の求め方**：推奨は、`placeLines` と `placeStanza` が使う孤立行と寡婦行の判定を一つの関数に出し、先読みもその関数から求めることである。規則が一か所になり、K2 が式の上でも成り立つ。
   - 退けた案は、`nextNeed` に「3 行なら全体」と書くことである。差分は小さいが、規則を変えたときに食い違いが戻る。
2. **`FContinued` と `FStanza` も直すか**：推奨は、三つとも直すことである。同じ規則で置くので、同じ食い違いがある。
   - 退けた案は、マニュアルで表に出た `FParagraph` だけを直すことである。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [docs/specifications.md](../../specifications.md) の「改ページ」の節
- [golem-layout ADR 0003](0003-pagination-and-s2.md)、[golem-layout ADR 0019](0019-keep-with-next-counts-footnotes.md)、[golem-driver ADR 0032](../../golem-driver/adr/0032-default-heading-styles.md)、[ADR 0180](../../adr/0180-verse-spacing-and-stanza-breaks.md)、[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)
- [ADR 0180](../../adr/0180-verse-spacing-and-stanza-breaks.md) の実装のプルリクエスト（[#623](https://github.com/tett23/golem/pull/623)）の報告
