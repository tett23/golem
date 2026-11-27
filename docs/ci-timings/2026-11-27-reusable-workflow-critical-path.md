# 再利用ワークフローを含む CI の時間の訂正（2026-11-27）

[root ADR 0472](../adr/0472-count-reusable-workflows-in-ci-timing.md) の A1 に従い、[root ADR 0457](../adr/0457-split-the-tests-rest-runner-in-two.md) と同じ 20 回を再計測した。
中央値は 864 秒で、予算 300 秒を 564 秒超える。
以前の 318 秒は再利用ワークフローの証明ジョブを落としていたため、予算との比較にはこの訂正値を使う。

## 入力と再現方法

対象の実行番号と時刻は、[以前の記録](https://github.com/tett23/golem/blob/7c82b2df4f53510e1cf01d22034ab95d362f1994/docs/ci-timings/2026-11-27-pull-request-ci-after-adr-0457.md) と同じである。
以前の記録と入力は変更していない。
[今回の入力](2026-11-27-reusable-workflow-critical-path/) は同じジョブのフィールドを保ち、実行したコミットを `workflow_revision` に追加した。
各入力の `run.headSha` と `workflow_revision` は一致する。

計測には、この記録とともに追加した `scripts/ci/ci-critical-path.sh` と `scripts/ci/ci-workflow-graph.sh` を使った。
Git のローカルの履歴から各実行の `.github/workflows/` を読み、呼出先も同じコミットから展開する。
再現する checkout には、表のコミットの Git オブジェクトが必要である。
読めないコミットや呼出先があれば、時間をゼロとして続けずに失敗する。

```sh
sh scripts/ci/ci-critical-path.sh docs/ci-timings/2026-11-27-reusable-workflow-critical-path/*.json
sh scripts/ci/ci-critical-path.sh --graph
```

## 結果の照合

この 20 回では証明の子ジョブが互いに並列であることを、各コミットのワークフローで照合した。
通常のジョブの旧計測値と、changes の時間、最長の証明の時間、ci の時間の和のうち、大きい方を取る別計算とも、20 回すべてで一致した。
入力のジョブのデータと実行のメタデータは、以前の保存データと構造上等しいことも確かめた。
ランナーの待ち時間は数えていない。

| 実行 | ワークフローのコミット | 訂正した秒 | 旧計測の秒 |
| --- | --- | --- | --- |
| [45854683253](https://github.com/tett23/golem/actions/runs/45854683253) | `02811dcb1652d2f00140b54cd3357ad8a25a2afb` | 907 | 290 |
| [45846112729](https://github.com/tett23/golem/actions/runs/45846112729) | `b4f2a30f6f232b66ffb0d96a8727f438c16eb431` | 880 | 330 |
| [45839811994](https://github.com/tett23/golem/actions/runs/45839811994) | `123153b56197977f1cb896f6600eb0dfebdbfc27` | 1246 | 317 |
| [45828312661](https://github.com/tett23/golem/actions/runs/45828312661) | `7527d5144b064d17278ea7a8392b0fab307a92f8` | 922 | 304 |
| [45818968689](https://github.com/tett23/golem/actions/runs/45818968689) | `d918c8cb53b7b3ae686d19b6fd32eabe6f970795` | 1255 | 317 |
| [45806887362](https://github.com/tett23/golem/actions/runs/45806887362) | `79b9172e156eede9f0e09d95f293deb8d7e2c33a` | 1232 | 390 |
| [45802211168](https://github.com/tett23/golem/actions/runs/45802211168) | `d866976cb71a8bc53494919c1cfca004c86a8439` | 918 | 394 |
| [45798868746](https://github.com/tett23/golem/actions/runs/45798868746) | `3319c8a99be7ded691d3022f2a49548277142697` | 1234 | 319 |
| [45796807999](https://github.com/tett23/golem/actions/runs/45796807999) | `29fb12bf5934a1026683a465bc2e4783857c6f44` | 896 | 344 |
| [45790549503](https://github.com/tett23/golem/actions/runs/45790549503) | `4ab43dd4b03c1fbd6ed5051062d83bcd41b07045` | 848 | 353 |
| [45782760168](https://github.com/tett23/golem/actions/runs/45782760168) | `a72fb7669ebdd8cfaccaf908810f9ba5e711b764` | 793 | 278 |
| [45779653066](https://github.com/tett23/golem/actions/runs/45779653066) | `37b99600b65c2cdbe22ae98566900a49c190e412` | 1094 | 382 |
| [45778475871](https://github.com/tett23/golem/actions/runs/45778475871) | `091abd19567e165730781ad56f01e685f84c11d8` | 265 | 265 |
| [45776789010](https://github.com/tett23/golem/actions/runs/45776789010) | `e8c4d7b34c92f7757f8723677cdc1bd7d76b77fc` | 275 | 275 |
| [45769539953](https://github.com/tett23/golem/actions/runs/45769539953) | `dabf15e9930dbe46b003b2ae53ef481c6951bbed` | 296 | 296 |
| [45763351806](https://github.com/tett23/golem/actions/runs/45763351806) | `71172ba2651dbdbbdcdcf42134e12f4f5388325c` | 382 | 382 |
| [45762207326](https://github.com/tett23/golem/actions/runs/45762207326) | `e4413ce2f5ffd36b469cf78a87c22e626f058bed` | 272 | 272 |
| [45761310637](https://github.com/tett23/golem/actions/runs/45761310637) | `2c49c7bb30ba74f18603554550ad0be700ecdb12` | 353 | 353 |
| [45760792453](https://github.com/tett23/golem/actions/runs/45760792453) | `ae1eb246f29017933f7fcbf8822dbd12906e7a04` | 230 | 230 |
| [45760266546](https://github.com/tett23/golem/actions/runs/45760266546) | `b4531eb158925ba4dc6e7746547df5a087f4d9c2` | 385 | 385 |

## 残る予算超過

予算の値、検査を走らせるイベント、証明の範囲は変更していない。
証明の再利用ワークフローを含む最も長い道を短くする次の改善は、別の ADR で決める。
この計測の訂正は、その改善を実装したことを意味しない。
