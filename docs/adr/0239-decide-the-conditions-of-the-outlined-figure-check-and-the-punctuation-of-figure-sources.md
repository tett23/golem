# ADR 0239: 輪郭の SVG の文字の検査の条件と、図の原稿の約物の詰めを決め、輪郭の手順の変更を記録する

ステータス: 採択→図の原稿の約物の詰めの表（実装すること 3 の表と、不変条件 I4 と、I7 の中点類の部分）は [docs/adr/0241](0241-derive-the-punctuation-of-figure-sources-from-the-default-aki-set.md)

## 文脈

[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の I4 は、開発者のマニュアルの輪郭の SVG の文字が、そのブラウザで描いた原稿の SVG の文字と、CSS の 1 画素以下の差の位置と大きさにあることを求める。
`scripts/browser/svg-text.mjs` は、原稿と輪郭の SVG を SVG の 2 倍の CSS の大きさに描いて撮り、原稿の `text` の要素ごとに墨の画素の外接矩形を比べる（[svg-text.mjs の比べ方](https://github.com/tett23/golem/blob/4fcd1f3a1a855cef11a8d7a23f919f86dbf72d84/scripts/browser/svg-text.mjs#L57-L70)）。
墨は、輝度が 160 より暗い画素である（[pixels.mjs](https://github.com/tett23/golem/blob/4fcd1f3a1a855cef11a8d7a23f919f86dbf72d84/scripts/browser/pixels.mjs#L60-L62)）。
この ADR は、I4 が失敗し続けている原因のうち、輪郭の誤りでないものの扱いを決める。
あわせて、PR #718 が ADR なしに変えた [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) の輪郭の手順を記録する。

### PR #718 の前の I4（CI で観測した値）

`browser.yml` の I4 は、PR #718 の前の二つの実行（42481365628 と、`main` の c409d5ea の `workflow_dispatch` の 42482965379）で、六つの図のすべてについて二つのブラウザで失敗した。
二つの実行の値は同じである。
図ごとの最大の値は次のとおりで、単位は CSS の画素である。

| 図 | Chromium の中心 | Chromium の大きさ | Safari の中心 | Safari の大きさ |
| --- | --- | --- | --- | --- |
| channels | 3.5 | 2 | 3.5 | 2 |
| channels-example | 12.5 | 25 | 3.5 | 2 |
| modules | 4 | 4 | 3.5 | 2 |
| pipeline | 4 | 4 | 5.5 | 3 |
| purity | 12 | 24 | 3.5 | 2 |
| stages | 12.5 | 25 | 3 | 315 |

42482965379 の失敗の行は、Chromium が 234、Safari が 195 である。
Chromium で大きさが 20 画素を超えて違う文字列は、どれも隣り合う全角の約物を持つ（`見出し「行分割」（階層 1）`、`見出し「参考文献」「索引」（@nonumber）`、`…使えない（G02014）。`、`時計（…作る）　乱数（…使う）` など）。
Safari の stages の大きな差は、縦書きの四つの文字列（`プラグイン` が 81、`golem check と LSP` が 315、`HTML、EPUB、テキスト` が 256、`golem build の PDF` が 315）である。
PR #718 がマージされた 2026-11-08T14:11Z より後の `browser.yml` の実行は、この ADR を書いた時点ではない。

### PR #718 が直したこと（PR の本文の報告）

PR #718 は、輪郭の誤りを二つ見つけ、`scripts/manual/outline-prepare.sh` を足して、Inkscape に渡す原稿の写しを直すようにした。
次の二つは PR の本文の報告であり、この ADR では確かめていない。

- **`dominant-baseline: central`**：Inkscape 1.4 は、Noto Sans JP の OS/2 の typographic ascender と descender（880 と -120）の中点に中央の基準線を置き、アルファベットの基準線の 0.38 em 上になる。Chromium は hhea の ascent と descent（1160 と -288）の中点に置き、0.436 em 上になる。輪郭は 0.056 em 高く、写しで 0.056 em 下げる。
- **隣り合う全角の約物**：Chromium の既定の `text-spacing-trim: normal` は、隣り合う全角の約物の一方を `halt` で半角にする（Chromium の `han_kerning.cc`）。Inkscape は詰めないので、写しで Chromium と同じ字に `halt` の `tspan` を当てる。約物の分類は Chromium が Noto Sans JP について計算するものを写した（[outline-prepare.sh の分類](https://github.com/tett23/golem/blob/4fcd1f3a1a855cef11a8d7a23f919f86dbf72d84/scripts/manual/outline-prepare.sh#L114-L118)）。縦書きの中の隣り合う約物は、Inkscape が `vhal` を Chromium と違う位置に置くので、エラーで止める。

PR の報告の値の中では、算術は合っている（880 と -120 の中点は 380、1160 と -288 の中点は 436 で、差は 56 である）。
フォントの表そのものは、この ADR では読んでいない。

### 残る差（PR の本文の報告）

PR #718 は、残る差を三つ報告した。
どれも、版を固定した Chrome for Testing の Linux の x86-64 の版でも、CI の Safari でも測っていない。

| 条件 | PR #718 の後の I4 |
| --- | --- |
| Debian の chromium-headless-shell 156（arm64 の Linux）、既定の起動 | 中心が最大 3 画素、大きさが最大 6 画素 |
| 同じもの、`--font-render-hinting=none` | 失敗は一つ。灰色の 20px の文字列の墨の外接矩形が 2 画素広い |
| chrome-headless-shell 157.0.8103.38（mac-arm64） | 中心は最大 1 画素。大きさの 2 画素の差と墨の 20% を超える差が、macOS の字の描き方で残る |

1. **ヒンティング**：Linux の Chromium は、既定のヒンティングで字の送りを画素にそろえる。欧文を含む長い文字列で、幅が 2 から 6 画素違う。`--font-render-hinting=none` で起動すると、この差は消える。
2. **Safari の縦書き**：macOS の QuickLook の WebKit では、SVG の縦書きの正立の字を、1 em ではなく行の高さ（hhea の ascent と descent の和、1.448 em）ずつ送る。Chromium と Inkscape は 1 em ずつ送る。PR は Safari そのものでは確かめていないが、上の stages の Safari の差はこの説明に合う。
3. **Safari の約物**：同じ WebKit は、隣り合う約物を既定で詰めない。PR #718 の後の輪郭は詰めた幅になるので、Safari の I4 には、詰めた六つの文字列で幅の差が新しく出る見込みである。

### 本文の組版は、隣り合う約物をどう組むか（コードを読んで確かめた）

図の約物を詰めるかは、ブラウザの既定ではなく、本の組み方の問いである。
開発者のマニュアルの本文は、Golem が既定のアキ量のセット `gyomatsu-yakumono-hankaku` で組む。
Golem は約物の字を半角の箱として置き（[`punctSpace`](https://github.com/tett23/golem/blob/4fcd1f3a1a855cef11a8d7a23f919f86dbf72d84/modules/golem-layout/src/Golem/Layout/Japanese.hs#L796-L807)）、字の間の空きをセットの規則で決める（[既定のセットの規則](https://github.com/tett23/golem/blob/4fcd1f3a1a855cef11a8d7a23f919f86dbf72d84/modules/golem-layout/src/Golem/Layout/Aki.hs#L78-L106)）。
今の図の原稿にある四つの組み合わせについて、墨と墨の間の空きを比べると次のようになる。
単位は em で、Safari の列は PR #718 の報告による。

| 組み合わせ | 原稿の例 | Golem の本文 | JLReq | Chromium の既定 | Safari の既定と `space-all` |
| --- | --- | --- | --- | --- | --- |
| 終わり括弧類と句点類 | `）。` | 0 | 0（ベタ） | 0 | 0.5 |
| 終わり括弧類と始め括弧類 | `」（`、`」「` | 0.5 | 0.5 | 0.5 | 1 |
| 終わり括弧類と和字間隔 | `）　` | 0.5 に和字間隔の 1 | 規定なし | 0 に和字間隔の 1 | 0.5 に和字間隔の 1 |
| 始め括弧類と始め括弧類 | 今の原稿にない | 0.5 | 0（ベタ） | 0 | 0.5 |

JLReq は、終わり括弧類の後ろの句点類をベタ組とし、終わり括弧類の後ろの始め括弧類との字間を二分とする（「始め括弧類，終わり括弧類，読点類，句点類及び中点類が連続する場合の配置方法」）。
Golem の本文は、今の原稿の三つの組み合わせのうち二つで JLReq と同じであり、Chromium の既定とも同じである。
三つめの `）　` では、Golem は終わり括弧類の後ろの二分を残し、Chromium は和字間隔を中点類に数えて終わり括弧類を詰める。
したがって、PR #718 の輪郭は、purity の `時計（…作る）　乱数（…使う）` で本の組み方より 0.5 em 狭い。

表の四行めは、この ADR が決めることではない。
Golem の既定のセットは、始め括弧類の前に、前の字が始め括弧類でも二分を置く（`(j <> w <> o, o, …)` の規則）。
JLReq は、始め括弧類が連続する字間をベタ組とする。
これは本文の組版の問いであり、図の原稿にはまだ現れないので、別に扱う（「実装しないこと」）。

### ADR を経ずに変わった手順

[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) は、輪郭の手順を五つの段で決め、三つめの段で原稿の写しから `@font-face` を消すことだけを定めた。
Inkscape が `dominant-baseline` や縦書きを Chrome と違って組む場合は、原稿の側を、どちらでも同じに描かれる書き方に直すとも書いた。
PR #718 は、原稿を直さず、写しを直す段を足した。
結果は [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) の目的（輪郭がブラウザで見た原稿と同じ形になること）に沿うが、手順は [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) と違う。
コミットした ADR は変えられないので、その記録をこの ADR に置く。

## 実装すること

### 1. Chromium の起動の仕方

`scripts/browser/run.mjs` は、`svg` の検査のときだけ、`cdp.mjs` の `launch` の `args` に `--font-render-hinting=none` を渡す（[`launch` の引数](https://github.com/tett23/golem/blob/4fcd1f3a1a855cef11a8d7a23f919f86dbf72d84/scripts/browser/cdp.mjs#L162-L172)、[`run.mjs` の検査の選び方](https://github.com/tett23/golem/blob/4fcd1f3a1a855cef11a8d7a23f919f86dbf72d84/scripts/browser/run.mjs#L83-L96)）。
`html` の検査は、今のまま既定の起動で走らせる。
`html` の検査は利用者の Chrome に近い描き方を確かめるものであり、I4 は輪郭と原稿の形の一致を確かめるものだからである。
`chromium` のジョブの要約に、I4 の起動の引数を版と並べて書く。

### 2. I4 の判定

[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の I4 を、この ADR の I1 と I2 に置き換える。

- 中心の差の上限は、CSS の 1 画素のままとする。
- 大きさの差の上限を、CSS の 2 画素にする。墨の外接矩形の左右（上下）の縁は、原稿の字形と輪郭のパスで別々に画素へ量子化され、縁ごとに 1 画素まで動く。中心は二つの縁の平均なので 1 画素まで、大きさは差なので 2 画素まで動く。
- 墨の画素の数の上限（`INK_LIMIT`）は変えない。
- 縦書きの `text` の要素（原稿で `writing-mode` が縦のもの）は、Chromium では横書きと同じに判定する。Safari では、測って要約とログに書くが、判定には含めない。
- Safari の要約に、判定から外した縦書きの文字列の数と、その中心と大きさの最大の差を書く。

### 3. 図の原稿の約物の詰め

図の約物を、Golem が本文を組むのと同じ空きで組む。
詰めは、ブラウザの既定に任せず、原稿に書く。

- 原稿の `<style>` に、一行の規則 `text { text-spacing-trim: space-all; }` を置き、ブラウザの自動の詰めを止める。
- 原稿の `<style>` に、一行の規則 `tspan.halt { font-feature-settings: "halt"; }` を置く。
- 詰める約物は、原稿の `text` の中で `<tspan class="halt">（</tspan>` のように一字ずつ包む。
- どの字を包むかは、次の表で決まる。表の「空き」は Golem の既定のセットの最適の空きで、O は始め括弧類、P は終わり括弧類と句点類と読点類、S は和字間隔である。約物の字の墨の外の空き（O は前に、P は後ろに 0.5 em）の和から、Golem の空きを引いた量だけ詰める。

| 前の字 | 後ろの字 | 空き | 詰める字 |
| --- | --- | --- | --- |
| P | P | 0 | 前の字 |
| P | O | 0.5 | 後ろの字 |
| P | S | 0.5 | なし |
| O | O | 0.5 | なし |
| O | P | 0 | なし |
| S | O | 0.5 | なし |

一字は、墨の外の空きを片側にしか持たないので、二つの組み合わせで同じ字を詰めることはない。
中点類を含む組み合わせと、縦書きの中の組み合わせは、表に載せず、検査をエラーで止める。
今の原稿にはどちらもない。

`scripts/manual/check-figures.sh` に、原稿の検査を足す。
原稿の横書きの `text` の中の隣り合う O、P、S の組み合わせのそれぞれで、`halt` の `tspan` が表のとおりであることを確かめる。
表にない組み合わせ、`halt` の要らない字の `halt`、`text-spacing-trim: space-all` の規則がない原稿は、エラーにする。
検査は POSIX の sh と awk で書き、Inkscape を使わないので、`docs.yml` の `manual` ジョブで今と同じく走る。

`scripts/manual/outline-prepare.sh` を、次のように改める。

- Chromium の約物の分類と、それによる `golem-halt` の `tspan` の挿入を消す。
- `text` の中に、`<tspan class="halt">` で一字を包んだものだけを許す。ほかの要素は、今と同じくエラーにする。
- `text-spacing-trim` の一行の規則を、Inkscape に渡す写しから消す。[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) の「文字だけに効くプロパティ」の表に `text-spacing-trim` はなく、輪郭の SVG に残すと G08011 になるためである。
- 足す規則に、`tspan.halt { baseline-shift: 0; }` を入れる。Inkscape は入れ子の `tspan` の `baseline-shift` を足し合わせるので、PR #718 の `golem-halt` と同じ扱いが要る。
- `dominant-baseline: central` の 0.056 em の扱いと、`@font-face` を消すことは、今のままとする。

六つの原稿のうち、channels-example、purity、stages の三つに `halt` を書き、すべての輪郭の SVG を作り直す。
purity の `）　` は詰めないので、その輪郭は PR #718 の輪郭より 0.5 em 広くなる。

### 4. 輪郭の手順の記録

[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) の「開発者のマニュアルの図」の手順は、この ADR の後、次の五つの段になる。

1. `scripts/manual/fetch-fonts.sh` でマニュアルのフォントを用意する。
2. 一時のディレクトリに fontconfig の設定を書く（[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) と同じ）。
3. `scripts/manual/outline-prepare.sh` で原稿の写しを作る。写しは、`@font-face` と `text-spacing-trim` の規則を除き、中央揃えで `dominant-baseline: central` の横書きの文字を 0.056 em 下げ、`halt` の `tspan` の `baseline-shift` を 0 にする規則を足したものである。
4. `inkscape --export-text-to-path --export-plain-svg` で輪郭にする（[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) と同じ）。
5. `outline-prepare.sh --strip` で足した規則を出力から除き、先頭に原稿の SHA-256 などのコメントを置く。

原稿の書き方の制約（`text` の要素は一行に書き、中に置くのは `halt` の `tspan` だけ、縦書きに隣り合う全角の約物を置かない）も、この手順の一部とする。
[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) のステータスの行に、この ADR を指す句（「輪郭の手順の原稿の写しの直しと、図の原稿の約物の詰めは docs/adr/0239」に、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) からの相対のリンクを付けたもの）を足す。

### 5. 文書

- `docs/manual-policy.md` の図の項に、図の約物は本文と同じ空きで組み、詰めを原稿に `halt` で書くことと、`check-figures.sh` がそれを確かめることを書く。原稿を開いて確かめるブラウザは Chromium の系統のものとし、Safari では縦書きが輪郭と違って描かれることも書く。
- README の図の手順と、開発者のマニュアルの `manual-dev/part2/15-manuals.gm` の図の段落を、同じく改める。
- `docs/roadmap.md` の「SVG の図版の見た目」から、検査の起動の仕方と、Safari の縦書きと約物の比べ方を決めることを外す。
- 仕様書の CI の節と README の `browser.yml` の行に、I4 の Chromium の起動の引数と、Safari で縦書きを判定しないことを書く。
- 実装のプルリクエストで測った I4 の値を、`docs/ci-timings/` の新しい記録に置く。

## 実装しないこと

- 利用者のブラウザの Chrome の既定の起動（ヒンティングあり）で、輪郭と原稿が一致することを確かめること。
- Safari で縦書きの原稿を、輪郭と同じに描かせる書き方（字ごとの `y` の並び、`textLength`）。Inkscape と Safari がどう扱うかを確かめていないうえ、原稿を直すたびに位置を計算し直す必要がある。
- 中点類を含む約物の組み合わせと、縦書きの中の隣り合う約物の詰め。今の原稿になく、縦書きでは Inkscape の `vhal` の置き方が Chromium と違う。
- 行頭と行末の約物の空き（段落の先頭の始め括弧類の前の二分、行末の句点類の後ろの空き）を、図の文字列に当てること。図の `text` は段落の行ではなく、中央揃えの位置は字の送りの全体で決まるので、行末の空きを変えると、詰めのない文字列まで位置が動く。
- Golem の既定のセットの、始め括弧類が連続するときの二分を JLReq に合わせること。本文の組版の変更であり、別の ADR で扱う。
- アキ量のセットを図ごとに選ぶこと。図の約物は既定のセット `gyomatsu-yakumono-hankaku` だけに合わせる。
- 利用者のマニュアルの図（`manual/images/`）を I4 で確かめること。[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) と同じく、開発者のマニュアルの図だけを確かめる。`check-figures.sh` の約物の検査は、二冊の原稿の両方に当てる。
- I4 の墨の閾値を、文字の色ごとに変えること。

## 不変条件

番号はこの ADR のものであり、[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の I1 から I7 とは別である。

| 番号 | 不変条件 |
| --- | --- |
| I1 | Chromium の I4 では、原稿のすべての `text` の要素（横書きも縦書きも）について、二つの墨の外接矩形の中心の差が CSS の 1 画素以下、大きさの差が CSS の 2 画素以下、墨の画素の数の差が `INK_LIMIT` 以下である。 |
| I2 | Safari の I4 では、横書きのすべての `text` の要素について I1 と同じ基準が成り立つ。縦書きの要素は合否に数えず、その数と差の最大が要約に出る。 |
| I3 | `svg` の検査の Chromium は `--font-render-hinting=none` を引数に持ち、`html` の検査の Chromium は持たない。 |
| I4 | 原稿の横書きの `text` の中の隣り合う O、P、S のすべての組み合わせで、`halt` の `tspan` で包んだ字は、「実装すること」の 3 の表の「詰める字」とちょうど一致する。そうでない原稿で、`check-figures.sh` は 0 でない終了コードで終わる。 |
| I5 | `check-figures.sh` を通る原稿は、`text { text-spacing-trim: space-all; }` を持つ。 |
| I6 | `outline-prepare.sh` の写しを Inkscape にかけて `--strip` した輪郭の SVG は、`text-spacing-trim`、`golem-outline` の規則、`@font-face` を持たず、golem-svg が G08011 なしで読む。 |
| I7 | 中点類を含む隣り合う約物、縦書きの中の隣り合う約物、`halt` 以外の要素を中に持つ `text` で、`check-figures.sh` か `outline-prepare.sh` は 0 でない終了コードで終わり、行の番号を標準エラーに書く。 |
| I8 | 同じ原稿から `outline-prepare.sh` が作る写しのバイト列は、何度作っても同じである。 |

境界の入力は次のとおりである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 中心の差がちょうど 1 画素、大きさの差がちょうど 2 画素の横書きの文字列 | 通る | I1、I2 |
| 大きさの差が 3 画素の横書きの文字列 | 失敗する | I1、I2 |
| 中心の差が 1.5 画素で、大きさの差が 0 の文字列 | 失敗する | I1 |
| 灰色（`#555`）の 20px の文字列で、墨の縁が左右に 1 画素ずつ広い | 通る | I1 |
| 縦書きの文字列の大きさの差が 315 画素（Safari） | Safari で通り、要約に 315 が出る | I2 |
| 同じ縦書きの文字列の大きさの差が 3 画素（Chromium） | 失敗する | I1 |
| 欧文だけの横書きの文字列 | 表の組み合わせがなく、`halt` は要らない | I4 |
| 約物を一つだけ持つ文字列（`（G02014）`） | `halt` は要らない | I4 |
| `）。`（P と P） | `）` だけを包むと通り、包まないと失敗する | I4 |
| `」（`（P と O） | `（` だけを包むと通り、`」` を包むと失敗する | I4 |
| `）　`（P と S） | 何も包まないと通り、`）` を包むと失敗する | I4 |
| `」（「`（三つの約物） | `（` だけを包む | I4 |
| `）」。`（P が三つ） | `）` と `」` を包む | I4 |
| 空の `text` の要素 | `halt` は要らず、`check-figures.sh` は通る | I4 |
| `space-all` の規則を消した原稿 | `check-figures.sh` が失敗する | I5 |
| `）・`（P と中点類） | エラーで止まる | I7 |
| 縦書きの `」（` | エラーで止まる | I7 |
| `text` の中の `<tspan class="b">` | エラーで止まる | I7 |

## テスト設計

テストを先に書き、失敗することを確かめてから実装する。
テストの名前には、この ADR の番号（`ADR0239-I4` のように）を入れる。

- I1 と I2：`scripts/browser/test/` の `node --test` に、`compareInk` の境界のテストを足す。中心 1 と大きさ 2 で通り、大きさ 3 と中心 1.5 で失敗する。縦書きの印を持つ測りが、Safari の判定では失敗に数えられず、要約の数に入ることを、ブラウザなしの関数のテストで確かめる。
- I3：`run.mjs` が `launch` に渡す引数を返す関数を分け、`svg` と `html` のそれぞれで引数を比べるテストを書く。
- I4、I5、I7：`scripts/manual/test.sh` に、境界の表の原稿を fixture として足し、`check-figures.sh` の終了コードと標準エラーを確かめる。
- I6 と I8：`scripts/manual/test.sh` で、`halt` の `tspan` と `space-all` を持つ fixture の写しが `text-spacing-trim` を持たず、`tspan.halt { baseline-shift: 0; }` を持つこと、二度作った写しが同じことを確かめる。Inkscape の出力が golem-svg で読めることは、今の golem-driver のテスト（開発者のマニュアルの輪郭の SVG に `Unsupported` がない）が確かめる。

自動のテストにできないことは、実装のプルリクエストで次の順に確かめる。

1. Chromium と Inkscape が、SVG の `tspan` の `font-feature-settings: "halt"` で同じ幅に組むことを、手元の Chromium で I4 を走らせて確かめる。
2. [ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の実装と同じく、検証の間だけ push で `browser.yml` を走らせる。Chrome for Testing 157 の x86-64 で、`--font-render-hinting=none` の I4 が通ることを確かめる。
3. 同じ実行で、Safari 27.2 の I4 の横書きが通ることを確かめる。Safari が SVG の `tspan` の `halt` を当てない場合は、実装を止め、測った値をメンテナーに報告する。そのときは、この ADR の 3 の前提が崩れるので、新しい ADR で決め直す。
4. 測った値（図ごとの中心、大きさ、墨の差の最大と、Safari で判定から外した縦書きの差）を `docs/ci-timings/` の記録に置く。

## トレードオフ

I4 の Chromium は、ヒンティングを切って走る。
利用者の Linux の Chrome は既定でヒンティングをかけるので、I4 が確かめるのは「利用者の Chrome で原稿がこう見える」ことではなくなる。
しかし、利用者が見るのは輪郭の SVG であり、原稿の SVG は開発の時の入力である。
輪郭のパスはヒンティングを受けないので、ヒンティングのある描き方を基準にすると、輪郭には合わせようのない差が残る。

大きさの差の上限を 2 画素に広げると、幅が 2 画素以内で違う誤りを見逃す。
今わかっている輪郭の誤りは、どれもこれより大きい。
`dominant-baseline` の 0.056 em は 20px の字で中心に 2.24 画素の差として出て、約物の詰めの 0.5 em は幅に 20 画素以上の差として出る。
中心の上限は 1 画素のまま残るので、位置の誤りの感度は変わらない。

Safari では、縦書きを判定から外す。
Safari の縦書きを [ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) のとおり判定すると、Safari が変わるまで I4 は毎晩失敗し、ほかの失敗を隠す。
代わりに、Safari の縦書きの描き方が変わっても、判定では気づかない。
要約の縦書きの差の最大を前の実行と比べれば、変化には気づける。
また、[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の I6（検査はどちらのブラウザでも同じ基準を当てる）に、二つめの例外ができる。

図の約物の詰めを、原稿に書く。
原稿の書き手は、隣り合う約物に `halt` の `tspan` を書く必要があり、原稿は読みにくくなる。
代わりに、Chromium の内部の分類（`han_kerning.cc`）を写した表がなくなり、Chromium の版を上げたときに分類が変わる心配もなくなる。
三つの描き手（Chromium、Safari、Inkscape）は、どれも自動の詰めをせず、原稿に書いた `halt` だけを当てるので、同じ幅に組むことが期待できる。
この期待は、Safari については確かめていない（テスト設計の 3）。
書き忘れは `check-figures.sh` が CI で見つける。

図の約物の空きを、ブラウザではなく Golem の本文に合わせる。
開発者のマニュアルの図は、PDF でも HTML でも、本文と同じページに置かれる。
本文で `）　` の後ろに二分を空け、図で詰めると、同じ本の中で約物の組み方が二通りになる。
代わりに、Golem の既定のセットが JLReq と違う箇所（始め括弧類の連続）は、図にもそのまま写る。

## メンテナーが決めること

1. **ヒンティングと I4 の起動**：推奨は、`svg` の検査の Chromium だけを `--font-render-hinting=none` で起動し、大きさの差の上限を 2 画素にすることである。
   - 退けた案の一つは、既定の起動のまま、中心と大きさの上限を 6 画素に広げることである。`dominant-baseline` の誤り（中心で 2 から 3.5 画素）を見逃す。
   - 二つめは、起動の引数を変え、大きさの上限は 1 画素のまま残すことである。字形とパスの縁の量子化だけで、同じ形の組が失敗しうる。PR #718 が報告した灰色の文字列がそれに当たる見込みである。
   - 三つめは、墨の閾値を文字の色ごとに変えることである。どの閾値でも縁の量子化は残り、色を原稿から読む処理が増える。
   - 四つめは、`html` の検査も同じ引数で起動することである。利用者の Chrome から遠ざかるうえ、HTML の検査にヒンティングの差の問題はない。
2. **Safari の縦書き**：推奨は、Safari の I4 で縦書きを判定から外し、測った値を要約に書くことである。
   - 退けた案の一つは、Safari の I4 を全部やめることである。横書きの二つめの描き手としての Safari の確かめ（中央の基準線と約物の幅が二つのエンジンで同じこと）を失う。
   - 二つめは、Safari だけ上限を広げることである。差は 300 画素を超え、上限に意味がなくなる。[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の「上限は二つのブラウザで共通」にも反する。
   - 三つめは、原稿の縦書きを字ごとの `y` の並びか `textLength` で書くことである（「実装しないこと」）。
3. **図の約物の詰め**：推奨は、Golem の本文と同じ空きで詰め、詰めを原稿に `halt` で書き、`text-spacing-trim: space-all` でブラウザの自動の詰めを止めることである。今の原稿の組み合わせのうち、`）。` と `」（` と `」「` は JLReq とも Chromium とも同じ幅になり、`）　` だけが PR #718 より 0.5 em 広くなって本文と同じになる。
   - 退けた案の一つは、`space-all` だけを原稿に書き、どこも詰めないことである。三つのブラウザと Inkscape はそろうが、`）。` と `」（` が JLReq の「連続する約物」の配置にも本文にも合わず、一字ぶん空いた形になる。
   - 二つめは、PR #718 のまま Chromium の詰めに合わせ、Safari の比べ方を変えることである。Chromium の内部の分類を写し続ける必要があり、`）　` で本文と違ううえ、Safari の I4 に詰めの例外をもう一つ足すことになる。
4. **PR #718 の手順の記録**：推奨は、この ADR を記録とし、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) のステータスの行からこの ADR を指すことである。
   - 退けた案の一つは、PR #718 の記録だけの ADR を別に作ることである。手順の 3 の段は、この ADR の 3 で変わるので、二つの ADR で同じ段を順に書き換えることになる。
   - 二つめは、PR #718 を戻し、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) のとおり原稿の側を直すことである。`dominant-baseline: central` の差を原稿で消すには、すべての `text` を `tspan` で包むか、基準線をやめて位置を計算し直す必要がある。前者は今の写しと同じ形を原稿に持ち込むだけであり、後者は原稿の書き方として重い。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：基本は推奨のとおりとした。
- **ブラウザの検査の厳しさ**（2026-11-08、メンテナー）：ブラウザでは表示がずれるのがふつうなので、検査を厳密にしなくてよい。致命的な崩れを見つけるものと、費用に比べて効果の大きいものだけを行う。実装では、上限や対象を決めるときにこの方針を優先し、ずれを詰めるために手間のかかる処理を足さない。この方針で推奨の一部を緩めたときは、実装のプルリクエストにその点と理由を書く。

## 参考文献

- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/（「句読点や，括弧類などの基本的な配置方法」、「始め括弧類，終わり括弧類，読点類，句点類及び中点類が連続する場合の配置方法」。w3c/jlreq の 43942474 の index.html で読んだ）
- W3C, CSS Text Module Level 4（`text-spacing-trim`）, https://www.w3.org/TR/css-text-4/
- W3C, CSS Fonts Module Level 4（`font-feature-settings`）, https://www.w3.org/TR/css-fonts-4/
- W3C, CSS Writing Modes Level 3（`text-orientation`）, https://www.w3.org/TR/css-writing-modes-3/
- Microsoft, OpenType の feature tags（`halt`、`vhal`）, https://learn.microsoft.com/en-us/typography/opentype/spec/featurelist
- Chromium, `third_party/blink/renderer/platform/fonts/shaping/han_kerning.cc`（PR #718 の報告による。この ADR では読んでいない）
- tett23/golem PR #718, Outline the figures where Chromium draws their sources, https://github.com/tett23/golem/pull/718
- GitHub Actions の `browser.yml` の実行 42481365628 と 42482965379, https://github.com/tett23/golem/actions/workflows/browser.yml
