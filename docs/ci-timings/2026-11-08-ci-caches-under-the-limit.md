# CI の所要時間とキャッシュの量（2026-11-08、プルリクエストが dist-newstyle を保存しなくなった前後）

[ADR 0228](../adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) の実装（[#691](https://github.com/tett23/golem/pull/691)、2026-11-08T04:08:19Z にマージ）の前後の、プルリクエストの `ci.yml` の所要時間と、リポジトリのキャッシュの量の記録である。
2026-11-08 に作り、コミットした後は変更しない。

## 条件

所要時間は、`build` まで走って成功したプルリクエストの実行で測った。
文書だけの変更で `build` を省いた実行（150 秒より短いもの）は除いた。
実行の秒は、`gh api repos/tett23/golem/actions/runs/<id>` の `run_started_at` から `updated_at` までである。
ジョブの表は、`gh run view <id> --json jobs -q .` を実行ごとに一行にし、`scripts/ci/timings.sh --median` に渡した出力から、ジョブ全体の行を抜いたものである。
単位は秒である。

前の実行は、マージの前に終わった直近の 10 回である。
後の実行は、マージの後に作られた 5 回である。
前も後も、プルリクエストの最初の push と二度め以降の push が混ざっていて、その割合はそろえていない。

## 実行

| 組 | 実行 |
|---|---|
| 前 | [42443760779](https://github.com/tett23/golem/actions/runs/42443760779)、[42443681209](https://github.com/tett23/golem/actions/runs/42443681209)、[42443655266](https://github.com/tett23/golem/actions/runs/42443655266)、[42443393558](https://github.com/tett23/golem/actions/runs/42443393558)、[42441981590](https://github.com/tett23/golem/actions/runs/42441981590)、[42440602180](https://github.com/tett23/golem/actions/runs/42440602180)、[42440584193](https://github.com/tett23/golem/actions/runs/42440584193)、[42439897432](https://github.com/tett23/golem/actions/runs/42439897432)、[42439466797](https://github.com/tett23/golem/actions/runs/42439466797)、[42438673112](https://github.com/tett23/golem/actions/runs/42438673112) |
| 後 | [42446247796](https://github.com/tett23/golem/actions/runs/42446247796)、[42446580883](https://github.com/tett23/golem/actions/runs/42446580883)、[42447033631](https://github.com/tett23/golem/actions/runs/42447033631)、[42447706410](https://github.com/tett23/golem/actions/runs/42447706410)、[42447843158](https://github.com/tett23/golem/actions/runs/42447843158) |

## 実行の全体

| 組 | 件数 | 最小 | 中央値 | 最大 | 各実行 |
|---|---|---|---|---|---|
| 前 | 10 | 236 | 310 | 514 | 236、247、268、272、310、310、313、387、425、514 |
| 後 | 5 | 279 | 297 | 392 | 279、284、297、353、392 |

[ADR 0228](../adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) が記録した 2026-11-07T07:11Z からの約 20 時間の値は、中央値 266 秒、第 3 四分位 344 秒（57 件）だった。
前の 10 回の中央値（310 秒）も後の 5 回の中央値（297 秒）も、CONTRIBUTING の 5 分（300 秒）の前後にある。
後の 5 回のうち 2 回（353 秒、392 秒）は 5 分を超えた。
件数が少なく、並んだ作業の数で実行の時間が変わるので、この差から前と後のどちらが速いかは言えない。

## ジョブ

| ジョブ | 前の最小 | 前の中央値 | 前の最大 | 後の最小 | 後の中央値 | 後の最大 |
|---|---|---|---|---|---|---|
| `changes` | 9 | 10.5 | 14 | 9 | 9 | 11 |
| `scripts-linux` | 63 | 69.5 | 75 | 65 | 70 | 71 |
| `build (ubuntu-24.04, tests-driver)` | 104 | 158 | 274 | 130 | 162 | 263 |
| `build (ubuntu-24.04, tests-rest)` | 118 | 211 | 383 | 150 | 201 | 298 |
| `build (ubuntu-24.04, outputs)` | 146 | 194 | 386 | 156 | 191 | 295 |
| `build (ubuntu-24.04, env)` | 89 | 135.5 | 323 | 111 | 144 | 189 |
| `build (ubuntu-24.04-arm, tests-driver)` | 111 | 141.5 | 297 | 141 | 152 | 226 |
| `build (ubuntu-24.04-arm, tests-rest)` | 131 | 154 | 300 | 160 | 176 | 239 |
| `build (ubuntu-24.04-arm, outputs)` | 77 | 97 | 230 | 106 | 126 | 195 |
| `wasm` | 130 | 193 | 320 | 124 | 138 | 242 |
| `visual` | 90 | 137 | 317 | 119 | 132 | 231 |
| `determinism` | 6 | 7.5 | 10 | 7 | 9 | 9 |
| `verapdf` | 52 | 67 | 81 | 52 | 68 | 79 |
| `release-scripts` | 16 | 17 | 21 | 14 | 15 | 17 |
| `scripts-macos` | 91 | 104.5 | 128 | 92 | 104 | 115 |
| `format` | 66 | 83 | 107 | 69 | 81 | 106 |
| `plugins` | 49 | 61 | 65 | 47 | 60 | 64 |
| `editors` | 14 | 16 | 28 | 16 | 18 | 21 |
| `ci` | 5 | 6 | 8 | 5 | 7 | 8 |

後の実行では、`caches` はプルリクエストなので省かれる。
`build` の `tests-driver` は、プルリクエストの保存のステップがなくなったが、中央値はほとんど変わらない。

## キャッシュの量

`gh api repos/tett23/golem/actions/caches --paginate` の一覧の `size_in_bytes` を足した。

| 時刻 | `main` の `dist-` | `main` のそのほか | プルリクエストの `dist-` | 合計 |
|---|---|---|---|---|
| 2026-11-08T04:08:34Z（最初の `caches` の前） | 15 個、5,036,061,788 | 14 個、1,986,859,669 | 8 個、3,560,752,154 | 37 個、10,583,673,611 |
| 2026-11-08T04:13:39Z（最初の `caches` の後） | 3 個、1,007,343,354 | 14 個、1,986,859,669 | 8 個、3,560,752,154 | 25 個、6,554,955,177 |
| 2026-11-08T04:48:15Z（さらに三つの `main` への push の後） | 3 個、1,007,658,617 | 14 個、1,986,859,669 | 8 個、3,560,752,154 | 25 個、6,555,270,440 |

最初の `caches` は、マージの `main` への push の実行 [42445577014](https://github.com/tett23/golem/actions/runs/42445577014) のジョブで、12 個の `dist-` を消した（x86-64 の `dist-newstyle` が 4 個、aarch64 が 4 個、`dist-wasm` が 4 個）。
残ったのは三つの族に一つずつで、どれも一つ前の `main` への push（`5109605`）が保存したものである。
マージの push は Haskell のソースを変えておらず、`cabal build` が何もコンパイルしなかったので、`dist-newstyle` を保存しなかった（I2）。
`dist-` でない `main` のキャッシュの数と、プルリクエストのキャッシュの数は変わらなかった（I4）。
その後の二つの実行（[42446603603](https://github.com/tett23/golem/actions/runs/42446603603)、[42447038844](https://github.com/tett23/golem/actions/runs/42447038844)）の `caches` も成功し、04:48:15Z の `main` の `dist-` は三つの族に一つずつだった（I3）。
プルリクエストの 8 個（3.56 GB）は、マージの前に保存したもので、使われないまま 7 日で GitHub が消す。
