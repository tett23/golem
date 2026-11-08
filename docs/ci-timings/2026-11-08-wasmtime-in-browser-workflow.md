# browser.yml の wasmtime の測定（2026-11-08、[ADR 0238](../adr/0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md) の実装のプルリクエスト）

[ADR 0238](../adr/0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md) が実装のプルリクエストで測ることにした値の記録である。
ADR はコミットした後に変えられないので、ここに置く。
2026-11-08 に作り、コミットした後は変更しない。

## 測り方

`workflow_dispatch` は既定のブランチにあるワークフローしか起動できない。
このため、検証の間だけ、ブランチ `impl-0238` の push で `browser.yml` を起動する一時的なコミットを置いた（実行 42490319390）。
入力の成果物は、同じブランチの `ci.yml` の実行 42489579415（コミット `e328025c`）のものである。
この実行の `golem.wasm` は、標準化された例外処理の形で作ったものである。
一時的なコミットは、マージの前に取り消した。

## `chromium` のジョブの時間

| ステップ | 時間 |
|---|---|
| wasmtime の C API の取得（`scripts/fetch-wasmtime.sh`） | 1 秒 |
| Deno の比べ合わせ | 46 秒 |
| Chromium の比べ合わせ | 92 秒 |
| wasmtime の比べ合わせ（`compare.sh --wasmtime`） | 56 秒 |
| 二つの `call` の比べ（I5） | 57 秒 |

ジョブの全体は、始まりから 5 分 20 秒ほどで、すべてのステップを終えたところで `timeout-minutes` の 5 分を超えて取り消された。
wasmtime の二つのステップは、どちらも通った。
I5 の三つの入力の枠は、正規化されていないパスで 9 バイト、ファイルのない枠で 183 バイト、kanikosen で 1671203 バイトの、同じバイト列の結果の枠を返した。
`timeout-minutes` は、測った時間の倍ほどの 11 分にした。

同じ実行の `safari` のジョブでも、Safari 27.2 の比べ合わせは通った。
両方のジョブの輪郭の SVG の文字の検査（I4）は失敗した。
これは [ADR 0234](../adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の測定の記録にあるとおりで、この ADR とは関わらない。

## `ci.yml` の `wasm` のジョブの時間

実行 42489579415 の `wasm` のジョブは 293 秒で、5 分を超えなかった。
ツールチェーンのキャッシュは当たり、`golem.wasm` のビルドは 122 秒だった。
`scripts/wasm/legacy-eh.sh` は 1 秒かからなかった。

golem-font を変える前のコミット（`c23d4af7`、実行 42489033049）では、`legacy-eh.sh` が古い形の例外処理の命令を見つけて 1 で終わった。
