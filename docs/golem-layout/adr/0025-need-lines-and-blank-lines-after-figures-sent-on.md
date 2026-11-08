# ADR 0025: 送った図版の後でも、`@need-lines` と行アキが段に入るまで進む

ステータス: 採択→行アキの手順 3 が段の先頭で止まること、続きの注の後の回り込む図版、P4 の 6 行の例、P3 の読み方は [ADR 0211](../../adr/0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、P1、P3、P4 の「次のブロック」は [golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)

## 文脈

[golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md) は、見出しを後と離さない規則の判定で、次の段へ一度だけ進み、移った先の段を空と決めてかかっていたことを直した。
移った先の段の先頭には、送った図版と続きの注が先に置かれる（`advance` の `placeDeferred`、[`State.hs`](https://github.com/tett23/golem/blob/6e5f852fb08cd182e4bb40ef4cd9c3bca0b74618/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L211-L240)）。
そこで、入るか段が空になるまで進み続ける `keep` を作った（[`State.hs`](https://github.com/tett23/golem/blob/6e5f852fb08cd182e4bb40ef4cd9c3bca0b74618/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L118-L125)）。

[golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md) の実装（[#650](https://github.com/tett23/golem/pull/650)）は、同じ作りがほかに二つあることを見つけ、`cabal repl` で違反を確かめた。
どちらも [golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md) の「実装しないこと」で調べていないとしたものである。

### `@need-lines`（`applyNeed`）

`applyNeed` は、残りが N 行に足りなければ `nextColumn` を一度だけ呼ぶ（[`Paginate.hs`](https://github.com/tett23/golem/blob/6e5f852fb08cd182e4bb40ef4cd9c3bca0b74618/modules/golem-layout/src/Golem/Layout/Paginate.hs#L170-L178)）。
移った段の先頭に送った図版が置かれても、残りを確かめ直さない。

- `paginate 1 4 [FParagraph 3 行, FFigure 3 行, FNeedLines 2, FParagraph 1 行]` では、2 ページの図版の後に 1 行しか残らないのに、段落の行がそこに置かれる。
- 守れなかった `@need-lines` は G07037 の警告にする（仕様書の「改ページの手での制御」）が、この場合は `UnmetNeedLines` にも記録されず、警告も出ない。

仕様書は「`@need-lines N`（残りが N 行に足りなければ次の段から続ける）」と定める。
次の段でも足りなければ、さらに次の段から続けるのが、この文の意味である。

### 行アキ（`placeBlank`）

`placeBlank` は、行アキの行数と後の最初の部分が今の段に入らなければ、`nextColumn` を一度だけ呼ぶ（[`Paginate.hs`](https://github.com/tett23/golem/blob/6e5f852fb08cd182e4bb40ef4cd9c3bca0b74618/modules/golem-layout/src/Golem/Layout/Paginate.hs#L154-L168)）。
移った段の先頭に送った図版が置かれると、その段は先頭ではないので、行アキを捨てずに置く。
入るかどうかは確かめ直さない。

- `paginate 1 4 [FParagraph 3 行, FFigure 3 行, FBlank 2, FParagraph 1 行]` では、2 行の行アキが図版の後に置かれ、4 行の段で 5 行を使う。行アキは捨てられず、`DroppedBlank` にも記録されない。段落は 3 ページに送られる。

仕様書の「行アキ」の節の手順の 3 は、「今の段が空でなく、行アキの行数の和と、置くものの最初の部分の和が今の段の残りに入らなければ、次の段へ進む」と定める。
手順の 4 は「今の段の先頭なら、行アキを捨て」ると定める。
行アキは段に入りきらない場合も段の先頭で捨て、途中で切り詰めない、とも定める。
今の実装は、3 を一度だけ行い、移った段が先頭でなければ、入らない行アキをそのまま置いている。

### 同じ作りの残り

`nextColumn` を一度だけ呼んで、その後に入るかを確かめ直さない箇所は、ほかにもある。

- 表（`FTable`）：見出しの行と最初の行が入らなければ一度だけ進む（[`Paginate.hs`](https://github.com/tett23/golem/blob/6e5f852fb08cd182e4bb40ef4cd9c3bca0b74618/modules/golem-layout/src/Golem/Layout/Paginate.hs#L263-L268)）。
- 回り込む図版（`FWrapped`）：入らなければ一度だけ進み、そのまま置く（[`Paginate.hs`](https://github.com/tett23/golem/blob/6e5f852fb08cd182e4bb40ef4cd9c3bca0b74618/modules/golem-layout/src/Golem/Layout/Paginate.hs#L284-L289)）。

この二つで違反が起きるかは、確かめていない。
表は `placeTable` が行を入るだけ置くので、表そのものは段からあふれない見込みがあるが、見出しの行と最初の行を同じ段に置く規則（[golem-driver ADR 0031](../../golem-driver/adr/0031-table-spacing-and-rules.md)）が守られるかは未確認である。
回り込む図版は `FWrapped` を置いた後に入るかを確かめないので、あふれる見込みが高い。

[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙は、手での制御（`FNeedLines`、`FBlank` など）と、表と回り込む図版を対象にしていない。
そのため、この二つの違反は、列挙のテストでは見つからなかった。

## 実装すること

### 1. `@need-lines`

`applyNeed` の、残りが足りないときの枝を、`keep` で書き直す。
量は N とし、送った図版と続きの注を置いた後の段で確かめ直す。
N が段の行の数より大きいときの扱い（`UnmetNeedLines` を記録し、空の段なら進まない）は変えない。

`keep` は、段が空になれば止まる。
空の段では N 行が必ず空いている（N が段の行の数以下の場合）ので、`@need-lines` は必ず守られ、`UnmetNeedLines` は N が段の行の数より大きいときだけ記録される。

### 2. 行アキ

`placeBlank` の手順の 3 を、`keep` で書き直す。
量は、行アキの行数の和と、置くものの最初の部分の和とする（今の `total + needIn ...` と同じ）。
進んだ先の段が先頭（`sUsed == top`）なら、手順の 4 のとおり行アキを捨て、`DroppedBlank` を記録する。
送った図版が先頭に置かれた段は、先頭ではない（「メンテナーが決めること」の 1）。
その段に、行アキと置くものの最初の部分が入れば行アキを置き、入らなければさらに進む。

これで、行アキが段からあふれることも、途中で切り詰められることもなくなる。

### 3. 同じ作りの残りを確かめる

表と回り込む図版の二つについて、送った図版の後で違反が起きるかを、実装の最初に確かめる（「メンテナーが決めること」の 2）。

- 起きれば、同じ原因なので、この ADR で `keep` を使って直す。表は、見出しの行と最初の行の和を量とする。回り込む図版は、図版の行と脇の行の多いほうを量とする。
- 起きなければ、起きない理由を PR の説明に書き、変えない。

`nextColumn` を一度だけ呼ぶほかの箇所（段落と連と罫線のまとまりを分ける箇所、改段、改ページ）は、移った後に入るだけを数え直すか、移った先で何も確かめずに置いてよいものである。
実装のときに、各箇所がどちらであるかを PR の説明に一覧で書く。

### 4. 列挙を広げる

[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の `PaginateEnum` の要素に、`@need-lines 2`（`ENeedLines`）と、1 行と 2 行の行アキ（`EBlank 1`、`EBlank 2`）を足す。
`PaginateInvariants` に、下の P1 から P4 の述語を足す。
要素が 3 個増えるので、プルリクエストの上限の時間（[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の「メンテナーが決めること」の 3）を測り直し、延びすぎるなら足す要素を減らす（「メンテナーが決めること」の 3）。
表と回り込む図版は、3 で違反が見つかった場合に限り、列挙に足すかを、範囲を広げる ADR（[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)）の「ページ分割の残りの要素」で決める。

### 5. 文書

- [docs/specifications.md](../../specifications.md) の「行アキ」の節の手順の 3 を、「入るか、段が空になるまで次の段へ進む」に改める。送った図版の後の段は先頭ではないことを書く。
- 「改ページの手での制御」の `@need-lines` の文に、送った図版の後の段でも数え直すことを書く。
- 出力が変わる本があれば、変わったページを目で確かめてから、`scripts/determinism/hashes.txt`、golden、見た目の回帰テストの参照を改める。

## 実装しないこと

- **`@need-lines` の判定に行アキを数えること**：仕様書の「`@need-lines` の判定に行アキの行数は数えない」のとおりとする。
- **段落と `@no-page-break` のあいだの行アキ**：[golem-layout ADR 0022](0022-no-page-break-counts-spaces.md) が docs/roadmap.md の未決事項に回したものである。この ADR では扱わない。
- **`@page-lines`（`adjustLines`）**：段の行の数を変えるもので、次の段へ進まない。
- **表と回り込む図版の列挙**：4 のとおり、範囲を広げる ADR で決める。

## 不変条件

段の行の数を C、今の段の行の数（`@page-lines` を当てたもの）を C' とする。

- **P1 `@need-lines` を守る**：`@need-lines N`（N ≤ C'）の後に置かれる最初のブロックは、置く直前の段の残りが N 行以上ある段に置かれる。ただし、その段が空の段であるときを除く。
- **P2 守れない `@need-lines` だけを記録する**：`UnmetNeedLines` は、N が C' より大きい `@need-lines` に限って、ちょうど一つずつ記録される。
- **P3 行アキはあふれない**：行アキを置いた段では、置いたものと行アキと注の本文と区切りの行の和が C' を超えない（[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の I2 の、行アキを含めた形）。
- **P4 行アキは後と同じ段に置くか、捨てて記録する**：行アキは、後に置くブロックの最初の部分と同じ段に置かれるか、段の先頭で捨てられて、`@blank-line` ごとにちょうど一つの `DroppedBlank` が記録される。捨てない行アキが、後のブロックと別の段に置かれることはない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 送った図版 | なし、一つ（段の残りより 1 行多い）、二つ |
| `@need-lines` の N | 1、2、C、C + 1 |
| 行アキの行数 | 1、2、C |
| 移った段の残り（図版の後） | 0、1、N − 1、N、ちょうど行アキと最初の部分が入る |
| 段の数 | 1、2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、P1 から P4 の番号を入れる。

- **P1**：`paginate 1 4 [FParagraph 3 行, FFigure 3 行, FNeedLines 2, FParagraph 1 行]` で、段落が 3 ページに置かれ、警告が出ないこと。今は 2 ページの図版の後に置かれるので失敗する。二段組みでも同じ形を確かめる。
- **P2**：同じ入力で `UnmetNeedLines` が記録されないこと。N を C + 1 にすると、ちょうど一つ記録されること。
- **P3**：`paginate 1 4 [FParagraph 3 行, FFigure 3 行, FBlank 2, FParagraph 1 行]` で、どの段も 4 行を超えないこと。今は 2 ページで 5 行を使うので失敗する。
- **P4**：同じ入力で、行アキが 3 ページの先頭で捨てられ、`DroppedBlank` が一つ記録されること。行アキと段落が図版の後に入る場合（段の行の数 6）は、行アキが捨てられずに図版の後に置かれ、段落と同じ段にあること。
- 列挙：4 で足した要素を含めた全入力で、P1 から P4 と I1 から I8 が成り立つこと。
- 今の `PaginateSpec` の `@need-lines` と行アキのテストが、変わらず通ること。
- 3 で違反が見つかった表と回り込む図版には、最小の反例を回帰のテストにする。

## トレードオフ

送った図版の後で `@need-lines` と行アキを守るために、段を余分に進む場面が出る。
段の末尾の空きは増えるが、書き手が指定した `@need-lines` と行アキを守り、段からあふれることもなくなる。

列挙に要素を三つ足すと、入力の数が増える。
[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の実装で、要素 3 個の上限で 4 秒だったので、要素の候補が増えた分だけ時間が延びる。
延びすぎるときは、足す要素を `ENeedLines` と `EBlank 2` の二つに絞る。

表と回り込む図版は、確かめてから直すので、この ADR の範囲が実装のときに決まる。
同じ原因のものを別の ADR に分けると、同じ直し方を二度決めることになるので、この形にした。

## メンテナーが決めること

1. **送った図版の後の段は、行アキにとって「段の先頭」か**：推奨は、先頭ではないとすることである。仕様書の「段の先頭」は、段に何も置いていない状態（`sUsed == top`）であり、図版を置いた後はそうでない。図版と後のブロックのあいだの行アキは、書き手が区切りとして書いたもので、残す意味がある。
   - 退けた案は、送った図版だけを置いた段も先頭とみなし、行アキを捨てることである。図版の直後の区切りが黙って消え、図版をどこに送ったかで行アキの有無が変わる。
2. **表と回り込む図版を、この ADR で直すか**：推奨は、実装の最初に確かめ、同じ原因の違反があればこの ADR で直すことである。原因と直し方が同じなので、ADR を分けると同じ決定を二度書くことになる。
   - 退けた案は、`applyNeed` と `placeBlank` だけを直し、表と回り込む図版は別の ADR にすることである。
3. **列挙に足す要素**：推奨は、`ENeedLines`（N = 2）、`EBlank 1`、`EBlank 2` の三つである。N = 2 は、N = 1 では守れない場面が起きにくく、C 以上では空の段で必ず守れるためである。プルリクエストの時間が延びすぎるなら、`EBlank 1` を外す。
   - 退けた案は、N を 1 から C まで列挙することである。入力の数が増えるわりに、境界の値は表の値で足りる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md)、[golem-layout ADR 0024](0024-recto-start-places-figures-sent-on-first.md)、[golem-layout ADR 0022](0022-no-page-break-counts-spaces.md)、[golem-layout ADR 0003](0003-pagination-and-s2.md)
- [docs/adr/0030](../../adr/0030-manual-page-break-control.md)、[docs/adr/0046](../../adr/0046-blank-line-command.md)、[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md)、[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)
- [docs/specifications.md](../../specifications.md) の「行アキ」と「改ページの手での制御」の節
- [#650](https://github.com/tett23/golem/pull/650) の報告
