# ADR 0279: 囲みを持つ段落では句読点をぶら下げない

ステータス: 採択

## 文脈

### 囲みの中のぶら下げ

[ADR 0271](0271-paragraph-backgrounds-and-borders.md) は、段落スタイルに背景と囲み罫（囲み）を書けるようにした。
囲みを持つ段落の行は、囲みの範囲の両端から `padding` だけ内側を行の領域として組む（[`flowUnits` の `withBox`](https://github.com/tett23/golem/blob/7e8fe7d3d59d893342c0e55a1cb6d1a39245a482/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2161-L2178)）。
この ADR は、`[composition]` の `hanging-punctuation = true` のときに囲みの中の句読点をどう組むかを決めていなかった。

今の実装は、囲みの中の段落も囲みの外の段落と同じ組み方の環境で組む（[`composeUnit`](https://github.com/tett23/golem/blob/7e8fe7d3d59d893342c0e55a1cb6d1a39245a482/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2250-L2259)）。
ぶら下げ組では、句点類と読点類の箱が、字の幅から後ろのアキを引いた幅（全角の字では半角）だけ行末の外に出ることを許される（[`Japanese.hs` の 1229 行](https://github.com/tett23/golem/blob/7e8fe7d3d59d893342c0e55a1cb6d1a39245a482/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1229)、[`protrusionOf`](https://github.com/tett23/golem/blob/7e8fe7d3d59d893342c0e55a1cb6d1a39245a482/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L442-L452)）。
行の領域の終わりは囲みの終わりの辺から `padding` だけ内側にあるので、ぶら下げた句読点は `padding` の中に入る。
`padding` の既定は 0.5zw であり、ぶら下げる幅と等しい。
既定の囲みでは、ぶら下げた句読点の箱が、囲みの終わりの辺にちょうど接する。
`padding` が 0.5zw より小さければ、箱は辺を越えて枠に重なる。

### JLReq のぶら下げ組

JLReq は、ぶら下げ組を、行頭禁則にかかる句点類（cl-06）と読点類（cl-07）に限り、行末の版面の領域の外側に接して置く処理とする（「基本版面からはみ出す例」の節）。
用語集も、句読点を一字だけ、指定された行長を越えて置く方法とする（JIS Z 8125 の引用）。
どちらも、ぶら下げる先は版面の外の余白である。
囲みの中では、行が届いてよい端は版面の端ではなく、囲みの内側の端である。
囲みの内側の余白は、文字と枠を離すための空きであり、版面の外の余白とは役割が違う。

### 今のほかの例外

表のセルは、すでにぶら下げ組と突き出しを使わない（[golem-driver ADR 0008](../golem-driver/adr/0008-pdf-tables.md)、[`tableEnv`](https://github.com/tett23/golem/blob/7e8fe7d3d59d893342c0e55a1cb6d1a39245a482/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2279-L2288)）。
行末の約物が列の幅の外に出ると、隣の列の間隔に入り込むためである。
コードブロックも、ぶら下げ組を使わない（[仕様書の「style.toml」](../specifications.md#styletoml) の段落スタイル `code` の節）。
囲みの中の段落は、行の領域の外に枠と余白を持つ点で、セルと同じ形をしている。

## 実装すること

### 囲みの中ではぶら下げない

囲みを持つ段落（[ADR 0271](0271-paragraph-backgrounds-and-borders.md) の「囲む段落」のとおり、文書の最上位の段落で、解決した段落スタイルが `background` か `border` を持つもの）は、`hanging-punctuation` の値によらず、`hanging-punctuation = false` のときと同じに組む（「メンテナーが決めること」の 1）。
一つの囲みにまとめた段落と、`line-breaks = "keep"` の段落（連）も同じである。

- golem-typeset の `composeUnit` は、`uBox` を持つ単位を、`ComposeEnv` の `ceHanging` を偽にした環境で組む。
- 同じ単位の行分割の `Params` の `pProtrusion` は、`[composition]` の `protrusion` の値にする。今は `kpParams` が `protrusion || hanging-punctuation` にしているので（[`kpParams`](https://github.com/tett23/golem/blob/7e8fe7d3d59d893342c0e55a1cb6d1a39245a482/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1473-L1482)）、`hanging-punctuation` だけを偽にしたときの値と等しくする。
- 突き出し（`protrusion`）は変えない。`protrusion = true` の本では、囲みの中の欧文の行の端のハイフン、ダッシュ、句読点、引用符を、今のとおり少し外に出す（「実装しないこと」）。

囲みを持たない段落、注の本文、傍注、表のセル、見出し、キャプション、コードブロックの組み方は変えない。
囲みの中の段落の注の本文は、段の下に置かれて囲みの外にあるので、今のとおり `hanging-punctuation` に従う。

意味論 IR、CDDL、プラグインの ABI、style.toml のキー、diagnostics は変えない。
golem のパッケージのあいだの `build-depends` も変えない。

### HTML と EPUB

変えない。
Golem の `style.css` は CSS の `hanging-punctuation` を書かず、PDF のぶら下げ組は HTML に移らない（マニュアルの出力の章）。

### 文書

- [docs/specifications.md](../specifications.md) の「style.toml」の `hanging-punctuation` の説明に、囲みを持つ段落ではぶら下げないことを書き、この ADR へのリンクを付ける。段落の囲みの節の、行の領域を述べる段落にも同じことを書く。行分割の不変条件の段落に、この ADR の H1 から H3 を足す。
- マニュアルの style.toml の章（`manual/chapters/05-style.gm`）の `hanging-punctuation` の項目と、style.toml の付録（`manual/appendices/c-style.gm`）の `hanging-punctuation` の行に、囲みを持つ段落ではぶら下げないことを足す。
- [docs/diagnostics.md](../diagnostics.md) と docs/markup.md は変えない。コードと記法を変えないためである。
- [ロードマップ](../roadmap.md) にこの項目はないので、変えない。

## 実装しないこと

- **囲みの中の突き出し**：`protrusion = true` の欧文の行の端の字は、今のとおり囲みの中でも外に出す。出す量は字の幅の一部であり、ぶら下げの半角より小さい（[golem-layout ADR 0014](../golem-layout/adr/0014-protrusion-amount.md)）。囲みの中でも止めるかは、必要がわかってから別の ADR で決める。
- **ぶら下げの分だけ余白を広げること**：「メンテナーが決めること」の 1 の (b) は採らない。
- **段落スタイルごとのぶら下げの設定**：`hanging-punctuation` を段落スタイルに書けるようにはしない。囲みの中で止めることは、囲みを持つことから決まる。
- **HTML と EPUB の変更**：上の「HTML と EPUB」のとおり。
- **囲みの外の組み方の変更**：囲みを持たない段落のぶら下げは、今のとおりである。

## 不変条件

「囲みの段落」は、PDF の組版で `uBox` を持つ単位（囲みを持つ段落と、囲みの中の連）とする。
「句読点の箱」は、句点類（`FullStop`）と読点類（`Comma`）の字の箱とする。

- **H1 ぶら下げない**：どの本でも、囲みの段落の行分割の項目のうち、句読点の箱の `bcProtrudeEnd` は 0 である。
- **H2 ぶら下げを切った組み方と等しい**：`[composition]` の `hanging-punctuation` だけが違う二つの本で、同じ囲みの段落の行（`SetLine` の `slLine` と `slIndent`）は等しい。
- **H3 囲みの外は変わらない**：囲みの段落でない単位（囲みを持たない段落、注の本文、表のセル、見出し、コードブロック）の行は、この ADR の前と等しい。`hanging-punctuation = true` の本では、囲みを持たない段落の行末の句読点は、今のとおりぶら下がりうる。

H1 と H2 から、`protrusion = false` の本では、はみ出さない（`lineOverflow` が 0 の）囲みの段落の行は、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L1 から L13 のとおり行の領域の中に収まる。
句読点の箱が囲みの終わりの辺に接することも、辺を越えることもない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 囲み | 背景だけで `padding` が既定（0.5zw）、枠を持ち `padding = "0pt"`、一つにまとめた二つの段落、`line-breaks = "keep"` の連 |
| 組方向 | 横組み、縦組み |
| 囲みの分け方 | 分けない囲み、二つの頁に分けた囲み（最初の部分と最後の部分） |
| 組み方の設定 | `hanging-punctuation` が `true` と `false`、`protrusion` が `true` と `false` |
| 行末の字 | 行の領域にちょうど収まる `。`、行の領域から一字あふれる位置の `。` と `、`（ぶら下げ組ならぶら下がる位置）、句読点でない `」` |
| 囲みの外 | 囲みを持たない段落、コードブロック、表のセル、囲みの中の段落の脚注の本文 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、H1 から H3 の番号を入れる。

- **golem-driver のテスト（`BoxesSpec`）**：横組みの本（`horizontalStyle`、一行 12 字）と縦組みの本（`pdfStyle`）で、`hanging-punctuation = true` と `false` の二つを組み、囲みの段落の行を比べる（H2）。囲みの段落の本文は、行の領域から一字あふれる位置に `。` と `、` が来る文字列とし、背景だけの既定の `padding` の囲み、`padding = "0pt"` の枠の囲み、二つの段落をまとめた囲み、連の囲みの四つを置く。今の実装は `true` の本で `。` をぶら下げるので失敗する。
- 同じ本で、囲みの段落の行の句読点の箱の `bcProtrudeEnd` がすべて 0 であること（H1）。`protrusion = true` の本でも確かめる。今の実装では失敗する。
- 二つの頁に分かれる長さの囲みの段落（横組みの本で 30 行を超えるもの）で、H1 と H2 が成り立つこと。
- 囲みを持たない同じ文字列の段落が、`hanging-punctuation = true` の本で行末の `。` をぶら下げること（H3、`lineProtrusion` の終わりの側が正）。この ADR の前の実装でも成り立つので、実装の前に通ることを確かめる。
- H3：囲みを持たない今の fixture（golem-driver の golden の `complex-horizontal` と `complex-vertical`）の出力が変わらないこと。囲みを持つ `specimens` の横組みと縦組みは、ぶら下げていた行の組み方が変わりうるので、golden と見た目の回帰テストの参照を CI の成果物から更新し、変わった頁の画像を見て、囲みの中の句読点が辺に接しなくなったことを確かめる。

## トレードオフ

囲みの中の行は、囲みの外の行より、行末の句読点を前の行に収める余地が少ない。
ぶら下げられない句読点は行頭禁則のため前の行に追い込むか、前の字とともに次の行に送ることになる。
そのため、囲みの中の行の字のあいだは、同じ文字列を囲みの外で組んだときより詰まるか空きやすい。
囲みの中の行の領域は、囲みの外より `padding` の二倍だけ狭いので、この差はもとから生じている。

ぶら下げ組の本で、囲みの中と外とで行末のそろい方が違う。
囲みの外では句読点の分だけ行末が出入りし、囲みの中ではそろう。
囲みの中では行末の辺がそろって見えるので、枠との間隔の揺れがないほうを優先した。

突き出しを囲みの中でも止めないので、`protrusion = true` の本では、欧文の行の端の字が `padding` の中に少し入る。
ぶら下げと突き出しの扱いが分かれるが、突き出しは字面の見かけの端をそろえるための量であり、句読点の箱を丸ごと外に出すぶら下げとは目的が違う。

## メンテナーが決めること

1. **囲みの中のぶら下げ**：推奨は、(a) 囲みの中ではぶら下げないことである。JLReq のぶら下げは版面の外に出す処理であり、囲みの中で行が届いてよい端は囲みの内側の端である。表のセルとコードブロックがすでにぶら下げないことと同じ扱いになる。
   - 退けた案の一つは、(b) ぶら下げる分だけ `padding` を行末の側に広げることである。句読点は囲みの中に収まるが、行末の側の余白が行の始まりの側より半角広くなり、`padding` が辺によらず一つの値という [ADR 0271](0271-paragraph-backgrounds-and-borders.md) の規則と合わない。ぶら下げる句読点のない行では、行末の側だけが空いて見える。
   - もう一つは、(c) 今のまま変えないことである。既定の囲みでは句読点の箱が終わりの辺に接し、`padding` を 0.5zw より小さくすると枠に重なる。

## 決めたことの記録

2026-11-10 に、tett23 が次のとおり決めた。

1. 囲みの中のぶら下げは、(a) 囲みの中ではぶら下げない、(b) ぶら下げる分だけ `padding` を広げる、(c) 今のまま変えない、の三つの案から、推奨の (a) とした。JLReq のぶら下げは版面の外に出す処理であり、囲みの中で実際に届いてよい端は囲みの内側の端である、という理由による。

## 参考文献

- [ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0271](0271-paragraph-backgrounds-and-borders.md)
- [golem-driver ADR 0008](../golem-driver/adr/0008-pdf-tables.md)、[golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md)、[golem-layout ADR 0014](../golem-layout/adr/0014-protrusion-amount.md)
- W3C. Requirements for Japanese Text Layout (JLReq). https://www.w3.org/TR/jlreq/（「基本版面からはみ出す例」の節と、用語集の「ぶら下げ組」）。w3c/jlreq の `index.html`（`43942474`）を 2026-11-10 に読んだ。
