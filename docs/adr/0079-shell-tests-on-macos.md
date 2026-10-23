# ADR 0079: スクリプトのテストを macOS の BSD の道具でも走らせる

ステータス: 採択（未実装）

## 文脈

保守者の方針では、リポジトリのスクリプトは、動かす環境にある道具で動くように書く。
この方針はリポジトリの文書には書かれていない（manual-dev/part2/08-build-test.gm:132 は POSIX の sh とだけ書く）。
macOS で動くスクリプトは、BSD 版の awk、sed、find、grep でも動かなければならない。

ところが、scripts の下のテスト（[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh)、[scripts/manual/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/test.sh)、[scripts/env-determinism/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/test.sh)）は、CI の [`changes` ジョブ](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml#L35-L84) の ubuntu-24.04 だけで走る。
[scripts/release/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/test.sh) も [`release-scripts` ジョブ](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml#L359-L381) の ubuntu で走る。
手元の Mac の開発環境は、nix と mise で GNU 版の awk と sed を `PATH` の先に置いている。
2026-10-23 のテストの品質の点検は、BSD 版でスクリプトのテストを走らせている場所がどこにもないことを指摘した。
[ci.yml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml)、[release.yml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/release.yml)、[docs.yml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/docs.yml) を読んで、これを確かめた。

macOS で動くスクリプトには、[scripts/release/build-macos.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/build-macos.sh)、[package.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/package.sh)、[smoke.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh)（release.yml の macOS のランナー）と、開発者が手元で動かす [scripts/manual/build.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/build.sh)、[scripts/ci/](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci) の検査がある。
BSD 版で動かないことは、リリースのときか、GNU 版を入れていない開発者の手元で初めて分かる。

## 実装すること

- ci.yml に `scripts-macos` ジョブを足す。macos-15 のランナーで、`PATH` に GNU 版を足さずに、四本のテスト（[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh)、[scripts/manual/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/test.sh)、[scripts/env-determinism/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/test.sh)、[scripts/release/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/test.sh)）を走らせる。
- テストが使う道具のうち macOS にないもの（`timeout`、`sha256sum` など）は、スクリプトがすでに代わりの道具（`shasum -a 256`）に切り替えるか、テストが飛ばす。飛ばしたものは [ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md) の形で数を書く。`jq` は macos-15 のランナーにもとから入っているので、そのまま使う。
- `scripts-macos` を、[`ci` ジョブの `needs`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml#L406-L407) と [scripts/ci/gate.sh の `NAMES`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/gate.sh#L14) に足す。docs だけの変更では、`changes` の判定で飛ばす（`build` と同じ）。
- CONTRIBUTING.md に、scripts の下のスクリプトは macOS の BSD 版の道具でも動くように書き、このジョブで確かめることを書く。
- README.md の CI の表と、開発者のマニュアルの CI の章（manual-dev/part2/11-ci-jobs.gm）に、このジョブを書く。

## 実装しないこと

- Haskell のビルドとテストを macOS で走らせること。リリースの macOS のビルドが行う。
- 手元の開発環境から GNU 版を外すこと。

## テスト設計

- 自動テストにできるのは、ジョブの設定の確かめ方である。[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh) に、ci.yml の `scripts-macos` ジョブが macOS のランナーで四本のテストを走らせ、`ci` の `needs` にあることを確かめる項目を足す（今の `step_if` と同じ形）。今はジョブがないので落ちる。
- 実装のプルリクエストで、このジョブを走らせ、落ちたテストを一つずつ直す。直したものは、BSD 版との違い（`sed -i` の引数、`awk` の正規表現など）をプルリクエストの説明に書く。

## トレードオフ

- macOS のランナーは、Actions の実行時間の計算で Linux より高い。四本のテストは数分で終わるので、追加の時間は小さい。
- 最初の実装で、今の BSD 版で動かない箇所が見つかる可能性がある。見つかれば、スクリプトを BSD 版でも動くように直す。

## 参考文献

- [ADR 0001](0001-haskell-workspace-and-ci.md)
- [ADR 0021](0021-docs-workflow-and-ci-gate.md)
- [ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md)
- actions/runner-images、macOS 15 の README
