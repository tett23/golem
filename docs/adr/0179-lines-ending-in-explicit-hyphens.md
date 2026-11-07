# ADR 0179: 明示したハイフンを含む語の要素を分綴する

ステータス: 採択（未実装）

## 文脈

ロードマップの v0.1.0-rc4 の「明示したハイフンの前の行」は、原稿に書いたハイフンで終わる行が極端に間延びするとしている（fixture の『The Elements of Style』の目次と本文）。
[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md) は、欧文の語の中のハイフンの直後を分割の候補にし、そのような語には Liang のパターンを当てないと決めた。
TeX と同じ扱いである。

### 再現

fixture の `pd/elements-of-style` を作業用のディレクトリに写し、`tempest` の fixture のフォントを置いて、`main`（`50b9fca8`）から作業用のディレクトリでビルドした `golem` で PDF を組んだ（2026-11-06）。
行ごとの語の位置は、PDF の内容のストリームの文字の位置から読んだ（作業用のスクリプトで、コミットしない）。
原稿や `style.toml` を書き換えた試しは、手元に入れてある `golem`（0.1.0-rc3）で組んだ。
書き換える前の fixture では、`50b9fca8` からビルドしたものと同じ PDF を出力することを確かめてある。
語間の自然な幅は 2.34pt（Source Serif、10pt）で、伸びはその半分（1.17pt）である（[`Japanese.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L600-L604)）。
明示したハイフンで終わる行のうち、語間が広い行は次の三つである。

| ページ | 行 | 語間 | 自然な幅との比 | 不良度（計算） |
| --- | --- | --- | --- | --- |
| 1（目次） | `4. Place a comma before a conjunction introducing a co-` | 5.71pt | 2.44 | 約 2400 |
| 34（本文） | `edi-ble (not ed-ible); propo-sition; ordi-nary; espe-cial; reli-` | 5.34pt | 2.28 | 約 1700 |
| 35（本文） | `for-tune; pic-ture; sin-gle; presump-tuous; illus-tration; sub-` | 5.12pt | 2.19 | 約 1300 |

不良度は、TeX の式（およそ 100 × 調整比の三乗）で、語間の広がりと伸びから計算した。
どれも `tolerance`（200）を超えるので、許容度を問わない最後の段階で選ばれた行である（[`KnuthPlass.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L218-L233)）。
明示したハイフンで終わるほかの三つの行（19、25、52 ページ）の語間は 1.79pt から 3.31pt で、間延びしていない。

### 原因

