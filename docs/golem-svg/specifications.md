# golem-svg 仕様書

golem-svg は、`@figure` の SVG の図版を、PDF に描ける形（パス、塗りと線、行列とクリップを持つグループ）に読むパッケージである（[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)）。
依存は `base`、`bytestring`、`containers`、`text` だけである。
読める範囲と、範囲の外を G0811 にすることは、[仕様書](../specifications.md) の図版の節に書く。
この文書には、図の大きさにかかわらず読み終えるための上限と、その判定の場所を書く。

## モジュール

- `Golem.Svg`：図を読む `readSvg`。要素、スタイル、図形、`marker` を扱う。
- `Golem.Svg.Active`：HTML と EPUB に写す SVG の動く中身を、文書の順に返す `activeContent`（[docs/adr/0039](../adr/0039-svg-active-content-in-html-and-epub.md)）。拒むものの表は [仕様書](../specifications.md) の図版の節に書く。`style` の要素と属性の CSS は、注釈を同じ長さの空白に置き換えてから（`Golem.Svg.Css` の `stripComments`）、`@import` と `url(` を探す。手間は文書の長さに比例する。
- `Golem.Svg.Xml`：SVG が使う XML の読み手。
- `Golem.Svg.Css`：`<style>` と `style` の属性の CSS の読み手。
- `Golem.Svg.Number`：数の読み手と、有理数の三角関数と平方根。
- `Golem.Svg.Colors`：色の名前の表。

## 数の上限

数の読み手（`Golem.Svg.Number` の `numberPrefix` と `parseNumber`）は、絶対値が 10^9（`numberLimit`）以下の数だけを返す（[docs/adr/0041](../adr/0041-svg-marker-and-number-limits.md)）。
数の形は、仮数が 60 桁まで、指数が 4 桁までである。
形を読んだ後に値を判定し、10^9 を超える数は読めない数とする。
判定は、仮数の整数と 10 の指数のまま行い、指数が 9 を超えれば 10 の累乗を計算せずに超えたとする。
`1e9999` のような数から大きな整数を作らないためである。

`tooLarge` は、値の文字列に 10^9 を超える数があるかを返す。
`Golem.Svg` は、範囲の外の値の名前を決めるときにこれを使い、超える数があれば名前に `（読めない数）` を添える。
色の値は `rgb()` の中の数だけを見る。
16 進数の色の数字を数として読まないためである。
`marker` の `markerWidth`、`markerHeight`、`refX`、`refY`、`viewBox`、`orient` は、読めなければ既定の値を使うが、10^9 を超える数があれば G0811 にする。
ルートの `width`、`height`、`viewBox` に 10^9 を超える数があれば、`rootGeometry` が `SvgMalformed "大きさの数が大きすぎます"`（G0810）を返す。

値を 10^9 に丸めることはしない。
計算は有理数のままで、浮動小数点数は使わない。

## `marker` の深さと循環

図が置く `marker` を 1 段目とし、`marker` の中身が置く `marker` を 1 段深いとする。
9 段（`markerDepthLimit`）まで描き、10 段目を置く参照と、循環の中の参照を G0811 にする（[docs/adr/0041](../adr/0041-svg-marker-and-number-limits.md)）。

判定は、描く前に `marker` の参照のグラフで行う（`markerEdges`）。

1. 要素を読む走査（`elementOps`）は、問題と描画のほかに、置く `marker` の id を返す。図の本体が置く `marker` と、各 `marker` の中身が置く `marker` から、グラフを作る。
2. 強連結成分が同じ二つの `marker` のあいだの参照（自分自身への参照を含む）を、循環の参照とする。
3. 図の本体から届く `marker` だけを数える。`marker` の深さは、循環の参照を除いて、図の本体からその `marker` に至る最も長い参照の列の長さである。
4. 図の本体から届く `marker` の中身にある参照のうち、循環の参照を `marker（循環）`、深さ 9 の `marker` からの参照を `marker（入れ子）` とする。

問題は、`marker` の中身を文書の中で読むときに、参照を持つ図形の位置で出す。
各 `marker` の中身は一度だけ読み、置くたびに読み直さない。
そのため、問題を集める手間は、`marker` を置く回数ではなく文書の大きさに比例する。
`marker` の描画も、`marker` ごとに一度だけ作り、置く場所で共有する。

ADR は、描いている `marker` の id の列を描く途中で持つ判定を書く。
グラフで判定するのは、問題を集める手間を、置く回数の指数ではなく文書の大きさに比例させるためである。
循環がなく深さが 9 以下の図では、どちらの判定も同じ結果になる。
循環があるときは、列で判定すれば循環を閉じる参照だけを出すが、グラフで判定すれば循環の中の参照をすべて出す。

## 読む手間

XML と CSS の読み手は、入力の長さに比例する手間で読む。

- 実体参照と文字参照は、置き換えた断片を集め、最後に一度だけつなぐ。
- 隣り合う文字列（コメントで分かれた文字列や CDATA）は、断片を集め、終わりのタグで一度だけつなぐ。
- CSS のコメントを空白に置き換えるときも、断片を集めて一度だけつなぐ。
- 属性の重なりは、読んだ名前の集合で調べる。

これらは 2026-10-18 のセキュリティの監査（[docs/audits/2026-10-18-security-audit.md](../audits/2026-10-18-security-audit.md)）の C9 と C10 の修正であり、仕様を変えない。
