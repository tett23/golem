# CI の所要時間（2026-11-05、aarch64 のテストを二つのランナーに分けた前後）

[ADR 0155](../adr/0155-split-aarch64-test-runner.md) の実装の前後の、`ci.yml` の `build` の aarch64 のランナーの記録である。
数字は `gh run view <id> --json jobs` の手順の秒数で、各ジョブの終わりは実行の最初のジョブの始まりからの秒数である。
2026-11-05 に作り、コミットした後は変更しない。

## 前

[ADR 0155](../adr/0155-split-aarch64-test-runner.md) の文脈の 33 回の実行（41832262416 から 41884131738 まで）である。

| 項目 | 値 |
|---|---|
| aarch64 の `tests` の `cabal test` の手順 | 80〜103 秒（最近の 6 回は 92〜103 秒） |
| aarch64 の `tests` が `build` と `visual` の中で最後に終わった回 | 33 回のうち 15 回 |

## 後

このプルリクエスト（[#539](https://github.com/tett23/golem/pull/539)）の 2 回の実行である。
一回目は、開発者向けのマニュアルの参照を受け入れる前で、`visual` だけが失敗した。

| 実行 | aarch64 の `tests-driver` の手順 | aarch64 の `tests-rest` の手順 | aarch64 の `tests-driver` の終わり | aarch64 の `tests-rest` の終わり | 最後に終わった `build` か `visual` | 実行全体 |
|---|---|---|---|---|---|---|
| [41886607899](https://github.com/tett23/golem/actions/runs/41886607899) | 39 | 65 | 110 | 130 | x86-64 の `tests-rest`（172） | 188 |
| [41887380664](https://github.com/tett23/golem/actions/runs/41887380664) | 39 | 63 | 98 | 129 | x86-64 の `outputs`（161） | 178 |

二回目の実行で、aarch64 の二つのランナーが `PASS` を出したスイートは 3 と 25 で、x86-64 の二つのランナーと同じ 28 だった。

## 読み方

aarch64 のテストの手順は、80〜103 秒の一つから、39 秒と 63〜65 秒の二つになった。
aarch64 のランナーは 98〜130 秒で終わり、二回とも `build` の最後ではなくなった。
最後に終わったのは、x86-64 の `tests-rest`（golem-pdf-test が終わりを決める）か `outputs`（見た目の回帰テストの PDF が終わりを決める）である。
