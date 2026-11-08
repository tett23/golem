# CI の臨界経路と、取得の失敗（2026-11-09、`ci.yml` の 400 回の実行）

CI を速くし、ネットワークの失敗に強くする ADR（[ADR 0243](../adr/0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)、[ADR 0244](../adr/0244-take-verapdf-off-the-critical-path-of-ci.md)）のために、`ci.yml` の直近の実行を数えた記録である。
2026-11-09 に作り、コミットした後は変更しない。

## 条件

- 対象は、`gh run list --repo tett23/golem -w ci.yml -L 400` が 2026-11-09T00Z ごろに返した 400 回の実行である。作られた時刻は 2026-11-07T06:22:38Z から 2026-11-08T22:19:53Z までの約 40 時間に収まる。
- 各実行のジョブと手順は `gh api repos/tett23/golem/actions/runs/<id>/jobs?per_page=100` で取った。再実行した 8 回の実行は、前の試行も `.../runs/<id>/attempts/<n>/jobs` で取った（11 の試行）。
- 失敗した実行は `gh run view <id> --log-failed` で、再実行の前の試行の失敗したジョブは `gh api repos/tett23/golem/actions/jobs/<job id>/logs` で、ログを取った。
- 実行全体の秒は、その実行で最初に作られたジョブの `created_at` から、最後に終わったジョブの `completed_at` までである。待ち行列の秒は、ジョブの `created_at` から `started_at` まで、実行の秒は `started_at` から `completed_at` までである。
- 「終わり」の秒は、その実行で最初に始まったジョブの `started_at` から、そのジョブの `completed_at` までである。
- 第 3 四分位と第 9 十分位は、並べた値のあいだを線形に補間した。
- 「`build` が走って成功」は、結論が成功で、`build (ubuntu-24.04, tests-driver)` が省かれなかった実行である。文書だけの変更で `build` を省いた実行（`pull_request` の 39 回）は、実行全体が 70 秒前後なので除いた。
- 「`verapdf` を臨界経路から外したと仮定」の行は、`verapdf`、`determinism`、`ci` を除くジョブの最後の終わりに、`determinism` の中央値 7 秒と `ci` の中央値 6 秒を足した値である。[ADR 0244](../adr/0244-take-verapdf-off-the-critical-path-of-ci.md) の見積もりに使った。
- 集計は手元の一時的なスクリプト（jq と Python）で行い、コミットしていない。表の値は `scripts/ci/timings.sh --median` の形に合わせていない。

## 表 1 実行の内訳

| イベント | 結論 | 件数 |
|---|---|---|
| `pull_request` | cancelled | 39 |
| `pull_request` | failure | 76 |
| `pull_request` | success | 157 |
| `push` | (進行中) | 1 |
| `push` | failure | 5 |
| `push` | success | 122 |

## 表 2 実行全体の秒（最初のジョブの作成から最後のジョブの終わりまで）

| 組 | 件数 | 最小 | 中央値 | 第 3 四分位 | 第 9 十分位 | 最大 | 300 秒超 |
|---|---|---|---|---|---|---|---|
| `pull_request`、`build` が走って成功 | 118 | 22 | 298 | 376 | 452 | 1105 | 56（47%） |
| 同、`verapdf` を臨界経路から外したと仮定 | 118 | 27 | 234 | 322 | 397 | 1109 | 34（29%） |
| `push`、`build` が走って成功 | 86 | 255 | 372 | 452 | 518 | 991 | 77（90%） |
| 同、`verapdf` を臨界経路から外したと仮定 | 86 | 198 | 328 | 400 | 460 | 996 | 49（57%） |

## 表 3 最後に終わるジョブと、最後に終わる `build` のランナー

- `pull_request`（118 件）。最後に終わるジョブ（`ci` を除く）：`verapdf` 115、`wasm` 2、`visual` 1。
  最後に終わる `build` のランナー：`build (ubuntu-24.04, outputs)` 62、`build (ubuntu-24.04, tests-rest)` 44、`build (ubuntu-24.04-arm, tests-rest)` 7、`build (ubuntu-24.04-arm, tests-driver)` 2、`build (ubuntu-24.04, env)` 2、`build (ubuntu-24.04, tests-driver)` 1。
  `verapdf` の終わりから最後の `build` の終わりを引いた秒：中央値 68、第 3 四分位 77、最大 111。
- `push`（86 件）。最後に終わるジョブ（`ci` を除く）：`verapdf` 82、`wasm` 3、`format` 1。
  最後に終わる `build` のランナー：`build (ubuntu-24.04, env)` 77、`build (ubuntu-24.04, outputs)` 6、`build (ubuntu-24.04, tests-rest)` 2、`build (ubuntu-24.04-arm, outputs)` 1。
  `verapdf` の終わりから最後の `build` の終わりを引いた秒：中央値 71、第 3 四分位 75、最大 112。

## 表 4 ジョブごとの秒（`pull_request`、118 件）

