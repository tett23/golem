# CI の所要時間（2026-11-04、golem-driver-test を threaded にした前後）

[ADR 0146](../adr/0146-threaded-golem-driver-test.md) の実装の前後の、`ci.yml` の `build` のテストの手順の記録である。
数字は `gh run view <id> --json jobs` の手順の秒数と、ジョブのログの tasty の行（`All N tests passed (Xs)`）から取った。
2026-11-04 に作り、コミットした後は変更しない。

## 前

[ADR 0140](../adr/0140-ci-split-test-runners-and-visual-pdfs-first.md) の後の 10 回の実行（41818037051 から 41828953772 まで）である。

| 手順 | 秒 |
|---|---|
| x86-64 の `tests-driver` の `cabal test` | 55〜88 |
| aarch64 の `tests` の `cabal test` | 85〜92 |
| golem-driver-test（x86-64、`tests-driver` の中、tasty の報告） | 約 80（[41815303999](https://github.com/tett23/golem/actions/runs/41815303999) は 10:37:48 から 10:39:09） |
| golem-driver-test（aarch64） | 82〜87 |

## 後

このプルリクエスト（[#528](https://github.com/tett23/golem/pull/528)）の 3 回の実行である。
一回目と二回目は、開発者向けのマニュアルの参照を受け入れる前で、`visual` だけが失敗した。

| 実行 | `tests-driver` の `cabal test` | aarch64 の `tests` の `cabal test` | golem-driver-test（x86-64） | golem-driver-test（aarch64） | golem-driver-global-test（x86-64） |
|---|---|---|---|---|---|
| [41848776519](https://github.com/tett23/golem/actions/runs/41848776519) | 53 | 81 | 50.08 | 69.18 | 21.96 |
| [41849632732](https://github.com/tett23/golem/actions/runs/41849632732) | 54 | 82 | 49.63 | 69.48 | 21.95 |
| [41850302302](https://github.com/tett23/golem/actions/runs/41850302302) | 36 | 82 | 32.80 | 70.40 | 15.05 |

手元（10 コアの macOS、`+RTS -N4`）では、golem-driver-test は 20 回続けて 854 のテストがすべて通り、18.8 秒から 34.1 秒だった（前は 48.7 秒）。
golem-driver-global-test は 120 のテストが通り、8.4 秒だった。

## 読み方

x86-64 の golem-driver-test は約 80 秒から 33〜50 秒になり、`tests-driver` の手順は 36〜54 秒になった。
同じ手順の中で、golem-driver-global-test と golem-driver-parallel-test が同時に走り、コアを取り合う。
aarch64 の golem-driver-test は 82〜87 秒から約 70 秒になったが、`tests` は 24 のほかのスイートとコアを取り合うので、手順は 81〜82 秒とほとんど縮まなかった。
三回目の実行では、`build` で最後に終わったのは aarch64 の `tests`（170 秒）と `tests-rest`（161 秒）で、`tests-driver` は 95 秒で終わった。

[ADR 0146](../adr/0146-threaded-golem-driver-test.md) のテスト設計にある、夜間の `race.yml` の対象に golem-driver-test を足すかどうかは、足さないことにした。
`race.yml` が回数を増やすのは `GOLEM_RACE_TESTS` で回数を変える並行のプロパティで（[ADR 0075](../adr/0075-race-search-repetitions.md)）、golem-driver-test にはその変数で回数の変わるテストがない。
同時に走ることで起きる失敗は、プルリクエストごとの実行と、上の手元の 20 回で見る。
