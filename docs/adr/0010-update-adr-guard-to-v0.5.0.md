# ADR 0010: adr-guard を v0.5.0 に上げ、ステータスの行の変更を `--allow-status` で許可する

ステータス: 採択

## 文脈

このリポジトリは、コミット済みの ADR（`docs/adr/` と `docs/<モジュール>/adr/` の配下）の変更を [adr-guard](https://github.com/tett23/adr-guard) で拒否している。
検査は `.githooks/pre-commit` と、CI の `adr` ジョブ（[ADR 0001](0001-haskell-workspace-and-ci.md)、[ADR 0009](0009-ci-speed.md)）で行う。
現在は、pre-commit hook が `adr-guard pre-commit --allow-links` を実行し、`adr` ジョブが `tett23/adr-guard@v0.4.0` のactionを `allow-links: true` で使っている。
v0.4.0 への更新と `--allow-links` の導入は ADR を書かずに行った（コミット 6473174）。

その後、tett23/adr-guard は v0.5.0 に更新された（tett23/adr-guard の [ADR 0010](https://github.com/tett23/adr-guard/blob/main/docs/adr/0010-allow-status-option.md)）。
v0.5.0 では、コミット済みの ADR のステータスの行の変更も、`--allow-status` を付けたときだけ許可する。
付けないと、ADR を採択したときに古い ADR のステータスを `採択→...` に変えることもできない。

手元の adr-guard はすでに v0.5.0 に更新されている。
このリポジトリの pre-commit hook は `--allow-links` だけを付けているため、いまはステータスの行を変えるコミットが pre-commit hook で止まる。
README と CONTRIBUTING は「ステータスの行だけは変更できる」と書いており、v0.5.0 の手元の動作と食い違っている。

## 実装すること

- `.githooks/pre-commit` を `exec adr-guard pre-commit --allow-status --allow-links` にする。
- `.github/workflows/ci.yml` の `adr` ジョブのactionを `uses: tett23/adr-guard@v0.5.0` にし、入力 `allow-status: true` を加える（`allow-links: true` はそのまま）。
  checkout は `actions/checkout@v7` のまま、`fetch-depth: 0` と `persist-credentials: false` を保つ。
  v0.5.0 のactionは既定で `adr-guard links` も実行する。v0.4.0 と同じく、ADR の参照にリンクが無ければ失敗する。
- `README.md` の「Git フックの有効化」の節に、ステータスの行の変更とリンクだけの変更が pre-commit hook と CI の `--allow-status` と `--allow-links` で許可されること、v0.5.0 以降の adr-guard が要ることを書く。
  CI の節の表の `adr` ジョブの内容に、ADR の参照のリンクの検査を加える。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の ADR の節と開発環境の節を同じ内容に合わせる。
- `adr-guard links --fix --include-committed` を実行し、`adr-guard links` が終了コード0で終わる状態を保つ。

## 実装しないこと

- actionの指定方法の変更。これまでどおりバージョンのタグで指定する。
- Claude Code の hook の変更。Claude Code の hook は全体の設定（`~/.claude/settings.json`）にあり、このリポジトリでは管理しない。全体の設定は `adr-guard claude-hook --allow-status` に更新済み（反映は各自の環境で行う）。
- 手元の adr-guard の更新の自動化。
- `docs/specifications.md` の変更。仕様書は「ADR はコミット後、ステータスの行を除いて変更しない」とだけ定めており、adr-guard のバージョンやオプションを書いていない。この定めは v0.5.0 でも変わらない。
- v0.4.0 への更新に ADR が無かったことの補い。このADRが、adr-guard のバージョンとオプションの現在の決定を記録する。

## テスト設計

- 手元の adr-guard（v0.5.0）で、次を確かめる（コミットはしない）。
  - 変更をステージして `adr-guard pre-commit --allow-status --allow-links` が成功する。
  - `adr-guard links` が終了コード0で終わる。
  - コミット済みの ADR のステータスの行だけを変えると、pre-commit hook が許可する。
  - コミット済みの ADR の本文を変えると、pre-commit hook が拒否する。
- `.github/workflows/ci.yml` が YAML として読めることを確かめる。
- 変更のプルリクエストの CI で、`adr` ジョブが v0.5.0 のactionで実行され、成功することを確かめる。
  - ジョブのログで、`adr-guard-v0.5.0-x86_64-unknown-linux-gnu.tar.gz` のチェックサムが検証され、`check-range --allow-status --allow-links` と `links` が実行されていることを確かめる。

## トレードオフ

- pre-commit hook に `--allow-status` を付けるため、手元の adr-guard が v0.5.0 より古いと、引数の誤り（終了コード64）でコミットが止まる。README と CONTRIBUTING に必要なバージョンを書いて補う。
- ステータスの行の変更を許可するかどうかが、hook とactionの設定から読み取れるようになる。その分、設定に付けるオプションが増える。
