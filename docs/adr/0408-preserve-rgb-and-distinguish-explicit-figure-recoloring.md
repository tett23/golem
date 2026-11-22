# ADR 0408: RGB を自動で CMYK 化しない原則と図版の色置換を区別する

Status: proposed

## 文脈

画像と図版の RGB を CMYK に変換しない規則は、仕様の「色」と golem-pdf の ADR にある。
設計原則の節には、この規則を明記していない。
一方、[root ADR 0386](0386-page-list-and-page-colors.md) と [root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md) は、書き手が指定した色で単色図版を描く。
元の色の見た目を保つための色空間変換と、指定色への意図した置換を区別する。

## 調査した事項

仕様の「色」は、色を変換する向きを CMYK から RGB に限り、画像の印刷色への変換は印刷所の RIP に任せると定める。
[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) も、RGB から CMYK の方向に変換しないと定める。
[golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md) は、画像の ICC プロファイルを保持し、プロファイルのない RGB には sRGB を付ける。

実装中の図版の色指定には、白黒の濃淡か一色と判定した RGB の画像と描画を、選択したスウォッチの CMYK で描き直す経路がある。
この経路は元の RGB の色に近い CMYK を計算せず、スウォッチの成分と元画像の濃淡を使う。
図版の色指定がない場合、この経路は呼ばれない。
HTML と EPUB では、指定した CMYK スウォッチから RGB の近似色を求める。

## 実装すること

仕様の設計原則に「入力の色を自動で印刷色へ変換しない」を加え、次を記す。

Golem は、RGB の入力の見た目を保つ目的で、その入力を CMYK に自動変換しない。
PDF の出力インテントが CMYK であることだけを理由に、RGB の画像や図版を CMYK 化しない。
ICC プロファイルの付与と保持は色空間変換と区別し、入力に CMYK の値を推測して補わない。
HTML と EPUB などの画面表示では、従来どおり CMYK のスウォッチから RGB の近似色を求める。

書き手が `[figures].color` を指定した単色図版の色置換は、元の見た目を保つための色空間変換とは区別する。
この場合だけ、root [ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md) の規則で、元の一色または濃淡を、明示したスウォッチへ置き換える。
RGB に保存した白黒図版も対象とし、PDF では指定された CMYK スウォッチの濃淡で描く。
多色の図版と、色を指定していない図版に、この置換を適用しない。
HTML と EPUB の近似色は、元の RGB を CMYK に近似変換した結果ではなく、指定した CMYK スウォッチから求める。

README と仕様の「色」にも、この違いを明記する。
元の色を保つ規則と、図版の明示的な色置換の関係を、関連する golem-pdf ADR のステータスの補足リンクで記録する。

## 実装しないこと

RGB の見た目に対応する CMYK を推定する式や、ICC の色変換エンジンは追加しない。
RGB の写真を、印刷用 PDF であることだけを理由に CMYK 化しない。
図版の色置換ができる形式と機能の範囲は広げない。

## 不変条件

I1: 図版の色指定がない場合、RGB の画像と図版は、CMYK の出力インテントだけを理由に CMYK に置き換わらない。
I2: 明示した図版色の PDF の出力成分は、選択スウォッチと [root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md) の濃淡の規則で決まり、元の RGB に近い CMYK を推定しない。
I3: 色を指定した場合も、多色の図版の元の色を保つ。
I4: HTML と EPUB の置換後の色は、指定 CMYK と濃淡から求めた RGB の近似色と一致する。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 色指定なし、RGB の写真、CMYK 出力インテント | RGB のまま | I1 |
| 色指定なし、RGB の SVG または PDF 図版 | RGB のまま | I1 |
| 色指定あり、RGB に保存した灰色の図 | 指定 CMYK スウォッチの濃淡 | I2 |
| 色指定あり、一色の赤または青の図 | どちらも指定スウォッチの色 | I2 |
| 色指定あり、多色の RGB 写真 | 元の色 | I3 |
| HTML と EPUB の色指定 | CMYK スウォッチから求めた RGB | I4 |

## 受けいれ条件

A1: PNG、JPEG、SVG、取り込んだ PDF の通常 CLI 出力で、色指定の有無による色空間と成分を照合する。
A2: 設計原則、仕様の「色」、README と補足リンクが同じ境界を示す。

## テスト設計

root ADR 0408 I1、I2、I3、I4 の試験で、RGB の写真、一色の赤と青、白黒の濃淡、指定色の有無と各出力を検査する。
画像の成分、描画命令の色空間、ICC プロファイルと、多色画像の保持を照合する。
root ADR 0408 A1 は通常 CLI で確かめ、A2 は文書を精読して確かめる。

## トレードオフ

印刷色の自動変換を禁止しつつ、書き手が選んだ色への図版の置換は使える。
RGB で保存した一色の図も明示的な色指定によって CMYK になるので、その違いを「変換しない」という一文だけで説明できない。

## 参考文献

- [root ADR 0386](0386-page-list-and-page-colors.md)
- [root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md)
- [golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)
- [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)
- [仕様の「色」](../specifications.md#色)
