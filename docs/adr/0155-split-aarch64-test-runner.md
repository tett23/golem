# ADR 0155: aarch64 の build のテストを、x86-64 と同じく二つのランナーに分ける

ステータス: 採択

## 文脈

[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md) は、x86-64 のテストを `tests-driver`（golem-driver のスイート）と `tests-rest`（そのほか）の二つのランナーに分けた。
aarch64 の `tests` は、一つのランナーで 26 のスイートのすべてを実行している（[ci.yml](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/.github/workflows/ci.yml#L149-L162)）。
その後、[ADR 0146](0146-threaded-golem-driver-test.md) が golem-driver-test を threaded にし、[ADR 0147](0147-touch-setup-config-after-restoring-dist.md) がスイートの設定し直しをなくした。

### 計測

2026-11-04 から 11-05 の `ci.yml` の 33 回の実行（41832262416 から 41884131738 まで、プルリクエストと `main` への push）を `gh run view <id> --json jobs` で取った。

aarch64 の `tests` の `cabal test` の手順は 80 秒から 103 秒で、最近の 6 回は 92 秒から 103 秒だった。
その終わりを決めるのは golem-driver-test（約 70 秒）と、遅れて始まる golem-pdf-test、golem-parser-test（約 50 秒ずつ）で、4 コアを取り合っている（[docs/ci-timings/2026-11-04-threaded-golem-driver-test.md](../ci-timings/2026-11-04-threaded-golem-driver-test.md)）。
x86-64 では、同じ golem-driver-test がほかのスイートと分かれて 33〜50 秒で終わる。

33 回のうち 15 回で、aarch64 の `tests` が `build` と `visual` の中で最後に終わった。
その 15 回で、二番めに終わったジョブとの差は 2 秒から 48 秒、平均 24 秒だった。
残りの 18 回は、x86-64 の `tests-rest`、`outputs`、`env`、`visual` のどれかが最後だった。

### 同時に動くジョブの数

同じ 33 回で、`changes` の終わりから `build` の各ランナーが始まるまでの待ちは最大 13 秒で、`ci` ジョブの待ちは最大 3 秒だった。
GitHub の無料のプランの同時実行の枠（20）による待ちは、この期間には見えなかった。
今の一回の実行は、同時に最大 12 のジョブを使う。

## 実装すること

テストを先に書き、今の実装で失敗することを確かめる。

- `build` の行列の `ubuntu-24.04-arm` の `tests` を、`tests-driver`（`suites: driver`、`save: true`）と `tests-rest`（`suites: rest`、`save: false`）の二つにする。どちらも `tests: true`、`outputs: false`、`env: false` とする。`outputs` は変えない。
- `scripts/ci/test-suites.sh` は変えない。x86-64 と同じ二つの部分を使う。
- 生成したパーサーの検査は、今の条件（`matrix.tests && matrix.suites != 'driver'`）のままで、aarch64 では `tests-rest` で走る。
- `dist-newstyle` を保存するのは、aarch64 では `tests-driver` とする。
- README の CI の表と、開発者のマニュアルの CI の章を直す。
- 計測の結果を `docs/ci-timings/` に記録する。

## 実装しないこと

- **aarch64 の `outputs` のランナーに、テストの一部を載せること。** `outputs` は 96〜135 秒で終わり、余りは 30〜80 秒ある。しかし golem-driver のスイート（約 70 秒）も、golem-pdf-test と golem-parser-test（約 50 秒が遅れて始まる）も、載せると `outputs` が今の `tests` と同じくらい遅くなりうる。決定性の検査の出力とテストは同時に走らせられない（[ADR 0037](0037-ci-build-job-speedup.md)）ので、続けて走らせることになる。
- **aarch64 のテストを省くこと。** 決定性と、ネイティブライブラリの結果が両方のアーキテクチャで一致することを確かめられなくなる（[ADR 0001](0001-haskell-workspace-and-ci.md)、[ADR 0009](0009-ci-speed.md)）。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

- `build` の行列が、`ubuntu-24.04` の `tests-driver`、`tests-rest`、`outputs`、`env` と、`ubuntu-24.04-arm` の `tests-driver`、`tests-rest`、`outputs` を持ち、各行の `tests`、`outputs`、`env`、`suites`、`save` が上のとおりであること（今の項目を改める）。
- `save` が `true` の行が、アーキテクチャごとにちょうど一つであること。

### 自動テストにできないものの確かめ方

- 実装のプルリクエストの実行で、aarch64 の二つのランナーのログの `Test suite …: PASS` の和が、x86-64 の二つのランナーの和と同じ 26（そのときのスイートの数）であること。
- 実装のプルリクエストの 3 回の実行と、その後の `main` への push の実行で、aarch64 の二つの `cabal test` の手順の時間と、`build` の最後のランナーの終わりを記録する。

## トレードオフ

- 見込める短縮は小さい。aarch64 の `tests` の手順は、golem-driver のスイートと残りに分けると、それぞれ 50〜70 秒前後になると見込む（x86-64 の `tests-driver` と `tests-rest` の今の時間から推した値で、確かめていない）。上の 33 回に当てはめると、短くなるのは aarch64 が最後だった 15 回だけで、その差（平均 24 秒、最大 48 秒）か約 30 秒の小さいほうが縮む。33 回の平均では、一回あたり 9 秒前後である。
- 一方で、テストのスイートは増え続けており、aarch64 の `tests` の手順は、最近の 6 回で 92〜103 秒と長くなっている。分けなければ、aarch64 が最後になる回が増えると見込む。
- ランナーが一つ増え、一回の実行で同時に動くジョブは最大 13 になる。二つの実行が重なれば 26 で、枠の 20 を超えて待ちが出うる。上の 33 回では待ちは見えなかった。
- aarch64 のランナーが一つ増えるので、キャッシュの取り寄せが一回の実行で約 0.8 GB（GHC 約 150 MB、索引約 109 MB、store 約 135 MB、`dist-newstyle` 約 400 MB）増える。

## 決めたことの記録

- **採択**：メンテナーが、arm のランナーを一つ増やして今すぐ分けることと、arm の `outputs` にテストを載せる代案を退けることを決めた（2026-11-05）。

## 参考文献

- [ci.yml（今の build の行列）](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/.github/workflows/ci.yml#L149-L162)
- [docs/ci-timings/2026-11-04-threaded-golem-driver-test.md](../ci-timings/2026-11-04-threaded-golem-driver-test.md)
- GitHub Docs, "Usage limits, billing, and administration"（同時に動くジョブの数の上限）. https://docs.github.com/en/actions/administering-github-actions/usage-limits-billing-and-administration
- [ADR 0001](0001-haskell-workspace-and-ci.md)、[ADR 0009](0009-ci-speed.md)、[ADR 0037](0037-ci-build-job-speedup.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)、[ADR 0146](0146-threaded-golem-driver-test.md)、[ADR 0147](0147-touch-setup-config-after-restoring-dist.md)
- 計測のデータ：上の 33 回の実行（2026-11-04〜05）
