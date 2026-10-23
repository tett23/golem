# ADR 0070: 変更のパスを取るときにリネームの検出を切り、移動元のパスも数える

ステータス: 採択（未実装）

## 文脈

CI は、変更が `docs/` の下とルートの Markdown だけならビルドを省く（[ADR 0009](0009-ci-speed.md)、[ADR 0021](0021-docs-workflow-and-ci-gate.md)）。
変更のパスは [scripts/ci/changed-paths.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/changed-paths.sh) が取り、判定は [scripts/ci/needs-build.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/needs-build.sh) が行う。

changed-paths.sh は [`git -c core.quotePath=false diff --name-only "$RANGE"`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/changed-paths.sh#L37) でパスを取る。
git の `diff.renames` は既定で有効なので、`--name-only` は移動したファイルの移動先だけを書く。
2026-10-23 に git 2.55.0 で、`modules/x/A.hs` を `docs/A.md` に `git mv` したコミットを作って確かめた。
`git diff --name-only` は `docs/A.md` の一行だけを書き、`--no-renames` を付けると `docs/A.md` と `modules/x/A.hs` の二行を書いた。
前者では needs-build.sh が false を返し、モジュールのファイルを消したプルリクエストのビルドとテストが省かれる。

これはテストの不足ではなく、CI の判定の誤りである。
changed-paths.sh のテスト（[scripts/ci/test.sh の `changed_paths`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L89-L125)）はあるが、移動の fixture がない。
点検の報告は changed-paths.sh を「テストなし」としたが、これは誤りである。

## 実装すること

- changed-paths.sh の `git diff` に `--no-renames` を付ける。移動は、移動元の削除と移動先の追加の二つのパスとして書かれる。
- 利用者の git の設定（`diff.renames`）に左右されないよう、設定ではなくオプションで切る。
- README.md の CI の表の後の段落（336 行め）と、開発者のマニュアルの CI の章（manual-dev/part2/11-ci-jobs.gm:61 付近）に、移動は移動元と移動先の両方を変更のパスとして数えることを一文で書く。

## 実装しないこと

- コピーの検出（`-C`）の扱い。既定で無効であり、`--name-only` に影響しない。
- needs-build.sh の判定の規則を変えること。

## テスト設計

[scripts/ci/test.sh の changed-paths.sh の fixture のリポジトリ](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L93-L106) に、`a.hs` を `docs/moved.md` に `git mv` するコミットを足す。
先に足し、今のスクリプトで落ちることを確かめる。

- `changed-paths.sh push <前> <後>` の出力が `a.hs` と `docs/moved.md` の二行である。
- 同じ範囲で `needs-build.sh` が true を書く。
- fixture のリポジトリに `git config diff.renames true` を明示し、利用者の設定によらず再現するようにする。

## トレードオフ

- 移動だけのプルリクエストで、移動元が `modules/` の下ならビルドが走る。移動元のファイルが消えたことはビルドの結果を変えうるので、走るのが正しい。

## 参考文献

- [ADR 0009](0009-ci-speed.md)
- [ADR 0021](0021-docs-workflow-and-ci-gate.md)
- git-diff(1)、`--no-renames` と `diff.renames`
