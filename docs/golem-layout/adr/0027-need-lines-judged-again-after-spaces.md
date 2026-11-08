# ADR 0027: `@need-lines` の後の空きでブロックが段を移れば、移った段で判定し直す

ステータス: 採択→Alloy のスコープは [ADR 0236](../../adr/0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)

## 文脈

毎晩の `enum.yml` の抜き取り（[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)）が、[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) の P1 の違反を見つけた。
仕様書の「既知の不具合」の「`@need-lines` の後の空きで、ブロックが送った図版の後の足りない残りに置かれる」が、この違反を記録している。
最も小さい例は、一段で段の行の数が 4 の版面に、2 行の段落、3 行の図版、`@need-lines 2`、二つの一行の空き、1 行の段落を置いたものである。
最後の段落は、2 ページの図版の後の、残りが 1 行の位置に置かれる。

ここでいう**空き**は、改ページに渡す一行ずつの空き（`FSpace`）で、表とコードブロックの後や、`space-before` を持つ段落の前に入る。
原稿に書く行アキ（`@blank-line`、`FBlank`）とは別のものである。
空きを `@need-lines` の「次のブロック」に数えるかを、仕様は定めていない。

### 空きが `@need-lines` を使い切る

`placeAll` の空きの枝は、空きを置く前に `ready` を当てる（[`Paginate.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L139-L140)）。
`ready` は改ページと `@need-lines`（`applyNeed`、[`L180-L188`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L180-L188)）を当て、`sNeed` を空にする。
`@need-lines` は空きの位置で判定され、後のブロックの位置では判定されない。

上の例では、`@need-lines 2` は 1 ページの残り 2 行で守られたと判定される。
続く二つの空きが残りの 2 行を埋め（[`L312-L314`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L312-L314)）、段落は入らずに `placeLines` が次の段へ進む。
次の段の先頭には送った図版が置かれ、残りは 1 行になる。
段落はそこに置かれ、`@need-lines` は数え直されない。

行アキは、同じ枝で扱いが違う。
空きの枝は `placeBlank` を当てないので、行アキは空きを越えて待ち、次のブロックの位置で判定される。
`@need-lines` だけが、空きの位置で使い切られている。

### 確かめたこと

`cabal repl golem-layout-test` で、`PaginateEnum` の `paginateInput` と `PaginateInvariants` の `breaches` を使って確かめた（2026-11-08、golem-layout のソースは origin/main の `4c808d07` と同じもの）。

- `Input 4 1 [EPara 2, EFigure 3, ENeedLines, ESpace, ESpace, EPara 1]`：最後の段落が 2 ページの図版の後に置かれ、P1 が違反になる。二段組み（`Input 4 2 …`）でも、1 ページの二段めの図版の後に置かれる。
- `Input 4 1 [EPara 2, ENeedLines, ESpace, EPara 1]`：空きの前の残りが 2 行、空きの後が 1 行で、段落は 1 ページに置かれる。P1 は空きを数えないので、守られている。
- 既知の不具合の一覧がこの項目で除く入力は、要素 5 個で 14 ある（[`PaginateInvariantsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateInvariantsSpec.hs#L372-L377)）。14 のすべてを列挙で取り出すと、`[…, EFigure 3, ENeedLines, ESpace, EFigure 1]` の形で、`@need-lines` のブロックが待つ図版である。これは [golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の直す形でもある。空きだけで起きる最も小さい例は、仕様書のとおり要素 6 個で、毎晩のすべての入力を調べる上限（5 個）の外にある。

二つめの例が、直し方の制約になる。
空きの後に判定を移すだけでは、この入力の段落が 2 ページへ移る。
P1 は空きを数えず、今の出力は P1 を守っているので、移す理由がない。

## 実装すること

### 1. 判定した段から移ったら、判定し直す

`@need-lines` は、今と同じく、空きの前の位置で、空きを数えずに判定する。
判定した後、次のブロックの最初の部分が判定した段に入らず、ブロックが後の段に移るなら、移った段で `@need-lines` を判定し直す。
移った段は、送った図版と続きの注を先に置いた後の段であり、`keep` で入るか段が空になるまで進む（[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) と同じ）。

実装の形は、次を想定する。

- 空きの枝では、改ページだけを当て、`applyNeed` を当てた後も `sNeed` を消さず、判定した段（ページと段の番号）を添えて残す。
- 次のブロックの `ready` で、判定した段にいれば、ブロックの最初の部分（`nextNeed`）が残りに入るかだけを見る。入れば進まない。入らなければ、`keep` で、移った段からは N 行を量として進む。
- 判定した段から改ページで移っていれば、移った先で N 行を判定する。

`@need-lines` の後に空きがない入力では、`sNeed` はブロックの直前で判定されて消え、今と同じ手順になる。

### 2. 不変条件の述語と既知の不具合の一覧

P1 の述語（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateInvariants.hs#L434-L453)）は変えない。
空きを数えない今の数え方が、この ADR の規則でもある。
`PaginateInvariantsSpec` の `knownBugs` から、この項目と `needLinesBeforeSpace` を除く。
要素 5 個の 14 の入力は待つ図版の形なので、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) を先に実装する（「メンテナーが決めること」の 3）。

