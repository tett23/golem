# プルリクエストの CI の時間（2026-11-27、tests-rest を二つに分けた後の 20 回）

[root ADR 0457](../adr/0457-split-the-tests-rest-runner-in-two.md) の A1 に従い、実装のマージ後の成功したプルリクエストの CI を 20 回測った。
中央値は 318 秒で、[root ADR 0392](../adr/0392-budget-the-pull-request-ci-at-five-minutes.md) の予算 300 秒を 18 秒超えた。
この記録は 2026-11-27 に作り、コミットした後は変更しない。

## 条件

測定に使ったコードは origin/main の [4121ea73d](https://github.com/tett23/golem/commit/4121ea73d4466eaf47353e4b84d22f08327aed1e) である。
[root ADR 0457](../adr/0457-split-the-tests-rest-runner-in-two.md) の実装は [PR #1180](https://github.com/tett23/golem/pull/1180) で、2026-11-26T00:14:27Z にマージされた。
対象は、その後に作成された成功した `ci.yml` のうち、`build` を省かなかった新しい順の 20 回である。
ジョブの API は最後の試行の結果を返すため、再実行された実行は最後の試行を数える。

`gh run list --repo tett23/golem --workflow ci.yml --event pull_request --limit 100 --json databaseId,createdAt,conclusion,headSha` の結果から、マージ後の成功 28 回のジョブを `gh api repos/tett23/golem/actions/runs/<id>/jobs?per_page=100 --paginate` で取得した。
取得した一覧のうち、`build` を省いた実行を外して新しい順に 20 回選んだ。
測定に使うフィールドを残した [ジョブの一覧](2026-11-27-pull-request-ci-after-adr-0457/) を同梱する。
各ファイルの `run` に実行番号、作成の時刻、コミットを、`jobs` にジョブの名前、結論、開始と終了の時刻を残した。

時間は、ジョブの依存関係をたどった最も長い道の秒で、ランナーを待つ時間を含まない。
依存関係は測定時の `.github/workflows/ci.yml` から読み、同じジョブの matrix の脚は最も長いものを使う。
次のコマンドは、同梱した値から中央値を再計算する。

```sh
sh scripts/ci/ci-critical-path.sh docs/ci-timings/2026-11-27-pull-request-ci-after-adr-0457/*.json
```

## 実行ごとの秒

| 実行 | 作成の時刻（UTC） | コミット | 秒 |
| --- | --- | --- | --- |
| [45854683253](https://github.com/tett23/golem/actions/runs/45854683253) | 2026-11-26T16:00:48Z | `02811dcb1` | 290 |
| [45846112729](https://github.com/tett23/golem/actions/runs/45846112729) | 2026-11-26T15:08:48Z | `b4f2a30f6` | 330 |
| [45839811994](https://github.com/tett23/golem/actions/runs/45839811994) | 2026-11-26T14:31:06Z | `123153b56` | 317 |
| [45828312661](https://github.com/tett23/golem/actions/runs/45828312661) | 2026-11-26T13:21:15Z | `7527d5144` | 304 |
| [45818968689](https://github.com/tett23/golem/actions/runs/45818968689) | 2026-11-26T12:21:59Z | `d918c8cb5` | 317 |
| [45806887362](https://github.com/tett23/golem/actions/runs/45806887362) | 2026-11-26T11:02:29Z | `79b9172e1` | 390 |
| [45802211168](https://github.com/tett23/golem/actions/runs/45802211168) | 2026-11-26T10:32:00Z | `d866976cb` | 394 |
| [45798868746](https://github.com/tett23/golem/actions/runs/45798868746) | 2026-11-26T10:10:42Z | `3319c8a99` | 319 |
| [45796807999](https://github.com/tett23/golem/actions/runs/45796807999) | 2026-11-26T09:57:39Z | `29fb12bf5` | 344 |
| [45790549503](https://github.com/tett23/golem/actions/runs/45790549503) | 2026-11-26T09:17:10Z | `4ab43dd4b` | 353 |
| [45782760168](https://github.com/tett23/golem/actions/runs/45782760168) | 2026-11-26T08:23:32Z | `a72fb7669` | 278 |
| [45779653066](https://github.com/tett23/golem/actions/runs/45779653066) | 2026-11-26T08:01:04Z | `37b99600b` | 382 |
| [45778475871](https://github.com/tett23/golem/actions/runs/45778475871) | 2026-11-26T07:51:43Z | `091abd195` | 265 |
| [45776789010](https://github.com/tett23/golem/actions/runs/45776789010) | 2026-11-26T07:38:05Z | `e8c4d7b34` | 275 |
| [45769539953](https://github.com/tett23/golem/actions/runs/45769539953) | 2026-11-26T06:38:03Z | `dabf15e99` | 296 |
| [45763351806](https://github.com/tett23/golem/actions/runs/45763351806) | 2026-11-26T05:42:35Z | `71172ba26` | 382 |
| [45762207326](https://github.com/tett23/golem/actions/runs/45762207326) | 2026-11-26T05:31:55Z | `e4413ce2f` | 272 |
| [45761310637](https://github.com/tett23/golem/actions/runs/45761310637) | 2026-11-26T05:23:47Z | `2c49c7bb3` | 353 |
| [45760792453](https://github.com/tett23/golem/actions/runs/45760792453) | 2026-11-26T05:19:04Z | `ae1eb246f` | 230 |
| [45760266546](https://github.com/tett23/golem/actions/runs/45760266546) | 2026-11-26T05:14:21Z | `b4531eb15` | 385 |

## 臨界経路

臨界経路の回数は次のとおりである。
最も長い道が同じ長さで複数ある場合は、依存関係の一つを数えた。

| 経路 | 回数 |
| --- | --- |
| changes、build、parser-fmt-manuscripts、ci | 8 |
| changes、scripts-macos、ci | 5 |
| changes、wasm、ci | 3 |
| changes、verapdf、ci | 2 |
| changes、build、determinism、ci | 2 |

build を通る 10 回では、最後の脚は tests-rest-b が 8 回、tests-driver-b が 2 回だった。
tests-rest-b は x86-64 が 5 回と ARM64 が 3 回で、tests-driver-b はそれぞれ 1 回だった。

## 残ること

[root ADR 0457](../adr/0457-split-the-tests-rest-runner-in-two.md) の「測る」の節に従い、予算を満たすための次の手を新しい ADR で決める。
今回の記録だけでは、CI のイベント、検査の範囲、時間の上限を変えない。
次の手を決めるまでは、[root ADR 0457](../adr/0457-split-the-tests-rest-runner-in-two.md) を未実装のままにする。
