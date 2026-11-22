# プルリクエストの CI の時間の測り直し（2026-11-23、成功した `ci.yml` の 20 回）

[ADR 0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) の項目 7 と A2 が求める測り直しの記録である（[root ADR 0415](../adr/0415-fix-the-medium-findings-of-the-conformance-audit-of-2026-11-18.md) の 1）。
[ADR 0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) の実装（PR #1049、2026-11-18T03:09:56Z のマージ）より後の、成功したプルリクエストの `ci.yml` の時間を、[ADR 0392](../adr/0392-budget-the-pull-request-ci-at-five-minutes.md) の予算の 300 秒と比べた。
2026-11-23 に作り、コミットした後は変更しない。

## 条件

- 値は、`origin/main`（`b216e6e7d`）の作業ツリーで、2026-11-23 に `sh scripts/ci/ci-critical-path.sh` を一度走らせた出力である。
  このスクリプトは、`gh run list --workflow ci.yml --event pull_request --status success` の新しい順に、`build` を省かなかった実行を 20 回取る。
- 実行の時間は、ジョブの `needs` をたどった最も長い道の秒で、ランナーを待つ時間を含まない（`scripts/ci/ci-critical-path.sh` の冒頭の注記を参照）。
  `needs` は、測った時点の `.github/workflows/ci.yml` から読んだ。
- 作成の時刻、コミット、ブランチは、`gh api repos/tett23/golem/actions/runs/<id>` の `created_at`、`head_sha`、`head_branch` である。
  20 回はどれも最初の試行（`run_attempt` が 1）で、作成の時刻はすべて PR #1049 のマージより後である。

## 表 1 まとめ

| 値 | 秒 |
| --- | --- |
| 中央値（`ci-critical-path.sh` の最後の行） | 398.5 |
| 最小 | 276 |
| 最大 | 896 |
| 300 秒以下の回数 | 20 回のうち 2 回 |

## 表 2 実行ごとの秒

| 実行 | コミット | ブランチ | 作成（UTC） | 秒 |
| --- | --- | --- | --- | --- |
| 45071963290 | `eae3c786` | `codex/impl-root-0386` | 11-22T21:24 | 442 |
| 45070241008 | `4d4e80ae` | `codex/impl-0352` | 11-22T21:06 | 481 |
| 45055120571 | `ecf0565e` | `codex/impl-0365` | 11-22T18:26 | 466 |
| 45054879767 | `6df818e0` | `codex/impl-0352` | 11-22T18:24 | 704 |
| 45050959782 | `d9968b33` | `codex/root-0398-integrated` | 11-22T17:42 | 367 |
| 45050240043 | `a78cc764` | `codex/impl-0352` | 11-22T17:34 | 495 |
| 45050179761 | `4c455ea0` | `codex/impl-root-0377` | 11-22T17:34 | 305 |
| 45046398172 | `4e867523` | `codex/root-0397-integrated` | 11-22T16:54 | 468 |
| 45039100996 | `7db36b9e` | `codex/impl-0400-nov22` | 11-22T15:34 | 896 |
| 45027068804 | `ff9da161` | `codex/impl-0379-nov22` | 11-22T13:21 | 556 |
| 45024747431 | `abbcfd77` | `codex/root-0402` | 11-22T12:55 | 511 |
| 45023692021 | `cd5e1296` | `codex/fix-diagnostic-guidance-nov22` | 11-22T12:42 | 345 |
| 45019957037 | `1fbca5cf` | `codex/root-0397` | 11-22T11:59 | 325 |
| 45019133545 | `0eaa2009` | `impl/root-0399-move` | 11-22T11:48 | 330 |
| 45017041347 | `774981db` | `codex/root-0397` | 11-22T11:22 | 327 |
| 45016435182 | `e96e199b` | `codex/root-0384` | 11-22T11:15 | 292 |
| 45016326129 | `b3b44bbf` | `codex/root-0397` | 11-22T11:14 | 276 |
| 44247421984 | `c0209359` | `impl-0396` | 11-18T05:53 | 329 |
| 44240215242 | `0ea2d4a3` | `impl-0358` | 11-18T04:51 | 430 |
| 44237126145 | `38d76668` | `impl-0391` | 11-18T04:24 | 311 |

## 読み方

中央値の 398.5 秒は、予算の 300 秒を 98.5 秒超える。
したがって、予算の 300 秒を満たさない。
[ADR 0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) の A2 と項目 8 により、コンパイルの時間を縮める変更を [ADR 0416](../adr/0416-shorten-the-build-of-the-pull-request-ci.md) で入れる。

20 回のうち 300 秒以下は 2 回だけで、どちらも 2026-11-22 の 11 時台の実行である。
600 秒を超えた 2 回（704 秒と 896 秒）は、中央値を動かさないが、最大と平均を押し上げる。
長い実行の理由（ジョブのどこで時間がかかったか）は、この記録では調べていない（未確認）。

[root ADR 0415](../adr/0415-fix-the-medium-findings-of-the-conformance-audit-of-2026-11-18.md) の調査した事項の 1 は、この ADR を書いた時点の、`build` を省かなかった 25 回のすべてから中央値を 389 秒と数えた。
この記録の 398.5 秒は、`ci-critical-path.sh` が選ぶ直近の 20 回の値であり、回の選び方が違うので、二つの値は一致しない。
