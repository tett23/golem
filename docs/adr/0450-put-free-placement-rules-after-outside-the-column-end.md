# ADR 0450: 自由な配置でも、段の終わりの後の `keep-in-column = false` の罫線を段の外に引く

Status: accepted

## 文脈

[golem-driver ADR 0040](../golem-driver/adr/0040-rules-outside-column-only-at-type-area-edge.md) は、`keep-in-column = false` の罫線を、領域を取らずに版面の外に引く位置を二つに限った。
一つは、版面の上端から始まる段の始まりの前の罫線で、もう一つは、段の終わりの後の罫線である。
段の終わりの後の罫線は、その段に脚注があれば段の中に収める。

自由な配置については、[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) の「段落の罫線」が、版面の外に線の全体が収まり、内側の間隔も取れるときは、本文の側に追加の長さを取らないと決めた。
仕様書は、両方の配置で、段の終わりの後の罫線を本文の側の領域を増やさずに版面の外に引くと書くが、0397 の「線の全体が収まる」ときという条件を写していない。
実装は、自由な配置では段の終わりの後の罫線を段の外に引かず、仕様書と合わない。

自由な配置では、最後の行の行ボックスが段の終わりにちょうど達することはまれである。
そのため、0397 の文だけでは、どの位置を基準に「版面の外に線の全体が収まる」かを決め、罫線を引いた後に段の中に残る隙間をどうするかが決まらない。
メンテナーは、自由な配置でも段の外に出すと決めた。
この ADR は、0397 の文を細かくし、自由な配置でいつ段の外に出し、どこに引き、その段をどうするかを決める。

## 調査した事項

