# ADR 0043: `@need-lines` の前に置いた空きも、判定の残りに数えない

ステータス: 採択

## 文脈

2026-11-09 の毎晩の `enum.yml`（run 42530629702、main の `40eb98ce`）で、要素 6 個の抜き取り（[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)）が [golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の P5 の違反を見つけた。
要素を取り除いても違反が残る最も小さい入力は、要素 6 個のままである。

```haskell
paginateWithin maxBound 1 (ColumnSet 2 0 0 0) 3
  (enumFlows [EPara 1, ESpace, ENeedLinesMore 2, EFigure 1, EBlank 1, EFigure 1])
-- 1 ページの一段め: (0, SLine 0)
-- 1 ページの二段め: (0, SFigure 1000), (2, SFigure 1001)
-- 捨てた行アキの記録: なし
```

段の行の数が 3 なので、`ENeedLinesMore 2` は `@need-lines 2` であり、`ENeedLines` と同じ値である。
`ENeedLines` に置き換えた入力も同じ出力と同じ違反を出す。

### 改ページは、`@need-lines` の前の空きを残りから引く

改ページは、空き（`FSpace`）を置くと、その行を段の使った行に足す（[`Paginate.hs`](https://github.com/tett23/golem/blob/18f16e7c761395942d34553a4c5475bf5ec88efd/modules/golem-layout/src/Golem/Layout/Paginate.hs#L396-L398)）。
`@need-lines` はためておかれ、次のブロックの前で `applyNeed` が判定する（[`Paginate.hs`](https://github.com/tett23/golem/blob/18f16e7c761395942d34553a4c5475bf5ec88efd/modules/golem-layout/src/Golem/Layout/Paginate.hs#L208-L213)、[`L264-L272`](https://github.com/tett23/golem/blob/18f16e7c761395942d34553a4c5475bf5ec88efd/modules/golem-layout/src/Golem/Layout/Paginate.hs#L264-L272)）。
空きが `@need-lines` より前に書かれていれば、判定の残りは空きを置いた後の残りになる。
上の例では、一行めの段落の後に空きを置いて残りが 1 行になり、`@need-lines 2` が満たされないので、図版 1000 は二段めへ移る。

空きが `@need-lines` の後にあれば、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) のとおり、空きの前で判定する（[`Paginate.hs`](https://github.com/tett23/golem/blob/18f16e7c761395942d34553a4c5475bf5ec88efd/modules/golem-layout/src/Golem/Layout/Paginate.hs#L191-L200)）。
同じ版面で空きの位置だけを変えると、結果が分かれる（`Input 3 1`、2026-11-09 に `cabal repl golem-layout-test` で確かめた）。

| 流れ | 二つめの段落 |
| --- | --- |
| `[EPara 1, ESpace, ENeedLines, EPara 1]` | 2 ページ |
| `[EPara 1, ENeedLines, ESpace, EPara 1]` | 1 ページの 3 行め |
| `[EPara 1, ENeedLines, EPara 1]` | 1 ページの 2 行め |

一つめの行は、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) の P7 に反する。
P7 は「空きを除いた入力で同じ段に置かれるブロックを、空きのために後の段へ移さない」と定める。
空きを除いた三つめの行では段落が 1 ページにあり、一つめの行では空きのために 2 ページへ移る。
仕様書の `@need-lines` の文も、空きは「判定の残りに数えない」と書き、空きの位置を限っていない（[docs/specifications.md](../../specifications.md) の「改ページの手での制御」）。
ただし、P7 の節も仕様書の続く文も、`@need-lines` の後の空きだけを例に挙げており、前の空きを考えて書いたものではない可能性がある。

### 述語は、前の空きを残りから引かない

述語の `waitingFigures` は、`@need-lines` が図版を動かしたかを、最後に置いた部分の後の残りで量る（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/18f16e7c761395942d34553a4c5475bf5ec88efd/modules/golem-layout/test/PaginateInvariants.hs#L432-L436)、[`L472`](https://github.com/tett23/golem/blob/18f16e7c761395942d34553a4c5475bf5ec88efd/modules/golem-layout/test/PaginateInvariants.hs#L472)）。
空きは出力の枠に現れないので、この残りは空きを数えない。
上の例では、一段めの残りが 2 行なので、述語は `@need-lines 2` が図版 1000 を動かしていないと読む。
すると図版 1000 は自ら送られた図版になり、その後の図版 1001 は待つ図版になる（[golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md) の W1 と、仕様書の自ら送られる図版の文）。
P5 は、待つ図版の前の行アキが一度捨てられたと記録されることを求めるので、違反になる。
改ページは図版 1001 を待たせておらず、行アキを二段めの格子の 1 行めに置いている。

述語は仕様書の文のとおりに残りを量り、改ページは前の空きを引いている。
P5 の違反は、この食い違いが待つ図版の読み方を通して現れたものである。

### いつから起きていたか

2026-11-09 に、次の三つを確かめた。

- 改ページの振る舞いは、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の実装の前（`57ba5029`）から同じである。上の表の三行は、この版でも同じ結果になる。
- `ENeedLines` に置き換えた反例は、[ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の実装（`a819a6b5`、P5 と `leftAt` を足した）、[ADR 0033](0033-read-waiting-figures-from-the-placement.md) の実装の前（`1efc2d69`）、[ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) をマージする前の main（`65678b80`）のどれでも P5 の違反になる。
- `65678b80` で、毎晩と同じ `GOLEM_ENUM_DEPTH=5`、`GOLEM_ENUM_PAGINATION_SAMPLES=5000000` で抜き取りのテストを走らせると通る。

抜き取りは種を固定しているが、抜き取る入力は列挙の要素の一覧で決まる。
[golem-layout ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) の実装（`a5b4b69f`）が `ENeedLinesMore` を一覧に足したので、抜き取る入力が変わり、この形が初めて抜き取られた。
違反は [ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の実装から潜んでおり、[ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) の実装が見つけさせた。
要素 5 個までのすべての入力を調べるテストは、今も通る。

### 述語を直せば通ることの確認

述語だけを改め、`@need-lines` の前に書いた空き（最も大きい `@need-lines` より前のもの）の行を残りから引く形を試した（コミットしていない）。
毎晩と同じ変数で、要素 5 個までのすべての入力と、要素 6 個の抜き取りの両方が通り、golem-layout-test の 919 のテストも通った。
つまり、この違反は、前の空きの数え方だけが改ページと述語で違うことから来ている。
どちらに合わせるかは、「メンテナーが決めること」の 1 で決める。

## 実装すること

「メンテナーが決めること」の 1 を推奨のとおりとした場合を書く。

### 1. 前の空きを数えない判定

`@need-lines` の判定の残りは、前のブロックの最後に置いた部分（とその注）の後から数え、`@need-lines` の前に置いた空きも数えない。
前に置いた空きがあれば、`@need-lines` は空きを置く前の位置で、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) の空きの前の判定と同じく判定し、判定した段を覚える。
次のブロックの前では、今と同じく、判定した段にいれば、ブロックの最初の部分が空きを置いた後の残りに入るかだけを見る。
入らなければ、移った段で判定し直す。

実装の形は、次を想定する。

- 状態に、前のブロックの後に置いた空きの行の数を持たせる。ブロックを置けば 0 に戻す。
- `@need-lines` を受け取ったとき（`needMore`）に空きの行があれば、使った行から空きの行を引いた状態で `needBeforeSpace` と同じ判定をし、判定した段を `sNeedAt` に残す。
- 空きのない入力と、`@need-lines` の後にだけ空きがある入力では、今と同じ手順になる。

### 2. 述語

`waitingFigures` は変えない。
今の述語が、この ADR の数え方（前の空きを数えない）で残りを量っている。

### 3. 文書

- [docs/specifications.md](../../specifications.md) の「改ページの手での制御」の `@need-lines` の文に、`@need-lines` の前に置いた空きも数えないことと、この ADR へのリンクを足す。
- 出力が変わる本があれば、変わったページを目で確かめてから、`scripts/determinism/hashes.txt`、golden、見た目の回帰テストの参照を改める。
- [golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) のステータスの行に、前の空きの扱いをこの ADR が足したことを書く。

## 実装しないこと

- **述語を改ページに合わせること**：「メンテナーが決めること」の 1 の退けた案とする。
- **後の空きの扱いを変えること**：[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) のままとする。
- **改ページの印の後の空き**：改ページの印の後の空きは段の先頭で捨てられるので、判定の残りに関わらない。今のままとする。
- **`ENeedLinesMore` が段の行の数 3 で `ENeedLines` と同じ値になること**：列挙の大きさが少し増えるだけで、判定には関わらない。この ADR では変えない。

## 不変条件

C は段の行の数とする。
`@need-lines` の次のブロックは、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) のとおり、空きと待つ図版を飛ばした最初のブロックとする。

- **P9 空きの位置によらない**：前のブロックと `@need-lines` のあいだの空きを、`@need-lines` と次のブロックのあいだへ移した入力は、すべてのページの枠（`poSlots`）と記録（`poUnmet`）が元の入力と同じになる。あいだに改ページの印、`@no-page-break`、`@page-lines` がない入力に限る。
- **P10 前の空きは判定を動かさない**：`@need-lines` の前に空きがあり、`@need-lines` を空きの前の位置で判定して満たされ、次のブロックの最初の部分が空きを置いた後の残りに入るなら、ブロックはその段に置かれる。これは [golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) の P7 を前の空きに広げたものである。
- **P1 から P5 と I1 から I8**：前の空きがある入力でも、今の述語のまま成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `@need-lines` の前の空きの数 | 0、1、2、段の残りをちょうど埋める数 |
| `@need-lines` の後の空きの数 | 0、1 |
| 空きの前の残り | N − 1、N、N + 空きの数 − 1、N + 空きの数 |
| 次のブロック | 1 行の段落、2 行の段落、1 行の図版、C 行の図版 |
| 次のブロックの後 | なし、行アキと図版（今の反例の形） |
| 段の数 | 1、2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、P9、P10、P5 の番号を入れる。

- **P10**：`Input 3 1 [EPara 1, ESpace, ENeedLines, EPara 1]` で、二つめの段落が 1 ページに置かれること。今は 2 ページに置かれるので失敗する。
- **P5 の回帰**：毎晩の反例 `Input 3 2 [EPara 1, ESpace, ENeedLinesMore 2, EFigure 1, EBlank 1, EFigure 1]` で、`breaches` が違反を返さないこと。今は P5 の違反を返すので失敗する。出力の期待値は、規則から、図版 1000 が一段めの空きの後、図版 1001 が二段めの先頭で、行アキが捨てられて記録されると読める。実装の前にこの期待値を確かめ、違えばこの ADR の読みを見直す。
- **P9**：`PaginateInvariantsSpec` に、列挙の入力のうち空きの直後に `@need-lines` がある入力で、二つを入れ替えた入力と出力が同じことを確かめる述語を足す。プルリクエストの深さ（3）と毎晩の深さ（5）で走らせる。今は表の一行めの形で失敗する。
- **P7 の回帰**：[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) のテストが、変えずに通ること。
- 毎晩と同じ `GOLEM_ENUM_DEPTH=5` と `GOLEM_ENUM_PAGINATION_SAMPLES=5000000` で、すべての入力のテストと抜き取りのテストが通ること。

## トレードオフ

前の空きを数えないと、表やコードブロックの後の空きの後に `@need-lines 2` を書いても、ブロックが残り 1 行の位置に置かれることがある。
書き手が求めた 2 行は、見た目の上では空かない。
これは、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) が後の空きについてすでに受け入れたことと同じである。
その代わり、空きが前のブロックの後から来たか、後のブロックの前から来たかで、`@need-lines` の結果が変わらなくなる。
書き手は空きの出どころ（表の後か、`space-before` か）を原稿から区別できないので、区別しないほうが予想しやすい。

改ページの状態が一つ増え、出力が変わる本が出る可能性がある。
述語に合わせる案なら、どちらも起きない。

## メンテナーが決めること

1. **どちらを直すか**：推奨は、改ページを直し、前の空きも数えないことである。[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) の P7 と仕様書の文がすでにそう読め、述語もその読みで書かれている。空きの出どころで結果が分かれることもなくなる。
   - 退けた案の一つは、述語を改ページに合わせ、`@need-lines` は書いた位置で判定する（前に置いた空きは数え、後の空きは数えない）と仕様書に書くことである。出力は変わらず、変更はテストと文書だけで済み、ブロックの前に N 行が見た目の上でも空く場合が増える。しかし、P7 の文を後の空きに限る ADR が別に要り、表の一行めと二行めの違いを仕様として残すことになる。
   - もう一つは、この形を既知の不具合として `knownBugs` に載せることである。直すまでの毎晩の失敗は止まるが、仕様書の「既知の不具合」と一覧の両方に項目が増える。どちらかを決めるまでの一時の手当てとしてだけ使える。
2. **P9 を述語にするか**：推奨は、入れ替えた入力と比べる述語として列挙で調べることである。この違反は、P5 の待つ図版の読み方を通して要素 6 個で初めて現れ、要素 5 個までの列挙では見つからなかった。P9 なら、表の一行めの形（要素 4 個）で直接見つかる。
   - 退けた案は、回帰のテストだけを足すことである。同じ食い違いが別の制御（`@page-lines` など）との組で現れたときに、また抜き取りに頼ることになる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。v1 で余白などの吸収を扱うときに、この仕様を変えることがある。

## 参考文献

- [golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md)、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md)、[golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md)、[golem-layout ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)
- [docs/adr/0030](../../adr/0030-manual-page-break-control.md)、[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)
- [docs/specifications.md](../../specifications.md) の「改ページの手での制御」と「改ページ」の節
- 毎晩の `enum.yml` の run 42530629702（2026-11-09）の記録
