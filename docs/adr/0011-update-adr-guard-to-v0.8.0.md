# ADR 0011: adr-guard を v0.8.0 に上げ、ステータスの行の数と記録の保護も検査する

ステータス: 採択

## 文脈

このリポジトリは、コミット済みの ADR（`docs/adr/` と `docs/<モジュール>/adr/` の配下）の変更を [adr-guard](https://github.com/tett23/adr-guard) で拒否している。
検査は `.githooks/pre-commit` と、CI の `adr` ジョブで行う。
[ADR 0010](0010-update-adr-guard-to-v0.5.0.md) で、pre-commit hook を `adr-guard pre-commit --allow-status --allow-links` にし、`adr` ジョブのactionを `tett23/adr-guard@v0.5.0`（`allow-status: true`、`allow-links: true`）にした。

その後、tett23/adr-guard は v0.8.0 まで更新された。

- v0.6.0：どの深さの `docs/adr/` と `docs/<モジュール>/adr/` も保護する（tett23/adr-guard の [ADR 0011](https://github.com/tett23/adr-guard/blob/main/docs/adr/0011-nested-adr-directories.md)）。このリポジトリの ADR はすべて `docs/` の直下にあるため、保護の範囲は変わらない。
- v0.7.0：ADR は、行頭が `ステータス:` か `Status:` のステータスの行をちょうど1つ持たねばならない（tett23/adr-guard の [ADR 0012](https://github.com/tett23/adr-guard/blob/main/docs/adr/0012-status-line-and-status-adt.md)）。無い ADR と2つ以上ある ADR は、pre-commit hook と新しいサブコマンド `adr-guard check-status` で違反になる。actionは既定で `check-status` も実行する。
- v0.8.0：どの深さの `docs/` でも、`docs/audit/` と `docs/benchmarks/` の配下のコミット済みのファイルは、変更、削除、移動できない（tett23/adr-guard の [ADR 0013](https://github.com/tett23/adr-guard/blob/main/docs/adr/0013-protect-audit-and-benchmark-records.md)）。`--allow-status` と `--allow-links` は記録には効かない。

手元の adr-guard はすでに v0.8.0 に更新されている。
いまの作業ツリーで `adr-guard check-status` は終了コード0で終わる。すべての ADR が `ステータス:` の行をちょうど1つ持っており、ステータスの行の移行は要らない。
このリポジトリには `docs/audit/` も `docs/benchmarks/` もまだない。
計測の記録は `docs/ci-timings/` にある（[ADR 0009](0009-ci-speed.md)）が、名前が違うため v0.8.0 でも保護されない。

## 実装すること

- `.github/workflows/ci.yml` の `adr` ジョブのactionを `uses: tett23/adr-guard@v0.8.0` にする。
  入力 `allow-status: true` と `allow-links: true` はそのまま保つ。`check-status: false` は付けず、actionの既定のとおり `check-status` も実行する。
  checkout は `actions/checkout@v7` のまま、`fetch-depth: 0` と `persist-credentials: false` を保つ。
- `.githooks/pre-commit` は `exec adr-guard pre-commit --allow-status --allow-links` のまま保ち、コメントの ADR の参照にこの ADR を加える。
- `README.md` の「Git フックの有効化」の節に、v0.8.0 以降の adr-guard が要ること、ADR がステータスの行をちょうど1つ持つこと、`docs/audit/` と `docs/benchmarks/` のコミット済みの記録も変更できないことを書く。
  CI の節の表の `adr` ジョブの内容に、ステータスの行の検査を加える。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の開発環境の節、ADR の節、記録の置き場所の段落を同じ内容に合わせる。
- `CLAUDE.md` と `docs/glossary.md` の adr-guard に触れる記述を同じ内容に合わせる。
- `docs/specifications.md` の ADR の定めに、ステータスの行をちょうど1つ持つこと、`docs/audit/` と `docs/benchmarks/` の記録もコミット後は変更しないことを加える。
- [ADR 0010](0010-update-adr-guard-to-v0.5.0.md) のステータスを、actionの版とステータスの行の規則についてこの ADR に置き換えられたことを示す `採択→…は [ADR 0011](...)` の形にする。
- `adr-guard links --fix` を実行し、`adr-guard links` と `adr-guard check-status` が終了コード0で終わる状態を保つ。

## 実装しないこと

- `docs/ci-timings/` の記録の移動や名前の変更。コミット済みの記録を動かすことになり、[ADR 0009](0009-ci-speed.md) の記録の置き場所の決定も変わる。保護されないことは CONTRIBUTING に書き、これまでどおり約束とレビューで守る。
- ステータスの行の移行。違反の ADR が無いため不要である。
- Claude Code の hook の変更。Claude Code の hook は全体の設定（`~/.claude/settings.json`）にあり、このリポジトリでは管理しない。
- 手元の adr-guard の更新の自動化。
- actionの指定方法の変更。これまでどおりバージョンのタグで指定する。

## テスト設計

- 手元の adr-guard（v0.8.0）で、次を確かめる（コミットはしない）。
  - 変更をステージして `.githooks/pre-commit` が終了コード0で終わる。
  - `adr-guard links` と `adr-guard check-status` が終了コード0で終わる。
  - コミット済みの ADR の本文を変えると、pre-commit hook が拒否する。
- `.github/workflows/ci.yml` が YAML として読めることを確かめる。
- 変更のプルリクエストの CI で、`adr` ジョブが v0.8.0 のactionで実行され、成功することを確かめる。
  - ジョブのログで、`adr-guard-v0.8.0-x86_64-unknown-linux-gnu.tar.gz` のチェックサムが検証され、`check-range --allow-status --allow-links`、`links`、`check-status` が実行されていることを確かめる。

## トレードオフ

- 手元の adr-guard が v0.7.0 より古いと、pre-commit hook はステータスの行の数を検査せず、CI で初めて違反が分かる。README と CONTRIBUTING に必要なバージョンを書いて補う。
- ステータスの行が無い ADR や2つある ADR は、提案の段階でも pre-commit hook で止まる。ADR の書式が揃う代わりに、書きかけの ADR もステータスの行を持たねばならない。
- 記録の保護は `audit` と `benchmarks` の名前に固定されている。`docs/ci-timings/` のように別の名前で置いた記録は保護されないため、新しい種類の記録を置くときは、保護される名前を選ぶかどうかを考える必要がある。
