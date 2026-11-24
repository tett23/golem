# ADR 0444: 脚注の本文が次の段へ続くとき、段に空きができたら、その続きを先に置く

Status: accepted-pending

## 文脈

PDF のページ下の脚注は、注の印を含む行か見出しと同じ段に置き、段の先頭に置いても注の本文が収まらないときだけ、注の本文を分けて次の段に続ける（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)）。
この ADR では、分けた注の本文のうち、まだ置いていない部分を「続きの注」と呼ぶ。
格子の配置では `sPendingNotes`、自由な配置（[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md)）では `psCarry` がこれを持つ。
「段の空き」は、段の上限から、置いた本文と脚注（区切りを含む）が占める長さを引いた残りとし、格子の配置では `free`、自由な配置では行送りで割った残りの行の数で数える。

注の本文を分けるとき、段の空きは、同じブロックの後の行のために取っておく分を除いて、その注の本文に使われる。
そのため、続きの注がある段に後の注が入るのは、分けた後で段の空きが増えたときだけである。
`@page-lines` で段の行数を増やしたときがこれに当たる。
このとき、今の実装は、後の注の本文をその段に置く。
読み手は、注 1 の前半、注 2、注 1 の後半の順に読むことになる。
この ADR は、`@page-lines` で段の空きが増えたら続きの注を先にその段に置き、脚注の本文が原稿の順に並ぶようにする。

## 調査した事項

