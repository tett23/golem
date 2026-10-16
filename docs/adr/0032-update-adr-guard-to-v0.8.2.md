# ADR 0032: adr-guard を v0.8.2 に上げ、コミット済みの ADR のリンクだけの変更を許す

ステータス: 採択

## 文脈

このリポジトリは、コミット済みの ADR と記録の変更を [adr-guard](https://github.com/tett23/adr-guard) で拒否している。
検査は `.githooks/pre-commit` と、CI の `docs.yml` の `adr` ジョブで行う。
[ADR 0012](0012-update-adr-guard-to-v0.8.1.md) で、`adr` ジョブのactionを `tett23/adr-guard@v0.8.1`（`allow-status: true`、`allow-links: true`）にした。

その後、tett23/adr-guard は [v0.8.2](https://github.com/tett23/adr-guard/releases/tag/v0.8.2) を出した。

- `--allow-links` が、ADR の参照のリンクに限らず、コミット済みの ADR の「リンクだけの変更」全般を許すようになった。
  インラインリンクと参照形式のリンクを付ける、外す、リンク先を変える変更、画像のリンク先の変更、リンクの参照定義の行（`[1]: URL`）の変更が通る。
- リンクのテキストの変更、画像の追加と削除、自動リンク（`<URL>`）と本文の URL の変更は、これまでどおり拒否する。
- 記録（`docs/audit/`、`docs/audits/`、`docs/benchmarks/`、`docs/benchmark/`）は、これまでどおり `--allow-links` が効かず、完全に保護される。
- 根拠は tett23/adr-guard の [ADR 0015](https://github.com/tett23/adr-guard/blob/main/docs/adr/0015-allow-link-changes.md)。

手元の adr-guard はすでに v0.8.2 に更新されている。
`.githooks/pre-commit` と action の入力はすでに `--allow-links`（`allow-links: true`）を使っているため、版を上げるだけで新しい意味になる。
文書には `--allow-links` を「ADR の参照のリンクだけを変える変更を許す」と書いているので、意味の広がりに合わせて直す。

## 実装すること

- `.github/workflows/docs.yml` の `adr` ジョブのactionを `uses: tett23/adr-guard@v0.8.2` にする。
  入力 `allow-status: true`、`allow-links: true`、`base`、`head` はそのまま保つ。
  コメントの許す変更を「リンクだけの変更」とし、ADR の参照にこの ADR を加える。
- `.githooks/pre-commit` は `exec adr-guard pre-commit --allow-status --allow-links` のまま保ち、コメントの許す変更を同じく直し、ADR の参照にこの ADR を加える。
- `README.md` の「Git フックの有効化」の節で、必要な adr-guard を v0.8.2 以降にし、`cargo install` の `--tag` を `v0.8.2` にする。
  `--allow-links` の説明を、コミット済みの ADR のリンクだけの変更を許すものに直す。
  CI の `adr` ジョブの action の版も v0.8.2 にする。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の開発環境の節と、ADR を変更してはいけない節を同じ内容に合わせる。
- `manual-dev/` の adr-guard の版と `--allow-links` の説明（第二部の「ビルドとテスト」「ADR」「CI のジョブ」の章）を同じ内容に合わせる。
- [ADR 0012](0012-update-adr-guard-to-v0.8.1.md) のステータスを、actionの版についてこの ADR に置き換えられたことを示す `採択→…は [ADR 0032](...)` の形にする。
- `adr-guard links --fix --include-committed` を実行し、`adr-guard links` と `adr-guard check-status` が終了コード0で終わる状態を保つ。

## 実装しないこと

- `--allow-links` で新しく許されるようになった変更（ADR の参照以外のリンクの付け外しやリンク先の変更）の一括の適用。必要になったときに個別に行う。
- 記録の保護の変更。記録にはこれまでどおり `--allow-links` が効かない。
- Claude Code の hook の変更。Claude Code の hook は全体の設定（`~/.claude/settings.json`）にあり、このリポジトリでは管理しない。
- 手元の adr-guard の更新の自動化。
- actionの指定方法の変更。これまでどおりバージョンのタグで指定する。

## テスト設計

- 手元の adr-guard（v0.8.2）で、次を確かめる。
  - 変更をステージして `.githooks/pre-commit` が終了コード0で終わる（各コミットで hook が通る）。
  - `adr-guard links` と `adr-guard check-status` が終了コード0で終わる。
  - コミットの後、`adr-guard check-range origin/main HEAD --allow-status --allow-links` が終了コード0で終わる。
- `.github/workflows/docs.yml` が YAML として読めることを確かめる。
- 変更のプルリクエストの CI で、`adr` ジョブが v0.8.2 のactionで実行され、成功することを確かめる。
  - ジョブのログで、`adr-guard-v0.8.2-x86_64-unknown-linux-gnu.tar.gz` のチェックサムが検証され、`check-range --allow-status --allow-links`、`links`、`check-status` が実行されていることを確かめる。

## トレードオフ

- `--allow-links` が許す範囲が広がり、コミット済みの ADR が参照する外部の文献のリンク先も、ADR を新しく作らずに変えられるようになる。
  リンク切れを直せる利点がある一方、根拠の参照先が後から変わりうる。リンクのテキストは変えられないので、何を参照していたかは残る。リンク先の変更はレビューで確かめる。
- 手元の adr-guard が v0.8.2 より古いと、pre-commit hook は ADR の参照以外のリンクの変更を拒否し、CI とふるまいが食い違う。README と CONTRIBUTING に必要なバージョンを書いて補う。

## 参考文献

- tett23/adr-guard の [ADR 0015](https://github.com/tett23/adr-guard/blob/main/docs/adr/0015-allow-link-changes.md)「`--allow-links` で、ADRの参照以外のリンクを付ける・外す・リンク先を変える変更も許可する」
- tett23/adr-guard の [v0.8.2 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.8.2)