| ジョブ | 件数 | 待ち行列の中央値 | 実行の最小 | 中央値 | 第 3 四分位 | 第 9 十分位 | 最大 | 終わりの中央値 | 終わりの第 9 十分位 |
|---|---|---|---|---|---|---|---|---|---|
| `ci` | 118 | 2 | 4 | 6 | 7 | 7 | 9 | 300 | 473 |
| `verapdf` | 118 | 2 | 43 | 66 | 75 | 77 | 85 | 291 | 459 |
| `determinism` | 118 | 2 | 5 | 7 | 9 | 9 | 13 | 228 | 409 |
| `build (ubuntu-24.04, outputs)` | 118 | 2 | 114 | 191 | 270 | 329 | 438 | 207 | 356 |
| `build (ubuntu-24.04, tests-rest)` | 118 | 2 | 106 | 173 | 229 | 313 | 385 | 186 | 333 |
| `wasm` | 97 | 2 | 101 | 154 | 230 | 290 | 1082 | 171 | 311 |
| `build (ubuntu-24.04-arm, tests-rest)` | 118 | 4 | 116 | 152 | 220 | 289 | 377 | 171 | 314 |
| `build (ubuntu-24.04, tests-driver)` | 118 | 2 | 91 | 146 | 218 | 272 | 363 | 166 | 303 |
| `build (ubuntu-24.04-arm, tests-driver)` | 118 | 4 | 91 | 142 | 211 | 279 | 374 | 156 | 298 |
| `build (ubuntu-24.04, env)` | 118 | 2 | 86 | 130 | 195 | 263 | 340 | 150 | 302 |
| `visual` | 118 | 2 | 12 | 130 | 203 | 257 | 382 | 146 | 292 |
| `build (ubuntu-24.04-arm, outputs)` | 118 | 4 | 72 | 101 | 170 | 235 | 316 | 118 | 258 |
| `scripts-macos` | 118 | 2 | 81 | 104 | 114 | 125 | 148 | 117 | 139 |
| `editors-lsp` | 39 | 2 | 45 | 100 | 158 | 214 | 257 | 116 | 230 |
| `format` | 118 | 2 | 62 | 86 | 103 | 107 | 241 | 99 | 123 |
| `plugins` | 118 | 2 | 39 | 59 | 61 | 62 | 65 | 71 | 77 |
| `scripts-linux` | 118 | 2 | 59 | 69 | 72 | 77 | 89 | 69 | 77 |
| `release-scripts` | 118 | 2 | 13 | 17 | 19 | 23 | 110 | 30 | 38 |
| `editors` | 118 | 2 | 13 | 18 | 21 | 26 | 35 | 18 | 26 |
| `changes` | 118 | 2 | 8 | 11 | 12 | 13 | 19 | 11 | 14 |

## 表 4 ジョブごとの秒（`push`、86 件）

| ジョブ | 件数 | 待ち行列の中央値 | 実行の最小 | 中央値 | 第 3 四分位 | 第 9 十分位 | 最大 | 終わりの中央値 | 終わりの第 9 十分位 |
|---|---|---|---|---|---|---|---|---|---|
| `ci` | 86 | 2 | 4 | 6 | 7 | 8 | 10 | 370 | 516 |
| `verapdf` | 86 | 2 | 43 | 69 | 73 | 78 | 96 | 356 | 505 |
| `caches` | 35 | 2 | 6 | 8 | 9 | 11 | 12 | 311 | 415 |
| `determinism` | 86 | 2 | 5 | 8 | 9 | 9 | 12 | 298 | 448 |
| `build (ubuntu-24.04, env)` | 86 | 2 | 172 | 275 | 352 | 419 | 492 | 287 | 432 |
| `build (ubuntu-24.04, outputs)` | 86 | 2 | 120 | 221 | 300 | 347 | 424 | 236 | 360 |
| `build (ubuntu-24.04, tests-rest)` | 86 | 2 | 107 | 193 | 268 | 308 | 381 | 210 | 320 |
| `build (ubuntu-24.04-arm, tests-rest)` | 86 | 4 | 114 | 168 | 249 | 278 | 334 | 189 | 296 |
| `build (ubuntu-24.04, tests-driver)` | 86 | 2 | 87 | 170 | 256 | 296 | 378 | 186 | 316 |
| `build (ubuntu-24.04-arm, tests-driver)` | 86 | 4 | 104 | 164 | 234 | 267 | 325 | 183 | 284 |
| `wasm` | 68 | 2 | 100 | 154 | 247 | 291 | 971 | 168 | 305 |
| `visual` | 86 | 2 | 80 | 148 | 243 | 274 | 318 | 162 | 288 |
| `build (ubuntu-24.04-arm, outputs)` | 86 | 4 | 74 | 120 | 207 | 225 | 268 | 138 | 239 |
| `scripts-macos` | 86 | 2 | 80 | 106 | 116 | 122 | 148 | 120 | 138 |
| `editors-lsp` | 26 | 2 | 50 | 97 | 154 | 221 | 259 | 116 | 236 |
| `format` | 86 | 2 | 61 | 98 | 105 | 110 | 368 | 112 | 125 |
| `scripts-linux` | 86 | 2 | 59 | 70 | 73 | 78 | 90 | 70 | 79 |
| `plugins` | 86 | 2 | 41 | 56 | 61 | 62 | 64 | 70 | 77 |
| `release-scripts` | 86 | 2 | 13 | 17 | 18 | 22 | 30 | 30 | 38 |
| `editors` | 86 | 2 | 13 | 18 | 21 | 24 | 30 | 18 | 25 |
| `changes` | 86 | 2 | 8 | 11 | 12 | 12 | 14 | 11 | 13 |

## 表 5 手順ごとの秒（`pull_request`、118 件。中央値が 2 秒未満で最大が 20 秒未満の手順は省く）

