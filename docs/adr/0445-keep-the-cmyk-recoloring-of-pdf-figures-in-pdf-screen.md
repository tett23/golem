# ADR 0445: pdf-screen でも、PDF の図版の色の置換は CMYK のまま書き、SVG とラスターの図版は HTML と同じ値で書く

Status: proposed

## 文脈

[root ADR 0431](0431-plain-pdf-1-7-target.md) は、画面で読むための `pdf-screen` のターゲットを決めた。
その「実装すること」の書き方の色の項は、スウォッチで塗る文字、罫線、背景と、図版の色の明示的な置換（`[figures]` の `color`）を、HTML と EPUB と同じ `cmykToRgb` の sRGB で書くと決めている。
境界の表の I4 の行も、置き換えた図版の色が `cmykToRgb` の値と等しいことを求める。

ところが、PDF の出力の図版の色の置換は、図版の種類によって経路が違う。
PDF の図版は、PDF のページとして CMYK で塗り直す仕組みしか持たず、これを sRGB で書くには、色空間の書き方と透明のグループの色空間を新しく決める必要がある。
SVG の図版とラスターの図版は、HTML と EPUB のために sRGB で置き換える仕組みをすでに持つ。
ただし、灰色のラスターの図版の画素は、スウォッチの濃淡ごとに違う色になり、`cmykToRgb` の一つの値とは等しくならない。
0431 はこの違いを決めておらず、実装はこの点で止まった。
この ADR は、`pdf-screen` の図版の色の置換を、図版の種類ごとに決め直す。

## 調査した事項

