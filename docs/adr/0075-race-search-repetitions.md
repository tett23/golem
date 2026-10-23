# ADR 0075: 並行の競合を探すテストの回数を、CI の夜間の実行で増やす

ステータス: 採択（未実装）

## 文脈

並行の競合は、まれにしか起きない。
競合を探すテストは、繰り返しの回数が少ないと見逃しやすく、逆に、たまに起きた失敗が CI を一度だけ赤くする不安定なテストにもなる。

2026-10-23 のテストの品質の点検で、次の回数を確かめた。

- [modules/golem-driver/test/ParallelSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ParallelSpec.hs) の [134 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ParallelSpec.hs#L134)、[142 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ParallelSpec.hs#L142)、[171 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ParallelSpec.hs#L171) のプロパティは、それぞれ 25、8、10 回である。
- [modules/golem-font/test/ConcurrencySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-font/test/ConcurrencySpec.hs#L54) のプロパティは 30 回である。
- 並列のビルドを fixture の本で繰り返すテスト（[ParallelSpec.hs の `bookTest`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ParallelSpec.hs#L189-L197)）は、`GOLEM_PARALLEL_REPEAT` の回数だけ繰り返し、既定は 1 である。CI はこの変数を設定していない。
- 同じ環境で二回ビルドした出力の一致（[ADR 0002](0002-determinism.md) の 56 行め）は、[modules/golem-driver/test/PageElementsSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PageElementsSpec.hs#L407) の「parallel and sequential builds agree, and twice」が持つが、golem-driver-test は `-threaded` でないスイートである。

点検の報告は「hedgehog のシードは CI で固定も記録もされていない」としたが、これは半分だけ正しい。
tasty-hedgehog は、失敗したときに再現のためのシードとサイズをログに書く。
失敗の再現はできる。
記録されないのは、通った実行のシードであり、これは再現に要らない。

## 実装すること

- 回数を環境変数 `GOLEM_RACE_TESTS` で掛け算できるようにする。値は 1 以上の整数で、未設定なら 1 とする。上の四つのプロパティの `withTests` の回数をこの値で掛け、並列のビルドの繰り返しの回数はこの値とする。`GOLEM_PARALLEL_REPEAT` は廃止し、[ParallelSpec.hs の冒頭の注釈](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ParallelSpec.hs#L15-L16) を書き直す。
- プルリクエストの CI では今の回数（掛ける数 1）のままとする。
- [ci.yml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml) とは別に、夜間に main で走るワークフロー（`.github/workflows/race.yml`）を足し、`GOLEM_RACE_TESTS=40` で golem-driver-parallel-test、golem-font-race-test と、golem-font-test の ConcurrencySpec（`--test-options=-p` で選ぶ）だけを走らせる。失敗したら、ログのシードを添えて issue にする手順を README の CI の節に書く。
- race.yml は `schedule` で毎日一回起動するが、テストを走らせるのは、前回の実行から main が変わった日だけとする。Golem の開発が落ち着いた後も毎日走らせるのは、Actions の実行時間の無駄になる。
  - 判定は、起動した実行の `GITHUB_SHA` と、race.yml の main での直近の成功した実行の head の SHA を比べる。`schedule` で起動した実行の `GITHUB_SHA` は、既定のブランチの最新のコミットである。直近の成功した実行の SHA は `gh run list --workflow race.yml --branch main --status success --limit 1 --json headSha --jq '.[0].headSha'` で得る。二つが等しければテストを走らせずに成功で終え、異なるか、成功した実行がまだなければ走らせる。
  - 「直近 24 時間のコミットの有無」では判定しない。`schedule` の起動は遅れることがあり、時刻の窓で区切ると、窓の境のコミットを見落とすか二度数える。SHA の比較は、起動の時刻によらず同じ結果になる。
  - テストを走らせずに終えた実行も成功として記録され、その head の SHA は前回と同じなので、次の判定は変わらない。
  - 判定は小さなシェルのスクリプト（`scripts/ci/race-needed.sh`）にし、`gh` のコマンドを環境変数 `GH` で差し替えられるようにする。race.yml には `permissions: actions: read` を足し、`GH_TOKEN` に `github.token` を渡す。
  - `workflow_dispatch` で手で起動したときは、判定せずに走らせる。
- README.md の CI の表に race.yml の行を足し、開発者のマニュアルの CI の章に同じことを書く。

## 実装しないこと

- 競合を決定的に再現する仕組み（スケジューラの制御）を入れること。
- [PageElementsSpec.hs の 407 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PageElementsSpec.hs#L407) のテストを変えること。並列の経路を繰り返すのは golem-driver-parallel-test の役目とし、夜間の実行で回数を増やす。
- プルリクエストの CI の回数を増やすこと。CI の時間が延び、まれな失敗がプルリクエストを止める。

## テスト設計

- `race-needed.sh` の判定：[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh) に、偽の `gh`（`GH` で差し替える。決まった SHA を標準出力に書くシェルのスクリプト）で、SHA が等しければ走らせない、異なれば走らせる、空（成功した実行がない）なら走らせる、の三つを確かめる項目を足す。スクリプトがまだないので落ちる。
- ワークフローの設定は自動テストにしない。設定の確かめ方として、[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh) に、race.yml が `GOLEM_RACE_TESTS` を設定し、この三つだけを走らせることを確かめる項目を足す（今の `step_if` と同じ形）。race.yml がまだないので落ちる。
- 実装の後に、`GOLEM_RACE_TESTS=40` でこの三つを手元で走らせ、所要時間を測って `docs/ci-timings/` に記録する。所要時間が 30 分を超えるなら、掛ける数を下げる。

## トレードオフ

- 夜間の実行は、プルリクエストを止めない代わりに、競合を持ち込んだ変更の後で見つかる。見つけた時点で、どの変更が持ち込んだかを探す手間がかかる。
- 新しいワークフローは、main が変わった日に Actions の実行時間を使う。main が変わらない日も、判定のために数十秒だけ起動する。
- 判定は成功した実行と比べるので、競合で落ちた後に main が変わらなければ、翌日も同じコミットで走る。落ちたままの間は毎日走るが、競合を直すコミットが入れば止まる。前回の実行の結論を問わずに比べる案は、取り消した実行や基盤の不調で落ちた実行の後に、一度も確かめていないコミットを飛ばすので採らない。
- 公開のリポジトリでは、60 日のあいだリポジトリに動きがないと、GitHub は `schedule` のワークフローを止める。その間は main も変わらないので見逃しはないが、開発を再開したときに race.yml を有効に戻す必要がある。

## 参考文献

- [ADR 0002](0002-determinism.md)
- [ADR 0050](0050-run-golem-on-every-processor.md)
- tasty-hedgehog、失敗の再現（`--hedgehog-replay`）
- GitHub Docs、Events that trigger workflows（`schedule` の `GITHUB_SHA`）
- GitHub Docs、Disabling and enabling a workflow（60 日で止まる `schedule`）
- GitHub CLI、`gh run list`