| ジョブ | 手順 | 件数 | 最小 | 中央値 | 第 3 四分位 | 第 9 十分位 | 最大 |
|---|---|---|---|---|---|---|---|
| `build (ubuntu-24.04, outputs)` | `Run actions/checkout@v7` | 118 | 1 | 2 | 3 | 3 | 4 |
| `build (ubuntu-24.04, outputs)` | `Cache GHC (docs/adr/0009, docs/adr/0141)` | 118 | 2 | 3 | 4 | 5 | 6 |
| `build (ubuntu-24.04, outputs)` | `Run haskell-actions/setup@v2` | 118 | 3 | 6 | 7 | 8 | 11 |
| `build (ubuntu-24.04, outputs)` | `Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)` | 118 | 2 | 3 | 4 | 4 | 6 |
| `build (ubuntu-24.04, outputs)` | `Cache the cabal store` | 118 | 2 | 4 | 4 | 5 | 7 |
| `build (ubuntu-24.04, outputs)` | `Restore dist-newstyle (docs/adr/0009)` | 118 | 4 | 9 | 10 | 11 | 17 |
| `build (ubuntu-24.04, outputs)` | `wasmtime C API (golem-plugin ADR 0001)` | 118 | 1 | 2 | 2 | 2 | 106 |
| `build (ubuntu-24.04, outputs)` | `cabal build all peg-cli:exe:peg-hs` | 118 | 2 | 31 | 94 | 165 | 272 |
| `build (ubuntu-24.04, outputs)` | `golem is linked with the wasmtime of fetch-wasmtime.sh (docs/adr/0156)` | 118 | 1 | 2 | 2 | 2 | 2 |
| `build (ubuntu-24.04, outputs)` | `The PDFs of the visual regression test (docs/adr/0095)` | 118 | 28 | 47 | 52 | 54 | 61 |
| `build (ubuntu-24.04, outputs)` | `Upload the PDFs of the visual regression test` | 118 | 1 | 2 | 3 | 3 | 5 |
| `build (ubuntu-24.04, outputs)` | `The EPUB passes epubcheck` | 118 | 3 | 5 | 6 | 6 | 8 |
| `build (ubuntu-24.04, outputs)` | `The EPUB of several bibliographies passes epubcheck` | 118 | 3 | 5 | 5 | 5 | 6 |
| `build (ubuntu-24.04, outputs)` | `Outputs for the determinism check; the manuals build without diagnostics` | 118 | 18 | 30 | 33 | 35 | 38 |
| `build (ubuntu-24.04, outputs)` | `The user manual (docs/adr/0022)` | 118 | 1 | 2 | 3 | 3 | 4 |
| `build (ubuntu-24.04, outputs)` | `The developer manual (docs/adr/0024)` | 118 | 1 | 2 | 3 | 3 | 7 |
| `build (ubuntu-24.04, outputs)` | `The PDFs that declare PDF/A-2a and PDF/UA-1 (docs/adr/0183)` | 118 | 5 | 7 | 8 | 9 | 9 |
| `build (ubuntu-24.04, outputs)` | `Upload the PDFs that declare PDF/A-2a and PDF/UA-1` | 118 | 1 | 2 | 2 | 2 | 3 |
| `build (ubuntu-24.04, outputs)` | `The native list of the comparison with golem.wasm (docs/adr/0199)` | 97 | 4 | 6 | 6 | 7 | 8 |
| `build (ubuntu-24.04, outputs)` | `The EPUB with languages passes epubcheck` | 81 | 3 | 5 | 5 | 6 | 6 |
| `build (ubuntu-24.04, outputs)` | `Upload golem for the job editors-lsp (docs/adr/0231)` | 39 | 3 | 4 | 5 | 5 | 6 |
| `build (ubuntu-24.04, outputs)` | `The preflight of the manuals (docs/adr/0232)` | 31 | 21 | 31 | 36 | 37 | 39 |
| `build (ubuntu-24.04, outputs)` | `The EPUB of epub-forms passes epubcheck (docs/adr/0232)` | 29 | 3 | 5 | 5 | 6 | 6 |
| `build (ubuntu-24.04, tests-rest)` | `Run actions/checkout@v7` | 118 | 1 | 2 | 3 | 3 | 5 |
| `build (ubuntu-24.04, tests-rest)` | `Cache GHC (docs/adr/0009, docs/adr/0141)` | 118 | 2 | 4 | 4 | 5 | 9 |
| `build (ubuntu-24.04, tests-rest)` | `Run haskell-actions/setup@v2` | 118 | 4 | 6 | 7 | 8 | 10 |
| `build (ubuntu-24.04, tests-rest)` | `Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)` | 118 | 2 | 3 | 4 | 4 | 7 |
| `build (ubuntu-24.04, tests-rest)` | `Cache the cabal store` | 118 | 2 | 4 | 4 | 5 | 5 |
| `build (ubuntu-24.04, tests-rest)` | `Restore dist-newstyle (docs/adr/0009)` | 118 | 4 | 10 | 11 | 11 | 13 |
| `build (ubuntu-24.04, tests-rest)` | `wasmtime C API (golem-plugin ADR 0001)` | 118 | 1 | 2 | 2 | 3 | 114 |
| `build (ubuntu-24.04, tests-rest)` | `cabal build all peg-cli:exe:peg-hs` | 118 | 2 | 29 | 96 | 173 | 237 |
| `build (ubuntu-24.04, tests-rest)` | `The test suites of the runner (docs/adr/0140)` | 118 | 60 | 99 | 119 | 123 | 133 |
| `build (ubuntu-24.04, tests-driver)` | `Run actions/checkout@v7` | 118 | 2 | 3 | 3 | 3 | 4 |
| `build (ubuntu-24.04, tests-driver)` | `Cache GHC (docs/adr/0009, docs/adr/0141)` | 118 | 2 | 4 | 5 | 5 | 10 |
| `build (ubuntu-24.04, tests-driver)` | `Run haskell-actions/setup@v2` | 118 | 4 | 6 | 7 | 8 | 14 |
| `build (ubuntu-24.04, tests-driver)` | `Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)` | 118 | 2 | 3 | 4 | 4 | 6 |
| `build (ubuntu-24.04, tests-driver)` | `Cache the cabal store` | 118 | 2 | 3 | 4 | 5 | 6 |
| `build (ubuntu-24.04, tests-driver)` | `Restore dist-newstyle (docs/adr/0009)` | 118 | 4 | 9 | 10 | 11 | 13 |
| `build (ubuntu-24.04, tests-driver)` | `wasmtime C API (golem-plugin ADR 0001)` | 118 | 1 | 2 | 2 | 2 | 125 |
| `build (ubuntu-24.04, tests-driver)` | `cabal build all peg-cli:exe:peg-hs` | 118 | 2 | 30 | 98 | 161 | 248 |
| `build (ubuntu-24.04, tests-driver)` | `The test suites of the runner (docs/adr/0140)` | 118 | 41 | 71 | 86 | 96 | 103 |
| `build (ubuntu-24.04, tests-driver)` | `Save dist-newstyle of the pull request (docs/adr/0045)` | 39 | 4 | 5 | 6 | 7 | 31 |
| `build (ubuntu-24.04, env)` | `Run actions/checkout@v7` | 118 | 2 | 2 | 3 | 3 | 6 |
| `build (ubuntu-24.04, env)` | `Cache GHC (docs/adr/0009, docs/adr/0141)` | 118 | 2 | 3 | 4 | 4 | 5 |
| `build (ubuntu-24.04, env)` | `Run haskell-actions/setup@v2` | 118 | 4 | 5 | 6 | 7 | 10 |
| `build (ubuntu-24.04, env)` | `Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)` | 118 | 2 | 3 | 4 | 4 | 7 |
| `build (ubuntu-24.04, env)` | `Cache the cabal store` | 118 | 2 | 4 | 5 | 5 | 8 |
| `build (ubuntu-24.04, env)` | `Restore dist-newstyle (docs/adr/0009)` | 118 | 5 | 8 | 11 | 11 | 12 |
| `build (ubuntu-24.04, env)` | `wasmtime C API (golem-plugin ADR 0001)` | 118 | 1 | 2 | 2 | 3 | 115 |
| `build (ubuntu-24.04, env)` | `cabal build all peg-cli:exe:peg-hs` | 118 | 2 | 32 | 96 | 177 | 233 |
| `build (ubuntu-24.04, env)` | `The outputs do not change with the environment (docs/adr/0029, docs/adr/0038)` | 118 | 43 | 62 | 65 | 66 | 67 |
| `build (ubuntu-24.04-arm, tests-rest)` | `Run actions/checkout@v7` | 118 | 1 | 2 | 2 | 3 | 3 |
| `build (ubuntu-24.04-arm, tests-rest)` | `Cache GHC (docs/adr/0009, docs/adr/0141)` | 118 | 2 | 3 | 3 | 3 | 4 |
| `build (ubuntu-24.04-arm, tests-rest)` | `Run haskell-actions/setup@v2` | 118 | 7 | 8 | 10 | 10 | 11 |
| `build (ubuntu-24.04-arm, tests-rest)` | `Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)` | 118 | 1 | 2 | 3 | 3 | 4 |
| `build (ubuntu-24.04-arm, tests-rest)` | `Cache the cabal store` | 118 | 3 | 5 | 5 | 5 | 7 |
| `build (ubuntu-24.04-arm, tests-rest)` | `Restore dist-newstyle (docs/adr/0009)` | 118 | 10 | 13 | 14 | 15 | 21 |
| `build (ubuntu-24.04-arm, tests-rest)` | `wasmtime C API (golem-plugin ADR 0001)` | 118 | 1 | 2 | 2 | 2 | 5 |
| `build (ubuntu-24.04-arm, tests-rest)` | `cabal build all peg-cli:exe:peg-hs` | 118 | 2 | 26 | 96 | 163 | 246 |
| `build (ubuntu-24.04-arm, tests-rest)` | `golem is linked with the wasmtime of fetch-wasmtime.sh (docs/adr/0156)` | 118 | 1 | 2 | 2 | 2 | 2 |
| `build (ubuntu-24.04-arm, tests-rest)` | `The test suites of the runner (docs/adr/0140)` | 118 | 70 | 84 | 87 | 89 | 92 |
| `build (ubuntu-24.04-arm, tests-driver)` | `Run actions/checkout@v7` | 118 | 1 | 2 | 2 | 2 | 3 |
| `build (ubuntu-24.04-arm, tests-driver)` | `Cache GHC (docs/adr/0009, docs/adr/0141)` | 118 | 2 | 3 | 3 | 3 | 4 |
| `build (ubuntu-24.04-arm, tests-driver)` | `Run haskell-actions/setup@v2` | 118 | 6 | 8 | 9 | 10 | 27 |
| `build (ubuntu-24.04-arm, tests-driver)` | `Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)` | 118 | 1 | 2 | 3 | 3 | 4 |
| `build (ubuntu-24.04-arm, tests-driver)` | `Cache the cabal store` | 118 | 4 | 5 | 5 | 5 | 6 |
| `build (ubuntu-24.04-arm, tests-driver)` | `Restore dist-newstyle (docs/adr/0009)` | 118 | 10 | 12 | 14 | 14 | 16 |
| `build (ubuntu-24.04-arm, tests-driver)` | `wasmtime C API (golem-plugin ADR 0001)` | 118 | 1 | 2 | 2 | 2 | 139 |
| `build (ubuntu-24.04-arm, tests-driver)` | `cabal build all peg-cli:exe:peg-hs` | 118 | 2 | 26 | 98 | 162 | 255 |
| `build (ubuntu-24.04-arm, tests-driver)` | `golem is linked with the wasmtime of fetch-wasmtime.sh (docs/adr/0156)` | 118 | 1 | 2 | 2 | 2 | 2 |
| `build (ubuntu-24.04-arm, tests-driver)` | `The test suites of the runner (docs/adr/0140)` | 118 | 47 | 68 | 74 | 77 | 80 |
| `build (ubuntu-24.04-arm, tests-driver)` | `Save dist-newstyle of the pull request (docs/adr/0045)` | 38 | 5 | 6 | 6 | 7 | 8 |
| `build (ubuntu-24.04-arm, outputs)` | `Run actions/checkout@v7` | 118 | 1 | 2 | 2 | 2 | 3 |
| `build (ubuntu-24.04-arm, outputs)` | `Cache GHC (docs/adr/0009, docs/adr/0141)` | 118 | 1 | 2 | 3 | 3 | 5 |
| `build (ubuntu-24.04-arm, outputs)` | `Run haskell-actions/setup@v2` | 118 | 6 | 8 | 9 | 9 | 14 |
| `build (ubuntu-24.04-arm, outputs)` | `Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)` | 118 | 1 | 2 | 2 | 3 | 4 |
| `build (ubuntu-24.04-arm, outputs)` | `Cache the cabal store` | 118 | 3 | 5 | 5 | 5 | 6 |
| `build (ubuntu-24.04-arm, outputs)` | `Restore dist-newstyle (docs/adr/0009)` | 118 | 10 | 12 | 13 | 14 | 16 |
| `build (ubuntu-24.04-arm, outputs)` | `wasmtime C API (golem-plugin ADR 0001)` | 118 | 1 | 2 | 2 | 2 | 21 |
| `build (ubuntu-24.04-arm, outputs)` | `cabal build all peg-cli:exe:peg-hs` | 118 | 2 | 26 | 92 | 158 | 242 |
| `build (ubuntu-24.04-arm, outputs)` | `golem is linked with the wasmtime of fetch-wasmtime.sh (docs/adr/0156)` | 118 | 1 | 2 | 2 | 2 | 7 |
| `build (ubuntu-24.04-arm, outputs)` | `Outputs for the determinism check; the manuals build without diagnostics` | 118 | 28 | 32 | 34 | 34 | 38 |
| `verapdf` | `Run actions/checkout@v7` | 118 | 1 | 3 | 3 | 3 | 6 |
| `verapdf` | `Run cachix/install-nix-action@v31` | 118 | 3 | 4 | 4 | 5 | 6 |
| `verapdf` | `veraPDF from nixpkgs, at the store path of VERAPDF_STORE_PATH` | 118 | 13 | 20 | 24 | 27 | 32 |
| `verapdf` | `The PDFs pass PDF/A-2a and PDF/UA-1` | 118 | 20 | 33 | 39 | 39 | 42 |
| `visual` | `Run actions/checkout@v7` | 118 | 3 | 4 | 4 | 5 | 8 |
| `visual` | `Wait for the PDFs of the visual regression test (docs/adr/0099)` | 118 | 0 | 116 | 187 | 242 | 368 |
| `visual` | `Run actions/download-artifact@v8` | 118 | 0 | 2 | 2 | 3 | 4 |
| `visual` | `The pages match the references (docs/adr/0094, docs/adr/0095)` | 118 | 2 | 3 | 4 | 4 | 4 |
| `wasm` | `Run actions/checkout@v7` | 97 | 1 | 2 | 3 | 3 | 7 |
| `wasm` | `Run actions/setup-node@v7` | 97 | 4 | 5 | 5 | 6 | 7 |
| `wasm` | `Run haskell-actions/setup@v2` | 1 | 134 | 134 | 134 | 134 | 134 |
| `wasm` | `The native alex and happy (docs/adr/0202)` | 1 | 22 | 22 | 22 | 22 | 22 |
| `wasm` | `The wasm toolchain (docs/adr/0199)` | 97 | 0 | 0 | 1 | 1 | 114 |
| `wasm` | `The Hackage index of the wasm build` | 1 | 16 | 16 | 16 | 16 | 16 |
| `wasm` | `Restore dist-wasm` | 97 | 1 | 2 | 3 | 3 | 7 |
| `wasm` | `golem.wasm (docs/adr/0199)` | 97 | 1 | 12 | 55 | 102 | 669 |
| `wasm` | `Restore the wasm toolchain and its cabal store (docs/adr/0199)` | 97 | 1 | 31 | 34 | 35 | 94 |
| `wasm` | `Save the wasm toolchain and its cabal store` | 1 | 14 | 14 | 14 | 14 | 14 |
| `wasm` | `Save dist-wasm` | 7 | 2 | 3 | 4 | 4 | 4 |
| `wasm` | `The checks of golem.wasm under node:wasi (docs/adr/0199)` | 97 | 29 | 46 | 57 | 59 | 63 |
| `wasm` | `The PDFs and the diagnostics of golem.wasm (docs/adr/0199)` | 97 | 17 | 31 | 34 | 37 | 48 |
| `wasm` | `Run actions/upload-artifact@v7` | 97 | 1 | 2 | 3 | 3 | 4 |
| `wasm` | `Wait for the native list of the outputs runner` | 97 | 0 | 1 | 22 | 77 | 120 |
| `editors-lsp` | `Run actions/checkout@v7` | 39 | 1 | 3 | 3 | 3 | 4 |
| `editors-lsp` | `Wait for golem of the outputs runner (docs/adr/0231)` | 39 | 34 | 88 | 144 | 202 | 244 |
| `editors-lsp` | `Run actions/download-artifact@v8` | 39 | 1 | 2 | 3 | 3 | 7 |
| `editors-lsp` | `golem lsp in a headless Neovim (docs/adr/0231)` | 39 | 2 | 3 | 3 | 4 | 4 |
| `format` | `Run actions/checkout@v7` | 118 | 1 | 3 | 3 | 3 | 5 |
| `format` | `Run haskell-actions/run-fourmolu@v13` | 118 | 11 | 16 | 19 | 20 | 155 |
| `format` | `Run "$HOME/.local/bin/hlint" -j modules --ignore-glob="modules/golem-parser/src/Golem/Parser/Generated.hs" --ignore-glob="modules/golem-parser/test/StrippedGrammar.hs" --ignore-glob="modules/golem-emet/src/Golem/Emet/Generated.hs"` | 14 | 44 | 55 | 69 | 73 | 76 |
| `format` | `Run "$HOME/.local/bin/hlint" -j modules --ignore-glob="modules/golem-parser/src/Golem/Parser/Generated.hs" --ignore-glob="modules/golem-parser/test/StrippedGrammar.hs" --ignore-glob="modules/golem-emet/src/Golem/Emet/Generated.hs" --ignore-glob="modules/golem-driver/src/Golem/Driver/Version/Embedded.hs" --ignore-glob="modules/golem-driver/src/Golem/Driver/Explain/Embedded.hs"` | 104 | 48 | 64 | 77 | 80 | 90 |
| `scripts-macos` | `Run actions/checkout@v7` | 118 | 3 | 6 | 6 | 7 | 10 |
| `scripts-macos` | `Tests of the scripts (CI, manuals, environment check, release, by hand, visual regression test)` | 118 | 72 | 94 | 101 | 112 | 136 |
| `scripts-linux` | `Run actions/checkout@v7` | 118 | 2 | 3 | 3 | 3 | 3 |
| `scripts-linux` | `Tests of the CI scripts (docs/adr/0009)` | 118 | 14 | 17 | 18 | 19 | 23 |
| `scripts-linux` | `Tests of the environment check (docs/adr/0029)` | 118 | 5 | 8 | 9 | 10 | 13 |
| `scripts-linux` | `Tests of the scripts run by hand (docs/adr/0078)` | 118 | 2 | 3 | 3 | 4 | 5 |
| `scripts-linux` | `Tests of the scripts of the visual regression test (docs/adr/0093)` | 118 | 31 | 33 | 36 | 37 | 39 |
| `scripts-linux` | `Run actions/setup-node@v7` | 20 | 4 | 5 | 5 | 5 | 6 |
| `plugins` | `Run actions/checkout@v7` | 118 | 2 | 3 | 3 | 3 | 4 |
| `plugins` | `Tests of the crates` | 118 | 20 | 30 | 31 | 32 | 34 |
| `plugins` | `The committed plugins are what the sources build` | 118 | 12 | 20 | 21 | 22 | 23 |
| `plugins` | `The license documents of the plugins are up to date` | 118 | 1 | 2 | 2 | 3 | 3 |
| `editors` | `Run actions/checkout@v7` | 117 | 2 | 3 | 3 | 3 | 4 |
| `editors` | `Run actions/setup-node@v7` | 117 | 4 | 5 | 5 | 6 | 7 |
| `editors` | `Tests of the editor grammars (docs/adr/0170)` | 117 | 2 | 4 | 4 | 10 | 19 |

