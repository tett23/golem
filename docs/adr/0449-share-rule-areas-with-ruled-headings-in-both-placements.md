# ADR 0449: 罫線つき見出しも、隣り合う罫線の領域を共有する

Status: accepted

## 文脈

[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md) の「隣り合う罫線」は、後の罫線を持つ段落の直後に、前の罫線を持つ段落が同じ段で続くとき、二つの罫線を一つの領域に置くと決めた。
自由な配置の共有の長さは、[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) の「段落の罫線」が、同じく段落どうしについて決めた。
0027 は、罫線つき見出しが前か後にある場合を書いていない。
0397 は、見出しに付く罫線の領域の長さもこの節で求めると書くが、共有の規則の文は段落どうしで書いており、見出しとの共有を求めるのかが読み分けられない。
仕様書の「段落の罫線」と「罫線を持つ段落」の節も、段落どうしの場合だけを書いている。

二つの配置は、この点で食い違っている。
格子への配置は、罫線つき見出しも含めて、隣り合う罫線の領域を共有する。
自由な配置は、段落どうしの場合だけ共有し、見出しが前か後にあると、二つの罫線をそれぞれのまとまりの領域に別々に引く。
その結果、自由な配置では、段落の後の罫線と見出しの前の罫線が重なって引かれることがある。
[root ADR 0352](0352-prove-pagination-in-lean.md) の Lean のモデルが、この重なりを示した。

メンテナーは、見出しもこの規則に入れると決めた。
この ADR は、その範囲と、見出しが加わったときの測り方と、二つの配置での振る舞いを決める。

## 調査した事項

