# browser.yml の輪郭の SVG の文字の検査の測定（2026-11-08、[ADR 0239](../adr/0239-decide-the-conditions-of-the-outlined-figure-check-and-the-punctuation-of-figure-sources.md) の実装のプルリクエスト）

[ADR 0239](../adr/0239-decide-the-conditions-of-the-outlined-figure-check-and-the-punctuation-of-figure-sources.md) のテスト設計の 4 が、実装のプルリクエストで測ることにした値の記録である。
数字は、ブランチ `impl-0239` の push で走らせた `browser.yml` の二つの実行（42490942953 と 42491316216）から取った。
`workflow_dispatch` は既定のブランチにあるワークフローしか起動できないので、検証の間だけ push で起動した。
二つの実行の測った値は同じである。
入力の HTML とフォントは、`main` の c8c7f71c の `ci.yml` の実行 42489826255 の成果物である。
輪郭の SVG と原稿は、ブランチのものである。
2026-11-08 に作り、コミットした後は変更しない。

## 版

| 何 | 版 |
| --- | --- |
| chrome-headless-shell | Google Chrome for Testing 157.0.8103.38（linux64） |
| 輪郭の SVG の文字の検査の起動の引数 | `--font-render-hinting=none` |
| Safari | 27.2（20625.2.8.18.4） |
| macOS | 15.8.2（24H232）、像 `macos15` 20261104.0514.1 |
| Inkscape（輪郭を作ったもの） | 1.4.4（dcaf3e7d9e、2026-05-05） |

## 図ごとの最大の差

単位は CSS の画素で、図は SVG の 2 倍の大きさに描いた。
墨は、墨の画素の数の差を多い方の数で割った値である。

| 図 | Chromium の中心 | Chromium の大きさ | Chromium の墨 | Safari の中心 | Safari の大きさ | Safari の墨 |
| --- | --- | --- | --- | --- | --- | --- |
| channels | 1 | 1 | 9.52% | 3 | 2 | 18.79% |
| channels-example | 0.5 | 1 | 9.71% | 1 | 2 | 18.22% |
| modules | 1 | 1 | 2.91% | 2 | 2 | 17.41% |
| pipeline | 1 | 1 | 7.04% | 5.5 | 2 | 19.04% |
| purity | 1 | 2 | 8.93% | 3.5 | 2 | 18.73% |
| stages | 1 | 1 | 4.27% | 2.5 | 3 | 18.13% |

Chromium は、縦書きを含むすべての文字列で、中心が 1 画素以下、大きさが 2 画素以下だった。
Safari の列は、横書きの文字列だけの値である。

Safari で判定から外した縦書きの文字列は四つ（stages の `プラグイン`、`golem check と LSP`、`HTML、EPUB、テキスト`、`golem build の PDF`）で、中心の差の最大は 3、大きさの差の最大は 315、墨の差の最大は 17.57% だった。

## Safari の横書き

ADR の上限（中心 1 画素、大きさ 2 画素）では、Safari の横書きは 34 の文字列で失敗した（実行 42490942953）。
33 は中心の差（1.5 から 5.5 画素）で、`manifest.toml、style.toml`、`CST → AST`、`bookToc` のように、約物を持たない文字列にも出る。
残る一つは、stages の `…使えない（G02014）。` の大きさの差の 3 画素である。
このため、ADR の「決めたことの記録」のブラウザーの検査の厳しさの方針に従い、Safari の横書きの上限を中心と大きさとも 8 画素にした。

## Safari が `tspan` の `halt` を当てるか

ADR のテスト設計の 3 の前提である。
`halt` の `tspan` を持つ channels-example の四つの文字列と stages の一つの文字列は、Safari で大きさの差が 3 画素以下だった。
`halt` が当たらなければ、20px の字の約物の半分ぶん、20 画素の差になる。
したがって、Safari 27.2 は SVG の `tspan` の `font-feature-settings: "halt"` を当て、`text-spacing-trim: space-all` で自動の詰めをしない。
purity の `）　` も、輪郭を本文と同じ空きで作り直した後に、二つのブラウザで通った。

## 手元の Chromium

テスト設計の 1 は、macOS の Google Chrome 156.0.8078.80 を `--headless` で起動して確かめた。
`halt` の `tspan` を原稿から外すと、channels-example の四つの文字列で大きさが 22 から 37 画素違い、`halt` を書いた原稿では、約物を持つ文字列は上限の中に収まった。
macOS の字の描き方のため、墨の差はほとんどの文字列で 20% を超え、`[1] Knuth Donald. Breaking …` の中心が 2 画素、大きさが 4 画素違った。
これらは、CI の Chrome for Testing（linux64）では出ていない。