## 表 6 取得とキャッシュの手順（400 実行のすべての試行の最新、結論を問わない）

| 手順 | 件数 | 中央値 | 第 9 十分位 | 最大 | しきい値 | しきい値超 | 失敗 |
|---|---|---|---|---|---|---|---|
| `wasmtime C API (golem-plugin ADR 0001)` | 2219 | 2 | 3 | 210 | 20 | 26（11 実行） | 11 |
| `The wasm toolchain (docs/adr/0199)` | 246 | 0 | 1 | 114 | 60 | 4（4 実行） | 0 |
| `Restore the wasm toolchain and its cabal store (docs/adr/0199)` | 244 | 31 | 36 | 94 | 60 | 1（1 実行） | 0 |
| `hlint 3.10` | 296 | 1 | 1 | 36 | 20 | 1（1 実行） | 1 |
| `Run cachix/install-nix-action@v31` | 282 | 4 | 5 | 6 | 20 | 0（0 実行） | 0 |
| `veraPDF from nixpkgs, at the store path of VERAPDF_STORE_PATH` | 281 | 21 | 27 | 46 | 60 | 0（0 実行） | 1 |
| `Cache shem (docs/adr/0093)` | 319 | 1 | 2 | 2 | 10 | 0（0 実行） | 0 |
| `shem (docs/adr/0093)` | 319 | 0 | 0 | 1 | 10 | 0（0 実行） | 0 |
| `Cache Neovim (docs/adr/0231)` | 99 | 1 | 2 | 5 | 10 | 0（0 実行） | 0 |
| `Neovim (docs/adr/0231)` | 99 | 0 | 0 | 2 | 10 | 0（0 実行） | 0 |
| `golem lsp in a headless Neovim (docs/adr/0231)` | 93 | 3 | 4 | 5 | 10 | 0（0 実行） | 0 |
| `The grammars in Helix, by the README (docs/adr/0231)` | 128 | 1 | 1 | 11 | 60 | 0（0 実行） | 0 |
| `Run haskell-actions/setup@v2` | 2232 | 7 | 9 | 143 | 60 | 5（5 実行） | 0 |
| `Cache GHC (docs/adr/0009, docs/adr/0141)` | 2229 | 3 | 4 | 10 | 30 | 0（0 実行） | 0 |
| `Cache the cabal store` | 2225 | 4 | 5 | 9 | 30 | 0（0 実行） | 0 |
| `Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)` | 2225 | 3 | 4 | 7 | 30 | 0（0 実行） | 0 |
| `Restore dist-newstyle (docs/adr/0009)` | 2225 | 11 | 14 | 28 | 30 | 0（0 実行） | 0 |
| `Restore dist-wasm` | 244 | 3 | 4 | 7 | 30 | 0（0 実行） | 0 |
| `Run haskell-actions/run-fourmolu@v13` | 317 | 16 | 20 | 396 | 60 | 7（7 実行） | 21 |
| `Cache the release of epubcheck (docs/adr/0062)` | 319 | 1 | 2 | 5 | 20 | 0（0 実行） | 0 |
| `epubcheck is installed` | 304 | 0 | 0 | 1 | 20 | 0（0 実行） | 0 |
| `qpdf is installed` | 1291 | 0 | 0 | 2 | 20 | 0（0 実行） | 0 |
| `Cache the cddl CLI (docs/adr/0009)` | 1263 | 1 | 2 | 6 | 20 | 0（0 実行） | 0 |
| `Cache the fonts of the manuals (docs/adr/0022, docs/adr/0024)` | 910 | 1 | 2 | 5 | 20 | 0（0 実行） | 0 |
| `Run actions/setup-node@v7` | 705 | 5 | 6 | 9 | 20 | 0（0 実行） | 0 |
| `Run actions/download-artifact@v8` | 1179 | 1 | 2 | 7 | 20 | 0（0 実行） | 0 |
| `Run actions/checkout@v7` | 6368 | 3 | 4 | 11 | 20 | 0（0 実行） | 0 |

