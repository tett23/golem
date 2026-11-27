# ADR 0474: 色の計算を独立モジュールへ集め、固定の高速な近似を使う

Status: accepted-pending

## 文脈

[root ADR 0408](0408-preserve-rgb-and-distinguish-explicit-figure-recoloring.md) は RGB の見た目を保つための自動 CMYK 変換を禁じるが、明示的な図版の色置換は許している。
色の計算は出力側と図版の層に分散しており、CMYK から RGB への式にはコピーがある。
メンテナーは、CMYK からグレースケールへの計算も含めて、色の計算を独立したモジュールへ集めることを求めた。

2026-11-27 に、メンテナーは RGB から CMYK への近似も v1.x に先送りせず、高速な近似を一つだけ本体に持つ方針へ改めた。
電子書籍の表示色はデバイスに依存し、近似で足りる用途もあるため、固定の簡単な近似を許容する。
厳密な色管理は外部で行い、Golem がひと段落した後に別のライブラリとして作ることも検討する。

## 調査した事項

origin/main の [4121ea73d](https://github.com/tett23/golem/commit/4121ea73d4466eaf47353e4b84d22f08327aed1e) で、次のことを確かめた。

- `modules/` に `golem-color` パッケージは無い。
- [Golem.Html の cmykToRgb](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-html/src/Golem/Html.hs#L369-L373) と [Golem.Pdf.Writer の cmykToRgb](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L113-L121) は、同じ有理数の式を持つ。
  PDF 側のコメントは、HTML への依存を避けるためのコピーだと説明する。
- [PdfScreenSpec](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-driver/test/PdfScreenSpec.hs#L201-L206) は、両方の実装を複数の成分値で比較する。
- 同じ式を持つ [root ADR 0468](0468-paragraph-styles-for-headings-and-lists.md) のビルド済みテストに `--pattern='/colours:/'` を渡すと、27 件が成功した。
  [XhtmlSpec](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-html/test/XhtmlSpec.hs#L575-L584) の、無色が `(255,255,255)`、黒版が全部なら `(0,0,0)`、CMYK の百分率 `(20,40,60,10)` が `(184,138,92)` になるテストを含む。
- [FigureColor](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-typeset/src/Golem/Typeset/FigureColor.hs#L138-L166) は、判定した一色か灰色の画像を、引数で受けた CMYK スウォッチの濃淡へ置き換える。
  多色と描画する画素の無い画像は、置き換えない。
- 同じモジュールの [rgbTone と rgbComponents](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-typeset/src/Golem/Typeset/FigureColor.hs#L202-L211) は、スウォッチの CMYK に濃淡を掛けた後、途中で丸めずに画面色を求める。
- [PdfColor の inkValues](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-typeset/src/Golem/Typeset/PdfColor.hs#L1831-L1840) は、元の色の分類と濃淡から、指定スウォッチのインク量を計算する。
  元の RGB に近い CMYK を求める関数ではない。
- [Writer の画像の埋め込み](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L1294-L1301) は色を変換しないと記し、プロファイルの無い RGB には sRGB を付ける。

- [FigureColor.grayValue](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-typeset/src/Golem/Typeset/FigureColor.hs#L195-L200) と `PdfColor.inkValues` は、中性の CMYK の明るさを `(1-C)*(1-K)` で求める。
  任意の有彩色を重み付きでグレースケールにする処理ではない。
- [PdfDct](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-typeset/src/Golem/Typeset/PdfDct.hs#L88-L91) は JPEG の YCbCr を RGB に復号し、YCCK は K を保持して CMYK の成分を復元する。
  この経路では `JuicyPixels` の変換と、成分を反転するローカルな計算を使う。

[CSS Color 5 の 2026-11-16 Working Draft の 6.1 節](https://www.w3.org/TR/2026/WD-css-color-5-20261116/#cmyk-rgb) は、非較正 CMYK と sRGB の双方向の近似式を示す。
同文書は、インクや RGB 空間の測色値、ドットゲインを扱わない近似であると説明する。
これは調査した近似式の出典であり、Golem の印刷色の一致を保証する規格ではない。

## 実装すること

### 共通の下位モジュール

`modules/golem-color/` に独立した Cabal パッケージ `golem-color` を置き、名前空間を `Golem.Color` とする。
実行時依存は `base` に限り、ほかの Golem モジュール、ファイル、ICC の色変換エンジンに依存しない純粋な計算にする。
`docs/golem-color/adr/` とモジュールの仕様書も置く。

RGB、CMYK、グレースケールと符号化用の成分は、それぞれ別の型で区別する。
百分率、0 から 1 の比率、8-bit と 16-bit の整数成分を混同しない API にする。
成分の範囲外の入力は型の構築時に拒否し、変換の途中で暗黙に丸め込まない。
濃淡を掛けた成分を整数の百分率へ戻したり、16-bit の出力の前に 8-bit に丸めたりしない。

色空間変換、濃淡の抽出と適用、成分の量子化の計算を共通モジュールへ集める。
CMYK から RGB、中性の CMYK からグレースケール、灰色からインク量への計算も対象にする。
既存の外部 codec が行う色成分の変換も呼出箇所を洗い出し、成分間の計算とその検査を共通モジュールへ移す。
圧縮データの復号と再符号化そのものは codec の層に残す。

### RGB から CMYK への固定の近似

RGB から CMYK へは、上記の CSS Color 5 の近似式一つだけを使う。
RGB 成分 `r, g, b` と CMYK 成分 `c, m, y, k` は、0 から 1 の値とする。
入力の符号化済みの RGB 成分をそのまま使い、ガンマの解除や ICC による色空間の変換はしない。

```text
v = max(r, g, b)
k = 1 - v
v = 0 のとき: c = m = y = 0
v > 0 のとき: c = (v-r)/v, m = (v-g)/v, y = (v-b)/v
```

黒は `(0,0,0,1)`、白は `(0,0,0,0)` になる。
透明度は変換せず、元の値を保つ。
この式は RGB の三成分を単純に分版する近似であり、印刷条件に応じた色の一致や総インク量の制限を保証しない。
成分数が三つでも、Lab などの RGB ではない空間には適用しない。
RGB の ICC がある場合も、この関数はそのプロファイルを解釈せず、RGB の符号化成分に同じ近似を適用する。
元の RGB の ICC を、変換後の CMYK のプロファイルとして付けない。

8-bit と 16-bit の画素では、画素ごとの有理数の構築を避けた整数の実装を用意する。
最大成分値を `M`、入力の整数成分を `R,G,B`、`V=max(R,G,B)` とする。
`K=M-V` とし、`V=0` なら `C=0,Mg=0,Y=0`、それ以外は `C=roundEven(M*(V-R)/V)` とする。
`Mg` と `Y` もそれぞれ `G` と `B` に同じ式を使い、`Mg` はマゼンタの出力を指す。
`roundEven` は最も近い整数へ丸め、同距離なら偶数を選ぶ。
8-bit の `M` は 255、16-bit の `M` は 65535 とし、積と丸めの計算には少なくとも 64-bit の符号なし整数を使ってオーバーフローを防ぐ。
この整数の実装は別の近似式ではなく、有理数の式を末端で丸めた結果と同じものとする。

CMYK から RGB への既存の `(1-c)*(1-k)` などの式は保つ。
新しい RGB から CMYK への近似と、既存の CMYK から RGB への近似は、整数へ丸める前なら RGB の成分を往復して同じ値にする。
この性質は実際の印刷物と画面の色の一致を意味せず、元の CMYK の分版の復元も保証しない。

### 集める計算と残す処理

| 処理 | 置く場所 |
| --- | --- |
| RGB から CMYK への固定の近似、CMYK から RGB への既存の近似 | `golem-color` |
| 中性の CMYK からグレースケール、灰色とインク量の換算、スウォッチへの濃淡の適用 | `golem-color` |
| 色成分の 8-bit と 16-bit への量子化 | `golem-color` |
| JPEG の YCbCr と YCCK などの成分間の計算 | `golem-color` |
| 色指定とスウォッチ名の解決 | プロジェクトとドライバーの既存の層 |
| 画素や描画命令の走査、一色か多色かの集約 | 図版を扱う既存の層。色の数値の計算は共通 API を使う |
| 圧縮と展開、PDF と SVG の構文解析、描画命令や CSS の生成 | 各形式の既存の層 |
| ICC の付与と保持、透明度と配置、PDF の数値の文字列化 | 各形式の既存の層 |

移動前に、色を扱うモジュールと codec の呼出箇所を列挙し、計算、走査、符号化のどれに当たるかを実装 PR に記録する。
色の計算は移動先と回帰テストを示し、一部だけを移して完了にはしない。
既存に無い任意の有彩色からグレースケールへの式は、この変更では追加しない。

HTML と PDF に重複する式、および図版側の同じ計算を共通実装への呼び出しに置き換える。
既存の `Golem.Html.cmykToRgb` と `Golem.Pdf.Writer.cmykToRgb` は、従来の型と結果を保つ委譲関数として残す。
下位モジュールから出力モジュールへは依存させず、HTML と PDF の相互依存も作らない。

### 変換の呼出しと図版の色置換

共通モジュールは、変換の向きが型で分かる RGB から CMYK への関数を v1.0.0 から公開する。
呼出側が CMYK を必要としてこの関数を選んだ場合にだけ、固定の近似を適用する。
この変更で新しい CLI オプションや図版の一括変換の設定は加えない。
出力インテントが CMYK であることや PDF/X-4 の指定だけを理由に、RGB の図版を一括して変換しない。
色指定の無い図版は、元の成分、ICC とストリームの保持の既存の規則を保つ。

明示的な CMYK スウォッチへの図版の色置換は、[root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md) と [root ADR 0408](0408-preserve-rgb-and-distinguish-explicit-figure-recoloring.md) の既存の規則を保つ。
一色の RGB と RGB で保存した白黒の濃淡も対象にし、多色の図版は既存の規則に従って保持する。
色置換は選択したスウォッチと元図版の濃淡から求め、元の RGB を近似した CMYK と取り違えない。
RGB 図版に CMYK スウォッチを指定したことだけを理由にする、新しいエラーは導入しない。
変換できない図版や破損への G08113 と、古い成果物を残さない既存の規則は保つ。

### 文書と採択済み ADR との関係

README、設計原則、仕様書、モジュールの仕様書、マニュアルに、固定の式、成分の範囲、黒の分岐、丸め方、透明度、適用条件と限界を書く。
RGB の ICC を解釈した色管理ではないことと、プロファイルの無い RGB に sRGB を付ける処理との違いも説明する。
厳密に色を管理したい場合は、Golem の外で変換した CMYK データを入力してもらう。
式や係数、色変換用プロファイルを選ぶ機能は設けない。
別の色管理ライブラリは Golem がひと段落した後の検討事項とし、この ADR の実装範囲と依存には加えない。

[root ADR 0408](0408-preserve-rgb-and-distinguish-explicit-figure-recoloring.md) と [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) の変換方向の制限は、固定の近似を共通モジュールに認める範囲で改める。
図版を出力インテントだけで自動変換しない規則と、既存の明示的なスウォッチへの置換の規則は保つ。
[root ADR 0431](0431-plain-pdf-1-7-target.md) の式のコピーは共通実装への委譲に改める。
これらの変更はステータスのリンクで記録し、コミット済み ADR の本文は変えない。
ロードマップの v1.x の自動変換の項目は、この ADR の v1.0.0 向けの未実装項目へ移す。

## 実装しないこと

ICC による色管理、印刷条件に応じた分版、近似式や係数の選択機能、図版を一律に CMYK にする新しい設定は追加しない。
対応する図版形式は広げず、色指定の無い図版をこの変更だけを理由に復号して再符号化しない。

## 不変条件

- I1: RGB から CMYK への計算は固定の式一つで決まり、黒の分岐でゼロ除算せず、成分は範囲内にあり、透明度を保つ。
- I2: 8-bit と 16-bit の整数の実装は、有理数の式を末端で偶数丸めした値と一致する。
- I3: 色指定の無い図版は、出力インテントによらず元の色成分と既存の ICC の扱いを保つ。
- I4: 既存の色空間変換、図版の色置換、濃淡、量子化、透明度の結果は変わらない。
- I5: 色成分間の計算と濃淡の計算は共通モジュールにあり、出力層に式を重複させない。
- I6: 共通モジュールは `base` だけに依存し、Golem の出力側へ依存しない。
- I7: RGB から CMYK への近似を既存の逆向きの式で戻すと、量子化前の RGB は元の値に一致する。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| RGB の黒 `(0,0,0)` と白 `(1,1,1)` | CMYK `(0,0,0,1)` と `(0,0,0,0)` | I1, I7 |
| RGB の赤、緑、青 | CMYK `(0,1,1,0)`、`(1,0,1,0)`、`(1,1,0,0)` | I1, I7 |
| RGB `(1/5,2/5,3/5)` | CMYK `(2/3,1/3,0,2/5)` | I1, I7 |
| RGB の灰色 `(1/2,1/2,1/2)` | CMYK `(0,0,0,1/2)` | I1, I7 |
| 8-bit の RGB `(51,102,153)` | CMYK `(170,85,0,102)` | I1, I2 |
| 16-bit の RGB `(13107,26214,39321)` | CMYK `(43690,21845,0,26214)` | I1, I2 |
| 透明度が 0 と 1、および中間値 | 色成分の変換によらず透明度を保持 | I1 |
| 成分が 0 未満、または 1 を超える入力 | 型の構築で拒否 | I1 |
| CMYK の百分率 `(20,40,60,10)` | 既存の RGB `(184,138,92)` | I4, I5 |
| 中性の CMYK `(1/2,1/2,1/2,1/4)` | 既存の灰色の明るさ `3/8` | I4, I5 |
| RGB の図版、色指定なし、CMYK 出力インテント | 元の RGB を保持 | I3 |
| RGB の一色と白黒の濃淡に CMYK スウォッチを指定 | 既存の色置換の結果。専用のエラーなし | I4 |
| YCbCr と YCCK の JPEG の復号 | 移動前と同じ成分と K | I4, I5 |
| 出力側への逆向きの依存を追加した検査用入力 | 依存の検査が失敗 | I6 |

## 受けいれ条件

- A1: 通常 CLI で PNG、JPEG、SVG、PDF の、色指定の有無と灰色、一色、多色を、印刷用 PDF、画面用 PDF、HTML、EPUB で検査し、既存の図版の成分、ICC と透明度を保つ。
- A2: 固定したフォントとスタンプで視覚的な回帰テストを実行し、既存の色と透明度が変わらないことを描画の差分も含めて確かめる。
- A3: 移動前に列挙したすべての色の計算に、共通モジュールの移動先と回帰テストがある。
- A4: 仕様書とマニュアルに、採用した式一つと、その範囲、丸め、適用条件と限界が記載されている。

## テスト設計

テスト名を `root ADR 0474 I<n>: ` で始める。
まず共通 API、RGB から CMYK への固定の近似、委譲を確かめるテストを書き、未実装で失敗することを確かめる。
既存の式の端点、中間値、丸めの境界、8-bit と 16-bit、codec の固定小数点の端数を、移動前と比較する。
HTML と PDF の旧公開関数も、共通 API と同じ結果になることを検査する。

有理数の参照実装と整数の実装を比較し、黒の特別な分岐、ゼロに近い成分、最大成分が同じ場合、整数の丸めが同距離になる場合を含める。
8-bit は全 RGB 組み合わせを専用の照合用実行で検査し、通常の単体テストには境界と代表値を残す。
16-bit は端点、端点の隣、丸めの境界、固定シードの入力列で検査し、64-bit の積が範囲内にあることも確かめる。
この照合のためにテスト時間の予算を引き上げない。

RGB の保持は対象図版のオブジェクトで調べ、同じ出力の CMYK スウォッチや出力インテントの有無と混同しない。
A1 は通常 CLI、A2 は固定した描画ツール、A3 は実装 PR の一覧とコードの照合、A4 は文書の精読で確かめる。

## トレードオフ

共通パッケージと依存の辺が増え、codec の色成分の計算まで移す必要がある。
その代わり、色の計算を一か所で見直し、式を重複させずに使える。
固定の式は少数の比較、減算、乗算と除算で計算できるが、印刷条件に応じた色の再現は保証しない。
近似で足りる用途を本体で扱い、厳密な色管理を本体に抱え込まない。

## 参考文献

- [CSS Color 5 Working Draft, 2026-11-16, 6.1](https://www.w3.org/TR/2026/WD-css-color-5-20261116/#cmyk-rgb)
- [root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md)
- [root ADR 0408](0408-preserve-rgb-and-distinguish-explicit-figure-recoloring.md)
- [root ADR 0431](0431-plain-pdf-1-7-target.md)
- [golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)
- [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)
