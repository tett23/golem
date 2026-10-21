# ADR 0048: adr-guard を v0.8.3 に上げ、ステータスの候補に採択（未実装）を加える

ステータス: 採択

## 文脈

このリポジトリは、コミット済みの ADR と記録の変更を [adr-guard](https://github.com/tett23/adr-guard) で拒否している。
検査は `.githooks/pre-commit` と、CI の `docs.yml` の `adr` ジョブで行う。
[ADR 0032](0032-update-adr-guard-to-v0.8.2.md) で、`adr` ジョブの action を `tett23/adr-guard@v0.8.2`（`allow-status: true`、`allow-links: true`）にした。

その後、tett23/adr-guard は [v0.8.3](https://github.com/tett23/adr-guard/releases/tag/v0.8.3) を出した。

- 新しいステータス `採択（未実装）` を解釈する。
  採択されたが、まだ実装されていない ADR を表す。
  括弧は全角でも半角でもよく、英語では `Accepted (not implemented)` と書く。
- 新しいサブコマンド `adr-guard unimplemented [--status]` が、ステータスが `採択（未実装）` の ADR を一覧する。
- 根拠は tett23/adr-guard の ADR「[採択（未実装）のステータス](https://github.com/tett23/adr-guard/blob/main/docs/adr/0016-accepted-not-implemented-status.md)」。

手元の adr-guard はすでに v0.8.3 に更新されている。
メンテナーの全体の規則でも、ADR のステータスの候補に `採択（未実装）` が加わった。
一方、`CONTRIBUTING.md`、`CONTRIBUTING.en.md`、開発者のマニュアルは、ステータスの値を提案、採択、却下、破棄の四つと書いている。
採択した ADR のうち、実装を終えたものと終えていないものは、ステータスの行では区別できない。

## 実装すること

- `.github/workflows/docs.yml` の `adr` ジョブの action を `uses: tett23/adr-guard@v0.8.3` にする。
  入力 `allow-status: true`、`allow-links: true`、`base`、`head` はそのまま保つ。
  コメントの ADR の参照にこの ADR を加える。
- `.githooks/pre-commit` は `exec adr-guard pre-commit --allow-status --allow-links` のまま保ち、コメントの ADR の参照にこの ADR を加える。
- `README.md` の「Git フックの有効化」の節で、必要な adr-guard を v0.8.3 以降にし、`cargo install` の `--tag` を `v0.8.3` にする。
  CI の `adr` ジョブの action の版も v0.8.3 にする。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の開発環境の節の版を v0.8.3 にする。
  ADR の書き方の節で、ステータスの値に `採択（未実装）` を加え、採択したがまだ実装していない ADR に使うこと、実装を終えたら `採択` に変えること、`adr-guard unimplemented` で一覧できることを書く。
- `manual-dev/` の adr-guard の版（第二部の「ビルドとテスト」「ADR」「CI のジョブ」の章）を v0.8.3 にする。
  第二部の「ADR」の章のステータスの値と adr-guard の命令の一覧を、`CONTRIBUTING.md` と同じ内容に合わせる。
- [ADR 0032](0032-update-adr-guard-to-v0.8.2.md) のステータスを、action の版についてこの ADR に置き換えられたことを示す `採択→…は [ADR 0048](...)` の形にする。
- `adr-guard links --fix --include-committed` を実行し、`adr-guard links` と `adr-guard check-status` が終了コード 0 で終わる状態を保つ。

## 実装しないこと

- 既存の ADR のステータスの一括の書き換え。
  採択した ADR のうち実装を終えていないものを `採択（未実装）` に変えるかは、必要になったときに個別に決める。
- `採択（未実装）` の ADR を CI で拒否したり、警告したりする検査。
- `.githooks/pre-commit` のコマンドと action の入力の変更。
- 記録の保護の変更。
- Claude Code の hook の変更。Claude Code の hook は全体の設定（`~/.claude/settings.json`）にあり、このリポジトリでは管理しない。
- 手元の adr-guard の更新の自動化。
- action の指定方法の変更。これまでどおりバージョンのタグで指定する。

## テスト設計

- 手元の adr-guard（v0.8.3）で、次を確かめる。
  - 変更をステージして `.githooks/pre-commit` が終了コード 0 で終わる（各コミットで hook が通る）。
  - `adr-guard links` と `adr-guard check-status` が終了コード 0 で終わる。
  - `adr-guard unimplemented` が終了コード 0 で終わる。
  - コミットの後、`adr-guard check-range origin/main HEAD --allow-status --allow-links` が終了コード 0 で終わる。
- `.github/workflows/docs.yml` が YAML として読めることを確かめる。
- マニュアルの検査（`scripts/manual/test.sh`、`scripts/manual/check-updated.sh origin/main HEAD`、`scripts/ci/docs-refs.sh`）が通ることを確かめる。
- 変更のプルリクエストの CI で、`adr` ジョブが v0.8.3 の action で実行され、成功することを確かめる。

## トレードオフ

- ステータスの候補が一つ増え、ADR を書く人が `採択` と `採択（未実装）` を選び分ける手間が増える。
  その代わり、実装を終えていない ADR を `adr-guard unimplemented` で一覧でき、実装の漏れを探しやすくなる。
- `採択（未実装）` から `採択` への変更はステータスの行の変更なので、`--allow-status` で許される。
  実装のプルリクエストで変え忘れると、実装を終えた ADR が未実装の一覧に残る。レビューで確かめる。
- 手元の adr-guard が v0.8.3 より古いと、`adr-guard unimplemented` が使えない。README と CONTRIBUTING に必要なバージョンを書いて補う。

## 参考文献

- tett23/adr-guard の ADR「[採択（未実装）のステータス](https://github.com/tett23/adr-guard/blob/main/docs/adr/0016-accepted-not-implemented-status.md)」
- tett23/adr-guard の [v0.8.3 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.8.3)
