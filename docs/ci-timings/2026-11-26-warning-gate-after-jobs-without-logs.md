# warning の検査の失敗の数え直し（2026-11-26、ログの無いジョブを扱った後の `ci.yml` の 20 回）

[root ADR 0427](../adr/0427-warning-gate-and-jobs-without-logs.md) の A1 が求める記録である。
0427 の実装（PR #1113、2026-11-23T10:20:58Z のマージ、[241f8141a](https://github.com/tett23/golem/commit/241f8141acaf79d729a5c54731985e29b03c998e)）の後の `ci.yml` の 20 回で、`ci` の warning の検査の step（`No warning in the logs of the jobs but the allowed ones`）が、0427 の四つの原因で失敗したかを数えた。
2026-11-26 に作り、コミットした後は変更しない。

## 条件

- 20 回は、`gh run list --workflow ci.yml --created '>=2026-11-23T10:20:58Z'` の、作成の古い順の最初の 20 回である。
  イベント（`push` と `pull_request`）と結論で絞っていない。
  最初の回 45155282044 は、0427 のマージのコミット `241f8141` の main の実行である。
- 2 回の試行を持つ実行（45159877162）は、二つの試行の両方を数えた。
  したがって、数えた `ci` のジョブは 21 である。
- step の結論は、`gh api repos/tett23/golem/actions/runs/<id>/attempts/<n>/jobs` の `ci` のジョブの `steps` から読んだ。
- 四つの原因は、次のように数えた。
  - ログの無いジョブ：`ci` のジョブのログで、`job-logs.sh` が書く「the jobs cancelled before any step ran」の一覧の行数と、「cannot be fetched」の行数。
  - キャッシュの復元の失敗：試行ごとのログの束（`gh api .../runs/<id>/attempts/<n>/logs`）にある `##[warning]Failed to restore` の行数。
  - ランナーの action の取り直し：同じ束にある `##[warning]Failed to download action` と `##[warning]Back off` の行数。
  - wasm のキャッシュの追い出し：同じ束にある `wasm-cache: missed` の行数（`scripts/ci/wasm-cache.sh` が追い出しのときに出す注釈の文）。

## 表 1 まとめ

| 原因 | 起きた回数 | 検査の step の失敗 |
| --- | --- | --- |
| step を走らせずに取り消されたジョブ（ログの無いジョブ） | 1 回（45163344266 の 12 ジョブ） | 0 |
| 取れなかったログ | 0 | 0 |
| キャッシュの復元の失敗 | 0 | 0 |
| ランナーの action の取り直し | 0 | 0 |
| wasm のキャッシュの追い出し | 0 | 0 |

21 の `ci` のジョブのすべてで、warning の検査の step は `success` だった。
21 の試行のログの束には、`##[warning]` の行が一つも無かった。

## 表 2 実行ごとの結果

| 実行 | 試行 | イベント | ブランチ | 作成（UTC） | 実行の結論 | 検査の step | 除いたジョブ | 読んだジョブ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 45155282044 | 1 | push | `main` | 11-23T10:21 | success | success | 0 | 25 |
| 45155486605 | 1 | pull_request | `adr-0429` | 11-23T10:22 | success | success | 0 | 3 |
| 45155823707 | 1 | pull_request | `manual-followup` | 11-23T10:24 | success | success | 0 | 24 |
| 45156067490 | 1 | push | `main` | 11-23T10:26 | success | success | 0 | 3 |
| 45156893064 | 1 | pull_request | `manual-followup` | 11-23T10:31 | success | success | 0 | 24 |
| 45157592951 | 1 | pull_request | `impl-0429` | 11-23T10:36 | cancelled | success | 0 | 24 |
| 45157792855 | 1 | push | `main` | 11-23T10:37 | success | success | 0 | 24 |
| 45158321230 | 1 | pull_request | `impl-0429` | 11-23T10:40 | success | success | 0 | 24 |
| 45158742588 | 1 | pull_request | `manual-folda` | 11-23T10:43 | failure | success | 0 | 24 |
| 45159430152 | 1 | push | `main` | 11-23T10:48 | success | success | 0 | 25 |
| 45159877162 | 1 | pull_request | `manual-folda` | 11-23T10:51 | failure | success | 0 | 23 |
| 45159877162 | 2 | pull_request | `manual-folda` | 11-23T10:51 | success | success | 0 | 24 |
| 45161556318 | 1 | pull_request | `manual-folda` | 11-23T11:02 | success | success | 0 | 24 |
| 45162452367 | 1 | push | `main` | 11-23T11:08 | failure | success | 0 | 23 |
| 45163344266 | 1 | pull_request | `adr-0430` | 11-23T11:14 | cancelled | success | 12 | 3 |
| 45163372861 | 1 | pull_request | `adr-0430` | 11-23T11:14 | success | success | 0 | 3 |
| 45164179008 | 1 | pull_request | `adr-0430` | 11-23T11:19 | success | success | 0 | 3 |
| 45164774104 | 1 | push | `main` | 11-23T11:23 | success | success | 0 | 3 |
| 45166800707 | 1 | pull_request | `impl-0430` | 11-23T11:37 | failure | success | 0 | 24 |
| 45167841252 | 1 | pull_request | `impl-0430` | 11-23T11:44 | success | success | 0 | 24 |
| 45168702824 | 1 | push | `main` | 11-23T11:50 | failure | success | 0 | 23 |

実行の結論が `failure` や `cancelled` の回は、warning の検査より前の step かほかのジョブで止まった回で、検査の step 自身は通っている。
45159877162 の 1 回目の試行の結論は、試行ごとのジョブの一覧の `ci` の結論から読んだ。

## 読み方

20 回の実行（21 の試行）で、四つの原因のどれでも、warning の検査の step は失敗しなかった。
したがって、[root ADR 0427](../adr/0427-warning-gate-and-jobs-without-logs.md) の A1 を満たす。

四つの原因のうち、起きたのは step を走らせずに取り消されたジョブだけである。
45163344266 では、12 のジョブを読むジョブから除いて一覧に書き、残りの 3 ジョブのログを読んで、検査の step は通った。
キャッシュの復元の失敗、ランナーの action の取り直し、wasm のキャッシュの追い出しは、20 回のうちに起きなかった。
この三つで検査が失敗しないことは、この 20 回では確かめられておらず、0427 のテスト（I4、I6、I7）が確かめている。
