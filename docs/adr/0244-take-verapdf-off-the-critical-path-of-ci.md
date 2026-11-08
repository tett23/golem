# ADR 0244: `verapdf` を `build` の全体でなく成果物 `conformance-pdfs` を待つジョブにし、CI の臨界経路から外す

ステータス: 採択（未実装）

## 文脈

### プルリクエストの CI の半分が 5 分を超える

CONTRIBUTING は、プルリクエストの CI を 5 分以内に保ち、超えたらほかの作業を止めて CI を直すと定める（[`CONTRIBUTING.md`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/CONTRIBUTING.md#L393-L397)）。
[docs/ci-timings/2026-11-08-ci-caches-under-the-limit.md](../ci-timings/2026-11-08-ci-caches-under-the-limit.md) は、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の後の 5 回のうち 2 回が超えたと記録した。

[docs/ci-timings/2026-11-09-ci-critical-path-and-download-failures.md](../ci-timings/2026-11-09-ci-critical-path-and-download-failures.md)（以下「記録」）で、2026-11-07T06:22Z から 2026-11-08T22:19Z までの `ci.yml` の 400 回の実行を数えた。
プルリクエストで `build` が走って成功した 118 回の実行全体は、中央値 298 秒、第 3 四分位 376 秒、最大 1,105 秒で、56 回（47%）が 5 分を超えた（記録の表 2）。
待ち行列の秒はどのジョブも中央値 2 秒から 4 秒で、ランナーの不足はない（表 4）。

### 最後に終わるのは `verapdf` である

118 回のうち 115 回で、最後に終わるジョブ（`ci` を除く）は `verapdf` だった（表 3）。
`verapdf` は `needs: build` で `build` の 7 つのランナーすべてを待ち（[`ci.yml`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L1069-L1090)）、その後に Nix の導入（4 秒）、veraPDF の取得（中央値 20 秒）、検査（中央値 33 秒）を行う。
最後の `build` のランナーの終わりから `verapdf` の終わりまでは、中央値 68 秒、第 3 四分位 77 秒である。
その後に `ci` の 6 秒が続く。

`verapdf` が読む成果物 `conformance-pdfs` は、`outputs` のランナーが `cabal build` の直後に作って上げる（[`ci.yml`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L446-L454)）。
visual-pdfs の 47 秒と conformance-pdfs の 7 秒の後なので、`cabal build` の終わりから約 55 秒後である。
`outputs` のランナーはその後にも約 85 秒の手順（決定性の出力 30 秒、マニュアルのプリフライト 31 秒、epubcheck の 4 回で約 20 秒）を持つ（表 5）。
つまり、`verapdf` の入力は `outputs` の終わりの 85 秒前にそろっていて、`verapdf` はそれから `build` の全体の終わりまで待ち、さらに 68 秒かけている。

`visual`、`editors-lsp`、`wasm` は、同じ `outputs` のランナーの成果物を `scripts/visual/wait-pdfs.sh` で待ち、`build` の全体を待たない（[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）。
`verapdf` だけが `needs: build` のままである。
[ADR 0183](0183-tagged-pdf-and-pdf-a.md) が `verapdf` を足したとき、`visual` の待ち方は [ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) で決まっていたが、`verapdf` には適用しなかった。

### `verapdf` を外した後の見積もり

記録の表 2 の「`verapdf` を臨界経路から外したと仮定」の行は、`verapdf`、`determinism`、`ci` を除くジョブの最後の終わりに、`determinism` の 7 秒と `ci` の 6 秒を足したものである。
118 回の中央値は 298 秒から 234 秒に、5 分を超える実行は 56 回（47%）から 34 回（29%）になる。
`main` への push（86 回）は、中央値 372 秒から 328 秒に、超える実行は 77 回（90%）から 49 回（57%）になる。

残る 34 回の多くは、`cabal build` が長い実行である。
プルリクエストは `main` の `dist-newstyle` から変更をビルドし直すので、`cabal build` は中央値 31 秒、第 3 四分位 95 秒、第 9 十分位 165 秒と幅が広く、118 回のうち 24 回は 121 秒以上かかった（表 7）。
この幅は変更が触るモジュールで決まり、ジョブの並べ替えでは縮まない。

### `build` のランナーのあいだの差

`verapdf` の後に最後に終わる `build` のランナーは、x86-64 の `outputs`（62 回）と x86-64 の `tests-rest`（44 回）である（表 3）。
`outputs` は `cabal build` の後に約 140 秒、`tests-rest` は約 99 秒のテストを持つ。
x86-64 のテストは `tests-driver` が中央値 71 秒、`tests-rest` が 99 秒で、aarch64 は 68 秒と 84 秒である（表 5）。

`outputs` の手順を別のランナーに移して 60 秒縮めたと仮定しても、118 回の中央値は 234 秒から 232 秒にしかならない（記録の条件の節と同じ方法で数えた）。
次に遅い `tests-rest` がほぼ同じ時刻に終わるからである。

## 実装すること

### 1. `verapdf` は `conformance-pdfs` を待つ

`ci.yml` の `verapdf` を次のように変える。

- `needs: build` を `needs: [changes]` と `if: needs.changes.outputs.build == 'true'` にする（`visual`、`editors-lsp`、`wasm` と同じ）。
- `timeout-minutes` を 30 から 75 にする（キャッシュのないビルドを待つ `visual` と同じ）。
- 手順の順は、checkout、`cachix/install-nix-action`、veraPDF の取得（`nix build`、[ADR 0243](0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md) のトークンつき）、`scripts/visual/wait-pdfs.sh "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" 'build (ubuntu-24.04, outputs)' conformance-pdfs`（`timeout -k 10 3600`）、`actions/download-artifact`、検査、とする。Nix の導入と veraPDF の取得は待つ前に終える。
- `wait-pdfs.sh` は `GH_TOKEN` と `GH_REPO` を受け取る。`wasm` と `editors-lsp` は `contents: read` だけで同じ待ち方をしているので、権限は変えない。
- `outputs` のランナーが `conformance-pdfs` を上げずに終わったときは、`wait-pdfs.sh` が終了コード 1 で終わり、`verapdf` は失敗する（`visual` と同じ）。
- `ci` の `needs` は変えない。`verapdf` は引き続き `main` の保護が求める検査の一つである。

### 2. `outputs` の手順の順は変えない

`conformance-pdfs` を visual-pdfs より前に作れば `verapdf` は 47 秒早く始まるが、`visual` が 7 秒遅くなる。
どちらも `outputs` の終わりの前に終わるので、順は今のままとする。

### 3. 記録

- 実装のプルリクエストとそのマージの後、プルリクエストの実行を 10 回以上集め、記録と同じ方法（最初のジョブの作成から最後のジョブの終わりまで。最後に終わるジョブの数）で `docs/ci-timings/` に書く。中央値が 234 秒前後、最後に終わるジョブが `build` のランナーになることを確かめる。
- CONTRIBUTING の 5 分の方針は変えない。

### 4. 検査の更新

`scripts/ci/test.sh` の `ci.yml` の構造の検査に、`verapdf` の `needs` が `build` を含まないこと、`wait-pdfs.sh` を `conformance-pdfs` で呼ぶこと、`nix build` の手順が `wait-pdfs.sh` の手順より前にあることを足す。

### 5. 文書

- README.md の CI のジョブの表の `verapdf` の行に、`outputs` の成果物を待つことを書く。
- [ADR 0183](0183-tagged-pdf-and-pdf-a.md) のステータスの行に、`verapdf` の待ち方はこの ADR が決めたと書く。
- `docs/roadmap.md` の「CI のキャッシュの量」の項の、所要時間を数え直す部分は、この ADR の記録で代える。

## 実装しないこと

- **`outputs` のランナーの分割**。マニュアルのプリフライトと epubcheck を 8 つめのランナーに移しても、中央値は 2 秒しか縮まない（文脈）。ランナーが一つ増えると、キャッシュの復元が一回あたり約 0.6 GB 増える（[ADR 0167](0167-leave-cache-restore-failures-as-misses.md) の egress）。
- **テストスイートの配分の変更**。x86-64 の `tests-rest`（99 秒）と `tests-driver`（71 秒）の差は 28 秒で、そろえれば最も遅いテストのランナーは 14 秒ほど縮む。スイートごとの時間を測っていないので、この ADR では決めない（「メンテナーが決めること」の 2）。
- **変更のないパッケージのテストを省くこと**。CONTRIBUTING が挙げる手段の一つだが、変更したパッケージとそれに依存するパッケージの閉包を `plan.json` から求める規則、`manual/` や `docs/diagnostics.md` やスクリプトの変更をどのテストに結びつけるかの規則、`main` への push ではすべてを走らせることを決める必要がある。この ADR の効果を測ってから、別の ADR で扱う（「メンテナーが決めること」の 3）。
- **`main` への push の時間**。最後に終わる `build` のランナーは `env`（86 回のうち 77 回。すべての入力の環境の検査で中央値 275 秒）で、5 分の方針はプルリクエストのものである。
- **`determinism` と `ci` の時間**。合わせて約 13 秒で、ジョブを起こす時間がほとんどである。
- **`visual`、`editors-lsp`、`wasm` の待ち方**。すでに成果物を待っている。
- [ADR 0009](0009-ci-speed.md) が退けた、大きいランナー、aarch64 の省略、GHC を含むコンテナ。退けた理由は変わっていない。

## 不変条件

- **I1**：`verapdf` の検査の手順は、同じ実行の同じ試行で `build (ubuntu-24.04, outputs)` が `conformance-pdfs` を上げた後にだけ始まる（`wait-pdfs.sh` が 0 で終わる）。
- **I2**：`build (ubuntu-24.04, outputs)` が `conformance-pdfs` を上げずに終わったとき、`verapdf` は失敗する（`wait-pdfs.sh` が 1 で終わる）。
- **I3**：`verapdf` の `needs` は `build` を含まず、`ci` の `needs` は `verapdf` を含む。
- **I4**：`verapdf` でネットワークから取る手順（Nix の導入、veraPDF の取得）は、`wait-pdfs.sh` の手順より前にある。待っている時間に取るので、待ちの後に残るのは成果物のダウンロードと検査だけである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `outputs` のランナー | `conformance-pdfs` を上げて成功、上げる前に失敗、上げた後に失敗 |
| 試行 | 1 回め、再実行（`GITHUB_RUN_ATTEMPT` が 2） |
| `wait-pdfs.sh` が見るジョブの名前 | `build (ubuntu-24.04, outputs)`、`release.yml` から呼ばれたときの `ci / build (ubuntu-24.04, outputs)` |
| `conformance-pdfs` | 上がっている、まだない、期限切れ |

I1、I2 の `wait-pdfs.sh` の振る舞いは、`scripts/visual/test.sh` の既存のテスト（偽の `gh`）が、成果物の名前を引数で変えたときも含めて確かめている（[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)）。

## テスト設計

`scripts/ci/test.sh` の `ci.yml` の構造の検査に、次を先に足し、今の `ci.yml` で失敗することを確かめてから実装する。

- I3：`verapdf` の `needs` に `build` がなく、`changes` があること。`if` に `needs.changes.outputs.build == 'true'` があること。`ci` の `needs` に `verapdf` があること。
- I1、I2：`verapdf` に `scripts/visual/wait-pdfs.sh` を呼ぶ手順があり、その引数の成果物が `conformance-pdfs`、ジョブが `build (ubuntu-24.04, outputs)` であること。
- I4：`verapdf` の手順の並びで、`cachix/install-nix-action` と `nix build` の手順が `wait-pdfs.sh` の手順より前、`actions/download-artifact` と検査の手順が後にあること。
- `verapdf` の `timeout-minutes` が 75 であること。

`wait-pdfs.sh` 自体のテスト（`scripts/visual/test.sh`）は変えない。
成果物の名前を引数で与える形は [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) で足され、テストがある。

CI を走らせて確かめること（実装のプルリクエストの説明に書く）。

- 実装のプルリクエストの実行で、`verapdf` が `outputs` の終わりより前に終わること、最後に終わるジョブが `build` のランナーであること。
- `outputs` のランナーを失敗させた実行（`conformance-pdfs.sh` を一時的に `exit 1` に変えた push）で、`verapdf` が `wait-pdfs: 'build (ubuntu-24.04, outputs)' completed without uploading conformance-pdfs` で失敗すること。確かめた後にその変更を外す。
- マージの後、3 の記録を書く。

## トレードオフ

- `verapdf` は `build` の全体より早く始まるので、Nix の導入と veraPDF の取得を待ちの時間に重ねられる。その代わり、`outputs` が `conformance-pdfs` を上げるまで待つあいだ、ランナーを一つ占める。`visual` と同じ形で、この 40 時間の `visual` の待ちは中央値 116 秒だった。
- `verapdf` の失敗の原因が、`outputs` のビルドの失敗のときは、`wait-pdfs.sh` の行で伝わる。今の `needs: build` では `verapdf` は省かれ、`ci` のゲートが `build` の失敗を伝える。失敗の見え方が `visual` と同じになる。
- 5 分を超える実行は 47% から 29% に減る見積もりだが、0 にはならない。残りは `cabal build` が 100 秒を超える実行で、変更が触るモジュールの数で決まる。
- `main` への push の時間は縮むが、`env` のランナーの環境の検査が中央値 275 秒なので、5 分の中には収まらない。方針の対象外である。

## メンテナーが決めること

1. **`verapdf` の待ち方**：推奨は、`conformance-pdfs` を `wait-pdfs.sh` で待つことである。118 回のうち 115 回で最後に終わるジョブを、臨界経路から外す。見積もりで中央値が 298 秒から 234 秒になる。
   - 退けた案の一つは、`verapdf` を `main` への push だけで走らせることである。PDF/A と PDF/UA の適合はプルリクエストで壊れうるので、マージの前に見つける今の形を保つ。
   - 二つめは、veraPDF を `outputs` のランナーの中で走らせることである。Nix の導入と veraPDF の取得の 25 秒と検査の 33 秒が `outputs` に足され、`outputs` が 60 秒ほど遅くなる。`outputs` は最後に終わる `build` のランナーであることが多いので、臨界経路が縮まない。
   - 三つめは、`conformance-pdfs` を `cabal build` の直後、visual-pdfs より前に作ることである。`verapdf` は 47 秒早く始まるが、`visual` が 7 秒遅くなり、どちらも `outputs` の終わりの前に終わるので、効果がない。
2. **テストスイートの配分**：推奨は、実装のプルリクエストで `scripts/ci/suite-timeout.sh` にスイートごとの秒をログに書く一行を足し、スイートごとの時間を一度集めてから、別の ADR で配分を決めることである。x86-64 の `tests-rest` と `tests-driver` の差は 28 秒で、そろえても縮むのは 14 秒ほどである。
   - 退けた案は、x86-64 にテストのランナーを三つめとして足すことである。テストは 57 秒ほどに縮むが、ランナーの用意（キャッシュの復元と `cabal build`）が約 45 秒かかり、復元の量が一回あたり約 0.6 GB 増える。
3. **変更のないパッケージのテストを省くこと**：推奨は、この ADR の効果を記録してから、別の ADR で扱うことである。残る 29% の多くは `cabal build` が長い実行で、そこではテストの時間は主な項ではない。
   - 退けた案は、この ADR で同時に決めることである。閉包の規則と `manual/` や `docs/` の扱いを決める必要があり、`verapdf` の変更と独立である。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0009](0009-ci-speed.md)、[ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md)、[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)、[ADR 0155](0155-split-aarch64-test-runner.md)、[ADR 0167](0167-leave-cache-restore-failures-as-misses.md)、[ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md)、[ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)、[ADR 0243](0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)
- [docs/ci-timings/2026-11-09-ci-critical-path-and-download-failures.md](../ci-timings/2026-11-09-ci-critical-path-and-download-failures.md)、[docs/ci-timings/2026-11-08-ci-caches-under-the-limit.md](../ci-timings/2026-11-08-ci-caches-under-the-limit.md)、[docs/ci-timings/2026-11-04-split-test-runners.md](../ci-timings/2026-11-04-split-test-runners.md)
- [`.github/workflows/ci.yml` の `verapdf`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L1069-L1090)、[同 `visual` の待ち](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L847-L851)、[同 `outputs` の conformance-pdfs](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L446-L454)、[`scripts/visual/wait-pdfs.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/visual/wait-pdfs.sh)
- [`CONTRIBUTING.md` の CI の時間の方針](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/CONTRIBUTING.md#L393-L397)
