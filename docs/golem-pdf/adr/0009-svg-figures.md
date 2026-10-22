# ADR 0009: SVG の図版

ステータス: 採択→HTML と EPUB での SVG の動く中身の検査は [docs/adr ADR 0039](../../adr/0039-svg-active-content-in-html-and-epub.md)、`marker` の循環と入れ子の上限と、数の大きさの上限は [docs/adr/0041](../../adr/0041-svg-marker-and-number-limits.md)

## 文脈

仕様書の[「図版」の節](../../specifications.md#図版)は、SVG を「PDF へ変換する処理が重いので v1 では扱わない」と定めている。
ロードマップの v1.0.0 の「SVG の図版」は、これを改めて v1 で扱うとし、PDF での描き方（ベクターのまま描くか、変換するか）と、HTML と EPUB でそのまま使うかを決めることを求めている。

### 今の振る舞い

[ADR 0008](0008-pdf-figures.md) の実験で確かめたとおり、今の Golem は `@figure images/a.svg` を評価の段階で通し、次のように扱う。

- PDF は、`readImage` が SVG を読めないので、図版をキャプションごと黙って落とす。[ADR 0008](0008-pdf-figures.md) は、これを G08010 のエラーにし、図版の拡張子を `.pdf`、`.png`、`.jpg`、`.jpeg` に限る（G02074）。
- HTML と EPUB は、SVG のファイルをそのまま写して `<img>` で置く。EPUB はその `media-type` を `application/octet-stream` にする。SVG は EPUB 3 のコアメディアタイプ（`image/svg+xml`）なので、正しい型を書けば EPUB のリーダーはそのまま表示できる。

### 開発者のマニュアルの図

開発者のマニュアル（`manual-dev/`）の四つの図は、`manual-dev/images/src/` の SVG を原稿とし、`scripts/manual/render-figures.sh` が headless Chrome で PNG に描いたものを置いている（`docs/manual-policy.md`）。
同じ方針は、PDF と SVG の図版が使えるようになったら、図をベクターのまま置く形に改めると書いている。
四つの SVG が使う機能を数えると、v1 で扱う範囲の目安になる。

- **要素**：`svg`、`defs`、`style`、`marker`、`rect`、`line`、`path`、`text` だけである。`use`、グラデーション、クリップ、フィルター、画像はない。
- **パス**：`M`、`L`、`H`、`V`、`C`、`Z` の絶対座標の命令だけである。`transform` の属性はない。
- **スタイル**：`<style>` の CSS を、型、クラス、型とクラスの組（`rect.proc`）、セレクターのリストで当てる。`style` の属性も二か所ある。CSS の幾何のプロパティ（`rx`）も使う。
- **文字**：`@font-face` でプロジェクトの `fonts/` の Noto Sans JP を指し、`text` で文字を描く。縦書きも使う。
- **矢印**：`marker` を `orient="auto-start-reverse"` で使う。
- **色**：`#rrggbb` の sRGB の色だけである。

四つとも `text` を使うので、下の「メンテナーが決めたこと」により、原稿の SVG をそのまま PDF に置くことはできない。

### PDF での描き方の候補

SVG を PDF に描く方法は、外部の変換器に任せるか、Golem が PDF の描画の演算子に直すかのどちらかになる。

- **librsvg（`rsvg-convert`）**：LGPL で、cairo と Pango を通して PDF を書く。文字の書体は fontconfig で探すので、システムのフォントが出力に入る。
- **resvg と svg2pdf**：MPL 2.0 と Apache 2.0 などの Rust のライブラリである。組み込むには Rust のツールチェーンをビルドに加える必要がある。フォントのデータベースは既定でシステムのフォントを読む。
- **Inkscape**：GPL の大きなアプリケーションで、コマンドラインから PDF に書き出せる。
- **headless Chrome**：開発者のマニュアルが PNG に描くのに使っている。印刷で PDF にできるが、出力は Chrome の版で変わり、ページ単位の PDF を図版として取り込み直す必要がある。

外部のコマンドを `golem build` から呼ぶと、利用者がそれを別に入れる必要があり、出力が変換器の版で変わる。
[docs/adr/0002](../../adr/0002-determinism.md) は、ネイティブライブラリの版も出力の入力とみなし、システムのフォントを出力に影響させないと定めている。
どの変換器も、そのままではシステムのフォントを探す。
ライブラリとして組み込む場合も、HarfBuzz と FreeType のように版を固定して同梱する必要があり、cairo や Rust のツールチェーンはその負担が大きい。

一方、PDF の書き手は、矩形、字形、画像を描く演算子をすでに書いている。
SVG の静的な部分（パス、塗りと線、変換）を PDF の演算子に直す仕事は、その上に載せられる。
CLAUDE.md の方針（ライセンスに問題がなく再実装が容易なら、依存に入れず、必要な機能だけを再実装する）にも合う。
「変換する処理が重い」という仕様書の理由は、SVG の全体を扱う場合には当たるが、範囲を絞れば当たらない。

### 色

SVG の色は sRGB である。
仕様書の[「色」の節](../../specifications.md#色)は、色の変換を CMYK から RGB の方向に限り、写真などの画像を例外として、ICC プロファイルを付けて変換せずに埋め込むと定める。
SVG の図版も同じ例外に入れ、sRGB の ICCBased の色空間で描くのが、今の規則に最も近い。
[ADR 0008](0008-pdf-figures.md) が PDF の図版の DeviceRGB を sRGB の ICCBased に置き換えるのとも同じ形になる。

### メンテナーが決めたこと

案の段階で残していた問いに、メンテナーが次のとおり答えた。

- SVG の中の、輪郭（アウトライン）にしていない文字は、エラーとする。`text`、`tspan`、`textPath` の要素と `@font-face` は、どれも PDF に置けない。したがって、SVG の文字の書体を `@font-face` や `style.toml` の役割から探す仕組みは作らない。案にあった、外部のファイルを参照する SVG に `web` を求める診断（G08012）と、総称のファミリーと役割の結び付けの問いも、この決定で要らなくなった。
- `device-cmyk()` は扱わない（「実装しないこと」）。
- 開発者のマニュアルの四つの図は、文字を輪郭にした SVG にし、SVG の図版としてベクターのまま置く。PNG にはしない。輪郭の SVG は、編集できる原稿の SVG から開発の時に作り、原稿と輪郭の SVG の両方をコミットする。作るためのツールは、Golem 自身の実行時の依存を増やさないかぎり、理由があれば開発の時のツールを使ってよい。
- SVG を読む処理は、新しいパッケージ golem-svg として Haskell で書く。Rust のライブラリも、新しい組み込みの依存も入れない。組み込みの依存を足すことは、ビルドと決定性の管理の負担が大きいためである。
- 新しい診断のコード（G08011）が、並行して書かれているほかの ADR のコードと重なった場合は、実装する者がそれを報告し、重ならない順に実装する。この ADR を書いた時点では、08 の区分のコードを使うほかの案は [ADR 0008](0008-pdf-figures.md) だけである。

文字のエラーには、新しいコードを足さず、扱えない機能のコード G08011 を使う。
文字を描けない理由は、グラデーションや `use` を描けない理由と同じく、この ADR が扱う範囲の外にあることである。
直し方も同じく、作成ツールの側で範囲の中に収めて書き出し直すことであり、文字の場合は輪郭にして書き出す。
コードを分けても、利用者が取る行動は変わらない。
`@figure` ごとに一つの診断にまとめる G08011 の規則の中で、文字の場合は、メッセージの理由に輪郭にするよう書いて案内する。

## 実装すること

### 範囲

SVG 1.1 と SVG 2 の静的な部分のうち、次の表のものだけを扱う。
表にない SVG の要素、属性、プロパティの値は、黙って無視せず、G08011 のエラーにする。
無視して描くと、ブラウザーで見た図と PDF の図が食い違い、その違いに気付く手段がないためである。

| 種類 | 扱うもの |
| --- | --- |
| 構造の要素 | `svg`（ルートだけ）、`g`、`defs`、`style`、`marker`。`title`、`desc`、`metadata` は読み飛ばす |
| 図形の要素 | `rect`、`circle`、`ellipse`、`line`、`polyline`、`polygon`、`path` |
| パスの命令 | `M`、`L`、`H`、`V`、`C`、`S`、`Q`、`T`、`A`、`Z` と、その相対座標の形 |
| 変換 | `transform` の `matrix`、`translate`、`scale`、`rotate`（中心の指定を含む）、`skewX`、`skewY` |
| 塗りと線 | `fill`、`fill-rule`、`stroke`、`stroke-width`、`stroke-linecap`、`stroke-linejoin`、`stroke-miterlimit`、`stroke-dasharray`、`stroke-dashoffset` |
| 表示 | `display`（`none` と `inline`）、`visibility`（`visible` と `hidden`）。`opacity`、`fill-opacity`、`stroke-opacity` は `1` だけ |
| 幾何 | `rect` の `rx` と `ry`（属性と CSS のプロパティ） |
| 矢印 | `marker-start`、`marker-mid`、`marker-end`、`marker`（同じ文書の `url(#id)` だけ）。`marker` の `markerWidth`、`markerHeight`、`refX`、`refY`、`viewBox`、`preserveAspectRatio`、`orient`（`auto`、`auto-start-reverse`、角度）、`markerUnits`。`overflow` は既定の `hidden` だけで、マーカーの枠で切り抜く |
| 色 | CSS の色の名前、`#rgb`、`#rrggbb`、`rgb()`（整数と百分率）、`none`、`transparent`（`none` と同じ）、`currentColor` と `color` |
| 長さの単位 | 単位なしと `px`。ルートの `width` と `height` に限り、`pt`、`pc`、`mm`、`cm`、`in` も使える |
| ルートの大きさ | `width`、`height`、`viewBox`、`preserveAspectRatio`（すべての値） |
| 文字だけに効くプロパティ | `font-family`、`font-size`、`font-weight`、`font-style`、`font-variant` と `font-variant-` で始まるもの、`font-stretch`、`font-feature-settings`、`font-variation-settings`、`font`、`text-anchor`、`text-orientation`、`dominant-baseline`、`alignment-baseline`、`baseline-shift`、`writing-mode`、`glyph-orientation-vertical`、`letter-spacing`、`word-spacing`、`line-height`、`inline-size`、`shape-inside`、`shape-padding`、`xml:space`。値を問わず読み飛ばす |
| 描画に効かない属性 | `aria-` で始まる属性と `role`。読み飛ばす |

文字の要素（`text`、`tspan`、`textPath`）と、スタイルシートの `@font-face` は、表の外であり G08011 とする。

文字だけに効くプロパティを読み飛ばすのは、作成ツールが文字を輪郭にして書き出すときに、元の文字のスタイルを輪郭のパスや `g` に残すことが多いためである。
これらのプロパティは文字の要素がなければ描画に効かないので、読み飛ばしても PDF の図はブラウザーで見た図と変わらない。
同じく、Inkscape は輪郭にした文字の `g` に元の文字列を `aria-label` として残すので、支援技術のための属性も読み飛ばす。

### XML と CSS（golem-svg の `Golem.Svg.Xml`、`Golem.Svg.Css`）

SVG を読むための XML と CSS の部分集合を、依存に入れずに Haskell で書く。

- **XML**：UTF-8 の文書だけを読む（宣言の `encoding` が UTF-8 以外なら G08010）。要素、属性、名前空間、文字、CDATA、コメント、処理命令（読み飛ばす）、文字参照と五つの定義済みの実体参照を扱う。内部サブセットを持つ `DOCTYPE` は拒む（実体の展開をしないためである）。SVG の名前空間の外の要素と属性（Inkscape の `sodipodi:` など）は読み飛ばす。整形式でない文書は G08010 とする。
- **CSS**：`<style>` の中と `style` の属性を読む。セレクターは型、`.class`、`#id`、`*`、それらの組み合わせ（`rect.proc`）、カンマで並べたリストを扱う。結合子（子孫、子、兄弟）、擬似クラス、属性セレクター、`!important`、すべてのアットルール（`@font-face` を含む）は G08011 とする。カスケードは、表現の属性、詳細度と出現の順で並べたスタイルシートの規則、`style` の属性の順に強くなり、継承するプロパティは親から引き継ぐ。ベンダーの接頭辞の付いたプロパティ（`-inkscape-font-specification` など）は読み飛ばす。

### 描画（golem-svg の `Golem.Svg`）

SVG のバイト列を、PDF の書き手に渡せる描画の列に直す純粋な関数を作る。

```haskell
readSvg :: ByteString -> Either SvgError Svg
data Svg = Svg
  { svgSize :: !(Rational, Rational),   -- ルートの幅と高さ（縦横の比に使う）
    svgDrawing :: ![DrawOp]
  }
data DrawOp
  = DPath !Paint ![Segment]
  | DGroup !Matrix !(Maybe ClipRect) ![DrawOp]
data SvgError
  = SvgMalformed !Text                  -- G08010 の理由
  | SvgUnsupported !(NonEmpty Unsupported)  -- G08011
```

- 円、楕円、角の丸い矩形、円弧（`A`）は三次のベジェ曲線に直す。円弧は 90 度以下の区間に分ける。
- 数は有理数で計算する。三角関数と平方根は、IEEE の浮動小数点数と libm を使わず、有理数の級数を決まった項数で打ち切って求める。座標と行列の値は、PDF に書くときに 1/65536 の固定小数点に丸める。x86-64 と aarch64 で同じ出力にするためである（[docs/adr/0002](../../adr/0002-determinism.md)）。
- マーカーは、SVG の規則どおり、パスの頂点の接線（中間の頂点では前後の接線の二等分）の向きに置く。向きは接線のベクトルを整数の平方根で正規化して求め、角度を経由しない。
- 扱えないものは、要素や属性の名前と SVG のファイルの中の行と桁を持つ `Unsupported` として、文書の順にすべて集める。文字の要素と `@font-face` の `Unsupported` は、文字であることを示す種類を持ち、診断のメッセージで輪郭にするよう案内できるようにする。

### PDF への描き方（golem-pdf）

- SVG の図版は、[ADR 0008](0008-pdf-figures.md) の `Form` の印で置く。`docForms` の値を、取り込んだ PDF のページと SVG の描画の和にする。
- Form XObject の `BBox` は、ルートの `viewBox`（なければ `width` と `height`）とし、`preserveAspectRatio` を `Matrix` で表す。SVG の y 軸は下向きなので、`Matrix` で上下を反転する。
- 色は、sRGB のプロファイル（`Golem.Pdf.Srgb`）の ICCBased の色空間（`/GolemSRGB cs`、`CS`）と `sc`、`SC` で書く。DeviceRGB と、CMYK への変換は使わない。sRGB のプロファイルのストリームは、画像と取り込んだ PDF の図版と共有して一度だけ書く。
- 線の端、角、点線、マイターの限度は、PDF の対応する演算子（`J`、`j`、`d`、`M`、`w`）で書く。`fill-rule` の `evenodd` は `f*` と `B*` にする。
- マーカーの切り抜きは `re W n` で書く。
- 文字、フォント、透明、パターン、シェーディングは書かない。SVG の図版の Form XObject は、資源に `Font` を持たない。

### 置けない SVG の診断（golem-driver）

| コード | 重大度 | 出す場面 | メッセージ |
| --- | --- | --- | --- |
| G08010 | エラー | SVG を XML として読めない、UTF-8 でない、内部サブセットを持つ、大きさがない | `図版を PDF に置けません: <パス>（<理由>）`（[ADR 0008](0008-pdf-figures.md) と同じ） |
| G08011 | エラー | 扱わない要素、属性、値、輪郭にしていない文字 | `SVG の図版に扱えないものがあります: <パス>:<行>:<桁>（<名前>）ほか <n> 件` |

- G08011 は `@figure` ごとに一つ出し、最初に見つかったものの名前と位置をメッセージに書き、残りの件数を添える。位置はその `@figure` のブロックとする。
- 最初に見つかったものが文字の要素か `@font-face` なら、`（<名前>）` を `（<名前>: 文字は輪郭にして書き出してください）` とする。
- G08010 と G08011 は dev と prod の両方でエラーである。PDF を組むとき（`golem build` の PDF、`golem preflight`）にだけ出す。HTML、EPUB、プレーンテキストは SVG を読まない。

### HTML と EPUB（golem-html、golem-epub）

- SVG の図版は、今と同じくファイルを写して `<img>` で置く。`web` があれば、`web` を置く。HTML と EPUB は SVG の中身を検査しない（[ADR 0008](0008-pdf-figures.md) が PNG と JPEG を検査しないのと同じ）。
- golem-epub の `mediaType` に `.svg` の `image/svg+xml` を加える。

### 図版の形式（golem-eval）

[ADR 0008](0008-pdf-figures.md) の拡張子の表に、`.svg` を加える。

| 引数 | 受け付ける拡張子 |
| --- | --- |
| 画像（最初の位置引数） | `.pdf`、`.png`、`.jpg`、`.jpeg`、`.svg` |
| `web` | `.png`、`.jpg`、`.jpeg`、`.svg` |

- G02073 と G02074 のメッセージに SVG を加える（`図版の形式は PDF、PNG、JPEG、SVG です: <パス>`、`web の代替画像は PNG、JPEG、SVG です: <パス>`）。
- SVG の図版の `web` は省ける。`page` は SVG の図版にも書けない（G02075）。

### プリフライト（golem-preflight）

- SVG の図版も、[ADR 0008](0008-pdf-figures.md) の `FigureContent` の一つ（`SvgFigure`）としてページの図版の一覧に載せる。
- G09008 は、SVG の図版の色空間を `rgb` とする。G09006、G09007、G09009 は SVG の図版を検査しない。G09011 は矩形で検査する。

### 開発者のマニュアルの図

四つの図を、文字を輪郭にした SVG の図版として置く。

- 原稿は今と同じく `manual-dev/images/src/<名前>.svg` とし、文字を `text` のまま書く。ブラウザーで開いて確かめられるよう、`@font-face` もそのまま残す。
- 輪郭の SVG は `manual-dev/images/<名前>.svg` に置き、`@figure images/<名前>.svg alt="..."` で置く。`web` は書かない。輪郭の SVG は文字もフォントも持たないので、HTML と EPUB の `<img>` でも PDF と同じ形に描かれ、PNG の代わりの画像は要らない。
- 今の `manual-dev/images/<名前>.png` は消す。
- 原稿の先頭のコメントの「render-figures.sh で PNG にする」を、`outline-figures.sh` で輪郭の SVG にする旨に改める。

輪郭の SVG は、新しいスクリプト `scripts/manual/outline-figures.sh` が Inkscape（1.x）で作る。
`render-figures.sh` はこれに置き換えて消す。

```sh
sh scripts/manual/outline-figures.sh [名前...]   # 省けばすべての図
```

スクリプトは図ごとに次のことをする。

1. `scripts/manual/fetch-fonts.sh` でマニュアルのフォントを用意する。
2. 一時のディレクトリに fontconfig の設定を書く。フォントのディレクトリを `manual-dev/fonts` だけにし、原稿の `font-family` の名前（`Fig Sans`）を `Noto Sans JP` に結び付ける別名を置く。`FONTCONFIG_FILE` でこの設定を指し、システムのフォントを使わせない。
3. 原稿の写しから `@font-face` の規則を消す（Inkscape は `@font-face` を読まず、残すと輪郭の SVG が G08011 になるためである）。
4. `inkscape --export-text-to-path --export-plain-svg --export-filename=<出力> <写し>` で、文字を輪郭のパスにし、Inkscape の名前空間を除いた SVG を書く。
5. 出力の先頭に、原稿のパス、原稿の SHA-256、Inkscape の版、手で直さないことを書いたコメントを置く。

縦書きの文字は、Inkscape が `glyph-orientation-vertical` を読むことを確かめていない。
原稿の縦書きの規則には、ブラウザーと Inkscape の両方が読む `text-orientation: upright` を足す。

輪郭の SVG が原稿と食い違わないよう、新しいスクリプト `scripts/manual/check-figures.sh` を CI の `docs.yml` の `manual` ジョブで動かす。
このスクリプトは Inkscape を使わず、各輪郭の SVG の先頭のコメントの SHA-256 と、原稿の SHA-256 が一致することだけを確かめる。
原稿を直して輪郭の SVG を作り直し忘れると、CI が失敗する。

### データ構造

- 新しいパッケージ golem-svg を作る。依存は base、bytestring、containers、text だけとし、`Golem.Svg`、`Golem.Svg.Xml`、`Golem.Svg.Css` を持つ。golem-pdf は golem-svg に依存しない。
- golem-pdf に、SVG の描画を PDF の演算子で書くための `Drawing`（パス、塗りと線、行列と切り抜きを持つ組）を加える。字形は持たない。golem-driver が golem-svg の `Svg` を `Drawing` に直す。
- golem-pdf の `docForms` の値を `FormContent = ImportedForm ImportedPage | DrawnForm Drawing` にする。
- golem-driver の `FigureContent` に `SvgFigure !Drawing` を加える。

### ドキュメント

- 仕様書の[「図版」の節](../../specifications.md#図版)の SVG の文を、扱う範囲、文字を輪郭にする必要があること、PDF での描き方、HTML と EPUB での扱い、G08011 に書き直す。[「色」の節](../../specifications.md#色)の画像の例外に SVG の図版を加える。[「モジュール構成」の節](../../specifications.md#モジュール構成)に golem-svg を加える。
- `docs/markup.md` の「図版」の節の形式の一覧に SVG を加え、`web` を省けること、扱う範囲の要約、文字を輪郭にする必要があることを書く。
- `docs/diagnostics.md` に G08011 の節を足し、文字を輪郭にして書き出す直し方を書く。G02073 と G02074 のメッセージを改める。
- `docs/roadmap.md` から「SVG の図版」を消す。
- `docs/manual-policy.md` の図の項を改める。開発者のマニュアルの図は、`manual-dev/images/src/` の編集できる SVG を原稿とし、`scripts/manual/outline-figures.sh` で文字を輪郭にした SVG を `manual-dev/images/` に作り、両方をコミットする。輪郭の SVG は手で直さない。図は SVG の図版としてベクターのまま置き、`web` の画像は置かない。「今は RGB の PNG のままにする」の項は、図版が sRGB の SVG であることに改める。
- README.md の開発者のマニュアルの図の手順と、開発者のマニュアルの `manual-dev/part2/15-manuals.gm` の図の段落を、`outline-figures.sh` と輪郭の SVG に改め、Inkscape を入れる必要があることを書く。
- 利用者のマニュアルの `manual/chapters/03-markup.gm`（図版の節）と `manual/appendices/a-markup.gm` に SVG の扱いと文字の制限を、`manual/appendices/e-errors.gm` に G08011 を足す。
- 開発者のマニュアルの `manual-dev/part2/07-modules.gm` に golem-svg を加え、モジュールの図の原稿（`images/src/modules.svg`）にも箱を足して、輪郭の SVG を作り直す。
- 開発者のマニュアルの四つの `@figure`（`part1/06-ir.gm` の二つ、`part2/07-modules.gm`、`part2/12-purity.gm`）を `images/<名前>.svg` に改める。
- [ADR 0008](0008-pdf-figures.md) のステータスの行を「採択→図版の形式の SVG は [ADR 0009](0009-svg-figures.md)」に改める（[ADR 0008](0008-pdf-figures.md) が採択された後）。

## 実装しないこと

- SVG の中の輪郭にしていない文字を描くこと。`text`、`tspan`、`textPath`、`@font-face`、`style.toml` の役割の書体による SVG の文字の組版、SVG の縦書き。
- 表にない SVG の機能。とくに `use` と `symbol`、グラデーション、パターン、`clipPath`、`mask`、フィルター、`image`、`foreignObject`、1 でない不透明度、`switch`、アニメーション、スクリプト、外部の CSS（`<?xml-stylesheet?>`）。図の作成ツールが書き出す SVG にはこれらを含むものが多いので、範囲を広げる場合は使われる機能を数えてから別の ADR で決める。
- `device-cmyk()`（CSS Color Module Level 5）で SVG に CMYK の色を書くこと。ブラウザーが対応していないので、HTML と EPUB では別の色になる。`style.toml` のスウォッチを SVG から使うことも扱わない。
- SVG の色を CMYK に変換すること。Golem は RGB から CMYK の方向に変換しない。
- SVGZ（gzip で圧縮した SVG）と、UTF-8 以外の文字コード。
- HTML と EPUB で、SVG の中身を検査すること、SVG をインラインの `<svg>` として埋め込むこと、SVG が参照するファイルを出力に写すこと。
- `golem build` が外部の変換器（librsvg、resvg、Inkscape、Chrome）に変換を任せること。Rust のライブラリや新しい組み込みの依存を使うこと。Inkscape は、開発者のマニュアルの図を作る開発の時のツールとしてだけ使う。
- SVG の文字を輪郭にする処理を Golem に入れること。
- CI で Inkscape を動かして輪郭の SVG を作り直し、コミットしたものと比べること。CI は原稿の SHA-256 だけを比べる。
- 利用者のマニュアルの図。今は SVG の図を持たない。

## テスト設計

実装の前に書き、失敗することを確かめる。

### XML と CSS（`modules/golem-svg/test/Main.hs`）

- 要素、属性、名前空間、CDATA、文字参照、実体参照を読む。整形式でない文書、内部サブセットを持つ `DOCTYPE`、`encoding="Shift_JIS"` を拒む。
- Inkscape の名前空間の要素と属性を読み飛ばす。
- CSS の詳細度と出現の順、表現の属性と `style` の属性の強さ、継承を、開発者のマニュアルの `rect.proc` の規則の組み合わせで確かめる。子孫の結合子、`!important`、`@font-face`、`@media` が `Unsupported` になる。

### 描画（`modules/golem-svg/test/Main.hs`）

- 各図形とパスの命令（相対座標を含む）が、期待する線分とベジェ曲線の列になる。円弧は、開始点と終点が一致し、90 度以下の区間に分かれる。
- `rotate(30)` と `A` の命令の結果の値が、決まった有理数に丸めた固定の値に等しい（golden）。同じ入力から二度作った結果が同じである。
- `orient="auto-start-reverse"` のマーカーが、パスの始まりで逆向き、終わりで接線の向きに置かれる。
- 表にない要素（`linearGradient`、`use`）と値（`opacity="0.5"`）が、行と桁を持つ `Unsupported` になり、文書の順にすべて集まる。
- `text`、`tspan`、`textPath` が、文字の種類の `Unsupported` になる。
- `style="font-family:Noto Sans JP;font-size:12px;text-anchor:middle"` を持つ `path` と `g`（輪郭にした文字の書き出しの形）が、`Unsupported` なしで読める。
- 開発者のマニュアルの四つの輪郭の SVG（`manual-dev/images/<名前>.svg`）が、`Unsupported` なしで読める。
- 四つの原稿の SVG（`manual-dev/images/src/<名前>.svg`）の `Unsupported` が、文字の要素と `@font-face` だけである。原稿の文字のほかの部分が範囲に収まっていることを確かめる。
- `aria-label` を持つ `g` が、`Unsupported` なしで読める。

### PDF と CLI（`modules/golem-driver/test/Main.hs`、`modules/golem-driver/test/CliSpec.hs`）

- SVG の図版を置いた本の PDF に Form XObject があり、矩形の幅が行長で、高さがルートの縦横の比に合う。その Form XObject の資源に `Font` がない。
- SVG の `fill="#ff0000"` が、ICCBased の sRGB の `sc` で書かれ、PDF に DeviceRGB がない。`Golem.Pdf.X4.verify` が問題を返さない。PDF が `qpdf --check` を通る。
- `linearGradient` を含む SVG が `golem build --target pdf` で G08011 になり、終了コード 1 で PDF を書かない。dev と prod の両方で同じである。整形式でない SVG が G08010 になる。
- `text` を含む SVG が G08011 になり、メッセージに `文字は輪郭にして書き出してください` を含む。
- `text` を含む SVG の図版でも、`golem build --target html` と `--target epub` は診断を出さずに `<img>` で置く。`web` があれば、`<img>` が `web` を指す。
- EPUB の `package.opf` で、SVG の項目の `media-type` が `image/svg+xml` である。
- 同じ SVG の図版を持つ本を二度組んだ PDF のバイト列が同じである。決定性の CI の検査（x86-64 と aarch64）にも SVG の図版を持つ fixture を加える（[docs/adr/0002](../../adr/0002-determinism.md)）。
- `print` の設定の `golem preflight` で、SVG の図版が G09008（`rgb`）を出し、G09006 を出さない。

### 開発者のマニュアル（`scripts/manual/check-figures.sh`、`modules/golem-driver/test/CliSpec.hs`）

- 開発者のマニュアルを PDF、HTML、EPUB で組み、G08010 と G08011 が出ない。PDF の四つの図版が Form XObject で、資源に `Font` を持たない。HTML の `<img>` が `images/<名前>.svg` を指す。この確かめは、マニュアルを組む今の CI のジョブがそのまま行う。
- `check-figures.sh` は、原稿を一文字変えると失敗し、`outline-figures.sh` で作り直すと通る。シェルのスクリプトなので自動テストは書かず、実装の後にこの手順で確かめる。

### 自動テストにしない確かめ方

- 四つの輪郭の SVG と原稿の SVG を Chrome で開いて並べ、文字の位置（中央揃え、`dominant-baseline: central`）、縦書きの字の向き、太字が一致することを目で確かめる。開発者のマニュアルの PDF の図も同じく比べる。Inkscape が `dominant-baseline` や縦書きを Chrome と違って組む場合は、原稿の側をどちらでも同じに描かれる書き方に直す。
- Inkscape と Illustrator と draw.io で、表の範囲だけを使い、文字を輪郭にして描いた図を SVG で書き出し、PDF で崩れないこと、範囲の外の機能と輪郭にしていない文字が G08011 で報告されることを確かめる。
- SVG の図版を含む PDF を、商用のプリフライト（Acrobat の PDF/X-4 の検査）に通す。

## トレードオフ

外部の変換器を使わず、SVG の部分集合を Golem が Haskell で描くことにした。
変換器を使えば、SVG の機能のほとんどを最初から扱える。
しかし、どの変換器もシステムのフォントを探し、出力が変換器の版で変わり、利用者の環境に別のツールを要求する。
組み込みの依存として同梱する道もあるが、メンテナーはそれを避けると決めた。
代わりに、扱える SVG は狭く、作成ツールの書き出しによっては G08011 で止まる。
その場合は、ツールの側で範囲の中に収めて書き出し直すか、PDF で書き出して [ADR 0008](0008-pdf-figures.md) の PDF の図版として置く。

輪郭にしていない文字を、エラーにした。
SVG の文字を描くには、書体を探す規則（`@font-face`、`style.toml` の役割、総称のファミリー）、シェイピング、縦書き、`text-anchor` と `dominant-baseline` の位置合わせを決める必要があり、どれもブラウザーの描き方と細部まで合わせるのが難しい。
HTML と EPUB の `<img>` の SVG は `@font-face` を読み込まないので、文字を持つ SVG はそもそも出力によって違う書体で描かれる。
文字を輪郭にすれば、どの出力でも同じ形に描かれ、Golem は図形だけを扱えばよい。
代わりに、輪郭にした文字は後から直せず、図の作成ツールの側で原稿と書き出しを分けて管理する必要がある。
開発者のマニュアルの図も、原稿と輪郭の SVG の二つを持つ。

開発者のマニュアルの図を輪郭にするツールに、Inkscape を選んだ。
今の `render-figures.sh` が使う headless Chrome は、文字を描けるが、字形の輪郭をパスとして取り出す手段を持たない。
Golem の中の golem-font（FreeType と HarfBuzz）で輪郭を取り出す開発用の実行ファイルを書く道もある。
書体は組版とまったく同じになるが、`text-anchor`、`dominant-baseline`、縦書きの組み方を自前で書く必要があり、メンテナーが Golem から外すと決めた文字の組版を、開発用のツールとして抱え直すことになる。
手で輪郭にする道は、図を直すたびに作業が要り、原稿と輪郭の SVG の対応を機械で確かめられない。
Inkscape は GPL の大きなアプリケーションで、メンテナーの手元には今は入っておらず、入れる必要がある（macOS では Homebrew の cask、CI の Ubuntu では apt で入る）。
しかし、使うのは図を直した時だけであり、Golem の実行ファイルにもビルドにも入らない。
出力はコミットするので、Inkscape の版で出力が変わっても、本の決定性には響かない。
CI は Inkscape を動かさず、原稿の SHA-256 だけを比べるので、CI に Inkscape を入れる必要もない。
代わりに、Inkscape の組み方が Chrome と細部で違う場合は、原稿の側で合わせる必要がある。

HTML と EPUB でも、開発者のマニュアルの図は `web` を置かず輪郭の SVG を使うことにした。
輪郭の SVG はフォントを読み込まないので、`<img>` でも PDF と同じ形に描かれ、画面でも拡大して崩れない。
PNG を残すと、原稿、輪郭の SVG、PNG の三つを同期させる必要があり、Chrome と Inkscape の両方が要る。

文字のエラーに、新しいコードを足さず G08011 を使うことにした。
コードを分けると、利用者はコードの一覧から文字の問題だけを探しやすくなる。
しかし、原因（範囲の外の機能）と直し方（範囲に収めて書き出し直す）はほかの G08011 と同じであり、`@figure` ごとに一つにまとめる規則の中で文字だけを別の診断に分けると、一つの図版に二つのエラーが出る場合ができる。
メッセージの理由で輪郭にするよう案内すれば、直し方は伝わる。

文字だけに効くプロパティを、エラーにせず読み飛ばすことにした。
範囲の外のものはエラーにするという原則には外れて見える。
しかし、これらは文字の要素がなければ描画に効かず、読み飛ばしても図の見た目は変わらない。
エラーにすると、文字を輪郭にして書き出した SVG の多くが、残ったスタイルのために置けなくなる。

範囲の外の機能を、無視せずエラーにした。
無視すると、多くの SVG がとりあえず PDF に入るが、グラデーションが単色に、クリップされた図形がはみ出した形に、黙って変わる。
図の崩れは、印刷の後でしか気付かれないことがある。

SVG の色を sRGB のまま、ICCBased で PDF に入れることにした。
印刷の色への変換は RIP に任せることになり、図の色は CMYK で指定した文字や罫線の色と完全には合わない。
写真の画像と同じ扱いであり、`print` のプリフライトの設定は G09008 の警告でこれを知らせる。
CMYK で色を決めたい図は、CMYK の PDF に書き出して PDF の図版として置ける。

HTML と EPUB では SVG をそのまま使い、中身を検査しないことにした。
そのまま使えば、画面でもベクターのまま拡大できる。
PDF を組まない本では、輪郭にしていない文字を持つ SVG も HTML と EPUB に入り、読者の環境のフォントで描かれる。
PNG と JPEG の図版も HTML と EPUB では検査しないので、それと同じ扱いにした。

三角関数と平方根を、有理数の級数で自前で求めることにした。
`Double` と libm を使うほうが速く簡単だが、libm の超越関数は環境ごとに最後の桁が違いうる。
SVG の図版の数値の計算は図ごとに数百回程度なので、有理数の計算でも組版の時間にはほとんど響かないと見込む。

## 参考文献

- W3C, Scalable Vector Graphics (SVG) 1.1 (Second Edition), 2011（8 パス、9 基本図形、11.6 マーカー、F.6 円弧の実装の注記）
- W3C, Scalable Vector Graphics (SVG) 2, Candidate Recommendation, 2018（幾何のプロパティ `rx` と `ry`）
- W3C, CSS Color Module Level 4（色の名前、`rgb()`）と CSS Color Module Level 5（`device-cmyk()`）
- W3C, Selectors Level 3（詳細度）
- W3C, EPUB 3.3, 2023（コアメディアタイプの `image/svg+xml`）
- ISO 32000-1:2008（8.4 図形の状態、8.5 パスの構築と描画、8.6.5.5 ICCBased の色空間、8.10 Form XObject）
- Inkscape のコマンドラインの説明（`--export-text-to-path`、`--export-plain-svg`。Inkscape 1.x の `inkscape --help` によるもので、実際の出力は確かめていない）
- W3C, CSS Writing Modes Level 3（`text-orientation`）
