# ADR 0439: SVG の図版のパスの描画の速さを、Emet が乱数で作る図形で測る

Status: superseded-pending [{"part":"実装の時期","by":[],"kind":"note","note":"メンテナーは 2026-11-25 に、IR と ABI の検査をすべての実装の後に行うと決め、この ADR を先に実装してよいとした。"}]

## 文脈

図形の多い本（図解、ジェネラティブアート、地図）では、PDF にパスを書き出す速さが、組む時間の大きな部分になりうる。
今の Golem には、パスの書き出しの速さを測る仕組みが無い。

ロードマップの「パスの描画のベンチマーク」は、乱数で多数の図形を作るジェネラティブアートを入力にし、図形を作るコードを Emet で書き、乱数のシード値を `manifest.toml` から取ると書いている。
ところが、今の Emet は図版を作れない。
この ADR は、Emet が作った図形を Golem に渡す形、測り方、記録の置き場所、予算の決め方を決める。

測るのは、SVG の図版を PDF に描く経路（golem-svg の読み取りと golem-pdf の `Drawing.hs`）である。
[root ADR 0437](0437-paths-and-the-box-model.md) のレイアウトエンジンのパス（テキストフレームの形）は、この経路を通らないので、このベンチマークでは測らない。

## 調査した事項

origin/main（[9efdc4f89](https://github.com/tett23/golem/commit/9efdc4f89b3fec75abcd37c11abb3e1d909c6725)）で、次のことを確かめた。

- Emet の関数は意味論の IR（`Inline` と `Block`）を返す。
  `.gm` のブロックのコマンドが図版（`FigureBlock`）を返すと、「ブロックコマンドが返せないブロックです: 図版」として拒む（[Gm.hs#L170](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-emet/src/Golem/Emet/Gm.hs#L170)）。
  フィルタが新しく作った図版も拒む（[Gm.hs#L207](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-emet/src/Golem/Emet/Gm.hs#L207)）。
  コードはどちらも E06104 である。
- メモリの上の画像を図版にする経路は、プラグインのブロックのコマンドの出力だけである（[root ADR 0123](0123-figures-from-plugins.md)）。
  プラグインは、図版と画像のバイト列を同じ応答で返し、図版の `src` に `plugin:<名前>` を書いて画像を指す。
  ホストは、`src` を `golem-plugin-image://<SHA-256 の 16 進>.<拡張子>` に置き換え、同じバイト列の画像を一つにする。
  評価は、その図版を `@figure` と同じ段の検査（`checkFigure`）に、呼び出しの位置で通す。
  どの図版からも指されない画像は、不正な出力（G06009）である。
  この名前は `://` を含むので、原稿の `@figure` に書くと URL（G02060）になる。
- Emet の数は、自然数、整数、有理数で、浮動小数と三角関数は無い。
  整数の割り算 `div` と剰余 `%` がある。
  乱数の関数は無い。
  評価の手数は 1 億、深さは 1 万が上限である。
  `++` は作った値の長さも手数に足し、`String.join` は文字列を線形につなぐ。
- `manifest.toml` の `[vars]` の整数は、原稿の式から `vars.x` で読める（[root ADR 0185](0185-project-wide-variables.md)）。
  Emet の関数は `[vars]` をじかに読まず、引数として受け取る。
- SVG の図版は、パス（直線、三次のベジェ曲線、閉じ）と sRGB の色を、PDF に描く（[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)）。
  SVG の図版の数は、`Drawing.hs` の `fixed`（1/65536 に丸めた数）で書く（[Drawing.hs#L67-L69](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-pdf/src/Golem/Pdf/Drawing.hs#L67-L69)）。
  ここがパスの書き出しの費用の大きな部分かは、測っていない。
- `docs/benchmarks/` は、日付の付いた計測の記録を置き、コミットした後は変えない。
- [root ADR 0181](0181-footnote-heavy-layout-time.md) は、コミットごとに `cabal build exe:golem --disable-tests` で作った実行ファイルで、一冊ごとに `build/` を消してから 5 回組み、壁時計の時間の中央値を取った。
  CI のランナーの時間のばらつきが大きいので、組む時間を CI で検査しないと決めた。
- 予算は、ADR に値を書き、`docs/budgets.md` に写す。
- 手で動かすスクリプトのテストは `scripts/test.sh` に置く（[root ADR 0078](0078-tests-for-release-and-hand-run-scripts.md)）。
- ロードマップは、記法、IR、ABI を変える項目を、「IR と ABI の設計と妥当性の検査」の後に扱うと決めている。

指示者は 2026-11-23 に、この項目の ADR を書くよう求めた。

## 実装すること

### Emet のブロックのコマンドが返す図版

`.gm` のブロックのコマンドが、図版を返せるようにする。
図版の `src` には、`data:image/svg+xml,` に続けて SVG の文字列をそのまま書く。
評価は、その文字列の後ろの部分を UTF-8 のバイト列にし、プラグインの画像と同じ表に入れ、`src` を `golem-plugin-image://<SHA-256 の 16 進>.svg` に置き換える。
その後の扱い（`checkFigure` の検査、PDF への描画、HTML と EPUB への書き出し、プレーンテキストでの扱い）は、0123 のプラグインの図版と同じとする。

画像のバイト列が図版の値の中にあるので、Emet の関数は純粋なままで、どの図版からも指されない画像は生じない。
Emet に新しい組み込みの関数と型は足さない。

次の図版は、今までどおり E06104 で拒む。

- `src` が `data:image/svg+xml,` で始まらない図版（プロジェクトのファイルを指す図版は、`@figure` で書く）
- `web` のある図版
- フィルタが新しく作った図版
- 出力の最上位でない図版（箇条書きと定義リストの中）

原稿の `@figure` に `data:` の `src` を書いたときは、今までどおり URL（G02060）にする。
`data:` の `src` を画像に変えるのは、ブロックのコマンドの出力だけである。

### 実装の時期

ブロックのコマンドが図版を返せるようにすることは、`.gm` の関数が返せるものを変えるので、記法の変更に当たる。
そのため、この ADR の実装は、ロードマップの「IR と ABI の設計と妥当性の検査」の後に行う。

### 乱数とシード

乱数は、ベンチマークの Emet のファイルの中で、線形合同法を `%` と掛け算と足し算で書いて作る。
Golem に乱数の組み込みの関数は足さない。
シード値は `manifest.toml` の `[vars]` の整数 `seed` とし、原稿から `vars.seed` をブロックのコマンドに渡す。
同じ `seed` からは、同じ図形の並びと、同じ PDF ができる。

### ベンチマークの本

ベンチマークの本を `scripts/bench/path-drawing/` に置く。
本は、1 ページに図形を 1,000 個描く図版を、10 ページ持つ（図形の数の合計 10,000）。
図形は、直線の多角形と三次のベジェ曲線の閉じた形を半々とし、塗りと線を持つ。
SVG の文字列は、図形ごとの文字列のリストを `String.join` でつないで作る。
`++` で累積の文字列に足していくと、手数が図形の数の二乗に比例し、上限に近づくためである。

### 測り方

`scripts/bench/path-drawing/measure.sh` は、次のように測る。

1. `cabal build exe:golem --disable-tests` で今のコミットの実行ファイルを作り、`cabal list-bin exe:golem` で場所を得る。
2. `scripts/bench/path-drawing/` で、毎回 `build/` を消してから `golem build --target pdf` を 5 回走らせる。
3. 壁時計の時間の中央値をミリ秒で、標準出力の最後の行に出す。

[root ADR 0181](0181-footnote-heavy-layout-time.md) と同じ方法である。

### 記録と予算

実装のプルリクエストで `measure.sh` を走らせ、最初の記録を `docs/benchmarks/<日付>-path-drawing.md` に置く。
記録は、マシン、コミット、方法、5 回の時間と中央値、図形の数を持つ。

予算の値は、この ADR では決めない。
最初の記録を見てから、値と比べるマシンを、別の ADR で決め、`docs/budgets.md` に写す。
予算は CI で検査しない。
0181 のとおり、CI のランナーの時間のばらつきが大きいためである。

### 文書

仕様書の Emet の関数の出力の節と、プラグインの図版の節に、ブロックのコマンドの図版と `data:` の `src` の扱いを書く。
`docs/diagnostics.md` の E06104 の説明の「関数とフィルタが作った図版」を、この ADR の決まりに合わせて直す。
ロードマップの「パスの描画のベンチマーク」の項目を消す。

### ステータスの行

採択したら、[root ADR 0123](0123-figures-from-plugins.md) のステータスに、Emet のブロックのコマンドもメモリの上の画像の図版を返せるようにしたことを、この ADR が補ったと記録する。

## 実装しないこと

意味論の IR とプラグインの ABI を変えない。
Emet に浮動小数、三角関数、乱数、画像の組み込みの関数と型を足さない。
SVG のほかの形式（PNG、JPEG）の `data:` の `src` は受け付けない。
Emet の関数（ブロックのコマンドでないもの）とフィルタが図版を作ることは認めない。
CI でパスの書き出しの時間を検査しない。
パスの書き出しを速くする変更は、この ADR では行わない。
測った結果を見て、別の ADR で決める。

## 不変条件

- I1: 同じ `seed` で二回組んだ PDF は、バイト列まで等しい。
- I2: `seed = 1` と `seed = 2` の PDF のバイト列は異なる。
- I3: ブロックのコマンドが `data:image/svg+xml,` の `src` で返した図版の描画のストリーム（`drawingContent` の出力）は、同じ SVG をファイルとして置いた `@figure` の描画のストリームと等しい。
- I4: 同じ SVG の文字列の `src` を持つ二つの図版は、同じ画像の名前を指し、画像は一つになる。
- I5: `measure.sh` は、標準出力の最後の行に、一つの整数（ミリ秒）を出す。
- I6: ブロックのコマンドが返した `data:` の図版の HTML と EPUB の出力は、同じ SVG をプラグインが返したときと同じ名前の画像のファイルと、それを指す `<img>` を持つ。
- I7: 実装することの節で拒むと書いた図版と、原稿の `@figure` の `data:` の `src` は、今までどおりのコード（E06104、G02060）になる。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `seed = 1` で二回組む | 同じバイト列 | I1 |
| `seed = 1` と `seed = 2` | 違うバイト列 | I2 |
| 三角形一つの `data:` の図版と、同じ内容のファイルの `@figure` | 同じ描画のストリーム | I3 |
| 空の SVG（図形なし）の `data:` の図版 | ファイルの空の SVG と同じ | I3 |
| [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) の範囲の外の要素を持つ `data:` の図版 | ファイルの SVG と同じ diagnostic | I3 |
| 同じ文字列の `data:` の図版を二つ返す | 同じ名前で、画像は一つ | I4 |
| `data:` の図版の HTML の出力 | プラグインの画像と同じ名前のファイルと `<img>` | I6 |
| ブロックのコマンドが `images/a.svg` の `src` の図版を返す | E06104 | I7 |
| ブロックのコマンドが `data:image/png,` の図版を返す | E06104 | I7 |
| フィルタが `data:` の図版を作る | E06104 | I7 |
| 箇条書きの中の `data:` の図版 | E06104 | I7 |
| 原稿の `@figure` の `data:image/svg+xml,...` | G02060 | I7 |
| `measure.sh` | 最後の行が一つの整数 | I5 |

## 受けいれ条件

A1: 実装のプルリクエストで `measure.sh` を走らせ、最初の記録を `docs/benchmarks/` に置く。

## テスト設計

root ADR 0439 I1 から I4、I6、I7 を名前の先頭に置いたテストを、golem-emet と golem-driver に足す。
I1 と I2 は、図形の数を減らした小さなベンチマークの本で確かめる。
I3 は、境界の表の SVG の組で、二つの図版の描画のストリームを比べる。
I6 は、HTML と EPUB の出力の画像のファイルの名前と `<img>` の `src` を調べる。
I7 は、境界の表の各行の diagnostic のコードを調べる。
I3、I4、I6、I7 は、実装の前に落ちることを確かめる。
I5 は、`scripts/test.sh` で、`measure.sh` の出力の形を、`golem` の代わりの短いスクリプトで確かめる。
root ADR 0439 A1 は、実装のプルリクエストの記録で確かめる。

## トレードオフ

図形を SVG の文字列として渡すので、Emet で SVG を組み立てる費用と、Golem が SVG を読む費用も、測る時間に入る。
パスを書き出す時間だけを分けて測ることはできない。
その代わりに、利用者が実際に使う経路（Emet で図を作り、図版として描く）の速さを測れる。

SVG の文字列を図版の値の中に持つので、大きな図版では評価の値が大きくなる。
その代わりに、Emet に副作用のある関数も新しい型も足さずに済む。

記法の変更に当たるので、実装は IR と ABI の設計の後まで待つ。

CI で検査しないので、遅くなったことに気付くのは、手元で測ったときになる。

## 参考文献

- [root ADR 0078](0078-tests-for-release-and-hand-run-scripts.md)
- [root ADR 0123](0123-figures-from-plugins.md)
- [root ADR 0181](0181-footnote-heavy-layout-time.md)
- [root ADR 0185](0185-project-wide-variables.md)
- [root ADR 0437](0437-paths-and-the-box-model.md)
- [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)