## 表 7 `cabal build` の秒の分布（`pull_request`、x86-64 の `outputs`）

| 範囲 | 件数 |
|---|---|
| 20 秒以下 | 50 |
| 21 から 60 秒 | 29 |
| 61 から 120 秒 | 15 |
| 121 から 200 秒 | 19 |
| 200 秒超 | 5 |

## 表 8 取得の失敗

400 回の実行と、再実行の前の 11 の試行のログから、取得（ダウンロード）で失敗した手順を数えた。

| 手順 | 失敗したジョブ | 実行（試行） | 誤り |
|---|---|---|---|
| `build` の `wasmtime C API (golem-plugin ADR 0001)`（`scripts/fetch-wasmtime.sh`） | 32 | 10 回の実行の 14 の試行 | `curl: (22) The requested URL returned error: 504` が 23、同 `503` が 7、同 `502` が 2、`curl: (56) Connection died` が 1 |
| `format` の `hlint 3.10`（`scripts/ci/fetch-hlint.sh`） | 1 | 1 | `curl: (22) ... 503` |
| `verapdf` の `veraPDF from nixpkgs`（`nix build github:NixOS/nixpkgs/...`） | 1 | 1 | `api.github.com` の nixpkgs の tarball が `HTTP error 429`（4 回試して諦めた） |
| `visual` の `actions/download-artifact@v8` | 1 | 1 | `Failed to ListArtifacts: Unable to make request: ENOTFOUND` |
| `wasm` の `Wait for the native list`、`visual` の `Wait for the PDFs` | 6 と 6 | 同じ実行 | `outputs` のランナーが wasmtime の取得で失敗したため、成果物が上がらなかった（連鎖） |

