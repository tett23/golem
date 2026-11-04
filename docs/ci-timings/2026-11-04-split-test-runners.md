# CI の所要時間（2026-11-04、build のテストを四つのランナーに分け、visual-pdfs を先に組んだ前後）

[ADR 0140](../adr/0140-ci-split-test-runners-and-visual-pdfs-first.md) の実装の前後の、プルリクエストの `ci.yml` の所要時間の記録である。
数字は `gh run view <id> --json jobs` から取った。
各ジョブの欄は、実行の最初のジョブの始まりから、そのジョブが終わるまでの秒数である。
実行全体は、最初のジョブの始まりから `ci` の終わりまでの秒数である。
2026-11-04 に作り、コミットした後は変更しない。

## 前

モジュールを変えず、`cabal build` が 13 秒から 72 秒で済んだプルリクエストの 7 回の実行である。
[ADR 0140](../adr/0140-ci-split-test-runners-and-visual-pdfs-first.md) の文脈の表の 10 回のうち、`cabal build` が 86 秒を超えた 3 回を除いた。

| 実行 | 実行全体 | `x-tests` | `arm-all` | `x-outputs` | `visual` | `x-env` | `determinism` |
|---|---|---|---|---|---|---|---|
| [41785790404](https://github.com/tett23/golem/actions/runs/41785790404) | 222 | 208 | 190 | 178 | 190 | 87 | 215 |
| [41785477761](https://github.com/tett23/golem/actions/runs/41785477761) | 236 | 224 | 207 | 139 | 147 | 99 | 229 |
| [41784899059](https://github.com/tett23/golem/actions/runs/41784899059) | 212 | 158 | 199 | 191 | 198 | 90 | 205 |
| [41783846229](https://github.com/tett23/golem/actions/runs/41783846229) | 225 | 210 | 184 | 141 | 146 | 85 | 219 |
| [41782495838](https://github.com/tett23/golem/actions/runs/41782495838) | 227 | 213 | 196 | 143 | 156 | 88 | 219 |
| [41781230608](https://github.com/tett23/golem/actions/runs/41781230608) | 245 | 210 | 222 | 227 | 238 | 125 | 233 |
| [41780771663](https://github.com/tett23/golem/actions/runs/41780771663) | 259 | 239 | 225 | 215 | 223 | 134 | 247 |

実行全体の中央値は 227 秒である。

## 後

このプルリクエスト（[#509](https://github.com/tett23/golem/pull/509)）の 2 回の実行である。
一回目は、開発者向けのマニュアルの章を直したことで `visual` が失敗した（参照を受け入れる前）。
`visual` の時間には、失敗の報告を作って上げる手順の約 10 秒が含まれる。

| 実行 | 実行全体 | `x-tests-driver` | `x-tests-rest` | `arm-tests` | `arm-outputs` | `x-outputs` | `visual` | `x-env` | `determinism` |
|---|---|---|---|---|---|---|---|---|---|
| [41814517417](https://github.com/tett23/golem/actions/runs/41814517417) | 170 | 152 | 155 | 156 | 99 | 147 | 141 | 78 | 163 |
| [41815303999](https://github.com/tett23/golem/actions/runs/41815303999) | 190 | 154 | 174 | 157 | 96 | 172 | 146 | 78 | 180 |

## 手順の時間

| 手順 | 前 | 後 |
|---|---|---|
| x86-64 のテスト（`cabal test`） | 75〜131（一つのランナー） | `tests-driver` 85、85。`tests-rest` 71、91 |
| aarch64 のテスト | 80〜87（`all`） | 85、85（`tests`） |
| aarch64 の決定性の検査の出力 | 23〜24（`all` の中） | 23、23（`outputs`） |
| x86-64 の `visual-pdfs` を組む手順 | 33〜54（決定性の検査の出力の後） | 41、55（ビルドの直後） |

## 読み方

実行全体は、中央値 227 秒（212〜259 秒）から、170 秒と 190 秒になった。
最後に終わる `build` のランナーと `visual` は、約 210 秒から 156 秒と 174 秒になった。
後の二回では、`build` の六つのランナーと `visual` が 141 秒から 174 秒のあいだに終わり、特定の一つが残らない。
二回目の `tests-rest` と `visual-pdfs` が遅いのは、x86-64 のランナーのマシンの違いによる揺れで、前の計測と同じ形である。

二回の実行で、x86-64 の `tests-driver` と `tests-rest` のログの `Test suite …: PASS` の和は 26 のスイートで、aarch64 の `tests` と同じ集合だった。
`modules/*/*.cabal` の `test-suite` の数も 26 である。