目次の行を例にとる。
`co-ordinate` の分割の候補は、ハイフンの直後の一か所だけである（[`Japanese.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L749-L771)）。
`ordinate` はハイフンの後ろの要素なので、パターンで分綴されない。
行を `co-` で終えるか、`co-ordinate` の全体を載せるかしかない。

PDF の箱の位置から、行の自然な幅は 249.7pt、行長は 280pt である。
`ordinate`（37.7pt）と語間を足すと、10 の語間を縮めきっても行長を 1.9pt 超える。
したがって `co-` で終えるしかなく、足りない 30pt を 9 つの語間が受け持つ。

ハイフンを除いた原稿で確かめると、この見立てと合う。
目次の `co-ordinate` を `coordinate` に書き換えて組むと、`coordinate` が行に収まり、語間は 1.87pt になった。
ハイフンの字幅（3.2pt）の分だけ短くなるからである。
TeX（`tex`、TeX Live 2026）の `\showhyphens` は、`ordinate` を `or-di-nate`、`coordinate` を `co-or-di-nate` と分ける。

34 ページと 35 ページの行は、事情が違う。
分綴の例を並べた段落で、ほとんどの語に原稿のハイフンがある。
行の最後の語（`reli-gious`、`sub-stan-tial`）の後ろの要素を分綴しても、行に足せる部分が残りの幅より長いので、語間は変わらない（後述の試算）。
この二行を詰めるには、語間のほかに伸び縮みするもの（グリフの幅の伸縮）が要る。

### 試したこと

`[composition]` に `expansion = { limit = 20, step = 5 }`（[golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md)）を書いて組むと、三つの行はそれぞれ `co-ordinate`、`reli-gious;`、`sub-stan-` まで載り、間延びしなくなった。
34 ページを 100dpi の PNG に描いて、語間が本文のほかの行と同じ程度であることを目で確かめた。
ただし、グリフの幅の伸縮は [golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md) が利用者の選ぶものとしており、既定では伸縮しない。

### 参照した組み方

- TeX は、明示したハイフンを含む語を分綴しない（[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md) の「パターンによるハイフネーションとの関係」）。
- LuaTeX の手引きは、`\automatichyphenmode` の説明で、ハイフンの両側の語を分綴する案を試して捨てたと書く。複合語の中に分割の位置を足すには、`\hyphenation` の例外に `{-}{}{-}` の形で書く。
- LaTeX の microtype は、使える処理系ではグリフの幅の伸縮と文字の突き出しを既定で有効にする（パッケージの README）。

## 実装すること

### 複合語の要素の分綴（golem-layout）

明示したハイフンを含む欧文の語を、ハイフンの直後で要素に分けたうえで、要素ごとに Liang のパターンを当てる（「メンテナーが決めること」の 1）。

- `wordItems` は、今のとおり `explicitParts` で語を要素に分け、要素のあいだに `Penalty 0 p ExplicitHyphen` を置く。
- 各要素から、末尾のハイフンとダッシュの連なりを除いた部分を一つの語としてパターンに渡す。`co-ordinate` なら `co` と `ordinate`、`well-known` なら `well` と `known` である。除いた連なりは、分綴した最後の部分の後ろに戻す。
- パターンが分けた位置には、今の分綴と同じ `Penalty w 50 PatternHyphen` を置く（「メンテナーが決めること」の 3）。幅 `w` は描くハイフンの字幅である。
- `PatternHyphen` なので、一回目の段階（`pretolerance`）では使わず、二回目の段階から候補にする。明示したハイフンの候補は、今のとおり一回目から使う。
- 要素の長さが `lefthyphenmin` と `righthyphenmin` の和に満たない場合は、パターンの規則で分けない（今の分綴と同じ）。
- 要素ごとに当てるので、[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md) が挙げた `well--` の不具合（ハイフンを文字として読んだパターンが、ハイフンの直後に候補を作る）は起きない。パターンはハイフンを見ない。
- `explicit-hyphen-penalty` が 10000 以上で、語を一つの箱にする場合は、今のとおり分綴しない。

PDF の箱の幅から試算すると、目次の行は `co-ordi-` で終えられる。
自然な幅は 271.1pt（249.7pt に `ordi` の 18.3pt とハイフンの 3.1pt を足した値）で、9 つの語間の伸び 10.5pt で 8.9pt を受け持つ。
調整比は 0.85、不良度は約 60 で、二回目の段階で選べる。

試作として、`50b9fca8` を写した作業用のディレクトリで `wordItems` を上の規則に書き換えた `golem` をビルドし、fixture を組んだ（2026-11-06）。

- 目次の行は `4. Place a comma before a conjunction introducing a co-ordi-` で終わり、語間は 3.33pt（自然な幅の 1.42 倍）になった。試算と合う。
- 34 ページと 35 ページの行は変わらなかった（語間 5.34pt と 5.10pt）。34 ページは `gious` が分綴されず、35 ページは `stan-`（約 20pt）が残りの幅（語間の伸びと縮みを足して約 17.8pt）に収まらないからである。
- 49 ページの `over-simplified` を含む行（語間 8.06pt）も変わらなかった。次の語 `spellings` がパターンで分綴されないからである。
- 『The Merry Wives of Windsor』、『The Frogs』、『Nightmare Abbey』、『The Hunting of the Snark』も、PDF のバイト列が変わった。どれもハイフンを含む語を持つ。どの行が変わったかは調べていない。

### ドキュメント

- 仕様書の「行分割」の、明示のハイフンを含む語にパターンを当てないという記述を、要素ごとに当てる記述に改め、この ADR へのリンクを付ける。
- [golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md) のステータスの行に「明示のハイフンを含む語の分綴は [docs/adr/0179](0179-lines-ending-in-explicit-hyphens.md)」を加える。
- ロードマップの v0.1.0-rc4 から「明示したハイフンの前の行」を消す。34 ページと 35 ページのような、要素の分綴では詰まらない行は「実装しないこと」に書いたとおり残る。
- `docs/` の下に、Golem と TeX の組版の差異をまとめる文書 docs/differences-from-tex-and-indesign.md を新しく作る（「メンテナーが決めること」の 4）。[docs/adr/0189](0189-paragraph-alignment-spacing-and-end-indent.md) が InDesign との差異を同じ文書に書くので、名前に両方を入れる。
  - 文書は、差異ごとに一つの節を持つ。節には、TeX（と InDesign）の振る舞い、Golem の振る舞い、差異を決めた ADR へのリンク、移ってくる書き手が気をつけることを書く。
  - 最初の節は、この ADR の差異とする。TeX は明示したハイフンを含む語を分綴しないが、Golem は語を要素に分け、要素ごとにパターンで分綴する。一回目の段階で収まる段落では TeX と同じ結果になり、収まらない段落では `co-ordi-nate` のように一つの語に二種類のハイフンが並ぶことがある。
  - docs/specifications.md の「行分割」の節から、この文書へリンクする。
  - 文書は仕様の一部であり、コミットした後も、差異が変わればその都度書き換える。記録（`docs/audits/` の下の文書など）ではない。

## 実装しないこと

- グリフの幅の伸縮（`expansion`）を既定で有効にすること（「メンテナーが決めること」の 2）。
- 34 ページと 35 ページのような、ほとんどの語にハイフンを書いた段落の行を詰めること。書き手は `expansion` を書けば詰められる。
- 原稿で分綴の位置を指定する記法（任意ハイフン）。ロードマップの「任意ハイフン、分綴の例外、分離禁止」で扱う。
- U+2011（NON-BREAKING HYPHEN）を含む語の分綴。今のとおり一つの箱のままにする。
- 和文の中のハイフン類の扱い。
- HTML と EPUB の出力の変更。行分割はブラウザーが行う。

## テスト設計

`modules/golem-layout/test/Main.hs` のテストを先に書き換え、今の実装で失敗することを確かめてから実装する。

- `compose env "co-ordinate"`（`cePatterns = Just englishUS`）で、`co-` の後に `ExplicitHyphen` の罰則が一つあり、`ordinate` の箱が `hyphenate englishUS "ordinate"` の部分に分かれ、そのあいだに `PatternHyphen` の罰則があること。期待値はテストの中で `hyphenate` から求め、部分が二つ以上あることも確かめる。
- [golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md) の「`well-known` と `self-evident` に `PatternHyphen` の罰則がない」テストを、次のように改める。`well-known` の `well` と `known` はパターンで分けられないので、今のとおり `PatternHyphen` がない。`self-evident` は `evident` の中に `PatternHyphen` があり、ハイフンの直後（`self-|e…`）にはないこと。
- `compose env "lime-tree"` と `compose env "a--b"` の罰則が今と同じであること（要素が短く、分綴されない）。
- `ceExplicitHyphenPenalty = 10000` の `compose env "co-ordinate"` は、今のとおり箱が一つで罰則がないこと。
- 行分割：`co-` で終えると不良度が `tolerance` を超え、`ordinate` の中で分ければ超えない行長で、`co-ordinate` を含む段落を組む。`brPass` が 2 で、`ordinate` の中の罰則の位置で分かれること。`co-` で終えても `pretolerance` に収まる行長では、`brPass` が 1 で `co-` の後で分かれること。
- [golem-layout ADR 0007](../golem-layout/adr/0007-knuth-plass-reference-test.md) の参照テストが今のとおり通ること。参照テストは `\hyphenpenalty=10000` で組むので、パターンの候補は使われない。
- 決定性の検査が通ること。

見た目の回帰テストでは、欧文の fixture の参照を更新する。
更新の前に、`pd/elements-of-style` の 1 ページ目の目次の行が `co-ordi-` で終わり、語間が詰まったことを、変わったページの画像で確かめる。
ほかの変わったページも、明示したハイフンを含む語の要素の中で分かれた行だけが変わったことを確かめる。

## トレードオフ

TeX とも LuaTeX の既定とも結果が変わる。
[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md) は「一つの語に明示のハイフンとパターンのハイフンが並び、TeX とも結果が変わる」として、この案を退けていた。
この ADR は、その判断を、目次の行のような間延びを減らすほうに改める。
`co-ordi-nate` のように一つの語に二種類のハイフンが並ぶ行ができる。
TeX から移る書き手が差異を一か所で引けるように、差異を docs/differences-from-tex-and-indesign.md に書く。
差異の文書は、差異を足す ADR ごとに保守する文書が一つ増えることになる。

複合語は明示したハイフンの位置で分けるのが望ましいとされることがある（この ADR では文献で確かめていない）。
明示したハイフンの候補は一回目の段階から使い、要素の中の候補は二回目の段階からしか使わないので、一回目の段階で収まる段落では今と結果が変わらない。
許容度に収まる分け方がない段落でだけ、要素の中で分ける。

分割の候補が増えるので、行分割の計算の量は少し増える。

要素の分綴で詰まらない行（34 ページと 35 ページ）は残る。
これを詰めるグリフの幅の伸縮を既定にすると、すべての欧文の本の字形が変わる。

## 決めたことの記録

- **明示したハイフンの前の行を直すこと**（ロードマップ、v0.1.0-rc4 の「明示したハイフンの前の行」）：原稿に書いたハイフンで終わる行が、極端に間延びする（fixture の『The Elements of Style』の目次と本文）。
- **TeX との差異の文書**（2026-11-07、メンテナー）：TeX との差異は、`docs/` の下に新しく文書を作ってまとめる。
- **直し方、グリフの幅の伸縮、要素の中の分綴の罰則**（2026-11-07、メンテナー）：「メンテナーが決めること」の 1、2、3 を推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **直し方**：決めた。明示したハイフンを含む語の要素ごとにパターンを当て、要素の中の分綴を二回目の段階から使う。
2. **グリフの幅の伸縮を既定にするか**：決めた。既定にしない。字形を変えるかどうかは書き手が決める。
3. **要素の中の分綴の罰則**：決めた。今のパターンの分綴と同じ 50 とし、新しい設定を作らない。
4. **TeX との差異の文書**：決めた。docs/differences-from-tex-and-indesign.md を新しく作り、この ADR の差異を最初の節にする。[docs/adr/0189](0189-paragraph-alignment-spacing-and-end-indent.md) の InDesign との差異も同じ文書に書く。

## 参考文献

- [golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md)、[golem-layout ADR 0007](../golem-layout/adr/0007-knuth-plass-reference-test.md)、[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md)
- *LuaTeX Reference Manual*, Languages の章の `\automatichyphenmode` と例外の節。TeX Live 2026 の `texmf-dist/doc/context/sources/general/manuals/luatex/luatex-languages.tex` を読んだ（2026-11-06）。
- R Schlicht, *The microtype package*, README（v3.2d）。TeX Live 2026 の `texmf-dist/doc/latex/microtype/README.md` を読んだ（2026-11-06）。
- Donald E. Knuth, *The TeXbook*, Chapter 14 と Appendix H。