origin/main（[2630685](https://github.com/tett23/golem/commit/26306852107440a42f84c26fdc75fa6135d846a8)）で、次のことを確かめた。

- golem-typeset の `ruledLinks` は、後の罫線を持つ罫線つきのまとまりの直後に、前の罫線を持つ罫線つきのまとまりが来ると、後のまとまりに `frJoined` を立てる（[Flow.hs#L4712-L4724](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L4712-L4724)）。
  段落と見出しを区別しない。
- 格子への配置の `joinsNext` は、次のまとまりが `frJoined` の `FRuled` なら共有するとし、本体が段落か見出しかを見ない（[Decide.hs#L365-L369](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L365-L369)）。
  共有するときは、前のまとまりが収まるかの判定に、後の罫線の領域を数えない（[Decide.hs#L395](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L395) の `k2`）。
- 自由な配置の `joinsNext` は、次のまとまりの本体が段落（`RuledLines`）のときだけ共有する（[Physical.hs#L1332-L1335](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1332-L1335)）。
  この制限は PR #1148 で入った。
  それより前は、見出しが続くと段落の後の罫線が消えていた。
- 自由な配置で、待たせた罫線（`psJoin`）を読むのも、後のまとまりが入らないときに待たせた罫線を段の終わりに引いて次の段へ送るのも、段落の枝だけである（[Physical.hs#L1397](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1397) と [#L1453-L1454](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1453-L1454)）。
  見出しの枝（[Physical.hs#L1462-L1564](https://github.com/tett23/golem/blob/26306852107440a42f84c26fdc75fa6135d846a8/modules/golem-layout/src/Golem/Layout/Paginate/Physical.hs#L1462-L1564)）は、前の罫線を待たせた罫線と共有せず、後の罫線も次のまとまりと共有せずに見出しの領域に引く。
- [root ADR 0352](0352-prove-pagination-in-lean.md) の実装の PR #964 のモデルは、行送り 20 sp の段で、段落の後の罫線を 18〜22 sp、見出しの前の罫線を 21〜25 sp に引く入力で、二つが重なることを `ruledHeading_rules_overlap` の定理で示す。
  このモデルはまだ main にない。

## 実装すること

### 規則

[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md) の「隣り合う罫線」と、[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) の「段落の罫線」の共有の規則は、段落と見出しの両方に当てはまるものと読む。
後の罫線を持つ罫線つきのまとまり（段落か見出し）の直後に、前の罫線を持つ罫線つきのまとまり（段落か見出し）が同じ段でアキなしに続くとき、二つの罫線を一つの領域に置く。
組み合わせは、段落と段落、段落と見出し、見出しと段落、見出しと見出しの四つである。

領域の求め方と罫線の位置は、今の共有の規則と同じにする。
格子への配置では `k = max(0, ceil((iA + wA + max(oA, oB) + wB + iB + rB - (p - h)) / p))` で、自由な配置では必要量 `iA + wA + max(oA, oB) + wB + iB + rB` から g を引いた非負の長さを足す。
見出しが加わるときの各量は、次のとおりに測る。

- `rB` は、後のまとまりの最初の行の張り出しである。後のまとまりが見出しなら、見出しの最初の行の張り出しである。
- 自由な配置の g は、前のまとまりの最後の行の字面の終わりから、後のまとまりの最初の行の字面の始まりまでの距離である。見出しの字面は、見出しの実寸の字面とする。
- 格子への配置の `p` と `h` は、今と同じく格子の行送りと格子の字面の高さである。

### 共有する条件

共有するかどうかの条件は、今の規則と同じにする。

- あいだに `space-between` の空きの行や段落間のアキがあれば、共有しない。
- 後のまとまりが同じ段に入るときだけ共有する。入らなければ、前のまとまりの後の罫線はそのまとまりだけの罫線として段の終わりに引き、後のまとまりは次の段から置く。
- 空の段にも入らないとして罫線を省いて組むまとまり（[golem-driver ADR 0035](../golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)、G07046）は、前のまとまりとも後のまとまりとも共有しない。後の罫線だけを省き、前の罫線を残した見出しも、前の罫線を前のまとまりと共有せず、見出しだけの罫線として数える。罫線を省くかの判定が、前のまとまりの罫線によって変わらないようにするためである。

### まとまりが収まるかの判定

前のまとまりが後の罫線を共有するときは、前のまとまりが段に収まるかの判定に、後の罫線の領域を数えない。
共有した領域は、後のまとまりが収まるかの判定に数える。
後のまとまりが見出しのときは、見出しの行、注の本文、区切りの行に、共有した領域を足して判定する。
見出しの直後で改ページしない規則は、今のとおり、続く罫線のまとまりの全体を数え、共有した領域はその続くまとまりに含める。
見出しの内部の配置と、見出しを分けないことは変えない（[root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) の「段落の罫線」の最後の文のとおり）。

### 二つの配置

格子への配置は、共有するかの判定で見出しを区別していない（調査した事項）。
実装では、不変条件のテストで格子への配置も確かめ、この ADR から外れるところがあれば直す。

自由な配置では、次のように直す。

- `joinsNext` から、段落だけに限る条件を外す。
- 見出しの後の罫線も、段落の後の罫線と同じく、次のまとまりと共有するなら待たせる。
- 見出しの前の罫線も、待たせた罫線があれば、それと共有の領域に引く。
- 見出しが同じ段に入らなければ、待たせた罫線を段の終わりに引いてから、見出しを次の段に送る。

### 文書とステータスの行

仕様書の「段落の罫線」と「罫線を持つ段落」の節の、共有の規則の「段落」を、罫線つきのまとまり（段落と見出し）に直す。
あわせて、見出しが加わるときの測り方と収まるかの判定を書き、この ADR へリンクする。

採択したら、次の二つを記録する。

- [golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md) のステータスの配列に、次の要素を足す。

  ```text
  {"part":"隣り合う罫線","by":["docs/adr/0449-share-rule-areas-with-ruled-headings-in-both-placements.md"],"kind":"supplement"}
  ```

- [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) のステータスを `superseded [...]` にし、次の要素を入れる。[root ADR 0450](0450-put-free-placement-rules-after-outside-the-column-end.md) も同じ節に記録するので、両方を採択するときは二つの要素を同じ配列に入れる。

  ```text
  {"part":"段落の罫線","by":["docs/adr/0449-share-rule-areas-with-ruled-headings-in-both-placements.md"],"kind":"supplement"}
  ```

## 実装しないこと

罫線の表し方は変えない。
メンテナーは、罫線は後で IR の上で幅を持つパスとして表すことになると述べた（2026-11-25 の会話）。
パスの型は [root ADR 0437](0437-paths-and-the-box-model.md) が決めている。
この ADR は罫線の位置と領域の決め方だけを決め、その規則は罫線をどう表すかによらない。

罫線を持たないまとまり（表、コード、図版など）は、この規則に入れない。
区切りの罫線（[root ADR 0398](0398-styled-separators-in-manuscripts.md)）も入れない。

## 不変条件

- I1: 格子への配置でも自由な配置でも、G07046 で罫線を省いて組むまとまりを除き、後の罫線を持つ罫線つきのまとまりの直後に前の罫線を持つ罫線つきのまとまりがアキなしで同じ段に続くなら、二つの罫線は一つの領域に置かれ、位置は共有の式が与える値と一致する。
- I2: 格子への配置でも自由な配置でも、隣り合う二つの罫線つきのまとまりの罫線は、行送りの方向で重ならない。
- I3: 後のまとまりが両方の配置で前のまとまりと同じ段に入るフローについて、格子への配置と自由な配置は、隣り合う罫線を共有するかどうかで一致する。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 段落の後の罫線と段落の前の罫線 | 共有する（今と同じ） | I1, I2, I3 |
| 段落の後の罫線と見出しの前の罫線 | 共有する | I1, I2, I3 |
| 見出しの後の罫線と段落の前の罫線 | 共有する | I1, I2, I3 |
| 見出しの後の罫線と見出しの前の罫線 | 共有する | I1, I2, I3 |
| あいだに `space-between` の空きの行 | 共有しない | I2, I3 |
| 後の見出しが共有した領域を含めてちょうど同じ段に収まる | 共有する | I1, I2 |
| 後の見出しがあふれる（格子では 1 格子行、自由な配置では 1 sp） | 共有せず、見出しは次の段 | I2 |
| 後の見出しが空の段にも入らず G07046 | 共有しない | I2 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0449 I1 から I3 を名前の先頭に置いたテストを足す。
golem-layout の `PhysicalPaginateSpec` と `PaginateSpec` で、四つの組み合わせ、間隔の有無、内側と外側の間隔、太さ、`keep-in-column`、段の容量、後のまとまりが収まるかどうかを列挙する。
I1 は共有の式の位置と、I2 は罫線の区間が重ならないことと、I3 は二つの配置の共有の判定が一致することと比べる。
自由な配置の I1 と I2 のテストが、今の main で落ちることを確かめてから実装する。
golem-driver の `ParagraphRuleSpec` には、段落の後に罫線つき見出しが続く原稿を、自由な配置で組むテストを一つ足す。
PR #964 のモデルの `ruledHeading_rules_overlap` は、実装の後には成り立たなくなる。
この ADR の実装を main に入れた後、PR #964 に main をマージするときに、重ならないことの定理に置き換える。

## トレードオフ

見出しの前の罫線と段落の後の罫線が一つの領域にまとまるので、見出しの前の空きは、別々に引く場合より狭くなる。
その代わりに、二つの配置が同じ規則で組み、罫線が重ならない。

見出しを共有から外し、二つの罫線を別々の領域に引く案もある。
しかし、格子への配置を変えることになり、別々に引くと見出しの前に二本の罫線が並ぶので採らない。

## 参考文献

- [golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)
- [golem-driver ADR 0035](../golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)
- [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md)
- [root ADR 0352](0352-prove-pagination-in-lean.md)
- [root ADR 0437](0437-paths-and-the-box-model.md)
