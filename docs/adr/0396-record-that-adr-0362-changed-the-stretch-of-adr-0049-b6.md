# ADR 0396: [ADR 0362](0362-unbreakable-spacing.md) が [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の B6 の伸びを変えたことを記録し、毎晩の列挙のテストの述語を直す

Status: accepted

## 文脈

2026-11-18 の毎晩の列挙のジョブ（`enum.yml` の実行 44215045635、コミット `c5993c5ee`）が落ちた。
落ちたのは golem-layout-test の、縦組みと横組みの項目を比べるテストである（[`LineBreakInvariantsSpec.hs` の 260 行](https://github.com/tett23/golem/blob/c7f6d094c3df05de1c6ea9eeeb600e0754a75f18/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L260-L264)）。
入力は、全角の数字「１」が二つ続く並びであった。

このテストは flaky ではない。
毎晩の深さ（`GOLEM_ENUM_LINES_DEPTH=3`）では、同じ入力で必ず落ちる。
プルリクエストの深さでは、部品を一つまでしか並べないので、この入力を作らない。
そのため、原因の変更はプルリクエストの CI を通って `main` に入った。

原因は、[ADR 0362](0362-unbreakable-spacing.md) の実装（[#1011](https://github.com/tett23/golem/pull/1011)、マージ `eff3d57ee`）である。
誤っているのはテストの述語で、実装は [ADR 0362](0362-unbreakable-spacing.md) のとおりである。
[ADR 0362](0362-unbreakable-spacing.md) は、[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の B6 の一文を変えた。
しかし、そのことを [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) のステータスの行にも、テストの述語にも書かなかった。
この ADR は、その変更を記録し、テストの述語を [ADR 0362](0362-unbreakable-spacing.md) に合わせる。

## 調査した事項

調べは Fable の `auditor` に任せ、返ったコマンドと出力を確かめた。

- **再現**：`main`（`cf244a2b5`）を展開してビルドし、`GOLEM_ENUM_LINES_DEPTH=3 GOLEM_ENUM_LINES_SAMPLES=5000000 golem-layout-test -p '/line breaking invariants on/&&/vertical writing: up to 2 parts/'` を二回動かした。
  二回とも、`failedValue = ["\65297","\65297"]` で落ちた。
  環境変数を付けない（プルリクエストの深さ）と通った。
- **境目**：`eff3d57ee` の第一の親 `39eb1ebc1` では、同じコマンドが通った。
  `eff3d57ee` では落ちた。
- **項目の違い**：`cabal repl golem-layout-test` で、テストの項目の関数 `itemsOf` を「１１」に当てて並べた。
  横組みと縦組みの違いは、数字のあいだのグルーの伸びだけであった（横組みは 0、縦組みは 65536 sp）。
  このテストが列挙する入力は 813 件である（落ちた実行の `expected: Passed 813`）。
  同じ repl で 813 件を調べると、述語が偽になるのは「１|１」だけであった。
  グルーの伸びを無視して比べると、偽になる入力は 0 件であった。
- **実装**：連数字の組は、横組みでだけ分割を禁じる（[`pairKept`](https://github.com/tett23/golem/blob/c7f6d094c3df05de1c6ea9eeeb600e0754a75f18/modules/golem-layout/src/Golem/Layout/Japanese.hs#L2336-L2342)）。
  [ADR 0362](0362-unbreakable-spacing.md) の実装は、分離禁止文字と `pairKept` の位置のアキのグルーで、伸びの上限を最適の値にする（[`adjusted`](https://github.com/tett23/golem/blob/c7f6d094c3df05de1c6ea9eeeb600e0754a75f18/modules/golem-layout/src/Golem/Layout/Japanese.hs#L2383)）。
  縦組みの連数字は `pairKept` が偽なので、伸びが残る。
  B3 と B4 の組は、縦組みでも `pairKept` が真なので、伸びは 0 である。
- **縦組みの数字の分割**：縦組みの全角の数字の並びは、B2 ではなく「数と単位」の規則（[ADR 0275](0275-keep-numbers-with-the-units-after-them.md)、[ADR 0282](0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md)）で、既定では字のあいだで分けない（[`numberUnit`](https://github.com/tett23/golem/blob/c7f6d094c3df05de1c6ea9eeeb600e0754a75f18/modules/golem-layout/src/Golem/Layout/Japanese.hs#L2348-L2357)）。
  この規則の罰点は `number-unit-penalty` で、既定は 10000 であり、書き手が下げれば分けられる。
  [ADR 0362](0362-unbreakable-spacing.md) の実装のテストも、縦組みの数字のあいだが伸びることを確かめている（[`UnbreakableSpacingSpec.hs` の 85 行](https://github.com/tett23/golem/blob/c7f6d094c3df05de1c6ea9eeeb600e0754a75f18/modules/golem-layout/test/UnbreakableSpacingSpec.hs#L85-L88)）。
- **テストの述語**：落ちたテストは、縦組みの項目に [`forbidPairs`](https://github.com/tett23/golem/blob/c7f6d094c3df05de1c6ea9eeeb600e0754a75f18/modules/golem-layout/test/LineBreakInvariants.hs#L804-L805) を当てたものを、横組みの項目と比べる（[`keysOfDigitsKept`](https://github.com/tett23/golem/blob/c7f6d094c3df05de1c6ea9eeeb600e0754a75f18/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L197-L200)）。
  `forbidPairs` は罰点だけを替え、グルーの伸びを変えない。
  これは [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の B6 の「箱、グルーの幅と伸び縮みは変わらない」の読みであり、[ADR 0362](0362-unbreakable-spacing.md) の前には正しかった。
- **ADR どうし**：[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の B6 は、B2 から B4 で候補を消した入力について、グルーの伸び縮みが変わらないと書く。
  [ADR 0362](0362-unbreakable-spacing.md) は、B2 から B4 の組の位置で、伸びを 0 にする（[ADR 0362](0362-unbreakable-spacing.md) の文では「伸びの上限を 0 にする」）と決めた。
  [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) のステータスの行は、[ADR 0282](0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md) による一部の置き換えだけを記し、[ADR 0362](0362-unbreakable-spacing.md) を記していない。
  [ADR 0362](0362-unbreakable-spacing.md) の本文は、縦組みの連数字に触れていない。

## 実装すること

### 記録

[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の B6 のうち「グルーの伸び縮みは変わらない」の部分は、[ADR 0362](0362-unbreakable-spacing.md) が次のとおりに変えたものとして記録する。

- B2 から B4 の組の位置のアキのグルーは、幅と縮みを変えず、伸びを 0 にする（アキの最大を最適の値にする）。
- 縦組みの、全角の数字が二つ続く位置は、B2 の対象ではない（B2 は横組みだけを対象にする）。
  そのため、[ADR 0362](0362-unbreakable-spacing.md) の対象でもなく、アキ量のセットの伸びが残る。
  今の実装のこの振る舞いを、決めたこととする。

縦組みの数字のあいだの伸びを残すのは、伸びを決める規則と分割を決める規則を分けておくためである。
縦組みの全角の数字の並びを分けないのは、JLReq の分割禁止の組ではなく、「数と単位」の規則の罰点である。
この罰点は `number-unit-penalty` で書き手が変えられる。
伸びをこの罰点にそろえると、罰点の値でアキのグルーの伸びが変わることになり、二つの設定が絡み合う。
[ADR 0362](0362-unbreakable-spacing.md) が伸ばさないとした箇所は、分離禁止文字の連続と、[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の B2 から B4 の組であり、縦組みの連数字はそこに入らない。

採択したら、[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) のステータスの行の値（`Status:` の後）を次のとおりにする。
B6 の「グルーの幅と伸び縮みは変わらない」は、[ADR 0362](0362-unbreakable-spacing.md) の後は成り立たないので、補足ではなく置き換え（`kind` を省いた `replace`）とする。
修正先には、変えた [ADR 0362](0362-unbreakable-spacing.md) と、それを記録するこの ADR の二つを書く。

```
superseded [{"by":["docs/adr/0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md"],"part":"（縦組みの全角の数字の並び）"},{"by":["docs/adr/0362-unbreakable-spacing.md","docs/adr/0396-record-that-adr-0362-changed-the-stretch-of-adr-0049-b6.md"],"part":"（B6 のグルーの伸び縮み）"}]
```

### 仕様書

[docs/specifications.md](../specifications.md) の「行分割」の、三つの組と分離禁止文字の字間の段落を直す。

- 「伸びの上限だけを 0 にする」を、「伸びを 0 にする（アキの最大を最適の値にする）」に直す。
- 縦組みの全角の数字のあいだは B2 の組ではないので、選んだセットのとおりに伸びることを書き、この ADR へリンクする。

### テストの述語

`keysOfDigitsKept` の比べる値を、[ADR 0362](0362-unbreakable-spacing.md) に合わせる。
縦組みの項目に `forbidPairs False` を当てた後、横組みで分割を禁じる組の位置のアキのグルーの伸びを 0 にする。
この変換は、`forbidPairs` と並べて `LineBreakInvariants.hs` に置き、`adjacentPairs` と `pairForbidden False` で位置を決める。
`pairForbidden False` は B2 から B4 のすべての組を返すが、B3 と B4 の組は縦組みでも伸びがすでに 0 なので、変換はその位置では何も変えない。
変換が変えるのは、B2 の位置だけである。
[ADR 0362](0362-unbreakable-spacing.md) の実装は、B6 を見るもう一つのテスト（`UnbreakablePairsSpec`）を、golden を取り直して合わせた。
このテストは比べる相手が実装の出力なので、golden ではなく変換の関数で合わせる。
テストの名前とその上の注釈に、[ADR 0362](0362-unbreakable-spacing.md) とこの ADR を足す。

### プルリクエストで捕まえる

「１１」の一件を、プルリクエストの深さでも動く回帰のテストとして足す。
プルリクエストの深さは部品を一つまでしか並べないので、今は連数字の組を一度も作らない。
一件だけなので、範囲ごとの予算 10 秒（[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4）には響かないと見込む。
見込みは計測していないので、実装のプルリクエストで時間を確かめる。

## 実装しないこと

- 組版の実装は変えない。
  縦組みの数字のあいだの伸びも、横組みの B2 から B4 の位置の伸びも、今のままとする。
- プルリクエストの深さ（`formDepth`）は変えない。
- [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) と [ADR 0362](0362-unbreakable-spacing.md) の本文は変えない。

## 不変条件

「組の位置」は、`adjacentPairs` が返す、隣り合う二つの箱のあいだとする（コードと URL の箱どうしのあいだと、ルビの箱の端は含まない）。
「値」は、`breakParagraph` に渡す値（テストの `keyOf` が並べる、行の幅、項目の並び、`pExpansion`、`pProtrusion`）とする。

- I1：[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の列挙の部品を並べたどの入力でも、縦組みの項目に「横組みで分割を禁じる組の位置の罰点を無限にし、その位置のアキのグルーの伸びを 0 にする」変換を当てた値は、横組みの値に等しい。
- I2：縦組みで全角の数字が二つ続く組の位置のアキのグルーの伸びは、アキ量のセットの伸びに等しい。
- I3：横組みで全角の数字が二つ続く組の位置のアキのグルーの伸びは 0 であり、幅と縮みはアキ量のセットの値に等しい。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 空の段落 | 組の位置がなく、変換は何もしない | I1 |
| 「１」一つ | 組の位置がなく、変換は何もしない | I1 |
| 「１１」 | 縦組みの値に変換を当てると、横組みの値に等しい | I1 |
| 「あ１１い」 | 同上 | I1 |
| 「￥１」、「１％」 | 変換の前後で縦組みの値は同じで、横組みの値に等しい | I1 |
| 「１１」（縦組み、組み込みのセット） | 数字のあいだの伸びはセットの伸び（0 ではない） | I2 |
| 「１１」（横組み） | 数字のあいだの伸びは 0、幅と縮みはセットの値 | I3 |

組の外の字間（「１漢」の数字と漢字のあいだなど）がセットのとおりに伸びることは、[ADR 0362](0362-unbreakable-spacing.md) のテストが確かめるので、この ADR の不変条件には入れない。

## 受けいれ条件

- A1：毎晩の深さの段 `/line breaking invariants on/` の全体が、手元で通る。
  実装のプルリクエストに、動かしたコマンドと結果を書く。

## テスト設計

- I1：`keysOfDigitsKept` の比べる値を直したテストを、毎晩の深さ（`GOLEM_ENUM_LINES_DEPTH=3`、部品二つまで、行長 5 em まで）で動かして通す。
  名前は `root ADR 0396 I1: ...` とし、今の名前の内容（縦組みと横組みが数字のあいだを除いて同じ値になる）を続ける。
  直す前に、毎晩の深さで今の述語が「１|１」で落ちることを確かめる（[文脈](#文脈) の再現がそれに当たる）。
- I1 の回帰：「１１」の一件を、プルリクエストの深さで同じ述語にかけるテストを足す。
  名前は `root ADR 0396 I1: two digits in a row ...` の形とする。
  直す前の述語では落ち、直した後に通ることを確かめる。
- I2、I3：[`UnbreakableSpacingSpec.hs` の 85 行](https://github.com/tett23/golem/blob/c7f6d094c3df05de1c6ea9eeeb600e0754a75f18/modules/golem-layout/test/UnbreakableSpacingSpec.hs#L85-L88) のテストが、縦組みの「１２」の伸びと横組みの「１漢」の伸びを確かめている。
  縦組みの数字の部分を I2 のテストとして分け、名前を `root ADR 0396 I2: ...` にする。
  横組みの「１１」の伸びが 0 で、幅と縮みがセットの値であることを確かめる I3 のテストを足す。
  I2 と I3 は今の実装で通るので、先に失敗させる手順の例外とする。
  通ることを実装の前に確かめ、プルリクエストに書く。
- A1：毎晩の深さの段 `/line breaking invariants on/` の全体を手元で動かし、結果をプルリクエストに書く。

## トレードオフ

テストの述語と仕様書の文を直すだけなので、組版の出力は変わらない。
変わるのは、[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の B6 を読む人が、ステータスの行から [ADR 0362](0362-unbreakable-spacing.md) とこの ADR に辿れるようになることである。

縦組みの全角の数字のあいだを伸ばす振る舞いを決めたことで、縦組みで全角の数字を並べた行では、分けない数字のあいだが空くことがある。
縦中横を使わない書き手には、横組みと見た目がそろわない。
それを避けたい書き手が多いと分かったら、縦組みの数字のあいだも伸ばさない形を、新しい ADR で決める。

毎晩の深さでしか作らない入力に、似た述語の直し漏れが残っている見込みは、この ADR では調べていない。
回帰のテストは「１１」の一件だけを足す。

## 参考文献

- [ADR 0362](0362-unbreakable-spacing.md)
- [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md)
- [ADR 0282](0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md)
- [ADR 0275](0275-keep-numbers-with-the-units-after-them.md)
- [ADR 0208](0208-widen-lightweight-formal-methods.md)
- [ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)
