# CI の所要時間（2026-10-27、visual ジョブを足した後）

[ADR 0095](../adr/0095-visual-job-in-ci.md) の実装（[#430](https://github.com/tett23/golem/pull/430)）で足した見た目の回帰テストの、CI の所要時間の記録である。
表は `gh run view <id> --json jobs | scripts/ci/timings.sh` の出力から、見た目の回帰テストに関わる行を抜いたものである。
単位は秒である。
2026-10-27 に作り、コミットした後は変更しない。

## 参照と一致した実行

[#430](https://github.com/tett23/golem/pull/430) の最初の実行（[40363424152](https://github.com/tett23/golem/actions/runs/40363424152)）。
`third_party/shem` のキャッシュはなく、`fetch-shem.sh` が x86-64 の Linux のアーカイブを取った。

| ジョブ | ステップ | 秒 |
|---|---|---|
| `changes` | `Tests of the scripts of the visual regression test (docs/adr/0093)` | 4 |
| `scripts-macos` | `Tests of the scripts of the visual regression test` | 14 |
| `build (ubuntu-24.04, outputs)` | ジョブ全体 | 376 |
| `build (ubuntu-24.04, outputs)` | `Outputs for the determinism check; the manuals build without diagnostics` | 23 |
| `build (ubuntu-24.04, outputs)` | `The PDFs of the visual regression test (docs/adr/0095)` | 53 |
| `build (ubuntu-24.04, outputs)` | `Upload the PDFs of the visual regression test` | 3 |
| `visual` | ジョブ全体 | 225 |
| `visual` | `Set up job` | 1 |
| `visual` | `Run actions/checkout@v7` | 3 |
| `visual` | `Cache shem (docs/adr/0093)` | 0 |
| `visual` | `shem (docs/adr/0093)` | 0 |
| `visual` | `Run actions/download-artifact@v8` | 1 |
| `visual` | `The pages match the references (docs/adr/0094, docs/adr/0095)` | 216 |
| `visual` | `Summary of the visual regression test (docs/adr/0095)` | - |
| `visual` | `Post Cache shem (docs/adr/0093)` | 1 |
| `visual` | `Post Run actions/checkout@v7` | 0 |
| `visual` | `Complete job` | 0 |

## 参照の一行を書き換えた実行

`scripts/visual/pages/tempest.txt` の一行めの SHA-256 を書き換えた、捨てるプルリクエスト（[#431](https://github.com/tett23/golem/pull/431)、閉じた）の実行（[40363466922](https://github.com/tett23/golem/actions/runs/40363466922)）。
`visual` は `changed tempest page-0001` の一行を出して失敗し、要約の手順が動き、`ci` が失敗した。

| ジョブ | ステップ | 秒 |
|---|---|---|
| `build (ubuntu-24.04, outputs)` | ジョブ全体 | 359 |
| `build (ubuntu-24.04, outputs)` | `The PDFs of the visual regression test (docs/adr/0095)` | 51 |
| `visual` | ジョブ全体 | 222 |
| `visual` | `The pages match the references (docs/adr/0094, docs/adr/0095)` | 215 |
| `visual` | `Summary of the visual regression test (docs/adr/0095)` | 0 |
| `ci` | ジョブ全体 | 5 |

## 読み取れること

- 比べる手順は 216 秒と 215 秒だった。上限の 600 秒には収まったが、予算の 2 分（120 秒）を超えた。[ADR 0095](../adr/0095-visual-job-in-ci.md) の決めたとおり、予算を超えてもジョブは失敗させない。入力の数か解像度の見直しが要る。
- 手元の Apple silicon の macOS では、同じ shem の版で 17 の PDF を描くのに約 16 秒（[ADR 0094](../adr/0094-visual-regression-page-hashes-at-72-dpi.md) の測定）だった。CI はその 13 倍ほどかかった。原因は調べていない。
- 描く時間の大半はマニュアルで、使い手のマニュアル（310 ページ）が 59 秒、開発者のマニュアル（173 ページ）が 28 秒だった（標準エラーに出る入力の名前の時刻から）。
- `outputs` のランナーで 17 の PDF を組む手順は 53 秒と 51 秒だった。
- 二つの実行の比べる手順の差は 1 秒で、揺れは小さい。
