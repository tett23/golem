# ADR 0038: プルリクエストでは環境を変える検査を小さな入力に絞る

ステータス: 採択

## 文脈

[ADR 0029](0029-environment-variation-determinism-test.md) は、実行の環境を変えて出力の一致を確かめる `scripts/env-determinism/check.sh` を定め、CI の `build` ジョブの x86-64 のランナーで `--quick` を付けずに実行するとした。
同じ ADR は、CI の所要時間の上限を自分では決めず、`CONTRIBUTING.md` の約束（CI の実行時間は 5 分以内を保ち、超えたらまず CI を改善する）に従うとしている。
上限を超えたときには、入力の分け方を調整の対象にするとも書いている。

[ADR 0029](0029-environment-variation-determinism-test.md) の実装（#204）の後、CI の実行は 5 分を大きく超えた。
`docs/ci-timings/2026-10-18-after.md` の記録から、数字を引く。
単位は秒である。

| 実行 | 件数 | 実行全体の中央値 | x86-64 の `build` | aarch64 の `build` |
|---|---|---|---|---|
| [ADR 0037](0037-ci-build-job-speedup.md) の後、#204 の前（golem-font を組み直さなかったもの） | 41 | 327 | 296 | 249 |
| #204 の後 | 2 | 457 | 419.5 | 174 |

#204 の後の二回では、検査のステップが 224 秒と 226 秒かかった。
x86-64 の `build` ジョブは、検査を除けば約 195 秒で、aarch64 と同程度である。
検査のステップが、そのまま実行全体の臨界経路に加わっている。

ステップの中の時間は、ログの時刻から次のように分かれる（#204 のプルリクエストの実行 39054482039）。

| 部分 | 秒 |
|---|---|
| 小さな入力（`exprs`、`sample`、`sample-pdf`、`diagnostics`）への 19 の変化と基準のビルド | 約 8 |
| `combined` の `tempest` と `kanikosen` | 約 12 |
| `combined` のパブリックドメインの十冊 | 約 84 |
| `combined` の二つのマニュアル | 約 122 |

漏れの経路の大半を一つずつ当てるのは、小さな入力への 19 の変化であり、それは 10 秒に満たない。
時間の 96% は、大きな入力に `combined` を一回ずつ当てる部分にある。
この部分が捕まえるのは、大きな入力の機能の経路でだけ現れる漏れである。
その種の漏れを持ち込む変更は、どのプルリクエストでも起こりうるが、頻度は小さな入力で捕まる漏れより低い。

下書きのプルリクエスト（#207）で、プルリクエストのときだけ `--quick` を付ける変更を一回だけ測った（実行 39056116247）。
検査のステップは 7 秒、x86-64 の `build` ジョブは 199 秒、実行全体は 238 秒だった。
一回の値であり、件数は少ない。

## 実装すること

### プルリクエストでは `--quick` を付ける

`.github/workflows/ci.yml` の「The outputs do not change with the environment」のステップで、`check.sh` に渡す引数をイベントで変える。

- `pull_request` のときは `--quick` を付ける。小さな入力に、`combined` を含むすべての変化を当てる。
- `main` への push と、`release.yml` からの呼び出し（`workflow_call`）のときは、今と同じく `--quick` を付けない。大きな入力にも `combined` を当てる。

```yaml
- name: The outputs do not change with the environment (docs/adr/0029, docs/adr/0038)
  if: matrix.runner == 'ubuntu-24.04'
  env:
    # pull requests check the small inputs; pushes to main and releases
    # check every input (docs/adr/0038)
    QUICK: ${{ github.event_name == 'pull_request' && '--quick' || '' }}
  run: |
    # QUICK is empty or one word
    # shellcheck disable=SC2086
    GOLEM_REQUIRE_LOCALES=1 GOLEM_REQUIRE_FONTS=1 GOLEM="$(cabal list-bin -v0 golem)" sh scripts/env-determinism/check.sh $QUICK
```

`GOLEM_REQUIRE_LOCALES=1` と `GOLEM_REQUIRE_FONTS=1` はどちらのイベントでも付ける。
`--quick` のときはマニュアルを入力にしないので、フォントの有無は結果に影響しない。
ロケールの検査は小さな入力への変化に含まれるので、`--quick` でも働く。

`check.sh` 自体は変えない。
`--quick` の働き（大きな入力を飛ばす）は [ADR 0029](0029-environment-variation-determinism-test.md) のとおりである。

### `main` で失敗したとき

`main` への push で大きな入力の検査だけが失敗したときは、その push の CI が赤くなる。
直し方は、ほかの検査の失敗と同じく、原因を直すプルリクエストを出すことである。
手元では、`check.sh --only combined --input <名前>` で失敗した入力を再現できる。
リリースは `release.yml` が `ci.yml` を呼ぶので、大きな入力の検査を通らない限り出ない。

### ドキュメント

- README の CI の節の表の `build` の行に、プルリクエストでは小さな入力だけを検査し、`main` への push とリリースではすべての入力を検査することを書く。
- 開発者のマニュアルの第 11 章「CI のジョブ」（`manual-dev/part2/11-ci-jobs.gm`）の `build` の手順と、第 12 章「決定性を守る」（`manual-dev/part2/12-determinism.gm`）の「確かめ方」を、同じ内容に合わせる。大きな入力を変える変更では、手元で `--quick` を付けずに実行することを勧める。
- `docs/specifications.md` の検査の段落に、CI でのイベントごとの違いを書き、この ADR へのリンクを付ける。
- [ADR 0029](0029-environment-variation-determinism-test.md) のステータスを「採択→CI で `--quick` を付けるかどうかは ADR 0038」に変える。

