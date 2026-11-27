# 実行したワークフローの版による CI の時間の再照合（2026-11-27）

[root ADR 0472](../adr/0472-count-reusable-workflows-in-ci-timing.md) の A1 の同じ 20 回を、実行したワークフローの版で再照合した。
中央値は 864 秒で、直前の計測と 20 回すべての秒が一致した。
予算 300 秒の超過は 564 秒であり、改善したことにはならない。

## 訂正する事項

[直前の訂正記録](2026-11-27-reusable-workflow-critical-path.md) は、API の `headSha` でワークフローを選んでいた。
GitHub の `headSha` と、PR の一時的なマージ版として実行したワークフローのコミットは、この 20 回すべてで異なる。
今回は changes ジョブの最初の checkout のマージコミットをログから確かめ、再利用ワークフローの API の版とも、該当する 12 回すべてで一致することを確かめた。
直前の記録と入力は変更せず、この記録で版の取り方を訂正する。

新しい CI は changes ジョブで `GITHUB_WORKFLOW_SHA` を記録する。
この変数はワークフローファイルのコミットを表す（[GitHub の変数の仕様](https://docs.github.com/en/actions/reference/workflows-and-actions/variables)）。
ローカルの呼出先は呼出元と同じコミットを使う（[再利用ワークフローの仕様](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)）。
計測スクリプトは PR の head の値へ推測で戻さず、実行版を確定できなければ失敗する。

## 入力と再現方法

[今回の 20 回の入力](2026-11-27-ci-critical-path-at-execution-revisions/) は、以前のジョブの時刻と実行のメタデータを保持する。
`run.headSha` は API が返した PR の head、`workflow_revision` は実行した版、`workflow_revision_job` は照合に使った changes ジョブの ID である。
`workflow_files` に、その版から Git で取り出した ci.yml とローカルの呼出先の内容を保存した。
一時的なマージコミットを後で取得できなくても、この保存データだけで再計測できる。

```sh
sh scripts/ci/ci-critical-path.sh docs/ci-timings/2026-11-27-ci-critical-path-at-execution-revisions/*.json
```

保存ファイルの展開先は一時ディレクトリに限る。
ワークフローのディレクトリの外を指すパス、欠けた呼出先、循環、対応しないジョブがあれば、中央値を出さずに失敗する。

| 実行 | PR の head | 実行した版 | changes ジョブ | 秒 |
| --- | --- | --- | --- | --- |
| [45854683253](https://github.com/tett23/golem/actions/runs/45854683253) | `02811dcb1652d2f00140b54cd3357ad8a25a2afb` | `d1601e1bbde7232dbf6ac8ebbbf1d63a5072ceb6` | [140038833652](https://github.com/tett23/golem/actions/runs/45854683253/job/140038833652) | 907 |
| [45846112729](https://github.com/tett23/golem/actions/runs/45846112729) | `b4f2a30f6f232b66ffb0d96a8727f438c16eb431` | `2afe70fb7c4d5f5c44cb6a4ce5ce52dac9e0f0f0` | [140010355269](https://github.com/tett23/golem/actions/runs/45846112729/job/140010355269) | 880 |
| [45839811994](https://github.com/tett23/golem/actions/runs/45839811994) | `123153b56197977f1cb896f6600eb0dfebdbfc27` | `19096081493ca4a547d6ccc3159c30fe6287f983` | [139978189384](https://github.com/tett23/golem/actions/runs/45839811994/job/139978189384) | 1246 |
| [45828312661](https://github.com/tett23/golem/actions/runs/45828312661) | `7527d5144b064d17278ea7a8392b0fab307a92f8` | `9f07755db5b1cd3a9f4dc9548bf027e60e88a392` | [139938550776](https://github.com/tett23/golem/actions/runs/45828312661/job/139938550776) | 922 |
| [45818968689](https://github.com/tett23/golem/actions/runs/45818968689) | `d918c8cb53b7b3ae686d19b6fd32eabe6f970795` | `d122f92f2ab24cc7754fe5eadc1a1bc950ef97c3` | [139922409199](https://github.com/tett23/golem/actions/runs/45818968689/job/139922409199) | 1255 |
| [45806887362](https://github.com/tett23/golem/actions/runs/45806887362) | `79b9172e156eede9f0e09d95f293deb8d7e2c33a` | `21aebc7c31b105cd4727f16489a858754ce11d7b` | [139864383275](https://github.com/tett23/golem/actions/runs/45806887362/job/139864383275) | 1232 |
| [45802211168](https://github.com/tett23/golem/actions/runs/45802211168) | `d866976cb71a8bc53494919c1cfca004c86a8439` | `acf8a03534ed71e61d7be80b8ab5cf7124a20250` | [139848074028](https://github.com/tett23/golem/actions/runs/45802211168/job/139848074028) | 918 |
| [45798868746](https://github.com/tett23/golem/actions/runs/45798868746) | `3319c8a99be7ded691d3022f2a49548277142697` | `dde971c5d04a4172f8b996cb55486501a793458b` | [139836516497](https://github.com/tett23/golem/actions/runs/45798868746/job/139836516497) | 1234 |
| [45796807999](https://github.com/tett23/golem/actions/runs/45796807999) | `29fb12bf5934a1026683a465bc2e4783857c6f44` | `bfc613654c9fe7f3dcde6f710a0dd83ae834535c` | [139841176918](https://github.com/tett23/golem/actions/runs/45796807999/job/139841176918) | 896 |
| [45790549503](https://github.com/tett23/golem/actions/runs/45790549503) | `4ab43dd4b03c1fbd6ed5051062d83bcd41b07045` | `2f3c106607340b702e56b58e9cba95801227ea9a` | [139808163517](https://github.com/tett23/golem/actions/runs/45790549503/job/139808163517) | 848 |
| [45782760168](https://github.com/tett23/golem/actions/runs/45782760168) | `a72fb7669ebdd8cfaccaf908810f9ba5e711b764` | `ee2ca182cedc5e18b68b9cefbb0c375c603af6f9` | [139781958502](https://github.com/tett23/golem/actions/runs/45782760168/job/139781958502) | 793 |
| [45779653066](https://github.com/tett23/golem/actions/runs/45779653066) | `37b99600b65c2cdbe22ae98566900a49c190e412` | `b56967c3e6df84d6e55c9e5958c171b5746014a0` | [139771724684](https://github.com/tett23/golem/actions/runs/45779653066/job/139771724684) | 1094 |
| [45778475871](https://github.com/tett23/golem/actions/runs/45778475871) | `091abd19567e165730781ad56f01e685f84c11d8` | `3a2775d35ed83b28a37f2002c27216f05b9ddc46` | [139767845848](https://github.com/tett23/golem/actions/runs/45778475871/job/139767845848) | 265 |
| [45776789010](https://github.com/tett23/golem/actions/runs/45776789010) | `e8c4d7b34c92f7757f8723677cdc1bd7d76b77fc` | `a617b829bd266c68ffe9e569386bf6c927276319` | [139762258471](https://github.com/tett23/golem/actions/runs/45776789010/job/139762258471) | 275 |
| [45769539953](https://github.com/tett23/golem/actions/runs/45769539953) | `dabf15e9930dbe46b003b2ae53ef481c6951bbed` | `2fc8d30c0676070d3f06082c9b2a7b32e28d9c10` | [139738936855](https://github.com/tett23/golem/actions/runs/45769539953/job/139738936855) | 296 |
| [45763351806](https://github.com/tett23/golem/actions/runs/45763351806) | `71172ba2651dbdbbdcdcf42134e12f4f5388325c` | `fbdd72037ff47e4f087c77e171dbb9081d4d7482` | [139718309051](https://github.com/tett23/golem/actions/runs/45763351806/job/139718309051) | 382 |
| [45762207326](https://github.com/tett23/golem/actions/runs/45762207326) | `e4413ce2f5ffd36b469cf78a87c22e626f058bed` | `fe7ce9f603060c7e04d1a132b78ae92aea45024d` | [139714589856](https://github.com/tett23/golem/actions/runs/45762207326/job/139714589856) | 272 |
| [45761310637](https://github.com/tett23/golem/actions/runs/45761310637) | `2c49c7bb30ba74f18603554550ad0be700ecdb12` | `ad00b97840129fbd0ecf9638a1912f397275cbad` | [139715235500](https://github.com/tett23/golem/actions/runs/45761310637/job/139715235500) | 353 |
| [45760792453](https://github.com/tett23/golem/actions/runs/45760792453) | `ae1eb246f29017933f7fcbf8822dbd12906e7a04` | `2f433c54723a95fc40f98fbaff0a1cbe83bc0aad` | [139710033400](https://github.com/tett23/golem/actions/runs/45760792453/job/139710033400) | 230 |
| [45760266546](https://github.com/tett23/golem/actions/runs/45760266546) | `b4531eb158925ba4dc6e7746547df5a087f4d9c2` | `ed3756211b8aa9a492d1fbd365dabcbd413c7356` | [139708354782](https://github.com/tett23/golem/actions/runs/45760266546/job/139708354782) | 385 |

## 残る作業

予算値、検査のイベント、証明の範囲は変更していない。
予算超過の改善は別の ADR で決める。
