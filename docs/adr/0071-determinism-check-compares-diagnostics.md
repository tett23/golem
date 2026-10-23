# ADR 0071: アーキテクチャ間の決定性の検査で、diagnostics と終了コードも比べる

ステータス: 採択（未実装）

## 文脈

[ADR 0002](0002-determinism.md) は、出力のバイト列に加えて「診断の出力順も、ファイルの順と位置の順に固定する」（40 行め）と定める。
同じ入力からは同じ diagnostics を得ることも、決定性に含まれる（docs/specifications.md:501）。

ところが、x86-64 と aarch64 を比べる `determinism` ジョブ（[build のジョブで一覧を作る手順](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml#L284-L291) と [二つの一覧を比べる手順](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml#L348-L357)）の入力を作る [scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) は、`build/` の下のファイルの SHA-256 だけを書く。
`golem build` の標準出力は `>/dev/null` で捨て（[HTML、EPUB、テキストのビルド](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh#L13) と [PDF のビルド](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh#L27)）、標準エラー出力と終了コードは記録しない。
アーキテクチャによって diagnostics の順序やメッセージが変わっても、この検査は通る。

diagnostics を比べる検査は、ほかに [scripts/env-determinism/check.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/check.sh)（[ADR 0029](0029-environment-variation-determinism-test.md)）がある。
これは `--format json` の標準エラー出力と終了コードも比べ、diagnostics を出す専用の入力（[scripts/env-determinism/diagnostics/](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/diagnostics)）を持つ。
しかし、比べるのは同じランナーの中の環境の違いであり、x86-64 だけで走る（[ci.yml の環境の検査の手順](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml#L296-L308)）。
アーキテクチャの違いで diagnostics が変わることは、どこでも検査していない。

## 実装すること

- [scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) で、各ビルドを `--format json` で走らせ、標準エラー出力の SHA-256 と終了コードを、出力のファイルと同じ一覧に書く。行の形は `<SHA-256>  <入力>/stderr` と `exit <コード>  <入力>` とする。
- 標準出力も同じく SHA-256 を書く。今の `golem build` は標準出力に何も書かないはずなので、空の SHA-256 が並ぶ。
- 入力に [scripts/env-determinism/diagnostics/](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/diagnostics) を加える。diagnostics を出すための入力である。終了コードが 0 でない場合も、`set -e` のもとで止まらずに終了コードを受け取れるように書く。
- [release.yml の `determinism` ジョブ](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/release.yml#L167-L179) も [scripts/release/smoke.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh) を通して同じ一覧を比べるので、三つの配布物の間でも diagnostics を比べることになる。release.yml は変えない。
- 二冊のマニュアルは、[scripts/manual/build.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/build.sh) が diagnostics を一つでも出せば失敗にするので、diagnostics の比較の対象にしない。
- README.md の CI の表の `determinism` の行（330 行め）、開発者のマニュアルの CI の章（manual-dev/part2/11-ci-jobs.gm:149-152）、docs/specifications.md:3080 の段落に、比べるものに diagnostics と終了コードが入ることを書く。

## 実装しないこと

- env-determinism の検査を aarch64 でも走らせること。env-determinism は x86-64 だけで走らせる。diagnostics のメッセージや終了コードがアーキテクチャによって変わることは考えにくく、そうなる変更を持ち込む ADR は採択されない。しかも env-determinism の所要時間は x86-64 の臨界経路を決めており（docs/ci-timings/2026-10-18-after.md）、aarch64 に足すと CI が延びる。アーキテクチャの違いは、この ADR の determinism.sh の比較で見る。まれな問題を見つけることより、CI を安く保って開発を続けられることを優先する。
- diagnostics の中身（標準エラー出力そのもの）を一覧に書くこと。SHA-256 だけを書き、違いが出たら CI の成果物から両方を取り寄せて比べる。

## テスト設計

- [scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh) に、determinism.sh の出力の形の項目を足す。偽の `golem`（`GOLEM` で差し替える。標準エラー出力に固定の JSON を書き、終了コード 1 で終わるシェルのスクリプト）で、一覧に `<入力>/stderr` の行と `exit 1  diagnostics` の行が出ることを確かめる。今の determinism.sh では、偽の `golem` が終了コード 1 を返すと `set -e` で止まるので、この項目は落ちる。
- 偽の `golem` の標準エラー出力を一字変えると、一覧が変わることを確かめる。
- 実装のプルリクエストで、CI の二つのランナーの一覧が一致することを確かめる。

## トレードオフ

- determinism.sh の入力が一つ増え、`build` ジョブの出力のランナーの時間が、その入力を組む数秒だけ延びる。
- diagnostics の SHA-256 は、メッセージの文言を変えるたびに変わるが、比べるのは同じコミットの二つのランナーの間なので、文言の変更で検査が落ちることはない。

## 参考文献

- [ADR 0002](0002-determinism.md)
- [ADR 0029](0029-environment-variation-determinism-test.md)