origin/main（[5dfabfe99](https://github.com/tett23/golem/commit/5dfabfe991b96edaab06c6ecb966c2390497910b)）で、次のことを確かめた。

- PDF の出力では、PDF の図版も SVG の図版も `recolorPdf` で色を置き換え、`recolorPdf` は `recolorImportedPage` を呼ぶ（[Flow.hs#L5015](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L5015)、[Flow.hs#L5021-L5023](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L5021-L5023)、[Flow.hs#L5038-L5041](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L5038-L5041)）。
  ラスターの図版は、`safeAnalyzeRaster` の結果の画像に替える（[Flow.hs#L5024-L5032](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L5024-L5032)）。
- `recolorImportedPage`（`PdfColor.hs`）は、CMYK だけを書く。
  塗りは `paint` で CMYK を書き（[PdfColor.hs#L1827](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/PdfColor.hs#L1827)）、画像は DeviceCMYK（CCITT の画像は Indexed の DeviceCMYK）にし（[PdfColor.hs#L1519](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/PdfColor.hs#L1519)、[PdfColor.hs#L1533](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/PdfColor.hs#L1533)）、パターンの色空間は DeviceCMYK で（[PdfColor.hs#L1902](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/PdfColor.hs#L1902)）、透明のグループは `cmykGroup` で作り（[PdfColor.hs#L616](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/PdfColor.hs#L616)）、結果のページを `UseCmyk` と記録する（[PdfColor.hs#L99](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/PdfColor.hs#L99)）。
- SVG の図版の描画（`Drawing`）は、パスとグループだけを持ち、色は 0 から 255 の sRGB で、不透明度と透明のグループを持たない（[Drawing.hs#L32-L44](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-pdf/src/Golem/Pdf/Drawing.hs#L32-L44)）。
  `recolorFigure` は、SVG の図版の色を `rgbTone` で sRGB に置き換える（[Svg.hs#L122-L138](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/Svg.hs#L122-L138)）。
- ラスターの図版の置換は、PDF のために CMYK の画像（`CsCmyk`）を、HTML のために `rgbComponents` で写した sRGB の PNG を作る（[FigureColor.hs#L156-L171](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/FigureColor.hs#L156-L171)）。
  灰色の図版の画素はスウォッチの濃淡になるので、画素ごとに色が違う。
  一色の図版では、濃さが 1 なので、どの画素も `cmykToRgb` と同じ値になる。
- HTML と EPUB は、SVG の図版を `recolorFigure` で、PNG と JPEG の図版を同じ仕組みの PNG で置き換え、PDF の図版は置き換えない（[Driver.hs#L1448-L1476](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-driver/src/Golem/Driver.hs#L1448-L1476)）。
  そのため、PDF の図版だけは、HTML と EPUB に比べる相手が無い。
- `rgbComponents` は、C と K から R を `(1 − c)(1 − k)` で求める（[FigureColor.hs#L210](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-typeset/src/Golem/Typeset/FigureColor.hs#L210)）。
  濃さ d を掛けた `(1 − c d)(1 − k d)` は、c と k のどちらも 0 でないとき、d について線形でない。
  そのため、透明のグループの中で二つの色を sRGB で混ぜた色と、混ぜた濃さを sRGB に写した色は、一般には一致しない。
- golem-driver のライブラリは golem-html に依存しているが（[golem-driver.cabal#L63](https://github.com/tett23/golem/blob/5dfabfe991b96edaab06c6ecb966c2390497910b/modules/golem-driver/golem-driver.cabal#L63)）、`golem-driver-pdf-test` を含むテストスイートは、golem-html を build-depends に持たない。

## 実装すること

### PDF の図版

`pdf-screen` でも、`[figures]` の `color` で置き換えた PDF の図版は、`pdf` と同じく `recolorImportedPage` で CMYK に塗り直し、DeviceCMYK のまま書く。
透明のグループの色空間も `pdf` と同じにする。
出力インテントが無いので、PDF の閲覧ソフトが DeviceCMYK を画面の色に変える。

### SVG の図版

`pdf-screen` で `color` で置き換えた SVG の図版は、HTML と同じ `recolorFigure` で sRGB に置き換え、sRGB の ICCBased の色空間で書く。
各色は、HTML の SVG の色と同じ整数を 255 で割り、置き換えない SVG の図版を書くときと同じ桁に丸めた値で書く。

### ラスターの図版

`pdf-screen` で `color` で置き換えた PNG と JPEG の図版は、HTML の PNG と同じ画素（`rgbComponents` で写した値）の sRGB の画像にし、sRGB の ICCBased の色空間で書く。
透明度は、HTML の PNG のアルファと同じ値の SMask で書く。

### スウォッチで塗る文字、罫線、背景

0431 のとおり `cmykToRgb` の sRGB で書く。

### テストの依存

0431 の I4 のテストと、この ADR のテストを置く `golem-driver-pdf-test` に、golem-html を build-depends として足す。
ライブラリはすでに golem-html に依存しているので、パッケージの依存の向きは変わらない。

### 文書とステータスの行

仕様書の `pdf-screen` の色の記述と、マニュアルの出力の章に、図版の種類ごとの色の書き方を書く。

採択したら、[root ADR 0431](0431-plain-pdf-1-7-target.md) のステータスに、次の部分をこの ADR が置き換えたと記録する。

```text
superseded-pending [{"part":"実装することの書き方の色の項のうち図版の色の明示的な置換、不変条件の I4（スウォッチで塗る文字、罫線、背景に狭める）、境界の表の [figures] の color の行、受けいれ条件の A1 の色の比べ方","by":["docs/adr/0445-keep-the-cmyk-recoloring-of-pdf-figures-in-pdf-screen.md"],"kind":"replace"}]
```

0431 の A1 は、PDF の図版を除いて、色が HTML の出力と同じに見えることを確かめる。

## 実装しないこと

PDF の図版を sRGB で塗り直す仕組みは作らない。
`pdf` の色の置換は変えない。
`pdf-screen` で PDF の図版の色の置換に diagnostic を出すことはしない。

## 不変条件

- I1: `--target pdf --target pdf-screen` のビルドで、`color` を指定した PDF の図版の Form XObject と、そこからたどれるすべてのオブジェクト（入れ子の Form、画像、パターン、シェーディング、`/Group`）は、オブジェクトの番号を除いて `pdf` と `pdf-screen` で等しい。
- I2: `pdf-screen` で `color` を指定した SVG の図版の各色の成分は、HTML の出力の同じ図版の SVG の色の整数を 255 で割り、置き換えない SVG の図版と同じ桁に丸めた値に等しい。
- I3: `pdf-screen` で `color` を指定したラスターの図版の画素は、HTML の出力の同じ図版の PNG の画素と等しい。
- I4: `pdf-screen` で、スウォッチで塗る文字、罫線、背景の色は、0431 の I4 のとおり `cmykToRgb` の値と等しい。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `color` で置き換えた PDF の図版 | `pdf` と同じ DeviceCMYK | I1 |
| `color` で置き換えた透明のグループを持つ PDF の図版 | グループの色空間も `pdf` と同じ | I1 |
| `color` で置き換えた、灰色だけの SVG の図版 | HTML の SVG と同じ sRGB | I2 |
| `color` で置き換えた、一色の SVG の図版 | HTML の SVG と同じ sRGB | I2 |
| `color` で置き換えた、一色の PNG | どの画素も `cmykToRgb` の値 | I3 |
| `color` で置き換えた、8 ビットの灰色の PNG | HTML の PNG と同じ画素 | I3 |
| `color` で置き換えた、灰色の JPEG | HTML の PNG と同じ画素 | I3 |
| `color` で置き換えた、16 ビットの PNG | HTML の PNG と同じ画素 | I3 |
| `color` で置き換えた、透明度を持つ PNG | 透明度も HTML の PNG と同じ | I3 |
| スウォッチで塗る文字と罫線 | `cmykToRgb` の sRGB | I4 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。
0431 の A1 は、上のとおり狭めて手で確かめる。

## テスト設計

root ADR 0445 I1 から I4 を名前の先頭に置いたテストを、0431 の実装と同じプルリクエストで `golem-driver-pdf-test` に足す。
I1 は、同じ本を `--target pdf --target pdf-screen` で組み、図版の Form XObject からたどれるオブジェクトを、オブジェクトの番号を参照の先で置き換えて比べる。
I2 と I3 は、同じ本を `--target html --target pdf-screen` で組み、HTML の SVG の色と PNG の画素を、PDF の色と画像の画素と比べる。

## トレードオフ

PDF の図版の置き換えた色だけが、閲覧ソフトの CMYK の変換に任され、同じページのスウォッチの文字や罫線と少し違って見えることがある。
その代わりに、透明を混ぜた色が `pdf` と同じに保たれ、新しい色の変換の仕組みを作らずに済む。

PDF の図版を sRGB で塗り直す仕組みを作れば色はそろうが、色空間の書き方と透明のグループの扱いを決め直す必要があり、調査した事項のとおり、混ぜた色が `pdf` と変わる。

## 参考文献

- [root ADR 0408](0408-preserve-rgb-and-distinguish-explicit-figure-recoloring.md)
- [root ADR 0431](0431-plain-pdf-1-7-target.md)
