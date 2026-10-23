# ADR 0063: 内部の型の show をやめ、人が検算できる形でゴールデンを書く

ステータス: 破棄

## 文脈

ゴールデンのテストは、期待値のファイルを人が読んで正しいと判断できるときにだけ、仕様に対する検査になる。
読めないファイルを `--accept` で書き換えると、間違った出力がそのまま新しい期待値になる。
2026-10-23 のテストの品質の点検で、次の三つのゴールデンがこの状態にあることを確かめた。

- [golem-svg のテストの rotate-arc のゴールデン](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/Main.hs#L254-L256) は、`show (svgDrawing ...)` を [modules/golem-svg/test/golden/rotate-arc.txt](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/golden/rotate-arc.txt) に固定する。中身は `DGroup (Matrix (476102500705 % 549755813888) ...` のような Rational の分子と分母の羅列である。回転の角度や円弧の端点を、このファイルから検算できない。構成子やレコードの名前を変えるだけでも差分が出る。
- [golem-lsp のテストのセッションの結果](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs#L479-L488) は、`show` した lsp-types の値（`Range {_start = Position {_line = 3, ...}}`）を [modules/golem-lsp/test/golden/protocol.txt](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/golden/protocol.txt) と [protocol-utf8.txt](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/golden/protocol-utf8.txt) に固定する。lsp-types の Show のインスタンスは依存の版で変わりうる（[golem-lsp.cabal](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/golem-lsp.cabal#L38) は `>=2.3 && <2.5`）。版を上げると、プロトコルの振る舞いが同じでもゴールデンを全部書き直すことになる。
- [golem-font のテストの `render` と `goldenShape`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-font/test/Main.hs#L42-L46) は、整形の結果を `グリフ ID @クラスタ (送り, ...)` の形で [modules/golem-font/test/golden/](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-font/test/golden) の三つのファイルに書く。グリフ ID だけでは、どの字のグリフか、縦組みで縦書き用の字形に置き換わったかを読めない。HarfBuzz の版を上げてグリフが変わっても、正誤を判断せずに更新しやすい。

SVG のゴールデンの隣の「the same input gives the same drawing」（[modules/golem-svg/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/Main.hs#L257-L259)）は `readSvg doc @?= readSvg doc` であり、何も確かめていない。
これは [ADR 0065](0065-tautological-properties-and-oracles.md) で扱う。

## 実装すること

### golem-svg

- rotate-arc のゴールデンを、描画の命令を一行に一つずつ書いたテキストにする。座標と行列の成分は小数点以下 4 桁に丸めた十進数で書き、パスの命令は SVG の `M`、`C`、`L`、`Z` の文字で書く。
- 変換する関数はテストのコードに置き、`Golem.Svg` の公開の API は変えない。
- このゴールデンに加えて、回転と平行移動の行列の成分を、`rotate(30) translate(1,2)` から手で計算した値（cos 30°、sin 30° と平行移動の量）と比べる断言を足す。ゴールデンは回帰の検出に、断言は正しさの検査に使う。

### golem-lsp

- protocol.txt と protocol-utf8.txt の各行を、LSP の JSON の表現（`aeson` の `encode`）で書く。値ごとに一行とする。
- キーの順序は、aeson の `KeyMap` が既定で順序つきであることに頼る。実装のときに、同じ値を二度 `encode` したバイト列とキーの順序が名前の順であることを確かめる。
- `aeson` は golem-lsp のテストのスイートの依存にすでにある。依存は変えない。

### golem-font

- 各行に、そのクラスタの元の文字（`U+300C 「` の形）を添える。
- 縦組みのゴールデンには、同じ文字を横組みで整形したときのグリフ ID も添え、違えば `vert` の印を付ける。縦書き用の字形に置き換わったことを、ファイルを読むだけで確かめられるようにする。
- テストのフォントの Source Han Sans の部分集合は CID で字形を引くので、グリフ名（post の表や CFF の charset）は使わない。

## 実装しないこと

- golem-driver の text、xhtml、css のゴールデンの形を変えること。これらは Golem の出力そのものであり、人が読める。
- グリフ ID を cmap から独立に引き直すオラクルを書くこと。添える情報は読み手のためのもので、正しさの検査は既存の単体テスト（縦書き用の字形が横組みと違うこと、[modules/golem-font/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-font/test/Main.hs#L57-L60)）に任せる。

## テスト設計

テストを先に変え、今の実装で何が変わるかを確かめてから期待値を作る。

- golem-svg：`rotate(30) translate(1,2)` の行列の成分が、(cos 30°, sin 30°, −sin 30°, cos 30°, 1·cos 30° − 2·sin 30°, 1·sin 30° + 2·cos 30°) と 1e-4 の差で一致する。これは今の実装で通るはずの断言であり、落ちれば実装の誤りとして扱う。
- golem-svg：新しい形のゴールデンを作り、人が座標を一行ずつ読んで、円弧の端点が (7, 4) を変換した位置にあることを確かめてからコミットする。確かめた手順をプルリクエストの説明に書く。
- golem-lsp：新しい形のゴールデンが、lsp-types の型の名前（`Range`、`Position`、`_start`）を含まない。この断言をテストに足す。
- golem-font：縦組みのゴールデンで、U+300C、U+3001、U+30FC の行に `vert` の印があり、日本語の漢字の行にはない。この断言をテストに足す。

## トレードオフ

- SVG の座標を 4 桁に丸めるので、4 桁より細かい回帰はゴールデンでは見つからない。図版の座標は PDF に書くときにも丸めるので、それより細かい違いは出力に現れにくい。
- LSP のゴールデンは JSON の形になり、今より長くなる。依存の版を上げたときの書き直しは、JSON の表現が変わったときだけになる。
- font のゴールデンは一行が長くなる。正しさは読み手の目に頼る部分が残る。

## 参考文献

- [ADR 0065](0065-tautological-properties-and-oracles.md)
- tasty-golden 2.3.6 の `goldenVsString`

## 破棄の理由

この ADR は、人が読んで検算できることを優先して、ゴールデンの検査を緩める。
グリフ ID だけでは読めないので元の文字を添える、座標を 4 桁に丸める、という変更は、どれも人の読み手の都合による。
ところが、ゴールデンの差分を確かめるのは、いまは人ではなく AI である。
人が読みやすいことを、検査の厳しさより先に置く理由は薄い。

HarfBuzz の版を上げたときのグリフ ID の差分のように、ゴールデンの差分を追う作業は、AI のトークンを使って差分をレビューすることで扱う。
