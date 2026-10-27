# CI の所要時間（2026-10-27、build の PATH をそろえ、環境を変える検査とスクリプトのテストを分けた前後）

[ADR 0097](../adr/0097-ci-same-path-before-build-and-env-check-runner.md) の実装の前後の、`ci.yml` の所要時間の記録である。
表は `gh run view <id> --json jobs -q .` を実行ごとに一行にし、`scripts/ci/timings.sh --median` に渡した出力から、ジョブ全体の行を抜いたものである。
各組は 2 回の実行で、単位は秒である。
2026-10-27 に作り、コミットした後は変更しない。

## 実行

| 組 | 実行 |
|---|---|
| 前、プルリクエスト | [40368830926](https://github.com/tett23/golem/actions/runs/40368830926)、[40366727002](https://github.com/tett23/golem/actions/runs/40366727002) |
| 前、`main` への push（すべての入力の環境を変える検査） | [40368421139](https://github.com/tett23/golem/actions/runs/40368421139)、[40372815478](https://github.com/tett23/golem/actions/runs/40372815478) |
| 後、プルリクエスト（下書き [#435](https://github.com/tett23/golem/pull/435)） | [40375352220](https://github.com/tett23/golem/actions/runs/40375352220)、[40376691227](https://github.com/tett23/golem/actions/runs/40376691227) |
| 後、すべての入力（下書き [#436](https://github.com/tett23/golem/pull/436)。#435 から `--quick` を外しただけの、計測のための下書き） | [40375774694](https://github.com/tett23/golem/actions/runs/40375774694)、[40377816967](https://github.com/tett23/golem/actions/runs/40377816967) |

## 前、プルリクエスト

| ジョブ | 最小 | 中央値 | 最大 |
|---|---|---|---|
| `changes` | 31 | 32 | 33 |
| `build (ubuntu-24.04, tests)` | 145 | 156 | 167 |
| `build (ubuntu-24.04, outputs)` | 340 | 346.5 | 353 |
| `build (ubuntu-24.04-arm, all)` | 156 | 158 | 160 |
| `determinism` | 4 | 5 | 6 |
| `visual` | 213 | 214 | 215 |
| `release-scripts` | 17 | 17 | 17 |
| `scripts-macos` | 177 | 198.5 | 220 |
| `format` | 72 | 73 | 74 |
| `ci` | 4 | 5.5 | 7 |

## 前、main への push

| ジョブ | 最小 | 中央値 | 最大 |
|---|---|---|---|
| `changes` | 24 | 29 | 34 |
| `build (ubuntu-24.04, tests)` | 170 | 177.5 | 185 |
| `build (ubuntu-24.04, outputs)` | 396 | 422.5 | 449 |
| `build (ubuntu-24.04-arm, all)` | 168 | 170 | 172 |
| `determinism` | 5 | 5 | 5 |
| `visual` | 211 | 216.5 | 222 |
| `release-scripts` | 17 | 17.5 | 18 |
| `scripts-macos` | 197 | 211.5 | 226 |
| `format` | 58 | 64.5 | 71 |
| `ci` | 5 | 5 | 5 |

## 後、プルリクエスト

| ジョブ | 最小 | 中央値 | 最大 |
|---|---|---|---|
| `changes` | 9 | 9 | 9 |
| `scripts-linux` | 32 | 32.5 | 33 |
| `build (ubuntu-24.04, tests)` | 157 | 162.5 | 168 |
| `build (ubuntu-24.04, outputs)` | 148 | 149.5 | 151 |
| `build (ubuntu-24.04, env)` | 66 | 69 | 72 |
| `build (ubuntu-24.04-arm, all)` | 172 | 174 | 176 |
| `determinism` | 4 | 4.5 | 5 |
| `visual` | 238 | 263 | 288 |
| `release-scripts` | 15 | 15.5 | 16 |
| `scripts-macos` | 99 | 109 | 119 |
| `format` | 65 | 68.5 | 72 |
| `ci` | 4 | 5 | 6 |

## 後、すべての入力

| ジョブ | 最小 | 中央値 | 最大 |
|---|---|---|---|
| `changes` | 9 | 9 | 9 |
| `scripts-linux` | 30 | 30.5 | 31 |
| `build (ubuntu-24.04, tests)` | 166 | 170.5 | 175 |
| `build (ubuntu-24.04, outputs)` | 146 | 148.5 | 151 |
| `build (ubuntu-24.04, env)` | 140 | 160.5 | 181 |
| `build (ubuntu-24.04-arm, all)` | 160 | 171.5 | 183 |
| `determinism` | 5 | 5.5 | 6 |
| `visual` | 155 | 195.5 | 236 |
| `release-scripts` | 16 | 17.5 | 19 |
| `scripts-macos` | 120 | 123 | 126 |
| `format` | 72 | 72.5 | 73 |
| `ci` | 4 | 4.5 | 5 |

## 読み方

`build (ubuntu-24.04, outputs)` は、プルリクエストで約 347 秒から約 150 秒に、すべての入力で約 423 秒から約 149 秒になった。
後の `outputs` と `env` の `cabal build` のログには `configuration changed` がなく、`cabal build` の手順は 16 秒から 19 秒だった（前は 181 秒から 211 秒）。
後の `visual` の始まりは、`build` の行列で最も遅い `tests` か aarch64 の `all` が決める。
`visual` 自身は 155 秒から 288 秒と揺れ、実行全体の揺れの大半はここから来る。
`scripts-macos` の短縮は、`scripts/env-determinism/check.sh` のロケールの探し方を一つの `awk` にしたことによる。
