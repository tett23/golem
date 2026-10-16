# ADR 0012: adr-guard を v0.8.1 に上げ、ADR と記録のディレクトリ名の別名も保護する

ステータス: 採択→CI の action の版は [ADR 0032](0032-update-adr-guard-to-v0.8.2.md)

## 文脈

このリポジトリは、コミット済みの ADR と記録の変更を [adr-guard](https://github.com/tett23/adr-guard) で拒否している。
検査は `.githooks/pre-commit` と、CI の `adr` ジョブで行う。
[ADR 0011](0011-update-adr-guard-to-v0.8.0.md) で、`adr` ジョブのactionを `tett23/adr-guard@v0.8.0`（`allow-status: true`、`allow-links: true`）にし、`docs/audit/` と `docs/benchmarks/` の記録も保護されるようにした。

その後、tett23/adr-guard は [v0.8.1](https://github.com/tett23/adr-guard/releases/tag/v0.8.1) を出した。

- ADR のディレクトリとして、`adr` のほか `adrs`、`decisions`、`decision` も保護する。
- 記録のディレクトリとして、`docs/audit/` と `docs/benchmarks/` のほか `docs/audits/` と `docs/benchmark/` も保護する。
- 根拠は tett23/adr-guard の [ADR 0014](https://github.com/tett23/adr-guard/blob/main/docs/adr/0014-directory-name-variants.md)。

手元の adr-guard はすでに v0.8.1 に更新されている。
このリポジトリには、追跡ファイルにも未追跡のディレクトリにも、新しく保護される名前（`adrs`、`decisions`、`decision`、`audits`、`benchmark`）のディレクトリはない。
そのため、名前の変更やステータスの行とリンクの移行は要らない。
計測の記録を置く `docs/ci-timings/`（[ADR 0009](0009-ci-speed.md)）は、v0.8.1 でも名前が違うため保護されない。

## 実装すること

- `.github/workflows/ci.yml` の `adr` ジョブのactionを `uses: tett23/adr-guard@v0.8.1` にする。
  入力 `allow-status: true`、`allow-links: true`、`base`、`head` はそのまま保つ。
  コメントの記録のディレクトリに `docs/audits/` と `docs/benchmark/` を加え、ADR の参照にこの ADR を加える。
- `.githooks/pre-commit` は `exec adr-guard pre-commit --allow-status --allow-links` のまま保ち、コメントの ADR の参照にこの ADR を加える。
- `README.md` の「Git フックの有効化」の節で、必要な adr-guard を v0.8.1 以降にし、保護される記録のディレクトリに `docs/audits/` と `docs/benchmark/` を加える。
  CI の節の表の `adr` ジョブの内容にも同じディレクトリを加える。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の開発環境の節と、記録の置き場所の段落を同じ内容に合わせる。
- `CLAUDE.md` と `docs/glossary.md` の記録のディレクトリに触れる記述を同じ内容に合わせる。
- `docs/specifications.md` の記録の定めに `docs/audits/` と `docs/benchmark/` を加える。
- [ADR 0011](0011-update-adr-guard-to-v0.8.0.md) のステータスを、actionの版と記録のディレクトリについてこの ADR に置き換えられたことを示す `採択→…は [ADR 0012](...)` の形にする。
- `adr-guard links --fix` を実行し、`adr-guard links` と `adr-guard check-status` が終了コード0で終わる状態を保つ。

## 実装しないこと

- `docs/ci-timings/` の記録の移動や名前の変更。理由は [ADR 0011](0011-update-adr-guard-to-v0.8.0.md) と同じである。
- ADR のディレクトリの名前の変更。ADR はこれまでどおり `docs/adr/` と `docs/<モジュール>/adr/` に置き、別名の `adrs`、`decisions`、`decision` は使わない。文書では別名に触れない。
- Claude Code の hook の変更。Claude Code の hook は全体の設定（`~/.claude/settings.json`）にあり、このリポジトリでは管理しない。
- 手元の adr-guard の更新の自動化。
- actionの指定方法の変更。これまでどおりバージョンのタグで指定する。

## テスト設計

- 手元の adr-guard（v0.8.1）で、次を確かめる（コミットはしない）。
  - 変更をステージして `.githooks/pre-commit` が終了コード0で終わる。
  - `adr-guard links` と `adr-guard check-status` が終了コード0で終わる。
- 新しく保護される名前のディレクトリが無いことを、`git ls-files` と作業ツリーの検索で確かめる。
- `.github/workflows/ci.yml` が YAML として読めることを確かめる。
- 変更のプルリクエストの CI で、`adr` ジョブが v0.8.1 のactionで実行され、成功することを確かめる。
  - ジョブのログで、`adr-guard-v0.8.1-x86_64-unknown-linux-gnu.tar.gz` のチェックサムが検証され、`check-range --allow-status --allow-links`、`links`、`check-status` が実行されていることを確かめる。

## トレードオフ

- 手元の adr-guard が v0.8.1 より古いと、pre-commit hook は `docs/audits/` と `docs/benchmark/` の記録を保護せず、CI で初めて違反が分かる。README と CONTRIBUTING に必要なバージョンを書いて補う。
- 保護される名前が増えたため、`docs/audits/` や `docs/benchmark/` を記録以外の用途で使うと、コミット後に変更できなくなる。これらの名前は記録のためだけに使う。
- 記録の保護は adr-guard の決めた名前に固定されたままである。`docs/ci-timings/` のように別の名前の記録は、これまでどおり約束とレビューで守る。
