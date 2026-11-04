# CI の所要時間（2026-11-05、見た目の回帰テストの PDF を並べて組んだ前後）

[ADR 0163](../adr/0163-build-visual-pdfs-in-parallel.md) の実装の前後の、`ci.yml` の x86-64 の `outputs` と `visual` の記録である。
数字は `gh run view <id> --json jobs` の手順の秒数で、ジョブの終わりと実行全体は、実行の最初のジョブの始まりからの秒数である。
2026-11-05 に作り、コミットした後は変更しない。

## 前

[ADR 0163](../adr/0163-build-visual-pdfs-in-parallel.md) の文脈の実行のうち、`main` のモジュールのビルドが長かった 41887719789 を除く 6 回である。

| 実行 | PDF を組む手順 | `outputs` の終わり | `visual` の終わり | 最後に終わった `build` か `visual` | 実行全体 |
|---|---|---|---|---|---|
| [41889606653](https://github.com/tett23/golem/actions/runs/41889606653) | 46 | 128 | 112 | x86-64 の `tests-rest`（155） | 167 |
| [41889098177](https://github.com/tett23/golem/actions/runs/41889098177) | 51 | 152 | 133 | x86-64 の `outputs`（152） | 172 |
| [41888434053](https://github.com/tett23/golem/actions/runs/41888434053) | 42 | 144 | 131 | x86-64 の `outputs`（144） | 157 |
| [41887380664](https://github.com/tett23/golem/actions/runs/41887380664) | 57 | 161 | 129 | x86-64 の `outputs`（161） | 178 |
| [41887133582](https://github.com/tett23/golem/actions/runs/41887133582) | 52 | 153 | 130 | x86-64 の `outputs`（153） | 168 |
| [41886607899](https://github.com/tett23/golem/actions/runs/41886607899) | 47 | 152 | 136 | x86-64 の `tests-rest`（172） | 188 |

## 後

このプルリクエスト（[#543](https://github.com/tett23/golem/pull/543)）の 2 回の実行である。

| 実行 | PDF を組む手順 | `outputs` の終わり | `visual` の終わり | 最後に終わった `build` か `visual` | 実行全体 |
|---|---|---|---|---|---|
| [41914414453](https://github.com/tett23/golem/actions/runs/41914414453) | 27 | 112 | 103 | x86-64 の `tests-rest`（130） | 147 |
| [41915025371](https://github.com/tett23/golem/actions/runs/41915025371) | 32 | 129 | 114 | x86-64 の `tests-rest`（138） | 151 |

二回とも、`visual` は参照のまま通った（17 の PDF のページは変わらなかった）。
手元（10 コアの macOS）では、並べて組んだ 17 の PDF は、一つずつ組んだものとバイト単位で一致し、42.78 秒が 18.33 秒と 20.09 秒になった。

## 読み方

PDF を組む手順は 42〜57 秒から 27 秒と 32 秒になり、`outputs` と `visual` は 15〜40 秒早く終わった。
`outputs` は二回とも `build` の最後ではなくなり、最後は x86-64 の `tests-rest`（golem-pdf-test と golem-parser-test が終わりを決める）になった。
実行全体は 157〜188 秒から 147 秒と 151 秒になった。
