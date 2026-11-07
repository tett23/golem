# TeX と InDesign との差異

この文書は、Golem の組版が TeX や InDesign と異なる振る舞いをまとめる。
TeX や InDesign から移ってくる書き手が、差異を一か所で引けるようにするためである。

差異ごとに一つの節を置く。
節には、TeX（と InDesign）の振る舞い、Golem の振る舞い、差異を決めた ADR、移ってくる書き手が気をつけることを書く。
この文書は仕様の一部であり、差異が変わればその都度書き換える。

## 明示したハイフンを含む語の分綴

### TeX の振る舞い

TeX は、原稿に書いたハイフンを含む語を、Liang のパターンで分綴しない。
`co-ordinate` は `co-` の後ろでだけ分けられる。
LuaTeX も、既定では同じである。

### Golem の振る舞い

Golem は、明示したハイフンを含む語を、ハイフンの直後で要素に分け、要素ごとにパターンで分綴する。
`co-ordinate` は、`co-` の後ろのほか、`ordinate` の中（`or-di-nate`）でも分けられる。
要素の中の候補は二回目の段階から使い、明示したハイフンの候補は一回目の段階から使う。
そのため、一回目の段階で収まる段落では、TeX と同じ結果になる。
収まらない段落では、`co-ordi-nate` のように、一つの語に原稿のハイフンとパターンのハイフンが並ぶことがある。

### 決めた ADR

- [docs/adr/0179](adr/0179-lines-ending-in-explicit-hyphens.md)
- [golem-layout ADR 0008](golem-layout/adr/0008-explicit-hyphens.md)（明示したハイフンでの分割）

### 書き手が気をつけること

TeX で組んだときと、ハイフンで終わる行の位置が変わることがある。
ほとんどの語にハイフンを書いた段落の行は、要素の中で分けても詰まらないことがある。
そのような行は、`[composition]` の `expansion`（グリフの幅の伸縮）を書けば詰められる。

## 段落の前後のアキの合わせ方

### InDesign の振る舞い

InDesign は、前の段落の段落後のアキと、次の段落の段落前のアキを足す。
後のアキが 1 行の段落の後に、前のアキが 1 行の段落が来ると、2 行空く。

### Golem の振る舞い

Golem は、違う段落スタイルの段落のあいだでは、前の段落の `space-after` と次の段落の `space-before` のうち大きいほうを取る。
上の例では 1 行空く。
同じ段落スタイルの段落のあいだでは、`space-between` だけを取り、前後のアキを使わない。
複数の段落からなる引用の段落のあいだに、前後のアキが入らないようにするためである。
HTML と EPUB では、CSS の余白の相殺と同じ結果になる。

### 決めた ADR

- [docs/adr/0189](adr/0189-paragraph-alignment-spacing-and-end-indent.md)

### 書き手が気をつけること

InDesign の版下を移すときは、前後のアキの値を読み替える。
二つのアキを足した空きが要るなら、どちらかの値を和にする。

## 段落の前後のアキの単位

### InDesign の振る舞い

InDesign は、段落前と段落後のアキを長さで書く。

### Golem の振る舞い

Golem は、`space-before` と `space-after` を行の格子の行の数で書く。
`space-between` と同じく、行の格子を崩さないためである。
長さ（`mm` や `zw`）では書けない。

### 決めた ADR

- [docs/adr/0189](adr/0189-paragraph-alignment-spacing-and-end-indent.md)

### 書き手が気をつけること

InDesign で長さで書いたアキは、行送りで割った行の数に直す。

## 縦組みのノド側と小口側の揃え

### InDesign の振る舞い

InDesign は、縦組みのフレームでは、ノド側に揃える指定と小口側に揃える指定を適用しない。

### Golem の振る舞い

Golem は、縦組みの本で `align = "towards-spine"` か `align = "away-from-spine"` を書くと、エラー（G03118）として止める。
書いた値を黙って適用しない出力を作らないためである。

### 決めた ADR

- [docs/adr/0189](adr/0189-paragraph-alignment-spacing-and-end-indent.md)

### 書き手が気をつけること

横組みと縦組みを切り替える本では、段落スタイルの `align` も書き換える。

## 最終行右インデント

### InDesign の振る舞い

InDesign は、段落の最後の行だけの終わりの側の字下げ（最終行右インデント）を持つ。

### Golem の振る舞い

Golem は、最後の行だけの終わりの側の字下げを持たない。
すべての行の終わりの側の字下げは、段落スタイルの `end-indent` で書く。

### 決めた ADR

- [docs/adr/0189](adr/0189-paragraph-alignment-spacing-and-end-indent.md)

### 書き手が気をつけること

最終行右インデントを使った段落は、`end-indent` か、ほかの揃えで組み直す。