origin/main（[2630685](https://github.com/tett23/golem/commit/26306852107440a42f84c26fdc75fa6135d846a8)）で、次のことを確かめた。

- 格子への配置は、段の終わりの後の罫線に、段に脚注がなければ `rsdOutside` を渡し、版面の外に出せるようにする（[Decide.hs#L401](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L401)）。
- 自由な配置は、段の終わりの後の罫線を置く四つの箇所で、どれも `rsdOutside = Nothing` を渡す。
  - 段落の後の罫線（[Physical.hs#L1425](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1425)）。
  - 見出しの後の罫線（[Physical.hs#L1514](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1514) と [#L1517](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1517)）。
  - 次のまとまりと共有できずに段の終わりで引く罫線（`flushPendingRule`、[Physical.hs#L1578](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1578)）。
- 自由な配置の `ruleAfterEdge` は、`rsdOutside` を受け取れば外に引く枝を持つ（[FreeGeometry.hs#L109-L120](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/FreeGeometry.hs#L109-L120)）。
  この枝は、罫線が最後の行の行ボックスの終わり以降にあり、行ボックスの終わりからはみ出す長さが余白に収まるときに、追加量 0 で引く。
  間隔を書いた罫線は字面の終わりから内側の間隔 `i` だけ離した位置に、書かない罫線は行ボックスの終わりと字面の終わりの遅いほうに引く（`max pitch exact`）。
  基準は行ボックスの終わりで、段の終わりではない。
  今は、どの呼び出しもこの枝を使わない。
- [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) は、`keep-in-column = false` の版面の外への配置を版面の端だけで許し、脚注に接する段の終わりでは内側へ置くと決めている（0397 の「段落の罫線」）。

## 実装すること

### 段の外に引く条件と位置

自由な配置で、後の罫線を最後の行のすぐ後に置くときの位置を、次のとおりとする。

- 間隔を書いた罫線は、最後の行の字面の終わりから `i` だけ離した位置。
- 間隔を書かない罫線は、最後の行の行ボックスの終わりと字面の終わりの遅いほう。

次の三つがすべて成り立つとき、罫線をこの位置に、段の領域を増やさずに引く。

1. 罫線が `keep-in-column = false` である。
2. その段に脚注がない。
3. この位置が段の終わり以降にあり、罫線が段の終わりからはみ出す長さが、版面の外の余白に収まる。

条件 3 で、位置が段の終わり以降なら、段の中の追加量で置いた罫線は必ず段の終わりを越える。
そのため、この罫線は仕様書のいう段の終わりの後の罫線にあたる。
間隔を書かない罫線が段の外に出るのは、最後の行の行ボックスか字面が段の終わりに達するときだけである。
[golem-driver ADR 0040](../golem-driver/adr/0040-rules-outside-column-only-at-type-area-edge.md) のとおり、段の終わりはいつも版面の端に接するので、版面の端の条件は置かない。
この ADR は、仕様書の段の終わりの後の罫線を版面の外に引く規則を、自由な配置では位置が段の終わり以降の場合に狭める。

三つのどれかが成り立たないときは、今と同じく、段の中の追加量か段の終わりの追加量で段の中に収める。
`i + w` が余白を超えるときは、今と同じく G07001 とする。

実装では、`ruleAfterEdge` の外に引く枝の基準を、最後の行の行ボックスの終わりから段の終わりに変える。
後の罫線を置く四つの箇所は、三つの条件が成り立つときに `rsdOutside` を渡す。

### 段を閉じる

罫線を段の外に引いたら、その段を閉じる。
続く内容（行、見出し、ブロック、図版、注）は、次の段から置く。
罫線は段の領域を増やさないので、段の終わりまでの隙間に続く内容を置くと、罫線と重なりうるためである。

### 文書とステータスの行

仕様書の「段落の罫線」の節の、両方の配置方式に当てはめる規則の箇条に、自由な配置での条件と位置と段を閉じることを書き、この ADR へリンクする。
[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) の、版面の外に線の全体が収まるときは追加の長さを取らないという文も、あわせて写す。

採択したら、[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) のステータスを `superseded [...]` にし、次の要素を入れる。
[root ADR 0449](0449-share-rule-areas-with-ruled-headings-in-both-placements.md) が同じ節に記録するときは、二つの要素を同じ配列に入れる。

```text
{"part":"段落の罫線","by":["docs/adr/0450-put-free-placement-rules-after-outside-the-column-end.md"],"kind":"supplement"}
```

## 実装しないこと

段の始まりの前の罫線の扱いは変えない。
その規則は [golem-driver ADR 0040](../golem-driver/adr/0040-rules-outside-column-only-at-type-area-edge.md) と [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) が決めている。

段の終わりより前から始まる罫線を、段の中と外にまたがって引くことはしない。
格子への配置の振る舞いも変えない。

## 不変条件

- I1: 自由な配置で段の外に引いた罫線は、段の終わり以降に始まり、段の終わりからはみ出す長さは余白の範囲に収まる。
- I2: 自由な配置で段の外に引いた罫線があるとき、その段のどの行も、罫線より前で終わる。
- I3: 自由な配置で、三つの条件のどれかが成り立たない後の罫線は、段の中（脚注があれば注の領域より前）に収まる。
- I4: 段の外に引いた罫線の段には、その罫線の後に、行、見出し、ブロック、図版、注を置かない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 間隔なし、最後の行の行ボックスがちょうど段の終わりで終わる | 段の終わりに引き、段を閉じる | I1, I2, I4 |
| 間隔なし、最後の行の行ボックスが段の終わりより 1 sp 前で終わる | 段の中に収める | I3 |
| 間隔あり、字面の終わり + `i` がちょうど段の終わり | 段の終わりに引き、段を閉じる | I1, I2, I4 |
| 間隔あり、字面の終わり + `i` が段の終わりより 1 sp 前 | 段の中に収める | I3 |
| `i + w` が余白を超える | G07001（今のとおり） | なし |
| その段に脚注がある | 段の中に収める | I3 |
| `keep-in-column = true` | 段の中に収める | I3 |
| 共有できずに段の終わりで引く罫線で、位置が段の終わり以降 | 段の外に引き、段を閉じる | I1, I2, I4 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0450 I1 から I4 を名前の先頭に置いたテストを、golem-layout の `PhysicalPaginateSpec` に足す。
段落と見出しの後の罫線と、共有できずに段の終わりで引く罫線について、間隔の有無、`i`、`w`、段の容量、最後の行の位置、脚注の有無、`keep-in-column` を列挙する。
I1 と I4 のテストが今の main で落ちることを確かめてから実装する。
golem-driver の `ParagraphRuleSpec` には、自由な配置で段の終わりの後の罫線を段の外に引く原稿を一つ足し、罫線が版面の下の余白にあることを確かめる。

## トレードオフ

罫線の全体が段の終わり以降にあるときだけ外に出すので、外に出るのは、最後の行が段の終わりに十分近いときだけである。
その代わりに、罫線が段の中と外にまたがらず、段の中の内容と重ならない。

段の終わりより前から始まる罫線も外に出し、段を閉じる案もある。
格子への配置に近いが、段の中の隙間に罫線を引くことになり、[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) の「版面の外に線の全体が収まる」から離れるので採らない。

## 参考文献

- [golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)
- [golem-driver ADR 0040](../golem-driver/adr/0040-rules-outside-column-only-at-type-area-edge.md)
- [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md)