origin/main（[b2dd37006](https://github.com/tett23/golem/commit/b2dd3700629d4996faa700b7e985706d2bdf28db)）で、次のことを確かめた。

- 仕様書は、脚注を印のある行か見出しと同じページ（段）に置き、入らなければ行か見出しを注とともに次のページ（段）に送り、注の本文を分けるのは段の先頭でも収まらない場合に限ると定める（[specifications.md#L7894-L7897](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/docs/specifications.md#L7894-L7897)）。
  前のページから続く脚注は次の本文のページに続け（[specifications.md#L5324](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/docs/specifications.md#L5324)）、その段の末尾に先に置く（[specifications.md#L5333](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/docs/specifications.md#L5333)、[specifications.md#L5817](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/docs/specifications.md#L5817)）。
  注のあいだの順を決める文は無い。
- 格子の配置の `fitting` は、行とその注の行数だけで、行が段に収まるかを決め、続きの注を見ない（[Decide.hs#L275-L284](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L275-L284)）。
  行を置く `putLineKeeping` も、続きの注があっても、後の行の注を段の空きに置く（[State.hs#L223-L238](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L223-L238)）。
- 自由な配置の `putLineWithReserve` も、続きの注が残っていても、後の行の注を段の空きに置く（[Physical.hs#L404-L429](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L404-L429)）。
- 格子の配置の `@page-lines` は `adjustLines` で `sAdjust` を変え、段の行数 `envCapacity env + sAdjust st` を増やす（[Paginate.hs#L379-L390](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/modules/golem-layout/src/Golem/Layout/Paginate.hs#L379-L390)、[State.hs#L146-L147](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L146-L147)）。
  増やせる量は、段の行数の上限（`envMaxLines`）までである。
  自由な配置では、`FAdjustLines` の場合が同じことをする（[Physical.hs#L937](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L937)）。
- 段の上限が置いている途中で戻る経路は、ほかにもある。
  格子の配置の囲みの終わり（[State.hs#L142-L143](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L142-L143)）と、自由な配置の表の行（[Physical.hs#L1609-L1617](https://github.com/tett23/golem/blob/b2dd3700629d4996faa700b7e985706d2bdf28db/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1609-L1617)）である。
  これらは、後の行のために取っておいた場所を、その行が使うだけである。
  上限が戻るのと同時に使った長さも進むので、段の空きは増えない。
  これはコードを読んだ範囲での判断で、実行して確かめてはいない。
- 次の入力を自由な配置のページ分割に渡した（`cabal exec runghc` で確かめた）。
  段の長さは 40 sp、行送りは 10 sp、区切りは 0、一段である。

  ```text
  [5 行の注 500 を持つ行 0, FAdjustLines 2, 1 行の注 510 を持つ行 10, 段落]
  ```

  1 ページ目に注 500 の 0 行目から 2 行目と注 510 の全体が、2 ページ目に注 500 の 3 行目と 4 行目が置かれた。
  `FAdjustLines` が無いと、行 10 は 2 ページ目に送られ、注 510 は注 500 の続きの後に置かれた。
  区切りを 10 sp、段の長さを 50 sp にしても同じだった。
- 同じ入力を格子の配置（`paginateWithin`）に渡しても、同じ順になった。
- A6、一段 8 行の自由な配置の原稿で、長い注を持つ一行、`@page-lines +2`、短い注を持つ一行、一行の段落の順に書いて PDF を組んだ。
  PDF から抜いた文字は、1 ページ目に注 1 の前半と注 2 が、2 ページ目に注 1 の続きが並んだ。
  格子の配置では、注を長くした原稿で同じ順になった。
- この並びは、[root ADR 0352](0352-prove-pagination-in-lean.md) の Lean のモデル（PR #964 のブランチ `codex/impl-0352` の `experiments/pagination-proof/Physical.lean`）で、脚注の本文の行が置かれることを証明しようとして見つかった。
  脚注の本文の行が一度ずつ置かれることは成り立つが、原稿の順に並ぶことは成り立たない。

## 実装すること

### `@page-lines` で段の空きが増えたとき

格子の配置と自由な配置の両方で、続きの注がある段に `@page-lines` を適用し、段の空きが増えたら、その時点で、続きの注をその空きに置く。
格子の配置では `adjustLines` の後、自由な配置では `FAdjustLines` の場合の後である。
置く順は、続きの注の順（原稿の注の順）である。
空きに入りきらない分は、今までどおり次の段に続ける。

置く量は、その配置が段の始めに続きの注を置くときの規則に合わせる。
格子の配置では、段にまだ本文の行が無ければ、`carryNote` と同じく本文の行を一行残し、本文の行があれば段の空きをすべて使う。
そのため、注だけの段はできない。
自由な配置では、`carryInto` と同じく、本文の分を残さない。

### 後の行の判定

続きの注を空きに置いた後に、続きの注がまだ残っていれば、格子の配置では段の空きは 0 行（本文の行がまだ無い段では 1 行）になり、自由な配置では脚注の行送りより短くなる。
そのため、注を持つ行か見出しは、今までの判定（格子の配置の `fitting`、`roomForLine`、`needIn`、自由な配置の `fitting`）で、注とともに次の段に送られる。
判定の関数は変えない。

注を持たない行が段の空きに入るときは、今までどおり置く。

表の行と罫線のブロックの行は、注の本文を一行も置けなくても印の行を置き、注の本文を続きの注の後に足す（自由な配置の `putLineWithReserve` の `allowNoteContinuation`）。
この ADR の後は、続きの注が残る段に注の本文を置く空きが無いので、この経路の新しい注も続きの注の後に回り、順は保たれる。

### 文書とステータスの行

仕様書の脚注の節に、脚注の本文が原稿の順に並ぶことと、この規則を書く。
golem-layout の [ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md) の今の `superseded [...]` の配列に、次の項目を足す。

```text
{"part":"脚注","by":["docs/adr/0444-keep-footnotes-in-order-while-one-continues.md"],"kind":"supplement"}
```

## 実装しないこと

注の印を含む行か見出しと、その注の本文の始まりを、別の段に置く扱い（印を残して注の本文だけを次の段に回す）は足さない。
注の本文を分ける条件（段の先頭でも収まらないとき）は変えない。
回り込ませる図版の脇の行の脚注の扱い（[root ADR 0443](0443-count-side-line-notes-when-a-wrapped-figure-fits.md) の草案）は、この ADR では変えない。

## 不変条件

どの不変条件も、PDF のページ下の脚注についての性質である。
段の前後は、ページの順、同じページの中では段の順（段組みを切り替えたページでは、前の段組みの段の後に後の段組みの段）、同じ段の中では置いた順で決める。

- I1: 二つの注 i と j の印が原稿でこの順に出るなら、i の本文のどの部分も、j の本文のどの部分より前に置かれる。
- I2: 続きの注がある段に `@page-lines` を適用した直後に、続きの注がまだ残っていれば、その段の空きは、格子の配置では 0 行（本文の行がまだ無い段では 1 行）、自由な配置では脚注の行送りより短い。
- I3: この ADR の前の実装の出力で、どの注の本文も次の段に続かないなら、この ADR の後の出力はそれと等しい。
- I4: 本文の行は、どれも一度ずつ原稿の順に置かれる（一度ずつの部分は [root ADR 0352](0352-prove-pagination-in-lean.md) の不変条件 5 に当たる）。

| 入力（格子の配置、一段 5 行、段の行数の上限 9 行以上、区切り 1 行。行 0 は段の先頭で 5 行の注 500 を持ち、区切りと注 500 の 3 行がその段に入る） | 期待 | 不変条件 |
| --- | --- | --- |
| 行 0、`@page-lines +2`、1 行の注 510 を持つ行 10 | 注 500 の残りの 2 行は 1 ページ目に入る。行 10 と注 510 は 2 ページ目 | I1 |
| 同じで `@page-lines +1` | 注 500 の 1 行が 1 ページ目に入り、1 行が 2 ページ目に続く。行 10 と注 510 は 2 ページ目で、注 500 の続きの後に注 510 | I1, I2 |
| 同じで `@page-lines +3`（行 10 と注 510 の 2 行に対して残りが 1 行で、一行あふれる） | 行 10 と注 510 は 2 ページ目 | I1 |
| 同じで `@page-lines +4`（残りが 2 行で、ちょうど収まる） | 行 10 と注 510 は 1 ページ目で、注 500 の後 | I1 |
| `@page-lines +3`、注を持たない行 10 | 行 10 は 1 ページ目に残る | I1, I4 |
| 行 0 と `@page-lines +1` の後に、注を持たない 2 行の段落 | 段落は 2 ページ目から | I2, I4 |
| 注の本文が分かれない原稿 | 今と同じ | I3 |
| 自由な配置（段の長さ 50 sp、行送り 10 sp、区切り 10 sp）で、一行目と同じ原稿 | 格子の配置と同じ順 | I1 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0444 I1 から I4 を名前の先頭に置いたテストを、golem-layout の `PaginateSpec.hs` と `PhysicalPaginateSpec.hs` に足す。
境界の表の入力をページ分割の関数に渡し、注の部分の並びと、行の段を比べる。
I1 と I2 は、注を持つ行、`@page-lines`、囲みの終わり、自由な配置の表の行を小さな範囲で列挙して確かめる。
I3 は、同じ列挙の入力について、実装の前のコミットで書き出した出力を golden として置き、注が分かれない入力の出力がそれと等しいことを確かめる。
golem-driver では、表の一行目の原稿を組み、PDF から抜いた注の文字が原稿の順に並ぶことを確かめる。
表の一行目の I1 と、二行目の I2 と注 500 の置き場所は、実装の前に落ちることを確かめる。
[root ADR 0352](0352-prove-pagination-in-lean.md) の Lean のモデルにも同じ扱いを写すかは、そのプルリクエストで決める。

## トレードオフ

段が長くなった分は、本文の行より先に、続きの注に使われる。
`@page-lines` で行を増やしても、続きの注があるあいだは、本文の行は増えない。
その代わりに、注を分ける量が減り、注は原稿の順に並び、段の終わりに空きも残らない。
段の空きが前より減るので、続きの注がある段では、見出しの直後で改ページしない規則や `@need-lines` などの保ちの規則が、前より多くのものを次の段に送ったり、満たせない記録を出したりすることがある。

別の案として、続きの注があるあいだは、注を持つ行だけを次の段に送り、段が長くなった分を本文の行に使う方法がある。
この案では本文の行が増えるが、注を持つ行を送った後は、原稿の順を保つためにその後の行も送ることになり、段の終わりに空きが残る。
さらに、注を分けた段に、続きの注を置ける空きがあるのに注を次の段へ続けることになるので、採らない。

## 参考文献

- [golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)
- [root ADR 0352](0352-prove-pagination-in-lean.md)
- [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md)
