# ADR 0045: PDF の縦中横を横に並べて一字の箱に収めて描く

ステータス: 採択→I8 の `pdf-sample.txt`、述語 8 のテストは [ADR 0257](../../adr/0257-record-what-the-audit-of-the-layout-adrs-of-2026-11-09-found.md)

## 文脈

docs/roadmap.md の v0.1.0-rc4 の PDF の節に、「縦組みの脚注の本文の前の二桁の番号」の項目がある。
縦組みの注の本文の先頭の印（既定の `*{n}`）で、番号が 10 以上になると、二つめの数字が注の本文の一字めに重なる。
見た目の回帰テストの見本 `specimens-vertical` の 4 ページ（「縦組みの注の印」の節）で見つかり、参照はこの重なりのまま受け入れた（[docs/adr/0233](../../adr/0233-add-the-specimens-of-the-visual-checks-to-the-visual-regression-test.md)）。

この ADR を書くために調べると、原因は注の印に限らなかった。
PDF は、縦中横の箱の字を横に並べずに、縦組みの字として行の方向に一字ずつ積んで描いている。
注の本文の先頭の二桁の番号は、その一つの現れである。

### 再現

`origin/main`（`143b57e5`）の golem をビルドし、`modules/golem-driver/test/fixtures/specimens/vertical` を `scripts/visual/build.sh` と同じフォント（Noto Serif JP と Source Sans Pro）で組み、shem で 4 ページを画像にした（2026-11-08）。

- 注の本文の先頭の `*10`、`*11`、`*12` で、`1` の下にもう一字分の送りで二つめの数字が正立して描かれ、注の本文の一字め（`十`）に重なる。
- 本文の印の `10`、`11`、`12` も、同じく二字が縦に積まれ、印の後の読点や句点に重なる。
- `*1` から `*9` の一桁の番号は重ならない。

同じフォントの縦組みの小さなプロジェクトを作り、次の原稿を組んで画像にした。

```
縦中横は[tcy: 12]月と[tcy: !?]と[number-text 12 style=tcy]日と[number-text 7 style=tcy]日。
```

`[numbers]` の `vertical` は `auto` とし、12 項目の番号付きリストも置いた。
`[tcy: 12]`、`[tcy: !?]`、`[number-text 12 style=tcy]` はどれも二字が縦に積まれ、二字めが次の字に重なった。
番号付きリストの 10 番目からの印（`10、` など）も同じだった。
`[tcy: 123]` と `[tcy: 1234]` は三字と四字が縦に積まれ、後ろの二字から三字が次の字の位置まで伸びた。
`[number-text 7 style=tcy]` の一字は重ならなかった。

### 原因