wasmtime の取得の失敗は、2026-11-08T10:37Z から 12:16Z までの約 100 分に集中していた。
この時間の GitHub の release の配信（`github.com/.../releases/download/`）は、2 分で 504 を返すか、すぐに 502 か 503 を返した。
`fetch-wasmtime.sh` の `curl` には `--retry` がない（[`scripts/fetch-wasmtime.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/fetch-wasmtime.sh#L47)）。
10 回の実行のうち、6 回は手で再実行して通し（最大 4 回の試行）、4 回は失敗のまま終わった。
表 6 のとおり、wasmtime の取得の手順は 40 時間に 2,219 回走っている（`build` の 7 つのランナーが毎回取る）。

| 実行 | 作られた時刻 | イベント | 試行 | 最後の結論 |
|---|---|---|---|---|
| [42472239927](https://github.com/tett23/golem/actions/runs/42472239927) | 2026-11-08T10:37:53Z | `pull_request` | 1 | failure |
| [42472629902](https://github.com/tett23/golem/actions/runs/42472629902) | 2026-11-08T10:43:32Z | `pull_request` | 2 | success |
| [42475288545](https://github.com/tett23/golem/actions/runs/42475288545) | 2026-11-08T11:20:12Z | `pull_request` | 2 | success |
| [42476899008](https://github.com/tett23/golem/actions/runs/42476899008) | 2026-11-08T11:42:09Z | `push` | 1 | failure |
| [42477401593](https://github.com/tett23/golem/actions/runs/42477401593) | 2026-11-08T11:49:09Z | `pull_request` | 4 | success |
| [42477438930](https://github.com/tett23/golem/actions/runs/42477438930) | 2026-11-08T11:49:41Z | `pull_request` | 2 | success |
| [42478006073](https://github.com/tett23/golem/actions/runs/42478006073) | 2026-11-08T11:57:37Z | `pull_request` | 2 | failure |
| [42478297174](https://github.com/tett23/golem/actions/runs/42478297174) | 2026-11-08T12:01:27Z | `push` | 1 | failure |
| [42478712741](https://github.com/tett23/golem/actions/runs/42478712741) | 2026-11-08T12:06:51Z | `pull_request` | 2 | success |
| [42478862384](https://github.com/tett23/golem/actions/runs/42478862384) | 2026-11-08T12:08:49Z | `pull_request` | 3 | success |

ほかのワークフローも同じ方法で見た（`gh run list -L 300` と `--log-failed`）。

| ワークフロー | 実行 | 失敗 | 取得の失敗 |
|---|---|---|---|
| `docs.yml` | 300（2026-11-07T19:47Z から） | 6 | `adr` の `tett23/adr-guard@v0.10.0` が自分の実行ファイルを取るときの `curl: (22) ... 504` が 1。ほかの 5 は textlint の指摘 |
| `release.yml` | 19（2026-10-13 から） | 7 | `wasm` の `scripts/release/fetch-gmp.sh` で `gmplib.org` への接続が 20 秒で時間切れ（`curl: (28)`）が 2。ミラーに移って通った |
| `browser.yml` | 13 | 10 | 取得の失敗はない。輪郭化した図の文字の検査（[ADR 0239](../adr/0239-decide-the-conditions-of-the-outlined-figure-check-and-the-punctuation-of-figure-sources.md) の前）と `run-wasmtime` のコンパイルの失敗 |
| `models.yml` | 4 | 0 | なし |

[ADR 0167](../adr/0167-leave-cache-restore-failures-as-misses.md) が見直しの条件とした `Failed to restore: Egress is over the account limit.` は、81 回の失敗した実行のログに一つもなかった。
表 6 のキャッシュの復元の手順は、どれも最大が 30 秒未満で、外れた形跡がない。
外れたのは、`wasm` のツールチェーンのキャッシュ（`The wasm toolchain` が 60 秒を超えた 4 回、いずれもツールチェーンの取得と展開の 102 秒前後）と、`wasm` のネイティブの `alex` と `happy`（`haskell-actions/setup` が 60 秒を超えた 5 回）だけである。

## 表 9 キャッシュの量（2026-11-09T00Z ごろ）

`gh api repos/tett23/golem/actions/cache/usage` は 35 個、6,837,522,387 バイトを返した。
`gh api repos/tett23/golem/actions/caches --paginate` の一覧を、キーの族で足した。

| 族 | 個数 | MB |
|---|---|---|
| `dist-Linux-{X64,ARM64}-…`（`dist-newstyle`。`main` が 2、プルリクエストが 8） | 10 | 4,252 |
| `ghc-wasm-…`（wasm のツールチェーンと store） | 1 | 1,131 |
| `ghc-9.10.3-…`（GHC、二つのアーキテクチャ） | 2 | 297 |
| `cabal-store-…` | 2 | 258 |
| `dist-wasm-…` | 1 | 114 |
| `hackage-index-no-gz-…` | 1 | 109 |
| `chromium-…` | 1 | 108 |
| `helix-Linux-…` | 2 | 47 |
| `deno-…` | 1 | 38 |
| `epubcheck-5.4.0-…` | 1 | 32 |
| `textlint-Linux-…` | 1 | 29 |
| `manual-fonts-…` | 1 | 26 |
| `wasmtime-x86_64-linux-musl-…`（`release.yml`） | 2 | 24 |
| `wasmtime-aarch64-linux-musl-…`（`release.yml`） | 2 | 22 |
| `nvim-Linux-…` | 2 | 22 |
| `editors-Linux-…` | 1 | 8 |
| `cddl-0.10.7-…` | 2 | 3 |
| `shem-…` | 1 | 1 |
| `hosttools-…` | 1 | 1 |

プルリクエストの `dist-` の 8 個（約 3.5 GB）は、[ADR 0228](../adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) の実装の前に保存したもので、7 日で消える。
`release.yml` は wasmtime の C API をキャッシュしているが、`ci.yml` の `build` はキャッシュせず、毎回取っている。

## 表 10 固定した取得物の大きさ

`curl -sIL` の `Content-Length` である。

| 取得物 | MB | 取る場所 |
|---|---|---|
| wasmtime C API 49.0.5、x86-64 Linux | 15.3 | `build` の 4 つのランナー、`browser.yml` の `chromium` |
| wasmtime C API 49.0.5、aarch64 Linux | 13.1 | `build` の 3 つのランナー |
| Neovim 0.12.6 | 10.9 | `editors-lsp`（キャッシュあり） |
| Helix 25.07.1 | 15.9 | `editors`（キャッシュあり） |
| shem 0.1.0-rc4 | 0.5 | `visual`（キャッシュあり） |
| chrome-headless-shell 157.0.8103.38 | 122.2 | `browser.yml`（キャッシュあり） |
| Deno 2.9.8 | 40.0 | `browser.yml`（キャッシュあり） |
| Alloy 6.2.0 の jar | 20.1 | `models.yml`（キャッシュなし） |
| epubcheck 5.4.0 | 31.6 | `build` の `outputs`（zip をキャッシュし、SHA-256 を照合） |
| hlint 3.10 | 14.1 | `format`（キャッシュなし） |

## 読み方

- プルリクエストで `build` が走って成功した 118 回の実行全体は、中央値 298 秒、第 3 四分位 376 秒で、56 回（47%）が CONTRIBUTING の 5 分を超えた。[docs/ci-timings/2026-11-08-ci-caches-under-the-limit.md](2026-11-08-ci-caches-under-the-limit.md) の 5 回のうち 2 回が超えたのと同じ傾向である。
- 最後に終わるジョブは、118 回のうち 115 回が `verapdf` だった。`verapdf` は `build` の 7 つのランナーすべてを待ち（`needs: build`）、その後に Nix の導入と veraPDF の取得（約 25 秒）と検査（約 33 秒）を行うので、最後の `build` のランナーの終わりから中央値で 68 秒後に終わる。`verapdf` が待つ成果物 `conformance-pdfs` は、`outputs` のランナーが `cabal build` の直後の約 55 秒で上げている。
- `verapdf` を臨界経路から外すと、118 回の中央値は 234 秒、5 分を超える実行は 34 回（29%）になる見積もりである。
- `build` の 7 つのランナーのうち最後に終わるのは、`outputs`（62 回）と x86-64 の `tests-rest`（44 回）である。`outputs` は `cabal build` の後に約 140 秒の手順（visual-pdfs 47 秒、決定性の出力 30 秒、マニュアルのプリフライト 31 秒、epubcheck の 4 回で約 20 秒など）を持ち、`tests-rest` は約 99 秒のテストを持つ。
- `cabal build` は、プルリクエストでは `main` の `dist-newstyle` から変更をビルドし直すので、中央値 31 秒、第 3 四分位 95 秒、第 9 十分位 165 秒と幅が広い。118 回のうち 24 回は 121 秒以上かかった。この幅は、変更が触るモジュールで決まり、CI の構成では縮まない。
- 待ち行列の秒は、どのジョブも中央値 2 秒から 4 秒で、ランナーの不足はない。
- キャッシュの復元は、GHC、Hackage の索引、cabal の store、`dist-newstyle` のどれも失敗していない。`wasm` のツールチェーンの復元は 1.1 GB で 31 秒かかる。
- 取得の失敗は、wasmtime の C API に集中している。`build` の 7 つのランナーが毎回取り（40 時間に 2,219 回）、`curl` に再試行がなく、キャッシュもないからである。ほかの取得物（shem、Neovim、Helix、epubcheck、Chromium、Deno）はキャッシュがあるか再試行があり、この 40 時間に失敗していない。
