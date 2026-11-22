# ADR 0418: 手元の wasmtime が固定の版と違うとき、push を止める

Status: proposed

## 文脈

wasmtime の版は、`scripts/fetch-wasmtime.sh` が版と SHA-256 で固定する。
手元の `third_party/wasmtime` は、開発者がこのスクリプトを走らせたときにだけ固定の版に入れ替わる。
スクリプトを自動で呼ぶものはない。

2026-11-18 に、手元の wasmtime が 49.0.2 のまま、固定の版が 50.0.1 になっていたことが分かった。
手元のテストは、CI と違う版の wasmtime で走っていた。
tett23 は、このずれを自動で防ぐことを求め、2026-11-23 にこの ADR を書くことを決めた。

## 調査した事項

`origin/main`（`2ac7fb273`）で確かめた。

- `.githooks/pre-push` は、マニュアルの検査（`scripts/manual/check-updated.sh`）を呼ぶだけで、wasmtime に触れない。
  フックは `git config core.hooksPath .githooks` で入れる（README と CONTRIBUTING）。
- `scripts/fetch-wasmtime.sh --expected` は、`<配布物の名前> <SHA-256>` の一行を出す。
  対応しないプラットフォームでは、終了コード 1 で終わる。
- スクリプトは、取得した後に同じ形の一行を `third_party/wasmtime/VERSION` に書く。
  同じ一行のときは取り直さない（[ADR 0044](0044-release-workflow-hardening.md)）。
- `/third_party/` は `.gitignore` で無視している。
- `.claude/worktrees/` の下の worktree は、どれも `third_party/wasmtime/VERSION` を持たない。
  それらの `cabal.project.local` の `extra-lib-dirs` は、メインのチェックアウトの `third_party/wasmtime/lib` を指す。
  worktree のビルドは、メインのチェックアウトの wasmtime にリンクする。
- `git rev-parse --git-common-dir` は、どの worktree でもメインのチェックアウトの `.git` を返す。

## 実装すること

- `.githooks/pre-push` に、wasmtime の版の照合を足す。
  照合は、`scripts/check-local-wasmtime.sh` に置き、フックから呼ぶ。
- 照合は、push するチェックアウト（worktree を含む）の `scripts/fetch-wasmtime.sh --expected` の一行と、そのチェックアウトのビルドがリンクする wasmtime の `VERSION` の一行を比べる。
- ビルドがリンクする wasmtime は、そのチェックアウトの `cabal.project.local` の `extra-lib-dirs` のうち `third_party/wasmtime/lib` で終わるものの親のディレクトリとする。
  そのような行がなければ、そのチェックアウト自身の `third_party/wasmtime` とする。
  メインのチェックアウトから `cabal.project.local` を写した worktree では、メインのチェックアウトの wasmtime を比べることになる。
- wasmtime の版を上げるブランチを worktree から push するときは、その worktree で `scripts/fetch-wasmtime.sh` を走らせ、`cabal.project.local` をその worktree の `third_party/wasmtime` に向ける。
  照合が止めたときの標準エラーにも、この手順を書く。
- 照合は、一回の push に一度行う。
  push する ref がどれもブランチの削除のときは、照合しない。
- 次のときは、push を止め、比べた `VERSION` のディレクトリに wasmtime を取り直すよう、標準エラーに書く。
  - 二つの一行が違う。
  - `VERSION` がない（wasmtime を取得していない）。
- `--expected` が失敗したとき（対応しないプラットフォーム）は、push を止め、そのことを標準エラーに書く。
- 照合はネットワークに出ない。
  取得はしない。
- 照合を飛ばす仕組みは設けない。
  ずれたまま push したいときは、wasmtime を取り直す。
- README と CONTRIBUTING のフックの説明に、この照合を書く。

## 実装しないこと

- フックから wasmtime を取得しない。
  フックがネットワークに出ると、サンドボックスの中で失敗し、push のたびに時間がかかるためである。
- `post-checkout` や `post-merge` のフックは足さない。
- CI の照合（`scripts/check-wasmtime-linked.sh`、[ADR 0156](0156-wasmtime-49-0-5.md)）は変えない。
- wasmtime の版そのものを上げる手順は変えない。

## 不変条件

- I1：照合は、`--expected` の一行と `VERSION` の一行が等しいときだけ、終了コード 0 で終わる。
- I2：照合は、push するチェックアウトの `cabal.project.local` が指す wasmtime の `VERSION` を読み、指していなければそのチェックアウトの `VERSION` を読む。
- I3：照合は、ネットワークに出ず、ファイルを書かない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 一行が等しい | 0 で終わる | I1 |
| 版が違う（49.0.2 と 50.0.1） | 止める | I1 |
| SHA-256 だけが違う | 止める | I1 |
| `VERSION` がない | 止める | I1 |
| `--expected` が失敗 | 止める | I1 |
| worktree の `cabal.project.local` がメインを指し、メインに正しい `VERSION` | 0 で終わる | I2 |
| worktree に古い `VERSION`、`cabal.project.local` がメインを指し、メインに正しい `VERSION` | 0 で終わる | I2 |
| `cabal.project.local` がない worktree に正しい `VERSION` | 0 で終わる | I2 |
| ブランチの削除だけの push | 照合しない | I1 |

## 受けいれ条件

なし。
この ADR の振る舞いは、不変条件のテストで確かめる。

## テスト設計

- `scripts/test.sh` に、`scripts/check-local-wasmtime.sh` のテストを置く。
  名前は `root ADR 0418 I<番号>: ...` とする。
- テストは、一時のディレクトリに Git のリポジトリと worktree を作り、`VERSION` と `--expected` の代わりのスクリプトを置いて、境界の表の行ごとに終了コードを確かめる。
- I3 は、テストの前後で一時のディレクトリのファイルの一覧が変わらないことで確かめる。
- テストは、実装の前に失敗することを確かめてから実装する。

## トレードオフ

wasmtime を取得していないクローン（文書だけを直す人など）は、push の前に取得が要る。
フックは `core.hooksPath` を設定したクローンにしか入らないので、設定していない人には影響しない。
手元のテストと CI の wasmtime がずれる害のほうが大きいと判断する。

`--expected` が失敗するプラットフォーム（wasmtime の配布物のない環境）では、どの push も止まる。
そのような環境では golem-plugin を組めず、CI と同じテストを手元で走らせられないので、その環境から push することを想定しない。

## 参考文献

- [ADR 0044](0044-release-workflow-hardening.md)
- [ADR 0156](0156-wasmtime-49-0-5.md)