## 実装しないこと

- **検査を別のジョブにして、`build` ジョブと並べること。** [ADR 0029](0029-environment-variation-determinism-test.md) が退けた理由（`golem` の実行ファイルの受け渡しがない）は今も同じである。受け渡しを作っても、検査のジョブは `build` ジョブのビルドが終わるのを待つので、臨界経路は短くならない。検査のジョブで `golem` を組み直せば並べられるが、そのジョブのビルド（x86-64 の `cabal build` の中央値 140.5 秒）と検査（226 秒）で、今より長くなる。
- **`build` ジョブの中で、検査をテストや決定性の検査の出力と並行に走らせること。** ランナーは 4 コアで、`cabal test all` はすでにすべてのコアを使う。[ADR 0037](0037-ci-build-job-speedup.md) が退けた、テストと `scripts/determinism.sh` の並行と同じく、`test/fixtures/sample` の `build/` の作り直しとも競合する。
- **`check.sh` の中で、入力ごとのビルドを並列にすること。** 時間の半分を占める二つのマニュアルは、それぞれ一回のビルドが 40 秒から 80 秒かかり、並列にしても二つの和より短くはならない。`golem` が一回のビルドで使うコアの数との兼ね合いも測っていない。プルリクエストで `--quick` にすれば、この最適化の効果はプルリクエストの所要時間に現れない。
- **大きな入力の検査を、ラベルや変更のパスで選んでプルリクエストでも走らせること。** どの変更が大きな入力でだけ漏れを持ち込むかを、パスから決める規則が立たない。`modules/` のどの変更も出力を変えうる（[ADR 0037](0037-ci-build-job-speedup.md) の「実装しないこと」）。
- **大きな入力の検査を、定時の実行（`schedule`）に移すこと。** `main` への push で走らせれば、漏れを持ち込んだコミットを一つに絞れる。定時の実行では、その間のすべてのコミットが候補になる。
- **入力の一覧と変化の一覧を変えること。** [ADR 0029](0029-environment-variation-determinism-test.md) の検査の中身はそのままにし、CI でどの範囲を走らせるかだけを決める。
- **#204 の前から 5 分を超えていることへの対処。** [ADR 0037](0037-ci-build-job-speedup.md) の後でも、golem-font を組み直さなかった実行の中央値は 327 秒で、目標の 300 秒を超えている。残りの大半は、プルリクエストが変えたパッケージの `cabal build`（x86-64 で中央値 140.5 秒）である。これは別の ADR で扱う。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

`ci.yml` について、次の二つを確かめる。

- `scripts/env-determinism/check.sh` を呼ぶ行が、イベントで決まる引数（`$QUICK`）を受け取ること。今の `ci.yml` は引数を渡さないので失敗する。
- その引数を決める式が、`github.event_name == 'pull_request'` のときだけ `--quick` になること。式の文字列 `github.event_name == 'pull_request' && '--quick' || ''` が `ci.yml` にあることで確かめる。

### 自動テストにできないものの確かめ方

実装のプルリクエストで、次を確かめて結果をプルリクエストに書く。

- プルリクエストの実行のログで、検査が小さな入力だけを組み、`combined` を含む 19 の変化がすべて `ok` であること。`tempest` や `manual` の行が出ないこと。
- マージの後の `main` への push の実行のログで、検査が大きな入力の `combined` を含めて実行され、`SKIP` が出ないこと。
- 所要時間。マージの後、プルリクエストの実行を 5 回以上集めて `scripts/ci/timings.sh --median` で中央値を取り、`docs/ci-timings/` に記録する。見込みは、x86-64 の `build` ジョブが約 205 秒、実行全体が #204 の前と同程度である。

## トレードオフ

- 大きな入力でだけ現れる漏れは、プルリクエストでは見つからず、マージの後の `main` で見つかる。`main` が一時的に赤くなりうる。代わりに、プルリクエストの CI は約 215 秒短くなる。
- 漏れが見つかるのが一つのコミットの後なので、原因の候補はそのコミットに絞れる。定時の実行よりも絞り込みやすい。
- リリースは `ci.yml` 全体を通るので、大きな入力の漏れを含んだままリリースされることはない。
- プルリクエストと `main` で CI の中身が違うことになる。`changes` ジョブによる省略（[ADR 0009](0009-ci-speed.md)、[ADR 0021](0021-docs-workflow-and-ci-gate.md)）と同じく、`main` の保護が求める `ci` ジョブの結果は、プルリクエストでは軽い検査の結果になる。

## 参考文献

- [ADR 0009: CI の高速化](0009-ci-speed.md)
- [ADR 0021: ドキュメントの検査の分離と CI の判定ジョブ](0021-docs-workflow-and-ci-gate.md)
- [ADR 0029: 実行環境を変えて出力の一致を確かめる検査](0029-environment-variation-determinism-test.md)
- [ADR 0037: CI の build ジョブの手戻りをなくす](0037-ci-build-job-speedup.md)
- `docs/ci-timings/2026-10-18-after.md`（#206）
- GitHub Docs, "Events that trigger workflows"（`github.event_name` と `workflow_call` の呼び出し元のイベント）. https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows
