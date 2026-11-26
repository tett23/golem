# ADR 0441: 行数を変えた段から索引の段組みに切り替えるページで、索引の段の最後の行を決める

Status: accepted

## 文脈

一段組みの版面で `[index]` の `columns` が版面の段数と違うと、PDF は `@index` の位置で段数を切り替え、そのページの残りの行を索引の段に分ける（[root ADR 0025](0025-index-columns.md)）。
切り替えのページに脚注があれば、脚注の本文が占める行をページの下から除いた残りを分ける。

一方、`@page-lines` は印の位置の段の行数だけを変え、脚注を、増やした（減らした）段の下部に置く（[root ADR 0030](0030-manual-page-break-control.md)）。
`@page-lines` で行数を変えた段から索引に切り替えると、二つの決まりが、行の進む方向（横組みでは下、縦組みでは左）の別の終わりを指す。
脚注は変えた段の終わりに描かれるが、索引の段は版面の終わりから脚注の行を除いた範囲で組まれる。
そのため、行数を減らしたページでは、索引の行が脚注の区切りと本文に重なる。
この ADR は、切り替えのページで、索引の段の最後の行をどこにするかを決める。

この ADR では、行の番号を、段の最初の行を 0 として行の進む方向に数える。
格子の行の番号は、横組みでも縦組みでも同じに数える。
「脚注の行数」は、区切りの行を含む。

## 調査した事項