### 3. 列挙

毎晩の抜き取りでしか見つからない形なので、要素 6 個の最も小さい例を `PaginateSpec` の回帰のテストにする。
列挙の上限は変えない。

### 4. Alloy のモデル

`docs/golem-layout/models/pagination.als` は空きを持たない。
[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) が足す行アキと図版に加え、`@need-lines` と空きを足し、`@need-lines` と、空きを段の先頭で捨てる規則と、送った図版の規則が両立することを確かめる（[docs/roadmap.md](../../roadmap.md) の「規則の Alloy のモデル」）。
結果はモデルの README と PR の説明に書く。

### 5. 文書

- [docs/specifications.md](../../specifications.md) の「改ページの手での制御」の `@need-lines` の文に、空きは次のブロックに数えないこと、判定した段から次のブロックが移れば移った段で判定し直すことを書く。
- 「既知の不具合」から、この項目を除く。
- [docs/roadmap.md](../../roadmap.md) の「不変条件のテストで見つかった改ページの不具合」の項目を除く。
- 出力が変わる本があれば、変わったページを目で確かめてから、`scripts/determinism/hashes.txt`、golden、見た目の回帰テストの参照を改める。
- [golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) のステータスの行に、P1 を空きの後で守る規則をこの ADR が足したことを書く。

## 実装しないこと

- **空きを `@need-lines` の量に足すこと**：仕様書の「`@need-lines` の判定に行アキの行数は数えない」と同じく、空きも数えない（「メンテナーが決めること」の 1）。
- **待つ図版**：[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) で直す。
- **空きと行アキの順**：空きの枝は行アキを待たせるので、`@blank-line` の後に空きがあると、空きが行アキより先に置かれる。どちらも見えない空きで、どの不変条件にも当たらないので、変えない。
- **見出しの先読みの空き**：`nextNeed` は空きを後の量に足す（[docs/adr/0205](../../adr/0205-rules-added-by-the-implementation-of-adr-0180.md) の R1）。見出しを後と離さない規則の量であり、`@need-lines` の判定とは別の規則なので、変えない。

## 不変条件

段の行の数を C、今の段の行の数（`@page-lines` を当てたもの）を C' とする。
`@need-lines` の次のブロックは、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) のとおり、空きと待つ図版を飛ばした最初のブロックとする。

- **P1 `@need-lines` を守る**：[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) の P1 のまま、空きの有無によらず成り立つ。残りは、ブロックの前の置いたものの終わりから数え、空きと行アキを数えない。
- **P7 空きは判定を動かさない**：`@need-lines` の次のブロックの最初の部分が、判定した段の、空きを置いた後の残りに入るなら、ブロックはその段に置かれる。空きを除いた入力で同じ段に置かれるブロックを、空きのために後の段へ移さない。
- **P8 空きは段の先頭で捨てる**：判定し直して移った段の先頭では、空きを置かない（今の `FSpace` の枝のまま）。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `@need-lines` と次のブロックのあいだの空き | 0、1、2、判定した段の残りをちょうど埋める数 |
| 判定するときの段の残り | N − 1、N、N + 空きの数 − 1、N + 空きの数 |
| 次のブロックの最初の部分 | 1 行、2 行、段落の孤立行の規則で移るもの |
| 移った段の送った図版 | なし、残りを N − 1 行にするもの、段を埋めるもの |
| 空きの前の改ページ | なし、あり |
| 段の数 | 1、2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、P1、P7、P8 の番号を入れる。