組版（golem-layout）は、縦中横を一字分の箱として正しく組んでいる。
`piecesOf` は、`[tcy: ...]` を長さが文字の大きさ一つ分の `KindTcy` の箱にする（[`Japanese.hs` L521](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-layout/src/Golem/Layout/Japanese.hs#L521)）。
表記が `tcy` の数も同じ箱になる（[`numberPieces`](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-layout/src/Golem/Layout/Japanese.hs#L688-L694)）。
注の印の番号は、縦組みで 2 字までの算用数字なら縦中横の部品になる（[`markParts`](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-layout/src/Golem/Layout/Japanese.hs#L583-L592)）。
注の本文の先頭の印は、`withNoteMark` がこの部品を `Tcy` のインラインにして注の本文の前に置く（[`Flow.hs` L1165-L1170](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1165-L1170)）。
本文の印の中の縦中横の部品は、印の大きさ `m` 一つ分の長さを持つ（[`markItem`](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-layout/src/Golem/Layout/Japanese.hs#L929-L953)）。
これは [golem-layout ADR 0002](../../golem-layout/adr/0002-japanese-composition.md) の「縦中横の文字列は、横組みで組んだ結果を全角一字分の箱とする」のとおりである。

描画（golem-typeset の `drawLineAt`）には、`KindTcy` の分岐がない。
`KindTcy` の箱は、ふつうの文字の箱と同じ既定の分岐で、縦組みの正立の字として `runAtU` に渡る（[`Draw.hs` L885-L896](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L885-L896)）。
`runAt` は、縦組みの字を、前の字の送りの分だけ行の方向（ページの下）にずらして並べる（[`Draw.hs` L506](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L506)、[L548](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L548)）。
箱の長さは一字分なので、二字めからは箱の外、つまり次の箱の上に描かれる。
一字なら字が箱の中に収まるので、重なりは表に出ない。

本文の印の分岐も同じである。
`KindNoteMark` の分岐は、回転する部品（`KindRotated`）のほかを、縦組みの正立の字として描く（[`Draw.hs` L859-L881](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L859-L881)）。
縦中横の部品もこの道を通るので、二字が縦に積まれる。

既定の分岐は、縦中横の箱ができた最初の実装から変わっていない。
[docs/adr/0128](../../adr/0128-auto-tcy-filter.md) を書いた `668ed3ac` の `Draw.hs` でも、`KindTcy` は同じ既定の分岐で描かれていた（コードを読んで確かめた。そのコミットをビルドして組んではいない）。
同じ原因の箇所を、次の表にまとめる。

| 箇所 | 縦中横になる条件 | 確かめ方 |
|---|---|---|
| 原稿の `[tcy: ...]`（`auto-tcy` のフィルタの出力を含む） | 書いたとき | 組んで画像で見た |
| 表記が `tcy` の数（`[number-text ... style=tcy]`、`##N##`） | `style=tcy`、または `[numbers]` の `vertical` が `tcy`、`auto`、`auto-digits` で 0 から 99 | 組んで画像で見た |
| 番号付きリストの印の `{n}` | 上の数の規則に従うとき（[golem-driver ADR 0013](0013-list-indents.md)） | 組んで画像で見た |
| 本文の注の印 | 表記が `arabic` で 2 字まで（[docs/adr/0177](../../adr/0177-note-mark-style-and-numerals.md)） | 組んで画像で見た |
| 脚注の本文の先頭の印 | 同上 | 組んで画像で見た |
| 章末の注の本文の先頭の印 | 同上（[`Flow.hs` L1473](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1473) も `withNoteMark` を使う） | コードを読んだ |
| 目次、索引、相互参照のページ番号 | 表記が `tcy` の数になるとき（[golem-driver ADR 0009](0009-pdf-toc-page-numbers.md)） | コードを読んだ |

次の箇所は、この原因に当たらない。

- 3 字以上の算用数字の注の番号は縦中横にせず、欧文として横に倒す（[docs/adr/0177](../../adr/0177-note-mark-style-and-numerals.md) のメンテナーの決定の 14）。`*123` は回転した欧文の箱になり、重ならない。
- 傍注は横組みに限る（[golem-layout ADR 0006](../../golem-layout/adr/0006-sidenotes.md)）。横組みの印には縦中横の部品がない。
- HTML と EPUB は、縦中横を CSS の `text-combine-upright: all` で組む（[`Html.hs` L980](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-html/src/Golem/Html.hs#L980)）。字を横に並べて一字分に収めるのはリーダーである。
- 横組みの PDF では、縦中横の箱の字はもともと横に並ぶ。

### 仕様と資料

原稿の記法の説明は、縦中横を「縦書きの中で、短い文字列を横向きのまま一字分の幅に組む」と書いている（[docs/markup.md](../../markup.md) の「縦中横」の節）。
今の PDF はこれに合わない。

JLReq の 3.2.5（縦中横の処理）は、縦中横の文字列を左から右へベタ組で並べ、文字列の全体を行の中央に置くとする。
JLReq の 3.2.3 は、2 桁のアラビア数字と、行の幅とほぼ同じかやや行の幅よりはみ出す程度の 2 字程度の欧字を、縦中横にするのが一般的だとし、アラビア数字には半角の字を使うとする。
JLReq の 4.2.2 は、縦組みの注の番号のアラビア数字を一般に縦中横にするとする（[docs/adr/0177](../../adr/0177-note-mark-style-and-numerals.md) が引いた）。
行の幅を大きく超える文字列の扱いを、JLReq は書いていない。

縦組みの中に横書きの字を置く描き方は、Golem にすでにある。
[docs/adr/0177](../../adr/0177-note-mark-style-and-numerals.md) より前の縦組みの注の印は、印の文字列を横組みのフォントで横に並べ、印の基準線を箱の始まりから `m/2 + c × m` 下に置いていた（[golem-driver ADR 0018](0018-footnote-marks-and-numbers.md)、`c` は和文の書体の字面の枠の中心の高さ `lfEmBoxCentral`）。
`runAt` は、横組みの字に水平の比率（千分率）をかける引数を持つ（行の伸縮のための `ScaledGlyphRun`、合成の斜体と太字では `StyledGlyphRun`）。

## 実装すること

### 縦中横の箱の描き方（golem-typeset）

`drawLineAt` に `KindTcy` の分岐を加える。
縦組みでは、箱の文字列を横組みの字として描く。
横組みの描き方は今のままとする。

- 字の向き：横組みのフォントの参照（Identity-H）で、回転せずに描く。字の並びは今の `shapingOf` の選び方のまま（欧文の字は欧文の書体、ほかは和文の書体）とし、横組みでシェイピングする（「メンテナーが決めること」の 3）。
- 文字列の幅：横組みでシェイピングした送りの和を `W` とし、箱の大きさ（その位置の文字の大きさ）を `s` とする。トラッキングは足さない（仕様書の「style.toml」の節のとおり）。
- 水平の比率：`W ≤ s` なら比率をかけない。`W > s` なら、比率を `⌊1000 × s / W⌋` の千分率とし、描いた幅 `W'` を `s` 以下にする（「メンテナーが決めること」の 1）。
- 行に直交する方向の位置：描いた文字列の中心を行の中心線に置く。文字列の左端は、行の中心線から `W'/2` 左である。
- 行の方向の位置：和文の書体の字面の枠の中心を、箱の中心に置く。箱の始まり（ページの座標で上端）を `y0` とすると、基準線は `y0 − s/2 − c × s` である（「メンテナーが決めること」の 2）。
- ベースラインシフト：縦組みのほかの字と同じく、行の右へずらす（[docs/adr/0020](../../adr/0020-indesign-character-features.md)）。
- 合成の斜体と太字：横組みの字と同じく、字形の座標系で傾け、輪郭を太らせる（[golem-driver ADR 0004](0004-pdf-emphasis-and-character-styles.md)）。
- 一字の縦中横（`[number-text 7 style=tcy]`）も、同じ規則で描く（「メンテナーが決めること」の 5）。

### 注の印の中の縦中横（golem-typeset）

`KindNoteMark` の分岐で、縦中横の部品（`KindTcy`）を上と同じ規則で描く。
箱の大きさ `s` の代わりに印の大きさ `m` を使い、行の中心線の代わりに印の列の中心（今の `column`、行の中心線から `(s − m)/2` 右）を使う（「メンテナーが決めること」の 4）。
印の列の右端を本文の字面の枠の右端にそろえる規則（[docs/adr/0177](../../adr/0177-note-mark-style-and-numerals.md)）は変えない。

注の本文の先頭の印の番号は、注の本文の行の中のふつうの `KindTcy` の箱なので、上の節の分岐で描かれる。

### 組版は変えない

golem-layout の箱の作り方（`KindTcy` の箱の長さ、注の印の部品の長さ）、行分割、改ページは変えない。
変わるのは字形を描く位置と向きだけである。

### ドキュメント

- docs/specifications.md の「フォント」の節の縦組みの字の向きの段落に、PDF の縦中横は横組みの字を左から右へベタで並べ、字面の枠の中心を箱の中心に、文字列の中心を行の中心線に置き、一字分を超える文字列は水平に縮めて一字分に収めることを、この ADR へのリンクで書く。
- docs/specifications.md の「脚注」の節の縦組みの印の段落に、縦中横の部品を印の列の中心に置くことを書き足す。
- docs/roadmap.md の v0.1.0-rc4 の PDF の節から「縦組みの脚注の本文の前の二桁の番号」の項目を消す。
- [golem-layout ADR 0002](../../golem-layout/adr/0002-japanese-composition.md) のステータスの行に、PDF の縦中横の描き方をこの ADR で決めたことを、この ADR へのリンクで書き足す。

## 実装しないこと

- 縦中横の箱の長さを文字列の幅に合わせて伸ばすこと。箱は一字分のまま（[golem-layout ADR 0002](../../golem-layout/adr/0002-japanese-composition.md)）とする。
- OpenType の `hwid`、`twid`、`qwid` の機能で、半角、三分、四分の字形に替えること（「メンテナーが決めること」の 3）。
- 縦中横の前後の空き（JLReq の 3.2.5 の、読点類や括弧類との二分アキ）を変えること。空きは組版の規則であり、この ADR は描画だけを扱う。
- 3 字以上の算用数字の注の番号を縦中横にすること。[docs/adr/0177](../../adr/0177-note-mark-style-and-numerals.md) の決定のとおり、欧文として横に倒す。
- HTML と EPUB の縦中横の組み方を変えること。
- 縦組みの傍注。

## 不変条件

テストの名前には、ここの番号を入れる（[docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)）。
記号は次のとおりとする。

- `s`：縦中横の箱の大きさ（注の印の中では印の大きさ `m`）。
- `y0`：箱の始まりの行の方向の座標（ページの座標の上端）。
- `x_c`：行の中心線の座標（注の印の中では印の列の中心）。
- `c`：箱の和文の書体の `lfEmBoxCentral`。
- `W`：文字列を横組みでシェイピングした送りの和。`W'`：水平の比率をかけた後の送りの和。

述語は、縦組みの PDF の縦中横の箱ごとに成り立つ。
座標の比較は 1 sp の丸めの差を許す。

1. **向き**：箱の字形はすべて横組みのフォントの参照で描かれ、回転していない（`RotatedGlyphRun` でない）。
2. **並び**：箱の字形の基準線の y はすべて等しく、字形の原点の x は文字列の順に狭義に増える（字形が一つならこの述語は自明に成り立つ）。
3. **行の方向の位置**：基準線の y は `y0 − s/2 − c × s` に等しい。
4. **比率**：`W ≤ s` なら水平の比率は 1000（比率をかけない）である。`W > s` なら比率は `⌊1000 × s / W⌋` であり、`W' ≤ s` が成り立つ。
5. **行に直交する方向の位置**：最初の字形の原点の x は `x_c − W'/2` に等しい。
6. **箱に収まる**：字形の送りと和文の字面の枠が作る矩形、つまり x が `[x_c − W'/2, x_c + W'/2]`、y が `[y0 − s, y0]` の矩形は、箱の矩形（x が `[x_c − s/2, x_c + s/2]`、y が `[y0 − s, y0]`）に含まれる。したがって、行の次の箱の字形の範囲と重ならない。
7. **組版が変わらない**：同じ入力で、golem-layout の行の箱の並び（`Item` の列）と、各ページの行の位置は、この ADR の前後で等しい。
8. **ほかの PDF が変わらない**：横組みの本と、縦中横の箱を含まない縦組みの本は、PDF のページの内容のストリームがこの ADR の前後で等しい。

境界の入力を次の表に挙げる。
幅は、`scripts/visual/build.sh` と同じ Source Sans Pro の数字を半角と仮定した目安であり、テストでは測った `W` を使う。

| 入力 | 文字列 | `W` と `s` | 期待 |
|---|---|---|---|
| 空の `[tcy: ]` | 空 | `W = 0` | 字形がない。述語 1 から 6 は自明に成り立つ |
| 一字 `[number-text 7 style=tcy]` | `7` | `W < s` | 比率をかけず、`7` の中心が行の中心線に来る。一字でも描く位置は今と変わる |
| 二桁 `[tcy: 12]`、注の番号 10 | `12`、`10` | `W ≤ s` | 比率をかけず、二字が横に並ぶ |
| 記号 `[tcy: !?]` | `!?` | `W ≤ s` | 比率をかけず、二字が横に並ぶ |
| ちょうど収まる | 送りの和が `s` に等しい文字列 | `W = s` | 比率をかけない |
| 1 sp あふれる | 送りの和が `s + 1 sp` の文字列 | `W > s` | 比率は 999 以下になり、`W' ≤ s` |
| 三桁 `[tcy: 123]` | `123` | `W > s` | 比率をかけて一字分に収める |
| 四桁 `[tcy: 1234]` | `1234` | `W ≫ s` | 比率をかけて一字分に収める |
| 注の番号 9 | `9` | `W < s` | 一字の縦中横として描く |
| 注の番号 99 | `99` | `W ≤ s` | 二字が横に並ぶ |
| 注の番号 100 | `100` | 縦中横でない | 欧文として横に倒した箱のまま。この ADR で変わらない |
| 横組みの `[tcy: 12]` | `12` | 横組み | 今と同じ PDF（述語 8） |

## テスト設計

実装の前に書き、今の実装で失敗することを確かめる。

### 描画の述語（`modules/golem-driver/test`）

縦組みの小さなプロジェクトを、`scripts/visual/build.sh` と同じフォントで組み、ページの内容のストリームから `drawnGlyphs`（`Support.hs`）で字形のフォント、行列、位置を読む。
述語 1 から 6 を、違反を返す関数として書き、次の入力で成り立つことを確かめる。

- I1 から I6：`[tcy: 12]`、`[tcy: !?]`、`[number-text 12 style=tcy]`、`[number-text 7 style=tcy]`、`[tcy: 123]`、`[tcy: 1234]` を一つの段落に置いた本。今の実装では、`12` の二字の y が異なり、縦組みのフォントの参照で描かれるので、I1、I2、I6 が失敗する。
- I1 から I6：12 個の注を持つ縦組みの本（`specimens-vertical` の「縦組みの注の印」と同じ原稿）の、注の本文の先頭の番号 10 から 12 と、本文の印の番号 10 から 12。今の実装では I2 と I6 が失敗する。
- I1 から I6：`[numbers]` の `vertical = "auto"` の本の、12 項目の番号付きリストの 10 番目から 12 番目の印。
- I4：`W = s` と `W = s + 1 sp` の境界は、フォントの字の幅に依存して原稿で作りにくい。描画の関数に固定の送りを返す測り方を渡す単位のテスト（golem-typeset）で、`W = s − 1 sp`、`W = s`、`W = s + 1 sp`、`W = 2s` の比率を確かめる。

各述語は、違反する入力で失敗することも確かめる（[docs/adr/0233](../../adr/0233-add-the-specimens-of-the-visual-checks-to-the-visual-regression-test.md) のテスト設計と同じく、失敗しえない述語は何も確かめない）。
今の実装の出力が、その失敗する入力になる。

### 組版と他の出力が変わらないこと

- I7：上の縦組みの本で、`layoutPdf` の行の箱の並びと行の位置を、この ADR の前のコミットの値と比べる。golem-layout のテスト（`KindTcy` の箱が一字分であること）はそのまま通る。
- I8：横組みの PDF のテスト、出力のゴールデン（`pdf-sample.txt`、`pdf-complex-horizontal.txt`、`pdf-figures.txt`）、決定性の検査の横組みの PDF のハッシュが、変わらずに通る。

### 変わることを受け入れる出力

次の出力は、縦中横を含むので変わる。
変わった箇所が縦中横の箱だけであることを、差分の画像で確かめてから更新する。

- 見た目の回帰テストの参照の `specimens-vertical` と `specimens-vertical-marks-japanese` の 4 ページ（注の本文の先頭の番号 10 から 12 と、本文の印の番号 10 から 12）。
- 同じく `complex-vertical`（`[tcy: !?]` と `[number-text 3 style=tcy]`）、`kanikosen` と `kanikosen-marks-japanese`（`第[tcy: 36]号`）の該当するページ。
- 出力のゴールデンの `pdf-complex-vertical.txt` と、`scripts/determinism/hashes.txt` の `complex-vertical` の PDF のハッシュ。

### 自動テストにしない確かめ方

- `specimens-vertical` の 4 ページを shem で画像にし、注の本文の先頭の `10`、`11`、`12` が横に並んで一字分に収まり、注の本文の一字めに重ならないことを目で確かめる。
- `[tcy: 123]` を含む縦組みの本を画像にし、縮めた三桁が読める大きさかを目で確かめる（「トレードオフ」）。

## トレードオフ

一字分を超える縦中横を水平に縮めるので、`[tcy: 1234]` のような長い文字列は細くなり、読みにくくなる。
縮めずに行の外へはみ出させれば字の形は保てるが、隣の行やルビと重なりうる。
JLReq の 3.2.3 は「やや行の幅よりはみ出す程度」を許すが、どこまでを「やや」とするかを Golem の規則にできない。
HTML と EPUB の `text-combine-upright` も一字分に収めるので、媒体のあいだで組みがそろう。
長い文字列を縦中横にしたくない書き手は、原稿で縦中横にしなければよい。

一字の縦中横の描く位置も変わる。
今は欧文の書体の字を縦組みの字として描いており、字の位置は欧文の書体の縦の送りの扱いで決まっていた。
変更の後は、二字の縦中横と同じ規則で、字面の枠の中心を箱の中心に置く。
一字と二字の縦中横で、規則を一つにすることを優先した。

字面の枠の中心は和文の書体の値を使うので、欧文の書体の数字の字面は、その中心に対して上下に偏ることがある。
字の外接矩形（インク）の中心を箱の中心に置けば偏りは消えるが、`12` と `!?` で中心の高さが字ごとに変わり、同じ行の縦中横がそろわなくなる。

縦中横を含む縦組みの本の PDF は、すべて変わる。
見た目の回帰テストの参照と決定性の検査のハッシュの更新が要る。
今の描き方は、記法の説明（[docs/markup.md](../../markup.md)）とも JLReq とも合わない誤りなので、受け入れる。

## メンテナーが決めること

1. **一字分を超える文字列**：推奨は、水平に縮めて一字分に収めること（`W > s` のとき比率 `⌊1000 × s / W⌋`）。
   - 縮めずに行の中心線にそろえ、行の外へはみ出させる案は採らない。隣の行やルビと重なり、はみ出しの上限を決められない。
   - 縦中横の箱の長さを文字列の幅まで伸ばす案は採らない。[golem-layout ADR 0002](../../golem-layout/adr/0002-japanese-composition.md) の一字分の箱を変え、行分割が変わる。
   - 3 字以上の縦中横を欧文として横に倒す案は採らない。書き手が `[tcy: ...]` と書いた指定を、黙って変えることになる。
2. **行の方向の位置**：推奨は、和文の書体の字面の枠の中心を箱の中心に置くこと。[golem-driver ADR 0018](0018-footnote-marks-and-numbers.md) の横書きの向きの縦組みの印、[golem-driver ADR 0015](0015-vertical-dashes.md) の回転したダッシュと同じ基準である。
   - 字の外接矩形の中心を箱の中心に置く案は採らない。字ごとに高さが変わり、同じ行の縦中横がそろわない。
   - 欧文の書体の ascender と descender の中央を使う案は採らない。和文の字と並べたときの位置が、欧文の書体の値で変わる。
3. **字形と書体**：推奨は、今の `shapingOf` の選び方（欧文の字は欧文の書体）のまま横組みでシェイピングし、OpenType の機能を足さないこと。JLReq の 3.2.3 の「アラビア数字は半角の字」には、欧文の書体の数字がおおむね当たる。
   - 和文の書体の `hwid`（二桁）、`twid`（三桁）、`qwid`（四桁）を当てる案は採らない。機能を持たない和文の書体があり、字数で書体が替わると、同じ本の中で数字の形がそろわない。必要になったら、文字スタイルの `features` で書き手が当てる道を別の ADR で検討する。
4. **注の印の中の縦中横の中心**：推奨は、印の列の中心（行の中心線から `(s − m)/2` 右）に置くこと。[docs/adr/0177](../../adr/0177-note-mark-style-and-numerals.md) の、印の字の列を本文の字面の枠の右端にそろえる規則を保つ。
   - 行の中心線に置く案は採らない。印の中の `*` や括弧の列と、番号の列がずれる。
5. **一字の縦中横**：推奨は、二字以上と同じ規則で横組みの字として描くこと。
   - 一字だけ今の描き方（縦組みの字として描く）を残す案は採らない。一つの箱の種類に二つの描き方ができ、描く位置の規則を二つ持つことになる。
6. **扱う範囲**：推奨は、注の印に限らず、すべての縦中横の箱をこの ADR で直すこと。原因は一つの分岐の欠落であり、注の印だけを直すと、同じ分岐の欠落が `[tcy: ...]`、数、リストの印に残る。
   - 注の印の縦中横の部品だけを直す案は採らない。roadmap の項目は消えるが、同じ重なりが本文に残る。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- W3C, Requirements for Japanese Text Layout（JLReq）, W3C Group Note, https://www.w3.org/TR/jlreq/ 。3.2.3（縦組の和欧文混植に用いる文字）、3.2.5（縦中横の処理）を 2026-11-08 に読んだ。4.2.2（注の番号）は [docs/adr/0177](../../adr/0177-note-mark-style-and-numerals.md) の引用による。
- W3C, CSS Writing Modes Level 3, `text-combine-upright`, https://www.w3.org/TR/css-writing-modes-3/#text-combine-upright 。一字分に収める組み方の比較に使った。本文の規定は、この ADR のためには読み直していない。