origin/main（[b9eb4f236](https://github.com/tett23/golem/commit/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652)）で、次のことを確かめた。

- PR #1128 は、`@page-lines` で増やした行を切り替えの残りの行に数えず、索引の段の行数を版面の行数のままにした。
  同じページで切り替えるかは、版面の行数から使った行と脚注の行を引いた `typeAreaFree` が正かで決める（[Paginate.hs#L564](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/modules/golem-layout/src/Golem/Layout/Paginate.hs#L564)、[State.hs#L157-L158](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L157-L158)）。
  使った行が段の上限に届くと、段は空と見なされ、一行を強制して置く（[State.hs#L165](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L165)）。
- 索引の段を始める `startSet` は `sAdjust` を 0 にし、脚注の行の数（区切りを含む `sNoteLines`）を `sReserved` として持ち越す（[State.hs#L324-L331](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L324-L331)）。
  索引の段の上限は、版面の行数から脚注の行数を引いた値になる（[State.hs#L143-L151](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L143-L151)）。
  同じページの次の段へ進むときも、`sAdjust` を 0 にし、脚注の行数を `sReserved` から戻す（[State.hs#L299-L301](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L299-L301)）。
- 閉じた本文の段は、`@page-lines` で変えた行数を `poLines` に記録し（[State.hs#L277](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L277)）、描画は脚注をその段の `poLines` の終わりから置く（[Draw.hs#L1728](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L1728)）。
- 版面 10 行、区切り 1 行で、`@page-lines -3`、最初の行に 2 行の脚注を持つ 2 行の段落、二段の索引の項目 12 個をページ分割の関数に渡すと、次のようになった（`cabal exec runghc` で確かめた）。
  - 本文の段は `poLines` 7 で、区切りは行 4、脚注は行 5 と 6 に描かれる。
  - 索引の二つの段は行 2 から 6 を使い、行 4 から 6 が区切りと脚注に重なる。
  - `@page-lines` が無いときは、区切りが行 7、脚注が行 8 と 9 に来て、重ならない。
- 自由な配置（[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md)）のページ分割は、切り替えで `psAdjustment` と `psNotesUsed` を残し、次の段で 0 に戻す（`Paginate/Physical.hs` の 927 行から 933 行、304 行、309 行）。
  コードを読んだ範囲で、実行はしていない。
- PR #1128 は、マニュアルの `05-style.gm` にも、増やした行を残りの行に数えないことを足した。
- golem の CLI で原稿を組んで確かめてはいない。

## 実装すること

### 切り替えのページの索引の段の終わり

切り替えのページの索引の段は、どの段も、行の番号が次の値より小さい行だけを使う。

```text
終わり = min(版面の行数, 切り替える前の段の行数 − 脚注の行数)
```

切り替える前の段の行数は、`@page-lines` で変えた後の行数である。
脚注の行数は、区切りを含み、脚注が無ければ 0 である。
変えた段の脚注は、今までどおりその段の終わりに置くので、この値は脚注の区切りの行の番号と、版面の行数の小さいほうになる。

- 行数を減らしたページでは、索引は脚注の区切りの前で終わり、脚注に重ならない。
- 行数を増やしたページでは、索引は版面の終わりまで使い、版面の外に出ない。
- `@page-lines` が無いページでは、今と同じ（版面の行数から脚注の行数を引いた値）になる。

### 同じページで切り替えるか

同じページで切り替えるかは、上の終わりから使った行数を引いた残りが正かで決める。
残りが 0 以下なら、次のページの最初から索引の段に分ける。

### 次のページから

次のページからは、今までどおりページの全体の行を索引の段に分ける。

### 自由な配置

自由な配置のページ分割でも、同じ終わりと同じ判定を使う。
長さは行の数ではなく、行の進む方向の長さで数える。

### 文書とステータスの行

仕様書の索引の段組みの節と、マニュアルの `05-style.gm` に、この規則を一文ずつ足す。
マニュアルのページの見た目が変われば、見た目の検査の参照を更新する。

採択したら、[root ADR 0025](0025-index-columns.md) のステータスに、「切り替えの位置」の節の切り替えのページの段の終わりを、この ADR が補ったと記録する。

```text
superseded [{"part":"切り替えの位置","by":["docs/adr/0441-index-columns-on-a-page-with-adjusted-lines.md"],"kind":"supplement"}]
```

## 実装しないこと

`@page-lines` の意味（印の位置の段だけを変える）は変えない。
変えた段の脚注の位置は変えない。
二段以上の版面からの切り替え（今のページを閉じて次のページから始める）は変えない。
脚注を索引の段に置くことはしない。

## 不変条件

- I1: 切り替えのページで、どの索引の段のどの行も、切り替える前の段の脚注の区切りと脚注の本文の行と重ならない。
- I2: 切り替えのページで、どの索引の段の最後の行の番号も、`min(版面の行数, 切り替える前の段の行数 − 脚注の行数)` より小さい。
- I3: 切り替えの位置で使った行数が I2 の終わり以上なら、索引は次のページの最初から始まり、切り替えのページに索引の行は無い。
- I4: `@page-lines` を使わない原稿の出力は、この ADR の前と等しい。

| 入力（版面 10 行、区切り 1 行、索引は二段） | 期待 | 不変条件 |
| --- | --- | --- |
| `@page-lines -3`、2 行の段落と 2 行の脚注、索引 12 項目 | 索引は行 2 と 3 だけを使い、残りは次のページ | I1, I2 |
| `@page-lines -3`、脚注なし、2 行の段落、索引 12 項目 | 索引は行 2 から 6 を使う | I2 |
| `@page-lines -3`、脚注 2 行、3 行の段落（ちょうど 1 行残る） | 索引は行 3 だけを使う | I1, I2 |
| `@page-lines -3`、脚注 2 行、4 行の段落（残りが 0 行） | 索引は次のページから | I3 |
| `@page-lines -3`、脚注 2 行、5 行の段落（一行あふれる） | 索引は次のページから | I3 |
| `@page-lines +3`、2 行の段落と 2 行の脚注 | 索引は行 2 から 9 を使い、脚注は行 10 から 12 | I1, I2 |
| `@page-lines` なし、2 行の段落と 2 行の脚注 | 今と同じ（索引は行 2 から 6） | I1, I4 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0441 I1 から I4 を名前の先頭に置いたテストを、golem-layout の `PaginateSpec.hs` と `PhysicalPaginateSpec.hs`、golem-driver に足す。
I1 から I3 は、境界の表の入力をページ分割の関数に渡し、索引の行の番号と脚注の位置を比べる。
golem-driver では、境界の表の一行目の原稿を組み、PDF の索引の行と脚注の行の位置が重ならないことを確かめる。
I4 は、今の試験と golden が変わらないことで確かめる。
I1 から I3 は、実装の前に落ちることを確かめる。

## トレードオフ

行数を減らしたページでは、索引の段が短くなり、索引のページ数が増えることがある。
その代わりに、0030 の脚注の位置を変えずに、重なりを無くせる。

行数を増やし、脚注を持つページでは、PR #1128 の振る舞い（索引は版面の行数から脚注の行数を引いた範囲）より索引が長くなる。
増やした段の脚注は版面の外に置かれるので、索引が版面の終わりまで使っても重ならない。

## 参考文献

- [root ADR 0025](0025-index-columns.md)
- [root ADR 0030](0030-manual-page-break-control.md)
- [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md)
