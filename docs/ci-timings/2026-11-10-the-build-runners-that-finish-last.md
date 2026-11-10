# `build` のランナーのうち最後に終わるもの（2026-11-10、`main` の push 15 回とプルリクエスト 14 回）

[ADR 0291](../adr/0291-run-the-tests-of-every-package-on-every-change.md) の 4 が求める記録である。
変更のないパッケージのテストを省いたとき、CI の実行がどれだけ縮みうるかを見るため、`ci.yml` の `build` のランナーのうち最後に終わったものと、二番めに終わったものとの差を数えた。
2026-11-10 に作り、コミットした後は変更しない。

## 条件

- `main` の push は、`7e8fe7d3` から `8828fc5d` までの成功した実行のうち、`build` を省かなかった 15 回である（文書だけの変更で `build` を省いた 4 回は除いた）。
- プルリクエストは、同じ期間の成功した `pull_request` の実行のうち、`build` を省かなかった 14 回（2026-11-10T00:28Z から 03:40Z に作られたもの）である。
- 各実行のジョブは `gh api repos/tett23/golem/actions/runs/<id>/jobs?per_page=100` で取った。
- 秒は、実行の最初のジョブ（省かれたものを除く）の `started_at` から、各ジョブの `completed_at` までで、`scripts/ci/timings.sh` と同じく `started_at` と `completed_at` から求めた。
- 「最後」と「二番め」は、`build` の七つのランナーのうち `completed_at` が最も遅いものと、その次のものである。
- 集計は手元の jq で行い、コミットしていない。

## 表 1 まとめ

| 実行 | `build` のランナーのうち最後に終わったもの | 二番めとの差 |
| --- | --- | --- |
| `main` の push 15 回 | `outputs` 9 回、`env` 5 回、`tests-rest`（x86-64）1 回 | `tests-rest` が最後の 1 回で 57 秒 |
| プルリクエスト 14 回 | `outputs` 7 回、`tests-rest`（x86-64）7 回 | `tests-rest` が最後の 7 回で 2 秒から 73 秒、中央値 21 秒 |

## 表 2 `main` の push

| 実行 | コミット | 作成（UTC） | 最後（秒） | 二番め | 差（秒） |
| --- | --- | --- | --- | --- | --- |
| 42749412945 | `8828fc5d` | 11-10T03:26 | `ubuntu-24.04, tests-rest`（494） | `ubuntu-24.04, env` | 57 |
| 42747377433 | `e6013d41` | 11-10T03:07 | `ubuntu-24.04, env`（361） | `ubuntu-24.04, tests-rest` | 8 |
| 42743811596 | `ef8438ce` | 11-10T02:35 | `ubuntu-24.04, outputs`（237） | `ubuntu-24.04-arm, tests-rest` | 47 |
| 42740480282 | `8529b6d7` | 11-10T02:06 | `ubuntu-24.04, outputs`（235） | `ubuntu-24.04, env` | 19 |
| 42738715688 | `795fcf5d` | 11-10T01:51 | `ubuntu-24.04, outputs`（236） | `ubuntu-24.04, tests-rest` | 7 |
| 42735279926 | `5fe4b57f` | 11-10T01:22 | `ubuntu-24.04, outputs`（293） | `ubuntu-24.04, tests-rest` | 3 |
| 42732052330 | `96d7e806` | 11-10T00:56 | `ubuntu-24.04, outputs`（446） | `ubuntu-24.04, tests-driver` | 20 |
| 42729705298 | `0c694902` | 11-10T00:37 | `ubuntu-24.04, env`（450） | `ubuntu-24.04, tests-rest` | 10 |
| 42723132548 | `79c91475` | 11-09T23:46 | `ubuntu-24.04, outputs`（321） | `ubuntu-24.04, tests-rest` | 12 |
| 42717986659 | `7f496c77` | 11-09T23:08 | `ubuntu-24.04, outputs`（314） | `ubuntu-24.04, env` | 32 |
| 42715298341 | `b5d39129` | 11-09T22:49 | `ubuntu-24.04, outputs`（242） | `ubuntu-24.04, env` | 46 |
| 42714202388 | `ebba7958` | 11-09T22:42 | `ubuntu-24.04, env`（289） | `ubuntu-24.04, tests-driver` | 12 |
| 42712675271 | `16b4091d` | 11-09T22:31 | `ubuntu-24.04, env`（265） | `ubuntu-24.04, outputs` | 20 |
| 42711171269 | `fdc722e9` | 11-09T22:21 | `ubuntu-24.04, outputs`（255） | `ubuntu-24.04, env` | 14 |
| 42702830010 | `7e8fe7d3` | 11-09T21:28 | `ubuntu-24.04, env`（412） | `ubuntu-24.04, outputs` | 37 |