- **P1**：`Input 4 1 [EPara 2, EFigure 3, ENeedLines, ESpace, ESpace, EPara 1]` の流れで、最後の段落が 3 ページに置かれること。今は 2 ページに置かれるので失敗する。二段組みでも同じ形を確かめる。
- **P7**：`Input 4 1 [EPara 2, ENeedLines, ESpace, EPara 1]` で、段落が 1 ページに置かれること。今も通る。判定を空きの後へ移すだけの実装を退けるテストである。
- **P1 と孤立行**：判定した段に空きの後で段落の 1 行だけが入り、孤立行の規則で段落が移る入力で、移った段の残りが N 行以上であること。
- **P8**：判定し直して移った段の先頭に空きが置かれないこと。
- 既知の不具合の一覧から項目を除いた後、毎晩の深さ（`GOLEM_ENUM_DEPTH=5`）の列挙と、要素 6 個の抜き取りで、P1 から P4 と I1 から I8 が成り立つこと。プルリクエストの深さ（3）では、この項目が除く入力は 0 なので、先に失敗させるのは回帰のテストで行う。
- Alloy のモデルでは、「実装すること」の 4 の述語の組を `run` で調べ、結果を README に書く。

## トレードオフ

`@need-lines` の判定に、空きの前と後の二つの段階ができる。
空きの後で判定を一つにまとめる（「メンテナーが決めること」の 1 の退けた案）ほうがコードは短いが、今 P1 を守っている出力まで変える。
二段階にすれば、出力が変わるのは、ブロックが判定した段から移り、移った段の残りが N 行に足りない入力に限られる。
今の P1 の違反を直す範囲だけで出力が変わる。

`sNeed` に判定した段を添えるので、状態が一つ増える。
この状態は空きのあいだだけ生き、次のブロックの `ready` で消える。

## メンテナーが決めること

1. **空きを `@need-lines` の次のブロックに数えるか**：推奨は、数えず、空きの前で判定し、ブロックが判定した段から移れば移った段で判定し直すことである。空きはブロックの見えない前後の空きで、書き手が N 行を求めたのは後のブロックに対してである。今 P1 を守っている出力は変えない。
   - 退けた案の一つは、空きを次のブロックに数え、P1 を空きの位置で量るように改めることである。書き手が 2 行を求めたブロックが、残り 1 行の位置に置かれたまま、指定を守ったことになる。
   - 二つめは、空きの枝から `applyNeed` を外し、後のブロックの位置で、置いた空きの分を引いた残りで判定することである。コードは一行の変更で済むが、`Input 4 1 [EPara 2, ENeedLines, ESpace, EPara 1]` の段落が 2 ページへ移るように、P1 を守っている出力も変わる。
   - 三つめは、空きの前で N に空きの行の数を足して判定し、空きを後のブロックと一緒に移すことである。二つめと同じく今の出力を変え、空きの行を `@need-lines` に数えることになり、行アキを数えない規則と食い違う。
2. **空きの数え方を P1 に書くか**：推奨は、P1 の文を変えず、仕様書の `@need-lines` の文に、空きも行アキと同じく数えないことを書き足すことである。述語は今も空きを数えていない。
   - 退けた案は、P1 を P1′ として書き直すことである。数え方が変わらないのに、同じ不変条件に二つの名前ができる。
3. **[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) との順**：推奨は、0026 を先に実装し、この ADR をその後に実装することである。既知の不具合の一覧のこの項目が除く 14 の入力は、`@need-lines` のブロックが待つ図版の形で、0026 が直す。先にこの ADR だけを入れると、項目を一覧から除けない。
   - 退けた案は、二つを一つの ADR と一つの PR にすることである。原因のコードが別の枝（空きの枝と、待つ図版の判定）にあり、どちらの変更がどの違反を直したかを PR ごとに確かめられなくなる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md)、[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md)、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)
- [docs/adr/0030](../../adr/0030-manual-page-break-control.md)、[docs/adr/0046](../../adr/0046-blank-line-command.md)、[docs/adr/0205](../../adr/0205-rules-added-by-the-implementation-of-adr-0180.md)、[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)
- [docs/specifications.md](../../specifications.md) の「改ページの手での制御」、「行アキ」、「既知の不具合」の節
- [docs/roadmap.md](../../roadmap.md) の「規則の Alloy のモデル」
- 日本語組版処理の要件（JLReq）、<https://www.w3.org/TR/jlreq/>（`@need-lines` に当たる指定を定めていない）
