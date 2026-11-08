# browser.yml の測定（2026-11-08、[ADR 0234](../adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の実装のプルリクエスト）

[ADR 0234](../adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) が実装のプルリクエストで測ることにした値の記録である。
ADR はコミットした後に変えられないので、ADR の「記録」に足す値をここに置く。
数字は、ブランチ `impl-0234` の push で走らせた `browser.yml` の実行から取った。
`workflow_dispatch` は既定のブランチにあるワークフローしか起動できないので、検証の間だけ push で起動した。
`golem-linux-x86_64` の成果物は [ADR 0231](../adr/0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md) の実装のプルリクエストの `ci.yml` の実行 42478712741 のものを使った。
2026-11-08 に作り、コミットした後は変更しない。

## 前提の確かめ

ADR が確かめていないとした二つの前提を、実装の前に一時的なワークフローで確かめた（実行 42477212797）。

- macOS 15 のランナー（像 `macos-15-arm64` 20261104.0514.1、macOS 15.8.2 24H232）で、`sudo safaridriver --enable` の後に `safaridriver` のセッションを作れ、Safari 27.2（20625.2.8.18.4）がウィンドウを開いて動いた。`Navigate To`、`Execute Script`、`Set Window Rect`、`Take Screenshot` が答えた。`devicePixelRatio` は 1、`127.0.0.1` のページの `isSecureContext` は真で、`crypto.subtle` があった。
- Chrome for Testing 157.0.8103.38 の `chrome-headless-shell` は、`file://` のページからの `fetch` を `URL scheme "file" is not supported` として拒んだ。同じページを `127.0.0.1` で配ると読めた。
- `ubuntu-24.04` のランナーは `kernel.apparmor_restrict_unprivileged_userns` が 1 で、`chrome-headless-shell` はサンドボックスを作れずに止まった。`cdp.mjs` は `--no-sandbox` で起動する。

## Chrome for Testing の配布の条件

zip の `ABOUT` は、中身を「Google Chrome」とし、利用の条件を Chrome の利用規約（`chrome://terms`、Google Chrome and ChromeOS Additional Terms of Service）に委ねている。
`LICENSE.headless_shell` は、Chromium とその部品のライセンスの一覧である。
Chrome for Testing の告知は、これを自動化とテストのための版としている。
CI で取って動かすことを禁じる条件は見当たらなかった。
Golem はこの zip を再配布せず、ランナーが Google から取り、Actions のキャッシュに置くだけである。
このため、ADR の「決めたことの記録」の 1 のとおり、Chromium のスナップショットではなく Chrome for Testing を使った。

## ジョブの時間

実行 42481365628 の、ジョブの始まりから終わりまでの時間である。

| ジョブ | 時間 | `timeout-minutes` |
|---|---|---|
| `prepare` | 24 秒 | 2 |
| `chromium` | 2 分 15 秒 | 5 |
| `safari` | 2 分 36 秒 | 6 |

`chromium` のうち、Deno の比べ合わせは 20 秒、Chromium の比べ合わせは 58 秒だった。
`safari` の Safari の比べ合わせは 76 秒だった。
`timeout-minutes` は、測った時間の倍ほどにした。

## 輪郭の SVG の文字（I4）

開発者のマニュアルの六つの図について、原稿の SVG の `text` の要素ごとに、二つの画像の墨の外接矩形を比べた、図ごとの最大の値である（実行 42481365628）。

| 図 | Chromium の中心の差 | Chromium の大きさの差 | Chromium の墨の差 | Safari の中心の差 | Safari の大きさの差 | Safari の墨の差 |
|---|---|---|---|---|---|---|
| channels | 3.5 | 2 | 10.53% | 3.5 | 2 | 18.60% |
| channels-example | 12.5 | 25 | 11.35% | 3.5 | 2 | 18.22% |
| modules | 4 | 4 | 3.85% | 3.5 | 2 | 17.15% |
| pipeline | 4 | 4 | 8.89% | 5.5 | 3 | 18.96% |
| purity | 12 | 24 | 7.87% | 3.5 | 2 | 17.39% |
| stages | 12.5 | 25 | 5.98% | 3 | 315 | 18.06% |

中心と大きさの差は CSS の画素で、SVG の 2 倍の大きさに描いたときの値である。
墨の画素の数の差は、大きいほうに対する割合である。
上限は、二つのブラウザの最大の 18.96% のすぐ上の 20% とし、`scripts/browser/svg-text.mjs` の `INK_LIMIT` に書いた。

中心の差と大きさの差は、今の六つの図のどれでも、どちらのブラウザでも 1 画素を超え、I4 の検査は失敗する。
中央揃えで `dominant-baseline: central` の文字は、輪郭のほうが CSS の 2 から 3.5 画素（SVG の座標で 1 から 1.75）上にある。
Chromium の 12 画素を超える差は、行の長い文字列で、輪郭と原稿の幅が違うものである。
Safari の stages の 315 画素の差は、縦書きの文字列（`golem check と LSP`）で、Safari が原稿の縦書きを輪郭と違う形に描くものである。

## 取るものの大きさ

| もの | 大きさ |
|---|---|
| `chrome-headless-shell-linux64.zip`（157.0.8103.38） | 128,168,542 バイト |
| `deno-x86_64-unknown-linux-gnu.zip`（2.9.8） | 41,963,064 バイト |

キャッシュに置くのは展開した `third_party/chromium` と `third_party/deno` で、圧縮した量はおよそ zip の大きさになる。
二つで約 170 MB である。
[ADR 0228](../adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) の I5 の見積もり（定常で約 3.0 GB、ツールチェーンのキーを替えたときに約 2.0 GB、push が重なったときに約 1.0 GB）に足しても、約 6.2 GB で 10 GB の下にある。
キャッシュを保存するのは `main` の実行だけで、版を上げない限り、それぞれ一つだけ残る。