## 表 3 プルリクエスト

| 実行 | コミット | ブランチ | 作成（UTC） | 最後（秒） | 二番め | 差（秒） |
| --- | --- | --- | --- | --- | --- | --- |
| 42750973817 | `e58b458c` | `impl-0281` | 11-10T03:40 | `ubuntu-24.04, outputs`（233） | `ubuntu-24.04, tests-driver` | 3 |
| 42749566843 | `ea1adcec` | `impl-0285` | 11-10T03:27 | `ubuntu-24.04, tests-rest`（449） | `ubuntu-24.04, outputs` | 4 |
| 42748404900 | `e0321f6d` | `impl-0278` | 11-10T03:16 | `ubuntu-24.04, tests-rest`（480） | `ubuntu-24.04, tests-driver` | 73 |
| 42745638372 | `245848ec` | `fix-enum-heading-keep` | 11-10T02:51 | `ubuntu-24.04, outputs`（325） | `ubuntu-24.04-arm, tests-driver` | 20 |
| 42745588562 | `fbfa23c0` | `impl-0283` | 11-10T02:51 | `ubuntu-24.04, outputs`（363） | `ubuntu-24.04-arm, tests-rest` | 38 |
| 42744930735 | `da470527` | `impl-0281` | 11-10T02:45 | `ubuntu-24.04, outputs`（268） | `ubuntu-24.04, tests-rest` | 42 |
| 42743256649 | `ca557aaf` | `fix-i4-shy` | 11-10T02:30 | `ubuntu-24.04, outputs`（221） | `ubuntu-24.04-arm, tests-rest` | 8 |
| 42743148058 | `8ff29b30` | `impl-0281` | 11-10T02:29 | `ubuntu-24.04, tests-rest`（256） | `ubuntu-24.04-arm, tests-driver` | 11 |
| 42739674843 | `dc64fab0` | `impl-0282` | 11-10T02:00 | `ubuntu-24.04, tests-rest`（232） | `ubuntu-24.04, outputs` | 2 |
| 42738115261 | `0e21886e` | `fix-enum-section-waiting` | 11-10T01:46 | `ubuntu-24.04, outputs`（255） | `ubuntu-24.04, tests-rest` | 22 |
| 42734534064 | `ddff6689` | `impl-0280` | 11-10T01:15 | `ubuntu-24.04, tests-rest`（310） | `ubuntu-24.04, outputs` | 29 |
| 42731822427 | `550b11ca` | `impl-0280` | 11-10T00:54 | `ubuntu-24.04, outputs`（297） | `ubuntu-24.04-arm, tests-driver` | 33 |
| 42731014763 | `dc09ddfc` | `impl-0275` | 11-10T00:47 | `ubuntu-24.04, tests-rest`（382） | `ubuntu-24.04, outputs` | 23 |
| 42728552528 | `dc3ee976` | `impl-0274` | 11-10T00:28 | `ubuntu-24.04, tests-rest`（444） | `ubuntu-24.04, outputs` | 21 |

## 読み方

省いて縮むのは、`tests-rest` がいちばん遅いときの、二番めのランナーとの差までである。
`main` の push では 15 回のうち 1 回だけで、プルリクエストでは 14 回のうち 7 回で、その中央値は 21 秒である。
