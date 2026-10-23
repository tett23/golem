# 競合を探すテストの所要時間（2026-10-24、手元、GOLEM_RACE_TESTS=40）

[ADR 0075](../adr/0075-race-search-repetitions.md) のテスト設計に従い、`.github/workflows/race.yml` が走らせる三つのテストを、`GOLEM_RACE_TESTS=40` で手元で走らせた記録である。
2026-10-24 に作り、コミットした後は変更しない。

## 環境

- Apple M1 Max（10 コア）、macOS
- GHC 9.10.3、ビルド済みの `dist-newstyle` で、`cabal test -v0` の開始から終了まで（コンパイルを含まない）
- コミットは [ADR 0075](../adr/0075-race-search-repetitions.md) の実装のブランチ（`impl-adr-0075`）

## 結果

単位は秒である。

| テスト | 秒 | 回数 |
|---|---|---|
| `golem-driver-parallel-test` | 324 | 三つのプロパティが 1000、320、400 回、見本の本の並列のビルドがそれぞれ 40 回 |
| `golem-font-race-test` | 7 | 回数は `GOLEM_RACE_TESTS` によらない |
| `golem-font-test` の並行のテスト（`-p '/one font from many threads/'`） | 8 | プロパティが 1200 回 |
| 合計 | 339 | |

`golem-driver-parallel-test` の中では、tasty が各テストを同時に走らせる。
いちばん長いのは `kanikosen` の並列のビルドの 40 回で、317 秒だった。

## 判断

合計は 6 分弱で、[ADR 0075](../adr/0075-race-search-repetitions.md) の上限の 30 分を下回るので、掛ける数は 40 のままとする。
GitHub の `ubuntu-24.04` のランナーは 4 コアで、手元より遅い。
プロセッサの数に比例して延びるとしても 15 分ほどであり、`race.yml` の `timeout-minutes: 60` に収まる。
最初の夜間の実行の所要時間で、この見積もりを確かめる。
