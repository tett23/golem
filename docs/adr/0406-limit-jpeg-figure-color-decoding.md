# ADR 0406: JPEG 図版の色変換で復号する方式を定める

Status: accepted

## 文脈

[root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md) は、JPEG を含む図版の白黒の濃淡を指定色へ写す。
JPEG には複数の符号化方式があり、色変換のために復号する方式と、復号できない場合の扱いを補足する。

## 調査した事項

実装中の `Golem.Typeset.FigureColor.validateJpeg` は、フレームマーカー SOF0、SOF1、SOF2 と精度 8-bit を受け入れ、それ以外を拒む。
これらは Huffman 符号化の baseline、extended sequential、progressive の DCT 方式である。
同じモジュールの色変換は、復号した画素を調べてから、白黒の濃淡、一色、多色を区別する。
指示者は 2026-11-22 に、対応方式を限定し、非対応方式はエラーにする案を選んだ。

## 実装すること

図版の描画色を指定した JPEG の色変換は、8-bit の Huffman 符号化による baseline、extended sequential、progressive の DCT 方式を対象とする。
12-bit、lossless、arithmetic coding など、この範囲にない方式は G08113 のエラーにし、その図版を含む対象媒体の生成を中止する。
復号に失敗する壊れた JPEG も同じエラーにする。
生成を中止した媒体には、以前の出力を生成成功した成果物として残さない。

図版の描画色を指定しない場合は、従来どおり JPEG を扱う。
今回の色変換の復号方式の制限だけを理由に、従来埋め込めた JPEG を拒まない。
対応方式を復号した結果が多色なら、[root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md) に従って元の画素を保つ。
非対応方式は単色か多色かを判定できないため、元画像を黙って出力する代わりにエラーにする。
PDF、HTML、EPUB のすべてに同じ制限を適用する。

## 実装しないこと

非対応方式の JPEG デコーダーは追加しない。
外部コマンドやネットワークサービスへ画像を渡して変換しない。
PNG、SVG、取り込んだ PDF の規則は変えない。

## 不変条件

I1: 描画色を指定した非対応方式または復号不能な JPEG は、G08113 を出して対象媒体の生成を失敗させる。
I2: 描画色を指定しない JPEG の受け入れ範囲と出力は、この制限の追加前と一致する。
I3: 対応方式の JPEG の濃淡、多色、透明度と配置の扱いは [root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md) と一致する。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 色指定あり、8-bit baseline の白黒写真 | 指定色の濃淡 | I3 |
| 色指定あり、8-bit extended sequential または progressive | 復号し、画素に従って判定 | I3 |
| 色指定あり、12-bit または lossless | G08113、対象媒体を生成しない | I1 |
| 色指定あり、壊れた JPEG | G08113、対象媒体を生成しない | I1 |
| 色指定なし、従来埋め込めた非対応方式 | 従来と同じ出力 | I2 |
| 色指定あり、対応方式の色付き写真 | 元の画素を保持 | I3 |

## 受けいれ条件

A1: 通常 CLI の PDF、HTML、EPUB 出力で、対応方式の変換と非対応方式のエラーを確認する。

## テスト設計

root ADR 0406 I1、I2、I3 を先頭に置いた試験で、各対応方式、非対応の精度と方式、破損、色指定の有無を検査する。
エラーのコード、終了コードと、古い成果物が成功した出力として残らないことを検査する。
root ADR 0406 A1 の通常 CLI 試験では、実際の生成物の色と、失敗した媒体の出力先を照合する。

## トレードオフ

よく使われる 8-bit の DCT 方式を扱い、非対応方式を見落として異なる色の出力を渡すことを避ける。
色指定なしでは埋め込める JPEG でも、描画色を指定するとエラーになる場合がある。

## 参考文献

- [root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md)
- [JPEG の符号化方式](https://jpeg.org/jpeg/)
