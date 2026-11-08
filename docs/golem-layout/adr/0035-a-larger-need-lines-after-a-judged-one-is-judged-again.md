# ADR 0035: 判定済みの `@need-lines` の後のより大きい `@need-lines` を判定し直す

ステータス: 採択

## 文脈

[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) は、`@need-lines` の後に空き（`FSpace`）があるとき、空きの前で `@need-lines` を判定し、判定した段を覚えておくとした。
ブロックが判定した段にあれば、ブロックの最初の部分が残りに入るかだけを見る。
同じ段で二度判定しないためである。

2026-11-08 のレビュー（[ADR 0236](../../adr/0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)）が、この規則の抜けを読んだ。
同じ段に、`@need-lines 2`、空き、`@need-lines 4`、空き、ブロックの順に書いたとする。
改ページは、二つめの `@need-lines` を一つめと合わせて大きいほうの 4 にする（[`Paginate.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-layout/src/Golem/Layout/Paginate.hs#L149)）。
しかし、判定した段の印は一つめのときのまま残る。
二つめの空きの前の判定は、印が今の段なので何もしない（[`Paginate.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-layout/src/Golem/Layout/Paginate.hs#L169-L178)）。
ブロックの前でも、印が今の段なので、4 行が残りにあるかを見ない（[`Paginate.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-layout/src/Golem/Layout/Paginate.hs#L187-L191)）。
残りが 2 行と 3 行のあいだなら、`@need-lines 4` は満たされないまま、記録もされない。
これは [golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) の P1 と P2 の違反である。

毎晩の列挙（[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)）がこれを見つけなかったのは、列挙の `ENeedLines` がいつも `@need-lines 2` を作るからである（[`PaginateEnum.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-layout/test/PaginateEnum.hs#L136)）。
同じ値の二つは合わせても変わらないので、この形は列挙に現れない。

メンテナーは、今の設計の不具合として直すと決めた（2026-11-08）。

## 実装すること

1. `@need-lines` を合わせて行の数が増えたとき、判定した段の印（`sNeedAt`）を消す。増えた値は、次の空きの前か、ブロックの前で、改めて判定する。行の数が増えないとき（同じか小さい値）は、印を残す。
2. 列挙の `ENeedLines` に、行の数の違う二つめの要素を足す。`ENeedLines` は今の 2 行のまま、`ENeedLinesMore` は段の行の数から 1 を引いた行を作る。段の行の数が 2 以下の版面では、`ENeedLinesMore` は列挙に出さない。
3. 仕様書の「改ページ」の `@need-lines` の文に、合わせて増えた値は判定し直すことと、この ADR へのリンクを足す。

## 実装しないこと

- **`@need-lines` を合わせる規則（大きいほうを採る）を変えること**：仕様書のとおりとする。
- **二つめの `@need-lines` が小さいときに判定し直すこと**：大きいほうがすでに判定済みなので、小さい値は満たされている。

## 不変条件

C は段の行の数とする。

- **N1 合わせた値の判定**：同じ段で判定した `@need-lines` の後に、より大きい `@need-lines` があるとき、ブロックの最初の行は、大きいほうの行の数が残りにある段に置かれるか、[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) の P2 のとおり満たせないことが記録される。これは P1 と P2 を、合わせた値について言い直したものである。
- **N2 小さい値**：判定した `@need-lines` の後に、同じか小さい `@need-lines` があっても、改ページの結果は、二つめがないときと同じである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 二つめの行の数 | 一つめより小さい、同じ、一つ大きい、C、C + 1 |
| 間の空きの数 | 0、1、2 |
| 一つめを判定した後の段の残り | 二つめの行の数ちょうど、一つ少ない |
| 二つめの後のブロック | 段落、図版、表 |

## テスト設計

- 例のテスト：一段で C = 6 の版面に、3 行の段落、`@need-lines 2`、一行の空き、`@need-lines 4`、一行の空き、1 行の段落を置き、最後の段落が次の段に置かれること（N1）。今の実装では、残りの 1 行に置かれ、失敗する。
- 境界の表の各行の例のテストを `PaginateSpec` に足す。テストの名前に N1、N2 を入れる。
- 列挙：2 の `ENeedLinesMore` を足した列挙で、今の P1 と P2 の述語が、プルリクエストの段で違反を見つけること（直す前）と、見つけないこと（直した後）を確かめる。プルリクエストの段の時間が [ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md) の 10 秒の予算を超えるなら、`ENeedLinesMore` は毎晩の段だけに入れ、その分けかたを PR に書く。
- Alloy のモデル（`docs/golem-layout/models/pagination.als`）の `@need-lines` の規則に、合わせて増えた値を判定し直すことを足し、スコープ 3 で走らせ直して結果を README に書く（[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の手で確かめる項目）。

## トレードオフ

印を消すと、二つめの値で同じ段を二度判定することがある。
[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) が二度判定を避けたのは、同じ値で判定し直すと、空きの後に段を移ったブロックを、移る前の段の残りで判定してしまうからである。
増えた値の判定は、まだ一度も行っていない判定なので、この問題には当たらない。

列挙の要素を一つ足すと、列挙の大きさが増える。
`ENeedLinesMore` を毎晩の段だけに入れる道を残し、プルリクエストの時間を守る。

## メンテナーが決めること

1. **直し方**：推奨は、合わせて増えたときに印を消すことである。判定の場所を増やさず、今の二つの判定（空きの前とブロックの前）がそのまま増えた値を見る。
   - 退けた案は、印に判定した行の数も持たせ、値が違えば判定し直すことである。振る舞いは同じだが、状態が一つ増える。
2. **列挙の要素**：推奨は、段の行の数から 1 を引いた行を作る `ENeedLinesMore` を足すことである。2 行より大きく、段に収まる最大の値で、残りが足りない形を作りやすい。
   - 退けた案は、`ENeedLines` に行の数の引数を持たせ、1 から C までを列挙することである。列挙の大きさが C 倍になる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md)、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md)、[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)、[ADR 0236](../../adr/0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)
